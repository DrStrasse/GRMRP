AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

function ENT:Initialize()
    self:SetModel("models/props_wasteland/gaspump001a.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)
    if self:GetFuelKind() == "" then self:SetFuelKind("petrol") end
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:Wake() end
end

--[[ Е НА КОЛОНКЕ: подключить или убрать шланг.

     Раньше E выдавало игроку ОРУЖИЕ-пистолет, и он сам вставлял его
     в бак. По заказу владельца (31.08) шланг игроку не отдаётся:
     он живёт на колонке. E — подключить к ближайшей машине (или к
     той, на которую смотрит игрок), повторное E — убрать.

     Убрать шланг можно только так — осознанно. Никакой таймер и
     никакое расстояние до игрока его из бака не выдернет. ]]
function ENT:Use(ply)
    if not IsValid(ply) or not GRM.Fuel then return end
    if ply:KeyDown(IN_SPEED) then return end
    local F = GRM.Fuel
    if ply:GetPos():DistToSqr(self:GetPos()) > 260 * 260 then return end

    -- Шланг в баке — убираем.
    if IsValid(self.GRMHoseCar) then
        F.UnplugHose(self, ply, "Шланг убран.")
        return
    end

    local veh, err = F.FindTarget(self, ply)
    if not IsValid(veh) then
        if GRM.Notify then GRM.Notify(ply, err or "Рядом нет машины.", 255, 180, 80) end
        return
    end
    local ok, why = F.PlugHose(self, veh, ply)
    if not GRM.Notify then return end
    if ok then
        GRM.Notify(ply, "Шланг в баке. Идёт заливка.", 120, 220, 140)
    else
        GRM.Notify(ply, tostring(why or "Не вышло"), 255, 180, 80)
    end
end

-- Колонку убрали со шлангом в баке — снимаем учёт, чтобы таймер не висел.
function ENT:OnRemove()
    if GRM.Fuel and GRM.Fuel.ForgetHose then GRM.Fuel.ForgetHose(self) end
end
