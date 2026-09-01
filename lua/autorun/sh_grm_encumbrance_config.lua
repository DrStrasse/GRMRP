--[[--------------------------------------------------------------------

    GRM Encumbrance — Shared Config

----------------------------------------------------------------------]]

GRM = GRM or {}
GRM.Encumbrance = GRM.Encumbrance or {}

GRM.Encumbrance.Config = {
    Capacity        = 65,
    HardMultiplier  = 1.25,
    DefaultItemWeight = 0.25,
    DefaultWeaponWeight = 1.5,
    SoftStart       = 0.5,
    SpeedAtCapacity = 0.72,
    SpeedAtHardLimit = 0.35,
    MinimumSpeed    = 0.25,
    UpdateInterval = 0.25,
    SyncInterval   = 0.5,
    BodyMassMinAdd = 0.2,
    BodyMassMaxAdd = 0.5,
    BodyMassCap = 12,
    BodyMassRunPerSec = 0.035,

    AmmoWeights = {
        Pistol        = 0.012,
        SMG1          = 0.008,
        AR2           = 0.015,
        ["357"]       = 0.025,
        Buckshot      = 0.032,
        XBowBolt      = 0.080,
        RPG_Round     = 2.500,
        Grenade       = 0.700,
        SMG1_Grenade  = 0.500,
        AR2AltFire    = 0.015,
        AirboatGun    = 0.008,
        Strider       = 0,
    },

    ItemWeights = {
        item_healthkit    = 1.0,
        item_battery      = 1.0,
        item_lockpick     = 0.3,
        item_repair_kit   = 1.5,
    },

    WeaponWeights = {
        weapon_pistol         = 1.2,
        weapon_357            = 1.3,
        weapon_smg1           = 3.0,
        weapon_ar2            = 4.5,
        weapon_shotgun        = 3.8,
        weapon_crossbow       = 4.0,
        weapon_rpg            = 8.0,
        weapon_frag           = 0.8,
        weapon_slam           = 1.0,
        weapon_crowbar        = 2.0,
        weapon_stunstick      = 2.5,
        weapon_physcannon     = 5.0,
        weapon_bugbait        = 0.5,
    },

    WeaponClassRules = {
        { pattern = "weapon_", weight = 2.5 },
        { pattern = "gms_",    weight = 3.0 },
        { pattern = "cw_",     weight = 3.5 },
        { pattern = "tfa_",    weight = 3.0 },
        { pattern = "arccw_",  weight = 3.5 },
        { pattern = "m9k_",    weight = 3.0 },
        { pattern = "zircon_", weight = 3.5 },
        { pattern = "ar2_",    weight = 4.0 },
    },
}
