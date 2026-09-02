--[[ sim_admin_console — серверная консоль внутри админки (заказ 02.09)

    Проверяет контракт sv_grm_admin_console.lua v1.0:
      1) право server.console: без него пакет молча игнорируется;
      2) guard лимитит поток;
      3) санитайз: переводы строк вырезаются, длина режется;
      4) встроенные команды: status / get / set / bans / ac / history;
      5) raw-строка уходит в game.ConsoleCommand;
      6) эхо остальным носителям права; себе — ровно один пакет;
      7) журнал 60 записей; ошибка команды не роняет обработчик.

    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_admin_console.lua
----------------------------------------------------------------------]]
SERVER = true
local NOW = 1000
function CurTime() return NOW end
os.time = function() return 1700000000 end
function IsValid(v) return type(v) == "table" and v._valid ~= false end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isfunction(v) return type(v) == "function" end
function isnumber(v) return type(v) == "number" end
function string.Trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
function table.Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

local CV = { sv_cheats = { v = "0", def = "0" }, mp_timelimit = { v = "120", def = "120" } }
local function mkCvar(name)
    local c = CV[name]
    if not c then return nil end
    local out = { GetInt = function() return math.floor(tonumber(c.v) or 0) end,
        GetFloat = function() return tonumber(c.v) or 0 end,
        GetString = function() return c.v end, GetDefault = function() return c.def end,
        SetString = function(_, v) c.v = tostring(v) end }
    return out
end
GetConVar = mkCvar
CreateConVar = function(name, def)
    CV[name] = CV[name] or { v = tostring(def), def = tostring(def) }
    return mkCvar(name)
end

local CONSOLE = {}
game = { GetMap = function() return "rp_test" end, MaxPlayers = function() return 48 end,
    ConsoleCommand = function(c) CONSOLE[#CONSOLE + 1] = tostring(c) end }

local SENT = {}
net = {
    Receive = function(name, fn) net._rx = net._rx or {} net._rx[name] = fn end,
    Start = function(n) SENT[#SENT + 1] = { s = n } end,
    WriteString = function(v) SENT[#SENT].str = tostring(v) end,
    WriteTable = function(v) SENT[#SENT].tbl = v end,
    Send = function(t) local e = SENT[#SENT] e.to = e.to or {} local n = 0
        if istable(t) then for _ in pairs(t) do n = n + 1 end e.to[#e.to + 1] = n end
    end,
}
local RXLINE = ""
function net.ReadString() return RXLINE end

local ALL = {}
player = { GetAll = function() return ALL end }
local function mkPlayer(nick)
    local p = { _valid = true, nick = nick, sid = "76561199100000" .. #ALL }
    function p:Nick() return self.nick end
    function p:SteamID64() return self.sid end
    ALL[#ALL + 1] = p
    return p
end

local AUDIT = {}
GRM = { Audit = { Write = function(_, _, actor, tgt, det) AUDIT[#AUDIT + 1] = { actor = actor, det = det } end },
    Net = {}, Admin = { Net = { CONSOLE = "GRM_Admin_Console", CONSOLE_OUT = "GRM_Admin_ConsoleOut" } } }
GUARD_OK = true
GRM.Net.Guard = function() return GUARD_OK end
PERM = {}
function GRM.Admin.Can(ply, perm) return PERM[perm] and ply._admins ~= false and true or false end
AC_CALLS = {}
GRM.AntiCheat = { Version = "1.0.0", AdminCmd = function(_, line)
    AC_CALLS[#AC_CALLS + 1] = line
    if line == "list" then return "подозреваемых: 2" end
    if line == "boom" then error("сбой команды") end
    return "ac-заглушка: " .. tostring(line)
end }
GRM.ServerBan = {
    Bans = { ["7656119910000001"] = { reason = "читы", remaining = 600, paused = true } },
    Describe = function(rec) return tostring(rec.reason) end,
    GlobalList = function()
        return { { sid64 = "7656119910000001", name = "Banana", reason = "читы", hwid = "sha1:xyz" },
            { sid64 = "7656119910000002", name = "Alt", reason = "мошенничество", hwid = "" } }
    end,
}

dofile("lua/autorun/server/sv_grm_admin_console.lua")

local PASS, FAIL = 0, {}
local function t(name, cond, info)
    if cond then PASS = PASS + 1 else FAIL[#FAIL + 1] = name .. (info and (" · " .. tostring(info)) or "") end
end
local function run(ply, line)
    RXLINE = line
    net._rx["GRM_Admin_Console"](0, ply)
    return SENT[#SENT] and SENT[#SENT].tbl
end
local root = mkPlayer("Owner")
root._admins = true
PERM["server.console"] = true

-- 1) право
local pleb = mkPlayer("Pleb")
pleb._admins = false
local n0 = #SENT
run(pleb, "status")
t("без права — молчание", #SENT == n0)
PERM["server.console"] = nil
run(root, "status")
t("право отозвано — молчание", #SENT == n0)
PERM["server.console"] = true

-- 2) guard
GUARD_OK = false
n0 = #SENT
run(root, "status")
t("guard глушит", #SENT == n0)
GUARD_OK = true

-- 3) санитайз
local r = run(root, "get sv_cheats\r\nbadcmd")
t("переводы вырезаны", CONSOLE[#CONSOLE] == nil) -- встроенная get не идёт в движок
r = run(root, "mp_timelimit 60" .. string.rep("x", 400))
local sent = SENT[#SENT]
t("raw после усечения", sent.s == "GRM_Admin_ConsoleOut")
local executed = CONSOLE[#CONSOLE]
t("движку ушла урезанная строка", #executed <= 301, #executed)

-- 4) builtins
r = run(root, "status")
t("status: карта и аптайм", r.text:find("rp_test") and r.text:find("античит"), r.text)
r = run(root, "get sv_cheats")
t("get значение", r.text == "sv_cheats = 0 (дефолт 0)", r.text)
r = run(root, "get nosuch_cvar")
t("get отсутствующего", r.text:find("не найден") ~= nil, r.text)
r = run(root, "set sv_cheats 1")
t("set старый→новый", r.text == "sv_cheats: 0 → 1", r.text)
t("cvar реально изменён", CV.sv_cheats.v == "1")
r = run(root, "set new_grm_cvar 42")
t("set создаёт новый", r.text:find("new_grm_cvar: 0 → 42") ~= nil, r.text)
r = run(root, "bans")
t("bans: деморган+глобал", r.text:find("деморган ·") and r.text:find("читы")
    and r.text:find("глобал · 7656119910000001") and r.text:find("без железа"), r.text)
r = run(root, "ac list")
t("ac мост", r.text == "подозреваемых: 2" and AC_CALLS[#AC_CALLS] == "list")
r = run(root, "ac status")
t("ac status не соврёт без данных", r.text:find("ac-заглушка: status", 1, true) ~= nil, r.text)
r = run(root, "boom")
t("raw boom — не built-in", r.text:find("выполнено") ~= nil)

-- 5) история и журнал
r = run(root, "history")
t("history содержит строки", r.text:find("status") and r.text:find("set sv_cheats"), "…")
t("аудит пишет каждый ввод", #AUDIT >= 12, #AUDIT)
local log = GRM.Admin.ConsoleLog or {}
t("журнал не пуст", #log > 0)

-- 6) ошибка команды не роняет обработчик
r = run(root, "ac boom")
t("сбой AC обёрнут", r.text:find("ошибка") ~= nil, r.text)

-- 7) эхо коллегам
local peer = mkPlayer("CoOwner")
peer._admins = true
local before = #SENT
run(root, "status")
local packet = SENT[before + 1]
t("ответ + эхо коллеге", SENT[before + 1] and SENT[before + 2])
t("в payload есть автор и строка", packet.tbl.admin == "Owner" and packet.tbl.line == "status")
peer._admins = false
before = #SENT
local nobody = mkPlayer("Watcher")
nobody._admins = false
run(root, "status")
t("нет коллег — нет второго пакета", #SENT == before + 1)

-- 8) журнал ограничен 60
for i = 1, 80 do run(root, "status") end
t("журнал ≤ 60", #GRM.Admin.ConsoleLog <= 60, #GRM.Admin.ConsoleLog)

print(("sim_admin_console: PASS %d, FAIL %d"):format(PASS, #FAIL))
for _, f in ipairs(FAIL) do print("  ✗ " .. f) end
os.exit(#FAIL == 0 and 0 or 1)
