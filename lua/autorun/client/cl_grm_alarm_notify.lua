--[[--------------------------------------------------------------------
    GRM Alarm Notify — клиент настройки оповещаемых фракций (находка 179h)
    Суперадмин: /grm_alarm_notify → окно с чекбоксами существующих фракций.
----------------------------------------------------------------------]]
if not CLIENT then return end

surface.CreateFont("GRMAlarmN_Title", { font = "Roboto", size = 17, weight = 800, extended = true })
surface.CreateFont("GRMAlarmN_Normal", { font = "Roboto", size = 13, weight = 600, extended = true })
surface.CreateFont("GRMAlarmN_Small", { font = "Roboto", size = 11, weight = 500, extended = true })

local C = {
    bg = Color(15, 20, 30, 248), panel = Color(30, 40, 56, 245), green = Color(80, 220, 130),
    red = Color(230, 85, 75), text = Color(245, 248, 255), dim = Color(160, 172, 190),
}

local frame = nil

net.Receive("GRM_AlarmNotify_Data", function()
    local data = net.ReadTable() or {}
    local facList = net.ReadTable() or {}
    local selected = istable(data.factions) and data.factions or {}

    if IsValid(frame) then frame:Remove() end
    frame = vgui.Create("DFrame")
    frame:SetTitle("")
    frame:SetSize(440, 520)
    frame:Center()
    frame:MakePopup()
    frame.Paint = function(_, w, h)
        draw.RoundedBox(9, 0, 0, w, h, C.bg)
        draw.RoundedBoxEx(9, 0, 0, w, 50, Color(26, 36, 52, 250), true, true, false, false)
        draw.SimpleText("ФРАКЦИИ ДЛЯ ОПОВЕЩЕНИЯ", "GRMAlarmN_Title", 14, 25, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local body = vgui.Create("DPanel", frame)
    body:Dock(FILL)
    body:DockMargin(12, 58, 12, 12)
    body:SetPaintBackground(false)

    local hint = vgui.Create("DLabel", body)
    hint:Dock(TOP)
    hint:SetTall(40)
    hint:SetFont("GRMAlarmN_Small")
    hint:SetTextColor(C.dim)
    hint:SetWrap(true)
    hint:SetText("Эти фракции будут получать оповещения о взломах кейпадов, сканеров и дверей, а также отметку на мини-карте.")

    local scroll = vgui.Create("DScrollPanel", body)
    scroll:Dock(FILL)
    scroll:DockMargin(0, 6, 0, 6)
    scroll.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, C.panel) end

    local checks = {}
    if #facList == 0 then
        local l = vgui.Create("DLabel", scroll)
        l:Dock(TOP) l:SetTall(28) l:SetFont("GRMAlarmN_Small") l:SetTextColor(C.dim)
        l:SetText("Фракций пока нет — создайте их в /factions.")
    end
    for _, fname in ipairs(facList) do
        local c = vgui.Create("DCheckBoxLabel", scroll)
        c:Dock(TOP)
        c:SetTall(26)
        c:DockMargin(8, 1, 4, 1)
        c:SetText(fname)
        c:SetFont("GRMAlarmN_Normal")
        c:SetTextColor(C.text)
        c:SetValue(selected[fname] == true and 1 or 0)
        checks[fname] = c
    end

    local save = vgui.Create("DButton", body)
    save:Dock(BOTTOM)
    save:SetTall(38)
    save:SetText("")
    save.Paint = function(self, w, h)
        local col = self:IsHovered() and Color(100, 240, 150) or C.green
        draw.RoundedBox(7, 0, 0, w, h, col)
        draw.SimpleText("СОХРАНИТЬ", "GRMAlarmN_Normal", w / 2, h / 2, Color(10, 20, 14), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    save.DoClick = function()
        local out = {}
        for fname, c in pairs(checks) do
            if c:GetChecked() then out[#out + 1] = fname end
        end
        table.sort(out)
        net.Start("GRM_AlarmNotify_Save")
            net.WriteTable(out)
        net.SendToServer()
        frame:Close()
    end
end)
