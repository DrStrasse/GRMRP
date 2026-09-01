-- Симуляция сервера GMod для sh_grm_achievements.lua + sh_grm_jobs.lua (Коды 77/78)
-- Жизненный цикл: доступ → вакансия → выполнение → деньги → ачивка;
-- заказ фракции: публикация (эскроу) → взятие → выполнение/отзыв (возврат).
string.Trim = function(s) s = tostring(s or ""); return (s:gsub("^%s*(.-)%s*$", "%1")) end
local H = { hooks = {}, netrecv = {}, concommands = {}, timers = {} }
local realPrint = print
local function P(...) realPrint("[SIM]", ...) end

_G._SIM = H
function istable(x) return type(x) == "table" end
function isstring(x) return type(x) == "string" end
function isfunction(x) return type(x) == "function" end
function isnumber(x) return type(x) == "number" end
function IsValid(o) return o ~= nil and o ~= false end
table.Count = function(t) local n = 0 for k in pairs(t or {}) do n = n + 1 end return n end

local VMT = {}
VMT.__index = function(self, k)
    if k == "Distance" then return function(s, o) local dx, dy, dz = s.x - o.x, s.y - o.y, s.z - o.z return math.sqrt(dx * dx + dy * dy + dz * dz) end end
    if k == "DistToSqr" then return function(s, o) local dx, dy, dz = s.x - o.x, s.y - o.y, s.z - o.z return dx * dx + dy * dy + dz * dz end end
    return nil
end
VMT.__add = function(a, b) return setmetatable({ x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }, VMT) end
VMT.__mul = function(a, n) if type(a) == "number" then a, n = n, a end return setmetatable({ x = a.x * n, y = a.y * n, z = a.z * n }, VMT) end
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VMT) end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end

util = {
    AddNetworkString = function() end,
    JSONToTable = function() return nil end,
    TableToJSON = function() return "{}" end,
}
file = { Read = function() return nil end, Write = function() end, Exists = function() return false end, IsDir = function() return true end, CreateDir = function() end }
hook = { Add = function(name, id, fn) H.hooks[name] = H.hooks[name] or {} H.hooks[name][id] = fn end,
         Run = function(name, ...) local fns = H.hooks[name] or {} for id, fn in pairs(fns) do local r = fn(...) if r ~= nil then return r end end end,
         Call = function(name, gm, ...) return hook.Run(name, ...) end }
timer = { Create = function(name, d, r, fn) if type(name) == "function" then fn = name end if fn then H.timers[tostring(name)] = fn end end,
          Simple = function(d, fn) if type(d) == "function" then d() elseif fn then fn() end end,
          Remove = function(name) H.timers[tostring(name)] = nil end }
ents = { FindByClass = function(c) return H.entsByClass and H.entsByClass[c] or {} end,
         Create = function(c) return nil end }
player = { GetAll = function() return H.players or {} end,
           GetBySteamID = function() return nil end,
           GetBySteamID64 = function() return nil end }
game = { GetMap = function() return "gm_test" end }
function CurTime() return 1000 end
HUD_PRINTTALK = 3

local netlog = {}
net = { Start = function(m) netlog.cur = { msg = m } end,
        WriteString = function() end, WriteUInt = function() end, WriteInt = function() end,
        WriteBool = function() end, WriteTable = function() end, WriteVector = function() end,
        Send = function(tg) netlog.sent = netlog.sent or {} table.insert(netlog.sent, { msg = netlog.cur and netlog.cur.msg, to = "P" }) netlog.cur = nil end,
        Broadcast = function() end, SendToServer = function() end,
        Receive = function(m, fn) H.netrecv[m] = fn end }
concommand = { Add = function(n, fn) H.concommands[n] = fn end }
AddCSLuaFile = function() end

-- инъекция входящих net-полей в receiver
local function netInject(msg, fields)
    local i = 0
    net.ReadString = function() i = i + 1 return fields[i] end
    net.ReadUInt = function() i = i + 1 return fields[i] end
    net.ReadInt = function() i = i + 1 return fields[i] end
    net.ReadBool = function() i = i + 1 return fields[i] end
    net.ReadTable = function() i = i + 1 return fields[i] end
    local fn = H.netrecv[msg]
    assert(fn, "нет receiver для " .. tostring(msg))
    fn(0, H._curPly)
    return i
end

-- GRM-деньги: фиксируем выдачу и бросаем хук как настоящая валюта
local moneylog = {}
GRM = GRM or {}
GRM.Format = function(n) return tostring(n) .. " GRM" end
GRM.GiveMoney = function(ply, amount, reason)
    ply._bal = (ply._bal or 1000) + amount
    moneylog[#moneylog + 1] = { ply = ply:Nick(), amount = amount, reason = reason }
    P("MONEY: " .. ply:Nick() .. " +" .. tostring(amount) .. " [" .. tostring(reason) .. "]")
    hook.Run("GRM_MoneyChanged", ply, ply._bal, amount, reason)
    return true
end
GRM.Notify = function(ply, msg, r, g, b) P("NOTIFY[" .. ply:Nick() .. "]: " .. tostring(msg)) end

-- фракции
local LEADER_SID = "STEAM_0:1:111"
Factions = { ["Мэрия"] = { Members = { [LEADER_SID] = true }, Leader = LEADER_SID } }
_G.FactionsAPI = {
    GetFactionOf = function(sid) return sid == LEADER_SID and "Мэрия" or nil end,
    IsLeader = function(sid, f) return sid == LEADER_SID and f == "Мэрия" end,
    GetLeader = function(f) return f == "Мэрия" and LEADER_SID or nil end,
}
local budget = 5000
GRM.FactionBudgetGet = function(f) return budget end
GRM.FactionBudgetAdd = function(f, delta, reason)
    budget = budget + delta
    P("BUDGET: " .. tostring(f) .. " " .. tostring(delta) .. " -> " .. tostring(budget) .. " [" .. tostring(reason) .. "]")
end

local function mkPly(nick, sid, s64, super)
    local p = {
        _pos = Vector(0, 0, 0), _bal = 1000,
        SteamID = function() return sid end,
        SteamID64 = function() return s64 end,
        Nick = function() return nick end,
        IsSuperAdmin = function() return super end,
        IsAdmin = function() return super end,
        IsPlayer = function() return true end,
        Alive = function() return true end,
        InVehicle = function() return false end,
        IsOnGround = function() return true end,
        GetPos = function(self) return self._pos end,
        GetNWString = function() return "" end,
        PrintMessage = function(_, ch, txt) P("CHAT[" .. nick .. "]: " .. tostring(txt)) end,
        GetEyeTrace = function() return {} end,
    }
    return p
end

local leader = mkPly("Мэр", LEADER_SID, "76000000000000111", true)
local worker = mkPly("Курьеров", "STEAM_0:2:222", "76000000000000222", false)
local worker2 = mkPly("Грузов", "STEAM_0:3:333", "76000000000000333", false)
H.players = { leader, worker, worker2 }

-- фейковые энтити карты
local center = { GetPos = function() return Vector(0, 0, 0) end, EntIndex = function() return 7 end, GetClass = function() return "grm_jobcenter" end }
local depotA = { GetPos = function() return Vector(2000, 0, 0) end, GetClass = function() return "grm_depot" end }
local depotB = { GetPos = function() return Vector(-1500, 500, 0) end, GetClass = function() return "grm_depot" end }
H.entsByClass = { grm_jobcenter = { center }, grm_depot = { depotA, depotB } }

SERVER = true
CLIENT = false

P("=== Загрузка sh_grm_achievements.lua ===")
dofile("lua/autorun/sh_grm_achievements.lua")
P("=== Загрузка sh_grm_jobs.lua ===")
dofile("lua/autorun/sh_grm_jobs.lua")

local JB = GRM.Jobs
local AC = GRM.Ach
assert(JB and AC, "модули не поднялись")
assert(#depotA and true, "")

local fails = 0
local function CHECK(name, cond)
    if cond then P("OK: " .. name) else fails = fails + 1 P("FAIL: " .. name) end
end

-- 1) доступ работодателя через чат PlayerSay-контракта
H._curPly = leader
local consumed = H.hooks["PlayerSay"]["GRM_Jobs_ChatCmds"](leader, "/job_allow Мэрия")
CHECK("/job_allow поглощена", consumed == "")
CHECK("Мэрия получила доступ работодателя", JB.Cfg.allow["Мэрия"] == true)

-- 2) вакансии генерируются и принимаются
worker._pos = Vector(0, 0, 0)
JB.OpenMenu(worker, center)
local wsid = worker:SteamID64()
local offers = JB._lastOffers[wsid] and JB._lastOffers[wsid].list or {}
CHECK("вакансий выдано >= 1", #offers >= 1)
CHECK("первая вакансия — курьер (goto)", offers[1] and offers[1].jtype == "goto" and offers[1].tplId == "courier")

H._curPly = worker
netInject("GRM_Jobs_Accept", { offers[1].idx })
CHECK("задача принята", istable(JB.Active[wsid]))
CHECK("улицы живы: idx у вакансии числовой", type(offers[1].idx) == "number")
local job = JB.Active[wsid]
CHECK("у задачи есть цель", job and job.target and math.abs(job.target.x) > 100)

-- 3) движок прогресса: добежал → выполнил → деньги + ачивка
worker._pos = Vector(job.target.x, job.target.y, job.target.z)
JB.TickJobs()
CHECK("задача завершена при прибытии", JB.Active[wsid] == nil)
CHECK("начисление прошло", #moneylog >= 1)
local st = JB.StatsFor(wsid)
CHECK("статистика done=1", st and st.done == 1)
local rec = AC.RecOf(worker)
CHECK("ачивка job1 разблокирована", rec.u.job1 == true)
CHECK("метрика jobsDone=1", (rec.c.jobsDone or 0) == 1)
-- каскад: награда job1 (+500) считается в moneyEarned → first_pay (1000) докрывается — дизайн так задуман
CHECK("first_pay докрылась каскадом наград", rec.u.first_pay == true)
CHECK("метрика moneyEarned выросла", (rec.c.moneyEarned or 0) > 0)

-- 4) заказ фракции: публикация (эскроу) → взятие → смена → выполнение
--    (layout NET_POST v1.1.0: kind, title, desc, jtype, money(u20), shiftSec(u12), shifts(u8), zoneMode)
H._curPly = leader
netInject("GRM_Jobs_Post", { "order", "Патруль парка", "Продежурить на точке", "stay", 1500, 600, 1, "term" })
local posts = JB.Cfg.posts["Мэрия"] or {}
CHECK("заказ опубликован", #posts == 1)
CHECK("эскроу списано (5000-1500=3500)", budget == 3500)
local pid = posts[1] and posts[1].id

H._curPly = worker2
netInject("GRM_Jobs_TakePost", { "Мэрия", pid })
local j2 = JB.Active[worker2:SteamID64()]
CHECK("заказ взят", istable(j2) and j2.fromPost == true)
CHECK("майнер помечен исполнителем", posts[1].takenBy == worker2:SteamID64())
worker2._pos = Vector(j2.target.x, j2.target.y, j2.target.z)
for i = 1, 95 do JB.TickJobs() end
CHECK("stay-заказ выполнен после смены", JB.Active[worker2:SteamID64()] == nil)
CHECK("заказ снят с витрины", #(JB.Cfg.posts["Мэрия"] or {}) == 0)
CHECK("бюджет НЕ дернулся при выплате (эскроу уже списан)", budget == 3500)
local rec2 = AC.RecOf(worker2)
CHECK("метрика jobsFaction у исполнителя", (rec2.c.jobsFaction or 0) == 1)

-- 5) публикация и отзыв: возврат эскроу
H._curPly = leader
netInject("GRM_Jobs_Post", { "order", "Доставка архива", "", "goto", 1200, 600, 1, "term" })
posts = JB.Cfg.posts["Мэрия"] or {}
pid = posts[1] and posts[1].id
CHECK("второй заказ опубликован (3500-1200=2300)", budget == 2300 and pid ~= nil)
netInject("GRM_Jobs_Unpost", { "Мэрия", pid })
CHECK("отзыв вернул эскроу (2300+1200=3500)", budget == 3500)
CHECK("витрина пуста", #(JB.Cfg.posts["Мэрия"] or {}) == 0)

-- 6) ВАКАНСИЯ фракции: зарплата×смены, зона «где стою», две смены двумя рабочими
H._curPly = leader
netInject("GRM_Jobs_Post", { "vacancy", "Завод смена", "Производство боеприпасов", "stay", 400, 300, 2, "here" })
posts = JB.Cfg.posts["Мэрия"] or {}
local vp = posts[1]
CHECK("вакансия опубликована", istable(vp) and vp.kind == "vacancy")
CHECK("зарплата/смены сохранены", vp and vp.salary == 400 and vp.shiftsLeft == 2)
CHECK("эскроу = зарплата × смены (3500-800=2700)", budget == 2700)
CHECK("JB.PostEscrow = 800", JB.PostEscrow(vp) == 800)
CHECK("зона зафиксирована (here)", istable(vp.zone))
pid = vp.id

-- первая смена: worker2
vp.staySec = 5 -- сим-ускорение: короткая смена
H._curPly = worker2
netInject("GRM_Jobs_TakePost", { "Мэрия", pid })
local jv = JB.Active[worker2:SteamID64()]
CHECK("смена взята", istable(jv) and jv.jtype == "shift" and jv.postKind == "vacancy")
CHECK("зарплата в задаче = 400", jv.reward == 400)
CHECK("цель смены = зона вакансии", jv.target and math.abs(jv.target.x - vp.zone.x) < 1)
CHECK("бронь выставлена", vp.takenBy == worker2:SteamID64())
worker2._pos = Vector(vp.zone.x, vp.zone.y, vp.zone.z)
for i = 1, 6 do JB.TickJobs() end
CHECK("первая смена отработана", JB.Active[worker2:SteamID64()] == nil)
CHECK("осталась 1 смена", vp.shiftsLeft == 1)
CHECK("payedTotal=400, lastWorker=Грузов", vp.payedTotal == 400 and vp.lastWorker == "Грузов")
CHECK("бронь снята, вакансия на витрине", vp.takenBy == nil and #(JB.Cfg.posts["Мэрия"] or {}) == 1)
CHECK("бюджет не дёрнулся (эскроу списан при публикации)", budget == 2700)
CHECK("JB.PostEscrow = 400 (остаток)", JB.PostEscrow(vp) == 400)

-- вторая смена: worker закрывает вакансию
vp.staySec = 5
H._curPly = worker
local earnedBefore = JB.StatsFor(worker:SteamID64()).earned
netInject("GRM_Jobs_TakePost", { "Мэрия", pid })
worker._pos = Vector(vp.zone.x, vp.zone.y, vp.zone.z)
for i = 1, 6 do JB.TickJobs() end
CHECK("вторая смена отработана", JB.Active[worker:SteamID64()] == nil)
CHECK("вакансия закрылась (смены исчерпаны)", #(JB.Cfg.posts["Мэрия"] or {}) == 0)
CHECK("статистика worker +400", JB.StatsFor(worker:SteamID64()).earned == earnedBefore + 400)
CHECK("бюджет без возврата (всё выплачено сменами)", budget == 2700)
local recw = AC.RecOf(worker)
CHECK("метрика jobsFaction у второго исполнителя", (recw.c.jobsFaction or 0) == 1)

-- 7) регресс: провал исполнителя НЕ закрывает многоразовую вакансию
H._curPly = leader
netInject("GRM_Jobs_Post", { "vacancy", "Сборка гаек", "", "stay", 300, 300, 2, "here" })
vp = (JB.Cfg.posts["Мэрия"] or {})[#(JB.Cfg.posts["Мэрия"] or {})]
CHECK("вакансия 2 опубликована (2700-600=2100)", budget == 2100 and istable(vp))
pid = vp.id
H._curPly = worker2
netInject("GRM_Jobs_TakePost", { "Мэрия", pid })
c2 = H.hooks["PlayerSay"]["GRM_Jobs_ChatCmds"](worker2, "/jobcancel")
CHECK("исполнитель отказался", c2 == "" and JB.Active[worker2:SteamID64()] == nil)
CHECK("вакансия ЖИВА после провала (бронь снята)", #(JB.Cfg.posts["Мэрия"] or {}) == 1 and vp.takenBy == nil)
CHECK("смены не сгорели", vp.shiftsLeft == 2)
CHECK("эскроу не трогали (ни одна смена не оплачена)", budget == 2100)
H._curPly = leader
netInject("GRM_Jobs_Unpost", { "Мэрия", pid })
CHECK("отзыв свободной вакансии вернул эскроу (2100+600=2700)", budget == 2700)
CHECK("витрина пуста", #(JB.Cfg.posts["Мэрия"] or {}) == 0)

-- 8) регресс: отзыв лидером ЗАНЯТОЙ вакансии — провал исполнителя + полный возврат
H._curPly = leader
netInject("GRM_Jobs_Post", { "vacancy", "Упаковка", "", "stay", 300, 300, 2, "here" })
vp = (JB.Cfg.posts["Мэрия"] or {})[#(JB.Cfg.posts["Мэрия"] or {})]
CHECK("вакансия 3 опубликована (2700-600=2100)", budget == 2100 and istable(vp))
pid = vp.id
H._curPly = worker2
netInject("GRM_Jobs_TakePost", { "Мэрия", pid })
CHECK("смена 3 взята", istable(JB.Active[worker2:SteamID64()]))
H._curPly = leader
netInject("GRM_Jobs_Unpost", { "Мэрия", pid })
CHECK("исполнитель провален отзывом", JB.Active[worker2:SteamID64()] == nil)
CHECK("занятая вакансия снята с витрины", #(JB.Cfg.posts["Мэрия"] or {}) == 0)
CHECK("неизрасходованный эскроу возвращён (2100+600=2700)", budget == 2700)

-- 9) /jobs и /jobcancel через PlayerSay
H._curPly = worker
local c1 = H.hooks["PlayerSay"]["GRM_Jobs_ChatCmds"](worker, "/jobs")
CHECK("/jobs поглощена", c1 == "")
c2 = H.hooks["PlayerSay"]["GRM_Jobs_ChatCmds"](worker, "/jobcancel")
CHECK("/jobcancel поглощена (нет задачи — честно говорит)", c2 == "")

-- 10) чужотные команды не поглощаются
local c3 = H.hooks["PlayerSay"]["GRM_Jobs_ChatCmds"](worker, "/alert test")
CHECK("чужая команда проходит мимо (nil)", c3 == nil)
local c4 = H.hooks["PlayerSay"]["GRM_Ach_ChatCmds"](worker, "/ach")
CHECK("/ach поглощена", c4 == "")

P("=== ИТОГ: " .. (fails == 0 and "ВСЕ ПРОВЕРКИ ПРОШЛИ" or ("ПРОВАЛОВ: " .. tostring(fails))) .. " ===")
os.exit(fails == 0 and 0 or 1)
