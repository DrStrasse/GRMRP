--[[--------------------------------------------------------------------

    GRM Encumbrance — server

    Фикс: дедупликация ammoID, учёт кастомных патронов (ArcCW/TFA)

----------------------------------------------------------------------]]

if CLIENT then return end

AddCSLuaFile("autorun/sh_grm_encumbrance_config.lua")
AddCSLuaFile("autorun/client/cl_grm_encumbrance.lua")
include("autorun/sh_grm_encumbrance_config.lua")

GRM = GRM or {}
GRM.Encumbrance = GRM.Encumbrance or {}
local E = GRM.Encumbrance
local C = E.Config
local NET_SYNC = "GRM_Weight_Sync"
util.AddNetworkString(NET_SYNC)

E.PlayerData = E.PlayerData or {}

local function steamID(ply) return IsValid(ply) and ply:SteamID64() or "" end

local function notify(ply, message)
    if GRM and isfunction(GRM.Notify) then GRM.Notify(ply, message, 255, 180, 70)
    elseif IsValid(ply) then ply:ChatPrint("[Вес] " .. message) end
end

function E.GetItemWeight(itemID, slot)
    if isstring(itemID) and string.StartWith(itemID, "weapon:") then
        local class = slot and slot.data and slot.data.class or string.sub(itemID, 8)
        return E.GetWeaponWeight(class)
    end
    local def = GRM and GRM.Inventory and GRM.Inventory.GetItemDef and GRM.Inventory.GetItemDef(itemID)
    if def and def.type == "ammo" and def.ammoType then
        return math.max(0, tonumber(C.AmmoWeights[def.ammoType]) or 0.008)
    end
    if def and tonumber(def.weight) then return math.max(0, tonumber(def.weight)) end
    return math.max(0, tonumber(C.ItemWeights[itemID]) or C.DefaultItemWeight)
end

function E.GetWeaponWeight(class)
    class = string.lower(tostring(class or ""))
    if class == "" then return 0 end
    if C.WeaponWeights[class] ~= nil then return math.max(0, C.WeaponWeights[class]) end
    for _, rule in ipairs(C.WeaponClassRules or {}) do
        if string.find(class, rule.pattern, 1, true) then
            return math.max(0, tonumber(rule.weight) or C.DefaultWeaponWeight)
        end
    end
    return math.max(0, C.DefaultWeaponWeight)
end

local function inventoryWeight(ply, breakdown)
    if not GRM or not GRM.Inventory or not GRM.Inventory.GetPlayerInv then return 0 end
    local inv = GRM.Inventory.GetPlayerInv(ply)
    if not inv or not inv.slots then return 0 end
    local total = 0
    for _, slot in pairs(inv.slots) do
        if slot and slot.id then
            local count = math.max(1, tonumber(slot.count) or 1)
            local value = E.GetItemWeight(slot.id, slot) * count
            total = total + value
            breakdown.inventory = breakdown.inventory + value
        end
    end
    return total
end

local function equippedWeaponWeight(ply, breakdown)
    local total = 0
    for _, wep in ipairs(ply:GetWeapons()) do
        if IsValid(wep) then
            local value = E.GetWeaponWeight(wep:GetClass())
            total = total + value
            breakdown.weapons = breakdown.weapons + value
        end
    end
    return total
end

local function liveAmmoWeight(ply, breakdown)
    -- Патроны НЕ учитываются в весе (баг: вес не сбрасывается)
    return 0
end

local BODY_FILE = "grm_body_mass.json"
local bodyMass = {}
local function loadBody()
    if not file.Exists(BODY_FILE, "DATA") then return end
    local ok, t = pcall(util.JSONToTable, file.Read(BODY_FILE, "DATA") or "", false, true)
    if ok and istable(t) then bodyMass = t end
end
local function saveBody()
    local ok, enc = pcall(util.TableToJSON, bodyMass, true)
    if ok and enc then file.Write(BODY_FILE, enc) end
end
loadBody()
local function bodyKey(ply)
    if GRM.Identity and GRM.Identity.CharacterKey then return GRM.Identity.CharacterKey(ply) end
    return IsValid(ply) and (ply:SteamID64() or "") or ""
end
function E.GetBodyMass(ply)
    local k = bodyKey(ply)
    if k == "" then return 0 end
    return math.max(0, tonumber(bodyMass[k]) or 0)
end
function E.SetBodyMass(ply, value)
    local k = bodyKey(ply)
    if k == "" then return end
    local cap = tonumber(C.BodyMassCap) or 12
    bodyMass[k] = math.Clamp(tonumber(value) or 0, 0, cap)
    if GRM.Perf and GRM.Perf.Coalesce then
        GRM.Perf.Coalesce("grm_body_mass_save", 4, saveBody)
    else
        saveBody()
    end
    E.Refresh(ply)
end
function E.AddBodyMassFromFood(ply, hungerRestore)
    if not IsValid(ply) then return end
    local h = math.max(0, tonumber(hungerRestore) or 0)
    local mn = tonumber(C.BodyMassMinAdd) or 0.2
    local mx = tonumber(C.BodyMassMaxAdd) or 0.5
    local add = mn + math.Clamp(h / 55, 0, 1) * (mx - mn)
    E.SetBodyMass(ply, E.GetBodyMass(ply) + add)
end

function E.CalculateWeight(ply)
    if not IsValid(ply) then return 0, { inventory = 0, weapons = 0, ammo = 0, body = 0 } end
    local breakdown = { inventory = 0, weapons = 0, ammo = 0, body = 0 }
    local total = inventoryWeight(ply, breakdown)
    total = total + equippedWeaponWeight(ply, breakdown)
    total = total + liveAmmoWeight(ply, breakdown)
    breakdown.body = E.GetBodyMass(ply)
    total = total + breakdown.body
    return math.Round(total * 100) / 100, breakdown
end

function E.GetCapacity(ply)
    local base = tonumber(C.Capacity) or 50
    local bonus = 0
    if IsValid(ply) and GRM.Customization and GRM.Customization.GetFunctionValue then
        bonus = GRM.Customization.GetFunctionValue(ply, "backpack", "backpackCapacity", "sum")
    end
    return base + math.Clamp(tonumber(bonus) or 0, 0, 100)
end
function E.GetHardCapacity(ply) return E.GetCapacity(ply) * (tonumber(C.HardMultiplier) or 1.25) end

function E.GetSpeedMultiplierForRatio(ratio)
    local soft = math.Clamp(tonumber(C.SoftStart) or 0.5, 0, 0.99)
    local hard = math.max(1.01, tonumber(C.HardMultiplier) or 1.25)
    if ratio <= soft then return 1 end
    if ratio <= 1 then return Lerp((ratio - soft) / (1 - soft), 1, C.SpeedAtCapacity or 0.72) end
    if ratio <= hard then return Lerp((ratio - 1) / (hard - 1), C.SpeedAtCapacity or 0.72, C.SpeedAtHardLimit or 0.35) end
    return C.MinimumSpeed or 0.25
end

function E.GetPlayerState(ply)
    local weight, breakdown = E.CalculateWeight(ply)
    local capacity = E.GetCapacity(ply)
    local hard = E.GetHardCapacity(ply)
    local ratio = weight / math.max(1, capacity)
    return {
        weight = weight, capacity = capacity, hard = hard, ratio = ratio,
        multiplier = E.GetSpeedMultiplierForRatio(ratio),
        overloaded = weight > capacity, blocked = weight >= hard,
        breakdown = breakdown,
    }
end

function E.CanCarry(ply, additionalWeight)
    local state = E.GetPlayerState(ply)
    return state.weight + math.max(0, additionalWeight or 0) <= state.hard, state
end

function E.GetStaminaDrainMultiplier(ply)
    local ratio = E.GetPlayerState(ply).ratio
    return 1 + math.max(0, ratio - (C.SoftStart or 0.5)) * 1.4
end

function E.GetStaminaRegenMultiplier(ply)
    local ratio = E.GetPlayerState(ply).ratio
    return math.Clamp(1 - math.max(0, ratio - 0.5) * 0.65, 0.25, 1)
end

local function applySpeed(ply, state)
    local movement = GRM and GRM.Movement and GRM.Movement.Config or {}
    local baseWalk = tonumber(movement.WalkSpeed) or 160
    local baseRun = tonumber(movement.RunSpeed) or 220
    local baseExhausted = tonumber(movement.ExhaustedSpeed) or 80
    local walk = math.max(45, math.floor(baseWalk * state.multiplier))
    local run = math.max(walk, math.floor(baseRun * state.multiplier))
    if state.overloaded then run = walk end
    if state.ratio >= (C.HardMultiplier or 1.25) then
        walk = math.max(35, math.floor(baseExhausted * state.multiplier))
        run = walk
    end
    ply:SetWalkSpeed(walk)
    ply:SetRunSpeed(run)
end

local function sync(ply, state)
    net.Start(NET_SYNC)
    net.WriteFloat(state.weight)
    net.WriteFloat(state.capacity)
    net.WriteFloat(state.hard)
    net.WriteFloat(state.multiplier)
    net.WriteBool(state.overloaded)
    net.WriteBool(state.blocked)
    net.WriteFloat(state.breakdown.inventory)
    net.WriteFloat(state.breakdown.weapons)
    net.WriteFloat(state.breakdown.ammo)
    net.WriteFloat(state.breakdown.body or 0)
    net.Send(ply)
end

local function updatePlayer(ply)
    if not IsValid(ply) then return end
    local state = E.GetPlayerState(ply)
    applySpeed(ply, state)
    local data = E.PlayerData[steamID(ply)] or {}
    local changed = not data.weight
        or math.abs((data.weight or 0) - state.weight) >= 0.05
        or data.overloaded ~= state.overloaded
        or data.blocked ~= state.blocked
    if changed or (CurTime() - (data.lastSync or 0)) >= (C.SyncInterval or 0.5) then
        sync(ply, state)
        data.weight = state.weight
        data.overloaded = state.overloaded
        data.blocked = state.blocked
        data.lastSync = CurTime()
        E.PlayerData[steamID(ply)] = data
        hook.Run("GRM_WeightUpdated", ply, state)
    end
end

function E.Refresh(ply)
    if not IsValid(ply) then return end
    timer.Simple(0, function() if IsValid(ply) then updatePlayer(ply) end end)
end

timer.Create("GRM_Weight_Update", math.max(0.1, C.UpdateInterval or 0.25), 0, function()
    local dt = math.max(0.1, C.UpdateInterval or 0.25)
    local burn = tonumber(C.BodyMassRunPerSec) or 0.035
    for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
        if IsValid(ply) and ply:Alive() and ply:IsSprinting() and ply:GetVelocity():Length2D() > 80 then
            local cur = E.GetBodyMass(ply)
            if cur > 0 then E.SetBodyMass(ply, cur - burn * dt) end
        end
        updatePlayer(ply)
    end
end)
hook.Add("ShutDown", "GRM_Weight_SaveBody", saveBody)

hook.Add("Move", "GRM_Weight_FinalSpeedCap", function(ply, mv)
    local state = E.GetPlayerState(ply)
    local movement = GRM and GRM.Movement and GRM.Movement.Config or {}
    local base = ply:KeyDown(IN_SPEED) and (tonumber(movement.RunSpeed) or 220) or (tonumber(movement.WalkSpeed) or 160)
    local cap = base * state.multiplier
    if state.overloaded then cap = (tonumber(movement.WalkSpeed) or 160) * state.multiplier end
    local velocity = mv:GetVelocity()
    local horizontal = velocity:Length2D()
    if horizontal > cap and cap > 0 then
        local ratio = cap / horizontal
        mv:SetVelocity(Vector(velocity.x * ratio, velocity.y * ratio, velocity.z))
    end
end)

-- INVENTORY INTEGRATION
local function installInventoryWrapper()
    if not GRM or not GRM.Inventory then return false end
    if isfunction(GRM.Inventory.AddItem) and GRM.Inventory.AddItem ~= E.AddItemWrapper then
        E.OriginalAddItem = GRM.Inventory.AddItem
        E.AddItemWrapper = function(ply, itemID, count)
            count = math.max(0, math.floor(tonumber(count) or 1))
            if count <= 0 then return 0 end
            local unitWeight = E.GetItemWeight(itemID)
            local allowed = count
            --[[ СОСТОЯНИЕ ВЕСА НУЖНО И В ОТКАЗЕ, ПОЭТОМУ ОБЪЯВЛЕНО ЗДЕСЬ.
                 Раньше `local state` жил внутри `if unitWeight > 0`, а
                 сообщение об отказе ниже читало его снаружи — то есть
                 глобальный nil. Вместо «Перегруз: 30.0 / 30.0 кг» игрок
                 получал Lua-ошибку и не понимал, почему не берётся
                 предмет. ]]
            local state
            if unitWeight > 0 then
                state = E.GetPlayerState(ply)
                allowed = math.Clamp(math.floor((state.hard - state.weight) / unitWeight), 0, count)
            end
            if allowed <= 0 then
                state = state or E.GetPlayerState(ply)
                if IsValid(ply) then notify(ply, string.format("Перегруз: %.1f / %.1f кг. Новый предмет поднять нельзя.", state.weight, state.hard)) end
                return count
            end
            local notAdded = E.OriginalAddItem(ply, itemID, allowed)
            notAdded = tonumber(notAdded) or 0
            E.Refresh(ply)
            return notAdded + (count - allowed)
        end
        GRM.Inventory.AddItem = E.AddItemWrapper
    end
    if isfunction(GRM.Inventory.RemoveItem) and GRM.Inventory.RemoveItem ~= E.RemoveItemWrapper then
        E.OriginalRemoveItem = GRM.Inventory.RemoveItem
        E.RemoveItemWrapper = function(ply, itemID, count)
            local result = E.OriginalRemoveItem(ply, itemID, count)
            E.Refresh(ply)
            return result
        end
        GRM.Inventory.RemoveItem = E.RemoveItemWrapper
    end
    if isfunction(GRM.Inventory.AddWeapon) and GRM.Inventory.AddWeapon ~= E.AddWeaponWrapper then
        E.OriginalAddWeapon = GRM.Inventory.AddWeapon
        E.AddWeaponWrapper = function(ply, weaponClass, clip1, clip2)
            local canCarry = E.CanCarry(ply, E.GetWeaponWeight(weaponClass))
            if not canCarry then
                if IsValid(ply) then notify(ply, "Слишком тяжело: оружие нельзя убрать в инвентарь.") end
                return false
            end
            local result = E.OriginalAddWeapon(ply, weaponClass, clip1, clip2)
            E.Refresh(ply)
            return result
        end
        GRM.Inventory.AddWeapon = E.AddWeaponWrapper
    end
    return isfunction(GRM.Inventory.AddItem)and GRM.Inventory.AddItem==E.AddItemWrapper and isfunction(GRM.Inventory.RemoveItem)and GRM.Inventory.RemoveItem==E.RemoveItemWrapper
end

timer.Create("GRM_Weight_InstallInventory",1,0,function()if installInventoryWrapper()then timer.Remove("GRM_Weight_InstallInventory")end end)
timer.Simple(0, installInventoryWrapper)

hook.Add("PlayerCanPickupWeapon", "GRM_Weight_WeaponPickup", function(ply, weapon)
    if not IsValid(weapon) then return end
    local canCarry = E.CanCarry(ply, E.GetWeaponWeight(weapon:GetClass()))
    if not canCarry then notify(ply, "Слишком тяжело: нельзя поднять оружие."); return false end
end)

hook.Add("PlayerInitialSpawn", "GRM_Weight_Initial", function(ply)
    timer.Simple(3, function() updatePlayer(ply) end)
end)
hook.Add("PlayerDisconnected", "GRM_Weight_Cleanup", function(ply) E.PlayerData[steamID(ply)] = nil end)

concommand.Add("grm_weight_debug", function(ply)
    if not IsValid(ply) then return end
    local state = E.GetPlayerState(ply)
    ply:ChatPrint(string.format("[Вес] Всего: %.2f / %.2f кг (жёсткий: %.2f)", state.weight, state.capacity, state.hard))
    ply:ChatPrint(string.format("[Вес] Инвентарь: %.2f | Оружие: %.2f | Скорость: %d%%", state.breakdown.inventory, state.breakdown.weapons, state.multiplier * 100))
end)

print("[GRM] Encumbrance server loaded")
