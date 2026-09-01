--[[--------------------------------------------------------------------
    GRM Closed Customization v1.0.0
    Безопасные аксессуары из Inventory: 6 слотов, CharacterKey persistence,
    серверный каталог, магазин GRM Vendor и закрытый редактор трансформаций.
    PAC3-код не используется.
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Customization = GRM.Customization or {}
local C = GRM.Customization
C.Version = "1.0.0"
C.CatalogFile = "grm_customization/catalog.json"
C.LoadoutsFile = "grm_customization/loadouts.json"
C.MaxAccessories = 6

C.Slots = {
    head = { name = "Голова", icon = "icon16/user_gray.png", bones = { "ValveBiped.Bip01_Head1" } },
    face = { name = "Лицо", icon = "icon16/emoticon_smile.png", bones = { "ValveBiped.Bip01_Head1" } },
    torso = { name = "Туловище", icon = "icon16/shield.png", bones = { "ValveBiped.Bip01_Spine2", "ValveBiped.Bip01_Spine1" } },
    legs = { name = "Ноги", icon = "icon16/lorry.png", bones = { "ValveBiped.Bip01_Pelvis", "ValveBiped.Bip01_L_Thigh", "ValveBiped.Bip01_R_Thigh" } },
    left_hand = { name = "Левая рука", icon = "icon16/arrow_left.png", bones = { "ValveBiped.Bip01_L_Hand", "ValveBiped.Bip01_L_Forearm" } },
    right_hand = { name = "Правая рука", icon = "icon16/arrow_right.png", bones = { "ValveBiped.Bip01_R_Hand", "ValveBiped.Bip01_R_Forearm" } },
}
C.SlotOrder = { "head", "face", "torso", "legs", "left_hand", "right_hand" }
C.Catalog = C.Catalog or {}
C.Loadouts = C.Loadouts or {}
C.Profiles = C.Profiles or {} -- [CharacterKey][accessoryID] = transform

-- Закрытый реестр разрешённых функций. Внешний GRM-модуль может добавить
-- свой тип через RegisterFunctionType, но клиент не может прислать Lua/код.
C.FunctionTypes = C.FunctionTypes or {
    gasmask = { name = "Противогаз", description = "Защита от яда, газа, кислоты и радиации" },
    backpack = { name = "Рюкзак", description = "Увеличивает допустимый переносимый вес" },
    radio = { name = "Рация", description = "Заменяет включённый переносной радиомодулятор" },
    watch = { name = "Часы", description = "Показывает часы и дату на HUD" },
    armor = { name = "Защитное снаряжение", description = "Снижает пулевой/взрывной/режущий урон" },
    artificial_eye = { name = "Искусственный глаз", description = "Связь с чипом зрения и автосканированием" },
    night_vision = { name = "Очки ночного видения", description = "Включает ночной режим при активном чипе" },
    neuro_link = { name = "Нейроинтерфейс", description = "Связь аксессуара с системой аугментаций" },
    prosthesis = { name = "Функциональный протез", description = "Расширенный функционал конечности" },
    -- Находка 178f: сумка ограбления — поэтапный сбор денег с паллет
    loot_bag = { name = "Сумка ограбления", description = "Поэтапный сбор денег с паллет (до 100.000, порциями за подход)" },
}

-- Интеграция аксессуаров с аугментациями: функции не содержат Lua от клиента.
local function accessoryFlag(ply, id, enabled)
    if IsValid(ply) then ply:SetNWBool("GRM_Accessory_" .. id, enabled == true) end
    hook.Run("GRM_AccessoryAugmentationLink", ply, id, enabled == true)
end
C.FunctionTypes.artificial_eye.OnEquip=function(ply) accessoryFlag(ply,"artificial_eye",true) end
C.FunctionTypes.artificial_eye.OnUnequip=function(ply) accessoryFlag(ply,"artificial_eye",false) end
C.FunctionTypes.night_vision.OnEquip=function(ply) accessoryFlag(ply,"night_vision",true) end
C.FunctionTypes.night_vision.OnUnequip=function(ply) accessoryFlag(ply,"night_vision",false) end
C.FunctionTypes.neuro_link.OnEquip=function(ply) accessoryFlag(ply,"neuro_link",true) end
C.FunctionTypes.neuro_link.OnUnequip=function(ply) accessoryFlag(ply,"neuro_link",false) end
C.FunctionTypes.prosthesis.OnEquip=function(ply) accessoryFlag(ply,"prosthesis",true) end
C.FunctionTypes.prosthesis.OnUnequip=function(ply) accessoryFlag(ply,"prosthesis",false) end

function C.RegisterFunctionType(id, data)
    id = string.lower(tostring(id or "")):gsub("[^%w_%-]", "")
    if id == "" or not istable(data) then return false end
    C.FunctionTypes[id] = table.Copy(data)
    return true
end

local function cleanID(value)
    return string.lower(tostring(value or "")):gsub("[^%w_%-]", ""):sub(1, 48)
end

local function finite(value, fallback)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return fallback or 0 end
    return value
end

local function vecData(value, limit)
    value = istable(value) and value or {}
    limit = limit or 48
    return {
        x = math.Clamp(finite(value.x, 0), -limit, limit),
        y = math.Clamp(finite(value.y, 0), -limit, limit),
        z = math.Clamp(finite(value.z, 0), -limit, limit),
    }
end

local function angData(value)
    value = istable(value) and value or {}
    return {
        p = math.NormalizeAngle(finite(value.p, 0)),
        y = math.NormalizeAngle(finite(value.y, 0)),
        r = math.NormalizeAngle(finite(value.r, 0)),
    }
end

local function slotAllowsBone(slot, bone)
    local def = C.Slots[slot]
    if not def then return false end
    for _, allowed in ipairs(def.bones or {}) do if allowed == bone then return true end end
    return false
end

local function normalizeCatalogItem(id, input)
    input = istable(input) and input or {}
    id = cleanID(id ~= "" and id or input.id)
    if id == "" then return nil end
    local slot = tostring(input.slot or "head")
    if not C.Slots[slot] then slot = "head" end
    local bone = tostring(input.bone or C.Slots[slot].bones[1])
    if not slotAllowsBone(slot, bone) then bone = C.Slots[slot].bones[1] end
    local model = tostring(input.model or "")
    local functions = {}
    for functionID in pairs(C.FunctionTypes or {}) do
        if istable(input.functions) and input.functions[functionID] == true then functions[functionID] = true end
    end
    local cfg = istable(input.functionConfig) and input.functionConfig or {}
    local functionConfig = {
        gasProtection = math.Clamp(finite(cfg.gasProtection, 0.85), 0, 0.98),
        backpackCapacity = math.Clamp(finite(cfg.backpackCapacity, 20), 0, 100),
        armorReduction = math.Clamp(finite(cfg.armorReduction, 0.2), 0, 0.75),
        -- Находка 178f: сумка ограбления (макс. запас и порция за подход)
        lootMaxMoney = math.Clamp(math.floor(finite(cfg.lootMaxMoney, 100000)), 1000, 1000000),
        lootPerUse = math.Clamp(math.floor(finite(cfg.lootPerUse, 25000)), 1000, 100000),
    }
    return {
        id = id,
        itemID = "grm_acc_" .. id,
        name = tostring(input.name or id):sub(1, 64),
        category = tostring(input.category or "Прочее"):sub(1, 48),
        description = tostring(input.description or "Нательный аксессуар"):sub(1, 220),
        model = model:sub(1, 192),
        price = math.Clamp(math.floor(finite(input.price, 0)), 0, 100000000),
        slot = slot,
        bone = bone,
        position = vecData(input.position, 48),
        angles = angData(input.angles),
        scale = math.Clamp(finite(input.scale, 1), 0.2, 3),
        skin = math.Clamp(math.floor(finite(input.skin, 0)), 0, 32),
        functions = functions,
        functionConfig = functionConfig,
    }
end

local function normalizeEquipped(slot, input)
    if not C.Slots[slot] or not istable(input) then return nil end
    local accessoryID = cleanID(input.accessoryID)
    local item = C.Catalog[accessoryID]
    if not item or item.slot ~= slot then return nil end
    local bone = tostring(input.bone or item.bone)
    if not slotAllowsBone(slot, bone) then bone = item.bone end
    return {
        accessoryID = accessoryID,
        itemID = item.itemID,
        bone = bone,
        position = vecData(input.position or item.position, 48),
        angles = angData(input.angles or item.angles),
        scale = math.Clamp(finite(input.scale, item.scale), 0.2, 3),
    }
end

function C.GetItem(id) return C.Catalog[cleanID(id)] end
function C.GetItemByInventoryID(itemID)
    for _, item in pairs(C.Catalog or {}) do if item.itemID == itemID then return item end end
end
function C.IsBoneAllowed(slot, bone) return slotAllowsBone(slot, bone) end

if SERVER then
    util.AddNetworkString("GRM_Custom_Catalog")
    util.AddNetworkString("GRM_Custom_Sync")
    util.AddNetworkString("GRM_Custom_Request")
    util.AddNetworkString("GRM_Custom_Op")
    util.AddNetworkString("GRM_Custom_Open")
    util.AddNetworkString("GRM_Custom_Close")
    util.AddNetworkString("GRM_Custom_Ack")
    util.AddNetworkString("GRM_Custom_AdminOpen")
    util.AddNetworkString("GRM_Custom_AdminOp")

    local function ensureDir()
        if not file.IsDir("grm_customization", "DATA") then file.CreateDir("grm_customization") end
    end
    local function readJSON(path)
        for _, candidate in ipairs({path, path .. ".backup"}) do
            if file.Exists(candidate, "DATA") then
                local raw = file.Read(candidate, "DATA") or ""
                local ok, data = pcall(util.JSONToTable, raw, false, true)
                if ok and istable(data) then
                    if candidate ~= path then print("[GRM Customization] restored from backup: " .. candidate) end
                    return data
                end
            end
        end
    end
    local function writeJSON(path, data)
        ensureDir()
        local ok, raw = pcall(util.TableToJSON, data or {}, true)
        if not ok or not isstring(raw) or raw == "" then return false end
        local old = file.Exists(path, "DATA") and file.Read(path, "DATA") or nil
        if isstring(old) and old ~= "" then file.Write(path .. ".backup", old) end
        file.Write(path, raw)
        if file.Read(path, "DATA") ~= raw then return false end
        local parsed = readJSON(path)
        return istable(parsed)
    end
    local function sendAck(ply, ok, action, message)
        if not IsValid(ply) then return end
        net.Start("GRM_Custom_Ack")
            net.WriteBool(ok == true)
            net.WriteString(tostring(action or ""))
            net.WriteString(tostring(message or ""))
        net.Send(ply)
    end

    local function charKey(ply)
        if GRM.Identity and GRM.Identity.CharacterKey then return GRM.Identity.CharacterKey(ply) end
        if GRM.Char and GRM.Char.GetActiveKey then return GRM.Char.GetActiveKey(ply) end
        return tostring(ply:SteamID64()) .. ":char1"
    end

    local function loadData()
        C.Catalog = {}
        for id, input in pairs(readJSON(C.CatalogFile) or {}) do
            local item = normalizeCatalogItem(id, input)
            if item and util.IsValidModel(item.model) then C.Catalog[item.id] = item end
        end
        local stored = readJSON(C.LoadoutsFile) or {}
        C.Loadouts, C.Profiles = {}, {}
        local records = istable(stored.records) and stored.records or nil
        if records then
            for _, rec in pairs(records) do
                if istable(rec) and tostring(rec.key or "") ~= "" then
                    local characterKey = tostring(rec.key)
                    C.Loadouts[characterKey], C.Profiles[characterKey] = {}, {}
                    for slot, equipped in pairs(istable(rec.slots) and rec.slots or {}) do
                        local normalized = normalizeEquipped(slot, equipped)
                        if normalized then C.Loadouts[characterKey][slot] = normalized end
                    end
                    for accessoryID, profile in pairs(istable(rec.profiles) and rec.profiles or {}) do
                        local item = C.Catalog[tostring(accessoryID)]
                        if item then
                            local payload = table.Copy(profile)
                            payload.accessoryID = item.id
                            local normalized = normalizeEquipped(item.slot, payload)
                            if normalized then C.Profiles[characterKey][item.id] = normalized end
                        end
                    end
                end
            end
        else
            -- Legacy v1: map CharacterKey -> slots.
            for characterKey, loadout in pairs(stored) do
                characterKey = tostring(characterKey)
                C.Loadouts[characterKey], C.Profiles[characterKey] = {}, {}
                for slot, equipped in pairs(istable(loadout) and loadout or {}) do
                    local normalized = normalizeEquipped(slot, equipped)
                    if normalized then
                        C.Loadouts[characterKey][slot] = normalized
                        C.Profiles[characterKey][normalized.accessoryID] = table.Copy(normalized)
                    end
                end
            end
        end
    end
    local function saveCatalog() return writeJSON(C.CatalogFile, C.Catalog) end
    local function saveLoadouts()
        local records, keys = {}, {}
        for k in pairs(C.Loadouts) do keys[k] = true end
        for k in pairs(C.Profiles) do keys[k] = true end
        for characterKey in pairs(keys) do
            records[#records + 1] = {key=tostring(characterKey),slots=table.Copy(C.Loadouts[characterKey] or {}),profiles=table.Copy(C.Profiles[characterKey] or {})}
        end
        table.sort(records, function(a,b) return a.key < b.key end)
        return writeJSON(C.LoadoutsFile, {version=2,records=records})
    end
    loadData()
    function C.SaveData() return saveCatalog() and saveLoadouts() end
    function C.LoadData()
        loadData()
        return true
    end

    function C.GetLoadout(plyOrKey)
        local key = IsValid(plyOrKey) and charKey(plyOrKey) or tostring(plyOrKey or "")
        C.Loadouts[key] = C.Loadouts[key] or {}
        C.Profiles[key] = C.Profiles[key] or {}
        return C.Loadouts[key], key
    end

    function C.GetFunctionalItems(ply, functionID)
        local out = {}
        local loadout = C.GetLoadout(ply)
        for slot, equipped in pairs(loadout) do
            local item = C.Catalog[equipped.accessoryID]
            if item and istable(item.functions) and item.functions[functionID] == true then
                out[#out + 1] = { slot = slot, equipped = equipped, item = item }
            end
        end
        return out
    end

    function C.HasFunction(ply, functionID)
        return IsValid(ply) and #C.GetFunctionalItems(ply, functionID) > 0
    end

    function C.GetFunctionValue(ply, functionID, configKey, mode)
        local values = C.GetFunctionalItems(ply, functionID)
        local result = mode == "sum" and 0 or nil
        for _, rec in ipairs(values) do
            local value = finite(rec.item.functionConfig and rec.item.functionConfig[configKey], 0)
            if mode == "sum" then result = result + value else result = math.max(result or 0, value) end
        end
        return result or 0
    end

    local function dispatchFunctionEvent(eventName, ply, slot, item, equipped)
        for functionID, enabled in pairs(item and item.functions or {}) do
            if enabled == true then
                local def = C.FunctionTypes[functionID]
                local callback = def and def[eventName]
                if isfunction(callback) then
                    local ok, err = pcall(callback, ply, item, equipped, slot)
                    if not ok then print("[GRM Customization] function " .. functionID .. " " .. eventName .. " error: " .. tostring(err)) end
                end
            end
        end
    end

    function C.EquipInventorySlot(ply, slotIndex, requestedSlot)
        if not IsValid(ply) or ply:GetNWBool("GRM_Arrested", false) then return false end
        if not (GRM.Inventory and GRM.Inventory.GetPlayerInv and GRM.Inventory.RemoveFromSlot) then return false end
        slotIndex = math.floor(tonumber(slotIndex) or 0)
        local inv = GRM.Inventory.GetPlayerInv(ply)
        local invSlot = inv and inv.slots and inv.slots[slotIndex]
        if not invSlot or not invSlot.id then return false end
        local item = C.GetItemByInventoryID(invSlot.id)
        if not item then
            if GRM.Notify then GRM.Notify(ply, "Этот предмет не является аксессуаром.", 255, 150, 90) end
            return false
        end
        if requestedSlot and requestedSlot ~= "" and requestedSlot ~= item.slot then
            if GRM.Notify then GRM.Notify(ply, "«" .. item.name .. "» нельзя надеть в слот «" .. tostring((C.Slots[requestedSlot] or {}).name or requestedSlot) .. "».", 255, 150, 90) end
            return false
        end
        local loadout = C.GetLoadout(ply)
        if loadout[item.slot] then
            if GRM.Notify then GRM.Notify(ply, "Слот «" .. C.Slots[item.slot].name .. "» уже занят. Сначала снимите аксессуар.", 255, 170, 80) end
            return false
        end
        if not GRM.Inventory.RemoveFromSlot(ply, slotIndex, 1) then return false end
        local _, characterKey = C.GetLoadout(ply)
        local remembered = C.Profiles[characterKey] and C.Profiles[characterKey][item.id]
        loadout[item.slot] = normalizeEquipped(item.slot, remembered or { accessoryID = item.id })
        C.Profiles[characterKey][item.id] = table.Copy(loadout[item.slot])
        saveLoadouts(); C.SyncPlayer(ply)
        dispatchFunctionEvent("OnEquip", ply, item.slot, item, loadout[item.slot])
        hook.Run("GRM_AccessoryEquipped", ply, item.slot, item, loadout[item.slot])
        if GRM.Encumbrance and GRM.Encumbrance.Refresh then GRM.Encumbrance.Refresh(ply) end
        if GRM.Notify then GRM.Notify(ply, "Надето: " .. item.name, 100, 220, 130) end
        return true
    end

    function C.UnequipSlot(ply, equipmentSlot, silent, deferSync)
        if not IsValid(ply) or not C.Slots[equipmentSlot] then return false, "Некорректный слот" end
        local loadout = C.GetLoadout(ply)
        local equipped = loadout[equipmentSlot]
        if not equipped then return false, "Слот уже пуст" end
        local item = C.Catalog[equipped.accessoryID]
        if not (GRM.Inventory and GRM.Inventory.AddItem) then return false, "Инвентарь не загружен" end
        local left = GRM.Inventory.AddItem(ply, equipped.itemID, 1)
        if left > 0 then return false, "В инвентаре нет свободного места" end
        loadout[equipmentSlot] = nil
        if not deferSync then saveLoadouts(); C.SyncPlayer(ply) end
        dispatchFunctionEvent("OnUnequip", ply, equipmentSlot, item, equipped)
        hook.Run("GRM_AccessoryUnequipped", ply, equipmentSlot, item, equipped)
        if GRM.Encumbrance and GRM.Encumbrance.Refresh then GRM.Encumbrance.Refresh(ply) end
        if not silent and GRM.Notify then GRM.Notify(ply, "Аксессуар снят в инвентарь: " .. C.Slots[equipmentSlot].name, 100, 220, 130) end
        return true
    end

    function C.UnequipAll(ply)
        local removed, errors = 0, {}
        for _, equipmentSlot in ipairs(C.SlotOrder) do
            local loadout = C.GetLoadout(ply)
            if loadout[equipmentSlot] then
                local ok, reason = C.UnequipSlot(ply, equipmentSlot, true, true)
                if ok then removed = removed + 1 else errors[#errors + 1] = reason end
            end
        end
        if removed > 0 then saveLoadouts(); C.SyncPlayer(ply) end
        return removed, errors
    end

    local function inventoryDef(item)
        return {
            type = "item", name = item.name, desc = item.description,
            icon = "icon16/user_suit.png", model = item.model, weight = 0.4,
            maxStack = 1, useFunc = "grm_accessory_equip", accessoryID = item.id,
        }
    end

    local function registerIntegrations()
        if GRM.Inventory and GRM.Inventory.RegisterItem then
            for _, item in pairs(C.Catalog) do GRM.Inventory.RegisterItem(item.itemID, inventoryDef(item)) end
        end
        if GRM.Inventory and GRM.Inventory.RegisterUseHandler then
            GRM.Inventory.RegisterUseHandler("grm_accessory_equip", function(ply, slotIndex)
                C.EquipInventorySlot(ply, slotIndex)
            end)
        end
        if GRM.Vendor then
            GRM.Vendor.Catalogs.accessory = {}
            GRM.Vendor.Models.accessory = "models/alyx.mdl"
            for _, item in pairs(C.Catalog) do
                GRM.Vendor.RegisterItem("accessory", item.itemID, {
                    name = item.name, price = item.price, model = item.model,
                    desc = item.description, category = item.category, maxStack = 1, noSell = true,
                    functions = table.Copy(item.functions or {}), functionConfig = table.Copy(item.functionConfig or {}),
                })
            end
        end
        return GRM.Inventory and GRM.Inventory.RegisterItem and GRM.Inventory.RegisterUseHandler and GRM.Vendor and GRM.Vendor.RegisterItem
    end
    timer.Create("GRM_Custom_RegisterIntegrations",1,0,function()if registerIntegrations()then timer.Remove("GRM_Custom_RegisterIntegrations")end end)
    timer.Simple(0, registerIntegrations)
    function C.LoadData()
        loadData(); registerIntegrations()
        for _, target in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(target) then C.SendCatalog(target); C.SyncPlayer(target) end
        end
        return true
    end

    function C.SendCatalog(ply)
        net.Start("GRM_Custom_Catalog") net.WriteTable(C.Catalog) net.Send(ply)
    end
    function C.SyncPlayer(ply, recipient)
        if not IsValid(ply) then return end
        local loadout = C.GetLoadout(ply)
        net.Start("GRM_Custom_Sync")
            net.WriteEntity(ply)
            net.WriteString(charKey(ply))
            net.WriteTable(loadout)
        if recipient then net.Send(recipient) else net.Broadcast() end
    end
    function C.SyncAllTo(ply)
        C.SendCatalog(ply)
        for _, target in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do if IsValid(target) then C.SyncPlayer(target, ply) end end
    end

    function C.Confiscate(ply)
        if IsValid(ply) and ply:GetNWBool("GRM_CustomEditing", false) then
            ply.GRM_CustomEditingUntil = nil
            ply:SetNWBool("GRM_CustomEditing", false)
            net.Start("GRM_Custom_Close") net.Send(ply)
        end
        local loadout = C.GetLoadout(ply)
        local removed = table.Count(loadout)
        if removed > 0 then
            for slot, equipped in pairs(loadout) do
                local item=C.Catalog[equipped.accessoryID]
                if item then dispatchFunctionEvent("OnUnequip", ply, slot, item, equipped) end
                hook.Run("GRM_AccessoryUnequipped", ply, slot, item, equipped)
            end
            local _, key = C.GetLoadout(ply)
            C.Loadouts[key] = {}
            saveLoadouts()
            C.SyncPlayer(ply)
            if GRM.Encumbrance and GRM.Encumbrance.Refresh then GRM.Encumbrance.Refresh(ply) end
        end
        return removed
    end

    local function openEditor(ply)
        if not IsValid(ply) or not ply:Alive() or ply:InVehicle() or ply:GetNWBool("GRM_Arrested", false)
            or ply:GetNWBool("GRM_Cuffed", false) then return end
        ply.GRM_CustomEditingUntil = CurTime() + 12
        ply:SetNWBool("GRM_CustomEditing", true)
        -- Сначала отдельным авторитетным пакетом обновляем equipment state.
        -- Open передаёт только каталог: редактор больше не может заменить
        -- живой loadout пустой/перепутанной второй таблицей.
        C.SyncPlayer(ply, ply)
        net.Start("GRM_Custom_Open")
            net.WriteTable(C.Catalog)
        net.Send(ply)
    end
    local function closeEditor(ply)
        if not IsValid(ply) then return end
        ply.GRM_CustomEditingUntil = nil
        ply:SetNWBool("GRM_CustomEditing", false)
    end

    local function rateOK(ply)
        if CurTime() < (ply.GRM_CustomNextOp or 0) then return false end
        ply.GRM_CustomNextOp = CurTime() + 0.12
        return true
    end

    net.Receive("GRM_Custom_Request", function(_, ply) C.SyncAllTo(ply) end)
    net.Receive("GRM_Custom_Open", function(_, ply) if rateOK(ply) then openEditor(ply) end end)
    net.Receive("GRM_Custom_Op", function(_, ply)
        local op = net.ReadString()
        if op == "close" then closeEditor(ply) return end
        if op == "ping" then
            if ply:GetNWBool("GRM_CustomEditing", false) then ply.GRM_CustomEditingUntil = CurTime() + 12 end
            return
        end
        if op == "pose_freeze" or op == "pose_unfreeze" then
            local frozen = op == "pose_freeze"
            ply:SetNWBool("GRM_CustomPoseFrozen", frozen)
            ply:Freeze(frozen)
            if frozen then ply:SetSequence("pose_standing_01"); ply:SetPlaybackRate(0) else ply:ResetSequence(ply:LookupSequence("idle_all_01") or 0); ply:SetPlaybackRate(1) end
            sendAck(ply,true,op,frozen and "Персонаж заморожен в Т-позе" or "Персонаж разморожен")
            return
        end
        if not rateOK(ply) then sendAck(ply, false, op, "Слишком частое действие") return end
        if op == "equip_inventory" then
            local inventorySlot = net.ReadUInt(8)
            local equipmentSlot = net.ReadString()
            local ok = C.EquipInventorySlot(ply, inventorySlot, equipmentSlot)
            sendAck(ply, ok, op, ok and "Аксессуар надет" or "Не удалось надеть аксессуар")
            return
        end
        if op == "unequip_inventory" then
            local equipmentSlot = net.ReadString()
            if ply:GetNWBool("GRM_Arrested", false) then
                sendAck(ply, false, op, "Во время ареста экипировка недоступна")
                return
            end
            local ok, reason = C.UnequipSlot(ply, equipmentSlot)
            sendAck(ply, ok, op, ok and "Аксессуар снят в инвентарь" or tostring(reason))
            return
        end
        if ply:GetNWBool("GRM_Arrested", false) or not ply:GetNWBool("GRM_CustomEditing", false) then
            sendAck(ply, false, op, "Редактор не активен или действие запрещено")
            return
        end
        if op == "save_all_close" then
            local incoming = net.ReadTable() or {}
            local loadout = C.GetLoadout(ply)
            for slot, current in pairs(loadout) do
                local proposed = incoming[slot]
                if proposed and proposed.accessoryID == current.accessoryID then
                    loadout[slot] = normalizeEquipped(slot, proposed) or current
                end
            end
            local _, characterKey = C.GetLoadout(ply)
            for _, equipped in pairs(loadout) do C.Profiles[characterKey][equipped.accessoryID] = table.Copy(equipped) end
            saveLoadouts(); C.SyncPlayer(ply); closeEditor(ply)
            sendAck(ply, true, op, "Все изменения сохранены")
            return
        end
        local slot = net.ReadString()
        if not C.Slots[slot] then sendAck(ply, false, op, "Неизвестный слот") return end
        local loadout = C.GetLoadout(ply)
        if op == "unequip" then
            local ok, reason = C.UnequipSlot(ply, slot)
            if not ok and GRM.Notify then GRM.Notify(ply, tostring(reason), 255, 120, 90) end
            sendAck(ply, ok, op, ok and "Аксессуар снят в инвентарь" or tostring(reason))
        elseif op == "save_transform" then
            local current = loadout[slot]
            if not current then sendAck(ply, false, op, "Слот пуст") return end
            local incoming = net.ReadTable() or {}
            incoming.accessoryID = current.accessoryID
            local normalized = normalizeEquipped(slot, incoming)
            if not normalized then sendAck(ply, false, op, "Положение отклонено сервером") return end
            loadout[slot] = normalized
            local _, characterKey = C.GetLoadout(ply)
            C.Profiles[characterKey][normalized.accessoryID] = table.Copy(normalized)
            saveLoadouts(); C.SyncPlayer(ply)
            sendAck(ply, true, op, "Положение аксессуара сохранено")
        end
    end)

    hook.Add("StartCommand", "GRM_Customization_Freeze", function(ply, cmd)
        if not ply:GetNWBool("GRM_CustomEditing", false) then return end
        if CurTime() > (ply.GRM_CustomEditingUntil or 0) or not ply:Alive() then closeEditor(ply) return end
        cmd:ClearMovement(); cmd:ClearButtons()
    end)
    hook.Add("PlayerDeath", "GRM_Customization_CloseOnDeath", closeEditor)
    hook.Add("PlayerDisconnected", "GRM_Customization_SaveLeave", function(ply) closeEditor(ply); saveLoadouts() end)
    hook.Add("GRM_CharacterChanged", "GRM_Customization_CharacterChanged", function(ply)
        timer.Simple(0, function() if IsValid(ply) then C.SyncPlayer(ply) end end)
    end)
    hook.Add("PlayerInitialSpawn", "GRM_Customization_Join", function(ply)
        timer.Simple(3, function()
            if IsValid(ply) then
                C.SyncAllTo(ply); C.SyncPlayer(ply)
                -- Находка 179z: запоминание функциональных эффектов надетых
                -- аксессуаров. OnEquip раньше вызывался только в момент
                -- надевания — после рестарта NWBool-флаги (artificial_eye /
                -- night_vision / neuro_link / prosthesis) терялись, и
                -- аксессуар «не запоминался» до пере-надевания. Восстанавливаем
                -- эффекты для всего надетого при входе.
                local loadout = C.GetLoadout(ply)
                for slot, equipped in pairs(loadout) do
                    local item = C.Catalog[equipped.accessoryID]
                    if item then dispatchFunctionEvent("OnEquip", ply, slot, item, equipped) end
                end
            end
        end)
    end)
    -- Находка 179z: фонарик (F) ВЫРУБЛЕН глобально. При включённом
    -- освещении движок уводит рендер в отдельный световой проход, где
    -- аксессуары перестают отрисовываться. AllowFlashlight=false — движок
    -- не даёт включить фонарик никому.
    hook.Add("AllowFlashlight", "GRM_Customization_NoFlashlight", function()
        return false
    end)
    hook.Add("ShutDown", "GRM_Customization_Save", function() saveCatalog(); saveLoadouts() end)

    -- Встроенные функциональные аксессуары. Никакой код из каталога не
    -- исполняется: админ включает только заранее зарегистрированные флаги.
    local gasDamageMask = bit.bor(DMG_NERVEGAS or 0, DMG_POISON or 0, DMG_ACID or 0, DMG_RADIATION or 0)
    local armorDamageMask = bit.bor(DMG_BULLET or 0, DMG_BLAST or 0, DMG_SLASH or 0, DMG_CLUB or 0)
    hook.Add("EntityTakeDamage", "GRM_Customization_FunctionalProtection", function(target, dmg)
        if not IsValid(target) or not target:IsPlayer() or not dmg then return end
        local original = math.max(0, dmg:GetDamage())
        local multiplier = 1
        local gasProtected = gasDamageMask ~= 0 and dmg:IsDamageType(gasDamageMask) and C.HasFunction(target, "gasmask")
        if gasProtected then
            multiplier = multiplier * (1 - C.GetFunctionValue(target, "gasmask", "gasProtection", "max"))
        end
        local armored = armorDamageMask ~= 0 and dmg:IsDamageType(armorDamageMask) and C.HasFunction(target, "armor")
        if armored then
            multiplier = multiplier * (1 - C.GetFunctionValue(target, "armor", "armorReduction", "max"))
        end
        multiplier = math.Clamp(multiplier, 0.02, 1)
        if multiplier < 1 then
            dmg:SetDamage(original * multiplier)
            hook.Run("GRM_AccessoryDamageModified", target, dmg, original, multiplier, gasProtected, armored)
            if gasProtected and CurTime() >= (target.GRM_GasMaskNextNotice or 0) then
                target.GRM_GasMaskNextNotice = CurTime() + 4
                if GRM.Notify then GRM.Notify(target, "Противогаз защитил от опасной среды", 110, 220, 150) end
            end
        end
    end)

    local function runRemoveCommand(ply, argument)
        if not IsValid(ply) then return end
        argument = string.lower(string.Trim(tostring(argument or "all")))
        local aliases = {
            all = "all", ["все"] = "all", head = "head", ["голова"] = "head",
            face = "face", ["лицо"] = "face", torso = "torso", ["туловище"] = "torso",
            legs = "legs", ["ноги"] = "legs", left_hand = "left_hand", ["левая"] = "left_hand",
            right_hand = "right_hand", ["правая"] = "right_hand",
        }
        local slot = aliases[argument]
        if not slot then
            if GRM.Notify then GRM.Notify(ply, "Слоты: head, face, torso, legs, left_hand, right_hand, all", 255, 170, 80) end
            return
        end
        if slot == "all" then
            local removed, errors = C.UnequipAll(ply)
            local suffix = #errors > 0 and (" Не снято: " .. table.concat(errors, "; ")) or ""
            if GRM.Notify then GRM.Notify(ply, "Снято аксессуаров: " .. removed .. "." .. suffix, removed > 0 and 100 or 255, removed > 0 and 220 or 170, 120) end
        else
            local ok, reason = C.UnequipSlot(ply, slot)
            if not ok and GRM.Notify then GRM.Notify(ply, tostring(reason), 255, 150, 90) end
        end
    end

    concommand.Add("grm_accessories_off", function(ply, _, args) runRemoveCommand(ply, args[1] or "all") end)
    concommand.Add("grm_accessory_remove", function(ply, _, args) runRemoveCommand(ply, args[1] or "all") end)
    hook.Add("PlayerSayTransform", "GRM_Customization_RemoveCommand", function(ply, pack)
        if not istable(pack) or not isstring(pack[1]) then return end
        local text = string.Trim(pack[1])
        local command, argument = string.match(text, "^(%S+)%s*(.-)$")
        command = string.lower(command or "")
        if command ~= "/accessories_off" and command ~= "!accessories_off"
            and command ~= "/acc_remove" and command ~= "!acc_remove"
            and command ~= "/снятьаксессуары" and command ~= "!снятьаксессуары" then return end
        runRemoveCommand(ply, argument ~= "" and argument or "all")
        pack[1] = ""; pack.SkipPlayerSay = true
    end)

    local function adminOpen(ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        net.Start("GRM_Custom_AdminOpen") net.WriteTable(C.Catalog) net.Send(ply)
    end
    concommand.Add("grm_accessories_admin", adminOpen)
    hook.Add("PlayerSayTransform", "GRM_Customization_AdminCommand", function(ply, pack)
        if not istable(pack) or not isstring(pack[1]) then return end
        local cmd = string.lower(string.Trim(pack[1]))
        if cmd ~= "/grm_accessories_admin" and cmd ~= "!grm_accessories_admin" then return end
        adminOpen(ply); pack[1] = ""; pack.SkipPlayerSay = true
    end)

    net.Receive("GRM_Custom_AdminOp", function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() or not rateOK(ply) then return end
        local op = net.ReadString()
        local id = cleanID(net.ReadString())
        if op == "save" then
            local incoming = net.ReadTable() or {}
            incoming.id = id
            local item = normalizeCatalogItem(id, incoming)
            if not item or not util.IsValidModel(item.model) then
                if GRM.Notify then GRM.Notify(ply, "Некорректная модель или ID аксессуара.", 255, 100, 100) end
                sendAck(ply, false, "admin_save", "Некорректная модель или ID аксессуара")
                return
            end
            C.Catalog[id] = item
        elseif op == "delete" then
            local old = C.Catalog[id]
            if old then
                C.Catalog[id] = nil
                for key, loadout in pairs(C.Loadouts) do
                    for slot, equipped in pairs(loadout) do
                        if equipped.accessoryID == id then loadout[slot] = nil end
                    end
                    if C.Profiles[key] then C.Profiles[key][id] = nil end
                end
            end
        else return end
        saveCatalog(); saveLoadouts(); registerIntegrations()
        for _, target in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do C.SendCatalog(target); C.SyncPlayer(target) end
        sendAck(ply, true, op == "delete" and "admin_delete" or "admin_save", op == "delete" and "Аксессуар удалён из каталога" or "Аксессуар сохранён в каталоге")
        adminOpen(ply)
    end)

    -- ── СУМКА ОГРАБЛЕНИЯ (находка 178f) ─────────────────────
    -- Деньги с паллет собираются ПОЭТАПНО: за один подход в сумку
    -- уходит perUse (по умолчанию 25.000), максимум maxMoney (100.000).
    -- Выгрузка: /bag_unload (деньги в кошелёк).
    C.LootBagDefaults = { maxMoney = 100000, perUse = 25000 }
    local function lootBagCfg(ply, key)
        local v = math.floor(tonumber(C.GetFunctionValue(ply, "loot_bag", key, "max")) or 0)
        if v <= 0 then v = C.LootBagDefaults[key] or 0 end
        return v
    end
    function C.LootBagMax(ply) return lootBagCfg(ply, "maxMoney") end
    function C.LootBagPerUse(ply) return lootBagCfg(ply, "perUse") end
    function C.LootBagGet(ply)
        if not IsValid(ply) then return 0 end
        return math.max(0, math.floor(tonumber(ply._grmLootBag) or 0))
    end
    function C.LootBagSet(ply, amount)
        if not IsValid(ply) then return 0 end
        amount = math.max(0, math.floor(tonumber(amount) or 0))
        ply._grmLootBag = amount
        ply:SetNWInt("GRM_LootBag", amount)
        return amount
    end
    -- Попытка положить amt в сумку. Возвращает: сколько реально взято
    -- (0 = сумка полна/нет сумки).
    function C.LootBagAdd(ply, amt)
        if not IsValid(ply) then return 0 end
        if not C.HasFunction(ply, "loot_bag") then return 0 end
        amt = math.max(0, math.floor(tonumber(amt) or 0))
        if amt <= 0 then return 0 end
        local maxMoney = C.LootBagMax(ply)
        local cur = C.LootBagGet(ply)
        if cur >= maxMoney then return 0 end
        local perUse = math.max(1, C.LootBagPerUse(ply))
        local take = math.min(amt, perUse, maxMoney - cur)
        if take <= 0 then return 0 end
        C.LootBagSet(ply, cur + take)
        return take
    end
    -- Находка 179e: выгрузка сумки НЕ в кошелёк, а на землю (пачками/
    -- паллетами) ЛИБО ближайшему отмывщику денег (если рядом и идёт ивент).
    function C.LootBagUnload(ply)
        if not IsValid(ply) then return 0, "Нет игрока" end
        local cur = C.LootBagGet(ply)
        if cur <= 0 then return 0, "Сумка пуста" end

        -- 1) отмывщик денег рядом (радиус 400) и ивент активен → сдать ему
        local launderer = nil
        if GRM.Economy and GRM.Economy.FindNearestLaunderer then
            launderer = GRM.Economy.FindNearestLaunderer(ply, 400)
        end
        if IsValid(launderer) and launderer.GetEventActive and launderer:GetEventActive() and launderer.DepositFromBag then
            local deposited = launderer:DepositFromBag(ply)
            if deposited > 0 then
                C.LootBagSet(ply, math.max(0, C.LootBagGet(ply) - deposited))
                hook.Run("GRM_LootBagUnloaded", ply, deposited)
                return deposited
            end
        end

        -- 2) иначе — на землю перед игроком (паллеты ≥50к / пачка money.mdl)
        if GRM.Economy and GRM.Economy.SpawnCashAt then
            local pos = ply:GetPos() + ply:GetForward() * 60 + Vector(0, 0, 10)
            local spawned = GRM.Economy.SpawnCashAt(pos, cur, nil)
            C.LootBagSet(ply, math.max(0, C.LootBagGet(ply) - spawned))
            if GRM.Notify then
                GRM.Notify(ply, "Выгружено на землю: " .. (GRM.Format and GRM.Format(spawned) or tostring(spawned)) .. " (E — подобрать)", 100, 220, 130)
            end
            hook.Run("GRM_LootBagUnloaded", ply, spawned)
            return spawned
        end

        -- 3) фолбэк (нет экономики) — в кошелёк
        if not (GRM and GRM.GiveMoney) then return 0, "Модуль валюты не загружен" end
        C.LootBagSet(ply, 0)
        GRM.GiveMoney(ply, cur, "Сумка ограбления: выгрузка")
        if GRM.Notify then GRM.Notify(ply, "Из сумки в кошелёк: " .. (GRM.Format and GRM.Format(cur) or tostring(cur)), 100, 220, 130) end
        hook.Run("GRM_LootBagUnloaded", ply, cur)
        return cur
    end

    concommand.Add("grm_bag_unload", function(ply)
        if not IsValid(ply) then return end
        local _, err = C.LootBagUnload(ply)
        if err ~= nil and err ~= "" and GRM.Notify then
            GRM.Notify(ply, err, 255, 190, 90)
        end
    end)

    -- Находка 179e: /bag_unload в чате (EasyChat перехватывает PlayerSay)
    local function bagUnloadChat(ply, datapack)
        if not istable(datapack) then return end
        local text = datapack[1]
        if not isstring(text) then return end
        if string.lower(string.Trim(text)) ~= "/bag_unload" then return end
        if not IsValid(ply) then return end
        local _, err = C.LootBagUnload(ply)
        if err ~= nil and err ~= "" and GRM.Notify then
            GRM.Notify(ply, err, 255, 190, 90)
        end
        datapack.SkipPlayerSay = true
        datapack[1] = ""
    end
    hook.Add("PlayerSayTransform", "GRM_LootBag_UnloadTransform", bagUnloadChat)
    hook.Add("PlayerSay", "GRM_LootBag_UnloadSay", function(ply, text)
        if not isstring(text) then return end
        if string.lower(string.Trim(text)) ~= "/bag_unload" then return end
        if IsValid(ply) then
            local _, err = C.LootBagUnload(ply)
            if err ~= nil and err ~= "" and GRM.Notify then
                GRM.Notify(ply, err, 255, 190, 90)
            end
        end
        return ""
    end)

    -- Сумка снимается — деньги остаются в сумке (персонально), но
    -- подсказку не показываем: NWInt сбрасывается на клиенте автоматически.
    C.FunctionTypes.loot_bag.OnUnequip = function(ply)
        if IsValid(ply) then ply:SetNWInt("GRM_LootBag", math.max(0, math.floor(tonumber(ply._grmLootBag) or 0))) end
    end

    print("[GRM Customization] server v" .. C.Version .. " loaded")
else
    -- Клиентская часть находится в autorun/client/cl_grm_customization.lua.
end
