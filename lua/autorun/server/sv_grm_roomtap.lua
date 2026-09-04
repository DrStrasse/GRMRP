-- Boot-шим: старт подсистемы идёт через планировщик GRM.Boot (приоритеты и
-- бюджет на тик). Если планировщик почему-то не загружен, работаем по-старому.
local function grmBootStart(id, tier, fn)
    if GRM and GRM.Boot and GRM.Boot.OnMapStart then return GRM.Boot.OnMapStart(id, tier, fn) end
    return hook.Add("InitPostEntity", id, fn)
end

--[[--------------------------------------------------------------------
    GRM RoomTap — server

    Запись помещений НЕ пытается записать raw-аудио: движок Garry's Mod
    не передаёт его серверу. Система фиксирует текстовые реплики, входы и
    выходы из радиуса чипа, конфигурацию устройств и их идентификаторы.
----------------------------------------------------------------------]]

if not SERVER then return end

AddCSLuaFile("autorun/sh_grm_roomtap_config.lua")
AddCSLuaFile("autorun/client/cl_grm_roomtap.lua")

for _, path in ipairs({
    "entities/grm_roomtap_chip/shared.lua",
    "entities/grm_roomtap_chip/cl_init.lua",
    "entities/grm_roomtap_server/shared.lua",
    "entities/grm_roomtap_server/cl_init.lua",
    "entities/grm_roomtap_terminal/shared.lua",
    "entities/grm_roomtap_terminal/cl_init.lua",
}) do
    AddCSLuaFile(path)
end

include("autorun/sh_grm_roomtap_config.lua")

GRM = GRM or {}
GRM.RoomTap = GRM.RoomTap or {}

local RT = GRM.RoomTap
local CFG = RT.Config

local NET_RESULT          = "GRM_RoomTap_Result"
local NET_OPEN_CHIP       = "GRM_RoomTap_OpenChip"
local NET_OPEN_SERVER     = "GRM_RoomTap_OpenServer"
local NET_OPEN_TERMINAL   = "GRM_RoomTap_OpenTerminal"
local NET_DEVICE_ACTION   = "GRM_RoomTap_DeviceAction"
local NET_TERMINAL_DATA   = "GRM_RoomTap_TerminalData"
local NET_SHOP_OPEN       = "GRM_RoomTap_ShopOpen"
local NET_SHOP_DATA       = "GRM_RoomTap_ShopData"
local NET_SHOP_SPAWN      = "GRM_RoomTap_ShopSpawn"
local NET_SHOP_REMOVE     = "GRM_RoomTap_ShopRemove"
local NET_ACCESS_REQUEST  = "GRM_RoomTap_AccessRequest"
local NET_ACCESS_DATA     = "GRM_RoomTap_AccessData"
local NET_ACCESS_SAVE     = "GRM_RoomTap_AccessSave"
local NET_REQUESTS_OPEN   = "GRM_RoomTap_RequestsOpen"
local NET_REQUESTS_DATA   = "GRM_RoomTap_RequestsData"
local NET_REQUEST_APPROVE = "GRM_RoomTap_RequestApprove"

for _, name in ipairs({
    NET_RESULT, NET_OPEN_CHIP, NET_OPEN_SERVER, NET_OPEN_TERMINAL,
    NET_DEVICE_ACTION, NET_TERMINAL_DATA, NET_SHOP_OPEN, NET_SHOP_DATA,
    NET_SHOP_SPAWN, NET_SHOP_REMOVE, NET_ACCESS_REQUEST, NET_ACCESS_DATA,
    NET_ACCESS_SAVE, NET_REQUESTS_OPEN, NET_REQUESTS_DATA, NET_REQUEST_APPROVE,
}) do
    util.AddNetworkString(name)
end

local DATA_DIR = "grm_roomtap"
local ACCESS_FILE = DATA_DIR .. "/access.json"
local SHOP_FILE = DATA_DIR .. "/temporary_equipment.json"
local MAP_DIR = DATA_DIR .. "/maps"
local RECORDS_DIR = DATA_DIR .. "/records"

RT.AccessData = RT.AccessData or {}
RT.ShopOwned = RT.ShopOwned or {}       -- устройства текущей карты
RT.ShopStored = RT.ShopStored or {}     -- записи всех карт для сохранения между сменами карт
RT.RecentRecords = RT.RecentRecords or {}
RT.Presence = RT.Presence or {}

-- ============================================================
-- BASIC HELPERS
-- ============================================================

local function trim(value)
    return string.Trim(tostring(value or ""))
end

local function safeFilePart(value, fallback)
    local result = string.lower(trim(value))
    result = string.gsub(result, "[^%w_%-]", "_")
    result = string.gsub(result, "_+", "_")
    result = string.Trim(result, "_")
    return result ~= "" and result or (fallback or "main")
end

local function rpName(ply)
    if not IsValid(ply) then return "?" end
    local name = ply:GetNWString("GRM_RPName", "")
    return name ~= "" and name or ply:Nick()
end

local function steamID64(ply)
    if not IsValid(ply) then return "" end
    if GRM.Identity and GRM.Identity.CharacterKey then return GRM.Identity.CharacterKey(ply) end
    local id = ply:SteamID64()
    return id and id ~= "0" and id or ply:SteamID()
end

local function vecToTable(v)
    return { x = v.x, y = v.y, z = v.z }
end

local function angToTable(a)
    return { p = a.p, y = a.y, r = a.r }
end

local function tableToVec(t)
    return Vector(tonumber(t and t.x) or 0, tonumber(t and t.y) or 0, tonumber(t and t.z) or 0)
end

local function tableToAng(t)
    return Angle(tonumber(t and t.p) or 0, tonumber(t and t.y) or 0, tonumber(t and t.r) or 0)
end

local function ensureDir(path)
    if not file.Exists(path, "DATA") then file.CreateDir(path) end
end

local function readJSON(path, fallback)
    if not file.Exists(path, "DATA") then return table.Copy(fallback or {}) end

    local raw = file.Read(path, "DATA") or ""
    if raw == "" then return table.Copy(fallback or {}) end

    local ok, data = pcall(util.JSONToTable, raw)
    if ok and istable(data) then return data end

    print("[GRM RoomTap] Ошибка чтения JSON: " .. path)
    return table.Copy(fallback or {})
end

local function writeJSON(path, data)
    ensureDir(DATA_DIR)
    local json = util.TableToJSON(data or {}, true)
    if json then file.Write(path, json) end
end

local function notify(ply, success, message)
    if not IsValid(ply) then return end

    net.Start(NET_RESULT)
        net.WriteBool(success == true)
        net.WriteString(tostring(message or ""))
    net.Send(ply)
end

local function moneyText(amount)
    if GRM and isfunction(GRM.Format) then return GRM.Format(amount) end
    return tostring(amount) .. " GRM"
end

local function canPay(ply, amount)
    if not GRM or not isfunction(GRM.HasMoney) then return true end
    return GRM.HasMoney(ply, amount)
end

local function takeMoney(ply, amount)
    if GRM and isfunction(GRM.TakeMoney) then GRM.TakeMoney(ply, amount) end
end

function RT.NormalizeChannel(value)
    return safeFilePart(value, "main")
end

function RT.GetAutoSector(pos)
    local size = math.max(128, tonumber(CFG.GridSectorSize) or 1024)
    local x = math.floor(pos.x / size)
    local y = math.floor(pos.y / size)
    return string.format("X%d / Y%d", x, y)
end

local function newDeviceID(prefix)
    return string.format("%s_%d_%d", prefix or "device", os.time(), math.random(100000, 999999))
end

-- ============================================================
-- FACTION ACCESS: /roomtap_access
-- ============================================================

local function normalizeAccess(data)
    data = istable(data) and data or {}
    data.Factions = istable(data.Factions) and data.Factions or {}
    data.Roles = istable(data.Roles) and data.Roles or {}
    data.Departments = istable(data.Departments) and data.Departments or {}
    return data
end

local function getFactionInfo(ply)
    if not IsValid(ply) or not istable(Factions) then return nil, nil, nil end

    local sid = ply:SteamID()
    local sid64 = ply:SteamID64()
    local charKey = steamID64(ply)

    for factionName, faction in pairs(Factions) do
        if istable(faction) and istable(faction.Members) then
            local member = GRM.Identity.FactionMember(faction, ply)
            if istable(member) then
                return factionName, member.Role, member.Department
            end
        end
    end

    return nil, nil, nil
end

local function nestedAllowed(groups, factionName, value)
    if not istable(groups) or not value then return false end
    if istable(groups[factionName]) and groups[factionName][value] == true then return true end
    if istable(groups["*"]) and groups["*"][value] == true then return true end
    return false
end

function RT.LoadAccess()
    ensureDir(DATA_DIR)
    RT.AccessData = normalizeAccess(readJSON(ACCESS_FILE, {}))
    return RT.AccessData
end

function RT.SaveAccess(data)
    RT.AccessData = normalizeAccess(data or RT.AccessData)
    writeJSON(ACCESS_FILE, RT.AccessData)
end

function RT.HasAccess(ply)
    if not IsValid(ply) then return false end

    local accessConfig = CFG.Access or {}
    if accessConfig.SuperAdminBypass ~= false and ply:IsSuperAdmin() then return true end
    if accessConfig.AdminBypass and ply:IsAdmin() then return true end

    local factionName, role, department = getFactionInfo(ply)
    if not factionName then return false end

    local data = normalizeAccess(RT.AccessData)
    if data.Factions[factionName] == true then return true end
    if nestedAllowed(data.Roles, factionName, role) then return true end
    if nestedAllowed(data.Departments, factionName, department) then return true end

    return false
end

local function buildFactionsPayload()
    local result = {}

    for factionName, faction in pairs(Factions or {}) do
        if istable(faction) then
            result[factionName] = {
                Roles = istable(faction.Roles) and faction.Roles or {},
                Departments = istable(faction.Departments) and faction.Departments or {},
            }
        end
    end

    return result
end

local function sendAccessData(ply)
    if not IsValid(ply) or not ply:IsSuperAdmin() then
        if IsValid(ply) then notify(ply, false, "Настраивать доступ может только superadmin.") end
        return
    end

    net.Start(NET_ACCESS_DATA)
        net.WriteTable(buildFactionsPayload())
        net.WriteTable(normalizeAccess(RT.AccessData))
    net.Send(ply)
end

-- ============================================================
-- DEVICE ACCESS AND DISCOVERY
-- ============================================================

RT.DeviceClasses = {
    grm_roomtap_chip = true,
    grm_roomtap_server = true,
    grm_roomtap_terminal = true,
}

function RT.IsDevice(ent)
    return IsValid(ent) and RT.DeviceClasses[ent:GetClass()] == true
end

function RT.CanUseDevice(ply, ent)
    return IsValid(ply) and RT.IsDevice(ent)
        and ply:GetPos():DistToSqr(ent:GetPos()) <= (tonumber(CFG.UseDistance) or 180) ^ 2
end

function RT.CanConfigure(ply, ent)
    if not RT.CanUseDevice(ply, ent) then return false end
    if RT.HasAccess(ply) then return true end

    local accessConfig = CFG.Access or {}
    if accessConfig.AllowOwnerConfigureTemporary ~= false
        and ent.GRMRoomTapShopID
        and ent.GetOwnerSteam
        and ent:GetOwnerSteam() == steamID64(ply) then
        return true
    end

    return false
end

function RT.FindStorage(channel)
    channel = RT.NormalizeChannel(channel)

    for _, server in ipairs(ents.FindByClass("grm_roomtap_server")) do
        if IsValid(server) and server:GetActive() and RT.NormalizeChannel(server:GetChannel()) == channel then
            return server
        end
    end

    return nil
end

function RT.GetChipDetails(chip)
    if not IsValid(chip) then return {} end

    local manualSector = trim(chip:GetSector())
    return {
        deviceID = chip:GetDeviceID(),
        label = chip:GetLabel(),
        channel = RT.NormalizeChannel(chip:GetChannel()),
        manualSector = manualSector,
        autoSector = RT.GetAutoSector(chip:GetPos()),
        radius = chip:GetRadius(),
        active = chip:GetActive(),
        permanent = chip:GetPermanent(),
        owner = chip:GetOwnerName(),
    }
end

-- ============================================================
-- RECORDING TO SERVER MEDIA
-- ============================================================

local function mapFolder()
    return safeFilePart(game.GetMap() or "unknown", "unknown")
end

local function ensureRecordPath(channel)
    channel = RT.NormalizeChannel(channel)
    ensureDir(DATA_DIR)
    ensureDir(RECORDS_DIR)
    ensureDir(RECORDS_DIR .. "/" .. mapFolder())
    ensureDir(RECORDS_DIR .. "/" .. mapFolder() .. "/" .. channel)
    return RECORDS_DIR .. "/" .. mapFolder() .. "/" .. channel
end

local function recordFilePath(channel, timestamp)
    local root = ensureRecordPath(channel)
    return root .. "/" .. os.date("%Y-%m-%d", timestamp or os.time()) .. ".jsonl"
end

local function pushRecent(record)
    table.insert(RT.RecentRecords, 1, record)

    local max = math.max(50, tonumber(CFG.MemoryRecordsLimit) or 750)
    while #RT.RecentRecords > max do
        table.remove(RT.RecentRecords)
    end
end

local function subjectData(subject)
    if IsValid(subject) and subject:IsPlayer() then
        return {
            steamID = steamID64(subject),
            name = rpName(subject),
            position = vecToTable(subject:GetPos()),
        }
    end

    if istable(subject) then
        return {
            steamID = tostring(subject.steamID or ""),
            name = tostring(subject.name or "Неизвестно"),
            position = subject.position,
        }
    end

    return { steamID = "", name = "Система" }
end

-- Главная функция записи. Файл JSONL является «серверным носителем»:
-- data/grm_roomtap/records/<map>/<channel>/<date>.jsonl
function RT.WriteChipRecord(chip, eventName, subject, message, extra)
    if not IsValid(chip) or chip:GetClass() ~= "grm_roomtap_chip" or not chip:GetActive() then
        return false
    end

    local channel = RT.NormalizeChannel(chip:GetChannel())
    local storage = RT.FindStorage(channel)
    if not IsValid(storage) then return false end

    local now = os.time()
    local details = RT.GetChipDetails(chip)
    local record = {
        time = now,
        date = os.date("%Y-%m-%d %H:%M:%S", now),
        event = tostring(eventName or "event"),
        message = string.sub(trim(message), 1, 600),
        channel = channel,
        serverID = storage:GetDeviceID(),
        serverLabel = storage:GetLabel(),
        chipID = details.deviceID,
        chipLabel = details.label,
        sector = details.manualSector ~= "" and details.manualSector or "Не указан",
        autoSector = details.autoSector,
        radius = details.radius,
        subject = subjectData(subject),
        extra = istable(extra) and extra or nil,
    }

    local encoded = util.TableToJSON(record, false)
    if not encoded then return false end

    file.Append(recordFilePath(channel, now), encoded .. "\n")
    pushRecent(record)
    hook.Run("GRM_RoomTapRecorded", record, chip, storage)

    return true
end

local function loadRecentRecords()
    RT.RecentRecords = {}

    local root = RECORDS_DIR .. "/" .. mapFolder()
    if not file.Exists(root, "DATA") then return end

    local _, channels = file.Find(root .. "/*", "DATA")
    for _, channel in ipairs(channels or {}) do
        local channelPath = root .. "/" .. channel
        local files = file.Find(channelPath .. "/*.jsonl", "DATA")

        for _, fileName in ipairs(files or {}) do
            local raw = file.Read(channelPath .. "/" .. fileName, "DATA") or ""
            for line in string.gmatch(raw, "[^\r\n]+") do
                local ok, record = pcall(util.JSONToTable, line)
                if ok and istable(record) then
                    RT.RecentRecords[#RT.RecentRecords + 1] = record
                end
            end
        end
    end

    table.sort(RT.RecentRecords, function(a, b)
        return (tonumber(a.time) or 0) > (tonumber(b.time) or 0)
    end)

    local max = math.max(50, tonumber(CFG.MemoryRecordsLimit) or 750)
    while #RT.RecentRecords > max do
        table.remove(RT.RecentRecords)
    end
end

local function cleanupOldRecordFiles()
    local retention = tonumber(CFG.RecordsRetentionDays) or 0
    if retention <= 0 then return end

    local root = RECORDS_DIR .. "/" .. mapFolder()
    local _, channels = file.Find(root .. "/*", "DATA")
    local cutoff = os.time() - retention * 86400

    for _, channel in ipairs(channels or {}) do
        local channelPath = root .. "/" .. channel
        local files = file.Find(channelPath .. "/*.jsonl", "DATA")

        for _, fileName in ipairs(files or {}) do
            local y, m, d = string.match(fileName, "^(%d%d%d%d)%-(%d%d)%-(%d%d)%.jsonl$")
            if y then
                local stamp = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 0 })
                if stamp < cutoff then file.Delete(channelPath .. "/" .. fileName) end
            end
        end
    end
end

function RT.BuildTerminalData()
    local records = {}
    local limit = math.Clamp(tonumber(CFG.TerminalRecordsLimit) or 250, 10, 1000)

    for index = 1, math.min(#RT.RecentRecords, limit) do
        records[#records + 1] = RT.RecentRecords[index]
    end

    local chips = {}
    for _, chip in ipairs(ents.FindByClass("grm_roomtap_chip")) do
        if IsValid(chip) then
            local data = RT.GetChipDetails(chip)
            data.storageOnline = IsValid(RT.FindStorage(data.channel))
            chips[#chips + 1] = data
        end
    end

    table.sort(chips, function(a, b) return tostring(a.label) < tostring(b.label) end)

    local servers = {}
    for _, server in ipairs(ents.FindByClass("grm_roomtap_server")) do
        if IsValid(server) then
            servers[#servers + 1] = {
                deviceID = server:GetDeviceID(),
                label = server:GetLabel(),
                channel = server:GetChannel(),
                active = server:GetActive(),
                permanent = server:GetPermanent(),
            }
        end
    end

    return { records = records, chips = chips, servers = servers }
end

-- ============================================================
-- PRESENCE AND TEXT RECORDING
-- ============================================================

local function scanPresence()
    for _, chip in ipairs(ents.FindByClass("grm_roomtap_chip")) do
        if IsValid(chip) and chip:GetActive() and IsValid(RT.FindStorage(chip:GetChannel())) then
            local state = RT.Presence[chip] or {}
            RT.Presence[chip] = state
            local seen = {}
            local radiusSqr = math.max(1, chip:GetRadius()) ^ 2

            for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                local sid = steamID64(ply)
                local inside = ply:GetPos():DistToSqr(chip:GetPos()) <= radiusSqr
                seen[sid] = true

                if inside and not state[sid] then
                    local subject = subjectData(ply)
                    if RT.WriteChipRecord(chip, "enter", subject, "Игрок вошёл в радиус записи.") then
                        state[sid] = subject
                    end
                elseif not inside and state[sid] then
                    RT.WriteChipRecord(chip, "exit", state[sid], "Игрок покинул радиус записи.")
                    state[sid] = nil
                end
            end

            for sid, subject in pairs(state) do
                if not seen[sid] then
                    RT.WriteChipRecord(chip, "disconnect", subject, "Игрок отключился, находясь в радиусе записи.")
                    state[sid] = nil
                end
            end
        else
            RT.Presence[chip] = nil
        end
    end
end

hook.Add("PlayerSay", "GRM_RoomTap_TextRecording", function(ply, text)
    if not IsValid(ply) then return end

    text = trim(text)
    if text == "" then return end

    -- Команды не являются содержимым беседы и в журнал не попадают.
    local first = string.sub(text, 1, 1)
    if first == "/" or first == "!" then return end

    local fac = ply:GetNWString("GRM_Faction", "")
    local isJudge = false
    for _, w in ipairs({ "юстиц", "суд", "прокур", "правосуд", "justice", "court", "prokur" }) do
        if fac:lower():find(w, 1, true) then isJudge = true break end
    end

    local ck = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply)) or (ply.SteamID64 and ply:SteamID64()) or ""
    local hasJudgeWarrant = (not isJudge) or (GRM.Doors and GRM.Doors.HasWarrant and GRM.Doors.HasWarrant(ck, "wiretap_judge"))

local recordText = text    if isJudge and not hasJudgeWarrant then
        recordText = "[Защищено судебным иммунитетом: требуется ордер надзора Верховного суда]"
    end

    for _, chip in ipairs(ents.FindByClass("grm_roomtap_chip")) do
        if IsValid(chip) and chip:GetActive()
            and ply:GetPos():DistToSqr(chip:GetPos()) <= math.max(1, chip:GetRadius()) ^ 2 then
            RT.WriteChipRecord(chip, "text", ply, recordText)
        end
    end
end)

hook.Add("EntityRemoved", "GRM_RoomTap_PresenceCleanup", function(ent)
    if RT.Presence[ent] then RT.Presence[ent] = nil end

    -- Если временный предмет был удалён физически (cleanup, админом и т.п.),
    -- не восстанавливаем его затем из файла temporary_equipment.json.
    if RT.IsShuttingDown then return end

    local id = ent and ent.GRMRoomTapShopID or nil
    if id then
        RT.ShopOwned[id] = nil
        RT.ShopStored[id] = nil
        timer.Simple(0, function()
            if RT.SaveShopOwned then RT.SaveShopOwned() end
        end)
    end
end)

timer.Create("GRM_RoomTap_PresenceScan", math.max(1, tonumber(CFG.PresenceScanSeconds) or 2), 0, scanPresence)
timer.Create("GRM_RoomTap_ExpireTemporary", 30, 0, function()
    local changed = false
    local now = os.time()

    for id, record in pairs(RT.ShopOwned) do
        if tonumber(record.expiresAt) and record.expiresAt > 0 and record.expiresAt <= now then
            if IsValid(record.ent) then record.ent:Remove() end
            RT.ShopOwned[id] = nil
            RT.ShopStored[id] = nil
            changed = true
        end
    end

    if changed and RT.SaveShopOwned then RT.SaveShopOwned() end
end)

timer.Create("GRM_RoomTap_RecordCleanup", 3600, 0, cleanupOldRecordFiles)

-- ============================================================
-- MAP PERSISTENCE (ADMIN EQUIPMENT)
-- ============================================================

local function mapFile()
    return MAP_DIR .. "/" .. mapFolder() .. ".json"
end

local function entityRecord(ent)
    local record = {
        class = ent:GetClass(),
        pos = vecToTable(ent:GetPos()),
        ang = angToTable(ent:GetAngles()),
        deviceID = ent:GetDeviceID(),
        label = ent:GetLabel(),
        ownerSteam = ent:GetOwnerSteam(),
        ownerName = ent:GetOwnerName(),
        permanent = true,
    }

    if ent:GetClass() == "grm_roomtap_chip" then
        record.channel = ent:GetChannel()
        record.sector = ent:GetSector()
        record.radius = ent:GetRadius()
        record.active = ent:GetActive()
    elseif ent:GetClass() == "grm_roomtap_server" then
        record.channel = ent:GetChannel()
        record.active = ent:GetActive()
    end

    return record
end

local function applyRecord(ent, record)
    if not IsValid(ent) then return end

    ent:SetDeviceID(trim(record.deviceID) ~= "" and record.deviceID or newDeviceID(ent:GetClass()))
    ent:SetLabel(trim(record.label) ~= "" and record.label or ent.PrintName or ent:GetClass())
    ent:SetOwnerSteam(record.ownerSteam or "")
    ent:SetOwnerName(record.ownerName or "")
    ent:SetPermanent(record.permanent == true)

    if ent:GetClass() == "grm_roomtap_chip" then
        ent:SetChannel(RT.NormalizeChannel(record.channel))
        ent:SetSector(trim(record.sector))
        ent:SetRadius(math.Clamp(tonumber(record.radius) or CFG.DefaultChipRadius, CFG.MinChipRadius, CFG.MaxChipRadius))
        ent:SetActive(record.active ~= false)
    elseif ent:GetClass() == "grm_roomtap_server" then
        ent:SetChannel(RT.NormalizeChannel(record.channel))
        ent:SetActive(record.active ~= false)
    end
end

function RT.SaveMapEquipment(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then
        notify(ply, false, "Сохранять расстановку оборудования может только superadmin.")
        return false
    end

    ensureDir(DATA_DIR)
    ensureDir(MAP_DIR)

    local list = {}
    for class in pairs(RT.DeviceClasses) do
        for _, ent in ipairs(ents.FindByClass(class)) do
            if IsValid(ent) and ent:GetPermanent() then
                list[#list + 1] = entityRecord(ent)
            end
        end
    end

    writeJSON(mapFile(), list)
    if IsValid(ply) then notify(ply, true, "Сохранено постоянного оборудования: " .. #list) end
    print("[GRM RoomTap] Сохранено постоянного оборудования: " .. #list)
    return true
end

function RT.LoadMapEquipment(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then
        notify(ply, false, "Загружать расстановку оборудования может только superadmin.")
        return false
    end

    local list = readJSON(mapFile(), {})
    local count = 0

    -- Удаляем только предыдущее постоянное оборудование, не временное из магазина.
    for class in pairs(RT.DeviceClasses) do
        for _, ent in ipairs(ents.FindByClass(class)) do
            if IsValid(ent) and ent:GetPermanent() then ent:Remove() end
        end
    end

    for _, record in ipairs(list) do
        if istable(record) and RT.DeviceClasses[record.class] then
            local ent = ents.Create(record.class)
            if IsValid(ent) then
                ent:SetPos(tableToVec(record.pos))
                ent:SetAngles(tableToAng(record.ang))
                ent:Spawn()
                ent:Activate()
                applyRecord(ent, record)

                local phys = ent:GetPhysicsObject()
                if IsValid(phys) then phys:EnableMotion(false) end
                count = count + 1
            end
        end
    end

    if IsValid(ply) then notify(ply, true, "Загружено постоянного оборудования: " .. count) end
    print("[GRM RoomTap] Загружено постоянного оборудования: " .. count)
    return true
end

-- ============================================================
-- TEMPORARY SHOP EQUIPMENT
-- ============================================================

local function shopItem(itemID)
    return istable(CFG.ShopItems) and CFG.ShopItems[itemID] or nil
end

local function getDuration(id)
    for _, duration in ipairs(CFG.TemporaryDurations or {}) do
        if duration.id == id then return duration end
    end
    return nil
end

local function countShopOwned(ply, itemID)
    local sid = steamID64(ply)
    local total, perItem = 0, 0

    for _, record in pairs(RT.ShopOwned) do
        if record.ownerSteam == sid then
            total = total + 1
            if record.itemID == itemID then perItem = perItem + 1 end
        end
    end

    return total, perItem
end

local function refreshShopRecord(record)
    local ent = record.ent
    if not IsValid(ent) then return record end

    record.pos = vecToTable(ent:GetPos())
    record.ang = angToTable(ent:GetAngles())
    record.deviceID = ent:GetDeviceID()
    record.label = ent:GetLabel()

    if ent:GetClass() == "grm_roomtap_chip" then
        record.channel = ent:GetChannel()
        record.sector = ent:GetSector()
        record.radius = ent:GetRadius()
        record.active = ent:GetActive()
    elseif ent:GetClass() == "grm_roomtap_server" then
        record.channel = ent:GetChannel()
        record.active = ent:GetActive()
    end

    return record
end

function RT.SaveShopOwned()
    ensureDir(DATA_DIR)
    RT.ShopStored = RT.ShopStored or {}

    -- Обновляем только устройства текущей карты, но не теряем временное
    -- оборудование на других картах при смене карты/рестарте.
    for id, record in pairs(RT.ShopOwned) do
        refreshShopRecord(record)
        local copy = table.Copy(record)
        copy.ent = nil
        RT.ShopStored[id] = copy
    end

    local now = os.time()
    for id, record in pairs(RT.ShopStored) do
        if not istable(record) or (tonumber(record.expiresAt) or 0) <= now then
            RT.ShopStored[id] = nil
        end
    end

    writeJSON(SHOP_FILE, RT.ShopStored)
end

local function applyShopRecord(ent, record)
    applyRecord(ent, {
        deviceID = record.deviceID,
        label = record.label,
        ownerSteam = record.ownerSteam,
        ownerName = record.ownerName,
        channel = record.channel,
        sector = record.sector,
        radius = record.radius,
        active = record.active,
        permanent = false,
    })

    ent.GRMRoomTapShopID = record.id
end

local function spawnShopRecord(record)
    if not record or not RT.DeviceClasses[record.class] then return nil end

    local ent = ents.Create(record.class)
    if not IsValid(ent) then return nil end

    ent:SetPos(tableToVec(record.pos))
    ent:SetAngles(tableToAng(record.ang))
    ent:Spawn()
    ent:Activate()
    applyShopRecord(ent, record)

    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then phys:EnableMotion(false) end

    record.ent = ent
    RT.ShopOwned[record.id] = record
    return ent
end

function RT.LoadShopOwned()
    RT.ShopOwned = {}
    RT.ShopStored = readJSON(SHOP_FILE, {})

    local now = os.time()
    local count = 0

    for id, record in pairs(RT.ShopStored) do
        if not istable(record) or (tonumber(record.expiresAt) or 0) <= now then
            RT.ShopStored[id] = nil
        elseif record.map == game.GetMap() and RT.DeviceClasses[record.class] then
            record.id = record.id or id
            if spawnShopRecord(record) then count = count + 1 end
        end
    end

    RT.SaveShopOwned()
    print("[GRM RoomTap] Загружено временного оборудования: " .. count)
end

local function canBuyTemporary(ply, itemID)
    local item = shopItem(itemID)
    if not item then return false, "Товар не найден." end

    if CFG.ShopRequireEquipmentAccess ~= false and not RT.HasAccess(ply) then
        return false, "Нет доступа к оборудованию прослушки. Обратитесь к руководителю фракции."
    end

    local _, perItem = countShopOwned(ply, itemID)
    if tonumber(item.maxOwned) and perItem >= item.maxOwned then
        return false, "Лимит этого оборудования: " .. tostring(item.maxOwned)
    end

    return true
end

local function makeShopRecord(ply, itemID, duration)
    local item = shopItem(itemID)
    local pos = ply:GetPos() + ply:GetForward() * (tonumber(CFG.ShopSpawnDistance) or 90) + Vector(0, 0, 8)
    local angle = Angle(0, ply:EyeAngles().y + 180, 0)
    local id = string.format("rteq_%d_%d_%d", os.time(), ply:EntIndex(), math.random(1000, 9999))

    return {
        id = id,
        itemID = itemID,
        class = item.class,
        map = game.GetMap(),
        ownerSteam = steamID64(ply),
        ownerName = rpName(ply),
        expiresAt = os.time() + duration.seconds,
        createdAt = os.time(),
        pos = vecToTable(pos),
        ang = angToTable(angle),
        deviceID = newDeviceID(itemID),
        label = item.name,
        channel = "main",
        sector = "",
        radius = CFG.DefaultChipRadius,
        active = true,
        requestedPermanent = false,
    }
end

local function sendShopData(ply)
    local items = {}

    for id, item in pairs(CFG.ShopItems or {}) do
        local copy = table.Copy(item)
        local ok, reason = canBuyTemporary(ply, id)
        copy.canBuy = ok
        copy.reason = reason or ""
        local _, amount = countShopOwned(ply, id)
        copy.owned = amount
        items[id] = copy
    end

    net.Start(NET_SHOP_DATA)
        net.WriteTable(items)
        net.WriteTable(CFG.TemporaryDurations or {})
    net.Send(ply)
end

local function removeNearestOwned(ply)
    local sid = steamID64(ply)
    local best, bestDistance
    local maxDistance = (tonumber(CFG.ShopRemoveDistance) or 180) ^ 2

    for _, record in pairs(RT.ShopOwned) do
        if record.ownerSteam == sid and IsValid(record.ent) then
            local distance = record.ent:GetPos():DistToSqr(ply:GetPos())
            if distance <= maxDistance and (not bestDistance or distance < bestDistance) then
                best = record
                bestDistance = distance
            end
        end
    end

    if not best then return false, "Рядом нет вашего временного оборудования." end

    if IsValid(best.ent) then best.ent:Remove() end
    RT.ShopOwned[best.id] = nil
    RT.ShopStored[best.id] = nil
    RT.SaveShopOwned()
    return true, "Временное оборудование удалено."
end

function RT.MakePermanent(ent)
    if not RT.IsDevice(ent) then return false end

    if ent.GRMRoomTapShopID then
        RT.ShopOwned[ent.GRMRoomTapShopID] = nil
        RT.ShopStored[ent.GRMRoomTapShopID] = nil
        ent.GRMRoomTapShopID = nil
        RT.SaveShopOwned()
    end

    ent:SetPermanent(true)
    RT.SaveMapEquipment(nil)
    return true
end

local function sendRequests(ply)
    if not IsValid(ply) or not ply:IsSuperAdmin() then
        if IsValid(ply) then notify(ply, false, "Список запросов доступен только superadmin.") end
        return
    end

    local requests = {}
    for id, record in pairs(RT.ShopOwned) do
        if record.requestedPermanent then
            requests[#requests + 1] = {
                id = id,
                ownerName = record.ownerName,
                ownerSteam = record.ownerSteam,
                itemID = record.itemID,
                label = record.label,
                expiresAt = record.expiresAt,
                online = IsValid(record.ent),
            }
        end
    end

    net.Start(NET_REQUESTS_DATA)
        net.WriteTable(requests)
    net.Send(ply)
end

-- ============================================================
-- OPEN EQUIPMENT MENUS
-- ============================================================

function RT.OpenChipMenu(ply, chip)
    if not RT.CanConfigure(ply, chip) then
        notify(ply, false, "Нет доступа к этому чипу или вы слишком далеко.")
        return
    end

    local details = RT.GetChipDetails(chip)
    details.storageOnline = IsValid(RT.FindStorage(details.channel))

    net.Start(NET_OPEN_CHIP)
        net.WriteEntity(chip)
        net.WriteTable(details)
        net.WriteBool(ply:IsSuperAdmin())
        net.WriteBool(chip.GRMRoomTapShopID ~= nil and chip:GetOwnerSteam() == steamID64(ply))
    net.Send(ply)
end

function RT.OpenServerMenu(ply, server)
    if not RT.CanConfigure(ply, server) then
        notify(ply, false, "Нет доступа к серверной стойке или вы слишком далеко.")
        return
    end

    net.Start(NET_OPEN_SERVER)
        net.WriteEntity(server)
        net.WriteTable({
            deviceID = server:GetDeviceID(),
            label = server:GetLabel(),
            channel = server:GetChannel(),
            active = server:GetActive(),
            permanent = server:GetPermanent(),
            owner = server:GetOwnerName(),
        })
        net.WriteBool(ply:IsSuperAdmin())
        net.WriteBool(server.GRMRoomTapShopID ~= nil and server:GetOwnerSteam() == steamID64(ply))
    net.Send(ply)
end

function RT.OpenTerminalMenu(ply, terminal)
    if not RT.CanUseDevice(ply, terminal) or not RT.HasAccess(ply) then
        notify(ply, false, "Нет доступа к компьютеру мониторинга.")
        return
    end

    net.Start(NET_OPEN_TERMINAL)
        net.WriteEntity(terminal)
        net.WriteTable(RT.BuildTerminalData())
        net.WriteBool(ply:IsSuperAdmin())
        net.WriteBool(terminal.GRMRoomTapShopID ~= nil and terminal:GetOwnerSteam() == steamID64(ply))
    net.Send(ply)
end

-- ============================================================
-- NETWORK
-- ============================================================

net.Receive(NET_DEVICE_ACTION, function(_, ply)
    local action = net.ReadString()
    local ent = net.ReadEntity()

    if not RT.IsDevice(ent) then return end

    if action == "chip_set" then
        local label = string.sub(trim(net.ReadString()), 1, 80)
        local channel = RT.NormalizeChannel(net.ReadString())
        local sector = string.sub(trim(net.ReadString()), 1, 80)
        local radius = math.Clamp(net.ReadUInt(16), CFG.MinChipRadius, CFG.MaxChipRadius)
        local active = net.ReadBool()

        if ent:GetClass() ~= "grm_roomtap_chip" or not RT.CanConfigure(ply, ent) then return end

        ent:SetLabel(label ~= "" and label or "Чип прослушки")
        ent:SetChannel(channel)
        ent:SetSector(sector)
        ent:SetRadius(radius)
        ent:SetActive(active)
        RT.WriteChipRecord(ent, "chip_config", ply, "Настройки чипа изменены.")
        notify(ply, true, "Настройки чипа сохранены.")
        RT.SaveShopOwned()
        return
    end

    if action == "server_set" then
        local label = string.sub(trim(net.ReadString()), 1, 80)
        local channel = RT.NormalizeChannel(net.ReadString())
        local active = net.ReadBool()

        if ent:GetClass() ~= "grm_roomtap_server" or not RT.CanConfigure(ply, ent) then return end

        ent:SetLabel(label ~= "" and label or "Серверная стойка")
        ent:SetChannel(channel)
        ent:SetActive(active)
        notify(ply, true, "Настройки серверной стойки сохранены.")
        RT.SaveShopOwned()
        return
    end

    if action == "make_permanent" then
        if not ply:IsSuperAdmin() or not RT.CanUseDevice(ply, ent) then return end
        RT.MakePermanent(ent)
        notify(ply, true, "Оборудование отмечено постоянным и сохранено для карты.")
        return
    end

    if action == "request_permanent" then
        if not RT.CanUseDevice(ply, ent) or not ent.GRMRoomTapShopID or ent:GetOwnerSteam() ~= steamID64(ply) then return end
        local record = RT.ShopOwned[ent.GRMRoomTapShopID]
        if not record then return end

        record.requestedPermanent = true
        RT.SaveShopOwned()
        notify(ply, true, "Запрос на постоянное сохранение оборудования отправлен администраторам.")

        for _, admin in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if admin:IsSuperAdmin() then
                notify(admin, false, "[Прослушка] Запрос сохранения от " .. rpName(ply) .. ". Команда: roomtap_requests")
            end
        end
        return
    end
end)

net.Receive(NET_TERMINAL_DATA, function(_, ply)
    local terminal = net.ReadEntity()
    if IsValid(terminal) and terminal:GetClass() == "grm_roomtap_terminal" then
        RT.OpenTerminalMenu(ply, terminal)
    end
end)

net.Receive(NET_SHOP_OPEN, function(_, ply)
    sendShopData(ply)
    net.Start(NET_SHOP_OPEN)
    net.Send(ply)
end)

net.Receive(NET_SHOP_SPAWN, function(_, ply)
    local itemID = net.ReadString()
    local durationID = net.ReadString()
    local item = shopItem(itemID)
    local duration = getDuration(durationID)
    local ok, reason = canBuyTemporary(ply, itemID)

    if not ok then notify(ply, false, reason) return end
    if not duration then notify(ply, false, "Выберите срок временной установки.") return end

    local price = math.floor((tonumber(item.price) or 0) * (tonumber(duration.multiplier) or 1))
    if not canPay(ply, price) then
        notify(ply, false, "Недостаточно средств. Нужно: " .. moneyText(price))
        return
    end

    local record = makeShopRecord(ply, itemID, duration)
    local ent = spawnShopRecord(record)
    if not IsValid(ent) then
        RT.ShopOwned[record.id] = nil
        notify(ply, false, "Не удалось установить оборудование.")
        return
    end

    takeMoney(ply, price)
    RT.SaveShopOwned()
    notify(ply, true, "Установлено временное оборудование на " .. duration.name .. ": " .. item.name)
    sendShopData(ply)
end)

net.Receive(NET_SHOP_REMOVE, function(_, ply)
    local ok, message = removeNearestOwned(ply)
    notify(ply, ok, message)
    sendShopData(ply)
end)

net.Receive(NET_ACCESS_REQUEST, function(_, ply)
    sendAccessData(ply)
end)

net.Receive(NET_ACCESS_SAVE, function(_, ply)
    if not IsValid(ply) or not ply:IsSuperAdmin() then return end
    RT.SaveAccess(net.ReadTable() or {})
    notify(ply, true, "Доступ к прослушке помещений сохранён.")
    sendAccessData(ply)
end)

net.Receive(NET_REQUESTS_OPEN, function(_, ply)
    sendRequests(ply)
end)

net.Receive(NET_REQUEST_APPROVE, function(_, ply)
    if not IsValid(ply) or not ply:IsSuperAdmin() then return end

    local id = net.ReadString()
    local record = RT.ShopOwned[id]
    if not record or not record.requestedPermanent or not IsValid(record.ent) then
        notify(ply, false, "Запрос не найден или оборудование уже удалено.")
        return
    end

    RT.MakePermanent(record.ent)
    notify(ply, true, "Оборудование игрока сохранено постоянно.")
    sendRequests(ply)
end)

-- ============================================================
-- COMMANDS
-- ============================================================

hook.Add("PlayerSay", "GRM_RoomTap_ChatCommands", function(ply, text)
    local command = string.lower(trim(text))

    if command == "/roomtapshop" or command == "!roomtapshop" or command == "/rtshop" then
        sendShopData(ply)
        net.Start(NET_SHOP_OPEN)
        net.Send(ply)
        return ""
    end

    if command == "/roomtap_access" or command == "!roomtap_access" then
        sendAccessData(ply)
        return ""
    end

    if command == "/roomtap_requests" or command == "!roomtap_requests" then
        sendRequests(ply)
        return ""
    end

    if command == "/roomtap_remove" or command == "!roomtap_remove" then
        local ok, message = removeNearestOwned(ply)
        notify(ply, ok, message)
        return ""
    end
end)

concommand.Add("roomtap_shop", function(ply)
    if IsValid(ply) then
        sendShopData(ply)
        net.Start(NET_SHOP_OPEN)
        net.Send(ply)
    end
end)

concommand.Add("roomtap_access", function(ply)
    if IsValid(ply) then sendAccessData(ply) end
end)

concommand.Add("roomtap_requests", function(ply)
    if IsValid(ply) then sendRequests(ply) end
end)

concommand.Add("roomtap_remove", function(ply)
    if IsValid(ply) then
        local ok, message = removeNearestOwned(ply)
        notify(ply, ok, message)
    end
end)

concommand.Add("grm_roomtap_save", function(ply)
    RT.SaveMapEquipment(ply)
end)

concommand.Add("grm_roomtap_load", function(ply)
    RT.LoadMapEquipment(ply)
end)

concommand.Add("grm_roomtap_reload", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    RT.LoadAccess()
    loadRecentRecords()
    if IsValid(ply) then notify(ply, true, "GRM RoomTap перезагружен.") end
end)

concommand.Add("grm_roomtap_debug", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    local line = string.format("[GRM RoomTap] chips=%d servers=%d terminals=%d recent=%d temporary=%d",
        #ents.FindByClass("grm_roomtap_chip"),
        #ents.FindByClass("grm_roomtap_server"),
        #ents.FindByClass("grm_roomtap_terminal"),
        #RT.RecentRecords,
        table.Count(RT.ShopOwned)
    )
    if IsValid(ply) then ply:ChatPrint(line) else print(line) end
end)

-- ============================================================
-- BOOT / SAVE
-- ============================================================

RT.LoadAccess()

grmBootStart("GRM_RoomTap_LoadEquipment", "normal", function()
    timer.Simple(1, function()
        RT.LoadMapEquipment(nil)
        loadRecentRecords()
        cleanupOldRecordFiles()
    end)

    timer.Simple(2, function()
        RT.LoadShopOwned()
    end)
end)

hook.Add("PostCleanupMap", "GRM_RoomTap_Cleanup", function()
    timer.Simple(0.5, function()
        RT.LoadMapEquipment(nil)
    end)
end)

hook.Add("ShutDown", "GRM_RoomTap_Save", function()
    -- EntityRemoved срабатывает при выключении сервера; временные записи
    -- в этот момент нельзя удалять, иначе они не переживут рестарт.
    RT.IsShuttingDown = true
    RT.SaveShopOwned()
    RT.SaveMapEquipment(nil)
end)

timer.Create("GRM_RoomTap_AutoSave", 60, 0, function()
    RT.SaveShopOwned()
end)

print("[GRM RoomTap] Server loaded")

-- Вечер-18: единый словарь slash-команд: имена живого PlayerSay-обработчика
-- вносятся во внешний реестр библиотеки (на режиме сверка идёт ДО ParseSay —
-- без регистрации команда стала бы «неизвестной»).
if GRM and GRM.Chat and GRM.Chat.RegisterExternalCommands then
    GRM.Chat.RegisterExternalCommands({ "/roomtap_access", "/roomtap_remove", "/roomtap_requests", "/roomtapshop", "/rtshop" })
end
