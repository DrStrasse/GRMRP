--[[
    sim_charkey_canon.lua — ключ персонажа и владельцы хуков.

    Что проверяет (и какие боевые баги ловит):

    1. КОНТРАКТ КАНОНА. `GRM.CharKey` из sh_01_grm_core.lua — единственная
       реализация ключа персонажа. До консолидации локальная `charKey` была
       скопирована в 36 файлов в 25 редакциях; редакции разошлись:
         * часть возвращала "" для строкового ключа  → запись в пустой ключ;
         * часть возвращала голый SteamID64 без слота → второй персонаж
           видел имущество первого;
         * часть возвращала nil при невалидном игроке → падение в конкатенации.
       Стенд фиксирует контракт по всем этим четырём осям.

    2. НЕТ ВОЗВРАТА КОПИЙ. Файлы, переведённые на канон, не должны заново
       объявлять `local function charKey` (регресс-защита от «дописал рядом»).

    3. ОДИН ВЛАДЕЛЕЦ ХУКА (§5.1). В sh_factions.lua было ДВЕ регистрации
       hook.Add("PlayerInitialSpawn", "Factions_SyncOnJoin"): вторая молча
       затирала первую, и зашедший игрок не получал ни снимка фракций, ни
       NW-полей. Проверяем: имя регистрируется один раз в пределах одной
       области видимости (SERVER/CLIENT считаем раздельно — это законно),
       и уцелевший обработчик делает все три действия.

    Откатная проверка (§10.2) выполнена: возврат второго hook.Add и возврат
    локальной копии charKey в sh_grm_atm.lua дают красный по пунктам 2 и 3.
]]

local ROOT = "lua/"
local ok_count, fail_count = 0, 0

local function ok(msg)
    ok_count = ok_count + 1
    print("  ok   " .. msg)
end

local function fail(msg)
    fail_count = fail_count + 1
    print("  FAIL " .. msg)
end

local function check(cond, msg)
    if cond then ok(msg) else fail(msg) end
end

local function readFile(path)
    local fh = io.open(path, "rb")
    if not fh then return nil end
    local data = fh:read("*a")
    fh:close()
    return data
end

-- Комментарии отрезаем: шаблон обязан совпадать с КОДОМ, а не с пояснением
-- к фиксу (§10.1.5 — на этом уже обжигались).
local function stripComments(src)
    src = src:gsub("%-%-%[%[.-%]%]", "")
    return (src:gsub("%-%-[^\n]*", ""))
end

-- ── мок GMod, минимально достаточный для sh_01_grm_core.lua ──────────
SERVER, CLIENT = true, false
function AddCSLuaFile() end
function isstring(v) return type(v) == "string" end
function isfunction(v) return type(v) == "function" end
function istable(v) return type(v) == "table" end
function IsValid(v) return type(v) == "table" and v.valid == true end
function CreateClientConVar() end
string.Trim = function(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end

local coreSrc = readFile(ROOT .. "autorun/sh_01_grm_core.lua")
if not coreSrc then
    print("НЕ НАЙДЕН sh_01_grm_core.lua — запускать из корня репозитория")
    os.exit(1)
end
local chunk = assert(loadstring(coreSrc, "sh_01_grm_core.lua"))
chunk()

check(type(GRM) == "table" and isfunction(GRM.CharKey),
    "канон GRM.CharKey объявлен в ядре")

-- ── 1. контракт ──────────────────────────────────────────────────────
local function fakePlayer(sid, key)
    return {
        valid = true,
        IsPlayer = function() return true end,
        SteamID64 = function() return sid end,
        SteamID = function() return "STEAM_0:1:1" end,
        _key = key,
    }
end

-- Игрок без Identity: слот дописывается, ключ никогда не голый SteamID64.
GRM.Identity = nil
local ply = fakePlayer("76561198000000001")
check(GRM.CharKey(ply) == "76561198000000001:char1",
    "игрок без Identity → SteamID64:char1 (а не голый SteamID64)")

-- Игрок с Identity: слот берёт владелец контракта, ядро не изобретает свой.
GRM.Identity = {
    CharacterKey = function(p) return p._key or (p:SteamID64() .. ":char2") end,
}
check(GRM.CharKey(fakePlayer("76561198000000002", "76561198000000002:char3"))
    == "76561198000000002:char3", "игрок с Identity → ключ владельца контракта")

-- Identity вернул пустое (персонаж ещё не выбран) — не отдаём "" наружу.
GRM.Identity = { CharacterKey = function() return "" end }
check(GRM.CharKey(fakePlayer("76561198000000003")) == "76561198000000003:char1",
    "пустой ответ Identity → падение на SteamID64:char1, не пустая строка")

GRM.Identity = nil
check(GRM.CharKey("76561198000000004:char2") == "76561198000000004:char2",
    "готовый ключ персонажа проходит насквозь (редакции возвращали \"\")")
check(GRM.CharKey("76561198000000005") == "76561198000000005:char1",
    "legacy-ключ аккаунта достраивается слотом char1")
check(GRM.CharKey("backend_slot") == "backend_slot",
    "служебная строка не калечится")
check(GRM.CharKey(nil) == "" and GRM.CharKey(false) == "",
    "nil/невалидный → \"\" (никогда не nil: ключ идёт в конкатенации)")

local invalidEnt = { valid = false, IsPlayer = function() return true end }
check(GRM.CharKey(invalidEnt) ~= nil, "удалённая энтити не роняет ключ")

-- ── 2. копии не вернулись ────────────────────────────────────────────
local CONSOLIDATED = {
    "autorun/server/sv_grm_comp_terminal.lua",
    "autorun/sh_grm_services.lua",
    "autorun/sh_grm_special_service.lua",
    "autorun/sh_grm_wanted_board.lua",
    "autorun/sh_grm_wanted_bulletins.lua",
    "autorun/sh_grm_wanted_exchange.lua",
    "autorun/sh_grm_wanted_fines.lua",
    "autorun/sh_grm_estate_deal.lua",
    "autorun/sh_grm_home_bed.lua",
    "autorun/sh_grm_housing.lua",
    "autorun/sh_grm_housing_panel.lua",
    "autorun/sh_grm_housing_search.lua",
    "autorun/sh_grm_atm.lua",
    "autorun/sh_grm_public_kiosk.lua",
    "autorun/sh_grm_diplomas.lua",
}

local returned = {}
for _, rel in ipairs(CONSOLIDATED) do
    local src = readFile(ROOT .. rel)
    if not src then
        fail("файл пропал: " .. rel)
    else
        local code = stripComments(src)
        if code:find("local function charKey", 1, true) then
            returned[#returned + 1] = rel
        end
        if not code:find("local charKey = GRM.CharKey", 1, true) then
            fail("не привязан канон: " .. rel)
        end
    end
end
check(#returned == 0, "локальные копии charKey не вернулись в переведённые файлы"
    .. (#returned > 0 and (" (" .. table.concat(returned, ", ") .. ")") or ""))

-- ── 3. один владелец хука входа игрока ───────────────────────────────
local factionsSrc = readFile(ROOT .. "autorun/sh_factions.lua")
check(factionsSrc ~= nil, "sh_factions.lua на месте")

if factionsSrc then
    local code = stripComments(factionsSrc)
    local count = 0
    for _ in code:gmatch('hook%.Add%(%s*"PlayerInitialSpawn"%s*,%s*"Factions_SyncOnJoin"') do
        count = count + 1
    end
    check(count == 1,
        "PlayerInitialSpawn/Factions_SyncOnJoin регистрируется один раз (было " .. count .. ")")

    -- Уцелевший обработчик обязан делать всё, что делали обе копии:
    -- снимок фракций, NW-поля и общую рассылку.
    local body = code:match('hook%.Add%(%s*"PlayerInitialSpawn"%s*,%s*"Factions_SyncOnJoin".-\n%s*end%)')
    if not body then
        fail("тело обработчика входа не найдено")
    else
        check(body:find("sendFactionDataTo", 1, true) ~= nil,
            "вход игрока: отправляется снимок фракций (sendFactionDataTo)")
        check(body:find("syncPlayerFactionNW", 1, true) ~= nil,
            "вход игрока: обновляются NW-поля (syncPlayerFactionNW)")
        check(body:find("broadcastFactionData", 1, true) ~= nil,
            "вход игрока: идёт общая рассылка (broadcastFactionData)")
    end
end

print(("CHARKEY CANON: %d/%d, провалов: %d"):format(ok_count, ok_count + fail_count, fail_count))
os.exit(fail_count > 0 and 1 or 0)
