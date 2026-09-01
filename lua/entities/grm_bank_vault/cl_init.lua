--[[--------------------------------------------------------------------
    grm_bank_vault — клиент: 3D2D-дисплей + E-меню (Загрузить/Выгрузить)
----------------------------------------------------------------------]]
include("shared.lua")

surface.CreateFont("GRMVault_Title", { font = "Roboto", size = 17, weight = 900, extended = true })
surface.CreateFont("GRMVault_Normal", { font = "Roboto", size = 12, weight = 600, extended = true })
surface.CreateFont("GRMVault_Small", { font = "Roboto", size = 10, weight = 500, extended = true })

local function money(n)
    return GRM and GRM.Format and GRM.Format(tonumber(n) or 0) or (tostring(math.floor(tonumber(n) or 0)) .. " GRM")
end

function ENT:Draw()
    self:DrawModel()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    if ply:GetPos():DistToSqr(self:GetPos()) > 900 * 900 then return end

    local mins, maxs = self:OBBMins(), self:OBBMaxs()
    local depth = (maxs and mins and (maxs.x - mins.x) > 0.1) and (maxs.x - mins.x) or 40
    local pos = self:WorldSpaceCenter() + self:GetForward() * (depth * 0.5 + 6)
    local ang = (-self:GetRight()):AngleEx(self:GetForward())
    cam.Start3D2D(pos, ang, 0.06)
        local w, h = 340, 120
        draw.RoundedBox(8, -w/2, -h/2, w, h, Color(8, 12, 18, 225))
        draw.RoundedBox(6, -w/2 + 5, -h/2 + 5, w - 10, h - 10, Color(16, 24, 34, 235))
        draw.SimpleText("БАНКОВСКОЕ ХРАНИЛИЩЕ", "GRMVault_Title", 0, -46, Color(120, 210, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("В ГОСБЮДЖЕТЕ СЕЙЧАС: " .. money(self:GetStateBudget() or 0), "GRMVault_Title", 0, -20, Color(255, 220, 90), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("В хранилище: " .. money(self:GetHeldCash() or 0) .. " / " .. money(self:GetCapacity() or 0), "GRMVault_Normal", 0, 12, Color(200, 220, 240), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("E — меню: загрузить паллеты / выгрузить", "GRMVault_Small", 0, 36, Color(140, 155, 175), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("Распределение в госбюджет — через Компьютер Банка", "GRMVault_Small", 0, 52, Color(110, 130, 150), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    cam.End3D2D()
end

-- ── E-меню хранилища ──
local C = {
    bg = Color(15, 20, 30, 248), panel = Color(30, 40, 56, 245), blue = Color(75, 155, 255),
    green = Color(80, 220, 130), red = Color(230, 85, 75), yellow = Color(245, 195, 70),
    text = Color(245, 248, 255), dim = Color(160, 172, 190),
}

local function act(vault, action, amount)
    if not IsValid(vault) then return end
    net.Start("GRM_VaultMenu_Action")
        net.WriteEntity(vault)
        net.WriteString(action)
        if action == "unload" then net.WriteUInt(math.max(0, math.floor(tonumber(amount) or 0)), 32) end
    net.SendToServer()
end

local menuFrame = nil

net.Receive("GRM_VaultMenu_Open", function()
    local vault = net.ReadEntity()
    local d = net.ReadTable() or {}
    if not IsValid(vault) then return end

    if IsValid(menuFrame) then menuFrame:Remove() end
    menuFrame = vgui.Create("DFrame")
    menuFrame:SetTitle("")
    menuFrame:SetSize(420, 360)
    menuFrame:Center()
    menuFrame:MakePopup()
    menuFrame.Paint = function(_, w, h)
        draw.RoundedBox(9, 0, 0, w, h, C.bg)
        draw.RoundedBoxEx(9, 0, 0, w, 52, Color(26, 36, 52, 250), true, true, false, false)
        draw.SimpleText("БАНКОВСКОЕ ХРАНИЛИЩЕ", "GRMVault_Title", 16, 26, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local body = vgui.Create("DPanel", menuFrame)
    body:Dock(FILL)
    body:DockMargin(12, 62, 12, 12)
    body:SetPaintBackground(false)

    local info = vgui.Create("DPanel", body)
    info:Dock(TOP)
    info:SetTall(96)
    info:DockMargin(0, 0, 0, 10)
    info.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, C.panel)
        draw.SimpleText("В ГОСБЮДЖЕТЕ СЕЙЧАС: " .. money(d.stateBudget or 0), "GRMVault_Title", 14, 22, Color(255, 220, 90), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("В хранилище: " .. money(d.held or 0) .. " / " .. money(d.capacity or 0), "GRMVault_Normal", 14, 52, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Загрузить — паллеты и деньги рядом (радиус 250)", "GRMVault_Small", 14, 74, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local function addBtn(text, col, fn)
        local b = vgui.Create("DButton", body)
        b:Dock(TOP)
        b:SetTall(42)
        b:DockMargin(0, 0, 0, 8)
        b:SetText("")
        b.Paint = function(self, w, h)
            local c = self:IsHovered() and Color(math.min(col.r + 25, 255), math.min(col.g + 25, 255), math.min(col.b + 25, 255)) or col
            draw.RoundedBox(7, 0, 0, w, h, c)
            draw.SimpleText(text, "GRMVault_Normal", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        b.DoClick = fn
        return b
    end

    addBtn("⬆ ЗАГРУЗИТЬ (паллеты и деньги рядом)", C.green, function()
        act(vault, "load")
    end)

    if d.canManage then
        addBtn("⬇ ВЫГРУЗИТЬ (указать сумму)", C.yellow, function()
            Derma_StringRequest("Выгрузка из хранилища",
                "Сумма (≥50.000 — паллеты, <50.000 — пачка money):",
                "50000",
                function(val)
                    local amount = math.floor(tonumber(val) or 0)
                    if amount <= 0 then return end
                    act(vault, "unload", amount)
                end)
        end)
    else
        local l = vgui.Create("DLabel", body)
        l:Dock(TOP)
        l:DockMargin(0, 0, 0, 8)
        l:SetTall(25)
        l:SetFont("GRMVault_Small")
        l:SetTextColor(C.dim)
        l:SetText("Выгрузка — только для сотрудников с доступом к экономике.")
    end

    local hint = vgui.Create("DLabel", body)
    hint:Dock(BOTTOM)
    hint:SetTall(40)
    hint:SetFont("GRMVault_Small")
    hint:SetTextColor(C.dim)
    hint:SetWrap(true)
    hint:SetText("Деньги в хранилище хранятся автономно. Распределение в гос.бюджет / бюджеты фракций — через Компьютер Управления (Банк).")
end)
