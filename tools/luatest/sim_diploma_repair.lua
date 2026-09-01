-- ======================================================================
-- sim_diploma_repair — разовая починка дипломов, обрезанных по БАЙТАМ.
--
-- Предыстория (задача 12): trim() резал строки через string.sub, то есть
-- по байтам. Кириллица в UTF-8 занимает 2 байта, поэтому trim(s, 96)
-- оставлял ~48 русских букв и мог разорвать последний символ пополам:
--   «…школа КГБ им. Ф.Э.Дзержинског» + битый байт.
-- Код выдачи уже починен (GRM.Utf8Sub), но записи, сохранённые ДО этого,
-- лежат в diplomas.json обрезанными. Их чинит D.Repair.
--
-- Главное требование: это ГОСРЕЕСТР, придумывать данные нельзя.
--   • битый хвост — мусор, убираем всегда;
--   • institution/graduateName — есть канонический источник (доступ
--     фракции и паспорт), восстанавливаем целиком;
--   • specialty/qualification/note/… — источника нет, хвост уничтожен
--     записью на диск. Такие поля НЕ додумываем, а выносим в отчёт.
--
-- Проверяем:
--   1) битый UTF-8 хвост распознаётся и убирается, строка снова валидна;
--   2) institution восстанавливается из доступа фракции;
--   3) graduateName восстанавливается из паспорта;
--   4) specialty с утраченным хвостом попадает в unrecoverable и НЕ
--      выдумывается;
--   5) режим просмотра (apply=false) ничего не пишет на диск;
--   6) apply=true пишет и создаёт бэкап diplomas.bak.<ts>.json;
--   7) повторный прогон идемпотентен — второй раз чинить нечего;
--   8) целые записи не трогаются;
--   9) права: обычный игрок починку не запускает.
--
-- Запуск: luajit tools/luatest/sim_diploma_repair.lua
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
_G.string.Comma = function(v) return tostring(math.floor(tonumber(v) or 0)) end
_G.string.Explode = function(sep, s)
    local o = {} for m in tostring(s):gmatch("[^" .. sep .. "]+") do o[#o + 1] = m end return o
end
_G.CurTime = function() return os.clock() * 1000 end
_G.SortedPairs = function(t) return pairs(t) end
_G.SetGlobalDouble = function() end
_G.Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end

-- ── JSON (как в sim_education) ───────────────────────────────────────
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
        if ch == '\\' then
            local n = str:sub(pos + 1, pos + 1)
            if n == "u" then
                local hex = str:sub(pos + 2, pos + 5)
                s = s .. string.char(tonumber(hex, 16) % 256) pos = pos + 6
            else
                s = s .. (({ ['n'] = '\n', ['"'] = '"', ['\\'] = '\\' })[n] or "") pos = pos + 2
            end
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
_G.net = setmetatable({
    Start = function() end, Send = function() end, Broadcast = function() end,
    Receive = function() end, AddNetworkString = function() end,
}, { __index = function() return function() end end })

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
        SetNWInt = function() end, SetNW2Int = function() end,
        ChatPrint = function() end, PrintMessage = function() end,
        GetPos = function() return { DistToSqr = function() return 0 end } end,
    }
    PLAYERS[#PLAYERS + 1] = p
    return p
end
_G.player = { GetAll = function() return PLAYERS end, GetBySteamID = function() end, GetBySteamID64 = function() end }

_G.GRM = { Identity = { CharacterKey = function(p) return p.key end } }
_G.GRM.Notify = function() end
_G.GRM.FormatMoney = function(v) return tostring(v) .. " GRM" end

_G.Factions = {
    ["Университет"] = {
        Leader = "76561198000000031:char1", LeaderRoleName = "Ректор",
        Members = { ["76561198000000031:char1"] = { Role = "Ректор" } },
    },
}
_G.FactionsAPI = { Save = function() end }

-- Канонический источник ФИО: паспорт выпускника.
local GRAD_KEY  = "76561198000000077:char1"
local GRAD_FULL = "Иоганн Себастьян Мюллер-Вайнгартнер"
_G.GRM.Documents = {
    Registry = { passports = { [GRAD_KEY] = { fullName = GRAD_FULL, status = "active" } } },
}

dofile("lua/autorun/sh_00_grm_ui.lua")
dofile("lua/autorun/sh_grm_services.lua")
dofile("lua/autorun/sh_grm_diplomas.lua")

local S, D = GRM.Services, GRM.Diplomas

local fails, total = 0, 0
local function check(name, cond, extra)
    total = total + 1
    if cond then print("  OK   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "   " .. tostring(extra or "")) end
end

-- Канонические значения учреждения.
local INST_FULL = "Высшая Краснознамённая школа КГБ им. Ф.Э.Дзержинского"
S.SetAccess("Университет", {
    canService = true, canInvoice = true, canDiploma = true,
    institution = INST_FULL, maxInvoice = 50000,
})

local admin = mkPlayer("76561198000000001:char1", "Admin", "", true)
local civil = mkPlayer("76561198000000055:char1", "Civil", "", false)

--[[ Байтовая обрезка даёт ДВА разных исхода, и оба встречаются в реестре:
     • рез попал на границу символа — строка валидна, но текст оборван
       посередине слова («…контрразведыва»);
     • рез попал внутрь двухбайтового символа — в конце висит битый байт.
     Какой именно случай выпадет, решает чётность ASCII-символов до реза,
     поэтому проверяем оба явно. ]]
local SPEC_FULL = "Аналитико-прогностическое и социальное управление (оперативная работа)"
local SPEC_CUT  = string.sub(SPEC_FULL, 1, 96)                      -- рез по границе
local QUAL_FULL = "AОперативно-розыскная деятельность и контрразведывательное обеспечение"
local QUAL_CUT  = string.sub(QUAL_FULL, 1, 96)                      -- рез внутри символа

--- Валиден ли UTF-8 (нет оборванных последовательностей).
local function validUTF8(s)
    local i, n = 1, #s
    while i <= n do
        local b = s:byte(i)
        local size = (b < 128 and 1) or (b >= 192 and b < 224 and 2)
            or (b >= 224 and b < 240 and 3) or (b >= 240 and 4) or nil
        if not size then return false end
        if i + size - 1 > n then return false end
        for j = i + 1, i + size - 1 do
            local c = s:byte(j)
            if not c or c < 128 or c >= 192 then return false end
        end
        i = i + size
    end
    return true
end

print("\n=== ПОДГОТОВКА: реестр с записями, обрезанными по байтам ===")
local INST_CUT = string.sub(INST_FULL, 1, 96)
local GRAD_CUT = string.sub(GRAD_FULL, 1, 64)
check("учреждение действительно обрезано байтами", #INST_CUT == 96 and INST_CUT ~= INST_FULL)
check("случай А: рез по границе символа, строка валидна но текст оборван",
    validUTF8(INST_CUT) and validUTF8(SPEC_CUT))
check("случай Б: рез внутри символа, в конце битый байт",
    not validUTF8(GRAD_CUT) and not validUTF8(QUAL_CUT),
    "тест обязан воспроизводить оба исхода обрезки")

-- Кладём «старый» файл прямо на диск-заглушку и грузим штатным D.Load().
local broken = {
    version = 1, nextNumber = 3,
    diplomas = {
        {
            number = "ГД-2026-000001", seq = 1, graduate = GRAD_KEY,
            graduateName = GRAD_CUT, institution = INST_CUT,
            faction = "Университет", specialty = SPEC_CUT,
            qualification = QUAL_CUT, level = "master", form = "full",
            grade = "", paid = false, invoiceID = 0,
            issuer = "76561198000000031:char1", issuerName = "Rector",
            signedBy = "", issued = 1000, revoked = false, note = "",
        },
        {   -- целая запись: её трогать нельзя
            number = "ГД-2026-000002", seq = 2, graduate = GRAD_KEY,
            graduateName = "Пётр Иванов", institution = INST_FULL,
            faction = "Университет", specialty = "Юриспруденция",
            qualification = "", level = "bachelor", form = "full",
            grade = "", paid = false, invoiceID = 0,
            issuer = "76561198000000031:char1", issuerName = "Rector",
            signedBy = "", issued = 2000, revoked = false, note = "",
        },
    },
}
files["grm_services/diplomas.json"] = enc(broken)
D.Load()
check("реестр загружен: 2 записи", #D.List == 2, "#List=" .. #D.List)

print("\n=== ТЕСТ 1: режим просмотра ничего не пишет ===")
local before = files["grm_services/diplomas.json"]
local ok1, rep1 = D.Repair(admin, false)
check("просмотр отработал", ok1 == true, tostring(rep1))
check("файл на диске не изменился", files["grm_services/diplomas.json"] == before)
check("в памяти запись всё ещё обрезана", D.List[1].institution == INST_CUT)
check("просмотр насчитал изменения", rep1.changed > 0, "changed=" .. tostring(rep1.changed))
check("бэкап в режиме просмотра не создан",
    (function() for k in pairs(files) do if k:find("diplomas%.bak%.") then return false end end return true end)())

print("\n=== ТЕСТ 2: восстановление по каноническому источнику ===")
local ok2, rep2 = D.Repair(admin, true)
check("починка отработала", ok2 == true, tostring(rep2))
check("учреждение восстановлено целиком", D.List[1].institution == INST_FULL,
    "получили: " .. tostring(D.List[1].institution))
check("ФИО выпускника восстановлено из паспорта", D.List[1].graduateName == GRAD_FULL,
    "получили: " .. tostring(D.List[1].graduateName))
check("строки снова валидный UTF-8",
    validUTF8(D.List[1].institution) and validUTF8(D.List[1].graduateName))

print("\n=== ТЕСТ 3: утраченное НЕ выдумывается ===")
local specNow = D.List[1].specialty
check("специальность не стала полным текстом", specNow ~= SPEC_FULL,
    "модуль не имеет права додумывать утраченный хвост")
check("у специальности убран битый символ", validUTF8(specNow), "specialty=" .. tostring(specNow))
check("специальность осталась началом исходной", SPEC_FULL:sub(1, #specNow) == specNow)
local function isFlagged(field)
    for _, u in ipairs(rep2.unrecoverable) do
        if u.number == "ГД-2026-000001" and u.field == field then return true end
    end
    return false
end
check("специальность помечена как невосстановимая", isFlagged("specialty"),
    "администратор должен увидеть, что поле надо ввести заново")

local qualNow = D.List[1].qualification
check("у квалификации срезан битый байт", validUTF8(qualNow), "qualification=" .. tostring(qualNow))
check("квалификация не выдумана", qualNow ~= QUAL_FULL)
check("квалификация осталась началом исходной", QUAL_FULL:sub(1, #qualNow) == qualNow)
check("квалификация помечена как невосстановимая", isFlagged("qualification"))

print("\n=== ТЕСТ 4: запись на диск и бэкап ===")
local bak = nil
for k in pairs(files) do if k:find("diplomas%.bak%.") then bak = k end end
check("бэкап исходного файла создан", bak ~= nil)
check("в бэкапе лежат ИСХОДНЫЕ обрезанные данные",
    bak and files[bak] == before, "бэкап обязан быть до правок")
local saved = util.JSONToTable(files["grm_services/diplomas.json"])
local savedRec
for _, r in ipairs(saved.diplomas or {}) do if r.number == "ГД-2026-000001" then savedRec = r end end
check("на диск записано восстановленное учреждение",
    savedRec and savedRec.institution == INST_FULL)

print("\n=== ТЕСТ 5: целая запись не тронута ===")
check("вторая запись без изменений",
    D.List[2].institution == INST_FULL and D.List[2].specialty == "Юриспруденция"
    and D.List[2].graduateName == "Пётр Иванов")

print("\n=== ТЕСТ 5б: длинное, но ЦЕЛОЕ значение не считается битым ===")
--[[ INST_FULL длиннее старого лимита в 96 байт. После восстановления оно
     целое, но проверка «длина >= лимита» сама по себе объявила бы его
     обрезанным и погнала администратора править исправную запись. ]]
check("канонические 98 байт длиннее старого лимита 96", #INST_FULL > 96)
local falseAlarm = false
for _, u in ipairs(rep2.unrecoverable) do
    if u.field == "institution" then falseAlarm = true end
end
check("целое учреждение не помечено как невосстановимое", not falseAlarm,
    "ложная тревога заставит править исправные данные")

print("\n=== ТЕСТ 6: идемпотентность ===")
local ok6, rep6 = D.Repair(admin, true)
check("повторная починка отработала", ok6 == true)
check("во второй раз чинить нечего", rep6.changed == 0, "changed=" .. tostring(rep6.changed))
check("битых хвостов больше нет", rep6.fixedTails == 0, "fixedTails=" .. tostring(rep6.fixedTails))
check("учреждение осталось целым", D.List[1].institution == INST_FULL)

print("\n=== ТЕСТ 7: права ===")
local ok7, err7 = D.Repair(civil, true)
check("обычный игрок починку не запускает", ok7 == false, tostring(err7))
check("причина отказа названа", tostring(err7):find("уперадмин") ~= nil, tostring(err7))

print(("\n=== ИТОГ: %d/%d, failures=%d ==="):format(total - fails, total, fails))
if fails > 0 then os.exit(1) end
