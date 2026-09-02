-- Boot-шим: старт подсистемы идёт через планировщик GRM.Boot (приоритеты и
-- бюджет на тик). Если планировщик почему-то не загружен, работаем по-старому.
local function grmBootStart(id, tier, fn)
    if GRM and GRM.Boot and GRM.Boot.OnMapStart then return GRM.Boot.OnMapStart(id, tier, fn) end
    return hook.Add("InitPostEntity", id, fn)
end

-- GRM Vehicle Dealer & Garage v3.0.0
if SERVER then AddCSLuaFile() end
GRM=GRM or{};GRM.VehicleDealer=GRM.VehicleDealer or{};local VD=GRM.VehicleDealer
VD.Version="3.8.0";VD.DealerFile="grm_vehicle_dealers/";VD.GarageFile="grm_vehicle_garages.json";VD.MaxActive=3;VD.UseDistance=180;VD.DefaultLift=30
VD.Dealers=VD.Dealers or{};VD.Garages=VD.Garages or{};VD.Active=VD.Active or{}
VD.VehicleKinds={personal="Личный купленный",government="Государственный служебный",public="Общественный транспорт",job_taxi="Работа: такси",job_garbage="Работа: мусоровоз",job_courier="Работа: доставка"}
-- Список организаций для выпадающих списков админки дилера (v3.3.0):
-- фракции больше не вводятся руками — берём реальный реестр.
function VD.FactionList()
    local src = (istable(Factions) and Factions) or (istable(FactionsData) and FactionsData) or {}
    local out = {}
    for name, f in pairs(src) do
        if isstring(name) and name ~= "" then
            local disp = (GRM.Factions and GRM.Factions.DisplayName and GRM.Factions.DisplayName(name)) or name
            out[#out + 1] = { key = name, name = tostring(disp) }
        end
    end
    table.sort(out, function(a, b) return string.lower(a.name) < string.lower(b.name) end)
    return out
end

-- Базовые категории каталога. Админ может дописать свою — она подхватится
-- в список из уже сохранённого ассортимента.
VD.BaseCategories = {
    "Легковые", "Внедорожники", "Спорт", "Грузовые", "Автобусы",
    "Мотоциклы", "Служебные", "Спецтехника", "Военные", "Прочее",
}

function VD.CategoryList(entries)
    local seen, out = {}, {}
    for _, c in ipairs(VD.BaseCategories) do
        if not seen[c] then seen[c] = true out[#out + 1] = c end
    end
    for _, e in ipairs(entries or {}) do
        local c = tostring(e.category or "")
        if c ~= "" and not seen[c] then seen[c] = true out[#out + 1] = c end
    end
    return out
end

--[[ РЕЖИМ ВЫДАЧИ У ДИЛЕРА (v3.7.0, заказ владельца 19.08):
     «в настройках дилера выставлять — показывать кнопку выдачи или решать,
     выдавать через дилера или через гараж».
       dealer — как раньше: купил и машина стоит на площадке;
       garage — покупка уезжает прямо в гараж, у дилера её не выдают;
       both   — есть обе кнопки: «купить и выдать» и «купить в гараж».
     Отдельно VD_ShowRetrieve — показывать ли у дилера кнопку «ВЫДАТЬ»
     (доставать машину из гаража, стоя у дилера). ]]
VD.DeliveryModes = {
    dealer = "Выдавать у дилера",
    garage = "Отправлять в гараж",
    both   = "На выбор игрока",
}
function VD.DeliveryMode(dealer)
    local mode = IsValid(dealer) and tostring(dealer.VD_Delivery or "") or ""
    return VD.DeliveryModes[mode] and mode or "dealer"
end
function VD.ShowRetrieve(dealer)
    if not IsValid(dealer) then return true end
    return dealer.VD_ShowRetrieve ~= false
end

--[[ ВЫКУП ГОСУДАРСТВОМ (v3.8.0, заказ владельца 19.08):
     «нужна у дилера кнопка продать государству, продажа идёт ниже
     купленного: машина стоила 1 500 200 — продана будет по цене чуть ниже,
     скажем 1 400 300».
     Ставка задаётся конваром в процентах от цены покупки; деньги идут игроку
     и списываются из государственного бюджета, если модуль экономики
     подключён (иначе просто выплата, как раньше делал возврат 50%). ]]
VD.SlotDebugCvar = VD.SlotDebugCvar or CreateConVar("grm_vd_slot_debug", "0",
    bit.bor(FCVAR_ARCHIVE), "Печатать в консоль, почему машина не встала на место гаража")

VD.StateBuybackCvar = VD.StateBuybackCvar or CreateConVar("grm_vd_state_buyback", "93",
    bit.bor(FCVAR_ARCHIVE), "Процент от цены покупки, который государство платит за выкуп транспорта")

function VD.StateBuybackRate() return math.Clamp(VD.StateBuybackCvar:GetInt(), 1, 100) end

--- Сколько государство заплатит за конкретную запись гаража.
function VD.StateBuybackPrice(record)
    if not istable(record) then return 0 end
    local price = math.max(0, math.floor(tonumber(record.price) or 0))
    if price <= 0 then return 0 end
    return math.max(1, math.floor(price * VD.StateBuybackRate() / 100))
end

function VD.EntryKind(entry)local kind=tostring(entry and entry.ownershipType or"");if VD.VehicleKinds[kind]then return kind end;if entry and entry.service then return entry.faction and entry.faction~=""and"government"or"public"end;return"personal"end
local function jsonT(s)local ok,t=pcall(util.JSONToTable,s or"",false,true);return ok and istable(t)and t or nil end
local function ensureDir()if SERVER and not file.IsDir("grm_vehicle_dealers","DATA")then file.CreateDir("grm_vehicle_dealers")end end
local function mapFile()ensureDir();return VD.DealerFile..string.lower(game.GetMap()or"unknown")..".json"end
local function write(path,data)local ok,s=pcall(util.TableToJSON,data,true);if not ok or not isstring(s)then return false end;file.Write(path,s);return file.Read(path,"DATA")==s end
local function key(ply)if GRM.Identity and GRM.Identity.CharacterKey then return GRM.Identity.CharacterKey(ply)end;return tostring(ply:SteamID64())..":char1"end
local function vd(v)return{x=v.x,y=v.y,z=v.z}end;local function ad(a)return{p=a.p,y=a.y,r=a.r}end
local function vec(t)return Vector(tonumber(t.x)or 0,tonumber(t.y)or 0,tonumber(t.z)or 0)end;local function ang(t)return Angle(tonumber(t.p)or 0,tonumber(t.y)or 0,tonumber(t.r)or 0)end
-- Имена с клеймом сторонних паков техники (заказ владельца 02.09.2026 — таких
-- надписей не должно быть ни в одном модуле) отсекает общий фильтр VK.CleanName.
-- Каталог фильтруется здесь, на источнике; сохранённые записи — в точках выдачи
-- клиенту (nameV).
local function nameV(n,fb)
 local function pass(s)
  s=tostring(s or"");if s==""then return nil end
  if VK and isfunction(VK.CleanName)then return VK.CleanName(s)end
  return s
 end
 return pass(n)or pass(fb)or"Транспорт"
end
function VD.VehicleInfo(class)
 class=tostring(class or"");local v=(list.Get("Vehicles")or{})[class];if v then return{name=nameV(v.Name,class),model=v.Model or"models/buggy.mdl",system="source",data=v}end
 local s=(list.Get("simfphys_vehicles")or{})[class];if s then return{name=nameV(s.Name or s.PrintName,class),model=s.Model or"models/buggy.mdl",system="simfphys",data=s}end
 local l=(list.Get("LVS_Vehicles")or{})[class];if l then return{name=nameV(l.Name or l.PrintName,class),model=l.Model or"models/buggy.mdl",system="lvs",data=l}end
 return{name=nameV(class),model="models/buggy.mdl",system="unknown",data={}}
end
function VD.AllVehicleClasses()local out,seen={},{};for _,registry in ipairs({list.Get("Vehicles")or{},list.Get("simfphys_vehicles")or{},list.Get("LVS_Vehicles")or{}})do for class in pairs(registry)do if not seen[class]then seen[class]=true;local i=VD.VehicleInfo(class);out[#out+1]={class=class,name=i.name,model=i.model,system=i.system}end end end;table.sort(out,function(a,b)return a.name<b.name end);return out end
local function playerFaction(ply)if FactionsAPI and FactionsAPI.GetFactionOf then return FactionsAPI.GetFactionOf(ply)end;for name,f in pairs(Factions or{})do if GRM.Identity and GRM.Identity.FactionMember and GRM.Identity.FactionMember(f,ply)then return name end end end
function VD.CanUseEntry(ply,entry)
 local kind=VD.EntryKind(entry);if ply:IsSuperAdmin()then return true end
 if kind=="government"then return entry.faction and entry.faction~=""and playerFaction(ply)==entry.faction end
 if kind:find("job_",1,true)==1 then local job=GRM.Jobs and GRM.Jobs.GetActiveJob and GRM.Jobs.GetActiveJob(ply);return istable(job)and("job_"..tostring(job.tplId or job.jtype))==kind end
 if entry.faction and entry.faction~=""then return playerFaction(ply)==entry.faction end
 return true
end
function VD.ClassifyVehicle(ent)return IsValid(ent)and tostring(ent:GetNWString("GRM_VehicleKind",ent.GRMVehicleKind or"personal"))or"unknown"end
function VD.DealerRecord(ent)return{id=ent:GetDealerID(),name=ent:GetDealerName(),model=ent:GetDealerModel(),delivery=VD.DeliveryMode(ent),showRetrieve=VD.ShowRetrieve(ent),pos=vd(ent:GetPos()),ang=ad(ent:GetAngles()),spawnPos=vd(ent:GetSpawnPos()),spawnAng=ad(ent:GetSpawnAngle()),hasSpawn=ent:GetHasCustomSpawn(),hasSpawnZone=ent:GetHasSpawnZone(),spawnZoneMin=vd(ent:GetSpawnZoneMin()),spawnZoneMax=vd(ent:GetSpawnZoneMax()),lift=tonumber(ent.VD_Lift)or VD.DefaultLift,vehicles=table.Copy(ent.VD_Vehicles or{})}end
if SERVER then
 for _,n in ipairs({"GRM_VD_Open","GRM_VD_Action","GRM_VD_Result","GRM_VD_AdminOpen","GRM_VD_AdminSave","GRM_VD_ZoneRequest","GRM_VD_ZoneData","VD_RequestVehicleList","VD_VehicleList","VD_AdminSpawnVehicle"})do util.AddNetworkString(n)end
 local function loadDealers()local d=file.Exists(mapFile(),"DATA")and jsonT(file.Read(mapFile(),"DATA"))or{};local src=d and(d.dealers or d)or{};local o={}for _,r in pairs(src)do if istable(r)and r.id and r.pos then o[#o+1]=r end end;return o end
 local function saveDealers(records)
  local okWrite=write(mapFile(),{version=3,map=game.GetMap(),dealers=records})
  -- Ассортимент поменялся — предзагрузка моделей подхватит новые классы
  -- (порционно, через GRM.Perf; см. sh_grm_vehicle_precache.lua).
  hook.Run("GRM_VehicleDealerSaved",records)
  return okWrite
 end
 local function loadGarage(markStored)VD.Garages=file.Exists(VD.GarageFile,"DATA")and(jsonT(file.Read(VD.GarageFile,"DATA"))or{})or{};if markStored then for _,garageRows in pairs(VD.Garages)do for _,record in pairs(garageRows)do record.stored=true end end end end;local function saveGarage()return write(VD.GarageFile,VD.Garages)end;loadGarage(true);saveGarage()
 local function makeID(prefix)return prefix.."_"..util.CRC(table.concat({game.GetMap(),SysTime(),math.random()},":"))end
 function VD.SaveDealer(ent)if not IsValid(ent)or ent:GetClass()~="sent_vehicle_dealer"then return false,"Дилер не найден"end;if ent:GetDealerID()==""then ent:SetDealerID(makeID("dealer"))end;local records=loadDealers();local rec=VD.DealerRecord(ent);local found=false;for i,r in ipairs(records)do if r.id==rec.id then records[i]=rec;found=true break end end;if not found then records[#records+1]=rec end;VD.Dealers[rec.id]=ent;return saveDealers(records),rec.id end
 function VD.DeleteDealer(ent)local records=loadDealers();for i=#records,1,-1 do if records[i].id==ent:GetDealerID()then table.remove(records,i)end end;VD.Dealers[ent:GetDealerID()]=nil;return saveDealers(records)end
 local function apply(ent,r)
  ent:SetDealerID(r.id);ent:SetDealerName(r.name or"Дилер транспорта")
  local model=util.IsValidModel(r.model or"")and r.model or"models/Humans/Group01/Male_02.mdl"
  -- Модель ставим ТОЛЬКО через ApplyDealerModel: он же возвращает idle,
  -- иначе после каждой загрузки карты дилер стоял в Т-позе.
  if ent.ApplyDealerModel then ent:ApplyDealerModel(model)else ent:SetDealerModel(model);ent:SetModel(model)end
  local legacyPoint=vec(r.spawnPos or r.pos);local hasPad=r.hasSpawnZone==true
  local padMin=vec(r.spawnZoneMin or r.spawnPos or r.pos);local padMax=vec(r.spawnZoneMax or r.spawnPos or r.pos)
  -- v3.1.2: точка выдачи (hasSpawn без зоны) больше НЕ превращается в площадку —
  -- остаётся точкой с направлением и высотой. Зоны (hasSpawnZone) сохранены для совместимости.
  if hasPad then ent:SetSpawnZoneMin(padMin);ent:SetSpawnZoneMax(padMax)end
  ent:SetHasSpawnZone(hasPad);ent.VD_Lift=tonumber(r.lift)or VD.DefaultLift
  ent:SetSpawnPos(hasPad and((padMin+padMax)*.5)or legacyPoint);ent:SetHasCustomSpawn(r.hasSpawn==true or hasPad);ent:SetSpawnAngle(ang(r.spawnAng or r.ang))
  ent.VD_Delivery=VD.DeliveryModes[tostring(r.delivery or"")]and tostring(r.delivery)or"dealer"
  ent.VD_ShowRetrieve=r.showRetrieve~=false
  ent.VD_Vehicles=table.Copy(r.vehicles or{})
  -- Легаси-записи могли сохраниться с клеймом пака в имени (заказ 02.09) —
  -- срезаем на загрузке; источник новых имён (VD.VehicleInfo) уже фильтрован.
  for _,v in ipairs(ent.VD_Vehicles)do if isstring(v.name)then v.name=nameV(v.name,v.class)end end
  VD.Dealers[r.id]=ent
 end
 function VD.LoadDealers()
  local made,healed,migrated=0,0,0
  for _,r in ipairs(loadDealers())do
   local ent=VD.Dealers[r.id]
   if not IsValid(ent)then for _,e in ipairs(ents.FindByClass("sent_vehicle_dealer"))do if e:GetDealerID()==r.id or e:GetPos():DistToSqr(vec(r.pos))<64 then ent=e break end end end
   if not IsValid(ent)then ent=ents.Create("sent_vehicle_dealer");ent:SetPos(vec(r.pos));ent:SetAngles(ang(r.ang));ent:SetDealerID(r.id);ent:Spawn();ent:Activate();made=made+1 else healed=healed+1 end
   if r.hasSpawn==true and r.hasSpawnZone~=true then migrated=migrated+1 end
   apply(ent,r)
  end
  if migrated>0 then VD.SaveAllDealers();print("[GRM VehicleDealer] legacy delivery points migrated to pads: "..migrated)end
  return true,("создано %d, обновлено %d, мигрировано точек %d"):format(made,healed,migrated)
 end
 function VD.SaveAllDealers()local records={}for _,e in ipairs(ents.FindByClass("sent_vehicle_dealer"))do if IsValid(e)then if e:GetDealerID()==""then e:SetDealerID(makeID("dealer"))end;records[#records+1]=VD.DealerRecord(e)end end;return saveDealers(records),"сохранено дилеров: "..#records end
 function VD.FindDeliveryPosition(dealer)
  if not IsValid(dealer)then return nil,angle_zero,"Дилер не найден"end
  local a=dealer:GetHasSpawnZone()and dealer:GetSpawnAngle()or Angle(0,dealer:GetAngles().y+90,0)
  if dealer:GetHasSpawnZone()then
   local mn,mx=dealer:GetSpawnZoneMin(),dealer:GetSpawnZoneMax();local center=(mn+mx)*.5
   local marginX=math.min(70,math.max(0,(mx.x-mn.x)*.25));local marginY=math.min(100,math.max(0,(mx.y-mn.y)*.25))
   local xs={center.x,mn.x+marginX,mx.x-marginX};local ys={center.y,mn.y+marginY,mx.y-marginY};local candidates={center}
   for _,x in ipairs(xs)do for _,y in ipairs(ys)do if x~=center.x or y~=center.y then candidates[#candidates+1]=Vector(x,y,center.z)end end end
   for _,candidate in ipairs(candidates)do
    local lift=tonumber(dealer.VD_Lift)or VD.DefaultLift
    local ground=util.TraceLine({start=Vector(candidate.x,candidate.y,mx.z+240),endpos=Vector(candidate.x,candidate.y,mn.z-340),filter=dealer,mask=MASK_SOLID})
    if ground.Hit and not ground.StartSolid then
     local p=ground.HitPos+Vector(0,0,lift)
     local blocked=util.TraceHull({start=p+Vector(0,0,48),endpos=p+Vector(0,0,48),mins=Vector(-60,-105,-42),maxs=Vector(60,105,58),filter=dealer,mask=MASK_SOLID})
     if not blocked.Hit and not blocked.StartSolid then return p,a end
    end
   end
   return nil,a,"Площадка выдачи занята или не имеет безопасной поверхности"
  end
  if dealer:GetHasCustomSpawn()then
   local lift=tonumber(dealer.VD_Lift)or VD.DefaultLift
   local base=dealer:GetSpawnPos()
   local ground=util.TraceLine({start=base+Vector(0,0,180),endpos=base-Vector(0,0,300),filter=dealer,mask=MASK_SOLID})
   local p=base
   if ground.Hit and not ground.StartSolid then p=ground.HitPos+Vector(0,0,lift)else p=p+Vector(0,0,lift)end
   local blocked=util.TraceHull({start=p+Vector(0,0,48),endpos=p+Vector(0,0,48),mins=Vector(-60,-105,-42),maxs=Vector(60,105,58),filter=dealer,mask=MASK_SOLID})
   if blocked.Hit or blocked.StartSolid then
    for i=1,3 do
     local cand=p+Vector(0,0,45*i)
     local b2=util.TraceHull({start=cand+Vector(0,0,48),endpos=cand+Vector(0,0,48),mins=Vector(-60,-105,-42),maxs=Vector(60,105,58),filter=dealer,mask=MASK_SOLID})
     if not b2.Hit and not b2.StartSolid then return cand,dealer:GetSpawnAngle()end
    end
    return nil,dealer:GetSpawnAngle(),"Точка выдачи занята"
   end
   return p,dealer:GetSpawnAngle()
  end
  return dealer:GetPos()+dealer:GetForward()*220,a,"У дилера не задана точка выдачи — используется временное место перед NPC"
 end
 function VD.FindSpawnPoint(dealer)return VD.FindDeliveryPosition(dealer)end -- compatibility API
 local function spawnPos(dealer)return VD.FindDeliveryPosition(dealer)end
 function VD.SetSpawnZone(dealer,first,second,lift)
  if not IsValid(dealer)then return false,"Дилер не найден"end
  dealer.VD_Lift=math.Clamp(math.floor(tonumber(lift)or VD.DefaultLift),0,100)
  local mn=Vector(math.min(first.x,second.x),math.min(first.y,second.y),math.min(first.z,second.z));local mx=Vector(math.max(first.x,second.x),math.max(first.y,second.y),math.max(first.z,second.z))
  if mx.x-mn.x<220 or mx.y-mn.y<260 then return false,"Площадка слишком мала: минимум 220×260"end
  if mx.z-mn.z<24 then local centerZ=(mn.z+mx.z)*.5;mn.z=centerZ-12;mx.z=centerZ+12 end
  dealer:SetSpawnZoneMin(mn);dealer:SetSpawnZoneMax(mx);dealer:SetHasSpawnZone(true);dealer:SetSpawnPos((mn+mx)*.5);dealer:SetHasCustomSpawn(true)
  return VD.SaveDealer(dealer)
 end
 function VD.ClearSpawnZone(dealer)
  if not IsValid(dealer)then return false end
  dealer:SetHasSpawnZone(false);dealer:SetHasCustomSpawn(false);dealer:SetSpawnPos(dealer:GetPos()+dealer:GetForward()*220)
  return VD.SaveDealer(dealer)
 end
 -- v3.1.2: единая ТОЧКА выдачи (позиция + направление + высота)
 function VD.SetSpawnPoint(dealer,pos,ang,lift)
  if not IsValid(dealer)then return false,"Дилер не найден"end
  dealer:SetSpawnPos(pos);dealer:SetSpawnAngle(ang or Angle(0,dealer:GetAngles().y+90,0));dealer:SetHasCustomSpawn(true);dealer:SetHasSpawnZone(false);dealer.VD_Lift=math.Clamp(math.floor(tonumber(lift)or VD.DefaultLift),0,100)
  return VD.SaveDealer(dealer)
 end
 function VD.ClearSpawnPoint(dealer)
  if not IsValid(dealer)then return false end
  dealer:SetHasSpawnZone(false);dealer:SetHasCustomSpawn(false);dealer:SetSpawnPos(dealer:GetPos()+dealer:GetForward()*220)
  return VD.SaveDealer(dealer)
 end
 --[[ v3.5.0: спавн умеет работать и БЕЗ дилера — по готовому месту
      {pos=Vector, ang=Angle, lift=число}. Это нужно гаражам (GRM.Garage):
      машина выдаётся на место гаража, а вся возня со спавн-системами
      (simfphys / LVS / Source / SENT) остаётся в одном месте. ]]
 function VD.Spawn(class,dealer,ply,place)
  class=tostring(class or"");local info=VD.VehicleInfo(class);local ent;local errors={}
  local p,a,lift
  if istable(place)and place.pos then
   p=place.pos;a=place.ang or Angle(0,0,0);lift=math.Clamp(math.floor(tonumber(place.lift)or VD.DefaultLift),0,100)
  else
   local zoneError;p,a,zoneError=spawnPos(dealer);if not p then return nil,info,{zoneError or"Нет свободной точки в зоне"}end
   lift=tonumber(IsValid(dealer)and dealer.VD_Lift or nil)or VD.DefaultLift
  end
  local ground=util.TraceLine({start=p+Vector(0,0,180),endpos=p-Vector(0,0,300),filter={dealer,ply}});if ground.Hit and not ground.StartSolid then p=ground.HitPos+Vector(0,0,lift)else p=p+Vector(0,0,lift)end
  local function attempt(label,fn)local ok,res=pcall(fn);if ok and IsValid(res)then ent=res;return true end;errors[#errors+1]=label..": "..tostring(res);return false end
  local simList=list.Get("simfphys_vehicles")or{};local simData=simList[class]
  if simData then
   local spawnName=tostring(simData.SpawnList or class)
   -- SpawnVehicleSimple — штатный API simfphys для серверного создания
   -- машины по spawn-name. Некоторые armed-паки переопределяют
   -- SpawnVehicle и возвращают «живую» base-entity без корпуса; из-за
   -- этого автопарк отмечал технику выданной, а на стоянке было пусто.
   if simfphys and isfunction(simfphys.SpawnVehicleSimple)then attempt("simfphys.SpawnVehicleSimple",function()return simfphys.SpawnVehicleSimple(spawnName,p,a)end)end
   if not IsValid(ent)and simfphys and isfunction(simfphys.SpawnVehicle)then attempt("simfphys.SpawnVehicle",function()return simfphys.SpawnVehicle(ply,p,a,spawnName)end)end
  end
  if not IsValid(ent)then
   for registryClass,data in pairs(simList)do if registryClass==class or tostring(data.SpawnList or"")==class then local spawnName=tostring(data.SpawnList or registryClass);if simfphys and isfunction(simfphys.SpawnVehicle)then attempt("simfphys fallback",function()return simfphys.SpawnVehicle(ply,p,a,spawnName)end)end;if IsValid(ent)then break end end end
  end
  local lvsData=(list.Get("LVS_Vehicles")or{})[class]
  if not IsValid(ent)and lvsData then
   if isfunction(lvsData.SpawnFunction)then attempt("LVS SpawnFunction",function()return lvsData.SpawnFunction(ply,{HitPos=p,HitNormal=Vector(0,0,1)},class)end)end
   if not IsValid(ent)then attempt("LVS entity",function()local e=ents.Create(tostring(lvsData.Class or class));if not IsValid(e)then return end;e:SetPos(p);e:SetAngles(a);if util.IsValidModel(lvsData.Model or"")then e:SetModel(lvsData.Model)end;for k,v in pairs(lvsData.KeyValues or{})do e:SetKeyValue(k,tostring(v))end;e:Spawn();e:Activate();return e end)end
  end
  local source=(list.Get("Vehicles")or{})[class]
  if not IsValid(ent)and source then attempt("Source vehicle",function()local e=ents.Create(tostring(source.Class or"prop_vehicle_jeep"));if not IsValid(e)then return end;e:SetModel(source.Model or"models/buggy.mdl");local kv=source.KeyValues or{};for k,v in pairs(kv)do e:SetKeyValue(k,tostring(v))end;if kv.VehicleScript then e:SetKeyValue("vehiclescript",tostring(kv.VehicleScript))end;e:SetPos(p);e:SetAngles(a);e:Spawn();e:Activate();if e.SetVehicleClass then e:SetVehicleClass(class)end;return e end)end
  if not IsValid(ent)and scripted_ents.GetStored(class)then attempt("scripted entity",function()local e=ents.Create(class);if not IsValid(e)then return end;e:SetPos(p);e:SetAngles(a);e:Spawn();e:Activate();return e end)end
  if not IsValid(ent)then print("[GRM VehicleDealer] spawn failed "..class.." | "..table.concat(errors," | "))end
  if IsValid(ent)then
   -- v3.1.3: применяем ВЫСОТУ ПОСЛЕ посадки. DropToFloor ставит машину на землю
   -- (и simfphys внутри тоже сажает сам), поэтому сначала опускаем на поверхность,
   -- затем поднимаем на lift. Для simfphys посадка асинхронная (физика) — догоняем
   -- таймером, чтобы высота реально применилась.
   pcall(function()if ent.DropToFloor then ent:DropToFloor()end end)
   if lift>0 then
    local base=ent:GetPos()
    ent:SetPos(base+Vector(0,0,lift))
    timer.Simple(0.15,function()
     if not IsValid(ent)then return end
     local b2=ent:GetPos()
     -- simfphys после посадки мог снова опустить — поднимаем ещё раз поверх
     ent:SetPos(b2+Vector(0,0,lift))
    end)
   end
  end
  return IsValid(ent)and ent or nil,info,errors
 end
 local function garage(ply)local k=key(ply);VD.Garages[k]=VD.Garages[k]or{};return VD.Garages[k],k end
 local function activeCount(ply)local n=0;for _,e in pairs(VD.Active)do if IsValid(e)and e.GRMGarageOwner==ply then n=n+1 end end;return n end
 --[[ Одна и та же машина может стоять в ассортименте НЕСКОЛЬКО раз — под
      разные организации, цены и категории (заказ владельца 22.08). Поэтому
      ищем не «первую попавшуюся позицию класса», а ту, которой игрок
      реально может воспользоваться; если подходящей нет — возвращаем
      первую, чтобы отказ объяснялся обычной проверкой доступа. ]]
 local function findEntry(dealer,class,ply)
  local first
  for _,e in ipairs(dealer.VD_Vehicles or{})do
   if e.class==class then
    first=first or e
    if not IsValid(ply)or VD.CanUseEntry(ply,e)then return e end
   end
  end
  return first
 end
 --[[ ЛИМИТ ОДИНАКОВЫХ МАШИН (v3.6.0, заказ владельца 19.08).
      «Купленный транспорт должен как-то распознаваться, лимит 2 машины на
      покупку одного и того же класса». Считаем ПО КЛАССУ: и записи гаража
      (машина в гараже — всё равно купленная), и живые машины на карте, у
      которых записи нет (служебные). ]]
 VD.ClassLimitCvar = VD.ClassLimitCvar or CreateConVar("grm_vd_class_limit", "2",
  bit.bor(FCVAR_ARCHIVE), "Сколько машин ОДНОГО класса может держать игрок (0 — без лимита)")

 function VD.ClassLimit()return math.max(0,VD.ClassLimitCvar:GetInt())end

 --- Сколько машин этого класса уже за игроком (гараж + карта).
 function VD.CountClass(ply,class)
  class=tostring(class or"");if class==""then return 0 end
  local n,counted=0,{}
  for id,rec in pairs(VD.GarageRecords(ply)or{})do
   if istable(rec)and tostring(rec.class or"")==class then n=n+1;counted[id]=true end
  end
  for id,ent in pairs(VD.Active)do
   if not counted[id]and IsValid(ent)and ent.GRMGarageOwner==ply and tostring(ent.VD_Class or"")==class then n=n+1 end
  end
  return n
 end

 --- Можно ли выдать ещё одну машину этого класса.
 function VD.CanOwnMore(ply,class)
  local limit=VD.ClassLimit()
  if limit<=0 then return true end
  local have=VD.CountClass(ply,class)
  if have<limit then return true,have,limit end
  return false,have,limit
 end

 --- Метки на самой машине: по ним её узнают HUD, ключи, багажник и админка.
 function VD.TagVehicle(ent,ply,class,kind,record)
  if not IsValid(ent)then return end
  ent.VD_Class=class;ent.VD_Owner=ply;ent.GRMVehicleKind=kind
  ent:SetNWString("GRM_VehicleClass",tostring(class or""))
  ent:SetNWString("GRM_VehicleKind",tostring(kind or"personal"))
  ent:SetNWString("GRM_VehicleName",nameV(istable(record)and record.name or class,class))
  ent:SetNWString("GRM_WorkVehicle",tostring(kind or""):find("job_",1,true)==1 and tostring(kind):sub(5)or"")
  if IsValid(ply)then
   ent:SetNWEntity("GRM_VehicleOwnerEnt",ply)
   ent:SetNWString("GRM_VehicleOwner",ply:GetNWString("GRM_RPName",ply:Nick()))
  end
  if istable(record)and record.id then ent:SetNWString("GRM_VehicleRecord",tostring(record.id))end
 end

 -- Назначение замка выполняется после каждого пути выдачи. simfphys может
 -- закончить инициализацию позже SpawnVehicle, поэтому повторяем на
 -- следующем тике: без этого машина выглядит «без владельца» у рядового.
 function VD.AssignLockOwner(ent,ply,kind,faction)
  if not IsValid(ent)or not IsValid(ply)then return false end
  local function apply()
   if not IsValid(ent)then return end
   if tostring(kind or"")=="government"and tostring(faction or"")~=""then
    if VK and VK.SetFactionOwner then VK.SetFactionOwner(ent,tostring(faction))end
   else
    if VK and VK.SetPlayerOwner then VK.SetPlayerOwner(ent,ply)end
   end
  end
  apply();timer.Simple(0,function()apply()end);timer.Simple(.35,function()apply()end)
  return true
 end

 --- Это машина, выданная дилером (для внешних модулей).
 function VD.IsDealerVehicle(ent)
  return IsValid(ent)and(ent.GRMGarageID~=nil or tostring(ent:GetNWString("GRM_VehicleClass",""))~="")
 end

 --[[ ЕДИНЫЙ СЛОЙ «ЗАПИСЬ ГАРАЖА ↔ ЖИВАЯ МАШИНА» (v3.5.0).
      Раньше выдача/уборка личного транспорта была раскопирована по операциям
      меню дилера. Теперь это три функции, которыми пользуются и дилер, и
      модуль гаражей (GRM.Garage) — одна логика, одни проверки, одно
      сохранение. ]]
 function VD.GarageRecords(ply)local g=garage(ply);return g end
 function VD.SaveGarages()return saveGarage()end
 -- Единый путь оформления ЛИЧНОЙ машины для дилера и гражданского рынка.
 -- Не спавнит entity: запись сначала попадает в личный гараж.
 function VD.CreatePersonalRecord(ply,spec,garageID)
  if not IsValid(ply)or not istable(spec)then return nil,"Игрок или позиция не найдены"end
  local class=tostring(spec.class or"");if class==""then return nil,"Не указан класс транспорта"end
  local allowed,have,limit=VD.CanOwnMore(ply,class)
  if not allowed then return nil,("У вас уже %d шт. этого класса (предел %d)"):format(have,limit)end
  local info=VD.VehicleInfo(class);local id=makeID("vehicle")
  local rec={id=id,class=class,name=nameV(spec.name or info.name,class),model=tostring(spec.model or info.model or""),price=math.max(0,math.floor(tonumber(spec.price)or 0)),stored=true,service=false,ownershipType="personal",requestedGarage=tostring(garageID or""):sub(1,48),marketID=tostring(spec.marketID or"")}
  local g=garage(ply);g[id]=rec
  hook.Run("GRM_VehicleDealerSpawned",nil,ply,class,rec,nil)
  if not saveGarage()then g[id]=nil return nil,"Не удалось сохранить личный гараж"end
  return rec
 end
 function VD.ActiveCount(ply)return activeCount(ply)end
 function VD.FindRecord(ply,id)local g=garage(ply);return g[tostring(id or"")]end
 function VD.SetRecordGarage(ply,id,garageID)
  local r=VD.FindRecord(ply,id);if not r then return false,"Запись гаража не найдена"end
  r.garageID=tostring(garageID or"");saveGarage();return true
 end
 -- Выдать машину по записи. place={pos,ang,lift} — место гаража; если места
 -- нет, работает по-старому от дилера.
 --[[ ГДЕ ПОЯВИТСЯ МАШИНА (заказ владельца 21.08: «места выдачи не
      срабатывают, транспорт спавнится перед дилером»).

      Раньше выдача у дилера ВООБЩЕ не смотрела на гаражи: место бралось
      только из точки/площадки самого дилера. Размеченные места гаража
      использовались лишь в окне гаража — отсюда ощущение, что точки и
      места «ничего не делают».

      Теперь место выбирается по одному правилу, в порядке убывания
      конкретности:
        1) явное место (гараж прислал слот) — как было;
        2) свободное МЕСТО ГАРАЖА, связанного с этим дилером;
        3) свободное место домашнего гаража машины, если он рядом с дилером;
        4) собственная точка/площадка дилера;
        5) перед дилером — последний фолбэк.
      Возвращаем ещё и описание места, чтобы игрок видел, куда подали. ]]
 function VD.ResolveDeliveryPlace(ply,rec,dealer,place)
  if istable(place)and place.pos then return place,"место гаража" end
  local G=GRM.Garage
  if not (G and G.FreeSlot and G.Get)then return nil,"площадка дилера" end

  --[[ Разбор ведём с ПРИЧИНАМИ: если место не подошло, игрок (и лог) видят,
       почему именно — «гараж чужой», «нет мест», «все места заняты». Без
       этого «ноль реакции» приходилось выяснять экспериментом. ]]
  local reasons={}
  local seen={}
  local function slotOf(garage)
   if not istable(garage)then return nil end
   if seen[garage.id]then return nil end
   seen[garage.id]=true
   if #(garage.slots or{})==0 then
    reasons[#reasons+1]=("гараж «%s»: не размечено ни одного места"):format(tostring(garage.name))
    return nil
   end
   if IsValid(ply)and G.CanUse and not G.CanUse(ply,garage)then
    reasons[#reasons+1]=("гараж «%s»: нет доступа"):format(tostring(garage.name))
    return nil
   end
   local p,err=G.FreeSlot(garage,ply)
   if p then return p,("место «%s» гаража «%s»"):format(
     (p.slot and p.slot.name)or"стоянка",tostring(garage.name))end
   reasons[#reasons+1]=("гараж «%s»: %s"):format(tostring(garage.name),tostring(err or "мест нет"))
   return nil
  end

  --[[ 1) ГАРАЖ, ГДЕ СТОИТ ИГРОК ИЛИ ДИЛЕР.
       Самое ожидаемое поведение: разметил места — машины появляются на них,
       без всякой ручной привязки. Сначала смотрим гараж под ногами игрока,
       потом гараж, в зоне которого стоит сам дилер, потом ближайший гараж
       в пределах 1200 юнитов. ]]
  local near={}
  if IsValid(ply)and G.FindByPos then near[#near+1]=G.FindByPos(ply:GetPos())end
  if IsValid(dealer)and G.FindByPos then near[#near+1]=G.FindByPos(dealer:GetPos())end
  if IsValid(dealer)and G.Nearest then near[#near+1]=G.Nearest(dealer:GetPos(),1200)end
  if IsValid(ply)and G.Nearest then near[#near+1]=G.Nearest(ply:GetPos(),1200)end
  for _,garage in ipairs(near)do
   local p,label=slotOf(garage)
   if p then return p,label end
  end

  -- 2) гараж, связанный с дилером
  if IsValid(dealer)and dealer.GetDealerID then
   local dealerID=tostring(dealer:GetDealerID() or "")
   if dealerID~="" then
    for _,garage in pairs(G.Garages or{})do
     for _,linked in ipairs(garage.linkedDealers or{})do
      if tostring(linked)==dealerID then
       local p,label=slotOf(garage)
       if p then return p,label end
      end
     end
    end
   end
  end

  -- 3) домашний гараж машины, если он недалеко от дилера
  local home=G.Get(rec and rec.garageID or "")
  if istable(home)then
   local far=false
   if IsValid(dealer)and G.ZoneCenter then
    far=G.ZoneCenter(home):Distance(dealer:GetPos())>3000
   end
   if not far then
    local p,label=slotOf(home)
    if p then return p,label end
   end
  end
  VD.LastPlaceReason=#reasons>0 and table.concat(reasons,"; ")
   or "рядом нет гаража с местами выдачи"
  if VD.SlotDebugCvar and VD.SlotDebugCvar:GetBool()then
   print("[GRM VehicleDealer] место выдачи не найдено: "..VD.LastPlaceReason)
  end
  return nil,"площадка дилера"
 end

 function VD.IssueRecord(ply,id,place,dealer)
  if not IsValid(ply)then return nil,"Игрок не найден"end
  id=tostring(id or"");local r=VD.FindRecord(ply,id)
  if not r then return nil,"Запись гаража не найдена"end
  if r.service then return nil,"Служебный транспорт выдаётся у дилера"end
  if IsValid(VD.Active[id])then return nil,"Транспорт уже выдан"end
  if activeCount(ply)>=VD.MaxActive then return nil,("Лимит активного транспорта: %d"):format(VD.MaxActive)end
  local resolved,placeLabel=VD.ResolveDeliveryPlace(ply,r,dealer,place)
  place=resolved or place
  local ent,_,spawnErrors=VD.Spawn(r.class,dealer,ply,place)
  if not ent then return nil,(spawnErrors and spawnErrors[1])or"Не удалось выдать транспорт"end
  r.lastPlace=tostring(placeLabel or "")
  r.stored=false;saveGarage()
  ent.GRMGarageID=id;ent.GRMGarageOwner=ply;ent.GRMGarageOwnerKey=key(ply);ent.VD_Price=r.price
  VD.TagVehicle(ent,ply,r.class,tostring(r.ownershipType or"personal"),r)
  VD.Active[id]=ent
  if VD.AssignLockOwner then VD.AssignLockOwner(ent,ply,"personal") end
  hook.Run("GRM_VehicleIssued",ply,ent,r,place)
  return ent
 end
 -- Убрать машину с карты. maxDist=nil — без ограничения по дистанции.
 function VD.StoreRecord(ply,id,maxDist)
  if not IsValid(ply)then return false,"Игрок не найден"end
  id=tostring(id or"");local ent=VD.Active[id]
  if not IsValid(ent)or ent.GRMGarageOwner~=ply then return false,"Активный транспорт не найден"end
  local driver=ent.GetDriver and ent:GetDriver()or nil
  if IsValid(driver)and driver~=ply then return false,"В транспорте сидит водитель"end
  maxDist=tonumber(maxDist)
  if maxDist and ply:GetPos():DistToSqr(ent:GetPos())>maxDist*maxDist then return false,"Подгоните транспорт ближе"end
  local r=VD.FindRecord(ply,id)
  ent:Remove();VD.Active[id]=nil
  if r then r.stored=true;saveGarage()end
  hook.Run("GRM_VehicleStored",ply,id,r)
  return true,r and"Транспорт убран в гараж"or"Служебный транспорт убран"
 end

 --[[ v3.4.0 (заказ владельца): «Убрать транспорт» теперь есть и в меню дилера,
      а не только в контекстном C-меню. Для этого дилер присылает список
      ЖИВОГО транспорта игрока (в т.ч. служебного, у которого нет записи в
      гараже — раньше такую машину из меню убрать было нечем). ]]
 function VD.ActiveRows(ply)
  local rows,k={},key(ply);local g=VD.Garages[k]or{}
  for id,ent in pairs(VD.Active)do
   if IsValid(ent)and ent.GRMGarageOwner==ply then
    local rec=g[id]
    local class=tostring(ent.VD_Class or rec and rec.class or ent:GetClass())
    local info=VD.VehicleInfo(class)
    local kind=tostring(ent.GRMVehicleKind or rec and rec.ownershipType or"personal")
    rows[#rows+1]={
     id=id,class=class,name=(rec and rec.name)or info.name or class,model=info.model,
     ownershipType=kind,ownershipName=VD.VehicleKinds[kind]or"Транспорт",
     personal=kind=="personal",
     distance=math.floor(ply:GetPos():Distance(ent:GetPos())),
     occupied=IsValid(ent.GetDriver and ent:GetDriver()or nil),
    }
   end
  end

  --[[ СЛУЖЕБНЫЙ ПАРК ОРГАНИЗАЦИИ В РАЗДЕЛЕ «НА КАРТЕ».
       Раньше здесь были только личные машины из VD.Active, а единицы
       автопарка (FL.Active) в списке не появлялись: «убрать в гараж»
       у дилера для служебного фракционного авто было недоступно.
       Теперь активная техника организации видна в том же разделе и
       возвращается в гараж той же командой, что и личная. ]]
  local FL=GRM.Fleet
  if FL and FL.UnitsOf then
   local faction=tostring(ply:GetNWString("GRM_Faction","")or"")
   if faction~="" then
    for _,unit in ipairs(FL.UnitsOf(faction))do
     local ent=FL.Active and FL.Active[unit.id]
     if IsValid(ent)then
      local kind=tostring(unit.kind or"government")
      rows[#rows+1]={
       id=tostring(unit.id or""),
       class=tostring(unit.class or""),
       name=nameV(unit.name,unit.class),
       model=tostring(unit.model or""),
       ownershipType=kind,
       ownershipName=VD.VehicleKinds[kind]or"Служебный транспорт",
       personal=false,
       fleet=true,
       distance=math.floor(ply:GetPos():Distance(ent:GetPos())),
       occupied=IsValid(ent.GetDriver and ent:GetDriver()or nil),
       plate=(GRM.Plates and GRM.Plates.PlateOfVehicleKey)
        and tostring(GRM.Plates.PlateOfVehicleKey("fleet:"..tostring(unit.id))or"")or"",
      }
     end
    end
   end
  end

  table.sort(rows,function(a,b)return tostring(a.name)<tostring(b.name)end)
  return rows
 end
 function VD.Push(ply,dealer)local g=garage(ply);local garageRows={}
  for _,r in pairs(g)do
   -- В карточке гаража показываем, к какому гаражу приписана машина
   -- (модуль GRM.Garage; если его нет — поле просто пустое).
   local row=table.Copy(r);local home=GRM.Garage and GRM.Garage.Get and GRM.Garage.Get(r.garageID)
   -- Имена из старых сохранённых записей гаража тоже гоним через фильтр (02.09).
   if isstring(row.name)then row.name=nameV(row.name,r.class)end
   row.homeName=home and home.name or"";row.homeID=tostring(r.garageID or"")
   row.buyback=VD.StateBuybackPrice(r);row.buybackRate=VD.StateBuybackRate()
   -- Номерной знак машины и её UID: карточка в окне дилера показывает,
   -- под каким номером машина зарегистрирована (заказ владельца 22.08).
   row.plate=tostring(r.plate or"")
   row.uid="veh:"..tostring(r.id or"")
   -- НОМЕР ДОЛЖЕН ВИДЕТЬСЯ У ДИЛЕРА, КАК ТОЛЬКО ЗАКРЕПЛЁН.
   -- Источники, по порядку: запись гаража → реестр по UID → активная
   -- машина (если выдана, но запись ещё не синхронизировалась).
   if GRM.Plates and GRM.Plates.PlateOfVehicleKey then
    local db=tostring(GRM.Plates.PlateOfVehicleKey(row.uid)or"")
    if db~="" then row.plate=db end
   end
   if row.plate=="" then
    local ent=VD.Active and VD.Active[r.id]
    if IsValid(ent) and GRM.Plates and GRM.Plates.VehiclePlates then
     local children=GRM.Plates.VehiclePlates(ent)
     if #children>0 then row.plate=tostring(children[1]:GetNWString("GRM_Plate","")or"") end
    end
   end
   garageRows[#garageRows+1]=row
  end
  --[[ СЛУЖЕБНЫЙ ПАРК ОРГАНИЗАЦИИ — ПОШТУЧНО (заказ владельца 22.08:
       «каждая служебная машина должна считаться отдельно»). Каталог
       показывает КЛАССЫ (что можно закупить), а этот список — реальные
       единицы техники: у каждой своё состояние и гараж (номер, если есть,
       берётся из реестра — автоматически он не генерируется). ]]
  local fleetRows={}
  do
   local FL=GRM.Fleet
   local faction=ply:GetNWString("GRM_Faction","")
   if FL and FL.UnitsOf and faction~="" then
    for _,unit in ipairs(FL.UnitsOf(faction)) do
     local allowed,why=true,nil
     if FL.UnitAllowedFor then allowed,why=FL.UnitAllowedFor(unit,FL.ActorOf and FL.ActorOf(ply) or nil) end
     local garageRec=GRM.Garage and GRM.Garage.Get and GRM.Garage.Get(unit.garageID) or nil
     local fleetUID="fleet:"..tostring(unit.id)
     local fplate=tostring(unit.plate or"")
     if GRM.Plates and GRM.Plates.PlateOfVehicleKey then
      local db=tostring(GRM.Plates.PlateOfVehicleKey(fleetUID)or"")
      if db~="" then fplate=db end
     end
     if fplate=="" then
      local ent=FL.Active and FL.Active[unit.id]
      if IsValid(ent) and GRM.Plates and GRM.Plates.VehiclePlates then
       local children=GRM.Plates.VehiclePlates(ent)
       if #children>0 then fplate=tostring(children[1]:GetNWString("GRM_Plate","")or"") end
      end
     end
     fleetRows[#fleetRows+1]={
      id=unit.id,class=unit.class,name=nameV(unit.name,unit.class),model=unit.model,
      onMap=FL.Active and IsValid(FL.Active[unit.id]) or false,
      statusName=FL.UnitStatuses and FL.UnitStatuses[unit.status] or tostring(unit.status or ""),
      garageName=garageRec and garageRec.name or "",
      restriction=FL.RestrictionText and FL.RestrictionText(unit) or "",
      allowed=allowed==true,reason=allowed and "" or tostring(why or ""),
      plate=fplate,
     }
    end
   end
  end
  local catalog={}for _,e in ipairs(dealer.VD_Vehicles or{})do if VD.CanUseEntry(ply,e)then local i=VD.VehicleInfo(e.class);local personal=VD.EntryKind(e)=="personal";local civil=personal and GRM.CivilVehicles and GRM.CivilVehicles.FindForDealer and GRM.CivilVehicles.FindForDealer(e)or nil;local market=not personal and GRM.Fleet and GRM.Fleet.FindMarketForDealer and GRM.Fleet.FindMarketForDealer(e)or nil;local inMarket=personal and civil~=nil or market~=nil;if not personal or civil then catalog[#catalog+1]={class=e.class,name=nameV((civil and civil.name)or e.name,i.name),model=i.model,system=i.system,price=math.max(0,math.floor(tonumber((civil and civil.price)or(market and market.price)or e.price)or 0)),category=(civil and civil.category)or e.category or"Транспорт",service=VD.EntryKind(e)~="personal",faction=e.faction,owned=VD.CountClass(ply,e.class),classLimit=VD.ClassLimit(),factionName=(e.faction and e.faction~=""and((GRM.Factions and GRM.Factions.DisplayName and GRM.Factions.DisplayName(e.faction))or e.faction)or""),ownershipType=VD.EntryKind(e),ownershipName=VD.VehicleKinds[VD.EntryKind(e)],marketID=inMarket and ((civil and civil.id)or market.id)or"",marketReady=inMarket}end end end;local garageChoices=(GRM.Garage and GRM.Garage.ChoicesFor)and GRM.Garage.ChoicesFor(ply,dealer)or{}
  net.Start("GRM_VD_Open")net.WriteEntity(dealer)net.WriteString(dealer:GetDealerName())net.WriteTable(catalog)net.WriteTable(garageRows)net.WriteTable(VD.ActiveRows(ply))net.WriteTable(garageChoices)
   net.WriteString(VD.DeliveryMode(dealer))net.WriteBool(VD.ShowRetrieve(dealer))net.WriteTable(fleetRows)net.Send(ply)end
 local function result(ply,ok,msg)net.Start("GRM_VD_Result")net.WriteBool(ok)net.WriteString(msg)net.Send(ply);if GRM.Notify then GRM.Notify(ply,msg,ok and 100 or 255,ok and 220 or 110,ok and 130 or 90)end end
 net.Receive("GRM_VD_Action",function(_,ply)local dealer,op=net.ReadEntity(),net.ReadString();if not IsValid(dealer)or dealer:GetClass()~="sent_vehicle_dealer"or ply:GetPos():DistToSqr(dealer:GetPos())>300*300 then return end;ply.GRMVDNext=ply.GRMVDNext or 0;if CurTime()<ply.GRMVDNext then return end;ply.GRMVDNext=CurTime()+.35
  if op=="buy"then local class=net.ReadString();local wantGarage=net.ReadString()or"";local wantWay=net.ReadString()or"";local entry=findEntry(dealer,class,ply);if not entry or not VD.CanUseEntry(ply,entry)then result(ply,false,"Транспорт недоступен")return end;local kind=VD.EntryKind(entry)
   --[[ ПОКУПКА ≠ ВЫДАЧА (заказ владельца 21.08).
        Раньше кнопка «Купить» сразу спавнила машину (или отправляла её в
        гараж) — покупка и выдача были одним действием, и настройка дилера
        решала за игрока. Теперь личный транспорт при покупке ТОЛЬКО
        оформляется в собственность и встаёт на хранение; на карту он
        выходит отдельной кнопкой «ВЫДАТЬ», где игрок сам выбирает — у
        дилера или в гараже. Служебный транспорт покупкой не является:
        он по-прежнему выдаётся на месте. ]]
   local personal=(kind=="personal")
   -- Личный каталог дилера — только ручные позиции гражданского рынка.
   -- Цена рынка серверно подменяет старую цену ассортимента дилера.
   if personal and GRM.CivilVehicles and GRM.CivilVehicles.FindForDealer then
    local civil=GRM.CivilVehicles.FindForDealer(entry)
    if not civil then result(ply,false,"Эта личная машина не выставлена на гражданском рынке")return end
    entry=table.Copy(entry);entry.price=civil.price;entry.name=civil.name or entry.name
   end
   local allowed,have,limit=VD.CanOwnMore(ply,class)
   if not allowed then result(ply,false,("У вас уже %d шт. «%s» — это предел (%d на класс). Продайте одну, чтобы взять ещё."):format(have,tostring(entry.name or class),limit))return end
   if not personal and activeCount(ply)>=VD.MaxActive then result(ply,false,"Лимит активного транспорта")return end
   local record_placeLabel=nil
   local price=personal and math.max(0,math.floor(tonumber(entry.price)or 0))or 0;if price>0 and(not GRM.HasMoney or not GRM.HasMoney(ply,price))then result(ply,false,"Недостаточно средств")return end;local info=VD.VehicleInfo(class)
   local ent
   if not personal then
    -- служебная машина тоже встаёт на место гаража, если оно есть
    local placeSvc,placeLabelSvc=VD.ResolveDeliveryPlace(ply,{class=class},dealer,nil)
    local spawnErrors;ent,info,spawnErrors=VD.Spawn(class,dealer,ply,placeSvc)
    if IsValid(ent)then record_placeLabel=placeLabelSvc end
    if not ent then result(ply,false,(spawnErrors and spawnErrors[1])or"Не удалось создать транспорт")return end
   end
   if price>0 and GRM.TakeMoney then GRM.TakeMoney(ply,price,"Покупка транспорта "..class)end;local id=makeID("vehicle");local record={id=id,class=class,name=entry.name or info.name,model=info.model,price=price,stored=true,dealerID=dealer:GetDealerID(),service=not personal,ownershipType=kind}
   -- Гараж приписки, выбранный игроком в меню: сам дилер про гаражи не
   -- знает, поле читает модуль GRM.Garage в хуке ниже.
   record.requestedGarage=tostring(wantGarage or""):sub(1,48);if personal then local g=garage(ply);g[id]=record;saveGarage()end;if IsValid(ent)then
    record.stored=false
    ent.GRMGarageID=id;ent.GRMGarageOwner=ply;ent.GRMGarageOwnerKey=key(ply);ent.VD_Price=price;VD.TagVehicle(ent,ply,class,kind,record);VD.Active[id]=ent
    if VD.AssignLockOwner then VD.AssignLockOwner(ent,ply,"personal") end
   end
   hook.Run("GRM_VehicleDealerSpawned",ent,ply,class,record,dealer)
   local home=(GRM.Garage and GRM.Garage.Get)and GRM.Garage.Get(record.garageID)or nil
   result(ply,true,IsValid(ent)and(("Транспорт выдан: %s — %s"):format(record.name,tostring(record_placeLabel or "площадка дилера")))
    or(home and ("Транспорт приобретён: %s. Стоит в гараже «%s» — нажмите «ВЫДАТЬ»."):format(record.name,home.name)
    or ("Транспорт приобретён: "..record.name..". Нажмите «ВЫДАТЬ», чтобы получить его.")))
   VD.Push(ply,dealer)
  elseif op=="retrieve"then local id=net.ReadString();local way=net.ReadString()or"";local wantGarage=net.ReadString()or""
   --[[ ВЫДАЧА: игрок сам выбирает способ.
        way="dealer" — машина подаётся здесь, у дилера;
        way="garage" — машина подаётся на свободное место гаража (своего или
        выбранного), забирать её нужно там. ]]
   local rec=VD.FindRecord(ply,id)
   if not rec then result(ply,false,"Запись гаража не найдена")return end
   -- Режим дилера ограничивает только выдачу НА МЕСТЕ: "garage" — этот дилер
   -- машины не отдаёт, забирать в гараже. Подача в гараж доступна всегда,
   -- пока есть модуль гаражей и доступный гараж.
   local mode=VD.DeliveryMode(dealer)
   if way=="" then way=(mode=="garage")and"garage"or"dealer" end
   if way=="dealer" and mode=="garage" then way="garage" end

   if way=="garage" then
    if not(GRM.Garage and GRM.Garage.IssueRemote)then result(ply,false,"Модуль гаражей не подключён")return end
    local okG,msgG=GRM.Garage.IssueRemote(ply,id,wantGarage~=""and wantGarage or rec.garageID)
    result(ply,okG,msgG or(okG and"Транспорт подан в гараж"or"Не удалось подать транспорт в гараж"))
    if okG then VD.Push(ply,dealer)end
    return
   end

   -- Выдача у дилера. Если у машины есть домашний гараж и включён строгий
   -- режим (grm_garage_strict 1) — забирать её нужно именно в гараже.
   if not VD.ShowRetrieve(dealer)then result(ply,false,"Этот дилер не выдаёт транспорт — заберите машину в гараже")return end
   if rec and GRM.Garage and GRM.Garage.DealerIssueBlocked then
    local blocked,why=GRM.Garage.DealerIssueBlocked(ply,rec)
    if blocked then result(ply,false,why or"Заберите транспорт в своём гараже")return end
   end
   local ent,err=VD.IssueRecord(ply,id,nil,dealer)
   if not ent then result(ply,false,err or"Не удалось выдать транспорт")return end
   local placeMsg=tostring(rec.lastPlace~=""and rec.lastPlace or "площадка дилера")
   if rec.lastPlace=="площадка дилера"and ply:IsSuperAdmin()and VD.LastPlaceReason then
    ply:ChatPrint("[Гараж] Места не сработали: "..tostring(VD.LastPlaceReason)..
     " (проверьте grm_garage_slots)")
   end
   result(ply,true,("Транспорт выдан: %s"):format(placeMsg))
   VD.Push(ply,dealer)
  elseif op=="fleet_buy"then
   --[[ ЕДИНЫЙ МЕХАНИЗМ ЗАКУПКИ (заказ владельца 22.08).
        Служебная позиция у дилера — это НЕ «получить машину», а заявка на
        закупку в автопарк организации: деньги идут из бюджета, а на карте
        появляется отдельная ЕДИНИЦА техники со своим слотом. Номер
        автоматически не генерируется — ставится вручную, как личным
        машинам. Выдаётся она потом — из раздела «Техника организации». ]]
   local class=net.ReadString();local wantGarage=net.ReadString()or"";local marketID=net.ReadString()or""
   local FL=GRM.Fleet
   if not(FL and FL.Buy and FL.MarketList)then result(ply,false,"Автопарк недоступен")return end
   local faction=ply:GetNWString("GRM_Faction","")
   local pick
   --[[ ЗАКУПКА ИМЕННО ТОЙ ПОЗИЦИИ, ЧТО БЫЛА НА КАРТОЧКЕ.
        Клиент шлёт marketID вместе с классом. Если позиция с этим id
        пропала (дилер пересохранён, цена/ассортимент изменились) — не
        подменяем её другой карточкой класса: это была бы чуждая цена. ]]
   -- Служебная карточка дилера сама является живой позицией автопарка.
   -- Берём её повторно на сервере: клиент не может подменить класс, цену
   -- или позицию другого дилера.
   if marketID~="" then
    local exact=FL.Entry and FL.Entry(marketID) or nil
    if exact and tostring(exact.class)==class then
     pick=exact
    else
     result(ply,false,"Позиция дилера изменилась. Обновите каталог и повторите закупку")
     return
    end
   end
   if not pick then
    for _,entry in ipairs(FL.MarketList())do
     if tostring(entry.class)==class then
      local allowed=FL.EntryAllowed and FL.EntryAllowed(entry,faction,
       (GRM.PCBoard and GRM.PCBoard.PlayerLevel and GRM.PCBoard.PlayerLevel(ply))or"none",ply:IsSuperAdmin())
      if allowed or not FL.EntryAllowed then pick=entry break end
      pick=pick or entry
     end
    end
   end
   if not pick then result(ply,false,"Позиция закупки не найдена: обновите каталог дилера")return end
   local made,err=FL.Buy(ply,pick.id,1,wantGarage)
   result(ply,made~=nil,made and("Закуплено в автопарк: "..tostring(pick.name))or tostring(err or"Не удалось закупить"))
   if made then VD.Push(ply,dealer)end
  elseif op=="fleet_issue"or op=="fleet_store"then
   --[[ Служебная техника поштучно: выдаём и возвращаем КОНКРЕТНУЮ единицу
        автопарка, а не «какую-нибудь машину этого класса». Вся логика
        (право по должности, свободное место, статус) живёт в едином
        диспетчере GRM.Vehicles — дилер только передаёт запрос. ]]
   local id=net.ReadString()
   local V=GRM.Vehicles
   if not V then result(ply,false,"Диспетчер транспорта недоступен")return end
   local ok,msg
   if op=="fleet_issue"then ok,msg=V.Issue(ply,"fleet",id,nil) else ok,msg=V.Store(ply,"fleet",id) end
   result(ply,ok==true,msg or(ok and"Готово"or"Не удалось"))
   if ok then VD.Push(ply,dealer)end
  elseif op=="store"then local id=net.ReadString();local ok,msg=VD.StoreRecord(ply,id,700);result(ply,ok,msg or"Транспорт помещён в гараж");if ok then VD.Push(ply,dealer)end
  elseif op=="remove"then local id=net.ReadString();local ok,msg=VD.StoreRecord(ply,id,nil);result(ply,ok,msg or"Транспорт убран");if ok then VD.Push(ply,dealer)end
  elseif op=="sell"then
   -- «Продать государству»: цена — процент от покупки (grm_vd_state_buyback).
   local id=net.ReadString();local g=garage(ply);local r=g[id]
   if not r then result(ply,false,"Запись гаража не найдена")return end
   if r.service then result(ply,false,"Служебный транспорт не выкупается")return end
   local payout=VD.StateBuybackPrice(r)
   if payout<=0 then result(ply,false,"Эта машина досталась бесплатно — государство её не выкупает")return end
   local ent=VD.Active[id]
   if IsValid(ent)then
    local driver=ent.GetDriver and ent:GetDriver()or nil
    if IsValid(driver)and driver~=ply then result(ply,false,"В транспорте сидит водитель")return end
    ent:Remove()
   end
   VD.Active[id]=nil;g[id]=nil;saveGarage()
   if GRM.GiveMoney then GRM.GiveMoney(ply,payout,"Выкуп транспорта государством")end
   -- Деньги приходят из казны: если экономика подключена, бюджет уменьшается.
   if GRM.Economy and GRM.Economy.StateBudgetAdd then
    pcall(GRM.Economy.StateBudgetAdd,-payout,"Выкуп транспорта у "..ply:Nick())
   end
   if GRM.Audit and GRM.Audit.Write then
    GRM.Audit.Write("vehicle","state.buyback",ply,{record=id,class=r.class},{price=r.price,payout=payout,rate=VD.StateBuybackRate()})
   end
   result(ply,true,("Государство выкупило «%s» за %s (%d%% от цены покупки)"):format(
    tostring(r.name or r.class),GRM.Format and GRM.Format(payout)or payout,VD.StateBuybackRate()))
   VD.Push(ply,dealer)
  end
 end)
 net.Receive("GRM_VD_ZoneRequest",function(_,ply)if not IsValid(ply)or not ply:IsSuperAdmin()then return end;local out={}for _,d in ipairs(ents.FindByClass("sent_vehicle_dealer"))do if IsValid(d)then out[#out+1]={id=d:GetDealerID(),name=d:GetDealerName(),pos=vd(d:GetPos()),hasZone=d:GetHasSpawnZone(),min=vd(d:GetSpawnZoneMin()),max=vd(d:GetSpawnZoneMax()),ang=ad(d:GetSpawnAngle()),hasPoint=d:GetHasCustomSpawn(),spawnPos=vd(d:GetSpawnPos()),spawnAng=ad(d:GetSpawnAngle()),lift=tonumber(d.VD_Lift)or VD.DefaultLift}end end;net.Start("GRM_VD_ZoneData")net.WriteTable(out)net.Send(ply)end)
 net.Receive("VD_RequestVehicleList",function(_,ply)if not IsValid(ply)or not ply:IsSuperAdmin()then return end;local out={}for _,v in ipairs(VD.AllVehicleClasses())do out[#out+1]={class=v.class,name=v.name,dealer="GRM v3"}end;net.Start("VD_VehicleList")net.WriteTable(out)net.Send(ply)end)
 net.Receive("VD_AdminSpawnVehicle",function(_,ply)if not IsValid(ply)or not ply:IsSuperAdmin()then return end;local sid,class=net.ReadString(),net.ReadString();local target;for _,p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll())do if p:SteamID64()==sid then target=p break end end;if not IsValid(target)then return end;local d,best=nil,math.huge;for _,candidate in ipairs(ents.FindByClass("sent_vehicle_dealer"))do local distance=target:GetPos():DistToSqr(candidate:GetPos());if distance<best then d,best=candidate,distance end end;if not IsValid(d)then return end;local placeAdm=VD.ResolveDeliveryPlace(target,{class=class},d,nil);local ent=VD.Spawn(class,d,target,placeAdm);if IsValid(ent)then local id=makeID("admin_vehicle");ent.GRMGarageID=id;ent.GRMGarageOwner=target;ent.GRMGarageOwnerKey=key(target);ent.VD_Owner=target;ent.VD_Class=class;VD.Active[id]=ent end end)
 net.Receive("GRM_VD_AdminSave",function(_,ply)
  if not IsValid(ply)or not ply:IsSuperAdmin()then return end
  local dealer,data=net.ReadEntity(),net.ReadTable()or{};if not IsValid(dealer)or dealer:GetClass()~="sent_vehicle_dealer"or ply:GetPos():DistToSqr(dealer:GetPos())>600*600 then return end
  dealer:SetDealerName(tostring(data.name or"Дилер транспорта"):sub(1,64));local model=tostring(data.model or"")
  if util.IsValidModel(model)then
   if dealer.ApplyDealerModel then dealer:ApplyDealerModel(model)else dealer:SetDealerModel(model);dealer:SetModel(model)end
  elseif dealer.ApplyIdleAnimation then dealer:ApplyIdleAnimation(true)end
  dealer.VD_Delivery=VD.DeliveryModes[tostring(data.delivery or"")]and tostring(data.delivery)or"dealer"
  dealer.VD_ShowRetrieve=data.showRetrieve~=false
  local available={};for _,v in ipairs(VD.AllVehicleClasses())do available[v.class]=true end;dealer.VD_Vehicles={};for _,e in ipairs(istable(data.vehicles)and data.vehicles or{})do if #dealer.VD_Vehicles>=256 then break end;local class=tostring(e.class or"");if available[class]then dealer.VD_Vehicles[#dealer.VD_Vehicles+1]={class=class,name=tostring(e.name or VD.VehicleInfo(class).name):sub(1,64),price=math.Clamp(math.floor(tonumber(e.price)or 0),0,100000000),category=tostring(e.category or"Транспорт"):sub(1,40),faction=tostring(e.faction or""):sub(1,64),service=VD.EntryKind(e)~="personal",ownershipType=VD.VehicleKinds[tostring(e.ownershipType or"")]and e.ownershipType or(e.service and(e.faction and e.faction~=""and"government"or"public")or"personal")}end end
  local ok,detail=VD.SaveDealer(dealer);net.Start("GRM_VD_Result")net.WriteBool(ok==true)net.WriteString(ok and("Дилер и ассортимент сохранены: "..tostring(detail))or tostring(detail or"Ошибка"))net.Send(ply)
 end)
 function _G.VD_RemoveDealerVehicle(ply,veh,opts)
  if not IsValid(ply)or not IsValid(veh)or veh.GRMGarageOwner~=ply then return false,"Это не ваш транспорт",0 end
  local max=tonumber(opts and opts.maxDist)or 600;if ply:GetPos():DistToSqr(veh:GetPos())>max*max then return false,"Слишком далеко от транспорта",0 end
  local id=veh.GRMGarageID;local g=garage(ply);local record=g[id];veh:Remove();VD.Active[id]=nil
  if record then record.stored=true;saveGarage();return true,"Транспорт помещён в гараж",0 end
  return true,"Служебный транспорт убран",0
 end
 hook.Add("PlayerDisconnected","GRM_VD_StoreDisconnect",function(ply)for id,e in pairs(VD.Active)do if IsValid(e)and e.GRMGarageOwner==ply then e:Remove();VD.Active[id]=nil;local g=VD.Garages[key(ply)];if g and g[id]then g[id].stored=true end end end;saveGarage()end)
 hook.Add("EntityRemoved","GRM_VD_ActiveCleanup",function(e)local id=e.GRMGarageID;if id and VD.Active[id]==e then VD.Active[id]=nil;local owner=e.GRMGarageOwner;if IsValid(owner)then local g=VD.Garages[key(owner)];if g and g[id]then g[id].stored=true;saveGarage()end end end end)
 local function migrateLegacyDealers()
  if #loadDealers()>0 or not file.IsDir("grm/dealers","DATA")then return end
  local files=file.Find("grm/dealers/*.json","DATA");local records={}
  for _,fname in ipairs(files or{})do local old=jsonT(file.Read("grm/dealers/"..fname,"DATA"));if old and old.pos then local vehicles={};for group,listRows in pairs(old.vehicles or{})do for _,v in pairs(listRows)do vehicles[#vehicles+1]={class=v.class,name=v.name,price=v.price or 0,category="Legacy",faction=group~="__global"and group~="__nofaction"and group or"",service=group~="__global"and group~="__nofaction"}end end;records[#records+1]={id=fname:gsub("%.json$",""),name=old.name,model=old.model,pos=vd(old.pos),ang=ad(old.angles or Angle()),hasSpawn=old.hasCustomSpawn==true,spawnPos=vd(old.spawnPos or old.pos),spawnAng=ad(old.spawnAngle or old.angles or Angle()),vehicles=vehicles}end end
  if #records>0 then saveDealers(records);print("[GRM VehicleDealer] migrated legacy dealers: "..#records)end
 end
 local function nearestDealer(ply,max)local best,dist=nil,(max or 400)^2;for _,d in ipairs(ents.FindByClass("sent_vehicle_dealer"))do local dd=ply:GetPos():DistToSqr(d:GetPos());if dd<dist then best,dist=d,dd end end;return best end
 hook.Add("PlayerSayTransform","GRM_VD_GarageCommand",function(ply,pack)if not istable(pack)or not isstring(pack[1])then return end;local c=string.lower(string.Trim(pack[1]));if c~="/garage"and c~="!garage"and c~="/гараж"then return end;local d=nearestDealer(ply,450);if IsValid(d)then VD.Push(ply,d)elseif GRM.Notify then GRM.Notify(ply,"Подойдите к дилеру транспорта",255,160,90)end;pack[1]="";pack.SkipPlayerSay=true end)
 concommand.Add("grm_garage",function(ply)local d=IsValid(ply)and nearestDealer(ply,450);if IsValid(d)then VD.Push(ply,d)end end)
 grmBootStart("GRM_VD_Load","normal",function()timer.Simple(1.5,function()migrateLegacyDealers();VD.LoadDealers()end)end);hook.Add("PostCleanupMap","GRM_VD_Cleanup",function()timer.Simple(.8,VD.LoadDealers)end)
 function VD.SaveAll()local a,b=VD.SaveAllDealers();local c=saveGarage();return a and c,b end;function VD.LoadAll()loadGarage();return VD.LoadDealers()end
 print("[GRM VehicleDealer] server v"..VD.Version.." loaded")
end
