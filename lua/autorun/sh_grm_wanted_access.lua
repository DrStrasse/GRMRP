--[[--------------------------------------------------------------------
    GRM Wanted Access (Код 61)
    Выдача доступа: /wanted_access + вкладка в /factions
    data/grm_wanted/access.json
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Wanted = GRM.Wanted or {}
GRM.Wanted.AccessManager = GRM.Wanted.AccessManager or {}
local AM = GRM.Wanted.AccessManager

local NET_REQ = "GRM_WantedAccess_Request"
local NET_DATA = "GRM_WantedAccess_Data"
local NET_SAVE = "GRM_WantedAccess_Save"
local NET_RESULT = "GRM_WantedAccess_Result"

local ACCESS_DIR = "grm_wanted"
local ACCESS_FILE = ACCESS_DIR .. "/access.json"

AM.Config = AM.Config or { SuperAdminBypass = true, AdminBypass = false }

local function jsonT(txt)
    local ok, t = pcall(util.JSONToTable, txt, false, true)
    return (ok and istable(t)) and t or nil
end

local function normalizeAccess(data)
    data = istable(data) and data or {}
    data.ViewFactions = istable(data.ViewFactions) and data.ViewFactions or {}
    data.EditFactions = istable(data.EditFactions) and data.EditFactions or {}
    data.ViewRoles = istable(data.ViewRoles) and data.ViewRoles or {}
    data.EditRoles = istable(data.EditRoles) and data.EditRoles or {}
    data.ViewDepartments = istable(data.ViewDepartments) and data.ViewDepartments or {}
    data.EditDepartments = istable(data.EditDepartments) and data.EditDepartments or {}
    data.ViewSteam = istable(data.ViewSteam) and data.ViewSteam or {}
    data.EditSteam = istable(data.EditSteam) and data.EditSteam or {}
    -- Юрисдикции (добавлено в v1.1). Значения: "all" | "civil" | "military".
    -- Старые access.json таких полей не содержат — они просто создаются
    -- пустыми, поведение по умолчанию берётся из фракции игрока.
    data.Jurisdictions = istable(data.Jurisdictions) and data.Jurisdictions or {}
    data.JurisdictionSteam = istable(data.JurisdictionSteam) and data.JurisdictionSteam or {}
    return data
end

local function normJur(v)
    v = tostring(v or "")
    if v == "all" or v == "civil" or v == "military" then return v end
    return nil
end

local function getFactionInfo(ply)
    if not IsValid(ply) or not istable(Factions) then return nil, nil, nil end
    local sid, sid64 = ply:SteamID(), ply:SteamID64()
    local charKey = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply)) or (sid64 .. ":char1")
    for factionName, f in pairs(Factions) do
        if istable(f) and istable(f.Members) then
            local m = GRM.Identity.FactionMember(f, ply)
            if istable(m) then return factionName, m.Role, m.Department end
        end
    end
    return nil, nil, nil
end

local function nested(t, factionName, key)
    if not istable(t) or not key then return false end
    if istable(t[factionName]) and t[factionName][key] == true then return true end
    return false
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
        if not file.Exists(ACCESS_FILE, "DATA") then
            AM.Data = normalizeAccess({})
            return AM.Data
        end
        local raw = file.Read(ACCESS_FILE, "DATA") or ""
        local data = jsonT(raw)
        if not data then
            AM.Data = normalizeAccess({})
            return AM.Data
        end
        AM.Data = normalizeAccess(data)
        return AM.Data
    end

    function AM.Save(data)
        ensureDir()
        AM.Data = normalizeAccess(data or AM.Data)
        local ok, txt = pcall(util.TableToJSON, AM.Data, true)
        if ok and isstring(txt) then
            file.Write(ACCESS_FILE, txt)
            print("[GRM Wanted Access] SAVE ok")
            return true
        end
        return false
    end

    AM.Load()

    local function buildFactionsPayload()
        local out = {}
        for factionName, f in pairs(Factions or {}) do
            if istable(f) then
                out[factionName] = {
                    Roles = istable(f.Roles) and f.Roles or {},
                    Departments = istable(f.Departments) and f.Departments or {},
                }
            end
        end
        return out
    end

    local function sendResult(ply, ok, msg)
        if not IsValid(ply) then return end
        net.Start(NET_RESULT)
            net.WriteBool(ok and true or false)
            net.WriteString(tostring(msg or ""))
        net.Send(ply)
    end

    local function sendData(ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then
            if IsValid(ply) then sendResult(ply, false, "Только superadmin.") end
            return
        end
        net.Start(NET_DATA)
            net.WriteTable(buildFactionsPayload())
            net.WriteTable(AM.Data or normalizeAccess({}))
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
    net.Receive(NET_REQ, function(bits, ply) if adminGuard(ply, "wanted.access.open", bits, 1024) then sendData(ply) end end)
    net.Receive(NET_SAVE, function(bits, ply)
        if not adminGuard(ply, "wanted.access.save", bits, 524288) then return end
        local data = normalizeAccess(net.ReadTable() or {})
        local ok = AM.Save(data)
        if ok and GRM.Audit and GRM.Audit.Write then GRM.Audit.Write("access", "wanted.legacy.save", ply, {}, {}) end
        sendResult(ply, ok == true, ok and "Доступ к розыску сохранён." or "Ошибка записи доступа.")
        sendData(ply)
    end)

    local function check(ply, mode)
        -- mode: "view" | "edit"
        if not IsValid(ply) then return false end
        local cfg = AM.Config or {}
        if cfg.SuperAdminBypass ~= false and ply:IsSuperAdmin() then return true end
        if GRM.Access and GRM.Access.Explicit then
            local decision = GRM.Access.Explicit(ply, mode == "edit" and "wanted.civil.edit" or "wanted.civil.view")
            if decision ~= nil then return decision == true end
            if mode == "view" then
                local edit = GRM.Access.Explicit(ply, "wanted.civil.edit")
                if edit == true then return true end -- edit implies view
            end
        end
        if cfg.AdminBypass and ply:IsAdmin() then return true end
        local data = normalizeAccess(AM.Data or AM.Load())
        local sid, sid64 = ply:SteamID(), ply:SteamID64()
        local charKey = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply)) or (sid64 .. ":char1")
        local steamT = mode == "edit" and data.EditSteam or data.ViewSteam
        if steamT[charKey] or steamT[sid64] or steamT[sid] then return true end
        -- edit implies view lists also count for edit steam only; view can use edit lists too?
        -- View: View* OR Edit* ; Edit: only Edit*
        if mode == "view" then
            if data.EditSteam[sid64] or data.EditSteam[sid] then return true end
        end

        local factionName, role, department = getFactionInfo(ply)
        if not factionName then return false end

        if mode == "edit" then
            if data.EditFactions[factionName] then return true end
            if nested(data.EditRoles, factionName, role) then return true end
            if nested(data.EditDepartments, factionName, department) then return true end
            return false
        end

        -- view
        if data.ViewFactions[factionName] or data.EditFactions[factionName] then return true end
        if nested(data.ViewRoles, factionName, role) or nested(data.EditRoles, factionName, role) then return true end
        if nested(data.ViewDepartments, factionName, department) or nested(data.EditDepartments, factionName, department) then return true end
        return false
    end

    function AM.CanView(ply) return check(ply, "view") end
    function AM.CanEdit(ply) return check(ply, "edit") end

    --- Юрисдикция, разрешённая игроку менеджером доступов.
    -- Возвращает "all" | "civil" | "military" либо nil, если явного
    -- назначения нет (тогда ядро розыска берёт юрисдикцию фракции).
    -- Приоритет: персональное назначение по SteamID → назначение фракции.
    function AM.JurisdictionOf(ply)
        if not IsValid(ply) then return nil end
        local cfg = AM.Config or {}
        if cfg.SuperAdminBypass ~= false and ply:IsSuperAdmin() then return "all" end

        local data = normalizeAccess(AM.Data or AM.Load())
        local sid, sid64 = ply:SteamID(), ply:SteamID64()
        local charKey = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply)) or (sid64 .. ":char1")

        local js = data.JurisdictionSteam
        local personal = normJur(js[charKey] or js[sid64] or js[sid])
        if personal then return personal end

        local factionName = getFactionInfo(ply)
        if factionName then
            local byFaction = normJur(data.Jurisdictions[factionName])
            if byFaction then return byFaction end
        end
        return nil
    end

    function AM.Install()
        if not GRM.Wanted then return end
        GRM.Wanted.CanView = function(ply)
            if not IsValid(ply) then return false end
            if ply:IsSuperAdmin() then return true end
            return AM.CanView(ply)
        end
        GRM.Wanted.CanEdit = function(ply)
            if not IsValid(ply) then return false end
            if ply:IsSuperAdmin() then return true end
            return AM.CanEdit(ply)
        end
        -- Ядро розыска и терминалы спрашивают юрисдикцию через это поле:
        -- если менеджер доступов не загружен, там срабатывает фолбэк по фракции.
        GRM.Wanted.JurisdictionOf = AM.JurisdictionOf
    end

    AM.Install()
    timer.Simple(0, AM.Install)
    timer.Simple(1, AM.Install)
    timer.Simple(3, AM.Install)
    timer.Simple(6, AM.Install)

    concommand.Add("grm_wanted_access", function(ply)
        if IsValid(ply) and ply:IsSuperAdmin() then sendData(ply) end
    end)

    hook.Add("PlayerSay", "GRM_WantedAccess_Chat", function(ply, text)
        local msg = string.lower(string.Trim(text or ""))
        if msg == "/wanted_access" or msg == "!wanted_access" then
            if not ply:IsSuperAdmin() then ply:ChatPrint("[Розыск] Только superadmin.") return "" end
            sendData(ply)
            return ""
        end
    end)

    print("[GRM Wanted] Access Manager loaded")
end

if CLIENT then
    surface.CreateFont("GRMWantedAcc_Title", { font = "Roboto", size = 20, weight = 700, extended = true })
    surface.CreateFont("GRMWantedAcc_Normal", { font = "Roboto", size = 14, weight = 500, extended = true })
    surface.CreateFont("GRMWantedAcc_Small", { font = "Roboto", size = 12, weight = 400, extended = true })

    local THEME = {
        bg = Color(22, 24, 30, 250),
        panel = Color(32, 36, 46, 245),
        text = Color(230, 235, 240),
        dim = Color(150, 160, 175),
        green = Color(70, 180, 110),
        accent = Color(70, 140, 220),
        yellow = Color(220, 180, 70),
        red = Color(200, 80, 80),
    }

    local function sortedKeys(t)
        local k = {}
        for key in pairs(t or {}) do k[#k + 1] = key end
        table.sort(k, function(a, b) return tostring(a) < tostring(b) end)
        return k
    end

    local function mkBtn(parent, text, col)
        local b = vgui.Create("DButton", parent)
        b:SetText(text)
        b:SetFont("GRMWantedAcc_Normal")
        b:SetTextColor(color_white)
        b.Paint = function(self, w, h)
            local c = col or THEME.accent
            if self:IsHovered() then c = Color(math.min(255, c.r + 20), math.min(255, c.g + 20), math.min(255, c.b + 20)) end
            draw.RoundedBox(6, 0, 0, w, h, c)
        end
        return b
    end

    local function openMenu(factions, data)
        data = normalizeAccess(data)
        factions = factions or {}
        if IsValid(AM._frame) then AM._frame:Remove() end
        local frame = vgui.Create("DFrame")
        AM._frame = frame
        frame:SetTitle("")
        frame:SetSize(920, 680)
        frame:Center()
        frame:MakePopup()
        frame.Paint = function(_, w, h)
            draw.RoundedBox(8, 0, 0, w, h, THEME.bg)
            draw.RoundedBoxEx(8, 0, 0, w, 36, Color(36, 40, 54), true, true, false, false)
            draw.SimpleText("Доступ к системе розыска", "GRMWantedAcc_Title", 14, 18, THEME.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end

        local tabs = vgui.Create("DPropertySheet", frame)
        tabs:Dock(FILL)
        tabs:DockMargin(8, 44, 8, 52)

        local function factionChecklist(title, field, color)
            local panel = vgui.Create("DScrollPanel")
            local help = vgui.Create("DLabel", panel)
            help:Dock(TOP)
            help:SetTall(36)
            help:DockMargin(8, 6, 8, 4)
            help:SetWrap(true)
            help:SetFont("GRMWantedAcc_Small")
            help:SetTextColor(THEME.dim)
            help:SetText(title)
            for _, fname in ipairs(sortedKeys(factions)) do
                local row = vgui.Create("DPanel", panel)
                row:Dock(TOP)
                row:SetTall(32)
                row:DockMargin(6, 0, 6, 3)
                row.Paint = function(_, w, h) draw.RoundedBox(5, 0, 0, w, h, THEME.panel) end
                local chk = vgui.Create("DCheckBoxLabel", row)
                chk:Dock(FILL)
                chk:DockMargin(10, 0, 0, 0)
                chk:SetText(fname)
                chk:SetTextColor(THEME.text)
                chk:SetFont("GRMWantedAcc_Normal")
                chk:SetValue(data[field][fname] and 1 or 0)
                chk.OnChange = function(_, val)
                    if val then data[field][fname] = true else data[field][fname] = nil end
                end
            end
            return panel
        end

        tabs:AddSheet("Смотреть: фракции", factionChecklist(
            "Фракции с правом ОТКРЫВАТЬ базу розыска (/wanted).", "ViewFactions"), "icon16/magnifier.png")
        tabs:AddSheet("Редактировать: фракции", factionChecklist(
            "Фракции с правом ВЫПИСЫВАТЬ статьи / менять уровень / снимать розыск.", "EditFactions"), "icon16/pencil.png")

        local function nestedTab(title, field, sourceKey, icon)
            local panel = vgui.Create("DPanel")
            panel:SetPaintBackground(false)
            local top = vgui.Create("DPanel", panel)
            top:Dock(TOP)
            top:SetTall(38)
            top:SetPaintBackground(false)
            local combo = vgui.Create("DComboBox", top)
            combo:Dock(LEFT)
            combo:SetWide(300)
            combo:DockMargin(8, 6, 6, 6)
            combo:SetValue("Фракция…")
            local scroll = vgui.Create("DScrollPanel", panel)
            scroll:Dock(FILL)
            scroll:DockMargin(8, 4, 8, 8)
            local function rebuild(fname)
                scroll:Clear()
                local f = factions[fname]
                if not f then return end
                for _, key in ipairs(f[sourceKey] or {}) do
                    local row = vgui.Create("DPanel", scroll)
                    row:Dock(TOP)
                    row:SetTall(32)
                    row:DockMargin(0, 0, 0, 3)
                    row.Paint = function(_, w, h) draw.RoundedBox(5, 0, 0, w, h, THEME.panel) end
                    local chk = vgui.Create("DCheckBoxLabel", row)
                    chk:Dock(FILL)
                    chk:DockMargin(10, 0, 0, 0)
                    chk:SetText(tostring(key))
                    chk:SetTextColor(THEME.text)
                    data[field][fname] = istable(data[field][fname]) and data[field][fname] or {}
                    chk:SetValue(data[field][fname][key] and 1 or 0)
                    chk.OnChange = function(_, val)
                        data[field][fname] = data[field][fname] or {}
                        if val then data[field][fname][key] = true else data[field][fname][key] = nil end
                    end
                end
            end
            for _, fname in ipairs(sortedKeys(factions)) do combo:AddChoice(fname) end
            combo.OnSelect = function(_, _, v) rebuild(v) end
            tabs:AddSheet(title, panel, icon)
        end

        nestedTab("Смотреть: ранги", "ViewRoles", "Roles", "icon16/user.png")
        nestedTab("Редактировать: ранги", "EditRoles", "Roles", "icon16/user_edit.png")
        nestedTab("Смотреть: отделы", "ViewDepartments", "Departments", "icon16/brick.png")
        nestedTab("Редактировать: отделы", "EditDepartments", "Departments", "icon16/brick_edit.png")

        -- Steam
        local function steamTab(title, field)
            local panel = vgui.Create("DPanel")
            panel:SetPaintBackground(false)
            local row = vgui.Create("DPanel", panel)
            row:Dock(TOP)
            row:SetTall(36)
            row:DockMargin(8, 8, 8, 4)
            row:SetPaintBackground(false)
            local entry = vgui.Create("DTextEntry", row)
            entry:Dock(LEFT)
            entry:SetWide(320)
            entry:SetPlaceholderText("SteamID64 / STEAM_0:…")
            local list = vgui.Create("DListView", panel)
            list:Dock(FILL)
            list:DockMargin(8, 4, 8, 8)
            list:AddColumn("Steam")
            local function rebuild()
                list:Clear()
                for _, sid in ipairs(sortedKeys(data[field])) do list:AddLine(sid) end
            end
            rebuild()
            local add = mkBtn(row, "Добавить", THEME.green)
            add:Dock(LEFT)
            add:SetWide(100)
            add:DockMargin(6, 0, 0, 0)
            add.DoClick = function()
                local s = string.Trim(entry:GetValue() or "")
                if s ~= "" then data[field][s] = true entry:SetText("") rebuild() end
            end
            local del = mkBtn(row, "Удалить", THEME.accent)
            del:Dock(LEFT)
            del:SetWide(100)
            del:DockMargin(6, 0, 0, 0)
            del.DoClick = function()
                local ln = list:GetSelected()
                if ln and ln[1] then data[field][ln[1]:GetColumnText(1)] = nil rebuild() end
            end
            local online = vgui.Create("DComboBox", row)
            online:Dock(FILL)
            online:DockMargin(6, 0, 0, 0)
            online:SetValue("Онлайн…")
            for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                if IsValid(p) then
                    local ck = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(p)) or p:SteamID64()
                    online:AddChoice(p:Nick() .. " [" .. ck .. "]", ck)
                end
            end
            online.OnSelect = function(_, _, _, id)
                if id then data[field][id] = true rebuild() end
            end
            tabs:AddSheet(title, panel, "icon16/key.png")
        end
        steamTab("Смотреть: Steam", "ViewSteam")
        steamTab("Редактировать: Steam", "EditSteam")

        local bottom = vgui.Create("DPanel", frame)
        bottom:Dock(BOTTOM)
        bottom:SetTall(44)
        bottom:SetPaintBackground(false)
        local save = mkBtn(bottom, "Сохранить доступ", THEME.green)
        save:Dock(RIGHT)
        save:SetWide(180)
        save:DockMargin(6, 6, 10, 6)
        save.DoClick = function()
            net.Start(NET_SAVE)
                net.WriteTable(data)
            net.SendToServer()
        end
        local reload = mkBtn(bottom, "Обновить", THEME.accent)
        reload:Dock(RIGHT)
        reload:SetWide(120)
        reload:DockMargin(6, 6, 0, 6)
        reload.DoClick = function()
            net.Start(NET_REQ)
            net.SendToServer()
            frame:Close()
        end
    end

    net.Receive(NET_DATA, function()
        openMenu(net.ReadTable() or {}, net.ReadTable() or {})
    end)
    net.Receive(NET_RESULT, function()
        local ok = net.ReadBool()
        local msg = net.ReadString()
        notification.AddLegacy(msg, ok and NOTIFY_GENERIC or NOTIFY_ERROR, 4)
    end)

    function AM.OpenMenu()
        net.Start(NET_REQ)
        net.SendToServer()
    end
    concommand.Add("grm_wanted_access", AM.OpenMenu)

    hook.Add("OnPlayerChat", "GRM_WantedAccess_Chat", function(ply, text)
        if ply ~= LocalPlayer() then return end
        local msg = string.lower(string.Trim(text or ""))
        if msg == "/wanted_access" or msg == "!wanted_access" then
            AM.OpenMenu()
            return true
        end
    end)

    -- v18.08: вкладка встраивается штатным хуком меню организаций
    -- (работает и в старом /factions, и в Unified UI). Раньше модуль
    -- ПОДМЕНЯЛ глобальную OpenAdminMenu и искал DPropertySheet внутри окна —
    -- в новом меню такого листа нет, поэтому вкладка просто не появлялась.
    local function installFactionsTab(sheet)
        if not IsValid(sheet) then return end
        for _, item in ipairs(sheet.Items or {}) do
            if item.Tab and item.Tab:GetText() == "Розыск" then return end
        end
        local panel = vgui.Create("DPanel")
        panel:SetPaintBackground(false)
        local label = vgui.Create("DLabel", panel)
        label:Dock(TOP)
        label:SetTall(70)
        label:DockMargin(12, 12, 12, 4)
        label:SetWrap(true)
        label:SetText("Доступ фракций / рангов / отделов / SteamID к базе розыска: просмотр (/wanted) и редактирование (статьи, уровни).")
        label:SetTextColor(Color(220, 220, 230))
        local button = mkBtn(panel, "Открыть настройку доступа розыска", THEME.accent)
        button:Dock(TOP)
        button:SetTall(36)
        button:DockMargin(12, 8, 12, 0)
        button.DoClick = AM.OpenMenu
        local tip = vgui.Create("DLabel", panel)
        tip:Dock(TOP)
        tip:SetTall(36)
        tip:DockMargin(12, 12, 12, 0)
        tip:SetText("/wanted_access  ·  grm_wanted_access  ·  /wanted — база")
        tip:SetTextColor(Color(160, 170, 180))
        sheet:AddSheet("Розыск", panel, "icon16/exclamation.png")
    end
    -- Вкладка встраивается в меню фракций, как только оно появится.
    -- Раньше здесь крутился собственный опрашивающий таймер (0.5 с × 24) —
    -- и так в шести модулях доступов. Теперь единое ожидание условия
    -- GRM.Boot.When: одна проверка на всех, с таймаутом и без «вечных» реп.
    hook.Add("GRM_FactionsAdmin_BuildTabs", "GRM_WantedAccess_Tab", installFactionsTab)
    print("[GRM Wanted] Access client loaded")
end

-- Вечер-18: единый словарь slash-команд: имена живого PlayerSay-обработчика
-- вносятся во внешний реестр библиотеки (на режиме сверка идёт ДО ParseSay —
-- без регистрации команда стала бы «неизвестной»).
if GRM and GRM.Chat and GRM.Chat.RegisterExternalCommands then
    GRM.Chat.RegisterExternalCommands({ "/wanted_access" })
end
