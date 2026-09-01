--[[--------------------------------------------------------------------
    sim_industry_job — жизненный цикл задачи на станке.

    ЗАКАЗ ВЛАДЕЛЬЦА (31.08), дословно: «мини-игра пройдена и запускается
    прогресс-бар производства, а игрок может свободно гулять. Это бред».

    ЧТО БЫЛО В СТАРОМ ЦЕХЕ. beginCraft() создавал `timer.Create` и всё.
    У задачи не было владельца, стадии и вложенного сырья. Игрок уходил
    через полкарты и всё равно получал оружие в руки `owner:Give()`.
    Выход с сервера сжигал материалы безвозвратно.

    ЧТО ПРОВЕРЯЕМ ЗДЕСЬ.
      * Задача — объект: знает работника, стадию, вложенное сырьё.
      * Отошёл от станка — работа ВСТАЁТ, а не проваливается и не идёт
        сама. Прогресс замирает.
      * Вернулся — работа продолжается с того же места.
      * Умер / вышел с сервера — пауза с понятной причиной.
      * Продукт идёт в ВЫХОД СТАНКА, а не в руки и не пропом на пол.
      * Брак возвращает часть сырья, а не сжигает его.
      * Заброшенная задача закрывается с возвратом сырья.

    Запуск: luajit tools/luatest/sim_industry_job.lua
----------------------------------------------------------------------]]

local pass, fail = 0, 0
local function ok(v, name, extra)
    if v then pass = pass + 1 print("  ok   " .. name)
    else fail = fail + 1 print("  FAIL " .. name .. "   " .. tostring(extra or "")) end
end

-- ================================================================
--  ОКРУЖЕНИЕ GMod
-- ================================================================
local NOW = 1000
local TIMERS = {}
local SIMPLE = {}
local NET_HANDLERS = {}

SERVER = true
function AddCSLuaFile() end

istable    = function(v) return type(v) == "table" end
isstring   = function(v) return type(v) == "string" end
isnumber   = function(v) return type(v) == "number" end
isfunction = function(v) return type(v) == "function" end
IsValid    = function(v) return type(v) == "table" and v.__dead ~= true end

function CurTime() return NOW end
game = { GetMap = function() return "rp_test" end }
util = { AddNetworkString = function() end }
weapons = { Get = function() return { WorldModel = "models/weapons/w_pistol.mdl" } end }
timer = {
    Create = function(name, delay, reps, fn) TIMERS[name] = fn end,
    Simple = function(delay, fn) SIMPLE[#SIMPLE + 1] = { at = NOW + (delay or 0), fn = fn } end,
}
local function runTimers()
    for i = #SIMPLE, 1, -1 do
        if NOW >= SIMPLE[i].at then
            local fn = SIMPLE[i].fn
            table.remove(SIMPLE, i)
            fn()
        end
    end
end

-- Вектор: нужны DistToSqr и Distance для проверки присутствия.
local Vec = {}
Vec.__index = Vec
local function V(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, Vec) end
function Vec:DistToSqr(o)
    local dx, dy, dz = self.x - o.x, self.y - o.y, self.z - o.z
    return dx * dx + dy * dy + dz * dz
end
function Vec:Distance(o) return math.sqrt(self:DistToSqr(o)) end
function Vec:__sub(o) return V(self.x - o.x, self.y - o.y, self.z - o.z) end
function Vec:__add(o) return V(self.x + o.x, self.y + o.y, self.z + o.z) end

local function hookStub() end
hook = { Add = hookStub, Run = function() end, Remove = hookStub }
net = {
    Start = function() net._buf = {} end,
    Send = function() net._sent = net._sent or {} net._sent[#net._sent + 1] = net._buf net._buf = {} end,
    SendToServer = function() end,
    Receive = function(name, fn) NET_HANDLERS[name] = fn end,
    WriteEntity = function(e) (net._buf or {})[#(net._buf or {}) + 1] = e end,
    WriteString = function(s) (net._buf or {})[#(net._buf or {}) + 1] = s end,
    WriteUInt = function(v) (net._buf or {})[#(net._buf or {}) + 1] = v end,
    WriteFloat = function(v) (net._buf or {})[#(net._buf or {}) + 1] = v end,
    WriteBool = function(v) (net._buf or {})[#(net._buf or {}) + 1] = v end,
    WriteTable = function(t) (net._buf or {})[#(net._buf or {}) + 1] = t end,
}
NULL = setmetatable({}, { __index = function() return function() return false end end })

concommand = { Add = function() end, Run = function() end }
HUD_PRINTCONSOLE = 2

GRM = GRM or {}
GRM.Persistence = {
    LoadJSON = function(path, defaults) return defaults, "missing" end,
    SaveJSON = function() return true end,
}
GRM.Audit = { Write = function() end }
--[[ Права повторяют СЕМАНТИКУ настоящего GRM.Access.Check: суперадмин
     обходит запрет, а при отсутствии гранта решение принимает
     `default`. В настоящем модуле default == false, то есть capability
     ЗАПРЕЩЕНА по умолчанию — именно поэтому проверки ниже обязаны
     утверждать, что открытые действия объявили default = true. ]]
local ACCESS = {}
GRM.Access = {
    Register = function(id, definition) ACCESS[id] = definition end,
    Can = function(ply, capability)
        local def = ACCESS[capability]
        if not def then return false, "unknown_capability" end
        if IsValid(ply) and ply.IsSuperAdmin and ply:IsSuperAdmin() and def.superadminBypass ~= false then
            return true, "superadmin"
        end
        return def.default == true, "default"
    end,
}
--[[ Инвентарь игрока: у каждого персонажа свои слоты. Без него адаптер
     контейнера честно возвращает «не влезло», и проверка «чужой забрал
     готовое» падала бы не на политике доступа, а на отсутствии карманов. ]]
local INVENTORIES = {}
local function invOf(ply)
    INVENTORIES[ply] = INVENTORIES[ply] or { slots = {} }
    return INVENTORIES[ply]
end
local function invUsed(inv)
    local n = 0
    for _, slot in pairs(inv.slots) do n = n + (slot.count or 0) end
    return n
end
--[[ ПРАВИЛО НАСТОЯЩЕГО ИНВЕНТАРЯ. AddItem сначала спрашивает
     GetItemDef и, если предмета в справочнике НЕТ, возвращает ВСЁ
     количество как «не влезло» (sh_grm_inventory.lua:549). Раньше
     заглушка принимала любой предмет, поэтому баг «предметы
     производства не зарегистрированы» дошёл до живого сервера:
     стенды были зелёными, а игрок не мог взять ни лом, ни изделие. ]]
GRM.Inventory = {
    ItemDefs = {},
    GetItemDef = function(id) return GRM.Inventory.ItemDefs[id] end,
    AddItem = function(ply, id, count)
        if not GRM.Inventory.ItemDefs[id] then return count end
        local inv = invOf(ply)
        local put = math.min(count, math.max(0, 24 - invUsed(inv)))
        if put > 0 then inv.slots[#inv.slots + 1] = { id = id, count = put } end
        return count - put
    end,
    RemoveItem = function(ply, id, count)
        local inv, left = invOf(ply), count
        for i = 1, #inv.slots do
            local slot = inv.slots[i]
            if slot and slot.id == id and left > 0 then
                local take = math.min(slot.count, left)
                slot.count = slot.count - take
                left = left - take
                if slot.count <= 0 then inv.slots[i] = nil end
            end
        end
        return left
    end,
    CountItem = function(ply, id)
        local n = 0
        for _, slot in pairs(invOf(ply).slots) do
            if slot.id == id then n = n + (slot.count or 0) end
        end
        return n
    end,
    GetPlayerInv = function(ply) return invOf(ply) end,
}
GRM.Notify = function() end
GRM.GiveMoney = function() end
GRM.TakeMoney = function() end
GRM.GetBalance = function() return 0 end
GRM.HasMoney = function() return true end
GRM.Format = function(v) return tostring(v) end

-- ================================================================
--  БОЕВЫЕ ФАЙЛЫ
-- ================================================================
local function load(p)
    local chunk = assert(loadfile(p))
    chunk()
end
-- Ядро GRM (sh_00_grm_ui + sh_01_grm_core) — как на сервере, до модулей.
dofile("tools/luatest/lib_grm_core.lua")()
load("lua/autorun/sh_grm_industry_core.lua")
load("lua/autorun/sh_grm_industry_container.lua")
load("lua/autorun/server/sv_grm_industry.lua")

--[[ Регистрация предметов производства в инвентаре. Грузим её тем же
     файлом, что работает на сервере: без неё строгий инвентарь стенда
     отказывается принимать лом и изделия, и стенд краснеет ровно так,
     как краснел живой сервер. ]]
load("lua/autorun/zz_grm_industry_items.lua")

local I = GRM.Industry
local C = GRM.Container
local CFG = I.Config
ok(I ~= nil and I.StartJob ~= nil, "серверный модуль цеха загружен из боевого файла")
ok(TIMERS["GRM_Industry_Tick"] ~= nil, "тик задач зарегистрирован")
local tick = TIMERS["GRM_Industry_Tick"]

-- Прокрутить N тиков вперёд.
local function advance(seconds)
    local steps = math.floor(seconds / CFG.TickInterval)
    for _ = 1, steps do
        NOW = NOW + CFG.TickInterval
        tick()
        runTimers()
    end
end

-- ================================================================
--  ФИКСИРОВАННЫЕ ОБЪЕКТЫ
-- ================================================================
local function newEnt(role, kind)
    local e = { NodeRole = role, vars = {}, pos = V(0, 0, 0) }
    for _, name in ipairs({ "NodeID", "NodeKind", "FactionName", "NodeLabel", "WorkerName", "JobStage" }) do
        e["Set" .. name] = function(self, v) self.vars[name] = v end
        e["Get" .. name] = function(self) return self.vars[name] or "" end
    end
    for _, name in ipairs({ "Stock", "Wear" }) do
        e["Set" .. name] = function(self, v) self.vars[name] = v end
        e["Get" .. name] = function(self) return self.vars[name] or 0 end
    end
    for _, name in ipairs({ "Busy" }) do
        e["Set" .. name] = function(self, v) self.vars[name] = v end
        e["Get" .. name] = function(self) return self.vars[name] == true end
    end
    e["SetProgress"] = function(self, v) self.vars.Progress = v end
    e["GetProgress"] = function(self) return self.vars.Progress or 0 end
    e.GetPos = function(self) return self.pos end
    e.SetModel = function() end
    e.PhysicsInit = function() end
    e.SetMoveType = function() end
    e.SetSolid = function() end
    e.GetPhysicsObject = function() return nil end
    e.EmitSound = function() end
    e.Nick = function() return "Тестовый" end
    e.GetNWString = function() return "" end
    e.SteamID64 = function() return "76561190000000001" end
    e.IsPlayer = function() return true end
    if kind then e.vars.NodeKind = kind end
    return e
end

local function newPlayer(sid)
    local p = newEnt("player")
    p.pos = V(0, 0, 0)
    p._sid = sid or "76561190000000001"
    p.SteamID64 = function() return p._sid end
    p.Alive = function() return true end
    p._super = false
    p.IsSuperAdmin = function() return p._super end
    p.GetNWString = function(_, key) return key == "GRM_Faction" and (p._faction or "") or "" end
    p.HasWeapon = function() return false end
    p.Give = function() end
    return p
end

--[[ Вызов боевого обработчика действий цеха в обход сети: читалки net
     подставляем сами. Так проверяется настоящая политика доступа, а не
     её пересказ. ]]
local function callAction(ply, ent, op, itemID, count)
    local handler = NET_HANDLERS["GRM_IND_Action"]
    if not handler then return end
    local strings = { op, itemID or "" }
    local si = 0
    net.ReadEntity = function() return ent end
    net.ReadString = function() si = si + 1 return strings[si] or "" end
    net.ReadUInt = function() return count or 1 end
    net.ReadTable = function() return {} end
    handler(64, ply)
end

local function newStation(kind)
    local e = newEnt("station", kind)
    e.pos = V(0, 0, 0)
    I.InitNode(e)
    return e, I.NodeFor(e)
end

local function fillInput(rec, items)
    for id, n in pairs(items) do C.Add(rec.inID, id, n) end
end

-- ================================================================
print("\n=== 1. ЗАДАЧА — ЭТО ОБЪЕКТ, А НЕ ТАЙМЕР ===")
-- ================================================================
do
    local ent, rec = newStation("furnace")   -- у печи нет мини-игры
    fillInput(rec, { defective_components = 1 })
    local ply = newPlayer()

    ok(ent:GetNodeKind() == "furnace", "станок инициализирован как печь")
    ok(rec.inID ~= nil and rec.outID ~= nil, "у станка есть вход и выход")
    ok(C.Count(rec.inID, "defective_components") == 1, "сырьё лежит во входе")

    I.StartJob(ply, ent, "melt_components")
    local job = rec.job and I.Jobs[rec.job] or nil
    ok(job ~= nil, "задача создана")
    ok(job.worker == ply, "у задачи есть работник — старый цех его не помнил")
    ok(job.input and job.input.defective_components == 1, "задача помнит вложенное сырьё")
    ok(job.stage == "assemble", "печь сразу переходит к сборке", job.stage)
    ok(C.Count(rec.inID, "defective_components") == 0, "сырьё списано со входа")
    ok(ent:GetBusy() == true, "станок помечен занятым")
end

-- ================================================================
print("\n=== 2. ПРОГРЕСС ИДЁТ ТОЛЬКО РЯДОМ СО СТАНКОМ ===")
-- ================================================================
do
    -- ГЛАВНАЯ ПРОВЕРКА ПО ЖАЛОБЕ ВЛАДЕЛЬЦА.
    local ent, rec = newStation("furnace")
    fillInput(rec, { defective_components = 1 })
    local ply = newPlayer()
    I.StartJob(ply, ent, "melt_components")
    local job = I.Jobs[rec.job]

    advance(2)
    local near_progress = job.progress
    ok(near_progress > 0, "рядом со станком прогресс идёт", near_progress)
    ok(job.stage == "assemble", "стадия — сборка")

    -- Уходим за радиус работы.
    ply.pos = V(0, 5000, 0)
    advance(CFG.GraceSeconds + 1)
    ok(job.stage == "paused", "ОТОШЁЛ — работа встала на паузу", job.stage)
    ok(job.pauseReason == "away", "причина паузы — отошёл", job.pauseReason)

    -- Держимся вдали долго: прогресс НЕ должен расти.
    local frozen = job.progress
    advance(60)
    ok(job.progress == frozen, "пока работника нет, прогресс стоит на месте",
        tostring(frozen) .. " -> " .. tostring(job.progress))
    ok(job.stage == "paused", "и не перешёл в «сделано»")
    ok(C.IsEmpty(rec.outID), "продукта в выходе нет — работник не работал")

    -- Возвращаемся.
    ply.pos = V(0, 0, 0)
    advance(CFG.TickInterval * 2)
    ok(job.stage == "assemble", "ВЕРНУЛСЯ — работа продолжилась", job.stage)
    ok(job.progress > frozen, "прогресс пошёл с того же места", job.progress - frozen)
    ok(job.pauseReason == nil, "причина паузы снята")
end

-- ================================================================
print("\n=== 3. СМЕРТЬ И ВЫХОД ИЗ ИГРЫ ===")
-- ================================================================
do
    local ent, rec = newStation("furnace")
    fillInput(rec, { defective_components = 1 })
    local ply = newPlayer()
    I.StartJob(ply, ent, "melt_components")
    local job = I.Jobs[rec.job]

    ply.Alive = function() return false end
    advance(CFG.GraceSeconds + 1)
    ok(job.stage == "paused" and job.pauseReason == "dead", "смерть работника ставит паузу", job.pauseReason)

    ply.Alive = function() return true end
    advance(CFG.TickInterval * 2)
    ok(job.stage == "assemble", "ожил — продолжил")

    -- Выход с сервера: объект игрока становится невалидным.
    ply.__dead = true
    advance(CFG.GraceSeconds + 1)
    ok(job.stage == "paused" and job.pauseReason == "offline", "выход из игры ставит паузу", job.pauseReason)

    local before = job.progress
    advance(120)
    ok(job.progress == before, "пока работника нет на сервере, прогресс стоит")
    ok(job.stage == "paused", "задача не завершилась сама")
end

-- ================================================================
print("\n=== 4. ПРОДУКТ ИДЁТ В ВЫХОД СТАНКА ===")
-- ================================================================
do
    local ent, rec = newStation("furnace")
    fillInput(rec, { defective_components = 1 })
    local ply = newPlayer()
    I.StartJob(ply, ent, "melt_components")
    local job = I.Jobs[rec.job]

    local need = job.assembleDuration
    advance(need + 2)

    ok(I.Jobs[job.id] == nil, "задача закрыта после сборки")
    ok(rec.job == nil, "станок свободен")
    ok(ent:GetBusy() == false, "признак занятости снят")
    ok(C.Count(rec.outID, "scrap_metal") == 2, "продукт лежит в ВЫХОДЕ станка, а не в руках",
        C.Count(rec.outID, "scrap_metal"))
    ok(rec.wear > 0, "износ станка вырос", rec.wear)
end

-- ================================================================
print("\n=== 5. СЫРЬЁ НЕ СГОРАЕТ ===")
-- ================================================================
do
    -- Отмена работы возвращает сырьё.
    local ent, rec = newStation("furnace")
    fillInput(rec, { defective_components = 1 })
    local ply = newPlayer()
    I.StartJob(ply, ent, "melt_components")
    local job = I.Jobs[rec.job]
    advance(1)

    I.CancelJob(job, "Отменено", true)
    ok(C.Count(rec.outID, "defective_components") == 1, "сырьё ВЕРНУЛОСЬ при отмене",
        C.Count(rec.outID, "defective_components"))
    ok(I.Jobs[job.id] == nil, "задача удалена")
    ok(rec.job == nil, "станок свободен")

    -- Заброшенная задача закрывается сама и тоже возвращает сырьё.
    local ent2, rec2 = newStation("furnace")
    fillInput(rec2, { defective_components = 1 })
    local ply2 = newPlayer()
    I.StartJob(ply2, ent2, "melt_components")
    local job2 = I.Jobs[rec2.job]
    ply2.__dead = true
    advance(CFG.GraceSeconds + 2)
    job2.updatedAt = CurTime() - CFG.AbandonAfter - 10
    advance(1)
    ok(I.Jobs[job2.id] == nil, "заброшенная задача закрылась", job2.id)
    ok(C.Count(rec2.outID, "defective_components") == 1, "сырьё возвращено и при забросе")
end

-- ================================================================
print("\n=== 6. МИНИ-ИГРА И КАЧЕСТВО ===")
-- ================================================================
do
    local function runMinigame(miss)
        local ent, rec = newStation("weapon")
        fillInput(rec, { scrap_metal = 5, components_box = 1 })
        local ply = newPlayer()
        I.StartJob(ply, ent, "arccw_makarov")
        local job = I.Jobs[rec.job]
        ok(job ~= nil, "задача на верстаке создана")
        ok(job.stage == "process", "сначала идёт мини-игра", job.stage)
        ok(job.expectedSteps == I.StepsFor("weapon"), "шагов столько, сколько задано для верстака")

        local handler = NET_HANDLERS["GRM_IND_Step"]
        ok(handler ~= nil, "обработчик шагов мини-игры зарегистрирован")

        for i = 1, job.expectedSteps do
            NOW = NOW + 0.5       -- защита от «прощёлкал быстрее возможного»
            local lane = (job.sequence or {})[i] or 0
            net.ReadEntity = function() return ent end
            net.ReadUInt = function() if net._u == nil then net._u = i else return lane end; return i end
            net.ReadFloat = function() return miss and job.window or 0 end
            net.ReadBool = function() return miss == true end
            handler(64, ply)
            net._u = nil
        end
        return ent, rec, job, ply
    end

    -- Читалки под конкретный порядок: entity, index(UInt8), float, bool, lane(UInt4).
    local function readOrder(ent, i, err, missed, lane)
        local seq = { ent, i }
        local idx = 0
        net.ReadEntity = function() return ent end
        net.ReadUInt = function()
            idx = idx + 1
            if idx == 1 then return i end
            return lane
        end
        net.ReadFloat = function() return err end
        net.ReadBool = function() return missed end
    end

    local function playMinigame(miss)
        local ent, rec = newStation("weapon")
        fillInput(rec, { scrap_metal = 5, components_box = 1 })
        local ply = newPlayer()
        I.StartJob(ply, ent, "arccw_makarov")
        local job = I.Jobs[rec.job]
        local handler = NET_HANDLERS["GRM_IND_Step"]

        for i = 1, job.expectedSteps do
            NOW = NOW + 0.5
            readOrder(ent, i, miss and job.window or 0, miss == true, (job.sequence or {})[i] or 0)
            handler(64, ply)
        end
        return ent, rec, job, ply
    end

    -- УСПЕШНОЕ ПРОХОЖДЕНИЕ.
    local ent, rec, job, ply = playMinigame(false)
    ok(job.stage == "assemble" or I.Jobs[job.id] == nil, "после мини-игры задача перешла к сборке", job.stage)
    ok(job.quality == 100, "безупречное прохождение даёт качество 100", job.quality)
    ok(job.outcome == "master", "результат — изделие с клеймом мастера", job.outcome)
    ok(C.Count(rec.outID, "arccw_makarov") == 0, "продукт ЕЩЁ не выдан — впереди сборка")

    advance(job.assembleDuration + 2)
    ok(C.Count(rec.outID, "arccw_makarov") == 1, "после сборки пистолет в выходе станка",
        C.Count(rec.outID, "arccw_makarov"))

    -- ПРОВАЛ: брак и возврат половины сырья.
    local ent2, rec2, job2 = playMinigame(true)
    ok(job2.quality == 0, "сплошные промахи дают качество ноль", job2.quality)
    ok(job2.outcome == "defect", "результат — брак", job2.outcome)
    ok(I.Jobs[job2.id] == nil, "задача закрыта сразу, сборки не будет")
    ok(C.Count(rec2.outID, "defective_weapon_parts") == 1, "брак положили в выход — его можно переплавить",
        C.Count(rec2.outID, "defective_weapon_parts"))
    local scrapBack = C.Count(rec2.outID, "scrap_metal")
    ok(scrapBack > 0, "часть сырья вернулась, а не сгорела", scrapBack)
    ok(scrapBack < 5, "вернулась ЧАСТЬ, а не всё — иначе провал выгоднее работы", scrapBack)
end

-- ================================================================
print("\n=== 7. НЕЛЬЗЯ СДЕЛАТЬ НЕЧЕГО ИЗ НИЧЕГО ===")
-- ================================================================
do
    local ent, rec = newStation("weapon")
    local ply = newPlayer()
    local okStart = I.StartJob(ply, ent, "arccw_makarov")
    ok(okStart == false, "без сырья работа не начинается")
    ok(rec.job == nil, "задачи не возникло")
    ok(C.IsEmpty(rec.inID) and C.IsEmpty(rec.outID), "ничего не списалось")

    -- Чужую задачу на занятом станке не начать.
    fillInput(rec, { scrap_metal = 5, components_box = 1 })
    I.StartJob(ply, ent, "arccw_makarov")
    local firstJob = rec.job
    fillInput(rec, { scrap_metal = 5, components_box = 1 })
    ok(I.StartJob(ply, ent, "arccw_makarov") == false, "второй раз тот же станок не запустить")
    ok(rec.job == firstJob, "задача осталась прежней")

    -- Рецепт чужого станка не пройдёт.
    local ent2, rec2 = newStation("gpu")
    fillInput(rec2, { scrap_metal = 5, components_box = 1 })
    ok(I.StartJob(ply, ent2, "arccw_makarov") == false, "на станке видеокарт оружие не собирают")
end

-- ================================================================
print("\n=== 8. ВЫХОД ЗАБИТ — РАБОТА НЕ НАЧИНАЕТСЯ ===")
-- ================================================================
do
    --[[ Продукт не должен пропадать из-за переполненного выхода. Проверяем
         ДО старта: иначе игрок тратит время и сырьё, а получить нечего. ]]
    local ent, rec = newStation("furnace")
    local cap = C.Capacity(rec.outID)
    ok(cap > 0, "у выхода станка есть лимит по весу", cap)

    -- Забиваем выход тяжёлым грузом.
    local unit = I.WeightOf("scrap_metal")
    C.Add(rec.outID, "scrap_metal", math.floor(cap / unit))
    ok(C.Free(rec.outID) < unit, "выход забит", C.Free(rec.outID))

    fillInput(rec, { defective_components = 1 })
    local ply = newPlayer()
    ok(I.StartJob(ply, ent, "melt_components") == false, "при забитом выходе работа не начинается")
    ok(C.Count(rec.inID, "defective_components") == 1, "сырьё не списано")
end

-- ================================================================
print("\n=== 9. СТАНКИ ОБЩИЕ (решение владельца 31.08) ===")
-- ================================================================
do
    --[[ РЕШЕНИЕ ВЛАДЕЛЬЦА: «Станки общие». Владельца у станка НЕТ:
         забрать готовое изделие может любой, кто подошёл. Проверка нужна
         затем, чтобы следующая правка не добавила сюда проверку владельца
         «для порядка» и не сломала осознанный выбор. ]]
    local ent, rec = newStation("furnace")
    fillInput(rec, { defective_components = 1 })
    local maker = newPlayer("76561190000000011")
    I.StartJob(maker, ent, "melt_components")
    local job = I.Jobs[rec.job]
    advance(job.assembleDuration + 2)
    ok(C.Count(rec.outID, "scrap_metal") == 2, "изделие лежит в выходе станка")

    -- Чужой игрок забирает продукт.
    local passer = newPlayer("76561190000000022")
    ok(maker ~= passer, "это другой персонаж")
    callAction(passer, ent, "withdraw", "scrap_metal", 2)
    ok(C.Count(rec.outID, "scrap_metal") == 0, "ЧУЖОЙ ЗАБРАЛ ГОТОВОЕ — станок общий",
        C.Count(rec.outID, "scrap_metal"))
    ok(C.Count(C.ForPlayer(passer).id, "scrap_metal") == 2, "изделие ушло в инвентарь забравшего")

    -- Работу, вставшую на паузу, тоже может продолжить любой.
    local ent2, rec2 = newStation("furnace")
    fillInput(rec2, { defective_components = 1 })
    local worker = newPlayer("76561190000000033")
    I.StartJob(worker, ent2, "melt_components")
    local job2 = I.Jobs[rec2.job]
    worker.__dead = true
    advance(CFG.GraceSeconds + 2)
    ok(job2.stage == "paused", "работник вышел — работа на паузе", job2.stage)

    local helper = newPlayer("76561190000000044")
    callAction(helper, ent2, "job_resume")
    ok(job2.stage == "assemble", "ЧУЖОЙ ПРОДОЛЖИЛ ВСТАВШУЮ РАБОТУ — станок общий", job2.stage)
    ok(job2.worker == helper, "работник у задачи сменился")

    -- Но ИДУЩУЮ работу перехватить нельзя: живой работник у станка в приоритете.
    local ent3, rec3 = newStation("furnace")
    fillInput(rec3, { defective_components = 1 })
    local busy = newPlayer("76561190000000055")
    I.StartJob(busy, ent3, "melt_components")
    local job3 = I.Jobs[rec3.job]
    advance(2)
    local stranger = newPlayer("76561190000000066")
    callAction(stranger, ent3, "job_resume")
    ok(job3.worker == busy, "идущую работу чужой не перехватывает")
end

-- ================================================================
print("\n=== 10. ПРАВА ПОДКЛЮЧЕНЫ (пункт 9) ===")
-- ================================================================
do
    --[[ БЫЛО: capability были зарегистрированы, но нигде не спрашивались —
         производство держалось на честном слове. ]]
    ok(ACCESS["industry.produce"] ~= nil, "capability производства зарегистрирована")
    ok(ACCESS["industry.manage"] ~= nil, "capability наладки зарегистрирована")
    ok(ACCESS["industry.logistics"] ~= nil, "capability логистики зарегистрирована")

    --[[ САМОЕ ВАЖНОЕ. GRM.Access.Check при отсутствии гранта возвращает
         `default == true`, то есть capability по умолчанию ЗАПРЕЩЕНА.
         Если у открытых действий не выставить default = true, подключение
         проверок разом заперло бы производство — вразрез с решением
         владельца «станки общие». ]]
    ok(ACCESS["industry.produce"].default == true,
        "производство ОТКРЫТО по умолчанию (иначе станки перестанут работать)")
    ok(ACCESS["industry.logistics"].default == true, "рейсы открыты по умолчанию")
    ok(ACCESS["industry.manage"].default ~= true, "наладка закрыта по умолчанию")

    ok(I.ActionCapability.job_start == "industry.produce", "запуск работы требует права производства")
    ok(I.ActionCapability.station_setup == "industry.manage", "смена типа станка требует права наладки")

    -- Обычный игрок может работать: право открыто по умолчанию.
    local ent, rec = newStation("furnace")
    fillInput(rec, { defective_components = 1 })
    local worker = newPlayer("76561190000000301")
    callAction(worker, ent, "job_start", "melt_components", 1)
    ok(rec.job ~= nil, "работник запустил работу", rec.job)
    I.CancelJob(I.Jobs[rec.job], "тест", false)

    -- Наладку станка обычному игроку нельзя.
    local ent2, rec2 = newStation("furnace")
    local kindBefore = ent2:GetNodeKind()
    callAction(worker, ent2, "station_setup", "weapon", 1)
    ok(ent2:GetNodeKind() == kindBefore, "ОБЫЧНОМУ ИГРОКУ НАЛАДКА НЕ ДОСТУПНА", ent2:GetNodeKind())

    -- Суперадмин наладку делает.
    local boss = newPlayer("76561190000000302")
    boss._super = true
    callAction(boss, ent2, "station_setup", "weapon", 1)
    ok(ent2:GetNodeKind() == "weapon", "суперадмин меняет тип станка", ent2:GetNodeKind())

    --[[ Если фракция или админ ЗАКРОЮТ право производства, станок обязан
         остановиться. Без этой проверки выданный запрет ни на что не влиял. ]]
    ACCESS["industry.produce"].default = false
    local ent3, rec3 = newStation("furnace")
    fillInput(rec3, { defective_components = 1 })
    callAction(worker, ent3, "job_start", "melt_components", 1)
    ok(rec3.job == nil, "БЕЗ ПРАВА ПРОИЗВОДСТВА РАБОТА НЕ НАЧИНАЕТСЯ", rec3.job)
    ok(C.Count(rec3.inID, "defective_components") == 1, "сырьё списано не было")

    -- Суперадмин обходит запрет.
    callAction(boss, ent3, "job_start", "melt_components", 1)
    ok(rec3.job ~= nil, "суперадмин обходит запрет производства")
    ACCESS["industry.produce"].default = true
end

-- ================================================================
print("\n=== 12. СБОР РЕСУРСОВ: СЫРЬЁ И ИЗДЕЛИЯ ПОПАДАЮТ В РУКИ ===")
-- ================================================================
do
    --[[ ЖАЛОБА ВЛАДЕЛЬЦА: «сбор ресурсов не проходит». Причина была
         не в станках и не в источнике: предметы производства вообще
         не были зарегистрированы в инвентаре. GRM.Inventory.AddItem
         без описания предмета возвращает ВСЁ количество как «не
         влезло», адаптер контейнера честно отвечал «нет места», и
         игрок не получал ничего при пустом инвентаре.

         Инвентарь стенда подчинён тому же правилу (см. GRM.Inventory
         выше), поэтому проверка ниже ловит повтор бага. ]]
    local src = newEnt("supply")
    src.pos = V(0, 0, 0)
    I.InitNode(src)
    local srcRec = I.NodeFor(src)

    local ply = newPlayer("76561190000001201")
    local box = C.ForPlayer(ply)
    ok(srcRec.supply ~= nil, "у источника есть запас")
    ok(C.Count(box.id, "scrap_metal") == 0, "инвентарь игрока пуст")

    callAction(ply, src, "supply_take", "", 5)
    ok(C.Count(box.id, "scrap_metal") == 5, "ЛОМ ИЗ ИСТОЧНИКА ПОПАЛ В ИНВЕНТАРЬ",
        C.Count(box.id, "scrap_metal"))
    ok(srcRec.supply.stock == 20, "запас источника уменьшился", srcRec.supply.stock)

    -- Готовое изделие со станка тоже должно уходить в руки.
    local st, stRec = newStation("components")
    C.Add(stRec.outID, "components_box", 2)
    local ply2 = newPlayer("76561190000001202")
    callAction(ply2, st, "withdraw", "components_box", 1)
    ok(C.Count(C.ForPlayer(ply2).id, "components_box") == 1,
        "ИЗДЕЛИЕ СО СТАНКА ПОПАЛО В РУКИ", C.Count(C.ForPlayer(ply2).id, "components_box"))
    ok(C.Count(stRec.outID, "components_box") == 1, "на станке осталось одно изделие",
        C.Count(stRec.outID, "components_box"))
end

-- ================================================================
print("\n=== 13. ПРЕДМЕТЫ ПРОИЗВОДСТВА ЗАРЕГИСТРИРОВАНЫ В ИНВЕНТАРЕ ===")
-- ================================================================
do
    --[[ Тот самый справочник, которого не хватало. Проверяем по
         боевому файлу регистрации, а не по копии: если предмет
         забудут зарегистрировать, стенд скажет. ]]
    ok(GRM.Inventory and GRM.Inventory.ItemDefs ~= nil, "справочник предметов есть")
    local missing = {}
    for id in pairs(I.Items or {}) do
        if not (GRM.Inventory.ItemDefs and GRM.Inventory.ItemDefs[id]) then
            missing[#missing + 1] = id
        end
    end
    table.sort(missing)
    ok(#missing == 0, "ВСЕ ПРЕДМЕТЫ ПРОИЗВОДСТВА ЗАРЕГИСТРИРОВАНЫ", table.concat(missing, ", "))

    local def = GRM.Inventory.ItemDefs and GRM.Inventory.ItemDefs["scrap_metal"]
    ok(def ~= nil, "металлолом описан")
    ok(def and def.name == "Металлолом", "название совпадает со справочником цеха",
        def and def.name)
    ok(def and tonumber(def.weight) == I.Items.scrap_metal.weight,
        "вес совпадает со справочником цеха", def and def.weight)

    -- Оружие из рецептов: без регистрации его тоже нельзя выдать.
    local guns = 0
    for _, recipe in pairs(I.Recipes or {}) do
        local out = recipe.output
        if out and not I.Items[out] then
            guns = guns + 1
            if not GRM.Inventory.ItemDefs[out] then
                ok(false, "оружие " .. tostring(out) .. " не зарегистрировано")
            end
        end
    end
    ok(guns > 0, "в рецептах есть оружейные изделия", guns)
end

-- ================================================================
print("\n=== ИТОГ ===")
print("  пройдено: " .. pass .. ", провалено: " .. fail)
if fail > 0 then os.exit(1) end
