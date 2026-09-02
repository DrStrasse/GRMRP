--[[ sim_grmrp_chat — стенд ядра чата GRM:RP (режим, modules/chat/sh_core).

    Проверяет контракт нормализатора и диспетчера (WIKI 4.9.1/4.21):
      1) sanitize: control-символы, <> (markup-инъекция), NBSP, пробелы,
         clamp с сохранением целостности UTF-8;
      2) ParseSay: каналы по cmd, /pm с адресатом, ошибки;
      3) LadderCheck: предупреждение на burst, mute при rate-нарушении,
         экспоненциальный рост и потолок, декей окна;
      4) ResolveAudience: дальность, dead-сегрегация, onlyDead;
      5) ResolvePmTarget: steamid → уникальность имени → отказ на амбигуитете;
      6) RegisterChannel: валидация/клемпы/дубли.

    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_grmrp_chat.lua
----------------------------------------------------------------------]]

-- минимальные стабы движка (ровно то, что трогает core)
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function math.Clamp(v, a, b) return v < a and a or (v > b and b or v) end

local which = (arg and arg[1]) or "mode"
if which == "addon" then
    dofile("lua/autorun/sh_08_grm_chat_core.lua")
else
    dofile("gamemodes/grmrp/gamemode/modules/chat/sh_grmrp_chat_core.lua")
end
local GRMRPChat = _G[(which == "addon") and "GRMChat" or "GRMRPChat"]

local passed, failed = 0, 0
local function T(name, cond)
    if cond then passed = passed + 1
    else
        failed = failed + 1
        print("FAIL: " .. name)
    end
end

-- 1) sanitize -----------------------------------------------------------
local s = GRMRPChat.Sanitize("при­вет   мир\r\n\t<font=DermaDefault>hack</font>", 512)
T("control chars stripped", not s:find("\r") and not s:find("\n") and not s:find("\t"))
T("angle brackets neutralized", not s:find("<") and not s:find(">"))
T("nbsp gone", not s:find("\226\128\137"))
T("spaces collapsed", not s:find("  "))
T("markup payload defused", s:find("hack") ~= nil and s:find("<font") == nil)

local long = string.rep("а", 300) -- 2 байта на букву
local clamped = GRMRPChat.Sanitize(long, 501) -- нечётный отрезал посередине буквы
T("utf8 clamp keeps char integrity", #clamped == 500 and clamped:sub(-2) == "а")
local okDecode = true
local i = 1
while i <= #clamped do
    local b = clamped:byte(i)
    local extra = b >= 240 and 3 or (b >= 224 and 2 or (b >= 192 and 1 or 0))
    if b >= 128 and b < 192 then okDecode = false break end
    i = i + extra + 1
end
T("no dangling continuation bytes", okDecode)

-- 2) ParseSay -----------------------------------------------------------
GRMRPChat.RegisterChannel("ic", { title = "Крик", cmd = "w", scope = "range" })
GRMRPChat.RegisterChannel("ooc", { title = "OOC", cmd = "ooc", scope = "world" })
GRMRPChat.RegisterChannel("dead", { title = "Мертвечина", onlyDead = true })
GRMRPChat.RegisterChannel("advert", { title = "Объявление", cmd = "advert", scope = "world", cooldown = 60 })
GRMRPChat.RegisterChannel("pm", { title = "Личное", cmd = "pm", scope = "pm" })

local ch, body = GRMRPChat.ParseSay("просто текст", "ic")
T("plain → default channel", ch == "ic" and body == "просто текст")
ch, body = GRMRPChat.ParseSay("/ooc продам гараж", "ic")
T("/ooc routes by cmd", ch == "ooc" and body == "продам гараж")
ch, body = GRMRPChat.ParseSay("/W капслок режет", "ic")
T("cmd case-insensitive", ch == "ic")
local err
ch, err = GRMRPChat.ParseSay("/heh что", "ic")
T("unknown cmd rejected", ch == nil and err:find("неизвестная") ~= nil)
ch, err = GRMRPChat.ParseSay("/ooc", "ic")
T("world empty body allowed", ch == "ooc")
ch, err = GRMRPChat.ParseSay("/w", "ic")
T("range empty body rejected", ch == nil)
local extra
ch, body, extra = GRMRPChat.ParseSay("/pm Вася привет", "ic")
T("/pm parses target", ch == "pm" and extra.target == "Вася" and body == "привет")
ch, err = GRMRPChat.ParseSay("/pm толькоимя", "ic")
T("/pm without message rejected", ch == nil)
ch, err = GRMRPChat.ParseSay("", "ic")
T("empty rejected", ch == nil)
ch, err = GRMRPChat.ParseSay("   ", "ic")
T("spaces-only rejected", ch == nil)

-- 3) LadderCheck --------------------------------------------------------
local st = {}
local now = 100
local ok, warn = GRMRPChat.LadderCheck(st, now, 0.35, 8, 10)
T("first ok", ok == true and warn == nil)
for i2 = 2, 7 do
    now = now + 1
    ok = GRMRPChat.LadderCheck(st, now, 0.35, 8, 10)
end
T("no warn before burst", ok == true)
now = now + 1
ok, warn = GRMRPChat.LadderCheck(st, now, 0.35, 8, 10) -- hits = 8
T("warn at burst edge", ok == true and warn ~= nil)
now = now + 0.1 -- почти сразу: и burst, и rate-нарушение
ok = GRMRPChat.LadderCheck(st, now, 0.35, 8, 10)
T("over burst mutes", ok == false)
T("muted stays muted", (select(1, GRMRPChat.LadderCheck(st, now + 1, 0.35, 8, 10))) == false)

st = {}
now = 500
GRMRPChat.LadderCheck(st, now, 0.35, 8, 10)          -- 1-е
ok, warn = GRMRPChat.LadderCheck(st, now + 0.1, 0.35, 8, 10) -- быстрее rate
T("rate violation mutes", ok == false and warn:find("флуд") ~= nil)
local mute1 = st.muteUntil - (now + 0.1)
ok, warn = GRMRPChat.LadderCheck(st, st.muteUntil + 1, 0.35, 8, 10)
T("mute decays back", ok == true)
GRMRPChat.LadderCheck(st, st.lastAny + 0.01, 0.35, 8, 10)
local mute2 = st.muteUntil - st.lastAny
T("escalating mute", mute2 >= mute1 * 1.5)
st.penalty = 10 -- «злостный»: следующая пауза должна упереться в потолок
st.muteUntil = 0
st.lastAny = 20000
GRMRPChat.LadderCheck(st, 20000.01, 0.35, 8, 10)
T("mute capped at 180", st.muteUntil - 20000.01 == 180)

-- окно декея: после window счётчик обнуляется
st = {}
for i4 = 1, 6 do GRMRPChat.LadderCheck(st, 1000 + i4 * 0.5, 0.35, 8, 10) end
local hits = st.hits
GRMRPChat.LadderCheck(st, 1000 + 21, 0.35, 8, 10)
T("window decays hits", st.hits == 1 and hits == 6)

-- 4) ResolveAudience ----------------------------------------------------
local function mk(name, x, dead) return { Name = name, _x = x, _dead = dead and true or false } end
local function dist(a, b) return (a._x - b._x) ^ 2 end
local function isDead(p) return p._dead end

local author = mk("Автор", 0, false)
local near = mk("Рядом", 100, false)
local far = mk("Далеко", 99999, false)
local dead = mk("Труп", 50, true)
local players = { author, near, far, dead }

local chanIC = GRMRPChat.GetChannel("ic")
chanIC.range = 700
local list, aerr = GRMRPChat.ResolveAudience(chanIC, author, players, dist, isDead)
T("ic: near hears, far and dead don't", #list == 1 and list[1] == near and aerr == nil)

local deadChan = GRMRPChat.GetChannel("dead")
deadChan.range = 700
local authorDead = mk("Дух", 0, true)
list = GRMRPChat.ResolveAudience(deadChan, authorDead, { authorDead, near, dead }, dist, isDead)
T("dead chat: only dead within range", #list == 1 and list[1] == dead)
local list2, err2 = GRMRPChat.ResolveAudience(deadChan, author, players, dist, isDead)
T("alive rejected from dead chat", list2 == nil and err2 ~= nil)
local list3, err3 = GRMRPChat.ResolveAudience(chanIC, authorDead, players, dist, isDead)
T("dead rejected from ic", list3 == nil and err3 ~= nil)

local ooc = GRMRPChat.GetChannel("ooc")
list = GRMRPChat.ResolveAudience(ooc, author, players, dist, isDead)
T("world: everyone alive hears", #list == 2)

-- 5) ResolvePmTarget ------------------------------------------------------
local bob = { Name = "Bob Marley", SteamID64 = "76561197000000002" }
local boba = { Name = "Boba Fett", SteamID64 = "76561197000000003" }
local ppl = { author, bob, boba }
local t
t = GRMRPChat.ResolvePmTarget("76561197000000002", ppl, author)
T("pm by steamid", t == bob)
t = GRMRPChat.ResolvePmTarget("boba", ppl, author)
T("pm unique substring", t == boba)
t, err = GRMRPChat.ResolvePmTarget("bob", ppl, author)
T("pm ambiguous rejected", t == nil and err:find("неодноз") ~= nil)
t, err = GRMRPChat.ResolvePmTarget("нети", ppl, author)
T("pm not found", t == nil and err:find("не найден") ~= nil)
t = GRMRPChat.ResolvePmTarget("автор", ppl, author)
T("pm self excluded", t == nil)

-- 6) RegisterChannel ------------------------------------------------------
local okC, errC = GRMRPChat.RegisterChannel("ic", { title = "дубль" })
T("duplicate rejected", okC == nil and errC:find("duplicate") ~= nil)
local c = GRMRPChat.RegisterChannel("t1", { title = string.rep("х", 100), range = 999999, color = { r = 300, g = -5 } })
T("title clamped", #c.title == 32)
T("range clamped", c.range == 4096)
T("color clamped", c.color.r == 255 and c.color.g == 0)
local c2 = GRMRPChat.RegisterChannel("t2", { scope = "левый" })
T("bad scope falls back to range", c2.scope == "range")
T("bad id rejected", (GRMRPChat.RegisterChannel("", {})) == nil)

print(string.format("GRMRP_CHAT[%s]: %d/%d, провалов: %d", which,
    passed, passed + failed, failed))
os.exit(failed == 0 and 0 or 1)
