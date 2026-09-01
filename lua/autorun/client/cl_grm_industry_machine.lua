--[[--------------------------------------------------------------------
    GRM Industry — окно станка и мини-игра.

    ДВЕ ЖАЛОБЫ ВЛАДЕЛЬЦА, КОТОРЫЕ ЗДЕСЬ ЗАКРЫВАЮТСЯ.

    1. Дизайн и предпросмотр. Было: одно окно на все четыре станка,
       список строк по 100 точек и предпросмотр 92×86 с зашитой
       камерой. Стало: список изделий слева, крупная карточка справа
       с настоящим 3D-предпросмотром, материалами и состоянием станка.

    2. «Мини-игра пройдена — и игрок свободно гуляет». Тело мини-игры
       здесь, но прогресс сборки теперь принадлежит задаче на сервере:
       отошёл — задача встала, а не пропала. Окно станка при этом не
       закрывается, состояние видно всё время.
----------------------------------------------------------------------]]

if not CLIENT then return end

GRM = GRM or {}
local I = GRM.Industry
local C = GRM.Container
local UI = I.UI
local NET = I.NET

--[[ Палитру (UI.C) заполняет cl_grm_industry_ui.lua, а файлы в
     lua/autorun/client грузятся по алфавиту — этот файл идёт РАНЬШЕ,
     чем ui. Раньше здесь было `local C_ = UI.C`, и на клиенте всё
     падало при загрузке: «attempt to index local 'UI' (a nil
     value)» — окно просто не появлялось. Читаем поле лениво, в
     момент обращения, когда палитра уже создана. ]]
local C_ = setmetatable({}, { __index = function(_, key)
    local palette = I.UI and I.UI.C
    return palette and palette[key]
end })

-- ================================================================
--  МИНИ-ИГРА
-- ================================================================
local ARROW_KEYS = { [KEY_UP] = 1, [KEY_RIGHT] = 2, [KEY_DOWN] = 3, [KEY_LEFT] = 4 }
local ARROW_GLYPH = { [1] = "↑", [2] = "→", [3] = "↓", [4] = "←" }

local mgFrame, mg = nil, nil

-- Узел, чьё окно сейчас открыто. Нужен обработчику обновления задачи.
local openEnt = nil

local function closeMinigame()
    if IsValid(mgFrame) then mgFrame:Close() end
    mgFrame, mg = nil, nil
end

local function sendStep(index, errorSeconds, missed, lane)
    net.Start(NET.step)
        net.WriteEntity(mg.ent)
        net.WriteUInt(index, 8)
        net.WriteFloat(math.Clamp(tonumber(errorSeconds) or 0, 0, mg.window))
        net.WriteBool(missed == true)
        net.WriteUInt(tonumber(lane) or 0, 4)
    net.SendToServer()
end

-- Завершаем шаг: либо玩家 попал, либо время вышло.
local function resolveStep(lane)
    if not mg or mg.closing then return end
    local ideal = mg.window * 0.6
    local elapsed = CurTime() - mg.stepStart
    local errorSeconds = math.abs(elapsed - ideal)
    local missed = math.abs(elapsed - ideal) > (mg.window * 0.35)
    if mg.kind == "assembly" and lane ~= (mg.sequence and mg.sequence[mg.index] or lane) then
        missed = true
    end

    mg.results[mg.index] = { error = errorSeconds, missed = missed }
    mg.flash = missed and "bad" or "good"
    mg.flashUntil = CurTime() + 0.25
    sendStep(mg.index, errorSeconds, missed, lane)

    if mg.index >= mg.steps then
        mg.closing = true
        timer.Simple(0.45, closeMinigame)
        return
    end
    mg.index = mg.index + 1
    mg.stepStart = CurTime()
end

local function openMinigame(ent, kind, steps, window, sequence)
    closeMinigame()
    if steps <= 0 then return end

    UI.Fonts()
    mg = {
        ent = ent, kind = kind or "rhythm", steps = steps,
        window = math.max(0.4, tonumber(window) or 1),
        sequence = sequence or {},
        index = 1, stepStart = CurTime(),
        results = {}, closing = false,
    }

    local titles = {
        rhythm = "Подача под пресс",
        trace  = "Пайка дорожек",
        assembly = "Сборка по чертежу",
    }
    local hints = {
        rhythm = "Пробел или ЛКМ — когда бегунок в зоне",
        trace  = "Пробел или ЛКМ — когда точка на узле",
        assembly = "Стрелки — в том порядке, который показывает чертёж",
    }

    local f = vgui.Create("DFrame")
    mgFrame = f
    GRM.UI.Track("industry_minigame", f)
    f:SetTitle("")
    f:SetSize(660, 400)
    f:Center()
    f:MakePopup()
    f:SetKeyboardInputEnabled(true)
    f:SetDraggable(false)
    f:ShowCloseButton(false)
    f.Paint = function(_, w, h)
        draw.RoundedBox(9, 0, 0, w, h, C_.bg)
        draw.RoundedBoxEx(9, 0, 0, w, 44, C_.header, true, true, false, false)
        draw.SimpleText(titles[mg.kind] or "Работа", "GRMInd_Title", 18, 23, C_.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(mg.index .. " / " .. mg.steps, "GRMInd_Normal", w - 18, 23, C_.yellow, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    f.OnKeyCodePressed = function(_, key)
        if not mg or mg.closing then return end
        if mg.kind == "assembly" then
            local lane = ARROW_KEYS[key]
            if lane then resolveStep(lane) end
        elseif key == KEY_SPACE then
            resolveStep(0)
        end
    end

    f.OnClose = function()
        -- Закрыли окно — недосланные шаги сервер досчитает промахами
        -- по своему крайнему сроку. Продукт не пропадёт: при провале
        -- часть сырья возвращается.
        mg = nil
        mgFrame = nil
    end

    local canvas = vgui.Create("DPanel", f)
    canvas:SetPos(18, 60)
    canvas:SetSize(624, 250)
    canvas.OnMousePressed = function(_, code)
        if code == MOUSE_LEFT and mg and mg.kind ~= "assembly" then resolveStep(0) end
    end
    canvas.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, C_.panel)
        if not mg then return end

        local t = math.Clamp((CurTime() - mg.stepStart) / mg.window, 0, 1)
        local ideal = 0.6
        local zone = 0.35

        if mg.kind == "assembly" then
            -- Крупная стрелка и подсказка следующей.
            local lane = mg.sequence[mg.index] or 1
            draw.SimpleText(ARROW_GLYPH[lane] or "?", "GRMInd_Big", w / 2, h / 2 - 10, C_.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText("нажмите " .. (ARROW_GLYPH[lane] or "?"), "GRMInd_Small", w / 2, h / 2 + 40, C_.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        else
            -- Бегунок и целевая зона.
            local trackX, trackW = 40, w - 80
            local trackY = h / 2 - 9
            draw.RoundedBox(6, trackX, trackY, trackW, 18, Color(18, 25, 35))
            local zoneX = trackX + trackW * (ideal - zone / 2)
            local zoneW = trackW * zone
            draw.RoundedBox(6, zoneX, trackY, zoneW, 18, Color(50, 82, 60))
            surface.SetDrawColor(C_.green)
            surface.DrawOutlinedRect(zoneX, trackY, zoneW, 18, 1)

            if mg.kind == "trace" then
                -- Путь точки: синусоида, узел — в зоне.
                surface.SetDrawColor(C_.line)
                for px = 0, trackW, 4 do
                    local f1 = px / trackW
                    local y1 = trackY + 9 + math.sin(f1 * math.pi * 3) * 22
                    local y2 = trackY + 9 + math.sin((px + 4) / trackW * math.pi * 3) * 22
                    surface.DrawLine(trackX + px, y1, trackX + px + 4, y2)
                end
                local cx = trackX + trackW * t
                local cy = trackY + 9 + math.sin(t * math.pi * 3) * 22
                surface.SetDrawColor(C_.accent)
                surface.DrawOutlinedRect(cx - 6, cy - 6, 12, 12, 2)
            else
                local cx = trackX + trackW * t
                draw.RoundedBox(3, cx - 4, trackY - 6, 8, 30, C_.accent)
            end
        end

        -- Остаток времени на шаг.
        UI.Bar(canvas, 40, h - 34, w - 80, 12, 1 - t, t > 0.85 and C_.red or C_.accent)
    end

    local hint = vgui.Create("DLabel", f)
    hint:SetPos(18, 320)
    hint:SetSize(624, 22)
    hint:SetText(hints[mg.kind] or "")
    hint:SetFont("GRMInd_Small")
    hint:SetTextColor(C_.dim)

    local cancel = UI.Button(f, "Прервать (материалы вернутся частично)", C_.red, 300, 30)
    cancel:SetPos(18, 352)
    cancel.DoClick = function()
        -- Молча закрыть нельзя: сервер должен списать промахи, иначе
        -- задача повиснет до своего крайнего срока.
        if mg and not mg.closing then
            mg.closing = true
            for i = mg.index, mg.steps do
                sendStep(i, mg.window, true, 0)
            end
        end
        timer.Simple(0.2, closeMinigame)
    end

    -- Досылаем промах, если игрок не успел.
    local watch = vgui.Create("DPanel", f)
    watch:SetSize(0, 0)
    watch.Think = function()
        if not mg or mg.closing then return end
        if CurTime() - mg.stepStart > mg.window then resolveStep(0) end
    end
end

net.Receive(NET.mg, function()
    local ent = net.ReadEntity()
    local kind = net.ReadString()
    local steps = net.ReadUInt(8)
    local window = net.ReadFloat()
    local sequence = net.ReadTable() or {}
    if not IsValid(ent) then return end
    openMinigame(ent, kind, steps, window, sequence)
end)

-- ================================================================
--  ОКНО СТАНКА
-- ================================================================
local function openStation(ent, data)
    if not IsValid(ent) then return end
    UI.Fonts()

    local stationName = (I.Stations[data.kind or ""] or {}).name or "Станок"
    local f, top = UI.Window("industry_station", stationName .. " — " .. (data.label or ""), 980, 640)
    openEnt = ent
    f.OnClose = function() if openEnt == ent then openEnt = nil end end

    local selected = nil
    local M = 14
    local LEFT_W = 340

    -- ─── ЛЕВАЯ КОЛОНКА: изделия ────────────────────────────────
    local leftCard, leftTop = UI.Card(f, "ИЗДЕЛИЯ")
    leftCard:SetPos(M, top + 8)
    leftCard:SetSize(LEFT_W, 420)

    local list = vgui.Create("DScrollPanel", leftCard)
    list:SetPos(6, leftTop)
    list:SetSize(LEFT_W - 12, 420 - leftTop - 6)
    local vbar = list:GetVBar()
    if IsValid(vbar) then
        vbar:SetWide(8)
        vbar.Paint = function() end
        vbar.btnUp.Paint = function() end
        vbar.btnDown.Paint = function() end
        vbar.btnGrip.Paint = function(self, w, h) draw.RoundedBox(4, 0, 0, w, h, C_.line) end
    end

    local rows = {}
    for _, recipe in ipairs(data.recipes or {}) do
        local row = UI.Row(list, 52, function(self)
            for _, r in ipairs(rows) do r.m_selected = false end
            self.m_selected = true
            selected = recipe
            if I.RefreshStationDetail then I.RefreshStationDetail(recipe) end
        end)
        row:Dock(TOP)
        row:DockMargin(0, 0, 0, 5)
        row.m_title = recipe.name or recipe.id
        row.m_hint = "лом " .. tostring(recipe.scrap or 0) .. " · " ..
                     tostring((recipe.process or 0) + (recipe.assemble or 0)) .. " с"
        row.m_value = (recipe.price and recipe.price > 0) and UI.Money(recipe.price) or I.NameOf(recipe.output)
        row.m_valueColor = C_.yellow
        row.m_recipe = recipe
        rows[#rows + 1] = row
    end

    -- ─── ЛЕВАЯ КОЛОНКА ВНИЗУ: вход и выход станка ──────────────
    local ioCard, ioTop = UI.Card(f, "ВХОД И ВЫХОД СТАНКА")
    ioCard:SetPos(M, top + 436)
    ioCard:SetSize(LEFT_W, 160)

    local ioList = vgui.Create("DScrollPanel", ioCard)
    ioList:SetPos(6, ioTop)
    ioList:SetSize(LEFT_W - 12, 160 - ioTop - 6)

    local function drawItemLine(parent, label, itemID, count, onTake)
        local line = vgui.Create("DPanel", parent)
        line:Dock(TOP); line:SetTall(26); line:DockMargin(0, 0, 0, 3)
        line.Paint = function(self, w, h)
            if self:IsHovered() then draw.RoundedBox(4, 0, 0, w, h, C_.hover) end
            draw.SimpleText(label, "GRMInd_Small", 8, h / 2, C_.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(I.NameOf(itemID) .. " ×" .. tostring(count), "GRMInd_Small", 110, h / 2, C_.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        if onTake then
            local b = UI.Button(line, "забрать", C_.accent, 62, 20)
            b:Dock(RIGHT); b:DockMargin(0, 3, 6, 3)
            b.DoClick = onTake
        end
        return line
    end

    local function refreshIO()
        ioList:Clear()
        local input, output = I.StationInput, I.StationOutput
        for _, line in ipairs(input or {}) do
            drawItemLine(ioList, "вход", line.itemID, line.count, nil)
        end
        local anyOut = false
        for _, line in ipairs(output or {}) do
            anyOut = true
            drawItemLine(ioList, "выход", line.itemID, line.count, function()
                net.Start(NET.action) net.WriteEntity(ent) net.WriteString("withdraw")
                    net.WriteString(line.itemID) net.WriteUInt(1, 16)
                net.SendToServer()
                f:Close()
            end)
        end
        if #(input or {}) == 0 and not anyOut then
            local empty = vgui.Create("DLabel", ioList)
            empty:Dock(TOP); empty:SetTall(24)
            empty:SetText("пусто")
            empty:SetFont("GRMInd_Small"); empty:SetTextColor(C_.dim)
        end
    end
    I.StationInput, I.StationOutput = data.input or {}, data.output or {}
    refreshIO()

    -- ─── ПРАВАЯ КОЛОНКА: карточка изделия ──────────────────────
    local rightX = M + LEFT_W + 12
    local rightW = 980 - rightX - M

    local preview = UI.ModelPanel(f, rightW, 260)
    preview:SetPos(rightX, top + 8)

    local infoCard, infoTop = UI.Card(f, "")
    infoCard:SetPos(rightX, top + 280)
    infoCard:SetSize(rightW, 168)

    local needList = vgui.Create("DPanel", infoCard)
    needList:SetPos(10, infoTop)
    needList:SetSize(rightW - 20, 92)
    needList.Paint = nil

    local statusLabel = vgui.Create("DLabel", infoCard)
    statusLabel:SetPos(10, infoTop + 96)
    statusLabel:SetSize(rightW - 20, 20)
    statusLabel:SetFont("GRMInd_Small")
    statusLabel:SetTextColor(C_.dim)

    -- ─── КНОПКИ ────────────────────────────────────────────────
    local btnY = top + 458
    local startBtn = UI.Button(f, "СОБРАТЬ", C_.accent, 220, 40)
    startBtn:SetPos(rightX, btnY)

    local depositBtn = UI.Button(f, "Загрузить сырьё", C_.green, 180, 40)
    depositBtn:SetPos(rightX + 232, btnY)

    local repairBtn = UI.Button(f, "Ремонт станка", C_.yellow, 180, 40)
    repairBtn:SetPos(rightX + 424, btnY)

    local jobBtn = UI.Button(f, "Отменить работу", C_.red, 180, 40)
    jobBtn:SetPos(rightX + 232, btnY + 48)

    local resumeBtn = UI.Button(f, "Продолжить работу", C_.green, 180, 40)
    resumeBtn:SetPos(rightX, btnY + 48)

    -- ─── ЛОГИКА ОБНОВЛЕНИЯ ─────────────────────────────────────
    local function selectedInputs()
        if not selected then return {} end
        return selected.inputs or {}
    end

    local function canStart()
        if not selected then return false end
        if data.job then return false end
        for _, line in ipairs(selectedInputs()) do
            if (tonumber(line.have) or 0) < (tonumber(line.need) or 0) then return false end
        end
        return true
    end

    function I.RefreshStationDetail(recipe)
        needList:Clear()
        if not recipe then
            preview:ClearItem()
            statusLabel:SetText("Выберите изделие слева")
            statusLabel:SetTextColor(C_.dim)
        else
            if recipe.weapon then
                preview:SetItem(recipe.weapon, recipe.name)
            else
                preview:SetItem(recipe.weapon, recipe.outputName)
            end

            local y = 0
            for _, line in ipairs(recipe.inputs or {}) do
                local enough = (tonumber(line.have) or 0) >= (tonumber(line.need) or 0)
                local l = vgui.Create("DPanel", needList)
                l:SetPos(0, y); l:SetSize(rightW - 20, 26)
                l.Paint = function(_, w, h)
                    draw.SimpleText(line.name, "GRMInd_Normal", 4, h / 2, C_.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    draw.SimpleText("нужно " .. tostring(line.need) .. " · есть " .. tostring(line.have),
                        "GRMInd_Small", w - 4, h / 2, enough and C_.green or C_.red, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                end
                y = y + 28
            end
            statusLabel:SetText("Сырьё: " .. tostring(recipe.scrap or 0) .. " лом · работа " ..
                tostring((recipe.process or 0) + (recipe.assemble or 0)) .. " с")
            statusLabel:SetTextColor(C_.dim)
        end

        startBtn:SetEnabled(canStart())
    end

    -- Состояние задачи: показываем всё время, окно не закрывается.
    local function refreshJob()
        local job = data.job
        if not job then
            jobBtn:SetVisible(false)
            resumeBtn:SetVisible(false)
            return
        end
        jobBtn:SetVisible(true)
        jobBtn:SetEnabled(job.worker == LocalPlayer() or LocalPlayer():IsSuperAdmin())
        resumeBtn:SetVisible(true)
        resumeBtn:SetEnabled(job.canResume ~= false)
    end

    -- Прогресс поверх карточки: рисуем на самом окне.
    local oldPaint = f.Paint
    f.Paint = function(self, w, h)
        oldPaint(self, w, h)

        local wear = tonumber(data.wear) or 0
        draw.SimpleText("Износ станка: " .. math.floor(wear) .. "%", "GRMInd_Small", rightX, h - 34,
            wear > 60 and C_.red or C_.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        if data.job then
            local stage = data.job.stage
            local text = "Свободен"
            local color = C_.green
            if stage == "process" then text = "Мини-игра: " .. tostring(data.job.step) .. "/" .. tostring(data.job.steps); color = C_.yellow
            elseif stage == "assemble" then text = "Сборка " .. math.floor((tonumber(data.job.progress) or 0) * 100) .. "%"; color = C_.accent
            elseif stage == "paused" then text = "ПАУЗА: " .. tostring(data.job.pauseReason or "работника нет"); color = C_.red
            elseif stage == "blocked" then text = "Выход станка забит"; color = C_.red end
            draw.SimpleText(text, "GRMInd_Normal", rightX, h - 56, color, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            if stage == "assemble" or stage == "paused" then
                UI.Bar(self, rightX, h - 48, 300, 8, tonumber(data.job.progress) or 0,
                    stage == "paused" and C_.red or C_.accent)
            end
            if data.job.worker and data.job.worker ~= "" then
                draw.SimpleText("Работник: " .. tostring(data.job.worker), "GRMInd_Small", rightX + 320, h - 56, C_.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
        end
    end

    startBtn.DoClick = function()
        if not selected then return end
        net.Start(NET.action) net.WriteEntity(ent) net.WriteString("job_start")
            net.WriteString(selected.id)
        net.SendToServer()
        f:Close()
    end

    depositBtn.DoClick = function()
        if not selected then return end
        for _, line in ipairs(selectedInputs()) do
            local missing = (tonumber(line.need) or 0) - (tonumber(C.Count(nil, line.itemID)) or 0)
            -- В станок кладём только то, чего не хватает на руках.
            local have = 0
            for _, pl in ipairs(data.player or {}) do
                if pl.itemID == line.itemID then have = pl.count end
            end
            local put = math.min(have, math.max(0, (tonumber(line.need) or 0) - (tonumber(line.have) or 0) + have))
            if put > 0 then
                net.Start(NET.action) net.WriteEntity(ent) net.WriteString("deposit")
                    net.WriteString(line.itemID) net.WriteUInt(put, 16)
                net.SendToServer()
            end
        end
        timer.Simple(0.3, function() if IsValid(f) then f:Close() end end)
    end

    repairBtn.DoClick = function()
        net.Start(NET.action) net.WriteEntity(ent) net.WriteString("station_repair") net.SendToServer()
        f:Close()
    end

    jobBtn.DoClick = function()
        net.Start(NET.action) net.WriteEntity(ent) net.WriteString("job_cancel") net.SendToServer()
        f:Close()
    end

    resumeBtn.DoClick = function()
        net.Start(NET.action) net.WriteEntity(ent) net.WriteString("job_resume") net.SendToServer()
        f:Close()
    end

    if rows[1] then rows[1].DoClick(rows[1]) end
    refreshJob()
end

-- ================================================================
--  ОКНА ПРОЧИХ РОЛЕЙ ЦЕХА
-- ================================================================
local function openSupply(ent, data)
    if not IsValid(ent) then return end
    UI.Fonts()
    local f, top = UI.Window("industry_supply", "Источник сырья — " .. (data.label or ""), 520, 330)

    local card, cardTop = UI.Card(f, "МЕТАЛЛОЛОМ")
    card:SetPos(14, top + 8); card:SetSize(492, 120)

    local stock = tonumber(data.stock) or 0
    local maxStock = tonumber(data.maxStock) or 60

    local bar = vgui.Create("DPanel", card)
    bar:SetPos(10, cardTop); bar:SetSize(472, 40); bar.Paint = nil
    bar.Paint = function(_, w, h)
        draw.SimpleText(stock .. " / " .. maxStock, "GRMInd_Head", 4, h / 2, C_.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        UI.Bar(bar, 120, h / 2 - 8, w - 124, 16, stock / math.max(1, maxStock), C_.yellow)
    end

    local one = UI.Button(f, "Взять 1", C_.green, 150, 38); one:SetPos(14, top + 140)
    one.DoClick = function()
        net.Start(NET.action) net.WriteEntity(ent) net.WriteString("supply_take") net.WriteUInt(1, 16) net.SendToServer()
        f:Close()
    end

    local five = UI.Button(f, "Взять 5", C_.green, 150, 38); five:SetPos(180, top + 140)
    five.DoClick = function()
        net.Start(NET.action) net.WriteEntity(ent) net.WriteString("supply_take") net.WriteUInt(5, 16) net.SendToServer()
        f:Close()
    end

    local ten = UI.Button(f, "Взять 10", C_.green, 150, 38); ten:SetPos(346, top + 140)
    ten.DoClick = function()
        net.Start(NET.action) net.WriteEntity(ent) net.WriteString("supply_take") net.WriteUInt(10, 16) net.SendToServer()
        f:Close()
    end

    local note = vgui.Create("DLabel", f)
    note:SetPos(14, top + 196); note:SetSize(492, 44); note:SetWrap(true)
    note:SetFont("GRMInd_Small"); note:SetTextColor(C_.dim)
    note:SetText("Источник пополняется сам, но медленно. Металлолом можно купить на точке сбыта — деньги вместо ожидания.")
end

local function openStorage(ent, data)
    if not IsValid(ent) then return end
    UI.Fonts()
    local f, top = UI.Window("industry_storage", "Склад цеха — " .. (data.label or ""), 760, 520)

    local card, cardTop = UI.Card(f, "НА СКЛАДЕ")
    card:SetPos(14, top + 8); card:SetSize(732, 330)

    local list = vgui.Create("DScrollPanel", card)
    list:SetPos(8, cardTop); list:SetSize(716, 330 - cardTop - 8)

    local function line(itemID, count)
        local p = vgui.Create("DPanel", list)
        p:Dock(TOP); p:SetTall(30); p:DockMargin(0, 0, 0, 4)
        p.Paint = function(self, w, h)
            draw.RoundedBox(5, 0, 0, w, h, self:IsHovered() and C_.hover or C_.slot)
            draw.SimpleText(I.NameOf(itemID), "GRMInd_Normal", 10, h / 2, C_.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText("×" .. tostring(count), "GRMInd_Normal", 200, h / 2, C_.yellow, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        local take = UI.Button(p, "взять", C_.accent, 70, 22); take:Dock(RIGHT); take:DockMargin(0, 4, 90, 4)
        take.DoClick = function()
            net.Start(NET.action) net.WriteEntity(ent) net.WriteString("storage_take")
                net.WriteString(itemID) net.WriteUInt(1, 16) net.SendToServer()
            f:Close()
        end
        local takeAll = UI.Button(p, "всё", C_.green, 70, 22); takeAll:Dock(RIGHT); takeAll:DockMargin(0, 4, 8, 4)
        takeAll.DoClick = function()
            net.Start(NET.action) net.WriteEntity(ent) net.WriteString("storage_take")
                net.WriteString(itemID) net.WriteUInt(math.min(count, 60000), 16) net.SendToServer()
            f:Close()
        end
    end

    for _, entry in ipairs(data.output or {}) do line(entry.itemID, entry.count) end
    if #(data.output or {}) == 0 then
        local empty = vgui.Create("DLabel", list)
        empty:Dock(TOP); empty:SetTall(26); empty:SetText("склад пуст")
        empty:SetFont("GRMInd_Small"); empty:SetTextColor(C_.dim)
    end

    local hint = vgui.Create("DLabel", f)
    hint:SetPos(14, top + 350); hint:SetSize(732, 22)
    hint:SetFont("GRMInd_Small"); hint:SetTextColor(C_.dim)
    hint:SetText("Положить продукцию на склад: откройте склад, держа изделие в инвентаре, и нажмите «взять» напротив — так проще.")

    local deposit = UI.Button(f, "Положить всё с рук на склад", C_.green, 300, 34)
    deposit:SetPos(14, top + 386)
    deposit.DoClick = function()
        for _, entry in ipairs(data.player or {}) do
            if I.PriceOf(entry.itemID) >= 0 and not (I.ItemDef(entry.itemID) or {}).defect then
                net.Start(NET.action) net.WriteEntity(ent) net.WriteString("storage_deposit")
                    net.WriteString(entry.itemID) net.WriteUInt(math.min(entry.count, 60000), 16) net.SendToServer()
            end
        end
        timer.Simple(0.4, function() if IsValid(f) then f:Close() end end)
    end
end

local function openMarket(ent, data)
    if not IsValid(ent) then return end
    UI.Fonts()
    local f, top = UI.Window("industry_market", "Точка сбыта — " .. (data.label or ""), 720, 520)

    local card, cardTop = UI.Card(f, "ВАШИ ТОВАРЫ (оплата " .. math.floor((data.sellPercent or 0.5) * 100) .. "%)")
    card:SetPos(14, top + 8); card:SetSize(692, 340)

    local list = vgui.Create("DScrollPanel", card)
    list:SetPos(8, cardTop); list:SetSize(676, 340 - cardTop - 8)

    for _, entry in ipairs(data.player or {}) do
        local price = I.PriceOf(entry.itemID)
        if price > 0 then
            local p = vgui.Create("DPanel", list)
            p:Dock(TOP); p:SetTall(30); p:DockMargin(0, 0, 0, 4)
            p.Paint = function(self, w, h)
                draw.RoundedBox(5, 0, 0, w, h, self:IsHovered() and C_.hover or C_.slot)
                draw.SimpleText(I.NameOf(entry.itemID), "GRMInd_Normal", 10, h / 2, C_.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText("×" .. tostring(entry.count), "GRMInd_Normal", 260, h / 2, C_.yellow, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText(UI.Money(math.floor(price * (data.sellPercent or 0.5) * entry.count)), "GRMInd_Normal",
                    500, h / 2, C_.green, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            local sell = UI.Button(p, "продать всё", C_.green, 120, 22); sell:Dock(RIGHT); sell:DockMargin(0, 4, 8, 4)
            sell.DoClick = function()
                net.Start(NET.action) net.WriteEntity(ent) net.WriteString("market_sell")
                    net.WriteString(entry.itemID) net.WriteUInt(math.min(entry.count, 60000), 16) net.SendToServer()
                f:Close()
            end
        end
    end

    local buyCard, buyTop = UI.Card(f, "МЕТАЛЛОЛОМ (по " .. UI.Money(data.scrapPrice or 60) .. " за шт.)")
    buyCard:SetPos(14, top + 360); buyCard:SetSize(692, 96)

    local ten = UI.Button(buyCard, "Купить 10", C_.accent, 140, 32); ten:SetPos(12, buyTop + 6)
    ten.DoClick = function()
        net.Start(NET.action) net.WriteEntity(ent) net.WriteString("market_buy_scrap") net.WriteUInt(10, 16) net.SendToServer()
        f:Close()
    end
    local fifty = UI.Button(buyCard, "Купить 50", C_.accent, 140, 32); fifty:SetPos(164, buyTop + 6)
    fifty.DoClick = function()
        net.Start(NET.action) net.WriteEntity(ent) net.WriteString("market_buy_scrap") net.WriteUInt(50, 16) net.SendToServer()
        f:Close()
    end
    local note = vgui.Create("DLabel", buyCard)
    note:SetPos(320, buyTop + 6); note:SetSize(360, 40); note:SetWrap(true)
    note:SetFont("GRMInd_Small"); note:SetTextColor(C_.dim)
    note:SetText("Покупка сырья — это обмен денег на время: ждать пополнения источника или заплатить и работать сразу.")
end

-- ================================================================
--  ДИСПЕТЧЕР ОКОН
-- ================================================================
local Openers = {
    station = openStation,
    supply  = openSupply,
    storage = openStorage,
    market  = openMarket,
}

net.Receive(NET.open, function()
    local ent = net.ReadEntity()
    local data = net.ReadTable() or {}
    local opener = Openers[data.role or ""]
    if opener then opener(ent, data) end
end)

--[[ ОБНОВЛЕНИЕ ЗАДАЧИ. Сервер шлёт состояние после каждого шага и при
     смене стадии. Если окно станка открыто — перезапрашиваем состояние,
     чтобы прогресс шёл на глазах, а не только при повторном нажатии E.
     Ссылка на открытый узел хранится в openEnt: из пакета её взять
     нельзя, сервер шлёт только идентификатор станка. ]]
net.Receive(NET.job, function()
    local machine = net.ReadString()
    local job = net.ReadTable() or {}

    if job.stage == "paused" and job.pauseReason then
        UI.Notify("Работа на паузе: " .. tostring(job.pauseReason), false)
    elseif job.stage == "blocked" then
        UI.Notify("Выход станка забит — заберите готовое", false)
    elseif job.stage == "assemble" and job.quality then
        UI.Notify("Качество " .. tostring(job.quality) .. "/100, идёт сборка", true)
    end

    if machine ~= "" and IsValid(openEnt) and openEnt:GetNodeID() == machine then
        net.Start(NET.action)
            net.WriteEntity(openEnt)
            net.WriteString("refresh")
        net.SendToServer()
    end
end)

print("[GRM Industry] окна цеха загружены")
