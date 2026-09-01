-- Boot-шим: старт подсистемы идёт через планировщик GRM.Boot (приоритеты и
-- бюджет на тик). Если планировщик почему-то не загружен, работаем по-старому.
local function grmBootStart(id, tier, fn)
    if GRM and GRM.Boot and GRM.Boot.OnMapStart then return GRM.Boot.OnMapStart(id, tier, fn) end
    return hook.Add("InitPostEntity", id, fn)
end

--[[
    GRM Augmentations System
    Модуль кибернетических аугментаций для игроков
]]

if SERVER then
    AddCSLuaFile()
    AddCSLuaFile("autorun/client/cl_grm_augmentations.lua")
    AddCSLuaFile("autorun/client/cl_grm_augmentations_admin.lua")
    AddCSLuaFile("autorun/sh_grm_augmentation_chips.lua")
    AddCSLuaFile("autorun/client/cl_grm_augmentation_chips.lua")
    AddCSLuaFile("autorun/client/cl_grm_augmentation_station.lua")
    AddCSLuaFile("autorun/client/cl_grm_augmentations_hud.lua")
    AddCSLuaFile("autorun/client/cl_grm_augmentation_interface.lua")
    AddCSLuaFile("autorun/sh_grm_augmentation_access.lua")
    AddCSLuaFile("autorun/sh_grm_augmentation_integrations.lua")
    AddCSLuaFile("autorun/sh_grm_news.lua")
end

GRM = GRM or {}
GRM.Augmentations = GRM.Augmentations or {}
local AUG = GRM.Augmentations

-- Конфигурация (настраиваемые лимиты)
AUG.Config = {
    MaxHealth = 1000,           -- Максимальное здоровье после аугментации
    MaxArmor = 255,             -- Максимальная броня
    DefaultHealth = 100,        -- Базовое здоровье
    DefaultArmor = 0,           -- Базовая броня

    -- Категории аугментаций
    Categories = {
        civilian = "Гражданские",
        service = "Служебные",
        military = "Военные",
        experimental = "Экспериментальные"
    },

    -- Типы аугментаций с категориями и правами доступа
    InfraredVision = {
        enabled = true,
        category = "service",
        name = "Инфракрасное зрение",
        description = "Видеть тепловые сигнатуры живых существ",
        cost = 5000,
        access = {
            factions = {"Police", "Military", "FSB"},
            roles = {"detective", "soldier", "agent"},
            superadmin = true
        }
    },

    EnhancedArmor = {
        enabled = true,
        category = "service",
        name = "Усиленная броня",
        description = "Максимальная защита до 255",
        cost = 3000,
        access = {
            factions = {"Police", "Military", "Security"},
            roles = {"officer", "soldier", "guard"},
            superadmin = true
        }
    },

    HealthBoost = {
        enabled = true,
        category = "civilian",
        name = "Увеличение здоровья",
        description = "Максимальное здоровье до 1000",
        cost = 4000,
        access = {
            factions = {}, -- доступно всем фракциям
            roles = {}, -- доступно всем ролям
            everyone = true
        }
    },

    HUDOverlay = {
        enabled = true,
        category = "service",
        name = "HUD терминал",
        description = "Информационный оверлей перед глазами",
        cost = 2000,
        access = {
            factions = {"Police", "Military", "Medic", "FSB"},
            roles = {"officer", "soldier", "medic", "agent"},
            superadmin = true
        }
    },

    EnhancedSpeed = {
        enabled = true,
        category = "military",
        name = "Ускорение",
        description = "Увеличение скорости передвижения на 50%",
        cost = 6000,
        access = {
            factions = {"Military", "FSB"},
            roles = {"soldier", "agent", "special_forces"},
            superadmin = true
        }
    },

    Regeneration = {
        enabled = true,
        category = "civilian",
        name = "Регенерация",
        description = "Медленное восстановление здоровья",
        cost = 3500,
        access = {
            factions = {},
            roles = {},
            everyone = true
        }
    },

    NightVision = {
        enabled = true,
        category = "military",
        name = "Ночное зрение",
        description = "Видеть в темноте",
        cost = 4500,
        access = {
            factions = {"Military", "Police", "FSB"},
            roles = {"soldier", "officer", "agent"},
            superadmin = true
        }
    },

    EMPShield = {
        enabled = true,
        category = "experimental",
        name = "EMP защита",
        description = "Защита от электромагнитных импульсов",
        cost = 8000,
        access = {
            factions = {"Military"},
            roles = {"special_forces", "engineer"},
            superadmin = true
        }
    }
}

-- Хранилище аугментаций игроков
AUG.PlayerData = AUG.PlayerData or {}

-- Получение данных игрока
function AUG.GetPlayerData(ply)
    if not IsValid(ply) then return nil end
    local charKey = GRM.Identity and GRM.Identity.CharacterKey(ply) or ply:SteamID64()
    AUG.PlayerData[charKey] = AUG.PlayerData[charKey] or {
        augmented = false,
        augmentations = {}, -- таблица активных аугментаций
        health = AUG.Config.DefaultHealth,
        armor = AUG.Config.DefaultArmor
    }
    return AUG.PlayerData[charKey]
end

-- Проверка прав доступа к аугментации
function AUG.CanAccessAugmentation(ply, augType)
    if not IsValid(ply) then return false end
    local action = (augType == "HealthBoost" or augType == "EnhancedArmor") and "implant" or "implant"
    if GRM.AugmentationAccess and not GRM.AugmentationAccess.Can(ply, action) then return false end

    -- Суперадмин имеет доступ ко всему
    if ply:IsSuperAdmin() then return true end

    local augConfig = AUG.Config[augType]
    if not augConfig or not augConfig.enabled then return false end

    local access = augConfig.access
    if not access then return false end

    -- Если доступно всем
    if access.everyone then return true end

    -- Проверка по фракции
    if GRM.Factions and #access.factions > 0 then
        local plyFaction = GRM.Factions.GetPlayerFaction and GRM.Factions.GetPlayerFaction(ply)
        if plyFaction then
            for _, faction in ipairs(access.factions) do
                if plyFaction == faction then return true end
            end
        end
    end

    -- Проверка по роли
    if GRM.Roles and #access.roles > 0 then
        local plyRole = GRM.Roles.GetPlayerRole and GRM.Roles.GetPlayerRole(ply)
        if plyRole then
            for _, role in ipairs(access.roles) do
                if plyRole == role then return true end
            end
        end
    end

    return false
end

-- Проверка наличия аугментации
function AUG.HasAugmentation(ply, augType)
    local data = AUG.GetPlayerData(ply)
    if not data then return false end
    return data.augmentations[augType] == true
end

-- Получение списка доступных аугментаций для игрока
function AUG.GetAvailableAugmentations(ply)
    local available = {}

    for augType, augConfig in pairs(AUG.Config) do
        if type(augConfig) == "table" and augConfig.enabled and augConfig.category then
            if AUG.CanAccessAugmentation(ply, augType) then
                table.insert(available, {
                    type = augType,
                    name = augConfig.name,
                    description = augConfig.description,
                    category = augConfig.category,
                    cost = augConfig.cost
                })
            end
        end
    end

    return available
end

-- Применение аугментации
function AUG.ApplyAugmentation(ply, augType)
    if not IsValid(ply) then return false end

    -- Проверка прав доступа
    if not AUG.CanAccessAugmentation(ply, augType) then
        return false, "Нет прав доступа к этой аугментации"
    end

    local augConfig = AUG.Config[augType]
    if not augConfig or not augConfig.enabled then
        return false, "Аугментация недоступна"
    end

    local data = AUG.GetPlayerData(ply)
    if not data then return false, "Ошибка получения данных" end

    -- Проверка уже установлена ли
    if data.augmentations[augType] then
        return false, "Аугментация уже установлена"
    end

    -- Применение аугментации
    data.augmentations[augType] = true
    data.augmented = true

    -- Специфичная логика для каждой аугментации
    if augType == "EnhancedArmor" then
        data.armor = AUG.Config.MaxArmor
        if SERVER then
            ply:SetArmor(AUG.Config.MaxArmor)
        end

    elseif augType == "HealthBoost" then
        data.health = AUG.Config.MaxHealth
        if SERVER then
            ply:SetMaxHealth(AUG.Config.MaxHealth)
            ply:SetHealth(AUG.Config.MaxHealth)
        end

    elseif augType == "InfraredVision" or augType == "HUDOverlay" or augType == "NightVision" then
        -- Клиентские эффекты обрабатываются через сеть
        if SERVER then
            net.Start("GRM_Augmentation_Update")
            net.WriteString(augType)
            net.WriteBool(true)
            net.Send(ply)
        end

    elseif augType == "EnhancedSpeed" then
        if SERVER then
            -- Увеличение скорости на 50%
            local currentSpeed = ply:GetWalkSpeed()
            ply:SetWalkSpeed(currentSpeed * 1.5)
            ply:SetRunSpeed(currentSpeed * 1.8)
        end

    elseif augType == "Regeneration" then
        -- Обрабатывается в Think hook на клиенте/сервере
    end

    return true
end

-- Удаление аугментации
function AUG.RemoveAugmentation(ply, augType)
    if not IsValid(ply) then return false end

    local data = AUG.GetPlayerData(ply)
    if not data or not data.augmentations[augType] then
        return false
    end

    -- Удаление аугментации
    data.augmentations[augType] = nil

    -- Специфичная логика удаления
    if augType == "EnhancedArmor" then
        data.armor = AUG.Config.DefaultArmor
        if SERVER then
            ply:SetArmor(AUG.Config.DefaultArmor)
        end

    elseif augType == "HealthBoost" then
        data.health = AUG.Config.DefaultHealth
        if SERVER then
            ply:SetMaxHealth(AUG.Config.DefaultHealth)
            ply:SetHealth(math.min(ply:Health(), AUG.Config.DefaultHealth))
        end

    elseif augType == "InfraredVision" or augType == "HUDOverlay" or augType == "NightVision" then
        if SERVER then
            net.Start("GRM_Augmentation_Update")
            net.WriteString(augType)
            net.WriteBool(false)
            net.Send(ply)
        end

    elseif augType == "EnhancedSpeed" then
        if SERVER then
            -- Возврат к стандартной скорости
            ply:SetWalkSpeed(200)
            ply:SetRunSpeed(400)
        end
    end

    -- Проверка остались ли аугментации
    if table.Count(data.augmentations) == 0 then
        data.augmented = false
    end

    return true
end

-- Сохранение данных
function AUG.SaveData()
    if not SERVER then return end

    local saveData = {
        config = {
            MaxHealth = AUG.Config.MaxHealth,
            MaxArmor = AUG.Config.MaxArmor,
            DefaultHealth = AUG.Config.DefaultHealth,
            DefaultArmor = AUG.Config.DefaultArmor
        },
        players = AUG.PlayerData
    }

    file.CreateDir("grm_augmentations")
    file.Write("grm_augmentations/data.txt", util.TableToJSON(saveData, true))
end

-- Загрузка данных
function AUG.LoadData()
    if not SERVER then return end

    if not file.Exists("grm_augmentations/data.txt", "DATA") then
        return
    end

    local data = util.JSONToTable(file.Read("grm_augmentations/data.txt", "DATA"))
    if not data then return end

    if data.config then
        AUG.Config.MaxHealth = data.config.MaxHealth or 1000
        AUG.Config.MaxArmor = data.config.MaxArmor or 255
        AUG.Config.DefaultHealth = data.config.DefaultHealth or 100
        AUG.Config.DefaultArmor = data.config.DefaultArmor or 0
    end

    if data.players then
        AUG.PlayerData = data.players
    end
end

-- Network strings
if SERVER then
    util.AddNetworkString("GRM_Augmentation_Update")
    util.AddNetworkString("GRM_Augmentation_Apply")
    util.AddNetworkString("GRM_Augmentation_Remove")
    util.AddNetworkString("GRM_Augmentation_Admin_Open")
    util.AddNetworkString("GRM_Augmentation_Admin_Save")
    util.AddNetworkString("GRM_Augmentation_Admin_GetList")
    util.AddNetworkString("GRM_Augmentation_Admin_SendList")

    -- Загрузка данных при старте
    grmBootStart("GRM_Augmentations_Init", "normal", function()
        AUG.LoadData()
    end)

    -- Сохранение данных при выключении
    hook.Add("ShutDown", "GRM_Augmentations_Save", function()
        AUG.SaveData()
    end)

    -- Обработка запросов на аугментацию
    net.Receive("GRM_Augmentation_Apply", function(len, ply)
        local augType = net.ReadString()
        local success, errorMsg = AUG.ApplyAugmentation(ply, augType)

        net.Start("GRM_Augmentation_Update")
        net.WriteString(augType)
        net.WriteBool(success)
        net.Send(ply)

        if success then
            AUG.SaveData()
            ply:ChatPrint("[Аугментации] Установлена: " .. (AUG.Config[augType].name or augType))
        else
            ply:ChatPrint("[Аугментации] Ошибка: " .. (errorMsg or "Неизвестная ошибка"))
        end
    end)

    -- Обработка запросов на удаление
    net.Receive("GRM_Augmentation_Remove", function(len, ply)
        local augType = net.ReadString()
        local success = AUG.RemoveAugmentation(ply, augType)

        net.Start("GRM_Augmentation_Update")
        net.WriteString(augType)
        net.WriteBool(not success) -- false = removed
        net.Send(ply)

        if success then
            AUG.SaveData()
            ply:ChatPrint("[Аугментации] Удалена: " .. (AUG.Config[augType].name or augType))
        end
    end)

    -- Восстановление аугментаций при спавне
    hook.Add("PlayerSpawn", "GRM_Augmentations_Spawn", function(ply)
        local data = AUG.GetPlayerData(ply)
        if not data or not data.augmented then return end

        timer.Simple(0.1, function()
            if not IsValid(ply) then return end

            -- Восстановление HP и брони
            if data.health > AUG.Config.DefaultHealth then
                ply:SetMaxHealth(data.health)
                ply:SetHealth(data.health)
            end

            if data.armor > AUG.Config.DefaultArmor then
                ply:SetArmor(data.armor)
            end

            -- Отправка клиентских аугментаций
            for augType, enabled in pairs(data.augmentations) do
                if enabled and (augType == "InfraredVision" or augType == "HUDOverlay" or augType == "NightVision") then
                    net.Start("GRM_Augmentation_Update")
                    net.WriteString(augType)
                    net.WriteBool(true)
                    net.Send(ply)
                end

                if enabled and augType == "EnhancedSpeed" then
                    local currentSpeed = ply:GetWalkSpeed()
                    ply:SetWalkSpeed(currentSpeed * 1.5)
                    ply:SetRunSpeed(currentSpeed * 1.8)
                end
            end
        end)
    end)

    -- Админ-панель: открытие
    net.Receive("GRM_Augmentation_Admin_Open", function(len, ply)
        if not ply:IsSuperAdmin() then return end

        local augList = {}
        for augType, augConfig in pairs(AUG.Config) do
            if type(augConfig) == "table" and augConfig.category then
                table.insert(augList, {
                    type = augType,
                    name = augConfig.name,
                    description = augConfig.description,
                    category = augConfig.category,
                    cost = augConfig.cost,
                    enabled = augConfig.enabled,
                    access = augConfig.access
                })
            end
        end

        net.Start("GRM_Augmentation_Admin_SendList")
        net.WriteTable(augList)
        net.WriteTable(AUG.Config.Categories)
        net.WriteTable(Factions or FactionsData or {})
        net.Send(ply)
    end)

    -- Админ-панель: сохранение настроек
    net.Receive("GRM_Augmentation_Admin_Save", function(len, ply)
        if not ply:IsSuperAdmin() then return end

        local augType = net.ReadString()
        local enabled = net.ReadBool()
        local cost = net.ReadUInt(32)
        local accessTable = net.ReadTable()

        if AUG.Config[augType] then
            AUG.Config[augType].enabled = enabled
            AUG.Config[augType].cost = cost
            AUG.Config[augType].access = accessTable

            AUG.SaveData()
            ply:ChatPrint("[Аугментации] Настройки сохранены для: " .. augType)
        end
    end)
end

print("[GRM Augmentations] System v2.0 loaded")
