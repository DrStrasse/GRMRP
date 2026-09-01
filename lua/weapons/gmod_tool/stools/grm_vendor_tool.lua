-- GRM Vendor Tool v2.0 — spawn, configure stock and autosave
TOOL.Category = "GRM";TOOL.Name = "#tool.grm_vendor_tool.name";TOOL.Command=nil;TOOL.ConfigName=""
TOOL.ClientConVar={type="weapon"}
-- Список типов берём из реестра GRM.Vendor (v2.2.0): новый торговец
-- (например, салон связи) появляется в тулгане сам, без правки этого файла.
local function TYPESLIST()
    return (GRM and GRM.Vendor and GRM.Vendor.TypeNames)
        or {weapon="Оружие",ore="Руда",food="Еда",rare="Редкости",accessory="Аксессуары"}
end
local TYPES=setmetatable({},{__index=function(_,k)return TYPESLIST()[k]end,
    __pairs=function()return pairs(TYPESLIST())end})
if CLIENT then language.Add("tool.grm_vendor_tool.name", "GRM Торговец");language.Add("tool.grm_vendor_tool.desc","Создание, ассортимент, цены и сохранение торговцев");language.Add("tool.grm_vendor_tool.0","ЛКМ: поставить • ПКМ: настроить • R: убрать с карты")end

function TOOL:LeftClick(tr)
 if not tr.Hit then return false end;if CLIENT then return true end
 local ply=self:GetOwner();if not IsValid(ply)or not ply:IsSuperAdmin()then return false end
 local kind=self:GetClientInfo("type");if not TYPES[kind]then kind="weapon"end
 if #ents.FindByClass("grm_vendor")>=(GRM.Vendor.Config.MaxVendors or 64)then GRM.Notify(ply,"Лимит торговцев на карте",255,100,100)return false end
 local ent=ents.Create("grm_vendor");if not IsValid(ent)then return false end
 ent.VendorType=kind;ent:SetPos(tr.HitPos+tr.HitNormal);ent:SetAngles(Angle(0,ply:EyeAngles().y+180,0));ent:Spawn();ent:Activate()
 local phys=ent:GetPhysicsObject();if IsValid(phys)then phys:EnableMotion(false);phys:Sleep()end
 local ok,id=GRM.Vendor.SaveVendor(ent)
 undo.Create("GRM_Vendor");undo.AddEntity(ent);undo.SetPlayer(ply);undo.Finish()
 GRM.Notify(ply,ok and("Торгаш поставлен и сохранён: "..tostring(id))or"Торгаш поставлен, но запись не подтверждена",ok and 100 or 255,ok and 220 or 100,120)
 return true
end

function TOOL:RightClick(tr)
 if CLIENT then return true end;local ply=self:GetOwner();local ent=tr.Entity
 if not IsValid(ply)or not ply:IsSuperAdmin()or not IsValid(ent)or ent:GetClass()~="grm_vendor"then return false end
 net.Start("GRM_VendorTool_Config")net.WriteEntity(ent)net.WriteTable({vendorType=ent.VendorType,displayName=ent.DisplayName,model=ent:GetModel(),customPrices=ent.CustomPrices or{},customLimits=ent.CustomLimits or{},enabledItems=ent.EnabledItems or{},catalog=GRM.Vendor.GetCatalog(ent.VendorType),vendorID=ent.GRMVendorID})net.Send(ply);return true
end

function TOOL:Reload(tr)
 if CLIENT then return true end;local ply=self:GetOwner();local ent=tr.Entity
 if not IsValid(ply)or not ply:IsSuperAdmin()or not IsValid(ent)or ent:GetClass()~="grm_vendor"then return false end
 local id=tostring(ent.GRMVendorID or"");ent:Remove();GRM.Notify(ply,"NPC убран с карты; запись "..id.." сохранена. Вернуть: /vendor_load",100,190,255);return true
end

if SERVER then
 util.AddNetworkString("GRM_VendorTool_Config");util.AddNetworkString("GRM_VendorTool_Result")
 net.Receive("GRM_VendorTool_Config",function(_,ply)
  if not IsValid(ply)or not ply:IsSuperAdmin()then return end
  local ent,data=net.ReadEntity(),net.ReadTable()or{};if not IsValid(ent)or ent:GetClass()~="grm_vendor"then return end
  if ply:GetPos():DistToSqr(ent:GetPos())>400*400 then return end
  local kind=tostring(data.vendorType or ent.VendorType);if not TYPES[kind]or not GRM.Vendor.Catalogs[kind]then kind=ent.VendorType end
  ent.VendorType=kind;ent.DisplayName=tostring(data.displayName or""):sub(1,64)
  local model=tostring(data.model or"");ent.VendorModel=util.IsValidModel(model)and model or"";ent:SetModel(ent.VendorModel~=""and ent.VendorModel or(GRM.Vendor.Models[kind]or"models/kleiner.mdl"))
  local catalog=GRM.Vendor.GetCatalog(kind);ent.CustomPrices={};ent.CustomLimits={};ent.EnabledItems={}
  for id,item in pairs(catalog)do
   if istable(data.customPrices)and data.customPrices[id]~=nil then ent.CustomPrices[id]=math.Clamp(math.floor(tonumber(data.customPrices[id])or item.price or 0),0,100000000)end
   if istable(data.customLimits)and(tonumber(data.customLimits[id])or 0)>0 then ent.CustomLimits[id]=math.Clamp(math.floor(tonumber(data.customLimits[id])),1,10000)end
   ent.EnabledItems[id]=not istable(data.enabledItems) or data.enabledItems[id]~=false
  end
  ent:SetNWString("VendorType",kind);ent:SetNWString("GRMVendorName",GRM.Vendor.GetDisplayName(ent));if ent.SetupIdleAnimation then ent:SetupIdleAnimation()end
  local ok,detail=GRM.Vendor.SaveVendor(ent)
  net.Start("GRM_VendorTool_Result")net.WriteBool(ok==true)net.WriteString(ok and("Настройки и торговец сохранены: "..tostring(detail))or tostring(detail or"Ошибка записи"))net.Send(ply)
 end)
end

if CLIENT then
 local UI={bg=Color(12,17,25,252),head=Color(22,30,43),card=Color(29,40,55),text=Color(238,244,250),dim=Color(151,169,190),blue=Color(65,145,240),green=Color(60,190,115),red=Color(215,75,80),orange=Color(235,158,68)}
 surface.CreateFont("GRMVendorToolTitle",{font="Roboto",size=21,weight=900,extended=true});surface.CreateFont("GRMVendorToolBody",{font="Roboto",size=13,weight=600,extended=true});surface.CreateFont("GRMVendorToolSmall",{font="Roboto",size=11,weight=500,extended=true})
 local function button(p,t,c)local b=vgui.Create("DButton",p);b:SetText(t);b:SetFont("GRMVendorToolBody");b:SetTextColor(color_white);b.Paint=function(self,w,h)local x=self:IsHovered()and Color(math.min(c.r+18,255),math.min(c.g+18,255),math.min(c.b+18,255))or c;draw.RoundedBox(6,0,0,w,h,x)end;return b end
 net.Receive("GRM_VendorTool_Config",function()
  local ent,data=net.ReadEntity(),net.ReadTable()or{};local catalog=data.catalog or{};local f=vgui.Create("DFrame");GRM.UI.Track("vendor_config",f);f:SetSize(920,760);f:Center();f:MakePopup();f:SetTitle("");f:ShowCloseButton(false)
  f.Paint=function(_,w,h)draw.RoundedBox(9,0,0,w,h,UI.bg);draw.RoundedBoxEx(9,0,0,w,58,UI.head,true,true,false,false);draw.SimpleText("GRM / НАСТРОЙКА ТОРГАША","GRMVendorToolTitle",18,29,UI.text,TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER)end
  local close=button(f,"×",UI.red);close:SetPos(875,14);close:SetSize(30,30);close.DoClick=function()f:Close()end
  local name=vgui.Create("DTextEntry",f);name:SetPos(18,72);name:SetSize(350,30);name:SetPlaceholderText("Название торговца");name:SetText(data.displayName or"")
  local model=vgui.Create("DTextEntry",f);model:SetPos(380,72);model:SetSize(520,30);model:SetPlaceholderText("models/...mdl");model:SetText(data.model or"")
  local scroll=vgui.Create("DScrollPanel",f);scroll:SetPos(18,116);scroll:SetSize(882,580)
  for id,item in SortedPairsByMemberValue(catalog,"category")do local row=vgui.Create("DPanel",scroll);row:Dock(TOP);row:SetTall(58);row:DockMargin(0,0,0,5);row.Paint=function(_,w,h)draw.RoundedBox(6,0,0,w,h,UI.card);draw.SimpleText(item.name or id,"GRMVendorToolBody",44,9,UI.text);draw.SimpleText((item.category or"Прочее").." • база "..tostring(item.price or 0),"GRMVendorToolSmall",44,33,UI.dim)end
   local enabled=vgui.Create("DCheckBox",row);enabled:SetPos(12,20);enabled:SetValue(not data.enabledItems or next(data.enabledItems)==nil or data.enabledItems[id]==true)
   local price=vgui.Create("DNumberWang",row);price:SetPos(560,9);price:SetSize(130,26);price:SetMin(0);price:SetMax(100000000);price:SetValue((data.customPrices or{})[id]or item.price or 0)
   local limit=vgui.Create("DNumberWang",row);limit:SetPos(705,9);limit:SetSize(90,26);limit:SetMin(0);limit:SetMax(10000);limit:SetValue((data.customLimits or{})[id]or 0)
   local pl=vgui.Create("DLabel",row);pl:SetPos(560,36);pl:SetSize(130,18);pl:SetText("Цена");pl:SetTextColor(UI.dim);local ll=vgui.Create("DLabel",row);ll:SetPos(705,36);ll:SetSize(130,18);ll:SetText("Лимит 0=∞");ll:SetTextColor(UI.dim)
   row._id=id;row._enabled=enabled;row._price=price;row._limit=limit;row._base=item.price or 0
  end
  local save=button(f,"СОХРАНИТЬ И ПРИМЕНИТЬ",UI.green);save:SetPos(18,708);save:SetSize(882,36);save.DoClick=function()local prices,limits,enabled={},{},{};for _,row in ipairs(scroll:GetCanvas():GetChildren())do if row._id then enabled[row._id]=row._enabled:GetChecked();local p=math.floor(row._price:GetValue());local l=math.floor(row._limit:GetValue());if p~=row._base then prices[row._id]=p end;if l>0 then limits[row._id]=l end end end;net.Start("GRM_VendorTool_Config")net.WriteEntity(ent)net.WriteTable({vendorType=data.vendorType,displayName=name:GetValue(),model=model:GetValue(),customPrices=prices,customLimits=limits,enabledItems=enabled})net.SendToServer();surface.PlaySound("buttons/button15.wav")end
 end)
 net.Receive("GRM_VendorTool_Result",function()local ok,text=net.ReadBool(),net.ReadString();notification.AddLegacy(text,ok and NOTIFY_GENERIC or NOTIFY_ERROR,5);surface.PlaySound(ok and"buttons/button9.wav"or"buttons/button10.wav")end)
 function TOOL.BuildCPanel(panel)panel:AddControl("Header",{Description="GRM Торгаш v2: автоматически сохраняет тип, модель, ассортимент, цены и лимиты"});local options={};for id,name in pairs(TYPESLIST())do options[name]={["grm_vendor_tool_type"]=id}end;panel:AddControl("ComboBox",{Label="Тип торговца",Options=options});panel:Help("ЛКМ — поставить и сохранить\nПКМ — GRM-настройки\nR — убрать NPC, сохранив запись\n/vendor_unsave — удалить запись навсегда")end
end
