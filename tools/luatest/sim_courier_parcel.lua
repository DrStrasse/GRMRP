--[[--------------------------------------------------------------------
    sim_courier_parcel — у курьера появилась настоящая посылка.

    БАГ (разбор 29.08). Шаблон обещал «Доставьте посылку в точку города»,
    но посылки не существовало: ни предмета, ни энтити, ни проверки, что
    ты вообще что-то несёшь. Работа сводилась к «дойди до координаты».
    Курьера нельзя было ограбить, посылку — потерять или украсть, то есть
    у механики не было ни одного пересечения с другими игроками.

    ЧТО ПРОВЕРЯЕМ:
      1. взял заказ — в руках появилась посылка (энтити grm_parcel);
      2. без посылки точка доставки НЕ засчитывается;
      3. дошёл с посылкой — заказ закрыт, посылка исчезла;
      4. умер по дороге — посылка выпала в мир, работа провалена;
      5. выпавшую посылку может подобрать ДРУГОЙ игрок (кража);
      6. отказ от работы убирает посылку из рук.

    Запуск: luajit tools/luatest/sim_courier_parcel.lua
----------------------------------------------------------------------]]
SERVER, CLIENT = true, false
function AddCSLuaFile() end
NULL = { _valid = false }

local now = 100
function CurTime() return now end
function IsValid(v) return type(v) == "table" and v._valid ~= false end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function isfunction(v) return type(v) == "function" end
local VMT = {}
VMT.__index = VMT
function VMT:DistToSqr(o) local a, b, c = self.x - o.x, self.y - o.y, self.z - o.z return a * a + b * b + c * c end
function VMT:Distance(o) return math.sqrt(self:DistToSqr(o)) end
VMT.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
VMT.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
function Vector(x, y, z)
    return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VMT)
end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
function table.Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
math.Clamp = function(v, lo, hi) if v < lo then return lo end if v > hi then return hi end return v end

local HOOKS = {}
hook = {
    Add = function(ev, name, fn) HOOKS[ev] = HOOKS[ev] or {} HOOKS[ev][name] = fn end,
    Remove = function(ev, name) if HOOKS[ev] then HOOKS[ev][name] = nil end end,
    Run = function() end,
}
local function fire(ev, ...) for _, fn in pairs(HOOKS[ev] or {}) do fn(...) end end

timer = { Create = function() end, Simple = function(_, fn) fn() end, Remove = function() end }
util = { AddNetworkString = function() end }
net = { Receive = function() end, Start = function() end, Send = function() end,
        WriteTable = function() end, WriteUInt = function() end, WriteString = function() end }

--[[ Грузим НАСТОЯЩИЙ код энтити посылки, а не пишем заглушку: иначе
     стенд проверял бы выдуманное поведение. Из init.lua берём методы
     AttachTo/Detach/OnRemove, а NetworkVar-аксессоры (SetCarrier,
     SetOwnerKey и прочие из SetupDataTables) подменяем простым
     хранилищем — сеть в моке всё равно не работает. ]]
local ENT = {}
do
    _G.ENT = ENT
    -- include подтягивает shared.lua (там SetupDataTables) — в моке
    -- сетевые переменные не нужны, аксессоры подставим сами.
    _G.include = function() end
    local chunk = assert(loadfile("lua/entities/grm_parcel/init.lua"))
    chunk()
end

local function attachNetworkVars(e)
    local store = {}
    local function accessor(name, default)
        e["Set" .. name] = function(self, v) store[name] = v end
        e["Get" .. name] = function(self) local v = store[name] if v == nil then return default end return v end
    end
    accessor("Carrier", NULL)
    accessor("OwnerKey", "")
    accessor("Label", "")
    accessor("Fragile", false)
end

-- Фабрика энтити: считаем созданные и удалённые посылки.
local SPAWNED = {}
ents = {
    Create = function(cls)
        local e = { _valid = true, _class = cls, nw = {}, _pos = Vector(0, 0, 0) }
        function e:SetModel() end
        function e:SetMoveType() end
        function e:SetSolid() end
        function e:SetCollisionGroup() end
        function e:PhysicsInit() end
        function e:SetPos(v) self._pos = v end
        function e:GetPos() return self._pos end
        function e:SetAngles() end
        function e:SetLocalPos() end
        function e:SetLocalAngles() end
        function e:SetParent(p) self._parent = p end
        function e:GetParent() return self._parent end
        function e:Spawn() end
        function e:Activate() end
        function e:GetClass() return self._class end
        function e:EntIndex() return 100 + #SPAWNED end
        function e:Remove() self._valid = false end
        function e:NextThink() end
        function e:GetPhysicsObject() return { _valid = true, Wake = function() end, EnableMotion = function() end } end
        function e:SetNWString(k, v) self.nw[k] = v end
        function e:GetNWString(k, d) local v = self.nw[k] if v == nil then return d end return v end
        function e:SetNWEntity(k, v) self.nw[k] = v end
        function e:GetNWEntity(k) return self.nw[k] or NULL end
        -- Настоящие методы посылки поверх мока энтити.
        if cls == "grm_parcel" then
            for k, v in pairs(ENT) do if type(v) == "function" then e[k] = v end end
            attachNetworkVars(e)
            if e.Initialize then e:Initialize() end
        end
        SPAWNED[#SPAWNED + 1] = e
        return e
    end,
    FindByClass = function() return {} end,
    FindInSphere = function() return {} end,
}
player = { GetAll = function() return {} end }

GRM = { Jobs = {}, Notify = function() end, Format = tostring }
local JB = GRM.Jobs

local ACTIVE = {}
JB.GetActiveJob = function(p) return ACTIVE[p] end
JB.PushTracker = function() end
JB.PushMyState = function() end
JB.SaveActive = function() end

local FAILED, COMPLETED = {}, {}
JB.Fail = function(p, why) FAILED[#FAILED + 1] = { who = p, why = why } ACTIVE[p] = nil end
JB.Complete = function(p) COMPLETED[#COMPLETED + 1] = p ACTIVE[p] = nil end

assert(loadfile("lua/autorun/sh_grm_jobs_courier.lua"))()

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

local function mkPlayer(name)
    local p = { _valid = true, nw = {}, _pos = Vector(0, 0, 0), _alive = true }
    function p:GetPos() return self._pos end
    function p:SetPos(v) self._pos = v end
    function p:Alive() return self._alive end
    function p:IsPlayer() return true end
    function p:Nick() return name end
    function p:GetNWString(_, d) return name end
    function p:SetNWEntity(k, v) self.nw[k] = v end
    function p:GetNWEntity(k) return self.nw[k] or NULL end
    function p:SetNWBool(k, v) self.nw[k] = v end
    function p:GetNWBool(k, d) local v = self.nw[k] if v == nil then return d end return v end
    function p:ChatPrint() end
    function p:GetShootPos() return self._pos end
    function p:GetAimVector() return Vector(1, 0, 0) end
    function p:EyeAngles() return Angle(0, 0, 0) end
    return p
end

print("\n=== 1. ВЗЯЛ ЗАКАЗ — В РУКАХ ПОСЫЛКА ===")
local courier = mkPlayer("Курьер")
ACTIVE[courier] = { tplId = "courier", jtype = "goto",
                    target = Vector(1000, 0, 0), zoneRadius = 170, title = "Курьер" }

ok(isfunction(JB.GiveParcel), "есть выдача посылки")
if isfunction(JB.GiveParcel) then JB.GiveParcel(courier, ACTIVE[courier]) end
local parcel = courier:GetNWEntity("GRM_Parcel")
ok(IsValid(parcel), "посылка появилась в руках")
ok(IsValid(parcel) and parcel:GetClass() == "grm_parcel", "это энтити grm_parcel",
    IsValid(parcel) and parcel:GetClass())

print("\n=== 2. БЕЗ ПОСЫЛКИ ТОЧКА НЕ ЗАСЧИТЫВАЕТСЯ ===")
--[[ Смысл всей механики: доставка — это доставка ГРУЗА. Если посылку
     отняли или потеряли, дойти до адреса недостаточно. ]]
ok(isfunction(JB.HasParcel), "есть проверка «несёт ли посылку»")
ok(JB.HasParcel(courier) == true, "курьер с посылкой определяется")
local emptyHanded = mkPlayer("Пустой")
ok(JB.HasParcel(emptyHanded) == false, "без посылки — false")

print("\n=== 3. ДОШЁЛ С ПОСЫЛКОЙ — ЗАКАЗ ЗАКРЫТ ===")
ok(isfunction(JB.DeliverParcel), "есть сдача посылки")
courier:SetPos(Vector(1000, 0, 0))
JB.DeliverParcel(courier, ACTIVE[courier])
ok(not IsValid(parcel), "посылка исчезла из рук после сдачи")
ok(not IsValid(courier:GetNWEntity("GRM_Parcel")), "ссылка в руках очищена")

print("\n=== 4. СМЕРТЬ В ПУТИ — ПОСЫЛКА ПАДАЕТ В МИР ===")
local courier2 = mkPlayer("Курьер2")
ACTIVE[courier2] = { tplId = "courier", jtype = "goto",
                     target = Vector(1000, 0, 0), zoneRadius = 170, title = "Курьер" }
JB.GiveParcel(courier2, ACTIVE[courier2])
local parcel2 = courier2:GetNWEntity("GRM_Parcel")
ok(IsValid(parcel2), "вторая посылка выдана")

courier2._alive = false
fire("PlayerDeath", courier2)
ok(not IsValid(courier2:GetNWEntity("GRM_Parcel")), "из рук убитого посылка ушла")
ok(IsValid(parcel2) and not IsValid(parcel2:GetParent()),
    "посылка осталась в мире, а не удалилась вместе с телом")

print("\n=== 5. ВЫПАВШУЮ ПОСЫЛКУ МОЖЕТ ЗАБРАТЬ ДРУГОЙ ===")
--[[ Ради этого всё и делалось: посылка становится предметом, за который
     возможна борьба. Чужой курьер поднимает её и может донести сам. ]]
local thief = mkPlayer("Вор")
ACTIVE[thief] = { tplId = "courier", jtype = "goto",
                  target = Vector(1000, 0, 0), zoneRadius = 170, title = "Курьер" }
ok(isfunction(JB.PickupParcel), "есть подбор брошенной посылки")
local took = JB.PickupParcel(thief, parcel2)
ok(took == true, "посылка подобрана", tostring(took))
ok(JB.HasParcel(thief) == true, "теперь она в руках у нашедшего")

print("\n=== 6. ОТКАЗ ОТ РАБОТЫ УБИРАЕТ ПОСЫЛКУ ===")
local courier3 = mkPlayer("Курьер3")
ACTIVE[courier3] = { tplId = "courier", jtype = "goto",
                     target = Vector(1000, 0, 0), zoneRadius = 170, title = "Курьер" }
JB.GiveParcel(courier3, ACTIVE[courier3])
ok(JB.HasParcel(courier3) == true, "посылка на руках перед отказом")
fire("GRM_Jobs_Failed", courier3, ACTIVE[courier3], "отказ")
ok(JB.HasParcel(courier3) == false, "после провала работы руки пусты")

print("\n=== 7. МОДУЛЬ ПОДПИСАН НА РЕАЛЬНЫЕ ХУКИ ЯДРА ===")
--[[ Ядро объявляет о старте работы хуком GRM_Jobs_Started. Подписка на
     несуществующее имя (например GRM_Jobs_Accepted) молча ничего не
     делала бы: посылка не выдавалась, а работа при этом шла. ]]
local core = io.open("lua/autorun/sh_grm_jobs.lua"):read("*a")
local courier = io.open("lua/autorun/sh_grm_jobs_courier.lua"):read("*a")
ok(core:find('hook.Run("GRM_Jobs_Started"', 1, true) ~= nil, "ядро шлёт GRM_Jobs_Started")
ok(courier:find('hook.Add("GRM_Jobs_Started"', 1, true) ~= nil,
    "курьер слушает именно его, а не выдуманное имя")
ok(HOOKS["GRM_Jobs_Started"] ~= nil and next(HOOKS["GRM_Jobs_Started"]) ~= nil,
    "обработчик выдачи посылки зарегистрирован")

print("\n=== 8. ЯДРО НЕ ЗАСЧИТЫВАЕТ ТОЧКУ БЕЗ ПОСЫЛКИ ===")
--[[ Самая важная связка. Если ядро закрывает goto по одной координате,
     предмет ничего не значит: отняли посылку — всё равно дошёл и получил
     деньги. Проверяем по телу обработчика goto, а не по всему файлу:
     упоминание HasParcel где-то ещё нас бы обмануло. ]]
local gotoBody = core:match("else %-%- goto(.-)\n%s*end%s*\n%s*end%s*\n%s*end") or
                 core:match("else %-%- goto(.-)\n%s*end") or ""
ok(gotoBody:find("tplId ==", 1, true) ~= nil and gotoBody:find("HasParcel", 1, true) ~= nil,
    "в ветке goto есть проверка курьерской посылки")
ok(gotoBody:find("DeliverParcel", 1, true) ~= nil,
    "сдача идёт через DeliverParcel, а не голым Complete")
ok(gotoBody:find("JB.Complete(ply)", 1, true) ~= nil,
    "остальные goto-задачи закрываются как раньше")

print(("\nCOURIER PARCEL: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
