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
surface.CreateFont("GRMRP_Chat14", {
    font = "Segoe UI", size = 14, weight = 400, extended = true
})
surface.CreateFont("GRMRP_ChatChip", {
    font = "Segoe UI", size = 13, weight = 700, extended = true
})

GRMChat = GRMChat or {}
GRMChat.lines = GRMChat.lines or {}
GRMChat.INPUT_OPEN = false

local MAX_LINES = 300 -- рисуем 18, история (окно) видит все 300
local TTL, FADE = 45, 4          -- сек; fade — последние FADE секунд жизни

-- forward: push зовёт ensureFeed (создать ленту до первой строки) — без
-- объявления выше local читался бы как глобал-nil (стенды forward_locals /
-- global_hygiene ловят именно это).
local feedLayout, ensureFeed

local function push(chan, name, text, t, mine)
    table.insert(GRMChat.lines, {
        chan = chan, name = name, text = text, t = t, mine = mine and true or false
    })
    if #GRMChat.lines > MAX_LINES then
        table.remove(GRMChat.lines, 1)
    end
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
    local bits = {
        "чат вечер-9 (03.09), лента = панель",
        "лента: " .. n .. " строк",
        "часы: CurTime (RealTime-дефект ленты исправлен)",
        "enable=" .. (cv and tostring(cv:GetBool()) or "cvar нет → вкл"),
        hold,
    }
    for _, s in ipairs(bits) do print("[GRMRP chat] " .. s) end
    if GRMChat.AddLine then
        GRMChat.AddLine("ooc", "чат-диаг",
            bits[1] .. " · " .. bits[2] .. " · " .. bits[3])
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

feedLayout = function(p)
    local w = math.min(780, ScrW() - 32)
    local hgt = 22 * 18 + 14
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
                local x, y = 8, h - 10 - shown * 22
                local chan = ln.chan
                local col = chan.color or { r = 255, g = 255, b = 255 }
                local a = math.floor(255 * lifeLeft + 0.5)

                surface.SetFont("GRMRP_Chat14")
                local tw = surface.GetTextSize(ln.text) or 40
                surface.SetDrawColor(8, 14, 23, math.floor(a * 0.55))
                surface.DrawRect(x - 6, y - 3, math.min(760, 130 + tw), 20)
                draw.DrawText("[" .. (chan.title or "·") .. "]", "GRMRP_ChatChip", x, y - 1,
                    Color(col.r, col.g, col.b, a), TEXT_ALIGN_LEFT)
                local tx = x + 14 + #tostring(chan.title or "·") * 9
                if #ln.name > 0 then
                    draw.DrawText(ln.name .. ":", "GRMRP_ChatChip", tx, y - 1,
                        Color(170, 190, 210, a), TEXT_ALIGN_LEFT)
                    tx = tx + #ln.name * 8 + 10
                end
                draw.DrawText(ln.text, "GRMRP_Chat14", tx, y,
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
