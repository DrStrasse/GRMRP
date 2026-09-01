--[[ GRM Service Orders v1.0 — paid/requested ATM services in organization computers. ]]
if SERVER then AddCSLuaFile()end
GRM=GRM or{};GRM.ServiceOrders=GRM.ServiceOrders or{};local O=GRM.ServiceOrders
O.Version="1.0.0";local NREQ="GRM_ServiceOrders_Request";local NDATA="GRM_ServiceOrders_Data"
if SERVER then
 util.AddNetworkString(NREQ);util.AddNetworkString(NDATA)
 local function snapshot(ply)
  local S=GRM.Services;if not S then return"",{}end;local faction=S.FactionOf and S.FactionOf(ply)or ply:GetNWString("GRM_Faction","");if faction==""and not ply:IsSuperAdmin()then return"",{}end
  local rows={};for _,rec in ipairs(S.OrderedServicesForFaction and S.OrderedServicesForFaction(faction,150)or{})do local slot=tostring(rec.target or""):match(":char([1-3])$");rows[#rows+1]={id=rec.id,characterKey=rec.target,playerName=tostring(rec.targetName or S.CharacterName(rec.target)or rec.target),characterLabel=slot and("Персонаж "..slot)or"Персонаж",serviceName=tostring(rec.title or"Услуга"),serviceID=tostring(rec.serviceID or""),status=tostring(rec.status or"unpaid"),amount=tonumber(rec.amount)or 0,paid=tonumber(rec.paid)or 0,orderedAt=tonumber(rec.issued)or 0,paidAt=tonumber(rec.paidAt or rec.closed)or 0,atmNumber=tonumber(rec.atmNumber)or 0,atmName=tostring(rec.atmName or"Банкомат")}end;return faction,rows
 end
 net.Receive(NREQ,function(bits,ply)if not IsValid(ply)then return end;if GRM.Net and not GRM.Net.Guard(ply,"services.orders.request",{rate=1,burst=2,maxBits=128},{bits=bits})then return end;local faction,rows=snapshot(ply);net.Start(NDATA);net.WriteString(faction);net.WriteTable(rows);net.Send(ply)end)
 local function inform(rec,text)if not rec or tostring(rec.serviceID or"")==""then return end;local S=GRM.Services;for _,p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll())do if IsValid(p)and S and S.FactionOf and S.FactionOf(p)==rec.faction then if GRM.Notify then GRM.Notify(p,text,105,210,145)else p:ChatPrint("[Услуги] "..text)end end end end
 hook.Add("GRM_InvoiceIssued","GRM_ServiceOrders_Issued",function(_,rec)if rec and rec.orderSource=="atm"then inform(rec,"Новый заказ услуги №"..rec.id..": "..rec.title)end end)
 hook.Add("GRM_InvoicePaid","GRM_ServiceOrders_Paid",function(_,rec)if rec and rec.status=="paid"and rec.serviceID~=""then inform(rec,"Услуга оплачена №"..rec.id..": "..rec.title)end end)
end
if CLIENT then
 surface.CreateFont("GRMSvcOrdHead",{font="Roboto",size=16,weight=800,extended=true});surface.CreateFont("GRMSvcOrdText",{font="Roboto",size=13,weight=500,extended=true})
 local views={}
 local function request()net.Start(NREQ);net.SendToServer()end
 local function statusName(st)return st=="paid"and"ОПЛАЧЕНО"or st=="cancelled"and"АННУЛИРОВАНО"or"ОЖИДАЕТ ОПЛАТЫ"end
 local function date(ts)if(tonumber(ts)or 0)<=0 then return"—"end return os.date("%d.%m.%Y %H:%M",ts)end
 function O.AttachTab(tabs)
  if not IsValid(tabs)then return end;local panel=vgui.Create("DPanel",tabs);panel:DockPadding(10,10,10,10);panel.Paint=function(_,w,h)draw.RoundedBox(6,0,0,w,h,Color(24,31,43))end
  local top=vgui.Create("DPanel",panel);top:Dock(TOP);top:SetTall(38);top:SetPaintBackground(false);local search=vgui.Create("DTextEntry",top);search:Dock(FILL);search:SetPlaceholderText("Поиск игрока, услуги или банкомата...");local refresh=vgui.Create("DButton",top);refresh:Dock(RIGHT);refresh:SetWide(130);refresh:SetText("Обновить");refresh.DoClick=request
  local list=vgui.Create("DListView",panel);list:Dock(FILL);list:DockMargin(0,8,0,0);list:AddColumn("№"):SetFixedWidth(45);list:AddColumn("Игрок / персонаж");list:AddColumn("Услуга");list:AddColumn("Статус"):SetFixedWidth(130);list:AddColumn("Оплата"):SetFixedWidth(100);list:AddColumn("Дата"):SetFixedWidth(135);list:AddColumn("Банкомат"):SetFixedWidth(150)
  local state={panel=panel,list=list,search=search,rows={},faction=""};views[#views+1]=state
  local function rebuild()
   if not IsValid(list)then return end;list:Clear();local q=string.lower(string.Trim(search:GetValue()or""))
   for _,r in ipairs(state.rows)do
    local atm=r.atmNumber>0 and("№"..r.atmNumber.." • "..r.atmName)or r.atmName;local player=r.playerName.." ("..r.characterLabel..")";local hay=string.lower(player.." "..r.serviceName.." "..atm.." "..statusName(r.status))
    if q==""or hay:find(q,1,true)then
     local line=list:AddLine(r.id,player,r.serviceName,statusName(r.status),tostring(r.paid).." / "..tostring(r.amount),date(r.paidAt>0 and r.paidAt or r.orderedAt),atm);local col=r.status=="paid"and Color(105,220,140)or r.status=="cancelled"and Color(225,100,100)or Color(235,190,90)
     for _,column in ipairs(line.Columns or{})do if column.SetTextColor then column:SetTextColor(col)end end
    end
   end
  end
  state.rebuild=rebuild;search.OnChange=rebuild;panel.Think=function(self)if(self._next or 0)<RealTime()then self._next=RealTime()+8;request()end end
  tabs:AddSheet("Заказанные услуги",panel,"icon16/cart.png");request()
 end
 net.Receive(NDATA,function()local faction,rows=net.ReadString(),net.ReadTable()or{};for i=#views,1,-1 do local v=views[i];if not IsValid(v.panel)then table.remove(views,i)else v.faction=faction;v.rows=rows;if v.rebuild then v.rebuild()end end end end)
end
print("[GRM ServiceOrders] v"..O.Version.." loaded")
