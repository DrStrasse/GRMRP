--[[--------------------------------------------------------------------
    GRM Faction Permissions v2.1.0 (Код 122)

    Гибкая система доступов для фракций к экономическим функциям.
    Доступы выдаются по ролям (рангам) внутри фракции.

    Структура данных:
    {
        ["Фракция"] = {
            roles = {
                ["Роль"] = { permission1 = true, permission2 = true, ... }
            }
        }
    }

    v2.1.0 — добавлена сетевая синхронизация: раньше клиентские вызовы
    GrantToRole/RevokeFromRole/GetFactionRoles писали в ЛОКАЛЬНЫЙ data/ клиента
    и ничего не меняли на сервере (доступы «по ролям» молча не работали).
    Теперь:
      • на сервере Grant/Revoke пишут файл и рассылают обновление клиентам;
      • на клиенте Grant/Revoke отправляют net-сообщение, а чтение идёт из
        синхронизированного PERMS.Data;
      • добавлен псевдоним HasPermission = PlayerHasPermission (его ждёт
        grm_bank_computer).
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.FactionPerms = GRM.FactionPerms or {}
local PERMS = GRM.FactionPerms

-- Файл хранения доступов
PERMS.ConfigFile = "grm_faction_perms.json"

local NET_GET  = "GRM_FPerm_Get"
local NET_DATA = "GRM_FPerm_Data"
local NET_SET  = "GRM_FPerm_Set"

-- Все доступные разрешения
PERMS.Permissions = {
    -- Гос.бюджет
    state_budget_view = "Просмотр гос.бюджета",
    state_budget_add = "Пополнение гос.бюджета",
    state_budget_remove = "Снятие с гос.бюджета",

    -- Бюджеты фракций
    faction_budget_view = "Просмотр бюджетов фракций",
    faction_budget_edit = "Редактирование бюджетов фракций",

    -- Налоги
    tax_view = "Просмотр налогов",
    tax_edit = "Редактирование налоговых ставок",

    -- Штрафы
    fine_issue = "Выдача штрафов",
    fine_configure = "Настройка штрафов",

    -- Ком.час
    kom_hour_set = "Установка комендантского часа",
    kom_hour_remove = "Снятие комендантского часа",

    -- Законы
    law_publish = "Публикация законов",
    law_remove = "Удаление законов",

    -- Инкассация (Код 126)
    incasso_start = "Активация рейса инкассации (/incass)",
    incasso_deliver = "Сдача денег в хранилище (/incass_delivery)",

    -- Закрепление объектов на карте (Задача 9)
    perm_manage = "Закрепление объектов на карте (перм-инструмент)",

    -- Автопарк организации (закупка транспорта)
    fleet_buy = "Закупка транспорта в автопарк организации",
    fleet_manage = "Распоряжение автопарком (приписка к гаражу, списание)",

    -- Номерные знаки (учёт транспорта)
    plates_issue = "Регистрация номерных знаков (выдача и аннулирование)",
    plates_check = "Проверка номеров по базе учёта транспорта",

    -- Связь и наблюдение
    phone_equipment = "Связь: доступ к оборудованию (АТС, терминалы)",
    phone_wiretap = "Связь: прослушка телефонов и помещений",
    cctv_view = "Видеонаблюдение: просмотр камер",
    cctv_manage = "Видеонаблюдение: настройка камер и серверов",
}

-- Загрузка доступов (сервер читает файл; на клиенте — сброс пустой).
function PERMS.Load()
    if not file.Exists(PERMS.ConfigFile, "DATA") then
        PERMS.Data = {}
        return
    end
    local data = file.Read(PERMS.ConfigFile, "DATA")
    local ok, tbl = pcall(util.JSONToTable, data)
    if ok and istable(tbl) then
        PERMS.Data = tbl
    else
        PERMS.Data = {}
    end
end

-- Сохранение доступов (только сервер).
function PERMS.Save()
    local ok, data = pcall(util.TableToJSON, PERMS.Data or {}, true)
    if ok then
        file.Write(PERMS.ConfigFile, data)
    end
end

--[[ ДОСТУПЫ ДОЛЖНОСТЕЙ (ось v5, GRM.Positions).

     Раньше источник права был один — звание. Из-за этого право «распоряжаться
     автопарком» получали ВСЕ сержанты организации, а не начальник
     транспортного отдела. Отделить было нечем.

     Теперь источников три, и они складываются по ИЛИ:
        1) право звания      (как раньше, ничего не сломано);
        2) право должности   (новое);
        3) персональный грант GRM.Access (был и остался).

     Права должностей лежат отдельно от прав званий, поэтому старый файл
     доступов читается как есть:
        PERMS.Data[организация].positions[ключДолжности][право] = true

     НАСЛЕДОВАНИЕ. Начальник узла может наследовать права должностей своего
     подразделения. По умолчанию ВЫКЛЮЧЕНО — молча раздавать доступы опасно.
     Включается флагом организации, отдельно для каждой.

     ЗАМЕЩЕНИЕ. Заместитель может получать права начальника, когда того нет
     в сети. По умолчанию тоже ВЫКЛЮЧЕНО, включается тем же флагом. ]]
PERMS.PositionDefaults = {
    inherit = false,    -- начальник наследует права подчинённых должностей узла
    standin = false,    -- заместитель замещает начальника, когда тот не в сети
}

--- Настройки должностных прав организации.
function PERMS.PositionSettings(factionName)
    local fd = PERMS.Data and PERMS.Data[tostring(factionName or "")] or {}
    local cfg = istable(fd.positionSettings) and fd.positionSettings or {}
    return {
        inherit = cfg.inherit == true,
        standin = cfg.standin == true,
    }
end

--- Право конкретной должности (без наследования).
function PERMS.PositionHasPermission(factionName, positionID, permission)
    if not factionName or not positionID or not permission then return false end
    local fd = PERMS.Data and PERMS.Data[factionName] or {}
    local store = istable(fd.positions) and fd.positions or {}
    local row = store[tostring(positionID)]
    return istable(row) and row[permission] == true
end

function PERMS.GetPositionPerms(factionName, positionID)
    local fd = PERMS.Data and PERMS.Data[factionName] or {}
    local store = istable(fd.positions) and fd.positions or {}
    return store[tostring(positionID)] or {}
end

function PERMS.GetFactionPositions(factionName)
    local fd = PERMS.Data and PERMS.Data[factionName] or {}
    return istable(fd.positions) and fd.positions or {}
end

--[[ Есть ли право у должности с учётом наследования и замещения.
     Возвращает: есть ли право, причина (для диагностики). ]]
function PERMS.PositionGrants(factionName, positionID, permission, ply)
    positionID = tostring(positionID or "")
    if positionID == "" then return false end
    if PERMS.PositionHasPermission(factionName, positionID, permission) then
        return true, "position:" .. positionID
    end

    local POS = GRM.Positions
    if not (POS and POS.Get) then return false end
    local own = POS.Get(factionName, positionID)
    if not own then return false end
    local cfg = PERMS.PositionSettings(factionName)

    --[[ Наследование: начальник узла получает права должностей, которые
         этому узлу подчинены и весят меньше. Строго вниз по дереву. ]]
    if cfg.inherit then
        for _, other in ipairs(POS.List(factionName)) do
            if other.id ~= own.id and POS.Weight(other) < POS.Weight(own)
                and PERMS.PositionHasPermission(factionName, other.id, permission) then
                -- Узел подчинённой должности должен лежать в ветке начальника.
                if own.node == "root" then return true, "inherit:" .. other.id end
                for _, node in ipairs(POS.NodeChain(factionName, other.node)) do
                    if node == own.node then return true, "inherit:" .. other.id end
                end
            end
        end
    end

    --[[ Замещение: заместитель берёт права начальника своего узла, но только
         пока начальника действительно нет в сети. ]]
    if cfg.standin and POS.NormalizeKind(own.kind) == "deputy" then
        local head = POS.HeadOfNode(factionName, own.node)
        if head and head.id ~= own.id
            and PERMS.PositionHasPermission(factionName, head.id, permission)
            and PERMS.PositionVacant(factionName, head.id, ply) then
            return true, "standin:" .. head.id
        end
    end

    return false
end

--[[ Нет ли на должности живого человека в сети (кроме самого спрашивающего).
     Нужно замещению: зам получает права, только когда начальника нет. ]]
function PERMS.PositionVacant(factionName, positionID, exceptPly)
    local POS = GRM.Positions
    if not (POS and POS.Holders) then return false end
    local holders = POS.Holders(factionName, positionID)
    if #holders == 0 then return true end
    for _, key in ipairs(holders) do
        local holder = GRM.Identity and GRM.Identity.ResolveCharacter
            and GRM.Identity.ResolveCharacter(key) or nil
        if IsValid(holder) and holder ~= exceptPly then return false end
    end
    return true
end

-- Проверить доступ роли
function PERMS.RoleHasPermission(factionName, roleName, permission)
    if not factionName or not roleName or not permission then return false end
    local factionData = PERMS.Data and PERMS.Data[factionName] or {}
    local roleData = factionData.roles or {}
    return roleData[roleName] and roleData[roleName][permission] == true
end

-- Получить все доступы роли
function PERMS.GetRolePerms(factionName, roleName)
    local factionData = PERMS.Data and PERMS.Data[factionName] or {}
    local roleData = factionData.roles or {}
    return roleData[roleName] or {}
end

-- Получить все роли с доступами для фракции
function PERMS.GetFactionRoles(factionName)
    local factionData = PERMS.Data and PERMS.Data[factionName] or {}
    return factionData.roles or {}
end

-- Проверка доступа игрока (через фракцию и роль)
function PERMS.PlayerHasPermission(ply, permission)
    if not IsValid(ply) then return false end
    if ply:IsSuperAdmin() then return true end -- Суперадмин имеет все доступы
    if Factions then
        for factionName, f in pairs(Factions) do
            if istable(f) and istable(f.Members) then
                local member = GRM.Identity and GRM.Identity.FactionMember and GRM.Identity.FactionMember(f, ply)
                if member then
                    local roleName = member.Role or "Участник"
                    if PERMS.RoleHasPermission(factionName, roleName, permission) then
                        return true
                    end
                    -- Должность — второй независимый источник права.
                    local positionID = tostring(member.Position or "")
                    if positionID ~= "" and PERMS.PositionGrants(factionName, positionID, permission, ply) then
                        return true
                    end
                end
            end
        end
    end

    --[[ ЗАПАСНОЙ ПУТЬ ПО NW-ПОЛЯМ.
         Состав организации может быть ключован иначе (SteamID против ключа
         персонажа) или ещё не подтянуться после входа и смены персонажа —
         тогда перебор Members возвращает пусто, и выданный доступ «не
         работает». На NW-поля опирается весь остальной GRM, берём их же.
         Ровно та же находка, что была с дверными категориями. ]]
    local nwFaction = ply.GetNWString and ply:GetNWString("GRM_Faction", "") or ""
    if nwFaction ~= "" then
        local nwRole = ply:GetNWString("GRM_Role", "")
        if nwRole ~= "" and PERMS.RoleHasPermission(nwFaction, nwRole, permission) then return true end
        -- отдел и подотдел тоже могут держать доступ
        local dept = ply:GetNWString("GRM_Department", "")
        local sub = ply:GetNWString("GRM_Subdepartment", "")
        if dept ~= "" and PERMS.RoleHasPermission(nwFaction, dept, permission) then return true end
        if sub ~= "" and PERMS.RoleHasPermission(nwFaction, sub, permission) then return true end
        local nwPos = ply:GetNWString("GRM_Position", "")
        if nwPos ~= "" and PERMS.PositionGrants(nwFaction, nwPos, permission, ply) then return true end
    end
    return false
end

-- Псевдоним: grm_bank_computer и др. ждут именно HasPermission.
PERMS.HasPermission = PERMS.PlayerHasPermission

if SERVER then
    util.AddNetworkString(NET_GET)
    util.AddNetworkString(NET_DATA)
    util.AddNetworkString(NET_SET)

    PERMS.Load()

    -- Выдать доступ роли во фракции (сервер: пишем файл + рассылаем).
    function PERMS.GrantToRole(factionName, roleName, permission)
        PERMS.Data = PERMS.Data or {}
        PERMS.Data[factionName] = PERMS.Data[factionName] or { roles = {} }
        PERMS.Data[factionName].roles = PERMS.Data[factionName].roles or {}
        PERMS.Data[factionName].roles[roleName] = PERMS.Data[factionName].roles[roleName] or {}
        PERMS.Data[factionName].roles[roleName][permission] = true
        PERMS.Save()
        PERMS.Broadcast()
    end

    --- Выдать доступ ДОЛЖНОСТИ (хранится отдельно от прав званий).
    function PERMS.GrantToPosition(factionName, positionID, permission)
        PERMS.Data = PERMS.Data or {}
        PERMS.Data[factionName] = PERMS.Data[factionName] or { roles = {} }
        local fd = PERMS.Data[factionName]
        fd.positions = istable(fd.positions) and fd.positions or {}
        fd.positions[positionID] = istable(fd.positions[positionID]) and fd.positions[positionID] or {}
        fd.positions[positionID][permission] = true
        PERMS.Save()
        PERMS.Broadcast()
    end

    function PERMS.RevokeFromPosition(factionName, positionID, permission)
        local fd = PERMS.Data and PERMS.Data[factionName]
        if istable(fd) and istable(fd.positions) and istable(fd.positions[positionID]) then
            fd.positions[positionID][permission] = nil
            PERMS.Save()
            PERMS.Broadcast()
        end
    end

    --- Наследование и замещение — по одному флагу на организацию.
    function PERMS.SetPositionSetting(factionName, key, value)
        key = tostring(key or "")
        if key ~= "inherit" and key ~= "standin" then return false end
        PERMS.Data = PERMS.Data or {}
        PERMS.Data[factionName] = PERMS.Data[factionName] or { roles = {} }
        local fd = PERMS.Data[factionName]
        fd.positionSettings = istable(fd.positionSettings) and fd.positionSettings or {}
        fd.positionSettings[key] = value == true or nil
        PERMS.Save()
        PERMS.Broadcast()
        return true
    end

    --[[ Должность удалили — её права должны уйти вместе с ней, иначе
         одноимённая новая должность молча унаследует чужие доступы. ]]
    hook.Add("GRM_FactionPositionChanged", "GRM_FactionPerms_PositionGone",
        function(factionName, positionID, _, kind)
            if kind ~= "delete" then return end
            local fd = PERMS.Data and PERMS.Data[factionName]
            if not (istable(fd) and istable(fd.positions) and fd.positions[positionID]) then return end
            fd.positions[positionID] = nil
            PERMS.Save()
            PERMS.Broadcast()
            print(("[GRM FactionPerms] права удалённой должности очищены: %s (%s)")
                :format(tostring(positionID), tostring(factionName)))
        end)

    -- Отозвать доступ у роли
    function PERMS.RevokeFromRole(factionName, roleName, permission)
        PERMS.Data = PERMS.Data or {}
        local fd = PERMS.Data[factionName]
        if fd and fd.roles and fd.roles[roleName] then
            fd.roles[roleName][permission] = nil
            PERMS.Save()
            PERMS.Broadcast()
        end
    end

    --[[ Переименование системного ключа должности (GRM_FactionRoleKeyRenamed):
         права выданы НА КЛЮЧ, поэтому переносим их вместе с ним, иначе после
         смены ключа должность молча теряет все доступы. ]]
    hook.Add("GRM_FactionRoleKeyRenamed", "GRM_FactionPerms_RoleKey", function(factionName, oldKey, newKey)
        local fd = PERMS.Data and PERMS.Data[factionName]
        if not (istable(fd) and istable(fd.roles) and fd.roles[oldKey] ~= nil) then return end
        fd.roles[newKey] = fd.roles[oldKey]
        fd.roles[oldKey] = nil
        PERMS.Save()
        PERMS.Broadcast()
        print(("[GRM FactionPerms] ключ должности перенесён: %s → %s (%s)"):format(oldKey, newKey, factionName))
    end)

    -- Отправить актуальные доступы одному игроку.
    function PERMS.SendTo(ply)
        if not IsValid(ply) then return end
        net.Start(NET_DATA)
            net.WriteTable(PERMS.Data or {})
        net.Send(ply)
    end

    -- Рассылка всем суперадминам (и лидерам — они видят доступы своей фракции).
    function PERMS.Broadcast()
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(p) and p:IsSuperAdmin() then
                PERMS.SendTo(p)
            end
        end
        --[[ Права поменялись — окна, которые от них зависят (номерные знаки,
             автопарк, терминалы), должны обновиться САМИ. Раньше человек
             выдавал доступ и не понимал, почему компьютер по-прежнему пишет
             «недоступно»: снимок у него был старый. ]]
        hook.Run("GRM_AccessChanged", "faction_perms")
    end

    -- Локальная проверка лидерства (без зависимости от FactionsAPI).
    local function isLeaderOfFaction(ply, factionName)
        if not IsValid(ply) or not istable(Factions) or not Factions[factionName] then return false end
        local f = Factions[factionName]
        local ck = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply)) or ply:SteamID64()
        local ldr = tostring(f.Leader or "")
        if ldr ~= "" and (ldr == ck or ldr == ply:SteamID() or ldr == ply:SteamID64()) then return true end
        local member = istable(f.Members) and (GRM.Identity.FactionMember(f, ply) or f.Members[ck] or f.Members[ply:SteamID()] or f.Members[ply:SteamID64()]) or nil
        if istable(member) then
            local leaderRole = f.LeaderRoleName or "Лидер"
            if member.Role == leaderRole or member.Role == "Лидер" then return true end
        end
        return false
    end

    net.Receive(NET_GET, function(_, ply)
        if not IsValid(ply) then return end
        if not ply:IsSuperAdmin() then return end
        PERMS.SendTo(ply)
    end)

    net.Receive(NET_SET, function(_, ply)
        if not IsValid(ply) then return end
        local faction = net.ReadString()
        local role = net.ReadString()
        local perm = net.ReadString()
        local val = net.ReadBool()
        --[[ Вид цели дописан в конец пакета, поэтому старые клиенты
             продолжают работать: пустая строка = право звания. ]]
        local kind = net.ReadString() or ""
        if faction == "" or role == "" then return end

        -- Настройки наследования и замещения приходят тем же каналом.
        if kind == "setting" then
            if not ply:IsSuperAdmin() and not isLeaderOfFaction(ply, faction) then
                PERMS.SendTo(ply)
                return
            end
            PERMS.SetPositionSetting(faction, perm, val)
            PERMS.SendTo(ply)
            return
        end

        if perm == "" then return end
        if not PERMS.Permissions[perm] then return end
        --[[ Право менять доступы: суперадмин или лидер этой организации.
             Раньше отказ был молчаливым — человек щёлкал галочку, она
             возвращалась обратно, и выглядело это как баг. Теперь ответ
             честный, а состояние пересинхронизируется. ]]
        if not ply:IsSuperAdmin() and not isLeaderOfFaction(ply, faction) then
            if GRM.Notify then
                GRM.Notify(ply, "Доступами организации управляет её лидер или суперадмин.", 255, 140, 110)
            else
                ply:ChatPrint("[Доступы] Менять их может лидер организации или суперадмин.")
            end
            PERMS.SendTo(ply)
            return
        end
        if kind == "position" then
            if val then PERMS.GrantToPosition(faction, role, perm)
            else PERMS.RevokeFromPosition(faction, role, perm) end
        elseif val then
            PERMS.GrantToRole(faction, role, perm)
        else
            PERMS.RevokeFromRole(faction, role, perm)
        end
        PERMS.SendTo(ply)
    end)

    hook.Add("PlayerInitialSpawn", "GRM_FPerm_SyncOnJoin", function(ply)
        timer.Simple(2, function()
            if IsValid(ply) and ply:IsSuperAdmin() then
                PERMS.SendTo(ply)
            end
        end)
    end)

    print("[GRM] Faction Permissions v2.1.0 loaded (Код 122, сетевая синхронизация)")
else
    -- КЛИЕНТ: локальный кеш, пополняемый сервером.
    PERMS.Data = PERMS.Data or {}

    net.Receive(NET_DATA, function()
        PERMS.Data = net.ReadTable() or {}
        hook.Run("GRM_FPermDataUpdated")
    end)

    -- Запросить актуальные доступы у сервера.
    function PERMS.Request()
        net.Start(NET_GET)
        net.SendToServer()
    end

    -- На клиенте Grant/Revoke отправляют net-сообщение (а не пишут локальный файл).
    local function sendPerm(factionName, target, permission, value, kind)
        net.Start(NET_SET)
            net.WriteString(tostring(factionName or ""))
            net.WriteString(tostring(target or ""))
            net.WriteString(tostring(permission or ""))
            net.WriteBool(value == true)
            net.WriteString(tostring(kind or ""))
        net.SendToServer()
    end

    function PERMS.GrantToRole(factionName, roleName, permission)
        sendPerm(factionName, roleName, permission, true, "role")
    end

    function PERMS.RevokeFromRole(factionName, roleName, permission)
        sendPerm(factionName, roleName, permission, false, "role")
    end

    function PERMS.GrantToPosition(factionName, positionID, permission)
        sendPerm(factionName, positionID, permission, true, "position")
    end

    function PERMS.RevokeFromPosition(factionName, positionID, permission)
        sendPerm(factionName, positionID, permission, false, "position")
    end

    --- Переключатель наследования/замещения (target не используется).
    function PERMS.SetPositionSetting(factionName, key, value)
        sendPerm(factionName, "settings", key, value, "setting")
    end
end
