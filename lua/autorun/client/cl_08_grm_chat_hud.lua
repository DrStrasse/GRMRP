-- СГЕНЕРИРОВАНО tools/sync_chat_addon.py — источник: cl_grmrp_chat_hud.lua
-- Не править руками: изменения вносите в файл режима и перегенерируйте
-- (`python3 tools/sync_chat_addon.py`); расхождение ловит --check.
--[[ GRMChat — аддонский мутированный порт чат-модуля режима (тот же код,
    другие имена). На серверах с gamemode GRMRP модуль молча выключается
    целиком: чат режима — единственный владелец, дублей net-имён/cvar'ов/
    перехвата PlayerSay не возникает никогда.
]]
if SERVER then return end
if GRMRP and GRMRP.Version then return end

if SERVER then return end

-- Segoe UI (Windows) вместо бандлованного Roboto: кириллица та же, а
-- отсутствующие глифы (emoji) дотягиваются системным линкингом — в Roboto
-- «🙂» рисовался квадратом («плохо обрабатывает текст» со скрина 03.09).
-- вечер-10: «чат маленький» (владелец) — лента поднята 14→17, чип 13→15;
-- имя шрифта историческое (GRMRP_Chat14), размер — authoritative тут.
surface.CreateFont("GRMRP_Chat14", {
    font = "Segoe UI", size = 17, weight = 400, extended = true
})
surface.CreateFont("GRMRP_ChatChip", {
    font = "Segoe UI", size = 15, weight = 700, extended = true
})

GRMChat = GRMChat or {}
GRMChat.lines = GRMChat.lines or {}
GRMChat.INPUT_OPEN = false

local MAX_LINES = 300 -- рисуем 18; архив истории — отдельный, свой лимит
local MAX_ARCHIVE = 400
local TTL, FADE = 45, 4          -- сек; fade — последние FADE секунд жизни

-- forward: push зовёт ensureFeed (создать ленту до первой строки) — без
-- объявления выше local читался бы как глобал-nil (стенды forward_locals /
-- global_hygiene ловят именно это).
local feedLayout, ensureFeed

local function push(chan, name, text, t, mine)
    local entry = {
        chan = chan, name = name, text = text, t = t, mine = mine and true or false,
        wallT = os.time(), -- вечер-12: стенное время для истории/хранения
    }
    table.insert(GRMChat.lines, entry)
    if #GRMChat.lines > MAX_LINES then
        table.remove(GRMChat.lines, 1)
    end
    -- Вечер-12 («хранение»): лента — витрина (TTL-подметание её честно
    -- убивает), история — архив. Архив TTL не подметается, живёт дольше
    -- ленты и доживает до записи на диск (низ этого файла).
    GRMChat.archive = GRMChat.archive or {}
    table.insert(GRMChat.archive, entry)
    if #GRMChat.archive > MAX_ARCHIVE then
        table.remove(GRMChat.archive, 1)
    end
    GRMChat._histDirty = true
    ensureFeed() -- лента живёт панелью: создана до первой строки
end

function GRMChat.AddLine(chanId, name, text, t)
    local chan = GRMChat.GetChannel and GRMChat.GetChannel(chanId)
    push(chan or { title = "·", color = { r = 255, g = 255, b = 255 } },
        name, text, t, false)
end

-- Эхо автора печатается ФОРМАТРОМ ЯДРА (тот же ParseSay/RP, что и у
-- слушателей): «/me идёт» в ленту идёт как «* Вася идёт», а не сырой
-- слэш-текст (жалоба «результат прорисовки» 03.09).
function GRMChat.AddSelfLine(raw, selChan)
    raw = tostring(raw or "")
    local nick = LocalPlayer():Nick()
    local name, text, chanId = nick, raw, selChan
    if string.sub(raw, 1, 1) == "/" then
        local cid, body, extra = GRMChat.ParseSay(raw, selChan)
        if cid then
            chanId = cid
            local rp = extra and GRMChat.RP and GRMChat.RP[extra.cmd or ""]
            if rp then
                name = ""
                text = rp.fmt(nick, body, extra.cmd == "do" and { self = true } or nil)
            elseif cid == "pm" then
                name, text = "📩 " .. (extra.target or "?"), body
            else
                name, text = nick, body
            end
        end
    end
    local chan = GRMChat.GetChannel and GRMChat.GetChannel(chanId)
    push(chan or { title = "·", color = { r = 255, g = 255, b = 255 } },
        name, text, CurTime(), true)
end

function GRMChat.ClearLines()
    GRMChat.lines = {}
end

-- Самодиагностика (эскалация 03.09: «не отрисовывает ни по одному
-- каналу»). «/chatdiag» в строке ввода: вывод — в консоль И одной строкой
-- в ленту. Строка нарисована — значит лента жива, а жалоба относится к
-- другой сборке; строки нет при живом вводе — лог клиента в руки.
function GRMChat.Diagnose()
    local cv = GetConVar and GetConVar("grm_chat_enable")
    local n = #(GRMChat.lines or {})
    local hold = GRMChat.INPUT_OPEN and "ввод открыт" or "ввод закрыт"
    -- вечер-12.2: диагностика покрывает ВСЕ пять мест жалобы — отправка,
    -- хранение (архив+диск), запоминание (память ввода), история, окно.
    local arcN = #(GRMChat.archive or {})
    local inpN = #(GRMChat.inputHistory or {})
    local fdesc = "диск: нет файла"
    pcall(function()
        if file and file.Exists and file.Size and file.Exists("grm_chat/archive.txt", "DATA") then
            local sz = file.Size("grm_chat/archive.txt", "DATA")
            local tm = file.Time and file.Time("grm_chat/archive.txt", "DATA", "mtime")
            fdesc = "диск: " .. tostring(sz or "?") .. " Б" ..
                (tm and (" (запись " .. os.date("%H:%M", tm) .. ")") or "")
        end
    end)
    local bits = {
        "чат вечер-12.2 (03.09), лента = панель · SendText для модулей",
        "лента: " .. n .. " строк · архив истории: " .. arcN .. " · " .. fdesc,
        "память ввода: " .. inpN .. " строк (↑/↓, переживает рестарт)",
        "окно истории: " .. (GRMChat.HIST_OPEN and "открыто" or "закрыто") .. " · источник — архив, не лента",
        "enable=" .. (cv and tostring(cv:GetBool()) or "cvar нет → вкл"),
        hold,
    }
    for _, s in ipairs(bits) do print("[GRMRP chat] " .. s) end
    if GRMChat.AddLine then
        GRMChat.AddLine("ooc", "чат-диаг",
            bits[1] .. " · " .. bits[2] .. " · " .. bits[3] .. " · " .. bits[4])
    end
end

net.Receive(GRMChat.Net.MSG, function()
    if not GRMChat.lines then return end
    local chanId = net.ReadString()
    local name = net.ReadString()
    local text = net.ReadString()
    net.ReadDouble() -- серверные часы: протокол читаем, возраст НЕ считаем
    if chanId == "system" then
        push({ title = "!", color = { r = 250, g = 185, b = 63 } }, "", name, CurTime(), false)
        return
    end
    if string.sub(chanId, -5) == "_self" then
        -- эхо сервера для наших старых клиентов: локальный эхо-каст уже
        -- напечатан — молча гасим дубль (§5.2 «один владелец строки»)
        return
    end
    -- ШТАМП — КЛИЕНТСКИЕ CurTime. Урок 03.09 (вечер-6, «отправка есть,
    -- отрисовки нет ни в одном канале»): лена считала возраст строки как
    -- RealTime() - t, где t — CurTime автора или, для чужих строк, CurTime
    -- СЕРВЕРА из пакета. Разница RealTime/CurTime = часы аптайма машины,
    -- «свежая» строка была уже «протухшей» — lifeLeft=0, лента молчала.
    -- Возраст и жизнь строки живут на одних часах: CurTime().
    GRMChat.AddLine(chanId, name, text, CurTime())
end)

--[[ Вечер-9: лента РИСУЕТСЯ ПАНЕЛЬЮ, а не HUDPaint. Третья identical
     жалоба «не отрисовывает» при доказанном (грепом из зипов) вечер-7/8 —
     значит ищем не текст, а среду: surface-вызовы из HUDPaint живут в
     пространстве масштаба HUD (HudScaleMode), и «якорь снизу от ScrH()»
     на чужих масштабах/разрешениях уезжает за край экрана. Полоса ввода
     при этом видна — потому что она derma (физические пиксели). Лента
     переезжает в тот же мир: обычная нено/modal панель над полосой ввода
     искажается тем, что и ввод, то есть ничем. Буфер, часы и hold-логика
     не меняются. ]]
local feed = nil
local ROW = 26 -- строка ленты вечером-10 крупнее: 22 -> 26

feedLayout = function(p)
    local w = math.min(900, ScrW() - 32)
    local hgt = ROW * 18 + 14
    p:SetBounds(8, math.max(0, ScrH() - 268 - hgt), w, hgt)
end

ensureFeed = function()
    if IsValid(feed) then return feed end
    feed = vgui.Create("EditablePanel")
    if not IsValid(feed) then return nil end
    feed:SetMouseInputEnabled(false)
    feed:SetKeyInputEnabled(false)
    feedLayout(feed)
    feed.Paint = function(p, w, h)
        local lines = GRMChat.lines
        if not lines or #lines == 0 then return end
        local nowRT = CurTime() -- те же часы, что в штампах push/AddLine
        local hold = GRMChat.INPUT_OPEN or GRMChat.HIST_OPEN
        local shown = 0
        for i = #lines, 1, -1 do
            local ln = lines[i]
            if shown >= 18 then break end
            local age = nowRT - (ln.t or 0)
            -- Открыт ввод/история → лента ДЕРЖИТСЯ (не гаснет, §5.17).
            local lifeLeft = (hold and 1) or math.Clamp((TTL + FADE - age) / FADE, 0, 1)
            if lifeLeft > 0 then
                shown = shown + 1
                local x, y = 10, h - 12 - shown * ROW
                local chan = ln.chan
                local tag = chan.title or "·"
                local col = chan.color or { r = 255, g = 255, b = 255 }
                local a = math.floor(255 * lifeLeft + 0.5)

                -- «Странные полосы» вечера-9: фон рисовался по формуле
                -- «130 + ширина текста» и не накрывал имя. Полоса м.10
                -- измеряется по ФАКТУ строки (шрифт->ширина), со скруглением
                -- и цветным акцентом канала слева.
                surface.SetFont("GRMRP_ChatChip")
                local cw = surface.GetTextSize("[" .. tag .. "]") or 30
                local nw = 0
                if #ln.name > 0 then nw = (surface.GetTextSize(ln.name .. ":") or 0) + 8 end
                surface.SetFont("GRMRP_Chat14")
                local tw = surface.GetTextSize(ln.text) or 40
                local strip = math.min(w - 16, 16 + cw + 6 + nw + tw + 10)
                draw.RoundedBox(5, x - 8, y - 4, strip, ROW - 5, Color(8, 14, 23, math.floor(a * 0.72)))
                draw.RoundedBox(0, x - 8, y - 4, 3, ROW - 5, Color(col.r, col.g, col.b, a))
                local tx = x
                draw.DrawText("[" .. tag .. "]", "GRMRP_ChatChip", tx, y - 3,
                    Color(col.r, col.g, col.b, a), TEXT_ALIGN_LEFT)
                tx = tx + cw + 6
                if #ln.name > 0 then
                    draw.DrawText(ln.name .. ":", "GRMRP_ChatChip", tx, y - 3,
                        Color(170, 190, 210, a), TEXT_ALIGN_LEFT)
                    tx = tx + nw
                end
                draw.DrawText(ln.text, "GRMRP_Chat14", tx, y - 2,
                    ln.mine and Color(255, 255, 255, a) or Color(225, 238, 247, a),
                    TEXT_ALIGN_LEFT)
            end
        end
        -- подметание просроченных (не держим мусор буфера между боями)
        if not hold then
            for i = #lines, 1, -1 do
                if nowRT - lines[i].t > TTL + FADE then
                    table.remove(lines, i)
                end
            end
        end
    end
    return feed
end

hook.Add("OnScreenSizeChanged", "GRMChat_FeedPos", function()
    if IsValid(feed) then feedLayout(feed) end
end)

-- Оттиск сборки прямо в ленте (вечер-9): открыв ввод, владелец видит,
-- КАКОЙ сборкой рисует чат, — за спор «починили/не починили» отвечает
-- одна строка, без консоли. Один раз за сессию клиента.
function GRMChat.AddSystem(text)
    push({ title = "!", color = { r = 250, g = 185, b = 63 } },
        tostring(text or ""), "", CurTime(), false)
end

function GRMChat.EnsureFeed()
    return ensureFeed()
end

--[[ Вечер-12: ХРАНЕНИЕ истории. Архив пишется в DATA раз в 45 секунд
     (только когда менялся) и читается на старте — история пережила
     рестарт клиента. Нет file/util — молча живём в RAM: окно истории
     работоспособность от этого не теряет. ]]
local HIST_FILE = "grm_chat/archive.txt"

local function saveArchive()
    if not (GRMChat.archive and #GRMChat.archive > 0) then return end
    local out = {}
    local from = math.max(1, #GRMChat.archive - 120 + 1)
    for i = from, #GRMChat.archive do
        local ln = GRMChat.archive[i]
        out[#out + 1] = {
            w = ln.wallT or 0,
            c = tostring(ln.chan and ln.chan.title or "·"),
            n = tostring(ln.name or ""),
            x = tostring(ln.text or ""),
        }
    end
    pcall(function()
        if file and file.CreateDir and file.Write and util and util.TableToJSON then
            file.CreateDir("grm_chat")
            file.Write(HIST_FILE, util.TableToJSON(out))
            GRMChat._histDirty = false
        end
    end)
end
GRMChat.SaveArchive = saveArchive

-- вечер-12.2: «хранение» доводится до надёжности — флеш при выходе из игры
-- (движковый глобальный хук Shutdown), ручная команда и очистка. Таймер
-- 45 с → 20 с: окно «последние полминуты не сохранены» сокращено вдвое.
local function flushAll()
    saveArchive()
    if GRMChat.SaveInput then GRMChat.SaveInput() end
end
hook.Add("Shutdown", "GRMChat_ArchiveFlush", flushAll)

if concommand and concommand.Add then
    concommand.Add("grm_chat_save", function()
        flushAll()
        print("[GRM chat] архив и память ввода записаны на диск")
    end)
    concommand.Add("grm_chat_clear", function()
        GRMChat.archive = {}
        GRMChat._histDirty = false
        pcall(function()
            if file and file.Remove then file.Remove(HIST_FILE, "DATA") end
        end)
        GRMChat.lines = {}
        if GRMChat.AddSystem then
            GRMChat.AddSystem("архив истории очищен (память и диск); grm_chat_clear")
        end
    end)
end

local function loadArchive()
    pcall(function()
        if not (file and file.Exists and util and util.JSONToTable) then return end
        if not file.Exists(HIST_FILE, "DATA") then return end
        local raw = file.Read(HIST_FILE, "DATA")
        if not isstring(raw) or #raw < 2 then return end
        local tbl = util.JSONToTable(raw)
        if not istable(tbl) then return end
        GRMChat.archive = GRMChat.archive or {}
        for i = 1, #tbl do
            local e = tbl[i]
            if istable(e) and isstring(e.x) then
                table.insert(GRMChat.archive, {
                    chan = { title = tostring(e.c or "·"), color = { r = 132, g = 160, b = 178 } },
                    name = tostring(e.n or ""), text = tostring(e.x),
                    wallT = tonumber(e.w) or 0,
                })
            end
        end
        local over = #GRMChat.archive - MAX_ARCHIVE
        for i = 1, over do table.remove(GRMChat.archive, 1) end
        -- восстановленные строки в ЛЕНТУ не попадают: лента остаётся живой
    end)
end
loadArchive()

if timer and timer.Create then
    timer.Create("GRMChat_HistSave", 20, 0, function()
        if GRMChat._histDirty then saveArchive() end
    end)
end

-- Единственный владелец отображения чата: движковая панель скрыта, весь
-- chat.AddText (его зовут документы/обучение/биндер) течёт в нашу ленту.
hook.Add("HUDShouldDraw", "GRMChat_HideVanilla", function(name)
    if name == "CHudChat" and GRMChat.Enabled and GRMChat.Enabled() then
        return false
    end
end)

do
    local baseAddText = chat.AddText
    function chat.AddText(...)
        if not (GRMChat.Enabled and GRMChat.Enabled()) then
            return baseAddText(...)
        end
        local parts = {}
        for i = 1, select("#", ...) do
            local v = select(i, ...)
            if isstring(v) then
                parts[#parts + 1] = v
            end
        end
        local text = table.concat(parts, " ")
        if #text == 0 then return end
        if GRMChat.AddLine then
            GRMChat.AddLine("ooc", "", text, CurTime())
        end
    end
end
