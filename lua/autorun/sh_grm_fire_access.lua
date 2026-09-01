--[[--------------------------------------------------------------------
    GRM Fire Access (Код 58)
    /fire_access + /grm_fire_notify + вкладка в /factions
    data/grm_fire/access.json , data/grm_fire/notify.json
----------------------------------------------------------------------]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Fire = GRM.Fire or {}
GRM.Fire.AccessManager = GRM.Fire.AccessManager or {}
local AM = GRM.Fire.AccessManager
local F = GRM.Fire

local NET_REQ = "GRM_FireAccess_Request"
local NET_DATA = "GRM_FireAccess_Data"
local NET_SAVE = "GRM_FireAccess_Save"
local NET_NREQ = "GRM_FireNotify_Open"
local NET_NDATA = "GRM_FireNotify_Data"
local NET_NSAVE = "GRM_FireNotify_Save"

local ACCESS_DIR = "grm_fire"
local ACCESS_FILE = ACCESS_DIR .. "/access.json"
local NOTIFY_FILE = ACCESS_DIR .. "/notify.json"

local function jsonT(txt)
    local ok, t = pcall(util.JSONToTable, txt, false, true)
    return (ok and istable(t)) and t or nil
end

local function normalize(data)
    data = istable(data) and data or {}
    data.version = 1
    data.ViewFactions = istable(data.ViewFactions) and data.ViewFactions or {}
    data.ControlFactions = istable(data.ControlFactions) and data.ControlFactions or {}
    data.ViewRoles = istable(data.ViewRoles) and data.ViewRoles or {}
    data.ControlRoles = istable(data.ControlRoles) and data.ControlRoles or {}
    data.ViewSteam = istable(data.ViewSteam) and data.ViewSteam or {}
    data.ControlSteam = istable(data.ControlSteam) and data.ControlSteam or {}
    return data
end

local function getFactionInfo(ply)
    if not IsValid(ply) or not istable(Factions) then return nil, nil, nil end
    for name, f in pairs(Factions) do
        if istable(f) and istable(f.Members) then
            local m = GRM.Identity and GRM.Identity.FactionMember and GRM.Identity.FactionMember(f, ply)
            if istable(m) then return name, m.Role, m.Department end
        end
    end
    return nil, nil, nil
end

local function nested(t, fac, key)
    return istable(t) and key and istable(t[fac]) and t[fac][key] == true
end

local function steamHas(list, ply)
    if not istable(list) or not IsValid(ply) then return false end
    local sid, sid64 = ply:SteamID(), ply:SteamID64()
    local ck = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply)) or sid64
    if istable(list[1]) or list[1] then
        for _, s in ipairs(list) do
            if s == ck or s == sid64 or s == sid then return true end
        end
    end
    return list[ck] == true or list[sid64] == true or list[sid] == true
end

if SERVER then
    util.AddNetworkString(NET_REQ)
    util.AddNetworkString(NET_DATA)
    util.AddNetworkString(NET_SAVE)
    util.AddNetworkString(NET_NREQ)
    util.AddNetworkString(NET_NDATA)
    util.AddNetworkString(NET_NSAVE)

    local function ensureDir()
        if not file.IsDir(ACCESS_DIR, "DATA") then file.CreateDir(ACCESS_DIR) end
    end

    function AM.Load()
        ensureDir()
        if not file.Exists(ACCESS_FILE, "DATA") then AM.Data = normalize({}) return AM.Data end
        local data = jsonT(file.Read(ACCESS_FILE, "DATA") or "")
        if not istable(data) then
            local q = ACCESS_FILE .. ".corrupt." .. os.time()
            file.Write(q, file.Read(ACCESS_FILE, "DATA") or "")
            print("[GRM Fire] access битый — " .. q)
            AM.Data = normalize({})
            return AM.Data
        end
        AM.Data = normalize(data)
        return AM.Data
    end

    function AM.Save(data)
        ensureDir()
        AM.Data = normalize(data or AM.Data)
        local ok, txt = pcall(util.TableToJSON, AM.Data, true)
        if not ok or not isstring(txt) then return false end
        file.Write(ACCESS_FILE, txt)
        return file.Read(ACCESS_FILE, "DATA") == txt
    end

    AM.Load()

    F.NotifyData = F.NotifyData or { version = 1, factions = {} }

    function F.LoadNotify()
        ensureDir()
        if not file.Exists(NOTIFY_FILE, "DATA") then return end
        local t = jsonT(file.Read(NOTIFY_FILE, "DATA") or "")
        if istable(t) and istable(t.factions) then
            F.NotifyData.factions = {}
            if t.factions[1] then
                for _, n in ipairs(t.factions) do F.NotifyData.factions[tostring(n)] = true end
            else
                for k, v in pairs(t.factions) do if v == true then F.NotifyData.factions[tostring(k)] = true end end
            end
        end
    end

    function F.SaveNotify()
        ensureDir()
        local arr = {}
        for n in pairs(F.NotifyData.factions or {}) do arr[#arr + 1] = n end
        table.sort(arr)
        local payload = { version = 1, factions = arr }
        local ok, txt = pcall(util.TableToJSON, payload, true)
        if ok and isstring(txt) then file.Write(NOTIFY_FILE, txt) end
    end
    F.LoadNotify()

    local function factionOf(ply)
        return select(1, getFactionInfo(ply))
    end

    function F.NotifyFactions(text, pos, r, g, b)
        r = tonumber(r) or 255
        g = tonumber(g) or 120
        b = tonumber(b) or 80
        for facName in pairs(F.NotifyData.factions or {}) do
            for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                if IsValid(p) and factionOf(p) == facName then
                    if GRM.Notify then GRM.Notify(p, text, r, g, b)
                    else p:ChatPrint("[Пожар] " .. tostring(text)) end
                end
            end
        end
    end

    local function check(ply, mode)
        if not IsValid(ply) then return false end
        if ply:IsSuperAdmin() then return true end
        if GRM.Access and GRM.Access.Explicit then
            local decision = GRM.Access.Explicit(ply, mode == "control" and "fire.dispatch" or "fire.fight")
            if decision ~= nil then return decision == true end
            if mode == "view" then
                local dispatch = GRM.Access.Explicit(ply, "fire.dispatch")
                if dispatch == true then return true end -- control implies view
            end
        end
        local data = normalize(AM.Data or AM.Load())
        if steamHas(mode == "control" and data.ControlSteam or data.ViewSteam, ply) then return true end
        if mode == "view" and steamHas(data.ControlSteam, ply) then return true end
        local fac, role = getFactionInfo(ply)
        if not fac then return false end
        if mode == "control" then
            return data.ControlFactions[fac] == true or nested(data.ControlRoles, fac, role)
        end
        return data.ViewFactions[fac] == true or data.ControlFactions[fac] == true
            or nested(data.ViewRoles, fac, role) or nested(data.ControlRoles, fac, role)
    end

    function AM.CanView(ply) return check(ply, "view") end
    function AM.CanControl(ply) return check(ply, "control") end

    local function buildFactions()
        local out = {}
        for n, f in pairs(Factions or {}) do
            if istable(f) then
                out[n] = { Roles = istable(f.Roles) and f.Roles or {} }
            end
        end
        return out
    end

    local function sendAccess(ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        net.Start(NET_DATA)
            net.WriteTable(buildFactions())
            net.WriteTable(AM.Data or normalize({}))
        net.Send(ply)
    end

    local function adminGuard(ply, key, bits, maxBits)
        if not (IsValid(ply) and ply:IsSuperAdmin()) then return false end
        if GRM.Net and GRM.Net.Guard then
            return GRM.Net.Guard(ply, key, { rate = .75, burst = 2, maxBits = maxBits,
                permission = function(actor) return actor:IsSuperAdmin() end }, { bits = bits }) == true
        end
        return true
    end

    net.Receive(NET_REQ, function(bits, ply) if adminGuard(ply, "fire.access.open", bits, 1024) then sendAccess(ply) end end)
    net.Receive(NET_SAVE, function(bits, ply)
        if not adminGuard(ply, "fire.access.save", bits, 524288) then return end
        local ok = AM.Save(net.ReadTable() or {})
        if ok and GRM.Audit and GRM.Audit.Write then GRM.Audit.Write("access", "fire.legacy.save", ply, {}, {}) end
        sendAccess(ply)
        -- Права изменились — пересчитать флаг «пожарный» у игроков,
        -- от него зависит строка с водой и пеной на экране.
        hook.Run("GRM_FireAccessChanged", ply)
        if GRM.Notify then GRM.Notify(ply, "Доступ пожарных сохранён.", 100, 220, 130) end
    end)

    local function factionList()
        local out = {}
        if istable(Factions) then
            for name in pairs(Factions) do
                if istable(Factions[name]) then out[#out + 1] = tostring(name) end
            end
        end
        table.sort(out)
        return out
    end

    local function sendNotify(ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        local sel = {}
        for n in pairs(F.NotifyData.factions or {}) do sel[#sel + 1] = n end
        net.Start(NET_NDATA)
            net.WriteTable(sel)
            net.WriteTable(factionList())
        net.Send(ply)
    end

    net.Receive(NET_NREQ, function(bits, ply) if adminGuard(ply, "fire.notify.open", bits, 1024) then sendNotify(ply) end end)
    net.Receive(NET_NSAVE, function(bits, ply)
        if not adminGuard(ply, "fire.notify.save", bits, 262144) then return end
        local selected = net.ReadTable() or {}
        F.NotifyData.factions = {}
        for _, n in ipairs(selected) do
            if isstring(n) and string.Trim(n) ~= "" then F.NotifyData.factions[string.Trim(n)] = true end
        end
        F.SaveNotify()
        if GRM.Audit and GRM.Audit.Write then GRM.Audit.Write("access", "fire.notifications.save", ply, {}, { factions = table.Count(F.NotifyData.factions) }) end
        if GRM.Notify then GRM.Notify(ply, "Фракции оповещения о пожаре сохранены.", 100, 220, 130) end
    end)

    local function openAccess(ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then
            if GRM.Notify then GRM.Notify(ply, "Только суперадмин.", 255, 100, 100) end
            return
        end
        sendAccess(ply)
    end
    local function openNotify(ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then
            if GRM.Notify then GRM.Notify(ply, "Только суперадмин.", 255, 100, 100) end
            return
        end
        sendNotify(ply)
    end

    concommand.Add("grm_fire_access", openAccess)
    concommand.Add("grm_fire_notify", openNotify)

    hook.Add("PlayerSay", "GRM_FireAccess_Chat", function(ply, text)
        local msg = string.lower(string.Trim(text or ""))
        if msg == "/fire_access" or msg == "!fire_access" then openAccess(ply) return "" end
        if msg == "/grm_fire_notify" or msg == "!grm_fire_notify" then openNotify(ply) return "" end
    end)

    print("[GRM Fire] Access Manager loaded")
end

if CLIENT then
    surface.CreateFont("GRMFireAcc_Title", { font = "Roboto", size = 18, weight = 700, extended = true })
    surface.CreateFont("GRMFireAcc_Normal", { font = "Roboto", size = 14, weight = 500, extended = true })

    local THEME = {
        bg = Color(22, 24, 30, 250), panel = Color(32, 36, 46, 245),
        text = Color(230, 235, 240), green = Color(70, 180, 110), accent = Color(220, 110, 50),
    }

    local function sortedKeys(t)
        local k = {}
        for key in pairs(t or {}) do k[#k + 1] = key end
        table.sort(k, function(a, b) return tostring(a) < tostring(b) end)
        return k
    end

    local function mkBtn(parent, text, col)
        local b = vgui.Create("DButton", parent)
        b:SetText(text) b:SetFont("GRMFireAcc_Normal") b:SetTextColor(color_white)
        b.Paint = function(self, w, h)
            local c = col or THEME.accent
            if self:IsHovered() then c = Color(math.min(255, c.r + 20), math.min(255, c.g + 20), math.min(255, c.b + 20)) end
            draw.RoundedBox(6, 0, 0, w, h, c)
        end
        return b
    end

    local function openAccess(factions, data)
        data = normalize(data)
        if IsValid(AM._frame) then AM._frame:Remove() end
        local frame = vgui.Create("DFrame")
        AM._frame = frame
        frame:SetTitle("")
        frame:SetSize(820, 600)
        frame:Center()
        frame:MakePopup()
        frame.Paint = function(_, w, h)
            draw.RoundedBox(8, 0, 0, w, h, THEME.bg)
            draw.SimpleText("Доступ пожарных", "GRMFireAcc_Title", 14, 18, THEME.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
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
        facTab("Пульт: фракции", "ViewFactions")
        facTab("Рукав/гидрант: фракции", "ControlFactions")

        local function steamTab(title, field)
            local panel = vgui.Create("DPanel")
            panel:SetPaintBackground(false)
            local row = vgui.Create("DPanel", panel)
            row:Dock(TOP) row:SetTall(34) row:DockMargin(8, 8, 8, 4) row:SetPaintBackground(false)
            local entry = vgui.Create("DTextEntry", row)
            entry:Dock(LEFT) entry:SetWide(280) entry:SetPlaceholderText("SteamID64 / CharacterKey")
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
            tabs:AddSheet(title, panel, "icon16/key.png")
        end
        steamTab("Пульт: Steam", "ViewSteam")
        steamTab("Рукав: Steam", "ControlSteam")

        local bottom = vgui.Create("DPanel", frame)
        bottom:Dock(BOTTOM) bottom:SetTall(44) bottom:SetPaintBackground(false)
        local save = mkBtn(bottom, "Сохранить", THEME.green)
        save:Dock(RIGHT) save:SetWide(160) save:DockMargin(6, 6, 10, 6)
        save.DoClick = function()
            net.Start(NET_SAVE) net.WriteTable(data) net.SendToServer()
        end
    end

    net.Receive(NET_DATA, function()
        openAccess(net.ReadTable() or {}, net.ReadTable() or {})
    end)

    net.Receive(NET_NDATA, function()
        local selected, all = net.ReadTable() or {}, net.ReadTable() or {}
        local set = {}
        for _, n in ipairs(selected) do set[n] = true end
        if IsValid(AM._nframe) then AM._nframe:Remove() end
        local frame = vgui.Create("DFrame")
        AM._nframe = frame
        frame:SetTitle("")
        frame:SetSize(520, 480)
        frame:Center()
        frame:MakePopup()
        frame.Paint = function(_, w, h)
            draw.RoundedBox(8, 0, 0, w, h, THEME.bg)
            draw.SimpleText("Оповещение о пожаре", "GRMFireAcc_Title", 14, 18, THEME.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        local scroll = vgui.Create("DScrollPanel", frame)
        scroll:Dock(FILL) scroll:DockMargin(8, 40, 8, 52)
        local picks = {}
        for _, n in ipairs(all) do picks[n] = set[n] == true end
        for _, n in ipairs(all) do
            local row = vgui.Create("DPanel", scroll)
            row:Dock(TOP) row:SetTall(30) row:DockMargin(4, 2, 4, 2)
            row.Paint = function(_, w, h) draw.RoundedBox(5, 0, 0, w, h, THEME.panel) end
            local chk = vgui.Create("DCheckBoxLabel", row)
            chk:Dock(FILL) chk:DockMargin(10, 0, 0, 0)
            chk:SetText(n) chk:SetTextColor(THEME.text)
            chk:SetValue(picks[n] and 1 or 0)
            chk.OnChange = function(_, v) picks[n] = v and true or false end
        end
        local bot = vgui.Create("DPanel", frame)
        bot:Dock(BOTTOM) bot:SetTall(44) bot:SetPaintBackground(false)
        local save = mkBtn(bot, "Сохранить", THEME.green)
        save:Dock(RIGHT) save:SetWide(140) save:DockMargin(6, 6, 10, 6)
        save.DoClick = function()
            local arr = {}
            for n, v in pairs(picks) do if v then arr[#arr + 1] = n end end
            net.Start(NET_NSAVE) net.WriteTable(arr) net.SendToServer()
        end
    end)

    net.Receive(NET_NREQ, function()
        net.Start(NET_NREQ) net.SendToServer()
    end)

    function AM.OpenMenu()
        net.Start(NET_REQ) net.SendToServer()
    end
    concommand.Add("grm_fire_access", AM.OpenMenu)
    concommand.Add("grm_fire_notify", function()
        net.Start(NET_NREQ) net.SendToServer()
    end)

    -- v18.08: вкладка встраивается штатным хуком меню организаций
    -- (работает и в старом /factions, и в Unified UI). Раньше модуль
    -- ПОДМЕНЯЛ глобальную OpenAdminMenu и искал DPropertySheet внутри окна —
    -- в новом меню такого листа нет, поэтому вкладка просто не появлялась.
    local function installTab(sheet)
        if not IsValid(sheet) then return end
        for _, item in ipairs(sheet.Items or {}) do
            if item.Tab and item.Tab:GetText() == "Пожарные" then return end
        end
        local panel = vgui.Create("DPanel")
        panel:SetPaintBackground(false)
        local lab = vgui.Create("DLabel", panel)
        lab:Dock(TOP) lab:SetTall(70) lab:DockMargin(12, 12, 12, 4) lab:SetWrap(true)
        lab:SetText("Доступ к рукавам/гидрантам и пульт оповещения. Имя фракции в коде не ищем — отметьте галочками.")
        lab:SetTextColor(Color(220, 220, 230))
        local b = mkBtn(panel, "Открыть доступ пожарных", THEME.accent)
        b:Dock(TOP) b:SetTall(36) b:DockMargin(12, 8, 12, 0)
        b.DoClick = AM.OpenMenu
        local b2 = mkBtn(panel, "Фракции оповещения о пожаре", THEME.green)
        b2:Dock(TOP) b2:SetTall(36) b2:DockMargin(12, 8, 12, 0)
        b2.DoClick = function() net.Start(NET_NREQ) net.SendToServer() end
        local b3 = mkBtn(panel, "Пожарные машины (список ТС)", Color(70, 140, 220))
        b3:Dock(TOP) b3:SetTall(36) b3:DockMargin(12, 8, 12, 0)
        b3.DoClick = function() RunConsoleCommand("grm_fire_trucks") end
        local b4 = mkBtn(panel, "Очаги и таймеры", Color(220, 110, 50))
        b4:Dock(TOP) b4:SetTall(36) b4:DockMargin(12, 8, 12, 0)
        b4.DoClick = function() RunConsoleCommand("grm_fire_spots") end
        local b5 = mkBtn(panel, "Журнал тушения /fire_log", Color(60, 180, 130))
        b5:Dock(TOP) b5:SetTall(36) b5:DockMargin(12, 8, 12, 0)
        b5.DoClick = function() RunConsoleCommand("grm_fire_log") end
        sheet:AddSheet("Пожарные", panel, "icon16/fire.png")
    end
    -- Вкладка встраивается в меню фракций, как только оно появится.
    -- Раньше здесь крутился собственный опрашивающий таймер (0.5 с × 24) —
    -- и так в шести модулях доступов. Теперь единое ожидание условия
    -- GRM.Boot.When: одна проверка на всех, с таймаутом и без «вечных» реп.
    hook.Add("GRM_FactionsAdmin_BuildTabs", "GRM_FireAccess_Tab", installTab)
    print("[GRM Fire] Access client loaded")
end
