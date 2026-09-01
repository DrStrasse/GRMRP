--[[ GRM Jobs v4: physical garbage cycle and live player taxi dispatch. ]]
if SERVER then AddCSLuaFile()end
GRM=GRM or{};GRM.Jobs=GRM.Jobs or{};local JB=GRM.Jobs
JB.V4Version="1.0.0";JB.TaxiRequests=JB.TaxiRequests or{};JB.NextTaxiRequest=JB.NextTaxiRequest or 1
local NTAXI="GRM_JobsV4_Taxi";local NTAXIACT="GRM_JobsV4_TaxiAct";local NGARBAGE="GRM_JobsV4_GarbageLoad"
local function key(p)return JB.CharacterKey and JB.CharacterKey(p)or(GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(p))or(IsValid(p)and p:SteamID64()..":char1"or tostring(p or""))end
local function active(p)return JB.GetActiveJob and JB.GetActiveJob(p)end
local function online(characterKey)for _,p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll())do if key(p)==characterKey then return p end end end
function JB.TaxiStatus(ply)local k=key(ply);for _,r in pairs(JB.TaxiRequests)do if r.callerKey==k and r.status~="completed"and r.status~="cancelled"then return{id=r.id,status=r.status,driverName=r.driverName or"",fare=r.fare or 0,created=r.created,expires=r.expires}end end;return nil end
if SERVER then
 util.AddNetworkString(NTAXI);util.AddNetworkString(NTAXIACT);util.AddNetworkString(NGARBAGE)
 local function notify(p,msg,ok)if not IsValid(p)then return end;if GRM.Notify then GRM.Notify(p,msg,ok==false and 255 or 100,ok==false and 135 or 220,ok==false and 105 or 140)else p:ChatPrint("[Работы] "..msg)end end
 local function pushTaxi(p)if IsValid(p)and GRM.Mobile and GRM.Mobile.PushData then GRM.Mobile.PushData(p,"taxi")end end
 local function saveJobs(why)if JB.SaveActive then JB.SaveActive(why)end end
 local function audit(action,actor,target,details)if GRM.Audit and GRM.Audit.Write then GRM.Audit.Write("jobs",action,actor,target or{},details or{})end end
 local function taxiDrivers()local out={};for _,p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll())do local j=active(p);if istable(j)and j.tplId=="taxi"and j.taxiStandby then out[#out+1]=p end end;return out end
 --[[ ЖИЗНЕННЫЙ ЦИКЛ ЗАКАЗА ТАКСИ.

      waiting  — заказ висит в эфире, любой свободный водитель может взять
      accepted — водитель едет к точке посадки
      arrived  — водитель на месте, ждёт, пока клиент сядет
      riding   — клиент в машине, едут к точке назначения
      completed— доехали, деньги перешли водителю
      cancelled— отменён (заказчиком, водителем, таймаутом или разрывом)

      ДЕНЬГИ БЕРУТСЯ ТОЛЬКО В completed. Раньше оплата списывалась при
      посадке, и заказ там же закрывался: водителю было выгодно немедленно
      высадить клиента, потому что деньги уже получены, а поездки как
      таковой в системе не существовало. Теперь при посадке сумма лишь
      ПРОВЕРЯЕТСЯ (хватает ли наличных), а списывается по прибытии. ]]
 local TAXI_ARRIVE_RADIUS = 180      -- радиус «водитель подъехал к клиенту»
 local TAXI_DROPOFF_RADIUS = 220     -- радиус «доехали до назначения»
 local TAXI_CALL_MAX_DIST = 12000    -- дальше этого заказ водителю не предлагаем
 local TAXI_KEEP_CLOSED = 120        -- сколько секунд держать закрытую заявку

 --- Точка назначения для заказа: случайная из размеченных taxi_dropoff.
 --  Берём самую дальнюю из двух случайных, чтобы поездка была осмысленной,
 --  а не «пять метров за полную таксу».
 local function pickDropoff(fromPos)
  local pts=JB.GetRoutePoints and JB.GetRoutePoints("taxi_dropoff")or nil
  if not istable(pts) or #pts==0 then return nil end
  local best,bestName,bestD=nil,nil,-1
  for _=1,math.min(2,#pts) do
   local obj=pts[math.random(#pts)];local p=obj.GetPos and obj:GetPos()or nil
   if p then
    local d=fromPos and p:DistToSqr(fromPos) or 0
    if d>bestD then best,bestD=p,d;bestName=(obj._grmJobPoint and obj._grmJobPoint.name)or(obj.GetNWString and obj:GetNWString("GRM_JobZoneName","")) end
   end
  end
  if not best then return nil end
  return {x=best.x,y=best.y,z=best.z},tostring(bestName or "Точка назначения")
 end

 --- Снять заказ и вернуть водителя в режим ожидания. Общая концовка для
 --  отмены, таймаута и разрыва связи: раньше это было размазано копипастой.
 local function releaseDriver(r,why)
  local driver=r.driverKey and online(r.driverKey)or nil
  if IsValid(driver) then
   local j=active(driver)
   if j and j.taxiRequestID==r.id then
    j.taxiRequestID=nil;j.stage=0;j.target=driver:GetPos();j.center=j.target
    JB.PushTracker(driver);JB.PushMyState(driver);saveJobs("taxi "..tostring(why or "release"))
   end
  end
  return driver
 end

 function JB.CallTaxi(caller,source)
  if not IsValid(caller)or not caller:IsPlayer()then return false,"Заказчик не найден"end
  if JB.TaxiStatus(caller)then return false,"У вас уже есть активный заказ такси"end
  --[[ Таксист на линии не может быть сам себе клиентом. Без этой проверки
       водитель вызывал такси себе, сам принимал заказ, садился в свою же
       машину — деньги ходили по кругу, а статистика заказов росла. ]]
  local ownJob=active(caller)
  if istable(ownJob)and ownJob.tplId=="taxi"then return false,"Вы сами на смене такси — заказ себе оформить нельзя"end
  local pos=caller:GetPos()
  local dropoff,dropoffName=pickDropoff(pos)
  if not dropoff then return false,"На карте не размечены точки назначения такси. Сообщите администрации."end
  local id=JB.NextTaxiRequest;JB.NextTaxiRequest=id+1
  JB.TaxiRequests[id]={id=id,callerKey=key(caller),callerName=caller:GetNWString("GRM_RPName",caller:Nick()),
   pickup={x=pos.x,y=pos.y,z=pos.z},dropoff=dropoff,dropoffName=dropoffName,
   status="waiting",created=os.time(),expires=os.time()+600,source=tostring(source or"chat")}
  for _,driver in ipairs(taxiDrivers())do notify(driver,"Новый заказ такси от "..JB.TaxiRequests[id].callerName..". Откройте /taxi.",true)end
  notify(caller,"Такси вызвано. Пункт назначения: "..dropoffName..". Ожидайте принятия заказа.",true)
  pushTaxi(caller);audit("taxi.call",caller,{requestID=id},{source=source,dropoff=dropoffName})
  hook.Run("GRM_TaxiCalled",caller,JB.TaxiRequests[id]);return true,id
 end

 function JB.CancelTaxi(caller,reason)
  local st=JB.TaxiStatus(caller);if not st then return false,"Активного заказа нет"end
  local r=JB.TaxiRequests[st.id];r.status="cancelled";r.closedAt=os.time()
  r.cancelReason=tostring(reason or"заказчик отменил")
  --[[ Возврат не нужен: деньги теперь списываются только по прибытии,
       поэтому отмена в пути ничего пассажиру не стоит. Это и есть
       правильный порядок — раньше оплата уходила на посадке и обратно
       не возвращалась ни при каком сценарии. ]]
  local driver=releaseDriver(r,"cancel")
  if IsValid(driver)then notify(driver,"Заказ такси отменён.",false)end
  notify(caller,"Заказ такси отменён.",true);pushTaxi(caller)
  audit("taxi.cancel",caller,{requestID=r.id},{reason=r.cancelReason});return true
 end

 local function requestWire(driver)
  local rows={};local dpos=driver:GetPos()
  for _,r in pairs(JB.TaxiRequests)do
   if r.status=="waiting"then
    local p=Vector(r.pickup.x,r.pickup.y,r.pickup.z);local dist=dpos:Distance(p)
    -- Заказы с другого конца карты не показываем: принять их всё равно
    -- нельзя, а список они засоряют.
    if dist<=TAXI_CALL_MAX_DIST then
     rows[#rows+1]={id=r.id,callerName=r.callerName,distance=math.floor(dist),age=math.max(0,os.time()-r.created),dropoffName=tostring(r.dropoffName or"")}
    end
   end
  end
  table.sort(rows,function(a,b)return a.distance<b.distance end);return rows
 end
 function JB.OpenTaxiDriverMenu(ply)
  local j=active(ply);if not(istable(j)and j.tplId=="taxi"and j.taxiStandby)then notify(ply,"Сначала выйдите на линию через Биржу труда.",false)return end
  net.Start(NTAXI);net.WriteUInt(JB.GetTaxiFare and JB.GetTaxiFare(ply,700)or 700,20);net.WriteUInt(tonumber(JB.WorkConfig and JB.WorkConfig.taxiMin)or 0,20);net.WriteUInt(tonumber(JB.WorkConfig and JB.WorkConfig.taxiMax)or 100000,20);net.WriteTable(requestWire(ply));net.WriteUInt(tonumber(j.taxiRequestID)or 0,24);net.Send(ply)
 end
 --- Водитель берёт заказ. Публичная: её зовёт и меню, и стенд.
 function JB.AcceptTaxi(driver,id)
  local j=active(driver);local r=JB.TaxiRequests[id]
  if not(istable(j)and j.tplId=="taxi"and j.taxiStandby)then return false,"Вы не на линии такси"end
  if j.taxiRequestID then return false,"Сначала завершите текущий заказ"end
  if not r or r.status~="waiting"then return false,"Заказ уже недоступен"end
  if not JB.IsWorkVehicleAllowed(driver,"taxi")then return false,"Сядьте за руль разрешённого автомобиля такси"end
  local caller=online(r.callerKey);if not IsValid(caller)then r.status="cancelled";r.closedAt=os.time();return false,"Заказчик вышел с сервера"end
  if r.callerKey==key(driver)then return false,"Нельзя принять собственный заказ"end
  local fare=JB.GetTaxiFare and JB.GetTaxiFare(driver,700)or 700
  if GRM.HasMoney and not GRM.HasMoney(caller,fare)then return false,"У заказчика недостаточно наличных для вашей таксы"end
  r.status="accepted";r.driverKey=key(driver);r.driverName=driver:GetNWString("GRM_RPName",driver:Nick());r.fare=fare;r.expires=os.time()+600
  j.taxiRequestID=id;j.stage=1;j.target=Vector(r.pickup.x,r.pickup.y,r.pickup.z);j.center=j.target;j.zoneRadius=TAXI_ARRIVE_RADIUS;j.zoneName="Клиент такси: "..r.callerName
  saveJobs("taxi accepted");JB.PushTracker(driver);JB.PushMyState(driver)
  notify(driver,"Заказ принят. Маркер клиента появился на экране.",true)
  notify(caller,"Заказ принял водитель "..r.driverName..". Стоимость: "..fare..". Поедете в: "..tostring(r.dropoffName or"назначение")..".",true)
  pushTaxi(caller);audit("taxi.accept",driver,{requestID=id,callerKey=r.callerKey},{fare=fare});return true
 end
 local acceptTaxi=JB.AcceptTaxi
 net.Receive(NTAXIACT,function(bits,ply)if not IsValid(ply)then return end;if GRM.Net and not GRM.Net.Guard(ply,"jobs.taxi.action",{rate=.25,burst=3,maxBits=4096},{bits=bits})then return end;local op=net.ReadString();if op=="accept"then local ok,msg=acceptTaxi(ply,net.ReadUInt(24));notify(ply,msg,ok);JB.OpenTaxiDriverMenu(ply)elseif op=="refresh"then JB.OpenTaxiDriverMenu(ply)elseif op=="set_fare"then local min=tonumber(JB.WorkConfig and JB.WorkConfig.taxiMin)or 0;local max=tonumber(JB.WorkConfig and JB.WorkConfig.taxiMax)or 100000;JB.TaxiFares=JB.TaxiFares or{};JB.TaxiFares[key(ply)]=math.Clamp(net.ReadUInt(20),min,max);notify(ply,"Такса обновлена: "..JB.TaxiFares[key(ply)],true);JB.OpenTaxiDriverMenu(ply)elseif op=="release"then local j=active(ply);if j and j.taxiRequestID then local r=JB.TaxiRequests[j.taxiRequestID];if r then r.status="waiting";r.driverKey=nil;r.driverName=nil;r.expires=os.time()+600 end;j.taxiRequestID=nil;j.stage=0;JB.PushTracker(ply);saveJobs("taxi released");JB.OpenTaxiDriverMenu(ply)end end end)

 --- Расчёт по завершённой поездке. Единственное место, где ходят деньги.
 local function settleRide(driver,r,passenger)
  local fare=tonumber(r.fare)or 0
  if fare>0 and GRM.HasMoney and not GRM.HasMoney(passenger,fare)then
   -- Денег не хватило на месте (потратил в пути). Заказ закрываем, но
   -- водителя не наказываем молчанием — он должен понимать, что произошло.
   notify(passenger,"Недостаточно наличных для оплаты поездки.",false)
   notify(driver,"Клиент не смог расплатиться. Заказ закрыт без оплаты.",false)
   r.status="completed";r.closedAt=os.time();r.unpaid=true
   audit("taxi.unpaid",driver,{requestID=r.id,callerKey=r.callerKey},{fare=fare})
   return false
  end
  if fare>0 and GRM.TakeMoney then GRM.TakeMoney(passenger,fare,"Поездка на такси")end
  if fare>0 and GRM.GiveMoney then GRM.GiveMoney(driver,fare,"Оплата заказа такси")end
  r.status="completed";r.completed=os.time();r.closedAt=os.time()
  notify(passenger,"Поездка завершена. Оплачено: "..fare..".",true)
  notify(driver,"Клиент доставлен. Получена оплата: "..fare..".",true)
  pushTaxi(passenger);audit("taxi.paid",driver,{requestID=r.id,callerKey=r.callerKey},{fare=fare})
  hook.Run("GRM_TaxiCompleted",passenger,driver,fare,r)
  return true
 end

 function JB.TickTaxiJob(driver,j)
  local id=tonumber(j.taxiRequestID);if not id then return end
  local r=JB.TaxiRequests[id]
  if not r or r.status=="cancelled"or r.status=="completed"then j.taxiRequestID=nil;j.stage=0;JB.PushTracker(driver);return end
  local caller=online(r.callerKey)
  if not IsValid(caller)then
   -- Пассажир вышел с сервера: заказ снимаем, водителя освобождаем.
   r.status="cancelled";r.closedAt=os.time();r.cancelReason="заказчик вышел с сервера"
   j.taxiRequestID=nil;j.stage=0;JB.PushTracker(driver);notify(driver,"Заказчик вышел с сервера. Заказ снят.",false);return
  end
  if r.status=="accepted"and driver:GetPos():DistToSqr(Vector(r.pickup.x,r.pickup.y,r.pickup.z))<=TAXI_ARRIVE_RADIUS*TAXI_ARRIVE_RADIUS then
   r.status="arrived";r.arrivedAt=os.time();r.expires=os.time()+120;j.stage=2;j.center=j.target;JB.PushTracker(driver)
   notify(driver,"Вы прибыли. Дождитесь посадки клиента.",true);notify(caller,"Такси прибыло. Сядьте в автомобиль водителя.",true);pushTaxi(caller);return
  end
  --[[ ГЛАВНЫЙ ЭТАП, КОТОРОГО РАНЬШЕ НЕ БЫЛО: собственно поездка.
       Клиент в машине — ведём к точке назначения и платим по прибытии. ]]
  if r.status=="riding"then
   local dp=r.dropoff;if not istable(dp)then return end
   local goal=Vector(dp.x,dp.y,dp.z)
   if driver:GetPos():DistToSqr(goal)<=TAXI_DROPOFF_RADIUS*TAXI_DROPOFF_RADIUS then
    settleRide(driver,r,caller)
    j.taxiRequestID=nil;j.stage=0;j.target=driver:GetPos();j.center=j.target
    JB.PushTracker(driver);JB.PushMyState(driver);saveJobs("taxi completed")
   end
  end
 end
 local function vehicleRoot(ent)
  if not IsValid(ent)then return ent end;local parent=ent.GetParent and ent:GetParent()or nil;if IsValid(parent)then ent=parent end
  for _,keyName in ipairs({"BaseVehicle","Vehicle","SimfphysVehicle"})do local base=ent.GetNWEntity and ent:GetNWEntity(keyName);if IsValid(base)then return base end end;return ent
 end
 --[[ ПОСАДКА НЕ ЗАКРЫВАЕТ ЗАКАЗ, А НАЧИНАЕТ ПОЕЗДКУ.
      Проверяем платёжеспособность заранее, чтобы водитель не вёз клиента
      через полгорода впустую, но сами деньги трогаем только в settleRide. ]]
 hook.Add("PlayerEnteredVehicle","GRM_Taxi_PassengerEntered",function(passenger,veh)
  local st=JB.TaxiStatus(passenger);if not st then return end
  local r=JB.TaxiRequests[st.id];if not r or r.status~="arrived"then return end
  local driver=online(r.driverKey);if not IsValid(driver)or not driver:InVehicle()or vehicleRoot(veh)~=vehicleRoot(driver:GetVehicle())then return end
  local fare=tonumber(r.fare)or 0
  if fare>0 and GRM.HasMoney and not GRM.HasMoney(passenger,fare)then notify(passenger,"Недостаточно наличных для оплаты такси.",false)return end
  r.status="riding";r.boardedAt=os.time();r.expires=os.time()+1800
  local j=active(driver)
  if j then
   local dp=r.dropoff
   j.stage=2;j.target=Vector(dp.x,dp.y,dp.z);j.center=j.target;j.zoneRadius=TAXI_DROPOFF_RADIUS
   j.zoneName="Назначение: "..tostring(r.dropoffName or"точка")
   JB.PushTracker(driver);JB.PushMyState(driver);saveJobs("taxi riding")
  end
  notify(passenger,"Вы в машине. Пункт назначения: "..tostring(r.dropoffName or"точка")..". Оплата "..fare.." по прибытии.",true)
  notify(driver,"Клиент на борту. Везите в: "..tostring(r.dropoffName or"точка")..".",true)
  pushTaxi(passenger);audit("taxi.board",driver,{requestID=r.id,callerKey=r.callerKey},{fare=fare})
 end)
 --[[ Пассажир вышел до прибытия — поездка прервана, денег никто не платит.
      Водитель возвращается на линию, заказ закрывается. ]]
 hook.Add("PlayerLeaveVehicle","GRM_Taxi_PassengerLeft",function(passenger)
  local st=JB.TaxiStatus(passenger);if not st then return end
  local r=JB.TaxiRequests[st.id];if not r or r.status~="riding"then return end
  r.status="cancelled";r.closedAt=os.time();r.cancelReason="пассажир вышел в пути"
  local driver=releaseDriver(r,"passenger left")
  if IsValid(driver)then notify(driver,"Пассажир вышел, не доехав. Заказ закрыт без оплаты.",false)end
  notify(passenger,"Вы вышли из такси. Поездка не оплачена.",false);pushTaxi(passenger)
  audit("taxi.abort",passenger,{requestID=r.id},{reason=r.cancelReason})
 end)
 --[[ Водитель отключился посреди поездки. Пассажир не должен ничего терять:
      деньги ещё у него (списание только по прибытии), поэтому просто
      снимаем заказ и сообщаем. ]]
 hook.Add("PlayerDisconnected","GRM_Taxi_DriverLeft",function(ply)
  local k=key(ply)
  for _,r in pairs(JB.TaxiRequests)do
   if r.driverKey==k and(r.status=="accepted"or r.status=="arrived"or r.status=="riding")then
    r.status="cancelled";r.closedAt=os.time();r.cancelReason="водитель вышел с сервера"
    local caller=online(r.callerKey)
    if IsValid(caller)then notify(caller,"Водитель отключился. Заказ снят, деньги не списаны.",false);pushTaxi(caller)end
    audit("taxi.driver_left",ply,{requestID=r.id},{})
   elseif r.callerKey==k and(r.status=="waiting"or r.status=="accepted"or r.status=="arrived"or r.status=="riding")then
    r.status="cancelled";r.closedAt=os.time();r.cancelReason="заказчик вышел с сервера"
    local driver=releaseDriver(r,"caller left")
    if IsValid(driver)then notify(driver,"Заказчик вышел с сервера. Заказ снят.",false)end
   end
  end
 end)
 --[[ СВИП: не только помечает просроченные, но и ВЫЧИЩАЕТ закрытые.
      Раньше записи только копились — таблица росла весь аптайм, а
      TaxiStatus и список заказов перебирали её целиком на каждый вызов. ]]
 timer.Create("GRM_Taxi_RequestSweep",5,0,function()
  local now=os.time()
  for id,r in pairs(JB.TaxiRequests)do
   if(r.status=="waiting"or r.status=="accepted"or r.status=="arrived"or r.status=="riding")and(r.expires or 0)<now then
    r.status="cancelled";r.closedAt=now;r.cancelReason=r.cancelReason or"истёк срок заказа"
    local d=releaseDriver(r,"expired")
    if IsValid(d)then notify(d,"Заказ такси истёк.",false)end
    local c=online(r.callerKey);if IsValid(c)then notify(c,"Заказ такси истёк.",false)end
   end
   if(r.status=="completed"or r.status=="cancelled")and((r.closedAt or r.completed or 0)+TAXI_KEEP_CLOSED)<now then
    JB.TaxiRequests[id]=nil
   end
  end
 end)
 local function currentGarbageGoal(j)local idx=tonumber(j.pointIndex)or 1;local g=j.points and j.points[idx];return g,idx end
 function JB.SearchGarbageBin(ply,bin)
  if not(IsValid(ply)and IsValid(bin))then return end;if ply:InVehicle()then notify(ply,"Выйдите из транспорта.",false)return end;if IsValid(ply:GetNWEntity("GRM_GarbageBox"))then notify(ply,"Вы уже несёте коробку с мусором.",false)return end
  local j=active(ply);if not(istable(j)and j.tplId=="garbage")then notify(ply,"Сначала возьмите работу мусоровоза.",false)return end;local goal,idx=currentGarbageGoal(j);if not istable(goal)or idx>=#(j.points or{})then notify(ply,"Сейчас нужно ехать на свалку.",false)return end
  local gv=Vector(goal.x or 0,goal.y or 0,goal.z or 0);local bindRadius=tonumber(JB.WorkConfig and JB.WorkConfig.garbageBindRadius)or 500;if bin:GetPos():DistToSqr(gv)>bindRadius*bindRadius then notify(ply,"Это не текущая мусорка маршрута.",false)return end;if bin:GetReadyAt()>CurTime()then notify(ply,"Мусорку уже обыскали. Подождите.",false)return end;if(ply._grmGarbageSearch or 0)>CurTime()then return end
  local duration=tonumber(JB.WorkConfig and JB.WorkConfig.garbageSearchTime)or 2.5;ply._grmGarbageSearch=CurTime()+duration;ply:SetNWBool("GRM_SearchingGarbage",true);bin._grmGarbageSearchingUntil=CurTime()+duration;bin:SetNWString("GRM_GarbageState","searching");notify(ply,"Ищем подходящие отходы...",true)
  timer.Simple(duration,function()if not IsValid(ply)then return end;ply:SetNWBool("GRM_SearchingGarbage",false);if IsValid(bin)then bin._grmGarbageSearchingUntil=nil end;if not IsValid(bin)or ply:GetPos():DistToSqr(bin:GetPos())>180*180 or IsValid(ply:GetNWEntity("GRM_GarbageBox"))then return end;local curJob=active(ply);if not(istable(curJob)and curJob.tplId=="garbage")then return end;local current,currentIdx=currentGarbageGoal(curJob);if currentIdx~=idx then return end;local currentID=istable(curJob.garbagePointIDs)and curJob.garbagePointIDs[currentIdx]or nil;local curPos=istable(current)and Vector(current.x or 0,current.y or 0,current.z or 0)or nil;if curPos and bin:GetPos():DistToSqr(curPos)>bindRadius*bindRadius then return end;local _=currentID;local box=ents.Create("grm_garbage_box");if not IsValid(box)then return end;box:SetPos(ply:GetPos());box:SetSourcePointID(tostring(idx));box:Spawn();box:Activate();box:AttachTo(ply);bin:SetReadyAt(CurTime()+(tonumber(JB.WorkConfig.garbageBinCooldown)or 90));bin:SetNWString("GRM_GarbageState","cooldown");notify(ply,"Пакет собран. Поднесите его сзади к мусоровозу и нажмите G.",true)end)
 end
 hook.Add("StartCommand","GRM_Garbage_SearchLock",function(p,cmd)if p:GetNWBool("GRM_SearchingGarbage",false)then cmd:ClearMovement();cmd:ClearButtons()end end)
 local function nearestGarbageVehicle(ply)local best,dist=nil,230*230;for _,e in ipairs(ents.FindInSphere(ply:GetPos(),230))do if IsValid(e)and(e:IsVehicle()or e.GetDriver)then local root=JB.ResolveGarbageVehicle and JB.ResolveGarbageVehicle(e)or e;local d=ply:GetPos():DistToSqr(e:GetPos());if d<dist and(JB.IsVehicleClassAllowed(root,"garbage")or(root~=e and JB.IsVehicleClassAllowed(e,"garbage")))then local basis=IsValid(root)and root or e;local behind=(ply:GetPos()-basis:GetPos()):Dot(basis:GetForward())<0;if behind then best,dist=e,d end end end end;return best end
 local function loadGarbage(ply)
  local box=ply:GetNWEntity("GRM_GarbageBox");if not IsValid(box)then return end;local j=active(ply);if not(istable(j)and j.tplId=="garbage")then return end;local veh=nearestGarbageVehicle(ply);if not IsValid(veh)then notify(ply,"Встаньте сзади разрешённого мусоровоза.",false)return end
  local cap=tonumber(JB.WorkConfig and JB.WorkConfig.garbageCapacity)or 3;local load=JB.GetGarbageLoad and JB.GetGarbageLoad(veh)or(tonumber(veh.GRM_GarbageLoad)or 0);if load>=cap then notify(ply,("Кузов заполнен: %d/%d. Езжайте на полигон."):format(load,cap),false)return end;if JB.SetGarbageLoad then veh=JB.SetGarbageLoad(veh,load+1)or veh else veh.GRM_GarbageLoad=load+1;veh:SetNWInt("GRM_GarbageLoad",load+1)end;if JB.MarkGarbageTruck then JB.MarkGarbageTruck(veh,ply,j)end;box:Remove();j.garbageCollected=(tonumber(j.garbageCollected)or 0)+1;j.pointIndex=(tonumber(j.pointIndex)or 1)+1;saveJobs("garbage loaded");JB.PushTracker(ply);JB.PushMyState(ply);local nextName=(j.pointNames or{})[j.pointIndex]or"Свалка";audit("garbage.load",ply,{vehicle=veh:EntIndex()},{load=load+1,capacity=cap});notify(ply,("Пакет загружен: %d/%d. %s"):format(load+1,cap,(load+1)>=cap and ("Кузов полон — на полигон: "..nextName) or ("Дальше: "..nextName)),true)
 end
 -- G у мусоровоза: с пакетом — загрузка в кузов, без пакета — сбор на текущей
 -- точке маршрута (в т.ч. когда физического контейнера на точке нет).
 net.Receive(NGARBAGE,function(bits,ply)if not IsValid(ply)then return end;if GRM.Net and not GRM.Net.Guard(ply,"jobs.garbage.load",{rate=.5,burst=2,maxBits=256},{bits=bits})then return end;if IsValid(ply:GetNWEntity("GRM_GarbageBox"))then loadGarbage(ply)elseif JB.CollectAtPoint then JB.CollectAtPoint(ply)end end)
 hook.Add("CanPlayerEnterVehicle","GRM_Garbage_BlockVehicle",function(p)if IsValid(p:GetNWEntity("GRM_GarbageBox"))then notify(p,"Сначала загрузите коробку с мусором сзади машины клавишей G.",false)return false end end)
 hook.Add("PlayerDeath","GRM_Garbage_RemoveCarry",function(p)local b=p:GetNWEntity("GRM_GarbageBox");if IsValid(b)then b:Remove()end end);hook.Add("PlayerDisconnected","GRM_Garbage_RemoveCarryLeave",function(p)local b=p:GetNWEntity("GRM_GarbageBox");if IsValid(b)then b:Remove()end end)
 local function chat(p,text)local s=string.lower(string.Trim(text or""));if s=="/calltaxi"or s=="/вызватьтакси"then local ok,msg=JB.CallTaxi(p,"chat");if not ok then notify(p,msg,false)end return true elseif s=="/canceltaxi"then local ok,msg=JB.CancelTaxi(p,"chat");if not ok then notify(p,msg,false)end return true end end
 hook.Add("PlayerSay","GRM_JobsV4_Chat",function(p,t)if chat(p,t)then return""end end);hook.Add("PlayerSayTransform","GRM_JobsV4_EasyChat",function(p,pack)if istable(pack)and chat(p,pack[1])then pack[1]="";pack.SkipPlayerSay=true end end)
 local function registerPerm()if GRM.Perm and GRM.Perm.RegisterClass then GRM.Perm.RegisterClass("grm_garbage_bin",true)end;if GRM.PermData and GRM.PermData.AddExtract then GRM.PermData.AddExtract("grm_garbage_bin",function(e)return{binName=e:GetBinName()}end);GRM.PermData.AddApply("grm_garbage_bin",function(e,d)e:SetBinName(tostring(d.binName or"Мусорный контейнер"))end)end end;timer.Simple(1,registerPerm);timer.Simple(4,registerPerm)
 function JB.SaveGarbageBins(ply)
  if not(IsValid(ply)and ply:IsSuperAdmin())then return false,"только суперадмин"end;registerPerm();if not(GRM.Perm and GRM.Perm.Add)then return false,"perm-модуль не загружен"end
  local saved,errors=0,{};for _,bin in ipairs(ents.FindByClass("grm_garbage_bin"))do if IsValid(bin)then local ok,why=GRM.Perm.Add(ply,bin,{ownerKind="server",freeze=true,label="Мусорный контейнер"});if ok then saved=saved+1 else errors[#errors+1]=tostring(why)end end end
  if#errors>0 then return false,"сохранено "..saved..", ошибок "..#errors..": "..table.concat(errors,"; ")end;return true,"мусорок сохранено: "..saved
 end
 function JB.LoadGarbageBins(ply)
  if not(IsValid(ply)and ply:IsSuperAdmin())then return false,"только суперадмин"end;registerPerm();if not(GRM.Perm and GRM.Perm.LoadClass)then return false,"точечная загрузка perm недоступна"end
  local ok,result=GRM.Perm.LoadClass("grm_garbage_bin","/grm_persistence");if not ok then return false,tostring(result)end;return true,("восстановлено %d, уже на месте %d"):format(tonumber(result.spawned)or 0,tonumber(result.skipped)or 0)
 end
end
if CLIENT then
 hook.Add("PlayerButtonDown","GRM_Garbage_GKey",function(p,keyCode)if p~=LocalPlayer()or keyCode~=KEY_G then return end;if not(IsValid(p:GetNWEntity("GRM_GarbageBox"))or p:GetNWBool("GRM_GarbageJob",false))then return end;if(p._grmGarbageKeyNext or 0)>CurTime()then return end;p._grmGarbageKeyNext=CurTime()+.6;net.Start(NGARBAGE);net.SendToServer()end)
 hook.Add("HUDPaint","GRM_Garbage_CarryHUD",function()local p=LocalPlayer();local box=IsValid(p)and p:GetNWEntity("GRM_GarbageBox")or nil;if not IsValid(box)then return end;draw.RoundedBox(7,ScrW()/2-220,ScrH()-145,440,42,Color(14,20,28,230));draw.SimpleText("КОРОБКА С МУСОРОМ • сзади мусоровоза нажмите G","DermaDefaultBold",ScrW()/2,ScrH()-124,Color(235,220,130),TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)end)
 net.Receive(NTAXI,function()
  local fare,minFare,maxFare=net.ReadUInt(20),net.ReadUInt(20),net.ReadUInt(20);local rows,current=net.ReadTable()or{},net.ReadUInt(24)
  if IsValid(JB._taxiFrame)then JB._taxiFrame:Remove()end
  local f=vgui.Create("DFrame");JB._taxiFrame=f;f:SetSize(760,620);f:Center();f:MakePopup();f:SetTitle("ТАКСИ • ЖИВЫЕ ЗАКАЗЫ");if GRM.UI then GRM.UI.Track("jobs.taxi",f)end
  local fareSlider=vgui.Create("DNumSlider",f);fareSlider:Dock(TOP);fareSlider:DockMargin(10,8,10,0);fareSlider:SetTall(42);fareSlider:SetText("Ваша такса");fareSlider:SetMin(minFare);fareSlider:SetMax(maxFare);fareSlider:SetDecimals(0);fareSlider:SetValue(fare)
  local fareSave=vgui.Create("DButton",f);fareSave:Dock(TOP);fareSave:DockMargin(10,4,10,6);fareSave:SetTall(30);fareSave:SetText("СОХРАНИТЬ ТАКСУ");fareSave.DoClick=function()net.Start(NTAXIACT);net.WriteString("set_fare");net.WriteUInt(math.floor(fareSlider:GetValue()),20);net.SendToServer()end
  local sc=vgui.Create("DScrollPanel",f);sc:Dock(FILL);sc:DockMargin(10,4,10,4)
  if current>0 then local release=vgui.Create("DButton",f);release:Dock(BOTTOM);release:SetTall(42);release:SetText("ОТКАЗАТЬСЯ ОТ ТЕКУЩЕГО ЗАКАЗА");release.DoClick=function()net.Start(NTAXIACT);net.WriteString("release");net.SendToServer()end end
  for _,r in ipairs(rows)do local row=vgui.Create("DPanel",sc);row:Dock(TOP);row:SetTall(78);row:DockMargin(0,0,0,6);row.Paint=function(_,w,h)draw.RoundedBox(6,0,0,w,h,Color(28,38,52));draw.SimpleText(r.callerName,"DermaDefaultBold",12,13,color_white);draw.SimpleText(r.distance.." юн. • ожидает "..r.age.." сек","DermaDefault",12,33,Color(170,190,210));draw.SimpleText("в "..tostring(r.dropoffName or "назначение"),"DermaDefault",12,51,Color(235,205,120))end;local take=vgui.Create("DButton",row);take:Dock(RIGHT);take:SetWide(150);take:SetText("ПРИНЯТЬ");take.DoClick=function()net.Start(NTAXIACT);net.WriteString("accept");net.WriteUInt(r.id,24);net.SendToServer()end end
  local refresh=vgui.Create("DButton",f);refresh:Dock(BOTTOM);refresh:SetTall(40);refresh:SetText("ОБНОВИТЬ ЗАКАЗЫ");refresh.DoClick=function()net.Start(NTAXIACT);net.WriteString("refresh");net.SendToServer()end
 end)
end
print("[GRM Jobs v4] physical garbage + live taxi loaded")
