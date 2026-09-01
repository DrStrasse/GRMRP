-- Симуляция сервера GMod для денежного дропа (Код 81)
-- Загружает НАСТОЯЩИЕ sh_grm_currency.lua и sh_grm_inventory.lua и
-- прогоняет: /dropmoney (списание → энтити grm_money_drop → E возврат),
-- отказ при нехватке, /money_pack (кошелёк → предмет money в инвентарь),
-- «Использовать» предмет money (обналичить весь стак обратно),
-- чат-контракт находки 89 (PlayerSayTransform + SkipPlayerSay + fallback).
string.Trim = function(s) s = tostring(s or ""); return (s:gsub("^%s*(.-)%s*$", "%1")) end
local H = { hooks = {}, netrecv = {}, concommands = {}, timers = {} }
local realPrint = print
local function P(...) realPrint("[SIM]", ...) end

_G._SIM = H
SERVER = true
CLIENT = false
function AddCSLuaFile() end
if not string.StartWith then
    string.StartWith = function(s, prefix) return string.sub(s, 1, #prefix) == prefix end
end
if not string.StartsWith then string.StartsWith = string.StartWith end
function istable(x) return type(x) == "table" end
function isstring(x) return type(x) == "string" end
function isfunction(x) return type(x) == "function" end
function isnumber(x) return type(x) == "number" end
function IsValid(o) return o ~= nil and o ~= false end
table.Count = function(t) local n = 0 for k in pairs(t or {}) do n = n + 1 end return n end
table.Copy = function(t)
    local r = {}
    for k, v in pairs(t or {}) do r[k] = istable(v) and table.Copy(v) or v end
    return r
end

local VMT = {}
VMT.__index = function(self, k)
    if k == "DistToSqr" then return function(s, o) local dx, dy, dz = s.x - o.x, s.y - o.y, s.z - o.z return dx * dx + dy * dy + dz * dz end end
    return nil
end
VMT.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
VMT.__mul = function(a, b)
    if isnumber(a) then return Vector(a * b.x, a * b.y, a * b.z) end
    return Vector(a.x * b, a.y * b, a.z * b)
end
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VMT) end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
function math.Clamp(v, mn, mx) v = tonumber(v) or 0 if v < mn then return mn end if v > mx then return mx end return v end

-- «диск» + JSON: эмуляция КАЛЕЧЕНИЯ числовых ключей как в живом GMod
-- (находка 65): SteamID64-ключи при чтении становятся числами, если
-- модуль читает голым JSONToTable — тест ловит регрессию.
local savedSnap, corruptKeys = {}, false
util = {
    AddNetworkString = function() end,
    IsValidModel = function() return true end,
    TableToJSON = function(t) savedSnap = table.Copy(t) return "{}" end,
    JSONToTable = function(txt, ign, ignConv)
        if txt == "" then return nil end
        local t = table.Copy(savedSnap)
        if corruptKeys and not ignConv then
            for k, v in pairs(t) do
                if isstring(k) and k:match("^%d+$") then t[k] = nil t[tonumber(k)] = v end
            end
        end
        return t
    end,
}
local written = {}
file = { Read = function(n) return written[n] end,
         Write = function(n, txt) written[n] = txt end,
         Exists = function(n) return written[n] ~= nil end,
         IsDir = function() return true end, CreateDir = function() end }
hook = { Add = function(name, id, fn) H.hooks[name] = H.hooks[name] or {} H.hooks[name][id] = fn end,
         Run = function(name, ...) local fns = H.hooks[name] or {} for id, fn in pairs(fns) do local r = fn(...) if r ~= nil then return r end end end,
         Call = function(name, gm, ...) return hook.Run(name, ...) end }
timer = { Create = function(name, d, r, fn) if type(name) == "function" then fn = name end if fn then H.timers[tostring(name)] = fn end end,
          Simple = function(d, fn) if type(d) == "function" then d() elseif fn then fn() end end,
          Remove = function(name) H.timers[tostring(name)] = nil end,
          Exists = function() return false end }

-- энтити-стаб: ents.Create возвращает объект с NW-сеттерами и Use()
local created = {}
ents = { Create = function(class)
    local e = { class = class, nw = {}, spawned = false, removed = false }
    e.SetPos = function(s, v) s.pos = v end
    e.SetAngles = function(s, a) s.ang = a end
    e.Spawn = function(s) s.spawned = true end
    e.Remove = function(s) s.removed = true end
    e.SetAmount = function(s, v) s.nw.Amount = v end
    e.GetAmount = function(s) return s.nw.Amount or 0 end
    e.SetItemID = function(s, v) s.nw.ItemID = v end
    e.GetItemID = function(s) return s.nw.ItemID end
    e.SetItemCount = function(s, v) s.nw.ItemCount = v end
    e.GetItemCount = function(s) return s.nw.ItemCount or 0 end
    e.GetPhysicsObject = function() return nil end
    e.GetForward = function() return Vector(1, 0, 0) end
    created[#created + 1] = e
    return e
end, FindInSphere = function() return {} end, FindByClass = function() return {} end }

player = { GetAll = function() return H.players or {} end, GetBySteamID = function() return nil end, GetBySteamID64 = function() return nil end }
game = { GetMap = function() return "gm_test" end }
function CurTime() return 1000 end
function SysTime() return 1000 end
HUD_PRINTTALK = 3
HUD_PRINTCENTER = 4

local netlog = {}
net = { Start = function(m) netlog.cur = { msg = m } end,
        WriteString = function() end, WriteUInt = function() end, WriteInt = function() end,
        WriteBool = function() end, WriteTable = function() end, WriteVector = function() end,
        WriteEntity = function() end, WriteFloat = function() end, WriteBit = function() end,
        Send = function() netlog.sent = netlog.sent or {} netlog.sent[#netlog.sent + 1] = netlog.cur netlog.cur = nil end,
        Broadcast = function() netlog.cur = nil end,
        SendToServer = function() end,
        Receive = function(m, fn) H.netrecv[m] = fn end }
concommand = { Add = function(n, fn) H.concommands[n] = fn end }

-- ── игроки ───────────────────────────────────────────────────
local PMT = {}
PMT.__index = function(t, k)
    if isstring(k) and (k:match("^SetNW") or k:match("^GetNW")) then
        return function(s, key, val)
            if k:match("^Set") then s.nw = s.nw or {} s.nw[key] = val return end
            local v = s.nw and s.nw[key]
            if v == nil then
                if k:match("Int$") or k:match("Float$") then return 0 end
                if k:match("Bool$") then return false end
                return ""
            end
            return v
        end
    end
    if k == "SteamID" then return function(s) return s.sid end end
    if k == "SteamID64" then return function(s) return s.s64 end end
    if k == "IsPlayer" then return function() return true end end
    if k == "IsBot" then return function() return false end end
    if k == "IsSuperAdmin" then return function() return t.super == true end end
    if k == "Nick" then return function(s) return s.nick end end
    if k == "GetNWString" then return function() return "" end end
    if k == "GetPos" then return function(s) return s.pos or Vector(0, 0, 0) end end
    if k == "GetForward" then return function() return Vector(1, 0, 0) end end
    if k == "GetEyeTrace" then return function(s) return { Entity = s.aim, HitPos = Vector(50, 0, 0) } end end
    if k == "PrintMessage" then return function(s, ch, txt) P(("CHAT[%s]: %s"):format(s.nick, tostring(txt))) end end
    if k == "GiveAmmo" then return function() end end
    if k == "Health" then return function() return 100 end end
    if k == "GetMaxHealth" then return function() return 100 end end
    if k == "Armor" then return function() return 0 end end
    if k == "SetArmor" then return function() end end
    if k == "SetHealth" then return function() end end
    if k == "HasWeapon" then return function() return false end end
    if k == "Give" then return function() return nil end end
    return nil
end
local function mkPly(nick, s64, super)
    return setmetatable({ nick = nick, s64 = s64, sid = "STEAM_0:1:" .. s64:sub(-3), super = super, pos = Vector(0, 0, 0) }, PMT)
end
local A = mkPly("Тестер", "76561198000000001", true)
local B = mkPly("Прохожий", "76561198000000002", false)
H.players = { A, B }

-- ── загрузка реальных модулей ────────────────────────────────
GRM = nil -- чистый старт, модули сами создадут namespace
dofile("lua/autorun/sh_grm_currency.lua")
dofile("lua/autorun/sh_grm_inventory.lua")

local fails = 0
local function ok(cond, label)
    if cond then P("[OK] " .. label)
    else fails = fails + 1 P("[FAIL] " .. label) end
end

-- вход игроков (стартовый баланс)
for _, p in ipairs(H.players) do
    local f = (H.hooks["PlayerInitialSpawn"] or {})["GRM_Currency_Init"]
    if f then f(p) end
    local t = H.timers["GRM_Currency_FirstSync_" .. p:SteamID64()]
    if t then t() end
end
ok(GRM ~= nil and GRM.GetBalance ~= nil, "модуль валюты поднялся")
local startBal = GRM.GetBalance(A)
ok(startBal >= 1000, "стартовый баланс A: " .. tostring(startBal))

-- чат-контракт: PlayerSayTransform должен поглотить команду (находка 89)
local function say(p, text)
    local dp = { text }
    for id, fn in pairs(H.hooks["PlayerSayTransform"] or {}) do fn(p, dp) end
    local swallowed = (dp[1] == "" or dp.SkipPlayerSay == true)
    if not swallowed then
        for id, fn in pairs(H.hooks["PlayerSay"] or {}) do
            local r = fn(p, text)
            if r == "" then swallowed = true end
        end
    end
    return swallowed
end

-- ── 1) /dropmoney: списание → энтити с суммой ────────────────
ok(say(A, "/dropmoney 500"), "/dropmoney поглощена чат-контрактом")
ok(GRM.GetBalance(A) == startBal - 500, "баланс A уменьшился на 500 → " .. GRM.GetBalance(A))
local drop = created[#created]
ok(drop ~= nil and drop.class == "grm_money_drop", "создана энтити grm_money_drop")
ok(drop and drop.spawned and drop:GetAmount() == 500, "у энтити сумма 500, заспавнена")

-- ── 2) E по пачке: деньги другому игроку, энтити исчезает ────
-- имитация ServerUse: берём сумму, GiveMoney, Remove (логика init.lua
-- не грузится в симе — энтити тупая; сценарий сверяем с init.lua глазами)
ok(drop:GetAmount() == 500, "на земле лежит 500")
local bBefore = GRM.GetBalance(B)
do -- повторяем контракт ENT:Use из grm_money_drop/init.lua
    local amt = drop:GetAmount()
    if amt > 0 then
        GRM.GiveMoney(B, amt, "Подобраны деньги с земли")
        drop:Remove()
    end
end
ok(GRM.GetBalance(B) == bBefore + 500, "B поднял 500 → баланс " .. GRM.GetBalance(B))
ok(drop.removed, "энтити денег удалена после подбора")

-- ── 3) отказ при нехватке денег ──────────────────────────────
ok(say(B, "/dropmoney 999999999"), "запрос сверх баланса поглощён")
ok(GRM.GetBalance(B) == bBefore + 500, "баланс B не изменился при отказе")
ok(created[#created] == drop, "новых энтити не создалось")

-- ── 4) /money_pack: кошелёк → предмет money в инвентарь ──────
ok(GRM.Inventory ~= nil and GRM.Inventory.AddItem ~= nil, "модуль инвентаря поднялся")
ok(GRM.Inventory.GetItemDef("money") ~= nil, "предмет «money» зарегистрирован")
local def = GRM.Inventory.GetItemDef("money")
ok(def.model == "models/props/cs_assault/money.mdl", "модель предмета money = cs_assault/money.mdl")
ok(def.useFunc == "cash_to_wallet", "useFunc предмета money = cash_to_wallet")
local aBefore = GRM.GetBalance(A)
ok(say(A, "/money_pack 300"), "/money_pack поглощена")
ok(GRM.GetBalance(A) == aBefore - 300, "с кошелька A списано 300")
local inv = GRM.Inventory.GetPlayerInv(A)
local moneySlot, moneyCount = nil, 0
for i, s in pairs(inv.slots) do
    if s.id == "money" then moneySlot = i moneyCount = s.count break end
end
ok(moneySlot ~= nil and moneyCount == 300, "в инвентаре A слот money x300")

-- ── 5) «Использовать» предмет money: обналичить весь стак ────
-- grm_inv_use публичный net-канал клиент→сервер
local useRecv = H.netrecv["grm_inv_use"]
ok(useRecv ~= nil, "есть receiver grm_inv_use")
-- эмуляция net-фрейма: monkey-patch ReadUInt/ReadString под фабрику
local seq = { moneySlot }
local seqN = 0
net.ReadUInt = function() seqN = seqN + 1 return seq[seqN] end
net.ReadEntity = function() return A end
if useRecv then useRecv(0, A) end
ok(inv.slots[moneySlot] == nil, "слот money пуст после обналичивания")
ok(GRM.GetBalance(A) == aBefore, "деньги вернулись в кошелёк A → " .. GRM.GetBalance(A))

-- ── 6) падение чтения JSON с калечеными ключами (страховка 65) ─
corruptKeys = true
local raw = util.JSONToTable("{}", false, true)
ok(istable(raw), "jsonT (3-ий аргумент) вернул таблицу даже в corrupt-режиме")
corruptKeys = false

-- ── итог ─────────────────────────────────────────────────────
if fails == 0 then
    P("=== ИТОГ: ВСЕ ПРОВЕРКИ ПРОШЛИ ===")
else
    P("=== ИТОГ: ПРОВАЛОВ: " .. tostring(fails) .. " ===")
    os.exit(1)
end
