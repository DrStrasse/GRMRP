--[[--------------------------------------------------------------------
    grm_comp_fire — cl_init.lua (Клиентская часть пожарной станции)
----------------------------------------------------------------------]]
include("shared.lua")

local THEME = {
    bg      = Color(24, 30, 34, 250),
    panel   = Color(30, 38, 44, 245),
    header  = Color(38, 48, 56, 255),
    accent  = Color(235, 120, 60),
    danger  = Color(220, 70, 70),
    success = Color(60, 190, 100),
    text    = Color(235, 240, 245),
    dim     = Color(150, 160, 170),
    gold    = Color(245, 200, 70),
}

local function mkBtn(parent, text, col, doClick)
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b:SetFont("DermaDefaultBold")
    b:SetTextColor(color_white)
    b.Paint = function(s, w, h)
        draw.RoundedBox(6, 0, 0, w, h, s:IsHovered() and Color(col.r + 20, col.g + 20, col.b + 20) or col)
        surface.SetDrawColor(255, 255, 255, 40)
        surface.DrawOutlinedRect(0, 0, w, h)
        draw.SimpleText(text, "DermaDefaultBold", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    b.DoClick = function() surface.PlaySound("buttons/button15.wav") if doClick then doClick() end end
    return b
end

local g_FireEnt = nil

local function requestCalls()
    if not IsValid(g_FireEnt) then return end
    net.Start("GRM_CompFire_Calls")
        net.WriteEntity(g_FireEnt)
    net.SendToServer()
end

local function paintClose(s, w, h)
    draw.RoundedBox(4, 0, 0, w, h, s:IsHovered() and THEME.danger or Color(45, 50, 60))
    draw.SimpleText("X", "DermaDefaultBold", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

local function openMenu(ent, data)
    g_FireEnt = ent
    if IsValid(GRM.FireComputerFrame) then GRM.FireComputerFrame:Remove() end
    local frame = vgui.Create("DFrame")
    GRM.FireComputerFrame = frame
    if GRM.UI and GRM.UI.Track then GRM.UI.Track("fire_computer",frame) end
    frame:SetTitle("")
    frame:SetSize(560, 620)
    frame:Center()
    frame:MakePopup()
    frame:ShowCloseButton(false)
    frame:SetDeleteOnClose(true)
    frame.OnRemove=function() if GRM.FireComputerFrame==frame then GRM.FireComputerFrame=nil end end
    frame.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, THEME.bg)
        draw.RoundedBoxEx(8, 0, 0, w, 42, THEME.header, true, true, false, false)
        draw.SimpleText(data.name or "ПОЖАРНАЯ СЛУЖБА", "DermaDefaultBold", 16, 21, THEME.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Диспетчерская станция", "DermaDefault", w - 52, 21, THEME.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    local btnClose = vgui.Create("DButton", frame)
    btnClose:SetSize(28, 24)
    btnClose:SetText("")
    btnClose.Paint = paintClose
    btnClose.DoClick = function() frame:Close() end

    local status = vgui.Create("DPanel", frame)
    status:Dock(TOP) status:DockMargin(12, 52, 12, 6) status:SetTall(96)
    status.Paint = function(_, w, h)
        draw.RoundedBox(6, 0, 0, w, h, THEME.panel)
        local line1 = string.format("Очагов сейчас: %d   ·   vFire: %s   ·   аддон: %s",
            tonumber(data.activeFires) or 0,
            data.vfireReady and "готов" or "НЕТ",
            data.addonReady and "готов" or "НЕТ")
        local line2 = string.format("Рандомное возгорание: %s (интервал %d-%d с, лимит %d)",
            data.randomEnabled and "ВКЛ" or "выкл",
            tonumber(data.minSec) or 0, tonumber(data.maxSec) or 0,
            tonumber(data.maxIncidents) or 8)
        draw.SimpleText(line1, "DermaDefault", 12, 12, THEME.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText(line2, "DermaDefault", 12, 36, THEME.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText("Плита (случайный очаг): " .. (data.stoveEnabled and "ВКЛ" or "выкл"), "DermaDefault", 12, 60, THEME.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end

    local body = vgui.Create("DPanel", frame)
    body:Dock(FILL) body:DockMargin(12, 0, 12, 12)
    body.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, THEME.panel) end

    local y = 12
    local rows = {}
    local function row(text, col, fn)
        local b = mkBtn(body, text, col or THEME.accent, fn)
        b._rowY=y; rows[#rows+1]=b; y=y+50
        return b
    end
    body.PerformLayout=function(_,w)
        for _,b in ipairs(rows) do b:SetPos(14,b._rowY or 12); b:SetSize(math.max(120,w-28),40) end
    end

    row("Журнал пожаров  (/fire_log)", Color(60, 120, 150), function() RunConsoleCommand("grm_fire_log") end)
    row("Журнал вызовов (пожар / 911)", Color(150, 90, 60), function() requestCalls() end)
    row("Активные вызовы — принять", Color(180, 70, 50), function()
        if GRM.Fire and GRM.Fire.Dispatch and GRM.Fire.Dispatch.RequestList then
            GRM.Fire.Dispatch.RequestList()
        else
            RunConsoleCommand("grm_fire_calls")
        end
    end)

    if data.isAdmin then
        row("Доступ и оповещение  (/fire_access)", Color(150, 110, 60), function() RunConsoleCommand("grm_fire_access") end)
        row("Фракции оповещения  (/grm_fire_notify)", Color(120, 100, 60), function() RunConsoleCommand("grm_fire_notify") end)
        row("Пожарные машины  (/fire_trucks)", Color(140, 70, 45), function() RunConsoleCommand("grm_fire_trucks") end)
        row("Очаги / точки  (/fire_spots)", Color(170, 60, 45), function() RunConsoleCommand("grm_fire_spots") end)
    end

    frame:SetSize(560, math.min(760, 210 + y))
    frame:Center()
    if IsValid(btnClose) then btnClose:SetPos(frame:GetWide() - 36, 8) end
    frame.PerformLayout = function(self, w)
        if IsValid(btnClose) then btnClose:SetPos(w - 36, 8) end
    end
end

net.Receive("GRM_CompFire_Open", function()
    local ent = net.ReadEntity()
    local data = net.ReadTable() or {}
    if not IsValid(ent) then return end
    openMenu(ent, data)
end)


-----------------------------------------------------------------------
-- ЖУРНАЛ ВЫЗОВОВ (экстренные вызовы 911 категории «Пожар»)
-----------------------------------------------------------------------
local function openCallsWindow(rows)
    if IsValid(GRM.FireCallsFrame) then GRM.FireCallsFrame:Remove() end

    local frame = vgui.Create("DFrame")
    GRM.FireCallsFrame = frame
    if GRM.UI and GRM.UI.Track then GRM.UI.Track("fire_calls", frame) end
    frame:SetTitle("")
    frame:SetSize(math.min(900, ScrW() - 80), math.min(600, ScrH() - 120))
    frame:Center()
    frame:MakePopup()
    frame:ShowCloseButton(false)
    frame:SetDeleteOnClose(true)
    frame.OnRemove = function() if GRM.FireCallsFrame == frame then GRM.FireCallsFrame = nil end end
    frame.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, THEME.bg)
        draw.RoundedBoxEx(8, 0, 0, w, 42, THEME.header, true, true, false, false)
        draw.SimpleText("ЖУРНАЛ ВЫЗОВОВ · ПОЖАРНАЯ СЛУЖБА", "DermaDefaultBold", 16, 21, THEME.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Всего записей: " .. #rows, "DermaDefault", w - 52, 21, THEME.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    local close = vgui.Create("DButton", frame)
    close:SetSize(28, 24)
    close:SetText("")
    close.Paint = paintClose
    close.DoClick = function() frame:Close() end
    frame.PerformLayout = function(self, w) if IsValid(close) then close:SetPos(w - 36, 8) end end

    local list = vgui.Create("DListView", frame)
    list:Dock(FILL)
    list:DockMargin(12, 52, 12, 12)
    list:SetMultiSelect(false)
    list:AddColumn("№"):SetFixedWidth(60)
    list:AddColumn("Время"):SetFixedWidth(140)
    list:AddColumn("Заявитель"):SetFixedWidth(180)
    list:AddColumn("Описание")
    list:AddColumn("Район"):SetFixedWidth(140)
    list:AddColumn("Статус"):SetFixedWidth(120)
    list:AddColumn("Принял"):SetFixedWidth(150)

    local STATUS = {
        open = "Открыт", assigned = "Принят", closed = "Закрыт",
        pending = "ОЖИДАЕТ ПРИНЯТИЯ", accepted = "Принят",
    }
    for _, r in ipairs(rows) do
        list:AddLine(
            tostring(r.id or 0),
            os.date("%d.%m.%Y %H:%M", tonumber(r.created) or 0),
            tostring(r.caller or ""),
            tostring(r.text or ""),
            tostring(r.area or ""),
            STATUS[tostring(r.status or "")] or tostring(r.status or ""),
            tostring(r.assigned or "")
        )
    end

    if #rows == 0 then
        local empty = vgui.Create("DLabel", frame)
        empty:Dock(BOTTOM) empty:SetTall(30) empty:DockMargin(12, 0, 12, 10)
        empty:SetContentAlignment(5)
        empty:SetTextColor(THEME.dim)
        empty:SetText("Вызовов по линии пожарной службы пока не поступало.")
    end
end

net.Receive("GRM_CompFire_CallsData", function()
    openCallsWindow(net.ReadTable() or {})
end)
