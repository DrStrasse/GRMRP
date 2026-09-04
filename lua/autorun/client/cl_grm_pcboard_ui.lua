--[[--------------------------------------------------------------------
    GRM PCBoard UI v1.0.0 — вывод справки и вкладка «Госбаза» в /factions

    Клиентская часть планшета:
      • справка приходит одним пакетом и печатается в чат цветами GRM;
      • по кнопке (или команде grm_pcboard_window) открывается то же самое
        окном — спецслужбам с десятком блоков в чате тесно;
      • суперадмин настраивает допуски во вкладке «Госбаза» меню /factions:
        слева дерево (организация → отделы → подотделы → должности),
        справа уровень допуска узла и галочки блоков.
----------------------------------------------------------------------]]
if not CLIENT then return end

GRM = GRM or {}
GRM.PCBoard = GRM.PCBoard or {}
local PB = GRM.PCBoard

local C = {
    bg     = Color(20, 25, 34, 250),
    card   = Color(32, 40, 53, 245),
    line   = Color(52, 63, 80, 220),
    text   = Color(232, 238, 246),
    dim    = Color(160, 172, 190),
    gold   = Color(226, 184, 92),
    green  = Color(92, 200, 130),
    red    = Color(220, 92, 88),
    accent = Color(72, 150, 244),
}

surface.CreateFont("GRMPCB_Title", { font = "Roboto", size = 22, weight = 800, extended = true })
surface.CreateFont("GRMPCB_Sub",   { font = "Roboto", size = 16, weight = 700, extended = true })
surface.CreateFont("GRMPCB_Text",  { font = "Roboto", size = 15, weight = 500, extended = true })
surface.CreateFont("GRMPCB_Small", { font = "Roboto", size = 13, weight = 400, extended = true })

local cvWindow = CreateClientConVar("grm_cl_pcboard_window", "0", true, false,
    "Открывать справку госбазы отдельным окном (1) или только в чате (0)")

--- Обрезка длинной подписи по фактической ширине панели: «Подотдел:
--- Управление Начальника ВАИ Гарнизона» иначе уезжает под соседний текст.
local function elide(text, font, maxWidth)
    text = tostring(text or "")
    if maxWidth <= 0 then return "" end
    surface.SetFont(font)
    if (surface.GetTextSize(text) or 0) <= maxWidth then return text end
local cut = text    while #cut > 1 do
        -- шаг по UTF-8, иначе кириллица рвётся пополам и превращается в кракозябры
        local last = #cut
        while last > 1 and bit.band(string.byte(cut, last), 0xC0) == 0x80 do last = last - 1 end
        cut = string.sub(cut, 1, last - 1)
        if (surface.GetTextSize(cut .. "…") or 0) <= maxWidth then return cut .. "…" end
    end
    return "…"
end

-- Общая кнопка модуля объявлена ВЫШЕ всех, кто её вызывает: замыкание
-- не видит local, объявленный ниже по файлу.
local function clickSnd(kind)
    local path = kind == "hover" and "garrysmod/ui_hover.wav" or "ui/buttonclick.wav"
    if GRM.Sound and GRM.Sound.UI then GRM.Sound.UI(path, kind == "hover" and 0.02 or 0.05)
    elseif surface and surface.PlaySound then surface.PlaySound(path) end
end

local function mkButton(parent, text, color)
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b:SetCursor("hand")
    b.Paint = function(self, w, h)
        local hov, down = self:IsHovered(), self:IsDown()
        if hov and self._hov ~= true then clickSnd("hover") end
        self._hov = hov
        local c = color or C.accent
        if down then c = Color(math.max(c.r - 28, 0), math.max(c.g - 28, 0), math.max(c.b - 28, 0))
        elseif hov then c = Color(math.min(c.r + 22, 255), math.min(c.g + 22, 255), math.min(c.b + 22, 255)) end
        draw.RoundedBox(6, 0, down and 1 or 0, w, h - (down and 1 or 0), c)
        if hov and not down then draw.RoundedBox(6, 1, 1, w - 2, 2, Color(255, 255, 255, 40)) end
        draw.SimpleText(text, "GRMPCB_Text", w * 0.5, h * 0.5 + (down and 1 or 0), C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    b.OnDepressed = function()
        clickSnd("click")
    end
    return b
end

-----------------------------------------------------------------------
-- ВЫВОД СПРАВКИ В ЧАТ
-----------------------------------------------------------------------
local function printCard(card)
    local head = card.self and "ВАША КАРТОЧКА" or "СПРАВКА"
    chat.AddText(C.gold, "[ГОСБАЗА] ", C.text, head .. " · ",
        C.accent, card.cid ~= "" and card.cid or "без номера",
        C.dim, "  (" .. tostring(card.levelName or "") .. (card.hidden and " · скрытно" or "") .. ")")
    chat.AddText(C.text, tostring(card.title or "—"))
    for _, block in ipairs(card.blocks or {}) do
        chat.AddText(C.gold, "— " .. tostring(block.label))
        for _, row in ipairs(block.rows or {}) do
            chat.AddText(C.dim, "   " .. tostring(row[1]) .. ": ", C.text, tostring(row[2]))
        end
    end
    chat.AddText(C.dim, "   подробнее окном: grm_pcboard_window")
end

-----------------------------------------------------------------------
-- ОКНО СПРАВКИ
-----------------------------------------------------------------------
function PB.OpenCardWindow(card)
    card = card or PB.LastCard
    if not istable(card) then
        notification.AddLegacy("Справка ещё не запрашивалась.", NOTIFY_ERROR, 4)
        return
    end
    if IsValid(PB._cardFrame) then PB._cardFrame:Remove() end

    local frame = vgui.Create("DFrame")
    PB._cardFrame = frame
    -- Окно справки тоже тянется под экран: у спецслужб блоков много.
    frame:SetSize(math.Clamp(math.floor(ScrW() * 0.42), 620, 900),
        math.Clamp(math.floor(ScrH() * 0.78), 620, 1000))
    frame:SetSizable(true)
    frame:Center()
    frame:SetTitle("")
    frame:MakePopup()
    frame.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, C.bg)
        draw.RoundedBox(8, 0, 0, w, 64, C.card)
        draw.SimpleText("ГОСУДАРСТВЕННАЯ БАЗА ДАННЫХ", "GRMPCB_Sub", 18, 14, C.gold)
        draw.SimpleText(tostring(card.title or "—") .. "   " .. tostring(card.cid or ""),
            "GRMPCB_Title", 18, 34, C.text)
        draw.SimpleText(tostring(card.levelName or "") .. " · " .. os.date("%d.%m.%Y %H:%M", card.time or os.time()),
            "GRMPCB_Small", w - 18, 22, C.dim, TEXT_ALIGN_RIGHT)
    end

    local scroll = vgui.Create("DScrollPanel", frame)
    scroll:Dock(FILL)
    scroll:DockMargin(10, 70, 10, 10)

    for _, block in ipairs(card.blocks or {}) do
        local rows = block.rows or {}
        local panel = vgui.Create("DPanel", scroll)
        panel:Dock(TOP)
        panel:DockMargin(0, 0, 0, 8)
        panel:SetTall(30 + #rows * 20)
        panel.Paint = function(_, w, h)
            draw.RoundedBox(6, 0, 0, w, h, C.card)
            draw.SimpleText(tostring(block.label), "GRMPCB_Sub", 12, 7, C.gold)
            for i, row in ipairs(rows) do
                local y = 28 + (i - 1) * 20
                draw.SimpleText(tostring(row[1]), "GRMPCB_Text", 16, y, C.dim)
                draw.SimpleText(tostring(row[2]), "GRMPCB_Text", 220, y, C.text)
            end
        end
    end
end

concommand.Add("grm_pcboard_window", function() PB.OpenCardWindow() end)

hook.Add("GRM_PCBoardCard", "GRM_PCBoard_Show", function(card)
    printCard(card)
    surface.PlaySound("buttons/button17.wav")
    if cvWindow:GetBool() then PB.OpenCardWindow(card) end
end)

-----------------------------------------------------------------------
-- ВКЛАДКА «ГОСБАЗА» В СЛУЖЕБНЫХ КОМПЬЮТЕРАХ
-----------------------------------------------------------------------
--- Тот же самый /pcboard, только кнопкой: команда уходит на сервер
--  консольной командой, никакой второй реализации запроса нет.
function PB.AttachTab(sheet)
    if not IsValid(sheet) then return end

    local panel = vgui.Create("DPanel", sheet)
    panel:SetPaintBackground(false)
    panel:DockPadding(12, 12, 12, 12)

    local top = vgui.Create("DPanel", panel)
    top:Dock(TOP)
    top:SetTall(72)
    top.Paint = function(_, w, h)
        draw.RoundedBox(6, 0, 0, w, h, C.card)
        draw.SimpleText("ГОСУДАРСТВЕННАЯ БАЗА ДАННЫХ", "GRMPCB_Sub", 12, 8, C.gold)
        draw.SimpleText("Номер (ГР-1042), имя или «авто <номер>». Запрос виден окружающим как РП-действие.",
            "GRMPCB_Small", 12, 30, C.dim)
    end

    local row = vgui.Create("DPanel", top)
    row:Dock(BOTTOM)
    row:SetTall(30)
    row:DockMargin(10, 0, 10, 6)
    row:SetPaintBackground(false)

    local entry = vgui.Create("DTextEntry", row)
    entry:Dock(FILL)
    entry:SetPlaceholderText("ГР-1042 / Ганс Мюллер / авто АА-1234")

    local function query(text)
        text = string.Trim(tostring(text or ""))
        if text == "" then
            RunConsoleCommand("grm_pcboard")
        else
            RunConsoleCommand("grm_pcboard", unpack(string.Explode(" ", text)))
        end
    end

    local run = mkButton(row, "Пробить", C.accent)
    run:Dock(RIGHT)
    run:SetWide(120)
    run:DockMargin(6, 0, 0, 0)
    run.DoClick = function() query(entry:GetValue()) end
    entry.OnEnter = function() query(entry:GetValue()) end

    local mine = mkButton(row, "Моя карточка", C.card)
    mine:Dock(RIGHT)
    mine:SetWide(130)
    mine:DockMargin(6, 0, 0, 0)
    mine.DoClick = function() RunConsoleCommand("grm_pcboard", "я") end

    local logBtn = mkButton(row, "Журнал", C.card)
    logBtn:Dock(RIGHT)
    logBtn:SetWide(100)
    logBtn:DockMargin(6, 0, 0, 0)
    logBtn.DoClick = function() RunConsoleCommand("grm_pcboard", "журнал") end

    local scroll = vgui.Create("DScrollPanel", panel)
    scroll:Dock(FILL)
    scroll:DockMargin(0, 8, 0, 0)

    local function rebuild(card)
        scroll:Clear()
        if not istable(card) then
            local empty = vgui.Create("DLabel", scroll)
            empty:Dock(TOP)
            empty:SetTall(30)
            empty:SetFont("GRMPCB_Text")
            empty:SetTextColor(C.dim)
            empty:SetText("Справка появится здесь после запроса.")
            return
        end
        local head = vgui.Create("DPanel", scroll)
        head:Dock(TOP)
        head:SetTall(46)
        head:DockMargin(0, 0, 0, 8)
        head.Paint = function(_, w, h)
            draw.RoundedBox(6, 0, 0, w, h, C.card)
            draw.SimpleText(tostring(card.title or "—") .. "   " .. tostring(card.cid or ""),
                "GRMPCB_Sub", 12, 8, C.text)
            draw.SimpleText(tostring(card.levelName or "") .. " · " ..
                os.date("%d.%m.%Y %H:%M", card.time or os.time()), "GRMPCB_Small", 12, 28, C.dim)
        end
        for _, block in ipairs(card.blocks or {}) do
            local rows = block.rows or {}
            local pnl = vgui.Create("DPanel", scroll)
            pnl:Dock(TOP)
            pnl:DockMargin(0, 0, 0, 6)
            pnl:SetTall(28 + #rows * 20)
            pnl.Paint = function(_, w, h)
                draw.RoundedBox(6, 0, 0, w, h, C.card)
                draw.SimpleText(tostring(block.label), "GRMPCB_Sub", 12, 5, C.gold)
                for i, r in ipairs(rows) do
                    local y = 26 + (i - 1) * 20
                    draw.SimpleText(tostring(r[1]), "GRMPCB_Text", 16, y, C.dim)
                    draw.SimpleText(tostring(r[2]), "GRMPCB_Text", 240, y, C.text)
                end
            end
        end
    end
    rebuild(PB.LastCard)

    -- Пока окно терминала открыто, новая справка сама ложится во вкладку.
    hook.Add("GRM_PCBoardCard", panel, function(_, card) if IsValid(panel) then rebuild(card) end end)
    panel.OnRemove = function() hook.Remove("GRM_PCBoardCard", panel) end

    sheet:AddSheet("Госбаза", panel, "icon16/report_magnify.png")
    return panel
end

-----------------------------------------------------------------------
-- ВКЛАДКА «ГОСБАЗА» В /factions
-----------------------------------------------------------------------
--- Узел настроек: организация целиком или её отдел/подотдел/должность.
local function nodeOf(cfg, facName, field, key)
    cfg.factions = cfg.factions or {}
    local fac = cfg.factions[facName]
    if not fac then
        fac = { level = "none", blocks = {}, depts = {}, subs = {}, roles = {} }
        cfg.factions[facName] = fac
    end
    fac.blocks = fac.blocks or {}
    fac.depts, fac.subs, fac.roles = fac.depts or {}, fac.subs or {}, fac.roles or {}
    if not field then return fac end
    fac[field][key] = fac[field][key] or { blocks = {} }
    fac[field][key].blocks = fac[field][key].blocks or {}
    return fac[field][key]
end

--- Редактор доступов. parent = вкладка /factions (клики идут туда же, куда
-- и остальное меню) либо отдельный DFrame.
function PB.BuildAccessEditor(host, payload)
    if not IsValid(host) then return end
    local keep = PB._editorSel
    --[[ host бывает и вкладкой /factions, и собственным DFrame. Обычный
         :Clear() на DFrame сносил его кнопки закрытия/сворачивания, после
         чего PerformLayout окна каждый кадр звал у них SetPos — консоль
         заливало «dframe.lua:246: Tried to use a NULL Panel!». ]]
    if GRM.UI and GRM.UI.SafeClear then GRM.UI.SafeClear(host) else host:Clear() end
    payload = istable(payload) and payload or {}
    local cfg = istable(payload.config) and payload.config or { settings = {}, factions = {} }
    local tree = istable(payload.tree) and payload.tree or {}
    local blocks = istable(payload.blocks) and payload.blocks or {}
    cfg.settings = istable(cfg.settings) and cfg.settings or {}
    cfg.factions = istable(cfg.factions) and cfg.factions or {}

    local frame = vgui.Create("DPanel", host)
    frame:Dock(FILL)
    frame:DockMargin(0, 0, 0, 0)
    frame:SetPaintBackground(false)
    frame.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, C.bg)
        draw.RoundedBox(8, 0, 0, w, 56, C.card)
        draw.SimpleText("ГОСБАЗА: ДОСТУПЫ ПЛАНШЕТА /pcboard", "GRMPCB_Sub", 18, 10, C.gold)
        draw.SimpleText("Уровень задаётся организации, а отдел, подотдел и должность могут его переопределить.",
            "GRMPCB_Small", 18, 32, C.dim)
    end

    -- ── левая колонка: организации и узлы ──────────────────────────
    local left = vgui.Create("DPanel", frame)
    left:Dock(LEFT)
    left:SetWide(360)
    left:DockMargin(10, 62, 8, 118)
    left.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, C.card) end
    frame.PerformLayout = function(_, w)
        if IsValid(left) then left:SetWide(math.Clamp(math.floor((w or 800) * 0.32), 300, 480)) end
    end

    local facCombo = vgui.Create("DComboBox", left)
    facCombo:Dock(TOP)
    facCombo:DockMargin(8, 8, 8, 6)
    facCombo:SetTall(32)
    facCombo:SetValue("Организация…")

    local nodeList = vgui.Create("DScrollPanel", left)
    nodeList:Dock(FILL)
    nodeList:DockMargin(8, 0, 8, 8)

    -- ── правая колонка: уровень и блоки выбранного узла ────────────
    local right = vgui.Create("DPanel", frame)
    right:Dock(FILL)
    right:DockMargin(0, 62, 10, 118)
    right.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, C.card) end

    local title = vgui.Create("DLabel", right)
    title:Dock(TOP)
    title:DockMargin(12, 10, 12, 0)
    title:SetTall(24)
    title:SetFont("GRMPCB_Sub")
    title:SetTextColor(C.gold)
    title:SetText("Выберите организацию слева")

    local levelRow = vgui.Create("DPanel", right)
    levelRow:Dock(TOP)
    levelRow:DockMargin(12, 6, 12, 6)
    levelRow:SetTall(34)
    levelRow:SetPaintBackground(false)

    local levelLabel = vgui.Create("DLabel", levelRow)
    levelLabel:Dock(LEFT)
    levelLabel:SetWide(150)
    levelLabel:SetFont("GRMPCB_Text")
    levelLabel:SetTextColor(C.text)
    levelLabel:SetText("Уровень допуска")

    local levelCombo = vgui.Create("DComboBox", levelRow)
    levelCombo:Dock(FILL)
    levelCombo:SetTall(28)

    local blockScroll = vgui.Create("DScrollPanel", right)
    blockScroll:Dock(FILL)
    blockScroll:DockMargin(12, 4, 12, 10)

    local current = { fac = nil, field = nil, key = nil }

    local function levelChoices(withInherit)
        local out = {}
        if withInherit then out[#out + 1] = { id = "", name = "Наследовать" } end
        for _, id in ipairs(GRM.PCBoard.LevelOrder or {}) do
            out[#out + 1] = { id = id, name = GRM.PCBoard.LevelName(id) }
        end
        return out
    end

    local rebuildRight
    local function rebuildBlocks(node, level)
        blockScroll:Clear()
        local head = vgui.Create("DLabel", blockScroll)
        head:Dock(TOP)
        head:SetTall(24)
        head:SetFont("GRMPCB_Text")
        head:SetTextColor(C.dim)
        head:SetText("Блоки справки: «по уровню» — как задумано уровнем, иначе принудительно.")

        for _, def in ipairs(blocks) do
            local row = vgui.Create("DPanel", blockScroll)
            row:Dock(TOP)
            row:SetTall(34)
            row:DockMargin(0, 0, 0, 4)
            -- Провайдеры живут на сервере, поэтому «даёт ли уровень блок»
            -- считаем по присланной матрице, а не по локальному реестру.
            local levels = istable(def.levels) and def.levels or {}
            local byLevel = level == "admin" or levels[tostring(level or "none")] == true
            row.Paint = function(_, w, h)
                draw.RoundedBox(5, 0, 0, w, h, C.bg)
                draw.SimpleText(tostring(def.label), "GRMPCB_Text", 10, 9, C.text)
                draw.SimpleText(byLevel and "уровень даёт" or "уровень не даёт", "GRMPCB_Small",
                    w - 200, 11, byLevel and C.green or C.dim, TEXT_ALIGN_RIGHT)
            end
            local combo = vgui.Create("DComboBox", row)
            combo:Dock(RIGHT)
            combo:SetWide(180)
            combo:DockMargin(6, 4, 6, 4)
            local value = node.blocks[def.key]
            combo:AddChoice("По уровню", "default", value == nil)
            combo:AddChoice("Включить", "on", value == true)
            combo:AddChoice("Выключить", "off", value == false)
            if value == nil then combo:SetValue("По уровню")
            elseif value then combo:SetValue("Включить") else combo:SetValue("Выключить") end
            combo.OnSelect = function(_, _, _, id)
                if id == "on" then node.blocks[def.key] = true
                elseif id == "off" then node.blocks[def.key] = false
                else node.blocks[def.key] = nil end
            end
        end
    end

    local rebuildNodes

    rebuildRight = function()
        if not current.fac then return end
        local node = nodeOf(cfg, current.fac, current.field, current.key)
        local isRoot = current.field == nil
        title:SetText(isRoot and ("Организация: " .. current.fac)
            or (({ depts = "Отдел: ", subs = "Подотдел: ", roles = "Должность: " })[current.field] .. tostring(current.label or current.key)))

        levelCombo:Clear()
        local chosen = node.level
        for _, row in ipairs(levelChoices(not isRoot)) do
            levelCombo:AddChoice(row.name, row.id, (chosen or "") == row.id or (isRoot and chosen == nil and row.id == "none"))
        end
        levelCombo:SetValue(chosen and GRM.PCBoard.LevelName(chosen) or (isRoot and GRM.PCBoard.LevelName("none") or "Наследовать"))
        levelCombo._grmSilent = true
        levelCombo.OnSelect = function(_, _, value, id)
            if levelCombo._grmSilent then return end
            if id == nil then
                for _, row in ipairs(levelChoices(not isRoot)) do
                    if row.name == value then id = row.id break end
                end
            end
            id = tostring(id or "")
            if id == "" then node.level = nil else node.level = id end
            rebuildBlocks(node, id ~= "" and id or "none")
            if rebuildNodes then rebuildNodes() end
        end
        timer.Simple(0, function() if IsValid(levelCombo) then levelCombo._grmSilent = false end end)

        -- Для наследующего узла показываем итог по цепочке, а не «none».
        local effLevel = node.level
        if not effLevel then
            effLevel = select(1, GRM.PCBoard.ResolveAccess(current.fac,
                current.field == "depts" and current.key or "",
                current.field == "subs" and current.key or "",
                current.field == "roles" and current.key or "", cfg))
        end
        rebuildBlocks(node, effLevel)
    end

    rebuildNodes = function()
        nodeList:Clear()
        if not current.fac then return end
        local facRow
        for _, row in ipairs(tree) do if row.name == current.fac then facRow = row break end end
        if not facRow then return end

        local function addRow(label, field, key, keyLabel)
            local node = (field == nil) and (cfg.factions[current.fac] or {})
                or (((cfg.factions[current.fac] or {})[field] or {})[key] or {})
            local btn = vgui.Create("DButton", nodeList)
            btn:Dock(TOP)
            btn:SetTall(34)
            btn:DockMargin(0, 0, 0, 3)
            btn:SetText("")
            btn:SetTooltip(label)
            btn.Paint = function(self, w, h)
                local active = current.field == field and current.key == key
                draw.RoundedBox(5, 0, 0, w, h, active and C.accent or (self:IsHovered() and C.line or C.bg))
                local lvl = node.level
                local mark = lvl and ((GRM.PCBoard.Levels[lvl] or {}).short or lvl) or "насл."
                -- Названия отделов длинные: обрезаем по фактической ширине,
                -- чтобы имя не наезжало на метку уровня справа.
                surface.SetFont("GRMPCB_Small")
                local markW = (surface.GetTextSize(mark) or 0) + 18
                draw.SimpleText(elide(label, "GRMPCB_Text", w - markW - 16), "GRMPCB_Text", 10, 9, C.text)
                draw.SimpleText(mark, "GRMPCB_Small", w - 10, 11, lvl and C.gold or C.dim, TEXT_ALIGN_RIGHT)
            end
            btn.DoClick = function()
                current.field, current.key, current.label = field, key, keyLabel or label
                rebuildRight()
            end
        end

        addRow("ОРГАНИЗАЦИЯ ЦЕЛИКОМ", nil, nil)
        for _, dep in ipairs(facRow.departments or {}) do
            addRow("Отдел: " .. tostring(dep.display or dep.key), "depts", dep.key, dep.display)
        end
        for _, sub in ipairs(facRow.subdepartments or {}) do
            addRow("Подотдел: " .. tostring(sub.display or sub.key), "subs", sub.key, sub.display)
        end
        for _, role in ipairs(facRow.roles or {}) do
            addRow("Должность: " .. tostring(role.display or role.key), "roles", role.key, role.display)
        end
    end

    table.sort(tree, function(a, b)
        return string.lower(tostring(a.display or a.name or "")) < string.lower(tostring(b.display or b.name or ""))
    end)
    if #tree == 0 then
        local empty = vgui.Create("DLabel", nodeList)
        empty:Dock(TOP)
        empty:SetTall(48)
        empty:SetWrap(true)
        empty:SetFont("GRMPCB_Small")
        empty:SetTextColor(C.dim)
        empty:SetText("Список организаций пуст. Откройте /factions и создайте организацию, затем нажмите «Обновить».")
    end
    for _, row in ipairs(tree) do
        local id = tostring(row.name or row.display or "")
        if id ~= "" then
            facCombo:AddChoice(tostring(row.display or id), id)
        end
    end
    -- GMod зовёт OnSelect(index, value, data). Четвёртый аргумент бывает nil.
    facCombo._grmSilent = true
    facCombo.OnSelect = function(_, _, value, data)
        if facCombo._grmSilent then return end
        local name = tostring(data or value or "")
        if name == "" or name == "Организация…" then return end
        current.fac, current.field, current.key, current.label = name, nil, nil, nil
        PB._editorSel = { fac = name }
        nodeOf(cfg, name)
        rebuildNodes()
        rebuildRight()
    end
    local startFac
    if keep and keep.fac then
        for _, row in ipairs(tree) do
            if tostring(row.name) == tostring(keep.fac) then startFac = keep.fac break end
        end
    end
    if not startFac and tree[1] then startFac = tostring(tree[1].name or tree[1].display or "") end
    if startFac and startFac ~= "" then
        local disp = startFac
        for _, row in ipairs(tree) do
            if tostring(row.name) == startFac then disp = tostring(row.display or row.name) break end
        end
        facCombo:SetValue(disp)
        current.fac = startFac
        current.field, current.key, current.label = keep and keep.field, keep and keep.key, keep and keep.label
        nodeOf(cfg, startFac)
        rebuildNodes()
        rebuildRight()
    end
    timer.Simple(0, function() if IsValid(facCombo) then facCombo._grmSilent = false end end)

    -- Низ двумя рядами: поля не дерутся с кнопками.
    local bottom = vgui.Create("DPanel", frame)
    bottom:Dock(BOTTOM)
    bottom:SetTall(108)
    bottom:DockMargin(10, 0, 10, 10)
    bottom.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, C.card) end

    local settings = vgui.Create("DPanel", bottom)
    settings:Dock(TOP)
    settings:SetTall(56)
    settings:SetPaintBackground(false)

    local actions = vgui.Create("DPanel", bottom)
    actions:Dock(FILL)
    actions:DockMargin(0, 0, 0, 0)
    actions:SetPaintBackground(false)

    local s = cfg.settings
    local function numField(label, field, minv, maxv)
        local wrap = vgui.Create("DPanel", settings)
        wrap:Dock(LEFT)
        wrap:SetWide(168)
        wrap:DockMargin(10, 8, 6, 4)
        wrap.Paint = function(_, w, h)
            draw.RoundedBox(5, 0, 0, w, h, C.bg)
            draw.SimpleText(label, "GRMPCB_Small", 8, 4, C.dim)
        end
        local num = vgui.Create("DNumberWang", wrap)
        num:Dock(BOTTOM)
        num:SetTall(22)
        num:DockMargin(8, 0, 8, 5)
        num:SetMinMax(minv, maxv)
        num:SetValue(tonumber(s[field]) or minv)
        num.OnValueChanged = function(_, v) s[field] = v end
        return num
    end
    numField("Кулдаун, с", "cooldown", 0, 300)
    numField("Запросов в минуту", "perMinute", 1, 60)
    numField("Время пробития, с", "delay", 0, 30)

    local function checkField(label, get, set, width)
        local wrap = vgui.Create("DPanel", settings)
        wrap:Dock(LEFT)
        wrap:SetWide(width)
        wrap:DockMargin(4, 8, 6, 4)
        wrap.Paint = function(_, w, h) draw.RoundedBox(5, 0, 0, w, h, C.bg) end
        local chk = vgui.Create("DCheckBoxLabel", wrap)
        chk:Dock(FILL)
        chk:DockMargin(10, 0, 8, 0)
        chk:SetFont("GRMPCB_Text")
        chk:SetText(label)
        chk:SetTextColor(C.text)
        chk:SetValue(get() and 1 or 0)
        chk.OnChange = function(_, v)
            clickSnd("click")
            set(v)
        end
        return chk
    end
    checkField("Только на службе", function() return s.requireDuty ~= false end,
        function(v) s.requireDuty = v end, 176)
    checkField("Скрытый запрос спецслужбам", function() return s.allowHidden ~= false end,
        function(v) s.allowHidden = v end, 240)

    local save = mkButton(actions, "Сохранить", C.green)
    save:Dock(RIGHT)
    save:SetWide(168)
    save:DockMargin(8, 8, 12, 10)
    save.DoClick = function()
        net.Start(PB.Net.SAVE)
        net.WriteTable(cfg)
        net.SendToServer()
    end

    local refresh = mkButton(actions, "Обновить", C.accent)
    refresh:Dock(RIGHT)
    refresh:SetWide(132)
    refresh:DockMargin(8, 8, 0, 10)
    refresh.DoClick = function()
        PB.RequestAccessMenu(not IsValid(PB._accessHost) and IsValid(PB._accessFrame))
    end

    local hint = vgui.Create("DLabel", actions)
    hint:Dock(FILL)
    hint:DockMargin(14, 10, 8, 10)
    hint:SetWrap(true)
    hint:SetFont("GRMPCB_Small")
    hint:SetTextColor(C.dim)
    hint:SetContentAlignment(4)
    hint:SetText("Изменения применяются только после «Сохранить».")
end

--[[ ОТКУДА БРАЛОСЬ ОКНО ГОСБАЗЫ ПРИ ЗАКРЫТИИ /factions (находка 27.08).

     Вкладка «Госбаза» внутри меню организаций при создании сразу просит у
     сервера снимок допусков. Ответ приходит на кадр-другой позже. Если за
     это время меню закрыли, панель вкладки уже уничтожена — и обработчик,
     не найдя её, услужливо открывал ОТДЕЛЬНОЕ полноэкранное окно. Со
     стороны это выглядело так: закрываешь фракции — выскакивает /pcboard.
     Тот же эффект давал ответ сервера после «Сохранить».

     Теперь ответ знает, чего от него ждали: снимок для встроенной вкладки
     НИКОГДА не открывает своё окно. Отдельное окно появляется только по
     явной команде игрока (grm_pcboard_access или кнопка «Обновить» в нём). ]]
function PB.OpenAccessMenu(payload, wantWindow)
    if IsValid(PB._accessHost) then
        PB.BuildAccessEditor(PB._accessHost, payload)
        return
    end
    -- Окно просили? Если снимок был для вкладки, а вкладки уже нет — молчим.
    if wantWindow ~= true and not IsValid(PB._accessFrame) then return end
    if IsValid(PB._accessFrame) then PB._accessFrame:Remove() end
    local wrap = vgui.Create("DFrame")
    PB._accessFrame = wrap
    local w = math.Clamp(math.floor(ScrW() * 0.86), 1020, 1900)
    local h = math.Clamp(math.floor(ScrH() * 0.88), 700, 1200)
    wrap:SetSize(w, h)
    wrap:SetMinWidth(1020)
    wrap:SetMinHeight(700)
    wrap:SetSizable(true)
    wrap:Center()
    wrap:SetTitle("Госбаза /pcboard")
    wrap:MakePopup()
    wrap:DoModal()
    wrap:MoveToFront()
    wrap:SetKeyboardInputEnabled(true)
    wrap:SetMouseInputEnabled(true)
    PB.BuildAccessEditor(wrap, payload)
end

net.Receive(PB.Net.DATA, function()
    local payload = net.ReadTable()
    if not istable(payload) then return end
    -- Флаг ставит тот, кто запрашивал снимок, и сбрасывается он здесь же.
    local wantWindow = PB._wantWindow == true
    PB._wantWindow = nil
    PB.OpenAccessMenu(payload, wantWindow)
end)

--- wantWindow = true только для явного вызова игроком.
function PB.RequestAccessMenu(wantWindow)
    PB._wantWindow = wantWindow == true
    net.Start(PB.Net.REQ)
    net.SendToServer()
end
concommand.Add("grm_pcboard_access", function() PB.RequestAccessMenu(true) end)

local function installTab(sheet)
    if not IsValid(sheet) then return end
    local lp = LocalPlayer()
    if not (IsValid(lp) and lp:IsSuperAdmin()) then return end

    local panel = vgui.Create("DPanel")
    panel:SetPaintBackground(false)
    PB._accessHost = panel
    panel.OnRemove = function()
        if PB._accessHost == panel then PB._accessHost = nil end
    end

    local wait = vgui.Create("DLabel", panel)
    wait:Dock(FILL)
    wait:SetFont("GRMPCB_Text")
    wait:SetTextColor(C.dim)
    wait:SetContentAlignment(5)
    wait:SetText("Загрузка допусков госбазы…")

    timer.Simple(0, function()
        if IsValid(panel) then PB.RequestAccessMenu(false) end
    end)

    sheet:AddSheet("Госбаза", panel, "icon16/report_magnify.png")
end
hook.Add("GRM_FactionsAdmin_BuildTabs", "GRM_PCBoard_Tab", installTab)

print("[GRM PCBoard] UI v1.0.0 loaded")
