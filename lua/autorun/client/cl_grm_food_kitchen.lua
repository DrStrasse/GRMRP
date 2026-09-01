--[[
    GRM Food Kitchen — клиентские окна агрегатов (Код 110, «GrandEats»)
    Плита / Холодильник / Горшок: одно живое окно на душу.

    Протокол (sh_grm_food_kitchen.lua):
      сервер→клиент  GRM_Kitchen_Open : WriteTable пэйлоада
                     (payload.kind = "stove"/"fridge"/"planter",
                      payload.idx  = EntIndex агрегата)
      клиент→сервер  GRM_Kitchen_Op   : WriteUInt(idx,16) +
                     WriteString(op) + WriteTable(аргументы).

    Живое окно (урок Кода 108): НЕ пересоздаём фрейм — если окно уже
    открыто для этого агрегата, наполняем его заново по свежему
    пэйлоаду (сервер шлёт его после КАЖДОЙ операции). Тики готовки/
    роста между операциями крутятся на клиенте через payload.now +
    смещение от момента получения.
]]

if not CLIENT then return end

GRM = GRM or {}
GRM.Food = GRM.Food or {}

local function FK() return GRM.FoodKitchen or {} end

surface.CreateFont("GRMFK_Title",  { font = "Roboto", size = 22, weight = 800, extended = true })
surface.CreateFont("GRMFK_Normal", { font = "Roboto", size = 15, weight = 500, extended = true })
surface.CreateFont("GRMFK_Bold",   { font = "Roboto", size = 14, weight = 700, extended = true })
surface.CreateFont("GRMFK_Small",  { font = "Roboto", size = 13, weight = 400, extended = true })

-- цветовая гамма в духе сборки (тёмные панели, тёплые акценты)
local COL_BG      = Color(28, 28, 34, 245)
local COL_ROW     = Color(40, 40, 48, 235)
local COL_OK      = Color(120, 220, 140)
local COL_WARN    = Color(255, 190, 90)
local COL_BAD     = Color(255, 140, 110)
local COL_TEXT    = Color(235, 235, 240)
local COL_DIM     = Color(160, 160, 170)
local COL_ACCENT  = Color(255, 210, 70)

-- ============================================================
-- ХЕЛПЕРЫ
-- ============================================================

local function sendOp(idx, op, tbl)
    if not (FK().NET_OP and isnumber(idx)) then return end
    net.Start(FK().NET_OP)
        net.WriteUInt(idx, 16)
        net.WriteString(tostring(op or ""))
        net.WriteTable(istable(tbl) and tbl or {})
    net.SendToServer()
end

local function fmtTime(sec)
    sec = math.max(0, math.floor(tonumber(sec) or 0))
    local m = math.floor(sec / 60)
    local s = sec % 60
    if m > 0 then
        return string.format("%d мин %02d сек", m, s)
    end
    return string.format("%d сек", s)
end

local function fmtMoney(n)
    n = tonumber(n) or 0
    if GRM.Format then return GRM.Format(n) end
    return tostring(n) .. " GRM"
end

local function mkRow(parent, tall)
    local row = vgui.Create("DPanel", parent)
    row:Dock(TOP)
    row:SetTall(tall or 44)
    row:DockMargin(4, 4, 4, 0)
    row.Paint = function(self, w, h)
        draw.RoundedBox(6, 0, 0, w, h, COL_ROW)
    end
    return row
end

local function mkBtn(parent, txt, col)
    local b = vgui.Create("DButton", parent)
    b:SetText(tostring(txt or ""))
    b:SetFont("GRMFK_Bold")
    b:SetTextColor(col or COL_TEXT)
    b.Paint = function(self, w, h)
        local bg = self:IsEnabled() and Color(58, 58, 68, 255) or Color(44, 44, 50, 180)
        if self:IsHovered() and self:IsEnabled() then bg = Color(72, 72, 84, 255) end
        draw.RoundedBox(6, 0, 0, w, h, bg)
    end
    return b
end

local function mkHeader(parent, title, sub)
    local p = vgui.Create("DPanel", parent)
    p:Dock(TOP)
    p:SetTall(sub and 56 or 38)
    p:DockMargin(4, 4, 4, 2)
    p.Paint = function() end

    local t = vgui.Create("DLabel", p)
    t:Dock(TOP)
    t:SetFont("GRMFK_Title")
    t:SetText(title)
    t:SetTextColor(COL_ACCENT)
    t:SetContentAlignment(4)
    t:SetTall(30)

    if sub then
        local s = vgui.Create("DLabel", p)
        s:Dock(TOP)
        s:SetFont("GRMFK_Small")
        s:SetText(sub)
        s:SetTextColor(COL_DIM)
        s:SetContentAlignment(4)
        s:SetTall(18)
    end
    return p
end

-- ============================================================
-- ЖИВОЕ ОКНО: один фрейм, наполняем заново по пэйлоадам
-- ============================================================
local WIN = nil -- { frame=..., body=..., idx=..., kind=..., payload=..., recvAt=os.time() }

local buildStove, buildFridge, buildPlanter -- форварды

local function serverNow()
    if not WIN then return os.time() end
    return (tonumber(WIN.payload and WIN.payload.now) or os.time()) + (os.time() - (WIN.recvAt or os.time()))
end

local function refillWindow()
    if not (WIN and IsValid(WIN.frame) and IsValid(WIN.body)) then return end
    WIN.body:Clear()
    local k = WIN.kind
    if k == "stove" then
        buildStove(WIN.body, WIN.payload)
    elseif k == "fridge" then
        buildFridge(WIN.body, WIN.payload)
    elseif k == "planter" then
        buildPlanter(WIN.body, WIN.payload)
    end
end

local TITLES = {
    stove   = "Плита",
    fridge  = "Холодильник",
    planter = "Горшок для рассады",
}

local SIZES = {
    stove   = { 620, 560 },
    --[[ Холодильник шире и выше остальных: с переходом на сетку слотов
         (6 колонок по 74 пикселя + отступы и полоса прокрутки) прежних
         660x560 не хватало — ячейки резались по правому краю. ]]
    fridge  = { 560, 620 },
    planter = { 560, 480 },
}

local function openOrRefill(payload)
    if not istable(payload) then return end
    local kind = tostring(payload.kind or "")
    local idx  = tonumber(payload.idx) or -1
    if not TITLES[kind] or idx < 0 then return end

    -- живое окно: тот же агрегат — только перенаполняем (урок 108)
    if WIN and IsValid(WIN.frame) and WIN.idx == idx then
        WIN.kind = kind
        WIN.payload = payload
        WIN.recvAt = os.time()
        refillWindow()
        return
    end

    if WIN and IsValid(WIN.frame) then WIN.frame:Remove() end

    local sz = SIZES[kind] or { 600, 520 }
    local frame = vgui.Create("DFrame")
    frame:SetSize(sz[1], sz[2])
    frame:Center()
    frame:SetTitle("")
    frame:SetDeleteOnClose(true)
    frame:MakePopup()
    frame.lblTitle:SetVisible(false)
    frame.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, COL_BG)
        draw.RoundedBoxEx(8, 0, 0, w, 30, Color(22, 22, 26, 255), true, true, false, false)
        draw.SimpleText(TITLES[WIN and WIN.kind or kind] or "Кухня", "GRMFK_Bold", 10, 15, COL_ACCENT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local body = vgui.Create("DScrollPanel", frame)
    body:Dock(FILL)
    body:DockMargin(8, 34, 8, 8)
    local sb = body:GetVBar()
    if IsValid(sb) then sb:SetWide(6) end

    WIN = { frame = frame, body = body, idx = idx, kind = kind, payload = payload, recvAt = os.time() }
    refillWindow()
end

net.Receive(FK().NET_OPEN or "GRM_Kitchen_Open", function()
    local payload = net.ReadTable()
    openOrRefill(payload)
end)

-- ============================================================
-- ПЛИТА
-- ============================================================
buildStove = function(body, p)
    local idx = tonumber(p.idx) or -1
    local state = tonumber(p.state) or 0
    local ready = istable(p.ready) and p.ready or {}
    local readyCap = tonumber(p.readyCap) or 4

    -- статус готовки (живой тик через serverNow)
    mkHeader(body, "ПЛИТА", "Готовка по рецептам из ингредиентов инвентаря")

    local stat = mkRow(body, 66)
    local statLbl = vgui.Create("DLabel", stat)
    statLbl:Dock(TOP)
    statLbl:DockMargin(10, 6, 10, 0)
    statLbl:SetFont("GRMFK_Bold")
    statLbl:SetTall(20)
    local bar = vgui.Create("DProgress", stat)
    bar:Dock(TOP)
    bar:DockMargin(10, 4, 10, 0)
    bar:SetTall(16)

    -- время рецепта для прогресс-бара
    local totalTime = 0
    for _, r in ipairs(istable(p.recipes) and p.recipes or {}) do
        if tostring(r.id) == tostring(p.recipe or "") then
            totalTime = tonumber(r.time) or 0
            break
        end
    end

    if state == 1 then
        statLbl:SetTextColor(COL_WARN)
        local recName = tostring(p.recipe or "")
        for _, r in ipairs(istable(p.recipes) and p.recipes or {}) do
            if tostring(r.id) == recName then recName = tostring(r.name) break end
        end
        stat.Think = function()
            local left = (tonumber(p.finish) or 0) - serverNow()
            statLbl:SetText("Готовится: " .. recName .. " — осталось " .. fmtTime(left))
            bar:SetFraction(totalTime > 0 and math.Clamp(1 - left / totalTime, 0, 1) or 0)
            if IsValid(bar.TextLabel) then bar.TextLabel:SetText("") end
        end
    else
        statLbl:SetText("Плита свободна — выберите рецепт ниже.")
        statLbl:SetTextColor(COL_OK)
        bar:SetFraction(0)
    end

    -- лоток готовых блюд
    local tray = mkRow(body, 52)
    local trayLbl = vgui.Create("DLabel", tray)
    trayLbl:Dock(LEFT)
    trayLbl:DockMargin(10, 0, 6, 0)
    trayLbl:SetWide(360)
    trayLbl:SetFont("GRMFK_Normal")
    local names = {}
    for _, it in ipairs(ready) do names[#names + 1] = tostring(it.name or it.id) end
    trayLbl:SetText("Лоток готовых (" .. tostring(#ready) .. "/" .. tostring(readyCap) .. "): "
        .. (#names > 0 and table.concat(names, ", ") or "пусто"))
    trayLbl:SetTextColor(#ready > 0 and COL_OK or COL_DIM)

    local btnCollect = mkBtn(tray, "Забрать всё", COL_OK)
    btnCollect:Dock(RIGHT)
    btnCollect:DockMargin(6, 8, 10, 8)
    btnCollect:SetWide(120)
    btnCollect:SetEnabled(#ready > 0)
    btnCollect.DoClick = function() sendOp(idx, "stove_collect", {}) end

    if state == 1 then
        local btnCancel = mkBtn(tray, "Отменить готовку", COL_WARN)
        btnCancel:Dock(RIGHT)
        btnCancel:DockMargin(6, 8, 0, 8)
        btnCancel:SetWide(150)
        btnCancel.DoClick = function()
            Derma_Query("Отменить готовку? Ингредиенты вернутся в инвентарь.", "Плита",
                "Отменить", function() sendOp(idx, "stove_cancel", {}) end,
                "Оставить", function() end)
        end
    end

    -- список рецептов
    local lblR = vgui.Create("DLabel", body)
    lblR:Dock(TOP)
    lblR:DockMargin(6, 10, 6, 0)
    lblR:SetTall(20)
    lblR:SetFont("GRMFK_Bold")
    lblR:SetText("Рецепты:")
    lblR:SetTextColor(COL_TEXT)

    local recipes = istable(p.recipes) and p.recipes or {}
    if #recipes == 0 then
        local none = mkRow(body, 34)
        local l = vgui.Create("DLabel", none)
        l:Dock(FILL) l:DockMargin(10, 0, 10, 0)
        l:SetFont("GRMFK_Normal") l:SetText("Рецепты не настроены.") l:SetTextColor(COL_DIM)
        return
    end

    for _, r in ipairs(recipes) do
        local need = istable(r.need) and r.need or {}
        local rowH = 46 + #need * 18
        local row = mkRow(body, rowH)

        local title = vgui.Create("DLabel", row)
        title:Dock(TOP)
        title:DockMargin(10, 5, 10, 0)
        title:SetTall(18)
        title:SetFont("GRMFK_Bold")
        title:SetText(tostring(r.name) .. "  →  " .. tostring(r.outName or "?")
            .. "   (" .. fmtTime(r.time) .. ")")
        title:SetTextColor(r.can and COL_TEXT or COL_DIM)

        for _, nd in ipairs(need) do
            local l = vgui.Create("DLabel", row)
            l:Dock(TOP)
            l:DockMargin(18, 0, 10, 0)
            l:SetTall(16)
            l:SetFont("GRMFK_Small")
            local has = tonumber(nd.have) or 0
            local req = tonumber(nd.n) or 1
            local ok = has >= req
            l:SetText((ok and "✓ " or "✗ ") .. tostring(nd.name) .. ": " .. tostring(has) .. "/" .. tostring(req))
            l:SetTextColor(ok and COL_OK or COL_BAD)
        end

        local btn = mkBtn(row, state == 1 and "Плита занята" or "Готовить", COL_OK)
        btn:Dock(BOTTOM)
        btn:DockMargin(10, 2, 10, 6)
        btn:SetTall(24)
        btn:SetEnabled((tonumber(p.state) or 0) == 0 and r.can == true)
        btn.DoClick = function() sendOp(idx, "stove_cook", { recipe = tostring(r.id) }) end
    end
end

-- ============================================================
-- ХОЛОДИЛЬНИК
-- ============================================================
buildFridge = function(body, p)
    local idx = tonumber(p.idx) or -1
    local slots = istable(p.slots) and p.slots or {}
    local cap = tonumber(p.cap) or 12
    local store = istable(p.store) and p.store or {}

    mkHeader(body, "ХОЛОДИЛЬНИК", "Срок годности внутри заморожен — приготовленное не портится")

    --[[ СЕТКА СЛОТОВ ВМЕСТО СПИСКА СТРОК (заказ владельца 28.08:
         «в холодильнике бы слоты нормально сделать как в инвентаре»).

         Раньше содержимое рисовалось строками с двумя кнопками на
         каждой: занимало пол-экрана на трёх позициях, а сколько мест
         свободно — было понятно только из подписи. Сетка показывает и
         занятые, и ПУСТЫЕ ячейки: вместимость видна сразу, как в
         инвентаре и в домашнем шкафу.

         ЛКМ — переложить всё, SHIFT+ЛКМ — одну штуку. Та же раскладка,
         что в шкафу (sh_grm_housing_storage), чтобы игроку не пришлось
         запоминать разные правила для разных ящиков. ]]
    local COLS = 6
    local CELL = 74

    local function paintCell(self, w, h)
        local hov = self:IsHovered()
        local it = self._item
        local filled = istable(it) and it.id
        draw.RoundedBox(6, 0, 0, w, h, hov and Color(48, 66, 92, 250)
            or (filled and Color(38, 40, 50, 245) or Color(24, 24, 30, 235)))
        surface.SetDrawColor(filled and 70 or 44, filled and 130 or 46,
            filled and 190 or 58, hov and 230 or 150)
        surface.DrawOutlinedRect(0, 0, w, h, 1)

        if not filled then
            -- Пустая ячейка: видно, сколько места осталось.
            draw.SimpleText("·", "GRMFK_Normal", w / 2, h / 2, Color(70, 70, 82),
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            return
        end

        local mat = GRM.Perf and GRM.Perf.Material and GRM.Perf.Material(it.icon or "icon16/box.png")
            or Material(it.icon or "icon16/box.png", "smooth")
        if mat and not mat:IsError() then
            surface.SetMaterial(mat)
            surface.SetDrawColor(255, 255, 255, 235)
            surface.DrawTexturedRect(w / 2 - 12, 10, 24, 24)
        end

        -- Название режем по ширине ячейки, иначе оно вылезет за края.
        local nm = tostring(it.name or it.id)
        if #nm > 12 then nm = string.sub(nm, 1, 11) .. "…" end
        draw.SimpleText(nm, "GRMFK_Small", w / 2, h - 26,
            it.cooked and COL_WARN or COL_TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        local n = tonumber(it.n) or 1
        if n > 1 then
            draw.SimpleText("×" .. n, "GRMFK_Small", w - 6, 6, COL_ACCENT,
                TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
        end
        --[[ Портящееся помечаем точкой: в списке на это была целая
             колонка текста, в ячейке хватает цветной метки. ]]
        if it.cooked then
            draw.RoundedBox(3, 5, 5, 6, 6, COL_WARN)
        end
    end

    --- Одна сетка: host — куда класть, list — что показывать.
    local function grid(host, list, count, onClick, tipCooked)
        local rows = math.max(1, math.ceil(count / COLS))
        local pan = vgui.Create("DPanel", host)
        pan:Dock(TOP)
        pan:DockMargin(6, 4, 6, 0)
        pan:SetTall(rows * (CELL + 6))
        pan.Paint = function() end

        for i = 1, count do
            local it = list[i]
            local b = vgui.Create("DButton", pan)
            b:SetText("")
            local c, r = (i - 1) % COLS, math.floor((i - 1) / COLS)
            b:SetPos(c * (CELL + 6), r * (CELL + 6))
            b:SetSize(CELL, CELL)
            b._item = it
            b.Paint = paintCell
            if istable(it) and it.id then
                --[[ Подсказка с точным названием и остатком срока: в
                     ячейку это не помещается, а знать полезно. ]]
                local tip = tostring(it.name or it.id) .. " ×" .. tostring(it.n or 1)
                if tipCooked and it.cooked then
                    tip = tip .. "  ·  годен ещё " .. fmtTime(it.remain)
                elseif tipCooked then
                    tip = tip .. "  ·  не портится"
                elseif it.cooked then
                    tip = tip .. "  ·  портится вне холодильника!"
                end
                b:SetTooltip(tip .. "\nЛКМ — всё, SHIFT+ЛКМ — одну штуку")
                b.DoClick = function()
                    local one = input.IsKeyDown(KEY_LSHIFT) or input.IsKeyDown(KEY_RSHIFT)
                    onClick(it, one and 1 or (tonumber(it.n) or 1))
                end
            end
        end
        return pan
    end

    local lblIn = vgui.Create("DLabel", body)
    lblIn:Dock(TOP)
    lblIn:DockMargin(6, 6, 6, 0)
    lblIn:SetTall(20)
    lblIn:SetFont("GRMFK_Bold")
    lblIn:SetText("Внутри (" .. tostring(#slots) .. "/" .. tostring(cap) .. " слотов)   ·   ЛКМ — забрать всё, SHIFT+ЛКМ — одну")
    lblIn:SetTextColor(COL_TEXT)

    grid(body, slots, cap, function(it, n)
        sendOp(idx, "fridge_take", { slot = tonumber(it.slot) or 0, n = n })
    end, true)

    local lblPut = vgui.Create("DLabel", body)
    lblPut:Dock(TOP)
    lblPut:DockMargin(6, 14, 6, 0)
    lblPut:SetTall(20)
    lblPut:SetFont("GRMFK_Bold")
    lblPut:SetText("Из вашего инвентаря (можно хранить):")
    lblPut:SetTextColor(COL_TEXT)

    if #store == 0 then
        local none = mkRow(body, 34)
        local l = vgui.Create("DLabel", none)
        l:Dock(FILL) l:DockMargin(10, 0, 10, 0)
        l:SetFont("GRMFK_Normal") l:SetText("В инвентаре нет еды для хранения.") l:SetTextColor(COL_DIM)
    else
        --[[ Показываем ровно столько ячеек, сколько есть позиций:
             инвентарь игрока здесь не наш, рисовать его пустые слоты
             незачем. ]]
        grid(body, store, #store, function(it, n)
            sendOp(idx, "fridge_store", { id = tostring(it.id), n = n })
        end, false)
    end
end

-- ============================================================
-- ГОРШОК
-- ============================================================
buildPlanter = function(body, p)
    local idx = tonumber(p.idx) or -1
    local state = tonumber(p.state) or 0
    local crops = istable(p.crops) and p.crops or {}

    mkHeader(body, "ГОРШОК", "Сажайте семена, поливайте — и собирайте урожай сырых овощей")

    if state == 0 then
        local lbl = vgui.Create("DLabel", body)
        lbl:Dock(TOP)
        lbl:DockMargin(6, 6, 6, 0)
        lbl:SetTall(20)
        lbl:SetFont("GRMFK_Bold")
        lbl:SetText("Горшок пуст — выберите культуру:")
        lbl:SetTextColor(COL_TEXT)

        for _, c in ipairs(crops) do
            local row = mkRow(body, 46)
            local l = vgui.Create("DLabel", row)
            l:Dock(LEFT)
            l:DockMargin(10, 0, 6, 0)
            l:SetWide(330)
            l:SetFont("GRMFK_Normal")
            l:SetText(tostring(c.name) .. " — семена " .. fmtMoney(c.cost)
                .. ", " .. fmtTime(c.time) .. ", урожай ×" .. tostring(c.yield))
            l:SetTextColor(COL_TEXT)

            local btn = mkBtn(row, "Посадить", COL_OK)
            btn:Dock(RIGHT)
            btn:DockMargin(6, 7, 10, 7)
            btn:SetWide(100)
            btn.DoClick = function() sendOp(idx, "planter_plant", { crop = tostring(c.id) }) end
        end
        return
    end

    if state == 1 then
        -- живой отсчёт роста + полив
        local growTime = 0
        for _, c in ipairs(crops) do
            if tostring(c.id) == tostring(p.crop or "") then growTime = tonumber(c.time) or 0 break end
        end

        local stat = mkRow(body, 92)
        local l = vgui.Create("DLabel", stat)
        l:Dock(TOP)
        l:DockMargin(10, 6, 10, 0)
        l:SetTall(20)
        l:SetFont("GRMFK_Bold")
        l:SetTextColor(COL_OK)

        local bar = vgui.Create("DProgress", stat)
        bar:Dock(TOP)
        bar:DockMargin(10, 4, 10, 0)
        bar:SetTall(16)

        local btnWater = mkBtn(stat, "Полить (−25% времени)", COL_ACCENT)
        btnWater:Dock(BOTTOM)
        btnWater:DockMargin(10, 4, 10, 8)
        btnWater:SetTall(26)
        btnWater.DoClick = function() sendOp(idx, "planter_water", {}) end

        stat.Think = function()
            local now = serverNow()
            local left = (tonumber(p.finish) or 0) - now
            l:SetText("Растёт: " .. tostring(p.cropName or p.crop or "?")
                .. " — до урожая " .. fmtTime(left) .. " (урожай ×" .. tostring(p.yield or 1) .. ")")
            bar:SetFraction(growTime > 0 and math.Clamp(1 - left / growTime, 0, 1) or 0)
            local cd = (tonumber(p.waterAt) or 0) - now
            if cd > 0 then
                btnWater:SetEnabled(false)
                btnWater:SetText("Полить можно через " .. fmtTime(cd))
            else
                btnWater:SetEnabled(true)
                btnWater:SetText("Полить (−" .. tostring(math.floor((tonumber(p.boost) or 0.25) * 100)) .. "% времени)")
            end
        end
        return
    end

    -- state == 2: урожай готов
    local row = mkRow(body, 60)
    local l = vgui.Create("DLabel", row)
    l:Dock(TOP)
    l:DockMargin(10, 6, 10, 0)
    l:SetTall(20)
    l:SetFont("GRMFK_Bold")
    l:SetText("Урожай готов: " .. tostring(p.cropName or p.crop or "?") .. " ×" .. tostring(p.yield or 1) .. "!")
    l:SetTextColor(COL_OK)

    local btn = mkBtn(row, "Собрать урожай", COL_OK)
    btn:Dock(BOTTOM)
    btn:DockMargin(10, 2, 10, 8)
    btn:SetTall(26)
    btn.DoClick = function() sendOp(idx, "planter_harvest", {}) end
end
