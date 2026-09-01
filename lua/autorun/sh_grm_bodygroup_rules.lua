--[[--------------------------------------------------------------------
    GRM Bodygroup Rules v1.0.0 — фильтр бодигрупп моделей персонажа.

    ЗАЧЕМ. Меню персонажа честно сканирует модель и раньше отдавало игроку
    ВСЕ её части (Armbands, шевроны, кобуры, погоны). Это ломало ролевую
    логику: рядовой снимал повязку отдела, гражданский надевал военную
    амуницию. Теперь список частей проходит через этот модуль: он решает,
    какие строки игрок вообще увидит, какие увидит только для чтения и
    какие значения ему разрешены.

    КАК УСТРОЕНО.
      Правило = (модель, организация, отдел/подотдел, должность) → набор
      настроек по номерам бодигрупп. Пусто в поле = «любой».
      Приоритет (следующий перекрывает предыдущий):
          модель                          (общее правило модели)
        → модель + организация
        → модель + организация + отдел
        → модель + организация + подотдел
        → модель + организация + должность
        → модель + организация + отдел + должность
        → модель + организация + подотдел + должность

      Режимы группы:
        hide  — игрок НЕ видит строку, значение принудительно = value
                (например Armbands всегда 1 и без выбора);
        lock  — строка видна, но серая и не меняется (для наглядности);
        limit — игрок видит строку, но переключает только values.

    ГДЕ ПРИМЕНЯЕТСЯ.
      1. Клиент, меню персонажа/гардероб — вкладка «Телосложение»:
         скрытые строки не рисуются, закрытые серые, ограниченные
         переключают только разрешённые значения.
      2. Сервер, GRM.Char.ApplyAppearance — любая сохранённая внешность
         прогоняется через BG.Sanitize, поэтому подделанный net-пакет
         не даст запрещённую часть.

    ДАННЫЕ. data/grm_bodygroup_rules.json
      { "version":1, "rules": { "модель|орг|отдел|должность": { "3": {...} } } }

    ДОСТУП. Редактор — только суперадмин: /bodygroups_admin или
    консольная команда grm_bodygroups_admin (есть в едином админ-хабе).
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.BGRules = GRM.BGRules or {}
local BG = GRM.BGRules

BG.Version = "1.0.0"
BG.File    = "grm_bodygroup_rules.json"
BG.Rules   = BG.Rules or {}     -- key -> { [groupIndexString] = spec }

local NET_SYNC = "GRM_BGRules_Sync"
local NET_OPEN = "GRM_BGRules_Open"
local NET_REQ  = "GRM_BGRules_Req"
local NET_ACT  = "GRM_BGRules_Act"

-----------------------------------------------------------------------
-- ОБЩАЯ ЧАСТЬ (сервер и клиент считают правила одинаково)
-----------------------------------------------------------------------

local function low(s) return string.lower(string.Trim(tostring(s or ""))) end
local function tag(s) return string.Trim(tostring(s or "")) end

--[[ Ключ правила. Пустое поле = «любой».
     Пятая часть — ДОЛЖНОСТЬ (ось v5). Правила старого формата из четырёх
     частей читаются как есть: им дописывается пустая пятая часть, поэтому
     уже настроенные правила не пропадают. ]]
function BG.Key(model, faction, dept, role, position)
    return low(model) .. "|" .. tag(faction) .. "|" .. tag(dept) .. "|"
        .. tag(role) .. "|" .. tag(position)
end

function BG.ParseKey(key)
    local parts = string.Explode("|", tostring(key or ""))
    return parts[1] or "", parts[2] or "", parts[3] or "", parts[4] or "", parts[5] or ""
end

--- Нормализация одной настройки группы.
function BG.NormalizeSpec(spec)
    if not istable(spec) then return nil end
    local mode = string.lower(tostring(spec.mode or "free"))
    if mode ~= "hide" and mode ~= "lock" and mode ~= "limit" then return nil end
    local out = { mode = mode }
    if mode == "hide" or mode == "lock" then
        out.value = math.max(0, math.floor(tonumber(spec.value) or 0))
    else
        local seen, values = {}, {}
        for _, v in ipairs(istable(spec.values) and spec.values or {}) do
            local vi = math.floor(tonumber(v) or -1)
            if vi >= 0 and not seen[vi] then seen[vi] = true values[#values + 1] = vi end
        end
        table.sort(values)
        if #values == 0 then return nil end     -- «ничего не разрешено» = правила нет
        out.values = values
    end
    return out
end

function BG.NormalizeGroups(groups)
    local out, count = {}, 0
    for gi, spec in pairs(istable(groups) and groups or {}) do
        local idx = math.floor(tonumber(gi) or -1)
        local norm = BG.NormalizeSpec(spec)
        if idx >= 0 and norm then out[tostring(idx)] = norm count = count + 1 end
    end
    return out, count
end

--[[ Разрешение правил для конкретной модели и контекста игрока.
     ctx = { faction=..., dept=..., sub=..., role=..., position=... }

     Порядок цепочки — от общего к точному, следующее звено перекрывает
     предыдущее. ДОЛЖНОСТЬ идёт последней, то есть она сильнее ранга:
     у начальника отдела нашивка на месте, у рядового того же отдела с тем
     же званием та же строка скрыта. ]]
function BG.Resolve(model, ctx)
    ctx = istable(ctx) and ctx or {}
    local faction, dept, sub = tag(ctx.faction), tag(ctx.dept), tag(ctx.sub)
    local role, position = tag(ctx.role), tag(ctx.position)
    local chain = { BG.Key(model, "", "", "", "") }
    if faction ~= "" then
        chain[#chain + 1] = BG.Key(model, faction, "", "", "")
        if dept ~= "" then chain[#chain + 1] = BG.Key(model, faction, dept, "", "") end
        if sub ~= "" then chain[#chain + 1] = BG.Key(model, faction, sub, "", "") end
        if role ~= "" then
            chain[#chain + 1] = BG.Key(model, faction, "", role, "")
            if dept ~= "" then chain[#chain + 1] = BG.Key(model, faction, dept, role, "") end
            if sub ~= "" then chain[#chain + 1] = BG.Key(model, faction, sub, role, "") end
        end
        -- Должность: сильнее ранга, поэтому её звенья идут последними.
        if position ~= "" then
            chain[#chain + 1] = BG.Key(model, faction, "", "", position)
            if dept ~= "" then chain[#chain + 1] = BG.Key(model, faction, dept, "", position) end
            if sub ~= "" then chain[#chain + 1] = BG.Key(model, faction, sub, "", position) end
            if role ~= "" then
                chain[#chain + 1] = BG.Key(model, faction, "", role, position)
                if dept ~= "" then chain[#chain + 1] = BG.Key(model, faction, dept, role, position) end
                if sub ~= "" then chain[#chain + 1] = BG.Key(model, faction, sub, role, position) end
            end
        end
    end
    local out = {}
    for _, key in ipairs(chain) do
        local rule = BG.Rules[key]
        if istable(rule) then
            for gi, spec in pairs(rule) do
                local idx = math.floor(tonumber(gi) or -1)
                local norm = BG.NormalizeSpec(spec)
                if idx >= 0 and norm then out[idx] = norm end
            end
        end
    end
    return out
end

--- Разрешено ли игроку видеть строку группы.
function BG.IsVisible(spec)
    return not (istable(spec) and spec.mode == "hide")
end

--- Разрешено ли игроку менять строку группы.
function BG.IsEditable(spec)
    if not istable(spec) then return true end
    return spec.mode ~= "hide" and spec.mode ~= "lock"
end

--- Список разрешённых значений группы (nil = все 0..total-1).
function BG.AllowedValues(spec, total)
    total = math.max(1, math.floor(tonumber(total) or 1))
    if not istable(spec) then return nil end
    if spec.mode == "limit" then
        local out = {}
        for _, v in ipairs(spec.values or {}) do
            if v >= 0 and v < total then out[#out + 1] = v end
        end
        if #out == 0 then return { 0 } end
        return out
    end
    if spec.mode == "hide" or spec.mode == "lock" then
        return { math.Clamp(math.floor(tonumber(spec.value) or 0), 0, total - 1) }
    end
    return nil
end

--[[ Приведение набора бодигрупп к правилам. Возвращает таблицу со
     строковыми ключами (формат GRM.Char.NormalizeBodygroups). ]]
function BG.Sanitize(model, bodygroups, ctx)
    local rules = BG.Resolve(model, ctx)
    local cur = {}
    for g, v in pairs(istable(bodygroups) and bodygroups or {}) do
        local gi, vi = tonumber(g), tonumber(v)
        if gi and vi then
            gi, vi = math.floor(gi), math.floor(vi)
            if gi >= 0 and vi > 0 then cur[gi] = vi end
        end
    end
    for gi, spec in pairs(rules) do
        if spec.mode == "hide" or spec.mode == "lock" then
            local val = math.max(0, math.floor(tonumber(spec.value) or 0))
            cur[gi] = (val > 0) and val or nil
        elseif spec.mode == "limit" then
            local allowed = {}
            for _, v in ipairs(spec.values or {}) do allowed[v] = true end
            local now = cur[gi] or 0
            if not allowed[now] then
                local pick
                for _, v in ipairs(spec.values or {}) do
                    if not pick or v < pick then pick = v end
                end
                pick = pick or 0
                cur[gi] = (pick > 0) and pick or nil
            end
        end
    end
    local out = {}
    for gi, v in pairs(cur) do
        if v > 0 then out[tostring(gi)] = v end
    end
    return out
end

--- Контекст игрока: организация/отдел/подотдел/должность его персонажа.
function BG.ContextFor(ply, characterKey)
    local key = tostring(characterKey or "")
    if key == "" and GRM.Char and GRM.Char.GetActiveKey then
        key = tostring(GRM.Char.GetActiveKey(ply) or "")
    end
    local src = (SERVER and Factions) or (CLIENT and (Factions or FactionsData)) or {}
    for name, f in pairs(src or {}) do
        if istable(f) and istable(f.Members) then
            local member = key ~= "" and f.Members[key] or nil
            if not istable(member) and GRM.Identity and GRM.Identity.FactionMember then
                member = GRM.Identity.FactionMember(f, ply)
            end
            if istable(member) then
                return {
                    faction = name,
                    dept = tostring(member.Department or ""),
                    sub = tostring(member.Subdepartment or member.Subdept or ""),
                    role = tostring(member.Role or ""),
                    position = tostring(member.Position or ""),
                }
            end
        end
    end
    return { faction = "", dept = "", sub = "", role = "", position = "" }
end

--[[ МИГРАЦИЯ КЛЮЧЕЙ. До появления должностей ключ состоял из четырёх
     частей: модель|организация|узел|ранг. Теперь их пять. Старые правила
     дочитываются как «должность не указана», то есть продолжают работать
     ровно как раньше. ]]
function BG.UpgradeKey(key)
    key = tostring(key or "")
    if key == "" then return key end
    local parts = string.Explode("|", key)
    if #parts >= 5 then return key end
    for i = #parts + 1, 5 do parts[i] = "" end
    return table.concat(parts, "|")
end

function BG.UpgradeRules(rules)
    local out = {}
    for key, groups in pairs(istable(rules) and rules or {}) do
        if isstring(key) and istable(groups) then out[BG.UpgradeKey(key)] = groups end
    end
    return out
end

--- Есть ли для модели хоть одно правило (для подсветки в редакторе).
function BG.HasAnyRule(model)
    local prefix = low(model) .. "|"
    for key in pairs(BG.Rules) do
        if string.sub(key, 1, #prefix) == prefix then return true end
    end
    return false
end

-----------------------------------------------------------------------
-- СЕРВЕР
-----------------------------------------------------------------------
if SERVER then
    util.AddNetworkString(NET_SYNC)
    util.AddNetworkString(NET_OPEN)
    util.AddNetworkString(NET_REQ)
    util.AddNetworkString(NET_ACT)

    local function jsonT(txt)
        local ok, t = pcall(util.JSONToTable, txt, false, true)
        return (ok and istable(t)) and t or nil
    end

    function BG.Load()
        BG.Rules = {}
        if not file.Exists(BG.File, "DATA") then return end
        local t = jsonT(file.Read(BG.File, "DATA") or "")
        if not istable(t) then return end
        local raw = BG.UpgradeRules(istable(t.rules) and t.rules or t)
        for key, groups in pairs(raw) do
            if isstring(key) and istable(groups) then
                local norm, count = BG.NormalizeGroups(groups)
                if count > 0 then BG.Rules[key] = norm end
            end
        end
    end

    function BG.Save(reason)
        local ok, txt = pcall(util.TableToJSON, { version = 1, rules = BG.Rules or {} }, true)
        if ok and txt then
            file.Write(BG.File, txt)
        else
            ErrorNoHalt("[GRM Bodygroups] Не удалось сохранить правила (" .. tostring(reason) .. ")\n")
        end
    end

    BG.Load()

    --[[ Рассылка правил: клиент считает те же правила локально в меню.
         Пакет сжимаем — правил на большой сервер набирается много, а
         сырой JSON быстро упирается в лимит net-сообщения. ]]
    function BG.Sync(ply)
        local ok, txt = pcall(util.TableToJSON, BG.Rules or {})
        if not ok or not txt then return end
        local data = util.Compress(txt) or ""
        if #data == 0 then return end
        net.Start(NET_SYNC)
            net.WriteUInt(#txt, 32)
            net.WriteUInt(#data, 32)
            net.WriteData(data, #data)
        if IsValid(ply) then net.Send(ply) else net.Broadcast() end
    end

    hook.Add("PlayerInitialSpawn", "GRM_BGRules_Sync", function(ply)
        timer.Simple(3, function() if IsValid(ply) then BG.Sync(ply) end end)
    end)

    --- Записать/удалить правило одной области.
    function BG.SetRule(model, faction, dept, role, groups, position)
        model = low(model)
        if model == "" then return false, "Модель не указана" end
        local key = BG.Key(model, faction, dept, role, position)
        local norm, count = BG.NormalizeGroups(groups)
        if count == 0 then
            BG.Rules[key] = nil
        else
            BG.Rules[key] = norm
        end
        BG.Save("setrule")
        BG.Sync()
        hook.Run("GRM_BodygroupRulesChanged", key, BG.Rules[key])
        return true, count == 0 and "Правило снято" or ("Сохранено настроек: " .. count)
    end

    function BG.DeleteRule(key)
        key = tostring(key or "")
        if BG.Rules[key] == nil then return false, "Правило не найдено" end
        BG.Rules[key] = nil
        BG.Save("delrule")
        BG.Sync()
        hook.Run("GRM_BodygroupRulesChanged", key, nil)
        return true, "Правило удалено"
    end

    --[[ Снимок для редактора: правила + организации (должности, отделы,
         подотделы) + модели, которые вообще где-то используются. ]]
    local function collectSnapshot()
        local factions, models, seen = {}, {}, {}

        local function addModel(path, owner)
            path = low(isstring(path) and path or (istable(path) and (path.path or path.model or path[1]) or ""))
            if path == "" then return end
            if not seen[path] then
                seen[path] = { path = path, owners = {} }
                models[#models + 1] = seen[path]
            end
            if owner and owner ~= "" and not table.HasValue(seen[path].owners, owner) then
                table.insert(seen[path].owners, owner)
            end
        end

        for _, entry in ipairs(istable(DefaultModels) and DefaultModels or {}) do
            addModel(entry, "Общие")
        end
        for _, g in ipairs({ "male", "female" }) do
            for _, p in ipairs((GRM.Char and GRM.Char.CitizenModels and GRM.Char.CitizenModels[g]) or {}) do
                addModel(p, "Гражданские")
            end
        end

        for name, f in pairs(Factions or {}) do
            if istable(f) then
                local row = {
                    name = name,
                    display = (GRM.Factions and GRM.Factions.DisplayName and GRM.Factions.DisplayName(f, name)) or name,
                    roles = {}, depts = {}, models = {}, positions = {},
                }
                -- Должности организации (ось v5): нужны редактору правил,
                -- чтобы можно было закрыть часть формы конкретной должности.
                if GRM.Positions and GRM.Positions.List then
                    for _, pos in ipairs(GRM.Positions.List(f)) do
                        local nodeName = GRM.Positions.NodeDisplayName(f, pos.node)
                        local kindName = GRM.Positions.KindName[pos.kind] or pos.kind
                        row.positions[#row.positions + 1] = {
                            key = pos.id,
                            display = pos.name .. "  (" .. kindName .. " • " .. nodeName .. ")",
                        }
                    end
                end
                for _, roleKey in ipairs(istable(f.Roles) and f.Roles or {}) do
                    row.roles[#row.roles + 1] = { key = roleKey,
                        display = (GRM.Factions and GRM.Factions.RoleDisplayName and GRM.Factions.RoleDisplayName(f, roleKey)) or roleKey }
                end
                for _, deptKey in ipairs(istable(f.Departments) and f.Departments or {}) do
                    row.depts[#row.depts + 1] = { key = deptKey, sub = false,
                        display = (GRM.Factions and GRM.Factions.DepartmentDisplayName and GRM.Factions.DepartmentDisplayName(f, deptKey)) or deptKey }
                end
                for subKey, sub in pairs(istable(f.Subdepartments) and f.Subdepartments or {}) do
                    if istable(sub) then
                        row.depts[#row.depts + 1] = { key = subKey, sub = true,
                            display = tostring(sub.name or subKey) }
                    end
                end

                local function addFactionModels(list, owner)
                    for _, entry in ipairs(istable(list) and list or {}) do
                        addModel(entry, owner)
                        local p = low(isstring(entry) and entry or (istable(entry) and (entry.path or entry.model or entry[1]) or ""))
                        if p ~= "" and not table.HasValue(row.models, p) then row.models[#row.models + 1] = p end
                    end
                end
                addFactionModels(f.Models, row.display)
                for roleKey, list in pairs(istable(f.RoleModels) and f.RoleModels or {}) do
                    addFactionModels(list, row.display .. " • " .. tostring(roleKey))
                end
                for deptKey, list in pairs(istable(f.DepartmentModels) and f.DepartmentModels or {}) do
                    addFactionModels(list, row.display .. " • " .. tostring(deptKey))
                end
                for subKey, sub in pairs(istable(f.Subdepartments) and f.Subdepartments or {}) do
                    if istable(sub) then addFactionModels(sub.models, row.display .. " • " .. tostring(subKey)) end
                end
                --[[ Модели ДОЛЖНОСТЕЙ (ось v5) не попадали в список вообще:
                     админ ставил модель должности в models_admin, шёл в
                     редактор правил — а модели там нет, выбрать нечего.
                     Это и была «пустота» из отчёта 27.08. ]]
                for posKey, list in pairs(istable(f.PositionModels) and f.PositionModels or {}) do
                    addFactionModels(list, row.display .. " • должность " .. tostring(posKey))
                end

                table.sort(row.roles, function(a, b) return string.lower(a.display) < string.lower(b.display) end)
                table.sort(row.depts, function(a, b) return string.lower(a.display) < string.lower(b.display) end)
                table.sort(row.models)
                factions[#factions + 1] = row
            end
        end
        --[[ Модель могли убрать из фракции ПОСЛЕ того, как для неё завели
             правило. Тогда её не было ни в одном списке: правило продолжало
             действовать на игроков, а открыть и снять его в редакторе было
             негде — со стороны это выглядело как «структура багается».
             Поэтому любая модель с правилами всегда попадает в список. ]]
        for key in pairs(BG.Rules or {}) do
            local path = tostring(string.Explode("|", key)[1] or "")
            if path ~= "" then addModel(path, "есть правила") end
        end

        table.sort(factions, function(a, b) return string.lower(a.display) < string.lower(b.display) end)
        table.sort(models, function(a, b) return a.path < b.path end)

        return { rules = BG.Rules or {}, factions = factions, models = models }
    end

    --[[ focus = { model=, faction=, dept=, role=, position= } — редактор
         откроется сразу на нужной модели и области. Так работает переход
         «Правила бодигрупп» из models_admin: админ выбрал модель должности
         и попал ровно в её правила, а не в пустой список. ]]
    function BG.OpenEditor(ply, focus)
        if not (IsValid(ply) and ply:IsSuperAdmin()) then
            if IsValid(ply) then ply:PrintMessage(HUD_PRINTTALK, "[Бодигруппы] Редактор доступен только суперадмину.") end
            return false
        end
        local snapshot = collectSnapshot()
        if istable(focus) then
            snapshot.focus = {
                model = low(focus.model),
                faction = tag(focus.faction),
                dept = tag(focus.dept),
                role = tag(focus.role),
                position = tag(focus.position),
            }
            -- Модель из фокуса обязана быть в списке, даже если её нигде нет.
            if snapshot.focus.model ~= "" then
                local found = false
                for _, row in ipairs(snapshot.models) do
                    if row.path == snapshot.focus.model then found = true break end
                end
                if not found then
                    snapshot.models[#snapshot.models + 1] =
                        { path = snapshot.focus.model, owners = { "из редактора моделей" } }
                end
            end
        end
        local ok, txt = pcall(util.TableToJSON, snapshot)
        if not ok or not txt then return false end
        local data = util.Compress(txt)
        net.Start(NET_OPEN)
            net.WriteUInt(#txt, 32)
            net.WriteUInt(#data, 32)
            net.WriteData(data, #data)
        net.Send(ply)
        return true
    end

    net.Receive(NET_REQ, function(_, ply)
        if not (IsValid(ply) and ply:IsSuperAdmin()) then return end
        if GRM.Perf and GRM.Perf.Throttle and not GRM.Perf.Throttle("bgrules.open." .. ply:EntIndex(), 0.5) then return end
        local focus = net.ReadTable()
        BG.OpenEditor(ply, istable(focus) and focus or nil)
    end)

    net.Receive(NET_ACT, function(_, ply)
        if not (IsValid(ply) and ply:IsSuperAdmin()) then return end
        local payload = net.ReadTable() or {}
        local action = tostring(payload.action or "")
        local ok, msg = false, "Неизвестное действие"
        if action == "save" then
            ok, msg = BG.SetRule(payload.model, payload.faction, payload.dept, payload.role,
                payload.groups, payload.position)
        elseif action == "delete" then
            ok, msg = BG.DeleteRule(payload.key)
        end
        if GRM.Audit and GRM.Audit.Write then
            GRM.Audit.Write("bodygroups", action, ply, {}, { model = payload.model, faction = payload.faction,
                dept = payload.dept, role = payload.role, ok = ok })
        end
        ply:PrintMessage(HUD_PRINTTALK, "[Бодигруппы] " .. tostring(msg))
        --[[ Раньше здесь заново открывался ВЕСЬ редактор. Окно уничтожалось
             и создавалось с нуля, поэтому после каждого сохранения или
             удаления правила сбрасывались выбранная организация, отдел,
             должность и модель — админ каждый раз возвращался в начало.
             Правила уже разосланы через BG.Sync внутри SetRule/DeleteRule,
             и клиент обновит списки на месте, не трогая выбор. ]]
    end)

    concommand.Add("grm_bodygroups_admin", function(ply) BG.OpenEditor(ply) end)

    --- Открыть правила конкретной модели и области (зовёт models_admin).
    function BG.OpenFor(ply, focus) return BG.OpenEditor(ply, focus) end

    hook.Add("PlayerSay", "GRM_BGRules_Cmd", function(ply, text)
        local low2 = string.lower(string.Trim(tostring(text or "")))
        if low2 == "/bodygroups_admin" or low2 == "!bodygroups_admin" or low2 == "/бодигруппы" then
            BG.OpenEditor(ply)
            return ""
        end
    end)

    if GRM.Modules and GRM.Modules.Register then
        GRM.Modules.Register("bodygroup_rules", {
            label = "Правила бодигрупп",
            version = BG.Version,
            Refresh = function(ply) BG.Sync(ply) end,
            Status = function() return "правил: " .. tostring(table.Count(BG.Rules or {})) end,
            Depends = { "factions" },
        })
    end
end

-----------------------------------------------------------------------
-- КЛИЕНТ
-----------------------------------------------------------------------
if CLIENT then
    net.Receive(NET_SYNC, function()
        local rawLen = net.ReadUInt(32)
        local len = net.ReadUInt(32)
        local data = net.ReadData(len)
        local txt = util.Decompress(data, rawLen + 64) or ""
        local ok, t = pcall(util.JSONToTable, txt, false, true)
        BG.Rules = BG.UpgradeRules((ok and istable(t)) and t or {})
        --[[ Редактор открыт — обновляем его СОДЕРЖИМОЕ, не трогая окно и
             выбранную область. Это и есть замена прежнему пересозданию. ]]
        if BG._editorRefresh then
            local okRefresh, err = pcall(BG._editorRefresh)
            if not okRefresh then
                BG._editorRefresh = nil
                ErrorNoHalt("[GRM Bodygroups] обновление редактора: " .. tostring(err) .. "\n")
            end
        end
        hook.Run("GRM_BodygroupRulesSynced")
    end)

    local C = {
        bg     = Color(12, 15, 22, 250),
        head   = Color(22, 30, 44),
        panel  = Color(20, 26, 38),
        panel2 = Color(28, 36, 52),
        acc    = Color(70, 150, 240),
        green  = Color(60, 190, 120),
        red    = Color(200, 80, 80),
        yellow = Color(240, 200, 90),
        text   = Color(228, 234, 244),
        dim    = Color(140, 155, 175),
    }
    surface.CreateFont("GRMBG_Title",  { font = "Roboto", size = 24, weight = 700, extended = true, antialias = true })
    surface.CreateFont("GRMBG_Sub",    { font = "Roboto", size = 18, weight = 600, extended = true, antialias = true })
    surface.CreateFont("GRMBG_Normal", { font = "Roboto", size = 16, weight = 500, extended = true, antialias = true })
    surface.CreateFont("GRMBG_Small",  { font = "Roboto", size = 13, weight = 500, extended = true, antialias = true })

    local function button(parent, text, color, w, h)
        local b = vgui.Create("DButton", parent)
        b:SetText("")
        if w and h then b:SetSize(w, h) end
        b.Paint = function(self, pw, ph)
            local c = self:IsHovered() and Color(math.min(255, color.r + 30), math.min(255, color.g + 30), math.min(255, color.b + 30)) or color
            draw.RoundedBox(6, 0, 0, pw, ph, c)
            draw.SimpleText(text, "GRMBG_Normal", pw / 2, ph / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        return b
    end

    local function modeLabel(spec)
        if not istable(spec) then return "Доступно игроку", C.green end
        if spec.mode == "hide" then return "Скрыто (значение " .. tostring(spec.value or 0) .. ")", C.red end
        if spec.mode == "lock" then return "Закреплено на " .. tostring(spec.value or 0), C.yellow end
        if spec.mode == "limit" then return "Разрешено: " .. table.concat(spec.values or {}, ", "), C.acc end
        return "Доступно игроку", C.green
    end

    local editor
    local function openEditor(snapshot)
        if IsValid(editor) then editor:Remove() end

        local rules    = istable(snapshot.rules) and snapshot.rules or {}
        local factions = istable(snapshot.factions) and snapshot.factions or {}
        local models   = istable(snapshot.models) and snapshot.models or {}
        BG.Rules = rules

        -- Текущая область правки.
        local sel = { faction = "", dept = "", role = "", position = "", model = "" }
        local draftGroups = {}          -- [индексСтрокой] = spec (черновик, до «Сохранить»)
        local modelInfo = {}            -- сканирование модели: [i] = { name, total }

        local f = vgui.Create("DFrame")
        editor = f
        f:SetSize(math.min(1480, ScrW() - 60), math.min(880, ScrH() - 60))
        f:Center()
        f:MakePopup()
        f:SetTitle("")
        f:ShowCloseButton(false)
        if GRM.UI and GRM.UI.Track then GRM.UI.Track("bodygroups.admin", f) end
        f.Paint = function(_, pw, ph)
            draw.RoundedBox(10, 0, 0, pw, ph, C.bg)
            draw.RoundedBoxEx(10, 0, 0, pw, 62, C.head, true, true, false, false)
            draw.SimpleText("ПРАВИЛА БОДИГРУПП МОДЕЛЕЙ", "GRMBG_Title", 22, 20, C.text)
            draw.SimpleText("Что игрок видит и может менять в меню персонажа", "GRMBG_Small", 22, 44, C.dim)
        end
        local close = button(f, "ЗАКРЫТЬ", C.red, 120, 30)
        close:SetPos(f:GetWide() - 136, 16)
        close.DoClick = function() f:Remove() end

        -- ── ЛЕВО: область действия ───────────────────────────────────
        local left = vgui.Create("DPanel", f)
        left:SetPos(16, 74)
        left:SetSize(360, f:GetTall() - 90)
        left.Paint = function(_, pw, ph) draw.RoundedBox(8, 0, 0, pw, ph, C.panel) end

        local function head(parent, text, y)
            local l = vgui.Create("DLabel", parent)
            l:SetPos(12, y) l:SetSize(parent:GetWide() - 24, 20)
            l:SetFont("GRMBG_Sub") l:SetTextColor(C.yellow) l:SetText(text)
            return l
        end

        head(left, "1. Область действия", 10)

        local facCombo = vgui.Create("DComboBox", left)
        facCombo:SetPos(12, 36) facCombo:SetSize(336, 28)
        facCombo:SetSortItems(false)
        local deptCombo = vgui.Create("DComboBox", left)
        deptCombo:SetPos(12, 72) deptCombo:SetSize(336, 28)
        deptCombo:SetSortItems(false)
        local roleCombo = vgui.Create("DComboBox", left)
        roleCombo:SetPos(12, 108) roleCombo:SetSize(336, 28)
        roleCombo:SetSortItems(false)
        -- Должность — отдельная ось: сильнее ранга. Начальник отдела и
        -- рядовой того же отдела с тем же званием получают разные правила.
        local posCombo = vgui.Create("DComboBox", left)
        posCombo:SetPos(12, 144) posCombo:SetSize(336, 28)
        posCombo:SetSortItems(false)

        head(left, "2. Модель", 182)
        local search = vgui.Create("DTextEntry", left)
        search:SetPos(12, 208) search:SetSize(336, 26)
        search:SetPlaceholderText("Поиск по пути модели…")
        search:SetUpdateOnType(true)

        local modelList = vgui.Create("DScrollPanel", left)
        modelList:SetPos(12, 242) modelList:SetSize(336, left:GetTall() - 376)

        local rulesHead = vgui.Create("DLabel", left)
        rulesHead:SetFont("GRMBG_Sub") rulesHead:SetTextColor(C.yellow)
        rulesHead:SetPos(12, left:GetTall() - 126) rulesHead:SetSize(336, 20)
        rulesHead:SetText("Сохранённые правила модели")
        local savedList = vgui.Create("DScrollPanel", left)
        savedList:SetPos(12, left:GetTall() - 102) savedList:SetSize(336, 90)

        -- ── ЦЕНТР: превью ────────────────────────────────────────────
        local center = vgui.Create("DPanel", f)
        center:SetPos(388, 74)
        center:SetSize(400, f:GetTall() - 90)
        center.Paint = function(_, pw, ph)
            draw.RoundedBox(8, 0, 0, pw, ph, C.panel)
        end
        local preview = vgui.Create("DModelPanel", center)
        preview:SetPos(8, 8) preview:SetSize(384, center:GetTall() - 66)
        preview:SetFOV(34)
        preview:SetAnimated(false)
        preview.LayoutEntity = function(self, ent)
            if IsValid(ent) then ent:SetAngles(Angle(0, self.GRMYaw or 45, 0)) end
        end
        preview.GRMYaw = 45
        preview.OnMousePressed = function(self) self.GRMDrag = true self:MouseCapture(true) end
        preview.OnMouseReleased = function(self) self.GRMDrag = false self:MouseCapture(false) end
        preview.OnCursorMoved = function(self, x)
            if not self.GRMDrag then return end
            local last = self.GRMLastX or x
            self.GRMYaw = (self.GRMYaw or 45) + (x - last) * 0.6
            self.GRMLastX = x
        end
        local previewNote = vgui.Create("DLabel", center)
        previewNote:SetPos(12, center:GetTall() - 50) previewNote:SetSize(376, 40)
        previewNote:SetFont("GRMBG_Small") previewNote:SetTextColor(C.dim)
        previewNote:SetWrap(true)
        previewNote:SetText("Модель не выбрана.")

        -- ── ПРАВО: строки бодигрупп ──────────────────────────────────
        local right = vgui.Create("DPanel", f)
        right:SetPos(800, 74)
        right:SetSize(f:GetWide() - 816, f:GetTall() - 90)
        right.Paint = function(_, pw, ph) draw.RoundedBox(8, 0, 0, pw, ph, C.panel) end

        local scopeLine = vgui.Create("DLabel", right)
        scopeLine:SetPos(14, 10) scopeLine:SetSize(right:GetWide() - 28, 20)
        scopeLine:SetFont("GRMBG_Sub") scopeLine:SetTextColor(C.acc)
        scopeLine:SetText("Область: все организации")

        local groupScroll = vgui.Create("DScrollPanel", right)
        groupScroll:SetPos(14, 38) groupScroll:SetSize(right:GetWide() - 28, right:GetTall() - 100)

        local saveBtn = button(right, "СОХРАНИТЬ ПРАВИЛО ОБЛАСТИ", C.green, 320, 38)
        saveBtn:SetPos(14, right:GetTall() - 52)
        local clearBtn = button(right, "СНЯТЬ ПРАВИЛО ОБЛАСТИ", C.red, 300, 38)
        clearBtn:SetPos(348, right:GetTall() - 52)

        -- ── логика ───────────────────────────────────────────────────
        local rebuildGroups, rebuildModels, rebuildSaved

        --- Правило текущей области (без наследования) из BG.Rules.
        local function currentKey()
            return BG.Key(sel.model, sel.faction, sel.dept, sel.role, sel.position)
        end

        --- Наследованные правила (что действует, если в области пусто).
        local function inherited()
            local scope = { faction = sel.faction, dept = sel.dept, role = sel.role,
                position = sel.position }
            return BG.Resolve(sel.model, scope)
        end

        local function scanModel()
            modelInfo = {}
            local ent = IsValid(preview) and preview:GetEntity() or nil
            if not IsValid(ent) then return end
            for i = 0, (ent:GetNumBodyGroups() or 0) - 1 do
                local total = ent:GetBodygroupCount(i) or 1
                local name = ent:GetBodygroupName(i)
                if name == "" then name = "Группа " .. i end
                modelInfo[i] = { name = name, total = total }
            end
        end

        --[[ Итоговые настройки области: наследование + черновик.
             В черновике false = «админ явно вернул строку игроку». ]]
        local function effective()
            local eff = inherited()
            local own = BG.Rules[currentKey()] or {}
            for gi, spec in pairs(own) do eff[math.floor(tonumber(gi) or 0)] = spec end
            for gi, spec in pairs(draftGroups) do
                local idx = math.floor(tonumber(gi) or 0)
                if spec == false then eff[idx] = nil else eff[idx] = spec end
            end
            return eff
        end

        local function applyPreviewRules()
            local ent = IsValid(preview) and preview:GetEntity() or nil
            if not IsValid(ent) then return end
            for i = 0, (ent:GetNumBodyGroups() or 0) - 1 do ent:SetBodygroup(i, 0) end
            for gi, spec in pairs(effective()) do
                if istable(spec) and (spec.mode == "hide" or spec.mode == "lock") then
                    ent:SetBodygroup(gi, math.floor(tonumber(spec.value) or 0))
                end
            end
        end

        --[[ Модель в DModelPanel появляется НЕ мгновенно: сразу после
             SetModel список бодигрупп ещё пуст, и правая колонка писала
             «нет настраиваемых частей» — выглядело как «модель не
             назначается». Одной проверки через 0.05 с не хватало на тяжёлых
             моделях. Теперь ждём появления частей несколькими попытками и
             прекращаем, как только модель прочиталась. ]]
        local modelToken = 0
        local function awaitModel(token, tries)
            if not IsValid(f) or token ~= modelToken then return end
            scanModel()
            applyPreviewRules()
            rebuildGroups()
            local ent = IsValid(preview) and preview:GetEntity() or nil
            local ready = IsValid(ent) and (ent:GetNumBodyGroups() or 0) > 0
            if ready or tries <= 0 then return end
            timer.Simple(0.1, function() awaitModel(token, tries - 1) end)
        end

        local function frameCamera()
            local ent = IsValid(preview) and preview:GetEntity() or nil
            if not IsValid(ent) then return end
            local mn, mx = ent:GetRenderBounds()
            local mid = (mn + mx) * 0.5
            local hgt = math.max(16, mx.z - mn.z)
            local dist = (hgt * 0.55) / math.tan(math.rad(17))
            preview:SetLookAt(Vector(0, 0, mid.z))
            preview:SetCamPos(Vector(dist, dist * 0.2, mid.z + hgt * 0.05))
        end

        local function setModel(path)
            sel.model = low(path)
            draftGroups = {}
            modelToken = modelToken + 1
            preview:SetModel(sel.model)
            frameCamera()
            previewNote:SetText(sel.model)
            scanModel()
            rebuildGroups()
            rebuildSaved()
            rebuildModels()
            -- до 12 попыток (~1.2 с): хватает и тяжёлым моделям
            awaitModel(modelToken, 12)
        end

        local function scopeText()
            local parts = {}
            parts[#parts + 1] = sel.faction == "" and "все организации" or sel.faction
            if sel.dept ~= "" then parts[#parts + 1] = "отдел/подотдел: " .. sel.dept end
            if sel.role ~= "" then parts[#parts + 1] = "звание: " .. sel.role end
            if sel.position ~= "" then parts[#parts + 1] = "должность: " .. sel.position end
            return "Область: " .. table.concat(parts, " • ")
        end

        rebuildSaved = function()
            savedList:Clear()
            if sel.model == "" then return end
            local prefix = sel.model .. "|"
            local keys = {}
            for key in pairs(BG.Rules or {}) do
                if string.sub(key, 1, #prefix) == prefix then keys[#keys + 1] = key end
            end
            table.sort(keys)
            if #keys == 0 then
                local l = vgui.Create("DLabel", savedList)
                l:Dock(TOP) l:SetTall(20) l:SetFont("GRMBG_Small") l:SetTextColor(C.dim)
                l:SetText("Правил для этой модели нет.")
                return
            end
            for _, key in ipairs(keys) do
                local _, fac, dept, role, position = BG.ParseKey(key)
                local row = vgui.Create("DPanel", savedList)
                row:Dock(TOP) row:SetTall(26) row:DockMargin(0, 0, 4, 4)
                local label = (fac == "" and "все организации" or fac)
                    .. (dept ~= "" and (" / " .. dept) or "")
                    .. (role ~= "" and (" / " .. role) or "")
                    .. (position ~= "" and (" / ★" .. position) or "")
                row.Paint = function(_, pw, ph)
                    draw.RoundedBox(4, 0, 0, pw, ph, C.panel2)
                    draw.SimpleText(label, "GRMBG_Small", 8, ph / 2, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end
                local del = button(row, "×", C.red, 24, 20)
                row.PerformLayout = function(self, pw) del:SetPos(pw - 28, 3) end
                del.DoClick = function()
                    net.Start(NET_ACT) net.WriteTable({ action = "delete", key = key }) net.SendToServer()
                end
            end
        end

        rebuildGroups = function()
            groupScroll:Clear()
            scopeLine:SetText(scopeText())
            if sel.model == "" then
                local l = vgui.Create("DLabel", groupScroll)
                l:Dock(TOP) l:SetTall(24) l:SetFont("GRMBG_Normal") l:SetTextColor(C.dim)
                l:SetText("Выберите модель слева — её части будут просканированы.")
                return
            end
            local count = table.Count(modelInfo)
            if count == 0 then
                local l = vgui.Create("DLabel", groupScroll)
                l:Dock(TOP) l:SetTall(24) l:SetFont("GRMBG_Normal") l:SetTextColor(C.dim)
                l:SetText("У модели нет настраиваемых частей (или она ещё грузится).")
                return
            end

            local eff = inherited()
            local own = BG.Rules[currentKey()] or {}

            for i = 0, count - 1 do
                local info = modelInfo[i]
                if info then
                    local key = tostring(i)
                    -- false в черновике = «строка возвращена игроку».
                    local drafted = draftGroups[key]
                    local spec
                    if drafted == false then spec = nil
                    elseif istable(drafted) then spec = drafted
                    elseif istable(own[key]) then spec = table.Copy(own[key]) end
                    local inheritedSpec = eff[i]

                    local row = vgui.Create("DPanel", groupScroll)
                    row:Dock(TOP) row:SetTall(76) row:DockMargin(0, 0, 6, 8)
                    row.Paint = function(_, pw, ph)
                        draw.RoundedBox(6, 0, 0, pw, ph, C.panel2)
                        draw.SimpleText("[" .. i .. "] " .. info.name .. "   (вариантов: " .. info.total .. ")",
                            "GRMBG_Normal", 12, 14, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                        local txt, col = modeLabel(spec or inheritedSpec)
                        local suffix = spec and "" or (inheritedSpec and "  (наследуется)" or "")
                        draw.SimpleText(txt .. suffix, "GRMBG_Small", 12, 34, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    end

                    local function setSpec(newSpec)
                        draftGroups[key] = newSpec == nil and false or newSpec
                        spec = newSpec
                        applyPreviewRules()
                        rebuildGroups()
                    end

                    local x = 12
                    local function mkBtn(text, color, w, fn)
                        local b = button(row, text, color, w, 26)
                        b:SetPos(x, 44)
                        b.DoClick = fn
                        x = x + w + 6
                        return b
                    end

                    mkBtn("Доступно", C.green, 108, function() setSpec(nil) end)
                    mkBtn("Скрыть", C.red, 92, function()
                        local cur = (istable(spec) and tonumber(spec.value)) or 0
                        setSpec({ mode = "hide", value = math.Clamp(cur, 0, info.total - 1) })
                    end)
                    mkBtn("Закрепить", C.yellow, 108, function()
                        local cur = (istable(spec) and tonumber(spec.value)) or 0
                        setSpec({ mode = "lock", value = math.Clamp(cur, 0, info.total - 1) })
                    end)

                    if istable(spec) and (spec.mode == "hide" or spec.mode == "lock") then
                        local valLbl = vgui.Create("DLabel", row)
                        valLbl:SetPos(x, 44) valLbl:SetSize(96, 26)
                        valLbl:SetFont("GRMBG_Small") valLbl:SetTextColor(C.dim)
                        valLbl:SetText("значение: " .. tostring(spec.value or 0))
                        x = x + 100
                        local minus = button(row, "−", C.panel, 26, 26)
                        minus:SetPos(x, 44) x = x + 30
                        minus.DoClick = function()
                            local v = (tonumber(spec.value) or 0) - 1
                            if v < 0 then v = info.total - 1 end
                            setSpec({ mode = spec.mode, value = v })
                        end
                        local plus = button(row, "+", C.panel, 26, 26)
                        plus:SetPos(x, 44) x = x + 30
                        plus.DoClick = function()
                            local v = ((tonumber(spec.value) or 0) + 1) % info.total
                            setSpec({ mode = spec.mode, value = v })
                        end
                    end

                    if info.total > 1 then
                        local limitBtn = button(row, "Только выбранные значения", C.acc, 220, 26)
                        limitBtn:SetPos(x, 44)
                        limitBtn.DoClick = function()
                            local values = (istable(spec) and spec.mode == "limit" and table.Copy(spec.values or {})) or {}
                            local menu = DermaMenu()
                            for v = 0, info.total - 1 do
                                local on = table.HasValue(values, v)
                                local opt = menu:AddOption((on and "✔ " or "   ") .. "вариант " .. v, function()
                                    if on then table.RemoveByValue(values, v) else values[#values + 1] = v end
                                    table.sort(values)
                                    if #values == 0 then setSpec(nil) else setSpec({ mode = "limit", values = values }) end
                                end)
                                opt:SetFont("GRMBG_Small")
                            end
                            menu:Open()
                        end
                    end
                end
            end
        end

        rebuildModels = function()
            modelList:Clear()
            local filter = low(search:GetValue() or "")
            local facRow
            for _, row in ipairs(factions) do
                if row.name == sel.faction then facRow = row break end
            end
            local shown = 0
            local function add(path, note, highlight)
                if filter ~= "" and not string.find(path, filter, 1, true) then return end
                shown = shown + 1
                local b = vgui.Create("DButton", modelList)
                b:SetText("") b:Dock(TOP) b:SetTall(30) b:DockMargin(0, 0, 4, 4)
                local short = string.match(path, "([^/]+)$") or path
                b.Paint = function(self, pw, ph)
                    local on = path == sel.model
                    draw.RoundedBox(4, 0, 0, pw, ph, on and Color(30, 52, 80) or (self:IsHovered() and C.panel2 or C.panel))
                    if on then
                        surface.SetDrawColor(C.acc) surface.DrawOutlinedRect(0, 0, pw, ph, 1)
                    end
                    draw.SimpleText(short, "GRMBG_Small", 8, 9, on and C.text or C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    draw.SimpleText(note or "", "GRMBG_Small", pw - 8, 9, highlight and C.yellow or C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                    draw.SimpleText(path, "GRMBG_Small", 8, 21, Color(95, 110, 130), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end
                b.DoClick = function() setModel(path) end
            end

            if facRow and #facRow.models > 0 then
                local listed = {}
                for _, path in ipairs(facRow.models) do
                    listed[path] = true
                    add(path, BG.HasAnyRule(path) and "правила" or "", BG.HasAnyRule(path))
                end
                --[[ Модель убрали из организации, а правило для неё осталось.
                     Показываем её здесь же, иначе снять правило можно было бы
                     только через «Все организации» — и админ его не находил. ]]
                local orphan = {}
                for key in pairs(BG.Rules or {}) do
                    local parts = string.Explode("|", key)
                    local path, fac = tostring(parts[1] or ""), tostring(parts[2] or "")
                    if path ~= "" and not listed[path] and fac == sel.faction and not orphan[path] then
                        orphan[path] = true
                        add(path, "правило вне списка", true)
                    end
                end
            else
                for _, row in ipairs(models) do
                    add(row.path, BG.HasAnyRule(row.path) and "правила" or (row.owners[1] or ""), BG.HasAnyRule(row.path))
                end
            end
            if shown == 0 then
                local l = vgui.Create("DLabel", modelList)
                l:Dock(TOP) l:SetTall(22) l:SetFont("GRMBG_Small") l:SetTextColor(C.dim)
                l:SetText("Моделей не найдено.")
            end
        end

        local function fillDeptRole()
            deptCombo:Clear()
            roleCombo:Clear()
            posCombo:Clear()
            deptCombo:AddChoice("Все отделы и подотделы", "", sel.dept == "")
            roleCombo:AddChoice("Все звания", "", sel.role == "")
            posCombo:AddChoice("Все должности", "", sel.position == "")
            for _, row in ipairs(factions) do
                if row.name == sel.faction then
                    for _, d in ipairs(row.depts) do
                        deptCombo:AddChoice((d.sub and "подотдел: " or "отдел: ") .. d.display, d.key, sel.dept == d.key)
                    end
                    for _, r in ipairs(row.roles) do
                        roleCombo:AddChoice(r.display, r.key, sel.role == r.key)
                    end
                    for _, pos in ipairs(row.positions or {}) do
                        posCombo:AddChoice(pos.display, pos.key, sel.position == pos.key)
                    end
                end
            end
            if sel.faction == "" then
                deptCombo:SetValue("Все отделы и подотделы")
                roleCombo:SetValue("Все звания")
                posCombo:SetValue("Все должности")
            end
        end

        facCombo:AddChoice("Все организации (общее правило модели)", "", true)
        for _, row in ipairs(factions) do
            facCombo:AddChoice(row.display, row.name, false)
        end
        facCombo.OnSelect = function(_, _, _, data)
            sel.faction = tostring(data or "")
            sel.dept, sel.role, sel.position = "", "", ""
            fillDeptRole()
            draftGroups = {}
            rebuildModels()
            rebuildGroups()
        end
        deptCombo.OnSelect = function(_, _, _, data)
            sel.dept = tostring(data or "")
            draftGroups = {}
            rebuildGroups()
        end
        roleCombo.OnSelect = function(_, _, _, data)
            sel.role = tostring(data or "")
            draftGroups = {}
            rebuildGroups()
        end
        posCombo.OnSelect = function(_, _, _, data)
            sel.position = tostring(data or "")
            draftGroups = {}
            rebuildGroups()
        end
        search.OnChange = function() rebuildModels() end

        saveBtn.DoClick = function()
            if sel.model == "" then
                notification.AddLegacy("Сначала выберите модель", NOTIFY_ERROR, 4)
                return
            end
            -- Сохраняем ТОЛЬКО собственные настройки области: уже
            -- записанные плюс правки. false стирает строку.
            local own = table.Copy(BG.Rules[currentKey()] or {})
            for key, spec in pairs(draftGroups) do
                if spec == false then own[key] = nil else own[key] = spec end
            end
            net.Start(NET_ACT)
                net.WriteTable({ action = "save", model = sel.model, faction = sel.faction,
                    dept = sel.dept, role = sel.role, position = sel.position, groups = own })
            net.SendToServer()
            draftGroups = {}
        end

        clearBtn.DoClick = function()
            if sel.model == "" then return end
            net.Start(NET_ACT) net.WriteTable({ action = "delete", key = currentKey() }) net.SendToServer()
            draftGroups = {}
        end

        fillDeptRole()
        rebuildModels()
        rebuildGroups()
        rebuildSaved()

        --[[ ФОКУС из models_admin: сразу встаём на нужную модель и область,
             чтобы админ не искал их руками и не видел «пустоту». ]]
        local focus = istable(snapshot.focus) and snapshot.focus or nil
        if focus then
            if focus.faction ~= "" then
                sel.faction = focus.faction
                for _, row in ipairs(factions) do
                    if row.name == focus.faction then facCombo:SetValue(row.display) break end
                end
            end
            sel.dept = focus.dept or ""
            sel.role = focus.role or ""
            sel.position = focus.position or ""
            fillDeptRole()
            -- Подписи комбобоксов под выбранную область.
            for _, row in ipairs(factions) do
                if row.name == sel.faction then
                    for _, d in ipairs(row.depts) do
                        if d.key == sel.dept then
                            deptCombo:SetValue((d.sub and "подотдел: " or "отдел: ") .. d.display)
                        end
                    end
                    for _, r in ipairs(row.roles) do
                        if r.key == sel.role then roleCombo:SetValue(r.display) end
                    end
                    for _, pos in ipairs(row.positions or {}) do
                        if pos.key == sel.position then posCombo:SetValue(pos.display) end
                    end
                end
            end
            rebuildModels()
            if focus.model ~= "" then
                setModel(focus.model)
            else
                rebuildGroups()
            end
        end

        f._grmRestore = function()
            return { faction = sel.faction, dept = sel.dept, role = sel.role,
                position = sel.position, model = sel.model }
        end

        --[[ Точечное обновление после ответа сервера: перерисовываем только
             списки, выбранная область и модель остаются на месте. Именно это
             заменило пересоздание окна после каждой правки. ]]
        BG._editorRefresh = function()
            if not IsValid(f) then BG._editorRefresh = nil return end
            draftGroups = {}
            rebuildSaved()
            rebuildModels()
            applyPreviewRules()
            rebuildGroups()
        end
        --[[ GRM.UI.Track тоже вешает OnRemove (снимает окно с учёта живых
             окон). Затирать его нельзя — цепляемся следом за ним. ]]
        local prevOnRemove = f.OnRemove
        f.OnRemove = function(self)
            if prevOnRemove then pcall(prevOnRemove, self) end
            BG._editorRefresh = nil
            if editor == self then editor = nil end
        end
    end

    net.Receive(NET_OPEN, function()
        local rawLen = net.ReadUInt(32)
        local len = net.ReadUInt(32)
        local data = net.ReadData(len)
        local txt = util.Decompress(data, rawLen + 64) or ""
        local ok, snapshot = pcall(util.JSONToTable, txt, false, true)
        if not ok or not istable(snapshot) then
            notification.AddLegacy("Не удалось прочитать снимок правил", NOTIFY_ERROR, 5)
            return
        end
        -- Перед пересозданием запоминаем выбор, чтобы после сохранения
        -- редактор открылся там же, где админ работал.
        local restore = IsValid(editor) and editor._grmRestore and editor._grmRestore() or nil
        openEditor(snapshot)
        if restore and IsValid(editor) then
            -- Возврат к прежней модели/области делается мягко: только модель,
            -- остальное админ видит в комбобоксах.
            hook.Run("GRM_BodygroupEditorRestored", restore)
        end
    end)

    --- focus необязателен: без него редактор открывается как раньше.
    function BG.Request(focus)
        net.Start(NET_REQ)
            net.WriteTable(istable(focus) and focus or {})
        net.SendToServer()
    end

    concommand.Add("grm_bodygroups_admin", function() BG.Request() end)

    hook.Add("PlayerSayTransform", "GRM_BGRules_Cmd", function(_, datapack)
        if not istable(datapack) then return end
        local msg = datapack[1]
        if not isstring(msg) then return end
        local cmd = string.lower(string.Trim(msg))
        if cmd == "/bodygroups_admin" or cmd == "!bodygroups_admin" or cmd == "/бодигруппы" then
            BG.Request()
            datapack[1] = ""
            datapack.SkipPlayerSay = true
            return false
        end
    end)
end
