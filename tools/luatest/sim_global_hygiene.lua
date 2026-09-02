--[[--------------------------------------------------------------------
    sim_global_hygiene — чистота пространства имён и порядок объявлений.

    ПОЧЕМУ ЭТОТ СТЕНД ВООБЩЕ НУЖЕН. В Lua забытый `local` не является
    ошибкой. Компилятор молча делает две вещи, и обе плохие:

      1. ПРИСВОЕНИЕ без local пишет в ОБЩЕЕ пространство имён сервера.
         Наш модуль и чужой аддон с переменной `ui` или `Factions`
         затирают друг друга. Файл грузится, ошибок нет, ломается позже
         и совсем в другом месте.

      2. ЧТЕНИЕ имени ВЫШЕ его `local`-объявления компилируется как
         обращение к глобалу. Тоже без ошибок при загрузке — падает уже
         в бою:  attempt to call global 'vehicleBase' (a nil value).

    Ровно так упал знак на машине: PL.LayoutFor вызывала vehicleBase,
    объявленную на 200 строк ниже. Ставишь номер на бампер — Lua-ошибка
    вместо крепления. Сам стенд номеров (sim_plates) это уже ловил
    крашем, но по нему было не видно, что это целый КЛАСС багов.

    ЧЕМ ПРОВЕРЯЕМ. Не текстовым поиском, а БАЙТКОДОМ luajit -bl. Он
    показывает решение, которое реально принял компилятор: GSET — запись
    в глобал, GGET — чтение глобала. Текстовый поиск здесь врёт
    (комментарии, строки, одноимённые поля таблиц), байткод — нет.

    Запуск: luajit tools/luatest/sim_global_hygiene.lua
----------------------------------------------------------------------]]
local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

--[[ Путь к самому интерпретатору: arg[-1] — это то, чем нас запустили.
     Так стенд работает в общем прогоне без переменных окружения; LUAJIT
     остаётся ручным переопределением на случай нестандартной сборки. ]]
local LJ = os.getenv("LUAJIT") or (arg and arg[-1]) or "luajit"

--[[ ЛИСТИНГ БАЙТКОДА ТРЕБУЕТ jit.*-МОДУЛЕЙ.
     Команда `luajit -bl` реализована lua-файлами jit/bcsave.lua рядом с
     бинарником. Если LUA_PATH их не видит, luajit пишет «unknown luaJIT
     command» в stdout и завершается успешно — разбор получает пустоту, и
     стенд бодро рапортует «нарушений нет», ничего не проверив.
     Такой молчаливый зелёный отчёт хуже отсутствия стенда, поэтому путь
     выводим от самого бинарника, а работоспособность проверяем явно. ]]
local LJDIR = LJ:match("^(.*)/[^/]+$")
local BCPATH = LJDIR and (LJDIR .. "/?.lua") or "?.lua"
local function bcCmd(path)
    return ("LUA_PATH='%s;;' %s -bl '%s' 2>&1"):format(BCPATH, LJ, path)
end

-- Файлы сборки. EasyChat — внешняя библиотека, живёт по своим правилам.
local files = {}
do
    local p = io.popen("find lua addons -name '*.lua' | grep -v easychat | sort")
    for line in p:lines() do files[#files + 1] = line end
    p:close()
end
print(("\n=== ФАЙЛОВ В ПРОВЕРКЕ: %d ==="):format(#files))

-- САМОПРОВЕРКА ИНСТРУМЕНТА. Пока не убедились, что листинг байткода
-- реально приходит, любые «нарушений нет» ниже ничего не стоят.
do
    local probe = io.popen(bcCmd("lua/autorun/sh_01_grm_core.lua"))
    local text = probe:read("*a") or ""
    probe:close()
    if not text:find("BYTECODE", 1, true) then
        print("  FAIL листинг байткода недоступен — стенд не может ничего проверить")
        print("       вывод luajit: " .. tostring(text:sub(1, 120)))
        print("       подсказка: LUAJIT=/путь/к/luajit, рядом должен лежать каталог jit/")
        os.exit(1)
    end
    print("  ok   листинг байткода доступен, разбор осмыслен")
end

-- Разбор байткода одного файла: какие имена он пишет в глобалы и какие
-- читает из глобалов (по каждой функции отдельно).
local function scan(path)
    local h = io.popen(bcCmd(path))
    local sets, gets = {}, {}
    for line in h:lines() do
        local s = line:match('GSET%s+%d+%s+%d+%s+; "([%w_]+)"')
        if s then sets[s] = true end
        local g = line:match('GGET%s+%d+%s+%d+%s+; "([%w_]+)"')
        if g then gets[g] = true end
    end
    h:close()
    return sets, gets
end

-- Имена, объявленные в файле через local (грубо, но для сверки хватает:
-- нас интересует пересечение с РЕАЛЬНЫМ обращением к глобалу).
--[[ ВАЖНО: разбираем ПОСТРОЧНО.
     Класс %s включает перевод строки, поэтому шаблон вида
     `local%s+([%w_,%s]*)=` жадно перепрыгивает через несколько строк и
     затягивает в «локальные» посторонние имена из следующих объявлений.
     Так FactionsData один раз попал в список локалей и дал ложную
     тревогу в секции 1. Одна строка — одно объявление. ]]
local function localNames(src)
    local names = {}
    for line in (src .. "\n"):gmatch("([^\n]*)\n") do
        local fn = line:match("local%s+function%s+([A-Za-z_][%w_]*)")
        if fn then names[fn] = true end
        local decl = line:match("^%s*local%s+([A-Za-z_][%w_,%s]-)%s*=")
                  or line:match("^%s*local%s+([A-Za-z_][%w_,%s]-)%s*$")
        if decl then
            for n in decl:gmatch("[A-Za-z_][%w_]*") do names[n] = true end
        end
    end
    return names
end

-------------------------------------------------------------------------
-- 1. ИСПОЛЬЗОВАНИЕ ДО ОБЪЯВЛЕНИЯ
-------------------------------------------------------------------------
-- Имя объявлено в файле как local, но байткод читает его как ГЛОБАЛ —
-- значит, обращение стоит выше объявления и вернёт nil.
print("\n=== 1. ЧТЕНИЕ LOCAL-ИМЕНИ КАК ГЛОБАЛА (ПАДЕНИЕ В БОЮ) ===")

-- Штатные глобалы GMod и внешних аддонов: если файл делает
-- `local net = net`, чтение глобала net — это норма, а не баг.
local AMBIENT = {}
for _, n in ipairs({
    "net", "util", "table", "string", "math", "os", "io", "hook", "timer",
    "file", "player", "ents", "team", "chat", "cam", "list", "weapons",
    "surface", "draw", "render", "vgui", "concommand", "cvars", "sound",
    "istable", "isstring", "isnumber", "isfunction", "isbool", "isentity",
    "IsValid", "CurTime", "SysTime", "RealTime", "Vector", "Angle", "Color",
    "pairs", "ipairs", "tostring", "tonumber", "type", "pcall", "unpack",
    "GRM", "EasyChat", "textscreenFonts",
}) do AMBIENT[n] = true end

local earlyUse = {}
for _, path in ipairs(files) do
    local src = read(path)
    local lcl = localNames(src)
    local _, gets = scan(path)
    for name in pairs(gets) do
        if lcl[name] and not AMBIENT[name] then
            earlyUse[#earlyUse + 1] = path .. " -> " .. name
        end
    end
end
table.sort(earlyUse)
ok(#earlyUse == 0, "ни одно local-имя не читается как глобал",
    #earlyUse > 0 and ("\n     " .. table.concat(earlyUse, "\n     ")) or nil)

-------------------------------------------------------------------------
-- 2. ТОЧКИ, ГДЕ ЭТО УЖЕ ЛОВИЛОСЬ — СТОРОЖА ОТ ВОЗВРАТА
-------------------------------------------------------------------------
-- Каждая проверка ниже — конкретный баг, найденный этим стендом.
-- Проверяем не «есть ли слово», а что объявление стоит ВЫШЕ первого
-- использования: только это и защищает от регрессии.
print("\n=== 2. КОНКРЕТНЫЕ НАХОДКИ: ОБЪЯВЛЕНИЕ ВЫШЕ ИСПОЛЬЗОВАНИЯ ===")

--[[ Первая строка, подходящая под шаблон, СРЕДИ КОДА.
     Комментарии пропускаем сознательно: пояснение к правке само содержит
     имя функции («PL.LayoutFor зовёт vehicleBase»), и без этого фильтра
     проверка цепляется за собственный комментарий и врёт — уже ловились
     на этом. Отсекаем и строчные `--`, и тело длинного блока --[==[ ]==]. ]]
local function declLine(src, pattern)
    local n, inBlock = 0, false
    for line in (src .. "\n"):gmatch("([^\n]*)\n") do
        n = n + 1
        local code = line
        if inBlock then
            if code:find("]]", 1, true) then
                inBlock = false
                code = code:sub((code:find("]]", 1, true)) + 2)
            else
                code = ""
            end
        end
        local blockAt = code:find("%-%-%[%[")
        if blockAt then
            local rest = code:sub(blockAt)
            if not rest:find("]]", 1, true) then inBlock = true end
            code = code:sub(1, blockAt - 1)
        end
        code = code:gsub("%-%-.*$", "")
        if code:find(pattern) then return n end
    end
end

local function orderOk(src, declPat, usePat, label)
    local d = declLine(src, declPat)
    local u = declLine(src, usePat)
    ok(d ~= nil and u ~= nil and d < u, label,
        ("объявление=%s использование=%s"):format(tostring(d), tostring(u)))
end

local plates = read("lua/autorun/sh_grm_plates.lua")
orderOk(plates, "local function vehicleBase", "PL%.LayoutFor",
    "номера: vehicleBase объявлена до LayoutFor (знак вставал с ошибкой)")

ok(plates:find("local vehID, vehName = PL.VehicleIdentity(veh)", 1, true) == nil
   or plates:find("local vehID, vehName", 1, true) < plates:find("gr.vehicleUID = tostring(vehID", 1, true),
    "номера: vehID виден там, где пишется vehicleUID гаража")

local minimap = read("lua/autorun/sh_grm_minimap.lua")
orderOk(minimap, "local mapRenderCenter", "if mapRenderCenter and mapRenderSpan then",
    "миникарта: центр/масштаб объявлены до отрисовки маркеров")

-- Перегруз: `state` объявлен ВНЕ ветки `if unitWeight > 0`, иначе
-- сообщение об отказе ниже читает nil и валит вызов Lua-ошибкой.
local enc = read("lua/autorun/server/sv_grm_encumbrance.lua")
orderOk(enc, "^%s*local state%s*$", "Перегруз: %%%.1f / %%%.1f кг",
    "перегруз: state объявлен до сообщения об отказе")

local launder = read("lua/entities/grm_money_launderer/cl_init.lua")
orderOk(launder, "local lastMenuData", "lastMenuData and lastMenuData%.cooldownLeft",
    "отмывщик: lastMenuData объявлен до 3D2D-таблички")

local dealer = read("lua/entities/sent_vehicle_dealer/cl_init.lua")
orderOk(dealer, "local marketReady = v%.marketReady", "not personal and not marketReady",
    "автодилер: marketReady объявлен до подсказки о рынке")

local bleed = read("lua/autorun/zz_grm_bleedout.lua")
orderOk(bleed, "local amt = dmg:GetDamage%(%)", "damage = math%.floor%(amt",
    "кровотечение: amt объявлен до записи в журнал ран")

local adminMenu = read("lua/autorun/sh_grm_admin_menu.lua")
ok(adminMenu:find("local _nullPanel\n", 1, true) ~= nil
   or adminMenu:find("_nullPanel = setmetatable", 1, true) ~= nil,
    "админ-меню: заглушка панели ссылается на себя корректно")

-------------------------------------------------------------------------
-- 3. ЗАПИСЬ В ГЛОБАЛЫ
-------------------------------------------------------------------------
-- Присвоение без local — общее пространство имён с чужими аддонами.
-- Полностью вычистить исторический код нельзя (на эти имена завязан
-- внешний API), поэтому фиксируем СПИСОК: он не должен расти.
print("\n=== 3. ЗАПИСЬ В ГЛОБАЛЫ: СПИСОК НЕ РАСТЁТ ===")

-- Осознанно публичные имена: внешний API фракций, точек спавна и т.п.
local ALLOWED_GLOBALS = {}
for _, n in ipairs({
    -- публичный API фракций (на него завязаны сторонние наработки)
    "Factions", "FactionsData", "FactionsExt", "FactionsExtData",
    "FactionCharacterChoices", "Invites", "OpenAdminMenu", "OpenLeaderMenu",
    "ApplyModelSettings", "ApplyWeaponsToPlayer", "GetModelDataForPlayer",
    "GetModelsForPlayer", "GetWeaponsForPlayer", "IsModelAllowedForPlayer",
    "OpenExtendedSettings", "OriginalModels", "DefaultModels", "DEFAULT_WEAPONS",
    "CurfewState", "CurfewActive", "CurfewEndTime", "CurfewFaction",
    "CurfewReason", "CurfewStartedAt", "CurfewStartedBy",
    -- точки спавна: внешние тулзы зовут эти функции по имени
    "SpawnPoints", "GlobalSpawnPoints", "AddSpawnPoint", "AddGlobalSpawnPoint",
    "RemoveSpawnPointFromFaction", "RemoveSpawnPointFromDepartment",
    "RemoveSpawnPointFromRole", "RemoveSpawnPointFromSubdept",
    "RemoveGlobalSpawnPoint", "RemoveSpawnPointFromPosition",
    "GetSpawnPointsFor", "SaveSpawnPoints", "LoadSpawnPoints",
    -- терминалы и меню, вызываемые из entity-файлов по имени
    "GRM_CompTerminal_ActiveFrame", "GRM_CompTerminal_ActiveJur",
    "GRM_CompTerminal_BuildExchangeTab", "GRM_CompTerminal_BuildWarrantTab",
    -- волна 8: тело двух копий из cl_init станций поднято в общий модуль
    "GRM_CompTerminal_FillFines", "GRM_CompTerminal_FillWanted",
    "GRM_CompTerminal_FineStatus",
    "GRM_CompTerminal_JurName", "GRM_CompTerminal_JurTag",
    "GRM_CompTerminal_Send", "OpenUnifiedFactionsMenu",
    "GRM_HasVehicleAccess", "VK", "EC_MODULE_PATH",
    -- межмодульные вызовы по имени: эти функции зовут ДРУГИЕ файлы
    -- сборки, локализация их сломает (проверено по месту вызова)
    "broadcastFactionData",          -- зовут duty, roster, faction_fixes
    "GRM_SaveEntities", "GRM_LoadEntities", "GRM_ClearSavedEntities",
    "GRM_ScanServerVehicles", "GRM_GetAccessibleVehicles",
    "GRM_GetAllVehicleClasses", "GRM_MovePlayerToSpawnPoint",
    "GRM_ElectroBatonStunGuard", "GRM_FireAddon", "RPDesc_Descriptions",
    "AddSpawnPointForFaction", "AddSpawnPointForDepartment",
    "AddSpawnPointForRole", "AddSpawnPointForSubdept",
    "AddSpawnPointForPosition", "ClearSpawnPoints",
    "GetSpawnPointsForFaction", "GetSpawnPointsForDepartment",
    "GetSpawnPointsForRole", "GetSpawnPointsForSubdept",
    "GetSpawnPointsForPosition", "GetGlobalSpawnPoints",
    "GetSpawnPointForPlayer",
    -- сторонний Textscreens: правим только у себя, апстрим не трогаем
    "resetall", "resetline",
    -- ключевые таблицы движка/аддона
    "GRM", "ENT", "SWEP", "TOOL", "PANEL", "EasyChat", "textscreenFonts",
}) do ALLOWED_GLOBALS[n] = true end

local leaks = {}
for _, path in ipairs(files) do
    local sets = scan(path)
    for name in pairs(sets) do
        if not ALLOWED_GLOBALS[name] then leaks[#leaks + 1] = path .. " -> " .. name end
    end
end
table.sort(leaks)
ok(#leaks == 0, "новых записей в глобалы нет",
    #leaks > 0 and ("\n     " .. table.concat(leaks, "\n     ")) or nil)

print(("\nGLOBAL HYGIENE: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
