--[[ GRMRPChat HUD-лента: closed-form fade (EasyChat chathud, WIKI 4.21.4),
    кольцевой буфер, разметка не парсится — рисуем чипами (цвет канала +
    имя + текст), т.к. пользовательский ввод уже обезврежен на сервере.
]]

-- Вечер-14: единая библиотека (см. sh_core).
if SERVER then return end
if GRMRPChat and GRMRPChat.__hud then return end
GRMRPChat = GRMRPChat or {}
GRMRPChat.__hud = true

-- Segoe UI (Windows) вместо бандлованного Roboto: кириллица та же, а
-- отсутствующие глифы (emoji) дотягиваются системным линкингом — в Roboto
-- «🙂» рисовался квадратом («плохо обрабатывает текст» со скрина 03.09).
-- вечер-10: «чат маленький» (владелец) — лента поднята 14→17, чип 13→15;
-- имя шрифта историческое (GRMRP_Chat14), размер — authoritative тут.
-- вечер-22: владелец «текст слишком маленький» — лента 17→19, чип 15→16;
-- 19px Segoe UI на тёмной панели GRM, межстрочный шаг 30px — читабельно.
surface.CreateFont("GRMRP_Chat14", {
    font = "Segoe UI", size = 19, weight = 400, extended = true
})
surface.CreateFont("GRMRP_ChatChip", {
    font = "Segoe UI", size = 16, weight = 700, extended = true
})

GRMRPChat = GRMRPChat or {}
GRMRPChat.lines = GRMRPChat.lines or {}
GRMRPChat.INPUT_OPEN = false

local MAX_LINES = 300 -- рисуем 18; архив истории — отдельный, свой лимит
local MAX_ARCHIVE = 400
local TTL, FADE = 45, 4          -- сек; fade — последние FADE секунд жизни

-- forward: push зовёт ensureFeed (создать ленту до первой строки) — без
-- объявления выше local читался бы как глобал-nil (стенды forward_locals /
-- global_hygiene ловят именно это).
local feedLayout, ensureFeed

-- Вечер-22: робастность. nil-поля и nil-канал не роняют ленту: restore
-- архива, чужие вызовы AddLine и кривые пакеты доезжают до paint, а не до
-- ErrorNoHalt-обрушения HUD.
local RAW_CHAN = { id = "raw", title = "·", color = { r = 255, g = 255, b = 255 } }
local moduleErrBudget = 3
local function push(chan, name, text, t, mine)
    local entry = {
        chan = istable(chan) and chan or RAW_CHAN,
        name = tostring(name or ""),
        text = string.sub(tostring(text or ""), 1, 900),
        t = tonumber(t) or CurTime(),
        mine = mine and true or false,
        wallT = os.time(), -- вечер-12: стенное время для истории/хранения
    }
    -- Вечер-21: хук модулей (упоминания перекрашивают entry.color,
    -- подавленные каналы ставят entry.muted — строка уходит в архив, но не
    -- в витрину). Единственная точка подписки — обе ветки (сеть/echo/
    -- AddLine/мост) идут через push.
    -- Сбой хука модуля не съедает строку: pcall + лог с бюджетом (3).
    if hook and hook.Run then
        local ok, err = pcall(hook.Run, "GRMRPChat_Message", entry)
        if not ok and moduleErrBudget > 0 then
            moduleErrBudget = moduleErrBudget - 1
            if ErrorNoHalt then
                ErrorNoHalt("[grm_chat] модуль ленты: " .. tostring(err) ..
                    (moduleErrBudget > 0 and "" or " (дальше молчим)") .. "\n")
            end
        end
    end
    if not entry.muted then
        table.insert(GRMRPChat.lines, entry)
        if #GRMRPChat.lines > MAX_LINES then
            table.remove(GRMRPChat.lines, 1)
        end
    end
    -- Вечер-12 («хранение»): лента — витрина (TTL-подметание её честно
    -- убивает), история — архив. Архив TTL не подметается, живёт дольше
    -- ленты и доживает до записи на диск (низ этого файла).
    GRMRPChat.archive = GRMRPChat.archive or {}
    table.insert(GRMRPChat.archive, entry)
    if #GRMRPChat.archive > MAX_ARCHIVE then
        table.remove(GRMRPChat.archive, 1)
    end
    GRMRPChat._histDirty = true
    ensureFeed() -- лента живёт панелью: создана до первой строки
end

function GRMRPChat.AddLine(chanId, name, text, t)
    local chan = GRMRPChat.GetChannel and GRMRPChat.GetChannel(chanId)
    push(chan or { title = "·", color = { r = 255, g = 255, b = 255 } },
        name, text, t, false)
end

-- Эхо автора печатается ФОРМАТРОМ ЯДРА (тот же ParseSay/RP, что и у
-- слушателей): «/me идёт» в ленту идёт как «* Вася идёт», а не сырой
-- слэш-текст (жалоба «результат прорисовки» 03.09).
function GRMRPChat.AddSelfLine(raw, selChan)
    raw = tostring(raw or "")
    local nick = LocalPlayer():Nick()
    local name, text, chanId = nick, raw, selChan
    if string.sub(raw, 1, 1) == "/" then
        local cid, body, extra = GRMRPChat.ParseSay(raw, selChan)
        if cid then
            chanId = cid
            local rp = extra and GRMRPChat.RP and GRMRPChat.RP[extra.cmd or ""]
            if rp then
                name = ""
                text = rp.fmt(nick, body, extra.cmd == "do" and { self = true } or nil)
            elseif cid == "pm" then
                name, text = "[ЛС] " .. (extra.target or "?"), body
            else
                name, text = nick, body
            end
        end
    end
    local chan = GRMRPChat.GetChannel and GRMRPChat.GetChannel(chanId)
    push(chan or { title = "·", color = { r = 255, g = 255, b = 255 } },
        name, text, CurTime(), true)
end

-- Вечер-24 (история чата «не отражает»): у C++ Label перенос зависит от
-- уже применённой ширины панели — в тот же кадр после SetSize она негарантирована,
-- и DLabel дал «столбик по букве» на весь экран. Перенос считается ЗДЕСЬ
-- явно (ground truth — surface.GetTextSize), строки раскладываются сами.
function GRMRPChat.WrapText(text, fontName, maxW)
    text = tostring(text or "")
    maxW = math.max(60, tonumber(maxW) or 200)
    surface.SetFont(fontName or "DermaDefault")
    local out, cur = {}, ""
    for word in text:gmatch("%S+") do
        local try = #cur == 0 and word or (cur .. " " .. word)
        local tw = surface.GetTextSize(try) or 0
        if tw <= maxW then
            cur = try
        else
            if #cur > 0 then out[#out + 1] = cur end
            -- слово длиннее всей ширины: режем по ширине, иначе у.Label
            -- начинается «столбик по букве» (тот самый скрин 06.09)
            local w = word
            while (surface.GetTextSize(w) or 0) > maxW do
                local cut = #w
                while cut > 1 and (surface.GetTextSize(w:sub(1, cut)) or 0) > maxW do
                    cut = cut - 1
                end
                -- не рассечь UTF-8-пару (клипы посередине буквы — WIKI);
                -- continuation byte = 0x80..0xBF на позиции cut+1
                while cut > 1 do
                    local nb = w:byte(cut + 1)
                    if not nb or nb < 0x80 or nb >= 0xC0 then break end
                    cut = cut - 1
                end
                out[#out + 1] = w:sub(1, cut)
                w = w:sub(cut + 1)
            end
            cur = w
        end
    end
    if #cur > 0 then out[#out + 1] = cur end
    if #out == 0 then out[1] = "" end
    return out
end

-- Клиентское зеркало кулдауна каналов (advert и пр.): сервер и так отвергает
-- сверх лимита, НО оптимистичное эхо печатало «принятое» сообщение автору —
-- владелец видел свою строку в ленте и решал, что анти-спам пропустил
-- (претензия веч.-24). Теперь в окне кулдауна сообщение не печатается и
-- даже не уходит: мгновенная локальная отбивка, сервер — по-прежнему
-- единственный владелец решения.
function GRMRPChat.CooldownLeft(chanId)
    local chan = GRMRPChat.GetChannel and GRMRPChat.GetChannel(chanId)
    if not chan or not chan.cooldown or chan.cooldown <= 0 then return 0 end
    local last = (GRMRPChat._cdSent or {})[chanId]
    if not last then return 0 end
    return math.max(0, chan.cooldown - (CurTime() - last))
end

function GRMRPChat.MarkCooldownSend(chanId)
    local chan = GRMRPChat.GetChannel and GRMRPChat.GetChannel(chanId)
    if not chan or not chan.cooldown or chan.cooldown <= 0 then return end
    GRMRPChat._cdSent = GRMRPChat._cdSent or {}
    GRMRPChat._cdSent[chanId] = CurTime()
end

function GRMRPChat.ClearLines()
    GRMRPChat.lines = {}
end

--[[ Вечер-13: МОСТ chat.AddText. Документы/анонсы/обучение зовут движковый
     chat.AddText; панель движка режим прячет (GM:HUDShouldDraw), и без моста
     эти строки просто исчезали — а с живым песочным портом их перехватывал
     порт в СВОЮ ленту (тот же баг двойного владельца). Теперь chat.AddText течёт
     в ленту режима; при выключенном чате — базовая реализация (цепочка).
     Единственный wrapper за сессию: повторная загрузка файла не удваивает. ]]
if not GRMRPChat._addTextBridge and chat and chat.AddText then
    local baseAddText = chat.AddText
    function chat.AddText(...)
        if not GRMRPChat.Enabled() then
            return baseAddText(...)
        end
        -- вечер-22: падение моста не глушит движковый вывод — разбор в
        -- pcall, при сбое строка уходит базовой реализации. Аргументы
        -- снимаем в таблицу ДО замыкания: '...' внутри функции недоступен.
        local argc = select("#", ...)
        local argv = { ... }
        local ok = pcall(function()
            local parts = {}
            for i = 1, argc do
                local v = argv[i]
                if isstring(v) then
                    parts[#parts + 1] = v
                elseif istable(v) and isstring(v[1]) then
                    parts[#parts + 1] = v[1] -- {color, text}
                elseif IsValid(v) and v.IsPlayer and v:IsPlayer() then
                    parts[#parts + 1] = v:Nick()
                end
            end
            local text = table.concat(parts, " ")
            if #text == 0 then return end
            if string.find(text, "[МОДЕРАЦИЯ]", 1, true)
                or string.find(text, "[АДМИНИСТРАЦИЯ]", 1, true) then
                -- анонсы админки («[МОДЕРАЦИЯ] Администратор X наказал
                -- игрока Y - глобальный бан…») — в красный канал
                -- модерации ленты; префикс уже внутри текста
                if GRMRPChat.AddNotice then
                    GRMRPChat.AddNotice(text, "МОДЕРАЦИЯ", 225, 70, 70)
                    return
                end
            end
            if GRMRPChat.AddLine then
                GRMRPChat.AddLine("ooc", "", text, CurTime())
            end
        end)
        if not ok then return baseAddText(...) end
    end
    GRMRPChat._addTextBridge = true
end

-- Самодиагностика (эскалация 03.09: «не отрисовывает ни по одному
-- каналу»). «/chatdiag» в строке ввода: вывод — в консоль И одной строкой
-- в ленту. Строка нарисована — значит лента жива, а жалоба относится к
-- другой сборке; строки нет при живом вводе — лог клиента в руки.
function GRMRPChat.Diagnose()
    local cv = GetConVar and GetConVar("grmrp_chat_enable")
    local n = #(GRMRPChat.lines or {})
    local hold = GRMRPChat.INPUT_OPEN and "ввод открыт" or "ввод закрыт"
    -- вечер-12.2: диагностика покрывает ВСЕ пять мест жалобы — отправка,
    -- хранение (архив+диск), запоминание (память ввода), история, окно.
    local arcN = #(GRMRPChat.archive or {})
    local inpN = #(GRMRPChat.inputHistory or {})
    local fdesc = "диск: нет файла"
    pcall(function()
        if file and file.Exists and file.Size and file.Exists("grm_chat/archive.txt", "DATA") then
            local sz = file.Size("grm_chat/archive.txt", "DATA")
            local tm = file.Time and file.Time("grm_chat/archive.txt", "DATA", "mtime")
            fdesc = "диск: " .. tostring(sz or "?") .. " Б" ..
                (tm and (" (запись " .. os.date("%H:%M", tm) .. ")") or "")
        end
    end)
    local portDesc = "чужие владельцы чата: нет"
    local legacy = (GRMChat and GRMChat ~= GRMRPChat) and GRMChat or nil
    if legacy then
        portDesc = legacy.SUPPRESSED and "чужие владельцы: подавлены"
            or "чужие владельцы: АКТИВЕН — дубль чата!!!"
    end
    local modsN, modsBad = 0, 0
    for _, m in pairs(GRMRPChat.Modules or {}) do
        if m.state == "loaded" then modsN = modsN + 1
        elseif m.state == "error" then modsBad = modsBad + 1 end
    end
    local bits = {
        "чат вечер-22 (06.09) · заход/выход и модерация — в ленте · шрифт 19px · автоотыгровки на шине",
        portDesc .. " · chat.AddText: " .. (GRMRPChat._addTextBridge and "мост к ленте" or "мимо ленты!"),
        "лента: " .. n .. " строк · архив истории: " .. arcN .. " · " .. fdesc,
        "память ввода: " .. inpN .. " строк (↑/↓, переживает рестарт)",
        "окно истории: " .. (GRMRPChat.HIST_OPEN and "открыто" or "закрыто") .. " · источник — архив, не лента",
        "enable=" .. (cv and tostring(cv:GetBool()) or "cvar нет → вкл"),
        "модули: " .. modsN .. (modsBad > 0 and (" · ОШИБОК: " .. modsBad)
            or ""),
        hold,
    }
    for _, s in ipairs(bits) do print("[GRMRP chat] " .. s) end
    if GRMRPChat.AddLine then
        GRMRPChat.AddLine("ooc", "чат-диаг",
            bits[1] .. " · " .. bits[2] .. " · " .. bits[3] .. " · " .. bits[4])
    end
end

-- Вечер-14: только собственный реестр имён (GRMRPChat.Net) — библиотека
-- не знает про GRMRP и живёт в песочнице без режима.
net.Receive(GRMRPChat.Net.MSG, function()
    if not GRMRPChat.lines then return end
    local chanId = net.ReadString()
    local name = net.ReadString()
    local text = net.ReadString()
    net.ReadDouble() -- серверные часы: протокол читаем, возраст НЕ считаем
    if chanId == "system" then
        push({ id = "system", title = "Система", color = { r = 250, g = 185, b = 63 } },
            "", name, CurTime(), false)
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
    GRMRPChat.AddLine(chanId, name, text, CurTime())
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
local ROW = 30 -- строка ленты: веч.-10 22→26, веч.-22 26→30 (текст 19px)

feedLayout = function(p)
    local w = math.min(900, ScrW() - 32)
    local hgt = ROW * 18 + 14
    -- Вечер-18: «Panel:SetBounds» в Lua-API движка НЕТ (есть только
    -- GetBounds) — боевой креш клиента именно здесь. Реальные нативные
    -- методы: SetPos + SetSize (ground truth: ноль употреблений SetBounds
    -- во всём lua-дереве движка Facepunch/garrysmod).
    p:SetPos(8, math.max(0, ScrH() - 268 - hgt))
    p:SetSize(w, hgt)
end

ensureFeed = function()
    if IsValid(feed) then return feed end
    feed = vgui.Create("EditablePanel")
    if not IsValid(feed) then return nil end
    feed:SetMouseInputEnabled(false)
    -- Реальный метод — SetKeyboardInputEnabled («SetKeyInputEnabled» в
    -- движке НЕТ: 04.09 краш боевого клиента ensureFeed:174, стендовый
    -- вседозволяющий vgui-стаб его не видел).
    feed:SetKeyboardInputEnabled(false)
    feedLayout(feed)
    feed.Paint = function(p, w, h)
        local lines = GRMRPChat.lines
        if not lines or #lines == 0 then return end
        local nowRT = CurTime() -- те же часы, что в штампах push/AddLine
        local hold = GRMRPChat.INPUT_OPEN or GRMRPChat.HIST_OPEN
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
                local chan = ln.chan or RAW_CHAN
                local tag = chan.title or "·"
                local col = ln.color or chan.color or { r = 255, g = 255, b = 255 }
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
                -- Вечер-24 (владелец): тело отыгровки — фиолетовое (bodyColor
                -- канала), тег [Отыгровка] остаётся жёлтым. Свой эхо-каст красим
                -- тем же тоном: «всё касаемо отыгровок», не только чужие строки.
                local bcol = chan.bodyColor
                draw.DrawText(ln.text, "GRMRP_Chat14", tx, y - 2,
                    bcol and Color(bcol.r, bcol.g, bcol.b, a)
                    or (ln.mine and Color(255, 255, 255, a) or Color(225, 238, 247, a)),
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

hook.Add("OnScreenSizeChanged", "GRMRPChat_FeedPos", function()
    if IsValid(feed) then feedLayout(feed) end
end)

-- Оттиск сборки прямо в ленте (вечер-9): открыв ввод, владелец видит,
-- КАКОЙ сборкой рисует чат, — за спор «починили/не починили» отвечает
-- одна строка, без консоли. Один раз за сессию клиента.
function GRMRPChat.AddSystem(text)
    push({ id = "system", title = "Система", color = { r = 250, g = 185, b = 63 } },
        tostring(text or ""), "", CurTime(), false)
end

-- Вечер-22: уведомление с собственным тегом канала. Цвета — язык GRM:
-- амбра «Система» и красный 225,70,70 анонсов админки — без
-- самодеятельной палитры.
function GRMRPChat.AddNotice(text, tag, r, g, b)
    push({ id = "notice", title = tostring(tag or "Система"),
        color = {
            r = tonumber(r) or 250,
            g = tonumber(g) or 185,
            b = tonumber(b) or 63,
        } },
        "", tostring(text or ""), CurTime(), false)
end

function GRMRPChat.EnsureFeed()
    return ensureFeed()
end

--[[ Вечер-12: ХРАНЕНИЕ истории. Архив пишется в DATA раз в 45 секунд
     (только когда менялся) и читается на старте — история пережила
     рестарт клиента. Нет file/util — молча живём в RAM: окно истории
     работоспособность от этого не теряет. ]]
local HIST_FILE = "grm_chat/archive.txt"

local function saveArchive()
    if not (GRMRPChat.archive and #GRMRPChat.archive > 0) then return end
    local out = {}
    local from = math.max(1, #GRMRPChat.archive - 120 + 1)
    for i = from, #GRMRPChat.archive do
        local ln = GRMRPChat.archive[i]
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
            GRMRPChat._histDirty = false
        end
    end)
end
GRMRPChat.SaveArchive = saveArchive

-- вечер-12.2: «хранение» доводится до надёжности — флеш при выходе из игры
-- (движковый глобальный хук Shutdown), ручная команда и очистка. Таймер
-- 45 с → 20 с: окно «последние полминуты не сохранены» сокращено вдвое.
local function flushAll()
    saveArchive()
    if GRMRPChat.SaveInput then GRMRPChat.SaveInput() end
end
hook.Add("Shutdown", "GRMRPChat_ArchiveFlush", flushAll)

GRMRPChat.__cc = GRMRPChat.__cc or {}
GRMRPChat.__cc.grm_chat_save = true
GRMRPChat.__cc.grm_chat_clear = true
if concommand and concommand.Add then
    concommand.Add("grm_chat_save", function()
        flushAll()
        print("[GRM chat] архив и память ввода записаны на диск")
    end)
    concommand.Add("grm_chat_clear", function()
        GRMRPChat.archive = {}
        GRMRPChat._histDirty = false
        pcall(function()
            if file and file.Remove then file.Remove(HIST_FILE, "DATA") end
        end)
        GRMRPChat.lines = {}
        if GRMRPChat.AddSystem then
            GRMRPChat.AddSystem("архив истории очищен (память и диск); grm_chat_clear")
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
        GRMRPChat.archive = GRMRPChat.archive or {}
        for i = 1, #tbl do
            local e = tbl[i]
            if istable(e) and isstring(e.x) then
                table.insert(GRMRPChat.archive, {
                    chan = { title = tostring(e.c or "·"), color = { r = 132, g = 160, b = 178 } },
                    name = tostring(e.n or ""), text = tostring(e.x),
                    wallT = tonumber(e.w) or 0,
                })
            end
        end
        local over = #GRMRPChat.archive - MAX_ARCHIVE
        for i = 1, over do table.remove(GRMRPChat.archive, 1) end
        -- восстановленные строки в ЛЕНТУ не попадают: лента остаётся живой
    end)
end
loadArchive()

if timer and timer.Create then
    timer.Create("GRMRPChat_HistSave", 20, 0, function()
        if GRMRPChat._histDirty then saveArchive() end
    end)
end

-- Вечер-14: единый hide ванильного чата (песочнице не нужен GM-метод,
-- режиму он не мешает — оба возвращают false идемпотентно).
hook.Add("HUDShouldDraw", "GRMRPChat_HideVanilla", function(name)
    if name == "CHudChat" and GRMRPChat.Enabled() then
        return false
    end
end)

-- ...и поздняя зачистка чужих хуков после полной инициализации
hook.Add("InitPostEntity", "GRMRPChat_LateSuppress", function()
    if isfunction(GRMRPChat.SuppressForeignChat) then
        GRMRPChat.SuppressForeignChat()
    end
end)
