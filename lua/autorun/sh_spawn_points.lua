-- Boot-шим: старт подсистемы идёт через планировщик GRM.Boot (приоритеты и
-- бюджет на тик). Если планировщик почему-то не загружен, работаем по-старому.
local function grmBootStart(id, tier, fn)
    if GRM and GRM.Boot and GRM.Boot.OnMapStart then return GRM.Boot.OnMapStart(id, tier, fn) end
    return hook.Add("InitPostEntity", id, fn)
end

--[[
    СИСТЕМА ТОЧЕК СПАВНА ДЛЯ ФРАКЦИЙ И ГЛОБАЛЬНЫХ

    - Хранение точек для каждой фракции (отдельно для каждой карты)
    - Глобальные точки (отдельно для каждой карты)
    - Админ-меню для управления (добавление, удаление, телепорт)
    - При спавне игрока выбор случайной точки из списка его фракции или глобальной

    ИСПРАВЛЕНИЯ/ДОРАБОТКИ:
    - pos/ang сохраняются как plain-таблицы {x,y,z} / {p,y,r} — переживают JSON-сериализацию
    - SpawnPoints инициализируется автоматически для любых (в т.ч. новых) фракций
    - После добавления/удаления точки сервер сразу присылает свежие данные клиенту
    - Меню обновляется без закрытия и повторного открытия
    - net.Receive("SpawnAdmin_SendData") зарегистрирован на уровне модуля, а не внутри функции
    - Точки сохраняются отдельно для каждой карты (в имени файла добавляется game.GetMap())
--]]

-- ================================================================
-- ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ (shared)
-- ================================================================

--- Конвертировать Vector или plain-таблицу в {x, y, z}
local function vecToTable(v)
    if type(v) == "table" then
        return {
            x = tonumber(v.x or v[1]) or 0,
            y = tonumber(v.y or v[2]) or 0,
            z = tonumber(v.z or v[3]) or 0,
        }
    elseif isvector and isvector(v) then
        return { x = v.x, y = v.y, z = v.z }
    end
    return { x = 0, y = 0, z = 0 }
end

--- Конвертировать Angle или plain-таблицу в {p, y, r}
local function angToTable(a)
    if type(a) == "table" then
        return {
            p = tonumber(a.p or a[1]) or 0,
            y = tonumber(a.y or a[2]) or 0,
            r = tonumber(a.r or a[3]) or 0,
        }
    elseif isangle and isangle(a) then
        return { p = a.p, y = a.y, r = a.r }
    end
    return { p = 0, y = 0, r = 0 }
end

--- Восстановить Vector из plain-таблицы
local function tableToVec(t)
    if type(t) ~= "table" then return Vector(0, 0, 0) end
    return Vector(
        tonumber(t.x or t[1]) or 0,
        tonumber(t.y or t[2]) or 0,
        tonumber(t.z or t[3]) or 0
    )
end

--- Восстановить Angle из plain-таблицы
local function tableToAng(t)
    if type(t) ~= "table" then return Angle(0, 0, 0) end
    return Angle(
        tonumber(t.p or t[1]) or 0,
        tonumber(t.y or t[2]) or 0,
        tonumber(t.r or t[3]) or 0
    )
end

if SERVER then

    -- ================================================================
    -- СЕРВЕРНАЯ ЧАСТЬ
    -- ================================================================

    -- Функции получения имён файлов с учётом карты
    local function getGlobalSpawnFile()
        return "spawn_points_global_" .. game.GetMap() .. ".json"
    end

    local function getFactionSpawnFile()
        return "spawn_points_factions_" .. game.GetMap() .. ".json"
    end

    -- Структура точек спавна (ЕДИНЫЙ формат хранения, находка 157):
    -- data.factions = {
    --   [factionName] = {
    --     points = {...},           -- точки фракции (общие)
    --     roles = {
    --       [roleName] = {...},     -- точки конкретной роли
    --     },
    --     departments = {
    --       [deptName] = {...},     -- точки конкретного отдела
    --     }
    --   }
    -- }
    -- Раньше формат был НЕПОСЛЕДОВАТЕЛЬНЫМ: AddSpawnPointForFaction писал
    -- голый массив точек, а role/dept-функции — объект {points,roles,departments}.
    -- Загрузчик при этом присваивал полученное в f.SpawnPoints и НЕ восстанавливал
    -- RoleSpawnPoints/DepartmentSpawnPoints — после рестарта все роли/отделы и
    -- половина точек «пропадали» (класс потери конфигурации).

    -- Чтение JSON только с ignoreConversions=true (находка 65)
    local function jsonT(txt)
        local ok, t = pcall(util.JSONToTable, txt, false, true)
        return (ok and istable(t)) and t or nil
    end

    -- Запись JSON с pcall + read-back (правило проекта: file.Write ничего не
    -- возвращает, контроль — только чтением обратно)
    local function saveJson(path, tbl)
        local ok, raw = pcall(util.TableToJSON, tbl, true)
        if not ok or not isstring(raw) or raw == "" then
            print("[SpawnPoints] ОШИБКА сериализации: " .. path .. " — " .. tostring(raw))
            return false
        end
        file.Write(path, raw)
        local back = file.Exists(path, "DATA") and file.Read(path, "DATA") or ""
        if back ~= raw then
            print("[SpawnPoints] read-back не совпал: " .. path)
            return false
        end
        return true
    end

    --[[ ОСИ ИЕРАРХИИ ФРАКЦИИ — одна таблица вместо четырёх копий механики.

         Раньше каждая ось (роль / должность / отдел / подотдел) была
         размазана по ШЕСТИ местам: своя таблица в ensure, своё поле в
         bundle, своя строка в загрузчике, свои Add/Remove/Get и своя
         ветка в ClearSpawnPoints. Цена такой схемы уже оплачена дважды:
           * находка 157 — загрузчик восстанавливал не все оси, после
             рестарта половина точек «пропадала»;
           * ось v5 «должность» — добавили в Add/Remove/Get, но забыли
             ветку в ClearSpawnPoints: очистить точки должности из меню
             было нельзя.
         Обе ошибки одного класса: «добавил ось — забыл одно из мест».

         Теперь ось описывается ОДНОЙ строкой, механика общая:
           id     — ключ раздела в командах и в ClearSpawnPoints;
           field  — где точки лежат в таблице фракции;
           bundle — имя оси в JSON (единый формат, находка 157);
           member — поле карточки участника, по которому ищется его точка;
           label  — как ось зовётся в сообщениях админу;
           valid  — существует ли такой узел во фракции (nil = не проверяем);
           norm   — приведение ключа (у должностей ключ числовой в UI).
         Порядок строк = порядок приоритета при выборе точки спавна:
         должность точнее подотдела, подотдел — роли, роль — отдела.
    ]]
    local SPAWN_AXES = {
        { id = "position", field = "PositionSpawnPoints",   bundle = "positions",
          member = "Position",      label = "Должность", norm = tostring },
        { id = "sub",      field = "SubdeptSpawnPoints",    bundle = "subdepartments",
          member = "Subdepartment", label = "Подотдел" },
        { id = "role",     field = "RoleSpawnPoints",       bundle = "roles",
          member = "Role",          label = "Роль" },
        { id = "dept",     field = "DepartmentSpawnPoints", bundle = "departments",
          member = "Department",    label = "Отдел" },
    }

    local AXIS = {}
    for _, axis in ipairs(SPAWN_AXES) do AXIS[axis.id] = axis end

    --- Убедиться, что у фракции есть таблицы точек (общие + все оси)
    local function ensureFactionSpawnPoints(f)
        if not istable(f.SpawnPoints) then f.SpawnPoints = {} end
        for _, axis in ipairs(SPAWN_AXES) do
            if not istable(f[axis.field]) then f[axis.field] = {} end
        end
    end

    -- Полный bundle фракции: общие точки + все оси (единый формат)
    local function factionBundle(f)
        ensureFactionSpawnPoints(f)
        local bundle = { points = f.SpawnPoints or {} }
        for _, axis in ipairs(SPAWN_AXES) do
            bundle[axis.bundle] = f[axis.field] or {}
        end
        return bundle
    end

    -- Сохранить ВСЕ фракционные точки единым форматом
    local function saveAllFactionSpawnPoints()
        local allData = {}
        if Factions then
            for name, f in pairs(Factions) do
                allData[name] = factionBundle(f)
            end
        end
        saveJson(getFactionSpawnFile(), allData)
    end

    -- ----------------------------------------------------------------
    -- 1. Глобальные точки (загрузка/сохранение для текущей карты)
    -- ----------------------------------------------------------------

    local function loadGlobalSpawnPoints()
        local filePath = getGlobalSpawnFile()
        if not file.Exists(filePath, "DATA") then return {} end
        return jsonT(file.Read(filePath, "DATA")) or {}
    end

    local function saveGlobalSpawnPoints(tbl)
        saveJson(getGlobalSpawnFile(), tbl)
    end

    GlobalSpawnPoints = GlobalSpawnPoints or {}

    -- ----------------------------------------------------------------
    -- 2. Точки фракций (загрузка/сохранение для текущей карты)
    -- ----------------------------------------------------------------

    local function loadFactionSpawnPoints()
        local filePath = getFactionSpawnFile()
        if not file.Exists(filePath, "DATA") then return {} end
        return jsonT(file.Read(filePath, "DATA")) or {}
    end

    local function saveFactionSpawnPoints(tbl)
        saveJson(getFactionSpawnFile(), tbl)
    end

    -- ----------------------------------------------------------------
    -- 3. Перезагрузка всех точек для текущей карты
    -- ----------------------------------------------------------------

    local function reloadSpawnPoints()
        -- Загружаем глобальные
        GlobalSpawnPoints = loadGlobalSpawnPoints()
        if not istable(GlobalSpawnPoints) then GlobalSpawnPoints = {} end

        -- Загружаем фракционные (единый формат) и применяем к фракциям
        local loadedData = loadFactionSpawnPoints()
        local needResave = false
        if Factions then
            for factionName, f in pairs(Factions) do
                ensureFactionSpawnPoints(f)
                local entry = loadedData[factionName]
                if istable(entry) then
                    -- МИГРАЦИЯ старого формата: entry — голый массив точек
                    -- (так писал AddSpawnPointForFaction до находки 157).
                    local legacy = entry.points == nil and entry.roles == nil and entry.departments == nil
                    f.SpawnPoints = legacy and entry or (istable(entry.points) and entry.points or {})
                    for _, axis in ipairs(SPAWN_AXES) do
                        local stored = not legacy and entry[axis.bundle] or nil
                        f[axis.field] = istable(stored) and stored or {}
                    end
                    if legacy then needResave = true end
                else
                    f.SpawnPoints = {}
                    for _, axis in ipairs(SPAWN_AXES) do f[axis.field] = {} end
                end
            end
        end
        -- Одноразовая миграция легаси-файла в единый формат
        if needResave then saveAllFactionSpawnPoints() end
    end

    -- ----------------------------------------------------------------
    -- 4. Инициализация при старте и при смене карты
    -- ----------------------------------------------------------------

    -- Вызываем при загрузке модуля
    reloadSpawnPoints()

    -- При смене карты перезагружаем точки (после полной инициализации карты и фракций)
    grmBootStart("SpawnPoints_ReloadOnMap", "early", function()
        -- Если Factions ещё не определена, ждём короткое время
        if not Factions then
            timer.Simple(0.1, function()
                if Factions then
                    reloadSpawnPoints()
                end
            end)
        else
            reloadSpawnPoints()
        end
    end)

    hook.Add("PostCleanupMap", "SpawnPoints_ReloadCleanup", function()
        timer.Simple(0.5, function()
            reloadSpawnPoints()
        end)
    end)

    -- При создании новой фракции инициализируем пустые точки
    hook.Add("FactionCreated", "SpawnPoints_InitNew", function(factionName)
        if Factions and Factions[factionName] then
            ensureFactionSpawnPoints(Factions[factionName])
        end
    end)

    -- ----------------------------------------------------------------
    -- 5. Функции работы с точками (используют загруженные данные)
    -- ----------------------------------------------------------------

    --- Собрать данные для отправки клиенту.
    --  Кроме самих точек шлём СТРУКТУРУ организации из factions.json:
    --  должности, отделы и подотделы с публичными названиями, тегами и
    --  привязкой подотдела к родительскому отделу — меню строит дерево
    --  «организация → отдел → подотдел → должность» без ручного ввода.
    local function buildSpawnData()
        local data = { factions = {}, global = GlobalSpawnPoints, map = game.GetMap() }
        if Factions then
            for name, f in pairs(Factions) do
                ensureFactionSpawnPoints(f)
                local roles, roleNames = {}, {}
                if istable(f.Roles) then
                    for _, r in ipairs(f.Roles) do
                        if r ~= f.LeaderRoleName then
                            roles[#roles + 1] = tostring(r)
                            local disp = istable(f.RoleDisplayNames) and f.RoleDisplayNames[r] or nil
                            roleNames[tostring(r)] = tostring((disp ~= nil and disp ~= "") and disp or r)
                        end
                    end
                end
                local depts, deptNames, deptTags = {}, {}, {}
                if istable(f.Departments) then
                    for _, d in ipairs(f.Departments) do
                        depts[#depts + 1] = tostring(d)
                        local disp = istable(f.DepartmentDisplayNames) and f.DepartmentDisplayNames[d] or nil
                        deptNames[tostring(d)] = tostring((disp ~= nil and disp ~= "") and disp or d)
                        local tag = istable(f.DepartmentTags) and f.DepartmentTags[d] or nil
                        deptTags[tostring(d)] = tostring(tag or "")
                    end
                end
                -- Подотделы: массив, чтобы порядок был предсказуемым, с родителем
                local subs = {}
                if istable(f.Subdepartments) then
                    for subKey, sub in pairs(f.Subdepartments) do
                        if istable(sub) then
                            subs[#subs + 1] = {
                                id = tostring(subKey),
                                name = tostring((sub.name ~= nil and sub.name ~= "") and sub.name or subKey),
                                parent = tostring(sub.parentDept or ""),
                                tag = tostring(sub.tag or ""),
                                quota = tonumber(sub.quota) or 0,
                            }
                        end
                    end
                    table.sort(subs, function(a, b)
                        if a.parent ~= b.parent then return a.parent < b.parent end
                        return a.name < b.name
                    end)
                end

                -- Должности (ось v5) в снимок дерева точек спавна.
                local posList = {}
                if GRM.Positions and GRM.Positions.List then
                    for _, pos in ipairs(GRM.Positions.List(f)) do
                        posList[#posList + 1] = {
                            id = pos.id, name = pos.name, node = pos.node,
                            kindName = (GRM.Positions.KindName or {})[pos.kind] or pos.kind,
                            nodeName = GRM.Positions.NodeDisplayName(f, pos.node),
                        }
                    end
                end

                data.factions[name] = {
                    points = f.SpawnPoints or {},
                    roles = f.RoleSpawnPoints or {},
                    departments = f.DepartmentSpawnPoints or {},
                    subdepartments = f.SubdeptSpawnPoints or {},
                    positions = f.PositionSpawnPoints or {},
                    posList = posList,
                    rolesList = roles,
                    roleNames = roleNames,
                    departmentsList = depts,
                    deptNames = deptNames,
                    deptTags = deptTags,
                    subList = subs,
                    displayName = tostring(f.DisplayName or name),
                    tag = tostring(f.Tag or ""),
                    leaderRole = tostring(f.LeaderRoleName or ""),
                    leader = tostring(f.Leader or "—"),
                    memberCount = istable(f.Members) and table.Count(f.Members) or 0,
                }
            end
        end
        return data
    end

    -- Глобальные
    function AddGlobalSpawnPoint(pos, ang)
        table.insert(GlobalSpawnPoints, { pos = vecToTable(pos), ang = angToTable(ang) })
        saveGlobalSpawnPoints(GlobalSpawnPoints)
        return true
    end

    function RemoveGlobalSpawnPoint(index)
        if not GlobalSpawnPoints or index < 1 or index > #GlobalSpawnPoints then
            return false, "Неверный индекс"
        end
        table.remove(GlobalSpawnPoints, index)
        saveGlobalSpawnPoints(GlobalSpawnPoints)
        return true
    end

    function GetGlobalSpawnPoints()
        return GlobalSpawnPoints
    end

    -- Фракционные
    function AddSpawnPointForFaction(factionName, pos, ang)
        if not Factions or not Factions[factionName] then
            return false, "Фракция не найдена"
        end

        ensureFactionSpawnPoints(Factions[factionName])
        table.insert(Factions[factionName].SpawnPoints, { pos = vecToTable(pos), ang = angToTable(ang) })

        -- Сохраняем ВСЕ точки всех фракций единым форматом (points+roles+departments)
        saveAllFactionSpawnPoints()
        return true
    end

    function RemoveSpawnPointFromFaction(factionName, index)
        if not Factions or not Factions[factionName] then
            return false, "Фракция не найдена"
        end

        ensureFactionSpawnPoints(Factions[factionName])
        local pts = Factions[factionName].SpawnPoints
        if index < 1 or index > #pts then return false, "Неверный индекс" end
        table.remove(pts, index)

        saveAllFactionSpawnPoints()
        return true
    end

    function GetSpawnPointsForFaction(factionName)
        if not Factions or not Factions[factionName] then return {} end
        ensureFactionSpawnPoints(Factions[factionName])
        return Factions[factionName].SpawnPoints
    end

    --[[ ВАЛИДАТОРЫ УЗЛОВ — по одному на ось, всё остальное общее.
         Роль/отдел: если список у фракции пуст, разрешаем (легаси-точки
         старых сборок иначе стали бы неудаляемыми). Подотдел/должность —
         строго по реестру: их ключи генерируются, «свободного» имени быть
         не может. ]]
    local function isValidRole(f, roleName)
        if not istable(f.Roles) or #f.Roles == 0 then return true end
        if roleName == f.LeaderRoleName then return true end
        for _, r in ipairs(f.Roles) do
            if tostring(r) == tostring(roleName) then return true end
        end
        return false
    end

    local function isValidDepartment(f, deptName)
        if not istable(f.Departments) or #f.Departments == 0 then return true end
        for _, d in ipairs(f.Departments) do
            if tostring(d) == tostring(deptName) then return true end
        end
        return false
    end

    local function isValidSubdept(f, subKey)
        if not istable(f.Subdepartments) then return false end
        return istable(f.Subdepartments[subKey])
    end

    local function isValidPosition(f, positionID)
        return GRM.Positions ~= nil and isfunction(GRM.Positions.Get)
            and GRM.Positions.Get(f, positionID) ~= nil
    end

    AXIS.role.valid = isValidRole
    AXIS.dept.valid = isValidDepartment
    AXIS.sub.valid = isValidSubdept
    AXIS.position.valid = isValidPosition

    --[[ ОБЩАЯ МЕХАНИКА ТОЧЕК ОСИ.
         Три функции на все четыре оси: раньше это были двенадцать почти
         одинаковых тел, различавшихся именем поля и текстом ошибки. ]]
    local function axisFaction(factionName)
        if not Factions or not Factions[factionName] then return nil end
        return Factions[factionName]
    end

    local function axisKey(axis, key)
        return axis.norm and axis.norm(key or "") or key
    end

    local function axisAdd(axis, factionName, key, pos, ang)
        local f = axisFaction(factionName)
        if not f then return false, "Фракция не найдена" end
        key = axisKey(axis, key)
        if axis.valid and not axis.valid(f, key) then
            return false, axis.label .. " «" .. tostring(key) .. "» не существует во фракции «"
                .. factionName .. "»"
        end
        ensureFactionSpawnPoints(f)
        local points = f[axis.field]
        if not points[key] then points[key] = {} end
        table.insert(points[key], { pos = vecToTable(pos), ang = angToTable(ang) })
        saveAllFactionSpawnPoints()
        return true
    end

    local function axisRemove(axis, factionName, key, index)
        local f = axisFaction(factionName)
        if not f then return false end
        key = axisKey(axis, key)
        local points = f[axis.field]
        if not istable(points) or not points[key] then return false end
        table.remove(points[key], index)
        -- Пустой узел удаляем целиком: иначе в JSON копятся пустые ключи,
        -- а меню показывает разделы без единой точки.
        if #points[key] == 0 then points[key] = nil end
        saveAllFactionSpawnPoints()
        return true
    end

    local function axisPoints(axis, factionName, key)
        local f = axisFaction(factionName)
        if not f then return {} end
        key = axisKey(axis, key)
        local points = f[axis.field]
        if not istable(points) or not istable(points[key]) then return {} end
        return points[key]
    end

    --[[ Публичные имена — часть контракта (их зовут админ-меню и чат-команды),
         поэтому остаются как были; тела сведены к одной строке. ]]
    function AddSpawnPointForRole(factionName, roleName, pos, ang)
        return axisAdd(AXIS.role, factionName, roleName, pos, ang)
    end

    function RemoveSpawnPointFromRole(factionName, roleName, index)
        return axisRemove(AXIS.role, factionName, roleName, index)
    end

    function GetSpawnPointsForRole(factionName, roleName)
        return axisPoints(AXIS.role, factionName, roleName)
    end

    function AddSpawnPointForDepartment(factionName, deptName, pos, ang)
        return axisAdd(AXIS.dept, factionName, deptName, pos, ang)
    end

    function RemoveSpawnPointFromDepartment(factionName, deptName, index)
        return axisRemove(AXIS.dept, factionName, deptName, index)
    end

    function GetSpawnPointsForDepartment(factionName, deptName)
        return axisPoints(AXIS.dept, factionName, deptName)
    end

    function AddSpawnPointForSubdept(factionName, subKey, pos, ang)
        return axisAdd(AXIS.sub, factionName, subKey, pos, ang)
    end

    function RemoveSpawnPointFromSubdept(factionName, subKey, index)
        return axisRemove(AXIS.sub, factionName, subKey, index)
    end

    function GetSpawnPointsForSubdept(factionName, subKey)
        return axisPoints(AXIS.sub, factionName, subKey)
    end

    function AddSpawnPointForPosition(factionName, positionID, pos, ang)
        return axisAdd(AXIS.position, factionName, positionID, pos, ang)
    end

    function RemoveSpawnPointFromPosition(factionName, positionID, index)
        return axisRemove(AXIS.position, factionName, positionID, index)
    end

    function GetSpawnPointsForPosition(factionName, positionID)
        return axisPoints(AXIS.position, factionName, positionID)
    end

    --[[ Узел удалили — его точки больше некому использовать. Один хук на
         все оси: раньше уборка была написана только для должностей, и
         удалённый отдел оставлял за собой мёртвые точки в JSON. ]]
    hook.Add("GRM_FactionPositionChanged", "GRM_SpawnPoints_PositionGone",
        function(factionName, positionID, _, kind)
            if kind ~= "delete" then return end
            local f = Factions and Factions[factionName]
            if not istable(f) then return end
            local points = f[AXIS.position.field]
            local key = axisKey(AXIS.position, positionID)
            if not (istable(points) and points[key]) then return end
            points[key] = nil
            saveAllFactionSpawnPoints()
        end)

    -- === ОЧИСТКА ВСЕХ ТОЧЕК УЗЛА (организация / отдел / подотдел / должность) ===
    function ClearSpawnPoints(scope, factionName, key)
        if scope == "global" then
            GlobalSpawnPoints = {}
            saveGlobalSpawnPoints(GlobalSpawnPoints)
            return true
        end
        local f = Factions and Factions[factionName]
        if not f then return false, "Фракция не найдена" end
        ensureFactionSpawnPoints(f)
        if scope == "faction" then
            f.SpawnPoints = {}
        else
            -- Раздел ищем в реестре осей: раньше здесь была лестница
            -- if/elseif, и ось «должность» в неё просто не попала —
            -- её точки нельзя было очистить из меню.
            local axis = AXIS[scope]
            if not axis then return false, "Неизвестный раздел" end
            f[axis.field][axisKey(axis, key)] = nil
        end
        saveAllFactionSpawnPoints()
        return true
    end

    -- ----------------------------------------------------------------
    -- 6. Основная логика спавна
    -- ----------------------------------------------------------------

    function GetSpawnPointForPlayer(ply)
        if not IsValid(ply) then return nil end
        local factionName = nil
        local memberData = nil

        if Factions then
            local steamID = ply:SteamID()
            for name, f in pairs(Factions) do
                local member
                if GRM.Identity and GRM.Identity.FactionMember then
                    member = GRM.Identity.FactionMember(f, ply)
                elseif f.Members then
                    member = f.Members[steamID] or f.Members[ply:SteamID64()]
                end
                if member then
                    factionName = name
                    memberData = member
                    break
                end
            end
        end

        if not factionName then
            -- Нет фракции → глобальные точки
            local globalPoints = GetGlobalSpawnPoints()
            if #globalPoints > 0 then
                local point = globalPoints[math.random(1, #globalPoints)]
                return tableToVec(point.pos), tableToAng(point.ang)
            end
            return nil
        end

        --[[ ВЫБОР ТОЧКИ — от самой узкой оси к самой широкой.
             Порядок задан таблицей SPAWN_AXES (должность → подотдел →
             роль → отдел), а не четырьмя одинаковыми блоками подряд:
             раньше добавление оси требовало вставить сюда пятый блок,
             и «должность» какое-то время спавнила по подотделу. ]]
        if memberData then
            for _, axis in ipairs(SPAWN_AXES) do
                local nodeKey = tostring(memberData[axis.member] or "")
                if nodeKey ~= "" then
                    local points = axisPoints(axis, factionName, nodeKey)
                    if #points > 0 then
                        local point = points[math.random(1, #points)]
                        return tableToVec(point.pos), tableToAng(point.ang)
                    end
                end
            end
        end

        -- Точки организации, затем глобальные — общий фолбэк.
        local factionPoints = GetSpawnPointsForFaction(factionName)
        if #factionPoints > 0 then
            local point = factionPoints[math.random(1, #factionPoints)]
            return tableToVec(point.pos), tableToAng(point.ang)
        end

        local globalFallback = GetGlobalSpawnPoints()
        if #globalFallback > 0 then
            local point = globalFallback[math.random(1, #globalFallback)]
            return tableToVec(point.pos), tableToAng(point.ang)
        end

        return nil
    end

    function GRM_MovePlayerToSpawnPoint(ply)
        if not IsValid(ply) then return false end
        local pos, ang = GetSpawnPointForPlayer(ply)
        if not pos then return false end
        ply:SetPos(pos)
        if ang then
            ply:SetAngles(ang)
            if ply.SetEyeAngles then ply:SetEyeAngles(ang) end
        end
        return true, pos, ang
    end

    --[[ БАГ (жалоба владельца 27.08): «почему когда персонаж не выбран,
         он уже стоит на карте?». Виноват был именно этот хук: он ставил
         на фракционную точку ЛЮБОГО заспавнившегося игрока, в том числе
         сидящего в лимбе до выбора персонажа. Модуль персонажей уносил
         его за карту, а мы тут же возвращали обратно.
         Теперь пока персонаж не подтверждён — не трогаем игрока вообще,
         его позицией управляет только лимб. ]]
    hook.Add("PlayerSpawn", "SpawnAtFactionPoint", function(ply)
        if IsValid(ply) and GRM.Char and GRM.Char.IsPending and GRM.Char.IsPending(ply) then return end
        --[[ Во время входа позицией распоряжается ТОЛЬКО конвейер
             (GRM.Entry): игрок мог выбрать «дом» или «где вышел», и
             фракционная точка обязана уступить. Раньше этот хук
             срабатывал последним и возвращал человека в штаб — отсюда
             жалоба «нажми любую кнопку, ничего не происходит». ]]
        if GRM.Entry and GRM.Entry.InProgress and GRM.Entry.InProgress(ply) then return end
        if IsValid(ply) and ply.GRMEntryPoint ~= nil then return end
        GRM_MovePlayerToSpawnPoint(ply)
    end)

    -- ----------------------------------------------------------------
    -- 7. NET-обработчики для админ-меню
    -- ----------------------------------------------------------------

    util.AddNetworkString("SpawnAdmin_OpenMenu")
    util.AddNetworkString("SpawnAdmin_SendData")
    util.AddNetworkString("SpawnAdmin_AddPoint")
    util.AddNetworkString("SpawnAdmin_RemovePoint")
    util.AddNetworkString("SpawnAdmin_TeleportToPoint")
    util.AddNetworkString("SpawnAdmin_AddRolePoint")
    util.AddNetworkString("SpawnAdmin_RemoveRolePoint")
    util.AddNetworkString("SpawnAdmin_AddDeptPoint")
    util.AddNetworkString("SpawnAdmin_RemoveDeptPoint")
    util.AddNetworkString("SpawnAdmin_AddSubPoint")
    util.AddNetworkString("SpawnAdmin_RemoveSubPoint")
    util.AddNetworkString("SpawnAdmin_ClearPoints")

    local function sendSpawnDataToPlayer(ply)
        net.Start("SpawnAdmin_SendData")
        net.WriteTable(buildSpawnData())
        net.Send(ply)
    end

    net.Receive("SpawnAdmin_OpenMenu", function(_, ply)
        if not ply:IsSuperAdmin() then return end
        sendSpawnDataToPlayer(ply)
    end)

    net.Receive("SpawnAdmin_AddPoint", function(_, ply)
        if not ply:IsSuperAdmin() then return end

        local faction = net.ReadString()
        local pos     = net.ReadVector()
        local ang     = net.ReadAngle()

        local ok, err
        if faction == "__global" then
            ok, err = AddGlobalSpawnPoint(pos, ang)
        else
            ok, err = AddSpawnPointForFaction(faction, pos, ang)
        end

        if ok then
            sendSpawnDataToPlayer(ply)
        else
            ply:PrintMessage(HUD_PRINTTALK, "[SpawnPoints] Ошибка: " .. tostring(err))
            sendSpawnDataToPlayer(ply)
        end
    end)

    net.Receive("SpawnAdmin_RemovePoint", function(_, ply)
        if not ply:IsSuperAdmin() then return end

        local faction = net.ReadString()
        local index   = net.ReadInt(32)

        local ok, err
        if faction == "__global" then
            ok, err = RemoveGlobalSpawnPoint(index)
        else
            ok, err = RemoveSpawnPointFromFaction(faction, index)
        end

        if not ok then
            ply:PrintMessage(HUD_PRINTTALK, "[SpawnPoints] Ошибка: " .. tostring(err))
        end

        sendSpawnDataToPlayer(ply)
    end)

    net.Receive("SpawnAdmin_TeleportToPoint", function(_, ply)
        if not ply:IsSuperAdmin() then return end

        local pos = net.ReadVector()
        local ang = net.ReadAngle()

        ply:SetPos(pos)
        ply:SetAngles(ang)
    end)

    -- === ТОЧКИ ДЛЯ РОЛЕЙ ===
    net.Receive("SpawnAdmin_AddRolePoint", function(_, ply)
        if not ply:IsSuperAdmin() then return end
        local factionName = net.ReadString()
        local roleName = net.ReadString()
        local pos = net.ReadVector()
        local ang = net.ReadAngle()
        local ok, err = AddSpawnPointForRole(factionName, roleName, pos, ang)
        if not ok and err then
            ply:PrintMessage(HUD_PRINTTALK, "[SpawnPoints] " .. tostring(err))
        end
        sendSpawnDataToPlayer(ply)
    end)

    net.Receive("SpawnAdmin_RemoveRolePoint", function(_, ply)
        if not ply:IsSuperAdmin() then return end
        local factionName = net.ReadString()
        local roleName = net.ReadString()
        local index = net.ReadInt(32)
        RemoveSpawnPointFromRole(factionName, roleName, index)
        sendSpawnDataToPlayer(ply)
    end)

    -- === ТОЧКИ ДЛЯ ОТДЕЛОВ ===
    net.Receive("SpawnAdmin_AddDeptPoint", function(_, ply)
        if not ply:IsSuperAdmin() then return end
        local factionName = net.ReadString()
        local deptName = net.ReadString()
        local pos = net.ReadVector()
        local ang = net.ReadAngle()
        local ok, err = AddSpawnPointForDepartment(factionName, deptName, pos, ang)
        if not ok and err then
            ply:PrintMessage(HUD_PRINTTALK, "[SpawnPoints] " .. tostring(err))
        end
        sendSpawnDataToPlayer(ply)
    end)

    net.Receive("SpawnAdmin_RemoveDeptPoint", function(_, ply)
        if not ply:IsSuperAdmin() then return end
        local factionName = net.ReadString()
        local deptName = net.ReadString()
        local index = net.ReadInt(32)
        RemoveSpawnPointFromDepartment(factionName, deptName, index)
        sendSpawnDataToPlayer(ply)
    end)

    -- === ТОЧКИ ДЛЯ ПОДОТДЕЛОВ ===
    net.Receive("SpawnAdmin_AddSubPoint", function(_, ply)
        if not ply:IsSuperAdmin() then return end
        local factionName = net.ReadString()
        local subKey = net.ReadString()
        local pos = net.ReadVector()
        local ang = net.ReadAngle()
        local ok, err = AddSpawnPointForSubdept(factionName, subKey, pos, ang)
        if not ok and err then
            ply:PrintMessage(HUD_PRINTTALK, "[SpawnPoints] " .. tostring(err))
        end
        sendSpawnDataToPlayer(ply)
    end)

    net.Receive("SpawnAdmin_RemoveSubPoint", function(_, ply)
        if not ply:IsSuperAdmin() then return end
        local factionName = net.ReadString()
        local subKey = net.ReadString()
        local index = net.ReadInt(32)
        RemoveSpawnPointFromSubdept(factionName, subKey, index)
        sendSpawnDataToPlayer(ply)
    end)

    -- === ОЧИСТКА ВСЕХ ТОЧЕК УЗЛА ===
    net.Receive("SpawnAdmin_ClearPoints", function(_, ply)
        if not ply:IsSuperAdmin() then return end
        local scope = net.ReadString()
        local factionName = net.ReadString()
        local key = net.ReadString()
        local ok, err = ClearSpawnPoints(scope, factionName, key)
        if not ok and err then
            ply:PrintMessage(HUD_PRINTTALK, "[SpawnPoints] " .. tostring(err))
        end
        sendSpawnDataToPlayer(ply)
    end)

    -- Команда чата на стороне сервера: работает и в ванильном чате, и там,
    -- где клиентский PlayerSayTransform не срабатывает.
    hook.Add("PlayerSay", "GRM_SpawnPoints_ChatCmd", function(ply, text)
        local low = string.lower(string.Trim(tostring(text or "")))
        if low ~= "/spawnmenu" and low ~= "/точкиспавна" then return end
        if not ply:IsSuperAdmin() then
            ply:PrintMessage(HUD_PRINTTALK, "[SpawnPoints] Нет прав")
            return ""
        end
        sendSpawnDataToPlayer(ply)
        return ""
    end)

    print("[SpawnPoints] Серверная часть загружена (карта: " .. game.GetMap() .. ")")

end

-- ================================================================
-- ОБЩИЙ СЛОЙ МЕНЮ (shared): дерево «организация → отдел → подотдел →
-- должность» строится ЧИСТОЙ функцией, без vgui. Так его можно гонять в
-- стендах и не держать две копии логики в разных панелях.
-- ================================================================

GRM = GRM or {}
GRM.SpawnPoints = GRM.SpawnPoints or {}
local SP = GRM.SpawnPoints
SP.Version = "2.0.0"

-- Соответствие «вид узла → раздел хранения»
SP.Scopes = {
    global    = "global",
    facpoints = "faction",
    dept      = "dept",
    sub       = "sub",
    role      = "role",
}

local function spCount(t)
    return istable(t) and #t or 0
end

local function spLower(s)
    s = string.lower(tostring(s or ""))
    -- string.lower знает только латиницу: кириллицу приводим вручную,
    -- иначе поиск «медиц» не находит «Медицина» (класс потери регистра).
    if not string.find(s, "\208", 1, true) then return s end
    s = string.gsub(s, "\208([\144-\159])", function(c)
        return "\208" .. string.char(string.byte(c) + 32)
    end)
    s = string.gsub(s, "\208([\160-\175])", function(c)
        return "\209" .. string.char(string.byte(c) - 32)
    end)
    s = string.gsub(s, "\208\129", "\209\145") -- Ё → ё
    return s
end

--[[ Корзины снимка по осям. Имена совпадают с полями bundle, который
     сервер шлёт клиенту (roles/departments/subdepartments/positions). ]]
SP.ScopeBuckets = {
    role = "roles",
    dept = "departments",
    sub = "subdepartments",
    position = "positions",
}

--- Все точки конкретного узла.
--  sel = { scope = "global"|"faction"|"dept"|"sub"|"role", faction = ..., key = ... }
function SP.PointsFor(data, sel)
    if not istable(data) or not istable(sel) then return {} end
    if sel.scope == "global" then return istable(data.global) and data.global or {} end
    local fac = istable(data.factions) and data.factions[sel.faction] or nil
    if not istable(fac) then return {} end
    if sel.scope == "faction" then return istable(fac.points) and fac.points or {} end
    -- Ось → её корзина в снимке. Тот же набор осей, что и на сервере
    -- (SPAWN_AXES): ветка на каждую ось здесь означала бы, что новая ось
    -- появится в игре, но не появится в админ-меню.
    local bucketField = SP.ScopeBuckets[sel.scope]
    local bucket = bucketField and fac[bucketField] or nil
    if not istable(bucket) then return {} end
    local pts = bucket[sel.key]
    return istable(pts) and pts or {}
end

--- Сколько всего точек у организации (общие + должности + отделы + подотделы)
function SP.FactionTotal(fac)
    if not istable(fac) then return 0 end
    local total = spCount(fac.points)
    for _, bucket in ipairs({ fac.roles, fac.departments, fac.subdepartments }) do
        if istable(bucket) then
            for _, pts in pairs(bucket) do total = total + spCount(pts) end
        end
    end
    return total
end

--- Всего точек на карте
function SP.GrandTotal(data)
    if not istable(data) then return 0 end
    local total = spCount(data.global)
    if istable(data.factions) then
        for _, fac in pairs(data.factions) do total = total + SP.FactionTotal(fac) end
    end
    return total
end

--- Построить плоский список строк дерева.
--  expanded — таблица раскрытых узлов (ключи "fac:ИМЯ" и "dept:ИМЯ/КЛЮЧ").
--  filter — строка поиска; при непустом поиске всё раскрывается автоматически.
--  Возвращает массив строк:
--    { kind, depth, label, note, count, faction, key, scope, expandable, expanded, id }
function SP.BuildTree(data, filter, expanded)
    data = istable(data) and data or {}
    expanded = istable(expanded) and expanded or {}
    filter = spLower(filter)
    local searching = filter ~= ""
    local rows = {}

    local function hit(text)
        if not searching then return true end
        return string.find(spLower(text), filter, 1, true) ~= nil
    end

    rows[#rows + 1] = {
        kind = "global", depth = 0, id = "global",
        label = "Глобальные точки", note = "для тех, кто без организации",
        count = spCount(data.global), scope = "global",
        icon = "icon16/world.png",
    }

    local names = {}
    if istable(data.factions) then
        for name in pairs(data.factions) do names[#names + 1] = name end
    end
    table.sort(names, function(a, b)
        local fa, fb = data.factions[a], data.factions[b]
        local la = istable(fa) and tostring(fa.displayName or a) or a
        local lb = istable(fb) and tostring(fb.displayName or b) or b
        return spLower(la) < spLower(lb)
    end)

    for _, name in ipairs(names) do
        local fac = data.factions[name]
        if not istable(fac) then fac = { points = fac } end

        local facLabel = tostring(fac.displayName or name)
        local deptList = istable(fac.departmentsList) and fac.departmentsList or {}
        local deptNames = istable(fac.deptNames) and fac.deptNames or {}
        local roleList = istable(fac.rolesList) and fac.rolesList or {}
        local roleNames = istable(fac.roleNames) and fac.roleNames or {}
        local subList = istable(fac.subList) and fac.subList or {}

        -- Легаси-узлы: точки есть, а в структуре организации записи уже нет.
        -- Прятать их нельзя — иначе точку не удалить. Помечаем «вне структуры».
        local knownDept, knownRole, knownSub = {}, {}, {}
        for _, d in ipairs(deptList) do knownDept[tostring(d)] = true end
        for _, r in ipairs(roleList) do knownRole[tostring(r)] = true end
        for _, s in ipairs(subList) do if istable(s) then knownSub[tostring(s.id)] = true end end

        local orphanDepts, orphanRoles, orphanSubs = {}, {}, {}
        if istable(fac.departments) then
            for key in pairs(fac.departments) do
                if not knownDept[tostring(key)] then orphanDepts[#orphanDepts + 1] = tostring(key) end
            end
        end
        if istable(fac.roles) then
            for key in pairs(fac.roles) do
                if not knownRole[tostring(key)] then orphanRoles[#orphanRoles + 1] = tostring(key) end
            end
        end
        if istable(fac.subdepartments) then
            for key in pairs(fac.subdepartments) do
                if not knownSub[tostring(key)] then orphanSubs[#orphanSubs + 1] = tostring(key) end
            end
        end
        table.sort(orphanDepts) table.sort(orphanRoles) table.sort(orphanSubs)

        -- Кого показывать при поиске
        local facHit = hit(facLabel) or hit(name)
        local matchedChildren = false
        local function childHit(text)
            if not searching then return true end
            if facHit then return true end
            local m = hit(text)
            if m then matchedChildren = true end
            return m
        end

        local deptRows = {}
        for _, deptKey in ipairs(deptList) do
            local dLabel = tostring(deptNames[tostring(deptKey)] or deptKey)
            local subsHere = {}
            for _, sub in ipairs(subList) do
                if istable(sub) and tostring(sub.parent) == tostring(deptKey) then
                    if childHit(sub.name) or childHit(sub.id) then
                        subsHere[#subsHere + 1] = sub
                    end
                end
            end
            if childHit(dLabel) or childHit(deptKey) or #subsHere > 0 then
                deptRows[#deptRows + 1] = { key = tostring(deptKey), label = dLabel, subs = subsHere,
                    tag = tostring((istable(fac.deptTags) and fac.deptTags[tostring(deptKey)]) or "") }
            end
        end
        for _, deptKey in ipairs(orphanDepts) do
            if childHit(deptKey) then
                deptRows[#deptRows + 1] = { key = deptKey, label = deptKey, subs = {}, orphan = true }
            end
        end

        -- Подотделы без живого родителя — отдельной группой, чтобы не потерялись
        local looseSubs = {}
        for _, sub in ipairs(subList) do
            if istable(sub) and not knownDept[tostring(sub.parent)] then
                if childHit(sub.name) or childHit(sub.id) then looseSubs[#looseSubs + 1] = sub end
            end
        end
        for _, subKey in ipairs(orphanSubs) do
            if childHit(subKey) then looseSubs[#looseSubs + 1] = { id = subKey, name = subKey, orphan = true } end
        end

        local roleRows = {}
        for _, roleKey in ipairs(roleList) do
            local rLabel = tostring(roleNames[tostring(roleKey)] or roleKey)
            if childHit(rLabel) or childHit(roleKey) then
                roleRows[#roleRows + 1] = { key = tostring(roleKey), label = rLabel }
            end
        end
        for _, roleKey in ipairs(orphanRoles) do
            if childHit(roleKey) then
                roleRows[#roleRows + 1] = { key = roleKey, label = roleKey, orphan = true }
            end
        end

        local show = (not searching) or facHit or matchedChildren
        if show then
            local facExpanded = searching or expanded["fac:" .. name] == true
            rows[#rows + 1] = {
                kind = "faction", depth = 0, id = "fac:" .. name,
                label = facLabel, note = tostring(fac.tag or ""),
                count = SP.FactionTotal(fac), faction = name,
                expandable = true, expanded = facExpanded,
                icon = "icon16/building.png",
            }

            if facExpanded then
                rows[#rows + 1] = {
                    kind = "facpoints", depth = 1, id = "facpts:" .. name,
                    label = "Точки организации", faction = name, scope = "faction",
                    count = spCount(fac.points), icon = "icon16/flag_blue.png",
                }

                if #deptRows > 0 then
                    rows[#rows + 1] = { kind = "header", depth = 1, id = "hdr_d:" .. name, label = "ОТДЕЛЫ" }
                end
                for _, d in ipairs(deptRows) do
                    local deptId = "dept:" .. name .. "/" .. d.key
                    local deptExpanded = (#d.subs > 0) and (searching or expanded[deptId] == true) or false
                    rows[#rows + 1] = {
                        kind = "dept", depth = 1, id = deptId,
                        label = d.label, note = d.orphan and "вне структуры" or (d.tag ~= "" and d.tag or nil),
                        faction = name, key = d.key, scope = "dept",
                        count = spCount(istable(fac.departments) and fac.departments[d.key] or nil),
                        expandable = #d.subs > 0, expanded = deptExpanded,
                        icon = "icon16/folder.png",
                    }
                    if deptExpanded then
                        for _, sub in ipairs(d.subs) do
                            rows[#rows + 1] = {
                                kind = "sub", depth = 2, id = "sub:" .. name .. "/" .. tostring(sub.id),
                                label = tostring(sub.name or sub.id), note = tostring(sub.tag or ""),
                                faction = name, key = tostring(sub.id), scope = "sub",
                                count = spCount(istable(fac.subdepartments) and fac.subdepartments[tostring(sub.id)] or nil),
                                icon = "icon16/folder_page.png",
                            }
                        end
                    end
                end

                if #looseSubs > 0 then
                    rows[#rows + 1] = { kind = "header", depth = 1, id = "hdr_s:" .. name, label = "ПОДОТДЕЛЫ БЕЗ ОТДЕЛА" }
                    for _, sub in ipairs(looseSubs) do
                        rows[#rows + 1] = {
                            kind = "sub", depth = 1, id = "sub:" .. name .. "/" .. tostring(sub.id),
                            label = tostring(sub.name or sub.id), note = sub.orphan and "вне структуры" or nil,
                            faction = name, key = tostring(sub.id), scope = "sub",
                            count = spCount(istable(fac.subdepartments) and fac.subdepartments[tostring(sub.id)] or nil),
                            icon = "icon16/folder_page.png",
                        }
                    end
                end

                if #roleRows > 0 then
                    rows[#rows + 1] = { kind = "header", depth = 1, id = "hdr_r:" .. name, label = "ДОЛЖНОСТИ" }
                end
                for _, r in ipairs(roleRows) do
                    rows[#rows + 1] = {
                        kind = "role", depth = 1, id = "role:" .. name .. "/" .. r.key,
                        label = r.label, note = r.orphan and "вне структуры" or nil,
                        faction = name, key = r.key, scope = "role",
                        count = spCount(istable(fac.roles) and fac.roles[r.key] or nil),
                        icon = "icon16/user.png",
                    }
                end
            end
        end
    end

    return rows
end

--[[ Подписи узлов для «хлебной крошки». Раньше это была лестница из
     трёх ветвей, где каждая сама доставала свой словарь имён; подотдел
     дополнительно ищет свой отдел, чтобы путь читался целиком. ]]
local function nodeName(names, key)
    return tostring((istable(names) and names[key]) or key)
end

local SCOPE_LABELS = {
    role = function(fac, key)
        local names = istable(fac) and fac.roleNames or nil
        return "Должность «" .. nodeName(names, key) .. "»"
    end,
    dept = function(fac, key)
        local names = istable(fac) and fac.deptNames or nil
        return "Отдел «" .. nodeName(names, key) .. "»"
    end,
    sub = function(fac, key)
        local subLabel, parentLabel = tostring(key), nil
        if istable(fac) and istable(fac.subList) then
            for _, sub in ipairs(fac.subList) do
                if istable(sub) and tostring(sub.id) == tostring(key) then
                    subLabel = tostring(sub.name or sub.id)
                    local dn = istable(fac.deptNames) and fac.deptNames[tostring(sub.parent)] or nil
                    parentLabel = tostring(dn or sub.parent or "")
                    break
                end
            end
        end
        if parentLabel and parentLabel ~= "" then
            return "Отдел «" .. parentLabel .. "»  →  Подотдел «" .. subLabel .. "»"
        end
        return "Подотдел «" .. subLabel .. "»"
    end,
}

--- Человеческая «хлебная крошка» выбранного узла
function SP.SelectionPath(data, sel)
    if not istable(sel) then return "—" end
    if sel.scope == "global" then return "Глобальные точки" end
    local fac = istable(data) and istable(data.factions) and data.factions[sel.faction] or nil
    local facLabel = istable(fac) and tostring(fac.displayName or sel.faction) or tostring(sel.faction or "—")
    if sel.scope == "faction" then return facLabel .. "  →  Точки организации" end
    local label = SCOPE_LABELS[sel.scope]
    if label then return facLabel .. "  →  " .. label(fac, sel.key) end
    return facLabel
end

--- Приоритет, по которому игрок получит точку (для подсказки в меню)
SP.PriorityHint = "Приоритет спавна: подотдел → должность → отдел → организация → глобальные"

if CLIENT then

    -- ----------------------------------------------------------------
    -- Палитра и шрифты — единые с остальным интерфейсом GRM
    -- ----------------------------------------------------------------
    local C = {
        bg        = Color(16, 20, 28, 252),
        sidebar   = Color(12, 15, 22, 255),
        card      = Color(22, 28, 38, 240),
        cardLight = Color(28, 36, 48, 240),
        cardHover = Color(36, 46, 62, 240),
        border    = Color(38, 48, 66, 200),
        accent    = Color(65, 145, 235),
        accentDim = Color(40, 100, 180),
        green     = Color(55, 185, 110),
        gold      = Color(245, 195, 65),
        red       = Color(225, 70, 70),
        text      = Color(240, 244, 250),
        dim       = Color(155, 170, 190),
    }

    surface.CreateFont("GRMSpawn_Title",  { font = "Roboto", size = 21, weight = 800, extended = true })
    surface.CreateFont("GRMSpawn_Sub",    { font = "Roboto", size = 15, weight = 700, extended = true })
    surface.CreateFont("GRMSpawn_Normal", { font = "Roboto", size = 14, weight = 500, extended = true })
    surface.CreateFont("GRMSpawn_Btn",    { font = "Roboto", size = 13, weight = 600, extended = true })
    surface.CreateFont("GRMSpawn_Small",  { font = "Roboto", size = 11, weight = 400, extended = true })
    surface.CreateFont("GRMSpawn_Num",    { font = "Roboto", size = 12, weight = 800, extended = true })

    -- Материалы иконок берём через общий кэш (в кадре ни одного Material())
    local matCache = {}
    local function icon(path)
        if GRM.Perf and GRM.Perf.Material then return GRM.Perf.Material(path) end
        local m = matCache[path]
        if not m then m = Material(path, "smooth") matCache[path] = m end
        return m
    end

    local function drawIcon(path, x, y, size)
        local m = icon(path)
        if not m then return end
        surface.SetDrawColor(255, 255, 255, 235)
        surface.SetMaterial(m)
        surface.DrawTexturedRect(x, y, size or 16, size or 16)
    end

    -- ----------------------------------------------------------------
    -- Состояние меню
    -- ----------------------------------------------------------------
    local menuState = {
        frame    = nil,
        data     = { factions = {}, global = {} },
        expanded = {},
        sel      = { scope = "global" },
        filter   = "",
        rebuild  = nil,
        selectedIndex = nil,
    }

    -- ----------------------------------------------------------------
    -- Координаты
    -- ----------------------------------------------------------------
    local function safeCoord(t, key1, key2)
        if type(t) == "table" then
            return tonumber(t[key1] or t[key2]) or 0
        elseif isvector and isvector(t) or isangle and isangle(t) then
            return tonumber(t[key1]) or 0
        end
        return 0
    end

    local function pointToVec(pos)
        if isvector and isvector(pos) then return pos end
        return Vector(safeCoord(pos, "x", 1), safeCoord(pos, "y", 2), safeCoord(pos, "z", 3))
    end

    local function pointToAng(ang)
        if isangle and isangle(ang) then return ang end
        return Angle(safeCoord(ang, "p", 1), safeCoord(ang, "y", 2), safeCoord(ang, "r", 3))
    end

    local function distanceTo(pos)
        local lp = LocalPlayer()
        if not IsValid(lp) then return nil end
        return lp:GetPos():Distance(pointToVec(pos))
    end

    -- ----------------------------------------------------------------
    -- Элементы в стиле GRM
    -- ----------------------------------------------------------------
    local function gButton(parent, text, base, hover, iconPath, onClick)
        local b = vgui.Create("DButton", parent)
        b:SetText("")
        b.Paint = function(self, w, h)
            local col = self:IsHovered() and hover or base
            if not self:IsEnabled() then col = C.card end
            draw.RoundedBox(6, 0, 0, w, h, col)
            local tx = 12
            if iconPath then
                drawIcon(iconPath, 10, h / 2 - 8, 16)
                tx = 32
            end
            draw.SimpleText(text, "GRMSpawn_Btn", tx, h / 2,
                self:IsEnabled() and C.text or C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        b.DoClick = function(self)
            surface.PlaySound("ui/buttonclick.wav")
            if onClick then onClick(self) end
        end
        return b
    end

    local function gEntry(parent, placeholder)
        local e = vgui.Create("DTextEntry", parent)
        e:SetFont("GRMSpawn_Normal")
        e:SetPlaceholderText(placeholder or "")
        e:SetDrawLanguageID(false)
        e.Paint = function(self, w, h)
            draw.RoundedBox(6, 0, 0, w, h, Color(18, 23, 32, 245))
            surface.SetDrawColor(C.border)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
            drawIcon("icon16/magnifier.png", 8, h / 2 - 8, 16)
            self:DrawTextEntryText(C.text, C.accent, C.text)
        end
        e:SetTextInset(28, 0)
        return e
    end

    -- ----------------------------------------------------------------
    -- Отправка команд на сервер
    -- ----------------------------------------------------------------
    --[[ Каналы админ-команд по осям. Раньше это были две лестницы по
         пять веток (добавить/удалить), различавшиеся ТОЛЬКО именем
         канала и тем, пишется ли ключ узла. Ось с ключом (роль, отдел,
         подотдел) шлёт `faction + key`, ось без ключа (глобальные,
         организация) — только «фракцию»; для глобальных это условное
         имя `__global`, как ждёт сервер. ]]
    local SCOPE_NET = {
        global = { add = "SpawnAdmin_AddPoint", remove = "SpawnAdmin_RemovePoint",
                   faction = "__global" },
        faction = { add = "SpawnAdmin_AddPoint", remove = "SpawnAdmin_RemovePoint" },
        role = { add = "SpawnAdmin_AddRolePoint", remove = "SpawnAdmin_RemoveRolePoint", keyed = true },
        dept = { add = "SpawnAdmin_AddDeptPoint", remove = "SpawnAdmin_RemoveDeptPoint", keyed = true },
        sub = { add = "SpawnAdmin_AddSubPoint", remove = "SpawnAdmin_RemoveSubPoint", keyed = true },
    }

    --- Записать «адрес» узла в пакет: фракция (или __global) и ключ узла.
    local function writeScope(channel, sel)
        net.WriteString(channel.faction or sel.faction)
        if channel.keyed then net.WriteString(sel.key) end
    end

    local function sendAdd(sel, pos, ang)
        local channel = SCOPE_NET[sel.scope]
        if not channel then return end
        net.Start(channel.add)
            writeScope(channel, sel)
            net.WriteVector(pos)
            net.WriteAngle(ang)
        net.SendToServer()
    end

    local function sendRemove(sel, index)
        local channel = SCOPE_NET[sel.scope]
        if not channel then return end
        net.Start(channel.remove)
            writeScope(channel, sel)
            net.WriteInt(index, 32)
        net.SendToServer()
    end

    local function sendClear(sel)
        net.Start("SpawnAdmin_ClearPoints")
        net.WriteString(tostring(sel.scope or ""))
        net.WriteString(tostring(sel.faction or ""))
        net.WriteString(tostring(sel.key or ""))
        net.SendToServer()
    end

    -- ----------------------------------------------------------------
    -- Правая часть: карточки точек выбранного узла
    -- ----------------------------------------------------------------
    local function buildPointList(canvas, sel)
        canvas:Clear()
        local points = SP.PointsFor(menuState.data, sel)

        if #points == 0 then
            local empty = vgui.Create("DPanel", canvas)
            empty:Dock(TOP)
            empty:SetTall(90)
            empty:DockMargin(2, 2, 2, 2)
            empty.Paint = function(_, w, h)
                draw.RoundedBox(8, 0, 0, w, h, C.card)
                drawIcon("icon16/information.png", w / 2 - 8, 20, 16)
                draw.SimpleText("Здесь пока нет точек", "GRMSpawn_Sub", w / 2, 48, C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                draw.SimpleText("Встаньте в нужное место и нажмите «Поставить здесь»", "GRMSpawn_Small",
                    w / 2, 68, C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            return
        end

        for i, point in ipairs(points) do
            local card = vgui.Create("DPanel", canvas)
            card:Dock(TOP)
            card:SetTall(54)
            card:DockMargin(2, 0, 2, 6)
            card.Paint = function(self, w, h)
                local selected = menuState.selectedIndex == i
                local bg = selected and C.accentDim or (self:IsHovered() and C.cardHover or C.card)
                draw.RoundedBox(8, 0, 0, w, h, bg)
                draw.RoundedBox(8, 0, 0, 3, h, selected and C.accent or C.border)

                draw.SimpleText("#" .. i, "GRMSpawn_Num", 14, h / 2, selected and C.text or C.dim,
                    TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

                local px = string.format("%.0f", safeCoord(point.pos, "x", 1))
                local py = string.format("%.0f", safeCoord(point.pos, "y", 2))
                local pz = string.format("%.0f", safeCoord(point.pos, "z", 3))
                draw.SimpleText("X " .. px .. "   Y " .. py .. "   Z " .. pz, "GRMSpawn_Normal",
                    52, 14, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

                local yaw = string.format("%.0f", safeCoord(point.ang, "y", 2))
                local info = "Поворот " .. yaw .. "°"
                local dist = distanceTo(point.pos)
                if dist then info = info .. "   •   до вас " .. string.format("%.0f", dist / 52.5) .. " м" end
                draw.SimpleText(info, "GRMSpawn_Small", 52, 36, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            card.OnMousePressed = function()
                menuState.selectedIndex = i
            end

            local del = gButton(card, "Удалить", C.card, C.red, "icon16/delete.png", function()
                sendRemove(sel, i)
                menuState.selectedIndex = nil
            end)
            del:Dock(RIGHT)
            del:SetWide(104)
            del:DockMargin(6, 10, 10, 10)

            local tp = gButton(card, "Телепорт", C.card, C.accent, "icon16/arrow_right.png", function()
                net.Start("SpawnAdmin_TeleportToPoint")
                net.WriteVector(pointToVec(point.pos))
                net.WriteAngle(pointToAng(point.ang))
                net.SendToServer()
                if IsValid(menuState.frame) then menuState.frame:Close() end
            end)
            tp:Dock(RIGHT)
            tp:SetWide(112)
            tp:DockMargin(6, 10, 0, 10)
        end
    end

    -- ----------------------------------------------------------------
    -- Окно
    -- ----------------------------------------------------------------
    local function buildMenu(data)
        menuState.data = istable(data) and data or { factions = {}, global = {} }
        menuState.data.factions = istable(menuState.data.factions) and menuState.data.factions or {}
        menuState.data.global = istable(menuState.data.global) and menuState.data.global or {}

        if IsValid(menuState.frame) then
            -- окно уже открыто — просто перерисовываем содержимое, выбор сохраняется
            if menuState.rebuild then menuState.rebuild() end
            return
        end

        local w = math.min(math.max(ScrW() * 0.72, 960), 1500)
        local h = math.min(math.max(ScrH() * 0.76, 620), 940)

        local frame = vgui.Create("DFrame")
        frame:SetSize(w, h)
        frame:Center()
        frame:SetTitle("")
        frame:ShowCloseButton(false)
        frame:MakePopup()
        frame:SetDraggable(true)
        menuState.frame = frame
        menuState.selectedIndex = nil

        frame.Paint = function(_, fw, fh)
            draw.RoundedBox(10, 0, 0, fw, fh, C.bg)
            draw.RoundedBoxEx(10, 0, 0, fw, 56, Color(22, 28, 40), true, true, false, false)
            draw.RoundedBox(0, 0, 56, fw, 2, C.accent)
            drawIcon("icon16/map.png", 18, 20, 16)
            draw.SimpleText("Точки спавна", "GRMSpawn_Title", 42, 20, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText("Карта: " .. tostring(menuState.data.map or game.GetMap()) ..
                "  •  /spawnmenu  •  суперадмин", "GRMSpawn_Small", 42, 39, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText("Всего точек: " .. SP.GrandTotal(menuState.data), "GRMSpawn_Sub",
                fw - 58, 28, C.green, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end

        local close = vgui.Create("DButton", frame)
        close:SetText("")
        close:SetSize(30, 30)
        close:SetPos(w - 42, 13)
        close.DoClick = function() frame:Close() end
        close.Paint = function(self, bw, bh)
            draw.RoundedBox(6, 0, 0, bw, bh, self:IsHovered() and C.red or Color(34, 42, 58))
            surface.SetDrawColor(240, 242, 246)
            surface.DrawLine(9, 9, bw - 9, bh - 9)
            surface.DrawLine(9, bh - 9, bw - 9, 9)
        end

        -- ── левая колонка: поиск + дерево ────────────────────────────
        local left = vgui.Create("DPanel", frame)
        left:Dock(LEFT)
        left:SetWide(math.floor(w * 0.33))
        left:DockMargin(10, 66, 5, 10)
        left.Paint = function(_, pw, ph) draw.RoundedBox(10, 0, 0, pw, ph, C.sidebar) end

        local search = gEntry(left, "Поиск: организация, отдел, подотдел, должность")
        search:Dock(TOP)
        search:SetTall(32)
        search:DockMargin(10, 10, 10, 8)

        local tree = vgui.Create("DScrollPanel", left)
        tree:Dock(FILL)
        tree:DockMargin(6, 0, 6, 10)
        local treeBar = tree:GetVBar()
        treeBar:SetWide(6)
        treeBar.Paint = function(_, bw, bh) draw.RoundedBox(3, 0, 0, bw, bh, Color(18, 23, 32)) end
        treeBar.btnUp.Paint = function() end
        treeBar.btnDown.Paint = function() end
        treeBar.btnGrip.Paint = function(_, bw, bh) draw.RoundedBox(3, 0, 0, bw, bh, C.border) end

        -- ── правая колонка ───────────────────────────────────────────
        local right = vgui.Create("DPanel", frame)
        right:Dock(FILL)
        right:DockMargin(5, 66, 10, 10)
        right:SetPaintBackground(false)

        local head = vgui.Create("DPanel", right)
        head:Dock(TOP)
        head:SetTall(62)
        head:DockMargin(0, 0, 0, 8)
        head.Paint = function(_, pw, ph)
            draw.RoundedBox(10, 0, 0, pw, ph, C.card)
            local sel = menuState.sel
            local iconPath = "icon16/world.png"
            if sel.scope == "faction" then iconPath = "icon16/building.png"
            elseif sel.scope == "dept" then iconPath = "icon16/folder.png"
            elseif sel.scope == "sub" then iconPath = "icon16/folder_page.png"
            elseif sel.scope == "role" then iconPath = "icon16/user.png" end
            drawIcon(iconPath, 14, 14, 16)
            draw.SimpleText(SP.SelectionPath(menuState.data, sel), "GRMSpawn_Sub", 38, 20, C.text,
                TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(SP.PriorityHint, "GRMSpawn_Small", 38, 42, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            local n = #SP.PointsFor(menuState.data, sel)
            draw.SimpleText(n .. (n == 1 and " точка" or (n >= 2 and n <= 4 and " точки" or " точек")),
                "GRMSpawn_Sub", pw - 16, ph / 2, n > 0 and C.green or C.gold, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end

        local bar = vgui.Create("DPanel", right)
        bar:Dock(TOP)
        bar:SetTall(46)
        bar:DockMargin(0, 0, 0, 8)
        bar.Paint = function(_, pw, ph) draw.RoundedBox(10, 0, 0, pw, ph, C.card) end

        local list = vgui.Create("DScrollPanel", right)
        list:Dock(FILL)
        local listBar = list:GetVBar()
        listBar:SetWide(6)
        listBar.Paint = function(_, bw, bh) draw.RoundedBox(3, 0, 0, bw, bh, Color(18, 23, 32)) end
        listBar.btnUp.Paint = function() end
        listBar.btnDown.Paint = function() end
        listBar.btnGrip.Paint = function(_, bw, bh) draw.RoundedBox(3, 0, 0, bw, bh, C.border) end

        local hint = vgui.Create("DPanel", right)
        hint:Dock(BOTTOM)
        hint:SetTall(26)
        hint:DockMargin(0, 8, 0, 0)
        hint.Paint = function(_, pw, ph)
            draw.RoundedBox(8, 0, 0, pw, ph, C.card)
            draw.SimpleText("Точка ставится там, где стоите вы (или куда смотрите). Угол берётся из вашего взгляда.",
                "GRMSpawn_Small", 12, ph / 2, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end

        -- Кнопки действий
        local function currentAngles()
            local lp = LocalPlayer()
            if not IsValid(lp) then return Angle(0, 0, 0) end
            local a = lp:EyeAngles()
            return Angle(0, a.y, 0)
        end

        local bHere = gButton(bar, "Поставить здесь", C.accentDim, C.accent, "icon16/add.png", function()
            local lp = LocalPlayer()
            if not IsValid(lp) then return end
            sendAdd(menuState.sel, lp:GetPos(), currentAngles())
        end)
        bHere:Dock(LEFT)
        bHere:SetWide(170)
        bHere:DockMargin(8, 7, 6, 7)

        local bAim = gButton(bar, "Куда смотрю", C.cardLight, C.cardHover, "icon16/bullet_go.png", function()
            local lp = LocalPlayer()
            if not IsValid(lp) then return end
            local tr = lp:GetEyeTrace()
            if not tr or not tr.HitPos then return end
            sendAdd(menuState.sel, tr.HitPos + Vector(0, 0, 6), currentAngles())
        end)
        bAim:Dock(LEFT)
        bAim:SetWide(150)
        bAim:DockMargin(0, 7, 6, 7)

        local bRefresh = gButton(bar, "Обновить", C.cardLight, C.cardHover, "icon16/arrow_refresh.png", function()
            net.Start("SpawnAdmin_OpenMenu")
            net.SendToServer()
        end)
        bRefresh:Dock(LEFT)
        bRefresh:SetWide(130)
        bRefresh:DockMargin(0, 7, 6, 7)

        local bClear = gButton(bar, "Очистить узел", C.cardLight, C.red, "icon16/bin.png", function()
            local sel = menuState.sel
            local n = #SP.PointsFor(menuState.data, sel)
            if n == 0 then
                notification.AddLegacy("Здесь и так пусто", NOTIFY_GENERIC, 2)
                return
            end
            Derma_Query("Удалить все точки узла?\n" .. SP.SelectionPath(menuState.data, sel) .. "\nТочек: " .. n,
                "Точки спавна",
                "Удалить", function() sendClear(sel) menuState.selectedIndex = nil end,
                "Отмена", function() end)
        end)
        bClear:Dock(RIGHT)
        bClear:SetWide(150)
        bClear:DockMargin(0, 7, 8, 7)

        local bExport = gButton(bar, "Экспорт", C.cardLight, C.cardHover, "icon16/page_copy.png", function()
            local pts = SP.PointsFor(menuState.data, menuState.sel)
            SetClipboardText(util.TableToJSON(pts, true))
            notification.AddLegacy("Точки узла скопированы в буфер обмена", NOTIFY_GENERIC, 3)
        end)
        bExport:Dock(RIGHT)
        bExport:SetWide(120)
        bExport:DockMargin(0, 7, 6, 7)

        -- ── строка дерева ────────────────────────────────────────────
        local function makeRow(row)
            local panel = vgui.Create("DButton", tree:GetCanvas())
            panel:Dock(TOP)
            panel:SetText("")
            panel:SetTall(row.kind == "header" and 24 or 34)
            panel:DockMargin(4 + row.depth * 14, 0, 4, 3)

            if row.kind == "header" then
                panel:SetMouseInputEnabled(false)
                panel.Paint = function(_, pw, ph)
                    draw.SimpleText(row.label, "GRMSpawn_Small", 6, ph / 2, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end
                return panel
            end

            panel.Paint = function(self, pw, ph)
                local sel = menuState.sel
                local isSel = row.scope ~= nil and sel.scope == row.scope
                    and tostring(sel.faction or "") == tostring(row.faction or "")
                    and tostring(sel.key or "") == tostring(row.key or "")
                local bg = isSel and C.accentDim or (self:IsHovered() and C.cardHover or C.card)
                draw.RoundedBox(7, 0, 0, pw, ph, bg)
                if isSel then draw.RoundedBox(7, 0, 0, 3, ph, C.accent) end

                local x = 10
                if row.expandable then
                    drawIcon(row.expanded and "icon16/bullet_arrow_down.png" or "icon16/bullet_arrow_right.png",
                        x, ph / 2 - 8, 16)
                    x = x + 18
                end
                if row.icon then
                    drawIcon(row.icon, x, ph / 2 - 8, 16)
                    x = x + 22
                end

                local label = row.label
                local maxW = pw - x - 46
                surface.SetFont("GRMSpawn_Normal")
                while surface.GetTextSize(label) > maxW and #label > 4 do
                    label = string.sub(label, 1, #label - 4) .. "…"
                end
                local ty = row.note and row.note ~= "" and (ph / 2 - 7) or (ph / 2)
                draw.SimpleText(label, "GRMSpawn_Normal", x, ty, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                if row.note and row.note ~= "" then
                    draw.SimpleText(row.note, "GRMSpawn_Small", x, ph / 2 + 8, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end

                local cnt = tonumber(row.count) or 0
                if cnt > 0 then
                    local bw = math.max(22, 12 + string.len(tostring(cnt)) * 8)
                    draw.RoundedBox(9, pw - bw - 8, ph / 2 - 9, bw, 18, isSel and C.accent or Color(40, 52, 70))
                    draw.SimpleText(cnt, "GRMSpawn_Num", pw - bw / 2 - 8, ph / 2, C.text,
                        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
            end

            panel.DoClick = function()
                surface.PlaySound("ui/buttonclickrelease.wav")
                if row.expandable then
                    menuState.expanded[row.id] = not menuState.expanded[row.id]
                end
                if row.scope then
                    menuState.sel = { scope = row.scope, faction = row.faction, key = row.key }
                    menuState.selectedIndex = nil
                end
                if menuState.rebuild then menuState.rebuild() end
            end

            return panel
        end

        -- ── пересборка содержимого ───────────────────────────────────
        menuState.rebuild = function()
            if not IsValid(frame) then return end
            local scroll = tree:GetVBar() and tree:GetVBar():GetScroll() or 0
            tree:Clear()
            local rows = SP.BuildTree(menuState.data, menuState.filter, menuState.expanded)
            for _, row in ipairs(rows) do makeRow(row) end
            tree:InvalidateLayout(true)
            if tree:GetVBar() then tree:GetVBar():SetScroll(scroll) end
            buildPointList(list:GetCanvas(), menuState.sel)
        end

        search.OnChange = function(self)
            menuState.filter = self:GetValue() or ""
            if menuState.rebuild then menuState.rebuild() end
        end

        menuState.rebuild()
        frame.OnClose = function()
            menuState.rebuild = nil
            menuState.frame = nil
        end
    end

    -- ----------------------------------------------------------------
    -- NET: свежие данные от сервера
    -- ----------------------------------------------------------------
    net.Receive("SpawnAdmin_SendData", function()
        local data = net.ReadTable() or {}
        buildMenu(data)
    end)

    local function openSpawnAdminMenu()
        net.Start("SpawnAdmin_OpenMenu")
        net.SendToServer()
    end

    -- ----------------------------------------------------------------
    -- Команда /spawnmenu (PlayerSay + PlayerSayTransform — EasyChat)
    -- ----------------------------------------------------------------
    local function handleCommand(msg)
        if not isstring(msg) then return false end
        local low = string.lower(msg)
        if low:find("^/spawnmenu%s*") ~= 1 and low:find("^/точкиспавна%s*") ~= 1 then return false end
        if LocalPlayer():IsSuperAdmin() then
            openSpawnAdminMenu()
        else
            notification.AddLegacy("Нет прав", NOTIFY_ERROR, 3)
        end
        return true
    end

    hook.Add("PlayerSayTransform", "SpawnAdminCommand", function(ply, datapack)
        if ply ~= LocalPlayer() then return end
        if handleCommand(datapack and datapack[1]) then datapack[1] = "" end
    end)

    concommand.Add("grm_spawnmenu", function()
        if LocalPlayer():IsSuperAdmin() then openSpawnAdminMenu()
        else notification.AddLegacy("Нет прав", NOTIFY_ERROR, 3) end
    end)

    print("[SpawnPoints] Клиентская часть v2.0.0 (дерево организация → отдел → подотдел → должность)")

end


--[[ Модуль представляется общему реестру GRM.Modules: соседи знают, что он
     есть, а шина обновлений сама позовёт его при смене прав, состава,
     должности или персонажа. ]]
if GRM.Modules and GRM.Modules.Register then
    GRM.Modules.Register("spawnpoints", {
        label = "Точки спавна",
        version = (GRM.SpawnPoints and GRM.SpawnPoints.Version) or "1.0.0",
        Depends = { "access" },
        Status = function() return "дерево точек: организация → отдел → подотдел → должность" end,
    })
end
