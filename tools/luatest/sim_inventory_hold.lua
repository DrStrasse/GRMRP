--[[--------------------------------------------------------------------
    sim_inventory_hold — инвентарь на удержании клавиши.

    ЗАКАЗ ВЛАДЕЛЬЦА (31.08): «Инвентарь надо сделать удерживаемым, если
    он активируется на бинд».

    ЧТО БЫЛО. Клавиша работала переключателем: нажал — открыл, нажал
    ещё раз — закрыл. Отпускание клавиши не обрабатывалось вовсе —
    хука PlayerButtonUp для инвентаря не существовало.

    ЧТО ПРОВЕРЯЕМ. Поведение целиком: стенд поднимает мок GMod, грузит
    БОЕВОЙ модуль инвентаря и дёргает настоящие хуки PlayerButtonDown /
    PlayerButtonUp, как это делает движок.

      * удержание: зажал — открылось, отпустил — закрылось;
      * ВОСПРОИЗВЕДЕНИЕ ЛОВУШКИ: короткий клик отпускается почти
        мгновенно, и без порога окно закрылось бы в том же кадре, в
        котором открылось — игрок не успел бы ничего увидеть;
      * окно НЕ закрывается, пока предмет тащат мышью или открыто
        контекстное меню: перетаскивание оборвалось бы на полпути;
      * режим выключается конваром — остаётся привычный переключатель;
      * чужая клавиша, чат и игровое меню инвентарь не трогают.

    Запуск: luajit tools/luatest/sim_inventory_hold.lua
----------------------------------------------------------------------]]

local pass, fail = 0, 0
local function ok(v, name, extra)
    if v then pass = pass + 1 print("  ok   " .. name)
    else fail = fail + 1 print("  FAIL " .. name .. "   " .. tostring(extra or "")) end
end

-----------------------------------------------------------------------
-- Мок GMod: столько, чтобы клиентская часть модуля исполнилась.
-----------------------------------------------------------------------
SERVER, CLIENT = false, true
function AddCSLuaFile() end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function isfunction(v) return type(v) == "function" end
function isbool(v) return type(v) == "boolean" end
function IsValid(v) return istable(v) and v._valid ~= false end

local NOW = 100
function RealTime() return NOW end
function CurTime() return NOW end
function SysTime() return NOW end
function FrameTime() return 0.016 end

function Vector(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
math.Clamp = function(v, lo, hi)
    v = tonumber(v) or lo
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end
string.Trim = function(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
string.Explode = function(sep, str)
    local o = {}
    for p in tostring(str):gmatch("([^" .. sep .. "]+)") do o[#o + 1] = p end
    return o
end
string.StartWith = function(s, p) return string.sub(tostring(s), 1, #p) == p end
table.Count = function(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
table.Copy = function(t)
    if type(t) ~= "table" then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = table.Copy(v) end
    return o
end

--[[ Хуки записываем: стенд будет дёргать их сам, как движок. ]]
local HOOKS = {}
hook = {
    Add = function(event, name, fn)
        HOOKS[event] = HOOKS[event] or {}
        HOOKS[event][name] = fn
    end,
    Remove = function(event, name)
        if HOOKS[event] then HOOKS[event][name] = nil end
    end,
    Run = function() end,
    Call = function() end,
}
local function fire(event, ...)
    for _, fn in pairs(HOOKS[event] or {}) do fn(...) end
end

-- Конвары: настоящее хранилище, чтобы конвар режима реально работал.
local CVARS = {}
function CreateClientConVar(name, def) CVARS[name] = tostring(def) end
function GetConVarNumber(name) return tonumber(CVARS[name]) or 0 end
function GetConVar(name)
    return { GetInt = function() return math.floor(tonumber(CVARS[name]) or 0) end,
             GetFloat = function() return tonumber(CVARS[name]) or 0 end }
end
function RunConsoleCommand(name, val) CVARS[name] = tostring(val) end

timer = { Create = function() end, Simple = function() end, Remove = function() end,
          Exists = function() return false end }
util = { AddNetworkString = function() end, TableToJSON = function() return "{}" end,
         JSONToTable = function() return {} end }
net = setmetatable({}, { __index = function() return function() return "" end end })
concommand = { Add = function() end }
surface = setmetatable({}, { __index = function() return function() return 10, 10 end end })
draw = setmetatable({}, { __index = function() return function() end end })
vgui = { Create = function() return { _valid = false } end }
gui = {
    MousePos = function() return 0, 0 end,
    IsGameUIVisible = function() return false end,
    IsConsoleVisible = function() return false end,
    EnableScreenClicker = function() end,
}
input = { IsMouseDown = function() return false end, IsKeyDown = function() return false end }
function ScrW() return 1920 end
function ScrH() return 1080 end
function LocalPlayer() return _G.__LP end
notification = { AddLegacy = function() end }
chat = { AddText = function() end }
language = { Add = function() end }
killicon = { Add = function() end }
function print_(...) end
NOTIFY_ERROR, NOTIFY_HINT, NOTIFY_UNDO = 1, 2, 3
MOUSE_LEFT, MOUSE_RIGHT = 107, 108
KEY_I, KEY_G = 26, 24

GRM = { Notify = function() end }
GRM.UI = { Track = function(_, p) return p end, Close = function() end,
           IsOpen = function() return false end, SafeClear = function() end }

local ply = { _valid = true, _typing = false }
function ply:IsTyping() return self._typing end
function ply:GetModel() return "models/player/kleiner.mdl" end
function ply:Nick() return "Test" end
_G.__LP = ply

assert(loadfile("lua/autorun/sh_grm_inventory.lua"))()
local INV = GRM.Inventory
assert(INV, "GRM.Inventory не загрузился")

ok(HOOKS["PlayerButtonDown"] and HOOKS["PlayerButtonDown"]["GRM_Inv_Bind"] ~= nil,
    "бинд открытия зарегистрирован")
ok(HOOKS["PlayerButtonUp"] and HOOKS["PlayerButtonUp"]["GRM_Inv_BindUp"] ~= nil,
    "ИСПРАВЛЕНО: обработчик ОТПУСКАНИЯ появился (раньше его не было вовсе)")

-----------------------------------------------------------------------
-- Подменяем окно заглушкой: сам VGUI нам не нужен, нужна логика.
-----------------------------------------------------------------------
local state = { open = false, busy = false, opens = 0, closes = 0 }
INV.RequestOpen = function() state.open = true state.opens = state.opens + 1 end
INV.CloseGUI = function() state.open = false state.closes = state.closes + 1 end
INV.IsOpen = function() return state.open end
INV.IsBusy = function() return state.busy end

local KEY = 26   -- условная клавиша инвентаря
CVARS["grm_cl_inv_key"] = tostring(KEY)

local function reset()
    state.open, state.busy = false, false
    state.opens, state.closes = 0, 0
    NOW = NOW + 10          -- уводим время, чтобы не сработала защита от дребезга
end

-----------------------------------------------------------------------
print("\n=== 1. УДЕРЖАНИЕ: ЗАЖАЛ — ОТКРЫТО, ОТПУСТИЛ — ЗАКРЫТО ===")
-----------------------------------------------------------------------
do
    CVARS["grm_cl_inv_hold"] = "1"
    reset()
    fire("PlayerButtonDown", ply, KEY)
    ok(state.open, "по нажатию окно открылось")

    NOW = NOW + 1.0         -- подержали секунду
    fire("PlayerButtonUp", ply, KEY)
    ok(not state.open, "ИСПРАВЛЕНО: по отпусканию окно закрылось")
    ok(state.closes == 1, "закрытие ровно одно", state.closes)
end

-----------------------------------------------------------------------
print("\n=== 2. КОРОТКИЙ КЛИК ОКНО НЕ СХЛОПЫВАЕТ ===")
-----------------------------------------------------------------------
do
    --[[ ВОСПРОИЗВЕДЕНИЕ ЛОВУШКИ. Клавишу отпускают через считанные
         миллисекунды. Без порога окно закрылось бы в том же кадре, в
         котором открылось: игрок нажал — и ничего не увидел. ]]
    reset()
    fire("PlayerButtonDown", ply, KEY)
    ok(state.open, "клик открыл окно")

    NOW = NOW + 0.05        -- отпустили почти сразу
    fire("PlayerButtonUp", ply, KEY)
    ok(state.open, "окно осталось открытым — короткое нажатие не закрывает")
    ok(state.closes == 0, "закрытий не было", state.closes)
end

do
    -- И дальше оно работает как обычный переключатель.
    NOW = NOW + 1
    fire("PlayerButtonDown", ply, KEY)
    ok(not state.open, "повторное нажатие закрывает окно")
end

-----------------------------------------------------------------------
print("\n=== 3. ГРАНИЦА ПОРОГА ===")
-----------------------------------------------------------------------
do
    reset()
    fire("PlayerButtonDown", ply, KEY)
    NOW = NOW + 0.24
    fire("PlayerButtonUp", ply, KEY)
    ok(state.open, "0.24 с — ещё клик, окно остаётся")

    reset()
    fire("PlayerButtonDown", ply, KEY)
    NOW = NOW + 0.30
    fire("PlayerButtonUp", ply, KEY)
    ok(not state.open, "0.30 с — уже удержание, окно закрылось")
end

-----------------------------------------------------------------------
print("\n=== 4. НЕ ЗАКРЫВАЕМ ПОСРЕДИ ДЕЙСТВИЯ ===")
-----------------------------------------------------------------------
do
    --[[ Если отпустить клавишу, пока предмет тащат мышью, окно
         закрылось бы прямо из-под руки и перетаскивание оборвалось. ]]
    reset()
    fire("PlayerButtonDown", ply, KEY)
    NOW = NOW + 1
    state.busy = true       -- тащим предмет / открыто контекстное меню
    fire("PlayerButtonUp", ply, KEY)
    ok(state.open, "во время перетаскивания окно не закрылось")

    -- Действие закончилось — окно закрывается обычным способом.
    state.busy = false
    NOW = NOW + 1
    fire("PlayerButtonDown", ply, KEY)
    ok(not state.open, "после действия клавиша закрывает как переключатель")
end

-----------------------------------------------------------------------
print("\n=== 5. РЕЖИМ ОТКЛЮЧАЕТСЯ КОНВАРОМ ===")
-----------------------------------------------------------------------
do
    CVARS["grm_cl_inv_hold"] = "0"
    reset()
    fire("PlayerButtonDown", ply, KEY)
    ok(state.open, "окно открылось")
    NOW = NOW + 2
    fire("PlayerButtonUp", ply, KEY)
    ok(state.open, "с выключенным удержанием отпускание НЕ закрывает")
    NOW = NOW + 1
    fire("PlayerButtonDown", ply, KEY)
    ok(not state.open, "работает переключателем, как раньше")
    CVARS["grm_cl_inv_hold"] = "1"
end

-----------------------------------------------------------------------
print("\n=== 6. ЧУЖИЕ КЛАВИШИ И ЧАТ ===")
-----------------------------------------------------------------------
do
    reset()
    fire("PlayerButtonDown", ply, KEY + 5)
    ok(not state.open, "чужая клавиша инвентарь не открывает")

    ply._typing = true
    NOW = NOW + 1
    fire("PlayerButtonDown", ply, KEY)
    ok(not state.open, "в чате клавиша не срабатывает")
    ply._typing = false

    -- Клавиша не назначена — бинд молчит.
    CVARS["grm_cl_inv_key"] = "0"
    NOW = NOW + 1
    fire("PlayerButtonDown", ply, 0)
    ok(not state.open, "невыставленная клавиша ничего не открывает")
    CVARS["grm_cl_inv_key"] = tostring(KEY)
end

do
    -- Отпускание чужой клавиши не должно закрывать окно.
    reset()
    fire("PlayerButtonDown", ply, KEY)
    NOW = NOW + 1
    fire("PlayerButtonUp", ply, KEY + 5)
    ok(state.open, "отпускание другой клавиши окно не трогает")
end

-----------------------------------------------------------------------
print("\n=== 7. ИСХОДНИКИ ===")
-----------------------------------------------------------------------
do
    local function readf(p)
        local fh = assert(io.open(p, "rb"))
        local t = fh:read("*a") fh:close() return t
    end
    local core = readf("lua/autorun/sh_grm_inventory.lua")
    local ui = readf("lua/autorun/client/cl_grm_inventory_ui.lua")
    local f4 = readf("lua/autorun/sh_grm_f4menu.lua")

    ok(core:find('CreateClientConVar("grm_cl_inv_hold"', 1, true) ~= nil,
        "конвар режима создаётся")
    local up = core:match('hook%.Add%("PlayerButtonUp", "GRM_Inv_BindUp".-\n    end%)')
    ok(up and up:find("IsBusy", 1, true) ~= nil,
        "отпускание учитывает незаконченное действие")
    ok(up and up:find("0.25", 1, true) ~= nil, "порог удержания задан явно")

    ok(ui:find("function INV.IsBusy", 1, true) ~= nil, "IsBusy объявлена в UI")
    local busy = ui:match("function INV%.IsBusy%(%).-\nend")
    ok(busy and busy:find("dragData", 1, true) ~= nil, "учитывает перетаскивание")
    ok(busy and busy:find("_ctxMenu", 1, true) ~= nil, "и открытое контекстное меню")
    --[[ dermamenu.GetOpenMenus не документирован: в рабочем коде на
         него полагаться нельзя, ссылку на меню держим свою. ]]
    -- Ищем ВЫЗОВ, а не слово: в комментарии рядом объясняется, почему
    -- этот API не используется, и поиск по подстроке ловил бы текст.
    ok(busy and busy:find("dermamenu%s*%.") == nil,
        "не опирается на недокументированный API")
    ok(ui:find("INV._ctxMenu = menu", 1, true) ~= nil, "меню запоминается при открытии")

    ok(f4:find("grm_cl_inv_hold", 1, true) ~= nil, "режим настраивается в F4")
    ok(f4:find("HEAD + #BINDS * BIND_ROW_H + PAD + 24 + 30", 1, true) ~= nil,
        "высота блока учитывает новую строку — вёрстка не поедет")
end

-----------------------------------------------------------------------
print(string.format("\nИТОГО: %d ok, %d FAIL", pass, fail))
os.exit(fail == 0 and 0 or 1)
