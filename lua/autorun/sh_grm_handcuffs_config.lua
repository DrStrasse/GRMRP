--[[--------------------------------------------------------------------
    GRM Handcuffs - Shared Config
--------------------------------------------------------------------]]

if SERVER then
    AddCSLuaFile()
end

GRM = GRM or {}
GRM.Handcuffs = GRM.Handcuffs or {}

GRM.Handcuffs.Config = GRM.Handcuffs.Config or {
    WeaponClass = "grm_handcuffs",
    RestrainedWeaponClass = "grm_cuffed",

    CuffDistance = 110,
    DragDistance = 145,
    ReleaseDistance = 115,

    CuffTime = 1.2,
    UncuffTime = 1.5,
    ReleaseRate = 32, -- progress/sec при удержании E другим игроком
    ReleaseProgressMax = 100,

    CuffedWalkSpeedMultiplier = 0.45,
    CuffedRunSpeedMultiplier = 0.35,
    -- Сопровождение без parent/Freeze/SetPos: задержанный идёт за ведущим
    -- обычным движением игрока, сохраняя собственную высоту и коллизии мира.
    DragFollowDistance = 52,
    DragHardDistance = 110, -- legacy; оставлен для совместимости конфигов
    EscortDeadZone = 10,
    EscortCorrectionGain = 5.5,
    EscortAcceleration = 8,
    EscortTurnRate = 5,
    EscortMaxSpeed = 300,
    EscortBreakDistance = 420,
    EscortBreakVerticalDistance = 120,
    MaxDraggedPlayers = 1,

    -- Транспорт: посадка только на пассажирские места, не на водительское.
    VehicleUseDistance = 170,
    VehicleSeatSearchRadius = 420,
    VehicleExitOffset = 80,
    VehicleAllowDriverSeat = false,

    AllowSameFactionCuff = true,
    AllowCuffAdmins = false,
    -- Задержанный не может освободиться сам.
    CanSelfRelease = false,

    -- При сковывании забираем/прячем всё оружие, чтобы игрок не стоял
    -- в наручниках с физганом/оружием в руках.
    StripWeaponsOnCuff = true,
    RestoreWeaponsOnUncuff = true,
    EnforceNoWeaponsWhileCuffed = true,

    AnyoneCanReleaseWithUse = false,
    AccessUsersCanReleaseWithUse = true,

    -- Клиентская поза рук за спиной для задержанного.
    EnableBehindBackPose = false,

    GagBlocksTextChat = true,
    GagBlocksVoice = true,
    BlindfoldEnabled = true,

    Sounds = {
        CuffStart = "npc/metropolice/gear1.wav",
        CuffSuccess = "physics/metal/metal_chainlink_impact_soft2.wav",
        Uncuff = "doors/door_latch3.wav",
        Error = "buttons/button10.wav",
        Drag = "npc/metropolice/gear2.wav",
        Gag = "physics/cardboard/cardboard_box_impact_soft4.wav",
        Blindfold = "npc/metropolice/gear3.wav",
    },
}

-- Безопасное добавление новых параметров при lua_refresh/обновлении поверх старой версии.
GRM.Handcuffs.Config.CanSelfRelease = GRM.Handcuffs.Config.CanSelfRelease == nil and false or GRM.Handcuffs.Config.CanSelfRelease
GRM.Handcuffs.Config.StripWeaponsOnCuff = GRM.Handcuffs.Config.StripWeaponsOnCuff == nil and true or GRM.Handcuffs.Config.StripWeaponsOnCuff
GRM.Handcuffs.Config.RestoreWeaponsOnUncuff = GRM.Handcuffs.Config.RestoreWeaponsOnUncuff == nil and true or GRM.Handcuffs.Config.RestoreWeaponsOnUncuff
GRM.Handcuffs.Config.EnforceNoWeaponsWhileCuffed = GRM.Handcuffs.Config.EnforceNoWeaponsWhileCuffed == nil and true or GRM.Handcuffs.Config.EnforceNoWeaponsWhileCuffed
GRM.Handcuffs.Config.EnableBehindBackPose = false
GRM.Handcuffs.Config.DragFollowDistance = GRM.Handcuffs.Config.DragFollowDistance or 52
GRM.Handcuffs.Config.EscortDeadZone = GRM.Handcuffs.Config.EscortDeadZone or 10
GRM.Handcuffs.Config.EscortCorrectionGain = GRM.Handcuffs.Config.EscortCorrectionGain or 5.5
GRM.Handcuffs.Config.EscortAcceleration = GRM.Handcuffs.Config.EscortAcceleration or 8
GRM.Handcuffs.Config.EscortTurnRate = GRM.Handcuffs.Config.EscortTurnRate or 5
GRM.Handcuffs.Config.EscortMaxSpeed = GRM.Handcuffs.Config.EscortMaxSpeed or 300
GRM.Handcuffs.Config.EscortBreakDistance = GRM.Handcuffs.Config.EscortBreakDistance or 420
GRM.Handcuffs.Config.EscortBreakVerticalDistance = GRM.Handcuffs.Config.EscortBreakVerticalDistance or 120
GRM.Handcuffs.Config.VehicleUseDistance = GRM.Handcuffs.Config.VehicleUseDistance or 170
GRM.Handcuffs.Config.VehicleSeatSearchRadius = GRM.Handcuffs.Config.VehicleSeatSearchRadius or 420
GRM.Handcuffs.Config.VehicleExitOffset = GRM.Handcuffs.Config.VehicleExitOffset or 80
GRM.Handcuffs.Config.VehicleAllowDriverSeat = GRM.Handcuffs.Config.VehicleAllowDriverSeat == nil and false or GRM.Handcuffs.Config.VehicleAllowDriverSeat

-- Доступ вынесен в отдельный патч-файл zz_grm_handcuffs_access_patch.lua.
-- Здесь оставлены безопасные дефолты.
GRM.Handcuffs.Access = GRM.Handcuffs.Access or {
    SuperAdminBypass = true,
    AdminBypass = false,

    -- Если true, при отсутствии Factions игроки без bypass не смогут использовать наручники.
    RequireFactionSystem = true,

    -- Если фракция есть в AllowedFactions=true, всем её участникам доступ разрешён,
    -- если для этой фракции не указаны более точные ограничения в AllowedRoles/AllowedDepartments.
    AllowedFactions = {
        -- ["Полиция"] = true,
    },

    -- Доступ по ролям. Можно использовать конкретную фракцию или "*" для любой фракции.
    AllowedRoles = {
        -- ["Полиция"] = { ["Лидер"] = true, ["Офицер"] = true },
        -- ["*"] = { ["Полицейский"] = true },
    },

    -- Доступ по отделам. Можно использовать конкретную фракцию или "*" для любой фракции.
    AllowedDepartments = {
        -- ["Полиция"] = { ["Патруль"] = true, ["Оперотдел"] = true },
    },

    DeniedFactions = {},
    DeniedRoles = {},
    DeniedDepartments = {},
}
