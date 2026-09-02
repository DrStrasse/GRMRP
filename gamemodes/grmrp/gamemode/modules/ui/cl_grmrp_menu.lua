--[[ GRM:RP — меню паузы. Заменяет стандартный gameui (ESC): плавные кнопки
    въезжают слева, в центре — 3D-персонаж с «отражением», справа — карточка
    персонажа (RP-имя, HP/AR, наработка, деньги). Реестр вкладок декларативный
    (GRMRPMenu.AddTab) — точка расширения окон режима (§5.16).
    Паттерны: §5.13 (анимации только пока идут), §5.17 (шрифты extended,
    кириллица), палитра общая с чатом.
]]

if SERVER then return end

GRMRPMenu = GRMRPMenu or {}
local Menu = GRMRPMenu

local COL = {
    bg = Color(8, 14, 23),
    panel = Color(16, 27, 42),
    panelHi = Color(24, 38, 58),
    accent = Color(48, 204, 255),
    text = Color(225, 238, 247),
    dim = Color(132, 160, 178),
    gold = Color(250, 185, 63),
    green = Color(64, 222, 147),
    red = Color(244, 78, 96)
}

local function font(name, size, weight)
    surface.CreateFont(name, {
        font = "Roboto", size = size, weight = weight or 500,
        extended = true, antialias = true, shadows = false
    })
end
font("GRMRP_MenuBrand", 30, 900)
font("GRMRP_MenuTab", 19, 700)
font("GRMRP_MenuHead", 24, 800)
font("GRMRP_MenuLbl", 15, 500)
font("GRMRP_MenuDim", 13, 400)

local function clamp(v, a, b) return v < a and a or (v > b and b or v) end
local function easeOut(t) t = clamp(t, 0, 1); return 1 - (1 - t) * (1 - t) * (1 - t) * (1 - t) end

------------------------------------------------------------------ реестр вкладок
local tabs = {}
local tabsDirty = true

function Menu.AddTab(def)
    if not isstring(def.id) or not isfunction(def.action) then return false end
    for i = 1, #tabs do
        if tabs[i].id == def.id then tabs[i] = def; tabsDirty = true; return true end
    end
    table.insert(tabs, def)
    tabsDirty = true
    return true
end

function Menu.Tabs()
    if tabsDirty then
        table.sort(tabs, function(a, b) return (a.order or 50) < (b.order or 50) end)
        tabsDirty = false
    end
    return tabs
end

local function fmtTime(secs)
    secs = math.max(0, math.floor(secs or 0))
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    if h > 0 then return string.format("%d ч %02d мин", h, m) end
    return string.format("%d мин %02d с", m, secs % 60)
end

Menu.AddTab({ id = "resume", order = 10, title = "Вернуться в игру", accent = COL.green,
    action = function() Menu.Close() end })
Menu.AddTab({ id = "settings", order = 20, title = "Настройки", accent = COL.accent,
    action = function() Menu.ToggleSettings() end })
Menu.AddTab({ id = "servers", order = 30, title = "Сетевая игра", accent = COL.accent,
    action = function()
        Menu.suppressUntil = CurTime() + 30
        Menu.Close()
        RunConsoleCommand("gameui_activate")
    end })
Menu.AddTab({ id = "newgame", order = 40, title = "Новая игра (локально)", accent = COL.gold,
    visible = function() return game.SinglePlayer() end,
    action = function()
        local ok, err = pcall(function()
            game.CreateLocalServer(game.GetMap(), "GRM:RP — локально", function() end)
        end)
        if not ok then Menu.SystemLine("Не удалось: " .. tostring(err)) end
    end })
Menu.AddTab({ id = "workshop", order = 50, title = "Мастерская", accent = COL.gold,
    action = function()
        if gui.OpenURL then
            gui.OpenURL("https://steamcommunity.com/app/4000/workshop/")
        end
    end })
Menu.AddTab({ id = "disconnect", order = 70, title = "Отключиться от сервера", accent = COL.red,
    visible = function() return not game.SinglePlayer() end,
    action = function() RunConsoleCommand("disconnect") end })
Menu.AddTab({ id = "quit", order = 80, title = "Выход из игры", accent = COL.red,
    action = function() RunConsoleCommand("quit") end })

function Menu.SystemLine(text)
    if GRMRPChat and GRMRPChat.pushSystem then
        GRMRPChat.pushSystem(text)
    else
        MsgC(COL.accent, "[GRMRP] ", COL.text, text, "\n")
    end
end

------------------------------------------------------------------ карточки
local function newCard(parent, w, h)
    local card = vgui.Create("DPanel", parent)
    card:SetSize(w, h)
    card.Paint = function(s, cw, ch)
        draw.RoundedBox(6, 0, 0, cw, ch, COL.panel)
        surface.SetDrawColor(40, 62, 92, 120)
        surface.DrawOutlinedRect(0, 0, cw, ch)
    end
    return card
end

local function statRow(parent, y, label)
    local cap = vgui.Create("DLabel", parent)
    cap:SetFont("GRMRP_MenuDim")
    cap:SetTextColor(COL.dim)
    cap:SetText(label)
    cap:SetPos(14, y)
    cap:SizeToContents()

    local val = vgui.Create("DLabel", parent)
    val:SetFont("GRMRP_MenuLbl")
    val:SetTextColor(COL.text)
    val:SetText("—")
    val:SetPos(150, y - 3)
    val:SetWide(parent:GetWide() - 164)
    val:SetContentAlignment(6)
    return val
end

------------------------------------------------------------------ окно
function Menu.Open()
    if IsValid(Menu.root) then return end

    Menu.suppressUntil = 0
    if not GRMRP.JoinTime then GRMRP.JoinTime = CurTime() end
    local scrW, scrH = ScrW(), ScrH()
    local root = vgui.Create("DPanel")
    Menu.root = root
    root:SetPos(0, 0)
    root:SetSize(scrW, scrH)
    root:MakePopup()
    root.animStart = CurTime()
    root.bgAlpha = 0

    local colW = math.Clamp(scrW * 0.24, 300, 380)

    root.Paint = function(s, w, h)
        -- фон: тонировка кадра + лёгкий вертикальный градиент
        local a = s.bgAlpha
        draw.RoundedBox(0, 0, 0, w, h, Color(4, 8, 14, math.floor(170 * a / 255 + 0.5)))
        for i = 0, 15 do
            local t = i / 15
            surface.SetDrawColor(8, 14, 23, math.floor((1 - t) * 60 * a / 255))
            surface.DrawRect(0, h - (i + 1) * (h / 16), w, h / 16)
        end
        -- левая подложка
        local bx, by, bw, bh = 16, 84, colW, s.colH or 420
        draw.RoundedBox(8, bx, by, bw, bh + 26, Color(COL.panel.r, COL.panel.g, COL.panel.b, math.floor(230 * a / 255 + 0.5)))
        draw.SimpleText("GRM", "GRMRP_MenuBrand", bx + 18, by - 52, COL.accent)
        draw.SimpleText("RP", "GRMRP_MenuBrand", bx + 78, by - 52, COL.text)
        draw.SimpleText("меню паузы · v" .. (GRMRP and GRMRP.VERSION or "?"), "GRMRP_MenuDim", bx + 18, by - 18, COL.dim)
        draw.SimpleText("ESC — закрыть", "GRMRP_MenuDim", w - 130, h - 30, COL.dim)
    end

    ------------------------------------------------------------ кнопки слева
    local animList = {}
    local y = 110
    for _, def in ipairs(Menu.Tabs()) do
        if def.visible == nil or def.visible() then
            local b = vgui.Create("DButton", root)
            b:SetText("")
            b:SetSize(colW - 44, 36)
            b.x0 = 16 + 22
            b.y0 = y
            b.anim = 0
            b.t0 = CurTime() + 0.05 * (#animList + 1)
            b.hover = 0
            local accent = def.accent or COL.accent
            b.Paint = function(s, w, h)
                local e = s.anim
                if e <= 0 then return end
                local hov = s.hover
                local x = s.x0 - (1 - e) * 160
                s:SetPos(x, s.y0)
                local a = 255 * e
                draw.RoundedBox(6, 0, 0, w, h, hov > 0.01 and
                    Color(COL.panelHi.r, COL.panelHi.g, COL.panelHi.b, a) or
                    Color(COL.panel.r, COL.panel.g, COL.panel.b, a * 0.85))
                surface.SetDrawColor(accent.r, accent.g, accent.b, math.floor(a * (0.65 + hov * 0.35)))
                surface.DrawRect(3, 5, 4, h - 10)
                draw.SimpleText(def.title, "GRMRP_MenuTab", 20, 8,
                    Color(225, 238, 247, math.floor(a)))
                if hov > 0.01 then
                    draw.SimpleText("›", "GRMRP_MenuTab", w - 24, 8, Color(accent.r, accent.g, accent.b, math.floor(a * hov)))
                end
            end
            b.DoClick = function()
                surface.PlaySound("buttons/button14.wav")
                def.action()
            end
            b.DoRightClick = b.DoClick
            b.Think = function(s)
                local goal = (s:IsHovered() and 1 or 0)
                if math.abs(s.hover - goal) > 0.003 then
                    s.hover = s.hover + (goal - s.hover) * math.min(1, FrameTime() * 14)
                elseif s.hover ~= goal then
                    s.hover = goal
                end
                if s:IsHovered() and not s.HoverPlayed then
                    s.HoverPlayed = true
                    surface.PlaySound("buttons/lightswitch.wav")
                elseif not s:IsHovered() then
                    s.HoverPlayed = false
                end
            end
            table.insert(animList, b)
            y = y + 42
        end
    end
    root.colH = y - 110

    ------------------------------------------------------------ персонаж + отражение
    local ply = LocalPlayer()
    local centerX = 16 + colW + 24
    local rightW = math.Clamp(scrW * 0.26, 300, 380)
    local stageX = centerX
    local stageW = math.max(220, (scrW - rightW - 16) - stageX - 16)
    local stageH = math.min(470, scrH - 140)
    local stageY = math.floor((scrH - stageH) / 2)

    local function camParams()
        local mn, mx = ply:OBBMins(), ply:OBBMaxs()
        local h = (mx and mx.z or 64) - (mn and mn.z or 0)
        local wide = math.max(math.abs(mx and mx.x or 16), math.abs(mn and mn.x or 16))
        return h, wide
    end

    -- Персонаж — часть меню, НЕ «отдельное окно»: без рамки/фона стажи
    -- (замечание 03.09). Две панели подряд: фигура + «отражение».
    local function applyLook(m)
        m:SetModel(ply:GetModel() or "models/player.mdl")
        -- копия живой внешности: без этого DModelPanel показывает «голую»
        -- модель — «почему не показываются бодигруппы» (03.09)
        if ply:Skin() ~= nil then m:SetSkin(ply:Skin()) end
        if ply.GetBodyGroups and m.SetBodygroup then
            for _, bg in ipairs(ply:GetBodyGroups()) do
                local ok, val = pcall(function() return ply:GetBodygroup(bg.id) end)
                if ok and isnumber(val) then m:SetBodygroup(bg.id, val) end
            end
        end
    end

    local function newModel(parent, flip, px, py, pw, ph)
        local m = vgui.Create("DModelPanel", parent)
        local hgt, wide = camParams()
        m:SetSize(pw, ph)
        m:SetPos(px, py)
        applyLook(m)
        m:SetAnimated(not flip)
        -- Кадрируем ВСЮ фигуру: широкий кадр по полному росту (голова не
        -- режется — жалоба со скрина), панель кропает по своим границам.
        local dist = hgt * 2.05 + wide * 1.35 + 30
        if not flip then
            m:SetCamPos(Vector(dist, dist * 0.32, hgt * 0.54))
            m:SetLookAt(Vector(0, 0, hgt * 0.48))
        else
            -- «отражение»: камера сверху вниз; градиент тушит дальний край
            m:SetCamPos(Vector(dist, dist * 0.32, hgt * 1.62))
            m:SetLookAt(Vector(0, 0, hgt * 0.95))
            m.PaintOver = function(_, w2, h2)
                for i = 0, 5 do
                    local t = i / 5
                    surface.SetDrawColor(8, 14, 23, math.floor(90 + t * 160))
                    surface.DrawRect(0, math.floor(h2 * t / 2), w2, math.ceil(h2 / 6))
                end
            end
        end
        return m
    end
    local mainH = math.floor(stageH * 0.72)
    local reflH = stageH - mainH - 8
    Menu.model = newModel(root, false, stageX, stageY, stageW, mainH)
    Menu.modelRef = newModel(root, true, stageX, stageY + mainH + 8, stageW, reflH)

    ------------------------------------------------------------ карточка справа
    local card = newCard(root, rightW, 250)
    card:SetPos(scrW - rightW - 16, stageY + 8)

    local nameLbl = vgui.Create("DLabel", card)
    nameLbl:SetFont("GRMRP_MenuHead")
    nameLbl:SetTextColor(COL.gold)
    nameLbl:SetText("—")
    nameLbl:SetPos(14, 10)
    nameLbl:SetWide(rightW - 28)

    local steamLbl = vgui.Create("DLabel", card)
    steamLbl:SetFont("GRMRP_MenuDim")
    steamLbl:SetTextColor(COL.dim)
    steamLbl:SetPos(14, 42)
    steamLbl:SetWide(rightW - 28)

    local vHP = statRow(card, 76, "Здоровье")
    local vAR = statRow(card, 104, "Броня")
    local vMoney = statRow(card, 132, "Деньги")
    local vJob = statRow(card, 160, "Работа")
    local vTime = statRow(card, 188, "В игре")
    local vMap = statRow(card, 216, "Карта")

    ------------------------------------------------------------ статистика (тик 0.5с)
    card.nextStats = 0
    card.UpdateStats = function()
        if CurTime() < card.nextStats then return end
        card.nextStats = CurTime() + 0.5
        local pl = LocalPlayer()
        if not IsValid(pl) then return end
        local rpName = pl.GRMCharName
        nameLbl:SetText((isstring(rpName) and #rpName > 0 and rpName) or pl:Nick())
        steamLbl:SetText("Steam: " .. (pl.SteamName and pl:SteamName() or pl:Nick()))
        local mxHP = pl.GetMaxHealth and pl:GetMaxHealth() or 100
        vHP:SetText(tostring(math.max(0, pl:Health())) .. " / " .. tostring(mxHP))
        vAR:SetText(tostring(math.max(0, pl:Armor())))
        vMoney:SetText(GRMRP.Economy and GRMRP.Economy.GetBalance
            and tostring(GRMRP.Economy.GetBalance(pl)) or "—")
        vJob:SetText(GRMRP.Jobs and GRMRP.Jobs.GetJobName
            and tostring(GRMRP.Jobs.GetJobName(pl)) or "—")
        vTime:SetText(fmtTime(CurTime() - (GRMRP.JoinTime or CurTime())))
        vMap:SetText(game.GetMap())
    end

    ------------------------------------------------------------ закрытие/клавиши
    function root:OnKeyCodeTyped(code)
        if code == KEY_ESCAPE then
            if IsValid(Menu.settings) then
                Menu.settings:Remove()
                Menu.settings = nil
                return true
            end
            Menu.Close()
            return true
        end
    end

    ------------------------------------------------------------Think: только анимации
    root.AnimEnd = CurTime() + 0.05 * #animList + 0.35
    root.Think = function(s)
        local now = CurTime()
        if now < s.AnimEnd then
            local g = easeOut((now - s.animStart) / 0.5)
            s.bgAlpha = math.floor(255 * g)
            for i = 1, #animList do
                local b = animList[i]
                b.anim = easeOut((now - b.t0) / 0.32)
            end
        elseif s.bgAlpha ~= 255 then
            s.bgAlpha = 255
        end
        card:UpdateStats()
    end
end

function Menu.Close()
    if IsValid(Menu.settings) then
        Menu.settings:Remove()
        Menu.settings = nil
    end
    if IsValid(Menu.root) then Menu.root:Remove() end
    Menu.root = nil
    Menu.model = nil
    Menu.modelRef = nil
end

function Menu.ToggleSettings()
    if IsValid(Menu.settings) then
        Menu.settings:Remove()
        Menu.settings = nil
        return
    end
    if not IsValid(Menu.root) then return end
    local root = Menu.root
    local scrW, scrH = ScrW(), ScrH()
    local w = math.Clamp(scrW * 0.42, 480, 680)
    local h = math.min(scrH - 150, 560)
    local f = vgui.Create("DPanel", root)
    Menu.settings = f
    f:SetSize(w, h)
    f:SetPos(math.floor((scrW - w) / 2), math.floor((scrH - h) / 2))
    f.Paint = function(_, cw, ch)
        draw.RoundedBox(8, 0, 0, cw, ch, Color(12, 20, 32, 248))
        surface.SetDrawColor(40, 62, 92, 160)
        surface.DrawOutlinedRect(0, 0, cw, ch)
        draw.SimpleText("Настройки", "GRMRP_MenuHead", 16, 10, COL.text)
        draw.SimpleText("клиентские · применяются сразу · сервер их не видит",
            "GRMRP_MenuDim", 16, 42, COL.dim)
    end

    local scroll = vgui.Create("DScrollPanel", f)
    scroll:SetPos(12, 62)
    scroll:SetSize(w - 24, h - 110)
    local body = vgui.Create("DPanel", scroll)
    body:SetPaintBackground(false)
    local bw = w - 48
    body:SetWide(bw)

    local y = 0
    local function section(title)
        local lbl = vgui.Create("DLabel", body)
        lbl:SetText(string.upper(title))
        lbl:SetFont("GRMRP_MenuTab")
        lbl:SetTextColor(COL.accent)
        lbl:SetPos(4, y)
        lbl:SizeToContents()
        y = y + 30
    end
    local function finishRow(hh)
        local used = hh
        body:SetTall(y + 8)
        return used
    end

    -- Один владелец записи: ConVar:SetFloat напрямую. Никаких
    -- RunConsoleCommand/SetConvar-привязок — они гоняли cvar через консоль
    -- сервера и печатали «Command is blocked!» (лог 03.09).
    local function slider(label, cvarName, minV, maxV, dec, extra)
        local row = vgui.Create("DPanel", body)
        row:SetPos(0, y)
        row:SetSize(bw, 40)
        row:SetPaintBackground(false)
        local sl = vgui.Create("DNumSlider", row)
        sl:SetPos(0, 0)
        sl:SetSize(bw, 36)
        sl:SetText(label)
        sl:SetMin(minV)
        sl:SetMax(maxV)
        sl:SetDecimals(dec)
        local cv = cvarName and GetConVar(cvarName)
        if cv then sl:SetValue(math.Clamp(cv:GetFloat(), minV, maxV)) end
        sl.OnValueChanged = function(_, v2)
            if cv then cv:SetFloat(v2) end
            if extra then extra(v2) end
        end
        y = y + 42
        finishRow(40)
    end

    local function toggle(label, get, set, hint)
        local row = vgui.Create("DPanel", body)
        row:SetPos(0, y)
        row:SetSize(bw, 28)
        row:SetPaintBackground(false)
        local cap = vgui.Create("DLabel", row)
        cap:SetText(label)
        cap:SetFont("GRMRP_MenuLbl")
        cap:SetTextColor(COL.text)
        cap:SetPos(6, 6)
        cap:SetSize(bw - 120, 18)
        local btn = vgui.Create("DButton", row)
        btn:SetText("")
        btn:SetSize(96, 24)
        btn:SetPos(bw - 102, 2)
        btn.state = get() and true or false
        btn.Paint = function(s, w2, h2)
            local on = s.state
            draw.RoundedBox(4, 0, 0, w2, h2, on and
                Color(COL.green.r, COL.green.g, COL.green.b, 60) or Color(24, 38, 58, 220))
            draw.SimpleText(on and "Вкл" or "Выкл", "GRMRP_MenuLbl",
                w2 / 2 - 12, 4, on and COL.green or COL.dim)
        end
        btn.DoClick = function(s)
            s.state = not s.state
            set(s.state)
            surface.PlaySound("buttons/talkon.wav")
        end
        if hint then
            local hl = vgui.Create("DLabel", row)
            hl:SetText(hint)
            hl:SetFont("GRMRP_MenuDim")
            hl:SetTextColor(COL.dim)
            hl:SetPos(8, 20)
            hl:SizeToContents()
        end
        y = y + 30
        finishRow(28)
    end

    local function note(text)
        local lbl = vgui.Create("DLabel", body)
        lbl:SetText(text)
        lbl:SetFont("GRMRP_MenuDim")
        lbl:SetTextColor(COL.dim)
        lbl:SetPos(6, y)
        lbl:SetSize(bw - 12, 16)
        y = y + 20
    end

    section("Звук")
    slider("Общая громкость", "volume", 0, 1, 2)
    slider("Музыка", "snd_musicvolume", 0, 1, 2)

    section("Мышь")
    slider("Чувствительность", "sensitivity", 0.1, 10, 1)
    toggle("Сглаживание мыши", function()
        local cv = GetConVar("m_filter"); return cv and cv:GetBool()
    end, function(on)
        local cv = GetConVar("m_filter"); if cv then cv:SetBool(on) end
    end)
    toggle("Инверсия оси Y", function()
        local cv = GetConVar("m_pitch"); return cv and cv:GetFloat() < 0
    end, function(on)
        local cv = GetConVar("m_pitch")
        if cv then cv:SetFloat((on and -1 or 1) * math.abs(cv:GetFloat() > 0 and cv:GetFloat() or 0.022)) end
    end)

    section("Графика")
    slider("Поле зрения (fov_desired)", "fov_desired", 60, 110, 0, function(v)
        RunConsoleCommand("fov_set_favorite", tostring(math.floor(v)))
    end)
    slider("Максимум FPS (0 — без limits)", "fps_max", 0, 333, 0)
    slider("Сглаживание MSAA (после рестарта уровня)", "mat_antialias", 0, 8, 0,
        function(v)
            local snap = 0
            for _, a2 in ipairs({ 0, 2, 4, 8 }) do
                if math.abs(v - a2) < math.abs(v - snap) then snap = a2 end
            end
            local cv = GetConVar("mat_antialias")
            if cv then cv:SetFloat(snap) end
        end)
    slider("Резкость текстур (меньше — лучше)", "mat_picmip", -1, 3, 0)

    section("Интерфейс")
    slider("Счётчик FPS/пинга (net_graph)", "net_graph", 0, 3, 0)
    toggle("Показывать цель (TargetID)", function()
        local cv = GetConVar("hud_showtargetid"); return cv and cv:GetBool()
    end, function(on)
        local cv = GetConVar("hud_showtargetid"); if cv then cv:SetBool(on) end
    end)

    section("Чат")
    note("Y / привязка grm_chat_open — открыть · Enter — отправить · Tab — цели /pm")
    note("↑/↓ — своя история · ESC — закрыть · кнопка «история» — окно на 300 строк")
    note("emoji-пас включён: :) <3 +1 ... ; команды /me /do /it /try /roll")

    local close = vgui.Create("DButton", f)
    close:SetText("Закрыть  (ESC)")
    close:SetFont("GRMRP_MenuTab")
    close:SetSize(180, 32)
    close:SetPos((w - 180) / 2, h - 42)
    close.DoClick = function()
        surface.PlaySound("buttons/button14.wav")
        Menu.ToggleSettings()
    end
    function f:OnKeyCodeTyped(code)
        if code == KEY_ESCAPE then
            Menu.ToggleSettings()
            return true
        end
    end
    f:MakePopup()
end

------------------------------------------------------------------ перехват ESC
-- Движок открывает gameui по ESC без lua-хука; стандартный приём gamemode'ов —
-- поймать видимый gameui в тот же кадр, спрятать его (SP: снимает паузу) и
-- показать своё окно. Свои кнопки, сами зовущие gameui (вкладка «Сетевая
-- игра»), помечают окно подавленным через suppressUntil.
hook.Add("Think", "GRMRPMenu_Takeover", function()
    if IsValid(Menu.root) then return end
    if Menu.suppressUntil and CurTime() < Menu.suppressUntil then return end
    if gui.IsGameUIVisible() then
        gui.HideGameUI()
        Menu.Open()
    end
end)

-- Q-меню (spawnmenu) ужимаем до инструментов? — нет: sandbox-наследие живёт,
-- но our menu не конфликтует: gameui подавлен, spawnmenu не трогаем.
