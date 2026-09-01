--[[--------------------------------------------------------------------
    GRM RoomTap — shared configuration
    Прослушка помещений: чипы, серверные стойки и терминалы.
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.RoomTap = GRM.RoomTap or {}

local RT = GRM.RoomTap

RT.Config = RT.Config or {
    -- Модели оборудования.
    ChipModel = "models/jaanus/wiretool/wiretool_controlchip.mdl",
    ServerModel = "models/props_silo/silo_server_d.mdl",
    TerminalModel = "models/props/cs_office/computer.mdl",

    -- Радиус записи: расстояние проверяется сквозь стены, без TraceLine.
    DefaultChipRadius = 350,
    MinChipRadius = 64,
    MaxChipRadius = 2500,
    UseDistance = 180,

    -- Автоматический сектор карты. Например: X-2 / Y4.
    GridSectorSize = 1024,

    -- Частота фиксации входа/выхода игрока из зоны чипа.
    PresenceScanSeconds = 2,

    -- Ограничения терминала и хранения.
    TerminalRecordsLimit = 250,
    MemoryRecordsLimit = 750,
    RecordsRetentionDays = 30, -- 0 = не удалять старые файлы автоматически

    -- Магазин временного оборудования.
    ShopRequireEquipmentAccess = true,
    ShopSpawnDistance = 90,
    ShopRemoveDistance = 180,
    -- Цена временной установки = базовая цена предмета * multiplier.
    -- Сейчас множители линейные: базовая цена указана за 1 час.
    -- При необходимости здесь же можно сделать скидку на долгую аренду.
    TemporaryDurations = {
        { id = "1h",   name = "1 час",       seconds = 1 * 60 * 60,   multiplier = 1 },
        { id = "2h",   name = "2 часа",      seconds = 2 * 60 * 60,   multiplier = 2 },
        { id = "3h",   name = "3 часа",      seconds = 3 * 60 * 60,   multiplier = 3 },
        { id = "5h",   name = "5 часов",     seconds = 5 * 60 * 60,   multiplier = 5 },
        { id = "10h",  name = "10 часов",    seconds = 10 * 60 * 60,  multiplier = 10 },
        { id = "24h",  name = "24 часа",     seconds = 24 * 60 * 60,  multiplier = 24 },
        { id = "48h",  name = "2 суток",     seconds = 48 * 60 * 60,  multiplier = 48 },
        { id = "72h",  name = "3 суток",     seconds = 72 * 60 * 60,  multiplier = 72 },
        { id = "5d",   name = "5 суток",     seconds = 5 * 86400,     multiplier = 120 },
        { id = "7d",   name = "1 неделя",    seconds = 7 * 86400,     multiplier = 168 },
    },

    ShopItems = {
        chip = {
            id = "chip",
            name = "Чип прослушки помещения",
            description = "Записывает текст и события присутствия в заданном радиусе.",
            class = "grm_roomtap_chip",
            model = "models/jaanus/wiretool/wiretool_controlchip.mdl",
            price = 1200,
            maxOwned = 4,
        },
        server = {
            id = "server",
            name = "Серверная стойка записи",
            description = "Принимает и хранит записи чипов своего канала.",
            class = "grm_roomtap_server",
            model = "models/props_silo/silo_server_d.mdl",
            price = 5000,
            maxOwned = 2,
        },
        terminal = {
            id = "terminal",
            name = "Компьютер мониторинга",
            description = "Открывает журнал записей всех доступных каналов.",
            class = "grm_roomtap_terminal",
            model = "models/props/cs_office/computer.mdl",
            price = 3500,
            maxOwned = 2,
        },
    },

    -- Отдельная система /roomtap_access. Данные хранятся в
    -- data/grm_roomtap/access.json и настраиваются только superadmin.
    Access = {
        SuperAdminBypass = true,
        AdminBypass = false,
        AllowOwnerConfigureTemporary = true,
    },
}

-- Не затираем настройки, если конфиг был создан предыдущей версией.
local defaults = {
    ChipModel = "models/jaanus/wiretool/wiretool_controlchip.mdl",
    ServerModel = "models/props_silo/silo_server_d.mdl",
    TerminalModel = "models/props/cs_office/computer.mdl",
    DefaultChipRadius = 350,
    MinChipRadius = 64,
    MaxChipRadius = 2500,
    UseDistance = 180,
    GridSectorSize = 1024,
    PresenceScanSeconds = 2,
    TerminalRecordsLimit = 250,
    MemoryRecordsLimit = 750,
    RecordsRetentionDays = 30,
    ShopRequireEquipmentAccess = true,
    ShopSpawnDistance = 90,
    ShopRemoveDistance = 180,
}

for key, value in pairs(defaults) do
    if RT.Config[key] == nil then RT.Config[key] = value end
end
