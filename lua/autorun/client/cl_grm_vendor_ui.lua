-- GRM Vendor UI v2.0 — unified GRM storefront
if not CLIENT then return end
GRM=GRM or{}; GRM.Vendor=GRM.Vendor or{}; GRM.Vendor.UI=GRM.Vendor.UI or{}
local UI={bg=Color(11,16,24,252),head=Color(21,29,42),side=Color(17,24,35),card=Color(27,37,51),card2=Color(33,45,61),line=Color(57,76,99),text=Color(238,244,250),dim=Color(151,169,190),blue=Color(66,147,242),green=Color(61,190,117),red=Color(215,73,79),orange=Color(237,158,67),yellow=Color(239,198,81)}
surface.CreateFont("GRMVendor2_Title",{font="Roboto",size=23,weight=900,extended=true})
surface.CreateFont("GRMVendor2_Head",{font="Roboto",size=16,weight=800,extended=true})
surface.CreateFont("GRMVendor2_Body",{font="Roboto",size=13,weight=550,extended=true})
surface.CreateFont("GRMVendor2_Small",{font="Roboto",size=11,weight=500,extended=true})
local current={ent=nil,kind="",name="",catalog={}}
local function money(n)return GRM.Format and GRM.Format(n)or(tostring(n).." GRM")end
local function balance()return tonumber(GRM.PlayerBalance)or(GRM.GetBalance and tonumber(GRM.GetBalance(LocalPlayer())))or 0 end
local function button(parent,text,color)
 local b=vgui.Create("DButton",parent);b:SetText(text);b:SetFont("GRMVendor2_Body");b:SetTextColor(color_white)
 b.Paint=function(self,w,h)local c=color or UI.blue;if self:IsHovered()then c=Color(math.min(c.r+18,255),math.min(c.g+18,255),math.min(c.b+18,255))end;draw.RoundedBox(6,0,0,w,h,c)end;return b
end
local function functionText(item)
 local names={gasmask="Противогаз",backpack="Рюкзак",radio="Рация",watch="Часы",armor="Защита"};local out={}
 for id,on in pairs(item.functions or{})do if on then out[#out+1]=names[id]or id end end;table.sort(out);return table.concat(out," • ")
end
local function setupPreview(panel,model)
 if not util.IsValidModel(model or"")then return end
 panel:SetModel(model);local ent=panel:GetEntity();if not IsValid(ent)then return end
 local mn,mx=ent:GetRenderBounds();local size=math.max((mx-mn):Length(),12);panel:SetFOV(34);panel:SetCamPos(Vector(size,size,size*.55));panel:SetLookAt((mn+mx)*.5)
 panel.LayoutEntity=function(self,e)e:SetAngles(Angle(0,(RealTime()*20)%360,0))end
end

local function openStore(ent,kind,name,catalog)
 current={ent=ent,kind=kind,name=name,catalog=catalog}
 if IsValid(GRM.Vendor.UI.Frame)then GRM.Vendor.UI.Frame:Remove()end
 local f=vgui.Create("DFrame");GRM.UI.Track("vendor",f);GRM.Vendor.UI.Frame=f;f:SetSize(math.Clamp(ScrW()*.78,980,1380),math.Clamp(ScrH()*.82,680,900));f:Center();f:MakePopup();f:SetTitle("");f:ShowCloseButton(false)
 f.Paint=function(_,w,h)draw.RoundedBox(10,0,0,w,h,UI.bg);draw.RoundedBoxEx(10,0,0,w,64,UI.head,true,true,false,false);draw.SimpleText("GRM / ТОРГОВАЯ СИСТЕМА","GRMVendor2_Small",22,17,UI.blue);draw.SimpleText(name,"GRMVendor2_Title",22,42,UI.text,TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER);draw.SimpleText("Наличные: "..money(balance()),"GRMVendor2_Head",w-62,32,UI.green,TEXT_ALIGN_RIGHT,TEXT_ALIGN_CENTER)end
 local close=button(f,"×",UI.red);close:SetPos(f:GetWide()-44,16);close:SetSize(30,30);close.DoClick=function()f:Close()end
 local search=vgui.Create("DTextEntry",f);search:SetPos(18,78);search:SetSize(f:GetWide()-36,34);search:SetFont("GRMVendor2_Body");search:SetPlaceholderText("Поиск по названию, описанию или функции...")
 local side=vgui.Create("DScrollPanel",f);side:SetPos(18,124);side:SetSize(210,f:GetTall()-142)
 local content=vgui.Create("DScrollPanel",f);content:SetPos(240,124);content:SetSize(f:GetWide()-258,f:GetTall()-142)
 local selectedCategory="Все"
 local categories={["Все"]=true};for _,item in pairs(catalog)do categories[item.category or"Прочее"]=true end
 local function rebuild()
  content:Clear();local query=string.lower(string.Trim(search:GetValue()or""));local count=0
  local ids={};for id in pairs(catalog)do ids[#ids+1]=id end;table.sort(ids,function(a,b)return tostring(catalog[a].name)<tostring(catalog[b].name)end)
  for _,id in ipairs(ids)do local item=catalog[id];local category=item.category or"Прочее";local hay=string.lower(table.concat({item.name or"",item.desc or"",category,functionText(item)}," "))
   if(selectedCategory=="Все"or selectedCategory==category)and(query==""or string.find(hay,query,1,true))then
    count=count+1;local licNames={rifled="Нарезное",short="Короткоствольное",smooth="Гладкоствольное",traumatic="Травматическое",hunting="Охотничье"};local licText=item.requiresLicense and ("Лицензия: "..(licNames[item.weaponCategory]or tostring(item.weaponCategory or"оружейная")))or"";local row=vgui.Create("DPanel",content);row:Dock(TOP);row:SetTall(112);row:DockMargin(0,0,6,7);row.Paint=function(self,w,h)draw.RoundedBox(8,0,0,w,h,self:IsHovered()and UI.card2 or UI.card);surface.SetDrawColor(UI.line);surface.DrawOutlinedRect(0,0,w,h,1);draw.SimpleText(item.name or id,"GRMVendor2_Head",112,12,UI.text);draw.SimpleText(category.."  •  "..money(item.price),"GRMVendor2_Body",112,37,UI.yellow);draw.SimpleText(item.desc or"","GRMVendor2_Small",112,62,UI.dim);local ft=functionText(item);if licText~=""then draw.SimpleText(licText,"GRMVendor2_Small",112,84,UI.orange)elseif ft~=""then draw.SimpleText("Функции: "..ft,"GRMVendor2_Small",112,84,UI.green)end end
    local model=vgui.Create("DModelPanel",row);model:SetPos(7,7);model:SetSize(96,96);setupPreview(model,item.model)
    local actions=vgui.Create("DPanel",row);actions:Dock(RIGHT);actions:SetWide(126);actions:DockMargin(6,8,8,8);actions:SetPaintBackground(false)
    local buy=button(actions,"КУПИТЬ",UI.green);buy:Dock(TOP);buy:SetTall(42);buy.DoClick=function()surface.PlaySound("buttons/button15.wav");net.Start("GRM_Vendor_Buy")net.WriteEntity(ent)net.WriteString(id)net.SendToServer()end
    if(tonumber(item.sellPrice)or 0)>0 then local sell=button(actions,"Продать",UI.orange);sell:Dock(BOTTOM);sell:SetTall(35);sell.DoClick=function()Derma_StringRequest("Продажа","Количество:","1",function(v)net.Start("GRM_Vendor_Sell")net.WriteEntity(ent)net.WriteString(id)net.WriteUInt(math.Clamp(math.floor(tonumber(v)or 1),1,1000),16)net.SendToServer()end)end end
   end
  end
  if count==0 then local empty=vgui.Create("DLabel",content);empty:Dock(TOP);empty:SetTall(90);empty:SetFont("GRMVendor2_Head");empty:SetTextColor(UI.dim);empty:SetContentAlignment(5);empty:SetText("Товары не найдены")end
 end
 local cats={};for cat in pairs(categories)do cats[#cats+1]=cat end;table.sort(cats,function(a,b)if a=="Все"then return true elseif b=="Все"then return false end return a<b end)
 for _,cat in ipairs(cats)do local b=button(side,cat,UI.card);b:Dock(TOP);b:SetTall(36);b:DockMargin(0,0,5,5);b.Paint=function(self,w,h)local c=selectedCategory==cat and UI.blue or(self:IsHovered()and UI.card2 or UI.card);draw.RoundedBox(6,0,0,w,h,c)end;b.DoClick=function()selectedCategory=cat;surface.PlaySound("buttons/button14.wav");rebuild()end end
 search.OnChange=rebuild;rebuild()
end

net.Receive("GRM_Vendor_Open",function()local ent=net.ReadEntity();local kind=net.ReadString();local name=net.ReadString();local catalog=net.ReadTable()or{};openStore(ent,kind,name,catalog)end)
net.Receive("GRM_Vendor_Result",function()local ok,text=net.ReadBool(),net.ReadString();notification.AddLegacy(text,ok and NOTIFY_GENERIC or NOTIFY_ERROR,4);surface.PlaySound(ok and"buttons/button9.wav"or"buttons/button10.wav")end)
print("[GRM Vendor] Client UI v2.0 loaded")
