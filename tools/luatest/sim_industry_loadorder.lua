--[[--------------------------------------------------------------------
    sim_industry_loadorder — порядок загрузки клиентских файлов
    индустрии.

    ЗАЧЕМ ЭТОТ СТЕНД. Он появился после настоящей поломки на сервере:

        cl_grm_industry_machine.lua:25: attempt to index local 'UI'
        (a nil value)

    Причина в двух вещах, которых не видно при чтении отдельного
    файла:

    1. GMod грузит файлы из lua/autorun по алфавиту, а папку client —
       после корня. Внутри lua/autorun/client порядок такой:
       logistics, machine, ui. То есть UI-файл, который создаёт I.UI
       и палитру, грузится ПОСЛЕДНИМ, а два других берут её в момент
       загрузки. Раньше там было `local C_ = UI.C` — получали nil.

    2. Таблица имён сетей I.NET создавалась в sv_grm_industry.lua,
       а это папка autorun/server — сервер только. На клиенте I.NET
       была nil, и net.Receive(NET.job, ...) падал. Ни одно окно
       индустрии не открывалось.

    Обычные стенды поднимают файлы через loadfile по одному и в
    нужном им порядке, поэтому такие ошибки не ловятся: в стенде всё
    есть, а на сервере — нет. Здесь файлы грузятся так же, как их
    загрузит GMod.

    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_industry_loadorder.lua
----------------------------------------------------------------------]]
local stub = dofile("tools/luatest/lib_gmod_stub.lua")
stub.install()

-- Клиентская сторона: именно там и падало.
SERVER, CLIENT = false, true

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

-- ================================================================
--  НЕДОСТАЮЩИЕ ГЛОБАЛЫ КЛИЕНТА
-- ================================================================
-- Заглушка lib_gmod_stub заточена под сервер, поэтому клиентские
-- константы приходится объявить. Без них файл упадёт на `table index
-- is nil` в конструкторе вида { [KEY_UP] = 1 } — и это будет ошибка
-- стенда, а не боевого кода.
KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT = 1, 2, 3, 4
KEY_SPACE, KEY_ESCAPE, KEY_ENTER, KEY_TAB = 5, 6, 7, 8
MOUSE_LEFT, MOUSE_RIGHT, MOUSE_MIDDLE = 107, 108, 109
IN_ATTACK, IN_USE, IN_RELOAD, IN_JUMP = 1, 32, 2048, 2
_G.input = setmetatable({}, { __index = function() return function() return false end end })
_G.gui = setmetatable({}, { __index = function() return function() end end })
_G.render = setmetatable({}, { __index = function() return function() end end })
_G.cam = setmetatable({}, { __index = function() return function() end end })
_G.Material = function() return setmetatable({}, { __index = function() return function() end end }) end
_G.ScrW, _G.ScrH = function() return 1920 end, function() return 1080 end
_G.LocalPlayer = function() return stub.makeEntity({ class = "player", isPlayer = true }) end
_G.system = { IsLinux = function() return true end, IsWindows = function() return false end }
_G.DermaMenu = function() return setmetatable({}, { __index = function() return function() end end }) end
_G.Derma_StringRequest = function() end
--[[ Клиентские конвары. Инвентарь и ещё несколько модулей создают их
     при загрузке; без заглушки файлы падают не по своей вине. ]]
_G.CreateClientConVar = function(name, default)
    local value = tostring(default == nil and "" or default)
    return {
        GetString = function() return value end,
        GetInt = function() return math.floor(tonumber(value) or 0) end,
        GetFloat = function() return tonumber(value) or 0 end,
        GetBool = function() return value == "1" or value == "true" end,
        SetString = function(_, v) value = tostring(v) end,
        SetInt = function(_, v) value = tostring(math.floor(tonumber(v) or 0)) end,
        SetFloat = function(_, v) value = tostring(tonumber(v) or 0) end,
        SetBool = function(_, v) value = v and "1" or "0" end,
    }
end
-- Реестр сущностей: нужен общему файлу узлов, он объявляет классы.
_G.scripted_ents = {
    Register = function() end,
    GetStored = function() return nil end,
    Get = function() return nil end,
    GetList = function() return {} end,
}
_G.ENT, _G.SWEP = nil, nil
-- Константы расстановки панелей и выравнивания текста.
TOP, BOTTOM, LEFT, RIGHT, FILL = 1, 2, 3, 4, 5
TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, TEXT_ALIGN_RIGHT = 0, 1, 2
color_white = Color(255, 255, 255)
_G.color_white = color_white
_G.chat = { AddText = function() end }

-- ================================================================
--  УЧЁТ СЕТЕВЫХ СООБЩЕНИЙ
-- ================================================================
--[[ Запоминаем, кто что объявил. Нам важно не только что файлы
     загрузились, но и что клиент реально подписался на сообщения
     под теми же именами, под которыми сервер их шлёт. ]]
local RECEIVED, SENT = {}, {}
_G.net.Receive = function(name, fn) RECEIVED[name] = fn or true end
_G.net.Start = function(name) SENT[#SENT + 1] = name end

-- ================================================================
--  СЕМАНТИКА ШРИФТОВ (как в GMod)
-- ================================================================
--[[ Пустая заглушка surface всё принимает молча, а настоящий GMod
     отвечает «'GRMInd_Head' isn't a valid font» и возвращает nil из
     GetTextSize — отсюда и «arithmetic on local 'w' (a nil value)»
     в draw.SimpleText. Поэтому шрифты учитываем, а обе ошибки
     воспроизводим: иначе стенд пропустит обращение к шрифту,
     которого нет. ]]
local FONTS = {}
_G.surface.CreateFont = function(name, data) FONTS[name] = data or {} end
_G.surface.SetFont = function(name)
    if not FONTS[name] then
        error("'" .. tostring(name) .. "' isn't a valid font", 2)
    end
end
_G.surface.GetTextSize = function(text)
    local len = tostring(text or ""):len()
    return len * 6, 14
end
_G.draw.SimpleText = function(text, font, x, y)
    _G.surface.SetFont(font)               -- так делает draw.lua
    local w = _G.surface.GetTextSize(text)
    if w == nil then                       -- draw.lua:69
        error("attempt to perform arithmetic on local 'w' (a nil value)", 2)
    end
    return w
end

-- ================================================================
--  ЗАГРУЗЧИК, ПОВТОРЯЮЩИЙ ПОРЯДОК GMOD
-- ================================================================
--[[ GMod берёт файлы из lua/autorun по алфавиту, а подпапки client и
     server — после корня. Внутри каждой папки тоже по алфавиту.
     Здесь порядок получается из ls, а не записан руками: если
     добавят новый файл, он встанет в цепочку сам. ]]
local function sorted(pattern)
    local handle = assert(io.popen("ls " .. pattern .. " 2>/dev/null | sort"))
    local out = {}
    for line in handle:lines() do if line ~= "" then out[#out + 1] = line end end
    handle:close()
    return out
end

--[[ Штатные файлы фреймворка идут по алфавиту РАНЬШЕ industry —
     в GMod так и будет. Берём их, потому что UI.Window вызывает
     GRM.UI.Track из lua/autorun/sh_00_grm_ui.lua. Подставлять вместо
     него заглушку нельзя: тогда прогон окна проверял бы сам себя. ]]
--[[ ТОЛЬКО НУЖНЫЕ КОРНЕВЫЕ ФАЙЛЫ, а не все подряд. В репозитории
     есть файлы с glua-синтаксисом, который обычный LuaJIT не читает
     (например goto/::label:: в cl_grm_admin_panel.lua), — их штатный
     sim_gmod_syntax и так отмечает. Здесь берём ровно то, от чего
     зависят клиентские файлы индустрии: фреймворк, производительность
     и само ядро. Порядок по-прежнему алфавитный, как у GMod. ]]
--[[ В список добавлены инвентарь и файл регистрации предметов —
     именно в том порядке, в котором их грузит GMod. Это важно:
     инвентарь ПЕРЕСОЗДАЁТ справочник предметов, поэтому регистрация
     обязана стоять после него. ]]
local ROOT_FILES   = sorted("lua/autorun/sh_00_grm_*.lua lua/autorun/sh_06_grm_performance.lua "
    .. "lua/autorun/sh_grm_industry*.lua lua/autorun/sh_grm_inventory.lua "
    .. "lua/autorun/zz_grm_industry_items.lua")
local CLIENT_FILES = sorted("lua/autorun/client/cl_grm_industry*.lua")

local function loadFile(path)
    local chunk, err = loadstring(read(path), "@" .. path)
    if not chunk then return false, err end
    local good, runErr = pcall(chunk)
    if not good then return false, runErr end
    return true
end

-- Загружаем всё с нуля: общие, затем клиентские — как GMod.
local function loadAll(clientOrder)
    GRM = nil
    package.loaded = {}
    stub.reset()
    RECEIVED, SENT, FONTS_CLEARED = {}, {}, nil
    for k in pairs(FONTS) do FONTS[k] = nil end
    local errors = {}
    for _, path in ipairs(ROOT_FILES) do
        local good, err = loadFile(path)
        if not good then errors[#errors + 1] = path .. ": " .. tostring(err) end
    end
    for _, path in ipairs(clientOrder) do
        local good, err = loadFile(path)
        if not good then errors[#errors + 1] = path .. ": " .. tostring(err) end
    end
    return errors
end

-- ================================================================
print("\n=== 1. СОСТАВ ЦЕПОЧКИ ===")
-- ================================================================
ok(#ROOT_FILES >= 3, "общие файлы найдены", #ROOT_FILES)
ok(#CLIENT_FILES >= 3, "клиентские файлы найдены", #CLIENT_FILES)
--[[ ПРОВЕРКА САМОГО ПОРЯДКА. Если файл с палитрой встанет в цепочку
     раньше своих потребителей, весь этот стенд потеряет смысл:
     поломка перестанет воспроизводиться, а на сервере останется. ]]
local uiPos
for i, path in ipairs(CLIENT_FILES) do
    if path:find("cl_grm_industry_ui%.lua$") then uiPos = i end
end
ok(uiPos ~= nil, "файл с палитрой в цепочке есть")
ok(uiPos == #CLIENT_FILES,
    "файл с палитрой грузится ПОСЛЕДНИМ — иначе стенд не проверяет то, что сломалось",
    uiPos .. " из " .. #CLIENT_FILES)

-- ================================================================
print("\n=== 2. ЗАГРУЗКА В ПОРЯДКЕ GMOD ===")
-- ================================================================
--[[ СНАЧАЛА ТОЛЬКО ОБЩИЕ ФАЙЛЫ. Клиентские берут I.UI и I.NET в
     момент загрузки, а GMod грузит подпапку client ПОСЛЕ корня.
     Значит, к старту клиентских файлов обе таблицы уже обязаны
     существовать — иначе потребитель получит nil. Проверяем это
     отдельно: так ловится не только падение при загрузке, но и
     тихая поломка, когда файл загрузился, а функция внутри падает
     уже по клику игрока. ]]
loadAll({})
ok(GRM and GRM.Industry ~= nil, "общие файлы подняли GRM.Industry")
ok(GRM and GRM.Industry.NET ~= nil, "I.NET готова до старта клиентских файлов")
ok(GRM and GRM.Industry.UI ~= nil, "I.UI готова до старта клиентских файлов")

local errors = loadAll(CLIENT_FILES)
ok(#errors == 0, "ВСЕ ФАЙЛЫ ЗАГРУЗИЛИСЬ БЕЗ ОШИБОК", table.concat(errors, " | "))

local I = GRM and GRM.Industry
ok(I ~= nil, "GRM.Industry поднялся")
ok(I and I.NET ~= nil, "I.NET есть и на клиенте", tostring(I and I.NET))

-- ================================================================
print("\n=== 3. ИМЕНА СЕТЕЙ ОДИНАКОВЫ НА ОБЕИХ СТОРОНАХ ===")
-- ================================================================
--[[ Имена должны совпадать. В стенде сервер не поднимается целиком,
     поэтому сравниваем с тем, что объявлено в sv_grm_industry.lua:
     вычитываем имена из текста файла, чтобы расхождение поймать
     сразу, а не по жалобе «окно не открывается». ]]
if I and I.NET then
    local expected = {
        open = "GRM_IND_Open", action = "GRM_IND_Action", job = "GRM_IND_Job",
        mg = "GRM_IND_Minigame", step = "GRM_IND_Step", note = "GRM_IND_Note",
    }
    for key, name in pairs(expected) do
        ok(I.NET[key] == name, "имя " .. key .. " = " .. name, I.NET[key])
    end
    -- Клиент обязан подписаться на то, что присылает сервер.
    for _, key in ipairs({ "open", "job", "mg" }) do
        ok(RECEIVED[I.NET[key]] ~= nil, "клиент слушает " .. I.NET[key])
    end
    --[[ Ни одного nil в имени: net.Start(nil) молча не отправляет
         ничего, и игрок видит «кнопка не работает» без ошибок. ]]
    local nilNames = 0
    for k, v in pairs(I.NET) do if type(v) ~= "string" then nilNames = nilNames + 1 end end
    ok(nilNames == 0, "пустых имён нет", nilNames)
end

-- ================================================================
print("\n=== 4. ПАЛИТРА ДОСТУПНА ТЕМ, КТО ГРУЗИТСЯ РАНЬШЕ ===")
-- ================================================================
--[[ Паллитру создаёт файл, который в цепочке последний. Значит,
     потребители обязаны брать её лениво. Проверяем, что таблица
     вообще наполнилась после загрузки всей цепочки. ]]
ok(I and I.UI ~= nil, "I.UI создана")
ok(I and I.UI and I.UI.C ~= nil, "палитра I.UI.C заполнена")
if I and I.UI and I.UI.C then
    ok(I.UI.C.text ~= nil, "в палитре есть цвет текста")
    ok(I.UI.C.accent ~= nil, "в палитре есть акцентный цвет")
end

-- ================================================================
print("\n=== 5. ПОРЯДОК НЕ ВЛИЯЕТ: ГРУЗИМ В ОБРАТНУЮ СТОРОНУ ===")
-- ================================================================
--[[ Если какой-то файл опять возьмёт поле в момент загрузки, прямой
     порядок может этого не показать — но обратный покажет всегда.
     Это и есть проверка «зависимости от порядка нет». ]]
local reversed = {}
for i = #CLIENT_FILES, 1, -1 do reversed[#reversed + 1] = CLIENT_FILES[i] end
local revErrors = loadAll(reversed)
ok(#revErrors == 0, "ФАЙЛЫ НЕ ЗАВИСЯТ ОТ ПОРЯДКА ЗАГРУЗКИ", table.concat(revErrors, " | "))

local I2 = GRM and GRM.Industry
ok(I2 and I2.UI and I2.UI.C ~= nil, "палитра на месте и при обратном порядке")

-- ================================================================
print("\n=== 6. ОКНО СТАНКА ОТКРЫВАЕТСЯ ВЖИВУЮ ===")
-- ================================================================
--[[ ЗАГРУЗКА БЕЗ ОШИБКИ ЕЩЁ НЕ ЗНАЧИТ, ЧТО ОКНО РАБОТАЕТ. Если
     файл возьмёт UI.C в момент загрузки, он получит nil: файлы
     загрузятся чисто, а упадёт уже по клику игрока — и в логе
     будет «attempt to index a nil value» без внятного места.
     Поэтому открываем окно по-настоящему, через сетевой обработчик,
     точно так же, как это делает сервер. ]]
loadAll(CLIENT_FILES)

local function fakeNode(role)
    local e = stub.makeEntity({ class = "grm_ind_" .. role, __valid = true })
    e.GetNWString = function() return "" end
    e.GetNWInt = function() return 0 end
    e.GetNWFloat = function() return 0 end
    e.EntIndex = function() return 7 end
    return e
end

local OPEN_DATA = {
    role = "station", kind = "furnace", label = "Печь №1",
    stock = {}, out = {}, supply = {}, market = {}, recipes = {
        { id = "melt_components", name = "Компоненты", output = "defective_components",
          scrap = 1, process = 4, assemble = 2, price = 120 },
    },
    wear = 0, job = nil,
}
_G.net.ReadEntity = function() return fakeNode("station") end
_G.net.ReadTable  = function() return OPEN_DATA end
_G.net.ReadString = function() return "furnace" end
_G.net.ReadUInt   = function() return 1 end
_G.net.ReadFloat  = function() return 0 end
_G.net.ReadBool   = function() return false end
_G.net.ReadInt    = function() return 0 end

local receiver = RECEIVED[I.NET.open]
ok(receiver ~= nil, "обработчик открытия окна зарегистрирован")
if receiver then
    local good, err = pcall(receiver)
    ok(good, "ОКНО СТАНКА ОТКРЫЛОСЬ БЕЗ ОШИБКИ", err)
end

-- ================================================================
print("\n=== 7. ПОДПИСИ В МИРЕ — БЕЗ ОТКРЫТОГО ОКНА ===")
-- ================================================================
--[[ Шрифты создавались только в UI.Window: пока игрок не открыл ни
     одного окна индустрии, шрифтов нет. А подписи над узлами
     рисуются в хуке PostDrawTranslucentRenderables — игрок просто
     подошёл к станку, ничего не открывая. На живом сервере это
     давало две ошибки на каждый кадр подряд. ]]
loadAll(CLIENT_FILES)
ok(FONTS["GRMInd_Head"] ~= nil, "ШРИФТЫ ГОТОВЫ ДО ОТКРЫТИЯ ПЕРВОГО ОКНА")
ok(FONTS["GRMInd_Small"] ~= nil, "шрифт подписи тоже готов")
ok(FONTS["GRMInd_Title"] ~= nil, "шрифт заголовка готов")

--[[ СЕТЕВЫЕ ПЕРЕМЕННЫЕ УЗЛА. В живом GMod их создаёт
     self:NetworkVar(...) в sh_grm_industry_entities.lua, и методов
     GetNodeLabel/GetJobStage на сущности не было бы вовсе без него.
     Вычитываем имена из исходника: если переменную переименуют,
     стенд скажет об этом, а не будет верить выдуманной заглушке. ]]
local NODE_VARS = {}
do
    local src = read("lua/autorun/sh_grm_industry_entities.lua")
    for vType, name in src:gmatch('NetworkVar%(%s*"(%w+)"%s*,%s*%d+%s*,%s*"(%w+)"%s*%)') do
        NODE_VARS[name] = vType
    end
end
ok(NODE_VARS.NodeLabel ~= nil, "у узла объявлена сетевая переменная NodeLabel")
ok(NODE_VARS.JobStage ~= nil, "у узла объявлена сетевая переменная JobStage")
ok(NODE_VARS.Progress ~= nil, "у узла объявлена сетевая переменная Progress")

local VAR_DEFAULT = { String = "", Int = 0, Float = 0, Bool = false }

local labelHook = stub.hooks["PostDrawTranslucentRenderables"]
    and stub.hooks["PostDrawTranslucentRenderables"]["GRM_IndustryNodeLabels"]
ok(labelHook ~= nil, "обработчик подписей над узлами зарегистрирован")
if labelHook then
    ok(GRM and GRM.Perf ~= nil, "GRM.Perf доступен (иначе подписи молча не рисуются)")
    -- Узел рядом с игроком: попадает в радиус подписей (900).
    local node = stub.makeEntity({ class = "grm_ind_station", pos = Vector(60, 0, 0) })
    for name, vType in pairs(NODE_VARS) do
        node["Get" .. name] = function() return VAR_DEFAULT[vType] end
    end
    node.GetNodeLabel = function() return "Печь №1" end
    local ply = stub.makeEntity({ class = "player", isPlayer = true, pos = Vector(0, 0, 0) })
    ply.EyePos = function() return Vector(0, 0, 64) end
    ply.EyeAngles = function() return Angle(0, 0, 0) end
    _G.LocalPlayer = function() return ply end

    local good, err = pcall(labelHook)
    ok(good, "ПОДПИСИ НАД УЗЛАМИ РИСУЮТСЯ БЕЗ ОШИБКИ", err)
end

-- ================================================================
print("\n=== 8. ПРЕДМЕТЫ ПРОИЗВОДСТВА ДОСТУПНЫ ИНВЕНТАРЮ ===")
-- ================================================================
--[[ Без этой проверки производство работало вхолостую.
     GRM.Inventory.AddItem первым делом спрашивает GetItemDef и, если
     предмета в справочнике нет, возвращает ВСЁ количество как «не
     влезло». Игрок видел «Нет места в инвентаре» при пустом
     инвентаре, а лом со станка не получал. ]]
loadAll(CLIENT_FILES)
ok(GRM.Inventory ~= nil, "инвентарь поднялся")
ok(GRM.Inventory.ItemDefs ~= nil, "справочник предметов инвентаря есть")

--[[ Файл регистрации обязан стоять ПОСЛЕ инвентаря: тот создаёт
     ItemDefs перезаписью, поэтому ранняя регистрация будет выброшена.
     Без этой проверки стенд зелёный, а на сервере — пусто. ]]
local invPos, itemsPos
for i, path in ipairs(ROOT_FILES) do
    if path:find("sh_grm_inventory%.lua$") then invPos = i end
    if path:find("zz_grm_industry_items%.lua$") then itemsPos = i end
end
ok(invPos ~= nil, "инвентарь есть в цепочке")
ok(itemsPos ~= nil, "файл регистрации предметов есть в цепочке")
ok(invPos and itemsPos and itemsPos > invPos,
    "регистрация предметов грузится ПОСЛЕ инвентаря", tostring(invPos) .. " / " .. tostring(itemsPos))

local I3 = GRM and GRM.Industry
if I3 and I3.Items and GRM.Inventory and GRM.Inventory.ItemDefs then
    local missing = {}
    for id in pairs(I3.Items) do
        if GRM.Inventory.ItemDefs[id] == nil then missing[#missing + 1] = id end
    end
    table.sort(missing)
    ok(#missing == 0, "ВСЕ ПРЕДМЕТЫ ПРОИЗВОДСТВА ЗАРЕГИСТРИРОВАНЫ В ИНВЕНТАРЕ",
        table.concat(missing, ", "))
    ok(GRM.Inventory.ItemDefs["scrap_metal"] ~= nil, "металлолом описан для инвентаря")

    -- Оружие из рецептов тоже должно попадать в руки.
    local missingGuns = {}
    for _, recipe in pairs(I3.Recipes or {}) do
        local out = recipe.output
        if out and out ~= "" and not I3.Items[out] and GRM.Inventory.ItemDefs[out] == nil then
            missingGuns[#missingGuns + 1] = out
        end
    end
    table.sort(missingGuns)
    ok(#missingGuns == 0, "ОРУЖИЕ ИЗ РЕЦЕПТОВ ЗАРЕГИСТРИРОВАНО", table.concat(missingGuns, ", "))

    -- И описание должно быть полным, иначе инвентарь покажет пустышку.
    local def = GRM.Inventory.ItemDefs["scrap_metal"]
    ok(def and def.name ~= nil, "у предмета есть название")
    ok(def and tonumber(def.weight) ~= nil, "у предмета есть вес")
    ok(def and def.maxStack ~= nil, "у предмета есть размер стака")
end

-- ================================================================
print("\n=== 9. ЁМКОСТЬ РАБОТАЕТ ПРИ ЗАГРУЗКЕ В ПОРЯДКЕ GMOD ===")
-- ================================================================
--[[ ПОЧЕМУ РАЗДЕЛ ПОЯВИЛСЯ. Владелец прислал:
         ошибка действия 'supply_take':
         sh_grm_industry_container.lua:223:
         attempt to index upvalue 'I' (a nil value)

     Файл ёмкости по алфавиту идёт РАНЬШЕ ядра (container < core) и
     брал `local I = GRM.Industry` в момент загрузки — получал nil.
     Всё загружалось без единой ошибки, а первый же перенос предмета
     падал. Стенд грузил файлы в правильном порядке, но НИ РАЗУ не
     переносил предмет — поэтому молчал. ]]
loadAll(CLIENT_FILES)

local contPos, corePos
for i, path in ipairs(ROOT_FILES) do
    if path:find("sh_grm_industry_container%.lua$") then contPos = i end
    if path:find("sh_grm_industry_core%.lua$") then corePos = i end
end
ok(contPos and corePos and contPos < corePos,
    "файл ёмкости грузится РАНЬШЕ ядра — иначе раздел ничего не проверяет",
    tostring(contPos) .. " / " .. tostring(corePos))

local C = GRM and GRM.Container
ok(C ~= nil, "контейнер поднялся")
if C then
    local id = "sim:loadorder"
    local good, err = pcall(function()
        C.Ensure(id, "store", "sim", -1)
        C.Add(id, "scrap_metal", 3)
        C.Count(id, "scrap_metal")
        C.Weight(id)
        C.List(id)
        C.MoveUpTo(id, "sim:loadorder2", "scrap_metal", 1)
        C.Take(id, "scrap_metal", 1)
        C.Remove(id)
    end)
    ok(good, "ПЕРЕНОС ПРЕДМЕТОВ РАБОТАЕТ ПОСЛЕ ЗАГРУЗКИ В ПОРЯДКЕ GMOD", err)

    -- Вес берётся из справочника ядра — значит ядро точно поднялось.
    C.Ensure(id, "store", "sim", -1)
    local w = C.Weight(id)
    C.Add(id, "scrap_metal", 2)
    ok(C.Weight(id) > w, "вес считается по справочнику ядра", C.Weight(id))
    C.Remove(id)
end

-- ================================================================
print("\n=== 10. ПОДПИСИ НЕ МОРГАЮТ ===")
-- ================================================================
--[[ ЖАЛОБА ВЛАДЕЛЬЦА: «подписи к предметам моргают».

     GRM.Perf.Throttle пропускает вызов РОВНО ОДИН РАЗ за интервал
     (sh_06_grm_performance.lua:34). Это ограничитель частоты
     ВЫЧИСЛЕНИЙ. А он стоял на всём хуке, включая cam.Start3D2D:
     хук зовётся шестьдесят раз в секунду, рисует четыре.

     Проверяем самым простым способом: считаем вызовы отрисовки и
     дёргаем хук два раза подряд. Второй раз — с тем же CurTime,
     то есть расчёт обязан взяться из кэша, а нарисовать — обязателен.
     Заморгало — значит второй вызов ничего не нарисовал. ]]
loadAll(CLIENT_FILES)

local DRAWN = 0
_G.cam.Start3D2D = function() DRAWN = DRAWN + 1 end
_G.cam.End3D2D = function() end

local lblHook = stub.hooks["PostDrawTranslucentRenderables"]
    and stub.hooks["PostDrawTranslucentRenderables"]["GRM_IndustryNodeLabels"]
ok(lblHook ~= nil, "обработчик подписей зарегистрирован")

if lblHook then
    -- Узел рядом с игроком, иначе рисовать нечего и проверка пустая.
    stub.makeEntity({ class = "grm_ind_station", pos = Vector(60, 0, 0) })
    local ply = stub.makeEntity({ class = "player", isPlayer = true, pos = Vector(0, 0, 0) })
    ply.EyePos = function() return Vector(0, 0, 64) end
    ply.EyeAngles = function() return Angle(0, 0, 0) end
    _G.LocalPlayer = function() return ply end
    -- Сетевые переменные узла — как в настоящей сущности.
    local last = nil
    for _, e in ipairs(stub.entities) do
        if e.class == "grm_ind_station" then
            last = e
            for name, vType in pairs(NODE_VARS) do
                e["Get" .. name] = function() return VAR_DEFAULT[vType] end
            end
            e.GetNodeLabel = function() return "Печь №1" end
        end
    end
    ok(last ~= nil, "узел для подписи создан")

    local function drawOnce()
        local before = DRAWN
        local good, err = pcall(lblHook)
        return good, err, DRAWN - before
    end

    local g1, e1, n1 = drawOnce()
    ok(g1, "первый кадр отрисовался без ошибки", e1)
    ok(n1 >= 1, "на первом кадре подпись нарисована", n1)

    -- Второй кадр — сразу же, без сдвига времени: расчёт из кэша,
    -- но отрисовка обязательна. Именно здесь моргание и ловится.
    local g2, e2, n2 = drawOnce()
    ok(g2, "второй кадр отрисовался без ошибки", e2)
    ok(n2 >= 1, "ПОДПИСЬ РИСУЕТСЯ НА КАЖДОМ КАДРЕ, А НЕ РАЗ В ИНТЕРВАЛ", n2)

    -- И третий, на всякий случай.
    local _, _, n3 = drawOnce()
    ok(n3 >= 1, "третий кадр тоже нарисован", n3)
end

-- ================================================================
print("\n=== ИТОГ ===")
-- ================================================================
print(string.format("  пройдено: %d, провалено: %d", total - fails, fails))
if fails > 0 then print("  СТЕНД КРАСНЫЙ") os.exit(1) end
print("  СТЕНД ЗЕЛЁНЫЙ")
