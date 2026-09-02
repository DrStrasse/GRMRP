--[[ GRMRPChat — чистые функции чата: санитайз, разбор, лестница нарушений,
    разрешение адресатов. Ни одной движковой зависимости — весь файл
    прогоняется стендом tools/luatest/sim_grmrp_chat.lua (урок
    «нормализатор с отказом», WIKI 4.9.1 + control-chars EasyChat 4.21.3).
]]

GRMRPChat = GRMRPChat or {}

GRMRPChat.HARD_MAX = 512          -- жёсткий потолок байт (серверный закон)
GRMRPChat.SUGAR_MAX = 64          -- потолок «сладких» слов (ник/канал/адресат)

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
        elseif b >= 240 and b < 248 then extra = 3
        elseif b >= 128 and b < 192 then
            i = i + 1 -- осиротевший continuation — не расширяем
            goto continue
        end
        if i + extra > maxBytes then break end
        lastEnd = i + extra
        i = i + extra + 1
        ::continue::
    end
    if lastEnd == 0 then return "" end
    return string.sub(s, 1, lastEnd)
end

function GRMRPChat.Sanitize(text, maxBytes)
    text = tostring(text or "")
    local limit = math.Clamp(tonumber(maxBytes) or GRMRPChat.HARD_MAX, 1, GRMRPChat.HARD_MAX)
    local out = {}
    local i, n = 1, #text
    while i <= n do
        local b = string.byte(text, i)
        if STRIP[b] then
            if b == 9 or b == 10 or b == 13 then table.insert(out, " ") end
            -- управляющий — в помойку
        elseif b == 60 then
            table.insert(out, "＜")
        elseif b == 62 then
            table.insert(out, "＞")
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
    return utf8Clamp(s, limit)
end

-- Таблица каналов: объявление = данные (декларативность DarkRP + наш
-- реестр). scope: "range" | "world" | "pm"; onlyDead — слушают только мертвые.
GRMRPChat.Channels = {}

function GRMRPChat.RegisterChannel(id, spec)
    if not isstring(id) or #id == 0 or #id > GRMRPChat.SUGAR_MAX then return nil, "bad id" end
    if not istable(spec) then return nil, "bad spec" end
    if GRMRPChat.Channels[id] then return nil, "duplicate channel " .. id end
    spec = spec or {}
    local col = istable(spec.color) and spec.color or {}
    local chan = {
        id = id,
        title = string.sub(tostring(spec.title or id), 1, 32),
        cmd = spec.cmd and string.sub(tostring(spec.cmd), 1, GRMRPChat.SUGAR_MAX) or nil,
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
    GRMRPChat.Channels[id] = chan
    return chan
end

function GRMRPChat.GetChannel(id)
    return GRMRPChat.Channels[tostring(id)]
end

-- Каналы режима — ОБЩАЯ декларация (не sv!): клиент строит по этому же
-- реестру чипы ввода и цвета ленты; сервер — маршрутизацию. Дальность ic
-- перебивается cvar'ом на сервере при разборе (sv-обвязка).
GRMRPChat.RegisterChannel("ic", {
    title = "Крик", scope = "range", cmd = "w",
    color = { r = 235, g = 235, b = 235 }
})
GRMRPChat.RegisterChannel("dead", {
    title = "Мертвечина", scope = "range", range = 400, onlyDead = true,
    color = { r = 240, g = 90, b = 90 }
})
GRMRPChat.RegisterChannel("ooc", {
    title = "OOC", scope = "world", cmd = "ooc",
    color = { r = 120, g = 210, b = 255 }
})
GRMRPChat.RegisterChannel("me", {
    title = "Отыгровка", scope = "range", cmd = "me",
    color = { r = 255, g = 185, b = 63 }
})
GRMRPChat.RegisterChannel("advert", {
    title = "Объявление", scope = "world", cmd = "advert", cooldown = 60,
    color = { r = 190, g = 120, b = 255 }
})
GRMRPChat.RegisterChannel("pm", {
    title = "Личное", scope = "pm", cmd = "pm",
    color = { r = 64, g = 222, b = 147 }
})

-- Разбор строки PlayerSay: "/cmd text" → канал+тело; без слэша — defChan.
-- Возвращает (channelID, body, extra) либо (nil, причина).
function GRMRPChat.ParseSay(text, defChan)
    text = GRMRPChat.Sanitize(text, GRMRPChat.HARD_MAX)
    if #text == 0 then return nil, "empty" end

    local cmdRaw, body = text:match("^/([%w_]+)%s*(.*)$")
    if not cmdRaw then return defChan, text, nil end
    local cmd = string.lower(cmdRaw)

    if cmd == "pm" then
        local target, rest = body:match("^(%S+)%s*(.*)$")
        if not target or #rest == 0 then return nil, "использование: /pm <ник> <текст>" end
        return "pm", rest, { target = target }
    end

    for id, chan in pairs(GRMRPChat.Channels) do
        if chan.cmd == cmd then
            if chan.scope ~= "world" and #body == 0 then
                return nil, "пустое сообщение в /" .. cmd
            end
            return id, body, nil
        end
    end

    return nil, "неизвестная команда /" .. cmd
end

-- Лестница нарушений (FPP 4.11.3): предупреждение → mute с экспоненциальным
-- ростом и потолком; декей окна — sliding count, без буферов-окон.
-- state = {hits, lastHit, lastAny, penalty, muteUntil} (персист per-player).
-- Возврат: (ok, warn, muteUntil).
function GRMRPChat.LadderCheck(state, now, rate, burst, window)
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
function GRMRPChat.ResolveAudience(chan, author, players, distSqrFn, isDeadFn)
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
function GRMRPChat.ResolvePmTarget(query, players, selfPly)
    query = string.lower(GRMRPChat.Sanitize(query, GRMRPChat.SUGAR_MAX))
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
