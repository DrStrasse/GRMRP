--[[ GRM Quest Ecosystem v1.0.0 — authoritative quests, NPCs, objectives and persistence ]]
if SERVER then
    AddCSLuaFile()
    AddCSLuaFile("autorun/client/cl_grm_quests.lua")
end

GRM = GRM or {}
GRM.Quests = GRM.Quests or {}
local Q = GRM.Quests
Q.Version = "1.5.0"
Q.Definitions = Q.Definitions or {}
Q.Progress = Q.Progress or {}
Q.NPCs = Q.NPCs or {}
Q.EventTypes = {
    generic="Событие", mining="Добыча руды", factory_produce="Производство",
    inventory_gain="Получение предмета", visit="Посещение", talk="Разговор",
    invoice_paid="Оплата счёта", warrant_approved="Ордер утверждён", call_911="Вызов 911",
    ore_sell="Продажа руды",
}

local function trim(value, limit)
    value = string.Trim(tostring(value or ""))
    if GRM.Utf8Sub then return GRM.Utf8Sub(value, limit or 128) end
    return string.sub(value, 1, limit or 128)
end
local function characterKey(ply)
    if GRM.Identity and GRM.Identity.CharacterKey then return GRM.Identity.CharacterKey(ply) end
    if GRM.Char and GRM.Char.GetActiveKey then return GRM.Char.GetActiveKey(ply) end
    return tostring(ply:SteamID64()) .. ":char1"
end
Q.CharacterKey = characterKey

--[[--------------------------------------------------------------------
    КОГДА ЧТО СРАБАТЫВАЕТ (заказ владельца 28.08).

    «Не понятно, как выстраивать выдачу наград и ачивок, и к чему
     сделано криво — до квеста / вовремя / после? Как подключить
     выплаты? Как диалоги нормально настроить?»

    Порядок жизни квеста жёстко зашит в код, но раньше нигде не был
    записан, поэтому со стороны выглядел произвольным. Фиксируем его
    здесь ОДИН раз, и студия строит свою подсказку из этой же таблицы —
    чтобы описание не разошлось с поведением.

    Ось времени:

      1. ДО КВЕСТА. Игрок подходит к NPC. Проигрывается диалог фазы
         «offer». Награды тут НЕ выдаются. Единственный способ выдать
         квест — ответ с действием «Принять квест» (accept). Нет такого
         ответа — квест взять физически нельзя.

      2. ПРИНЯТИЕ. Q.Start: пишется прогресс, показывается уведомление
         «start», проигрывается кат-сцена «accept».

      3. ВО ВРЕМЯ. Идут этапы. На каждом выполненном — уведомление
         «step». Диалог фазы «active» это просто разговор по ходу дела,
         он на прогресс не влияет (кроме своих действий вроде «Событие»).

      4. ЗАВЕРШЕНИЕ. Когда кончились этапы: сначала НАГРАДА КВЕСТА
         (деньги и предметы), затем АЧИВКА со своей отдельной наградой,
         затем уведомление «complete», затем кат-сцена «complete».

      5. ПОСЛЕ. Диалог фазы «complete» — только разговор. Повторная
         выдача награды не происходит: если квест не «повторяемый»,
         второй раз его не начать.

    Отсюда ответ на вопрос «как подключить выплаты»: награда квеста —
    вкладка «Награды», выдаётся САМА в шаге 4. Отдельные выплаты по ходу
    разговора — действие «Деньги»/«Предмет» у ответа в диалоге.
----------------------------------------------------------------------]]
Q.Lifecycle = {
    { phase = "offer",    when = "ДО КВЕСТА",   what = "Диалог у NPC. Награды не выдаются. Взять квест можно ТОЛЬКО ответом с действием «Принять квест»." },
    { phase = "start",    when = "ПРИНЯТИЕ",    what = "Уведомление «Принятие квеста» + кат-сцена «При принятии»." },
    { phase = "active",   when = "ВО ВРЕМЯ",    what = "Этапы по порядку. На каждом — уведомление «Завершение этапа». Диалог «Во время квеста» на прогресс не влияет." },
    { phase = "complete", when = "ЗАВЕРШЕНИЕ",  what = "1) награда квеста: деньги и предметы; 2) ачивка и её отдельная награда; 3) уведомление; 4) кат-сцена «При завершении»." },
    { phase = "after",    when = "ПОСЛЕ",       what = "Диалог «После завершения» — только разговор. Награда повторно не выдаётся." },
}

--[[ ПРОВЕРКА КВЕСТА НА ТИПОВЫЕ ОШИБКИ.

     Держим в ОБЩЕЙ части, а не в студии: так одна и та же проверка
     работает и в редакторе, и на сервере при сохранении, и в стенде.

     Возвращает список проблем: { level = "error"|"warn", text = ... }.
     error — квест сломан и работать не будет; warn — работать будет, но
     почти наверняка не так, как задумано. ]]
--[[--------------------------------------------------------------------
    КОПИРОВАНИЕ КВЕСТА И ШАБЛОНЫ (заказ владельца 29.08).

    «Сделай возможность копирования квестов и создание шаблонов, но при
     этом с пометкой о необходимости изменить какие-либо параметры или
     просто плашку с предупреждением, что параметры могут отличаться.»

    ЧТО НЕЛЬЗЯ ПРОСТО СКОПИРОВАТЬ. Копия квеста — это не копия текста:
    часть данных привязана к конкретному месту и к конкретным именам.

      • ID квеста — обязан быть новым, иначе копия ЗАТРЁТ оригинал;
      • ID достижения — если оставить старый, два квеста будут выдавать
        одну и ту же ачивку, и вторая просто не сработает;
      • зоны этапов «посетить место» — это координаты. В копии они
        указывают туда же, куда оригинал: обычно это ошибка;
      • точки камер — тоже координаты, тот же случай;
      • ID квестового NPC — если оставить прежний, оба квеста повиснут
        на одном персонаже;
      • «предыдущие квесты» — ссылки могли остаться от старой цепочки.

    Поэтому копия помечается: Q.CopyQuest готовит данные, а
    Q.CopyWarnings перечисляет, что перепроверить. Список строится по
    ФАКТИЧЕСКОМУ содержимому, а не общими словами: пустые разделы не
    упоминаются, чтобы предупреждение не превращалось в шум.
----------------------------------------------------------------------]]

--- Что в этом квесте требует правки после копирования.
function Q.CopyWarnings(def)
    local out = {}
    if not istable(def) then return out end
    local function add(level, text) out[#out + 1] = { level = level, text = text } end

    add("must", "ID квеста заменён на новый — переименуйте на осмысленный.")

    local zones, cams = 0, 0
    for _, s in ipairs(istable(def.steps) and def.steps or {}) do
        if tostring(s.type or "") == "visit" and (istable(s.min) or istable(s.pos)) then
            zones = zones + 1
        end
    end
    for _, phase in ipairs({ "accept", "complete" }) do
        cams = cams + #((istable(def.cutscene) and def.cutscene[phase]) or {})
    end

    if zones > 0 then
        add("must", ("Зон этапов «посетить место»: %d — координаты те же, что у оригинала. Переставьте тулом."):format(zones))
    end
    if cams > 0 then
        add("must", ("Точек камер: %d — снимают то же место. Переснимите или переставьте."):format(cams))
    end
    if tostring(def.npc or "") ~= "" then
        add("check", ("NPC «%s» тот же. Если это отдельный персонаж — задайте новый ID."):format(tostring(def.npc)))
    end
    local ach = istable(def.achievement) and def.achievement or {}
    if ach.enabled then
        add("must", "ID достижения обновлён: со старым оба квеста выдавали бы одну ачивку.")
    end
    if #(istable(def.prerequisites) and def.prerequisites or {}) > 0 then
        add("check", "Заданы «предыдущие квесты» — проверьте, нужна ли эта цепочка копии.")
    end
    local m = tostring(def.map or "")
    if m ~= "" and m ~= string.lower((game and game.GetMap and game.GetMap()) or "") then
        add("must", ("Квест был создан для карты «%s» — координаты здесь не совпадут."):format(m))
    end
    add("check", "Награда, тексты и уведомления скопированы как есть — при необходимости поправьте.")

    return out
end

--[[ Подготовить копию. Возвращает новый квест и список предупреждений.

     asTemplate=true — режим шаблона: чистим то, что почти наверняка
     придётся задавать заново (координаты зон, камеры, привязку к NPC),
     оставляя структуру этапов и диалогов. Иначе автор получил бы «почти
     готовый» квест, который тихо ведёт игроков в старые точки. ]]
function Q.CopyQuest(def, newID, asTemplate)
    if not istable(def) then return nil, {} end
    local out = table.Copy(def)

    newID = string.lower(trim(newID, 64)):gsub("[^%w_%-%:]", "_")
    if newID == "" then newID = tostring(def.id or "quest") .. "_copy" end
    out.id = newID
    out.title = tostring(def.title or "") .. (asTemplate and " (шаблон)" or " (копия)")

    --[[ Черновик: копия не должна сразу появиться у NPC и начать
         водить игроков по чужим координатам. ]]
    out.draft = true
    out.enabled = false

    -- Карта — та, где делают копию: координаты всё равно перепроверять.
    out.map = string.lower((game and game.GetMap and game.GetMap()) or "")

    --[[ ID достижения обязан быть свой, иначе ачивка второго квеста
         молча не выдастся: система считает её уже полученной. ]]
    if istable(out.achievement) and out.achievement.enabled then
        out.achievement.id = "quest_" .. newID
    end

    -- Раскладку графа сохраняем: она удобна и переносится без вреда.
    if asTemplate then
        for _, s in ipairs(istable(out.steps) and out.steps or {}) do
            -- Координаты чистим, тип и текст оставляем: структура полезна.
            s.min, s.max, s.pos = nil, nil, nil
        end
        out.cutscene = { accept = {}, complete = {} }
        out.npc = ""
        out.prerequisites = {}
    end

    local warnings = Q.CopyWarnings(def)
    out.copyNotes = warnings
    return out, warnings
end

function Q.Validate(def)
    local out = {}
    if not istable(def) then return out end

    local function add(level, text) out[#out + 1] = { level = level, text = text } end

    local steps = istable(def.steps) and def.steps or {}
    local dlg = istable(def.dialogue) and def.dialogue or {}
    local offer = istable(dlg.offer) and (dlg.offer.nodes or dlg.offer) or {}
    local rewards = istable(def.rewards) and def.rewards or {}
    local ach = istable(def.achievement) and def.achievement or {}

    if tostring(def.title or "") == "" then add("error", "Нет названия квеста.") end
    if #steps == 0 then
        add("error", "Нет ни одного этапа — квест сохранится черновиком и не появится у NPC.")
    end

    --[[ САМАЯ ЧАСТАЯ ЛОВУШКА. Квест выдаётся только действием accept в
         диалоге. Всё настроено, а взять нельзя — и непонятно почему. ]]
    local hasAccept = false
    for _, node in ipairs(offer) do
        for _, ch in ipairs(istable(node) and node.choices or {}) do
            if tostring(ch.action or "") == "accept" then hasAccept = true break end
        end
        if hasAccept then break end
    end
    if #offer == 0 then
        if not def.autoStart then
            add("error", "Нет диалога «До принятия» — игроку негде взять квест. Добавьте реплику и ответ с действием «Принять квест».")
        end
    elseif not hasAccept and not def.autoStart then
        add("error", "В диалоге «До принятия» нет ответа с действием «Принять квест» — взять квест невозможно.")
    end

    --[[ Чужая карта — это не опечатка, а гарантированно нерабочий
         квест: координаты зон и камер здесь ни на что не указывают. ]]
    --[[ Непроверенная копия — частая причина «квест ведёт не туда»:
         координаты остались от оригинала. Предупреждаем, но не ошибкой:
         автор мог осознанно оставить те же точки. ]]
    if istable(def.copyNotes) and #def.copyNotes > 0 then
        add("warn", ("Это копия: не подтверждено %d пункт(ов) проверки — координаты и ID могли остаться от оригинала."):format(#def.copyNotes))
    end

    local qmap = string.lower(tostring(def.map or ""))
    local nowMap = string.lower((game and game.GetMap and game.GetMap()) or "")
    if qmap ~= "" and nowMap ~= "" and qmap ~= nowMap then
        add("error", ("Квест создан для карты «%s», а сейчас «%s» — зоны и камеры не совпадут."):format(qmap, nowMap))
    end

    if tostring(def.npc or "") == "" and not def.autoStart then
        add("warn", "Не указан ID квестового NPC — квест некому выдавать.")
    end

    -- Награда: молчаливый ноль почти всегда означает «забыли заполнить».
    local money = math.floor(tonumber(rewards.money) or 0)
    local itemCount = 0
    for _ in pairs(istable(rewards.items) and rewards.items or {}) do itemCount = itemCount + 1 end
    if money <= 0 and itemCount == 0 and not (ach.enabled and (tonumber(ach.reward) or 0) > 0) then
        add("warn", "Награды нет совсем: ни денег, ни предметов, ни ачивки.")
    end

    if ach.enabled then
        if tostring(ach.name or "") == "" then add("warn", "Ачивка включена, но без названия.") end
        if tostring(ach.id or "") == "" then add("error", "Ачивка включена, но без ID.") end
    end

    -- Ссылки между репликами: висячий переход обрывает разговор молча.
    for phase, list in pairs(dlg) do
        local nodes = istable(list) and (list.nodes or list) or {}
        local byID = {}
        for _, n in ipairs(nodes) do byID[tostring(n.id or "")] = true end
        for _, n in ipairs(nodes) do
            local nx = tostring(n.next or "")
            if nx ~= "" and not byID[nx] then
                add("warn", ("Реплика «%s» (%s) ведёт на несуществующий ID «%s»."):format(
                    tostring(n.id or "?"), tostring(phase), nx))
            end
            for _, ch in ipairs(istable(n.choices) and n.choices or {}) do
                local cn = tostring(ch.next or "")
                if cn ~= "" and not byID[cn] then
                    add("warn", ("Ответ «%s» ведёт на несуществующий ID «%s»."):format(
                        tostring(ch.text or "?"), cn))
                end
                -- Действие с обязательным аргументом без аргумента молча не сработает.
                local act = tostring(ch.action or "")
                local needsArg = { set_flag = true, clear_flag = true, give_money = true,
                    give_item = true, emit = true }
                if needsArg[act] and tostring(ch.actionArg or "") == "" then
                    add("warn", ("Ответ «%s»: действие «%s» без аргумента — ничего не произойдёт."):format(
                        tostring(ch.text or "?"), act))
                end
            end
        end
    end

    -- Этапы: пустая цель у типовых ошибок настройки.
    for i, s in ipairs(steps) do
        local t = tostring(s.type or "")
        if t == "event" and tostring(s.event or "") == "" then
            add("error", ("Этап %d: тип «Событие», но само событие не указано."):format(i))
        end
        if t == "item" and tostring(s.item or "") == "" then
            add("error", ("Этап %d: тип «Иметь предмет», но предмет не указан."):format(i))
        end
        if t == "talk" and tostring(s.npc or "") == "" then
            add("warn", ("Этап %d: разговор с NPC, но ID NPC пуст."):format(i))
        end
        if t == "visit" and not istable(s.pos) and not istable(s.min) then
            add("error", ("Этап %d: «Посетить место» без заданной зоны — настройте её тулом."):format(i))
        end
    end

    return out
end

if SERVER then
    util.AddNetworkString("GRM_Quest_OpenNPC")
    util.AddNetworkString("GRM_Quest_PlayerOp")
    util.AddNetworkString("GRM_Quest_Sync")
    util.AddNetworkString("GRM_Quest_Notice")
    util.AddNetworkString("GRM_Quest_Cutscene")
    util.AddNetworkString("GRM_Quest_CutscenePreview")
    util.AddNetworkString("GRM_Quest_CutsceneStop")
    util.AddNetworkString("GRM_Quest_AdminOpen")
    util.AddNetworkString("GRM_Quest_AdminOp")
    util.AddNetworkString("GRM_Quest_Journal")
    util.AddNetworkString("GRM_Quest_Music")

    Q.DataDir = "grm_quests"
    Q.DefFile = Q.DataDir .. "/" .. string.lower(game.GetMap() or "unknown") .. ".json"
    Q.ProgressFile = Q.DataDir .. "/progress.json"

    local function ensureDir() if not file.IsDir(Q.DataDir, "DATA") then file.CreateDir(Q.DataDir) end end
    local function readJSON(path)
        if not file.Exists(path, "DATA") then return nil end
        local ok, parsed = pcall(util.JSONToTable, file.Read(path, "DATA") or "", false, true)
        return ok and istable(parsed) and parsed or nil
    end
    local function writeJSON(path, value)
        ensureDir()
        local ok, raw = pcall(util.TableToJSON, value, true)
        if not ok or not isstring(raw) or raw == "" then return false end
        local old = file.Exists(path, "DATA") and file.Read(path, "DATA") or nil
        if isstring(old) and old ~= "" then file.Write(path .. ".backup", old) end
        file.Write(path, raw)
        if file.Read(path, "DATA") ~= raw then return false end
        return istable(readJSON(path))
    end

    local function vectorData(value)
        if isvector(value) then return {x=value.x,y=value.y,z=value.z} end
        value = istable(value) and value or {}
        return {x=tonumber(value.x) or 0,y=tonumber(value.y) or 0,z=tonumber(value.z) or 0}
    end
    local function angleData(value)
        if isangle(value) then return {p=value.p,y=value.y,r=value.r} end
        value = istable(value) and value or {}
        return {p=tonumber(value.p) or 0,y=tonumber(value.y) or 0,r=tonumber(value.r) or 0}
    end
    local function vec(value) value=istable(value) and value or {};return Vector(tonumber(value.x)or 0,tonumber(value.y)or 0,tonumber(value.z)or 0) end
    local function ang(value) value=istable(value) and value or {};return Angle(tonumber(value.p)or 0,tonumber(value.y)or 0,tonumber(value.r)or 0) end

    local STEP_TYPES = {visit=true,event=true,talk=true,item=true}
    local function normalizeStep(step, index)
        step = istable(step) and step or {}
        local kind = trim(step.type, 24)
        if not STEP_TYPES[kind] then kind = "event" end
        local out = {
            type=kind,title=trim(step.title ~= "" and step.title or ("Этап "..index),100),
            description=trim(step.description,300),count=math.Clamp(math.floor(tonumber(step.count)or 1),1,100000),
            event=trim(step.event,64),target=trim(step.target,96),npc=trim(step.npc,64),item=trim(step.item,96),
            consume=step.consume==true,radius=math.Clamp(tonumber(step.radius)or 120,24,10000),
        }
        if step.min and step.max then out.min=vectorData(step.min);out.max=vectorData(step.max)
        elseif step.pos then out.pos=vectorData(step.pos) end
        --[[ Координаты блока на холсте редактора. Нормализация
             пересобирает таблицу по полям, поэтому без явного переноса
             раскладка стиралась при каждом сохранении и блоки прыгали
             в исходную сетку. ]]
        out._gx=math.Clamp(math.floor(tonumber(step._gx)or 0),0,20000)
        out._gy=math.Clamp(math.floor(tonumber(step._gy)or 0),0,20000)
        return out
    end
    --[[ ЧЕКПОИНТЫ КВЕСТА (заказ владельца 30.08).

         Точка на карте, до которой игрок должен дойти. В графе это блок
         ЧЕКПОИНТ, который можно связать линией с наградой, ачивкой,
         кат-сценой или следующим этапом.

         id обязателен и уникален: по нему граф находит связи, и по нему
         же прогресс помнит, что точка уже пройдена. Без него две точки
         слились бы в одну. ]]
    local function normalizeCheckpoints(list)
        local out,seen={},{}
        for index,rec in ipairs(istable(list) and list or {})do
            if #out>=32 then break end
            rec=istable(rec) and rec or {}
            local id=trim(rec.id,64)
            if id=="" then id="cp"..index end
            if not seen[id] then
                seen[id]=true
                out[#out+1]={
                    id=id,
                    label=trim(rec.label,64),
                    pos=vectorData(rec.pos),
                    radius=math.Clamp(math.floor(tonumber(rec.radius) or 96),16,2048),
                    -- Точка может как двигать этап, так и просто дёргать
                    -- связанные блоки: решает автор квеста.
                    advanceStep=rec.advanceStep==true,
                    once=rec.once~=false,
                    _gx=math.Clamp(math.floor(tonumber(rec._gx) or 0),0,20000),
                    _gy=math.Clamp(math.floor(tonumber(rec._gy) or 0),0,20000),
                }
            end
        end
        return out
    end
    local function normalizeCutscene(nodes)
        local out={}
        for index,node in ipairs(istable(nodes)and nodes or {})do
            if #out>=32 then break end
            local transition=node.transition=="cut"and"cut"or(node.transition=="move"and"move"or(index==1 and"cut"or"move"))
            out[#out+1]={id=trim(node.id and node.id~=""and node.id or("camera_"..index),64),next=trim(node.next,64),transition=transition,moveDuration=math.Clamp(tonumber(node.moveDuration)or 1,.05,30),pos=vectorData(node.pos),ang=angleData(node.ang),fov=math.Clamp(tonumber(node.fov)or 75,20,120),duration=math.Clamp(tonumber(node.duration)or 3,.25,30),caption=trim(node.caption,300),sound=trim(node.sound,160),image=trim(node.image,160),_gx=math.Clamp(math.floor(tonumber(node._gx)or 0),0,20000),_gy=math.Clamp(math.floor(tonumber(node._gy)or 0),0,20000)}
        end
        return out
    end
    local function normalizeDialoguePhase(value, phase)
        if isstring(value) then
            if value==""then return{}end
            return{{id=phase.."_1",speaker="",text=trim(value,1200),next="",choices={}}}
        end
        local source=istable(value)and(value.nodes or value)or{};local out={}
        for i,node in ipairs(source)do if#out>=64 then break end;node=istable(node)and node or{};local choices={};for _,choice in ipairs(istable(node.choices)and node.choices or{})do if#choices<8 then choices[#choices+1]={text=trim(choice.text,160),next=trim(choice.next,64),action=trim(choice.action,24),actionArg=trim(choice.actionArg,96),cond=trim(choice.cond,96)}end end;out[#out+1]={id=trim(node.id and node.id~=""and node.id or(phase.."_"..i),64),speaker=trim(node.speaker,80),text=trim(node.text,1200),next=trim(node.next,64),choices=choices,_gx=math.Clamp(math.floor(tonumber(node._gx)or 0),0,20000),_gy=math.Clamp(math.floor(tonumber(node._gy)or 0),0,20000)}end
        return out
    end
    local function normalizeDialogue(value)
        value=istable(value)and value or{}
        return{offer=normalizeDialoguePhase(value.offer,"offer"),active=normalizeDialoguePhase(value.active,"active"),complete=normalizeDialoguePhase(value.complete,"complete")}
    end
    local function normalizeNotification(value, defaultText, defaultBanner)
        value=istable(value)and value or{}
        return{enabled=value.enabled~=false,text=trim(value.text and value.text~=""and value.text or defaultText,300),sound=trim(value.sound,160),duration=math.Clamp(tonumber(value.duration)or 4,1,15),banner=value.banner==true or(defaultBanner==true and value.banner~=false)}
    end
    local function normalizeAchievement(value,questID,title,summary)
        value=istable(value)and value or{};local enabled=value.enabled==true;local id=string.lower(trim(value.id,64)):gsub("[^%w_%-%:]","_");if id==""then id="quest_"..questID end
        return{enabled=enabled,id=id,name=trim(value.name and value.name~=""and value.name or title,100),description=trim(value.description and value.description~=""and value.description or summary,300),reward=math.Clamp(math.floor(tonumber(value.reward)or 0),0,100000000),hidden=value.hidden==true}
    end
    --[[ БЛОК МУЗЫКИ (заказ владельца 28.08). Пустой путь означает
         «музыки нет»: возвращаем nil, чтобы не таскать мусор в файле
         квестов и не пытаться проиграть пустоту. ]]
    local function normalizeMusic(value)
        if not istable(value) then return nil end
        local sound=trim(value.sound,160)
        if sound=="" then return nil end
        local when=tostring(value.when or "start")
        if when~="start" and when~="step" and when~="complete" then when="start" end
        return {sound=sound,when=when,loop=value.loop==true,
            volume=math.Clamp(tonumber(value.volume)or 1,.1,1),
            _gx=math.Clamp(math.floor(tonumber(value._gx)or 0),0,20000),
            _gy=math.Clamp(math.floor(tonumber(value._gy)or 0),0,20000)}
    end
    --[[ РАСКЛАДКА СВЯЗЕЙ ГРАФА (заказ владельца 29.08).

         Нормализация пересобирает квест по полям, поэтому без явного
         переноса связи стирались при первом же сохранении — ровно как
         было с координатами блоков. Движок это поле не читает: оно
         нужно только редактору, чтобы нарисовать линии. ]]
    local function normalizeGraph(value)
        if not istable(value) then return nil end
        local out={links={}}
        for _,l in ipairs(istable(value.links)and value.links or{})do
            if #out.links>=256 then break end
            local from,to=trim(l.from,64),trim(l.to,64)
            if from~=""and to~=""then
                --[[ КОГДА СРАБАТЫВАЕТ СВЯЗЬ ОТ РЕПЛИКИ (жалоба владельца
                     29.08: «кат-сцена срабатывает ещё до момента пока не
                     прошёл диалог»).

                     По умолчанию эффект запускался в момент ПОКАЗА
                     реплики — ролик перекрывал ещё не прочитанный текст.
                     Теперь у связи есть режим:
                       now   — сразу, как реплика появилась (было раньше);
                       after — когда игрок закончит разговор.
                     Значение по умолчанию оставляем now: у существующих
                     квестов поведение не поменяется без ведома автора. ]]
                out.links[#out.links+1]={from=from,to=to,
                    port=math.Clamp(math.floor(tonumber(l.port)or 0),0,32),
                    when=(l.when=="after")and"after"or"now"}
            end
        end
        --[[ КООРДИНАТЫ КАРКАСНЫХ БЛОКОВ (СТАРТ и ФИНИШ).

             Жалоба владельца 30.08: «финиш всё ещё нельзя вынести в
             граф, не показывается».

             У всех остальных блоков позиция хранится в их собственных
             данных (_gx/_gy у реплики, камеры, награды). У СТАРТ и ФИНИШ
             своих данных в квесте нет вообще — им негде было храниться.
             Поэтому при каждом открытии редактор ставил их заново по
             умолчанию, и ФИНИШ уезжал за правый край холста: блок есть,
             а найти его нельзя.

             Держим их здесь, рядом со связями: это тоже раскладка
             редактора, движку она не нужна. ]]
        out.frame={}
        for _,name in ipairs({"start","finish"})do
            local rec=istable(value.frame) and value.frame[name] or nil
            if istable(rec) then
                out.frame[name]={
                    x=math.Clamp(math.floor(tonumber(rec.x) or 0),0,20000),
                    y=math.Clamp(math.floor(tonumber(rec.y) or 0),0,20000),
                }
            end
        end

        --[[ Раньше здесь стоял выход по пустому списку связей. Теперь
             граф хранит ещё и раскладку каркаса: у квеста без единой
             линии она всё равно должна пережить сохранение. ]]
        if #out.links==0 and not next(out.frame) then return nil end
        return out
    end
    --[[ Заметки копии живут в самом квесте: автор мог закрыть студию и
         вернуться завтра. Без сохранения предупреждение исчезло бы, а
         старые координаты остались. ]]
    local function normalizeCopyNotes(value)
        if not istable(value) then return nil end
        local out={}
        for _,n in ipairs(value)do
            if #out>=24 then break end
            local text=trim(istable(n) and n.text or n,300)
            if text~=""then
                out[#out+1]={text=text,level=(istable(n) and n.level=="check")and"check"or"must"}
            end
        end
        if #out==0 then return nil end
        return out
    end
    function Q.NormalizeDefinition(raw)
        raw=istable(raw)and raw or {}
        local id=string.lower(trim(raw.id,64)):gsub("[^%w_%-%:]","_")
        if id=="" then return nil,"ID обязателен"end
        local steps={};for i,step in ipairs(istable(raw.steps)and raw.steps or {})do if #steps<64 then steps[#steps+1]=normalizeStep(step,i)end end
        local draft=raw.draft==true or #steps==0
        local rewards={money=math.Clamp(math.floor(tonumber(raw.rewards and raw.rewards.money)or 0),0,100000000),items={}}
        for itemID,count in pairs(istable(raw.rewards and raw.rewards.items)and raw.rewards.items or {})do rewards.items[trim(itemID,96)]=math.Clamp(math.floor(tonumber(count)or 1),1,10000)end
        local prerequisites={};for _,v in ipairs(istable(raw.prerequisites)and raw.prerequisites or {})do prerequisites[#prerequisites+1]=trim(v,64)end
        local title,summary=trim(raw.title,100),trim(raw.summary,400);local notifications=istable(raw.notifications)and raw.notifications or{}
        --[[ КАРТА КВЕСТА (заказ владельца 29.08: «квесты должны
             запоминать конкретную карту, под которую создавались»).

             Файл определений и так свой у каждой карты, но внутри
             записи карта не хранилась. Из-за этого квест, перенесённый
             копированием файла или восстановленный из бэкапа, молча
             оказывался на чужой карте: зоны этапов и точки камер — это
             координаты, на другой карте они указывают в пустоту.

             Пустое значение = «карта не указана»: так открываются
             старые квесты, созданные до этой правки. ]]
        local questMap=string.lower(trim(raw.map,64))
        return {id=id,map=questMap,copyNotes=normalizeCopyNotes(raw.copyNotes),title=title,draft=draft,summary=summary,category=trim(raw.category,48),npc=trim(raw.npc,64),repeatable=raw.repeatable==true,autoStart=raw.autoStart==true,enabled=raw.enabled~=false,requireFaction=trim(raw.requireFaction,64),requireFlag=trim(raw.requireFlag,64),requireMoney=math.Clamp(math.floor(tonumber(raw.requireMoney)or 0),0,100000000),prerequisites=prerequisites,steps=steps,rewards=rewards,achievement=normalizeAchievement(raw.achievement,id,title,summary),notifications={start=normalizeNotification(notifications.start,"Получен квест: {title}",false),step=normalizeNotification(notifications.step,"Этап выполнен: {step}",false),complete=normalizeNotification(notifications.complete,"Квест завершён: {title}",true)},dialogue=normalizeDialogue(raw.dialogue),music=normalizeMusic(raw.music),graph=normalizeGraph(raw.graph),checkpoints=normalizeCheckpoints(raw.checkpoints),cutscene={accept=normalizeCutscene(raw.cutscene and raw.cutscene.accept),complete=normalizeCutscene(raw.cutscene and raw.cutscene.complete),acceptAfterDialogue=raw.cutscene and raw.cutscene.acceptAfterDialogue==true,completeAfterDialogue=raw.cutscene and raw.cutscene.completeAfterDialogue==true}}
    end

    function Q.SaveDefinitions()
        local records={};for _,def in pairs(Q.Definitions)do records[#records+1]=def end;table.sort(records,function(a,b)return a.id<b.id end)
        local npcs={};for _,ent in ipairs(ents.FindByClass("grm_quest_npc"))do if IsValid(ent)then npcs[#npcs+1]={id=ent:GetQuestNPCID(),name=ent:GetQuestNPCName(),model=ent:GetModel(),pos=vectorData(ent:GetPos()),ang=angleData(ent:GetAngles())}end end
        return writeJSON(Q.DefFile,{version=1,map=game.GetMap(),quests=records,npcs=npcs})
    end
    function Q.SaveProgressNow()
        local records={};for key,quests in pairs(Q.Progress)do records[#records+1]={key=key,quests=quests}end
        return writeJSON(Q.ProgressFile,{version=1,records=records})
    end
    function Q.SaveProgress()
        if GRM.Perf and GRM.Perf.Coalesce then
            return GRM.Perf.Coalesce("quests.progress", 1.5, Q.SaveProgressNow)
        end
        return Q.SaveProgressNow()
    end
    function Q.LoadData()
        Q.Definitions={};local defs=readJSON(Q.DefFile)or {}
        for _,raw in pairs(defs.quests or {})do local def=Q.NormalizeDefinition(raw);if def then Q.Definitions[def.id]=def end end
        Q.Progress={};local progress=readJSON(Q.ProgressFile)or {}
        for _,record in pairs(progress.records or {})do if istable(record)and isstring(record.key)then Q.Progress[record.key]=istable(record.quests)and record.quests or {}end end
        Q._NPCRecords=istable(defs.npcs)and defs.npcs or {}
        return true
    end
    Q.LoadData()
    function Q.RegisterAchievements()
        if not(GRM.Ach and GRM.Ach.Register)then return 0 end;local count=0
        for _,def in pairs(Q.Definitions)do local a=def.achievement;if a and a.enabled then GRM.Ach.Register({id=a.id,name=a.name,desc=a.description,metric="quest:"..def.id,goal=1,reward=a.reward,hidden=a.hidden,questID=def.id});count=count+1 end end
        return count
    end
    timer.Create("GRM_Quest_AchievementBridge",1,0,function()if GRM.Ach and GRM.Ach.Register then Q.RegisterAchievements();timer.Remove("GRM_Quest_AchievementBridge")end end)

    local function progressFor(ply)
        local key=characterKey(ply);Q.Progress[key]=Q.Progress[key]or {};return Q.Progress[key],key
    end
    function Q.GetProgress(ply,questID)local all=progressFor(ply);return all[tostring(questID or "")]end
    local sync
    function Q.ResetProgress(questID,targetKey)
        questID=trim(questID,64);targetKey=targetKey and tostring(targetKey)or nil;local removed,removedKeys=0,{}
        if targetKey and targetKey~=""and targetKey~="*"then local quests=Q.Progress[targetKey];if quests and quests[questID]then quests[questID]=nil;removed=1;removedKeys[1]=targetKey end
        else for key,quests in pairs(Q.Progress)do if quests[questID]then quests[questID]=nil;removed=removed+1;removedKeys[#removedKeys+1]=key end end end
        local achievement=Q.Definitions[questID]and Q.Definitions[questID].achievement;if achievement and achievement.enabled and GRM.Ach and GRM.Ach.ResetUnlock then for _,key in ipairs(removedKeys)do GRM.Ach.ResetUnlock(key,achievement.id,true)end;if GRM.Ach.SaveNow then GRM.Ach.SaveNow("quest progress reset")end end
        Q.SaveProgress();for _,online in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll())do if IsValid(online)and(not targetKey or targetKey=="*"or characterKey(online)==targetKey)then sync(online)end end
        hook.Run("GRM_QuestProgressReset",questID,targetKey,removed);return removed
    end
    --[[ Подходит ли квест текущей карте.

         Зоны этапов и точки камер — это координаты. На другой карте они
         указывают в пустоту: игрок получит цель, до которой невозможно
         дойти, а кат-сцена снимет стену.

         Квест без метки считаем совместимым: иначе после обновления
         все существующие квесты разом перестали бы выдаваться. ]]
    function Q.FitsMap(def)
        if not istable(def) then return false end
        local m=string.lower(trim(def.map,64))
        if m=="" then return true end
        return m==string.lower(game.GetMap() or "")
    end

    local function canStart(ply,def)
        if not def or not def.enabled then return false,"Квест отключён"end
        if not Q.FitsMap(def) then
            return false,"Квест создан для карты "..tostring(def.map).." и здесь не работает"
        end
        if def.draft or #(def.steps or{})==0 then return false,"Квест пока является черновиком"end
        local all=progressFor(ply);local old=all[def.id]
        if old and old.status=="active"then return false,"Квест уже выполняется"end
        if old and old.status=="completed"and not def.repeatable then return false,"Квест уже завершён"end
        for _,id in ipairs(def.prerequisites or {})do if not all[id]or all[id].status~="completed"then return false,"Не выполнено условие: "..id end end
        if tostring(def.requireFaction or "")~="" and string.lower(ply:GetNWString("GRM_Faction","")or"")~=string.lower(def.requireFaction)then return false,"Нужна фракция: "..def.requireFaction end
        if tostring(def.requireFlag or "")~="" and not(Q.GetFlag and Q.GetFlag(ply,def.requireFlag))then return false,"Нужен флаг: "..def.requireFlag end
        if (tonumber(def.requireMoney)or 0)>0 then
            local have=(GRM.GetBalance and GRM.GetBalance(ply)or 0)+((GRM.Economy and GRM.Economy.BankBalance)and GRM.Economy.BankBalance(ply)or 0)
            if have<(tonumber(def.requireMoney)or 0)then return false,"Недостаточно денег" end
        end
        return true
    end
    sync=function(ply)
        if not IsValid(ply)then return end
        --[[ Показываем только квесты ТЕКУЩЕЙ карты.

             Прогресс общий на весь сервер, а определения свои у каждой
             карты. Квест другой карты и так не попадал в журнал (его
             определения тут нет), но если карты делят имя квеста, в
             журнал лез бы чужой — с целями, до которых не дойти.

             Прогресс при этом НЕ трогаем: вернётся игрок на ту карту —
             продолжит с того же места. ]]
        local all=progressFor(ply);local defs={};for id,p in pairs(all)do local d=Q.Definitions[id];if d and Q.FitsMap(d) then defs[#defs+1]={definition=d,progress=p}end end
        net.Start("GRM_Quest_Sync")net.WriteTable(defs)net.Send(ply)
    end
    Q.Sync=sync
    local function notice(ply,ok,text,opts)opts=istable(opts)and opts or{};net.Start("GRM_Quest_Notice")net.WriteBool(ok)net.WriteString(trim(text,300))net.WriteString(trim(opts.sound,160))net.WriteFloat(math.Clamp(tonumber(opts.duration)or 4,1,15))net.WriteBool(opts.banner==true)net.WriteString(trim(opts.heading,80))net.Send(ply)end
    --[[ ВОСПРОИЗВЕДЕНИЕ МУЗЫКИ БЛОКА (заказ владельца 28.08).

         Блок МУЗЫКА хранит момент: start / step / complete. Здесь мы
         сверяем момент и шлём команду клиенту. Зациклённый трек
         останавливаем при завершении квеста, иначе он играл бы вечно. ]]
    local function questMusic(ply,kind,def)
        local m=def and def.music
        if not (IsValid(ply) and istable(m)) then return end
        if tostring(m.when or "start")~=kind then
            -- Конец квеста глушит зациклённый трек, даже если он не отсюда.
            if kind=="complete" and m.loop then
                net.Start("GRM_Quest_Music")net.WriteString("")net.WriteFloat(0)net.WriteBool(false)net.Send(ply)
            end
            return
        end
        net.Start("GRM_Quest_Music")
            net.WriteString(trim(m.sound,160))
            net.WriteFloat(math.Clamp(tonumber(m.volume)or 1,.1,1))
            net.WriteBool(m.loop==true)
        net.Send(ply)
    end
    Q.PlayQuestMusic=questMusic

    local function questNotice(ply,kind,def,step)
        local cfg=def.notifications and def.notifications[kind];if cfg and cfg.enabled==false then return end;cfg=cfg or{};local text=tostring(cfg.text or"");text=text:gsub("{title}",tostring(def.title or"")):gsub("{step}",tostring(step and step.title or"")):gsub("{count}",tostring(step and step.count or""));notice(ply,true,text,{sound=cfg.sound,duration=cfg.duration,banner=cfg.banner,heading=({start="НОВОЕ ЗАДАНИЕ",step="ЭТАП ВЫПОЛНЕН",complete="ЗАДАНИЕ ЗАВЕРШЕНО"})[kind]})
    end
    local function startCutscenePVS(ply,nodes)
        if not IsValid(ply)then return end;local duration=0;for _,node in ipairs(nodes or{})do duration=duration+math.Clamp(tonumber(node.duration)or 3,.05,30)+(node.transition=="move"and math.Clamp(tonumber(node.moveDuration)or 1,.05,30)or 0)end
        ply.GRMQuestCutscenePVS={nodes=table.Copy(nodes or{}),expires=CurTime()+duration+8}
    end
    --[[ ЕДИНСТВЕННАЯ ТОЧКА ПОКАЗА РОЛИКА — И ЕДИНСТВЕННОЕ МЕСТО ГЕЙТА.

         Владелец дважды сообщал, что ролик лезет поверх открытого
         диалога. Обе прошлые попытки закрывали по ОДНОМУ пути:

           1) пометка на связи графа — мимо: ролик «при принятии» идёт из
              Q.Start и графа не касается;
           2) флаг в Q.Start — мимо: у владельца ролик висит на ЛИНИИ от
              блока, его зовёт runEffect, минуя Q.Start.

         Путей запуска несколько (Q.Start, финал квеста, граф от реплики,
         граф от этапа), и латать каждый — гарантия промахнуться снова.
         Поэтому проверка стоит ЗДЕСЬ: через эту функцию проходят все.

         Правило: идёт разговор и у ролика включено «ждать конца
         диалога» — откладываем. Разговора нет — показываем сразу, иначе
         ролик от этапа посреди города повис бы в очереди до следующей
         болтовни с NPC. ]]
    local function cutsceneNow(ply,nodes)
        if not IsValid(ply) or #(nodes or {})==0 then return end
        startCutscenePVS(ply,nodes)
        net.Start("GRM_Quest_Cutscene")net.WriteTable(nodes)net.Send(ply)
    end
    Q._CutsceneNow = cutsceneNow

    local function cutscene(ply,nodes,afterDialogue,tag)
        if not IsValid(ply) or #(nodes or {})==0 then return end
        if afterDialogue and istable(ply.GRMQuestDlg) then
            Q.QueueCutscene(ply,nodes,tag)
            return
        end
        cutsceneNow(ply,nodes)
    end

    --[[ ОЧЕРЕДЬ РОЛИКОВ: «сыграть, когда закончится разговор».

         ЗАЧЕМ. Ролик «При принятии» запускался прямо из Q.Start, а
         Q.Start зовут из ответа «Принять квест» — то есть ещё внутри
         диалога. Игрок видел титр кат-сцены поверх открытого окна с
         репликой «1 / 2» (скриншот владельца 29.08).

         Прошлая попытка чинить это пометкой на СВЯЗИ графа не помогала:
         путь Q.Start -> cutscene() графа не касается вовсе. Поэтому
         момент запуска теперь свойство САМОГО РОЛИКА, а здесь — простой
         буфер на игрока.

         Держим ОДИН отложенный ролик: если за разговор накопилось бы
         несколько, показывать их подряд поверх друг друга бессмысленно —
         выигрывает последний назначенный. ]]
    Q.PendingCutscene = Q.PendingCutscene or {}

    --- Отложить ролик до конца разговора. true, если действительно отложен.
    function Q.QueueCutscene(ply,nodes,tag)
        if not IsValid(ply) then return false end
        if #(nodes or {})==0 then return false end
        Q.PendingCutscene[ply]={nodes=table.Copy(nodes),tag=tostring(tag or "")}
        return true
    end

    --- Выпустить отложенный ролик. Зовётся из ВСЕХ точек выхода диалога.
    function Q.FlushCutscene(ply)
        if not IsValid(ply) then return false end
        local rec=Q.PendingCutscene[ply]
        if not istable(rec) then return false end
        -- Снимаем ДО показа: иначе повторный выход из разговора
        -- проиграет тот же ролик второй раз.
        Q.PendingCutscene[ply]=nil
        -- Показ БЕЗ гейта: разговор уже закончен, второй раз откладывать
        -- некуда — иначе ролик заперся бы в очереди навсегда.
        cutsceneNow(ply,rec.nodes)
        return true
    end

    --- Игрок ушёл — буфер не держим.
    hook.Add("PlayerDisconnected","GRM_Quest_PendingCutsceneDrop",function(ply)
        Q.PendingCutscene[ply]=nil
    end)

    net.Receive("GRM_Quest_CutscenePreview",function(_,ply)
        if not IsValid(ply)or not ply:IsSuperAdmin()then return end;local nodes=normalizeCutscene(net.ReadTable()or{});if#nodes>0 then startCutscenePVS(ply,nodes)end
    end)
    net.Receive("GRM_Quest_CutsceneStop",function(_,ply)if IsValid(ply)then ply.GRMQuestCutscenePVS=nil end end)
    hook.Add("SetupPlayerVisibility","GRM_Quest_CutscenePVS",function(ply)
        local state=IsValid(ply)and ply.GRMQuestCutscenePVS;if not state then return end;if CurTime()>(state.expires or 0)then ply.GRMQuestCutscenePVS=nil return end
        for i,node in ipairs(state.nodes or{})do if i>32 then break end;if node.pos then AddOriginToPVS(vec(node.pos))end end
    end)
    hook.Add("PlayerDeath","GRM_Quest_CutscenePVSDeath",function(ply)ply.GRMQuestCutscenePVS=nil end)
    hook.Add("PlayerDisconnected","GRM_Quest_CutscenePVSLeave",function(ply)ply.GRMQuestCutscenePVS=nil end)

    local function itemCount(ply,itemID)
        if GRM.Inventory and GRM.Inventory.CountItem then return tonumber(GRM.Inventory.CountItem(ply,itemID))or 0 end
        return 0
    end
    local function reward(ply,def)
        local r=def.rewards or {};if(r.money or 0)>0 and GRM.GiveMoney then GRM.GiveMoney(ply,r.money,"Квест: "..def.title)end
        for itemID,count in pairs(r.items or {})do if GRM.Inventory and GRM.Inventory.AddItem then GRM.Inventory.AddItem(ply,itemID,count)end end
    end
    local function unlockQuestAchievement(ply,def)
        local a=def.achievement;if not(a and a.enabled and GRM.Ach and GRM.Ach.Register and GRM.Ach.Unlock and GRM.Ach.RecOf)then return end
        GRM.Ach.Register({id=a.id,name=a.name,desc=a.description,metric="quest:"..def.id,goal=1,reward=a.reward,hidden=a.hidden,questID=def.id});GRM.Ach.Unlock(ply,GRM.Ach.Defs[a.id],GRM.Ach.RecOf(ply))
    end
    --[[--------------------------------------------------------------
        ГРАФ УПРАВЛЯЕТ КВЕСТОМ (заказ владельца 29.08:
        «делай чтобы линия управляла связями, чтобы графы не были
         бесполезными»).

        Было: связи в редакторе — просто картинка. Ролик играл по своей
        фазе, награда выдавалась в конце, музыка по выбранному моменту.
        Протянутая линия ни на что не влияла.

        Стало: блоки делятся на ДВА вида.

          ТРИГГЕРЫ — то, что происходит в игре:
             start           принятие квеста
             <id реплики>    игрок дошёл до этой реплики
             step_<N>        закрыт N-й этап
             finish          квест завершён

          ЭФФЕКТЫ — то, что запускается по линии:
             cut_accept / cut_complete   ролик
             music                        звук
             reward                       деньги и предметы
             achieve                      достижение

        Когда срабатывает триггер, идём по его связям и выполняем
        подключённые эффекты. Цепочки поддерживаются: эффект тоже может
        вести к следующему эффекту.

        ВАЖНО ПРО ДВОЙНОЙ ЗАПУСК. Если ролик подключён линией, он НЕ
        должен вдобавок играть по своей фазе — иначе зритель увидит его
        дважды. Поэтому эффект, у которого есть входящая связь,
        считается «управляемым графом» и из штатных точек пропускается.
    ----------------------------------------------------------------]]
    --[[ finish тоже эффект: линия «этап → ФИНИШ» обязана завершать квест.
         Раньше finish был ТОЛЬКО именем триггера, от которого расходятся
         связи в конце квеста, а целью связи быть не мог — владелец
         соединял блоки, линия рисовалась и сохранялась, но не делала
         ничего («не срабатывает блок финиша»). ]]
    local EFFECT_UIDS = {cut_accept=true,cut_complete=true,music=true,reward=true,achieve=true,finish=true}

    --- Есть ли у эффекта входящая связь: значит им управляет граф.
    function Q.GraphDrives(def,uid)
        if not (istable(def) and istable(def.graph) and istable(def.graph.links)) then return false end
        uid=tostring(uid or "")
        for _,l in ipairs(def.graph.links)do
            if tostring(l.to or "")==uid then return true end
        end
        return false
    end

    --[[ Куда ведут связи от блока.

         mode фильтрует по моменту запуска:
           nil     — все связи (для эффектов внутри цепочки);
           "now"   — только те, что срабатывают сразу;
           "after" — только отложенные до конца разговора. ]]
    --[[ port — НОМЕР ОТВЕТА ИГРОКА, от которого идёт линия.

         0 (или поля нет) — связь самой реплики: срабатывает при показе.
         N               — связь N-го варианта ответа: срабатывает,
                           только если игрок выбрал именно его.

         Заказ владельца 29.08: «там два варианта ответа, и нужно ставить,
         на какой вариант делать запуск кат-сцены, чтобы не просто ткнул
         1-й ответ — кат-сцена, ткнул 2-й — кат-сцена».

         Порты в студии были и раньше, port доезжал до сервера, но здесь
         не читался — поэтому срабатывали ВСЕ связи реплики сразу,
         независимо от выбора.

         Аргумент port:
           nil — берём только общие связи (port 0). Так зовут показ
                 реплики и не-диалоговые триггеры;
           N   — берём ТОЛЬКО связи N-го ответа, общие не трогаем: они
                 уже отработали при показе, второй раз не нужно. ]]
    local function graphTargets(def,uid,mode,port)
        local out={}
        if not (istable(def) and istable(def.graph) and istable(def.graph.links)) then return out end
        uid=tostring(uid or "")
        for _,l in ipairs(def.graph.links)do
            if tostring(l.from or "")==uid then
                local w=(l.when=="after")and"after"or"now"
                local lp=math.floor(tonumber(l.port)or 0)
                local matchMode=(not mode)or w==mode
                local matchPort=(port==nil and lp==0)or(port~=nil and lp==port)
                if matchMode and matchPort then out[#out+1]=tostring(l.to or "") end
            end
        end
        return out
    end

    --[[ Выполнить ОДИН блок-эффект. Возвращает true, если это был
         эффект: по нему решаем, идти ли дальше по цепочке. ]]
    local function runEffect(ply,def,uid,p)
        --[[ Ролик по ЛИНИИ ГРАФА — тот самый случай владельца. Флаг
             «ждать конца диалога» берём с самого ролика: линия может
             идти от реплики, и показывать поверх неё нельзя. ]]
        if uid=="cut_accept" then
            cutscene(ply,def.cutscene and def.cutscene.accept,
                def.cutscene and def.cutscene.acceptAfterDialogue,"accept")
            return true
        end
        if uid=="cut_complete" then
            cutscene(ply,def.cutscene and def.cutscene.complete,
                def.cutscene and def.cutscene.completeAfterDialogue,"complete")
            return true
        end
        if uid=="music" then
            local m=def.music
            if istable(m) then
                net.Start("GRM_Quest_Music")
                    net.WriteString(trim(m.sound,160))
                    net.WriteFloat(math.Clamp(tonumber(m.volume)or 1,.1,1))
                    net.WriteBool(m.loop==true)
                net.Send(ply)
            end
            return true
        end
        if uid=="reward" then reward(ply,def) return true end
        if uid=="achieve" then unlockQuestAchievement(ply,def) return true end
        --[[ ФИНИШ КАК ЦЕЛЬ СВЯЗИ. Автор ведёт линию «этап → ФИНИШ» и
             ожидает, что квест на этом закончится. Завершаем через
             Q.ForceFinish: там же снимается защита от повторного вызова,
             иначе связь от финиша к финишу зациклила бы завершение. ]]
        if uid=="finish" then
            if Q.ForceFinish then Q.ForceFinish(ply,def,p) end
            return true
        end
        return false
    end

    --[[ Пройти по связям от триггера и выполнить эффекты.

         Защита от зацикливания обязательна: автор может свести линии в
         кольцо, и без пометки посещённых сервер уйдёт в бесконечный
         цикл, повесив карту. ]]
    --[[ mode: "now" / "after" / nil.

         nil означает «запустить ВСЁ, независимо от пометки». Так зовут
         не-диалоговые триггеры: этап, старт, финиш. У них нет разговора,
         который надо дождаться, и если бы они уважали пометку «после
         диалога», связь от этапа не сработала бы НИКОГДА — эффект
         молча пропал бы. Фильтр применяют только реплики. ]]
    function Q.RunGraphFrom(ply,def,fromUID,p,mode,port)
        if not (IsValid(ply) and istable(def)) then return 0 end
        local seen,queue,fired={},{tostring(fromUID or "")},0
        local guard=0
        local first=true
        while #queue>0 do
            guard=guard+1;if guard>64 then break end
            local cur=table.remove(queue,1)
            --[[ Режим и порт касаются только связей ОТ ТРИГГЕРА. Внутри
                 цепочки эффектов фильтр не нужен: раз цепочка уже
                 запущена, она отрабатывает целиком. ]]
            local useMode=first and mode or nil
            local usePort=first and port or nil
            first=false
            for _,nxt in ipairs(graphTargets(def,cur,useMode,usePort))do
                if not seen[nxt] then
                    seen[nxt]=true
                    --[[ ЦЕПОЧКА ИДЁТ ТОЛЬКО ПО ЭФФЕКТАМ (жалоба владельца
                         31.08: «квест после диалога сразу же принимается и
                         завершается», «неверно идёт срабатывание некоторых
                         связей»).

                         Раньше в очередь клался ЛЮБОЙ блок, к которому
                         ведёт линия, — в том числе реплика, этап и
                         чекпоинт. Обход тут же брал их собственные связи
                         и шёл дальше. Одна линия «реплика → следующая
                         реплика» превращала вызов в пробег по всему
                         графу: срабатывали награда, ачивка и ФИНИШ,
                         подключённые в самом конце цепочки. Квест
                         завершался в тот же миг, когда игрок дочитал
                         первую фразу.

                         Эффект — это разовое действие (ролик, музыка,
                         награда, ачивка, финиш), и продолжать цепочку
                         имеет смысл только через него. Реплика, этап и
                         чекпоинт — это ТОЧКИ ОЖИДАНИЯ: они запускаются
                         своим событием (игрок дошёл, выбрал ответ, сдал
                         предмет), а не обходом графа. ]]
                    if runEffect(ply,def,nxt,p) then
                        fired=fired+1
                        -- Цепочка: эффект может вести к следующему эффекту.
                        queue[#queue+1]=nxt
                    end
                end
            end
        end
        return fired
    end

    local function finishQuest(ply,def,p)
        --[[ ЗАЩИТА ОТ ПОВТОРНОГО ЗАВЕРШЕНИЯ.

             Квест может прийти сюда двумя путями сразу: обычным (кончились
             этапы) и по линии «этап → ФИНИШ» из графа. Без этой проверки
             награда выдалась бы дважды, а связь «финиш → финиш»
             зациклила бы завершение. ]]
        if not istable(p) or p.status=="completed" then return end
        p.status="completed";p.completedAt=os.time()
        --[[ Блоки, подключённые линией, запускает граф — здесь их
             пропускаем, иначе награда выдастся дважды, а ролик
             проиграется два раза подряд. ]]
        if not Q.GraphDrives(def,"reward") then reward(ply,def) end
        if not Q.GraphDrives(def,"achieve") then unlockQuestAchievement(ply,def) end
        questNotice(ply,"complete",def)
        if not Q.GraphDrives(def,"music") then questMusic(ply,"complete",def) end
        if not Q.GraphDrives(def,"cut_complete") then
            cutscene(ply,def.cutscene.complete,def.cutscene.completeAfterDialogue,"complete")
        end
        -- Триггер «finish»: запускаем всё, что подключено к нему линиями.
        Q.RunGraphFrom(ply,def,"finish",p)
        hook.Run("GRM_QuestCompleted",ply,def.id);Q.SaveProgress();sync(ply)
    end
    --[[ Завершение квеста ПО ЛИНИИ ГРАФА (блок ФИНИШ как цель связи).

         Отдельная точка входа нужна, потому что finishQuest локальная, а
         зовёт её runEffect, объявленный выше по файлу. Прогресс берём из
         текущего, если его не передали: связь может прийти из места, где
         таблицы прогресса под рукой нет. ]]
    function Q.ForceFinish(ply,def,p)
        if not (IsValid(ply) and istable(def)) then return false end
        if not istable(p) then
            local all=progressFor(ply)
            p=all and all[def.id]
        end
        if not istable(p) or p.status=="completed" then return false end
        finishQuest(ply,def,p)
        return true
    end

    --[[--------------------------------------------------------------
        ЧЕКПОИНТЫ: ДОСТИЖЕНИЕ ТОЧКИ НА КАРТЕ

        Заказ владельца 30.08: маркер, который можно связать с выплатой
        или ачивкой. Логика намеренно простая — точка сама ничего не
        решает, она лишь ДЁРГАЕТ ГРАФ. Что произойдёт дальше (награда,
        ачивка, ролик, следующий этап), задаёт автор квеста линиями.

        UID блока в графе — "cp_<id>": так связь от конкретной точки не
        путается со связями других точек того же квеста.
    ----------------------------------------------------------------]]
    --[[ checkCurrent объявлена ниже по файлу, а нужна нам здесь. Прямое
         обращение по имени скомпилировалось бы как чтение ГЛОБАЛА и
         вернуло nil — тот самый класс багов, что чинили стендом
         sim_global_hygiene. Держим явную ссылку. ]]
    local checkCurrentRef

    function Q.CheckpointUID(cpID) return "cp_"..tostring(cpID or "") end

    --- Дошёл ли игрок до этой точки в текущем прохождении.
    function Q.CheckpointDone(p,cpID)
        return istable(p) and istable(p.checkpoints) and p.checkpoints[tostring(cpID or "")]==true
    end

    --[[ ЕДИНОЕ ПРАВИЛО ВИДИМОСТИ ЧЕКПОИНТА.

         Заказ владельца 30.08: «надо чтобы было видно только тем, кто
         взял квест, чтобы любой рандом не забрал награду чужого».

         Одна функция на два вопроса — «показывать ли маркер» и «пускать
         ли к срабатыванию». Если развести их по разным местам, они
         рано или поздно разойдутся: игрок видит точку, а она не
         работает (или наоборот).

         Живёт на сервере: он и прячет энтити по сети, и решает выдачу
         награды. Клиент дублирует то же правило по своему прогрессу —
         но клиентская проверка это удобство, а НЕ защита. ]]
    function Q.CheckpointVisibleFor(ply,questID,cpID)
        if not IsValid(ply) then return false end
        local def=Q.Definitions[tostring(questID or "")]
        if not (istable(def) and istable(def.checkpoints)) then return false end
        cpID=tostring(cpID or "")

        local rec
        for _,c in ipairs(def.checkpoints) do if c.id==cpID then rec=c break end end
        if not rec then return false end

        local all=progressFor(ply)
        local p=all and all[def.id]
        if not (istable(p) and p.status=="active") then return false end

        -- Пройденную одноразовую точку прятать: она больше не сработает.
        if rec.once~=false and istable(p.checkpoints) and p.checkpoints[cpID] then return false end
        return true
    end

    function Q.ReachCheckpoint(ply,questID,cpID,ent)
        if not IsValid(ply) then return false end
        local def=Q.Definitions[tostring(questID or "")]
        if not (istable(def) and istable(def.checkpoints)) then return false end
        cpID=tostring(cpID or "")

        local rec
        for _,c in ipairs(def.checkpoints) do if c.id==cpID then rec=c break end end
        if not rec then return false end

        -- Точка работает только во время квеста: иначе прохожий дёргал бы
        -- награду просто гуляя по карте.
        local all=progressFor(ply)
        local p=all and all[def.id]
        if not (istable(p) and p.status=="active") then return false end

        p.checkpoints=istable(p.checkpoints) and p.checkpoints or {}
        if rec.once~=false and p.checkpoints[cpID] then return false end
        p.checkpoints[cpID]=true

        --[[ Общий флаг на энтити НЕ ставим: сетевая переменная одна на
             всех, и первый прошедший спрятал бы маркер остальным. Факт
             прохождения уже записан в ЛИЧНЫЙ прогресс выше — клиент
             читает его оттуда. ]]
        questNotice(ply,"step",def,{title=rec.label~="" and rec.label or "Точка достигнута"})

        --[[ Главное: запускаем всё, что автор подключил линией к этой
             точке. Режим nil — «выполнить всё»: у чекпоинта нет диалога,
             которого стоило бы дожидаться. ]]
        Q.RunGraphFrom(ply,def,Q.CheckpointUID(cpID),p)

        --[[ Если автор пометил точку как «двигает этап», засчитываем шаг.
             По умолчанию НЕ двигаем: чаще чекпоинт — это просто выплата
             по дороге, а не цель этапа. ]]
        if rec.advanceStep then
            p.step=(tonumber(p.step) or 1)+1
            p.count=0
            checkCurrentRef(ply,def,p)
        end

        Q.SaveProgress();sync(ply)
        -- Точка пройдена: у одноразовой маркер должен исчезнуть сразу.
        if Q.RefreshCheckpointVisibility then Q.RefreshCheckpointVisibility() end
        hook.Run("GRM_QuestCheckpoint",ply,def.id,cpID)
        return true
    end

    local function checkCurrent(ply,def,p)
        local step=def.steps[p.step or 1];if not step then finishQuest(ply,def,p)return end
        if step.type=="item"then p.count=itemCount(ply,step.item);if p.count>=step.count then if step.consume and GRM.Inventory and GRM.Inventory.RemoveItem then GRM.Inventory.RemoveItem(ply,step.item,step.count)end;p.step=p.step+1;p.count=0;questNotice(ply,"step",def,step);if not Q.GraphDrives(def,"music") then questMusic(ply,"step",def) end;Q.RunGraphFrom(ply,def,"step_"..tostring((tonumber(p.step) or 1)-1),p);checkCurrent(ply,def,p)end end
    end
    -- Ссылка для Q.ReachCheckpoint, объявленной выше по файлу.
    checkCurrentRef=checkCurrent

    function Q.Start(ply,questID)
        local def=Q.Definitions[tostring(questID or "")];local ok,why=canStart(ply,def);if not ok then return false,why end
        local all=progressFor(ply);all[def.id]={status="active",step=1,count=0,startedAt=os.time()};questNotice(ply,"start",def)
        if not Q.GraphDrives(def,"music") then questMusic(ply,"start",def) end
        --[[ Ролик принятия: если автор попросил «после диалога», не
             показываем сразу — игрок ещё читает реплику. Выпустит
             Q.FlushCutscene, когда разговор закончится. ]]
        if not Q.GraphDrives(def,"cut_accept") then
            cutscene(ply,def.cutscene.accept,def.cutscene.acceptAfterDialogue,"accept")
        end
        -- Триггер «start»: линии от блока СТАРТ.
        Q.RunGraphFrom(ply,def,"start",all[def.id])
        checkCurrent(ply,def,all[def.id]);Q.SaveProgress();sync(ply)
        -- Квест взят: показываем его точки владельцу без задержки.
        if Q.RefreshCheckpointVisibility then Q.RefreshCheckpointVisibility() end
        hook.Run("GRM_QuestStarted",ply,def.id);return true
    end
    function Q.Event(ply,eventName,target,amount,meta)
        if not IsValid(ply)then return end;eventName=trim(eventName,64);target=trim(target,96);amount=math.max(1,math.floor(tonumber(amount)or 1));local all=progressFor(ply)
        for id,p in pairs(all)do local def=Q.Definitions[id];if def and def.enabled and not def.draft and Q.FitsMap(def) and p.status=="active"then local step=def.steps[p.step or 1];local match=step and step.type=="event"and step.event==eventName and(step.target==""or step.target==target);if match then p.count=math.min(step.count,(tonumber(p.count)or 0)+amount);if p.count>=step.count then p.step=p.step+1;p.count=0;questNotice(ply,"step",def,step);if not Q.GraphDrives(def,"music") then questMusic(ply,"step",def) end;Q.RunGraphFrom(ply,def,"step_"..tostring((tonumber(p.step) or 1)-1),p);checkCurrent(ply,def,p)end end end end
        Q.SaveProgress();sync(ply)
    end
    function Q.Talk(ply,npcID)
        local all=progressFor(ply);for id,p in pairs(all)do local def=Q.Definitions[id];local step=def and def.steps[p.step or 1];if def and def.enabled and not def.draft and p.status=="active"and step and step.type=="talk"and step.npc==npcID then p.step=p.step+1;p.count=0;questNotice(ply,"step",def,step);if not Q.GraphDrives(def,"music") then questMusic(ply,"step",def) end;Q.RunGraphFrom(ply,def,"step_"..tostring((tonumber(p.step) or 1)-1),p);checkCurrent(ply,def,p)end end;Q.SaveProgress();sync(ply)
    end

    local function inZone(pos,step)
        if step.min and step.max then local mn,mx=vec(step.min),vec(step.max);return pos.x>=math.min(mn.x,mx.x)and pos.x<=math.max(mn.x,mx.x)and pos.y>=math.min(mn.y,mx.y)and pos.y<=math.max(mn.y,mx.y)and pos.z>=math.min(mn.z,mx.z)and pos.z<=math.max(mn.z,mx.z)end
        return step.pos and pos:DistToSqr(vec(step.pos))<=step.radius*step.radius
    end
    timer.Create("GRM_Quest_Objectives",1,0,function()
        local changed,changedPlayers=false,{}
        for _,ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll())do if IsValid(ply)and ply:Alive()then local all=progressFor(ply);for id,p in pairs(all)do local def=Q.Definitions[id];local step=def and def.steps[p.step or 1]
            if def and def.enabled and not def.draft and p.status=="active"and step then
                if step.type=="visit"and inZone(ply:GetPos(),step)then p.step=p.step+1;p.count=0;questNotice(ply,"step",def,step);if not Q.GraphDrives(def,"music") then questMusic(ply,"step",def) end;Q.RunGraphFrom(ply,def,"step_"..tostring((tonumber(p.step) or 1)-1),p);checkCurrent(ply,def,p);changed=true;changedPlayers[ply]=true
                elseif step.type=="item"then local before=p.count;checkCurrent(ply,def,p);if before~=p.count then changed=true;changedPlayers[ply]=true end end
            end
        end end end
        if changed then Q.SaveProgress();for ply in pairs(changedPlayers)do if IsValid(ply)then sync(ply)end end end
    end)

    function Q.OpenNPC(ply,npc)
        if not IsValid(ply)or not IsValid(npc)or ply:GetPos():DistToSqr(npc:GetPos())>220*220 then return end
        local npcID=npc:GetQuestNPCID();Q.Talk(ply,npcID);local rows={};local all=progressFor(ply)
        for _,def in pairs(Q.Definitions)do if def.npc==npcID and def.enabled and not def.draft then local p=all[def.id];local available=canStart(ply,def);rows[#rows+1]={definition=def,progress=p,available=available==true}end end
        table.sort(rows,function(a,b)return a.definition.title<b.definition.title end)
        net.Start("GRM_Quest_OpenNPC")net.WriteEntity(npc)net.WriteString(npc:GetQuestNPCName())net.WriteTable(rows)net.Send(ply)
    end

    net.Receive("GRM_Quest_PlayerOp",function(_,ply)
        if not IsValid(ply)then return end;ply.GRMQuestNext=ply.GRMQuestNext or 0;if CurTime()<ply.GRMQuestNext then return end;ply.GRMQuestNext=CurTime()+.2
        local op=net.ReadString();local id=net.ReadString()
        if op=="accept"then local ok,why=Q.Start(ply,id);if not ok then notice(ply,false,why)end
        elseif op=="dialogue"then
            local npc=ply:GetEyeTrace().Entity
            if not(IsValid(npc)and npc:GetClass()=="grm_quest_npc")then notice(ply,false,"Подойдите к персонажу")return end
            local def=Q.Definitions[id];if not def then return end
            local all=progressFor(ply);local p=all[id]
            local phase=not p and"offer"or(p.status=="active"and"active"or"complete")
            if not(Q.BeginDialogue and Q.BeginDialogue(ply,npc,id,phase))then notice(ply,false,"У этого задания нет диалога")end
        elseif op=="restart"then local def=Q.Definitions[id];local all=progressFor(ply);if not def or not def.repeatable then notice(ply,false,"Квест нельзя повторять")elseif not all[id]or all[id].status~="completed"then notice(ply,false,"Сначала завершите квест")else all[id]=nil;local ok,why=Q.Start(ply,id);if not ok then notice(ply,false,why)end end
        elseif op=="abandon"then local all=progressFor(ply);if all[id]and all[id].status=="active"then all[id]=nil;Q.SaveProgress();sync(ply);notice(ply,true,"Квест отменён")end end
    end)

    function Q.AdminData()local defs={};for _,d in pairs(Q.Definitions)do defs[#defs+1]=d end;table.sort(defs,function(a,b)return tostring(a.title or a.id)<tostring(b.title or b.id)end);local online={};for _,p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll())do if IsValid(p)then online[#online+1]={name=p:Nick(),key=characterKey(p)}end end;return{definitions=defs,eventTypes=Q.EventTypes,npcs=Q._NPCRecords or {},onlinePlayers=online}end
    local function adminOpen(ply)if not IsValid(ply)or not ply:IsSuperAdmin()then return end;net.Start("GRM_Quest_AdminOpen")net.WriteTable(Q.AdminData())net.Send(ply)end
    Q.OpenAdmin=adminOpen
    concommand.Add("grm_quests_admin",adminOpen)

    --[[ Сброс из консоли: grm_quest_reset <questID> [ник или SteamID64]
         Без второго аргумента сбрасывает СЕБЕ — самый частый случай,
         когда админ проверяет собственную правку. ]]
    concommand.Add("grm_quest_reset",function(ply,_,args)
        if not (IsValid(ply) and ply:IsSuperAdmin()) then return end
        local questID=trim(args and args[1],64)
        if questID=="" then
            ply:ChatPrint("[Квесты] grm_quest_reset <ID квеста> [ник или SteamID64]")
            return
        end
        local target=ply
        local who=trim(args and args[2],64)
        if who~="" then
            target=nil
            local low=string.lower(who)
            for _,p2 in ipairs(player.GetAll()) do
                if p2:SteamID64()==who or string.find(string.lower(p2:Nick()),low,1,true) then
                    target=p2 break
                end
            end
            if not IsValid(target) then ply:ChatPrint("[Квесты] Игрок не найден: "..who) return end
        end
        local done,why=Q.ResetQuest(ply,target,questID)
        ply:ChatPrint(done and ("[Квесты] Прохождение сброшено: "..questID.." у "..target:Nick())
            or ("[Квесты] "..tostring(why)))
    end)
    hook.Add("PlayerSayTransform","GRM_Quest_AdminChat",function(ply,pack)if not istable(pack)then return end;local cmd=string.lower(trim(pack[1],64));if cmd=="/grm_quests_admin"or cmd=="!grm_quests_admin"then adminOpen(ply);pack[1]="";pack.SkipPlayerSay=true end end)
    local function openJournal(ply)if not IsValid(ply)then return end;sync(ply);net.Start("GRM_Quest_Journal")net.Send(ply)end
    concommand.Add("grm_quests",openJournal)
    hook.Add("PlayerSayTransform","GRM_Quest_JournalChat",function(ply,pack)if not istable(pack)then return end;local cmd=string.lower(trim(pack[1],64));if cmd=="/quests"or cmd=="!quests"or cmd=="/квесты"then openJournal(ply);pack[1]="";pack.SkipPlayerSay=true end end)
    net.Receive("GRM_Quest_AdminOp",function(_,ply)
        if not IsValid(ply)or not ply:IsSuperAdmin()then return end;local op=net.ReadString()
        if op=="save"then local def,why=Q.NormalizeDefinition(net.ReadTable());if not def then notice(ply,false,why)return end
            --[[ Квест создаётся на той карте, где его правят. Ставим
                 метку при сохранении, а не при создании: так её получат
                 и старые квесты, которые просто открыли и сохранили. ]]
            if tostring(def.map or "")=="" then def.map=string.lower(game.GetMap() or "") end
            Q.Definitions[def.id]=def;Q.SaveDefinitions();Q.RegisterAchievements()
            -- Точки могли добавить, сдвинуть или удалить в студии —
            -- переставляем маркеры сразу, без перезапуска карты.
            Q.RefreshCheckpointMarkers()
            adminOpen(ply);notice(ply,true,"Квест сохранён: "..def.id)
        elseif op=="reset_progress"then local id=trim(net.ReadString(),64);local target=trim(net.ReadString(),96);if target=="@self"then target=characterKey(ply)elseif target~="*"and target:match("^%d+$")then target=target..":char1"end;local count=Q.ResetProgress(id,target);notice(ply,true,"Сброшен прогресс: "..count.." записей")
        elseif op=="delete"then local id=trim(net.ReadString(),64);local old=Q.Definitions[id];if old and old.achievement and GRM.Ach and GRM.Ach.Unregister then GRM.Ach.Unregister(old.achievement.id)end;Q.Definitions[id]=nil;Q.SaveDefinitions();adminOpen(ply);notice(ply,true,"Квест удалён")
        elseif op=="reset"then
            --[[ Кнопка «Сбросить прохождение» в студии. Право проверяет
                 Q.ResetQuest на сервере: клиентская кнопка ничего не
                 решает, её можно вызвать напрямую пакетом. ]]
            local id=trim(net.ReadString(),64)
            local done,why=Q.ResetQuest(ply,ply,id)
            notice(ply,done==true,done and ("Прохождение сброшено: "..id) or tostring(why))
        elseif op=="request"then adminOpen(ply)end
    end)

    function Q.SpawnNPC(id,name,model,pos,angles)
        local ent=ents.Create("grm_quest_npc");if not IsValid(ent)then return nil end;ent:SetPos(pos);ent:SetAngles(angles);ent:SetQuestNPCID(trim(id,64));ent:SetQuestNPCName(trim(name,80));if util.IsValidModel(model)then ent:SetModel(model)end;ent:Spawn();ent:Activate();Q.SaveDefinitions();return ent
    end
    --[[ МАРКЕРЫ ЧЕКПОИНТОВ НА КАРТЕ.

         Пересоздаём их целиком при каждом обновлении квестов: точек
         немного, а попытка «обновить существующие» дала бы рассинхрон
         после правки квеста в студии (удалённые точки остались бы
         висеть). Проще и надёжнее снести и расставить заново. ]]
    --[[ Пересчитать, кому видны маркеры. Зовём по СОБЫТИЮ (взял квест,
         прошёл точку, завершил), а не только по таймеру энтити: иначе
         игрок берёт квест и до секунды стоит перед пустым местом. ]]
    function Q.RefreshCheckpointVisibility()
        for _,ent in ipairs(ents.FindByClass("grm_quest_checkpoint"))do
            if IsValid(ent) and ent.UpdateTransmit then ent:UpdateTransmit() end
        end
    end

    function Q.RefreshCheckpointMarkers()
        for _,ent in ipairs(ents.FindByClass("grm_quest_checkpoint"))do
            if IsValid(ent) then ent:Remove() end
        end
        local made=0
        for _,def in pairs(Q.Definitions or {})do
            -- Черновики и чужие карты не расставляем: маркер посреди
            -- города от невключённого квеста только путает игроков.
            if def.enabled and not def.draft and Q.FitsMap(def) then
                for _,cp in ipairs(istable(def.checkpoints) and def.checkpoints or {})do
                    local pos=cp.pos
                    if istable(pos) and not (pos.x==0 and pos.y==0 and pos.z==0) then
                        local ent=ents.Create("grm_quest_checkpoint")
                        if IsValid(ent) then
                            ent:SetPos(vec(pos))
                            ent:SetQuestID(def.id)
                            ent:SetCheckpointID(cp.id)
                            ent:SetLabel(cp.label)
                            ent:SetRadius(cp.radius or 96)
                            ent:Spawn();ent:Activate()
                            made=made+1
                        end
                    end
                end
            end
        end
        return made
    end

    function Q.SaveAll()local a=Q.SaveDefinitions();local b=Q.SaveProgress();return a and b,"квесты и прогресс сохранены"end
    function Q.LoadAll()
        Q.LoadData();for _,ent in ipairs(ents.FindByClass("grm_quest_npc"))do if IsValid(ent)then ent:Remove()end end
        for _,r in ipairs(Q._NPCRecords or {})do Q.SpawnNPC(r.id,r.name,r.model,vec(r.pos),ang(r.ang))end
        Q.RefreshCheckpointMarkers()
        return true,"квесты, прогресс и NPC загружены"
    end
    --[[ Постановка чекпоинта тулом. Точку ставит админ кликом по земле:
         координаты руками в студии — гарантированная опечатка.
         Если точки с таким id ещё нет, создаём: автор мог добавить блок
         в графе и сразу пойти ставить маркер, не сохраняя квест. ]]
    --[[--------------------------------------------------------------
        СБРОС ПРОХОЖДЕНИЯ (заказ владельца 31.08).

        ЗАЧЕМ. Квест проходится один раз: после завершения он лежит в
        прогрессе со статусом completed, и NPC его больше не предлагает.
        Проверить правку сюжета было можно только сменой персонажа или
        ручной чисткой файла прогресса.

        ТОЛЬКО СУПЕРАДМИН. Без этого любой игрок обнулял бы себе
        прохождение и фармил награду по кругу — это дыра в экономике, а
        не удобство. Проверка стоит на СЕРВЕРЕ: клиентская ничего не
        стоит, её можно обойти подменой клиента.
    ----------------------------------------------------------------]]
    function Q.ResetQuest(actor,target,questID)
        -- Право: только суперадмин. Консоль сервера (actor == nil) права
        -- НЕ получает: команду может выполнить кто угодно из RCON-обёрток,
        -- а сброс чужого прогресса должен быть именным.
        if not (IsValid(actor) and actor.IsSuperAdmin and actor:IsSuperAdmin()) then return false,"Только суперадмин" end
        if not IsValid(target) then return false,"Игрок не найден" end

        questID=trim(questID,64)
        local def=Q.Definitions[questID]
        if not istable(def) then return false,"Квест не найден: "..questID end

        local all,key=progressFor(target)
        if not istable(all) or not istable(all[questID]) then
            return false,"У игрока нет прохождения этого квеста"
        end

        --[[ Убираем запись ЦЕЛИКОМ, а не правим статус: вместе с ней
             уходят пройденные чекпоинты и номер этапа. Оставь их — и
             маркеры останутся скрытыми, пройти заново будет нельзя. ]]
        all[questID]=nil

        --[[ Ачивку тоже снимаем: она выдаётся один раз, и без сброса
             повторное прохождение не покажет её выдачу — то есть
             проверить полный цикл не получится. ]]
        local a=def.achievement
        if istable(a) and a.enabled and GRM.Ach and isfunction(GRM.Ach.Reset) then
            pcall(GRM.Ach.Reset,target,a.id)
        end

        Q.SaveProgress();sync(target)
        if Q.RefreshCheckpointVisibility then Q.RefreshCheckpointVisibility() end
        if GRM.Audit and GRM.Audit.Write then
            GRM.Audit.Write("quests","progress.reset",actor,{questID=questID},{target=key})
        end
        hook.Run("GRM_QuestReset",actor,target,questID)
        return true
    end

    function Q.SetCheckpointPos(questID,cpID,pos)
        local def=Q.Definitions[tostring(questID or "")]
        if not istable(def) then return false,"Квест не найден" end
        cpID=trim(cpID,64)
        if cpID=="" then return false,"Не задан ID чекпоинта. Нажмите кнопку в Quest Studio." end

        def.checkpoints=istable(def.checkpoints) and def.checkpoints or {}
        local rec
        for _,c in ipairs(def.checkpoints) do if c.id==cpID then rec=c break end end
        if not rec then
            if #def.checkpoints>=32 then return false,"Слишком много чекпоинтов в квесте" end
            rec={id=cpID,label="",radius=96,once=true}
            def.checkpoints[#def.checkpoints+1]=rec
        end
        rec.pos=vectorData(pos)
        Q.SaveDefinitions()
        Q.RefreshCheckpointMarkers()
        return true
    end

    function Q.SetVisitZone(questID,stepIndex,first,second)
        local def=Q.Definitions[questID];local step=def and def.steps[math.floor(tonumber(stepIndex)or 0)];if not step then return false,"Квест или этап не найден"end;step.type="visit";step.min=vectorData(first);step.max=vectorData(second);Q.SaveDefinitions();return true
    end
    function Q.AddCutsceneNode(questID,phase,ply)
        local def=Q.Definitions[questID];if not def then return false,"Квест не найден"end;phase=phase=="complete"and"complete"or"accept";def.cutscene[phase]=def.cutscene[phase]or {};local index=#def.cutscene[phase]+1;local id="camera_"..index;if index>1 and tostring(def.cutscene[phase][index-1].next or"")==""then def.cutscene[phase][index-1].next=id end;def.cutscene[phase][index]={id=id,next="",transition=index==1 and"cut"or"move",moveDuration=1,pos=vectorData(ply:EyePos()),ang=angleData(ply:EyeAngles()),fov=75,duration=3,caption="",sound="",image=""};Q.SaveDefinitions();return true
    end

    hook.Add("GRM_CharacterChanged","GRM_Quest_CharacterSync",function(ply)timer.Simple(1,function()if IsValid(ply)then sync(ply)end end)end)
    hook.Add("PlayerInitialSpawn","GRM_Quest_Join",function(ply)timer.Simple(3,function()if not IsValid(ply)then return end;for _,def in pairs(Q.Definitions)do if def.autoStart and not def.draft and Q.FitsMap(def) then Q.Start(ply,def.id)end end;sync(ply)end)end)
    hook.Add("ShutDown","GRM_Quest_Save",function()Q.SaveDefinitions();Q.SaveProgress()end)
    hook.Add("PostCleanupMap","GRM_Quest_NPCRestore",function()timer.Simple(1,function()for _,r in ipairs(Q._NPCRecords or {})do Q.SpawnNPC(r.id,r.name,r.model,vec(r.pos),ang(r.ang))end end)end)
if GRM.Boot and GRM.Boot.Task then
    GRM.Boot.Task("quests.npc", "late", function() for _,r in ipairs(Q._NPCRecords or {})do Q.SpawnNPC(r.id,r.name,r.model,vec(r.pos),ang(r.ang))end end, { label = "Квесты: спавн NPC" })
else
    hook.Add("InitPostEntity","GRM_Quest_NPCLoad",function()timer.Simple(2,function()for _,r in ipairs(Q._NPCRecords or {})do Q.SpawnNPC(r.id,r.name,r.model,vec(r.pos),ang(r.ang))end end)end)
end

    -- Integrations: modules may also call GRM.Quests.Event directly.
    hook.Add("GRM_QuestEvent","GRM_Quest_GenericEvent",function(ply,eventName,target,amount,meta)Q.Event(ply,eventName,target,amount,meta)end)
    print("[GRM Quests] server v"..Q.Version.." loaded")
end
