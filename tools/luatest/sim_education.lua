-- ======================================================================
-- sim_education — рабочее место учреждения образования.
--
-- Проверяем то, что переделано по замечаниям к выдаче дипломов:
--   1) реестр персонажей включает ОФЛАЙН (паспорта, составы фракций),
--      а не только player.GetAll();
--   2) диплом выписывается офлайн-персонажу и получает ФИО из паспорта,
--      а не сырой ключ 7656…:char1;
--   3) счёт тоже выставляется офлайн-персонажу с человеческим именем;
--   4) права: без canDiploma выписать нельзя, суперадмин может всегда;
--   5) снимок рабочего места отдаёт реестр своего учреждения, а
--      суперадмину — весь;
--   6) действия рабочего места (issue/revoke/check) работают через
--      GRM.Education и уважают права.
--
-- Запуск: luajit tools/luatest/sim_education.lua
-- ======================================================================
local files = {}
_G.CLIENT = false _G.SERVER = true
function _G.AddCSLuaFile() end
function _G.include() end
function _G.ErrorNoHalt(s) io.write("[ErrorNoHalt] " .. tostring(s)) end
function _G.IsValid(v) return type(v) == "table" and v.__valid == true end
function _G.isfunction(v) return type(v) == "function" end
function _G.istable(v) return type(v) == "table" end
function _G.isstring(v) return type(v) == "string" end
_G.math.Clamp = function(v, a, b) if v < a then return a elseif v > b then return b end return v end
_G.string.Trim = function(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
_G.string.Comma = function(v)
    local s = tostring(math.floor(tonumber(v) or 0))
    local out = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
    return (out:gsub("^%s+", ""))
end
_G.string.Explode = function(sep, s)
    local o = {} for m in tostring(s):gmatch("[^" .. sep .. "]+") do o[#o + 1] = m end return o
end
_G.CurTime = function() return os.clock() * 1000 end
_G.SortedPairs = function(t) return pairs(t) end
_G.SetGlobalDouble = function() end
_G.Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
_G.color_white = _G.Color(255, 255, 255)

-- JSON
local function esc(s) return (s:gsub('[%c"\\]', function(c)
    return ({ ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n' })[c] or string.format('\\u%04x', c:byte())
end)) end
local function enc(v)
    local t = type(v)
    if t == "number" then return (v % 1 == 0) and string.format("%d", v) or tostring(v) end
    if t == "string" then return '"' .. esc(v) .. '"' end
    if t == "boolean" then return tostring(v) end
    if t == "table" then
        if #v > 0 or next(v) == nil then
            local o = {} for _, x in ipairs(v) do o[#o + 1] = enc(x) end return "[" .. table.concat(o, ",") .. "]"
        end
        local o = {} for k, x in pairs(v) do o[#o + 1] = '"' .. esc(tostring(k)) .. '":' .. enc(x) end
        return "{" .. table.concat(o, ",") .. "}"
    end
    return "null"
end
local pos, str
local function skip() while true do local c = str:sub(pos, pos)
    if c == " " or c == "\n" or c == "\t" or c == "\r" then pos = pos + 1 else break end end end
local function val()
    skip() local c = str:sub(pos, pos)
    if c == "{" then pos = pos + 1 local o = {} skip()
        if str:sub(pos, pos) == "}" then pos = pos + 1 return o end
        while true do skip() local k = val() skip() pos = pos + 1 local v = val() o[k] = v skip()
            local d = str:sub(pos, pos) pos = pos + 1 if d == "}" then return o end end
    elseif c == "[" then pos = pos + 1 local o = {} skip()
        if str:sub(pos, pos) == "]" then pos = pos + 1 return o end
        while true do o[#o + 1] = val() skip() local d = str:sub(pos, pos) pos = pos + 1
            if d == "]" then return o end end
    elseif c == '"' then pos = pos + 1 local s = "" while true do local ch = str:sub(pos, pos)
        if ch == '\\' then local n = str:sub(pos + 1, pos + 1)
            s = s .. (({ ['n'] = '\n', ['"'] = '"', ['\\'] = '\\' })[n] or "") pos = pos + 2
        elseif ch == '"' then pos = pos + 1 return s else s = s .. ch pos = pos + 1 end end
    else local s = pos while str:sub(pos, pos):match("[%w%.%-%+eE]") do pos = pos + 1 end
        local sub = str:sub(s, pos - 1)
        if sub == "true" then return true elseif sub == "false" then return false
        elseif sub == "null" then return nil end
        return tonumber(sub) end
end
_G.util = {
    AddNetworkString = function() end,
    TableToJSON = function(t) return enc(t) end,
    JSONToTable = function(s) str = s pos = 1 local ok, r = pcall(val) return ok and r or nil end,
}
_G.file = {
    Exists = function(p) return files[p] ~= nil end,
    Read = function(p) return files[p] end,
    Write = function(p, c) files[p] = c end,
    IsDir = function() return true end,
    CreateDir = function() end,
}
_G.table.Count = function(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
_G.table.Copy = function(t) local o = {}
    for k, v in pairs(t) do o[k] = type(v) == "table" and _G.table.Copy(v) or v end return o end
_G.table.HasValue = function(t, v) for _, x in pairs(t) do if x == v then return true end end return false end

local hooks = {}
_G.hook = {
    Add = function(ev, name, fn) hooks[ev] = hooks[ev] or {} hooks[ev][name] = fn end,
    Remove = function(ev, name) if hooks[ev] then hooks[ev][name] = nil end end,
    Run = function(ev, ...) for _, fn in pairs(hooks[ev] or {}) do fn(...) end end,
    Call = function(ev, _, ...) return _G.hook.Run(ev, ...) end,
}
_G.timer = { Simple = function(_, fn) if fn then fn() end end }
_G.concommand = { Add = function() end }

local netLog = {}
_G.net = setmetatable({
    Start = function(n) netLog[#netLog + 1] = n end,
    Send = function() end,
    Broadcast = function() end,
    Receive = function(name, fn) _G.net["_rx_" .. name] = fn end,
    AddNetworkString = function() end,
}, { __index = function() return function() end end })

-- ── игроки и персонажи ───────────────────────────────────────────────
local PLAYERS = {}
local function mkPlayer(key, nick, faction, super, rpName)
    local nw = { GRM_Faction = faction or "", GRM_RPName = rpName or "" }
    local p = {
        __valid = true, key = key,
        IsPlayer = function() return true end,
        IsSuperAdmin = function() return super == true end,
        IsAdmin = function() return super == true end,
        Nick = function() return nick end,
        SteamID = function() return "STEAM_0:0:1" end,
        SteamID64 = function() return (key:gsub(":char%d", "")) end,
        GetNWString = function(_, k, d) local v = nw[k] if v == nil or v == "" then return d or "" end return v end,
        SetNWString = function(_, k, v) nw[k] = v end,
        GetNWBool = function(_, _, d) return d or false end,
        SetNWBool = function() end,
        GetNWInt = function(_, _, d) return d or 0 end,
        SetNWInt = function() end,
        SetNW2Int = function() end,
        ChatPrint = function() end,
        PrintMessage = function() end,
        GetPos = function() return { DistToSqr = function() return 0 end } end,
    }
    PLAYERS[#PLAYERS + 1] = p
    return p
end
_G.player = { GetAll = function() return PLAYERS end, GetBySteamID = function() end, GetBySteamID64 = function() end }

_G.GRM = { Identity = { CharacterKey = function(p) return p.key end } }
_G.GRM.Notify = function() end
_G.GRM.FormatMoney = function(v) return _G.string.Comma(v) .. " GRM" end

-- экономика (минимум для счетов)
local CASH, BANK, STATE, FBUD = {}, {}, 0, {}
_G.GRM.GetBalance = function(p) return CASH[p.key] or 0 end
_G.GRM.HasMoney   = function(p, n) return (CASH[p.key] or 0) >= n end
_G.GRM.TakeMoney  = function(p, n)
    if (CASH[p.key] or 0) < n then return false end CASH[p.key] = CASH[p.key] - n return true end
_G.GRM.GiveMoney  = function(p, n) CASH[p.key] = (CASH[p.key] or 0) + n return true end
_G.GRM.FactionBudgetAdd = function(n, d) FBUD[n] = (FBUD[n] or 0) + d return FBUD[n] end
_G.GRM.FactionBudgetGet = function(n) return FBUD[n] or 0 end
_G.GRM.Economy = {
    BankBalance = function(p) return BANK[p.key] or 0 end,
    BankTake = function(p, n)
        if (BANK[p.key] or 0) < n then return false, "funds" end BANK[p.key] = BANK[p.key] - n return true end,
    BankGive = function(p, n) BANK[p.key] = (BANK[p.key] or 0) + n return true end,
    StateAdd = function(d) STATE = STATE + d return STATE end,
}

-- фракции: университет с доступом, клиника — без
_G.Factions = {
    ["Университет"] = {
        Leader = "76561198000000031:char1", LeaderRoleName = "Ректор",
        Members = {
            ["76561198000000031:char1"] = { Role = "Ректор" },
            ["76561198000000032:char1"] = { Role = "Преподаватель" },
            -- курсант, которого нет онлайн и нет в паспортах
            ["76561198000000099:char2"] = { Role = "Курсант" },
        },
    },
    ["Городская клиника"] = {
        Leader = "76561198000000041:char1", LeaderRoleName = "Лидер",
        Members = { ["76561198000000041:char1"] = { Role = "Лидер" } },
    },
}
_G.FactionsAPI = { Save = function() end }

-- реестр документов: два ОФЛАЙН персонажа с паспортами
_G.GRM.Documents = {
    Registry = {
        passports = {
            ["76561198000000077:char1"] = {
                fullName = "Иоганн Мюллер", steamID64 = "76561198000000077", status = "active",
            },
            ["76561198000000088:char3"] = {
                fullName = "Клара Вебер", steamID64 = "76561198000000088", status = "active",
            },
        },
    },
}

-- Ядро грузится первым и на живом сервере (sh_01_grm_core.lua), и здесь:
-- модули ниже берут из него канон GRM.CharKey (§5.2.6, одна реализация).
assert(loadfile("lua/autorun/sh_01_grm_core.lua"))()
dofile("lua/autorun/sh_grm_services.lua")
dofile("lua/autorun/sh_grm_diplomas.lua")
dofile("lua/autorun/sh_grm_education.lua")

local S, D, EDU = GRM.Services, GRM.Diplomas, GRM.Education

local fails, total = 0, 0
local function check(name, cond, extra)
    total = total + 1
    if cond then print("  OK   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "   " .. tostring(extra or "")) end
end

-- участники
local rector  = mkPlayer("76561198000000031:char1", "Rector",  "Университет", false, "Отто Крамер")
local teacher = mkPlayer("76561198000000032:char1", "Teacher", "Университет", false)
local medic   = mkPlayer("76561198000000041:char1", "Medic",   "Городская клиника")
local admin   = mkPlayer("76561198000000001:char1", "Admin",   "", true)

S.SetAccess("Университет", {
    canService = true, canInvoice = true, canDiploma = true,
    institution = "Государственный университет Гроннера", maxInvoice = 50000,
})
S.SetAccess("Городская клиника", { canService = true, canInvoice = true, canDiploma = false })

-- ======================================================================
print("\n=== ТЕСТ 1: реестр персонажей видит офлайн ===")
local reg = S.CharacterRegistry()
local byKey = {}
for _, r in ipairs(reg) do byKey[r.key] = r end

check("реестр не пуст", #reg > 0, #reg)
check("онлайн-игрок есть в реестре", byKey["76561198000000031:char1"] ~= nil)
check("офлайн-персонаж из паспорта есть", byKey["76561198000000077:char1"] ~= nil)
check("второй офлайн-персонаж есть", byKey["76561198000000088:char3"] ~= nil)
check("курсант из состава фракции есть", byKey["76561198000000099:char2"] ~= nil)
check("у офлайн-персонажа ФИО из паспорта",
    byKey["76561198000000077:char1"] and byKey["76561198000000077:char1"].name == "Иоганн Мюллер",
    byKey["76561198000000077:char1"] and byKey["76561198000000077:char1"].name)
check("онлайн помечен флагом online",
    byKey["76561198000000031:char1"] and byKey["76561198000000031:char1"].online == true)
check("офлайн не помечен online",
    byKey["76561198000000077:char1"] and byKey["76561198000000077:char1"].online ~= true)
check("фракция подтянута к участнику",
    byKey["76561198000000099:char2"] and byKey["76561198000000099:char2"].faction == "Университет",
    byKey["76561198000000099:char2"] and byKey["76561198000000099:char2"].faction)
check("RP-имя важнее ника для онлайн",
    byKey["76561198000000031:char1"] and byKey["76561198000000031:char1"].name == "Отто Крамер",
    byKey["76561198000000031:char1"] and byKey["76561198000000031:char1"].name)

print("\n=== ТЕСТ 2: имя персонажа по ключу ===")
check("паспортное ФИО для офлайн", S.CharacterName("76561198000000077:char1") == "Иоганн Мюллер",
    S.CharacterName("76561198000000077:char1"))
check("RP-имя для онлайн", S.CharacterName("76561198000000031:char1") == "Отто Крамер",
    S.CharacterName("76561198000000031:char1"))
check("неизвестный ключ возвращает сам ключ", S.CharacterName("111:char1") == "111:char1")
check("пустой ключ даёт прочерк", S.CharacterName("") == "—")

-- ======================================================================
print("\n=== ТЕСТ 3: диплом офлайн-персонажу ===")
local okD, recD = D.Issue(teacher, {
    graduate = "76561198000000077:char1",
    specialty = "юриспруденция", qualification = "юрист",
    level = "bachelor", form = "full", grade = "с отличием",
})
check("преподаватель учреждения выписал диплом офлайн-персонажу", okD, recD)
check("диплом получил ФИО из паспорта, а не ключ",
    okD and recD.graduateName == "Иоганн Мюллер", okD and recD.graduateName)
check("диплом привязан к персонажу", okD and recD.graduate == "76561198000000077:char1")
check("учреждение подставлено из доступов",
    okD and recD.institution == "Государственный университет Гроннера", okD and recD.institution)
check("номер бланка выдан", okD and tostring(recD.number):match("^ГД%-%d+%-%d+$") ~= nil,
    okD and recD.number)

print("\n=== ТЕСТ 4: права на выписку ===")
local okM, whyM = D.Issue(medic, { graduate = "76561198000000088:char3", specialty = "терапия" })
check("клинике без canDiploma выписывать нельзя", okM == false, whyM)
local okA, recA = D.Issue(admin, { graduate = "76561198000000088:char3", specialty = "медицина",
    institution = "Медицинская академия" })
check("суперадмин выписывает всегда", okA, recA)
check("у суперадминского диплома тоже ФИО из паспорта",
    okA and recA.graduateName == "Клара Вебер", okA and recA.graduateName)

print("\n=== ТЕСТ 5: счёт офлайн-персонажу ===")
local okI, recI = S.IssueInvoice(rector, "76561198000000077:char1",
    { title = "Обучение, семестр 1", amount = 12000 })
check("счёт офлайн-персонажу выставлен", okI, recI)
check("в счёте человеческое имя, а не ключ",
    okI and recI.targetName == "Иоганн Мюллер", okI and recI.targetName)

-- ======================================================================
print("\n=== ТЕСТ 6: права рабочего места ===")
local can1 = EDU.CanUse(teacher)
local can2 = EDU.CanUse(medic)
local can3 = EDU.CanUse(admin)
check("сотрудник учреждения имеет доступ", can1 == true)
check("сотрудник клиники доступа не имеет", can2 == false)
check("суперадмин имеет доступ", can3 == true)

print("\n=== ТЕСТ 7: снимок рабочего места ===")
local snapT = EDU.Snapshot(teacher)
check("снимок разрешает выписку", snapT.canIssue == true)
check("в снимке название учреждения",
    snapT.institution == "Государственный университет Гроннера", snapT.institution)
check("в снимке есть уровни образования", #snapT.levels > 0, #snapT.levels)
check("в снимке есть формы обучения", #snapT.forms > 0, #snapT.forms)
check("в снимке есть реестр персонажей", #snapT.characters > 0, #snapT.characters)
check("офлайн-персонаж попал в выбор выпускника", (function()
    for _, c in ipairs(snapT.characters) do
        if c.key == "76561198000000077:char1" then return true end
    end
end)() == true)
check("реестр учреждения содержит свой диплом", (function()
    for _, d in ipairs(snapT.diplomas) do if d.graduateName == "Иоганн Мюллер" then return true end end
end)() == true)
check("чужой диплом в реестр учреждения не попал", (function()
    for _, d in ipairs(snapT.diplomas) do if d.graduateName == "Клара Вебер" then return true end end
end)() ~= true)
check("статистика посчитана", snapT.stats.total == #snapT.diplomas, snapT.stats.total)
check("преподаватель не лидер", snapT.isLeader == false)

local snapR = EDU.Snapshot(rector)
check("ректор опознан как руководитель", snapR.isLeader == true)

local snapA = EDU.Snapshot(admin)
check("суперадмин видит весь реестр", #snapA.diplomas >= 2, #snapA.diplomas)
check("снимок суперадмина помечен", snapA.isSuper == true)

local snapM = EDU.Snapshot(medic)
check("клинике снимок выписку не разрешает", snapM.canIssue == false)

print("\n=== ТЕСТ 8: аннулирование ===")
local okR, whyR = D.Revoke(teacher, recD.number, "ошибка данных")
check("рядовой сотрудник аннулировать не может", okR == false, whyR)
local okR2 = D.Revoke(rector, recD.number, "ошибка данных")
check("руководитель учреждения аннулировал", okR2)
local snapT2 = EDU.Snapshot(rector)
check("в статистике учтён аннулированный", snapT2.stats.revoked >= 1, snapT2.stats.revoked)

print("\n=== ТЕСТ 9: проверка по номеру ===")
check("диплом находится по номеру", D.ByNumber(recA.number) ~= nil)
check("несуществующий номер не находится", D.ByNumber("ГД-1900-000001") == nil)

print("\n=== ТЕСТ 10: данные не потеряны при перезагрузке ===")
local before = #D.List
D.List = {}
D.Load()
check("реестр дипломов восстановлен из файла", #D.List == before, ("%d vs %d"):format(#D.List, before))
local restored = D.ByNumber(recA.number)
check("восстановленная запись сохранила ФИО",
    restored and restored.graduateName == "Клара Вебер", restored and restored.graduateName)

print("\n=== ТЕСТ 11: «Мои дипломы» — личный просмотр игроком ===")
-- Игрок смотрит свои дипломы как обычный документ: без прав фракции,
-- без банкомата. Выпускник recD — офлайн-персонаж 76561198000000077:char1.
local graduate = mkPlayer("76561198000000077:char1", "Johann", "", false, "Иоганн Мюллер")

check("EDU.MyDiplomas существует", isfunction(EDU.MyDiplomas))

local mine = EDU.MyDiplomas(graduate)
check("выпускник видит свой диплом", #mine >= 1, #mine)
check("в списке только свои бланки", (function()
    for _, d in ipairs(mine) do
        if d.graduateName ~= "Иоганн Мюллер" then return false end
    end
    return true
end)())
check("бланк отдан с номером", mine[1] and tostring(mine[1].number):match("^ГД%-") ~= nil,
    mine[1] and mine[1].number)
check("уровень отдан читаемым названием, а не кодом",
    mine[1] and mine[1].levelName ~= nil and mine[1].levelName ~= "bachelor",
    mine[1] and mine[1].levelName)
check("форма обучения отдана названием",
    mine[1] and mine[1].formName ~= nil and mine[1].formName ~= "full",
    mine[1] and mine[1].formName)
check("учреждение отдано", mine[1] and mine[1].institution ~= nil and mine[1].institution ~= "")

-- Аннулированный бланк владелец обязан видеть — со статусом
local revokedSeen = false
for _, d in ipairs(mine) do if d.revoked then revokedSeen = true end end
check("аннулированный бланк остаётся виден владельцу со статусом", revokedSeen)

-- Чужие дипломы не подмешиваются
local stranger = mkPlayer("76561198000000099:char1", "Stranger", "", false)
check("посторонний не видит чужих дипломов", #EDU.MyDiplomas(stranger) == 0,
    #EDU.MyDiplomas(stranger))

-- Клара Вебер (recA) — отдельный персонаж, у неё свой бланк
local klara = mkPlayer("76561198000000088:char3", "Klara", "", false, "Клара Вебер")
local kmine = EDU.MyDiplomas(klara)
check("второй выпускник видит ровно свой диплом", #kmine == 1, #kmine)
check("бланк второго выпускника принадлежит ей",
    kmine[1] and kmine[1].graduateName == "Клара Вебер", kmine[1] and kmine[1].graduateName)

-- Прав фракции для личного просмотра не требуется
check("для личного просмотра права canDiploma не нужны",
    EDU.CanUse(graduate) == false and #EDU.MyDiplomas(graduate) >= 1)

print(("\n=== ИТОГ: %d/%d, failures=%d ==="):format(total - fails, total, fails))
if fails > 0 then os.exit(1) end
