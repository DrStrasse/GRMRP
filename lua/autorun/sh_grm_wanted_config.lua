--[[--------------------------------------------------------------------
    GRM Wanted — shared config (Код 61)
    Уровни розыска, каталог статей, лимиты.
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Wanted = GRM.Wanted or {}
local W = GRM.Wanted

W.Config = W.Config or {
    MaxLevel = 5,
    MaxReasonsPerPlayer = 32,
    MaxActiveRecords = 512,
    HistorySize = 200,
    -- Авто-спад уровня (0 = выкл), секунды
    LevelDecaySeconds = 0,
    -- Показывать уровень в HUD/Tab (если модули читают GRM.Wanted.GetLevel)
    SyncToClient = true,
    -- Суперадмин всегда может всё
    SuperAdminBypass = true,

    -- ── Юрисдикции ──────────────────────────────────────────────
    -- Явный список военных фракций: ["Точное имя фракции"] = true.
    -- true  → персонажи фракции проходят по ВОЕННОЙ ветке (жандармерия);
    -- false → принудительно гражданская ветка (перебивает эвристику).
    MilitaryFactions = {},
    -- Фолбэк-эвристика по подстроке в названии фракции, если фракция
    -- не перечислена в MilitaryFactions.
    MilitaryPatterns = {
        "feldgendarmerie", "wehrmacht", "heer", "militar", "military",
        "жандарм", "военн", "комендат", "вооруж", "гарнизон",
    },
}

-- Уровни: index 0 = чист, 1..MaxLevel
W.Levels = W.Levels or {
    [0] = { name = "Чист",          color = Color(140, 200, 140), short = "—" },
    [1] = { name = "Административка", color = Color(220, 200, 80),  short = "★" },
    [2] = { name = "Лёгкий розыск",   color = Color(230, 170, 60),  short = "★★" },
    [3] = { name = "Розыск",          color = Color(230, 120, 50),  short = "★★★" },
    [4] = { name = "Особый розыск",   color = Color(220, 60, 60),   short = "★★★★" },
    [5] = { name = "Федеральный",     color = Color(160, 40, 200),  short = "★★★★★" },
}

-- Каталог статей по умолчанию (id → запись).
--   type:         "admin" | "crime"
--   jurisdiction: "civil" (Полиция Порядка) | "military" (Feldgendarmerie)
W.DefaultCatalog = W.DefaultCatalog or {
    -- ── Гражданская юрисдикция: Ordnungspolizei ─────────────────
    { id = "admin_noise",     type = "admin", jurisdiction = "civil", code = "АК-1",  title = "Нарушение общественного порядка", fine = 500,  defaultLevel = 1 },
    { id = "admin_traffic",   type = "admin", jurisdiction = "civil", code = "АК-2",  title = "Нарушение ПДД",                   fine = 1000, defaultLevel = 1 },
    { id = "admin_id",        type = "admin", jurisdiction = "civil", code = "АК-3",  title = "Отказ предъявить документы",      fine = 1500, defaultLevel = 1 },
    { id = "admin_curfew",    type = "admin", jurisdiction = "civil", code = "АК-4",  title = "Нарушение комендантского часа",   fine = 2500, defaultLevel = 1 },
    { id = "crime_theft",     type = "crime", jurisdiction = "civil", code = "УК-1",  title = "Кража",                           fine = 5000, defaultLevel = 2 },
    { id = "crime_assault",   type = "crime", jurisdiction = "civil", code = "УК-2",  title = "Нападение / побои",               fine = 8000, defaultLevel = 3 },
    { id = "crime_robbery",   type = "crime", jurisdiction = "civil", code = "УК-3",  title = "Грабёж",                          fine = 15000, defaultLevel = 3 },
    { id = "crime_weapon",    type = "crime", jurisdiction = "civil", code = "УК-4",  title = "Незаконное оружие",               fine = 20000, defaultLevel = 4 },
    { id = "crime_murder",    type = "crime", jurisdiction = "civil", code = "УК-5",  title = "Убийство",                        fine = 0,     defaultLevel = 5 },
    { id = "crime_escape",    type = "crime", jurisdiction = "civil", code = "УК-6",  title = "Побег / уклонение",               fine = 10000, defaultLevel = 4 },
    { id = "crime_corrupt",   type = "crime", jurisdiction = "civil", code = "УК-7",  title = "Коррупция / взятка",              fine = 25000, defaultLevel = 4 },
    { id = "crime_forgery",   type = "crime", jurisdiction = "civil", code = "УК-8",  title = "Подделка документов",             fine = 12000, defaultLevel = 3 },
    { id = "crime_smuggling", type = "crime", jurisdiction = "civil", code = "УК-9",  title = "Контрабанда",                     fine = 18000, defaultLevel = 3 },
    { id = "crime_riot",      type = "crime", jurisdiction = "civil", code = "УК-10", title = "Организация беспорядков",         fine = 22000, defaultLevel = 4 },

    -- ── Военная юрисдикция: Feldgendarmerie / комендатура ───────
    { id = "mil_ausgang",     type = "admin", jurisdiction = "military", code = "ДВ-1", title = "Нарушение формы одежды",              fine = 1500,  defaultLevel = 1 },
    { id = "mil_disobey",     type = "admin", jurisdiction = "military", code = "ДВ-2", title = "Пререкание со старшим по званию",     fine = 2500,  defaultLevel = 1 },
    { id = "mil_post",        type = "crime", jurisdiction = "military", code = "ВУ-1", title = "Нарушение караульной службы",         fine = 6000,  defaultLevel = 2 },
    { id = "mil_awol",        type = "crime", jurisdiction = "military", code = "ВУ-2", title = "Самовольное оставление части (СОЧ)",  fine = 10000, defaultLevel = 3 },
    { id = "mil_desert",      type = "crime", jurisdiction = "military", code = "ВУ-3", title = "Дезертирство",                        fine = 0,     defaultLevel = 5 },
    { id = "mil_order",       type = "crime", jurisdiction = "military", code = "ВУ-4", title = "Неисполнение приказа",                fine = 8000,  defaultLevel = 3 },
    { id = "mil_weaponloss",  type = "crime", jurisdiction = "military", code = "ВУ-5", title = "Утрата табельного оружия",            fine = 20000, defaultLevel = 3 },
    { id = "mil_looting",     type = "crime", jurisdiction = "military", code = "ВУ-6", title = "Мародёрство",                         fine = 25000, defaultLevel = 4 },
    { id = "mil_treason",     type = "crime", jurisdiction = "military", code = "ВУ-7", title = "Измена / переход к противнику",       fine = 0,     defaultLevel = 5 },
    { id = "mil_sabotage",    type = "crime", jurisdiction = "military", code = "ВУ-8", title = "Саботаж / вредительство",             fine = 0,     defaultLevel = 5 },
}

function W.GetLevelInfo(level)
    level = math.floor(tonumber(level) or 0)
    local maxL = (W.Config and W.Config.MaxLevel) or 5
    level = math.Clamp(level, 0, maxL)
    local info = (W.Levels and W.Levels[level]) or { name = "Ур." .. level, color = color_white, short = tostring(level) }
    return level, info
end

function W.ClampLevel(level)
    local maxL = (W.Config and W.Config.MaxLevel) or 5
    return math.Clamp(math.floor(tonumber(level) or 0), 0, maxL)
end

print("[GRM Wanted] config v2.0.0")
