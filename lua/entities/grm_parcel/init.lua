AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

local CARRY_POS = Vector(24, 0, 40)
local CARRY_ANG = Angle(0, 90, 0)

function ENT:Initialize()
    self:SetModel("models/props_junk/cardboard_box004a.mdl")
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:PhysicsInit(SOLID_VPHYSICS)
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:Wake() end
end

--[[ ВЗЯТЬ В РУКИ. Пока посылку несут, физика выключена и коробка
     припаркована к модели игрока: иначе она застревает в геометрии и
     улетает от каждого толчка. ]]
function ENT:AttachTo(ply)
    if not IsValid(ply) then return false end
    self:SetCarrier(ply)
    self:SetParent(ply)
    self:SetMoveType(MOVETYPE_NONE)
    self:SetSolid(SOLID_NONE)
    self:SetCollisionGroup(COLLISION_GROUP_IN_VEHICLE)
    self:SetLocalPos(CARRY_POS)
    self:SetLocalAngles(CARRY_ANG)
    ply:SetNWEntity("GRM_Parcel", self)
    return true
end

--[[ ВЫПУСТИТЬ ИЗ РУК. Возвращаем физику, чтобы коробка лежала на земле и
     её мог поднять любой желающий: именно это делает посылку предметом
     торга, а не декорацией. ]]
function ENT:Detach(dropPos)
    local carrier = self:GetCarrier()
    if IsValid(carrier) and carrier:GetNWEntity("GRM_Parcel") == self then
        carrier:SetNWEntity("GRM_Parcel", NULL)
    end
    self:SetCarrier(NULL)
    self:SetParent(nil)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetCollisionGroup(COLLISION_GROUP_NONE)
    if dropPos then self:SetPos(dropPos) end
    self:PhysicsInit(SOLID_VPHYSICS)
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:Wake() end
    return true
end

-- Носильщик исчез (вышел с сервера) — роняем на его последнем месте,
-- а не удаляем: заказ ещё можно спасти, если кто-то донесёт.
function ENT:Think()
    local carrier = self:GetCarrier()
    if IsValid(self:GetParent()) and not IsValid(carrier) then
        self:Detach(self:GetPos())
    end
    self:NextThink(CurTime() + 1)
    return true
end

function ENT:Use(activator)
    if not IsValid(activator) or not activator:IsPlayer() then return end
    if IsValid(self:GetCarrier()) then return end
    if GRM and GRM.Jobs and GRM.Jobs.PickupParcel then
        GRM.Jobs.PickupParcel(activator, self)
    end
end

function ENT:OnRemove()
    local carrier = self:GetCarrier()
    if IsValid(carrier) and carrier:GetNWEntity("GRM_Parcel") == self then
        carrier:SetNWEntity("GRM_Parcel", NULL)
    end
end
