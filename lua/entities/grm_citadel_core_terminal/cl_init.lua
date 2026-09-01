include("shared.lua")
if not CLIENT then return end
net.Receive("GRM_CitadelTerminal_Open",function()
 local terminal=net.ReadEntity(); local core=net.ReadEntity()
 local f=vgui.Create("DFrame"); f:SetTitle(""); f:SetSize(620,480); f:Center(); f:MakePopup(); f:ShowCloseButton(false)
 f.Paint=function(self,w,h) draw.RoundedBox(8,0,0,w,h,Color(8,16,28,250)); draw.RoundedBoxEx(8,0,0,w,58,Color(12,28,45),true,true,false,false); draw.SimpleText("ТЕРМИНАЛ ЯДРА ЦИТАДЕЛИ","DermaLarge",18,22,Color(220,240,250)); draw.SimpleText("СИСТЕМА УПРАВЛЕНИЯ ТЕМНОЙ МАТЕРИЕЙ","DermaDefault",18,45,Color(70,210,255)) end
 local close=vgui.Create("DButton",f); close:SetPos(580,14); close:SetSize(25,25); close:SetText("X"); close.DoClick=function() f:Close() end
 local l=vgui.Create("DLabel",f); l:SetPos(24,78); l:SetSize(570,190); l:SetFont("DermaDefaultBold"); l:SetTextColor(Color(180,230,255)); l:SetWrap(true)
 local function refresh()
  if not IsValid(core) then l:SetText("СВЯЗЬ С ЯДРОМ ОТСУТСТВУЕТ\n\nУстановите ядро рядом с терминалом и выполните повторное подключение.") return end
  l:SetText(string.format("ИДЕНТИФИКАТОР: %s\n\nУСТАНОВЛЕНО В КРЕПЛЕНИЕ: %s\nЭНЕРГИЯ: %.0f / %.0f\nВЫХОД: %.0f\nНАГРЕВ: %.1f%%\nСТАБИЛЬНОСТЬ: %.1f%%\nСОСТОЯНИЕ: %s",core:GetCoreID(),core:GetInstalled() and "ДА" or "НЕТ",core:GetEnergy(),core:GetMaxEnergy(),core:GetOutput(),core:GetHeat(),core:GetStability(),core:GetActive() and "АКТИВНО" or "ОТКЛЮЧЕНО"))
 end
 local y=290
 for _,v in ipairs({{"install","УСТАНОВИТЬ ЯДРО В КРЕПЛЕНИЕ"},{"toggle","ВКЛЮЧИТЬ / ВЫКЛЮЧИТЬ"},{"cool","ОХЛАДИТЬ И СТАБИЛИЗИРОВАТЬ"},{"fill","ЗАРЯДИТЬ ЯДРО"}}) do
  local b=vgui.Create("DButton",f); b:SetPos(24,y); b:SetSize(570,34); b:SetText(v[2]); b.DoClick=function() net.Start("GRM_CitadelTerminal_Action"); net.WriteEntity(terminal); net.WriteString(v[1]); net.SendToServer(); timer.Simple(.15,refresh) end; y=y+40
 end
 local timerName="GRM_CoreTerminal_"..math.random(100000,999999); timer.Create(timerName,.5,0,function() if IsValid(f) then refresh() else timer.Remove(timerName) end end); refresh()
end)
function ENT:Draw()
 self:DrawModel(); local p=self:GetPos()+self:GetUp()*28; -- метка следует за камерой рендера, а не за поворотом игрока
 cam.Start3D2D(p,Angle(0,EyeAngles().y-90,90),.08); draw.RoundedBox(5,-150,-30,300,60,Color(5,15,25,220)); draw.SimpleText("ТЕРМИНАЛ ЯДРА","DermaLarge",0,-15,Color(80,210,255),TEXT_ALIGN_CENTER); draw.SimpleText("E — управление","DermaDefault",0,14,Color(220,230,240),TEXT_ALIGN_CENTER); cam.End3D2D()
end
