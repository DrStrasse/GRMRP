--[[--------------------------------------------------------------------
    GRM Industry — общий набор интерфейса цеха и логистики.

    ЗАЧЕМ ОТДЕЛЬНЫЙ КИТ. В старом цехе и старой логистике каждый файл
    рисовал окна сам: свои шрифты, свои цвета, свои кнопки с разной
    высотой и скруглением. В итоге «одно и то же» окно двух систем
    выглядело по-разному, а правка отступа превращалась в поиск по
    всему файлу.

    Здесь один источник: палитра, шрифты, окно, кнопка, строка списка,
    полоса прогресса и предпросмотр модели. Окна цеха и логистики
    собираются из этих деталей и выглядят одинаково.
----------------------------------------------------------------------]]

if not CLIENT then return end

GRM = GRM or {}
GRM.Industry = GRM.Industry or {}
local I = GRM.Industry

I.UI = I.UI or {}
local UI = I.UI

-- ================================================================
--  ПАЛИТРА И ШРИФТЫ
-- ================================================================
UI.C = UI.C or {
    bg     = Color(16, 21, 29, 250),
    header = Color(24, 32, 44),
    panel  = Color(30, 39, 52),
    hover  = Color(44, 57, 74),
    slot   = Color(38, 49, 65),
    line   = Color(58, 76, 99),
    accent = Color(67, 155, 255),
    green  = Color(54, 186, 105),
    red    = Color(205, 70, 65),
    yellow = Color(235, 178, 60),
    text   = Color(238, 243, 250),
    dim    = Color(160, 172, 189),
}

local fontsReady = false
function UI.Fonts()
    if fontsReady then return end
    fontsReady = true
    surface.CreateFont("GRMInd_Title",  { font = "Roboto", size = 21, weight = 800, extended = true })
    surface.CreateFont("GRMInd_Head",   { font = "Roboto", size = 16, weight = 700, extended = true })
    surface.CreateFont("GRMInd_Normal", { font = "Roboto", size = 14, weight = 500, extended = true })
    surface.CreateFont("GRMInd_Small",  { font = "Roboto", size = 12, weight = 400, extended = true })
    surface.CreateFont("GRMInd_Big",    { font = "Roboto", size = 46, weight = 900, extended = true })
end

--[[ ШРИФТЫ СОЗДАЁМ СРАЗУ, ПРИ ЗАГРУЗКЕ ФАЙЛА, а не при первом окне.

     Подписи над узлами в мире (PostDrawTranslucentRenderables)
     рисуются БЕЗ открытого окна: игрок просто подошёл к станку.
     Раньше шрифты появлялись только из UI.Window, поэтому в мире
     сыпалось две ошибки на каждый кадр:

       'GRMInd_Head' isn't a valid font
       draw.lua:69: attempt to perform arithmetic on local 'w'

     Вторая — следствие первой: без шрифта surface.GetTextSize
     возвращает nil, и рамка считается от nil. ]]
UI.Fonts()

-- ================================================================
--  БАЗОВЫЕ ЭЛЕМЕНТЫ
-- ================================================================
function UI.Notify(message, ok)
    notification.AddLegacy(tostring(message or ""), ok and NOTIFY_GENERIC or NOTIFY_ERROR, 4)
    surface.PlaySound(ok and "buttons/button17.wav" or "buttons/button10.wav")
end

-- Окно. Обязательно регистрируется в GRM.UI.Track: гвард жизненного
-- цикла не даёт двум копиям окна открыться поверх друг друга.
function UI.Window(key, title, w, h)
    UI.Fonts()
    local f = vgui.Create("DFrame")
    GRM.UI.Track(key, f)
    f:SetTitle("")
    f:SetSize(w, h)
    f:Center()
    f:MakePopup()
    f:SetDraggable(true)
    f:ShowCloseButton(false)
    f.Paint = function(_, pw, ph)
        draw.RoundedBox(9, 0, 0, pw, ph, UI.C.bg)
        draw.RoundedBoxEx(9, 0, 0, pw, 40, UI.C.header, true, true, false, false)
        draw.SimpleText(title, "GRMInd_Title", 16, 21, UI.C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local close = vgui.Create("DButton", f)
    close:SetText("✕"); close:SetFont("GRMInd_Normal"); close:SetTextColor(UI.C.text)
    close:SetPos(w - 34, 8); close:SetSize(26, 26)
    close.Paint = function(self, pw, ph)
        draw.RoundedBox(5, 0, 0, pw, ph, self:IsHovered() and UI.C.red or UI.C.panel)
    end
    close.DoClick = function() f:Close() end
    return f, 40
end

function UI.Button(parent, text, color, w, h)
    UI.Fonts()
    local b = vgui.Create("DButton", parent)
    b:SetText(text); b:SetFont("GRMInd_Normal"); b:SetTextColor(color_white)
    if w then b:SetWide(w) end
    if h then b:SetTall(h) end
    b.Paint = function(self, pw, ph)
        local col = color
        if not self:IsEnabled() then col = Color(64, 70, 80)
        elseif self:IsHovered() then col = Color(math.min(color.r + 22, 255), math.min(color.g + 22, 255), math.min(color.b + 22, 255)) end
        draw.RoundedBox(5, 0, 0, pw, ph, col)
    end
    return b
end

-- Панель-карточка с заголовком. Все блоки окон собраны из неё.
function UI.Card(parent, title)
    UI.Fonts()
    local p = vgui.Create("DPanel", parent)
    p.Paint = function(_, w, h)
        draw.RoundedBox(7, 0, 0, w, h, UI.C.panel)
        if title and title ~= "" then
            draw.SimpleText(title, "GRMInd_Small", 12, 12, UI.C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
    return p, (title and title ~= "") and 26 or 8
end

function UI.Bar(parent, x, y, w, h, frac, color)
    draw.RoundedBox(4, x, y, w, h, Color(18, 25, 35))
    local fill = math.Clamp(tonumber(frac) or 0, 0, 1)
    if fill > 0 then draw.RoundedBox(4, x, y, w * fill, h, color or UI.C.green) end
end

function UI.Money(amount)
    return GRM.Format and GRM.Format(amount) or (tostring(amount) .. " GRM")
end

-- ================================================================
--  ПРЕДПРОСМОТР МОДЕЛИ
-- ================================================================
--[[ КАК НАЙТИ МОДЕЛЬ ОРУЖИЯ. У старого верстака было
     `weaponData.WorldModel or weaponData.ViewModel`, и на ArcCW-сборках,
     где WorldModel пуст или служебный, вместо оружия показывалась
     пустота. Здесь перебираем все известные поля по очереди. ]]
function UI.WeaponModel(class)
    if not class or class == "" then return nil end
    local swep = weapons.Get(class)
    if not swep then return nil end
    local candidates = { swep.WorldModel, swep.WM, swep.WorldModelOverride, swep.ViewModel, swep.VM }
    for _, m in ipairs(candidates) do
        if isstring(m) and m ~= "" and util.IsValidModel(m) then return m end
    end
    return nil
end

--[[ КАДР ПО ГАБАРИТАМ МОДЕЛИ. Считает боевая функция ядра
     I.CameraFor: она же проверяется стендом. Зашитые числа вроде
     Vector(70, 0, 42) потеряли бы и пистолет, и РПГ. ]]
function UI.FitModel(panel, model, fov)
    local ent = panel:GetEntity()
    if not IsValid(ent) then return end
    local mins, maxs = ent:GetModelBounds()
    local w, h = panel:GetWide(), panel:GetTall()
    local cam = I.CameraFor(mins or Vector(0, 0, 0), maxs or Vector(0, 0, 0), w, h, fov or 34)
    panel:SetCamPos(Vector(cam.camPos.x, cam.camPos.y, cam.camPos.z))
    panel:SetLookAt(Vector(cam.lookAt.x, cam.lookAt.y, cam.lookAt.z))
    panel:SetFOV(fov or 34)
end

--[[ Панель предпросмотра с вращением. Возвращает панель и функцию
     SetItem(class) — она же показывает карточку-заглушку, если модель
     найти не удалось. Пустой квадрат вместо оружия был одной из жалоб
     владельца, поэтому заглушка говорит текстом, а не молчит. ]]
function UI.ModelPanel(parent, w, h)
    UI.Fonts()
    local holder = vgui.Create("DPanel", parent)
    holder:SetSize(w, h)

    local mdl = vgui.Create("DModelPanel", holder)
    mdl:SetSize(w, h)
    mdl:SetFOV(34)
    mdl:SetAmbientLight(Color(110, 120, 140))
    mdl:SetDirectionalLight(BOX_TOP, Color(200, 205, 220))
    mdl:SetDirectionalLight(BOX_FRONT, Color(150, 160, 180))
    mdl:SetVisible(false)

    -- Медленное автовращение, которое перехватывается мышью.
    mdl.m_spin = 0
    mdl.m_dragging = false
    mdl.m_lastX = 0
    mdl.LayoutEntity = function(self)
        if self.m_dragging then return end
        self.m_spin = (self.m_spin or 0) + 0.35
        if self.m_spin > 360 then self.m_spin = self.m_spin - 360 end
        self:SetAngles(Angle(0, self.m_spin, 0))
    end
    mdl.OnMousePressed = function(self, code)
        if code == MOUSE_LEFT then self.m_dragging = true; self.m_lastX = gui.MouseX() end
    end
    mdl.OnMouseReleased = function(self, code)
        if code == MOUSE_LEFT then self.m_dragging = false end
    end
    mdl.Think = function(self)
        if self.m_dragging then
            local dx = gui.MouseX() - (self.m_lastX or 0)
            self.m_lastX = gui.MouseX()
            self.m_spin = (self.m_spin or 0) + dx * 0.5
            self:SetAngles(Angle(0, self.m_spin, 0))
        end
    end

    local fallback = vgui.Create("DPanel", holder)
    fallback:SetSize(w, h)
    fallback:SetVisible(false)
    fallback.m_text = ""
    fallback.m_sub = ""
    fallback.Paint = function(self, pw, ph)
        draw.RoundedBox(7, 0, 0, pw, ph, Color(26, 34, 46))
        surface.SetDrawColor(UI.C.line)
        surface.DrawOutlinedRect(0, 0, pw, ph, 1)
        draw.SimpleText(self.m_text, "GRMInd_Head", pw / 2, ph / 2 - 12, UI.C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(self.m_sub, "GRMInd_Small", pw / 2, ph / 2 + 14, UI.C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    function holder:SetItem(class, name)
        local model = UI.WeaponModel(class)
        if model then
            mdl:SetVisible(true)
            fallback:SetVisible(false)
            mdl:SetModel(model)
            mdl.m_spin = 25
            -- Габариты известны только после установки модели.
            timer.Simple(0, function() if IsValid(mdl) then UI.FitModel(mdl, model, 34) end end)
        else
            mdl:SetVisible(false)
            fallback:SetVisible(true)
            fallback.m_text = name or class or "—"
            fallback.m_sub = "модель не задана в сборке оружия"
        end
    end

    function holder:ClearItem()
        mdl:SetVisible(false)
        fallback:SetVisible(true)
        fallback.m_text = ""
        fallback.m_sub = "выберите изделие"
    end

    holder:ClearItem()
    return holder
end

-- ================================================================
--  ПОДПИСИ НАД УЗЛАМИ В МИРЕ
-- ================================================================
--[[ Без подписи узел узнаётся только нажатием E — в старом цехе так и
     было, из-за чего игроки не понимали, где станок, а где склад.

     Обходим entities через реестр производительности: он кеширует
     списки по классам и не перебирает все entity карты каждый кадр.
     Рисуем не чаще четырёх раз в секунду и только рядом. ]]
UI.NodeClasses = {
    "grm_ind_supply", "grm_ind_station", "grm_ind_storage",
    "grm_ind_market", "grm_ind_depot", "grm_ind_warehouse", "grm_ind_armory",
}

local LABEL_RANGE = 900

function UI.NodeTitle(ent)
    if not IsValid(ent) then return "", "" end
    local rec = I.NodeFor and I.NodeFor(ent) or nil
    local role = tostring(ent.NodeRole or "")
    local roleName = (I.NodeRoles and I.NodeRoles[role] and I.NodeRoles[role].name) or role

    local title = tostring(ent:GetNodeLabel() or "")
    if title == "" then title = roleName end

    --[[ Только сетевые переменные: таблица задач живёт на сервере,
         клиент видит состояние через NetworkVar. ]]
    local sub = ""
    local stage = tostring(ent.GetJobStage and ent:GetJobStage() or "")
    if stage == "assemble" then
        sub = "сборка " .. tostring(math.floor((tonumber(ent:GetProgress()) or 0) * 100)) .. "%"
    elseif stage == "paused" then
        sub = "пауза: работника нет"
    elseif stage == "process" then
        sub = "идёт работа"
    elseif stage == "blocked" then
        sub = "выход забит"
    elseif role == "supply" then
        sub = "металлолом: " .. tostring(ent.GetStock and ent:GetStock() or 0)
    end
    return title, sub
end

--[[ ПОДПИСИ НАД УЗЛАМИ: РАСЧЁТ РЕЖЕМ, РИСУЕМ КАЖДЫЙ КАДР.

     Раньше GRM.Perf.Throttle стоял на ВСЁМ хуке, включая отрисовку.
     А Throttle пропускает вызов РОВНО ОДИН РАЗ за интервал
     (sh_06_grm_performance.lua:34) — это ограничитель частоты
     вычислений, а не рисования. Получалось: хук вызывается шестьдесят
     раз в секунду, а рисует четыре. Отсюда и моргание.

     Правильно так: обход сущностей и чтение сетевых переменных
     обновляем четыре раза в секунду в кэш, а рисуем из кэша на
     каждом кадре. ]]
local LABEL_REFRESH = 0.25
local labelCache, labelCacheAt = {}, -1

local function collectLabels(eye)
    local out = {}
    for _, class in ipairs(UI.NodeClasses) do
        local list = (GRM.Perf and GRM.Perf.Entities and GRM.Perf.Entities(class))
            or ents.FindByClass(class)
        for _, ent in ipairs(list or {}) do
            if IsValid(ent) and ent:GetPos():DistToSqr(eye) <= LABEL_RANGE * LABEL_RANGE then
                local title, sub = UI.NodeTitle(ent)
                out[#out + 1] = {
                    ent    = ent,
                    title  = title,
                    sub    = sub,
                    height = (ent.OBBMaxs and ent:OBBMaxs().z or 30) + 18,
                }
            end
        end
    end
    return out
end

local IND_ANG = Angle(0, 0, 90)
local IND_POS = Vector(0, 0, 0)
hook.Add("PostDrawTranslucentRenderables", "GRM_IndustryNodeLabels", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    local eye = ply:EyePos()

    --[[ Расчёт — не чаще четырёх раз в секунду. Считает слой
         производительности: GRM.Perf.Throttle пропускает ровно один
         вызов за интервал, это как раз то, что нужно для обхода
         сущностей и чтения сетевых переменных. Но под его запрет
         нельзя ставить отрисовку — иначе подписи моргают. ]]
    local now = CurTime()
    local refresh = (now - labelCacheAt >= LABEL_REFRESH)
    if refresh and GRM.Perf and GRM.Perf.Throttle then
        refresh = GRM.Perf.Throttle("industry.labels", LABEL_REFRESH)
    end
    if refresh then
        labelCache, labelCacheAt = collectLabels(eye), now
    end

    -- Отрисовка — КАЖДЫЙ кадр, иначе подписи моргают.
    -- Угол и точка якоря — скретч (каждая запись тут же потребляется
    -- cam.Start3D2D; §6.1.8)
    IND_ANG.y = ply:EyeAngles().y - 90
    local ang = IND_ANG
    for _, item in ipairs(labelCache or {}) do
        if IsValid(item.ent) then
            local ip = item.ent:GetPos()
            IND_POS.x = ip.x
            IND_POS.y = ip.y
            IND_POS.z = ip.z + item.height
            cam.Start3D2D(IND_POS, ang, 0.11)
                surface.SetFont("GRMInd_Head")
                local w = surface.GetTextSize(item.title)
                draw.SimpleText(item.title, "GRMInd_Head", 0, 0, UI.C.text, TEXT_ALIGN_CENTER)
                if item.sub ~= "" then
                    draw.SimpleText(item.sub, "GRMInd_Small", 0, 22, UI.C.yellow, TEXT_ALIGN_CENTER)
                    local w2 = surface.GetTextSize(item.sub)
                    if w2 > w then w = w2 end
                end
                surface.SetDrawColor(UI.C.accent)
                surface.DrawOutlinedRect(-w / 2 - 8, -6, w + 16, 42, 2)
            cam.End3D2D()
        end
    end
end)

-- ================================================================
--  СТРОКА СПИСКА
-- ================================================================
--[[ Одна строка: название слева, подсказка под ним, значение справа.
     selected — подсветка выбранной позиции. ]]
function UI.Row(parent, tall, onClick)
    UI.Fonts()
    local row = vgui.Create("DButton", parent)
    row:SetTall(tall)
    row:SetText("")
    row.m_title, row.m_hint, row.m_value, row.m_valueColor = "", "", "", UI.C.text
    row.m_selected = false
    row.Paint = function(self, w, h)
        local bg = self.m_selected and UI.C.hover or (self:IsHovered() and Color(38, 49, 66) or UI.C.slot)
        draw.RoundedBox(6, 0, 0, w, h, bg)
        if self.m_selected then
            surface.SetDrawColor(UI.C.accent)
            surface.DrawOutlinedRect(0, 0, w, h, 2)
        end
        draw.SimpleText(self.m_title, "GRMInd_Normal", 12, h * 0.36, UI.C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(self.m_hint, "GRMInd_Small", 12, h * 0.72, UI.C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if self.m_value ~= "" then
            draw.SimpleText(self.m_value, "GRMInd_Normal", w - 12, h / 2, self.m_valueColor, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
    end
    if onClick then row.DoClick = function() onClick(row) end end
    return row
end

print("[GRM Industry] интерфейс загружен")
