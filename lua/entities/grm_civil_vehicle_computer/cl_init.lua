include("shared.lua")
function ENT:Draw()
 self:DrawModel()
 local pos=self:GetPos()+self:GetUp()*24+self:GetForward()*2
 local ang=self:GetAngles();ang:RotateAroundAxis(ang:Up(),90);ang:RotateAroundAxis(ang:Forward(),90)
 cam.Start3D2D(pos,ang,.08)
  draw.RoundedBox(6,-170,-48,340,96,Color(10,22,37,240))
  draw.SimpleText(self:GetComputerName()~=""and self:GetComputerName()or"ГРАЖДАНСКИЙ РЫНОК ТРАНСПОРТА","DermaDefaultBold",0,-20,Color(64,222,147),TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
  draw.SimpleText("Личный транспорт · наличные или счёт","DermaDefault",0,2,Color(225,238,247),TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
  draw.SimpleText("Нажмите [E]","DermaDefault",0,24,Color(132,160,178),TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
 cam.End3D2D()
end
