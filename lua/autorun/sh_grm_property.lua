-- Boot-шим: старт подсистемы идёт через планировщик GRM.Boot (приоритеты и
-- бюджет на тик). Если планировщик почему-то не загружен, работаем по-старому.
local function grmBootStart(id, tier, fn)
    if GRM and GRM.Boot and GRM.Boot.OnMapStart then return GRM.Boot.OnMapStart(id, tier, fn) end
    return hook.Add("InitPostEntity", id, fn)
end

--[[
    GRM Property Core v1.0.0
    Buildings/premises above GRM Doors: ownership, rent, utilities, staff,
    temporary keys, eviction, sealing and integrations with Alarm/CCTV.
]]
if SERVER then AddCSLuaFile() end
GRM=GRM or {}; GRM.Property=GRM.Property or {}; local P=GRM.Property
P.Version="1.0.0"; P.Types={apartment="Квартира",shop="Магазин",office="Офис",warehouse="Склад",government="Государственное здание",restricted="Закрытая территория"}
P.Config=P.Config or {RentSeconds=7*86400,UtilityInterval=300,MaxProperties=256,MaxDoors=64,MaxKeys=32,UseDistance=260}
local NOPEN="GRM_Property_Open";local NACT="GRM_Property_Act";local NADMIN="GRM_Property_Admin";local NRESULT="GRM_Property_Result"
if GRM.Access and GRM.Access.Register then GRM.Access.Register("property.manage",{label="Недвижимость: управление объектами",scope="account"})end
local function ck(p)if GRM.Identity and GRM.Identity.CharacterKey then return GRM.Identity.CharacterKey(p)end return IsValid(p)and(p:SteamID64()..":char1")or tostring(p or"")end
local function trim(s,n)s=string.Trim(tostring(s or""));if GRM.Utf8Sub then return GRM.Utf8Sub(s,n or 96)end return s:sub(1,n or 96)end
local function arrHas(t,v)for _,r in ipairs(t or{})do if(istable(r)and r.key or r)==v then return true,r end end return false end
local function factionOf(p)for name,f in pairs(Factions or{})do local m=GRM.Identity and GRM.Identity.FactionMember and GRM.Identity.FactionMember(f,p);if m then return name,m end end end
function P.Normalize(r)
 r=istable(r)and r or{};r.id=trim(r.id,48);r.name=trim(r.name,96);r.type=P.Types[r.type]and r.type or"apartment";r.doors=istable(r.doors)and r.doors or{};r.ownerType=({none=1,character=1,organization=1,faction=1})[r.ownerType]and r.ownerType or"none";r.ownerKey=trim(r.ownerKey,96);r.ownerName=trim(r.ownerName,96);r.tenure=r.tenure=="rent"and"rent"or(r.tenure=="owned"and"owned"or"none");r.rentUntil=tonumber(r.rentUntil)or 0;r.purchasePrice=math.max(0,math.floor(tonumber(r.purchasePrice)or 50000));r.rentPrice=math.max(0,math.floor(tonumber(r.rentPrice)or 5000));r.utilityRate=math.max(0,math.floor(tonumber(r.utilityRate)or 500));r.utilityDebt=math.max(0,math.floor(tonumber(r.utilityDebt)or 0));r.lastUtilityAt=tonumber(r.lastUtilityAt)or os.time();r.employees=istable(r.employees)and r.employees or{};r.guests=istable(r.guests)and r.guests or{};r.tempKeys=istable(r.tempKeys)and r.tempKeys or{};r.sealed=r.sealed==true;r.sealReason=trim(r.sealReason,160);r.sealUntil=tonumber(r.sealUntil)or 0;r.alarmNetwork=trim(r.alarmNetwork,64);r.cameraIDs=istable(r.cameraIDs)and r.cameraIDs or{};r.zone=istable(r.zone)and r.zone or nil
 --[[ Вид объекта для системы бизнеса (GRM.Estate): estate — жильё,
      business — бизнес, "" — вывести из типа автоматически. Пеня за
      просрочку копится отдельным полем, чтобы её было видно в отчёте. ]]
 r.estateKind=({estate=1,business=1})[tostring(r.estateKind or"")]and r.estateKind or""
 r.estatePenalty=math.max(0,math.floor(tonumber(r.estatePenalty)or 0))
 --[[ Точка появления в жилье, заданная админом вручную (grm_housing_setspawn).
      Нужна там, где автопоиск «от двери внутрь комнаты» промахивается:
      сложная планировка, второй этаж, длинный коридор. Если поля нет,
      GRM.Housing.SpawnPoint ищет точку сам. Чистим мусор: без координат
      запись бессмысленна и мешает автопоиску. ]]
 if istable(r.housingSpawn) and tonumber(r.housingSpawn.x) then
  r.housingSpawn={x=tonumber(r.housingSpawn.x) or 0,y=tonumber(r.housingSpawn.y) or 0,z=tonumber(r.housingSpawn.z) or 0,yaw=tonumber(r.housingSpawn.yaw) or 0}
 else r.housingSpawn=nil end
 --[[ Журнал входов в жильё (фаза 3): кто заходил не своим ключом.
      Живёт в самом объекте, потому что нужен вместе с ним и должен
      исчезать вместе с ним — отдельный файл пришлось бы чистить от
      «сирот» после сноса квартир. _entrySeen НЕ сохраняем: это
      сессионная защита от повторов при дёргании дверных полотен. ]]
 r.rentWarned=r.rentWarned==true or nil
 r.entryLog=istable(r.entryLog) and r.entryLog or nil
 r._entrySeen=nil
 return r
end
function P.CanAdmin(p)return IsValid(p)and(p:IsSuperAdmin()or(GRM.Access and GRM.Access.Can and GRM.Access.Can(p,"property.manage")==true))end
function P.HasAccess(p,r)
 if not IsValid(p)then return false end;if P.CanAdmin(p)then return true end;r=P.Normalize(r);local key=ck(p);if r.ownerType=="character"and r.ownerKey==key then return true end;local fac=factionOf(p);if r.ownerType=="faction"and fac==r.ownerKey then return true end;if arrHas(r.employees,key)or arrHas(r.guests,key)then return true end;for _,v in ipairs(r.tempKeys)do if v.key==key and(tonumber(v.expires)or 0)>os.time()then return true end end;return false
end
function P.CanManage(p,r)if not IsValid(p)then return false end;if P.CanAdmin(p)then return true end;r=P.Normalize(r);return r.ownerType=="character"and r.ownerKey==ck(p)end
function P.GetByDoorID(id)return P.ByDoor and P.ByDoor[tostring(id or"")]end
function P.ResolveDoor(ent)
    if not IsValid(ent) then return nil end
    local function doorish(e)
        if not IsValid(e) then return false end
        if GRM.Doors and GRM.Doors.IsDoor and GRM.Doors.IsDoor(e) then return true end
        local c = e:GetClass()
        return c == "func_door" or c == "func_door_rotating" or c == "prop_door_rotating"
            or c == "grm_sliding_door" or c == "func_movelinear"
    end
    if doorish(ent) then return ent end
    local par = ent.GetParent and ent:GetParent()
    if doorish(par) then return par end
    return nil
end
function P.DoorID(ent)
    ent = P.ResolveDoor(ent)
    if not ent then return nil, nil end
    if GRM.Doors and GRM.Doors.GetDoorID then
        local id = GRM.Doors.GetDoorID(ent)
        if id then return id, ent end
    end
    return "ent_" .. tostring(ent:EntIndex()), ent
end
function P.GetByDoor(ent)local id=select(1,P.DoorID(ent));return id and P.GetByDoorID(id),id end
function P.IsInside(r,pos)if not(istable(r)and istable(r.zone)and pos)then return false end;local a,b=r.zone.mins,r.zone.maxs;if not(a and b)then return false end;return pos.x>=a.x and pos.y>=a.y and pos.z>=a.z and pos.x<=b.x and pos.y<=b.y and pos.z<=b.z end
function P.CameraIDs(r)return istable(r)and r.cameraIDs or{}end
function P.AlarmNetwork(r)return istable(r)and tostring(r.alarmNetwork or"")or""end
function P.Reindex()P.ByDoor={};for _,r in pairs(P.Records or{})do P.Normalize(r);for _,id in ipairs(r.doors)do P.ByDoor[tostring(id)]=r end end end

if SERVER then
 util.AddNetworkString(NOPEN);util.AddNetworkString(NACT);util.AddNetworkString(NADMIN);util.AddNetworkString(NRESULT)
 local FILE="grm_property/"..string.lower(game.GetMap()or"unknown")..".json"
 local function load()local d=GRM.Persistence and GRM.Persistence.LoadJSON and GRM.Persistence.LoadJSON(FILE,{version=1,records={}})or{records={}};P.Records={};for _,r in ipairs(d.records or{})do r=P.Normalize(r);if r.id~=""then P.Records[r.id]=r end end;P.Reindex()end
 local function save(reason)local a={};for _,r in pairs(P.Records or{})do a[#a+1]=P.Normalize(r)end;table.sort(a,function(x,y)return x.id<y.id end);local ok,why=GRM.Persistence.SaveJSON(FILE,{version=1,records=a},{version=1});if not ok then ErrorNoHalt("[GRM Property] SAVE FAIL "..tostring(why).."\n")end;return ok end
 P.Save=save;load()
 local function tell(p,msg,ok)if GRM.Notify then GRM.Notify(p,msg,ok and 90 or 255,ok and 220 or 110,ok and 120 or 100)elseif IsValid(p)then p:ChatPrint("[Недвижимость] "..msg)end end
 local function doorByID(id)for _,e in ipairs(ents.GetAll())do if IsValid(e)and GRM.Doors and GRM.Doors.IsDoor(e)and GRM.Doors.GetDoorID(e)==id then return e end end end
 local function nearProperty(p,r)
  if not IsValid(p)then return false end
  for _,id in ipairs(r.doors or{})do local e=doorByID(id);if IsValid(e)and p:GetPos():DistToSqr(e:GetPos())<=P.Config.UseDistance^2 then return true end end
  --[[ Объект, размеченный тулом бизнес-зоны, дверей может не иметь вовсе.
       Тогда «рядом» означает «внутри зоны», иначе такой объект нельзя
       было бы ни купить, ни арендовать. ]]
  if GRM.Estate and GRM.Estate.PointInZone and istable(r.zone) then
   if GRM.Estate.PointInZone(r,p:GetPos())then return true end
  end
  --[[ Покупка от двери (заказ 28.08). Человек стоит У ДВЕРИ, а она —
       на границе зоны или чуть снаружи: зону обводят по дому, дверное
       полотно нередко оказывается за коробкой. Строгая проверка
       «внутри зоны» его отсекала, и покупка через дверь срывалась.
       Тот же допуск, по которому двери притягиваются к объекту. ]]
  if GRM.EstateDeal and GRM.EstateDeal.DoorNearZone and istable(r.zone) then
   if GRM.EstateDeal.DoorNearZone(r,p:GetPos())then return true end
  end
  return false
 end
 local function lockAll(r,on)for _,id in ipairs(r.doors)do local e=doorByID(id);if IsValid(e)and GRM.Doors.LockDoor then GRM.Doors.LockDoor(e,on)end end end
 local function zoneFromDoors(ids)local mn,mx;for _,id in ipairs(ids or{})do local e=doorByID(id);if IsValid(e)and e.WorldSpaceAABB then local a,b=e:WorldSpaceAABB();if a and b then mn=mn and Vector(math.min(mn.x,a.x),math.min(mn.y,a.y),math.min(mn.z,a.z))or a;mx=mx and Vector(math.max(mx.x,b.x),math.max(mx.y,b.y),math.max(mx.z,b.z))or b end end end;if not mn then return nil end;local pad=Vector(192,192,96);mn=mn-pad;mx=mx+pad;return{mins={x=mn.x,y=mn.y,z=mn.z},maxs={x=mx.x,y=mx.y,z=mx.z}}end
 --[[ ВЛАДЕЛЕЦ НА САМОЙ ДВЕРИ (жалоба владельца 28.08: «дверь как была
      ничья, так и осталась ничья»).

      Раньше здесь гасился только признак «продаётся», а запись двери
      оставалась с owner_type = "none". Табличка над дверью читает
      именно её, поэтому дверь купленной квартиры продолжала показывать
      «Продаётся / Ничья», хотя объект уже был куплен.

      Теперь владелец объекта проставляется и на дверях. Освободили
      объект — двери снова становятся ничьими и доступными к покупке. ]]
 local function setDoorPolicy(r)
  if not(GRM.Doors and GRM.Doors.GetRecord)then return end
  local owned=tostring(r.ownerType or "none")~="none"
  local dtype,dkey,dnick="none","",""
  if owned then
   if r.ownerType=="faction" then dtype,dkey="faction",tostring(r.ownerKey or "")
   else dtype,dkey,dnick="player",tostring(r.ownerKey or ""),tostring(r.ownerName or "") end
  end
  for _,id in ipairs(r.doors)do
   local e=doorByID(id)
   if IsValid(e)then
    if GRM.Doors.SetDoorOwner then
     GRM.Doors.SetDoorOwner(e,dtype,dkey,dnick,r.name)
    else
     -- Старый модуль дверей без SetDoorOwner: хотя бы прежнее поведение.
     local rec=GRM.Doors.GetRecord(e)
     if rec then rec.ownable=false;rec.title=r.name;rec.id=id;rec._ephemeral=nil end
    end
   end
  end
  if GRM.Doors.SaveDoors then GRM.Doors.SaveDoors()end
 end
 local function public(r,sensitive)return{id=r.id,name=r.name,type=r.type,typeName=P.Types[r.type],estateKind=(GRM.Estate and GRM.Estate.KindOf and GRM.Estate.KindOf(r))or"none",estatePenalty=r.estatePenalty,doors=#r.doors,ownerType=r.ownerType,ownerKey=sensitive and r.ownerKey or"",ownerName=r.ownerName,tenure=r.tenure,rentUntil=r.rentUntil,purchasePrice=r.purchasePrice,rentPrice=r.rentPrice,utilityRate=r.utilityRate,utilityDebt=r.utilityDebt,sealed=r.sealed,sealReason=r.sealReason,sealUntil=r.sealUntil,alarmNetwork=sensitive and r.alarmNetwork or"",cameraIDs=sensitive and r.cameraIDs or{},employees=sensitive and r.employees or{},guests=sensitive and r.guests or{},tempKeys=sensitive and r.tempKeys or{},zone=r.zone}end
 local function send(p,r,admin)
  if not IsValid(p)then return end;local rows={};if r then rows[1]=public(r,P.CanManage(p,r)or P.CanAdmin(p))else for _,v in pairs(P.Records)do rows[#rows+1]=public(v,P.CanAdmin(p))end;table.sort(rows,function(a,b)return a.name<b.name end)end
  net.Start(admin and NADMIN or NOPEN);net.WriteTable(rows);net.WriteBool(r and P.CanManage(p,r)or P.CanAdmin(p));net.WriteBool(P.CanAdmin(p));net.WriteBool(P.CanAdmin(p)or(GRM.Access and GRM.Access.Can and GRM.Access.Can(p,"wanted.civil.edit")==true));net.Send(p)
 end
 P.OpenAdmin=function(p)if P.CanAdmin(p)then send(p,nil,true)end end
 local function guard(p,key,bits,max)
  if GRM.Net and GRM.Net.Guard then return GRM.Net.Guard(p,key,{rate=.35,burst=3,maxBits=max or 262144},{bits=bits})==true end;return IsValid(p)
 end
 function P.OpenForDoor(p,e)local r=P.GetByDoor(e);if not r then tell(p,"Эта дверь не входит в объект недвижимости.",false)return end;send(p,r,false)end
 local NSEL="GRM_Property_Sel"
 util.AddNetworkString(NSEL)
 local function pushSel(p)
  local ids={}
  for id in pairs(P.Selections and P.Selections[p]or{})do ids[#ids+1]=id end
  net.Start(NSEL) net.WriteUInt(#ids,8) for _,id in ipairs(ids)do net.WriteString(tostring(id)) end net.Send(p)
 end
 function P.ToggleDoorSelection(p,e)
  if not P.CanAdmin(p) then return false end
  local id,door=P.DoorID(e)
  if not id then return false end
  P.Selections=P.Selections or{};local s=P.Selections[p]or{};P.Selections[p]=s
  if s[id] then s[id]=nil;pushSel(p);return true,false,id end
  s[id]=true;pushSel(p);return true,true,id
 end
 local function selectedIDs(p)local a={};for id in pairs(P.Selections and P.Selections[p]or{})do a[#a+1]=id end;table.sort(a);return a end
 local function newID()return"prop_"..os.time().."_"..math.random(1000,9999)end
 local function clearOwnership(r)r.ownerType="none";r.ownerKey="";r.ownerName="";r.tenure="none";r.rentUntil=0;r.employees={};r.guests={};r.tempKeys={};r.utilityDebt=0;lockAll(r,false)end
 local function audit(action,p,r,d)if GRM.Audit then GRM.Audit.Write("property",action,p,{propertyID=r and r.id or""},d or{})end end
 --[[ Ядро действий вынесено из net.Receive, чтобы окно квартиры
      (sh_grm_housing_panel) могло звать ТЕ ЖЕ проверки, а не заводить
      свою копию правил доступа. Две реализации одних правил — самый
      быстрый способ получить дыру: поправят одну, забудут другую. ]]
 function P.PanelAction(p,a)
  if not IsValid(p)or not istable(a)then return end
  P._Act(p,a)
 end
 function P._Act(p,a)
  local act=tostring(a.action or"");local r=P.Records[tostring(a.id or"")]
  if act=="open_aim"then local tr=p:GetEyeTrace();if tr and IsValid(tr.Entity)then P.OpenForDoor(p,tr.Entity)end return end
  if act=="admin_open"then if P.CanAdmin(p)then send(p,nil,true)end return end
  if act=="create"then
   if not P.CanAdmin(p)then return end;local doors=selectedIDs(p);if#doors<1 then tell(p,"Сначала отметьте двери инструментом GRM Недвижимость.",false)return end;if#doors>P.Config.MaxDoors then return end
   for _,id in ipairs(doors)do if P.ByDoor[id]then tell(p,"Одна из дверей уже относится к другому объекту.",false)return end end
   local r2=P.Normalize({id=newID(),name=a.name,type=a.type,doors=doors,zone=zoneFromDoors(doors),purchasePrice=a.purchasePrice,rentPrice=a.rentPrice,utilityRate=a.utilityRate});if r2.name==""then r2.name="Объект недвижимости"end;P.Records[r2.id]=r2;P.Selections[p]={};P.Reindex();setDoorPolicy(r2);save("create");audit("create",p,r2,{doors=#doors});if GRM.Estate and GRM.Estate.Sync then if GRM.Estate.InvalidateScan then GRM.Estate.InvalidateScan()end;pcall(GRM.Estate.Sync)end;send(p,nil,true);return
  end
  if not r then return end
  if act=="buy"or act=="rent"then
   if not nearProperty(p,r)then tell(p,"Подойдите к одной из дверей объекта.",false)return end;if r.ownerType~="none"then tell(p,"Объект уже занят.",false)return end;if r.sealed then tell(p,"Объект опечатан.",false)return end
   --[[ Лимит бизнесов в одни руки (решение владельца: 2-3). Жильё
        в лимит не входит и покупается свободно. ]]
   if GRM.Estate and GRM.Estate.CanAcquire then
    local canBuy,whyBuy=GRM.Estate.CanAcquire(p,r)
    if not canBuy then tell(p,tostring(whyBuy),false)return end
   end
   local price=act=="buy"and r.purchasePrice or r.rentPrice
   if price>0 and GRM.HasMoney and not GRM.HasMoney(p,price)then tell(p,"Недостаточно наличных.",false)return end;if price>0 and GRM.TakeMoney then GRM.TakeMoney(p,price,act=="buy"and"Покупка недвижимости"or"Аренда недвижимости")end
   r.ownerType="character";r.ownerKey=ck(p);r.ownerName=p:GetNWString("GRM_RPName",p:Nick());r.tenure=act=="buy"and"owned"or"rent";r.rentUntil=act=="rent"and(os.time()+P.Config.RentSeconds)or 0;r.lastUtilityAt=os.time();lockAll(r,true);save(act);audit(act,p,r,{price=price});hook.Run("GRM_PropertyOwnerChanged",r,act,p);tell(p,act=="buy"and"Объект куплен."or"Договор аренды оформлен.",true);send(p,r,false)
  elseif act=="extend_rent"then
   --[[ ПРОДЛЕНИЕ АРЕНДЫ (фаза 4 жилья).
        Раньше продлить было НЕЧЕМ: аренда просто истекала по таймеру
        биллинга, человека молча выселяло, ключи и доступ пропадали.
        Единственным способом «продлить» было дождаться выселения и
        успеть арендовать заново раньше других — это не механика, а
        случайность.
        Платим за один период вперёд; срок наращиваем ОТ ТЕКУЩЕГО
        rentUntil, а не от «сейчас», иначе оплата досрочно сжигала бы
        остаток уже оплаченного времени. ]]
   if not P.CanManage(p,r)then return end
   if r.tenure~="rent"then tell(p,"Этот объект не арендуется.",false)return end
   local price=r.rentPrice
   if price>0 and GRM.HasMoney and not GRM.HasMoney(p,price)then tell(p,"Недостаточно наличных.",false)return end
   if price>0 and GRM.TakeMoney then GRM.TakeMoney(p,price,"Продление аренды") end
   local base=math.max(tonumber(r.rentUntil)or 0,os.time())
   r.rentUntil=base+P.Config.RentSeconds
   -- Предупреждения выдаются заново: срок теперь другой.
   r.rentWarned=nil
   save("extend-rent");audit("rent.extend",p,r,{price=price})
   tell(p,"Аренда продлена. Оплачено ещё "..math.floor(P.Config.RentSeconds/86400).." сут.",true)
   send(p,r,false)
  elseif act=="pay_utilities"then
   if not P.CanManage(p,r)then return end;local sum=r.utilityDebt;if sum<=0 then return end;if GRM.HasMoney and not GRM.HasMoney(p,sum)then tell(p,"Недостаточно наличных.",false)return end;if GRM.TakeMoney then GRM.TakeMoney(p,sum,"Коммунальные платежи")end;r.utilityDebt=0;save("utilities");audit("utilities.pay",p,r,{amount=sum});send(p,r,false)
  elseif act=="add_key"then
   if not P.CanManage(p,r)then return end;local key=trim(a.key,96);if not(GRM.Identity and GRM.Identity.IsCharacterKey and GRM.Identity.IsCharacterKey(key))then tell(p,"Нужен CharacterKey SteamID64:charN.",false)return end;local kind=({employee=1,guest=1,temp=1})[a.kind]and a.kind or"guest";local row={key=key,name=trim(a.name,64)};if kind=="temp"then row.expires=os.time()+math.Clamp(tonumber(a.minutes)or 60,5,10080)*60;r.tempKeys[#r.tempKeys+1]=row else local list=kind=="employee"and r.employees or r.guests;if not arrHas(list,key)and#list<P.Config.MaxKeys then list[#list+1]=row end end;save("key");audit("key.add",p,r,{key=key,kind=kind});send(p,r,false)
  elseif act=="remove_key"then if not P.CanManage(p,r)then return end;local key=tostring(a.key or"");for _,field in ipairs({"employees","guests","tempKeys"})do local n={};for _,v in ipairs(r[field])do if v.key~=key then n[#n+1]=v end end;r[field]=n end;save("remove-key");send(p,r,false)
  elseif act=="release"then if not P.CanManage(p,r)then return end;clearOwnership(r);save("release");audit("release",p,r,{});hook.Run("GRM_PropertyOwnerChanged",r,"release",p);send(p,r,false)
  elseif act=="admin_update"then
   if not P.CanAdmin(p)then return end;r.name=trim(a.name,96);r.type=P.Types[a.type]and a.type or r.type;r.purchasePrice=math.max(0,math.floor(tonumber(a.purchasePrice)or r.purchasePrice));r.rentPrice=math.max(0,math.floor(tonumber(a.rentPrice)or r.rentPrice));r.utilityRate=math.max(0,math.floor(tonumber(a.utilityRate)or r.utilityRate));r.alarmNetwork=trim(a.alarmNetwork,64);r.cameraIDs={};for id in tostring(a.cameraIDs or""):gmatch("[^,%s]+")do r.cameraIDs[#r.cameraIDs+1]=trim(id,64)end;r.ownerType=({none=1,character=1,organization=1,faction=1})[a.ownerType]and a.ownerType or r.ownerType;r.ownerKey=trim(a.ownerKey,96);r.ownerName=trim(a.ownerName,96)
   if a.estateKind~=nil then r.estateKind=({estate=1,business=1})[tostring(a.estateKind)]and tostring(a.estateKind)or"" end
   if GRM.Estate and GRM.Estate.InvalidateScan then GRM.Estate.InvalidateScan(r) end
   setDoorPolicy(r);save("admin-update");audit("admin.update",p,r,{});hook.Run("GRM_PropertyOwnerChanged",r,"admin_update",p);send(p,nil,true)
  elseif act=="seal"then
   if not P.CanAdmin(p)and not(GRM.Access and GRM.Access.Can(p,"wanted.civil.edit"))then return end;if not P.CanAdmin(p)and not nearProperty(p,r)then return end;r.sealed=a.on==true;r.sealReason=trim(a.reason,160);r.sealUntil=r.sealed and(os.time()+math.Clamp(tonumber(a.minutes)or 60,5,10080)*60)or 0;lockAll(r,r.sealed or r.ownerType~="none");save("seal");audit(r.sealed and"seal"or"unseal",p,r,{reason=r.sealReason});send(p,r,false)
  elseif act=="evict"then if not P.CanAdmin(p)then return end;clearOwnership(r);save("evict");audit("evict",p,r,{});hook.Run("GRM_PropertyOwnerChanged",r,"evict",p);send(p,nil,true)
  elseif act=="delete"then if not P.CanAdmin(p)then return end;clearOwnership(r);P.Records[r.id]=nil;P.Reindex();save("delete");audit("delete",p,r,{});send(p,nil,true)end
 end
 net.Receive(NACT,function(bits,p)
  if not guard(p,"property.action",bits,524288)then return end
  P._Act(p,net.ReadTable()or{})
 end)
 hook.Add("GRM_DoorPropertyAccess","GRM_Property_Key",function(p,doorID)local r=P.GetByDoorID(doorID);if r then return P.HasAccess(p,r)end end)
 hook.Add("GRM_DoorAccessOverride","GRM_Property_Seal",function(p,e)local r=P.GetByDoor(e);if not r then return nil end;local warrant=r.ownerType=="character"and GRM.Doors and GRM.Doors.HasWarrant and GRM.Doors.HasWarrant(r.ownerKey)and GRM.Access and GRM.Access.Can(p,"wanted.civil.edit");if warrant then return true,"property_warrant"end;if r.sealed and not P.CanAdmin(p)then return false,"Объект опечатан: "..(r.sealReason~=""and r.sealReason or"доступ запрещён")end;if P.HasAccess(p,r)then return true,"property_key"end;return false,"Нет ключа от объекта «"..r.name.."»."end)
 local function propertyBreach(actor,door)local r=P.GetByDoor(door);if not r then return end;if r.alarmNetwork~=""and GRM.Alarm and GRM.Alarm.Log then GRM.Alarm.Log(r.alarmNetwork,"breach","Взлом объекта: "..r.name)end;hook.Run("GRM_PropertyBreach",r,actor,door,r.cameraIDs);audit("breach",actor,r,{alarmNetwork=r.alarmNetwork,cameras=#r.cameraIDs})end
 hook.Add("GRM_OnDoorLockpicked","GRM_Property_Alarm",propertyBreach);hook.Add("GRM_DoorHacked","GRM_Property_AlarmHack",propertyBreach)
 hook.Add("PlayerSay","GRM_Property_Chat",function(p,t)local s=string.lower(string.Trim(t or""));if s=="/property"or s=="/недвижимость"then local tr=p:GetEyeTrace();if tr and IsValid(tr.Entity)then P.OpenForDoor(p,tr.Entity)end return""elseif s=="/property_admin"and P.CanAdmin(p)then send(p,nil,true)return""end end)
 hook.Add("PlayerSayTransform","GRM_Property_EasyChat",function(p,t,d)d=istable(t)and t or d;local raw=istable(t)and t[1]or t;local s=string.lower(string.Trim(raw or""));if s~="/property"and s~="/недвижимость"and s~="/property_admin"then return end;if s=="/property_admin"then if P.CanAdmin(p)then send(p,nil,true)end else local tr=p:GetEyeTrace();if tr and IsValid(tr.Entity)then P.OpenForDoor(p,tr.Entity)end end;d.SkipPlayerSay=true;d[1]=""end)
 concommand.Add("grm_property",function(p)if IsValid(p)then local tr=p:GetEyeTrace();if tr and IsValid(tr.Entity)then P.OpenForDoor(p,tr.Entity)end end end);concommand.Add("grm_property_admin",function(p)if P.CanAdmin(p)then send(p,nil,true)end end)
 --[[ ПРЕДУПРЕЖДЕНИЕ ОБ ОКОНЧАНИИ АРЕНДЫ (фаза 4).
      Раньше биллинг выселял молча: человек заходил и обнаруживал, что
      жильё чужое, вещи в шкафу недоступны, спавн пропал. Теперь за
      сутки до конца приходит предупреждение — успеть продлить. ]]
 P.RentWarnBefore=86400
 local function warnRent(r,now)
  if r.tenure~="rent"or r.ownerType~="character"then return end
  local left=(tonumber(r.rentUntil)or 0)-now
  if left<=0 or left>P.RentWarnBefore then return end
  if r.rentWarned then return end
  r.rentWarned=true
  local target=GRM.Identity and GRM.Identity.ResolveCharacter and GRM.Identity.ResolveCharacter(r.ownerKey)
  local hours=math.max(1,math.floor(left/3600))
  local msg="[Недвижимость] Аренда «"..tostring(r.name).."» заканчивается через "..hours.." ч. Продлите в /property, иначе объект освободится."
  if IsValid(target)then
   if GRM.Notify then GRM.Notify(target,msg,255,190,90) else target:PrintMessage(HUD_PRINTTALK,msg) end
  end
 end
 --[[ Биллинг — low и порционно. Раньше раз в 5 минут обходились ВСЕ
      объекты карты (до 256) в одном тике: заметный пик, особенно вместе
      с сохранением в конце. Теперь объекты обрабатываются кусками по 12,
      а запись на диск идёт один раз в конце круга. ]]
 local function billOne(r,now)
  if r.sealed and r.sealUntil>0 and r.sealUntil<=now then r.sealed=false;r.sealUntil=0 end
  warnRent(r,now)
  if r.tenure=="rent"and r.rentUntil>0 and r.rentUntil<=now then
   local who=r.ownerKey;clearOwnership(r);r.rentWarned=nil;audit("rent.expired",nil,r,{})
   local ex=GRM.Identity and GRM.Identity.ResolveCharacter and GRM.Identity.ResolveCharacter(who)
   if IsValid(ex)and GRM.Notify then GRM.Notify(ex,"[Недвижимость] Аренда «"..tostring(r.name).."» закончилась, объект освобождён.",255,120,100)end
   hook.Run("GRM_PropertyOwnerChanged",r,"rent_expired",nil)
  elseif r.ownerType~="none"and r.utilityRate>0 then
   local periods=math.floor((now-r.lastUtilityAt)/P.Config.UtilityInterval)
   if periods>0 then r.utilityDebt=math.min(100000000,r.utilityDebt+periods*r.utilityRate);r.lastUtilityAt=r.lastUtilityAt+periods*P.Config.UtilityInterval end
  end
  for i=#r.tempKeys,1,-1 do if(tonumber(r.tempKeys[i].expires)or 0)<=now then table.remove(r.tempKeys,i)end end
 end
 local function billList()
  local a={};for _,r in pairs(P.Records or{})do a[#a+1]=r end;return a
 end
 if GRM.Sched then
  GRM.Sched.EverySpread("property.billing",P.Config.UtilityInterval,billList,
   function(r)billOne(r,os.time())end,
   {prio="low",chunk=12,onDone=function()save("billing")end})
  -- Круг закончился — сохраняем один раз, а не после каждого объекта.
  GRM.Sched.Every("property.billing.save",P.Config.UtilityInterval,function()save("billing")end,{prio="low"})
 else
  timer.Create("GRM_Property_Billing",P.Config.UtilityInterval,0,function()
   local now=os.time();for _,r in pairs(P.Records)do billOne(r,now)end;save("billing")
  end)
 end
 --[[ ОБНОВЛЕНИЕ ДВЕРЕЙ ПРИ СМЕНЕ ВЛАДЕЛЬЦА.

      Корень жалобы «дверь как была ничья, так и осталась ничья»:
      setDoorPolicy звалась только при СОЗДАНИИ объекта и правке из
      админки. Ни покупка, ни аренда, ни продажа её не дёргали, поэтому
      таблички на дверях жили своей жизнью и всегда показывали «Ничья».

      Вешаемся на общий хук: он срабатывает при любом пути — окно сделки,
      /property, рынок, выселение, окончание аренды. Одна точка вместо
      правок в шести местах, и ни один новый путь не будет забыт.

      ВАЖНО ПРО ПОРЯДОК. Двери к объекту притягивает модуль сделок
      (GRM.EstateDeal.AttachDoors), и он сидит на ЭТОМ ЖЕ хуке. Порядок
      обработчиков одного хука в Lua не определён (обход pairs), поэтому
      полагаться на «он отработает раньше» нельзя: в половине случаев мы
      бы проставляли владельца ещё пустому списку дверей.

      Поэтому здесь сначала САМИ зовём привязку, и только потом ставим
      владельца. Повторный вызов безопасен: AttachDoors пропускает уже
      привязанные двери. ]]
 hook.Add("GRM_PropertyOwnerChanged","GRM_Property_DoorsSync",function(r)
  if not istable(r)then return end
  local owned=tostring(r.ownerType or "none")~="none"
  -- Двери притягиваем только к объекту с хозяином.
  if owned and GRM.EstateDeal and GRM.EstateDeal.AttachDoors then
   GRM.EstateDeal.AttachDoors(r)
  end
  setDoorPolicy(r)
  -- Занятый или опечатанный объект запирается, свободный открывается.
  lockAll(r,r.sealed==true or owned)
 end)
 grmBootStart("GRM_Property_DoorPolicy","early",function()timer.Simple(2,function()P.Reindex();for _,r in pairs(P.Records)do setDoorPolicy(r);if r.sealed or r.ownerType~="none"then lockAll(r,true)end end end)end)
 print("[GRM Property] v"..P.Version.." server loaded")
end

if CLIENT then
 surface.CreateFont("GRMPropTitle",{font="Roboto",size=24,weight=800,extended=true});surface.CreateFont("GRMPropText",{font="Roboto",size=16,weight=500,extended=true});surface.CreateFont("GRMPropSmall",{font="Roboto",size=13,weight=400,extended=true})
 local C={bg=Color(17,20,27,252),panel=Color(29,34,44),accent=Color(170,45,60),green=Color(60,175,105),red=Color(195,65,70),text=Color(235,239,245),dim=Color(150,160,175)}
 local function btn(par,text,col,fn)local b=vgui.Create("DButton",par);b:SetText(text);b:SetFont("GRMPropText");b:SetTextColor(color_white);b.Paint=function(s,w,h)draw.RoundedBox(6,0,0,w,h,s:IsHovered()and Color(190,65,80)or(col or C.accent))end;b.DoClick=fn or function()end;return b end
 local function send(a)net.Start(NACT);net.WriteTable(a);net.SendToServer()end
 local function open(rows,canManage,isAdmin,canEnforce,admin)
  if IsValid(P._frame)then P._frame:Remove()end;local f=vgui.Create("DFrame");P._frame=f;f:SetSize(math.min(1250,ScrW()-50),math.min(820,ScrH()-50));f:Center();f:MakePopup();f:SetTitle("");f.Paint=function(_,w,h)draw.RoundedBox(10,0,0,w,h,C.bg);draw.SimpleText(admin and"УПРАВЛЕНИЕ НЕДВИЖИМОСТЬЮ"or"ОБЪЕКТ НЕДВИЖИМОСТИ","GRMPropTitle",22,22,C.text)end;if GRM.UI then GRM.UI.Track(admin and"property.admin"or"property.view",f)end
  local list=vgui.Create("DListView",f);list:SetPos(18,62);list:SetSize(380,f:GetTall()-80);list:AddColumn("Название");list:AddColumn("Тип");list:AddColumn("Владелец");for _,r in ipairs(rows)do local l=list:AddLine(r.name,r.typeName,r.ownerName~=""and r.ownerName or"Свободно");l.Row=r end
  local p=vgui.Create("DScrollPanel",f);p:SetPos(414,62);p:SetSize(f:GetWide()-432,f:GetTall()-80)
  local function render(r)p:Clear();if not r then return end;local y=0;local function lab(t,font,col)local l=vgui.Create("DLabel",p);l:SetPos(4,y);l:SetSize(p:GetWide()-20,font=="GRMPropTitle"and 34 or 24);l:SetFont(font or"GRMPropText");l:SetTextColor(col or C.text);l:SetText(t);y=y+l:GetTall()+5;return l end;local function field(v,ph)local e=vgui.Create("DTextEntry",p);e:SetPos(4,y);e:SetSize(p:GetWide()-20,32);e:SetFont("GRMPropText");e:SetText(tostring(v or""));e:SetPlaceholderText(ph or"");y=y+38;return e end
   lab(r.name,"GRMPropTitle");lab(r.typeName.." • дверей: "..r.doors..(r.sealed and" • ОПЕЧАТАНО"or""),"GRMPropText",r.sealed and C.red or C.dim);lab("Владелец: "..(r.ownerName~=""and r.ownerName or"нет").." • статус: "..r.tenure);lab("Покупка: "..r.purchasePrice.." • аренда: "..r.rentPrice.." • коммунальные: "..r.utilityDebt.." (тариф "..r.utilityRate..")")
   if r.ownerType=="none"and not r.sealed then local b=btn(p,"КУПИТЬ",C.green,function()send({action="buy",id=r.id})end);b:SetPos(4,y);b:SetSize(220,36);local q=btn(p,"АРЕНДОВАТЬ",C.accent,function()send({action="rent",id=r.id})end);q:SetPos(234,y);q:SetSize(220,36);y=y+44 end
   if canManage and r.ownerType~="none"then local pay=btn(p,"ОПЛАТИТЬ КОММУНАЛЬНЫЕ",C.green,function()send({action="pay_utilities",id=r.id})end);pay:SetPos(4,y);pay:SetSize(330,36);local release=btn(p,"ОСВОБОДИТЬ",C.red,function()Derma_Query("Освободить объект? Ключи будут удалены.","Недвижимость","Да",function()send({action="release",id=r.id})end,"Нет")end);release:SetPos(344,y);release:SetSize(180,36);y=y+44;lab("Ключи сотрудников / гостей / временные","GRMPropText");local key=field("","CharacterKey SteamID64:charN");local nm=field("","Имя");local kind=vgui.Create("DComboBox",p);kind:SetPos(4,y);kind:SetSize(220,32);kind:AddChoice("Сотрудник","employee",true);kind:AddChoice("Гость","guest");kind:AddChoice("Временный ключ","temp");y=y+38;local add=btn(p,"ДОБАВИТЬ КЛЮЧ",C.accent,function()local _,k=kind:GetSelected();send({action="add_key",id=r.id,key=key:GetValue(),name=nm:GetValue(),kind=k,minutes=60})end);add:SetPos(4,y);add:SetSize(260,36);y=y+44;local function keyRow(prefix,v)local row=vgui.Create("DPanel",p);row:SetPos(4,y);row:SetSize(p:GetWide()-20,30);row.Paint=function(_,w,h)draw.RoundedBox(4,0,0,w,h,C.panel)end;local l=vgui.Create("DLabel",row);l:SetPos(8,3);l:SetSize(row:GetWide()-115,24);l:SetFont("GRMPropSmall");l:SetTextColor(C.dim);l:SetText(prefix..": "..(v.name~=""and v.name or v.key));local del=btn(row,"Убрать",C.red,function()send({action="remove_key",id=r.id,key=v.key})end);del:SetPos(row:GetWide()-100,3);del:SetSize(94,24);y=y+34 end;for _,v in ipairs(r.employees or{})do keyRow("Сотрудник",v)end;for _,v in ipairs(r.guests or{})do keyRow("Гость",v)end;for _,v in ipairs(r.tempKeys or{})do keyRow("Временный",v)end end
   if canEnforce and not admin then lab("Правоприменение","GRMPropTitle");local reason=field(r.sealReason,"Основание опечатывания");local enforce=btn(p,r.sealed and"СНЯТЬ ПЕЧАТЬ"or"ОПЕЧАТАТЬ НА 60 МИН",C.red,function()send({action="seal",id=r.id,on=not r.sealed,reason=reason:GetValue(),minutes=60})end);enforce:SetPos(4,y);enforce:SetSize(310,36);y=y+44 end
   if admin then lab("Администрирование","GRMPropTitle");local name=field(r.name,"Название");local typ=field(r.type,"Тип ID");local buy=field(r.purchasePrice,"Цена покупки");local rent=field(r.rentPrice,"Аренда");local util=field(r.utilityRate,"Тариф");local alarm=field(r.alarmNetwork,"Alarm network");local cams=field(table.concat(r.cameraIDs or{},","),"CCTV DeviceID через запятую");local ownerType=field(r.ownerType,"none/character/organization/faction");local ownerKey=field(r.ownerKey,"CharacterKey/фракция/организация");local ownerName=field(r.ownerName,"Название владельца");local sv=btn(p,"СОХРАНИТЬ",C.green,function()send({action="admin_update",id=r.id,name=name:GetValue(),type=typ:GetValue(),purchasePrice=buy:GetValue(),rentPrice=rent:GetValue(),utilityRate=util:GetValue(),alarmNetwork=alarm:GetValue(),cameraIDs=cams:GetValue(),ownerType=ownerType:GetValue(),ownerKey=ownerKey:GetValue(),ownerName=ownerName:GetValue()})end);sv:SetPos(4,y);sv:SetSize(260,36);local seal=btn(p,r.sealed and"СНЯТЬ ПЕЧАТЬ"or"ОПЕЧАТАТЬ",C.red,function()send({action="seal",id=r.id,on=not r.sealed,reason="Решение администрации",minutes=60})end);seal:SetPos(274,y);seal:SetSize(220,36);y=y+44;local evict=btn(p,"ВЫСЕЛИТЬ",C.red,function()send({action="evict",id=r.id})end);evict:SetPos(4,y);evict:SetSize(220,36);local del=btn(p,"УДАЛИТЬ ОБЪЕКТ",C.red,function()Derma_Query("Удалить объект недвижимости?","Недвижимость","Удалить",function()send({action="delete",id=r.id})end,"Отмена")end);del:SetPos(234,y);del:SetSize(260,36);y=y+44 end
  end
  list.OnRowSelected=function(_,_,l)render(l.Row)end;if rows[1]then list:SelectFirstItem();render(rows[1])end
  if admin then local create=btn(f,"СОЗДАТЬ ИЗ ОТМЕЧЕННЫХ ДВЕРЕЙ",C.green,function()Derma_StringRequest("Новый объект","Название","Объект",function(n)send({action="create",name=n,type="apartment",purchasePrice=50000,rentPrice=5000,utilityRate=500})end)end);create:SetPos(18,f:GetTall()-54);create:SetSize(360,34)end
 end
 net.Receive(NOPEN,function()open(net.ReadTable()or{},net.ReadBool(),net.ReadBool(),net.ReadBool(),false)end);net.Receive(NADMIN,function()open(net.ReadTable()or{},net.ReadBool(),net.ReadBool(),net.ReadBool(),true)end);net.Receive(NRESULT,function()notification.AddLegacy(net.ReadString(),NOTIFY_GENERIC,4)end)
 P._sel={}
 net.Receive("GRM_Property_Sel",function()
  local n=net.ReadUInt(8);P._sel={}
  for i=1,n do P._sel[net.ReadString()]=true end
 end)
-- контуры выделения (общие, создаются раз при загрузке; §6.1.8)
local HALO_HOVER = Color(80, 200, 255)
local HALO_SEL = Color(70, 220, 120)
 hook.Add("PreDrawHalos","GRM_Property_Halos",function()
  local lp=LocalPlayer();if not IsValid(lp)then return end
  local wep=lp:GetActiveWeapon()
  if not(IsValid(wep)and wep:GetClass()=="gmod_tool")then return end
  local tool=lp.GetTool and lp:GetTool()
  if not(istable(tool)and tool.Mode=="grm_property")then return end
  local hover,sel={},{}
  local tr=lp:GetEyeTrace()
  local look=P.ResolveDoor(tr and tr.Entity)
  if IsValid(look)then hover[1]=look end
  for _,cls in ipairs({"func_door","func_door_rotating","prop_door_rotating","grm_sliding_door","func_movelinear"})do
   for _,e in ipairs(ents.FindByClass(cls))do
    local id=select(1,P.DoorID(e))
    if id and P._sel[id]then sel[#sel+1]=e end
   end
  end
  if #hover>0 then halo.Add(hover,HALO_HOVER,2,2,1,true,true) end
  if #sel>0 then halo.Add(sel,HALO_SEL,3,3,2,true,true) end
 end)
end
