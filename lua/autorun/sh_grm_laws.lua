--[[--------------------------------------------------------------------
    GRM Laws System v2.0.0 — законодательство по разделам

    Заказ владельца (19.08): разделы (общие, уголовные, административные,
    воинские, экономические), удобный редактор для лиц с доступом, единый
    стиль GRM, синхронизация частями и приоритетный старт.

    ЧТО НОВОГО ПРОТИВ v1.2:
      • Категории законов и вкладки по ним, счётчики в боковом меню.
      • Статья: номер, заголовок, текст, наказание — раньше был просто текст.
      • Редактор прямо в окне (без Derma_StringRequest): выбор категории,
        поля статьи и наказания, многострочный текст, кнопки сохранения.
      • Список уходит клиенту ЧАСТЯМИ через GRM.Net.Stream (кодекс на сотню
        статей — это десятки килобайт одним пакетом).
      • Загрузка через GRM.Boot (приоритет normal), права — через
        GRM.Admin (право laws.edit) с сохранением прежних проверок.
      • Старые записи мигрируют: текст остаётся, категория «Общие»,
        заголовок берётся из первой строки.

    Команды: /laws, /законы, /закон, консоль grm_laws
----------------------------------------------------------------------]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Laws = GRM.Laws or {}
local LAWS = GRM.Laws

LAWS.Version      = "2.0.0"
LAWS.ConfigFile   = "grm_laws.json"
LAWS.MaxLaws      = 400
LAWS.MaxLawLength = 2000

-- Разделы кодекса. Порядок задаёт порядок вкладок.
LAWS.Categories = {
    { id = "general",        name = "Общие положения",     color = { r = 245, g = 195, b = 65  } },
    { id = "criminal",       name = "Уголовные",           color = { r = 225, g = 70,  b = 70  } },
    { id = "administrative", name = "Административные",    color = { r = 65,  g = 145, b = 235 } },
    { id = "military",       name = "Воинские",            color = { r = 120, g = 170, b = 90  } },
    { id = "economic",       name = "Экономические",       color = { r = 75,  g = 195, b = 170 } },
}

function LAWS.CategoryName(id)
    for _, cat in ipairs(LAWS.Categories) do
        if cat.id == id then return cat.name end
    end
    return "Общие положения"
end

function LAWS.CategoryColor(id)
    for _, cat in ipairs(LAWS.Categories) do
        if cat.id == id then return Color(cat.color.r, cat.color.g, cat.color.b) end
    end
    return Color(245, 195, 65)
end

function LAWS.ValidCategory(id)
    id = tostring(id or "")
    for _, cat in ipairs(LAWS.Categories) do
        if cat.id == id then return id end
    end
    return "general"
end

local function jsonT(raw)
    if not raw or raw == "" then return nil end
    local ok, tbl = pcall(util.JSONToTable, raw, false, true)
    if ok and istable(tbl) then return tbl end
    ok, tbl = pcall(util.JSONToTable, raw)
    if ok and istable(tbl) then return tbl end
    return nil
end

local function cleanText(s)
    s = tostring(s or "")
    if string.Trim then s = string.Trim(s) end
    s = s:gsub("\r\n", "\n"):gsub("\r", "\n")
    return s
end

-- Заголовок из первой строки текста — для миграции старых записей.
local function titleFromText(text)
    local first = string.match(tostring(text or ""), "^([^\n]+)") or ""
    first = string.Trim(first)
    if #first > 64 then first = string.sub(first, 1, 61) .. "…" end
    return first ~= "" and first or "Без названия"
end

local function normalizeData(tbl)
    local out = {}
    if not istable(tbl) then return out end

    local rows = istable(tbl.laws) and tbl.laws or tbl
    for _, law in ipairs(rows) do
        if istable(law) then
            local text = cleanText(law.text)
            if text ~= "" then
                out[#out + 1] = {
                    id        = math.max(1, math.floor(tonumber(law.id) or (#out + 1))),
                    category  = LAWS.ValidCategory(law.category),
                    article   = string.sub(tostring(law.article or ""), 1, 24),
                    title     = string.sub(cleanText(law.title) ~= "" and cleanText(law.title) or titleFromText(text), 1, 96),
                    text      = text:sub(1, LAWS.MaxLawLength),
                    penalty   = string.sub(cleanText(law.penalty or ""), 1, 200),
                    author    = tostring(law.author or "Система"),
                    date      = tostring(law.date or ""),
                    timestamp = tonumber(law.timestamp) or os.time(),
                    updatedBy = tostring(law.updatedBy or ""),
                    updated   = tonumber(law.updated) or 0,
                }
            end
        end
    end

    table.sort(out, function(a, b)
        if a.category == b.category then return (tonumber(a.id) or 0) < (tonumber(b.id) or 0) end
        return a.category < b.category
    end)
    return out
end

local function nextLawID()
    local maxID = 0
    for _, law in ipairs(LAWS.Data or {}) do
        maxID = math.max(maxID, math.floor(tonumber(law.id) or 0))
    end
    return maxID + 1
end

function LAWS.Load()
    if not file.Exists(LAWS.ConfigFile, "DATA") then
        LAWS.Data = {}
        return LAWS.Data
    end
    LAWS.Data = normalizeData(jsonT(file.Read(LAWS.ConfigFile, "DATA")) or {})
    return LAWS.Data
end

function LAWS.Save()
    LAWS.Data = normalizeData(LAWS.Data or {})
    local ok, raw = pcall(util.TableToJSON, { version = 2, laws = LAWS.Data }, true)
    if not ok or not isstring(raw) then return false end
    file.Write(LAWS.ConfigFile, raw)
    return true
end

function LAWS.GetAll()
    if not LAWS.Data then LAWS.Load() end
    return LAWS.Data or {}
end

function LAWS.ByCategory(category)
    local out = {}
    for _, law in ipairs(LAWS.GetAll()) do
        if law.category == category then out[#out + 1] = law end
    end
    return out
end

function LAWS.Get(lawID)
    lawID = math.floor(tonumber(lawID) or 0)
    for i, law in ipairs(LAWS.GetAll()) do
        if math.floor(tonumber(law.id) or 0) == lawID then return law, i end
    end
    return nil
end

--[[ Создание статьи. data: { category, article, title, text, penalty } ]]
function LAWS.Add(authorName, data)
    if not LAWS.Data then LAWS.Load() end
    data = istable(data) and data or { text = tostring(data or "") }

    local text = cleanText(data.text)
    if #LAWS.Data >= LAWS.MaxLaws then
        return false, "Достигнут лимит статей (" .. LAWS.MaxLaws .. ")"
    end
    if #text < 10 then return false, "Текст статьи слишком короткий (минимум 10 символов)" end
    if #text > LAWS.MaxLawLength then
        return false, "Текст статьи слишком длинный (максимум " .. LAWS.MaxLawLength .. ")"
    end

    local law = {
        id        = nextLawID(),
        category  = LAWS.ValidCategory(data.category),
        article   = string.sub(cleanText(data.article or ""), 1, 24),
        title     = string.sub(cleanText(data.title or "") ~= "" and cleanText(data.title) or titleFromText(text), 1, 96),
        text      = text,
        penalty   = string.sub(cleanText(data.penalty or ""), 1, 200),
        author    = tostring(authorName or "Система"),
        date      = os.date("%d.%m.%Y %H:%M"),
        timestamp = os.time(),
    }
    table.insert(LAWS.Data, law)
    LAWS.Save()
    return true, law
end

function LAWS.Edit(lawID, data, editorName)
    if not LAWS.Data then LAWS.Load() end
    local law = LAWS.Get(lawID)
    if not law then return false, "Статья не найдена" end
    data = istable(data) and data or {}

    local text = cleanText(data.text or law.text)
    if #text < 10 then return false, "Текст статьи слишком короткий (минимум 10 символов)" end
    if #text > LAWS.MaxLawLength then
        return false, "Текст статьи слишком длинный (максимум " .. LAWS.MaxLawLength .. ")"
    end

    law.category = LAWS.ValidCategory(data.category or law.category)
    law.article  = string.sub(cleanText(data.article or law.article or ""), 1, 24)
    law.title    = string.sub(cleanText(data.title or law.title or "") ~= "" and cleanText(data.title or law.title) or titleFromText(text), 1, 96)
    law.text     = text
    law.penalty  = string.sub(cleanText(data.penalty or law.penalty or ""), 1, 200)
    law.updated  = os.time()
    law.updatedBy = tostring(editorName or law.updatedBy or "")

    LAWS.Save()
    return true, law
end

function LAWS.Remove(lawID)
    if not LAWS.Data then LAWS.Load() end
    local law, index = LAWS.Get(lawID)
    if not law then return false, "Статья не найдена" end
    table.remove(LAWS.Data, index)
    LAWS.Save()
    return true
end

-----------------------------------------------------------------------
-- СЕРВЕР
-----------------------------------------------------------------------
if SERVER then
    util.AddNetworkString("GRM_Laws_Open")
    util.AddNetworkString("GRM_Laws_List")
    util.AddNetworkString("GRM_Laws_Action")
    util.AddNetworkString("GRM_Laws_Refresh")
    util.AddNetworkString("GRM_Laws_Result")
    util.AddNetworkString("GRM_Laws_Changed")

    -- Право на правку кодекса: суперадмин, доступ фракции или право
    -- админ-платформы. Регистрируем его, чтобы суперадмин мог выдать
    -- «законотворчество» нужной группе без правки кода.
    if GRM.Admin and GRM.Admin.RegisterPerm then
        --[[ 21.08. Было minAccess = "admin": право автоматически получала
             ЛЮБАЯ группа с флагом admin (включая модераторов) и любой
             engine-админ. Отсюда кнопки «Опубликовать» у людей, которым
             законотворчество не выдавали. Теперь право только у суперадмина
             и у тех, кому его выдали явно — группой или должностью во
             фракции (law_publish / law_remove). ]]
        GRM.Admin.RegisterPerm("laws.edit", {
            label = "Правка законодательства", category = "Документы",
            minAccess = "superadmin", desc = "Создание, изменение и удаление статей кодекса",
        })
        GRM.Admin.RegisterPerm("laws.remove", {
            label = "Удаление статей кодекса", category = "Документы",
            minAccess = "superadmin", desc = "Удаление опубликованных статей",
        })
    end

    local function canEdit(ply)
        if not IsValid(ply) then return false end
        if ply:IsSuperAdmin() then return true end
        if GRM.FactionEconomy and GRM.FactionEconomy.CanPublishLaws then
            if GRM.FactionEconomy.CanPublishLaws(ply) == true then return true end
        end
        if GRM.Admin and GRM.Admin.Can then return GRM.Admin.Can(ply, "laws.edit") == true end
        return false
    end

    local function canRemove(ply)
        if not IsValid(ply) then return false end
        if ply:IsSuperAdmin() then return true end
        if GRM.FactionEconomy and GRM.FactionEconomy.HasAccess then
            if GRM.FactionEconomy.HasAccess(ply, "law_remove") == true then return true end
        end
        if GRM.Admin and GRM.Admin.Can and GRM.Admin.Can(ply, "laws.remove") == true then return true end
        -- Право публиковать больше НЕ означает право удалять: удаление статьи
        -- закрывается отдельной галочкой (law_remove).
        return false
    end
    LAWS.CanEdit, LAWS.CanRemove = canEdit, canRemove

    local function result(ply, ok, message)
        if not IsValid(ply) then return end
        net.Start("GRM_Laws_Result")
            net.WriteBool(ok == true)
            net.WriteString(tostring(message or ""))
        net.Send(ply)
    end

    -- Кто сейчас смотрит кодекс: только им шлём обновления.
    LAWS.Viewers = LAWS.Viewers or {}

    --[[ Кодекс уходит ЧАСТЯМИ: сотня статей по 2000 символов — это десятки
         килобайт, и одним пакетом они занимают канал целиком. ]]
    function LAWS.SendList(ply)
        if not IsValid(ply) then return end
        local payload = {
            laws = LAWS.GetAll(),
            canEdit = canEdit(ply),
            canRemove = canRemove(ply),
        }

        if GRM.Net and GRM.Net.Stream then
            if GRM.Net.Stream("laws.list", payload, { ply }, { chunk = 6144, interval = 0.05 }) then return end
        end

        net.Start("GRM_Laws_List")
            net.WriteTable(payload)
        net.Send(ply)
    end

    function LAWS.AskClientOpen(ply)
        if not IsValid(ply) then return end
        LAWS.Viewers[ply] = true
        net.Start("GRM_Laws_Open")
        net.Send(ply)
        -- Список идёт следом: окно успеет создаться и примет данные.
        timer.Simple(0.1, function() if IsValid(ply) then LAWS.SendList(ply) end end)
    end

    --[[ Обновление кодекса.

         Раньше свежий список уходил ТОЛЬКО тем, кого сервер считал
         «зрителями». Список зрителей живёт в памяти и легко расходится с
         реальностью: игрок переподключился, окно открылось из другого места,
         сервер перезагрузил модуль — и человек сидит со старым кодексом,
         не понимая, почему правки не видны.

         Теперь помимо адресной рассылки уходит крошечный сигнал ВСЕМ:
         «кодекс изменился». У кого окно открыто — сам попросит свежий
         список, у кого закрыто — сигнал ничего не стоит. ]]
    function LAWS.BroadcastUpdate()
        for ply in pairs(LAWS.Viewers) do
            if IsValid(ply) then LAWS.SendList(ply) else LAWS.Viewers[ply] = nil end
        end

        net.Start("GRM_Laws_Changed")
        net.Broadcast()
    end

    -- Запрос на открытие приходит и из чата, и из контекстного меню (Q):
    -- отвечаем командой открыть окно и сразу шлём кодекс.
    net.Receive("GRM_Laws_Open", function(_, ply)
        if not IsValid(ply) then return end
        LAWS.Viewers[ply] = true
        LAWS.AskClientOpen(ply)
    end)

    net.Receive("GRM_Laws_Refresh", function(_, ply)
        if not IsValid(ply) then return end
        LAWS.Viewers[ply] = true
        LAWS.SendList(ply)
    end)

    net.Receive("GRM_Laws_Action", function(bits, ply)
        if not IsValid(ply) then return end
        if GRM.Net and GRM.Net.Guard and not GRM.Net.Guard(ply, "laws.action", { rate = 0.5, burst = 4, maxBits = 32768 }, { bits = bits }) then return end

        local op = net.ReadString()
        local id = net.ReadUInt(16)
        local data = net.ReadTable() or {}

        if op == "add" then
            if not canEdit(ply) then result(ply, false, "Нет права публиковать законы") return end
            local ok, lawOrErr = LAWS.Add(ply:Nick(), data)
            if not ok then result(ply, false, tostring(lawOrErr)) return end
            if GRM.Audit and GRM.Audit.Write then
                GRM.Audit.Write("laws", "add", ply, { id = lawOrErr.id }, { category = lawOrErr.category, title = lawOrErr.title })
            end
            result(ply, true, "Статья опубликована")

        elseif op == "edit" then
            if not canEdit(ply) then result(ply, false, "Нет права изменять законы") return end
            local ok, err = LAWS.Edit(id, data, ply:Nick())
            if not ok then result(ply, false, tostring(err)) return end
            if GRM.Audit and GRM.Audit.Write then
                GRM.Audit.Write("laws", "edit", ply, { id = id }, { category = data.category })
            end
            result(ply, true, "Статья обновлена")

        elseif op == "remove" then
            if not canRemove(ply) then result(ply, false, "Нет права удалять законы") return end
            local ok, err = LAWS.Remove(id)
            if not ok then result(ply, false, tostring(err)) return end
            if GRM.Audit and GRM.Audit.Write then GRM.Audit.Write("laws", "remove", ply, { id = id }, {}) end
            result(ply, true, "Статья удалена")

        else
            return
        end

        LAWS.BroadcastUpdate()
    end)

    hook.Add("PlayerDisconnected", "GRM_Laws_DropViewer", function(ply)
        if LAWS.Viewers then LAWS.Viewers[ply] = nil end
    end)

    local function chatOpen(ply, text)
        local cmd = string.lower(string.Trim(tostring(text or "")))
        if cmd == "/laws" or cmd == "!laws" or cmd == "/закон" or cmd == "/законы" then
            LAWS.AskClientOpen(ply)
            return true
        end
        return false
    end

    hook.Add("PlayerSay", "GRM_Laws_Chat", function(ply, text)
        if chatOpen(ply, text) then return "" end
    end)
    hook.Add("PlayerSayTransform", "GRM_Laws_ChatTr", function(ply, pack)
        if not istable(pack) or not isstring(pack[1]) then return end
        if chatOpen(ply, pack[1]) then
            pack[1] = ""
            pack.SkipPlayerSay = true
        end
    end)

    concommand.Add("grm_laws", function(ply) LAWS.AskClientOpen(ply) end)

    if GRM.Boot and GRM.Boot.OnMapStart then
        GRM.Boot.OnMapStart("GRM_Laws_Load", "normal", function() LAWS.Load() end)
    else
        hook.Add("InitPostEntity", "GRM_Laws_Load", function() LAWS.Load() end)
    end
end

-----------------------------------------------------------------------
-- КЛИЕНТ
-----------------------------------------------------------------------
if CLIENT then
    surface.CreateFont("GRMLaw_Title",  { font = "Roboto", size = 21, weight = 800, extended = true })
    surface.CreateFont("GRMLaw_Sub",    { font = "Roboto", size = 15, weight = 700, extended = true })
    surface.CreateFont("GRMLaw_Body",   { font = "Roboto", size = 14, weight = 500, extended = true })
    surface.CreateFont("GRMLaw_Btn",    { font = "Roboto", size = 13, weight = 600, extended = true })
    surface.CreateFont("GRMLaw_Small",  { font = "Roboto", size = 11, weight = 500, extended = true })

    local C = {
        bg        = Color(16, 20, 28, 252),
        sidebar   = Color(12, 15, 22, 255),
        card      = Color(22, 28, 38, 240),
        cardHover = Color(36, 46, 62, 240),
        cardLight = Color(28, 36, 48, 240),
        border    = Color(38, 48, 66, 200),
        accent    = Color(65, 145, 235),
        gold      = Color(245, 195, 65),
        green     = Color(55, 185, 110),
        red       = Color(225, 70, 70),
        text      = Color(240, 244, 250),
        dim       = Color(155, 170, 190),
    }

    local state = { laws = {}, canEdit = false, canRemove = false }
    local frame, listPanel, editorPanel, currentCategory, currentLaw, searchBox
    local rebuildList, buildEditor

    local function btn(parent, label, col, fn)
        local b = vgui.Create("DButton", parent)
        b:SetText("")
        b.Paint = function(self, w, h)
            local c = col or C.accent
            if self:IsHovered() then c = Color(math.min(255, c.r + 22), math.min(255, c.g + 22), math.min(255, c.b + 22)) end
            draw.RoundedBox(6, 0, 0, w, h, c)
            draw.SimpleText(label, "GRMLaw_Btn", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        b.DoClick = function() surface.PlaySound("buttons/button15.wav") if fn then fn() end end
        return b
    end

    local function entry(parent, placeholder, multiline)
        local e = vgui.Create("DTextEntry", parent)
        e:SetFont("GRMLaw_Body")
        e:SetTextColor(C.text)
        if placeholder then e:SetPlaceholderText(placeholder) end
        if multiline then e:SetMultiline(true) end
        e.Paint = function(self, w, h)
            draw.RoundedBox(5, 0, 0, w, h, C.cardLight)
            surface.SetDrawColor(C.border)
            surface.DrawOutlinedRect(0, 0, w, h)
            self:DrawTextEntryText(C.text, C.accent, C.text)
            if self:GetText() == "" and self.GetPlaceholderText and self:GetPlaceholderText() then
                draw.SimpleText(self:GetPlaceholderText(), "GRMLaw_Small", 8, multiline and 10 or h / 2,
                    C.dim, TEXT_ALIGN_LEFT, multiline and TEXT_ALIGN_TOP or TEXT_ALIGN_CENTER)
            end
        end
        return e
    end

    local function sendAction(op, id, data)
        net.Start("GRM_Laws_Action")
            net.WriteString(op)
            net.WriteUInt(math.max(0, math.floor(tonumber(id) or 0)), 16)
            net.WriteTable(istable(data) and data or {})
        net.SendToServer()
    end

    -- ── Список статей ────────────────────────────────────────────────
    rebuildList = function()
        if not IsValid(listPanel) then return end
        listPanel:Clear()

        local query = IsValid(searchBox) and string.lower(string.Trim(searchBox:GetValue() or "")) or ""
        local shown = 0

        for _, law in ipairs(state.laws) do
            local inCategory = (currentCategory == "all") or (law.category == currentCategory)
            local hay = string.lower(tostring(law.title or "") .. " " .. tostring(law.text or "") .. " " ..
                tostring(law.article or "") .. " " .. tostring(law.penalty or ""))
            if inCategory and (query == "" or string.find(hay, query, 1, true)) then
                shown = shown + 1

                local card = vgui.Create("DPanel", listPanel)
                card:Dock(TOP)
                card:DockMargin(0, 0, 6, 6)
                card:SetTall(96)

                local col = LAWS.CategoryColor(law.category)
                card.Paint = function(self, w, h)
                    local active = currentLaw and currentLaw.id == law.id
                    draw.RoundedBox(8, 0, 0, w, h, active and C.cardHover or C.card)
                    draw.RoundedBox(8, 0, 0, 4, h, col)
                    surface.SetDrawColor(C.border)
                    surface.DrawOutlinedRect(0, 0, w, h)

                    local head = (law.article ~= "" and ("Ст. " .. law.article .. " · ") or "") .. tostring(law.title or "")
                    draw.SimpleText(head, "GRMLaw_Sub", 16, 12, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                    draw.SimpleText(LAWS.CategoryName(law.category), "GRMLaw_Small", w - 14, 14, col, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)

                    local body = tostring(law.text or ""):gsub("\n", " ")
                    if #body > 150 then body = string.sub(body, 1, 147) .. "…" end
                    draw.SimpleText(body, "GRMLaw_Body", 16, 36, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

                    if tostring(law.penalty or "") ~= "" then
                        draw.SimpleText("Наказание: " .. law.penalty, "GRMLaw_Small", 16, 60, C.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                    end
                    draw.SimpleText(tostring(law.author or "") .. "  ·  " .. tostring(law.date or ""),
                        "GRMLaw_Small", 16, 76, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                end

                card:SetCursor("hand")
                card.OnMousePressed = function()
                    currentLaw = law
                    buildEditor()
                    rebuildList()
                end
            end
        end

        if shown == 0 then
            local empty = vgui.Create("DPanel", listPanel)
            empty:Dock(TOP) empty:SetTall(80)
            empty.Paint = function(_, w, h)
                draw.RoundedBox(8, 0, 0, w, h, C.card)
                draw.SimpleText(query ~= "" and "Ничего не найдено" or "В этом разделе пока нет статей",
                    "GRMLaw_Body", w / 2, h / 2, C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end
    end

    -- ── Редактор / просмотр ──────────────────────────────────────────
    buildEditor = function()
        if not IsValid(editorPanel) then return end
        editorPanel:Clear()

        local law = currentLaw
        if not law and not state.canEdit then
            local hint = vgui.Create("DPanel", editorPanel)
            hint:Dock(FILL)
            hint.Paint = function(_, w, h)
                draw.RoundedBox(8, 0, 0, w, h, C.card)
                draw.SimpleText("Выберите статью слева", "GRMLaw_Body", w / 2, h / 2, C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            return
        end

        law = law or { id = 0, category = currentCategory ~= "all" and currentCategory or "general",
            article = "", title = "", text = "", penalty = "" }

        local head = vgui.Create("DPanel", editorPanel)
        head:Dock(TOP) head:SetTall(34) head:SetPaintBackground(false)
        head.Paint = function(_, w, h)
            draw.SimpleText(law.id > 0 and ("СТАТЬЯ #" .. law.id) or "НОВАЯ СТАТЬЯ",
                "GRMLaw_Sub", 2, h / 2, C.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            if law.id > 0 and tostring(law.updatedBy or "") ~= "" then
                draw.SimpleText("правил: " .. law.updatedBy, "GRMLaw_Small", w - 2, h / 2, C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end
        end

        local editable = state.canEdit

        --[[ Режим просмотра: показываем статью текстом, без единого поля
             ввода и без кнопок. Раньше зритель видел «редактор» с
             заблокированными полями — выглядело как «кнопки есть, но не
             работают». ]]
        if not editable then
            local view = vgui.Create("DScrollPanel", editorPanel)
            view:Dock(FILL)

            local function line(text, font, col, tall)
                local lbl = vgui.Create("DLabel", view)
                lbl:Dock(TOP) lbl:DockMargin(0, 0, 0, 6)
                lbl:SetFont(font or "GRMLaw_Body") lbl:SetTextColor(col or C.text)
                lbl:SetWrap(true) lbl:SetAutoStretchVertical(true)
                lbl:SetTall(tall or 20) lbl:SetText(tostring(text or ""))
                return lbl
            end

            local catName = law.category
            for _, cat in ipairs(LAWS.Categories) do
                if cat.id == law.category then catName = cat.name break end
            end
            line("Раздел: " .. tostring(catName), "GRMLaw_Small", C.dim)
            line(tostring(law.article or "") ~= "" and ("Статья " .. law.article) or "Статья", "GRMLaw_Sub", C.gold)
            line(tostring(law.title or ""), "GRMLaw_Sub", C.text)
            line(tostring(law.text or ""), "GRMLaw_Body", C.text)
            if tostring(law.penalty or "") ~= "" then
                line("Наказание: " .. law.penalty, "GRMLaw_Body", C.red)
            end
            line("Правка кодекса доступна только уполномоченным должностям.", "GRMLaw_Small", C.dim)
            return
        end

        local catCombo = vgui.Create("DComboBox", editorPanel)
        catCombo:Dock(TOP) catCombo:SetTall(28) catCombo:DockMargin(0, 0, 0, 6)
        catCombo:SetFont("GRMLaw_Body") catCombo:SetTextColor(C.text)
        catCombo.Paint = function(_, w, h)
            draw.RoundedBox(5, 0, 0, w, h, C.cardLight)
            surface.SetDrawColor(C.border)
            surface.DrawOutlinedRect(0, 0, w, h)
        end
        for _, cat in ipairs(LAWS.Categories) do
            catCombo:AddChoice(cat.name, cat.id, cat.id == law.category)
        end
        catCombo:SetEnabled(editable)

        local rowTop = vgui.Create("DPanel", editorPanel)
        rowTop:Dock(TOP) rowTop:SetTall(28) rowTop:DockMargin(0, 0, 0, 6) rowTop:SetPaintBackground(false)

        local artEntry = entry(rowTop, "№ статьи")
        artEntry:Dock(LEFT) artEntry:SetWide(110) artEntry:DockMargin(0, 0, 6, 0)
        artEntry:SetText(tostring(law.article or ""))
        artEntry:SetEditable(editable)

        local titleEntry = entry(rowTop, "Заголовок статьи")
        titleEntry:Dock(FILL)
        titleEntry:SetText(tostring(law.title or ""))
        titleEntry:SetEditable(editable)

        local textEntry = entry(editorPanel, "Текст статьи", true)
        textEntry:Dock(FILL) textEntry:DockMargin(0, 0, 0, 6)
        textEntry:SetText(tostring(law.text or ""))
        textEntry:SetEditable(editable)

        local penEntry = entry(editorPanel, "Наказание / санкция")
        penEntry:Dock(BOTTOM) penEntry:SetTall(28) penEntry:DockMargin(0, 6, 0, 6)
        penEntry:SetText(tostring(law.penalty or ""))
        penEntry:SetEditable(editable)

        if not editable then return end

        local buttons = vgui.Create("DPanel", editorPanel)
        buttons:Dock(BOTTOM) buttons:SetTall(38) buttons:SetPaintBackground(false)

        local function collect()
            local _, catID = catCombo:GetSelected()
            return {
                category = catID or law.category,
                article = artEntry:GetValue(),
                title = titleEntry:GetValue(),
                text = textEntry:GetValue(),
                penalty = penEntry:GetValue(),
            }
        end

        local save = btn(buttons, law.id > 0 and "СОХРАНИТЬ СТАТЬЮ" or "ОПУБЛИКОВАТЬ", C.green, function()
            if law.id > 0 then sendAction("edit", law.id, collect())
            else sendAction("add", 0, collect()) end
        end)
        save:Dock(LEFT) save:SetWide(200) save:DockMargin(0, 0, 6, 0)

        local newBtn = btn(buttons, "НОВАЯ СТАТЬЯ", C.accent, function()
            currentLaw = nil
            buildEditor()
            rebuildList()
        end)
        newBtn:Dock(LEFT) newBtn:SetWide(150) newBtn:DockMargin(0, 0, 6, 0)

        if law.id > 0 and state.canRemove then
            local del = btn(buttons, "УДАЛИТЬ", C.red, function()
                Derma_Query("Удалить статью #" .. law.id .. "?", "Кодекс", "Удалить", function()
                    sendAction("remove", law.id, {})
                    currentLaw = nil
                end, "Отмена")
            end)
            del:Dock(RIGHT) del:SetWide(140)
        end
    end

    -- ── Окно ─────────────────────────────────────────────────────────
    function LAWS.OpenMenu()
        if IsValid(frame) then frame:Remove() end
        currentCategory = currentCategory or "all"
        currentLaw = nil

        frame = vgui.Create("DFrame")
        if GRM.UI and GRM.UI.Track then GRM.UI.Track("grm_laws", frame) end
        frame:SetSize(math.Clamp(ScrW() * 0.86, 1080, 1500), math.Clamp(ScrH() * 0.84, 640, 940))
        frame:Center()
        frame:MakePopup()
        frame:SetTitle("")
        frame:SetSizable(true)
        frame:ShowCloseButton(false)
        frame.Paint = function(_, w, h)
            draw.RoundedBox(8, 0, 0, w, h, C.bg)
            draw.RoundedBoxEx(8, 0, 0, w, 46, C.sidebar, true, true, false, false)
            surface.SetDrawColor(C.border)
            surface.DrawOutlinedRect(0, 0, w, h)
            draw.SimpleText("GRM · СВОД ЗАКОНОВ", "GRMLaw_Title", 18, 23, C.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(state.canEdit and "У вас есть доступ к правке кодекса" or "Режим просмотра · правка недоступна",
                "GRMLaw_Small", w - 60, 23, state.canEdit and C.green or C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end

        local close = vgui.Create("DButton", frame)
        close:SetSize(34, 30) close:SetText("")
        close.Paint = function(self, w, h)
            if self:IsHovered() then draw.RoundedBox(4, 0, 0, w, h, C.red) end
            draw.SimpleText("✕", "GRMLaw_Btn", w / 2, h / 2, self:IsHovered() and color_white or C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        close.DoClick = function() frame:Close() end
        frame.PerformLayout = function(self, w) if IsValid(close) then close:SetPos(w - 44, 8) end end

        local body = vgui.Create("DPanel", frame)
        body:Dock(FILL) body:DockMargin(0, 46, 0, 0) body:SetPaintBackground(false)

        -- Боковое меню разделов
        local nav = vgui.Create("DScrollPanel", body)
        nav:Dock(LEFT) nav:SetWide(240)
        nav.Paint = function(_, w, h)
            draw.RoundedBox(0, 0, 0, w, h, C.sidebar)
            surface.SetDrawColor(C.border)
            surface.DrawLine(w - 1, 0, w - 1, h)
        end

        local function navButton(id, label, color)
            local b = vgui.Create("DButton", nav)
            b:Dock(TOP) b:SetTall(40) b:DockMargin(6, 4, 8, 0) b:SetText("")
            b.Paint = function(self, w, h)
                local active = currentCategory == id
                if active then draw.RoundedBox(6, 0, 0, w, h, C.accent)
                elseif self:IsHovered() then draw.RoundedBox(6, 0, 0, w, h, C.cardHover) end
                draw.RoundedBox(6, 0, 0, 3, h, color or C.gold)

                local count = 0
                for _, law in ipairs(state.laws) do
                    if id == "all" or law.category == id then count = count + 1 end
                end
                draw.SimpleText(label, "GRMLaw_Btn", 14, h / 2, active and color_white or (self:IsHovered() and C.text or C.dim),
                    TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText(tostring(count), "GRMLaw_Small", w - 12, h / 2,
                    active and color_white or C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end
            b.DoClick = function()
                currentCategory = id
                currentLaw = nil
                rebuildList()
                buildEditor()
            end
            return b
        end

        navButton("all", "Весь кодекс", C.gold)
        for _, cat in ipairs(LAWS.Categories) do
            navButton(cat.id, cat.name, Color(cat.color.r, cat.color.g, cat.color.b))
        end

        -- Правая часть: поиск + список + редактор
        local right = vgui.Create("DPanel", body)
        right:Dock(FILL) right:DockMargin(12, 10, 12, 12) right:SetPaintBackground(false)

        local topRow = vgui.Create("DPanel", right)
        topRow:Dock(TOP) topRow:SetTall(30) topRow:DockMargin(0, 0, 0, 8) topRow:SetPaintBackground(false)

        searchBox = entry(topRow, "Поиск по кодексу: статья, заголовок, текст, наказание…")
        searchBox:Dock(FILL)
        searchBox.OnChange = function() rebuildList() end

        local refresh = btn(topRow, "ОБНОВИТЬ", C.accent, function()
            net.Start("GRM_Laws_Refresh")
            net.SendToServer()
        end)
        refresh:Dock(RIGHT) refresh:SetWide(120) refresh:DockMargin(8, 0, 0, 0)

        local split = vgui.Create("DPanel", right)
        split:Dock(FILL) split:SetPaintBackground(false)

        listPanel = vgui.Create("DScrollPanel", split)
        listPanel:Dock(LEFT)
        listPanel:SetWide(math.floor(frame:GetWide() * 0.42))

        editorPanel = vgui.Create("DPanel", split)
        editorPanel:Dock(FILL) editorPanel:DockMargin(10, 0, 0, 0)
        editorPanel:DockPadding(12, 10, 12, 10)
        editorPanel.Paint = function(_, w, h)
            draw.RoundedBox(8, 0, 0, w, h, C.card)
            surface.SetDrawColor(C.border)
            surface.DrawOutlinedRect(0, 0, w, h)
        end

        rebuildList()
        buildEditor()

        net.Start("GRM_Laws_Refresh")
        net.SendToServer()
    end

    local function applyPayload(payload)
        if not istable(payload) then return end
        state.laws = istable(payload.laws) and payload.laws or {}
        state.canEdit = payload.canEdit == true
        state.canRemove = payload.canRemove == true

        -- Выбранная статья могла измениться на сервере.
        if currentLaw then
            local found = nil
            for _, law in ipairs(state.laws) do
                if law.id == currentLaw.id then found = law break end
            end
            currentLaw = found
        end

        if IsValid(frame) then
            rebuildList()
            buildEditor()
        end
    end

    if GRM.Net and GRM.Net.Receive then
        GRM.Net.Receive("laws.list", applyPayload)
    end

    net.Receive("GRM_Laws_List", function()
        applyPayload(net.ReadTable() or {})
    end)

    net.Receive("GRM_Laws_Open", function() LAWS.OpenMenu() end)

    -- Кодекс изменился: если окно открыто — просим свежий список.
    net.Receive("GRM_Laws_Changed", function()
        if not IsValid(frame) then return end
        net.Start("GRM_Laws_Refresh")
        net.SendToServer()
    end)

    net.Receive("GRM_Laws_Result", function()
        local ok, message = net.ReadBool(), net.ReadString()
        notification.AddLegacy(message, ok and NOTIFY_GENERIC or NOTIFY_ERROR, 4)
        surface.PlaySound(ok and "buttons/button14.wav" or "buttons/button10.wav")
    end)

    -- Окно откроет сервер ответом (иначе получалось двойное открытие).
    concommand.Add("grm_laws", function()
        net.Start("GRM_Laws_Open")
        net.SendToServer()
    end)
end

print("[GRM Laws] v" .. LAWS.Version .. " loaded")
