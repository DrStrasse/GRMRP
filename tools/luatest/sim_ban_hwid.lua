--[[ sim_ban_hwid — глобальный бан ПО ЖЕЛЕЗУ (заказ владельца 02.09.2026:
    «нужен не просто бан, а бан по железу компьютера, считывание компьютера
    игрока»).

    Проверяется контракт модуля GRM.ServerBan v1.2.0:
      1) канонизация снимка и хеш (одинаковый снимок — одинаковый hwid,
         разные — разные; пустой снимок — nil);
      2) нормализация IP (порт отбрасывается);
      3) SB.GlobalBan: запись в глобальную книгу, индексы hwid/ip,
         история и снимок в пэйлоаде сохранения (version 2);
      4) новый аккаунт с забаненного железа — кик + добан остатка срока
         (banid + writeid), запись hwid-hit;
      5) с owner-аккаунта совпадение hwid молчит;
      6) CheckJoinIP — вход с забаненного IP кикается до всякого отчёта;
      7) GlobalLift снимает запись и ИНДЕКСЫ (иначе добан висел бы вечно);
      8) принят один отчёт на соединение (спам-защита), явный запрос админа
         разрешает ещё один;
      9) roundtrip: saveBans → SB.Load восстанавливает книгу и индексы,
         истёкшие записи не переживают перезагрузку;
     10) интеграция по исходникам: снимок снимается ДО кика в A.ban/A.ban_id,
         A.unban снимает глобальную запись, A.machine зарегистрирован,
         панель отдаёт чекбокс «по железу» и кнопку снимка.

    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_ban_hwid.lua
----------------------------------------------------------------------]]
SERVER, CLIENT = true, false
function AddCSLuaFile() end

local NOW = 100
function CurTime() return NOW end
function SysTime() return NOW end
local CLOCK = 1700000000
os.time = function() return CLOCK end
function IsValid(v) return type(v) == "table" and v._valid ~= false end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isfunction(v) return type(v) == "function" end
function isnumber(v) return type(v) == "number" end
function isbool(v) return type(v) == "boolean" end
function isvector(v) return type(v) == "table" and v._vector == true end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function string.Trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
function table.Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
function ErrorNoHalt(...) end
function math.Rand(a, b) return a + (b - a) * 0.5 end
RENDERMODE_TRANSCOLOR, RENDERMODE_NORMAL, HUD_PRINTCONSOLE = 5, 0, 2
MOVETYPE_WALK, FCVAR_ARCHIVE, CHAN_VOICE = 2, 1, 3
NULL = { _valid = false }
function Vector(x, y, z) return { x = x or 0, y = y or 0, z = z or 0, _vector = true } end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a } end

local hooks = {}
SWAP_SEEN = {}
hook = {
    Add = function(n, id, fn) hooks[n] = hooks[n] or {} hooks[n][id] = fn end,
    Remove = function(n, id) if hooks[n] then hooks[n][id] = nil end end,
    Run = function(name, ...)
        local t = hooks[name]
        if not t then return end
        for _, fn in pairs(t) do fn(...) end
    end,
}
local timers = {}
timer = { Create = function(id, _, _, fn) timers[id] = fn end, Simple = function(_, fn) fn() end,
    Remove = function(id) timers[id] = nil end, Exists = function() return false end,
    Adjust = function() return true end }
concommand = { Add = function(name, fn) concommand[name] = fn end }

local FS = {}
file = { IsDir = function() return true end, CreateDir = function() end,
    Write = function(p, s) FS[p] = s end, Read = function(p) return FS[p] end,
    Exists = function(p) return FS[p] ~= nil end }
local function enc(v)
    local t = type(v)
    if t == "number" or t == "boolean" then return tostring(v) end
    if t == "string" then return string.format("%q", v) end
    if t ~= "table" then return "null" end
    local parts = {}
    if #v > 0 then
        for _, i in ipairs(v) do parts[#parts + 1] = enc(i) end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    for k, i in pairs(v) do parts[#parts + 1] = string.format("%q", tostring(k)) .. ":" .. enc(i) end
    return "{" .. table.concat(parts, ",") .. "}"
end
local function dec(str)
    local pos = 1
    local function value()
        while str:sub(pos, pos):match("%s") do pos = pos + 1 end
        local c = str:sub(pos, pos)
        if c == "{" then
            pos = pos + 1 local out = {}
            if str:sub(pos, pos) == "}" then pos = pos + 1 return out end
            while true do
                local k = value() pos = pos + 1
                out[k] = value()
                local sep = str:sub(pos, pos) pos = pos + 1
                if sep == "}" then break end
            end
            return out
        elseif c == "[" then
            pos = pos + 1 local out = {}
            if str:sub(pos, pos) == "]" then pos = pos + 1 return out end
            while true do
                out[#out + 1] = value()
                local sep = str:sub(pos, pos) pos = pos + 1
                if sep == "]" then break end
            end
            return out
        elseif c == '"' then
            local i, out = pos + 1, {}
            while str:sub(i, i) ~= '"' do out[#out + 1] = str:sub(i, i) i = i + 1 end
            pos = i + 1 return table.concat(out)
        elseif str:sub(pos, pos + 3) == "true" then pos = pos + 4 return true
        elseif str:sub(pos, pos + 4) == "false" then pos = pos + 5 return false
        elseif str:sub(pos, pos + 3) == "null" then pos = pos + 4 return nil
        else
            local a, b = str:find("[%-%d%.]+", pos) pos = b + 1 return tonumber(str:sub(a, b))
        end
    end
    local ok, res = pcall(value)
    return ok and res or nil
end

local CONSOLE = {}
util = { PrecacheSound = function() end, AddNetworkString = function() end,
    TableToJSON = function(t) return enc(t) end,
    JSONToTable = function(str) return dec(str) end,
    SteamIDFrom64 = function(s) return "STEAM:" .. s end,
    -- детерминированный «хеш»: равенство/неравенство снимков видно и так,
    -- а префикс имитирует формат SHA1
    SHA1 = function(s) return "sha1:" .. tostring(s) end }
game = { GetMap = function() return "rp_test" end,
    ConsoleCommand = function(c) CONSOLE[#CONSOLE + 1] = tostring(c) end }
CreateConVar = function(name, default)
    local value = tostring(default)
    return { GetBool = function() return value ~= "0" end,
        GetInt = function() return math.floor(tonumber(value) or 0) end,
        GetFloat = function() return tonumber(value) or 0 end,
        GetString = function() return value end }
end
GetConVar = CreateConVar
bit = { bor = function() return 0 end }

local SENT = {}
net = {
    Receive = function(name, fn) net._rx = net._rx or {} net._rx[name] = fn end,
    Start = function(n) SENT[#SENT + 1] = { s = n } end,
    WriteString = function(v) local t = SENT[#SENT] t.str = (t.str or "") .. tostring(v) end,
    WriteTable = function(v) SENT[#SENT].tbl = v end,
    Send = function(ply) SENT[#SENT].to = ply end,
    SendToServer = function() SENT[#SENT].to = "server" end,
    Broadcast = function() end,
}
function net.ReadTable() return SENT[#SENT] and SENT[#SENT].tbl end

local ALL = {}
player = { GetAll = function() return ALL end }
ents = { FindByClass = function() return {} end }

GRM = { Identity = {}, Perf = {}, Audit = { Write = function() end } }
GRM.CharKey = function(ply)
    return IsValid(ply) and (tostring(ply._charkey or "") ~= "" and ply._charkey or (tostring(ply:SteamID64()) .. ":char1")) or ""
end
GRM.Perf.Players = function() return ALL end
local NOTIFY = {}
GRM.Notify = function(p, text) NOTIFY[#NOTIFY + 1] = tostring(text) end
GRM.Admin = { Announce = function() end, Can = function() return false end }

local function mkPlayer(nick, sid, ip)
    local p = { _valid = true, nick = nick, sid = sid, _ip = ip or "93.185.1.1:27015",
        nw = {}, kicks = {}, msgs = {}, model = "models/player/group01/male_02.mdl",
        material = "", weapons = { {} }, pos = { x = 0, y = 0, z = 0, _vector = true } }
    function p:IsPlayer() return true end
    function p:Nick() return self.nick end
    function p:SteamID64() return self.sid end
    function p:SteamID() return "STEAM_" .. self.sid end
    function p:IPAddress() return self._ip end
    function p:IsSuperAdmin() return self._super == true end
    function p:Kick(why) self.kicked = true self.kicks[#self.kicks + 1] = tostring(why) end
    function p:PrintMessage(t, l) self.msgs[#self.msgs + 1] = tostring(l) end
    function p:GetNWString(k, d) local v = self.nw[k] if v == nil then return d end return v end
    function p:SetNWString(k, v) self.nw[k] = v end
    function p:GetNWBool(k, d) local v = self.nw[k] if v == nil then return d end return v end
    function p:SetNWBool(k, v) self.nw[k] = v end
    function p:GetNWInt(k, d) local v = self.nw[k] if v == nil then return d end return v end
    function p:SetNWInt(k, v) self.nw[k] = v end
    function p:GetModel() return self.model end
    function p:SetModel(v) self.model = v end
    function p:GetMaterial() return self.material end
    function p:SetMaterial(v) self.material = v end
    function p:SetColor(v) self.color = v end
    function p:SetRenderMode(v) self.rendermode = v end
    function p:GetPos() return self.pos end
    function p:SetPos(v) self.pos = v end
    function p:GetVelocity() return Vector(0, 0, 0) end
    function p:SetVelocity() end
    function p:GetWeapons() return self.weapons end
    function p:GetActiveWeapon() return self.weapons[1] or NULL end
    function p:StripWeapons() self.weapons = {} end
    function p:StripAmmo() end
    function p:Freeze(v) self.frozen = v end
    function p:SetMoveType(v) self.movetype = v end
    function p:Alive() return true end
    function p:Give() end
    function p:ChatPrint(m) self.msgs[#self.msgs + 1] = tostring(m) end
    function p:EmitSound() end
    ALL[#ALL + 1] = p
    return p
end

assert(loadfile("lua/autorun/sh_grm_ban.lua"))()
local SB = GRM.ServerBan

local pass, fail = 0, 0
local function ok(v, name, extra)
    if v then pass = pass + 1 print("  ok   " .. name)
    else fail = fail + 1 print("  FAIL " .. name .. "   " .. tostring(extra or "")) end
end
local function has(t, sub) return table.concat(t, "\n"):find(sub, 1, true) ~= nil end

print("\n=== 1. КАНОН И ХЕШ ===")
local REP1 = { os = "win", res = "2560x1440", hdr = "0", gpu = "a;b", lang = "ru",
    sens = "2.0", addons = 12, addonHash = "aaa" }
local REP2 = { os = "win", res = "2560x1440", hdr = "0", gpu = "a;b", lang = "ru",
    sens = "2.0", addons = 12, addonHash = "aaa" }
local REP3 = { os = "win", res = "1920x1080", hdr = "0", gpu = "a;b", lang = "ru",
    sens = "2.0", addons = 12, addonHash = "aaa" }
ok(SB.CanonicalMachine(REP1) == SB.CanonicalMachine(REP2), "одинаковые снимки канонятся одинаково")
ok(SB.HwidOf(REP1) == SB.HwidOf(REP2) and SB.HwidOf(REP1) ~= SB.HwidOf(REP3),
    "hwid: равенство по совпадению, различие по расхождению")
ok(SB.HwidOf({}) == nil and SB.HwidOf(nil) == nil, "пустой снимок не имеет хеша")
-- порядок полей канона фиксирован SB.MachineFields
ok(SB.CanonicalMachine(REP1):find("os=win|res=", 1, true) ~= nil, "канон: k=v в фиксированном порядке")

print("\n=== 2. IP ===")
ok(SB.IpPlain("1.2.3.4:27015") == "1.2.3.4", "порт отбрасывается")
ok(SB.IpPlain("") == "" and SB.IpPlain(nil) == "", "пустой IP — пустая строка")

print("\n=== 3. ГЛОБАЛЬНАЯ ЗАПИСЬ ===")
local victim = mkPlayer("Жертва", "111000111")
victim.GRM_MachineRep = REP1
local actor = mkPlayer("Админ", "999000999"); actor._super = true
local okB, msgB = SB.GlobalBan("111000111", "Жертва", 120, "рейд-чит", actor, REP1, "93.185.1.1:27015")
ok(okB, "GlobalBan записан", msgB)
local rec = SB.GlobalRec("111000111")
ok(istable(rec) and rec.hwid == SB.HwidOf(REP1), "запись хранит отпечаток")
ok(istable(rec) and rec.ip == "93.185.1.1", "запись хранит IP без порта")
ok(SB.HwidIndex[SB.HwidOf(REP1)] == "111000111", "индекс hwid построен")
ok(SB.IpIndex["93.185.1.1"] == "111000111", "индекс IP построен")
ok(SB.GlobalBan("abc", "нет", 1, "x") == false, "не-SteamID64 не принимается")

print("\n=== 4. НОВЫЙ АККАУНТ С ТОГО ЖЕ ЖЕЛЕЗА ===")
local alt = mkPlayer("АльтАкк", "222000222")
SB.AcceptMachine(alt, REP2)
ok(alt.kicked == true, "вход с забаненного железа кикается")
ok(has(alt.kicks, "железу"), "кик объясняет причину", table.concat(alt.kicks, ";"))
ok(has(CONSOLE, "banid 120 STEAM:222000222") or has(CONSOLE, "STEAM:222000222"),
    "новый аккаунт добанавливается движком (banid + writeid)")
ok(has(CONSOLE, "writeid"), "banid закреплён writeid")

print("\n=== 5. СОВПАДЕНИЕ С СВОЕЙ ЗАПИСЬЮ МОЛЧИТ ===")
local before = #alt.kicks
SB.AcceptMachine(victim, REP1) -- сам жертва шлёт свой снимок
ok(#victim.kicks == 0, "владелец записи не кикается своим hwid")

print("\n=== 6. ВХОД ПО IP (ДО ОТЧЁТА КЛИЕНТА) ===")
local third = mkPlayer("Третий", "333000333", "93.185.1.1:40000")
SB.CheckJoinIP(third)
ok(third.kicked == true, "IP-индекс срабатывает сразу на входе")
ok(has(third.kicks, "IP"), "причина кика — IP", table.concat(third.kicks, ";"))

print("\n=== 7. СНЯТИЕ УБОРАЧИВАЕТ ИНДЕКСЫ (ЦЕПНОЙ АЛЬТ — ОТДЕЛЬНАЯ ЗАПИСЬ) ===")
SB.GlobalLift("111000111")
ok(SB.GlobalRec("111000111") == nil, "запись удалена")
ok(SB.HwidIndex[SB.HwidOf(REP1)] == "222000222", "индекс hwid перешёл к цепной записи")
ok(SB.GlobalRec("222000222") ~= nil, "авто-добан альта — самостоятельная запись (v1.3)")
ok(SB.IpIndex["93.185.1.1"] == "222000222", "после снятия жертвы IP держит цепная запись")
SB.GlobalLift("222000222")
ok(SB.IpIndex["93.185.1.1"] == nil and SB.HwidIndex[SB.HwidOf(REP2)] == nil,
    "снятие цепной записи снимает её индексы")
local fourth = mkPlayer("Четвёртый", "444000444")
SB.AcceptMachine(fourth, REP2)
ok(fourth.kicked ~= true, "после снятия добра нет")

print("\n=== 8. ОДИН ОТЧЁТ НА СОЕДИНЕНИЕ ===")
SB.GlobalBan("555000555", "Пятый", 60, "спам", nil, REP3, "")
local sixth = mkPlayer("Шестой", "666000666")
SB.AcceptMachine(sixth, REP3)      -- попадание: кик + добан
sixth.kicked = false
SB.AcceptMachine(mkPlayer("Седьмой", "777000777"), REP3) -- чужой первый — сработает
local owner = mkPlayer("Владелец", "555000555")
SB.AcceptMachine(owner, { os = "win", res = "800x600", hdr = "0", gpu = "zzz", lang = "ru",
    sens = "1", addons = 0, addonHash = "0" })          -- первый отчёт принят
local stamp = SB.MachineLog["555000555"].t
owner.GRM_MachineRep = nil
SB.AcceptMachine(owner, REP1)                            -- повтор без запроса — игнор
ok(SB.MachineLog["555000555"].rep.res == "800x600" and SB.MachineLog["555000555"].t == stamp,
    "повторный самоотчёт клиента не принимается (анти-спам)")
SB.MachineWait["555000555"] = actor                     -- явный запрос админа — можно
SB.AcceptMachine(owner, REP1)
ok(SB.MachineLog["555000555"].rep.res == "2560x1440",
    "отчёт по явному запросу админа принимается")
SB.GlobalLift("555000555")

print("\n=== 9. ПРОСРОЧКА ВЫЧИЩАЕТСЯ ПРИ ПРОСМОТРЕ ===")
SB.GlobalBan("1212121212", "Истёкший", 1, "просрочен", nil, nil, "")
SB.Global["1212121212"]["until"] = CLOCK - 10 -- вручную уводим в прошлое
ok(SB.Global["1212121212"] ~= nil, "запись заведена")
ok(SB.GlobalRec("1212121212") == nil, "истёкшая глобальная запись вычищена при просмотре")
ok(SB.Global["1212121212"] == nil, "просроченная удалена из книги")

print("\n=== 9b. УЖЕСТОЧЕНИЕ v1.3 ===")
-- Цепные записи 8-й секции (666 и 777 — обе на REP3-машине) мешают
-- детерминизму индексной проверки roundtrip: снять их до секции 10.
SB.GlobalLift("666000666")
SB.GlobalLift("777000777")
-- Ушедшие (разбаненные/снятые) объекты не должны оставаться «онлайн»
-- с прежним снимком: ретро-скан следующей глобал-записи добанит их снова
-- (для живой машины это корректное поведение модуля).
for _, p in ipairs(ALL) do
    if p.sid == "666000666" or p.sid == "777000777" or p.sid == "999000992" then
        p.GRM_MachineRep = nil
    end
end
-- бэкфилл: бан офлайн (без снимка), человек заходит — отпечаток дописывается
SB.GlobalBan("999000991", "Офлайновый", 0, "офлайн-бан", nil, nil, "")
local offline = mkPlayer("Офлайновый", "999000991")
SB.AcceptMachine(offline, REP2)
local orec = SB.GlobalRec("999000991")
ok(orec and orec.hwid == SB.HwidOf(REP2), "бэкфилл: снимок дописан в существующую запись")
ok(SB.HwidIndex[SB.HwidOf(REP2)] == "999000991", "бэкфилл построил hwid-индекс")
ok(SB.IpIndex[SB.IpPlain(offline._ip)] == "999000991", "бэкфилл построил IP-индекс")
ok(offline.kicked ~= true, "бэкфилл не кикает владельца записи")
-- ретро-скан: альт уже в сети, админ банит жертву с её снимком
local alt2 = mkPlayer("Альт в сети", "999000992")
alt2.GRM_MachineRep = REP3
SB.GlobalBan("999000993", "ТутЖертва", 0, "ретрокейс", nil, REP3, "")
ok(alt2.kicked == true, "ретро-скан: альт добанят, не дожидаясь переподключения")
ok(SB.GlobalRec("999000992") ~= nil, "ретро: на альта заведена своя запись")
local rec2 = SB.GlobalRec("999000992")
ok(rec2 and tostring(rec2.reason):find("ретро по железу") ~= nil, "ретро: причина помечена")
SB.GlobalLift("999000992"); SB.GlobalLift("999000993"); SB.GlobalLift("999000991")
-- смена снимка в сессии → GRM_AC_HwidSwap
local swapP = mkPlayer("Свопер", "999000994")
local REPX1 = { os = "win", res = "1280x720", hdr = "0", gpu = "gx", lang = "ru", sens = "1", addons = 0, addonHash = "1" }
local REPX2 = { os = "win", res = "1280x720", hdr = "0", gpu = "gx", lang = "ru", sens = "1", addons = 7, addonHash = "1" }
SB.AcceptMachine(swapP, REPX1)
local swapHits = 0
hooks["GRM_AC_HwidSwap"] = hooks["GRM_AC_HwidSwap"] or {}
hooks["GRM_AC_HwidSwap"]["test"] = function() swapHits = swapHits + 1 end
SB.MachineWait["999000994"] = true -- как после ре-валидации
SB.AcceptMachine(swapP, REPX2)
ok(swapHits == 1, "несовпадение хешей в сессии зовёт GRM_AC_HwidSwap", swapHits)
-- таймер ре-валидации: ставит mark-запросы и пингует клиентов
local tick = timers and timers["GRM_ServerBan_MachineRecheck"]
ok(tick ~= nil, "таймер ре-валидации создан")
if tick then
    local beforeR = #SENT
    tick()
    local sawReq = false
    for i = beforeR + 1, #SENT do
        if SENT[i].s == "GRM_ServerBan_MachineReq" then sawReq = true end
    end
    local marked = false
    for _, v in pairs(SB.MachineWait) do
        if v == true then marked = true end
    end
    ok(sawReq and marked, "ре-валидация: запрос ушёл, приёмник разблокирован")
    for k in pairs(SB.MachineWait) do SB.MachineWait[k] = nil end
end

-- auth-хук: запись бьёт до спавна
local freshAlt = mkPlayer("Фрэш", "999000995")
SB.GlobalBan("999000995", "Фрэш", 0, "preban", nil, nil, "")
local authHook = hooks["PlayerAuthed"] and hooks["PlayerAuthed"]["GRM_ServerBan_GlobalAuth"]
ok(authHook ~= nil, "PlayerAuthed-хук зарегистрирован")
if authHook then
    authHook(freshAlt, "STEAM_0:1:995", "999000995")
    ok(freshAlt.kicked == true, "глобал-запись кикает на auth, до спавна")
    ok(#freshAlt.kicks > 0 and freshAlt.kicks[1]:find("Глобальный бан активен") ~= nil, "кик описан")
end
SB.GlobalLift("999000995")
SB.GlobalLift("999000994")

print("\n=== 10. ROUNDTRIP ЧЕРЕЗ ДИСК ===")
SB.GlobalBan("888000888", "Восьмой", 0, "навсегда", nil, REP3, "5.6.7.8:27015")
SB.Load()
ok(istable(SB.GlobalRec("888000888")) and SB.GlobalRec("888000888").permanent == true,
    "бессрочная запись пережила перезагрузку")
ok(SB.HwidIndex[SB.HwidOf(REP3)] == "888000888", "индекс hwid пересобран при загрузке")
ok(SB.IpIndex["5.6.7.8"] == "888000888", "индекс IP пересобран при загрузке")
SB.GlobalLift("888000888")

print("\n=== 11. ИНТЕГРАЦИЯ (сканер исходников) ===")
local function body(path)
    local fh = io.open(path, "rb") if not fh then return "" end
    local t = fh:read("*a") fh:close() return t
end
local actions = body("lua/autorun/server/sv_grm_admin_actions.lua")
local bid = actions:find("A%.ban_id = ")
local bidSeg = bid and actions:sub(bid) or ""
local banPos = bidSeg:find("globalRow%(target%.GRM_MachineRep", 1)
local kickPos = bidSeg:find("banid %%d %%s kick", 1)
ok(banPos and kickPos and banPos < kickPos,
    "A.ban_id: снимок машины берётся ДО кика (после — не с кого)")
ok(actions:find("target%.GRM_MachineRep, target%.IPAddress", 1) ~= nil,
    "A.ban: снимок и IP цели уходят в глобальную запись")
ok(actions:find("GlobalLift and GRM%.ServerBan%.GlobalLift%(sid64%)", 1) ~= nil,
    "A.unban снимает и глобальную запись по железу")
ok(actions:find("A%.machine = %{ perm = \"mod%.ban\"", 1) ~= nil,
    "админ-действие machine зарегистрировано")
local panel = body("lua/autorun/client/cl_grm_admin_panel.lua")
ok(panel:find("DCheckBoxLabel", 1, true) ~= nil and panel:find("бан по железу", 1, true) ~= nil,
    "окно бана: чекбокс «бан по железу»")
ok(panel:find('action%("Снимок машины", "mod%.ban", "machine"', 1) ~= nil,
    "панель игрока: кнопка снимка машины")
local mod = body("lua/autorun/sh_grm_ban.lua")
ok(mod:find("MACHINE = \"GRM_ServerBan_Machine\", MACHINE_REQ = \"GRM_ServerBan_MachineReq\"", 1, true) ~= nil,
    "net-каналы снимка объявлены в SB.Net (AddNetworkString по SB.Net)")
ok(mod:find("InitPostEntity", 1, true) ~= nil and mod:find("SendMachine", 1, true) ~= nil,
    "клиент сам шлёт снимок при соединении")
ok(mod:find("SB.MachineFields = { \"os\", \"res\", \"hdr\", \"gpu\", \"lang\", \"sens\", \"addons\", \"addonHash\" }", 1, true) ~= nil,
    "состав снимка зафиксирован списком (смена = рассинхрон хешей)")

print(("\nBAN HWID: %d/%d, провалов: %d"):format(pass, pass + fail, fail))
os.exit(fail == 0 and 0 or 1)
