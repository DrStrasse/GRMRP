-- Единый центр управления GRM: админка, сохранения, доступы и аугментации.
if not CLIENT then return end
local function open()
 local f=vgui.Create("DFrame"); f:SetTitle("GRM — ЕДИНЫЙ ЦЕНТР УПРАВЛЕНИЯ"); f:SetSize(math.min(760,ScrW()-60),math.min(680,ScrH()-60)); f:Center(); f:MakePopup()
 local info=vgui.Create("DLabel",f); info:SetPos(25,45); info:SetSize(700,32); info:SetText("Синхронизированный центр администрирования GRM"); info:SetTextColor(Color(100,200,255)); info:SetFont("DermaDefaultBold")
 local actions={{"Аугментации и доступы","grm_augmentations_admin"},{"Сохранения и базы","grm_persistence_admin"},{"Сеть и электроника","grm_network_admin"},{"Логистика","grm_logistics_admin_menu"},{"Экономика","grm_salary_admin"},{"Пермы оборудования","grm_perm_list"},
 -- Пожарная служба (заказ владельца 18.08): раньше в этом окне её не было вовсе
 {"Пожарные: доступы","grm_fire_access"},{"Пожарные: очаги","grm_fire_spots"},{"Пожарные: журнал","grm_fire_log"},{"Пожарные: вызовы","grm_fire_calls"},{"Пожарные: машины","grm_fire_trucks"},
 {"Полная админ-панель GRM","grm_admin"}}
 for i,a in ipairs(actions) do local x=25+((i-1)%2)*355; local y=95+math.floor((i-1)/2)*75; local b=vgui.Create("DButton",f); b:SetPos(x,y); b:SetSize(330,52); b:SetText(a[1]); b.DoClick=function() f:Close(); RunConsoleCommand(a[2]) end end
 local sync=vgui.Create("DButton",f); sync:SetPos(25,95+math.ceil(#actions/2)*75+10); sync:SetSize(685,45); sync:SetText("СИНХРОНИЗИРОВАТЬ СОСТОЯНИЕ GRM"); sync.DoClick=function() RunConsoleCommand("grm_persistence_admin"); chat.AddText(Color(80,210,150),"[GRM] Запрошена синхронизация сохранений") end
end
concommand.Add("grm_unified_admin",open)
concommand.Add("grm_admin_center",open)
print("[GRM UnifiedAdmin] loaded")
