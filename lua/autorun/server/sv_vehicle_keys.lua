--[[--------------------------------------------------------------------
    GRM Vehicle Keys (VK) — server

    IMPORTANT:
    This is the only file that registers VK_Keys_Give / VK_Keys_Revoke
    receivers. The SWEP only sends requests and never owns these handlers.
----------------------------------------------------------------------]]

if CLIENT then return end

AddCSLuaFile("autorun/sh_vehicle_keys.lua")
AddCSLuaFile("autorun/client/cl_vehicle_hud.lua")
include("autorun/sh_vehicle_keys.lua")

VK = VK or {}

local NET_SYNC_VEHICLE = "VK_SyncVehicle"
local NET_RESULT = "VK_Result"
local NET_KEYS_SYNC = "VK_Keys_Sync"
local NET_REQUEST_LIST = "VK_RequestPlayerList"
local NET_SEND_LIST = "VK_SendPlayerList"
local NET_GIVE_KEY = "VK_Keys_Give"
local NET_REVOKE_KEY = "VK_Keys_Revoke"

local NET_TOGGLE_LOCK = "VK_ToggleLock"

for _, name in ipairs({
    NET_SYNC_VEHICLE, NET_RESULT, NET_KEYS_SYNC, NET_REQUEST_LIST,
    NET_SEND_LIST, NET_GIVE_KEY, NET_REVOKE_KEY, NET_TOGGLE_LOCK,
}) do
    util.AddNetworkString(name)
end

local function sqlEscape(value)
    return sql.SQLStr(tostring(value or ""))
end

local function query(statement)
    local result = sql.Query(statement)
    if result == false then
        ErrorNoHalt("[VK] SQLite error: " .. tostring(sql.LastError()) .. "\n")
    end
    return result
end

local function initDatabase()
    query([[CREATE TABLE IF NOT EXISTS vk_keys (
        id TEXT PRIMARY KEY,
        owner_steam TEXT NOT NULL,
        name TEXT DEFAULT '',
        col_r INTEGER DEFAULT 100,
        col_g INTEGER DEFAULT 200,
        col_b INTEGER DEFAULT 255,
        created_at INTEGER DEFAULT 0
    )]])

    query([[CREATE TABLE IF NOT EXISTS vk_player_keys (
        steam_id TEXT NOT NULL,
        key_id TEXT NOT NULL,
        PRIMARY KEY (steam_id, key_id)
    )]])
end

initDatabase()

VK.Cache = {
    keys = {}, -- [keyID] = { owner_steam, name, r, g, b }
    rings = {}, -- [steamID] = { keyID, ... }
}

local function loadCache()
    local keys = query("SELECT * FROM vk_keys") or {}
    for _, row in ipairs(keys) do
        VK.Cache.keys[row.id] = {
            owner_steam = row.owner_steam,
            name = row.name or "Ключ",
            r = tonumber(row.col_r) or 100,
            g = tonumber(row.col_g) or 200,
            b = tonumber(row.col_b) or 255,
        }
    end

    local holderKeys = query("SELECT * FROM vk_player_keys") or {}
    for _, row in ipairs(holderKeys) do
        if VK.Cache.keys[row.key_id] then
            VK.Cache.rings[row.steam_id] = VK.Cache.rings[row.steam_id] or {}
            table.insert(VK.Cache.rings[row.steam_id], row.key_id)
        end
    end

    print("[VK] Loaded keys: " .. table.Count(VK.Cache.keys))
end

loadCache()

local function playerSteamID(ply)
    if not IsValid(ply) then return "" end
    if GRM.Identity and GRM.Identity.CharacterKey then return GRM.Identity.CharacterKey(ply) end
    return ply:SteamID() or ""
end

local function characterOneKey(value)
    local raw = tostring(value or "")
    if raw:match(":char[1-3]$") then return raw end
    if raw:match("^%d+$") then return raw .. ":char1" end
    if util.SteamIDTo64 then
        local s64 = util.SteamIDTo64(raw)
        if s64 and s64 ~= "0" then return tostring(s64) .. ":char1" end
    end
    return raw
end

local function migrateLegacyRing(ply)
    if not IsValid(ply) then return end
    local active = playerSteamID(ply)
    if not active:match(":char1$") then return end
    local sources = { ply:SteamID(), ply:SteamID64(), characterOneKey(ply:SteamID64()) }
    local target = VK.Cache.rings[active] or {}
    VK.Cache.rings[active] = target
    for _, source in ipairs(sources) do
        for _, keyID in ipairs(VK.Cache.rings[tostring(source)] or {}) do
            if not table.HasValue(target, keyID) then
                target[#target + 1] = keyID
                query("INSERT OR IGNORE INTO vk_player_keys(steam_id, key_id) VALUES(" .. sqlEscape(active) .. "," .. sqlEscape(keyID) .. ")")
            end
        end
    end
end

for _, key in pairs(VK.Cache.keys) do
    key.owner_steam = characterOneKey(key.owner_steam)
end

local function accountSteamID(ply)
    return IsValid(ply) and (ply:SteamID() or "") or ""
end

local function makeKeyID()
    return string.format("vkey_%d_%d_%d", os.time(), math.random(100000, 999999), math.random(100000, 999999))
end

local function ownerKeyID(ownerSteam)
    for keyID, key in pairs(VK.Cache.keys) do
        if key.owner_steam == ownerSteam then return keyID end
    end
    return nil
end

function VK.Result(ply, ok, message)
    if not IsValid(ply) then return end

    net.Start(NET_RESULT)
        net.WriteBool(ok == true)
        net.WriteString(tostring(message or ""))
    net.Send(ply)
end

function VK.CreateKey(ownerSteam, name, r, g, b)
    ownerSteam = tostring(ownerSteam or "")
    if ownerSteam == "" then return nil end

    local defaultColor = VK.KEY_CONFIG.DEFAULT_COLOR or { r = 100, g = 200, b = 255 }
    r = math.Clamp(tonumber(r) or defaultColor.r, 0, 255)
    g = math.Clamp(tonumber(g) or defaultColor.g, 0, 255)
    b = math.Clamp(tonumber(b) or defaultColor.b, 0, 255)

    local keyID = makeKeyID()
    local keyName = tostring(name or ("Ключи от машин: " .. ownerSteam))

    local ok = query("INSERT INTO vk_keys(id, owner_steam, name, col_r, col_g, col_b, created_at) VALUES(" ..
        sqlEscape(keyID) .. "," .. sqlEscape(ownerSteam) .. "," .. sqlEscape(keyName) .. "," ..
        r .. "," .. g .. "," .. b .. "," .. os.time() .. ")")

    if ok == false then return nil end

    VK.Cache.keys[keyID] = {
        owner_steam = ownerSteam,
        name = keyName,
        r = r,
        g = g,
        b = b,
    }

    return keyID
end

function VK.GetOrCreateOwnerKey(ownerSteam, displayName)
    local existing = ownerKeyID(ownerSteam)
    if existing then return existing end
    return VK.CreateKey(ownerSteam, displayName)
end

function VK.GiveKey(holderSteam, keyID)
    holderSteam = tostring(holderSteam or "")
    if holderSteam == "" then return false, "Некорректный SteamID" end
    if not VK.Cache.keys[keyID] then return false, "Ключ не существует" end

    local ring = VK.Cache.rings[holderSteam] or {}
    VK.Cache.rings[holderSteam] = ring

    if table.HasValue(ring, keyID) then return false, "Уже есть" end

    local ok = query("INSERT OR IGNORE INTO vk_player_keys(steam_id, key_id) VALUES(" ..
        sqlEscape(holderSteam) .. "," .. sqlEscape(keyID) .. ")")
    if ok == false then return false, "Ошибка базы данных" end

    table.insert(ring, keyID)
    return true
end

function VK.RevokeKey(holderSteam, keyID)
    holderSteam = tostring(holderSteam or "")
    local ring = VK.Cache.rings[holderSteam]
    if not ring then return false, "У игрока нет ключей" end

    for index, currentKeyID in ipairs(ring) do
        if currentKeyID == keyID then
            local ok = query("DELETE FROM vk_player_keys WHERE steam_id=" .. sqlEscape(holderSteam) ..
                " AND key_id=" .. sqlEscape(keyID))
            if ok == false then return false, "Ошибка базы данных" end

            table.remove(ring, index)
            return true
        end
    end

    return false, "У игрока нет этого ключа"
end

function VK.HasOwnerKey(holderSteam, ownerSteam)
    local ring = VK.Cache.rings[tostring(holderSteam or "")] or {}

    for _, keyID in ipairs(ring) do
        local key = VK.Cache.keys[keyID]
        if key and key.owner_steam == ownerSteam then return true end
    end

    return false
end

function VK.SyncKeyRing(ply)
    if not IsValid(ply) then return end
    migrateLegacyRing(ply)

    local data = {}
    for _, keyID in ipairs(VK.Cache.rings[playerSteamID(ply)] or {}) do
        local key = VK.Cache.keys[keyID]
        if key then data[keyID] = key end
    end

    net.Start(NET_KEYS_SYNC)
        net.WriteTable(data)
    net.Send(ply)
end

function VK.IsFactionMember(ply, factionName)
    if not IsValid(ply) or not factionName then return false end
    -- Фракции GRM после CharacterKey могут хранить состав не по SteamID.
    -- NW-поле публикуется ядром именно для текущего персонажа и является
    -- надёжным быстрым путём для замков служебной техники.
    if tostring(ply:GetNWString("GRM_Faction", "")) == tostring(factionName) then return true end
    if not istable(Factions) then return false end

    local faction = Factions[factionName]
    if not istable(faction) or not istable(faction.Members) then return false end

    local ck = playerSteamID(ply)
    return faction.Members[ck] ~= nil
        or faction.Members[ply:SteamID()] ~= nil
        or faction.Members[ply:SteamID64()] ~= nil
end

function VK.PlayerHasFactionVehicleAccess(ply)
    if not IsValid(ply) then return false end

    for _, vehicle in ipairs(ents.GetAll()) do
        if VK.IsVehicle(vehicle)
            and vehicle.VK_OwnerType == VK.OWNER_TYPE.FACTION
            and VK.IsFactionMember(ply, vehicle.VK_FactionName) then
            return true
        end
    end

    return false
end

--[[ СНЯТИЕ УДАЛЁННЫХ СВЕПОВ (31.08, заказ владельца «удали старые
     свепы ключей»).

     Файлы ds_key_swep и vehicle_keys_swep удалены, но у игроков они
     уже лежат в слотах с прошлых заходов. Класса больше нет — движок
     оставит «фантомное» оружие, которое нельзя ни достать, ни
     выбросить, и оно будет висеть в инвентаре вечно.

     Поэтому снимаем их при первом же обновлении ключей: взамен игрок
     тут же получит новую связку, ниже по этой функции. ]]
local LEGACY_KEY_SWEPS = { "ds_key_swep", "vehicle_keys_swep" }

function VK.StripLegacySweps(ply)
    if not IsValid(ply) then return end
    for _, cls in ipairs(LEGACY_KEY_SWEPS) do
        if ply:HasWeapon(cls) then ply:StripWeapon(cls) end
    end
end

function VK.UpdateKeySwep(ply)
    if not IsValid(ply) then return end
    migrateLegacyRing(ply)
    VK.StripLegacySweps(ply)

    local config = VK.KEY_CONFIG or {}
    local ring = VK.Cache.rings[playerSteamID(ply)] or {}
    local shouldHaveSWEP = #ring > 0 or VK.PlayerHasFactionVehicleAccess(ply)
    local swepClass = config.SWEP_CLASS or "grm_keyring"

    if shouldHaveSWEP then
        if config.AUTO_GIVE_SWEP ~= false and not ply:HasWeapon(swepClass) then
            ply:Give(swepClass)
        end
    elseif config.AUTO_STRIP_SWEP ~= false and ply:HasWeapon(swepClass) then
        ply:StripWeapon(swepClass)
    end
end

local function refreshAllKeySWEPS()
    local list = (GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()
    -- Распределение нагрузки: на полном сервере обновление ключей у всех
    -- разом заметно в тике. Отдаём очереди GRM.Perf — она размажет проход
    -- по кадрам в рамках бюджета.
    if GRM.Perf and GRM.Perf.Spread and #list > 8 then
        GRM.Perf.Spread("vehiclekeys.refresh", list, function(ply)
            if IsValid(ply) then VK.UpdateKeySwep(ply) end
        end, { chunk = 4 })
        return
    end
    for _, ply in ipairs(list) do VK.UpdateKeySwep(ply) end
end

-- ============================================================
-- VEHICLE OWNERSHIP / NETWORK STATE
-- ============================================================

function VK.SyncVehicle(veh, target)
    if not IsValid(veh) then return end

    -- NW2 gives the SWEP reliable client-side state even if a custom sync
    -- arrives before its client receiver has loaded.
    veh:SetNW2String("VK_OwnerType", veh.VK_OwnerType or "")
    veh:SetNW2String("VK_OwnerSteam", veh.VK_OwnerSteam or "")
    veh:SetNW2String("VK_OwnerNick", veh.VK_OwnerNick or "")
    veh:SetNW2String("VK_FactionName", veh.VK_FactionName or "")
    veh:SetNW2Bool("VK_Locked", veh.VK_Locked == true)

    net.Start(NET_SYNC_VEHICLE)
        net.WriteEntity(veh)
        net.WriteString(veh.VK_OwnerType or "")
        net.WriteString(veh.VK_OwnerSteam or "")
        net.WriteString(veh.VK_OwnerNick or "")
        net.WriteString(veh.VK_FactionName or "")
        net.WriteBool(veh.VK_Locked == true)
    if IsValid(target) then net.Send(target) else net.Broadcast() end
end

function VK.SetPlayerOwner(veh, ply)
    if not IsValid(veh) or not IsValid(ply) then return false end

    veh.VK_OwnerType = VK.OWNER_TYPE.PLAYER
    veh.VK_OwnerSteam = playerSteamID(ply)
    veh.VK_OwnerNick = ply:Nick()
    veh.VK_FactionName = nil
    veh.VD_Owner = ply -- compatibility with Vehicle Dealer
    -- При выдаче/смене владельца транспорт всегда закрывается.
    veh.VK_Locked = true

    local keyID = VK.GetOrCreateOwnerKey(playerSteamID(ply), "Ключи от машин: " .. ply:Nick())
    if keyID then VK.GiveKey(playerSteamID(ply), keyID) end

    VK.SyncKeyRing(ply)
    VK.UpdateKeySwep(ply)
    VK.SyncVehicle(veh)
    return true
end

function VK.SetFactionOwner(veh, factionName)
    if not IsValid(veh) or not isstring(factionName) or factionName == "" then return false end

    veh.VK_OwnerType = VK.OWNER_TYPE.FACTION
    veh.VK_OwnerSteam = nil
    veh.VK_OwnerNick = nil
    veh.VK_FactionName = factionName
    veh.VD_Owner = nil
    -- Передача фракции также начинается с закрытого транспорта.
    veh.VK_Locked = true

    VK.SyncVehicle(veh)
    refreshAllKeySWEPS()
    return true
end

function VK.ClearOwner(veh)
    if not IsValid(veh) then return false end

    veh.VK_OwnerType = nil
    veh.VK_OwnerSteam = nil
    veh.VK_OwnerNick = nil
    veh.VK_FactionName = nil
    veh.VD_Owner = nil
    veh.VK_Locked = false -- ownerless vehicle must remain accessible

    VK.SyncVehicle(veh)
    refreshAllKeySWEPS()
    return true
end

function VK.CanInteract(veh, ply, requireOwnerLevel)
    if not IsValid(veh) or not IsValid(ply) or not VK.IsVehicle(veh) then return false end
    if ply:IsSuperAdmin() then return true end

    if veh.VK_OwnerType == VK.OWNER_TYPE.PLAYER and veh.VK_OwnerSteam == playerSteamID(ply) then
        return true
    end

    if requireOwnerLevel then return false end

    if veh.VK_OwnerType == VK.OWNER_TYPE.FACTION then
        return VK.IsFactionMember(ply, veh.VK_FactionName)
    end

    if veh.VK_OwnerType == VK.OWNER_TYPE.PLAYER and veh.VK_OwnerSteam then
        return VK.HasOwnerKey(playerSteamID(ply), veh.VK_OwnerSteam)
    end

    return false
end

function VK.GetAimedVehicle(ply, range)
    if not IsValid(ply) then return nil end

    local trace = util.TraceLine({
        start = ply:EyePos(),
        endpos = ply:EyePos() + ply:GetAimVector() * (range or VK.INTERACT_RANGE),
        filter = ply,
        mask = MASK_ALL,
    })

    return IsValid(trace.Entity) and VK.IsVehicle(trace.Entity) and trace.Entity or nil
end

function VK.IsLookingAtVehicle(ply, veh, range)
    return VK.GetAimedVehicle(ply, range) == veh
end

local function canManagePersonalKeys(ply, veh)
    return IsValid(veh)
        and VK.IsLookingAtVehicle(ply, veh)
        and veh.VK_OwnerType == VK.OWNER_TYPE.PLAYER
        and VK.CanInteract(veh, ply, true)
end

-- ============================================================
-- LOCKING AND DOORS
-- ============================================================

local function lockTarget(ent)
    if not IsValid(ent) then return nil end
    if VK.IsVehicle(ent) then return ent end

    -- Standard passenger seats and many vehicle addons parent seats to vehicle.
    local parent = ent:GetParent()
    for _ = 1, 3 do
        if not IsValid(parent) then break end
        if VK.IsVehicle(parent) then return parent end
        parent = parent:GetParent()
    end

    return nil
end

local function denyLockedEntry(ply, ent)
    local veh = lockTarget(ent)
    if not IsValid(veh) or not veh.VK_Locked or ply:IsSuperAdmin() then return end

    ply:ChatPrint("[VK] Транспорт заблокирован. Используйте связку ключей.")
    ply:EmitSound(VK.SND.DENY, 65, 100, 0.7)
    return false
end

hook.Add("PlayerUse", "VK_LockCheckUse", denyLockedEntry)
hook.Add("CanPlayerEnterVehicle", "VK_LockCheckEnter", denyLockedEntry)

function VK.ToggleLock(ply, veh)
    if not IsValid(ply) or ply:InVehicle() then return false end
    veh = veh or VK.GetAimedVehicle(ply)
    if not IsValid(veh) then
        VK.Result(ply, false, "Посмотрите на машину")
        return false
    end
    if not VK.CanInteract(veh, ply, false) then
        ply:EmitSound(VK.SND.DENY, 65, 100, 0.7)
        VK.Result(ply, false, "Нет ключа или доступа")
        return false
    end
    if not veh.VK_OwnerType then
        VK.Result(ply, false, "У машины нет владельца")
        return false
    end
    veh.VK_Locked = not (veh.VK_Locked == true)
    ply:EmitSound(veh.VK_Locked and VK.SND.LOCK or VK.SND.UNLOCK, 65, 100)
    VK.SyncVehicle(veh)
    VK.Result(ply, true, veh.VK_Locked and "Машина заблокирована" or "Машина разблокирована")
    return true
end

net.Receive(NET_TOGGLE_LOCK, function(_, ply)
    if not IsValid(ply) then return end
    ply._vkLockTs = ply._vkLockTs or 0
    if CurTime() < ply._vkLockTs then return end
    ply._vkLockTs = CurTime() + 0.4
    VK.ToggleLock(ply, net.ReadEntity())
end)

function VK.ToggleDoors(veh)
    if not IsValid(veh) then return false end

    local open = not (veh.VK_DoorsOpen == true)
    local invoked = false

    local function invoke(object, method, ...)
        if not isfunction(object[method]) then return false end
        local ok = pcall(object[method], object, ...)
        if ok then invoked = true end
        return ok
    end

    if invoke(veh, "ToggleDoors") then
        veh.VK_DoorsOpen = open
        return true
    end

    if invoke(veh, "SetDoorsOpen", open) then
        veh.VK_DoorsOpen = open
        return true
    end

    if open and invoke(veh, "OpenDoors") then
        veh.VK_DoorsOpen = true
        return true
    end

    if not open and invoke(veh, "CloseDoors") then
        veh.VK_DoorsOpen = false
        return true
    end

    local entityTable = veh.GetTable and veh:GetTable() or nil
    if entityTable and istable(entityTable.Doors) then
        for _, door in pairs(entityTable.Doors) do
            if istable(door) or IsValid(door) then
                if isfunction(door.SetOpen) then
                    local ok = pcall(door.SetOpen, door, open)
                    invoked = invoked or ok
                elseif isfunction(door.Toggle) then
                    local ok = pcall(door.Toggle, door)
                    invoked = invoked or ok
                end
            end
        end

        if invoked then
            veh.VK_DoorsOpen = open
            return true
        end
    end

    -- Last fallback for SENTs supporting Fire inputs. It cannot be verified,
    -- therefore it is only considered successful when vehicle accepted input.
    local ok = pcall(function()
        veh:Fire(open and "OpenDoors" or "CloseDoors", "", 0)
        veh:Fire(open and "Open" or "Close", "", 0)
    end)

    if ok then
        veh.VK_DoorsOpen = open
        return true
    end

    return false
end

-- ============================================================
-- DEALER INTEGRATION / INITIAL CLIENT SYNC
-- ============================================================

hook.Add("VD_OnVehicleSpawned", "VK_RegisterDealerOwner", function(veh, ply)
    if not IsValid(veh) or not VK.IsVehicle(veh) then return end
    if IsValid(ply) then VK.SetPlayerOwner(veh, ply) end
end)

hook.Add("PlayerInitialSpawn", "VK_InitialSync", function(ply)
    timer.Simple(3, function()
        if not IsValid(ply) then return end

        VK.SyncKeyRing(ply)
        VK.UpdateKeySwep(ply)

        for _, ent in ipairs(ents.GetAll()) do
            if VK.IsVehicle(ent) and (ent.VK_OwnerType or ent.VK_Locked ~= nil) then
                VK.SyncVehicle(ent, ply)
            end
        end
    end)
end)

-- Faction membership can be updated by another addon without an event.
timer.Create("VK_RefreshFactionSWEPs", 15, 0, refreshAllKeySWEPS)

-- ============================================================
-- SECURE KEY-MENU NETWORK API
-- ============================================================

net.Receive(NET_REQUEST_LIST, function(_, ply)
    local veh = net.ReadEntity()

    if not canManagePersonalKeys(ply, veh) then
        VK.Result(ply, false, "Нужно смотреть на свою личную машину рядом с вами")
        return
    end

    local players = {}
    for _, target in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
        if target ~= ply then
            players[#players + 1] = {
                steam = playerSteamID(target),
                nick = target:Nick(),
                hasKey = VK.HasOwnerKey(playerSteamID(target), veh.VK_OwnerSteam),
            }
        end
    end

    table.sort(players, function(a, b) return string.lower(a.nick) < string.lower(b.nick) end)

    net.Start(NET_SEND_LIST)
        net.WriteEntity(veh)
        net.WriteTable(players)
    net.Send(ply)
end)

net.Receive(NET_GIVE_KEY, function(_, ply)
    local veh = net.ReadEntity()
    local targetSteam = net.ReadString()

    if not canManagePersonalKeys(ply, veh) then
        VK.Result(ply, false, "Нет прав или машина слишком далеко")
        return
    end

    local target = player.GetBySteamID(targetSteam)
    if not IsValid(target) then
        VK.Result(ply, false, "Игрок должен быть онлайн")
        return
    end

    local ownerName = veh.VK_OwnerNick or veh.VK_OwnerSteam
    local keyID = VK.GetOrCreateOwnerKey(veh.VK_OwnerSteam, "Ключи от машин: " .. ownerName)
    local ok, message = VK.GiveKey(playerSteamID(target), keyID)

    if ok then
        target:EmitSound(VK.SND.KEY_GET, 65, 100)
        VK.SyncKeyRing(target)
        VK.UpdateKeySwep(target)
        VK.Result(target, true, "Вам выдан ключ от машин: " .. ownerName)
    end

    VK.Result(ply, ok or message == "Уже есть", ok and "Ключ выдан" or message)
end)

net.Receive(NET_REVOKE_KEY, function(_, ply)
    local veh = net.ReadEntity()
    local targetSteam = net.ReadString()

    if not canManagePersonalKeys(ply, veh) then
        VK.Result(ply, false, "Нет прав или машина слишком далеко")
        return
    end

    local target = player.GetBySteamID(targetSteam)
    if not IsValid(target) then
        VK.Result(ply, false, "Игрок должен быть онлайн")
        return
    end

    local keyID = ownerKeyID(veh.VK_OwnerSteam)
    if not keyID then
        VK.Result(ply, false, "Ключ ещё не создавался")
        return
    end

    local ok, message = VK.RevokeKey(playerSteamID(target), keyID)
    if ok then
        VK.SyncKeyRing(target)
        VK.UpdateKeySwep(target)
        VK.Result(target, false, "Ваш ключ от машин владельца отозван")
    end

    VK.Result(ply, ok, ok and "Ключ отозван" or message)
end)

-- ============================================================
-- ADMIN / OWNER CONSOLE COMMANDS
-- ============================================================

local function findOnlinePlayer(queryText)
    local query = string.lower(string.Trim(tostring(queryText or "")))
    if query == "" then return nil end

    for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
        if ply:SteamID() == queryText or ply:SteamID64() == queryText or string.lower(ply:Nick()) == query then
            return ply
        end
    end

    return nil
end

concommand.Add("vk_givekey", function(ply, _, args)
    if not IsValid(ply) then return end

    local veh = VK.GetAimedVehicle(ply, 300)
    if not canManagePersonalKeys(ply, veh) then
        ply:ChatPrint("[VK] Посмотрите на свою личную машину рядом с вами")
        return
    end

    local target = findOnlinePlayer(table.concat(args, " "))
    if not IsValid(target) then
        ply:ChatPrint("[VK] Игрок должен быть онлайн; укажите SteamID или точный ник")
        return
    end

    local keyID = VK.GetOrCreateOwnerKey(veh.VK_OwnerSteam, "Ключи от машин: " .. (veh.VK_OwnerNick or veh.VK_OwnerSteam))
    local ok, message = VK.GiveKey(playerSteamID(target), keyID)

    if ok then
        VK.SyncKeyRing(target)
        VK.UpdateKeySwep(target)
        target:EmitSound(VK.SND.KEY_GET, 65, 100)
    end

    ply:ChatPrint("[VK] " .. (ok and ("Ключ выдан: " .. target:Nick()) or tostring(message)))
end)

concommand.Add("vk_revokekey", function(ply, _, args)
    if not IsValid(ply) then return end

    local veh = VK.GetAimedVehicle(ply, 300)
    if not canManagePersonalKeys(ply, veh) then
        ply:ChatPrint("[VK] Посмотрите на свою личную машину рядом с вами")
        return
    end

    local target = findOnlinePlayer(table.concat(args, " "))
    if not IsValid(target) then
        ply:ChatPrint("[VK] Игрок должен быть онлайн; укажите SteamID или точный ник")
        return
    end

    local keyID = ownerKeyID(veh.VK_OwnerSteam)
    if not keyID then
        ply:ChatPrint("[VK] Ключ ещё не создавался")
        return
    end

    local ok, message = VK.RevokeKey(playerSteamID(target), keyID)
    if ok then
        VK.SyncKeyRing(target)
        VK.UpdateKeySwep(target)
    end

    ply:ChatPrint("[VK] " .. (ok and ("Ключ отозван у " .. target:Nick()) or tostring(message)))
end)

concommand.Add("vk_setowner", function(ply, _, args)
    if not IsValid(ply) or not ply:IsSuperAdmin() then
        if IsValid(ply) then ply:ChatPrint("[VK] Только superadmin") end
        return
    end

    local veh = VK.GetAimedVehicle(ply, 300)
    if not IsValid(veh) then
        ply:ChatPrint("[VK] Посмотрите на транспорт")
        return
    end

    local target = findOnlinePlayer(table.concat(args, " "))
    if not IsValid(target) then
        ply:ChatPrint("[VK] Игрок должен быть онлайн; укажите SteamID или точный ник")
        return
    end

    VK.SetPlayerOwner(veh, target)
    ply:ChatPrint("[VK] Владелец назначен: " .. target:Nick())
end)

concommand.Add("vk_setfaction", function(ply, _, args)
    if not IsValid(ply) or not ply:IsSuperAdmin() then
        if IsValid(ply) then ply:ChatPrint("[VK] Только superadmin") end
        return
    end

    local veh = VK.GetAimedVehicle(ply, 300)
    if not IsValid(veh) then
        ply:ChatPrint("[VK] Посмотрите на транспорт")
        return
    end

    local factionName = string.Trim(table.concat(args, " "))
    if factionName == "" or not istable(Factions) or not Factions[factionName] then
        ply:ChatPrint("[VK] Фракция не найдена. Название должно совпадать полностью.")
        return
    end

    VK.SetFactionOwner(veh, factionName)
    ply:ChatPrint("[VK] Машина передана фракции: " .. factionName)
end)

concommand.Add("vk_clearowner", function(ply)
    if not IsValid(ply) or not ply:IsSuperAdmin() then
        if IsValid(ply) then ply:ChatPrint("[VK] Только superadmin") end
        return
    end

    local veh = VK.GetAimedVehicle(ply, 300)
    if not IsValid(veh) then
        ply:ChatPrint("[VK] Посмотрите на транспорт")
        return
    end

    VK.ClearOwner(veh)
    ply:ChatPrint("[VK] Владелец снят; транспорт разблокирован")
end)

print("[VK] Vehicle key server v" .. tostring(VK.VERSION) .. " loaded")
