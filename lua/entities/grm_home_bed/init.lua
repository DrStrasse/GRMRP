AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    local mdl = self.Model
    if util.IsValidModel and not util.IsValidModel(mdl) then mdl = self.ModelFallback end
    self:SetModel(mdl)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
        --[[ Кровать — мебель, а не ящик: она не должна ездить по комнате
             от толчков и проваливаться сквозь пол на нагруженной карте. ]]
        phys:EnableMotion(false)
    end

    self:UpdateLink()
end

--[[ Обновить привязку к жилью. Кровать сама владельца не хранит —
     принадлежит объекту недвижимости, в чьей зоне стоит. Поэтому
     достаточно пересчитать, а не хранить и синхронизировать. ]]
function ENT:UpdateLink()
    local B = GRM.HomeBed
    local rec = B and B.PropertyOf and B.PropertyOf(self)
    self:SetLinked(istable(rec))
    self:SetHomeName(istable(rec) and tostring(rec.name or "") or "")
end

function ENT:Use(activator)
    if not (IsValid(activator) and activator:IsPlayer()) then return end
    local B = GRM.HomeBed
    if not B then return end
    -- Антиспам: E зажимают, а лечь/встать должно срабатывать по нажатию.
    if (self._grmNextUse or 0) > CurTime() then return end
    self._grmNextUse = CurTime() + 0.5

    if self:GetSleeper() == activator then
        B.GetUp(activator)
    else
        B.LieDown(activator, self)
    end
end

function ENT:OnRemove()
    local B = GRM.HomeBed
    local sleeper = self:GetSleeper()
    -- Кровать убрали из-под лежащего — обязательно поднимаем, иначе он
    -- останется замороженным навсегда.
    if IsValid(sleeper) and B and B.GetUp then B.GetUp(sleeper) end
end
