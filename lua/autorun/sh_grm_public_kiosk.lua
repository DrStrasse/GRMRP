--[[--------------------------------------------------------------------
    GRM Public Kiosk v1.0 — гражданский терминал самообслуживания.

    Любой житель (без фракции). Не копирует TerminalR: только идея
    «подойти и пользоваться». Деньги и счета идут через GRM.Services /
    Wanted.Fines / Diplomas.
----------------------------------------------------------------------]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.PublicKiosk = GRM.PublicKiosk or {}
local K = GRM.PublicKiosk
K.Version = "1.0.0"
K.UseRange = 200

local NET_OPEN = "GRM_PublicKiosk_Open"
local NET_ACT  = "GRM_PublicKiosk_Act"
local NET_DATA = "GRM_PublicKiosk_Data"
local NET_RES  = "GRM_PublicKiosk_Result"

local function charKey(v)
    if GRM.Services and isfunction(GRM.Services.CharKey) then return GRM.Services.CharKey(v) end
    if IsValid(v) and v:IsPlayer() then
        if GRM.Identity and isfunction(GRM.Identity.CharacterKey) then return GRM.Identity.CharacterKey(v) end
        return tostring(v:SteamID64()) .. ":char1"
    end
    return tostring(v or "")
end

local function rpName(ply)
    if not IsValid(ply) then return "" end
    local n = ply:GetNWString("GRM_RPName", "")
    if n == "" then n = ply:Nick() end
    return n
end

if SERVER then
    util.AddNetworkString(NET_OPEN)
    util.AddNetworkString(NET_ACT)
    util.AddNetworkString(NET_DATA)
    util.AddNetworkString(NET_RES)

    local function result(ply, ok, msg)
        if not IsValid(ply) then return end
        net.Start(NET_RES) net.WriteBool(ok and true or false) net.WriteString(tostring(msg or "")) net.Send(ply)
    end

    local function snapshot(ply)
        local key = charKey(ply)
        local S, D = GRM.Services, GRM.Diplomas
        local F = GRM.Wanted and GRM.Wanted.Fines
        local E = GRM.Economy
        local W = GRM.Wanted
        local rec = W and W.Records and W.Records[key]
        local wanted = nil
        if istable(rec) and (tonumber(rec.level) or 0) > 0 then
            local reasons = {}
            for _, c in ipairs(rec.reasons or {}) do
                reasons[#reasons + 1] = ((c.code and c.code ~= "" and (c.code .. " ") or "") .. tostring(c.title or ""))
            end
            wanted = { level = rec.level, name = rec.name, reasons = table.concat(reasons, "; ") }
        end
        local warrants = {}
        if GRM.Doors and isfunction(GRM.Doors.ListWarrants) then
            for _, w in ipairs(GRM.Doors.ListWarrants(nil, false) or {}) do
                if istable(w) and tostring(w.sid or "") == key then
                    warrants[#warrants + 1] = {
                        number = w.number, type = w.type, reason = w.reason,
                        expires = w.expires, status = w.status,
                    }
                end
            end
        end
        local fines, invoices = {}, {}
        if F and isfunction(F.For) then
            for _, r in ipairs(F.For(key, true)) do
                fines[#fines + 1] = { id = r.id, amount = r.amount, paid = r.paid, reason = r.reason }
                if #fines >= 80 then break end
            end
        end
        if S and isfunction(S.InvoicesFor) then
            for _, r in ipairs(S.InvoicesFor(key, false)) do
                invoices[#invoices + 1] = {
                    id = r.id, title = r.title, amount = r.amount, paid = r.paid,
                    status = r.status, faction = r.faction,
                }
                if #invoices >= 80 then break end
            end
        end
        local services = {}
        if S and isfunction(S.ListServices) then
            for _, r in ipairs(S.ListServices({ onlyEnabled = true })) do
                services[#services + 1] = {
                    id = r.id, name = r.name, category = r.category,
                    price = r.price, provider = r.provider, desc = r.desc,
                }
                if #services >= 80 then break end
            end
        end
        local diplomas = {}
        if D and isfunction(D.For) then
            for _, r in ipairs(D.For(key, true)) do
                diplomas[#diplomas + 1] = {
                    number = r.number, institution = r.institution, specialty = r.specialty,
                    revoked = r.revoked, issued = r.issued,
                }
            end
        end
        return {
            name = rpName(ply), nick = ply:Nick(), key = key,
            faction = ply:GetNWString("GRM_Faction", ""),
            role = ply:GetNWString("GRM_Role", ""),
            cash = isfunction(GRM.GetBalance) and GRM.GetBalance(ply) or 0,
            bank = (E and isfunction(E.BankBalance)) and E.BankBalance(ply) or 0,
            wanted = wanted, warrants = warrants,
            fines = fines, invoices = invoices,
            debt = S and isfunction(S.DebtSummary) and S.DebtSummary(key) or { total = 0 },
            services = services, diplomas = diplomas,
            categories = S and S.Categories or {},
        }
    end

    function K.Open(ply, ent)
        if not (IsValid(ply) and ply:IsPlayer()) then return end
        if IsValid(ent) and ply:GetPos():DistToSqr(ent:GetPos()) > (K.UseRange * K.UseRange) then return end
        ply._grmKioskEnt = IsValid(ent) and ent or nil
        ply._grmATMEnt = ply._grmKioskEnt
        net.Start(NET_OPEN)
            net.WriteEntity(IsValid(ent) and ent or Entity(0))
            net.WriteTable(snapshot(ply))
        net.Send(ply)
    end

    local function push(ply)
        if not IsValid(ply) then return end
        net.Start(NET_DATA) net.WriteTable(snapshot(ply)) net.Send(ply)
    end

    local function near(ply)
        local ent = ply._grmKioskEnt
        if not IsValid(ent) then return false, "Терминал недоступен" end
        if ply:GetPos():DistToSqr(ent:GetPos()) > (K.UseRange * K.UseRange) then
            return false, "Вы отошли от терминала"
        end
        return true
    end

    net.Receive(NET_ACT, function(_, ply)
        if not IsValid(ply) then return end
        ply.GRM_KioskNext = ply.GRM_KioskNext or 0
        if CurTime() < ply.GRM_KioskNext then return end
        ply.GRM_KioskNext = CurTime() + 0.35
        local act = string.sub(net.ReadString(), 1, 24)
        local args = net.ReadTable() or {}
        local okN, why = near(ply)
        if not okN then return result(ply, false, why) end

        local S = GRM.Services
        if act == "pay_fine" then
            if not (S and isfunction(S.PayFine)) then return result(ply, false, "Оплата недоступна") end
            local ok, msg = S.PayFine(ply, args.id, args.amount, "auto")
            result(ply, ok and true or false, ok and ("Оплачено: " .. tostring(msg)) or tostring(msg))
        elseif act == "pay_invoice" then
            if not (S and isfunction(S.PayInvoice)) then return result(ply, false, "Оплата недоступна") end
            local ok, msg = S.PayInvoice(ply, args.id, args.amount, "auto")
            result(ply, ok and true or false, ok and ("Оплачено: " .. tostring(msg)) or tostring(msg))
        elseif act == "pay_all" then
            if not S then return result(ply, false, "Оплата недоступна") end
            local F = GRM.Wanted and GRM.Wanted.Fines
            local paid = 0
            if F and isfunction(F.For) then
                for _, rec in ipairs(F.For(ply, true)) do
                    local ok, res = S.PayFine(ply, rec.id, rec.amount - rec.paid, "auto")
                    if ok then paid = paid + (tonumber(res) or 0) end
                end
            end
            for _, rec in ipairs(S.InvoicesFor(ply, true)) do
                local ok, res = S.PayInvoice(ply, rec.id, rec.amount - rec.paid, "auto")
                if ok then paid = paid + (tonumber(res) or 0) end
            end
            result(ply, paid > 0, paid > 0 and ("Погашено: " .. tostring(paid)) or "Задолженности нет")
        elseif act == "order_service" then
            if not S then return result(ply, false, "Госуслуги недоступны") end
            local svc = S.ServiceByID(args.id)
            if not svc or svc.enabled == false then return result(ply, false, "Услуга недоступна") end
            if (tonumber(svc.price) or 0) <= 0 then return result(ply, false, "Бесплатная услуга — обратитесь в организацию") end
            local rec = {
                id = S._nextInvoice, target = charKey(ply), targetName = rpName(ply),
                issuer = "система", issuerName = "Гражданский терминал",
                faction = svc.provider, serviceID = svc.id, title = svc.name,
                amount = svc.price, paid = 0, status = "unpaid", issued = os.time(),
                orderSource = "kiosk", note = "Заказано через гражданский терминал",
            }
            S._nextInvoice = S._nextInvoice + 1
            S.Invoices[#S.Invoices + 1] = rec
            if S.SaveInvoices then S.SaveInvoices() end
            hook.Run("GRM_InvoiceIssued", ply, rec)
            local ok, res = S.PayInvoice(ply, rec.id, rec.amount, "auto")
            if ok then result(ply, true, "Услуга «" .. svc.name .. "» оплачена")
            else result(ply, true, "Счёт №" .. rec.id .. " создан, но не оплачен: " .. tostring(res)) end
        elseif act == "check_diploma" then
            local D = GRM.Diplomas
            if not D then return result(ply, false, "Реестр недоступен") end
            local rec = D.ByNumber(args.number)
            if not rec then return result(ply, false, "Диплом не найден") end
            result(ply, true, rec.revoked and ("АННУЛИРОВАН: " .. tostring(rec.number))
                or ("Действителен: " .. tostring(rec.number) .. " — " .. tostring(rec.graduateName or "") .. ", " .. tostring(rec.specialty or "")))
        elseif act == "call_911" then
            local EM = GRM["911"] or GRM.Emergency
            if not (EM and isfunction(EM.CreateCall)) then return result(ply, false, "Служба 911 недоступна") end
            local txt = string.Trim(tostring(args.text or ""))
            if txt == "" then return result(ply, false, "Опишите происшествие") end
            EM.CreateCall(ply, tostring(args.category or "police"), txt, ply:GetPos())
            result(ply, true, "Вызов принят")
        elseif act == "refresh" then
            -- only push
        else
            return result(ply, false, "Неизвестная операция")
        end
        push(ply)
    end)
end

if CLIENT then
    local snap, frame = {}, nil
    local function money(v)
        if GRM.FormatMoney then return GRM.FormatMoney(v) end
        return tostring(math.floor(tonumber(v) or 0)) .. " GRM"
    end
    local function act(a, t)
        net.Start(NET_ACT) net.WriteString(a) net.WriteTable(t or {}) net.SendToServer()
    end

    local CC = {
        bg = Color(16, 22, 30, 250), panel = Color(24, 32, 42, 245), header = Color(22, 38, 42, 255),
        accent = Color(70, 200, 170), text = Color(230, 238, 240), dim = Color(140, 160, 165),
        gold = Color(240, 200, 90), danger = Color(220, 80, 80), ok = Color(70, 190, 110),
    }

    local function mkBtn(p, txt, col, fn)
        local b = vgui.Create("DButton", p)
        b:SetText(txt) b:SetFont("DermaDefaultBold") b:SetTextColor(color_white)
        b.Paint = function(s, w, h)
            draw.RoundedBox(4, 0, 0, w, h, s:IsHovered() and col or Color(col.r * 0.72, col.g * 0.72, col.b * 0.72))
        end
        b.DoClick = function() surface.PlaySound("buttons/button15.wav") if fn then fn() end end
        return b
    end

    local function rebuild(body)
        body:Clear()
        local tabs = vgui.Create("DPropertySheet", body)
        tabs:Dock(FILL)

        -- Я
        local me = vgui.Create("DPanel", tabs)
        me.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, CC.panel) end
        local y = 16
        local lines = {
            "ФИО: " .. tostring(snap.name or ""),
            "Фракция: " .. ((snap.faction ~= "" and snap.faction) or "гражданский"),
            (snap.role ~= "" and ("Должность: " .. snap.role) or nil),
            "Наличные: " .. money(snap.cash) .. "   Счёт: " .. money(snap.bank),
        }
        if snap.wanted then
            lines[#lines + 1] = "РОЗЫСК: уровень " .. tostring(snap.wanted.level) .. " — " .. tostring(snap.wanted.reasons or "")
        else
            lines[#lines + 1] = "В розыске не значитесь."
        end
        if #(snap.warrants or {}) == 0 then
            lines[#lines + 1] = "Судебных ордеров на вас нет."
        else
            for _, w in ipairs(snap.warrants) do
                lines[#lines + 1] = ("Ордер №%s (%s): %s"):format(tostring(w.number or "?"), tostring(w.type or ""), tostring(w.reason or ""))
            end
        end
        for _, t in ipairs(lines) do
            if t then
                local l = vgui.Create("DLabel", me)
                l:SetPos(16, y) l:SetSize(860, 22) l:SetFont("DermaDefaultBold")
                l:SetTextColor(string.find(t, "РОЗЫСК", 1, true) and CC.danger or CC.text)
                l:SetText(t)
                y = y + 24
            end
        end
        tabs:AddSheet("Мои данные", me, "icon16/user.png")

        -- Долги
        local debt = vgui.Create("DPanel", tabs)
        debt.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, CC.panel) end
        local tot = (snap.debt and snap.debt.total) or 0
        local hd = vgui.Create("DLabel", debt)
        hd:SetPos(16, 10) hd:SetSize(400, 22) hd:SetFont("DermaDefaultBold")
        hd:SetTextColor(tot > 0 and CC.gold or CC.ok)
        hd:SetText("Итого к оплате: " .. money(tot))
        local bAll = mkBtn(debt, "Оплатить всё", CC.ok, function() act("pay_all", {}) end)
        bAll:SetPos(420, 8) bAll:SetSize(160, 26)
        local list = vgui.Create("DListView", debt)
        list:SetPos(16, 42) list:SetSize(900, 420)
        list:AddColumn("Тип"):SetFixedWidth(90)
        list:AddColumn("№"):SetFixedWidth(70)
        list:AddColumn("Сумма"):SetFixedWidth(120)
        list:AddColumn("Основание")
        for _, f in ipairs(snap.fines or {}) do
            local due = (f.amount or 0) - (f.paid or 0)
            if due > 0 then
                local line = list:AddLine("штраф", tostring(f.id), money(due), tostring(f.reason or ""))
                line._kind, line._id, line._due = "fine", f.id, due
            end
        end
        for _, inv in ipairs(snap.invoices or {}) do
            if inv.status == "unpaid" then
                local due = (inv.amount or 0) - (inv.paid or 0)
                local line = list:AddLine("счёт", tostring(inv.id), money(due), tostring(inv.title or ""))
                line._kind, line._id, line._due = "inv", inv.id, due
            end
        end
        local bPay = mkBtn(debt, "Оплатить выбранное", CC.accent, function()
            local i = list:GetSelectedLine()
            if not i then return end
            local row = list:GetLine(i)
            if not row then return end
            if row._kind == "fine" then act("pay_fine", { id = row._id, amount = row._due })
            else act("pay_invoice", { id = row._id, amount = row._due }) end
        end)
        bPay:SetPos(16, 470) bPay:SetSize(200, 28)
        tabs:AddSheet("Задолженность", debt, "icon16/money_delete.png")

        -- Услуги
        local svc = vgui.Create("DPanel", tabs)
        svc.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, CC.panel) end
        local sl = vgui.Create("DListView", svc)
        sl:SetPos(16, 12) sl:SetSize(900, 430)
        sl:AddColumn("Услуга"):SetFixedWidth(280)
        sl:AddColumn("Исполнитель"):SetFixedWidth(200)
        sl:AddColumn("Цена"):SetFixedWidth(120)
        sl:AddColumn("Описание")
        for _, s in ipairs(snap.services or {}) do
            local line = sl:AddLine(tostring(s.name), tostring(s.provider or "—"), money(s.price), tostring(s.desc or ""))
            line._id = s.id
        end
        local bOrd = mkBtn(svc, "Заказать и оплатить", CC.ok, function()
            local i = sl:GetSelectedLine()
            if not i then return end
            local row = sl:GetLine(i)
            if row and row._id then act("order_service", { id = row._id }) end
        end)
        bOrd:SetPos(16, 452) bOrd:SetSize(220, 28)
        tabs:AddSheet("Госуслуги", svc, "icon16/basket.png")

        -- Дипломы + 911
        local more = vgui.Create("DPanel", tabs)
        more.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, CC.panel) end
        local num = vgui.Create("DTextEntry", more)
        num:SetPos(16, 16) num:SetSize(280, 26) num:SetPlaceholderText("Номер диплома ГД-2026-…")
        local bChk = mkBtn(more, "Проверить диплом", CC.accent, function()
            act("check_diploma", { number = string.Trim(num:GetText() or "") })
        end)
        bChk:SetPos(306, 16) bChk:SetSize(180, 26)
        local dl = vgui.Create("DListView", more)
        dl:SetPos(16, 52) dl:SetSize(900, 220)
        dl:AddColumn("Номер"):SetFixedWidth(160)
        dl:AddColumn("Учреждение"):SetFixedWidth(280)
        dl:AddColumn("Специальность"):SetFixedWidth(280)
        dl:AddColumn("Статус")
        for _, d in ipairs(snap.diplomas or {}) do
            dl:AddLine(tostring(d.number), tostring(d.institution or ""), tostring(d.specialty or ""),
                d.revoked and "аннулирован" or "действителен")
        end
        local cat = vgui.Create("DComboBox", more)
        cat:SetPos(16, 290) cat:SetSize(180, 26)
        cat:AddChoice("Полиция", "police", true)
        cat:AddChoice("Медицина", "medical")
        cat:AddChoice("Пожарные", "fire")
        local txt = vgui.Create("DTextEntry", more)
        txt:SetPos(206, 290) txt:SetSize(500, 26) txt:SetPlaceholderText("Сообщение в 911…")
        local b911 = mkBtn(more, "Вызов 911", CC.danger, function()
            local _, c = cat:GetSelected()
            act("call_911", { category = c or "police", text = txt:GetText() })
        end)
        b911:SetPos(716, 290) b911:SetSize(140, 26)
        tabs:AddSheet("Документы и 911", more, "icon16/page_white_text.png")
    end

    local function openUI(ent)
        if IsValid(frame) then frame:Remove() end
        frame = vgui.Create("DFrame")
        frame:SetSize(math.Clamp(ScrW() * 0.72, 980, 1280), math.Clamp(ScrH() * 0.78, 620, 860))
        frame:Center() frame:SetTitle("") frame:MakePopup() frame:ShowCloseButton(false)
        frame.Paint = function(_, w, h)
            draw.RoundedBox(8, 0, 0, w, h, CC.bg)
            draw.RoundedBoxEx(8, 0, 0, w, 40, CC.header, true, true, false, false)
            draw.SimpleText(IsValid(ent) and ent.GetComputerName and ent:GetComputerName() or "ГРАЖДАНСКИЙ ТЕРМИНАЛ",
                "DermaDefaultBold", 16, 20, CC.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        local close = vgui.Create("DButton", frame)
        close:SetSize(28, 24) close:SetPos(frame:GetWide() - 36, 8)
        close:SetText("✕") close:SetTextColor(CC.dim)
        close.Paint = function(s, w, h) draw.RoundedBox(4, 0, 0, w, h, s:IsHovered() and CC.danger or Color(40, 50, 55)) end
        close.DoClick = function() frame:Close() end
        local body = vgui.Create("DPanel", frame)
        body:Dock(FILL) body:DockMargin(6, 42, 6, 6)
        body.Paint = function() end
        frame._body = body
        rebuild(body)
    end

    net.Receive(NET_OPEN, function()
        local ent = net.ReadEntity()
        snap = net.ReadTable() or {}
        openUI(ent)
    end)
    net.Receive(NET_DATA, function()
        snap = net.ReadTable() or {}
        if IsValid(frame) and IsValid(frame._body) then rebuild(frame._body) end
    end)
    net.Receive(NET_RES, function()
        local ok = net.ReadBool()
        local msg = net.ReadString()
        if msg == "" then return end
        notification.AddLegacy(msg, ok and NOTIFY_GENERIC or NOTIFY_ERROR, 5)
        surface.PlaySound(ok and "buttons/button14.wav" or "buttons/button10.wav")
    end)
end

print("[GRM PublicKiosk] v" .. K.Version .. " loaded")
