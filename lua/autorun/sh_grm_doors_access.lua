--[[--------------------------------------------------------------------
    GRM Doors Access Manager v3.0.0 (Код 64)

    Матрица ордеров / тарана / категорий — CONCEPT_DOORS_ACCESS_V3.md.
    Ядро дверей (слои EvaluateAccess) — sh_grm_doors.lua v3.

      Ордер      — /warrant и ключ на запертую дверь хозяина;
      Таран      — выбить дверь, НЕ ключ на E;
      Управление — /door_access и категории, НЕ админка R;
      Карта (R)  — только SuperAdmin (D.CanAdminDoors).

    data/grm_doors/access.json, version=3, jsonT(..., false, true).
    Steam — массивы CharacterKey. Карантин битого файла.
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Doors = GRM.Doors or {}
GRM.Doors.AccessManager = GRM.Doors.AccessManager or {}
local AM = GRM.Doors.AccessManager
AM.Version = "3.0.0"

local NET_REQ    = "GRM_DoorAccess_Request"
local NET_DATA   = "GRM_DoorAccess_Data"
local NET_SAVE   = "GRM_DoorAccess_Save"
local NET_RESULT = "GRM_DoorAccess_Result"
local NET_CAT    = "GRM_DoorAccess_CatAct"

local ACCESS_DIR  = "grm_doors"
local ACCESS_FILE = ACCESS_DIR .. "/access.json"

local MAP_KEYS = {
    "ManageFactions", "WarrantFactions", "ForceFactions",
    "AlarmFriendlyFactions", "AlarmFriendlyCategories",
}
local NEST_KEYS = {
    "ManageRoles", "WarrantRoles", "ForceRoles",
    "ManageDepartments", "WarrantDepartments", "ForceDepartments",
}
local STEAM_KEYS = { "ManageSteam", "WarrantSteam", "ForceSteam" }

local KINDS = {
    manage  = { fac = "ManageFactions",  roles = "ManageRoles",  depts = "ManageDepartments",  steam = "ManageSteam" },
    warrant = { fac = "WarrantFactions", roles = "WarrantRoles", depts = "WarrantDepartments", steam = "WarrantSteam" },
    force   = { fac = "ForceFactions",   roles = "ForceRoles",   depts = "ForceDepartments",   steam = "ForceSteam" },
}

local function jsonT(txt)
    local ok, t = pcall(util.JSONToTable, txt, false, true)
    return (ok and istable(t)) and t or nil
end

local function toSet(src)
    local out = {}
    if not istable(src) then return out end
    if #src > 0 then
        for _, v in ipairs(src) do
            local s = tostring(v or "")
            if s ~= "" then out[s] = true end
        end
        return out
    end
    for k, v in pairs(src) do
        if v == true then out[tostring(k)] = true
        elseif isstring(v) and v ~= "" then out[v] = true end
    end
    return out
end

local function toNest(src)
    local out = {}
    if not istable(src) then return out end
    for fac, inner in pairs(src) do
        if istable(inner) then out[tostring(fac)] = toSet(inner) end
    end
    return out
end

local function setToArray(set)
    local arr = {}
    for k, v in pairs(set or {}) do
        if v then arr[#arr + 1] = tostring(k) end
    end
    table.sort(arr)
    return arr
end

function AM.Normalize(d)
    d = istable(d) and d or {}
    local out = { version = 3 }
    for _, k in ipairs(MAP_KEYS) do out[k] = toSet(d[k]) end
    for _, k in ipairs(NEST_KEYS) do out[k] = toNest(d[k]) end
    for _, k in ipairs(STEAM_KEYS) do out[k] = toSet(d[k]) end
    return out
end

local function defaults()
    return AM.Normalize({
        WarrantFactions = { Polizei = true, FBI = true },
        ForceFactions   = { Polizei = true, FBI = true },
        AlarmFriendlyFactions = { Polizei = true },
    })
end

--- Чистая матрица. actor = { superadmin, key, sid64, sid, faction, role, department }
function AM.Evaluate(data, actor, kind)
    local spec = KINDS[kind]
    if not spec then return false end
    data = AM.Normalize(data)
    actor = istable(actor) and actor or {}
    if actor.superadmin == true then return true end
    local steam = data[spec.steam]
    local key, sid64, sid = tostring(actor.key or ""), tostring(actor.sid64 or ""), tostring(actor.sid or "")
    if (key ~= "" and steam[key]) or (sid64 ~= "" and steam[sid64]) or (sid ~= "" and steam[sid]) then
        return true
    end
    local fac = actor.faction
    if not fac or fac == "" then return false end
    if data[spec.fac][fac] then return true end
    local role, dept = actor.role, actor.department
    if role and istable(data[spec.roles][fac]) and data[spec.roles][fac][role] then return true end
    if dept and istable(data[spec.depts][fac]) and data[spec.depts][fac][dept] then return true end
    return false
end

-----------------------------------------------------------------------
-- SERVER
-----------------------------------------------------------------------
if SERVER then
    if GRM._doorsAccessActive then
        print("[GRM Doors] Вторая копия sh_grm_doors_access.lua пропущена")
        return
    end
    GRM._doorsAccessActive = true

    util.AddNetworkString(NET_REQ)
    util.AddNetworkString(NET_DATA)
    util.AddNetworkString(NET_SAVE)
    util.AddNetworkString(NET_RESULT)
    util.AddNetworkString(NET_CAT)

    local function ensureDir()
        if not file.IsDir(ACCESS_DIR, "DATA") then file.CreateDir(ACCESS_DIR) end
    end

    local function writeJSON(path, data)
        local ok, txt = pcall(util.TableToJSON, data, true)
        if not (ok and isstring(txt)) then return false end
        file.Write(path, txt)
        return file.Read(path, "DATA") == txt
    end

    local function persistShape(d)
        d = AM.Normalize(d)
        local out = { version = 3 }
        for _, k in ipairs(MAP_KEYS) do out[k] = d[k] end
        for _, k in ipairs(NEST_KEYS) do out[k] = d[k] end
        for _, k in ipairs(STEAM_KEYS) do out[k] = setToArray(d[k]) end
        return out
    end

    function AM.Load()
        ensureDir()
        if not file.Exists(ACCESS_FILE, "DATA") then
            AM.Data = defaults()
            AM.Save(AM.Data, "init")
            return AM.Data
        end
        local raw = file.Read(ACCESS_FILE, "DATA") or ""
        local t = jsonT(raw)
        if not t then
            local bak = ACCESS_FILE .. ".corrupt." .. os.time()
            file.Write(bak, raw)
            ErrorNoHalt("[GRM Doors Access] " .. ACCESS_FILE .. " повреждён, копия: " .. bak .. "\n")
            AM.Data = defaults()
            return AM.Data
        end
        AM.Data = AM.Normalize(t)
        return AM.Data
    end

    function AM.Save(data, reason)
        ensureDir()
        AM.Data = AM.Normalize(data or AM.Data)
        local shaped = persistShape(AM.Data)
        if writeJSON(ACCESS_FILE, shaped) then
            print("[GRM Doors Access] SAVE ok [" .. tostring(reason or "save") .. "]")
            return true
        end
        ErrorNoHalt("[GRM Doors Access] SAVE fail [" .. tostring(reason or "save") .. "]\n")
        return false
    end

    AM.Load()

    --[[ Ключ должности переименован — переносим галочки «Ранг: …» в списках
         управления, ордеров и вскрытия, иначе доступ повисает на мёртвом ключе. ]]
    hook.Add("GRM_FactionRoleKeyRenamed", "GRM_DoorsAccess_RoleKey", function(factionName, oldKey, newKey)
        local data = AM.Data or AM.Load()
        if not istable(data) then return end
        local changed = false
        for _, spec in pairs(KINDS or {}) do
            local bucket = istable(data[spec.roles]) and data[spec.roles][factionName] or nil
            if istable(bucket) and bucket[oldKey] ~= nil then
                bucket[newKey] = bucket[oldKey]
                bucket[oldKey] = nil
                changed = true
            end
        end
        if changed then AM.Save(data, "role key renamed") end
    end)

    local function factionInfo(ply)
        if not IsValid(ply) or not istable(Factions) then return nil, nil, nil end
        if not (GRM.Identity and GRM.Identity.FactionMember) then return nil, nil, nil end
        for n, f in pairs(Factions) do
            if istable(f) and istable(f.Members) then
                local m = GRM.Identity.FactionMember(f, ply)
                if istable(m) then return n, m.Role, m.Department end
            end
        end
        return nil, nil, nil
    end

    local function actorOf(ply)
        local fac, role, dept = factionInfo(ply)
        local sid64 = (IsValid(ply) and ply.SteamID64 and ply:SteamID64()) or ""
        return {
            superadmin = IsValid(ply) and ply:IsSuperAdmin() == true,
            key = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply))
                or (tostring(sid64) .. ":char1"),
            sid64 = tostring(sid64 or ""),
            sid = (IsValid(ply) and ply.SteamID and ply:SteamID()) or "",
            faction = fac,
            role = role,
            department = dept,
        }
    end

    function AM.CanManage(ply)
        return IsValid(ply) and AM.Evaluate(AM.Data or AM.Load(), actorOf(ply), "manage")
    end

    function AM.CanWarrant(ply)
        return IsValid(ply) and AM.Evaluate(AM.Data or AM.Load(), actorOf(ply), "warrant")
    end

    function AM.CanForceDoor(ply)
        return IsValid(ply) and AM.Evaluate(AM.Data or AM.Load(), actorOf(ply), "force")
    end

    local function factionInCat(cat, fac)
        if not istable(cat) or not fac then return false end
        local facs = cat.factions
        if not istable(facs) then return false end
        if facs[fac] == true then return true end
        for _, n in pairs(facs) do if n == fac then return true end end
        return false
    end

    function AM.IsFriendly(ply, networkID)
        if not IsValid(ply) then return false end
        if ply:IsSuperAdmin() then return true end
        if AM.CanForceDoor(ply) or AM.CanWarrant(ply) or AM.CanManage(ply) then return true end

        local d = AM.Normalize(AM.Data or AM.Load())
        local fac = factionInfo(ply)
        if fac and d.AlarmFriendlyFactions[fac] then return true end

        if fac and istable(d.AlarmFriendlyCategories) then
            local cats = (GRM.Doors and GRM.Doors.Data and GRM.Doors.Data.categories) or {}
            for catId, on in pairs(d.AlarmFriendlyCategories) do
                if on and factionInCat(cats[catId], fac) then return true end
            end
        end

        if GRM.Alarm and GRM.Alarm.AccessManager and GRM.Alarm.AccessManager.CanControl then
            if GRM.Alarm.AccessManager.CanControl(ply) then return true end
        end
        return false
    end

    local function canOpen(ply)
        return IsValid(ply) and (ply:IsSuperAdmin() or AM.CanManage(ply))
    end

    local function rateOk(ply)
        if not IsValid(ply) then return false end
        ply.GRM_DoorAccNext = ply.GRM_DoorAccNext or 0
        if CurTime() < ply.GRM_DoorAccNext then return false end
        ply.GRM_DoorAccNext = CurTime() + 0.4
        return true
    end

    local function sendResult(ply, ok, msg)
        if not IsValid(ply) then return end
        net.Start(NET_RESULT)
            net.WriteBool(ok and true or false)
            net.WriteString(tostring(msg or ""))
        net.Send(ply)
    end

    local function buildFactionsMap()
        local out = {}
        if istable(Factions) then
            for n, f in pairs(Factions) do
                if istable(f) then
                    out[n] = {
                        Roles = f.Roles or {},
                        Departments = f.Departments or {},
                    }
                end
            end
        end
        return out
    end

    local function collectCats()
        local cats = {}
        if GRM.Doors and GRM.Doors.Data and GRM.Doors.Data.categories then
            for id, c in pairs(GRM.Doors.Data.categories) do
                local cc = istable(c) and table.Copy(c) or {}
                cc.id = id
                cats[#cats + 1] = cc
            end
        end
        return cats
    end

    local function sendData(ply)
        if not canOpen(ply) then
            sendResult(ply, false, "Нет прав открывать /door_access.")
            return
        end
        local canEdit = ply:IsSuperAdmin() == true
        net.Start(NET_DATA)
            net.WriteTable(buildFactionsMap())
            net.WriteTable(canEdit and AM.Normalize(AM.Data or {}) or AM.Normalize({}))
            net.WriteTable(collectCats())
            net.WriteBool(canEdit)
        net.Send(ply)
    end

    local function takeKnown(raw)
        raw = istable(raw) and raw or {}
        local sliced = {}
        for _, k in ipairs(MAP_KEYS) do if istable(raw[k]) then sliced[k] = raw[k] end end
        for _, k in ipairs(NEST_KEYS) do if istable(raw[k]) then sliced[k] = raw[k] end end
        for _, k in ipairs(STEAM_KEYS) do if istable(raw[k]) then sliced[k] = raw[k] end end
        return AM.Normalize(sliced)
    end

    net.Receive(NET_REQ, function(_, ply)
        if not rateOk(ply) then return end
        sendData(ply)
    end)

    net.Receive(NET_SAVE, function(_, ply)
        if not rateOk(ply) then return end
        if not IsValid(ply) or not ply:IsSuperAdmin() then
            sendResult(ply, false, "Матрицу ордеров/тарана правит только суперадмин.")
            return
        end
        AM.Save(takeKnown(net.ReadTable() or {}), "matrix " .. ply:Nick())
        sendResult(ply, true, "Настройки доступа к дверям и ордерам сохранены.")
        sendData(ply)
    end)

    net.Receive(NET_CAT, function(_, ply)
        if not rateOk(ply) then return end
        if not canOpen(ply) then
            sendResult(ply, false, "Нет прав управлять категориями.")
            return
        end
        if not (GRM.Doors and GRM.Doors.CreateCategory) then return end

        local a = net.ReadTable() or {}
        local op = tostring(a.op or "")
        local ok, res, msg = false, nil, ""

        if op == "create" then
            res, msg = GRM.Doors.CreateCategory(a.id, a.name)
            ok = istable(res)
            if ok then msg = "Категория создана: " .. tostring(res.name or res.id) end
        elseif op == "rename" then
            ok, msg = GRM.Doors.RenameCategory(a.id, a.name)
            if ok then msg = "Категория переименована." end
        elseif op == "delete" then
            ok, msg = GRM.Doors.DeleteCategory(a.id)
            if ok then msg = "Категория удалена (ссылки дверей очищены)." end
        elseif op == "setfaction" then
            ok, msg = GRM.Doors.CategorySetFaction(a.id, a.faction, a.on == true)
            if ok then
                msg = (a.on and "Фракция добавлена в категорию: " or "Фракция убрана из категории: ")
                    .. tostring(a.faction)
            end
        else
            msg = "Неизвестная операция."
        end

        sendResult(ply, ok and true or false, tostring(msg or ""))
        if ok then sendData(ply) end
    end)

    concommand.Add("grm_door_access", function(ply)
        if canOpen(ply) then sendData(ply)
        elseif IsValid(ply) then sendResult(ply, false, "Нет прав открывать /door_access.") end
    end)

    hook.Add("PlayerSay", "GRM_DoorAccess_Chat", function(ply, text)
        local msg = string.lower(string.Trim(text or ""))
        if msg == "/door_access" or msg == "!door_access" then
            if canOpen(ply) then sendData(ply)
            else sendResult(ply, false, "Нет прав открывать /door_access.") end
            return ""
        end
    end)

    print("[GRM Doors] Менеджер доступа к дверям v" .. AM.Version .. " загружен (сервер)")
end

-----------------------------------------------------------------------
-- CLIENT
-----------------------------------------------------------------------
if CLIENT then
    if GRM._doorsAccessClient then
        print("[GRM Doors] Вторая копия access-клиента пропущена")
        return
    end
    GRM._doorsAccessClient = true

    surface.CreateFont("GRMDoorAcc_Title",  { font = "Roboto", size = 18, weight = 800, extended = true })
    surface.CreateFont("GRMDoorAcc_Normal", { font = "Roboto", size = 13, weight = 500, extended = true })

    local CUI = {
        bg     = Color(20, 24, 32, 250),
        panel  = Color(32, 38, 50, 245),
        accent = Color(70, 150, 240),
        green  = Color(60, 190, 110),
        red    = Color(220, 75, 70),
        yellow = Color(230, 180, 60),
        text   = Color(240, 245, 250),
        dim    = Color(160, 170, 185),
    }

    local function sortKeys(t)
        local k = {}
        for key in pairs(t or {}) do k[#k + 1] = key end
        table.sort(k, function(a, b) return tostring(a) < tostring(b) end)
        return k
    end

    local function pageScroll(pnl)
        if not IsValid(pnl) then return nil end
        if pnl.ClassName == "DScrollPanel" then return pnl end
        for _, ch in ipairs(pnl:GetChildren()) do
            if IsValid(ch) and ch.ClassName == "DScrollPanel" then return ch end
        end
        return nil
    end

    local function mkBtn(p, text, col, w, h)
        local b = vgui.Create("DButton", p)
        if w then b:SetWide(w) end
        if h then b:SetTall(h) end
        b:SetText(text) b:SetTextColor(color_white) b:SetFont("GRMDoorAcc_Normal")
        b.Paint = function(self, pw, ph)
            local c = col or CUI.accent
            if not self:IsEnabled() then c = Color(60, 65, 75)
            elseif self:IsHovered() then c = Color(math.min(255, c.r + 25), math.min(255, c.g + 25), math.min(255, c.b + 25)) end
            draw.RoundedBox(6, 0, 0, pw, ph, c)
        end
        return b
    end

    local function openAccessMenu(factionsMap, data, cats, canEdit)
        data = AM.Normalize(data)
        cats = cats or {}
        canEdit = canEdit == true
        table.sort(cats, function(a, b) return tostring(a and a.id) < tostring(b and b.id) end)

        local wantTab = AM._wantTab
        AM._wantTab = nil
        local prevTab, prevScroll
        if IsValid(AM._tabs) then
            local at = AM._tabs:GetActiveTab()
            if IsValid(at) then
                prevTab = at:GetText()
                for _, it in ipairs(AM._tabs.Items or {}) do
                    if it.Tab == at then
                        local sp = pageScroll(it.Panel)
                        if sp then prevScroll = sp:GetVBar():GetScroll() end
                        break
                    end
                end
            end
        end

        if IsValid(AM._f) then AM._f:Remove() end
        local frame = vgui.Create("DFrame")
        AM._f = frame
        if GRM.UI and GRM.UI.Track then GRM.UI.Track("grm_door_access", frame) end
        frame:SetTitle("")
        frame:SetSize(960, 680)
        frame:Center()
        frame:MakePopup()
        frame:ShowCloseButton(false)
        frame.Paint = function(_, pw, ph)
            draw.RoundedBox(8, 0, 0, pw, ph, CUI.bg)
            draw.RoundedBoxEx(8, 0, 0, pw, 38, Color(28, 34, 46), true, true, false, false)
            draw.SimpleText("Доступ: ордера, таран, категории  ·  v" .. AM.Version,
                "GRMDoorAcc_Title", 14, 19, CUI.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end

        local closeBtn = vgui.Create("DButton", frame)
        closeBtn:SetText("X") closeBtn:SetFont("GRMDoorAcc_Title") closeBtn:SetTextColor(color_white)
        closeBtn:SetPos(916, 6) closeBtn:SetSize(32, 26)
        closeBtn.DoClick = function() frame:Close() end
        closeBtn.Paint = function(self, pw, ph)
            draw.RoundedBox(4, 0, 0, pw, ph, self:IsHovered() and CUI.red or Color(45, 52, 68))
        end

        local tabs = vgui.Create("DPropertySheet", frame)
        tabs:Dock(FILL)
        tabs:DockMargin(8, 2, 8, 52)
        AM._tabs = tabs

        local function helpBanner(parent, text)
            local h = vgui.Create("DLabel", parent)
            h:Dock(TOP) h:SetTall(52) h:DockMargin(8, 6, 8, 4)
            h:SetWrap(true) h:SetFont("GRMDoorAcc_Normal") h:SetTextColor(CUI.dim)
            h:SetText(text)
            return h
        end

        local function addKindTab(title, kind, help, icon)
            local spec = KINDS[kind]
            local page = vgui.Create("DPanel")
            page:SetPaintBackground(false)
            helpBanner(page, help)

            local sc = vgui.Create("DScrollPanel", page)
            sc:Dock(FILL) sc:DockMargin(8, 0, 8, 8)

            local function addChk(parent, label, val, onChange)
                local r = vgui.Create("DPanel", parent)
                r:Dock(TOP) r:SetTall(30) r:DockMargin(0, 0, 0, 3)
                r.Paint = function(_, pw, ph) draw.RoundedBox(6, 0, 0, pw, ph, CUI.panel) end
                local chk = vgui.Create("DCheckBoxLabel", r)
                chk:Dock(FILL) chk:DockMargin(10, 0, 0, 0)
                chk:SetText(label) chk:SetTextColor(CUI.text)
                chk:SetValue(val and 1 or 0)
                chk:SetEnabled(canEdit)
                chk.OnChange = function(_, v)
                    if canEdit then onChange(v) end
                end
            end

            for _, fn in ipairs(sortKeys(factionsMap)) do
                addChk(sc, "Вся фракция: " .. fn, data[spec.fac][fn], function(val)
                    if val then data[spec.fac][fn] = true else data[spec.fac][fn] = nil end
                end)
            end

            local nestBox = vgui.Create("DPanel", page)
            nestBox:Dock(BOTTOM) nestBox:SetTall(210) nestBox:DockMargin(8, 4, 8, 8)
            nestBox.Paint = function(_, pw, ph)
                draw.RoundedBox(6, 0, 0, pw, ph, CUI.panel)
                draw.SimpleText("Ранги и подразделения выбранной фракции", "GRMDoorAcc_Normal",
                    10, 14, CUI.yellow, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            local combo = vgui.Create("DComboBox", nestBox)
            combo:SetPos(10, 28) combo:SetSize(300, 26)
            combo:SetValue("Выберите фракцию...")
            local roleSc = vgui.Create("DScrollPanel", nestBox)
            roleSc:SetPos(10, 60) roleSc:SetSize(450, 140)
            local deptSc = vgui.Create("DScrollPanel", nestBox)
            deptSc:SetPos(470, 60) deptSc:SetSize(450, 140)

            local function rebuildNest(fname)
                roleSc:Clear() deptSc:Clear()
                local f = factionsMap[fname]
                if not f then return end
                data[spec.roles][fname] = istable(data[spec.roles][fname]) and data[spec.roles][fname] or {}
                data[spec.depts][fname] = istable(data[spec.depts][fname]) and data[spec.depts][fname] or {}
                for _, key in ipairs(f.Roles or {}) do
                    addChk(roleSc, "Ранг: " .. tostring(key), data[spec.roles][fname][key], function(val)
                        if val then data[spec.roles][fname][key] = true else data[spec.roles][fname][key] = nil end
                    end)
                end
                for _, key in ipairs(f.Departments or {}) do
                    addChk(deptSc, "Отдел: " .. tostring(key), data[spec.depts][fname][key], function(val)
                        if val then data[spec.depts][fname][key] = true else data[spec.depts][fname][key] = nil end
                    end)
                end
            end
            for _, fn in ipairs(sortKeys(factionsMap)) do combo:AddChoice(fn) end
            combo.OnSelect = function(_, _, val) rebuildNest(val) end

            tabs:AddSheet(title, page, icon)
        end

        addKindTab("Ордера", "warrant",
            "Кто выписывает /warrant и проходит запертую дверь хозяина по ордеру. Не даёт таран и не открывает админку R.",
            "icon16/exclamation.png")
        addKindTab("Таран", "force",
            "Кто выбивает дверь тараном. CanForce не есть ключ на E — замок сам не откроется.",
            "icon16/key.png")
        addKindTab("Управление", "manage",
            "Кто открывает /door_access и правит категории. Не даёт назначать владельца двери карты в R-меню.",
            "icon16/shield.png")

        do
            local page = vgui.Create("DPanel")
            page:SetPaintBackground(false)
            helpBanner(page, "«Свои» для сигнализации: фракция или категория не поднимает тревогу. Ордер/таран/управление тоже считаются своими.")
            local sc = vgui.Create("DScrollPanel", page)
            sc:Dock(FILL) sc:DockMargin(8, 0, 8, 8)
            for _, fn in ipairs(sortKeys(factionsMap)) do
                local r = vgui.Create("DPanel", sc)
                r:Dock(TOP) r:SetTall(30) r:DockMargin(0, 0, 0, 3)
                r.Paint = function(_, pw, ph) draw.RoundedBox(6, 0, 0, pw, ph, CUI.panel) end
                local chk = vgui.Create("DCheckBoxLabel", r)
                chk:Dock(FILL) chk:DockMargin(10, 0, 0, 0)
                chk:SetText("Своя фракция: " .. fn) chk:SetTextColor(CUI.text)
                chk:SetValue(data.AlarmFriendlyFactions[fn] and 1 or 0)
                chk:SetEnabled(canEdit)
                chk.OnChange = function(_, val)
                    if not canEdit then return end
                    if val then data.AlarmFriendlyFactions[fn] = true else data.AlarmFriendlyFactions[fn] = nil end
                end
            end
            for _, c in ipairs(cats) do
                local cid = tostring(c.id or "")
                if cid ~= "" then
                    local r = vgui.Create("DPanel", sc)
                    r:Dock(TOP) r:SetTall(30) r:DockMargin(0, 0, 0, 3)
                    r.Paint = function(_, pw, ph) draw.RoundedBox(6, 0, 0, pw, ph, Color(38, 46, 62)) end
                    local chk = vgui.Create("DCheckBoxLabel", r)
                    chk:Dock(FILL) chk:DockMargin(10, 0, 0, 0)
                    chk:SetText("Своя категория: " .. tostring(c.name or cid))
                    chk:SetTextColor(CUI.yellow)
                    chk:SetValue(data.AlarmFriendlyCategories[cid] and 1 or 0)
                    chk:SetEnabled(canEdit)
                    chk.OnChange = function(_, val)
                        if not canEdit then return end
                        if val then data.AlarmFriendlyCategories[cid] = true else data.AlarmFriendlyCategories[cid] = nil end
                    end
                end
            end
            tabs:AddSheet("Сигнализация", page, "icon16/bell.png")
        end

        do
            local catPage = vgui.Create("DPanel")
            catPage:SetPaintBackground(false)
            helpBanner(catPage, "Категории — владельцы ведомственных дверей и пункты ACL. Создаёт SuperAdmin или тот, кому выдано «Управление».")

            local cr = vgui.Create("DPanel", catPage)
            cr:Dock(TOP) cr:SetTall(64) cr:DockMargin(8, 0, 8, 6)
            cr.Paint = function(_, pw, ph)
                draw.RoundedBox(6, 0, 0, pw, ph, CUI.panel)
                draw.SimpleText("Создать категорию (ID — латиница/цифры/_/-, напр. polizei_swat)",
                    "GRMDoorAcc_Normal", 10, 14, CUI.yellow, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            local idEntry = vgui.Create("DTextEntry", cr)
            idEntry:SetPos(10, 30) idEntry:SetSize(200, 26) idEntry:SetPlaceholderText("ID категории")
            local nameEntry = vgui.Create("DTextEntry", cr)
            nameEntry:SetPos(218, 30) nameEntry:SetSize(320, 26) nameEntry:SetPlaceholderText("Название категории")
            local bCreate = mkBtn(cr, "Создать", CUI.green, 120, 26)
            bCreate:SetPos(546, 30)
            bCreate.DoClick = function()
                net.Start(NET_CAT)
                net.WriteTable({ op = "create", id = idEntry:GetValue(), name = nameEntry:GetValue() })
                net.SendToServer()
            end

            local catScroll = vgui.Create("DScrollPanel", catPage)
            catScroll:Dock(FILL) catScroll:DockMargin(8, 4, 8, 8)
            local facNames = sortKeys(factionsMap)

            local function buildCatBlock(c)
                local cid = tostring(c.id or "")
                if cid == "" then return end
                local cname = tostring(c.name or cid)
                local facs, seenF = {}, {}
                if istable(c.factions) then
                    for k, v in pairs(c.factions) do
                        local fn
                        if v == true and isstring(k) then fn = k
                        elseif isstring(v) then fn = v end
                        if fn and not seenF[fn] then seenF[fn] = true facs[#facs + 1] = fn end
                    end
                end
                table.sort(facs)

                local n = #facs
                local block = vgui.Create("DPanel", catScroll)
                block:Dock(TOP) block:SetTall(34 + n * 26 + 36 + 36) block:DockMargin(0, 0, 0, 6)
                block.Paint = function(_, pw, ph)
                    draw.RoundedBox(6, 0, 0, pw, ph, CUI.panel)
                    draw.SimpleText(cname .. "   [" .. cid .. "]", "GRMDoorAcc_Normal", 10, 15, CUI.yellow, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end

                for i, fn in ipairs(facs) do
                    local rf = vgui.Create("DPanel", block)
                    rf:SetPos(10, 30 + (i - 1) * 26) rf:SetSize(430, 22)
                    rf.Paint = function(_, pw, ph)
                        draw.RoundedBox(4, 0, 0, pw, ph, Color(26, 32, 42))
                        draw.SimpleText("• " .. fn, "GRMDoorAcc_Normal", 8, ph / 2, CUI.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    end
                    local bRem = mkBtn(rf, "убрать", CUI.red, 100, 20)
                    bRem:SetPos(322, 1)
                    bRem.DoClick = function()
                        net.Start(NET_CAT)
                        net.WriteTable({ op = "setfaction", id = cid, faction = fn, on = false })
                        net.SendToServer()
                    end
                end

                local yA = 34 + n * 26
                local addCombo = vgui.Create("DComboBox", block)
                addCombo:SetPos(10, yA) addCombo:SetSize(300, 26)
                addCombo:SetValue("Добавить фракцию...")
                for _, fn in ipairs(facNames) do addCombo:AddChoice(fn) end
                local bAdd = mkBtn(block, "Добавить", CUI.green, 120, 26)
                bAdd:SetPos(318, yA)
                bAdd.DoClick = function()
                    local _, fn = addCombo:GetSelected()
                    if fn then
                        net.Start(NET_CAT)
                        net.WriteTable({ op = "setfaction", id = cid, faction = fn, on = true })
                        net.SendToServer()
                    end
                end

                local yB = yA + 36
                local renEntry = vgui.Create("DTextEntry", block)
                renEntry:SetPos(10, yB) renEntry:SetSize(300, 26) renEntry:SetValue(cname)
                local bRen = mkBtn(block, "Переименовать", CUI.accent, 120, 26)
                bRen:SetPos(318, yB)
                bRen.DoClick = function()
                    net.Start(NET_CAT)
                    net.WriteTable({ op = "rename", id = cid, name = renEntry:GetValue() })
                    net.SendToServer()
                end
                local bDel = mkBtn(block, "Удалить категорию", CUI.red, 160, 26)
                bDel:SetPos(448, yB)
                bDel.DoClick = function()
                    Derma_Query("Удалить категорию «" .. cname .. "»?\nСсылки дверей на неё будут очищены.", "Удаление категории",
                        "Удалить", function()
                            net.Start(NET_CAT)
                            net.WriteTable({ op = "delete", id = cid })
                            net.SendToServer()
                        end,
                        "Отмена", function() end)
                end
            end

            for _, c in ipairs(cats) do buildCatBlock(c) end
            if #cats == 0 then
                local empty = vgui.Create("DLabel", catScroll)
                empty:Dock(TOP) empty:SetTall(30) empty:DockMargin(4, 4, 4, 4)
                empty:SetText("Пока нет ни одной категории — создайте первую выше.")
                empty:SetTextColor(CUI.dim) empty:SetFont("GRMDoorAcc_Normal")
            end
            tabs:AddSheet("Категории", catPage, "icon16/folder_user.png")
        end

        do
            local page = vgui.Create("DPanel")
            page:SetPaintBackground(false)
            helpBanner(page, "Персональный доступ по CharacterKey (SteamID64:charN). Карта R по-прежнему только у суперадмина.")
            local function steamCol(parent, title, field, x)
                local box = vgui.Create("DPanel", parent)
                box:SetPos(x, 64) box:SetSize(300, 470)
                box.Paint = function(_, pw, ph)
                    draw.RoundedBox(6, 0, 0, pw, ph, CUI.panel)
                    draw.SimpleText(title, "GRMDoorAcc_Normal", 10, 14, CUI.yellow, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end
                local entry = vgui.Create("DTextEntry", box)
                entry:SetPos(8, 30) entry:SetSize(184, 24)
                entry:SetPlaceholderText("SteamID64 / ключ")
                local list = vgui.Create("DListView", box)
                list:SetPos(8, 88) list:SetSize(284, 374)
                list:AddColumn("Ключ")
                list:SetMultiSelect(false)
                local function rebuild()
                    list:Clear()
                    for _, sid in ipairs(sortKeys(data[field])) do list:AddLine(sid) end
                end
                rebuild()
                local add = mkBtn(box, "+", CUI.green, 48, 24)
                add:SetPos(196, 30)
                add:SetEnabled(canEdit)
                add.DoClick = function()
                    local s = string.Trim(entry:GetValue() or "")
                    if s ~= "" then data[field][s] = true entry:SetText("") rebuild() end
                end
                local del = mkBtn(box, "−", CUI.red, 48, 24)
                del:SetPos(248, 30)
                del:SetEnabled(canEdit)
                del.DoClick = function()
                    local ln = list:GetSelected()
                    if ln and ln[1] then data[field][ln[1]:GetColumnText(1)] = nil rebuild() end
                end
                local online = vgui.Create("DComboBox", box)
                online:SetPos(8, 58) online:SetSize(284, 24)
                online:SetValue("Онлайн…")
                online:SetEnabled(canEdit)
                for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                    if IsValid(p) then
                        local ck = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(p)) or p:SteamID64()
                        online:AddChoice(p:Nick() .. " [" .. ck .. "]", ck)
                    end
                end
                online.OnSelect = function(_, _, _, id)
                    if id and canEdit then data[field][id] = true rebuild() end
                end
            end
            steamCol(page, "Ордера", "WarrantSteam", 12)
            steamCol(page, "Таран", "ForceSteam", 326)
            steamCol(page, "Управление", "ManageSteam", 640)
            tabs:AddSheet("Steam", page, "icon16/vcard.png")
        end

        tabs.tabScroller:Hide()

        local tabBar = vgui.Create("DPanel", frame)
        tabBar:Dock(TOP)
        tabBar:SetTall(34)
        tabBar:DockMargin(8, 44, 8, 2)
        tabBar:SetPaintBackground(false)

        local tabBtns = {}
        for idx, it in ipairs(tabs.Items or {}) do
            if IsValid(it.Tab) then
                local b = vgui.Create("DButton", tabBar)
                b:SetText(it.Tab:GetText() or ("Вкладка " .. idx))
                b:SetFont("GRMDoorAcc_Normal")
                b:SetTextColor(CUI.text)
                b._tab = it.Tab
                b.DoClick = function() tabs:SetActiveTab(b._tab) end
                b.Paint = function(self, pw, ph)
                    local active = tabs:GetActiveTab() == self._tab
                    local c = active and CUI.accent or CUI.panel
                    if not active and self:IsHovered() then c = Color(52, 60, 76) end
                    draw.RoundedBox(6, 0, 0, pw, ph, c)
                end
                tabBtns[#tabBtns + 1] = b
            end
        end

        tabBar.PerformLayout = function(self, w, h)
            surface.SetFont("GRMDoorAcc_Normal")
            local x, y = 0, 0
            for _, b in ipairs(tabBtns) do
                local tw = surface.GetTextSize(b:GetText() or "") or 40
                local bw = tw + 26
                if x > 0 and x + bw > w then x = 0 y = y + 31 end
                b:SetPos(x, y) b:SetSize(bw, 28)
                x = x + bw + 6
            end
            local needH = y + 28
            if needH > 0 and self:GetTall() ~= needH then self:SetTall(needH) end
        end

        local restoreName = wantTab or prevTab
        if restoreName == "Категории фракций" then restoreName = "Категории" end
        if not restoreName and not canEdit then restoreName = "Категории" end
        if restoreName then
            for _, it in ipairs(tabs.Items or {}) do
                if IsValid(it.Tab) and it.Tab:GetText() == restoreName then
                    tabs:SetActiveTab(it.Tab)
                    --[[ ВОЗВРАТ ПРОКРУТКИ.
                         Одна попытка через timer.Simple(0) не работала:
                         DScrollPanel зажимает SetScroll по высоте холста, а
                         она известна только ПОСЛЕ раскладки. Поэтому список
                         категорий после каждой галочки прыгал наверх (заказ
                         владельца 21.08). Теперь пробуем несколько кадров,
                         пока позиция реально не встанет. ]]
                    if prevScroll and prevScroll > 0 and not wantTab then
                        local rPnl = it.Panel
                        local restore
                        restore = function(tries)
                            if not IsValid(rPnl) then return end
                            local sp = pageScroll(rPnl)
                            if not (sp and IsValid(sp:GetVBar())) then return end
                            sp:InvalidateLayout(true)
                            sp:GetVBar():SetScroll(prevScroll)
                            if math.abs(sp:GetVBar():GetScroll() - prevScroll) > 1 and tries > 1 then
                                timer.Simple(0, function() restore(tries - 1) end)
                            end
                        end
                        timer.Simple(0, function() restore(8) end)
                    end
                    break
                end
            end
        end

        local bot = vgui.Create("DPanel", frame)
        bot:Dock(BOTTOM) bot:SetTall(44) bot:SetPaintBackground(false)

        if canEdit then
            local bSave = mkBtn(bot, "Сохранить матрицу доступа", CUI.green, 260, 32)
            bSave:Dock(RIGHT) bSave:DockMargin(0, 6, 12, 6)
            bSave.DoClick = function()
                net.Start(NET_SAVE) net.WriteTable(data) net.SendToServer()
            end
        else
            local note = vgui.Create("DLabel", bot)
            note:Dock(FILL) note:DockMargin(12, 0, 12, 0)
            note:SetFont("GRMDoorAcc_Normal") note:SetTextColor(CUI.yellow)
            note:SetText("Матрицу ордеров/тарана правит суперадмин. Вам доступны только категории.")
        end
    end

    net.Receive(NET_DATA, function()
        openAccessMenu(net.ReadTable() or {}, net.ReadTable() or {}, net.ReadTable() or {}, net.ReadBool())
    end)

    net.Receive(NET_RESULT, function()
        local ok = net.ReadBool()
        local msg = net.ReadString()
        if notification then
            notification.AddLegacy(msg, ok and NOTIFY_GENERIC or NOTIFY_ERROR, 4)
        else
            chat.AddText(ok and Color(100, 220, 100) or Color(255, 100, 100), "[Доступ Дверей] ", color_white, msg)
        end
    end)

    function AM.OpenMenu(tabName)
        if tabName == "Категории фракций" then tabName = "Категории" end
        if isstring(tabName) and tabName ~= "" then AM._wantTab = tabName end
        net.Start(NET_REQ) net.SendToServer()
    end

    concommand.Add("grm_door_access", AM.OpenMenu)

    hook.Add("OnPlayerChat", "GRM_DoorAccess_ChatCl", function(ply, text)
        if ply ~= LocalPlayer() then return end
        local msg = string.lower(string.Trim(text or ""))
        if msg == "/door_access" or msg == "!door_access" then
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
            if item.Tab and (item.Tab:GetText() == "Двери и Ордера" or item.Tab:GetText() == "Двери") then return end
        end
        local panel = vgui.Create("DPanel")
        panel:SetPaintBackground(false)

        local label = vgui.Create("DLabel", panel)
        label:Dock(TOP)
        label:SetTall(86)
        label:DockMargin(12, 12, 12, 4)
        label:SetWrap(true)
        label:SetText("Три контура дверей: ордер (/warrant + ключ на запертую дверь хозяина), таран (выбить, не ключ на E), управление (/door_access и категории). Назначение дверей карты в R — только суперадмин. Розыск и штрафы настраиваются отдельно.")
        label:SetTextColor(Color(220, 220, 230))

        local button = mkBtn(panel, "Настроить доступ: ордера, таран, управление", CUI.accent)
        button:Dock(TOP)
        button:SetTall(38)
        button:DockMargin(12, 8, 12, 0)
        button.DoClick = function() AM.OpenMenu() end

        local btnCats = mkBtn(panel, "Категории фракций (владельцы дверей)", CUI.green)
        btnCats:Dock(TOP)
        btnCats:SetTall(38)
        btnCats:DockMargin(12, 8, 12, 0)
        btnCats.DoClick = function() AM.OpenMenu("Категории") end

        sheet:AddSheet("Двери и Ордера", panel, "icon16/door.png")
    end
    -- Вкладка встраивается в меню фракций, как только оно появится.
    -- Раньше здесь крутился собственный опрашивающий таймер (0.5 с × 24) —
    -- и так в шести модулях доступов. Теперь единое ожидание условия
    -- GRM.Boot.When: одна проверка на всех, с таймаутом и без «вечных» реп.
    hook.Add("GRM_FactionsAdmin_BuildTabs", "GRM_DoorsAccess_Tab", installFactionsTab)

    print("[GRM Doors] Менеджер доступа к дверям v" .. AM.Version .. " загружен (клиент)")
end

-- Вечер-18: единый словарь slash-команд: имена живого PlayerSay-обработчика
-- вносятся во внешний реестр библиотеки (на режиме сверка идёт ДО ParseSay —
-- без регистрации команда стала бы «неизвестной»).
if GRM and GRM.Chat and GRM.Chat.RegisterExternalCommands then
    GRM.Chat.RegisterExternalCommands({ "/door_access" })
end
