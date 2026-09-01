-- sim_qmenu_v4_schema — построение схемы из ClientConVar, включая мусор
function istable(x) return type(x) == "table" end
function isstring(x) return type(x) == "string" end
function isnumber(x) return type(x) == "number" end
function isfunction(x) return type(x) == "function" end
function IsValid() return false end
util = { AddNetworkString = function() end, TableToJSON = function() return "{}" end,
         JSONToTable = function() return nil end }
file = { Exists = function() return false end, Read = function() return nil end, Write = function() end }
hook = { Add = function() end, Run = function() end }
timer = { Simple = function() end }
net = setmetatable({}, { __index = function() return function() end end })
concommand = { Add = function() end }
AddCSLuaFile = function() end
SERVER, CLIENT = true, false
math.Clamp = function(v, lo, hi) if v < lo then return lo end if v > hi then return hi end return v end
string.Trim = function(s) return (tostring(s or ""):gsub("^%s*(.-)%s*$", "%1")) end

dofile("lua/autorun/sh_grm_qmenu.lua")
local QM = GRM.QMenu

local pass, fail = 0, 0
local function ok(c, m)
    if c then pass = pass + 1 print("  ok  " .. m)
    else fail = fail + 1 print("  FAIL " .. m) end
end

local auto = QM.SchemaFromConVars({ freeze = "1", label = "", speed = "120", junk = true })
local by = {}
for _, r in ipairs(auto) do by[r.cvar] = r end
ok(by.freeze and by.freeze.type == "bool", "0/1 → bool")
ok(by.speed and by.speed.type == "number", "число → number")
ok(by.label and by.label.type == "text", "пусто → text")
ok(by.junk and by.junk.type == "text", "прочее значение → text")

local auto2 = QM.SchemaFromConVars({ [1] = "x", [""] = "y" })
ok(#auto2 <= 1, "числовые ключи не попадают в схему как cvar")

ok(QM.SchemaFromConVars(nil) and #QM.SchemaFromConVars(nil) == 0, "nil → пустая схема")
ok(QM.SchemaFromConVars("nope") and #QM.SchemaFromConVars("nope") == 0, "не таблица → пустая")

local huge = {}
for i = 1, 80 do huge["k" .. i] = "0" end
ok(#QM.SchemaFromConVars(huge) == 32, "потолок 32 поля")

local sch, kind = QM.ResolveSchema("grm_perm_tool")
ok(kind == "hand", "ручная схема перм-тула")
ok(sch and #sch >= 3, "у перм-тула есть поля")
local none, nk = QM.ResolveSchema("нет_такого_тула")
ok(none == nil and nk == "none", "нет схемы и нет ClientConVar → none")

local ts, tk = QM.ResolveSchema("textscreen")
ok(ts == nil and tk == "none", "textscreen без ручной схемы — не дампить")
local light, lk = QM.ResolveSchema("light")
ok(lk == "hand" and light and #light >= 3, "light — ручная схема с подписями")
ok(light[1].label ~= light[1].cvar, "у light человеческая подпись, не сырой cvar")

local function hasRow(tool, cvar, kind)
    local rows = QM.ResolveSchema(tool)
    for _, row in ipairs(rows or {}) do
        if row.cvar == cvar and (not kind or row.type == kind) then return true end
    end
    return false
end
ok(hasRow("pulley", "pulley_forcelimit", "slider") and hasRow("pulley", "pulley_material", "choice"), "шкив: прочность и материал")
ok(hasRow("winch", "winch_fwd_group", "key") and hasRow("winch", "winch_fwd_speed", "slider"), "лебёдка: клавиши и скорости")
ok(hasRow("hydraulic", "hydraulic_addlength", "slider") and hasRow("hydraulic", "hydraulic_toggle", "bool"), "гидравлика: ход и переключатель")
ok(hasRow("muscle", "muscle_period", "slider") and hasRow("muscle", "muscle_group", "key"), "мышца: период и клавиша")
ok(hasRow("rope", "rope_width", "slider") and hasRow("slider", "slider_width", "slider"), "верёвка и направляющая: толщина")
ok(hasRow("axis", "axis_torquelimit", "slider") and hasRow("ballsocket", "ballsocket_nocollide", "bool"), "ось и шарнир: ограничения")
ok(hasRow("motor", "motor_torque", "slider") and hasRow("wheel", "wheel_fwd", "key"), "мотор и колесо: сила и клавиши")
ok(hasRow("thruster", "thruster_force", "slider") and hasRow("hoverball", "hoverball_strength", "slider"), "ускоритель и ховербол: сила")
ok(hasRow("balloon", "balloon_force", "slider") and QM.ResolveSchema("balloon")[3].type == "color", "воздушный шар: сила и палитра")

-- UI не должен звать автосхему: ResolveSchema не смотрит weapons
local src
do
    local fh = io.open("lua/autorun/sh_grm_qmenu.lua", "r")
    src = fh:read("*a") fh:close()
end
local body = src:match("function QM%.ResolveSchema.-%sfunction QM%.")
ok(body and not body:find("SchemaFromConVars", 1, true), "ResolveSchema не зовёт SchemaFromConVars")
ok(body and not body:find("weapons.GetStored", 1, true), "ResolveSchema не лезет в weapons")

print(("РЕЗУЛЬТАТ: %d/%d, fail=%d"):format(pass, pass + fail, fail))
if fail > 0 then os.exit(1) end
