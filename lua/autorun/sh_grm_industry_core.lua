--[[--------------------------------------------------------------------
    GRM Industry Core — общее ядро производства и логистики.

    Здесь ТОЛЬКО данные и чистые функции: ни одного вызова GMod на
    этапе загрузки файла. Сделано так намеренно: стенд может поднять
    файл через loadfile в пустом окружении и проверять боевые функции,
    а не их пересказ.

    Серверная логика — sv_grm_industry.lua и sv_grm_industry_logistics.lua.
    Клиент — cl_grm_industry_*.lua.
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Industry = GRM.Industry or {}
local I = GRM.Industry

I.Version = "1.0.0"

-- ================================================================
--  ИМЕНА СЕТЕВЫХ СООБЩЕНИЙ
-- ================================================================
--[[ Таблица живёт в общем ядре, потому что клиент и сервер обязаны
     называть сообщения ОДИНАКОВО. Раньше она создавалась в
     sv_grm_industry.lua — а это папка autorun/server, то есть
     сервер только. На клиенте I.NET была nil, и net.Receive(
     NET.job, ...) падал при загрузке: ни одно окно индустрии не
     открывалось, а на любой клик отвечало net.Start(nil). ]]
I.NET = I.NET or {
    open    = "GRM_IND_Open",
    action  = "GRM_IND_Action",
    job     = "GRM_IND_Job",
    mg      = "GRM_IND_Minigame",
    step    = "GRM_IND_Step",
    note    = "GRM_IND_Note",
}

-- ================================================================
--  КЛИЕНТСКИЙ ИНТЕРФЕЙС
-- ================================================================
--[[ Таблицу создаём здесь, а палитру, шрифты и окна заполняет
     cl_grm_industry_ui.lua. Файлы в lua/autorun/client грузятся по
     алфавиту: logistics и machine идут РАНЬШЕ, чем ui. Создание
     таблицы в ядре снимает зависимость от этого порядка. ]]
I.UI = I.UI or {}

-- ================================================================
--  КОНФИГУРАЦИЯ
-- ================================================================
I.Config = I.Config or {
    -- Радиус, в котором работник считается «у станка».
    WorkRadius      = 220,
    -- Сколько секунд можно не возвращаться, прежде чем работа встанет.
    GraceSeconds    = 5,
    -- Частота проверки присутствия.
    TickInterval    = 0.5,
    -- Через сколько секунд простоя задача закрывается с возвратом сырья.
    AbandonAfter    = 24 * 3600,

    -- Износ станка за один запуск (по виду рецепта).
    WearPerCraft    = 0.8,
    WearCap         = 100,

    -- Навык: сколько допуск даёт один уровень и где потолок.
    SkillStep       = 0.01,   -- +1% к окну мини-игры за уровень
    SkillCap        = 0.25,

    -- Мини-игры. window — сколько секунд даётся на шаг.
    Minigame = {
        components = { kind = "rhythm",   steps = 5, window = 1.6 },
        gpu        = { kind = "trace",    steps = 6, window = 1.4 },
        weapon     = { kind = "assembly", steps = 7, window = 1.3 },
        furnace    = { kind = "none",     steps = 0, window = 0 },
    },

    -- Штрафы мини-игры: ошибка по времени и полный промах.
    PenaltyPerStepWindow = 16,   -- (|ошибка| / окно) × это
    PenaltyPerMiss       = 20,
    -- Защита от «прощёлкал быстрее чем возможно»: минимум секунд на шаг.
    MinSecondsPerStep    = 0.25,

    -- Пороги качества (с учётом износа станка).
    Quality = {
        Master = 90,
        Good   = 60,
        Rough  = 30,
        -- Добавка к порогу мастера за единицу износа. При износе 100%
        -- порог становится 100 и «с клеймом мастера» получить нельзя:
        -- убитый станок не выдаёт шедевров, сколько ни старайся.
        WearPenalty = 0.1,
    },

    Outcome = {
        master  = { label = "С клеймом мастера", priceMul = 1.10, refund = 0 },
        good    = { label = "Обычное изделие",   priceMul = 1.00, refund = 0 },
        rough   = { label = "Требует доводки",   priceMul = 0.60, refund = 0 },
        defect  = { label = "Брак",              priceMul = 0,    refund = 0.50 },
    },

    -- Логистика.
    Logistics = {
        BasePercent   = 0.08,   -- базовый процент от ценности груза
        DistanceFull  = 20000,  -- дистанция, дающая максимальную надбавку
        DistanceBonus = 0.30,   -- максимальная надбавка за расстояние
        RiskDefault   = 1.0,
        RiskMax       = 1.6,
        LateMultiplier = 0.6,
        DefaultDeadline = 30 * 60,
        ExpireAfter     = 6 * 3600,
        MinReward       = 50,
    },

    -- Источники сырья.
    Supply = {
        StartStock  = 25,
        MaxStock    = 60,
        RefillEvery = 60,
        RefillAmount = 3,
        BuyPrice     = 60,      -- цена покупки лома у источника, если включено
    },

    -- Вес в килограммах на единицу предмета.
    FallbackWeight = 1.0,
}

-- ================================================================
--  ПРЕДМЕТЫ
-- ================================================================
--[[ Единый справочник того, что ходит по производству и логистике.
     Инвентарь (GRM.Inventory) остаётся владельцем предметов игрока —
     этот справочник только описывает вес и цену для цеха и рейсов. ]]
I.Items = I.Items or {
    scrap_metal            = { name = "Металлолом",       weight = 1.2, price = 60 },
    components_box         = { name = "Ящик комплектующих", weight = 3.0, price = 400 },
    gpu_basic              = { name = "Базовая видеокарта", weight = 1.5, price = 700 },
    gpu_mid                = { name = "Средняя видеокарта", weight = 1.8, price = 1500 },
    gpu_premium            = { name = "Премиум видеокарта", weight = 2.2, price = 3200 },
    defective_components   = { name = "Бракованные комплектующие", weight = 1.0, price = 0, defect = true },
    defective_gpu          = { name = "Бракованная видеокарта",    weight = 1.5, price = 0, defect = true },
    defective_weapon_parts = { name = "Бракованные оружейные детали", weight = 2.0, price = 0, defect = true },
    item_repair_kit        = { name = "Ремкомплект",      weight = 1.0, price = 300 },
}

-- ================================================================
--  РЕЦЕПТЫ
-- ================================================================
--[[ Поле `scrap` — суммарный лом с учётом вложенных ящиков. Оно же
     основа баланса: выгода на единицу сырья НЕ должна расти монотонно,
     иначе производят только верхнюю строку (баг старого цеха). ]]
I.Recipes = I.Recipes or {
    components_box = {
        id = "components_box", station = "components",
        name = "Ящик комплектующих",
        input = { scrap_metal = 5 }, output = "components_box", outputCount = 1,
        process = 8, assemble = 14, wear = 0.5, scrap = 5,
    },

    gpu_basic = {
        id = "gpu_basic", station = "gpu",
        name = "Базовая видеокарта",
        input = { components_box = 1 }, output = "gpu_basic", outputCount = 1,
        process = 10, assemble = 16, wear = 0.8, scrap = 5,
    },
    gpu_mid = {
        id = "gpu_mid", station = "gpu",
        name = "Средняя видеокарта",
        input = { components_box = 2 }, output = "gpu_mid", outputCount = 1,
        process = 14, assemble = 24, wear = 1.2, scrap = 10,
    },
    gpu_premium = {
        id = "gpu_premium", station = "gpu",
        name = "Премиум видеокарта",
        input = { components_box = 4 }, output = "gpu_premium", outputCount = 1,
        process = 18, assemble = 34, wear = 1.6, scrap = 20,
    },

    arccw_makarov = {
        id = "arccw_makarov", station = "weapon",
        name = "Макаров", weapon = "arccw_makarov",
        input = { scrap_metal = 5, components_box = 1 }, output = "arccw_makarov",
        outputCount = 1, process = 12, assemble = 20, wear = 0.8,
        price = 2500, scrap = 10,
    },
    arccw_p228 = {
        id = "arccw_p228", station = "weapon",
        name = "P228", weapon = "arccw_p228",
        input = { scrap_metal = 7, components_box = 1 }, output = "arccw_p228",
        outputCount = 1, process = 14, assemble = 24, wear = 1.0,
        price = 3400, scrap = 12,
    },
    arccw_p90 = {
        id = "arccw_p90", station = "weapon",
        name = "P90", weapon = "arccw_p90",
        input = { scrap_metal = 13, components_box = 3 }, output = "arccw_p90",
        outputCount = 1, process = 18, assemble = 32, wear = 1.4,
        price = 8000, scrap = 28,
    },
    arccw_m4a1 = {
        id = "arccw_m4a1", station = "weapon",
        name = "M4A1", weapon = "arccw_m4a1",
        input = { scrap_metal = 19, components_box = 3 }, output = "arccw_m4a1",
        outputCount = 1, process = 20, assemble = 40, wear = 1.6,
        price = 10000, scrap = 34,
    },
    arccw_rpg7 = {
        id = "arccw_rpg7", station = "weapon",
        name = "РПГ-7", weapon = "arccw_rpg7",
        input = { scrap_metal = 40, components_box = 6 }, output = "arccw_rpg7",
        outputCount = 1, process = 24, assemble = 56, wear = 2.0,
        price = 18000, scrap = 70,
    },

    melt_components = {
        id = "melt_components", station = "furnace",
        name = "Переплавить бракованные комплектующие",
        input = { defective_components = 1 }, output = "scrap_metal", outputCount = 2,
        process = 0, assemble = 8, wear = 0.4, scrap = -2,
    },
    melt_weapon = {
        id = "melt_weapon", station = "furnace",
        name = "Переплавить бракованные оружейные детали",
        input = { defective_weapon_parts = 1 }, output = "scrap_metal", outputCount = 4,
        process = 0, assemble = 12, wear = 0.6, scrap = -4,
    },
    melt_gpu = {
        id = "melt_gpu", station = "furnace",
        name = "Переплавить бракованную видеокарту",
        input = { defective_gpu = 1 }, output = "scrap_metal", outputCount = 5,
        process = 0, assemble = 16, wear = 0.8, scrap = -5,
    },
}

-- Роли узлов цеха и логистики. Данные, а не регистрация: серверная
-- логика обязана видеть их и без загрузки файла сущностей.
I.NodeRoles = I.NodeRoles or {
    supply    = { name = "Источник сырья",        model = "models/props_junk/trashdumpster01a.mdl" },
    station   = { name = "Станок",                model = "models/mosi/fallout4/furniture/workstations/workshopbench.mdl" },
    storage   = { name = "Склад цеха",            model = "models/props_junk/wood_crate002a.mdl" },
    market    = { name = "Точка сбыта",           model = "models/Humans/Group03/male_03.mdl" },
    -- Маркер точки отправления — полупрозрачная труба: её же использует
    -- чекпоинт квестов, и владелец указывал этот вид прямо.
    depot     = { name = "Точка отправления",     model = "models/hunter/tubes/tube2x2x1.mdl" },
    warehouse = { name = "Склад фракции",         model = "models/props_junk/wood_crate002a.mdl" },
    armory    = { name = "Оружейный шкаф фракции", model = "models/props_lab/lockers.mdl" },
}

-- Ёмкость по роли, кг. -1 — без лимита.
I.RoleCapacity = I.RoleCapacity or {
    supply    = -1,
    station   = 400,     -- вход станка
    storage   = 2000,
    market    = -1,
    depot     = 3000,
    warehouse = 6000,
    armory    = 1500,
}

I.Stations = I.Stations or {
    components = { name = "Станок комплектующих", model = "models/mosi/fallout4/furniture/workstations/workshopbench.mdl" },
    gpu        = { name = "Станок сборки видеокарт", model = "models/props_wasteland/controlroom_desk001a.mdl" },
    weapon     = { name = "Кустарный оружейный верстак", model = "models/mosi/fallout4/furniture/workstations/weaponworkbench01.mdl" },
    furnace    = { name = "Печь переплавки брака", model = "models/props_forest/furnace01.mdl" },
}

-- Какой брак получается при провале на каждом станке.
I.DefectFor = I.DefectFor or {
    components = "defective_components",
    gpu        = "defective_gpu",
    weapon     = "defective_weapon_parts",
}

-- ================================================================
--  СПРАВОЧНИК: вес и цена
-- ================================================================
function I.ItemDef(itemID)
    return I.Items[tostring(itemID or "")]
end

function I.WeightOf(itemID)
    local def = I.ItemDef(itemID)
    if def then return tonumber(def.weight) or I.Config.FallbackWeight end
    -- Оружие описано в рецепте, а не в справочнике предметов.
    local recipe = I.Recipes[tostring(itemID or "")]
    if recipe and recipe.price then return 4.0 end
    return I.Config.FallbackWeight
end

function I.PriceOf(itemID)
    local def = I.ItemDef(itemID)
    if def and def.price then return tonumber(def.price) or 0 end
    local recipe = I.Recipes[tostring(itemID or "")]
    if recipe and recipe.price then return tonumber(recipe.price) or 0 end
    return 0
end

function I.NameOf(itemID)
    local def = I.ItemDef(itemID)
    if def and def.name then return def.name end
    local recipe = I.Recipes[tostring(itemID or "")]
    if recipe and recipe.name then return recipe.name end
    return tostring(itemID or "?")
end

function I.RecipeFor(station, recipeID)
    local recipe = I.Recipes[tostring(recipeID or "")]
    if not recipe then return nil end
    if recipe.station ~= tostring(station or "") then return nil end
    return recipe
end

function I.RecipesFor(station)
    local out = {}
    for id, recipe in pairs(I.Recipes) do
        if recipe.station == tostring(station or "") then
            out[#out + 1] = { id = id, name = recipe.name, recipe = recipe }
        end
    end
    table.sort(out, function(a, b) return (a.name or a.id) < (b.name or b.id) end)
    return out
end

-- ================================================================
--  КАЧЕСТВО
-- ================================================================
--[[ ЧИСТАЯ ФУНКЦИЯ. steps — массив результатов шагов мини-игры:
     { error = секунды отклонения (0..window), missed = bool }.
     Возвращает качество 0..100.

     Формула намеренно мягкая: промах стоит дороже, чем неточность, но
     даже серия промахов не обнуляет всё мгновенно — иначе мини-игра
     превращается в «сдал/не сдал» и брак становится редкостью, как
     это и случилось со старыми стрелками. ]]
function I.QualityFromSteps(steps, window, cfg)
    cfg = cfg or I.Config
    window = math.max(0.1, tonumber(window) or 1)
    if not istable(steps) or #steps == 0 then return 0 end

    local penalty = 0
    for _, step in ipairs(steps) do
        if not istable(step) then
            penalty = penalty + (cfg.PenaltyPerMiss or 20)
        else
            local err = math.abs(tonumber(step.error) or 0)
            if step.missed then
                penalty = penalty + (cfg.PenaltyPerMiss or 20)
            else
                penalty = penalty + (err / window) * (cfg.PenaltyPerStepWindow or 16)
            end
        end
    end
    local quality = 100 - penalty
    if quality < 0 then quality = 0 end
    if quality > 100 then quality = 100 end
    return math.floor(quality + 0.5)
end

--[[ Исход по качеству. Износ станка ПОДНИМАЕТ порог «мастера»: на
     убитом станке идеальную вещь сделать нельзя. Это второй тормоз
     против стратегии «гнать только верхний рецепт» — первый в том,
     что выгода на единицу сырья у верхнего рецепта не самая высокая. ]]
function I.OutcomeFor(quality, wear, cfg)
    cfg = cfg or I.Config
    quality = tonumber(quality) or 0
    wear = math.max(0, math.min(100, tonumber(wear) or 0))

    local q = cfg.Quality or {}
    local master = (tonumber(q.Master) or 90) + wear * (tonumber(q.WearPenalty) or 0.1)
    local good = tonumber(q.Good) or 60
    local rough = tonumber(q.Rough) or 30

    local outcome
    if quality >= master then outcome = "master"
    elseif quality >= good then outcome = "good"
    elseif quality >= rough then outcome = "rough"
    else outcome = "defect" end

    local info = (cfg.Outcome or {})[outcome] or {}
    return outcome, {
        label = info.label or outcome,
        priceMul = tonumber(info.priceMul) or 0,
        refund = tonumber(info.refund) or 0,
    }
end

-- Окно мини-игры с учётом навыка: опытный работник видит шаг дольше.
function I.WindowFor(station, level, cfg)
    cfg = cfg or I.Config
    local mg = (cfg.Minigame or {})[tostring(station or "")] or {}
    local base = tonumber(mg.window) or 1
    local step = tonumber(cfg.SkillStep) or 0.01
    local cap = tonumber(cfg.SkillCap) or 0.25
    local bonus = math.min(cap, math.max(0, tonumber(level) or 0) * step)
    return base * (1 + bonus)
end

function I.StepsFor(station, cfg)
    cfg = cfg or I.Config
    local mg = (cfg.Minigame or {})[tostring(station or "")] or {}
    return math.floor(tonumber(mg.steps) or 0)
end

function I.MinigameKind(station, cfg)
    cfg = cfg or I.Config
    local mg = (cfg.Minigame or {})[tostring(station or "")] or {}
    return tostring(mg.kind or "none")
end

-- Время сборки растёт с износом.
function I.AssembleTime(recipe, wear, level)
    local base = math.max(1, tonumber(recipe and recipe.assemble) or 1)
    wear = math.max(0, math.min(100, tonumber(wear) or 0))
    -- Уровень мастера срезает до 15% времени.
    local skill = math.min(0.15, math.max(0, tonumber(level) or 0) * 0.006)
    return math.max(1, base * (1 + wear / 100) * (1 - skill))
end

-- ================================================================
--  ЛОГИСТИКА: ценность и награда
-- ================================================================
function I.OrderValue(lines)
    local value, weight = 0, 0
    for _, line in ipairs(lines or {}) do
        local n = math.max(0, math.floor(tonumber(line.count) or 0))
        value = value + I.PriceOf(line.itemID) * n
        weight = weight + I.WeightOf(line.itemID) * n
    end
    return math.floor(value), math.floor(weight * 10) / 10
end

--[[ НАГРАДА ЗА РЕЙС. Платят процент от ценности, а не фикс за коробку:
     в старой логистике награда 600 за ящик из семи стволов делала
     перевозку в десятки раз невыгоднее простой продажи скупщику, и
     система существовала только ради роли. ]]
function I.RewardFor(value, distance, risk, onTime, cfg)
    local L = (cfg or I.Config).Logistics or {}
    local base = tonumber(L.BasePercent) or 0.08
    local full = math.max(1, tonumber(L.DistanceFull) or 20000)
    local bonusMax = tonumber(L.DistanceBonus) or 0.30

    local distBonus = bonusMax * math.min(1, math.max(0, (tonumber(distance) or 0) / full))
    local riskMul = math.max(1, math.min(tonumber(L.RiskMax) or 1.6, tonumber(risk) or 1))
    local timeMul = onTime and 1 or (tonumber(L.LateMultiplier) or 0.6)

    local reward = (tonumber(value) or 0) * base * (1 + distBonus) * riskMul * timeMul
    reward = math.floor(reward)
    return math.max(math.floor(tonumber(L.MinReward) or 0), reward)
end

--[[ Какие строки нужны складу. demand: { [itemID] = { min, max } }.
     Заказываем то, чего меньше минимума, до максимума. ]]
function I.DemandLines(stock, demand)
    local lines = {}
    local ids = {}
    for id in pairs(demand or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local rule = demand[id] or {}
        local have = math.floor(tonumber((stock or {})[id]) or 0)
        local min = math.floor(tonumber(rule.min) or 0)
        local max = math.floor(tonumber(rule.max) or 0)
        if max > min and have < min then
            lines[#lines + 1] = { itemID = id, count = max - have }
        end
    end
    return lines
end

-- ================================================================
--  РАСКЛАДКА (общая для окон цеха и логистики)
-- ================================================================
--[[ Камера для предпросмотра модели. Считаем от габаритов, а не от
     зашитых чисел: у старого верстака было SetCamPos(Vector(70,0,42))
     при FOV 28 — пистолет терялся, РПГ вылезал за рамку.

     Возвращает обычные таблицы, а не Vector: файл должен грузиться
     стендом без GMod. Клиент оборачивает результат сам. ]]
function I.CameraFor(mins, maxs, panelW, panelH, fov)
    local minX = tonumber(mins and (mins.x or mins[1])) or 0
    local minY = tonumber(mins and (mins.y or mins[2])) or 0
    local minZ = tonumber(mins and (mins.z or mins[3])) or 0
    local maxX = tonumber(maxs and (maxs.x or maxs[1])) or 0
    local maxY = tonumber(maxs and (maxs.y or maxs[2])) or 0
    local maxZ = tonumber(maxs and (maxs.z or maxs[3])) or 0

    local sizeX = math.max(1, maxX - minX)
    local sizeY = math.max(1, maxY - minY)
    local sizeZ = math.max(1, maxZ - minZ)
    local center = { x = (minX + maxX) / 2, y = (minY + maxY) / 2, z = (minZ + maxZ) / 2 }

    fov = math.max(10, tonumber(fov) or 36)
    panelW = math.max(1, tonumber(panelW) or 1)
    panelH = math.max(1, tonumber(panelH) or 1)
    local aspect = panelW / panelH

    -- Ключевой размер — тот, что не влезает: по вертикали или по ширине.
    local halfV = math.tan(math.rad(fov) / 2)
    local halfH = halfV * aspect
    local radius = math.max(sizeX, sizeY, sizeZ) / 2
    local distV = radius / math.max(0.01, halfV)
    local distH = radius / math.max(0.01, halfH)
    local dist = math.max(distV, distH) * 1.25 + 8

    --[[ Направление обзора нормируем: distance должна быть РЕАЛЬНЫМ
         расстоянием от камеры до центра, иначе вызывающий код, считающий
         дальность по позиции, разойдётся с возвращённым числом. ]]
    local dx, dy, dz = 0.75, -0.75, 0.42
    local len = math.sqrt(dx * dx + dy * dy + dz * dz)

    return {
        camPos = { x = center.x + dx / len * dist, y = center.y + dy / len * dist, z = center.z + dz / len * dist },
        lookAt = center,
        distance = dist,
    }
end

--[[ Сетка, которая вписывается и в ширину, и в высоту. Старая сетка
     инвентаря считала только ширину, поэтому на 1366×768 нижний ряд
     выползал за панель. ]]
function I.GridFor(panelW, panelH, count, opts)
    opts = opts or {}
    local pad = tonumber(opts.pad) or 12
    local gap = tonumber(opts.gap) or 8
    local minSize = tonumber(opts.minSize) or 48
    local maxSize = tonumber(opts.maxSize) or 108

    count = math.max(1, math.floor(tonumber(count) or 1))
    local availW = math.max(minSize, (tonumber(panelW) or 0) - pad * 2)
    local availH = math.max(minSize, (tonumber(panelH) or 0) - pad * 2)

    local bestCols, bestSize = 1, minSize
    for cols = 1, count do
        local rows = math.ceil(count / cols)
        local sizeW = math.floor((availW - gap * (cols - 1)) / cols)
        local sizeH = math.floor((availH - gap * (rows - 1)) / rows)
        local size = math.min(sizeW, sizeH)
        if size > bestSize then bestSize, bestCols = size, cols end
    end
    bestSize = math.max(minSize, math.min(maxSize, bestSize))

    return { columns = bestCols, size = bestSize, gap = gap, pad = pad,
             rows = math.ceil(count / bestCols) }
end

-- ================================================================
--  МЕЛКИЕ ПОМОЩНИКИ
-- ================================================================
function I.Clamp(v, lo, hi)
    v = tonumber(v) or lo
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function I.Round(v, digits)
    local m = 10 ^ (tonumber(digits) or 0)
    return math.floor((tonumber(v) or 0) * m + 0.5) / m
end

print("[GRM Industry] core v" .. I.Version .. " loaded")
