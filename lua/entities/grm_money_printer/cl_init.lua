include("shared.lua")

surface.CreateFont("GRM_Printer_Title", { font = "Roboto", size = 18, weight = 800, extended = true })
surface.CreateFont("GRM_Printer_Normal", { font = "Roboto", size = 13, weight = 600, extended = true })
surface.CreateFont("GRM_Printer_Small", { font = "Roboto", size = 11, weight = 500, extended = true })

local C = {
    bg = Color(16, 20, 30, 245), card = Color(32, 40, 58, 245), blue = Color(75, 155, 255),
    green = Color(80, 220, 130), red = Color(230, 85, 75), yellow = Color(245, 195, 70), text = Color(245, 248, 255), dim = Color(165, 176, 192)
}

local function money(n)
    return GRM and GRM.Format and GRM.Format(tonumber(n) or 0) or tostring(math.floor(tonumber(n) or 0)) .. " GRM"
end

local function pct(a, b)
    b = math.max(1, tonumber(b) or 1)
    return math.Clamp((tonumber(a) or 0) / b, 0, 1)
end

function ENT:Draw()
    self:DrawModel()

    local pos = self:GetPos() + Vector(0, 0, 28)
    local ang = Angle(0, EyeAngles().y - 90, 90)
    local printed, maxMoney = self:GetPrinted(), self:GetMaxMoney()
    local heat, hp = self:GetHeat(), self:GetPrinterHealth()
    local hpPercent = math.floor(math.Clamp(hp / 250, 0, 1) * 100)
    local broken = self:GetBroken()
    local active = self:GetActive()

    cam.Start3D2D(pos, ang, 0.08)
        local w, h = 260, 128
        draw.RoundedBox(10, -w/2, -h/2, w, h, Color(8, 10, 16, 230))
        draw.RoundedBox(8, -w/2 + 6, -h/2 + 6, w - 12, h - 12, C.bg)
        draw.SimpleText("GRM Money Printer", "GRM_Printer_Title", 0, -46, C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(active and (broken and "СЛОМАН" or "РАБОТАЕТ") or "ВЫКЛЮЧЕН", "GRM_Printer_Normal", 0, -24, broken and C.red or (active and C.green or C.yellow), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        local barW = 210
        local y = 0
        draw.RoundedBox(4, -barW/2, y, barW, 10, Color(25, 30, 42, 255))
        draw.RoundedBox(4, -barW/2, y, barW * pct(printed, maxMoney), 10, C.green)
        draw.SimpleText(money(printed) .. " / " .. money(maxMoney), "GRM_Printer_Small", 0, y + 20, C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        y = 42
        draw.RoundedBox(4, -barW/2, y, barW, 8, Color(25, 30, 42, 255))
        draw.RoundedBox(4, -barW/2, y, barW * pct(heat, 100), 8, heat >= 75 and C.red or C.yellow)
        draw.SimpleText("Нагрев: " .. tostring(math.floor(heat)) .. "%   Состояние: " .. tostring(hpPercent) .. "%", "GRM_Printer_Small", 0, y + 18, C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    cam.End3D2D()
end

local function act(ent, action)
    if not IsValid(ent) then return end
    net.Start("GRM_Printer_Action")
        net.WriteEntity(ent)
        net.WriteString(action)
    net.SendToServer()
end

local function addButton(parent, text, color, fn)
    local b = vgui.Create("DButton", parent)
    b:Dock(TOP)
    b:SetTall(36)
    b:DockMargin(0, 0, 0, 6)
    b:SetText("")
    b.Paint = function(self, w, h)
        local col = self:IsHovered() and Color(math.min(color.r + 25, 255), math.min(color.g + 25, 255), math.min(color.b + 25, 255), 245) or color
        draw.RoundedBox(7, 0, 0, w, h, col)
        draw.SimpleText(text, "GRM_Printer_Normal", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    b.DoClick = fn
    return b
end

net.Receive("GRM_Printer_Open", function()
    local ent = net.ReadEntity()
    local data = net.ReadTable() or {}
    if not IsValid(ent) then return end

    local f = vgui.Create("DFrame")
    f:SetTitle("")
    f:SetSize(460, 520)
    f:Center()
    f:MakePopup()
    f.Paint = function(_, w, h)
        draw.RoundedBox(10, 0, 0, w, h, C.bg)
        draw.RoundedBoxEx(10, 0, 0, w, 58, Color(28, 36, 54, 250), true, true, false, false)
        draw.SimpleText("Денежный принтер", "GRM_Printer_Title", 18, 29, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(tostring(data.owner or "—"), "GRM_Printer_Small", w - 18, 31, C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    local body = vgui.Create("DPanel", f)
    body:Dock(FILL)
    body:DockMargin(12, 70, 12, 12)
    body:SetPaintBackground(false)

    local info = vgui.Create("DPanel", body)
    info:Dock(TOP)
    info:SetTall(136)
    info:DockMargin(0, 0, 0, 10)
    info.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, C.card)
        draw.SimpleText("Накоплено: " .. money(data.printed or 0) .. " / " .. money(data.maxMoney or 0), "GRM_Printer_Normal", 14, 24, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Печать: " .. money(data.printAmount or 0) .. " каждые " .. tostring(data.printInterval or 0) .. " сек", "GRM_Printer_Small", 14, 50, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Нагрев: " .. tostring(data.heat or 0) .. "%", "GRM_Printer_Small", 14, 74, (data.heat or 0) >= 75 and C.red or C.yellow, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Состояние: " .. tostring(math.floor(100 * (data.health or 0) / math.max(1, data.maxHealth or 250))) .. "%", "GRM_Printer_Small", 14, 98, (data.broken and C.red or C.green), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(data.broken and "СЛОМАН" or (data.active and "РАБОТАЕТ" or "ВЫКЛЮЧЕН"), "GRM_Printer_Normal", w - 14, 24, data.broken and C.red or (data.active and C.green or C.yellow), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    addButton(body, "Снять деньги", C.green, function() act(ent, "collect"); f:Close() end)
    addButton(body, (data.active and "Выключить" or "Включить"), C.blue, function() act(ent, "toggle"); f:Close() end)
    addButton(body, "Ремонт (" .. money(data.repairCost or 0) .. ")", C.yellow, function() act(ent, "repair"); f:Close() end)
    addButton(body, "Улучшить ёмкость (" .. money(data.upgradeCapacityCost or 0) .. ")", Color(100, 155, 230), function() act(ent, "cap"); f:Close() end)
    addButton(body, "Улучшить скорость (" .. money(data.upgradeRateCost or 0) .. ")", Color(130, 120, 230), function() act(ent, "rate"); f:Close() end)
    addButton(body, "Обновить", Color(90, 100, 120), function() act(ent, "refresh"); f:Close() end)
end)

net.Receive("GRM_Printer_Broken", function()
    local ent = net.ReadEntity()
    local reason = net.ReadString()
    notification.AddLegacy("Денежный принтер сломался: " .. tostring(reason or "поломка"), NOTIFY_ERROR, 5)
    surface.PlaySound("ambient/energy/spark6.wav")
end)
