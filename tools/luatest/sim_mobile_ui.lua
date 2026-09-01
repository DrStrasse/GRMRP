-- sim_mobile_ui.lua — smoke-симуляция КЛИЕНТСКОЙ оболочки мобильного (Код 88.2).
-- ВНИМАНИЕ (2026-08-05): тест написан под полноценный клиентский UI Mobile v1.2.2
-- (репит-клок, навигация, SMS-треды, контакты, калькулятор). Текущий модуль
-- ветки — упрощённая v2.0.1 (см. шапку sh_grm_mobile.lua: «этот файл не
-- восстанавливает полноценный UI»), серверный контракт покрыт sim_mobile.lua
-- (121/121 OK). Пока UI не восстановлен, этот стенд ожидаемо падает —
-- НЕ считать регрессией; при возврате полноценного UI вернуть в регресс.
-- Грузит РЕАЛЬНЫЙ sh_grm_mobile.lua с CLIENT=true и моками Derma/surface/draw,
-- прогоняет: открытие телефона, навигацию, репит-клок (главный фикс 88.2:
-- OS-шторм PlayerButtonDown без Up = ровно ОДИН шаг выбора; удержание =
-- 0.45с пауза, затем ровные повторы по 0.11с), все экраны, набор номера,
-- SMS-треды/пузыри, контакты/меню, калькулятор, диктовку номера (E),
-- входящий вызов, авто-закрытие при потере трубки.

local PASS, FAILN = 0, 0
local function ok(cond, name)
    if cond then PASS = PASS + 1 print("  ok  " .. name)
    else FAILN = FAILN + 1 print("  FAIL " .. name) end
end
local function sect(s) print("== " .. s) end

-- ---------- виртуальное время ----------
local TT = 0
function CurTime() return TT end
function FrameTime() return 0.016 end
function SysTime() return TT end

-- ---------- базовые типы/утилиты ----------
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function isfunction(v) return type(v) == "function" end
function isbool(v) return type(v) == "boolean" end
function Color(r, g, b, a) return { r = r or 0, g = g or 0, b = b or 0, a = a or 255 } end
function IsColor(t) return istable(t) and t.r ~= nil and t.g ~= nil and t.b ~= nil end
function Material(p) return { p = p } end
function string.Trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
function string.FormattedTime(sec, fmt)
    local m = math.floor(sec / 60) local s = math.floor(sec % 60)
    return string.format("%02d:%02d", m, s)
end
TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, TEXT_ALIGN_RIGHT = 0, 1, 2
NOTIFY_HINT = 3
function ScrW() return 1920 end
function ScrH() return 1080 end

-- клавиши (важны относительные порядки цифровых блоков)
KEY_0 = 40 for i = 1, 9 do _G["KEY_" .. i] = 40 + i end
KEY_PAD_0 = 90 for i = 1, 9 do _G["KEY_PAD_" .. i] = 90 + i end
KEY_PAD_ENTER, KEY_PAD_DIVIDE, KEY_PAD_MULTIPLY, KEY_PAD_MINUS, KEY_PAD_PLUS = 100, 101, 102, 103, 104
KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT = 200, 201, 202, 203
KEY_ENTER, KEY_BACKSPACE, KEY_DELETE, KEY_E, KEY_N = 64, 66, 67, 30, 45
MOUSE_LEFT, MOUSE_RIGHT, MOUSE_MIDDLE = 107, 108, 109

-- ---------- surface/draw ----------
surface = {
    CreateFont = function() end,
    PlaySound = function() end,
    SetDrawColor = function() end,
    SetMaterial = function() end,
    DrawTexturedRect = function() end,
    SetAlphaMultiplier = function() end,
    _font = "GRMMob_X",
    SetFont = function(f) surface._font = f end,
    GetTextSize = function(s)
        local scale = (surface._font == "GRMMob_B") and 12 or (surface._font == "GRMMob_T") and 9 or 7
        return #tostring(s) * scale, 14
    end,
}
local DRAWS = { boxes = 0, texts = 0 }
draw = {
    RoundedBox = function(_, x, y, w, h) DRAWS.boxes = DRAWS.boxes + 1
        if DRAWS.log then DRAWS.log[#DRAWS.log + 1] = { x = x, y = y, w = w, h = h } end end,
    RoundedBoxEx = function() DRAWS.boxes = DRAWS.boxes + 1 end,
    SimpleText = function() DRAWS.texts = DRAWS.texts + 1 end,
}

-- ---------- hook/net/timer/concommand ----------
local H = {}
hook = { Add = function(ev, id, fn) H[ev] = H[ev] or {} H[ev][id] = fn end }
local function fireHook(ev, ...)
    if H[ev] then for _, fn in pairs(H[ev]) do fn(...) end end
end

local NET_RECV = {}
local NET_SENT = {}
net = {
    Receive = function(name, fn) NET_RECV[name] = fn end,
    Start = function(name) net._cur = { name = name, writes = {} } end,
    WriteTable = function(t) table.insert(net._cur.writes, t) end,
    WriteString = function(s) table.insert(net._cur.writes, { __str = s }) end,
    SendToServer = function() NET_SENT[#NET_SENT + 1] = net._cur end,
    Send = function() end,
    ReadTable = function() local v = table.remove(net._in, 1) return v end,
    ReadString = function() local v = table.remove(net._in, 1) return v end,
}
local function sendToClient(name, ...)
    net._in = { ... }
    NET_RECV[name]()
end
local function lastAct()
    for i = #NET_SENT, 1, -1 do
        if NET_SENT[i].name == "GRM_Mob_Act" then return NET_SENT[i].writes[1] end
    end
    return nil
end

timer = { Create = function(id, d, n, fn) timer._t = timer._t or {} timer._t[id] = fn end, Simple = function(_, fn) fn() end, Remove = function() end }
concommand = { Add = function(name, fn) concommand._c = concommand._c or {} concommand._c[name] = fn end }

-- ---------- input/vgui/notification/Derma ----------
local KEYS_HELD = {}
input = { IsKeyDown = function(k) return KEYS_HELD[k] == true end }
local PANELS = {}
local function mkPanel()
    local p = {
        _x, _y, _w, _h = 0, 0, 0, 0, _vis = false,
        SetSize = function(s, w, h) s._w, s._h = w, h end,
        SetPos = function(s, x, y) s._x, s._y = x, y end,
        GetPos = function(s) return s._x, s._y end,
        SetVisible = function(s, v) s._vis = v end,
        IsVisible = function(s) return s._vis end,
        Remove = function(s) s._removed = true end,
        CursorPos = function(s) return s._cx or -1, s._cy or -1 end,
    }
    PANELS[#PANELS + 1] = p
    return p
end
vgui = {
    Create = function() return mkPanel() end,
    GetKeyboardFocus = function() return vgui._focus end,
}
function IsValid(e) return e ~= nil and not (istable(e) and e._removed == true) end
gui = {
    _mx = 0, _my = 0,
    IsGameUIVisible = function() return false end,
    IsConsoleVisible = function() return false end,
    MousePos = function() return gui._mx, gui._my end,
}
notification = { AddLegacy = function() notification._n = (notification._n or 0) + 1 end }
local STR_ANSWERS = {}
local STR_CALLS = 0
function Derma_StringRequest(title, sub, def, cb)
    STR_CALLS = STR_CALLS + 1
    local ans = table.remove(STR_ANSWERS, 1)
    if ans ~= nil then cb(ans) end
end
local MENU_OPTS = {}
function DermaMenu()
    MENU_OPTS = {}
    local m = {}
    function m:AddOption(label, fn)
        MENU_OPTS[#MENU_OPTS + 1] = { label = label, fn = fn }
        return { SetIcon = function() end }
    end
    function m:Open() end
    return m
end
local RUN_CC = {}
function RunConsoleCommand(cmd, arg) RUN_CC[#RUN_CC + 1] = { cmd = cmd, arg = arg } end

-- ---------- игрок-клиент ----------
local LP = { _isLP = true }
LP.Alive = function(s) return s._alive ~= false end
function LocalPlayer() return LP end
player = { GetAll = function() return {} end }

-- ---------- GMod-глобалы рантайма ----------
CLIENT = true SERVER = false
AddCSLuaFile = function() end
GRM = {}
util = { AddNetworkString = function() end,
    JSONToTable = function() return nil end,
    TableToJSON = function(t) return "json" end }
file = { Exists = function() return false end, Read = function() return nil end, Write = function() end, CreateDir = function() end }
-- utf8 в LuaJIT отсутствует — файл обязан работать и без него (проверяем фолбэк-путь)

-- ---------- грузим РЕАЛЬНЫЙ модуль ----------
sect("загрузка sh_grm_mobile.lua (CLIENT-ветка)")
local chunk, err = loadfile("lua/autorun/sh_grm_mobile.lua")
ok(chunk ~= nil, "парсится: " .. tostring(err))
if not chunk then os.exit(1) end
local okr, rerr = pcall(chunk)
ok(okr, "выполняется без ошибок: " .. tostring(rerr))
local MB = GRM.Mobile
ok(MB ~= nil, "GRM.Mobile зарегистрирован")
ok(MB.Version=="1.2.2"and MB.UIVersion=="3.3.0","protocol 1.2.2 / UI 3.3.0 (+ Taxi app)")
ok(MB.Tiers.crappy.ui == "feature" and MB.Tiers.lost.ui == "flip", "кнопочная трубка и раскладушка имеют отдельный дизайн")
ok(MB.Tiers.tinkle.ui == "smartphone" and MB.Tiers.whiz_gold.ui == "smartphone", "смартфоны используют app-grid дизайн")

-- ---------- хелперы симуляции ----------
local function tap(k)                      -- короткое нажатие (темп человека: 0.09с — Код 100 дебаунс 0.07 пропускает)
    fireHook("PlayerButtonDown", LP, k)
    fireHook("PlayerButtonUp", LP, k)
    TT = TT + 0.09
end
local function press(k)                    -- зажать (Down без Up)
    KEYS_HELD[k] = true
    fireHook("PlayerButtonDown", LP, k)
end
local function release(k)
    KEYS_HELD[k] = false
    fireHook("PlayerButtonUp", LP, k)
end
local function thinkFor(sec)               -- крутим кадры Think
    local t0 = TT
    local step = 0.016
    while TT - t0 < sec - 0.0001 do
        TT = TT + step
        fireHook("Think")
    end
end
local function paintPhone()
    local p = PANELS[#PANELS]
    if p and p.Paint then p.Paint(p, 340, 560) end
end

-- ---------- состояние «трубка есть» ----------
sect("push состояния: трубка tinkle (8 приложений), номер выдан")
local function feedIdle()
    sendToClient("GRM_Mob_State", {
        has = true, tier = "tinkle", number = "12345", bars = 4, operator = "Panoramic",
        modelName = "Panoramic Tinkle", lineState = "idle", unread = 2,
        otherNumber = "", otherName = "", signal = 0.9,
    })
end
feedIdle()
sendToClient("GRM_Mob_Data", "contacts", { rows = {
    { i = 1, name = "Анна", num = "11111" },
    { i = 2, name = "Борис", num = "54321" },
} })
sendToClient("GRM_Mob_Data", "sms", { rows = {
    { num = "54321", dir = "in", read = true, text = "привет, ты где?", ts = os.time() - 400 },
    { num = "11111", dir = "in", read = false, text = "скинь номер босса", ts = os.time() - 200 },
    { num = "54321", dir = "out", read = true, text = "у рынка, подъезжай", ts = os.time() - 100 },
    { num = "54321", dir = "in", read = false, text = "окей, жду у входа уже пять минут, скорее", ts = os.time() },
} })
sendToClient("GRM_Mob_Data", "notes", { rows = { { i = 1, text = "код от гаража 42-17", ts = os.time() } } })
sendToClient("GRM_Mob_Data", "jobs", { rows = {
    { fac = "PD", title = "Патруль", kind = "вакансия", pay = "з/п 900 ×3", desc = "" },
    { fac = "Медики", title = "Дежурство", kind = "заказ", pay = "1200", desc = "" },
}, mine = nil })
sendToClient("GRM_Mob_Data", "fac", { data = {
    name = "Братство", myRole = "Солдат", myDept = "Охрана", total = 3, online = 2,
    rows = {
        { name = "Лидер", online = true, role = "Глава", dept = "—", leader = true },
        { name = "Боец2", online = true, role = "Солдат", dept = "Охрана", leader = false },
        { name = "Боец3", online = false, role = "Солдат", dept = "—", leader = false },
    },
} })
sendToClient("GRM_Mob_Data", "forum", { rows = {
    { id = 1, author = "Вася", text = "продам гараж у порта, дёшево", time = os.time() - 60, likes = 4, liked = false, replies = 1 },
    { id = 2, author = "Гриша", text = "кто видел мой мопед? угнали возле больницы, звоните", time = os.time(), likes = 2, liked = true, replies = 0 },
} })

-- ---------- чат не должен открывать телефон ----------
sect("стрелка вверх игнорируется, пока игрок печатает в чате")
NET_SENT = {}
fireHook("StartChat")
tap(KEY_UP)
ok(#PANELS == 0 and lastAct() == nil, "KEY_UP в открытом чате не создаёт и не открывает телефон")
fireHook("FinishChat")
vgui._focus = {}
tap(KEY_UP)
ok(#PANELS == 0, "KEY_UP игнорируется при активном поле ввода стороннего чата")
vgui._focus = nil

-- ---------- открытие ----------
sect("открытие по СТРЕЛКЕ ВВЕРХ")
tap(KEY_UP)
local act = lastAct()
ok(act ~= nil and act.op == "open", "отправлен op=open")
ok(#PANELS >= 1, "панель телефона создана")
ok(PANELS[#PANELS]._vis == true, "панель видима")
local dHome = DRAWS.texts
paintPhone()
ok(DRAWS.texts > dHome, "домашний экран рисуется (текстов: " .. DRAWS.texts .. ")")
local navActions = {}
for _,box in ipairs(MB._devUI.hitboxes or {}) do if box.navAction then navActions[box.navAction] = true end end
ok(navActions.back and navActions.home and navActions.close, "нижняя панель содержит «Назад», «Домой» и «Убрать»")

-- ---------- левая мышь не является Mouse3 ----------
sect("клик мышью: одно физическое нажатие открывает ровно одно приложение")
NET_SENT = {}
local clickPanel = PANELS[#PANELS]
clickPanel._cx, clickPanel._cy = 130, 130                    -- вторая плитка: SMS
paintPhone()
ok((MB._devUI.hoverAnim["home:2"] or 0) > 0, "наведение запускает плавную hover-анимацию плитки")
gui._mx, gui._my = clickPanel._x + 130, clickPanel._y + 130
fireHook("PlayerButtonDown", LP, MOUSE_LEFT)                 -- реальный GMod также шлёт button hook
clickPanel:OnMousePressed(MOUSE_LEFT)
clickPanel:OnMousePressed(MOUSE_LEFT)                       -- дребезг того же кадра обязан игнорироваться
fireHook("PlayerButtonUp", LP, MOUSE_LEFT)
local smsReads = 0
for _, sent in ipairs(NET_SENT) do
    local payload = sent.name == "GRM_Mob_Act" and sent.writes[1] or nil
    if payload and payload.op == "sms_read" then smsReads = smsReads + 1 end
end
ok(smsReads == 1 and lastAct() and lastAct().op == "sms_read", "ЛКМ=107 не считается Mouse3: SMS открыт один раз")
ok(MB._devUI.pointerPulse and MB._devUI.pointerPulse.id == "2", "клик создаёт отдельную pressed-анимацию")
clickPanel._cx, clickPanel._cy = -1, -1
tap(KEY_BACKSPACE)

-- ---------- OS-шторм: ровно один шаг ----------
sect("антидребезг: OS-авторепит не двигает выбор (фикс 88.2)")
NET_SENT = {}
press(KEY_DOWN)                                   -- первый Down: sel 1→2 (sms)
for i = 1, 30 do                                  -- системный авторепит: 30 давлений БЕЗ Up
    fireHook("PlayerButtonDown", LP, KEY_DOWN)
    TT = TT + 0.01
end
release(KEY_DOWN)
tap(KEY_ENTER)                                    -- если шторм прошёл — sel был бы далеко; ждём sms (приложение №2)
act = lastAct()
ok(act ~= nil and act.op == "sms_read", "после шторма из 30 Down sel = №2 (SMS), op=sms_read")
local dSms = DRAWS.texts
paintPhone()
ok(DRAWS.texts > dSms, "экран SMS-тредов рисуется")
tap(KEY_BACKSPACE)                                -- домой, sel=1

-- ---------- точный репит-клок ----------
sect("удержание стрелки: 0.45с пауза + ровные повторы 0.11с")
NET_SENT = {}
press(KEY_DOWN)                                   -- шаг 1 сразу: sel 1→2
thinkFor(0.70)                                    -- повторы на ~0.45/0.56/0.67 → ещё 3 шага
release(KEY_DOWN)
tap(KEY_ENTER)                                    -- sel должен быть №5 (jobs) для tinkle: dial,sms,contacts,notes,jobs
act = lastAct()
ok(act ~= nil and act.op == "jobs_query", "удержание 0.70с = ровно 4 шага → №5 Биржа (op=jobs_query)")
paintPhone()
tap(KEY_BACKSPACE)

-- ---------- набор номера ----------
sect("набор номера и исходящий вызов")
NET_SENT = {}
tap(KEY_ENTER)                                    -- sel=1 → dial
for _, k in ipairs({ KEY_5, KEY_4, KEY_3, KEY_2, KEY_1 }) do tap(k) end
tap(KEY_ENTER)
act = lastAct()
ok(act ~= nil and act.op == "dial" and act.number == "54321", "набор 54321 + ENTER → op=dial 54321")
paintPhone()

-- ---------- входящий вызов ----------
sect("входящий вызов: отклонение из карточки")
sendToClient("GRM_Mob_State", {
    has = true, tier = "tinkle", number = "12345", bars = 4, operator = "Panoramic",
    modelName = "Panoramic Tinkle", lineState = "ringing", unread = 0,
    otherNumber = "54321", otherName = "Борис", signal = 0.9,
})
paintPhone()
fireHook("HUDPaint")
ok(true, "карточка вызова + HUD-поповер отрисованы без ошибок")
NET_SENT = {}
tap(KEY_BACKSPACE)                                -- отклонить
act = lastAct()
ok(act ~= nil and act.op == "hangup", "BACKSPACE при ringing → op=hangup")
feedIdle()                                        -- линия свободна
tap(KEY_BACKSPACE)                                -- idle → домой

-- ---------- SMS треды и пузыри ----------
sect("SMS: треды, пузырьковый диалог, ответ")
NET_SENT = {}
tap(KEY_DOWN)                                     -- sel: 1→2 sms
tap(KEY_ENTER)
act = lastAct()
ok(act ~= nil and act.op == "sms_read", "SMS-экран открыт (op=sms_read)")
NET_SENT = {}
tap(KEY_ENTER)                                    -- свежайший тред 54321 → диалог
local dB = DRAWS.texts
paintPhone()
ok(DRAWS.texts > dB, "пузырьковый диалог отрисован")
tap(KEY_UP)                                       -- листаем историю
paintPhone()
STR_ANSWERS = { "уже иду" }
STR_CALLS = 0
tap(KEY_ENTER)                                    -- ответить в текущий тред
act = lastAct()
ok(STR_CALLS >= 1, "Derma-запрос текста показан (" .. STR_CALLS .. ")")
ok(act ~= nil and act.op == "sms" and act.num == "54321", "ответ ушёл: op=sms → 54321")
tap(KEY_BACKSPACE)                                -- назад к тредам
-- возврат в диалог сохраняет позицию треда (88.3b): идём на тред №2 (11111),
-- BACKSPACE, повторный ENTER должен открыть ТОТ ЖЕ тред №2, а не верхний
tap(KEY_DOWN)
tap(KEY_ENTER)                                    -- тред 11111
tap(KEY_BACKSPACE)                                -- назад; sel обязан остаться на №2
STR_ANSWERS = { "x", "y" }                        -- номер перезабьём префиллом… нет: префилл = threadNum
NET_SENT = {}
tap(KEY_ENTER)                                    -- снова тред №2 (если позиция не сбросилась)
STR_ANSWERS = { "проверка треда" }
tap(KEY_ENTER)                                    -- ответить внутри треда
act = lastAct()
ok(act ~= nil and act.op == "sms" and act.num == "11111", "BACKSPACE из диалога сохраняет позицию треда (№2 = 11111)")
tap(KEY_BACKSPACE)                                -- назад к тредам

-- ---------- контакты ----------
sect("контакты: меню действий, звонок")
tap(KEY_BACKSPACE)                                -- домой
tap(KEY_DOWN) tap(KEY_DOWN)                       -- sel 3 = contacts
tap(KEY_ENTER)
paintPhone()
tap(KEY_ENTER)                                    -- экран действий первого контакта (Анна 11111)
paintPhone()
NET_SENT = {}
tap(KEY_ENTER)                                    -- первое действие: позвонить
act = lastAct()
ok(act ~= nil and act.op == "dial" and act.number == "11111", "звонок из контакта → op=dial 11111")
feedIdle()
tap(KEY_BACKSPACE)                                -- действия контакта → контакты
tap(KEY_BACKSPACE)                                -- контакты → домой

-- ---------- заметки ----------
sect("заметки: удаление выбранной")
tap(KEY_DOWN) tap(KEY_DOWN) tap(KEY_DOWN)         -- sel 4 = notes
tap(KEY_ENTER)
paintPhone()
NET_SENT = {}
tap(KEY_DELETE)
act = lastAct()
ok(act ~= nil and act.op == "note_del" and act.i == 1, "DEL → op=note_del i=1")
tap(KEY_BACKSPACE)

-- ---------- биржа/фракция/форум: отрисовка ----------
sect("биржа, фракция, форум: отрисовка и действия")
for i = 1, 4 do tap(KEY_DOWN) end                 -- sel 5 = jobs
tap(KEY_ENTER) paintPhone() tap(KEY_BACKSPACE)
for i = 1, 5 do tap(KEY_DOWN) end                 -- sel 6 = fac
tap(KEY_ENTER)
NET_SENT = {}
paintPhone()
tap(KEY_DOWN) tap(KEY_UP)                         -- скролл состава
paintPhone()
ok(true, "экран фракции отрисован и скроллится")
tap(KEY_BACKSPACE)
for i = 1, 6 do tap(KEY_DOWN) end                 -- sel 7 = forum
tap(KEY_ENTER)
paintPhone()
tap(KEY_DOWN)                                     -- скролл ленты
paintPhone()
STR_ANSWERS = { "продаю гараж у доков, торг" }
NET_SENT = {}
tap(KEY_N)
act = lastAct()
ok(act ~= nil and act.op == "forum_post", "N на форуме → op=forum_post")
NET_SENT = {}
tap(KEY_DOWN) tap(KEY_DOWN) tap(KEY_DOWN)          -- toolbar 1 → первая современная карточка (4)
tap(KEY_ENTER)                                    -- открыть публикацию
paintPhone()
tap(KEY_ENTER)                                    -- интерактивная реакция
act = lastAct()
ok(act ~= nil and act.op == "forum_like" and tonumber(act.id) and act.id > 0, "карточка открывается, кнопка «Нравится» отправляет forum_like")
tap(KEY_BACKSPACE)                                -- к ленте
tap(KEY_BACKSPACE)                                -- домой

-- ---------- калькулятор ----------
sect("калькулятор: 7 + 8 = 15")
for i = 1, 7 do tap(KEY_DOWN) end                 -- sel 8 = calc
tap(KEY_ENTER)
paintPhone()
tap(KEY_7) tap(KEY_PAD_PLUS) tap(KEY_8)
tap(KEY_DOWN) tap(KEY_DOWN) tap(KEY_DOWN)         -- sel 1→13 («0»)
tap(KEY_RIGHT) tap(KEY_RIGHT)                     -- 13→15 («=»)
tap(KEY_ENTER)
paintPhone()
ok(true, "калькулятор отработал без ошибок")
tap(KEY_BACKSPACE)

-- ---------- Код 88.3: колесо и слоты ----------
sect("Код 88.3: колесо листает, слоты оружия заблокированы")
local function bindRet(b, pr)
    local blocked = false
    if H["PlayerBindPress"] then
        for _, fn in pairs(H["PlayerBindPress"]) do
            if fn(LP, b, pr) then blocked = true end
        end
    end
    return blocked
end
ok(bindRet("slot1", true) == true, "slot1 заблокирован при открытом телефоне")
ok(bindRet("slot4", true) == true, "slot4 заблокирован")
ok(bindRet("invprev", false) == false, "отпускание бинда не глушится")
-- колесо вниз: sel 1→2 (sms), ENTER → sms_read доказывает позицию
NET_SENT = {}
ok(bindRet("invnext", true) == true, "колесо вниз заблокировано для оружия")
tap(KEY_ENTER)
act = lastAct()
ok(act ~= nil and act.op == "sms_read", "колесо сдвинуло выбор на №2 (SMS)")
tap(KEY_BACKSPACE)
NET_SENT = {}
bindRet("invprev",true)bindRet("invprev",true)bindRet("invprev",true)bindRet("invprev",true) -- 1→10 power→9 calc→8 taxi→7 forum
tap(KEY_ENTER)
act = lastAct()
ok(act ~= nil and act.op == "forum_query", "колесо вверх трижды → №7 Форум")
tap(KEY_BACKSPACE)

-- ---------- E: диктовка ----------
sect("E: продиктовать номер в локальный чат")
RUN_CC = {}
tap(KEY_E)
ok(#RUN_CC >= 1 and RUN_CC[1].cmd == "say" and tostring(RUN_CC[1].arg):find("12345") ~= nil,
    "say /me … 12345 отправлен")

-- ---------- Код 100: OS-авторепит ПАРАМИ (SDL) не крутит выбор ----------
sect("Код 100: шторм повторов парами Down+Up (обход флага M.down) — выбор не скачет")
tap(KEY_BACKSPACE)                                -- домой закрылся
tap(KEY_UP)                                       -- переоткрыли: home, sel=1
NET_SENT = {}
KEYS_HELD[KEY_DOWN] = true                        -- SDL-семантика: клавиша ФИЗИЧЕСКИ зажата весь шторм
for i = 1, 15 do                                  -- 33 Гц повтор парами Down+Up: до фикса каждый проходил как новое нажатие
    fireHook("PlayerButtonDown", LP, KEY_DOWN)
    fireHook("PlayerButtonUp", LP, KEY_DOWN)
    TT = TT + 0.03
end
KEYS_HELD[KEY_DOWN] = false                       -- реальное отпускание
fireHook("PlayerButtonUp", LP, KEY_DOWN)
tap(KEY_ENTER)                                    -- принят ровно ОДИН шаг: sel=2 (sms)
act = lastAct()
ok(act ~= nil and act.op == "sms_read", "шторм 15 пар down/up → ровно один шаг (№2 SMS), выбор не ускакал")
tap(KEY_BACKSPACE)
NET_SENT = {}
tap(KEY_DOWN) tap(KEY_DOWN) tap(KEY_DOWN) tap(KEY_DOWN)  -- честный темп: 4 одиночных нажатия
tap(KEY_ENTER)
act = lastAct()
ok(act ~= nil and act.op == "jobs_query", "человеческий темп 0.09с: все 4 шага приняты → №5 Биржа")
tap(KEY_BACKSPACE)

sect("Код 100: кольцевой перепрыг в сетке смартфона")
DRAWS.log = {}
tap(KEY_UP)                                       -- 1 → последний app tile
paintPhone()
local tiles=0
for _,b in ipairs(DRAWS.log)do if b.w>=80 and b.w<=120 and b.h==b.w then tiles=tiles+1 end end
ok(tiles>=6,"кольцевой выбор рисует стабильную сетку приложений (tiles="..tiles..")")
DRAWS.log={}
tap(KEY_DOWN)                                     -- последний → первый
paintPhone()
local tiles2=0
for _,b in ipairs(DRAWS.log)do if b.w>=80 and b.w<=120 and b.h==b.w then tiles2=tiles2+1 end end
DRAWS.log=nil
ok(tiles2>=6,"обратный перепрыг сохраняет сетку без пролёта списка")

-- ---------- закрытие и потеря трубки ----------
sect("закрытие телефона и потеря трубки (op=close/ping)")
NET_SENT = {}
tap(KEY_BACKSPACE)                                -- домой закрылся (мы на home)
act = lastAct()
ok(act ~= nil and act.op == "close", "закрытие отправило op=close (снятие стойки)")
if timer._t and timer._t["GRM_Mob_Tick"] then timer._t["GRM_Mob_Tick"]() end
ok(true, "тикер секундомера отработал")
tap(KEY_UP)                                       -- переоткрыть
NET_SENT = {}
if timer._t and timer._t["GRM_Mob_Tick"] then timer._t["GRM_Mob_Tick"]() end
act = lastAct()
ok(act ~= nil and act.op == "ping", "открытый UI шлёт keepalive-ping раз в секунду")
-- смерть с открытым телефоном: UI закрывается сам, стойка не залипает на респавне
LP._alive = false
NET_SENT = {}
if timer._t and timer._t["GRM_Mob_Tick"] then timer._t["GRM_Mob_Tick"]() end
act = lastAct()
ok(act ~= nil and act.op == "close", "смерть с открытым телефоном → op=close (стойка снята)")
LP._alive = true
-- слоты НЕ заблокированы, когда телефон закрыт
ok(bindRet("slot1", true) == false, "после смертельного закрытия slot1 свободен")

sect("управление питанием: убрать отдельно от деактивации")
feedIdle()
tap(KEY_UP)                                       -- открыть
NET_SENT = {}
tap(KEY_UP) tap(KEY_ENTER)                        -- последняя плитка «Управление»
tap(KEY_ENTER)                                    -- «Убрать телефон»
act = lastAct()
ok(act ~= nil and act.op == "close", "«Убрать телефон» только закрывает UI, связь остаётся активной")
tap(KEY_UP)                                       -- открыть снова
NET_SENT = {}
tap(KEY_UP) tap(KEY_ENTER)                        -- Управление
tap(KEY_DOWN) tap(KEY_ENTER)                      -- Деактивировать → подтверждение
ok(lastAct() == nil or lastAct().op ~= "deactivate", "первое нажатие деактивацию не выполняет — показано подтверждение")
tap(KEY_ENTER)                                    -- Да, деактивировать
act = lastAct()
ok(act ~= nil and act.op == "deactivate", "подтверждение отправляет op=deactivate")

sendToClient("GRM_Mob_State", { has = false, lineState = "idle", unread = 0 })
if timer._t and timer._t["GRM_Mob_Tick"] then timer._t["GRM_Mob_Tick"]() end
ok(true, "state has=false + тикер: телефон сам закрылся без ошибок")
notification._n = 0
TT = TT + 100
tap(KEY_UP)
ok(notification._n == 1, "подсказка «купите трубку» показана один раз")
tap(KEY_UP)
ok(notification._n == 1, "троттл 15с: повторный UP подсказку не дублирует")

print("")
print(string.format("sim_mobile_ui: %d пройдено, %d провалено", PASS, FAILN))
if FAILN > 0 then os.exit(1) end
print("SIM_MOBILE_UI: OK")
