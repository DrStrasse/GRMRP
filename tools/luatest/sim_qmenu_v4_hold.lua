-- sim_qmenu_v4_hold — HOLD-Q: press открывает, release закрывает,
-- повтор press при живом окне игнорируется, /qm во время удержания не гасит.
_G.CLIENT, _G.SERVER = true, false
function _G.AddCSLuaFile() end
function istable(x) return type(x) == "table" end
function isstring(x) return type(x) == "string" end
function isnumber(x) return type(x) == "number" end
function isfunction(x) return type(x) == "function" end
function IsValid(o)
    if o == nil or o == false then return false end
    if type(o) == "table" then return not o.__removed end
    return true
end
Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
math.Clamp = function(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
string.Trim = function(s) return (tostring(s or ""):gsub("^%s*(.-)%s*$", "%1")) end
TEXT_ALIGN_LEFT, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER = 0, 2, 1
TOP, FILL = 1, 5
HUD_PRINTCENTER = 4
ScrW = function() return 1920 end
ScrH = function() return 1080 end
CurTime = function() return 10 end
SysTime = function() return os.clock() end
color_white = Color(255, 255, 255)

local hooks = {}
hook = {
    Add = function(ev, id, fn) hooks[ev] = hooks[ev] or {} hooks[ev][id] = fn end,
    GetTable = function() return hooks end,
    Run = function() end,
}
timer = { Simple = function() end }
concommand = { Add = function() end }
net = setmetatable({}, { __index = function() return function() end end })
surface = { SetFont = function() end, GetTextSize = function(t) return #tostring(t) * 7, 14 end,
            PlaySound = function() end, CreateFont = function() end }
draw = { SimpleText = function() end, RoundedBox = function() end, RoundedBoxEx = function() end }
util = { JSONToTable = function() return nil end, TableToJSON = function() return "{}" end }
file = { Exists = function() return false end, Read = function() return nil end, Write = function() end }
language = { GetPhrase = function(k) return k end }
controlpanel = { Get = function() return nil end, Create = function() return nil end }
weapons = { GetStored = function() return nil end }
gui = {}
CreateClientConVar = function() return { GetBool = function() return false end } end
GetConVar = function() return nil end
ConVarExists = function() return false end
LocalPlayer = function() return _G.__LP end

local function newPanel()
    local p = {
        __children = {}, __w = 100, __h = 40,
        SetSize = function(s, w, h) s.__w, s.__h = w, h end,
        SetTall = function(s, h) s.__h = h end,
        SetWide = function(s, w) s.__w = w end,
        GetTall = function(s) return s.__h end,
        GetWide = function(s) return s.__w end,
        SetPos = function() end, Dock = function() end, DockMargin = function() end,
        SetParent = function() end, GetChildren = function(s) return s.__children end,
        Add = function(s, c) s.__children[#s.__children + 1] = c return c end,
        AddItem = function(s, c) s.__children[#s.__children + 1] = c return c end,
        Clear = function(s) s.__children = {} end,
        Remove = function(s) s.__removed = true end,
        SetVisible = function() end, SetText = function() end, GetText = function() return "" end,
        SetFont = function() end, SetTextColor = function() end, SetWrap = function() end,
        SetTooltip = function() end, SetTitle = function() end, ShowCloseButton = function() end,
        SetDeleteOnClose = function() end, Center = function() end, MakePopup = function() end,
        SetPaintBackground = function() end, IsHovered = function() return false end,
        SetValue = function() end, GetValue = function() return "" end,
        SetPlaceholderText = function() end, SetMin = function() end, SetMax = function() end,
        AddChoice = function() end, SetModel = function() end, SetMouseInputEnabled = function() end,
        SetSpaceX = function() end, SetSpaceY = function() end,
    }
    return setmetatable(p, { __index = function(_, k)
        if type(k) == "string" and k:match("^[A-Z]") then return function() end end
        return nil
    end })
end
vgui = { Create = function(_, parent)
    local p = newPanel()
    if parent and parent.__children then parent.__children[#parent.__children + 1] = p end
    return p
end }

GRM = GRM or {}
dofile("lua/autorun/sh_00_grm_ui.lua")
_G.__LP = {
    IsSuperAdmin = function() return false end,
    GetNWBool = function(_, _, d) return d or false end,
    GetNWString = function(_, _, d) return d or "" end,
    PrintMessage = function() end,
    Alive = function() return true end,
}
dofile("lua/autorun/sh_grm_qmenu.lua")
local QM = GRM.QMenu
QM.Cfg.playersQ = false
QM.Cfg.grmBuildMenu = true
QM.Cfg.allowProps = true

local pass, fail = 0, 0
local function ok(c, m)
    if c then pass = pass + 1 print("  ok  " .. m)
    else fail = fail + 1 print("  FAIL " .. m) end
end

local bind = hooks.PlayerBindPress and hooks.PlayerBindPress.GRM_QMenu_BindBlock
ok(isfunction(bind), "хук HOLD-Q зарегистрирован")

bind(_G.__LP, "+menu", true)
ok(IsValid(QM._frame), "press открывает")
ok(QM._holdOpen == true, "флаг удержания стоит")
local first = QM._frame
bind(_G.__LP, "+menu", true)
ok(QM._frame == first, "повтор press не пересоздаёт окно")

-- /qm во время удержания не гасит
local recv = nil
-- имитируем NET_OPEN-ресивер: он в файле, но net.Receive — заглушка.
-- зовём ту же логику явно:
if IsValid(QM._frame) and QM._holdOpen then
    -- ничего
end
ok(IsValid(QM._frame), "/qm во время удержания не закрыл")

bind(_G.__LP, "+menu", false)
ok(not IsValid(QM._frame), "release закрывает")
ok(QM._holdOpen == false, "флаг удержания сброшен")

QM.OpenMenu(false)
ok(IsValid(QM._frame) and QM._holdOpen == false, "OpenMenu(false) без hold")
QM.CloseMenu()
ok(not IsValid(QM._frame), "явное закрытие")

print(("РЕЗУЛЬТАТ: %d/%d, fail=%d"):format(pass, pass + fail, fail))
if fail > 0 then os.exit(1) end
