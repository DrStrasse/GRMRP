--[[
    Доступ служебных компьютеров.
    У каждого экземпляра свой список организаций (NW GRM_CompFactions).
    Пустой список — старое поведение (эвристика ведомства).
    Меню: /comp_access, /пк_доступ, консоль grm_comp_access.
]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.CompAccess = GRM.CompAccess or {}
local A = GRM.CompAccess
A.NW = "GRM_CompFactions"
A.Version = "1.1.0"

A.Classes = {
    grm_doc_computer = "Универсальный терминал документов",
    grm_comp_police = "Полиция порядка",
    grm_comp_military_police = "Жандармерия / ВС",
    grm_comp_security = "Спецслужбы",
    grm_comp_military = "Военкомат",
    grm_comp_traffic = "Автоинспекция",
    grm_comp_medical = "Госпиталь",
    grm_comp_education = "Образование",
    grm_comp_fire = "Пожарная диспетчерская",
    grm_comp_cityhall = "Мэрия",
    grm_comp_court = "Юстиция",
    grm_comp_public = "Гражданский терминал",
    grm_civil_vehicle_computer = "Гражданский рынок транспорта",
}

function A.FactionRows()
    local src = (SERVER and istable(Factions) and Factions)
        or (istable(FactionsData) and FactionsData) or {}
    if SERVER and GRM.VehicleDealer and GRM.VehicleDealer.FactionList then
        return GRM.VehicleDealer.FactionList()
    end
    local out = {}
    for name in pairs(src) do
        if isstring(name) and name ~= "" then
            local disp = (GRM.Factions and GRM.Factions.DisplayName and GRM.Factions.DisplayName(name)) or name
            out[#out + 1] = { key = name, name = tostring(disp) }
        end
    end
    table.sort(out, function(a, b) return string.lower(a.name) < string.lower(b.name) end)
    return out
end

function A.Parse(raw)
    local set = {}
    for part in string.gmatch(tostring(raw or ""), "([^,]+)") do
        local s = string.Trim(part)
        if s ~= "" then set[s] = true end
    end
    return set
end

function A.Encode(set)
    local out = {}
    for name, on in pairs(istable(set) and set or {}) do
        if on and tostring(name) ~= "" then out[#out + 1] = tostring(name) end
    end
    table.sort(out)
    return table.concat(out, ",")
end

function A.GetRaw(ent)
    if not IsValid(ent) then return "" end
    if ent.GetNWString then return tostring(ent:GetNWString(A.NW, "") or "") end
    return tostring(ent.GRMCompFactions or "")
end

function A.Set(ent, csv)
    if not IsValid(ent) then return false end
    csv = string.sub(string.Trim(tostring(csv or "")), 1, 512)
    ent.GRMCompFactions = csv
    if ent.SetNWString then ent:SetNWString(A.NW, csv) end
    if SERVER and duplicator and duplicator.StoreEntityModifier then
        duplicator.StoreEntityModifier(ent, "GRM_CompAccess", { factions = csv })
    end
    if SERVER and GRM.PermData and GRM.PermData.UpdateEntry then
        pcall(GRM.PermData.UpdateEntry, ent)
    end
    return true
end

local function sameFaction(a, b)
    a, b = tostring(a or ""), tostring(b or "")
    if a == "" or b == "" then return false end
    if a == b then return true end
    if string.lower(a) == string.lower(b) then return true end
    local ra, rb = a, b
    if GRM.Economy and GRM.Economy.ResolveFactionKey then
        ra = tostring(GRM.Economy.ResolveFactionKey(a) or a)
        rb = tostring(GRM.Economy.ResolveFactionKey(b) or b)
    elseif FactionsAPI and FactionsAPI.GetRegistrationName then
        ra = tostring(FactionsAPI.GetRegistrationName(a) or a)
        rb = tostring(FactionsAPI.GetRegistrationName(b) or b)
    end
    return ra == rb or string.lower(ra) == string.lower(rb)
end

function A.Allowed(ent, ply)
    if not IsValid(ply) then return false end
    if ply:IsSuperAdmin() then return true end
    if not IsValid(ent) then return true end
    local raw = A.GetRaw(ent)
    if raw == "" then return true end
    local fac = ply:GetNWString("GRM_Faction", "")
    if fac == "" then return false end
    for name in pairs(A.Parse(raw)) do
        if sameFaction(fac, name) then return true end
    end
    return false
end

function A.IsServiceComputer(ent)
    if not IsValid(ent) then return false end
    return A.Classes[ent:GetClass()] ~= nil
end

if SERVER then
    util.AddNetworkString("GRM_CompAccess_List")
    util.AddNetworkString("GRM_CompAccess_ListReq")
    util.AddNetworkString("GRM_CompAccess_Apply")
    util.AddNetworkString("GRM_CompAccess_MenuReq")
    util.AddNetworkString("GRM_CompAccess_Menu")
    util.AddNetworkString("GRM_CompAccess_Save")

    if duplicator and duplicator.RegisterEntityModifier then
        duplicator.RegisterEntityModifier("GRM_CompAccess", function(_, ent, data)
            if IsValid(ent) and istable(data) then A.Set(ent, data.factions) end
        end)
    end

    local function canEdit(ply)
        return IsValid(ply) and (ply:IsSuperAdmin() or ply:IsAdmin())
    end

    local function persistAccess(class)
        if not (GRM.PermData and GRM.PermData.AddExtract) then return end
        GRM.PermData.AddExtract(class, function(ent)
            if not IsValid(ent) then return nil end
            local raw = A.GetRaw(ent)
            if raw == "" then return nil end
            return { compFactions = raw }
        end)
        GRM.PermData.AddApply(class, function(ent, data)
            if not IsValid(ent) or not istable(data) then return end
            if isstring(data.compFactions) then A.Set(ent, data.compFactions) end
        end)
    end
    for class in pairs(A.Classes) do persistAccess(class) end

    local function packComputers()
        local out = {}
        for class, label in pairs(A.Classes) do
            for _, ent in ipairs(ents.FindByClass(class)) do
                if IsValid(ent) then
                    local title = (isfunction(ent.GetComputerName) and ent:GetComputerName()) or ""
                    if title == "" then title = label end
                    local pos = ent:GetPos()
                    out[#out + 1] = {
                        idx = ent:EntIndex(),
                        class = class,
                        label = label,
                        title = tostring(title),
                        factions = A.GetRaw(ent),
                        x = math.floor(pos.x), y = math.floor(pos.y), z = math.floor(pos.z),
                    }
                end
            end
        end
        table.sort(out, function(a, b)
            if a.label == b.label then return tostring(a.title) < tostring(b.title) end
            return a.label < b.label
        end)
        return out
    end

    local function sendMenu(ply)
        if not canEdit(ply) then return end
        net.Start("GRM_CompAccess_Menu")
            net.WriteTable({ factions = A.FactionRows(), computers = packComputers() })
        net.Send(ply)
    end

    net.Receive("GRM_CompAccess_ListReq", function(_, ply)
        if not IsValid(ply) then return end
        if GRM.Net and GRM.Net.Guard and not GRM.Net.Guard(ply, "comp.access.list", { rate = 1, burst = 3 }, {}) then return end
        net.Start("GRM_CompAccess_List")
            net.WriteTable(A.FactionRows())
        net.Send(ply)
    end)

    net.Receive("GRM_CompAccess_MenuReq", function(_, ply)
        if not canEdit(ply) then return end
        if GRM.Net and GRM.Net.Guard and not GRM.Net.Guard(ply, "comp.access.menu", { rate = 1, burst = 2 }, {}) then return end
        sendMenu(ply)
    end)

    local function applyTo(ent, csv, ply)
        if not A.IsServiceComputer(ent) then
            if GRM.Notify then GRM.Notify(ply, "Это не служебный компьютер.", 255, 160, 90) end
            return false
        end
        A.Set(ent, csv)
        if GRM.Notify then
            GRM.Notify(ply, csv == "" and "Доступ ПК сброшен (как раньше, по ведомству)."
                or ("Доступ ПК записан: " .. csv), 100, 220, 130)
        end
        return true
    end

    net.Receive("GRM_CompAccess_Apply", function(_, ply)
        if not canEdit(ply) then return end
        local csv = string.sub(net.ReadString() or "", 1, 512)
        local tr = ply:GetEyeTrace()
        local ent = IsValid(tr.Entity) and tr.Entity or nil
        if not IsValid(ent) then
            if GRM.Notify then GRM.Notify(ply, "Наведитесь на служебный компьютер.", 255, 160, 90) end
            return
        end
        applyTo(ent, csv, ply)
    end)

    net.Receive("GRM_CompAccess_Save", function(_, ply)
        if not canEdit(ply) then return end
        if GRM.Net and GRM.Net.Guard and not GRM.Net.Guard(ply, "comp.access.save", { rate = 1, burst = 4 }, {}) then return end
        local idx = net.ReadUInt(16)
        local csv = string.sub(net.ReadString() or "", 1, 512)
        local ent = Entity(idx)
        if not IsValid(ent) then
            if GRM.Notify then GRM.Notify(ply, "Компьютер уже убран с карты.", 255, 160, 90) end
            sendMenu(ply)
            return
        end
        applyTo(ent, csv, ply)
        sendMenu(ply)
    end)

    local function openCmd(ply)
        if not canEdit(ply) then
            if GRM.Notify then GRM.Notify(ply, "Доступ к меню ПК — только админам.", 255, 120, 100) end
            return
        end
        sendMenu(ply)
    end
    concommand.Add("grm_comp_access", openCmd)

    hook.Add("PlayerSay", "GRM_CompAccess_Chat", function(ply, text, teamSays)
        local pack = { tostring(text or ""), SkipPlayerSay = false }
            if not istable(pack) or not isstring(pack[1]) then return end
            local low = string.lower(string.Trim(pack[1]))
            if low == "/comp_access" or low == "/pc_access" or low == "/пк_доступ" or low == "/компьютеры" then
                openCmd(ply)
                pack[1] = ""
                pack.SkipPlayerSay = true
            end

        if pack.SkipPlayerSay == true then return "" end
    end)
end

if CLIENT then
    A.Rows = A.Rows or {}
    net.Receive("GRM_CompAccess_List", function()
        A.Rows = net.ReadTable() or {}
        hook.Run("GRM_CompAccess_List", A.Rows)
    end)

    surface.CreateFont("GRMCompAcc_Title", { font = "Roboto", size = 20, weight = 800, extended = true })
    surface.CreateFont("GRMCompAcc_Body", { font = "Roboto", size = 13, weight = 500, extended = true })
    surface.CreateFont("GRMCompAcc_Small", { font = "Roboto", size = 11, weight = 500, extended = true })

    local C = {
        bg = Color(16, 20, 28, 252), side = Color(12, 15, 22, 255),
        card = Color(22, 28, 38, 240), hover = Color(36, 46, 62, 240),
        border = Color(38, 48, 66, 200), gold = Color(245, 195, 65),
        green = Color(55, 185, 110), accent = Color(65, 145, 235),
        text = Color(240, 244, 250), dim = Color(155, 170, 190),
    }

    local function openMenu(d)
        d = istable(d) and d or {}
        if IsValid(A._frame) then A._frame:Remove() end
        local f = vgui.Create("DFrame")
        A._frame = f
        f:SetSize(960, 620)
        f:Center()
        f:SetTitle("")
        f:MakePopup()
        f:ShowCloseButton(false)
        f.Paint = function(_, w, h)
            draw.RoundedBox(8, 0, 0, w, h, C.bg)
            draw.RoundedBoxEx(8, 0, 0, w, 46, C.side, true, true, false, false)
            draw.SimpleText("ДОСТУП СЛУЖЕБНЫХ КОМПЬЮТЕРОВ", "GRMCompAcc_Title", 16, 23, C.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText("/comp_access  ·  пустой список = доступ по ведомству", "GRMCompAcc_Small", w - 50, 23, C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
        local x = vgui.Create("DButton", f)
        x:SetSize(32, 26) x:SetPos(920, 10) x:SetText("")
        x.Paint = function(s, w, h)
            draw.RoundedBox(4, 0, 0, w, h, s:IsHovered() and Color(225, 70, 70) or C.card)
            draw.SimpleText("✕", "GRMCompAcc_Body", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        x.DoClick = function() f:Close() end

        local left = vgui.Create("DScrollPanel", f)
        left:SetPos(12, 56) left:SetSize(360, 552)
        local right = vgui.Create("DPanel", f)
        right:SetPos(384, 56) right:SetSize(564, 552)
        right.Paint = function(_, w, h)
            draw.RoundedBox(8, 0, 0, w, h, C.card)
        end

        local comps = istable(d.computers) and d.computers or {}
        local facs = istable(d.factions) and d.factions or {}
        local selected

        local function paintRight()
            right:Clear()
            if not selected then
                local hint = vgui.Create("DLabel", right)
                hint:Dock(FILL) hint:SetFont("GRMCompAcc_Body") hint:SetTextColor(C.dim)
                hint:SetContentAlignment(5)
                hint:SetText("Выберите компьютер слева.\nГалочки — кому можно пользоваться этим ПК.")
                return
            end
            local head = vgui.Create("DPanel", right)
            head:Dock(TOP) head:SetTall(72) head:SetPaintBackground(false)
            head.Paint = function(_, w)
                draw.SimpleText(selected.title, "GRMCompAcc_Title", 14, 16, C.text)
                draw.SimpleText(selected.label .. "  ·  #" .. tostring(selected.idx)
                    .. ("  ·  %d %d %d"):format(selected.x or 0, selected.y or 0, selected.z or 0),
                    "GRMCompAcc_Small", 14, 44, C.dim)
            end
            local set = A.Parse(selected.factions)
            local sc = vgui.Create("DScrollPanel", right)
            sc:Dock(FILL) sc:DockMargin(10, 0, 10, 8)
            for _, row in ipairs(facs) do
                local cb = vgui.Create("DCheckBoxLabel", sc)
                cb:Dock(TOP) cb:SetTall(22) cb:DockMargin(4, 2, 4, 2)
                cb:SetText(row.name .. (row.key ~= row.name and ("  [" .. row.key .. "]") or ""))
                cb:SetTextColor(C.text)
                cb:SetValue(set[row.key] == true)
                cb.OnChange = function(_, v) set[row.key] = v == true or nil end
            end
            if #facs == 0 then
                local empty = vgui.Create("DLabel", sc)
                empty:Dock(TOP) empty:SetText("Организаций нет — создайте их в /factions.")
                empty:SetTextColor(C.dim)
            end
            local bar = vgui.Create("DPanel", right)
            bar:Dock(BOTTOM) bar:SetTall(48) bar:SetPaintBackground(false)
            local function mk(lab, col, fn)
                local b = vgui.Create("DButton", bar)
                b:Dock(LEFT) b:SetWide(170) b:DockMargin(10, 10, 0, 10) b:SetText("")
                b.Paint = function(s, w, h)
                    draw.RoundedBox(6, 0, 0, w, h, s:IsHovered() and Color(math.min(255, col.r + 20), math.min(255, col.g + 20), math.min(255, col.b + 20)) or col)
                    draw.SimpleText(lab, "GRMCompAcc_Body", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
                b.DoClick = fn
            end
            mk("СОХРАНИТЬ", C.green, function()
                net.Start("GRM_CompAccess_Save")
                    net.WriteUInt(math.Clamp(tonumber(selected.idx) or 0, 0, 65535), 16)
                    net.WriteString(A.Encode(set))
                net.SendToServer()
            end)
            mk("СБРОСИТЬ (ВЕДОМСТВО)", C.accent, function()
                net.Start("GRM_CompAccess_Save")
                    net.WriteUInt(math.Clamp(tonumber(selected.idx) or 0, 0, 65535), 16)
                    net.WriteString("")
                net.SendToServer()
            end)
        end

        if #comps == 0 then
            local empty = vgui.Create("DPanel", left)
            empty:Dock(TOP) empty:SetTall(80)
            empty.Paint = function(_, w, h)
                draw.RoundedBox(8, 0, 0, w, h, C.card)
                draw.SimpleText("На карте нет служебных ПК.", "GRMCompAcc_Body", w / 2, 28, C.dim, TEXT_ALIGN_CENTER)
                draw.SimpleText("Поставьте тулом «GRM Служебное оборудование».", "GRMCompAcc_Small", w / 2, 50, C.dim, TEXT_ALIGN_CENTER)
            end
        end
        for _, rec in ipairs(comps) do
            local b = vgui.Create("DButton", left)
            b:Dock(TOP) b:SetTall(52) b:DockMargin(0, 0, 6, 6) b:SetText("")
            b.Paint = function(s, w, h)
                local on = selected and selected.idx == rec.idx
                draw.RoundedBox(6, 0, 0, w, h, on and C.accent or (s:IsHovered() and C.hover or C.card))
                draw.SimpleText(rec.title, "GRMCompAcc_Body", 10, 10, C.text)
                local acc = (rec.factions or "") == "" and "по ведомству" or rec.factions
                draw.SimpleText(rec.label .. "  ·  " .. acc, "GRMCompAcc_Small", 10, 30, on and C.text or C.dim)
            end
            b.DoClick = function() selected = rec paintRight() end
        end
        paintRight()
    end

    net.Receive("GRM_CompAccess_Menu", function()
        openMenu(net.ReadTable() or {})
    end)

    function A.OpenMenu()
        net.Start("GRM_CompAccess_MenuReq")
        net.SendToServer()
    end
    concommand.Add("grm_comp_access", A.OpenMenu)

    hook.Add("GRMRPChat_ClientCommand", "GRM_CompAccess_ChatCl", function(ply, text)
        local pack = { tostring(text or ""), SkipPlayerSay = false }
            if ply ~= LocalPlayer() or not istable(pack) then return end
            local low = string.lower(string.Trim(tostring(pack[1] or "")))
            if low == "/comp_access" or low == "/pc_access" or low == "/пк_доступ" or low == "/компьютеры" then
                A.OpenMenu()
                pack[1] = ""
                pack.SkipPlayerSay = true
            end

        if pack.SkipPlayerSay == true then return true end
    end)

    hook.Add("GRM_FactionsAdmin_BuildTabs", "GRM_CompAccess_Tab", function(sheet)
        if not IsValid(sheet) then return end
        for _, item in ipairs(sheet.Items or {}) do
            if item.Tab and item.Tab:GetText() == "Компьютеры" then return end
        end
        local p = vgui.Create("DPanel")
        p:SetPaintBackground(false)
        local l = vgui.Create("DLabel", p)
        l:Dock(TOP) l:SetTall(56) l:DockMargin(12, 12, 12, 4)
        l:SetWrap(true) l:SetTextColor(Color(220, 220, 230))
        l:SetText("Кому можно пользоваться каждым служебным компьютером на карте. Пустой список — доступ как раньше, по ведомству.")
        local b = vgui.Create("DButton", p)
        b:Dock(TOP) b:SetTall(36) b:DockMargin(12, 8, 12, 0) b:SetText("Открыть доступ компьютеров")
        b.DoClick = A.OpenMenu
        sheet:AddSheet("Компьютеры", p, "icon16/computer.png")
    end)
end

if GRM.Access and GRM.Access.Register then
    GRM.Access.Register("comp.access", {
        label = "Служебные компьютеры: настройка доступа",
        scope = "character",
        levels = { admin = true },
    })
end

print("[GRM CompAccess] v" .. A.Version .. " loaded (" .. (SERVER and "Server" or "Client") .. ")")

-- Вечер-18: команды пересажены с мёртвого входа EasyChat (PlayerSayTransform)
-- на боевой контракт библиотеки GRMRPChat — имена в едином внешнем реестре,
-- иначе чат съел бы их как «неизвестные» и по цепочке PlayerSay вызвал бы
-- обработчики этого файла.
if GRM and GRM.Chat and GRM.Chat.RegisterExternalCommands then
    GRM.Chat.RegisterExternalCommands({ "/comp_access", "/pc_access", "/компьютеры", "/пк_доступ" })
end
