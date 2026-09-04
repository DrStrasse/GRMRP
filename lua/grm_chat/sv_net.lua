--[[ GRMRPChat сервер: cvar'ы, каналы, net-контракт, рассылка.
    Логика — целиком в sh-ядре; этот файл только прикручивает движок.
    Клиент не доверяет себе: всё перечитывается и перепроверяется здесь
    (§5.1.3, урок file_browser).
]]

-- Вечер-14: единая библиотека (см. sh_core). Единственный sv-файл чата:
-- режимский modules/chat/sv_grmrp_chat.lua — форвардер сюда.
if not SERVER then return end
if GRMRPChat and GRMRPChat.__sv then return end
GRMRPChat = GRMRPChat or {}
if not GRMRPChat.__core then
    -- безопасный вход без ядра (кто-то включил sv раньше loadera): ядро
    -- дососедится само, флаг выставит оно же
    if file and file.Exists and file.Exists("grm_chat/sh_core.lua", "LUA") then
        include("grm_chat/sh_core.lua")
    end
end
GRMRPChat.__sv = true

util.AddNetworkString(GRMRPChat.Net.SAY)
util.AddNetworkString(GRMRPChat.Net.MSG)

CreateConVar("grmrp_chat_enable", "1",
    { FCVAR_REPLICATED, FCVAR_ARCHIVE }, "Чат режима: 1 вкл, 0 — возврат к движковому")
-- GRMRPChat.Enabled читает этот реплицируемый cvar; объявлен в shared.lua.
local cvMax = CreateConVar("grmrp_chat_max_chars", "256",
    { FCVAR_REPLICATED, FCVAR_ARCHIVE }, "Максимум байт в сообщении (жёсткий потолок 512)", 1, 512)
local cvRate = CreateConVar("grmrp_chat_rate", "0.35",
    { FCVAR_REPLICATED, FCVAR_ARCHIVE }, "Минимальный интервал между сообщениями, сек", 0, 10)
local cvBurst = CreateConVar("grmrp_chat_burst", "8",
    { FCVAR_REPLICATED, FCVAR_ARCHIVE }, "Сообщений в окне burst, дальше mute", 1, 64)
local cvWindow = CreateConVar("grmrp_chat_window", "10",
    { FCVAR_REPLICATED, FCVAR_ARCHIVE }, "Окно пересчёта burst, сек", 1, 120)
local cvIcRange = CreateConVar("grmrp_chat_ic_range", "700",
    { FCVAR_REPLICATED, FCVAR_ARCHIVE }, "Дальность IC-крика, юнитов", 0, 4096)

-- Каналы объявлены в sh-ядре (общий реестр для обеих сторон). Тут только
-- рантайм-перебивки cvar'ами (см. ProcessLine).

local stateByPlayer = setmetatable({}, { __mode = "k" })
local lastAdvert = setmetatable({}, { __mode = "k" })

local function stateFor(ply)
    local st = stateByPlayer[ply]
    if not st then
        st = {}
        stateByPlayer[ply] = st
    end
    return st
end

local function sendSystem(ply, text)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    net.Start(GRMRPChat.Net.MSG)
        net.WriteString("system")
        net.WriteString(GRMRPChat.Sanitize(text, cvMax:GetInt()))
        net.WriteString("")
        net.WriteDouble(0)
    net.Send(ply)
end
GRMRPChat.SendSystem = sendSystem

-- forcedTargets (вечер-15): явно заданный круг слушателей от вызывающей
-- системы (GRM.RPBroadcast с targets) — для событий с чужой геометрией
-- слышимости (предъявление «только цели», представление «в радиусе модуля»).
-- Радиусные правила канала при этом НЕ применяются (осознанно, не в обход:
-- тот же deliver, та же лента/санитайз — дублирующего пути нет).
local function deliver(chan, author, body, extra, lineOverride, includeAuthor, forcedTargets)
    local now = CurTime()
    local players = player.GetAll()

    local targets, err
    if chan.scope == "pm" then
        local target
        target, err = GRMRPChat.ResolvePmTarget(extra and extra.target or "", players, author)
        if not target then return err, 0 end
        targets = { target }
    elseif forcedTargets then
        targets = forcedTargets
    else
        targets, err = GRMRPChat.ResolveAudience(chan, author, players,
            function(a, b) return a:GetPos():DistToSqr(b:GetPos()) end,
            function(p) return not p:Alive() end)
        if not targets then return err end
    end

    local name = GRMRPChat.Sanitize(author:Name(), GRMRPChat.SUGAR_MAX)
    if lineOverride then body, name = lineOverride, "" end
    -- Автор не получает ретрансляцию: клиент печатает свою строку локально
    -- (оптимистичный эхо-каст; состояния сервер не менял — см. §5.4.3).
    local net_list = {}
    -- Вечер-13 (стенд sv_routing поймал): «includeAuthor» раньше НИЧЕГО не
    -- значило — автор уже был исключён из targets в ResolveAudience, и
    -- /it /try /roll (результат «знает только сервер») не видел САМ автор:
    -- ни локального эха (echo=false в клиенте), ни серверной строки. Теперь
    -- флаг явно ставит автора в начало списка.
    if includeAuthor then table.insert(net_list, author) end
    for i = 1, #targets do
        if targets[i] ~= author then
            table.insert(net_list, targets[i])
        end
    end
    if #net_list > 0 then
        net.Start(GRMRPChat.Net.MSG)
            net.WriteString(chan.id)
            net.WriteString(name)
            net.WriteString(body)
            net.WriteDouble(now)
        net.Send(net_list)
    end
    return nil, #targets
end

-- Состояние /do → контекст для /it (слабые ключи: утечек нет, §5.1.5).
local lastDo = setmetatable({}, { __mode = "k" })

-- opts (вечер-13): echoAuthor — ретранслировать строку и автору (серверные
-- события: показ документов; у клиентского ввода эхо локальное, не надо);
-- rpName — RP-имя вместо steam-ника; range — радиус события (400 у бланков).
function GRMRPChat.RPAction(kind, ply, body, chanId, opts)
    local def = GRMRPChat.RP[kind]
    if not def then return nil end
    local chan = table.Copy(GRMRPChat.GetChannel(def.chan) or GRMRPChat.GetChannel(chanId))
    if not chan then return "нет канала отыгровки" end
    chan.range = (opts and tonumber(opts.range)) or cvIcRange:GetFloat()
    local authorName
    if opts and isstring(opts.rpName) and #opts.rpName > 0 then
        authorName = GRMRPChat.Sanitize(opts.rpName, GRMRPChat.SUGAR_MAX)
    else
        authorName = GRMRPChat.Sanitize(ply:Name(), GRMRPChat.SUGAR_MAX)
    end

    if kind == "me" then
        -- Вечер-13: ветки «me» НЕ БЫЛО ВООБЩЕ — /me и серверные отыгровки
        -- проваливались в пустоту: получатель видел «* ...» только если
        -- строка шла через чужие каналы (старый RPChat/EasyChat), т.е.
        -- либо дубль, либо ничего. Стенд sim_chat_sv_routing закрывает дыру.
        local forced
        if opts and istable(opts.targets) and #opts.targets > 0 then
            forced = opts.targets
        end
        return deliver(chan, ply, body, nil, def.fmt(authorName, body, nil),
            opts and opts.echoAuthor == true, forced)
    end

    if kind == "do" then
        local audience = GRMRPChat.ResolveAudience(chan, ply, player.GetAll(),
            function(a, b) return a:GetPos():DistToSqr(b:GetPos()) end,
            function(p) return not p:Alive() end)
        if not audience then return "некого вокруг" end
        for i = 1, #audience do
            if audience[i] ~= ply then lastDo[audience[i]] = { by = ply, name = authorName, t = CurTime() } end
        end
        return deliver(chan, ply, body, nil, def.fmt(authorName, body, nil), false)
    end

    if kind == "it" then
        local ctx = lastDo[ply]
        if not ctx or not IsValid(ctx.by) or CurTime() - ctx.t > 90 then
            sendSystem(ply, "свежего /do рядом не было — отвечать не на что")
            return nil
        end
        return deliver(chan, ply, body, nil, def.fmt(authorName, body, { to = ctx.name }), true)
    end

    if kind == "try" then
        local roll = math.random(1, 100)
        return deliver(chan, ply, body, nil,
            def.fmt(authorName, body, { roll = roll, ok = roll <= 50 }), true)
    end

    if kind == "roll" then
        local max = GRMRPChat.RollSpec(body)
        local roll = math.random(1, max)
        return deliver(chan, ply, body, nil,
            def.fmt(authorName, body, { roll = roll, max = max }), true)
    end

    return nil
end

-- Единая точка входа: PlayerSay и net-поле ввода идут через неё.
function GRMRPChat.ProcessLine(ply, text, defaultChannel)
    if not GRMRPChat.Enabled() then return end

    -- Вечер-12: «/binder» и прочие команды модулей, набранные в НАШЕМ вводе
    -- (net-путь, мимо PlayerSay), уходят в общую цепочку — иначе окно биндера
    -- открывалось только из движкового say. Префиксная сверка: кириллические
    -- алиасы (/бинды) вне %w_. Ре-ентерь GM:PlayerSay гасит флаг _inExternal.
    if string.sub(text, 1, 1) == "/" and GRMRPChat.ExternalCommands
        and next(GRMRPChat.ExternalCommands) then
        local low = string.lower(text)
        local hit
        for c in pairs(GRMRPChat.ExternalCommands) do
            if string.sub(low, 1, #c) == c then hit = true break end
        end
        if hit then
            GRMRPChat._inExternal = true
            local okh, ret = pcall(hook.Run, "PlayerSay", ply, text, defaultChannel == "ooc", false)
            GRMRPChat._inExternal = nil
            if (not okh) or ret == nil or ret == "" then return "" end
            text = ret
        end
    end

    local now = CurTime()
    local st = stateFor(ply)
    local ok, warn = GRMRPChat.LadderCheck(st, now, cvRate:GetFloat(),
        cvBurst:GetInt(), cvWindow:GetInt())
    if warn then sendSystem(ply, warn) end
    if not ok then return "" end

    local chanId, body, extra = GRMRPChat.ParseSay(text, defaultChannel or "ic")
    if not chanId then
        if body == "empty" then return "" end -- пробелы: съедено молча
        sendSystem(ply, body) -- ParseSay вернул причину во втором значении
        -- (в т.ч. «неизвестная команда»: подсказка — наша, стенд sv_routing
        -- веч.-13; движку строку не отдаём — дубля ванильным say нет)
        return ""
    end
    body = GRMRPChat.Sanitize(body, cvMax:GetInt())
    if #body == 0 and not (extra and GRMRPChat.RP[extra.cmd or ""]) then return "" end

    -- RP-действия (/me /do /it /try /roll): своя форма строки, тот же
    -- аудиторный путь (один владелец — deliver).
    local kind = extra and extra.cmd
    if kind and GRMRPChat.RP[kind] then
        if #body == 0 and kind ~= "roll" then
            -- одинокий «/me» без действия не должен рождать пустую строку
            -- «* Ник » у половины сервера (стенд sv_routing)
            sendSystem(ply, "/" .. kind .. ": опишите действие после команды")
            return ""
        end
        local err = GRMRPChat.RPAction(kind, ply, body, chanId)
        if err then sendSystem(ply, err) end
        return ""
    end

    local chan = GRMRPChat.GetChannel(chanId)
    if not chan then sendSystem(ply, "канал не найден") return "" end

    if chan.cooldown > 0 then
        local last = lastAdvert[ply] or 0
        if now - last < chan.cooldown then
            sendSystem(ply, string.format("%s: подождите %d сек",
                chan.title, math.ceil(chan.cooldown - (now - last))))
            return ""
        end
        lastAdvert[ply] = now
    end

    if chanId == "ic" or chanId == "me" then
        chan = table.Copy(chan)
        chan.range = cvIcRange:GetFloat()
    end

    local err, heard = deliver(chan, ply, body, extra)
    if err then sendSystem(ply, err) return "" end
    -- Вечер-16 (Код 88.1 переехал из легаси-модуля): молчание локального
    -- канала видно — автор получает системную строку, а не «сообщение
    -- пропало». Троттл 8 с (диалог-пустышка не спамит).
    if chanId == "ic" and heard == 0 and (st.soloHintT or 0) + 8 <= now then
        st.soloHintT = now
        sendSystem(ply, "рядом никого нет — вас никто не слышит (радиус ~"
            .. tostring(math.floor(cvIcRange:GetFloat()))
            .. " юн). Глобально: /ooc, лично: /pm <ник> <текст>")
    end
    return ""
end

function GRMRPChat.OnPlayerSay(ply, text, teamChat, isDead)
    if not IsValid(ply) then return end
    return GRMRPChat.ProcessLine(ply, text, isDead and "dead" or (teamChat and "ooc" or "ic"))
end

-- Ввод из нашего окна. Тот же ProcessLine — дублирование запрещено (§5.2).
net.Receive(GRMRPChat.Net.SAY, function(len, ply)
    local sel = string.sub(net.ReadString(), 1, GRMRPChat.SUGAR_MAX)
    local text = net.ReadString()
    text = string.sub(text, 1, GRMRPChat.HARD_MAX * 2) -- физрежем ДО ядра
    if not GRMRPChat.GetChannel(sel) then sel = "ic" end -- канал — реестр, не доверие
    GRMRPChat.ProcessLine(ply, text, sel)
end)

hook.Add("PlayerDisconnect", "GRMRPChat", function(ply)
    stateByPlayer[ply] = nil
    lastAdvert[ply] = nil
end)

-- Вечер-14: единый вход PlayerSay для ВСЕХ серверов. Режим помечает свой
-- GM:PlayerSay (GM.__chatOwnsPlayerSay) — хук уступает, двойной обработки
-- нет. Серверы на другом геймоде получают чат библиотекой «как EasyChat»:
-- через хук, без правок геймода.
hook.Add("PlayerSay", "GRMRPChat_Capture", function(ply, text, teamChat, isDead)
    if GAMEMODE and GAMEMODE.__chatOwnsPlayerSay then return end
    if GRMRPChat._inExternal then return "" end -- ре-ентерь цепочки: съедено
    return GRMRPChat.OnPlayerSay(ply, text, teamChat, isDead)
end)

-- Вечер-14: поздняя страховка смешанных установок (перерегистрация чужих
-- хуков после reload):
if isfunction(GRMRPChat.SuppressForeignChat) then
    GRMRPChat.SuppressForeignChat()
end
