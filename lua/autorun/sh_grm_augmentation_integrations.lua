-- GRM Augmentation Integrations: безопасный мост чипов к подсистемам сборки.
if SERVER then AddCSLuaFile() end
GRM = GRM or {}
GRM.AugmentationIntegrations = GRM.AugmentationIntegrations or {}
local I = GRM.AugmentationIntegrations
I.Profiles = {
    civilian={inventory=true, medical=true, personal=true},
    service={inventory=true, medical=true, radio=true, electronics=true, faction=true},
    military={inventory=true, medical=true, radio=true, electronics=true, faction=true, tactical=true},
    experimental={inventory=true, medical=true, radio=true, electronics=true, faction=true, tactical=true, bio=true}
}
function I.GetProfile(chip) return I.Profiles[chip and chip.category or "civilian"] or I.Profiles.civilian end
function I.Apply(ply, chip)
    if not IsValid(ply) or not chip then return end
    local profile=I.GetProfile(chip); ply:SetNWString("GRM_AugProfile", chip.category or "civilian")
    ply:SetNWString("GRM_AugChipID", chip.id or "")
    for key, value in pairs(profile) do ply:SetNWBool("GRM_Aug_"..key, value == true) end
    if profile.inventory and chip.modifiers and chip.modifiers.carryWeight and GRM.Inventory and GRM.Inventory.SetBonusWeight then GRM.Inventory.SetBonusWeight(ply, chip.modifiers.carryWeight) end
    if profile.tactical then hook.Run("GRM_Augmentation_TacticalLink", ply, chip) end
    if profile.electronics then hook.Run("GRM_Augmentation_ElectronicsLink", ply, chip) end
    if profile.faction then hook.Run("GRM_Augmentation_FactionLink", ply, chip) end
    hook.Run("GRM_Augmentation_ChipActivated", ply, chip, profile)
end
function I.Remove(ply, chip)
    if not IsValid(ply) then return end
    ply:SetNWString("GRM_AugProfile", "none"); ply:SetNWString("GRM_AugChipID", "")
    for key in pairs(I.Profiles.experimental) do ply:SetNWBool("GRM_Aug_"..key, false) end
    hook.Run("GRM_Augmentation_ChipDeactivated", ply, chip)
end
-- Public extension point: phones, radio, economy, tickets, GPS and vendors can subscribe without hard dependencies.
hook.Add("GRM_Augmentation_ChipActivated", "GRM_AugIntegrations_Log", function(ply, chip, profile)
    if SERVER then print("[GRM Aug] link "..tostring(chip.category).." -> "..tostring(ply:Nick())) end
end)
if SERVER then
    hook.Add("PlayerSpawn", "GRM_AugIntegrations_Restore", function(ply)
        timer.Simple(0.4, function()
            if not IsValid(ply) or not GRM.AugChips then return end
            for _, chip in ipairs(GRM.AugChips.GetPlayerChips(ply) or {}) do if chip.implanted and chip.active ~= false then I.Apply(ply, chip) end end
        end)
    end)
end
print("[GRM AugIntegrations] bridge loaded")
