-- Boot-шим: старт подсистемы идёт через планировщик GRM.Boot (приоритеты и
-- бюджет на тик). Если планировщик почему-то не загружен, работаем по-старому.
local function grmBootStart(id, tier, fn)
    if GRM and GRM.Boot and GRM.Boot.OnMapStart then return GRM.Boot.OnMapStart(id, tier, fn) end
    return hook.Add("InitPostEntity", id, fn)
end

--[[
    GRM Augmentation Chips System
    Система программируемых чипов для аугментаций
]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.AugChips = GRM.AugChips or {}
local CHIPS = GRM.AugChips

-- Конфигурация
CHIPS.Config = {
    MaxChipsPerPlayer = 10,           -- Максимум чипов на игрока
    ImplantSuccessRate = 0.85,       -- Шанс успешной имплантации (85%)
    RejectionChance = 0.10,          -- Шанс отторжения (10%)
    ComplicationChance = 0.05,       -- Шанс осложнений (5%)

    -- Модификаторы чипов
    Modifiers = {
        speed = {
            name = "Скорость",
            description = "Увеличение скорости передвижения",
            minValue = 1.0,
            maxValue = 2.0,
            defaultValue = 1.0,
            unit = "x"
        },
        stamina = {
            name = "Выносливость",
            description = "Увеличение выносливости и времени бега",
            minValue = 1.0,
            maxValue = 3.0,
            defaultValue = 1.0,
            unit = "x"
        },
        carryWeight = {
            name = "Грузоподъемность",
            description = "Увеличение максимального веса инвентаря",
            minValue = 0,
            maxValue = 100,
            defaultValue = 0,
            unit = "kg"
        },
        health = {
            name = "Здоровье",
            description = "Увеличение максимального здоровья",
            minValue = 0,
            maxValue = 500,
            defaultValue = 0,
            unit = "HP"
        },
        armor = {
            name = "Броня",
            description = "Увеличение максимальной брони",
            minValue = 0,
            maxValue = 200,
            defaultValue = 0,
            unit = "AP"
        },
        doorHack = {name="Взлом дверей", description="Временно открывает запертую дверь на 60 секунд", options={"disabled","enabled"}, defaultValue="disabled"},
        vision = {
            name = "Зрение",
            description = "Тип визуального эффекта",
            options = {"normal", "infrared", "nightvision", "zoom", "xray"},
            defaultValue = "normal"
        }
    },

    -- Типы чипов по категориям
    ChipCategories = {
        civilian = {
            name = "Гражданские",
            maxLevel = 2,
            color = Color(50, 200, 100),
            allowed = {"speed", "stamina", "carryWeight", "health"}
        },
        service = {
            name = "Служебные",
            maxLevel = 3,
            color = Color(0, 150, 255),
            allowed = {"speed", "stamina", "carryWeight", "health", "armor", "vision"}
        },
        military = {
            name = "Военные",
            maxLevel = 5,
            color = Color(255, 180, 50),
            allowed = {"speed", "stamina", "carryWeight", "health", "armor", "vision"}
        },
        experimental = {
            name = "Экспериментальные",
            maxLevel = 10,
            color = Color(255, 80, 80),
            allowed = {"speed", "stamina", "carryWeight", "health", "armor", "vision", "doorHack"}
        }
    }
}

-- Хранилище чипов
CHIPS.PlayerChips = CHIPS.PlayerChips or {}
CHIPS.ChipDatabase = CHIPS.ChipDatabase or {}

-- Есть ли у игрока активный экспериментальный чип со взломом дверей
-- (единая проверка для сервера и клиента: enabled / true / "включен" / DOOR в имени)
function CHIPS.HasDoorHack(ply)
    if not IsValid(ply) then return nil end
    local list=CHIPS.GetPlayerChips(ply)
    for _,c in ipairs(list) do
        local m=c.modifiers or {}
        if c.implanted and c.active ~= false and c.category=="experimental" and
            (m.doorHack=="enabled" or m.doorHack==true or m.doorHack=="включен" or
             string.find(string.upper(c.name or ""),"DOOR")) then
            return c
        end
    end
    return nil
end

-- Получение чипов игрока
function CHIPS.GetPlayerChips(ply)
    if not IsValid(ply) then return {} end
    local charKey = GRM.Identity and GRM.Identity.CharacterKey(ply) or ply:SteamID64()
    CHIPS.PlayerChips[charKey] = CHIPS.PlayerChips[charKey] or {}
    local list=CHIPS.PlayerChips[charKey]; local seen={}; local clean={}
    for _,chip in ipairs(list) do if chip and chip.id and not seen[chip.id] then seen[chip.id]=true; clean[#clean+1]=chip end end
    CHIPS.PlayerChips[charKey]=clean
    return clean
end

-- Создание нового чипа
function CHIPS.CreateChip(ply, chipData)
    if not IsValid(ply) then return false, "Недействительный игрок" end

    local playerChips = CHIPS.GetPlayerChips(ply)
    local storedCount = 0
    for _, stored in ipairs(playerChips) do
        if not stored.implanted then storedCount = storedCount + 1 end
    end
    if storedCount >= CHIPS.Config.MaxChipsPerPlayer then
        return false, "Достигнут максимум неимплантированных чипов (" .. CHIPS.Config.MaxChipsPerPlayer .. "). Удалите старые чипы в программаторе."
    end

    -- Валидация данных чипа
    chipData.category = tostring(chipData.category or "civilian"):lower()
    if not CHIPS.Config.ChipCategories[chipData.category] then
        return false, "Неверная категория чипа"
    end

    if not chipData.name or chipData.name == "" then
        return false, "Не указано название чипа"
    end

    local category = CHIPS.Config.ChipCategories[chipData.category]

    -- Проверка модификаторов
    local modifiers = {}
    for modKey, modValue in pairs(chipData.modifiers or {}) do
        local modConfig = CHIPS.Config.Modifiers[modKey]
        if modConfig and table.HasValue(category.allowed, modKey) then
            if modConfig.options then
                local aliases={ ["обычное"]="normal",["инфракрасное"]="infrared",["ночное"]="nightvision",["увеличение"]="zoom",["рентген"]="xray",["отключен"]="disabled",["включен"]="enabled" }
                modValue=aliases[modValue] or modValue
                -- Опциональный модификатор (например, vision)
                if table.HasValue(modConfig.options, modValue) then
                    modifiers[modKey] = modValue
                end
            else
                -- Числовой модификатор
                local numValue = tonumber(modValue)
                if numValue then
                    numValue = math.Clamp(numValue, modConfig.minValue, modConfig.maxValue * (category.maxLevel / 5))
                    modifiers[modKey] = numValue
                end
            end
        end
    end

    -- Создание чипа
    local chip = {
        id = "chip_" .. os.time() .. "_" .. math.random(1000, 9999),
        name = chipData.name,
        category = chipData.category,
        level = math.Clamp(tonumber(chipData.level) or 1, 1, category.maxLevel),
        modifiers = modifiers,
        implanted = false,
        active = false,
        created = os.time(),
        creator = GRM.Identity and GRM.Identity.CharacterKey(ply) or ply:SteamID64()
    }

    table.insert(playerChips, chip)
    CHIPS.SaveData()

    return true, chip
end

-- Удаление чипа
function CHIPS.RemoveChip(ply, chipId)
    if not IsValid(ply) then return false end

    local playerChips = CHIPS.GetPlayerChips(ply)
    for i, chip in ipairs(playerChips) do
        if chip.id == chipId then
            if chip.implanted then
                -- Снятие эффектов перед удалением
                CHIPS.RemoveChipEffects(ply, chip)
            end
            table.remove(playerChips, i)
            CHIPS.SaveData()
            return true
        end
    end

    return false
end

-- Имплантация чипа
function CHIPS.ImplantChip(ply, chipId)
    if not IsValid(ply) then return false, "Недействительный игрок" end

    local playerChips = CHIPS.GetPlayerChips(ply)
    local chip = nil

    for _, c in ipairs(playerChips) do
        if c.id == chipId then
            chip = c
            break
        end
    end

    if not chip then return false, "Чип не найден" end
    if chip.implanted then return false, "Чип уже имплантирован" end

    -- Подсчет имплантированных чипов
    local implantedCount = 0
    for _, c in ipairs(playerChips) do
        if c.implanted then implantedCount = implantedCount + 1 end
    end

    if implantedCount >= CHIPS.Config.MaxChipsPerPlayer then
        return false, "Достигнут максимум имплантированных чипов"
    end

    -- Бросок на успех имплантации
    local roll = math.random()

    if roll <= CHIPS.Config.ImplantSuccessRate then
        -- Успех
        chip.implanted = true
        chip.active = true
        chip.implantTime = os.time()
        CHIPS.ApplyChipEffects(ply, chip)
        CHIPS.SaveData(); CHIPS.SyncChips(ply)
        return true, "Имплантация успешна"

    elseif roll <= CHIPS.Config.ImplantSuccessRate + CHIPS.Config.RejectionChance then
        -- Отторжение
        CHIPS.RemoveChip(ply, chipId)
        ply:TakeDamage(math.random(20, 40))
        ply:EmitSound("buttons/button10.wav", 72, 85, 1, CHAN_AUTO)
        net.Start("GRM_AugChip_Rejection"); net.Send(ply)
        return false, "Отторжение чипа! Вы получили урон."

    else
        -- Осложнения
        chip.implanted = true
        chip.active = true
        chip.implantTime = os.time()
        chip.hasComplications = true
        CHIPS.ApplyChipEffects(ply, chip)
        CHIPS.SaveData()
        ply:TakeDamage(math.random(10, 25))
        return true, "Имплантация с осложнениями! Чип работает, но вы получили урон."
    end
end

-- Применение эффектов чипа
function CHIPS.ApplyChipEffects(ply, chip)
    if not IsValid(ply) or not chip or not chip.implanted then return end

    for modKey, modValue in pairs(chip.modifiers or {}) do
        if modKey == "speed" then
            local baseSpeed = 200
            local baseRunSpeed = 400
            ply:SetWalkSpeed(baseSpeed * modValue)
            ply:SetRunSpeed(baseRunSpeed * modValue)

        elseif modKey == "health" then
            local baseMax = (GRM.Augmentations and GRM.Augmentations.Config.DefaultHealth) or 100
            local targetMax = math.min(baseMax + modValue, (GRM.Augmentations and GRM.Augmentations.Config.MaxHealth) or 1000)
            ply:SetMaxHealth(targetMax)
            ply:SetHealth(math.max(ply:Health(), targetMax))

        elseif modKey == "armor" then
            local currentArmor = ply:Armor()
            ply:SetArmor(math.min(currentArmor + modValue, 255))

        elseif modKey == "carryWeight" then
            -- Интеграция с системой инвентаря (если есть)
            if GRM.Inventory and GRM.Inventory.SetBonusWeight then
                GRM.Inventory.SetBonusWeight(ply, modValue)
            end
            ply:SetNWInt("GRM_ChipCarryWeight", modValue)

        elseif modKey == "stamina" then
            -- Интеграция с системой выносливости (если есть)
            if GRM.Stamina and GRM.Stamina.SetMultiplier then
                GRM.Stamina.SetMultiplier(ply, modValue)
            end
            ply:SetNWFloat("GRM_ChipStamina", modValue)

        elseif modKey == "vision" then
            -- Интеграция с системой зрения
            if SERVER then
                net.Start("GRM_Augmentation_Update")
                net.WriteString(modValue) -- infrared, nightvision, etc.
                net.WriteBool(true)
                net.Send(ply)
            end
        end
    end

    if SERVER then
        ply:EmitSound("ambient/machines/combine_terminal_idle4.wav", 72, 118, 1, CHAN_AUTO)
        net.Start("GRM_AugChip_Activated")
        net.WriteString(chip.name or "Чип")
        net.WriteTable(chip.modifiers or {})
        net.Send(ply)
    end

    if GRM.AugmentationIntegrations and GRM.AugmentationIntegrations.Apply then GRM.AugmentationIntegrations.Apply(ply, chip) end

    -- Уведомление
    if SERVER and not chip._restored then
        ply:ChatPrint("[Аугментации] Эффекты чипа '" .. chip.name .. "' активированы")
    end
end

-- Снятие эффектов чипа
function CHIPS.RemoveChipEffects(ply, chip)
    if not IsValid(ply) or not chip then return end

    for modKey, modValue in pairs(chip.modifiers or {}) do
        if modKey == "speed" then
            ply:SetWalkSpeed((GRM.Movement and GRM.Movement.Config.WalkSpeed) or 160)
            ply:SetRunSpeed((GRM.Movement and GRM.Movement.Config.RunSpeed) or 220)

        elseif modKey == "health" then
            local currentMax = ply:GetMaxHealth()
            ply:SetMaxHealth(currentMax - modValue)
            ply:SetHealth(math.min(ply:Health(), ply:GetMaxHealth()))

        elseif modKey == "armor" then
            local currentArmor = ply:Armor()
            ply:SetArmor(math.max(0, currentArmor - modValue))

        elseif modKey == "carryWeight" then
            if GRM.Inventory and GRM.Inventory.SetBonusWeight then
                GRM.Inventory.SetBonusWeight(ply, 0)
            end
            ply:SetNWInt("GRM_ChipCarryWeight", 0)

        elseif modKey == "stamina" then
            if GRM.Stamina and GRM.Stamina.SetMultiplier then
                GRM.Stamina.SetMultiplier(ply, 1.0)
            end
            ply:SetNWFloat("GRM_ChipStamina", 1.0)

        elseif modKey == "vision" then
            if SERVER then
                net.Start("GRM_Augmentation_Update")
                net.WriteString(modValue)
                net.WriteBool(false)
                net.Send(ply)
            end
        end
    end
    if GRM.AugmentationIntegrations and GRM.AugmentationIntegrations.Remove then GRM.AugmentationIntegrations.Remove(ply, chip) end
end

function CHIPS.RecomputeEffects(ply)
    if not IsValid(ply) then return end
    local baseHealth=(GRM.Augmentations and GRM.Augmentations.Config.DefaultHealth) or 100
    local baseArmor=(GRM.Augmentations and GRM.Augmentations.Config.DefaultArmor) or 0
    local walk=(GRM.Movement and GRM.Movement.Config.WalkSpeed) or 160
    local run=(GRM.Movement and GRM.Movement.Config.RunSpeed) or 220
    local healthBonus, armorBonus, weight, speed, stamina = 0,0,0,1,1
    local vision=nil
    for _,chip in ipairs(CHIPS.GetPlayerChips(ply)) do
        if chip.implanted and chip.active ~= false then
            for key,val in pairs(chip.modifiers or {}) do
                if key=="health" then healthBonus=healthBonus+(tonumber(val) or 0)
                elseif key=="armor" then armorBonus=armorBonus+(tonumber(val) or 0)
                elseif key=="carryWeight" then weight=math.max(weight,tonumber(val) or 0)
                elseif key=="speed" then speed=speed*(tonumber(val) or 1)
                elseif key=="stamina" then stamina=math.max(stamina,tonumber(val) or 1)
                elseif key=="vision" then vision=val end
            end
        end
    end
    local maxHealth=math.min(baseHealth+healthBonus,(GRM.Augmentations and GRM.Augmentations.Config.MaxHealth) or 1000)
    ply:SetMaxHealth(maxHealth); ply:SetHealth(math.min(ply:Health(),maxHealth)); ply:SetArmor(math.min(baseArmor+armorBonus,255)); ply:SetWalkSpeed(walk*speed); ply:SetRunSpeed(run*speed)
    ply:SetNWInt("GRM_ChipCarryWeight",weight); ply:SetNWFloat("GRM_ChipStamina",stamina)
    if vision and SERVER then net.Start("GRM_Augmentation_Update"); net.WriteString(vision); net.WriteBool(true); net.Send(ply) end
end

-- Извлечение чипа
function CHIPS.ExtractChip(ply, chipId)
    if not IsValid(ply) then return false, "Недействительный игрок" end

    local playerChips = CHIPS.GetPlayerChips(ply)
    local chip = nil

    for _, c in ipairs(playerChips) do
        if c.id == chipId then
            chip = c
            break
        end
    end

    if not chip then return false, "Чип не найден" end
    if not chip.implanted then return false, "Чип не имплантирован" end

    -- Снятие эффектов
    CHIPS.RemoveChipEffects(ply, chip)
    local returned = false
    if GRM.Inventory and GRM.Inventory.AddItem then
        local remaining = GRM.Inventory.AddItem(ply, "augmentation_chip", 1, {chipId=chip.id, chipName=chip.name, chipCategory=chip.category, chipLevel=chip.level, chipModifiers=chip.modifiers})
        returned = tonumber(remaining or 0) <= 0
    end
    if not returned then return false, "Инвентарь заполнен: чип не снят" end
    CHIPS.RemoveChipEffects(ply, chip)
    chip.implanted = false
    chip.active = false
    chip.implantTime = nil
    chip.hasComplications = nil

    CHIPS.SaveData()

    if SERVER then
        ply:ChatPrint("[Аугментации] Чип '" .. chip.name .. "' извлечен")
    end

    return true, "Чип извлечен"
end

-- Открытие меню имплантации для чипа из инвентаря
if SERVER then
    function CHIPS.OpenImplantMenu(ply, chipData)
        if not IsValid(ply) or not chipData then return end

        -- Отправка данных чипа клиенту для открытия меню
        net.Start("GRM_AugChip_ImplantMenu")
        net.WriteTable(chipData)
        net.Send(ply)
    end
end

-- Сохранение данных
function CHIPS.SaveData()
    if not SERVER then return end

    file.CreateDir("grm_augmentations")
    file.Write("grm_augmentations/chips.txt", util.TableToJSON(CHIPS.PlayerChips, true))
end

-- Загрузка данных
function CHIPS.LoadData()
    if not SERVER then return end

    if not file.Exists("grm_augmentations/chips.txt", "DATA") then return end

    local raw = file.Read("grm_augmentations/chips.txt", "DATA")
    local ok, data = pcall(util.JSONToTable, raw, false, true)
    if not ok then data = nil end
    if data then
        -- Удаляем дубликаты записей, появившиеся при старых тестах/повторной имплантации.
        for key, list in pairs(data) do
            if istable(list) then
                local seen, clean = {}, {}
                for _, chip in ipairs(list) do
                    local id = chip.id or (chip.name .. ":" .. tostring(chip.created or #clean))
                    if not seen[id] then
                        chip.implanted = chip.implanted == true
                        chip.active = chip.implanted and chip.active ~= false or false
                        clean[#clean + 1] = chip
                    end
                end
                data[key] = clean
            end
        end
        CHIPS.PlayerChips = data
    end
end

-- Восстановление эффектов при спавне
if SERVER then
    util.AddNetworkString("GRM_AugChip_Create")
    util.AddNetworkString("GRM_AugChip_Remove")
    util.AddNetworkString("GRM_AugChip_Implant")
    util.AddNetworkString("GRM_AugChip_Extract")
    util.AddNetworkString("GRM_AugChip_GetList")
    util.AddNetworkString("GRM_AugChip_SendList")
    util.AddNetworkString("GRM_AugChip_OpenProgrammer")
    util.AddNetworkString("GRM_AugStation_Open")
    util.AddNetworkString("GRM_AugStation_SpawnChip")
    util.AddNetworkString("GRM_AugChip_ImplantMenu")
    util.AddNetworkString("GRM_AugChip_ImplantFromInventory")
    util.AddNetworkString("GRM_AugChip_ImplantResult")
    util.AddNetworkString("GRM_AugChip_Activated")
    util.AddNetworkString("GRM_AugChip_Rejection")
    util.AddNetworkString("GRM_AugChip_Sync")
    util.AddNetworkString("GRM_AugChip_RequestSync")
    util.AddNetworkString("GRM_AugChip_ExtractByUI")
    util.AddNetworkString("GRM_AugChip_Reprogram")
    util.AddNetworkString("GRM_AugChip_Toggle")

    grmBootStart("GRM_AugChips_Init", "normal", function()
        CHIPS.LoadData()
    end)

    hook.Add("ShutDown", "GRM_AugChips_Save", function()
        CHIPS.SaveData()
    end)

    function CHIPS.SyncChips(ply)
        if not IsValid(ply) then return end
        net.Start("GRM_AugChip_Sync"); net.WriteTable(CHIPS.GetPlayerChips(ply)); net.Send(ply)
    end
    hook.Add("PlayerInitialSpawn", "GRM_AugChips_SyncJoin", function(ply) timer.Simple(2, function() CHIPS.SyncChips(ply) end) end)
    net.Receive("GRM_AugChip_RequestSync", function(_, ply)
        if IsValid(ply) then CHIPS.SyncChips(ply) end
    end)
    hook.Add("GRM_AugChips_SyncAfterSave", "GRM_AugChips_SyncAfterSave", function(ply) CHIPS.SyncChips(ply) end)

    hook.Add("PlayerSpawn", "GRM_AugChips_Spawn", function(ply)
        local playerChips = CHIPS.GetPlayerChips(ply)

        timer.Simple(0.2, function()
            if not IsValid(ply) then return end

            for _, chip in ipairs(playerChips) do
                if chip.implanted and chip.active ~= false then
                    chip._restored = true
                    CHIPS.ApplyChipEffects(ply, chip)
                    chip._restored = nil
                end
            end
        end)
    end)

    -- Обработка создания чипа
    net.Receive("GRM_AugChip_Create", function(len, ply)
        local chipData = net.ReadTable()
        local success, result = CHIPS.CreateChip(ply, chipData)

        net.Start("GRM_AugChip_Create")
        net.WriteBool(success)
        if success then
            net.WriteTable(result)
        else
            net.WriteString(result)
        end
        net.Send(ply)
    end)

    -- Обработка удаления чипа
    net.Receive("GRM_AugChip_Remove", function(len, ply)
        local chipId = net.ReadString()
        local success = CHIPS.RemoveChip(ply, chipId)

        net.Start("GRM_AugChip_Remove")
        net.WriteBool(success)
        net.WriteString(chipId)
        net.Send(ply)
    end)

    -- Обработка имплантации
    net.Receive("GRM_AugChip_Implant", function(len, ply)
        local chipId = net.ReadString()
        local success, message = CHIPS.ImplantChip(ply, chipId)

        net.Start("GRM_AugChip_Implant")
        net.WriteBool(success)
        net.WriteString(message)
        net.WriteString(chipId)
        net.Send(ply)
    end)

    net.Receive("GRM_AugChip_Reprogram", function(_, ply)
        if GRM.AugmentationAccess and not GRM.AugmentationAccess.Can(ply,"reprogram") then GRM.AugmentationAccess.Deny(ply); return end
        local id, modifiers = net.ReadString(), net.ReadTable() or {}
        local list = CHIPS.GetPlayerChips(ply)
        for _, chip in ipairs(list) do
            if chip.id == id and chip.implanted then
                local cat=CHIPS.Config.ChipCategories[chip.category] or {}
                local out={}
                for key,val in pairs(modifiers) do
                    local cfg=CHIPS.Config.Modifiers[key]
                    if cfg and (not cat.allowed or table.HasValue(cat.allowed,key)) then
                        if key == "vision" then local vm={ ["обычное"]="normal",["инфракрасное"]="infrared",["ночное"]="nightvision",["увеличение"]="zoom",["рентген"]="xray",["отключен"]="disabled",["включен"]="enabled" }; val=vm[val] or val end
                        if cfg.options and table.HasValue(cfg.options,val) then out[key]=val
                        elseif not cfg.options and tonumber(val) then out[key]=math.Clamp(tonumber(val),cfg.minValue,cfg.maxValue*((cat.maxLevel or 5)/5)) end
                    end
                end
                CHIPS.RemoveChipEffects(ply,chip); chip.modifiers=out; CHIPS.ApplyChipEffects(ply,chip); CHIPS.SaveData(); CHIPS.SyncChips(ply)
                ply:EmitSound("buttons/combine_button7.wav",72,105,1,CHAN_AUTO)
                GRM.Notify(ply,"Чип перепрограммирован",80,210,150); return
            end
        end
    end)

    net.Receive("GRM_AugChip_Toggle", function(_, ply)
        local id=net.ReadString(); local list=CHIPS.GetPlayerChips(ply)
        for _,chip in ipairs(list) do if chip.id==id and chip.implanted then
            if chip.active == false then chip.active=true; CHIPS.ApplyChipEffects(ply,chip) else CHIPS.RemoveChipEffects(ply,chip); chip.active=false end
            CHIPS.RecomputeEffects(ply); CHIPS.SaveData(); CHIPS.SyncChips(ply); ply:EmitSound(chip.active and "buttons/combine_button1.wav" or "buttons/combine_button2.wav",72,chip.active and 112 or 92,1,CHAN_AUTO)
            GRM.Notify(ply, chip.active and "Чип активирован" or "Чип деактивирован",80,210,150); return
        end end
    end)

    -- Снятие чипа из интерфейса Биоконтроля.
    net.Receive("GRM_AugChip_ExtractByUI", function(_, ply)
        if GRM.AugmentationAccess and not GRM.AugmentationAccess.Can(ply,"extract") then GRM.AugmentationAccess.Deny(ply); return end
        local chipId = net.ReadString()
        local ok, msg = CHIPS.ExtractChip(ply, chipId)
        if ok then CHIPS.SyncChips(ply) end
        ply:EmitSound("buttons/combine_button3.wav",72,95,1,CHAN_AUTO)
        GRM.Notify(ply, ok and "Чип снят: " .. msg or (msg or "Не удалось снять чип"), ok and 90 or 240, ok and 220 or 90, ok and 130 or 80)
    end)

    function CHIPS.RecomputeEffects(ply)
    if not IsValid(ply) then return end
    local baseHealth=(GRM.Augmentations and GRM.Augmentations.Config.DefaultHealth) or 100
    local baseArmor=(GRM.Augmentations and GRM.Augmentations.Config.DefaultArmor) or 0
    local walk=(GRM.Movement and GRM.Movement.Config.WalkSpeed) or 160
    local run=(GRM.Movement and GRM.Movement.Config.RunSpeed) or 220
    local healthBonus, armorBonus, weight, speed, stamina = 0,0,0,1,1
    local vision=nil
    for _,chip in ipairs(CHIPS.GetPlayerChips(ply)) do
        if chip.implanted and chip.active ~= false then
            for key,val in pairs(chip.modifiers or {}) do
                if key=="health" then healthBonus=healthBonus+(tonumber(val) or 0)
                elseif key=="armor" then armorBonus=armorBonus+(tonumber(val) or 0)
                elseif key=="carryWeight" then weight=math.max(weight,tonumber(val) or 0)
                elseif key=="speed" then speed=speed*(tonumber(val) or 1)
                elseif key=="stamina" then stamina=math.max(stamina,tonumber(val) or 1)
                elseif key=="vision" then vision=val end
            end
        end
    end
    local maxHealth=math.min(baseHealth+healthBonus,(GRM.Augmentations and GRM.Augmentations.Config.MaxHealth) or 1000)
    ply:SetMaxHealth(maxHealth); ply:SetHealth(math.min(ply:Health(),maxHealth)); ply:SetArmor(math.min(baseArmor+armorBonus,255)); ply:SetWalkSpeed(walk*speed); ply:SetRunSpeed(run*speed)
    ply:SetNWInt("GRM_ChipCarryWeight",weight); ply:SetNWFloat("GRM_ChipStamina",stamina)
    if vision and SERVER then net.Start("GRM_Augmentation_Update"); net.WriteString(vision); net.WriteBool(true); net.Send(ply) end
end

-- Извлечение чипа
    net.Receive("GRM_AugChip_Extract", function(len, ply)
        local chipId = net.ReadString()
        local success, message = CHIPS.ExtractChip(ply, chipId)

        net.Start("GRM_AugChip_Extract")
        net.WriteBool(success)
        net.WriteString(message)
        net.WriteString(chipId)
        net.Send(ply)
    end)

    -- Получение списка чипов
    net.Receive("GRM_AugChip_GetList", function(len, ply)
        local playerChips = CHIPS.GetPlayerChips(ply)

        net.Start("GRM_AugChip_SendList")
        net.WriteTable(playerChips)
        net.WriteTable(CHIPS.Config)
        net.Send(ply)
    end)

    -- Открытие станции
    net.Receive("GRM_AugStation_Open", function(len, ply)
        local station = net.ReadEntity()
        if not IsValid(station) or station:GetClass() ~= "grm_augmentation_station" then return end
        if ply:GetPos():DistToSqr(station:GetPos()) > (180 * 180) then return end
        if GRM.AugmentationAccess and not GRM.AugmentationAccess.Can(ply, "create", station) then GRM.AugmentationAccess.Deny(ply); return end

        -- Отправка данных для открытия меню станции
        net.Start("GRM_AugStation_Open")
        net.WriteEntity(station)
        net.WriteTable(CHIPS.Config)
        net.Send(ply)
    end)

    -- Создание физического чипа
    net.Receive("GRM_AugStation_SpawnChip", function(len, ply)
        if GRM.AugmentationAccess and not GRM.AugmentationAccess.Can(ply,"create") then GRM.AugmentationAccess.Deny(ply); return end
        local chipData = net.ReadTable()

        -- Создание чипа в базе данных
        local success, result = CHIPS.CreateChip(ply, chipData)
        if not success then
            ply:ChatPrint("[Аугментации] Ошибка создания чипа: " .. result)
            return
        end

        -- Создание физической модели чипа
        local chip = ents.Create("grm_augmentation_chip")
        if IsValid(chip) then
            chip:SetPos(ply:GetPos() + ply:GetForward() * 50 + Vector(0, 0, 10))
            chip:SetAngles(Angle(0, ply:EyeAngles().y, 0))
            chip:SetChipID(result.id)
            chip:SetChipName(result.name)
            chip:SetChipCategory(result.category)
            chip:SetChipLevel(result.level)
            chip:Spawn()

            -- Сохранение в базе данных чипов
            CHIPS.ChipDatabase[result.id] = result

            ply:ChatPrint("[Аугментации] Чип создан: " .. result.name)
            ply:ChatPrint("[Аугментации] Подберите чип чтобы добавить его в инвентарь")
        end
    end)

    -- Имплантация чипа из инвентаря
    net.Receive("GRM_AugChip_ImplantFromInventory", function(len, ply)
        if GRM.AugmentationAccess and not GRM.AugmentationAccess.Can(ply,"implant") then GRM.AugmentationAccess.Deny(ply); return end
        local chipData = net.ReadTable()
        local slotIdx = net.ReadUInt(8)

        if not IsValid(ply) or not chipData then return end

        -- Проверка лимита имплантированных чипов
        local playerChips = CHIPS.GetPlayerChips(ply)
        local implantedCount = 0
        for _, chip in ipairs(playerChips) do
            if chip.implanted then implantedCount = implantedCount + 1 end
        end

        if implantedCount >= CHIPS.Config.MaxChipsPerPlayer then
            ply:ChatPrint("[Аугментации] Достигнут максимум имплантированных чипов!")
            return
        end

        -- Имплантация чипа
        local newChip = {
            id = chipData.chipId or ("chip_" .. os.time() .. "_" .. math.random(1000, 9999)),
            name = chipData.chipName or "Неизвестный чип",
            category = chipData.chipCategory or "civilian",
            level = chipData.chipLevel or 1,
            modifiers = chipData.chipModifiers or {},
            implanted = false,
            created = os.time(),
            creator = GRM.Identity and GRM.Identity.CharacterKey(ply) or ply:SteamID64()
        }

        -- Бросок на успех имплантации
        local roll = math.random()
        local success, message

        if roll <= CHIPS.Config.ImplantSuccessRate then
            -- Успех
            newChip.implanted = true
            newChip.active = true
            newChip.implantTime = os.time()
            CHIPS.ApplyChipEffects(ply, newChip)
            table.insert(playerChips, newChip)
            success = true
            message = "Имплантация успешна: " .. newChip.name
        elseif roll <= CHIPS.Config.ImplantSuccessRate + CHIPS.Config.RejectionChance then
            -- Отторжение
            success = false
            message = "Отторжение чипа! Вы получили урон."
            ply:TakeDamage(math.random(20, 40))
        else
            -- Осложнения
            newChip.implanted = true
            newChip.active = true
            newChip.implantTime = os.time()
            newChip.hasComplications = true
            CHIPS.ApplyChipEffects(ply, newChip)
            table.insert(playerChips, newChip)
            success = true
            message = "Имплантация с осложнениями: " .. newChip.name
            ply:TakeDamage(math.random(10, 25))
        end

        -- Удаление чипа из инвентаря при успешной имплантации
        if success and GRM.Inventory then
            GRM.Inventory.RemoveFromSlot(ply, slotIdx, 1)
        end

        CHIPS.SaveData()
        if CHIPS.SyncChips then CHIPS.SyncChips(ply) end
        ply:ChatPrint("[Аугментации] " .. message)

        -- Отправка результата клиенту
        net.Start("GRM_AugChip_ImplantResult")
        net.WriteBool(success)
        net.WriteString(message)
        net.Send(ply)
    end)

    -- Обработчик использования augmentation_chip из инвентаря.
    local function registerChipUse()
        if not GRM.Inventory or not GRM.Inventory.RegisterUseHandler then return false end
        GRM.Inventory.RegisterUseHandler("augment_chip_implant", function(ply, slotIdx, slot)
            local d = istable(slot and slot.data) and slot.data or {}
            local saved = d.chipId and CHIPS.ChipDatabase[d.chipId] or nil
            if not saved and d.chipId then for _,oldChip in ipairs(CHIPS.GetPlayerChips(ply)) do if oldChip.id == d.chipId then saved=oldChip break end end end
            if not saved then
                local newest=0
                for _,oldChip in ipairs(CHIPS.GetPlayerChips(ply)) do
                    if not oldChip.implanted and (tonumber(oldChip.created) or 0) >= newest then saved=oldChip; newest=tonumber(oldChip.created) or 0 end
                end
            end
            local chip = saved or {id=d.chipId or ("chip_"..os.time().."_"..math.random(1000,9999)), name=d.chipName or d.name or "Чип", category=d.chipCategory or d.category or "civilian", level=tonumber(d.chipLevel or d.level) or 1, modifiers=d.chipModifiers or d.modifiers or {}, implanted=false, created=os.time()}
            if saved then chip.name=d.chipName or chip.name; chip.category=d.chipCategory or chip.category; chip.level=tonumber(d.chipLevel) or chip.level; chip.modifiers=d.chipModifiers or chip.modifiers end
            local list = CHIPS.GetPlayerChips(ply)
            local roll = math.random()
            if roll <= CHIPS.Config.ImplantSuccessRate or roll > CHIPS.Config.ImplantSuccessRate + CHIPS.Config.RejectionChance then
                chip.implanted=true; chip.active=true; chip.implantTime=os.time(); chip.hasComplications = roll > CHIPS.Config.ImplantSuccessRate + CHIPS.Config.RejectionChance
                CHIPS.ApplyChipEffects(ply, chip); if not saved then table.insert(list, chip) end; GRM.Inventory.RemoveFromSlot(ply, slotIdx, 1); CHIPS.SaveData(); CHIPS.SyncChips(ply)
                GRM.Notify(ply, chip.hasComplications and "Чип имплантирован с осложнениями" or "Чип успешно имплантирован", 80, 220, 150)
            else GRM.Notify(ply, "Отторжение чипа", 240, 90, 80); ply:TakeDamage(math.random(20,40)); ply:EmitSound("buttons/button10.wav", 72, 85, 1, CHAN_AUTO)
        net.Start("GRM_AugChip_Rejection"); net.Send(ply) end
        end)
        return true
    end
    timer.Create("GRM_AugChip_RegisterInventory", 1, 0, function() if registerChipUse() then timer.Remove("GRM_AugChip_RegisterInventory") end end)

    CHIPS._hackedDoors=CHIPS._hackedDoors or setmetatable({},{__mode="k"})
    local function hackDoor(ply, door)
        if not IsValid(ply) or not IsValid(door) then return false end
        local cls=door:GetClass()
        local valid=(cls=="func_door" or cls=="func_door_rotating" or cls=="prop_door_rotating" or cls=="prop_physics")
        if not valid then return false end
        if ply:GetPos():DistToSqr(door:GetPos()) > 180*180 then return false end
        local chip=CHIPS.HasDoorHack(ply)
        if not chip then return false end
        if GRM.AugmentationAccess and not GRM.AugmentationAccess.Can(ply,"hack_door",door) then GRM.AugmentationAccess.Deny(ply); return true end
        if door.GRMHackUntil and door.GRMHackUntil>CurTime() then return true end
        door.GRMHackUntil=CurTime()+30;CHIPS._hackedDoors[door]=true
        door.GRMHackHoldUntil=CurTime()+40; door.GRMHackWasLocked=door:GetInternalVariable("m_bLocked")==1
        door:Fire("Unlock","",0); door:Fire("Open","",0); door:Fire("Toggle","",0)
        ply:EmitSound("buttons/combine_button7.wav",70,125,1,CHAN_AUTO); if GRM.Notify then GRM.Notify(ply,"Дверь взломана на 60 секунд",80,210,150) else ply:ChatPrint("[Аугментации] Дверь взломана на 30 секунд, удержание открытия ещё 10 секунд") end
        timer.Create("GRM_DoorHack_"..door:EntIndex(),40,1,function() if IsValid(door) then door:Fire("Close","",0); if door.GRMHackWasLocked then door:Fire("Lock","",0) end; door.GRMHackUntil=nil; door.GRMHackHoldUntil=nil end;CHIPS._hackedDoors[door]=nil end)
        return true
    end
    hook.Add("Think", "GRM_AugChip_DoorHackCleanup", function()
        local now=CurTime();if(CHIPS._doorHackCleanupAt or 0)>now then return end;CHIPS._doorHackCleanupAt=now+.5
        for e in pairs(CHIPS._hackedDoors)do if not IsValid(e)then CHIPS._hackedDoors[e]=nil elseif e.GRMHackUntil and e.GRMHackUntil<=now then e.GRMHackUntil=nil;CHIPS._hackedDoors[e]=nil end end
    end)
    hook.Add("PlayerUse","GRM_AugChip_DoorHack",function(ply,ent) if hackDoor(ply,ent) then return false end end)
    hook.Add("KeyPress","GRM_AugChip_DoorHack_Key",function(ply,key) if key==IN_USE then hackDoor(ply,ply:GetEyeTrace().Entity) end end)

    print("[GRM AugChips] Chip system v1.0 loaded")
end
