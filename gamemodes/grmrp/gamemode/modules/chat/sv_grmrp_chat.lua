--[[ GRMRPChat сервер: cvar'ы, каналы, net-контракт, рассылка.
    Логика — целиком в sh-ядре; этот файл только прикручивает движок.
    Клиент не доверяет себе: всё перечитывается и перепроверяется здесь
    (§5.1.3, урок file_browser).
]]

if SERVER then
    util.AddNetworkString(GRMRP.Net.SAY)
    util.AddNetworkString(GRMRP.Net.MSG)
end

local cvEnable = CreateConVar("grmrp_chat_enable", "1",
    { FCVAR_REPLICATED, FCVAR_ARCHIVE }, "Чат режима: 1 вкл, 0 — возврат к движковому")
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

function GRMRPChat.Enabled()
    return cvEnable:GetBool()
end

-- Каналы режима. Очередность добавления не важна (stub-реестр GRMAPI).
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
    net.Start(GRMRP.Net.MSG)
        net.WriteString("system")
        net.WriteString(GRMRPChat.Sanitize(text, cvMax:GetInt()))
        net.WriteString("")
        net.WriteDouble(0)
    net.Send(ply)
end
GRMRPChat.SendSystem = sendSystem

local function deliver(chan, author, body, extra)
    local now = CurTime()
    local players = player.GetAll()

    local targets, err
    if chan.scope == "pm" then
        local target
        target, err = GRMRPChat.ResolvePmTarget(extra and extra.target or "", players, author)
        if not target then return err end
        targets = { target }
    else
        targets, err = GRMRPChat.ResolveAudience(chan, author, players,
            function(a, b) return a:GetPos():DistToSqr(b:GetPos()) end,
            function(p) return not p:Alive() end)
        if not targets then return err end
    end

    local name = GRMRPChat.Sanitize(author:Name(), GRMRPChat.SUGAR_MAX)
    -- Автор не получает ретрансляцию: клиент печатает свою строку локально
    -- (оптимистичный эхо-каст; состояния сервер не менял — см. §5.4.3).
    local net_list = {}
    for i = 1, #targets do
        if targets[i] ~= author then table.insert(net_list, targets[i]) end
    end
    if #net_list > 0 then
        net.Start(GRMRP.Net.MSG)
            net.WriteString(chan.id)
            net.WriteString(name)
            net.WriteString(body)
            net.WriteDouble(now)
        net.Send(net_list)
    end
    return nil
end

-- Единая точка входа: PlayerSay и net-поле ввода идут через неё.
function GRMRPChat.ProcessLine(ply, text, defaultChannel)
    if not GRMRPChat.Enabled() then return end

    local now = CurTime()
    local st = stateFor(ply)
    local ok, warn = GRMRPChat.LadderCheck(st, now, cvRate:GetFloat(),
        cvBurst:GetInt(), cvWindow:GetInt())
    if warn then sendSystem(ply, warn) end
    if not ok then return end

    local chanId, body, extra = GRMRPChat.ParseSay(text, defaultChannel or "ic")
    if not chanId then
        sendSystem(ply, body) -- ParseSay вернул причину во втором значении
        return
    end
    body = GRMRPChat.Sanitize(body, cvMax:GetInt())
    if #body == 0 then return end

    local chan = GRMRPChat.GetChannel(chanId)
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

function GRMRPChat.OnPlayerSay(ply, text, teamChat, isDead)
    if not IsValid(ply) then return end
    GRMRPChat.ProcessLine(ply, text, isDead and "dead" or (teamChat and "ooc" or "ic"))
end

-- Ввод из нашего окна. Тот же ProcessLine — дублирование запрещено (§5.2).
net.Receive(GRMRP.Net.SAY, function(len, ply)
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
