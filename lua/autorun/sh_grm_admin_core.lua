--[[--------------------------------------------------------------------
    GRM Admin Core v1.0.0 — собственная административная база

    Заказ владельца (18.08): «сервер на ULX/ULib, но нужна полностью своя
    база со своим админ-меню: сохранения, фракционный контроль, создание
    привилегий и редактирование полномочий, модерация игроков (ТП/мут/
    джаил/рагдолл), читерские функции суперадмина — при полной синхронизации
    с ULX/ULib, чтобы ничего не сломать».

    ЧТО ЭТО.
    Своя система ГРУПП и ПРАВ, живущая в GRM, но говорящая с внешним миром
    на общем языке:
      • CAMI (Common Admin Mod Interface) — стандарт, который понимают ULX,
        SAM, ServerGuard, DarkRP и большинство аддонов. Мы регистрируем в нём
        свои группы и привилегии и отвечаем на запросы доступа.
      • ULib/ULX — если установлен, группы и назначения зеркалируются в него
        (ULib.ucl), чтобы ulx-команды, меню и чужие модули продолжали работать.
      • Стандартные проверки движка (`ply:IsAdmin()`, `IsSuperAdmin()`,
        `GetUserGroup()`) остаются валидными: группа игрока ставится через
        `SetUserGroup`.

    МОДЕЛЬ.
      Группа: id, название, цвет, наследование (inherit), иммунитет (0..100),
              набор прав, флаги admin/superadmin для совместимости.
      Право:  id вида "category.action", название, категория, опасность.
      Назначение: SteamID64 → группа (+ срок, заметка, кем выдано).

    ХРАНЕНИЕ. data/grm_admin/groups.json, data/grm_admin/users.json
    ПРОВЕРКА. GRM.Admin.Can(ply, "perm.id") — единая точка для всей сборки.
    ИММУНИТЕТ. Нельзя применять модерацию к игроку с иммунитетом >= своего
              (суперадмин игнорирует это правило).

    Консоль: grm_admin_groups (печать групп), grm_admin_perms (печать прав),
             grm_admin_sync (пересинхронизация с ULib/CAMI).
----------------------------------------------------------------------]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Admin = GRM.Admin or {}
local AD = GRM.Admin
AD.Version = "1.0.0"

AD.Groups = AD.Groups or {}          -- id -> группа
AD.Users  = AD.Users or {}           -- steamid64 -> { group, until, note, by }
AD.Perms  = AD.Perms or {}           -- id -> описание права
AD.PermOrder = AD.PermOrder or {}

local GROUPS_FILE = "grm_admin/groups.json"
local USERS_FILE  = "grm_admin/users.json"

local NET_SYNC   = "GRM_Admin_Sync"      -- сервер → клиент: группы/права/назначения
local NET_SAVE   = "GRM_Admin_Save"      -- клиент → сервер: сохранить группы
local NET_ASSIGN = "GRM_Admin_Assign"    -- клиент → сервер: назначить группу игроку
local NET_ACT    = "GRM_Admin_Act"       -- клиент → сервер: действие модерации
local NET_PLAYERS= "GRM_Admin_Players"   -- сервер → клиент: срез по игрокам
local NET_REQ    = "GRM_Admin_Request"   -- клиент → сервер: запрос данных
local NET_RESULT = "GRM_Admin_Result"    -- сервер → клиент: результат действия
local NET_ANNOUNCE = "GRM_Admin_Announce" -- сервер → всем: объявление в чат

AD.Net = {
    SYNC = NET_SYNC, SAVE = NET_SAVE, ASSIGN = NET_ASSIGN, ACT = NET_ACT,
    PLAYERS = NET_PLAYERS, REQ = NET_REQ, RESULT = NET_RESULT, ANNOUNCE = NET_ANNOUNCE,
}

--- Как показать группу в списках: название и цвет берём из самой группы,
--  а не из захардкоженной таблицы в TAB-меню.
function AD.GroupLabel(groupID)
    local group = AD.Groups and AD.Groups[string.lower(tostring(groupID or ""))]
    if istable(group) then
        local name = tostring(group.name or groupID)
        local col = istable(group.color) and group.color or nil
        return name, col
    end
    return tostring(groupID or "user"), nil
end

-----------------------------------------------------------------------
-- РЕЕСТР ПРАВ
-----------------------------------------------------------------------
--[[ Право регистрируется модулем один раз. minAccess — кому оно доступно
     по умолчанию, если группа явно ничего не говорит:
        "user"       — всем
        "admin"      — группам с флагом admin
        "superadmin" — только суперадминам
     danger = true помечает опасные (читерские) права в интерфейсе. ]]
function AD.RegisterPerm(id, data)
    id = string.lower(string.Trim(tostring(id or "")))
    if id == "" then return false end
    data = istable(data) and data or {}

    local existing = AD.Perms[id]
    local row = existing or {}
    row.id = id
    row.label = tostring(data.label or row.label or id)
    row.category = tostring(data.category or row.category or "Прочее")
    row.minAccess = tostring(data.minAccess or row.minAccess or "admin")
    row.danger = data.danger == true or row.danger == true
    row.desc = tostring(data.desc or row.desc or "")
    AD.Perms[id] = row
    if not existing then AD.PermOrder[#AD.PermOrder + 1] = id end

    -- Зеркалим в CAMI, чтобы чужие админ-моды видели наше право.
    if CAMI and CAMI.RegisterPrivilege then
        CAMI.RegisterPrivilege({
            Name = "grm_" .. id,
            MinAccess = (row.minAccess == "user" and "user")
                or (row.minAccess == "superadmin" and "superadmin") or "admin",
            Description = row.label,
        })
    end
    return true
end

function AD.PermList()
    local out = {}
    for _, id in ipairs(AD.PermOrder) do
        local row = AD.Perms[id]
        if row then out[#out + 1] = row end
    end
    table.sort(out, function(a, b)
        if a.category == b.category then return a.label < b.label end
        return a.category < b.category
    end)
    return out
end

-- Базовый набор прав сборки.
local BASE_PERMS = {
    -- Меню и разделы
    { "menu.open",            "Открывать админ-меню GRM",              "Меню",        "admin" },
    { "menu.modules",         "Видеть состояние модулей и загрузки",   "Меню",        "admin" },

    -- Модерация
    { "mod.goto",             "Телепорт к игроку",                     "Модерация",   "admin" },
    { "mod.bring",            "Телепорт игрока к себе",                "Модерация",   "admin" },
    { "mod.return",           "Вернуть игрока на прежнее место",       "Модерация",   "admin" },
    { "mod.freeze",           "Заморозить / разморозить игрока",       "Модерация",   "admin" },
    { "mod.mute",             "Мут текстового чата",                   "Модерация",   "admin" },
    { "mod.gag",              "Мут голосового чата",                   "Модерация",   "admin" },
    { "mod.jail",             "Посадить в клетку / выпустить",         "Модерация",   "admin" },
    { "mod.ragdoll",          "Рагдоллинг игрока",                     "Модерация",   "admin" },
    { "mod.slay",             "Убить игрока",                          "Модерация",   "admin" },
    { "mod.respawn",          "Воскресить игрока",                     "Модерация",   "admin" },
    { "mod.heal",             "Лечение и броня",                       "Модерация",   "admin" },
    { "mod.strip",            "Забрать оружие",                        "Модерация",   "admin" },
    { "mod.spectate",         "Наблюдение за игроком",                 "Модерация",   "admin" },
    { "mod.kick",             "Кик с сервера",                         "Модерация",   "admin" },
    { "mod.ban",              "Бан",                                   "Модерация",   "superadmin" },
    { "mod.warn",             "Предупреждение игроку",                 "Модерация",   "admin" },

    -- Управление сборкой
    { "server.persistence",   "Сохранения и загрузка карты",           "Сервер",      "superadmin" },
    { "server.factions",      "Фракционный контроль",                  "Сервер",      "admin" },
    { "server.economy",       "Экономика и казна",                     "Сервер",      "superadmin" },
    { "server.cleanup",       "Очистка мусора и пропов",               "Сервер",      "admin" },
    { "server.settings",      "Настройки сервера (зона бана и прочее)", "Сервер",      "superadmin" },

    -- Права над правами
    { "acl.groups",           "Создание и правка групп",               "Привилегии",  "superadmin" },
    { "acl.assign",           "Назначение групп игрокам",              "Привилегии",  "superadmin" },

    -- «Читерские» возможности суперадмина
    { "cheat.god",            "Режим бога",                            "Суперадмин",  "superadmin", true },
    { "cheat.noclip",         "Ноклип где угодно",                     "Суперадмин",  "superadmin", true },
    { "cheat.cloak",          "Невидимость",                           "Суперадмин",  "superadmin", true },
    { "cheat.speed",          "Изменение скорости",                    "Суперадмин",  "superadmin", true },
    { "cheat.money",          "Выдача и списание денег",               "Суперадмин",  "superadmin", true },
    { "cheat.items",          "Выдача предметов и оружия",             "Суперадмин",  "superadmin", true },
    { "cheat.teleport_pos",   "Телепорт в точку прицела",              "Суперадмин",  "superadmin", true },
    { "cheat.buildmode",      "Строительный режим (бессмертие+ноклип)","Суперадмин",  "superadmin", true },
    { "cheat.freezeall",      "Заморозить всех",                       "Суперадмин",  "superadmin", true },
}
for _, row in ipairs(BASE_PERMS) do
    AD.RegisterPerm(row[1], { label = row[2], category = row[3], minAccess = row[4], danger = row[5] })
end

-----------------------------------------------------------------------
-- ГРУППЫ
-----------------------------------------------------------------------
AD.DefaultGroups = {
    {
        id = "user", name = "Игрок", color = { r = 190, g = 200, b = 210 },
        inherit = "", immunity = 0, admin = false, superadmin = false, perms = {},
    },
    {
        id = "moderator", name = "Модератор", color = { r = 90, g = 190, b = 130 },
        inherit = "user", immunity = 20, admin = true, superadmin = false,
        perms = {
            ["menu.open"] = true, ["mod.goto"] = true, ["mod.bring"] = true, ["mod.return"] = true,
            ["mod.freeze"] = true, ["mod.mute"] = true, ["mod.gag"] = true, ["mod.warn"] = true,
            ["mod.spectate"] = true,
        },
    },
    {
        id = "admin", name = "Администратор", color = { r = 70, g = 150, b = 240 },
        inherit = "moderator", immunity = 50, admin = true, superadmin = false,
        perms = {
            ["mod.jail"] = true, ["mod.ragdoll"] = true, ["mod.slay"] = true, ["mod.respawn"] = true,
            ["mod.heal"] = true, ["mod.strip"] = true, ["mod.kick"] = true,
            ["char.manage"] = true,
            ["server.factions"] = true, ["server.cleanup"] = true, ["menu.modules"] = true,
        },
    },
    {
        id = "superadmin", name = "Суперадминистратор", color = { r = 245, g = 195, b = 65 },
        inherit = "admin", immunity = 100, admin = true, superadmin = true,
        perms = { ["*"] = true },
    },
}

function AD.NewGroup(id, name)
    id = string.lower(string.Trim(tostring(id or ""))):gsub("[^a-z0-9_]", "")
    if id == "" then return nil end
    return {
        id = id, name = tostring(name or id), color = { r = 160, g = 170, b = 185 },
        inherit = "user", immunity = 10, admin = false, superadmin = false, perms = {},
    }
end

function AD.Group(id)
    return AD.Groups[string.lower(tostring(id or ""))]
end

function AD.GroupChain(id, depth)
    depth = (depth or 0) + 1
    local group = AD.Group(id)
    if not group or depth > 12 then return {} end
    local chain = { group }
    if group.inherit and group.inherit ~= "" and group.inherit ~= group.id then
        for _, parent in ipairs(AD.GroupChain(group.inherit, depth)) do chain[#chain + 1] = parent end
    end
    return chain
end

function AD.GroupOf(ply)
    if not IsValid(ply) then return "user" end
    local sid = tostring(ply:SteamID64() or "")
    local row = AD.Users[sid]
    if istable(row) and isstring(row.group) and AD.Groups[row.group] then
        if not row["until"] or row["until"] == 0 or row["until"] > os.time() then
            return row.group
        end
    end
    -- Фолбэк — группа движка/ULX (полная совместимость: если админ выдан
    -- через ulx, GRM это видит и уважает).
    local engine = string.lower(tostring(ply:GetUserGroup() or "user"))
    if AD.Groups[engine] then return engine end
    if ply:IsSuperAdmin() then return "superadmin" end
    if ply:IsAdmin() then return "admin" end
    return "user"
end

function AD.Immunity(ply)
    local group = AD.Group(AD.GroupOf(ply))
    if not group then return 0 end
    local best = tonumber(group.immunity) or 0
    for _, g in ipairs(AD.GroupChain(group.id)) do
        best = math.max(best, tonumber(g.immunity) or 0)
    end
    return best
end

function AD.IsSuper(ply)
    if not IsValid(ply) then return true end   -- консоль сервера
    if ply:IsSuperAdmin() then return true end
    local group = AD.Group(AD.GroupOf(ply))
    return group ~= nil and group.superadmin == true
end

--[[ Главная проверка. Порядок:
       1) консоль сервера и суперадмин — всё;
       2) явное правило в группе (или её родителях): true/false;
       3) "*" в группе — всё;
       4) minAccess права: user — всем, admin — админским группам;
       5) CAMI: спрашиваем внешний админ-мод (ULX и прочие). ]]
--[[ Проверка БЕЗ обращения к внешнему админ-моду.

     Именно её зовёт наш ответчик CAMI. Раньше и проверка, и ответ ходили
     через одну функцию AD.Can: она спрашивала CAMI, CAMI дёргал наш хук,
     хук снова звал AD.Can — и сервер сыпал «[ULib] stack overflow», а любое
     действие, где проверялось право (публикация закона, например), просто
     обрывалось на середине. ]]
function AD.CanLocal(ply, perm)
    perm = string.lower(string.Trim(tostring(perm or "")))
    if perm == "" then return false end
    if not IsValid(ply) then return true end
    if AD.IsSuper(ply) then return true end

    local chain = AD.GroupChain(AD.GroupOf(ply))
    for _, group in ipairs(chain) do
        local perms = istable(group.perms) and group.perms or {}
        if perms[perm] == true then return true end
        if perms[perm] == false then return false end
        if perms["*"] == true then return true end
    end

    local def = AD.Perms[perm]
    if def then
        -- Право уровня "user" доступно всем.
        if def.minAccess == "user" then return true end

        -- Права уровня "admin" НЕ выдаются автоматически всем админским
        -- группам: иначе матрица полномочий была бы бесполезной — модератор
        -- получал бы клетку и баны просто потому, что он «админ». Нужна
        -- явная галочка в группе (см. цикл выше).
        --
        -- Исключение — совместимость: если игрок админ движка/ULX, но в
        -- реестре GRM его группы вообще нет (первый запуск, чужая группа
        -- из ULX), не оставляем сервер без управления.
        local groupID = AD.GroupOf(ply)
        if def.minAccess == "admin" and not AD.Groups[groupID] and ply:IsAdmin() then
            return true
        end
    end

    return false
end

--[[ Главная проверка. Порядок:
       1) консоль сервера и суперадмин — всё;
       2) явное правило в группе (или её родителях): true/false;
       3) "*" в группе — всё;
       4) minAccess права: user — всем, admin — админским группам;
       5) CAMI: спрашиваем внешний админ-мод (ULX и прочие). ]]
AD._camiDepth = AD._camiDepth or 0

function AD.Can(ply, perm)
    perm = string.lower(string.Trim(tostring(perm or "")))
    if perm == "" then return false end
    if AD.CanLocal(ply, perm) then return true end

    -- Внешний админ-мод может знать больше (например, право выдано в ULX).
    -- Глубину сторожим: если мы уже внутри чужого запроса, второй раз в
    -- CAMI не идём — так рекурсия невозможна в принципе.
    if CAMI and CAMI.PlayerHasAccess and AD._camiDepth == 0 then
        AD._camiDepth = 1
        local ok, allowed = pcall(CAMI.PlayerHasAccess, ply, "grm_" .. perm, nil)
        AD._camiDepth = 0
        if ok and allowed == true then return true end
    end
    return false
end

-- Можно ли применять действие к цели (иммунитет).
--[[ МОСТ ПРАВ (заказ владельца 22.08: «выдал доступ — ничего не изменилось»).

     У сервера два реестра прав, и они не знали друг о друге:
       • GRM.Access — capability вида `plates.issue`, их спрашивают модули;
       • админ-платформа — права групп, которые владелец отмечает в /admin.
     Отметить `plates.issue` в /admin было можно, а модуль об этом не узнавал.
     Теперь платформа зарегистрирована ПРОВАЙДЕРОМ доступа: любой capability
     сначала ищется в её группах.

     Зовём именно CanLocal, а не Can: Can ходит в CAMI, CAMI зовёт наш хук —
     и получается «[ULib] stack overflow». Этот урок уже был. ]]
if SERVER and GRM.Access and GRM.Access.RegisterProvider then
    GRM.Access.RegisterProvider("grm_admin_platform", 50, function(ply, capability)
        if not (IsValid(ply) and isstring(capability)) then return nil end
        if AD.CanLocal(ply, capability) == true then return true, "admin_platform" end
        return nil
    end)
end

function AD.CanTarget(actor, target)
    if not IsValid(target) then return false, "Цель не найдена" end
    if not IsValid(actor) then return true end
    if actor == target then return true end
    if AD.IsSuper(actor) then return true end
    if AD.Immunity(target) >= AD.Immunity(actor) then
        return false, "У цели равный или больший иммунитет"
    end
    return true
end

-----------------------------------------------------------------------
-- СЕРВЕР: ХРАНЕНИЕ, СИНХРОНИЗАЦИЯ, МОСТЫ
-----------------------------------------------------------------------
if SERVER then
    util.AddNetworkString(NET_SYNC)
    util.AddNetworkString(NET_SAVE)
    util.AddNetworkString(NET_ASSIGN)
    util.AddNetworkString(NET_ACT)
    util.AddNetworkString(NET_PLAYERS)
    util.AddNetworkString(NET_REQ)
    util.AddNetworkString(NET_RESULT)
    util.AddNetworkString(NET_ANNOUNCE)

    local function ensureDir()
        if not file.IsDir("grm_admin", "DATA") then file.CreateDir("grm_admin") end
    end

    local function jsonT(txt)
        local ok, t = pcall(util.JSONToTable, txt, false, true)
        return (ok and istable(t)) and t or nil
    end

    function AD.SaveGroups(why)
        ensureDir()
        local rows = {}
        for id, group in pairs(AD.Groups) do rows[id] = group end
        local ok, encoded = pcall(util.TableToJSON, { version = 1, groups = rows }, true)
        if ok and isstring(encoded) then file.Write(GROUPS_FILE, encoded) end
        if GRM.Audit and GRM.Audit.Write then
            GRM.Audit.Write("admin", "groups.save", nil, { why = tostring(why or "") }, {})
        end
        return true
    end

    function AD.SaveUsers(why)
        ensureDir()
        local ok, encoded = pcall(util.TableToJSON, { version = 1, users = AD.Users }, true)
        if ok and isstring(encoded) then file.Write(USERS_FILE, encoded) end
        if GRM.Audit and GRM.Audit.Write then
            GRM.Audit.Write("admin", "users.save", nil, { why = tostring(why or "") }, {})
        end
        return true
    end

    function AD.LoadGroups()
        local raw = file.Read(GROUPS_FILE, "DATA")
        local data = raw and jsonT(raw) or nil
        AD.Groups = {}
        if istable(data) and istable(data.groups) then
            for id, group in pairs(data.groups) do
                if istable(group) then
                    group.id = string.lower(tostring(id))
                    group.perms = istable(group.perms) and group.perms or {}
                    AD.Groups[group.id] = group
                end
            end
        end
        -- Гарантируем базовые группы (без них нечем управлять сервером).
        for _, group in ipairs(AD.DefaultGroups) do
            if not AD.Groups[group.id] then AD.Groups[group.id] = table.Copy(group) end
        end
        return AD.Groups
    end

    function AD.LoadUsers()
        local raw = file.Read(USERS_FILE, "DATA")
        local data = raw and jsonT(raw) or nil
        AD.Users = (istable(data) and istable(data.users)) and data.users or {}
        return AD.Users
    end

    --[[ Импорт того, что уже настроено в ULX/ULib: группы и назначения.
         Делается один раз (флаг imported), чтобы не затирать правки. ]]
    function AD.ImportFromULib(force)
        if not (ULib and ULib.ucl) then return false, "ULib не установлен" end
        if AD.Users._ulibImported == true and not force then return false, "уже импортировано" end

        local addedGroups, addedUsers = 0, 0

        for name, data in pairs(ULib.ucl.groups or {}) do
            local id = string.lower(tostring(name))
            if id ~= "" and not AD.Groups[id] then
                local group = AD.NewGroup(id, name)
                if group then
                    group.inherit = string.lower(tostring(data.inherit_from or "user"))
                    group.admin = (id == "admin" or id == "superadmin"
                        or group.inherit == "admin" or group.inherit == "superadmin")
                    group.superadmin = (id == "superadmin" or group.inherit == "superadmin")
                    group.immunity = group.superadmin and 100 or (group.admin and 50 or 10)
                    AD.Groups[id] = group
                    addedGroups = addedGroups + 1
                end
            end
        end

        for sid, data in pairs(ULib.ucl.users or {}) do
            local sid64 = util.SteamIDTo64(tostring(sid) or "") or ""
            local groupName = istable(data) and string.lower(tostring(data.group or "")) or ""
            if sid64 ~= "" and groupName ~= "" and AD.Groups[groupName] and not AD.Users[sid64] then
                AD.Users[sid64] = { group = groupName, ["until"] = 0, note = "импорт из ULX", by = "ULib" }
                addedUsers = addedUsers + 1
            end
        end

        AD.Users._ulibImported = true
        AD.SaveGroups("import from ULib")
        AD.SaveUsers("import from ULib")
        return true, ("группы: %d, назначения: %d"):format(addedGroups, addedUsers)
    end

    -- Регистрация групп в CAMI, чтобы чужие модули знали о них.
    function AD.PublishCAMI()
        if not (CAMI and CAMI.RegisterUsergroup) then return false end
        for id, group in pairs(AD.Groups) do
            CAMI.RegisterUsergroup({
                Name = id,
                Inherits = (group.inherit ~= "" and group.inherit) or "user",
                CAMI_Source = "GRM",
            }, "GRM")
        end
        return true
    end

    --[[ Применение группы к игроку: движок + ULib + CAMI.
         Так все три мира видят одно и то же, и модули не ломаются. ]]
    function AD.ApplyGroup(ply, groupID, actor, opts)
        if not IsValid(ply) then return false, "Игрок не найден" end
        groupID = string.lower(tostring(groupID or "user"))
        if not AD.Groups[groupID] then return false, "Такой группы нет" end
        opts = istable(opts) and opts or {}

        local sid64 = tostring(ply:SteamID64() or "")
        local old = AD.GroupOf(ply)

        AD.Users[sid64] = {
            group = groupID,
            ["until"] = math.max(0, math.floor(tonumber(opts["until"]) or 0)),
            note = string.sub(tostring(opts.note or ""), 1, 160),
            by = IsValid(actor) and (actor:Nick() .. " [" .. tostring(actor:SteamID64() or "") .. "]") or "консоль",
            at = os.time(),
        }
        AD.SaveUsers("assign " .. sid64 .. " -> " .. groupID)

        -- 1) движок
        ply:SetUserGroup(groupID)

        -- 2) ULib/ULX
        if ULib and ULib.ucl and ULib.ucl.addUser then
            local ok = pcall(ULib.ucl.addUser, ply:SteamID(), nil, nil, groupID)
            if not ok then pcall(ULib.ucl.addUser, ply:SteamID(), {}, {}, groupID) end
        end

        -- 3) CAMI (SAM, ServerGuard, DarkRP и прочие подписчики)
        if CAMI and CAMI.SignalUserGroupChanged then
            pcall(CAMI.SignalUserGroupChanged, ply, old, groupID, "GRM")
        end

        if GRM.Audit and GRM.Audit.Write then
            GRM.Audit.Write("admin", "group.assign", actor,
                { steamid64 = sid64, nick = ply:Nick() }, { from = old, to = groupID, note = opts.note })
        end
        -- Группа висит на игроке NW-строкой: TAB-меню и любой другой модуль
        -- читают её без запроса к серверу и видят изменение сразу.
        ply:SetNWString("GRM_AdminGroup", groupID)

        hook.Run("GRM_AdminGroupChanged", ply, old, groupID)
        AD.SyncTo(nil)

        local oldName = AD.GroupLabel(old)
        local newName = AD.GroupLabel(groupID)
        local actorName = IsValid(actor) and (actor:GetNWString("GRM_RPName", "") ~= "" and
            actor:GetNWString("GRM_RPName", "") or actor:Nick()) or "Консоль"
        AD.Announce(("%s изменил группу игрока %s: %s → %s"):format(
            actorName, ply:Nick(), oldName, newName), "group")

        return true, ("Группа игрока %s: %s → %s"):format(ply:Nick(), old, groupID)
    end

    -- Синхронизация справочников клиенту (или всем).
    --[[ Широковещательный снимок прав пересобирается и уходит ВСЕМ. Правки
         прав идут пачками (галочки в панели), поэтому пачку сводим в одну
         рассылку: пересборка таблицы и сеть — не на каждый клик. ]]
    --[[ ОБЪЯВЛЕНИЕ В ЧАТ (заказ владельца 21.08). Назначения групп и любые
         наказания должны видеть все — красной строкой, как уведомление.
         Один слой на всё: и группы, и модерация зовут именно его. ]]
    function AD.Announce(text, kind)
        text = tostring(text or "")
        if text == "" then return false end
        net.Start(NET_ANNOUNCE)
        net.WriteString(text)
        net.WriteString(tostring(kind or "mod"))
        net.Broadcast()
        print("[GRM Admin] " .. text)
        return true
    end

    function AD.SyncTo(ply)
        if not IsValid(ply) and GRM.Perf and GRM.Perf.Coalesce then
            return GRM.Perf.Coalesce("grm_admin_sync_all", 0.5, function() AD.SyncNow() end)
        end
        return AD.SyncNow(ply)
    end

    function AD.SyncNow(ply)
        local perms = {}
        for _, row in ipairs(AD.PermList()) do
            perms[#perms + 1] = {
                id = row.id, label = row.label, category = row.category,
                minAccess = row.minAccess, danger = row.danger == true,
            }
        end
        --[[ Группы, права и назначения — крупная таблица, а рассылалась
             всем одним пакетом при каждом изменении: заметный рывок у всех
             сразу. Уходит потоком, куски собираются на клиенте. ]]
        hook.Run("GRM_AccessChanged", "admin_platform")
        local payload = { groups = AD.Groups, perms = perms, users = AD.Users }
        if GRM.Net and GRM.Net.Stream then
            GRM.Net.Stream(NET_SYNC, payload, IsValid(ply) and ply or nil, { chunk = 8192, interval = 0.05 })
            return
        end
        net.Start(NET_SYNC)
            net.WriteTable(payload)
        if IsValid(ply) then net.Send(ply) else net.Broadcast() end
    end

    --- Проставить NW-группу игроку (вход, загрузка назначений, импорт ULib).
    function AD.PushGroupNW(ply)
        if not IsValid(ply) then return end
        local group = AD.GroupOf(ply)
        if ply:GetNWString("GRM_AdminGroup", "") ~= group then
            ply:SetNWString("GRM_AdminGroup", group)
        end
    end

    hook.Add("PlayerInitialSpawn", "GRM_Admin_GroupNW", function(ply)
        timer.Simple(3, function() AD.PushGroupNW(ply) end)
    end)

    function AD.PlayerRows()
        local rows = {}
        for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(ply) then
                rows[#rows + 1] = {
                    sid = tostring(ply:SteamID64() or ""),
                    nick = ply:Nick(),
                    rpName = ply:GetNWString("GRM_RPName", ""),
                    -- Номера реестра: PID — игрок (по нему банят), CID — персонаж.
                    pid = ply:GetNWString("GRM_PID", ""),
                    cid = ply:GetNWString("GRM_CID", ""),
                    group = AD.GroupOf(ply),
                    immunity = AD.Immunity(ply),
                    faction = ply:GetNWString("GRM_Faction", ""),
                    hp = ply:Health(),
                    armor = ply:Armor(),
                    ping = ply:Ping(),
                    alive = ply:Alive(),
                    muted = ply.GRM_AdminMuted == true,
                    gagged = ply.GRM_AdminGagged == true,
                    jailed = ply.GRM_AdminJailed == true,
                    serverBanned = ply:GetNWBool("GRM_ServerBanned", false),
                    frozen = ply.GRM_AdminFrozen == true,
                    ragdolled = IsValid(ply.GRM_AdminRagdoll),
                    god = ply.GRM_AdminGod == true,
                }
            end
        end
        table.sort(rows, function(a, b) return string.lower(a.nick) < string.lower(b.nick) end)
        return rows
    end

    --[[ Срез по игрокам нужен только тем, у кого открыто меню. Раньше он
         рассылался всем (Broadcast) после каждого действия: лишний трафик и
         лишние пересборки интерфейса у тех, кто меню даже не открывал. ]]
    function AD.PushPlayers(ply)
        local rows = AD.PlayerRows()
        if IsValid(ply) then
            net.Start(NET_PLAYERS)
                net.WriteTable(rows)
            net.Send(ply)
            return
        end

        local targets = {}
        for watcher in pairs(AD.Watchers or {}) do
            if IsValid(watcher) then targets[#targets + 1] = watcher end
        end
        if #targets == 0 then return end
        net.Start(NET_PLAYERS)
            net.WriteTable(rows)
        net.Send(targets)
    end

    function AD.Result(ply, ok, message)
        if not IsValid(ply) then return end
        net.Start(NET_RESULT)
            net.WriteBool(ok == true)
            net.WriteString(tostring(message or ""))
        net.Send(ply)
        -- Один результат — одно уведомление: раньше рядом с net-сообщением
        -- дублировался GRM.Notify, и админ видел каждую строку дважды
        -- («Строительный режим включён» два раза подряд).
    end

    -- Правка групп (только с правом acl.groups).
    net.Receive(NET_SAVE, function(_, ply)
        if not (IsValid(ply) and AD.Can(ply, "acl.groups")) then
            AD.Result(ply, false, "Нет права на правку групп")
            return
        end
        local data = net.ReadTable() or {}
        local groups = istable(data.groups) and data.groups or {}

        local clean = {}
        for id, group in pairs(groups) do
            id = string.lower(tostring(id)):gsub("[^a-z0-9_]", "")
            if id ~= "" and istable(group) then
                local perms = {}
                for perm, value in pairs(istable(group.perms) and group.perms or {}) do
                    if isstring(perm) and (AD.Perms[perm] or perm == "*") then
                        perms[perm] = value == true
                    end
                end
                clean[id] = {
                    id = id,
                    name = string.sub(tostring(group.name or id), 1, 48),
                    color = istable(group.color) and {
                        r = math.Clamp(math.floor(tonumber(group.color.r) or 160), 0, 255),
                        g = math.Clamp(math.floor(tonumber(group.color.g) or 170), 0, 255),
                        b = math.Clamp(math.floor(tonumber(group.color.b) or 185), 0, 255),
                    } or { r = 160, g = 170, b = 185 },
                    inherit = string.lower(tostring(group.inherit or "")):gsub("[^a-z0-9_]", ""),
                    immunity = math.Clamp(math.floor(tonumber(group.immunity) or 0), 0, 100),
                    admin = group.admin == true,
                    superadmin = group.superadmin == true,
                    perms = perms,
                }
            end
        end

        -- Базовые группы не дают удалить: иначе сервером станет некому управлять.
        for _, base in ipairs(AD.DefaultGroups) do
            if not clean[base.id] then clean[base.id] = AD.Groups[base.id] or table.Copy(base) end
        end

        AD.Groups = clean
        AD.SaveGroups("edit by " .. ply:Nick())
        AD.PublishCAMI()
        AD.SyncTo(nil)
        AD.Result(ply, true, "Группы и полномочия сохранены")
    end)

    net.Receive(NET_ASSIGN, function(_, ply)
        if not (IsValid(ply) and AD.Can(ply, "acl.assign")) then
            AD.Result(ply, false, "Нет права назначать группы")
            return
        end
        local sid = net.ReadString()
        local groupID = net.ReadString()
        local days = net.ReadUInt(16)
        local note = net.ReadString()

        local target
        for _, p in ipairs(player.GetAll()) do
            if tostring(p:SteamID64() or "") == sid then target = p break end
        end
        if not IsValid(target) then AD.Result(ply, false, "Игрок не в сети") return end

        local okTarget, why = AD.CanTarget(ply, target)
        if not okTarget then AD.Result(ply, false, why) return end

        local ok, msg = AD.ApplyGroup(target, groupID, ply, {
            ["until"] = days > 0 and (os.time() + days * 86400) or 0,
            note = note,
        })
        AD.Result(ply, ok, msg)
        AD.PushPlayers(nil)
    end)

    net.Receive(NET_REQ, function(_, ply)
        if not IsValid(ply) then return end
        if not AD.Can(ply, "menu.open") then
            AD.Result(ply, false, "Нет доступа к админ-меню")
            return
        end
        -- Пока меню открыто, игрок получает живой срез по онлайну.
        AD.Watchers = AD.Watchers or {}
        AD.Watchers[ply] = CurTime() + 180

        -- Справочники (группы и права) меняются редко и весят больше среза:
        -- шлём их не чаще раза в 30 секунд, а список игроков — всегда.
        ply._grmAdminSyncAt = ply._grmAdminSyncAt or 0
        if CurTime() >= ply._grmAdminSyncAt then
            ply._grmAdminSyncAt = CurTime() + 30
            AD.SyncTo(ply)
        end
        AD.PushPlayers(ply)
    end)

    hook.Add("PlayerDisconnected", "GRM_Admin_DropWatcher", function(ply)
        if AD.Watchers then AD.Watchers[ply] = nil end
    end)

    -- Быстрые серверные команды из меню.
    concommand.Add("grm_admin_save_all", function(ply)
        if IsValid(ply) and not AD.Can(ply, "server.persistence") then return end
        local saved = {}
        if GRM.Persistence and GRM.Persistence.SaveAll then
            pcall(GRM.Persistence.SaveAll, "admin panel")
            saved[#saved + 1] = "модули"
        end
        if GRM.VehicleDealer and GRM.VehicleDealer.SaveAll then
            pcall(GRM.VehicleDealer.SaveAll)
            saved[#saved + 1] = "дилеры"
        end
        if GRM.Vendor and GRM.Vendor.SaveMapVendors then
            pcall(GRM.Vendor.SaveMapVendors)
            saved[#saved + 1] = "торговцы"
        end
        local msg = #saved > 0 and ("Сохранено: " .. table.concat(saved, ", ")) or "Модули сохранения не найдены"
        AD.Result(ply, #saved > 0, msg)
        if not IsValid(ply) then print("[GRM Admin] " .. msg) end
    end)

    concommand.Add("grm_admin_load_all", function(ply)
        if IsValid(ply) and not AD.Can(ply, "server.persistence") then return end
        local loaded = {}
        if GRM.Persistence and GRM.Persistence.LoadAll then
            pcall(GRM.Persistence.LoadAll, "admin panel")
            loaded[#loaded + 1] = "модули"
        end
        if GRM.VehicleDealer and GRM.VehicleDealer.LoadAll then
            pcall(GRM.VehicleDealer.LoadAll)
            loaded[#loaded + 1] = "дилеры"
        end
        if GRM.Vendor and GRM.Vendor.LoadMapVendors then
            pcall(GRM.Vendor.LoadMapVendors)
            loaded[#loaded + 1] = "торговцы"
        end
        local msg = #loaded > 0 and ("Загружено: " .. table.concat(loaded, ", ")) or "Модули загрузки не найдены"
        AD.Result(ply, #loaded > 0, msg)
        if not IsValid(ply) then print("[GRM Admin] " .. msg) end
    end)

    concommand.Add("grm_admin_cleanup", function(ply)
        if IsValid(ply) and not AD.Can(ply, "server.cleanup") then return end
        local action = AD.Actions and AD.Actions.cleanup
        if not action then return end
        local ok, msg = action.fn(ply)
        AD.Result(ply, ok, msg)
    end)

    -- Обновление списка игроков раз в 3 секунды тем, у кого открыто меню.
    AD.Watchers = AD.Watchers or {}
    timer.Create("GRM_Admin_PlayerPush", 3, 0, function()
        local any = false
        for ply, expires in pairs(AD.Watchers) do
            -- Меню закрыли или игрок вышел: подписка истекает сама, чтобы не
            -- слать обновления в пустоту.
            if not IsValid(ply) or (isnumber(expires) and expires < CurTime()) then
                AD.Watchers[ply] = nil
            else
                any = true
            end
        end
        if not any then return end
        local rows = AD.PlayerRows()
        for ply in pairs(AD.Watchers) do
            if IsValid(ply) then
                net.Start(NET_PLAYERS)
                    net.WriteTable(rows)
                net.Send(ply)
            end
        end
    end)

    -- Первичная загрузка.
    local function boot()
        AD.LoadGroups()
        AD.LoadUsers()
        AD.ImportFromULib(false)
        AD.PublishCAMI()
        AD.SaveGroups("boot")
    end

    if GRM.Boot and GRM.Boot.OnMapStart then
        GRM.Boot.OnMapStart("GRM_Admin_Boot", "early", boot)
    else
        hook.Add("InitPostEntity", "GRM_Admin_Boot", boot)
    end

    -- Игрок зашёл: ставим его группу из нашей базы (и уважаем ULX, если там
    -- выше). Так админка одинаково работает в обоих мирах.
    hook.Add("PlayerInitialSpawn", "GRM_Admin_ApplyGroup", function(ply)
        timer.Simple(1, function()
            if not IsValid(ply) then return end
            local sid = tostring(ply:SteamID64() or "")
            local row = AD.Users[sid]
            if istable(row) and isstring(row.group) and AD.Groups[row.group] then
                if not row["until"] or row["until"] == 0 or row["until"] > os.time() then
                    if string.lower(tostring(ply:GetUserGroup() or "user")) ~= row.group then
                        ply:SetUserGroup(row.group)
                    end
                elseif row["until"] and row["until"] > 0 then
                    -- Срок истёк — снимаем.
                    AD.Users[sid] = nil
                    AD.SaveUsers("expire " .. sid)
                    ply:SetUserGroup("user")
                end
            end
            AD.SyncTo(ply)
        end)
    end)

    -- Внешняя смена группы (ULX/SAM) → отражаем у себя, чтобы не разъезжалось.
    hook.Add("CAMI.PlayerUsergroupChanged", "GRM_Admin_External", function(ply, old, new, source)
        if source == "GRM" or not IsValid(ply) then return end
        local sid = tostring(ply:SteamID64() or "")
        if not AD.Groups[string.lower(tostring(new or ""))] then return end
        AD.Users[sid] = {
            group = string.lower(tostring(new)), ["until"] = 0,
            note = "синхронизация из " .. tostring(source or "внешнего мода"), by = tostring(source or ""), at = os.time(),
        }
        AD.SaveUsers("external sync " .. sid)
        AD.SyncTo(nil)
    end)

    --[[ Ответ на запросы доступа от чужих модулей: если спрашивают наше
         право (grm_*), решает GRM. Это и есть «синхронизация в обратную
         сторону»: сторонний аддон, спросивший через CAMI, получит наш ответ. ]]
    hook.Add("CAMI.PlayerHasAccess", "GRM_Admin_CAMIAnswer", function(actorPly, privilegeName, callback)
        if not isstring(privilegeName) or privilegeName:sub(1, 4) ~= "grm_" then return end
        local perm = privilegeName:sub(5)
        if not AD.Perms[perm] then return end
        -- Отвечаем СВОЕЙ локальной проверкой: спросить CAMI в ответ на
        -- запрос CAMI — это и есть та самая рекурсия.
        local allowed = AD.CanLocal(actorPly, perm)
        if isfunction(callback) then callback(allowed, "GRM Admin") end
        return true
    end)

    -- ULX-обёртка: команда ulx grmadmin открывает наше меню, чтобы
    -- администраторам не переучиваться на новые команды.
    local function registerULX()
        if not (ulx and ulx.command) then return false end
        if AD._ulxRegistered then return true end
        local ok = pcall(function()
            local function openPanel(callingPlayer)
                if not IsValid(callingPlayer) then return end
                if not AD.Can(callingPlayer, "menu.open") then
                    ULib.tsayError(callingPlayer, "Нет доступа к админ-меню GRM", true)
                    return
                end
                AD.SyncTo(callingPlayer)
                AD.PushPlayers(callingPlayer)
                callingPlayer:ConCommand("grm_admin_panel")
            end
            local cmd = ulx.command("GRM", "ulx grmadmin", openPanel, "!grmadmin")
            cmd:defaultAccess(ULib.ACCESS_ADMIN)
            cmd:help("Открыть центр администрирования GRM")
        end)
        AD._ulxRegistered = ok
        return ok
    end
    hook.Add("ULibLocalPlayerReady", "GRM_Admin_ULXCmd", registerULX)
    timer.Simple(8, registerULX)

    concommand.Add("grm_admin_groups", function(ply)
        if IsValid(ply) and not AD.Can(ply, "acl.groups") then return end
        local function out(line)
            if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
        end
        out("[GRM Admin] Группы:")
        for id, group in pairs(AD.Groups) do
            local count = 0
            for perm in pairs(group.perms or {}) do count = count + 1 end
            out(("  %-16s %-24s наследует %-12s иммунитет %3d  прав: %d%s"):format(
                id, group.name or id, group.inherit ~= "" and group.inherit or "—",
                group.immunity or 0, count, group.superadmin and "  [SUPER]" or (group.admin and "  [admin]" or "")))
        end
    end)

    concommand.Add("grm_admin_perms", function(ply)
        if IsValid(ply) and not AD.Can(ply, "acl.groups") then return end
        local function out(line)
            if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
        end
        out("[GRM Admin] Права:")
        for _, row in ipairs(AD.PermList()) do
            out(("  %-24s %-12s %s%s"):format(row.id, row.minAccess, row.label, row.danger and "  (опасное)" or ""))
        end
    end)

    concommand.Add("grm_admin_sync", function(ply)
        if IsValid(ply) and not AD.IsSuper(ply) then return end
        local ok, detail = AD.ImportFromULib(true)
        AD.PublishCAMI()
        AD.SyncTo(nil)
        local msg = "[GRM Admin] Синхронизация: " .. tostring(ok and detail or detail)
        if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg) else print(msg) end
    end)
end

-----------------------------------------------------------------------
-- КЛИЕНТ: приём справочников
-----------------------------------------------------------------------
if CLIENT then
    AD.Data = AD.Data or { groups = {}, perms = {}, users = {}, players = {} }

    local function applyAdminSync(data)
        data = istable(data) and data or {}
        AD.Data.groups = istable(data.groups) and data.groups or {}
        AD.Data.perms = istable(data.perms) and data.perms or {}
        AD.Data.users = istable(data.users) and data.users or {}
        hook.Run("GRM_AdminDataUpdated")
    end

    net.Receive(NET_SYNC, function() applyAdminSync(net.ReadTable()) end)
    if GRM.Net and GRM.Net.Receive then GRM.Net.Receive(NET_SYNC, applyAdminSync) end

    net.Receive(NET_PLAYERS, function()
        AD.Data.players = net.ReadTable() or {}
        hook.Run("GRM_AdminPlayersUpdated")
    end)

    --[[ Объявления администрации: красной строкой всем, чтобы наказание и
         смена группы были событием сервера, а не тихой записью в логе. ]]
    net.Receive(NET_ANNOUNCE, function()
        local text = net.ReadString()
        local kind = net.ReadString()
        local head = kind == "group" and "[АДМИНИСТРАЦИЯ] " or "[МОДЕРАЦИЯ] "
        chat.AddText(Color(225, 70, 70), head, Color(240, 220, 220), text)
        surface.PlaySound("buttons/button17.wav")
    end)

    net.Receive(NET_RESULT, function()
        local ok, message = net.ReadBool(), net.ReadString()
        notification.AddLegacy(message, ok and NOTIFY_GENERIC or NOTIFY_ERROR, 4)
        surface.PlaySound(ok and "buttons/button14.wav" or "buttons/button10.wav")
    end)

    function AD.Request()
        net.Start(NET_REQ)
        net.SendToServer()
    end
end

print("[GRM Admin Core] v" .. AD.Version .. " loaded")
