--[[--------------------------------------------------------------------
    sim_esc_menu_flow — рантайм-контракт ESC-меню с движком (вечер-25).
    Ground truth — официальный lua-код движка (Facepunch/garrysmod):
      * gui.ActivateGameUI/HideGameUI/IsGameUIVisible — реальные глобалки;
      * lua/menu/problems/problems_pnl.lua: скан input.IsKeyDown(KEY_ESCAPE)
        — движок САМ следит за клавишей так же, поэтому фронт нажатия —
        законный канал открытия (без ожидания gameui → без вспышки CEF);
      * канон команд — gamemenucommand OpenOptionsDialog/OpenServerBrowser +
        RunGameUICommand("quit") (lua/menu/mainmenu.lua), перепост до TTL.
    Вечер-25 (жалоба «работает пару раз, потом залипает + мерцает»):
    грейса more нет — проверяем, что эхо клавиши НЕ открывает окно заново,
    а следующее нажатие сразу после закрытия работает; закрытие не требует
    фокуса (сканер); перебинденный ESC открывается fallback'ом.
----------------------------------------------------------------------]]
local fails, total = 0, 0
local function check(name, cond, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "   " .. tostring(extra or "")) end
end
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

local SRC = "gamemodes/grmrp/gamemode/modules/ui/cl_grmrp_menu.lua"
local h = read(SRC)
local function has(n) return h:find(n, 1, true) ~= nil end

print("\n=== 0. СТАТИЧЕСКИЙ КОНТРАКТ ===")
check("скан фронтов: input.IsKeyDown(KEY_ESCAPE)", has("input.IsKeyDown(KEY_ESCAPE)"))
check("грейса-пожирателя больше нет", not has("Menu.justClosedRT ="))
check("корень НЕ владеет ESC (один владелец — сканер)", not has("root:OnKeyCodeTyped"))
check("консоль: бинд ищется LookupKeyBinding, не хардкодом клавиши",
    has("input.LookupKeyBinding") and has('string.find(b, "toggleconsole", 1, true)')
    and not has("RunConsoleCommand(\"toggleconsole\")\n            elseif"))
check("гашение gameui централизовано (root.Think — анимации)",
    not has("if gui.IsGameUIVisible() then gui.HideGameUI() end"))
check("кнопки: действие под pcall (нет «залипания»)", has("local ok, err = pcall(def.action)"))
check("оттиск вечер-26", has("вечер-26 (06.09)"))
check("перепост до TTL + isfunction-страховка", has("Menu.pendingTTL")
    and has("isfunction(RunGameUICommand)"))
check("активация — канон gui.ActivateGameUI", has("isfunction(gui.ActivateGameUI)"))
check("disconnect — прямой, без очереди", has('RunConsoleCommand("disconnect")')
    and not has('OpenGameuiWith("Disconnect"'))

--------------------------------------------------------------------- env
local T, RT = 100.0, 1000.0
local guiState = { visible = false, hides = 0, activates = 0 }
local rgui, cons, hooks, sysLog = {}, {}, {}, {}
local ESC = { down = false }
local KEYS = {}
local BINDS = {}
local FOCUS = { p = nil }

local function noopRet() return 0 end
local chatStub
chatStub = { INPUT_OPEN = false, HIST_OPEN = false,
    AddSystem = function(txt) sysLog[#sysLog + 1] = txt end,
    CloseHistory = function()
        chatStub.HIST_OPEN = false
        sysLog[#sysLog + 1] = "HIST-CLOSED"
    end }
local function newPanel()
    return setmetatable({ __panel = true }, {
        __index = function(t, k)
            if k == "Remove" then return function(s) s.__removed = true end end
            if rawget(t, k) ~= nil then return rawget(t, k) end
            return noopRet
        end,
        __newindex = function(t, k, v) rawset(t, k, v) end,
    })
end

local ENV = {
    SERVER = false,
    KEY_ESCAPE = 27,
    CurTime = function() return T end,
    RealTime = function() return RT end,
    SysTime = function() return T end,
    FrameTime = function() return 0.016 end,
    ScrW = function() return 1280 end,
    ScrH = function() return 720 end,
    Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end,
    Vector = function(x, y, z) return { x = x, y = y, z = z } end,
    Angle = function(p, y, r) return { p = p, y = y, r = r } end,
    IsValid = function(x) return type(x) == "table" and rawget(x, "__panel") == true
        and not rawget(x, "__removed") end,
    isfunction = function(v) return type(v) == "function" end,
    istable = function(v) return type(v) == "table" end,
    isstring = function(v) return type(v) == "string" end,
    isnumber = function(v) return type(v) == "number" end,
    gui = {
        IsGameUIVisible = function() return guiState.visible end,
        HideGameUI = function() guiState.hides = guiState.hides + 1; guiState.visible = false end,
        ActivateGameUI = function() guiState.activates = guiState.activates + 1; guiState.visible = true end,
    },
    input = {
        IsKeyDown = function(k) return (k == 27 and ESC.down) or (KEYS[k] == true) or false end,
        LookupKeyBinding = function(code) return BINDS[code] end,
    },
    vgui = { Create = function() return newPanel() end,
        GetKeyboardFocus = function() return FOCUS.p end },
    hook = { Add = function(nm, cl, fn) hooks[cl] = fn end, Run = function() end },
    timer = { Simple = function() end },
    RunConsoleCommand = function(...) cons[#cons + 1] = { ... } end,
    RunGameUICommand = function(cmd) rgui[#rgui + 1] = cmd end,
    draw = setmetatable({}, { __index = function() return noopRet end }),
    surface = setmetatable({ GetTextSize = function() return 40, 12 end },
        { __index = function() return noopRet end }),
    game = {
        SinglePlayer = function() return false end,
        GetMap = function() return "gm_flatgrass" end,
        CreateLocalServer = function() error("menu state only") end,
    },
    GRM = { PlayerBalance = 100, PlayerBank = 50 },
    GRMRP = { VERSION = "sim", JoinTime = 0 },
    GRMRPChat = chatStub,
    GRMRPMenu = {},
    string = setmetatable({}, { __index = function(_, k)
        if k == "Comma" then return function(_, n) return tostring(n) end end
        return string[k]
    end }),
    table = table, os = os,
    math = setmetatable({
        Clamp = function(v, a, b) return v < a and a or (v > b and b or v) end,
        Round = function(x) return math.floor(x + 0.5) end,
    }, { __index = math }),
}
ENV._G = ENV
setmetatable(ENV, { __index = function(t, k)
    local v = rawget(_G, k)
    if v ~= nil then return v end
    return noopRet
end })

local plStub = setmetatable({}, { __index = function(t, k)
    if k == "GetModel" then return function() return "models/player.mdl" end end
    if k == "GetMaxHealth" then return function() return 100 end end
    return noopRet
end })
ENV.LocalPlayer = function() return plStub end

local raw = read(SRC)
local fn = assert(loadstring(raw, SRC))
setfenv(fn, ENV)
local okL, errL = pcall(fn)
check("МЕНЮ ЗАГРУЗИЛОСЬ В СТЕНД", okL, errL)
if not okL then os.exit(1) end

local Menu = ENV.GRMRPMenu
local Think = hooks["GRMRPMenu_Takeover"]
check("хук GRMRPMenu_Takeover зарегистрирован", type(Think) == "function")

local function step(dt)
    dt = dt or 0.016
    T = T + dt; RT = RT + dt
    local r = Menu.root
    if ENV.IsValid(r) and r.Think then r:Think() end
    if Think then Think() end
end
local function press()  -- полный цикл нажатия: down-кадр, up-кадр
    ESC.down = true; step(); ESC.down = false; step()
end

print("\n=== 1. ОТКРЫТИЕ В КАДР НАЖАТИЯ (без вспышки gameui) ===")
guiState.visible = false
local h0 = guiState.hides
ESC.down = true
step()
check("окно открыто тем же кадром", ENV.IsValid(Menu.root))
check("ожидание видимости gameui НЕ требуется", h0 == guiState.hides)

print("\n=== 2. ЭХО КЛАВИШИ: движковая gameui гасится, окно цела ===")
guiState.visible = true -- bind gameui_activate от того же нажатия
step()
check("чужое gameui погашено", not guiState.visible and guiState.hides > h0)
check("наше окно НЕ пересоздано эхом", ENV.IsValid(Menu.root))
ESC.down = false
step()

print("\n=== 3. ЗАКРЫТИЕ БЕЗ ФОКУСА + СЛЕДУЮЩЕЕ НАЖАТИЕ СРАЗУ ===")
press()
check("ESC при открытом окне закрывает его (сканер, не панель)", not ENV.IsValid(Menu.root))
guiState.visible = true -- эхо закрытия
step()
check("эхо закрытия не переоткрыло окно", not ENV.IsValid(Menu.root))
check("эхо погашено", not guiState.visible)
T = T + 0.1; RT = RT + 0.1 -- тут старый грейс 0.4с СЪЕДАЛ нажатие
press()
check("повторное нажатие сразу работает (грейс снят)", ENV.IsValid(Menu.root))

print("\n=== 4. «ПЕРВЫЕ ПАРУ РАЗ» — цикл ×5 без деградации ===")
local okLoop = true
for i = 1, 5 do
    press() -- close
    if ENV.IsValid(Menu.root) then okLoop = false end
    guiState.visible = true; step() -- эхо
    press() -- open
    if not ENV.IsValid(Menu.root) then okLoop = false end
end
check("5 циклов открыть/закрыть — состояние чисто", okLoop)
check("pendingCmd не накопился", Menu.pendingCmd == nil)
check("ownsGameui не залип", Menu.ownsGameui == false)

print("\n=== 5. ПОРЯДОК ВЕРХНЕГО СЛОЯ: история → меню ===")
Menu.Close()
chatStub.HIST_OPEN = true
press()
check("первый ESC при истории: закрыта история, меню не открыто",
    chatStub.HIST_OPEN == false and not ENV.IsValid(Menu.root))
press()
check("следующий ESC: меню открыто", ENV.IsValid(Menu.root))
chatStub.HIST_OPEN = true
press()
check("ESC при открытом меню: сперва история", ENV.IsValid(Menu.root)
    and chatStub.HIST_OPEN == false)
chatStub.HIST_OPEN = false
Menu.Close()

print("\n=== 6. ЧАТ-ВВОД: ESC не наш ===")
chatStub.INPUT_OPEN = true
press()
check("при открытом вводе меню НЕ открывается", not ENV.IsValid(Menu.root))
chatStub.INPUT_OPEN = false

print("\n=== 7. REMAP: ESC не физический — fallback по видимости ===")
T = T + 1.0; RT = RT + 1.0; step() -- эхо-окно lastToggle истекло: guard не мешает
guiState.visible = true -- движок показал gameui от «своей» клавиши
step()
check("fallback открыл окно и погасил gameui", ENV.IsValid(Menu.root) and not guiState.visible)
Menu.Close()
T = T + 1.0; step()

print("\n=== 8. НАСТРОЙКИ: TTL-очередь, оба канала (контракт веч.-23) ===")
rgui, cons = {}, {}
Menu.OpenGameuiWith("OpenOptionsDialog")
check("активация gui.ActivateGameUI", guiState.visible and Menu.ownsGameui == true)
check("окно снято", not ENV.IsValid(Menu.root))
step(0.1); step(0.1); step(0.1)
local nrgui = #rgui
local ncons = 0
for _, c in ipairs(cons) do if c[1] == "gamemenucommand" and c[2] == "OpenOptionsDialog" then ncons = ncons + 1 end end
check("RunGameUICommand перепослан (>1)", nrgui > 1, nrgui)
check("gamemenucommand перепослан (>1)", ncons > 1, ncons)
T = T + 3.0; step()
check("TTL отпустил очередь", Menu.pendingCmd == nil)
check("своя сессия: gameui не гасим", guiState.visible)

print("\n=== 9. ВЛАДЕЛЕЦ ЗАКРЫЛ ENGINE-UI → сессия отпущена ===")
guiState.visible = false
step()
check("ownsGameui снят, перехват свободен", Menu.ownsGameui == false)
press()
check("ESC снова открывает наше меню", ENV.IsValid(Menu.root))

print("\n=== 10. БЕЗ ГЛОБАЛКИ RunGameUICommand — второй канал держит ===")
Menu.Close()
local savedRG = ENV.RunGameUICommand
ENV.RunGameUICommand = nil
rgui, cons = {}, {}
local okCall = pcall(Menu.OpenGameuiWith, "quit")
check("нет падения", okCall)
step(0.1); step(0.1)
local quitSent = false
for _, c in ipairs(cons) do if c[1] == "gamemenucommand" and c[2] == "quit" then quitSent = true end end
check("quit ушёл gamemenucommand-каналом", quitSent)
ENV.RunGameUICommand = savedRG
T = T + 3.0; step()

print("\n=== 11. ОШИБКА КНОПКИ — pcall + видимая строка ===")
do
    local okc, errc = pcall(function()
        local f = string.find(h, "local ok, err = pcall(def.action)", 1, true)
        if not f then error("нет pcall обёртки") end
    end)
    check("обёртка на месте", okc)
    check("сообщение об ошибке идёт в SystemLine",
        has('Menu.SystemLine("Кнопка «" .. tostring(def.title)')
        and has("GRMRPChat.AddSystem(text)"))
end

print("\n=== 12. КОНСОЛЬ ~ / Ё ПОД МЕНЮ (веч.-26) ===")
guiState.visible = false; step() -- отпустить сессию gameui после сцен.10
Menu.Close()
BINDS[96] = "toggleconsole"; BINDS[97] = nil
local rbind = hooks["GRMRPMenu_ConsoleKeys"]
check("хук перескана биндов зарегистрирован", type(rbind) == "function")
local function fireCount()
        local n = 0
        for _, c in ipairs(cons) do if c[1] == "toggleconsole" then n = n + 1 end end
        return n
    end
    cons = {}
    press() -- открыть меню (фронт ESC; скан консоли живёт при валидном root)
    FOCUS.p = Menu.root -- MakePopup в стенде — фокус считаем нашим
    check("меню открыто (предыстория чищена)", ENV.IsValid(Menu.root))
    KEYS[96] = true; step()
    KEYS[96] = false; step()
    check("~ при открытом меню дёргает toggleconsole", fireCount() == 1, fireCount())
    KEYS[96] = true; step(); step() -- два кадра удержания
    KEYS[96] = false; step()
    check("удержание — один выстрел на нажатие", fireCount() == 2, fireCount())
    FOCUS.p = newPanel() -- консоль/поле перехватили фокус
    KEYS[96] = true; step(); KEYS[96] = false; step()
    check("чужой фокус (печать в консоли) — клавишу НЕ трогаем", fireCount() == 2, fireCount())
    FOCUS.p = Menu.root
    BINDS[96] = nil; BINDS[105] = "toggleconsole +toggleconsole"
    hooks["GRMRPMenu_ConsoleKeys"]() -- перескан
    KEYS[105] = true; step(); KEYS[105] = false; step()
    check("ремап бинда: после OnBindingChanged ловится новая клавиша", fireCount() == 3, fireCount())
    chatStub.INPUT_OPEN = true -- открытый чат-ввод: ~ не наш (фокус у поля)
    KEYS[96] = true; step(); KEYS[96] = false; step()
    chatStub.INPUT_OPEN = false
    check("при открытом вводе ~ не трогаем (не спорим с полем)", fireCount() == 3, fireCount())
    KEYS[96] = false; KEYS[105] = false; FOCUS.p = nil

print(string.format("\nESC MENU FLOW: %d/%d, провалов: %d", total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
