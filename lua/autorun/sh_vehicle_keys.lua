--[[--------------------------------------------------------------------
    GRM Vehicle Keys (VK) — shared configuration and helpers
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

VK = VK or {}

VK.VERSION = "1.1.0"
VK.OWNER_TYPE = VK.OWNER_TYPE or {
    PLAYER = "player",
    FACTION = "faction",
}

VK.INTERACT_RANGE = VK.INTERACT_RANGE or 180
VK.HUD_RANGE = VK.HUD_RANGE or 220

VK.SND = VK.SND or {
    LOCK = "doors/latchbolt.wav",
    UNLOCK = "doors/latchunbolt.wav",
    DENY = "buttons/button11.wav",
    KEY_GET = "items/ammo_pickup.wav",
}

VK.KEY_CONFIG = VK.KEY_CONFIG or {
    -- Единая связка: старые ds_key_swep / vehicle_keys_swep удалены
    -- 31.08 по заказу владельца.
    SWEP_CLASS = "grm_keyring",
    AUTO_GIVE_SWEP = true,
    AUTO_STRIP_SWEP = true,
    DEFAULT_COLOR = { r = 100, g = 200, b = 255 },
}

VK.COL = VK.COL or (DS and DS.COL) or {
    BG = Color(8, 12, 28, 240),
    ACCENT = Color(55, 135, 255),
    SUCCESS = Color(50, 200, 90),
    DANGER = Color(220, 55, 55),
    WARNING = Color(255, 185, 40),
    TEXT = Color(225, 232, 255),
    DIM = Color(130, 145, 180),
    KEY = Color(255, 215, 0),
}

local function startsWith(text, prefix)
    return string.sub(string.lower(text or ""), 1, #prefix) == prefix
end

-- Standard vehicles, Simfphys and common LVS/LFS bases.
function VK.IsVehicle(ent)
    if not IsValid(ent) then return false end

    local ok, standardVehicle = pcall(ent.IsVehicle, ent)
    if ok and standardVehicle then return true end

    local class = string.lower(ent:GetClass() or "")

    if ent.IsSimfphysCar or ent.Simfphys or ent.IsSimfphys then return true end
    if startsWith(class, "simfphys_") or startsWith(class, "gcx_") or startsWith(class, "gmod_sent_vehicle_fphysics") then
        return true
    end

    if ent.LVS or ent.IsLVSVehicle or ent.IsLFSVehicle or ent.LFS then return true end
    if startsWith(class, "lvs_") or startsWith(class, "lfs_") or startsWith(class, "lunasflightschool_") then
        return true
    end

    -- Compatibility with Vehicle Dealer and similar systems.
    if ent.VD_ID then return true end

    return false
end

function VK.VehicleTypeLabel(ent)
    if not IsValid(ent) then return "Транспорт" end

    local class = string.lower(ent:GetClass() or "")

    if ent.IsSimfphysCar or ent.Simfphys or ent.IsSimfphys
        or startsWith(class, "simfphys_")
        or startsWith(class, "gcx_")
        or startsWith(class, "gmod_sent_vehicle_fphysics") then
        return "Simfphys"
    end

    if ent.LVS or ent.IsLVSVehicle or ent.IsLFSVehicle or ent.LFS
        or startsWith(class, "lvs_")
        or startsWith(class, "lfs_")
        or startsWith(class, "lunasflightschool_") then
        return "LVS/LFS"
    end

    return "Стандартный"
end

function VK.GetVehicleDisplayName(ent)
    if not IsValid(ent) then return "Транспорт" end

    if isfunction(ent.GetVehicleName) then
        local ok, name = pcall(ent.GetVehicleName, ent)
        if ok and isstring(name) and name ~= "" then return name end
    end

    if isstring(ent.PrintName) and ent.PrintName ~= "" then return ent.PrintName end
    if isstring(ent.VehicleName) and ent.VehicleName ~= "" then return ent.VehicleName end

    local class = ent:GetClass()
    local ok, vehicles = pcall(list.Get, "Vehicles")
    if ok and istable(vehicles) and vehicles[class] and vehicles[class].Name then
        return vehicles[class].Name
    end

    return class or "Транспорт"
end

function VK.GetOwnerState(veh)
    if not IsValid(veh) then
        return "", "", "", "", false
    end

    -- NW2 is authoritative for the client. Lua fields are used on server.
    if CLIENT then
        return veh:GetNW2String("VK_OwnerType", veh.VK_OwnerType or ""),
            veh:GetNW2String("VK_OwnerSteam", veh.VK_OwnerSteam or ""),
            veh:GetNW2String("VK_OwnerNick", veh.VK_OwnerNick or ""),
            veh:GetNW2String("VK_FactionName", veh.VK_FactionName or ""),
            veh:GetNW2Bool("VK_Locked", veh.VK_Locked == true)
    end

    return veh.VK_OwnerType or "", veh.VK_OwnerSteam or "", veh.VK_OwnerNick or "",
        veh.VK_FactionName or "", veh.VK_Locked == true
end

if CLIENT then
    CreateClientConVar("grm_cl_vehlock_key", "0", true, false, "Клавиша замка ТС (KEY_*, 0 = выкл)")

    hook.Add("PlayerButtonDown", "GRM_VK_LockBind", function(ply, key)
        if ply ~= LocalPlayer() then return end
        local want = math.floor(GetConVarNumber("grm_cl_vehlock_key") or 0)
        if want <= 0 or key ~= want then return end
        if ply:InVehicle() then return end
        if gui.IsGameUIVisible() or gui.IsConsoleVisible() then return end
        if ply.IsTyping and ply:IsTyping() then return end
        local now = CurTime()
        if now < (VK._lockBindAt or 0) then return end
        VK._lockBindAt = now + 0.35
        local veh = VK.GetAimedVehicle and VK.GetAimedVehicle(ply) or nil
        if not IsValid(veh) then
            local tr = ply:GetEyeTrace()
            veh = IsValid(tr.Entity) and VK.IsVehicle(tr.Entity) and tr.Entity or nil
        end
        if not IsValid(veh) then return end
        net.Start("VK_ToggleLock")
        net.WriteEntity(veh)
        net.SendToServer()
    end)
end
