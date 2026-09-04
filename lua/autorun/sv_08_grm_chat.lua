-- СГЕНЕРИРОВАНО tools/sync_chat_addon.py — источник: sv_grmrp_chat.lua
-- Не править руками: изменения вносите в файл режима и перегенерируйте
-- (`python3 tools/sync_chat_addon.py`); расхождение ловит --check.
--[[ GRMChat — аддонский мутированный порт чат-модуля режима (тот же код,
    другие имена). На серверах с gamemode GRMRP порт подавляется САМИМ
    РЕЖИМОМ (GRMRPChat.SuppressAddonPort снимает все хуки/таймеры/команды с
    id «GRMChat*»; вечер-13): прежний guard «if GRMRP.Version» ловил
    только поздний reload — GMod исполняет lua/autorun аддонов ДО файлов
    режима, и на свежей карте два чата жили бок о бок (двойная Y-полоса,
    перехваты, общая DATA-история). Теперь плюс ранний guard (порядок
    reload через lua_refresh) и гейты SUPPRESSED на входах.
]]
if (GRMRP and GRMRP.Version) or (GRMRPChat and GRMRPChat.Channels)
    then return end -- режим уже здесь/на reload: порт не рождается

GRMChat.DeferToModules = true -- любые /команды остаются модулям

if SERVER then
    util.AddNetworkString(GRMChat.Net.SAY)
    util.AddNetworkString(GRMChat.Net.MSG)
end

CreateConVar("grm_chat_enable", "1",
    { FCVAR_REPLICATED, FCVAR_ARCHIVE }, "Чат режима: 1 вкл, 0 — возврат к движковому")
-- GRMChat.Enabled читает этот реплицируемый cvar; объявлен в shared.lua.
local cvMax = CreateConVar("grm_chat_max_chars", "256",
    { FCVAR_REPLICATED, FCVAR_ARCHIVE }, "Максимум байт в сообщении (жёсткий потолок 512)", 1, 512)
local cvRate = CreateConVar("grm_chat_rate", "0.35",
    { FCVAR_REPLICATED, FCVAR_ARCHIVE }, "Минимальный интервал между сообщениями, сек", 0, 10)
local cvBurst = CreateConVar("grm_chat_burst", "8",
    { FCVAR_REPLICATED, FCVAR_ARCHIVE }, "Сообщений в окне burst, дальше mute", 1, 64)
local cvWindow = CreateConVar("grm_chat_window", "10",
    { FCVAR_REPLICATED, FCVAR_ARCHIVE }, "Окно пересчёта burst, сек", 1, 120)
local cvIcRange = CreateConVar("grm_chat_ic_range", "700",
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
    net.Start(GRMChat.Net.MSG)
        net.WriteString("system")
        net.WriteString(GRMChat.Sanitize(text, cvMax:GetInt()))
        net.WriteString("")
        net.WriteDouble(0)
    net.Send(ply)
end
GRMChat.SendSystem = sendSystem

local function deliver(chan, author, body, extra, lineOverride, includeAuthor)
    local now = CurTime()
    local players = player.GetAll()

    local targets, err
    if chan.scope == "pm" then
        local target
        target, err = GRMChat.ResolvePmTarget(extra and extra.target or "", players, author)
        if not target then return err end
        targets = { target }
    else
        targets, err = GRMChat.ResolveAudience(chan, author, players,
            function(a, b) return a:GetPos():DistToSqr(b:GetPos()) end,
            function(p) return not p:Alive() end)
        if not targets then return err end
    end

    local name = GRMChat.Sanitize(author:Name(), GRMChat.SUGAR_MAX)
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
        net.Start(GRMChat.Net.MSG)
            net.WriteString(chan.id)
            net.WriteString(name)
            net.WriteString(body)
            net.WriteDouble(now)
        net.Send(net_list)
    end
    return nil
end

-- Состояние /do → контекст для /it (слабые ключи: утечек нет, §5.1.5).
local lastDo = setmetatable({}, { __mode = "k" })

-- opts (вечер-13): echoAuthor — ретранслировать строку и автору (серверные
-- события: показ документов; у клиентского ввода эхо локальное, не надо);
-- rpName — RP-имя вместо steam-ника; range — радиус события (400 у бланков).
function GRMChat.RPAction(kind, ply, body, chanId, opts)
    local def = GRMChat.RP[kind]
    if not def then return nil end
    local chan = table.Copy(GRMChat.GetChannel(def.chan) or GRMChat.GetChannel(chanId))
    if not chan then return "нет канала отыгровки" end
    chan.range = (opts and tonumber(opts.range)) or cvIcRange:GetFloat()
    local authorName
    if opts and isstring(opts.rpName) and #opts.rpName > 0 then
        authorName = GRMChat.Sanitize(opts.rpName, GRMChat.SUGAR_MAX)
    else
        authorName = GRMChat.Sanitize(ply:Name(), GRMChat.SUGAR_MAX)
    end

    if kind == "me" then
        -- Вечер-13: ветки «me» НЕ БЫЛО ВООБЩЕ — /me и серверные отыгровки
        -- проваливались в пустоту: получатель видел «* ...» только если
        -- строка шла через чужие каналы (старый RPChat/EasyChat), т.е.
        -- либо дубль, либо ничего. Стенд sim_chat_sv_routing закрывает дыру.
        return deliver(chan, ply, body, nil, def.fmt(authorName, body, nil),
            opts and opts.echoAuthor == true)
    end

    if kind == "do" then
        local audience = GRMChat.ResolveAudience(chan, ply, player.GetAll(),
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
        local max = GRMChat.RollSpec(body)
        local roll = math.random(1, max)
        return deliver(chan, ply, body, nil,
            def.fmt(authorName, body, { roll = roll, max = max }), true)
    end

    return nil
end

-- Единая точка входа: PlayerSay и net-поле ввода идут через неё.
function GRMChat.ProcessLine(ply, text, defaultChannel)
    if not GRMChat.Enabled() then return end

    -- Аддонская сборка (GRMChat): любые /команды живут у модулей (rp_chat,
    -- радиосети, /factions, /laws, админ-права...). Мы только показываем их
    -- вывод в свою ленту — второй владелец текста не появляется.
    if GRMChat.DeferToModules and string.sub(text, 1, 1) == "/" then
        return "keep"
    end

    -- Вечер-12: «/binder» и прочие команды модулей, набранные в НАШЕМ вводе
    -- (net-путь, мимо PlayerSay), уходят в общую цепочку — иначе окно биндера
    -- открывалось только из движкового say. Префиксная сверка: кириллические
    -- алиасы (/бинды) вне %w_. Ре-ентерь GM:PlayerSay гасит флаг _inExternal.
    if string.sub(text, 1, 1) == "/" and GRMChat.ExternalCommands
        and next(GRMChat.ExternalCommands) then
        local low = string.lower(text)
        local hit
        for c in pairs(GRMChat.ExternalCommands) do
            if string.sub(low, 1, #c) == c then hit = true break end
        end
        if hit then
            GRMChat._inExternal = true
            local okh, ret = pcall(hook.Run, "PlayerSay", ply, text, defaultChannel == "ooc", false)
            GRMChat._inExternal = nil
            if (not okh) or ret == nil or ret == "" then return end
            text = ret
        end
    end

    local now = CurTime()
    local st = stateFor(ply)
    local ok, warn = GRMChat.LadderCheck(st, now, cvRate:GetFloat(),
        cvBurst:GetInt(), cvWindow:GetInt())
    if warn then sendSystem(ply, warn) end
    if not ok then return end

    local chanId, body, extra = GRMChat.ParseSay(text, defaultChannel or "ic")
    if not chanId then
        sendSystem(ply, body) -- ParseSay вернул причину во втором значении
        return
    end
    body = GRMChat.Sanitize(body, cvMax:GetInt())
    if #body == 0 and not (extra and GRMChat.RP[extra.cmd or ""]) then return end

    -- RP-действия (/me /do /it /try /roll): своя форма строки, тот же
    -- аудиторный путь (один владелец — deliver).
    local kind = extra and extra.cmd
    if kind and GRMChat.RP[kind] then
        if #body == 0 and kind ~= "roll" then
            -- одинокий «/me» без действия не должен рождать пустую строку
            -- «* Ник » у половины сервера (стенд sv_routing)
            sendSystem(ply, "/" .. kind .. ": опишите действие после команды")
            return
        end
        local err = GRMChat.RPAction(kind, ply, body, chanId)
        if err then sendSystem(ply, err) end
        return
    end

    local chan = GRMChat.GetChannel(chanId)
    if not chan then sendSystem(ply, "канал не найден") return end

    if chan.cooldown > 0 then
        local last = lastAdvert[ply] or 0
        if now - last < chan.cooldown then
            sendSystem(ply, string.format("%s: подождите %d сек",
                chan.title, math.ceil(chan.cooldown - (now - last))))
            return
        end
        lastAdvert[ply] = now
    end

    if chanId == "ic" or chanId == "me" then
        chan = table.Copy(chan)
        chan.range = cvIcRange:GetFloat()
    end

    local err = deliver(chan, ply, body, extra)
    if err then sendSystem(ply, err) end
end

function GRMChat.OnPlayerSay(ply, text, teamChat, isDead)
    if not IsValid(ply) then return end
    return GRMChat.ProcessLine(ply, text, isDead and "dead" or (teamChat and "ooc" or "ic"))
end

-- Ввод из нашего окна. Тот же ProcessLine — дублирование запрещено (§5.2).
net.Receive(GRMChat.Net.SAY, function(len, ply)
    local sel = string.sub(net.ReadString(), 1, GRMChat.SUGAR_MAX)
    local text = net.ReadString()
    text = string.sub(text, 1, GRMChat.HARD_MAX * 2) -- физрежем ДО ядра
    if not GRMChat.GetChannel(sel) then sel = "ic" end -- канал — реестр, не доверие
    GRMChat.ProcessLine(ply, text, sel)
end)

hook.Add("PlayerDisconnect", "GRMChat", function(ply)
    stateByPlayer[ply] = nil
    lastAdvert[ply] = nil
end)

-- Вечер-13: поздняя страховка (см. sh-ядро) — после reload порта снять его
-- серверные хуки заново.
if isfunction(GRMChat.SuppressAddonPort) then
    GRMChat.SuppressAddonPort()
end

-- Realm-клей песочницы: движковый PlayerSay превращается в наш канал.
hook.Add("PlayerSay", "GRMChat_Capture", function(ply, text, teamChat, isDead)
    if GRMChat.SUPPRESSED then return end -- вечер-13: режим владелец
    if GRMChat.Enabled and GRMChat.Enabled() then
        if GRMChat.OnPlayerSay(ply, text, teamChat, isDead) == "keep" then
            return text -- обрабатывают модули; лента получит их вывод
        end
        return ""
    end
end)
