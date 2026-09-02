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

    local function newModel(flip)
        local m = vgui.Create("DModelPanel", root)
        local hgt, wide = camParams()
        local showH = flip and math.floor(stageH * 0.32) or math.floor(stageH * 0.66)
        m:SetSize(stageW, showH)
        m:SetPos(stageX, flip and (stageY + showH) or (stageY - 10))
        m:SetModel(ply:GetModel() or "models/player.mdl")
        m:SetAnimated(not flip)
        if m.SetFOV then m:SetFOV(38) end
        local dist = hgt * 1.15 + wide * 1.6 + 40
        if not flip then
            m:SetCamPos(Vector(dist, 0, hgt * 0.52))
            m:SetLookAt(Vector(0, 0, hgt * 0.5))
        else
            -- «отражение»: камера снизу у плоскости ног — персонаж кувырком,
            -- затемняется оверлеем; за границы карточки не вылезает (панель кропает)
            m:SetCamPos(Vector(dist * 0.85, 0, -hgt * 0.28))
            m:SetLookAt(Vector(0, 0, hgt * 0.12))
        end
        if flip then
            m.PaintOver = function()
                local w2, h2 = m:GetSize()
                surface.SetDrawColor(8, 14, 23, 165)
                surface.DrawRect(0, 0, w2, h2)
            end
        end
        return m
    end
    Menu.model = newModel(false)
    Menu.modelRef = newModel(true)

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
    local scrW, scrH = ScrW(), ScrH()
    local w, h = 460, 300
    local f = vgui.Create("DPanel", Menu.root)
    Menu.settings = f
    f:SetSize(w, h)
    f:SetPos((scrW - w) / 2, (scrH - h) / 2)
    f.Paint = function(s, cw, ch)
        draw.RoundedBox(8, 0, 0, cw, ch, Color(12, 20, 32, 245))
        surface.SetDrawColor(40, 62, 92, 160)
        surface.DrawOutlinedRect(0, 0, cw, ch)
        draw.SimpleText("Быстрые настройки", "GRMRP_MenuHead", 16, 10, COL.text)
    end

    local rows = {
        { label = "Общая громкость", cvar = "volume", min = 0, max = 1, dec = 2 },
        { label = "Музыка", cvar = "snd_musicvolume", min = 0, max = 1, dec = 2 },
        { label = "Чувствительность мыши", cvar = "sensitivity", min = 0.1, max = 5, dec = 2 },
        { label = "Поле зрения (FOV)", fov = true, min = 60, max = 110, dec = 0 }
    }
    local y = 52
    for _, r in ipairs(rows) do
        local sl
        if r.fov then
            sl = vgui.Create("DNumSlider", f)
            local want = GetConVarNumber("fov_desired") or 75
            sl:SetValue(want)
            sl.OnValueChanged = function(_, v)
                RunConsoleCommand("fov_set_favorite", tostring(math.floor(v)))
            end
        else
            sl = vgui.Create("DNumSlider", f)
            sl:SetConVar(r.cvar)
        end
        sl:SetPos(10, y)
        sl:SetSize(w - 20, 34)
        sl:SetText(r.label)
        sl:SetMin(r.min)
        sl:SetMax(r.max)
        sl:SetDecimals(r.dec)
        y = y + 44
    end

    local close = vgui.Create("DButton", f)
    close:SetText("Закрыть  (ESC)")
    close:SetFont("GRMRP_MenuTab")
    close:SetSize(180, 32)
    close:SetPos((w - 180) / 2, h - 44)
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
