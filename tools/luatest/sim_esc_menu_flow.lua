--[[--------------------------------------------------------------------
    sim_esc_menu_flow — рантайм-контракт ESC-меню с движком (вечер-23).
    Ground truth — официальный lua-код движка (Facepunch/garrysmod):
      * gui.ActivateGameUI/HideGameUI/IsGameUIVisible — реальные глобалки
        клиента (lua/menu/openurl.lua зовёт их так же);
      * канон команд стандартных диалогов — «gamemenucommand
        OpenOptionsDialog|OpenServerBrowser» и RunGameUICommand("quit")
        (lua/menu/mainmenu.lua, кнопки нативного фолбека);
      * RunGameUICommand — глобалка меню-состояния, из игрового может не
        существовать → isfunction-страховка;
      * команды принимаются только когда gameui реально поднято, а «принято»
        из lua не наблюдаемо → перепост каждый кадр до TTL (идемпотентно).
    Сценарии гоняются НА ЖИВОМ коде cl_grmrp_menu.lua (окружение-заглушки,
    счётчик времени управляемый): перехват ESC, квест настройки/браузер,
    мастерская (nil-команда), guard без RunGameUICommand, disconnect без
    очереди, честное Close, грейс-окно.
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

print("\n=== 0. СТАТИЧЕСКИЙ КОНТРАКТ ДВИЖКА ===")
local function has(n) return h:find(n, 1, true) ~= nil end
check("активация — канон gui.ActivateGameUI", has("isfunction(gui.ActivateGameUI)"))
check("gameui_activate остался только запасным каналом",
    select(2, h:gsub('pcall%(function%(%) RunConsoleCommand%("gameui_activate"%) end%)', "%0")) == 1)
check("команды — движковые строки OpenOptionsDialog/OpenServerBrowser",
    has('"OpenOptionsDialog"') and has('"OpenServerBrowser"'))
check("выход — движковый quit через gameui", has('OpenGameuiWith("quit")'))
check("disconnect — прямой клиентский консольный без очереди",
    has('RunConsoleCommand("disconnect")') and not has('OpenGameuiWith("Disconnect"'))
check("перепост по TTL (не одноразовый выстрел)", has("Menu.pendingTTL"))
check("одевка флагов ДО Menu.Close в OpenGameuiWith", (function()
    local a = h:find("function Menu.OpenGameuiWith", 1, true)
    if not a then return false end
    local i1 = h:find("Menu.ownsGameui = true", a, true)
    local i2 = h:find("Menu.Close()", a, true)
    return i1 and i2 and i1 < i2
end)())
check("честный Close: гасит чужое gameui", has("if not Menu.ownsGameui and not Menu.pendingCmd and gui.IsGameUIVisible() then"))
check("нет зова несуществующего API", not has("SetKeyInputEnabled") and not has("SetBounds"))

--------------------------------------------------------------------- env
local T, RT = 100.0, 1000.0
local guiState = { visible = false, hides = 0, activates = 0 }
local rgui, cons, hooks = {}, {}, {}
local sysLog = {}

local noopRet
local function newPanel()
    local p = setmetatable({ __panel = true }, {
        __index = function(t, k)
            if k == "Remove" then return function(s) s.__removed = true end end
            if rawget(t, k) ~= nil then return rawget(t, k) end
            return noopRet
        end,
        __newindex = function(t, k, v) rawset(t, k, v) end,
    })
    return p
end
function noopRet() return 0 end

local ENV = {
    SERVER = false,
    CurTime = function() return T end,
    RealTime = function() return RT end,
    SysTime = function() return T end,
    FrameTime = function() return 0.016 end,
    ScrW = function() return 1280 end,
    ScrH = function() return 720 end,
    Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end,
    Vector = function(x, y, z) return { x = x, y = y, z = z } end,
    Angle = function(p, y, r) return { p = p, y = y, r = r } end,
    IsValid = function(x) return type(x) == "table" and rawget(x, "__panel") == true and not rawget(x, "__removed") end,
    isfunction = function(v) return type(v) == "function" end,
    istable = function(v) return type(v) == "table" end,
    isstring = function(v) return type(v) == "string" end,
    isnumber = function(v) return type(v) == "number" end,
    gui = {
        IsGameUIVisible = function() return guiState.visible end,
        HideGameUI = function() guiState.hides = guiState.hides + 1; guiState.visible = false end,
        ActivateGameUI = function() guiState.activates = guiState.activates + 1; guiState.visible = true end,
    },
    vgui = { Create = function() return newPanel() end },
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
    GRMRPMenu = {}, -- присваивание на nil-глобал ушло бы в noop-функцию
    GRMRP = { VERSION = "sim", JoinTime = 0,
        Economy = nil, Jobs = nil, DermaSVG = nil },
    GRMRPChat = { INPUT_OPEN = false, HIST_OPEN = false,
        AddSystem = function(txt) sysLog[#sysLog + 1] = txt end },
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

local plStub = setmetatable({ __panel = false }, { __index = function(t, k)
    if k == "GetModel" then return function() return "models/player.mdl" end end
    if k == "GetMaxHealth" then return function() return 100 end end
    return noopRet
end })
ENV.LocalPlayer = function() return plStub end

local okL, errL
do
    local raw = read(SRC)
    local fn = loadstring(raw, SRC)
    if fn then setfenv(fn, ENV); okL, errL = pcall(fn) end
end
check("МЕНЮ ЗАГРУЗИЛОСЬ В СТЕНД без ошибки", okL, errL)
if not okL then print("\nESC MENU FLOW: " .. total - fails .. "/" .. total .. ", провалов: " .. fails) os.exit(1) end

local Menu = ENV.GRMRPMenu -- пред-заполнен в ENV
local Think = hooks["GRMRPMenu_Takeover"]
check("хук GRMRPMenu_Takeover зарегистрирован", type(Think) == "function")

local function step(dt)
    dt = dt or 0.016
    T = T + dt; RT = RT + dt
    local r = Menu.root
    if ENV.IsValid(r) and r.Think then r:Think() end
    if Think then Think() end
end

print("\n=== 1. ПЕРЕХВАТ ESC ===")
guiState.visible = true
step()
check("чужое gameui погашено", not guiState.visible and guiState.hides >= 1)
check("наше окно открыто", ENV.IsValid(Menu.root))

print("\n=== 2. НАСТРОЙКИ: перепост до TTL, оба канала ===")
rgui, cons = {}, {}
Menu.OpenGameuiWith("OpenOptionsDialog")
check("активация — через gui.ActivateGameUI", guiState.visible and Menu.ownsGameui == true)
check("наше окно снято (не воюет с gameui)", not ENV.IsValid(Menu.root))
step(0.1); step(0.1); step(0.1)
local nrgui = #rgui
local ncons = 0
for _, c in ipairs(cons) do if c[1] == "gamemenucommand" and c[2] == "OpenOptionsDialog" then ncons = ncons + 1 end end
check("RunGameUICommand перепослан (>1 раз)", nrgui > 1, nrgui)
check("gamemenucommand перепослан (>1 раз)", ncons > 1, ncons)
check("окно не пересоздано во время pending", not ENV.IsValid(Menu.root))
T = T + 3.0; RT = RT + 3.0; step()
check("TTL истёк — очередь отпущена", Menu.pendingCmd == nil)
check("gameui владельца не погашено нашим хуком", guiState.visible)
step(); step()
check("после TTL диалог не трогаем (окно не всплыло)", not ENV.IsValid(Menu.root))

print("\n=== 3. БЕЗ ГЛОБАЛКИ RunGameUICommand (игровое состояние) ===")
local savedRG = ENV.RunGameUICommand
ENV.RunGameUICommand = nil
rgui, cons = {}, {}
local okCall = pcall(Menu.OpenGameuiWith, "quit")
check("нет падения при nil RunGameUICommand", okCall)
step(0.1); step(0.1)
local quitSent = false
for _, c in ipairs(cons) do if c[1] == "gamemenucommand" and c[2] == "quit" then quitSent = true end end
check("quit ушёл вторым каналом", quitSent)
ENV.RunGameUICommand = savedRG
T = T + 3.0; step()

print("\n=== 4. МАСТЕРСКАЯ: nil-команда = главное меню движка (аддоны в нём) ===")
guiState.visible = false
rgui, cons = {}, {}
local act0 = guiState.activates
Menu.OpenGameuiWith(nil)
check("gameui активировано", guiState.visible and guiState.activates == act0 + 1)
check("ложной команды в очередь нет", Menu.pendingCmd == nil)
step(); step()
check("наше окно НЕ всплыло поверх движкового меню", not ENV.IsValid(Menu.root))
guiState.visible = false
step()
check("пользователь закрыл engine UI — сессия отпущена", Menu.ownsGameui == false)

print("\n=== 5. ЧЕСТНЫЙ CLOSE И ГРЕЙС ===")
guiState.visible = true
Menu.Open()
check("окно открыто", ENV.IsValid(Menu.root))
guiState.visible = true -- движок снова вскрыл gameui под нашим ESC-слоем
step()
check("root.Think гасит gameui каждый кадр", not guiState.visible or guiState.hides >= 3)
Menu.Close()
check("после Close gameui погашен (не висит под следующим ESC)", not guiState.visible)
local hidesBefore = guiState.hides
guiState.visible = true
step() -- сразу после Close: грейс — тихо гасим, окно НЕ открываем
check("грейс 0.4с: только скрытие, без пересоздания окна",
    not ENV.IsValid(Menu.root) and guiState.hides > hidesBefore)
T = T + 1.0; RT = RT + 1.0
guiState.visible = true
step()
check("после грейса ESC-перехват восстановлен", ENV.IsValid(Menu.root))

print("\n=== 6. СИСТЕМНАЯ СТРОКА — канон библиотеки чата ===")
check("GRMRPChat.AddSystem вызывается (не pushSystem)",
    has("GRMRPChat.AddSystem(") and not has("GRMRPChat.pushSystem"))

print(string.format("\nESC MENU FLOW: %d/%d, провалов: %d", total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
