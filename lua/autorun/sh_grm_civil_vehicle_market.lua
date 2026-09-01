--[[ GRM Civil Vehicle Market v1.1.0
     Личный рынок транспорта: отдельный от GRM.Fleet контур.
     Оплата наличными/счётом, покупка кладёт машину в личный гараж. ]]
if SERVER then AddCSLuaFile() end
GRM = GRM or {}
GRM.CivilVehicles = GRM.CivilVehicles or {}
local CV = GRM.CivilVehicles
CV.Version = "1.1.0"
CV.Net = { OPEN="GRM_CivilVehicle_Open", SYNC="GRM_CivilVehicle_Sync", ACT="GRM_CivilVehicle_Act" }
CV.Data = CV.Data or { entries = {} }
local FILE = "grm_vehicle_market/civil.json"

local function trim(v,n) return string.sub(string.Trim(tostring(v or "")),1,n or 96) end
local function key(ply) return GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply) or (IsValid(ply) and ply:SteamID64()..":char1" or "") end
local function isAdmin(ply) return IsValid(ply) and ply:IsSuperAdmin() end
function CV.List()
 local out={} for id,e in pairs(CV.Data.entries or {}) do if istable(e)then e.id=id out[#out+1]=e end end
 table.sort(out,function(a,b)return tostring(a.name)<tostring(b.name)end)return out
end
function CV.FindForDealer(entry)
 if not istable(entry)then return nil end
 for id,e in pairs(CV.Data.entries or {})do
  if istable(e)and tostring(e.class or"")==tostring(entry.class or"")then e.id=id return e end
 end
 return nil
end

if SERVER then
 for _,n in pairs(CV.Net)do util.AddNetworkString(n)end
 local function ensure()if not file.IsDir("grm_vehicle_market","DATA")then file.CreateDir("grm_vehicle_market")end end
 CV._loaded=CV._loaded or false
 local function payload()
  if not CV._loaded then return nil end
  local rows={}for _,e in ipairs(CV.List())do rows[#rows+1]=e end
  return {version=1,entries=rows}
 end
 function CV.SaveNow()
  if not CV._loaded then return false end
  ensure();local ok,raw=pcall(util.TableToJSON,payload(),true);if not ok or not isstring(raw)then return false end
  file.Write(FILE,raw)return (file.Read(FILE,"DATA")or"")~=""
 end
 function CV.Save(why)
  if not CV._loaded then return false end
  if GRM.Save and GRM.Save.Mark then GRM.Save.Mark("grm_civil_vehicle_market",why or"гражданский рынок")end
  return CV.SaveNow()
 end
 function CV.Load()
  CV.Data.entries={};local raw=file.Read(FILE,"DATA")or"";local ok,t=pcall(util.JSONToTable,raw,false,true)
  if raw~=""and(not ok or not istable(t))then file.Write(FILE..".broken",raw)end
  for _,e in ipairs(ok and istable(t)and t.entries or{})do if istable(e)and trim(e.id)~=""then CV.Data.entries[trim(e.id)]=e end end
  CV._loaded=true
 end
 if GRM.Save and GRM.Save.Register then GRM.Save.Register("grm_civil_vehicle_market",{file=FILE,delay=2,label="гражданский рынок транспорта",build=payload})end
 local function allowed(ply,e)
  if not istable(e) then return false,"Позиция рынка не найдена" end
  if isAdmin(ply)then return true end
  local fac=ply:GetNWString("GRM_Faction","")
  if istable(e.factions)and #e.factions>0 then for _,f in ipairs(e.factions)do if tostring(f)==fac then return true end end return false,"Эта позиция не предназначена для вашей организации"end
  return true
 end
 local function snapshot(ply)
  local list={};for _,e in ipairs(CV.List())do local ok,why=allowed(ply,e);list[#list+1]={id=e.id,class=e.class,name=e.name,model=e.model,price=e.price,category=e.category,allowed=ok,reason=why or""}end
  local garages=(GRM.Garage and GRM.Garage.ChoicesFor)and GRM.Garage.ChoicesFor(ply,nil)or{}
  return {entries=list,garages=garages,admin=isAdmin(ply)}
 end
 CV.Viewers=CV.Viewers or {}
 function CV.Push(ply)
  local d=snapshot(ply);net.Start(CV.Net.SYNC)net.WriteTable(d)net.Send(ply)
 end
 function CV.PushViewers()
  for ply in pairs(CV.Viewers)do if IsValid(ply)then CV.Push(ply)else CV.Viewers[ply]=nil end end
 end
 function CV.Open(ply,source)
  if IsValid(source)then ply.GRM_CivilMarketSource=source end
  CV.Viewers[ply]=true
  net.Start(CV.Net.OPEN)net.Send(ply)CV.Push(ply)
 end
 hook.Add("PlayerDisconnected","GRM_CivilVehicle_Viewers",function(ply)CV.Viewers[ply]=nil end)
 local function pay(ply,amount,method)
  if method=="bank"then
   if not(GRM.Economy and GRM.Economy.BankBalance and GRM.Economy.BankTake)then return false,"Банк недоступен"end
   if GRM.Economy.BankBalance(ply)<amount then return false,"На счёте недостаточно средств"end
   return GRM.Economy.BankTake(ply,amount,"Покупка гражданского транспорта")~=false
  end
  if not(GRM.HasMoney and GRM.TakeMoney)or not GRM.HasMoney(ply,amount)then return false,"Недостаточно наличных"end
  GRM.TakeMoney(ply,amount,"Покупка гражданского транспорта")return true
 end
 net.Receive(CV.Net.ACT,function(_,ply)
  if not IsValid(ply)then return end
  local op=net.ReadString();local d=net.ReadTable()or{}
  ply.GRM_CivilMarketNext=ply.GRM_CivilMarketNext or 0
  if op~="refresh"and CurTime()<ply.GRM_CivilMarketNext then return end
  ply.GRM_CivilMarketNext=CurTime()+0.3
  local source=ply.GRM_CivilMarketSource
  if IsValid(source)and ply:GetPos():DistToSqr(source:GetPos())>260*260 then return end
  if op=="refresh"then CV.Viewers[ply]=true CV.Push(ply)return end
  if op=="watch"then CV.Viewers[ply]=d.on==true if d.on==true then CV.Push(ply)end return end
  if op=="buy"then
   local e=CV.Data.entries[tostring(d.id or"")];local ok,why=allowed(ply,e)
   if not e or not ok then return end
   local garage=GRM.Garage and GRM.Garage.ValidateChoice and GRM.Garage.ValidateChoice(ply,d.garageID)
   if not garage then return end
   local price=math.max(0,math.floor(tonumber(e.price)or 0));local paid,msg=pay(ply,price,tostring(d.payment))
   if not paid then if GRM.Notify then GRM.Notify(ply,msg or"Оплата не прошла",255,100,100)end return end
   local VD=GRM.VehicleDealer;local rec,err=VD and VD.CreatePersonalRecord and VD.CreatePersonalRecord(ply,{class=e.class,name=e.name,model=e.model,price=price,marketID=e.id},garage.id)
   if not rec then
    if tostring(d.payment)=="bank"and GRM.Economy and GRM.Economy.BankGive then GRM.Economy.BankGive(ply,price,"Откат покупки транспорта")elseif GRM.GiveMoney then GRM.GiveMoney(ply,price,"Откат покупки транспорта")end
    if GRM.Notify then GRM.Notify(ply,err or"Не удалось оформить транспорт",255,100,100)end return
   end
   if GRM.Notify then GRM.Notify(ply,"Транспорт оформлен и поставлен в личный гараж",90,220,140)end
   CV.Push(ply)return
  end
  if op=="add"and isAdmin(ply)then
   local class=trim(d.class);if class==""then return end
   local info=GRM.VehicleDealer and GRM.VehicleDealer.VehicleInfo and GRM.VehicleDealer.VehicleInfo(class)or{}
   local id="cv_"..os.time().."_"..math.random(100,999);CV.Data.entries[id]={id=id,class=class,name=trim(d.name~=""and d.name or info.name),model=tostring(info.model or""),price=math.max(0,math.floor(tonumber(d.price)or 0)),category=trim(d.category,48),factions=istable(d.factions)and d.factions or{}}
   CV.Save()CV.Push(ply)
  end
 end)
 local function boot()
  CV.Load()
  if GRM.Vendor and GRM.Vendor.RegisterType then GRM.Vendor.RegisterType("vehicle_market","Гражданский транспортный рынок","models/gman_high.mdl",{}) end
 end
 if GRM.Boot and GRM.Boot.OnMapStart then GRM.Boot.OnMapStart("GRM_CivilVehicle_Load","late",boot,{label="Гражданский рынок транспорта"})else hook.Add("InitPostEntity","GRM_CivilVehicle_Load",boot)end
 hook.Add("PlayerSay","GRM_CivilVehicle_Chat",function(ply,text)if string.lower(string.Trim(text or""))=="/transport_market"then CV.Open(ply)return""end end)
 concommand.Add("grm_civil_market",function(ply)if IsValid(ply)then CV.Open(ply)end end)
 concommand.Add("grm_civil_market_add",function(ply,_,args)
  if IsValid(ply)and not isAdmin(ply)then return end
  local class=trim(args[1]);local price=math.max(0,math.floor(tonumber(args[2])or 0));if class==""then return end
  local info=GRM.VehicleDealer and GRM.VehicleDealer.VehicleInfo and GRM.VehicleDealer.VehicleInfo(class)or{}
  local id="cv_"..os.time().."_"..math.random(100,999);CV.Data.entries[id]={id=id,class=class,name=trim(table.concat(args," ",3)~=""and table.concat(args," ",3)or info.name),model=tostring(info.model or""),price=price,category="Гражданский транспорт",factions={}}
  CV.Save("добавлена позиция");CV.PushViewers()
 end)
end

if CLIENT then
 surface.CreateFont("GRMCiv_Title",{font="Roboto",size=20,weight=800,extended=true})
 surface.CreateFont("GRMCiv_Sub",{font="Roboto",size=15,weight=700,extended=true})
 surface.CreateFont("GRMCiv_Body",{font="Roboto",size=13,weight=550,extended=true})
 surface.CreateFont("GRMCiv_Small",{font="Roboto",size=11,weight=500,extended=true})
 local C={
  bg=Color(16,20,28,252),sidebar=Color(12,15,22,255),card=Color(22,28,38,240),card2=Color(28,36,48,240),
  border=Color(38,48,66,200),accent=Color(65,145,235),gold=Color(245,195,65),green=Color(55,185,110),
  red=Color(225,70,70),text=Color(240,244,250),dim=Color(155,170,190)
 }
 local state={entries={},garages={},admin=false}
 local function act(op,d)net.Start(CV.Net.ACT)net.WriteString(op)net.WriteTable(d or{})net.SendToServer()end
 local function uiSound(kind)
  local path=kind=="hover"and"garrysmod/ui_hover.wav"or kind=="down"and"ui/buttonclick.wav"or"buttons/button15.wav"
  if GRM.Sound and GRM.Sound.UI then GRM.Sound.UI(path,0.04)else surface.PlaySound(path)end
 end
 local function skinEntry(e)
  e:SetFont("GRMCiv_Body")e:SetTextColor(C.text)
  e.Paint=function(s,w,h)
   draw.RoundedBox(5,0,0,w,h,C.card2)surface.SetDrawColor(C.border)surface.DrawOutlinedRect(0,0,w,h)
   s:DrawTextEntryText(C.text,C.accent,C.text)
   if s:GetText()==""and s.GetPlaceholderText and s:GetPlaceholderText()then
    draw.SimpleText(s:GetPlaceholderText(),"GRMCiv_Small",8,h/2,C.dim,TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER)
   end
  end
 end
 local function mkBtn(parent,label,col)
  local b=vgui.Create("DButton",parent)b:SetText("")b:SetCursor("hand")
  b.OnCursorEntered=function()uiSound("hover")end
  b.OnDepressed=function()uiSound("down")end
  b.Paint=function(s,w,h)
   local c=col or C.accent
   if not s:IsEnabled()then c=C.card2
   elseif s:IsDown()then c=Color(math.max(0,c.r-20),math.max(0,c.g-20),math.max(0,c.b-20))
   elseif s:IsHovered()then c=Color(math.min(255,c.r+22),math.min(255,c.g+22),math.min(255,c.b+22))end
   draw.RoundedBox(6,0,0,w,h,c)
   draw.SimpleText(label,"GRMCiv_Body",w/2,h/2,s:IsEnabled()and color_white or C.dim,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
  end
  return b
 end
 local function open()
  if IsValid(CV.Frame)then CV.Frame:Remove()end
  local f=vgui.Create("DFrame")CV.Frame=f
  if GRM.UI and GRM.UI.Track then GRM.UI.Track("grm_civil_market",f)end
  f:SetSize(math.Clamp(ScrW()*0.86,1100,1680),math.Clamp(ScrH()*0.84,700,1040))
  f:Center()f:SetTitle("")f:ShowCloseButton(false)f:SetDraggable(true)f:SetSizable(true)f:MakePopup()
  act("watch",{on=true})
  f.OnRemove=function()act("watch",{on=false})end
  f.Paint=function(_,w,h)
   draw.RoundedBox(8,0,0,w,h,C.bg)
   draw.RoundedBoxEx(8,0,0,w,48,C.sidebar,true,true,false,false)
   surface.SetDrawColor(C.border)surface.DrawOutlinedRect(0,0,w,h)
   draw.SimpleText("ГРАЖДАНСКИЙ РЫНОК ТРАНСПОРТА","GRMCiv_Title",18,24,C.gold,TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER)
   draw.SimpleText("Личная покупка · наличные или счёт · в выбранный гараж","GRMCiv_Small",w-56,24,C.dim,TEXT_ALIGN_RIGHT,TEXT_ALIGN_CENTER)
  end
  local close=vgui.Create("DButton",f)close:SetSize(34,30)close:SetText("")
  close.Paint=function(s,w,h)
   if s:IsHovered()then draw.RoundedBox(4,0,0,w,h,C.red)end
   draw.SimpleText("✕","GRMCiv_Sub",w/2,h/2,s:IsHovered()and color_white or C.dim,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
  end
  close.DoClick=function()f:Close()end
  f.PerformLayout=function(self,w)if IsValid(close)then close:SetPos(w-44,9)end end

  local body=vgui.Create("DPanel",f)
  body:Dock(FILL)body:DockMargin(12,52,12,12)body:SetPaintBackground(false)

  if state.admin then
   local admin=vgui.Create("DPanel",body)
   admin:Dock(TOP)admin:SetTall(78)admin:DockMargin(0,0,0,8)
   admin.Paint=function(_,w,h)
    draw.RoundedBox(6,0,0,w,h,C.card)
    draw.SimpleText("ДОБАВИТЬ ПОЗИЦИЮ НА РЫНОК","GRMCiv_Small",14,10,C.gold)
   end
   local class=vgui.Create("DTextEntry",admin)class:SetPos(12,32)class:SetSize(280,32)class:SetPlaceholderText("Класс: simfphys_…")skinEntry(class)
   local name=vgui.Create("DTextEntry",admin)name:SetPos(300,32)name:SetSize(280,32)name:SetPlaceholderText("Название")skinEntry(name)
   local price=vgui.Create("DTextEntry",admin)price:SetPos(588,32)price:SetSize(140,32)price:SetPlaceholderText("Цена")skinEntry(price)
   local add=mkBtn(admin,"ДОБАВИТЬ",C.green)add:SetPos(740,32)add:SetSize(150,32)
   add.DoClick=function()
    act("add",{class=class:GetValue(),name=name:GetValue(),price=tonumber(price:GetValue())or 0,category="Гражданский транспорт",factions={}})
   end
  end

  local bar=vgui.Create("DPanel",body)
  bar:Dock(TOP)bar:SetTall(44)bar:DockMargin(0,0,0,8)
  bar.Paint=function(_,w,h)
   draw.RoundedBox(6,0,0,w,h,C.card)
   draw.SimpleText("ГАРАЖ ПОСТАНОВКИ","GRMCiv_Small",14,h/2,C.dim,TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER)
  end
  local garage=""
  local combo=vgui.Create("DComboBox",bar)
  combo:Dock(FILL)combo:DockMargin(160,8,12,8)
  combo:SetFont("GRMCiv_Body")combo:SetTextColor(C.text)
  combo.Paint=function(s,w,h)
   draw.RoundedBox(5,0,0,w,h,C.card2)surface.SetDrawColor(C.border)surface.DrawOutlinedRect(0,0,w,h)
  end
  combo:SetValue(#(state.garages or{})>0 and "Выберите гараж" or "Нет доступных гаражей")
  for _,g in ipairs(state.garages or{})do
   combo:AddChoice(g.name,g.id,g.suggested==true)
   if g.suggested then garage=tostring(g.id or"")end
  end
  combo.OnSelect=function(_,_,_,v)garage=tostring(v or"")end

  local scroll=vgui.Create("DScrollPanel",body)
  scroll:Dock(FILL)
  local sbar=scroll:GetVBar()
  if IsValid(sbar)then
   sbar:SetWide(6)
   sbar.Paint=function(_,w,h)draw.RoundedBox(3,0,0,w,h,Color(18,22,32))end
   sbar.btnUp.Paint,sbar.btnDown.Paint=function()end,function()end
   sbar.btnGrip.Paint=function(_,w,h)draw.RoundedBox(3,0,0,w,h,C.border)end
  end

  if #(state.entries or{})==0 then
   local empty=vgui.Create("DPanel",scroll)
   empty:Dock(TOP)empty:SetTall(120)
   empty.Paint=function(_,w,h)
    draw.RoundedBox(8,0,0,w,h,C.card)
    draw.SimpleText("На рынке пока нет позиций","GRMCiv_Sub",w/2,h/2-10,C.text,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
    draw.SimpleText(state.admin and "Суперадмин: укажите класс, название и цену сверху." or "Загляните позже — каталог собирает администрация.",
     "GRMCiv_Small",w/2,h/2+14,C.dim,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
   end
  end

  for _,e in ipairs(state.entries or{})do
   local row=vgui.Create("DPanel",scroll)
   row:Dock(TOP)row:SetTall(138)row:DockMargin(0,0,8,8)
   row.Paint=function(_,w,h)
    draw.RoundedBox(8,0,0,w,h,C.card)
    surface.SetDrawColor(C.border)surface.DrawOutlinedRect(0,0,w,h)
    draw.SimpleText(tostring(e.name or"Транспорт"),"GRMCiv_Sub",156,18,C.text)
    draw.SimpleText(tostring(e.class or"").."  ·  "..tostring(e.category or"Гражданский транспорт"),"GRMCiv_Small",156,42,C.dim)
    local price=GRM.Format and GRM.Format(e.price)or tostring(e.price or 0)
    draw.SimpleText(price,"GRMCiv_Title",w-18,22,C.gold,TEXT_ALIGN_RIGHT)
    if e.allowed==false then
     draw.SimpleText(tostring(e.reason or"Недоступно"),"GRMCiv_Small",156,64,C.red)
    end
   end
   local preview=vgui.Create("DModelPanel",row)
   preview:SetPos(10,10)preview:SetSize(130,118)
   if util.IsValidModel(e.model or"")then
    preview:SetModel(e.model)
    local ent=preview:GetEntity()
    if IsValid(ent)then
     local mn,mx=ent:GetRenderBounds()
     local mid=(mn+mx)*0.5
     local size=math.max(16,(mx-mn):Length())
     preview:SetFOV(36)
     preview:SetLookAt(Vector(0,0,mid.z))
     preview:SetCamPos(Vector(size*0.7,size*0.55,mid.z+size*0.08))
    end
   end
   preview.LayoutEntity=function(self,ent)if self.bAnimated then self:RunAnimation()end ent:SetAngles(Angle(0,35,0))end
   local cash=mkBtn(row,"НАЛИЧНЫМИ",C.green)cash:SetSize(150,30)
   local bank=mkBtn(row,"СО СЧЁТА",C.accent)bank:SetSize(150,30)
   cash:SetEnabled(e.allowed~=false)
   bank:SetEnabled(e.allowed~=false)
   local function buy(method)
    if garage==""then notification.AddLegacy("Сначала выберите гараж постановки",NOTIFY_ERROR,3)return end
    act("buy",{id=e.id,garageID=garage,payment=method})
   end
   cash.DoClick=function()buy("cash")end
   bank.DoClick=function()buy("bank")end
   row.PerformLayout=function(_,w)
    cash:SetPos(w-168,62)
    bank:SetPos(w-168,98)
   end
  end
 end
 net.Receive(CV.Net.SYNC,function()state=net.ReadTable()or state;if IsValid(CV.Frame)then open()end end)
 net.Receive(CV.Net.OPEN,open)
end
