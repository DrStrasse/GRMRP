-- Stationary service terminal: CBaseAnimating is enough. base_ai registered the
-- entity in the NPC scheduler/think system despite having no navigation/combat.
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Служебный диспетчер GRM"
ENT.Author = "GRM"
ENT.Category = "GRM — RP"
ENT.Spawnable = false
ENT.AdminOnly = true
ENT.AutomaticFrameAdvance = true

function ENT:SetupDataTables() end
