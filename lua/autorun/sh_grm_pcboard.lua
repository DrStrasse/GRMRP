--[[--------------------------------------------------------------------
    GRM PCBoard v1.0.0 — планшет госслужащего («пробить по базе»)

    Заказ владельца (19.08), концепция CONCEPT_PCBOARD_IDENTITY.md, этап 4.

    Что это. Сотрудник госструктуры на службе командой /pcboard «пробивает»
    человека по базе данных. Справку видит ТОЛЬКО он, окружающие видят
    отыгранное системой РП-действие (/me). Объём справки зависит от уровня
    допуска организации (правоохранительный / комендатура / медицинский /
    спецслужбы / администрация) и точечных галочек блоков.

    Откуда данные. Ниоткуда «из воздуха»: каждый блок — это ПРОВАЙДЕР,
    который читает уже существующий модуль (розыск, штрафы, документы,
    дипломы, транспорт, недвижимость, медицина, организации). Нет модуля на
    сервере — блок просто не появится в справке, ошибок не будет.

    Защита от абьюза: видимое /me, кулдаун, лимит запросов в минуту, журнал
    всех запросов (data/grm_pcboard/log.json + GRM.Audit) и право
    «pcboard.audit» на его просмотр. Скрытый запрос разрешён только
    спецслужбам и всё равно пишется в журнал.

    Настройка: вкладка «Госбаза» в /factions (cl_grm_pcboard_ui.lua),
    хранение data/grm_pcboard/access.json.
----------------------------------------------------------------------]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.PCBoard = GRM.PCBoard or {}
local PB = GRM.PCBoard
PB.Version = "1.0.0"

PB.Net = {
    CARD  = "GRM_PCBoard_Card",
    REQ   = "GRM_PCBoard_AccessReq",
    DATA  = "GRM_PCBoard_AccessData",
    SAVE  = "GRM_PCBoard_AccessSave",
    LOG   = "GRM_PCBoard_Log",
}

-----------------------------------------------------------------------
-- УРОВНИ ДОПУСКА
-----------------------------------------------------------------------
-- rank нужен только для «кто главнее» при показе источника доступа;
-- объём справки задаётся не рангом, а набором блоков уровня.
PB.Levels = {
    none     = { rank = 0, name = "Нет доступа",        short = "—" },
    fire     = { rank = 1, name = "Пожарная служба",    short = "ПОЖ" },
    medical  = { rank = 1, name = "Медицинский",        short = "МЕД" },
    police   = { rank = 2, name = "Правоохранительный", short = "ПРАВ" },
    military = { rank = 2, name = "Комендатура",        short = "КОМ" },
    justice  = { rank = 3, name = "Юстиция",            short = "ЮСТ" },
    special  = { rank = 3, name = "Спецслужбы",         short = "СПЕЦ" },
    admin    = { rank = 4, name = "Администрация",      short = "АДМ" },
}
PB.LevelOrder = { "none", "fire", "medical", "police", "military", "justice", "special", "admin" }

function PB.LevelName(level)
    local row = PB.Levels[tostring(level or "none")]
    return row and row.name or "Нет доступа"
end

function PB.LevelValid(level)
    return PB.Levels[tostring(level or "")] ~= nil
end

-----------------------------------------------------------------------
-- ПРОВАЙДЕРЫ (блоки справки)
-----------------------------------------------------------------------
PB.Providers = PB.Providers or {}
PB.ProviderOrder = PB.ProviderOrder or {}

--- Регистрация блока справки.
--  key     — короткий ключ блока (он же ключ галочки в настройках);
--  def.label   — заголовок блока в справке;
--  def.order   — порядок вывода;
--  def.levels  — на каких уровнях блок включён ПО УМОЛЧАНИЮ;
--  def.collect — function(ctx) -> rows | nil. rows = { {"Поле","Значение"}, … }
function PB.RegisterProvider(key, def)
    key = tostring(key or "")
    if key == "" or not istable(def) then return false end
    def.key = key
    def.label = tostring(def.label or key)
    def.order = tonumber(def.order) or 100
    def.levels = istable(def.levels) and def.levels or {}
    if not PB.Providers[key] then PB.ProviderOrder[#PB.ProviderOrder + 1] = key end
    PB.Providers[key] = def
    return true
end

--- Список блоков в порядке вывода (общий для сервера и клиента-настройщика).
function PB.ProviderList()
    local out = {}
    for _, key in ipairs(PB.ProviderOrder) do
        local def = PB.Providers[key]
        if def then out[#out + 1] = def end
    end
    table.sort(out, function(a, b)
        if a.order == b.order then return a.key < b.key end
        return a.order < b.order
    end)
    return out
end

--- Блок доступен уровню по умолчанию?
function PB.BlockDefault(blockKey, level)
    local def = PB.Providers[tostring(blockKey or "")]
    if not def then return false end
    if level == "admin" then return true end
    return def.levels[tostring(level or "none")] == true
end

--- Итог: показывать блок или нет. overrides — галочки из настроек
--  (true — включить принудительно, false — выключить принудительно).
function PB.BlockAllowed(blockKey, level, overrides)
    if level == "none" or level == nil then return false end
    -- Ловушка Lua: «a and t[k] or nil» съедает false, а именно false здесь и
    -- означает «блок принудительно закрыт». Поэтому читаем значение явно.
    if istable(overrides) then
        local ov = overrides[tostring(blockKey or "")]
        if ov == true then return true end
        if ov == false then return false end
    end
    return PB.BlockDefault(blockKey, level)
end

-----------------------------------------------------------------------
-- НАСТРОЙКИ ДОСТУПА
-----------------------------------------------------------------------
PB.DefaultSettings = {
    cooldown    = 8,      -- секунд между запросами
    perMinute   = 3,      -- запросов в минуту
    delay       = 3,      -- «пробитие» занимает столько секунд
    requireDuty = true,   -- только на службе
    allowHidden = true,   -- спецслужбам можно скрытый запрос
    meStart     = "достаёт служебный планшет и пробивает человека по базе данных.",
    meDone      = "планшет коротко пиликает — запрос обработан.",
    logSize     = 400,
}

PB.Config = PB.Config or { settings = table.Copy(PB.DefaultSettings), factions = {} }

local function cleanBlocks(src)
    local out = {}
    for key, value in pairs(istable(src) and src or {}) do
        if isstring(key) and (value == true or value == false) then
            out[string.sub(key, 1, 48)] = value
        end
    end
    return out
end

local function cleanNode(src)
    src = istable(src) and src or {}
    local node = { blocks = cleanBlocks(src.blocks) }
    if PB.LevelValid(src.level) then node.level = tostring(src.level) end
    return node
end

--- Приведение конфигурации к строгому виду: сюда попадает и то, что пришло
--  из сети, и то, что прочитано из файла. Один слой проверки на всех.
function PB.Normalize(cfg)
    cfg = istable(cfg) and cfg or {}
    local out = { settings = {}, factions = {} }

    local s = istable(cfg.settings) and cfg.settings or {}
    local d = PB.DefaultSettings
    out.settings = {
        cooldown    = math.Clamp(math.floor(tonumber(s.cooldown) or d.cooldown), 0, 300),
        perMinute   = math.Clamp(math.floor(tonumber(s.perMinute) or d.perMinute), 1, 60),
        delay       = math.Clamp(tonumber(s.delay) or d.delay, 0, 30),
        requireDuty = s.requireDuty ~= false,
        allowHidden = s.allowHidden ~= false,
        meStart     = string.sub(tostring(s.meStart or d.meStart), 1, 160),
        meDone      = string.sub(tostring(s.meDone or d.meDone), 1, 160),
        logSize     = math.Clamp(math.floor(tonumber(s.logSize) or d.logSize), 20, 5000),
    }

    for fac, row in pairs(istable(cfg.factions) and cfg.factions or {}) do
        if isstring(fac) and istable(row) then
            local node = cleanNode(row)
            node.depts, node.subs, node.roles = {}, {}, {}
            for _, field in ipairs({ "depts", "subs", "roles" }) do
                for key, sub in pairs(istable(row[field]) and row[field] or {}) do
                    if isstring(key) and istable(sub) then
                        node[field][string.sub(key, 1, 64)] = cleanNode(sub)
                    end
                end
            end
            out.factions[string.sub(fac, 1, 96)] = node
        end
    end
    return out
end

--- Разбор доступа по цепочке организация → отдел → подотдел → должность.
--  Каждая ступень может переопределить уровень и догрузить свои галочки —
--  так «Полиции» ставится общий уровень, а конкретному отделу открывается
--  ещё один блок, без копирования всей ветки.
function PB.ResolveAccess(factionName, dept, subdept, role, cfg)
    cfg = istable(cfg) and cfg or PB.Config
    local fac = (istable(cfg.factions) and cfg.factions[tostring(factionName or "")]) or nil
    if not fac then return "none", {}, "" end

    local level = PB.LevelValid(fac.level) and fac.level or "none"
    local blocks, source = {}, "организация"
    for key, value in pairs(fac.blocks or {}) do blocks[key] = value end

    local function apply(node, label)
        if not istable(node) then return end
        if PB.LevelValid(node.level) then level = node.level source = label end
        for key, value in pairs(node.blocks or {}) do blocks[key] = value end
    end
    apply((fac.depts or {})[tostring(dept or "")], "отдел")
    apply((fac.subs or {})[tostring(subdept or "")], "подотдел")
    apply((fac.roles or {})[tostring(role or "")], "должность")

    return level, blocks, source
end

-----------------------------------------------------------------------
-- СЕРВЕР
-----------------------------------------------------------------------
if SERVER then
    for _, name in pairs(PB.Net) do util.AddNetworkString(name) end

    if GRM.Access and GRM.Access.Register then
        GRM.Access.Register("pcboard.audit", { label = "Госбаза: просмотр журнала запросов", scope = "account" })
    end

    local DIR = "grm_pcboard"
    local ACCESS_FILE = DIR .. "/access.json"
    local LOG_FILE = DIR .. "/log.json"

    PB.Log = PB.Log or {}

    local function jsonT(raw)
        local ok, t = pcall(util.JSONToTable, raw or "", false, true)
        return (ok and istable(t)) and t or nil
    end

    local function ensureDir()
        if not file.IsDir(DIR, "DATA") then file.CreateDir(DIR) end
    end

    -- Ключ персонажа — канон ядра (§5.2.6). Локальная копия убрана: копия канона.
    local charKeyOf = GRM.CharKey

    local function playerByCharKey(key)
        key = tostring(key or "")
        if key == "" then return nil end
        for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(ply) and charKeyOf(ply) == key then return ply end
        end
    end

    local function tell(ply, msg)
        if IsValid(ply) then ply:ChatPrint("[Госбаза] " .. tostring(msg)) else print("[Госбаза] " .. tostring(msg)) end
    end

    -------------------------------------------------------------------
    -- ХРАНЕНИЕ
    -------------------------------------------------------------------
    function PB.Load()
        ensureDir()
        PB.Config = PB.Normalize(jsonT(file.Read(ACCESS_FILE, "DATA") or "") or {})
        PB.Log = {}
        local log = jsonT(file.Read(LOG_FILE, "DATA") or "")
        if istable(log) and istable(log.rows) then
            for _, row in ipairs(log.rows) do
                if istable(row) then PB.Log[#PB.Log + 1] = row end
            end
        end
        return PB.Config
    end

    function PB.Save(why)
        ensureDir()
        local ok, raw = pcall(util.TableToJSON, PB.Normalize(PB.Config), true)
        if not ok or not isstring(raw) then return false end
        file.Write(ACCESS_FILE, raw)
        if GRM.Audit and GRM.Audit.Write then
            GRM.Audit.Write("pcboard", "access.save", nil, { why = tostring(why or "") }, {})
        end
        return true
    end

    local function trimLog()
        local limit = PB.Config.settings.logSize or 400
        while #PB.Log > limit do table.remove(PB.Log, 1) end
    end

    if GRM.Save and GRM.Save.Register then
        GRM.Save.Register("pcboard.log", { file = LOG_FILE, label = "Журнал запросов госбазы",
            delay = 10, build = function()
                ensureDir()
                trimLog()
                return { version = 1, rows = PB.Log }
            end })
        GRM.Save.Register("pcboard.access", { file = ACCESS_FILE, label = "Доступы госбазы",
            delay = 2, priority = 1, build = function()
                ensureDir()
                return PB.Normalize(PB.Config)
            end })
    end

    --[[ Журнал пополняется на КАЖДЫЙ запрос по базе. Синхронная запись файла
         на каждое пробитие — ровно тот микрофриз, который не должен
         существовать: помечаем грязным, пишет очередь GRM.Save. ]]
    function PB.SaveLog(force)
        if GRM.Save and GRM.Save.Mark and not force then return GRM.Save.Mark("pcboard.log", "запрос") end
        ensureDir()
        trimLog()
        local ok, raw = pcall(util.TableToJSON, { version = 1, rows = PB.Log }, true)
        if not ok or not isstring(raw) then return false end
        file.Write(LOG_FILE, raw)
        return true
    end

    -------------------------------------------------------------------
    -- ДОСТУП ИГРОКА
    -------------------------------------------------------------------
    --- Уровень допуска игрока: по его организации/отделу/подотделу/должности.
    --  Суперадмину доступен уровень «Администрация» всегда — иначе
    --  настраивать систему было бы нечем.
    function PB.PlayerLevel(ply)
        if not IsValid(ply) then return "none", {}, "" end
        if ply:IsSuperAdmin() then return "admin", {}, "суперадмин" end
        local fac = ply:GetNWString("GRM_Faction", "")
        if fac == "" then return "none", {}, "" end
        return PB.ResolveAccess(fac,
            ply:GetNWString("GRM_Department", ""),
            ply:GetNWString("GRM_Subdepartment", ""),
            ply:GetNWString("GRM_Role", ""))
    end

    function PB.CanUse(ply)
        local level, blocks, source = PB.PlayerLevel(ply)
        if level == "none" then return false, "У вашей организации нет доступа к государственной базе." end
        if level ~= "admin" and PB.Config.settings.requireDuty then
            local onDuty = GRM.FactionDuty and GRM.FactionDuty.IsOnDuty and GRM.FactionDuty.IsOnDuty(ply)
            if onDuty == false then return false, "Планшет работает только на службе." end
        end
        return true, nil, level, blocks, source
    end

    function PB.CanAudit(ply)
        if not IsValid(ply) then return true end
        if ply:IsSuperAdmin() then return true end
        if GRM.Access and GRM.Access.Can then return GRM.Access.Can(ply, "pcboard.audit") == true end
        return false
    end

    -------------------------------------------------------------------
    -- ПРОВАЙДЕРЫ ДАННЫХ
    -------------------------------------------------------------------
    local function docRegistry()
        return (GRM.Documents and istable(GRM.Documents.Registry)) and GRM.Documents.Registry or nil
    end

    local function fmtDate(ts)
        ts = tonumber(ts) or 0
        if ts <= 0 then return "—" end
        return os.date("%d.%m.%Y", ts)
    end

    local function money(n)
        n = math.floor(tonumber(n) or 0)
        if GRM.Format then return GRM.Format(n) end
        return tostring(n) .. " GRM"
    end

    PB.RegisterProvider("identity", {
        label = "Личность", order = 10,
        levels = { fire = true, medical = true, police = true, military = true, justice = true, special = true, admin = true },
        collect = function(ctx)
            local rows = {}
            local reg = docRegistry()
            local pass = reg and reg.passports and reg.passports[ctx.charKey] or nil
            rows[#rows + 1] = { "Имя", ctx.name ~= "" and ctx.name or "не установлено" }
            rows[#rows + 1] = { "Номер гражданина", ctx.cid ~= "" and ctx.cid or "нет в реестре" }
            if istable(pass) then
                rows[#rows + 1] = { "Пол", tostring(pass.gender or "—") }
                rows[#rows + 1] = { "Дата рождения", tostring(pass.birthDate or "—") }
                rows[#rows + 1] = { "Гражданство", tostring(pass.nationality or "—") }
                rows[#rows + 1] = { "Паспорт", tostring(pass.series or "") .. " " .. tostring(pass.number or "") ..
                    " · " .. tostring(pass.status or "—") }
            else
                rows[#rows + 1] = { "Паспорт", "в базе не значится" }
            end
            rows[#rows + 1] = { "Статус", ctx.online and "в сети" or "вне сети" }
            return rows
        end,
    })

    PB.RegisterProvider("wanted", {
        label = "Розыск и правонарушения", order = 20,
        levels = { police = true, military = true, justice = true, special = true, admin = true },
        collect = function(ctx)
            local W = GRM.Wanted
            if not (W and W.Records) then return nil end
            local rec = W.Records[ctx.charKey]
            if not istable(rec) then return { { "Розыск", "не разыскивается" } } end
            local rows = { { "Уровень розыска", tostring(rec.level or 0) },
                { "Юрисдикция", rec.jurisdiction == "military" and "воинская" or "гражданская" } }
            local n = 0
            for _, c in ipairs(rec.reasons or {}) do
                n = n + 1
                if n <= 6 then
                    rows[#rows + 1] = { "Статья " .. n, tostring(c.code or "") .. " " .. tostring(c.title or "") }
                end
            end
            if n == 0 then rows[#rows + 1] = { "Статьи", "нет" } end
            if n > 6 then rows[#rows + 1] = { "Ещё статей", tostring(n - 6) } end
            return rows
        end,
    })

    PB.RegisterProvider("fines", {
        label = "Штрафы и задолженности", order = 30,
        levels = { police = true, military = true, justice = true, special = true, admin = true },
        collect = function(ctx)
            local F = (GRM.Wanted and GRM.Wanted.Fines) or GRM.Fines
            if not (F and F.DebtOf) then return nil end
            local ok, debt = pcall(F.DebtOf, ctx.charKey)
            if not ok then return nil end
            local count = 0
            if F.For then
                local ok2, list = pcall(F.For, ctx.charKey, true)
                if ok2 and istable(list) then count = #list end
            end
            return { { "Непогашенных", tostring(count) }, { "Сумма долга", money(debt) } }
        end,
    })

    PB.RegisterProvider("licenses", {
        label = "Удостоверения и лицензии", order = 40,
        levels = { police = true, military = true, justice = true, special = true, admin = true },
        collect = function(ctx)
            local reg = docRegistry()
            if not reg then return nil end
            local rows = {}
            local lic = reg.licenses and reg.licenses[ctx.charKey]
            rows[#rows + 1] = { "В/У гражданское", istable(lic)
                and (tostring(lic.number or "—") .. " · " .. tostring(lic.status or "действует")) or "отсутствует" }
            local mil = reg.milLicenses and reg.milLicenses[ctx.charKey]
            rows[#rows + 1] = { "В/У военное", istable(mil)
                and (tostring(mil.number or "—") .. " · " .. tostring(mil.status or "действует")) or "отсутствует" }
            local wpn = reg.weaponLicenses and reg.weaponLicenses[ctx.charKey]
            rows[#rows + 1] = { "Разрешение на оружие", istable(wpn)
                and (tostring(wpn.number or "—") .. " · " .. tostring(wpn.status or "действует")) or "отсутствует" }
            local biz = reg.businessLicenses and reg.businessLicenses[ctx.charKey]
            if istable(biz) then rows[#rows + 1] = { "Лицензия на дело", tostring(biz.number or "есть") } end
            return rows
        end,
    })

    PB.RegisterProvider("marks", {
        label = "Внешность и особые приметы", order = 45,
        levels = { fire = true, medical = true, police = true, military = true, justice = true, special = true, admin = true },
        collect = function(ctx)
            local rows = {}
            local NP = GRM.Nameplate
            local marks = (NP and NP.Marks) and NP.Marks(ctx.charKey) or ""
            if marks ~= "" then rows[#rows + 1] = { "Особые приметы", marks } end
            if IsValid(ctx.target) and GRM.RPDesc and GRM.RPDesc.Get then
                local desc = GRM.RPDesc.Get(ctx.target)
                if isstring(desc) and desc ~= "" then rows[#rows + 1] = { "Внешность", desc } end
            end
            if #rows == 0 then return { { "Приметы", "не зафиксированы" } } end
            return rows
        end,
    })

    PB.RegisterProvider("military", {
        label = "Воинский учёт", order = 50,
        levels = { military = true, justice = true, special = true, admin = true },
        collect = function(ctx)
            local reg = docRegistry()
            if not reg then return nil end
            local mil = reg.military and reg.military[ctx.charKey]
            if not istable(mil) then
                return { { "Военный билет", "не выдавался" }, { "Воинский учёт", "не служил / нет данных" } }
            end
            return {
                { "Военный билет", tostring(mil.series or "") .. " " .. tostring(mil.number or "") },
                { "Звание", tostring(mil.rank or "—") },
                { "Подразделение", tostring(mil.unit or mil.department or "—") },
                { "Учёт", tostring(mil.status or "—") },
                { "Годность", tostring(mil.fitness or mil.category or "—") },
            }
        end,
    })

    PB.RegisterProvider("employment", {
        label = "Место службы", order = 60,
        levels = { justice = true, special = true, admin = true },
        collect = function(ctx)
            local rows = {}
            if IsValid(ctx.target) then
                local fac = ctx.target:GetNWString("GRM_FactionDisplay", ctx.target:GetNWString("GRM_Faction", ""))
                if fac ~= "" then
                    rows[#rows + 1] = { "Организация", fac }
                    local dep = ctx.target:GetNWString("GRM_DepartmentDisplay", "")
                    if dep ~= "" then rows[#rows + 1] = { "Отдел", dep } end
                    local sub = ctx.target:GetNWString("GRM_SubdepartmentDisplay", "")
                    if sub ~= "" then rows[#rows + 1] = { "Подотдел", sub } end
                    local role = ctx.target:GetNWString("GRM_Role", "")
                    if role ~= "" then rows[#rows + 1] = { "Должность", role } end
                end
            end
            local reg = docRegistry()
            local badge = reg and reg.badges and reg.badges[ctx.charKey] or nil
            if istable(badge) then
                rows[#rows + 1] = { "Удостоверение", tostring(badge.number or "—") .. " · " .. tostring(badge.status or "—") }
                if #rows == 1 then rows[#rows + 1] = { "Организация (по ксиве)", tostring(badge.faction or "—") } end
            end
            if #rows == 0 then rows[#rows + 1] = { "Место службы", "не значится" } end
            return rows
        end,
    })

    PB.RegisterProvider("vehicles", {
        label = "Транспорт на имени", order = 70,
        levels = { justice = true, special = true, admin = true },
        collect = function(ctx)
            local VD = GRM.VehicleDealer
            if not (VD and istable(VD.Garages)) then return nil end
            local rows, n = {}, 0
            for _, rec in pairs(VD.Garages[ctx.charKey] or {}) do
                if istable(rec) then
                    n = n + 1
                    if n <= 6 then
                        rows[#rows + 1] = { "ТС " .. n, tostring(rec.name or rec.class or "—") ..
                            (rec.stored and " · в гараже" or " · на руках") }
                    end
                end
            end
            if n == 0 then return { { "Транспорт", "не зарегистрирован" } } end
            if n > 6 then rows[#rows + 1] = { "Ещё ТС", tostring(n - 6) } end
            return rows
        end,
    })

    PB.RegisterProvider("property", {
        label = "Недвижимость", order = 80,
        levels = { fire = true, justice = true, special = true, admin = true },
        collect = function(ctx)
            local P = GRM.Property
            if not (P and istable(P.Records)) then return nil end
            local rows, n = {}, 0
            for _, rec in pairs(P.Records) do
                if istable(rec) and rec.ownerType == "character" and rec.ownerKey == ctx.charKey then
                    n = n + 1
                    if n <= 6 then
                        rows[#rows + 1] = { "Объект " .. n, tostring(rec.name or rec.id or "—") ..
                            " · " .. tostring((P.Types or {})[rec.type] or rec.type or "—") }
                    end
                end
            end
            if n == 0 then return { { "Недвижимость", "не значится" } } end
            if n > 6 then rows[#rows + 1] = { "Ещё объектов", tostring(n - 6) } end
            return rows
        end,
    })

    PB.RegisterProvider("education", {
        label = "Образование", order = 90,
        levels = { justice = true, special = true, admin = true },
        collect = function(ctx)
            local D = GRM.Diplomas
            if not (D and D.For) then return nil end
            local ok, list = pcall(D.For, ctx.charKey)
            if not ok or not istable(list) then return nil end
            if #list == 0 then return { { "Дипломы", "нет" } } end
            local rows = {}
            for i, rec in ipairs(list) do
                if i > 5 then break end
                rows[#rows + 1] = { "Диплом " .. i, tostring(rec.number or "—") .. " · " ..
                    tostring(rec.speciality or rec.institution or "—") }
            end
            return rows
        end,
    })

    PB.RegisterProvider("medical", {
        label = "Медицинская карта", order = 100,
        levels = { fire = true, medical = true, special = true, admin = true },
        collect = function(ctx)
            local rows = {}
            -- Постоянная медкарта (GRM.Medical) — она есть и для офлайн-лица.
            local MD = GRM.Medical
            local card = (MD and istable(MD.Cards)) and MD.Cards[ctx.charKey] or nil
            if istable(card) then
                rows[#rows + 1] = { "Группа крови", tostring(card.blood ~= "" and card.blood or "не указана") }
                rows[#rows + 1] = { "Аллергии", tostring(card.allergies ~= "" and card.allergies or "нет") }
                rows[#rows + 1] = { "Хронические", tostring(card.chronic ~= "" and card.chronic or "нет") }
                rows[#rows + 1] = { "Годность", tostring(card.fitnessCategory or "—") }
                rows[#rows + 1] = { "Записей в карте", tostring(#(card.entries or {})) }
            else
                rows[#rows + 1] = { "Медкарта", "не заводилась" }
            end
            -- Живое состояние доступно только для человека в сети.
            local MEDF = GRM.MedicalFull
            if IsValid(ctx.target) and MEDF and MEDF.Status then
                local ok, st = pcall(MEDF.Status, ctx.target)
                if ok and istable(st) then
                    rows[#rows + 1] = { "Состояние", ("здоровье %d · кровотечение %d%% · боль %d%%")
                        :format(st.health or 0, st.bleed or 0, st.pain or 0) }
                    rows[#rows + 1] = { "Препараты", tostring(st.narc or "нет") }
                end
            end
            return rows
        end,
    })

    PB.RegisterProvider("covers", {
        label = "Легенды и прикрытие", order = 110,
        levels = { special = true, admin = true },
        collect = function(ctx)
            local reg = docRegistry()
            if not reg then return nil end
            local cover = reg.coverBadges and reg.coverBadges[ctx.charKey] or nil
            if not istable(cover) then return { { "Легенды", "не выявлено" } } end
            return {
                { "Легенда", tostring(cover.fullName or "—") },
                { "Прикрытие", tostring(cover.faction or "—") .. " · " .. tostring(cover.role or "—") },
                { "Документ прикрытия", tostring(cover.number or "—") },
            }
        end,
    })

    PB.RegisterProvider("history", {
        label = "Кто пробивал это лицо", order = 120,
        levels = { justice = true, special = true, admin = true },
        collect = function(ctx)
            local rows, shown = {}, 0
            for i = #PB.Log, 1, -1 do
                local row = PB.Log[i]
                if istable(row) and row.targetKey == ctx.charKey and row.actorKey ~= ctx.actorKey then
                    shown = shown + 1
                    rows[#rows + 1] = { os.date("%d.%m %H:%M", tonumber(row.time) or 0),
                        tostring(row.actorName or "?") .. " · " .. PB.LevelName(row.level) }
                    if shown >= 5 then break end
                end
            end
            if shown == 0 then return { { "Запросов", "ранее не пробивали" } } end
            return rows
        end,
    })

    PB.RegisterProvider("account", {
        label = "Служебные данные администрации", order = 130,
        levels = { admin = true },
        collect = function(ctx)
            local rows = { { "Номер игрока", ctx.pid ~= "" and ctx.pid or "—" },
                { "SteamID64", tostring(ctx.accountKey or "—") },
                { "Ключ персонажа", ctx.charKey } }
            local R = GRM.Registry
            if R and istable(R.Data) and istable(R.Data.chars) then
                local n = 0
                for key, rec in pairs(R.Data.chars) do
                    if string.sub(key, 1, #tostring(ctx.accountKey or "")) == tostring(ctx.accountKey or "") then
                        n = n + 1
                        if n <= 3 then
                            rows[#rows + 1] = { "Персонаж " .. n, R.Format(R.CharPrefix, rec.cid) .. " · " ..
                                (rec.name ~= "" and rec.name or "без имени") .. (rec.retired and " · архив" or "") }
                        end
                    end
                end
            end
            return rows
        end,
    })

    -------------------------------------------------------------------
    -- СБОРКА СПРАВКИ
    -------------------------------------------------------------------
    --- ctx собирается один раз и уходит во все провайдеры: провайдер не
    --  должен сам искать игрока и лазить в реестр.
    local function buildContext(actor, charKey)
        local R = GRM.Registry
        local target = playerByCharKey(charKey)
        local accountKey = string.match(tostring(charKey), "^(%d+):char%d+$") or tostring(charKey)
        local name = ""
        if IsValid(target) then name = target:GetNWString("GRM_RPName", target:Nick()) end
        if name == "" and R and istable(R.Data) and R.Data.chars[charKey] then
            name = tostring(R.Data.chars[charKey].name or "")
        end
        return {
            charKey = charKey,
            accountKey = accountKey,
            target = target,
            online = IsValid(target),
            name = name,
            cid = (R and R.CID) and R.CID(charKey) or "",
            pid = (R and R.PID) and R.PID(accountKey) or "",
            actor = actor,
            actorKey = charKeyOf(actor),
        }
    end

    --- Карточка справки: заголовок + блоки, разрешённые уровнем и галочками.
    function PB.BuildCard(actor, charKey, level, blocks)
        local ctx = buildContext(actor, charKey)
        ctx.level = level
        local card = {
            title = (ctx.name ~= "" and ctx.name or "Личность не установлена"),
            cid = ctx.cid,
            level = level,
            levelName = PB.LevelName(level),
            time = os.time(),
            blocks = {},
        }
        for _, def in ipairs(PB.ProviderList()) do
            if PB.BlockAllowed(def.key, level, blocks) and isfunction(def.collect) then
                local ok, rows = pcall(def.collect, ctx)
                if ok and istable(rows) and #rows > 0 then
                    card.blocks[#card.blocks + 1] = { key = def.key, label = def.label, rows = rows }
                end
            end
        end
        return card, ctx
    end

    local function sendCard(actor, card)
        if not IsValid(actor) then return end
        net.Start(PB.Net.CARD)
        net.WriteTable(card)
        net.Send(actor)
    end

    -------------------------------------------------------------------
    -- РП-ДЕЙСТВИЕ
    -------------------------------------------------------------------
    local function meAction(actor, text)
        if not IsValid(actor) then return end
        -- Вечер-15: ручной радиус-цикл с ChatPrint (= второй владелец
        -- доставки) вырезан; единственная точка — шина GRM.RPBroadcast
        -- (свой радиус 355 сохраняем; RP-имя берёт шина из NW GRM_RPName).
        return GRM.RPBroadcast(actor, text, 355)
    end

    -------------------------------------------------------------------
    -- ЖУРНАЛ
    -------------------------------------------------------------------
    local function writeLog(ctx, level, hidden, how)
        PB.Log[#PB.Log + 1] = {
            time = os.time(),
            actorKey = ctx.actorKey,
            actorName = IsValid(ctx.actor) and ctx.actor:GetNWString("GRM_RPName", ctx.actor:Nick()) or "система",
            actorFaction = IsValid(ctx.actor) and ctx.actor:GetNWString("GRM_Faction", "") or "",
            targetKey = ctx.charKey,
            targetName = ctx.name,
            targetCID = ctx.cid,
            level = level,
            hidden = hidden == true,
            how = tostring(how or "aim"),
        }
        PB.SaveLog()
        if GRM.Audit and GRM.Audit.Write then
            GRM.Audit.Write("pcboard", "query", ctx.actor,
                { target = ctx.charKey, cid = ctx.cid }, { level = level, hidden = hidden == true, how = how })
        end
    end

    -------------------------------------------------------------------
    -- ЛИМИТЫ
    -------------------------------------------------------------------
    local function checkLimits(actor)
        local s = PB.Config.settings
        local now = CurTime()
        actor.GRM_PCBoardNext = actor.GRM_PCBoardNext or 0
        if now < actor.GRM_PCBoardNext then
            return false, ("Планшет обрабатывает предыдущий запрос, ещё %d с."):format(math.ceil(actor.GRM_PCBoardNext - now))
        end
        actor.GRM_PCBoardWindow = istable(actor.GRM_PCBoardWindow) and actor.GRM_PCBoardWindow or {}
        local fresh = {}
        for _, t in ipairs(actor.GRM_PCBoardWindow) do
            if now - t < 60 then fresh[#fresh + 1] = t end
        end
        if #fresh >= (s.perMinute or 3) then
            return false, ("Лимит запросов: %d в минуту."):format(s.perMinute or 3)
        end
        fresh[#fresh + 1] = now
        actor.GRM_PCBoardWindow = fresh
        actor.GRM_PCBoardNext = now + (s.cooldown or 8)
        return true
    end

    -------------------------------------------------------------------
    -- ЗАПРОС
    -------------------------------------------------------------------
    --- Основной вход: actor пробивает charKey.
    --  opts.hidden — скрытый запрос (только спецслужбы/админ),
    --  opts.how    — как нашли цель (для журнала),
    --  opts.self   — своя карточка (без лимитов и без /me).
    function PB.Run(actor, charKey, opts)
        opts = istable(opts) and opts or {}
        if not IsValid(actor) then return false, "Нет игрока" end
        charKey = tostring(charKey or "")
        if charKey == "" then return false, "Цель не найдена" end

        local level, blocks
        if opts.self then
            -- Своя карточка — это «что видят другие», уровень минимальный.
            level, blocks = "police", { wanted = true, fines = true, licenses = true, identity = true }
        else
            local ok, err, lvl, blk = PB.CanUse(actor)
            if not ok then return false, err end
            level, blocks = lvl, blk
            local okLimit, limitErr = checkLimits(actor)
            if not okLimit then return false, limitErr end
        end

        local s = PB.Config.settings
        local hidden = opts.hidden == true and s.allowHidden and (level == "special" or level == "admin")
        if opts.hidden and not hidden then
            return false, "Скрытый запрос доступен только спецслужбам."
        end

        if not (opts.self or hidden) then meAction(actor, s.meStart) end

        local delay = opts.self and 0 or (s.delay or 3)
        local function finish()
            if not IsValid(actor) then return end
            local card, ctx = PB.BuildCard(actor, charKey, level, blocks)
            card.hidden = hidden
            card.self = opts.self == true
            if not (opts.self or hidden) then meAction(actor, s.meDone) end
            sendCard(actor, card)
            if not opts.self then
                writeLog(ctx, level, hidden, opts.how)
                -- Сотрудник опознал человека: шапка над головой перестаёт
                -- показывать ему «Неизвестный» (модуль GRM.Nameplate).
                hook.Run("GRM_PCBoardIdentified", actor, charKey, level)
            end
        end
        if delay > 0 then timer.Simple(delay, finish) else finish() end
        return true
    end

    -------------------------------------------------------------------
    -- ПОИСК ЦЕЛИ
    -------------------------------------------------------------------
    local function aimTarget(actor)
        local tr = actor:GetEyeTrace()
        local ent = tr.Entity
        if IsValid(ent) and ent:IsPlayer() and ent:GetPos():DistToSqr(actor:GetPos()) <= 200 * 200 then
            return ent
        end
    end

    local function resolveQuery(query)
        query = string.Trim(tostring(query or ""))
        if query == "" then return nil end
        query = string.gsub(query, "^#", "")
        local R = GRM.Registry
        if R and R.Resolve then
            local key = R.Resolve(query)
            if key then return key end
        end
        -- Фолбэк без реестра: поиск по нику среди онлайна.
        local lower = string.lower(query)
        for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(ply) then
                local name = string.lower(ply:GetNWString("GRM_RPName", ply:Nick()))
                if string.find(name, lower, 1, true) or string.lower(ply:Nick()):find(lower, 1, true) then
                    return charKeyOf(ply)
                end
            end
        end
    end

    --- Владелец транспорта по идентификатору записи гаража или классу.
    local function resolveVehicle(query)
        local VD = GRM.VehicleDealer
        if not (VD and istable(VD.Garages)) then return nil, "Модуль транспорта не загружен" end
        query = string.lower(string.Trim(tostring(query or "")))
        if query == "" then return nil, "Укажите номер транспорта" end
        for charKey, rows in pairs(VD.Garages) do
            for id, rec in pairs(rows or {}) do
                if istable(rec) then
                    if string.lower(tostring(id)) == query
                        or string.lower(tostring(rec.plate or "")) == query
                        or string.lower(tostring(rec.class or "")) == query then
                        return charKey, nil, rec
                    end
                end
            end
        end
        return nil, "Транспорт с таким номером в базе не значится"
    end

    -------------------------------------------------------------------
    -- ЖУРНАЛ В ЧАТ
    -------------------------------------------------------------------
    local function showLog(actor, all)
        local mine = charKeyOf(actor)
        local rows, shown = {}, 0
        for i = #PB.Log, 1, -1 do
            local row = PB.Log[i]
            if istable(row) and (all or row.actorKey == mine) then
                shown = shown + 1
                rows[#rows + 1] = ("%s · %s → %s%s [%s]"):format(
                    os.date("%d.%m %H:%M", tonumber(row.time) or 0),
                    tostring(row.actorName or "?"),
                    tostring(row.targetName ~= "" and row.targetName or row.targetCID or "?"),
                    row.hidden and " · скрытно" or "",
                    PB.LevelName(row.level))
                if shown >= 20 then break end
            end
        end
        if shown == 0 then tell(actor, "Журнал пуст.") return end
        tell(actor, all and "Журнал запросов (последние 20):" or "Ваши последние запросы:")
        for _, line in ipairs(rows) do actor:ChatPrint("  " .. line) end
    end

    -------------------------------------------------------------------
    -- КОМАНДЫ
    -------------------------------------------------------------------
    local function command(actor, text)
        local args = string.Explode(" ", string.Trim(tostring(text or "")))
        local cmd = string.lower(args[1] or "")
        if cmd ~= "/pcboard" and cmd ~= "!pcboard" and cmd ~= "/пробить" and cmd ~= "!пробить" then return false end

        local sub = string.lower(tostring(args[2] or ""))
        local rest = table.concat(args, " ", 3)
        local hidden = false

        if sub == "скрытно" or sub == "тихо" or sub == "hidden" then
            hidden = true
            sub = string.lower(tostring(args[3] or ""))
            rest = table.concat(args, " ", 4)
        end

        if sub == "журнал" or sub == "log" then
            showLog(actor, PB.CanAudit(actor))
            return true
        end

        if sub == "я" or sub == "self" or sub == "me" then
            local ok, err = PB.Run(actor, charKeyOf(actor), { self = true, how = "self" })
            if not ok then tell(actor, err) end
            return true
        end

        if sub == "авто" or sub == "auto" then
            local key, err = resolveVehicle(rest ~= "" and rest or args[3])
            if not key then tell(actor, err or "Не найдено") return true end
            local ok, runErr = PB.Run(actor, key, { hidden = hidden, how = "vehicle" })
            if not ok then tell(actor, runErr) end
            return true
        end

        local query = table.concat(args, " ", hidden and 3 or 2)
        local key
        if query == "" then
            local ent = aimTarget(actor)
            if not IsValid(ent) then
                tell(actor, "Наведитесь на человека или укажите номер: /pcboard ГР-1042")
                return true
            end
            key = charKeyOf(ent)
        else
            key = resolveQuery(query)
            if not key then tell(actor, "В базе никого не нашлось по запросу: " .. query) return true end
        end

        local ok, err = PB.Run(actor, key, { hidden = hidden, how = query == "" and "aim" or "query" })
        if not ok then tell(actor, err) end
        return true
    end

    hook.Add("PlayerSay", "GRM_PCBoard_Chat", function(ply, text)
        if command(ply, text) then return "" end
    end)
    hook.Add("PlayerSayTransform", "GRM_PCBoard_ChatEC", function(ply, pack)
        if not (istable(pack) and isstring(pack[1])) then return end
        if command(ply, pack[1]) then pack[1] = "" pack.SkipPlayerSay = true end
    end)

    concommand.Add("grm_pcboard", function(ply, _, args)
        if not IsValid(ply) then return end
        command(ply, "/pcboard " .. table.concat(args or {}, " "))
    end)

    concommand.Add("grm_pcboard_log", function(ply)
        if IsValid(ply) and not PB.CanAudit(ply) then tell(ply, "Нет права на журнал запросов.") return end
        if IsValid(ply) then showLog(ply, true) return end
        for i = math.max(1, #PB.Log - 20), #PB.Log do
            local row = PB.Log[i]
            if istable(row) then
                print(("[Госбаза] %s %s → %s [%s]"):format(os.date("%d.%m %H:%M", row.time or 0),
                    tostring(row.actorName), tostring(row.targetName), PB.LevelName(row.level)))
            end
        end
    end)

    -------------------------------------------------------------------
    -- НАСТРОЙКА (сеть)
    -------------------------------------------------------------------
    --- Дерево организаций для редактора. Берём готовое из модуля дверей,
    --  чтобы отделы/подотделы/должности везде выглядели одинаково.
    function PB.FactionTree()
        if GRM.Doors and GRM.Doors.FactionTree then
            local ok, tree = pcall(GRM.Doors.FactionTree)
            if ok and istable(tree) then return tree end
        end
        local out = {}
        for name, f in pairs(istable(Factions) and Factions or {}) do
            if istable(f) then
                local row = { name = name, display = name, roles = {}, departments = {}, subdepartments = {} }
                for _, roleKey in ipairs(f.Roles or {}) do row.roles[#row.roles + 1] = { key = roleKey, display = roleKey } end
                for _, dep in ipairs(f.Departments or {}) do row.departments[#row.departments + 1] = { key = dep, display = dep } end
                for subKey, sub in pairs(f.Subdepartments or {}) do
                    if istable(sub) then
                        row.subdepartments[#row.subdepartments + 1] = { key = subKey, display = tostring(sub.name or subKey) }
                    end
                end
                out[#out + 1] = row
            end
        end
        return out
    end

    local function sendConfig(ply)
        if not (IsValid(ply) and ply:IsSuperAdmin()) then return end
        net.Start(PB.Net.DATA)
        net.WriteTable({
            config = PB.Normalize(PB.Config),
            tree = PB.FactionTree(),
            blocks = (function()
                local rows = {}
                for _, def in ipairs(PB.ProviderList()) do
                    rows[#rows + 1] = { key = def.key, label = def.label, levels = def.levels }
                end
                return rows
            end)(),
        })
        net.Send(ply)
    end

    net.Receive(PB.Net.REQ, function(_, ply) sendConfig(ply) end)

    net.Receive(PB.Net.SAVE, function(_, ply)
        if not (IsValid(ply) and ply:IsSuperAdmin()) then return end
        PB.Config = PB.Normalize(net.ReadTable() or {})
        PB.Save("edit by " .. ply:Nick())
        sendConfig(ply)
        if GRM.Notify then GRM.Notify(ply, "Доступы госбазы сохранены.", 100, 220, 130)
        else tell(ply, "Доступы госбазы сохранены.") end
    end)

    PB.Load()
    if GRM.Boot and GRM.Boot.OnMapStart then
        GRM.Boot.OnMapStart("GRM_PCBoard_Load", "early", function() PB.Load() end,
            { label = "Госбаза: доступы планшета" })
    end

    print("[GRM PCBoard] server v" .. PB.Version .. " loaded")
end

-----------------------------------------------------------------------
-- КЛИЕНТ (приём карточки — отрисовка в cl_grm_pcboard_ui.lua)
-----------------------------------------------------------------------
if CLIENT then
    PB.LastCard = PB.LastCard or nil
    net.Receive(PB.Net.CARD, function()
        local card = net.ReadTable()
        if not istable(card) then return end
        PB.LastCard = card
        hook.Run("GRM_PCBoardCard", card)
    end)
    print("[GRM PCBoard] client v" .. PB.Version .. " loaded")
end
