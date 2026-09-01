-- sim_prop_protect.lua — функциональная проверка проп-протектора (находка 179):
--   • IsManaged: prop_physics + ЛЮБАЯ серверная GRM-сущность (MarkServerEntity);
--   • обычный игрок НЕ может физганом/гравиганом/тулом трогать серверное;
--   • суперадмин — может;
--   • обычный чужой проп (prop_physics) — по-прежнему защищён (не сломали).
local pass, fail = 0, 0
local function ok(v, n) if v then pass = pass + 1 print("  ok  " .. n) else fail = fail + 1 print("  FAIL " .. n) end end

SERVER, CLIENT = true, false
function AddCSLuaFile() end
function isstring(v) return type(v) == "string" end
function istable(v) return type(v) == "table" end
function isfunction(v) return type(v) == "function" end
function IsValid(v) return v ~= nil and (type(v) == "table" and v.__valid ~= false or type(v) == "userdata") end
function print(...) local a = {} for i = 1, select("#", ...) do a[i] = tostring(select(i, ...)) end io.write(table.concat(a, " "), "\n") end
function Color(r, g, b) return { r = r or 0, g = g or 0, b = b or 0 } end
function CurTime() return 1000 end

local H = { hooks = {} }
hook = { Add = function(n, id, fn) H.hooks[n] = H.hooks[n] or {} H.hooks[n][id] = fn end, Run = function() end }
util = { AddNetworkString = function() end }
net = { Start = function() end, WriteTable = function() end, Send = function() end, Receive = function() end, ReadTable = function() return {} end }
file = { IsDir = function() return true end, CreateDir = function() end, Exists = function() return false end, Read = function() return nil end, Write = function() end, Find = function() return {} end }
game = { GetMap = function() return "rp_test" end }
concommand = { Add = function() end }

-- ── мок энтити ──
local EMT = {}
EMT.__index = function(t, k)
  if k == "GetClass" then return function(s) return s.__cls end
  elseif k == "GetNWString" then return function(s, key, d) local v = s.nw and s.nw[key]; if v == nil then return d or "" end return v end
  elseif k == "SetNWString" then return function(s, key, v) s.nw = s.nw or {} s.nw[key] = v end
  elseif k == "GetPhysicsObject" then return function() return { __valid = true, SetMaterial = function() end, SetFriction = function() end, SetDamping = function() end } end
  elseif k == "IsPlayer" then return function() return false end
  end
  return nil
end
local function mkEnt(cls)
  return setmetatable({ __cls = cls, __valid = true, nw = {} }, EMT)
end

-- ── мок игрока ──
local PMT = {}
PMT.__index = function(t, k)
  if k == "IsSuperAdmin" then return function(s) return s.super == true end
  elseif k == "IsPlayer" then return function() return true end
  elseif k == "SteamID64" then return function(s) return s.sid64 end
  elseif k == "SteamID" then return function() return "STEAM_0:1:1" end
  end
  return nil
end
local function mkPly(super)
  return setmetatable({ __valid = true, super = super == true, sid64 = super and "76561198000000001" or "76561198000000002" }, PMT)
end

GRM = {
  Identity = { CharacterKey = function(ply) return ply.sid64 .. ":char1" end },
  Notify = function() end,
}

-- ══════════════ ЗАГРУЗКА ══════════════
-- Ядро GRM (sh_00_grm_ui + sh_01_grm_core) — как на сервере, до модулей.
dofile("tools/luatest/lib_grm_core.lua")()
dofile("lua/autorun/sh_grm_prop_protect.lua")
local PP = GRM.PropProtect
ok(PP ~= nil and PP.IsManaged ~= nil and PP.CanInteract ~= nil, "проп-протектор загружен")

-- ══════════════ 1. IsManaged ══════════════
local prop = mkEnt("prop_physics")
ok(PP.IsManaged(prop) == true, "prop_physics: под защитой (как раньше)")
local vault = mkEnt("grm_bank_vault")
ok(PP.IsManaged(vault) == false, "grm_bank_vault БЕЗ метки: не управляется (прежнее поведение)")
PP.MarkServerEntity(vault)
ok(vault:GetNWString("GRM_EntityOwnerType", "") == "server", "MarkServerEntity пометил сущность")
ok(PP.IsManaged(vault) == true, "grm_bank_vault с меткой server: ПОД ЗАЩИТОЙ (находка 179)")
local press = mkEnt("grm_money_press")
PP.MarkServerEntity(press)
ok(PP.IsManaged(press) == true, "grm_money_press с меткой server: под защитой")
local alarm = mkEnt("grm_alarm_hub")
PP.MarkServerEntity(alarm)
ok(PP.IsManaged(alarm) == true, "grm_alarm_hub с меткой server: под защитой")

-- ══════════════ 2. CanInteract ══════════════
local player = mkPly(false)
local admin = mkPly(true)
ok(PP.CanInteract(player, vault, "physgun") == false, "игрок: НЕ может физганить серверное (находка 179)")
ok(PP.CanInteract(player, vault, "tool") == false, "игрок: НЕ может тулить серверное")
ok(PP.CanInteract(player, vault, "remove") == false, "игрок: НЕ может удалять серверное")
ok(PP.CanInteract(admin, vault, "physgun") == true, "суперадмин: может физганить серверное")
ok(PP.CanInteract(admin, vault, "tool") == true, "суперадмин: может тулить серверное")
ok(PP.CanInteract(admin, vault, "remove") == true, "суперадмин: может удалять серверное")

-- ══════════════ 3. Хуки ══════════════
local physHook = H.hooks["PhysgunPickup"]["GRM_PropProtect_Physgun"]
local gravHook = H.hooks["GravgunPickup"]["GRM_PropProtect_Gravgun"]
local gravPunt = H.hooks["GravgunPunt"]["GRM_PropProtect_GravgunPunt"]
ok(physHook ~= nil, "хук PhysgunPickup зарегистрирован")
ok(gravHook ~= nil, "хук GravgunPickup зарегистрирован (находка 179)")
ok(gravPunt ~= nil, "хук GravgunPunt зарегистрирован (находка 179)")

ok(physHook(player, vault) == false, "PhysgunPickup: игроку запрещено (server)")
ok(physHook(admin, vault) == true, "PhysgunPickup: суперадмину разрешено (server)")
ok(physHook(player, prop) == false, "PhysgunPickup: чужой проп игроку запрещено (прежнее)")
ok(gravHook(player, vault) == false, "GravgunPickup: игроку запрещено (server)")
ok(gravHook(admin, vault) == true, "GravgunPickup: суперадмину разрешено (server)")
ok(gravPunt(player, vault) == false, "GravgunPunt: игроку запрещено (server)")
ok(gravPunt(admin, vault) == nil or gravPunt(admin, vault) == true, "GravgunPunt: суперадмин не блокируется")

print(string.format("sim_prop_protect: %d ok, %d fail", pass, fail))
if fail > 0 then os.exit(1) end
