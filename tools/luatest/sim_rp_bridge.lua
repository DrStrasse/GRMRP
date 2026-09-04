--[[ sim_rp_bridge — ЕДИНАЯ шина GRM.RPBroadcast в рантайме (вечер-15).
    Файл шина грузится НАСТОЯЩИМ dofile; владелец чата — перехватчик opts.
    Проверяем: радиус-клермы, адресность (Player/список/таблица), проброс
    echoAuthor/rpName, фолбэк без владельца = ТОЛЬКО ChatPrint (ветка старой
    net-шины GRM_RPChat_Msg вырезана приказом «всё своё»; стенд это ловит),
    SUPPRESSED-владелец пропускается, алиас GRMChat==GRMRPChat не удваивает. ]]
local total, fails = 0, 0
local function T2(name, cond, note)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print(("  FAIL %-58s %s"):format(name, tostring(note or ""))) end
end

-- ---------- стабы ----------
local printed, netStarts = {}, {}
local function mkPlayer(name, x)
    local p = { __n = name, __x = x, __print = {} }
    function p:Name() return self.__n end
    function p:Nick() return self.__n end
    function p:IsPlayer() return true end
    function p:Alive() return true end
    function p:GetPos()
        local me = self.__x
        return { x2 = me, DistToSqr = function(_, o) local d = me - o.x2 return d * d end }
    end
    function p:GetNWString(cv, dflt) return self.__rp or dflt end
    function p:ChatPrint(s) self.__print[#self.__print + 1] = s printed[#printed + 1] = { self, s } end
    return p
end
local A, B, C
local g = _G
g.IsValid = function(v) return type(v) == "table" end
g.isstring = function(v) return type(v) == "string" end
g.isnumber = function(v) return type(v) == "number" end
g.istable = function(v) return type(v) == "table" end
g.isfunction = function(v) return type(v) == "function" end
g.isplayer = function(v)
    return type(v) == "table" and v.IsPlayer ~= nil and v:IsPlayer() == true
end
g.math.Clamp = g.math.Clamp or function(v, a, b) return math.max(a, math.min(b, v)) end
g.string.Trim = g.string.Trim or function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
g.SERVER, g.CLIENT = true, false
g.net = { Start = function(n) netStarts[#netStarts + 1] = n end }
g.util = { NetworkStringToID = function() return 42 end } -- «старая шина жива» — не помочь ли ей
local function pool() return { A, B, C } end
g.player = { GetAll = pool }

A, B, C = mkPlayer("Ann", 0), mkPlayer("Bob", 100), mkPlayer("Cal", 900)

-- ---------- загрузка боевой шины ----------
local root = arg[0]:match("^(.*)[/\\]tools[/\\]luatest") or "."
dofile(root .. "/lua/autorun/sh_grm_rpbridge.lua")
T2("шина загрузилась (GRM.RPBroadcast есть)", isfunction(GRM.RPBroadcast))
T2("GetRPName: без NW — Nick-фолбэк", GRM.GetRPName(A) == "Ann")
A.__rp = "Анна Я."
T2("GetRPName: RP-имя приоритетно", GRM.GetRPName(A) == "Анна Я.")

-- ---------- владелец-перехватчик ----------
local calls = {}
local owner = {
    Channels = setmetatable({}, { __index = function() return {} end }),
    HARD_MAX = 900,
    Sanitize = function(s) return s end,
    Enabled = function() return true end,
}
function owner.RPAction(kind, ply, body, chanId, opts)
    calls[#calls + 1] = { kind = kind, ply = ply, body = body, opts = opts }
    return nil
end
_G.GRMRPChat = owner

local function last() return calls[#calls] end
local function clear() calls = {} printed = {} netStarts = {} end

print("\n=== радиусы ===")
clear(); GRM.RPBroadcast(A, "показал документ", nil)
T2("nil → 400 (бланки веч.-8…12)", last() and last().opts.range == 400, last() and last().opts.range)
T2("kind=me, echo автора вкл, targets нет",
    last().kind == "me" and last().opts.echoAuthor == true and last().opts.targets == nil)
clear(); GRM.RPBroadcast(A, "t", 10)
T2("10 → clamp 64", last().opts.range == 64)
clear(); GRM.RPBroadcast(A, "t", 99999)
T2("99999 → clamp 4096", last().opts.range == 4096)
clear(); GRM.RPBroadcast(A, "   ", nil)
T2("пустой текст — молчание", #calls == 0)

print("\n=== адресность (вечер-15) ===")
clear(); GRM.RPBroadcast(A, "предъявляет вам документ", B)
local o = last().opts
T2("Player → targets={B}", istable(o.targets) and #o.targets == 1 and o.targets[1] == B)
clear(); GRM.RPBroadcast(A, "т", { targets = { B, C }, echoAuthor = false, rpName = "Маска" })
o = last().opts
T2("таблица: список, echo off, rpName легенды",
    #o.targets == 2 and o.echoAuthor == false and o.rpName == "Маска" and o.range == 400)
clear(); GRM.RPBroadcast(A, "т", { B, C })
T2("голый массив = список слушателей", #last().opts.targets == 2)
clear(); GRM.RPBroadcast(A, "т", { radius = 500, targets = { B } })
T2("radius+targets вместе", last().opts.range == 500 and #last().opts.targets == 1)

print("\n=== фолбэк без владельца (никакой старой шины!) ===")
_G.GRMRPChat = nil
clear()
GRM.RPBroadcast(A, "представляется окружающим.", 355)
T2("net не трогается вообще (GRM_RPChat_Msg мертва)", #netStarts == 0, table.concat(netStarts, ","))
local gotA, gotB, gotC = 0, 0, 0
for _, rec in ipairs(printed) do
    if rec[1] == A then gotA = gotA + 1 end
    if rec[1] == B then gotB = gotB + 1 end
    if rec[1] == C then gotC = gotC + 1 end
end
T2("ближний (100≤355) получил", gotB == 1)
T2("дальний (900>355) отсечён", gotC == 0)
T2("автор получил (в цикле радиуса)", gotA == 1)
clear()
GRM.RPBroadcast(A, "предъявляет вам документ.", { targets = { B }, echoAuthor = false })
T2("targets-фолбэк: ровно целевой", #printed == 1 and printed[1][1] == B, #printed)
T2("echo off — автор молчит", (function() for _, r in ipairs(printed) do if r[1] == A then return false end end return true end)())
clear()
GRM.RPBroadcast(A, "т", { targets = { B }, echoAuthor = true })
T2("echo on — автор отдельно", #printed == 2)
T2("формат «* Имя действие»", printed[1][2] == "* Анна Я. т", printed[1][2])

print("\n=== подавленные и алиасы ===")
_G.GRMRPChat = owner
clear()
owner.SUPPRESSED = true
GRM.RPBroadcast(A, "т", 355)
T2("SUPPRESSED-владелец пропущен → ChatPrint", #calls == 0 and #printed > 0)
owner.SUPPRESSED = nil
clear()
_G.GRMChat = owner -- алиас того же стола: цикл встанет на первом владельце
GRM.RPBroadcast(A, "т", nil)
T2("алиас: ровно один вызов RPAction (без двойной доставки)", #calls == 1, #calls)
_G.GRMChat = nil
clear()
_G.GRMRPChat = nil
_G.GRMChat = owner -- смешанная установка: отдельный живой порт — шина умеет в него
GRM.RPBroadcast(A, "т", nil)
T2("единственный живой владелец (GRMChat) обслуживает", #calls == 1)
_G.GRMChat = nil

print(("\nRP BRIDGE: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
