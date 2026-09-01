-- GRM Vehicle Dealer entity v3.0
AddCSLuaFile("cl_init.lua");AddCSLuaFile("shared.lua");include("shared.lua")
function ENT:Initialize()
 self:SetDealerID(self:GetDealerID()~=""and self:GetDealerID()or("dealer_"..util.CRC(game.GetMap()..":"..self:EntIndex()..":"..SysTime())))
 self:SetDealerName(self:GetDealerName()~=""and self:GetDealerName()or"Дилер транспорта")
 self:SetDealerModel(util.IsValidModel(self:GetDealerModel())and self:GetDealerModel()or"models/Humans/Group01/Male_02.mdl")
 self:SetModel(self:GetDealerModel());self:SetSolid(SOLID_BBOX);self:SetMoveType(MOVETYPE_NONE);self:SetCollisionBounds(Vector(-16,-16,0),Vector(16,16,72));self:SetCollisionGroup(COLLISION_GROUP_NPC);self:SetUseType(SIMPLE_USE);self:SetAutomaticFrameAdvance(true);self.VD_Vehicles=self.VD_Vehicles or{}
 self:ApplyIdleAnimation(true)
end

--[[ Сторож анимации: раз в 2 секунды проверяем, что дилер не «встал в
     reference» (Т-поза) после смены модели, перезагрузки карты или чужого
     аддона. Дёшево: сравнение имени последовательности, без трейсов. ]]
function ENT:Think()
    if (self._grmIdleCheck or 0) > CurTime() then return true end
    self._grmIdleCheck = CurTime() + 2
    self:ApplyIdleAnimation(false)
    self:NextThink(CurTime() + 2)
    return true
end
function ENT:Use(ply)if not IsValid(ply)or not ply:IsPlayer()then return end;if ply:GetPos():DistToSqr(self:GetPos())>(GRM.VehicleDealer.UseDistance or 180)^2 then return end;GRM.VehicleDealer.Push(ply,self)end
function ENT:OnRemove()if self.VD_PermanentDelete and GRM.VehicleDealer then GRM.VehicleDealer.DeleteDealer(self)end end
