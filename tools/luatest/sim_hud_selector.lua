--[[--------------------------------------------------------------------
    sim_hud_selector — контракт HUD v10.3 (селектор vs физган)
    ./.luabuild/lj/src/luajit tools/luatest/sim_hud_selector.lua
----------------------------------------------------------------------]]
local function read(p)
    local f = assert(io.open(p, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

local fails = 0
local function check(name, cond, extra)
    if cond then print("  OK   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "   " .. tostring(extra or "")) end
end
local function has(src, n) return src:find(n, 1, true) ~= nil end

local hud = read("lua/autorun/client/cl_grm_hud.lua")

print("\n=== КОНТРАКТ ИСТОЧНИКА ===")
check("версия 10.4 в шапке", has(hud, "GRM HUD v10.4"))
check("приветствие v10.4", has(hud, "HUD v10.4 загружен"))
check("принт v10.4", has(hud, '[GRM] HUD v10.4 загружен'))
check("хелпер IsPropToolBusy", has(hud, "function GRM.HUD.IsPropToolBusy"))
check("хелпер IsBuildWeapon", has(hud, "function GRM.HUD.IsBuildWeapon"))
check("физган в белом списке", has(hud, "weapon_physgun"))
check("гравиган в белом списке", has(hud, "weapon_physcannon"))
check("проверка IN_ATTACK", has(hud, "IN_ATTACK"))
check("тихий сброс бара", has(hud, "function AbortSelectorQuiet") or has(hud, "local function AbortSelectorQuiet"))
check("захват глотает invnext", has(hud, 'b == "invnext"') or has(hud, 'bind == "invnext"'))
check("Draw гасит бар при захвате", has(hud, "IsPropToolBusy(lpBusy)"))
check("таймаут не выбирает при захвате", has(hud, "таймаут НЕ вызывает SelectWeapon"))

-- Порядковый линт: AbortSelectorQuiet объявлен до первого вызова
do
    local def = hud:find("local function AbortSelectorQuiet", 1, true) or 0
    local use = hud:find("AbortSelectorQuiet()", 1, true) or 0
    check("AbortSelectorQuiet объявлен до вызова", def > 0 and use > def, "def=" .. def .. " use=" .. use)
end

print("\n=== РАНТАЙМ (мок клиента) ===")
CLIENT = true
SERVER = false
IN_ATTACK = 1
IN_ATTACK2 = 2048
IN_USE = 32
TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, TEXT_ALIGN_RIGHT = 0, 1, 2
TEXT_ALIGN_TOP, TEXT_ALIGN_BOTTOM = 3, 4

function Color(r, g, b, a) return { r = r or 0, g = g or 0, b = b or 0, a = a or 255 } end
function IsValid(x) return type(x) == "table" and x._valid ~= false end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function isfunction(v) return type(v) == "function" end
function Lerp(t, a, b) return a + (b - a) * t end
function math.Clamp(x, a, b)
    if x < a then return a end
    if x > b then return b end
    return x
end
function math.Approach(cur, target, inc)
    if cur < target then return math.min(cur + inc, target) end
    return math.max(cur - inc, target)
end
function math.Round(x) return math.floor(x + 0.5) end
function string.Comma(n) return tostring(n) end
function ScrW() return 1920 end
function ScrH() return 1080 end

local NOW = 10
function CurTime() return NOW end
function FrameTime() return 0.016 end

surface = {
    CreateFont = function() end,
    SetDrawColor = function() end,
    DrawOutlinedRect = function() end,
    DrawRect = function() end,
    SetFont = function() end,
    GetTextSize = function(s) return #tostring(s) * 7, 14 end,
}
draw = {
    RoundedBox = function() end,
    SimpleText = function() end,
}

local H = {}
hook = {
    Add = function(ev, id, fn) H[ev] = H[ev] or {} H[ev][id] = fn end,
    Run = function(ev, ...)
        if not H[ev] then return end
        for _, fn in pairs(H[ev]) do fn(...) end
    end,
}
net = {
    Receive = function() end,
    Start = function() end,
    SendToServer = function() end,
    ReadInt = function() return 0 end,
    ReadString = function() return "" end,
    ReadUInt = function() return 0 end,
}
timer = { Simple = function() end }
input = { selected = nil, SelectWeapon = function(w) input.selected = w end }

local function makeWep(cls, slot, pos, name)
    return {
        _valid = true,
        GetClass = function() return cls end,
        GetSlot = function() return slot end,
        GetSlotPos = function() return pos end,
        GetPrintName = function() return name end,
        Clip1 = function() return -1 end,
        GetPrimaryAmmoType = function() return -1 end,
    }
end

local physgun = makeWep("weapon_physgun", 0, 0, "Physics Gun")
local crowbar = makeWep("weapon_crowbar", 0, 1, "Crowbar")
local pistol  = makeWep("weapon_pistol", 1, 0, "Pistol")

local ply = {
    _valid = true,
    _alive = true,
    _keys = {},
    _weps = { physgun, crowbar, pistol },
    _active = physgun,
    Alive = function(self) return self._alive end,
    Health = function() return 100 end,
    GetMaxHealth = function() return 100 end,
    Armor = function() return 0 end,
    GetActiveWeapon = function(self) return self._active end,
    GetWeapons = function(self) return self._weps end,
    GetAmmoCount = function() return 0 end,
    KeyDown = function(self, k) return self._keys[k] == true end,
}
function LocalPlayer() return ply end

GRM = {}
-- Ядро GRM (sh_00_grm_ui + sh_01_grm_core) — как на сервере, до модулей.
dofile("tools/luatest/lib_grm_core.lua")()
dofile("lua/autorun/client/cl_grm_hud.lua")

local bind = H.PlayerBindPress and H.PlayerBindPress.GRM_HUD_Selector
local paint = H.HUDPaint and H.HUDPaint.GRM_HUD_Main
check("хук PlayerBindPress", type(bind) == "function")
check("хук HUDPaint", type(paint) == "function")
check("API IsBuildWeapon", type(GRM.HUD.IsBuildWeapon) == "function")
check("API IsPropToolBusy", type(GRM.HUD.IsPropToolBusy) == "function")

check("физган = build", GRM.HUD.IsBuildWeapon(ply) == true)
ply._keys[IN_ATTACK] = false
check("без ЛКМ не busy", GRM.HUD.IsPropToolBusy(ply) == false)
ply._keys[IN_ATTACK] = true
check("с ЛКМ busy", GRM.HUD.IsPropToolBusy(ply) == true)

ply._active = crowbar
check("монтировка не build", GRM.HUD.IsBuildWeapon(ply) == false)
check("монтировка+ЛКМ не busy", GRM.HUD.IsPropToolBusy(ply) == false)
ply._active = physgun

-- Без захвата колесо только подсвечивает. Выбор — исключительно ЛКМ.
ply._keys[IN_ATTACK] = false
input.selected = nil
NOW = 20
local rFree = bind(ply, "invnext", true)
check("без захвата invnext глотается", rFree == true)
NOW = 24
paint()
check("таймаут НЕ выбирает подсвеченное", input.selected == nil)
NOW = 25
bind(ply,"invnext",true)
local rConfirm=bind(ply,"+attack",true)
check("ЛКМ подтверждает выбор",rConfirm==true and input.selected==crowbar)

-- С захватом колесо НЕ должно выбрать другое оружие даже после таймаута
ply._keys[IN_ATTACK] = true
input.selected = nil
NOW = 30
local rBusy = bind(ply, "invnext", true)
check("с захватом invnext глотается (ваниль не сменит)", rBusy == true)
NOW = 34
paint()
check("с захватом таймаут НЕ выбирает", input.selected == nil, tostring(input.selected))

-- Слоты и lastinv тоже глушатся
input.selected = nil
local rSlot = bind(ply, "slot2", true)
check("с захватом slot2 глотается", rSlot == true)
NOW = 38
paint()
check("с захватом slot не выбирает", input.selected == nil)

local rLast = bind(ply, "lastinv", true)
check("с захватом lastinv глотается", rLast == true)

-- +attack при захвате не подтверждает селектор и не глотает клик
input.selected = nil
local rAtk = bind(ply, "+attack", true)
check("+attack при захвате не глотается", rAtk == nil)
check("+attack при захвате не SelectWeapon", input.selected == nil)

-- Гравиган тоже
local grav = makeWep("weapon_physcannon", 0, 2, "Gravity Gun")
ply._weps = { physgun, crowbar, pistol, grav }
ply._active = grav
ply._keys[IN_ATTACK] = true
check("гравиган = build", GRM.HUD.IsBuildWeapon(ply) == true)
check("гравиган+ЛКМ busy", GRM.HUD.IsPropToolBusy(ply) == true)
input.selected = nil
bind(ply, "invprev", true)
NOW = 50
paint()
check("гравиган: колесо не снимает", input.selected == nil)

print("")
if fails == 0 then print("ВСЕ ТЕСТЫ ПРОЙДЕНЫ (hud selector)")
else print("ПРОВАЛОВ: " .. fails) end
print(("HUDSEL failures=%d"):format(fails))
os.exit(fails == 0 and 0 or 1)
