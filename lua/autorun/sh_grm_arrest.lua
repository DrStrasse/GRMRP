--[[
    GRM Arrest System v1.1.0
    Категории заключённых, назначаемые камеры и полный режим без оружия.
]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Arrest = GRM.Arrest or {}
local A = GRM.Arrest
A.Version = "1.1.0"
A.File = "grm_arrest.json"
A.Cfg = A.Cfg or {
    model = "models/player/Group03/male_07.mdl",
    groups = {
        criminals = { name = "Уголовники", model = "models/player/Group03/male_07.mdl", cameraIDs = {}, autoPriority = 1000 },
        political = { name = "Политические", model = "models/player/Group03/male_04.mdl", cameraIDs = {}, autoPriority = 20 },
        guardhouse = { name = "Гауптвахта", model = "models/player/Group01/male_07.mdl", cameraIDs = {}, autoPriority = 10 },
    },
    cameras = {},
    spawns = {},
    access = { mode = "all", factions = {} },
    prisonZones = {},
}

local function key(ply)
    if IsValid(ply) and ply:IsPlayer() then
        if GRM.Identity and GRM.Identity.CharacterKey then return GRM.Identity.CharacterKey(ply) end
        return tostring(ply:SteamID64() or ply:SteamID() or "") .. ":char1"
    end
    return tostring(ply or "")
end

--[[ ДАННЫЕ АРЕСТА РАЗДЕЛЕНЫ НА ДВЕ ЧАСТИ (заказ владельца 21.08).

     Раньше камеры, точки содержания и зоны тюрьмы лежали в ОДНОМ файле
     grm_arrest.json вместе с категориями и доступами. Файл общий для всех
     карт, поэтому на новой карте показывались и «срабатывали» точки, которые
     размечались совсем в другом городе: арестованных телепортировало в
     пустоту, зоны тюрьмы висели посреди поля.

     Теперь:
       • ОБЩЕЕ (категории, модели, доступы) — по-прежнему grm_arrest.json;
       • ПРИВЯЗАННОЕ К КАРТЕ (камеры, точки, зоны) — grm_arrest/<карта>.json.
     У каждой записи есть поле map: даже если файл подменят руками, чужие
     записи не загрузятся. Старый общий файл мигрируется в текущую карту
     один раз и очищается. ]]
function A.MapName()
    return string.lower(game and game.GetMap and game.GetMap() or "unknown")
end

local MAP_DIR = "grm_arrest"

function A.MapFile(mapName)
    return MAP_DIR .. "/" .. tostring(mapName or A.MapName()) .. ".json"
end

--- Только записи текущей карты (защита от чужих данных в файле).
local function ofThisMap(list)
    local out = {}
    local here = A.MapName()
    for _, rec in ipairs(istable(list) and list or {}) do
        if istable(rec) then
            local recMap = tostring(rec.map or "")
            if recMap == "" or recMap == here then
                rec.map = here
                out[#out + 1] = rec
            end
        end
    end
    return out
end
A.OfThisMap = ofThisMap

local function saveGlobal()
    if not SERVER then return end
    local global = {
        groups = A.Cfg.groups, access = A.Cfg.access, model = A.Cfg.model,
        version = 2,
    }
    file.Write(A.File, util.TableToJSON(global, true))
end

local function saveMap()
    if not SERVER then return end
    if not file.IsDir(MAP_DIR, "DATA") then file.CreateDir(MAP_DIR) end
    local payload = {
        version = 1, map = A.MapName(),
        cameras = ofThisMap(A.Cfg.cameras),
        spawns = ofThisMap(A.Cfg.spawns),
        prisonZones = ofThisMap(A.Cfg.prisonZones),
    }
    file.Write(A.MapFile(), util.TableToJSON(payload, true))
end

local function save()
    if not SERVER then return end
    saveGlobal()
    saveMap()
end
A.SaveMapData = saveMap
A.SaveGlobalData = saveGlobal

local function normalizeConfig()
    A.Cfg.groups = istable(A.Cfg.groups) and A.Cfg.groups or {}
    A.Cfg.cameras = istable(A.Cfg.cameras) and A.Cfg.cameras or {}
    A.Cfg.spawns = istable(A.Cfg.spawns) and A.Cfg.spawns or {}
    A.Cfg.access = istable(A.Cfg.access) and A.Cfg.access or { mode = "all", factions = {} }
    A.Cfg.access.mode = A.Cfg.access.mode == "allowlist" and "allowlist" or "all"
    A.Cfg.access.factions = istable(A.Cfg.access.factions) and A.Cfg.access.factions or {}
    A.Cfg.prisonZones = istable(A.Cfg.prisonZones) and A.Cfg.prisonZones or {}

    A.Cfg.groups.criminals = istable(A.Cfg.groups.criminals) and A.Cfg.groups.criminals
        or { name = "Уголовники", model = "models/player/Group03/male_07.mdl" }
    A.Cfg.groups.guardhouse = istable(A.Cfg.groups.guardhouse) and A.Cfg.groups.guardhouse
        or { name = "Гауптвахта", model = "models/player/Group01/male_07.mdl" }

    local linked = {}
    for groupID, g in pairs(A.Cfg.groups) do
        if istable(g) then
            g.allowedFactions = istable(g.allowedFactions) and g.allowedFactions or {}
            g.autoPriority = math.floor(tonumber(g.autoPriority) or (groupID == "guardhouse" and 10 or groupID == "criminals" and 1000 or 100))
            local clean, seen = {}, {}
            for _, cameraID in ipairs(istable(g.cameraIDs) and g.cameraIDs or {}) do
                cameraID = tostring(cameraID or "")
                if cameraID ~= "" and not seen[cameraID] then
                    clean[#clean + 1] = cameraID
                    seen[cameraID], linked[cameraID] = true, true
                end
            end
            g.cameraIDs = clean
        end
    end

    -- Одноразовая миграция старой схемы «group лежит в camera» в новую
    -- «категория содержит список камер». Уже назначенные списки не трогаем.
    for _, camera in ipairs(A.Cfg.cameras) do
        local cameraID = tostring(camera.id or "")
        local legacyGroup = tostring(camera.group or "criminals")
        if cameraID ~= "" and not linked[cameraID] and istable(A.Cfg.groups[legacyGroup]) then
            local list = A.Cfg.groups[legacyGroup].cameraIDs
            list[#list + 1] = cameraID
            linked[cameraID] = true
        end
    end
end

local function readJSON(path)
    if not file.Exists(path, "DATA") then return nil end
    local ok, t = pcall(util.JSONToTable, file.Read(path, "DATA") or "", false, true)
    return (ok and istable(t)) and t or nil
end

local function load()
    if not SERVER then return end

    local legacyPoints = nil
    local global = readJSON(A.File)
    if global then
        for k, v in pairs(global) do
            if k ~= "cameras" and k ~= "spawns" and k ~= "prisonZones" then A.Cfg[k] = v end
        end
        -- старый общий файл: точки в нём привязаны к какой-то одной карте
        if istable(global.cameras) or istable(global.spawns) or istable(global.prisonZones) then
            legacyPoints = {
                cameras = istable(global.cameras) and global.cameras or {},
                spawns = istable(global.spawns) and global.spawns or {},
                prisonZones = istable(global.prisonZones) and global.prisonZones or {},
            }
        end
    end

    local mapData = readJSON(A.MapFile())
    if mapData then
        A.Cfg.cameras = ofThisMap(mapData.cameras)
        A.Cfg.spawns = ofThisMap(mapData.spawns)
        A.Cfg.prisonZones = ofThisMap(mapData.prisonZones)
    elseif legacyPoints then
        -- одноразовая миграция: считаем, что старые точки размечены ЗДЕСЬ
        A.Cfg.cameras = ofThisMap(legacyPoints.cameras)
        A.Cfg.spawns = ofThisMap(legacyPoints.spawns)
        A.Cfg.prisonZones = ofThisMap(legacyPoints.prisonZones)
        A.MigratedFrom = "grm_arrest.json"
        print(("[GRM Arrest] точки перенесены в карту %s: камер %d, точек %d, зон %d")
            :format(A.MapName(), #A.Cfg.cameras, #A.Cfg.spawns, #A.Cfg.prisonZones))
        saveMap()
        saveGlobal()   -- в общем файле точек больше нет
    else
        A.Cfg.cameras, A.Cfg.spawns, A.Cfg.prisonZones = {}, {}, {}
    end

    normalizeConfig()
    A.Loaded = true
end

--- Список карт, для которых уже размечены точки.
function A.MapsWithData()
    local out = {}
    if not SERVER then return out end
    local files = file.Find(MAP_DIR .. "/*.json", "DATA")
    for _, name in ipairs(files or {}) do
        out[#out + 1] = string.gsub(tostring(name), "%.json$", "")
    end
    table.sort(out)
    return out
end

--- Перенести разметку с другой карты (аккуратно: с заменой поля map).
function A.ImportFromMap(fromMap)
    if not SERVER then return false, "только сервер" end
    fromMap = string.lower(tostring(fromMap or ""))
    if fromMap == "" or fromMap == A.MapName() then return false, "укажите другую карту" end
    local data = readJSON(A.MapFile(fromMap))
    if not data then return false, "для этой карты разметки нет" end
    local here = A.MapName()
    local function adopt(list)
        local out = {}
        for _, rec in ipairs(istable(list) and list or {}) do
            if istable(rec) then rec.map = here out[#out + 1] = rec end
        end
        return out
    end
    A.Cfg.cameras = adopt(data.cameras)
    A.Cfg.spawns = adopt(data.spawns)
    A.Cfg.prisonZones = adopt(data.prisonZones)
    saveMap()
    return true, ("перенесено: камер %d, точек %d, зон %d")
        :format(#A.Cfg.cameras, #A.Cfg.spawns, #A.Cfg.prisonZones)
end

--- Убрать всю разметку текущей карты.
function A.ClearMapData()
    A.Cfg.cameras, A.Cfg.spawns, A.Cfg.prisonZones = {}, {}, {}
    if SERVER then saveMap() end
    return true
end

    local function group(id)
        return A.Cfg.groups[tostring(id or "")] or A.Cfg.groups.criminals
    end

    if SERVER then
    util.AddNetworkString("GRM_Arrest_Admin")
    util.AddNetworkString("GRM_Arrest_AdminData")
    util.AddNetworkString("GRM_Arrest_AdminAction")
    util.AddNetworkString("GRM_Arrest_Event")
    util.AddNetworkString("GRM_Arrest_AccessRequest")
    util.AddNetworkString("GRM_Arrest_AccessData")
    util.AddNetworkString("GRM_Arrest_AccessSave")
    util.AddNetworkString("GRM_Arrest_CategoryAccessRequest")
    util.AddNetworkString("GRM_Arrest_CategoryAccessData")
    util.AddNetworkString("GRM_Arrest_CategoryAccessSave")
    util.AddNetworkString("GRM_Arrest_ZoneRequest")
    util.AddNetworkString("GRM_Arrest_ZoneData")

    load()

    function A.CanArrest(ply)
        if not IsValid(ply) or not ply:IsPlayer() then return false end
        if ply:IsSuperAdmin() then return true end
        local access = A.Cfg.access or {}
        if access.mode ~= "allowlist" then return true end
        for factionName, allowed in pairs(access.factions or {}) do
            if allowed and GRM.Identity and GRM.Identity.FactionMember and Factions and Factions[factionName]
                and GRM.Identity.FactionMember(Factions[factionName], ply) then
                return true
            end
        end
        return false
    end

    function A.AddPrisonZone(a, b, name)
        local mn = Vector(math.min(a.x, b.x), math.min(a.y, b.y), math.min(a.z, b.z))
        local mx = Vector(math.max(a.x, b.x), math.max(a.y, b.y), math.max(a.z, b.z))
        A.Cfg.prisonZones[#A.Cfg.prisonZones + 1] = { name = tostring(name or "Тюрьма"), map = A.MapName(),
            min = { x = mn.x, y = mn.y, z = mn.z }, max = { x = mx.x, y = mx.y, z = mx.z } }
        save()
        return true
    end

    function A.IsInPrisonZone(ply)
        if not IsValid(ply) then return false end
        local here = A.MapName()
        for _, zone in ipairs(A.Cfg.prisonZones or {}) do
            -- В GMod нет goto (continue — зарезервированное слово его парсера),
            -- поэтому фильтр карты — обычным условием.
            if tostring(zone.map or here) == here then
                local mn, mx = zone.min or {}, zone.max or {}
                local pos = ply:GetPos()
                if pos.x >= (mn.x or 0) and pos.x <= (mx.x or 0)
                    and pos.y >= (mn.y or 0) and pos.y <= (mx.y or 0)
                    and pos.z >= (mn.z or -math.huge) and pos.z <= (mx.z or math.huge) then
                    return true
                end
            end
        end
        return false
    end

    function A.FactionOf(target)
        if not IsValid(target) then return "" end
        for factionName, faction in pairs(Factions or {}) do
            if GRM.Identity and GRM.Identity.FactionMember and GRM.Identity.FactionMember(faction, target) then return tostring(factionName) end
        end
        return ""
    end

    function A.ResolveGroupForTarget(target, requested)
        requested = string.lower(string.Trim(tostring(requested or "auto")))
        if requested ~= "" and requested ~= "auto" then
            return A.Cfg.groups[requested] and requested or nil
        end

        local factionName = A.FactionOf(target)
        if factionName == "" then return "criminals" end

        -- Автораспределение детерминировано: категории сортируются по
        -- autoPriority, затем ID. Поэтому «Гауптвахта» не зависит от pairs().
        local candidates = {}
        for groupID, g in pairs(A.Cfg.groups or {}) do
            if groupID ~= "criminals" and istable(g) and istable(g.allowedFactions)
                and g.allowedFactions[factionName] == true then
                candidates[#candidates + 1] = { id = tostring(groupID), priority = tonumber(g.autoPriority) or 100 }
            end
        end
        table.sort(candidates, function(a, b)
            if a.priority == b.priority then return a.id < b.id end
            return a.priority < b.priority
        end)
        return candidates[1] and candidates[1].id or "criminals"
    end

    function A.CanUseGroup(target, groupID)
        local g = group(groupID)
        local allowed = g and g.allowedFactions or {}
        local hasRestriction = false
        for _, enabled in pairs(allowed) do
            if enabled == true then hasRestriction = true break end
        end
        if not hasRestriction then return true end
        if not IsValid(target) or not target:IsPlayer() then return false end
        for factionName, enabled in pairs(allowed) do
            if enabled and Factions and Factions[factionName]
                and GRM.Identity and GRM.Identity.FactionMember
                and GRM.Identity.FactionMember(Factions[factionName], target) then
                return true
            end
        end
        return false
    end

    local function announce(event, targetName, groupName)
        net.Start("GRM_Arrest_Event")
            net.WriteString(event or "")
            net.WriteString(targetName or "")
            net.WriteString(groupName or "")
        net.Broadcast()
    end

    local function vec(t) return Vector(tonumber(t.x) or 0, tonumber(t.y) or 0, tonumber(t.z) or 0) end
    local function ang(t) return Angle(tonumber(t.p) or 0, tonumber(t.y) or 0, tonumber(t.r) or 0) end
    local function vdata(v) return { x = v.x, y = v.y, z = v.z } end
    local function adata(a) return { p = a.p, y = a.y, r = a.r } end

    local function spawnCamera(rec)
        local ent = ents.Create("grm_arrest_camera")
        if not IsValid(ent) then return nil end
        ent:SetPos(vec(rec.pos)) ent:SetAngles(ang(rec.ang))
        ent:Spawn() ent:Activate()
        ent:SetCameraID(rec.id or "")
        ent:SetCameraName(rec.name or rec.id or "Камера")
        ent:SetArrestGroup(rec.group or "criminals")
        ent.GRMArrestID = rec.id
        local phys = ent:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
        return ent
    end

    local function loadCameras()
        for _, ent in ipairs(ents.FindByClass("grm_arrest_camera")) do ent:Remove() end
        for _, rec in ipairs(A.Cfg.cameras or {}) do if istable(rec) then spawnCamera(rec) end end
    end

    function A.SaveConfig()
        save()
        return true
    end

    function A.LoadConfig()
        load()
        loadCameras()
        return true
    end

    function A.OpenAdmin(ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        --[[ Снимок собираем ЯВНО и только по текущей карте: так админ видит
             ровно то, что здесь работает, а не свалку со всех карт. ]]
        local snapshot = {
            groups = A.Cfg.groups,
            access = A.Cfg.access,
            model = A.Cfg.model,
            cameras = ofThisMap(A.Cfg.cameras),
            spawns = ofThisMap(A.Cfg.spawns),
            prisonZones = ofThisMap(A.Cfg.prisonZones),
            map = A.MapName(),
            maps = A.MapsWithData(),
        }
        if GRM.Net and GRM.Net.Stream then
            GRM.Net.Stream("GRM_Arrest_AdminData", snapshot, ply, { chunk = 8192, interval = 0.03 })
            return
        end
        net.Start("GRM_Arrest_AdminData")
            net.WriteTable(snapshot)
        net.Send(ply)
    end

    local function nearestPlayer(ply)
        if ply.GRM_Captives then
            for captive in pairs(ply.GRM_Captives) do if IsValid(captive) and GRM.Handcuffs and GRM.Handcuffs.IsCuffed(captive) then return captive end end
        end
        local tr = ply:GetEyeTrace()
        local target = tr and tr.Entity
        if IsValid(target) and target:IsPlayer() and target ~= ply and ply:GetPos():DistToSqr(target:GetPos()) <= 220 * 220 then return target end
        -- Команда должна работать по сопровождаемому задержанному, даже
        -- если прицел упирается в дверь/решётку/стену рядом с ним.
        local best, bestDist
        for _, candidate in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(candidate) and candidate ~= ply and candidate:IsPlayer()
                and GRM.Handcuffs and GRM.Handcuffs.IsCuffed and GRM.Handcuffs.IsCuffed(candidate) then
                local dist = ply:GetPos():DistToSqr(candidate:GetPos())
                if dist <= 220 * 220 and (not bestDist or dist < bestDist) then best, bestDist = candidate, dist end
            end
        end
        return best
    end

    local function cameraByID(cameraID)
        cameraID = tostring(cameraID or "")
        for _, rec in ipairs(A.Cfg.cameras or {}) do
            if tostring(rec.id or "") == cameraID then return rec end
        end
    end

    local function spawnByID(spawnID)
        spawnID = tostring(spawnID or "")
        for _, rec in ipairs(A.Cfg.spawns or {}) do
            if tostring(rec.id or "") == spawnID then return rec end
        end
    end

    local function chooseCamera(groupID)
        local g = A.Cfg.groups[tostring(groupID or "")]
        if not istable(g) then return nil end

        local candidates = {}
        for _, cameraID in ipairs(g.cameraIDs or {}) do
            local rec = cameraByID(cameraID)
            -- Камера без собственной точки не участвует в размещении.
            if rec and spawnByID(rec.spawnID) then
                candidates[#candidates + 1] = { camera = rec, occupied = 0 }
            end
        end
        if #candidates == 0 then return nil end

        -- Выбираем наименее занятую камеру категории. Так уголовники и
        -- гауптвахта не сваливаются всегда в первую точку.
        for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(ply) and ply:GetNWBool("GRM_Arrested", false)
                and ply:GetNWString("GRM_ArrestGroup", "") == tostring(groupID) then
                local occupiedID = ply:GetNWString("GRM_ArrestCameraID", "")
                for _, item in ipairs(candidates) do
                    if tostring(item.camera.id) == occupiedID then item.occupied = item.occupied + 1 end
                end
            end
        end
        table.sort(candidates, function(a, b)
            if a.occupied == b.occupied then return tostring(a.camera.id) < tostring(b.camera.id) end
            return a.occupied < b.occupied
        end)
        return candidates[1].camera
    end

    local function chooseSpawn(camera)
        return camera and spawnByID(camera.spawnID) or nil
    end

    local function confiscateInventory(target)
        local invAPI = GRM.Inventory
        if not (invAPI and invAPI.GetPlayerInv and invAPI.RemoveFromSlot) then return 0 end
        local inv = invAPI.GetPlayerInv(target)
        if not inv or not istable(inv.slots) then return 0 end

        local removed = 0
        local indexes = {}
        for slotIndex, slot in pairs(inv.slots) do
            if istable(slot) and slot.id then
                indexes[#indexes + 1] = tonumber(slotIndex) or slotIndex
                removed = removed + math.max(1, tonumber(slot.count) or 1)
            end
        end
        for _, slotIndex in ipairs(indexes) do
            invAPI.RemoveFromSlot(target, slotIndex, math.huge)
        end
        if invAPI.SyncToClient then invAPI.SyncToClient(target) end
        return removed
    end

    function A.EnforceUnarmed(target)
        if not IsValid(target) or not target:GetNWBool("GRM_Arrested", false) then return false end
        target:StripWeapons()
        if target.RemoveAllAmmo then target:RemoveAllAmmo() end
        -- Наручники хранят прежний loadout для возврата. При оформленном
        -- аресте это хранилище уничтожается: конфискованное не воскреснет.
        target.GRM_CuffStoredWeapons = nil
        return true
    end

    function A.Confiscate(target)
        if not IsValid(target) then return 0 end
        A.EnforceUnarmed(target)
        local removed = confiscateInventory(target)
        if GRM.Customization and GRM.Customization.Confiscate then
            removed = removed + (tonumber(GRM.Customization.Confiscate(target)) or 0)
        end
        return removed
    end

    local applyArrestAppearance

    function A.ArrestPlayer(actor, target, groupID)
        if not IsValid(actor) or not IsValid(target) then return false, "Цель не найдена" end
        local HC = GRM.Handcuffs
        if not (HC and HC.IsCuffed and HC.IsCuffed(target)) then return false, "Сначала наденьте на человека наручники" end
        if target:GetNWBool("GRM_Arrested", false) then return false, "Человек уже арестован" end
        local wanted = GRM.Wanted and GRM.Wanted.GetLevel and GRM.Wanted.GetLevel(target) or 0
        if wanted <= 0 then return false, "Сначала объявите игрока в розыск" end
        if not A.IsInPrisonZone(target) then return false, "Доставьте задержанного в тюрьму или на гауптвахту" end
        groupID = A.ResolveGroupForTarget(target, groupID)
        if not groupID or not A.Cfg.groups[groupID] then return false, "Категория ареста не существует" end
        local g = group(groupID)
        if not A.CanUseGroup(target, groupID) then
            return false, "Эта категория недоступна для фракции задержанного"
        end
        local cam = chooseCamera(groupID)
        if not cam then return false, "Категории не назначена ни одна камера с точкой размещения" end
        local sp = chooseSpawn(cam)
        if not sp then return false, "Для выбранной камеры не назначена точка арестованного" end
        target.GRM_ArrestOriginalModel = target:GetModel()
        target.GRM_ArrestOriginalSkin = target:GetSkin()
        target.GRM_ArrestOriginalBodygroups = {}
        for i = 0, (target:GetNumBodyGroups() or 0) - 1 do target.GRM_ArrestOriginalBodygroups[i] = target:GetBodygroup(i) end
        target:SetNWBool("GRM_Arrested", true)
        A.ArrestedCount = (A.ArrestedCount or 0) + 1
        target:SetNWString("GRM_ArrestGroup", groupID or "criminals")
        target:SetNWString("GRM_ArrestGroupName", g.name or groupID or "Арестованный")
        target:SetNWString("GRM_ArrestCameraID", tostring(cam.id or ""))

        -- Сначала прекращаем сопровождение, затем окончательно конфискуем
        -- оружие, инструменты, патроны и содержимое GRM Inventory.
        if HC and HC.StopDragging then
            local dragger = target:GetNWEntity("GRM_CuffDragger")
            HC.StopDragging(IsValid(dragger) and dragger or actor, target)
        end
        local confiscated = A.Confiscate(target)

        if applyArrestAppearance then applyArrestAppearance(target, g) end
        target:SetPos(vec(sp.pos))
        target:SetEyeAngles(ang(sp.ang or { p = 0, y = 0, r = 0 }))
        target:Freeze(false)
        if GRM.Notify then GRM.Notify(target, "Вы арестованы: " .. tostring(g.name), 255, 150, 100) end
        actor:ChatPrint("[Арест] Арестованный отправлен в «" .. tostring(g.name)
            .. "», камера «" .. tostring(cam.name or cam.id) .. "». Изъято предметов: " .. tostring(confiscated))
        announce("arrest", target:Nick(), g.name or groupID or "Арестованный")
        return true
    end

    function A.UnarrestPlayer(actor, target)
        if not IsValid(target) or not target:GetNWBool("GRM_Arrested", false) then return false end
        target:SetNWBool("GRM_Arrested", false)
        A.ArrestedCount = math.max(0, (A.ArrestedCount or 1) - 1)
        target:SetNWString("GRM_ArrestGroup", "")
        target:SetNWString("GRM_ArrestGroupName", "")
        target:SetNWString("GRM_ArrestCameraID", "")
        if target.GRM_ArrestOriginalModel and util.IsValidModel(target.GRM_ArrestOriginalModel) then target:SetModel(target.GRM_ArrestOriginalModel) end
        target:SetSkin(tonumber(target.GRM_ArrestOriginalSkin) or 0)
        for group, value in pairs(target.GRM_ArrestOriginalBodygroups or {}) do target:SetBodygroup(tonumber(group) or 0, tonumber(value) or 0) end
        target.GRM_ArrestOriginalModel = nil
        target.GRM_ArrestOriginalSkin = nil
        target.GRM_ArrestOriginalBodygroups = nil
        if GRM.Notify then GRM.Notify(target, "Вы освобождены.", 120, 220, 140) end
        announce("unarrest", target:Nick(), "")
        return true
    end

    hook.Add("CanPlayerSuicide", "GRM_Arrest_BlockSuicide", function(ply)
        if IsValid(ply) and ply:GetNWBool("GRM_Arrested", false) then
            if GRM.Notify then GRM.Notify(ply, "Самоубийство во время ареста запрещено.", 255, 100, 100) end
            return false
        end
        -- Запрещаем консольный kill для всех игроков RP-сервера.
        if IsValid(ply) and not ply:IsSuperAdmin() then
            if GRM.Notify then GRM.Notify(ply, "Команда kill запрещена.", 255, 100, 100) end
            return false
        end
    end)

    -- Арестованный не получает оружие ни из sandbox/gamemode, ни из
    -- /weapons_admin, ни от стороннего аддона. Таймер — последний fail-safe.
    hook.Add("PlayerLoadout", "GRM_Arrest_BlockLoadout", function(ply)
        if not IsValid(ply) or not ply:GetNWBool("GRM_Arrested", false) then return end
        timer.Simple(0, function() if IsValid(ply) then A.EnforceUnarmed(ply) end end)
        return true
    end)
    hook.Add("PlayerCanPickupWeapon", "GRM_Arrest_BlockWeaponPickup", function(ply)
        if IsValid(ply) and ply:GetNWBool("GRM_Arrested", false) then return false end
    end)
    hook.Add("PlayerCanPickupItem", "GRM_Arrest_BlockItemPickup", function(ply)
        if IsValid(ply) and ply:GetNWBool("GRM_Arrested", false) then return false end
    end)
    hook.Add("PlayerGiveSWEP", "GRM_Arrest_BlockGiveSWEP", function(ply)
        if IsValid(ply) and ply:GetNWBool("GRM_Arrested", false) then return false end
    end)
    hook.Add("PlayerSpawnSWEP", "GRM_Arrest_BlockSpawnSWEP", function(ply)
        if IsValid(ply) and ply:GetNWBool("GRM_Arrested", false) then return false end
    end)
    hook.Add("WeaponEquip", "GRM_Arrest_RemoveEquippedWeapon", function(weapon, ply)
        if not IsValid(ply) or not ply:GetNWBool("GRM_Arrested", false) then return end
        timer.Simple(0, function()
            if IsValid(weapon) then weapon:Remove() end
            if IsValid(ply) then A.EnforceUnarmed(ply) end
        end)
    end)
    -- Аудит нагрузки 18.08: таймер обходил ВСЕХ игроков 4 раза в секунду,
    -- хотя арестованных обычно ноль. Теперь проход идёт раз в 0.5 с и только
    -- когда на сервере реально есть хоть один арестованный (флаг ставит
    -- сам модуль ареста при посадке/освобождении).
    timer.Create("GRM_Arrest_EnforceUnarmed", 0.5, 0, function()
        if (A.ArrestedCount or 0) <= 0 then return end
        local seen = 0
        for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(ply) and ply:GetNWBool("GRM_Arrested", false) then
                A.EnforceUnarmed(ply)
                seen = seen + 1
            end
        end
        A.ArrestedCount = seen
    end)

    -- Счётчик арестованных: дешёвая замена постоянному сканированию.
    function A.RefreshArrestedCount()
        local n = 0
        for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(ply) and ply:GetNWBool("GRM_Arrested", false) then n = n + 1 end
        end
        A.ArrestedCount = n
        return n
    end
    hook.Add("GRM_ArrestStateChanged", "GRM_Arrest_CountWatch", function() A.RefreshArrestedCount() end)
    hook.Add("PlayerDisconnected", "GRM_Arrest_CountWatch", function() timer.Simple(0, function() A.RefreshArrestedCount() end) end)
    timer.Simple(5, function() if A.RefreshArrestedCount then A.RefreshArrestedCount() end end)

    local function handleArrestChatCommand(ply, text)
        if not IsValid(ply) or not ply:IsPlayer() then return false end
        local msg = string.Trim(text or "")
        local low = string.lower(msg)

        if low == "/grm_arrest_admin" or low == "!grm_arrest_admin" then
            if not ply:IsSuperAdmin() then
                ply:ChatPrint("[Арест] Админ-панель доступна только суперадмину.")
            else
                A.OpenAdmin(ply)
            end
            return true
        end

        if low == "/arrest" or low == "!arrest" or low:sub(1, 8) == "/arrest " or low:sub(1, 8) == "!arrest " then
            if not A.CanArrest(ply) then
                ply:ChatPrint("[Арест] Ваша фракция не имеет доступа к системе ареста.")
                return true
            end
            local gid = string.Trim(msg:sub(8))
            if gid == "" then gid = "auto" end
            local target = nearestPlayer(ply)
            local ok, err = A.ArrestPlayer(ply, target, gid)
            if not ok then ply:ChatPrint("[Арест] " .. tostring(err)) end
            return true
        end

        if low == "/unarrest" or low == "!unarrest" then
            if not A.CanArrest(ply) then
                ply:ChatPrint("[Арест] Ваша фракция не имеет доступа к системе ареста.")
                return true
            end
            local target = nearestPlayer(ply)
            if not A.UnarrestPlayer(ply, target) then ply:ChatPrint("[Арест] Цель не арестована.") end
            return true
        end

        return false
    end

    -- EasyChat вызывает transform до PlayerSay. Обрабатываем команды здесь,
    -- а PlayerSay сохраняем fallback-ом для стандартного чата.
    hook.Add("PlayerSay", "GRM_Arrest_Commands", function(ply, text, teamSays)
        local datapack = { tostring(text or ""), SkipPlayerSay = false }
            if not istable(datapack) or not isstring(datapack[1]) then return end
            if not handleArrestChatCommand(ply, datapack[1]) then return end
            datapack[1] = ""
            datapack.SkipPlayerSay = true

        if datapack.SkipPlayerSay == true then return "" end
    end)

    hook.Add("PlayerSay", "GRM_Arrest_CommandsFallback", function(ply, text)
        if handleArrestChatCommand(ply, text) then return "" end
    end)

    net.Receive("GRM_Arrest_ZoneRequest", function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        -- тулу уходят ТОЛЬКО зоны этой карты
        net.Start("GRM_Arrest_ZoneData")
            net.WriteString(A.MapName())
            net.WriteTable(ofThisMap(A.Cfg.prisonZones))
        net.Send(ply)
    end)

    net.Receive("GRM_Arrest_Admin", function(_, ply) A.OpenAdmin(ply) end)
    net.Receive("GRM_Arrest_AdminAction", function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        local action = net.ReadString()
        local id = string.Trim(net.ReadString() or "")
        if action == "add_camera" then
            local tr = ply:GetEyeTrace()
            local rec = { id = id ~= "" and id or ("cam_" .. os.time()), name = id ~= "" and id or ("Камера " .. tostring(#A.Cfg.cameras + 1)), group = "criminals", map = A.MapName(), pos = vdata(tr.HitPos), ang = adata(Angle(0, ply:EyeAngles().y, 0)), spawnID = "" }
            A.Cfg.cameras[#A.Cfg.cameras + 1] = rec
            local defaultGroup = A.Cfg.groups.criminals
            if defaultGroup then defaultGroup.cameraIDs[#defaultGroup.cameraIDs + 1] = rec.id end
            spawnCamera(rec) save()
        elseif action == "delete_camera" then
            for i = #A.Cfg.cameras, 1, -1 do
                local cam = A.Cfg.cameras[i]
                if tostring(cam.id) == id then
                    for _, ent in ipairs(ents.FindByClass("grm_arrest_camera")) do
                        if ent.GRMArrestID == cam.id then ent:Remove() end
                    end
                    table.remove(A.Cfg.cameras, i)
                    for _, g in pairs(A.Cfg.groups or {}) do
                        if istable(g) then
                            for j = #(g.cameraIDs or {}), 1, -1 do
                                if tostring(g.cameraIDs[j]) == id then table.remove(g.cameraIDs, j) end
                            end
                        end
                    end
                    break
                end
            end
            save()
        elseif action == "add_spawn" then
            local rec = { id = id ~= "" and id or ("spawn_" .. os.time()), name = id ~= "" and id or ("Точка ареста " .. tostring(#A.Cfg.spawns + 1)), map = A.MapName(), pos = vdata(ply:GetPos()), ang = adata(ply:EyeAngles()) }
            A.Cfg.spawns[#A.Cfg.spawns + 1] = rec save()
        elseif action == "delete_spawn" then
            for i = #A.Cfg.spawns, 1, -1 do
                if tostring(A.Cfg.spawns[i].id) == id then
                    table.remove(A.Cfg.spawns, i)
                    break
                end
            end
            for _, cam in ipairs(A.Cfg.cameras or {}) do
                if tostring(cam.spawnID or "") == id then cam.spawnID = "" end
            end
            save()
        elseif action == "map_clear" then
            A.ClearMapData()
            for _, ent in ipairs(ents.FindByClass("grm_arrest_camera")) do ent:Remove() end
            if GRM.Notify then GRM.Notify(ply, "Разметка ареста этой карты очищена.", 255, 200, 120) end
            A.OpenAdmin(ply)
        elseif action == "map_import" then
            local okImport, msg = A.ImportFromMap(id)
            if GRM.Notify then
                GRM.Notify(ply, okImport and ("Импорт с карты " .. id .. ": " .. tostring(msg))
                    or ("Импорт не выполнен: " .. tostring(msg)), okImport and 100 or 255,
                    okImport and 220 or 140, 120)
            end
            if okImport then loadCameras() end
            A.OpenAdmin(ply)
        elseif action == "set_group" then
            local name = string.Trim(net.ReadString() or "")
            local model = string.Trim(net.ReadString() or "")
            if id:match("^[%w_%-]+$") and name ~= "" then
                A.Cfg.groups[id] = A.Cfg.groups[id] or {}
                A.Cfg.groups[id].name = name
                A.Cfg.groups[id].allowedFactions = A.Cfg.groups[id].allowedFactions or {}
                A.Cfg.groups[id].cameraIDs = A.Cfg.groups[id].cameraIDs or {}
                A.Cfg.groups[id].autoPriority = tonumber(A.Cfg.groups[id].autoPriority) or 100
                if model ~= "" and util.IsValidModel(model) then A.Cfg.groups[id].model = model end
                save()
            end
        elseif action == "set_group_model" then
            local model = string.Trim(net.ReadString() or "")
            if A.Cfg.groups[id] and model:match("^models/.+%.mdl$") then
                A.Cfg.groups[id].model = model
                save()
            end
        elseif action == "set_group_data" then
            local data = net.ReadTable() or {}
            local model = string.Trim(tostring(data.model or ""))
            if A.Cfg.groups[id] and model:match("^models/.+%.mdl$") then
                A.Cfg.groups[id].model = model
                A.Cfg.groups[id].skin = math.max(0, math.floor(tonumber(data.skin) or 0))
                A.Cfg.groups[id].bodygroups = {}
                for group, value in pairs(data.bodygroups or {}) do
                    local gi, vi = tonumber(group), tonumber(value)
                    if gi and vi then A.Cfg.groups[id].bodygroups[gi] = vi end
                end
                A.Cfg.groups[id].allowedFactions = {}
                for factionName, enabled in pairs(data.allowedFactions or {}) do
                    if isstring(factionName) and #factionName <= 96 and enabled == true then
                        A.Cfg.groups[id].allowedFactions[factionName] = true
                    end
                end
                save()
            end
        elseif action == "set_camera_group" then
            local groupID = string.Trim(net.ReadString() or "")
            if A.Cfg.groups[groupID] and cameraByID(id) then
                -- Старый UI назначает одну категорию камере. Синхронизируем
                -- его с новой авторитетной схемой category.cameraIDs.
                for _, g in pairs(A.Cfg.groups) do
                    for i = #(g.cameraIDs or {}), 1, -1 do
                        if tostring(g.cameraIDs[i]) == id then table.remove(g.cameraIDs, i) end
                    end
                end
                A.Cfg.groups[groupID].cameraIDs[#A.Cfg.groups[groupID].cameraIDs + 1] = id
                local cam = cameraByID(id)
                if cam then cam.group = groupID end -- legacy-зеркало
                save()
            end
        elseif action == "set_group_cameras" then
            local incoming = net.ReadTable() or {}
            local g = A.Cfg.groups[id]
            if istable(g) then
                local selected, seen = {}, {}
                for _, cameraID in ipairs(incoming) do
                    cameraID = tostring(cameraID or "")
                    if cameraID ~= "" and cameraByID(cameraID) and not seen[cameraID] then
                        selected[#selected + 1] = cameraID
                        seen[cameraID] = true
                    end
                end
                table.sort(selected)
                g.cameraIDs = selected
                save()
            end
        elseif action == "assign_camera_spawn" then
            local spawnID = string.Trim(net.ReadString() or "")
            for _, cam in ipairs(A.Cfg.cameras) do if cam.id == id then cam.spawnID = spawnID end end
            save()
        elseif action == "reload" then
            loadCameras()
        end
        A.OpenAdmin(ply)
    end)

    net.Receive("GRM_Arrest_AccessRequest", function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        net.Start("GRM_Arrest_AccessData")
            net.WriteTable(A.Cfg.access or { mode = "all", factions = {} })
        net.Send(ply)
    end)

    net.Receive("GRM_Arrest_AccessSave", function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        local mode = net.ReadBool() and "allowlist" or "all"
        local incoming = net.ReadTable() or {}
        local factions = {}
        for name, allowed in pairs(incoming) do
            if isstring(name) and #name <= 96 and allowed == true then factions[name] = true end
        end
        A.Cfg.access = { mode = mode, factions = factions }
        save()
        net.Start("GRM_Arrest_AccessData") net.WriteTable(A.Cfg.access) net.Send(ply)
    end)

    net.Receive("GRM_Arrest_CategoryAccessRequest", function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        net.Start("GRM_Arrest_CategoryAccessData") net.WriteTable(A.Cfg.groups or {}) net.Send(ply)
    end)

    net.Receive("GRM_Arrest_CategoryAccessSave", function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        local groupID, selected = net.ReadString(), net.ReadTable() or {}
        local g = A.Cfg.groups[groupID]
        if not istable(g) then return end
        g.allowedFactions = {}
        for factionName, enabled in pairs(selected) do
            if isstring(factionName) and #factionName <= 96 and enabled == true then g.allowedFactions[factionName] = true end
        end
        save()
        net.Start("GRM_Arrest_CategoryAccessData") net.WriteTable(A.Cfg.groups or {}) net.Send(ply)
    end)

    concommand.Add("grm_arrest_admin", function(ply) A.OpenAdmin(ply) end)
    concommand.Add("grm_arrest_reload", function(ply) if not IsValid(ply) or ply:IsSuperAdmin() then loadCameras() end end)

    --[[ Диагностика и обслуживание разметки по картам. ]]
    local function printMapReport(ply)
        local function say(text)
            if IsValid(ply) then ply:ChatPrint(text) else print(text) end
        end
        say(("[Арест] карта %s: камер %d, точек %d, зон %d"):format(
            A.MapName(), #ofThisMap(A.Cfg.cameras), #ofThisMap(A.Cfg.spawns), #ofThisMap(A.Cfg.prisonZones)))
        local maps = A.MapsWithData()
        if #maps > 0 then say("[Арест] разметка есть на картах: " .. table.concat(maps, ", ")) end
        for _, cam in ipairs(ofThisMap(A.Cfg.cameras)) do
            say(("   камера %s — точка %s"):format(tostring(cam.id),
                tostring(cam.spawnID ~= "" and cam.spawnID or "НЕ НАЗНАЧЕНА")))
        end
    end

    concommand.Add("grm_arrest_points", function(ply)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        printMapReport(ply)
    end)
    concommand.Add("grm_arrest_maps", function(ply)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        local maps = A.MapsWithData()
        local line = #maps > 0 and table.concat(maps, ", ") or "нет"
        if IsValid(ply) then ply:ChatPrint("[Арест] карты с разметкой: " .. line) else print(line) end
    end)
    concommand.Add("grm_arrest_map_clear", function(ply)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        A.ClearMapData()
        for _, ent in ipairs(ents.FindByClass("grm_arrest_camera")) do ent:Remove() end
        if IsValid(ply) then ply:ChatPrint("[Арест] разметка этой карты очищена.") end
    end)
    concommand.Add("grm_arrest_import", function(ply, _, args)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        local okImport, msg = A.ImportFromMap(args and args[1])
        if okImport then loadCameras() end
        local text = "[Арест] " .. (okImport and ("импорт выполнен: " .. tostring(msg)) or ("импорт не выполнен: " .. tostring(msg)))
        if IsValid(ply) then ply:ChatPrint(text) else print(text) end
    end)
if GRM.Boot and GRM.Boot.Task then
    GRM.Boot.Task("arrest.cameras", "late", function() loadCameras() end, { label = "Арест: камеры содержания" })
else
    hook.Add("InitPostEntity", "GRM_Arrest_LoadCameras", function() timer.Simple(2, loadCameras) end)
end
    hook.Add("PostCleanupMap", "GRM_Arrest_Cleanup", function() timer.Simple(0.5, loadCameras) end)
    hook.Add("ShutDown", "GRM_Arrest_Save", save)

    applyArrestAppearance = function(ply, g)
        if not IsValid(ply) or not istable(g) then return end
        local desiredModel = tostring(g.model or "")
        local modelChanged = desiredModel ~= "" and string.lower(ply:GetModel() or "") ~= string.lower(desiredModel)
        local desiredSkin = math.max(0, math.floor(tonumber(g.skin) or 0))
        local skinChanged = ply:GetSkin() ~= desiredSkin
        local bodyChanged = false
        for i = 0, (ply:GetNumBodyGroups() or 0) - 1 do
            local wanted = tonumber(g.bodygroups and g.bodygroups[i] or 0) or 0
            if ply:GetBodygroup(i) ~= wanted then bodyChanged = true break end
        end
        if not modelChanged and not skinChanged and not bodyChanged then return end
        if modelChanged and util.IsValidModel(desiredModel) then ply:SetModel(desiredModel) end
        -- Сначала жёстко сбрасываем случайные bodygroups модели, затем
        -- применяем только сохранённые значения категории ареста.
        for i = 0, (ply:GetNumBodyGroups() or 0) - 1 do ply:SetBodygroup(i, 0) end
        local maxSkin = math.max(0, (ply:SkinCount() or 1) - 1)
        ply:SetSkin(math.Clamp(desiredSkin, 0, maxSkin))
        for groupID, value in pairs(g.bodygroups or {}) do ply:SetBodygroup(tonumber(groupID) or 0, tonumber(value) or 0) end
    end

    -- Apply once on arrest and after a respawn race. Faction/character/mask
    -- setters are guarded while GRM_Arrested is true, so no permanent timer
    -- is needed and the model cannot visibly flicker.
    hook.Add("PlayerSpawn", "GRM_Arrest_AppearanceAfterSpawn", function(ply)
        timer.Simple(0.2, function()
            if IsValid(ply) and ply:GetNWBool("GRM_Arrested", false) then
                A.EnforceUnarmed(ply)
                local groupID = ply:GetNWString("GRM_ArrestGroup", "criminals")
                local g = group(groupID)
                local cameraID = ply:GetNWString("GRM_ArrestCameraID", "")
                local cam = cameraByID(cameraID)
                local allowed = false
                for _, assignedID in ipairs(g.cameraIDs or {}) do
                    if tostring(assignedID) == cameraID then allowed = true break end
                end
                if not cam or not allowed or not chooseSpawn(cam) then cam = chooseCamera(groupID) end
                local sp = chooseSpawn(cam)
                if cam and sp then
                    ply:SetNWString("GRM_ArrestCameraID", tostring(cam.id or ""))
                    ply:SetPos(vec(sp.pos))
                    ply:SetEyeAngles(ang(sp.ang or { p = 0, y = 0, r = 0 }))
                end
                if applyArrestAppearance then applyArrestAppearance(ply, g) end
            end
        end)
    end)
end

if CLIENT then
    net.Receive("GRM_Arrest_Event", function()
        local event = net.ReadString()
        local targetName = net.ReadString()
        local groupName = net.ReadString()
        if event == "arrest" then
            notification.AddLegacy("Арестован: " .. targetName .. "  •  помещён в камеру: " .. groupName, NOTIFY_ERROR, 7)
            surface.PlaySound("buttons/button10.wav")
        elseif event == "unarrest" then
            notification.AddLegacy("Освобождён: " .. targetName, NOTIFY_GENERIC, 6)
            surface.PlaySound("buttons/button14.wav")
        end
    end)

    surface.CreateFont("GRMArrestTitle", { font = "Roboto", size = 22, weight = 900, extended = true })
    surface.CreateFont("GRMArrestHeading", { font = "Roboto", size = 16, weight = 800, extended = true })
    surface.CreateFont("GRMArrestBody", { font = "Roboto", size = 14, weight = 500, extended = true })
    surface.CreateFont("GRMArrestSmall", { font = "Roboto", size = 12, weight = 500, extended = true })

    local UI = {
        bg = Color(12, 17, 25, 252), header = Color(22, 29, 41, 255), sidebar = Color(17, 24, 35, 255),
        card = Color(25, 34, 48, 255), card2 = Color(30, 41, 57, 255), line = Color(54, 68, 89, 220),
        text = Color(239, 244, 250), dim = Color(157, 171, 190), accent = Color(72, 153, 255),
        green = Color(70, 201, 128), orange = Color(241, 157, 78), red = Color(222, 87, 91),
    }

    local function label(parent, text, font, color)
        local l = vgui.Create("DLabel", parent)
        l:SetText(text or "") l:SetFont(font or "GRMArrestBody") l:SetTextColor(color or UI.text)
        l:SetWrap(true)
        return l
    end

    local function button(parent, text, color, tall)
        local b = vgui.Create("DButton", parent)
        b:SetText(text or "") b:SetFont("GRMArrestBody") b:SetTextColor(UI.text)
        b:SetTall(tall or 34)
        b:SetContentAlignment(5)
        b.Paint = function(self, w, h)
            local c = color or UI.card2
            if self:IsHovered() then c = Color(math.min(c.r + 18, 255), math.min(c.g + 18, 255), math.min(c.b + 18, 255), c.a) end
            draw.RoundedBox(6, 0, 0, w, h, c)
        end
        return b
    end

    local function sendAction(action, id, extra)
        net.Start("GRM_Arrest_AdminAction")
            net.WriteString(action or "")
            net.WriteString(id or "")
            if extra then extra() end
        net.SendToServer()
    end

    local function sectionTitle(parent, title, subtitle)
        local p = vgui.Create("DPanel", parent)
        p:Dock(TOP) p:SetTall(48) p:DockMargin(0, 0, 0, 8) p:SetPaintBackground(false)
        local t = label(p, title, "GRMArrestHeading", UI.text) t:SetPos(0, 0) t:SetSize(600, 24)
        local s = label(p, subtitle or "", "GRMArrestSmall", UI.dim) s:SetPos(0, 25) s:SetSize(700, 20)
        return p
    end

    local function card(parent, height)
        local p = vgui.Create("DPanel", parent)
        p:Dock(TOP) p:SetTall(height) p:DockMargin(0, 0, 0, 10)
        p:SetPaintBackground(false)
        p.Paint = function(self, w, h)
            draw.RoundedBox(8, 0, 0, w, h, UI.card)
            draw.RoundedBox(8, 0, 0, 4, h, UI.accent)
        end
        return p
    end

    local function openGroupEditor(gid, source)
        local ed = table.Copy(source or {})
        ed.bodygroups = istable(ed.bodygroups) and ed.bodygroups or {}
        ed.allowedFactions = istable(ed.allowedFactions) and ed.allowedFactions or {}
        local w = vgui.Create("DFrame")
        GRM.UI.Track("arrest_group_editor", w)
        w:SetSize(920, 650) w:Center() w:MakePopup() w:SetTitle("") w:ShowCloseButton(false)
        w:SetDeleteOnClose(true)
        w.Paint = function(_, pw, ph)
            draw.RoundedBox(10, 0, 0, pw, ph, UI.bg)
            draw.RoundedBoxEx(10, 0, 0, pw, 62, UI.header, true, true, false, false)
            draw.SimpleText("ВНЕШНОСТЬ ГРУППЫ", "GRMArrestSmall", 22, 17, UI.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(tostring(ed.name or gid), "GRMArrestTitle", 22, 42, UI.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        local close = button(w, "×", UI.red, 30) close:SetPos(870, 16) close:SetSize(32, 30)
        close.DoClick = function() w:Close() end

        local model = vgui.Create("DTextEntry", w) model:SetPos(24, 92) model:SetSize(560, 34) model:SetFont("GRMArrestBody") model:SetText(ed.model or "")
        model:SetPlaceholderText("Путь к модели, например models/grworkers/grworker.mdl")
        model.Paint = function(self, pw, ph) draw.RoundedBox(5, 0, 0, pw, ph, UI.card2); self:DrawTextEntryText(UI.text, UI.accent, UI.text) end
        local load = button(w, "Обновить превью", UI.accent, 34) load:SetPos(594, 92) load:SetSize(160, 34)
        local preview = vgui.Create("DModelPanel", w) preview:SetPos(640, 150) preview:SetSize(230, 330) preview:SetFOV(42) preview.LayoutEntity = function() end
        preview.PaintOver = function(_, pw, ph) draw.RoundedBox(6, 0, 0, pw, ph, Color(0, 0, 0, 18)) end
        local previewHint = label(w, "ПРЕДПРОСМОТР", "GRMArrestSmall", UI.dim) previewHint:SetPos(640, 490) previewHint:SetSize(230, 20) previewHint:SetContentAlignment(5)

        local body = vgui.Create("DScrollPanel", w) body:SetPos(24, 145) body:SetSize(570, 330)
        local bodyTitle = label(w, "Параметры внешности", "GRMArrestHeading", UI.text) bodyTitle:SetPos(24, 126) bodyTitle:SetSize(400, 24)
        local skin = vgui.Create("DNumSlider", w) skin:SetPos(24, 500) skin:SetSize(570, 32) skin:SetText("Skin") skin:SetMin(0) skin:SetMax(16) skin:SetDecimals(0) skin:SetValue(ed.skin or 0)
        if IsValid(skin.Label) then skin.Label:SetFont("GRMArrestBody") skin.Label:SetTextColor(UI.text) end
        local function applyAppearance(ent)
            if not IsValid(ent) then return end
            local maxSkin = math.max(0, (ent:SkinCount() or 1) - 1)
            local selectedSkin = math.Clamp(math.floor(tonumber(ed.skin) or 0), 0, maxSkin)
            ent:SetSkin(selectedSkin)
            for group, value in pairs(ed.bodygroups or {}) do
                local gi, vi = tonumber(group), tonumber(value)
                if gi and vi then ent:SetBodygroup(gi, vi) end
            end
        end
        skin.OnValueChanged = function(_, value)
            ed.skin = math.floor(tonumber(value) or 0)
            applyAppearance(preview:GetEntity())
        end
        local function rebuild()
            body:Clear()
            local ent = IsValid(preview:GetEntity()) and preview:GetEntity() or nil
            if not IsValid(ent) then
                local hint = label(body, "Укажите корректную модель и нажмите «Обновить превью».", "GRMArrestBody", UI.dim)
                hint:Dock(TOP) hint:SetTall(50)
                return
            end
            local count = 0
            for i = 0, (ent:GetNumBodyGroups() or 0) - 1 do
                local variants = ent:GetBodygroupCount(i) or 1
                if variants > 1 then
                    count = count + 1
                    local row = vgui.Create("DPanel", body) row:Dock(TOP) row:SetTall(48) row:DockMargin(0, 0, 8, 6) row:SetPaintBackground(false)
                    local name = ent:GetBodygroupName(i) or ("Группа " .. i)
                    local title = label(row, name, "GRMArrestBody", UI.text) title:Dock(LEFT) title:SetWide(210) title:SetContentAlignment(4)
                    local combo = vgui.Create("DComboBox", row) combo:Dock(FILL) combo:SetTall(34) combo:SetValue("Вариант " .. tostring(ed.bodygroups[i] or 0))
                    for value = 0, variants - 1 do combo:AddChoice("Вариант " .. value, value) end
                    combo.OnSelect = function(_, _, _, value)
                        -- DComboBox передаёт выбранные данные четвёртым
                        -- аргументом. Третий аргумент — отображаемый текст.
                        ed.bodygroups[i] = tonumber(value) or 0
                        applyAppearance(preview:GetEntity())
                    end
                end
            end
            if count == 0 then
                local hint = label(body, "У этой модели нет настраиваемых bodygroups.", "GRMArrestBody", UI.dim)
                hint:Dock(TOP) hint:SetTall(40)
            end
            local factionTitle = label(body, "Допуск категории по фракции задержанного", "GRMArrestHeading", UI.text)
            factionTitle:Dock(TOP) factionTitle:SetTall(28) factionTitle:DockMargin(0, 12, 0, 4)
            local factionHint = label(body, "Пустой список — категория доступна всем. Отметьте фракции, которым разрешена эта категория.", "GRMArrestSmall", UI.dim)
            factionHint:Dock(TOP) factionHint:SetTall(34)
            local names = {}
            for factionName in pairs(FactionsData or {}) do names[#names + 1] = factionName end
            table.sort(names, function(a, b) return tostring(a) < tostring(b) end)
            for _, factionName in ipairs(names) do
                local check = vgui.Create("DCheckBoxLabel", body)
                check:Dock(TOP) check:SetTall(28) check:SetText(tostring(factionName))
                check:SetFont("GRMArrestBody") check:SetTextColor(UI.text)
                check:SetValue(ed.allowedFactions[factionName] == true)
                check.OnChange = function(_, value) ed.allowedFactions[factionName] = value == true end
            end
        end
        local function refreshPreview()
            local path = string.Trim(model:GetValue() or "")
            if util.IsValidModel(path) then
                preview:SetModel(path)
                applyAppearance(preview:GetEntity())
                rebuild()
            end
        end
        load.DoClick = refreshPreview
        if util.IsValidModel(model:GetValue()) then
            preview:SetModel(model:GetValue())
            applyAppearance(preview:GetEntity())
            rebuild()
        else
            rebuild()
        end

        local save = button(w, "СОХРАНИТЬ ВНЕШНОСТЬ", UI.green, 40) save:SetPos(640, 550) save:SetSize(230, 40)
        save.DoClick = function()
            sendAction("set_group_data", gid, function()
                net.WriteTable({ model = model:GetValue(), skin = skin:GetValue(), bodygroups = ed.bodygroups, allowedFactions = ed.allowedFactions })
            end)
            w:Close()
        end
    end

    local function openGroupAccessEditor(gid, source)
        local selected = table.Copy(source.allowedFactions or {})
        local w = vgui.Create("DFrame")
        GRM.UI.Track("arrest_category_access", w)
        w:SetSize(560, 520) w:Center() w:MakePopup() w:SetTitle("Доступ категории: " .. tostring(source.name or gid))
        local hint = label(w, "Отметьте фракции задержанных, которым разрешена эта категория. Пустой список = доступна всем.", "GRMArrestSmall", UI.dim)
        hint:SetPos(16, 36) hint:SetSize(520, 44)
        local list = vgui.Create("DScrollPanel", w) list:SetPos(16, 88) list:SetSize(528, 350)
        local names = {}
        for name in pairs(FactionsData or {}) do names[#names + 1] = name end
        table.sort(names)
        for _, factionName in ipairs(names) do
            local check = vgui.Create("DCheckBoxLabel", list)
            check:Dock(TOP) check:SetTall(34) check:SetText(tostring(factionName)) check:SetFont("GRMArrestBody") check:SetTextColor(UI.text)
            check:SetValue(selected[factionName] == true)
            check.OnChange = function(_, value) selected[factionName] = value == true end
        end
        local saveAccess = button(w, "СОХРАНИТЬ ДОПУСК", UI.green, 38) saveAccess:SetPos(16, 452) saveAccess:SetSize(528, 38)
        saveAccess.DoClick = function()
            sendAction("set_group_data", gid, function()
                net.WriteTable({ model = source.model or "models/player/Group03/male_07.mdl", skin = source.skin or 0, bodygroups = source.bodygroups or {}, allowedFactions = selected })
            end)
            w:Close()
        end
    end

    local function openGroupCameraEditor(gid, source, cameras)
        local selected = {}
        for _, cameraID in ipairs(source.cameraIDs or {}) do selected[tostring(cameraID)] = true end
        local w = vgui.Create("DFrame")
        GRM.UI.Track("arrest_category_cameras", w)
        w:SetSize(600, 560) w:Center() w:MakePopup()
        w:SetTitle("Камеры категории: " .. tostring(source.name or gid))
        local hint = label(w,
            "Отметьте камеры, в которые разрешено помещать эту категорию. У камеры обязательно должна быть назначена точка арестованного.",
            "GRMArrestSmall", UI.dim)
        hint:SetPos(16, 36) hint:SetSize(560, 48)
        local list = vgui.Create("DScrollPanel", w) list:SetPos(16, 90) list:SetSize(568, 390)
        for _, cam in ipairs(cameras or {}) do
            local cameraID = tostring(cam.id or "")
            local check = vgui.Create("DCheckBoxLabel", list)
            check:Dock(TOP) check:SetTall(38)
            local hasSpawn = tostring(cam.spawnID or "") ~= ""
            check:SetText(tostring(cam.name or cameraID) .. "  [" .. cameraID .. "]  •  точка: " .. tostring(hasSpawn and cam.spawnID or "НЕ НАЗНАЧЕНА"))
            check:SetFont("GRMArrestBody") check:SetTextColor(hasSpawn and UI.text or UI.red)
            check:SetValue(selected[cameraID] == true)
            check.OnChange = function(_, value) selected[cameraID] = value == true end
        end
        if #(cameras or {}) == 0 then
            local empty = label(list, "Сначала создайте хотя бы одну камеру.", "GRMArrestBody", UI.dim)
            empty:Dock(TOP) empty:SetTall(40)
        end
        local saveCameras = button(w, "СОХРАНИТЬ КАМЕРЫ КАТЕГОРИИ", UI.green, 40)
        saveCameras:SetPos(16, 500) saveCameras:SetSize(568, 40)
        saveCameras.DoClick = function()
            local out = {}
            for cameraID, enabled in pairs(selected) do if enabled then out[#out + 1] = cameraID end end
            table.sort(out)
            sendAction("set_group_cameras", gid, function() net.WriteTable(out) end)
            w:Close()
        end
    end

    local function openAdminWindow(data)
        data = istable(data) and data or {}
        local f = vgui.Create("DFrame")
        GRM.UI.Track("arrest_admin", f)
        f:SetSize(1120, 760) f:Center() f:MakePopup() f:SetTitle("") f:ShowCloseButton(false) f:SetDeleteOnClose(true)
        f.Paint = function(_, pw, ph)
            draw.RoundedBox(10, 0, 0, pw, ph, UI.bg)
            draw.RoundedBoxEx(10, 0, 0, pw, 66, UI.header, true, true, false, false)
            draw.SimpleText("GRM  /  СИСТЕМА АРЕСТА", "GRMArrestSmall", 24, 19, UI.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText("Камеры, группы и точки содержания", "GRMArrestTitle", 24, 45, UI.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            -- карта видна сразу: разметка теперь принадлежит конкретной карте
            draw.SimpleText("КАРТА: " .. string.upper(tostring(data.map or "?")), "GRMArrestSmall",
                pw - 64, 19, UI.green, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            draw.SimpleText(("камер %d  •  точек %d  •  зон %d"):format(
                #(data.cameras or {}), #(data.spawns or {}), #(data.prisonZones or {})),
                "GRMArrestSmall", pw - 64, 45, UI.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
        local close = button(f, "×", UI.red, 32) close:SetPos(1072, 17) close:SetSize(32, 32) close.DoClick = function() f:Close() end

        local side = vgui.Create("DPanel", f) side:SetPos(0, 66) side:SetSize(245, 694) side:SetPaintBackground(false)
        side.Paint = function(_, pw, ph)
            draw.RoundedBoxEx(10, 0, 0, pw, ph, UI.sidebar, false, false, true, false)
            draw.RoundedBox(0, pw - 1, 0, 1, ph, UI.line)
        end
        local sideTitle = label(side, "УПРАВЛЕНИЕ", "GRMArrestSmall", UI.dim) sideTitle:SetPos(24, 28) sideTitle:SetSize(190, 20)
        local help = label(side, "Настройте место камеры, точку телепорта и внешний вид каждой категории арестованных.", "GRMArrestBody", UI.text) help:SetPos(24, 58) help:SetSize(195, 100)
        local stat = label(side, string.format("ГРУППЫ  %d\nКАМЕРЫ  %d\nТОЧКИ    %d", table.Count(data.groups or {}), #(data.cameras or {}), #(data.spawns or {})), "GRMArrestBody", UI.dim) stat:SetPos(24, 190) stat:SetSize(190, 90)
        local hint = label(side, "Добавление происходит в точке прицела или под ногами администратора. После сохранения меню обновится автоматически.", "GRMArrestSmall", UI.dim) hint:SetPos(24, 540) hint:SetSize(195, 90)

        local content = vgui.Create("DScrollPanel", f) content:SetPos(269, 86) content:SetSize(825, 650)
        local canvas = content:GetCanvas()
        sectionTitle(canvas, "Быстрые действия", "Создайте объекты на карте, затем свяжите камеру с точкой содержания.")
        local actionBar = vgui.Create("DPanel", canvas) actionBar:Dock(TOP) actionBar:SetTall(46) actionBar:DockMargin(0, 0, 0, 18) actionBar:SetPaintBackground(false)
        local addCam = button(actionBar, "+  Камера в прицеле", UI.accent, 40) addCam:Dock(LEFT) addCam:SetWide(245) addCam.DoClick = function() sendAction("add_camera", "") end
        local addSpawn = button(actionBar, "+  Точка арестованного", UI.green, 40) addSpawn:Dock(LEFT) addSpawn:DockMargin(10, 0, 0, 0) addSpawn:SetWide(245) addSpawn.DoClick = function() sendAction("add_spawn", "") end

        --[[ РАЗДЕЛ КАРТЫ. Камеры, точки и зоны принадлежат карте: на другой
             карте они не показываются и не срабатывают. Здесь же — перенос
             разметки с другой карты и очистка текущей. ]]
        sectionTitle(canvas, "Карта и разметка",
            "Разметка привязана к карте " .. string.upper(tostring(data.map or "?")) ..
            ". Точки других карт сюда не попадают и не срабатывают.")
        local mapBar = vgui.Create("DPanel", canvas) mapBar:Dock(TOP) mapBar:SetTall(46)
        mapBar:DockMargin(0, 0, 0, 18) mapBar:SetPaintBackground(false)
        local mapCombo = vgui.Create("DComboBox", mapBar) mapCombo:Dock(LEFT) mapCombo:SetWide(320)
        mapCombo:SetValue("Перенести разметку с карты...")
        local pickedMap = ""
        for _, m in ipairs(data.maps or {}) do
            if tostring(m) ~= tostring(data.map) then mapCombo:AddChoice(tostring(m), tostring(m)) end
        end
        mapCombo.OnSelect = function(_, _, _, val) pickedMap = tostring(val or "") end
        local importBtn = button(mapBar, "ПЕРЕНЕСТИ СЮДА", UI.accent, 40)
        importBtn:Dock(LEFT) importBtn:DockMargin(10, 0, 0, 0) importBtn:SetWide(220)
        importBtn.DoClick = function()
            if pickedMap == "" then return end
            Derma_Query("Перенести разметку ареста с карты «" .. pickedMap .. "» на текущую?\nТекущая разметка будет заменена.",
                "Система ареста", "Перенести", function() sendAction("map_import", pickedMap) end, "Отмена")
        end
        local clearBtn = button(mapBar, "ОЧИСТИТЬ ЭТУ КАРТУ", UI.red, 40)
        clearBtn:Dock(LEFT) clearBtn:DockMargin(10, 0, 0, 0) clearBtn:SetWide(240)
        clearBtn.DoClick = function()
            Derma_Query("Удалить ВСЕ камеры, точки и зоны ареста на карте " .. string.upper(tostring(data.map or "?")) .. "?",
                "Система ареста", "Удалить", function() sendAction("map_clear", "") end, "Отмена")
        end

        sectionTitle(canvas, "Группы и доступ категорий", "Нажмите «Внешность и доступ фракций»: там задаются модель, bodygroups и фракции, которым разрешена эта категория.")
        for gid, g in pairs(data.groups or {}) do
            local p = card(canvas, 132)
            local name = label(p, tostring(g.name or gid), "GRMArrestHeading", UI.text) name:SetPos(20, 13) name:SetSize(350, 24)
            local allowedNames = {}
            for factionName, enabled in pairs(g.allowedFactions or {}) do if enabled then allowedNames[#allowedNames + 1] = tostring(factionName) end end
            table.sort(allowedNames)
            local accessText = #allowedNames > 0 and ("Допуск: " .. table.concat(allowedNames, ", ")) or "Допуск: все; авто → только при явной фракции"
            local id = label(p, tostring(gid) .. "   •   " .. tostring(g.model or "модель не задана"), "GRMArrestSmall", UI.dim) id:SetPos(20, 42) id:SetSize(470, 22)
            local accessInfo = label(p, accessText, "GRMArrestSmall", UI.dim) accessInfo:SetPos(20, 67) accessInfo:SetSize(470, 22)
            local camerasInfo = label(p, "Камер категории: " .. tostring(#(g.cameraIDs or {})), "GRMArrestSmall", #(g.cameraIDs or {}) > 0 and UI.green or UI.red) camerasInfo:SetPos(20, 92) camerasInfo:SetSize(470, 22)
            local edit = button(p, "Внешность / bodygroups", UI.accent, 30) edit:SetPos(535, 10) edit:SetSize(250, 30) edit.DoClick = function() openGroupEditor(gid, g) end
            local access = button(p, "ДОСТУП ФРАКЦИЙ", UI.orange, 30) access:SetPos(535, 48) access:SetSize(250, 30) access.DoClick = function() openGroupAccessEditor(gid, g) end
            local cameras = button(p, "КАМЕРЫ КАТЕГОРИИ", UI.green, 30) cameras:SetPos(535, 86) cameras:SetSize(250, 30) cameras.DoClick = function() openGroupCameraEditor(gid, g, data.cameras or {}) end
        end

        sectionTitle(canvas, "Камеры и точки содержания", "Категория может использовать несколько камер; одна камера также может входить в несколько категорий.")
        for _, cam in ipairs(data.cameras or {}) do
            local p = card(canvas, 150)
            local title = label(p, "КАМЕРА  " .. tostring(cam.id), "GRMArrestHeading", UI.text) title:SetPos(20, 12) title:SetSize(300, 24)
            local assigned = {}
            for gid, g in pairs(data.groups or {}) do
                for _, cameraID in ipairs(g.cameraIDs or {}) do
                    if tostring(cameraID) == tostring(cam.id) then assigned[#assigned + 1] = tostring(g.name or gid) end
                end
            end
            table.sort(assigned)
            local categoryText = #assigned > 0 and table.concat(assigned, ", ") or "НЕ НАЗНАЧЕНА"
            local meta = label(p, "Категории: " .. categoryText .. "   •   Точка: " .. tostring(tostring(cam.spawnID or "") ~= "" and cam.spawnID or "не назначена"), "GRMArrestSmall", #assigned > 0 and UI.dim or UI.red) meta:SetPos(20, 40) meta:SetSize(470, 44)
            local combo = vgui.Create("DComboBox", p) combo:SetPos(505, 12) combo:SetSize(280, 32) combo:SetValue("Быстро назначить одну категорию")
            for gid, g in pairs(data.groups or {}) do combo:AddChoice(tostring(g.name or gid) .. "  [" .. gid .. "]", gid) end
            local setGroup = button(p, "Только эта категория", UI.accent, 30) setGroup:SetPos(505, 52) setGroup:SetSize(135, 30)
            setGroup.DoClick = function() local gid = combo:GetOptionData(combo:GetSelectedID()) or cam.group or "criminals"; sendAction("set_camera_group", cam.id, function() net.WriteString(gid) end) end
            local setSpawn = button(p, "Привязать точку", UI.green, 30) setSpawn:SetPos(650, 52) setSpawn:SetSize(135, 30)
            setSpawn.DoClick = function()
                local menu = DermaMenu()
                for index, sp in ipairs(data.spawns or {}) do
                    local caption = string.format("Точка %d  •  %s  [%s]", index, tostring(sp.name or "Точка ареста"), tostring(sp.id or "—"))
                    menu:AddOption(caption, function() sendAction("assign_camera_spawn", cam.id, function() net.WriteString(sp.id) end) end)
                end
                menu:AddOption("Снять привязку", function() sendAction("assign_camera_spawn", cam.id, function() net.WriteString("") end) end)
                menu:Open()
            end
            local remove = button(p, "Удалить камеру", UI.red, 30) remove:SetPos(505, 94) remove:SetSize(280, 30)
            remove.DoClick = function()
                Derma_Query("Удалить камеру «" .. tostring(cam.id) .. "»?", "Подтверждение удаления", "Удалить", function() sendAction("delete_camera", cam.id) end, "Отмена")
            end
        end
        if #(data.cameras or {}) == 0 then
            local empty = card(canvas, 70) local txt = label(empty, "Камеры ещё не созданы. Нажмите «Камера в прицеле», стоя у нужной двери.", "GRMArrestBody", UI.dim) txt:SetPos(20, 22) txt:SetSize(760, 28)
        end

        sectionTitle(canvas, "Точки арестованных", "Удаление точки автоматически снимает её привязку со всех камер.")
        if #(data.spawns or {}) == 0 then
            local empty = card(canvas, 70) local txt = label(empty, "Точки ещё не созданы. Нажмите «Точка арестованного».", "GRMArrestBody", UI.dim) txt:SetPos(20, 22) txt:SetSize(760, 28)
        else
            for index, sp in ipairs(data.spawns or {}) do
                local p = card(canvas, 108)
                local title = label(p, "ТОЧКА " .. tostring(index) .. "  •  " .. tostring(sp.id), "GRMArrestHeading", UI.text) title:SetPos(20, 11) title:SetSize(450, 24)
                local meta = label(p, tostring(sp.name or ("Точка ареста " .. tostring(index))), "GRMArrestSmall", UI.dim) meta:SetPos(20, 39) meta:SetSize(450, 20)
                local linked = {}
                for _, cam in ipairs(data.cameras or {}) do
                    if tostring(cam.spawnID or "") == tostring(sp.id) then
                        linked[#linked + 1] = tostring(cam.name or cam.id) .. " [" .. tostring(cam.id) .. "]"
                    end
                end
                local linkText = #linked > 0 and ("Привязано к: " .. table.concat(linked, ", ")) or "Не привязана к камере"
                local link = label(p, linkText, "GRMArrestSmall", #linked > 0 and UI.green or UI.orange) link:SetPos(20, 67) link:SetSize(540, 22)
                local remove = button(p, "Удалить точку", UI.red, 34) remove:SetPos(585, 32) remove:SetSize(200, 34)
                remove.DoClick = function()
                    Derma_Query("Удалить точку «" .. tostring(sp.id) .. "»? Привязка камер будет снята.", "Подтверждение удаления", "Удалить", function() sendAction("delete_spawn", sp.id) end, "Отмена")
                end
            end
        end

        sectionTitle(canvas, "Новая группа", "Создайте собственную категорию, затем настройте её внешний вид.")
        local form = card(canvas, 128)
        local name = vgui.Create("DTextEntry", form) name:SetPos(20, 18) name:SetSize(235, 34) name:SetPlaceholderText("Название, например Политические")
        local model = vgui.Create("DTextEntry", form) model:SetPos(270, 18) model:SetSize(280, 34) model:SetPlaceholderText("models/.../model.mdl")
        local gid = vgui.Create("DTextEntry", form) gid:SetPos(565, 18) gid:SetSize(220, 34) gid:SetPlaceholderText("ID: political")
        local create = button(form, "Создать / сохранить группу", UI.orange, 38) create:SetPos(20, 70) create:SetSize(765, 38)
        create.DoClick = function() sendAction("set_group", gid:GetValue(), function() net.WriteString(name:GetValue()) net.WriteString(model:GetValue()) end) end
    end

    --[[ Снимок админки приходит порциями (GRM.Net.Stream) — окно собирается
         один раз, без пакета «всё сразу». ]]
    if GRM.Net and GRM.Net.Receive then
        GRM.Net.Receive("GRM_Arrest_AdminData", openAdminWindow)
    end
    net.Receive("GRM_Arrest_AdminData", function()
        openAdminWindow(net.ReadTable() or {})
    end)

    local arrestAccessPanel
    local arrestAccessData = { mode = "all", factions = {} }

    local function rebuildArrestAccessPanel()
        if not IsValid(arrestAccessPanel) then return end
        arrestAccessPanel:Clear()
        local info = label(arrestAccessPanel, "Доступ к /arrest и /unarrest", "GRMArrestHeading", UI.text)
        info:Dock(TOP) info:SetTall(28) info:DockMargin(12, 12, 12, 0)
        local hint = label(arrestAccessPanel, "Суперадмин всегда имеет доступ. В режиме списка использовать арест смогут только отмеченные фракции.", "GRMArrestSmall", UI.dim)
        hint:Dock(TOP) hint:SetTall(38) hint:DockMargin(12, 0, 12, 6)
        local only = vgui.Create("DCheckBoxLabel", arrestAccessPanel)
        only:Dock(TOP) only:SetTall(30) only:DockMargin(12, 0, 12, 8)
        only:SetText("Ограничить систему ареста списком фракций") only:SetFont("GRMArrestBody") only:SetTextColor(UI.text)
        only:SetValue(arrestAccessData.mode == "allowlist")
        local list = vgui.Create("DScrollPanel", arrestAccessPanel)
        list:Dock(FILL) list:DockMargin(12, 0, 12, 8)
        local factions = FactionsData or {}
        local names = {}
        for name in pairs(factions) do names[#names + 1] = name end
        table.sort(names, function(a, b) return tostring(a) < tostring(b) end)
        if #names == 0 then
            local empty = label(list, "Список фракций ещё не загружен.", "GRMArrestBody", UI.dim)
            empty:Dock(TOP) empty:SetTall(40)
        else
            for _, name in ipairs(names) do
                local row = vgui.Create("DPanel", list) row:Dock(TOP) row:SetTall(34) row:DockMargin(0, 0, 0, 4)
                row:SetPaintBackground(false)
                local check = vgui.Create("DCheckBoxLabel", row) check:Dock(FILL) check:DockMargin(8, 0, 0, 0)
                check:SetText(tostring(name)) check:SetFont("GRMArrestBody") check:SetTextColor(UI.text)
                check:SetValue(arrestAccessData.factions and arrestAccessData.factions[name] == true)
                check.OnChange = function(_, value)
                    arrestAccessData.factions[name] = value == true
                end
            end
        end
        local saveAccess = button(arrestAccessPanel, "СОХРАНИТЬ ДОСТУП", UI.green, 40)
        saveAccess:Dock(BOTTOM) saveAccess:DockMargin(12, 0, 12, 12)
        saveAccess.DoClick = function()
            net.Start("GRM_Arrest_AccessSave")
                net.WriteBool(only:GetChecked())
                net.WriteTable(arrestAccessData.factions or {})
            net.SendToServer()
        end
    end

    local arrestCategoryPanel
    local arrestCategoryData = {}
    local function rebuildArrestCategoryPanel()
        if not IsValid(arrestCategoryPanel) then return end
        arrestCategoryPanel:Clear()
        local title = label(arrestCategoryPanel, "Категории ареста по фракциям задержанных", "GRMArrestHeading", UI.text)
        title:Dock(TOP) title:SetTall(30) title:DockMargin(12, 12, 12, 0)
        local hint = label(arrestCategoryPanel, "Отметьте фракции, которым разрешена конкретная категория. Пустой список означает обычную категорию для гражданских.", "GRMArrestSmall", UI.dim)
        hint:Dock(TOP) hint:SetTall(38) hint:DockMargin(12, 0, 12, 8)
        local factions = {}
        for name in pairs(FactionsData or {}) do factions[#factions + 1] = name end
        table.sort(factions)
        for gid, g in pairs(arrestCategoryData or {}) do
            local box = vgui.Create("DPanel", arrestCategoryPanel) box:Dock(TOP) box:SetTall(72) box:DockMargin(12, 0, 12, 8)
            box.Paint = function(_, w, h) draw.RoundedBox(7, 0, 0, w, h, UI.card) end
            local gl = label(box, tostring(g.name or gid) .. "  [" .. tostring(gid) .. "]", "GRMArrestBody", UI.text) gl:SetPos(12, 8) gl:SetSize(260, 24)
            local selected = table.Copy(g.allowedFactions or {})
            local checks = {}
            for index, factionName in ipairs(factions) do
                local c = vgui.Create("DCheckBoxLabel", box) c:SetPos(280 + ((index - 1) % 3) * 180, 8 + math.floor((index - 1) / 3) * 26) c:SetSize(175, 24)
                c:SetText(tostring(factionName)) c:SetFont("GRMArrestSmall") c:SetTextColor(UI.text) c:SetValue(selected[factionName] == true)
                c.OnChange = function(_, value) selected[factionName] = value == true end
                checks[#checks + 1] = c
            end
            local saveGroup = button(box, "Сохранить", UI.green, 28) saveGroup:SetPos(12, 39) saveGroup:SetSize(150, 26)
            saveGroup.DoClick = function()
                net.Start("GRM_Arrest_CategoryAccessSave") net.WriteString(gid) net.WriteTable(selected) net.SendToServer()
            end
        end
    end

    net.Receive("GRM_Arrest_CategoryAccessData", function()
        arrestCategoryData = net.ReadTable() or {}
        timer.Simple(0, rebuildArrestCategoryPanel)
    end)

    net.Receive("GRM_Arrest_AccessData", function()
        arrestAccessData = net.ReadTable() or { mode = "all", factions = {} }
        arrestAccessData.factions = istable(arrestAccessData.factions) and arrestAccessData.factions or {}
        timer.Simple(0, rebuildArrestAccessPanel)
    end)

    hook.Add("GRM_FactionsAdmin_BuildTabs", "GRM_Arrest_FactionAccessTab", function(tabs)
        if not IsValid(tabs) or not IsValid(LocalPlayer()) or not LocalPlayer():IsSuperAdmin() then return end
        arrestAccessPanel = vgui.Create("DPanel")
        arrestAccessPanel:SetPaintBackground(false)
        tabs:AddSheet("Доступ к аресту", arrestAccessPanel, "icon16/shield.png")
        arrestCategoryPanel = vgui.Create("DPanel")
        arrestCategoryPanel:SetPaintBackground(false)
        tabs:AddSheet("Категории ареста", arrestCategoryPanel, "icon16/lock.png")
        rebuildArrestAccessPanel()
        rebuildArrestCategoryPanel()
        net.Start("GRM_Arrest_AccessRequest") net.SendToServer()
        net.Start("GRM_Arrest_CategoryAccessRequest") net.SendToServer()
        timer.Simple(0.6, function() rebuildArrestAccessPanel() rebuildArrestCategoryPanel() end)
    end)

    -- Камеры больше не рисуют огромные сферы/лучи для всех игроков.
    -- Только суперадмин видит компактную полупрозрачную метку вблизи.
    -- Плашка камеры: позиция и цвет с дышащей от дистанции альфой —
    -- скретч-объекты на загрузке файла, поля пишутся перед немедленной
    -- отрисовкой (камер много, а объект один; §6.1.8)
    local AZ_POS = Vector(0, 0, 34)
    local AZ_ANG = Angle(0, 0, 90)
    local AZ_C = Color(0, 0, 0, 255)
    local ARREST_LAB_UP = Vector(0, 0, 82)
    local ARREST_LAB_BG = Color(13, 18, 27, 220)
    local arrestZoneDrawFrame = -1
    hook.Add("PostDrawTranslucentRenderables", "GRM_Arrest_Zones", function()
        local frame = FrameNumber()
        if arrestZoneDrawFrame == frame then return end
        arrestZoneDrawFrame = frame
        local lp = LocalPlayer()
        if not IsValid(lp) or not lp:IsSuperAdmin() then return end
        local cameras=GRM.Perf and GRM.Perf.Entities and GRM.Perf.Entities("grm_arrest_camera")or ents.FindByClass("grm_arrest_camera")
        for _, camEnt in ipairs(cameras) do
            if IsValid(camEnt) then
                local distSqr = lp:GetPos():DistToSqr(camEnt:GetPos())
                if distSqr <= 500 * 500 then
                    local alpha = math.Clamp(170 - math.sqrt(distSqr) * 0.22, 45, 150)
                    local cp = camEnt:GetPos()
                    AZ_POS.x = cp.x
                    AZ_POS.y = cp.y
                    AZ_POS.z = cp.z + 34
                    local pos = AZ_POS
                    AZ_ANG.y = EyeAngles().y - 90
                    local ang = AZ_ANG
                    cam.Start3D2D(pos, ang, 0.055)
                        AZ_C.r, AZ_C.g, AZ_C.b, AZ_C.a = 12, 17, 25, alpha
                        draw.RoundedBox(4, -90, -14, 180, 28, AZ_C)
                        AZ_C.r, AZ_C.g, AZ_C.b, AZ_C.a = 235, 170, 95, alpha + 60
                        draw.SimpleText("КАМЕРА • " .. tostring(camEnt:GetCameraName() or camEnt:GetCameraID() or "без имени"),
                            "GRMArrestSmall", 0, 0, AZ_C, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                    cam.End3D2D()
                end
            end
        end
    end)

    hook.Add("HUDPaint", "GRM_Arrest_Label", function()
        local lp = LocalPlayer()
        if not IsValid(lp) then return end
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(p) and p:GetNWBool("GRM_Arrested", false) and (p == lp or lp:GetPos():DistToSqr(p:GetPos()) < 600 * 600) then
                local sp = (p:GetPos() + ARREST_LAB_UP):ToScreen()
                if sp.visible then
                    draw.RoundedBox(5, sp.x - 120, sp.y - 26, 240, 30, ARREST_LAB_BG)
                    draw.SimpleText("АРЕСТОВАННЫЙ  •  " .. p:GetNWString("GRM_ArrestGroupName", ""), "GRMArrestSmall", sp.x, sp.y - 11, UI.orange, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
            end
        end
    end)
end

print("[GRM Arrest] v" .. A.Version .. " loaded")


--[[ Модуль представляется общему реестру GRM.Modules: соседи знают, что он
     есть, а шина обновлений сама позовёт его при смене прав, состава,
     должности или персонажа. ]]
if GRM.Modules and GRM.Modules.Register then
    GRM.Modules.Register("arrest", {
        label = "Арест и содержание",
        version = (GRM.Arrest and GRM.Arrest.Version) or "1.0.0",
        Depends = { "access", "doors" },
        Status = function() local A2 = GRM.Arrest local n = #((A2.Cfg and A2.Cfg.cameras) or {}) return ("камер содержания: %d"):format(n) end,
    })
end

-- Вечер-18: команда разбирается внутри парсера модуля (не литералом в
-- хуке) — регистрируем её множество в едином внешнем словаре библиотеки,
-- иначе на режиме она стала бы «неизвестной» до цепочки.
if GRM and GRM.Chat and GRM.Chat.RegisterExternalCommands then
    GRM.Chat.RegisterExternalCommands({ "/arrest", "/grm_arrest_admin", "/unarrest" })
end
