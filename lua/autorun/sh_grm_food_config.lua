--[[
    GRM Food System - Конфиг (v2, Код 110 — «GrandEats»)
    Файл общий: загружается и на сервере, и на клиенте.

    v2 (Код 110 по заказу владельца, находка 127):
      • позиции 1-2 заказа: МОЛОКО (garbage_milkcarton002a) и КИТАЙСКАЯ
        ЛАПША (garbage_takeoutcarton001a) — в меню автомата;
      • позиция 3 заказа: КУХНЯ — сырые овощи (выращиваются в горшке),
        готовые блюда (плита по рецептам), испорченная еда (порча
        приготовленного вне холодильника);
      • позиция 5: холодильник-модель furniturefridge001a, параметры
        слотов/заморозки срока — в секции Kitchen;
      • позиция 4: плита-модель furniturestove001a — в секции Kitchen.

    ВАЖНО: все новые модели применяются ТОЛЬКО через проверку
    util.IsValidModel + фолбэк на кружку (находка 85): у сервера без
    CSS-контента экзотики просто не будет, блюдо станет кружкой —
    логика при этом не ломается.
]]

if SERVER then
    AddCSLuaFile()
end

GRM = GRM or {}
GRM.Food = GRM.Food or {}

GRM.Food.Config = {
    -- Голод
    HungerMax = 100,
    HungerDrainPerSecond = 0.008,
    HungerDamageInterval = 10,
    HungerDamageAmount = 2,
    HungerWarningThreshold = 20,

    ThirstMax = 100,
    ThirstDrainPerSecond = 0.014,
    ThirstDamageInterval = 8,
    ThirstDamageAmount = 2,
    ThirstWarningThreshold = 20,

    -- Лечение от еды не выше максимального HP игрока
    RespectMaxHealth = true,

    -- Расстояние использования/покупки у автомата и кухонных агрегатов
    VendingUseDistance = 150,

    -- Еда
    FoodItems = {
        ["grm_food_apple"] = {
            name = "Яблоко",
            model = "models/props/cs_italy/orange.mdl",
            hungerRestore = 15,
            thirstRestore = 2,
            healthRestore = 2,
            price = 20,
        },

        ["grm_food_bread"] = {
            name = "Хлеб",
            model = "models/props_junk/garbage_bag001a.mdl",
            hungerRestore = 25,
            thirstRestore = 3,
            healthRestore = 3,
            price = 44,
        },

        ["grm_food_water"] = {
            name = "Вода",
            model = "models/props_junk/garbage_plasticbottle003a.mdl",
            hungerRestore = 4,
            thirstRestore = 45,
            healthRestore = 0,
            price = 10,
        },

        ["grm_food_soda"] = {
            name = "Газировка",
            model = "models/props_junk/PopCan01a.mdl",
            hungerRestore = 3,
            thirstRestore = 22,
            healthRestore = 0,
            price = 15,
        },

        -- ══ Код 110, позиция 1: МОЛОКО (заказана именно эта модель) ══
        ["grm_food_milk"] = {
            name = "Молоко",
            model = "models/props_junk/garbage_milkcarton002a.mdl",
            hungerRestore = 8,
            thirstRestore = 28,
            healthRestore = 1,
            price = 25,
            icon = "icon16/cup.png",
        },

        -- ══ Код 110, позиция 2: КИТАЙСКАЯ ЛАПША (заказана именно эта модель) ══
        ["grm_food_noodles"] = {
            name = "Китайская лапша",
            model = "models/props_junk/garbage_takeoutcarton001a.mdl",
            hungerRestore = 30,
            thirstRestore = 5,
            healthRestore = 2,
            price = 55,
            icon = "icon16/basket.png",
        },

        -- ══ Код 110, позиция 3: СЫРЫЕ овощи (урожай горшка) ══
        -- Съедобны как есть, но ценнее как ингредиент рецептов плиты.
        ["grm_food_potato"] = {
            name = "Картофель (сырой)",
            model = "models/props_junk/garbage_metalcan001a.mdl",
            hungerRestore = 4,
            thirstRestore = 1,
            healthRestore = 0,
            price = 8,
            icon = "icon16/box.png",
            raw = true, -- продукт выращивания; в автомат НЕ ставится
        },

        ["grm_food_tomato"] = {
            name = "Помидор",
            model = "models/props/cs_italy/tomato.mdl",
            hungerRestore = 5,
            thirstRestore = 6,
            healthRestore = 1,
            price = 10,
            icon = "icon16/flower_daisy.png",
            raw = true,
        },

        ["grm_food_carrot"] = {
            name = "Морковь",
            model = "models/props/cs_italy/bananna.mdl",
            hungerRestore = 4,
            thirstRestore = 3,
            healthRestore = 1,
            price = 9,
            icon = "icon16/flower_daisy.png",
            raw = true,
        },

        -- ══ Код 110, позиция 3: ГОТОВЫЕ блюда (выход плиты). ══
        -- cooked=true: имеет СРОК ГОДНОСТИ (Kitchen.CookedSpoilSeconds)
        -- в инвентаре и в мире; в холодильнике срок ЗАМОРОЖЕН.
        ["grm_food_fried_potato"] = {
            name = "Жареная картошка",
            model = "models/props/cs_militia/foodtray01.mdl",
            hungerRestore = 35,
            thirstRestore = 2,
            healthRestore = 4,
            price = 45,
            icon = "icon16/cake.png",
            cooked = true,
        },

        ["grm_food_veg_soup"] = {
            name = "Овощной суп",
            model = "models/props/cs_office/Soup_can.mdl",
            hungerRestore = 55,
            thirstRestore = 18,
            healthRestore = 8,
            price = 80,
            icon = "icon16/cake.png",
            cooked = true,
        },

        ["grm_food_milk_shake"] = {
            name = "Молочный коктейль",
            model = "models/props/cs_office/coffee_mug.mdl",
            hungerRestore = 18,
            thirstRestore = 22,
            healthRestore = 3,
            price = 30,
            icon = "icon16/cup.png",
            cooked = true,
        },

        ["grm_food_fried_noodles"] = {
            name = "Лапша с овощами (жареная)",
            model = "models/props_junk/garbage_takeoutcarton001a.mdl",
            hungerRestore = 50,
            thirstRestore = 8,
            healthRestore = 5,
            price = 65,
            icon = "icon16/basket.png",
            cooked = true,
        },

        -- ══ Код 110: итог истёкшего срока — мусор ══
        ["grm_food_spoiled"] = {
            name = "Испорченная еда",
            model = "models/props_junk/garbage_milkcarton001a.mdl",
            hungerRestore = 0,
            healthRestore = 0,
            price = 0,
            icon = "icon16/bin_closed.png",
            spoiled = true,
        },
        ["grm_food_yeast"] = {
            name = "Дрожжи",
            model = "models/props_lab/jar01a.mdl",
            hungerRestore = 0, thirstRestore = 0, healthRestore = 0,
            price = 18, icon = "icon16/brick.png", raw = true,
        },
        ["grm_food_sugar"] = {
            name = "Сахар",
            model = "models/props_junk/garbage_metalcan002a.mdl",
            hungerRestore = 1, thirstRestore = 0, healthRestore = 0,
            price = 12, icon = "icon16/cup.png", raw = true,
        },
        ["grm_food_beer"] = {
            name = "Бутылка пива",
            model = "models/props_junk/garbage_glassbottle003a.mdl",
            hungerRestore = 4, thirstRestore = 16, healthRestore = 0,
            price = 45, icon = "icon16/drink.png", cooked = true, alcohol = 0.35,
        },
        ["grm_food_kvass"] = {
            name = "Бутылка кваса",
            model = "models/props_junk/garbage_glassbottle001a.mdl",
            hungerRestore = 6, thirstRestore = 24, healthRestore = 1,
            price = 28, icon = "icon16/drink.png", cooked = true, alcohol = 0.08,
        },
    },

    -- Автомат
    VendingMachineModel = "models/props_interiors/VendingMachineSoda01a.mdl",

    VendingMachineItems = {
        "grm_food_apple",
        "grm_food_bread",
        "grm_food_water",
        "grm_food_soda",
        -- Код 110, позиции 1-2: молоко и китайская лапша в меню автомата
        "grm_food_milk",
        "grm_food_noodles",
    },
}

-- =============================================================
-- КУХНЯ (Код 110, позиции 3-5): плита, холодильник, горшок.
-- Рецепты видны клиенту (окно плиты) — конфиг shared как и весь файл.
-- Денежные операции (семена) идут через GRM.HasMoney/TakeMoney, как
-- покупка в автомате; при отсутствии экономики — бесплатно (поведение
-- совпадает с автоматом: «нет GRM.TakeMoney — товар бесплатный»).
-- =============================================================
GRM.Food.Kitchen = {
    -- Модели агрегатов (заказ владельца, позиции 4-5) + горшок/растение.
    -- Применяются через util.IsValidModel + фолбэк (находка 85).
    StoveModel     = "models/props_c17/furniturestove001a.mdl",
    FridgeModel    = "models/props_c17/furniturefridge001a.mdl",
    PotModel       = "models/props_junk/terracotta01.mdl",
    PlantModel     = "models/props/cs_office/plant01.mdl",
    ModelFallback  = "models/props/cs_office/coffee_mug.mdl",

    ReadySlots   = 4,    -- макс. готовых блюд, лежащих на плите (выходной лоток)
    FridgeSlots  = 12,   -- слотов хранения в холодильнике
    UseDistance  = 150,

    -- Срок годности приготовленного (cooked=true): ВЕЗДЕ, кроме
    -- холодильника (там заморожен). Продукты автомата и сырые овощи
    -- не портятся (упаковка/корнеплод).
    CookedSpoilSeconds = 2700,  -- 45 минут
    SpoilSweepSeconds  = 30,    -- период свипера порчи (инвентарь у всех онлайн + мир)

    -- Рецепты плиты. raw = {itemID = нужное количество}, time = секунды
    -- готовки, out = id блюда, n = сколько блюд выходит за один цикл.
    Recipes = {
        ["fried_potato"] = {
            name = "Жареная картошка",
            out = "grm_food_fried_potato",
            n = 1,
            time = 60,
            raw = { grm_food_potato = 2 },
        },
        ["veg_soup"] = {
            name = "Овощной суп",
            out = "grm_food_veg_soup",
            n = 1,
            time = 90,
            raw = { grm_food_potato = 1, grm_food_tomato = 1, grm_food_carrot = 1, grm_food_water = 1 },
        },
        ["milk_shake"] = {
            name = "Молочный коктейль",
            out = "grm_food_milk_shake",
            n = 1,
            time = 45,
            raw = { grm_food_milk = 1, grm_food_apple = 1 },
        },
        ["veg_noodles"] = {
            name = "Лапша с овощами",
            out = "grm_food_fried_noodles",
            n = 1,
            time = 70,
            raw = { grm_food_noodles = 1, grm_food_carrot = 1 },
        },
        ["brew_beer"] = {
            name = "Пиво (варка)", out = "grm_food_beer", n = 2, time = 120, needKettle = true,
            raw = { grm_food_bread = 1, grm_food_water = 1, grm_food_yeast = 1 },
        },
        ["brew_kvass"] = {
            name = "Квас (варка)", out = "grm_food_kvass", n = 2, time = 90, needKettle = true,
            raw = { grm_food_bread = 1, grm_food_water = 1, grm_food_sugar = 1 },
        },
    },

    -- Культуры горшка. cost = цена семени; growSeconds = время роста;
    -- yield = сколько сырых овощей снимается за урожай.
    Crops = {
        ["potato"] = { name = "Картофель", item = "grm_food_potato", cost = 15, growSeconds = 240, yield = 3 },
        ["tomato"] = { name = "Помидор",   item = "grm_food_tomato",  cost = 12, growSeconds = 200, yield = 3 },
        ["carrot"] = { name = "Морковь",   item = "grm_food_carrot",  cost = 10, growSeconds = 180, yield = 3 },
    },

    WaterCooldown = 60,   -- секунд между поливами одного горшка
    WaterBoost = 0.25,    -- полив срезает 25% оставшегося времени роста
}
