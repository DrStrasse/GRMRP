--[[ GRM:RP — меню паузы. Заменяет стандартный gameui (ESC): плавные кнопки
    въезжают слева; справа — карточка персонажа: 3D-витрина ЖИВОГО вида
    (модель+скин+бодигруппы, вращается мышью) под RP-именем и статами —
    никакого «отдельного окна» в центре (замечание владельца 03.09). Реестр вкладок декларативный
    (GRMRPMenu.AddTab) — точка расширения окон режима (§5.16).
    Паттерны: §5.13 (анимации только пока идут), §5.17 (шрифты extended,
    кириллица), палитра общая с чатом.
]]

if SERVER then return end

GRMRPMenu = GRMRPMenu or {}
local Menu = GRMRPMenu
-- Оттиск сборки: виден в шапке меню. Нет строки «сборка …» на экране =
-- на сервере СТАРЫЙ файл (неснесённая папка grmrp — смешанные установки
-- уже жгли дважды; теперь опознание — один взгляд).
Menu.BuildStamp = 'вечер-10 (03.09)'

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
    action = function() Menu.OpenStandardSettings() end })
-- «Сетевая игра» = СТАРОЕ окно движка: server browser через gamemenucommand
-- (указание владельца вечером-9: «функционал должен выводить на старые окна»,
-- никаких подмен). Очередь подождёт menu-состояния — см. OpenGameuiWith.
Menu.AddTab({ id = "servers", order = 30, title = "Сетевая игра", accent = COL.accent,
    action = function() Menu.OpenGameuiWith("OpenServerBrowser") end })
Menu.AddTab({ id = "newgame", order = 40, title = "Новая игра (локально)", accent = COL.gold,
    visible = function() return game.SinglePlayer() end,
    action = function()
        local ok, err = pcall(function()
            game.CreateLocalServer(game.GetMap(), "GRM:RP — локально", function() end)
        end)
        if not ok then Menu.SystemLine("Не удалось: " .. tostring(err)) end
    end })
-- «Мастерская» — стандартное окно: главное меню движка (Addons/Workshop
-- живут в нём). Внешний URL был подменой функционала — снято (вечер-9).
Menu.AddTab({ id = "workshop", order = 50, title = "Мастерская", accent = COL.gold,
    action = function() Menu.OpenGameuiWith(nil) end })
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

    Menu.ownsGameui = false -- играем по-честному: чужая gameui-сессия не наша
    if not GRMRP.JoinTime then GRMRP.JoinTime = CurTime() end
    local scrW, scrH = ScrW(), ScrH()
    local root = vgui.Create("DPanel")
    Menu.root = root
    root:SetPos(0, 0)
    root:SetSize(scrW, scrH)
    root:MakePopup()
    root.animStart = CurTime()
    root.bgAlpha = 0
    -- ESC навешивается ДО контента: если сборка содержимого ошибётся,
    -- попоп не должен остаться висеть и есть invnext/invprev (селектор
    -- оружия «умер» именно так — крах Skin() в модели, лив 03.09).
    function root:OnKeyCodeTyped(code)
        if code == KEY_ESCAPE then
            -- обратный порядок (претензия вечера-9): ESC гасит ВЕРХНИЙ
            -- слой — открытый ввод/историю чата оставляет себе, меню
            -- закрывается, только когда оно и есть верхний слой
            if GRMRPChat and (GRMRPChat.INPUT_OPEN or GRMRPChat.HIST_OPEN) then
                return false
            end
            Menu.Close()
            return true
        end
    end

    local colW = math.Clamp(scrW * 0.24, 300, 380)

    root.Paint = function(s, w, h)
        -- фон: блюр кадра (заказ вечера-10: «не хватает блюра») — тот же
        -- Derma_DrawBackgroundBlur, что рисует standard-меню под своими
        -- попопами, + тонировка + лёгкий вертикальный градиент
        if Derma_DrawBackgroundBlur then
            Derma_DrawBackgroundBlur(s, s.animStart)
        end
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
        draw.SimpleText("меню паузы · v" .. (GRMRP and GRMRP.VERSION or "?") ..
            " · сборка " .. (Menu.BuildStamp or "∅ СТАРАЯ, перерапакуйте grmrp целиком"),
            "GRMRP_MenuDim", bx + 18, by - 18, COL.dim)
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
            end
            table.insert(animList, b)
            y = y + 42
        end
    end
    root.colH = y - 110

    ------------------------------------------------------------ витрина-карточка
    -- Показ персонажа — ВНУТРИ карточки справа, а не «отдельное окно» в
    -- центре экрана (замечание владельца 03.09). Бодигруппы и скин
    -- копируются с живого игрока: раньше DModelPanel рисовал «голую»
    -- дефолтную модель («почему не показываются текущие бодигруппы»).
    local ply = LocalPlayer()
    -- «Персонаж мелкий» (владелец 03.09 вечер-6): карточка и окно модели
    -- раздвинуты; раньше модель упиралась в потолок 120px на малых экранах.
    local rightW = math.Clamp(scrW * 0.30, 320, 430)
    local cardH = math.Clamp(scrH - 150, 420, 700)
    local modelH = math.Clamp(cardH - 62 - 196, 240, 440)
    local statsBase = 62 + modelH + 12
    cardH = statsBase + 6 * 28 + 18

    local card = newCard(root, rightW, cardH)
    card:SetPos(scrW - rightW - 16, 76)

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

    -- ВНЕШНОСТЬ — ЧЕРЕЗ GetEntity(): у базового DModelPanel (движковый
    -- garrysmod/lua/vgui/dmodelpanel.lua) НЕТ ни SetSkin, ни SetBodygroup,
    -- ни GetModelEntity — прежние «под guard'ом» вызовы молча
    -- пропускались, поэтому «бодигруппы так и не появились» (владелец,
    -- 03.09). Канон движка — писать на саму модель: ровно так делает
    -- официальный GenerateExample самой панели («ctrl:GetEntity():SetSkin(2)»).
    -- Скин/группы — отдельным проходом, их можно применять повторно.
    local function applySkinGroups(m)
        local e = m.GetEntity and m:GetEntity()
        if not IsValid(e) then return end
        if ply.GetSkin then
            local okS, sk = pcall(function() return ply:GetSkin() end)
            if okS and isnumber(sk) then pcall(function() e:SetSkin(sk) end) end
        end
        local applied = 0
        if ply.GetBodyGroups then
            for _, bg in ipairs(ply:GetBodyGroups()) do
                local idx = tonumber(bg.id)
                if idx then
                    local ok, val = pcall(function() return ply:GetBodygroup(idx) end)
                    if ok and isnumber(val) then
                        pcall(function() e:SetBodygroup(idx, val) end)
                        applied = applied + 1
                    end
                end
            end
        end
        if applied == 0 and ply.GetBodygroup then
            -- кастомная модель без внятного списка групп: грубая копия
            -- индексов 1..8 (движок сам игнорит несуществующие группы)
            for i = 1, 8 do
                local ok, val = pcall(function() return ply:GetBodygroup(i) end)
                if ok and isnumber(val) and val > 0 then
                    pcall(function() e:SetBodygroup(i, val) end)
                end
            end
        end
    end
    local function applyLook(m)
        m:SetModel(ply:GetModel() or "models/player.mdl")
        applySkinGroups(m)
    end

    local function newModel(parent, px, py, pw, ph)
        local m = vgui.Create("DModelPanel", parent)
        m:SetSize(pw, ph)
        m:SetPos(px, py)
        -- Камера своя и РАСЧЁТНАЯ: авторазмера у базовой панели НЕТ
        -- (дефолт camPos(50,50,50)+fov70 и рисовал «мелкого»).
        -- Длиннофокусный портрет: FOV 28, дистанция из условия
        -- «модель по высоте = 86% окна кадра».
        local hh = 72
        local mn, mx = ply:OBBMins(), ply:OBBMaxs()
        if mn and mx then
            hh = math.Clamp((mx.z or 72) - (mn.z or 0), 48, 200)
        end
        local fov = 28
        local d = math.max(60, (hh / 0.92) / (2 * math.tan(math.rad(fov * 0.5))))
        m:SetFOV(fov)
        m:SetCamPos(Vector(-d * 0.71, -d * 0.71, hh * 0.58))
        m:SetLookAt(Vector(0, 0, hh * 0.5))
        m:SetAmbientLight(Color(120, 124, 132))
        m:SetAnimSpeed(0.6)
        m:SetAnimated(true) -- idle/walk; поворот — базовый LayoutEntity
        -- сам крутит модель на месте (turntable), мыши у панели нет.
        applyLook(m)
        return m
    end

    -- Витрина — в пузыре: сорвалась — живёт всё остальное меню; «зависший
    -- полупрозрачный попоп» хуже, чем меню без модели.
    local okChar = pcall(function()
        Menu.model = newModel(card, 12, 62, rightW - 24, modelH)
    end)
    if not okChar then
        Menu.model = nil
        if GRMRP.ErrorNoHalt then
            GRMRP.ErrorNoHalt("меню: витрина персонажа отключена (ошибка сборки)")
        end
    end

    local vHP = statRow(card, statsBase, "Здоровье")
    local vAR = statRow(card, statsBase + 28, "Броня")
    local vMoney = statRow(card, statsBase + 56, "Деньги")
    local vJob = statRow(card, statsBase + 84, "Работа")
    local vTime = statRow(card, statsBase + 112, "В игре")
    local vMap = statRow(card, statsBase + 140, "Карта")

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
        -- Витрина живая: сменил модель — пересняли; сменил только
        -- бодигруппы/скин (экипировка) — применяем их, не дёргая SetModel.
        local mm = Menu.model
        if IsValid(mm) then
            local want = pl:GetModel() or "models/player.mdl"
            local cur = mm.GetModel and mm:GetModel()
            if cur ~= want then applyLook(mm) else applySkinGroups(mm) end
        end
    end

    ------------------------------------------------------------Think: только анимации
    root.AnimEnd = CurTime() + 0.05 * #animList + 0.35
    root.Think = function(s)
        -- Пока открыто МЕНЮ РЕЖИМА, движковый gameui не имеет права висеть
        -- поверх (гонка ESC 03.09: «стандартное меню открывается поверх»):
        -- снимаем его в тот же кадр тихо, без пересоздания нашего окна.
        if gui.IsGameUIVisible() then gui.HideGameUI() end
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
    if IsValid(Menu.root) then Menu.root:Remove() end
    Menu.root = nil
    Menu.model = nil
    Menu.modelRef = nil
    -- Грейс: движок вскрывает gameui от того же нажатия ESC; в окне грейса
    -- его НЕ перехватываем (не «возвращаем» своё окно), а тихо гасим.
    -- Открытие стандартного диалога настроек само снимает флаг.
    Menu.justClosedRT = RealTime()
end

-- Настройки/браузер/мастерская = СТАРОЕ: диалоги движка через gamemenucommand
-- (wiki «RunGameUICommand»: команда принимается только в menu-состоянии).
-- Вечер-10 по замечанию владельца: «украшать; функционал выводить на старые
-- окна и настройки». Раньше: gameui_activate + команда в тот же кадр (не
-- всякий раз принималась — «проблемы с настройками»), подавление our меню
-- на фиксированные 30 секунд (истёкли — Takeover погасил живой диалог:
-- «меню багнутое», ESC не в обратном порядке), внешняя URL для мастерской
-- (подмена — снята). Теперь: команда стоит в очереди и исполняется, лишь
-- движок реально показал gameui; пока сессия gameui открыта нами — перехват
-- молчит; пользователь закрывает engine-UI сам, и порядок ESC = диалог →
-- меню движка → игра.
function Menu.OpenGameuiWith(cmd)
    Menu.Close()
    Menu.justClosedRT = nil -- это не гонка ESC: gameui открыт нами
    Menu.ownsGameui = true
    Menu.pendingCmd = cmd
    Menu.pendingTries = cmd and 0 or nil
    if not gui.IsGameUIVisible() then
        pcall(function() RunConsoleCommand("gameui_activate") end)
    end
end

function Menu.OpenStandardSettings()
    Menu.OpenGameuiWith("OpenOptionsDialog")
end

------------------------------------------------------------------ перехват ESC
-- Движок открывает gameui по ESC без lua-хука; стандартный приём gamemode'ов —
-- поймать видимый gameui, спрятать его (SP: снимает паузу) и показать своё
-- окно. Кнопки, сами зовущие gameui (настройки/браузер/мастерская), помечают
-- сессию своей (ownsGameui) — в своей сессии движку не мешаем.
hook.Add("Think", "GRMRPMenu_Takeover", function()
    if gui.IsGameUIVisible() then
        if IsValid(Menu.root) then return end
        if Menu.justClosedRT and RealTime() - Menu.justClosedRT < 0.4 then
            gui.HideGameUI()
            return
        end
        if Menu.pendingCmd then
            local ok = pcall(function() RunGameUICommand(Menu.pendingCmd) end)
            Menu.pendingTries = (Menu.pendingTries or 0) + 1
            if ok then Menu.pendingCmd = nil
            elseif Menu.pendingTries > 10 then Menu.pendingCmd = nil end
            return
        end
        if Menu.ownsGameui then return end
        gui.HideGameUI()
        Menu.Open()
        return
    end
    if Menu.ownsGameui then
        -- пользователь закрыл engine-UI: обратный порядок сыгран до конца,
        -- перехват снова свободен
        Menu.ownsGameui = false
        Menu.pendingCmd = nil
    end
end)
