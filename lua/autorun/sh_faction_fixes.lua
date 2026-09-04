--[[--------------------------------------------------------------------
    Factions Extended / sh_faction_fixes.lua  v3.1.1
    Полностью исправленная версия расширения фракций:

      • Комендантский час.
      • Модели фракций / ролей / отделов с skin/bodygroups.
      • Оружие фракций / ролей / отделов.
      • Маскировка V2: подпись, модель, skin, bodygroups.
      • Исправлен выбор модели без DModelBrowser.
      • Исправлено удаление модели из списка по крестику.
      • GNewsAccess сохраняется и может использоваться только лидером, если ваш /gnews проверяет лидера.

    v3.1.1 (заказ владельца «переработать и синхронизировать расш.настройки»):
      - Вкладка «Расширенные настройки» /factions переехала с обезьяньего
        патча OpenAdminMenu (мёртвого: sh_factions грузится позже и
        перезаписывал глобал — вкладка пропадала) на хук-точку
        GRM_FactionsAdmin_BuildTabs — как мост «Доступы».
      - Синхронизация: buildSyncData теперь зеркалит Models/RoleModels/
        DepartmentModels/Weapons/RoleWeapons/DepartmentWeapons/GNewsAccess —
        вкладка показывает ЖИВЫЕ счётчики и статус ком.часа (активен/таймер/
        кем объявлен + кнопка отмены), маскировку по отделам; авто-синк
        1.5 с при любом изменении зеркал.
      - ФИКС: списки оружия из /weapons_admin не писались на диск —
        saveFactionExtras() теперь вызывается и для оружия (раньше после
        рестарта слетало).

    Зависимость:
      Основная система фракций должна создавать глобальную таблицу Factions.

    Файлы DATA:
      factions_extended.json
      fw_faction_extras.json
      default_models.json
      default_weapons.json
--------------------------------------------------------------------]]

if SERVER then
    AddCSLuaFile()
    -- Раздаём и прекэшируем kom_hour.wav ТОЛЬКО если файл реально лежит на
    -- сервере: иначе движок ругается на старте и клиенты получают битую
    -- запись в списке загрузок. Общий реестр звуков — GRM.Sound.
    if file.Exists("sound/kom_hour.wav", "GAME") then
        resource.AddFile("sound/kom_hour.wav")
        Sound("kom_hour.wav")
    else
        print("[GRM] sound/kom_hour.wav не найден — комендантский час прозвучит фолбэком (grm_sound_check покажет список)")
    end
end

GRM = GRM or {}
GRM.FactionsExt = GRM.FactionsExt or {}

-- ============================================================
-- NET STRINGS
-- ============================================================
local NET_EXT_SYNC           = "FactionsExt_Sync"
local NET_EXT_ACTION         = "FactionsExt_Action"
local NET_EXT_RESULT         = "FactionsExt_Result"
local NET_EXT_OPEN_MASK      = "FactionsExt_OpenMask"
local NET_EXT_APPLY_MASK     = "FactionsExt_ApplyMask"
local NET_EXT_REMOVE_MASK    = "FactionsExt_RemoveMask"
local NET_EXT_CURFEW         = "FactionsExt_Curfew"
local NET_CURFEW_MENU        = "GRM_Curfew_Menu"      -- запрос/выдача состояния меню
local NET_CURFEW_ACT         = "GRM_Curfew_Act"       -- объявить/остановить из меню
local NET_MODELS_SYNC        = "FactionsExt_ModelsSync"
local NET_MODELS_REQUEST     = "FactionsExt_ModelsRequest"
local NET_MODEL_SELECT       = "FactionsExt_ModelSelect"
local NET_ADMIN_MODELS_OPEN  = "FactionsExt_AdminModelsOpen"
local NET_ADMIN_MODELS_DATA  = "FactionsExt_AdminModelsData"
local NET_ADMIN_MODELS_SAVE  = "FactionsExt_AdminModelsSave"
local NET_ADMIN_WEAPONS_OPEN = "FactionsExt_AdminWeaponsOpen"
local NET_ADMIN_WEAPONS_DATA = "FactionsExt_AdminWeaponsData"
local NET_ADMIN_WEAPONS_SAVE = "FactionsExt_AdminWeaponsSave"
local NET_UPDATE_DEFAULT     = "FactionsExt_UpdateDefault"
local NET_MASK_ADMIN_OPEN    = "FactionsExt_MaskAdminOpen"
local NET_MASK_ADMIN_DATA    = "FactionsExt_MaskAdminData"
local NET_MASK_ADMIN_SAVE    = "FactionsExt_MaskAdminSave"

-- ============================================================
-- SHARED HELPERS
-- ============================================================
local EXT_FILE             = "factions_extended.json"
local EXTRAS_FILE          = "fw_faction_extras.json"
local DEFAULT_MODELS_FILE  = "default_models.json"
local DEFAULT_WEAPONS_FILE = "default_weapons.json"

local function trim(s)
    return string.Trim(tostring(s or ""))
end

local function safeLower(s)
    return string.lower(tostring(s or ""))
end

local function isModelPath(path)
    path = trim(path)
    local low = safeLower(path)
    return path ~= "" and string.StartWith(low, "models/") and string.EndsWith(low, ".mdl")
end

local function tableCopy(t)
    return istable(t) and table.Copy(t) or {}
end

local function readJSON(path, fallback)
    fallback = fallback or {}
    if not file.Exists(path, "DATA") then return tableCopy(fallback) end
    local raw = file.Read(path, "DATA") or ""
    if raw == "" then return tableCopy(fallback) end
    local ok, data = pcall(util.JSONToTable, raw)
    if ok and istable(data) then return data end
    return tableCopy(fallback)
end

local function writeJSON(path, data)
    file.Write(path, util.TableToJSON(data or {}, true))
end

local function normalizeBodygroups(bg)
    local out = {}
    if not istable(bg) then return out end
    for k, v in pairs(bg) do
        local group = tonumber(k)
        local value = tonumber(v)
        if group and value then
            out[tostring(math.floor(group))] = math.floor(value)
        end
    end
    return out
end

local function normalizeModelEntry(entry)
    if isstring(entry) then
        return {
            path = entry,
            skin = 0,
            bodygroups = {},
        }
    end
    if istable(entry) then
        return {
            path = tostring(entry.path or entry.model or entry.Model or entry[1] or "models/player/Group01/male_07.mdl"),
            skin = tonumber(entry.skin or entry.Skin) or 0,
            bodygroups = normalizeBodygroups(entry.bodygroups or entry.Bodygroups or entry.bg),
        }
    end
    return {
        path = "models/player/Group01/male_07.mdl",
        skin = 0,
        bodygroups = {},
    }
end

local function normalizeMaskEntry(entry, fallbackName)
    if isstring(entry) then
        return {
            name = fallbackName or "Маскировка",
            path = entry,
            skin = 0,
            bodygroups = {},
        }
    end
    if istable(entry) then
        return {
            name = tostring(entry.name or entry.label or entry.title or entry.Name or fallbackName or "Маскировка"),
            path = tostring(entry.path or entry.model or entry.Model or entry[1] or "models/player/Group01/male_07.mdl"),
            skin = tonumber(entry.skin or entry.Skin) or 0,
            bodygroups = normalizeBodygroups(entry.bodygroups or entry.Bodygroups or entry.bg),
        }
    end
    return {
        name = fallbackName or "Маскировка",
        path = "models/player/Group01/male_07.mdl",
        skin = 0,
        bodygroups = {},
    }
end

local function modelPathOf(entry)
    if isstring(entry) then return entry end
    if istable(entry) then return entry.path or entry.model or entry.Model or entry[1] end
    return nil
end

local function normalizeMaskDepartment(dept)
    dept = istable(dept) and dept or {}
    dept.Roles = istable(dept.Roles) and dept.Roles or {}
    dept.Models = istable(dept.Models) and dept.Models or {}
    local models = {}
    for i, entry in ipairs(dept.Models) do
        models[i] = normalizeMaskEntry(entry, "Маскировка " .. i)
    end
    dept.Models = models
    return dept
end

local function normalizeExtDefaults()
    FactionsExt = FactionsExt or {}
    for factionName, cfg in pairs(FactionsExt) do
        if istable(cfg) then
            cfg.CurfewRoles = istable(cfg.CurfewRoles) and cfg.CurfewRoles or {}
            cfg.MaskDepartments = istable(cfg.MaskDepartments) and cfg.MaskDepartments or {}
            cfg.GNewsAccess = cfg.GNewsAccess == true

            -- Миграция старого формата MaskRoles/MaskModels.
            if istable(cfg.MaskRoles) and istable(cfg.MaskModels) and #cfg.MaskModels > 0 then
                local firstDept = (Factions and Factions[factionName] and istable(Factions[factionName].Departments) and Factions[factionName].Departments[1]) or ""
                if firstDept ~= "" and not cfg.MaskDepartments[firstDept] then
                    cfg.MaskDepartments[firstDept] = {
                        Roles = cfg.MaskRoles,
                        Models = cfg.MaskModels,
                    }
                end
                cfg.MaskRoles = nil
                cfg.MaskModels = nil
            end

            for deptName, dept in pairs(cfg.MaskDepartments) do
                cfg.MaskDepartments[deptName] = normalizeMaskDepartment(dept)
            end
        end
    end
end

local function getFactionMemberByPlayer(ply)
    if not IsValid(ply) or not Factions then return nil, nil, nil, nil end
    local sid = ply:SteamID()
    local sid64 = ply:SteamID64()
    local ck = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply)) or sid64
    for factionName, f in pairs(Factions or {}) do
        if istable(f) and istable(f.Members) then
            local member = GRM.Identity.FactionMember(f, ply)
            if istable(member) then
                return factionName, member, f, sid
            end
        end
    end
    return nil, nil, nil, sid
end

local function tableHasValue(t, val)
    if not istable(t) then return false end
    for _, v in ipairs(t) do
        if v == val then return true end
    end
    return false
end

-- ============================================================
-- SERVER
-- ============================================================
if SERVER then
    util.AddNetworkString(NET_EXT_SYNC)
    util.AddNetworkString(NET_EXT_ACTION)
    util.AddNetworkString(NET_EXT_RESULT)
    util.AddNetworkString(NET_EXT_OPEN_MASK)
    util.AddNetworkString(NET_EXT_APPLY_MASK)
    util.AddNetworkString(NET_EXT_REMOVE_MASK)
    util.AddNetworkString(NET_EXT_CURFEW)
    util.AddNetworkString(NET_CURFEW_MENU)
    util.AddNetworkString(NET_CURFEW_ACT)
    util.AddNetworkString(NET_MODELS_SYNC)
    util.AddNetworkString(NET_MODELS_REQUEST)
    util.AddNetworkString(NET_MODEL_SELECT)
    util.AddNetworkString(NET_ADMIN_MODELS_OPEN)
    util.AddNetworkString(NET_ADMIN_MODELS_DATA)
    util.AddNetworkString(NET_ADMIN_MODELS_SAVE)
    util.AddNetworkString(NET_ADMIN_WEAPONS_OPEN)
    util.AddNetworkString(NET_ADMIN_WEAPONS_DATA)
    util.AddNetworkString(NET_ADMIN_WEAPONS_SAVE)
    util.AddNetworkString(NET_UPDATE_DEFAULT)
    util.AddNetworkString(NET_MASK_ADMIN_OPEN)
    util.AddNetworkString(NET_MASK_ADMIN_DATA)
    util.AddNetworkString(NET_MASK_ADMIN_SAVE)

    -- GNews leader-only integration.
    util.AddNetworkString("GNews_Send")
    util.AddNetworkString("GNews_Message")

    FactionsExt = FactionsExt or readJSON(EXT_FILE, {})
    CurfewActive = CurfewActive or false
    CurfewEndTime = CurfewEndTime or 0
    CurfewStartedBy = CurfewStartedBy or ""
    CurfewFaction = CurfewFaction or ""
    CurfewReason = CurfewReason or ""
    CurfewStartedAt = CurfewStartedAt or 0
    OriginalModels = OriginalModels or {}
    DefaultModels = DefaultModels or readJSON(DEFAULT_MODELS_FILE, {
        { path = "models/player/Group01/male_07.mdl", skin = 0, bodygroups = {} },
        { path = "models/player/Group01/male_04.mdl", skin = 0, bodygroups = {} },
    })
    for i, entry in ipairs(DefaultModels) do
        DefaultModels[i] = normalizeModelEntry(entry)
    end
    DEFAULT_WEAPONS = DEFAULT_WEAPONS or readJSON(DEFAULT_WEAPONS_FILE, {
        "weapon_physgun",
        "weapon_gravgun",
        "gmod_camera",
    })
    if not istable(DEFAULT_WEAPONS) or #DEFAULT_WEAPONS == 0 then
        DEFAULT_WEAPONS = { "weapon_physgun", "weapon_gravgun", "gmod_camera" }
    end
    normalizeExtDefaults()

    local function saveExt()
        normalizeExtDefaults()
        writeJSON(EXT_FILE, FactionsExt)
    end

    local function saveDefaultModels()
        writeJSON(DEFAULT_MODELS_FILE, DefaultModels)
    end

    local function saveDefaultWeapons()
        writeJSON(DEFAULT_WEAPONS_FILE, DEFAULT_WEAPONS)
    end

    local function saveFactionExtras()
        local out = {}
        for factionName, f in pairs(Factions or {}) do
            if istable(f) then
                out[factionName] = {
                    Models = f.Models or {},
                    RoleModels = f.RoleModels or {},
                    DepartmentModels = f.DepartmentModels or {},
                    Weapons = f.Weapons or {},
                    RoleWeapons = f.RoleWeapons or {},
                    DepartmentWeapons = f.DepartmentWeapons or {},
                    -- Наборы должностей (ось v5) — иначе после рестарта
                    -- форма начальника слетала бы, как когда-то оружие.
                    PositionModels = f.PositionModels or {},
                    PositionWeapons = f.PositionWeapons or {},
                }
            end
        end
        writeJSON(EXTRAS_FILE, out)
    end

    local function loadFactionExtras()
        if not Factions then return end
        local extras = readJSON(EXTRAS_FILE, {})
        for factionName, data in pairs(extras) do
            if Factions[factionName] and istable(data) then
                local f = Factions[factionName]
                f.Models = istable(data.Models) and data.Models or f.Models or {}
                for i, entry in ipairs(f.Models) do f.Models[i] = normalizeModelEntry(entry) end
                f.RoleModels = istable(data.RoleModels) and data.RoleModels or f.RoleModels or {}
                for _, list in pairs(f.RoleModels) do
                    if istable(list) then
                        for i, entry in ipairs(list) do list[i] = normalizeModelEntry(entry) end
                    end
                end
                f.DepartmentModels = istable(data.DepartmentModels) and data.DepartmentModels or f.DepartmentModels or {}
                for _, list in pairs(f.DepartmentModels) do
                    if istable(list) then
                        for i, entry in ipairs(list) do list[i] = normalizeModelEntry(entry) end
                    end
                end
                f.PositionModels = istable(data.PositionModels) and data.PositionModels or f.PositionModels or {}
                for _, list in pairs(f.PositionModels) do
                    if istable(list) then
                        for i, entry in ipairs(list) do list[i] = normalizeModelEntry(entry) end
                    end
                end
                f.Weapons = istable(data.Weapons) and data.Weapons or f.Weapons or {}
                f.RoleWeapons = istable(data.RoleWeapons) and data.RoleWeapons or f.RoleWeapons or {}
                f.DepartmentWeapons = istable(data.DepartmentWeapons) and data.DepartmentWeapons or f.DepartmentWeapons or {}
                f.PositionWeapons = istable(data.PositionWeapons) and data.PositionWeapons or f.PositionWeapons or {}
            end
        end
    end

    local function ensureFactionRuntimeDefaults()
        if not Factions then return false end
        for _, f in pairs(Factions) do
            if istable(f) then
                f.Models = istable(f.Models) and f.Models or {}
                f.RoleModels = istable(f.RoleModels) and f.RoleModels or {}
                f.DepartmentModels = istable(f.DepartmentModels) and f.DepartmentModels or {}
                f.Weapons = istable(f.Weapons) and f.Weapons or {}
                f.RoleWeapons = istable(f.RoleWeapons) and f.RoleWeapons or {}
                f.DepartmentWeapons = istable(f.DepartmentWeapons) and f.DepartmentWeapons or {}
                f.GNewsAccess = f.GNewsAccess == true
            end
        end
        loadFactionExtras()
        return true
    end

    local function loadExtrasWithRetry(attempt)
        attempt = attempt or 1
        if not ensureFactionRuntimeDefaults() then
            if attempt <= 30 then
                timer.Simple(0.5, function()
                    loadExtrasWithRetry(attempt + 1)
                end)
            else
                print("[Factions Extended] Factions не найдена, экстра-данные не загружены.")
            end
            return
        end
        print("[Factions Extended] Экстра-данные загружены")
    end
    loadExtrasWithRetry()

    local function sendExtResult(ply, ok, msg)
        if not IsValid(ply) then return end
        net.Start(NET_EXT_RESULT)
            net.WriteBool(ok and true or false)
            net.WriteString(msg or "")
        net.Send(ply)
    end

    local function broadcastExt()
        normalizeExtDefaults()
        -- Расширенные настройки организаций — второй по объёму пакет после
        -- снимка фракций (~10 КБ). Шлём частями, чтобы не занимать канал.
        if GRM.Net and GRM.Net.Stream then
            if GRM.Net.Stream("factions.ext", FactionsExt, nil, { chunk = 6144, interval = 0.05 }) then return end
        end
        net.Start(NET_EXT_SYNC)
            net.WriteTable(FactionsExt)
        net.Broadcast()
    end

    local function broadcastCurfew()
        net.Start(NET_EXT_CURFEW)
            net.WriteBool(CurfewActive == true)
            net.WriteFloat(tonumber(CurfewEndTime) or 0)
            net.WriteString(CurfewFaction or "")
            net.WriteString(CurfewStartedBy or "")
            net.WriteString(CurfewReason or "")
            net.WriteFloat(tonumber(CurfewStartedAt) or 0)
        net.Broadcast()
    end
    GRM.FactionsExt = GRM.FactionsExt or {}
    GRM.FactionsExt.BroadcastCurfew = broadcastCurfew

    local function getFactionDepartments(factionName)
        if not Factions or not Factions[factionName] then return {} end
        return istable(Factions[factionName].Departments) and Factions[factionName].Departments or {}
    end

    local function getExtConfig(factionName)
        FactionsExt[factionName] = FactionsExt[factionName] or {
            CurfewRoles = {},
            MaskDepartments = {},
            GNewsAccess = false,
            ChipDeathAlert = false,
        }
        local cfg = FactionsExt[factionName]
        cfg.CurfewRoles = istable(cfg.CurfewRoles) and cfg.CurfewRoles or {}
        cfg.MaskDepartments = istable(cfg.MaskDepartments) and cfg.MaskDepartments or {}
        cfg.GNewsAccess = cfg.GNewsAccess == true
        cfg.ChipDeathAlert = cfg.ChipDeathAlert == true
        return cfg
    end

    local function ensureMaskDept(factionName, deptName)
        local cfg = getExtConfig(factionName)
        cfg.MaskDepartments[deptName] = cfg.MaskDepartments[deptName] or { Roles = {}, Models = {} }
        cfg.MaskDepartments[deptName] = normalizeMaskDepartment(cfg.MaskDepartments[deptName])
        return cfg.MaskDepartments[deptName]
    end

    local function hasCurfewAccess(ply)
        local factionName, member = getFactionMemberByPlayer(ply)
        if not factionName or not member then return false end
        if ply:IsSuperAdmin() then return true end
        local cfg = getExtConfig(factionName)
        return tableHasValue(cfg.CurfewRoles, member.Role)
    end

    local function startCurfew(ply, duration, reason)
        reason = string.sub(string.Trim(tostring(reason or "")), 1, 140)
        reason = string.gsub(reason, "[%c]", "")
        CurfewActive = true
        CurfewEndTime = CurTime() + duration
        CurfewStartedAt = CurTime()
        CurfewStartedBy = IsValid(ply) and (ply:GetNWString("GRM_RPName", "") ~= "" and ply:GetNWString("GRM_RPName", "") or ply:Nick()) or "Система"
        CurfewFaction = select(1, getFactionMemberByPlayer(ply)) or ""
        CurfewReason = reason
        broadcastCurfew()
        if reason ~= "" then
            for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                if IsValid(p) then p:PrintMessage(HUD_PRINTTALK, "[Комендантский час] Причина: " .. reason) end
            end
        end
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            p:PrintMessage(HUD_PRINTCENTER, "=== ОБЪЯВЛЕН КОМЕНДАНТСКИЙ ЧАС ===\nВсе граждане должны покинуть улицы!")
            p:EmitSound("ambient/alarms/scanner_alert_pass1.wav", 100, 100)
            -- Комендантский час: kom_hour.wav — кастомный файл, которого на
            -- сервере может не быть. GRM.Sound проверяет наличие ОДИН раз и
            -- играет фолбэк вместо потока ошибок движка на каждого игрока.
            if GRM.Sound and GRM.Sound.Emit then
                GRM.Sound.Emit(p, "kom_hour.wav", 127, 110)
            else
                p:EmitSound("kom_hour.wav", 127, 110)
            end
        end
    end

    local function stopCurfew()
        CurfewActive = false
        CurfewEndTime = 0
        CurfewFaction = ""
        CurfewReason = ""
        CurfewStartedAt = 0
        broadcastCurfew()
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            p:PrintMessage(HUD_PRINTCENTER, "=== КОМЕНДАНТСКИЙ ЧАС ОТМЕНЁН ===")
        end
    end

    ----------------------------------------------------------------
    -- МЕНЮ КОМЕНДАНТСКОГО ЧАСА (/kom_hour без аргументов)
    -- Клиент не решает ничего сам: сервер отдаёт состояние + флаг доступа,
    -- и сам же валидирует каждое действие (доступ, состояние, лимиты).
    ----------------------------------------------------------------
    local CURFEW_MIN_MINUTES, CURFEW_MAX_MINUTES = 1, 120

    local function sendCurfewState(ply)
        if not IsValid(ply) then return end
        local can = ply:IsSuperAdmin() or hasCurfewAccess(ply)
        net.Start(NET_CURFEW_MENU)
            net.WriteBool(can == true)
            net.WriteBool(CurfewActive == true)
            net.WriteFloat(tonumber(CurfewEndTime) or 0)
            net.WriteFloat(tonumber(CurfewStartedAt) or 0)
            net.WriteString(CurfewStartedBy or "")
            net.WriteString(CurfewFaction or "")
            net.WriteString(CurfewReason or "")
            net.WriteUInt(CURFEW_MIN_MINUTES, 8)
            net.WriteUInt(CURFEW_MAX_MINUTES, 8)
        net.Send(ply)
    end
    GRM.FactionsExt.SendCurfewState = sendCurfewState

    -- Состояние ушло всем — обновим и открытые меню.
    local oldBroadcast = broadcastCurfew
    broadcastCurfew = function()
        oldBroadcast()
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(p) and p._grmCurfewMenuOpen then sendCurfewState(p) end
        end
    end
    GRM.FactionsExt.BroadcastCurfew = broadcastCurfew

    net.Receive(NET_CURFEW_MENU, function(bits, ply)
        if not IsValid(ply) then return end
        if GRM.Net and GRM.Net.Guard and not GRM.Net.Guard(ply, "curfew.menu", { rate = .5, burst = 3, maxBits = 64 }, { bits = bits }) then return end
        ply._grmCurfewMenuOpen = true
        sendCurfewState(ply)
    end)

    net.Receive(NET_CURFEW_ACT, function(bits, ply)
        if not IsValid(ply) then return end
        if GRM.Net and GRM.Net.Guard and not GRM.Net.Guard(ply, "curfew.act", { rate = 1, burst = 2, maxBits = 2048 }, { bits = bits }) then return end
        local act = net.ReadString()
        local minutes = net.ReadUInt(8)
        local reason = net.ReadString()

        if act == "close" then ply._grmCurfewMenuOpen = nil return end

        if not (ply:IsSuperAdmin() or hasCurfewAccess(ply)) then
            sendExtResult(ply, false, "Нет доступа к комендантскому часу")
            sendCurfewState(ply)
            return
        end

        if act == "start" then
            if CurfewActive then
                sendExtResult(ply, false, "Комендантский час уже идёт")
                sendCurfewState(ply)
                return
            end
            minutes = math.Clamp(math.floor(tonumber(minutes) or 10), CURFEW_MIN_MINUTES, CURFEW_MAX_MINUTES)
            startCurfew(ply, minutes * 60, reason)
            if GRM.Audit and GRM.Audit.Write then
                GRM.Audit.Write("curfew", "start", ply, {}, { minutes = minutes, reason = reason })
            end
            sendExtResult(ply, true, "Комендантский час объявлен на " .. minutes .. " мин.")
        elseif act == "stop" then
            if not CurfewActive then
                sendExtResult(ply, false, "Комендантский час не активен")
                sendCurfewState(ply)
                return
            end
            stopCurfew()
            if GRM.Audit and GRM.Audit.Write then
                GRM.Audit.Write("curfew", "stop", ply, {}, {})
            end
            sendExtResult(ply, true, "Комендантский час отменён")
        else
            sendCurfewState(ply)
        end
    end)

    hook.Add("PlayerDisconnected", "GRM_Curfew_MenuCleanup", function(ply) if ply then ply._grmCurfewMenuOpen = nil end end)

    function GetModelsForPlayer(ply)
        -- Сотрудник вне службы выглядит как гражданский. Этот флаг выставляет
        -- GRM.FactionDuty; без модуля поведение фракций остаётся прежним.
        if IsValid(ply) and ply:GetNWBool("GRM_FactionOffDuty", false) then return DefaultModels end
        local factionName, member, f = getFactionMemberByPlayer(ply)
        if not factionName or not f then return DefaultModels end
        --[[ Порядок выбора формы объявлен ОДИН раз в GRM.Positions:
                 должность → подотдел → отдел → ранг → организация
             Раньше он был продублирован здесь и в меню персонажа, причём
             по-разному: превью не учитывало подотдел вовсе, из-за чего
             сотрудник подотдела видел одну форму, а надевали ему другую. ]]
        if GRM.Positions and GRM.Positions.ResolveLoadout then
            local list = GRM.Positions.ResolveLoadout(f, member, "models")
            if istable(list) and #list > 0 then return list end
            return DefaultModels
        end

        -- Фолбэк на случай, если модуль должностей не загрузился.
        local role = member.Role
        local dept = member.Department
        local sub = tostring(member.Subdepartment or member.Subdept or "")
        if sub ~= "" and istable(f.Subdepartments) and istable(f.Subdepartments[sub])
            and istable(f.Subdepartments[sub].models) and #f.Subdepartments[sub].models > 0 then
            return f.Subdepartments[sub].models
        end
        if dept and dept ~= "" and istable(f.DepartmentModels) and istable(f.DepartmentModels[dept]) and #f.DepartmentModels[dept] > 0 then
            return f.DepartmentModels[dept]
        end
        if role and istable(f.RoleModels) and istable(f.RoleModels[role]) and #f.RoleModels[role] > 0 then
            return f.RoleModels[role]
        end
        if istable(f.Models) and #f.Models > 0 then return f.Models end
        return DefaultModels
    end

    function IsModelAllowedForPlayer(ply, modelPath)
        for _, entry in ipairs(GetModelsForPlayer(ply)) do
            entry = normalizeModelEntry(entry)
            if entry.path == modelPath then return true end
        end
        return false
    end

    function GetModelDataForPlayer(ply, modelPath)
        for _, entry in ipairs(GetModelsForPlayer(ply)) do
            entry = normalizeModelEntry(entry)
            if entry.path == modelPath then return entry end
        end
        return nil
    end

    local function applyStrictBodygroupsToPlayer(ply, modelData)
        if not IsValid(ply) or ply:GetNWBool("GRM_Arrested", false) then return end
        modelData = normalizeModelEntry(modelData)

        -- Если модель ещё не успела примениться или другой аддон перебил её,
        -- сначала возвращаем нужную модель.
        if modelData.path and modelData.path ~= "" and string.lower(ply:GetModel() or "") ~= string.lower(modelData.path) then
            ply:SetModel(modelData.path)
        end

        -- Строгий режим: сначала сбрасываем ВСЕ bodygroups в 0.
        -- Это убирает рандомные bodygroups от модели/игры/предыдущей маскировки.
        local count = ply:GetNumBodyGroups() or 0
        for i = 0, count - 1 do
            ply:SetBodygroup(i, 0)
        end
        ply:SetSkin(tonumber(modelData.skin) or 0)

        -- Затем применяем только явно сохранённые настройки.
        for group, value in pairs(modelData.bodygroups or {}) do
            local g = tonumber(group) or 0
            local v = tonumber(value) or 0
            ply:SetBodygroup(g, v)
        end
    end

    local function scheduleStrictModelApply(ply, modelData, reason)
        if not IsValid(ply) or ply:GetNWBool("GRM_Arrested", false) then return end
        modelData = normalizeModelEntry(modelData)
        if not modelData.path or modelData.path == "" then return end

        -- Запоминаем желаемую модель и bodygroups. Это нужно, потому что другие
        -- аддоны/PlayerSpawn могут позже сбросить skin/bodygroups или рандомизировать их.
        ply.FactionsExt_DesiredModelData = table.Copy(modelData)
        ply.FactionsExt_DesiredModelReason = reason or "unknown"
        ply.FactionsExt_DesiredModelUntil = CurTime() + 8

        -- Несколько повторных применений полностью убирают race condition после SetModel.
        local delays = { 0, 0.05, 0.15, 0.35, 0.75, 1.25, 2.0, 3.5 }
        local timerID = "FactionsExt_StrictModel_" .. ply:EntIndex() .. "_" .. math.floor(CurTime() * 1000)
        for i, delay in ipairs(delays) do
            timer.Simple(delay, function()
                if not IsValid(ply) then return end
                if ply.FactionsExt_DesiredModelData then
                    applyStrictBodygroupsToPlayer(ply, ply.FactionsExt_DesiredModelData)
                else
                    applyStrictBodygroupsToPlayer(ply, modelData)
                end
            end)
        end
    end

    function ApplyModelSettings(ply, modelData)
        if not IsValid(ply) or ply:GetNWBool("GRM_Arrested", false) then return end
        modelData = normalizeModelEntry(modelData)
        if not modelData.path or modelData.path == "" then return end
        ply:SetModel(modelData.path)
        scheduleStrictModelApply(ply, modelData, "ApplyModelSettings")
    end

    local function sendModelsToPlayer(ply)
        if not IsValid(ply) then return end
        local out = {}
        for i, entry in ipairs(GetModelsForPlayer(ply)) do
            out[i] = normalizeModelEntry(entry)
        end
        net.Start(NET_MODELS_SYNC)
            net.WriteTable(out)
        net.Send(ply)
    end

    function GetWeaponsForPlayer(ply)
        if IsValid(ply) and ply:GetNWBool("GRM_Arrested", false) then return {} end
        if IsValid(ply) and ply:GetNWBool("GRM_FactionOffDuty", false) then return DEFAULT_WEAPONS end
        local factionName, member, f = getFactionMemberByPlayer(ply)
        if not factionName or not f then return DEFAULT_WEAPONS end
        local role = member.Role
        local dept = member.Department
        local sub = member.Subdepartment
        -- Приоритет: ПОДОТДЕЛ → отдел → роль → фракция. Исторический порядок
        -- «отдел выше роли» для оружия сохранён, чтобы не менять поведение
        -- живых серверов; подотдел добавлен сверху как самый частный уровень.
        if sub and sub ~= "" and istable(f.Subdepartments) and istable(f.Subdepartments[sub])
            and istable(f.Subdepartments[sub].weapons) and #f.Subdepartments[sub].weapons > 0 then
            return f.Subdepartments[sub].weapons
        end
        if dept and istable(f.DepartmentWeapons) and istable(f.DepartmentWeapons[dept]) and #f.DepartmentWeapons[dept] > 0 then
            return f.DepartmentWeapons[dept]
        end
        if role and istable(f.RoleWeapons) and istable(f.RoleWeapons[role]) and #f.RoleWeapons[role] > 0 then
            return f.RoleWeapons[role]
        end
        if istable(f.Weapons) and #f.Weapons > 0 then return f.Weapons end
        return DEFAULT_WEAPONS
    end

    function ApplyWeaponsToPlayer(ply)
        if not IsValid(ply) then return end
        ply:StripWeapons()
        --[[ Персонаж ещё не выбран — игрок сидит в лимбе за картой, и
             оружия у него быть не должно вообще (заказ владельца 22.08).
             Набор из /weapons_admin выдаётся только после подтверждения
             персонажа и появления на точке спавна. ]]
        if ply:GetNWBool("GRM_CharacterPending", false) then
            if ply.RemoveAllAmmo then ply:RemoveAllAmmo() end
            return
        end
        if ply:GetNWBool("GRM_Arrested", false) then
            if ply.RemoveAllAmmo then ply:RemoveAllAmmo() end
            return
        end
        for _, class in ipairs(GetWeaponsForPlayer(ply)) do
            if isstring(class) and class ~= "" then
                ply:Give(class)
            end
        end
    end

    local function applyUniformForCharacter(key)
        key = tostring(key or "")
        if key == "" then return end
        local ply
        if GRM.Identity and GRM.Identity.ResolveCharacter then
            ply = GRM.Identity.ResolveCharacter(key)
        end
        if not IsValid(ply) then
            for _, p in ipairs(player.GetAll()) do
                local ck = GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(p)
                if ck == key then ply = p break end
            end
        end
        if not IsValid(ply) or not ply:Alive() then return end
        if ply:GetNWBool("GRM_CharacterPending", false) then return end
        if ply:GetNWBool("IsMasked", false) then return end
        if ply:GetNWBool("GRM_Arrested", false) then return end
        local fname, member = getFactionMemberByPlayer(ply)
        if fname and member then
            ply:SetNWString("GRM_Department", tostring(member.Department or ""))
            ply:SetNWString("GRM_Subdepartment", tostring(member.Subdepartment or member.Subdept or ""))
        end
        local list = GetModelsForPlayer(ply)
        local entry = istable(list) and list[1] and normalizeModelEntry(list[1]) or nil
        if entry and entry.path ~= "" then
            ply.FactionsExt_DesiredModelData = nil
            ApplyModelSettings(ply, entry)
            if GRM.Char and isfunction(GRM.Char.ApplyAppearance) then
                pcall(GRM.Char.ApplyAppearance, ply, { path = entry.path, skin = entry.skin, bodygroups = entry.bodygroups })
            end
        end
        ApplyWeaponsToPlayer(ply)
        sendModelsToPlayer(ply)
    end

    hook.Add("GRM_FactionMemberDepartmentChanged", "FactionsExt_ApplyDeptUniform", function(_, key)
        timer.Simple(0, function() applyUniformForCharacter(key) end)
    end)
    hook.Add("GRM_FactionMemberSubdepartmentChanged", "FactionsExt_ApplySubUniform", function(_, key)
        timer.Simple(0, function() applyUniformForCharacter(key) end)
    end)
    hook.Add("GRM_FactionMemberRoleChanged", "FactionsExt_ApplyRoleUniform", function(_, key)
        timer.Simple(0, function() applyUniformForCharacter(key) end)
    end)
    hook.Add("GRM_FactionMemberJoined", "FactionsExt_ApplyJoinUniform", function(_, key)
        timer.Simple(0.1, function() applyUniformForCharacter(key) end)
    end)

    local function applyWeaponsToTargetGroup(targetFaction, targetRole, targetDept, targetSub)
        for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(ply) then
                local factionName, member = getFactionMemberByPlayer(ply)
                if targetFaction and targetFaction ~= "" and factionName == targetFaction then
                    local roleMatch = (not targetRole or targetRole == "") or (member and member.Role == targetRole)
                    local deptMatch = (not targetDept or targetDept == "") or (member and member.Department == targetDept)
                    local subMatch = (not targetSub or targetSub == "") or (member and member.Subdepartment == targetSub)
                    if roleMatch and deptMatch and subMatch then
                        ApplyWeaponsToPlayer(ply)
                    end
                elseif not targetFaction or targetFaction == "" then
                    ApplyWeaponsToPlayer(ply)
                end
            end
        end
    end

    local function getAvailableMasks(ply)
        local factionName, member = getFactionMemberByPlayer(ply)
        if not factionName or not member then return nil, {} end
        local cfg = getExtConfig(factionName)
        local available = {}
        for deptName, dept in pairs(cfg.MaskDepartments or {}) do
            dept = normalizeMaskDepartment(dept)
            if tableHasValue(dept.Roles, member.Role) and #dept.Models > 0 then
                available[deptName] = dept.Models
            end
        end
        return factionName, available
    end

    local function applyMask(ply, entry)
        if not IsValid(ply) then return end
        entry = normalizeMaskEntry(entry)
        if not ply.FactionsExt_OriginalModel then
            ply.FactionsExt_OriginalModel = ply:GetModel()
        end
        ply.FactionsExt_MaskEntry = table.Copy(entry)
        ply:SetNWBool("IsMasked", true)
        ply:SetNWString("MaskModel", entry.path or "")
        ply:SetNWString("MaskName", entry.name or "")
        ply:SetNWString("GRM_MaskDesc", ply:GetNWString("GRM_MaskDesc", ""))
        ApplyModelSettings(ply, entry)
    end

    local function removeMask(ply)
        if not IsValid(ply) then return end
        ply:SetNWBool("IsMasked", false)
        ply:SetNWString("MaskModel", "")
        ply:SetNWString("MaskName", "")
        ply:SetNWString("GRM_MaskDesc", "")
        ply.FactionsExt_MaskEntry = nil
        local factionName = getFactionMemberByPlayer(ply)
        if factionName then
            local list = GetModelsForPlayer(ply)
            if list and list[1] then
                ApplyModelSettings(ply, list[1])
                return
            end
        end
        if ply.FactionsExt_OriginalModel then
            ply:SetModel(ply.FactionsExt_OriginalModel)
        end
        ply.FactionsExt_OriginalModel = nil
    end

    local function sendMaskMenu(ply)
        local factionName, available = getAvailableMasks(ply)
        if not factionName then
            ply:PrintMessage(HUD_PRINTTALK, "[Маскировка] Вы не состоите во фракции.")
            return
        end
        if table.Count(available or {}) <= 0 then
            ply:PrintMessage(HUD_PRINTTALK, "[Маскировка] Нет доступной маскировки для вашего ранга.")
            return
        end
        net.Start(NET_EXT_OPEN_MASK)
            net.WriteString(factionName)
            net.WriteTable(available)
        net.Send(ply)
    end

    net.Receive(NET_MODELS_REQUEST, function(_, ply)
        sendModelsToPlayer(ply)
    end)

    net.Receive(NET_MODEL_SELECT, function(_, ply)
        local modelPath = net.ReadString()
        if ply:GetNWBool("IsMasked", false) then
            ply:PrintMessage(HUD_PRINTTALK, "Сначала снимите маскировку (/mask off).")
            return
        end
        if IsModelAllowedForPlayer(ply, modelPath) then
            ApplyModelSettings(ply, GetModelDataForPlayer(ply, modelPath))
            ply:PrintMessage(HUD_PRINTTALK, "[Модель] Модель выбрана.")
        else
            ply:PrintMessage(HUD_PRINTTALK, "[Модель] Эта модель вам недоступна.")
        end
    end)

    net.Receive(NET_EXT_APPLY_MASK, function(_, ply)
        local deptName = net.ReadString()
        local index = net.ReadUInt(12)
        local _, available = getAvailableMasks(ply)
        local list = available and available[deptName]
        local entry = istable(list) and list[index] or nil
        if not istable(entry) then
            ply:PrintMessage(HUD_PRINTTALK, "[Маскировка] Эта маскировка недоступна.")
            return
        end
        applyMask(ply, entry)
        ply:PrintMessage(HUD_PRINTTALK, "[Маскировка] Применена: " .. (entry.name or entry.path or "модель"))
    end)

    net.Receive(NET_EXT_REMOVE_MASK, function(_, ply)
        removeMask(ply)
        ply:PrintMessage(HUD_PRINTTALK, "[Маскировка] Снята.")
    end)

    --[[ Структура фракции для админ-меню экипировки: роли, отделы И ПОДОТДЕЛЫ
         вместе с публичными названиями. Раньше меню /models_admin и
         /weapons_admin знали только про роли и отделы, хотя Faction Core v5
         давно ввёл иерархию «Отдел ➔ Подотдел», и у подотдела есть
         собственные списки моделей и оружия. ]]
    local function factionStructureFor(f, factionName, kind)
        local roleNames, deptNames = {}, {}
        for _, key in ipairs(f.Roles or {}) do
            roleNames[key] = GRM.Factions and GRM.Factions.RoleDisplayName
                and GRM.Factions.RoleDisplayName(f, key) or key
        end
        for _, key in ipairs(f.Departments or {}) do
            deptNames[key] = GRM.Factions and GRM.Factions.DepartmentDisplayName
                and GRM.Factions.DepartmentDisplayName(f, key) or key
        end

        local subs, subList = {}, {}
        for subKey, sub in pairs(istable(f.Subdepartments) and f.Subdepartments or {}) do
            if istable(sub) then
                local list = (kind == "weapons") and sub.weapons or sub.models
                subs[subKey] = istable(list) and list or {}
                subList[#subList + 1] = {
                    id = subKey,
                    name = tostring(sub.name or subKey),
                    parent = tostring(sub.parentDept or ""),
                }
            end
        end
        table.sort(subList, function(a, b)
            if a.parent ~= b.parent then return a.parent < b.parent end
            return a.name < b.name
        end)

        --[[ ДОЛЖНОСТИ (ось v5). Своя форма должности была доступна только
             из кода: в дереве редактора её не было. Теперь узел должности
             стоит рядом со своим подразделением, а списки лежат в
             f.PositionModels / f.PositionWeapons. ]]
        local posStore = (kind == "weapons") and f.PositionWeapons or f.PositionModels
        posStore = istable(posStore) and posStore or {}
        local positions, posList = {}, {}
        if GRM.Positions and GRM.Positions.List then
            for _, pos in ipairs(GRM.Positions.List(f)) do
                positions[pos.id] = istable(posStore[pos.id]) and posStore[pos.id] or {}
                posList[#posList + 1] = {
                    id = pos.id,
                    name = pos.name,
                    node = pos.node,
                    kind = pos.kind,
                    kindName = (GRM.Positions.KindName or {})[pos.kind] or pos.kind,
                    nodeName = GRM.Positions.NodeDisplayName(f, pos.node),
                }
            end
        end

        return {
            displayName = GRM.Factions and GRM.Factions.DisplayName and GRM.Factions.DisplayName(factionName) or factionName,
            rolesList = f.Roles or {},
            deptsList = f.Departments or {},
            roleNames = roleNames,
            deptNames = deptNames,
            subList = subList,
            subdepartments = subs,
            posList = posList,
            positions = positions,
        }
    end

    net.Receive(NET_ADMIN_MODELS_OPEN, function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        loadFactionExtras()
        local data = { factions = {}, default = DefaultModels }
        for factionName, f in pairs(Factions or {}) do
            local st = factionStructureFor(f, factionName, "models")
            data.factions[factionName] = {
                general = f.Models or {},
                roles = f.RoleModels or {},
                departments = f.DepartmentModels or {},
                subdepartments = st.subdepartments,
                positions = st.positions,
                posList = st.posList,
                rolesList = st.rolesList,
                deptsList = st.deptsList,
                subList = st.subList,
                roleNames = st.roleNames,
                deptNames = st.deptNames,
                displayName = st.displayName,
            }
        end
        net.Start(NET_ADMIN_MODELS_DATA)
            net.WriteTable(data)
        net.Send(ply)
    end)

    --[[ ОСИ СНАРЯЖЕНИЯ (фракция / роль / отдел / подотдел / должность).

         Одни и те же пять веток были написаны ДВАЖДЫ — отдельно для
         моделей и отдельно для оружия. Это ровно тот случай, о котором
         говорил владелец: условие про отдел и подотдел пишется по новой
         вместо одной общей проверки. Цена уже проявилась: у подотдела
         модели сохранялись на диск (FactionsAPI.Save), а оружие — нет,
         хотя лежит там же, в factions.json; после рестарта оружие
         подотдела пропадало.

         Ось описывает: куда класть список (`field` по виду снаряжения),
         как класть (`store`), нужно ли писать factions.json (`persist`)
         и кому пере-выдать оружие (`targets`).
    ]]
    local LOADOUT_AXES = {
        faction = {
            field = { models = "Models", weapons = "Weapons" },
            targets = function(factionName) return factionName, nil, nil, nil end,
        },
        role = {
            field = { models = "RoleModels", weapons = "RoleWeapons" },
            keyed = true,
            targets = function(factionName, key) return factionName, key, nil, nil end,
        },
        department = {
            field = { models = "DepartmentModels", weapons = "DepartmentWeapons" },
            keyed = true,
            targets = function(factionName, key) return factionName, nil, key, nil end,
        },
        subdepartment = {
            -- Списки подотдела живут внутри самой записи подотдела
            -- (f.Subdepartments[key].models/.weapons), как их читает
            -- GetSubdepartments; это часть factions.json, поэтому persist.
            persist = true,
            targets = function(factionName, key) return factionName, nil, nil, key end,
            store = function(f, kind, key, list)
                f.Subdepartments = istable(f.Subdepartments) and f.Subdepartments or {}
                if not istable(f.Subdepartments[key]) then return false end
                f.Subdepartments[key][kind] = list
                return true
            end,
        },
        position = {
            -- Форма должности: самая точная в порядке ResolveLoadout.
            field = { models = "PositionModels", weapons = "PositionWeapons" },
            keyed = true,
            persist = true,
            validate = function(f, key)
                return GRM.Positions ~= nil and GRM.Positions.Get ~= nil
                    and GRM.Positions.Get(f, key) ~= nil
            end,
        },
    }

    --[[ Записать список снаряжения по оси.
         kind — "models" или "weapons". Возвращает ok, причину отказа. ]]
    local function storeLoadout(kind, f, saveType, key, list)
        local axis = LOADOUT_AXES[saveType]
        if not axis then return false end
        if axis.validate and not axis.validate(f, key) then return false, "not_found" end

        if axis.store then
            if not axis.store(f, kind, key, list) then return false end
        else
            local field = axis.field[kind]
            if axis.keyed then
                f[field] = istable(f[field]) and f[field] or {}
                f[field][key] = list
            else
                f[field] = list
            end
        end

        if axis.persist and FactionsAPI and FactionsAPI.Save then pcall(FactionsAPI.Save) end
        return true
    end

    net.Receive(NET_ADMIN_MODELS_SAVE, function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        local saveType = net.ReadString()
        local factionName = net.ReadString()
        local key = net.ReadString()
        local models = net.ReadTable() or {}
        for i, entry in ipairs(models) do
            models[i] = normalizeModelEntry(entry)
        end

        if saveType == "default" then
            DefaultModels = models
            saveDefaultModels()
            net.Start(NET_UPDATE_DEFAULT)
                net.WriteString("models")
                net.WriteTable(DefaultModels)
            net.Send(ply)
            ply:PrintMessage(HUD_PRINTTALK, "[Модели] Стандартные модели обновлены.")
            return
        end

        if not Factions or not Factions[factionName] then return end
        local f = Factions[factionName]
        local ok, why = storeLoadout("models", f, saveType, key, models)
        if not ok then
            if why == "not_found" then
                ply:PrintMessage(HUD_PRINTTALK, "[Модели] Должность не найдена.")
            end
            return
        end

        saveFactionExtras()
        if broadcastFactionData then pcall(broadcastFactionData) end
        ply:PrintMessage(HUD_PRINTTALK, "[Модели] Сохранено.")
    end)

    net.Receive(NET_ADMIN_WEAPONS_OPEN, function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        loadFactionExtras()
        local data = { factions = {}, default = DEFAULT_WEAPONS }
        for factionName, f in pairs(Factions or {}) do
            local st = factionStructureFor(f, factionName, "weapons")
            data.factions[factionName] = {
                general = f.Weapons or {},
                roles = f.RoleWeapons or {},
                departments = f.DepartmentWeapons or {},
                subdepartments = st.subdepartments,
                positions = st.positions,
                posList = st.posList,
                rolesList = st.rolesList,
                deptsList = st.deptsList,
                subList = st.subList,
                roleNames = st.roleNames,
                deptNames = st.deptNames,
                displayName = st.displayName,
            }
        end
        net.Start(NET_ADMIN_WEAPONS_DATA)
            net.WriteTable(data)
        net.Send(ply)
    end)

    net.Receive(NET_ADMIN_WEAPONS_SAVE, function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        local saveType = net.ReadString()
        local factionName = net.ReadString()
        local key = net.ReadString()
        local weapons = net.ReadTable() or {}

        if saveType == "default" then
            DEFAULT_WEAPONS = weapons
            saveDefaultWeapons()
            net.Start(NET_UPDATE_DEFAULT)
                net.WriteString("weapons")
                net.WriteTable(DEFAULT_WEAPONS)
            net.Send(ply)
            ply:PrintMessage(HUD_PRINTTALK, "[Оружие] Стандартное оружие обновлено.")
            return
        end

        if not Factions or not Factions[factionName] then return end
        local f = Factions[factionName]
        local ok, why = storeLoadout("weapons", f, saveType, key, weapons)
        if not ok then
            if why == "not_found" then
                ply:PrintMessage(HUD_PRINTTALK, "[Оружие] Должность не найдена.")
            end
            return
        end

        -- Оружие, в отличие от моделей, надо пере-выдать тем, кто уже в игре.
        local axis = LOADOUT_AXES[saveType]
        if axis.targets then
            applyWeaponsToTargetGroup(axis.targets(factionName, key))
        end

        -- фикс v3.1.1: оружейные списки раньше НЕ сохранялись на диск
        -- (только модели) — после рестарта слетали; пишем в fw_faction_extras.json
        saveFactionExtras()
        if broadcastFactionData then pcall(broadcastFactionData) end
        ply:PrintMessage(HUD_PRINTTALK, "[Оружие] Сохранено.")
    end)

    local function buildMaskAdminData()
        local out = {}
        normalizeExtDefaults()
        for factionName, f in pairs(Factions or {}) do
            if istable(f) then
                out[factionName] = {
                    Roles = f.Roles or {},
                    Departments = f.Departments or {},
                    MaskDepartments = {},
                }
                local cfg = getExtConfig(factionName)
                for deptName, dept in pairs(cfg.MaskDepartments or {}) do
                    out[factionName].MaskDepartments[deptName] = normalizeMaskDepartment(dept)
                end
            end
        end
        return out
    end

    net.Receive(NET_MASK_ADMIN_OPEN, function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        net.Start(NET_MASK_ADMIN_DATA)
            net.WriteTable(buildMaskAdminData())
        net.Send(ply)
    end)

    net.Receive(NET_MASK_ADMIN_SAVE, function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        local factionName = trim(net.ReadString())
        local deptName = trim(net.ReadString())
        local deptData = net.ReadTable() or {}

        if not Factions or not Factions[factionName] then
            sendExtResult(ply, false, "Фракция не найдена")
            return
        end
        if not tableHasValue(Factions[factionName].Departments or {}, deptName) then
            sendExtResult(ply, false, "Отдел не найден")
            return
        end

        local clean = { Roles = {}, Models = {} }
        for _, role in ipairs(deptData.Roles or {}) do
            if role ~= "" then table.insert(clean.Roles, role) end
        end
        for i, entry in ipairs(deptData.Models or {}) do
            entry = normalizeMaskEntry(entry, "Маскировка " .. i)
            if isModelPath(entry.path) then table.insert(clean.Models, entry) end
        end

        local cfg = getExtConfig(factionName)
        cfg.MaskDepartments[deptName] = clean
        saveExt()
        sendExtResult(ply, true, "Маскировка сохранена: " .. factionName .. " / " .. deptName)
        broadcastExt()
    end)

    -- Проверка лидерства в конкретной фракции (для доступов, открытых лидерам).
    -- Тело когда-то было копией экспорта sh_grm_faction_perms; имя разбираем
    -- при вызове, потому что fixes грузится раньше perms (§5.4 п.12).
    local function isLeaderOfFaction(ply, factionName)
        local m = GRM.FactionPerms
        return (m and m.IsLeaderOfFaction and m.IsLeaderOfFaction(ply, factionName)) == true
    end

    net.Receive(NET_EXT_ACTION, function(_, ply)
        if not IsValid(ply) then return end
        local action = net.ReadString()
        local args = net.ReadTable() or {}

        -- Комендантский час: доступ суперадмину и ролям с допуском (/kom_hour).
        -- Обрабатывается ДО гейта «только суперадмин», чтобы лидеры могли
        -- объявлять/снимать ком.час прямо из меню фракций.
        if action == "startCurfew" then
            if not ply:IsSuperAdmin() and not hasCurfewAccess(ply) then
                sendExtResult(ply, false, "Нет доступа к комендантскому часу")
                return
            end
            local duration = math.Clamp(tonumber(args[1]) or 600, 60, 7200)
            startCurfew(ply, duration, args[2])
            sendExtResult(ply, true, "Комендантский час объявлен на " .. math.floor(duration / 60) .. " мин.")
            return
        end

        if action == "stopCurfew" then
            if not ply:IsSuperAdmin() and not hasCurfewAccess(ply) then
                sendExtResult(ply, false, "Нет доступа к комендантскому часу")
                return
            end
            if CurfewActive then
                stopCurfew()
                sendExtResult(ply, true, "Комендантский час отменён")
            else
                sendExtResult(ply, false, "Не активен")
            end
            return
        end

        -- Госновости (/gnews): суперадмин или лидер СВОЕЙ фракции.
        -- Вынесено до гейта «только суперадмин», чтобы лидеры могли
        -- переключать доступ к госновостям своей организации.
        if action == "setGNewsAccess" then
            local fname = trim(args[1])
            if fname == "" or not Factions or not Factions[fname] then
                sendExtResult(ply, false, "Фракция не найдена")
                return
            end
            if not ply:IsSuperAdmin() and not isLeaderOfFaction(ply, fname) then
                sendExtResult(ply, false, "Недостаточно прав")
                return
            end
            if GRM.MenuAccess and GRM.MenuAccess.PlayerCan
                and not GRM.MenuAccess.PlayerCan(ply, "access", fname) then
                sendExtResult(ply, false, "Раздел доступов закрыт администрацией")
                return
            end
            local enabled = args[2] and true or false
            local cfg = getExtConfig(fname)
            cfg.GNewsAccess = enabled
            Factions[fname].GNewsAccess = enabled
            saveExt()
            local factionsFromFile = readJSON("factions.json", Factions or {})
            if factionsFromFile[fname] then
                factionsFromFile[fname].GNewsAccess = enabled
                writeJSON("factions.json", factionsFromFile)
            end
            broadcastExt()
            if broadcastFactionData then pcall(broadcastFactionData) end
            sendExtResult(ply, true, enabled and "Доступ к /gnews выдан лидеру фракции" or "Доступ к /gnews снят")
            return
        end

        if not ply:IsSuperAdmin() then return end

        local factionName = trim(args[1])

        if factionName == "" or not Factions or not Factions[factionName] then
            sendExtResult(ply, false, "Фракция не найдена")
            return
        end

        local cfg = getExtConfig(factionName)

        if action == "toggleCurfewRole" then
            local role = trim(args[2])
            if role == "" then sendExtResult(ply, false, "Не указана роль") return end
            for i, r in ipairs(cfg.CurfewRoles) do
                if r == role then
                    table.remove(cfg.CurfewRoles, i)
                    saveExt()
                    broadcastExt()
                    sendExtResult(ply, true, "Доступ к /kom_hour снят: " .. role)
                    return
                end
            end
            table.insert(cfg.CurfewRoles, role)
            saveExt()
            broadcastExt()
            sendExtResult(ply, true, "Доступ к /kom_hour выдан: " .. role)
            return
        end

        if action == "toggleDeptRole" then
            local deptName = trim(args[2])
            local role = trim(args[3])
            if deptName == "" or role == "" then sendExtResult(ply, false, "Не указан отдел или роль") return end
            local dept = ensureMaskDept(factionName, deptName)
            for i, r in ipairs(dept.Roles) do
                if r == role then
                    table.remove(dept.Roles, i)
                    saveExt()
                    broadcastExt()
                    sendExtResult(ply, true, deptName .. ": доступ снят с роли " .. role)
                    return
                end
            end
            table.insert(dept.Roles, role)
            saveExt()
            broadcastExt()
            sendExtResult(ply, true, deptName .. ": доступ выдан роли " .. role)
            return
        end

        if action == "addDeptModel" then
            local deptName = trim(args[2])
            local modelArg = args[3]
            local modelPath = trim(modelPathOf(modelArg))
            if deptName == "" or modelPath == "" then sendExtResult(ply, false, "Не указан отдел или модель") return end
            local dept = ensureMaskDept(factionName, deptName)
            for _, entry in ipairs(dept.Models) do
                if modelPathOf(entry) == modelPath then
                    sendExtResult(ply, false, "Модель уже добавлена")
                    return
                end
            end
            table.insert(dept.Models, normalizeMaskEntry(modelArg, "Маскировка " .. (#dept.Models + 1)))
            saveExt()
            broadcastExt()
            sendExtResult(ply, true, deptName .. ": модель добавлена")
            return
        end

        if action == "removeDeptModel" then
            local deptName = trim(args[2])
            local modelPath = trim(modelPathOf(args[3]))
            if deptName == "" or modelPath == "" then sendExtResult(ply, false, "Не указан отдел или модель") return end
            local dept = ensureMaskDept(factionName, deptName)
            for i = #dept.Models, 1, -1 do
                if trim(modelPathOf(dept.Models[i])) == modelPath then
                    table.remove(dept.Models, i)
                    saveExt()
                    broadcastExt()
                    sendExtResult(ply, true, deptName .. ": модель удалена")
                    return
                end
            end
            sendExtResult(ply, false, deptName .. ": модель не найдена")
            return
        end

        -- Контроль чипов (находка 169): уведомлять членов фракции о смерти
        -- носителей экспериментальных чипов (звук+текст+GPS-метка)
        if action == "setChipDeathAlert" then
            local enabled = args[2] and true or false
            cfg.ChipDeathAlert = enabled
            saveExt()
            broadcastExt()
            sendExtResult(ply, true, enabled and "Уведомления о смерти носителей экспериментальных чипов ВКЛЮЧЕНЫ для «" .. factionName .. "»" or "Уведомления о смерти носителей экспериментальных чипов ВЫКЛЮЧЕНЫ для «" .. factionName .. "»")
            return
        end

        sendExtResult(ply, false, "Неизвестное действие: " .. tostring(action))
    end)

    hook.Add("PlayerSpawn", "FactionsExt_FullSetup", function(ply)
        timer.Simple(0.15, function()
            if not IsValid(ply) then return end
            if ply:GetNWBool("IsMasked", false) and ply.FactionsExt_MaskEntry then
                ApplyModelSettings(ply, ply.FactionsExt_MaskEntry)
            else
                local desired = ply.FactionsExt_DesiredModelData
                local models = GetModelsForPlayer(ply)
                if istable(desired) and desired.path and desired.path ~= ""
                    and IsModelAllowedForPlayer(ply, desired.path) then
                    ApplyModelSettings(ply, desired)
                elseif models and models[1] then
                    ApplyModelSettings(ply, models[1])
                end
            end
            ApplyWeaponsToPlayer(ply)
        end)
    end)

    hook.Add("PlayerInitialSpawn", "FactionsExt_OnJoin", function(ply)
        timer.Simple(3, function()
            if not IsValid(ply) then return end
            sendModelsToPlayer(ply)
            broadcastExt()
            broadcastCurfew()
            ApplyWeaponsToPlayer(ply)
        end)
        timer.Simple(10, function()
            if IsValid(ply) then ApplyWeaponsToPlayer(ply) end
        end)
    end)

    hook.Add("PlayerDisconnected", "FactionsExt_Cleanup", function(ply)
        OriginalModels[ply:SteamID()] = nil
        ply.FactionsExt_OriginalModel = nil
        ply.FactionsExt_MaskEntry = nil
    end)

    timer.Create("FactionsExt_CurfewCheck", 5, 0, function()
        if CurfewActive and CurfewEndTime > 0 and CurTime() >= CurfewEndTime then
            stopCurfew()
        end
    end)

    local function getAllowedModelEntryForCurrentPlayerModel(ply, models)
        if not IsValid(ply) or not istable(models) then return nil end
        local current = string.lower(ply:GetModel() or "")
        for _, entry in ipairs(models) do
            entry = normalizeModelEntry(entry)
            if string.lower(entry.path or "") == current then
                return entry
            end
        end
        return nil
    end

    timer.Create("FactionsExt_ModelCheck", 2, 0, function()
        for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(ply) and ply:Alive() then
                if ply:GetNWBool("IsMasked", false) then
                    -- Маскировка должна строго держать свои skin/bodygroups.
                    if ply.FactionsExt_MaskEntry then
                        applyStrictBodygroupsToPlayer(ply, ply.FactionsExt_MaskEntry)
                    end
                else
                    local models = GetModelsForPlayer(ply)
                    if istable(models) and models[1] then
                        local allowedCurrent = getAllowedModelEntryForCurrentPlayerModel(ply, models)
                        if allowedCurrent then
                    -- Не сбиваем модель, но строго возвращаем её сохранённые bodygroups.
                    -- Если игрок выбирал модель через /model, предпочтительнее его сохранённые настройки.
                    local desired = ply.FactionsExt_DesiredModelData
                    if desired and string.lower(desired.path or "") == string.lower(ply:GetModel() or "") then
                        applyStrictBodygroupsToPlayer(ply, desired)
                    else
                        applyStrictBodygroupsToPlayer(ply, allowedCurrent)
                    end
                else
                            -- Текущая модель не разрешена — ставим первую доступную.
                            ApplyModelSettings(ply, models[1])
                        end
                    end
                end
            end
        end
    end)

    timer.Simple(1, function()
        local oldBroadcast = broadcastFactionData
        broadcastFactionData = function()
            saveFactionExtras()
            if oldBroadcast then pcall(oldBroadcast) end
            broadcastExt()
        end
    end)

    local function handleMaskChatCommand(ply, text)
        local lower = safeLower(trim(text))

        if lower == "/mask" or lower == "!mask" then
            sendMaskMenu(ply)
            return true
        end

        if lower == "/mask off" or lower == "!mask off" then
            removeMask(ply)
            ply:PrintMessage(HUD_PRINTTALK, "[Маскировка] Снята.")
            return true
        end

        return false
    end

    -- ВАЖНО: обработчик объявлен ниже по файлу, поэтому здесь нужна
    -- форвард-декларация. Без неё замыкание хука читало ГЛОБАЛЬНУЮ
    -- переменную (nil) и падало при первом же сообщении в EasyChat:
    -- "attempt to call global 'handleCurfewChat' (a nil value)".
    local handleCurfewChat

    hook.Add("PlayerSay", "FactionsExt_CurfewCommands", function(ply, text, teamSays)
        local datapack = { tostring(text or ""), SkipPlayerSay = false }
            if not istable(datapack) or not isstring(datapack[1]) then return end
            if not handleCurfewChat(ply, datapack[1]) then return end
            datapack[1] = ""
            datapack.SkipPlayerSay = true

        if datapack.SkipPlayerSay == true then return "" end
    end)

    hook.Add("PlayerSay", "FactionsExt_MaskCommands", function(ply, text, teamSays)
        local datapack = { tostring(text or ""), SkipPlayerSay = false }
            if not istable(datapack) or not isstring(datapack[1]) then return end
            if not handleMaskChatCommand(ply, datapack[1]) then return end
            datapack[1] = ""
            datapack.SkipPlayerSay = true

        if datapack.SkipPlayerSay == true then return "" end
    end)

    -- Комендантский час доступен и через PlayerSay, и через PlayerSayTransform
    -- (правило сборки: EasyChat перехватывает ввод и обычный PlayerSay может
    -- не сработать). Обе точки входа зовут ОДИН обработчик.
    handleCurfewChat = function(ply, text)
        local lower = safeLower(trim(text))
        -- Русский алиас: длина «/комчас» в БАЙТАХ — 13, safeLower кириллицу
        -- не трогает, поэтому сравниваем исходную строку.
        local rawTrim = trim(text)
        local komPrefix = nil
        if string.sub(lower, 1, 9) == "/kom_hour" then komPrefix = 9
        elseif string.sub(rawTrim, 1, 13) == "/комчас" then komPrefix = 13 end
        if not komPrefix then return false end
        local arg = trim(string.sub(rawTrim, komPrefix + 1))
        -- Без аргументов — открываем меню (кнопки, ползунок, причина).
        if arg == "" then
            if not ply:IsSuperAdmin() and not hasCurfewAccess(ply) then
                ply:PrintMessage(HUD_PRINTTALK, "[Комендантский час] Нет доступа.")
                return true
            end
            ply._grmCurfewMenuOpen = true
            -- Тот же пакет состояния, что и у кнопки «Обновить» в меню:
            -- один источник правды, никакого дублирования полей.
            sendCurfewState(ply)
            return true
        end
        if safeLower(arg) == "off" then
            if not ply:IsSuperAdmin() and not hasCurfewAccess(ply) then
                ply:PrintMessage(HUD_PRINTTALK, "[Комендантский час] Нет доступа к отмене.")
                return true
            end
            if not CurfewActive then
                ply:PrintMessage(HUD_PRINTTALK, "[Комендантский час] Не активен.")
                return true
            end
            stopCurfew()
            return true
        end
        if not ply:IsSuperAdmin() and not hasCurfewAccess(ply) then
            ply:PrintMessage(HUD_PRINTTALK, "[Комендантский час] Нет доступа.")
            return true
        end
        -- «/kom_hour 15» — минуты (совместимость со старым «/kom_hour 900»
        -- в секундах сохранена: значения больше 120 считаем секундами).
        local num = tonumber(arg)
        local duration
        if num and num > 0 and num <= 120 then duration = num * 60 else duration = num or 600 end
        duration = math.Clamp(duration, 60, 7200)
        startCurfew(ply, duration)
        ply:PrintMessage(HUD_PRINTTALK, "[Комендантский час] Объявлен на " .. math.floor(duration / 60) .. " мин. Меню: /kom_hour без аргументов.")
        return true
    end

    hook.Add("PlayerSay", "FactionsExt_Commands", function(ply, text)
        local lower = safeLower(trim(text))

        if handleMaskChatCommand(ply, text) then return "" end

        if handleCurfewChat(ply, text) then return "" end

        if lower:sub(1, 10) == "/maskdesc " or lower:sub(1, 10) == "!maskdesc " then
            if not ply:GetNWBool("IsMasked", false) then
                ply:PrintMessage(HUD_PRINTTALK, "[Маскировка] Сначала наденьте маскировку: /mask")
                return ""
            end
            local desc = string.Trim(text:sub(11))
            desc = string.gsub(desc, "[%c]", "")
            desc = string.sub(desc, 1, 180)
            ply:SetNWString("GRM_MaskDesc", desc)
            ply:PrintMessage(HUD_PRINTTALK, desc ~= "" and "[Маскировка] Описание установлено." or "[Маскировка] Описание очищено.")
            return ""
        end

        if lower == "/maskdesc" or lower == "!maskdesc" then
            ply:PrintMessage(HUD_PRINTTALK, "[Маскировка] Установить описание: /maskdesc текст")
            return ""
        end

        if lower == "/model" then
            sendModelsToPlayer(ply)
            return ""
        end

        if lower == "!refreshweapons" then
            if ply:IsAdmin() or ply:IsSuperAdmin() then
                ApplyWeaponsToPlayer(ply)
                ply:PrintMessage(HUD_PRINTTALK, "[Оружие] Обновлено согласно вашей роли/фракции.")
            else
                ply:PrintMessage(HUD_PRINTTALK, "[Оружие] У вас нет прав.")
            end
            return ""
        end
    end)

    -- ============================================================
    -- GNEWS: доступ только лидеру фракции с включённым GNewsAccess
    -- ============================================================
    local function isFactionLeader(ply, f)
        if not IsValid(ply) or not istable(f) then return false end
        local ck = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply)) or ply:SteamID64()
        if f.Leader and f.Leader == ck then return true end
        local member = f.Members and GRM.Identity.FactionMember(f, ply)
        local leaderRole = f.LeaderRoleName or "Лидер"
        return istable(member) and (member.Role == leaderRole or member.Role == "Лидер")
    end

    local function hasGNewsAccess(ply)
        if not IsValid(ply) then return false, nil, nil end
        if ply:IsSuperAdmin() then
            local factionName, _, f = getFactionMemberByPlayer(ply)
            return true, factionName, f
        end
        local factionName, member, f = getFactionMemberByPlayer(ply)
        if not factionName or not f then return false, nil, nil end
        if f.GNewsAccess ~= true then return false, factionName, f end
        if not isFactionLeader(ply, f) then return false, factionName, f end
        return true, factionName, f
    end

    local function installGNewsReceiver()
        net.Receive("GNews_Send", function(_, ply)
            if not IsValid(ply) then return end
            local ok, factionName, f = hasGNewsAccess(ply)
            if not ok then
                if f and f.GNewsAccess == true then
                    ply:PrintMessage(HUD_PRINTTALK, "[GNews] /gnews доступен только лидеру вашей фракции.")
                else
                    ply:PrintMessage(HUD_PRINTTALK, "[GNews] У вашей фракции нет доступа к государственным новостям.")
                end
                return
            end

            local text = trim(net.ReadString())
            if text == "" then return end

            factionName = factionName or "Гос. новости"
            f = f or {}
            local tag = GRM.Factions and GRM.Factions.DisplayName and GRM.Factions.DisplayName(factionName) or factionName
            local rpName = ply:GetNWString("GRM_RPName", "")
            if rpName == "" then rpName = ply:Nick() end
            local member = f.Members and GRM.Identity and GRM.Identity.FactionMember and GRM.Identity.FactionMember(f, ply)
            local roleKey = (member and member.Role) or f.LeaderRoleName or "Лидер"
            local role = GRM.Factions and GRM.Factions.RoleDisplayName and GRM.Factions.RoleDisplayName(f, roleKey) or roleKey
            local color = f.Color or { r = 255, g = 200, b = 50 }

            net.Start("GNews_Message")
                net.WriteUInt(tonumber(color.r) or 255, 8)
                net.WriteUInt(tonumber(color.g) or 200, 8)
                net.WriteUInt(tonumber(color.b) or 50, 8)
                net.WriteString(tag)
                net.WriteString(rpName)
                net.WriteString(role)
                net.WriteString(text)
            net.Broadcast()

            file.Append("gnews_log.txt", os.date("%Y-%m-%d %H:%M:%S") .. " " .. rpName .. " (" .. ply:SteamID() .. "): " .. text .. "\n")
            print("[GNews] [" .. tag .. "]\n" .. rpName .. " (" .. role .. "): " .. text)
        end)
    end
    installGNewsReceiver()
    timer.Create("FactionsExt_GNews_LeaderOnly_Reinstall", 1, 10, installGNewsReceiver)

    hook.Add("PlayerSay", "FactionsExt_GNews_ServerChat", function(ply, text)
        if not IsValid(ply) then return end
        local trimmed = string.Trim(tostring(text or ""))
        if string.sub(trimmed:lower(), 1, 7) == "/gnews " then
            local msg = string.Trim(string.sub(trimmed, 8))
            if msg ~= "" then
                local ok, factionName, f = hasGNewsAccess(ply)
                if not ok then
                    if f and f.GNewsAccess == true then
                        ply:PrintMessage(HUD_PRINTTALK, "[GNews] /gnews доступен только лидеру вашей фракции.")
                    else
                        ply:PrintMessage(HUD_PRINTTALK, "[GNews] У вашей фракции нет доступа к государственным новостям.")
                    end
                    return ""
                end
                factionName = factionName or "Гос. новости"
                f = f or {}
                local tag = GRM.Factions and GRM.Factions.DisplayName and GRM.Factions.DisplayName(factionName) or factionName
                local rpName = ply:GetNWString("GRM_RPName", "")
                if rpName == "" then rpName = ply:Nick() end
                local member = f.Members and GRM.Identity and GRM.Identity.FactionMember and GRM.Identity.FactionMember(f, ply)
                local roleKey = (member and member.Role) or f.LeaderRoleName or "Лидер"
                local role = GRM.Factions and GRM.Factions.RoleDisplayName and GRM.Factions.RoleDisplayName(f, roleKey) or roleKey
                local color = f.Color or { r = 255, g = 200, b = 50 }

                net.Start("GNews_Message")
                    net.WriteUInt(tonumber(color.r) or 255, 8)
                    net.WriteUInt(tonumber(color.g) or 200, 8)
                    net.WriteUInt(tonumber(color.b) or 50, 8)
                    net.WriteString(tag)
                    net.WriteString(rpName)
                    net.WriteString(role)
                    net.WriteString(msg)
                net.Broadcast()
                file.Append("gnews_log.txt", os.date("%Y-%m-%d %H:%M:%S") .. " " .. rpName .. " (" .. ply:SteamID() .. "): " .. msg .. "\n")
                print("[GNews] [" .. tag .. "]\n" .. rpName .. " (" .. role .. "): " .. msg)
            end
            return ""
        end
    end)

    timer.Simple(5, function()
        ensureFactionRuntimeDefaults()
        for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(ply) then
                ApplyWeaponsToPlayer(ply)
                sendModelsToPlayer(ply)
            end
        end
        broadcastExt()
    end)

    print("[Factions Extended] Server loaded: models/weapons/mask-v2/curfew/gnews fixes")
end

-- ============================================================
-- CLIENT
-- ============================================================
if CLIENT then
    FactionsExtData = FactionsExtData or {}
    CurfewState = CurfewState or { active = false, endTime = 0, faction = "" }
    -- Ссылки на открытые окна модуля. Локально: глобальное имя `ui`
    -- пересекалось с таким же в sh_factions и в чужих аддонах.
    local ui = {}

    surface.CreateFont("FactionsExt_Title", { font = "Roboto", size = 20, weight = 700, extended = true, antialias = true })
    surface.CreateFont("FactionsExt_Normal", { font = "Roboto", size = 14, weight = 500, extended = true, antialias = true })
    surface.CreateFont("FactionsExt_Small", { font = "Roboto", size = 12, weight = 400, extended = true, antialias = true })

    local THEME = {
        bg = Color(25, 25, 30, 245),
        bgLight = Color(35, 35, 42, 240),
        panel = Color(30, 35, 48, 240),
        bgHover = Color(50, 50, 60, 250),
        accent = Color(80, 160, 255),
        accentDark = Color(50, 120, 200),
        text = Color(220, 220, 230),
        textDim = Color(150, 150, 165),
        success = Color(60, 200, 100),
        danger = Color(220, 60, 60),
        warning = Color(255, 180, 50),
        deptBg = Color(30, 35, 50, 240),
    }

    -- ------------------------------------------------------------
    -- DModelBrowser fallback
    -- ------------------------------------------------------------
    if not (vgui.GetControlTable and vgui.GetControlTable("DModelBrowser")) then
        local PANEL = {}
        local COMMON_MODEL_DIRS = {
            "models/player/*.mdl",
            "models/player/*/*.mdl",
            "models/player/*/*/*.mdl",
            "models/humans/group01/*.mdl",
            "models/humans/group02/*.mdl",
            "models/humans/group03/*.mdl",
            "models/humans/group03m/*.mdl",
            "models/police*.mdl",
            "models/combine*.mdl",
        }

        local function collectModels()
            local out, seen = {}, {}
            local function add(path)
                path = string.Replace(tostring(path or ""), "\\", "/")
                if path == "" or seen[path] or not string.EndsWith(safeLower(path), ".mdl") then return end
                seen[path] = true
                out[#out + 1] = path
            end
            for _, pattern in ipairs(COMMON_MODEL_DIRS) do
                local files = file.Find(pattern, "GAME")
                local dir = string.GetPathFromFilename(pattern)
                for _, name in ipairs(files or {}) do add(dir .. name) end
            end
            for _, path in ipairs({
                "models/player/Group01/male_07.mdl",
                "models/player/Group01/male_04.mdl",
                "models/player/police.mdl",
                "models/player/combine_soldier.mdl",
            }) do add(path) end
            table.sort(out)
            return out
        end

        function PANEL:Init()
            self.Models = collectModels()
            self:DockPadding(6, 6, 6, 6)

            self.Search = vgui.Create("DTextEntry", self)
            self.Search:Dock(TOP)
            self.Search:SetTall(28)
            self.Search:SetPlaceholderText("Поиск или ручной путь models/...mdl")

            self.Manual = vgui.Create("DButton", self)
            self.Manual:Dock(TOP)
            self.Manual:SetTall(26)
            self.Manual:DockMargin(0, 4, 0, 4)
            self.Manual:SetText("Выбрать введённый путь")
            self.Manual.DoClick = function()
                local path = trim(self.Search:GetText())
                if isModelPath(path) then self:SelectModel(path) end
            end

            self.Scroll = vgui.Create("DScrollPanel", self)
            self.Scroll:Dock(FILL)

            self.Search.OnChange = function() self:Rebuild() end
            self:Rebuild()
        end

        function PANEL:SelectModel(path)
            if self.OnSelect then self:OnSelect(path, path) end
        end

        function PANEL:Rebuild()
            self.Scroll:Clear()
            local filter = safeLower(trim(self.Search:GetText()))
            local shown = 0
            for _, path in ipairs(self.Models) do
                if filter == "" or string.find(safeLower(path), filter, 1, true) then
                    shown = shown + 1
                    if shown > 250 then break end

                    local row = self.Scroll:Add("DPanel")
                    row:Dock(TOP)
                    row:SetTall(70)
                    row:DockMargin(0, 0, 0, 5)
                    row.Paint = function(_, w, h) draw.RoundedBox(5, 0, 0, w, h, THEME.bgLight) end

                    local preview = vgui.Create("DModelPanel", row)
                    preview:Dock(LEFT)
                    preview:SetWide(70)
                    preview:SetModel(path)
                    preview:SetCamPos(Vector(55, 0, 50))
                    preview:SetLookAt(Vector(0, 0, 45))
                    preview.LayoutEntity = function() end

                    local label = vgui.Create("DLabel", row)
                    label:Dock(FILL)
                    label:SetText(path)
                    label:SetTextColor(THEME.text)

                    local btn = vgui.Create("DButton", row)
                    btn:Dock(RIGHT)
                    btn:SetWide(86)
                    btn:SetText("Выбрать")
                    btn.DoClick = function() self:SelectModel(path) end
                end
            end
        end

        vgui.Register("DModelBrowser", PANEL, "DPanel")
    end

    local function styledButton(parent, text, color, hoverColor, textColor)
        local btn = vgui.Create("DButton", parent)
        btn:SetText(text)
        btn:SetFont("FactionsExt_Normal")
        btn:SetTextColor(textColor or color_white)
        btn.Paint = function(s, w, h)
            local c = s:IsHovered() and (hoverColor or THEME.accentDark) or (color or THEME.accent)
            draw.RoundedBox(5, 0, 0, w, h, c)
        end
        return btn
    end

    local function sectionLabel(parent, title)
        local panel = vgui.Create("DPanel", parent)
        panel:Dock(TOP)
        panel:SetTall(30)
        panel:DockMargin(0, 8, 0, 4)
        panel.Paint = function(_, w, h)
            surface.SetDrawColor(55, 55, 70, 255)
            surface.DrawRect(0, h - 1, w, 1)
            draw.SimpleText(title, "FactionsExt_Normal", 4, h / 2, THEME.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        return panel
    end

    local function bodygroupsToText(bg)
        if not istable(bg) then return "" end
        local out = {}
        for k, v in pairs(bg) do out[#out + 1] = tostring(k) .. "=" .. tostring(v) end
        table.sort(out)
        return table.concat(out, ",")
    end

    local function parseBodygroupsText(text)
        local out = {}
        for part in string.gmatch(trim(text), "[^,]+") do
            local k, v = string.match(part, "^%s*(%d+)%s*=%s*(%d+)%s*$")
            if k and v then out[tostring(tonumber(k))] = tonumber(v) end
        end
        return out
    end

    local function applyModelPanelSettings(panel, entry)
        if not IsValid(panel) then return end
        local ent = panel:GetEntity()
        if not IsValid(ent) then return end
        entry = normalizeModelEntry(entry)

        -- Строго сбрасываем все bodygroups в предпросмотре, иначе DModelPanel/модель
        -- может показывать случайные значения.
        for i = 0, (ent:GetNumBodyGroups() or 0) - 1 do
            ent:SetBodygroup(i, 0)
        end
        ent:SetSkin(tonumber(entry.skin) or 0)
        for group, value in pairs(entry.bodygroups or {}) do
            ent:SetBodygroup(tonumber(group) or 0, tonumber(value) or 0)
        end
    end

    local function openBodygroupsEditor(initial, callback)
        local entry = normalizeMaskEntry(initial or {})
        entry.bodygroups = table.Copy(entry.bodygroups or {})

        local frame = vgui.Create("DFrame")
        frame:SetTitle("Изменить bodygroups — " .. (entry.name or "Маскировка"))
        frame:SetSize(820, 620)
        frame:Center()
        frame:MakePopup()

        local left = vgui.Create("DPanel", frame)
        left:Dock(LEFT)
        left:SetWide(360)
        left:DockMargin(8, 8, 8, 48)
        left:SetPaintBackground(false)

        local right = vgui.Create("DPanel", frame)
        right:Dock(FILL)
        right:DockMargin(0, 8, 8, 48)
        right:SetPaintBackground(false)

        local info = vgui.Create("DLabel", left)
        info:Dock(TOP)
        info:SetTall(58)
        info:SetWrap(true)
        info:SetFont("FactionsExt_Small")
        info:SetTextColor(THEME.text)
        info:SetText((entry.name or "Маскировка") .. "\n" .. (entry.path or ""))

        local skinSlider = vgui.Create("DNumSlider", left)
        skinSlider:Dock(TOP)
        skinSlider:SetTall(38)
        skinSlider:SetText("Skin")
        skinSlider:SetMin(0)
        skinSlider:SetMax(32)
        skinSlider:SetDecimals(0)
        skinSlider:SetValue(tonumber(entry.skin) or 0)

        local hint = vgui.Create("DLabel", left)
        hint:Dock(TOP)
        hint:SetTall(42)
        hint:SetWrap(true)
        hint:SetText("Двигайте ползунки bodygroups. Предпросмотр обновляется справа.")
        hint:SetTextColor(THEME.textDim)
        hint:SetFont("FactionsExt_Small")

        local scroll = vgui.Create("DScrollPanel", left)
        scroll:Dock(FILL)
        scroll:DockMargin(0, 6, 0, 0)

        local modelPanel = vgui.Create("DModelPanel", right)
        modelPanel:Dock(FILL)
        modelPanel:SetModel(entry.path)
        modelPanel:SetCamPos(Vector(80, 0, 55))
        modelPanel:SetLookAt(Vector(0, 0, 45))
        modelPanel.LayoutEntity = function() end

        local function applyPreview()
            applyModelPanelSettings(modelPanel, entry)
        end

        local function rebuildSliders()
            scroll:Clear()
            local ent = modelPanel:GetEntity()
            if not IsValid(ent) then return end
            skinSlider:SetMax(math.max((ent:SkinCount() or 1) - 1, 0))
            for i = 0, ent:GetNumBodyGroups() - 1 do
                local count = ent:GetBodygroupCount(i) or 0
                if count > 1 then
                    local row = vgui.Create("DPanel", scroll)
                    row:Dock(TOP)
                    row:SetTall(54)
                    row:DockMargin(0, 0, 0, 6)
                    row.Paint = function(_, w, h) draw.RoundedBox(5, 0, 0, w, h, THEME.bgLight) end
                    local slider = vgui.Create("DNumSlider", row)
                    slider:Dock(FILL)
                    slider:SetText((ent:GetBodygroupName(i) or "bodygroup") .. " [" .. i .. "]")
                    slider:SetMin(0)
                    slider:SetMax(count - 1)
                    slider:SetDecimals(0)
                    slider:SetValue(tonumber(entry.bodygroups[tostring(i)]) or 0)
                    slider.OnValueChanged = function(_, val)
                        val = math.Round(val)
                        entry.bodygroups[tostring(i)] = val
                        ent:SetBodygroup(i, val)
                    end
                end
            end
            applyPreview()
        end

        skinSlider.OnValueChanged = function(_, val)
            entry.skin = math.Round(val)
            applyPreview()
        end

        timer.Simple(0.1, function()
            if IsValid(frame) then rebuildSliders() end
        end)

        local bottom = vgui.Create("DPanel", frame)
        bottom:Dock(BOTTOM)
        bottom:SetTall(44)
        bottom:SetPaintBackground(false)

        local saveBtn = styledButton(bottom, "Применить bodygroups", THEME.success)
        saveBtn:Dock(LEFT)
        saveBtn:SetWide(190)
        saveBtn:DockMargin(8, 6, 4, 6)
        saveBtn.DoClick = function()
            callback(table.Copy(entry))
            frame:Close()
        end

        local resetBtn = styledButton(bottom, "Сбросить", THEME.danger)
        resetBtn:Dock(LEFT)
        resetBtn:SetWide(110)
        resetBtn:DockMargin(4, 6, 4, 6)
        resetBtn.DoClick = function()
            entry.skin = 0
            entry.bodygroups = {}
            skinSlider:SetValue(0)
            rebuildSliders()
        end
    end

    local function openModelPicker(callback)
        local frame = vgui.Create("DFrame")
        frame:SetTitle("Выбор модели")
        frame:SetSize(700, 560)
        frame:Center()
        frame:MakePopup()

        local browser = vgui.Create("DModelBrowser", frame)
        browser:Dock(FILL)
        browser.OnSelect = function(_, path)
            callback(path)
            frame:Close()
        end
    end

    local function openModelEntryEditor(initial, callback, isMask)
        local entry = isMask and normalizeMaskEntry(initial or {}) or normalizeModelEntry(initial or {})

        local frame = vgui.Create("DFrame")
        frame:SetTitle(isMask and "Редактор маскировки" or "Редактор модели")
        frame:SetSize(760, 560)
        frame:Center()
        frame:MakePopup()

        local left = vgui.Create("DPanel", frame)
        left:Dock(LEFT)
        left:SetWide(360)
        left:DockMargin(8, 8, 8, 48)
        left:SetPaintBackground(false)

        local right = vgui.Create("DPanel", frame)
        right:Dock(FILL)
        right:DockMargin(0, 8, 8, 48)
        right:SetPaintBackground(false)

        local nameEntry
        if isMask then
            nameEntry = vgui.Create("DTextEntry", left)
            nameEntry:Dock(TOP)
            nameEntry:SetTall(28)
            nameEntry:SetPlaceholderText("Подпись: Военная Полиция / Комитет / Врачи")
            nameEntry:SetText(entry.name or "")
        end

        local pathEntry = vgui.Create("DTextEntry", left)
        pathEntry:Dock(TOP)
        pathEntry:SetTall(28)
        pathEntry:DockMargin(0, 6, 0, 0)
        pathEntry:SetPlaceholderText("models/player/...")
        pathEntry:SetText(entry.path or "")

        local browseBtn = styledButton(left, "Выбрать модель", THEME.accent)
        browseBtn:Dock(TOP)
        browseBtn:SetTall(28)
        browseBtn:DockMargin(0, 6, 0, 0)

        local skinEntry = vgui.Create("DNumberWang", left)
        skinEntry:Dock(TOP)
        skinEntry:SetTall(28)
        skinEntry:DockMargin(0, 6, 0, 0)
        skinEntry:SetMin(0)
        skinEntry:SetMax(64)
        skinEntry:SetValue(tonumber(entry.skin) or 0)

        local bgEntry = vgui.Create("DTextEntry", left)
        bgEntry:Dock(TOP)
        bgEntry:SetTall(28)
        bgEntry:DockMargin(0, 6, 0, 0)
        bgEntry:SetPlaceholderText("bodygroups: 0=1,1=2")
        bgEntry:SetText(bodygroupsToText(entry.bodygroups))

        local modelPanel = vgui.Create("DModelPanel", right)
        modelPanel:Dock(FILL)
        modelPanel:SetModel(entry.path or "models/player/Group01/male_07.mdl")
        modelPanel:SetCamPos(Vector(80, 0, 55))
        modelPanel:SetLookAt(Vector(0, 0, 45))
        modelPanel.LayoutEntity = function() end

        local function currentEntry()
            local e = {
                path = trim(pathEntry:GetText()),
                skin = tonumber(skinEntry:GetValue()) or 0,
                bodygroups = parseBodygroupsText(bgEntry:GetText()),
            }
            if isMask then e.name = trim(nameEntry:GetText()) ~= "" and trim(nameEntry:GetText()) or "Маскировка" end
            return e
        end

        local function refreshPreview()
            local e = currentEntry()
            if isModelPath(e.path) then modelPanel:SetModel(e.path) end
            timer.Simple(0.05, function() applyModelPanelSettings(modelPanel, e) end)
        end

        browseBtn.DoClick = function()
            openModelPicker(function(path)
                pathEntry:SetText(path)
                refreshPreview()
            end)
        end

        local bgBtn = styledButton(left, "Изменить бодигруппы отдельным окном", Color(110, 120, 210))
        bgBtn:Dock(TOP)
        bgBtn:SetTall(30)
        bgBtn:DockMargin(0, 6, 0, 0)
        bgBtn.DoClick = function()
            local e = currentEntry()
            if not isModelPath(e.path) then notification.AddLegacy("Сначала укажите модель .mdl", NOTIFY_ERROR, 3) return end
            openBodygroupsEditor(e, function(updated)
                skinEntry:SetValue(updated.skin or 0)
                bgEntry:SetText(bodygroupsToText(updated.bodygroups))
                refreshPreview()
            end)
        end

        pathEntry.OnEnter = refreshPreview
        bgEntry.OnEnter = refreshPreview
        skinEntry.OnValueChanged = refreshPreview

        local bottom = vgui.Create("DPanel", frame)
        bottom:Dock(BOTTOM)
        bottom:SetTall(44)
        bottom:SetPaintBackground(false)

        local saveBtn = styledButton(bottom, "Сохранить", THEME.success)
        saveBtn:Dock(LEFT)
        saveBtn:SetWide(140)
        saveBtn:DockMargin(8, 6, 4, 6)
        saveBtn.DoClick = function()
            local e = currentEntry()
            if not isModelPath(e.path) then notification.AddLegacy("Укажите корректную модель .mdl", NOTIFY_ERROR, 3) return end
            callback(e)
            frame:Close()
        end
    end

    net.Receive(NET_EXT_SYNC, function()
        FactionsExtData = net.ReadTable() or {}
    end)

    -- Тот же снимок, пришедший частями.
    if GRM.Net and GRM.Net.Receive then
        GRM.Net.Receive("factions.ext", function(data)
            FactionsExtData = istable(data) and data or {}
            hook.Run("GRM_FactionExtUpdated", FactionsExtData)
        end)
    end

    net.Receive(NET_EXT_CURFEW, function()
        CurfewState.active = net.ReadBool()
        CurfewState.endTime = net.ReadFloat()
        CurfewState.faction = net.ReadString()
        CurfewState.startedBy = net.ReadString()
        CurfewState.reason = net.ReadString()
        CurfewState.startedAt = net.ReadFloat()

        -- Открытое меню комендантского часа обновляется тем же пакетом:
        -- отдельный опрос сервера по таймеру не нужен.
        if GRM.Curfew and GRM.Curfew.State then
            local st = GRM.Curfew.State
            st.active    = CurfewState.active
            st.endTime   = CurfewState.endTime
            st.faction   = CurfewState.faction
            st.startedBy = CurfewState.startedBy
            st.reason    = CurfewState.reason
            st.startedAt = CurfewState.startedAt
            if GRM.Curfew._apply then GRM.Curfew._apply() end
        end
    end)

    net.Receive(NET_EXT_RESULT, function()
        local ok = net.ReadBool()
        local msg = net.ReadString()
        notification.AddLegacy(msg, ok and NOTIFY_GENERIC or NOTIFY_ERROR, 4)
    end)

    local availableModels = {}

    net.Receive(NET_MODELS_SYNC, function()
        availableModels = net.ReadTable() or {}
    end)

    net.Receive(NET_UPDATE_DEFAULT, function()
        local dtype = net.ReadString()
        local data = net.ReadTable()
        notification.AddLegacy(dtype == "models" and "Стандартные модели обновлены" or "Стандартное оружие обновлено", NOTIFY_GENERIC, 3)
    end)

    local function openModelSelection()
        net.Start(NET_MODELS_REQUEST)
        net.SendToServer()
        timer.Simple(0.25, function()
            if #availableModels <= 0 then notification.AddLegacy("Нет доступных моделей", NOTIFY_ERROR, 3) return end
            local frame = vgui.Create("DFrame")
            frame:SetTitle("Выбор модели")
            frame:SetSize(560, 620)
            frame:Center()
            frame:MakePopup()

            local scroll = vgui.Create("DScrollPanel", frame)
            scroll:Dock(FILL)
            scroll:DockMargin(8, 8, 8, 8)

            for _, entry in ipairs(availableModels) do
                entry = normalizeModelEntry(entry)

                local row = scroll:Add("DPanel")
                row:Dock(TOP)
                row:SetTall(72)
                row:DockMargin(0, 0, 0, 5)
                row.Paint = function(_, w, h) draw.RoundedBox(5, 0, 0, w, h, THEME.bgLight) end

                local preview = vgui.Create("DModelPanel", row)
                preview:Dock(LEFT)
                preview:SetWide(70)
                preview:SetModel(entry.path)
                preview:SetCamPos(Vector(55, 0, 50))
                preview:SetLookAt(Vector(0, 0, 45))
                preview.LayoutEntity = function() end
                timer.Simple(0.05, function() applyModelPanelSettings(preview, entry) end)

                local label = vgui.Create("DLabel", row)
                label:Dock(FILL)
                label:SetText(entry.path)
                label:SetTextColor(THEME.text)

                local btn = vgui.Create("DButton", row)
                btn:Dock(RIGHT)
                btn:SetWide(90)
                btn:SetText("Выбрать")
                btn.DoClick = function()
                    net.Start(NET_MODEL_SELECT)
                        net.WriteString(entry.path)
                    net.SendToServer()
                    frame:Close()
                end
            end
        end)
    end

    net.Receive(NET_EXT_OPEN_MASK, function()
        local factionName = net.ReadString()
        local available = net.ReadTable() or {}

        local frame = vgui.Create("DFrame")
        frame:SetTitle("Маскировка — " .. factionName)
        frame:SetSize(760, 620)
        frame:Center()
        frame:MakePopup()

        local scroll = vgui.Create("DScrollPanel", frame)
        scroll:Dock(FILL)
        scroll:DockMargin(8, 8, 8, 8)

        local sortedDepts = {}
        for deptName in pairs(available) do sortedDepts[#sortedDepts + 1] = deptName end
        table.sort(sortedDepts)

        for _, deptName in ipairs(sortedDepts) do
            local header = scroll:Add("DPanel")
            header:Dock(TOP)
            header:SetTall(32)
            header:DockMargin(0, 8, 0, 4)
            header.Paint = function(_, w, h)
                draw.RoundedBox(5, 0, 0, w, h, THEME.deptBg)
                draw.SimpleText(deptName, "FactionsExt_Normal", 10, h / 2, THEME.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end

            for idx, entry in ipairs(available[deptName] or {}) do
                entry = normalizeMaskEntry(entry, "Маскировка " .. idx)
                local row = scroll:Add("DPanel")
                row:Dock(TOP)
                row:SetTall(116)
                row:DockMargin(0, 0, 0, 6)
                row.Paint = function(_, w, h)
                    draw.RoundedBox(6, 0, 0, w, h, THEME.bgLight)
                    draw.SimpleText(entry.name, "FactionsExt_Title", 118, 22, THEME.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    draw.SimpleText(entry.path, "FactionsExt_Small", 118, 48, THEME.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    draw.SimpleText("skin: " .. tostring(entry.skin or 0) .. " | bodygroups: " .. bodygroupsToText(entry.bodygroups), "FactionsExt_Small", 118, 70, THEME.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end

                local preview = vgui.Create("DModelPanel", row)
                preview:SetPos(8, 8)
                preview:SetSize(96, 100)
                preview:SetModel(entry.path)
                preview:SetCamPos(Vector(55, 0, 55))
                preview:SetLookAt(Vector(0, 0, 45))
                preview.LayoutEntity = function() end
                timer.Simple(0.05, function() applyModelPanelSettings(preview, entry) end)

                local btn = styledButton(row, "Надеть", THEME.success)
                btn:SetPos(620, 40)
                btn:SetSize(110, 34)
                btn.DoClick = function()
                    net.Start(NET_EXT_APPLY_MASK)
                        net.WriteString(deptName)
                        net.WriteUInt(idx, 12)
                    net.SendToServer()
                    frame:Close()
                end
            end
        end

        local off = scroll:Add("DButton")
        off:Dock(TOP)
        off:SetTall(34)
        off:DockMargin(0, 10, 0, 0)
        off:SetText("Снять маскировку")
        off.DoClick = function()
            net.Start(NET_EXT_REMOVE_MASK)
            net.SendToServer()
            frame:Close()
        end
    end)

    local pendingModelsCb = nil
    net.Receive(NET_ADMIN_MODELS_DATA, function()
        local data = net.ReadTable() or {}
        if GRM.LoadoutAdmin and GRM.LoadoutAdmin._pendingModels and GRM.LoadoutAdmin.Open then
            GRM.LoadoutAdmin._pendingModels = nil
            GRM.LoadoutAdmin.Open("models", data)
            return
        end
        if pendingModelsCb then local cb = pendingModelsCb pendingModelsCb = nil cb(data) end
    end)

    local function buildModelList(scroll, modelList, onSave)
        scroll:Clear()
        for idx, entry in ipairs(modelList) do
            entry = normalizeModelEntry(entry)
            modelList[idx] = entry

            local row = scroll:Add("DPanel")
            row:Dock(TOP)
            row:SetTall(70)
            row:DockMargin(0, 0, 0, 5)
            row.Paint = function(_, w, h) draw.RoundedBox(5, 0, 0, w, h, THEME.bgLight) end

            local lbl = vgui.Create("DLabel", row)
            lbl:Dock(FILL)
            lbl:SetText(entry.path .. " | skin " .. tostring(entry.skin) .. " | bg " .. bodygroupsToText(entry.bodygroups))
            lbl:SetTextColor(THEME.text)

            local bgBtn = styledButton(row, "Бодигруппы", Color(110, 120, 210))
            bgBtn:Dock(RIGHT)
            bgBtn:SetWide(110)
            bgBtn:DockMargin(2, 20, 2, 20)
            bgBtn.DoClick = function()
                openBodygroupsEditor(entry, function(updated)
                    modelList[idx] = normalizeModelEntry(updated)
                    buildModelList(scroll, modelList, onSave)
                    onSave(modelList)
                end)
            end

            local editBtn = styledButton(row, "Ред.", THEME.accent)
            editBtn:Dock(RIGHT)
            editBtn:SetWide(60)
            editBtn:DockMargin(2, 20, 2, 20)
            editBtn.DoClick = function()
                openModelEntryEditor(entry, function(updated)
                    modelList[idx] = normalizeModelEntry(updated)
                    buildModelList(scroll, modelList, onSave)
                    onSave(modelList)
                end, false)
            end

            local del = styledButton(row, "X", THEME.danger)
            del:Dock(RIGHT)
            del:SetWide(42)
            del:DockMargin(2, 20, 2, 20)
            del.DoClick = function()
                table.remove(modelList, idx)
                buildModelList(scroll, modelList, onSave)
                onSave(modelList)
            end
        end
    end

    local function buildWeaponList(scroll, list, onSave)
        scroll:Clear()
        for idx, class in ipairs(list) do
            local row = scroll:Add("DPanel")
            row:Dock(TOP)
            row:SetTall(30)
            row:DockMargin(0, 0, 0, 3)
            row:SetPaintBackground(false)

            local lbl = vgui.Create("DLabel", row)
            lbl:Dock(FILL)
            lbl:SetText(class)
            lbl:SetTextColor(THEME.text)

            local del = vgui.Create("DButton", row)
            del:Dock(RIGHT)
            del:SetWide(70)
            del:SetText("Удалить")
            del.DoClick = function()
                table.remove(list, idx)
                buildWeaponList(scroll, list, onSave)
                onSave(list)
            end
        end
    end

    -- v2.1: интерактивное админ-меню моделей с живым превью (GRM v2 refresh)
    --[[ Меню одежды переехало в GRM Loadout Admin (cl_grm_faction_loadout_admin):
         новый дизайн GRM + структура фракции целиком (должности, отделы И
         ПОДОТДЕЛЫ). Старая реализация оставлена как фолбэк на случай, если
         клиентский файл почему-то не загрузился. ]]
    local function openAdminModelsMenu()
        if GRM.LoadoutAdmin and GRM.LoadoutAdmin.OpenModels then
            GRM.LoadoutAdmin.OpenModels()
            return
        end
        pendingModelsCb = function(data)
            local frame = vgui.Create("DFrame")
            frame:SetTitle("Управление моделями")
            frame:SetSize(1100, 700)
            frame:Center()
            frame:MakePopup()
            ui.currentModelsFrame = frame

            local tabs = vgui.Create("DPropertySheet", frame)
            tabs:Dock(FILL)

            local function addModelPanel(title, modelList, saveFunc)
                local panel = vgui.Create("DPanel")
                panel:SetPaintBackground(false)

                -- ЛЕВО: список моделей
                local left = vgui.Create("DPanel", panel)
                left:Dock(LEFT) left:SetWide(560) left:DockMargin(5, 5, 2, 42)
                left:SetPaintBackground(false)

                local scroll = vgui.Create("DScrollPanel", left)
                scroll:Dock(FILL)

                -- ПРАВО: живое превью
                local previewPanel = vgui.Create("DPanel", panel)
                previewPanel:Dock(FILL) previewPanel:DockMargin(2, 5, 5, 42)
                previewPanel.Paint = function(_, w, h)
                    draw.RoundedBox(6, 0, 0, w, h, THEME.bgLight)
                    draw.SimpleText("Предпросмотр", "DermaDefaultBold", 10, 14, THEME.dim or Color(160,165,175), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end

                local preview = vgui.Create("DAdjustableModelPanel", previewPanel)
                preview:Dock(FILL) preview:DockMargin(6, 24, 6, 6)
                preview:SetFOV(38)

                local info = vgui.Create("DLabel", previewPanel)
                info:Dock(BOTTOM) info:SetTall(34) info:DockMargin(6, 0, 6, 4)
                info:SetText("") info:SetWrap(true) info:SetAutoStretchVertical(true)

                local function showInPreview(entry)
                    entry = normalizeModelEntry(entry)
                    if not IsValid(preview) or entry.path == "" then return end
                    preview:SetModel(entry.path)
                    local ent = preview:GetEntity()
                    if IsValid(ent) then
                        ent:SetSkin(tonumber(entry.skin) or 0)
                        for i = 0, (ent:GetNumBodyGroups() or 1) - 1 do ent:SetBodygroup(i, 0) end
                        for g, v in pairs(entry.bodygroups or {}) do
                            ent:SetBodygroup(tonumber(g) or 0, tonumber(v) or 0)
                        end
                    end
                    info:SetText(entry.path .. "\nskin " .. tostring(entry.skin) .. " | bg " .. bodygroupsToText(entry.bodygroups))
                end

                local selected = nil
                local function rebuild()
                    scroll:Clear()
                    for idx, entry in ipairs(modelList) do
                        entry = normalizeModelEntry(entry)
                        modelList[idx] = entry

                        local row = scroll:Add("DPanel")
                        row:Dock(TOP) row:SetTall(70) row:DockMargin(0, 0, 0, 5)
                        row.Paint = function(_, w, h)
                            draw.RoundedBox(5, 0, 0, w, h, (selected == row) and Color(44, 66, 96) or THEME.bgLight)
                        end
                        row:SetCursor("hand")
                        row.OnMousePressed = function()
                            selected = row
                            showInPreview(entry)
                            surface.PlaySound("buttons/button14.wav")
                            for _, sib in ipairs(scroll:GetCanvas():GetChildren()) do if sib.InvalidateLayout then sib:InvalidateLayout() end end
                        end

                        local ico = vgui.Create("SpawnIcon", row)
                        ico:Dock(LEFT) ico:SetWide(64) ico:DockMargin(3, 3, 0, 3)
                        ico:SetModel(entry.path, tonumber(entry.skin) or 0)
                        ico:SetMouseInputEnabled(false) ico:SetTooltip(false)

                        local lbl = vgui.Create("DLabel", row)
                        lbl:Dock(FILL) lbl:DockMargin(4, 0, 0, 0)
                        lbl:SetText(entry.path .. "\nskin " .. tostring(entry.skin) .. " | bg " .. bodygroupsToText(entry.bodygroups))
                        lbl:SetTextColor(THEME.text) lbl:SetWrap(true)
                        lbl:SetMouseInputEnabled(false)

                        local bgBtn = styledButton(row, "Боди", Color(110, 120, 210))
                        bgBtn:Dock(RIGHT) bgBtn:SetWide(52) bgBtn:DockMargin(2, 20, 2, 20)
                        bgBtn.DoClick = function()
                            openBodygroupsEditor(entry, function(updated)
                                modelList[idx] = normalizeModelEntry(updated)
                                rebuild() saveFunc(modelList)
                                showInPreview(modelList[idx] or entry)
                            end)
                        end

                        local editBtn = styledButton(row, "Ред.", THEME.accent)
                        editBtn:Dock(RIGHT) editBtn:SetWide(50) editBtn:DockMargin(2, 20, 2, 20)
                        editBtn.DoClick = function()
                            openModelEntryEditor(entry, function(updated)
                                modelList[idx] = normalizeModelEntry(updated)
                                rebuild() saveFunc(modelList)
                                showInPreview(modelList[idx] or entry)
                            end, false)
                        end

                        local del = styledButton(row, "X", THEME.danger)
                        del:Dock(RIGHT) del:SetWide(38) del:DockMargin(2, 20, 4, 20)
                        del.DoClick = function()
                            table.remove(modelList, idx)
                            rebuild() saveFunc(modelList)
                        end
                    end
                    if modelList[1] then showInPreview(modelList[1]) end
                end
                rebuild()

                local add = vgui.Create("DButton", panel)
                add:Dock(BOTTOM) add:SetTall(34) add:SetText("+ Добавить модель")
                add.DoClick = function()
                    openModelEntryEditor({ path = "models/player/Group01/male_07.mdl" }, function(entry)
                        table.insert(modelList, normalizeModelEntry(entry))
                        rebuild() saveFunc(modelList)
                    end, false)
                end
                return panel
            end

            tabs:AddSheet("Стандартные", addModelPanel("default", data.default or {}, function(list)
                net.Start(NET_ADMIN_MODELS_SAVE)
                    net.WriteString("default")
                    net.WriteString("")
                    net.WriteString("")
                    net.WriteTable(list)
                net.SendToServer()
            end), "icon16/world.png")

            for factionName, fd in pairs(data.factions or {}) do
                local panel = vgui.Create("DPanel")
                panel:SetPaintBackground(false)
                local subtabs = vgui.Create("DPropertySheet", panel)
                subtabs:Dock(FILL)

                subtabs:AddSheet("Общие", addModelPanel("general", fd.general or {}, function(list)
                    net.Start(NET_ADMIN_MODELS_SAVE)
                        net.WriteString("faction")
                        net.WriteString(factionName)
                        net.WriteString("")
                        net.WriteTable(list)
                    net.SendToServer()
                end), "icon16/group.png")

                for _, role in ipairs(fd.rolesList or {}) do
                    fd.roles[role] = fd.roles[role] or {}
                    subtabs:AddSheet("Роль: " .. role, addModelPanel(role, fd.roles[role], function(list)
                        net.Start(NET_ADMIN_MODELS_SAVE)
                            net.WriteString("role")
                            net.WriteString(factionName)
                            net.WriteString(role)
                            net.WriteTable(list)
                        net.SendToServer()
                    end), "icon16/user.png")
                end

                for _, dept in ipairs(fd.deptsList or {}) do
                    fd.departments[dept] = fd.departments[dept] or {}
                    subtabs:AddSheet("Отдел: " .. dept, addModelPanel(dept, fd.departments[dept], function(list)
                        net.Start(NET_ADMIN_MODELS_SAVE)
                            net.WriteString("department")
                            net.WriteString(factionName)
                            net.WriteString(dept)
                            net.WriteTable(list)
                        net.SendToServer()
                    end), "icon16/brick.png")
                end

                tabs:AddSheet(factionName, panel, "icon16/group.png")
            end
        end

        net.Start(NET_ADMIN_MODELS_OPEN)
        net.SendToServer()
    end

    local pendingWeaponsCb = nil
    net.Receive(NET_ADMIN_WEAPONS_DATA, function()
        local data = net.ReadTable() or {}
        if GRM.LoadoutAdmin and GRM.LoadoutAdmin._pendingWeapons and GRM.LoadoutAdmin.Open then
            GRM.LoadoutAdmin._pendingWeapons = nil
            GRM.LoadoutAdmin.Open("weapons", data)
            return
        end
        if pendingWeaponsCb then local cb = pendingWeaponsCb pendingWeaponsCb = nil cb(data) end
    end)

    -- v2.1: интерактивное админ-меню оружия с каталогом и поиском (GRM v2 refresh)
    -- Аналогично одежде: основной интерфейс — GRM Loadout Admin.
    local function openWeaponsAdminMenu()
        if GRM.LoadoutAdmin and GRM.LoadoutAdmin.OpenWeapons then
            GRM.LoadoutAdmin.OpenWeapons()
            return
        end
        pendingWeaponsCb = function(data)
            local frame = vgui.Create("DFrame")
            frame:SetTitle("Управление оружием")
            frame:SetSize(1100, 680)
            frame:Center()
            frame:MakePopup()
            ui.currentWeaponsFrame = frame

            local tabs = vgui.Create("DPropertySheet", frame)
            tabs:Dock(FILL)

            -- полный каталог оружия из зарегистрированных SWEP'ов
            local function weaponCatalog()
                local out, seen = {}, {}
                for _, w in ipairs(weapons.GetList() or {}) do
                    local cls = w.ClassName or ""
                    if cls ~= "" and not seen[cls] then
                        seen[cls] = true
                        out[#out + 1] = { class = cls, name = (w.PrintName and w.PrintName ~= "") and w.PrintName or cls, cat = w.Category or "Прочее" }
                    end
                end
                table.sort(out, function(a, b)
                    if a.cat == b.cat then return a.name < b.name end
                    return a.cat < b.cat
                end)
                return out
            end
            local CATALOG = weaponCatalog()

            local function addWeaponPanel(list, saveFunc)
                list = istable(list) and list or {}
                local panel = vgui.Create("DPanel")
                panel:SetPaintBackground(false)

                local function inList(cls)
                    for _, c in ipairs(list) do if c == cls then return true end end
                    return false
                end

                -- ЛЕВО: текущий набор
                local left = vgui.Create("DPanel", panel)
                left:Dock(LEFT) left:SetWide(430) left:DockMargin(5, 5, 2, 40)
                left:SetPaintBackground(false)
                local leftTitle = vgui.Create("DLabel", left)
                leftTitle:Dock(TOP) leftTitle:SetTall(20)
                leftTitle:SetText("В наборе (удалить ✕):") leftTitle:SetTextColor(THEME.text)
                local scroll = vgui.Create("DScrollPanel", left)
                scroll:Dock(FILL)

                -- ПРАВО: каталог с поиском
                local right = vgui.Create("DPanel", panel)
                right:Dock(FILL) right:DockMargin(2, 5, 5, 40)
                right:SetPaintBackground(false)
                local search = vgui.Create("DTextEntry", right)
                search:Dock(TOP) search:SetTall(24)
                search:SetPlaceholderText("Поиск по имени/классу в каталоге...")
                local catScroll = vgui.Create("DScrollPanel", right)
                catScroll:Dock(FILL)

                local function rebuildList()
                    scroll:Clear()
                    for idx, class in ipairs(list) do
                        local wpn = weapons.Get(class)
                        local row = scroll:Add("DPanel")
                        row:Dock(TOP) row:SetTall(30) row:DockMargin(0, 0, 0, 3)
                        row:SetPaintBackground(false)
                        row.Paint = function(_, w, h) draw.RoundedBox(4, 0, 0, w, h, THEME.bgLight) end

                        local lbl = vgui.Create("DLabel", row)
                        lbl:Dock(FILL) lbl:DockMargin(6, 0, 0, 0)
                        lbl:SetText((wpn and wpn.PrintName and wpn.PrintName ~= "") and (wpn.PrintName .. "  (" .. class .. ")") or class)
                        lbl:SetTextColor(THEME.text)

                        local del = styledButton(row, "X", THEME.danger)
                        del:Dock(RIGHT) del:SetWide(56) del:DockMargin(0, 3, 3, 3)
                        del.DoClick = function()
                            table.remove(list, idx)
                            saveFunc(list)
                            rebuildList()
                        end
                    end
                end

                local function rebuildCatalog(filter)
                    catScroll:Clear()
                    filter = string.lower(trim(filter))
                    local lastCat = nil
                    for _, w in ipairs(CATALOG) do
                        if filter == "" or string.find(string.lower(w.name .. " " .. w.class), filter, 1, true) then
                            if w.cat ~= lastCat then
                                lastCat = w.cat
                                local hdr = catScroll:Add("DLabel")
                                hdr:Dock(TOP) hdr:SetTall(18)
                                hdr:SetText("— " .. tostring(lastCat) .. " —")
                                hdr:SetTextColor(THEME.accent or Color(70,150,240))
                                hdr:SetContentAlignment(5)
                            end
                            local has = inList(w.class)
                            local rowBtn = catScroll:Add("DButton")
                            rowBtn:Dock(TOP) rowBtn:SetTall(24) rowBtn:DockMargin(0, 0, 0, 2)
                            rowBtn:SetText("")
                            rowBtn.Paint = function(_, pw, ph)
                                draw.RoundedBox(4, 0, 0, pw, ph, has and Color(44, 80, 60) or THEME.bgLight)
                                draw.SimpleText(w.name, "DermaDefault", 8, ph / 2, has and Color(120, 230, 150) or THEME.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                                draw.SimpleText(w.class, "DermaDefault", pw - 8, ph / 2, THEME.dim or Color(150,155,165), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                            end
                            rowBtn.DoClick = function()
                                if inList(w.class) then
                                    for i, c in ipairs(list) do if c == w.class then table.remove(list, i) break end end
                                else
                                    list[#list + 1] = w.class
                                end
                                saveFunc(list)
                                rebuildList()
                                rebuildCatalog(search:GetText())
                            end
                        end
                    end
                end
                search.OnChange = function() rebuildCatalog(search:GetText()) end

                rebuildList() rebuildCatalog("")

                -- ручное добавление по классу (как раньше)
                local row = vgui.Create("DPanel", panel)
                row:Dock(BOTTOM) row:SetTall(34) row:SetPaintBackground(false)
                local entry = vgui.Create("DTextEntry", row)
                entry:Dock(FILL)
                entry:SetPlaceholderText("или вручную: classname оружия...")
                local add = vgui.Create("DButton", row)
                add:Dock(RIGHT) add:SetWide(100) add:SetText("+ Добавить")
                local function confirm()
                    local class = trim(entry:GetText())
                    if class == "" or inList(class) then return end
                    table.insert(list, class)
                    entry:SetText("")
                    saveFunc(list)
                    rebuildList() rebuildCatalog(search:GetText())
                end
                entry.OnEnter = confirm
                add.DoClick = confirm
                return panel
            end

            tabs:AddSheet("Стандартные", addWeaponPanel(data.default or {}, function(list)
                net.Start(NET_ADMIN_WEAPONS_SAVE)
                    net.WriteString("default")
                    net.WriteString("")
                    net.WriteString("")
                    net.WriteTable(list)
                net.SendToServer()
            end), "icon16/shield.png")

            for factionName, fd in pairs(data.factions or {}) do
                local panel = vgui.Create("DPanel")
                panel:SetPaintBackground(false)
                local subtabs = vgui.Create("DPropertySheet", panel)
                subtabs:Dock(FILL)

                subtabs:AddSheet("Общие", addWeaponPanel(fd.general or {}, function(list)
                    net.Start(NET_ADMIN_WEAPONS_SAVE)
                        net.WriteString("faction")
                        net.WriteString(factionName)
                        net.WriteString("")
                        net.WriteTable(list)
                    net.SendToServer()
                end), "icon16/group.png")

                for _, role in ipairs(fd.rolesList or {}) do
                    fd.roles[role] = fd.roles[role] or {}
                    subtabs:AddSheet("Роль: " .. role, addWeaponPanel(fd.roles[role], function(list)
                        net.Start(NET_ADMIN_WEAPONS_SAVE)
                            net.WriteString("role")
                            net.WriteString(factionName)
                            net.WriteString(role)
                            net.WriteTable(list)
                        net.SendToServer()
                    end), "icon16/user.png")
                end

                for _, dept in ipairs(fd.deptsList or {}) do
                    fd.departments[dept] = fd.departments[dept] or {}
                    subtabs:AddSheet("Отдел: " .. dept, addWeaponPanel(fd.departments[dept], function(list)
                        net.Start(NET_ADMIN_WEAPONS_SAVE)
                            net.WriteString("department")
                            net.WriteString(factionName)
                            net.WriteString(dept)
                            net.WriteTable(list)
                        net.SendToServer()
                    end), "icon16/brick.png")
                end

                tabs:AddSheet(factionName, panel, "icon16/group.png")
            end
        end

        net.Start(NET_ADMIN_WEAPONS_OPEN)
        net.SendToServer()
    end

    local pendingMaskAdminCb = nil
    net.Receive(NET_MASK_ADMIN_DATA, function()
        local data = net.ReadTable() or {}
        if pendingMaskAdminCb then local cb = pendingMaskAdminCb pendingMaskAdminCb = nil cb(data) end
    end)

    local function openMaskAdminMenu()
        pendingMaskAdminCb = function(data)
            local frame = vgui.Create("DFrame")
            frame:SetTitle("Редактор маскировки V2")
            frame:SetSize(math.min(ScrW() - 80, 1320), math.min(ScrH() - 80, 860))
            frame:Center()
            frame:MakePopup()

            local top = vgui.Create("DPanel", frame)
            top:Dock(TOP)
            top:SetTall(40)
            top:DockMargin(8, 8, 8, 0)
            top:SetPaintBackground(false)

            local factionCombo = vgui.Create("DComboBox", top)
            factionCombo:Dock(LEFT)
            factionCombo:SetWide(260)
            factionCombo:SetValue("Фракция")

            local deptCombo = vgui.Create("DComboBox", top)
            deptCombo:Dock(LEFT)
            deptCombo:SetWide(220)
            deptCombo:DockMargin(8, 0, 0, 0)
            deptCombo:SetValue("Отдел")

            local saveBtn = styledButton(top, "Сохранить отдел", THEME.success)
            saveBtn:Dock(RIGHT)
            saveBtn:SetWide(160)

            local rolesPanel = vgui.Create("DScrollPanel", frame)
            rolesPanel:Dock(LEFT)
            rolesPanel:SetWide(300)
            rolesPanel:DockMargin(8, 8, 0, 8)

            local masksScroll = vgui.Create("DScrollPanel", frame)
            masksScroll:Dock(FILL)
            masksScroll:DockMargin(8, 8, 8, 8)

            local currentFaction, currentDept, currentData

            local function getDeptData(factionName, deptName)
                local f = data[factionName]
                f.MaskDepartments = f.MaskDepartments or {}
                f.MaskDepartments[deptName] = normalizeMaskDepartment(f.MaskDepartments[deptName] or { Roles = {}, Models = {} })
                return f.MaskDepartments[deptName]
            end

            local function roleEnabled(role)
                for _, r in ipairs(currentData.Roles or {}) do if r == role then return true end end
                return false
            end

            local function setRole(role, val)
                currentData.Roles = currentData.Roles or {}
                for i = #currentData.Roles, 1, -1 do
                    if currentData.Roles[i] == role then table.remove(currentData.Roles, i) end
                end
                if val then table.insert(currentData.Roles, role) end
            end

            local function rebuildRoles()
                rolesPanel:Clear()
                if not currentFaction then return end
                local title = vgui.Create("DLabel", rolesPanel)
                title:Dock(TOP)
                title:SetTall(30)
                title:SetText("Ранги с доступом к /mask")
                title:SetTextColor(THEME.text)
                title:SetFont("FactionsExt_Normal")
                for _, role in ipairs(data[currentFaction].Roles or {}) do
                    local chk = vgui.Create("DCheckBoxLabel", rolesPanel)
                    chk:Dock(TOP)
                    chk:SetTall(26)
                    chk:SetText(role)
                    chk:SetTextColor(THEME.text)
                    chk:SetFont("FactionsExt_Normal")
                    chk:SetValue(roleEnabled(role))
                    chk.OnChange = function(_, val) setRole(role, val) end
                end
            end

            local function rebuildMasks()
                masksScroll:Clear()
                if not currentData then return end

                local add = masksScroll:Add("DButton")
                add:Dock(TOP)
                add:SetTall(34)
                add:DockMargin(0, 0, 0, 8)
                add:SetText("+ Добавить маскировку")
                add.DoClick = function()
                    openModelEntryEditor({ name = "Новая маскировка", path = "models/player/Group01/male_07.mdl" }, function(entry)
                        table.insert(currentData.Models, normalizeMaskEntry(entry))
                        rebuildMasks()
                    end, true)
                end

                local hint = masksScroll:Add("DLabel")
                hint:Dock(TOP)
                hint:SetTall(22)
                hint:DockMargin(2, 0, 2, 6)
                hint:SetText("Справа у каждой маскировки: Бодигруппы, Редактировать, ✕ УДАЛИТЬ МОДЕЛЬ. Удаление сохраняется сразу.")
                hint:SetTextColor(THEME.textDim)
                hint:SetFont("FactionsExt_Small")

                for idx, entry in ipairs(currentData.Models or {}) do
                    entry = normalizeMaskEntry(entry, "Маскировка " .. idx)
                    currentData.Models[idx] = entry

                    local row = masksScroll:Add("DPanel")
                    row:Dock(TOP)
                    row:SetTall(122)
                    row:DockMargin(0, 0, 0, 8)
                    row.Paint = function(_, w, h)
                        draw.RoundedBox(6, 0, 0, w, h, THEME.bgLight)
                        draw.SimpleText(entry.name, "FactionsExt_Normal", 92, 20, THEME.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                        draw.SimpleText(entry.path, "FactionsExt_Small", 92, 42, THEME.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                        draw.SimpleText("skin: " .. tostring(entry.skin) .. " | bg: " .. bodygroupsToText(entry.bodygroups), "FactionsExt_Small", 92, 62, THEME.textDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    end

                    local preview = vgui.Create("DModelPanel", row)
                    preview:SetPos(6, 6)
                    preview:SetSize(78, 86)
                    preview:SetModel(entry.path)
                    preview:SetCamPos(Vector(55, 0, 55))
                    preview:SetLookAt(Vector(0, 0, 45))
                    preview.LayoutEntity = function() end
                    timer.Simple(0.05, function() applyModelPanelSettings(preview, entry) end)

                    -- Правая панель кнопок через Dock, чтобы кнопки не уезжали за пределы строки
                    -- на маленьком разрешении/узком окне.
                    local actions = vgui.Create("DPanel", row)
                    actions:Dock(RIGHT)
                    actions:SetWide(190)
                    actions:DockMargin(8, 8, 10, 8)
                    actions:SetPaintBackground(false)

                    local del = styledButton(actions, "✕ УДАЛИТЬ МОДЕЛЬ", THEME.danger)
                    del:Dock(BOTTOM)
                    del:SetTall(32)
                    del.DoClick = function()
                        Derma_Query(
                            "Удалить маскировку «" .. tostring(entry.name or entry.path or "модель") .. "» из списка?\n\nИзменение будет сразу сохранено для текущего отдела.",
                            "Удаление модели маскировки",
                            "Удалить", function()
                                table.remove(currentData.Models, idx)
                                rebuildMasks()
                                -- Сразу сохраняем удаление на сервер, чтобы не требовалось отдельно
                                -- нажимать «Сохранить отдел» после удаления.
                                if currentFaction and currentDept and currentData then
                                    net.Start(NET_MASK_ADMIN_SAVE)
                                        net.WriteString(currentFaction)
                                        net.WriteString(currentDept)
                                        net.WriteTable(currentData)
                                    net.SendToServer()
                                end
                            end,
                            "Отмена"
                        )
                    end

                    local edit = styledButton(actions, "Редактировать", THEME.accent)
                    edit:Dock(BOTTOM)
                    edit:SetTall(28)
                    edit:DockMargin(0, 0, 0, 6)
                    edit.DoClick = function()
                        openModelEntryEditor(entry, function(updated)
                            currentData.Models[idx] = normalizeMaskEntry(updated)
                            rebuildMasks()
                        end, true)
                    end

                    local bg = styledButton(actions, "Бодигруппы", Color(110, 120, 210))
                    bg:Dock(BOTTOM)
                    bg:SetTall(28)
                    bg:DockMargin(0, 0, 0, 6)
                    bg.DoClick = function()
                        openBodygroupsEditor(entry, function(updated)
                            currentData.Models[idx] = normalizeMaskEntry(updated)
                            rebuildMasks()
                        end)
                    end
                end
            end

            local function selectDept(dept)
                currentDept = dept
                currentData = getDeptData(currentFaction, currentDept)
                rebuildRoles()
                rebuildMasks()
            end

            local function selectFaction(factionName)
                currentFaction = factionName
                deptCombo:Clear()
                local f = data[factionName]
                for _, dept in ipairs(f.Departments or {}) do deptCombo:AddChoice(dept) end
                if f.Departments and f.Departments[1] then
                    deptCombo:SetValue(f.Departments[1])
                    selectDept(f.Departments[1])
                end
            end

            local sorted = {}
            for name in pairs(data) do sorted[#sorted + 1] = name end
            table.sort(sorted)
            for _, name in ipairs(sorted) do factionCombo:AddChoice(name) end
            factionCombo.OnSelect = function(_, _, val) selectFaction(val) end
            deptCombo.OnSelect = function(_, _, val) selectDept(val) end

            saveBtn.DoClick = function()
                if not currentFaction or not currentDept then return end
                net.Start(NET_MASK_ADMIN_SAVE)
                    net.WriteString(currentFaction)
                    net.WriteString(currentDept)
                    net.WriteTable(currentData)
                net.SendToServer()
            end

            if sorted[1] then
                factionCombo:SetValue(sorted[1])
                selectFaction(sorted[1])
            end
        end

        net.Start(NET_MASK_ADMIN_OPEN)
        net.SendToServer()
    end

    local function sendExtAction(action, args)
        net.Start(NET_EXT_ACTION)
            net.WriteString(action)
            net.WriteTable(args or {})
        net.SendToServer()
    end

    -- ============================================================================
    -- Вкладка «Расширенные настройки» админ-меню /factions (v3.1.1, переработка)
    --
    -- Раньше вкладка вставлялась обезьяньим патчем глобала OpenAdminMenu —
    -- sh_factions.lua грузится ПОЗЖЕ и перезаписывал его, поэтому вкладка тихо
    -- пропадала («раньше была — сейчас нет»). Теперь честная точка расширения:
    -- hook GRM_FactionsAdmin_BuildTabs (вызывается sh_factions при построении
    -- вкладок админ-меню, тот же механизм, что у моста «Доступы»).
    --
    -- СИНХРОНИЗАЦИЯ состояния (заказ владельца «переработать и синхронизировать»):
    --   ком.час доступ:  cfg.CurfewRoles   → проверяет hasCurfewAccess (/kom_hour)
    --   гос.новости:     f.GNewsAccess     → hasGNewsAccess (/gnews) — зеркало в
    --                                          FactionsData с v3.1.1 (buildSyncData)
    --   модели/оружие:   f.Models/RoleModels/DepartmentModels, f.Weapons/...
    --                    → читают GetModelsForPlayer (/model) и ApplyWeaponsToPlayer
    --                      (спавн); во вкладке — ЖИВЫЕ счётчики из NET_SYNC_ALL
    --   маскировка v2:   cfg.MaskDepartments → getAvailableMasks (/mask)
    -- Таймер-синк 1.5 c: панель сама пересобирается при изменении зеркал.
    -- ============================================================================
    function OpenExtendedSettings(parentFrame)
        -- Синхронизировать доступы по ролям (FactionPerms), чтобы чекбоксы
        -- законодательства отображали актуальное состояние.
        if GRM and GRM.FactionPerms and GRM.FactionPerms.Request then
            GRM.FactionPerms.Request()
        end

        local panel = vgui.Create("DPanel")
        panel:SetPaintBackground(false)
        panel:DockPadding(10, 10, 10, 10)

        local top = vgui.Create("DPanel", panel)
        top:Dock(TOP)
        top:SetTall(36)
        top:SetPaintBackground(false)

        local factionCombo = vgui.Create("DComboBox", top)
        factionCombo:SetPos(0, 5)
        factionCombo:SetSize(260, 26)

        local refresh = styledButton(top, "Обновить", THEME.accent)
        refresh:SetPos(270, 5)
        refresh:SetSize(100, 26)

        local scroll = vgui.Create("DScrollPanel", panel)
        scroll:Dock(FILL)
        scroll:DockMargin(0, 8, 0, 0)

        local function infoLine(parent, text, col, tall)
            local l = vgui.Create("DLabel", parent)
            l:Dock(TOP)
            l:SetTall(tall or 22)
            l:SetWrap(true)
            l:SetAutoStretchVertical(true)
            l:SetText(text)
            l:SetTextColor(col or THEME.textDim)
            l:SetFont("FactionsExt_Small")
            return l
        end
        local function countArr(t) return istable(t) and #t or 0 end
        local function countMapLists(t)
            local n = 0
            if istable(t) then for _, v in pairs(t) do if istable(v) then n = n + #v end end end
            return n
        end

        local function rebuildCombo()
            factionCombo:Clear()
            local sorted = {}
            for name in pairs(FactionsData or {}) do sorted[#sorted + 1] = name end
            table.sort(sorted)
            for _, name in ipairs(sorted) do factionCombo:AddChoice(name) end
            if sorted[1] then factionCombo:SetValue(sorted[1]) end
        end

        local function sigOf(factionName)
            local f = FactionsData and FactionsData[factionName]
            if not istable(f) then return "none" end
            local cfg = (FactionsExtData and FactionsExtData[factionName]) or {}
            return table.concat({
                tostring(countArr(f.Models)), tostring(countMapLists(f.RoleModels)), tostring(countMapLists(f.DepartmentModels)),
                tostring(countArr(f.Weapons)), tostring(countMapLists(f.RoleWeapons)), tostring(countMapLists(f.DepartmentWeapons)),
                tostring(f.GNewsAccess == true), tostring(cfg.GNewsAccess == true),
                tostring(CurfewState and CurfewState.active == true), tostring(CurfewState and CurfewState.faction or ""),
                tostring(istable(cfg.MaskDepartments) and table.Count(cfg.MaskDepartments) or 0),
                tostring(countArr(cfg.CurfewRoles)),
                -- Доступы по ролям (FactionPerms) — чтобы чекбоксы законов обновлялись
                tostring(GRM.FactionPerms and GRM.FactionPerms.GetFactionRoles and util.TableToJSON(GRM.FactionPerms.GetFactionRoles(factionName)) or "{}"),
            }, "|")
        end

        local lastSig = nil

        -- Вкладка пересобирается при изменении подписи состояния (это нужно,
        -- чтобы галочки подхватывали серверные данные). Но раньше при этом
        -- терялась позиция прокрутки: поставил галочку в конце длинного
        -- списка ролей — список отщёлкивал в самое начало. Запоминаем и
        -- возвращаем скролл вокруг пересборки.
        local function rebuild(factionName)
            local keepScroll = 0
            if IsValid(scroll) and IsValid(scroll.VBar) then keepScroll = scroll.VBar:GetScroll() end
            scroll:Clear()
            if keepScroll > 0 then
                timer.Simple(0, function()
                    if IsValid(scroll) and IsValid(scroll.VBar) then scroll.VBar:SetScroll(keepScroll) end
                end)
            end
            if not factionName or not FactionsData or not FactionsData[factionName] then return end
            local f = FactionsData[factionName]
            local cfg = (FactionsExtData and FactionsExtData[factionName]) or { CurfewRoles = {}, MaskDepartments = {}, GNewsAccess = false }

            infoLine(scroll, "Единый стейт доступов: эти же данные читают /model, выдача оружия при спавне, /kom_hour, /mask и /gnews. Изменения применяются мгновенно (синк 1.5 с).", THEME.textDim, 30)

            -- Комендантский час ------------------------------------------------
            sectionLabel(scroll, "Комендантский час (/kom_hour)")
            if CurfewState and CurfewState.active == true then
                local left = math.max(0, (tonumber(CurfewState.endTime) or 0) - CurTime())
                infoLine(scroll, string.format("СТАТУС: АКТИВЕН — осталось %02d:%02d%s", math.floor(left / 60), math.floor(left % 60),
                    (CurfewState.faction or "") ~= "" and (" • объявила: " .. tostring(CurfewState.faction)) or ""), Color(255, 120, 120), 20)
                local stopBtn = styledButton(scroll, "Отменить комендантский час", THEME.danger)
                stopBtn:Dock(TOP) stopBtn:SetTall(30) stopBtn:DockMargin(0, 2, 0, 4)
                stopBtn.DoClick = function() sendExtAction("stopCurfew", { factionName }) end
            else
                infoLine(scroll, "СТАТУС: не активен. Запуск: /kom_hour [мин] в чате — доступ у отмеченных ниже ролей.", THEME.textDim, 20)
            end
            local marked = 0
            for _, role in ipairs(f.Roles or {}) do
                local on = tableHasValue(cfg.CurfewRoles or {}, role)
                if on then marked = marked + 1 end
                local chk = vgui.Create("DCheckBoxLabel", scroll)
                chk:Dock(TOP)
                chk:SetTall(24)
                chk:SetText(role)
                chk:SetTextColor(on and Color(140, 240, 160) or THEME.text)
                chk:SetFont("FactionsExt_Normal")
                chk:SetValue(on and 1 or 0)
                chk.OnChange = function() sendExtAction("toggleCurfewRole", { factionName, role }) end
            end
            if #(f.Roles or {}) == 0 then infoLine(scroll, "Ролей нет — создайте во вкладке «Роли».", THEME.textDim, 20) end

            -- ГосНовости --------------------------------------------------------
            sectionLabel(scroll, "Гос.новости (/gnews)")
            local gnewsOn = (f.GNewsAccess == true) or (cfg.GNewsAccess == true)
            local gnews = vgui.Create("DCheckBoxLabel", scroll)
            gnews:Dock(TOP)
            gnews:SetTall(26)
            gnews:SetText(gnewsOn and "Доступ ВЫДАН лидеру этой фракции" or "Разрешить /gnews лидеру этой фракции")
            gnews:SetTextColor(gnewsOn and Color(140, 240, 160) or THEME.text)
            gnews:SetFont("FactionsExt_Normal")
            gnews:SetValue(gnewsOn and 1 or 0)
            gnews.OnChange = function(_, val) sendExtAction("setGNewsAccess", { factionName, tobool(val) }) end

            -- Контроль чипов (находка 169) --------------------------------------
            sectionLabel(scroll, "Контроль чипов")
            local chipAlertOn = cfg.ChipDeathAlert == true
            local chipAlert = vgui.Create("DCheckBoxLabel", scroll)
            chipAlert:Dock(TOP)
            chipAlert:SetTall(26)
            chipAlert:SetText(chipAlertOn and "Уведомлять о смерти носителей экспериментальных чипов — ВКЛ" or "Присылать уведомление о смерти носителей экспериментального чипа")
            chipAlert:SetTextColor(chipAlertOn and Color(140, 240, 160) or THEME.text)
            chipAlert:SetFont("FactionsExt_Normal")
            chipAlert:SetValue(chipAlertOn and 1 or 0)
            chipAlert.OnChange = function(_, val) sendExtAction("setChipDeathAlert", { factionName, tobool(val) }) end
            infoLine(scroll, "Члены фракции получат звук (npc/metropolice/die2.wav), текстовое уведомление и GPS-метку «В данном районе убит/умер специальный юнит» при смерти носителя экспериментального чипа.", THEME.textDim, 36)

            -- Модели ------------------------------------------------------------
            sectionLabel(scroll, "Модели (/model)")
            local mGen, mRole, mDept = countArr(f.Models), countMapLists(f.RoleModels), countMapLists(f.DepartmentModels)
            infoLine(scroll, "Назначено: общих " .. mGen .. " • по ролям " .. mRole .. " • по отделам " .. mDept ..
                (mGen + mRole + mDept == 0 and " (действуют стандартные)" or ""), THEME.text, 20)
            local modelsBtn = styledButton(scroll, "Редактор моделей (/models_admin)", THEME.accent)
            modelsBtn:Dock(TOP) modelsBtn:SetTall(32) modelsBtn:DockMargin(0, 2, 0, 4)
            modelsBtn.DoClick = openAdminModelsMenu

            -- Оружие ------------------------------------------------------------
            sectionLabel(scroll, "Оружие при спавне")
            local wGen, wRole, wDept = countArr(f.Weapons), countMapLists(f.RoleWeapons), countMapLists(f.DepartmentWeapons)
            local preview = {}
            for i = 1, 3 do if istable(f.Weapons) and f.Weapons[i] then preview[#preview + 1] = tostring(f.Weapons[i]) end end
            infoLine(scroll, "Назначено: общих " .. wGen .. " • по ролям " .. wRole .. " • по отделам " .. wDept ..
                (wGen + wRole + wDept == 0 and " (стандартный набор)" or "") ..
                (#preview > 0 and (" | " .. table.concat(preview, ", ") .. (wGen > 3 and ", …" or "")) or ""), THEME.text, 20)
            local weaponsBtn = styledButton(scroll, "Редактор оружия (/weapons_admin)", THEME.accent)
            weaponsBtn:Dock(TOP) weaponsBtn:SetTall(32) weaponsBtn:DockMargin(0, 2, 0, 4)
            weaponsBtn.DoClick = openWeaponsAdminMenu

            -- Маскировка ---------------------------------------------------------
            sectionLabel(scroll, "Маскировка V2 (/mask)")
            local depts = istable(cfg.MaskDepartments) and cfg.MaskDepartments or {}
            if table.Count(depts) == 0 then
                infoLine(scroll, "Отделов маскировки нет — создаются в редакторе (кнопка ниже).", THEME.textDim, 20)
            else
                local names = {}
                for d in pairs(depts) do names[#names + 1] = d end
                table.sort(names)
                for _, d in ipairs(names) do
                    local dept = istable(depts[d]) and depts[d] or {}
                    infoLine(scroll, "• " .. d .. " — ролей с доступом: " .. countArr(dept.Roles) .. ", вариантов: " .. countArr(dept.Models), THEME.text, 18)
                end
            end
            local maskBtn = styledButton(scroll, "Редактор маскировки V2 (/mask_admin)", THEME.accent)
            maskBtn:Dock(TOP) maskBtn:SetTall(32) maskBtn:DockMargin(0, 2, 0, 4)
            maskBtn.DoClick = openMaskAdminMenu

            -- Телефония ----------------------------------------------------------
            sectionLabel(scroll, "Телефония / оборудование")
            local phoneAccessBtn = styledButton(scroll, "Доступ к АТС / прослушке (/phone_access)", Color(70, 150, 210))
            phoneAccessBtn:Dock(TOP) phoneAccessBtn:SetTall(32) phoneAccessBtn:DockMargin(0, 2, 0, 0)
            phoneAccessBtn.DoClick = function()
                if GRM and GRM.Phone and GRM.Phone.AccessManager and GRM.Phone.AccessManager.OpenMenu then
                    GRM.Phone.AccessManager.OpenMenu()
                else
                    RunConsoleCommand("grm_phone_access")
                    notification.AddLegacy("Если меню не открылось — проверьте, что grm_phone_system установлен и загружен.", NOTIFY_HINT, 4)
                end
            end

            -- Законодательство ---------------------------------------------------
            sectionLabel(scroll, "Законодательство (законы)")

            -- Проверяем доступы для текущей фракции
            local factionPerms = {}
            if GRM and GRM.FactionPerms and GRM.FactionPerms.GetFactionRoles then
                factionPerms = GRM.FactionPerms.GetFactionRoles(factionName) or {}
            end

            --[[ 21.08. Раздел настроек законов открывался всем, кто дошёл до
                 вкладки: любой видел галочки «Публикация/Удаление законов».
                 Менять их всё равно мог только суперадмин или лидер (сервер
                 отказывал молча), поэтому выглядело как сломанный интерфейс.
                 Теперь без права раздел показывает состояние и объясняет,
                 кто им управляет — переключателей просто нет. ]]
            local canManageLaws = false
            do
                local lp = LocalPlayer()
                if IsValid(lp) then
                    if lp:IsSuperAdmin() then
                        canManageLaws = true
                    else
                        local data = (FactionsData or {})[factionName]
                        local key = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(lp))
                            or tostring(lp:SteamID64() or "")
                        if istable(data) then
                            if tostring(data.Leader or "") == key then canManageLaws = true end
                            local member = istable(data.Members) and data.Members[key]
                            if istable(member) and (member.IsLeader == true or member.Leader == true) then
                                canManageLaws = true
                            end
                        end
                    end
                end
            end

            infoLine(scroll, canManageLaws
                and "Настройка доступов к публикации и удалению законов по ролям фракции."
                or "Доступами к законам управляет лидер организации или суперадмин. Ниже — текущее состояние.",
                THEME.textDim, 20)

            -- Список ролей с чекбоксами для доступов
            for _, role in ipairs(f.Roles or {}) do
                local rolePerms = factionPerms[role] or {}

                local rolePanel = vgui.Create("DPanel", scroll)
                rolePanel:Dock(TOP)
                rolePanel:SetTall(50)
                rolePanel:DockMargin(0, 4, 0, 0)
                rolePanel.Paint = function(self, w, h)
                    draw.RoundedBox(4, 0, 0, w, h, Color(40, 40, 40, 150))
                end

                -- Название роли
                local roleLabel = vgui.Create("DLabel", rolePanel)
                roleLabel:SetPos(8, 4)
                roleLabel:SetSize(200, 20)
                roleLabel:SetText("Роль: " .. role)
                roleLabel:SetTextColor(Color(255, 200, 100))
                roleLabel:SetFont("FactionsExt_Normal")

                -- В GMod нет goto: ветка «нет прав» и ветка с чекбоксами
                -- разведены обычным if/else.
                if not canManageLaws then
                    -- Только состояние, без переключателей.
                    local stateLabel = vgui.Create("DLabel", rolePanel)
                    stateLabel:SetPos(8, 26)
                    stateLabel:SetSize(320, 20)
                    stateLabel:SetFont("FactionsExt_Small")
                    stateLabel:SetTextColor(THEME.textDim)
                    stateLabel:SetText(("Публикация: %s · удаление: %s"):format(
                        rolePerms.law_publish and "да" or "нет",
                        rolePerms.law_remove and "да" or "нет"))
                else

                    -- Чекбокс law_publish
                    local pubChk = vgui.Create("DCheckBoxLabel", rolePanel)
                    pubChk:SetPos(8, 26)
                    pubChk:SetSize(150, 20)
                    pubChk:SetText("Публикация законов")
                    pubChk:SetTextColor(rolePerms.law_publish and Color(140, 240, 160) or THEME.text)
                    pubChk:SetFont("FactionsExt_Small")
                    pubChk:SetValue(rolePerms.law_publish and 1 or 0)
                    pubChk.OnChange = function(_, val)
                        if GRM and GRM.FactionPerms then
                            if tobool(val) then
                                GRM.FactionPerms.GrantToRole(factionName, role, "law_publish")
                            else
                                GRM.FactionPerms.RevokeFromRole(factionName, role, "law_publish")
                            end
                        end
                    end

                    -- Чекбокс law_remove
                    local remChk = vgui.Create("DCheckBoxLabel", rolePanel)
                    remChk:SetPos(170, 26)
                    remChk:SetSize(150, 20)
                    remChk:SetText("Удаление законов")
                    remChk:SetTextColor(rolePerms.law_remove and Color(140, 240, 160) or THEME.text)
                    remChk:SetFont("FactionsExt_Small")
                    remChk:SetValue(rolePerms.law_remove and 1 or 0)
                    remChk.OnChange = function(_, val)
                        if GRM and GRM.FactionPerms then
                            if tobool(val) then
                                GRM.FactionPerms.GrantToRole(factionName, role, "law_remove")
                            else
                                GRM.FactionPerms.RevokeFromRole(factionName, role, "law_remove")
                            end
                        end
                    end
                end

            end

            if #(f.Roles or {}) == 0 then
                infoLine(scroll, "Ролей нет — создайте во вкладке «Роли».", THEME.textDim, 20)
            end
        end

        factionCombo.OnSelect = function(_, _, val)
            lastSig = sigOf(val)
            rebuild(val)
        end
        refresh.DoClick = function()
            rebuildCombo()
            local val = factionCombo:GetValue()
            if val and val ~= "" then lastSig = sigOf(val) rebuild(val) end
        end

        -- авто-синк с зеркалами (заказ «синхронизировать»): изменилось — пересобрать
        local tName = "FactionsExt_ExtTabSync_" .. tostring({}):gsub("%W", "")
        timer.Create(tName, 1.5, 0, function()
            if not IsValid(panel) then timer.Remove(tName) return end
            local val = factionCombo:GetValue()
            if not val or val == "" then return end
            local s = sigOf(val)
            if s ~= lastSig then lastSig = s rebuild(val) end
        end)
        panel.OnRemove = function() timer.Remove(tName) end

        timer.Simple(0.2, function()
            if IsValid(panel) then
                rebuildCombo()
                local val = factionCombo:GetValue()
                if val and val ~= "" then lastSig = sigOf(val) rebuild(val) end
            end
        end)

        return panel
    end

    -- Точка расширения: вкладка «Расширенные настройки» доступна ТОЛЬКО суперадмину
    hook.Add("GRM_FactionsAdmin_BuildTabs", "FactionsExt_ExtendedTab", function(tabs)
        if not IsValid(tabs) then return end
        if not (IsValid(LocalPlayer()) and LocalPlayer():IsSuperAdmin()) then return end
        tabs:AddSheet("Расширенные настройки", OpenExtendedSettings(tabs), "icon16/cog.png")
    end)

    -- Вкладка «Экономика» в /factions (v3.2.0): чистый информационный режим.
    -- Любые читерские кнопки убраны: только отображение госбюджета и
    -- бюджетов/налогов фракций. Управление — строго через банкомат/компьютер.
    local function OpenEconomyPanel(parentFrame)
        local panel = vgui.Create("DPanel")
        panel:SetPaintBackground(false)
        panel:DockPadding(0, 0, 0, 0)
        if GRM.Economy and GRM.Economy.EmbedAdminPanel then
            GRM.Economy.EmbedAdminPanel(panel)
            GRM.Economy._embeddedBuild = GRM.Economy.BuildAdminContent
            net.Start("GRM_Eco_AdminOpen")
            net.SendToServer()
        end
        local wait = vgui.Create("DLabel", panel)
        wait:Dock(TOP)
        wait:SetTall(28)
        wait:SetFont("GRMFac_Normal")
        wait:SetTextColor(Color(155, 170, 190))
        wait:SetText("  Загрузка казны…")
        return panel
    end
    hook.Add("GRM_FactionsAdmin_BuildTabs", "FactionsExt_EconomyTab", function(tabs)
        if not IsValid(tabs) then return end
        -- Вкладку видит только тот, у кого есть доступ к экономике.
        -- На клиенте проверяем по локальному признаку: сервер отправил
        -- NET_OPEN_ADMIN либо суперадмину, либо CanManageEconomy-игроку.
        -- Для точности спрашиваем сервер (лёгкий канал) — но чтобы не плодить
        -- лишние запросы, показываем вкладку всегда: сама панель экономики
        -- на сервере защищена CanManageEconomy, не-уполномоченному откроется
        -- пустой ответ. Лучше: показываем только суперадмину ИЛИ тем, кому
        -- сервер разрешил (определяем по факту, что нас пустили в админ-меню —
        -- это уже значит лидер/суперадмин; у лидера без экономики вкладка
        -- просто откроет защищённую панель).
        tabs:AddSheet("Экономика", OpenEconomyPanel(tabs), "icon16/money.png")
    end)


    net.Receive(NET_MASK_ADMIN_DATA, function()
        local data = net.ReadTable() or {}
        if pendingMaskAdminCb then
            local cb = pendingMaskAdminCb
            pendingMaskAdminCb = nil
            cb(data)
        end
    end)

    hook.Add("GRMRPChat_ClientCommand", "FactionsExt_ClientCommands", function(ply, text)
        local datapack = { tostring(text or ""), SkipPlayerSay = false }
            if ply ~= LocalPlayer() then return end
            local msg = datapack[1]
            if not msg then return end
            local lower = safeLower(trim(msg))

            if lower == "/model" then
                openModelSelection()
                datapack[1] = ""
                return
            end

            if lower == "/mask_admin" or lower == "!mask_admin" or lower == "/maskcfg" or lower == "!maskcfg" then
                openMaskAdminMenu()
                datapack[1] = ""
                return
            end

            if lower == "/models_admin" then
                if LocalPlayer():IsSuperAdmin() then openAdminModelsMenu() end
                datapack[1] = ""
                return
            end

            if lower == "/weapons_admin" then
                if LocalPlayer():IsSuperAdmin() then openWeaponsAdminMenu() end
                datapack[1] = ""
                return
            end

        if datapack.SkipPlayerSay == true then return true end
    end)

    concommand.Add("models_admin", function() if LocalPlayer():IsSuperAdmin() then openAdminModelsMenu() end end)
    concommand.Add("weapons_admin", function() if LocalPlayer():IsSuperAdmin() then openWeaponsAdminMenu() end end)
    concommand.Add("grm_mask_admin", function() if LocalPlayer():IsSuperAdmin() then openMaskAdminMenu() end end)
    concommand.Add("cl_model", openModelSelection)

    -- цвета плашки постоянны — создаются один раз, не на кадр (§6.1.8)
    local COL_CURFEW_BG, COL_CURFEW_TEXT = Color(150, 20, 20, 220), Color(255, 220, 220)
    hook.Add("HUDPaint", "FactionsExt_CurfewHUD", function()
        if not CurfewState.active then return end
        local remaining = math.max(0, CurfewState.endTime - CurTime())
        local text = "КОМЕНДАНТСКИЙ ЧАС — " .. string.format("%02d:%02d", math.floor(remaining / 60), math.floor(remaining % 60))

        surface.SetFont("FactionsExt_Title")
        local tw, th = surface.GetTextSize(text)
        local x, y = ScrW() / 2 - tw / 2, 40

        draw.RoundedBox(6, x - 12, y - 6, tw + 24, th + 12, COL_CURFEW_BG)
        draw.SimpleText(text, "FactionsExt_Title", x, y, COL_CURFEW_TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end)

    -- GNews client receiver/command.
    net.Receive("GNews_Message", function()
        local r, g, b = net.ReadUInt(8), net.ReadUInt(8), net.ReadUInt(8)
        local tag = net.ReadString()
        local playerName = net.ReadString()
        local role = net.ReadString()
        local message = net.ReadString()
        chat.AddText(
            Color(255, 60, 60), "[Гос.Новости] ",
            Color(r, g, b), "[" .. tag .. "]\n",
            Color(100, 200, 255), playerName,
            Color(230, 230, 230), " (" .. role .. "): ",
            Color(255, 255, 255), message
        )
    end)

    hook.Add("GRMRPChat_ClientCommand", "FactionsExt_GNews_PlayerCommand", function(ply, text)
        local datapack = { tostring(text or ""), SkipPlayerSay = false }
            if ply ~= LocalPlayer() then return end
            local msg = datapack[1]
            if not msg then return end
            local lower = safeLower(msg)

            if string.find(lower, "^/gnews%s+") == 1 then
                local text = trim(string.sub(msg, 7))
                if text ~= "" then
                    net.Start("GNews_Send")
                        net.WriteString(text)
                    net.SendToServer()
                end
                datapack[1] = ""
                return
            end

        if datapack.SkipPlayerSay == true then return true end
    end)

    timer.Simple(1, function()
        net.Start(NET_MODELS_REQUEST)
        net.SendToServer()
    end)

    print("[Factions Extended] Client loaded: fixed UI/model-browser/mask-v2")
end

-- Вечер-18: единый словарь slash-команд: имена живого PlayerSay-обработчика
-- вносятся во внешний реестр библиотеки (на режиме сверка идёт ДО ParseSay —
-- без регистрации команда стала бы «неизвестной»).
if GRM and GRM.Chat and GRM.Chat.RegisterExternalCommands then
    GRM.Chat.RegisterExternalCommands({ "/gnews", "/maskdesc" })
end
