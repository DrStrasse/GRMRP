include("shared.lua")

--[[ Окно скупщика руды в стиле GRM (заказ владельца 19.08).
     Было: DFrame 500×420 со стандартным скином, DListView, продажа по клику
     на строку (легко продать не то) и подпись над NPC чёрным прямоугольником
     через HUDPaint.
     Стало: широкое окно GRM с карточками руды, отдельными кнопками продажи,
     «продать всё», разделом инструмента (выдача/сдача, залог) и табличкой
     3D2D над скупщиком. ]]

surface.CreateFont("GRMOre_Title", { font = "Roboto", size = 21, weight = 800, extended = true })
surface.CreateFont("GRMOre_Head",  { font = "Roboto", size = 16, weight = 700, extended = true })
surface.CreateFont("GRMOre_Body",  { font = "Roboto", size = 13, weight = 550, extended = true })
surface.CreateFont("GRMOre_Small", { font = "Roboto", size = 11, weight = 500, extended = true })
surface.CreateFont("GRMOre_Sign",  { font = "Roboto", size = 26, weight = 800, extended = true })

local C = {
    bg      = Color(16, 20, 28, 252),
    sidebar = Color(12, 15, 22, 255),
    card    = Color(22, 28, 38, 240),
    cardHov = Color(32, 42, 56, 240),
    row     = Color(26, 33, 45, 240),
    border  = Color(38, 48, 66, 200),
    accent  = Color(65, 145, 235),
    gold    = Color(245, 195, 65),
    green   = Color(55, 185, 110),
    teal    = Color(75, 195, 170),
    red     = Color(225, 70, 70),
    text    = Color(240, 244, 250),
    dim     = Color(155, 170, 190),
}

local function money(n) return GRM.Format and GRM.Format(n) or (tostring(n) .. " GRM") end

local function button(parent, label, base)
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b.Paint = function(self, w, h)
        local col = base or C.accent
        if not self:IsEnabled() then col = Color(38, 44, 56)
        elseif self:IsHovered() then col = Color(math.min(255, col.r + 24), math.min(255, col.g + 24), math.min(255, col.b + 24)) end
        draw.RoundedBox(6, 0, 0, w, h, col)
        draw.SimpleText(label, "GRMOre_Body", w / 2, h / 2, self:IsEnabled() and color_white or C.dim,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    return b
end

-----------------------------------------------------------------------
-- ТАБЛИЧКА НАД СКУПЩИКОМ (3D2D вместо плоского HUD-прямоугольника)
-----------------------------------------------------------------------
--[[ Как и у торгаша: RenderGroup = BOTH вызывал Draw дважды за кадр,
     второй проход клал подложку поверх текста — заголовок «пропадал».
     Теперь вывеска идёт одним проходом через общий слой GRM.Sign. ]]
function ENT:Draw()
    self:DrawModel()
end

function ENT:DrawTranslucent()
    if not GRM.Sign then return end
    GRM.Sign.Draw(self, {
        title    = "СКУПЩИК РУДЫ",
        subtitle = self:GetNWString("GRMOreBuyerName", "Приём руды • выдача бура"),
        hint     = "E — открыть",
        accent   = C.gold,
        height   = 82,
    })
end

-----------------------------------------------------------------------
-- ОКНО
-----------------------------------------------------------------------
local frame

local function open(ent, rows, hasTool, deposit, toolAvailable)
    if IsValid(frame) then frame:Remove() end

    frame = vgui.Create("DFrame")
    frame:SetSize(math.Clamp(ScrW() * 0.60, 860, 1180), math.Clamp(ScrH() * 0.70, 580, 840))
    frame:Center() frame:SetTitle("") frame:ShowCloseButton(false) frame:MakePopup()
    if GRM.UI and GRM.UI.Track then GRM.UI.Track("grm_ore_buyer", frame) end

    local total, totalCount = 0, 0
    for _, r in ipairs(rows) do
        total = total + (r.count or 0) * (r.price or 0)
        totalCount = totalCount + (r.count or 0)
    end

    frame.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, C.bg)
        draw.RoundedBox(8, 0, 0, w, 46, C.sidebar)
        surface.SetDrawColor(C.border) surface.DrawOutlinedRect(0, 0, w, h)
        draw.SimpleText("GRM · СКУПЩИК РУДЫ", "GRMOre_Title", 18, 14, C.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText(("В сумке руды: %d ед.  •  на сумму %s"):format(totalCount, money(total)),
            "GRMOre_Small", 18, 36, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end

    local close = button(frame, "✕", C.red)
    close:SetSize(34, 30) close:SetPos(frame:GetWide() - 44, 8)
    close.DoClick = function() frame:Remove() end

    local body = vgui.Create("DPanel", frame)
    body:Dock(FILL) body:DockMargin(12, 54, 12, 12) body:SetPaintBackground(false)

    -- Правая колонка: инструмент.
    local right = vgui.Create("DPanel", body)
    right:Dock(RIGHT) right:SetWide(300) right:DockMargin(10, 0, 0, 0)
    right.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, C.card)
        surface.SetDrawColor(C.border) surface.DrawOutlinedRect(0, 0, w, h)
        draw.SimpleText("ИНСТРУМЕНТ ДОБЫЧИ", "GRMOre_Head", 14, 14, C.teal, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText(hasTool and "Бур у вас на руках" or "Бур не выдан", "GRMOre_Body", 14, 44,
            hasTool and C.green or C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        local depText = (deposit or 0) > 0 and ("Залог: " .. money(deposit) .. " (возвращается при сдаче)")
            or "Залог не требуется"
        draw.SimpleText(depText, "GRMOre_Small", 14, 66, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        if not toolAvailable then
            draw.SimpleText("Аддон бура не установлен на сервере!", "GRMOre_Small", 14, 86, C.red, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end
        draw.SimpleText("Бур теряется при смерти.", "GRMOre_Small", 14, 108, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText("Сдавайте его после смены.", "GRMOre_Small", 14, 124, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end

    local give = button(right, hasTool and "БУР УЖЕ ВЫДАН" or "ПОЛУЧИТЬ БУР", C.green)
    give:SetPos(14, 150) give:SetSize(272, 38)
    give:SetEnabled(not hasTool and toolAvailable ~= false)
    give.DoClick = function()
        surface.PlaySound("items/ammo_pickup.wav")
        net.Start("grm_ore_buyer_give_jackhammer") net.SendToServer()
    end

    local ret = button(right, "СДАТЬ БУР", C.red)
    ret:SetPos(14, 196) ret:SetSize(272, 34)
    ret:SetEnabled(hasTool == true)
    ret.DoClick = function()
        surface.PlaySound("items/weapon_drop.wav")
        net.Start("grm_ore_buyer_return_jackhammer") net.SendToServer()
    end

    -- Левая часть: руда.
    local list = vgui.Create("DScrollPanel", body)
    list:Dock(FILL)

    for _, r in ipairs(rows) do
        local col = (GRM.Mining and GRM.Mining.OreColor and GRM.Mining.OreColor(r.id)) or C.text
        local haveIt = (r.count or 0) > 0 and (r.price or 0) > 0
        local cardP = vgui.Create("DPanel", list)
        cardP:Dock(TOP) cardP:SetTall(74) cardP:DockMargin(0, 0, 6, 8)
        cardP.Paint = function(self, w, h)
            draw.RoundedBox(8, 0, 0, w, h, self:IsHovered() and C.cardHov or C.card)
            surface.SetDrawColor(C.border) surface.DrawOutlinedRect(0, 0, w, h)
            draw.RoundedBox(4, 12, 14, 8, h - 28, col)
            draw.SimpleText(tostring(r.name), "GRMOre_Head", 32, 14, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            local priceText = (r.price or 0) > 0 and ("Цена: " .. money(r.price) .. " за единицу") or "Скупка приостановлена"
            draw.SimpleText(priceText, "GRMOre_Body", 32, 38, (r.price or 0) > 0 and C.gold or C.red, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText(("В сумке: %d"):format(r.count or 0), "GRMOre_Body", 32, 56,
                haveIt and C.green or C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            if haveIt then
                draw.SimpleText(money((r.count or 0) * (r.price or 0)), "GRMOre_Head", w - 190, h / 2,
                    C.teal, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end
        end
        local sell = button(cardP, "ПРОДАТЬ", C.accent)
        sell:Dock(RIGHT) sell:SetWide(160) sell:DockMargin(6, 18, 12, 18)
        sell:SetEnabled(haveIt)
        sell.DoClick = function()
            surface.PlaySound("buttons/button14.wav")
            net.Start("grm_ore_sell") net.WriteString(r.id) net.SendToServer()
        end
    end

    if totalCount == 0 then
        local empty = vgui.Create("DPanel", list)
        empty:Dock(TOP) empty:SetTall(80) empty:DockMargin(0, 0, 6, 0)
        empty.Paint = function(_, w, h)
            draw.RoundedBox(8, 0, 0, w, h, C.card)
            draw.SimpleText("Руды нет. Возьмите бур и идите в шахту.", "GRMOre_Body", w / 2, h / 2,
                C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end

    local sellAll = button(frame, totalCount > 0 and ("ПРОДАТЬ ВСЁ · " .. money(total)) or "ПРОДАТЬ ВСЁ", C.green)
    sellAll:Dock(BOTTOM) sellAll:SetTall(38) sellAll:DockMargin(12, 0, 324, 12)
    sellAll:SetEnabled(totalCount > 0 and total > 0)
    sellAll.DoClick = function()
        surface.PlaySound("buttons/button14.wav")
        net.Start("grm_ore_sell") net.WriteString("all") net.SendToServer()
    end
end

net.Receive("grm_ore_buyer_open", function()
    local ent = net.ReadEntity()
    local rows = net.ReadTable() or {}
    local hasTool = net.ReadBool()
    local deposit = net.ReadUInt(24)
    local toolAvailable = net.ReadBool()
    open(ent, rows, hasTool, deposit, toolAvailable)
end)
