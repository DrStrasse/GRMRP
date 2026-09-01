AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

--[[ Скупщик руды. Вся логика (цены, продажа, выдача и сдача бура) живёт в
     GRM.Mining (lua/autorun/sh_grm_mining.lua) — здесь только NPC и вызов
     окна. Раньше этот файл дублировал у себя обработчики net, из-за чего
     правки приходилось вносить в двух местах. ]]

function ENT:Initialize()
    self:SetModel(self.Model)
    self:SetSolid(SOLID_BBOX)
    self:SetMoveType(MOVETYPE_NONE)
    self:SetCollisionGroup(COLLISION_GROUP_NPC)
    self:SetUseType(SIMPLE_USE)
    self:SetAutomaticFrameAdvance(true)
    self:SetNWString("GRMOreBuyerName", self:GetNWString("GRMOreBuyerName", "Скупщик руды"))
    self:SetupIdleAnimation()
end

function ENT:SetupIdleAnimation()
    local candidates = { self:SelectWeightedSequence(ACT_IDLE) }
    for _, name in ipairs({ "idle_all", "idle_all_01", "idle", "idle_unarmed", "stand", "ref" }) do
        candidates[#candidates + 1] = self:LookupSequence(name)
    end
    for _, seq in ipairs(candidates) do
        if seq and seq >= 0 then
            self:ResetSequence(seq)
            self:SetPlaybackRate(1)
            self:SetCycle(0)
            return
        end
    end
end

-- Анимация idle не требует тика каждый кадр: 0.02 давало 50 Think/сек на NPC.
function ENT:Think()
    self:NextThink(CurTime() + 0.25)
    return true
end

function ENT:Use(activator)
    if not (IsValid(activator) and activator:IsPlayer()) then return end
    if (self._grmNextUse or 0) > CurTime() then return end
    self._grmNextUse = CurTime() + 0.4
    if GRM.Mining and GRM.Mining.PushBuyer then
        GRM.Mining.PushBuyer(activator, self)
    elseif GRM.Notify then
        GRM.Notify(activator, "Модуль шахты не загружен.", 255, 130, 110)
    end
end

list.Set("SpawnableEntities", "grm_ore_buyer", {
    PrintName = "Скупщик руды",
    ClassName = "grm_ore_buyer",
    Category = "GRM MINE",
})
