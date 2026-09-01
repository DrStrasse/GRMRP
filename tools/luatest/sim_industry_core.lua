--[[--------------------------------------------------------------------
    sim_industry_core — чистые функции ядра производства и логистики.

    ЗАКАЗ ВЛАДЕЛЬЦА (31.08): «Логистику, заводское оборудование надо
    полностью переделать… Перепиши полностью для начала концепцию
    производства и логистики». Ядро написано с нуля, поэтому проверяем
    его формулы, а не пересказываем их.

    ЧТО ПРОВЕРЯЕМ.
      1) Качество мини-игры: штрафы, границы, пустой ввод.
      2) Исход по качеству и износу: убитый станок не даёт «мастера».
      3) Окно и время сборки: навык и износ работают в нужную сторону.
      4) Экономика: выгода на единицу сырья НЕ растёт монотонно —
         иначе производят только верхний рецепт (баг старого цеха).
      5) Награда за рейс: процент от ценности, надбавки за расстояние,
         риск и срок.
      6) Раскладка и предпросмотр: камера по габаритам модели.

    Запуск: luajit tools/luatest/sim_industry_core.lua
----------------------------------------------------------------------]]

local pass, fail = 0, 0
local function ok(v, name, extra)
    if v then pass = pass + 1 print("  ok   " .. name)
    else fail = fail + 1 print("  FAIL " .. name .. "   " .. tostring(extra or "")) end
end
local function near(a, b, eps)
    return math.abs((tonumber(a) or 0) - (tonumber(b) or 0)) <= (eps or 0.001)
end

--[[ Ядро загружаем БОЕВЫМ ФАЙЛОМ через loadfile: стенд, гоняющий копию
     формулы, не поймает регрессию в модуле. В файле нет GMod-вызовов
     на этапе загрузки — это было сделано специально для стендов.

     Глобалы GMod, которые ядро использует внутри функций, подставляем
     сами: вне GMod их просто нет. ]]
istable   = istable   or function(v) return type(v) == "table" end
isstring  = isstring  or function(v) return type(v) == "string" end
isnumber  = isnumber  or function(v) return type(v) == "number" end
isfunction = isfunction or function(v) return type(v) == "function" end

local coreSrc = assert(loadfile("lua/autorun/sh_grm_industry_core.lua"))
coreSrc()               -- оставляем модуль в глобальном GRM
local I = GRM.Industry
ok(I ~= nil, "ядро загружено из боевого файла")

-----------------------------------------------------------------------
print("\n=== 1. КАЧЕСТВО МИНИ-ИГРЫ ===")
-----------------------------------------------------------------------
do
    local cfg = I.Config
    local perfect = {}
    for i = 1, 7 do perfect[i] = { error = 0, missed = false } end
    ok(I.QualityFromSteps(perfect, 1.3, cfg) == 100, "безупречное прохождение даёт 100")

    local missed = {}
    for i = 1, 5 do missed[i] = { error = 0, missed = true } end
    ok(I.QualityFromSteps(missed, 1.6, cfg) == 0, "пять полных промахов дают ноль (5×20)",
        I.QualityFromSteps(missed, 1.6, cfg))

    ok(I.QualityFromSteps({}, 1.3, cfg) == 0, "пустой ввод — ноль, а не nil")
    ok(I.QualityFromSteps(nil, 1.3, cfg) == 0, "nil вместо таблицы — ноль")

    -- Ошибка на всё окно стоит PenaltyPerStepWindow очков.
    local sloppy = {}
    for i = 1, 3 do sloppy[i] = { error = 1.0, missed = false } end
    local q = I.QualityFromSteps(sloppy, 1.0, cfg)
    ok(q == 100 - 3 * cfg.PenaltyPerStepWindow, "ошибка на целое окно = " .. cfg.PenaltyPerStepWindow .. " штрафа за шаг", q)

    -- Границы: качество не уходит в минус и не пробивает сотню.
    local awful = {}
    for i = 1, 12 do awful[i] = { error = 99, missed = true } end
    ok(I.QualityFromSteps(awful, 1.0, cfg) >= 0, "качество не уходит ниже нуля", I.QualityFromSteps(awful, 1.0, cfg))
    ok(I.QualityFromSteps(perfect, 1.3, cfg) <= 100, "качество не пробивает сотню")

    -- Частичная неточность: промах должен стоить дороже, чем опоздание.
    local late = { { error = 1.0, missed = false } }
    local miss = { { error = 0, missed = true } }
    ok(I.QualityFromSteps(miss, 1.0, cfg) < I.QualityFromSteps(late, 1.0, cfg),
        "промах дороже, чем попадание на краю окна")
end

-----------------------------------------------------------------------
print("\n=== 2. ИСХОД ПО КАЧЕСТВУ И ИЗНОСУ ===")
-----------------------------------------------------------------------
do
    local o0 = I.OutcomeFor(100, 0)
    ok(o0 == "master", "качество 100 на новом станке — мастер", o0)
    ok(I.OutcomeFor(60, 0) == "good", "60 — обычное изделие")
    ok(I.OutcomeFor(30, 0) == "rough", "30 — требует доводки")
    ok(I.OutcomeFor(0, 0) == "defect", "0 — брак")

    -- ГЛАВНОЕ: износ ПОДНИМАЕТ порог мастера. На убитом станке идеала нет.
    ok(I.OutcomeFor(95, 0) == "master", "качество 95 на новом станке даёт мастера")
    local worn = I.OutcomeFor(95, 100)
    ok(worn ~= "master", "то же качество при износе 100% уже не мастера", worn)
    ok(worn == "good", "при износе 100% девяносто пять — обычное изделие", worn)
    ok(I.OutcomeFor(100, 100) == "master", "идеальное качество берёт износ")

    -- Порог мастера монотонно растёт с износом.
    local function masterAt(quality, wear) return I.OutcomeFor(quality, wear) == "master" end
    ok(masterAt(91, 0) and not masterAt(91, 100), "на изношенном станке порог мастера выше")

    local _, info = I.OutcomeFor(0, 0)
    ok(info.refund > 0 and info.refund <= 0.5, "брак возвращает часть сырья", info.refund)
    local _, good = I.OutcomeFor(70, 0)
    ok(good.priceMul == 1.0, "обычное изделие продаётся по номиналу", good.priceMul)
    local _, master = I.OutcomeFor(100, 0)
    ok(master.priceMul > 1.0, "мастерское изделие дороже номинала", master.priceMul)
end

-----------------------------------------------------------------------
print("\n=== 3. НАВЫК И ИЗНОС ===")
-----------------------------------------------------------------------
do
    local cfg = I.Config
    local w0 = I.WindowFor("weapon", 0, cfg)
    local w10 = I.WindowFor("weapon", 10, cfg)
    ok(w10 > w0, "навык расширяет окно мини-игры")
    ok(near(w10, w0 * 1.10, 0.001), "десятый уровень даёт +10% к окну", w10 / w0)
    -- Потолок: дальше навык не помогает.
    local wMax = I.WindowFor("weapon", 1000, cfg)
    ok(near(wMax, w0 * (1 + cfg.SkillCap), 0.001), "окно ограничено потолком навыка", wMax / w0)

    local recipe = I.Recipes.arccw_m4a1
    local t0 = I.AssembleTime(recipe, 0, 0)
    local t100 = I.AssembleTime(recipe, 100, 0)
    ok(t100 > t0, "износ увеличивает время сборки")
    ok(near(t100, t0 * 2, 0.01), "износ 100% удваивает время", t100 / t0)
    ok(I.AssembleTime(recipe, 0, 100) < t0, "навык ускоряет сборку")
    ok(I.AssembleTime(recipe, 0, 100) >= t0 * 0.85, "ускорение от навыка ограничено 15%")

    ok(I.StepsFor("furnace", cfg) == 0, "у печи нет мини-игры — сырьё просто плавится")
    ok(I.MinigameKind("furnace", cfg) == "none", "вид мини-игры печи — none")
    ok(I.MinigameKind("weapon", cfg) == "assembly", "у верстака сборка по чертежу")
end

-----------------------------------------------------------------------
print("\n=== 4. ЭКОНОМИКА: НЕТ МОНОТОННОГО РОСТА ===")
-----------------------------------------------------------------------
do
    --[[ БАГ СТАРОГО ЦЕХА: выгода на единицу сырья росла монотонно от
         Макарова к РПГ, поэтому производили только РПГ. Здесь проверяем,
         что самый дорогой рецепт НЕ самый выгодный на лом. ]]
    local rows = {}
    for id, r in pairs(I.Recipes) do
        if r.price and r.price > 0 and r.scrap and r.scrap > 0 then
            rows[#rows + 1] = { id = id, scrap = r.scrap, price = r.price, per = r.price / r.scrap }
        end
    end
    table.sort(rows, function(a, b) return a.scrap < b.scrap end)
    ok(#rows >= 5, "оружия в справочнике рецептов хотя бы пять", #rows)

    local best = rows[1]
    for _, r in ipairs(rows) do if r.per > best.per then best = r end end
    ok(best.id ~= "arccw_rpg7", "самый дорогой рецепт не самый выгодный на сырьё", best.id)

    local worst = rows[1]
    for _, r in ipairs(rows) do if r.per < worst.per then worst = r end end
    local spread = (best.per - worst.per) / best.per
    ok(spread < 0.35, "разброс выгоды меньше 35% — выбор по ситуации, а не по таблице", spread)

    -- Печь обязана возвращать меньше, чем стоило сырьё, иначе брак выгоднее работы.
    local melt = I.Recipes.melt_components
    ok(melt.scrap < 0, "переплавка возвращает сырьё (отрицательный расход)")
    local inPrice = I.PriceOf("defective_components")
    ok(inPrice == 0, "брак не имеет цены продажи — только переплавка", inPrice)
end

-----------------------------------------------------------------------
print("\n=== 5. ЛОГИСТИКА: ЦЕННОСТЬ И НАГРАДА ===")
-----------------------------------------------------------------------
do
    local L = I.Config.Logistics
    local lines = { { itemID = "arccw_m4a1", count = 4 }, { itemID = "components_box", count = 10 } }
    local value, weight = I.OrderValue(lines)
    ok(value == I.PriceOf("arccw_m4a1") * 4 + I.PriceOf("components_box") * 10, "ценность считается по справочнику")
    ok(weight > 0, "вес заказа посчитан", weight)

    local base = I.RewardFor(10000, 0, 1, true)
    ok(base == math.floor(10000 * L.BasePercent), "базовая награда — процент от ценности", base)

    local far = I.RewardFor(10000, L.DistanceFull, 1, true)
    ok(near(far / base, 1 + L.DistanceBonus, 0.02), "дальний рейс даёт полную надбавку", far / base)

    local risky = I.RewardFor(10000, 0, L.RiskMax, true)
    ok(near(risky / base, L.RiskMax, 0.02), "риск умножает награду", risky / base)

    local late = I.RewardFor(10000, 0, 1, false)
    ok(near(late / base, L.LateMultiplier, 0.02), "просроченный рейс оплачивается ниже", late / base)

    ok(I.RewardFor(10, 0, 1, true) >= L.MinReward, "у рейса есть минимальная плата", I.RewardFor(10, 0, 1, true))
    ok(I.RewardFor(0, 0, 1, true) >= 0, "пустой заказ не даёт отрицательной награды")

    -- СТАРАЯ ОШИБКА: фикс за коробку делал перевозку в разы дешевле
    -- продажи скупщику. Проверяем, что награда сопоставима с ценой груза.
    local richOrder = { { itemID = "arccw_m4a1", count = 3 } }
    local richValue = I.OrderValue(richOrder)
    local richReward = I.RewardFor(richValue, L.DistanceFull, L.RiskMax, true)
    ok(richReward > richValue * 0.05, "награда ощутима против цены груза", richReward / richValue)
    ok(richReward < richValue, "награда меньше цены самого груза — возить, а не воровать")
end

-----------------------------------------------------------------------
print("\n=== 6. СПРОС И ЗАКАЗЫ ===")
-----------------------------------------------------------------------
do
    local demand = {
        arccw_makarov = { min = 5, max = 20 },
        components_box = { min = 0, max = 10 },
        gpu_basic = { min = 3, max = 6 },
    }
    local stock = { arccw_makarov = 2, components_box = 0, gpu_basic = 12 }
    local lines = I.DemandLines(stock, demand)

    local function find(id)
        for _, l in ipairs(lines) do if l.itemID == id then return l end end
        return nil
    end
    local makarov = find("arccw_makarov")
    ok(makarov ~= nil and makarov.count == 18, "заказывается разница до максимума", makarov and makarov.count)
    ok(find("gpu_basic") == nil, "позиция выше минимума не заказывается")
    ok(find("components_box") == nil, "нулевой минимум не создаёт заказа")
    ok(I.DemandLines({}, {}) ~= nil and #I.DemandLines({}, {}) == 0, "пустой спрос — пустой заказ")
end

-----------------------------------------------------------------------
print("\n=== 7. ПРЕДПРОСМОТР И РАСКЛАДКА ===")
-----------------------------------------------------------------------
do
    --[[ БАГ СТАРОГО ВЕРСТАКА: камера была зашита как Vector(70,0,42) при
         FOV 28. Пистолет терялся, РПГ вылезал за рамку. Считаем от
         габаритов и проверяем, что крупная модель отодвигается. ]]
    local small = I.CameraFor({ x = -2, y = -1, z = 0 }, { x = 2, y = 1, z = 2 }, 400, 300, 34)
    local big = I.CameraFor({ x = -40, y = -6, z = -6 }, { x = 40, y = 6, z = 6 }, 400, 300, 34)
    ok(big.distance > small.distance, "крупная модель отодвигается дальше", big.distance .. " vs " .. small.distance)

    local d1 = math.sqrt((small.camPos.x - small.lookAt.x) ^ 2 + (small.camPos.y - small.lookAt.y) ^ 2 + (small.camPos.z - small.lookAt.z) ^ 2)
    ok(near(d1, small.distance, 1), "возвращённая дальность совпадает с позицией камеры", d1)
    ok(near(small.lookAt.x, 0, 0.001) and near(small.lookAt.z, 1, 0.001), "точка взгляда — центр модели")

    --[[ УЗКАЯ панель требует больше расстояния: углы у SetFOV считаются
         по вертикали, поэтому при малом соотношении сторон горизонтальный
         угол сжимается и модель приходится отодвигать. Проверка ловит
         перепутанные местами ширину и высоту. ]]
    local wide = I.CameraFor({ x = -50, y = -50, z = 0 }, { x = 50, y = 50, z = 10 }, 800, 200, 34)
    local tall = I.CameraFor({ x = -50, y = -50, z = 0 }, { x = 50, y = 50, z = 10 }, 200, 800, 34)
    ok(tall.distance > wide.distance, "для узкой панели модель отодвигается сильнее",
        tostring(tall.distance) .. " vs " .. tostring(wide.distance))
    local square = I.CameraFor({ x = -50, y = -50, z = 0 }, { x = 50, y = 50, z = 10 }, 400, 400, 34)
    ok(square.distance >= wide.distance and square.distance <= tall.distance,
        "квадратная панель даёт промежуточную дальность")

    -- Сетка: вписывается и в ширину, и в высоту.
    local grid = I.GridFor(600, 300, 9, { pad = 12, gap = 8, minSize = 48, maxSize = 108 })
    local rows = math.ceil(9 / grid.columns)
    local usedW = grid.columns * grid.size + (grid.columns - 1) * grid.gap + grid.pad * 2
    local usedH = rows * grid.size + (rows - 1) * grid.gap + grid.pad * 2
    ok(usedW <= 600 + 1, "сетка вписывается в ширину", usedW)
    ok(usedH <= 300 + 1, "сетка вписывается в высоту", usedH)
    ok(grid.size >= 48 and grid.size <= 108, "размер ячейки в заданных границах", grid.size)
end

-----------------------------------------------------------------------
print("\n=== ИТОГ ===")
print("  пройдено: " .. pass .. ", провалено: " .. fail)
if fail > 0 then os.exit(1) end
