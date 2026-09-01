--[[--------------------------------------------------------------------
    GRM CCTV — server v1.3.2 (Код 60/Код 89)
    Реестр, доступ, сеть, view + freeze, сейв, screenshot notify.
    Код 89: автосейв персистента при любой правке настроек (дебаунс 1с).
----------------------------------------------------------------------]]

if CLIENT then return end

AddCSLuaFile("autorun/sh_grm_cctv_config.lua")
AddCSLuaFile("autorun/client/cl_grm_cctv.lua")
include("autorun/sh_grm_cctv_config.lua")

GRM = GRM or {}
GRM.CCTV = GRM.CCTV or {}
local CCTV = GRM.CCTV
local CFG = function() return CCTV.Config or {} end

CCTV.Devices = CCTV.Devices or {}

local NET_OPEN_CAM   = "GRM_CCTV_OpenCam"
local NET_OPEN_MON   = "GRM_CCTV_OpenMon"
local NET_OPEN_SRV   = "GRM_CCTV_OpenSrv"
local NET_LIST       = "GRM_CCTV_List"
local NET_ACTION     = "GRM_CCTV_Action"
local NET_VIEW       = "GRM_CCTV_View"
local NET_VIEW_STOP  = "GRM_CCTV_ViewStop"
local NET_NOTIFY     = "GRM_CCTV_Notify"
local NET_SHOT_OK    = "GRM_CCTV_ShotOk"

util.AddNetworkString(NET_OPEN_CAM)
util.AddNetworkString(NET_OPEN_MON)
util.AddNetworkString(NET_OPEN_SRV)
util.AddNetworkString(NET_LIST)
util.AddNetworkString(NET_ACTION)
util.AddNetworkString(NET_VIEW)
util.AddNetworkString(NET_VIEW_STOP)
util.AddNetworkString(NET_NOTIFY)
util.AddNetworkString(NET_SHOT_OK)

local function jsonT(txt)
    local ok, t = pcall(util.JSONToTable, txt, false, true)
    return (ok and istable(t)) and t or nil
end

local function notify(ply, ok, msg)
    if not IsValid(ply) then return end
    net.Start(NET_NOTIFY)
        net.WriteBool(ok and true or false)
        net.WriteString(string.sub(tostring(msg or ""), 1, 220))
    net.Send(ply)
    if GRM and isfunction(GRM.Notify) then
        local r, g, b = ok and 100 or 255, ok and 220 or 120, ok and 100 or 120
        GRM.Notify(ply, msg, r, g, b)
    end
end

local function steam64(ply)
    if not IsValid(ply) then return "" end
    if GRM.Identity and GRM.Identity.CharacterKey then return GRM.Identity.CharacterKey(ply) end
    local id = ply:SteamID64()
    if id and id ~= "0" then return id end
    return ply:SteamID() or ""
end

local function withinUse(ply, ent)
    if not IsValid(ply) or not IsValid(ent) then return false end
    local d = CFG().UseDistance or 140
    return ply:GetPos():DistToSqr(ent:GetPos()) <= (d + 40) * (d + 40)
end

local function classOf(ent)
    return IsValid(ent) and tostring(ent:GetClass() or "") or ""
end

local function isCCTVClass(cls)
    return cls == "grm_cctv_camera" or cls == "grm_cctv_monitor" or cls == "grm_cctv_server"
end

function CCTV.HasAccess(ply)
    if not IsValid(ply) then return false end
    local acc = CFG().Access or {}
    if acc.SuperAdminBypass ~= false and ply:IsSuperAdmin() then return true end
    local sid = steam64(ply)
    if istable(acc.AllowSteam) and (acc.AllowSteam[sid] or acc.AllowSteam[ply:SteamID()]) then
        return true
    end
    if istable(acc.AllowFactions) and Factions then
        local sid1 = ply:SteamID()
        for fname, allowed in pairs(acc.AllowFactions) do
            if allowed then
                local f = Factions[fname]
                if istable(f) and istable(f.Members) and (f.Members[sid1] or f.Members[sid]) then
                    return true
                end
            end
        end
    end
    return false
end

function CCTV.CanView(ply)
    if not IsValid(ply) then return false end
    if (CFG().Access or {}).PublicView then return true end
    return CCTV.HasAccess(ply)
end

function CCTV.CanConfigure(ply, ent)
    if not IsValid(ply) then return false end
    if ply:IsSuperAdmin() then return true end
    if not CCTV.HasAccess(ply) then return false end
    if IsValid(ent) then
        local owner = ent.GetOwnerSteam and ent:GetOwnerSteam() or ""
        if owner ~= "" and (owner == steam64(ply) or owner == ply:SteamID()) then
            return true
        end
    end
    return CCTV.HasAccess(ply)
end

function CCTV.RegisterDevice(ent)
    if not IsValid(ent) then return end
    CCTV.Devices[ent:EntIndex()] = ent
end

function CCTV.UnregisterDevice(ent)
    if not IsValid(ent) then return end
    CCTV.Devices[ent:EntIndex()] = nil
end

function CCTV.RebuildRegistry()
    CCTV.Devices = {}
    for _, cls in ipairs({ "grm_cctv_camera", "grm_cctv_monitor", "grm_cctv_server" }) do
        for _, ent in ipairs(ents.FindByClass(cls)) do
            if IsValid(ent) then CCTV.Devices[ent:EntIndex()] = ent end
        end
    end
end

function CCTV.FindDeviceByID(deviceID, expectedClass)
    deviceID = tostring(deviceID or "")
    if deviceID == "" then return nil end
    for _, ent in pairs(CCTV.Devices) do
        if IsValid(ent) and (not expectedClass or classOf(ent) == expectedClass)
            and tostring(ent:GetDeviceID() or "") == deviceID then return ent end
    end
    -- Самолечение реестра после cleanup/restart/load-order гонки.
    CCTV.RebuildRegistry()
    for _, ent in pairs(CCTV.Devices) do
        if IsValid(ent) and (not expectedClass or classOf(ent) == expectedClass)
            and tostring(ent:GetDeviceID() or "") == deviceID then return ent end
    end
    return nil
end

function CCTV.NetworkHasServer(networkID)
    networkID = CCTV.NormalizeNetwork(networkID)
    for _, ent in pairs(CCTV.Devices) do
        if IsValid(ent) and classOf(ent) == "grm_cctv_server"
            and CCTV.NormalizeNetwork(ent:GetNetworkID()) == networkID
            and ent:GetActive() then
            return true, ent
        end
    end
    return false, nil
end

function CCTV.ListCameras(networkID, onlyActive)
    networkID = CCTV.NormalizeNetwork(networkID)
    local out = {}
    for _, ent in pairs(CCTV.Devices) do
        if IsValid(ent) and classOf(ent) == "grm_cctv_camera"
            and CCTV.NormalizeNetwork(ent:GetNetworkID()) == networkID then
            if (not onlyActive) or ent:GetActive() then
                out[#out + 1] = ent
            end
        end
    end
    table.sort(out, function(a, b)
        return tostring(a:GetLabel()) < tostring(b:GetLabel())
    end)
    return out
end

local function countClass(cls)
    local n = 0
    for _, ent in pairs(CCTV.Devices) do
        if IsValid(ent) and classOf(ent) == cls then n = n + 1 end
    end
    return n
end

local function savePath()
    local dir = CFG().SaveDir or "grm_cctv"
    if not file.IsDir(dir, "DATA") then file.CreateDir(dir) end
    local map = string.lower(game.GetMap() or "unknown")
    map = string.gsub(map, "[^%w%-%_]", "_")
    return dir .. "/" .. map .. ".json"
end

local function vecT(v)
    if isvector and isvector(v) then return { x = v.x, y = v.y, z = v.z } end
    if istable(v) then return { x = tonumber(v.x) or 0, y = tonumber(v.y) or 0, z = tonumber(v.z) or 0 } end
    return { x = 0, y = 0, z = 0 }
end

local function angT(a)
    if isangle and isangle(a) then return { p = a.p, y = a.y, r = a.r } end
    if istable(a) then return { p = tonumber(a.p) or 0, y = tonumber(a.y) or 0, r = tonumber(a.r) or 0 } end
    return { p = 0, y = 0, r = 0 }
end

function CCTV.SavePermanent()
    local list = {}
    for _, ent in pairs(CCTV.Devices) do
        if IsValid(ent) and isCCTVClass(classOf(ent)) and ent:GetPermanent() then
            list[#list + 1] = {
                class = classOf(ent),
                model = ent:GetModel() or "",
                pos = vecT(ent:GetPos()),
                ang = angT(ent:GetAngles()),
                device_id = ent:GetDeviceID(),
                label = ent:GetLabel(),
                network = ent:GetNetworkID(),
                owner_steam = ent:GetOwnerSteam(),
                owner_name = ent:GetOwnerName(),
                active = (not ent.GetActive) or ent:GetActive() == true,
                fov = (ent.GetCamFOV and ent:GetCamFOV()) or (CFG().DefaultFOV or 75),
            }
        end
    end
    local path = savePath()
    local ok, txt = pcall(util.TableToJSON, list, true)
    if not ok or not isstring(txt) then
        print("[GRM CCTV] SAVE fail: serialize")
        return false
    end
    file.Write(path, txt)
    local chk = file.Read(path, "DATA")
    if chk ~= txt then
        print("[GRM CCTV] SAVE fail: read-back " .. path)
        return false
    end
    print(("[GRM CCTV] SAVE ok: %d -> data/%s"):format(#list, path))
    return true
end

function CCTV.LoadPermanent()
    local path = savePath()
    if not file.Exists(path, "DATA") then return 0 end
    local raw = file.Read(path, "DATA") or ""
    local t = jsonT(raw)
    if not istable(t) then
        local q = (CFG().SaveDir or "grm_cctv") .. "/corrupt_" .. os.time() .. ".txt"
        file.Write(q, raw)
        print("[GRM CCTV] LOAD: quarantine data/" .. q)
        return 0
    end
    CCTV.RebuildRegistry()
    local spawned, healed, claimed = 0, 0, {}
    for _, rec in ipairs(t) do
        if istable(rec) and isstring(rec.class) and isCCTVClass(rec.class) then
            local pos = Vector(tonumber(rec.pos and rec.pos.x) or 0, tonumber(rec.pos and rec.pos.y) or 0, tonumber(rec.pos and rec.pos.z) or 0)
            local savedID = isstring(rec.device_id) and rec.device_id or ""
            local ent = savedID ~= "" and CCTV.FindDeviceByID(savedID, rec.class) or nil
            if IsValid(ent) and claimed[ent] then ent = nil end
            if not IsValid(ent) then
                for _, nearby in ipairs(ents.FindInSphere(pos, 8)) do
                    if IsValid(nearby) and not claimed[nearby] and classOf(nearby) == rec.class then ent = nearby break end
                end
            end
            local created = false
            if not IsValid(ent) then
                ent = ents.Create(rec.class)
                if IsValid(ent) then ent:SetPos(pos);ent:SetAngles(Angle(tonumber(rec.ang and rec.ang.p) or 0,tonumber(rec.ang and rec.ang.y) or 0,tonumber(rec.ang and rec.ang.r) or 0));ent:Spawn();ent:Activate();created=true end
            end
            if IsValid(ent) then
                claimed[ent] = true
                ent:SetPos(pos)
                ent:SetAngles(Angle(tonumber(rec.ang and rec.ang.p) or 0, tonumber(rec.ang and rec.ang.y) or 0, tonumber(rec.ang and rec.ang.r) or 0))
                if isstring(rec.model) and rec.model ~= "" then ent:SetModel(rec.model) end
                if savedID ~= "" then ent:SetDeviceID(savedID) end
                if isstring(rec.label) then ent:SetLabel(rec.label) end
                if isstring(rec.network) then ent:SetNetworkID(CCTV.NormalizeNetwork(rec.network)) end
                if isstring(rec.owner_steam) then ent:SetOwnerSteam(rec.owner_steam) end
                if isstring(rec.owner_name) then ent:SetOwnerName(rec.owner_name) end
                if ent.SetActive then ent:SetActive(rec.active ~= false) end
                if ent.SetCamFOV then ent:SetCamFOV(CCTV.ClampFOV(rec.fov)) end
                ent:SetPermanent(true)
                CCTV.RegisterDevice(ent)
                if GRM.PropProtect and GRM.PropProtect.MarkServerEntity then GRM.PropProtect.MarkServerEntity(ent) end
                local phys = ent:GetPhysicsObject()
                if IsValid(phys) then phys:EnableMotion(false) end
                if created then spawned=spawned+1 else healed=healed+1 end
            end
        end
    end
    CCTV.RebuildRegistry()
    print(("[GRM CCTV] LOAD: created=%d healed=%d from data/%s"):format(spawned, healed, path))
    return spawned + healed
end

function CCTV.StopView(ply, silent)
    if not IsValid(ply) then return end
    if not ply._grmCCTVView then
        if ply._grmCCTVFrozen then
            ply:Freeze(false)
            ply._grmCCTVFrozen = nil
        end
        ply:SetViewEntity(nil)
        return
    end
    ply:SetViewEntity(nil)
    if ply._grmCCTVFrozen or (CFG().FreezePlayer ~= false) then
        ply:Freeze(false)
        ply._grmCCTVFrozen = nil
    end
    ply._grmCCTVView = nil
    ply._grmCCTVCam = nil
    ply._grmCCTVMonitor = nil
    if not silent then
        net.Start(NET_VIEW_STOP)
        net.Send(ply)
    end
end

function CCTV.StartView(ply, cam, monitor, netID)
    if not IsValid(ply) or not IsValid(cam) or not IsValid(monitor) then return false end
    if ply._grmCCTVView then CCTV.StopView(ply, true) end

    ply:SetViewEntity(cam)
    ply._grmCCTVView = true
    ply._grmCCTVCam = cam
    ply._grmCCTVMonitor = monitor
    if CFG().FreezePlayer ~= false then
        ply:Freeze(true)
        ply._grmCCTVFrozen = true
        if ply.SetLocalVelocity then ply:SetLocalVelocity(Vector(0, 0, 0)) end
        if ply.SetVelocity then ply:SetVelocity(Vector(0, 0, 0)) end
    end

    local cfg = CFG()
    local sc = cfg.Screenshots or {}
    net.Start(NET_VIEW)
        net.WriteEntity(cam)
        net.WriteEntity(monitor)
        net.WriteString(string.sub(cam:GetLabel() or "Камера", 1, 48))
        net.WriteString(netID)
        net.WriteUInt(CCTV.ClampFOV(cam:GetCamFOV()), 8)
        net.WriteBool(cfg.AllowPan ~= false)
        net.WriteUInt(math.Clamp(tonumber(cfg.PanYawMax) or 55, 0, 180), 8)
        net.WriteUInt(math.Clamp(tonumber(cfg.PanPitchMax) or 35, 0, 89), 8)
        net.WriteFloat(tonumber(cfg.PanSensitivity) or 0.06)
        -- zoom
        net.WriteBool(cfg.AllowZoom ~= false)
        net.WriteUInt(math.Clamp(tonumber(cfg.ZoomStep) or 4, 1, 30), 8)
        net.WriteUInt(math.Clamp(tonumber(cfg.ZoomMinFOV) or 25, 10, 90), 8)
        net.WriteUInt(math.Clamp(tonumber(cfg.ZoomMaxFOV) or 100, 40, 150), 8)
        -- screenshots
        net.WriteBool(sc.Enabled ~= false)
        net.WriteString(string.sub(tostring(sc.Dir or "grm_cctv/screenshots"), 1, 120))
        net.WriteString(string.sub(tostring(sc.Format or "jpeg"), 1, 8))
        net.WriteUInt(math.Clamp(tonumber(sc.Quality) or 90, 10, 100), 8)
        net.WriteBool(sc.HideUI ~= false)
        net.WriteFloat(tonumber(sc.Cooldown) or 1.0)
        net.WriteString(string.sub(string.lower(game.GetMap() or "map"), 1, 40))
        net.WriteString(string.sub(cam:GetDeviceID() or "cam", 1, 40))
        -- PVS-safe fallback: удалённая камера может ещё быть NULL на клиенте.
        net.WriteVector(cam:GetPos())
        net.WriteAngle(cam:GetAngles())
    net.Send(ply)
    return true
end

function CCTV.OpenCameraMenu(ply, ent)
    if not IsValid(ply) or not IsValid(ent) then return end
    if not withinUse(ply, ent) then return end
    if not CCTV.CanConfigure(ply, ent) then
        notify(ply, false, "Нет доступа к настройке камеры.")
        return
    end
    net.Start(NET_OPEN_CAM)
        net.WriteEntity(ent)
    net.Send(ply)
end

function CCTV.OpenServerMenu(ply, ent)
    if not IsValid(ply) or not IsValid(ent) then return end
    if not withinUse(ply, ent) then return end
    if not CCTV.CanConfigure(ply, ent) then
        notify(ply, false, "Нет доступа к серверной стойке.")
        return
    end
    net.Start(NET_OPEN_SRV)
        net.WriteEntity(ent)
    net.Send(ply)
end

function CCTV.OpenMonitorMenu(ply, ent)
    if not IsValid(ply) or not IsValid(ent) then return end
    if not withinUse(ply, ent) then return end
    if not CCTV.CanView(ply) then
        notify(ply, false, "Нет доступа к системе видеонаблюдения.")
        return
    end
    local netID = CCTV.NormalizeNetwork(ent:GetNetworkID())
    local hasSrv = CCTV.NetworkHasServer(netID)
    local cams = CCTV.ListCameras(netID, false)
    net.Start(NET_OPEN_MON)
        net.WriteEntity(ent)
        net.WriteString(netID)
        net.WriteBool(hasSrv)
        net.WriteBool(CCTV.CanConfigure(ply, ent))
        net.WriteUInt(math.min(#cams, 255), 8)
        for i = 1, math.min(#cams, 255) do
            local c = cams[i]
            net.WriteEntity(c)
            net.WriteString(string.sub(c:GetLabel() or "Камера", 1, 48))
            net.WriteString(string.sub(c:GetDeviceID() or "", 1, 40))
            net.WriteBool(c:GetActive())
            net.WriteUInt(CCTV.ClampFOV(c:GetCamFOV()), 8)
        end
    net.Send(ply)
end

local function sendList(ply, monitor)
    if not IsValid(ply) or not IsValid(monitor) then return end
    local netID = CCTV.NormalizeNetwork(monitor:GetNetworkID())
    local hasSrv = CCTV.NetworkHasServer(netID)
    local cams = CCTV.ListCameras(netID, false)
    net.Start(NET_LIST)
        net.WriteEntity(monitor)
        net.WriteString(netID)
        net.WriteBool(hasSrv)
        net.WriteUInt(math.min(#cams, 255), 8)
        for i = 1, math.min(#cams, 255) do
            local c = cams[i]
            net.WriteEntity(c)
            net.WriteString(string.sub(c:GetLabel() or "Камера", 1, 48))
            net.WriteString(string.sub(c:GetDeviceID() or "", 1, 40))
            net.WriteBool(c:GetActive())
            net.WriteUInt(CCTV.ClampFOV(c:GetCamFOV()), 8)
        end
    net.Send(ply)
end

local VALID_ACTIONS = {
    set_label = true, set_network = true, set_active = true, set_fov = true,
    set_permanent = true, refresh_list = true, save_all = true,
    view_cam = true, stop_view = true, screenshot = true,
}

-- Код 89: любая правка настроек автоматически тонет в персистент
-- (дебаунс 1с — серия кликов не дёргает диск подряд).
local function saveSoon()
    timer.Create("GRM_CCTV_SaveSoon", 1, 1, function() CCTV.SavePermanent() end)
end

net.Receive(NET_ACTION, function(_, ply)
    if not IsValid(ply) then return end
    local action = net.ReadString() or ""
    local ent = net.ReadEntity()
    if not VALID_ACTIONS[action] then return end

    if action == "refresh_list" then
        if IsValid(ent) and classOf(ent) == "grm_cctv_monitor" and withinUse(ply, ent) and CCTV.CanView(ply) then
            sendList(ply, ent)
        end
        return
    end

    if action == "save_all" then
        if not ply:IsSuperAdmin() then
            notify(ply, false, "Сохранение — только суперадмин.")
            return
        end
        local ok = CCTV.SavePermanent()
        notify(ply, ok, ok and "CCTV: permanent сохранены." or "CCTV: ошибка сохранения.")
        return
    end

    if action == "stop_view" then
        CCTV.StopView(ply)
        return
    end

    if action == "screenshot" then
        -- Клиент уже сохранил файл в data/; сервер логирует и подтверждает.
        if not ply._grmCCTVView then return end
        local relPath = string.sub(net.ReadString() or "", 1, 200)
        local camLabel = string.sub(net.ReadString() or "", 1, 48)
        if relPath == "" then
            notify(ply, false, "Скриншот: пустой путь.")
            return
        end
        print(("[GRM CCTV] SCREENSHOT %s (%s) cam=%s -> data/%s"):format(
            ply:Nick(), steam64(ply), camLabel, relPath))
        notify(ply, true, "Скриншот: garrysmod/data/" .. relPath)
        net.Start(NET_SHOT_OK)
            net.WriteString(relPath)
        net.Send(ply)
        return
    end

    if action == "view_cam" then
        local cam = net.ReadEntity()
        local camID = net.BytesLeft and net.BytesLeft() > 0 and string.sub(net.ReadString() or "", 1, 40) or ""
        local monitor = ent
        if not IsValid(monitor) or classOf(monitor) ~= "grm_cctv_monitor" then return end
        if camID ~= "" then cam = CCTV.FindDeviceByID(camID, "grm_cctv_camera") end
        if not withinUse(ply, monitor) then return end
        if not CCTV.CanView(ply) then
            notify(ply, false, "Нет доступа.")
            return
        end
        if not IsValid(cam) or classOf(cam) ~= "grm_cctv_camera" then
            notify(ply, false, "Камера недоступна.")
            return
        end
        local netID = CCTV.NormalizeNetwork(monitor:GetNetworkID())
        if CCTV.NormalizeNetwork(cam:GetNetworkID()) ~= netID then
            notify(ply, false, "Камера в другой сети.")
            return
        end
        if not cam:GetActive() then
            notify(ply, false, "Камера выключена.")
            return
        end
        if not CCTV.NetworkHasServer(netID) then
            notify(ply, false, "Нет ONLINE-сервера сети «" .. netID .. "».")
            return
        end
        local now = CurTime()
        if (ply._grmCCTVCD or 0) > now then return end
        ply._grmCCTVCD = now + (CFG().SwitchCooldown or 0.15)
        CCTV.StartView(ply, cam, monitor, netID)
        return
    end

    if not IsValid(ent) or not isCCTVClass(classOf(ent)) then return end
    if not withinUse(ply, ent) then return end
    if not CCTV.CanConfigure(ply, ent) then
        notify(ply, false, "Нет прав на настройку.")
        return
    end

    if action == "set_label" then
        local label = string.sub(string.Trim(net.ReadString() or ""), 1, CFG().MaxLabelLen or 48)
        if label == "" then label = "Устройство" end
        ent:SetLabel(label)
        saveSoon() -- Код 89
        notify(ply, true, "Подпись: " .. label)
    elseif action == "set_network" then
        local nw = CCTV.NormalizeNetwork(net.ReadString())
        ent:SetNetworkID(nw)
        saveSoon() -- Код 89
        notify(ply, true, "Сеть: " .. nw)
    elseif action == "set_active" then
        if not ent.SetActive then return end
        local on = net.ReadBool()
        ent:SetActive(on)
        saveSoon() -- Код 89
        notify(ply, true, on and "Включено." or "Выключено.")
    elseif action == "set_fov" then
        if not ent.SetCamFOV then return end
        local fov = CCTV.ClampFOV(net.ReadUInt(8))
        ent:SetCamFOV(fov)
        saveSoon() -- Код 89
        notify(ply, true, "FOV: " .. tostring(fov))
    elseif action == "set_permanent" then
        if not ply:IsSuperAdmin() then
            notify(ply, false, "Permanent — только суперадмин.")
            return
        end
        local on = net.ReadBool()
        ent:SetPermanent(on)
        if on and ent:GetOwnerSteam() == "" then
            ent:SetOwnerSteam(steam64(ply))
            ent:SetOwnerName(ply:Nick())
        end
        CCTV.SavePermanent()
        notify(ply, true, on and "В permanent-сейве." or "Снято с permanent.")
    end
end)

-- Remote cameras may be outside the player's normal PVS. Explicit visibility origin
-- keeps props, NPCs and map details networked around the camera instead of a cut-down view.
hook.Add("SetupPlayerVisibility", "GRM_CCTV_RemoteCameraPVS", function(ply)
    if IsValid(ply) and ply._grmCCTVView and IsValid(ply._grmCCTVCam) then AddOriginToPVS(ply._grmCCTVCam:GetPos()) end
end)

hook.Add("Think", "GRM_CCTV_ViewGuard", function()
    local now=CurTime();if(CCTV._viewGuardAt or 0)>now then return end;CCTV._viewGuardAt=now+.2
    -- Кэш списка игроков вместо новой таблицы player.GetAll() 5 раз в секунду.
    for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
        if ply._grmCCTVView then
            local mon, cam = ply._grmCCTVMonitor, ply._grmCCTVCam
            local bad = not ply:Alive()
            if not IsValid(mon) or not IsValid(cam) then bad = true end
            if not bad and not withinUse(ply, mon) then bad = true end
            if not bad and not cam:GetActive() then bad = true end
            if not bad and not CCTV.NetworkHasServer(cam:GetNetworkID()) then bad = true end
            if bad then CCTV.StopView(ply) end
        end
    end
end)

hook.Add("PlayerDisconnected", "GRM_CCTV_Disconnect", function(ply)
    if IsValid(ply) then CCTV.StopView(ply, true) end
end)

hook.Add("PlayerDeath", "GRM_CCTV_Death", function(ply)
    if IsValid(ply) then CCTV.StopView(ply) end
end)

hook.Add("PlayerSilentDeath", "GRM_CCTV_SilentDeath", function(ply)
    if IsValid(ply) then CCTV.StopView(ply) end
end)

hook.Add("StartCommand", "GRM_CCTV_Lock", function(ply, cmd)
    if not IsValid(ply) or not ply._grmCCTVView then return end
    cmd:ClearMovement()
    cmd:ClearButtons()
    cmd:SetButtons(0)
    cmd:SetForwardMove(0)
    cmd:SetSideMove(0)
    cmd:SetUpMove(0)
end)

hook.Add("SetupMove", "GRM_CCTV_SetupMove", function(ply, mv, cmd)
    if not IsValid(ply) or not ply._grmCCTVView then return end
    mv:SetForwardSpeed(0)
    mv:SetSideSpeed(0)
    mv:SetUpSpeed(0)
    mv:SetVelocity(Vector(0, 0, 0))
end)

hook.Add("PlayerSpawnedSENT", "GRM_CCTV_Spawned", function(ply, ent)
    if not IsValid(ent) or not isCCTVClass(classOf(ent)) then return end
    if IsValid(ply) then
        ent:SetOwnerSteam(steam64(ply))
        ent:SetOwnerName(ply:Nick())
    end
    CCTV.RegisterDevice(ent)
end)

if GRM.Boot and GRM.Boot.Task then
    GRM.Boot.Task("cctv.map", "normal", function() CCTV.LoadPermanent() end, { label = "CCTV: камеры карты" })
else
hook.Add("InitPostEntity", "GRM_CCTV_Load", function()
    timer.Simple(2, function() CCTV.LoadPermanent() end)
end)
end

hook.Add("PostCleanupMap", "GRM_CCTV_Reload", function()
    timer.Simple(1, function() CCTV.LoadPermanent() end)
end)

hook.Add("ShutDown", "GRM_CCTV_ShutdownSave", function()
    CCTV.SavePermanent()
end)

concommand.Add("grm_cctv_save", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    local ok = CCTV.SavePermanent()
    if IsValid(ply) then notify(ply, ok, ok and "CCTV saved." or "CCTV save failed.") end
end)

concommand.Add("grm_cctv_load", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    local n = CCTV.LoadPermanent()
    if IsValid(ply) then notify(ply, true, "CCTV load: " .. tostring(n)) end
end)

concommand.Add("grm_cctv_list", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    local nCam, nMon, nSrv = 0, 0, 0
    for _, ent in pairs(CCTV.Devices) do
        if IsValid(ent) then
            local c = classOf(ent)
            if c == "grm_cctv_camera" then nCam = nCam + 1
            elseif c == "grm_cctv_monitor" then nMon = nMon + 1
            elseif c == "grm_cctv_server" then nSrv = nSrv + 1 end
        end
    end
    local msg = ("CCTV: cams=%d mon=%d srv=%d"):format(nCam, nMon, nSrv)
    print("[GRM CCTV] " .. msg)
    if IsValid(ply) then ply:ChatPrint(msg) end
end)

print("[GRM CCTV] server v1.3.2 — full remote PVS, DeviceID reconnect, clean live-view (Код 89)")
