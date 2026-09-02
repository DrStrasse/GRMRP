--[[--------------------------------------------------------------------
    GRM Phone Access Manager
    Модульная интерактивная настройка доступа к оборудованию телефонии:
      • АТС
      • Прослушка
      • Компьютер мониторинга связи

    Интеграция:
      • читает глобальную таблицу Factions из factions.lua / sh_factions.lua;
      • на клиенте использует FactionsData, если она есть;
      • добавляет отдельное меню /phone_access;
      • пытается добавить вкладку/кнопку в админ-меню фракций.

    Файл сохранения:
      garrysmod/data/grm_phone/access.json
--------------------------------------------------------------------]]

if SERVER then
    AddCSLuaFile()
end

GRM = GRM or {}
GRM.Phone = GRM.Phone or {}
GRM.Phone.AccessManager = GRM.Phone.AccessManager or {}
local AM = GRM.Phone.AccessManager

local NET_REQ    = "GRM_PhoneAccess_Request"
local NET_DATA   = "GRM_PhoneAccess_Data"
local NET_SAVE   = "GRM_PhoneAccess_Save"
local NET_RESULT = "GRM_PhoneAccess_Result"

local ACCESS_DIR = "grm_phone"
local ACCESS_FILE = ACCESS_DIR .. "/access.json"

AM.Config = AM.Config or {
    SuperAdminBypass = true,
    AdminBypass = false,
}

local function deepCopy(t)
    return istable(t) and table.Copy(t) or {}
end

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
    local ck = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply)) or sid64
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
    if not istable(t) or not key then return false end
    if istable(t[factionName]) and t[factionName][key] == true then
        return true
    end
    if istable(t["*"]) and t["*"][key] == true then
        return true
    end
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
        if not file.Exists(ACCESS_DIR, "DATA") then
            file.CreateDir(ACCESS_DIR)
        end
    end

    function AM.Load()
        ensureDir()
        if GRM.Persistence and GRM.Persistence.LoadJSON then
            local data = GRM.Persistence.LoadJSON(ACCESS_FILE, { version = 1 })
            AM.Data = normalizeAccess(data)
            return AM.Data
        end
        if not file.Exists(ACCESS_FILE, "DATA") then AM.Data = normalizeAccess({}) return AM.Data end
        local raw = file.Read(ACCESS_FILE, "DATA") or ""
        local ok, data = pcall(util.JSONToTable, raw, false, true)
        AM.Data = normalizeAccess(ok and data or {})
        return AM.Data
    end

    function AM.Save(data)
        ensureDir()
        AM.Data = normalizeAccess(data or AM.Data or {})
        AM.Data.version = 1
        if GRM.Persistence and GRM.Persistence.SaveJSON then
            return GRM.Persistence.SaveJSON(ACCESS_FILE, AM.Data, { version = 1 })
        end
        local encoded = util.TableToJSON(AM.Data, true)
        file.Write(ACCESS_FILE, encoded)
        return file.Read(ACCESS_FILE, "DATA") == encoded
    end

    AM.Load()

    -- Сборщик снимка фракций — общий для CCTV- и телефонного редакторов
    -- доступа (волна дедупа 1): GRM.Core.FactionAccessSnapshot.
    local buildFactionsPayload = GRM.Core.FactionAccessSnapshot

    local function sendResult(ply, ok, msg)
        if not IsValid(ply) then return end
        net.Start(NET_RESULT)
            net.WriteBool(ok and true or false)
            net.WriteString(msg or "")
        net.Send(ply)
    end

    local function sendData(ply)
        if not IsValid(ply) then return end
        if not ply:IsSuperAdmin() then
            sendResult(ply, false, "Только superadmin может настраивать доступ к телефонии.")
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
    net.Receive(NET_REQ, function(bits, ply)
        if adminGuard(ply, "phone.access.open", bits, 1024) then sendData(ply) end
    end)

    net.Receive(NET_SAVE, function(bits, ply)
        if not adminGuard(ply, "phone.access.save", bits, 524288) then return end
        local data = normalizeAccess(net.ReadTable() or {})
        local ok = AM.Save(data)
        if ok and GRM.Audit and GRM.Audit.Write then GRM.Audit.Write("access", "phone.legacy.save", ply, {}, {}) end
        sendResult(ply, ok == true, ok and "Доступ к оборудованию телефонии сохранён." or "Ошибка записи доступа.")
        if ok then sendData(ply) end
    end)

    local function hasAccessByData(ply)
        if not IsValid(ply) then return false, "invalid" end
        local cfg = AM.Config or {}
        if cfg.SuperAdminBypass ~= false and ply:IsSuperAdmin() then return true, "superadmin" end
        if GRM.Access and GRM.Access.Explicit then
            local decision, source = GRM.Access.Explicit(ply, "phone.equipment.use")
            if decision ~= nil then return decision == true, source or "core_access" end
        end
        if cfg.AdminBypass and ply:IsAdmin() then return true, "admin" end

        AM.Data = normalizeAccess(AM.Data or AM.Load())
        local data = AM.Data

        local factionName, role, department = getFactionInfo(ply)
        if not factionName then return false, "no_faction" end

        if data.Factions[factionName] == true then return true, "faction:" .. factionName end
        if nestedAccess(data.Roles, factionName, role) then return true, "role:" .. tostring(role) end
        if nestedAccess(data.Departments, factionName, department) then return true, "department:" .. tostring(department) end

        -- Fallback для старого ручного конфига sh_grm_phone_config.lua, если кто-то всё ещё им пользуется.
        local old = GRM.Phone and GRM.Phone.Config and GRM.Phone.Config.Access or nil
        if istable(old) then
            if istable(old.AllowedFactions) and old.AllowedFactions[factionName] == true then return true, "old_config_faction" end
            if nestedAccess(old.AllowedRoles, factionName, role) then return true, "old_config_role" end
            if nestedAccess(old.AllowedDepartments, factionName, department) then return true, "old_config_department" end
        end

        return false, "no_rule faction=" .. tostring(factionName) .. " role=" .. tostring(role) .. " department=" .. tostring(department)
    end

    -- Главная интеграция: переопределяем проверку доступа из grm_phone_system.
    -- ВАЖНО: sv_grm_phone.lua может загрузиться ПОСЛЕ этого файла и перезаписать
    -- GRM.Phone.HasEquipmentAccess. Поэтому ставим override несколько раз после старта.
    function AM.InstallAccessOverride()
        GRM.Phone = GRM.Phone or {}
        GRM.Phone.HasEquipmentAccess = function(ply)
            local ok = hasAccessByData(ply)
            if ok == true then return true end
            --[[ Единый слой доступа — второй законный источник: право можно
                 выдать в /admin (capability phone.equipment) или в доступах
                 организации (phone_equipment). Так модуль «знает» об общих
                 правах, а не только о своей таблице. ]]
            if GRM.Access and GRM.Access.Can and GRM.Access.Can(ply, "phone.equipment") then
                return true
            end
            return false
        end
        GRM.Phone.GetEquipmentAccessDebug = function(ply)
            local ok, reason = hasAccessByData(ply)
            local factionName, role, department = getFactionInfo(ply)
            return ok, reason, factionName, role, department, normalizeAccess(AM.Data or {})
        end
    end

    AM.InstallAccessOverride()
    timer.Simple(0, AM.InstallAccessOverride)
    timer.Simple(1, AM.InstallAccessOverride)
    timer.Simple(3, AM.InstallAccessOverride)
    timer.Simple(6, AM.InstallAccessOverride)

    concommand.Add("grm_phone_access_reload", function(ply)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        AM.Load()
        AM.InstallAccessOverride()
        if IsValid(ply) then ply:ChatPrint("[Телефония] Доступ перезагружен.") else print("[Телефония] Доступ перезагружен.") end
    end)

    concommand.Add("grm_phone_access_debug", function(ply, _, args)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        local target = ply
        local query = args[1]
        if query and query ~= "" then
            for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                if string.find(string.lower(p:Nick()), string.lower(query), 1, true) or p:SteamID() == query or p:SteamID64() == query then
                    target = p
                    break
                end
            end
        end
        if not IsValid(target) then
            print("[PhoneAccessDebug] target not found")
            return
        end
        local ok, reason, factionName, role, department, data = GRM.Phone.GetEquipmentAccessDebug(target)
        local lines = {
            "[PhoneAccessDebug] target=" .. target:Nick() .. " " .. target:SteamID(),
            "access=" .. tostring(ok) .. " reason=" .. tostring(reason),
            "faction=" .. tostring(factionName) .. " role=" .. tostring(role) .. " department=" .. tostring(department),
            "saved factions=" .. table.concat(table.GetKeys(data.Factions or {}), ", "),
        }
        for _, line in ipairs(lines) do
            if IsValid(ply) then ply:ChatPrint(line) else print(line) end
        end
    end)

    print("[GRM Phone] Access Manager loaded and override installed: data/" .. ACCESS_FILE)
end

-- ============================================================
-- CLIENT
-- ============================================================

if CLIENT then
    surface.CreateFont("GRMPhoneAccess_Title", { font = "Roboto", size = 20, weight = 700, extended = true })
    surface.CreateFont("GRMPhoneAccess_Normal", { font = "Roboto", size = 14, weight = 500, extended = true })
    surface.CreateFont("GRMPhoneAccess_Small", { font = "Roboto", size = 12, weight = 400, extended = true })

    local THEME = {
        bg = Color(24, 26, 32, 245),
        panel = Color(35, 38, 48, 240),
        accent = Color(80, 170, 255),
        green = Color(70, 190, 100),
        red = Color(210, 70, 60),
        text = Color(235, 235, 240),
        dim = Color(170, 175, 185),
    }

    local function sortedKeys(t)
        local out = {}
        for k in pairs(t or {}) do out[#out + 1] = k end
        table.sort(out)
        return out
    end

    local function makeButton(parent, text, color)
        local b = vgui.Create("DButton", parent)
        b:SetText(text)
        b:SetFont("GRMPhoneAccess_Normal")
        b:SetTextColor(color_white)
        b.Paint = function(s, w, h)
            local c = s:IsHovered() and Color(math.min(color.r + 25, 255), math.min(color.g + 25, 255), math.min(color.b + 25, 255)) or color
            draw.RoundedBox(6, 0, 0, w, h, c)
        end
        return b
    end

    local function accessValue(data, section, factionName, key)
        data[section] = data[section] or {}
        if section == "Factions" then
            return data.Factions[factionName] == true
        end
        data[section][factionName] = data[section][factionName] or {}
        return data[section][factionName][key] == true
    end

    local function setAccessValue(data, section, factionName, key, value)
        data[section] = data[section] or {}
        if section == "Factions" then
            data.Factions[factionName] = value and true or nil
            return
        end
        data[section][factionName] = data[section][factionName] or {}
        data[section][factionName][key] = value and true or nil
        if table.Count(data[section][factionName]) <= 0 then
            data[section][factionName] = nil
        end
    end

    local function openAccessMenu(factions, accessData, config)
        accessData = normalizeAccess(accessData)
        factions = factions or {}

        local frame = vgui.Create("DFrame")
        frame:SetTitle("")
        frame:SetSize(860, 660)
        frame:Center()
        frame:MakePopup()
        frame.Paint = function(_, w, h)
            draw.RoundedBox(8, 0, 0, w, h, THEME.bg)
            draw.RoundedBoxEx(8, 0, 0, w, 34, Color(35, 35, 45), true, true, false, false)
            draw.SimpleText("Доступ к оборудованию телефонии", "GRMPhoneAccess_Title", 12, 17, THEME.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end

        local tabs = vgui.Create("DPropertySheet", frame)
        tabs:Dock(FILL)
        tabs:DockMargin(8, 42, 8, 52)

        local function addFactionTab()
            local panel = vgui.Create("DScrollPanel")
            panel:DockPadding(6, 6, 6, 6)

            local help = vgui.Create("DLabel", panel)
            help:Dock(TOP)
            help:SetTall(38)
            help:SetWrap(true)
            help:SetFont("GRMPhoneAccess_Small")
            help:SetTextColor(THEME.dim)
            help:SetText("Отмеченные фракции полностью получают доступ к АТС, прослушке и компьютеру мониторинга связи.")

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
                chk:SetFont("GRMPhoneAccess_Normal")
                chk:SetTextColor(THEME.text)
                chk:SetValue(accessValue(accessData, "Factions", factionName))
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
            combo:SetWide(280)
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
                    chk:SetFont("GRMPhoneAccess_Normal")
                    chk:SetTextColor(THEME.text)
                    chk:SetValue(accessValue(accessData, section, factionName, key))
                    chk.OnChange = function(_, val)
                        setAccessValue(accessData, section, factionName, key, val)
                    end
                end
            end

            for _, factionName in ipairs(sortedKeys(factions)) do
                combo:AddChoice(factionName)
            end

            combo.OnSelect = function(_, _, value)
                rebuild(value)
            end

            tabs:AddSheet(title, panel, icon)
        end

        addFactionTab()
        addNestedTab("Ранги", "Roles", "Roles", "icon16/user.png")
        addNestedTab("Отделы", "Departments", "Departments", "icon16/brick.png")

        local bottom = vgui.Create("DPanel", frame)
        bottom:Dock(BOTTOM)
        bottom:SetTall(44)
        bottom:SetPaintBackground(false)

        local save = makeButton(bottom, "Сохранить доступ", THEME.green)
        save:Dock(RIGHT)
        save:SetWide(180)
        save:DockMargin(6, 6, 8, 6)
        save.DoClick = function()
            net.Start(NET_SAVE)
                net.WriteTable(accessData)
            net.SendToServer()
        end

        local reload = makeButton(bottom, "Обновить из factions", THEME.accent)
        reload:Dock(RIGHT)
        reload:SetWide(180)
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
    end)

    function AM.OpenMenu()
        net.Start(NET_REQ)
        net.SendToServer()
    end

    concommand.Add("grm_phone_access", AM.OpenMenu)

    hook.Add("PlayerSayTransform", "GRM_PhoneAccess_ChatCommand", function(ply, datapack)
        if ply ~= LocalPlayer() then return end
        local msg = string.lower(string.Trim(datapack[1] or ""))
        if msg == "/phone_access" or msg == "!phone_access" or msg == "/phoneaccess" or msg == "!phoneaccess" then
            AM.OpenMenu()
            datapack[1] = ""
            return
        end
    end)

    -- Интеграция с меню фракций: добавляем вкладку, если OpenAdminMenu уже есть.
    -- v18.08: вкладка встраивается штатным хуком меню организаций
    -- (работает и в старом /factions, и в Unified UI). Раньше модуль
    -- ПОДМЕНЯЛ глобальную OpenAdminMenu и искал DPropertySheet внутри окна —
    -- в новом меню такого листа нет, поэтому вкладка просто не появлялась.
    local function installFactionsMenuIntegration(sheet)
        if not IsValid(sheet) then return end

        for _, item in ipairs(sheet.Items or {}) do
            if item.Tab and item.Tab:GetText() == "Телефония" then return end
        end

        local panel = vgui.Create("DPanel")
        panel:SetPaintBackground(false)

        local label = vgui.Create("DLabel", panel)
        label:Dock(TOP)
        label:SetTall(60)
        label:DockMargin(12, 12, 12, 4)
        label:SetWrap(true)
        label:SetText("Настройка доступа фракций, рангов и отделов к оборудованию телефонии: АТС, прослушка, мониторинг связи.")
        label:SetTextColor(Color(220, 220, 230))

        local button = makeButton(panel, "Открыть настройку доступа телефонии", THEME.accent)
        button:Dock(TOP)
        button:SetTall(36)
        button:DockMargin(12, 8, 12, 0)
        button.DoClick = AM.OpenMenu

        sheet:AddSheet("Телефония", panel, "icon16/telephone.png")
    end
    -- Вкладка встраивается в меню фракций, как только оно появится.
    -- Раньше здесь крутился собственный опрашивающий таймер (0.5 с × 20) —
    -- и так в шести модулях доступов. Теперь единое ожидание условия
    -- GRM.Boot.When: одна проверка на всех, с таймаутом и без «вечных» реп.
    hook.Add("GRM_FactionsAdmin_BuildTabs", "GRM_PhoneAccess_Tab", installFactionsMenuIntegration)

    print("[GRM Phone] Access Manager client loaded")
end


if GRM.Access and GRM.Access.Register then
    GRM.Access.Register("phone.equipment", {
        label = "Связь: доступ к оборудованию (АТС, терминалы)", scope = "character",
        factionPerm = "phone_equipment",
        levels = { police = true, military = true, special = true, admin = true },
    })
    GRM.Access.Register("phone.wiretap", {
        label = "Связь: прослушка телефонов и помещений", scope = "character",
        factionPerm = "phone_wiretap",
        levels = { police = true, military = true, special = true, justice = true, admin = true },
    })
end

--[[ Модуль представляется общему реестру GRM.Modules: соседи знают, что он
     есть, а шина обновлений сама позовёт его при смене прав, состава,
     должности или персонажа. ]]
if GRM.Modules and GRM.Modules.Register then
    GRM.Modules.Register("phone_access", {
        label = "Доступ к оборудованию связи",
        version = (GRM.Phone and GRM.Phone.Version) or "1.0.0",
        Depends = { "access", "mobile" },
        Status = function() return "доступ к АТС, прослушке и терминалам связи" end,
    })
end
