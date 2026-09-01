--[[ Скупщик руды — стационарный NPC шахты. Спавн только администрацией:
     раньше AdminOnly = false пускал любого игрока ставить скупщиков из
     спавн-меню. ]]
ENT.Type = "anim"
ENT.Base = "base_anim"

ENT.PrintName = "Скупщик руды"
ENT.Category = "GRM MINE"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.AutomaticFrameAdvance = true
ENT.RenderGroup = RENDERGROUP_BOTH

ENT.Model = "models/Kleiner.mdl"
