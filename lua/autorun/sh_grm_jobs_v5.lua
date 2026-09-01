--[[ GRM Jobs v5.2: живая топология мусора, сверка маршрута и выгрузка на полигоне.
     v1.1.0: кузов 3 пакета (конфиг), полигон принимает ТОЛЬКО полный рейс 3/3.
     v1.2.0: физическая мусорка стала НЕОБЯЗАТЕЛЬНОЙ — маршрут строится по точкам,
             сверка больше не переставляет уже выстроенный рейс, сбор без
             контейнера идёт клавишей G прямо на точке. ]]
if SERVER then AddCSLuaFile()end
GRM=GRM or{};GRM.Jobs=GRM.Jobs or{};local JB=GRM.Jobs
JB.V5Version="1.2.0";JB.GarbageBindings=JB.GarbageBindings or{};JB.GarbageTrucks=JB.GarbageTrucks or setmetatable({},{__mode="k"})
local NREQ="GRM_JobsV5_StateReq";local NDATA="GRM_JobsV5_StateData"
local function posOf(rec)return Vector(tonumber(rec.pos and rec.pos.x)or 0,tonumber(rec.pos and rec.pos.y)or 0,tonumber(rec.pos and rec.pos.z)or 0)end
local function rootVehicle(ent)
 if not IsValid(ent)then return ent end;local original=ent
 for _=1,3 do local parent=ent.GetParent and ent:GetParent()or nil;if not IsValid(parent)or parent==ent then break end;ent=parent end
 for _,name in ipairs({"BaseVehicle","Vehicle","SimfphysVehicle","VehicleEntity","LVSVehicle"})do local base=ent.GetNWEntity and ent:GetNWEntity(name);if IsValid(base)then return base end;base=original.GetNWEntity and original:GetNWEntity(name);if IsValid(base)then return base end end
 for _,name in ipairs({"BaseVehicle","Vehicle","SimfphysVehicle","LVS"})do local base=ent[name]or original[name];if IsValid(base)then return base end end;return ent
end
if SERVER then
 util.AddNetworkString(NREQ);util.AddNetworkString(NDATA)
 local function notify(p,msg,ok)if not IsValid(p)then return end;if GRM.Notify then GRM.Notify(p,msg,ok==false and 255 or 100,ok==false and 125 or 220,ok==false and 95 or 145)else p:ChatPrint("[Мусоровоз] "..msg)end end
 local function audit(action,actor,target,details)if GRM.Audit and GRM.Audit.Write then GRM.Audit.Write("jobs",action,actor,target or{},details or{})end end
 local function nwString(ent,key,value)value=tostring(value or"");if ent:GetNWString(key,"")~=value then ent:SetNWString(key,value)end end
 local function nwInt(ent,key,value)value=math.floor(tonumber(value)or 0);if ent:GetNWInt(key,-2147483648)~=value then ent:SetNWInt(key,value)end end
 local function nwFloat(ent,key,value)value=tonumber(value)or 0;if math.abs(ent:GetNWFloat(key,-1e30)-value)>.001 then ent:SetNWFloat(key,value)end end
 local function pointMap()
  local all,garbage,dumps={},{},{};for _,rec in ipairs(JB.WorkPoints or{})do all[rec.id]=rec;if rec.type=="garbage"then garbage[#garbage+1]=rec elseif rec.type=="dump"then dumps[#dumps+1]=rec end end;return all,garbage,dumps
 end
 function JB.ResolveGarbageVehicle(veh)return rootVehicle(veh)end
 function JB.GetGarbageLoad(veh)
  if not IsValid(veh)then return 0 end;local root=rootVehicle(veh);return math.max(tonumber(veh.GRM_GarbageLoad)or veh:GetNWInt("GRM_GarbageLoad",0),IsValid(root)and(tonumber(root.GRM_GarbageLoad)or root:GetNWInt("GRM_GarbageLoad",0))or 0)
 end
 function JB.SetGarbageLoad(veh,value)
  if not IsValid(veh)then return nil end;local root=rootVehicle(veh);value=math.max(0,math.floor(tonumber(value)or 0));for _,e in ipairs({veh,root})do if IsValid(e)then e.GRM_GarbageLoad=value;nwInt(e,"GRM_GarbageLoad",value)end end;return IsValid(root)and root or veh
 end
 function JB.MarkGarbageTruck(veh,ply,j,preserveState)
  if not IsValid(veh)then return end;local source=veh;local load=JB.GetGarbageLoad(source);veh=JB.SetGarbageLoad(source,load);if not IsValid(veh)then return end;JB.GarbageTrucks[veh]=true;nwInt(veh,"GRM_GarbageCapacity",tonumber(JB.WorkConfig and JB.WorkConfig.garbageCapacity)or 3);if not preserveState then nwString(veh,"GRM_GarbageState","collecting")end;if IsValid(ply)then veh._grmGarbageDriver=ply;if veh:GetNWEntity("GRM_GarbageDriverEntity")~=ply then veh:SetNWEntity("GRM_GarbageDriverEntity",ply)end;nwString(veh,"GRM_GarbageDriver",ply:GetNWString("GRM_RPName",ply:Nick()))end
 end
 --[[ ВОССТАНОВЛЕНИЕ ГРУЗА ПОСЛЕ ПЕРЕЗАПУСКА СЕРВЕРА.

      Пакеты в кузове живут на энтити (veh.GRM_GarbageLoad + NW), а машина
      после рестарта — новая и пустая. Сам рейс при этом сохраняется на диск
      вместе со счётчиком garbageCollected.

      Без восстановления получался тупик: в прогрессе «собрано 3/3», кузов
      пустой, а полигон принимает только полный рейс — ни доехать, ни сдать,
      только провалить и потерять время.

      Правило простое: в кузове должно быть НЕ МЕНЬШЕ, чем помнит рейс.
      Берём максимум фактического и сохранённого, поэтому повторные вызовы
      ничего не «надувают», а реально догруженный сверх счётчика мусор не
      затирается. ]]
 function JB.RestoreGarbageLoad(ply,j,veh)
  if not istable(j) or j.tplId~="garbage" then return end
  if not IsValid(veh) then return end
  local saved=math.max(0,math.floor(tonumber(j.garbageCollected) or 0))
  if saved<=0 then return end
  local cap=math.max(0,math.floor(tonumber(JB.WorkConfig and JB.WorkConfig.garbageCapacity) or saved))
  if cap>0 and saved>cap then saved=cap end
  local actual=JB.GetGarbageLoad(veh)
  if actual>=saved then return end                 -- уже не меньше — не трогаем
  local root=JB.SetGarbageLoad(veh,saved) or veh
  JB.MarkGarbageTruck(root,ply,j,true)
  if IsValid(ply) and GRM.Notify then
   GRM.Notify(ply,("Груз рейса восстановлен: %d пакет(ов) в кузове."):format(saved),120,220,255)
  end
  audit("garbage.restore",ply,{vehicle=IsValid(root) and root:EntIndex() or 0},{load=saved,was=actual})
  return saved
 end
 --[[ Сел за руль мусоровоза со своим рейсом — груз возвращается сам.
      Игроку не нужно знать, что сервер перезапускался. ]]
 hook.Add("PlayerEnteredVehicle","GRM_Garbage_RestoreLoad",function(ply,seat)
  local j=JB.GetActiveJob and JB.GetActiveJob(ply)
  if not(istable(j) and j.tplId=="garbage") then return end
  local veh=rootVehicle(seat)
  if not IsValid(veh) then return end
  if JB.IsVehicleClassAllowed and not JB.IsVehicleClassAllowed(veh,"garbage") then return end
  JB.RestoreGarbageLoad(ply,j,veh)
 end)
 local function binState(bin)local now=CurTime();if(tonumber(bin._grmGarbageSearchingUntil)or 0)>now then return"searching"end;return bin:GetReadyAt()>now and"cooldown"or"ready"end
 local function bindTopology()
  local all,points,dumps=pointMap();local bins=ents.FindByClass("grm_garbage_bin");local claimed,bindings,boundRec={},{},{};local radius=tonumber(JB.WorkConfig and JB.WorkConfig.garbageBindRadius)or 500
  -- Привязка «точка ↔ мусорка» глобально жадная по расстоянию: раньше первая
  -- по списку точка забирала мусорку, которая физически ближе к следующей, и
  -- та оставалась без контейнера (маршрут «то есть, то нет»).
  local pairsList={}
  for _,rec in ipairs(points)do local rp=posOf(rec);for _,bin in ipairs(bins)do if IsValid(bin)then local d=rp:DistToSqr(bin:GetPos());if d<=radius*radius then pairsList[#pairsList+1]={rec=rec,bin=bin,d=d}end end end end
  table.sort(pairsList,function(a,b)if a.d==b.d then return tostring(a.rec.id)<tostring(b.rec.id)end;return a.d<b.d end)
  for _,rec in ipairs(points)do rec._grmGarbageBin=nil end
  for _,pair in ipairs(pairsList)do
   if not claimed[pair.bin]and not bindings[pair.rec.id]then claimed[pair.bin]=true;boundRec[pair.bin]=pair.rec;bindings[pair.rec.id]=pair.bin;pair.rec._grmGarbageBin=pair.bin end
  end
  for _,bin in ipairs(bins)do if IsValid(bin)then local rec=boundRec[bin];if rec then nwString(bin,"GRM_GarbagePointID",rec.id);nwString(bin,"GRM_GarbagePointName",rec.name);nwString(bin,"GRM_GarbageState",binState(bin))else nwString(bin,"GRM_GarbagePointID","");nwString(bin,"GRM_GarbagePointName","");nwString(bin,"GRM_GarbageState","unbound")end end end
  JB.GarbageBindings=bindings;JB.GarbageTopology={all=all,points=points,dumps=dumps,bins=bins,updated=CurTime()};return all,points,dumps
 end
 local function nearestUnused(points,want,used)
  local wp=want and Vector(tonumber(want.x)or 0,tonumber(want.y)or 0,tonumber(want.z)or 0)or nil;local best,bestD=nil,math.huge
  for _,rec in ipairs(points)do if not used[rec.id]then local d=wp and wp:DistToSqr(posOf(rec))or 0;if d<bestD then best,bestD=rec,d end end end;return best
 end
 --[[ ФИКС 19.08 (заказ владельца: «сбивает маршрут, хотя он уже выстроен»).
      Раньше сверка переписывала точку рейса, как только у неё пропадала
      привязка к физической мусорке (её могла «увести» соседняя точка, мусорку
      могло снести уборкой карты на секунду). Маршрут прыгал прямо во время
      рейса. Теперь точка меняется ТОЛЬКО если сама запись точки удалена из
      конфигурации карты; отсутствие мусорки маршрут не ломает. ]]
 local function reconcileActive(all,points,dumps)
  local changed=false
  for _,j in pairs(JB.Active or{})do if istable(j)and j.tplId=="garbage"then
   j.points=istable(j.points)and j.points or{};j.pointNames=istable(j.pointNames)and j.pointNames or{}
   local ids=istable(j.garbagePointIDs)and j.garbagePointIDs or{};local collectCount=math.max(0,#j.points-1)
   if#ids==0 then local inferred={};for i=1,collectCount do local rec=nearestUnused(points,j.points[i],inferred);ids[i]=rec and rec.id or"";if rec then inferred[rec.id]=true end end;j.garbagePointIDs=ids;changed=true end
   local used={};j.routeState="ready";j.routeBinsMissing=0
   for i=1,collectCount do
    local id=ids[i];local rec=all[id]
    if not rec then rec=nearestUnused(points,(j.points or{})[i],used);ids[i]=rec and rec.id or"";changed=true end
    if rec then
     used[rec.id]=true
     local px,py,pz=math.floor(tonumber(rec.pos.x)or 0),math.floor(tonumber(rec.pos.y)or 0),math.floor(tonumber(rec.pos.z)or 0)
     local old=j.points[i]or{}
     if math.floor(tonumber(old.x)or 0)~=px or math.floor(tonumber(old.y)or 0)~=py or math.floor(tonumber(old.z)or 0)~=pz then changed=true end
     j.points[i]={x=rec.pos.x,y=rec.pos.y,z=rec.pos.z};j.pointNames[i]=rec.name
     if not JB.GarbageBindings[rec.id]then j.routeBinsMissing=j.routeBinsMissing+1 end
    else
     j.routeState="missing_point"
    end
   end
   local dump=all[j.garbageDumpID];if not(dump and dump.type=="dump")then dump=dumps[1];j.garbageDumpID=dump and dump.id or"";changed=true end
   if dump then local n=#j.points;j.points[n]={x=dump.pos.x,y=dump.pos.y,z=dump.pos.z};j.pointNames[n]=dump.name else j.routeState="missing_dump"end
   local parts={j.routeState,tostring(j.garbageDumpID or"")};for i,id in ipairs(ids)do local p=j.points[i]or{};parts[#parts+1]=tostring(id)..":"..math.floor(tonumber(p.x)or 0)..":"..math.floor(tonumber(p.y)or 0)..":"..math.floor(tonumber(p.z)or 0)end;local sig=table.concat(parts,"|");if j._garbageTopologySignature~=sig then j._garbageTopologySignature=sig;j._garbageTopologyChanged=true;changed=true end
  end end
  return changed
 end
 function JB.RefreshGarbageTopology(reason)
  if JB._garbageRefreshing then return JB.GarbageTopology end;JB._garbageRefreshing=true;local all,points,dumps=bindTopology();local changed=reconcileActive(all,points,dumps);JB._garbageRefreshing=false
  if changed then if JB.SaveActive then JB.SaveActive("garbage topology "..tostring(reason or"refresh"))end;for _,ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll())do local j=JB.GetActiveJob and JB.GetActiveJob(ply);if j and j._garbageTopologyChanged then j._garbageTopologyChanged=nil;if JB.PushTracker then JB.PushTracker(ply)end;if JB.PushMyState then JB.PushMyState(ply)end end end end
  return JB.GarbageTopology
 end
 local oldRoute=JB.GetRoutePoints
 --[[ ФИКС 19.08 (заказ владельца: «пишет, что нет маршрута, хотя точки стоят»).
      Раньше маршрут строился ТОЛЬКО из тех точек сбора, к которым нашлась
      физическая мусорка grm_garbage_bin в радиусе связи. Нет мусорки (не
      заспавнена, снесена уборкой карты, стоит дальше радиуса, или две точки
      претендуют на одну мусорку) — точка выпадала, а при нуле точек биржа
      писала «Нет связанных точек сбора». Теперь мусорка — ДОПОЛНЕНИЕ к точке,
      а не условие её существования: маршрут строится по самим точкам. ]]
 function JB.GetRoutePoints(kind)
  if kind~="garbage"then return oldRoute and oldRoute(kind)end;JB.RefreshGarbageTopology("route request");local source=oldRoute and oldRoute(kind)or{};local out={};for _,obj in ipairs(source or{})do if obj._grmJobPoint then out[#out+1]=obj end end;return#out>0 and out or nil
 end
 -- Мусорка, обслуживающая точку маршрута: сначала привязанная, потом любая
 -- ближайшая в радиусе связи (её мог «увести» соседний контейнер).
 function JB.BinForPoint(id,pos)
  local bin=id and JB.GarbageBindings[id];if IsValid(bin)then return bin end
  if not pos then return nil end
  local radius=tonumber(JB.WorkConfig and JB.WorkConfig.garbageBindRadius)or 500;local best,bestD=nil,radius*radius
  for _,b in ipairs(ents.FindByClass("grm_garbage_bin"))do if IsValid(b)then local d=pos:DistToSqr(b:GetPos());if d<bestD then best,bestD=b,d end end end
  return best
 end
 local oldSearch=JB.SearchGarbageBin
 function JB.SearchGarbageBin(ply,bin)
  if not(IsValid(ply)and IsValid(bin))then return end;JB.RefreshGarbageTopology("bin use");local j=JB.GetActiveJob and JB.GetActiveJob(ply);if not(istable(j)and j.tplId=="garbage")then notify(ply,"Сначала возьмите работу мусоровоза.",false)return end
  local idx=tonumber(j.pointIndex)or 1;if idx>=#(j.points or{})then notify(ply,"Сейчас нужно ехать на свалку.",false)return end
  -- Строгую сверку «мусорка обязана быть привязана именно к этой точке»
  -- заменяем на дистанцию до текущей точки (её считает v4): привязка живёт
  -- на сервере и может слететь, а игрок стоит у правильного контейнера.
  if oldSearch then return oldSearch(ply,bin)end
 end
 --[[ Сбор без физической мусорки (заказ владельца 19.08): если у точки
      маршрута контейнера нет (не поставили/снесло), рейс всё равно должен
      идти — пакет собирается на самой точке клавишей G. ]]
 function JB.CollectAtPoint(ply)
  if not IsValid(ply)then return end
  local j=JB.GetActiveJob and JB.GetActiveJob(ply);if not(istable(j)and j.tplId=="garbage")then return end
  if ply:InVehicle()then notify(ply,"Выйдите из транспорта.",false)return end
  if IsValid(ply:GetNWEntity("GRM_GarbageBox"))then return end
  if(ply._grmGarbageSearch or 0)>CurTime()then return end
  JB.RefreshGarbageTopology("collect at point")
  local pts=j.points or{};local idx=tonumber(j.pointIndex)or 1
  if idx>=#pts then notify(ply,"Сейчас нужно ехать на свалку.",false)return end
  local g=pts[idx];if not istable(g)then return end
  local gv=Vector(tonumber(g.x)or 0,tonumber(g.y)or 0,tonumber(g.z)or 0)
  local id=istable(j.garbagePointIDs)and j.garbagePointIDs[idx]or""
  local bin=JB.BinForPoint(id,gv)
  if IsValid(bin)then
   if ply:GetPos():DistToSqr(bin:GetPos())<=200*200 then return JB.SearchGarbageBin(ply,bin)end
   notify(ply,"Подойдите к мусорке на текущей точке маршрута.",false)return
  end
  if ply:GetPos():DistToSqr(gv)>250*250 then notify(ply,"Подойдите к точке маршрута — контейнера здесь нет, отходы собираются на месте.",false)return end
  local duration=tonumber(JB.WorkConfig and JB.WorkConfig.garbageSearchTime)or 2.5
  ply._grmGarbageSearch=CurTime()+duration;ply:SetNWBool("GRM_SearchingGarbage",true)
  notify(ply,"Контейнера на точке нет — собираем отходы вручную...",true)
  timer.Simple(duration,function()
   if not IsValid(ply)then return end
   ply:SetNWBool("GRM_SearchingGarbage",false)
   if IsValid(ply:GetNWEntity("GRM_GarbageBox"))then return end
   local cur=JB.GetActiveJob and JB.GetActiveJob(ply);if not(istable(cur)and cur.tplId=="garbage")then return end
   if(tonumber(cur.pointIndex)or 1)~=idx then return end
   if ply:GetPos():DistToSqr(gv)>300*300 then return end
   local box=ents.Create("grm_garbage_box");if not IsValid(box)then return end
   box:SetPos(ply:GetPos());box:SetSourcePointID(tostring(idx));box:Spawn();box:Activate();box:AttachTo(ply)
   notify(ply,"Пакет собран. Поднесите его сзади к мусоровозу и нажмите G.",true)
  end)
 end
 local function unloadTruckFor(ply,seat)
  local direct=rootVehicle(seat);if IsValid(direct)and JB.GetGarbageLoad(direct)>0 then return direct end
  local best,bestD=nil,650*650;for veh in pairs(JB.GarbageTrucks)do if IsValid(veh)and JB.GetGarbageLoad(veh)>0 then local owner=veh._grmGarbageDriver or(veh.GetNWEntity and veh:GetNWEntity("GRM_GarbageDriverEntity"));if owner==ply then local d=IsValid(direct)and direct:GetPos():DistToSqr(veh:GetPos())or 0;if d<bestD then best,bestD=veh,d end end else JB.GarbageTrucks[veh]=nil end end;return best or direct
 end
 function JB.GetPlayerGarbageTruck(ply)return IsValid(ply)and unloadTruckFor(ply,ply:GetVehicle())or nil end
 local function clearUnload(ply,j,veh)
  j.garbageUnloadAt=nil;j.garbageUnloadStart=nil;if IsValid(ply)then ply:SetNWBool("GRM_GarbageUnloading",false);ply:SetNWFloat("GRM_GarbageUnloadStart",0);ply:SetNWFloat("GRM_GarbageUnloadEnd",0);ply:SetNWEntity("GRM_GarbageUnloadTruck",NULL)end;if IsValid(veh)then nwFloat(veh,"GRM_GarbageUnloadAt",0)end
 end
 function JB.TickGarbageDump(ply,j,seat,goal,rad)
  if j.routeState=="missing_dump"then if(j._garbageConfigHintAt or 0)<CurTime()then j._garbageConfigHintAt=CurTime()+10;notify(ply,"Свалка не настроена. Сообщите администрации.",false)end;clearUnload(ply,j,nil)return end
  local veh=unloadTruckFor(ply,seat);if not IsValid(veh)then clearUnload(ply,j,nil)return end;JB.MarkGarbageTruck(veh,ply,j,true);local load=JB.GetGarbageLoad(veh)
  if load<=0 then clearUnload(ply,j,veh);nwString(veh,"GRM_GarbageState","empty");if(j._garbageEmptyHintAt or 0)<CurTime()then j._garbageEmptyHintAt=CurTime()+8;notify(ply,"В машине не найден загруженный мусор. Сначала загрузите пакеты клавишей G.",false)end return end
  -- Полигон принимает только ПОЛНЫЙ рейс: собери 3/3 (все контейнеры маршрута),
  -- иначе выгрузка не начинается. Деградировавший маршрут (нет мусорки/свалки
  -- на карте) исключение — там игрока нельзя запирать.
  local required=math.max(0,#(j.points or{})-1)
  local capacity=tonumber(JB.WorkConfig and JB.WorkConfig.garbageCapacity)or required
  if capacity>0 and required>capacity then required=capacity end
  if j.routeState=="ready" and required>0 and load<required then
   clearUnload(ply,j,veh);nwString(veh,"GRM_GarbageState","collecting")
   if(j._garbagePartialHintAt or 0)<CurTime()then j._garbagePartialHintAt=CurTime()+8;notify(ply,("Полигон принимает только полный рейс: собрано %d/%d. Доберите оставшиеся контейнеры."):format(load,required),false)end
   return
  end
  local radius=math.max(tonumber(rad)or 170,tonumber(JB.WorkConfig and JB.WorkConfig.garbageDumpRadius)or 320);local inside=veh:GetPos():DistToSqr(goal)<radius*radius;local actualDriver=veh.GetDriver and veh:GetDriver()or nil;local driver=not IsValid(actualDriver)or actualDriver==ply or veh._grmGarbageDriver==ply;local stopped=not veh.GetVelocity or veh:GetVelocity():Length2D()<80
  if not inside or not driver or not stopped then if j.garbageUnloadAt then notify(ply,"Выгрузка прервана: остановите мусоровоз в зоне свалки.",false)end;clearUnload(ply,j,veh);nwString(veh,"GRM_GarbageState","to_dump");return end
  local duration=tonumber(JB.WorkConfig and JB.WorkConfig.garbageUnloadTime)or 4;if not j.garbageUnloadAt then j.garbageUnloadStart=CurTime();j.garbageUnloadAt=CurTime()+duration;nwString(veh,"GRM_GarbageState","unloading");nwFloat(veh,"GRM_GarbageUnloadAt",j.garbageUnloadAt);ply:SetNWBool("GRM_GarbageUnloading",true);ply:SetNWFloat("GRM_GarbageUnloadStart",j.garbageUnloadStart);ply:SetNWFloat("GRM_GarbageUnloadEnd",j.garbageUnloadAt);ply:SetNWEntity("GRM_GarbageUnloadTruck",veh);notify(ply,"Выгрузка началась. Стойте на месте "..duration.." сек.",true);JB.PushMyState(ply);return end
  if CurTime()<j.garbageUnloadAt then return end;j.garbageDelivered=load;clearUnload(ply,j,veh);JB.SetGarbageLoad(veh,0);nwString(veh,"GRM_GarbageState","empty");audit("garbage.unload",ply,{vehicle=veh:EntIndex(),dumpID=j.garbageDumpID},{load=load});notify(ply,"Выгрузка завершена: "..load.." коробок. Маршрут закрыт.",true);JB.Complete(ply)
 end
 hook.Add("PlayerLeaveVehicle","GRM_Garbage_UnloadLeave",function(ply,seat)local j=JB.GetActiveJob and JB.GetActiveJob(ply);if j and j.garbageUnloadAt then local veh=unloadTruckFor(ply,seat);clearUnload(ply,j,veh);if IsValid(veh)then nwString(veh,"GRM_GarbageState","to_dump")end;notify(ply,"Выгрузка прервана: вы покинули водительское место.",false)end end)
 hook.Add("PlayerDeath","GRM_Garbage_UnloadDeath",function(ply)local j=JB.GetActiveJob and JB.GetActiveJob(ply);if j and j.garbageUnloadAt then clearUnload(ply,j,nil)end end)
 hook.Add("GRM_Jobs_Failed","GRM_Garbage_UnloadFail",function(ply,j)if j and j.tplId=="garbage"then clearUnload(ply,j,nil)end end)
 function JB.GarbageStateSnapshot()
  JB.RefreshGarbageTopology("state");local t=JB.GarbageTopology or{};local rows={};for _,rec in ipairs(t.points or{})do local bin=JB.GarbageBindings[rec.id];rows[#rows+1]={kind="collection",id=rec.id,name=rec.name,bound=true,hasBin=IsValid(bin),bin=IsValid(bin)and bin:EntIndex()or 0,state=IsValid(bin)and bin:GetNWString("GRM_GarbageState","ready")or"manual",readyIn=IsValid(bin)and math.max(0,math.ceil(bin:GetReadyAt()-CurTime()))or 0,distance=IsValid(bin)and math.floor(posOf(rec):Distance(bin:GetPos()))or 0}end;for _,rec in ipairs(t.dumps or{})do rows[#rows+1]={kind="dump",id=rec.id,name=rec.name,bound=true,state="ready"}end
  local trucks={};for veh in pairs(JB.GarbageTrucks)do if IsValid(veh)then trucks[#trucks+1]={ent=veh:EntIndex(),load=tonumber(veh.GRM_GarbageLoad)or veh:GetNWInt("GRM_GarbageLoad",0),capacity=veh:GetNWInt("GRM_GarbageCapacity",tonumber(JB.WorkConfig and JB.WorkConfig.garbageCapacity)or 3),state=veh:GetNWString("GRM_GarbageState","idle"),driver=veh:GetNWString("GRM_GarbageDriver","")}else JB.GarbageTrucks[veh]=nil end end
  return{updated=os.time(),rows=rows,trucks=trucks,summary={points=#(t.points or{}),bound=table.Count(JB.GarbageBindings),bins=#(t.bins or{}),dumps=#(t.dumps or{})}}
 end
 net.Receive(NREQ,function(bits,ply)if not(IsValid(ply)and ply:IsSuperAdmin())then return end;if GRM.Net and not GRM.Net.Guard(ply,"jobs.garbage.state",{rate=.5,burst=3,maxBits=64},{bits=bits})then return end;net.Start(NDATA);net.WriteTable(JB.GarbageStateSnapshot());net.Send(ply)end)
 timer.Create("GRM_Garbage_Topology",10,0,function()JB.RefreshGarbageTopology("fallback auto")end)
if GRM.Boot and GRM.Boot.Task then
    GRM.Boot.Task("jobs.garbage", "late", function() JB.RefreshGarbageTopology("map init") end, { label = "Мусоровоз: топология контейнеров" })
else
 hook.Add("InitPostEntity","GRM_Garbage_TopologyInit",function()timer.Simple(2,function()JB.RefreshGarbageTopology("map init")end)end)
end
 hook.Add("PostCleanupMap","GRM_Garbage_TopologyCleanup",function()timer.Simple(1,function()JB.RefreshGarbageTopology("cleanup")end)end)
 hook.Add("OnEntityCreated","GRM_Garbage_TopologyCreate",function(e)timer.Simple(.2,function()if IsValid(e)and e:GetClass()=="grm_garbage_bin"then JB.RefreshGarbageTopology("bin created")end end)end)
 hook.Add("EntityRemoved","GRM_Garbage_TopologyRemove",function(e)if e:GetClass()=="grm_garbage_bin"then timer.Simple(0,function()JB.RefreshGarbageTopology("bin removed")end)end end)
else
 surface.CreateFont("GRMGarbageTitle",{font="Roboto",size=23,weight=900,extended=true});surface.CreateFont("GRMGarbageText",{font="Roboto",size=15,weight=600,extended=true})
 local stateNames={ready="готова",searching="идёт сбор",cooldown="восстановление",manual="сбор на точке",unbound="без контейнера",collecting="сбор",to_dump="к свалке",unloading="выгрузка",empty="пусто",idle="ожидание"}
 local frame,rowsPanel,lastData
 local function request()net.Start(NREQ);net.SendToServer()end
 local function rebuild(data)
  lastData=data;if not IsValid(rowsPanel)then return end;rowsPanel:Clear();local s=data.summary or{};local head=vgui.Create("DPanel",rowsPanel);head:Dock(TOP);head:SetTall(58);head:DockMargin(0,0,0,8);head.Paint=function(_,w,h)draw.RoundedBox(7,0,0,w,h,Color(20,34,48));draw.SimpleText(("ТОЧКИ %d • СВЯЗАНО %d • МУСОРКИ %d • СВАЛКИ %d"):format(s.points or 0,s.bound or 0,s.bins or 0,s.dumps or 0),"GRMGarbageTitle",16,h/2,color_white,TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER)end
  for _,r in ipairs(data.rows or{})do local p=vgui.Create("DPanel",rowsPanel);p:Dock(TOP);p:SetTall(62);p:DockMargin(0,0,0,6);p.Paint=function(_,w,h)local good=r.bound;draw.RoundedBox(6,0,0,w,h,Color(24,36,51));draw.RoundedBox(2,0,0,5,h,good and Color(65,205,135)or Color(235,85,85));draw.SimpleText((r.kind=="dump"and"СВАЛКА • "or"СБОР • ")..tostring(r.name),"GRMGarbageText",16,19,color_white);local state=r.kind=="dump"and"готова к выгрузке"or(r.hasBin and((r.state=="cooldown")and("восстановление "..r.readyIn.." сек")or(r.state=="searching"and("идёт сбор • мусорка #"..r.bin)or("мусорка #"..r.bin.." • готова • связь "..r.distance.." юн")))or"без контейнера — сбор на точке клавишей G");draw.SimpleText(state,"GRMGarbageText",16,43,good and Color(145,220,175)or Color(245,130,130))end end
  for _,r in ipairs(data.trucks or{})do local p=vgui.Create("DPanel",rowsPanel);p:Dock(TOP);p:SetTall(54);p:DockMargin(0,4,0,4);p.Paint=function(_,w,h)draw.RoundedBox(6,0,0,w,h,Color(37,42,58));draw.SimpleText(("МУСОРОВОЗ #%d • %d/%d • %s • %s"):format(r.ent or 0,r.load or 0,r.capacity or 0,stateNames[r.state]or r.state or"ожидание",r.driver or""),"GRMGarbageText",16,h/2,Color(235,205,115),TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER)end end
 end
 function JB.OpenGarbageState()
  if IsValid(frame)then frame:MakePopup();request();return end;frame=vgui.Create("DFrame");frame:SetSize(math.min(1000,ScrW()-80),math.min(760,ScrH()-80));frame:Center();frame:MakePopup();frame:SetTitle("МУСОРОВОЗ • ЖИВАЯ СХЕМА И СОСТОЯНИЕ");frame:SetDeleteOnClose(true);if GRM.UI then GRM.UI.Track("jobs.garbage.state",frame)end;rowsPanel=vgui.Create("DScrollPanel",frame);rowsPanel:Dock(FILL);rowsPanel:DockMargin(12,10,12,12);frame.OnRemove=function()frame=nil;rowsPanel=nil end;request()
 end
 concommand.Add("grm_garbage_status",JB.OpenGarbageState);net.Receive(NDATA,function()local data=net.ReadTable()or{};if not IsValid(frame)then JB.OpenGarbageState()end;rebuild(data)end)
 timer.Create("GRM_Garbage_StateRefresh",3,0,function()if IsValid(frame)then request()end end)
 hook.Add("HUDPaint","GRM_Garbage_UnloadProgress",function()local p=LocalPlayer();if not(IsValid(p)and p:GetNWBool("GRM_GarbageUnloading",false))then return end;local started,finish=p:GetNWFloat("GRM_GarbageUnloadStart",0),p:GetNWFloat("GRM_GarbageUnloadEnd",0);if finish<=started then return end;local frac=math.Clamp((CurTime()-started)/(finish-started),0,1);local w,h=520,82;local x,y=ScrW()/2-w/2,ScrH()-235;draw.RoundedBox(10,x,y,w,h,Color(10,17,26,242));draw.SimpleText("ВЫГРУЗКА МУСОРОВОЗА","GRMGarbageTitle",x+18,y+20,color_white,TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER);draw.SimpleText(math.max(0,math.ceil(finish-CurTime())).." сек.","GRMGarbageText",x+w-18,y+20,Color(235,205,110),TEXT_ALIGN_RIGHT,TEXT_ALIGN_CENTER);draw.RoundedBox(5,x+18,y+48,w-36,18,Color(35,48,62));draw.RoundedBox(5,x+18,y+48,(w-36)*frac,18,Color(65,205,135));draw.SimpleText(math.floor(frac*100).."%","DermaDefaultBold",x+w/2,y+57,color_white,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)end)
 hook.Add("HUDPaint","GRM_Garbage_TruckState",function()local p=LocalPlayer();if not(IsValid(p)and p:InVehicle())then return end;local v=rootVehicle(p:GetVehicle());if not IsValid(v)then return end;local cap=v:GetNWInt("GRM_GarbageCapacity",0);if cap<=0 then return end;local load=v:GetNWInt("GRM_GarbageLoad",0);draw.RoundedBox(7,ScrW()-270,ScrH()-145,250,54,Color(12,20,30,225));draw.SimpleText("МУСОРОВОЗ  "..load.."/"..cap,"GRMGarbageText",ScrW()-250,ScrH()-125,Color(235,210,120));local state=v:GetNWString("GRM_GarbageState","collecting");draw.SimpleText(stateNames[state]or state,"DermaDefault",ScrW()-250,ScrH()-106,Color(170,195,215))end)
end
print("[GRM Jobs v5] garbage topology + dump state loaded")
