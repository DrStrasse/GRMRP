AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

local function PL() return GRM and GRM.Plates end

function ENT:Initialize()
    self:SetModel(self.Model)
    self:SetModelScale(self.VisualScale or 0.70, 0)
    self:SetMaterial(self.Material)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
        phys:SetMass(2)
    end
    if self:GetNWString("GRM_Plate", "") == "" then
        self:SetNWString("GRM_Plate", "")
        self:SetNWString("GRM_PlateType", "civil")
        self:SetNWString("GRM_PlateStatus", "active")
        self:SetNWBool("GRM_PlateMounted", false)
    end
end

--- Записать на знак данные реестра.
function ENT:SetupPlate(rec)
    if not istable(rec) then return end
    self:SetNWString("GRM_Plate", tostring(rec.number or ""))
    self:SetNWString("GRM_PlateType", tostring(rec.type or "civil"))
    self:SetNWString("GRM_PlateStatus", tostring(rec.status or "active"))
    self:SetNWString("GRM_PlateOwner", tostring(rec.ownerName or ""))
    self.GRMPlateOwnerKey = tostring(rec.ownerKey or "")
end

--[[ Ближайший транспорт.

     Первая версия мерила расстояние до ЦЕНТРА машины и требовала 90 юнитов.
     У «Москвича» от заднего бампера до центра как раз около сотни — знак
     стоял вплотную, а система машину «не видела». Теперь меряем до
     ПОВЕРХНОСТИ (NearestPoint), ищем в широком радиусе и дополнительно
     простреливаем в обе стороны от плоскости знака. ]]
function ENT:FindVehicle(maxDist)
    local P = PL()
    if not P then return nil end
    maxDist = maxDist or 60
    local pos = self:GetPos()
    local best, bestD = nil, maxDist

    for _, ent in ipairs(ents.FindInSphere(pos, 400)) do
        if ent ~= self and P.LooksLikeVehicle(ent) then
            local base = P.VehicleBase(ent)
            if IsValid(base) then
                local near = base.NearestPoint and base:NearestPoint(pos) or base:GetPos()
                local d = near:Distance(pos)
                if d <= bestD then best, bestD = base, d end
            end
        end
    end
    if IsValid(best) then return best, bestD end

    -- запасной путь: трассируем в обе стороны от знака
    for _, dir in ipairs({ self:GetUp(), -self:GetUp(), self:GetForward(), -self:GetForward(),
                           self:GetRight(), -self:GetRight() }) do
        local tr = util.TraceLine({ start = pos, endpos = pos + dir * 80, filter = self })
        if tr.Hit and P.LooksLikeVehicle(tr.Entity) then
            return P.VehicleBase(tr.Entity), pos:Distance(tr.HitPos)
        end
    end
    return nil
end

function ENT:Use(ply)
    local P = PL()
    if not (IsValid(ply) and P) then return end
    if (self.GRMNextUse or 0) > CurTime() then return end
    self.GRMNextUse = CurTime() + 0.6
    P.HandlePlateUse(ply, self)
end

--- Закреплённый знак физганом не таскают: сначала снимите его [E].
function ENT:PhysgunPickup(ply)
    if IsValid(self:GetParent()) then return false end
    local P = PL()
    if not P then return true end
    return P.CanHandle(ply, self) == true
end

hook.Add("PhysgunPickup", "GRM_Plates_Pickup", function(ply, ent)
    if not (IsValid(ent) and ent:GetClass() == "grm_plate") then return end
    if IsValid(ent:GetParent()) then return false end
    local P = PL()
    if P and P.CanHandle then return P.CanHandle(ply, ent) == true end
end)

function ENT:OnRemove()
    local P = PL()
    local veh = self:GetParent()
    if P and IsValid(veh) and P.RememberLayout then
        timer.Simple(0, function()
            if IsValid(veh) then P.RememberLayout(veh) end
        end)
    end
end
