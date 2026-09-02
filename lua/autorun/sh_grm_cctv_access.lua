--[[--------------------------------------------------------------------
    GRM CCTV Access Manager (Код 60+)
    Интерактивная выдача доступа к видеонаблюдению:
      • смотреть мониторы / live-view;
      • настраивать камеры и серверы сети (E).

    Команды (superadmin):
      /cctv_access  |  !cctv_access  |  grm_cctv_access

    Интеграция:
      • вкладка «CCTV» в /factions (как «Телефония»);
      • читает Factions (ранги/отделы);
      • переопределяет CCTV.HasAccess / CanView / CanConfigure.

    Файл: garrysmod/data/grm_cctv/access.json
    (массивы/таблицы без числовых sid-ключей; jsonT ignoreConversions)
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.CCTV = GRM.CCTV or {}
GRM.CCTV.AccessManager = GRM.CCTV.AccessManager or {}
local AM = GRM.CCTV.AccessManager

local NET_REQ    = "GRM_CCTVAccess_Request"
local NET_DATA   = "GRM_CCTVAccess_Data"
local NET_SAVE   = "GRM_CCTVAccess_Save"
local NET_RESULT = "GRM_CCTVAccess_Result"

local ACCESS_DIR  = "grm_cctv"
local ACCESS_FILE = ACCESS_DIR .. "/access.json"

AM.Config = AM.Config or {
    SuperAdminBypass = true,
    AdminBypass = false,
}

local function jsonT(txt)
    local ok, t = pcall(util.JSONToTable, txt, false, true)
    return (ok and istable(t)) and t or nil
end

local function normalizeAccess(data)
    data = istable(data) and data or {}
    data.Factions = istable(data.Factions) and data.Factions or {}
    data.Roles = istable(data.Roles) and data.Roles or {}
    data.Departments = istable(data.Departments) and data.Departments or {}
    data.Steam = istable(data.Steam) and data.Steam or {}
    -- PublicView: все могут СМОТРЕТЬ (настройка — только по спискам / admin)
    if data.PublicView == nil then data.PublicView = false end
    return data
end

local function getFactionInfo(ply)
    if not IsValid(ply) or not istable(Factions) then return nil, nil, nil end
    local sid = ply:SteamID()
    local sid64 = ply:SteamID64()
    local charKey = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply)) or sid64
    for factionName, f in pairs(Factions) do
        if istable(f) and istable(f.Members) then
            local member = GRM.Identity.FactionMember(f, ply)
            if istable(member) then
                return factionName, member.Role, member.Department
            end
        end
    end
    return nil, nil, nil
end

local function nestedAccess(t, factionName, key)
    if not istable(t) or key == nil or key == "" then return false end
    if istable(t[factionName]) and t[factionName][key] == true then return true end
    if istable(t["*"]) and t["*"][key] == true then return true end
    return false
end

-- ============================================================
-- SERVER
-- ============================================================
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
        if string.Trim(raw) == "" then
            AM.Data = normalizeAccess({})
            return AM.Data
        end
        local data = jsonT(raw)
        if not data then
            local q = ACCESS_DIR .. "/access_corrupt_" .. os.time() .. ".txt"
            file.Write(q, raw)
            print("[GRM CCTV Access] битый access.json → data/" .. q)
            AM.Data = normalizeAccess({})
            return AM.Data
        end
        AM.Data = normalizeAccess(data)
        return AM.Data
    end

    function AM.Save(data)
        ensureDir()
        AM.Data = normalizeAccess(data or AM.Data or {})
        local ok, txt = pcall(util.TableToJSON, AM.Data, true)
        if not ok or not isstring(txt) then
            print("[GRM CCTV Access] SAVE fail: serialize")
            return false
        end
        file.Write(ACCESS_FILE, txt)
        local chk = file.Read(ACCESS_FILE, "DATA")
        if chk ~= txt then
            print("[GRM CCTV Access] SAVE fail: read-back")
            return false
        end
        print("[GRM CCTV Access] SAVE ok → data/" .. ACCESS_FILE)
        return true
    end

    AM.Load()

    -- Сборщик снимка фракций — общий для CCTV- и телефонного редакторов
    -- доступа (волна дедупа 1): GRM.Core.FactionAccessSnapshot.
    local buildFactionsPayload = GRM.Core.FactionAccessSnapshot

    local function sendResult(ply, ok, msg)
        if not IsValid(ply) then return end
        net.Start(NET_RESULT)
            net.WriteBool(ok and true or false)
            net.WriteString(tostring(msg or ""))
        net.Send(ply)
    end

    local function sendData(ply)
        if not IsValid(ply) then return end
        if not ply:IsSuperAdmin() then
            sendResult(ply, false, "Только superadmin может настраивать доступ к CCTV.")
            return
        end
        net.Start(NET_DATA)
            net.WriteTable(buildFactionsPayload())
            net.WriteTable(AM.Data or normalizeAccess({}))
            net.WriteTable(AM.Config or {})
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
    net.Receive(NET_REQ, function(bits, ply) if adminGuard(ply, "cctv.access.open", bits, 1024) then sendData(ply) end end)

    net.Receive(NET_SAVE, function(bits, ply)
        if not adminGuard(ply, "cctv.access.save", bits, 524288) then return end
        local data = net.ReadTable() or {}
        data = normalizeAccess(data)
        -- Steam: только string-ключи
        local steam = {}
        for k, v in pairs(data.Steam or {}) do
            if v == true and isstring(k) and k ~= "" then
                steam[k] = true
            end
        end
        data.Steam = steam
        local ok = AM.Save(data)
        if ok and GRM.Audit and GRM.Audit.Write then GRM.Audit.Write("access", "cctv.legacy.save", ply, {}, { publicView = data.PublicView == true }) end
        -- Синхронизируем PublicView в live-конфиг CCTV
        if GRM.CCTV and GRM.CCTV.Config and GRM.CCTV.Config.Access then
            GRM.CCTV.Config.Access.PublicView = data.PublicView and true or false
        end
        sendResult(ply, ok == true, ok and "Доступ к CCTV сохранён." or "Ошибка записи доступа CCTV.")
        if ok then sendData(ply) end
    end)

    local function hasAccessByData(ply)
        if not IsValid(ply) then return false, "invalid" end
        local cfg = AM.Config or {}
        if cfg.SuperAdminBypass ~= false and ply:IsSuperAdmin() then return true, "superadmin" end
        if cfg.AdminBypass and ply:IsAdmin() then return true, "admin" end

        AM.Data = normalizeAccess(AM.Data or AM.Load())
        local data = AM.Data

        local sid = ply:SteamID()
        local sid64 = ply:SteamID64()
        local charKey = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply)) or sid64
        if data.Steam[charKey] == true or data.Steam[sid64] == true or data.Steam[sid] == true then
            return true, "steam"
        end

        -- fallback: старый AllowSteam из sh_grm_cctv_config
        local old = GRM.CCTV and GRM.CCTV.Config and GRM.CCTV.Config.Access or nil
        if istable(old) and istable(old.AllowSteam) then
            if old.AllowSteam[sid64] or old.AllowSteam[sid] then return true, "config_steam" end
        end

        local factionName, role, department = getFactionInfo(ply)
        if not factionName then return false, "no_faction" end

        if data.Factions[factionName] == true then return true, "faction:" .. factionName end
        if nestedAccess(data.Roles, factionName, role) then return true, "role:" .. tostring(role) end
        if nestedAccess(data.Departments, factionName, department) then return true, "department:" .. tostring(department) end

        if istable(old) then
            if istable(old.AllowFactions) and old.AllowFactions[factionName] == true then
                return true, "config_faction"
            end
        end

        return false, "no_rule faction=" .. tostring(factionName) .. " role=" .. tostring(role) .. " dept=" .. tostring(department)
    end

    function AM.HasAccess(ply)
        local ok = hasAccessByData(ply)
        return ok == true
    end

    function AM.IsPublicView()
        local data = normalizeAccess(AM.Data or {})
        if data.PublicView then return true end
        local old = GRM.CCTV and GRM.CCTV.Config and GRM.CCTV.Config.Access
        if istable(old) and old.PublicView then return true end
        return false
    end

    function AM.GetDebug(ply)
        local ok, reason = hasAccessByData(ply)
        local factionName, role, department = getFactionInfo(ply)
        return ok, reason, factionName, role, department, normalizeAccess(AM.Data or {})
    end

    -- Переопределяем проверки CCTV (модуль sv может грузиться раньше/позже)
    function AM.InstallAccessOverride()
        GRM.CCTV = GRM.CCTV or {}

        GRM.CCTV.HasAccess = function(ply)
            return AM.HasAccess(ply)
        end

        GRM.CCTV.CanView = function(ply)
            if not IsValid(ply) then return false end
            if GRM.Access and GRM.Access.Explicit then
                local decision = GRM.Access.Explicit(ply, "cctv.view")
                if decision ~= nil then return decision == true end
                local configure = GRM.Access.Explicit(ply, "cctv.configure")
                if configure == true then return true end -- configure implies view
            end
            if AM.IsPublicView() then return true end
            return AM.HasAccess(ply)
        end

        GRM.CCTV.CanConfigure = function(ply, ent)
            if not IsValid(ply) then return false end
            if ply:IsSuperAdmin() then return true end
            if GRM.Access and GRM.Access.Explicit then
                local decision = GRM.Access.Explicit(ply, "cctv.configure")
                if decision ~= nil then return decision == true end
            end
            if not AM.HasAccess(ply) then return false end
            -- владелец entity тоже может крутить «своё»
            if IsValid(ent) and ent.GetOwnerSteam then
                local owner = ent:GetOwnerSteam() or ""
                if owner ~= "" and (owner == ply:SteamID64() or owner == ply:SteamID()) then
                    return true
                end
            end
            return true -- есть HasAccess → настройка разрешена
        end
    end

    AM.InstallAccessOverride()
    timer.Simple(0, AM.InstallAccessOverride)
    timer.Simple(1, AM.InstallAccessOverride)
    timer.Simple(3, AM.InstallAccessOverride)
    timer.Simple(6, AM.InstallAccessOverride)

    concommand.Add("grm_cctv_access", function(ply)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        if IsValid(ply) then sendData(ply) end
    end)

    concommand.Add("grm_cctv_access_reload", function(ply)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        AM.Load()
        AM.InstallAccessOverride()
        if IsValid(ply) then ply:ChatPrint("[CCTV] Доступ перезагружен.") else print("[CCTV] Доступ перезагружен.") end
    end)

    concommand.Add("grm_cctv_access_debug", function(ply, _, args)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        local target = ply
        local query = args and args[1]
        if query and query ~= "" then
            for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                if string.find(string.lower(p:Nick()), string.lower(query), 1, true)
                    or p:SteamID() == query or p:SteamID64() == query then
                    target = p
                    break
                end
            end
        end
        if not IsValid(target) then
            print("[CCTVAccessDebug] target not found")
            return
        end
        local ok, reason, factionName, role, department, data = AM.GetDebug(target)
        local lines = {
            "[CCTVAccessDebug] " .. target:Nick() .. " " .. target:SteamID() .. " / " .. tostring(target:SteamID64()),
            "access=" .. tostring(ok) .. " reason=" .. tostring(reason),
            "publicView=" .. tostring(AM.IsPublicView()),
            "faction=" .. tostring(factionName) .. " role=" .. tostring(role) .. " dept=" .. tostring(department),
        }
        for _, line in ipairs(lines) do
            if IsValid(ply) then ply:ChatPrint(line) else print(line) end
        end
    end)

    hook.Add("PlayerSay", "GRM_CCTVAccess_Chat", function(ply, text)
        local msg = string.lower(string.Trim(text or ""))
        if msg == "/cctv_access" or msg == "!cctv_access" or msg == "/cctvaccess" or msg == "!cctvaccess" then
            if not ply:IsSuperAdmin() then
                ply:ChatPrint("[CCTV] Только superadmin.")
                return ""
            end
            sendData(ply)
            return ""
        end
    end)

    print("[GRM CCTV] Access Manager loaded: data/" .. ACCESS_FILE)
end

-- ============================================================
-- CLIENT
-- ============================================================
if CLIENT then
    surface.CreateFont("GRMCCTVAccess_Title", { font = "Roboto", size = 20, weight = 700, extended = true })
    surface.CreateFont("GRMCCTVAccess_Normal", { font = "Roboto", size = 14, weight = 500, extended = true })
    surface.CreateFont("GRMCCTVAccess_Small", { font = "Roboto", size = 12, weight = 400, extended = true })

    local THEME = {
        bg = Color(22, 24, 30, 250),
        panel = Color(32, 36, 46, 245),
        text = Color(230, 235, 240),
        dim = Color(150, 160, 175),
        green = Color(70, 180, 110),
        accent = Color(70, 140, 220),
        yellow = Color(220, 180, 70),
    }

    local function sortedKeys(t)
        local keys = {}
        for k in pairs(t or {}) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        return keys
    end

    local function makeButton(parent, text, col)
        local b = vgui.Create("DButton", parent)
        b:SetText(text)
        b:SetFont("GRMCCTVAccess_Normal")
        b:SetTextColor(Color(255, 255, 255))
        b.Paint = function(self, w, h)
            local c = col or THEME.accent
            if self:IsHovered() then
                c = Color(math.min(255, c.r + 20), math.min(255, c.g + 20), math.min(255, c.b + 20))
            end
            draw.RoundedBox(6, 0, 0, w, h, c)
        end
        return b
    end

    local function accessValue(data, section, factionName, key)
        if section == "Factions" then
            return data.Factions[factionName] == true
        end
        if section == "Steam" then
            return data.Steam[factionName] == true -- factionName reused as steam key
        end
        local nest = data[section]
        return istable(nest) and istable(nest[factionName]) and nest[factionName][key] == true
    end

    local function setAccessValue(data, section, factionName, key, val)
        if section == "Factions" then
            if val then data.Factions[factionName] = true else data.Factions[factionName] = nil end
            return
        end
        if section == "Steam" then
            if val then data.Steam[factionName] = true else data.Steam[factionName] = nil end
            return
        end
        data[section] = istable(data[section]) and data[section] or {}
        data[section][factionName] = istable(data[section][factionName]) and data[section][factionName] or {}
        if val then
            data[section][factionName][key] = true
        else
            data[section][factionName][key] = nil
            if next(data[section][factionName]) == nil then data[section][factionName] = nil end
        end
    end

    local function openAccessMenu(factions, accessData, config)
        accessData = normalizeAccess(accessData)
        factions = factions or {}

        if IsValid(AM._frame) then AM._frame:Remove() end
        local frame = vgui.Create("DFrame")
        AM._frame = frame
        frame:SetTitle("")
        frame:SetSize(900, 680)
        frame:Center()
        frame:MakePopup()
        frame.Paint = function(_, w, h)
            draw.RoundedBox(8, 0, 0, w, h, THEME.bg)
            draw.RoundedBoxEx(8, 0, 0, w, 36, Color(35, 40, 52), true, true, false, false)
            draw.SimpleText("Доступ к видеонаблюдению (CCTV)", "GRMCCTVAccess_Title", 14, 18, THEME.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end

        local tabs = vgui.Create("DPropertySheet", frame)
        tabs:Dock(FILL)
        tabs:DockMargin(8, 44, 8, 52)

        -- ── Общее ──
        do
            local panel = vgui.Create("DPanel")
            panel:SetPaintBackground(false)

            local help = vgui.Create("DLabel", panel)
            help:Dock(TOP)
            help:SetTall(70)
            help:DockMargin(10, 10, 10, 6)
            help:SetWrap(true)
            help:SetFont("GRMCCTVAccess_Small")
            help:SetTextColor(THEME.dim)
            help:SetText("Кто может открывать мониторы CCTV (смотреть камеры) и настраивать оборудование (E по камере/серверу). Superadmin всегда имеет полный доступ. Спавн entity и permanent — только superadmin.")

            local pub = vgui.Create("DCheckBoxLabel", panel)
            pub:Dock(TOP)
            pub:SetTall(28)
            pub:DockMargin(12, 8, 12, 4)
            pub:SetText("PublicView — СМОТРЕТЬ мониторы могут ВСЕ игроки (настройка всё равно по спискам ниже)")
            pub:SetTextColor(THEME.text)
            pub:SetFont("GRMCCTVAccess_Normal")
            pub:SetValue(accessData.PublicView and 1 or 0)
            pub.OnChange = function(_, val) accessData.PublicView = val and true or false end

            local note = vgui.Create("DLabel", panel)
            note:Dock(TOP)
            note:SetTall(48)
            note:DockMargin(12, 12, 12, 0)
            note:SetWrap(true)
            note:SetFont("GRMCCTVAccess_Small")
            note:SetTextColor(THEME.yellow)
            note:SetText("Сеть (NetworkID) и ONLINE-сервер по-прежнему обязательны: без стойки камеры сети не видны даже при доступе.")

            tabs:AddSheet("Общее", panel, "icon16/cog.png")
        end

        -- ── Фракции ──
        do
            local panel = vgui.Create("DScrollPanel")
            panel:DockPadding(6, 6, 6, 6)

            local help = vgui.Create("DLabel", panel)
            help:Dock(TOP)
            help:SetTall(36)
            help:SetWrap(true)
            help:SetFont("GRMCCTVAccess_Small")
            help:SetTextColor(THEME.dim)
            help:SetText("Отмеченные фракции целиком получают доступ: смотреть мониторы + настраивать камеры/серверы.")

            for _, factionName in ipairs(sortedKeys(factions)) do
                local row = vgui.Create("DPanel", panel)
                row:Dock(TOP)
                row:SetTall(34)
                row:DockMargin(0, 0, 0, 4)
                row.Paint = function(_, w, h) draw.RoundedBox(5, 0, 0, w, h, THEME.panel) end

                local chk = vgui.Create("DCheckBoxLabel", row)
                chk:Dock(FILL)
                chk:DockMargin(10, 0, 0, 0)
                chk:SetText(factionName)
                chk:SetFont("GRMCCTVAccess_Normal")
                chk:SetTextColor(THEME.text)
                chk:SetValue(accessValue(accessData, "Factions", factionName) and 1 or 0)
                chk.OnChange = function(_, val)
                    setAccessValue(accessData, "Factions", factionName, nil, val)
                end
            end

            tabs:AddSheet("Фракции", panel, "icon16/group.png")
        end

        local function addNestedTab(title, section, sourceKey, icon)
            local panel = vgui.Create("DPanel")
            panel:SetPaintBackground(false)

            local top = vgui.Create("DPanel", panel)
            top:Dock(TOP)
            top:SetTall(38)
            top:SetPaintBackground(false)

            local combo = vgui.Create("DComboBox", top)
            combo:Dock(LEFT)
            combo:SetWide(300)
            combo:DockMargin(6, 6, 6, 6)
            combo:SetValue("Выберите фракцию")

            local scroll = vgui.Create("DScrollPanel", panel)
            scroll:Dock(FILL)
            scroll:DockMargin(6, 4, 6, 6)

            local function rebuild(factionName)
                scroll:Clear()
                local f = factions[factionName]
                if not f then return end
                local list = f[sourceKey] or {}
                if #list <= 0 then
                    local lbl = vgui.Create("DLabel", scroll)
                    lbl:Dock(TOP)
                    lbl:SetTall(32)
                    lbl:SetText("Нет данных для этой фракции.")
                    lbl:SetTextColor(THEME.dim)
                    return
                end
                for _, key in ipairs(list) do
                    local row = vgui.Create("DPanel", scroll)
                    row:Dock(TOP)
                    row:SetTall(34)
                    row:DockMargin(0, 0, 0, 4)
                    row.Paint = function(_, w, h) draw.RoundedBox(5, 0, 0, w, h, THEME.panel) end

                    local chk = vgui.Create("DCheckBoxLabel", row)
                    chk:Dock(FILL)
                    chk:DockMargin(10, 0, 0, 0)
                    chk:SetText(tostring(key))
                    chk:SetFont("GRMCCTVAccess_Normal")
                    chk:SetTextColor(THEME.text)
                    chk:SetValue(accessValue(accessData, section, factionName, key) and 1 or 0)
                    chk.OnChange = function(_, val)
                        setAccessValue(accessData, section, factionName, key, val)
                    end
                end
            end

            for _, factionName in ipairs(sortedKeys(factions)) do
                combo:AddChoice(factionName)
            end
            combo.OnSelect = function(_, _, value) rebuild(value) end
            tabs:AddSheet(title, panel, icon)
        end

        addNestedTab("Ранги", "Roles", "Roles", "icon16/user.png")
        addNestedTab("Отделы", "Departments", "Departments", "icon16/brick.png")

        -- ── Steam ──
        do
            local panel = vgui.Create("DPanel")
            panel:SetPaintBackground(false)

            local help = vgui.Create("DLabel", panel)
            help:Dock(TOP)
            help:SetTall(40)
            help:DockMargin(10, 8, 10, 4)
            help:SetWrap(true)
            help:SetFont("GRMCCTVAccess_Small")
            help:SetTextColor(THEME.dim)
            help:SetText("Индивидуальный доступ по SteamID64 (или STEAM_0:x:x). Не зависит от фракции.")

            local rowAdd = vgui.Create("DPanel", panel)
            rowAdd:Dock(TOP)
            rowAdd:SetTall(36)
            rowAdd:DockMargin(10, 4, 10, 6)
            rowAdd:SetPaintBackground(false)

            local entry = vgui.Create("DTextEntry", rowAdd)
            entry:Dock(LEFT)
            entry:SetWide(360)
            entry:SetPlaceholderText("7656119… или STEAM_0:1:…")

            local list = vgui.Create("DListView", panel)
            list:Dock(FILL)
            list:DockMargin(10, 0, 10, 10)
            list:AddColumn("SteamID / SteamID64")
            list:SetMultiSelect(false)

            local function rebuildSteam()
                list:Clear()
                for _, sid in ipairs(sortedKeys(accessData.Steam or {})) do
                    list:AddLine(sid)
                end
            end
            rebuildSteam()

            local addBtn = makeButton(rowAdd, "Добавить", THEME.green)
            addBtn:Dock(LEFT)
            addBtn:SetWide(110)
            addBtn:DockMargin(8, 0, 0, 0)
            addBtn.DoClick = function()
                local sid = string.Trim(entry:GetValue() or "")
                if sid == "" then return end
                accessData.Steam[sid] = true
                entry:SetText("")
                rebuildSteam()
            end

            local delBtn = makeButton(rowAdd, "Удалить выбранный", THEME.accent)
            delBtn:Dock(LEFT)
            delBtn:SetWide(160)
            delBtn:DockMargin(8, 0, 0, 0)
            delBtn.DoClick = function()
                local lines = list:GetSelected()
                if not lines or not lines[1] then return end
                local sid = lines[1]:GetColumnText(1)
                accessData.Steam[sid] = nil
                rebuildSteam()
            end

            -- быстрый add онлайн-игроков
            local online = vgui.Create("DComboBox", rowAdd)
            online:Dock(FILL)
            online:DockMargin(8, 0, 0, 0)
            online:SetValue("Игрок онлайн…")
            for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                if IsValid(p) then
                    local ck = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(p)) or p:SteamID64()
                    online:AddChoice(p:Nick() .. " (" .. ck .. ")", ck)
                end
            end
            online.OnSelect = function(_, _, _, data)
                if data then
                    accessData.Steam[data] = true
                    rebuildSteam()
                end
            end

            tabs:AddSheet("SteamID", panel, "icon16/key.png")
        end

        local bottom = vgui.Create("DPanel", frame)
        bottom:Dock(BOTTOM)
        bottom:SetTall(44)
        bottom:SetPaintBackground(false)

        local save = makeButton(bottom, "Сохранить доступ", THEME.green)
        save:Dock(RIGHT)
        save:SetWide(180)
        save:DockMargin(6, 6, 10, 6)
        save.DoClick = function()
            net.Start(NET_SAVE)
                net.WriteTable(accessData)
            net.SendToServer()
        end

        local reload = makeButton(bottom, "Обновить", THEME.accent)
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
        local factions = net.ReadTable() or {}
        local accessData = net.ReadTable() or {}
        local config = net.ReadTable() or {}
        openAccessMenu(factions, accessData, config)
    end)

    net.Receive(NET_RESULT, function()
        local ok = net.ReadBool()
        local msg = net.ReadString()
        notification.AddLegacy(msg, ok and NOTIFY_GENERIC or NOTIFY_ERROR, 4)
        surface.PlaySound(ok and "buttons/button14.wav" or "buttons/button10.wav")
    end)

    function AM.OpenMenu()
        net.Start(NET_REQ)
        net.SendToServer()
    end

    concommand.Add("grm_cctv_access", AM.OpenMenu)

    hook.Add("OnPlayerChat", "GRM_CCTVAccess_ChatClient", function(ply, text)
        if ply ~= LocalPlayer() then return end
        local msg = string.lower(string.Trim(text or ""))
        if msg == "/cctv_access" or msg == "!cctv_access" or msg == "/cctvaccess" or msg == "!cctvaccess" then
            AM.OpenMenu()
            return true
        end
    end)

    -- Вкладка в /factions
    -- v18.08: вкладка встраивается штатным хуком меню организаций
    -- (работает и в старом /factions, и в Unified UI). Раньше модуль
    -- ПОДМЕНЯЛ глобальную OpenAdminMenu и искал DPropertySheet внутри окна —
    -- в новом меню такого листа нет, поэтому вкладка просто не появлялась.
    local function installFactionsMenuIntegration(sheet)
        if not IsValid(sheet) then return end

        for _, item in ipairs(sheet.Items or {}) do
            if item.Tab and (item.Tab:GetText() == "CCTV" or item.Tab:GetText() == "Видеонаблюдение") then
                return
            end
        end

        local panel = vgui.Create("DPanel")
        panel:SetPaintBackground(false)

        local label = vgui.Create("DLabel", panel)
        label:Dock(TOP)
        label:SetTall(70)
        label:DockMargin(12, 12, 12, 4)
        label:SetWrap(true)
        label:SetText("Доступ фракций, рангов, отделов и SteamID к системе видеонаблюдения: мониторы, live-view, настройка камер и серверов сети.")
        label:SetTextColor(Color(220, 220, 230))

        local button = makeButton(panel, "Открыть настройку доступа CCTV", THEME.accent)
        button:Dock(TOP)
        button:SetTall(36)
        button:DockMargin(12, 8, 12, 0)
        button.DoClick = AM.OpenMenu

        local tip = vgui.Create("DLabel", panel)
        tip:Dock(TOP)
        tip:SetTall(40)
        tip:DockMargin(12, 12, 12, 0)
        tip:SetWrap(true)
        tip:SetText("Также: /cctv_access  ·  grm_cctv_access  ·  grm_cctv_access_debug <ник>")
        tip:SetTextColor(Color(160, 170, 180))

        sheet:AddSheet("CCTV", panel, "icon16/camera.png")
    end
    -- Вкладка встраивается в меню фракций, как только оно появится.
    -- Раньше здесь крутился собственный опрашивающий таймер (0.5 с × 24) —
    -- и так в шести модулях доступов. Теперь единое ожидание условия
    -- GRM.Boot.When: одна проверка на всех, с таймаутом и без «вечных» реп.
    hook.Add("GRM_FactionsAdmin_BuildTabs", "GRM_CCTVAccess_Tab", installFactionsMenuIntegration)

    print("[GRM CCTV] Access Manager client loaded")
end


if GRM.Access and GRM.Access.Register then
    GRM.Access.Register("cctv.view", {
        label = "Видеонаблюдение: просмотр камер", scope = "character",
        factionPerm = "cctv_view",
        levels = { police = true, military = true, special = true, admin = true },
    })
    GRM.Access.Register("cctv.manage", {
        label = "Видеонаблюдение: настройка камер и серверов", scope = "character",
        factionPerm = "cctv_manage",
        levels = { police = true, military = true, admin = true },
    })
end

--[[ Модуль представляется общему реестру GRM.Modules: соседи знают, что он
     есть, а шина обновлений сама позовёт его при смене прав, состава,
     должности или персонажа. ]]
if GRM.Modules and GRM.Modules.Register then
    GRM.Modules.Register("cctv", {
        label = "Видеонаблюдение",
        version = (GRM.CCTV and GRM.CCTV.Version) or "1.0.0",
        Depends = { "access" },
        Status = function() return "камеры, серверы записи и мониторы" end,
    })
end
