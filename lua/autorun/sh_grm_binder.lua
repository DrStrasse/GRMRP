--[[--------------------------------------------------------------------
    GRM Binder v2.2.0 — бинды-последовательности для отыгровки
    v2.2.0 (вечер-12): ДВУСТОРОНЯЯ синхронизация с чатом режима — строки
           уходят через GRMRPChat.SendText (локальное эхо автора, форматер
           /me /do, история ввода — как у живого набора); свои команды
           зарегистрированы в реестре чата («/binder» открывается и из
           окна GRM-чата); словарь отыгровок сверяется с реестром ядра;
           EasyChat-ветка вырезана (указание владельца).

    Команды: /binder, /autobinder, /rpbinder, /бинды (и консольная grm_binder)

    ЧТО ЭТО. Слот = одна клавиша + СПИСОК ШАГОВ, которые выполняются по
    порядку со своими паузами. Один слот может быть целой сценой:

        [G]  шаг 1  чат:    /me исполнил воинское приветствие
             шаг 2  консоль: act salute

        [B]  шаг 1  чат: /dep Займу гос.волну, просьба не перебивать!
             шаг 2  чат: /gnews Уважаемые граждане, минуточку внимания!   (пауза 2 с)
             шаг 3  чат: /gnews В Корпус производится набор...            (пауза 4 с)
             шаг 4  чат: /gnews Требования — адекватный внешний вид...    (пауза 4 с)
             шаг 5  чат: /gnews С уважением, Генерал-Фельджандарм A.V.G!  (пауза 3 с)

    Возможности:
      * до 40 слотов, до 16 шагов в каждом;
      * шаг: тип «в чат» (say — работают /me, /do, /dep, /gnews, /fr) либо
        «в консоль» (act salute, +duck и т.п.) + собственная пауза ПЕРЕД ним;
      * порядок шагов меняется стрелками, любой шаг можно отключить;
      * клавиша на слот (DBinder), общая задержка старта, кулдаун, вкл/выкл;
      * связка со следующим слотом (цепочка сцен);
      * готовые ПРЕСЕТЫ: отыгровки, документы, служебные каналы —
        вставляются в слот одним кликом;
      * «Проверить» проигрывает сцену прямо из меню, «Стоп» гасит все
        отложенные шаги;
      * всё хранится локально в data/grm_binder.json.

    Безопасность и производительность:
      * бинды не срабатывают, пока открыт чат, консоль, меню игры или любое
        окно с курсором;
      * между шагами чата выдерживается минимальная пауза (антифлуд-защита
        сервера иначе просто съест часть строк);
      * цепочки защищены от зацикливания (глубина + список посещённых);
      * нажатие клавиши смотрит в таблицу «клавиша → слоты», а не перебирает
        все слоты (PlayerButtonDown зовётся на каждое нажатие).
----------------------------------------------------------------------]]

if SERVER then
    AddCSLuaFile()

    util.AddNetworkString("GRM_Binder_Open")

    -- Само меню клиентское, но команду перехватываем на сервере: иначе
    -- «/binder» уйдёт в общий чат. Ловим и PlayerSay, и PlayerSayTransform.
    local CMDS = {
        ["/binder"] = true, ["!binder"] = true,
        ["/autobinder"] = true, ["!autobinder"] = true,
        ["/rpbinder"] = true, ["!rpbinder"] = true,
        ["/бинды"] = true, ["/биндер"] = true,
    }

    local function svRegisterToChat()
        if GRMRPChat and GRMRPChat.RegisterExternalChatCommand then
            for cmd in pairs(CMDS) do GRMRPChat.RegisterExternalChatCommand(cmd) end
        elseif GRMChat and GRMChat.RegisterExternalChatCommand then
            for cmd in pairs(CMDS) do GRMChat.RegisterExternalChatCommand(cmd) end
        else
            timer.Simple(0.5, svRegisterToChat)
        end
    end
    svRegisterToChat()

    local function handleBinderChat(ply, text)
        if not IsValid(ply) then return false end
        local cmd = string.lower(string.Trim(tostring(text or "")))
        if not CMDS[cmd] then return false end
        net.Start("GRM_Binder_Open")
        net.Send(ply)
        return true
    end

    hook.Add("PlayerSay", "GRM_Binder_Chat", function(ply, text)
        if handleBinderChat(ply, text) then return "" end
    end)

    hook.Add("PlayerSay", "GRM_Binder_ChatEC", function(ply, text, teamSays)
        local datapack = { tostring(text or ""), SkipPlayerSay = false }
            if not istable(datapack) or not isstring(datapack[1]) then return end
            if not handleBinderChat(ply, datapack[1]) then return end
            datapack[1] = ""
            datapack.SkipPlayerSay = true

        if datapack.SkipPlayerSay == true then return "" end
    end)

    return
end

GRM = GRM or {}
GRM.Binder = GRM.Binder or {}
local BD = GRM.Binder
BD.Version = "2.2.0"

-- Вечер-12: заявляем свои команды реестру чата (gamemode-модуль GRMRPChat
-- или аддонский GRMChat) — по ним чат маршрутизирует ввод и не считает их
-- «неизвестными». Отложенно: gamemode грузится после addon-авторана.
BD.ChatCommands = { "/binder", "!binder", "/autobinder", "/rpbinder",
    "/бинды", "/биндер" }
local function registerToChat()
    local done
    for _, ns in ipairs({ GRMRPChat, GRMChat }) do
        if ns and ns.RegisterExternalChatCommand then
            for _, c in ipairs(BD.ChatCommands) do ns.RegisterExternalChatCommand(c) end
            done = true
        end
    end
    if not done then timer.Simple(0.5, registerToChat) end
end
registerToChat()

BD.MaxSlots      = 40
BD.DefaultSlots  = 20
BD.MaxSteps      = 16
BD.File          = "grm_binder.json"
BD.MaxChainDepth = 8
BD.MinChatGap    = 0.6   -- минимальная пауза между сообщениями в чат

surface.CreateFont("GRMBind_Title", { font = "Roboto", size = 21, weight = 800, extended = true })
surface.CreateFont("GRMBind_Head",  { font = "Roboto", size = 16, weight = 700, extended = true })
surface.CreateFont("GRMBind_Body",  { font = "Roboto", size = 14, weight = 500, extended = true })
surface.CreateFont("GRMBind_Small", { font = "Roboto", size = 12, weight = 400, extended = true })
surface.CreateFont("GRMBind_Memo",  { font = "Roboto", size = 15, weight = 700, extended = true })

local C = {
    bg     = Color(16, 20, 28, 252),
    head   = Color(12, 15, 22, 255),
    card   = Color(22, 28, 38, 245),
    step   = Color(27, 34, 46, 245),
    border = Color(38, 48, 66, 200),
    acc    = Color(65, 145, 235),
    green  = Color(55, 185, 110),
    gold   = Color(245, 195, 65),
    goldBg = Color(58, 46, 14, 250),
    red    = Color(225, 70, 70),
    violet = Color(170, 130, 235),
    text   = Color(240, 244, 250),
    dim    = Color(155, 170, 190),
    off    = Color(58, 66, 80),
}

local MEMO = "БИНДЕР служит упрощением отыгровки монотонных механик и выполнения определённых действий, " ..
             "но не может служить заменой полноценной отыгровки РП процесса!"

local function click(path)
    if GRM.Sound and GRM.Sound.UI then GRM.Sound.UI(path or "buttons/button15.wav")
    elseif surface and surface.PlaySound then surface.PlaySound(path or "buttons/button15.wav") end
end

--[[ Звуковая схема круга — стоковые HL2, те же, что у выбора оружия:
     открытие, «щелчок» при переходе на другой сектор, подтверждение и
     отмена. Молчаливое меню ощущается сломанным. ]]
local RADIAL_SND = {
    open  = "common/wpn_hudon.wav",
    close = "common/wpn_hudoff.wav",
    move  = "common/wpn_moveselect.wav",
    pick  = "common/wpn_select.wav",
    deny  = "common/wpn_denyselect.wav",
}

local function radialSound(kind, throttle)
    local path = RADIAL_SND[kind]
    if not path then return end
    if GRM.Sound and GRM.Sound.UI then GRM.Sound.UI(path, throttle or 0.02)
    elseif surface and surface.PlaySound then surface.PlaySound(path) end
end

-----------------------------------------------------------------------
-- Пресеты: готовые сцены в один клик
-----------------------------------------------------------------------
BD.Presets = {
    {
        group = "Отыгровка",
        name = "Воинское приветствие",
        key = "KEY_G",
        steps = {
            { mode = "chat",    text = "/me исполнил воинское приветствие", delay = 0 },
            { mode = "console", text = "act salute",                        delay = 0.2 },
        },
    },
    {
        group = "Отыгровка",
        name = "Представиться",
        steps = {
            { mode = "chat", text = "/me приложил руку к головному убору и представился", delay = 0 },
            { mode = "chat", text = "/do На груди виден служебный жетон.",                delay = 1.5 },
        },
    },
    {
        group = "Отыгровка",
        name = "Досмотр гражданина",
        steps = {
            { mode = "chat", text = "/me попросил гражданина предъявить документы",      delay = 0 },
            { mode = "chat", text = "/do Рука легла на планшет с бланками.",             delay = 1.5 },
            { mode = "chat", text = "/y Предъявите документы, пожалуйста!",              delay = 1.5 },
        },
    },
    {
        group = "Документы",
        name = "Показать удостоверение",
        steps = {
            { mode = "chat", text = "/me достал служебное удостоверение и раскрыл его", delay = 0 },
            { mode = "chat", text = "/showbadge",                                        delay = 1.2 },
        },
    },
    {
        group = "Документы",
        name = "Показать паспорт",
        steps = {
            { mode = "chat", text = "/me достал паспорт из внутреннего кармана", delay = 0 },
            { mode = "chat", text = "/showpassport",                              delay = 1.2 },
        },
    },
    {
        group = "Документы",
        name = "Показать права",
        steps = {
            { mode = "chat", text = "/me протянул водительское удостоверение", delay = 0 },
            { mode = "chat", text = "/showprava",                               delay = 1.2 },
        },
    },
    {
        group = "Документы",
        name = "Показать военный билет",
        steps = {
            { mode = "chat", text = "/me предъявил военный билет", delay = 0 },
            { mode = "chat", text = "/showmilitary",                delay = 1.2 },
        },
    },
    {
        group = "Документы",
        name = "Показать медкарту",
        steps = {
            { mode = "chat", text = "/me открыл медицинскую карту", delay = 0 },
            { mode = "chat", text = "/showmedcard",                  delay = 1.2 },
        },
    },
    {
        group = "Документы",
        name = "Мои документы (список)",
        steps = {
            { mode = "chat", text = "/myid",       delay = 0 },
            { mode = "chat", text = "/mypasport",  delay = 0.8 },
            { mode = "chat", text = "/mylicense",  delay = 0.8 },
        },
    },
    {
        group = "Служебные каналы",
        name = "Объявление по гос.волне",
        steps = {
            { mode = "chat", text = "/dep Займу гос.волну, просьба не перебивать!",              delay = 0 },
            { mode = "chat", text = "/gnews Уважаемые граждане, минуточку внимания!",            delay = 2 },
            { mode = "chat", text = "/gnews Текст объявления — замените на свой.",               delay = 4 },
            { mode = "chat", text = "/gnews С уважением, администрация организации.",            delay = 4 },
        },
    },
    {
        group = "Служебные каналы",
        name = "Набор в организацию",
        steps = {
            { mode = "chat", text = "/dep Займу гос.волну, просьба не перебивать!",                                   delay = 0 },
            { mode = "chat", text = "/gnews Уважаемые граждане, минуточку внимания!",                                 delay = 2 },
            { mode = "chat", text = "/gnews Производится набор в нашу организацию, ждём вас по адресу.",              delay = 4 },
            { mode = "chat", text = "/gnews Требования: адекватный внешний вид, паспорт, медкарта, диплом.",          delay = 4 },
            { mode = "chat", text = "/gnews С уважением, руководство организации!",                                   delay = 4 },
        },
    },
    {
        group = "Служебные каналы",
        name = "Доклад по рации",
        steps = {
            { mode = "chat", text = "/fr Приём, докладываю обстановку.", delay = 0 },
            { mode = "chat", text = "/frb (( свободен, могу подъехать ))", delay = 1.5 },
        },
    },
}

-----------------------------------------------------------------------
-- Данные
-----------------------------------------------------------------------
local function blankStep()
    return { mode = "chat", text = "", delay = 0, enabled = true }
end

local function blankSlot(i)
    return {
        id = i,
        name = "Слот " .. i,
        key = KEY_NONE,
        enabled = true,
        delay = 0,            -- задержка перед стартом сцены
        cooldown = 0.5,       -- личный кулдаун слота
        chain = 0,            -- id связанного слота (0 = нет)
        chainDelay = 1,
        steps = { blankStep() },
    }
end
BD.BlankSlot = blankSlot
BD.BlankStep = blankStep

BD.Slots = BD.Slots or {}
BD.KeyMap = BD.KeyMap or {}

--[[ РАДИАЛЬНОЕ МЕНЮ (по образцу селектора оружия).
     Одна клавиша на всё: держишь — появляется круг с секторами, мышью
     наводишь нужный, отпускаешь — сцена играет. Сектора настраиваются
     в /binder: в каждый кладётся любой существующий слот. ]]
BD.MaxRadial = 12
BD.Radial = BD.Radial or { key = KEY_NONE, items = {} }

-- Правки в меню копятся в памяти и уходят на диск по кнопке «СОХРАНИТЬ».
BD.Dirty = false
function BD.MarkDirty() BD.Dirty = true end

local function slotHasWork(slot)
    for _, st in ipairs(slot.steps or {}) do
        if st.enabled ~= false and string.Trim(tostring(st.text or "")) ~= "" then return true end
    end
    return false
end

function BD.RebuildKeyMap()
    BD.KeyMap = {}
    for i = 1, BD.MaxSlots do
        local s = BD.Slots[i]
        if istable(s) and s.enabled and s.key and s.key > KEY_NONE and slotHasWork(s) then
            BD.KeyMap[s.key] = BD.KeyMap[s.key] or {}
            table.insert(BD.KeyMap[s.key], i)
        end
    end
end

-- Старый формат (одно действие на слот) читается и переводится в шаги.
local function normalizeSlot(row, i)
    local slot = blankSlot(i)
    slot.name = tostring(row.name or slot.name)
    slot.key = math.Clamp(math.floor(tonumber(row.key) or KEY_NONE), 0, 159)
    slot.enabled = row.enabled ~= false
    slot.delay = math.Clamp(tonumber(row.delay) or 0, 0, 60)
    slot.cooldown = math.Clamp(tonumber(row.cooldown) or 0.5, 0, 60)
    slot.chain = math.Clamp(math.floor(tonumber(row.chain) or 0), 0, BD.MaxSlots)
    slot.chainDelay = math.Clamp(tonumber(row.chainDelay) or 1, 0, 60)

    slot.steps = {}
    if istable(row.steps) and #row.steps > 0 then
        for _, st in ipairs(row.steps) do
            if istable(st) and #slot.steps < BD.MaxSteps then
                slot.steps[#slot.steps + 1] = {
                    mode = (st.mode == "console" and "console") or (st.mode == "anim" and "anim") or "chat",
                    text = tostring(st.text or ""),
                    delay = math.Clamp(tonumber(st.delay) or 0, 0, 60),
                    enabled = st.enabled ~= false,
                }
            end
        end
    elseif row.text and row.text ~= "" then
        -- миграция v1 → v2
        slot.steps[1] = {
            mode = (row.mode == "console") and "console" or "chat",
            text = tostring(row.text),
            delay = 0,
            enabled = true,
        }
    end
    if #slot.steps == 0 then slot.steps[1] = blankStep() end
    return slot
end

function BD.Load()
    BD.Slots = {}
    local raw = file.Read(BD.File, "DATA")
    local root = (raw and raw ~= "") and util.JSONToTable(raw) or nil

    -- v2.1: файл стал объектом { slots = {...}, radial = {...} }.
    -- Старый формат (просто массив слотов) читается как прежде.
    local data, radial = nil, nil
    if istable(root) then
        if istable(root.slots) then
            data, radial = root.slots, root.radial
        else
            data = root
        end
    end

    BD.Radial = { key = KEY_NONE, items = {} }
    if istable(radial) then
        BD.Radial.key = math.Clamp(math.floor(tonumber(radial.key) or KEY_NONE), 0, 159)
        for _, id in ipairs(istable(radial.items) and radial.items or {}) do
            if #BD.Radial.items < BD.MaxRadial then
                local n = math.Clamp(math.floor(tonumber(id) or 0), 0, BD.MaxSlots)
                if n > 0 then BD.Radial.items[#BD.Radial.items + 1] = n end
            end
        end
    end

    if istable(data) then
        for _, row in ipairs(data) do
            if istable(row) then
                local i = math.Clamp(math.floor(tonumber(row.id) or 0), 0, BD.MaxSlots)
                if i > 0 then BD.Slots[i] = normalizeSlot(row, i) end
            end
        end
    end
    local shown = BD.DefaultSlots
    for i = 1, BD.MaxSlots do if BD.Slots[i] then shown = math.max(shown, i) end end
    for i = 1, shown do
        if not BD.Slots[i] then BD.Slots[i] = blankSlot(i) end
    end
    BD.RebuildKeyMap()
    return BD.Slots
end

function BD.Save()
    local arr = {}
    for i = 1, BD.MaxSlots do
        local s = BD.Slots[i]
        if istable(s) then
            local steps = {}
            for _, st in ipairs(s.steps or {}) do
                steps[#steps + 1] = { mode = st.mode, text = st.text, delay = st.delay, enabled = st.enabled }
            end
            arr[#arr + 1] = {
                id = i, name = s.name, key = s.key, enabled = s.enabled,
                delay = s.delay, cooldown = s.cooldown,
                chain = s.chain, chainDelay = s.chainDelay, steps = steps,
            }
        end
    end
    file.Write(BD.File, util.TableToJSON({
        version = 2,
        slots = arr,
        radial = { key = BD.Radial.key or KEY_NONE, items = BD.Radial.items or {} },
    }, true))
    BD.RebuildKeyMap()
    BD.Dirty = false
    return true
end

-----------------------------------------------------------------------
-- Выполнение сцены
-----------------------------------------------------------------------
local lastRun = {}
BD.Running = BD.Running or {}   -- id таймеров активных сцен

-- Движок обрезает консольную команду say примерно на 127 байтах. Полноценная
-- длинная строка режима — net-канал GRM-чата (SendText; сервер физрежет 1024,
-- клиент 512): через него шаг уходит целиком. EasyChat вырезан из сборки
-- совсем (указание владельца, вечер-12) — его 3000-символьный лимит больше
-- нигде не опора. Без чата — режем по словам на куски, влезающие в say,
-- ведущая команда (/me, /do, /dep …) сохраняется в каждом куске.
BD.SayLimit = 120   -- запас от движкового 127 (байты, не символы)

function BD.ChatLimit()
    if (GRMRPChat and isfunction(GRMRPChat.SendText))
        or (GRMChat and isfunction(GRMChat.SendText)) then
        return 500 -- под клиентским clamp 512: строка не «схлопнется»
    end
    return BD.SayLimit
end

-- Режем строку на куски не длиннее limit БАЙТ, по границам слов.
function BD.SplitChat(text, limit)
    limit = math.max(16, math.floor(tonumber(limit) or BD.SayLimit))
    text = string.Trim(tostring(text or ""))
    if text == "" then return {} end
    if #text <= limit then return { text } end

    local prefix = string.match(text, "^(/%S+)%s") or ""
    local body   = prefix ~= "" and string.Trim(string.sub(text, #prefix + 1)) or text
    local head   = prefix ~= "" and (prefix .. " ") or ""
    local room   = limit - #head
    if room < 16 then head, room = "", limit end

    local out, cur = {}, ""
    local function flush()
        if cur ~= "" then out[#out + 1] = head .. cur; cur = "" end
    end
    for word in string.gmatch(body, "%S+") do
        -- одно слово длиннее куска — рвём его насильно
        while #word > room do
            flush()
            out[#out + 1] = head .. string.sub(word, 1, room)
            word = string.sub(word, room + 1)
        end
        if cur == "" then
            cur = word
        elseif #cur + 1 + #word <= room then
            cur = cur .. " " .. word
        else
            flush()
            cur = word
        end
    end
    flush()
    return out
end

local function sendChat(text)
    -- Вечер-12: приоритет — чат режима (GRMRPChat/GRMChat.SendText): тот же
    -- путь, что Enter в окне (локальное эхо автора — сервер автору НЕ
    -- ретранслирует; форматер /me /do; история ввода; антифлуд-лесенка).
    -- EasyChat вырезан полностью (указание владельца): ветки к нему нет.
    local ns = (GRMRPChat and isfunction(GRMRPChat.SendText) and GRMRPChat)
        or (GRMChat and isfunction(GRMChat.SendText) and GRMChat)
    local function put(part)
        if ns then ns.SendText(part)
        else RunConsoleCommand("say", part) end
    end
    -- С чатом лимит = ChatLimit (500 байт < клиентского clamp 512): целая
    -- строка идёт через net-канал без порезки; без чата — SayLimit с
    -- запасом от движкового 127 на say.
    local parts = BD.SplitChat(text, ns and BD.ChatLimit() or BD.SayLimit)
    for i, part in ipairs(parts) do
        if i == 1 then
            put(part)
        else
            local tname = ("GRM_BinderSay_%d_%f"):format(i, RealTime())
            BD.Running[tname] = true
            timer.Create(tname, BD.MinChatGap * (i - 1), 1, function()
                BD.Running[tname] = nil
                put(part)
            end)
        end
    end
    return #parts
end

-- Вечер-12: «синхронизация с /me и другими командами» — словарь отыгровок
-- и каналов берётся у ядра чата (RPCommandNames/Channels/ExternalCommands),
-- своего домысла нет. Неизвестное подсвечивается предупреждением при
-- прогоне, НО не блокируется: чат может быть выключен cvar'ом.
function BD.UnknownChatCommand(text)
    text = string.Trim(tostring(text or ""))
    local cmd = string.match(text, "^/([%w_]+)")
    if not cmd then return false end
    local ns = (GRMRPChat and GRMRPChat.RP) and GRMRPChat or (GRMChat and GRMChat.RP and GRMChat)
    if not ns then return false end
    cmd = string.lower(cmd)
    if ns.RP[cmd] then return false end
    for _, chan in pairs(ns.Channels or {}) do
        if chan.cmd and string.lower(chan.cmd) == cmd then return false end
        if chan.cmds then
            for alias in pairs(chan.cmds) do
                if string.lower(alias) == cmd then return false end
            end
        end
    end
    if cmd == "pm" then return false end
    for c in pairs(ns.ExternalCommands or {}) do
        if string.lower(c) == "/" .. cmd then return false end
    end
    return true
end

local function runStep(step)
    local text = string.Trim(tostring(step.text or ""))
    if text == "" then return false end
    if step.mode == "console" then
        LocalPlayer():ConCommand(text .. "\n")
    elseif step.mode == "anim" then
        if GRM.Social and GRM.Social.Request then GRM.Social.Request(text)
        else RunConsoleCommand("grm_social", text) end
    else
        if BD.UnknownChatCommand(text) then
            local ns = (GRMRPChat and GRMRPChat.AddSystem and GRMRPChat)
                or (GRMChat and GRMChat.AddSystem and GRMChat)
            if ns then
                ns.AddSystem("биндер: чат не знает команду «"
                    .. tostring(string.match(text, "^/[%w_]+"))
                    .. "» — шаг ушёл как есть")
            end
        end
        sendChat(text)
    end
    return true
end

function BD.StopAll()
    local n = 0
    for name in pairs(BD.Running) do
        if timer.Exists(name) then timer.Remove(name) end
        n = n + 1
    end
    BD.Running = {}
    return n
end

-- Проиграть сцену слота. depth/visited защищают цепочку слотов.
function BD.Run(index, depth, visited, force)
    index = math.floor(tonumber(index) or 0)
    local slot = BD.Slots[index]
    if not istable(slot) then return false end
    if not force and not slot.enabled then return false end

    depth = depth or 1
    visited = visited or {}
    if depth > BD.MaxChainDepth or visited[index] then
        chat.AddText(C.red, "[Биндер] ", C.text, "Цепочка прервана: слишком длинная или зациклена.")
        return false
    end
    visited[index] = true

    local now = RealTime()
    if not force then
        local cd = tonumber(slot.cooldown) or 0
        if cd > 0 and (lastRun[index] or 0) + cd > now then return false end
    end
    lastRun[index] = now

    -- Считаем абсолютное время каждого шага: пауза шага + минимальный
    -- интервал между сообщениями в чат (иначе антифлуд сервера съест строки).
    local at = math.Clamp(tonumber(slot.delay) or 0, 0, 60)
    local lastChatAt = -math.huge
    local seq = 0

    for _, step in ipairs(slot.steps or {}) do
        if step.enabled ~= false and string.Trim(tostring(step.text or "")) ~= "" then
            at = at + math.Clamp(tonumber(step.delay) or 0, 0, 60)
            if step.mode ~= "console" then
                if at - lastChatAt < BD.MinChatGap then at = lastChatAt + BD.MinChatGap end
                -- если строка не влезает в одно сообщение, она уйдёт кусками —
                -- держим паузу и на них, чтобы следующий шаг не наложился
                local parts = #BD.SplitChat(step.text, BD.ChatLimit())
                lastChatAt = at + BD.MinChatGap * math.max(0, parts - 1)
            end
            seq = seq + 1
            local tname = ("GRM_Binder_%d_%d_%f"):format(index, seq, now)
            if at <= 0 then
                runStep(step)
            else
                BD.Running[tname] = true
                timer.Create(tname, at, 1, function()
                    BD.Running[tname] = nil
                    runStep(step)
                end)
            end
        end
    end

    local nextID = math.floor(tonumber(slot.chain) or 0)
    if nextID > 0 and nextID ~= index then
        local wait = math.max(at, lastChatAt, 0) + math.Clamp(tonumber(slot.chainDelay) or 0, 0, 60)
        local tname = ("GRM_BinderChain_%d_%f"):format(index, now)
        BD.Running[tname] = true
        timer.Create(tname, wait, 1, function()
            BD.Running[tname] = nil
            BD.Run(nextID, depth + 1, visited, force)
        end)
    end
    return true
end

-- Бинды не должны стрелять, когда игрок печатает или залез в меню.
local function inputBusy()
    if gui.IsGameUIVisible() or gui.IsConsoleVisible() then return true end
    if vgui.CursorVisible() then return true end
    local lp = LocalPlayer()
    if IsValid(lp) and lp.IsTyping and lp:IsTyping() then return true end
    return false
end

-----------------------------------------------------------------------
-- РАДИАЛЬНОЕ МЕНЮ (подобие селектора оружия)
--
-- Держим одну клавишу → на экране круг с секторами. Мышь наводит сектор
-- (как в селекторе оружия), отпускание клавиши запускает выбранную сцену.
-- Курсор в центре = отмена. Рисуется только пока меню открыто, ничего не
-- считается в кадре сверх этого.
-----------------------------------------------------------------------
BD.RadialOpen = false
BD.RadialPick = 0

local function radialEntries()
    local out = {}
    for _, id in ipairs(BD.Radial.items or {}) do
        local slot = BD.Slots[id]
        if istable(slot) then out[#out + 1] = { id = id, slot = slot } end
    end
    return out
end
BD.RadialEntries = radialEntries

-- Сектор под курсором: 0 = центр (отмена).
function BD.RadialPickFrom(cx, cy, mx, my, count, deadZone)
    if count <= 0 then return 0 end
    local dx, dy = mx - cx, my - cy
    if (dx * dx + dy * dy) < (deadZone * deadZone) then return 0 end
    -- Отсчёт от «12 часов» по часовой стрелке — как читается круг глазами.
    local ang = math.deg(math.atan2(dx, -dy))
    if ang < 0 then ang = ang + 360 end
    local sector = math.floor((ang + (180 / count)) / (360 / count)) + 1
    if sector > count then sector = 1 end
    return sector
end

function BD.OpenRadial()
    if BD.RadialOpen then return end
    if #radialEntries() == 0 then
        chat.AddText(C.gold, "[Биндер] ", C.text, "Радиальные слоты не настроены — откройте /binder.")
        return
    end
    BD.RadialOpen = true
    BD.RadialPick = 0
    BD.RadialAnim = {}
    BD.RadialOpenedAt = RealTime()
    gui.EnableScreenClicker(true)
    radialSound("open", 0.05)
end

-- Закрыть круг. execute=true — запустить выбранный сектор.
function BD.CloseRadial(execute)
    if not BD.RadialOpen then return end
    BD.RadialOpen = false
    gui.EnableScreenClicker(false)

    local entries = radialEntries()
    local pick = BD.RadialPick
    BD.RadialPick = 0
    if not execute or pick <= 0 or not entries[pick] then
        radialSound("close", 0.05)
        return
    end
    radialSound("pick", 0.05)
    BD.Run(entries[pick].id)
end

hook.Add("PlayerButtonDown", "GRM_Binder_Radial", function(ply, key)
    if ply ~= LocalPlayer() then return end

    -- ЛКМ внутри открытого круга = «выполнить выбранное» (как просил владелец:
    -- навёл мышью, кликнул — цепочка пошла). ПКМ = отмена.
    if BD.RadialOpen then
        if key == MOUSE_LEFT then
            BD.CloseRadial(true)
            return
        elseif key == MOUSE_RIGHT then
            BD.CloseRadial(false)
            return
        end
    end

    if key ~= (BD.Radial.key or KEY_NONE) or key <= KEY_NONE then return end
    if inputBusy() then return end
    BD.OpenRadial()
end)

hook.Add("PlayerButtonUp", "GRM_Binder_RadialUp", function(ply, key)
    if ply ~= LocalPlayer() then return end
    if key ~= (BD.Radial.key or KEY_NONE) then return end
    -- Отпустили клавишу — круг просто закрывается. Запуск делает ЛКМ.
    BD.CloseRadial(false)
end)

--[[ Пока круг открыт, персонаж стоит на месте — как при открытом C-меню.
     Гасим и движение, и кнопки: иначе ЛКМ выбора сектора уходила бы ещё и
     в оружие (выстрел/удар), а WASD таскал бы игрока вслепую. ]]
hook.Add("StartCommand", "GRM_Binder_RadialFreeze", function(ply, cmd)
    if not BD.RadialOpen then return end
    if ply ~= LocalPlayer() then return end
    cmd:ClearMovement()
    cmd:ClearButtons()
end)

-- Страховка на случай, если событие отпускания клавиши потерялось
-- (альт-таб, потеря фокуса): круг не должен «залипнуть» с курсором.
hook.Add("Think", "GRM_Binder_RadialGuard", function()
    if not BD.RadialOpen then return end
    local key = BD.Radial.key or KEY_NONE
    if key <= KEY_NONE then BD.CloseRadial(false) return end
    if not input.IsKeyDown(key) and not input.IsMouseDown(key) then
        BD.CloseRadial(false)
    end
end)

-- ESC и смерть гасят меню, чтобы курсор не завис включённым.
hook.Add("OnPlayerChat", "GRM_Binder_RadialChat", function() if BD.RadialOpen then BD.CloseRadial(false) end end)
hook.Add("PlayerDeath", "GRM_Binder_RadialDeath", function() if BD.RadialOpen then BD.CloseRadial(false) end end)

-- Краски радиального меню (перерисовка каждый кадр; §6.1.8)
local BIND_OUTLINE = Color(8, 12, 18, 235)
local BIND_SEL = Color(235, 245, 255)
local BIND_TEXT_C = Color(0, 0, 0, 255)

hook.Add("HUDPaint", "GRM_Binder_RadialDraw", function()
    if not BD.RadialOpen then return end
    local entries = radialEntries()
    local count = #entries
    if count == 0 then BD.CloseRadial(false) return end

    local sw, sh = ScrW(), ScrH()
    local cx, cy = sw / 2, sh / 2
    local outer = math.min(sw, sh) * 0.30
    local inner = outer * 0.42
    local mx, my = gui.MousePos()
    if mx == 0 and my == 0 then mx, my = cx, cy end

    local prevPick = BD.RadialPick
    BD.RadialPick = BD.RadialPickFrom(cx, cy, mx, my, count, inner)
    -- «Щелчок» при переходе на другой сектор — как в селекторе оружия.
    if BD.RadialPick ~= prevPick and BD.RadialPick > 0 then radialSound("move") end

    -- Плавная подсветка: каждый сектор тянется к 1 при наведении и обратно
    -- к 0 при уходе мыши. Считается по FrameTime, без таймеров.
    BD.RadialAnim = BD.RadialAnim or {}
    local ft = math.min(FrameTime() * 9, 1)
    for i = 1, count do
        local target = (BD.RadialPick == i) and 1 or 0
        BD.RadialAnim[i] = (BD.RadialAnim[i] or 0) + (target - (BD.RadialAnim[i] or 0)) * ft
    end

    -- Затемнение и центральная «шайба»
    surface.SetDrawColor(0, 0, 0, 170)
    surface.DrawRect(0, 0, sw, sh)
    draw.NoTexture()
    surface.SetDrawColor(C.head.r, C.head.g, C.head.b, 240)

    local step = 360 / count
    local pulse = 0.5 + math.sin(RealTime() * 6) * 0.5
    for i, entry in ipairs(entries) do
        local anim = BD.RadialAnim[i] or 0
        local selected = (BD.RadialPick == i)
        local startAng = (i - 1) * step - step / 2 - 90
        local segments = math.max(8, math.floor(step / 3))

        -- Сектор «выезжает» и раздаётся по мере наведения.
        local grow = 16 * anim
        local r1 = outer + grow
        local r0 = inner - 4 * anim
        local gap = math.rad(1.2)

        local poly = {}
        for s2 = 0, segments do
            local a = math.rad(startAng) + gap + (math.rad(step) - gap * 2) * (s2 / segments)
            poly[#poly + 1] = { x = cx + math.cos(a) * r1, y = cy + math.sin(a) * r1 }
        end
        for s2 = segments, 0, -1 do
            local a = math.rad(startAng) + gap + (math.rad(step) - gap * 2) * (s2 / segments)
            poly[#poly + 1] = { x = cx + math.cos(a) * r0, y = cy + math.sin(a) * r0 }
        end

        draw.NoTexture()
        -- База темнее, наведённый сектор плавно уходит в акцентный синий.
        local br = Lerp(anim, C.card.r, C.acc.r)
        local bg = Lerp(anim, C.card.g, C.acc.g)
        local bb = Lerp(anim, C.card.b, C.acc.b)
        surface.SetDrawColor(br, bg, bb, 230 + 25 * anim)
        surface.DrawPoly(poly)

        -- Светящаяся кромка выбранного сектора.
        if anim > 0.02 then
            local edge = {}
            local glowR = r1 + 3
            for s2 = 0, segments do
                local a = math.rad(startAng) + gap + (math.rad(step) - gap * 2) * (s2 / segments)
                edge[#edge + 1] = { x = cx + math.cos(a) * glowR, y = cy + math.sin(a) * glowR }
            end
            for s2 = segments, 0, -1 do
                local a = math.rad(startAng) + gap + (math.rad(step) - gap * 2) * (s2 / segments)
                edge[#edge + 1] = { x = cx + math.cos(a) * r1, y = cy + math.sin(a) * r1 }
            end
            draw.NoTexture()
            surface.SetDrawColor(C.gold.r, C.gold.g, C.gold.b, (120 + 100 * pulse) * anim)
            surface.DrawPoly(edge)
        end

        -- Подпись сектора
        local midA = math.rad(startAng + step / 2)
        local tr = (r0 + r1) / 2
        local tx, ty = cx + math.cos(midA) * tr, cy + math.sin(midA) * tr
        local slot = entry.slot
        local steps = 0
        for _, st in ipairs(slot.steps or {}) do
            if st.enabled ~= false and string.Trim(tostring(st.text or "")) ~= "" then steps = steps + 1 end
        end
        -- textCol «разгорается» вместе с анимацией появления сектора — это
        -- скретч с записью полей перед немедленной отрисовкой; обводка и
        -- выбранный слот — константы (§6.1.8)
        local textCol = BIND_TEXT_C
        textCol.r = math.floor(Lerp(anim, C.text.r, 255))
        textCol.g = math.floor(Lerp(anim, C.text.g, 255))
        textCol.b = math.floor(Lerp(anim, C.text.b, 255))
        draw.SimpleTextOutlined(tostring(slot.name or ("Слот " .. entry.id)),
            anim > 0.5 and "GRMBind_Head" or "GRMBind_Body", tx, ty - 9,
            textCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, BIND_OUTLINE)
        draw.SimpleTextOutlined(steps .. " шаг(ов)", "GRMBind_Small", tx, ty + 11,
            selected and BIND_SEL or C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, BIND_OUTLINE)
    end

    -- Центр: подсказка и текущий выбор
    draw.NoTexture()
    surface.SetDrawColor(C.head.r, C.head.g, C.head.b, 245)
    local hub = {}
    for a = 0, 360, 6 do
        local r = math.rad(a)
        hub[#hub + 1] = { x = cx + math.cos(r) * (inner - 6), y = cy + math.sin(r) * (inner - 6) }
    end
    surface.DrawPoly(hub)

    local picked = entries[BD.RadialPick]
    draw.SimpleText("БИНДЕР", "GRMBind_Head", cx, cy - 22, C.gold, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    if picked then
        draw.SimpleText(tostring(picked.slot.name or ""), "GRMBind_Body", cx, cy, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("ЛКМ — выполнить", "GRMBind_Small", cx, cy + 20, C.green, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    else
        draw.SimpleText("наведите мышь", "GRMBind_Body", cx, cy, C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("ЛКМ — выполнить, ПКМ — отмена", "GRMBind_Small", cx, cy + 20, C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end)

hook.Add("PlayerButtonDown", "GRM_Binder_Keys", function(ply, key)
    if ply ~= LocalPlayer() then return end
    -- Клавиша радиального меню принадлежит только ему: если на ней случайно
    -- висит и обычный слот, сцена не должна играть одновременно с открытием
    -- круга.
    if key == (BD.Radial.key or KEY_NONE) and key > KEY_NONE then return end
    if BD.RadialOpen then return end
    local slots = BD.KeyMap[key]
    if not slots then return end
    if inputBusy() then return end
    for _, index in ipairs(slots) do BD.Run(index) end
end)

-----------------------------------------------------------------------
-- Меню
-----------------------------------------------------------------------
local frame

local function mkBtn(parent, label, col, onClick, font)
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b.Label = label
    b.Paint = function(s, w, h)
        local base = col or C.acc
        local c = s:IsHovered()
            and Color(math.min(255, base.r + 25), math.min(255, base.g + 25), math.min(255, base.b + 25))
            or base
        draw.RoundedBox(5, 0, 0, w, h, c)
        surface.SetDrawColor(255, 255, 255, 22)
        surface.DrawOutlinedRect(0, 0, w, h)
        draw.SimpleText(s.Label, font or "GRMBind_Body", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    b.DoClick = function() click() if onClick then onClick(b) end end
    return b
end

local function mkEntry(parent, placeholder, value, onChange)
    local e = vgui.Create("DTextEntry", parent)
    e:SetFont("GRMBind_Body")
    e:SetPlaceholderText(placeholder or "")
    e:SetText(tostring(value or ""))
    e:SetUpdateOnType(true)
    e.Paint = function(s, w, h)
        draw.RoundedBox(4, 0, 0, w, h, Color(14, 18, 26))
        surface.SetDrawColor(C.border.r, C.border.g, C.border.b, 255)
        surface.DrawOutlinedRect(0, 0, w, h)
        s:DrawTextEntryText(C.text, C.acc, C.text)
        if s:GetText() == "" and not s:HasFocus() then
            draw.SimpleText(s:GetPlaceholderText() or "", "GRMBind_Small", 7, h / 2, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
    e.OnValueChange = function(_, v) if onChange then onChange(v) end end
    return e
end

-- Окно выбора пресета
local function openPresetPicker(onPick)
    local f = vgui.Create("DFrame")
    f:SetSize(560, 560) f:Center() f:MakePopup() f:ShowCloseButton(false) f:SetTitle("")
    f.Paint = function(_, w, h)
        draw.RoundedBox(7, 0, 0, w, h, C.bg)
        draw.RoundedBox(7, 0, 0, w, 44, C.head)
        surface.SetDrawColor(C.border.r, C.border.g, C.border.b, 255)
        surface.DrawOutlinedRect(0, 0, w, h)
        draw.SimpleText("ГОТОВЫЕ СЦЕНЫ", "GRMBind_Head", 16, 22, C.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    local close = vgui.Create("DButton", f)
    close:SetPos(f:GetWide() - 38, 8) close:SetSize(28, 28) close:SetText("✕")
    close:SetFont("GRMBind_Head") close:SetTextColor(C.dim)
    close.Paint = function(s, w, h) if s:IsHovered() then draw.RoundedBox(4, 0, 0, w, h, C.red) end end
    close.DoClick = function() f:Close() end

    local scroll = vgui.Create("DScrollPanel", f)
    scroll:Dock(FILL) scroll:DockMargin(12, 52, 12, 12)

    local lastGroup
    local soc = GRM.Social and GRM.Social.List
    if istable(soc) then
        for _, p in ipairs(soc) do
            if p.id then
                local hdrNeed = lastGroup ~= "Анимации"
                if hdrNeed then
                    lastGroup = "Анимации"
                    local hdr = vgui.Create("DLabel", scroll)
                    hdr:Dock(TOP) hdr:SetTall(24) hdr:DockMargin(0, 8, 0, 2)
                    hdr:SetFont("GRMBind_Small") hdr:SetTextColor(C.acc)
                    hdr:SetText("— АНИМАЦИИ")
                end
                local row = vgui.Create("DButton", scroll)
                row:Dock(TOP) row:SetTall(40) row:DockMargin(0, 0, 0, 4) row:SetText("")
                row.Paint = function(s, w, h)
                    draw.RoundedBox(6, 0, 0, w, h, s:IsHovered() and C.step or C.card)
                    draw.SimpleText(p.name or p.id, "GRMBind_Body", 12, h / 2, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end
                row.DoClick = function()
                    click()
                    onPick({ name = p.name or p.id, steps = { { mode = "anim", text = p.id, delay = 0 } } })
                    f:Close()
                end
            end
        end
    end
    for _, preset in ipairs(BD.Presets) do
        if preset.group ~= lastGroup then
            lastGroup = preset.group
            local hdr = vgui.Create("DLabel", scroll)
            hdr:Dock(TOP) hdr:SetTall(24) hdr:DockMargin(0, 8, 0, 2)
            hdr:SetFont("GRMBind_Small") hdr:SetTextColor(C.acc)
            hdr:SetText("— " .. string.upper(preset.group))
        end
        local row = vgui.Create("DButton", scroll)
        row:Dock(TOP) row:SetTall(46) row:DockMargin(0, 0, 0, 4) row:SetText("")
        row.Paint = function(s, w, h)
            draw.RoundedBox(6, 0, 0, w, h, s:IsHovered() and C.step or C.card)
            draw.SimpleText(preset.name, "GRMBind_Body", 12, 15, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(#preset.steps .. " шаг(ов): " .. tostring(preset.steps[1].text):sub(1, 58),
                "GRMBind_Small", 12, 32, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        row.DoClick = function()
            click()
            onPick(preset)
            f:Close()
        end
    end
end

function BD.Open()
    if IsValid(frame) then frame:Remove() end
    BD.Load()
    BD.Dirty = false

    frame = vgui.Create("DFrame")
    frame:SetSize(math.min(1120, ScrW() - 60), math.min(800, ScrH() - 60))
    frame:Center() frame:MakePopup() frame:ShowCloseButton(false) frame:SetTitle("")
    frame:SetDeleteOnClose(true)
    if GRM.UI and GRM.UI.Track then GRM.UI.Track("binder", frame) end

    frame.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, C.bg)
        draw.RoundedBox(8, 0, 0, w, 50, C.head)
        surface.SetDrawColor(C.border.r, C.border.g, C.border.b, C.border.a)
        surface.DrawOutlinedRect(0, 0, w, h)
        draw.SimpleText("БИНДЕР ДЕЙСТВИЙ", "GRMBind_Title", 18, 25, C.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Сцены из шагов • чат и консоль • паузы и последовательность • до " .. BD.MaxSlots .. " слотов",
            "GRMBind_Small", 240, 26, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    -- Закрытие на крестик: если правки не сохранены — спрашиваем, чтобы
    -- настройка часа не улетела в никуда.
    local function tryClose()
        if not BD.Dirty then frame:Close() return end
        Derma_Query("Есть несохранённые изменения биндов.", "БИНДЕР",
            "Сохранить и закрыть", function() BD.Save() frame:Close() end,
            "Закрыть без сохранения", function() BD.Load() frame:Close() end,
            "Отмена", function() end)
    end

    local close = vgui.Create("DButton", frame)
    close:SetPos(frame:GetWide() - 42, 10) close:SetSize(30, 30) close:SetText("✕")
    close:SetFont("GRMBind_Head") close:SetTextColor(C.dim)
    close.Paint = function(s, w, h) if s:IsHovered() then draw.RoundedBox(4, 0, 0, w, h, C.red) end end
    close.DoClick = tryClose

    local body = vgui.Create("DPanel", frame)
    body:Dock(FILL) body:DockMargin(12, 58, 12, 12) body:SetPaintBackground(false)

    -- ЗОЛОТИСТАЯ ПАМЯТКА (заказ владельца)
    local memo = vgui.Create("DPanel", body)
    memo:Dock(TOP) memo:SetTall(56) memo:DockMargin(0, 0, 0, 8)
    memo.Paint = function(_, w, h)
        draw.RoundedBox(6, 0, 0, w, h, C.goldBg)
        surface.SetDrawColor(C.gold.r, C.gold.g, C.gold.b, 220)
        surface.DrawOutlinedRect(0, 0, w, h, 2)
        draw.RoundedBox(2, 0, 0, 5, h, C.gold)
        draw.SimpleText("ПАМЯТКА", "GRMBind_Memo", 16, 16, C.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(MEMO, "GRMBind_Body", 16, 36, Color(250, 238, 205), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    -- ── ПАНЕЛЬ УПРАВЛЕНИЯ: сколько слотов и явное сохранение ────────
    local topBar = vgui.Create("DPanel", body)
    topBar:Dock(TOP) topBar:SetTall(56) topBar:DockMargin(0, 0, 0, 8)
    topBar.Paint = function(_, w, h)
        draw.RoundedBox(6, 0, 0, w, h, C.card)
        draw.SimpleText("НАСТРОЙКА БИНДОВ", "GRMBind_Head", 16, 18, C.acc, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Выберите число слотов, настройте сцены и нажмите «СОХРАНИТЬ» — изменения запишутся на диск.",
            "GRMBind_Small", 16, 38, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local countLbl = vgui.Create("DLabel", topBar)
    countLbl:SetPos(300, 16) countLbl:SetSize(120, 22)
    countLbl:SetFont("GRMBind_Small") countLbl:SetTextColor(C.dim) countLbl:SetText("Слотов в списке:")

    local function slotCount()
        local n = 0
        for i = 1, BD.MaxSlots do if BD.Slots[i] then n = i end end
        return n
    end

    local countW = vgui.Create("DNumberWang", topBar)
    countW:SetPos(410, 14) countW:SetSize(64, 26)
    countW:SetMin(1) countW:SetMax(BD.MaxSlots) countW:SetDecimals(0) countW:SetValue(slotCount())

    local saveBtn, dirtyLbl

    countW.OnValueChanged = function(_, v)
        local want = math.Clamp(math.floor(tonumber(v) or 1), 1, BD.MaxSlots)
        local have = slotCount()
        if want == have then return end
        if want > have then
            for i = have + 1, want do BD.Slots[i] = BD.Slots[i] or blankSlot(i) end
        else
            for i = want + 1, have do BD.Slots[i] = nil end
            -- Убираем из круга сектора, ссылающиеся на удалённые слоты.
            local kept = {}
            for _, id in ipairs(BD.Radial.items or {}) do
                if BD.Slots[id] then kept[#kept + 1] = id end
            end
            BD.Radial.items = kept
        end
        BD.MarkDirty()
        BD.RebuildMenu()
    end

    dirtyLbl = vgui.Create("DLabel", topBar)
    dirtyLbl:SetPos(492, 16) dirtyLbl:SetSize(300, 22)
    dirtyLbl:SetFont("GRMBind_Small") dirtyLbl:SetTextColor(C.gold)
    dirtyLbl:SetText("")
    dirtyLbl.Think = function(s)
        s:SetText(BD.Dirty and "● есть несохранённые изменения" or "все изменения сохранены")
        s:SetTextColor(BD.Dirty and C.gold or C.dim)
    end

    saveBtn = mkBtn(topBar, "СОХРАНИТЬ", C.green, function()
        BD.Save()
        chat.AddText(C.green, "[Биндер] ", C.text, "Настройки сохранены.")
    end)
    saveBtn:SetPos(topBar:GetWide() - 190, 13) saveBtn:SetSize(170, 30)
    saveBtn.Think = function(s)
        s:SetPos((s:GetParent():GetWide() or 0) - 190, 13)
        s.Label = BD.Dirty and "СОХРАНИТЬ ●" or "СОХРАНИТЬ"
    end

    -- ── РАДИАЛЬНОЕ МЕНЮ: одна клавиша на все сцены ──────────────────
    local radialCard = vgui.Create("DPanel", body)
    radialCard:Dock(TOP) radialCard:SetTall(96) radialCard:DockMargin(0, 0, 0, 8)
    radialCard.Paint = function(_, w, h)
        draw.RoundedBox(6, 0, 0, w, h, C.card)
        draw.RoundedBox(2, 0, 0, 4, h, C.violet)
        draw.SimpleText("РАДИАЛЬНОЕ МЕНЮ — ОДНА КЛАВИША НА ВСЁ", "GRMBind_Head", 16, 18, C.violet, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Держите клавишу — появится круг, наводите мышью нужный сектор (как в селекторе оружия) и отпускайте. Центр круга — отмена.",
            "GRMBind_Small", 16, 38, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local radKeyLbl = vgui.Create("DLabel", radialCard)
    radKeyLbl:SetPos(16, 60) radKeyLbl:SetSize(70, 22)
    radKeyLbl:SetFont("GRMBind_Small") radKeyLbl:SetTextColor(C.dim) radKeyLbl:SetText("Клавиша:")

    local radBinder = vgui.Create("DBinder", radialCard)
    radBinder:SetPos(78, 58) radBinder:SetSize(110, 26)
    radBinder:SetValue(BD.Radial.key or KEY_NONE)
    radBinder.OnChange = function(_, num)
        BD.Radial.key = math.floor(tonumber(num) or KEY_NONE)
        BD.MarkDirty()
    end

    local sectorsHost = vgui.Create("DPanel", radialCard)
    sectorsHost:SetPos(198, 56) sectorsHost:SetSize(860, 30) sectorsHost:SetPaintBackground(false)

    local rebuildRadial
    rebuildRadial = function()
        sectorsHost:Clear()
        local x = 0
        for i, id in ipairs(BD.Radial.items or {}) do
            local slot = BD.Slots[id]
            local btn = mkBtn(sectorsHost, i .. ". " .. (slot and tostring(slot.name) or ("Слот " .. id)), C.violet, function()
                table.remove(BD.Radial.items, i)
                BD.MarkDirty()
                rebuildRadial()
            end, "GRMBind_Small")
            btn:SetPos(x, 0) btn:SetSize(150, 26)
            btn:SetTooltip("Клик — убрать сектор из круга")
            x = x + 156
        end

        if #(BD.Radial.items or {}) < BD.MaxRadial then
            local add = vgui.Create("DComboBox", sectorsHost)
            add:SetPos(x, 2) add:SetSize(170, 22)
            add:SetFont("GRMBind_Small")
            add:SetValue("+ добавить сектор")
            for i = 1, BD.MaxSlots do
                local slot = BD.Slots[i]
                if slot then add:AddChoice("#" .. i .. " " .. tostring(slot.name or ""), i) end
            end
            add.OnSelect = function(_, _, _, id)
                id = math.floor(tonumber(id) or 0)
                if id <= 0 then return end
                BD.Radial.items[#BD.Radial.items + 1] = id
                BD.MarkDirty()
                rebuildRadial()
            end
        else
            local full = vgui.Create("DLabel", sectorsHost)
            full:SetPos(x, 4) full:SetSize(200, 22)
            full:SetFont("GRMBind_Small") full:SetTextColor(C.dim)
            full:SetText("круг заполнен (" .. BD.MaxRadial .. ")")
        end
    end
    rebuildRadial()

    local hint = vgui.Create("DPanel", body)
    hint:Dock(TOP) hint:SetTall(44) hint:DockMargin(0, 0, 0, 8)
    hint:SetTall(60)
    hint.Paint = function(_, w, h)
        draw.RoundedBox(6, 0, 0, w, h, C.card)
        draw.SimpleText("Шаг «в чат» — /me /do /dep. «В консоль» — act salute. «АНИМ» — поза из студии, кнопка «поза…» или сцена из пресетов.",
            "GRMBind_Small", 14, 14, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Пауза указывается ПЕРЕД шагом; между сообщениями в чат автоматически держится минимум " .. BD.MinChatGap .. " с, чтобы антифлуд не съел строки.",
            "GRMBind_Small", 14, 30, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Длина строки: до " .. BD.ChatLimit() .. " символов за сообщение. Длинный текст сам разобьётся по словам на несколько кусков (через чат режима — уходит целиком).",
            "GRMBind_Small", 14, 46, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local scroll = vgui.Create("DScrollPanel", body)
    scroll:Dock(FILL)

    local footer = vgui.Create("DPanel", body)
    footer:Dock(BOTTOM) footer:SetTall(40) footer:DockMargin(0, 8, 0, 0) footer:SetPaintBackground(false)

    local rebuild

    local function stepRow(parent, slot, idx)
        local step = slot.steps[idx]
        local row = vgui.Create("DPanel", parent)
        row:Dock(TOP) row:SetTall(32) row:DockMargin(28, 0, 0, 3)
        row.Paint = function(_, w, h)
            draw.RoundedBox(5, 0, 0, w, h, C.step)
            draw.RoundedBox(2, 0, 0, 3, h, step.enabled ~= false
                and (step.mode == "console" and C.violet or C.green) or C.off)
            draw.SimpleText(idx .. ".", "GRMBind_Small", 12, h / 2, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end

        local modeLabel = (step.mode == "console" and "КОНСОЛЬ") or (step.mode == "anim" and "АНИМ") or "ЧАТ"
        local modeCol = (step.mode == "console" and C.violet) or (step.mode == "anim" and C.gold) or C.green
        local modeBtn = mkBtn(row, modeLabel, modeCol, function()
            step.mode = (step.mode == "chat" and "console") or (step.mode == "console" and "anim") or "chat"
            BD.MarkDirty() rebuild()
        end)
        modeBtn:SetPos(32, 4) modeBtn:SetSize(90, 24)

        local textW = (step.mode == "anim") and 400 or 520
        local text = mkEntry(row,
            (step.mode == "console" and "act salute") or (step.mode == "anim" and "id позы из студии") or "/me поправляет фуражку",
            step.text, function(v) step.text = v BD.MarkDirty() end)
        text:SetPos(128, 4) text:SetSize(textW, 24)

        if step.mode == "anim" then
            local pick = mkBtn(row, "поза…", C.gold, function()
                local pf = vgui.Create("DFrame")
                pf:SetSize(360, 420) pf:Center() pf:MakePopup() pf:SetTitle("")
                pf.Paint = function(_, w, h)
                    draw.RoundedBox(7, 0, 0, w, h, C.bg)
                    draw.SimpleText("ПОЗА В СЛОТ", "GRMBind_Head", 14, 18, C.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end
                local sc = vgui.Create("DScrollPanel", pf)
                sc:Dock(FILL) sc:DockMargin(10, 40, 10, 10)
                local last
                local poses = (GRM.Social and GRM.Social.List) or {}
                local cats = (GRM.Social and GRM.Social.Categories and GRM.Social.Categories()) or {}
                local byCat = {}
                for _, p in ipairs(poses) do
                    local c = tostring(p.cat or "general")
                    byCat[c] = byCat[c] or {}
                    byCat[c][#byCat[c] + 1] = p
                end
                local function addHdr(title)
                    local hdr = vgui.Create("DLabel", sc)
                    hdr:Dock(TOP) hdr:SetTall(20) hdr:SetFont("GRMBind_Small") hdr:SetTextColor(C.acc)
                    hdr:SetText(string.upper(title or ""))
                end
                if #cats == 0 then addHdr("Общее") end
                local function dump(list)
                    for _, p in ipairs(list or {}) do
                        local b = vgui.Create("DButton", sc)
                        b:Dock(TOP) b:SetTall(28) b:DockMargin(0, 0, 0, 3) b:SetText("")
                        b.Paint = function(s, w, h)
                            draw.RoundedBox(4, 0, 0, w, h, s:IsHovered() and C.acc or C.card)
                            draw.SimpleText(p.name or p.id, "GRMBind_Body", 10, h / 2, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                        end
                        b.DoClick = function()
                            step.text = p.id
                            BD.MarkDirty()
                            pf:Close()
                            rebuild()
                        end
                    end
                end
                if #cats > 0 then
                    for _, cat in ipairs(cats) do
                        addHdr(cat.name)
                        dump(byCat[cat.id])
                    end
                else
                    dump(poses)
                end
                local stop = vgui.Create("DButton", sc)
                stop:Dock(TOP) stop:SetTall(26) stop:SetText("снять позу (stop)")
                stop.DoClick = function() step.text = "stop" BD.MarkDirty() pf:Close() rebuild() end
            end)
            pick:SetPos(534, 4) pick:SetSize(114, 24)
        end

        local delayLbl = vgui.Create("DLabel", row)
        delayLbl:SetPos(656, 6) delayLbl:SetSize(50, 20)
        delayLbl:SetFont("GRMBind_Small") delayLbl:SetTextColor(C.dim) delayLbl:SetText("пауза")

        local delay = vgui.Create("DNumberWang", row)
        delay:SetPos(700, 5) delay:SetSize(58, 22)
        delay:SetMin(0) delay:SetMax(60) delay:SetDecimals(1) delay:SetValue(step.delay or 0)
        delay.OnValueChanged = function(_, v) step.delay = tonumber(v) or 0 BD.MarkDirty() end

        local up = mkBtn(row, "▲", C.off, function()
            if idx > 1 then
                slot.steps[idx], slot.steps[idx - 1] = slot.steps[idx - 1], slot.steps[idx]
                BD.MarkDirty() rebuild()
            end
        end)
        up:SetPos(768, 4) up:SetSize(26, 24)

        local down = mkBtn(row, "▼", C.off, function()
            if idx < #slot.steps then
                slot.steps[idx], slot.steps[idx + 1] = slot.steps[idx + 1], slot.steps[idx]
                BD.MarkDirty() rebuild()
            end
        end)
        down:SetPos(798, 4) down:SetSize(26, 24)

        local onBtn = mkBtn(row, step.enabled ~= false and "вкл" or "выкл",
            step.enabled ~= false and C.green or C.off, function()
                step.enabled = not (step.enabled ~= false)
                BD.MarkDirty() rebuild()
            end)
        onBtn:SetPos(828, 4) onBtn:SetSize(52, 24)

        local del = mkBtn(row, "✕", C.red, function()
            table.remove(slot.steps, idx)
            if #slot.steps == 0 then slot.steps[1] = blankStep() end
            BD.MarkDirty() rebuild()
        end)
        del:SetPos(884, 4) del:SetSize(26, 24)
    end

    local function slotCard(slot)
        local steps = slot.steps or {}
        local card = vgui.Create("DPanel", scroll)
        card:Dock(TOP) card:SetTall(74 + #steps * 35 + 38) card:DockMargin(0, 0, 0, 8)
        card.Paint = function(_, w, h)
            draw.RoundedBox(6, 0, 0, w, h, C.card)
            draw.RoundedBox(2, 0, 0, 4, h, slot.enabled and C.acc or C.off)
            draw.SimpleText("#" .. slot.id, "GRMBind_Small", 14, 20, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end

        local name = mkEntry(card, "название сцены", slot.name, function(v) slot.name = v BD.MarkDirty() end)
        name:SetPos(46, 10) name:SetSize(220, 26)

        local keyLbl = vgui.Create("DLabel", card)
        keyLbl:SetPos(276, 12) keyLbl:SetSize(60, 22)
        keyLbl:SetFont("GRMBind_Small") keyLbl:SetTextColor(C.dim) keyLbl:SetText("Клавиша:")

        local binder = vgui.Create("DBinder", card)
        binder:SetPos(338, 10) binder:SetSize(110, 26)
        binder:SetValue(slot.key or KEY_NONE)
        binder.OnChange = function(_, num) slot.key = math.floor(tonumber(num) or KEY_NONE) BD.MarkDirty() end

        local startLbl = vgui.Create("DLabel", card)
        startLbl:SetPos(458, 12) startLbl:SetSize(70, 22)
        startLbl:SetFont("GRMBind_Small") startLbl:SetTextColor(C.dim) startLbl:SetText("старт, с")

        local startW = vgui.Create("DNumberWang", card)
        startW:SetPos(516, 11) startW:SetSize(56, 24)
        startW:SetMin(0) startW:SetMax(60) startW:SetDecimals(1) startW:SetValue(slot.delay or 0)
        startW.OnValueChanged = function(_, v) slot.delay = tonumber(v) or 0 BD.MarkDirty() end

        local cdLbl = vgui.Create("DLabel", card)
        cdLbl:SetPos(582, 12) cdLbl:SetSize(70, 22)
        cdLbl:SetFont("GRMBind_Small") cdLbl:SetTextColor(C.dim) cdLbl:SetText("кулдаун")

        local cdW = vgui.Create("DNumberWang", card)
        cdW:SetPos(640, 11) cdW:SetSize(56, 24)
        cdW:SetMin(0) cdW:SetMax(60) cdW:SetDecimals(1) cdW:SetValue(slot.cooldown or 0.5)
        cdW.OnValueChanged = function(_, v) slot.cooldown = tonumber(v) or 0 BD.MarkDirty() end

        local onBtn = mkBtn(card, slot.enabled and "ВКЛ" or "ВЫКЛ", slot.enabled and C.green or C.off, function()
            slot.enabled = not slot.enabled BD.MarkDirty() rebuild()
        end)
        onBtn:SetPos(706, 10) onBtn:SetSize(64, 26)

        local testBtn = mkBtn(card, "Проверить", C.acc, function() BD.Run(slot.id, 1, {}, true) end)
        testBtn:SetPos(776, 10) testBtn:SetSize(92, 26)

        local presetBtn = mkBtn(card, "Сцена…", C.gold, function()
            openPresetPicker(function(preset)
                slot.name = preset.name
                slot.steps = {}
                for _, st in ipairs(preset.steps) do
                    slot.steps[#slot.steps + 1] = {
                        mode = st.mode, text = st.text, delay = st.delay or 0, enabled = true,
                    }
                end
                BD.MarkDirty() rebuild()
            end)
        end)
        presetBtn:SetPos(874, 10) presetBtn:SetSize(84, 26)

        local clearBtn = mkBtn(card, "Очистить", C.red, function()
            BD.Slots[slot.id] = blankSlot(slot.id)
            BD.MarkDirty() rebuild()
        end)
        clearBtn:SetPos(964, 10) clearBtn:SetSize(88, 26)

        local stepsHost = vgui.Create("DPanel", card)
        stepsHost:SetPos(0, 44) stepsHost:SetSize(card:GetWide(), #steps * 35 + 34)
        stepsHost:SetPaintBackground(false)
        stepsHost.PerformLayout = function(s) s:SetWide((s:GetParent():GetWide() or 0)) end

        for i = 1, #steps do stepRow(stepsHost, slot, i) end

        local addStep = mkBtn(stepsHost, "+ шаг", C.off, function()
            if #slot.steps >= BD.MaxSteps then
                chat.AddText(C.red, "[Биндер] ", C.text, "В сцене не больше " .. BD.MaxSteps .. " шагов.")
                return
            end
            slot.steps[#slot.steps + 1] = blankStep()
            BD.MarkDirty() rebuild()
        end)
        addStep:Dock(TOP) addStep:SetTall(26) addStep:DockMargin(28, 4, 620, 0)

        local chainLbl = vgui.Create("DLabel", card)
        chainLbl:SetPos(28, card:GetTall() - 30) chainLbl:SetSize(120, 20)
        chainLbl:SetFont("GRMBind_Small") chainLbl:SetTextColor(C.dim) chainLbl:SetText("Затем запустить слот:")

        local chainCombo = vgui.Create("DComboBox", card)
        chainCombo:SetPos(160, card:GetTall() - 32) chainCombo:SetSize(170, 22)
        chainCombo:SetFont("GRMBind_Small")
        chainCombo:AddChoice("— нет —", 0, (slot.chain or 0) == 0)
        for i = 1, BD.MaxSlots do
            local other = BD.Slots[i]
            if other and i ~= slot.id then
                chainCombo:AddChoice("#" .. i .. " " .. tostring(other.name or ""), i, slot.chain == i)
            end
        end
        chainCombo.OnSelect = function(_, _, _, id) slot.chain = math.floor(tonumber(id) or 0) BD.MarkDirty() end

        local chainDelayLbl = vgui.Create("DLabel", card)
        chainDelayLbl:SetPos(342, card:GetTall() - 30) chainDelayLbl:SetSize(110, 20)
        chainDelayLbl:SetFont("GRMBind_Small") chainDelayLbl:SetTextColor(C.dim) chainDelayLbl:SetText("через, с")

        local chainDelay = vgui.Create("DNumberWang", card)
        chainDelay:SetPos(404, card:GetTall() - 32) chainDelay:SetSize(56, 22)
        chainDelay:SetMin(0) chainDelay:SetMax(60) chainDelay:SetDecimals(1)
        chainDelay:SetValue(slot.chainDelay or 1)
        chainDelay.OnValueChanged = function(_, v) slot.chainDelay = tonumber(v) or 0 BD.MarkDirty() end
    end

    rebuild = function()
        local keep = 0
        if IsValid(scroll) and IsValid(scroll.VBar) then keep = scroll.VBar:GetScroll() end
        scroll:Clear()
        for i = 1, BD.MaxSlots do
            if BD.Slots[i] then slotCard(BD.Slots[i]) end
        end
        if keep > 0 then
            timer.Simple(0, function()
                if IsValid(scroll) and IsValid(scroll.VBar) then scroll.VBar:SetScroll(keep) end
            end)
        end
    end
    BD.RebuildMenu = function()
        if IsValid(frame) then rebuild() if rebuildRadial then rebuildRadial() end end
    end
    rebuild()

    local addBtn = mkBtn(footer, "+ ДОБАВИТЬ СЛОТ", C.acc, function()
        local n = 0
        for i = 1, BD.MaxSlots do if BD.Slots[i] then n = i end end
        if n >= BD.MaxSlots then
            chat.AddText(C.red, "[Биндер] ", C.text, "Достигнут предел в " .. BD.MaxSlots .. " слотов.")
            return
        end
        BD.Slots[n + 1] = blankSlot(n + 1)
        BD.MarkDirty() rebuild()
    end)
    addBtn:Dock(LEFT) addBtn:SetWide(190)

    local stopBtn = mkBtn(footer, "СТОП (сбросить отложенные)", C.red, function()
        local n = BD.StopAll()
        chat.AddText(C.gold, "[Биндер] ", C.text, "Отменено отложенных шагов: " .. n)
    end)
    stopBtn:Dock(LEFT) stopBtn:SetWide(250) stopBtn:DockMargin(8, 0, 0, 0)

    local infoLbl = vgui.Create("DLabel", footer)
    infoLbl:Dock(FILL) infoLbl:DockMargin(12, 0, 12, 0)
    infoLbl:SetFont("GRMBind_Small") infoLbl:SetTextColor(C.dim)
    infoLbl:SetText("Сохраняется автоматически в data/grm_binder.json. Бинды молчат, когда открыт чат, консоль или меню.")

    local closeBtn = mkBtn(footer, "ЗАКРЫТЬ", C.off, function() tryClose() end)
    closeBtn:Dock(RIGHT) closeBtn:SetWide(130)
end

-----------------------------------------------------------------------
-- Точки входа
-----------------------------------------------------------------------
concommand.Add("grm_binder", function() BD.Open() end)
concommand.Add("grm_binder_stop", function() BD.StopAll() end)

-- Открытие приходит с сервера: он же проглатывает команду из чата, поэтому
-- «/binder» не улетает всем в общий чат.
net.Receive("GRM_Binder_Open", function() BD.Open() end)

BD.Load()

print("[GRM Binder] v" .. BD.Version .. ": сцены из шагов, пресеты, /binder /autobinder /rpbinder")

-- Вечер-18: команда разбирается внутри парсера модуля (не литералом в
-- хуке) — регистрируем её множество в едином внешнем словаре библиотеки,
-- иначе на режиме она стала бы «неизвестной» до цепочки.
if GRM and GRM.Chat and GRM.Chat.RegisterExternalCommands then
    GRM.Chat.RegisterExternalCommands({ "/autobinder", "/binder", "/myid", "/mylicense", "/mypasport", "/rpbinder", "/showbadge", "/showmedcard", "/showmilitary", "/showpassport", "/showprava", "/биндер", "/бинды" })
end
