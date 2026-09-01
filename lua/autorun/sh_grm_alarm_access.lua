--[[--------------------------------------------------------------------
    GRM Alarm Access (Код 63)
    /alarm_access + вкладка «Сигнализация» в /factions
    data/grm_alarm/access.json
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Alarm = GRM.Alarm or {}
GRM.Alarm.AccessManager = GRM.Alarm.AccessManager or {}
local AM = GRM.Alarm.AccessManager

local NET_REQ = "GRM_AlarmAccess_Request"
local NET_DATA = "GRM_AlarmAccess_Data"
local NET_SAVE = "GRM_AlarmAccess_Save"
local NET_RESULT = "GRM_AlarmAccess_Result"

local ACCESS_DIR = "grm_alarm"
local ACCESS_FILE = ACCESS_DIR .. "/access.json"

AM.Config = AM.Config or { SuperAdminBypass = true }

local function jsonT(txt)
    local ok, t = pcall(util.JSONToTable, txt, false, true)
    return (ok and istable(t)) and t or nil
end

local function normalize(data)
    data = istable(data) and data or {}
    data.ViewFactions = istable(data.ViewFactions) and data.ViewFactions or {}
    data.ControlFactions = istable(data.ControlFactions) and data.ControlFactions or {}
    data.ViewRoles = istable(data.ViewRoles) and data.ViewRoles or {}
    data.ControlRoles = istable(data.ControlRoles) and data.ControlRoles or {}
    data.ViewDepartments = istable(data.ViewDepartments) and data.ViewDepartments or {}
    data.ControlDepartments = istable(data.ControlDepartments) and data.ControlDepartments or {}
    data.ViewSteam = istable(data.ViewSteam) and data.ViewSteam or {}
    data.ControlSteam = istable(data.ControlSteam) and data.ControlSteam or {}
    return data
end

local function getFactionInfo(ply)
    if not IsValid(ply) or not istable(Factions) then return nil, nil, nil end
    local sid, sid64 = ply:SteamID(), ply:SteamID64()
    local charKey = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply)) or sid64
    for name, f in pairs(Factions) do
        if istable(f) and istable(f.Members) then
            local m = GRM.Identity.FactionMember(f, ply)
            if istable(m) then return name, m.Role, m.Department end
        end
    end
    return nil, nil, nil
end

local function nested(t, fac, key)
    return istable(t) and key and istable(t[fac]) and t[fac][key] == true
end

if SERVER then
    util.AddNetworkString(NET_REQ)
    util.AddNetworkString(NET_DATA)
    util.AddNetworkString(NET_SAVE)
    util.AddNetworkString(NET_RESULT)

    local function ensureDir()
        if not file.IsDir(ACCESS_DIR, "DATA") then file.CreateDir(ACCESS_DIR) end
    end

    function AM.Load()
        ensureDir()
        if not file.Exists(ACCESS_FILE, "DATA") then AM.Data = normalize({}) return AM.Data end
        local data = jsonT(file.Read(ACCESS_FILE, "DATA") or "")
        AM.Data = normalize(data or {})
        return AM.Data
    end

    function AM.Save(data)
        ensureDir()
        AM.Data = normalize(data or AM.Data)
        local ok, txt = pcall(util.TableToJSON, AM.Data, true)
        if ok and isstring(txt) then file.Write(ACCESS_FILE, txt) return true end
        return false
    end

    AM.Load()

    local function buildFactions()
        local out = {}
        for n, f in pairs(Factions or {}) do
            if istable(f) then
                out[n] = { Roles = istable(f.Roles) and f.Roles or {}, Departments = istable(f.Departments) and f.Departments or {} }
            end
        end
        return out
    end

    local function sendData(ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        net.Start(NET_DATA)
            net.WriteTable(buildFactions())
            net.WriteTable(AM.Data or normalize({}))
        net.Send(ply)
    end

    net.Receive(NET_REQ, function(_, ply) sendData(ply) end)
    net.Receive(NET_SAVE, function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        AM.Save(net.ReadTable() or {})
        net.Start(NET_RESULT) net.WriteBool(true) net.WriteString("Доступ к сигнализации сохранён.") net.Send(ply)
        sendData(ply)
    end)

    local function check(ply, mode)
        if not IsValid(ply) then return false end
        if ply:IsSuperAdmin() then return true end
        local data = normalize(AM.Data or AM.Load())
        local sid, sid64 = ply:SteamID(), ply:SteamID64()
        local charKey = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply)) or sid64
        local steamT = mode == "control" and data.ControlSteam or data.ViewSteam
        if steamT[charKey] or steamT[sid64] or steamT[sid] then return true end
        if mode == "view" and (data.ControlSteam[charKey] or data.ControlSteam[sid64] or data.ControlSteam[sid]) then return true end

        local fac, role, dept = getFactionInfo(ply)
        if not fac then return false end
        if mode == "control" then
            if data.ControlFactions[fac] then return true end
            if nested(data.ControlRoles, fac, role) then return true end
            if nested(data.ControlDepartments, fac, dept) then return true end
            return false
        end
        if data.ViewFactions[fac] or data.ControlFactions[fac] then return true end
        if nested(data.ViewRoles, fac, role) or nested(data.ControlRoles, fac, role) then return true end
        if nested(data.ViewDepartments, fac, dept) or nested(data.ControlDepartments, fac, dept) then return true end
        return false
    end

    function AM.CanView(ply) return check(ply, "view") end
    function AM.CanControl(ply) return check(ply, "control") end

    function AM.Install()
        if not GRM.Alarm then return end
        GRM.Alarm.CanView = function(ply)
            if not IsValid(ply) then return false end
            if ply:IsSuperAdmin() then return true end
            return AM.CanView(ply)
        end
        GRM.Alarm.CanControl = function(ply)
            if not IsValid(ply) then return false end
            if ply:IsSuperAdmin() then return true end
            return AM.CanControl(ply)
        end
    end
    AM.Install()
    timer.Simple(0, AM.Install)
    timer.Simple(1, AM.Install)
    timer.Simple(3, AM.Install)
    timer.Simple(6, AM.Install)

    concommand.Add("grm_alarm_access", function(ply)
        if IsValid(ply) and ply:IsSuperAdmin() then sendData(ply) end
    end)
    hook.Add("PlayerSay", "GRM_AlarmAccess_Chat", function(ply, text)
        local msg = string.lower(string.Trim(text or ""))
        if msg == "/alarm_access" or msg == "!alarm_access" then
            if not ply:IsSuperAdmin() then return "" end
            sendData(ply)
            return ""
        end
    end)
    print("[GRM Alarm] Access Manager loaded")
end

if CLIENT then
    surface.CreateFont("GRMAlarmAcc_Title", { font = "Roboto", size = 18, weight = 700, extended = true })
    surface.CreateFont("GRMAlarmAcc_Normal", { font = "Roboto", size = 14, weight = 500, extended = true })

    local THEME = {
        bg = Color(22, 24, 30, 250), panel = Color(32, 36, 46, 245),
        text = Color(230, 235, 240), dim = Color(150, 160, 175),
        green = Color(70, 180, 110), accent = Color(70, 140, 220),
    }

    local function sortedKeys(t)
        local k = {}
        for key in pairs(t or {}) do k[#k + 1] = key end
        table.sort(k, function(a, b) return tostring(a) < tostring(b) end)
        return k
    end

    local function mkBtn(parent, text, col)
        local b = vgui.Create("DButton", parent)
        b:SetText(text) b:SetFont("GRMAlarmAcc_Normal") b:SetTextColor(color_white)
        b.Paint = function(self, w, h)
            local c = col or THEME.accent
            if self:IsHovered() then c = Color(math.min(255, c.r + 20), math.min(255, c.g + 20), math.min(255, c.b + 20)) end
            draw.RoundedBox(6, 0, 0, w, h, c)
        end
        return b
    end

    local function openMenu(factions, data)
        data = normalize(data)
        if IsValid(AM._frame) then AM._frame:Remove() end
        local frame = vgui.Create("DFrame")
        AM._frame = frame
        frame:SetTitle("")
        frame:SetSize(900, 660)
        frame:Center()
        frame:MakePopup()
        frame.Paint = function(_, w, h)
            draw.RoundedBox(8, 0, 0, w, h, THEME.bg)
            draw.SimpleText("Доступ к сигнализации / охране", "GRMAlarmAcc_Title", 14, 18, THEME.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end

        local tabs = vgui.Create("DPropertySheet", frame)
        tabs:Dock(FILL)
        tabs:DockMargin(8, 40, 8, 52)

        local function facTab(title, field)
            local panel = vgui.Create("DScrollPanel")
            for _, fname in ipairs(sortedKeys(factions)) do
                local row = vgui.Create("DPanel", panel)
                row:Dock(TOP) row:SetTall(32) row:DockMargin(6, 2, 6, 2)
                row.Paint = function(_, w, h) draw.RoundedBox(5, 0, 0, w, h, THEME.panel) end
                local chk = vgui.Create("DCheckBoxLabel", row)
                chk:Dock(FILL) chk:DockMargin(10, 0, 0, 0)
                chk:SetText(fname) chk:SetTextColor(THEME.text)
                chk:SetValue(data[field][fname] and 1 or 0)
                chk.OnChange = function(_, v) if v then data[field][fname] = true else data[field][fname] = nil end end
            end
            tabs:AddSheet(title, panel, "icon16/group.png")
        end
        facTab("Смотреть: фракции", "ViewFactions")
        facTab("Управление: фракции", "ControlFactions")

        local function nestTab(title, field, src)
            local panel = vgui.Create("DPanel")
            panel:SetPaintBackground(false)
            local combo = vgui.Create("DComboBox", panel)
            combo:Dock(TOP) combo:SetTall(28) combo:DockMargin(8, 8, 8, 4)
            combo:SetValue("Фракция…")
            local scroll = vgui.Create("DScrollPanel", panel)
            scroll:Dock(FILL) scroll:DockMargin(8, 4, 8, 8)
            local function rebuild(fname)
                scroll:Clear()
                local f = factions[fname]
                if not f then return end
                for _, key in ipairs(f[src] or {}) do
                    local row = vgui.Create("DPanel", scroll)
                    row:Dock(TOP) row:SetTall(30) row:DockMargin(0, 0, 0, 2)
                    row.Paint = function(_, w, h) draw.RoundedBox(5, 0, 0, w, h, THEME.panel) end
                    data[field][fname] = istable(data[field][fname]) and data[field][fname] or {}
                    local chk = vgui.Create("DCheckBoxLabel", row)
                    chk:Dock(FILL) chk:DockMargin(8, 0, 0, 0)
                    chk:SetText(tostring(key)) chk:SetTextColor(THEME.text)
                    chk:SetValue(data[field][fname][key] and 1 or 0)
                    chk.OnChange = function(_, v)
                        data[field][fname] = data[field][fname] or {}
                        if v then data[field][fname][key] = true else data[field][fname][key] = nil end
                    end
                end
            end
            for _, n in ipairs(sortedKeys(factions)) do combo:AddChoice(n) end
            combo.OnSelect = function(_, _, v) rebuild(v) end
            tabs:AddSheet(title, panel, "icon16/user.png")
        end
        nestTab("Смотреть: ранги", "ViewRoles", "Roles")
        nestTab("Управление: ранги", "ControlRoles", "Roles")
        nestTab("Смотреть: отделы", "ViewDepartments", "Departments")
        nestTab("Управление: отделы", "ControlDepartments", "Departments")

        local function steamTab(title, field)
            local panel = vgui.Create("DPanel")
            panel:SetPaintBackground(false)
            local row = vgui.Create("DPanel", panel)
            row:Dock(TOP) row:SetTall(34) row:DockMargin(8, 8, 8, 4) row:SetPaintBackground(false)
            local entry = vgui.Create("DTextEntry", row)
            entry:Dock(LEFT) entry:SetWide(300) entry:SetPlaceholderText("SteamID64")
            local list = vgui.Create("DListView", panel)
            list:Dock(FILL) list:DockMargin(8, 4, 8, 8) list:AddColumn("Steam")
            local function rebuild()
                list:Clear()
                for _, s in ipairs(sortedKeys(data[field])) do list:AddLine(s) end
            end
            rebuild()
            local add = mkBtn(row, "Добавить", THEME.green)
            add:Dock(LEFT) add:SetWide(100) add:DockMargin(6, 0, 0, 0)
            add.DoClick = function()
                local s = string.Trim(entry:GetValue() or "")
                if s ~= "" then data[field][s] = true entry:SetText("") rebuild() end
            end
            local online = vgui.Create("DComboBox", row)
            online:Dock(FILL) online:DockMargin(6, 0, 0, 0) online:SetValue("Онлайн…")
            for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                if IsValid(p) then
                    local ck = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(p)) or p:SteamID64()
                    online:AddChoice(p:Nick() .. " [" .. ck .. "]", ck)
                end
            end
            online.OnSelect = function(_, _, _, id) if id then data[field][id] = true rebuild() end end
            tabs:AddSheet(title, panel, "icon16/key.png")
        end
        steamTab("Смотреть: Steam", "ViewSteam")
        steamTab("Управление: Steam", "ControlSteam")

        local bottom = vgui.Create("DPanel", frame)
        bottom:Dock(BOTTOM) bottom:SetTall(44) bottom:SetPaintBackground(false)
        local save = mkBtn(bottom, "Сохранить", THEME.green)
        save:Dock(RIGHT) save:SetWide(160) save:DockMargin(6, 6, 10, 6)
        save.DoClick = function()
            net.Start(NET_SAVE) net.WriteTable(data) net.SendToServer()
        end
    end

    net.Receive(NET_DATA, function()
        openMenu(net.ReadTable() or {}, net.ReadTable() or {})
    end)
    net.Receive(NET_RESULT, function()
        notification.AddLegacy(net.ReadString(), net.ReadBool() and NOTIFY_GENERIC or NOTIFY_ERROR, 4)
    end)

    function AM.OpenMenu()
        net.Start(NET_REQ) net.SendToServer()
    end
    concommand.Add("grm_alarm_access", AM.OpenMenu)
    hook.Add("OnPlayerChat", "GRM_AlarmAccess_ChatCl", function(ply, text)
        if ply ~= LocalPlayer() then return end
        local msg = string.lower(string.Trim(text or ""))
        if msg == "/alarm_access" or msg == "!alarm_access" then AM.OpenMenu() return true end
    end)

    -- v18.08: вкладка встраивается штатным хуком меню организаций
    -- (работает и в старом /factions, и в Unified UI). Раньше модуль
    -- ПОДМЕНЯЛ глобальную OpenAdminMenu и искал DPropertySheet внутри окна —
    -- в новом меню такого листа нет, поэтому вкладка просто не появлялась.
    local function installTab(sheet)
        if not IsValid(sheet) then return end
        for _, item in ipairs(sheet.Items or {}) do
            if item.Tab and item.Tab:GetText() == "Сигнализация" then return end
        end
        local panel = vgui.Create("DPanel")
        panel:SetPaintBackground(false)
        local lab = vgui.Create("DLabel", panel)
        lab:Dock(TOP) lab:SetTall(60) lab:DockMargin(12, 12, 12, 4) lab:SetWrap(true)
        lab:SetText("Доступ к системе сигнализации: терминалы (просмотр логов/статуса) и управление режимами (выкл / охрана / пассив).")
        lab:SetTextColor(Color(220, 220, 230))
        local b = mkBtn(panel, "Открыть доступ сигнализации", THEME.accent)
        b:Dock(TOP) b:SetTall(36) b:DockMargin(12, 8, 12, 0)
        b.DoClick = AM.OpenMenu
        sheet:AddSheet("Сигнализация", panel, "icon16/bell.png")
    end
    -- Вкладка встраивается в меню фракций, как только оно появится.
    -- Раньше здесь крутился собственный опрашивающий таймер (0.5 с × 24) —
    -- и так в шести модулях доступов. Теперь единое ожидание условия
    -- GRM.Boot.When: одна проверка на всех, с таймаутом и без «вечных» реп.
    hook.Add("GRM_FactionsAdmin_BuildTabs", "GRM_AlarmAccess_Tab", installTab)
    print("[GRM Alarm] Access client loaded")
end
