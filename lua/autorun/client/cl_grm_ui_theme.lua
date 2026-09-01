-- Единая GRM/XUI тема: киберпанк-палитра и базовые строительные блоки.
if not CLIENT then return end
GRM=GRM or {}; GRM.UI=GRM.UI or {}; GRM.UI.Theme=GRM.UI.Theme or {}
local T=GRM.UI.Theme
T.Colors={bg=Color(8,14,23,248),panel=Color(16,27,42,245),panel2=Color(22,37,56,245),header=Color(10,22,37,255),text=Color(225,238,247),muted=Color(132,160,178),cyan=Color(48,204,255),green=Color(64,222,147),amber=Color(250,185,63),red=Color(244,78,96),purple=Color(174,98,255),line=Color(55,117,151,190)}
for name,size,weight in pairs({Title={24,800},Header={17,750},Body={14,500},Small={12,500},Mono={12,500}}) do surface.CreateFont("GRM_XUI_"..name,{font=name=="Mono" and "Roboto" or "Roboto",size=size,weight=weight,extended=true}) end
function T.PaintPanel(self,w,h,accent) draw.RoundedBox(8,0,0,w,h,T.Colors.panel); surface.SetDrawColor(accent or T.Colors.line); surface.DrawOutlinedRect(0,0,w,h,1) end
function T.PaintHeader(self,w,h,title,sub,accent) draw.RoundedBoxEx(8,0,0,w,h,T.Colors.header,true,true,false,false); draw.SimpleText(title,"GRM_XUI_Header",16,18,T.Colors.text,TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER); if sub then draw.SimpleText(sub,"GRM_XUI_Small",16,39,accent or T.Colors.cyan,TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER) end end
function T.ApplyFrame(f,key,title,subtitle)
    if key then GRM.UI.Track(key,f) end; f:SetTitle(""); f.Paint=function(self,w,h) draw.RoundedBox(9,0,0,w,h,T.Colors.bg); T.PaintHeader(self,w,52,title,subtitle) end
    f:ShowCloseButton(false); local close=vgui.Create("DButton",f); close:SetPos(f:GetWide()-40,12); close:SetSize(28,28); close:SetText("X"); close:SetFont("GRM_XUI_Header"); close:SetTextColor(T.Colors.text); close.Paint=function(self,w,h) draw.RoundedBox(4,0,0,w,h,self:IsHovered() and T.Colors.red or T.Colors.panel2) end; close.DoClick=function() f:Close() end
    return f
end
print("[GRM XUI] cyberpunk theme loaded")
