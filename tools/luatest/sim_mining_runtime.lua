--[[ Живой прогон шахты: цены с файлом, продажа руды, выдача и сдача бура.
     Загружается серверная часть sh_grm_mining.lua в моке GMod.
     Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_mining_runtime.lua ]]
SERVER, CLIENT = true, false
function AddCSLuaFile() end
NULL = { _valid = false }

local now = 100
function CurTime() return now end
function IsValid(v) return type(v) == "table" and v._valid ~= false end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function isfunction(v) return type(v) == "function" end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a } end
function Vector(x, y, z)
    local v = { x = x or 0, y = y or 0, z = z or 0 }
    function v:DistToSqr(o) local a, b, c = self.x - o.x, self.y - o.y, self.z - o.z return a * a + b * b + c * c end
    return v
end
function string.Trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
function string.Explode(sep, str) local out = {} for piece in tostring(str):gmatch("[^" .. sep .. "]+") do out[#out + 1] = piece end return out end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function table.HasValue(t, v) for _, x in pairs(t or {}) do if x == v then return true end end return false end
function table.Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
bit = { bor = function(a) return a end }
FCVAR_ARCHIVE = 1

local convars = {}
function CreateConVar(name, def)
    local cv = { value = def }
    function cv:GetInt() return math.floor(tonumber(self.value) or 0) end
    function cv:GetBool() return tostring(self.value) == "1" end
    convars[name] = cv
    return cv
end

local FS = {}
file = {
    IsDir = function() return true end, CreateDir = function() end,
    Write = function(p, s) FS[p] = s end, Read = function(p) return FS[p] end,
    Exists = function(p) return FS[p] ~= nil end,
}
-- Мини-JSON (числа/строки/таблицы) — хватает для круга сохранения цен.
local function enc(v)
    local t = type(v)
    if t == "number" or t == "boolean" then return tostring(v) end
    if t == "string" then return string.format("%q", v) end
    local parts = {}
    if #v > 0 then
        for _, i in ipairs(v) do parts[#parts + 1] = enc(i) end
        return "[" .. table.concat(parts, ",") .. "]"
    end
    for k, i in pairs(v) do parts[#parts + 1] = string.format("%q", tostring(k)) .. ":" .. enc(i) end
    return "{" .. table.concat(parts, ",") .. "}"
end
local function dec(s)
    local pos = 1
    local function value()
        while s:sub(pos, pos):match("%s") do pos = pos + 1 end
        local c = s:sub(pos, pos)
        if c == "{" then
            pos = pos + 1 local out = {}
            if s:sub(pos, pos) == "}" then pos = pos + 1 return out end
            while true do
                local k = value() pos = pos + 1
                out[k] = value()
                local sep = s:sub(pos, pos) pos = pos + 1
                if sep == "}" then break end
            end
            return out
        elseif c == '"' then
            local i = pos + 1 local out = {}
            while s:sub(i, i) ~= '"' do out[#out + 1] = s:sub(i, i) i = i + 1 end
            pos = i + 1
            return table.concat(out)
        else
            local a, b = s:find("[%-%d%.]+", pos)
            pos = b + 1
            return tonumber(s:sub(a, b))
        end
    end
    return value()
end
util = { AddNetworkString = function() end, TableToJSON = function(t) return enc(t) end,
         JSONToTable = function(s) return dec(s) end }

local sent = {}
net = { Receive = function(name, fn) net["_" .. name] = fn end, Start = function(n) sent[#sent + 1] = n end,
        Send = function() end, WriteEntity = function() end, WriteTable = function() end,
        WriteString = function() end, WriteBool = function() end, WriteUInt = function() end,
        WriteFloat = function() end, ReadString = function() return "" end }
hook = { Add = function() end, Run = function() end, Remove = function() end }
timer = { Create = function() end, Simple = function() end }
concommand = { Add = function() end }
list = { Set = function() end }
player = { GetAll = function() return {} end }
ents = { FindByClass = function() return {} end, FindInSphere = function() return {} end }
weapons = { GetStored = function(class) return class == "weapon_jackhammer_sd" and {} or nil end }

GRM = { Format = function(n) return tostring(n) .. " GRM" end }
local money = {}
GRM.Notify = function() end
GRM.HasMoney = function(ply, n) return (money[ply] or 0) >= n end
GRM.TakeMoney = function(ply, n) money[ply] = (money[ply] or 0) - n end
GRM.GiveMoney = function(ply, n) money[ply] = (money[ply] or 0) + n end

-- Инвентарь-заглушка.
GRM.Inventory = { ItemDefs = {} }
local invs = {}
GRM.Inventory.GetPlayerInv = function(ply) return invs[ply] end
GRM.Inventory.RemoveFromSlot = function(ply, idx, count)
    local inv = invs[ply]
    if not (inv and inv.slots[idx]) then return false end
    local slot = inv.slots[idx]
    if (slot.count or 1) <= count then inv.slots[idx] = nil else slot.count = slot.count - count end
    return true
end

assert(loadfile("lua/autorun/sh_grm_mining.lua"))()
local M = GRM.Mining

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

local function mkPlayer(name)
    local p = { _valid = true, weapons = {}, _pos = Vector(0, 0, 0) }
    function p:GetPos() return self._pos end
    function p:Nick() return name end
    function p:IsPlayer() return true end
    function p:IsAdmin() return true end
    function p:HasWeapon(c) return self.weapons[c] == true end
    function p:Give(c) self.weapons[c] = true return { _valid = true } end
    function p:StripWeapon(c) self.weapons[c] = nil end
    function p:SelectWeapon() end
    function p:ChatPrint() end
    money[p] = 10000
    invs[p] = { slots = {} }
    return p
end
local buyer = { _valid = true, _pos = Vector(0, 0, 0), GetPos = function(self) return self._pos end,
                EntIndex = function() return 5 end }

print("\n=== 1. ЦЕНЫ ===")
ok(GRM.OrePrices.copper == 50 and GRM.OrePrices.platinum == 150, "дефолтные цены загрузились")
local okSet, msg = M.SetPrice("gold", 250)
ok(okSet and GRM.OrePrices.gold == 250, "цена меняется", msg)
ok(select(1, M.SetPrice("unobtainium", 10)) == false, "неизвестная руда отклоняется")
ok(select(1, M.SetPrice("gold", -5)) == false, "отрицательная цена отклоняется")
-- Перечитываем как после рестарта карты.
GRM.OrePrices = {}
M.LoadPrices()
ok(GRM.OrePrices.gold == 250, "цена пережила перезагрузку (файл, а не только память)")

print("\n=== 2. ИНСТРУМЕНТ ===")
local miner = mkPlayer("Miner")
ok(M.ToolClass() == "weapon_jackhammer_sd", "класс бура берётся из зарегистрированных на сервере")
local okGive, giveMsg = M.GiveTool(miner, buyer)
ok(okGive and miner.weapons.weapon_jackhammer_sd == true, "бур выдан", giveMsg)
ok(select(1, M.GiveTool(miner, buyer)) == false, "второй бур на руки не выдаётся")
miner._pos = Vector(5000, 0, 0)
ok(select(1, M.GiveTool(mkPlayer("Far"), { _valid = true, _pos = Vector(9000, 0, 0), GetPos = function(self) return self._pos end })) == false,
    "издалека инструмент не получить")
miner._pos = Vector(0, 0, 0)
local okRet, retMsg = M.ReturnTool(miner)
ok(okRet and miner.weapons.weapon_jackhammer_sd == nil, "бур сдан", retMsg)
ok(select(1, M.ReturnTool(miner)) == false, "сдавать нечего — честный отказ")

print("\n=== 3. ЗАЛОГ ===")
convars["grm_mining_deposit"].value = "500"
local rich = mkPlayer("Rich")
money[rich] = 400
ok(select(1, M.GiveTool(rich, buyer)) == false, "без денег на залог бур не дают")
money[rich] = 1000
M.GiveTool(rich, buyer)
ok(money[rich] == 500, "залог списан")
M.ReturnTool(rich)
ok(money[rich] == 1000, "залог возвращён при сдаче")
convars["grm_mining_deposit"].value = "0"

print("\n=== 4. ПРОДАЖА ===")
local seller = mkPlayer("Seller")
money[seller] = 0
invs[seller].slots = {
    [1] = { id = "ore_copper", count = 10 },
    [2] = { id = "ore_gold", count = 4 },
    [3] = { id = "ore_platinum", count = 2 },
    [4] = { id = "item_bread", count = 1 },
}
local counts = M.CountOres(seller)
ok(counts.copper == 10 and counts.gold == 4 and counts.platinum == 2, "руда считается по инвентарю")
local okSell, sellMsg = M.Sell(seller, "copper", buyer)
ok(okSell and money[seller] == 500, "продажа одного типа считается по серверной цене", sellMsg)
ok(invs[seller].slots[1] == nil and invs[seller].slots[2] ~= nil, "проданы только медные слоты")
local okAll, allMsg = M.Sell(seller, "all", buyer)
ok(okAll and money[seller] == 500 + 4 * 250 + 2 * 150, "«продать всё» продаёт остальную руду", allMsg)
ok(invs[seller].slots[4] ~= nil, "не-руда в инвентаре не тронута")
ok(select(1, M.Sell(seller, "copper", buyer)) == false, "продавать нечего — отказ")

seller._pos = Vector(4000, 0, 0)
invs[seller].slots[5] = { id = "ore_gold", count = 1 }
ok(select(1, M.Sell(seller, "gold", buyer)) == false, "с другого конца карты продать нельзя")
seller._pos = Vector(0, 0, 0)

M.SetPrice("gold", 0)
ok(select(1, M.Sell(seller, "gold", buyer)) == false, "руда без цены не продаётся")

print("\n=== 5. ЗАЩИТА ОТ ДУБЛЕЙ ===")
local sellHandlers = 0
for _, path in ipairs({ "lua/autorun/sh_grm_mining.lua", "lua/autorun/sh_grm_ore_admin.lua",
                        "lua/entities/grm_ore_buyer/init.lua" }) do
    local f = assert(io.open(path, "rb")) local src = f:read("*a") f:close()
    for _ in src:gmatch('net%.Receive%("grm_ore_sell"') do sellHandlers = sellHandlers + 1 end
end
ok(sellHandlers == 1, "обработчик продажи ровно один (было два и они затирали друг друга)", sellHandlers)

print(("\nMINING RUNTIME: %d/%d, провалов: %d"):format(total - fails, total, fails))
if fails > 0 then os.exit(1) end
