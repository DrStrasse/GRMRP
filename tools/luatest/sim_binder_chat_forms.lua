--[[--------------------------------------------------------------------
    sim_binder_chat_forms — три заказа владельца:
      1) текст в форме регистрации организации не исчезает при автосинке;
      2) /dep и /fr выводятся так же, как /gnews (шапка + перенос строки);
      3) биндер действий: /binder, /autobinder, /rpbinder.

    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_binder_chat_forms.lua
----------------------------------------------------------------------]]
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

local ui       = read("lua/autorun/client/cl_grm_factions_unified_ui.lua")
local factions = read("lua/autorun/sh_factions.lua")
local binder   = read("lua/autorun/sh_grm_binder.lua")

print("\n=== 1. ФОРМА РЕГИСТРАЦИИ: ТЕКСТ НЕ ИСЧЕЗАЕТ ===")
ok(ui:find("local function hasActiveInput", 1, true) ~= nil,
    "определяется, что пользователь сейчас печатает")
ok(ui:find("pendingRefreshData = data", 1, true) ~= nil,
    "автосинк во время ввода откладывается, а не рушит панель")
ok(ui:find('hook.Add("Think", "GRM_FactionUnified_PendingRefresh"', 1, true) ~= nil,
    "отложенное обновление применяется, когда ввод закончен")
ok(ui:find("local function bindFormField", 1, true) ~= nil,
    "поля формы помечаются и переживают пересборку")
ok(ui:find('bindFormField(entKey, "create.key")', 1, true) ~= nil
    and ui:find('bindFormField(entDisp, "create.display")', 1, true) ~= nil
    and ui:find('bindFormField(entTag, "create.tag")', 1, true) ~= nil,
    "все три поля регистрации организации защищены")
ok(ui:find("local function collectFormValues", 1, true) ~= nil, "значения собираются перед Clear")
ok(ui:find('formValues["create.key"], formValues["create.display"], formValues["create.tag"] = nil, nil, nil', 1, true) ~= nil,
    "после создания организации черновик очищается")
ok(ui:find("local function rebuildCurrentTab", 1, true) ~= nil,
    "единая точка пересборки вкладки (со скроллом и значениями)")
ok(ui:find("lastTypedAt = RealTime()", 1, true) ~= nil,
    "пауза после последнего нажатия клавиши учитывается")

print("\n=== 2. /dep И /fr КАК /gnews ===")
ok(factions:find("local function printChannel", 1, true) ~= nil, "единый вывод служебных каналов")
ok(factions:find('tagColor, "[" .. tostring(tag or "") .. "]\\n"', 1, true) ~= nil,
    "после тэга идёт перенос строки — как в /gnews")
ok(factions:find('bodyColor, tostring(name or "")', 1, true) ~= nil,
    "имя, должность и текст рисуются единым цветом канала (заказ 18.08)")
ok(factions:find('printChannel("[Рация] "', 1, true) ~= nil, "/fr использует общий вывод")
ok(factions:find('printChannel("[Волна] "', 1, true) ~= nil, "/dep использует общий вывод")
ok(factions:find('printChannel("[Волна OOC] "', 1, true) ~= nil, "/depb тоже приведён к общему виду")
ok(factions:find('local msg = string.format("[%s] %s (%s): %s", tag, ply:Nick()', 1, true) == nil,
    "старая склейка всего в одну строку убрана из /fr")
ok(factions:find('local msgText = string.format("[%s] %s (%s): - %s"', 1, true) == nil,
    "старая склейка убрана из /dep")
ok(factions:find('local rpName = ply:GetNWString("GRM_RPName", "")', 1, true) ~= nil,
    "в канал уходит RP-имя, а не ник Steam (как в /gnews)")
ok(factions:find("GRM.Factions.RoleDisplayName", 1, true) ~= nil,
    "должность показывается публичным названием")
ok(select(2, factions:gsub("net%.WriteString%(tag%)", "")) >= 1
    and select(2, factions:gsub("net%.WriteString%(displayTag%)", "")) >= 2,
    "сервер шлёт поля раздельно (тэг, имя, должность, текст)")

print("\n=== 3. БИНДЕР ДЕЙСТВИЙ (v2: сцены из шагов) ===")
ok(binder:find('GRM.Binder', 1, true) ~= nil and binder:find('BD.Version = "2.2.0"', 1, true) ~= nil,
    "модуль GRM.Binder v2.2.0")
ok(binder:find("BD.MaxSlots      = 40", 1, true) ~= nil and binder:find("BD.MaxSteps      = 16", 1, true) ~= nil,
    "до 40 слотов, до 16 шагов в сцене")
ok(binder:find('["/binder"] = true', 1, true) ~= nil
    and binder:find('["/autobinder"] = true', 1, true) ~= nil
    and binder:find('["/rpbinder"] = true', 1, true) ~= nil,
    "все три команды: /binder, /autobinder, /rpbinder")
ok(binder:find('concommand.Add("grm_binder"', 1, true) ~= nil, "консольная команда")
ok(binder:find('hook.Add("PlayerSay", "GRM_Binder_Chat"', 1, true) ~= nil
    and binder:find('hook.Add("PlayerSay", "GRM_Binder_ChatEC"', 1, true) ~= nil,
    "команда ловится на сервере (боевой PlayerSay + реестр) — в общий чат не улетает")
ok(binder:find("EasyChat.SendGlobalMessage", 1, true) == nil,
    "EasyChat вырезан и из биндера (указание владельца; вечер-12)")
ok(binder:find("ns.SendText(part)", 1, true) ~= nil,
    "шаг «в чат» идёт через SendText чата режима — эхо автора, форматер /me, история ввода")
ok(binder:find("function BD.UnknownChatCommand", 1, true) ~= nil
    and binder:find("RPCommandNames", 1, true) ~= nil,
    "словарь /me-подобных команд — из реестра чата, не свой домысел (вечер-12)")
ok(binder:find("RegisterExternalChatCommand", 1, true) ~= nil,
    "свои команды биндер регистрирует в чате: «/binder» открывается и из GRM-ввода")

print("\n=== 3b. ЧАТ ↔ БИНДЕР: СЕРВЕРНЫЙ МАРШРУТ (вечер-12) ===")
local sv = read("lua/grm_chat/sv_net.lua")
ok(sv:find("GRMRPChat._inExternal = true", 1, true) ~= nil
    and sv:find('hook.Run, "PlayerSay"', 1, true) ~= nil,
    "ProcessLine отдаёт внешние /команды цепочке PlayerSay (маршрут из net-канала)")
local ini = read("gamemodes/grmrp/gamemode/init.lua")
ok(ini:find('if GRMRPChat._inExternal then return "" end', 1, true) ~= nil,
    "ре-ентерь guard GM:PlayerSay — маршрутизация не зацикливается")
local core = read("lua/grm_chat/sh_core.lua")
ok(core:find("function GRMRPChat.RegisterExternalChatCommand", 1, true) ~= nil
    and core:find("function GRMRPChat.RPCommandNames", 1, true) ~= nil,
    "ядро чата держит реестр внешних команд и словарь RP")
local cli = read("lua/grm_chat/cl_input.lua")
ok(cli:find("GRMRPChat.SendText = send", 1, true) ~= nil,
    "чат экспортирует SendText — общий путь отправки для модулей")
ok(cli:find('RunConsoleCommand("say", text)', 1, true) ~= nil,
    "внешние команды из ввода идут через say (перехватчики аддонов видят их)")
local hud = read("lua/autorun/client/cl_grm_hud.lua")
ok(hud:find("grm_money_diag", 1, true) ~= nil,
    "grm_money_diag — различимы «данные не приходят» и «данные есть, но не видно»")
ok(binder:find('RunConsoleCommand("say", part)', 1, true) ~= nil
    and binder:find("function BD.SplitChat", 1, true) ~= nil,
    "без EasyChat текст режется по словам на куски, влезающие в say")
ok(binder:find('LocalPlayer():ConCommand(text .. "\\n")', 1, true) ~= nil, "шаг «в консоль» выполняет команду")
ok(binder:find("DBinder", 1, true) ~= nil, "клавиша выбирается стандартным биндером")
ok(binder:find("local function normalizeSlot", 1, true) ~= nil
    and binder:find("-- миграция v1 → v2", 1, true) ~= nil,
    "старые однодейственные бинды мигрируют в шаги")
ok(binder:find("BD.MinChatGap", 1, true) ~= nil,
    "между сообщениями в чат держится минимальная пауза (антифлуд)")
ok(binder:find("slot.chain", 1, true) ~= nil and binder:find("chainDelay", 1, true) ~= nil,
    "связка со следующим слотом")
ok(binder:find("BD.MaxChainDepth", 1, true) ~= nil and binder:find("visited[index]", 1, true) ~= nil,
    "цепочка защищена от зацикливания")
ok(binder:find("function BD.StopAll", 1, true) ~= nil and binder:find("СТОП (сбросить отложенные)", 1, true) ~= nil,
    "есть аварийная остановка отложенных шагов")
ok(binder:find("local function inputBusy", 1, true) ~= nil and binder:find("lp:IsTyping()", 1, true) ~= nil,
    "бинды молчат, пока открыт чат/консоль/меню")
ok(binder:find("function BD.RebuildKeyMap", 1, true) ~= nil and binder:find("BD.KeyMap[key]", 1, true) ~= nil,
    "нажатие смотрит в таблицу клавиш, а не перебирает слоты")
ok(binder:find("file.Write(BD.File, util.TableToJSON({", 1, true) ~= nil
    and binder:find("slots = arr,", 1, true) ~= nil,
    "сохранение слотов и круга в data/grm_binder.json")
ok(binder:find("▲", 1, true) ~= nil and binder:find("▼", 1, true) ~= nil,
    "порядок шагов меняется стрелками")

print("\n=== 3.1 ПАМЯТКА И ПРЕСЕТЫ ===")
ok(binder:find("БИНДЕР служит упрощением отыгровки монотонных механик", 1, true) ~= nil
    and binder:find("не может служить заменой полноценной отыгровки РП процесса!", 1, true) ~= nil,
    "памятка владельца присутствует дословно")
ok(binder:find("C.goldBg", 1, true) ~= nil and binder:find('draw.SimpleText("ПАМЯТКА"', 1, true) ~= nil,
    "памятка оформлена золотистой табличкой")
ok(binder:find("BD.Presets = {", 1, true) ~= nil, "есть готовые сцены-пресеты")
ok(binder:find('group = "Документы"', 1, true) ~= nil, "пресеты по документам")
ok(binder:find("/showbadge", 1, true) ~= nil and binder:find("/showpassport", 1, true) ~= nil
    and binder:find("/showprava", 1, true) ~= nil and binder:find("/showmedcard", 1, true) ~= nil,
    "команды показа документов подставлены реальные")
ok(binder:find('group = "Служебные каналы"', 1, true) ~= nil
    and binder:find("/dep Займу гос.волну", 1, true) ~= nil
    and binder:find("/gnews", 1, true) ~= nil,
    "пресет объявления по гос.волне из примера владельца")
ok(binder:find("/me исполнил воинское приветствие", 1, true) ~= nil
    and binder:find("act salute", 1, true) ~= nil,
    "пресет «воинское приветствие»: чат + консоль")
ok(binder:find("/frb", 1, true) ~= nil, "в пресетах учтён новый канал /frb")
ok(binder:find("local function openPresetPicker", 1, true) ~= nil, "окно выбора сцены")

print("\n=== 4. ЖИВОЙ ПРОГОН БИНДЕРА ===")
local stub = dofile("tools/luatest/lib_gmod_stub.lua")
stub.install()
stub.reset()
_G.CLIENT, _G.SERVER = true, false
_G.KEY_NONE = 0
_G.KEY_F = 26
_G.RealTime = function() return stub.time or 0 end
_G.chat = { AddText = function() end }
_G.gui = { IsGameUIVisible = function() return false end, IsConsoleVisible = function() return false end }
_G.vgui.CursorVisible = function() return false end
_G.surface.CreateFont = function() end
_G.color_white = { r = 255, g = 255, b = 255 }
_G.TEXT_ALIGN_LEFT, _G.TEXT_ALIGN_CENTER, _G.TEXT_ALIGN_RIGHT = 0, 1, 2

local saved = nil
_G.file.Write = function(_, data) saved = data end
_G.file.Read = function() return saved end
-- Мини-сериализация для стенда: сохраняем слоты вместе с их шагами.
_G.util.TableToJSON = function(t)
    local parts = {}
    for _, row in ipairs(t or {}) do
        local steps = {}
        for _, st in ipairs(row.steps or {}) do
            steps[#steps + 1] = table.concat({
                tostring(st.mode or "chat"), tostring(st.text or ""),
                tostring(st.delay or 0), tostring(st.enabled ~= false),
            }, "\3")
        end
        parts[#parts + 1] = table.concat({
            tostring(row.id or 0), tostring(row.name or ""), tostring(row.key or 0),
            tostring(row.chain or 0), table.concat(steps, "\4"),
        }, "\1")
    end
    return table.concat(parts, "\2")
end
_G.util.JSONToTable = function(raw)
    if not raw or raw == "" then return nil end
    local out = {}
    for chunk in string.gmatch(raw, "([^\2]+)") do
        local f = {}
        for piece in string.gmatch(chunk .. "\1", "([^\1]*)\1") do f[#f + 1] = piece end
        local steps = {}
        for st in string.gmatch(tostring(f[5] or ""), "([^\4]+)") do
            local sf = {}
            for piece in string.gmatch(st .. "\3", "([^\3]*)\3") do sf[#sf + 1] = piece end
            steps[#steps + 1] = { mode = sf[1], text = sf[2], delay = tonumber(sf[3]) or 0, enabled = sf[4] ~= "false" }
        end
        out[#out + 1] = {
            id = tonumber(f[1]), name = f[2], key = tonumber(f[3]),
            chain = tonumber(f[4]), steps = steps,
        }
    end
    return out
end

local sentSay, sentCon = {}, {}
_G.RunConsoleCommand = function(cmd, arg) if cmd == "say" then sentSay[#sentSay + 1] = arg end end
local lp = stub.makeEntity({ class = "player", isPlayer = true })
lp.ConCommand = function(_, cmd) sentCon[#sentCon + 1] = cmd end
lp.IsTyping = function() return false end
_G.LocalPlayer = function() return lp end

local loaded, err = stub.loadModule("lua/autorun/sh_grm_binder.lua")
ok(loaded, "биндер поднялся в моке", err)
local BD = _G.GRM and _G.GRM.Binder
ok(BD and #BD.Slots >= 20, "создано 20 пустых слотов", BD and #BD.Slots)

-- Сцена #1: чат + консоль (пример владельца — приветствие)
BD.Slots[1].key = KEY_F
BD.Slots[1].cooldown = 0.5
BD.Slots[1].steps = {
    { mode = "chat",    text = "/me исполнил воинское приветствие", delay = 0, enabled = true },
    { mode = "console", text = "act salute",                        delay = 0, enabled = true },
}
BD.Save()

ok(BD.KeyMap[KEY_F] ~= nil and BD.KeyMap[KEY_F][1] == 1, "слот попал в таблицу клавиш")

stub.time = 100
_G.hook.Run("PlayerButtonDown", lp, KEY_F)
for _ = 1, 6 do stub.runTimers() end
ok(sentSay[1] == "/me исполнил воинское приветствие", "шаг «в чат» ушёл через say", sentSay[1])
ok(sentCon[1] == "act salute\n", "шаг «в консоль» выполнился", sentCon[1])

-- кулдаун
local before = #sentSay
_G.hook.Run("PlayerButtonDown", lp, KEY_F)
ok(#sentSay == before, "повторное нажатие внутри кулдауна игнорируется")

-- ввод занят
stub.time = 200
lp.IsTyping = function() return true end
_G.hook.Run("PlayerButtonDown", lp, KEY_F)
ok(#sentSay == before, "во время печати в чат бинд не срабатывает")
lp.IsTyping = function() return false end

-- Сцена из пяти строк /gnews: порядок и паузы
sentSay, sentCon = {}, {}
local scheduled = {}
_G.timer.Create = function(id, delay, reps, fn)
    scheduled[#scheduled + 1] = { at = delay, fn = fn }
    stub.timers[id] = { at = (stub.time or 0) + delay, fn = fn, reps = reps }
end
BD.Slots[3] = BD.BlankSlot(3)
BD.Slots[3].cooldown = 0
BD.Slots[3].steps = {
    { mode = "chat", text = "/dep Займу гос.волну, просьба не перебивать!", delay = 0, enabled = true },
    { mode = "chat", text = "/gnews Строка 1", delay = 2, enabled = true },
    { mode = "chat", text = "/gnews Строка 2", delay = 4, enabled = true },
    { mode = "chat", text = "/gnews Строка 3", delay = 4, enabled = true },
    { mode = "chat", text = "/gnews Финал",   delay = 3, enabled = true },
}
stub.time = 300
BD.Run(3, 1, {}, true)
ok(sentSay[1] == "/dep Займу гос.волну, просьба не перебивать!", "первый шаг сцены уходит сразу", sentSay[1])
ok(#scheduled == 4, ("остальные 4 строки поставлены в очередь с паузами: %d"):format(#scheduled))
local growing = true
for i = 2, #scheduled do if scheduled[i].at <= scheduled[i - 1].at then growing = false end end
ok(growing, "паузы накапливаются — строки идут по очереди, а не пачкой")
ok(math.abs(scheduled[1].at - 2) < 0.01 and math.abs(scheduled[4].at - 13) < 0.01,
    ("тайминги верные: %.1f и %.1f"):format(scheduled[1].at, scheduled[4].at))
for _, t in ipairs(scheduled) do t.fn() end
ok(#sentSay == 5 and sentSay[5] == "/gnews Финал", "вся сцена отыграна по порядку", sentSay[5])

-- отключённый шаг пропускается
sentSay = {}
scheduled = {}
BD.Slots[3].steps[2].enabled = false
stub.time = 400
BD.Run(3, 1, {}, true)
for _, t in ipairs(scheduled) do t.fn() end
local hasDisabled = false
for _, msg in ipairs(sentSay) do if msg == "/gnews Строка 1" then hasDisabled = true end end
ok(not hasDisabled and #sentSay == 4, "выключенный шаг не выполняется", #sentSay)

-- минимальная пауза между сообщениями в чат (антифлуд)
sentSay = {}
scheduled = {}
BD.Slots[4] = BD.BlankSlot(4)
BD.Slots[4].cooldown = 0
BD.Slots[4].steps = {
    { mode = "chat", text = "первое",  delay = 0, enabled = true },
    { mode = "chat", text = "второе",  delay = 0, enabled = true },
    { mode = "chat", text = "третье",  delay = 0, enabled = true },
}
stub.time = 500
BD.Run(4, 1, {}, true)
ok(#scheduled == 2 and scheduled[1].at >= BD.MinChatGap - 0.001,
    ("подряд идущие сообщения разведены минимум на %.1f с"):format(BD.MinChatGap))

-- аварийная остановка
scheduled = {}
stub.time = 600
BD.Run(3, 1, {}, true)
local stopped = BD.StopAll()
ok(stopped > 0, "СТОП снимает отложенные шаги", stopped)

-- защита от зацикливания слотов
-- (сначала гасим всё, что осталось от предыдущих сцен, иначе в счёт попадут
--  их отложенные шаги, а не результат цепочки)
BD.StopAll()
stub.timers = {}
scheduled = {}
sentSay, sentCon = {}, {}
BD.Slots[1].chain = 2 BD.Slots[2] = BD.BlankSlot(2) BD.Slots[2].chain = 1
BD.Slots[1].cooldown = 0 BD.Slots[2].cooldown = 0
BD.Slots[1].chainDelay = 0 BD.Slots[2].chainDelay = 0
BD.Slots[2].steps = { { mode = "chat", text = "второй", delay = 0, enabled = true } }
stub.time = 700
BD.Run(1, 1, {}, true)
for _ = 1, 12 do stub.runTimers() end
ok(#sentSay <= 3, ("цепочка слотов не зациклилась: %d действий"):format(#sentSay))


print("\n=== 5. КАНАЛЫ /db, /depb и НОВЫЙ /frb ===")
ok(factions:find('lower:find("^/depb%s+")', 1, true) ~= nil
    and factions:find('lower:find("^/db%s+")', 1, true) ~= nil,
    "/depb и /db на месте")
ok(select(2, factions:gsub("net%.Start%(NET_DEPB%)", "")) == 2,
    "обе команды идут в один канал NET_DEPB — значит формат общий")
ok(factions:find('local NET_RADIOB              = "Factions_RadioOOC"', 1, true) ~= nil,
    "добавлен канал фракционной рации НОН-РП (/frb)")
ok(factions:find("util.AddNetworkString(NET_RADIOB)", 1, true) ~= nil
    and factions:find("util.AddNetworkString(NET_RADIOB_MSG)", 1, true) ~= nil,
    "сетевые строки /frb зарегистрированы")
ok(factions:find("net.Receive(NET_RADIOB, function(_, ply)", 1, true) ~= nil,
    "серверный приёмник /frb")
ok(factions:find('lower:find("^/frb%s+") == 1 or lower:find("^/frooc%s+") == 1', 1, true) ~= nil,
    "команды /frb и /frooc ловятся в чате")
ok(factions:find('printChannel("[Рация OOC] "', 1, true) ~= nil,
    "/frb печатается тем же форматом, что /gnews")
ok(factions:find("for memberSteam, _ in pairs(f.Members) do", 1, true) ~= nil,
    "получатели /frb — только свои сотрудники")
ok(read("lua/autorun/sh_grm_f4menu.lua"):find("/frb текст", 1, true) ~= nil,
    "/frb добавлена в справку F4")


print("\n=== 6. РАДИАЛЬНОЕ МЕНЮ (подобие селектора оружия) ===")
ok(binder:find("BD.Radial = BD.Radial or { key = KEY_NONE, items = {} }", 1, true) ~= nil,
    "состояние радиального меню: одна клавиша + список секторов")
ok(binder:find("BD.MaxRadial = 12", 1, true) ~= nil, "до 12 секторов в круге")
ok(binder:find("function BD.RadialPickFrom", 1, true) ~= nil, "выбор сектора по положению мыши")
ok(binder:find("gui.EnableScreenClicker(true)", 1, true) ~= nil
    and binder:find("gui.EnableScreenClicker(false)", 1, true) ~= nil,
    "курсор появляется на время удержания и убирается обратно")
ok(binder:find("if key == MOUSE_LEFT then", 1, true) ~= nil,
    "ЛКМ запускает выбранную цепочку")
ok(binder:find("elseif key == MOUSE_RIGHT then", 1, true) ~= nil, "ПКМ — отмена")
ok(binder:find("-- Отпустили клавишу — круг просто закрывается. Запуск делает ЛКМ.", 1, true) ~= nil,
    "отпускание клавиши только закрывает круг")
ok(binder:find('hook.Add("StartCommand", "GRM_Binder_RadialFreeze"', 1, true) ~= nil
    and binder:find("cmd:ClearMovement()", 1, true) ~= nil
    and binder:find("cmd:ClearButtons()", 1, true) ~= nil,
    "пока круг открыт, игрок стоит на месте и не стреляет (как при C-меню)")
ok(binder:find('hook.Add("Think", "GRM_Binder_RadialGuard"', 1, true) ~= nil,
    "страховка от «залипания» круга при потере фокуса")
ok(binder:find('hook.Add("HUDPaint", "GRM_Binder_RadialDraw"', 1, true) ~= nil,
    "круг рисуется только пока меню открыто")
ok(binder:find("if not BD.RadialOpen then return end", 1, true) ~= nil,
    "закрытое меню не тратит ни кадра")
ok(binder:find("ЛКМ — выполнить, ПКМ — отмена", 1, true) ~= nil, "подсказка в центре круга")
ok(binder:find("РАДИАЛЬНОЕ МЕНЮ — ОДНА КЛАВИША НА ВСЁ", 1, true) ~= nil,
    "секция настройки в /binder")
ok(binder:find("radial = { key = BD.Radial.key or KEY_NONE, items = BD.Radial.items or {} }", 1, true) ~= nil,
    "настройки круга сохраняются в тот же файл")
ok(binder:find("if istable(root.slots) then", 1, true) ~= nil,
    "старый формат файла (просто массив слотов) продолжает читаться")

-- Живая геометрия: угол курсора → номер сектора
local pick = BD.RadialPickFrom
ok(isfunction(pick), "функция выбора сектора доступна")
if isfunction(pick) then
    local cx, cy = 100, 100
    ok(pick(cx, cy, 100, 0, 8, 40) == 1, "курсор вверх = первый сектор")
    ok(pick(cx, cy, 200, 100, 8, 40) == 3, "курсор вправо = третий из восьми")
    ok(pick(cx, cy, 100, 200, 8, 40) == 5, "курсор вниз = пятый из восьми")
    ok(pick(cx, cy, 0, 100, 8, 40) == 7, "курсор влево = седьмой из восьми")
    ok(pick(cx, cy, 105, 103, 8, 40) == 0, "курсор в центре = отмена")
    ok(pick(cx, cy, 200, 100, 4, 40) == 2, "при четырёх секторах вправо = второй")
end

-- Полный цикл: зажал -> навёл -> ЛКМ -> отпустил
local clicker = { state = false }
_G.gui = _G.gui or {}
_G.gui.EnableScreenClicker = function(v) clicker.state = v end
_G.gui.MousePos = function() return 100, 0 end
_G.gui.IsGameUIVisible = function() return false end
_G.gui.IsConsoleVisible = function() return false end
_G.MOUSE_LEFT, _G.MOUSE_RIGHT = 107, 108
_G.input = { IsKeyDown = function() return true end, IsMouseDown = function() return false end }

BD.Slots[5] = BD.BlankSlot(5)
BD.Slots[5].name = "Радиальная сцена"
BD.Slots[5].cooldown = 0
BD.Slots[5].steps = { { mode = "chat", text = "/me проверка радиального меню", delay = 0, enabled = true } }
BD.Radial.key = KEY_F
BD.Radial.items = { 5 }
BD.Save()

sentSay = {}
stub.time = 900
_G.hook.Run("PlayerButtonDown", lp, KEY_F)
ok(BD.RadialOpen == true and clicker.state == true, "удержание клавиши открыло круг и включило курсор")
ok(#sentSay == 0, "само открытие круга ничего не выполняет")

-- движение и кнопки блокируются
local frozen = { move = false, buttons = false }
local cmd = {
    ClearMovement = function() frozen.move = true end,
    ClearButtons = function() frozen.buttons = true end,
}
_G.hook.Run("StartCommand", lp, cmd)
ok(frozen.move and frozen.buttons, "пока круг открыт, движение и кнопки погашены")

BD.RadialPick = 1
_G.hook.Run("PlayerButtonDown", lp, MOUSE_LEFT)
ok(sentSay[1] == "/me проверка радиального меню", "ЛКМ запустила выбранную сцену", sentSay[1])
ok(BD.RadialOpen == false and clicker.state == false, "после ЛКМ круг закрылся и курсор убран")

-- отпускание клавиши без клика ничего не выполняет
sentSay = {}
stub.time = 1000
_G.hook.Run("PlayerButtonDown", lp, KEY_F)
BD.RadialPick = 1
_G.hook.Run("PlayerButtonUp", lp, KEY_F)
ok(BD.RadialOpen == false, "отпускание клавиши закрыло круг")
ok(#sentSay == 0, "без ЛКМ ничего не выполняется")

-- ПКМ отменяет
sentSay = {}
stub.time = 1100
_G.hook.Run("PlayerButtonDown", lp, KEY_F)
BD.RadialPick = 1
_G.hook.Run("PlayerButtonDown", lp, MOUSE_RIGHT)
ok(BD.RadialOpen == false and #sentSay == 0, "ПКМ закрыла круг без выполнения")

print("\n=== 7. ЯВНОЕ СОХРАНЕНИЕ И ЧИСЛО СЛОТОВ ===")
ok(binder:find("function BD.MarkDirty()", 1, true) ~= nil, "правки помечаются как несохранённые")
ok(binder:find('mkBtn(topBar, "СОХРАНИТЬ"', 1, true) ~= nil, "кнопка СОХРАНИТЬ в меню")
ok(binder:find("есть несохранённые изменения", 1, true) ~= nil, "видно, что изменения не записаны")
ok(binder:find("Слотов в списке:", 1, true) ~= nil, "поле выбора числа слотов")
ok(binder:find("local function tryClose", 1, true) ~= nil
    and binder:find("Derma_Query", 1, true) ~= nil,
    "закрытие с несохранёнными правками спрашивает подтверждение")
ok(binder:find("BD.Dirty = false", 1, true) ~= nil, "после записи флаг снимается")

BD.Dirty = false
BD.Slots[6] = BD.BlankSlot(6)
BD.MarkDirty()
ok(BD.Dirty == true, "MarkDirty поднимает флаг")
BD.Save()
ok(BD.Dirty == false, "Save снимает флаг")


print("\n=== 8. ЗВУК И ПОДСВЕТКА ===")
local hud = read("lua/autorun/client/cl_grm_hud.lua")
local snd = read("lua/autorun/sh_07_grm_sound.lua")

ok(snd:find('"common/wpn_hudon.wav", "common/wpn_hudoff.wav", "common/wpn_moveselect.wav"', 1, true) ~= nil
    and snd:find('"common/wpn_select.wav", "common/wpn_denyselect.wav"', 1, true) ~= nil,
    "стоковые звуки выбора оружия зарегистрированы и прекэшируются")

ok(hud:find("local SELECTOR_SND = {", 1, true) ~= nil, "селектор оружия: схема звуков")
ok(hud:find('open   = "common/wpn_hudon.wav"', 1, true) ~= nil
    and hud:find('move   = "common/wpn_moveselect.wav"', 1, true) ~= nil
    and hud:find('pick   = "common/wpn_select.wav"', 1, true) ~= nil
    and hud:find('deny   = "common/wpn_denyselect.wav"', 1, true) ~= nil,
    "используются именно ванильные HL2-звуки, а не самодельные")
ok(hud:find('if was ~= (selector.slot .. ":" .. selector.pos) then', 1, true) ~= nil
    and hud:find('selectorSound("move")', 1, true) ~= nil,
    "щелчок звучит только когда выбор реально сдвинулся")
ok(hud:find('selectorSound(has and "move" or "deny")', 1, true) ~= nil,
    "слоты: различный звук выбора и отказа (пустой слот)")
ok(hud:find("local function PickCurrent()", 1, true) ~= nil
    and hud:find("input.SelectWeapon(wep)", 1, true) ~= nil,
    "тик колеса выбирает оружие сразу (v10.5, заказ владельца)")
ok(hud:find('selectorSound("open", 0.05)', 1, true) ~= nil, "открытие селектора озвучено")
ok(hud:find('if selector.active and not silent then selectorSound("close") end', 1, true) ~= nil,
    "закрытие селектора озвучено")
ok(hud:find("GRM.Sound.UI(path, throttle or 0.02)", 1, true) ~= nil,
    "звук идёт через общий слой с троттлингом (быстрая прокрутка не трещит)")

ok(binder:find("local RADIAL_SND = {", 1, true) ~= nil, "круг биндера: та же звуковая схема")
ok(binder:find('radialSound("move")', 1, true) ~= nil, "щелчок при переходе на другой сектор")
ok(binder:find('radialSound("open", 0.05)', 1, true) ~= nil and binder:find('radialSound("pick", 0.05)', 1, true) ~= nil
    and binder:find('radialSound("close", 0.05)', 1, true) ~= nil,
    "открытие, выполнение и отмена озвучены")
ok(binder:find("if BD.RadialPick ~= prevPick and BD.RadialPick > 0 then", 1, true) ~= nil,
    "звук привязан к смене сектора, а не к каждому кадру")

ok(binder:find("BD.RadialAnim", 1, true) ~= nil, "у секторов есть анимация подсветки")
ok(binder:find("local ft = math.min(FrameTime() * 9, 1)", 1, true) ~= nil,
    "плавность считается по FrameTime, без таймеров")
ok(binder:find("local br = Lerp(anim, C.card.r, C.acc.r)", 1, true) ~= nil,
    "цвет сектора плавно уходит в акцентный при наведении")
ok(binder:find("-- Светящаяся кромка выбранного сектора.", 1, true) ~= nil,
    "у выбранного сектора светящаяся золотая кромка")
ok(binder:find('anim > 0.5 and "GRMBind_Head" or "GRMBind_Body"', 1, true) ~= nil,
    "подпись выбранного сектора крупнее")

print("\n=== 5. ДЛИННЫЕ /me /do /it (заказ владельца) ===")
local long = "/me " .. string.rep("подробно описывает происходящее действие ", 12)
local parts = BD.SplitChat(long, BD.SayLimit)
ok(#parts > 1, ("длинная строка разбита на куски: %d"):format(#parts))
local fits = true
for _, p in ipairs(parts) do if #p > BD.SayLimit then fits = false end end
ok(fits, "каждый кусок влезает в лимит консольной команды say")
local allPrefixed = true
for _, p in ipairs(parts) do if p:sub(1, 4) ~= "/me " then allPrefixed = false end end
ok(allPrefixed, "команда /me повторяется в каждом куске — текст не превращается в обычный чат")
local restored = {}
for _, p in ipairs(parts) do restored[#restored + 1] = p:sub(5) end
ok(table.concat(restored, " ") == (long:sub(5):gsub("%s+$", "")), "слова не теряются и не режутся посередине")
ok(#BD.SplitChat("/do короткая строка", BD.SayLimit) == 1, "короткая строка уходит одним сообщением")

-- вечер-12: целиком — через чат режима (SendText), а не EasyChat (вырезан)
sentSay = {}
local sentChat = {}
_G.EasyChat = nil
_G.GRMRPChat = { SendText = function(msg) sentChat[#sentChat + 1] = msg end }
BD.Slots[5] = BD.BlankSlot(5)
BD.Slots[5].cooldown = 0
BD.Slots[5].steps = { { mode = "chat", text = long, delay = 0, enabled = true } }
stub.time = 400
local sBase = #scheduled
BD.Run(5, 1, {}, true)
for i = sBase + 1, #scheduled do scheduled[i].fn() end -- лесенка кусков отстреляла
-- Лимит длинной строки = 500 байт (под клиентским clamp 512): куски <=500,
-- каждый со своим /me, склейка восстанавливает текст целиком (Trim-хвост —
-- стоящий контракт SplitChat). Превысившие лимит режутся, всё остальное — одним.
local okSizes, okCmd, body = true, true, {}
for _, p in ipairs(sentChat) do
    if #p > BD.ChatLimit() then okSizes = false end
    if p:sub(1, 4) ~= "/me " then okCmd = false end
    body[#body + 1] = p:sub(5)
end
ok(#sentChat >= 2 and okSizes, "строка >500 разбита на куски SendText в лимите", #sentChat)
ok(okCmd and table.concat(body, " ") == (string.Trim(long):sub(5)):gsub("%s+$", ""),
    "склейка кусков = исходный текст, /me в каждом куске")
ok(#sentSay == 0, "ни один кусок не уехал в say, пока жив чат режима")
ok(#sentSay == 0, "задвоения в say нет: SendText — единственный канал")
-- без чата — откат на say-куски в лимите
_G.GRMRPChat = nil
sentChat = {}
sentSay = {}
BD.Run(5, 1, {}, true)
ok(#sentSay >= 1, "без чата строки идут через say кусками", #sentSay)
local fitsSay = true
for _, p in ipairs(sentSay) do if #p > BD.SayLimit then fitsSay = false end end
ok(fitsSay, "куски в say-режиме не превышают лимит 120")

print(("\nBINDER + CHAT + FORMS: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
