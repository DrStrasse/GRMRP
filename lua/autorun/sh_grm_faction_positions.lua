--[[--------------------------------------------------------------------
    GRM Faction Positions v1.0.0 — должности организаций (фаза 1: данные).

    ЗАЧЕМ. У участника было ровно одно поле власти — Role. Ранг и должность
    были слиты в него, поэтому два сержанта (начальник патрульного отдела и
    рядовой патрульный) для системы выглядели ОДИНАКОВО: одни модели, одни
    права, один доступ. Чтобы сделать начальника, приходилось плодить ранги
    вида «Сержант — нач. отдела», а порядок подчинения всё равно нигде не
    хранился.

    ТРИ НЕЗАВИСИМЫЕ ОСИ (концепция CONCEPT_FACTION_POSITIONS_V5.md):
        РАНГ      — звание:            member.Role         (было и осталось)
        ДОЛЖНОСТЬ — место в штате:     member.Position     (это модуль)
        УЗЕЛ      — где служит:        Department/Subdepartment (было)

    Оси независимы: лейтенант может быть рядовым инспектором, а сержант —
    начальником отдела.

    ЗАПИСЬ ДОЛЖНОСТИ (внутри организации, f.Positions):
        f.Positions = {
            patrol_head = {
                id    = "patrol_head",
                name  = "Начальник патрульного отдела",
                node  = "dept:patrol",   -- root | dept:<key> | sub:<key>
                kind  = "head",          -- head | deputy | senior | staff
                rank  = { min = "sergeant" },
                slots = 1,
                perms = { fleet_manage = true },
                tag   = "НАЧ. ПАТР",
            },
        }

    ВЕС ВЛАСТИ не задаётся руками — он следует из вида должности (kind).
    Меньше полей, меньше шансов намудрить:
        head 80 · deputy 60 · senior 40 · staff 10
    Из веса выводится, кто в узле главный, кто кого замещает и кто кому
    подчиняется. Подчинение становится ДАННЫМИ, а не договорённостью.

    СОВМЕСТИМОСТЬ. Пустой member.Position = поведение ровно как раньше.
    Организация без должностей продолжает жить на рангах. Этот файл ничего
    не создаёт сам и никого не назначает.

    ФАЗА 1 даёт только слой данных и единый расчёт формы. Управление
    (раздел «Должности» в /factions), права и уровень должностей в
    models_admin / bodygroups_admin — следующие фазы.
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Positions = GRM.Positions or {}
local POS = GRM.Positions

POS.Version = "1.0.0"

--- Виды должностей и вес власти. Порядок важен для сортировки в UI.
POS.Kinds = {
    { id = "head",   name = "Начальник",           weight = 80 },
    { id = "deputy", name = "Заместитель",         weight = 60 },
    { id = "senior", name = "Старший сотрудник",   weight = 40 },
    { id = "staff",  name = "Сотрудник",           weight = 10 },
}

POS.KindWeight = {}
POS.KindName = {}
for _, k in ipairs(POS.Kinds) do
    POS.KindWeight[k.id] = k.weight
    POS.KindName[k.id] = k.name
end

local function trim(s, maxLen)
    return string.sub(string.Trim(tostring(s or "")), 1, tonumber(maxLen) or 96)
end

--- Организация по имени или по самой таблице.
local function factionOf(value)
    if istable(value) then return value end
    local name = tostring(value or "")
    if name == "" then return nil end
    return (Factions and Factions[name]) or (FactionsData and FactionsData[name]) or nil
end
POS.FactionOf = factionOf

-----------------------------------------------------------------------
-- УЗЛЫ СТРУКТУРЫ
-----------------------------------------------------------------------

--[[ Узел — это место в дереве организации. Один формат на весь код,
     чтобы должность, модели и правила бодигрупп говорили одинаково:
        "root"          — сама организация
        "dept:patrol"   — отдел
        "sub:traffic"   — подотдел ]]
function POS.NodeID(kind, key)
    kind = tostring(kind or "root")
    key = trim(key, 64)
    if kind == "root" or key == "" then return "root" end
    if kind == "sub" then return "sub:" .. key end
    return "dept:" .. key
end

function POS.ParseNode(node)
    node = tostring(node or "root")
    if node == "" or node == "root" then return "root", "" end
    local kind, key = string.match(node, "^(%a+):(.+)$")
    if kind == "sub" then return "sub", key end
    if kind == "dept" then return "dept", key end
    return "root", ""
end

--- Узел конкретного участника: подотдел точнее отдела.
function POS.MemberNode(member)
    if not istable(member) then return "root" end
    local sub = trim(member.Subdepartment or member.Subdept, 64)
    if sub ~= "" then return POS.NodeID("sub", sub) end
    local dept = trim(member.Department, 64)
    if dept ~= "" then return POS.NodeID("dept", dept) end
    return "root"
end

--[[ Цепочка узлов от точного к общему: подотдел → его отдел → организация.
     По ней ищут и должности, и форму, и правила внешности. ]]
function POS.NodeChain(factionValue, node)
    local f = factionOf(factionValue)
    local kind, key = POS.ParseNode(node)
    local chain = {}
    if kind == "sub" then
        chain[#chain + 1] = POS.NodeID("sub", key)
        local sub = istable(f) and istable(f.Subdepartments) and f.Subdepartments[key]
        local parent = istable(sub) and trim(sub.parentDept, 64) or ""
        if parent ~= "" then chain[#chain + 1] = POS.NodeID("dept", parent) end
    elseif kind == "dept" then
        chain[#chain + 1] = POS.NodeID("dept", key)
    end
    chain[#chain + 1] = "root"
    return chain
end

function POS.NodeDisplayName(factionValue, node)
    local f = factionOf(factionValue)
    local kind, key = POS.ParseNode(node)
    if kind == "root" then
        return (GRM.Factions and GRM.Factions.DisplayName and GRM.Factions.DisplayName(f)) or "Организация"
    end
    if kind == "dept" then
        if GRM.Factions and GRM.Factions.DepartmentDisplayName then
            return GRM.Factions.DepartmentDisplayName(f, key)
        end
        return key
    end
    if GRM.Factions and GRM.Factions.SubdepartmentDisplayName then
        return GRM.Factions.SubdepartmentDisplayName(f, key)
    end
    return key
end

-----------------------------------------------------------------------
-- НОРМАЛИЗАЦИЯ
-----------------------------------------------------------------------

function POS.NormalizeKind(kind)
    kind = string.lower(trim(kind, 16))
    if POS.KindWeight[kind] then return kind end
    return "staff"
end

function POS.Weight(position)
    if not istable(position) then return 0 end
    return POS.KindWeight[POS.NormalizeKind(position.kind)] or 0
end

--- Ключ должности: только латиница, цифры, дефис и подчёркивание.
function POS.MakeID(value)
    local id = string.lower(trim(value, 64))
    id = string.gsub(id, "[^%w_%-]", "_")
    id = string.gsub(id, "_+", "_")
    return id
end

function POS.NormalizePosition(id, row)
    if not istable(row) then return nil end
    id = POS.MakeID(id ~= "" and id or row.id)
    if id == "" then return nil end
    local out = {
        id = id,
        name = trim(row.name or row.displayName or id, 96),
        node = POS.NodeID(POS.ParseNode(row.node)),
        kind = POS.NormalizeKind(row.kind),
        tag = trim(row.tag, 24),
        slots = math.max(0, math.floor(tonumber(row.slots) or 0)),
        perms = {},
        rank = {},
    }
    if out.name == "" then out.name = id end
    -- node мог прийти как "dept:patrol" — ParseNode вернул пару, соберём назад
    local nk, nkey = POS.ParseNode(row.node)
    out.node = POS.NodeID(nk, nkey)
    for perm, on in pairs(istable(row.perms) and row.perms or {}) do
        if on == true then out.perms[tostring(perm)] = true end
    end
    local rank = istable(row.rank) and row.rank or {}
    local minRank = trim(rank.min, 96)
    if minRank ~= "" then out.rank.min = minRank end
    return out
end

--- Привести f.Positions к нормальному виду. Возвращает: изменилось ли что-то.
function POS.EnsureDefaults(factionValue)
    local f = factionOf(factionValue)
    if not istable(f) then return false end
    local changed = false
    if not istable(f.Positions) then
        f.Positions = {}
        changed = true
    end
    for id, row in pairs(f.Positions) do
        local norm = POS.NormalizePosition(id, row)
        if not norm then
            f.Positions[id] = nil
            changed = true
        else
            if norm.id ~= id then
                f.Positions[id] = nil
                f.Positions[norm.id] = norm
                changed = true
            else
                f.Positions[id] = norm
            end
        end
    end
    return changed
end

-----------------------------------------------------------------------
-- ЧТЕНИЕ
-----------------------------------------------------------------------

function POS.Get(factionValue, positionID)
    local f = factionOf(factionValue)
    if not istable(f) or not istable(f.Positions) then return nil end
    local id = POS.MakeID(positionID)
    if id == "" then return nil end
    local row = f.Positions[id]
    return istable(row) and POS.NormalizePosition(id, row) or nil
end

--- Должность участника (nil, если не назначена — это законно).
function POS.OfMember(factionValue, member)
    if not istable(member) then return nil end
    local id = POS.MakeID(member.Position)
    if id == "" then return nil end
    return POS.Get(factionValue, id)
end

--- Список должностей организации, отсортированный: сначала точные узлы,
--- внутри узла — по весу власти (начальник сверху).
function POS.List(factionValue, node)
    local f = factionOf(factionValue)
    local out = {}
    if not istable(f) or not istable(f.Positions) then return out end
    local filter = node and POS.NodeID(POS.ParseNode(node)) or nil
    for id, row in pairs(f.Positions) do
        local norm = POS.NormalizePosition(id, row)
        if norm and (not filter or norm.node == filter) then out[#out + 1] = norm end
    end
    table.sort(out, function(a, b)
        if a.node ~= b.node then return a.node < b.node end
        local wa, wb = POS.Weight(a), POS.Weight(b)
        if wa ~= wb then return wa > wb end
        return string.lower(a.name) < string.lower(b.name)
    end)
    return out
end

--- Кто занимает должность: список CharacterKey.
function POS.Holders(factionValue, positionID)
    local f = factionOf(factionValue)
    local out = {}
    local id = POS.MakeID(positionID)
    if not istable(f) or not istable(f.Members) or id == "" then return out end
    for key, rec in pairs(f.Members) do
        if istable(rec) and POS.MakeID(rec.Position) == id then out[#out + 1] = key end
    end
    table.sort(out)
    return out
end

--[[ Штат должности: занято, всего, есть ли свободные места.
     slots = 0 означает «без лимита» — так же, как quota у подотдела. ]]
function POS.Staffing(factionValue, positionID)
    local position = POS.Get(factionValue, positionID)
    if not position then return { taken = 0, slots = 0, free = 0, unlimited = true } end
    local taken = #POS.Holders(factionValue, positionID)
    local slots = math.max(0, math.floor(tonumber(position.slots) or 0))
    if slots == 0 then
        return { taken = taken, slots = 0, free = 0, unlimited = true }
    end
    return { taken = taken, slots = slots, free = math.max(0, slots - taken), unlimited = false }
end

function POS.HasFreeSlot(factionValue, positionID)
    local st = POS.Staffing(factionValue, positionID)
    return st.unlimited or st.free > 0
end

-----------------------------------------------------------------------
-- ВЕРТИКАЛЬ ПОДЧИНЕНИЯ
-----------------------------------------------------------------------

--- Начальник узла: должность с наибольшим весом среди должностей узла.
function POS.HeadOfNode(factionValue, node)
    local list = POS.List(factionValue, node)
    local best
    for _, p in ipairs(list) do
        if not best or POS.Weight(p) > POS.Weight(best) then best = p end
    end
    if best and POS.Weight(best) <= 0 then return nil end
    return best
end

--- Заместитель узла: должность вида deputy.
function POS.DeputyOfNode(factionValue, node)
    for _, p in ipairs(POS.List(factionValue, node)) do
        if POS.NormalizeKind(p.kind) == "deputy" then return p end
    end
    return nil
end

--[[ Кто главный для участника. Идём вверх по цепочке узлов: свой подотдел,
     затем его отдел, затем организация. Возвращает первую найденную
     должность-начальника СТРОГО выше по весу, чем у самого участника. ]]
function POS.SupervisorFor(factionValue, member)
    if not istable(member) then return nil end
    local own = POS.OfMember(factionValue, member)
    local ownWeight = own and POS.Weight(own) or 0
    local ownNode = own and own.node or POS.MemberNode(member)
    for i, node in ipairs(POS.NodeChain(factionValue, ownNode)) do
        local head = POS.HeadOfNode(factionValue, node)
        -- В своём узле начальник считается только если он реально выше.
        if head and (i > 1 or POS.Weight(head) > ownWeight) then
            if not own or head.id ~= own.id then return head, node end
        end
    end
    return nil
end

--- Командует ли первый участник вторым (строго выше по весу и по дереву).
function POS.Commands(factionValue, memberA, memberB)
    if not (istable(memberA) and istable(memberB)) then return false end
    local a = POS.OfMember(factionValue, memberA)
    if not a then return false end
    local b = POS.OfMember(factionValue, memberB)
    local wa = POS.Weight(a)
    local wb = b and POS.Weight(b) or 0
    if wa <= wb then return false end
    -- Начальник командует только внутри своей ветки дерева.
    local scope = a.node
    if scope == "root" then return true end
    for _, node in ipairs(POS.NodeChain(factionValue, POS.MemberNode(memberB))) do
        if node == scope then return true end
    end
    return false
end

-----------------------------------------------------------------------
-- ЕДИНЫЙ РАСЧЁТ ФОРМЫ (лечит расхождение превью и выдачи в мир)
-----------------------------------------------------------------------

--[[ БАГ, КОТОРЫЙ ЭТО ЗАКРЫВАЕТ (найден при разборе 27.08).

     Порядок выбора моделей отличался в ДВУХ местах:
       sh_faction_fixes.lua  GetModelsForPlayer  — подотдел → отдел → ранг → орг.
       sh_grm_character.lua  modelsForContext    — ранг → отдел → орг.,
                                                   подотдел не учитывался ВООБЩЕ

     Из-за этого сотрудник подотдела видел в меню персонажа одну форму, а в
     мир его одевали в другую. Теперь порядок объявлен ОДИН раз здесь, и обе
     стороны зовут эту функцию.

     Порядок (от точного к общему):
         должность → подотдел → отдел → ранг → организация → общие
     Должность впереди: у начальника отдела может быть своя форма, отличная
     от формы его подчинённых в том же отделе. ]]
function POS.ResolveLoadout(factionValue, member, kind)
    kind = (kind == "weapons") and "weapons" or "models"
    local f = factionOf(factionValue)
    if not istable(f) or not istable(member) then return nil, "none" end

    local function ok(list)
        return istable(list) and #list > 0
    end

    -- 1. должность
    local position = POS.OfMember(f, member)
    if position then
        local store = (kind == "weapons") and f.PositionWeapons or f.PositionModels
        local list = istable(store) and store[position.id]
        if ok(list) then return list, "position:" .. position.id end
    end

    -- 2. подотдел
    local sub = trim(member.Subdepartment or member.Subdept, 64)
    if sub ~= "" and istable(f.Subdepartments) and istable(f.Subdepartments[sub]) then
        local list = (kind == "weapons") and f.Subdepartments[sub].weapons or f.Subdepartments[sub].models
        if ok(list) then return list, "sub:" .. sub end
    end

    -- 3. отдел
    local dept = trim(member.Department, 64)
    if dept ~= "" then
        local store = (kind == "weapons") and f.DepartmentWeapons or f.DepartmentModels
        local list = istable(store) and store[dept]
        if ok(list) then return list, "dept:" .. dept end
    end

    -- 4. ранг
    local role = trim(member.Role, 96)
    if role ~= "" then
        local store = (kind == "weapons") and f.RoleWeapons or f.RoleModels
        local list = istable(store) and store[role]
        if ok(list) then return list, "role:" .. role end
    end

    -- 5. организация
    local list = (kind == "weapons") and f.Weapons or f.Models
    if ok(list) then return list, "faction" end

    return nil, "none"
end

-----------------------------------------------------------------------
-- ТЕГ ДОЛЖНОСТИ (для служебных каналов)
-----------------------------------------------------------------------
function POS.Tag(factionValue, member)
    local position = POS.OfMember(factionValue, member)
    if not position then return "" end
    return trim(position.tag, 24)
end

--- Человекочитаемое звание+должность: «Сержант · Начальник отдела».
function POS.DescribeMember(factionValue, member)
    if not istable(member) then return "" end
    local parts = {}
    local role = trim(member.Role, 96)
    if role ~= "" then
        local display = role
        if GRM.Factions and GRM.Factions.RoleDisplayName then
            display = GRM.Factions.RoleDisplayName(factionValue, role)
        end
        parts[#parts + 1] = display
    end
    local position = POS.OfMember(factionValue, member)
    if position then parts[#parts + 1] = position.name end
    return table.concat(parts, " · ")
end

-----------------------------------------------------------------------
-- СЕРВЕР: изменение данных
-----------------------------------------------------------------------
if SERVER then
    local function save()
        if _G.FactionsAPI and _G.FactionsAPI.Save then pcall(_G.FactionsAPI.Save) end
    end

    --- Создать или обновить должность.
    function POS.Set(factionName, positionID, data)
        local f = factionOf(factionName)
        if not istable(f) then return false, "Организация не найдена" end
        POS.EnsureDefaults(f)
        data = istable(data) and data or {}
        local id = POS.MakeID(positionID ~= "" and positionID or data.id or data.name)
        if id == "" then return false, "Не указан ключ должности" end
        data.id = id
        local norm = POS.NormalizePosition(id, data)
        if not norm then return false, "Некорректные данные должности" end

        -- Узел должен существовать, иначе должность повиснет в воздухе.
        local nk, nkey = POS.ParseNode(norm.node)
        if nk == "dept" and not table.HasValue(f.Departments or {}, nkey) then
            return false, "Отдел не найден: " .. tostring(nkey)
        end
        if nk == "sub" and not (istable(f.Subdepartments) and f.Subdepartments[nkey]) then
            return false, "Подотдел не найден: " .. tostring(nkey)
        end

        local existed = f.Positions[id] ~= nil
        f.Positions[id] = norm
        save()
        hook.Run("GRM_FactionPositionChanged", factionName, id, norm, existed and "update" or "create")
        return true, existed and "Должность обновлена" or "Должность создана"
    end

    --- Удалить должность: все, кто её занимал, остаются в организации без неё.
    function POS.Delete(factionName, positionID)
        local f = factionOf(factionName)
        if not istable(f) then return false, "Организация не найдена" end
        POS.EnsureDefaults(f)
        local id = POS.MakeID(positionID)
        if not f.Positions[id] then return false, "Должность не найдена" end
        f.Positions[id] = nil
        local cleared = 0
        for key, rec in pairs(f.Members or {}) do
            if istable(rec) and POS.MakeID(rec.Position) == id then
                rec.Position = ""
                cleared = cleared + 1
                hook.Run("GRM_FactionMemberPositionChanged", factionName, key, rec, id, "", nil)
            end
        end
        if istable(f.PositionModels) then f.PositionModels[id] = nil end
        if istable(f.PositionWeapons) then f.PositionWeapons[id] = nil end
        save()
        hook.Run("GRM_FactionPositionChanged", factionName, id, nil, "delete")
        return true, cleared > 0
            and ("Должность удалена, освобождено сотрудников: " .. cleared)
            or "Должность удалена"
    end

    --- Назначить участника на должность. Пустой positionID = снять.
    function POS.Assign(factionName, characterKey, positionID, actor)
        local f = factionOf(factionName)
        if not istable(f) then return false, "Организация не найдена" end
        POS.EnsureDefaults(f)
        local key = tostring(characterKey or "")
        local rec = istable(f.Members) and f.Members[key]
        if not istable(rec) then return false, "Сотрудник не найден в организации" end

        local id = POS.MakeID(positionID)
        local old = POS.MakeID(rec.Position)
        if id == "" then
            if old == "" then return false, "Должность и так не назначена" end
            rec.Position = ""
            save()
            hook.Run("GRM_FactionMemberPositionChanged", factionName, key, rec, old, "", actor)
            return true, "Сотрудник снят с должности"
        end

        local position = POS.Get(f, id)
        if not position then return false, "Должность не найдена" end
        if id == old then return false, "Сотрудник уже на этой должности" end

        -- Штат: слотов должно хватать. slots = 0 — без лимита.
        if not POS.HasFreeSlot(f, id) then
            local st = POS.Staffing(f, id)
            return false, ("Все места заняты (%d из %d)"):format(st.taken, st.slots)
        end

        -- Узел должности и узел сотрудника должны совпадать по ветке:
        -- нельзя быть начальником чужого отдела, оставаясь в своём.
        if position.node ~= "root" then
            local match = false
            for _, node in ipairs(POS.NodeChain(f, POS.MemberNode(rec))) do
                if node == position.node then match = true break end
            end
            if not match then
                return false, "Должность относится к другому подразделению: "
                    .. POS.NodeDisplayName(f, position.node)
            end
        end

        rec.Position = id
        save()
        hook.Run("GRM_FactionMemberPositionChanged", factionName, key, rec, old, id, actor)
        return true, "Назначен: " .. position.name
    end

    --[[ Нормализация при загрузке организаций. Ничего не создаёт: только
         приводит уже существующие записи к правильному виду и стирает
         ссылки на исчезнувшие должности. ]]
    function POS.NormalizeAll()
        if not istable(Factions) then return end
        for name, f in pairs(Factions) do
            if istable(f) then
                POS.EnsureDefaults(f)
                for key, rec in pairs(f.Members or {}) do
                    if istable(rec) then
                        local id = POS.MakeID(rec.Position)
                        if id ~= "" and not (istable(f.Positions) and f.Positions[id]) then
                            rec.Position = ""
                        elseif rec.Position ~= nil and rec.Position ~= id then
                            rec.Position = id
                        end
                    end
                end
            end
        end
    end

    hook.Add("InitPostEntity", "GRM_Positions_Normalize", function()
        timer.Simple(5, function() POS.NormalizeAll() end)
    end)

    if GRM.Modules and GRM.Modules.Register then
        GRM.Modules.Register("faction_positions", {
            label = "Должности организаций",
            version = POS.Version,
            Status = function()
                local total = 0
                for _, f in pairs(Factions or {}) do
                    if istable(f) and istable(f.Positions) then total = total + table.Count(f.Positions) end
                end
                return "должностей: " .. total
            end,
            Depends = { "factions" },
        })
    end

    --- Диагностика: grm_positions [организация]
    concommand.Add("grm_positions", function(ply)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        local function say(text)
            if IsValid(ply) then ply:PrintMessage(HUD_PRINTTALK, text) else print(text) end
        end
        say("[Должности] Версия " .. POS.Version)
        for name, f in pairs(Factions or {}) do
            if istable(f) then
                local list = POS.List(f)
                if #list > 0 then
                    say("  " .. tostring(name) .. ":")
                    for _, p in ipairs(list) do
                        local st = POS.Staffing(f, p.id)
                        say(("    [%s] %s — %s, узел %s, штат %s"):format(
                            p.kind, p.name, POS.KindName[p.kind] or p.kind,
                            POS.NodeDisplayName(f, p.node),
                            st.unlimited and (st.taken .. " (без лимита)") or (st.taken .. "/" .. st.slots)))
                    end
                end
            end
        end
    end)
end
