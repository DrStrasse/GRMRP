--[[--------------------------------------------------------------------
    GRM Industry — сервер: узлы, контейнеры, задачи, мини-игра, рынок.

    ГЛАВНОЕ ОТЛИЧИЕ ОТ СТАРОГО ЦЕХА. Раньше «производство» было таймером:
    `timer.Create` на N секунд и всё. У задачи не было владельца,
    прогресса и вложенных материалов — поэтому игрок уходил через
    полкарты и всё равно получал оружие в руки, а выход с сервера
    сжигал сырьё.

    Здесь задача — объект со стадиями. Она знает, чья она, сколько
    прошло и что в неё вложено. Отошёл работник — задача встаёт на
    паузу, а не проваливается; материалы возвращаются, а не сгорают.
----------------------------------------------------------------------]]

if not SERVER then return end

GRM = GRM or {}
local I = GRM.Industry
local C = GRM.Container
if not I or not C then
    print("[GRM Industry] ОШИБКА: ядро или контейнеры не загружены")
    return
end

local CFG = I.Config
local P = GRM.Persistence

I.Nodes  = I.Nodes or {}
I.Jobs   = I.Jobs or {}
I.Levels = I.Levels or {}      -- [charKey][station] = уровень навыка
I.NodeHandlers = I.NodeHandlers or {}

--[[ Имена сетей объявлены в общем ядре — клиент и сервер обязаны
     называть сообщения одинаково. Регистрируем их здесь: сделать
     это можно только на сервере. ]]
local NET = I.NET
if NET then
    for _, name in pairs(NET) do util.AddNetworkString(name) end
end

local DATA_DIR  = "grm_industry"
local MAP_FILE  = DATA_DIR .. "/map_" .. tostring(game.GetMap() or "unknown") .. ".json"
local LEVELFILE = DATA_DIR .. "/levels.json"
local SAVE_VERSION = 1

-- ================================================================
--  МЕЛКИЕ ПОМОЩНИКИ
-- ================================================================
local function notify(ply, message, ok)
    if not IsValid(ply) then return end
    if GRM.Notify then GRM.Notify(ply, tostring(message or ""), ok and 100 or 235, ok and 220 or 90, ok and 100 or 90) end
end
I.Notify = notify

local function charKey(ply)
    if not IsValid(ply) then return "" end
    if GRM.Char and GRM.Char.GetActiveKey then
        local ok, key = pcall(GRM.Char.GetActiveKey, ply)
        if ok and key and tostring(key) ~= "" and tostring(key) ~= "0" then return tostring(key) end
    end
    return tostring(ply:SteamID64() or "")
end
I.CharKey = charKey

--[[ ФРАКЦИЯ УЗЛА (пункт 8 из списка вопросов владельца). Раньше поле
     «фракция» у узла было только подписью для окна: проверки не было
     вовсе, и оружие из шкафа фракции мог забрать кто угодно.

     Пустая фракция — узел общий. Фракция указана — пускаем только
     её членов и суперадмина. ]]
--[[ НАЛАДКА: право industry.manage ИЛИ суперадмин. Раньше действия
     проверяли только IsSuperAdmin, и выданное capability ни на что не
     влияло — выдали право в /factions, а человек всё равно не может. ]]
function I.CanManage(ply)
    if not IsValid(ply) then return false end
    if ply:IsSuperAdmin() then return true end
    if GRM.Access and GRM.Access.Can then
        return GRM.Access.Can(ply, "industry.manage", {}) == true
    end
    return false
end

function I.FactionOf(ply)
    if not IsValid(ply) then return "" end
    return tostring(ply:GetNWString("GRM_Faction", "") or "")
end

function I.CanUseFactionNode(ply, ent)
    if not IsValid(ply) then return false, "invalid_player" end
    local faction = tostring(ent and ent.GetFactionName and ent:GetFactionName() or "")
    if faction == "" then return true, "public" end
    if ply:IsSuperAdmin() then return true, "superadmin" end
    if I.FactionOf(ply) == faction then return true, "faction" end
    if _G.FactionsAPI and _G.FactionsAPI.IsMember then
        local ok, member = pcall(_G.FactionsAPI.IsMember, faction, ply)
        if ok and member == true then return true, "faction" end
    end
    return false, "faction_mismatch"
end

local function newID(prefix)
    return tostring(prefix or "node") .. "_" .. tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999))
end

local function inRange(ply, ent, range)
    if not (IsValid(ply) and IsValid(ent)) then return false end
    return ply:GetPos():DistToSqr(ent:GetPos()) <= (tonumber(range) or 200) ^ 2
end

local function containerID(nodeID, slot)
    if slot then return "ind:" .. tostring(nodeID) .. ":" .. tostring(slot) end
    return "ind:" .. tostring(nodeID)
end
I.ContainerID = containerID

-- ================================================================
--  УЗЛЫ
-- ================================================================
function I.NodeFor(ent)
    if not IsValid(ent) then return nil end
    local id = tostring(ent:GetNodeID() or "")
    if id == "" then return nil end
    return I.Nodes[id]
end

function I.InitNode(ent)
    if not IsValid(ent) then return end

    local id = tostring(ent:GetNodeID() or "")
    if id == "" then
        id = newID(ent.NodeRole or "node")
        ent:SetNodeID(id)
    end

    local role = tostring(ent.NodeRole or "storage")
    local rec = I.Nodes[id]
    if not rec then
        rec = {
            id = id, role = role,
            wear = 0,
            supply = nil,
            demand = nil,
            job = nil,
        }
        I.Nodes[id] = rec
    end
    rec.ent = ent
    rec.role = role

    -- Контейнеры по роли.
    if role == "station" then
        if ent:GetNodeKind() == "" then ent:SetNodeKind("components") end
        rec.kind = tostring(ent:GetNodeKind())
        C.Ensure(containerID(id, "in"), "store", id, I.RoleCapacity.station)
        C.Ensure(containerID(id, "out"), "store", id, I.RoleCapacity.station)
        rec.inID = containerID(id, "in")
        rec.outID = containerID(id, "out")
    elseif role == "supply" then
        local s = I.Config.Supply
        rec.supply = rec.supply or { stock = s.StartStock, nextRefill = CurTime() + s.RefillEvery }
        C.Ensure(containerID(id), "store", id, -1)
        rec.outID = containerID(id)
    else
        C.Ensure(containerID(id), "store", id, I.RoleCapacity[role] or -1)
        rec.outID = containerID(id)
        if role == "warehouse" and not rec.demand then rec.demand = {} end
    end

    local model = (I.NodeRoles[role] or {}).model
    if role == "station" then
        local st = I.Stations[rec.kind or ""]
        if st and st.model then model = st.model end
    end
    if model then ent:SetModel(model) end

    ent:PhysicsInit(SOLID_VPHYSICS)
    ent:SetMoveType(MOVETYPE_VPHYSICS)
    ent:SetSolid(SOLID_VPHYSICS)
    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then phys:Wake() end

    if ent:GetNodeLabel() == "" then ent:SetNodeLabel((I.NodeRoles[role] or {}).name or role) end
end

function I.NodeRemoved(ent)
    local rec = I.NodeFor(ent)
    if not rec then return end
    -- Задача на удаляемом станке: материалы возвращаем, продукт не теряем.
    local job = rec.job and I.Jobs[rec.job] or nil
    if job then I.CancelJob(job, "Станок удалён", true) end
    I.Nodes[rec.id] = nil
end

function I.NodePermData(ent)
    local rec = I.NodeFor(ent)
    if not rec then return nil end
    local d = { wear = rec.wear }
    if rec.role == "supply" and rec.supply then d.supply = rec.supply end
    if rec.role == "warehouse" and rec.demand then d.demand = rec.demand end
    return d
end

function I.ApplyNodePermData(ent, data)
    local rec = I.NodeFor(ent)
    if not rec then return end
    if data.wear then rec.wear = I.Clamp(tonumber(data.wear) or 0, 0, CFG.WearCap) end
    if data.supply and rec.role == "supply" then rec.supply = data.supply end
    if data.demand and rec.role == "warehouse" then rec.demand = data.demand end
end

-- ================================================================
--  ЗАДАЧИ
-- ================================================================
local function jobPayload(job)
    if not job then return nil end
    return {
        id = job.id,
        recipeID = job.recipeID,
        stage = job.stage,
        pauseReason = job.pauseReason,
        progress = I.Round(job.progress or 0, 3),
        quality = job.quality,
        worker = job.workerName,
        step = job.stepIndex or 0,
        steps = job.expectedSteps or 0,
    }
end

local function sendJob(job)
    if not job or not IsValid(job.worker) then return end
    net.Start(NET.job)
        net.WriteString(job.machine or "")
        net.WriteTable(jobPayload(job))
    net.Send(job.worker)
end
I.SendJob = sendJob

--[[ ВЗЯТЬ СЫРЬЁ. Сначала забираем из входного контейнера станка,
     недостающее — из инвентаря работника. Всё или ничего: частичное
     списание оставило бы половину материалов в подвешенном состоянии. ]]
local function collectInputs(ply, rec, recipe)
    local plan = {}
    for itemID, need in pairs(recipe.input or {}) do
        need = math.max(0, math.floor(tonumber(need) or 0))
        if need <= 0 then return nil, "Пустой рецепт: " .. tostring(itemID) end

        local fromMachine = math.min(need, C.Count(rec.inID, itemID))
        local rest = need - fromMachine
        if rest > 0 then
            local playerBox = C.ForPlayer(ply)
            if not playerBox then return nil, "Не удалось получить инвентарь" end
            if C.Count(playerBox.id, itemID) < rest then
                return nil, "Не хватает: " .. I.NameOf(itemID) .. " (нужно " .. need .. ")"
            end
        end
        plan[#plan + 1] = { itemID = itemID, need = need, fromMachine = fromMachine, fromPlayer = rest }
    end

    -- Проверки прошли — теперь списываем. Откат при любой осечке.
    local taken = {}
    for _, line in ipairs(plan) do
        if line.fromMachine > 0 then
            local ok = C.Take(rec.inID, line.itemID, line.fromMachine)
            if not ok then
                for _, done in ipairs(taken) do C.Add(done.id, done.itemID, done.n) end
                return nil, "Ошибка списания со станка"
            end
            taken[#taken + 1] = { id = rec.inID, itemID = line.itemID, n = line.fromMachine }
        end
        if line.fromPlayer > 0 then
            local playerBox = C.ForPlayer(ply)
            local ok = C.Take(playerBox.id, line.itemID, line.fromPlayer)
            if not ok then
                for _, done in ipairs(taken) do C.Add(done.id, done.itemID, done.n) end
                return nil, "Ошибка списания из инвентаря"
            end
            taken[#taken + 1] = { id = playerBox.id, itemID = line.itemID, n = line.fromPlayer }
        end
    end
    return plan
end

function I.StartJob(ply, ent, recipeID)
    if not inRange(ply, ent, CFG.WorkRadius) then notify(ply, "Подойдите ближе к станку", false) return false end
    local rec = I.NodeFor(ent)
    if not rec or rec.role ~= "station" then return false end

    if rec.job and I.Jobs[rec.job] then notify(ply, "Станок уже занят", false) return false end

    local recipe = I.RecipeFor(rec.kind, recipeID)
    if not recipe then notify(ply, "Рецепт не найден", false) return false end
    if recipe.weapon and not weapons.Get(recipe.weapon) then
        notify(ply, "Оружие " .. tostring(recipe.weapon) .. " не установлено на сервере", false) return false
    end

    -- Выход станка проверяем ДО старта, а не в момент выдачи: иначе
    -- игрок теряет время, а продукт некуда положить.
    local outWeight = I.WeightOf(recipe.output) * (tonumber(recipe.outputCount) or 1)
    if C.Capacity(rec.outID) >= 0 and C.Weight(rec.outID) + outWeight > C.Capacity(rec.outID) then
        notify(ply, "Выход станка забит — сначала заберите готовое", false) return false
    end

    local plan, reason = collectInputs(ply, rec, recipe)
    if not plan then notify(ply, reason or "Не хватает материалов", false) return false end

    local key = charKey(ply)
    local level = tonumber(((I.Levels[key] or {})[rec.kind]) or 0) or 0
    local steps = I.StepsFor(rec.kind)

    local job = {
        id = newID("job"),
        machine = rec.id,
        recipeID = recipeID,
        recipe = recipe,
        worker = ply,
        workerKey = key,
        workerName = IsValid(ply) and (ply:GetNWString("GRM_RPName", "") ~= "" and ply:GetNWString("GRM_RPName", "") or ply:Nick()) or "?",
        stage = steps > 0 and "process" or "assemble",
        steps = {},
        stepIndex = 0,
        expectedSteps = steps,
        sequence = sequence,
        window = I.WindowFor(rec.kind, level),
        quality = nil,
        progress = 0,
        input = {},
        startedAt = CurTime(),
        updatedAt = CurTime(),
        lastStepAt = nil,
        mgDeadline = nil,
        assembleDuration = I.AssembleTime(recipe, rec.wear, level),
        assembleLeft = I.AssembleTime(recipe, rec.wear, level),
        graceUntil = nil,
        pauseReason = nil,
    }
    for _, line in ipairs(plan) do
        job.input[line.itemID] = (job.input[line.itemID] or 0) + line.need
    end

    I.Jobs[job.id] = job
    rec.job = job.id
    ent:SetBusy(true)
    ent:SetWorkerName(job.workerName)
    ent:SetJobStage(job.stage)
    ent:SetProgress(0)

    if steps > 0 then
        job.mgDeadline = CurTime() + steps * job.window * 2.5 + 6
        net.Start(NET.mg)
            net.WriteEntity(ent)
            net.WriteString(I.MinigameKind(rec.kind))
            net.WriteUInt(steps, 8)
            net.WriteFloat(job.window)
            net.WriteTable(sequence or {})
        net.Send(ply)
    else
        notify(ply, "Работа запущена: " .. tostring(recipe.name), true)
    end

    sendJob(job)
    I.SaveSoon()
    return true
end

--[[ ОТМЕНА. refund=true возвращает вложенное сырьё. Возврат идёт в
     выходной контейнер станка, чтобы ничего не пропало, даже если
     игрока уже нет на сервере. ]]
function I.CancelJob(job, reason, refund)
    if not job then return end
    local rec = I.Nodes[job.machine]
    if refund and rec then
        for itemID, n in pairs(job.input or {}) do
            local put = n
            if C.Capacity(rec.outID) >= 0 then
                local unit = I.WeightOf(itemID)
                if unit > 0 then put = math.min(put, math.floor(C.Free(rec.outID) / unit)) end
            end
            if put > 0 then C.Add(rec.outID, itemID, put) end
        end
    end
    if IsValid(job.worker) then notify(job.worker, tostring(reason or "Работа остановлена") .. (refund and ". Материалы возвращены." or ""), false) end

    I.Jobs[job.id] = nil
    if rec then
        rec.job = nil
        if IsValid(rec.ent) then
            rec.ent:SetBusy(false)
            rec.ent:SetWorkerName("")
            rec.ent:SetJobStage("")
            rec.ent:SetProgress(0)
        end
    end
    I.SaveSoon()
end

-- Результат мини-игры → качество → исход → стадия.
function I.ResolveProcess(job)
    local rec = I.Nodes[job.machine]
    if not rec then I.CancelJob(job, "Станок исчез", true) return end

    local quality = I.QualityFromSteps(job.steps, job.window)
    job.quality = quality

    local outcome, info = I.OutcomeFor(quality, rec.wear)
    job.outcome = outcome

    if outcome == "defect" then
        -- Брак: часть сырья возвращается, изделие идёт в переплавку.
        for itemID, n in pairs(job.input or {}) do
            local back = math.max(1, math.floor(n * (info.refund or 0.5)))
            local put = back
            if C.Capacity(rec.outID) >= 0 then
                local unit = I.WeightOf(itemID)
                if unit > 0 then put = math.min(put, math.floor(C.Free(rec.outID) / unit)) end
            end
            if put > 0 then C.Add(rec.outID, itemID, put) end
        end
        local defect = I.DefectFor[rec.kind]
        if defect then
            local unit = I.WeightOf(defect)
            if C.Free(rec.outID) >= unit then C.Add(rec.outID, defect, 1) end
        end
        if IsValid(job.worker) then
            notify(job.worker, "Брак. Часть материалов возвращена (" .. tostring(quality) .. "/100)", false)
        end
        I.Jobs[job.id] = nil
        rec.job = nil
        if IsValid(rec.ent) then rec.ent:SetBusy(false) rec.ent:SetJobStage("") rec.ent:SetProgress(0) rec.ent:SetWorkerName("") end
        I.SaveSoon()
        return
    end

    job.stage = "assemble"
    job.priceMul = info.priceMul
    if IsValid(rec.ent) then rec.ent:SetJobStage("assemble") end
    if IsValid(job.worker) then
        notify(job.worker, tostring(info.label) .. " (" .. tostring(quality) .. "/100). Сборка…", true)
    end
    sendJob(job)
end

local function finishJob(job)
    local rec = I.Nodes[job.machine]
    if not rec then I.CancelJob(job, "Станок исчез", true) return end
    local recipe = job.recipe

    local itemID = recipe.output
    local count = math.max(1, math.floor(tonumber(recipe.outputCount) or 1))

    -- Изделие кладётся в выход станка, а не в мир: старый цех выкидывал
    -- его пропом на пол, и подобрать продукцию мог любой прохожий.
    local ok = C.Add(rec.outID, itemID, count)
    if not ok then
        -- Место проверялось на старте, но могло заняться брaком от
        -- параллельной работы. Держим задачу, пока не освободится.
        job.stage = "blocked"
        job.pauseReason = "Выход станка забит"
        if IsValid(rec.ent) then rec.ent:SetJobStage("blocked") end
        sendJob(job)
        return
    end

    rec.wear = I.Clamp((tonumber(rec.wear) or 0) + (tonumber(recipe.wear) or CFG.WearPerCraft), 0, CFG.WearCap)
    if IsValid(rec.ent) then rec.ent:SetWear(math.floor(rec.wear)) end

    -- Навык растёт от качества, а не от количества сделанного.
    local key = job.workerKey
    if key ~= "" then
        I.Levels[key] = I.Levels[key] or {}
        local kind = rec.kind
        local cur = tonumber(I.Levels[key][kind]) or 0
        local gain = (job.quality or 0) >= 90 and 1 or ((job.quality or 0) >= 60 and 0.5 or 0)
        I.Levels[key][kind] = cur + gain
        I.LevelsDirty = true
    end

    if GRM.Audit and GRM.Audit.Write then
        GRM.Audit.Write("industry", "produce", job.worker, nil,
            { recipe = job.recipeID, quality = job.quality, outcome = job.outcome })
    end
    --[[ Имя события ОСТАВЛЕНО ПРЕЖНИМ ("factory_produce"): на него уже
         настроены квестовые шаги admинами. Переименование молча
         обнулило бы прогресс у всех, у кого такой шаг висит. ]]
    hook.Run("GRM_QuestEvent", job.worker, "factory_produce", tostring(itemID), count,
        { station = rec.kind, recipe = job.recipeID, quality = job.quality })

    if IsValid(job.worker) then
        notify(job.worker, "Готово: " .. I.NameOf(itemID) .. ". Заберите из станка.", true)
        job.worker:EmitSound("buttons/button14.wav")
    end

    I.Jobs[job.id] = nil
    rec.job = nil
    if IsValid(rec.ent) then
        rec.ent:SetBusy(false); rec.ent:SetJobStage(""); rec.ent:SetProgress(0); rec.ent:SetWorkerName("")
    end
    I.SaveSoon()
end
I.FinishJob = finishJob

-- ================================================================
--  ПРИСУТСТВИЕ И ТИК
-- ================================================================
local function presence(job)
    local ply = job.worker
    if not IsValid(ply) then return false, "offline" end
    if ply.Alive and not ply:Alive() then return false, "dead" end
    local rec = I.Nodes[job.machine]
    if not rec or not IsValid(rec.ent) then return false, "node_gone" end
    if ply:GetPos():DistToSqr(rec.ent:GetPos()) > (CFG.WorkRadius) ^ 2 then return false, "away" end
    return true
end
I.Presence = presence

local PAUSE_LABEL = { away = "Работник отошёл", dead = "Работник не в строю", offline = "Работник вне сети" }

function I.TickJob(job)
    local now = CurTime()

    if job.stage == "process" then
        -- Мини-игра не может висеть бесконечно: если игрок бросил окно,
        -- недосланные шаги считаем промахами.
        if job.mgDeadline and now > job.mgDeadline then
            for i = (job.stepIndex or 0) + 1, job.expectedSteps do
                job.steps[i] = { error = job.window, missed = true }
            end
            job.stepIndex = job.expectedSteps
            I.ResolveProcess(job)
        end
        return
    end

    if job.stage == "blocked" then
        local rec = I.Nodes[job.machine]
        if rec then
            local unit = I.WeightOf(job.recipe.output) * math.max(1, tonumber(job.recipe.outputCount) or 1)
            if C.Free(rec.outID) >= unit then
                job.stage = "assemble"
                job.pauseReason = nil
                finishJob(job)
            end
        end
        return
    end

    if job.stage ~= "assemble" and job.stage ~= "paused" then return end

    local ok, reason = presence(job)
    local rec = I.Nodes[job.machine]

    if ok then
        job.graceUntil = nil
        if job.stage == "paused" then
            job.stage = "assemble"
            job.pauseReason = nil
            if IsValid(rec and rec.ent) then rec.ent:SetJobStage("assemble") end
            if IsValid(job.worker) then notify(job.worker, "Работа продолжена", true) end
        end
        job.assembleLeft = job.assembleLeft - CFG.TickInterval
        job.progress = I.Clamp(1 - (job.assembleLeft / math.max(1, job.assembleDuration)), 0, 1)
        job.updatedAt = now
        if IsValid(rec and rec.ent) then rec.ent:SetProgress(job.progress) end
        if job.assembleLeft <= 0 then finishJob(job) end
        return
    end

    -- Нет присутствия. Сначала отсчёт, потом пауза — не провал.
    if reason == "node_gone" then I.CancelJob(job, "Станок исчез", true) return end

    if job.stage == "assemble" then
        if not job.graceUntil then
            job.graceUntil = now + CFG.GraceSeconds
        elseif now > job.graceUntil then
            job.stage = "paused"
            job.pauseReason = reason
            if IsValid(rec and rec.ent) then rec.ent:SetJobStage("paused") end
            if IsValid(job.worker) then notify(job.worker, (PAUSE_LABEL[reason] or "Работа приостановлена") .. ". Вернитесь к станку.", false) end
        end
    end

    if now - (job.updatedAt or now) > CFG.AbandonAfter then
        I.CancelJob(job, "Работа заброшена", true)
        return
    end
    job.updatedAt = now
end

local function tickAll()
    -- Сторож: без активных задач тик ничего не делает.
    if not next(I.Jobs) then return end
    for id, job in pairs(I.Jobs) do
        if job then
            local ok, err = pcall(I.TickJob, job)
            if not ok then print("[GRM Industry] ошибка задачи " .. tostring(id) .. ": " .. tostring(err)) end
        end
    end
end

-- ================================================================
--  ИСТОЧНИКИ СЫРЬЯ
-- ================================================================
function I.TickSupply()
    if not next(I.Nodes) then return end
    local s = CFG.Supply
    for _, rec in pairs(I.Nodes) do
        if rec.role == "supply" and rec.supply then
            if rec.supply.stock < (tonumber(s.MaxStock) or 60) and CurTime() >= (rec.supply.nextRefill or 0) then
                rec.supply.stock = math.min(tonumber(s.MaxStock) or 60, rec.supply.stock + (tonumber(s.RefillAmount) or 3))
                rec.supply.nextRefill = CurTime() + (tonumber(s.RefillEvery) or 60)
                if IsValid(rec.ent) then rec.ent:SetStock(rec.supply.stock) end
                I.SaveSoon()
            end
        end
    end
end

timer.Create("GRM_Industry_Tick", CFG.TickInterval, 0, function()
    tickAll()
end)
timer.Create("GRM_Industry_Supply", 5, 0, function()
    I.TickSupply()
end)

-- ================================================================
--  СБЫТ И СКУПКА
-- ================================================================
I.SellPercent = I.SellPercent or 0.5

local function sellItem(ply, node, itemID, count)
    local rec = I.NodeFor(node)
    if not rec then return false, "Узел не найден" end
    local playerBox = C.ForPlayer(ply)
    if not playerBox then return false, "Инвентарь недоступен" end

    count = math.max(1, math.floor(tonumber(count) or 1))
    if C.Count(playerBox.id, itemID) < count then return false, "Недостаточно предметов" end

    local unit = I.PriceOf(itemID)
    if unit <= 0 then return false, "Это здесь не покупают" end

    local total = math.floor(unit * count * I.SellPercent)
    local ok = C.Take(playerBox.id, itemID, count)
    if not ok then return false, "Не удалось забрать предмет" end

    if GRM.GiveMoney then GRM.GiveMoney(ply, total, "industry_sell") end
    if GRM.Audit and GRM.Audit.Write then
        GRM.Audit.Write("industry", "sell", ply, nil, { item = itemID, count = count, total = total })
    end
    return true, "Продано за " .. tostring(GRM.Format and GRM.Format(total) or total)
end

local function buyScrap(ply, node, count)
    local rec = I.NodeFor(node)
    if not rec then return false, "Узел не найден" end
    count = math.max(1, math.min(100, math.floor(tonumber(count) or 1)))
    local price = math.floor(count * (tonumber(CFG.Supply.BuyPrice) or 60))
    if GRM.HasMoney and not GRM.HasMoney(ply, price) then return false, "Недостаточно денег" end

    local playerBox = C.ForPlayer(ply)
    if not playerBox then return false, "Инвентарь недоступен" end

    local ok = C.Add(playerBox.id, "scrap_metal", count)
    if not ok then return false, "Нет места в инвентаре" end
    if GRM.TakeMoney then GRM.TakeMoney(ply, price, "industry_buy_scrap") end
    return true, "Куплено " .. count .. " металлолома"
end

-- ================================================================
--  ОТКРЫТИЕ ОКОН
-- ================================================================
local function recipePayload(rec, ply)
    local playerBox = C.ForPlayer(ply)
    local out = {}
    for _, entry in ipairs(I.RecipesFor(rec.kind)) do
        local r = entry.recipe
        local inputs = {}
        for itemID, n in pairs(r.input or {}) do
            local have = (C.Count(rec.inID, itemID) or 0) + (playerBox and C.Count(playerBox.id, itemID) or 0)
            inputs[#inputs + 1] = { itemID = itemID, need = n, have = have, name = I.NameOf(itemID) }
        end
        table.sort(inputs, function(a, b) return a.name < b.name end)
        out[#out + 1] = {
            id = entry.id, name = entry.name,
            weapon = r.weapon, output = r.output,
            outputName = I.NameOf(r.output),
            inputs = inputs,
            process = r.process, assemble = r.assemble,
            scrap = r.scrap, price = r.price or I.PriceOf(r.output),
        }
    end
    return out
end

function I.OpenNode(ply, ent)
    if not inRange(ply, ent, 260) then notify(ply, "Подойдите ближе", false) return end
    local rec = I.NodeFor(ent)
    if not rec then notify(ply, "Узел не настроен", false) return end

    -- Шкаф фракции: сначала фракция, потом окно. Поле «фракция» у узла
    -- было подписью без проверки — оружие мог забрать любой.
    if rec.role == "armory" then
        local allowed, why = I.CanUseFactionNode(ply, ent)
        if not allowed then
            notify(ply, "Шкаф принадлежит другой фракции", false)
            return
        end
    end

    -- Логистика обрабатывает свои роли сама.
    if I.NodeHandlers[rec.role] then
        I.NodeHandlers[rec.role](ply, ent, rec)
        return
    end

    local payload = {
        role = rec.role,
        kind = rec.kind or "",
        label = tostring(ent:GetNodeLabel() or ""),
        faction = tostring(ent:GetFactionName() or ""),
        wear = I.Round(rec.wear or 0, 1),
        input = rec.inID and C.List(rec.inID) or {},
        output = rec.outID and C.List(rec.outID) or {},
        outputWeight = rec.outID and C.Weight(rec.outID) or 0,
        outputCapacity = rec.outID and C.Capacity(rec.outID) or -1,
        recipes = {},
        stations = {},
        job = nil,
        player = {},
        money = (GRM.GetBalance and GRM.GetBalance(ply)) or 0,
        sellPercent = I.SellPercent,
    }

    local playerBox = C.ForPlayer(ply)
    if playerBox then payload.player = C.List(playerBox.id) end

    if rec.role == "station" then
        payload.recipes = recipePayload(rec, ply)
        for id, st in pairs(I.Stations) do payload.stations[#payload.stations + 1] = { id = id, name = st.name } end
        table.sort(payload.stations, function(a, b) return a.name < b.name end)
        if rec.job and I.Jobs[rec.job] then
            local job = I.Jobs[rec.job]
            payload.job = jobPayload(job)
            -- Продолжить чужую задачу может любой, у кого есть доступ.
            payload.job.canResume = not IsValid(job.worker) or job.worker == ply
        end
    elseif rec.role == "supply" then
        payload.stock = rec.supply and rec.supply.stock or 0
        payload.maxStock = tonumber(CFG.Supply.MaxStock) or 60
    elseif rec.role == "market" then
        payload.scrapPrice = tonumber(CFG.Supply.BuyPrice) or 60
    end

    net.Start(NET.open)
        net.WriteEntity(ent)
        net.WriteTable(payload)
    net.Send(ply)
end

function I.UseNode(ply, ent)
    if not IsValid(ply) or not IsValid(ent) then return end
    I.OpenNode(ply, ent)
end

-- ================================================================
--  ДЕЙСТВИЯ ИЗ ОКОН
-- ================================================================
local function playerBoxOf(ply)
    local box = C.ForPlayer(ply)
    if not box then notify(ply, "Инвентарь недоступен", false) return nil end
    return box
end

I.Actions = I.Actions or {}
local Actions = I.Actions

Actions.refresh = function(ply, ent, rec)
    I.OpenNode(ply, ent)
    return true
end

-- Станок: загрузить сырьё в его вход.
Actions.deposit = function(ply, ent, rec)
    local itemID = net.ReadString()
    local count = net.ReadUInt(16)
    if not rec.inID then return false end
    local box = playerBoxOf(ply); if not box then return false end
    local moved = C.MoveUpTo(box.id, rec.inID, itemID, count)
    if moved <= 0 then notify(ply, "Не удалось положить (нет предмета или места)", false) return false end
    notify(ply, "Загружено: " .. I.NameOf(itemID) .. " ×" .. moved, true)
    I.OpenNode(ply, ent)
    return true
end

-- Станок: забрать из выхода.
--[[ РЕШЕНИЕ ВЛАДЕЛЬЦА (31.08): «Станки общие». Владельца у выхода
     станка НЕТ: забрать готовое может любой, кто подошёл. Это осознанный
     выбор, а не недосмотр — не добавлять сюда проверку владельца или
     фракции. Стенд sim_industry_job это решение фиксирует. ]]
Actions.withdraw = function(ply, ent, rec)
    local itemID = net.ReadString()
    local count = net.ReadUInt(16)
    if not rec.outID then return false end
    count = math.max(1, math.floor(count))

    -- Оружие выдаётся в руки, а не в инвентарь как предмет.
    local recipe = I.Recipes[itemID]
    if recipe and recipe.weapon then
        if not weapons.Get(recipe.weapon) then notify(ply, "Оружие недоступно на сервере", false) return false end
        if C.Count(rec.outID, itemID) < 1 then notify(ply, "Здесь этого нет", false) return false end
        if ply:HasWeapon(recipe.weapon) then notify(ply, "Такое оружие у вас уже есть", false) return false end
        C.Take(rec.outID, itemID, 1)
        ply:Give(recipe.weapon)
        notify(ply, "Получено: " .. tostring(recipe.name or itemID), true)
    else
        local box = playerBoxOf(ply); if not box then return false end
        local moved = C.MoveUpTo(rec.outID, box.id, itemID, count)
        if moved <= 0 then notify(ply, "Не удалось забрать (нет места или предмета)", false) return false end
        notify(ply, "Забрано: " .. I.NameOf(itemID) .. " ×" .. moved, true)
    end
    I.OpenNode(ply, ent)
    return true
end

Actions.job_start = function(ply, ent, rec)
    local recipeID = net.ReadString()
    return I.StartJob(ply, ent, recipeID)
end

--[[ Подхватить чужую задачу. Станки общие, поэтому:
       * работу, вставшую на паузу (работник ушёл/вышел), может продолжить
         любой — иначе станок простаивает без хозяина;
       * работу, которая ИДЁТ, перехватить нельзя: живой работник у станка
         имеет приоритет. ]]
Actions.job_resume = function(ply, ent, rec)
    local job = rec.job and I.Jobs[rec.job] or nil
    if not job then notify(ply, "Здесь нечего продолжать", false) return false end
    if IsValid(job.worker) and job.worker ~= ply and job.stage ~= "paused" then
        notify(ply, "Станок занят другим работником", false) return false
    end
    job.worker = ply
    job.workerKey = charKey(ply)
    job.workerName = ply:GetNWString("GRM_RPName", "") ~= "" and ply:GetNWString("GRM_RPName", "") or ply:Nick()
    if job.stage == "paused" then job.stage = "assemble"; job.pauseReason = nil end
    job.graceUntil = nil
    if IsValid(ent) then ent:SetWorkerName(job.workerName) ent:SetJobStage(job.stage) end
    notify(ply, "Вы продолжили работу", true)
    sendJob(job)
    return true
end

Actions.job_cancel = function(ply, ent, rec)
    local job = rec.job and I.Jobs[rec.job] or nil
    if not job then return false end
    if job.worker ~= ply and not (ply:IsSuperAdmin()) then
        notify(ply, "Это чужая работа", false) return false
    end
    I.CancelJob(job, "Работа отменена", true)
    return true
end

-- Склад цеха: принять продукцию с рук.
Actions.storage_deposit = function(ply, ent, rec)
    local itemID = net.ReadString()
    local count = net.ReadUInt(16)
    local box = playerBoxOf(ply); if not box then return false end
    local moved = C.MoveUpTo(box.id, rec.outID, itemID, count)
    if moved <= 0 then notify(ply, "Не удалось положить", false) return false end
    notify(ply, "Положено на склад: " .. I.NameOf(itemID) .. " ×" .. moved, true)
    I.OpenNode(ply, ent)
    return true
end

Actions.storage_take = function(ply, ent, rec)
    local itemID = net.ReadString()
    local count = net.ReadUInt(16)
    local box = playerBoxOf(ply); if not box then return false end
    local moved = C.MoveUpTo(rec.outID, box.id, itemID, count)
    if moved <= 0 then notify(ply, "Не удалось забрать", false) return false end
    notify(ply, "Взято со склада: " .. I.NameOf(itemID) .. " ×" .. moved, true)
    I.OpenNode(ply, ent)
    return true
end

Actions.supply_take = function(ply, ent, rec)
    local count = net.ReadUInt(16)
    count = math.max(1, math.min(20, math.floor(count)))
    if not rec.supply then return false end
    local take = math.min(count, rec.supply.stock)
    if take <= 0 then notify(ply, "Здесь пока пусто", false) return false end
    local box = playerBoxOf(ply); if not box then return false end
    local ok = C.Add(box.id, "scrap_metal", take)
    if not ok then notify(ply, "Нет места в инвентаре", false) return false end
    rec.supply.stock = rec.supply.stock - take
    ent:SetStock(rec.supply.stock)
    notify(ply, "Взято металлолома: " .. take, true)
    I.OpenNode(ply, ent)
    return true
end

Actions.market_sell = function(ply, ent, rec)
    local itemID = net.ReadString()
    local count = net.ReadUInt(16)
    local ok, message = sellItem(ply, ent, itemID, count)
    notify(ply, message or (ok and "Готово" or "Не вышло"), ok == true)
    I.OpenNode(ply, ent)
    return ok
end

Actions.market_buy_scrap = function(ply, ent, rec)
    local count = net.ReadUInt(16)
    local ok, message = buyScrap(ply, ent, count)
    notify(ply, message or (ok and "Готово" or "Не вышло"), ok == true)
    I.OpenNode(ply, ent)
    return ok
end

-- Наладка станка: смена типа и ремонт.
Actions.station_setup = function(ply, ent, rec)
    if not I.CanManage(ply) then notify(ply, "Нет права наладки цеха", false) return false end
    local kind = net.ReadString()
    if not I.Stations[kind] then notify(ply, "Неизвестный тип станка", false) return false end
    if rec.job and I.Jobs[rec.job] then notify(ply, "Сначала остановите работу", false) return false end
    if not C.IsEmpty(rec.inID) or not C.IsEmpty(rec.outID) then
        notify(ply, "Сначала освободите вход и выход станка", false) return false
    end
    ent:SetNodeKind(kind)
    rec.kind = kind
    local model = I.Stations[kind].model
    if model then ent:SetModel(model) end
    notify(ply, "Тип станка: " .. I.Stations[kind].name, true)
    I.OpenNode(ply, ent)
    return true
end

Actions.station_repair = function(ply, ent, rec)
    local box = playerBoxOf(ply); if not box then return false end
    if (tonumber(rec.wear) or 0) <= 0 then notify(ply, "Станок не изношен", false) return false end
    if C.Count(box.id, "item_repair_kit") < 1 then notify(ply, "Нужен ремкомплект", false) return false end
    C.Take(box.id, "item_repair_kit", 1)
    rec.wear = 0
    ent:SetWear(0)
    notify(ply, "Станок отремонтирован", true)
    I.OpenNode(ply, ent)
    return true
end

net.Receive(NET.action, function(bits, ply)
    local ent = net.ReadEntity()
    local op = net.ReadString()
    if not IsValid(ply) or not IsValid(ent) then return end

    local rec = I.NodeFor(ent)
    if not rec then return end
    local fn = Actions[op]
    if not fn then return end

    -- ЕДИНАЯ ТОЧКА ПРОВЕРКИ. Старые обработчики цеха и логистики не
    -- проходили через GRM.Net.Guard вообще — ни рейта, ни лимита
    -- размера, ни дистанции.
    local cap = I.ActionCapability[op]
    if GRM.Net and GRM.Net.Guard then
        local ok = GRM.Net.Guard(ply, "industry." .. tostring(op), {
            rate = 0.25, burst = 6, maxBits = 32768, distance = 300,
            capability = cap,
        }, { bits = bits, entity = ent })
        if ok ~= true then return end
    else
        -- Без GRM.Net.Guard (например, в стендах) права всё равно проверяем.
        if cap and GRM.Access and GRM.Access.Can and not GRM.Access.Can(ply, cap, { entity = ent }) then
            notify(ply, "Нет права: " .. cap, false)
            return
        end
        if not inRange(ply, ent, 300) then return end
    end

    local ok, err = pcall(fn, ply, ent, rec)
    if not ok then
        print("[GRM Industry] ошибка действия '" .. tostring(op) .. "': " .. tostring(err))
        notify(ply, "Сбой действия, попробуйте ещё раз", false)
    end
end)

-- Шаг мини-игры: игрок сообщает, насколько попал в окно.
net.Receive(NET.step, function(bits, ply)
    local ent = net.ReadEntity()
    local index = net.ReadUInt(8)
    local err = net.ReadFloat()
    local missed = net.ReadBool()
    local lane = net.ReadUInt(4)

    if not IsValid(ply) or not IsValid(ent) then return end
    local rec = I.NodeFor(ent)
    if not rec then return end
    local job = rec.job and I.Jobs[rec.job] or nil
    if not job or job.worker ~= ply or job.stage ~= "process" then return end

    if GRM.Net and GRM.Net.Guard then
        local ok = GRM.Net.Guard(ply, "industry.step", { rate = 0.08, burst = 12, maxBits = 512, distance = 300 },
            { bits = bits, entity = ent })
        if ok ~= true then return end
    end

    -- Защита от «прощёлкал быстрее, чем возможно».
    local now = CurTime()
    if job.lastStepAt and (now - job.lastStepAt) < (tonumber(CFG.MinSecondsPerStep) or 0.25) then return end
    if index ~= (job.stepIndex or 0) + 1 then return end

    job.lastStepAt = now
    job.stepIndex = index
    err = math.abs(tonumber(err) or 0)
    -- Клиент не может прислать ошибку меньше окна и получить ноль штрафа,
    -- при этом «пролетев» шаг: верхний предел ошибки — само окно.
    if err > job.window then err = job.window end

    -- Сборка: нажата ли та стрелка, которую задал сервер.
    local expectedLane = (job.sequence or {})[index]
    if expectedLane and expectedLane > 0 then
        if lane ~= expectedLane and lane ~= 0 then missed = true end
        -- lane == 0 означает «время вышло», это всегда промах.
        if lane == 0 then missed = true end
    end

    job.steps[index] = { error = err, missed = missed == true }

    if index >= (job.expectedSteps or 0) then
        I.ResolveProcess(job)
    else
        sendJob(job)
    end
end)

-- ================================================================
--  СОХРАНЕНИЕ
-- ================================================================
local saveQueued = false
function I.SaveSoon()
    if saveQueued then return end
    saveQueued = true
    timer.Simple(2, function()
        saveQueued = false
        I.Save()
    end)
end

function I.Save()
    if not P or not P.SaveJSON then return false end
    local data = {
        version = SAVE_VERSION,
        nodes = {},
        jobs = {},
        containers = C.Serialize(),
    }
    for id, rec in pairs(I.Nodes) do
        data.nodes[id] = {
            id = id, role = rec.role, kind = rec.kind,
            wear = rec.wear, supply = rec.supply, demand = rec.demand,
            job = rec.job,
        }
    end
    for id, job in pairs(I.Jobs) do
        data.jobs[id] = {
            id = id, machine = job.machine, recipeID = job.recipeID,
            stage = job.stage, pauseReason = job.pauseReason,
            quality = job.quality, outcome = job.outcome,
            progress = job.progress, input = job.input,
            steps = job.steps, stepIndex = job.stepIndex,
            expectedSteps = job.expectedSteps, window = job.window,
            assembleDuration = job.assembleDuration, assembleLeft = job.assembleLeft,
            workerKey = job.workerKey, workerName = job.workerName,
            updatedAt = job.updatedAt,
        }
    end
    local ok, reason = P.SaveJSON(MAP_FILE, data)
    if not ok then print("[GRM Industry] не удалось сохранить карту: " .. tostring(reason)) end

    -- Заказы и рейсы пишет логистика, но сохраняются они одним вызовом:
    -- иначе администратор должен помнить про две команды.
    if I.SaveOrders then I.SaveOrders() end

    if I.LevelsDirty and P.SaveJSON then
        P.SaveJSON(LEVELFILE, { version = 1, levels = I.Levels })
        I.LevelsDirty = nil
    end
    return ok
end

function I.Load()
    if not P or not P.LoadJSON then return end
    local data, state = P.LoadJSON(MAP_FILE, { version = SAVE_VERSION, nodes = {}, jobs = {}, containers = {} },
        { version = SAVE_VERSION })
    if not istable(data) then return end

    C.Deserialize(data.containers or {})

    for id, rec in pairs(data.nodes or {}) do
        if istable(rec) then
            I.Nodes[id] = {
                id = id, role = rec.role, kind = rec.kind,
                wear = tonumber(rec.wear) or 0,
                supply = rec.supply, demand = rec.demand,
                job = nil,
            }
            local n = I.Nodes[id]
            n.inID = (n.role == "station") and containerID(id, "in") or nil
            n.outID = containerID(id, n.role == "station" and "out" or nil)
        end
    end

    -- Задачи восстанавливаем только те, у которых есть станок.
    for id, j in pairs(data.jobs or {}) do
        if istable(j) and I.Nodes[j.machine] then
            local recipe = I.Recipes[j.recipeID]
            if recipe then
                local job = {
                    id = j.id, machine = j.machine, recipeID = j.recipeID, recipe = recipe,
                    stage = j.stage == "process" and "paused" or (j.stage or "assemble"),
                    pauseReason = j.stage == "process" and "offline" or j.pauseReason,
                    quality = j.quality, outcome = j.outcome,
                    progress = tonumber(j.progress) or 0, input = j.input or {},
                    steps = j.steps or {}, stepIndex = tonumber(j.stepIndex) or 0,
                    expectedSteps = tonumber(j.expectedSteps) or 0, window = tonumber(j.window) or 1,
                    assembleDuration = tonumber(j.assembleDuration) or 10,
                    assembleLeft = tonumber(j.assembleLeft) or 10,
                    workerKey = j.workerKey or "", workerName = j.workerName or "?",
                    updatedAt = tonumber(j.updatedAt) or os.time(),
                    worker = NULL,
                }
                I.Jobs[id] = job
                I.Nodes[j.machine].job = id
            end
        end
    end

    local levels = P.LoadJSON(LEVELFILE, { version = 1, levels = {} })
    if istable(levels) and istable(levels.levels) then I.Levels = levels.levels end

    print("[GRM Industry] загружено: узлов " .. tostring(#I.Nodes) .. ", задач " .. tostring(#I.Jobs) ..
        ", состояние " .. tostring(state))
end

--[[ Загрузка идёт через GRM.Boot, а не своим хуком InitPostEntity:
     так восстановление карты стоит в общей очереди старта и не
     соревнуется с остальными модулями за порядок. ]]
if GRM.Boot and GRM.Boot.Task then
    GRM.Boot.Task("industry.map", "late", function() I.Load() end)
else
    hook.Add("InitPostEntity", "GRM_Industry_Load", function()
        timer.Simple(1, function() I.Load() end)
    end)
end
hook.Add("ShutDown", "GRM_Industry_Save", function() I.Save() end)
hook.Add("PreCleanupMap", "GRM_Industry_Save", function() I.Save() end)

-- ================================================================
--  КОНСОЛЬНЫЕ КОМАНДЫ
-- ================================================================
--[[ Старые команды цеха и логистики (grm_fc_save, grm_logistics_place_*,
     grm_logistics_admin_menu) ушли вместе со старыми файлами. Кнопка
     «Логистика и снабжение» в админке фракций и в едином центре
     управления ссылалась на grm_logistics_admin_menu, поэтому команду
     с этим именем оставляем — иначе кнопка молча ничего не делает. ]]
concommand.Add("grm_industry_status", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    local nodes, jobs, orders, routes = 0, 0, 0, 0
    for _ in pairs(I.Nodes) do nodes = nodes + 1 end
    for _ in pairs(I.Jobs) do jobs = jobs + 1 end
    if I.Orders then for _ in pairs(I.Orders) do orders = orders + 1 end end
    if I.Routes then for _ in pairs(I.Routes) do routes = routes + 1 end end
    local function say(s) if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, s) end print(s) end
    say("[GRM Industry] узлов: " .. nodes .. ", задач: " .. jobs .. ", заказов: " .. orders .. ", рейсов: " .. routes)
    for id, rec in pairs(I.Nodes) do
        say("  " .. tostring(rec.role) .. " [" .. tostring(id) .. "]" ..
            (rec.kind and (" тип " .. rec.kind) or "") ..
            " износ " .. tostring(math.floor(rec.wear or 0)) .. "%")
    end
end)

concommand.Add("grm_industry_save", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    local ok = I.Save()
    print("[GRM Industry] сохранение: " .. tostring(ok and "готово" or "ошибка"))
end)

concommand.Add("grm_industry_load", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    I.Load()
    print("[GRM Industry] загрузка выполнена")
end)

concommand.Add("grm_logistics_admin_menu", function(ply)
    if IsValid(ply) then
        if GRM.Notify then
            GRM.Notify(ply, "Логистика и производство переписаны. Команды: grm_industry_status, grm_industry_save, grm_industry_load. Узлы ставятся инструментом «GRM Производство и логистика».", 100, 200, 255)
        end
    end
    concommand.Run(ply or NULL, "grm_industry_status")
end)

-- ================================================================
--  ПРАВА
-- ================================================================
--[[ Пункт 9 из списка вопросов владельца: capability были зарегистрированы,
     но нигде не спрашивались — производство держалось на честном слове.

     ЗНАЧЕНИЕ default КРИТИЧНО. GRM.Access.Can возвращает
     `definition.default == true`, когда нет ни гранта, ни провайдера:
     то есть по умолчанию capability ЗАПРЕЩЕНА. Поэтому открытые действия
     обязаны объявить default = true, иначе подключение проверок разом
     заперло бы производство для всех — вразрез с решением владельца
     «станки общие». Суперадмин обходит запрет автоматически
     (superadminBypass по умолчанию включён). ]]
I.ActionCapability = {
    -- Работа у станка и торговля: открыто всем, но фракция или админ
    -- могут закрыть точечной выдачей права в /factions → Доступы.
    deposit          = "industry.produce",
    withdraw         = "industry.produce",
    job_start        = "industry.produce",
    job_resume       = "industry.produce",
    job_cancel       = "industry.produce",
    supply_take      = "industry.produce",
    storage_deposit  = "industry.produce",
    storage_take     = "industry.produce",
    market_sell      = "industry.produce",
    market_buy_scrap = "industry.produce",
    station_repair   = "industry.produce",

    -- Наладка: только по выдаче. Менять тип станка и спрос склада
    -- может не каждый — это настройка экономики сервера.
    station_setup    = "industry.manage",
    warehouse_demand = "industry.manage",

    -- Рейсы и шкаф: открыто, но закрываемо.
    order_take       = "industry.logistics",
    order_load       = "industry.logistics",
    order_go         = "industry.logistics",
    order_deliver    = "industry.logistics",
    route_abandon    = "industry.logistics",
    armory_store     = "industry.logistics",
    armory_take      = "industry.logistics",
}

if GRM.Access and GRM.Access.Register then
    GRM.Access.Register("industry.produce", {
        label = "Производство",
        description = "Работать на станках, склады и точки сбыта",
        default = true,          -- станки общие (решение владельца 31.08)
    })
    GRM.Access.Register("industry.manage", {
        label = "Наладка цеха",
        description = "Менять тип станка и спрос склада фракции",
        default = false,         -- только по выдаче
    })
    GRM.Access.Register("industry.logistics", {
        label = "Логистика",
        description = "Брать заказы, возить грузы, пользоваться шкафом фракции",
        default = true,          -- рейсы открыты, награда в руки
    })
end

print("[GRM Industry] сервер загружен, версия " .. tostring(I.Version))
