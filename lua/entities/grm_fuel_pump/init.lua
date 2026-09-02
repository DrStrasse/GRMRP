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

--[[ Е НА КОЛОНКЕ — конечный автомат (заказ владельца 02.09.2026):

     • шланг висит на колонке      — E берёт пистолет в руки;
     • пистолет в руках, E здесь — вешает обратно;
     • пистолет в баке, покой      — E открывает диалог закачки:
       колонка читает бак машины, даёт выбрать литры, плата — по выбору;
     • идёт закачка                — E останавливает (шланг остаётся в баке).

     В машину пистолет вставляет ИГРОК (E по машине, см. PlayerUse-хук в
     sh_grm_fuel.lua): автоподключение «к ближайшей машине» убрано — оно
     и было жалоба «колонка сама ставит шланг». ]]
function ENT:Use(ply)
    if not IsValid(ply) or not GRM.Fuel then return end
    if ply:KeyDown(IN_SPEED) then return end
    local F = GRM.Fuel
    if ply:GetPos():DistToSqr(self:GetPos()) > 260 * 260 then return end

    if IsValid(self.GRMHoseCar) then
        if self:GetBusy() then
            F.StopPour(self, "Закачку остановили.")
        else
            F.OpenPourDialog(self, ply)
        end
        return
    end

    local okT, whyT = F.TakeHose(self, ply)
    if not okT and whyT and GRM.Notify then
        GRM.Notify(ply, tostring(whyT), 255, 180, 80)
    end
end

-- Колонку убрали со шлангом в баке — снимаем учёт, чтобы таймер не висел.
function ENT:OnRemove()
    if GRM.Fuel and GRM.Fuel.ForgetHose then GRM.Fuel.ForgetHose(self) end
end
