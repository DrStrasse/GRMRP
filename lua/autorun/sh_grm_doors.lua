--[[--------------------------------------------------------------------
    GRM Doors System v5.0.0 (Код 64 — ЯДРО ПЕРЕСОБРАНО)

    Слои допуска — CONCEPT_DOORS_V3.md:
      0 SuperAdmin  — всё, включая назначение владельца карты;
      1 проход      — незапертую дверь проходит любой;
      2 ключ        — запертую: владелец / совладелец / фракция /
                      категория / ACL / ордер+CanWarrant;
      3 хозяйство   — имя, совладельцы, ACL: владелец-игрок или SuperAdmin;
      4 покупка     — ничья и ownable;
      5 карта       — фракция/категория/приватизация: только SuperAdmin;
      6 сила        — таран: CanForceDoor или ордер (не ключ на E).

    ownable=false = «не продаётся», НЕ «всем можно».
    AM.CanManage = /door_access, не вкладка R-меню.

    Идентичность: MapCreationID + AABB-склейка дублей одного полотна через
    ПРОСТРАНСТВЕННЫЙ ХЭШ (v5.0.0): дверь сравнивается только с соседями по
    сетке 128 юнитов, а не со всеми дверьми карты (было O(n^2) на каждый
    спавн двери — источник фризов на дупликаторе и загрузке карты).

    v5.0.0 «полная пересборка»:
      * D.AllDoors()        — список дверей из event-реестров GRM.Perf,
                              без ents.GetAll();
      * D.PurgeGhostDoors() — фантомы по группам, с весами «кого оставить»
                              (карта > владелец > запись > меньший ID) и
                              защитой полотен самой карты (force снимает);
      * D.RebuildAll()      — идентичность + фантомы + схлопывание записей
                              + сироты + переприменение визуала + save;
      * D.InvalidateIdentity() и коалесцированное обслуживание вместо
                              timer.Simple на каждую созданную entity;
      * /door_audit, /door_rebuild [dry|force|orphans].

    Персист: только изменённые записи, массив, version=3,
             jsonT(..., false, true). CharacterKey = SteamID64:charN.
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Doors = GRM.Doors or {}
local D = GRM.Doors
D.Version = "5.0.0"

D.Config = D.Config or {
    UseDistance = 180,
    MaxOwnersPerDoor = 12,
    DefaultRentSeconds = 7 * 24 * 3600,
    RentPrice = 5000,
    PermPriceMultiplier = 3,
    SuperAdminBypass = true,
    HUDDistance = 220,
    DuplicateCenterDistance = 64,
    DuplicateXYOverlap = 0.55,
    DuplicateZOverlap = 0.72,
    LockSyncInterval = 2.0,
    ActCooldown = 0.4,
    -- Ячейка пространственного хэша для поиска дублей. Сравниваем дверь только
    -- с соседями по сетке, а не со всеми дверьми карты (было O(n^2)).
    IdentityCellSize = 128,
    -- Удалять ли дубли, созданные САМОЙ картой. По умолчанию нет: фантомы
    -- родом из тулзы/дупликатора/сейва, а снос настоящего полотна карты
    -- ломает геометрию и не откатывается. Включается `grm_door_rebuild force`.
    PurgeMapDoors = false,
    DoorClasses = {
        prop_door_rotating = true,
        func_door = true,
        func_door_rotating = true,
    },
}

local NET_OPEN = "GRM_Doors_Open"
local NET_ACT  = "GRM_Doors_Act"
local NET_INFO = "GRM_Doors_Info"

-----------------------------------------------------------------------
-- SHARED
-----------------------------------------------------------------------
local function mapName()
    return string.lower(game.GetMap() or "unknown")
end

function D.CanAdminDoors(ply)
    return IsValid(ply) and ply.IsPlayer and ply:IsPlayer() and ply:IsSuperAdmin() == true
end

function D.IsDoor(ent)
    if not IsValid(ent) then return false end
    local cls = ent:GetClass()
    local cfg = D.Config and D.Config.DoorClasses or {}
    if cfg[cls] then return true end
    return cls == "prop_door_rotating" or cls == "func_door" or cls == "func_door_rotating"
end

local function baseDoorID(ent)
    if not IsValid(ent) then return nil end
    local map = mapName()
    local mcid = ent.MapCreationID and ent:MapCreationID()
    if mcid and mcid > 0 then return string.format("%s_m%d", map, mcid) end
    local pos = ent:GetPos()
    return string.format("%s_%s_%.0f_%.0f_%.0f", map, ent:GetClass(),
        math.floor(pos.x + 0.5), math.floor(pos.y + 0.5), math.floor(pos.z + 0.5))
end

local function aabbOverlapRatio(a, b)
    if not IsValid(a) or not IsValid(b) or not a.WorldSpaceAABB or not b.WorldSpaceAABB then return 0, 0 end
    local amin, amax = a:WorldSpaceAABB()
    local bmin, bmax = b:WorldSpaceAABB()
    if not amin or not amax or not bmin or not bmax then return 0, 0 end
    local ox = math.max(0, math.min(amax.x, bmax.x) - math.max(amin.x, bmin.x))
    local oy = math.max(0, math.min(amax.y, bmax.y) - math.max(amin.y, bmin.y))
    local oz = math.max(0, math.min(amax.z, bmax.z) - math.max(amin.z, bmin.z))
    local areaA = math.max(1, (amax.x - amin.x) * (amax.y - amin.y))
    local areaB = math.max(1, (bmax.x - bmin.x) * (bmax.y - bmin.y))
    local heightA = math.max(1, amax.z - amin.z)
    local heightB = math.max(1, bmax.z - bmin.z)
    return (ox * oy) / math.min(areaA, areaB), oz / math.min(heightA, heightB)
end

function D.IsSamePhysicalDoor(a, b)
    if not IsValid(a) or not IsValid(b) or a == b or not D.IsDoor(a) or not D.IsDoor(b) then return false end
    if a:GetParent() == b or b:GetParent() == a then return true end
    local centerA = a.WorldSpaceCenter and a:WorldSpaceCenter() or a:GetPos()
    local centerB = b.WorldSpaceCenter and b:WorldSpaceCenter() or b:GetPos()
    local maxCenter = (D.Config and D.Config.DuplicateCenterDistance) or 64
    if centerA:DistToSqr(centerB) > maxCenter * maxCenter then return false end
    local xy, z = aabbOverlapRatio(a, b)
    return xy >= ((D.Config and D.Config.DuplicateXYOverlap) or 0.55)
        and z >= ((D.Config and D.Config.DuplicateZOverlap) or 0.72)
end

-- Все двери карты одним списком. Раньше здесь был ents.GetAll() (полный скан
-- ВСЕХ энтити) при каждой пересборке; теперь берём event-реестры GRM.Perf.
function D.AllDoors()
    local out, seen = {}, {}
    local classes = {}
    for cls in pairs((D.Config and D.Config.DoorClasses) or {}) do classes[#classes + 1] = cls end
    if #classes == 0 then classes = { "prop_door_rotating", "func_door", "func_door_rotating" } end
    for _, cls in ipairs(classes) do
        local list = (GRM.Perf and GRM.Perf.Entities) and GRM.Perf.Entities(cls) or ents.FindByClass(cls)
        for _, ent in ipairs(list) do
            if IsValid(ent) and not seen[ent] and D.IsDoor(ent) then
                seen[ent] = true
                out[#out + 1] = ent
            end
        end
    end
    return out
end

local function doorCenter(ent)
    return (ent.WorldSpaceCenter and ent:WorldSpaceCenter()) or ent:GetPos()
end

-- Пространственный хэш: ключ ячейки по центру двери.
local function cellKey(v, size)
    return math.floor(v.x / size) .. ":" .. math.floor(v.y / size) .. ":" .. math.floor(v.z / size)
end

-- Кандидаты в дубли: только двери из своей и 26 соседних ячеек.
local function buildNeighbourIndex(doors)
    local size = math.max(32, tonumber(D.Config and D.Config.IdentityCellSize) or 128)
    local grid, centers = {}, {}
    for i, ent in ipairs(doors) do
        local c = doorCenter(ent)
        centers[i] = c
        local key = cellKey(c, size)
        local cell = grid[key]
        if not cell then cell = {} grid[key] = cell end
        cell[#cell + 1] = i
    end
    return grid, centers, size
end

local function forEachCandidatePair(doors, fn)
    local grid, centers, size = buildNeighbourIndex(doors)
    local checked = {}
    for i = 1, #doors do
        local c = centers[i]
        local cx, cy, cz = math.floor(c.x / size), math.floor(c.y / size), math.floor(c.z / size)
        for dx = -1, 1 do
            for dy = -1, 1 do
                for dz = -1, 1 do
                    local cell = grid[(cx + dx) .. ":" .. (cy + dy) .. ":" .. (cz + dz)]
                    if cell then
                        for _, j in ipairs(cell) do
                            if j > i then
                                local key = i * 100000 + j
                                if not checked[key] then
                                    checked[key] = true
                                    fn(i, j, doors[i], doors[j])
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end
D.ForEachCandidatePair = forEachCandidatePair

--[[ Ликвидация фантомов.

     Фантом — это ВТОРОЕ полотно ровно на месте первого (дубликатор, тулза,
     кривой сейв аддона перма). Именно из-за них «дверь помнит не того
     владельца»: запись висит на одном полотне, а игрок жмёт E на другом.

     Правила сноса (по убыванию приоритета «кого оставить»):
       1. дверь, созданная картой, важнее созданной в рантайме;
       2. дверь с непустой записью владельца важнее «ничьей»;
       3. меньший MapCreationID / EntIndex важнее.
     Дубли самой карты по умолчанию НЕ сносятся (D.Config.PurgeMapDoors). ]]
function D.PurgeGhostDoors(opts)
    if not SERVER then return 0 end
    opts = istable(opts) and opts or {}
    local doors = D.AllDoors()
    if #doors < 2 then return 0 end

    local allowMap = opts.force == true or (D.Config and D.Config.PurgeMapDoors) == true
    local dry = opts.dry == true
    local toRemove, kept, report = {}, {}, {}

    local function isMap(ent) return (ent.CreatedByMap and ent:CreatedByMap()) == true end
    local function weight(ent)
        local w = 0
        if isMap(ent) then w = w + 1000 end
        local rec = D.GetRecord and select(1, D.GetRecord(ent))
        if istable(rec) and rec.owner_type and rec.owner_type ~= "none" then w = w + 100 end
        if istable(rec) and not rec._ephemeral then w = w + 10 end
        local mcid = ent.MapCreationID and ent:MapCreationID() or 0
        if mcid > 0 then w = w + math.max(0, 5 - mcid / 100000) end
        return w
    end

    -- Работаем по ГРУППАМ идентичности, а не по отдельным парам: три полотна
    -- «лесенкой» (A≈B, B≈C, но A и C напрямую перекрываются слабо) — это всё
    -- равно одна физическая дверь, и лишними должны стать оба дубля, а не один.
    D._canonicalDoorIDs, D._equivalentDoors, D._primaryDoors = nil, nil, nil
    D.RebuildDoorIdentityCache()

    for _, group in pairs(D._equivalentDoors or {}) do
        if istable(group) and #group > 1 then
            local best
            for _, ent in ipairs(group) do
                if IsValid(ent) then
                    if not best then
                        best = ent
                    else
                        local wb, we = weight(best), weight(ent)
                        if we > wb or (we == wb and ent:EntIndex() < best:EntIndex()) then best = ent end
                    end
                end
            end
            for _, ent in ipairs(group) do
                if IsValid(ent) and ent ~= best then
                    if isMap(ent) and not allowMap then
                        local c = doorCenter(ent)
                        report[#report + 1] = ("конфликт полотен КАРТЫ #%d и #%d на %.0f,%.0f,%.0f (не сношу без force)")
                            :format(ent:EntIndex(), best:EntIndex(), c.x, c.y, c.z)
                    else
                        toRemove[ent] = true
                        kept[ent] = best
                    end
                end
            end
        end
    end

    local purged = 0
    for ent in pairs(toRemove) do
        local keep = kept[ent]
        if IsValid(ent) then
            purged = purged + 1
            local c = doorCenter(ent)
            local line = ("[GRM Doors] %s фантомная дверь #%d (%s) на %.0f,%.0f,%.0f — оставлена #%d")
                :format(dry and "НАЙДЕНА" or "Ликвидирована", ent:EntIndex(), tostring(ent:GetClass()),
                    c.x, c.y, c.z, IsValid(keep) and keep:EntIndex() or 0)
            report[#report + 1] = line
            print(line)
            if not dry then ent:Remove() end
        end
    end

    if purged > 0 and not dry then D.InvalidateIdentity(true) end
    return purged, report
end

-- Полная пересборка идентичности. Union-Find, но пары берём только из
-- соседних ячеек сетки — на карте с 400 дверьми это ~4k сравнений вместо 80k.
function D.RebuildDoorIdentityCache()
    if D._buildingDoorIdentity then return end
    D._buildingDoorIdentity = true

    local doors = D.AllDoors()
    local parent = {}
    local function root(i)
        while parent[i] ~= i do parent[i] = parent[parent[i]] i = parent[i] end
        return i
    end
    local function unite(a, b)
        local ra, rb = root(a), root(b)
        if ra ~= rb then parent[rb] = ra end
    end
    for i = 1, #doors do parent[i] = i end
    forEachCandidatePair(doors, function(i, j, a, b)
        if D.IsSamePhysicalDoor(a, b) then unite(i, j) end
    end)

    local ids = {}
    local baseIDs = {}
    for i, ent in ipairs(doors) do
        local r = root(i)
        local id = baseDoorID(ent)
        baseIDs[i] = id
        if id and (not ids[r] or id < ids[r]) then ids[r] = id end
    end

    D._canonicalDoorIDs, D._equivalentDoors, D._primaryDoors = {}, {}, {}
    for i, ent in ipairs(doors) do
        local id = ids[root(i)] or baseIDs[i]
        D._canonicalDoorIDs[ent] = id
        local group = D._equivalentDoors[id]
        if not group then group = {} D._equivalentDoors[id] = group end
        group[#group + 1] = ent
    end
    for id, group in pairs(D._equivalentDoors) do
        table.sort(group, function(a, b) return tostring(baseDoorID(a)) < tostring(baseDoorID(b)) end)
        D._primaryDoors[id] = group[1]
        if SERVER then
            for i, ent in ipairs(group) do
                if GRM.Perf and GRM.Perf.NWBool then
                    GRM.Perf.NWBool(ent, "GRM_DoorAlias", i > 1)
                    GRM.Perf.NWString(ent, "GRM_DoorCanonicalID", id)
                else
                    ent:SetNWBool("GRM_DoorAlias", i > 1)
                    ent:SetNWString("GRM_DoorCanonicalID", id)
                end
            end
        end
    end

    D._identityBuiltAt = CurTime()
    D._buildingDoorIdentity = nil
    return D._equivalentDoors
end

-- Сброс кэша + отложенная (коалесцированная) пересборка. Раньше на КАЖДУЮ
-- созданную дверь заводился свой timer.Simple и свой полный ребилд.
function D.InvalidateIdentity(immediate)
    D._canonicalDoorIDs, D._equivalentDoors, D._primaryDoors = nil, nil, nil
    if immediate then return D.RebuildDoorIdentityCache() end
    if GRM.Perf and GRM.Perf.Coalesce then
        GRM.Perf.Coalesce("doors.identity.rebuild", 0.2, function()
            if not D._canonicalDoorIDs then D.RebuildDoorIdentityCache() end
        end)
    else
        timer.Create("GRM_Doors_IdentityRebuild", 0.2, 1, function()
            if not D._canonicalDoorIDs then D.RebuildDoorIdentityCache() end
        end)
    end
end


function D.GetDoorID(ent)
    if not IsValid(ent) or not D.IsDoor(ent) then return nil end
    if not D._canonicalDoorIDs or not D._canonicalDoorIDs[ent] then D.RebuildDoorIdentityCache() end
    return D._canonicalDoorIDs and D._canonicalDoorIDs[ent] or baseDoorID(ent)
end

function D.GetPrimaryDoor(ent)local id=D.GetDoorID(ent);return id and D._primaryDoors and D._primaryDoors[id]or ent end
function D.IsPrimaryDoor(ent)return IsValid(ent)and D.GetPrimaryDoor(ent)==ent end
function D.GetEquivalentDoors(ent)
    local id = D.GetDoorID(ent)
    local list = id and D._equivalentDoors and D._equivalentDoors[id] or nil
    if istable(list) and #list > 0 then return list end
    return IsValid(ent) and { ent } or {}
end

function D.GetPartnerDoor(ent)
    if not IsValid(ent) or not D.IsDoor(ent) then return nil end
    local parent = ent:GetParent()
    if IsValid(parent) and D.IsDoor(parent) then return parent end
    if ent._grmPartnerDoor ~= nil then
        if IsValid(ent._grmPartnerDoor) then return ent._grmPartnerDoor end
        ent._grmPartnerDoor = false
    end
    local posA = ent.WorldSpaceCenter and ent:WorldSpaceCenter() or ent:GetPos()
    local cls = ent:GetClass()
    local best, bestD = nil, 70 * 70
    for _, other in ipairs(ents.FindInSphere(posA, 70)) do
        if IsValid(other) and other ~= ent and D.IsDoor(other) and other:GetClass() == cls then
            local posB = other.WorldSpaceCenter and other:WorldSpaceCenter() or other:GetPos()
            local d = posA:DistToSqr(posB)
            if d >= (18 * 18) and d <= bestD and math.abs(posA.z - posB.z) <= 14 then
                best, bestD = other, d
            end
        end
    end
    if best then
        ent._grmPartnerDoor = best
        best._grmPartnerDoor = ent
        return best
    end
    ent._grmPartnerDoor = false
    return nil
end

function D.BreachDoor(ent, breakerPly, method)
    if not IsValid(ent) or not D.IsDoor(ent) then return false end
    method = method or "battering_ram"

    D.LockDoor(ent, false, { noAutoLock = true })
    ent:Fire("Open", "", 0.05)
    ent._grmBreachedUntil = CurTime() + 300
    ent:SetNWFloat("GRM_BreachedUntil", ent._grmBreachedUntil)

    local partner = D.GetPartnerDoor(ent)
    if IsValid(partner) then
        D.LockDoor(partner, false, { noAutoLock = true })
        partner:Fire("Open", "", 0.05)
        partner._grmBreachedUntil = CurTime() + 300
        partner:SetNWFloat("GRM_BreachedUntil", partner._grmBreachedUntil)
    end

    hook.Run("GRM_OnDoorBreached", breakerPly, ent, method)

    if GRM.Audit and GRM.Audit.Log then
        local actorName = IsValid(breakerPly) and breakerPly:Nick() or "Система"
        local actorKey = IsValid(breakerPly) and (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(breakerPly) or breakerPly:SteamID64()) or ""
        GRM.Audit.Log("door_breached", actorKey, actorName, {
            doorID = D.GetDoorID(ent),
            method = method,
            pos = tostring(ent:GetPos()),
        })
    end
    return true
end

function D.IsDoorLocked(ent)
    if not IsValid(ent) then return false end
    if ent:GetNWBool("GRM_DoorLocked", false) == true then return true end
    if SERVER and ent.GetInternalVariable then
        local b = ent:GetInternalVariable("m_bLocked")
        if b == true or b == 1 then return true end
    end
    return false
end

local function listHas(arr, value)
    if not istable(arr) or value == nil or value == "" then return false end
    for _, v in ipairs(arr) do if v == value then return true end end
    return false
end

local function recordPriority(rec)
    if not istable(rec) then return -1 end
    local score = 0
    if rec.owner_type and rec.owner_type ~= "none" then score = score + 100 end
    if tostring(rec.title or "") ~= "" then score = score + 10 end
    if rec.locked == true then score = score + 3 end
    if rec.ownable == false then score = score + 1 end
    return score
end

--[[ ПРОФИЛЬ КАТЕГОРИИ ПРОТИВ СОТРУДНИКА (общая логика сервера и стендов).
     actor = { faction, department, subdepartment, role, superadmin }.
     Пустая фракция — «человек с улицы»: его пускает только everyone/noFaction. ]]
function D.CategoryMatch(cat, actor)
    if not istable(cat) then return false end
    actor = istable(actor) and actor or {}
    if cat.everyone == true then return true end
    local fac = tostring(actor.faction or "")
    if fac == "" then return cat.noFaction == true end
    if listHas(cat.factions, fac) then return true end
    local dept = tostring(actor.department or "")
    if dept ~= "" and listHas(cat.departments, fac .. "|" .. dept) then return true end
    local sub = tostring(actor.subdepartment or "")
    if sub ~= "" and listHas(cat.subdepartments, fac .. "|" .. sub) then return true end
    local role = tostring(actor.role or "")
    if role ~= "" and listHas(cat.roles, fac .. "|" .. role) then return true end
    return false
end

--[[ ЕДИНОЕ СОСТОЯНИЕ ЗАМКА ФИЗИЧЕСКОЙ ДВЕРИ.

     Двустворчатая дверь — это ДВА полотна с двумя разными записями. Раньше
     `LockDoor` писала состояние только в запись того полотна, по которому
     кликнули, а сторож замков (`GRM_Doors_LockReconciler`) каждые пару секунд
     приводил КАЖДУЮ запись к её собственному значению. Итог: отпираешь
     створку — соседняя запись остаётся «заперта», сторож возвращает замок и
     дёргает общий сетевой флаг. Со стороны это выглядело как «дверь сама
     заперлась через несколько секунд после того, как её открыл суперадмин».

     Теперь у группы полотен одно состояние: при каждой смене замка ставится
     метка времени `lock_at`, а победителем считается САМАЯ СВЕЖАЯ запись.
     Функция чистая — гоняется в стенде без карты и энтити. ]]
function D.ResolveGroupLock(records)
    if not istable(records) then return false, 0 end
    local best, bestAt = nil, -1
    for _, rec in pairs(records) do
        if istable(rec) then
            local at = tonumber(rec.lock_at) or 0
            local locked = rec.locked == true
            if at > bestAt then
                best, bestAt = locked, at
            elseif at == bestAt then
                -- одинаковая давность: безопаснее оставить дверь запертой
                best = (best == true) or locked
            end
        end
    end
    if best == nil then return false, 0 end
    return best == true, math.max(bestAt, 0)
end

--- Согласованы ли записи группы (для диагностики и сторожа).
function D.GroupLockInSync(records)
    if not istable(records) then return true end
    local first, seen = nil, false
    for _, rec in pairs(records) do
        if istable(rec) then
            local locked = rec.locked == true
            if not seen then first, seen = locked, true
            elseif locked ~= first then return false end
        end
    end
    return true
end

--[[ Подпись набора данных окна двери: категории и структура организаций.
     Нужна клиенту, чтобы понять, можно ли обновить УЖЕ ОТКРЫТОЕ окно на
     месте (галочка в категории) или требуется полная пересборка (категорию
     создали/удалили/переименовали, в организации появился отдел). Пока
     подпись не менялась, окно не пересобирается — и список не улетает
     вверх после каждой галочки. ]]
function D.MenuSignature(cats, facTree)
    local parts = {}
    for _, c in ipairs(istable(cats) and cats or {}) do
        if istable(c) then parts[#parts + 1] = tostring(c.id) .. "=" .. tostring(c.name or "") end
    end
    table.sort(parts)
    local facParts = {}
    for _, f in ipairs(istable(facTree) and facTree or {}) do
        if istable(f) then
            local n = tostring(f.name or "")
            facParts[#facParts + 1] = n .. ":" .. tostring(#(f.departments or {}))
                .. "/" .. tostring(#(f.subdepartments or {})) .. "/" .. tostring(#(f.roles or {}))
        end
    end
    table.sort(facParts)
    return table.concat(parts, ";") .. "|" .. table.concat(facParts, ";")
end

--- Может ли сотрудник управлять замком двери этой категории.
function D.CategoryCanLock(cat, actor)
    if not istable(cat) then return true end
    if cat.lockAdminOnly == true then return (istable(actor) and actor.superadmin) == true end
    if cat.canLock == false then return false end
    return D.CategoryMatch(cat, actor)
end

--[[ Флаги профиля категории — общий список для сервера и редактора. ]]
D.CategoryFlags = {
    { key = "everyone",      label = "Открывать может каждый (общественная)",
      desc = "Дверь пропускает любого игрока, даже без организации" },
    { key = "noFaction",     label = "Пускать людей без организации",
      desc = "Гражданские без фракции считаются своими" },
    { key = "canLock",       label = "«Свои» могут запирать и отпирать",
      desc = "Снимите — проход останется, а замком управлять будет нельзя" },
    { key = "lockAdminOnly", label = "Замком управляет только администрация",
      desc = "Даже свои не смогут закрыть или открыть замок" },
    { key = "keepLocked",    label = "Дверь всегда заперта",
      desc = "Замок принудительно возвращается в закрытое состояние" },
    { key = "allowBuy",      label = "Разрешить приватизацию",
      desc = "Дверь можно купить или арендовать, несмотря на категорию" },
}

--- Чистая матрица допуска. actor = { superadmin, key, faction, role, canWarrant, hasWarrantOnOwner, canForce, categoryHas }
function D.EvaluateAccess(rec, actor)
    rec = istable(rec) and rec or { owner_type = "none", ownable = true }
    actor = istable(actor) and actor or {}
    local owned = rec.owner_type and rec.owner_type ~= "none"
    local super = actor.superadmin == true
    local key = tostring(actor.key or "")
    local fac = actor.faction
    local role = actor.role

    local isOwner = rec.owner_type == "player" and rec.owner_key == key and key ~= ""
    local isCo = false
    if istable(rec.co_owners) then
        for _, s in ipairs(rec.co_owners) do if s == key then isCo = true break end end
    end
    local isFac = rec.owner_type == "faction" and fac and rec.owner_faction == fac
    local isCat = rec.owner_type == "category" and fac and actor.categoryHas == true
    local acl = (fac and listHas(rec.factions, fac))
        or (fac and role and listHas(rec.roles, fac .. "|" .. tostring(role)))
        or (actor.aclCategory == true)
    local warrant = rec.owner_type == "player" and (rec.owner_key or "") ~= ""
        and actor.hasWarrantOnOwner == true and actor.canWarrant == true
    local hasKey = super or isOwner or isCo or isFac or isCat or acl or warrant or actor.propertyHas == true

    --[[ Замок и приватизация у категорийной двери живут по профилю категории:
         «Общественная» пускает всех, но запирать её нельзя никому, кроме
         администрации; «Государственная» может разрешить замок только своим. ]]
    local lock = hasKey
    local buy = (not owned) and rec.ownable ~= false
    if rec.owner_type == "category" then
        lock = super or actor.categoryLock == true
        if actor.categoryKeepLocked == true and not super then lock = false end
        buy = rec.ownable ~= false and actor.categoryBuy == true
    end

    return {
        walk_unlocked = true,
        walk_locked = hasKey,
        lock = lock,
        own = super or isOwner,
        buy = buy,
        admin = super,
        force = super or actor.canForce == true or warrant,
        is_owner = isOwner,
        has_key = hasKey,
    }
end

--- Один тост «дверь заперта» на одно нажатие E / одну физическую дверь.
function D.ShouldNotifyLockDeny(state, doorId, now, holdingUse, cooldown)
    state = istable(state) and state or {}
    doorId = tostring(doorId or "")
    now = tonumber(now) or 0
    cooldown = tonumber(cooldown) or 1.5
    if doorId == "" then return false, state end
    if state.burst and now < state.burst then return false, state end
    if state.id == doorId and (state.held == true or (state.expires and now < state.expires)) then
        return false, state
    end
    state.id = doorId
    state.held = holdingUse == true
    state.expires = now + cooldown
    state.burst = now + 0.35
    return true, state
end

function D.ClearLockDenyHold(state)
    if istable(state) then state.held = false end
    return state
end

-- Идентичность дверей нужна ДО входа игроков — приоритет early. Планировщик
-- GRM.Boot размажет её по тикам вместе с остальной стартовой работой, вместо
-- собственного timer.Simple в общей куче.
local function doorsIdentityBoot()
    if D.PurgeGhostDoors then D.PurgeGhostDoors() end
    D.RebuildDoorIdentityCache()
end
if GRM.Boot and GRM.Boot.Task then
    GRM.Boot.Task("doors.identity", "early", doorsIdentityBoot, { label = "Двери: идентичность и фантомы" })
else
    hook.Add("InitPostEntity", "GRM_Doors_BuildIdentityCache", function() timer.Simple(0.5, doorsIdentityBoot) end)
end
hook.Add("PostCleanupMap", "GRM_Doors_RebuildIdentityCache", function()
    timer.Simple(.2, function()
        if D.PurgeGhostDoors then D.PurgeGhostDoors() end
        D.RebuildDoorIdentityCache()
    end)
end)

-- Дверь, созданная в рантайме (тулза/дупликатор/перм), пересобирает
-- идентичность и отложенно чистит фантомов. Раньше на КАЖДУЮ созданную
-- entity (не только дверь!) заводился отдельный timer.Simple(0.1) с полным
-- O(n^2) ребилдом — на загрузке карты это давало заметный фриз. Теперь всё
-- склеивается в один коалесцированный проход.
local function scheduleDoorMaintenance()
    if not (GRM.Perf and GRM.Perf.Coalesce) then
        timer.Create("GRM_Doors_Maintenance", 0.3, 1, function()
            D.RebuildDoorIdentityCache()
            if SERVER and D.PurgeGhostDoors then D.PurgeGhostDoors() end
        end)
        return
    end
    GRM.Perf.Coalesce("doors.maintenance", 0.3, function()
        D.RebuildDoorIdentityCache()
        if SERVER and D.PurgeGhostDoors and GRM.Perf.Throttle("doors.purge", 2) then
            D.PurgeGhostDoors()
        end
    end)
end
D.ScheduleMaintenance = scheduleDoorMaintenance

hook.Add("OnEntityCreated", "GRM_Doors_IdentityCreated", function(ent)
    -- Класс у только что созданной entity уже доступен для prop_door_rotating
    -- и func_door*, поэтому фильтруем СРАЗУ и не платим таймером за каждый проп.
    if not ent or not ent.GetClass then return end
    local cls = ent:GetClass()
    local cfg = D.Config and D.Config.DoorClasses or {}
    if not (cfg[cls] or cls == "prop_door_rotating" or cls == "func_door" or cls == "func_door_rotating") then return end
    D._canonicalDoorIDs, D._equivalentDoors, D._primaryDoors = nil, nil, nil
    scheduleDoorMaintenance()
end)

hook.Add("EntityRemoved", "GRM_Doors_IdentityRemoved", function(ent)
    if D._canonicalDoorIDs and D._canonicalDoorIDs[ent] then
        D.InvalidateIdentity(false)
    end
end)


if SERVER then
    --[[ ── ДИАГНОСТИКА И ПОЛНАЯ ПЕРЕСБОРКА ДВЕРЕЙ ──────────────────────────

         D.BuildAuditReport()  — что сейчас на карте (без изменений);
         D.RebuildAll(opts)    — полная пересборка:
             1. заново строит идентичность (пространственный хэш + union-find);
             2. ликвидирует фантомные полотна (dry — только показать);
             3. схлопывает записи-дубли на канонический ID;
             4. чинит «сироты» — записи без двери на карте;
             5. переприменяет визуал/замки и сохраняет БД.
         opts = { dry=true, force=true, dropOrphans=true } ]]

    function D.BuildAuditReport()
        D.RebuildDoorIdentityCache()
        local groups = D._equivalentDoors or {}
        local doors, pairsCount = 0, 0
        local groupCount, ambiguousCount, aliasCount = 0, 0, 0
        local ownedCount, ownerlessCount = 0, 0
        local classCounts, conflicts = {}, {}

        for _, ent in ipairs(D.AllDoors()) do
            doors = doors + 1
            if D.GetPartnerDoor and D.GetPartnerDoor(ent) then pairsCount = pairsCount + 1 end
            local cls = ent:GetClass()
            classCounts[cls] = (classCounts[cls] or 0) + 1
            local rec = D.GetRecord and select(1, D.GetRecord(ent))
            if istable(rec) and rec.owner_type and rec.owner_type ~= "none" then
                ownedCount = ownedCount + 1
            else
                ownerlessCount = ownerlessCount + 1
            end
        end

        for id, group in pairs(groups) do
            if istable(group) and #group > 1 then
                groupCount = groupCount + 1
                aliasCount = aliasCount + (#group - 1)
                local seenOwners = {}
                for _, e in ipairs(group) do
                    local rec = D.GetRecord and select(1, D.GetRecord(e))
                    local owner = istable(rec)
                        and (tostring(rec.owner_type or "none") .. ":" ..
                             tostring(rec.owner_key or rec.owner_faction or rec.owner_category or ""))
                        or "none:"
                    seenOwners[owner] = true
                end
                if table.Count(seenOwners) > 1 then
                    ambiguousCount = ambiguousCount + 1
                    conflicts[#conflicts + 1] = id
                end
            end
        end

        -- Записи-сироты: в БД есть, а двери с таким каноническим ID на карте нет.
        local orphans = {}
        for id, rec in pairs((D.Data and D.Data.doors) or {}) do
            if istable(rec) and not groups[id] then orphans[#orphans + 1] = id end
        end
        table.sort(orphans)

        local classStr = {}
        for cls, n in pairs(classCounts) do classStr[#classStr + 1] = cls .. "=" .. n end
        table.sort(classStr)

        return {
            doors = doors,
            classes = classStr,
            groups = groupCount,
            aliases = aliasCount,
            doublePairs = math.floor(pairsCount / 2),
            owned = ownedCount,
            ownerless = ownerlessCount,
            ambiguous = ambiguousCount,
            conflicts = conflicts,
            orphans = orphans,
            records = table.Count((D.Data and D.Data.doors) or {}),
        }
    end

    function D.RebuildAll(opts)
        opts = istable(opts) and opts or {}
        local dry = opts.dry == true
        local log = {}
        local function add(fmt, ...)
            local line = select("#", ...) > 0 and string.format(fmt, ...) or fmt
            log[#log + 1] = line
            print("[GRM Doors Rebuild] " .. line)
        end

        local before = D.BuildAuditReport()
        add("до: дверей %d, физ-групп %d (лишних полотен %d), записей %d, сирот %d, конфликтов %d",
            before.doors, before.groups, before.aliases, before.records, #before.orphans, before.ambiguous)

        -- 1. Идентичность с нуля.
        D._canonicalDoorIDs, D._equivalentDoors, D._primaryDoors = nil, nil, nil
        D.RebuildDoorIdentityCache()

        -- 2. Фантомы.
        local purged, purgeLog = D.PurgeGhostDoors({ dry = dry, force = opts.force == true })
        add("фантомных полотен %s: %d", dry and "найдено" or "ликвидировано", purged or 0)
        for _, l in ipairs(purgeLog or {}) do log[#log + 1] = l end

        -- 3. Записи-дубли -> канонический ID.
        local collapsed = 0
        if not dry then
            D._canonicalDoorIDs, D._equivalentDoors, D._primaryDoors = nil, nil, nil
            D.RebuildDoorIdentityCache()
            collapsed = D.CollapseDuplicateRecords() or 0
        end
        add("записей-дублей схлопнуто: %d", collapsed)

        -- 4. Сироты (по умолчанию только показываем — дверь может быть просто
        --    не заспавнена аддоном перма на момент запуска).
        local after = D.BuildAuditReport()
        if #after.orphans > 0 then
            add("записей без двери на карте: %d%s", #after.orphans,
                opts.dropOrphans and (dry and " (будут удалены)" or " — удалены") or " (оставлены; удалить: grm_door_rebuild orphans)")
            if opts.dropOrphans and not dry then
                for _, id in ipairs(after.orphans) do D.Data.doors[id] = nil end
            end
            for i = 1, math.min(12, #after.orphans) do add("   сирота: %s", after.orphans[i]) end
        end

        -- 5. Переприменяем визуал и сохраняем.
        if not dry then
            for _, ent in ipairs(D.AllDoors()) do
                local rec = D.GetRecord and select(1, D.GetRecord(ent))
                if istable(rec) and not rec._ephemeral then
                    D.ApplyRecordVisual(ent, rec)
                elseif ent.GetInternalVariable then
                    local eng = ent:GetInternalVariable("m_bLocked")
                    D.SyncLockNW(ent, eng == true or eng == 1)
                end
            end
            D.SaveDoors()
        end

        local final = D.BuildAuditReport()
        add("после: дверей %d, физ-групп %d (лишних полотен %d), записей %d, конфликтов %d",
            final.doors, final.groups, final.aliases, final.records, final.ambiguous)
        if dry then add("РЕЖИМ ПРОВЕРКИ (dry): ничего не изменено. Запуск без 'dry' применит.") end
        return log, final
    end

    local function printLines(ply, lines)
        for _, l in ipairs(lines) do
            if IsValid(ply) then ply:ChatPrint(l) else print(l) end
        end
    end

    function D.RunAudit(ply, purge)
        local ghost = 0
        if purge ~= false and D.PurgeGhostDoors then ghost = D.PurgeGhostDoors() or 0 end
        local r = D.BuildAuditReport()
        local lines = {
            "[GRM Door Audit] Дверей: " .. r.doors .. " | Классы: " .. table.concat(r.classes, ", "),
            "  Физических групп (дублей-полотен): " .. r.groups .. " | лишних полотен в группах: " .. r.aliases ..
                " | Двустворчатых пар: " .. r.doublePairs,
            "  С владельцем: " .. r.owned .. " | Без владельца: " .. r.ownerless,
            "  Групп с РАЗНЫМИ владельцами (конфликт «две двери за одну»): " .. r.ambiguous,
            "  Записей в БД: " .. r.records .. " | из них без двери на карте: " .. #r.orphans,
            "  Ликвидировано фантомов сейчас: " .. ghost .. " | Полная пересборка: grm_door_rebuild (или /door_rebuild)",
        }
        for i = 1, math.min(6, #r.conflicts) do
            lines[#lines + 1] = "   конфликт: " .. tostring(r.conflicts[i])
        end
        printLines(ply, lines)
        return r
    end

    concommand.Add("grm_door_audit", function(ply)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        D.RunAudit(ply, true)
    end)

    concommand.Add("grm_door_rebuild", function(ply, _, args)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        local opts = {}
        for _, a in ipairs(args or {}) do
            a = string.lower(tostring(a))
            if a == "dry" or a == "check" or a == "проверка" then opts.dry = true end
            if a == "force" then opts.force = true end
            if a == "orphans" or a == "сироты" then opts.dropOrphans = true end
        end
        local log = D.RebuildAll(opts)
        printLines(ply, log)
    end)
end

-----------------------------------------------------------------------
-- SERVER
-----------------------------------------------------------------------
if SERVER then
    util.AddNetworkString(NET_OPEN)
    util.AddNetworkString(NET_ACT)
    util.AddNetworkString(NET_INFO)
    util.AddNetworkString("GRM_Doors_Admin")
    util.AddNetworkString("GRM_Doors_AdminAct")

    if GRM._doorsCoreActive then
        print("[GRM Doors] Вторая копия sh_grm_doors.lua пропущена")
        return
    end
    GRM._doorsCoreActive = true

    local DATA_DIR = "grm_doors"
    D.Data = D.Data or { doors = {}, categories = {}, warrants = {} }

    local function jsonT(txt)
        local ok, t = pcall(util.JSONToTable, txt, false, true)
        return (ok and istable(t)) and t or nil
    end

    local function ensureDir()
        if not file.IsDir(DATA_DIR, "DATA") then file.CreateDir(DATA_DIR) end
    end

    local function notify(ply, msg, r, g, b)
        if not IsValid(ply) then return end
        if GRM.Notify then GRM.Notify(ply, msg, r or 100, g or 220, b or 100) return end
        net.Start(NET_INFO) net.WriteString(tostring(msg or "")) net.Send(ply)
    end

    local function charKey(v)
        if IsValid(v) and v.IsPlayer and v:IsPlayer() then
            if GRM.Identity and GRM.Identity.CharacterKey then return GRM.Identity.CharacterKey(v) end
            return tostring(v:SteamID64() or "") .. ":char1"
        end
        local s = tostring(v or "")
        if s:match(":char[1-3]$") then return s end
        if s:match("^%d+$") then return s .. ":char1" end
        return s
    end

    local function utf8cut(s, n)
        if GRM.Utf8Sub then return GRM.Utf8Sub(s, n) end
        return string.sub(tostring(s or ""), 1, n)
    end

    local function toArray(src)
        local out, seen = {}, {}
        if not istable(src) then return out end
        if #src > 0 then
            for _, v in ipairs(src) do
                local s = tostring(v or "")
                if s ~= "" and not seen[s] then seen[s] = true out[#out + 1] = s end
            end
            return out
        end
        for k, v in pairs(src) do
            local s
            if v == true then s = tostring(k)
            elseif isstring(v) then s = v
            elseif isstring(k) then s = k end
            if s and s ~= "" and not seen[s] then seen[s] = true out[#out + 1] = s end
        end
        return out
    end

    local function rpNick(ply)
        if not IsValid(ply) then return "" end
        local rp = ply.GetNWString and ply:GetNWString("GRM_RPName", "") or ""
        if rp ~= "" then return rp end
        return ply:Nick()
    end

    local function nickOf(key)
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(p) and (charKey(p) == key or p:SteamID64() == key or p:SteamID() == key) then
                return rpNick(p)
            end
        end
        return key
    end

    local function nextWarrantNumber()
        D.Data = D.Data or {}
        local n = math.max(1, math.floor(tonumber(D.Data.warrantSeq) or 0) + 1)
        D.Data.warrantSeq = n
        return n
    end

    local function doorsFile() ensureDir() return DATA_DIR .. "/" .. mapName() .. ".json" end
    local function catFile() ensureDir() return DATA_DIR .. "/categories.json" end
    local function warFile() ensureDir() return DATA_DIR .. "/warrants.json" end

    local function writeJSON(path, data)
        local ok, txt = pcall(util.TableToJSON, data, true)
        if not (ok and isstring(txt)) then return false end
        file.Write(path, txt)
        return file.Read(path, "DATA") == txt
    end

    local function normalizeRec(raw)
        if not istable(raw) then return nil end
        local id = tostring(raw.id or "")
        if id == "" then return nil end
        local ot = raw.owner_type
        if ot ~= "player" and ot ~= "faction" and ot ~= "category" then ot = "none" end
        return {
            id = id,
            title = utf8cut(tostring(raw.title or ""), 64),
            owner_type = ot,
            owner_key = tostring(raw.owner_key or raw.owner_sid or ""),
            owner_nick = utf8cut(tostring(raw.owner_nick or ""), 64),
            owner_faction = tostring(raw.owner_faction or ""),
            owner_category = tostring(raw.owner_category or ""),
            co_owners = toArray(raw.co_owners),
            factions = toArray(raw.factions),
            roles = toArray(raw.roles),
            categories = toArray(raw.categories),
            rent_until = tonumber(raw.rent_until) or 0,
            rent_price = math.max(0, math.floor(tonumber(raw.rent_price) or (D.Config.RentPrice or 5000))),
            locked = raw.locked == true,
            -- метка последней смены замка: по ней сторож понимает, какая из
            -- записей створок свежее (см. D.ResolveGroupLock)
            lock_at = math.max(0, math.floor(tonumber(raw.lock_at) or 0)),
            ownable = raw.ownable ~= false,
        }
    end

    local function defaultRec(id, ent)
        local locked = false
        if IsValid(ent) and ent.GetInternalVariable then
            local b = ent:GetInternalVariable("m_bLocked")
            locked = (b == true or b == 1)
        end
        return {
            id = id, title = "", owner_type = "none", owner_key = "", owner_nick = "",
            owner_faction = "", owner_category = "", co_owners = {}, factions = {},
            roles = {}, categories = {}, rent_until = 0,
            rent_price = tonumber(D.Config.RentPrice) or 5000,
            locked = locked, lock_at = 0, ownable = true, _ephemeral = true,
        }
    end

    local function recDirty(rec)
        if not istable(rec) then return false end
        if rec.owner_type and rec.owner_type ~= "none" then return true end
        if tostring(rec.title or "") ~= "" then return true end
        if rec.ownable == false then return true end
        if rec.locked == true then return true end
        if rec.rent_until and rec.rent_until > 0 then return true end
        if rec.rent_price and rec.rent_price ~= (D.Config.RentPrice or 5000) then return true end
        if #(rec.co_owners or {}) > 0 or #(rec.factions or {}) > 0
            or #(rec.roles or {}) > 0 or #(rec.categories or {}) > 0 then return true end
        return false
    end

    function D.CollapseDuplicateRecords()
        if not D._equivalentDoors then D.RebuildDoorIdentityCache()end;local changed=0
        for canonical,group in pairs(D._equivalentDoors or{})do
            local best,bestScore=D.Data.doors[canonical],recordPriority(D.Data.doors[canonical]);local aliases={}
            for _,ent in ipairs(group)do local alias=baseDoorID(ent);if alias then aliases[alias]=true;local candidate=D.Data.doors[alias];local score=recordPriority(candidate);if score>bestScore then best,bestScore=candidate,score end end end
            if best then best.id=canonical;D.Data.doors[canonical]=best end
            for alias in pairs(aliases)do if alias~=canonical and D.Data.doors[alias]then D.Data.doors[alias]=nil;changed=changed+1 end end
        end
        return changed
    end
    --[[ Доступ двери к рангу хранится строкой «фракция|ключ_ранга». При смене
         ключа ранга строки надо переписать, иначе дверь перестаёт узнавать
         своих сотрудников (заказ владельца 19.08). ]]
    hook.Add("GRM_FactionRoleKeyRenamed", "GRM_Doors_RoleKey", function(factionName, oldKey, newKey)
        local from, to = tostring(factionName) .. "|" .. tostring(oldKey), tostring(factionName) .. "|" .. tostring(newKey)
        local changed = 0
        for _, rec in pairs((D.Data and D.Data.doors) or {}) do
            if istable(rec) and istable(rec.roles) then
                for i, v in ipairs(rec.roles) do
                    if v == from then rec.roles[i] = to changed = changed + 1 end
                end
            end
        end
        if changed > 0 then
            D.SaveDoors()
            print(("[GRM Doors] ключ ранга перенесён в дверях: %s → %s (записей %d)"):format(from, to, changed))
        end
    end)

    local function buildDoorsPayload()
        D.CollapseDuplicateRecords()
        local arr = {}
        for id, rec in pairs(D.Data.doors or {}) do
            if istable(rec) and recDirty(rec) then
                rec.id = id
                rec._ephemeral = nil
                arr[#arr + 1] = rec
            end
        end
        table.sort(arr, function(a, b) return tostring(a.id) < tostring(b.id) end)
        return { version = 3, doors = arr }
    end

    --- Немедленная запись (выключение сервера, ручные команды).
    function D.SaveDoorsNow()
        return writeJSON(doorsFile(), buildDoorsPayload())
    end

    --[[ Обычное сохранение идёт через очередь GRM.Save: замок дёргается часто
         (ключи, сторож, автоблокировка), а каждая запись реестра дверей на
         диск в горячем пути — это микрофриз. Если слоя нет — пишем сразу. ]]
    if GRM.Save and GRM.Save.Register then
        D._saveRegistered = GRM.Save.Register("grm_doors", {
            file = doorsFile(), delay = 3, priority = 5,
            label = "двери", build = buildDoorsPayload,
        })
    end

    function D.SaveDoors(why)
        if D._saveRegistered and GRM.Save and GRM.Save.Mark then
            return GRM.Save.Mark("grm_doors", why or "doors")
        end
        return D.SaveDoorsNow()
    end

    function D.LoadDoors()
        D.Data.doors = {}
        local path = doorsFile()
        if not file.Exists(path, "DATA") then return true end
        local raw = file.Read(path, "DATA") or ""
        local t = jsonT(raw)
        if not t then
            local bak = path .. ".corrupt." .. os.time()
            file.Write(bak, raw)
            ErrorNoHalt("[GRM Doors] " .. path .. " повреждён, копия: " .. bak .. "\n")
            return false
        end
        local list = istable(t.doors) and t.doors or (istable(t[1]) and t or {})
        for _, rawRec in ipairs(list) do
            local rec = normalizeRec(rawRec)
            if rec and rec.id:sub(1, 5) ~= "pair_" then
                D.Data.doors[rec.id] = rec
            end
        end
        timer.Simple(1, function()
            for _, ent in ipairs(D.AllDoors()) do
                if IsValid(ent) then
                    local rec = select(1, D.GetRecord(ent))
                    if rec and not rec._ephemeral then
                        D.ApplyRecordVisual(ent, rec)
                    else
                        local eng = ent.GetInternalVariable and (ent:GetInternalVariable("m_bLocked") == true or ent:GetInternalVariable("m_bLocked") == 1)
                        D.SyncLockNW(ent, eng)
                    end
                end
            end
            local collapsed=D.CollapseDuplicateRecords();if collapsed>0 then D.SaveDoors();print("[GRM Doors] удалено фантомных записей-дублей: "..collapsed)end
        end)
        print("[GRM Doors] Загружено дверей на карте " .. mapName() .. ": " .. table.Count(D.Data.doors))
        return true
    end

    --[[ КАТЕГОРИИ ДОСТУПА v4 (заказ владельца 19.08).
         Раньше категория умела ровно одно: список фракций. Теперь это полный
         профиль доступа к двери:
           factions/departments/subdepartments/roles — кто «свой»;
           everyone   — открывать может каждый (общественная дверь);
           noFaction  — пускать людей без организации;
           canLock    — «свои» могут запирать/отпирать;
           lockAdminOnly — замком управляет только администрация;
           keepLocked — дверь всегда заперта (проходной режим отключён);
           allowBuy   — дверь можно приватизировать, несмотря на категорию.
         Пример владельца: гаражные ворота «Общественная» — everyone = true,
         canLock = false: открыть может любой, а запереть — никто. ]]
    function D.NormalizeCategory(raw, fallbackID)
        raw = istable(raw) and raw or {}
        local id = tostring(raw.id or fallbackID or "")
        local c = {
            id = id,
            name = utf8cut(tostring(raw.name or id), 48),
            factions       = toArray(raw.factions),
            departments    = toArray(raw.departments),
            subdepartments = toArray(raw.subdepartments),
            roles          = toArray(raw.roles),
            everyone      = raw.everyone == true,
            noFaction     = raw.noFaction == true,
            canLock       = raw.canLock ~= false,
            lockAdminOnly = raw.lockAdminOnly == true,
            keepLocked    = raw.keepLocked == true,
            allowBuy      = raw.allowBuy == true,
        }
        if c.name == "" then c.name = id end
        return c
    end

    function D.SaveCategories()
        local arr = {}
        for id, c in pairs(D.Data.categories or {}) do
            if istable(c) then arr[#arr + 1] = D.NormalizeCategory(c, id) end
        end
        table.sort(arr, function(a, b) return tostring(a.id) < tostring(b.id) end)
        return writeJSON(catFile(), { version = 4, categories = arr })
    end

    function D.LoadCategories()
        D.Data.categories = {}
        if not file.Exists(catFile(), "DATA") then
            D.Data.categories = {
                police = D.NormalizeCategory({ id = "police", name = "Полиция и Силовики" }),
                med    = D.NormalizeCategory({ id = "med",    name = "Медицинская служба" }),
                gov    = D.NormalizeCategory({ id = "gov",    name = "Правительство / Мэрия" }),
                public = D.NormalizeCategory({ id = "public", name = "Общественная",
                    everyone = true, canLock = false }),
            }
            D.SaveCategories()
            return true
        end
        local t = jsonT(file.Read(catFile(), "DATA") or "")
        if not istable(t) then return false end
        local list = istable(t.categories) and t.categories or (istable(t[1]) and t or nil)
        -- Старые файлы (version 3: только id/name/factions) читаются как есть —
        -- недостающие поля профиля добираются значениями по умолчанию.
        if list then
            for _, c in ipairs(list) do
                if istable(c) and isstring(c.id) then
                    D.Data.categories[c.id] = D.NormalizeCategory(c, c.id)
                end
            end
        else
            for id, c in pairs(t) do
                if istable(c) and id ~= "version" then
                    local cid = tostring(c.id or id)
                    D.Data.categories[cid] = D.NormalizeCategory(c, cid)
                end
            end
        end
        return true
    end

    function D.SaveWarrants()
        local arr = {}
        for sid, w in pairs(D.Data.warrants or {}) do
            if istable(w) then w.sid = sid arr[#arr + 1] = w end
        end
        return writeJSON(warFile(), { version = 4, warrants = arr, warrantSeq = tonumber(D.Data.warrantSeq) or 0 })
    end

    function D.LoadWarrants()
        D.Data.warrants = {}
        D.Data.warrantSeq = 0
        if not file.Exists(warFile(), "DATA") then return true end
        local t = jsonT(file.Read(warFile(), "DATA") or "")
        if not istable(t) then return false end
        D.Data.warrantSeq = math.max(0, math.floor(tonumber(t.warrantSeq) or 0))
        local list = istable(t.warrants) and t.warrants or (istable(t[1]) and t or {})
        local maxN = D.Data.warrantSeq
        for _, w in ipairs(list) do
            if istable(w) and isstring(w.sid) then
                D.Data.warrants[w.sid] = w
                local n = tonumber(w.number) or 0
                if n > maxN then maxN = n end
            end
        end
        D.Data.warrantSeq = maxN
        return true
    end

    function D.CreateCategory(id, name)
        id = string.lower(tostring(id or "")):gsub("[^%w_%-]", "")
        if id == "" or #id > 32 then return nil, "Некорректный ID категории" end
        D.Data.categories = D.Data.categories or {}
        if D.Data.categories[id] then return nil, "Категория уже существует" end
        name = utf8cut(tostring(name or ""), 48)
        if name == "" then name = id end
        local c = D.NormalizeCategory({ id = id, name = name })
        D.Data.categories[id] = c
        D.SaveCategories()
        return c
    end

    function D.RenameCategory(id, name)
        local c = D.Data.categories and D.Data.categories[tostring(id or "")]
        if not istable(c) then return nil, "Категория не найдена" end
        name = utf8cut(tostring(name or ""), 48)
        if name == "" then return nil, "Пустое название" end
        c.name = name
        D.SaveCategories()
        return true
    end

    function D.DeleteCategory(id)
        id = tostring(id or "")
        if not (D.Data.categories and D.Data.categories[id]) then return nil, "Категория не найдена" end
        D.Data.categories[id] = nil
        for _, rec in pairs(D.Data.doors or {}) do
            if istable(rec) then
                if rec.owner_type == "category" and rec.owner_category == id then
                    rec.owner_type, rec.owner_category = "none", ""
                end
                if istable(rec.categories) then
                    local nextCats = {}
                    for _, cid in ipairs(rec.categories) do if cid ~= id then nextCats[#nextCats + 1] = cid end end
                    rec.categories = nextCats
                end
            end
        end
        D.SaveDoors()
        D.SaveCategories()
        return true
    end

    function D.CategorySetFaction(id, factionName, on)
        local c = D.Data.categories and D.Data.categories[tostring(id or "")]
        if not istable(c) then return nil, "Категория не найдена" end
        factionName = tostring(factionName or "")
        if factionName == "" then return nil, "Не указана фракция" end
        c.factions = toArray(c.factions)
        local nextF = {}
        for _, fn in ipairs(c.factions) do if fn ~= factionName then nextF[#nextF + 1] = fn end end
        if on then nextF[#nextF + 1] = factionName end
        c.factions = nextF
        D.SaveCategories()
        return true
    end

    function D.CategoryOfDoor(rec)
        if not (istable(rec) and rec.owner_type == "category") then return nil end
        return D.Data.categories and D.Data.categories[tostring(rec.owner_category or "")]
    end

    local function factionInCategory(factionName, catId, actor)
        local cat = D.Data.categories and D.Data.categories[catId]
        if not istable(cat) then return false end
        actor = istable(actor) and actor or { faction = factionName }
        return D.CategoryMatch(cat, actor)
    end

    --[[ КТО ЭТОТ ЧЕЛОВЕК ДЛЯ ДВЕРИ.

         Раньше принадлежность бралась ТОЛЬКО из таблицы состава фракций.
         Если состав ключуется иначе (SteamID против ключа персонажа) или
         игрок ещё не «подтянулся» в таблицу, функция возвращала пустоту —
         и категории с фракциями просто не работали: ключи не открывали
         ведомственные двери (заказ владельца 21.08).

         Теперь есть запасной путь — NW-поля, на которые смотрит весь
         остальной GRM (шапка над головой, зарплата, доступы). ]]
    local function playerFactionInfo(ply)
        if not IsValid(ply) then return nil, nil, nil, nil end

        if istable(Factions) and GRM.Identity and GRM.Identity.FactionMember then
            for name, f in pairs(Factions) do
                if istable(f) and istable(f.Members) then
                    local m = GRM.Identity.FactionMember(f, ply)
                    if istable(m) then
                        return name, m.Role, m.Department, tostring(m.Subdepartment or m.Subdept or "")
                    end
                end
            end
        end

        local nwFac = ply.GetNWString and ply:GetNWString("GRM_Faction", "") or ""
        if nwFac ~= "" then
            return nwFac,
                ply:GetNWString("GRM_Role", ""),
                ply:GetNWString("GRM_Department", ""),
                ply:GetNWString("GRM_Subdepartment", "")
        end
        return nil, nil, nil, nil
    end

    function D.HasWarrant(plyOrSid, warrantType)
        local sid = charKey(plyOrSid)
        if sid == "" then return false end
        local w = D.Data.warrants and D.Data.warrants[sid]
        if not istable(w) then return false end
        local exp = tonumber(w.expires or w.expiresAt) or 0
        if exp > 0 and os.time() > exp then
            D.Data.warrants[sid] = nil
            D.SaveWarrants()
            return false
        end
        if w.status and w.status ~= "active" then return false end
        if warrantType and warrantType ~= "" then
            local t = tostring(w.type or "search")
            if t ~= warrantType and t ~= "all" then return false end
        end
        return true, w
    end

    function D.HasPropertyWarrant(propertyId, warrantType)
        propertyId = tostring(propertyId or "")
        if propertyId == "" or not istable(D.Data.warrants) then return false end
        for sid, w in pairs(D.Data.warrants) do
            if istable(w) and tostring(w.propertyId or "") == propertyId then
                local exp = tonumber(w.expires or w.expiresAt) or 0
                if exp > 0 and os.time() <= exp and (not w.status or w.status == "active") then
                    if not warrantType or warrantType == "" or w.type == warrantType or w.type == "all" then
                        return true, w
                    end
                end
            end
        end
        return false
    end

    function D.SyncLockNW(ent, locked)
        if not IsValid(ent) then return end
        for _, equivalent in ipairs(D.GetEquivalentDoors(ent)) do
            if IsValid(equivalent) then equivalent:SetNWBool("GRM_DoorLocked", locked == true) end
        end
        local partner = D.GetPartnerDoor(ent)
        if IsValid(partner) then partner:SetNWBool("GRM_DoorLocked", locked == true) end
    end

    local function ownerLabel(rec)
        if not rec or rec.owner_type == "none" then return "" end
        if rec.owner_type == "player" then return rec.owner_nick or "" end
        if rec.owner_type == "faction" then return "Фракция: " .. tostring(rec.owner_faction) end
        if rec.owner_type == "category" then
            local cc = D.Data.categories and D.Data.categories[rec.owner_category]
            return "Категория: " .. ((istable(cc) and tostring(cc.name or rec.owner_category)) or tostring(rec.owner_category))
        end
        return ""
    end

    function D.ApplyRecordVisual(ent, rec)
        if not IsValid(ent) then return end
        for _, equivalent in ipairs(D.GetEquivalentDoors(ent)) do
            if IsValid(equivalent) then
                equivalent:SetNWString("GRM_DoorTitle", rec and rec.title or "")
                equivalent:SetNWString("GRM_DoorOwner", ownerLabel(rec))
            end
        end
        local partner = D.GetPartnerDoor(ent)
        if IsValid(partner) then
            partner:SetNWString("GRM_DoorTitle", rec and rec.title or "")
            partner:SetNWString("GRM_DoorOwner", ownerLabel(rec))
        end
        D.SyncLockNW(ent, rec and rec.locked == true)
    end

    --[[ ГОТОВА ЛИ БАЗА ДВЕРЕЙ (жалоба владельца 31.08: «после
         перезапуска было несколько минут/секунд, что ключи дверные по
         дверям не срабатывали»).

         База владельцев грузится не мгновенно: задача "doors.db" стоит
         в очереди планировщика (GRM.Boot), а он выполняет задачи
         порциями по 2 мс на тик, чтобы не ронять tickrate на старте.
         До её выполнения D.Data.doors пуста.

         Беда в том, что пустая база НЕОТЛИЧИМА от «дверь ничья»:
         getRecord не находил запись и заводил новую, со свежими
         правами. Владелец двери на несколько секунд превращался в
         постороннего — ключи отвечали «У вас нет ключей от этой
         двери» либо молча ничего не делали.

         Здесь одна проверка на всех: пока база не поднята, любой
         запрос прав её ДОЖИДАЕТСЯ (Ensure выполняет задачу немедленно,
         вне очереди). Это дешевле, чем пускать игрока в чужую дверь. ]]
    local function ensureDoorsDB()
        if not GRM.Boot or not GRM.Boot.Ensure then return true end
        if GRM.Boot.Done and GRM.Boot.Done("doors.db") then return true end
        GRM.Boot.Ensure("doors.db", "запрос прав на дверь")
        return true
    end
    D.EnsureDB = ensureDoorsDB

    local function getRecord(ent)
        local id = D.GetDoorID(ent)
        if not id then return nil, nil end
        -- Без этого свежая карта отдаёт «ничью» дверь вместо купленной.
        ensureDoorsDB()
        D.Data.doors = D.Data.doors or {}

        local rec, bestScore = D.Data.doors[id], recordPriority(D.Data.doors[id])
        local aliases = {}
        for _, equivalent in ipairs(D.GetEquivalentDoors(ent)) do
            local aliasID = baseDoorID(equivalent)
            if aliasID then
                aliases[aliasID] = true
                local candidate = D.Data.doors[aliasID]
                local score = recordPriority(candidate)
                if score > bestScore then rec, bestScore = candidate, score end
            end
        end
        if rec then
            rec.id = id
            rec._ephemeral = nil
            D.Data.doors[id] = rec
            for aliasID in pairs(aliases) do
                if aliasID ~= id then D.Data.doors[aliasID] = nil end
            end
            return rec, id
        end
        -- Эфемерная запись в карте: SaveDoors её не пишет, пока recDirty.
        -- Нужна, чтобы TOOL/LockDoor мутировали тот же объект.
        local fresh = defaultRec(id, ent)
        D.Data.doors[id] = fresh
        return fresh, id
    end
    D.GetRecord = getRecord

    --[[ ПОСТАВИТЬ ВЛАДЕЛЬЦА ДВЕРИ ИЗВНЕ (жалоба владельца 28.08:
         «дверь как была ничья, так и осталась ничья»).

         Недвижимость привязывала дверь к объекту, но САМА ЗАПИСЬ двери
         оставалась нетронутой: owner_type = "none". Табличка на двери
         читает NW-поле GRM_DoorOwner, которое заполняется из этой
         записи, поэтому дверь купленной квартиры продолжала показывать
         «Продаётся / Ничья».

         Здесь одна точка, которая делает всё сразу и правильно:
         пишет запись, гасит признак «продаётся», обновляет табличку у
         всех полотен двери и сохраняет. Раньше каждый желающий должен
         был знать про owner_type, ownerLabel, ApplyRecordVisual и
         SaveDoors — и, конечно, забывал половину.

         ownerType: "player" / "faction" / "none". ]]
    function D.SetDoorOwner(ent, ownerType, key, nick, title)
        if not IsValid(ent) then return false end
        local rec, id = getRecord(ent)
        if not rec then return false end

        ownerType = tostring(ownerType or "none")
        if ownerType == "none" then
            rec.owner_type = "none"
            rec.owner_key, rec.owner_nick, rec.owner_faction = "", "", ""
            -- Освободили — значит снова можно приобрести.
            rec.ownable = true
        else
            rec.owner_type = ownerType
            if ownerType == "faction" then
                rec.owner_faction = tostring(key or "")
                rec.owner_key, rec.owner_nick = "", ""
            else
                rec.owner_key = tostring(key or "")
                rec.owner_nick = utf8cut(tostring(nick or ""), 64)
                rec.owner_faction = ""
            end
            --[[ Дверь принадлежит объекту недвижимости: покупать её
                 отдельно, в обход квартиры, нельзя. ]]
            rec.ownable = false
        end
        if isstring(title) and title ~= "" then rec.title = utf8cut(title, 64) end
        rec._ephemeral = nil

        D.ApplyRecordVisual(ent, rec)
        if D.SaveDoors then D.SaveDoors() end
        return true, rec, id
    end

    local function persist(rec, id)
        if not rec or not id then return rec end
        rec.id = id
        rec._ephemeral = nil
        D.Data.doors = D.Data.doors or {}
        D.Data.doors[id] = rec
        return rec
    end

    local function actorOf(ply, rec)
        local fac, role, dept, sub = playerFactionInfo(ply)
        local AM = D.AccessManager
        local actor = {
            superadmin = D.CanAdminDoors(ply),
            key = charKey(ply),
            faction = fac,
            role = role,
            department = dept,
            subdepartment = sub,
            canWarrant = AM and AM.CanWarrant and AM.CanWarrant(ply) or false,
            hasWarrantOnOwner = rec and rec.owner_type == "player" and D.HasWarrant(rec.owner_key) or false,
            canForce = AM and AM.CanForceDoor and AM.CanForceDoor(ply) or false,
        }

        -- Категория-владелец: проход, замок и приватизация считаются по её профилю
        -- (отделы, подотделы, должности, «все», «без организации»).
        local ownerCat = D.CategoryOfDoor(rec)
        actor.categoryHas = ownerCat and D.CategoryMatch(ownerCat, actor) or false
        actor.categoryLock = ownerCat and D.CategoryCanLock(ownerCat, actor) or false
        actor.categoryBuy = ownerCat and ownerCat.allowBuy == true or false
        actor.categoryKeepLocked = ownerCat and ownerCat.keepLocked == true or false

        -- Категории, добавленные в список доступа двери (не владелец).
        local aclCat = false
        if rec and istable(rec.categories) then
            for _, cid in ipairs(rec.categories) do
                if factionInCategory(fac, cid, actor) then aclCat = true break end
            end
        end
        actor.aclCategory = aclCat

        local propertyHas = hook.Run("GRM_DoorPropertyAccess", ply, rec and rec.id or "")
        actor.propertyHas = propertyHas == true
        return actor
    end

    function D.CanAccessDoor(ply, ent)
        if not IsValid(ply) or not IsValid(ent) then return false, "invalid" end
        local override, overrideReason = hook.Run("GRM_DoorAccessOverride", ply, ent)
        if override ~= nil then return override == true, overrideReason or "property" end
        if D.Config.SuperAdminBypass ~= false and ply:IsSuperAdmin() then return true, "superadmin" end
        local rec = select(1, getRecord(ent))
        local acc = D.EvaluateAccess(rec, actorOf(ply, rec))
        if acc.has_key then return true, "key" end
        return false, "denied"
    end

    function D.IsFriendlyForAlarm(ply, networkID)
        if not IsValid(ply) then return false end
        if ply:IsSuperAdmin() then return true end
        if D.AccessManager and D.AccessManager.IsFriendly then
            return D.AccessManager.IsFriendly(ply, networkID)
        end
        return false
    end

    --- Все полотна ОДНОЙ физической двери: сама дверь, её дубли на карте,
    --  вторая створка и дубли второй створки.
    function D.DoorGroup(ent)
        local out, seen = {}, {}
        local function add(e)
            if IsValid(e) and not seen[e] then seen[e] = true out[#out + 1] = e end
        end
        add(ent)
        for _, eq in ipairs(D.GetEquivalentDoors(ent)) do add(eq) end
        local partner = D.GetPartnerDoor(ent)
        if IsValid(partner) then
            add(partner)
            for _, eq in ipairs(D.GetEquivalentDoors(partner)) do add(eq) end
        end
        return out
    end

    --- Записи всех полотен группы: { [id] = rec }
    function D.GroupRecords(ent)
        local out = {}
        for _, leaf in ipairs(D.DoorGroup(ent)) do
            local id = D.GetDoorID(leaf)
            local rec = id and D.Data.doors and D.Data.doors[id] or nil
            if istable(rec) then out[id] = rec end
        end
        return out
    end

    --[[ АВТОБЛОКИРОВКА (по умолчанию выключена).
         `grm_door_autolock 8` — дверь сама запирается через 8 секунд после
         того, как её отперли. 0 — никогда. Отдельная явная настройка вместо
         прежнего «само собой запирается непонятно почему». ]]
    local cvAutoLock = CreateConVar("grm_door_autolock", "0", FCVAR_ARCHIVE,
        "Через сколько секунд дверь сама запирается после отпирания (0 — никогда)")

    function D.AutoLockDelay()
        local v = cvAutoLock and cvAutoLock:GetInt() or 0
        if v <= 0 then return 0 end
        return math.Clamp(v, 1, 3600)
    end

    function D.CancelAutoLock(id)
        if not id then return end
        local name = "GRM_Doors_AutoLock_" .. tostring(id)
        if timer.Exists and timer.Exists(name) then timer.Remove(name) end
    end

    function D.ScheduleAutoLock(ent, id)
        local delay = D.AutoLockDelay()
        if delay <= 0 or not IsValid(ent) or not id then return false end
        timer.Create("GRM_Doors_AutoLock_" .. tostring(id), delay, 1, function()
            if not IsValid(ent) then return end
            local rec = D.Data.doors and D.Data.doors[id] or nil
            if istable(rec) and rec.locked == true then return end
            D.LockDoor(ent, true, { noAutoLock = true })
        end)
        return true
    end

    function D.LockDoor(ent, locked, opts)
        if not IsValid(ent) then return false, false, nil end
        opts = istable(opts) and opts or {}
        local rec, id = getRecord(ent)
        -- Профиль категории «дверь всегда заперта» сильнее любой попытки её открыть.
        local keepCat = D.CategoryOfDoor(rec)
        local forced = false
        if istable(keepCat) and keepCat.keepLocked == true and not locked then
            locked = true
            forced = true
        end
        locked = locked and true or false

        local cmd = locked and "Lock" or "Unlock"
        local stamp = os.time()

        --[[ Замок ставим ВСЕЙ физической двери разом: полотну, его дублям,
             второй створке и дублям створки. И, главное, пишем состояние в
             КАЖДУЮ запись — иначе сторож замков вернёт старое значение из
             записи соседней створки (класс «дверь заперлась сама»). ]]
        for _, leaf in ipairs(D.DoorGroup(ent)) do
            leaf:Fire(cmd, "", 0)
            leaf:SetNWBool("GRM_DoorLocked", locked)
            local lrec, lid = getRecord(leaf)
            if lrec and lid then
                lrec.locked = locked
                lrec.lock_at = stamp
                persist(lrec, lid)
            end
        end
        D.SyncLockNW(ent, locked)
        D.SaveDoors()

        -- Необязательная автоблокировка: дверь сама запирается через N секунд
        -- после отпирания. По умолчанию выключена (grm_door_autolock 0).
        if id then D.CancelAutoLock(id) end
        if not locked and not opts.noAutoLock then D.ScheduleAutoLock(ent, id) end

        return true, locked, forced
    end

    --- Право управлять замком именно этой двери (ключи, меню, терминалы).
    --  Возвращает: можно ли, причина отказа, «дверь всегда заперта».
    function D.CanToggleLock(ply, ent, wantLocked)
        if not IsValid(ply) or not IsValid(ent) then return false, "Недействительный объект" end
        local rec = select(1, getRecord(ent))
        local actor = actorOf(ply, rec)
        local acc = D.EvaluateAccess(rec, actor)
        if not acc.has_key then return false, "У вас нет ключей от этой двери." end
        if not acc.lock then
            local cat = D.CategoryOfDoor(rec)
            if istable(cat) and cat.lockAdminOnly == true then
                return false, "Замком этой двери управляет только администрация."
            end
            return false, "Вам разрешён только проход — замком этой двери вы управлять не можете."
        end
        local cat = D.CategoryOfDoor(rec)
        if wantLocked == false and istable(cat) and cat.keepLocked == true and actor.superadmin ~= true then
            return false, "Дверь этой категории всегда заперта.", true
        end
        return true, nil, istable(cat) and cat.keepLocked == true or false
    end

    function D.ClaimDoor(ply, ent, mode)
        if not IsValid(ply) or not IsValid(ent) then return false, "Недействительный объект" end
        local rec, id = getRecord(ent)
        if not rec then return false, "Запись не найдена" end
        local acc = D.EvaluateAccess(rec, actorOf(ply, rec))
        if not acc.buy then
            if rec.ownable == false then return false, "Эту дверь нельзя приобрести" end
            return false, "Дверь уже находится в собственности"
        end
        if rec.owner_type == "player" and (tonumber(rec.rent_until) or 0) > os.time() then
            return false, "Дверь уже арендована другим игроком"
        end

        --[[ ДВЕРЬ ОТ ОБЪЕКТА НЕДВИЖИМОСТИ (заказ владельца 28.08:
             «если я покупаю дверь, то автоматически зона должна считывать
              купленную дверь + выставлять полную цену и автоматически
              привязываться сразу к игроку»).

             Дверь может быть входом в квартиру или бизнес. Тогда покупать
             её отдельно за 15 000 бессмысленно и нечестно: человек
             получил бы ключ от жилья, не заплатив за само жильё, а зона
             осталась бы свободной и её купил бы кто-то ещё.

             Отдаём такую покупку недвижимости: она возьмёт ПОЛНУЮ цену
             объекта и оформит его целиком — вместе с этой дверью,
             остальными дверями и оборудованием внутри. ]]
        local claimed = hook.Run("GRM_DoorClaimToProperty", ply, ent, rec, mode)
        if claimed ~= nil then return claimed == true, claimed == true and "" or "Объект недвижимости" end

        local price = tonumber(rec.rent_price) or tonumber(D.Config.RentPrice) or 5000
        if mode == "rent" then
            if price > 0 and GRM.TakeMoney then
                if not GRM.HasMoney(ply, price) then return false, "Недостаточно наличных для аренды" end
                GRM.TakeMoney(ply, price, "Аренда двери")
            end
            rec.rent_until = os.time() + (tonumber(D.Config.DefaultRentSeconds) or 604800)
        else
            local permPrice = price * (tonumber(D.Config.PermPriceMultiplier) or 3)
            if permPrice > 0 and GRM.TakeMoney then
                if not GRM.HasMoney(ply, permPrice) then return false, "Недостаточно наличных для покупки (навечно)" end
                GRM.TakeMoney(ply, permPrice, "Покупка двери навечно")
            end
            rec.rent_until = 0
        end
        rec.owner_type = "player"
        rec.owner_key = charKey(ply)
        rec.owner_nick = ply:Nick()
        rec.owner_faction, rec.owner_category = "", ""
        rec.co_owners, rec.factions, rec.roles, rec.categories = {}, {}, {}, {}
        rec.locked = true
        persist(rec, id)
        D.LockDoor(ent, true)
        D.ApplyRecordVisual(ent, rec)
        D.SaveDoors()
        return true
    end

    function D.ReleaseDoor(ply, ent)
        local rec, id = getRecord(ent)
        if not rec then return false, "Запись не найдена" end
        local acc = D.EvaluateAccess(rec, actorOf(ply, rec))
        if not acc.own then return false, "Вы не являетесь владельцем этой двери" end

        --[[ ДВЕРЬ ОТ ОБЪЕКТА НЕДВИЖИМОСТИ (заказ владельца 28.08:
             «если я через дверь нажал освободить, то дом сразу же должен
              быть продан государству»).

             Если дверь входит в квартиру или бизнес, освобождать её
             отдельно бессмысленно и вредно: объект остался бы у
             владельца, но БЕЗ входной двери — попасть внутрь стало бы
             нельзя, а деньги за жильё никто не вернул бы.

             Отдаём такое освобождение недвижимости: она продаст объект
             государству целиком, с выплатой и удержанием долга по ЖКХ,
             и заодно освободит все двери и оборудование. ]]
        local handled = hook.Run("GRM_DoorReleaseToProperty", ply, ent, rec)
        if handled ~= nil then return handled == true, "" end

        rec.owner_type = "none"
        rec.owner_key, rec.owner_nick, rec.owner_faction, rec.owner_category = "", "", "", ""
        rec.co_owners, rec.factions, rec.roles, rec.categories = {}, {}, {}, {}
        rec.rent_until = 0
        rec.locked = false
        persist(rec, id)
        D.LockDoor(ent, false)
        D.ApplyRecordVisual(ent, rec)
        D.SaveDoors()
        return true
    end

    function D.IssueWarrant(issuer, targetSid, warrantType, minutes, reason, propertyId, approvedBy)
        if not IsValid(issuer) and not (isstring(issuer) and issuer == "console") then return false, "Ошибка инициатора" end
        targetSid = charKey(targetSid)
        if targetSid == "" then return false, "Не указана цель" end
        warrantType = tostring(warrantType or "search")
        minutes = math.Clamp(math.floor(tonumber(minutes) or 30), 5, 24 * 60)
        D.Data.warrants = D.Data.warrants or {}
        local id = "war_" .. os.time() .. "_" .. math.random(100, 999)
        local issuerName = IsValid(issuer) and rpNick(issuer) or tostring(issuer)
        local issuerKey = IsValid(issuer) and charKey(issuer) or tostring(issuer)
        local judgeName = IsValid(approvedBy) and rpNick(approvedBy) or (isstring(approvedBy) and approvedBy or "Суд")
        local judgeKey = IsValid(approvedBy) and charKey(approvedBy) or (isstring(approvedBy) and approvedBy or "")
        D.Data.warrants[targetSid] = {
            id = id,
            number = nextWarrantNumber(),
            sid = targetSid,
            type = warrantType,
            name = nickOf(targetSid),
            propertyId = tostring(propertyId or ""),
            reason = utf8cut(tostring(reason or "Судебный ордер"), 200),
            by = issuerKey, byNick = issuerName,
            issuerFaction = IsValid(issuer) and issuer:GetNWString("GRM_Faction", "") or "",
            approvedBy = judgeKey, approvedByName = judgeName,
            status = "active",
            issued = os.time(), expires = os.time() + minutes * 60,
        }
        D.SaveWarrants()
        hook.Run("GRM_OnWarrantIssued", targetSid, D.Data.warrants[targetSid], issuer)
        return true, D.Data.warrants[targetSid]
    end

    function D.RequestWarrant(issuer, targetSid, warrantType, minutes, reason, propertyId, source)
        if not IsValid(issuer) then return false, "Ошибка инициатора" end
        targetSid = charKey(targetSid)
        if targetSid == "" then return false, "Не указан фигурант" end
        warrantType = tostring(warrantType or "search")
        minutes = math.Clamp(math.floor(tonumber(minutes) or 30), 5, 24 * 60)
        D.Data.warrants = D.Data.warrants or {}
        local id = "req_" .. os.time() .. "_" .. math.random(100, 999)
        D.Data.warrants[id] = {
            id = id,
            number = nextWarrantNumber(),
            sid = targetSid,
            type = warrantType,
            name = nickOf(targetSid),
            propertyId = tostring(propertyId or ""),
            reason = utf8cut(tostring(reason or "Ходатайство на ордер"), 200),
            by = charKey(issuer), byNick = rpNick(issuer),
            issuerFaction = issuer:GetNWString("GRM_Faction", ""),
            issuerRole = issuer:GetNWString("GRM_Role", ""),
            source = tostring(source or ""),
            status = "pending",
            issued = os.time(), expires = os.time() + minutes * 60,
        }
        D.SaveWarrants()
        hook.Run("GRM_OnWarrantRequested", id, D.Data.warrants[id], issuer)
        return true, D.Data.warrants[id]
    end

    function D.ApproveWarrant(judge, warrantId, minutes)
        if not IsValid(judge) then return false, "Ошибка судьи" end
        if not istable(D.Data.warrants) or not D.Data.warrants[warrantId] then
            return false, "Ходатайство не найдено"
        end
        local req = D.Data.warrants[warrantId]
        minutes = math.Clamp(math.floor(tonumber(minutes) or 60), 5, 24 * 60)
        local targetSid = req.sid
        D.Data.warrants[warrantId] = nil
        local rec = {
            id = "war_" .. os.time() .. "_" .. math.random(100, 999),
            number = tonumber(req.number) or nextWarrantNumber(),
            sid = targetSid,
            type = req.type or "search",
            name = req.name or nickOf(targetSid),
            propertyId = req.propertyId or "",
            reason = req.reason or "Утверждён судом",
            by = req.by or "", byNick = req.byNick or "",
            issuerFaction = req.issuerFaction or "",
            source = req.source or "",
            approvedBy = charKey(judge), approvedByName = rpNick(judge),
            status = "active",
            issued = os.time(), expires = os.time() + minutes * 60,
        }
        D.Data.warrants[targetSid] = rec
        D.SaveWarrants()
        hook.Run("GRM_OnWarrantApproved", targetSid, rec, judge)
        D.AnnounceWarrantApproved(judge, rec)
        return true, rec
    end

    function D.AnnounceWarrantApproved(judge, rec)
        if not istable(rec) then return end
        local rp = IsValid(judge) and rpNick(judge) or tostring(rec.approvedByName or "Прокурор")
        local role = IsValid(judge) and string.lower(judge:GetNWString("GRM_Role", "") or "") or ""
        local title = "Прокурор"
        if string.find(role, "суд", 1, true) or string.find(role, "judge", 1, true) then title = "Судья" end
        local num = rec.number or rec.id or "?"
        local reason = tostring(rec.reason or "ходатайство")
        local who = tostring(rec.name or rec.sid or "неизвестный")
        local body = string.format("%s (%s) утвердил ордер №%s на %s в отношении %s.",
            title, rp, tostring(num), reason, who)
        local BL = GRM.Wanted and GRM.Wanted.Bulletins
        if BL and isfunction(BL.Raw) then
            BL.Raw("dep", judge, body, "civil", nil, "[Правосудие] ")
        end
    end

    function D.RejectWarrant(judge, warrantId, reason)
        if not istable(D.Data.warrants) or not D.Data.warrants[warrantId] then
            return false, "Ходатайство не найдено"
        end
        local req = D.Data.warrants[warrantId]
        req.status = "rejected"
        req.rejectReason = utf8cut(tostring(reason or "Отклонено судом"), 160)
        req.rejectedBy = IsValid(judge) and charKey(judge) or "court"
        D.SaveWarrants()
        hook.Run("GRM_OnWarrantRejected", warrantId, req, judge)
        return true
    end

    function D.RevokeWarrant(issuer, targetSid)
        if not IsValid(issuer) and not (isstring(issuer) and issuer == "console") then return false end
        targetSid = charKey(targetSid)
        if D.Data.warrants and D.Data.warrants[targetSid] then
            D.Data.warrants[targetSid] = nil
        end
        D.SaveWarrants()
        return true
    end

    function D.ListWarrants(filterType, includePending)
        local out = {}
        local now = os.time()
        for k, w in pairs(D.Data.warrants or {}) do
            if istable(w) then
                local exp = tonumber(w.expires or w.expiresAt) or 0
                if exp == 0 or exp > now then
                    local isPend = (w.status == "pending" or string.sub(k, 1, 4) == "req_")
                    if (not isPend or includePending == true) then
                        if not filterType or filterType == "" or filterType == "all" or w.type == filterType then
                            out[#out + 1] = w
                        end
                    end
                end
            end
        end
        table.sort(out, function(a, b) return (a.issued or 0) > (b.issued or 0) end)
        return out
    end

    local function aimDoor(ply)
        if not IsValid(ply) then return nil end
        local tr = util.TraceLine({
            start = ply:GetShootPos(),
            endpos = ply:GetShootPos() + ply:GetAimVector() * (D.Config.UseDistance or 180),
            filter = ply,
        })
        local ent = tr.Entity
        if D.IsDoor(ent) then return ent end
        if IsValid(ent) and IsValid(ent:GetParent()) and D.IsDoor(ent:GetParent()) then
            return ent:GetParent()
        end
    end

    local function nearDoor(ply, ent)
        if not (IsValid(ply) and IsValid(ent)) then return false end
        local maxD = D.Config.UseDistance or 180
        return ply:GetPos():DistToSqr(ent:GetPos()) <= (maxD + 40) * (maxD + 40)
    end

    hook.Add("AcceptInput", "GRM_Doors_SyncInput", function(ent, input)
        if not D.IsDoor(ent) then return end
        local lIn = string.lower(tostring(input or ""))
        if lIn == "lock" then D.SyncLockNW(ent, true)
        elseif lIn == "unlock" then D.SyncLockNW(ent, false) end
    end)

    timer.Create("GRM_Doors_LockReconciler", (D.Config and D.Config.LockSyncInterval) or 2.0, 0, function()
        if not istable(D.Data) or not istable(D.Data.doors) then return end
        -- Раньше сверка замков каждые 2 секунды делала ПОЛНЫЙ ents.GetAll()
        -- по всем энтити карты. Теперь берём только двери из event-реестров.
        --
        -- И главное: сверяем не «каждое полотно со своей записью», а группу
        -- полотен одной физической двери с ОДНИМ состоянием (самая свежая
        -- запись по lock_at). Иначе соседняя створка возвращала замок обратно
        -- и дверь «запиралась сама» через пару секунд после отпирания.
        for _, ent in ipairs(D.AllDoors()) do
            if IsValid(ent) then
                local id = D.GetDoorID(ent)
                local rec = id and D.Data.doors[id] or nil
                local okE, engRaw = pcall(function() return ent:GetInternalVariable("m_bLocked") end)
                if not okE then engRaw = nil end
                local engLocked = (engRaw == true or engRaw == 1)

                local group = D.GroupRecords(ent)
                local hasGroup = next(group) ~= nil
                local groupLocked, stamp = D.ResolveGroupLock(group)

                if hasGroup and (groupLocked == true or (rec and rec.owner_type and rec.owner_type ~= "none")) then
                    local want = groupLocked
                    -- Лечим рассинхрон записей створок: у всей группы одно значение.
                    if not D.GroupLockInSync(group) then
                        for gid, grec in pairs(group) do
                            grec.locked = want
                            grec.lock_at = math.max(tonumber(grec.lock_at) or 0, stamp)
                            D.Data.doors[gid] = grec
                        end
                        D.SaveDoors()
                    end
                    if engRaw ~= nil and engLocked ~= want then ent:Fire(want and "Lock" or "Unlock", "", 0) end
                    if ent:GetNWBool("GRM_DoorLocked", false) ~= want then D.SyncLockNW(ent, want) end
                else
                    local want = (hasGroup and groupLocked) or engLocked
                    if ent:GetNWBool("GRM_DoorLocked", false) ~= want then D.SyncLockNW(ent, want) end
                end
            end
        end
    end)

    hook.Add("PlayerUse", "GRM_Doors_Use", function(ply, ent)
        if not D.IsDoor(ent) then
            if IsValid(ent) and IsValid(ent:GetParent()) and D.IsDoor(ent:GetParent()) then
                ent = ent:GetParent()
            else
                return
            end
        end
        if not D.IsDoorLocked(ent) then return end
        local override, overrideReason = hook.Run("GRM_DoorAccessOverride", ply, ent)
        if override == false then
            notify(ply, tostring(overrideReason or "Доступ к объекту закрыт."), 255, 90, 90)
            return false
        elseif override == true then
            return
        end
        local rec = select(1, getRecord(ent))
        local acc = D.EvaluateAccess(rec, actorOf(ply, rec))
        if not acc.walk_locked then
            local id = D.GetDoorID(ent) or ("e" .. tostring(ent:EntIndex()))
            ply.GRM_DoorLockTold = ply.GRM_DoorLockTold or {}
            local show, st = D.ShouldNotifyLockDeny(
                ply.GRM_DoorLockTold, id, CurTime(),
                ply.KeyDown and ply:KeyDown(IN_USE) or true,
                (D.Config and D.Config.LockNotifyCooldown) or 1.5
            )
            ply.GRM_DoorLockTold = st
            if show then notify(ply, "Дверь заперта на замок. У вас нет доступа.", 255, 90, 90) end
            return false
        end
    end)

    hook.Add("KeyRelease", "GRM_Doors_LockDenyRelease", function(ply, key)
        if key == IN_USE and IsValid(ply) then
            D.ClearLockDenyHold(ply.GRM_DoorLockTold)
        end
    end)

    local function packDoorData(ent, ply)
        local rec, id = getRecord(ent)
        if not rec then return nil end
        local acc = D.EvaluateAccess(rec, actorOf(ply, rec))
        local payload = {
            id = id,
            title = rec.title or "",
            owner_type = rec.owner_type,
            owner_nick = rec.owner_nick or "",
            owner_faction = rec.owner_faction or "",
            owner_category = rec.owner_category or "",
            owner_category_name = (istable(D.Data.categories) and istable(D.Data.categories[rec.owner_category or ""])
                and tostring(D.Data.categories[rec.owner_category].name or "")) or "",
            locked = D.IsDoorLocked(ent),
            rent_until = tonumber(rec.rent_until) or 0,
            rent_price = tonumber(rec.rent_price) or (D.Config.RentPrice or 5000),
            can_access = acc.has_key,
            is_owner = acc.is_owner,
            is_admin = acc.admin,
            ownable = rec.ownable ~= false,
            can_buy = acc.buy,
            can_own = acc.own,
        }
        if acc.own or acc.admin then
            payload.owner_key = rec.owner_key or ""
            payload.factions = rec.factions or {}
            payload.roles = rec.roles or {}
            payload.categories = rec.categories or {}
            local co = {}
            for _, sid in ipairs(rec.co_owners or {}) do
                co[#co + 1] = { sid = sid, nick = nickOf(sid) }
            end
            payload.co_owners = co
        end
        return payload
    end

    --[[ Дерево организаций для редактора категорий: фракция → отделы →
         подотделы → должности, с публичными названиями (их видит админ) и
         системными ключами (их хранит категория). ]]
    function D.FactionTree()
        local out = {}
        if not istable(Factions) then return out end
        local FA = GRM.Factions or {}
        for name, f in pairs(Factions) do
            if istable(f) then
                local row = { name = name, display = (FA.DisplayName and FA.DisplayName(name)) or name,
                    roles = {}, departments = {}, subdepartments = {} }
                for _, roleKey in ipairs(f.Roles or {}) do
                    row.roles[#row.roles + 1] = { key = roleKey,
                        display = (FA.RoleDisplayName and FA.RoleDisplayName(f, roleKey)) or roleKey }
                end
                for _, deptKey in ipairs(f.Departments or {}) do
                    row.departments[#row.departments + 1] = { key = deptKey,
                        display = (FA.DepartmentDisplayName and FA.DepartmentDisplayName(f, deptKey)) or deptKey }
                end
                for subKey, sub in pairs(f.Subdepartments or {}) do
                    if istable(sub) then
                        row.subdepartments[#row.subdepartments + 1] = { key = subKey,
                            display = tostring(sub.name or subKey), parent = tostring(sub.parentDept or "") }
                    end
                end
                table.sort(row.subdepartments, function(a, b) return tostring(a.display) < tostring(b.display) end)
                out[#out + 1] = row
            end
        end
        table.sort(out, function(a, b) return string.lower(tostring(a.display)) < string.lower(tostring(b.display)) end)
        return out
    end

    function D.OpenDoorMenu(ply)
        local ent = aimDoor(ply)
        if not IsValid(ent) then
            notify(ply, "Подойдите ближе и смотрите на дверь.", 255, 180, 60)
            return
        end
        local doorData = packDoorData(ent, ply)
        local acc = doorData and (doorData.can_own or doorData.is_admin)
        local catsList, facList = {}, {}
        if acc then
            -- Категории уходят ЦЕЛИКОМ (профиль доступа), иначе редактировать
            -- их на клиенте нечем.
            for id, c in pairs(D.Data.categories or {}) do
                catsList[#catsList + 1] = D.NormalizeCategory(c, id)
            end
            table.sort(catsList, function(a, b) return tostring(a.name) < tostring(b.name) end)
            facList = D.FactionTree()
        end
        net.Start(NET_OPEN)
            net.WriteEntity(ent)
            net.WriteTable(doorData or {})
            net.WriteTable(catsList)
            net.WriteTable(facList)
            net.WriteBool(D.CanAdminDoors(ply))
        net.Send(ply)
    end

    local function handleServerDoorBind(ply)
        if not IsValid(ply) then return end
        if IsValid(aimDoor(ply)) then D.OpenDoorMenu(ply) return true end
    end
    --[[ Меню двери открывается ТОЛЬКО по F3 (заказ владельца 19.08).
         Раньше двери перехватывали все четыре бинда и забирали F2 у тикетов,
         F4 у главного меню и F1 у справки. ]]
    hook.Add("ShowSpare1", "GRM_Doors_ServerOverrideF3", handleServerDoorBind)
    hook.Remove("ShowTeam", "GRM_Doors_ServerOverrideF2")
    hook.Remove("ShowSpare2", "GRM_Doors_ServerOverrideF4")
    hook.Remove("ShowHelp", "GRM_Doors_ServerOverrideF1")

    net.Receive(NET_ACT, function(_, ply)
        if not IsValid(ply) then return end
        ply.GRM_DoorActNext = ply.GRM_DoorActNext or 0
        if CurTime() < ply.GRM_DoorActNext then return end
        ply.GRM_DoorActNext = CurTime() + (D.Config.ActCooldown or 0.4)

        local a = net.ReadTable() or {}
        local act = tostring(a.action or "")
        if act == "open_menu" then D.OpenDoorMenu(ply) return end

        local ent = Entity(tonumber(a.entIndex) or -1)
        if not IsValid(ent) or not D.IsDoor(ent) then
            notify(ply, "Дверь не найдена.", 255, 100, 100)
            return
        end
        if not nearDoor(ply, ent) then
            notify(ply, "Подойдите ближе к двери.", 255, 180, 60)
            return
        end

        local rec, id = getRecord(ent)
        if not rec then return end
        local acc = D.EvaluateAccess(rec, actorOf(ply, rec))

        if act == "claim_rent" then
            local ok, err = D.ClaimDoor(ply, ent, "rent")
            notify(ply, ok and "Дверь успешно арендована!" or tostring(err), ok and 100 or 255, ok and 220 or 100, 100)
            if ok then D.OpenDoorMenu(ply) end

        elseif act == "claim_perm" then
            local ok, err = D.ClaimDoor(ply, ent, "permanent")
            notify(ply, ok and "Дверь куплена в постоянную собственность!" or tostring(err), ok and 100 or 255, ok and 220 or 100, 100)
            if ok then D.OpenDoorMenu(ply) end

        elseif act == "release" then
            local ok, err = D.ReleaseDoor(ply, ent)
            notify(ply, ok and "Дверь освобождена." or tostring(err), ok and 100 or 255, ok and 220 or 100, 100)
            if ok then D.OpenDoorMenu(ply) end

        elseif act == "lock" or act == "unlock" then
            if not acc.lock then
                notify(ply, "У вас нет прав закрывать/открывать эту дверь.", 255, 100, 100)
                return
            end
            D.LockDoor(ent, act == "lock")
            notify(ply, act == "lock" and "Замок заблокирован." or "Замок разблокирован.", 100, 220, 100)
            D.OpenDoorMenu(ply)

        elseif act == "set_title" then
            if not acc.own then return end
            rec.title = utf8cut(tostring(a.title or ""), 64)
            persist(rec, id)
            D.ApplyRecordVisual(ent, rec)
            D.SaveDoors()
            notify(ply, "Название двери обновлено.", 100, 220, 100)
            D.OpenDoorMenu(ply)

        elseif act == "add_coowner" then
            if not acc.own then return end
            local sid = charKey(a.sid)
            if sid == "" then return end
            rec.co_owners = rec.co_owners or {}
            if #rec.co_owners >= (D.Config.MaxOwnersPerDoor or 12) then
                notify(ply, "Достигнут лимит совладельцев.", 255, 180, 60)
                return
            end
            if not listHas(rec.co_owners, sid) then rec.co_owners[#rec.co_owners + 1] = sid end
            persist(rec, id)
            D.SaveDoors()
            notify(ply, "Совладелец добавлен: " .. nickOf(sid), 100, 220, 100)
            D.OpenDoorMenu(ply)

        elseif act == "remove_coowner" then
            if not acc.own then return end
            local sid = charKey(a.sid)
            local nextCo = {}
            for _, s in ipairs(rec.co_owners or {}) do if s ~= sid then nextCo[#nextCo + 1] = s end end
            rec.co_owners = nextCo
            persist(rec, id)
            D.SaveDoors()
            notify(ply, "Совладелец удалён.", 100, 220, 100)
            D.OpenDoorMenu(ply)

        elseif act == "toggle_acl_faction" then
            if not acc.own then return end
            local fac = tostring(a.faction or "")
            rec.factions = rec.factions or {}
            if listHas(rec.factions, fac) then
                local n = {}
                for _, f in ipairs(rec.factions) do if f ~= fac then n[#n + 1] = f end end
                rec.factions = n
            else
                rec.factions[#rec.factions + 1] = fac
            end
            persist(rec, id)
            D.SaveDoors()
            D.OpenDoorMenu(ply)

        elseif act == "toggle_acl_role" then
            if not acc.own then return end
            local key = tostring(a.roleKey or "")
            rec.roles = rec.roles or {}
            if listHas(rec.roles, key) then
                local n = {}
                for _, r in ipairs(rec.roles) do if r ~= key then n[#n + 1] = r end end
                rec.roles = n
            else
                rec.roles[#rec.roles + 1] = key
            end
            persist(rec, id)
            D.SaveDoors()
            D.OpenDoorMenu(ply)

        elseif act == "toggle_acl_category" then
            if not acc.own then return end
            local cat = tostring(a.category or "")
            rec.categories = rec.categories or {}
            if listHas(rec.categories, cat) then
                local n = {}
                for _, c in ipairs(rec.categories) do if c ~= cat then n[#n + 1] = c end end
                rec.categories = n
            else
                rec.categories[#rec.categories + 1] = cat
            end
            persist(rec, id)
            D.SaveDoors()
            D.OpenDoorMenu(ply)

        elseif act == "set_faction_owner" then
            if not acc.admin then
                notify(ply, "Только суперадмин может менять принадлежность двери.", 255, 100, 100)
                return
            end
            rec.owner_type = "faction"
            rec.owner_faction = tostring(a.faction or "")
            rec.owner_key, rec.owner_nick, rec.owner_category = "", "", ""
            rec.rent_until = 0
            persist(rec, id)
            D.ApplyRecordVisual(ent, rec)
            D.SaveDoors()
            notify(ply, "Назначен владелец: фракция [" .. rec.owner_faction .. "]", 100, 220, 100)
            D.OpenDoorMenu(ply)

        elseif act == "set_category_owner" then
            if not acc.admin then
                notify(ply, "Только суперадмин может менять принадлежность двери.", 255, 100, 100)
                return
            end
            rec.owner_type = "category"
            rec.owner_category = tostring(a.category or "")
            rec.owner_faction, rec.owner_key, rec.owner_nick = "", "", ""
            rec.rent_until = 0
            persist(rec, id)
            D.ApplyRecordVisual(ent, rec)
            D.SaveDoors()
            local catC = D.Data.categories and D.Data.categories[rec.owner_category]
            local catDisp = (istable(catC) and tostring(catC.name or rec.owner_category)) or rec.owner_category
            notify(ply, "Назначен владелец: категория [" .. catDisp .. "]", 100, 220, 100)
            D.OpenDoorMenu(ply)

        elseif act == "cat_create" then
            if not acc.admin then notify(ply, "Только суперадмин.", 255, 100, 100) return end
            local c, err = D.CreateCategory(a.catId, a.name)
            notify(ply, c and ("Категория создана: " .. tostring(c.name)) or tostring(err), c and 100 or 255, c and 220 or 100, 100)
            D.OpenDoorMenu(ply)

        elseif act == "cat_rename" then
            if not acc.admin then return end
            local okRen, err = D.RenameCategory(a.catId, a.name)
            notify(ply, okRen and "Категория переименована." or tostring(err), okRen and 100 or 255, okRen and 220 or 100, 100)
            D.OpenDoorMenu(ply)

        elseif act == "cat_delete" then
            if not acc.admin then return end
            local okDel, err = D.DeleteCategory(a.catId)
            notify(ply, okDel and "Категория удалена." or tostring(err), okDel and 100 or 255, okDel and 220 or 100, 100)
            D.OpenDoorMenu(ply)

        elseif act == "cat_flag" then
            if not acc.admin then return end
            local c = D.Data.categories and D.Data.categories[tostring(a.catId or "")]
            if not istable(c) then return end
            local flag = tostring(a.flag or "")
            local known = false
            for _, row in ipairs(D.CategoryFlags or {}) do if row.key == flag then known = true break end end
            if not known then return end
            c[flag] = a.value == true
            D.Data.categories[c.id] = D.NormalizeCategory(c, c.id)
            D.SaveCategories()
            D.OpenDoorMenu(ply)

        elseif act == "cat_member" then
            -- Переключение элемента профиля: фракция, отдел, подотдел, должность.
            if not acc.admin then return end
            local c = D.Data.categories and D.Data.categories[tostring(a.catId or "")]
            if not istable(c) then return end
            local list = tostring(a.list or "")
            if list ~= "factions" and list ~= "departments" and list ~= "subdepartments" and list ~= "roles" then return end
            local value = tostring(a.value or "")
            if value == "" then return end
            local cur, nextList = toArray(c[list]), {}
            local found = false
            for _, v in ipairs(cur) do
                if v == value then found = true else nextList[#nextList + 1] = v end
            end
            if not found then nextList[#nextList + 1] = value end
            c[list] = nextList
            D.Data.categories[c.id] = D.NormalizeCategory(c, c.id)
            D.SaveCategories()
            D.OpenDoorMenu(ply)

        elseif act == "clear_owner" then
            if not acc.admin then notify(ply, "Только суперадмин.", 255, 100, 100) return end
            rec.owner_type = "none"
            rec.owner_key, rec.owner_nick, rec.owner_faction, rec.owner_category = "", "", "", ""
            rec.rent_until = 0
            persist(rec, id)
            D.ApplyRecordVisual(ent, rec)
            D.SaveDoors()
            notify(ply, "Владелец двери сброшен.", 100, 220, 100)
            D.OpenDoorMenu(ply)

        elseif act == "toggle_ownable" then
            if not acc.admin then
                notify(ply, "Только суперадмин может менять статус приватизации.", 255, 100, 100)
                return
            end
            rec.ownable = not (rec.ownable ~= false)
            persist(rec, id)
            D.SaveDoors()
            notify(ply, rec.ownable and "Дверь сделана доступной для покупки/аренды" or "Дверь заблокирована от приватизации", 100, 220, 100)
            D.OpenDoorMenu(ply)
        end
    end)

    local function chatCommand(ply, text)
        local args = string.Explode(" ", string.Trim(text or ""))
        local cmd = string.lower(args[1] or "")
        if cmd == "/door" or cmd == "!door" then D.OpenDoorMenu(ply) return true end
        if cmd == "/door_audit" or cmd == "/аудит_дверей" then
            if not D.CanAdminDoors(ply) then notify(ply, "Только суперадмин.", 255, 120, 100) return true end
            D.RunAudit(ply, true)
            return true
        end
        if cmd == "/door_rebuild" or cmd == "/пересборка_дверей" then
            if not D.CanAdminDoors(ply) then notify(ply, "Только суперадмин.", 255, 120, 100) return true end
            local opts = {}
            for i = 2, #args do
                local a = string.lower(tostring(args[i] or ""))
                if a == "dry" or a == "check" or a == "проверка" then opts.dry = true end
                if a == "force" then opts.force = true end
                if a == "orphans" or a == "сироты" then opts.dropOrphans = true end
            end
            local log = D.RebuildAll(opts)
            for _, l in ipairs(log) do notify(ply, l, 180, 210, 255) end
            return true
        end

        if cmd == "/lock" or cmd == "!lock" or cmd == "/unlock" or cmd == "!unlock" then
            local ent = aimDoor(ply)
            if IsValid(ent) then
                local rec = select(1, getRecord(ent))
                local acc = D.EvaluateAccess(rec, actorOf(ply, rec))
                if acc.lock then
                    local want = (cmd == "/lock" or cmd == "!lock")
                    D.LockDoor(ent, want)
                    notify(ply, want and "Замок заблокирован." or "Замок разблокирован.", 100, 220, 100)
                else
                    notify(ply, "У вас нет доступа к этой двери.", 255, 100, 100)
                end
            end
            return true
        end
        if cmd == "/warrant" or cmd == "!warrant" then
            local who = args[2]
            if not who then notify(ply, "Использование: /warrant <ник|sid64> [мин] [причина]", 255, 180, 80) return true end
            local sid, mins, reason = who, tonumber(args[3]) or 30, table.concat(args, " ", 4)
            for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                if IsValid(p) and (string.find(string.lower(p:Nick()), string.lower(who), 1, true)
                    or p:SteamID64() == who or p:SteamID() == who) then
                    sid = charKey(p) break
                end
            end
            local ok, err = D.IssueWarrant(ply, sid, mins, reason)
            notify(ply, ok and "Ордер выписан на обыск!" or tostring(err), ok and 100 or 255, ok and 220 or 100, 100)
            return true
        end
        if cmd == "/unwarrant" or cmd == "!unwarrant" then
            local who = args[2]
            if not who then return true end
            local sid = who
            for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                if IsValid(p) and (string.find(string.lower(p:Nick()), string.lower(who), 1, true) or p:SteamID64() == who) then
                    sid = charKey(p) break
                end
            end
            local ok, err = D.RevokeWarrant(ply, sid)
            notify(ply, ok and "Ордер отозван." or tostring(err), ok and 100 or 255, ok and 220 or 100, 100)
            return true
        end
        if cmd == "/warrants" or cmd == "!warrants" then
            local n = 0
            for sid, w in pairs(D.Data.warrants or {}) do
                if D.HasWarrant(sid) then
                    n = n + 1
                    notify(ply, string.format("Ордер: %s (%s) до %s — %s", tostring(w.name), sid,
                        os.date("%H:%M", w.expires or 0), tostring(w.reason)), 220, 180, 80)
                end
            end
            if n == 0 then notify(ply, "Активных ордеров на обыск нет.", 150, 150, 150) end
            return true
        end
    end

    hook.Add("PlayerSayTransform", "GRM_Doors_Commands", function(p, pack)
        if not istable(pack) or not isstring(pack[1]) then return end
        if chatCommand(p, pack[1]) then pack[1] = "" pack.SkipPlayerSay = true end
    end)
    hook.Add("PlayerSay", "GRM_Doors_Chat", function(p, t)
        if chatCommand(p, t) then return "" end
    end)

    timer.Create("GRM_Doors_Tick", 60, 0, function()
        local now = os.time()
        local changed = false
        for id, rec in pairs(D.Data.doors or {}) do
            if istable(rec) and rec.owner_type == "player" and (tonumber(rec.rent_until) or 0) > 0
                and now > (tonumber(rec.rent_until) or 0) then
                rec.owner_type = "none"
                rec.owner_key, rec.owner_nick = "", ""
                rec.co_owners, rec.factions, rec.roles, rec.categories = {}, {}, {}, {}
                rec.rent_until, rec.locked = 0, false
                changed = true
            end
        end
        if changed then D.SaveDoors() end
        for sid, w in pairs(D.Data.warrants or {}) do
            if istable(w) and (tonumber(w.expires) or 0) > 0 and now > (tonumber(w.expires) or 0) then
                D.Data.warrants[sid] = nil
                D.SaveWarrants()
            end
        end
    end)

    -- Три чтения JSON подряд: раньше выполнялись прямо в InitPostEntity
    -- вместе с загрузками ещё двух десятков модулей.
    local function doorsDBBoot()
        D.LoadCategories()
        D.LoadDoors()
        D.LoadWarrants()
    end
    if GRM.Boot and GRM.Boot.Task then
        GRM.Boot.Task("doors.db", "early", doorsDBBoot, { label = "Двери: база владельцев" })
        hook.Add("PostCleanupMap", "GRM_Doors_ReloadDB", function()
            if GRM.Boot.Reset then GRM.Boot.Reset("doors.db") end
        end)
    else
        hook.Add("InitPostEntity", "GRM_Doors_Load", doorsDBBoot)
    end

    print("[GRM Doors] Серверная система дверей v" .. D.Version .. " загружена")
end

-----------------------------------------------------------------------
-- CLIENT
-----------------------------------------------------------------------
if CLIENT then
    CreateClientConVar("grm_cl_doorhud", "1", true, false)
    surface.CreateFont("GRMDoor_Title",  { font = "Roboto", size = 18, weight = 800, extended = true })
    surface.CreateFont("GRMDoor_Sub",    { font = "Roboto", size = 14, weight = 600, extended = true })
    surface.CreateFont("GRMDoor_Normal", { font = "Roboto", size = 13, weight = 500, extended = true })
    surface.CreateFont("GRMDoor_HUD",    { font = "Roboto", size = 19, weight = 800, extended = true })
    surface.CreateFont("GRMDoor_HUDSm",  { font = "Roboto", size = 13, weight = 600, extended = true })

    local function act(t)
        net.Start(NET_ACT) net.WriteTable(t or {}) net.SendToServer()
    end

    net.Receive(NET_INFO, function()
        chat.AddText(Color(70, 160, 240), "[Двери] ", color_white, net.ReadString())
    end)

    hook.Add("HUDShouldDraw", "GRM_Doors_HideGamemodeDoorHUD", function(name)
        if name == "DarkRP_DoorHUD" or name == "RPDoorHUD" or name == "DoorHUD"
            or name == "HUDDrawDoorData" or name == "SuperiorDoorHUD" then
            return false
        end
    end)
    hook.Add("HUDDrawDoorData", "GRM_Doors_SuppressGamemodeDoorData", function() return true end)
    timer.Create("GRM_Doors_SuppressDuplicateHUD", 2, 0, function()
        for _, id in ipairs({ "DarkRP_DoorHUD", "doorHUD", "DrawDoorInfo", "HUDPaint_Doors", "DoorHUD", "SuperiorDoorHUD" }) do
            if id ~= "GRM_Doors_HUD3D2D" then hook.Remove("HUDPaint", id) end
        end
    end)

    local function handleDoorBindOverride()
        local ply = LocalPlayer()
        if not IsValid(ply) then return end
        local tr = ply:GetEyeTrace()
        if IsValid(tr.Entity) and D.IsDoor(tr.Entity) and tr.StartPos:DistToSqr(tr.HitPos) <= 180 * 180 then
            act({ action = "open_menu" })
            return true
        end
    end
    -- Клиентский перехват — тоже только F3; остальные бинды остаются своим
    -- владельцам (F2 — тикеты, F4 — главное меню, F1 — справка).
    hook.Add("ShowSpare1", "GRM_Doors_OverrideF3", handleDoorBindOverride)
    hook.Remove("ShowTeam", "GRM_Doors_OverrideF2")
    hook.Remove("ShowSpare2", "GRM_Doors_OverrideF4")
    hook.Remove("ShowHelp", "GRM_Doors_OverrideF1")

    hook.Add("HUDPaint", "GRM_Doors_HUD3D2D", function()
        local cv = GetConVar("grm_cl_doorhud")
        if cv and cv:GetInt() == 0 then return end
        local ply = LocalPlayer()
        if not IsValid(ply) or not ply:Alive() then return end
        local active = ply:GetActiveWeapon()
        local acls = IsValid(active) and active:GetClass() or ""
        if acls == "grm_keyring" then return end
        -- Общий трейс из глаз (GRM.Perf): один на кадр на все HUD-модули,
        -- вместо собственного GetEyeTrace 60 раз в секунду в каждом.
        local tr = (GRM.Perf and GRM.Perf.EyeTrace) and GRM.Perf.EyeTrace(ply, 0.05) or ply:GetEyeTrace()
        if not tr then return end

        local ent = tr.Entity
        if not IsValid(ent) then return end
        if not D.IsDoor(ent) and not (IsValid(ent:GetParent()) and D.IsDoor(ent:GetParent())) then return end
        local dist = tr.StartPos:DistToSqr(tr.HitPos)
        local maxDist = (D.Config and D.Config.HUDDistance or 220) ^ 2
        if dist > maxDist then return end
        local alpha = math.Clamp((1 - dist / maxDist) * 255, 0, 240)
        local locked = D.IsDoorLocked(ent)
        local title = ent:GetNWString("GRM_DoorTitle", "")
        local ownerStr = ent:GetNWString("GRM_DoorOwner", "")
        local sw, sh = ScrW(), ScrH()
        local cx, cy = sw / 2, sh / 2 + 90
        local bw, bh = 300, 76
        draw.RoundedBox(8, cx - bw / 2, cy, bw, bh, Color(16, 20, 28, alpha * 0.92))
        surface.SetDrawColor(locked and Color(220, 70, 70, alpha) or Color(60, 190, 110, alpha))
        surface.DrawOutlinedRect(cx - bw / 2, cy, bw, bh, 2)
        draw.SimpleText(title ~= "" and title or "Дверь", "GRMDoor_HUD", cx, cy + 18, Color(240, 245, 250, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(ownerStr ~= "" and ownerStr or "Продаётся / Ничья", "GRMDoor_HUDSm", cx, cy + 38, Color(200, 210, 225, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(locked and "[ЗАКРЫТО]" or "[ОТКРЫТО]", "GRMDoor_HUDSm", cx, cy + 58,
            locked and Color(255, 90, 90, alpha) or Color(90, 230, 130, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end)

    --[[ Окно «Управление дверью» переехало в отдельный клиентский модуль
         lua/autorun/client/cl_grm_doors_menu.lua (стиль GRM + редактор
         категорий). Здесь остались HUD, бинды и сеть. ]]

    concommand.Add("grm_door", function()
        net.Start(NET_ACT) net.WriteTable({ action = "open_menu" }) net.SendToServer()
    end)

    print("[GRM Doors] Клиентская система дверей v" .. D.Version .. " загружена")
end

if SERVER and GRM.Modules and GRM.Modules.Register then
    GRM.Modules.Register("doors", {
        label = "Двери и замки", version = (GRM.Doors and GRM.Doors.Version) or "5.0.0",
        Depends = { "access" },
        Status = function()
            local n = 0
            for _ in pairs((GRM.Doors and GRM.Doors.Data and GRM.Doors.Data.doors) or {}) do n = n + 1 end
            return ("дверей в реестре: %d"):format(n)
        end,
    })
end
