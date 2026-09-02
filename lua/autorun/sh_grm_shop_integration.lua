--[[--------------------------------------------------------------------
    GRM Shop Integration — Интеграция магазина с дилером

    Этот файл связывает:
      • Магазин транспорта (sh_grm_vehicle_access.lua)
      • Дилер транспорта (vehicle_dealer.lua)
      • Систему фракций (sh_factions.lua)

    Добавляет:
      • Вкладку "Транспорт" в меню фракций (/factions)
      • Автоматическое считывание транспорта на сервере
      • Проверку доступа при выдаче через дилер
--------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

-- ============================================================
-- SERVER: Интеграция с дилером
-- ============================================================

if SERVER then

    -- ── Сканирование транспорта на сервере ───────────────────────
    -- Возвращает список всех транспортных средств, зарегистрированных на сервере

    local _serverVehicleCache = nil
    local _serverVehicleCacheTime = 0
    local VEHICLE_CACHE_TTL = 30

    function GRM_ScanServerVehicles()
        local now = CurTime()
        if _serverVehicleCache and (now - _serverVehicleCacheTime) < VEHICLE_CACHE_TTL then
            return _serverVehicleCache
        end

        local result = {}
        local seen = {}

        -- Стандартные GMod транспорты
        local gmodVehicles = list.Get("Vehicles") or {}
        for class, data in pairs(gmodVehicles) do
            if not seen[class] and class ~= "" then
                seen[class] = true
                table.insert(result, {
                    class = class,
                    name = data.Name or class,
                    model = data.Model or "",
                    category = data.Category or "GMod",
                    addon = "gmod",
                })
            end
        end

        -- SimFPhys
        local sfVehicles = list.Get("simfphys_vehicles") or {}
        for class, data in pairs(sfVehicles) do
            if not seen[class] and class ~= "" then
                seen[class] = true
                table.insert(result, {
                    class = class,
                    name = data.Name or class,
                    model = data.Model or "",
                    category = data.Category or "SimFPhys",
                    addon = "simfphys",
                })
            end
        end

        -- LVS
        local lvsVehicles = list.Get("LVS_Vehicles") or {}
        for class, data in pairs(lvsVehicles) do
            if not seen[class] and class ~= "" then
                seen[class] = true
                table.insert(result, {
                    class = class,
                    name = data.Name or class,
                    model = data.Model or "",
                    category = data.Category or "LVS",
                    addon = "lvs",
                })
            end
        end

        -- Scripted entities с базой vehicle
        for class, data in pairs(scripted_ents.GetList() or {}) do
            if not seen[class] and isstring(class) then
                local base = (data and data.Base or ""):lower()
                local cls = class:lower()
                if (cls:find("glide_") == 1 or base:find("glide") or base:find("vehicle") or cls:find("vehicle"))
                    and not cls:find("wheel") and not cls:find("seat") and not cls:find("constraint") then
                    seen[class] = true
                    table.insert(result, {
                        class = class,
                        name = (data and data.PrintName) or class,
                        model = "",
                        category = cls:find("glide_") == 1 and "Glide" or "Scripted",
                        addon = cls:find("glide_") == 1 and "glide" or "generic",
                    })
                end
            end
        end

        table.sort(result, function(a, b) return (a.name or "") < (b.name or "") end)

        _serverVehicleCache = result
        _serverVehicleCacheTime = now

        return result
    end

    -- ── Хук: модификация списка транспорта дилера ────────────────
    -- Перехватываем момент, когда дилер формирует список для игрока

    hook.Add("PlayerSay", "GRM_ShopIntegration_Cmds", function(ply, text)
        local lower = string.lower(string.Trim(text))

        -- /scanvehicles — показать все транспорты на сервере (admin)
        if lower == "/scanvehicles" or lower == "!scanvehicles" then
            if not ply:IsAdmin() then
                ply:PrintMessage(HUD_PRINTTALK, "[GRM] Только для админа.")
                return ""
            end

            local vehicles = GRM_ScanServerVehicles()
            ply:ChatPrint("[GRM] Найдено транспортных средств: " .. #vehicles)

            local categories = {}
            for _, v in ipairs(vehicles) do
                local cat = v.addon or "unknown"
                categories[cat] = (categories[cat] or 0) + 1
            end
            for cat, count in pairs(categories) do
                ply:ChatPrint("  " .. cat .. ": " .. count)
            end

            return ""
        end

        -- /vlist — список доступного транспорта для игрока
        if lower == "/vlist" or lower == "!vlist" then
            if not GRM_GetAccessibleVehicles then
                ply:ChatPrint("[GRM] Система доступа не загружена.")
                return ""
            end

            local accessible = GRM_GetAccessibleVehicles(ply)

            if #accessible == 0 then
                ply:ChatPrint("[GRM] У вас нет доступного транспорта. Используйте /vshop для покупки.")
            else
                ply:ChatPrint("[GRM] Ваш доступный транспорт (" .. #accessible .. "):")
                for i, v in ipairs(accessible) do
                    local sourceText = ""
                    if v.source == "personal" then
                        sourceText = " [куплено]"
                    elseif v.source == "faction" then
                        sourceText = " [фракция]"
                    elseif v.source == "role" then
                        sourceText = " [ранг]"
                    elseif v.source == "department" then
                        sourceText = " [отдел]"
                    end
                    ply:ChatPrint("  " .. i .. ". " .. v.class .. sourceText)
                end
            end

            return ""
        end
    end)

    -- ── Периодическое обновление кеша ────────────────────────────
    timer.Create("GRM_VehicleCacheRefresh", 60, 0, function()
        _serverVehicleCache = nil -- Сбрасываем кеш
    end)

    print("[GRM] Shop Integration — загружен")
end

-- ============================================================
-- CLIENT: Вкладка "Транспорт" в меню фракций
-- ============================================================

if CLIENT then
    -- Интеграция в меню лидера фракции
    -- Добавляем вкладку "Транспорт" при открытии меню лидера

    local NET_VACCESS_OPEN = "GRM_VAccess_Open"

    -- Патчим OpenLeaderMenu для добавления вкладки транспорта
    -- Краски вкладки «Транспорт» в менеджере магазинов: Think крутит их только
-- при пересборке, но Paint кнопки — каждый кадр открытого окна; держим
-- константами загрузки (§6.1.8).
local SHOP_TAB_TEXT = Color(200, 200, 210)
local SHOP_BTN_TEXT = Color(255, 255, 255)
local SHOP_BLUE_HOVER = Color(50, 120, 200)
local SHOP_BLUE = Color(80, 160, 255)
local SHOP_GREEN_HOVER = Color(40, 160, 80)
local SHOP_GREEN = Color(60, 200, 100)

hook.Add("Think", "GRM_PatchLeaderMenu", function()
        -- Этот хук срабатывает один раз для патча
        if GRM.Perf and not GRM.Perf.Throttle("shop.leader.patch",.5)then return end
        if not OpenLeaderMenu then return end

        local _origLeaderMenu = OpenLeaderMenu

        OpenLeaderMenu = function()
            _origLeaderMenu()

            -- Добавляем вкладку после создания меню
            timer.Simple(0.3, function()
                if not IsValid(ui) or not IsValid(ui.currentFrame) then return end

                local propSheet = nil
                for _, child in ipairs(ui.currentFrame:GetChildren()) do
                    if child.ClassName == "DPropertySheet" then
                        propSheet = child
                        break
                    end
                end

                if not IsValid(propSheet) then return end

                -- Проверяем, не добавлена ли уже вкладка
                for _, sheet in ipairs(propSheet.Items or {}) do
                    if sheet.Tab and sheet.Tab:GetText() == "Транспорт" then
                        return
                    end
                end

                -- Создаём вкладку транспорта
                local transportPanel = vgui.Create("DPanel")
                transportPanel:SetPaintBackground(false)
                transportPanel:DockPadding(10, 10, 10, 10)

                local infoLbl = vgui.Create("DLabel", transportPanel)
                infoLbl:Dock(TOP)
                infoLbl:SetTall(40)
                infoLbl:SetWrap(true)
                infoLbl:SetText("Управление доступом к транспорту для вашей фракции.\nНастройте, какой транспорт доступен участникам по рангам и отделам.")
                infoLbl:SetFont("Factions_Normal")
                infoLbl:SetTextColor(SHOP_TAB_TEXT)

                local btnOpenAccess = vgui.Create("DButton", transportPanel)
                btnOpenAccess:Dock(TOP)
                btnOpenAccess:SetTall(36)
                btnOpenAccess:DockMargin(0, 10, 0, 0)
                btnOpenAccess:SetText("Открыть панель управления транспортом")
                btnOpenAccess:SetFont("Factions_Normal")
                btnOpenAccess:SetTextColor(SHOP_BTN_TEXT)
                function btnOpenAccess:Paint(w, h)
                    draw.RoundedBox(6, 0, 0, w, h, self:IsHovered() and SHOP_BLUE_HOVER or SHOP_BLUE)
                end
                btnOpenAccess.DoClick = function()
                    net.Start(NET_VACCESS_OPEN)
                    net.SendToServer()
                end

                local btnShop = vgui.Create("DButton", transportPanel)
                btnShop:Dock(TOP)
                btnShop:SetTall(36)
                btnShop:DockMargin(0, 8, 0, 0)
                btnShop:SetText("Открыть магазин транспорта")
                btnShop:SetFont("Factions_Normal")
                btnShop:SetTextColor(SHOP_BTN_TEXT)
                function btnShop:Paint(w, h)
                    draw.RoundedBox(6, 0, 0, w, h, self:IsHovered() and SHOP_GREEN_HOVER or SHOP_GREEN)
                end
                btnShop.DoClick = function()
                    net.Start("GRM_VShop_Open")
                    net.SendToServer()
                end

                propSheet:AddSheet("Транспорт", transportPanel, "icon16/car.png")
            end)
        end

        -- Убираем хук после патча
        hook.Remove("Think", "GRM_PatchLeaderMenu")
    end)

    print("[GRM] Shop Integration — клиент загружен")
end
