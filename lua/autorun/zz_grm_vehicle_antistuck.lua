--[[--------------------------------------------------------------------
    GRM Vehicle Anti-Stuck / Anti-Stack

    Куда положить:
      garrysmod/addons/grm_vehicle_antistuck/lua/autorun/zz_grm_vehicle_antistuck.lua

    Можно положить и в любой существующий аддон в lua/autorun/.

    Что делает:
      • После выхода из машины переносит игрока в безопасную точку рядом с транспортом.
      • Временно отключает столкновение игрока с машиной, чтобы его не зажало моделью.
      • Если игрок всё же оказался внутри bounding box машины — выталкивает наружу.
      • Поддерживает обычный транспорт, simfphys, LVS и vehicle seats/children.
--------------------------------------------------------------------]]

if SERVER then
    AddCSLuaFile()
end

GRM = GRM or {}
GRM.VehicleAntiStuck = GRM.VehicleAntiStuck or {}
local AS = GRM.VehicleAntiStuck

AS.Config = AS.Config or {
    Enabled = true,
    -- ТОНКАЯ ЛОГИКА:
    -- true  = вообще не трогать игроков, которые просто подошли к машине.
    -- false = включить старую общую проверку рядом с машинами.
    OnlyAfterVehicleExit = true,
    -- Не телепортировать сразу при выходе, а сначала проверить, реально ли игрок внутри машины.
    -- Это убирает ощущение, что система откидывает слишком далеко при нормальном выходе.
    ForceMoveOnExit = false,
    -- Сколько секунд после выхода игрок временно не сталкивается с машиной.
    NoCollideTime = 1.25,
    -- Сколько секунд после выхода проверять, не застрял ли игрок.
    PostExitCheckTime = 0.8,
    -- Как часто проверять только игроков, которые недавно вышли из транспорта.
    ThinkInterval = 0.25,
    -- Насколько далеко от края машины искать безопасную точку.
    -- Небольшое значение, чтобы не швыряло далеко.
    ExitExtraDistance = 26,
    -- Радиус поиска связанных сидений/транспорта.
    VehicleChildSearchRadius = 420,
    -- Мягкий толчок после переноса. 0 = вообще без толчка.
    PushVelocity = 0,
    -- Максимальное горизонтальное удаление от позиции выхода/сиденья.
    MaxExitDistance = 180,
    -- Запрещаем поиск этажом выше. Допустим только небольшой подъём на порог.
    MaxUpwardDelta = 24,
    MaxDownwardDelta = 88,
    -- Безопасная высота над найденной землёй.
    GroundOffset = 3,
    -- Насколько расширять OBB машины при проверке "внутри".
    -- Маленькое значение, чтобы не срабатывало при обычном подходе к машине.
    InsideOBBExpand = 2,
    -- Дополнительная hull-проверка StartSolid. По умолчанию выключена,
    -- потому что она часто срабатывает просто рядом с машиной.
    UseHullStartSolidCheck = false,
    -- Игнорировать проверку для админов в noclip.
    IgnoreNoclip = true,
    -- Временно делать игрока COLLISION_GROUP_DEBRIS_TRIGGER после выхода.
    TemporaryPlayerCollisionGroup = true,

    --[[ Заказ владельца 21.08: игрока НИКОГДА не должно сталкивать
         транспортом, и при выходе его нужно чуть отставлять вбок от КОРПУСА
         машины (а не от сиденья — у simfphys сиденье это отдельный под,
         который стоит внутри модели). ]]
    -- Постоянное отключение столкновения «игрок ↔ транспорт».
    AlwaysNoCollideWithVehicles = true,
    -- На сколько юнитов отставить игрока от борта машины при выходе.
    SideExitOffset = 10,
    -- Ставить игрока сбоку от машины при каждом выходе.
    SideExitOnLeave = true,
}

-- Если файл обновлён поверх старой версии через lua_refresh, мягко переводим старые настройки
-- на новый адекватный профиль один раз.
AS.Config.ProfileVersion = AS.Config.ProfileVersion or 0
if AS.Config.ProfileVersion < 3 then
    AS.Config.OnlyAfterVehicleExit = true
    AS.Config.ForceMoveOnExit = false
    AS.Config.NoCollideTime = 1.25
    AS.Config.PostExitCheckTime = 0.8
    AS.Config.ThinkInterval = 0.25
    AS.Config.ExitExtraDistance = 26
    AS.Config.VehicleChildSearchRadius = 420
    AS.Config.PushVelocity = 0
    AS.Config.MaxExitDistance = 180
    AS.Config.MaxUpwardDelta = 24
    AS.Config.MaxDownwardDelta = 88
    AS.Config.GroundOffset = 3
    AS.Config.InsideOBBExpand = 2
    AS.Config.UseHullStartSolidCheck = false
    AS.Config.IgnoreNoclip = true
    AS.Config.TemporaryPlayerCollisionGroup = true
    AS.Config.ProfileVersion = 3
end

-- Безопасные дефолты.
AS.Config.AlwaysNoCollideWithVehicles = AS.Config.AlwaysNoCollideWithVehicles ~= false
AS.Config.SideExitOnLeave = AS.Config.SideExitOnLeave ~= false
AS.Config.SideExitOffset = tonumber(AS.Config.SideExitOffset) or 10
AS.Config.Enabled = AS.Config.Enabled ~= false
AS.Config.OnlyAfterVehicleExit = AS.Config.OnlyAfterVehicleExit ~= false
AS.Config.ForceMoveOnExit = AS.Config.ForceMoveOnExit == true
AS.Config.NoCollideTime = AS.Config.NoCollideTime or 1.25
AS.Config.PostExitCheckTime = AS.Config.PostExitCheckTime or 0.8
AS.Config.ThinkInterval = AS.Config.ThinkInterval or 0.25
AS.Config.ExitExtraDistance = AS.Config.ExitExtraDistance or 26
AS.Config.VehicleChildSearchRadius = AS.Config.VehicleChildSearchRadius or 420
AS.Config.PushVelocity = tonumber(AS.Config.PushVelocity) or 0
AS.Config.MaxExitDistance = tonumber(AS.Config.MaxExitDistance) or 180
AS.Config.MaxUpwardDelta = tonumber(AS.Config.MaxUpwardDelta) or 24
AS.Config.MaxDownwardDelta = tonumber(AS.Config.MaxDownwardDelta) or 88
AS.Config.GroundOffset = AS.Config.GroundOffset or 3
AS.Config.InsideOBBExpand = AS.Config.InsideOBBExpand or 2
AS.Config.UseHullStartSolidCheck = AS.Config.UseHullStartSolidCheck == true
AS.Config.IgnoreNoclip = AS.Config.IgnoreNoclip ~= false
AS.Config.TemporaryPlayerCollisionGroup = AS.Config.TemporaryPlayerCollisionGroup ~= false

local PLAYER_MINS = Vector(-16, -16, 0)
local PLAYER_MAXS = Vector(16, 16, 72)

local function cfg()
    return AS.Config or {}
end

--[[ РАСПОЗНАВАНИЕ ТРАНСПОРТА.

     Тут была настоящая причина «сталкивает корпусом»: в списке стояло
     «sim_fphys», а реальные классы simfphys называются `simfphys_*`
     (например `simfphys_btr80`). Ни одна машина simfphys под проверку не
     попадала — значит и корпус не считался транспортом: ни no-collide, ни
     поиск базы под сиденьем не работали.

     Теперь помимо классов смотрим на признаки самих аддонов: у simfphys это
     поле `IsSimfphysCar`/`LVS`, их выставляет сам аддон. ]]
local VEHICLE_CLASS_HINTS = {
    "prop_vehicle", "gmod_sent_vehicle", "simfphys", "sim_fphys",
    "lvs_", "lvs", "gred", "glide_",
}

local function isVehicleLike(ent)
    if not IsValid(ent) then return false end
    if ent:IsVehicle() then return true end
    if ent.IsSimfphysCar or ent.LVS or ent.IsGlideVehicle then return true end
    if ent.GetSeatIndex and ent.GetVehicle then return true end
    local class = string.lower(ent:GetClass() or "")
    for _, hint in ipairs(VEHICLE_CLASS_HINTS) do
        if string.find(class, hint, 1, true) then return true end
    end
    return false
end

local function getVehicleBase(ent)
    if not IsValid(ent) then return ent end
    local parent = ent:GetParent()
    if IsValid(parent) and isVehicleLike(parent) then
        return parent
    end

    -- У simfphys/LVS игрок часто сидит в prop_vehicle_prisoner_pod,
    -- а реальная машина является parent или находится совсем рядом.
    if ent:IsVehicle() then
        local radius = cfg().VehicleChildSearchRadius or 480
        local best = ent
        local bestDist = math.huge
        for _, v in ipairs(ents.FindInSphere(ent:GetPos(), radius)) do
            if IsValid(v) and v ~= ent and isVehicleLike(v) and not v:IsVehicle() then
                local d = v:GetPos():DistToSqr(ent:GetPos())
                if d < bestDist then
                    best = v
                    bestDist = d
                end
            end
        end
        return best
    end

    return ent
end

local function collectRelatedEntities(base, seat)
    local filter = {}
    local function add(ent)
        if IsValid(ent) then filter[#filter + 1] = ent end
    end
    add(base)
    add(seat)

    if IsValid(base) then
        for _, child in ipairs(base:GetChildren()) do
            add(child)
        end

        local radius = cfg().VehicleChildSearchRadius or 480
        for _, ent in ipairs(ents.FindInSphere(base:GetPos(), radius)) do
            if IsValid(ent) and ent:IsVehicle() then
                if ent:GetParent() == base or ent:GetPos():DistToSqr(base:GetPos()) <= 280 * 280 then
                    add(ent)
                end
            end
        end
    end

    return filter
end

local function vehicleRadius(ent)
    if not IsValid(ent) then return 96 end
    local mins, maxs = ent:OBBMins(), ent:OBBMaxs()
    local size = maxs - mins
    local r = math.max(math.abs(size.x), math.abs(size.y)) * 0.5
    return math.Clamp(r, 64, 360)
end

local function isPointInsideVehicleOBB(pos, ent, expand)
    if not IsValid(ent) then return false end
    expand = expand or 10

    local localPos = ent:WorldToLocal(pos)
    local mins, maxs = ent:OBBMins(), ent:OBBMaxs()
    mins = mins - Vector(expand, expand, expand)
    maxs = maxs + Vector(expand, expand, expand)

    return localPos.x >= mins.x and localPos.x <= maxs.x
       and localPos.y >= mins.y and localPos.y <= maxs.y
       and localPos.z >= mins.z and localPos.z <= maxs.z
end

local function horizontalDistSqr(a,b)
    local dx,dy=a.x-b.x,a.y-b.y
    return dx*dx+dy*dy
end

local function groundAndHullClear(pos, filter, anchor, referenceZ)
    -- Короткая трасса вокруг текущего этажа. Старые +96/-160 могли начать
    -- луч над потолком и выбрать пол следующего этажа.
    local ground=util.TraceLine({start=pos+Vector(0,0,24),endpos=pos-Vector(0,0,72),filter=filter,mask=MASK_PLAYERSOLID})
    if not ground.Hit or ground.StartSolid then return nil end
    if ground.HitNormal and ground.HitNormal.z<0.55 then return nil end
    local finalPos=ground.HitPos+Vector(0,0,cfg().GroundOffset or 3)
    local dz=finalPos.z-referenceZ
    if dz>(cfg().MaxUpwardDelta or 24) or dz<-(cfg().MaxDownwardDelta or 88) then return nil end
    local maxDist=cfg().MaxExitDistance or 180
    if horizontalDistSqr(finalPos,anchor)>maxDist*maxDist then return nil end

    local hull=util.TraceHull({start=finalPos,endpos=finalPos,mins=PLAYER_MINS,maxs=PLAYER_MAXS,filter=filter,mask=MASK_PLAYERSOLID})
    if hull.StartSolid or hull.Hit then return nil end

    -- Проверяем путь на уровне корпуса: нельзя телепортироваться сквозь стену.
    local path=util.TraceHull({start=anchor+Vector(0,0,36),endpos=finalPos+Vector(0,0,36),mins=Vector(-14,-14,-32),maxs=Vector(14,14,32),filter=filter,mask=MASK_PLAYERSOLID})
    if path.StartSolid or path.Hit then return nil end
    return finalPos
end

local function pushCandidate(out,pos,dir)
    if not pos then return end
    for _,old in ipairs(out)do if old.pos:DistToSqr(pos)<16 then return end end
    out[#out+1]={pos=pos,dir=dir}
end

local function buildCandidates(ply,base,seat)
    local out={}
    local anchor=IsValid(seat) and seat:GetPos() or ply:GetPos()
    -- Сначала точки буквально рядом с сиденьем — это ожидаемое место выхода.
    local seatDirs=IsValid(seat) and {seat:GetRight(),-seat:GetRight(),-seat:GetForward(),seat:GetForward()} or {}
    for _,dir in ipairs(seatDirs)do dir.z=0;if dir:LengthSqr()>1 then dir:Normalize();pushCandidate(out,anchor+dir*46+Vector(0,0,18),dir)end end

    if IsValid(base)then
        local mins,maxs=base:OBBMins(),base:OBBMaxs();local center=(mins+maxs)*0.5;local extra=cfg().ExitExtraDistance or 26
        local locals={
            {Vector(maxs.x+extra,center.y,center.z),base:GetForward()},
            {Vector(mins.x-extra,center.y,center.z),-base:GetForward()},
            {Vector(center.x,maxs.y+extra,center.z),base:GetRight()},
            {Vector(center.x,mins.y-extra,center.z),-base:GetRight()},
        }
        for _,v in ipairs(locals)do local dir=v[2];dir.z=0;if dir:LengthSqr()>1 then dir:Normalize()end;pushCandidate(out,base:LocalToWorld(v[1]),dir)end
    end

    -- Последними — небольшие кольца вокруг исходной позиции, но никогда
    -- дальше MaxExitDistance и без необработанного fallback.
    local dirs=IsValid(base) and {base:GetRight(),-base:GetRight(),base:GetForward(),-base:GetForward()} or {ply:GetRight(),-ply:GetRight(),ply:GetForward(),-ply:GetForward()}
    for _,radius in ipairs({64,96,128})do for _,dir in ipairs(dirs)do dir.z=0;if dir:LengthSqr()>1 then dir:Normalize();pushCandidate(out,anchor+dir*radius+Vector(0,0,18),dir)end end end
    return out,anchor
end

function AS.FindSafeExitPos(ply,vehicleOrSeat)
    if not IsValid(ply) or not IsValid(vehicleOrSeat) then return nil end
    local base=getVehicleBase(vehicleOrSeat);if not IsValid(base)then base=vehicleOrSeat end
    local filter=collectRelatedEntities(base,vehicleOrSeat);filter[#filter+1]=ply
    local candidates,anchor=buildCandidates(ply,base,vehicleOrSeat)
    local referenceZ=ply:GetPos().z
    for _,candidate in ipairs(candidates)do
        local clear=groundAndHullClear(candidate.pos,filter,anchor,referenceZ)
        if clear then return clear,candidate.dir,base end
    end
    -- Нет безопасной точки рядом — не переносим вообще. Временный NoCollide
    -- всё равно даст игроку выйти из модели без броска на улицу/этаж.
    return nil,nil,base
end

AS._BuildCandidates=buildCandidates -- тестовый экспорт
AS._GroundAndHullClear=groundAndHullClear

AS.NoCollidePairs = AS.NoCollidePairs or {}

local function pairKey(a, b)
    if not IsValid(a) or not IsValid(b) then return nil end
    local ia, ib = a:EntIndex(), b:EntIndex()
    if ia > ib then ia, ib = ib, ia end
    return ia .. ":" .. ib
end

function AS.TempNoCollide(ply, base, seat, duration)
    if not IsValid(ply) then return end
    duration = duration or (cfg().NoCollideTime or 2.5)
    local untilTime = CurTime() + duration

    local entities = collectRelatedEntities(base, seat)
    for _, ent in ipairs(entities) do
        if IsValid(ent) then
            local key = pairKey(ply, ent)
            if key then
                AS.NoCollidePairs[key] = untilTime
            end
        end
    end

    if cfg().TemporaryPlayerCollisionGroup and SERVER then
        ply.GRM_AntiStuck_OldCollisionGroup = ply.GRM_AntiStuck_OldCollisionGroup or ply:GetCollisionGroup()
        ply:SetCollisionGroup(COLLISION_GROUP_DEBRIS_TRIGGER)

        timer.Create("GRM_AntiStuck_RestoreCG_" .. ply:EntIndex(), duration, 1, function()
            if not IsValid(ply) then return end
            ply:SetCollisionGroup(ply.GRM_AntiStuck_OldCollisionGroup or COLLISION_GROUP_PLAYER)
            ply.GRM_AntiStuck_OldCollisionGroup = nil
        end)
    end
end

--[[ ПОСТОЯННОЕ ОТСУТСТВИЕ СТОЛКНОВЕНИЯ «ИГРОК ↔ ТРАНСПОРТ».

     Временного no-collide на полторы секунды не хватало: человека сталкивало
     корпусом уже после того, как окно защиты закрылось (и особенно на
     крупной технике вроде simfphys_btr80, где сиденье стоит глубоко внутри
     модели). Проверка стоит ПЕРЕД разбором пар и стоит копейки: сначала
     дешёвый IsPlayer, и только потом класс второго объекта. ]]
local function otherIsVehicle(ent)
    if not IsValid(ent) then return false end
    if ent:IsVehicle() then return true end
    return isVehicleLike(ent)
end

hook.Add("ShouldCollide", "GRM_VehicleAntiStuck_PlayerVehicle", function(a, b)
    if not AS.Config or AS.Config.Enabled == false then return end
    if AS.Config.AlwaysNoCollideWithVehicles == false then return end
    if not (IsValid(a) and IsValid(b)) then return end

    local ply, other
    if a:IsPlayer() then ply, other = a, b
    elseif b:IsPlayer() then ply, other = b, a
    else return end

    -- Водителя и пассажиров это не касается: они и так «внутри».
    if otherIsVehicle(other) then return false end
end)

hook.Add("ShouldCollide", "GRM_VehicleAntiStuck_TempNoCollide", function(a, b)
    if not AS.Config or AS.Config.Enabled == false then return end
    -- ГОРЯЧИЙ ПУТЬ: ShouldCollide вызывается движком для КАЖДОЙ пары
    -- сталкивающихся объектов каждый тик. Раньше здесь всегда делался
    -- pairKey() (2x EntIndex + конкатенация строк) даже когда активных
    -- no-collide пар не было вообще — это давало постоянную нагрузку и
    -- микрофризы на серверах с транспортом/пропами. Быстрый выход при пустой
    -- таблице делает хук практически бесплатным в 99.99% случаев.
    if next(AS.NoCollidePairs) == nil then return end
    local key = pairKey(a, b)
    if not key then return end
    local untilTime = AS.NoCollidePairs[key]
    if not untilTime then return end
    if CurTime() > untilTime then
        AS.NoCollidePairs[key] = nil
        return
    end
    return false
end)

--[[ ВЫХОД СБОКУ ОТ КОРПУСА (заказ 21.08).

     Считаем габариты именно БАЗОВОЙ машины: у simfphys/LVS игрок сидит в
     prop_vehicle_prisoner_pod, который стоит внутри модели, и «отойти от
     сиденья» ничего не даёт — человек остаётся в корпусе.

     Сторону выбираем ту, к которой игрок ближе (вышел слева — остался
     слева), и отставляем на полшины корпуса плюс SideExitOffset. Если там
     стена или другой объект — пробуем противоположный борт, потом корму и
     нос. Не нашли ничего свободного — ничего не двигаем: лучше остаться на
     месте, чем оказаться в стене. ]]
function AS.SideExitPos(ply, base)
    if not (IsValid(ply) and IsValid(base)) then return nil end

    local offset = math.max(0, tonumber(cfg().SideExitOffset) or 10)
    local mins, maxs = base:OBBMins(), base:OBBMaxs()
    local center = base:LocalToWorld(base:OBBCenter())
    local ang = base:GetAngles()
    local right, forward = ang:Right(), ang:Forward()

    local halfWidth = math.abs(maxs.y - mins.y) * 0.5
    local halfLength = math.abs(maxs.x - mins.x) * 0.5

    -- С какой стороны человек уже находится: туда и выпускаем.
    local toPlayer = ply:GetPos() - center
    local sideSign = (toPlayer:Dot(right) >= 0) and 1 or -1

    local hull = { math.abs(offset) + 2, 0 }
    local candidates = {
        center + right * sideSign * (halfWidth + offset + 16),
        center - right * sideSign * (halfWidth + offset + 16),
        center - forward * (halfLength + offset + 16),
        center + forward * (halfLength + offset + 16),
    }

    local filter = collectRelatedEntities(base, base)
    filter[#filter + 1] = ply

    for _, candidate in ipairs(candidates) do
        -- Ставим на землю: борт машины может быть выше или ниже игрока.
        local ground = util.TraceLine({
            start = candidate + Vector(0, 0, 40),
            endpos = candidate - Vector(0, 0, 120),
            filter = filter,
            mask = MASK_PLAYERSOLID,
        })
        local spot = ground.Hit and (ground.HitPos + Vector(0, 0, cfg().GroundOffset or 3)) or candidate

        local room = util.TraceHull({
            start = spot,
            endpos = spot,
            mins = ply:OBBMins(),
            maxs = ply:OBBMaxs(),
            filter = filter,
            mask = MASK_PLAYERSOLID,
        })
        if not room.StartSolid then return spot end
    end
    return nil
end

function AS.MovePlayerOutOfVehicle(ply, vehicleOrSeat, reason)
    if not IsValid(ply) or not IsValid(vehicleOrSeat) then return false end
    if cfg().IgnoreNoclip and ply:GetMoveType() == MOVETYPE_NOCLIP then return false end

    local pos, dir, base = AS.FindSafeExitPos(ply, vehicleOrSeat)
    if not pos then return false end

    AS.TempNoCollide(ply, base or vehicleOrSeat, vehicleOrSeat, cfg().NoCollideTime or 2.5)

    ply:SetPos(pos)
    ply:SetLocalVelocity(Vector(0, 0, 0))

    local push = tonumber(cfg().PushVelocity) or 35
    if dir and push > 0 then
        ply:SetVelocity(dir * push + Vector(0, 0, math.min(push * 0.25, 12)))
    end

    ply.GRM_AntiStuck_LastVehicle = base or vehicleOrSeat
    ply.GRM_AntiStuck_LastSeat = vehicleOrSeat
    ply.GRM_AntiStuck_LastFix = CurTime()

    return true
end

local function playerLooksStuckInVehicle(ply, ent)
    if not IsValid(ply) or not IsValid(ent) then return false end

    --[[ Раньше срабатывало по попаданию центра тела в OBB машины. Удлинённый
         корпус внедорожника даёт ОГРОМНЫЙ бокс: игрок отошёл назад вдоль
         борта, его грудь всё ещё внутри бокса — и антистак телепортировал его
         обратно в машину (жалоба владельца: «двинулся — тянет в машину»).

         Теперь «застрял» = реальное пересечение хитбокса игрока с СОЛИДНОЙ
         геометрией машины (TraceHull с фильтром только по машине и её
         детям), плюс дистанция до ближайшей точки корпуса маленькая. ]]
    local mins, maxs = ply:OBBMins(), ply:OBBMaxs()
    local from = ply:GetPos()
    local filter = collectRelatedEntities(ent, ent)
    filter[#filter + 1] = ply

    local hull = util.TraceHull({
        start = from,
        endpos = from,
        mins = mins,
        maxs = maxs,
        filter = filter,
        mask = MASK_PLAYERSOLID,
    })
    if hull.StartSolid and IsValid(hull.Entity) and isVehicleLike(hull.Entity) then
        return true
    end

    -- Запасной случай: если трасса в этом тике не увидела корпус, но игрок
    -- глубоко внутри БЛИЖАЙШЕЙ точки корпуса (<12 юнитов) и в пределах OBB.
    local base = ent.NearestPoint and ent or nil
    if base then
        local near = ent:NearestPoint(ply:GetPos() + Vector(0,0,40))
        local d2 = near:DistToSqr(ply:GetPos() + Vector(0,0,40))
        if d2 < 14*14 and isPointInsideVehicleOBB(ply:GetPos() + Vector(0,0,40), ent, 1) then
            return true
        end
    end

    return false
end

if SERVER then

    hook.Add("PlayerLeaveVehicle", "GRM_VehicleAntiStuck_OnLeave", function(ply, vehicle)
        if not cfg().Enabled then return end
        if not IsValid(ply) or not IsValid(vehicle) then return end

        local base = getVehicleBase(vehicle)

        ply.GRM_AntiStuck_LastVehicle = base
        ply.GRM_AntiStuck_LastSeat = vehicle
        ply.GRM_AntiStuck_PostExitUntil = CurTime() + (cfg().PostExitCheckTime or 0.8)

        -- Временно отключаем столкновение с машиной сразу после выхода,
        -- но НЕ переносим игрока, если он нормально вышел.
        AS.TempNoCollide(ply, base, vehicle, cfg().NoCollideTime or 1.25)

        --[[ Ставим человека сбоку от КОРПУСА, а не от сиденья: 10 юнитов от
             борта той стороны, к которой он ближе. Делается следующим тиком,
             иначе движок ещё держит игрока в поде и SetPos перетрётся. ]]
        if cfg().SideExitOnLeave and IsValid(base) then
            timer.Simple(0, function()
                if not (IsValid(ply) and IsValid(base)) then return end
                if ply:InVehicle() then return end
                if cfg().IgnoreNoclip and ply:GetMoveType() == MOVETYPE_NOCLIP then return end
                local spot = AS.SideExitPos(ply, base)
                if not spot then return end
                ply:SetPos(spot)
                ply:SetLocalVelocity(Vector(0, 0, 0))
            end)
        end

        if cfg().ForceMoveOnExit then
            timer.Simple(0, function()
                if IsValid(ply) and IsValid(vehicle) then
                    AS.MovePlayerOutOfVehicle(ply, vehicle, "leave_force")
                end
            end)
        end

        -- Поздние повторные проверки убраны: они тянули игрока обратно в
        -- машину, когда он сам отошёл (корпус длинной машины попадал в OBB).
        -- Достаточно одной ранней проверки, пока игрок ещё не двигался.
        timer.Simple(0.15, function()
            if not IsValid(ply) then return end
            local last = IsValid(ply.GRM_AntiStuck_LastVehicle) and ply.GRM_AntiStuck_LastVehicle or vehicle
            if not IsValid(last) then return end
            if ply:InVehicle() then return end
            if cfg().IgnoreNoclip and ply:GetMoveType() == MOVETYPE_NOCLIP then return end
            -- Если игрок уже сам отошёл от корпуса — не трогаем его вообще.
            local near = last.NearestPoint and last:NearestPoint(ply:GetPos()) or nil
            if near and near:DistToSqr(ply:GetPos()) > (52 * 52) then return end
            if playerLooksStuckInVehicle(ply, last) then
                AS.MovePlayerOutOfVehicle(ply, last, "post_exit_check")
            end
        end)
    end)

    -- Если игрок умер/отключился, возвращаем collision group.
    local function cleanupPlayer(ply)
        if not IsValid(ply) then return end
        if ply.GRM_AntiStuck_OldCollisionGroup then
            ply:SetCollisionGroup(ply.GRM_AntiStuck_OldCollisionGroup)
            ply.GRM_AntiStuck_OldCollisionGroup = nil
        end
    end
    hook.Add("PlayerDeath", "GRM_VehicleAntiStuck_CleanupDeath", cleanupPlayer)
    hook.Add("PlayerDisconnected", "GRM_VehicleAntiStuck_CleanupDisconnect", cleanupPlayer)

    -- Периодическая чистка истёкших no-collide пар: иначе записи, которые
    -- больше никогда не столкнутся (игрок ушёл/отключился), копились бы
    -- в NoCollidePairs вечно. Редкий (раз в 2с) проход — дешёвый.
    timer.Create("GRM_VehicleAntiStuck_Cleanup", 2, 0, function()
        if next(AS.NoCollidePairs) == nil then return end
        local now = CurTime()
        for k, untilTime in pairs(AS.NoCollidePairs) do
            if untilTime <= now then AS.NoCollidePairs[k] = nil end
        end
    end)

    timer.Create("GRM_VehicleAntiStuck_Think", AS.Config.ThinkInterval, 0, function()
        if not cfg().Enabled then return end

        for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(ply) and ply:Alive() and not ply:InVehicle() then
                if not (cfg().IgnoreNoclip and ply:GetMoveType() == MOVETYPE_NOCLIP) then
                    -- Новый режим: проверяем только игроков, которые недавно вышли из машины.
                    -- Игроков, которые просто подошли к машине, не трогаем.
                    if ply.GRM_AntiStuck_PostExitUntil and CurTime() <= ply.GRM_AntiStuck_PostExitUntil then
                        local ent = IsValid(ply.GRM_AntiStuck_LastVehicle) and ply.GRM_AntiStuck_LastVehicle or nil
                        if IsValid(ent) then
                            -- Если игрок сам идёт и уже оторвался от корпуса на
                            -- шаг — он не застрял, не тянем его обратно.
                            local near = ent.NearestPoint and ent:NearestPoint(ply:GetPos()) or nil
                            local vel = ply:GetVelocity():Length2D()
                            if near and near:DistToSqr(ply:GetPos()) > (56*56) and vel > 20 then
                                -- считаем, что он благополучно вышел
                                ply.GRM_AntiStuck_PostExitUntil = nil
                            elseif playerLooksStuckInVehicle(ply, ent) then
                                AS.MovePlayerOutOfVehicle(ply, ent, "post_exit_think")
                            end
                        end
                    end
                end
            end
        end
    end)

    concommand.Add("grm_antistuck_vehicle", function(ply)
        if not IsValid(ply) then return end
        if not ply:IsAdmin() and not ply:IsSuperAdmin() then return end

        local tr = ply:GetEyeTrace()
        local ent = tr.Entity
        if not IsValid(ent) or not isVehicleLike(ent) then
            ply:ChatPrint("[AntiStuck] Наведитесь на транспорт.")
            return
        end

        AS.MovePlayerOutOfVehicle(ply, ent, "manual")
    end)

    print("[GRM Vehicle Anti-Stuck] Server loaded.")
else
    print("[GRM Vehicle Anti-Stuck] Client loaded.")
end
