-- Boot-шим: старт подсистемы идёт через планировщик GRM.Boot (приоритеты и
-- бюджет на тик). Если планировщик почему-то не загружен, работаем по-старому.
local function grmBootStart(id, tier, fn)
    if GRM and GRM.Boot and GRM.Boot.OnMapStart then return GRM.Boot.OnMapStart(id, tier, fn) end
    return hook.Add("InitPostEntity", id, fn)
end

--[[--------------------------------------------------------------------
    GRM Prop Protect v2.0.0
    Комплексная защита пропов, объектов карты, дверей и серверного оборудования.

    • Защита объектов карты: func_door, func_door_rotating, prop_door_rotating,
      func_wall, func_brush, prop_static/dynamic и объекты, созданные картой.
    • Защита серверного оборудования: автоматы с едой (grm_vending_machine, grm_food_*),
      банкоматы, хранилища, служебные компьютеры ведомств, торговцы, АТС, телефоны, сигнализации.
    • Защита пропов игроков: изоляция по CharacterKey (чужие игроки не могут брать физганом,
      наносить урон, менять тулганом или удалять).
    • Anti-Prop-Kill & Anti-Crush: полная блокировка урона игрокам от брошенных пропов (DMG_CRUSH).
    • Админ-панель /prop_admin и консольные команды очистки (grm_cleanup_props, grm_cleanup_offline).
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.PropProtect = GRM.PropProtect or {}
local PP = GRM.PropProtect

PP.Version = "2.0.0"
PP.File    = "grm_prop_protect.json"

PP.Cfg = PP.Cfg or {
    enabled         = true,
    protectProps    = true,
    protectWorld    = true,
    protectServer   = true,
    protectDoors    = true,
    antiCrush       = true,
    ownPhysgun      = true,
    ownTool         = true,
    ownRemove       = true,
    adminAll        = true,
    maxProps        = 150,
    stableFriction  = true,
}

-- Список известных классов серверного оборудования GRM
local SERVER_CLASSES = {
    -- Автоматы с едой и кухня
    grm_vending_machine      = true,
    grm_food_stove           = true,
    grm_food_fridge          = true,
    grm_food_planter         = true,
    -- Торговцы
    grm_vendor               = true,
    -- Банковское оборудование
    grm_bank_terminal        = true,
    grm_bank_vault           = true,
    grm_bank_computer        = true,
    grm_money_press          = true,
    grm_money_press_terminal = true,
    grm_money_printer        = true,
    grm_money_launderer      = true,
    -- Служебные компьютеры ведомств
    grm_doc_computer         = true,
    grm_comp_police          = true,
    grm_comp_military_police = true,
    grm_comp_security        = true,
    grm_comp_military        = true,
    grm_comp_traffic         = true,
    grm_comp_medical         = true,
    grm_comp_education       = true,
    grm_comp_fire            = true,
    grm_comp_cityhall        = true,
    grm_comp_court           = true,
    grm_comp_public          = true,
    -- Связь и телефония
    grm_payphone             = true,
    grm_pbx_station          = true,
    grm_phone_terminal       = true,
    grm_phone_wiretap        = true,
    grm_phone                = true,
    -- Сигнализация и CCTV
    grm_alarm_sensor         = true,
    grm_alarm_hub            = true,
    grm_alarm_terminal       = true,
    grm_alarm_speaker        = true,
    grm_cctv_camera          = true,
    grm_cctv_monitor         = true,
    grm_cctv_server          = true,
    -- Биржа труда, гардероб и руды
    grm_jobcenter            = true,
    grm_depot                = true,
    grm_duty_npc             = true,
    grm_board                = true,
    grm_wardrobe             = true,
    grm_ore_node             = true,
    grm_ore_buyer            = true,
    grm_chip_terminal        = true,
    grm_scanner              = true,
    grm_keypad               = true,
    grm_roomtap_chip         = true,
    grm_roomtap_server       = true,
    grm_roomtap_terminal     = true,
}

-- Ключ персонажа — канон ядра (§5.2.6). Локальная копия убрана:
-- свой разбор слота — этим владеет GRM.Identity.ActiveSlot.
local charKey = GRM.CharKey

local function ownerOf(ent)
    if not IsValid(ent) then return "" end
    local own = ent.GRM_PropOwnerCharacterKey or ent:GetNWString("GRM_PropOwnerCharacterKey", "")
    if tostring(own or "") ~= "" then return tostring(own) end
    own = ent.GRM_EntityOwnerCharacterKey or ent:GetNWString("GRM_EntityOwnerCharacterKey", "")
    return tostring(own or "")
end

-- Проверка: объект является частью карты / дверью / брашем
function PP.IsMapEntity(ent)
    if not IsValid(ent) then return false end
    if ent:IsWorld() then return true end

    -- Создан компилятором карты (bsp)
    if ent.CreatedByMap and ent:CreatedByMap() then return true end

    local cl = string.lower(ent:GetClass() or "")
    if cl == "worldspawn" then return true end

    -- Брашевые энтити и двери карты
    if cl:sub(1, 5) == "func_" or cl == "prop_door_rotating" or cl == "prop_dynamic" or cl == "prop_static" or cl == "prop_detail" then
        return true
    end

    return false
end

-- Проверка: объект является постоянным серверным оборудованием
function PP.IsServerEntity(ent)
    if not IsValid(ent) then return false end
    -- Закреплённый объект серверный только если у него нет живого владельца
    -- (задача 9, П1). Раньше ЛЮБОЙ перм считался серверным, и после
    -- рестарта владелец терял доступ к собственной запермленной двери.
    if ent._grmPermKind ~= nil then
        return ent._grmPermKind == "server"
    end
    if ent._grmPerm == true or ent.GRMFoodPermanent == true then return true end
    if ent.GRM_EntityOwnerType == "server" or ent:GetNWString("GRM_EntityOwnerType", "") == "server" then return true end

    local cl = ent:GetClass() or ""
    if SERVER_CLASSES[cl] == true then return true end

    return false
end

function PP.MarkServerEntity(ent)
    if not IsValid(ent) then return end
    ent:SetNWString("GRM_EntityOwnerType", "server")
    ent:SetNWString("GRM_EntityOwnerName", "Сервер")
    ent.GRM_EntityOwnerType = "server"
    ent._grmPerm = true
end

function PP.IsOwnedEntity(ent)
    if not IsValid(ent) then return false end
    if PP.IsMapEntity(ent) or PP.IsServerEntity(ent) then return true end
    return ownerOf(ent) ~= ""
end

function PP.IsOwner(ply, ent)
    if not (IsValid(ply) and IsValid(ent)) then return false end
    local own = ownerOf(ent)
    return own ~= "" and own == charKey(ply)
end

local function isAdmin(ply)
    return IsValid(ply) and ply:IsPlayer() and ply:IsSuperAdmin() and (PP.Cfg.adminAll ~= false)
end

-- Централизованный определитель прав доступа к сущности
function PP.CanInteract(ply, ent, action)
    if not IsValid(ent) then return false end
    if not PP.Cfg.enabled then return true end

    -- Суперадмин имеет полный доступ ко всему
    if isAdmin(ply) then return true end

    -- 1. Объекты карты (двери, браши, здания, статичные пропы)
    if PP.IsMapEntity(ent) then
        if action == "use" then return true end -- Обычное нажатие [E] разрешено
        return false -- Все остальные действия (физган, тулган, свойства, урон) заблокированы
    end

    -- 2. Постоянное серверное оборудование (автоматы еды, банкоматы, компьютеры, торговцы)
    if PP.IsServerEntity(ent) then
        if action == "use" then return true end -- Обычное использование [E] разрешено
        return false -- Физган, тулган, свойства, удаление заблокированы для игроков
    end

    -- 2.5. Закреплённые объекты фракции/персонажа (задача 9).
    -- Удаление закреплённого объекта запрещено всем, кроме суперадмина:
    -- сначала сними перм (/permremove или R инструментом), потом удаляй.
    if ent._grmPermKind == "faction" or ent._grmPermKind == "character" then
        if action == "use" then return true end
        if action == "remove" then return false end

        local allowed = false
        if ent._grmPermKind == "character" then
            allowed = PP.IsOwner(ply, ent)
        elseif IsValid(ply) then
            local fac = ply:GetNWString("GRM_Faction", "")
            local entFac = tostring(ent.GRM_PermFaction or "")
            if entFac == "" then entFac = ent:GetNWString("GRM_PermFaction", "") end
            allowed = fac ~= "" and fac == entFac
            if allowed and GRM.FactionPerms and GRM.FactionPerms.PlayerHasPermission then
                local okP, res = pcall(GRM.FactionPerms.PlayerHasPermission, ply, "perm_manage")
                allowed = (okP and res) and true or false
            end
        end
        return allowed
    end

    -- 3. Собственные пропы игрока
    if PP.IsOwner(ply, ent) then
        if action == "physgun" then return PP.Cfg.ownPhysgun ~= false end
        if action == "tool" then return PP.Cfg.ownTool ~= false end
        if action == "remove" then return PP.Cfg.ownRemove ~= false end
        return true
    end

    -- 4. Чужие пропы или неопознанные объекты
    if action == "use" then return true end
    return false
end

local function stablePhysics(ent)
    if not PP.Cfg.stableFriction or not IsValid(ent) then return end
    local phys = ent:GetPhysicsObject()
    if not IsValid(phys) then return end
    pcall(function() phys:SetMaterial("default") end)
    pcall(function() phys:SetFriction(0.85) end)
    pcall(function() phys:SetDamping(0.05, 0.05) end)
end

-- ============================================================
-- СЕРВЕРНАЯ ЧАСТЬ
-- ============================================================
if SERVER then
    util.AddNetworkString("GRM_PropProtect_Open")
    util.AddNetworkString("GRM_PropProtect_Data")
    util.AddNetworkString("GRM_PropProtect_Save")

    local function load()
        if not file.Exists(PP.File, "DATA") then return end
        local ok, t = pcall(util.JSONToTable, file.Read(PP.File, "DATA") or "", false, true)
        if ok and istable(t) then
            for k, v in pairs(t) do PP.Cfg[k] = v end
        end
    end

    local function save()
        file.Write(PP.File, util.TableToJSON(PP.Cfg, true))
    end
    load()

    local function countProps(ply)
        local n = 0
        local key = charKey(ply)
        for _, ent in ipairs(ents.FindByClass("prop_physics")) do
            -- Закреплённые объекты не занимают личную квоту (задача 9, П5):
            -- иначе после десятка пермов игрок не может спавнить пропы вообще.
            if ownerOf(ent) == key and not ent._grmPerm then n = n + 1 end
        end
        return n
    end

    local function registerProp(ply, ent)
        if not IsValid(ply) or not IsValid(ent) then return end
        ent.GRM_PropOwnerCharacterKey = charKey(ply)
        ent.GRM_PropOwnerAccountKey = ply:SteamID64() or "0"
        ent:SetNWString("GRM_PropOwnerCharacterKey", ent.GRM_PropOwnerCharacterKey)
        ent:SetNWString("GRM_PropOwnerName", ply:GetNWString("GRM_RPName", "") ~= "" and ply:GetNWString("GRM_RPName", "") or ply:Nick())
        stablePhysics(ent)
    end

    local function registerOwnedEntity(ply, ent)
        if not IsValid(ply) or not IsValid(ent) or ent._grmPerm then return end
        ent.GRM_EntityOwnerCharacterKey = charKey(ply)
        ent.GRM_EntityOwnerAccountKey = ply:SteamID64() or "0"
        ent.GRM_EntityOwnerName = ply:GetNWString("GRM_RPName", "") ~= "" and ply:GetNWString("GRM_RPName", "") or ply:Nick()
        ent:SetNWString("GRM_EntityOwnerCharacterKey", ent.GRM_EntityOwnerCharacterKey)
        ent:SetNWString("GRM_EntityOwnerName", ent.GRM_EntityOwnerName)
    end

    hook.Add("PlayerSpawnedProp", "GRM_PropProtect_Register", function(ply, model, ent)
        if not PP.Cfg.enabled or not IsValid(ent) then return end
        if countProps(ply) >= tonumber(PP.Cfg.maxProps or 150) then
            ent:Remove()
            if GRM.Notify then GRM.Notify(ply, "Достигнут лимит пропов на персонажа (" .. tostring(PP.Cfg.maxProps or 150) .. ").", 255, 100, 100) end
            return
        end
        registerProp(ply, ent)
    end)

    hook.Add("PlayerSpawnedSENT", "GRM_PropProtect_RegisterSENT", registerOwnedEntity)
    hook.Add("PlayerSpawnedSWEP", "GRM_PropProtect_RegisterSWEP", registerOwnedEntity)
    hook.Add("PlayerSpawnedVehicle", "GRM_PropProtect_RegisterVehicle", registerOwnedEntity)

    local function cleanupDisconnectedOwner(ply)
        local ownerKey = charKey(ply)
        timer.Create("GRM_PropProtect_Disconnect_" .. string.gsub(ownerKey, "[^%w_]", "_"), 300, 1, function()
            for _, ent in ipairs(ents.GetAll()) do
                if IsValid(ent) and not ent._grmPerm and not PP.IsServerEntity(ent) and not PP.IsMapEntity(ent) and ownerOf(ent) == ownerKey then
                    ent:Remove()
                end
            end
        end)
    end

    hook.Add("PlayerDisconnected", "GRM_PropProtect_DisconnectCleanup", cleanupDisconnectedOwner)
    hook.Add("PlayerInitialSpawn", "GRM_PropProtect_CancelDisconnectCleanup", function(ply)
        local id = string.gsub(charKey(ply), "[^%w_]", "_")
        timer.Remove("GRM_PropProtect_Disconnect_" .. id)
    end)

    -- ── ХУКИ ВЗАИМОДЕЙСТВИЯ С ФИЗИКОЙ И ИНСТРУМЕНТАМИ ───────────

    hook.Add("PhysgunPickup", "GRM_PropProtect_Physgun", function(ply, ent)
        if not IsValid(ent) then return false end
        if not PP.CanInteract(ply, ent, "physgun") then
            return false
        end
        stablePhysics(ent)
        return true
    end)

    hook.Add("GravgunPickup", "GRM_PropProtect_Gravgun", function(ply, ent)
        if not IsValid(ent) then return false end
        if not PP.CanInteract(ply, ent, "gravgun") then
            return false
        end
        return true
    end)

    hook.Add("GravgunPunt", "GRM_PropProtect_GravgunPunt", function(ply, ent)
        if not IsValid(ent) then return false end
        if not PP.CanInteract(ply, ent, "gravgun") then
            return false
        end
        return true
    end)

    hook.Add("PhysgunDrop", "GRM_PropProtect_PhysgunDrop", function(_, ent)
        if IsValid(ent) then stablePhysics(ent) end
    end)

    hook.Add("CanTool", "GRM_PropProtect_Tool", function(ply, tr, tool)
        if not (tr and tr.Hit) then return false end
        local ent = tr.Entity
        if not IsValid(ent) or ent:IsWorld() then
            if IsValid(ent) and PP.IsMapEntity(ent) then
                if not (IsValid(ply) and ply:IsSuperAdmin() and PP.Cfg.adminAll) then
                    if GRM.Notify then GRM.Notify(ply, "Запрещено применять инструменты к объектам карты!", 255, 100, 100) end
                    return false
                end
            end
            return
        end

        if not PP.CanInteract(ply, ent, "tool") then
            if GRM.Notify then
                if PP.IsMapEntity(ent) then
                    GRM.Notify(ply, "Запрещено изменять объекты карты!", 255, 100, 100)
                elseif PP.IsServerEntity(ent) then
                    GRM.Notify(ply, "Запрещено изменять служебное оборудование сервера!", 255, 100, 100)
                else
                    GRM.Notify(ply, "У вас нет прав на изменение этого объекта (чужой проп).", 255, 120, 100)
                end
            end
            return false
        end
    end)

    hook.Add("CanProperty", "GRM_PropProtect_Property", function(ply, property, ent)
        if not IsValid(ent) then return false end
        if not PP.CanInteract(ply, ent, "property") then
            return false
        end
    end)

    hook.Add("CanPlayerUnfreeze", "GRM_PropProtect_Unfreeze", function(ply, ent, phys)
        if not IsValid(ent) then return false end
        if not PP.CanInteract(ply, ent, "unfreeze") then
            return false
        end
    end)

    hook.Add("EntityTakeDamage", "GRM_PropProtect_Damage", function(target, dmg)
        if not IsValid(target) then return end

        -- 1. Anti Prop-Kill: Блокировка урона игрокам от столкновения с пропом (DMG_CRUSH)
        if target:IsPlayer() and dmg:IsDamageType(DMG_CRUSH) then
            local inf = dmg:GetInflictor()
            local att = dmg:GetAttacker()
            if (IsValid(inf) and inf:GetClass() == "prop_physics") or (IsValid(att) and att:GetClass() == "prop_physics") then
                dmg:ScaleDamage(0)
                dmg:SetDamage(0)
                return true
            end
        end

        -- 2. Защита серверных автоматов, оборудования и дверей от физического разрушения
        if PP.IsServerEntity(target) or PP.IsMapEntity(target) then
            if dmg:IsDamageType(DMG_CRUSH) or dmg:IsDamageType(DMG_CLUB) then
                dmg:ScaleDamage(0)
                dmg:SetDamage(0)
                return true
            end
        end

        -- 3. Защита пропов от взаимного краш-урона
        if target:GetClass() == "prop_physics" and dmg:IsDamageType(DMG_CRUSH) then
            dmg:ScaleDamage(0)
            dmg:SetDamage(0)
            return true
        end
    end)

    -- Консольные и чат-команды очистки пропов
    local function cleanupProps(ply, onlyOffline)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        local count = 0
        local activeKeys = {}
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            activeKeys[charKey(p)] = true
        end

        for _, ent in ipairs(ents.FindByClass("prop_physics")) do
            if IsValid(ent) and not ent._grmPerm and not PP.IsServerEntity(ent) and not PP.IsMapEntity(ent) then
                local own = ownerOf(ent)
                if own ~= "" then
                    if not onlyOffline or not activeKeys[own] then
                        ent:Remove()
                        count = count + 1
                    end
                end
            end
        end

        local msg = onlyOffline and ("Очищено пропов офлайн-игроков: " .. count) or ("Очищено всех пропов игроков: " .. count)
        if IsValid(ply) then
            if GRM.Notify then GRM.Notify(ply, msg, 100, 220, 130) else ply:ChatPrint(msg) end
        else
            print("[GRM PropProtect] " .. msg)
        end
    end

    concommand.Add("grm_cleanup_props", function(ply) cleanupProps(ply, false) end)
    concommand.Add("grm_cleanup_offline", function(ply) cleanupProps(ply, true) end)

    hook.Add("PlayerSay", "GRM_PropProtect_ChatCommands", function(ply, text)
        if not (IsValid(ply) and ply:IsSuperAdmin()) then return end
        local low = string.lower(string.Trim(text or ""))
        if low == "/cleanupprops" or low == "!cleanupprops" or low == "/очиститьпропы" then
            cleanupProps(ply, false)
            return ""
        elseif low == "/cleanupoffline" or low == "!cleanupoffline" or low == "/очиститьофлайн" then
            cleanupProps(ply, true)
            return ""
        elseif low == "/prop_admin" or low == "/propprotect" or low == "/проппротект" then
            net.Start("GRM_PropProtect_Data") net.WriteTable(PP.Cfg) net.Send(ply)
            return ""
        end
    end)

    net.Receive("GRM_PropProtect_Open", function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        net.Start("GRM_PropProtect_Data") net.WriteTable(PP.Cfg) net.Send(ply)
    end)

    net.Receive("GRM_PropProtect_Save", function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        local t = net.ReadTable() or {}
        for _, k in ipairs({"enabled", "protectProps", "protectWorld", "protectServer", "protectDoors", "antiCrush", "ownPhysgun", "ownTool", "ownRemove", "adminAll", "stableFriction"}) do
            if t[k] ~= nil then PP.Cfg[k] = t[k] == true end
        end
        PP.Cfg.maxProps = math.Clamp(math.floor(tonumber(t.maxProps) or 150), 1, 1000)
        save()
        net.Start("GRM_PropProtect_Data") net.WriteTable(PP.Cfg) net.Send(ply)
        if GRM.Notify then GRM.Notify(ply, "Настройки GRM Prop Protect сохранены.", 100, 220, 130) end
    end)

    concommand.Add("grm_prop_admin", function(ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        net.Start("GRM_PropProtect_Data") net.WriteTable(PP.Cfg) net.Send(ply)
    end)

    grmBootStart("GRM_PropProtect_StabilizeExisting", "early", function()
        timer.Simple(1, function()
            for _, ent in ipairs(ents.FindByClass("prop_physics")) do
                if not PP.IsMapEntity(ent) and ownerOf(ent) ~= "" then stablePhysics(ent) end
            end
        end)
    end)
end

-- ============================================================
-- КЛИЕНТСКАЯ ЧАСТЬ
-- ============================================================
if CLIENT then
    net.Receive("GRM_PropProtect_Open", function() end)

    surface.CreateFont("GRMPP_Owner", { font = "Roboto", size = 14, weight = 700, extended = true, antialias = true })

    -- GetEyeTrace каждый кадр — заметная трассировка; троттлим до ~10 Гц.
    -- Между тиками перерисовываем кэшированный результат (метка обновляется
    -- с лёгкой задержкой, что незаметно для владельца).
    local ppHUDTrace = { at = 0, ent = nil }
        -- Палитра метки владельца: константы загрузки, не покадровые аллокации
    -- (§6.1.8). Жёлтый «сервер» и «закреплён» — один цвет на двоих.
    local COL_DEFAULT = Color(180, 190, 205)
    local COL_MAP = Color(140, 175, 220)
    local COL_GOLD = Color(245, 205, 80)
    local COL_MINE = Color(100, 230, 130)
    local COL_ONLINE = Color(150, 220, 255)
    local COL_OFFLINE = Color(220, 160, 100)
    local COL_HUD_BG = Color(12, 17, 25, 225)

hook.Add("HUDPaint", "GRM_PropProtect_OwnerHUD", function()
        local lp = LocalPlayer()
        if not IsValid(lp) then return end
        local now = CurTime()
        if now - (ppHUDTrace.at or 0) >= 0.1 then
            ppHUDTrace.at = now
            local tr = (GRM.Perf and GRM.Perf.EyeTrace) and GRM.Perf.EyeTrace(lp, 0.1) or lp:GetEyeTrace()
            ppHUDTrace.ent = tr and tr.Entity
        end
        local ent = ppHUDTrace.ent
        if not IsValid(ent) then return end

        local text = ""
        local col = COL_DEFAULT

        if PP.IsMapEntity(ent) then
            text = "Владелец: Карта (Мир)"
            col = COL_MAP
        elseif PP.IsServerEntity(ent) then
            text = "Владелец: Сервер (Оборудование)"
            col = COL_GOLD
        elseif PP.IsOwner(lp, ent) then
            text = "Владелец: Вы (Ваш проп)"
            col = COL_MINE
        elseif ownerOf(ent) ~= "" then
            local ownerKey = ownerOf(ent)
            local ownerName = ent:GetNWString("GRM_PropOwnerName", "")
            if ownerName == "" then ownerName = ent:GetNWString("GRM_EntityOwnerName", "") end
            local online = false
            for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                if IsValid(p) and GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(p) == ownerKey then
                    online = true
                    break
                end
            end
            text = "Владелец: " .. (ownerName ~= "" and ownerName or "Игрок") .. (online and "" or " (Офлайн)")
            col = online and COL_ONLINE or COL_OFFLINE
        else
            return
        end

        -- Закреплённый объект видно сразу: без метки админы удаляли пермы,
        -- не понимая, почему они возвращаются после рестарта.
        local permLine = nil
        if ent:GetNWBool("GRM_IsPerm", false) or ent._grmPerm then
            local k = ent:GetNWString("GRM_PermKind", "server")
            permLine = "★ ЗАКРЕПЛЁН НА КАРТЕ"
                .. (k == "faction" and " (фракция)" or k == "character" and " (личный)" or "")
        end

        local w, h = 310, permLine and 50 or 30
        local x, y = ScrW() - w - 18, math.floor(ScrH() * 0.32)
        draw.RoundedBox(6, x, y, w, h, COL_HUD_BG)
        if permLine then
            draw.SimpleText(text, "GRMPP_Owner", x + 12, y + 15, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(permLine, "GRMPP_Owner", x + 12, y + 35, COL_GOLD, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        else
            draw.SimpleText(text, "GRMPP_Owner", x + 12, y + h / 2, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end)

    net.Receive("GRM_PropProtect_Data", function()
        local cfg = net.ReadTable() or {}
        local f = vgui.Create("DFrame")
        f:SetTitle("GRM — Настройка системы защиты пропов (Prop Protect)")
        f:SetSize(560, 480)
        f:Center()
        f:MakePopup()
        f.Paint = function(_, w, h) draw.RoundedBox(8, 0, 0, w, h, Color(22, 26, 36)) end

        local y = 42
        local function check(text, key)
            local c = vgui.Create("DCheckBoxLabel", f)
            c:SetPos(20, y)
            c:SetSize(500, 24)
            c:SetText(text)
            c:SetValue(cfg[key] and 1 or 0)
            c.OnChange = function(_, v) cfg[key] = v end
            y = y + 26
        end

        check("Защита включена (Master Switch)", "enabled")
        check("Защищать объекты и двери карты (func_door, prop_door)", "protectWorld")
        check("Защищать серверные автоматы, оборудование и ПК", "protectServer")
        check("Защищать пропы игроков от других игроков", "protectProps")
        check("Блокировать Prop-Kill и Crush-урон игрокам", "antiCrush")
        check("Владелец может брать свои пропы физганом", "ownPhysgun")
        check("Владелец может изменять свои пропы инструментами", "ownTool")
        check("Владелец может удалять свои пропы", "ownRemove")
        check("Суперадминистраторы имеют полный доступ ко всему", "adminAll")
        check("Стабилизировать физику и трение пропов", "stableFriction")

        local n = vgui.Create("DNumberWang", f)
        n:SetPos(20, y + 8)
        n:SetSize(140, 26)
        n:SetMin(1)
        n:SetMax(1000)
        n:SetValue(cfg.maxProps or 150)

        local l = vgui.Create("DLabel", f)
        l:SetPos(170, y + 10)
        l:SetText("Лимит пропов на персонажа")
        l:SizeToContents()

        local b = vgui.Create("DButton", f)
        b:SetText("✔ Сохранить настройки")
        b:SetFont("DermaDefaultBold")
        b:SetTextColor(color_white)
        b:SetPos(20, 420)
        b:SetSize(520, 36)
        b.Paint = function(s, bw, bh) draw.RoundedBox(6, 0, 0, bw, bh, s:IsHovered() and Color(40, 160, 90) or Color(30, 130, 75)) end
        b.DoClick = function()
            cfg.maxProps = n:GetValue()
            net.Start("GRM_PropProtect_Save")
            net.WriteTable(cfg)
            net.SendToServer()
            f:Close()
        end
    end)
end

print("[GRM PropProtect] v" .. PP.Version .. " loaded")
