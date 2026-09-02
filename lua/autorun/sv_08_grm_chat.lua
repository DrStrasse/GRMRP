-- СГЕНЕРИРОВАНО tools/sync_chat_addon.py — источник: sv_grmrp_chat.lua
-- Не править руками: изменения вносите в файл режима и перегенерируйте
-- (`python3 tools/sync_chat_addon.py`); расхождение ловит --check.
--[[ GRMChat — аддонский мутированный порт чат-модуля режима (тот же код,
    другие имена). На серверах с gamemode GRMRP модуль молча выключается
    целиком: чат режима — единственный владелец, дублей net-имён/cvar'ов/
    перехвата PlayerSay не возникает никогда.
]]
if GRMRP and GRMRP.Version then return end

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

local function deliver(chan, author, body, extra)
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
    -- Автор не получает ретрансляцию: клиент печатает свою строку локально
    -- (оптимистичный эхо-каст; состояния сервер не менял — см. §5.4.3).
    local net_list = {}
    for i = 1, #targets do
        if targets[i] ~= author then table.insert(net_list, targets[i]) end
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

-- Единая точка входа: PlayerSay и net-поле ввода идут через неё.
function GRMChat.ProcessLine(ply, text, defaultChannel)
    if not GRMChat.Enabled() then return end

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
    if #body == 0 then return end

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
    GRMChat.ProcessLine(ply, text, isDead and "dead" or (teamChat and "ooc" or "ic"))
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

-- Realm-клей песочницы: движковый PlayerSay превращается в наш канал.
hook.Add("PlayerSay", "GRMChat_Capture", function(ply, text, teamChat, isDead)
    if GRMChat.Enabled and GRMChat.Enabled() then
        GRMChat.OnPlayerSay(ply, text, teamChat, isDead)
        return ""
    end
end)
