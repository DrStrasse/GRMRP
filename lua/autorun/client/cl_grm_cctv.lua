--[[--------------------------------------------------------------------
    GRM CCTV — client v1.3.2
    UI, live view, pan, zoom, freeze local input, screenshots, help HUD.
----------------------------------------------------------------------]]

if not CLIENT then return end

include("autorun/sh_grm_cctv_config.lua")

GRM = GRM or {}
GRM.CCTV = GRM.CCTV or {}
local CCTV = GRM.CCTV

local NET_OPEN_CAM   = "GRM_CCTV_OpenCam"
local NET_OPEN_MON   = "GRM_CCTV_OpenMon"
local NET_OPEN_SRV   = "GRM_CCTV_OpenSrv"
local NET_LIST       = "GRM_CCTV_List"
local NET_ACTION     = "GRM_CCTV_Action"
local NET_VIEW       = "GRM_CCTV_View"
local NET_VIEW_STOP  = "GRM_CCTV_ViewStop"
local NET_NOTIFY     = "GRM_CCTV_Notify"
local NET_SHOT_OK    = "GRM_CCTV_ShotOk"

-- HUD камеры. Форвард-декларация: функция определена ниже, а зовут её и
-- съёмка скриншота, и обычная отрисовка — обе выше по файлу. Раньше имя
-- было глобальным и утекало в общее пространство имён клиента.
local drawCCTVChrome

local ViewState = {
    active = false,
    cam = NULL,
    camID = "",
    basePos = Vector(0, 0, 0),
    monitor = NULL,
    label = "",
    network = "",
    baseFov = 75,
    fov = 75,
    allowPan = true,
    yawMax = 55,
    pitchMax = 35,
    sens = 0.06,
    yawOff = 0,
    pitchOff = 0,
    baseAng = Angle(0, 0, 0),
    allowZoom = true,
    zoomStep = 4,
    zoomMin = 25,
    zoomMax = 100,
    shotEnabled = true,
    shotDir = "grm_cctv/screenshots",
    shotFormat = "jpeg",
    shotQuality = 90,
    shotHideUI = true,
    shotCooldown = 1.0,
    shotMap = "map",
    shotCamId = "cam",
    hideOverlay = false,
    lastShot = 0,
    flashUntil = 0,
    lastShotPath = "",
    pendingShot = false,
    shotRT = nil,
    shotRTW = 0,
    shotRTH = 0,
}

local function sendAction(action, ent, writeExtra)
    net.Start(NET_ACTION)
        net.WriteString(action)
        net.WriteEntity(IsValid(ent) and ent or NULL)
        if writeExtra then writeExtra() end
    net.SendToServer()
end

local function styleFrame(frame, title)
    frame:SetTitle(title or "GRM CCTV")
    frame:SetSize(math.min(ScrW() * 0.5, 560), math.min(ScrH() * 0.6, 480))
    frame:Center()
    frame:MakePopup()
end

local function addLabeledEntry(parent, y, label, default, numeric)
    local lbl = vgui.Create("DLabel", parent)
    lbl:SetPos(15, y)
    lbl:SetSize(120, 20)
    lbl:SetText(label)
    lbl:SetTextColor(Color(220, 220, 220))
    local entry
    if numeric then
        entry = vgui.Create("DNumberWang", parent)
        entry:SetPos(140, y)
        entry:SetSize(180, 22)
        entry:SetMin(10)
        entry:SetMax(150)
        entry:SetValue(tonumber(default) or 75)
    else
        entry = vgui.Create("DTextEntry", parent)
        entry:SetPos(140, y)
        entry:SetSize(280, 22)
        entry:SetValue(tostring(default or ""))
    end
    return entry
end

local function addBtn(parent, x, y, w, h, text, col, fn)
    local b = vgui.Create("DButton", parent)
    b:SetPos(x, y)
    b:SetSize(w, h)
    b:SetText(text)
    if col then b:SetTextColor(col) end
    b.DoClick = fn
    return b
end

local function safePart(s)
    s = string.lower(tostring(s or "x"))
    s = string.gsub(s, "[^%w%-%_]", "_")
    if s == "" then s = "x" end
    return string.sub(s, 1, 40)
end

local function ensureShotDirs(relFile)
    -- relFile like grm_cctv/screenshots/main/cam/file.jpg
    local parts = string.Explode("/", relFile)
    local acc = ""
    for i = 1, #parts - 1 do
        acc = (acc == "") and parts[i] or (acc .. "/" .. parts[i])
        if not file.IsDir(acc, "DATA") then
            file.CreateDir(acc)
        end
    end
end

net.Receive(NET_NOTIFY, function()
    local ok = net.ReadBool()
    local msg = net.ReadString() or ""
    if GRM and isfunction(GRM.Notify) then
        GRM.Notify(LocalPlayer(), msg, ok and 100 or 255, ok and 220 or 120, ok and 100 or 120)
    else
        chat.AddText(ok and Color(100, 220, 100) or Color(255, 120, 120), "[CCTV] ", color_white, msg)
    end
end)

net.Receive(NET_SHOT_OK, function()
    local path = net.ReadString() or ""
    ViewState.lastShotPath = path
    ViewState.flashUntil = CurTime() + 0.35
end)

-- ── config menus (camera / server / monitor) ───────────────
net.Receive(NET_OPEN_CAM, function()
    local ent = net.ReadEntity()
    if not IsValid(ent) then return end
    if IsValid(CCTV._camFrame) then CCTV._camFrame:Remove() end
    local f = vgui.Create("DFrame")
    CCTV._camFrame = f
    styleFrame(f, "Камера — " .. (ent:GetLabel() or ""))
    f:SetSize(460, 280)
    local label = addLabeledEntry(f, 40, "Подпись", ent:GetLabel())
    local network = addLabeledEntry(f, 70, "Сеть", ent:GetNetworkID())
    local fov = addLabeledEntry(f, 100, "FOV", ent:GetCamFOV(), true)
    local active = vgui.Create("DCheckBoxLabel", f)
    active:SetPos(15, 140)
    active:SetText("Камера включена (ONLINE)")
    active:SetValue(ent:GetActive())
    active:SizeToContents()
    local perm = vgui.Create("DCheckBoxLabel", f)
    perm:SetPos(15, 165)
    perm:SetText("Permanent (суперадмин, переживает рестарт)")
    perm:SetValue(ent:GetPermanent())
    perm:SizeToContents()
    local idlbl = vgui.Create("DLabel", f)
    idlbl:SetPos(15, 195)
    idlbl:SetSize(420, 18)
    idlbl:SetText("ID: " .. tostring(ent:GetDeviceID() or ""))
    idlbl:SetTextColor(Color(150, 150, 150))
    addBtn(f, 15, 230, 120, 28, "Сохранить", Color(100, 220, 120), function()
        sendAction("set_label", ent, function() net.WriteString(label:GetValue()) end)
        sendAction("set_network", ent, function() net.WriteString(network:GetValue()) end)
        sendAction("set_fov", ent, function() net.WriteUInt(math.Clamp(tonumber(fov:GetValue()) or 75, 10, 150), 8) end)
        sendAction("set_active", ent, function() net.WriteBool(active:GetChecked()) end)
        sendAction("set_permanent", ent, function() net.WriteBool(perm:GetChecked()) end)
        f:Close()
    end)
    addBtn(f, 150, 230, 100, 28, "Отмена", nil, function() f:Close() end)
end)

net.Receive(NET_OPEN_SRV, function()
    local ent = net.ReadEntity()
    if not IsValid(ent) then return end
    if IsValid(CCTV._srvFrame) then CCTV._srvFrame:Remove() end
    local f = vgui.Create("DFrame")
    CCTV._srvFrame = f
    styleFrame(f, "Сервер CCTV — " .. (ent:GetLabel() or ""))
    f:SetSize(460, 250)
    local label = addLabeledEntry(f, 40, "Подпись", ent:GetLabel())
    local network = addLabeledEntry(f, 70, "Сеть", ent:GetNetworkID())
    local active = vgui.Create("DCheckBoxLabel", f)
    active:SetPos(15, 110)
    active:SetText("Стойка ONLINE (без неё камеры сети не видны)")
    active:SetValue(ent:GetActive())
    active:SizeToContents()
    local perm = vgui.Create("DCheckBoxLabel", f)
    perm:SetPos(15, 140)
    perm:SetText("Permanent (суперадмин)")
    perm:SetValue(ent:GetPermanent())
    perm:SizeToContents()
    addBtn(f, 15, 205, 120, 28, "Сохранить", Color(100, 220, 120), function()
        sendAction("set_label", ent, function() net.WriteString(label:GetValue()) end)
        sendAction("set_network", ent, function() net.WriteString(network:GetValue()) end)
        sendAction("set_active", ent, function() net.WriteBool(active:GetChecked()) end)
        sendAction("set_permanent", ent, function() net.WriteBool(perm:GetChecked()) end)
        f:Close()
    end)
    addBtn(f, 150, 205, 100, 28, "Отмена", nil, function() f:Close() end)
end)

local function buildMonitorUI(monitor, netID, hasSrv, canCfg, cams)
    if IsValid(CCTV._monFrame) then CCTV._monFrame:Remove() end
    local f = vgui.Create("DFrame")
    CCTV._monFrame = f
    f:SetTitle("Видеонаблюдение — сеть «" .. tostring(netID) .. "»")
    f:SetSize(math.min(ScrW() * 0.55, 640), math.min(ScrH() * 0.7, 520))
    f:Center()
    f:MakePopup()

    local status = vgui.Create("DLabel", f)
    status:SetPos(15, 32)
    status:SetSize(f:GetWide() - 30, 22)
    if hasSrv then
        status:SetText("Сервер сети: ONLINE · камер: " .. tostring(#cams))
        status:SetTextColor(Color(100, 220, 120))
    else
        status:SetText("Сервер сети: OFFLINE — просмотр недоступен")
        status:SetTextColor(Color(255, 140, 100))
    end

    local list = vgui.Create("DListView", f)
    list:SetPos(15, 60)
    list:SetSize(f:GetWide() - 30, f:GetTall() - 160)
    list:AddColumn("№"):SetFixedWidth(36)
    list:AddColumn("Камера")
    list:AddColumn("Статус"):SetFixedWidth(80)
    list:AddColumn("FOV"):SetFixedWidth(50)
    list:AddColumn("ID"):SetFixedWidth(120)
    list:SetMultiSelect(false)
    for i, cam in ipairs(cams) do
        local line = list:AddLine(tostring(i), cam.label or "Камера", cam.active and "ONLINE" or "OFF",
            tostring(cam.fov or 75), string.sub(cam.id or "", 1, 16))
        line._camEnt = cam.ent
        line._camID = tostring(cam.id or "")
        line._active = cam.active
    end

    local function selectedCam()
        -- GetSelectedLine/GetLine стабилен и при одиночном выборе. GetSelected()
        -- в разных версиях Derma возвращает разные формы таблицы.
        local index = list:GetSelectedLine()
        local line = index and list:GetLine(index) or nil
        if not IsValid(line) then return nil, "", false end
        return line._camEnt, tostring(line._camID or ""), line._active == true
    end

    local function requestView(cam, camID)
        sendAction("view_cam", monitor, function()
            net.WriteEntity(IsValid(cam) and cam or NULL)
            net.WriteString(tostring(camID or ""))
        end)
    end

    addBtn(f, 15, f:GetTall() - 85, 140, 30, "Смотреть", Color(100, 200, 255), function()
        if not hasSrv then
            chat.AddText(Color(255, 140, 100), "[CCTV] ", color_white, "Нет ONLINE-сервера сети.")
            return
        end
        local cam, camID, active = selectedCam()
        if camID == "" then
            chat.AddText(Color(255, 200, 100), "[CCTV] ", color_white, "Выбери камеру.")
            return
        end
        if not active then
            chat.AddText(Color(255, 140, 100), "[CCTV] ", color_white, "Камера выключена.")
            return
        end
        -- Камера может быть вне PVS и потому быть NULL на клиенте. Сервер находит
        -- её по постоянному DeviceID и остаётся единственным авторитетом.
        requestView(cam, camID)
        f:Close()
    end)
    addBtn(f, 165, f:GetTall() - 85, 110, 30, "Обновить", nil, function()
        sendAction("refresh_list", monitor)
    end)
    if canCfg then
        local label = addLabeledEntry(f, f:GetTall() - 50, "Сеть монитора", netID)
        label:SetPos(15, f:GetTall() - 48)
        label:SetSize(200, 22)
        addBtn(f, 230, f:GetTall() - 50, 120, 26, "Сменить сеть", Color(220, 200, 100), function()
            sendAction("set_network", monitor, function() net.WriteString(label:GetValue()) end)
            timer.Simple(0.2, function()
                if IsValid(monitor) then sendAction("refresh_list", monitor) end
            end)
        end)
        addBtn(f, 360, f:GetTall() - 50, 100, 26, "Permanent", nil, function()
            sendAction("set_permanent", monitor, function() net.WriteBool(true) end)
        end)
    end
    addBtn(f, f:GetWide() - 115, f:GetTall() - 85, 100, 30, "Закрыть", nil, function() f:Close() end)
    list.DoDoubleClick = function()
        if not hasSrv then return end
        local cam, camID, active = selectedCam()
        if camID ~= "" and active then
            requestView(cam, camID)
            f:Close()
        end
    end
end

local function readCamList(n)
    local cams = {}
    for i = 1, n do
        local ent = net.ReadEntity()
        local label = net.ReadString()
        local id = net.ReadString()
        local active = net.ReadBool()
        local fov = net.ReadUInt(8)
        cams[#cams + 1] = { ent = ent, label = label, id = id, active = active, fov = fov }
    end
    return cams
end

net.Receive(NET_OPEN_MON, function()
    local mon = net.ReadEntity()
    local netID = net.ReadString()
    local hasSrv = net.ReadBool()
    local canCfg = net.ReadBool()
    local n = net.ReadUInt(8)
    local cams = readCamList(n)
    if IsValid(mon) then buildMonitorUI(mon, netID, hasSrv, canCfg, cams) end
end)

net.Receive(NET_LIST, function()
    local mon = net.ReadEntity()
    local netID = net.ReadString()
    local hasSrv = net.ReadBool()
    local n = net.ReadUInt(8)
    local cams = readCamList(n)
    if IsValid(mon) then buildMonitorUI(mon, netID, hasSrv, true, cams) end
end)

-- ── live view ──────────────────────────────────────────────
local function resetPan()
    ViewState.yawOff = 0
    ViewState.pitchOff = 0
    if IsValid(ViewState.cam) then
        ViewState.baseAng = ViewState.cam:GetAngles()
        ViewState.basePos = ViewState.cam:GetPos()
    elseif not ViewState.baseAng then
        ViewState.baseAng = Angle(0, 0, 0)
    end
end

function CCTV.IsViewing()
    return ViewState.active == true
end

-- HUDPaint не подчиняется cl_drawhud/HUDShouldDraw. Поэтому на время просмотра
-- снимаем все сторонние HUDPaint hooks и точно возвращаем их при любом выходе.
local suppressedHUDPaint = {}
local function suppressOtherHUDPaint()
    local hooks = hook.GetTable and hook.GetTable().HUDPaint or nil
    if not hooks then return end
    local remove = {}
    for id, fn in pairs(hooks) do
        if id ~= "GRM_CCTV_Overlay" then
            if suppressedHUDPaint[id] == nil then suppressedHUDPaint[id] = fn end
            remove[#remove + 1] = id
        end
    end
    for _, id in ipairs(remove) do hook.Remove("HUDPaint", id) end
end

local function restoreOtherHUDPaint()
    for id, fn in pairs(suppressedHUDPaint) do
        local hooks = hook.GetTable and hook.GetTable().HUDPaint or {}
        if hooks[id] == nil then hook.Add("HUDPaint", id, fn) end
    end
    suppressedHUDPaint = {}
end

local function restoreGameHUD()
    restoreOtherHUDPaint()
    if ViewState._hudHidden then
        LocalPlayer():ConCommand(ViewState._drawHUDWasEnabled == false and "cl_drawhud 0" or "cl_drawhud 1")
        ViewState._drawHUDWasEnabled = nil
        ViewState._hudHidden = false
    end
end

local function hideGameHUD()
    if not ViewState._hudHidden then
        local cvar = GetConVar and GetConVar("cl_drawhud") or nil
        ViewState._drawHUDWasEnabled = not cvar or cvar:GetBool()
        LocalPlayer():ConCommand("cl_drawhud 0")
        ViewState._hudHidden = true
    end
    suppressOtherHUDPaint()
end

local function stopView()
    if not ViewState.active then return end
    sendAction("stop_view", ViewState.monitor)
    ViewState.active = false
    ViewState.cam = NULL
    ViewState.camID = ""
    ViewState.monitor = NULL
    ViewState.yawOff = 0
    ViewState.pitchOff = 0
    ViewState.hideOverlay = false
    restoreGameHUD()
    gui.EnableScreenClicker(false)
end

local function clampZoom(fov)
    return math.Clamp(tonumber(fov) or 75, ViewState.zoomMin or 25, ViewState.zoomMax or 100)
end

local function applyZoomDelta(dir)
    if not ViewState.active or not ViewState.allowZoom then return end
    -- dir > 0 = zoom in (меньший FOV), dir < 0 = zoom out
    local step = ViewState.zoomStep or 4
    ViewState.fov = clampZoom((ViewState.fov or 75) - dir * step)
end

-- Снимок через RenderView в RT: обычный render.Capture экрана при SetViewEntity
-- часто даёт ЧЁРНЫЙ кадр (буфер viewentity не тот). Рендерим вид камеры сами.
local function getShotView()
    local cam = ViewState.cam
    local base = ViewState.baseAng or (IsValid(cam) and cam:GetAngles())
    local cameraPos = IsValid(cam) and cam:GetPos() or ViewState.basePos
    if not base or not cameraPos then return nil end
    local viewAng = Angle(base.p, base.y, base.r)
    viewAng:RotateAroundAxis(viewAng:Up(), ViewState.yawOff or 0)
    viewAng:RotateAroundAxis(viewAng:Right(), ViewState.pitchOff or 0)
    local origin = cameraPos + viewAng:Forward() * 6 + viewAng:Up() * 2
    return origin, viewAng, ViewState.fov or (IsValid(cam) and cam:GetCamFOV()) or 75
end

local function getShotRT(w, h)
    w = math.floor(math.Clamp(w or ScrW(), 320, 1920))
    h = math.floor(math.Clamp(h or ScrH(), 240, 1080))
    if not ViewState.shotRT or ViewState.shotRTW ~= w or ViewState.shotRTH ~= h then
        ViewState.shotRT = GetRenderTargetEx(
            "GRM_CCTV_ShotRT_" .. w .. "x" .. h,
            w, h,
            RT_SIZE_NO_CHANGE,
            MATERIAL_RT_DEPTH_SEPARATE,
            0, 0,
            IMAGE_FORMAT_RGB888
        )
        ViewState.shotRTW = w
        ViewState.shotRTH = h
    end
    return ViewState.shotRT, w, h
end

local function finishScreenshot(data, rel)
    ViewState.hideOverlay = false
    ViewState.pendingShot = false
    if not data or data == "" then
        chat.AddText(Color(255, 120, 120), "[CCTV] ", color_white, "Скриншот пустой (чёрный/ошибка захвата).")
        return
    end
    -- грубая проверка «всё чёрное»: слишком маленький jpeg/png почти всегда брак
    if #data < 800 then
        chat.AddText(Color(255, 160, 80), "[CCTV] ", color_white, "Снимок подозрительно мал — возможно, чёрный кадр. Попробуйте ещё раз.")
    end
    ensureShotDirs(rel)
    file.Write(rel, data)
    ViewState.lastShotPath = rel
    ViewState.flashUntil = CurTime() + 0.45
    sendAction("screenshot", ViewState.monitor, function()
        net.WriteString(rel)
        net.WriteString(ViewState.label or "")
    end)
    chat.AddText(Color(100, 220, 140), "[CCTV] ", color_white, "Скриншот: ", Color(180, 220, 255), "garrysmod/data/" .. rel)
end

local function takeScreenshot()
    if not ViewState.active or not ViewState.shotEnabled then return end
    if ViewState.pendingShot then return end
    local now = CurTime()
    if now < (ViewState.lastShot or 0) + (ViewState.shotCooldown or 1) then
        chat.AddText(Color(255, 200, 100), "[CCTV] ", color_white, "Подождите перед следующим снимком.")
        return
    end
    if not getShotView() then return end

    ViewState.lastShot = now
    ViewState.pendingShot = true
    -- HUD камеры РИСУЕТСЯ на снимок (drawCCTVChrome в RT). hideOverlay не трогаем.
end

-- Захват в PostRender: RenderView (мир) + 2D HUD камеры в тот же RT, затем Capture.
-- Так на скрин попадают REC / имя / правая колонка подсказок (не только «голый» 3D).
hook.Add("PostRender", "GRM_CCTV_CaptureShot", function()
    if not ViewState.pendingShot then return end
    if not ViewState.active then
        ViewState.pendingShot = false
        ViewState.hideOverlay = false
        return
    end

    local origin, angles, fov = getShotView()
    if not origin then
        ViewState.pendingShot = false
        ViewState.hideOverlay = false
        chat.AddText(Color(255, 120, 120), "[CCTV] ", color_white, "Нет вида камеры для снимка.")
        return
    end

    local fmt = string.lower(ViewState.shotFormat or "jpeg")
    if fmt ~= "png" then fmt = "jpeg" end
    local ext = (fmt == "png") and "png" or "jpg"
    local stamp = os.date("%Y%m%d_%H%M%S")
    local netPart = safePart(ViewState.network)
    local camPart = safePart(ViewState.shotCamId)
    local mapPart = safePart(ViewState.shotMap)
    local dir = tostring(ViewState.shotDir or "grm_cctv/screenshots")
    dir = string.gsub(dir, "^/+", "")
    dir = string.gsub(dir, "%.%.", "")
    local rel = string.format("%s/%s/%s/%s_%s_%s_%s.%s",
        dir, netPart, camPart, mapPart, netPart, camPart, stamp, ext)

    -- Полный размер экрана — HUD 1:1 как в игре
    local capW, capH = ScrW(), ScrH()
    capW = math.Clamp(capW, 640, 1920)
    capH = math.Clamp(capH, 360, 1080)

    local rt, w, h = getShotRT(capW, capH)
    local data
    local ok, err = pcall(function()
        local oldW, oldH = ScrW(), ScrH()
        render.PushRenderTarget(rt)
        render.Clear(0, 0, 0, 255, true, true)
        render.SetViewPort(0, 0, w, h)

        render.RenderView({
            origin = origin,
            angles = angles,
            x = 0, y = 0,
            w = w, h = h,
            fov = fov,
            aspectratio = w / math.max(h, 1),
            drawhud = false,
            drawviewmodel = false,
            drawmonitors = true,
            dopostprocess = false,
            bloomtone = false,
        })

        -- 2D: тот же HUD камеры, что на экране
        cam.Start2D()
        if isfunction(drawCCTVChrome) then
            drawCCTVChrome(w, h, true) -- true = screenshot mode (без flash)
        end
        cam.End2D()

        render.CapturePixels()
        data = render.Capture({
            format = fmt,
            quality = math.Clamp(tonumber(ViewState.shotQuality) or 90, 10, 100),
            x = 0, y = 0,
            w = w, h = h,
            alpha = false,
        })

        render.SetViewPort(0, 0, oldW, oldH)
        render.PopRenderTarget()
    end)

    if not ok then
        ViewState.pendingShot = false
        ViewState.hideOverlay = false
        chat.AddText(Color(255, 120, 120), "[CCTV] ", color_white, "Ошибка снимка: " .. tostring(err))
        pcall(function() render.PopRenderTarget() end)
        pcall(function() cam.End2D() end)
        return
    end

    finishScreenshot(data, rel)
end)

net.Receive(NET_VIEW, function()
    local cam = net.ReadEntity()
    local mon = net.ReadEntity()
    local label = net.ReadString()
    local network = net.ReadString()
    local fov = net.ReadUInt(8)
    local allowPan = net.ReadBool()
    local yawMax = net.ReadUInt(8)
    local pitchMax = net.ReadUInt(8)
    local sens = net.ReadFloat()
    local allowZoom = net.ReadBool()
    local zoomStep = net.ReadUInt(8)
    local zoomMin = net.ReadUInt(8)
    local zoomMax = net.ReadUInt(8)
    local shotEnabled = net.ReadBool()
    local shotDir = net.ReadString()
    local shotFormat = net.ReadString()
    local shotQuality = net.ReadUInt(8)
    local shotHideUI = net.ReadBool()
    local shotCooldown = net.ReadFloat()
    local shotMap = net.ReadString()
    local shotCamId = net.ReadString()
    local basePos = net.ReadVector()
    local baseAng = net.ReadAngle()

    ViewState.active = true
    ViewState.cam = cam
    ViewState.camID = shotCamId
    ViewState.basePos = basePos
    ViewState.baseAng = baseAng
    ViewState.monitor = mon
    ViewState.label = label
    ViewState.network = network
    ViewState.baseFov = fov
    ViewState.fov = fov
    ViewState.allowPan = allowPan
    ViewState.yawMax = yawMax
    ViewState.pitchMax = pitchMax
    ViewState.sens = (sens and sens > 0) and sens or 0.06
    ViewState.allowZoom = allowZoom
    ViewState.zoomStep = zoomStep
    ViewState.zoomMin = zoomMin
    ViewState.zoomMax = zoomMax
    ViewState.shotEnabled = shotEnabled
    ViewState.shotDir = shotDir
    ViewState.shotFormat = shotFormat
    ViewState.shotQuality = shotQuality
    ViewState.shotHideUI = shotHideUI
    ViewState.shotCooldown = shotCooldown
    ViewState.shotMap = shotMap
    ViewState.shotCamId = shotCamId
    ViewState.hideOverlay = false
    resetPan()
    hideGameHUD()

    if IsValid(CCTV._monFrame) then CCTV._monFrame:Close() end
    gui.EnableScreenClicker(false)
end)

net.Receive(NET_VIEW_STOP, function()
    ViewState.active = false
    ViewState.cam = NULL
    ViewState.camID = ""
    ViewState.monitor = NULL
    ViewState.yawOff = 0
    ViewState.pitchOff = 0
    ViewState.hideOverlay = false
    restoreGameHUD()
    gui.EnableScreenClicker(false)
end)

hook.Add("InputMouseApply", "GRM_CCTV_MousePan", function(cmd, x, y, ang)
    if not ViewState.active or not ViewState.allowPan then return end
    local sens = ViewState.sens or 0.06
    ViewState.yawOff = math.Clamp((ViewState.yawOff or 0) - x * sens, -(ViewState.yawMax or 55), (ViewState.yawMax or 55))
    ViewState.pitchOff = math.Clamp((ViewState.pitchOff or 0) + y * sens, -(ViewState.pitchMax or 35), (ViewState.pitchMax or 35))
    cmd:SetMouseX(0)
    cmd:SetMouseY(0)
    return true
end)

-- Колёсико: приблизить / отдалить
hook.Add("PlayerBindPress", "GRM_CCTV_ZoomBinds", function(ply, bind, pressed)
    if not ViewState.active or ply ~= LocalPlayer() then return end
    bind = string.lower(tostring(bind or ""))
    if not pressed then
        if string.find(bind, "invnext", 1, true) or string.find(bind, "invprev", 1, true) then
            return true -- block weapon switch even on release
        end
        return
    end
    if string.find(bind, "invnext", 1, true) then
        applyZoomDelta(-1) -- scroll down = out
        return true
    end
    if string.find(bind, "invprev", 1, true) then
        applyZoomDelta(1) -- scroll up = in
        return true
    end
end)

hook.Add("CalcView", "GRM_CCTV_CalcView", function(ply, pos, ang, fov)
    if not ViewState.active then return end
    local origin, viewAng, cameraFov = getShotView()
    if not origin then return end
    return {
        origin = origin,
        angles = viewAng,
        fov = cameraFov,
        znear = 2,
        zfar = 32768,
        drawviewer = false,
    }
end)

hook.Add("CreateMove", "GRM_CCTV_CreateMove", function(cmd)
    if not ViewState.active then return end
    cmd:ClearMovement()
    cmd:SetButtons(0)
    cmd:SetForwardMove(0)
    cmd:SetSideMove(0)
    cmd:SetUpMove(0)
end)

-- Прячем ванильный HUD + типичные элементы, чтобы не наслаивались на CCTV.
local HIDE_VANILLA = {
    CHudHealth = true, CHudBattery = true, CHudAmmo = true, CHudSecondaryAmmo = true,
    CHudWeaponSelection = true, CHudCrosshair = true, CHudDamageIndicator = true,
    CHudGeiger = true, CHudZoom = true, CHudSuitPower = true, CHudPoisonDamageIndicator = true,
    CHudSquadStatus = true, CHudTrain = true, CHudMessage = true, CHudMenu = true,
    CHudChat = false, -- чат оставляем
}
hook.Add("HUDShouldDraw", "GRM_CCTV_HideHUD", function(name)
    if not ViewState.active then return end
    if HIDE_VANILLA[name] then return false end
end)

-- Подхватываем даже HUD hooks, которые другой аддон зарегистрировал уже после входа.
hook.Add("Think", "GRM_CCTV_SuppressOtherHUD", function()
    if ViewState.active and(not GRM.Perf or GRM.Perf.Throttle("cctv.hudhooks",.5))then suppressOtherHUDPaint()end
end)

surface.CreateFont("GRM_CCTV_Title", { font = "Roboto", size = 22, weight = 700, extended = true })
surface.CreateFont("GRM_CCTV_Meta", { font = "Roboto", size = 16, weight = 500, extended = true })
surface.CreateFont("GRM_CCTV_Help", { font = "Roboto", size = 16, weight = 600, extended = true })
surface.CreateFont("GRM_CCTV_HelpTitle", { font = "Roboto", size = 17, weight = 800, extended = true })
surface.CreateFont("GRM_CCTV_Key", { font = "Roboto", size = 14, weight = 700, extended = true })

local function drawKeyChip(x, y, keyText, desc, alpha)
    alpha = alpha or 230
    surface.SetFont("GRM_CCTV_Key")
    local kw, kh = surface.GetTextSize(keyText)
    local padX, padY = 6, 3
    local boxW, boxH = kw + padX * 2, kh + padY * 2
    surface.SetDrawColor(15, 22, 18, alpha)
    surface.DrawRect(x, y, boxW, boxH)
    surface.SetDrawColor(90, 220, 130, alpha)
    surface.DrawOutlinedRect(x, y, boxW, boxH, 1)
    draw.SimpleText(keyText, "GRM_CCTV_Key", x + boxW * 0.5, y + boxH * 0.5,
        Color(200, 255, 210, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    if desc and desc ~= "" then
        draw.SimpleText(desc, "GRM_CCTV_Help", x + boxW + 8, y + boxH * 0.5,
            Color(225, 232, 225, alpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    return boxH + 4
end

-- Единый HUD камеры: и на экране, и на скриншоте (рисуется в RT).
-- w,h — размер поверхности; forShot — без «вспышки» после F.
drawCCTVChrome = function(w, h, forShot)
    w = w or ScrW()
    h = h or ScrH()

    -- верхняя планка
    surface.SetDrawColor(0, 0, 0, 200)
    surface.DrawRect(0, 0, w, 50)

    -- Scanlines: ровная сетка на всю высоту кадра (не «сжатая» полоса 50..120)
    -- Правую колонку управления не заливаем линиями — там UI.
    do
        local sideW = math.Clamp(math.floor(w * 0.26), 280, 360)
        local viewRight = w - sideW - 14
        surface.SetDrawColor(0, 255, 120, 7)
        for y = 50, h - 1, 3 do
            surface.DrawRect(0, y, math.max(1, viewRight), 1)
        end
    end

    local blink = (math.floor(CurTime() * 2) % 2 == 0)
    if blink then
        surface.SetDrawColor(220, 40, 40, 230)
        draw.NoTexture()
        surface.DrawRect(14, 16, 11, 11)
    end
    draw.SimpleText("REC  LIVE", "GRM_CCTV_Meta", 32, 14, Color(255, 80, 80), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

    draw.SimpleText(ViewState.label ~= "" and ViewState.label or "Камера",
        "GRM_CCTV_Title", w * 0.5, 6, Color(220, 255, 220), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

    local zoomPct = 0
    do
        local zmin, zmax = ViewState.zoomMin or 25, ViewState.zoomMax or 100
        local f = ViewState.fov or 75
        if zmax > zmin then
            zoomPct = math.floor((1 - (f - zmin) / (zmax - zmin)) * 100 + 0.5)
        end
    end
    draw.SimpleText(
        string.format("сеть: %s  ·  FOV %d  ·  зум %d%%",
            tostring(ViewState.network or "?"), tonumber(ViewState.fov) or 75, zoomPct),
        "GRM_CCTV_Meta", w * 0.5, 30, Color(160, 200, 160), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

    draw.SimpleText(os.date("%Y-%m-%d %H:%M:%S"), "GRM_CCTV_Meta", w - 12, 14,
        Color(200, 200, 200), TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)

    -- прицел
    local cx, cy = w * 0.5, h * 0.5
    surface.SetDrawColor(80, 255, 120, 140)
    surface.DrawLine(cx - 9, cy, cx + 9, cy)
    surface.DrawLine(cx, cy - 9, cx, cy + 9)

    if not forShot and CurTime() < (ViewState.flashUntil or 0) then
        surface.SetDrawColor(255, 255, 255, 55)
        surface.DrawRect(0, 0, w, h)
    end

    -- правая колонка
    local panelW = math.Clamp(math.floor(w * 0.26), 280, 360)
    local panelX = w - panelW - 12
    local panelY = 60
    local panelH = h - panelY - 12

    surface.SetDrawColor(8, 12, 10, 210)
    surface.DrawRect(panelX, panelY, panelW, panelH)
    surface.SetDrawColor(70, 180, 110, 180)
    surface.DrawOutlinedRect(panelX, panelY, panelW, panelH, 1)
    surface.SetDrawColor(90, 220, 130, 220)
    surface.DrawRect(panelX, panelY, 3, panelH)

    local pad = 12
    local x = panelX + pad
    local y = panelY + 10
    local innerW = panelW - pad * 2

    draw.SimpleText("УПРАВЛЕНИЕ", "GRM_CCTV_HelpTitle", x, y, Color(120, 230, 150))
    y = y + 22
    surface.SetDrawColor(70, 160, 100, 100)
    surface.DrawRect(x, y, innerW, 1)
    y = y + 10

    draw.SimpleText("Обзор", "GRM_CCTV_Help", x, y, Color(180, 210, 180))
    y = y + 18
    if ViewState.allowPan then
        y = y + drawKeyChip(x, y, "МЫШЬ ← →", "влево / вправо")
        y = y + drawKeyChip(x, y, "МЫШЬ ↑ ↓", "вверх / вниз")
        draw.SimpleText(string.format("углы %+.0f° / %+.0f°", ViewState.yawOff or 0, ViewState.pitchOff or 0),
            "GRM_CCTV_Meta", x, y, Color(140, 175, 140))
        y = y + 18
    else
        draw.SimpleText("поворот выключен", "GRM_CCTV_Meta", x, y, Color(200, 180, 120))
        y = y + 18
    end

    y = y + 4
    surface.SetDrawColor(70, 160, 100, 70)
    surface.DrawRect(x, y, innerW, 1)
    y = y + 10

    draw.SimpleText("Зум", "GRM_CCTV_Help", x, y, Color(180, 210, 180))
    y = y + 18
    if ViewState.allowZoom then
        y = y + drawKeyChip(x, y, "КОЛЁСИКО ↑", "приблизить")
        y = y + drawKeyChip(x, y, "КОЛЁСИКО ↓", "отдалить")
        y = y + drawKeyChip(x, y, "+ / =", "приблизить")
        y = y + drawKeyChip(x, y, "-", "отдалить")
        draw.SimpleText(string.format("FOV %d  ( %d … %d )  зум %d%%",
            tonumber(ViewState.fov) or 75, ViewState.zoomMin or 25, ViewState.zoomMax or 100, zoomPct),
            "GRM_CCTV_Meta", x, y, Color(140, 175, 140))
        y = y + 18
    else
        draw.SimpleText("зум выключен", "GRM_CCTV_Meta", x, y, Color(200, 180, 120))
        y = y + 18
    end

    y = y + 4
    surface.SetDrawColor(70, 160, 100, 70)
    surface.DrawRect(x, y, innerW, 1)
    y = y + 10

    draw.SimpleText("Снимок", "GRM_CCTV_Help", x, y, Color(180, 210, 180))
    y = y + 18
    if ViewState.shotEnabled then
        y = y + drawKeyChip(x, y, "F", "скриншот")
        y = y + drawKeyChip(x, y, "ПРОБЕЛ", "скриншот")
    else
        draw.SimpleText("скриншоты выкл.", "GRM_CCTV_Meta", x, y, Color(200, 180, 120))
        y = y + 18
    end

    y = y + 4
    surface.SetDrawColor(70, 160, 100, 70)
    surface.DrawRect(x, y, innerW, 1)
    y = y + 10

    draw.SimpleText("Выход из камеры", "GRM_CCTV_Help", x, y, Color(180, 210, 180))
    y = y + 18
    y = y + drawKeyChip(x, y, "ПКМ", "выйти")
    y = y + drawKeyChip(x, y, "ESC", "выйти")
    y = y + drawKeyChip(x, y, "E", "выйти")
    draw.SimpleText("ещё: Backspace · Q · !camexit", "GRM_CCTV_Meta", x, y, Color(140, 160, 140))
    y = y + 20

    local pathHint
    if ViewState.lastShotPath ~= "" then
        pathHint = "снимок: data/" .. ViewState.lastShotPath
    else
        pathHint = "папка: data/" .. tostring(ViewState.shotDir or "grm_cctv/screenshots")
    end
    if #pathHint > 48 then
        pathHint = "…" .. string.sub(pathHint, -46)
    end
    draw.SimpleText(pathHint, "GRM_CCTV_Meta", x, panelY + panelH - 28, Color(130, 150, 130))
    draw.SimpleText("тело у монитора стоит", "GRM_CCTV_Meta", x, panelY + panelH - 14, Color(120, 140, 120))
end

hook.Add("HUDPaint", "GRM_CCTV_Overlay", function()
    if not ViewState.active then return end
    if ViewState.hideOverlay then return end
    drawCCTVChrome(ScrW(), ScrH(), false)
end)

-- keys: exit / zoom / screenshot
local function onExitButton(btn)
    if not ViewState.active then return end
    if btn == MOUSE_RIGHT or btn == KEY_ESCAPE or btn == KEY_E
        or btn == KEY_BACKSPACE or btn == KEY_Q then
        stopView()
        return true
    end
    -- zoom keys
    if ViewState.allowZoom then
        if btn == KEY_EQUAL or btn == KEY_PAD_PLUS then
            applyZoomDelta(1)
            return true
        end
        if btn == KEY_MINUS or btn == KEY_PAD_MINUS then
            applyZoomDelta(-1)
            return true
        end
    end
    -- screenshot (Space used for shot; not exit)
    if ViewState.shotEnabled and (btn == KEY_F or btn == KEY_SPACE) then
        takeScreenshot()
        return true
    end
end

hook.Add("PlayerButtonDown", "GRM_CCTV_Keys", function(ply, btn)
    if ply ~= LocalPlayer() then return end
    onExitButton(btn)
end)

hook.Add("KeyPress", "GRM_CCTV_KeyPress", function(ply, key)
    if ply ~= LocalPlayer() or not ViewState.active then return end
    if key == IN_USE or key == IN_ATTACK2 then
        stopView()
    elseif key == IN_JUMP and ViewState.shotEnabled then
        -- Space also fires KeyPress JUMP — screenshot already via PlayerButtonDown
    end
end)

hook.Add("Think", "GRM_CCTV_ExitThink", function()
    if not ViewState.active then return end
    if input.IsKeyDown(KEY_ESCAPE) or input.IsMouseDown(MOUSE_RIGHT) then
        local now = CurTime()
        if (ViewState._exitCD or 0) > now then return end
        ViewState._exitCD = now + 0.25
        stopView()
    end
end)

hook.Add("Think", "GRM_CCTV_CamValid", function()
    if not ViewState.active then return end
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then stopView() return end
    if IsValid(ViewState.cam) then
        ViewState.basePos = ViewState.cam:GetPos()
    elseif tostring(ViewState.camID or "") == "" then
        stopView()
    end
end)

hook.Add("PlayerDeath", "GRM_CCTV_ClientDeathExit", function(ply)
    if ViewState.active and ply == LocalPlayer() then stopView() end
end)

concommand.Add("grm_cctv_stop", function() stopView() end)
concommand.Add("grm_cctv_shot", function() takeScreenshot() end)

hook.Add("OnPlayerChat", "GRM_CCTV_ChatExit", function(ply, text)
    if ply ~= LocalPlayer() or not ViewState.active then return end
    local t = string.Trim(string.lower(tostring(text or "")))
    if t == "!camexit" or t == "/camexit" or t == "!cctvexit" then
        stopView()
        return true
    end
    if t == "!camshot" or t == "/camshot" then
        takeScreenshot()
        return true
    end
end)

print("[GRM CCTV] client v1.2.4")
