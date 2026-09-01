--[[--------------------------------------------------------------------
    sim_comp_terminal — рассинхрон прав терминала и ядра розыска.

    Баг: офицер OrdnungPolizei / Feldgendarmerie открывает терминал
    (T.CanEdit фолбэчит по названию фракции), жмёт «Снять с розыска»,
    клиент сразу пишет «снят», а W.Clear режет строгим W.CanEdit
    (AccessManager / access.json) → «Нет прав». Суперадмин проходит.

    Фикс v1.0.1: после T.CanEdit ядро зовётся с trusted; юрисдикция
    остаётся; клиенты ходят через GRM_CompTerminal_Send без тоста.

    Запуск из корня репо:
      ./.luabuild/lj/src/luajit tools/luatest/sim_comp_terminal.lua
----------------------------------------------------------------------]]

local function read(p)
    local f = assert(io.open(p, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

local files = {}
_G.CLIENT = false
_G.SERVER = true
function _G.AddCSLuaFile() end
function _G.include() end
function _G.ErrorNoHalt(s) io.write("[ErrorNoHalt] " .. tostring(s)) end
function _G.IsValid(v) return type(v) == "table" and v.__valid == true end
function _G.isfunction(v) return type(v) == "function" end
function _G.istable(v) return type(v) == "table" end
function _G.isstring(v) return type(v) == "string" end
_G.math.Clamp = function(v, a, b)
    if v < a then return a elseif v > b then return b end
    return v
end
_G.string.Trim = function(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
_G.string.Explode = function(sep, s)
    local o = {}
    for m in tostring(s):gmatch("[^" .. sep .. "]+") do o[#o + 1] = m end
    return o
end
_G.os = os
_G.table = table
_G.hook = { Add = function() end, Run = function() end }
_G.timer = { Simple = function() end }
_G.concommand = { Add = function() end }
_G.net = setmetatable({}, { __index = function() return function() end end })
_G.util = { AddNetworkString = function() end }

local function esc(s)
    return (s:gsub('[%c"\\]', function(c)
        return ({ ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n' })[c]
            or string.format('\\u%04x', c:byte())
    end))
end
local function enc(v)
    local t = type(v)
    if t == "number" then return (v % 1 == 0) and string.format("%d", v) or tostring(v) end
    if t == "string" then return '"' .. esc(v) .. '"' end
    if t == "boolean" then return tostring(v) end
    if t == "table" then
        if #v > 0 or next(v) == nil then
            local o = {}
            for _, x in ipairs(v) do o[#o + 1] = enc(x) end
            return "[" .. table.concat(o, ",") .. "]"
        end
        local o = {}
        for k, x in pairs(v) do o[#o + 1] = '"' .. esc(tostring(k)) .. '":' .. enc(x) end
        return "{" .. table.concat(o, ",") .. "}"
    end
    return "null"
end
local pos, str
local function skip()
    while true do
        local c = str:sub(pos, pos)
        if c == " " or c == "\n" or c == "\t" or c == "\r" then pos = pos + 1 else break end
    end
end
local function val()
    skip()
    local c = str:sub(pos, pos)
    if c == "{" then
        pos = pos + 1
        local o = {}
        skip()
        if str:sub(pos, pos) == "}" then pos = pos + 1 return o end
        while true do
            skip()
            local k = val()
            skip()
            pos = pos + 1
            local v = val()
            o[k] = v
            skip()
            local d = str:sub(pos, pos)
            pos = pos + 1
            if d == "}" then return o end
        end
    elseif c == "[" then
        pos = pos + 1
        local o = {}
        skip()
        if str:sub(pos, pos) == "]" then pos = pos + 1 return o end
        while true do
            o[#o + 1] = val()
            skip()
            local d = str:sub(pos, pos)
            pos = pos + 1
            if d == "]" then return o end
        end
    elseif c == '"' then
        pos = pos + 1
        local s = ""
        while true do
            local ch = str:sub(pos, pos)
            if ch == "\\" then
                local n = str:sub(pos + 1, pos + 1)
                s = s .. ({ ["n"] = "\n", ['"'] = '"', ["\\"] = "\\" })[n] or ""
                pos = pos + 2
            elseif ch == '"' then
                pos = pos + 1
                return s
            else
                s = s .. ch
                pos = pos + 1
            end
        end
    else
        local s = pos
        while str:sub(pos, pos):match("[%w%.%-+eE]") do pos = pos + 1 end
        local sub = str:sub(s, pos - 1)
        if sub == "true" then return true
        elseif sub == "false" then return false
        elseif sub == "null" then return nil end
        return tonumber(sub)
    end
end
_G.util.TableToJSON = function(t) return enc(t) end
_G.util.JSONToTable = function(s) str = s pos = 1 local ok, r = pcall(val) return ok and r or nil end
_G.file = {
    Exists = function(p) return files[p] ~= nil end,
    Read = function(p) return files[p] end,
    Write = function(p, c) files[p] = c end,
    IsDir = function() return true end,
    CreateDir = function() end,
}
_G.table.Count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
_G.table.Copy = function(t)
    local o = {}
    for k, v in pairs(t) do o[k] = type(v) == "table" and _G.table.Copy(v) or v end
    return o
end
_G.Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
_G.color_white = _G.Color(255, 255, 255)
_G.GRM = { Identity = { CharacterKey = function(p) return p.key end } }

local PLAYERS = {}
local function mkPlayer(key, nick, faction, super)
    local nw = { GRM_Faction = faction or "", GRM_Role = "Сотрудник", GRM_Department = "" }
    local nwi, nwb = {}, {}
    local p = {
        __valid = true, key = key,
        IsPlayer = function() return true end,
        IsSuperAdmin = function() return super == true end,
        IsAdmin = function() return super == true end,
        Nick = function() return nick end,
        SteamID = function() return "STEAM_0:0:1" end,
        SteamID64 = function() return (key:gsub(":char%d", "")) end,
        GetNWString = function(_, k, d) return nw[k] or d or "" end,
        SetNWString = function(_, k, v) nw[k] = v end,
        SetNWBool = function(_, k, v) nwb[k] = v end,
        SetNWInt = function(_, k, v) nwi[k] = v end,
        SetNW2Int = function(_, k, v) nwi[k] = v end,
        GetNWInt = function(_, k, d) return nwi[k] or d or 0 end,
        ChatPrint = function() end,
    }
    PLAYERS[#PLAYERS + 1] = p
    return p
end
_G.player = { GetAll = function() return PLAYERS end }

-- Ядро GRM (sh_00_grm_ui + sh_01_grm_core) — как на сервере, до модулей.
dofile("tools/luatest/lib_grm_core.lua")()
dofile("lua/autorun/sh_grm_wanted_config.lua")
dofile("lua/autorun/server/sv_grm_wanted.lua")
dofile("lua/autorun/server/sv_grm_comp_terminal.lua")

local W = GRM.Wanted
local T = GRM.CompTerminal

-- Как на живом сервере без /wanted_access: AccessManager режет всех,
-- кроме суперадмина. Терминал пускает офицера по фолбэку фракции.
W.CanView = function(p)
    if not IsValid(p) then return false end
    return p:IsSuperAdmin()
end
W.CanEdit = function(p)
    if not IsValid(p) then return false end
    return p:IsSuperAdmin()
end

local fails = 0
local function check(name, cond, extra)
    if cond then
        print("  OK   " .. name)
    else
        fails = fails + 1
        print("  FAIL " .. name .. "   " .. tostring(extra or ""))
    end
end
local function has(src, needle) return src:find(needle, 1, true) ~= nil end

local cop    = mkPlayer("76561198000000010:char1", "Kurt Weber",  "OrdnungPolizei")
local gend   = mkPlayer("76561198000000011:char1", "Otto Hahn",   "Feldgendarmerie")
local civ    = mkPlayer("76561198000000020:char1", "Anna Klein",  "Civilian")
local sold   = mkPlayer("76561198000000021:char1", "Erich Braun", "Wehrmacht")
local root   = mkPlayer("76561198000000099:char1", "Root",        "Admin", true)
local wehr   = mkPlayer("76561198000000022:char1", "Hans Soldat", "Wehrmacht")

print("\n=== ИСТОЧНИКИ: контракт v1.0.1 ===")
local svT   = read("lua/autorun/server/sv_grm_comp_terminal.lua")
local svW   = read("lua/autorun/server/sv_grm_wanted.lua")
local clP   = read("lua/entities/grm_comp_police/cl_init.lua")
local clM   = read("lua/entities/grm_comp_military_police/cl_init.lua")
local clT   = read("lua/autorun/client/cl_grm_comp_terminal.lua")

check("терминал v1.1.0 (фото к делу)", has(svT, 'T.Version = "1.1.0'), T.Version)
check("ядро: trusted в AddCustomCharge", has(svW, "data.trusted==true") or has(svW, "data.trusted == true"))
check("ядро: trusted в SetLevel", has(svW, "function W.SetLevel(issuer,targetSid,level,note,trusted)"))
check("ядро: Clear пробрасывает trusted", has(svW, "function W.Clear(i,s,n,trusted)"))
check("wanted_add ставит data.trusted", has(svT, "data.trusted = true"))
check("wanted_clear зовёт Clear(..., true)", has(svT, 'W.Clear(ply, key, text ~= "" and text or "Снят с розыска в терминале", true)'))
check("legacy add передаёт trusted", has(svT, "trusted = true,"))
check("legacy clear зовёт Clear(..., true)", has(svT, 'W.Clear(ply, key, reason ~= "" and reason or "Снят с розыска", true)'))
check("клиент полиции: wanted_add через Send", has(clP, 'GRM_CompTerminal_Send("wanted_add"'))
check("клиент полиции: wanted_clear через Send", has(clP, 'GRM_CompTerminal_Send("wanted_clear"'))
check("клиент жандармерии: wanted_add через Send", has(clM, 'GRM_CompTerminal_Send("wanted_add"'))
check("клиент жандармерии: wanted_clear через Send", has(clM, 'GRM_CompTerminal_Send("wanted_clear"'))
check("клиент полиции не шлёт легаси add", not has(clP, 'net.Start("GRM_CompPolice_WantedAct")'))
check("клиент жандармерии не шлёт легаси add", not has(clM, 'net.Start("GRM_CompMilPolice_Act")'))
check("нет оптимистичного тоста полиции «снят»", not has(clP, 'Гражданин снят с розыска.'))
check("нет оптимистичного тоста жандармерии «снят»", not has(clM, 'Военнослужащий снят с розыска.'))
check("нет оптимистичного тоста полиции «передана»", not has(clP, "Ориентировка передана патрульным экипажам!"))
check("нет оптимистичного тоста жандармерии «передана»", not has(clM, "Ориентировка передана патрулям комендатуры!"))
check("общий Send существует", has(clT, "function GRM_CompTerminal_Send"))
check("Result рисует тост по ответу сервера", has(clT, "GRM_CompTerminal_Result") and has(clT, "notification.AddLegacy"))

print("\n=== ТЕСТ 1: терминал пускает офицера, ядро без trusted режет ===")
check("полицейский открывает гражданский терминал", T.CanManage(cop, "civil") == true)
check("полицейский T.CanEdit civil", T.CanEdit(cop, "civil") == true)
check("жандарм открывает военный терминал", T.CanManage(gend, "military") == true)
check("жандарм T.CanEdit military", T.CanEdit(gend, "military") == true)
check("гражданский терминал не откроет", T.CanManage(civ, "civil") == false)
check("вермахт военный терминал не откроет (нет жандарм-паттерна)", T.CanManage(wehr, "military") == false)
check("W.CanEdit офицера ложь (нет access.json)", W.CanEdit(cop) == false)
check("W.CanEdit жандарма ложь", W.CanEdit(gend) == false)
check("W.CanEdit суперадмина истина", W.CanEdit(root) == true)

print("\n=== ТЕСТ 2: снять без trusted — «Нет прав» (старый баг) ===")
local okAdd = W.AddCustomCharge(root, civ.key, {
    code = "УК-1", title = "Кража", level = 2, jurisdiction = "civil",
})
check("суперадмин завёл гражданское дело", okAdd == true)
check("уровень 2", W.GetLevel(civ.key) == 2, W.GetLevel(civ.key))

local okNo, errNo = W.Clear(cop, civ.key, "задержан")
check("офицер без trusted не снимает", okNo == false, errNo)
check("ошибка именно «Нет прав»", errNo == "Нет прав", errNo)
check("запись на месте", W.GetLevel(civ.key) == 2, W.GetLevel(civ.key))

print("\n=== ТЕСТ 3: trusted после T.CanEdit — офицер снимает ===")
local okYes, errYes = W.Clear(cop, civ.key, "задержан в терминале", true)
check("офицер с trusted снял", okYes == true, errYes)
check("уровень 0", W.GetLevel(civ.key) == 0, W.GetLevel(civ.key))

print("\n=== ТЕСТ 4: trusted add — офицер объявляет ===")
local okNew, errNew = W.AddCustomCharge(cop, civ.key, {
    code = "УК-ПР", title = "Хулиганство", level = 3,
    jurisdiction = "civil", manual = true, trusted = true,
})
check("офицер с trusted объявил", okNew == true, errNew)
check("уровень 3", W.GetLevel(civ.key) == 3, W.GetLevel(civ.key))

local okBare, errBare = W.AddCustomCharge(cop, civ.key, {
    code = "УК-ПР", title = "Ещё раз", level = 1, jurisdiction = "civil",
})
check("без trusted add режется", okBare == false and errBare == "Нет прав", errBare)

print("\n=== ТЕСТ 5: trusted не обходит юрисдикцию ===")
local okMil = W.AddCustomCharge(root, sold.key, {
    code = "ВУ-1", title = "Дезертирство", level = 4, jurisdiction = "military",
})
check("военное дело заведено", okMil == true)
local okCross, errCross = W.Clear(cop, sold.key, "не наше", true)
check("полиция не снимет военное даже с trusted", okCross == false, errCross)
check("текст про Feldgendarmerie", type(errCross) == "string" and errCross:find("Feldgendarmerie", 1, true) ~= nil, errCross)
check("военное дело на месте", W.GetLevel(sold.key) == 4, W.GetLevel(sold.key))

local okGend, errGend = W.Clear(gend, sold.key, "доставлен", true)
check("жандарм с trusted снял военное", okGend == true, errGend)
check("военный уровень 0", W.GetLevel(sold.key) == 0, W.GetLevel(sold.key))

local okCivCross, errCivCross = W.AddCustomCharge(gend, civ.key, {
    code = "ВУ-ПР", title = "Не то ведомство", level = 2,
    jurisdiction = "civil", trusted = true,
})
check("жандарм не вменит гражданскую даже с trusted", okCivCross == false, errCivCross)
check("текст про Полицию Порядка", type(errCivCross) == "string" and errCivCross:find("Полиция", 1, true) ~= nil, errCivCross)

print("\n=== ТЕСТ 6: суперадмин по-прежнему без trusted ===")
local okRoot = W.Clear(root, civ.key, "оправдан")
check("суперадмин снял без trusted", okRoot == true)
check("гражданский уровень 0", W.GetLevel(civ.key) == 0, W.GetLevel(civ.key))

print("\n=== ТЕСТ 7: чужой не снимет даже с trusted (юрисдикция) ===")
-- гражданский игрок: CanUseJurisdiction(civil) истинна (своя фракция civil),
-- поэтому trusted НЕ должен быть доступен с клиента — только после T.CanEdit.
-- Здесь проверяем, что голый вызов с trusted у гражданского пройдёт
-- юрисдикцию civil. Это серверный флаг: клиент его выставить не может.
local okCivTrust, errCivTrust = W.Clear(civ, civ.key, "сам себя", true)
check("гражданский с trusted технически пройдёт ядро (флаг серверный)", okCivTrust == true, errCivTrust)
check("гражданский без терминала T.CanEdit ложь", T.CanEdit(civ, "civil") == false)

print("")
if fails == 0 then
    print("ВСЕ ТЕСТЫ ПРОЙДЕНЫ (comp terminal v1.0.1)")
else
    print("ПРОВАЛОВ: " .. fails)
end
print(("COMP_TERMINAL failures=%d"):format(fails))
os.exit(fails == 0 and 0 or 1)
