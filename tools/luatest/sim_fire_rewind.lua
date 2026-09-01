--[[--------------------------------------------------------------------
    sim_fire_rewind — геометрия смотки рукава (серверная HoseMoveHint)
    ./.luabuild/lj/src/luajit tools/luatest/sim_fire_rewind.lua
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

-- Мок ровно настолько, чтобы dofile sh_grm_fire_hose.lua отдал HoseMoveHint.
local env = {
    SERVER = true,
    CLIENT = false,
    AddCSLuaFile = function() end,
    include = function() end,
    hook = { Add = function() end, Run = function() end },
    util = { AddNetworkString = function() end },
    net = {
        Start = function() end, Receive = function() end,
        WriteUInt = function() end, WriteVector = function() end,
        WriteEntity = function() end, WriteBool = function() end,
        WriteString = function() end, Broadcast = function() end, Send = function() end,
    },
    ents = { Create = function() end, FindByClass = function() return {} end },
    constraint = {},
    Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end,
    Vector = function(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end,
    IsValid = function(e) return e ~= nil and e ~= false end,
    isvector = function() return false end,
    istable = function(t) return type(t) == "table" end,
    isstring = function(s) return type(s) == "string" end,
    isfunction = function(f) return type(f) == "function" end,
    CurTime = function() return 0 end,
    print = function() end,
    math = math, string = string, table = table,
    ipairs = ipairs, pairs = pairs,
    tonumber = tonumber, tostring = tostring,
    pcall = pcall, type = type,
    GRM = {},
}
setmetatable(env, { __index = _G })

local src = read("addons/grm_fire/lua/autorun/sh_grm_fire_hose.lua")
local loader = loadstring or load
local chunk, err = loader(src)
if not chunk then
    print("LOAD FAIL: " .. tostring(err))
    os.exit(1)
end
if setfenv then setfenv(chunk, env) end
chunk()
local A = env.GRM.FireAddon
assert(A and A.HoseMoveHint, "HoseMoveHint не загрузился")

local function V(x, y) return { x = x, y = y, z = 0 } end
local prev, last = V(140, 0), V(210, 0)

local function hint(px, py, opt)
    return A.HoseMoveHint(V(px, py), last, prev, opt or { step = 70 })
end

print("\n=== HoseMoveHint: вперёд / назад по прямой ===")
check("стоит на последнем узле — idle", hint(210, 0) == "idle", hint(210, 0))
check("шаг вперёд 80 — lay", hint(290, 0) == "lay", hint(290, 0))
check("7 юн назад по линии — rewind", hint(203, 0) == "rewind", hint(203, 0))
check("середина сегмента — rewind", hint(175, 0) == "rewind", hint(175, 0))
check("на предыдущем узле — rewind", hint(140, 0) == "rewind", hint(140, 0))
check("за prev к источнику — rewind", hint(80, 0) == "rewind", hint(80, 0))

print("\n=== HoseMoveHint: диагональ / S / ALT / скорость ===")
check("диагональ назад (180,40) — rewind", hint(180, 40) == "rewind", hint(180, 40))
check("в сторону от last (210,80) — lay", hint(210, 80) == "lay", hint(210, 80))
check("S у конца — rewind", hint(210, 0, { step = 70, back = true }) == "rewind")
check("ALT у конца — reel", hint(210, 0, { step = 70, reel = true }) == "reel")
check("скорость к prev — rewind", hint(215, 5, { step = 70, vel = V(-200, 0) }) == "rewind",
    hint(215, 5, { step = 70, vel = V(-200, 0) }))
check("скорость вперёд — lay", hint(290, 0, { step = 70, vel = V(200, 0) }) == "lay")
check("ALT далеко — не reel", hint(800, 800, { step = 70, reel = true }) ~= "reel")

print("\n=== серверный Think зовёт hint, не клиент ===")
local init = read("addons/grm_fire/lua/entities/grm_fire_hose/init.lua")
check("HoseMoveHint в init", init:find("HoseMoveHint", 1, true) ~= nil)
check("MoveHint в Think", init:find("self:MoveHint", 1, true) ~= nil)
check("нет клиентской смотки в SWEP Think", (function()
    local w = read("addons/grm_fire/lua/weapons/weapon_grm_hose.lua")
    local th = w:find("function SWEP:Think", 1, true) or 0
    local nx = w:find("function SWEP:", th + 10) or #w
    local body = w:sub(th, nx)
    return body:find("TryRewind", 1, true) == nil and body:find("if CLIENT then return end", 1, true) ~= nil
end)())
check("IN_BACK в MoveOpt", init:find("IN_BACK", 1, true) ~= nil)
check("IN_WALK reel", init:find("IN_WALK", 1, true) ~= nil)
check("нет лимита LayStep*1.25", init:find("LayStep or 70) * 1.25", 1, true) == nil)
check("FollowHost на сервере", init:find("function ENT:FollowHost", 1, true) ~= nil)
check("Think зовёт FollowHost", init:find("self:FollowHost()", 1, true) ~= nil)
check("SyncAnchors SrcPos", init:find("function ENT:SyncAnchors", 1, true) ~= nil)
check("PayoutFromSource", init:find("function ENT:PayoutFromSource", 1, true) ~= nil)
check("InsertLayAt", init:find("function ENT:InsertLayAt", 1, true) ~= nil)
check("нет натяжки DragNode в FollowHost", (function()
    local a = init:find("function ENT:FollowHost", 1, true) or 0
    local b = init:find("function ENT:Rewind", 1, true) or #init
    return init:sub(a, b):find("DragNode", 1, true) == nil
end)())

print("\n=== тяга за машиной ===")
local nx, ny, moved, d = A.HoseDragPoint(100, 0, 0, 0, 50)
check("HoseDragPoint есть", A.HoseDragPoint ~= nil)
check("далеко — сдвинуть до maxSeg", moved == true and math.abs(nx - 50) < 0.01 and math.abs(ny) < 0.01, tostring(nx) .. "," .. tostring(ny))
local sx, sy, sm = A.HoseDragPoint(30, 0, 0, 0, 50)
check("внутри maxSeg — не трогать", sm == false and math.abs(sx - 30) < 0.01)
check("compact близко", A.HoseShouldCompact(20, 52) == true)
check("compact далеко нет", A.HoseShouldCompact(40, 52) == false)

print("")
if fails == 0 then print("ВСЕ ТЕСТЫ ПРОЙДЕНЫ (fire rewind)")
else print("ПРОВАЛОВ: " .. fails) end
print(("FIRE_REWIND failures=%d"):format(fails))
os.exit(fails == 0 and 0 or 1)
