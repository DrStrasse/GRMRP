--[[
    GRM Food System - Серверная логика + программная регистрация сущностей
    Папки lua/entities не используются.
]]

if not SERVER then return end

AddCSLuaFile("autorun/sh_grm_food_config.lua")
AddCSLuaFile("autorun/client/cl_grm_food_hud.lua")
AddCSLuaFile("autorun/client/cl_grm_vending_gui.lua")

GRM = GRM or {}
GRM.Food = GRM.Food or {}

if not GRM.Food.Config then
    include("autorun/sh_grm_food_config.lua")
end

local function cfg()
    return GRM.Food.Config or {}
end

-- ============================================================
-- СЕТЕВЫЕ СООБЩЕНИЯ
-- ============================================================

util.AddNetworkString("GRM_Food_Sync")
util.AddNetworkString("GRM_Vending_Open")
util.AddNetworkString("GRM_Vending_Buy")

-- ============================================================
-- РЕГИСТРАЦИЯ СУЩНОСТЕЙ
-- ============================================================

local function getFoodData(itemID)
    local config = cfg()
    return config.FoodItems and config.FoodItems[itemID] or nil
end

-- 1. Сущность еды
local FOOD = {}

FOOD.Type = "anim"
FOOD.Base = "base_gmodentity"
FOOD.PrintName = "Еда"
FOOD.Category = "GRM Food"
FOOD.Spawnable = true       -- видно в spawnmenu для тестов
FOOD.AdminSpawnable = true
FOOD.AdminOnly = true       -- через list.Set на клиенте будет admin-only

function FOOD:SetupDataTables()
    self:NetworkVar("String", 0, "ItemID")
end

function FOOD:ResolveItemID()
    local itemID = self.GRMFoodItemID

    if (not itemID or itemID == "") and self.GetItemID then
        itemID = self:GetItemID()
    end

    if (not itemID or itemID == "") and self.GetNWString then
        itemID = self:GetNWString("ItemID", "")
    end

    if not itemID or itemID == "" then
        itemID = "grm_food_apple"
    end

    return itemID
end

function FOOD:ApplyFoodModel()
    local itemID = self:ResolveItemID()
    local data = getFoodData(itemID)
    local model = (data and data.model) or "models/props/cs_office/coffee_mug.mdl"

    self:SetModel(model)

    return model
end

function FOOD:SetFoodItemID(itemID)
    itemID = tostring(itemID or "")

    if itemID == "" then
        itemID = "grm_food_apple"
    end

    self.GRMFoodItemID = itemID

    -- NetworkVar создаёт SetItemID/GetItemID, а NWString оставлен как запасной вариант.
    -- Главное: модель меняется сразу после смены itemID, а не остаётся от яблока/апельсина.
    if self.SetItemID then
        self:SetItemID(itemID)
    end

    if self.SetNWString then
        self:SetNWString("ItemID", itemID)
    end

    self:ApplyFoodModel()
end

function FOOD:Initialize()
    local itemID = self:ResolveItemID()
    self.GRMFoodItemID = itemID

    if self.SetItemID then
        self:SetItemID(itemID)
    end

    if self.SetNWString then
        self:SetNWString("ItemID", itemID)
    end

    self:ApplyFoodModel()
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
    end
end

function FOOD:Use(activator)
    if not IsValid(activator) or not activator:IsPlayer() then return end

    local itemID = self:ResolveItemID()
    local data = getFoodData(itemID)

    if not data then
        activator:ChatPrint("[Еда] Ошибка: неизвестный тип еды.")
        return
    end

    local hungerRestore = tonumber(data.hungerRestore) or 0
    local thirstRestore = tonumber(data.thirstRestore) or 0

    if GRM.Food.RestoreHunger then
        GRM.Food.RestoreHunger(activator, hungerRestore)
    end
    if GRM.Food.RestoreThirst then
        GRM.Food.RestoreThirst(activator, thirstRestore)
    end

    local healthRestore = tonumber(data.healthRestore) or 0
    if healthRestore > 0 then
        local maxHealth = activator.GetMaxHealth and activator:GetMaxHealth() or 100
        local newHealth = activator:Health() + healthRestore

        if cfg().RespectMaxHealth then
            newHealth = math.min(newHealth, maxHealth)
        end

        activator:SetHealth(newHealth)
    end

    activator:EmitSound("npc/barnacle/barnacle_gulp1.wav", 70, 100)
    activator:ChatPrint("[Еда] Вы использовали: " .. (data.name or itemID)
        .. " (+" .. hungerRestore .. " сытости, +" .. thirstRestore .. " жажды).")

    self:Remove()
end

scripted_ents.Register(FOOD, "grm_food_item")

-- 2. Сущность торгового автомата
local VENDING = {}

VENDING.Type = "anim"
VENDING.Base = "base_gmodentity"
VENDING.PrintName = "Торговый автомат"
VENDING.Category = "GRM Food"
VENDING.Spawnable = true
VENDING.AdminSpawnable = true

function VENDING:Initialize()
    self:SetModel(cfg().VendingMachineModel or "models/props_interiors/VendingMachineSoda01a.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
        phys:EnableMotion(false)
    end
end

function VENDING:Use(activator)
    if not IsValid(activator) or not activator:IsPlayer() then return end

    local dist = cfg().VendingUseDistance or 150
    if activator:GetPos():DistToSqr(self:GetPos()) > dist * dist then
        activator:ChatPrint("[Автомат] Подойдите ближе.")
        return
    end

    net.Start("GRM_Vending_Open")
        net.WriteEntity(self)
    net.Send(activator)
end

scripted_ents.Register(VENDING, "grm_vending_machine")


-- ============================================================
-- ПЕРМАНЕНТНЫЕ АВТОМАТЫ НА КАРТЕ
-- ============================================================

local VENDING_SAVE_DIR = "grm_food"
local VENDING_SAVE_PREFIX = "vending_"

local function vendingSaveFile()
    local map = string.lower(game.GetMap() or "unknown")
    return VENDING_SAVE_DIR .. "/" .. VENDING_SAVE_PREFIX .. map .. ".json"
end

local function ensureVendingSaveDir()
    if not file.Exists(VENDING_SAVE_DIR, "DATA") then
        file.CreateDir(VENDING_SAVE_DIR)
    end
end

local function canManageVending(ply)
    -- Серверная консоль разрешена. Игрокам — только superadmin.
    if not IsValid(ply) then return true end
    return ply:IsPlayer() and ply:IsSuperAdmin()
end

local function reply(ply, msg)
    if IsValid(ply) then
        ply:ChatPrint(msg)
    else
        print(msg)
    end
end

local function vecToTable(v)
    return { x = v.x, y = v.y, z = v.z }
end

local function angToTable(a)
    return { p = a.p, y = a.y, r = a.r }
end

local function tableToVec(t)
    return Vector(tonumber(t and t.x) or 0, tonumber(t and t.y) or 0, tonumber(t and t.z) or 0)
end

local function tableToAng(t)
    return Angle(tonumber(t and t.p) or 0, tonumber(t and t.y) or 0, tonumber(t and t.r) or 0)
end

local function createPermanentVending(pos, ang)
    local ent = ents.Create("grm_vending_machine")
    if not IsValid(ent) then return nil end

    ent.GRMFoodPermanent = true
    ent:SetPos(pos)
    ent:SetAngles(ang)
    ent:Spawn()
    ent:Activate()

    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(false)
    end

    if GRM.PropProtect and GRM.PropProtect.MarkServerEntity then
        GRM.PropProtect.MarkServerEntity(ent)
    end

    return ent
end

local function removeVendingMachines(replaceAll)
    for _, ent in ipairs(ents.FindByClass("grm_vending_machine")) do
        if IsValid(ent) and (replaceAll or ent.GRMFoodPermanent) then
            ent:Remove()
        end
    end
end

function GRM.Food.SaveVendingMachines(ply)
    if not canManageVending(ply) then
        reply(ply, "[GRM Food] Только superadmin может сохранять автоматы.")
        return false
    end

    ensureVendingSaveDir()

    --[[ БИЗНЕС-ДАННЫЕ СОХРАНЯЮТСЯ ВМЕСТЕ С ПОЗИЦИЕЙ (находка 27.08).

         Раньше здесь писались только pos/ang, и файл ПЕРЕЗАПИСЫВАЛСЯ
         целиком. Владелец и накопленная касса, которые дописывал модуль
         бизнеса, стирались при каждом сохранении — после рестарта выручка
         обнулялась, а автомат становился ничьим. ]]
    local saved = {}
    for _, ent in ipairs(ents.FindByClass("grm_vending_machine")) do
        if IsValid(ent) then
            local row = {
                pos = vecToTable(ent:GetPos()),
                ang = angToTable(ent:GetAngles()),
            }
            if GRM.VendingBiz then
                row.owner = GRM.VendingBiz.GetOwner and GRM.VendingBiz.GetOwner(ent) or ""
                row.cash = GRM.VendingBiz.GetCash and GRM.VendingBiz.GetCash(ent) or 0
                row.sold = math.max(0, math.floor(tonumber(ent.GRMVendSold) or 0))
                row.earned = math.max(0, math.floor(tonumber(ent.GRMVendEarned) or 0))
            end
            saved[#saved + 1] = row
        end
    end

    file.Write(vendingSaveFile(), util.TableToJSON(saved, true))
    reply(ply, "[GRM Food] Сохранено автоматов: " .. #saved .. ". Файл: data/" .. vendingSaveFile())

    return true, #saved
end

function GRM.Food.LoadVendingMachines(ply, replaceAll)
    if IsValid(ply) and not canManageVending(ply) then
        reply(ply, "[GRM Food] Только superadmin может загружать автоматы.")
        return false
    end

    local path = vendingSaveFile()
    if not file.Exists(path, "DATA") then
        if IsValid(ply) then
            reply(ply, "[GRM Food] Сохранённые автоматы для этой карты не найдены.")
        end
        return false
    end

    local raw = file.Read(path, "DATA")
    if not raw or raw == "" then return false end

    local ok, data = pcall(util.JSONToTable, raw, false, true)
    if not ok or not istable(data) then
        reply(ply, "[GRM Food] Ошибка чтения файла автоматов: data/" .. path)
        return false
    end

    removeVendingMachines(replaceAll == true)

    local count = 0
    for _, row in ipairs(data) do
        if istable(row) and row.pos and row.ang then
            local ent = createPermanentVending(tableToVec(row.pos), tableToAng(row.ang))
            if IsValid(ent) then
                count = count + 1
                -- Владелец, касса и счётчик продаж возвращаются вместе с автоматом.
                if GRM.VendingBiz then
                    if isstring(row.owner) and row.owner ~= "" then
                        ent:SetNWString("GRM_VendOwner", row.owner)
                        ent.GRMVendOwner = row.owner
                    end
                    if GRM.VendingBiz.SetCash then
                        GRM.VendingBiz.SetCash(ent, tonumber(row.cash) or 0)
                    end
                    ent.GRMVendSold = math.max(0, math.floor(tonumber(row.sold) or 0))
                    ent.GRMVendEarned = math.max(0, math.floor(tonumber(row.earned) or 0))
                    ent:SetNWInt("GRM_VendSold", ent.GRMVendSold)
                    ent:SetNWInt("GRM_VendEarned", ent.GRMVendEarned)
                end
            end
        end
    end

    reply(ply, "[GRM Food] Загружено автоматов: " .. count .. ".")
    return true, count
end

function GRM.Food.ClearVendingMachines(ply, saveEmpty)
    if not canManageVending(ply) then
        reply(ply, "[GRM Food] Только superadmin может очищать автоматы.")
        return false
    end

    removeVendingMachines(true)

    if saveEmpty then
        ensureVendingSaveDir()
        file.Write(vendingSaveFile(), "[]")
        reply(ply, "[GRM Food] Все автоматы удалены, сохранение для карты очищено.")
    else
        reply(ply, "[GRM Food] Все автоматы удалены. Файл сохранения не изменён.")
    end

    return true
end

local function vendingCommand(callback)
    return function(ply)
        callback(ply)
    end
end

concommand.Add("grm_vending_save", vendingCommand(function(ply)
    GRM.Food.SaveVendingMachines(ply)
end))

concommand.Add("grm_vending_load", vendingCommand(function(ply)
    GRM.Food.LoadVendingMachines(ply, true)
end))

concommand.Add("grm_vending_clear", vendingCommand(function(ply)
    GRM.Food.ClearVendingMachines(ply, true)
end))

hook.Add("PlayerSay", "GRM_Food_VendingChatCommands", function(ply, text)
    local cmd = string.Trim(string.lower(text or ""))

    if cmd == "!grmsavevending" or cmd == "/grmsavevending" or cmd == "!grm_vending_save" or cmd == "/grm_vending_save" then
        GRM.Food.SaveVendingMachines(ply)
        return ""
    end

    if cmd == "!grmloadvending" or cmd == "/grmloadvending" or cmd == "!grm_vending_load" or cmd == "/grm_vending_load" then
        GRM.Food.LoadVendingMachines(ply, true)
        return ""
    end

    if cmd == "!grmclearvending" or cmd == "/grmclearvending" or cmd == "!grm_vending_clear" or cmd == "/grm_vending_clear" then
        GRM.Food.ClearVendingMachines(ply, true)
        return ""
    end
end)

if GRM.Boot and GRM.Boot.Task then
    GRM.Boot.Task("food.vending", "late", function() GRM.Food.LoadVendingMachines(nil, false) end,
        { label = "Еда: торговые автоматы" })
else
    hook.Add("InitPostEntity", "GRM_Food_LoadPermanentVending", function()
        timer.Simple(1, function() GRM.Food.LoadVendingMachines(nil, false) end)
    end)
end

hook.Add("PostCleanupMap", "GRM_Food_Cleanup", function()
    timer.Simple(0.5, function()
        GRM.Food.LoadVendingMachines(nil, false)
    end)
end)

-- ============================================================
-- ЛОГИКА ГОЛОДА И ЖАЖДЫ
-- ============================================================

local hungerData = {}
local thirstData = {}
local nextHungerDamage = {}
local nextHungerWarning = {}
local nextThirstDamage = {}
local nextThirstWarning = {}
local SAVE_FILE = "grm_hunger.json"
local THIRST_SAVE_FILE = "grm_thirst.json"

local function getPlayerID(ply)
    if not IsValid(ply) then return nil end
    if GRM.Identity and GRM.Identity.CharacterKey then return GRM.Identity.CharacterKey(ply) end
    return ply:SteamID64() or ply:SteamID() or tostring(ply:UserID())
end

local function loadHunger()
    if not file.Exists(SAVE_FILE, "DATA") then return end

    local raw = file.Read(SAVE_FILE, "DATA")
    if not raw or raw == "" then return end

    local ok, data = pcall(util.JSONToTable, raw, false, true)
    if ok and istable(data) then
        hungerData = data
    end
end

local function saveHunger()
    local ok, enc = pcall(util.TableToJSON, hungerData, true)
    if ok and enc then
        file.Write(SAVE_FILE, enc)
    end
end

local function loadThirst()
    if not file.Exists(THIRST_SAVE_FILE, "DATA") then return end
    local raw = file.Read(THIRST_SAVE_FILE, "DATA")
    if not raw or raw == "" then return end
    local ok, data = pcall(util.JSONToTable, raw, false, true)
    if ok and istable(data) then thirstData = data end
end

local function saveThirst()
    local ok, enc = pcall(util.TableToJSON, thirstData, true)
    if ok and enc then file.Write(THIRST_SAVE_FILE, enc) end
end

local function saveVitals()
    saveHunger()
    saveThirst()
end

loadHunger()
loadThirst()

-- Legacy hunger records were keyed by account SteamID64. Move them to
-- char1 once Character Core is available so the old value is not lost.
if GRM.Identity then
    local moved = {}
    for key, value in pairs(hungerData) do
        local raw = tostring(key or "")
        if raw:match("^%d+$") then
            local newKey = raw .. ":char1"
            if hungerData[newKey] == nil then moved[newKey] = value end
            hungerData[key] = nil
        end
    end
    for key, value in pairs(moved) do hungerData[key] = value end
    if next(moved) ~= nil then saveHunger() end
end

function GRM.Food.GetHunger(ply)
    if not IsValid(ply) then return cfg().HungerMax or 100 end

    local sid = getPlayerID(ply)
    if not sid then return cfg().HungerMax or 100 end

    if hungerData[sid] == nil then
        hungerData[sid] = cfg().HungerMax or 100
    end

    return tonumber(hungerData[sid]) or (cfg().HungerMax or 100)
end

function GRM.Food.SetHunger(ply, value)
    if not IsValid(ply) then return end

    local sid = getPlayerID(ply)
    if not sid then return end

    local maxHunger = cfg().HungerMax or 100
    hungerData[sid] = math.Clamp(tonumber(value) or maxHunger, 0, maxHunger)
    GRM.Food.SyncHunger(ply)
end

function GRM.Food.GetThirst(ply)
    if not IsValid(ply) then return cfg().ThirstMax or 100 end
    local sid = getPlayerID(ply)
    if not sid then return cfg().ThirstMax or 100 end
    if thirstData[sid] == nil then thirstData[sid] = cfg().ThirstMax or 100 end
    return tonumber(thirstData[sid]) or (cfg().ThirstMax or 100)
end

function GRM.Food.SetThirst(ply, value)
    if not IsValid(ply) then return end
    local sid = getPlayerID(ply)
    if not sid then return end
    local maxT = cfg().ThirstMax or 100
    thirstData[sid] = math.Clamp(tonumber(value) or maxT, 0, maxT)
    GRM.Food.SyncHunger(ply)
end

function GRM.Food.RestoreHunger(ply, amount)
    if not IsValid(ply) then return end
    local add = tonumber(amount) or 0
    GRM.Food.SetHunger(ply, GRM.Food.GetHunger(ply) + add)
    if add > 0 and GRM.Encumbrance and GRM.Encumbrance.AddBodyMassFromFood then
        GRM.Encumbrance.AddBodyMassFromFood(ply, add)
    end
end

function GRM.Food.RestoreThirst(ply, amount)
    if not IsValid(ply) then return end
    GRM.Food.SetThirst(ply, GRM.Food.GetThirst(ply) + (tonumber(amount) or 0))
end

function GRM.Food.SyncHunger(ply)
    if not IsValid(ply) then return end

    net.Start("GRM_Food_Sync")
        net.WriteFloat(GRM.Food.GetHunger(ply))
        net.WriteFloat(GRM.Food.GetThirst(ply))
    net.Send(ply)
end

if timer.Exists("GRM_Food_HungerTick") then
    timer.Remove("GRM_Food_HungerTick")
end

--[[ Голод и жажда — normal: это игровая логика, но точность в доли
     секунды не нужна, а расход всё равно считается от накопленного
     времени. При просадке сервера задачу отложат, и это верно. ]]
local function hungerTick()
    for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
        if IsValid(ply) then
            if GRM.ServerBan and GRM.ServerBan.PlayerBanned and GRM.ServerBan.PlayerBanned(ply) then
                GRM.Food.SetHunger(ply, cfg().HungerMax or 100)
                GRM.Food.SetThirst(ply, cfg().ThirstMax or 100)
            elseif not ply:Alive() then
                GRM.Food.SyncHunger(ply)
            else
                --[[ Множитель расхода. Дома человек тратит меньше сил:
                     модуль жилья (sh_grm_housing) возвращает через этот
                     хук значение меньше единицы. Сделано хуком, а не
                     проверкой жилья прямо здесь, чтобы питание не зависело
                     от недвижимости и отдых можно было отключить конваром. ]]
                local scale = hook.Run("GRM_Food_DrainScale", ply)
                scale = (isnumber(scale) and scale > 0) and math.min(scale, 4) or 1

                local cur = GRM.Food.GetHunger(ply)
                local newVal = math.max(0, cur - (cfg().HungerDrainPerSecond or 0.02) * scale)
                GRM.Food.SetHunger(ply, newVal)

                local tcur = GRM.Food.GetThirst(ply)
                local tnew = math.max(0, tcur - (cfg().ThirstDrainPerSecond or 0.035) * scale)
                GRM.Food.SetThirst(ply, tnew)

                if newVal <= 0 then
                    nextHungerDamage[ply] = nextHungerDamage[ply] or 0
                    if CurTime() >= nextHungerDamage[ply] then
                        nextHungerDamage[ply] = CurTime() + (cfg().HungerDamageInterval or 10)
                        ply:TakeDamage(cfg().HungerDamageAmount or 2, game.GetWorld(), game.GetWorld())
                        ply:ChatPrint("[Голод] Вы умираете от голода!")
                    end
                end

                if tnew <= 0 then
                    nextThirstDamage[ply] = nextThirstDamage[ply] or 0
                    if CurTime() >= nextThirstDamage[ply] then
                        nextThirstDamage[ply] = CurTime() + (cfg().ThirstDamageInterval or 8)
                        ply:TakeDamage(cfg().ThirstDamageAmount or 2, game.GetWorld(), game.GetWorld())
                        ply:ChatPrint("[Жажда] Вы умираете от жажды!")
                    end
                end

                local warningThreshold = (cfg().HungerMax or 100) * ((cfg().HungerWarningThreshold or 20) / 100)
                if newVal <= warningThreshold and newVal > 0 then
                    nextHungerWarning[ply] = nextHungerWarning[ply] or 0
                    if CurTime() >= nextHungerWarning[ply] then
                        nextHungerWarning[ply] = CurTime() + 10
                        ply:ChatPrint("[Голод] Вы голодны! Найдите еду.")
                    end
                end

                local tWarn = (cfg().ThirstMax or 100) * ((cfg().ThirstWarningThreshold or 20) / 100)
                if tnew <= tWarn and tnew > 0 then
                    nextThirstWarning[ply] = nextThirstWarning[ply] or 0
                    if CurTime() >= nextThirstWarning[ply] then
                        nextThirstWarning[ply] = CurTime() + 10
                        ply:ChatPrint("[Жажда] Вы хотите пить! Найдите воду.")
                    end
                end
            end
        end
    end
end


if timer.Exists("GRM_Food_AutoSave") then
    timer.Remove("GRM_Food_AutoSave")
end

timer.Create("GRM_Food_AutoSave", 30, 0, saveHunger)

hook.Add("PlayerInitialSpawn", "GRM_Food_OnJoin", function(ply)
    timer.Simple(1, function()
        if not IsValid(ply) then return end

        local sid = getPlayerID(ply)
        if sid and hungerData[sid] == nil then
            hungerData[sid] = cfg().HungerMax or 100
        end

        GRM.Food.SyncHunger(ply)
    end)
end)

hook.Add("GRM_CharacterChanged", "GRM_Food_OnCharacterChanged", function(ply)
    if not IsValid(ply) then return end
    local sid = getPlayerID(ply)
    if sid and hungerData[sid] == nil then hungerData[sid] = cfg().HungerMax or 100 end
    GRM.Food.SyncHunger(ply)
    saveHunger()
end)

hook.Add("PlayerSpawn", "GRM_Food_OnSpawn", function(ply)
    timer.Simple(0, function()
        if IsValid(ply) then
            GRM.Food.SyncHunger(ply)
        end
    end)
end)

if GRM.Sched then
    GRM.Sched.Every("food.hunger", 1, hungerTick, { prio = "normal" })
else
    timer.Create("GRM_Food_HungerTick", 1, 0, hungerTick)
end

hook.Add("PlayerDisconnected", "GRM_Food_OnLeave", function(ply)
    nextHungerDamage[ply] = nil
    nextHungerWarning[ply] = nil
    nextThirstDamage[ply] = nil
    nextThirstWarning[ply] = nil
    saveVitals()
end)

hook.Add("ShutDown", "GRM_Food_Shutdown", saveVitals)

-- ============================================================
-- ОБРАБОТЧИК ПОКУПКИ
-- ============================================================

local function isItemAllowedInVending(itemID)
    for _, allowedID in ipairs(cfg().VendingMachineItems or {}) do
        if allowedID == itemID then
            return true
        end
    end

    return false
end

net.Receive("GRM_Vending_Buy", function(_, ply)
    if not IsValid(ply) then return end

    ply.GRMFoodNextBuy = ply.GRMFoodNextBuy or 0
    if CurTime() < ply.GRMFoodNextBuy then return end
    ply.GRMFoodNextBuy = CurTime() + 0.3

    local ent = net.ReadEntity()
    local itemID = net.ReadString()

    if not IsValid(ent) or ent:GetClass() ~= "grm_vending_machine" then
        ply:ChatPrint("[Автомат] Ошибка: неверный автомат.")
        return
    end

    local maxDist = cfg().VendingUseDistance or 150
    if ply:GetPos():DistToSqr(ent:GetPos()) > maxDist * maxDist then
        ply:ChatPrint("[Автомат] Вы слишком далеко от автомата.")
        return
    end

    if not isItemAllowedInVending(itemID) then
        ply:ChatPrint("[Автомат] Этот товар нельзя купить здесь.")
        return
    end

    local data = getFoodData(itemID)
    if not data then
        ply:ChatPrint("[Автомат] Товар не найден.")
        return
    end

    local price = tonumber(data.price) or 0

    -- Интеграция с экономикой GRM, если она есть.
    -- Если функций GRM.HasMoney / GRM.TakeMoney нет, товар будет бесплатным.
    if GRM.HasMoney and not GRM.HasMoney(ply, price) then
        ply:ChatPrint("[Автомат] Недостаточно денег!")
        return
    end

    if GRM.TakeMoney then
        GRM.TakeMoney(ply, price)
    end
    if GRM.VendingBiz and GRM.VendingBiz.AddSale then GRM.VendingBiz.AddSale(ent, price) end

    local food = ents.Create("grm_food_item")
    if not IsValid(food) then
        ply:ChatPrint("[Автомат] Ошибка выдачи товара.")
        return
    end

    -- ВАЖНО: itemID и модель задаём ДО Spawn(), чтобы Initialize()
    -- не успевал поставить дефолтную модель яблока/апельсина.
    food.GRMFoodItemID = itemID

    if food.SetItemID then
        food:SetItemID(itemID)
    end

    food:SetNWString("ItemID", itemID)
    food:SetModel(data.model or "models/props/cs_office/coffee_mug.mdl")

    food:SetPos(ply:GetPos() + ply:GetForward() * 50 + Vector(0, 0, 25))
    food:SetAngles(Angle(0, ply:EyeAngles().y, 0))
    food:Spawn()

    if food.SetFoodItemID then
        food:SetFoodItemID(itemID)
    elseif food.ApplyFoodModel then
        food:ApplyFoodModel()
    end

    food:SetOwner(ply)

    local phys = food:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
    end

    ply:ChatPrint("[Автомат] Вы купили " .. (data.name or itemID) .. ".")
end)

-- Админ-команда для теста: grm_food_set <ник/SteamID64> <значение>
concommand.Add("grm_food_set", function(ply, _, args)
    if IsValid(ply) and not ply:IsAdmin() then return end

    local targetName = args[1]
    local value = tonumber(args[2])

    if not targetName or not value then
        if IsValid(ply) then
            ply:ChatPrint("Использование: grm_food_set <ник/SteamID64> <0-100>")
        else
            print("Использование: grm_food_set <ник/SteamID64> <0-100>")
        end
        return
    end

    for _, target in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
        if string.find(string.lower(target:Nick()), string.lower(targetName), 1, true) or target:SteamID64() == targetName then
            GRM.Food.SetHunger(target, value)

            if IsValid(ply) then
                ply:ChatPrint("Сытость установлена для " .. target:Nick())
            else
                print("Сытость установлена для " .. target:Nick())
            end
            return
        end
    end

    if IsValid(ply) then
        ply:ChatPrint("Игрок не найден.")
    else
        print("Игрок не найден.")
    end
end)

print("[GRM Food] Сервер загружен. Сущности зарегистрированы через scripted_ents.Register.")
