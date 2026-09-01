--[[--------------------------------------------------------------------
    grm_bank_computer — клиент: 3D2D + меню в стиле GRM (не Derma)
----------------------------------------------------------------------]]
include("shared.lua")

surface.CreateFont("GRMBComp_Title", { font = "Roboto", size = 18, weight = 900, extended = true })
surface.CreateFont("GRMBComp_Head",  { font = "Roboto", size = 15, weight = 700, extended = true })
surface.CreateFont("GRMBComp_Norm",  { font = "Roboto", size = 13, weight = 500, extended = true })
surface.CreateFont("GRMBComp_Small", { font = "Roboto", size = 11, weight = 400, extended = true })
surface.CreateFont("GRMBComp_Stat",  { font = "Roboto", size = 20, weight = 800, extended = true })

local function money(n)
    return GRM and GRM.Format and GRM.Format(tonumber(n) or 0) or (tostring(math.floor(tonumber(n) or 0)) .. " GRM")
end

local function facName(key)
    if GRM.Factions and GRM.Factions.DisplayName then return GRM.Factions.DisplayName(key) end
    return tostring(key or "")
end

function ENT:Draw()
    self:DrawModel()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    if ply:GetPos():DistToSqr(self:GetPos()) > (500 * 500) then return end

    local pos = self:GetPos() + Vector(0, 0, 24)
    local ang = EyeAngles()
    ang:RotateAroundAxis(ang:Forward(), 90)
    ang:RotateAroundAxis(ang:Right(), 90)

    cam.Start3D2D(pos, Angle(0, ang.y, 90), 0.07)
        draw.RoundedBox(6, -150, -30, 300, 60, Color(16, 20, 28, 240))
        draw.RoundedBoxEx(6, -150, -30, 300, 26, Color(12, 15, 22, 255), true, true, false, false)
        draw.SimpleText("КАЗНА GRM", "GRMBComp_Head", 0, -17, Color(245, 195, 65), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("[E]  госбюджет · субсидии · хранилища", "GRMBComp_Small", 0, 12, Color(200, 210, 225), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    cam.End3D2D()
end

local C = {
    bg      = Color(16, 20, 28, 252),
    sidebar = Color(12, 15, 22, 255),
    panel   = Color(22, 28, 38, 245),
    card    = Color(28, 36, 48, 245),
    hover   = Color(36, 46, 62, 245),
    border  = Color(38, 48, 66, 200),
    accent  = Color(65, 145, 235),
    gold    = Color(245, 195, 65),
    green   = Color(55, 185, 110),
    red     = Color(225, 70, 70),
    teal    = Color(75, 195, 170),
    text    = Color(240, 244, 250),
    dim     = Color(155, 170, 190),
}

local function sendAction(comp, action, target, amount)
    if not IsValid(comp) then return end
    net.Start("GRM_BankComp_Action")
        net.WriteEntity(comp)
        net.WriteString(action)
        net.WriteString(target or "")
        net.WriteUInt(math.max(0, math.floor(tonumber(amount) or 0)), 32)
    net.SendToServer()
end

local function grmPrompt(title, hint, def, cb)
    local m = vgui.Create("DFrame")
    m:SetTitle("")
    m:SetSize(420, 176)
    m:Center()
    m:MakePopup()
    m:ShowCloseButton(false)
    m.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, C.bg)
        draw.RoundedBoxEx(8, 0, 0, w, 40, C.sidebar, true, true, false, false)
        surface.SetDrawColor(C.border)
        surface.DrawOutlinedRect(0, 0, w, h)
        draw.SimpleText(title, "GRMBComp_Head", 16, 20, C.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    local te = vgui.Create("DTextEntry", m)
    te:SetPos(16, 56)
    te:SetSize(388, 34)
    te:SetNumeric(true)
    te:SetFont("GRMBComp_Norm")
    te:SetTextColor(C.text)
    te:SetPlaceholderText(hint or "Сумма GRM")
    te:SetText(tostring(def or ""))
    te.Paint = function(s, w, h)
        draw.RoundedBox(5, 0, 0, w, h, Color(24, 30, 40, 245))
        surface.SetDrawColor(C.border)
        surface.DrawOutlinedRect(0, 0, w, h)
        if (s:GetText() or "") == "" and not s:HasFocus() then
            draw.SimpleText(hint or "Сумма GRM", "GRMBComp_Small", 10, h / 2, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        s:DrawTextEntryText(C.text, C.accent, C.text)
    end
    local function mk(x, lab, col, fn)
        local b = vgui.Create("DButton", m)
        b:SetPos(x, 108)
        b:SetSize(188, 48)
        b:SetText("")
        b.Paint = function(s, w, h)
            draw.RoundedBox(6, 0, 0, w, h, s:IsHovered() and Color(math.min(255, col.r + 20), math.min(255, col.g + 20), math.min(255, col.b + 20)) or col)
            draw.SimpleText(lab, "GRMBComp_Head", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        b.DoClick = fn
        return b
    end
    mk(16, "ОТМЕНА", C.card, function() m:Close() end)
    mk(216, "ПОДТВЕРДИТЬ", C.accent, function()
        local n = math.floor(tonumber(te:GetValue()) or 0)
        m:Close()
        if n > 0 and cb then cb(n) end
    end)
    te.OnEnter = function()
        local n = math.floor(tonumber(te:GetValue()) or 0)
        m:Close()
        if n > 0 and cb then cb(n) end
    end
    te:RequestFocus()
end

local function pickFaction(d, title, cb)
    local names = {}
    for n in pairs(d.factions or {}) do names[#names + 1] = n end
    table.sort(names, function(a, b) return string.lower(facName(a)) < string.lower(facName(b)) end)
    if #names == 0 then notification.AddLegacy("Нет организаций", NOTIFY_ERROR, 3) return end
    local m = vgui.Create("DFrame")
    m:SetTitle("")
    m:SetSize(460, 420)
    m:Center()
    m:MakePopup()
    m:ShowCloseButton(false)
    m.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, C.bg)
        draw.RoundedBoxEx(8, 0, 0, w, 42, C.sidebar, true, true, false, false)
        draw.SimpleText(title, "GRMBComp_Head", 16, 21, C.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    local x = vgui.Create("DButton", m)
    x:SetPos(418, 8) x:SetSize(28, 26) x:SetText("")
    x.Paint = function(s, w, h)
        draw.RoundedBox(4, 0, 0, w, h, s:IsHovered() and C.red or C.card)
        draw.SimpleText("✕", "GRMBComp_Norm", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    x.DoClick = function() m:Close() end
    local sc = vgui.Create("DScrollPanel", m)
    sc:SetPos(12, 52) sc:SetSize(436, 354)
    for _, key in ipairs(names) do
        local info = d.factions[key] or {}
        local row = vgui.Create("DButton", sc)
        row:Dock(TOP) row:SetTall(52) row:DockMargin(0, 0, 4, 6) row:SetText("")
        row.Paint = function(s, w, h)
            draw.RoundedBox(6, 0, 0, w, h, s:IsHovered() and C.hover or C.panel)
            surface.SetDrawColor(C.border)
            surface.DrawOutlinedRect(0, 0, w, h)
            draw.SimpleText(facName(key), "GRMBComp_Head", 12, 16, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText("казна  " .. money(info.budget or 0) .. "   •   налог  " .. math.floor((info.taxRate or 0.05) * 100) .. "%",
                "GRMBComp_Small", 12, 36, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        row.DoClick = function()
            m:Close()
            cb(key)
        end
    end
end

net.Receive("GRM_BankComp_Open", function()
    local comp = net.ReadEntity()
    local d = net.ReadTable() or {}
    if not IsValid(comp) then return end

    if IsValid(GRM._bankCompFrame) then GRM._bankCompFrame:Remove() end
    local f = vgui.Create("DFrame")
    GRM._bankCompFrame = f
    f:SetSize(math.Clamp(ScrW() * 0.62, 860, 1100), math.Clamp(ScrH() * 0.72, 560, 720))
    f:Center()
    f:SetTitle("")
    f:MakePopup()
    f:ShowCloseButton(false)
    f.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, C.bg)
        draw.RoundedBoxEx(8, 0, 0, w, 48, C.sidebar, true, true, false, false)
        draw.SimpleText("КАЗНА И ГОСБЮДЖЕТ", "GRMBComp_Title", 18, 24, C.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("компьютер управления банком", "GRMBComp_Small", 280, 24, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local btnX = vgui.Create("DButton", f)
    btnX:SetSize(34, 28)
    btnX:SetPos(f:GetWide() - 44, 10)
    btnX:SetText("")
    btnX.Paint = function(s, w, h)
        draw.RoundedBox(4, 0, 0, w, h, s:IsHovered() and C.red or C.card)
        draw.SimpleText("✕", "GRMBComp_Head", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    btnX.DoClick = function() f:Remove() end

    local body = vgui.Create("DPanel", f)
    body:Dock(FILL)
    body:DockMargin(0, 48, 0, 0)
    body:SetPaintBackground(false)

    local side = vgui.Create("DPanel", body)
    side:Dock(LEFT)
    side:SetWide(210)
    side.Paint = function(_, w, h)
        draw.RoundedBoxEx(0, 0, 0, w, h, C.sidebar, false, false, true, false)
        surface.SetDrawColor(C.border)
        surface.DrawLine(w - 1, 0, w - 1, h)
    end

    local content = vgui.Create("DPanel", body)
    content:Dock(FILL)
    content:DockMargin(12, 10, 12, 10)
    content:SetPaintBackground(false)

    local tabs = {}
    local current

    local function selectTab(key)
        current = key
        for k, b in pairs(tabs) do b.active = (k == key) end
        content:Clear()
        if tabs[key] and tabs[key].build then tabs[key].build(content) end
    end

    local function addNav(key, label, build)
        local b = vgui.Create("DButton", side)
        b:Dock(TOP)
        b:SetTall(40)
        b:DockMargin(8, 8, 8, 0)
        b:SetText("")
        b.active = false
        b.build = build
        b.Paint = function(s, w, h)
            if s.active then
                draw.RoundedBox(6, 0, 0, w, h, C.accent)
            elseif s:IsHovered() then
                draw.RoundedBox(6, 0, 0, w, h, C.hover)
            end
            draw.SimpleText(label, "GRMBComp_Norm", 14, h / 2, s.active and color_white or C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        b.DoClick = function() selectTab(key) end
        tabs[key] = b
    end

    local function summaryRow(parent)
        local summary = vgui.Create("DPanel", parent)
        summary:Dock(TOP)
        summary:SetTall(92)
        summary:DockMargin(0, 0, 0, 10)
        summary.Paint = function(_, w, h)
            local cw = math.floor((w - 16) / 3)
            local function box(x, t, v, col)
                draw.RoundedBox(6, x, 0, cw, h, C.panel)
                surface.SetDrawColor(C.border)
                surface.DrawOutlinedRect(x, 0, cw, h)
                draw.SimpleText(t, "GRMBComp_Small", x + 12, 16, C.dim)
                draw.SimpleText(v, "GRMBComp_Stat", x + 12, 46, col)
            end
            box(0, "ГОСБЮДЖЕТ", money(d.stateBudget or 0), C.gold)
            local vtxt = money(d.nearestVaultHeld or d.totalHeld or 0)
            box(cw + 8, "ХРАНИЛИЩЕ", vtxt, C.green)
            local st = "нет рядом"
            local scol = C.dim
            if d.press and d.press.found then
                st = d.press.broken and "перегрев" or (d.press.active and "печатает" or "выкл")
                scol = d.press.broken and C.red or (d.press.active and C.green or C.dim)
            end
            box((cw + 8) * 2, "ПЕЧАТНЫЙ СТАНОК", st, scol)
        end
    end

    local function actionCard(parent, title, desc, lab, col, fn)
        local p = vgui.Create("DPanel", parent)
        p:Dock(TOP)
        p:SetTall(72)
        p:DockMargin(0, 0, 0, 8)
        p.Paint = function(_, w, h)
            draw.RoundedBox(6, 0, 0, w, h, C.panel)
            surface.SetDrawColor(C.border)
            surface.DrawOutlinedRect(0, 0, w, h)
            draw.SimpleText(title, "GRMBComp_Head", 14, 20, C.text)
            draw.SimpleText(desc, "GRMBComp_Small", 14, 46, C.dim)
        end
        local b = vgui.Create("DButton", p)
        b:Dock(RIGHT)
        b:DockMargin(0, 18, 12, 18)
        b:SetWide(200)
        b:SetText("")
        b.Paint = function(s, w, h)
            local c = s:IsHovered() and Color(math.min(255, col.r + 22), math.min(255, col.g + 22), math.min(255, col.b + 22)) or col
            draw.RoundedBox(5, 0, 0, w, h, c)
            draw.SimpleText(lab, "GRMBComp_Norm", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        b.DoClick = fn
    end

    addNav("dist", "Распределение", function(pnl)
        summaryRow(pnl)
        actionCard(pnl, "Хранилище → госбюджет",
            "Наличные из вольта зачисляются в казну сервера",
            "В КАЗНУ", C.gold, function()
                grmPrompt("Зачисление в госбюджет", "Сумма из хранилища", "50000", function(amt)
                    sendAction(comp, "vault_to_state", "", amt)
                end)
            end)
        actionCard(pnl, "Госбюджет → хранилище",
            "Выделение казны в физический запас (инкассация / выдача)",
            "В ХРАНИЛИЩЕ", C.green, function()
                grmPrompt("Выделение в хранилище", "Сумма из госбюджета", "50000", function(amt)
                    sendAction(comp, "state_to_vault", "", amt)
                end)
            end)
        actionCard(pnl, "Хранилище → казна фракции",
            "Прямой перевод наличного резерва в бюджет организации",
            "ВО ФРАКЦИЮ", C.accent, function()
                pickFaction(d, "Кому перевести из хранилища", function(key)
                    grmPrompt("Перевод «" .. facName(key) .. "»", "Сумма из хранилища", "50000", function(amt)
                        sendAction(comp, "vault_to_faction", key, amt)
                    end)
                end)
            end)
        actionCard(pnl, "Госсубсидия фракции",
            "Официальное финансирование из казны — та же казна, что видит автопарк",
            "СУБСИДИЯ", Color(130, 90, 210), function()
                pickFaction(d, "Кому выдать субсидию", function(key)
                    grmPrompt("Субсидия «" .. facName(key) .. "»", "Сумма из госбюджета", "100000", function(amt)
                        sendAction(comp, "state_to_faction", key, amt)
                    end)
                end)
            end)
    end)

    addNav("press", "Печатный станок", function(pnl)
        summaryRow(pnl)
        if not (d.press and d.press.found) then
            local empty = vgui.Create("DPanel", pnl)
            empty:Dock(FILL)
            empty.Paint = function(_, w, h)
                draw.RoundedBox(6, 0, 0, w, 80, C.panel)
                draw.SimpleText("Станок (grm_money_press) не найден в радиусе 1200.", "GRMBComp_Norm", 16, 28, C.dim)
                draw.SimpleText("Поставьте печатный станок рядом с этим компьютером.", "GRMBComp_Small", 16, 50, C.dim)
            end
            return
        end
        local pInfo = vgui.Create("DPanel", pnl)
        pInfo:Dock(TOP)
        pInfo:SetTall(88)
        pInfo:DockMargin(0, 0, 0, 10)
        pInfo.Paint = function(_, w, h)
            draw.RoundedBox(6, 0, 0, w, h, C.panel)
            draw.SimpleText("ПАРАМЕТРЫ СТАНКА", "GRMBComp_Head", 14, 18, C.text)
            draw.SimpleText((d.press.active and "печатает" or "выключен") .. "   •   нагрев " .. tostring(d.press.heat or 0) .. "°",
                "GRMBComp_Norm", 14, 44, d.press.active and C.green or C.dim)
            draw.SimpleText("партия " .. money(d.press.printAmount or 5000) .. "   •   буфер " .. money(d.press.buffer or 0),
                "GRMBComp_Norm", 14, 66, C.gold)
        end
        local function mk(lab, col, act)
            local b = vgui.Create("DButton", pnl)
            b:Dock(TOP) b:SetTall(40) b:DockMargin(0, 0, 0, 8) b:SetText("")
            b.Paint = function(s, w, h)
                local c = s:IsHovered() and Color(math.min(255, col.r + 20), math.min(255, col.g + 20), math.min(255, col.b + 20)) or col
                draw.RoundedBox(5, 0, 0, w, h, c)
                draw.SimpleText(lab, "GRMBComp_Norm", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            b.DoClick = function() sendAction(comp, act, "", 0) end
        end
        mk(d.press.active and "ПРИОСТАНОВИТЬ ПЕЧАТЬ" or "ЗАПУСТИТЬ ПЕЧАТЬ", d.press.active and C.red or C.green, "press_toggle")
        mk("ОХЛАДИТЬ СТАНОК", C.accent, "press_cool")
        mk("ВЫДАТЬ ПАЛЛЕТУ ИЗ БУФЕРА", C.gold, "press_flush_buffer")
    end)

    addNav("fac", "Казны фракций", function(pnl)
        summaryRow(pnl)
        local sc = vgui.Create("DScrollPanel", pnl)
        sc:Dock(FILL)
        local names = {}
        for n in pairs(d.factions or {}) do names[#names + 1] = n end
        table.sort(names, function(a, b) return string.lower(facName(a)) < string.lower(facName(b)) end)
        if #names == 0 then
            local e = vgui.Create("DPanel", sc)
            e:Dock(TOP) e:SetTall(60)
            e.Paint = function(_, w, h)
                draw.RoundedBox(6, 0, 0, w, h, C.panel)
                draw.SimpleText("Организаций нет.", "GRMBComp_Norm", 14, h / 2, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            return
        end
        for _, key in ipairs(names) do
            local info = d.factions[key] or {}
            local row = vgui.Create("DPanel", sc)
            row:Dock(TOP) row:SetTall(58) row:DockMargin(0, 0, 4, 6)
            row.Paint = function(_, w, h)
                draw.RoundedBox(6, 0, 0, w, h, C.panel)
                surface.SetDrawColor(C.border)
                surface.DrawOutlinedRect(0, 0, w, h)
                draw.SimpleText(facName(key), "GRMBComp_Head", 14, 16, C.text)
                if facName(key) ~= key then
                    draw.SimpleText("[" .. key .. "]", "GRMBComp_Small", 14, 38, C.dim)
                else
                    draw.SimpleText("налог  " .. math.floor((info.taxRate or 0.05) * 100) .. "%", "GRMBComp_Small", 14, 38, C.dim)
                end
                draw.SimpleText(money(info.budget or 0), "GRMBComp_Stat", w - 16, h / 2, C.gold, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end
        end
    end)

    selectTab("dist")
end)
