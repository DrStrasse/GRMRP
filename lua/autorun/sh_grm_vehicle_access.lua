--[[--------------------------------------------------------------------
    GRM Vehicle Access System v1.0
    Система доступа к транспорту с интеграцией фракций и экономики

    Функциональность:
      • Персональная покупка доступа к транспорту
      • Доступ по фракции / отделу / рангу
      • Магазин транспорта (/vshop)
      • Управление доступом для лидера/суперадмина
      • Сервер считывает имеющийся транспорт на карте

    Зависимости:
      • sh_factions.lua (система фракций)
      • grm_currency.lua (валюта GRM)
      • vehicle_dealer.lua (дилер транспорта)
--------------------------------------------------------------------]]

if SERVER then
    AddCSLuaFile()
end

-- ============================================================
-- СЕТЕВЫЕ СТРОКИ
-- ============================================================

local NET_VSHOP_OPEN        = "GRM_VShop_Open"
local NET_VSHOP_BUY         = "GRM_VShop_Buy"
local NET_VSHOP_RESULT      = "GRM_VShop_Result"
local NET_VACCESS_OPEN      = "GRM_VAccess_Open"
local NET_VACCESS_DATA      = "GRM_VAccess_Data"
local NET_VACCESS_SAVE      = "GRM_VAccess_Save"
local NET_VACCESS_RESULT    = "GRM_VAccess_Result"
local NET_VSHOP_ADMIN_OPEN  = "GRM_VShop_AdminOpen"
local NET_VSHOP_ADMIN_DATA  = "GRM_VShop_AdminData"
local NET_VSHOP_ADMIN_SAVE  = "GRM_VShop_AdminSave"

-- ============================================================
-- SERVER
-- ============================================================

if SERVER then
    util.AddNetworkString(NET_VSHOP_OPEN)
    util.AddNetworkString(NET_VSHOP_BUY)
    util.AddNetworkString(NET_VSHOP_RESULT)
    util.AddNetworkString(NET_VACCESS_OPEN)
    util.AddNetworkString(NET_VACCESS_DATA)
    util.AddNetworkString(NET_VACCESS_SAVE)
    util.AddNetworkString(NET_VACCESS_RESULT)
    util.AddNetworkString(NET_VSHOP_ADMIN_OPEN)
    util.AddNetworkString(NET_VSHOP_ADMIN_DATA)
    util.AddNetworkString(NET_VSHOP_ADMIN_SAVE)

    -- ── Файлы данных ─────────────────────────────────────────────
    local PURCHASES_FILE    = "grm_vehicle_purchases.json"
    local SHOP_PRICES_FILE  = "grm_vehicle_prices.json"
    local FACTION_ACCESS_FILE = "grm_faction_vehicle_access.json"

    -- ── Данные ───────────────────────────────────────────────────
    -- Персональные покупки: { [steamID64] = { "class1", "class2", ... } }
    local PlayerPurchases = {}

    -- Цены магазина: { [vehicleClass] = { price = N, name = "...", category = "..." } }
    local ShopPrices = {}

    -- Доступ фракций к транспорту:
    -- { [factionName] = {
    --     general = { "class1", "class2" },
    --     roles = { [roleName] = { "class1" } },
    --     departments = { [deptName] = { "class1" } }
    -- } }
    local FactionVehicleAccess = {}

    -- ── Загрузка/Сохранение ──────────────────────────────────────
    local function safeJSON(data)
        local ok, t = pcall(util.JSONToTable, data or "")
        if ok and istable(t) then return t end
        return {}
    end

    local function loadPurchases()
        if not file.Exists(PURCHASES_FILE, "DATA") then return {} end
        return safeJSON(file.Read(PURCHASES_FILE, "DATA"))
    end

    local function savePurchases()
        file.Write(PURCHASES_FILE, util.TableToJSON(PlayerPurchases, true))
    end

    local function loadShopPrices()
        if not file.Exists(SHOP_PRICES_FILE, "DATA") then return {} end
        return safeJSON(file.Read(SHOP_PRICES_FILE, "DATA"))
    end

    local function saveShopPrices()
        file.Write(SHOP_PRICES_FILE, util.TableToJSON(ShopPrices, true))
    end

    local function loadFactionAccess()
        if not file.Exists(FACTION_ACCESS_FILE, "DATA") then return {} end
        return safeJSON(file.Read(FACTION_ACCESS_FILE, "DATA"))
    end

    local function saveFactionAccess()
        file.Write(FACTION_ACCESS_FILE, util.TableToJSON(FactionVehicleAccess, true))
    end

    -- Инициализация
    PlayerPurchases = loadPurchases()
    ShopPrices = loadShopPrices()
    FactionVehicleAccess = loadFactionAccess()

    -- ── Утилиты ──────────────────────────────────────────────────
    local function characterKey(ply)
        if IsValid(ply) and ply:IsPlayer() then
            if GRM.Identity and GRM.Identity.CharacterKey then return GRM.Identity.CharacterKey(ply) end
            return tostring(ply:SteamID64() or "")
        end
        local raw = tostring(ply or "")
        if raw:match(":char[1-3]$") then return raw end
        if raw:match("^%d+$") then return raw .. ":char1" end
        return raw
    end

    -- Получить фракцию, роль и отдел игрока
    local function getPlayerFactionInfo(ply)
        if not Factions then return nil, nil, nil end
        local sid = ply:SteamID()
        local ck = characterKey(ply)
        for name, f in pairs(Factions) do
            local info = istable(f) and GRM.Identity.FactionMember(f, ply) or nil
            if info then
                return name, info.Role or "Участник", info.Department or ""
            end
        end
        return nil, nil, nil
    end

    -- Проверить, есть ли у игрока персональный доступ к транспорту
    local function hasPersonalAccess(ply, vehicleClass)
        local sid = characterKey(ply)
        if not PlayerPurchases[sid] then return false end
        for _, class in ipairs(PlayerPurchases[sid]) do
            if class == vehicleClass then return true end
        end
        return false
    end

    -- Проверить доступ по фракции/отделу/рангу
    local function hasFactionAccess(ply, vehicleClass)
        local factionName, role, department = getPlayerFactionInfo(ply)
        if not factionName then return false end

        local access = FactionVehicleAccess[factionName]
        if not access then return false end

        -- Приоритет: отдел > ранг > общий фракционный

        -- Проверка по отделу
        if department and access.departments and access.departments[department] then
            for _, class in ipairs(access.departments[department]) do
                if class == vehicleClass then return true end
            end
        end

        -- Проверка по рангу
        if role and access.roles and access.roles[role] then
            for _, class in ipairs(access.roles[role]) do
                if class == vehicleClass then return true end
            end
        end

        -- Проверка общего доступа фракции
        if access.general then
            for _, class in ipairs(access.general) do
                if class == vehicleClass then return true end
            end
        end

        return false
    end

    -- Полная проверка доступа игрока к транспорту
    function GRM_HasVehicleAccess(ply, vehicleClass)
        if not IsValid(ply) then return false end

        -- Суперадмин имеет доступ ко всему
        if ply:IsSuperAdmin() then return true end

        -- Персональная покупка
        if hasPersonalAccess(ply, vehicleClass) then return true end

        -- Фракционный доступ
        if hasFactionAccess(ply, vehicleClass) then return true end

        return false
    end

    -- Получить список доступного транспорта для игрока
    function GRM_GetAccessibleVehicles(ply)
        if not IsValid(ply) then return {} end

        local result = {}
        local seen = {}

        -- Персональные покупки
        local sid = characterKey(ply)
        if PlayerPurchases[sid] then
            for _, class in ipairs(PlayerPurchases[sid]) do
                if not seen[class] then
                    seen[class] = true
                    table.insert(result, { class = class, source = "personal" })
                end
            end
        end

        -- Фракционный доступ
        local factionName, role, department = getPlayerFactionInfo(ply)
        if factionName then
            local access = FactionVehicleAccess[factionName]
            if access then
                -- Общий
                if access.general then
                    for _, class in ipairs(access.general) do
                        if not seen[class] then
                            seen[class] = true
                            table.insert(result, { class = class, source = "faction" })
                        end
                    end
                end
                -- По рангу
                if role and access.roles and access.roles[role] then
                    for _, class in ipairs(access.roles[role]) do
                        if not seen[class] then
                            seen[class] = true
                            table.insert(result, { class = class, source = "role" })
                        end
                    end
                end
                -- По отделу
                if department and access.departments and access.departments[department] then
                    for _, class in ipairs(access.departments[department]) do
                        if not seen[class] then
                            seen[class] = true
                            table.insert(result, { class = class, source = "department" })
                        end
                    end
                end
            end
        end

        return result
    end

    -- Получить все доступные классы транспорта на сервере
    function GRM_GetAllVehicleClasses()
        local result = {}
        local seen = {}

        -- Из list.Get("Vehicles") — стандартные GMod транспорты
        local vehicles = list.Get("Vehicles") or {}
        for class, data in pairs(vehicles) do
            if not seen[class] then
                seen[class] = true
                table.insert(result, {
                    class = class,
                    name = data.Name or class,
                    model = data.Model or "",
                    category = data.Category or "Другое",
                    addon = "gmod"
                })
            end
        end

        -- SimFPhys
        local sfVehicles = list.Get("simfphys_vehicles") or {}
        for class, data in pairs(sfVehicles) do
            if not seen[class] then
                seen[class] = true
                table.insert(result, {
                    class = class,
                    name = data.Name or class,
                    model = data.Model or "",
                    category = data.Category or "SimFPhys",
                    addon = "simfphys"
                })
            end
        end

        -- LVS
        local lvsVehicles = list.Get("LVS_Vehicles") or {}
        for class, data in pairs(lvsVehicles) do
            if not seen[class] then
                seen[class] = true
                table.insert(result, {
                    class = class,
                    name = data.Name or class,
                    model = data.Model or "",
                    category = data.Category or "LVS",
                    addon = "lvs"
                })
            end
        end

        table.sort(result, function(a, b) return (a.name or "") < (b.name or "") end)
        return result
    end

    -- ── Покупка транспорта ───────────────────────────────────────

    local function buyVehicleAccess(ply, vehicleClass)
        if not IsValid(ply) then return false, "Игрок не найден" end
        if not vehicleClass or vehicleClass == "" then return false, "Не указан класс" end

        -- Проверяем, есть ли уже доступ
        if hasPersonalAccess(ply, vehicleClass) then
            return false, "У вас уже есть доступ к этому транспорту"
        end

        -- Проверяем цену
        local priceData = ShopPrices[vehicleClass]
        if not priceData then return false, "Этот транспорт не продаётся" end

        local price = priceData.price or 0
        if price <= 0 then return false, "Цена не установлена" end

        -- Проверяем баланс
        if not GRM or not GRM.HasMoney then return false, "Система валюты не загружена" end
        if not GRM.HasMoney(ply, price) then
            return false, "Недостаточно средств. Нужно: " .. GRM.Format(price) ..
                          ", у вас: " .. GRM.Format(GRM.GetBalance(ply))
        end

        -- Списываем деньги
        GRM.TakeMoney(ply, price)

        -- Добавляем доступ
        local sid = characterKey(ply)
        if not PlayerPurchases[sid] then PlayerPurchases[sid] = {} end
        table.insert(PlayerPurchases[sid], vehicleClass)
        savePurchases()

        return true, "Транспорт куплен! Цена: " .. GRM.Format(price)
    end

    -- ── Управление доступом фракции ──────────────────────────────
    local function setFactionVehicleAccess(factionName, accessType, key, vehicleClasses)
        if not factionName or factionName == "" then return false, "Не указана фракция" end
        if not Factions or not Factions[factionName] then return false, "Фракция не найдена" end

        if not FactionVehicleAccess[factionName] then
            FactionVehicleAccess[factionName] = { general = {}, roles = {}, departments = {} }
        end

        local access = FactionVehicleAccess[factionName]

        if accessType == "general" then
            access.general = vehicleClasses or {}
        elseif accessType == "role" then
            if not key or key == "" then return false, "Не указан ранг" end
            access.roles = access.roles or {}
            access.roles[key] = vehicleClasses or {}
        elseif accessType == "department" then
            if not key or key == "" then return false, "Не указан отдел" end
            access.departments = access.departments or {}
            access.departments[key] = vehicleClasses or {}
        else
            return false, "Неизвестный тип доступа"
        end

        saveFactionAccess()
        return true, "Доступ обновлён"
    end

    -- ── Сетевые обработчики ──────────────────────────────────────

    -- Открытие магазина
    net.Receive(NET_VSHOP_OPEN, function(_, ply)
        if not IsValid(ply) then return end

        local allVehicles = GRM_GetAllVehicleClasses()
        local sid = characterKey(ply)

        -- Отмечаем, какие уже куплены
        local purchased = PlayerPurchases[sid] or {}
        local purchasedSet = {}
        for _, class in ipairs(purchased) do purchasedSet[class] = true end

        -- Формируем данные для магазина
        local shopData = {}
        for _, veh in ipairs(allVehicles) do
            local priceData = ShopPrices[veh.class]
            local hasFAccess = hasFactionAccess(ply, veh.class)

            table.insert(shopData, {
                class = veh.class,
                name = (priceData and priceData.name) or veh.name or veh.class,
                price = priceData and priceData.price or 0,
                category = (priceData and priceData.category) or veh.category or "Другое",
                owned = purchasedSet[veh.class] or false,
                factionAccess = hasFAccess,
                inShop = priceData ~= nil,
            })
        end

        net.Start(NET_VSHOP_OPEN)
        net.WriteTable(shopData)
        net.Send(ply)
    end)

    -- Покупка
    net.Receive(NET_VSHOP_BUY, function(_, ply)
        if not IsValid(ply) then return end
        local vehicleClass = net.ReadString()

        local ok, msg = buyVehicleAccess(ply, vehicleClass)

        net.Start(NET_VSHOP_RESULT)
        net.WriteBool(ok)
        net.WriteString(msg or "")
        net.Send(ply)

        if ok then
            GRM.Notify(ply, msg, 100, 220, 100)
        else
            GRM.Notify(ply, "Ошибка: " .. msg, 255, 100, 100)
        end
    end)

    -- Админ: открытие настроек цен
    net.Receive(NET_VSHOP_ADMIN_OPEN, function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end

        local allVehicles = GRM_GetAllVehicleClasses()

        net.Start(NET_VSHOP_ADMIN_DATA)
        net.WriteTable({
            vehicles = allVehicles,
            prices = ShopPrices,
        })
        net.Send(ply)
    end)

    -- Админ: сохранение цен
    net.Receive(NET_VSHOP_ADMIN_SAVE, function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end

        local newPrices = net.ReadTable() or {}
        ShopPrices = newPrices
        saveShopPrices()

        ply:PrintMessage(HUD_PRINTTALK, "[GRM Shop] Цены сохранены.")
    end)

    -- Лидер/Админ: открытие управления доступом
    net.Receive(NET_VACCESS_OPEN, function(_, ply)
        if not IsValid(ply) then return end

        local isSuperAdmin = ply:IsSuperAdmin()
        local isLeader = false
        local leaderFaction = nil
        if Factions then
            local ck = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply)) or ply:SteamID64()
            for name, f in pairs(Factions) do
                if istable(f) then
                    local isLead = (f.Leader == ck)
                    if not isLead and GRM.Identity and GRM.Identity.FactionMember then
                        local mem = GRM.Identity.FactionMember(f, ply)
                        local lRole = f.LeaderRoleName or "Лидер"
                        if istable(mem) and (mem.Role == lRole or mem.Role == "Лидер") then isLead = true end
                    end
                    if isLead then
                        isLeader = true
                        leaderFaction = name
                        break
                    end
                end
            end
        end
        if not isSuperAdmin and not isLeader then
            ply:PrintMessage(HUD_PRINTTALK, "[GRM] Недостаточно прав.")
            return
        end

        local allVehicles = GRM_GetAllVehicleClasses()
        local factionsData = {}

        if isSuperAdmin then
            -- Суперадмин видит все фракции
            for name, f in pairs(Factions or {}) do
                if istable(f) then
                    factionsData[name] = {
                        roles = f.Roles or {},
                        departments = f.Departments or {},
                        access = FactionVehicleAccess[name] or { general = {}, roles = {}, departments = {} },
                    }
                end
            end
        elseif isLeader and leaderFaction then
            -- Лидер видит только свою фракцию
            local f = Factions[leaderFaction]
            if f then
                factionsData[leaderFaction] = {
                    roles = f.Roles or {},
                    departments = f.Departments or {},
                    access = FactionVehicleAccess[leaderFaction] or { general = {}, roles = {}, departments = {} },
                }
            end
        end

        net.Start(NET_VACCESS_DATA)
        net.WriteTable({
            vehicles = allVehicles,
            factions = factionsData,
            isSuperAdmin = isSuperAdmin,
        })
        net.Send(ply)
    end)

    -- Сохранение доступа
    net.Receive(NET_VACCESS_SAVE, function(_, ply)
        if not IsValid(ply) then return end

        local isSuperAdmin = ply:IsSuperAdmin()
        local isLeader = false
        local leaderFaction = nil
        if Factions then
            local ck = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply)) or ply:SteamID64()
            for name, f in pairs(Factions) do
                if istable(f) then
                    local isLead = (f.Leader == ck)
                    if not isLead and GRM.Identity and GRM.Identity.FactionMember then
                        local mem = GRM.Identity.FactionMember(f, ply)
                        local lRole = f.LeaderRoleName or "Лидер"
                        if istable(mem) and (mem.Role == lRole or mem.Role == "Лидер") then isLead = true end
                    end
                    if isLead then
                        isLeader = true
                        leaderFaction = name
                        break
                    end
                end
            end
        end
        if not isSuperAdmin and not isLeader then return end

        local factionName = net.ReadString()
        local accessType = net.ReadString()
        local key = net.ReadString()
        local classes = net.ReadTable() or {}

        -- Лидер может менять только свою фракцию
        if not isSuperAdmin and factionName ~= leaderFaction then
            net.Start(NET_VACCESS_RESULT)
            net.WriteBool(false)
            net.WriteString("Вы можете управлять только своей фракцией")
            net.Send(ply)
            return
        end

        -- Лидер НЕ может менять общий (general) доступ — только суперадмин
        if not isSuperAdmin and accessType == "general" then
            net.Start(NET_VACCESS_RESULT)
            net.WriteBool(false)
            net.WriteString("Только суперадмин может назначать транспорт фракции. Вы можете управлять доступом отделов и рангов.")
            net.Send(ply)
            return
        end

        -- Лидер может назначать отделам/рангам ТОЛЬКО тот транспорт,
        -- который уже закреплён за фракцией суперадмином (в general)
        if not isSuperAdmin and (accessType == "role" or accessType == "department") then
            local factionAccess = FactionVehicleAccess[factionName]
            local generalSet = {}
            if factionAccess and factionAccess.general then
                for _, class in ipairs(factionAccess.general) do
                    generalSet[class] = true
                end
            end

            -- Фильтруем: оставляем только транспорт из general
            local filteredClasses = {}
            for _, class in ipairs(classes) do
                if generalSet[class] then
                    table.insert(filteredClasses, class)
                end
            end
            classes = filteredClasses
        end

        local ok, msg = setFactionVehicleAccess(factionName, accessType, key, classes)

        net.Start(NET_VACCESS_RESULT)
        net.WriteBool(ok)
        net.WriteString(msg or "")
        net.Send(ply)
    end)

    -- ── Интеграция с дилером ─────────────────────────────────────
    -- Переопределяем проверку доступа в дилере

    -- Хук для проверки доступа при спавне через дилер
    hook.Add("VD_CheckVehicleAccess", "GRM_VehicleAccessCheck", function(ply, vehicleClass, dealerData)
        -- Если у дилера есть свой список — проверяем по нему
        -- Если нет — проверяем через нашу систему
        return GRM_HasVehicleAccess(ply, vehicleClass)
    end)

    -- ── Чат-команды ──────────────────────────────────────────────
    hook.Add("PlayerSay", "GRM_VehicleShopCmds", function(ply, text)
        local lower = string.lower(string.Trim(text))

        -- /vshop — открыть магазин транспорта
        if lower == "/vshop" or lower == "!vshop" then
            local allVehicles = GRM_GetAllVehicleClasses()
            local sid = characterKey(ply)
            local purchased = PlayerPurchases[sid] or {}
            local purchasedSet = {}
            for _, class in ipairs(purchased) do purchasedSet[class] = true end

            local shopData = {}
            for _, veh in ipairs(allVehicles) do
                local priceData = ShopPrices[veh.class]
                if priceData then
                    table.insert(shopData, {
                        class = veh.class,
                        name = priceData.name or veh.name or veh.class,
                        price = priceData.price or 0,
                        category = priceData.category or veh.category or "Другое",
                        owned = purchasedSet[veh.class] or false,
                        factionAccess = hasFactionAccess(ply, veh.class),
                    })
                end
            end

            net.Start(NET_VSHOP_OPEN)
            net.WriteTable(shopData)
            net.Send(ply)
            return ""
        end

        -- /vaccess — управление доступом к транспорту
        if lower == "/vaccess" or lower == "!vaccess" then
            net.Start(NET_VACCESS_OPEN)
            net.Send(ply)
            return ""
        end

        -- /vshop_admin — настройка цен (суперадмин)
        if lower == "/vshop_admin" or lower == "!vshop_admin" then
            if not ply:IsSuperAdmin() then
                ply:PrintMessage(HUD_PRINTTALK, "[GRM Shop] Только для суперадмина.")
                return ""
            end

            local allVehicles = GRM_GetAllVehicleClasses()
            net.Start(NET_VSHOP_ADMIN_DATA)
            net.WriteTable({
                vehicles = allVehicles,
                prices = ShopPrices,
            })
            net.Send(ply)
            return ""
        end

        -- /myvehicles — список купленного транспорта
        if lower == "/myvehicles" or lower == "!myvehicles" then
            local sid = characterKey(ply)
            local purchased = PlayerPurchases[sid]
            if not purchased or #purchased == 0 then
                ply:ChatPrint("[GRM Shop] У вас нет купленного транспорта.")
            else
                ply:ChatPrint("[GRM Shop] Ваш транспорт:")
                for i, class in ipairs(purchased) do
                    local priceData = ShopPrices[class]
                    local name = (priceData and priceData.name) or class
                    ply:ChatPrint("  " .. i .. ". " .. name .. " (" .. class .. ")")
                end
            end
            return ""
        end
    end)

    print("[GRM] Vehicle Access System v1.0 — загружен")
end

-- ============================================================
-- CLIENT
-- ============================================================

if CLIENT then
    local THEME = {
        bg          = Color(25, 25, 30, 248),
        bgLight     = Color(35, 35, 42, 240),
        bgHover     = Color(50, 50, 60, 250),
        accent      = Color(80, 160, 255),
        accentDark  = Color(50, 120, 200),
        text        = Color(220, 220, 230),
        textDim     = Color(150, 150, 165),
        success     = Color(60, 200, 100),
        successDark = Color(40, 160, 80),
        danger      = Color(220, 60, 60),
        dangerHover = Color(180, 40, 40),
        gold        = Color(255, 200, 50),
        border      = Color(60, 60, 75),
    }

    surface.CreateFont("VShop_Title",  { font = "Roboto", size = 22, weight = 700, antialias = true })
    surface.CreateFont("VShop_Normal", { font = "Roboto", size = 14, weight = 500, antialias = true })
    surface.CreateFont("VShop_Small",  { font = "Roboto", size = 12, weight = 400, antialias = true })
    surface.CreateFont("VShop_Price",  { font = "Roboto", size = 16, weight = 700, antialias = true })

    local function styledButton(parent, text, color, hoverColor, textColor)
        local btn = vgui.Create("DButton", parent)
        btn:SetText(text)
        btn:SetFont("VShop_Normal")
        btn:SetTextColor(textColor or Color(255, 255, 255))
        function btn:Paint(w, h)
            local c = self:IsHovered() and (hoverColor or THEME.accentDark) or (color or THEME.accent)
            draw.RoundedBox(4, 0, 0, w, h, c)
        end
        return btn
    end

    -- ════════════════════════════════════════════════════════
    -- МАГАЗИН ТРАНСПОРТА
    -- ════════════════════════════════════════════════════════

    net.Receive(NET_VSHOP_OPEN, function()
        local shopData = net.ReadTable() or {}

        if #shopData == 0 then
            notification.AddLegacy("[GRM Shop] Магазин пуст — администратор не добавил товары.", NOTIFY_ERROR, 4)
            return
        end

        local frame = vgui.Create("DFrame")
        frame:SetTitle("")
        frame:SetSize(900, 640)
        frame:Center()
        frame:MakePopup()

        function frame:Paint(w, h)
            draw.RoundedBox(8, 0, 0, w, h, THEME.bg)
            draw.RoundedBoxEx(8, 0, 0, w, 36, Color(35, 35, 45), true, true, false, false)
            draw.SimpleText("Магазин транспорта", "VShop_Title", 14, 18, THEME.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

            local balText = "Баланс: " .. (GRM and GRM.Format and GRM.Format(GRM.LocalBalance or 0) or "???")
            draw.SimpleText(balText, "VShop_Normal", w - 14, 18, THEME.gold, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end

        -- Категории
        local categories = {}
        local catOrder = {}
        for _, item in ipairs(shopData) do
            local cat = item.category or "Другое"
            if not categories[cat] then
                categories[cat] = {}
                table.insert(catOrder, cat)
            end
            table.insert(categories[cat], item)
        end
        table.sort(catOrder)

        local tabs = vgui.Create("DPropertySheet", frame)
        tabs:Dock(FILL)
        tabs:DockMargin(6, 40, 6, 6)
        function tabs:Paint(w, h)
            surface.SetDrawColor(THEME.bgLight)
            surface.DrawRect(0, 0, w, h)
        end

        for _, catName in ipairs(catOrder) do
            local items = categories[catName]

            local catPanel = vgui.Create("DPanel")
            catPanel:SetPaintBackground(false)

            local scroll = vgui.Create("DScrollPanel", catPanel)
            scroll:Dock(FILL)
            scroll:DockMargin(4, 4, 4, 4)

            for _, item in ipairs(items) do
                local row = vgui.Create("DPanel", scroll)
                row:Dock(TOP)
                row:SetTall(64)
                row:DockMargin(2, 2, 2, 2)

                local isOwned = item.owned
                local hasFAccess = item.factionAccess
                local borderColor = isOwned and THEME.success or (hasFAccess and THEME.accent or THEME.border)

                function row:Paint(w, h)
                    draw.RoundedBox(6, 0, 0, w, h, THEME.bgLight)
                    surface.SetDrawColor(borderColor)
                    surface.DrawOutlinedRect(0, 0, w, h, 1)
                end

                -- Название
                local lblName = vgui.Create("DLabel", row)
                lblName:SetPos(12, 8)
                lblName:SetSize(300, 20)
                lblName:SetText(item.name or item.class)
                lblName:SetFont("VShop_Normal")
                lblName:SetTextColor(THEME.text)

                -- Класс
                local lblClass = vgui.Create("DLabel", row)
                lblClass:SetPos(12, 30)
                lblClass:SetSize(300, 16)
                lblClass:SetText(item.class)
                lblClass:SetFont("VShop_Small")
                lblClass:SetTextColor(THEME.textDim)

                -- Статус
                local statusText, statusColor
                if isOwned then
                    statusText = "✓ КУПЛЕНО"
                    statusColor = THEME.success
                elseif hasFAccess then
                    statusText = "✓ Доступ от фракции"
                    statusColor = THEME.accent
                else
                    statusText = ""
                    statusColor = THEME.textDim
                end

                if statusText ~= "" then
                    local lblStatus = vgui.Create("DLabel", row)
                    lblStatus:SetPos(12, 46)
                    lblStatus:SetSize(200, 14)
                    lblStatus:SetText(statusText)
                    lblStatus:SetFont("VShop_Small")
                    lblStatus:SetTextColor(statusColor)
                end

                -- Цена
                local price = item.price or 0
                if price > 0 then
                    local priceText = GRM and GRM.Format and GRM.Format(price) or (price .. " GRM")
                    local lblPrice = vgui.Create("DLabel", row)
                    lblPrice:SetPos(580, 20)
                    lblPrice:SetSize(140, 24)
                    lblPrice:SetText(priceText)
                    lblPrice:SetFont("VShop_Price")
                    lblPrice:SetTextColor(THEME.gold)
                    lblPrice:SetContentAlignment(6)
                end

                -- Кнопка покупки
                if not isOwned and not hasFAccess and price > 0 then
                    local btnBuy = styledButton(row, "Купить", THEME.success, THEME.successDark)
                    btnBuy:SetPos(740, 16)
                    btnBuy:SetSize(100, 32)
                    btnBuy.DoClick = function()
                        net.Start(NET_VSHOP_BUY)
                        net.WriteString(item.class)
                        net.SendToServer()
                        frame:Close()
                    end
                elseif isOwned or hasFAccess then
                    local lblOk = vgui.Create("DLabel", row)
                    lblOk:SetPos(740, 22)
                    lblOk:SetSize(100, 20)
                    lblOk:SetText("Доступно")
                    lblOk:SetFont("VShop_Normal")
                    lblOk:SetTextColor(THEME.success)
                    lblOk:SetContentAlignment(5)
                end
            end

            tabs:AddSheet(catName, catPanel, "icon16/car.png")
        end
    end)

    -- Результат покупки
    net.Receive(NET_VSHOP_RESULT, function()
        local ok = net.ReadBool()
        local msg = net.ReadString()
        if ok then
            notification.AddLegacy(msg, NOTIFY_GENERIC, 4)
        else
            notification.AddLegacy("Ошибка: " .. msg, NOTIFY_ERROR, 4)
        end
    end)

    -- ════════════════════════════════════════════════════════
    -- УПРАВЛЕНИЕ ДОСТУПОМ К ТРАНСПОРТУ (ЛИДЕР/СУПЕРАДМИН)
    -- ════════════════════════════════════════════════════════

    net.Receive(NET_VACCESS_DATA, function()
        local data = net.ReadTable() or {}
        local vehicles = data.vehicles or {}
        local factions = data.factions or {}
        local isSuperAdmin = data.isSuperAdmin or false

        local frame = vgui.Create("DFrame")
        frame:SetTitle("")
        frame:SetSize(1100, 720)
        frame:Center()
        frame:MakePopup()

        function frame:Paint(w, h)
            draw.RoundedBox(8, 0, 0, w, h, THEME.bg)
            draw.RoundedBoxEx(8, 0, 0, w, 36, Color(35, 35, 45), true, true, false, false)
            draw.SimpleText("Управление доступом к транспорту", "VShop_Title", 14, 18, THEME.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end

        local tabs = vgui.Create("DPropertySheet", frame)
        tabs:Dock(FILL)
        tabs:DockMargin(6, 40, 6, 6)

        -- Создаём вкладку для каждой фракции
        for factionName, fData in pairs(factions) do
            local fPanel = vgui.Create("DPanel")
            fPanel:SetPaintBackground(false)

            local innerTabs = vgui.Create("DPropertySheet", fPanel)
            innerTabs:Dock(FILL)

            -- ── Общий доступ фракции ──
            local genPanel = vgui.Create("DPanel")
            genPanel:SetPaintBackground(false)
            genPanel:DockPadding(8, 8, 8, 8)

            local generalAccess = fData.access and fData.access.general or {}
            local generalSet = {}
            for _, class in ipairs(generalAccess) do generalSet[class] = true end

            if not isSuperAdmin then
                -- Лидер видит только список закреплённого транспорта (только чтение)
                local infoLbl = vgui.Create("DLabel", genPanel)
                infoLbl:Dock(TOP)
                infoLbl:SetTall(36)
                infoLbl:SetWrap(true)
                infoLbl:SetText("Транспорт, закреплённый за фракцией суперадмином. Вы можете распределять его по отделам и рангам во вкладках ниже.")
                infoLbl:SetFont("VShop_Normal")
                infoLbl:SetTextColor(THEME.textDim)

                local genScroll = vgui.Create("DScrollPanel", genPanel)
                genScroll:Dock(FILL)
                genScroll:DockMargin(0, 8, 0, 0)

                if #generalAccess == 0 then
                    local emptyLbl = vgui.Create("DLabel", genScroll)
                    emptyLbl:Dock(TOP)
                    emptyLbl:SetTall(30)
                    emptyLbl:SetText("Суперадмин ещё не закрепил транспорт за вашей фракцией.")
                    emptyLbl:SetFont("VShop_Normal")
                    emptyLbl:SetTextColor(THEME.danger)
                else
                    for _, class in ipairs(generalAccess) do
                        local row = vgui.Create("DPanel", genScroll)
                        row:Dock(TOP)
                        row:SetTall(26)
                        row:DockMargin(0, 1, 0, 1)
                        row:SetPaintBackground(false)

                        local lbl = vgui.Create("DLabel", row)
                        lbl:SetPos(12, 3)
                        lbl:SetSize(600, 20)

                        -- Найти имя транспорта
                        local vehName = class
                        for _, veh in ipairs(vehicles) do
                            if veh.class == class then vehName = veh.name .. " [" .. class .. "]" break end
                        end

                        lbl:SetText("✓ " .. vehName)
                        lbl:SetFont("VShop_Normal")
                        lbl:SetTextColor(THEME.success)
                    end
                end
            else
                -- Суперадмин может редактировать общий доступ
                local genScroll = vgui.Create("DScrollPanel", genPanel)
                genScroll:Dock(FILL)
                genScroll:DockMargin(0, 0, 0, 40)

                for _, veh in ipairs(vehicles) do
                    local row = vgui.Create("DPanel", genScroll)
                    row:Dock(TOP)
                    row:SetTall(28)
                    row:DockMargin(0, 1, 0, 1)
                    row:SetPaintBackground(false)

                    local chk = vgui.Create("DCheckBoxLabel", row)
                    chk:SetPos(8, 4)
                    chk:SetSize(600, 20)
                    chk:SetText(veh.name .. " [" .. veh.class .. "]")
                    chk:SetFont("VShop_Normal")
                    chk:SetTextColor(THEME.text)
                    chk:SetValue(generalSet[veh.class] or false)
                    chk.OnChange = function(_, val)
                        if val then
                            generalSet[veh.class] = true
                        else
                            generalSet[veh.class] = nil
                        end
                    end
                end

                local btnSaveGen = styledButton(genPanel, "Сохранить общий доступ", THEME.success, THEME.successDark)
                btnSaveGen:Dock(BOTTOM)
                btnSaveGen:SetTall(32)
                btnSaveGen.DoClick = function()
                    local classes = {}
                    for class, _ in pairs(generalSet) do
                        table.insert(classes, class)
                    end
                    net.Start(NET_VACCESS_SAVE)
                    net.WriteString(factionName)
                    net.WriteString("general")
                    net.WriteString("")
                    net.WriteTable(classes)
                    net.SendToServer()
                    notification.AddLegacy("Сохранено!", NOTIFY_GENERIC, 3)
                end
            end

            innerTabs:AddSheet("Фракционный транспорт", genPanel, "icon16/group.png")

            -- ── Доступ по рангам ──
            -- Для лидера показываем только транспорт из general списка фракции
            local vehiclesForRolesDepts = vehicles
            if not isSuperAdmin then
                vehiclesForRolesDepts = {}
                for _, veh in ipairs(vehicles) do
                    if generalSet[veh.class] then
                        table.insert(vehiclesForRolesDepts, veh)
                    end
                end
            end

            local rolesPanel = vgui.Create("DPanel")
            rolesPanel:SetPaintBackground(false)

            local rolesScroll = vgui.Create("DScrollPanel", rolesPanel)
            rolesScroll:Dock(FILL)
            rolesScroll:DockMargin(4, 4, 4, 4)

            if not isSuperAdmin and #vehiclesForRolesDepts == 0 then
                local emptyLbl = vgui.Create("DLabel", rolesScroll)
                emptyLbl:Dock(TOP)
                emptyLbl:SetTall(30)
                emptyLbl:DockMargin(8, 8, 8, 0)
                emptyLbl:SetText("Нет закреплённого транспорта. Попросите суперадмина назначить транспорт фракции.")
                emptyLbl:SetFont("VShop_Normal")
                emptyLbl:SetTextColor(THEME.danger)
            end

            for _, roleName in ipairs(fData.roles or {}) do
                local roleAccess = (fData.access and fData.access.roles and fData.access.roles[roleName]) or {}
                local roleSet = {}
                for _, class in ipairs(roleAccess) do roleSet[class] = true end

                local wrapper = vgui.Create("DPanel", rolesScroll)
                wrapper:Dock(TOP)
                wrapper:DockMargin(0, 4, 0, 4)
                wrapper:SetPaintBackground(false)

                local header = vgui.Create("DCollapsibleCategory", wrapper)
                header:Dock(TOP)
                header:SetLabel("▸ Ранг: " .. roleName .. " (" .. #roleAccess .. " транспорт)")
                header:SetExpanded(false)

                local innerScroll = vgui.Create("DScrollPanel", header)
                innerScroll:SetTall(200)

                for _, veh in ipairs(vehiclesForRolesDepts) do
                    local row = vgui.Create("DPanel", innerScroll)
                    row:Dock(TOP)
                    row:SetTall(24)
                    row:DockMargin(4, 0, 4, 0)
                    row:SetPaintBackground(false)

                    local chk = vgui.Create("DCheckBoxLabel", row)
                    chk:SetPos(8, 2)
                    chk:SetSize(600, 20)
                    chk:SetText(veh.name .. " [" .. veh.class .. "]")
                    chk:SetFont("VShop_Small")
                    chk:SetValue(roleSet[veh.class] or false)
                    chk.OnChange = function(_, val)
                        if val then roleSet[veh.class] = true
                        else roleSet[veh.class] = nil end
                    end
                end

                local btnSaveRole = styledButton(innerScroll, "Сохранить для «" .. roleName .. "»", THEME.accent, THEME.accentDark)
                btnSaveRole:Dock(TOP)
                btnSaveRole:SetTall(28)
                btnSaveRole:DockMargin(8, 4, 8, 4)
                btnSaveRole.DoClick = function()
                    local classes = {}
                    for class, _ in pairs(roleSet) do table.insert(classes, class) end
                    net.Start(NET_VACCESS_SAVE)
                    net.WriteString(factionName)
                    net.WriteString("role")
                    net.WriteString(roleName)
                    net.WriteTable(classes)
                    net.SendToServer()
                    notification.AddLegacy("Сохранено для ранга: " .. roleName, NOTIFY_GENERIC, 3)
                end

                wrapper:SetTall(240)
            end

            innerTabs:AddSheet("По рангам", rolesPanel, "icon16/user.png")

            -- ── Доступ по отделам ──
            local deptsPanel = vgui.Create("DPanel")
            deptsPanel:SetPaintBackground(false)

            local deptsScroll = vgui.Create("DScrollPanel", deptsPanel)
            deptsScroll:Dock(FILL)
            deptsScroll:DockMargin(4, 4, 4, 4)

            for _, deptName in ipairs(fData.departments or {}) do
                local deptAccess = (fData.access and fData.access.departments and fData.access.departments[deptName]) or {}
                local deptSet = {}
                for _, class in ipairs(deptAccess) do deptSet[class] = true end

                local wrapper = vgui.Create("DPanel", deptsScroll)
                wrapper:Dock(TOP)
                wrapper:DockMargin(0, 4, 0, 4)
                wrapper:SetPaintBackground(false)

                local header = vgui.Create("DCollapsibleCategory", wrapper)
                header:Dock(TOP)
                header:SetLabel("▸ Отдел: " .. deptName .. " (" .. #deptAccess .. " транспорт)")
                header:SetExpanded(false)

                local innerScroll = vgui.Create("DScrollPanel", header)
                innerScroll:SetTall(200)

                for _, veh in ipairs(vehicles) do
                    local row = vgui.Create("DPanel", innerScroll)
                    row:Dock(TOP)
                    row:SetTall(24)
                    row:DockMargin(4, 0, 4, 0)
                    row:SetPaintBackground(false)

                    local chk = vgui.Create("DCheckBoxLabel", row)
                    chk:SetPos(8, 2)
                    chk:SetSize(600, 20)
                    chk:SetText(veh.name .. " [" .. veh.class .. "]")
                    chk:SetFont("VShop_Small")
                    chk:SetValue(deptSet[veh.class] or false)
                    chk.OnChange = function(_, val)
                        if val then deptSet[veh.class] = true
                        else deptSet[veh.class] = nil end
                    end
                end

                local btnSaveDept = styledButton(innerScroll, "Сохранить для «" .. deptName .. "»", THEME.accent, THEME.accentDark)
                btnSaveDept:Dock(TOP)
                btnSaveDept:SetTall(28)
                btnSaveDept:DockMargin(8, 4, 8, 4)
                btnSaveDept.DoClick = function()
                    local classes = {}
                    for class, _ in pairs(deptSet) do table.insert(classes, class) end
                    net.Start(NET_VACCESS_SAVE)
                    net.WriteString(factionName)
                    net.WriteString("department")
                    net.WriteString(deptName)
                    net.WriteTable(classes)
                    net.SendToServer()
                    notification.AddLegacy("Сохранено для отдела: " .. deptName, NOTIFY_GENERIC, 3)
                end

                wrapper:SetTall(240)
            end

            innerTabs:AddSheet("По отделам", deptsPanel, "icon16/brick.png")

            tabs:AddSheet(factionName, fPanel, "icon16/group.png")
        end
    end)

    -- Результат сохранения доступа
    net.Receive(NET_VACCESS_RESULT, function()
        local ok = net.ReadBool()
        local msg = net.ReadString()
        if ok then
            notification.AddLegacy(msg, NOTIFY_GENERIC, 3)
        else
            notification.AddLegacy("Ошибка: " .. msg, NOTIFY_ERROR, 3)
        end
    end)

    -- ════════════════════════════════════════════════════════
    -- АДМИН-ПАНЕЛЬ ЦЕН
    -- ════════════════════════════════════════════════════════

    net.Receive(NET_VSHOP_ADMIN_DATA, function()
        local data = net.ReadTable() or {}
        local vehicles = data.vehicles or {}
        local prices = data.prices or {}

        local frame = vgui.Create("DFrame")
        frame:SetTitle("")
        frame:SetSize(1000, 680)
        frame:Center()
        frame:MakePopup()

        function frame:Paint(w, h)
            draw.RoundedBox(8, 0, 0, w, h, THEME.bg)
            draw.RoundedBoxEx(8, 0, 0, w, 36, Color(35, 35, 45), true, true, false, false)
            draw.SimpleText("Настройка цен магазина (SuperAdmin)", "VShop_Title", 14, 18, THEME.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end

        local infoLbl = vgui.Create("DLabel", frame)
        infoLbl:Dock(TOP)
        infoLbl:DockMargin(10, 40, 10, 4)
        infoLbl:SetTall(24)
        infoLbl:SetText("Установите цену > 0 чтобы добавить транспорт в магазин. Цена 0 = не продаётся.")
        infoLbl:SetFont("VShop_Normal")
        infoLbl:SetTextColor(THEME.textDim)

        local scroll = vgui.Create("DScrollPanel", frame)
        scroll:Dock(FILL)
        scroll:DockMargin(8, 4, 8, 44)

        -- Хранилище изменённых цен
        local editedPrices = table.Copy(prices)

        for _, veh in ipairs(vehicles) do
            local row = vgui.Create("DPanel", scroll)
            row:Dock(TOP)
            row:SetTall(36)
            row:DockMargin(0, 1, 0, 1)

            local existing = prices[veh.class]
            local hasPrice = existing and existing.price and existing.price > 0

            function row:Paint(w, h)
                draw.RoundedBox(4, 0, 0, w, h, hasPrice and Color(30, 40, 30, 200) or THEME.bgLight)
            end

            -- Название
            local lblName = vgui.Create("DLabel", row)
            lblName:SetPos(8, 8)
            lblName:SetSize(280, 20)
            lblName:SetText(veh.name)
            lblName:SetFont("VShop_Normal")
            lblName:SetTextColor(THEME.text)

            -- Класс
            local lblClass = vgui.Create("DLabel", row)
            lblClass:SetPos(300, 8)
            lblClass:SetSize(250, 20)
            lblClass:SetText(veh.class)
            lblClass:SetFont("VShop_Small")
            lblClass:SetTextColor(THEME.textDim)

            -- Категория
            local catEntry = vgui.Create("DTextEntry", row)
            catEntry:SetPos(560, 5)
            catEntry:SetSize(120, 26)
            catEntry:SetFont("VShop_Small")
            catEntry:SetText((existing and existing.category) or veh.category or "Другое")
            catEntry:SetPlaceholderText("Категория")

            -- Цена
            local priceEntry = vgui.Create("DTextEntry", row)
            priceEntry:SetPos(690, 5)
            priceEntry:SetSize(100, 26)
            priceEntry:SetFont("VShop_Normal")
            priceEntry:SetNumeric(true)
            priceEntry:SetText(tostring((existing and existing.price) or 0))
            priceEntry:SetPlaceholderText("Цена")

            priceEntry.OnChange = function()
                local p = math.floor(tonumber(priceEntry:GetText()) or 0)
                local cat = catEntry:GetText()
                if p > 0 then
                    editedPrices[veh.class] = {
                        price = p,
                        name = veh.name,
                        category = cat ~= "" and cat or "Другое",
                    }
                else
                    editedPrices[veh.class] = nil
                end
            end

            catEntry.OnChange = function()
                local p = math.floor(tonumber(priceEntry:GetText()) or 0)
                local cat = catEntry:GetText()
                if p > 0 then
                    editedPrices[veh.class] = {
                        price = p,
                        name = veh.name,
                        category = cat ~= "" and cat or "Другое",
                    }
                end
            end

            -- Индикатор "в магазине"
            if hasPrice then
                local lblInShop = vgui.Create("DLabel", row)
                lblInShop:SetPos(800, 8)
                lblInShop:SetSize(60, 20)
                lblInShop:SetText("✓")
                lblInShop:SetFont("VShop_Normal")
                lblInShop:SetTextColor(THEME.success)
            end
        end

        -- Кнопка сохранения
        local btnSave = styledButton(frame, "Сохранить все цены", THEME.success, THEME.successDark)
        btnSave:Dock(BOTTOM)
        btnSave:DockMargin(8, 4, 8, 8)
        btnSave:SetTall(36)
        btnSave.DoClick = function()
            net.Start(NET_VSHOP_ADMIN_SAVE)
            net.WriteTable(editedPrices)
            net.SendToServer()
            notification.AddLegacy("Цены сохранены!", NOTIFY_GENERIC, 3)
            frame:Close()
        end
    end)

    -- Чат-команды обрабатываются серверным хуком PlayerSay (GRM_VehicleShopCmds),
    -- который отправляет данные напрямую. Клиентский OnPlayerChat не нужен,
    -- т.к. PlayerSay возвращает "" и сообщение не доходит до клиента.

    print("[GRM] Vehicle Access System — клиент загружен")
end
