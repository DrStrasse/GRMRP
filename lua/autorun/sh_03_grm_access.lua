--[[ GRM Access Core v1.0.0: capability registry and unified grants. ]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Access = GRM.Access or {}
local A = GRM.Access
A.Version = "1.1.0"
A.Capabilities = A.Capabilities or {}
A.Providers = A.Providers or {}
A.Grants = A.Grants or {}

local function validID(id)
    return isstring(id) and id:match("^[a-z][a-z0-9_]*%.[a-z0-9_%.]+$") ~= nil
end

function A.Register(id, definition)
    id = string.lower(string.Trim(tostring(id or "")))
    if not validID(id) then return false, "invalid_capability_id" end
    definition = istable(definition) and definition or {}
    local current = A.Capabilities[id] or {}
    for key, value in pairs(definition) do current[key] = value end
    current.id = id
    current.label = tostring(current.label or id)
    current.scope = current.scope == "account" and "account" or "character"
    A.Capabilities[id] = current
    return true
end

function A.RegisterProvider(id, priority, callback)
    if not isfunction(callback) then return false, "callback_required" end
    A.Providers[tostring(id)] = { priority = tonumber(priority) or 0, callback = callback }
    return true
end

function A.Actor(ply)
    local actor = {
        player = ply,
        accountKey = IsValid(ply) and tostring(ply:SteamID64() or "") or "",
        characterKey = "",
        faction = IsValid(ply) and ply:GetNWString("GRM_Faction", "") or "",
        role = IsValid(ply) and ply:GetNWString("GRM_Role", "") or "",
        department = IsValid(ply) and ply:GetNWString("GRM_Department", "") or "",
    }
    if GRM.Identity and GRM.Identity.CharacterKey then actor.characterKey = GRM.Identity.CharacterKey(ply) end
    if actor.characterKey == "" and actor.accountKey ~= "" then actor.characterKey = actor.accountKey .. ":char1" end
    return actor
end

local SUBJECT_PRIORITY = { everyone = 0, faction = 10, role = 20, department = 20, account = 30, character = 40 }
local function grantMatches(grant, actor, capability)
    if not istable(grant) or grant.enabled == false then return false end
    if grant.capability ~= "*" and grant.capability ~= capability then return false end
    local kind, subject = tostring(grant.subjectType or ""), tostring(grant.subject or "")
    if kind == "everyone" then return true end
    if kind == "character" then return subject ~= "" and subject == actor.characterKey end
    if kind == "account" then return subject ~= "" and subject == actor.accountKey end
    if kind == "faction" then return subject ~= "" and subject == actor.faction end
    if kind == "role" then
        return subject ~= "" and subject == actor.role and (not grant.faction or grant.faction == "" or grant.faction == actor.faction)
    end
    if kind == "department" then
        return subject ~= "" and subject == actor.department and (not grant.faction or grant.faction == "" or grant.faction == actor.faction)
    end
    return false
end

local function explicitDecision(actor, capability)
    local best, decision, source = -1, nil, nil
    for index, grant in ipairs(A.Grants or {}) do
        if grantMatches(grant, actor, capability) then
            local priority = SUBJECT_PRIORITY[tostring(grant.subjectType)] or -1
            local allow = grant.allow ~= false
            if priority > best or (priority == best and allow == false) then
                best, decision, source = priority, allow, "grant:" .. tostring(index)
            end
        end
    end
    return decision, source
end

-- Explicit returns nil when Core has no assignment. Legacy Can* adapters use
-- this to honour central grants without recursively calling A.Check.
function A.Explicit(ply, capability)
    capability = string.lower(string.Trim(tostring(capability or "")))
    if not A.Capabilities[capability] or not (IsValid(ply) and ply.IsPlayer and ply:IsPlayer()) then return nil end
    if A.Capabilities[capability].superadminBypass ~= false and ply:IsSuperAdmin() then return true, "superadmin" end
    return explicitDecision(A.Actor(ply), capability)
end

function A.Check(ply, capability, context)
    capability = string.lower(string.Trim(tostring(capability or "")))
    local definition = A.Capabilities[capability]
    if not definition then return false, "unknown_capability" end
    if not (IsValid(ply) and ply.IsPlayer and ply:IsPlayer()) then return false, "invalid_actor" end
    if definition.superadminBypass ~= false and ply:IsSuperAdmin() then return true, "superadmin" end

    local actor = A.Actor(ply)
    local decision, source = explicitDecision(actor, capability)
    if decision ~= nil then return decision, source end

    local providers = {}
    for id, provider in pairs(A.Providers) do providers[#providers + 1] = { id = id, value = provider } end
    table.sort(providers, function(a, b)
        if a.value.priority == b.value.priority then return a.id < b.id end
        return a.value.priority > b.value.priority
    end)
    for _, row in ipairs(providers) do
        local ok, allowed, reason = pcall(row.value.callback, ply, capability, context or {}, actor, definition)
        if ok and allowed ~= nil then return allowed == true, reason or ("provider:" .. row.id) end
    end

    if isfunction(definition.legacy) then
        local ok, allowed, reason = pcall(definition.legacy, ply, context or {}, actor)
        if ok and allowed ~= nil then return allowed == true, reason or "legacy" end
    end
    return definition.default == true, "default"
end

function A.Can(ply, capability, context)
    return A.Check(ply, capability, context)
end

--[[--------------------------------------------------------------------
    ЕДИНАЯ ТОЧКА ПРАВА (заказ владельца 22.08: «все модули должны знать
    друг друга»).

    Раньше каждый модуль спрашивал права по-своему: кто-то GRM.Access,
    кто-то права организации, кто-то уровень госбазы, кто-то просто
    IsSuperAdmin. Отсюда и «выдал доступ — не работает»: выдал в одном
    месте, а модуль смотрит в другое.

    Теперь у capability есть штатные источники, и они спрашиваются в
    понятном порядке:
       1) явные гранты GRM.Access (точечная выдача);
       2) админ-платформа (/admin → Привилегии)   — провайдер в admin_core;
       3) доступы организаций (/factions → Доступы) — правило имени:
          capability `plates.issue` ↔ право организации `plates_issue`;
       4) уровень госбазы (police / military / justice / admin ...) —
          если capability объявила `levels = { police = true }`.
    Ответ всегда с ПРИЧИНОЙ: A.Why(ply, cap) печатает её человеку.
----------------------------------------------------------------------]]

--- Имя права организации для capability: точки → подчёркивания.
function A.FactionPermName(capability)
    capability = string.lower(string.Trim(tostring(capability or "")))
    if capability == "" then return "" end
    local def = A.Capabilities[capability]
    if def and isstring(def.factionPerm) then return def.factionPerm end
    return (string.gsub(capability, "%.", "_"))
end

if SERVER then
    -- Доступы организаций: /factions → «Доступы»
    A.RegisterProvider("grm_faction_perms", 40, function(ply, capability)
        local PERMS = GRM.FactionPerms
        if not (PERMS and PERMS.PlayerHasPermission) then return nil end
        local name = A.FactionPermName(capability)
        if name == "" or not (PERMS.Permissions and PERMS.Permissions[name]) then return nil end
        if PERMS.PlayerHasPermission(ply, name) == true then return true, "faction_perm:" .. name end
        return nil
    end)

    -- Уровень госбазы: capability объявляет, какие уровни ей подходят
    A.RegisterProvider("grm_pcboard_level", 30, function(ply, capability, _, _, definition)
        local levels = definition and definition.levels
        if not istable(levels) then return nil end
        if not (GRM.PCBoard and GRM.PCBoard.PlayerLevel) then return nil end
        local level = GRM.PCBoard.PlayerLevel(ply)
        if level and levels[level] then return true, "pcboard:" .. tostring(level) end
        return nil
    end)
end

--- Почему право есть или нет. Возвращает: можно, причина, список источников.
function A.Why(ply, capability)
    capability = string.lower(string.Trim(tostring(capability or "")))
    local allowed, reason = A.Check(ply, capability)
    local sources = {}
    local def = A.Capabilities[capability]
    if not def then
        sources[#sources + 1] = "capability не объявлена — модуль её не регистрировал"
    else
        sources[#sources + 1] = "право организации: " .. A.FactionPermName(capability)
        --[[ Право может прийти и от ДОЛЖНОСТИ (ось v5), а не только от
             звания. Показываем это в ответе, иначе человек ищет причину
             в правах звания и не находит. ]]
        if IsValid(ply) and ply.GetNWString then
            local posID = ply:GetNWString("GRM_Position", "")
            if posID ~= "" then
                local posName = ply:GetNWString("GRM_PositionDisplay", "")
                sources[#sources + 1] = "должность: "
                    .. (posName ~= "" and posName or posID) .. " [" .. posID .. "]"
            else
                sources[#sources + 1] = "должность: не назначена (действует только звание)"
            end
        end
        if istable(def.levels) then
            local names = {}
            for lv in pairs(def.levels) do names[#names + 1] = lv end
            table.sort(names)
            sources[#sources + 1] = "уровни госбазы: " .. table.concat(names, ", ")
        end
    end
    return allowed == true, tostring(reason or "?"), sources
end

if concommand then
concommand.Add("grm_access_check", function(caller, _, args)
    local cap = string.lower(tostring(args and args[1] or ""))
    local target = caller
    if SERVER and args and args[2] then
        local needle = string.lower(args[2])
        for _, p in ipairs(player.GetAll()) do
            if string.find(string.lower(p:Nick()), needle, 1, true) then target = p break end
        end
    end
    local function say(t) if IsValid(caller) then caller:ChatPrint(t) else print(t) end end
    if cap == "" then
        say("[Доступ] как пользоваться: grm_access_check <право> [ник]")
        local list = {}
        for id in pairs(A.Capabilities) do list[#list + 1] = id end
        table.sort(list)
        say("[Доступ] известные права: " .. table.concat(list, ", "))
        return
    end
    local allowed, reason, sources = A.Why(target, cap)
    say(("[Доступ] %s → %s (%s)"):format(cap, allowed and "ЕСТЬ" or "нет", reason))
    for _, line in ipairs(sources) do say("   · " .. line) end
end)
end

if GRM.Modules and GRM.Modules.Register then
    GRM.Modules.Register("access", {
        label = "Единый слой доступа", version = A.Version,
        Status = function()
            local n = 0
            for _ in pairs(A.Capabilities) do n = n + 1 end
            return ("прав объявлено: %d, источников: гранты, /admin, организации, госбаза"):format(n)
        end,
    })
end

function A.List()
    local out = {}
    for id, definition in pairs(A.Capabilities) do out[#out + 1] = { id = id, label = definition.label, scope = definition.scope } end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

local CORE_CAPABILITIES = {
    ["medical.computer.use"] = "Медицинский компьютер: вход",
    ["medical.patient.edit"] = "Медицина: изменение карты пациента",
    ["wanted.civil.view"] = "Розыск: просмотр",
    ["wanted.civil.edit"] = "Розыск: изменение дел",
    ["fire.dispatch"] = "Пожарная служба: диспетчер",
    ["fire.fight"] = "Пожарная служба: работа на месте",
    ["cctv.view"] = "CCTV: просмотр",
    ["cctv.configure"] = "CCTV: настройка",
    ["phone.equipment.use"] = "Телефония: оборудование",
    ["world.perm.manage"] = "Мир: управление постоянными объектами",
    ["doc.passport.issue"] = "Документы: выдача паспорта",
    ["doc.weapon_license.issue"] = "Документы: лицензия на оружие",
}
for id, label in pairs(CORE_CAPABILITIES) do A.Register(id, { label = label, scope = "character" }) end
A.Capabilities["world.perm.manage"].scope = "account"

if SERVER then
    local FILE = "grm_core/access_grants.json"
    function A.Load()
        local defaults = { version = 1, grants = {} }
        local data = GRM.Persistence and GRM.Persistence.LoadJSON and GRM.Persistence.LoadJSON(FILE, defaults, { version = 1 }) or defaults
        A.Grants = istable(data) and istable(data.grants) and data.grants or {}
        return A.Grants
    end
    function A.Save()
        if not (GRM.Persistence and GRM.Persistence.SaveJSON) then return false, "persistence_unavailable" end
        return GRM.Persistence.SaveJSON(FILE, { version = 1, grants = A.Grants }, { version = 1 })
    end
    function A.SetGrants(grants)
        if not istable(grants) then return false, "grants_required" end
        local clean = {}
        for _, grant in ipairs(grants) do
            if #clean >= 512 then break end
            local capability = istable(grant) and string.lower(tostring(grant.capability or "")) or ""
            local kind = istable(grant) and tostring(grant.subjectType or "") or ""
            local subject = istable(grant) and string.Trim(tostring(grant.subject or "")) or ""
            local faction = istable(grant) and string.Trim(tostring(grant.faction or "")) or ""
            local validSubject = kind == "everyone"
                or (kind == "character" and GRM.Identity and GRM.Identity.IsCharacterKey and GRM.Identity.IsCharacterKey(subject))
                or (kind == "account" and subject:match("^%d+$") ~= nil)
                or ((kind == "faction" or kind == "role" or kind == "department") and subject ~= "")
            if istable(grant) and (capability == "*" or A.Capabilities[capability]) and SUBJECT_PRIORITY[kind] and validSubject then
                clean[#clean + 1] = {
                    capability = capability, subjectType = kind, subject = kind == "everyone" and "" or subject,
                    faction = faction, allow = grant.allow ~= false, enabled = grant.enabled ~= false,
                }
            end
        end
        A.Grants = clean
        return A.Save()
    end
    A.Load()

    -- Legacy systems remain authoritative until their UI is migrated.
    A.Capabilities["fire.dispatch"].legacy = function(ply)
        local am = GRM.Fire and GRM.Fire.AccessManager
        return am and am.CanControl and am.CanControl(ply) or nil, "legacy_fire_control"
    end
    A.Capabilities["fire.fight"].legacy = function(ply)
        local am = GRM.Fire and GRM.Fire.AccessManager
        return am and am.CanView and am.CanView(ply) or nil, "legacy_fire_view"
    end
    A.Capabilities["wanted.civil.view"].legacy = function(ply)
        local am = GRM.Wanted and GRM.Wanted.AccessManager
        return am and am.CanView and am.CanView(ply) or nil, "legacy_wanted_view"
    end
    A.Capabilities["wanted.civil.edit"].legacy = function(ply)
        local am = GRM.Wanted and GRM.Wanted.AccessManager
        return am and am.CanEdit and am.CanEdit(ply) or nil, "legacy_wanted_edit"
    end
    A.Capabilities["cctv.view"].legacy = function(ply)
        if GRM.CCTV and GRM.CCTV.CanView then return GRM.CCTV.CanView(ply), "legacy_cctv" end
    end
    A.Capabilities["cctv.configure"].legacy = function(ply, context)
        if GRM.CCTV and GRM.CCTV.CanConfigure then return GRM.CCTV.CanConfigure(ply, context.entity), "legacy_cctv" end
    end
    A.Capabilities["phone.equipment.use"].legacy = function(ply)
        if GRM.Phone and GRM.Phone.HasEquipmentAccess then return GRM.Phone.HasEquipmentAccess(ply), "legacy_phone" end
    end
end

-- Unified capability editor. Old domain access windows remain available
-- during migration; this editor adds explicit overrides above them.
local NET_OPEN = "GRM_AccessCore_Open"
local NET_SAVE = "GRM_AccessCore_Save"
local NET_RESULT = "GRM_AccessCore_Result"

if SERVER then
    util.AddNetworkString(NET_OPEN)
    util.AddNetworkString(NET_SAVE)
    util.AddNetworkString(NET_RESULT)

    local function factionPayload()
        local out = {}
        for name, faction in pairs(Factions or {}) do
            if istable(faction) then
                local roles, departments = {}, {}
                for role in pairs(faction.Roles or {}) do roles[#roles + 1] = tostring(role) end
                for department in pairs(faction.Departments or {}) do departments[#departments + 1] = tostring(department) end
                table.sort(roles); table.sort(departments)
                out[#out + 1] = { name = tostring(name), roles = roles, departments = departments }
            end
        end
        table.sort(out, function(a, b) return a.name < b.name end)
        return out
    end

    local function sendEditor(ply)
        if not (IsValid(ply) and ply:IsSuperAdmin()) then return end
        net.Start(NET_OPEN)
            net.WriteTable(A.List())
            net.WriteTable(factionPayload())
            net.WriteTable(A.Grants or {})
        net.Send(ply)
    end

    local function guard(ply, key, bits, maxBits)
        if not (IsValid(ply) and ply:IsSuperAdmin()) then return false end
        if GRM.Net and GRM.Net.Guard then
            return GRM.Net.Guard(ply, key, { rate = 0.75, burst = 2, maxBits = maxBits,
                permission = function(actor) return actor:IsSuperAdmin() end }, { bits = bits }) == true
        end
        return true
    end

    net.Receive(NET_OPEN, function(bits, ply)
        if not guard(ply, "access.editor.open", bits, 1024) then return end
        sendEditor(ply)
    end)
    net.Receive(NET_SAVE, function(bits, ply)
        if not guard(ply, "access.editor.save", bits, 1048576) then return end
        local incoming = net.ReadTable()
        local before = #(A.Grants or {})
        local ok, reason = A.SetGrants(incoming)
        if ok and GRM.Audit and GRM.Audit.Write then
            GRM.Audit.Write("access", "grants.save", ply, { file = "grm_core/access_grants.json" }, { before = before, after = #A.Grants })
        end
        net.Start(NET_RESULT); net.WriteBool(ok == true); net.WriteString(tostring(reason or (ok and "saved" or "error"))); net.Send(ply)
        if ok then sendEditor(ply) end
    end)

    local function openEditor(ply)
        if not (IsValid(ply) and ply:IsSuperAdmin()) then
            if IsValid(ply) then ply:ChatPrint("[GRM Access] Только superadmin.") end
            return
        end
        sendEditor(ply)
    end
    concommand.Add("grm_access", openEditor)
    hook.Add("PlayerSay", "GRM_AccessCore_Chat", function(ply, text)
        local msg = string.lower(string.Trim(tostring(text or "")))
        if msg == "/grm_access" or msg == "!grm_access" or msg == "/доступы" then openEditor(ply) return "" end
    end)

end

if CLIENT then
    surface.CreateFont("GRMCoreAccessTitle", { font = "Roboto", size = 24, weight = 800, extended = true })
    surface.CreateFont("GRMCoreAccessText", { font = "Roboto", size = 16, weight = 500, extended = true })
    surface.CreateFont("GRMCoreAccessSmall", { font = "Roboto", size = 13, weight = 400, extended = true })
    local COL = { bg = Color(17, 20, 26, 252), panel = Color(27, 32, 41), row = Color(35, 41, 52),
        accent = Color(170, 45, 60), green = Color(65, 170, 105), red = Color(195, 70, 75),
        text = Color(235, 238, 242), dim = Color(150, 160, 175) }

    local function button(parent, text, color)
        local btn = vgui.Create("DButton", parent); btn:SetText(""); btn.Label = text; btn.Col = color or COL.accent
        btn.Paint = function(self, w, h)
            draw.RoundedBox(6, 0, 0, w, h, self:IsHovered() and Color(self.Col.r + 18, self.Col.g + 18, self.Col.b + 18) or self.Col)
            draw.SimpleText(self.Label, "GRMCoreAccessText", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        return btn
    end

    local function sortedFactionNames(factions)
        local out = {}; for _, row in ipairs(factions or {}) do out[#out + 1] = row.name end; return out
    end

    local function openEditor(capabilities, factions, grants)
        if IsValid(A._editor) then A._editor:Remove() end
        local frame = vgui.Create("DFrame"); frame:SetSize(ScrW() * .94, ScrH() * .92); frame:Center(); frame:SetTitle("")
        frame:MakePopup(); frame:ShowCloseButton(true); frame:SetSizable(true); frame:SetMinWidth(1050); frame:SetMinHeight(650)
        frame.Paint = function(_, w, h)
            draw.RoundedBox(10, 0, 0, w, h, COL.bg)
            draw.SimpleText("GRM CORE • ЕДИНЫЕ ПРАВА", "GRMCoreAccessTitle", 24, 22, COL.text)
            draw.SimpleText("Явные назначения имеют приоритет над старыми матрицами доступа", "GRMCoreAccessSmall", 24, 51, COL.dim)
        end
        A._editor = frame
        if GRM.UI and GRM.UI.Track then GRM.UI.Track("core.access", frame) end

        local work = table.Copy(grants or {})
        local selectedCapability = capabilities[1] and capabilities[1].id or ""
        local selectedGrant = nil
        local left = vgui.Create("DPanel", frame); left.Paint = function(_,w,h) draw.RoundedBox(8,0,0,w,h,COL.panel) end
        local middle = vgui.Create("DPanel", frame); middle.Paint = left.Paint
        local right = vgui.Create("DPanel", frame); right.Paint = left.Paint

        local search = vgui.Create("DTextEntry", left); search:SetFont("GRMCoreAccessText"); search:SetPlaceholderText("Поиск capability...")
        local capList = vgui.Create("DListView", left); capList:SetMultiSelect(false); capList:AddColumn("Capability"); capList:AddColumn("Название")
        local grantList = vgui.Create("DListView", middle); grantList:SetMultiSelect(false)
        grantList:AddColumn("Решение"):SetFixedWidth(90); grantList:AddColumn("Тип"):SetFixedWidth(100); grantList:AddColumn("Субъект"); grantList:AddColumn("Фракция")

        local title = vgui.Create("DLabel", right); title:SetFont("GRMCoreAccessTitle"); title:SetTextColor(COL.text); title:SetText("НОВОЕ НАЗНАЧЕНИЕ")
        local typeBox = vgui.Create("DComboBox", right); typeBox:SetFont("GRMCoreAccessText")
        for _, kind in ipairs({"everyone", "faction", "role", "department", "account", "character"}) do typeBox:AddChoice(kind, kind) end
        typeBox:ChooseOptionID(2)
        local factionBox = vgui.Create("DComboBox", right); factionBox:SetFont("GRMCoreAccessText"); factionBox:SetValue("Фракция")
        for _, name in ipairs(sortedFactionNames(factions)) do factionBox:AddChoice(name, name) end
        local subjectBox = vgui.Create("DComboBox", right); subjectBox:SetFont("GRMCoreAccessText"); subjectBox:SetValue("Роль / отдел")
        local subjectEntry = vgui.Create("DTextEntry", right); subjectEntry:SetFont("GRMCoreAccessText"); subjectEntry:SetPlaceholderText("SteamID64 или CharacterKey")
        local hint = vgui.Create("DLabel", right); hint:SetFont("GRMCoreAccessSmall"); hint:SetTextColor(COL.dim); hint:SetWrap(true)
        hint:SetText("Фракция — выберите название. Роль/отдел — сначала фракцию. Account — SteamID64. Character — SteamID64:charN.")
        local allowBtn = button(right, "ДОБАВИТЬ РАЗРЕШЕНИЕ", COL.green)
        local denyBtn = button(right, "ДОБАВИТЬ ЗАПРЕТ", COL.red)
        local deleteBtn = button(middle, "УДАЛИТЬ ВЫБРАННОЕ", COL.red)
        local saveBtn = button(frame, "СОХРАНИТЬ ВСЕ НАЗНАЧЕНИЯ", COL.accent)
        local status = vgui.Create("DLabel", frame); status:SetFont("GRMCoreAccessSmall"); status:SetTextColor(COL.dim); status:SetText("Несохранённые изменения отсутствуют")

        local function factionData(name)
            for _, row in ipairs(factions or {}) do if row.name == name then return row end end
        end
        local function currentKind() local _, data = typeBox:GetSelected(); return data or "faction" end
        local function refreshSubjectControls()
            local kind = currentKind(); local fac = select(2, factionBox:GetSelected()) or ""
            factionBox:SetVisible(kind == "faction" or kind == "role" or kind == "department")
            subjectBox:SetVisible(kind == "role" or kind == "department")
            subjectEntry:SetVisible(kind == "account" or kind == "character")
            subjectBox:Clear()
            local row = factionData(fac); local values = row and (kind == "role" and row.roles or row.departments) or {}
            for _, value in ipairs(values) do subjectBox:AddChoice(value, value) end
            subjectBox:SetValue(kind == "role" and "Выберите роль" or "Выберите отдел")
        end
        typeBox.OnSelect = refreshSubjectControls; factionBox.OnSelect = function() refreshSubjectControls() end

        local function refillCaps(filter)
            capList:Clear(); filter = string.lower(string.Trim(filter or ""))
            for _, cap in ipairs(capabilities or {}) do
                if filter == "" or string.find(string.lower(cap.id .. " " .. cap.label), filter, 1, true) then
                    local line = capList:AddLine(cap.id, cap.label); line.Capability = cap.id
                    if cap.id == selectedCapability then capList:SelectItem(line) end
                end
            end
        end
        local function refillGrants()
            grantList:Clear(); selectedGrant = nil
            for index, grant in ipairs(work) do
                if grant.capability == selectedCapability or selectedCapability == "*" then
                    local line = grantList:AddLine(grant.allow == false and "ЗАПРЕТ" or "РАЗРЕШЕНО", grant.subjectType,
                        grant.subject == "" and "Все" or grant.subject, grant.faction or "")
                    line.GrantIndex = index
                end
            end
        end
        search.OnChange = function(self) refillCaps(self:GetValue()) end
        capList.OnRowSelected = function(_, _, line) selectedCapability = line.Capability or line:GetColumnText(1); refillGrants() end
        grantList.OnRowSelected = function(_, _, line) selectedGrant = line.GrantIndex end

        local function addGrant(allow)
            if selectedCapability == "" then return end
            local kind = currentKind(); local fac = select(2, factionBox:GetSelected()) or ""; local subject = ""
            if kind == "faction" then subject = fac
            elseif kind == "role" or kind == "department" then subject = select(2, subjectBox:GetSelected()) or ""
            elseif kind == "account" or kind == "character" then subject = string.Trim(subjectEntry:GetValue()) end
            if kind ~= "everyone" and subject == "" then status:SetText("Сначала выберите или введите субъект права"); status:SetTextColor(COL.red); return end
            work[#work + 1] = { capability = selectedCapability, subjectType = kind, subject = subject,
                faction = (kind == "role" or kind == "department") and fac or "", allow = allow, enabled = true }
            status:SetText("Есть несохранённые изменения"); status:SetTextColor(Color(230,190,90)); refillGrants()
        end
        allowBtn.DoClick = function() addGrant(true) end; denyBtn.DoClick = function() addGrant(false) end
        deleteBtn.DoClick = function()
            if selectedGrant and work[selectedGrant] then table.remove(work, selectedGrant); status:SetText("Есть несохранённые изменения"); refillGrants() end
        end
        saveBtn.DoClick = function() net.Start(NET_SAVE); net.WriteTable(work); net.SendToServer(); status:SetText("Сохранение...") end

        frame.PerformLayout = function(self, w, h)
            local top, bottom, gap, leftW, rightW = 82, 66, 12, math.max(300, w * .29), math.max(310, w * .25)
            left:SetPos(18, top); left:SetSize(leftW, h - top - bottom)
            right:SetPos(w - rightW - 18, top); right:SetSize(rightW, h - top - bottom)
            middle:SetPos(18 + leftW + gap, top); middle:SetSize(w - leftW - rightW - 36 - gap * 2, h - top - bottom)
            search:SetPos(12,12); search:SetSize(left:GetWide()-24,36); capList:SetPos(12,58); capList:SetSize(left:GetWide()-24,left:GetTall()-70)
            grantList:SetPos(12,12); grantList:SetSize(middle:GetWide()-24,middle:GetTall()-64); deleteBtn:SetPos(12,middle:GetTall()-44); deleteBtn:SetSize(middle:GetWide()-24,32)
            title:SetPos(16,16); title:SetSize(right:GetWide()-32,34); typeBox:SetPos(16,64); typeBox:SetSize(right:GetWide()-32,36)
            factionBox:SetPos(16,110); factionBox:SetSize(right:GetWide()-32,36); subjectBox:SetPos(16,156); subjectBox:SetSize(right:GetWide()-32,36)
            subjectEntry:SetPos(16,156); subjectEntry:SetSize(right:GetWide()-32,36); hint:SetPos(16,205); hint:SetSize(right:GetWide()-32,80)
            allowBtn:SetPos(16,right:GetTall()-100); allowBtn:SetSize(right:GetWide()-32,36); denyBtn:SetPos(16,right:GetTall()-54); denyBtn:SetSize(right:GetWide()-32,36)
            saveBtn:SetPos(w-330,h-52); saveBtn:SetSize(312,36); status:SetPos(18,h-49); status:SetSize(w-370,30)
        end
        refillCaps(""); refillGrants(); refreshSubjectControls()
    end

    net.Receive(NET_OPEN, function() openEditor(net.ReadTable() or {}, net.ReadTable() or {}, net.ReadTable() or {}) end)
    net.Receive(NET_RESULT, function()
        local ok, reason = net.ReadBool(), net.ReadString()
        notification.AddLegacy(ok and "Единые права сохранены" or ("Ошибка: " .. reason), ok and NOTIFY_GENERIC or NOTIFY_ERROR, 5)
    end)
    concommand.Add("grm_access", function() net.Start(NET_OPEN); net.SendToServer() end)
end

print("[GRM Access] capability core v" .. A.Version .. " loaded")

-- Вечер-18: единый словарь slash-команд: имена живого PlayerSay-обработчика
-- вносятся во внешний реестр библиотеки (на режиме сверка идёт ДО ParseSay —
-- без регистрации команда стала бы «неизвестной»).
if GRM and GRM.Chat and GRM.Chat.RegisterExternalCommands then
    GRM.Chat.RegisterExternalCommands({ "/grm_access", "/доступы" })
end
