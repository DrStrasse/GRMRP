if not CLIENT then return end
GRM=GRM or {}; GRM.AugmentationAccess=GRM.AugmentationAccess or {}
local A=GRM.AugmentationAccess
function A.OpenAdmin() if not LocalPlayer():IsSuperAdmin() then return end; net.Start("GRM_AugAccess_Request"); net.SendToServer() end
net.Receive("GRM_AugAccess_Data",function()
 local cfg=net.ReadTable() or {}; local factions=net.ReadTable() or {}; local f=vgui.Create("DFrame"); f:SetTitle("GRM — Доступ к аугментациям"); f:SetSize(760,600); f:Center(); f:MakePopup()
 local actions={"create","implant","reprogram","extract","hack_door"}; local names={create="Создание чипов",implant="Имплантация",reprogram="Перепрограммирование",extract="Извлечение",hack_door="Взлом дверей"}; local checks={}
 local y=55; local title=vgui.Create("DLabel",f); title:SetPos(20,30); title:SetSize(700,22); title:SetText("РАЗРЕШЕНИЯ ПО ФРАКЦИЯМ"); title:SetTextColor(Color(70,200,255))
 for _,act in ipairs(actions) do local c=vgui.Create("DCheckBoxLabel",f); c:SetPos(20,y); c:SetText(names[act]); c:SetValue(cfg.actions and cfg.actions[act] ~= false and 1 or 0); c:SetTextColor(Color(230,240,250)); checks[act]=c; y=y+30 end
 local box=vgui.Create("DScrollPanel",f); box:SetPos(260,55); box:SetSize(470,370); local selected={}; for _,act in ipairs(actions) do selected[act]={} end
 for _,act in ipairs(actions) do for name,on in pairs((cfg.factions and cfg.factions[act]) or {}) do if on then selected[act][name]=true end end end
 local yy=0; for _,name in ipairs(factions) do for _,act in ipairs(actions) do local c=vgui.Create("DCheckBoxLabel",box); c:SetPos(8,yy); c:SetSize(440,22); c:SetText(name.."  /  "..names[act]); c:SetTextColor(Color(210,225,235)); c:SetValue(selected[act][name] and 1 or 0); c.OnChange=function(_,v) selected[act][name]=v and true or nil end; yy=yy+24 end end; box:GetCanvas():SetTall(yy+5)
 local save=vgui.Create("DButton",f); save:SetPos(20,500); save:SetSize(710,42); save:SetText("СОХРАНИТЬ ДОСТУПЫ")
 save.DoClick=function() local d=cfg; d.actions=d.actions or {}; d.factions={}; for _,act in ipairs(actions) do d.actions[act]=checks[act]:GetChecked(); d.factions[act]={}; for name,on in pairs(selected[act]) do if on then d.factions[act][name]=true end end end; net.Start("GRM_AugAccess_Save"); net.WriteTable(d); net.SendToServer(); f:Close() end
end)
concommand.Add("grm_augmentation_access_admin",A.OpenAdmin)
