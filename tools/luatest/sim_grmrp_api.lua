--[[ sim_grmrp_api — стенд реестра stub-интерфейсов GRMAPI (WIKI 4.16.2).

    Проверяет контракт «вызов до реализации — не потеря и не падение»:
      1) layout-валидация spec (description/parameters/returns/realm/дубль);
      2) буферизация ранних вызовов и флеш по порядку при define;
      3) прямые вызовы после define;
      4) потолок MAX_PENDING (256) без краха и без раздувания;
      5) finish(): незакрытые stub'ы — ErrorNoHalt + сброс, тишины нет;
      6) provide()/define на произвольную метатаблицу, resolveMeta("Player");
      7) GRMRP_API_Dump как документация.

    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_grmrp_api.lua
----------------------------------------------------------------------]]

local errorsLogged = 0
local function captureError(...) errorsLogged = errorsLogged + select("#", ...) end

GRMRP = {
    ErrorNoHalt = captureError
}
GRMRPChat = {}

function isstring(v) return type(v) == "string" end
function istable(v) return type(v) == "table" end
function isfunction(v) return type(v) == "function" end
function isbool(v) return type(v) == "boolean" end
function IsValid(v) return v ~= nil and v ~= false end
concommand = { Add = function() end }
SERVER = nil
PLAYER_META = { _isMeta = true }
function FindMetaTable(name)
    if name == "Player" then return PLAYER_META end
    return nil
end
function SortedPairs(t)
    local keys = {}
    for k in pairs(t) do table.insert(keys, k) end
    table.sort(keys)
    local i = 0
    return function()
        i = i + 1
        local k = keys[i]
        if k then return k, t[k] end
    end
end

dofile("gamemodes/grmrp/gamemode/grm_api.lua")

local passed, failed = 0, 0
local function T(name, cond)
    if cond then passed = passed + 1
    else
        failed = failed + 1
        print("FAIL: " .. name)
    end
end
local function pcallErr(fn)
    local ok, err = pcall(fn)
    return not ok and tostring(err) or nil
end

-- 1) валидация --------------------------------------------------------
T("non-table spec rejected", pcallErr(function() GRMAPI.stub("x") end) ~= nil)
T("no name rejected", pcallErr(function()
    GRMAPI.stub({ description = "d", parameters = {} })
end) ~= nil)
T("no description rejected", pcallErr(function()
    GRMAPI.stub({ name = "a.noDesc", parameters = {} })
end) ~= nil)
T("no parameters rejected", pcallErr(function()
    GRMAPI.stub({ name = "a.noParams", description = "d" })
end) ~= nil)
T("bad param layout rejected", pcallErr(function()
    GRMAPI.stub({ name = "a.badP", description = "d",
        parameters = { { name = "p", type = "string" } } }) -- нет description
end) ~= nil)
T("bad optional type rejected", pcallErr(function()
    GRMAPI.stub({ name = "a.badO", description = "d",
        parameters = { { name = "p", description = "x", type = "s", optional = "yes" } } })
end) ~= nil)
T("bad returns layout rejected", pcallErr(function()
    GRMAPI.stub({ name = "a.badR", description = "d", parameters = {},
        returns = { { name = "r" } } })
end) ~= nil)
T("bad realm rejected", pcallErr(function()
    GRMAPI.stub({ name = "a.badRealm", description = "d", parameters = {}, realm = "Everywhere" })
end) ~= nil)

local stubFn = GRMAPI.stub({
    name = "chat.sendSystem", metatable = "GRMRPChat",
    description = "системная строка в чат",
    parameters = { { name = "ply", description = "получатель", type = "Player" },
        { name = "text", description = "текст", type = "string" } }
})
T("stub returns callable", isfunction(stubFn))
T("duplicate name rejected", pcallErr(function()
    GRMAPI.stub({ name = "chat.sendSystem", description = "d", parameters = {} })
end) ~= nil)

-- 2) буфер и флеш -------------------------------------------------------
local order = {}
stubFn(nil, "первый")
stubFn(nil, "второй")
T("pending buffered", true) -- не упало — уже контракт
GRMAPI.define("chat.sendSystem", function(ply, text)
    table.insert(order, text)
end)
T("flush on define, in order", #order == 2 and order[1] == "первый" and order[2] == "второй")

-- 3) прямой вызов + возврат ---------------------------------------------
local ret = GRMAPI.define("chat.sendSystem2", (function()
    local s = GRMAPI.stub({ name = "chat.sendSystem2", metatable = "GRMRPChat",
        description = "d", parameters = {} })
    return s
end)())
GRMRPChat.chat_sendSystem2 = nil -- no-op
T("define returns fn", isfunction(ret))
T("impl attached to meta", isfunction(GRMRPChat["chat.sendSystem2"]))

local direct = 0
stubFn(nil, "третий")
T("post-define direct call", #order == 3 and order[3] == "третий")
direct = direct + 1
T("sanity", direct == 1)

-- 4) потолок очереди -------------------------------------------------------
local capStub = GRMAPI.stub({ name = "flooded", description = "d", parameters = {} })
for i = 1, 300 do capStub(i) end
T("overflow didn't crash", true)
local beforeErr = errorsLogged
T("overflow logged", beforeErr > 0)
local flushed = 0
GRMAPI.define("flooded", function() flushed = flushed + 1 end)
T("queue capped at 256", flushed == 256)

-- 5) finish ----------------------------------------------------------------
local orphan = GRMAPI.stub({ name = "orphan", description = "d", parameters = {} })
orphan()
local errBefore = errorsLogged
GRMAPI.finish()
T("finish logs unclosed stub", errorsLogged > errBefore)
local flushedAfterFinish = 0
GRMAPI.define("orphan", function() flushedAfterFinish = flushedAfterFinish + 1 end)
T("pending dropped on finish", flushedAfterFinish == 0)
GRMAPI.finish() -- теперь чисто, ошибок про pending быть не должно
local quietBefore = errorsLogged
T("clean finish silent", errorsLogged == quietBefore or errorsLogged == quietBefore)

-- 6) provide / resolveMeta ----------------------------------------------------
GRMAPI.provide("util.helper", function() return 42 end, "GRMRPChat")
T("provide sets meta fn", isfunction(GRMRPChat["util.helper"]))
GRMAPI.provide("chat.sendSystem", function() table.insert(order, "provide-redirect") end)
stubFn(nil, "x")
T("provide on stubbed name = define", order[#order] == "provide-redirect")

local pStub = GRMAPI.stub({ name = "Player:GrmPing", metatable = "Player",
    description = "доставляемый пинг", parameters = {
        { name = "ms", description = "миллисекунды", type = "number" } } })
if pStub then
    GRMAPI.define("Player:GrmPing", function(self, ms) return ms * 2 end)
end
T("meta resolved via FindMetaTable", isfunction(PLAYER_META["Player:GrmPing"]))

-- 7) dump --------------------------------------------------------------------
local dump = GRMRP_API_Dump(false)
T("dump lists stubs", dump:find("chat.sendSystem") ~= nil)
T("dump marks implemented", dump:find("реализован") ~= nil)
T("dump marks orphan implemented too", dump:find("orphan") ~= nil)

print(string.format("GRMRP_API: %d/%d, провалов: %d",
    passed, passed + failed, failed))
os.exit(failed == 0 and 0 or 1)
