--[[--------------------------------------------------------------------
    grm_money_press_terminal — клиент: меню управления станком
----------------------------------------------------------------------]]
include("shared.lua")

surface.CreateFont("GRMPressT_Title", { font = "Roboto", size = 18, weight = 900, extended = true })
surface.CreateFont("GRMPressT_Normal", { font = "Roboto", size = 13, weight = 600, extended = true })
surface.CreateFont("GRMPressT_Small", { font = "Roboto", size = 11, weight = 500, extended = true })

local C = {
    bg = Color(15, 20, 30, 248), panel = Color(30, 40, 56, 245), blue = Color(75, 155, 255),
    green = Color(80, 220, 130), red = Color(230, 85, 75), yellow = Color(245, 195, 70),
    text = Color(245, 248, 255), dim = Color(160, 172, 190),
}

local function money(n)
    return GRM and GRM.Format and GRM.Format(tonumber(n) or 0) or (tostring(math.floor(tonumber(n) or 0)) .. " GRM")
end

local function act(term, press, action)
    if not IsValid(term) or not IsValid(press) then return end
    net.Start("GRM_PressTerminal_Action")
        net.WriteEntity(term)
        net.WriteString(action)
        net.WriteEntity(press)
    net.SendToServer()
end

local function addBtn(parent, text, col, fn)
    local b = vgui.Create("DButton", parent)
    b:Dock(TOP)
    b:SetTall(38)
    b:DockMargin(0, 0, 0, 6)
    b:SetText("")
    b.Paint = function(self, w, h)
        local c = self:IsHovered() and Color(math.min(col.r + 25, 255), math.min(col.g + 25, 255), math.min(col.b + 25, 255)) or col
        draw.RoundedBox(7, 0, 0, w, h, c)
        draw.SimpleText(text, "GRMPressT_Normal", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    b.DoClick = fn
    return b
end

local frame = nil

net.Receive("GRM_PressTerminal_Open", function()
    local term = net.ReadEntity()
    local hasPress = net.ReadBool()
    local press = net.ReadEntity()
    if not IsValid(term) then return end

    if IsValid(frame) then frame:Remove() end
    frame = vgui.Create("DFrame")
    frame:SetTitle("")
    frame:SetSize(460, 520)
    frame:Center()
    frame:MakePopup()
    frame.Paint = function(_, w, h)
        draw.RoundedBox(10, 0, 0, w, h, C.bg)
        draw.RoundedBoxEx(10, 0, 0, w, 56, Color(26, 36, 52, 250), true, true, false, false)
        draw.SimpleText("ТЕРМИНАЛ ПЕЧАТНОГО СТАНКА", "GRMPressT_Title", 18, 28, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local body = vgui.Create("DPanel", frame)
    body:Dock(FILL)
    body:DockMargin(12, 68, 12, 12)
    body:SetPaintBackground(false)

    if not hasPress or not IsValid(press) then
        local l = vgui.Create("DLabel", body)
        l:Dock(TOP)
        l:SetTall(80)
        l:SetFont("GRMPressT_Normal")
        l:SetTextColor(C.yellow)
        l:SetWrap(true)
        l:SetText("Станок не найден.\nПоставьте печатный станок (grm_money_press) в радиусе 600 юнитов от терминала.")
        return
    end

    local data = net.ReadTable() or {}

    local info = vgui.Create("DPanel", body)
    info:Dock(TOP)
    info:SetTall(176)
    info:DockMargin(0, 0, 0, 10)
    info.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, C.panel)
        local heat = data.heat or 0
        local stateCol = heat >= 100 and C.red or (data.active and C.green or C.yellow)
        local stateTxt = heat >= 100 and "ПЕРЕГРЕТ" or (data.active and "ПЕЧАТАЕТ" or "ОСТАНОВЛЕН")
        draw.SimpleText(stateTxt, "GRMPressT_Title", 14, 22, stateCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Скорость: ур. " .. tostring(data.speedLevel or 0) .. " / " .. tostring(data.maxSpeedLevel or 5), "GRMPressT_Normal", 14, 50, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Печать: " .. money(data.printAmount or 0) .. " GRM / " .. tostring(data.printInterval or 10) .. " сек", "GRMPressT_Normal", 14, 74, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Буфер: " .. money(data.buffer or 0) .. " / " .. money(100000) .. " (паллета при 100к)", "GRMPressT_Normal", 14, 98, C.yellow, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Нагрев: " .. tostring(math.floor(heat)) .. "%", "GRMPressT_Normal", 14, 122, heat >= 80 and C.red or C.yellow, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Напечатано всего: " .. money(data.totalPrinted or 0), "GRMPressT_Small", 14, 146, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    addBtn(body, data.active and "■ Остановить печать" or "▶ Запустить печать", data.active and C.red or C.green, function()
        act(term, press, "toggle")
    end)
    addBtn(body, "⬆ Прокачать скорость (" .. money(data.upgradeCost or 0) .. ")", C.blue, function()
        act(term, press, "upgrade")
    end)
    addBtn(body, "❄ Охладить (" .. money(data.coolCost or 0) .. ")", Color(100, 180, 230), function()
        act(term, press, "cool")
    end)
    addBtn(body, "↻ Обновить", Color(90, 100, 120), function()
        act(term, press, "refresh")
    end)

    local hint = vgui.Create("DLabel", body)
    hint:Dock(BOTTOM)
    hint:SetTall(46)
    hint:SetFont("GRMPressT_Small")
    hint:SetTextColor(C.dim)
    hint:SetWrap(true)
    hint:SetText("Деньги печатаются в ГОСБЮДЖЕТ. При 100.000 буфера станок спавнит паллету у себя — поднесите её к хранилищу и загрузите (E → Загрузить).")
end)
