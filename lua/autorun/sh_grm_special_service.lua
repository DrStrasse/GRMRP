-- Boot-шим: старт подсистемы идёт через планировщик GRM.Boot (приоритеты и
-- бюджет на тик). Если планировщик почему-то не загружен, работаем по-старому.
local function grmBootStart(id, tier, fn)
    if GRM and GRM.Boot and GRM.Boot.OnMapStart then return GRM.Boot.OnMapStart(id, tier, fn) end
    return hook.Add("InitPostEntity", id, fn)
end

--[[--------------------------------------------------------------------
    GRM Special Service v1.0.0 — спецслужбы (Гестапо, Комитет).

    Требование: спецслужбы контролируют ВСЕ базы данных, имеют несколько
    документов прикрытия и могут ТАЙНО вносить изменения и удалять записи
    из баз розыска, штрафов и арестов.

    Что даёт модуль:
      1. Реестр агентов: фракции, отделы, должности и персональные ключи
         (data/grm_wanted/special.json). Настраивается суперадмином.
      2. Полный доступ: агент видит обе юрисдикции розыска, весь реестр
         штрафов, журнал арестов и обмен сведениями.
      3. Тайные операции — правки без следа в обычной истории:
           • covert_wanted_set / covert_wanted_wipe — правка и удаление
             записей розыска;
           • covert_charge_remove — удаление отдельной статьи;
           • covert_fine_wipe — удаление штрафа из реестра;
           • covert_hide — пометка записи «скрыта» (covert): она исчезает
             из терминалов, листа розыска и ориентировок.
         Все операции пишутся в ЗАКРЫТЫЙ журнал спецслужбы, который виден
         только агентам и суперадмину — обычная история розыска о них
         не знает, а ориентировки не рассылаются.
      4. Документы прикрытия: несколько легенд на персонажа, переключение
         активной, выдача и аннулирование. Опирается на существующий
         DOC.Registry.coverBadges и расширяет его массивом легенд.

    Данные:
      data/grm_wanted/special.json
        { version = 1,
          agents  = { Factions = {}, Departments = {}, Roles = {}, Steam = {} },
          journal = { {t, actor, actorName, op, target, detail} },
          covers  = { [charKey] = { active = n, list = { {...legend} } } } }

    Миграция: файла может не быть — создаётся пустой. Существующие
    coverBadges НЕ трогаются: при первом обращении легенда из
    DOC.Registry.coverBadges импортируется в список как легенда №1.
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.SpecialService = GRM.SpecialService or {}

local SS = GRM.SpecialService
SS.Version = "1.0.0"

local NET_OPEN   = "GRM_SpecService_Open"
local NET_DATA   = "GRM_SpecService_Data"
local NET_ACT    = "GRM_SpecService_Act"
local NET_RESULT = "GRM_SpecService_Result"

local DIR  = "grm_wanted"
local FILE = "grm_wanted/special.json"

SS.Config = SS.Config or {
    MaxJournal   = 500,
    MaxCovers    = 5,      -- документов прикрытия на персонажа
    MaxRowsSent  = 150,
    Cooldown     = 0.4,
    -- фолбэк-эвристика: фракции, чьё название содержит эти подстроки,
    -- считаются спецслужбой, даже если реестр ещё не настроен
    Patterns = {
        "gestapo", "гестапо", "geheime", "sicherheitsdienst",
        "комитет", "komitet", "abwehr", "абвер", "контрразвед",
        "спецслужб", "тайная полиция",
    },
}

-----------------------------------------------------------------------
-- Общие хелперы
-----------------------------------------------------------------------
local function charKey(v)
    if IsValid(v) and v:IsPlayer() then
        if GRM.Identity and isfunction(GRM.Identity.CharacterKey) then
            return GRM.Identity.CharacterKey(v)
        end
        return tostring(v:SteamID64()) .. ":char1"
    end
    local s = tostring(v or "")
    if s:match(":char[1-3]$") then return s end
    if s:match("^%d+$") then return s .. ":char1" end
    return s
end
SS.CharKey = charKey

-- Статусы оперативных дел нужны обеим сторонам: сервер валидирует,
-- клиент рисует выпадающий список в редакторе дела.
SS.CaseStatuses = {
    { id = "open",      name = "В работе" },
    { id = "watch",     name = "Наблюдение" },
    { id = "suspended", name = "Приостановлено" },
    { id = "closed",    name = "Закрыто" },
    { id = "archived",  name = "В архиве" },
}

function SS.CaseStatusName(id)
    for _, s in ipairs(SS.CaseStatuses) do if s.id == id then return s.name end end
    return "В работе"
end

if SERVER then
    for _, n in ipairs({ NET_OPEN, NET_DATA, NET_ACT, NET_RESULT }) do util.AddNetworkString(n) end

    SS.Data = SS.Data or nil

    local function ensure()
        if not file.IsDir(DIR, "DATA") then file.CreateDir(DIR) end
    end

    local function jsonT(txt)
        local ok, t = pcall(util.JSONToTable, txt or "", false, true)
        return (ok and istable(t)) and t or nil
    end

    local function write(path, data)
        local ok, s = pcall(util.TableToJSON, data, true)
        if not ok or not isstring(s) then
            ErrorNoHalt("[GRM SpecService] сериализация не удалась: " .. tostring(path) .. "\n")
            return false
        end
        file.Write(path, s)
        return file.Read(path, "DATA") == s
    end

    local function normalize(d)
        d = istable(d) and d or {}
        d.agents = istable(d.agents) and d.agents or {}
        local a = d.agents
        a.Factions    = istable(a.Factions) and a.Factions or {}
        a.Departments = istable(a.Departments) and a.Departments or {}
        a.Roles       = istable(a.Roles) and a.Roles or {}
        a.Steam       = istable(a.Steam) and a.Steam or {}
        d.journal = istable(d.journal) and d.journal or {}
        d.covers  = istable(d.covers) and d.covers or {}
        -- Оперативные дела. Ключ — CharacterKey субъекта учёта.
        -- Появились позже covers/journal: у старых файлов поля нет,
        -- поэтому просто создаём пустое — миграция без потери данных.
        d.cases   = istable(d.cases) and d.cases or {}
        for key, c in pairs(d.cases) do
            if istable(c) then
                c.key     = c.key or key
                c.name    = tostring(c.name or "")
                c.status  = tostring(c.status or "open")
                c.threat  = math.Clamp(math.floor(tonumber(c.threat) or 0), 0, 5)
                c.summary = tostring(c.summary or "")
                c.notes   = istable(c.notes) and c.notes or {}
                c.created = tonumber(c.created) or os.time()
                c.updated = tonumber(c.updated) or c.created
            else
                d.cases[key] = nil
            end
        end
        return d
    end

    function SS.Load()
        ensure()
        local raw = file.Exists(FILE, "DATA") and file.Read(FILE, "DATA") or nil
        local t = raw and jsonT(raw)
        if raw and not t then
            local bak = FILE .. ".corrupt." .. os.time()
            file.Write(bak, raw)
            ErrorNoHalt("[GRM SpecService] special.json повреждён, копия: " .. bak .. "\n")
        end
        SS.Data = normalize(t)
        return SS.Data
    end

    function SS.Save()
        ensure()
        local d = normalize(SS.Data)
        while #d.journal > (SS.Config.MaxJournal or 500) do table.remove(d.journal, 1) end
        SS.Data = d
        return write(FILE, {
            version = 2, agents = d.agents, journal = d.journal, covers = d.covers,
            cases = d.cases,
        })
    end

    local function data()
        if not SS.Data then SS.Load() end
        return normalize(SS.Data)
    end
    SS.Get = data

    -------------------------------------------------------------------
    -- Определение агента
    -------------------------------------------------------------------
    local function nested(t, faction, key)
        if not (istable(t) and key and key ~= "") then return false end
        return istable(t[faction]) and t[faction][key] == true
    end

    --- Является ли игрок сотрудником спецслужбы.
    function SS.IsAgent(ply)
        if not (IsValid(ply) and ply:IsPlayer()) then return false end
        if ply:IsSuperAdmin() then return true end

        local d = data()
        local key   = charKey(ply)
        local sid64 = ply:SteamID64() or ""
        local sid   = ply:SteamID() or ""
        local st = d.agents.Steam
        if st[key] == true or st[sid64] == true or st[sid] == true then return true end

        local fName = ply:GetNWString("GRM_Faction", "")
        if fName == "" then return false end
        if d.agents.Factions[fName] == true then return true end
        if nested(d.agents.Departments, fName, ply:GetNWString("GRM_Department", "")) then return true end
        if nested(d.agents.Roles, fName, ply:GetNWString("GRM_Role", "")) then return true end

        -- фолбэк по названию фракции: реестр может быть ещё не заполнен
        local low = string.lower(fName)
        for _, pat in ipairs(SS.Config.Patterns or {}) do
            if string.find(low, pat, 1, true) then return true end
        end
        return false
    end

    --- Спецслужба видит обе юрисдикции.
    function SS.JurisdictionOf(ply)
        return SS.IsAgent(ply) and "all" or nil
    end

    -------------------------------------------------------------------
    -- Закрытый журнал
    -------------------------------------------------------------------
    --- Запись в журнал спецслужбы. В обычную историю розыска не попадает.
    function SS.Note(actor, op, target, detail)
        local d = data()
        d.journal[#d.journal + 1] = {
            t         = os.time(),
            actor     = IsValid(actor) and charKey(actor) or "system",
            actorName = IsValid(actor) and actor:Nick() or "Система",
            op        = tostring(op or "?"):sub(1, 32),
            target    = charKey(target),
            detail    = tostring(detail or ""):sub(1, 200),
        }
        while #d.journal > (SS.Config.MaxJournal or 500) do table.remove(d.journal, 1) end
        SS.Data = d
    end

    -------------------------------------------------------------------
    -- Тайные операции с базой розыска
    -------------------------------------------------------------------
    local function records()
        local W = GRM.Wanted
        return (W and istable(W.Records)) and W.Records or nil
    end

    local function saveWanted()
        local W = GRM.Wanted
        if W and isfunction(W.Save) then return W.Save() end
        return false
    end

    --- Тайно изменить уровень розыска. История розыска не пишется,
    -- ориентировка не рассылается — только закрытый журнал.
    function SS.CovertSetLevel(actor, key, level, note)
        if not SS.IsAgent(actor) then return false, "Доступ только для спецслужбы" end
        local R = records()
        if not R then return false, "Модуль розыска недоступен" end
        key = charKey(key)
        local rec = R[key]
        if not rec then return false, "Запись не найдена" end

        local W = GRM.Wanted
        local old = tonumber(rec.level) or 0
        level = isfunction(W.ClampLevel) and W.ClampLevel(level) or math.Clamp(math.floor(tonumber(level) or 0), 0, 5)
        rec.level = level
        rec.updated = os.time()
        if level == 0 then rec.reasons = {} end
        saveWanted()

        -- Обновляем сетевые переменные цели без чат-уведомления.
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(p) and charKey(p) == key then
                p:SetNW2Int("GRM_WantedLevel", level)
                p:SetNWInt("GRM_WantedLevel", level)
                p:SetNWBool("GRM_Wanted", level > 0)
                break
            end
        end

        SS.Note(actor, "wanted_level", key, ("%d → %d %s"):format(old, level, tostring(note or "")))
        SS.Save()
        return true, ("Уровень изменён скрытно: %d → %d"):format(old, level)
    end

    --- Тайно удалить статью из дела.
    function SS.CovertRemoveCharge(actor, key, index, note)
        if not SS.IsAgent(actor) then return false, "Доступ только для спецслужбы" end
        local R = records()
        if not R then return false, "Модуль розыска недоступен" end
        key = charKey(key)
        local rec = R[key]
        if not rec then return false, "Запись не найдена" end
        index = math.floor(tonumber(index) or 0)
        local c = istable(rec.reasons) and rec.reasons[index]
        if not c then return false, "Статья не найдена" end

        table.remove(rec.reasons, index)
        local maxLevel = 0
        for _, r in ipairs(rec.reasons) do maxLevel = math.max(maxLevel, tonumber(r.level) or 0) end
        rec.level = maxLevel
        rec.updated = os.time()
        saveWanted()

        SS.Note(actor, "charge_remove", key, tostring(c.code or "") .. " " .. tostring(c.title or "") .. " " .. tostring(note or ""))
        SS.Save()
        return true, ("Статья «%s» удалена без следа"):format(tostring(c.title or "?"))
    end

    --- Полное удаление дела из базы розыска.
    function SS.CovertWipe(actor, key, note)
        if not SS.IsAgent(actor) then return false, "Доступ только для спецслужбы" end
        local R = records()
        if not R then return false, "Модуль розыска недоступен" end
        key = charKey(key)
        local rec = R[key]
        if not rec then return false, "Запись не найдена" end

        local name = tostring(rec.name or key)
        R[key] = nil
        saveWanted()

        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(p) and charKey(p) == key then
                p:SetNW2Int("GRM_WantedLevel", 0)
                p:SetNWInt("GRM_WantedLevel", 0)
                p:SetNWBool("GRM_Wanted", false)
                break
            end
        end

        SS.Note(actor, "wanted_wipe", key, name .. " " .. tostring(note or ""))
        SS.Save()
        return true, ("Дело «%s» изъято из базы"):format(name)
    end

    --- Скрыть/раскрыть дело: скрытое не видно ни терминалам, ни листу
    -- розыска, ни ориентировкам — только спецслужбе.
    function SS.CovertHide(actor, key, hidden, note)
        if not SS.IsAgent(actor) then return false, "Доступ только для спецслужбы" end
        local R = records()
        if not R then return false, "Модуль розыска недоступен" end
        key = charKey(key)
        local rec = R[key]
        if not rec then return false, "Запись не найдена" end

        rec.covert = hidden and true or nil
        rec.updated = os.time()
        saveWanted()
        SS.Note(actor, hidden and "hide" or "unhide", key, tostring(note or ""))
        SS.Save()
        return true, hidden and "Дело скрыто от ведомств" or "Дело возвращено в общий доступ"
    end

    --- Тайно удалить штраф из реестра.
    function SS.CovertWipeFine(actor, id, note)
        if not SS.IsAgent(actor) then return false, "Доступ только для спецслужбы" end
        local F = GRM.Wanted and GRM.Wanted.Fines
        if not (F and istable(F.List)) then return false, "Реестр штрафов недоступен" end
        id = math.floor(tonumber(id) or 0)
        for i, rec in ipairs(F.List) do
            if rec.id == id then
                table.remove(F.List, i)
                if isfunction(F.Save) then F.Save() end
                SS.Note(actor, "fine_wipe", rec.target, ("№%d %s %s"):format(id, tostring(rec.reason or ""), tostring(note or "")))
                SS.Save()
                return true, ("Штраф №%d изъят из реестра"):format(id)
            end
        end
        return false, "Штраф не найден"
    end

    --- Тайно освободить арестованного (снятие ареста без записи в
    -- обычный журнал арестов).
    function SS.CovertRelease(actor, targetName)
        if not SS.IsAgent(actor) then return false, "Доступ только для спецслужбы" end
        local A = GRM.Arrest
        -- В модуле арестов освобождение называется UnarrestPlayer.
        local release = A and (A.UnarrestPlayer or A.Release)
        if not isfunction(release) then return false, "Модуль арестов недоступен" end

        local low = string.lower(tostring(targetName or ""))
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(p) and p:GetNWBool("GRM_Arrested", false)
                and (charKey(p) == targetName or string.find(string.lower(p:Nick()), low, 1, true)) then
                local ok = release(actor, p)
                SS.Note(actor, "release", charKey(p), p:Nick())
                SS.Save()
                return ok and true or false, ok and ("Освобождён: " .. p:Nick()) or "Освободить не удалось"
            end
        end
        return false, "Арестованный не найден"
    end

    -------------------------------------------------------------------
    -- Документы прикрытия (несколько легенд на персонажа)
    -------------------------------------------------------------------
    local function coversOf(key)
        local d = data()
        key = charKey(key)
        local entry = d.covers[key]
        if not istable(entry) then
            entry = { active = 0, list = {} }
            -- импорт единственной существующей легенды из старого реестра
            local DOC = GRM.Documents
            local old = DOC and DOC.Registry and DOC.Registry.coverBadges and DOC.Registry.coverBadges[key]
            if istable(old) then
                entry.list[1] = table.Copy(old)
                entry.list[1].label = entry.list[1].label or "Легенда №1"
                entry.active = 1
            end
            d.covers[key] = entry
        end
        entry.list = istable(entry.list) and entry.list or {}
        entry.active = math.floor(tonumber(entry.active) or 0)
        return entry
    end
    SS.CoversOf = coversOf

    --- Список легенд персонажа (для UI).
    -------------------------------------------------------------------
    -- ОПЕРАТИВНЫЕ ДЕЛА
    --
    -- Сотрудник ведёт дело на субъекта учёта: краткая фабула, уровень
    -- угрозы, статус и хронологические пометки. Дело хранится в общей
    -- базе спецслужбы (special.json) — то есть видно всем агентам,
    -- а не только автору, и переживает перезаход.
    -------------------------------------------------------------------
    local function subjectName(key)
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(p) and charKey(p) == key then
                local rp = p:GetNWString("GRM_RPName", "")
                if rp ~= "" then return rp end
                return p:Nick()
            end
        end
        local reg = GRM.Documents and GRM.Documents.Registry
        local pass = reg and reg.passports and reg.passports[key]
        if istable(pass) and isstring(pass.fullName) and pass.fullName ~= "" then
            return pass.fullName
        end
        if GRM.Services and isfunction(GRM.Services.CharacterName) then
            return GRM.Services.CharacterName(key)
        end
        return key
    end
    SS.SubjectName = subjectName

    --- Получить дело (создав пустое при необходимости).
    function SS.CaseOf(key)
        key = charKey(key)
        if key == "" then return nil end
        local d = data()
        local c = d.cases[key]
        if not istable(c) then
            c = {
                key = key, name = subjectName(key), status = "open", threat = 0,
                summary = "", notes = {}, created = os.time(), updated = os.time(),
            }
            d.cases[key] = c
        end
        return c
    end

    --- Сохранить фабулу/статус/угрозу.
    function SS.CaseSave(actor, key, fields)
        if not SS.IsAgent(actor) then return false, "Доступ запрещён" end
        key = charKey(key)
        if key == "" then return false, "Не указан субъект" end
        fields = istable(fields) and fields or {}

        local c = SS.CaseOf(key)
        if not c then return false, "Дело не создано" end

        if isstring(fields.summary) then c.summary = string.sub(fields.summary, 1, 4000) end
        if isstring(fields.status) then
            for _, s in ipairs(SS.CaseStatuses) do
                if s.id == fields.status then c.status = s.id break end
            end
        end
        if fields.threat ~= nil then
            c.threat = math.Clamp(math.floor(tonumber(fields.threat) or 0), 0, 5)
        end
        c.name = subjectName(key)
        c.updated = os.time()

        SS.Note(actor, "case_save", key, "дело обновлено: " .. SS.CaseStatusName(c.status))
        if not SS.Save() then return false, "Не удалось записать базу" end
        hook.Run("GRM_SS_CaseSaved", key, c, actor)
        return true, "Дело сохранено в базе спецслужбы"
    end

    --- Добавить пометку в дело.
    function SS.CaseAddNote(actor, key, text)
        if not SS.IsAgent(actor) then return false, "Доступ запрещён" end
        key = charKey(key)
        if key == "" then return false, "Не указан субъект" end
        text = string.Trim(tostring(text or ""))
        if text == "" then return false, "Пустая пометка" end

        local c = SS.CaseOf(key)
        if not c then return false, "Дело не создано" end

        local name = IsValid(actor) and (actor:GetNWString("GRM_RPName", "") ~= ""
            and actor:GetNWString("GRM_RPName", "") or actor:Nick()) or "СИСТЕМА"

        c.notes[#c.notes + 1] = {
            t = os.time(), author = charKey(actor), authorName = name,
            text = string.sub(text, 1, 1000),
        }
        while #c.notes > 200 do table.remove(c.notes, 1) end
        c.updated = os.time()

        SS.Note(actor, "case_note", key, string.sub(text, 1, 120))
        if not SS.Save() then return false, "Не удалось записать базу" end
        hook.Run("GRM_SS_CaseNoteAdded", key, c, actor)
        return true, "Пометка внесена в дело"
    end

    --- Удалить пометку (только суперадмин: чистка ошибочных записей).
    function SS.CaseRemoveNote(actor, key, index)
        if not (IsValid(actor) and actor:IsSuperAdmin()) then
            return false, "Удалять пометки может только суперадмин"
        end
        key = charKey(key)
        local d = data()
        local c = d.cases[key]
        if not istable(c) then return false, "Дело не найдено" end
        index = math.floor(tonumber(index) or 0)
        if not c.notes[index] then return false, "Пометка не найдена" end

        table.remove(c.notes, index)
        c.updated = os.time()
        SS.Note(actor, "case_note_del", key, "удалена пометка №" .. index)
        if not SS.Save() then return false, "Не удалось записать базу" end
        return true, "Пометка удалена"
    end

    --- Удалить дело целиком (суперадмин).
    function SS.CaseDelete(actor, key)
        if not (IsValid(actor) and actor:IsSuperAdmin()) then
            return false, "Удалять дело может только суперадмин"
        end
        key = charKey(key)
        local d = data()
        if not istable(d.cases[key]) then return false, "Дело не найдено" end
        d.cases[key] = nil
        SS.Note(actor, "case_delete", key, "дело удалено")
        if not SS.Save() then return false, "Не удалось записать базу" end
        return true, "Дело удалено из базы"
    end

    --- Срез дел для терминалов (без полного текста пометок).
    function SS.CaseRows(limit)
        limit = math.floor(tonumber(limit) or (SS.Config.MaxRowsSent or 150))
        local d = data()
        local out = {}
        for key, c in pairs(d.cases) do
            if istable(c) then
                out[#out + 1] = {
                    key = key, name = c.name, status = c.status,
                    statusName = SS.CaseStatusName(c.status),
                    threat = c.threat, summary = c.summary,
                    notes = c.notes, updated = c.updated, created = c.created,
                }
                if #out >= limit then break end
            end
        end
        table.sort(out, function(a, b) return (a.updated or 0) > (b.updated or 0) end)
        return out
    end

    function SS.ListCovers(key)
        local entry = coversOf(key)
        local out = {}
        for i, c in ipairs(entry.list) do
            out[#out + 1] = {
                index    = i,
                label    = tostring(c.label or ("Легенда №" .. i)),
                fullName = tostring(c.fullName or "?"),
                faction  = tostring(c.faction or ""),
                role     = tostring(c.role or ""),
                number   = tostring(c.number or ""),
                status   = tostring(c.status or "Действителен"),
                coverColor = istable(c.coverColor) and table.Copy(c.coverColor) or nil,
                foilStyle = tostring(c.foilStyle or "gold"),
                active   = (entry.active == i),
            }
        end
        return out
    end

    --- Оформить новую легенду. Доступно агентам и тем фракциям, которым
    -- разрешены документы прикрытия в шаблонах документов.
    function SS.IssueCover(actor, targetKey, legend)
        if not SS.IsAgent(actor) then
            local DOC = GRM.Documents
            local myFac = IsValid(actor) and actor:GetNWString("GRM_Faction", "") or ""
            local allowed = DOC and DOC.Templates and DOC.Templates.access
                and istable(DOC.Templates.access.coverDocs) and DOC.Templates.access.coverDocs[myFac] == true
            if not allowed then return false, "Нет допуска к документам прикрытия" end
        end

        targetKey = charKey(targetKey)
        if targetKey == "" then return false, "Не указан персонаж" end
        legend = istable(legend) and legend or {}

        local entry = coversOf(targetKey)
        if #entry.list >= (SS.Config.MaxCovers or 5) then
            return false, ("Достигнут предел легенд (%d)"):format(SS.Config.MaxCovers or 5)
        end

        local rec = {
            label       = tostring(legend.label or ("Легенда №" .. (#entry.list + 1))):sub(1, 48),
            fullName    = tostring(legend.fullName or "Без имени"):sub(1, 64),
            faction     = tostring(legend.faction or ""):sub(1, 64),
            role        = tostring(legend.role or ""):sub(1, 64),
            department  = tostring(legend.department or ""):sub(1, 64),
            number      = tostring(legend.number or ""):sub(1, 32),
            permissions = istable(legend.permissions) and table.Copy(legend.permissions) or { weapon = true, transport = true },
            issuedBy    = tostring(legend.issuedBy or "Оперативное управление"):sub(1, 96),
            issueDate   = os.date("%d.%m.%Y"),
            validUntil  = tostring(legend.validUntil or "Бессрочно"):sub(1, 32),
            status      = "Действителен",
            coverColor  = istable(legend.coverColor) and {r=math.Clamp(tonumber(legend.coverColor.r) or 30,0,255),g=math.Clamp(tonumber(legend.coverColor.g) or 35,0,255),b=math.Clamp(tonumber(legend.coverColor.b) or 45,0,255)} or nil,
            foilStyle   = ({gold=true,silver=true,bronze=true,white=true})[tostring(legend.foilStyle or "gold")] and tostring(legend.foilStyle or "gold") or "gold",
            isCover     = true,
            created     = os.time(),
            updated     = os.time(),
        }
        entry.list[#entry.list + 1] = rec
        if entry.active == 0 then entry.active = #entry.list end

        SS.ApplyActiveCover(targetKey)
        SS.Note(actor, "cover_issue", targetKey, rec.label .. " / " .. rec.fullName)
        SS.Save()
        return true, ("Легенда «%s» оформлена"):format(rec.label)
    end

    --- Переключить активную легенду (0 = показывать настоящий документ).
    function SS.SetActiveCover(actor, targetKey, index)
        if not SS.IsAgent(actor) then return false, "Доступ только для спецслужбы" end
        targetKey = charKey(targetKey)
        local entry = coversOf(targetKey)
        index = math.floor(tonumber(index) or 0)
        if index < 0 or index > #entry.list then return false, "Легенда не найдена" end
        entry.active = index
        SS.ApplyActiveCover(targetKey)
        SS.Note(actor, "cover_switch", targetKey, "активна №" .. index)
        SS.Save()
        return true, index == 0 and "Работа под настоящим документом" or ("Активна легенда №" .. index)
    end

    --- Аннулировать легенду.
    function SS.RevokeCover(actor, targetKey, index)
        if not SS.IsAgent(actor) then return false, "Доступ только для спецслужбы" end
        targetKey = charKey(targetKey)
        local entry = coversOf(targetKey)
        index = math.floor(tonumber(index) or 0)
        local c = entry.list[index]
        if not c then return false, "Легенда не найдена" end
        table.remove(entry.list, index)
        if entry.active == index then entry.active = 0
        elseif entry.active > index then entry.active = entry.active - 1 end
        SS.ApplyActiveCover(targetKey)
        SS.Note(actor, "cover_revoke", targetKey, tostring(c.label or index))
        SS.Save()
        return true, ("Легенда «%s» аннулирована"):format(tostring(c.label or index))
    end

    --- Синхронизация с реестром документов: активная легенда кладётся в
    -- DOC.Registry.coverBadges, чтобы существующий показ документов
    -- («предъявить удостоверение») работал без изменений.
    function SS.ApplyActiveCover(targetKey)
        local DOC = GRM.Documents
        if not (DOC and istable(DOC.Registry)) then return false end
        targetKey = charKey(targetKey)
        DOC.Registry.coverBadges = DOC.Registry.coverBadges or {}

        local entry = coversOf(targetKey)
        local active = entry.list[entry.active]
        if istable(active) then
            local copy = table.Copy(active)
            copy.status = "Действителен"
            copy.isCover = true
            DOC.Registry.coverBadges[targetKey] = copy
        else
            DOC.Registry.coverBadges[targetKey] = nil
        end
        if isfunction(DOC.SaveRegistry) then DOC.SaveRegistry("special service cover " .. targetKey) end
        return true
    end

    -------------------------------------------------------------------
    -- Сбор данных для клиента
    -------------------------------------------------------------------
    --- Безопасный подсчёт долга: реестра штрафов может не быть вовсе.
    local function debtOf(F, key)
        if not (F and isfunction(F.DebtOf)) then return 0 end
        local ok, res = pcall(F.DebtOf, key)
        return (ok and tonumber(res)) or 0
    end

    local function wantedRows()
        local R = records()
        local out = {}
        if not R then return out end
        local F = GRM.Wanted and GRM.Wanted.Fines
        for k, r in pairs(R) do
            if istable(r) then
                out[#out + 1] = {
                    key          = k,
                    name         = tostring(r.name or "?"),
                    level        = tonumber(r.level) or 0,
                    jurisdiction = r.jurisdiction == "military" and "military" or "civil",
                    charges      = #(r.reasons or {}),
                    covert       = r.covert == true,
                    shared       = istable(r.shared) and (r.shared.civil and "civil" or r.shared.military and "military" or "") or "",
                    updated      = tonumber(r.updated) or 0,
                    debt         = debtOf(F, k),
                }
            end
        end
        table.sort(out, function(a, b)
            if a.level ~= b.level then return a.level > b.level end
            return a.updated > b.updated
        end)
        while #out > (SS.Config.MaxRowsSent or 150) do table.remove(out) end
        return out
    end

    local function fineRows()
        local F = GRM.Wanted and GRM.Wanted.Fines
        local out = {}
        if not (F and istable(F.List)) then return out end
        for i = #F.List, 1, -1 do
            local r = F.List[i]
            if istable(r) then
                out[#out + 1] = {
                    id = r.id, target = r.target, targetName = r.targetName,
                    issuerName = r.issuerName, amount = r.amount, paid = r.paid,
                    reason = r.reason, status = r.status, issued = r.issued,
                    jurisdiction = r.jurisdiction,
                }
            end
            if #out >= (SS.Config.MaxRowsSent or 150) then break end
        end
        return out
    end

    local function arrestRows()
        local out = {}
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(p) and p:GetNWBool("GRM_Arrested", false) then
                out[#out + 1] = {
                    key    = charKey(p),
                    name   = p:Nick(),
                    group  = p:GetNWString("GRM_ArrestGroupName", ""),
                    camera = p:GetNWString("GRM_ArrestCameraID", ""),
                }
            end
        end
        return out
    end

    local function journalRows()
        local d = data()
        local out = {}
        for i = #d.journal, math.max(1, #d.journal - 120), -1 do
            out[#out + 1] = d.journal[i]
        end
        return out
    end

    local function onlineRows()
        local out = {}
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(p) then
                local rp = p:GetNWString("GRM_RPName", "")
                out[#out + 1] = {
                    key     = charKey(p),
                    nick    = p:Nick(),
                    rpName  = rp ~= "" and rp or p:Nick(),
                    faction = p:GetNWString("GRM_Faction", ""),
                }
            end
        end
        table.sort(out, function(a, b) return a.rpName < b.rpName end)
        return out
    end

    function SS.Send(ply)
        if not SS.IsAgent(ply) then
            if GRM.Notify then GRM.Notify(ply, "Доступ запрещён.", 250, 110, 110) end
            return
        end
        net.Start(NET_DATA)
            net.WriteTable(wantedRows())
            net.WriteTable(fineRows())
            net.WriteTable(arrestRows())
            net.WriteTable(journalRows())
            net.WriteTable(onlineRows())
            net.WriteTable(SS.ListCovers(charKey(ply)))
            net.WriteTable(SS.CaseRows())
        net.Send(ply)
    end

    net.Receive(NET_OPEN, function(_, ply)
        if not (IsValid(ply) and ply:IsPlayer()) then return end
        ply.GRM_SSNext = ply.GRM_SSNext or 0
        if CurTime() < ply.GRM_SSNext then return end
        ply.GRM_SSNext = CurTime() + 1
        SS.Send(ply)
    end)

    local function result(ply, ok, msg)
        if not IsValid(ply) then return end
        net.Start(NET_RESULT)
            net.WriteBool(ok and true or false)
            net.WriteString(tostring(msg or ""))
        net.Send(ply)
    end

    net.Receive(NET_ACT, function(_, ply)
        if not (IsValid(ply) and ply:IsPlayer()) then return end
        ply.GRM_SSActNext = ply.GRM_SSActNext or 0
        if CurTime() < ply.GRM_SSActNext then return end
        ply.GRM_SSActNext = CurTime() + (SS.Config.Cooldown or 0.4)

        local act    = string.sub(net.ReadString(), 1, 32)
        local target = string.sub(net.ReadString(), 1, 64)
        local text   = string.sub(net.ReadString(), 1, 200)
        local num    = net.ReadInt(32)
        -- Пятое поле добавлено вместе с оперативными делами: длинная
        -- фабула не влезает в 200-символьный text. Пишется всегда,
        -- поэтому рассинхрона со старым клиентом быть не может.
        local extra  = net.ReadTable() or {}

        if not SS.IsAgent(ply) then return result(ply, false, "Доступ запрещён") end

        local ok, msg
        if act == "level" then
            ok, msg = SS.CovertSetLevel(ply, target, num, text)
        elseif act == "wipe" then
            ok, msg = SS.CovertWipe(ply, target, text)
        elseif act == "hide" then
            ok, msg = SS.CovertHide(ply, target, num ~= 0, text)
        elseif act == "charge_remove" then
            ok, msg = SS.CovertRemoveCharge(ply, target, num, text)
        elseif act == "fine_wipe" then
            ok, msg = SS.CovertWipeFine(ply, num, text)
        elseif act == "release" then
            ok, msg = SS.CovertRelease(ply, target)
        elseif act == "cover_issue" then
            ok, msg = SS.IssueCover(ply, target ~= "" and target or charKey(ply), {
                label = extra.label or text, fullName = extra.fullName or text,
                faction = extra.faction, role = extra.role, department = extra.department,
                number = extra.number, coverColor = extra.coverColor, foilStyle = extra.foilStyle,
            })
        elseif act == "cover_switch" then
            ok, msg = SS.SetActiveCover(ply, target ~= "" and target or charKey(ply), num)
        elseif act == "cover_revoke" then
            ok, msg = SS.RevokeCover(ply, target ~= "" and target or charKey(ply), num)
        elseif act == "case_save" then
            -- extra: { summary = ..., status = ..., threat = n }
            ok, msg = SS.CaseSave(ply, target, {
                summary = extra and extra.summary or text,
                status  = extra and extra.status or nil,
                threat  = extra and extra.threat or num,
            })
        elseif act == "case_note" then
            ok, msg = SS.CaseAddNote(ply, target, text)
        elseif act == "case_note_del" then
            ok, msg = SS.CaseRemoveNote(ply, target, num)
        elseif act == "case_delete" then
            ok, msg = SS.CaseDelete(ply, target)
        elseif act == "refresh" then
            SS.Send(ply)
            return
        else
            ok, msg = false, "Неизвестная операция"
        end

        result(ply, ok, msg)
        if ok then SS.Send(ply) end
    end)

    -------------------------------------------------------------------
    -- Установка расширенных прав: агент видит обе юрисдикции
    -------------------------------------------------------------------
    local function installJurisdictionHook()
        local W = GRM.Wanted
        if not (W and isfunction(W.CanUseJurisdiction)) then return end
        if W._SSPatched then return end
        local original = W.CanUseJurisdiction
        W.CanUseJurisdiction = function(ply, j)
            if SS.IsAgent(ply) then return j == "civil" or j == "military" end
            return original(ply, j)
        end
        -- CanView/CanEdit: агенту всегда «да».
        if isfunction(W.CanView) then
            local ov = W.CanView
            W.CanView = function(p) if SS.IsAgent(p) then return true end return ov(p) end
        end
        if isfunction(W.CanEdit) then
            local oe = W.CanEdit
            W.CanEdit = function(p) if SS.IsAgent(p) then return true end return oe(p) end
        end
        W._SSPatched = true
    end

    -- Менеджер доступов переустанавливает CanView/CanEdit на таймерах
    -- 0/1/3/6 секунд — накатываем патч после него.
    grmBootStart("GRM_SS_Install", "normal", function()
        timer.Simple(8, installJurisdictionHook)
    end)
    timer.Simple(8, installJurisdictionHook)
    timer.Simple(12, installJurisdictionHook)

    -------------------------------------------------------------------
    -- Команды
    -------------------------------------------------------------------
    local function reply(ply, ok, text)
        if not IsValid(ply) then return end
        if GRM.Notify then GRM.Notify(ply, tostring(text), ok and 170 or 250, ok and 120 or 110, ok and 250 or 110)
        else ply:ChatPrint("[Спецслужба] " .. tostring(text)) end
    end

    local function resolve(arg)
        local BL = GRM.Wanted and GRM.Wanted.Bulletins
        if BL and isfunction(BL.ResolveTarget) then return BL.ResolveTarget(arg) end
        return charKey(arg)
    end

    local HANDLERS = {
        ["/spec"] = function(ply) SS.Send(ply) end,
        ["/специальный"] = function(ply) SS.Send(ply) end,
        ["/covert_level"] = function(ply, a)
            local ok, m = SS.CovertSetLevel(ply, resolve(a[1]), tonumber(a[2]) or 0, table.concat(a, " ", 3))
            reply(ply, ok, m)
        end,
        ["/covert_wipe"] = function(ply, a)
            local ok, m = SS.CovertWipe(ply, resolve(a[1]), table.concat(a, " ", 2))
            reply(ply, ok, m)
        end,
        ["/covert_hide"] = function(ply, a)
            local ok, m = SS.CovertHide(ply, resolve(a[1]), true, table.concat(a, " ", 2))
            reply(ply, ok, m)
        end,
        ["/covert_unhide"] = function(ply, a)
            local ok, m = SS.CovertHide(ply, resolve(a[1]), false, table.concat(a, " ", 2))
            reply(ply, ok, m)
        end,
        ["/covert_fine_wipe"] = function(ply, a)
            local ok, m = SS.CovertWipeFine(ply, tonumber(a[1]) or 0, table.concat(a, " ", 2))
            reply(ply, ok, m)
        end,
        ["/covers"] = function(ply, a)
            local key = (a[1] and a[1] ~= "") and resolve(a[1]) or charKey(ply)
            if not SS.IsAgent(ply) then return reply(ply, false, "Доступ только для спецслужбы") end
            local list = SS.ListCovers(key)
            if #list == 0 then return reply(ply, true, "Легенд нет") end
            ply:ChatPrint("── Документы прикрытия ──")
            for _, c in ipairs(list) do
                ply:ChatPrint(("%s#%d  %s  •  %s  •  %s (%s)")
                    :format(c.active and "► " or "  ", c.index, c.label, c.fullName,
                            c.faction ~= "" and c.faction or "—", c.status))
            end
            ply:ChatPrint("Переключить: /cover_use <номер>   •   Оформить: /cover_new <имя легенды>")
        end,
        ["/cover_use"] = function(ply, a)
            local ok, m = SS.SetActiveCover(ply, charKey(ply), tonumber(a[1]) or 0)
            reply(ply, ok, m)
        end,
        ["/cover_new"] = function(ply, a)
            local name = string.Trim(table.concat(a, " "))
            if name == "" then return reply(ply, false, "Использование: /cover_new <имя легенды>") end
            local ok, m = SS.IssueCover(ply, charKey(ply), { label = name, fullName = name })
            reply(ply, ok, m)
        end,
        ["/cover_drop"] = function(ply, a)
            local ok, m = SS.RevokeCover(ply, charKey(ply), tonumber(a[1]) or 0)
            reply(ply, ok, m)
        end,
    }
    SS.Handlers = HANDLERS

    local function dispatch(ply, text)
        if not isstring(text) then return false end
        local args = string.Explode(" ", string.Trim(text))
        local fn = HANDLERS[string.lower(args[1] or "")]
        if not fn then return false end
        table.remove(args, 1)
        local ok, e = pcall(fn, ply, args)
        if not ok then
            ErrorNoHalt("[GRM SpecService] " .. tostring(e) .. "\n")
            reply(ply, false, "Внутренняя ошибка команды")
        end
        return true
    end
    SS.Dispatch = dispatch

    hook.Add("PlayerSayTransform", "GRM_SS_Transform", function(ply, pack)
        if not istable(pack) or not isstring(pack[1]) then return end
        if dispatch(ply, pack[1]) then
            pack[1] = ""
            pack.SkipPlayerSay = true
        end
    end)

    hook.Add("PlayerSay", "GRM_SS_Fallback", function(ply, text)
        if dispatch(ply, text) then return "" end
    end)

    concommand.Add("grm_spec", function(ply) if IsValid(ply) then SS.Send(ply) end end)
    concommand.Add("grm_spec_agents", function(ply, _, args)
        -- быстрая настройка реестра из консоли суперадмина:
        --   grm_spec_agents faction "Gestapo" 1
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        local kind = string.lower(tostring(args[1] or ""))
        local name = tostring(args[2] or "")
        local on   = tostring(args[3] or "1") ~= "0"
        if name == "" then
            print("[GRM SpecService] grm_spec_agents <faction|steam> <имя|steamid> <0|1>")
            return
        end
        local d = data()
        if kind == "faction" then d.agents.Factions[name] = on or nil
        elseif kind == "steam" then d.agents.Steam[name] = on or nil
        else print("[GRM SpecService] неизвестный тип: " .. kind) return end
        SS.Data = d
        SS.Save()
        print(("[GRM SpecService] %s %s = %s"):format(kind, name, tostring(on)))
    end)

    SS.Load()
    print("[GRM SpecService] сервер v" .. SS.Version .. " загружен")
end

if CLIENT then
    local function C()
        local T = GRM.UI and GRM.UI.Theme
        return (T and T.Colors) or {
            bg = Color(8, 14, 23, 248), panel = Color(16, 27, 42, 245),
            panel2 = Color(22, 37, 56, 245), header = Color(10, 22, 37, 255),
            text = Color(225, 238, 247), muted = Color(132, 160, 178),
            cyan = Color(48, 204, 255), green = Color(64, 222, 147),
            amber = Color(250, 185, 63), red = Color(244, 78, 96),
            purple = Color(174, 98, 255), line = Color(55, 117, 151, 190),
        }
    end

    surface.CreateFont("GRM_SS_Title", { font = "Roboto", size = 22, weight = 800, extended = true })
    surface.CreateFont("GRM_SS_Head",  { font = "Roboto", size = 15, weight = 700, extended = true })
    surface.CreateFont("GRM_SS_Row",   { font = "Roboto", size = 13, weight = 500, extended = true })

    SS.Wanted, SS.Fines, SS.Arrests, SS.Journal, SS.Online, SS.Covers = {}, {}, {}, {}, {}, {}
    SS.Cases = {}
    local frame, tabs, selected = nil, nil, ""

    local function act(a, target, text, num, extra)
        net.Start(NET_ACT)
            net.WriteString(a)
            net.WriteString(tostring(target or ""))
            net.WriteString(tostring(text or ""))
            net.WriteInt(math.floor(tonumber(num) or 0), 32)
            net.WriteTable(istable(extra) and extra or {})
        net.SendToServer()
    end
    SS.Act = act

    local function btn(parent, label, x, y, w, h, col, fn)
        local b = vgui.Create("DButton", parent)
        b:SetPos(x, y) b:SetSize(w, h)
        b:SetText(label) b:SetFont("GRM_SS_Row") b:SetTextColor(C().text)
        b.Paint = function(self, bw, bh)
            local c = col or C().panel2
            draw.RoundedBox(4, 0, 0, bw, bh, Color(c.r, c.g, c.b, self:IsHovered() and 255 or 200))
            surface.SetDrawColor(C().line) surface.DrawOutlinedRect(0, 0, bw, bh, 1)
        end
        b.DoClick = function() surface.PlaySound("ui/buttonclick.wav") if fn then fn() end end
        return b
    end

    local function money(v)
        v = math.floor(tonumber(v) or 0)
        if GRM.FormatMoney then return GRM.FormatMoney(v) end
        return string.Comma(v) .. " ℛ"
    end

    -- ── Вкладка «Базы розыска» ───────────────────────────────────────
    local function buildWantedTab(parent)
        local sc = vgui.Create("DScrollPanel", parent)
        sc:Dock(FILL) sc:DockMargin(8, 8, 8, 8)

        for _, row in ipairs(SS.Wanted) do
            local card = vgui.Create("DPanel", sc)
            card:SetTall(52) card:Dock(TOP) card:DockMargin(0, 0, 0, 5)
            card.Paint = function(self, w, h)
                draw.RoundedBox(6, 0, 0, w, h, C().panel)
                surface.SetDrawColor(row.covert and C().red or (row.jurisdiction == "military" and C().purple or C().cyan))
                surface.DrawRect(0, 0, 3, h)
                surface.SetDrawColor(C().line) surface.DrawOutlinedRect(0, 0, w, h, 1)
                draw.SimpleText(row.name, "GRM_SS_Head", 12, 13, C().text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                local tag = row.jurisdiction == "military" and "ВОЕН" or "ГРАЖД"
                if row.covert then tag = tag .. " • СКРЫТО" end
                if row.shared ~= "" then tag = tag .. " • передано" end
                draw.SimpleText(("%s • уровень %d • статей %d • долг %s")
                    :format(tag, row.level, row.charges, money(row.debt)),
                    "GRM_SS_Row", 12, 34, C().muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end

            -- Кнопки прижаты к правому краю карточки: раскладку держит
            -- сама карточка, чтобы ничего не разъезжалось при ресайзе.
            local buttons = {
                { btn(card, "Ур. 0", 0, 0, 54, 22, C().panel2,
                    function() act("level", row.key, "оператив", 0) end), 350, 8 },
                { btn(card, "Ур. -1", 0, 0, 54, 22, C().panel2,
                    function() act("level", row.key, "оператив", math.max(0, row.level - 1)) end), 292, 8 },
                { btn(card, row.covert and "Раскрыть" or "Скрыть", 0, 0, 84, 22, C().amber,
                    function() act("hide", row.key, "оператив", row.covert and 0 or 1) end), 234, 8 },
                { btn(card, "Изъять дело", 0, 0, 100, 22, C().red, function()
                    Derma_Query("Изъять дело «" .. row.name .. "» из базы без следа?", "Спецоперация",
                        "Изъять", function() act("wipe", row.key, "оператив", 0) end, "Отмена", function() end)
                end), 128, 8 },
                { btn(card, "Копировать ключ", 0, 0, 120, 20, C().panel2,
                    function() SetClipboardText(row.key) end), 128, 30 },
            }
            card.PerformLayout = function(_, w)
                for _, b in ipairs(buttons) do
                    if IsValid(b[1]) then b[1]:SetPos(w - b[2], b[3]) end
                end
            end
        end

        if #SS.Wanted == 0 then
            local e = vgui.Create("DPanel", sc) e:SetTall(50) e:Dock(TOP)
            e.Paint = function(self, w, h)
                draw.RoundedBox(6, 0, 0, w, h, C().panel)
                draw.SimpleText("База розыска пуста", "GRM_SS_Head", w / 2, h / 2, C().muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end
        return sc
    end

    -- ── Вкладка «Штрафы» ─────────────────────────────────────────────
    local function buildFinesTab(parent)
        local sc = vgui.Create("DScrollPanel", parent)
        sc:Dock(FILL) sc:DockMargin(8, 8, 8, 8)
        for _, r in ipairs(SS.Fines) do
            local card = vgui.Create("DPanel", sc)
            card:SetTall(44) card:Dock(TOP) card:DockMargin(0, 0, 0, 5)
            card.Paint = function(self, w, h)
                draw.RoundedBox(6, 0, 0, w, h, C().panel)
                surface.SetDrawColor(C().line) surface.DrawOutlinedRect(0, 0, w, h, 1)
                draw.SimpleText(("№%d  %s  —  %s"):format(r.id, tostring(r.targetName), money(r.amount)),
                    "GRM_SS_Head", 12, 13, C().text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText(("%s • %s • выписал %s"):format(tostring(r.status), tostring(r.reason or ""), tostring(r.issuerName or "")),
                    "GRM_SS_Row", 12, 31, C().muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            local bWipe = btn(card, "Изъять из реестра", 0, 0, 140, 22, C().red, function()
                act("fine_wipe", r.target, "оператив", r.id)
            end)
            card.PerformLayout = function(_, w) if IsValid(bWipe) then bWipe:SetPos(w - 150, 11) end end
        end
        if #SS.Fines == 0 then
            local e = vgui.Create("DPanel", sc) e:SetTall(50) e:Dock(TOP)
            e.Paint = function(self, w, h)
                draw.RoundedBox(6, 0, 0, w, h, C().panel)
                draw.SimpleText("Реестр штрафов пуст", "GRM_SS_Head", w / 2, h / 2, C().muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end
        return sc
    end

    -- ── Вкладка «Аресты» ─────────────────────────────────────────────
    local function buildArrestTab(parent)
        local sc = vgui.Create("DScrollPanel", parent)
        sc:Dock(FILL) sc:DockMargin(8, 8, 8, 8)
        for _, r in ipairs(SS.Arrests) do
            local card = vgui.Create("DPanel", sc)
            card:SetTall(44) card:Dock(TOP) card:DockMargin(0, 0, 0, 5)
            card.Paint = function(self, w, h)
                draw.RoundedBox(6, 0, 0, w, h, C().panel)
                surface.SetDrawColor(C().line) surface.DrawOutlinedRect(0, 0, w, h, 1)
                draw.SimpleText(r.name, "GRM_SS_Head", 12, 13, C().text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText(("%s • камера %s"):format(tostring(r.group or "—"), tostring(r.camera or "—")),
                    "GRM_SS_Row", 12, 31, C().muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            local bRel = btn(card, "Освободить тайно", 0, 0, 140, 22, C().amber, function()
                act("release", r.key, "", 0)
            end)
            card.PerformLayout = function(_, w) if IsValid(bRel) then bRel:SetPos(w - 150, 11) end end
        end
        if #SS.Arrests == 0 then
            local e = vgui.Create("DPanel", sc) e:SetTall(50) e:Dock(TOP)
            e.Paint = function(self, w, h)
                draw.RoundedBox(6, 0, 0, w, h, C().panel)
                draw.SimpleText("Арестованных нет", "GRM_SS_Head", w / 2, h / 2, C().muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end
        return sc
    end

    -- ── Вкладка «Документы прикрытия» ────────────────────────────────
    local function buildCoverTab(parent)
        local wrap = vgui.Create("DPanel", parent)
        wrap:Dock(FILL) wrap:DockMargin(8, 8, 8, 8)
        wrap.Paint = function() end

        local labelEntry=vgui.Create("DTextEntry",wrap);labelEntry:SetPos(0,0);labelEntry:SetSize(210,26);labelEntry:SetPlaceholderText("Название легенды")
        local nameEntry=vgui.Create("DTextEntry",wrap);nameEntry:SetPos(218,0);nameEntry:SetSize(210,26);nameEntry:SetPlaceholderText("ФИО по легенде")
        local factionCombo=vgui.Create("DComboBox",wrap);factionCombo:SetPos(436,0);factionCombo:SetSize(220,26);factionCombo:SetValue("Фракция прикрытия")
        local selectedFaction="";local factionNames={};for n in pairs(Factions or{})do factionNames[#factionNames+1]=n end;table.sort(factionNames);for _,n in ipairs(factionNames)do factionCombo:AddChoice(n,n)end
        local factionManual=vgui.Create("DTextEntry",wrap);factionManual:SetPos(664,0);factionManual:SetSize(220,26);factionManual:SetPlaceholderText("или вручную")
        local mixer=vgui.Create("DColorMixer",wrap);mixer:SetPos(0,36);mixer:SetSize(260,145);mixer:SetPalette(true);mixer:SetAlphaBar(false);mixer:SetWangs(true);mixer:SetColor(Color(30,35,45))
        factionCombo.OnSelect=function(_,_,_,data)selectedFaction=tostring(data or"");local cfg=GRM.Documents and GRM.Documents.Templates and GRM.Documents.Templates.factions and GRM.Documents.Templates.factions[selectedFaction];if cfg and cfg.coverColor then mixer:SetColor(Color(cfg.coverColor.r,cfg.coverColor.g,cfg.coverColor.b))end end
        local roleEntry=vgui.Create("DTextEntry",wrap);roleEntry:SetPos(275,42);roleEntry:SetSize(190,26);roleEntry:SetPlaceholderText("Должность")
        local deptEntry=vgui.Create("DTextEntry",wrap);deptEntry:SetPos(475,42);deptEntry:SetSize(190,26);deptEntry:SetPlaceholderText("Подразделение")
        local numEntry=vgui.Create("DTextEntry",wrap);numEntry:SetPos(675,42);numEntry:SetSize(190,26);numEntry:SetPlaceholderText("Номер")
        local foil=vgui.Create("DComboBox",wrap);foil:SetPos(275,76);foil:SetSize(190,26);foil:SetValue("Золотое тиснение");foil:AddChoice("Золотое","gold",true);foil:AddChoice("Серебряное","silver");foil:AddChoice("Бронзовое","bronze");foil:AddChoice("Белое","white")
        btn(wrap,"ОФОРМИТЬ ЛЕГЕНДУ",475,76,390,34,C().green,function()
            local full=string.Trim(nameEntry:GetValue()or"");if full==""then return end
            local fac=string.Trim(factionManual:GetValue()or"");if fac==""then fac=selectedFaction end;if fac==""then return end
            local _,foilID=foil:GetSelected();local col=mixer:GetColor()
            act("cover_issue","",full,0,{label=string.Trim(labelEntry:GetValue()or"")~=""and labelEntry:GetValue()or full,fullName=full,faction=fac,role=roleEntry:GetValue(),department=deptEntry:GetValue(),number=numEntry:GetValue(),coverColor={r=col.r,g=col.g,b=col.b},foilStyle=foilID or"gold"})
        end)
        btn(wrap,"Настоящий документ",475,118,190,28,C().panel2,function()act("cover_switch","","",0)end)

        local sc=vgui.Create("DScrollPanel",wrap);sc:SetPos(0,190);sc:SetSize(wrap:GetWide(),math.max(50,wrap:GetTall()-190));sc.PerformLayout=function(self)self:SetSize(wrap:GetWide(),math.max(50,wrap:GetTall()-190))end

        for _, c in ipairs(SS.Covers) do
            local card = vgui.Create("DPanel", sc)
            card:SetTall(52) card:Dock(TOP) card:DockMargin(0, 0, 0, 5)
            card.Paint = function(self, w, h)
                draw.RoundedBox(6, 0, 0, w, h, C().panel)
                surface.SetDrawColor(c.active and C().green or C().line)
                surface.DrawOutlinedRect(0, 0, w, h, c.active and 2 or 1)
                local cc=c.coverColor or {r=80,g=90,b=110};draw.RoundedBox(3,8,8,5,36,Color(cc.r or 80,cc.g or 90,cc.b or 110))
                draw.SimpleText(("#%d  %s"):format(c.index, c.label), "GRM_SS_Head", 18, 13, c.active and C().green or C().text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText(("%s • %s %s • №%s • %s")
                    :format(c.fullName, c.faction ~= "" and c.faction or "—", c.role, c.number, c.status),
                    "GRM_SS_Row", 12, 34, C().muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            local bUse = btn(card, c.active and "Активна" or "Использовать", 0, 0, 120, 22,
                c.active and C().green or C().panel2, function() act("cover_switch", "", "", c.index) end)
            local bDrop = btn(card, "Аннулировать", 0, 0, 120, 22, C().red,
                function() act("cover_revoke", "", "", c.index) end)
            card.PerformLayout = function(_, w)
                if IsValid(bUse) then bUse:SetPos(w - 254, 15) end
                if IsValid(bDrop) then bDrop:SetPos(w - 128, 15) end
            end
        end

        if #SS.Covers == 0 then
            local e = vgui.Create("DPanel", sc) e:SetTall(50) e:Dock(TOP)
            e.Paint = function(self, w, h)
                draw.RoundedBox(6, 0, 0, w, h, C().panel)
                draw.SimpleText("Легенд не оформлено", "GRM_SS_Head", w / 2, h / 2, C().muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end
        return wrap
    end

    -- ── Вкладка «Закрытый журнал» ────────────────────────────────────
    local function buildJournalTab(parent)
        local sc = vgui.Create("DScrollPanel", parent)
        sc:Dock(FILL) sc:DockMargin(8, 8, 8, 8)
        for _, e in ipairs(SS.Journal) do
            local card = vgui.Create("DPanel", sc)
            card:SetTall(36) card:Dock(TOP) card:DockMargin(0, 0, 0, 4)
            card.Paint = function(self, w, h)
                draw.RoundedBox(4, 0, 0, w, h, C().panel)
                draw.SimpleText(("[%s] %s → %s"):format(os.date("%d.%m %H:%M", tonumber(e.t) or 0),
                    tostring(e.actorName or "?"), tostring(e.op or "?")),
                    "GRM_SS_Row", 10, 11, C().text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText(tostring(e.detail or ""), "GRM_SS_Row", 10, 25, C().muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
        end
        if #SS.Journal == 0 then
            local e = vgui.Create("DPanel", sc) e:SetTall(50) e:Dock(TOP)
            e.Paint = function(self, w, h)
                draw.RoundedBox(6, 0, 0, w, h, C().panel)
                draw.SimpleText("Журнал пуст", "GRM_SS_Head", w / 2, h / 2, C().muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end
        return sc
    end

    local function rebuild()
        if not IsValid(frame) then return end
        local active = IsValid(tabs) and tabs:GetActiveTab() and tabs:GetActiveTab():GetText() or nil
        if IsValid(tabs) then tabs:Remove() end

        tabs = vgui.Create("DPropertySheet", frame)
        tabs:SetPos(10, 58)
        tabs:SetSize(frame:GetWide() - 20, frame:GetTall() - 68)
        tabs.Paint = function(self, w, h) draw.RoundedBox(6, 0, 0, w, h, Color(0, 0, 0, 0)) end

        local pW = vgui.Create("DPanel", tabs) pW.Paint = function() end
        buildWantedTab(pW)
        tabs:AddSheet("Розыск", pW, "icon16/user_red.png")

        local pF = vgui.Create("DPanel", tabs) pF.Paint = function() end
        buildFinesTab(pF)
        tabs:AddSheet("Штрафы", pF, "icon16/money.png")

        local pA = vgui.Create("DPanel", tabs) pA.Paint = function() end
        buildArrestTab(pA)
        tabs:AddSheet("Аресты", pA, "icon16/lock.png")

        local pC = vgui.Create("DPanel", tabs) pC.Paint = function() end
        buildCoverTab(pC)
        tabs:AddSheet("Прикрытие", pC, "icon16/user_gray.png")

        local pJ = vgui.Create("DPanel", tabs) pJ.Paint = function() end
        buildJournalTab(pJ)
        tabs:AddSheet("Журнал", pJ, "icon16/book.png")

        if active then
            for _, sheet in ipairs(tabs:GetItems()) do
                if sheet.Tab and sheet.Tab:GetText() == active then tabs:SetActiveTab(sheet.Tab) break end
            end
        end
    end

    function SS.Open()
        if IsValid(frame) then frame:Remove() end
        frame = vgui.Create("DFrame")
        frame:SetSize(math.min(1000, ScrW() - 60), math.min(680, ScrH() - 60))
        frame:Center()
        frame:MakePopup()
        frame:SetTitle("")
        frame:ShowCloseButton(false)

        local T = GRM.UI and GRM.UI.Theme
        if T and isfunction(T.ApplyFrame) then
            T.ApplyFrame(frame, "spec_service", "ОПЕРАТИВНЫЙ ТЕРМИНАЛ",
                "полный контроль баз • операции не журналируются ведомствами")
        else
            if GRM.UI and isfunction(GRM.UI.Track) then GRM.UI.Track("spec_service", frame) end
            frame.Paint = function(self, w, h)
                draw.RoundedBox(9, 0, 0, w, h, C().bg)
                draw.RoundedBoxEx(9, 0, 0, w, 52, C().header, true, true, false, false)
                draw.SimpleText("ОПЕРАТИВНЫЙ ТЕРМИНАЛ", "GRM_SS_Title", 16, 20, C().text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText("полный контроль баз", "GRM_SS_Row", 16, 40, C().purple, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            btn(frame, "X", frame:GetWide() - 40, 12, 28, 28, C().red, function() frame:Close() end)
        end

        btn(frame, "Обновить", frame:GetWide() - 130, 14, 84, 24, C().panel2, function()
            net.Start(NET_OPEN) net.SendToServer()
        end)

        rebuild()
    end

    --- Терминал спецслужб (grm_comp_security) держит свой список тайных
    -- операций: если он открыт, обновляем и его.
    local function refreshSecurityTerminal(rows)
        local f = _G.GRM_CompSecurity_ActiveFrame
        if IsValid(f) and isfunction(f._fillCovert) then
            local map = {}
            for _, r in ipairs(rows or {}) do map[r.key] = r end
            f._fillCovert(map)
        end
    end

    net.Receive(NET_DATA, function()
        SS.Wanted  = net.ReadTable() or {}
        SS.Fines   = net.ReadTable() or {}
        SS.Arrests = net.ReadTable() or {}
        SS.Journal = net.ReadTable() or {}
        SS.Online  = net.ReadTable() or {}
        SS.Covers  = net.ReadTable() or {}
        SS.Cases   = net.ReadTable() or {}
        refreshSecurityTerminal(SS.Wanted)

        if IsValid(frame) then
            rebuild()
        elseif not IsValid(_G.GRM_CompSecurity_ActiveFrame) then
            -- Данные пришли по запросу «Обновить» из терминала спецслужб —
            -- в этом случае вторым окном не мешаем.
            SS.Open()
        end
    end)

    net.Receive(NET_RESULT, function()
        local ok = net.ReadBool()
        local msg = net.ReadString()
        chat.AddText(ok and C().green or C().red, "[Спецслужба] ", C().text, msg)
    end)

    concommand.Add("grm_spec_open", function()
        net.Start(NET_OPEN) net.SendToServer()
    end)

    print("[GRM SpecService] клиент v" .. SS.Version .. " загружен")
end
