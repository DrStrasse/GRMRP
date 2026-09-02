-- СГЕНЕРИРОВАНО tools/sync_chat_addon.py — источник: sh_grmrp_chat_core.lua
-- Не править руками: изменения вносите в файл режима и перегенерируйте
-- (`python3 tools/sync_chat_addon.py`); расхождение ловит --check.
--[[ GRMChat — аддонский мутированный порт чат-модуля режима (тот же код,
    другие имена). На серверах с gamemode GRMRP модуль молча выключается
    целиком: чат режима — единственный владелец, дублей net-имён/cvar'ов/
    перехвата PlayerSay не возникает никогда.
]]
if GRMRP and GRMRP.Version then return end

GRMChat = GRMChat or {}
GRMChat.Net = { SAY = "grm/chat_say", MSG = "grm/chat_msg" }

function GRMChat.ErrorNoHalt(...)
    if MsgC then
        MsgC(Color(244, 78, 96), "[GRMChat] ", Color(250, 185, 63), ...)
    end
end

GRMChat = GRMChat or {}

GRMChat.HARD_MAX = 512          -- жёсткий потолок байт (серверный закон)
GRMChat.SUGAR_MAX = 64          -- потолок «сладких» слов (ник/канал/адресат)

-- Управляющие символы вырезаются ДО всего остального; "<" ">" зеркалятся
-- — защита markup-инъекции: клиент экранировать больше не обязан,
-- единственный владелец санитайза — этот файл.
local STRIP = {}
for i = 0, 31 do STRIP[i] = true end
STRIP[127] = true -- DEL; байты 0x80+ трогать нельзя — это continuation UTF-8

local function utf8Clamp(s, maxBytes)
    if #s <= maxBytes then return s end
    local lastEnd, i = 0, 1
    while i <= maxBytes do
        local b = string.byte(s, i)
        local extra = 0
        if b >= 194 and b < 224 then extra = 1
        elseif b >= 224 and b < 240 then extra = 2
        elseif b >= 240 and b < 248 then extra = 3 end
        --goto! Парсер GMod не знает goto/labels (урок sh_grm_arrest.lua:285)
        local orphan = b >= 128 and b < 194 -- continuation без пары — просто шаг
        if not orphan and i + extra <= maxBytes then
            lastEnd = i + extra
        end
        i = i + extra + 1
    end
    if lastEnd == 0 then return "" end
    return string.sub(s, 1, lastEnd)
end

-- Эмодзи: текстовые смайлы заменяются живыми символами, готовые многобайтные
-- символы sanitize и так сохраняет (продовольствие UTF-8-safe). Дёшево и
-- чисто: ровно те же данные видит превью клиента и лента сервера.
local EMOJI = {
    { ":)", "🙂" }, { "(:", "🙂" }, { "=)", "🙂" },
    { ":-)", "🙂" }, { ":(", "🙁" }, { ":-(", "🙁" },
    { ":D", "😃" }, { ":-D", "😃" }, { ";)", "😉" }, { ";-)", "😉" },
    { ":P", "😛" }, { ":-P", "😛" }, { ":o", "😮" }, { ":O", "😮" },
    { "<3", "❤" }, { "</3", "💔" }, { "+1", "👍" }, { "-1", "👎" },
    { ":fire:", "🔥" }, { ":skull:", "💀" }, { "xD", "😆" }
}

local function replaceAll(text, from, to)
    local out, i, n = {}, 1, #text
    local fl = #from
    while true do
        local a2, b2 = string.find(text, from, i, true)
        if not a2 then
            table.insert(out, string.sub(text, i))
            break
        end
        table.insert(out, string.sub(text, i, a2 - 1))
        table.insert(out, to)
        i = b2 + 1
        if fl == 0 then break end
    end
    return table.concat(out)
end

function GRMChat.EmojiPass(text)
    for i = 1, #EMOJI do
        text = replaceAll(text, EMOJI[i][1], EMOJI[i][2])
    end
    return text
end

function GRMChat.Sanitize(text, maxBytes)
    text = tostring(text or "")
    local limit = math.Clamp(tonumber(maxBytes) or GRMChat.HARD_MAX, 1, GRMChat.HARD_MAX)
    local out = {}
    local i, n = 1, #text
    while i <= n do
        local b = string.byte(text, i)
        if STRIP[b] then
            if b == 9 or b == 10 or b == 13 then table.insert(out, " ") end
            -- управляющий — в помойку
        elseif b == 226 and string.byte(text, i + 1) == 128
            and string.byte(text, i + 2) == 137 then
            table.insert(out, " ")          -- NBSP → обычный пробел
            i = i + 2
        else
            table.insert(out, string.char(b))
        end
        i = i + 1
    end
    local s = table.concat(out)
    s = s:gsub("[ \t]+", " ")
    s = s:gsub("^ +", "")
    s = s:gsub(" +$", "")
    s = GRMChat.EmojiPass(s) -- "<3" жив: углы разворачиваем ПОСЛЕ эмодзи-паса
    s = s:gsub("<", "＜"):gsub(">", "＞")
    return utf8Clamp(s, limit)
end

-- Таблица каналов: объявление = данные (декларативность DarkRP + наш
-- реестр). scope: "range" | "world" | "pm"; onlyDead — слушают только мертвые.
GRMChat.Channels = {}

function GRMChat.RegisterChannel(id, spec)
    if not isstring(id) or #id == 0 or #id > GRMChat.SUGAR_MAX then return nil, "bad id" end
    if not istable(spec) then return nil, "bad spec" end
    if GRMChat.Channels[id] then return nil, "duplicate channel " .. id end
    spec = spec or {}
    local col = istable(spec.color) and spec.color or {}
    local chan = {
        id = id,
        title = string.sub(tostring(spec.title or id), 1, 32),
        cmd = spec.cmd and string.sub(tostring(spec.cmd), 1, GRMChat.SUGAR_MAX) or nil,
        allowEmpty = spec.allowEmpty == true,
        color = {
            r = math.Clamp(tonumber(col.r) or 255, 0, 255),
            g = math.Clamp(tonumber(col.g) or 255, 0, 255),
            b = math.Clamp(tonumber(col.b) or 255, 0, 255)
        },
        scope = (spec.scope == "world" or spec.scope == "pm") and spec.scope or "range",
        range = math.Clamp(tonumber(spec.range) or 700, 0, 4096),
        onlyDead = spec.onlyDead == true,
        cooldown = math.Clamp(tonumber(spec.cooldown) or 0, 0, 300)
    }
    if istable(spec.cmds) then
        chan.cmds = {}
        for i = 1, #spec.cmds do
            local c = string.lower(tostring(spec.cmds[i] or ""))
            if #c > 0 and #c <= GRMChat.SUGAR_MAX then chan.cmds[c] = true end
        end
    end
    GRMChat.Channels[id] = chan
    return chan
end

function GRMChat.GetChannel(id)
    return GRMChat.Channels[tostring(id)]
end

-- Каналы режима — ОБЩАЯ декларация (не sv!): клиент строит по этому же
-- реестру чипы ввода и цвета ленты; сервер — маршрутизацию. Дальность ic
-- перебивается cvar'ом на сервере при разборе (sv-обвязка).
GRMChat.RegisterChannel("ic", {
    title = "Крик", scope = "range", cmd = "w",
    color = { r = 235, g = 235, b = 235 }
})
GRMChat.RegisterChannel("dead", {
    title = "Мертвечина", scope = "range", range = 400, onlyDead = true,
    color = { r = 240, g = 90, b = 90 }
})
GRMChat.RegisterChannel("ooc", {
    title = "OOC", scope = "world", cmd = "ooc",
    color = { r = 120, g = 210, b = 255 }
})
GRMChat.RegisterChannel("me", {
    title = "Отыгровка", scope = "range", cmd = "me",
    cmds = { "do", "it", "try" },
    color = { r = 255, g = 185, b = 63 }
})
GRMChat.RegisterChannel("dice", {
    title = "Кости", scope = "range", cmd = "roll", allowEmpty = true,
    color = { r = 120, g = 240, b = 200 }
})
GRMChat.RegisterChannel("advert", {
    title = "Объявление", scope = "world", cmd = "advert", cooldown = 60,
    color = { r = 190, g = 120, b = 255 }
})
GRMChat.RegisterChannel("pm", {
    title = "Личное", scope = "pm", cmd = "pm",
    color = { r = 64, g = 222, b = 147 }
})

-- RP-формат: один источник строк для серверной рассылки и клиентского
-- превью (предпоказ = то же самое, что увидят остальные; честность §5.1.3).
GRMChat.RP = {
    me = { chan = "me", fmt = function(n, b)
        return "* " .. n .. " " .. b
    end },
    ["do"] = { chan = "me", fmt = function(n, b, ctx)
        if ctx and ctx.self then return "* " .. b .. " (возле вас)" end
        return "* " .. b .. " (возле " .. n .. ")"
    end },
    it = { chan = "me", echo = true, fmt = function(n, b, ctx)
        if ctx and ctx.to then return "* " .. b .. " (в ответ " .. ctx.to .. ")" end
        return "* " .. b
    end },
    try = { chan = "me", echo = true, fmt = function(n, b, ctx)
        local res = ctx and (ctx.ok and "успех" or "не вышло") or "?"
        return "* " .. n .. " пробует «" .. b .. "» → " ..
            tostring(ctx and ctx.roll or "?") .. " — " .. res
    end },
    roll = { chan = "dice", echo = true, fmt = function(n, b, ctx)
        return "🎲 " .. n .. " кидает 1.." .. tostring(ctx and ctx.max or 100) ..
            " → " .. tostring(ctx and ctx.roll or "?")
    end }
}

function GRMChat.RollSpec(body)
    local num = tonumber(string.match(tostring(body or ""), "%d+"))
    if not num then num = 100 end
    return math.Clamp(math.floor(num), 2, 10000)
end

-- Строка предпросмотра для поля ввода (клиент, чистая функция).
function GRMChat.PreviewText(name, raw, selChan)
    raw = tostring(raw or "")
    if #raw == 0 then return "" end
    local cmdRaw, body = raw:match("^/([%w_]+)%s*(.*)$")
    if not cmdRaw then
        local chan = selChan and GRMChat.GetChannel(selChan)
        if chan and chan.cmd ~= "w" then
            return "[" .. chan.title .. "] " .. name .. ": " .. raw
        end
        return name .. ": " .. raw
    end
    local cmd = string.lower(cmdRaw)
    if cmd == "pm" then
        return "📩 " .. (body:match("^(%S+)") or "?") .. ": " ..
            (string.gsub(body, "^%S+%s*", "", 1) or "")
    end
    local def = GRMChat.RP[cmd]
    if def then return def.fmt(name, body, { self = true }) end
    for _, chan in pairs(GRMChat.Channels) do
        if chan.cmd == cmd or (chan.cmds and chan.cmds[cmd]) then
            return "[" .. chan.title .. "] " .. name .. ": " .. body
        end
    end
    return "⚠ /" .. cmd .. " — неизвестная команда"
end

-- Разбор строки PlayerSay: "/cmd text" → канал+тело; без слэша — defChan.
-- Возвращает (channelID, body, extra) либо (nil, причина).
function GRMChat.ParseSay(text, defChan)
    text = GRMChat.Sanitize(text, GRMChat.HARD_MAX)
    if #text == 0 then return nil, "empty" end

    local cmdRaw, body = text:match("^/([%w_]+)%s*(.*)$")
    if not cmdRaw then return defChan, text, nil end
    local cmd = string.lower(cmdRaw)

    if cmd == "pm" then
        local target, rest = body:match("^(%S+)%s*(.*)$")
        if not target or #rest == 0 then return nil, "использование: /pm <ник> <текст>" end
        return "pm", rest, { target = target }
    end

    for id, chan in pairs(GRMChat.Channels) do
        if chan.cmd == cmd or (chan.cmds and chan.cmds[cmd]) then
            if chan.scope ~= "world" and #body == 0 and not chan.allowEmpty then
                return nil, "пустое сообщение в /" .. cmd
            end
            return id, body, { cmd = cmd }
        end
    end

    return nil, "неизвестная команда /" .. cmd
end

-- Лестница нарушений (FPP 4.11.3): предупреждение → mute с экспоненциальным
-- ростом и потолком; декей окна — sliding count, без буферов-окон.
-- state = {hits, lastHit, lastAny, penalty, muteUntil} (персист per-player).
-- Возврат: (ok, warn, muteUntil).
function GRMChat.LadderCheck(state, now, rate, burst, window)
    rate = rate or 0.35
    burst = burst or 8
    window = window or 10

    if state.muteUntil and state.muteUntil > now then
        return false, nil, state.muteUntil
    end

    if now - (state.lastHit or 0) >= window then
        state.hits = 0
    end
    state.lastHit = now
    state.hits = (state.hits or 0) + 1

    local function punish(reason)
        state.penalty = (state.penalty or 0) + 1
        local mute = now + math.min(180, 10 * (2 ^ math.min(state.penalty, 5)))
        state.muteUntil = mute
        return false, reason, mute
    end

    if state.lastAny and now - state.lastAny < rate then
        return punish("флуд: чат притихнет на время")
    end
    state.lastAny = now

    if state.hits > burst then
        return punish("скорость сообщений выше пределов")
    end
    if state.hits == burst then
        return true, "не флуди — дальше включится кулдаун", nil
    end

    return true, nil, nil
end

-- Аудитория автора в канале. distSqrFn/isDeadFn — инжектируемые (стенд!).
function GRMChat.ResolveAudience(chan, author, players, distSqrFn, isDeadFn)
    if not chan then return nil, "нет канала" end
    if chan.scope == "pm" then return nil, "pm требует адресата" end

    local authorDead = isDeadFn and isDeadFn(author) or false
    if authorDead and not chan.onlyDead then return nil, "мертвым доступен только dead-чат" end
    if not authorDead and chan.onlyDead then return nil, "живым тут не место" end

    local list = {}
    local r2 = chan.range * chan.range
    for i = 1, #players do
        local ply = players[i]
        if ply ~= author then
            local dead = isDeadFn and isDeadFn(ply) or false
            if chan.scope == "world" then
                if not dead or chan.onlyDead or dead == authorDead then
                    table.insert(list, ply)
                end
            elseif dead == authorDead and distSqrFn(author, ply) <= r2 then
                table.insert(list, ply)
            end
        end
    end
    return list, nil
end

-- Разрешение "/pm <query>": точный SteamID64 → уникальное вхождение ника
-- (непрефиксные совпадения — отказ, без «первого попавшегося»).
function GRMChat.ResolvePmTarget(query, players, selfPly)
    query = string.lower(GRMChat.Sanitize(query, GRMChat.SUGAR_MAX))
    if #query == 0 then return nil, "пустой адресат" end
    for i = 1, #players do
        local ply = players[i]
        if ply ~= selfPly and ply.SteamID64 and tostring(ply.SteamID64) == query then
            return ply, nil
        end
    end
    local found, ambiguous = nil, false
    for i = 1, #players do
        local ply = players[i]
        if ply ~= selfPly then
            local name = string.lower(tostring(ply.Name or ""))
            if name:find(query, 1, true) then
                if found then ambiguous = true break end
                found = ply
            end
        end
    end
    if ambiguous then return nil, "адресат неоднозначен" end
    if found then return found, nil end
    return nil, "игрок не найден"
end
