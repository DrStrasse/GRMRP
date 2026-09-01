-- Boot-шим: старт подсистемы идёт через планировщик GRM.Boot (приоритеты и
-- бюджет на тик). Если планировщик почему-то не загружен, работаем по-старому.
local function grmBootStart(id, tier, fn)
    if GRM and GRM.Boot and GRM.Boot.OnMapStart then return GRM.Boot.OnMapStart(id, tier, fn) end
    return hook.Add("InitPostEntity", id, fn)
end

--[[--------------------------------------------------------------------
    GRM Diplomas v1.0.0 — государственный реестр дипломов

    Образовательное учреждение (фракция с доступом canDiploma) обучает
    людей — платно через счета (sh_grm_services.lua) или бесплатно — и
    выписывает диплом с заполняемыми полями:

        учреждение, выпускник, специальность, квалификация,
        форма обучения, оценка, номер бланка, дата выдачи, подписант.

    Диплом хранится в государственном реестре и проверяется по номеру:
    любой желающий может убедиться, что диплом настоящий, а суперадмин —
    отредактировать или удалить любую запись.

    Данные: data/grm_services/diplomas.json
            { version = 1, diplomas = {...}, nextNumber = N }

    Ключ выпускника — GRM.Identity.CharacterKey (SteamID64:charN):
    диплом принадлежит персонажу, а не аккаунту.
----------------------------------------------------------------------]]

if CLIENT then return end

GRM = GRM or {}
GRM.Diplomas = GRM.Diplomas or {}

local D = GRM.Diplomas
D.Version = "1.0.0"

local DIR  = "grm_services"
local FILE = "grm_services/diplomas.json"

D.List = D.List or {}          -- массив записей (порядок = хронология)
D._nextNumber = D._nextNumber or 1

-----------------------------------------------------------------------
-- Конфигурация
-----------------------------------------------------------------------
D.Config = D.Config or {
    MaxRecords      = 5000,
    MaxPerCharacter = 24,      -- сколько дипломов может быть у персонажа
    -- серия бланка: год + код учреждения, номер — сквозной по реестру
    SeriesPrefix    = "ГД",    -- «Государственный диплом»
    SuperAdminBypass = true,
}

--- Уровни образования: используются в бланке и в фильтрах реестра.
D.Levels = D.Levels or {
    { id = "course",     name = "Курсы повышения квалификации" },
    { id = "vocational", name = "Среднее профессиональное" },
    { id = "bachelor",   name = "Высшее (бакалавриат)" },
    { id = "master",     name = "Высшее (магистратура)" },
    { id = "doctor",     name = "Учёная степень" },
}

D.Forms = D.Forms or {
    { id = "full",     name = "Очная" },
    { id = "part",     name = "Заочная" },
    { id = "evening",  name = "Вечерняя" },
    { id = "external", name = "Экстернат" },
}

local function nameOf(list, id, fallback)
    for _, v in ipairs(list) do
        if v.id == id then return v.name end
    end
    return fallback or "—"
end

function D.LevelName(id) return nameOf(D.Levels, id, "Не указан") end
function D.FormName(id)  return nameOf(D.Forms,  id, "Не указана") end

function D.LevelExists(id)
    for _, v in ipairs(D.Levels) do if v.id == id then return true end end
    return false
end
function D.FormExists(id)
    for _, v in ipairs(D.Forms) do if v.id == id then return true end end
    return false
end

-----------------------------------------------------------------------
-- Утилиты
-----------------------------------------------------------------------
local function ensure()
    if not file.IsDir(DIR, "DATA") then file.CreateDir(DIR) end
end

local function jsonT(s)
    local ok, t = pcall(util.JSONToTable, s or "", false, true)
    return ok and istable(t) and t or nil
end

local function write(path, data)
    ensure()
    local ok, s = pcall(util.TableToJSON, data, true)
    if not ok or not isstring(s) then return false end
    file.Write(path, s)
    return file.Read(path, "DATA") == s
end

local function backupCorrupt(path)
    local raw = file.Read(path, "DATA")
    if not raw or raw == "" then return end
    file.Write(path .. ".corrupt." .. os.time(), raw)
end

local function charKey(v)
    if GRM.Services and isfunction(GRM.Services.CharKey) then return GRM.Services.CharKey(v) end
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
D.CharKey = charKey

local function findPlayerByKey(k)
    if GRM.Services and isfunction(GRM.Services.FindPlayer) then return GRM.Services.FindPlayer(k) end
    k = tostring(k or "")
    for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
        if IsValid(p) and (charKey(p) == k or p:SteamID64() == k) then return p end
    end
end

local function notify(p, msg, r, g, b)
    if not IsValid(p) then return end
    if GRM.Notify then GRM.Notify(p, msg, r or 120, g or 200, b or 255)
    else p:ChatPrint("[Дипломы] " .. msg) end
end

--[[ Задача 10: лимит считается в СИМВОЛАХ, а не в байтах. string.sub резал
     кириллицу пополам (2 байта на символ): «…Ф.Э.Дзержинского» приезжало на
     клиент как «…Ф.Э.Дзержинског». Выглядело как отсутствие переноса строк,
     хотя перенос работал — до бланка просто доезжал обрезанный текст. ]]
local function trim(s, n)
    s = string.Trim(tostring(s or ""))
    if n then
        if GRM and GRM.Utf8Sub then s = GRM.Utf8Sub(s, n)
        else s = string.sub(s, 1, n) end
    end
    return s
end

-----------------------------------------------------------------------
-- Права
-----------------------------------------------------------------------
--- Может ли игрок выписывать дипломы. @return можно, фракция, причина
function D.CanIssue(ply)
    if not IsValid(ply) then return false, nil, "Нет игрока" end
    if D.Config.SuperAdminBypass and ply:IsSuperAdmin() then
        local n = GRM.Services and GRM.Services.FactionOf(ply)
        return true, n or "Администрация", nil
    end
    local S = GRM.Services
    if not S then return false, nil, "Модуль госуслуг не загружен" end
    local name = S.FactionOf(ply)
    if not name then return false, nil, "Вы не состоите в организации" end
    local a = S.AccessOf(name)
    if not a.canDiploma then
        return false, name, "Организации «" .. name .. "» не выдан доступ на выдачу дипломов"
    end
    -- Выписывать может любой сотрудник учреждения: подпись фиксируется в бланке.
    return true, name, nil
end

--- Официальное название учреждения для бланка.
function D.InstitutionOf(factionName)
    local S = GRM.Services
    if S then
        local a = S.AccessOf(factionName)
        if a.institution and a.institution ~= "" then return a.institution end
    end
    return tostring(factionName or "")
end

-----------------------------------------------------------------------
-- Загрузка / сохранение
-----------------------------------------------------------------------
local function normalize(raw)
    if not istable(raw) then return nil end
    local number = trim(raw.number, 32)
    if number == "" then return nil end
    return {
        number      = number,
        seq         = math.floor(tonumber(raw.seq) or 0),
        graduate    = charKey(raw.graduate),
        graduateName= trim(raw.graduateName, 64),
        institution = trim(raw.institution, 96),
        faction     = trim(raw.faction, 64),
        specialty   = trim(raw.specialty, 96),
        qualification = trim(raw.qualification, 96),
        level       = D.LevelExists(raw.level) and raw.level or "course",
        form        = D.FormExists(raw.form) and raw.form or "full",
        grade       = trim(raw.grade, 32),
        paid        = raw.paid == true,
        invoiceID   = math.floor(tonumber(raw.invoiceID) or 0),
        issuer      = tostring(raw.issuer or ""),
        issuerName  = trim(raw.issuerName, 64),
        signedBy    = trim(raw.signedBy, 64),
        issued      = math.floor(tonumber(raw.issued) or os.time()),
        revoked     = raw.revoked == true,
        revokeReason= trim(raw.revokeReason, 160),
        note        = trim(raw.note, 240),
    }
end

function D.Load()
    D.List, D._nextNumber = {}, 1
    if not file.Exists(FILE, "DATA") then return end
    local t = jsonT(file.Read(FILE, "DATA") or "")
    if not t then
        backupCorrupt(FILE)
        print("[GRM Diplomas] diplomas.json повреждён — сохранена копия, реестр пуст")
        return
    end
    local list = istable(t.diplomas) and t.diplomas or (istable(t) and t or {})
    local maxSeq = 0
    for _, raw in pairs(list) do
        local n = normalize(raw)
        if n then
            D.List[#D.List + 1] = n
            if n.seq > maxSeq then maxSeq = n.seq end
        end
    end
    table.sort(D.List, function(a, b) return (a.issued or 0) < (b.issued or 0) end)
    D._nextNumber = math.max(maxSeq + 1, math.floor(tonumber(t.nextNumber) or 1))
end

function D.Save()
    local maxRec = D.Config.MaxRecords
    while #D.List > maxRec do table.remove(D.List, 1) end
    return write(FILE, { version = 1, diplomas = D.List, nextNumber = D._nextNumber })
end

-----------------------------------------------------------------------
-- Выдача диплома
-----------------------------------------------------------------------
local function makeNumber(seq)
    -- ГД-2026-000123: серия, год, сквозной номер бланка
    return ("%s-%s-%06d"):format(D.Config.SeriesPrefix, os.date("%Y"), seq)
end

--- Выписать диплом.
-- @param data {
--     graduate      — игрок / ключ / SteamID64 выпускника (обязательно)
--     specialty     — специальность (обязательно)
--     qualification — присвоенная квалификация
--     level, form   — уровень образования и форма обучения
--     grade         — итоговая оценка («отлично», «с отличием», …)
--     institution   — название учреждения (по умолчанию — из настроек фракции)
--     paid          — обучение было платным
--     invoiceID     — счёт, по которому оплачено обучение
--     signedBy      — кто подписал бланк (по умолчанию — выдающий)
--     note          — примечание
-- }
function D.Issue(issuer, data)
    data = istable(data) and data or {}

    local can, fname, why = D.CanIssue(issuer)
    if not can then return false, why end

    local gKey = charKey(data.graduate)
    if gKey == "" then return false, "Не указан выпускник" end

    local specialty = trim(data.specialty, 96)
    if specialty == "" then return false, "Не указана специальность" end

    local isSuper = IsValid(issuer) and issuer:IsSuperAdmin()
    if not isSuper then
        local mine = 0
        for _, rec in ipairs(D.List) do
            if rec.graduate == gKey and not rec.revoked then mine = mine + 1 end
        end
        if mine >= D.Config.MaxPerCharacter then
            return false, "У выпускника слишком много дипломов"
        end
    end

    -- платное обучение: счёт должен быть оплачен, иначе бланк не выдаём
    local invoiceID = math.floor(tonumber(data.invoiceID) or 0)
    if invoiceID > 0 then
        local S = GRM.Services
        local inv = S and isfunction(S.InvoiceByID) and S.InvoiceByID(invoiceID) or nil
        if not inv then return false, "Счёт №" .. invoiceID .. " не найден" end
        if inv.target ~= gKey then return false, "Счёт выставлен другому лицу" end
        if inv.status ~= "paid" and not isSuper then
            return false, "Обучение не оплачено: счёт №" .. invoiceID .. " не закрыт"
        end
    end

    local institution = trim(data.institution, 96)
    if institution == "" then institution = D.InstitutionOf(fname) end
    if institution == "" then return false, "Не указано учреждение образования" end

    local seq = D._nextNumber
    local rec = {
        number       = makeNumber(seq),
        seq          = seq,
        graduate     = gKey,
        graduateName = trim(data.graduateName, 64),
        institution  = institution,
        faction      = fname or "",
        specialty    = specialty,
        qualification= trim(data.qualification, 96),
        level        = D.LevelExists(data.level) and data.level or "course",
        form         = D.FormExists(data.form) and data.form or "full",
        grade        = trim(data.grade, 32),
        paid         = data.paid == true or invoiceID > 0,
        invoiceID    = invoiceID,
        issuer       = IsValid(issuer) and charKey(issuer) or "система",
        issuerName   = IsValid(issuer) and issuer:Nick() or "система",
        signedBy     = trim(data.signedBy, 64),
        issued       = os.time(),
        revoked      = false,
        note         = trim(data.note, 240),
    }
    if rec.graduateName == "" then
        -- ФИО выпускника: паспорт → RP-имя → ник. Диплом принадлежит
        -- персонажу, поэтому офлайн-выдача обязана давать читаемое имя.
        local S = GRM.Services
        if S and isfunction(S.CharacterName) then
            rec.graduateName = S.CharacterName(gKey)
        else
            local gp = findPlayerByKey(gKey)
            rec.graduateName = IsValid(gp) and gp:Nick() or gKey
        end
    end
    if rec.signedBy == "" then rec.signedBy = rec.issuerName end

    D._nextNumber = D._nextNumber + 1
    D.List[#D.List + 1] = rec
    D.Save()

    local gp = findPlayerByKey(gKey)
    if IsValid(gp) then
        notify(gp, ("Вам выдан диплом %s: %s, специальность «%s». Проверить: /diploma %s")
            :format(rec.number, rec.institution, rec.specialty, rec.number), 140, 220, 255)
    end
    hook.Run("GRM_DiplomaIssued", issuer, rec)
    return true, rec
end

-----------------------------------------------------------------------
-- Поиск и выборки
-----------------------------------------------------------------------
function D.ByNumber(number)
    number = string.upper(trim(number, 32))
    for _, rec in ipairs(D.List) do
        if string.upper(rec.number) == number then return rec end
    end
end

function D.For(graduate, includeRevoked)
    local k = charKey(graduate)
    local out = {}
    for _, rec in ipairs(D.List) do
        if rec.graduate == k and (includeRevoked or not rec.revoked) then
            out[#out + 1] = rec
        end
    end
    return out
end

function D.ByFaction(factionName, limit)
    limit = math.floor(tonumber(limit) or 150)
    local out = {}
    for i = #D.List, 1, -1 do
        local rec = D.List[i]
        if rec.faction == factionName then
            out[#out + 1] = rec
            if #out >= limit then break end
        end
    end
    return out
end

--- Постраничная выборка реестра (для терминалов и админ-панели).
-- @param filter { query=..., faction=..., level=..., onlyValid=bool }
function D.Page(filter, offset, limit)
    filter = istable(filter) and filter or {}
    offset = math.max(0, math.floor(tonumber(offset) or 0))
    limit  = math.Clamp(math.floor(tonumber(limit) or 100), 1, 400)

    local q = filter.query and string.lower(trim(filter.query, 64)) or ""
    local out, total = {}, 0
    for i = #D.List, 1, -1 do   -- новые сверху
        local rec = D.List[i]
        local ok = true
        if filter.onlyValid and rec.revoked then ok = false end
        if ok and filter.faction and filter.faction ~= "" and rec.faction ~= filter.faction then ok = false end
        if ok and filter.level and filter.level ~= "" and rec.level ~= filter.level then ok = false end
        if ok and q ~= "" then
            local hay = string.lower(table.concat({
                rec.number or "", rec.graduateName or "", rec.specialty or "",
                rec.institution or "", rec.qualification or "",
            }, " "))
            if not string.find(hay, q, 1, true) then ok = false end
        end
        if ok then
            total = total + 1
            if total > offset and #out < limit then out[#out + 1] = rec end
        end
    end
    return out, total
end

-----------------------------------------------------------------------
-- Аннулирование / правка / удаление
-----------------------------------------------------------------------
--- Аннулировать диплом (учреждение — свой, суперадмин — любой).
function D.Revoke(actor, number, reason)
    local rec = D.ByNumber(number)
    if not rec then return false, "Диплом не найден" end
    if rec.revoked then return false, "Диплом уже аннулирован" end

    if IsValid(actor) and not actor:IsSuperAdmin() then
        local S = GRM.Services
        local fname = S and S.FactionOf(actor)
        if rec.faction ~= fname then return false, "Диплом выдан другим учреждением" end
        if not (S and S.IsLeaderOf(actor, fname)) then
            return false, "Аннулировать диплом может руководитель учреждения"
        end
    end

    rec.revoked = true
    rec.revokeReason = trim(reason, 160)
    D.Save()

    local gp = findPlayerByKey(rec.graduate)
    if IsValid(gp) then
        notify(gp, ("Ваш диплом %s аннулирован. Причина: %s")
            :format(rec.number, rec.revokeReason ~= "" and rec.revokeReason or "не указана"), 255, 150, 150)
    end
    hook.Run("GRM_DiplomaRevoked", actor, rec)
    return true, rec
end

--- Восстановить ошибочно аннулированный диплом (только суперадмин).
function D.Restore(actor, number)
    if not (IsValid(actor) and actor:IsSuperAdmin()) then return false, "Только суперадмин" end
    local rec = D.ByNumber(number)
    if not rec then return false, "Диплом не найден" end
    if not rec.revoked then return false, "Диплом действителен" end
    rec.revoked = false
    rec.revokeReason = ""
    D.Save()
    hook.Run("GRM_DiplomaRestored", actor, rec)
    return true, rec
end

--- Правка полей бланка.
-- Учреждение может исправить опечатку в своём дипломе, суперадмин — в любом.
function D.Edit(actor, number, patch)
    local rec = D.ByNumber(number)
    if not rec then return false, "Диплом не найден" end
    patch = istable(patch) and patch or {}

    local isSuper = IsValid(actor) and actor:IsSuperAdmin()
    if IsValid(actor) and not isSuper then
        local S = GRM.Services
        local fname = S and S.FactionOf(actor)
        if rec.faction ~= fname then return false, "Диплом выдан другим учреждением" end
        if not (S and S.IsLeaderOf(actor, fname)) then
            return false, "Править бланк может руководитель учреждения"
        end
    end

    if patch.specialty     ~= nil then rec.specialty     = trim(patch.specialty, 96) end
    if patch.qualification ~= nil then rec.qualification = trim(patch.qualification, 96) end
    if patch.grade         ~= nil then rec.grade         = trim(patch.grade, 32) end
    if patch.note          ~= nil then rec.note          = trim(patch.note, 240) end
    if patch.signedBy      ~= nil then rec.signedBy      = trim(patch.signedBy, 64) end
    if patch.level ~= nil and D.LevelExists(patch.level) then rec.level = patch.level end
    if patch.form  ~= nil and D.FormExists(patch.form)   then rec.form  = patch.form end
    -- учреждение и выпускника меняет только суперадмин: это личность и эмитент
    if isSuper then
        if patch.institution  ~= nil then rec.institution  = trim(patch.institution, 96) end
        if patch.graduateName ~= nil then rec.graduateName = trim(patch.graduateName, 64) end
        if patch.graduate     ~= nil then rec.graduate     = charKey(patch.graduate) end
        if patch.number ~= nil then
            local n = trim(patch.number, 32)
            if n ~= "" and (not D.ByNumber(n) or string.upper(n) == string.upper(rec.number)) then
                rec.number = n
            end
        end
    end

    D.Save()
    hook.Run("GRM_DiplomaEdited", actor, rec)
    return true, rec
end

--- Удаление записи из реестра (только суперадмин — полный доступ).
function D.Delete(actor, number)
    if IsValid(actor) and not actor:IsSuperAdmin() then return false, "Только суперадмин" end
    number = string.upper(trim(number, 32))
    for i = #D.List, 1, -1 do
        if string.upper(D.List[i].number) == number then
            local rec = D.List[i]
            table.remove(D.List, i)
            D.Save()
            hook.Run("GRM_DiplomaDeleted", actor, rec)
            return true, rec
        end
    end
    return false, "Диплом не найден"
end

--- Полная очистка реестра (только суперадмин, с подтверждением снаружи).
function D.Wipe(actor)
    if not (IsValid(actor) and actor:IsSuperAdmin()) then return false, "Только суперадмин" end
    local n = #D.List
    D.List = {}
    D.Save()
    hook.Run("GRM_DiplomaWiped", actor, n)
    return true, n
end

-----------------------------------------------------------------------
-- Текстовый бланк (для чата, документов и печати на терминале)
-----------------------------------------------------------------------
function D.RenderText(rec)
    if not istable(rec) then return "" end
    local lines = {
        "════════════════════════════════════════",
        "         ГОСУДАРСТВЕННЫЙ ДИПЛОМ",
        "════════════════════════════════════════",
        "Бланк №: " .. rec.number,
        "Учреждение: " .. rec.institution,
        "Выпускник: " .. rec.graduateName,
        "Специальность: " .. rec.specialty,
        "Квалификация: " .. (rec.qualification ~= "" and rec.qualification or "—"),
        "Уровень: " .. D.LevelName(rec.level),
        "Форма обучения: " .. D.FormName(rec.form),
        "Оценка: " .. (rec.grade ~= "" and rec.grade or "—"),
        "Обучение: " .. (rec.paid and "платное" or "бесплатное"),
        "Дата выдачи: " .. os.date("%d.%m.%Y", rec.issued or os.time()),
        "Подпись: " .. (rec.signedBy ~= "" and rec.signedBy or rec.issuerName),
    }
    if rec.note ~= "" then lines[#lines + 1] = "Примечание: " .. rec.note end
    if rec.revoked then
        lines[#lines + 1] = "──────────────────────────────────────"
        lines[#lines + 1] = "!!! ДИПЛОМ АННУЛИРОВАН !!!"
        if rec.revokeReason ~= "" then lines[#lines + 1] = "Причина: " .. rec.revokeReason end
    end
    lines[#lines + 1] = "════════════════════════════════════════"
    return table.concat(lines, "\n")
end

-----------------------------------------------------------------------
-- Разовая починка записей, обрезанных байтовым string.sub (задача 12)
-----------------------------------------------------------------------
--[[ До перехода на GRM.Utf8Sub поля резались как БАЙТЫ: trim(s, 96)
     оставлял ~48 кириллических букв и мог разорвать последний символ
     пополам. Записи, сохранённые тогда, уже лежат в diplomas.json
     обрезанными — новый код чинит будущие выдачи, но не прошлые.

     Что реально можно восстановить, а что нет:
       • битый хвост (незавершённый UTF-8) — убирается всегда, это чистый
         мусор без информации;
       • institution и graduateName — есть КАНОНИЧЕСКИЙ источник (реестр
         услуг и паспорта), поэтому текст восстанавливается целиком;
       • specialty, qualification, note, grade, signedBy, revokeReason —
         источника нет, хвост уничтожен записью на диск. Такие поля мы
         НЕ придумываем: чистим битый символ и сообщаем администратору,
         что значение надо ввести заново.
     Молча «додумывать» данные в госреестре нельзя, поэтому невосстановимое
     честно попадает в отчёт отдельным списком. ]]

-- Байтовые лимиты, которыми пользовался старый trim(). Совпадение длины
-- строки с лимитом ровно в байтах — почерк обрезки байтами.
D.FieldLimits = D.FieldLimits or {
    number = 32, graduateName = 64, institution = 96, faction = 64,
    specialty = 96, qualification = 96, grade = 32, issuerName = 64,
    signedBy = 64, revokeReason = 160, note = 240,
}

--- Позиция начала незавершённого UTF-8 символа в конце строки (или nil).
local function brokenTailAt(s)
    local n = #s
    local i = n
    while i >= 1 and i > n - 4 do
        local b = string.byte(s, i)
        if b < 128 then return nil end            -- ASCII — символ целый
        if b >= 192 then                          -- ведущий байт
            local size = (b < 224 and 2) or (b < 240 and 3) or 4
            if i + size - 1 > n then return i end -- байтов не хватило
            return nil
        end
        i = i - 1                                 -- байт-продолжение
    end
    return nil
end

--- Убрать оборванный символ в конце строки.
local function stripBrokenTail(s)
    local at = brokenTailAt(s)
    if at then return string.sub(s, 1, at - 1), true end
    return s, false
end

--- Похоже ли поле на обрезанное байтами.
local function looksTruncated(value, limit)
    if not limit then return false end
    -- Ровно лимит байт: старый string.sub(s, N) иначе бы не сработал.
    return #value >= limit
end

--- Разовая починка реестра дипломов.
-- @param actor кто чинит (для прав и уведомлений); nil — консоль сервера
-- @param apply true — записать изменения; false/nil — только показать
-- @return ok, отчёт { scanned, fixedTails, restored[], unrecoverable[], changed }
function D.Repair(actor, apply)
    if IsValid(actor) and not actor:IsSuperAdmin() then
        return false, "Только суперадмин"
    end

    local S = GRM.Services
    local report = {
        scanned = 0, fixedTails = 0, changed = 0,
        restored = {}, unrecoverable = {},
    }

    for _, rec in ipairs(D.List) do
        report.scanned = report.scanned + 1

        -- Канонические источники: учреждение — из доступа фракции,
        -- ФИО выпускника — из паспорта/состава фракции.
        local canon = {}
        if isfunction(D.InstitutionOf) and tostring(rec.faction or "") ~= "" then
            canon.institution = D.InstitutionOf(rec.faction)
        end
        if S and isfunction(S.CharacterName) and tostring(rec.graduate or "") ~= "" then
            local nm = S.CharacterName(rec.graduate)
            -- CharacterName возвращает сам ключ, если имени не нашлось.
            if nm and nm ~= "—" and nm ~= rec.graduate then canon.graduateName = nm end
        end

        for field, limit in pairs(D.FieldLimits) do
            local cur = rec[field]
            if isstring(cur) and cur ~= "" then
                local cleaned, hadTail = stripBrokenTail(cur)
                if hadTail then report.fixedTails = report.fixedTails + 1 end

                local full = canon[field]
                local restoredHere = false
                if full and full ~= "" and #cleaned < #full
                    and string.sub(full, 1, #cleaned) == cleaned then
                    -- Сохранённое — начало канонического значения: дописываем.
                    if apply then rec[field] = full end
                    report.restored[#report.restored + 1] = {
                        number = rec.number, field = field, from = cur, to = full,
                    }
                    report.changed = report.changed + 1
                    restoredHere = true
                elseif hadTail then
                    if apply then rec[field] = cleaned end
                    report.changed = report.changed + 1
                end

                -- Значение уже совпало с каноническим — оно целое, даже если
                -- его длина случайно упёрлась в старый лимит.
                local matchesCanon = (full ~= nil and full ~= "" and cleaned == full)

                if not restoredHere and not matchesCanon and looksTruncated(cur, limit) then
                    -- Хвост уничтожен, канона нет — только сообщаем.
                    report.unrecoverable[#report.unrecoverable + 1] = {
                        number = rec.number, field = field,
                        value = (hadTail and cleaned or cur),
                    }
                end
            end
        end
    end

    if apply and report.changed > 0 then
        -- Миграция обязана быть обратимой: сначала бэкап исходного файла.
        local raw = file.Read(FILE, "DATA")
        if raw and raw ~= "" then
            ensure()
            file.Write(("%s/diplomas.bak.%d.json"):format(DIR, os.time()), raw)
        end
        D.Save()
    end

    return true, report
end

-----------------------------------------------------------------------
-- Старт
-----------------------------------------------------------------------
local function boot()
    D.Load()
    print(("[GRM Diplomas] v%s загружен, дипломов в реестре: %d"):format(D.Version, #D.List))
end

grmBootStart("GRM_Diplomas_Load", "late", boot)
if GRM and GRM.Diplomas then boot() end
