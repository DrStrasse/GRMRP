AddCSLuaFile()

--[[ Узел руды. Логика добычи (проверка бура, троттлинг прогресса) живёт в
     GRM.Mining; здесь — модель, тип руды и разрушение. Отладочная печать в
     консоль на каждый удар убрана: на живой шахте это был спам. ]]
ENT.Type = "anim"
ENT.Base = "base_anim"

ENT.PrintName = "Узел руды"
ENT.Category = "GRM MINE"
ENT.Spawnable = true

ENT.Model = "models/props/cs_militia/militiarock05.mdl"
ENT.MineTime = 3

local function oreColor(oreType)
    if GRM and GRM.Mining and GRM.Mining.OreColor then return GRM.Mining.OreColor(oreType) end
    return Color(220, 220, 220)
end

local function oreList()
    if GRM and GRM.Mining and GRM.Mining.OreOrder then return GRM.Mining.OreOrder end
    return { "copper", "gold", "aluminum", "platinum" }
end

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "OreTypeNW")
end

function ENT:Initialize()
    if CLIENT then return end

    self:SetModel(self.Model)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_NONE)
    self:SetSolid(SOLID_VPHYSICS)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:EnableMotion(false) end

    if not self.OreType then
        local list = oreList()
        self:SetOreType(list[math.random(#list)])
    else
        self:SetOreType(self.OreType)
    end

    self.MineProgress = 0
    self.LastHitTime = 0
end

function ENT:SetOreType(oreType)
    oreType = tostring(oreType or "")
    if GRM and GRM.Mining and GRM.Mining.IsOre and not GRM.Mining.IsOre(oreType) then return end
    self.OreType = oreType
    self:SetOreTypeNW(oreType)
    -- Тип руды нужен и клиенту (подпись прогресса), и сейверу карты.
    self:SetNWString("GRM_OreType", oreType)
    self:SetColor(oreColor(oreType))
    self:SetMaterial("models/debug/debugwhite")
    self.MineProgress = 0
    self.LastHitTime = 0
end

if SERVER then
    function ENT:TakeDamageCustom(dmg, attacker)
        if not (IsValid(attacker) and attacker:IsPlayer()) then return end

        local ct = CurTime()
        -- Пауза больше секунды — прогресс сбрасывается: рудник не «копится» часами.
        if ct - (self.LastHitTime or 0) > 1 then self.MineProgress = 0 end
        self.LastHitTime = ct

        local mineTime = math.max(0.5, tonumber(self.MineTime) or 3)
        self.MineProgress = (self.MineProgress or 0) + math.max(0, tonumber(dmg) or 0) / 100
        local frac = math.Clamp(self.MineProgress / mineTime, 0, 1)

        if GRM.Mining and GRM.Mining.PushProgress then
            GRM.Mining.PushProgress(attacker, self, frac, frac >= 1)
        else
            net.Start("grm_ore_progress") net.WriteEntity(self) net.WriteFloat(frac) net.Send(attacker)
        end

        if self.MineProgress >= mineTime then self:OnDestroyed(attacker) end
    end

    function ENT:OnDestroyed(attacker)
        local pos = self:GetPos()
        if IsValid(attacker) then
            hook.Run("GRM_QuestEvent", attacker, "mining", tostring(self.OreType or "ore"), 1, { entity = self })
        end
        for _ = 1, math.random(4, 7) do
            local chunk = ents.Create("grm_ore_chunk")
            if IsValid(chunk) then
                chunk:SetPos(pos + VectorRand() * 30 + Vector(0, 0, 20))
                chunk:Spawn()
                chunk:SetOreType(self.OreType)
                local phys = chunk:GetPhysicsObject()
                if IsValid(phys) then phys:ApplyForceCenter(VectorRand() * 300) end
            end
        end
        self:EmitSound("physics/concrete/concrete_break3.wav", 75, math.random(90, 110))
        self:Remove()
    end
end
