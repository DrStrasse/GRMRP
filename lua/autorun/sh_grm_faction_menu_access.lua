--[[--------------------------------------------------------------------
    GRM Faction Menu Access v1.0.0 — кто какие разделы видит в /factions

    Заказ владельца (18.08): «в меню factions надо поправить доступы,
    некоторые вкладки видны лидерам, в том числе вкладка спецслужб. Нужна
    тонкая настройка и доступ к чувствительным моментам должен быть у
    суперадмина, а он уже решает кому и что показывать».

    Как устроено:
      • у каждого раздела меню есть УРОВЕНЬ доступа:
            admin   — только суперадмин (по умолчанию для всего чувствительного)
            leader  — лидер организации и суперадмин
            member  — любой сотрудник организации
            off     — раздел скрыт у всех, кроме суперадмина в режиме отладки
      • по умолчанию всё чувствительное закрыто на admin;
      • суперадмин меняет уровни в самом меню: раздел «Права меню»;
      • дополнительно можно выдать раздел КОНКРЕТНОЙ организации
        (исключение сильнее общего уровня).

    Хранение: data/grm_faction_menu_access.json
    Синхронизация: при изменении и при заходе игрока.
    Консоль: grm_faction_menu_access (печать текущей раскладки).
----------------------------------------------------------------------]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.MenuAccess = GRM.MenuAccess or {}
local MA = GRM.MenuAccess
MA.Version = "1.0.0"

local NET_SYNC = "GRM_FacMenuAccess_Sync"
local NET_SAVE = "GRM_FacMenuAccess_Save"
local FILE = "grm_faction_menu_access.json"

MA.Levels = { admin = 3, leader = 2, member = 1, off = 4 }
MA.LevelNames = {
    admin  = "Только суперадмин",
    leader = "Лидер организации",
    member = "Любой сотрудник",
    off    = "Скрыт",
}
MA.LevelOrder = { "member", "leader", "admin", "off" }

-- Известные разделы меню. Навесные вкладки других модулей попадают сюда
-- автоматически по ключу ext:<название>.
MA.Tabs = {
    { key = "overview",  name = "Обзор",                default = "member" },
    { key = "members",   name = "Личный состав",        default = "leader" },
    { key = "structure", name = "Структура и штат",     default = "leader" },
    { key = "positions", name = "Должности",            default = "leader" },
    { key = "personnel", name = "Кадровые дела",        default = "leader" },
    { key = "finance",   name = "Казна и финансы",      default = "leader" },
    { key = "gear",      name = "Вооружение и форма",   default = "admin"  },
    { key = "access",    name = "Доступы и связь",      default = "admin"  },
    { key = "mask",      name = "Маскировка",           default = "admin"  },
    { key = "curfew",    name = "Комендантский час",    default = "admin"  },
    { key = "security",  name = "Спецслужбы",           default = "admin"  },
    { key = "service",   name = "Служебные системы",    default = "admin"  },
    { key = "create",    name = "Создать организацию",  default = "admin"  },
}

MA.Config = MA.Config or { levels = {}, overrides = {} }

function MA.DefaultLevel(tabKey)
    tabKey = tostring(tabKey or "")
    for _, row in ipairs(MA.Tabs) do
        if row.key == tabKey then return row.default end
    end
    -- Навесные разделы других модулей (арест, экономика, логистика …) —
    -- чувствительные по определению: по умолчанию только суперадмину.
    return "admin"
end

function MA.TabName(tabKey)
    tabKey = tostring(tabKey or "")
    for _, row in ipairs(MA.Tabs) do
        if row.key == tabKey then return row.name end
    end
    if tabKey:sub(1, 4) == "ext:" then return tabKey:sub(5) end
    return tabKey
end

function MA.LevelOf(tabKey, factionName)
    tabKey = tostring(tabKey or "")
    factionName = tostring(factionName or "")

    local ov = MA.Config.overrides or {}
    local facRow = ov[factionName]
    if istable(facRow) and isstring(facRow[tabKey]) and MA.Levels[facRow[tabKey]] then
        return facRow[tabKey], true
    end

    local lvl = (MA.Config.levels or {})[tabKey]
    if isstring(lvl) and MA.Levels[lvl] then return lvl, false end
    return MA.DefaultLevel(tabKey), false
end

--[[ Видит ли игрок раздел.
     isLeader — лидер именно этой организации; isMember — состоит в ней. ]]
function MA.CanSee(tabKey, factionName, isSuperAdmin, isLeader, isMember)
    if isSuperAdmin then return true end
    local level = MA.LevelOf(tabKey, factionName)
    if level == "off" or level == "admin" then return false end
    if level == "leader" then return isLeader == true end
    return isMember == true or isLeader == true
end

-- Клиентский помощник: сам определяет роль игрока в организации.
function MA.CanSeeLocal(tabKey, factionName)
    if not CLIENT then return true end
    local lp = LocalPlayer()
    if not IsValid(lp) then return false end
    if lp:IsSuperAdmin() then return true end

    local data = FactionsData or {}
    local fac = data[factionName]
    local charKey = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(lp))
        or (tostring(lp:SteamID64() or "") .. ":char1")

    local isMember, isLeader = false, false
    if istable(fac) and istable(fac.Members) then
        local mem = fac.Members[charKey] or fac.Members[tostring(lp:SteamID64() or "")]
        if istable(mem) then
            isMember = true
            isLeader = mem.IsLeader == true or mem.Leader == true
        end
    end
    if istable(fac) and tostring(fac.Leader or "") ~= "" then
        if fac.Leader == charKey or fac.Leader == lp:SteamID64() then isLeader = true end
    end

    return MA.CanSee(tabKey, factionName, false, isLeader, isMember)
end

-- Серверная проверка: не только «спрятать кнопку», но и не пустить действие.
-- Если раздел закрыт до уровня «только суперадмин», лидер не выполнит его и
-- в обход интерфейса (консолью или подделанным net-пакетом).
function MA.PlayerCan(ply, tabKey, factionName)
    if not IsValid(ply) then return false end
    if ply:IsSuperAdmin() then return true end
    factionName = tostring(factionName or "")

    local isLeader = false
    if FactionsAPI and FactionsAPI.IsLeader then isLeader = FactionsAPI.IsLeader(ply, factionName) == true end
    local isMember = isLeader
    if not isMember then
        local f = (istable(Factions) and Factions[factionName]) or nil
        if istable(f) and GRM.Identity and GRM.Identity.FactionMember then
            isMember = GRM.Identity.FactionMember(f, ply) == true
        end
    end
    return MA.CanSee(tabKey, factionName, false, isLeader, isMember)
end

-----------------------------------------------------------------------
-- СЕРВЕР
-----------------------------------------------------------------------
if SERVER then
    util.AddNetworkString(NET_SYNC)
    util.AddNetworkString(NET_SAVE)

    function MA.Load()
        local raw = file.Read(FILE, "DATA")
        if raw and raw ~= "" then
            local ok, data = pcall(util.JSONToTable, raw, false, true)
            if ok and istable(data) then
                MA.Config.levels = istable(data.levels) and data.levels or {}
                MA.Config.overrides = istable(data.overrides) and data.overrides or {}
                return true
            end
        end
        MA.Config.levels = {}
        MA.Config.overrides = {}
        return false
    end

    function MA.Save(why)
        local ok, encoded = pcall(util.TableToJSON, {
            version = 1, levels = MA.Config.levels or {}, overrides = MA.Config.overrides or {},
        }, true)
        if not ok or not isstring(encoded) then return false end
        file.Write(FILE, encoded)
        if GRM.Audit and GRM.Audit.Write then
            GRM.Audit.Write("factions", "menu.access.save", nil, { why = tostring(why or "") }, {})
        end
        return true
    end

    function MA.Sync(ply)
        local payload = { levels = MA.Config.levels or {}, overrides = MA.Config.overrides or {} }
        if GRM.Net and GRM.Net.Stream then
            GRM.Net.Stream(NET_SYNC, payload, IsValid(ply) and ply or nil, { chunk = 8192, interval = 0.05 })
            return
        end
        net.Start(NET_SYNC)
        net.WriteTable(payload)
        if IsValid(ply) then net.Send(ply) else net.Broadcast() end
    end

    net.Receive(NET_SAVE, function(_, ply)
        if not (IsValid(ply) and ply:IsSuperAdmin()) then return end
        local data = net.ReadTable() or {}

        local levels = {}
        for key, value in pairs(istable(data.levels) and data.levels or {}) do
            if isstring(key) and isstring(value) and MA.Levels[value] then
                levels[string.sub(key, 1, 64)] = value
            end
        end

        local overrides = {}
        for fac, row in pairs(istable(data.overrides) and data.overrides or {}) do
            if isstring(fac) and istable(row) then
                local clean = {}
                for key, value in pairs(row) do
                    if isstring(key) and isstring(value) and MA.Levels[value] then
                        clean[string.sub(key, 1, 64)] = value
                    end
                end
                if next(clean) then overrides[string.sub(fac, 1, 64)] = clean end
            end
        end

        MA.Config.levels = levels
        MA.Config.overrides = overrides
        MA.Save("edit by " .. ply:Nick())
        MA.Sync()
        if GRM.Notify then GRM.Notify(ply, "Права разделов меню организаций сохранены.", 100, 220, 130) end
    end)

    hook.Add("PlayerInitialSpawn", "GRM_FacMenuAccess_Sync", function(ply)
        timer.Simple(6, function() if IsValid(ply) then MA.Sync(ply) end end)
    end)

    if GRM.Boot and GRM.Boot.OnMapStart then
        GRM.Boot.OnMapStart("GRM_FacMenuAccess_Load", "early", function() MA.Load() end)
    else
        hook.Add("InitPostEntity", "GRM_FacMenuAccess_Load", function() MA.Load() end)
    end

    concommand.Add("grm_faction_menu_access", function(ply)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        local function out(line)
            if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
        end
        out("[GRM] Права разделов меню организаций:")
        for _, row in ipairs(MA.Tabs) do
            out(("  %-26s %s"):format(row.name, MA.LevelNames[MA.LevelOf(row.key, "")] or "?"))
        end
        for fac, rows in pairs(MA.Config.overrides or {}) do
            for key, level in pairs(rows) do
                out(("  ИСКЛЮЧЕНИЕ %s / %s -> %s"):format(fac, MA.TabName(key), MA.LevelNames[level] or level))
            end
        end
    end)
end

-----------------------------------------------------------------------
-- КЛИЕНТ
-----------------------------------------------------------------------
if CLIENT then
    local function applyMenuAccess(data)
        data = istable(data) and data or {}
        MA.Config.levels = istable(data.levels) and data.levels or {}
        MA.Config.overrides = istable(data.overrides) and data.overrides or {}
        hook.Run("GRM_FacMenuAccessUpdated")
    end

    net.Receive(NET_SYNC, function() applyMenuAccess(net.ReadTable()) end)
    if GRM.Net and GRM.Net.Receive then GRM.Net.Receive(NET_SYNC, applyMenuAccess) end

    function MA.RequestSave(levels, overrides)
        net.Start(NET_SAVE)
        net.WriteTable({ levels = levels or {}, overrides = overrides or {} })
        net.SendToServer()
    end
end

print("[GRM Faction Menu Access] v" .. MA.Version .. " loaded")
