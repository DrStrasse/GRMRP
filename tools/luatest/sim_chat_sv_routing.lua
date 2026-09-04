--[[ sim_chat_sv_routing — серверный роутинг чата РЕАЛЬНЫМ sv-файлом.

    Урок вечера-13: в RPAction не было ветки «me» — /me доходил только до
    автора (локальное эхо), остальные не видели НИЧЕГО; стенды веч.8-12 этого
    не поймали, потому что грузили только sh-ядро. Мораль (OWNER_REPORTS.md):
    «зелёный стенд» ≠ «работает» — тестируем код, который реально ходит по
    движку: здесь — ProcessLine/deliver/лестница/PM/external-роутинг через
    подставленные net/hook/player.
]]
-- ============ движковые стабы ============
local function T(v) return type(v) end
_G.isstring = function(v) return T(v) == "string" end
_G.istable = function(v) return T(v) == "table" end
_G.isfunction = function(v) return T(v) == "function" end
_G.isnumber = function(v) return T(v) == "number" end
_G.IsValid = function(v) return T(v) == "table" and v.__valid ~= false end
local function vcopy(t)
    if T(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = vcopy(v) end
    return out
end
_G.table.Copy = vcopy
_G.string.Trim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
_G.string.Explode = function(sep, s)
    local out = {}
    for part in (s .. sep):gmatch("(.-)" .. sep) do out[#out + 1] = part end
    return out
end
_G.math.Clamp = function(v, a, b) return math.max(a, math.min(b, v)) end

local clock = { t = 1000 }
_G.CurTime = function() return clock.t end
_G.RealTime = function() return clock.t end

local cvStore = {}
local function mkcv(name, def)
    local o = { int = tonumber(def), bool = def == "1", float = tonumber(def) or 0 }
    function o:GetInt() return self.int end
    function o:GetFloat() return self.float end
    function o:GetBool() return self.bool end
    cvStore[name] = o
    return o
end
_G.CreateConVar = function(name, def) return mkcv(name, def) end
_G.GetConVar = function(name) return cvStore[name] end

-- net: сборщик пакетов
local sent = {}   -- { targets = {...}, parts = {...} }
local cur
_G.net = {
    Start = function(name) cur = { name = name, parts = {} } end,
    WriteString = function(s) cur.parts[#cur.parts + 1] = s end,
    WriteDouble = function(d) cur.parts[#cur.parts + 1] = d end,
    Send = function(list)
        sent[#sent + 1] = { name = cur.name, targets = list, parts = vcopy(cur.parts) }
    end,
    AddNetworkString = function() end,
    Broadcast = function() end,
    Receive = {},   -- [name] = fn; заполняется ниже хуком
}
local recvFns = {}
_G.net.Receive = function(name, fn) recvFns[name] = fn end
_G.util = {
    AddNetworkString = function() end,
    NetworkStringToID = function(s) return s == "GRM_RPChat_Msg" and 12 or 0 end,
}
_G.SERVER, _G.CLIENT = true, false

-- hook: таблица id → fns, как в движке
local hookTable = {}
_G.hook = {
    Add = function(name, id, fn)
        hookTable[name] = hookTable[name] or {}
        hookTable[name][id] = fn
    end,
    Remove = function(name, id)
        if hookTable[name] then hookTable[name][id] = nil end
    end,
    Run = function(name, ...)
        _G.__hookRunCalls = _G.__hookRunCalls or {}
        _G.__hookRunCalls[#_G.__hookRunCalls + 1] = {
            name = name, args = { ... },
            inExt = GRMRPChat and GRMRPChat._inExternal or nil,
        }
        if _G.__hookRunRet ~= nil then return _G.__hookRunRet end
        return nil
    end,
}
_G.GetTable = nil
_G.concommand = { Add = function() end, Remove = function() end }
_G.timer = { Create = function() end, Remove = function() end, Simple = function(_, f) f() end }

-- игроки
local function mkPlayer(name, x)
    local p = {
        __name = name, x = x, alive = true, sid64 = "76561197000000" .. tostring(math.random(1000, 9999)),
    }
    function p:Name() return self.__name end
    function p:Nick() return self.__name end
    function p:GetPos()
        local me = self.x
        return { x2 = me, DistToSqr = function(_, o) local d = me - o.x2 return d * d end }
    end
    function p:Alive() return self.alive end
    function p:IsPlayer() return true end
    function p:SteamID64() return self.sid64 end
    return p
end
local A, B, C, BOB, BOBA
local function resetPlayers()
    A = mkPlayer("Ann", 0)
    B = mkPlayer("Bob", 100)
    C = mkPlayer("Cal", 900)
    BOB, BOBA = A, mkPlayer("Boba Fett", 50)
end
_G.player = { GetAll = function() return { A, B, C, BOBA } end }

-- ============ загрузка боевого кода ============
GRMRP = { Net = { SAY = "grmrp/chat_say", MSG = "grmrp/chat_msg" } }
function GRMRP.ErrorNoHalt(...) end
local root = arg[0]:match("^(.*)[/\\]tools[/\\]luatest") or "."
dofile(root .. "/gamemodes/grmrp/gamemode/modules/chat/sh_grmrp_chat_core.lua")
-- как в shared.lua режима:
function GRMRPChat.Enabled() return true end
dofile(root .. "/gamemodes/grmrp/gamemode/modules/chat/sv_grmrp_chat.lua")

-- ============ мини-фреймворк ============
local total, fails = 0, 0
local function T2(name, cond, note)
    total = total + 1
    if cond then
        print("  ok   " .. name)
    else
        fails = fails + 1
        print(("  FAIL %-58s %s"):format(name, note and tostring(note) or ""))
    end
end
local function lastMsg() return sent[#sent] end
local function reset()
    sent = {}
    _G.__hookRunCalls = {}
    _G.__hookRunRet = nil
    resetPlayers()
    clock.t = clock.t + 1000
end

-- ============ 1. /me — то, чего не было ============
reset()
GRMRPChat.ProcessLine(A, "/me осматривит витрину", "ic")
local m = lastMsg()
T2("/me доставлен (net-пакет создан)", m ~= nil)
if m then
    T2("me: канал me", m.parts[1] == "me", m.parts[1])
    T2("me: формат строки для остальных", m.parts[3] == "* Ann осматривит витрину", m.parts[3])
    local hasA, hasB = false, false
    for _, p in ipairs(m.targets) do
        if p == A then hasA = true end
        if p == B then hasB = true end
    end
    T2("me: автор ИСКЛЮЧЁН (локальное эхо клиента)", not hasA)
    T2("me: ближний слушатель получил", hasB)
    local hasC = false
    for _, p in ipairs(m.targets) do if p == C then hasC = true end end
    T2("me: дальний (900 > 700) отсечён радиусом", not hasC)
end

-- echoAuthor (серверные события через шину документов)
reset()
local err = GRMRPChat.RPAction("me", A, "предъявил бланк", nil,
    { echoAuthor = true, rpName = "Энн Тремейн", range = 400 })
m = lastMsg()
T2("шина-вызов: без ошибки", err == nil, err)
if m then
    T2("echoAuthor: автор в списке получателей", (function()
        for _, p in ipairs(m.targets) do if p == A then return true end end
        return false
    end)())
    T2("rpName форматирует имя, не steam-ник",
        m.parts[3] == "* Энн Тремейн предъявил бланк", m.parts[3])
    local hasC = false
    for _, p in ipairs(m.targets) do if p == C then hasC = true end end
    T2("range=400 отсекает дальнего сильнее cvar", not hasC)
end

-- ============ 2. /do → /it контекст ============
reset()
GRMRPChat.ProcessLine(A, "/do мяч катится", "ic")
sent = {} -- мягкий клир: lastDo живёт на тех же объектах игроков
GRMRPChat.ProcessLine(B, "/it пинает мяч", "ic")
m = lastMsg()
T2("it: ответ на свежий do форматируется", m and m.parts[3] and m.parts[3]:find("в ответ Ann") ~= nil, m and m.parts[3])
reset()
GRMRPChat.ProcessLine(C, "/it ничего нет", "ic")
m = lastMsg()
T2("it без do: system-подсказка автору", m and m.parts[1] == "system"
    and m.parts[2]:find("свежего /do") ~= nil, m and (m.parts[2] or ""))

-- ============ 3. try/roll ============
reset()
GRMRPChat.ProcessLine(A, "/try вскрыть", "ic")
m = lastMsg()
T2("try: строка с итогом броска", m and m.parts[3]:find("пробует «вскрыть»") ~= nil, m and m.parts[3])
reset()
GRMRPChat.ProcessLine(A, "/roll 20", "ic")
m = lastMsg()
T2("roll: канал dice и потолок из тела", m and m.parts[1] == "dice"
    and m.parts[3]:find("1%.%.20") ~= nil, m and (m.parts[1] .. "/" .. (m.parts[3] or "")))
reset()
GRMRPChat.ProcessLine(A, "/roll", "ic")
m = lastMsg()
T2("roll без тела разрешён (allowEmpty)", m ~= nil)

-- ============ 4. PM ============
reset()
GRMRPChat.ProcessLine(A, "/pm Boba привет", "ic")
m = lastMsg()
T2("pm: один адресат", m and #m.targets == 1 and m.targets[1].__name == "Boba Fett", m and #m.targets)
reset()
GRMRPChat.ProcessLine(A, "/pm Никого нет", "ic")
m = lastMsg()
T2("pm: нет цели → system", m and m.parts[1] == "system" and m.parts[2]:find("игрок не найден") ~= nil)
reset()
GRMRPChat.ProcessLine(A, "/pm Bo текст", "ic")
m = lastMsg()
T2("pm: префикс-двойники → неоднозначен или точный Bob (разрешено)",
    m and (m.parts[1] == "system" or m.parts[1] == "pm"))

-- ============ 5. sanitize/лимиты ============
reset()
GRMRPChat.ProcessLine(A, "привет <script> мир", "ic")
m = lastMsg()
T2("markup зеркалится у получателей", m and m.parts[3]:find("＜script＞") ~= nil, m and m.parts[3])
reset()
GRMRPChat.ProcessLine(A, "a\tb", "ic")
m = lastMsg()
T2("таб → пробел (управляющие гасятся)", m and m.parts[3] == "a b", m and m.parts[3])
reset()
GRMRPChat.ProcessLine(A, string.rep("длин", 400), "ic")
m = lastMsg()
T2("тело обрезано по cvMax (256) с UTF-8 границей",
    m and #m.parts[3] <= 260 and m.parts[3]:sub(-6) == string.rep("длин", 400):sub(-6),
    m and #m.parts[3])
reset()
local nBefore = #sent
GRMRPChat.ProcessLine(A, "/me   ", "ic")
local sysHint, meLine = false, false
for i = nBefore + 1, #sent do
    local p = sent[i]
    if p.name == "grmrp/chat_msg" then
        if p.parts[1] == "system" then sysHint = true end
        if p.parts[1] == "me" then meLine = true end
    end
end
T2("пустое RP-тело: подсказка автору, в ленту ничего", sysHint and not meLine)

-- ============ 6. неизвестные и внешние команды ============
reset()
GRMRPChat.ProcessLine(A, "/nope hi", "ic")
m = lastMsg()
T2("неизвестная команда → system с именем команды",
    m and m.parts[1] == "system" and m.parts[2]:find("неизвестная команда /nope") ~= nil, m and m.parts[2])
reset()
GRMRPChat.RegisterExternalChatCommand("/xtor")
_G.__hookRunRet = ""
GRMRPChat.ProcessLine(A, "/xtor run", "ic")
local hc = _G.__hookRunCalls[1]
T2("external: строка ушла в цепочку PlayerSay", hc and hc.name == "PlayerSay" and hc.args[2] == "/xtor run")
T2("external: ре-ентерь guard поднят на время цепочки", hc and hc.inExt == true)
T2("external: съедена (ретрансляции в ленту нет)", #sent == 0)
_G.__hookRunRet = "отредактировано"
reset()
_G.__hookRunRet = "отредактировано"
GRMRPChat.ProcessLine(A, "/xtor run", "ic")
m = lastMsg()
T2("external: хук вернул правку — текст обработан далее", m and m.parts[3]:find("отредактировано") ~= nil, m and m.parts[3])
_G.__hookRunRet = nil

-- ============ 7. лестница и кулдауны ============
reset()
local ok1 = true
for i = 1, 30 do GRMRPChat.ProcessLine(A, "спам " .. i, "ic") end
local sysWarn = false
for _, p in ipairs(sent) do
    if p.parts[1] == "system" and p.parts[2]:find("флуд") then sysWarn = true end
end
T2("лестница: спам наказан system-предупреждением/мутом", sysWarn)
sent = {}
GRMRPChat.ProcessLine(A, "ещё", "ic")
T2("мут активен: сообщения не доставляются", #sent == 0, #sent)
reset()
GRMRPChat.ProcessLine(B, "/advert крик", "ic")
local n1 = #sent
clock.t = clock.t + 1 -- вне rate, внутри 60-сек кулдауна
GRMRPChat.ProcessLine(B, "/advert ещё", "ic")
local advertBlocked = #sent > n1 and (function()
    local p = lastMsg()
    return p.parts[1] == "system" and p.parts[2]:find("подождите") ~= nil
end)()
T2("advert cooldown 60s: повтор заблокирован подсказкой", advertBlocked)

-- ============ 8. мёртвые ============
reset()
A.alive = false
BOBA.alive = false
GRMRPChat.ProcessLine(A, "из загробного", "ic")
m = lastMsg()
T2("мертвец в ic → refusal system", m and m.parts[1] == "system"
    and m.parts[2]:find("dead") ~= nil, m and m.parts[2])
reset()
A.alive = false
BOBA.alive = false
GRMRPChat.ProcessLine(A, "/dead привидения", "ic")
m = lastMsg()
local deadOnly = m and (function()
    if m.parts[1] ~= "dead" then return false end
    for _, p in ipairs(m.targets) do if p.alive then return false end end
    return true
end)()
T2("dead-чат: канал dead и только мёртвые получатели", deadOnly == true, deadOnly == nil and "нет пакета" or "")

-- ============ 9. net-вход ============
reset()
local h = recvFns["grmrp/chat_say"]
T2("net-обработчик ввода зарегистрирован", h ~= nil)
if h then
    local q = { "ic", "окно говорит" }
    net.ReadString = function() return table.remove(q, 1) or "" end
    h(0, A)
    m = lastMsg()
    T2("net-путь = тот же ProcessLine", m and m.parts[1] == "ic"
        and m.parts[3] == "окно говорит", m and m.parts[1])
    net.ReadString = nil
end

-- ============ 10. OnPlayerSay маппинг ============
reset()
GRMRPChat.OnPlayerSay(B, "йопт", false, false)
m = lastMsg()
T2("say без слэша → ic, имя автора в payload", m and m.parts[1] == "ic" and m.parts[2] == "Bob", m and (m.parts[1] .. "/" .. (m.parts[2] or "")))
reset()
GRMRPChat.OnPlayerSay(B, "ооч", true, false)
m = lastMsg()
T2("teamChat=true → ooc default", m and m.parts[1] == "ooc")
reset()
B.alive = false
BOBA.alive = false
GRMRPChat.OnPlayerSay(B, "бу", false, true)
m = lastMsg()
T2("isDead=true → dead default", m and (m.parts[1] == "dead" or m.parts[1] == "system"))

print(("SV ROUTING: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
