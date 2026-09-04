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

-- Вечер-12.2: гранично-безопасная обрезка наружу (клиентский ввод режет
-- 512 ЭТИМ, а не сырым string.sub — иначе кириллица на границе превращается
-- в «битый хвост», ровно класс жалоб «плохо обрабатывает текст»).
GRMRPChat.Utf8Cut = utf8Clamp

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

function GRMRPChat.EmojiPass(text)
    for i = 1, #EMOJI do
        text = replaceAll(text, EMOJI[i][1], EMOJI[i][2])
    end
    return text
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
    s = GRMRPChat.EmojiPass(s) -- "<3" жив: углы разворачиваем ПОСЛЕ эмодзи-паса
    s = s:gsub("<", "＜"):gsub(">", "＞")
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
            if #c > 0 and #c <= GRMRPChat.SUGAR_MAX then chan.cmds[c] = true end
        end
    end
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
-- cmd="dead" (вечер-13, ловля sv_routing): без алиаса «/dead текст» падал в
-- «неизвестная команда», хотя канал dead есть — добраться до него можно было
-- только безслэшевым вводом мертвеца.
GRMRPChat.RegisterChannel("dead", {
    title = "Мертвечина", scope = "range", range = 400, onlyDead = true,
    cmd = "dead", color = { r = 240, g = 90, b = 90 }
})
GRMRPChat.RegisterChannel("ooc", {
    title = "OOC", scope = "world", cmd = "ooc",
    color = { r = 120, g = 210, b = 255 }
})
GRMRPChat.RegisterChannel("me", {
    title = "Отыгровка", scope = "range", cmd = "me",
    cmds = { "do", "it", "try" },
    color = { r = 255, g = 185, b = 63 }
})
GRMRPChat.RegisterChannel("dice", {
    title = "Кости", scope = "range", cmd = "roll", allowEmpty = true,
    color = { r = 120, g = 240, b = 200 }
})
GRMRPChat.RegisterChannel("advert", {
    title = "Объявление", scope = "world", cmd = "advert", cooldown = 60,
    color = { r = 190, g = 120, b = 255 }
})
GRMRPChat.RegisterChannel("pm", {
    title = "Личное", scope = "pm", cmd = "pm",
    color = { r = 64, g = 222, b = 147 }
})

-- RP-формат: один источник строк для серверной рассылки и клиентского
-- превью (предпоказ = то же самое, что увидят остальные; честность §5.1.3).
-- Вечер-12 (чат ↔ модули, «чат должен взаимодействовать с биндером»):
-- реестр slash-команд, которые принадлежат АДОНАМ (биндер и др.). Чат их не
-- парсит и не казнит как «неизвестные»: серверный ProcessLine отдаёт такие
-- строки общей цепочке PlayerSay, а клиентский ввод ведёт их через движковый
-- say — перехватчики аддонов срабатывают и из нашего окна ввода.
GRMRPChat.ExternalCommands = GRMRPChat.ExternalCommands or {}
function GRMRPChat.RegisterExternalChatCommand(name)
    name = string.lower(tostring(name or ""))
    if name == "" then return false end
    if string.sub(name, 1, 1) ~= "/" then name = "/" .. name end
    GRMRPChat.ExternalCommands[name] = true
    return true
end

-- Единый словарь отыгровок наружу: биндер сверяет пресеты/шаги с НИМ, а не
-- со своим домыслом («синхронизация с /me и другими командами», вечер-12).
function GRMRPChat.RPCommandNames()
    local out = {}
    for k in pairs(GRMRPChat.RP or {}) do out[#out + 1] = "/" .. k end
    table.sort(out)
    return out
end

GRMRPChat.RP = {
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

function GRMRPChat.RollSpec(body)
    local num = tonumber(string.match(tostring(body or ""), "%d+"))
    if not num then num = 100 end
    return math.Clamp(math.floor(num), 2, 10000)
end

-- Строка предпросмотра для поля ввода (клиент, чистая функция).
function GRMRPChat.PreviewText(name, raw, selChan)
    raw = tostring(raw or "")
    if #raw == 0 then return "" end
    local cmdRaw, body = raw:match("^/([%w_]+)%s*(.*)$")
    if not cmdRaw then
        local chan = selChan and GRMRPChat.GetChannel(selChan)
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
    local def = GRMRPChat.RP[cmd]
    if def then return def.fmt(name, body, { self = true }) end
    for _, chan in pairs(GRMRPChat.Channels) do
        if chan.cmd == cmd or (chan.cmds and chan.cmds[cmd]) then
            return "[" .. chan.title .. "] " .. name .. ": " .. body
        end
    end
    return "⚠ /" .. cmd .. " — неизвестная команда"
end

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
                -- Вечер-12.2 сверка с контрактом веч.-8 (стенд «everyone
                -- ALIVE hears» пиновал его намеренно): мирские каналы — для
                -- живых, мертвец живёт в dead-чате. Мёртвый слушатель тут
                -- НЕ лишний — это политика, а не дефект: не меняем.
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
            -- Вечер-13 (стенд sv_routing): на движке ply.Name — МЕТОД,
            -- прежний tostring(ply.Name) давал «function: 0x…»: /pm по нику
            -- не находил НИКОГО, только по SteamID64. Кириллица тоже жива:
            -- lower — байтовый, но для совпадения достаточно обеих сторон.
            local name
            if isfunction(ply.Name) then
                name = tostring(ply:Name())
            else
                name = tostring(ply.Name
                    or (isfunction(ply.Nick) and ply:Nick() or ""))
            end
            name = string.lower(name)
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

-----------------------------------------------------------------------
-- Вечер-13: КОРЕНЬ «всё тех же ошибок» на живом сервере. Песочный порт
-- (аддон GRMChat — машиногенная копия этого модуля) самоотключался по
-- `if GRMRP.Version` В МОМЕНТ СВОЕЙ ЗАГРУЗКИ — а GMod исполняет
-- lua/autorun аддонов ДО файлов режима, значит условие было ложным ВСЕГДА.
-- На GRMRP-сервере жили ДВА чата: вторая Y-полоса, две ленты в одной
-- точке, перехваченный портом chat.AddText (строки документов/анонсов
-- утекали в чужую панель) и общий файл истории в DATA. Порт обязан быть
-- мёртв, когда чат режима загрузился: снимаем всё, что он зарегистрировал
-- (все его id начинаются с «GRMChat» — префикс зафиксирован генератором),
-- вешаем таймеры и команды.
-----------------------------------------------------------------------
function GRMRPChat.SuppressAddonPort()
    local port = rawget(_G, "GRMChat")
    if type(port) ~= "table" then return false end
    port.SUPPRESSED = true
    local removed = 0
    if hook and hook.GetTable then
        -- Вечер-13: префиксов ДВА. «GRMChat*» — песочный порт; «GRM_RPChat*» —
        -- СТАРЫЙ модуль rp_chat, его PlayerSay возвращал "" и съедал РЯД
        -- целиком (на GRMRP-серверах с живым портом GM:PlayerSay не вызывался
        -- никогда); его же лента лезла в AddText вторым слоем.
        local PREFIXES = { "^GRMChat", "^GRM_RPChat" }
        local doomed = {}
        for name, byId in pairs(hook.GetTable()) do
            for id in pairs(byId) do
                if type(id) == "string" then
                    for _, pat in ipairs(PREFIXES) do
                        if string.find(id, pat, 1, true) then
                            doomed[#doomed + 1] = { name, id }
                            break
                        end
                    end
                end
            end
        end
        for i = 1, #doomed do
            pcall(hook.Remove, doomed[i][1], doomed[i][2])
            removed = removed + 1
        end
    end
    if timer and timer.Remove then
        for _, t in ipairs({ "GRMChat_HistSave", "GRMChat_InpSave", "GRMChat_HistRefr" }) do
            pcall(timer.Remove, t)
        end
    end
    -- консольные команды порта СОВПАДАЮТ по именам с нашими (grm_chat_*) —
    -- удаляем только для того, чтобы перерегистрировать свои (ниже по этому
    -- же пути), а не из-за конфликта владельцев.
    if concommand and concommand.Remove then
        for _, c in ipairs({ "grm_chat_open", "grm_chat_save", "grm_chat_clear",
            "grm_rpchat_help" }) do
            pcall(concommand.Remove, c)
        end
    end
    GRMRPChat.PORT_SUPPRESSED = true
    if not GRMRPChat._suppressPrinted then
        GRMRPChat._suppressPrinted = true
        print(("[GRMRPChat] песочный порт чата подавлен (%d хуков) — режим единственный владелец")
            :format(removed))
    end
    return true
end

do
    GRMRPChat.SuppressAddonPort()
end
