-- Boot-шим: старт подсистемы идёт через планировщик GRM.Boot (приоритеты и
-- бюджет на тик). Если планировщик почему-то не загружен, работаем по-старому.
local function grmBootStart(id, tier, fn)
    if GRM and GRM.Boot and GRM.Boot.OnMapStart then return GRM.Boot.OnMapStart(id, tier, fn) end
    return hook.Add("InitPostEntity", id, fn)
end

--[[--------------------------------------------------------------------
    GRM Services v1.0.0 — государственные услуги и счета на оплату

    Три сущности:
      • КАТАЛОГ УСЛУГ  — что организация умеет оказывать и почём.
      • ПРАВА ФРАКЦИЙ  — кому разрешено оказывать услуги и выставлять счета.
      • РЕЕСТР СЧЕТОВ  — выставленные счета и их оплата через банкомат.

    Деньги ходят так же, как в штрафах (sh_grm_wanted_fines.lua):
    оплата списывается через экономику, доля уходит в бюджет фракции-
    исполнителя, остаток — в казну государства. Проценты настраиваются.

    Данные:
      data/grm_services/services.json  { version=1, services={...}, access={...} }
      data/grm_services/invoices.json  { version=1, invoices={...}, nextID=N }

    Ключ плательщика — GRM.Identity.CharacterKey (SteamID64:charN),
    поэтому счета переживают перезаход и привязаны к персонажу, а не
    к аккаунту.

    Заявки на создание организаций подаются ВНЕ игры (Discord) — здесь
    только то, что происходит после одобрения: админ создал фракцию и
    выдал ей доступы, дальше она работает сама.
----------------------------------------------------------------------]]

if CLIENT then return end

GRM = GRM or {}
GRM.Services = GRM.Services or {}

local S = GRM.Services
S.Version = "1.1.0"

local DIR       = "grm_services"
local FILE_SRV  = "grm_services/services.json"
local FILE_INV  = "grm_services/invoices.json"

S.Catalog  = S.Catalog  or {}   -- id -> запись услуги
S.Access   = S.Access   or {}   -- имя фракции -> права
S.Invoices = S.Invoices or {}   -- массив счетов (порядок = хронология)
S._nextInvoice = S._nextInvoice or 1

-----------------------------------------------------------------------
-- Конфигурация
-----------------------------------------------------------------------
S.Config = S.Config or {
    MaxInvoices        = 4000,   -- потолок реестра (старые закрытые вытесняются)
    MaxUnpaidPerChar   = 30,     -- сколько неоплаченных счетов можно навесить
    MaxAmount          = 5000000,-- потолок суммы одного счёта
    MaxServices        = 400,    -- потолок каталога
    -- доля оплаты, уходящая в бюджет фракции-исполнителя (остаток — государству)
    ProviderShare      = 0.80,
    -- лимит суммы счёта по умолчанию для фракции без явной настройки
    DefaultMaxInvoice  = 100000,
    SuperAdminBypass   = true,
}

--- Категории услуг. Права фракции выдаются по категориям.
S.Categories = S.Categories or {
    { id = "education", name = "Образование",            color = { 120, 190, 255 } },
    { id = "medical",   name = "Медицина",               color = { 255, 130, 140 } },
    { id = "legal",     name = "Юридические услуги",     color = { 200, 170, 255 } },
    { id = "utility",   name = "Коммунальные услуги",    color = { 150, 220, 160 } },
    { id = "transport", name = "Транспорт и лицензии",   color = { 255, 200, 110 } },
    { id = "state",     name = "Государственные сборы",  color = { 230, 230, 240 } },
    { id = "other",     name = "Прочее",                 color = { 180, 180, 190 } },
}

function S.CategoryName(id)
    for _, c in ipairs(S.Categories) do
        if c.id == id then return c.name end
    end
    return "Прочее"
end

function S.CategoryExists(id)
    for _, c in ipairs(S.Categories) do
        if c.id == id then return true end
    end
    return false
end

-----------------------------------------------------------------------
-- Утилиты
-----------------------------------------------------------------------
local function ensure()
    if not file.IsDir(DIR, "DATA") then file.CreateDir(DIR) end
end

local function jsonT(s)
    -- третий аргумент true: ключи-SteamID64 не должны превратиться в числа
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

--- Битый json не затираем: уводим в копию, чтобы данные можно было спасти.
local function backupCorrupt(path)
    local raw = file.Read(path, "DATA")
    if not raw or raw == "" then return end
    file.Write(path .. ".corrupt." .. os.time(), raw)
end

-- Ключ персонажа — канон ядра (§5.2.6): одна реализация на проект,
-- ранняя привязка безопасна, sh_01_grm_core.lua грузится первым.
local charKey = GRM.CharKey
S.CharKey = charKey

local function findPlayerByKey(k)
    k = tostring(k or "")
    if k == "" then return nil end
    for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
        if IsValid(p) and (charKey(p) == k or p:SteamID64() == k) then return p end
    end
end
S.FindPlayer = findPlayerByKey

-----------------------------------------------------------------------
-- Реестр персонажей (не только онлайн)
-----------------------------------------------------------------------
--[[
    Диплом выдаётся ПЕРСОНАЖУ, а не сессии игрока. Раньше выбор
    выпускника строился из player.GetAll(), поэтому вручить документ
    можно было только тому, кто прямо сейчас стоит рядом с терминалом,
    а после перезахода в другого персонажа диплом «уезжал» не туда.

    Источники, сливаемые в один список (ключ — CharacterKey):
      1) онлайн-игроки          — самое свежее имя и признак online;
      2) реестр паспортов       — GRM.Documents.Registry.passports,
                                  здесь лежат офлайн-персонажи с ФИО;
      3) составы фракций        — Members[CharacterKey], чтобы курсант
                                  без паспорта тоже был виден.
    Имя выбирается по приоритету: паспорт (ФИО) → RP-ник → Nick.
]]
function S.CharacterRegistry()
    local out, byKey = {}, {}

    local function put(key, data)
        key = tostring(key or "")
        if key == "" or not key:match(":char[1-3]$") then return end
        local rec = byKey[key]
        if not rec then
            rec = { key = key, name = "", rpName = "", passport = "", faction = "", online = false }
            byKey[key] = rec
            out[#out + 1] = rec
        end
        for k, v in pairs(data or {}) do
            if v ~= nil and v ~= "" and (rec[k] == nil or rec[k] == "" or rec[k] == false) then
                rec[k] = v
            end
        end
    end

    -- 1) онлайн
    for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
        if IsValid(p) and p:IsPlayer() then
            local rp = p.GetNWString and p:GetNWString("GRM_RPName", "") or ""
            put(charKey(p), {
                rpName  = rp ~= "" and rp or p:Nick(),
                name    = rp ~= "" and rp or p:Nick(),
                online  = true,
                steamID = tostring(p:SteamID64() or ""),
            })
        end
    end

    -- 2) паспорта (офлайн-персонажи)
    local DOC = GRM.Documents
    local passports = DOC and istable(DOC.Registry) and istable(DOC.Registry.passports) and DOC.Registry.passports
    if passports then
        for key, rec in pairs(passports) do
            if istable(rec) then
                local full = tostring(rec.fullName or "")
                put(key, {
                    passport = full,
                    name     = full,
                    steamID  = tostring(rec.steamID64 or ""),
                })
                -- паспортное ФИО важнее временного ника
                local r = byKey[tostring(key)]
                if r and full ~= "" then r.name = full end
            end
        end
    end

    -- 3) составы фракций
    if Factions then
        for fname, f in pairs(Factions) do
            if istable(f) and istable(f.Members) then
                for key, _ in pairs(f.Members) do
                    put(key, { faction = fname })
                    local r = byKey[tostring(key)]
                    if r and (r.faction == "" or r.faction == nil) then r.faction = fname end
                end
            end
        end
    end

    for _, rec in ipairs(out) do
        if rec.name == "" then rec.name = rec.key end
    end
    table.sort(out, function(a, b)
        if a.online ~= b.online then return a.online end
        return tostring(a.name):lower() < tostring(b.name):lower()
    end)
    return out
end

--- Отображаемое имя персонажа по ключу (работает и для офлайн).
function S.CharacterName(key)
    key = tostring(key or "")
    if key == "" then return "—" end
    local p = findPlayerByKey(key)
    local DOC = GRM.Documents
    local pass = DOC and istable(DOC.Registry) and istable(DOC.Registry.passports)
        and DOC.Registry.passports[key]
    if istable(pass) and tostring(pass.fullName or "") ~= "" then return tostring(pass.fullName) end
    if IsValid(p) then
        local rp = p.GetNWString and p:GetNWString("GRM_RPName", "") or ""
        return rp ~= "" and rp or p:Nick()
    end
    return key
end

local function notify(p, msg, r, g, b)
    if not IsValid(p) then return end
    if GRM.Notify then GRM.Notify(p, msg, r or 120, g or 200, b or 255)
    else p:ChatPrint("[Госуслуги] " .. msg) end
end
S.Notify = notify

local function money(v)
    if GRM.FormatMoney then return GRM.FormatMoney(v) end
    return string.Comma(math.floor(tonumber(v) or 0)) .. " GRM"
end
S.Money = money

-- Задача 10: лимит в символах, а не в байтах — иначе кириллица режется
-- пополам (названия услуг, назначения платежа, примечания к счетам).
local function trim(s, n)
    s = string.Trim(tostring(s or ""))
    if n then
        if GRM and GRM.Utf8Sub then s = GRM.Utf8Sub(s, n)
        else s = string.sub(s, 1, n) end
    end
    return s
end

--- Фракция игрока (имя, запись). Единый способ на весь модуль.
function S.FactionOf(ply)
    if not IsValid(ply) then return nil end
    if FactionsAPI and isfunction(FactionsAPI.GetPlayerFaction) then
        local n = FactionsAPI.GetPlayerFaction(ply)
        if n and n ~= "" then return n, Factions and Factions[n] end
    end
    if not Factions then return nil end
    local ck = charKey(ply)
    for name, f in pairs(Factions) do
        if istable(f) and istable(f.Members) then
            if (GRM.Identity and isfunction(GRM.Identity.FactionMember) and GRM.Identity.FactionMember(f, ply))
                or f.Members[ck] or f.Members[ply:SteamID()] or f.Members[ply:SteamID64()] then
                return name, f
            end
        end
    end
    return nil
end

function S.IsLeaderOf(ply, factionName)
    if not IsValid(ply) then return false end
    local f = Factions and Factions[factionName]
    if not istable(f) then return false end
    local ck = charKey(ply)
    if tostring(f.Leader or "") == ck then return true end
    if tostring(f.Leader or "") == tostring(ply:SteamID64() or "") then return true end
    local mem = (GRM.Identity and isfunction(GRM.Identity.FactionMember) and GRM.Identity.FactionMember(f, ply))
        or (istable(f.Members) and (f.Members[ck] or f.Members[ply:SteamID()] or f.Members[ply:SteamID64()]))
    local leaderRole = f.LeaderRoleName or "Лидер"
    return istable(mem) and (mem.Role == leaderRole or mem.Role == "Лидер")
end

-----------------------------------------------------------------------
-- Права фракций
-----------------------------------------------------------------------
--[[
    Запись доступа:
    {
        canService  = true,   -- может оказывать услуги (вести каталог)
        canInvoice  = true,   -- может выставлять счета
        canDiploma  = false,  -- может выдавать дипломы (см. sh_grm_diplomas)
        categories  = { education = true, ... },  -- пусто = все разрешённые
        maxInvoice  = 100000, -- потолок суммы одного счёта
        institution = "",     -- официальное название для бланков/дипломов
        note        = "",
    }

    Быстрые переключатели продублированы флагами прямо во фракции
    (f.ServiceAccess / f.InvoiceAccess / f.DiplomaAccess) — их видно в
    меню фракций рядом с «доступом к волне». Здесь — детальная настройка.
]]
local function defaultAccess()
    return {
        canService  = false,
        canInvoice  = false,
        canDiploma  = false,
        categories  = {},
        maxInvoice  = S.Config.DefaultMaxInvoice,
        institution = "",
        note        = "",
    }
end
S.DefaultAccess = defaultAccess

function S.AccessOf(factionName)
    factionName = tostring(factionName or "")
    if factionName == "" then return defaultAccess() end
    local a = S.Access[factionName]
    if not istable(a) then
        a = defaultAccess()
        S.Access[factionName] = a
    end
    a.categories = istable(a.categories) and a.categories or {}
    a.maxInvoice = math.max(0, math.floor(tonumber(a.maxInvoice) or S.Config.DefaultMaxInvoice))
    -- Флаг во фракции — «включатель»: снят в меню фракций → выключено и здесь.
    local f = Factions and Factions[factionName]
    if istable(f) then
        if f.ServiceAccess ~= nil then a.canService = a.canService and f.ServiceAccess ~= false end
        if f.InvoiceAccess ~= nil then a.canInvoice = a.canInvoice and f.InvoiceAccess ~= false end
        if f.DiplomaAccess ~= nil then a.canDiploma = a.canDiploma and f.DiplomaAccess ~= false end
    end
    return a
end

--- Изменение прав фракции (только суперадмин вызывает это извне).
function S.SetAccess(factionName, patch)
    factionName = tostring(factionName or "")
    if factionName == "" then return false, "Не указана фракция" end
    if Factions and not Factions[factionName] then return false, "Фракция не найдена" end
    local a = S.Access[factionName] or defaultAccess()
    patch = istable(patch) and patch or {}

    if patch.canService ~= nil then a.canService = patch.canService == true end
    if patch.canInvoice ~= nil then a.canInvoice = patch.canInvoice == true end
    if patch.canDiploma ~= nil then a.canDiploma = patch.canDiploma == true end
    if patch.maxInvoice ~= nil then
        a.maxInvoice = math.Clamp(math.floor(tonumber(patch.maxInvoice) or 0), 0, S.Config.MaxAmount)
    end
    if patch.institution ~= nil then a.institution = trim(patch.institution, 96) end
    if patch.note ~= nil then a.note = trim(patch.note, 160) end
    if istable(patch.categories) then
        local c = {}
        for id, on in pairs(patch.categories) do
            if on == true and S.CategoryExists(id) then c[id] = true end
        end
        a.categories = c
    end

    S.Access[factionName] = a
    -- Держим флаги фракции в согласии с детальной настройкой.
    local f = Factions and Factions[factionName]
    if istable(f) then
        f.ServiceAccess = a.canService
        f.InvoiceAccess = a.canInvoice
        f.DiplomaAccess = a.canDiploma
        if FactionsAPI and isfunction(FactionsAPI.Save) then FactionsAPI.Save() end
    end
    S.SaveServices()
    hook.Run("GRM_ServiceAccessChanged", factionName, a)
    return true, a
end

--[[ Список организаций, которые ВПРАВЕ быть исполнителем услуги.
     Раньше исполнитель нигде не показывался: игрок не понимал, откуда он
     берётся и как его сменить. Теперь список отдаётся в банкомат, где из
     него выбирают явно (суперадмин) либо видят своё название (лидер).
     @param category  необязательный фильтр по категории услуг
     @return массив { name, institution, canService, canInvoice, maxInvoice } ]]
function S.ProviderList(category)
    local out = {}
    if not Factions then return out end
    for name, f in pairs(Factions) do
        if istable(f) then
            local a = S.AccessOf(name)
            local fits = a.canService
            if fits and category and category ~= "" then
                fits = S.FactionCanService(name, category)
            end
            if fits then
                out[#out + 1] = {
                    name        = name,
                    institution = a.institution or "",
                    canService  = a.canService == true,
                    canInvoice  = a.canInvoice == true,
                    maxInvoice  = a.maxInvoice or 0,
                }
            end
        end
    end
    table.sort(out, function(x, y) return x.name < y.name end)
    return out
end

--- Может ли фракция оказывать услуги данной категории.
function S.FactionCanService(factionName, category)
    local a = S.AccessOf(factionName)
    if not a.canService then return false end
    if not category or category == "" then return true end
    if table.Count(a.categories) == 0 then return true end
    return a.categories[category] == true
end

--- Может ли игрок выставлять счета от имени своей фракции.
-- @return можно, имя фракции, причина отказа
function S.CanInvoice(ply)
    if not IsValid(ply) then return false, nil, "Нет игрока" end
    if S.Config.SuperAdminBypass and ply:IsSuperAdmin() then
        local n = S.FactionOf(ply)
        return true, n or "Администрация", nil
    end
    local name = S.FactionOf(ply)
    if not name then return false, nil, "Вы не состоите в организации" end
    local a = S.AccessOf(name)
    if not a.canInvoice then
        return false, name, "Организации «" .. name .. "» не выдан доступ на выставление счетов"
    end
    return true, name, nil
end

-----------------------------------------------------------------------
-- Загрузка / сохранение
-----------------------------------------------------------------------
local function normalizeService(raw)
    if not istable(raw) then return nil end
    local id = trim(raw.id, 48)
    if id == "" then return nil end
    return {
        id       = id,
        name     = trim(raw.name, 96) ~= "" and trim(raw.name, 96) or id,
        category = S.CategoryExists(raw.category) and raw.category or "other",
        price    = math.Clamp(math.floor(tonumber(raw.price) or 0), 0, S.Config.MaxAmount),
        provider = trim(raw.provider, 64),
        desc     = trim(raw.desc, 240),
        enabled  = raw.enabled ~= false,
        created  = math.floor(tonumber(raw.created) or os.time()),
        createdBy = trim(raw.createdBy, 64),
    }
end

function S.LoadServices()
    S.Catalog, S.Access = {}, {}
    if not file.Exists(FILE_SRV, "DATA") then return end
    local t = jsonT(file.Read(FILE_SRV, "DATA") or "")
    if not t then
        backupCorrupt(FILE_SRV)
        print("[GRM Services] services.json повреждён — сохранена копия, начинаем с чистого каталога")
        return
    end
    local list = istable(t.services) and t.services or {}
    for _, raw in pairs(list) do
        local n = normalizeService(raw)
        if n then S.Catalog[n.id] = n end
    end
    local acc = istable(t.access) and t.access or {}
    for name, raw in pairs(acc) do
        if istable(raw) then
            local a = defaultAccess()
            a.canService  = raw.canService == true
            a.canInvoice  = raw.canInvoice == true
            a.canDiploma  = raw.canDiploma == true
            a.maxInvoice  = math.max(0, math.floor(tonumber(raw.maxInvoice) or S.Config.DefaultMaxInvoice))
            a.institution = trim(raw.institution, 96)
            a.note        = trim(raw.note, 160)
            a.categories  = {}
            if istable(raw.categories) then
                for id, on in pairs(raw.categories) do
                    if on == true and S.CategoryExists(id) then a.categories[id] = true end
                end
            end
            S.Access[tostring(name)] = a
        end
    end
end

function S.SaveServices()
    local list = {}
    for _, s in pairs(S.Catalog) do list[#list + 1] = s end
    return write(FILE_SRV, { version = 1, services = list, access = S.Access })
end

local function normalizeInvoice(raw)
    if not istable(raw) then return nil end
    local id = math.floor(tonumber(raw.id) or 0)
    if id <= 0 then return nil end
    local amount = math.Clamp(math.floor(tonumber(raw.amount) or 0), 0, S.Config.MaxAmount)
    local paid   = math.Clamp(math.floor(tonumber(raw.paid) or 0), 0, amount)
    local status = tostring(raw.status or "unpaid")
    if status ~= "unpaid" and status ~= "paid" and status ~= "cancelled" then status = "unpaid" end
    return {
        id         = id,
        target     = charKey(raw.target),
        targetName = trim(raw.targetName, 64),
        issuer     = tostring(raw.issuer or ""),
        issuerName = trim(raw.issuerName, 64),
        faction    = trim(raw.faction, 64),
        serviceID  = trim(raw.serviceID, 48),
        title      = trim(raw.title, 120),
        amount     = amount,
        paid       = paid,
        status     = status,
        issued     = math.floor(tonumber(raw.issued) or os.time()),
        closed=raw.closed and math.floor(tonumber(raw.closed))or nil,paidAt=raw.paidAt and math.floor(tonumber(raw.paidAt))or nil,lastPaidAt=raw.lastPaidAt and math.floor(tonumber(raw.lastPaidAt))or nil,
        atmNumber=math.max(0,math.floor(tonumber(raw.atmNumber)or 0)),atmName=trim(raw.atmName,64),orderSource=trim(raw.orderSource,24),
        note=trim(raw.note,200),
    }
end

function S.LoadInvoices()
    S.Invoices, S._nextInvoice = {}, 1
    if not file.Exists(FILE_INV, "DATA") then return end
    local t = jsonT(file.Read(FILE_INV, "DATA") or "")
    if not t then
        backupCorrupt(FILE_INV)
        print("[GRM Services] invoices.json повреждён — сохранена копия, реестр счетов пуст")
        return
    end
    -- толерантно: и { invoices = {...} }, и голый массив
    local list = istable(t.invoices) and t.invoices or (istable(t) and t or {})
    local maxID = 0
    for _, raw in pairs(list) do
        local n = normalizeInvoice(raw)
        if n then
            S.Invoices[#S.Invoices + 1] = n
            if n.id > maxID then maxID = n.id end
        end
    end
    table.sort(S.Invoices, function(a, b) return (a.issued or 0) < (b.issued or 0) end)
    S._nextInvoice = math.max(maxID + 1, math.floor(tonumber(t.nextID) or 1))
end

function S.SaveInvoices()
    -- вытеснение: сначала уходят закрытые счета, неоплаченные держим до конца
    local maxRec = S.Config.MaxInvoices
    while #S.Invoices > maxRec do
        local removed = false
        for i = 1, #S.Invoices do
            if S.Invoices[i].status ~= "unpaid" then
                table.remove(S.Invoices, i)
                removed = true
                break
            end
        end
        if not removed then table.remove(S.Invoices, 1) end
    end
    return write(FILE_INV, { version = 1, invoices = S.Invoices, nextID = S._nextInvoice })
end

-----------------------------------------------------------------------
-- Каталог услуг
-----------------------------------------------------------------------
local function slug(text)
    local s = string.lower(trim(text, 64))
    s = s:gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
    if s == "" then s = "srv" end
    return s
end

--- Создание/обновление услуги.
-- @param actor игрок (или nil для системных вызовов)
function S.UpsertService(actor, data)
    data = istable(data) and data or {}
    local name = trim(data.name, 96)
    if name == "" then return false, "Не указано название услуги" end

    local category = S.CategoryExists(data.category) and data.category or "other"
    local price = math.Clamp(math.floor(tonumber(data.price) or 0), 0, S.Config.MaxAmount)

    local provider = trim(data.provider, 64)
    local isSuper = IsValid(actor) and actor:IsSuperAdmin()
    if IsValid(actor) and not isSuper then
        local fname = S.FactionOf(actor)
        if not fname then return false, "Вы не состоите в организации" end
        if not S.IsLeaderOf(actor, fname) then
            return false, "Каталогом услуг управляет лидер организации"
        end
        if not S.FactionCanService(fname, category) then
            return false, "Организации не выдан доступ на услуги категории «" .. S.CategoryName(category) .. "»"
        end
        provider = fname -- от чужого имени услугу не завести
    end
    if provider == "" then
        return false, "Не указан исполнитель услуги: выберите организацию в поле «Исполнитель»"
    end
    -- Суперадмин заводит услуги за любую организацию, но не за несуществующую:
    -- иначе в витрине появляется исполнитель, которому некуда платить.
    if isSuper and Factions and not Factions[provider] then
        return false, ("Организация «%s» не найдена: выберите исполнителя из списка"):format(provider)
    end

    local id = trim(data.id, 48)
    local existing = id ~= "" and S.Catalog[id] or nil
    if existing and IsValid(actor) and not isSuper and existing.provider ~= provider then
        return false, "Эта услуга принадлежит другой организации"
    end
    if not existing then
        if table.Count(S.Catalog) >= S.Config.MaxServices then
            return false, "Каталог переполнен"
        end
        if id == "" then
            local base = slug(provider) .. "_" .. slug(name)
            id = base
            local n = 2
            while S.Catalog[id] do id = base .. "_" .. n n = n + 1 end
        end
    end

    local rec = existing or {
        id = id,
        created = os.time(),
        createdBy = IsValid(actor) and actor:Nick() or "система",
    }
    rec.id       = id
    rec.name     = name
    rec.category = category
    rec.price    = price
    rec.provider = provider
    rec.desc     = trim(data.desc, 240)
    rec.enabled  = data.enabled ~= false

    S.Catalog[id] = rec
    S.SaveServices()
    hook.Run("GRM_ServiceUpserted", actor, rec)
    return true, rec
end

function S.DeleteService(actor, id)
    id = trim(id, 48)
    local rec = S.Catalog[id]
    if not rec then return false, "Услуга не найдена" end
    if IsValid(actor) and not actor:IsSuperAdmin() then
        local fname = S.FactionOf(actor)
        if rec.provider ~= fname then return false, "Эта услуга принадлежит другой организации" end
        if not S.IsLeaderOf(actor, fname) then return false, "Каталогом услуг управляет лидер организации" end
    end
    S.Catalog[id] = nil
    S.SaveServices()
    hook.Run("GRM_ServiceDeleted", actor, rec)
    return true, rec
end

--- Список услуг для витрины банкомата.
-- @param filter { category=..., provider=..., onlyEnabled=true, query=... }
function S.ListServices(filter)
    filter = istable(filter) and filter or {}
    local out = {}
    for _, rec in pairs(S.Catalog) do
        local ok = true
        if filter.onlyEnabled ~= false and rec.enabled == false then ok = false end
        if ok and filter.category and filter.category ~= "" and rec.category ~= filter.category then ok = false end
        if ok and filter.provider and filter.provider ~= "" and rec.provider ~= filter.provider then ok = false end
        if ok and filter.query and filter.query ~= "" then
            local q = string.lower(filter.query)
            if not (string.find(string.lower(rec.name), q, 1, true)
                or string.find(string.lower(rec.provider or ""), q, 1, true)) then ok = false end
        end
        if ok then out[#out + 1] = rec end
    end
    table.sort(out, function(a, b)
        if a.category ~= b.category then return a.category < b.category end
        return (a.name or "") < (b.name or "")
    end)
    return out
end

function S.ServiceByID(id) return S.Catalog[trim(id, 48)] end

-----------------------------------------------------------------------
-- Счета
-----------------------------------------------------------------------
function S.InvoiceByID(id)
    id = math.floor(tonumber(id) or 0)
    for _, rec in ipairs(S.Invoices) do
        if rec.id == id then return rec end
    end
end

--- Счета персонажа.
function S.InvoicesFor(target, onlyUnpaid)
    local k = charKey(target)
    local out = {}
    for _, rec in ipairs(S.Invoices) do
        if rec.target == k and (not onlyUnpaid or rec.status == "unpaid") then
            out[#out + 1] = rec
        end
    end
    return out
end

--- Суммарный долг персонажа по счетам.
function S.DebtOf(target)
    local sum = 0
    for _, rec in ipairs(S.InvoicesFor(target, true)) do
        sum = sum + (rec.amount - rec.paid)
    end
    return sum
end

--- Счета, выставленные фракцией (для кабинета организации).
function S.InvoicesByFaction(factionName,limit)
    limit=math.floor(tonumber(limit)or 120);local out={};for i=#S.Invoices,1,-1 do local rec=S.Invoices[i];if rec.faction==factionName then out[#out+1]=rec;if#out>=limit then break end end end;return out
end
function S.OrderedServicesForFaction(factionName,limit)
    local out={};for _,rec in ipairs(S.InvoicesByFaction(factionName,limit or 150))do if tostring(rec.serviceID or"")~=""then out[#out+1]=rec end end
    table.sort(out,function(a,b)return(tonumber(a.issued)or 0)>(tonumber(b.issued)or 0)end);return out
end

--- Выставление счёта.
-- @param opts { serviceID, title, amount, note, faction }
function S.IssueInvoice(issuer, target, opts)
    opts = istable(opts) and opts or {}

    local can, fname, why = S.CanInvoice(issuer)
    if not can then return false, why end

    local tKey = charKey(target)
    if tKey == "" then return false, "Не указан плательщик" end
    if IsValid(issuer) and tKey == charKey(issuer) and not issuer:IsSuperAdmin() then
        return false, "Нельзя выставить счёт самому себе"
    end

    --[[ Организация-исполнитель счёта: именно ей уйдёт доля оплаты.
         Задача 10: раньше поле принималось от кого угодно — сотрудник мог
         выставить счёт «от имени» чужой организации и увести туда деньги.
         Теперь чужое имя вправе указать только суперадмин. ]]
    local isSuperIssuer = IsValid(issuer) and issuer:IsSuperAdmin()
    local faction = trim(opts.faction, 64)
    if faction == "" then
        faction = fname or ""
    elseif not isSuperIssuer and faction ~= (fname or "") then
        return false, "Счёт выставляется только от имени вашей организации"
    end

    local svc = opts.serviceID and S.ServiceByID(opts.serviceID) or nil
    local amount = math.floor(tonumber(opts.amount) or (svc and svc.price) or 0)
    local title  = trim(opts.title, 120)
    if svc then
        if title == "" then title = svc.name end
        -- чужую услугу как основание не берём (суперадмину можно всё)
        if svc.provider ~= faction and not (IsValid(issuer) and issuer:IsSuperAdmin()) then
            return false, "Эта услуга принадлежит организации «" .. tostring(svc.provider) .. "»"
        end
    end
    if title == "" then return false, "Не указано назначение счёта" end
    if amount <= 0 then return false, "Сумма должна быть больше нуля" end
    if amount > S.Config.MaxAmount then return false, "Сумма превышает допустимый предел" end

    local isSuper = IsValid(issuer) and issuer:IsSuperAdmin()
    if not isSuper then
        local a = S.AccessOf(faction)
        if a.maxInvoice > 0 and amount > a.maxInvoice then
            return false, ("Предел суммы счёта для организации: %s"):format(money(a.maxInvoice))
        end
        local unpaid = #S.InvoicesFor(tKey, true)
        if unpaid >= S.Config.MaxUnpaidPerChar then
            return false, "У плательщика слишком много неоплаченных счетов"
        end
    end

    local rec = {
        id         = S._nextInvoice,
        target     = tKey,
        targetName = trim(opts.targetName, 64),
        issuer     = IsValid(issuer) and charKey(issuer) or "система",
        issuerName = IsValid(issuer) and issuer:Nick() or "система",
        faction    = faction,
        serviceID  = svc and svc.id or "",
        title      = title,
        amount     = amount,
        paid       = 0,
        status     = "unpaid",
        issued     = os.time(),
        note       = trim(opts.note, 200),
    }
    if rec.targetName == "" then
        -- имя берём из реестра персонажей: для офлайн это ФИО паспорта,
        -- а не сырой ключ вида 7656…:char1
        rec.targetName = S.CharacterName(tKey)
    end

    S._nextInvoice = S._nextInvoice + 1
    S.Invoices[#S.Invoices + 1] = rec
    S.SaveInvoices()

    local tp = findPlayerByKey(tKey)
    if IsValid(tp) then
        notify(tp, ("Вам выставлен счёт №%d: %s — %s. Оплата в банкомате.")
            :format(rec.id, rec.title, money(rec.amount)), 255, 200, 120)
    end
    hook.Run("GRM_InvoiceIssued", issuer, rec)
    return true, rec
end

--[[ Куда уходят деньги с оплаченного счёта:
     доля исполнителя — в бюджет фракции, остаток — в казну.
     Если фракции нет (счёт от администрации) — всё в казну. ]]
local function distribute(rec, sum, payerName)
    if sum <= 0 then return end
    local E = GRM.Economy
    local share = math.Clamp(tonumber(S.Config.ProviderShare) or 0.8, 0, 1)
    local toFaction = 0

    if rec.faction ~= "" and Factions and Factions[rec.faction] and isfunction(GRM.FactionBudgetAdd) then
        toFaction = math.floor(sum * share)
        if toFaction > 0 then
            GRM.FactionBudgetAdd(rec.faction, toFaction,
                ("Оплата счёта №%d (%s)"):format(rec.id, payerName or "плательщик"))
        end
    end
    local toState = sum - toFaction
    if toState > 0 and E and isfunction(E.StateAdd) then
        E.StateAdd(toState, ("Оплата счёта №%d (%s)"):format(rec.id, payerName or "плательщик"))
    end
end
S.Distribute = distribute

--- Оплата счёта. source: "cash" (наличные) | "bank" (счёт в банке).
-- @return true, внесённая сумма | false, причина
function S.PayInvoice(ply, id, amount, source)
    if not (IsValid(ply) and ply:IsPlayer()) then return false, "Нет игрока" end
    local rec = S.InvoiceByID(id)
    if not rec then return false, "Счёт №" .. tostring(id) .. " не найден" end
    if rec.status ~= "unpaid" then return false, "Этот счёт уже закрыт" end
    if rec.target ~= charKey(ply) then return false, "Это не ваш счёт" end

    local due = rec.amount - rec.paid
    amount = math.floor(tonumber(amount) or due)
    if amount <= 0 then return false, "Сумма должна быть больше нуля" end
    amount = math.min(amount, due)

    local ok, err = GRM.Services.Charge(ply, amount, source, ("Оплата счёта №%d"):format(rec.id))
    if not ok then return false, err end

    rec.paid=rec.paid+amount;rec.lastPaidAt=os.time()
    if rec.paid>=rec.amount then rec.status="paid";rec.closed=os.time();rec.paidAt=rec.closed end
    S.SaveInvoices()
    distribute(rec, amount, ply:Nick())

    if rec.status == "paid" then
        notify(ply, ("Счёт №%d оплачен полностью (%s)."):format(rec.id, money(rec.amount)), 120, 220, 140)
    else
        notify(ply, ("Внесено %s по счёту №%d. Остаток: %s")
            :format(money(amount), rec.id, money(rec.amount - rec.paid)), 200, 220, 140)
    end
    hook.Run("GRM_InvoicePaid", ply, rec, amount)
    return true, amount
end

function S.CancelInvoice(actor, id, reason)
    local rec = S.InvoiceByID(id)
    if not rec then return false, "Счёт не найден" end
    if rec.status == "cancelled" then return false, "Счёт уже аннулирован" end

    if IsValid(actor) and not actor:IsSuperAdmin() then
        local fname = S.FactionOf(actor)
        if rec.faction ~= fname then return false, "Счёт выставлен другой организацией" end
        if not S.IsLeaderOf(actor, fname) then return false, "Аннулировать счета может лидер организации" end
    end

    rec.status = "cancelled"
    rec.closed = os.time()
    rec.note = trim((rec.note ~= "" and (rec.note .. " | ") or "") .. "Аннулирован: " .. tostring(reason or "без причины"), 200)
    S.SaveInvoices()

    local tp = findPlayerByKey(rec.target)
    if IsValid(tp) then
        notify(tp, ("Счёт №%d (%s) аннулирован."):format(rec.id, rec.title), 200, 200, 200)
    end
    hook.Run("GRM_InvoiceCancelled", actor, rec)
    return true, rec
end

--- Удаление счёта из реестра (только суперадмин — полный доступ).
function S.DeleteInvoice(actor, id)
    if IsValid(actor) and not actor:IsSuperAdmin() then return false, "Только суперадмин" end
    id = math.floor(tonumber(id) or 0)
    for i = #S.Invoices, 1, -1 do
        if S.Invoices[i].id == id then
            local rec = S.Invoices[i]
            table.remove(S.Invoices, i)
            S.SaveInvoices()
            hook.Run("GRM_InvoiceDeleted", actor, rec)
            return true, rec
        end
    end
    return false, "Счёт не найден"
end

--- Правка счёта суперадмином (сумма/назначение/статус).
function S.AdminEditInvoice(actor, id, patch)
    if not (IsValid(actor) and actor:IsSuperAdmin()) then return false, "Только суперадмин" end
    local rec = S.InvoiceByID(id)
    if not rec then return false, "Счёт не найден" end
    patch = istable(patch) and patch or {}

    if patch.amount ~= nil then
        rec.amount = math.Clamp(math.floor(tonumber(patch.amount) or rec.amount), 0, S.Config.MaxAmount)
        if rec.paid > rec.amount then rec.paid = rec.amount end
    end
    if patch.title ~= nil then rec.title = trim(patch.title, 120) end
    if patch.note ~= nil then rec.note = trim(patch.note, 200) end
    if patch.status ~= nil then
        local st = tostring(patch.status)
        if st == "unpaid" or st == "paid" or st == "cancelled" then
            rec.status = st
            rec.closed = (st == "unpaid") and nil or os.time()
            if st == "paid" then rec.paid = rec.amount end
        end
    end
    S.SaveInvoices()
    hook.Run("GRM_InvoiceEdited", actor, rec)
    return true, rec
end

-----------------------------------------------------------------------
-- Единая касса: списание наличными или со счёта
-----------------------------------------------------------------------
--[[ Штрафы (F.Pay) умеют брать только наличные. В банкомате логично
     платить со счёта, поэтому здесь общий вход: source="bank" списывает
     со счёта в банке, "cash" — из кармана, "auto" — сначала счёт, потом
     наличные. Возврат: true | false, причина. ]]
function S.Charge(ply, amount, source, reason)
    amount = math.floor(tonumber(amount) or 0)
    if not IsValid(ply) or amount <= 0 then return false, "Некорректная сумма" end
    source = tostring(source or "auto")
    local E = GRM.Economy

    local bank = (E and isfunction(E.BankBalance)) and E.BankBalance(ply) or 0
    local cash = isfunction(GRM.GetBalance) and GRM.GetBalance(ply) or 0

    local function takeBank(sum)
        if not (E and isfunction(E.BankTake)) then return false end
        return E.BankTake(ply, sum, reason) == true
    end
    local function takeCash(sum)
        if not isfunction(GRM.TakeMoney) then return false end
        return GRM.TakeMoney(ply, sum, reason) == true
    end

    if source == "bank" then
        if bank < amount then
            return false, ("Недостаточно средств на счёте: нужно %s, на счёте %s"):format(money(amount), money(bank))
        end
        if not takeBank(amount) then return false, "Не удалось списать средства со счёта" end
        return true
    elseif source == "cash" then
        if cash < amount then
            return false, ("Недостаточно наличных: нужно %s, у вас %s"):format(money(amount), money(cash))
        end
        if not takeCash(amount) then return false, "Не удалось списать наличные" end
        return true
    end

    -- auto: сначала счёт, недостающее добираем наличными
    if bank + cash < amount then
        return false, ("Недостаточно средств: нужно %s, доступно %s"):format(money(amount), money(bank + cash))
    end
    local fromBank = math.min(bank, amount)
    if fromBank > 0 and not takeBank(fromBank) then fromBank = 0 end
    local rest = amount - fromBank
    if rest > 0 then
        if not takeCash(rest) then
            -- откат: вернём на счёт то, что уже сняли
            if fromBank > 0 and E and isfunction(E.BankGive) then E.BankGive(ply, fromBank, "Откат оплаты") end
            return false, "Не удалось списать средства"
        end
    end
    return true
end

-----------------------------------------------------------------------
-- Оплата штрафов из банкомата (мост к реестру штрафов)
-----------------------------------------------------------------------
--[[ F.Pay берёт наличные. Чтобы в банкомате можно было гасить штраф со
     счёта, временно подменяем источник: списываем сами, а реестру
     отдаём уже «оплаченные» деньги через его же логику. Проще и честнее
     сделать это переводом наличных: снимаем со счёта → кладём в карман →
     зовём F.Pay. Так вся бухгалтерия штрафов остаётся в одном месте. ]]
function S.PayFine(ply, id, amount, source)
    local F = GRM.Wanted and GRM.Wanted.Fines
    if not (F and isfunction(F.Pay)) then return false, "Реестр штрафов недоступен" end
    if not IsValid(ply) then return false, "Нет игрока" end

    local rec = isfunction(F.ByID) and F.ByID(id) or nil
    if not rec then return false, "Штраф №" .. tostring(id) .. " не найден" end
    if rec.status ~= "unpaid" then return false, "Этот штраф уже закрыт" end

    local due = rec.amount - rec.paid
    amount = math.floor(tonumber(amount) or due)
    if amount <= 0 then return false, "Сумма должна быть больше нуля" end
    amount = math.min(amount, due)

    local E = GRM.Economy
    local cash = isfunction(GRM.GetBalance) and GRM.GetBalance(ply) or 0
    -- не хватает наличных — доливаем со счёта ровно недостающее
    if cash < amount and source ~= "cash" then
        local need = amount - cash
        local bank = (E and isfunction(E.BankBalance)) and E.BankBalance(ply) or 0
        if bank < need then
            return false, ("Недостаточно средств: нужно %s, доступно %s")
                :format(money(amount), money(cash + bank))
        end
        if not (E and isfunction(E.BankTake) and E.BankTake(ply, need, "Оплата штрафа со счёта")) then
            return false, "Не удалось списать средства со счёта"
        end
        if not (isfunction(GRM.GiveMoney) and GRM.GiveMoney(ply, need, "Снятие на оплату штрафа")) then
            -- деньги не пропали: вернём их на счёт
            if E and isfunction(E.BankGive) then E.BankGive(ply, need, "Откат оплаты штрафа") end
            return false, "Не удалось перевести средства для оплаты"
        end
    end

    return F.Pay(ply, id, amount)
end

-----------------------------------------------------------------------
-- Сводка задолженности (для банкомата и терминалов)
-----------------------------------------------------------------------
function S.DebtSummary(target)
    local k = charKey(target)
    local F = GRM.Wanted and GRM.Wanted.Fines
    local fines = (F and isfunction(F.DebtOf)) and F.DebtOf(k) or 0
    local invoices = S.DebtOf(k)
    return {
        fines    = fines,
        invoices = invoices,
        total    = fines + invoices,
    }
end

-----------------------------------------------------------------------
-- Старт
-----------------------------------------------------------------------
local function boot()
    S.LoadServices()
    S.LoadInvoices()
    print(("[GRM Services] v%s загружен: услуг %d, счетов %d")
        :format(S.Version, table.Count(S.Catalog), #S.Invoices))
end

grmBootStart("GRM_Services_Load", "normal", boot)
if GRM and GRM.Services then boot() end
