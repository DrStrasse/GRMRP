include("shared.lua")
function ENT:Draw()
 self:DrawModel();local lp=LocalPlayer();if not IsValid(lp)or lp:GetPos():DistToSqr(self:GetPos())>700*700 then return end
 local pos=self:GetPos()+Vector(0,0,self:OBBMaxs().z+14);local ang=EyeAngles();ang=Angle(0,ang.y-90,90)
 cam.Start3D2D(pos,ang,.08);draw.RoundedBox(10,-170,-34,340,68,Color(9,14,23,235));draw.SimpleText(self:GetQuestNPCName(),"DermaLarge",0,-9,Color(240,245,252),TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER);draw.SimpleText("[E] поговорить  •  ЗАДАНИЯ","DermaDefaultBold",0,17,Color(242,190,75),TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER);cam.End3D2D()
end
