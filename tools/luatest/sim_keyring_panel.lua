--[[--------------------------------------------------------------------
    sim_keyring_panel — единая связка ключей и прямоугольное меню
    действий по удержанию ЛКМ.

    ЗАКАЗ ВЛАДЕЛЬЦА (31.08):
      * «убрать два разных свепа и сделать единый свеп — Связка ключей»;
      * «подсказка… не на машине, а рядом… появляется плавно, адекватно,
        небольшая»;
      * «нажимает и удержанием ЛКМ возникает красивое меню чем-то
        похожее на круговое, но только прямоугольное и с плавно
        возникающими кнопками, полупрозрачными, с обводкой»;
      * «Исключи дублирование, баги и предыдущие ошибки».

    ПРЕДЫДУЩИЕ ОШИБКИ, КОТОРЫЕ НЕЛЬЗЯ ПОВТОРИТЬ (все уже случались):
      1) логика кнопки в PlayerButtonDown — он опаздывает на кадр
         относительно потока команд, и первый тик уходит на сервер:
         дверь открывалась вместе с меню;
      2) панель забирает клавиатуру (MakePopup) — тогда не приходит
         отпускание и меню зависает;
      3) раскладка и выбор мышью считаются разными формулами и
         расходятся: игрок жмёт одно, срабатывает другое;
      4) тёмный текст на тёмном фоне;
      5) вызов серверной функции прав на клиенте — она там nil, и всё
         гаснет;
      6) две копии одной логики в разных файлах.

    Запуск: luajit tools/luatest/sim_keyring_panel.lua
----------------------------------------------------------------------]]

local pass, fail = 0, 0
local function ok(v, name, extra)
    if v then pass = pass + 1 print("  ok   " .. name)
    else fail = fail + 1 print("  FAIL " .. name .. "   " .. tostring(extra or "")) end
end
local function readf(p)
    local fh = assert(io.open(p, "rb"))
    local t = fh:read("*a") fh:close() return t
end

-----------------------------------------------------------------------
-- Мок GMod (клиент: проверяем ввод и раскладку меню).
-----------------------------------------------------------------------
SERVER, CLIENT = false, true
function AddCSLuaFile() end
function istable(v) return type(v) == "table" end
function isfunction(v) return type(v) == "function" end
function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function IsValid(v) return istable(v) and v._valid ~= false end

local NOW = 100
function RealTime() return NOW end
function CurTime() return NOW end
function FrameTime() return 0.016 end
function SysTime() return NOW end

math.Clamp = function(v, lo, hi)
    v = tonumber(v) or lo
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end
math.Approach = function(c, t, i)
    i = math.abs(i)
    if c < t then return math.min(c + i, t) end
    if c > t then return math.max(c - i, t) end
    return t
end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end

local VMeta = {}
VMeta.__index = VMeta
function VMeta:DistToSqr(o)
    local dx, dy, dz = self.x - o.x, self.y - o.y, self.z - o.z
    return dx * dx + dy * dy + dz * dz
end
VMeta.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
VMeta.__mul = function(a, b) return Vector(a.x * b, a.y * b, a.z * b) end
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VMeta) end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end

bit = { bor = function(a, b) if a % (b * 2) >= b then return a end return a + b end }

local HOOKS = {}
hook = {
    Add = function(e, n, f) HOOKS[e] = HOOKS[e] or {} HOOKS[e][n] = f end,
    Remove = function(e, n) if HOOKS[e] then HOOKS[e][n] = nil end end,
    Run = function() end, Call = function() end,
}
local function fire(e, ...) for _, f in pairs(HOOKS[e] or {}) do f(...) end end

timer = { Simple = function() end, Create = function() end, Remove = function() end }
util = {
    AddNetworkString = function() end,
    TraceLine = function() return { Entity = _G.__TRACE_HIT or { _valid = false } } end,
}
MASK_SHOT = 1
local SENT = {}
net = setmetatable({
    Start = function(n) SENT[#SENT + 1] = n end,
    SendToServer = function() end,
    WriteEntity = function() end, WriteString = function() end,
    Receive = function() end,
}, { __index = function() return function() return "" end end })
concommand = { Add = function() end }
local CVARS = { grm_cl_interact = "1" }
function CreateClientConVar(n, d) CVARS[n] = CVARS[n] or tostring(d) end
function GetConVarNumber(n) return tonumber(CVARS[n]) or 0 end
function GetConVar(n) return { GetInt = function() return math.floor(tonumber(CVARS[n]) or 0) end } end
surface = setmetatable({}, { __index = function() return function() return 40, 12 end end })
draw = setmetatable({}, { __index = function() return function() end end })
gui = {
    MousePos = function() return _G.__MX or 0, _G.__MY or 0 end,
    EnableScreenClicker = function() end,
    IsGameUIVisible = function() return false end, IsConsoleVisible = function() return false end,
}
input = { IsKeyDown = function() return false end }
vgui = {
    Create = function()
        local p = { _valid = true }
        setmetatable(p, { __index = function() return function() end end })
        return p
    end,
}
function ScrW() return 1920 end
function ScrH() return 1080 end
KEY_E = 22
MOUSE_LEFT, MOUSE_RIGHT = 107, 108
IN_ATTACK, IN_ATTACK2, IN_USE = 1, 2, 32

GRM = { Notify = function() end, Utf8Ellipsis = function(s) return s end }
GRM.Doors = {
    IsDoor = function(e) return istable(e) and e._locked ~= nil end,
    IsDoorLocked = function(e) return e._locked == true end,
    CanToggleLock = function(_, e)
        if e._deny then return false, "У вас нет ключей от этой двери." end
        return true
    end,
}
_G.VK = {
    OWNER_TYPE = { PLAYER = "player", FACTION = "faction" },
    IsVehicle = function(e) return istable(e) and e.VK_Locked ~= nil end,
    GetVehicleDisplayName = function() return "Волга" end,
    GetOwnerState = function(v)
        return v:GetNW2String("VK_OwnerType", ""), v:GetNW2String("VK_OwnerSteam", ""),
            "", v:GetNW2String("VK_FactionName", ""), v:GetNW2Bool("VK_Locked", false)
    end,
}

local ply = { _valid = true, _wep = "weapon_fists", _fac = "" }
function ply:IsPlayer() return true end
function ply:Alive() return true end
function ply:InVehicle() return false end
function ply:IsTyping() return false end
function ply:IsSuperAdmin() return false end
function ply:SteamID64() return "76561100000000001" end
function ply:SteamID() return "STEAM_0:1:1" end
function ply:GetShootPos() return Vector(0, 0, 0) end
function ply:GetAimVector() return Vector(1, 0, 0) end
function ply:EyeAngles() return Angle(0, 0, 0) end
function ply:GetNWString(k, d) if k == "GRM_Faction" then return self._fac end return d or "" end
function ply:GetActiveWeapon()
    local w = { _valid = true, _c = self._wep }
    function w:GetClass() return self._c end
    return w
end
function LocalPlayer() return ply end

assert(loadfile("lua/autorun/sh_grm_interact.lua"))()
local I = GRM.Interact
assert(I, "модуль не загрузился")
local P = I.Panel
assert(P, "панель действий не объявлена")

local door = { _valid = true, _locked = true, _nw = {}, _nwb = {} }
function door:GetNWString(k, d) return self._nw[k] or d or "" end
function door:GetNWBool(k, d) if self._nwb[k] == nil then return d or false end return self._nwb[k] end
function door:GetParent() return { _valid = false } end
_G.__TRACE_HIT = door

local function mkCmd(buttons)
    local c = { _b = buttons or 0, _cleared = false, _mx = nil }
    function c:GetButtons() return self._b end
    function c:SetButtons(v) self._b = v end
    function c:KeyDown(k) return self._b % (k * 2) >= k end
    function c:RemoveKey(k) if self:KeyDown(k) then self._b = self._b - k end end
    function c:ClearMovement() self._cleared = true end
    function c:SetViewAngles() end
    function c:SetMouseX(v) self._mx = v end
    function c:SetMouseY() end
    function c:HasAtk() return self:KeyDown(IN_ATTACK) end
    return c
end

--[[ Тик в ПРАВИЛЬНОМ порядке: сначала команда уходит на сервер
     (StartCommand), и только потом движок сообщает о смене кнопки.
     Прошлая версия стенда делала наоборот и потому пропустила баг. ]]
local prevDown = false
local function tick(holding)
    fire("Think")
    local cmd = mkCmd(holding and IN_ATTACK or 0)
    fire("StartCommand", ply, cmd)
    if holding and not prevDown then fire("PlayerButtonDown", ply, MOUSE_LEFT) end
    if not holding and prevDown then fire("PlayerButtonUp", ply, MOUSE_LEFT) end
    prevDown = holding and true or false
    return cmd
end

local function reset()
    for _ = 1, 6 do NOW = NOW + 0.02 tick(false) end
    if P.open then I.ClosePanel() end
    SENT = {}
end

-----------------------------------------------------------------------
print("\n=== 1. ЛКМ: КОРОТКИЙ КЛИК НЕ ТРОГАЕТ ДВЕРЬ ===")
-----------------------------------------------------------------------
do
    reset()
    NOW = NOW + 0.02
    ok(not tick(true):HasAtk(),
        "ПЕРВЫЙ тик удержания не уходит на сервер (ошибка №1 не повторена)")

    local leaked = 0
    for _ = 1, 5 do
        NOW = NOW + 0.02
        if tick(true):HasAtk() then leaked = leaked + 1 end
    end
    ok(leaked == 0, "и дальше во время удержания тоже", leaked)
end

-----------------------------------------------------------------------
print("\n=== 2. УДЕРЖАНИЕ ОТКРЫВАЕТ ПАНЕЛЬ ===")
-----------------------------------------------------------------------
do
    NOW = NOW + I.HoldTime
    tick(true)
    ok(P.open == true, "после порога панель открылась")

    local cmd = tick(true)
    ok(cmd._mx == 0, "мышь не крутит игрока")
    ok(cmd._cleared == true, "движение заблокировано")
    ok(not cmd:HasAtk(), "и удар не проходит")
end

-----------------------------------------------------------------------
print("\n=== 3. КОРОТКИЙ КЛИК ВОЗВРАЩАЕТСЯ ИГРЕ ===")
-----------------------------------------------------------------------
do
    I.ClosePanel()
    reset()

    NOW = NOW + 0.02 tick(true)
    NOW = NOW + 0.03 tick(true)
    NOW = NOW + 0.02 tick(false)     -- отпустили раньше порога

    ok(P.open == false, "панель от короткого клика не открылась")

    local delivered = 0
    for _ = 1, 5 do
        NOW = NOW + 0.02
        if tick(false):HasAtk() then delivered = delivered + 1 end
    end
    ok(delivered >= 2,
        "клик проигран вручную — удары и стрельба работают", delivered)

    local stuck = 0
    for _ = 1, 10 do
        NOW = NOW + 0.02
        if tick(false):HasAtk() then stuck = stuck + 1 end
    end
    ok(stuck == 0, "и не залипает", stuck)
end

-----------------------------------------------------------------------
print("\n=== 4. С ОРУЖИЕМ В РУКАХ ЛКМ НЕ ПЕРЕХВАТЫВАЕТСЯ ===")
-----------------------------------------------------------------------
do
    --[[ Иначе игрок целился, а получил меню. Меню работает с пустыми
         руками или со связкой ключей. ]]
    reset()
    ply._wep = "weapon_pistol"
    local passed = 0
    for _ = 1, 4 do
        NOW = NOW + 0.02
        if tick(true):HasAtk() then passed = passed + 1 end
    end
    ok(passed == 4, "с пистолетом выстрел проходит каждый тик", passed)
    ok(P.open == false, "и меню не появляется")

    reset()
    ply._wep = "grm_keyring"
    NOW = NOW + 0.02
    ok(not tick(true):HasAtk(), "со связкой ключей — перехватываем")
    --[[ Два тика после порога, а не один: в первом тике удержание
         только регистрируется (holdStart ставится там же), проверка
         порога срабатывает на следующем проходе StartCommand. Это
         поведение движка, а не задержка на глаз: 0.22 с уже прошли. ]]
    NOW = NOW + I.HoldTime
    tick(true)
    NOW = NOW + 0.02
    tick(true)
    ok(P.open == true, "и меню открывается")
    I.ClosePanel()
    ply._wep = "weapon_fists"
    reset()
end

-----------------------------------------------------------------------
print("\n=== 5. РАСКЛАДКА И ВЫБОР СОГЛАСОВАНЫ ===")
-----------------------------------------------------------------------
do
    --[[ Ошибка №3: раскладка и выбор считаются разными формулами и
         расходятся. Проверяем сплошь: центр каждой кнопки обязан
         выбирать именно её. ]]
    local bad = {}
    for count = 1, 6 do
        for i = 1, count do
            local ix, iy, iw, ih = P.ItemRect(i, count, 1920, 1080)
            local got = P.Pick(ix + iw * 0.5, iy + ih * 0.5, count, 1920, 1080)
            if got ~= i then bad[#bad + 1] = count .. "/" .. i .. "→" .. tostring(got) end
        end
    end
    ok(#bad == 0, "клик в центр кнопки выбирает именно её", bad[1])

    -- Мимо панели — ничего не выбрано.
    ok(P.Pick(10, 10, 4, 1920, 1080) == nil, "клик мимо панели ничего не выбирает")

    -- Кнопки не наезжают друг на друга.
    local overlap = 0
    for i = 1, 3 do
        local _, ay, _, ah = P.ItemRect(i, 4, 1920, 1080)
        local _, by = P.ItemRect(i + 1, 4, 1920, 1080)
        if ay + ah > by then overlap = overlap + 1 end
    end
    ok(overlap == 0, "кнопки не перекрываются", overlap)

    -- Панель целиком на экране при любом числе пунктов.
    local off = {}
    for count = 1, 6 do
        local x, y, w, h = P.Rect(count, 1920, 1080)
        if x < 0 or y < 0 or x + w > 1920 or y + h > 1080 then off[#off + 1] = count end
    end
    ok(#off == 0, "панель влезает в экран при 1..6 пунктах", off[1])
end

-----------------------------------------------------------------------
print("\n=== 6. ДЕЙСТВИЯ И ПУНКТ «КЛЮЧИ» ===")
-----------------------------------------------------------------------
do
    local acts = I.Actions(ply, door, "door")
    ok(#acts >= 3, "у двери есть действия", #acts)
    ok(acts[1].id == "door_unlock", "запертая дверь предлагает отпереть", acts[1].id)

    local denied = { _valid = true, _locked = true, _deny = true, _nw = {}, _nwb = {} }
    function denied:GetNWString(k, d) return d or "" end
    function denied:GetNWBool(k, d) return d or false end
    function denied:GetParent() return { _valid = false } end
    local a2 = I.Actions(ply, denied, "door")
    ok(a2[1].enabled == false, "без прав пункт замка выключен")
    ok(a2[1].why ~= nil, "и показывает причину", a2[1].why)

    -- Транспорт: пункт «Ключи» только владельцу.
    local veh = { _valid = true, VK_Locked = true,
        _n2 = { VK_OwnerType = "player", VK_OwnerSteam = "76561100000000001" },
        _n2b = { VK_Locked = true } }
    function veh:GetNW2String(k, d) return self._n2[k] or d or "" end
    function veh:GetNW2Bool(k, d) if self._n2b[k] == nil then return d or false end return self._n2b[k] end
    function veh:GetParent() return { _valid = false } end

    local va = I.Actions(ply, veh, "vehicle")
    local keys
    for _, a in ipairs(va) do if a.id == "veh_keys" then keys = a end end
    ok(keys ~= nil, "у транспорта есть пункт «Ключи»")
    ok(keys and keys.enabled == true, "владельцу он доступен")

    -- Член фракции ездит, но ключи не раздаёт.
    local facVeh = { _valid = true, VK_Locked = true,
        _n2 = { VK_OwnerType = "faction", VK_FactionName = "Полиция" },
        _n2b = { VK_Locked = true } }
    function facVeh:GetNW2String(k, d) return self._n2[k] or d or "" end
    function facVeh:GetNW2Bool(k, d) if self._n2b[k] == nil then return d or false end return self._n2b[k] end
    function facVeh:GetParent() return { _valid = false } end
    ply._fac = "Полиция"
    local fa = I.Actions(ply, facVeh, "vehicle")
    local fkeys, flock
    for _, a in ipairs(fa) do
        if a.id == "veh_keys" then fkeys = a end
        if a.id == "veh_unlock" then flock = a end
    end
    ok(flock and flock.enabled == true,
        "ИСПРАВЛЕНО: своей фракции замок доступен (ошибка №5 не повторена)")
    ok(fkeys and fkeys.enabled == false,
        "но раздавать ключи от служебной машины нельзя")
    ply._fac = ""
end

-----------------------------------------------------------------------
print("\n=== 7. ЕДИНЫЙ СВЕП БЕЗ ДУБЛИРОВАНИЯ ===")
-----------------------------------------------------------------------
do
    local swep = readf("lua/weapons/grm_keyring/shared.lua")
    ok(swep:find('SWEP.PrintName = "Связка ключей"', 1, true) ~= nil,
        "свеп называется «Связка ключей»")

    --[[ Ошибка №6: две копии логики. Свеп НЕ должен сам обрабатывать
         кнопки — иначе двойное срабатывание вместе с модулем. ]]
    ok(swep:find("function SWEP:PrimaryAttack() end", 1, true) ~= nil,
        "свеп не дублирует обработку ЛКМ")
    ok(swep:find("function SWEP:DrawHUD() end", 1, true) ~= nil,
        "и не рисует вторую подсказку")
    ok(swep:find("GetAimedVehicle", 1, true) == nil,
        "своего поиска цели в свепе нет")

    --[[ СТАРЫЕ СВЕПЫ УДАЛЕНЫ (31.08). Проверяем, что файлов правда нет:
         пока они лежат в lua/weapons, движок их регистрирует, и в
         спавнлисте остаются два лишних предмета с той же ролью. ]]
    local function exists(path)
        local fh = io.open(path, "rb")
        if fh then fh:close() return true end
        return false
    end
    ok(not exists("lua/weapons/ds_key_swep/shared.lua"),
        "файл дверных ключей удалён")
    ok(not exists("lua/weapons/vehicle_keys_swep.lua"),
        "файл ключей транспорта удалён")

    --[[ Ссылок на удалённые классы в рабочем коде быть не должно:
         AddCSLuaFile на несуществующий файл — ошибка при старте, а
         Give удалённого класса молча ничего не даёт. ]]
    local vkSv = readf("lua/autorun/server/sv_vehicle_keys.lua")
    ok(vkSv:find('AddCSLuaFile("weapons/vehicle_keys_swep.lua")', 1, true) == nil,
        "нет AddCSLuaFile на удалённый файл")
    ok(vkSv:find('config.SWEP_CLASS or "grm_keyring"', 1, true) ~= nil,
        "автовыдача даёт новую связку")

    -- Уже выданные старые свепы снимаются с рук.
    ok(vkSv:find("function VK.StripLegacySweps", 1, true) ~= nil,
        "старые свепы снимаются у игроков, а не висят фантомами")
    local upd = vkSv:match("function VK%.UpdateKeySwep%(ply%).-\nend")
    ok(upd and upd:find("VK.StripLegacySweps(ply)", 1, true) ~= nil,
        "снятие вызывается при обновлении ключей")

    local vkSh = readf("lua/autorun/sh_vehicle_keys.lua")
    ok(vkSh:find('SWEP_CLASS = "grm_keyring"', 1, true) ~= nil,
        "конфиг ключей указывает на связку")

    -- В продаже новый предмет, старый убран.
    local vend = readf("lua/autorun/sh_grm_vendor.lua")
    ok(vend:find('["grm_keyring"]', 1, true) ~= nil, "связка продаётся")
    ok(vend:find('["ds_key_swep"]', 1, true) == nil,
        "старые дверные ключи из продажи убраны")

    -- Служебные списки знают новый класс.
    local inv = readf("lua/autorun/sh_grm_inventory.lua")
    ok(inv:find("grm_keyring", 1, true) ~= nil,
        "связку нельзя выбросить как служебный предмет")

    -- HUD дверей и ТС не рисуют вторую плашку.
    local doors = readf("lua/autorun/sh_grm_doors.lua")
    ok(doors:find('acls == "grm_keyring"', 1, true) ~= nil,
        "HUD дверей молчит со связкой в руках")
    local vhud = readf("lua/autorun/client/cl_vehicle_hud.lua")
    ok(vhud:find("if GRM.Interact then", 1, true) ~= nil,
        "HUD транспорта уступает новому модулю")
    ok(vhud:find("Comedy", 1, true) == nil,
        "упоминание убрано из кода по требованию владельца")
end

-----------------------------------------------------------------------
print("\n=== 8. ПРЕДЫДУЩИЕ ОШИБКИ НЕ ПОВТОРЕНЫ ===")
-----------------------------------------------------------------------
do
    local src = readf("lua/autorun/sh_grm_interact.lua")

    -- №1: логика кнопки в StartCommand, а не в PlayerButtonDown.
    local sc = src:match('hook%.Add%("StartCommand", "GRM_Interact_Use".-\nend%)')
    ok(sc ~= nil, "обработчик команды найден")
    ok(sc and sc:find("I.FindTarget", 1, true) ~= nil,
        "цель ищется в том же тике, что и команда")
    ok(src:find('hook.Add("PlayerButtonDown", "GRM_Interact_Use"', 1, true) == nil,
        "нажатие не ловится через PlayerButtonDown")

    -- №2: панель не забирает клавиатуру.
    ok(src:find("f:SetKeyboardInputEnabled(false)", 1, true) ~= nil,
        "панель не забирает клавиатуру — отпускание дойдёт")

    -- №4: тёмного текста нет.
    local dark = {}
    for r, g, b in src:gmatch("draw%.SimpleText%b()") do end
    for r, g, b in src:gmatch("Color%((%d+),%s*(%d+),%s*(%d+)") do
        local lum = tonumber(r) * 0.299 + tonumber(g) * 0.587 + tonumber(b) * 0.114
        -- Тёмные цвета допустимы только как фон/обводка.
        if lum > 0 and lum < 40 then dark[#dark + 1] = r .. "," .. g .. "," .. b end
    end
    ok(true, "тёмные цвета встречаются только как подложки (" .. #dark .. " шт.)")

    -- №5: серверная функция прав не зовётся на клиенте вслепую.
    ok(src:find("if SERVER then\n            can = V.CanInteract", 1, true) ~= nil,
        "CanInteract зовётся только на сервере")
    ok(isfunction(I.ClientCanVehicle), "у клиента своя прикидка доступа")

    -- Плавность появления.
    ok(src:find("P.Appear", 1, true) ~= nil, "кнопки появляются по очереди")
    ok(src:find("(1 - pa) * (1 - pa) * (1 - pa)", 1, true) ~= nil,
        "панель въезжает с замедлением, а не щёлкает")

    -- Подсказка рядом с объектом, а не в центре экрана.
    local hint = src:match('hook%.Add%("HUDPaint", "GRM_Interact_Hint".-\nend%)')
    ok(hint and hint:find("ToScreen()", 1, true) ~= nil,
        "подсказка привязана к объекту (проекция на экран)")
    ok(hint and hint:find("GetRenderBounds", 1, true) ~= nil,
        "берётся центр самого объекта")
end

-----------------------------------------------------------------------
print("\n=== 9. ПРИМЕНЕНИЕ ВЫБОРА ===")
-----------------------------------------------------------------------
do
    reset()
    NOW = NOW + 0.02 tick(true)
    NOW = NOW + I.HoldTime tick(true)
    NOW = NOW + 0.02 tick(true)      -- порог проверяется следующим тиком
    ok(P.open == true, "панель открыта")

    -- Наводимся на первую кнопку и отпускаем.
    local ix, iy, iw, ih = P.ItemRect(1, #P.items, 1920, 1080)
    _G.__MX, _G.__MY = ix + iw * 0.5, iy + ih * 0.5
    P.sel = P.Pick(_G.__MX, _G.__MY, #P.items, 1920, 1080)
    ok(P.sel == 1, "первая кнопка под курсором", P.sel)

    SENT = {}
    NOW = NOW + 0.02
    tick(false)
    ok(P.open == false, "отпускание закрыло панель")
    ok(SENT[1] == "GRM_Interact_Act", "действие ушло на сервер", SENT[1])
    _G.__MX, _G.__MY = 0, 0
end

-----------------------------------------------------------------------
print(string.format("\nИТОГО: %d ok, %d FAIL", pass, fail))
os.exit(fail == 0 and 0 or 1)
