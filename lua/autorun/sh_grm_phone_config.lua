--[[--------------------------------------------------------------------
    GRM Phone Lines System - Shared Config
--------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Phone = GRM.Phone or {}

GRM.Phone.Config = GRM.Phone.Config or {
    LocalVoiceRadius = 355,

    -- Если true, аддон убирает известные конфликтующие хуки локального/радио войса
    -- и ставит единый voice hook: локальный + рация + телефоны.
    IntegrateRadioVoice = true,
    RemoveKnownVoiceHooks = true,

    -- Телефонная связь.
    UseDistance = 130,
    MaxUseDistance = 180,
    RingTimeout = 35,
    RequireActivePBX = true,
    AllowCrossExchangeCalls = false,

    -- Номера.
    MinNumber = 1000,
    MaxNumber = 9999,

    -- Модели телефонов.
    -- Обычный стационарный телефон с трубкой на базе.
    PhoneModel = "models/props/cs_office/phone.mdl",
    PhoneModelOnHook = "models/props/cs_office/phone.mdl",
    -- Стационарный телефон без трубки: используется визуально, когда трубка снята/идёт разговор.
    PhoneModelOffHook = "models/props/cs_office/phone_p1.mdl",
    -- Отдельная трубка. Пока используется как справочная модель/для будущей визуализации.
    HandsetModel = "models/props/cs_office/phone_p2.mdl",
    -- Телефонная будка / таксофон.
    PayphoneModel = "models/props_equipment/phone_booth.mdl",
    -- Оборудование АТС и прослушки.
    PBXModel = "models/props_lab/servers.mdl",
    PBXDefaultMaxLines = 60, -- по умолчанию 60 линий связи, можно ставить 50-70+
    WiretapModel = "models/props_lab/reciever01a.mdl",
    TerminalModel = "models/props_lab/monitor01b.mdl", -- компьютер спецслужб/диспетчера

    -- Звуки.
    Sounds = {
        Ring = "ambient/alarms/klaxon1.wav",
        Dial = "buttons/button17.wav",
        Pickup = "buttons/button14.wav",
        Hangup = "buttons/button10.wav",
        Deny = "buttons/button8.wav",
        Switch = "buttons/button3.wav",
    },

    Access = {
        SuperAdminBypass = true,
        AdminBypass = false,
        -- Кто может пользоваться АТС/прослушкой и менять оборудование.
        AllowedFactions = {
            -- ["Полиция"] = true,
            -- ["ФСБ"] = true,
            -- ["Администрация"] = true,
        },
        AllowedRoles = {
            -- ["Полиция"] = { ["Лидер"] = true, ["Диспетчер"] = true },
            -- ["*"] = { ["Связист"] = true },
        },
        AllowedDepartments = {
            -- ["Полиция"] = { ["Связь"] = true },
        },
    },
}
