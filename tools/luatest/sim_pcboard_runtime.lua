--[[ Живой прогон планшета госслужб /pcboard: уровни допуска по цепочке
     организация → отдел → подотдел → должность, галочки блоков, сборка
     справки из реальных провайдеров, РП-действие, кулдаун и лимит,
     скрытый запрос, журнал.
     Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_pcboard_runtime.lua ]]
SERVER, CLIENT = true, false
function AddCSLuaFile() end

local NOW = 100
function CurTime() return NOW end
function IsValid(v) return type(v) == "table" and v._valid ~= false end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isfunction(v) return type(v) == "function" end
function isnumber(v) return type(v) == "number" end
function string.Trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
function string.Explode(sep, str)
    local out = {}
    for part in tostring(str):gmatch("[^" .. sep .. "]+") do out[#out + 1] = part end
    return out
end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function table.Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
function table.Copy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = table.Copy(v) end
    return out
end

local FS = {}
file = { IsDir = function() return true end, CreateDir = function() end,
         Write = function(p, s) FS[p] = s end, Read = function(p) return FS[p] end,
         Exists = function(p) return FS[p] ~= nil end }

-- Мини-JSON (как в остальных стендах).
local function enc(v)
    local t = type(v)
    if t == "number" or t == "boolean" then return tostring(v) end
    if t == "string" then return string.format("%q", v) end
    local parts = {}
    if #v > 0 then for _, i in ipairs(v) do parts[#parts + 1] = enc(i) end return "[" .. table.concat(parts, ",") .. "]" end
    for k, i in pairs(v) do parts[#parts + 1] = string.format("%q", tostring(k)) .. ":" .. enc(i) end
    return "{" .. table.concat(parts, ",") .. "}"
end
local function dec(s)
    local pos = 1
    local function value()
        while s:sub(pos, pos):match("%s") do pos = pos + 1 end
        local c = s:sub(pos, pos)
        if c == "{" then
            pos = pos + 1 local out = {}
            if s:sub(pos, pos) == "}" then pos = pos + 1 return out end
            while true do
                local k = value() pos = pos + 1
                out[k] = value()
                local sep = s:sub(pos, pos) pos = pos + 1
                if sep == "}" then break end
            end
            return out
        elseif c == "[" then
            pos = pos + 1 local out = {}
            if s:sub(pos, pos) == "]" then pos = pos + 1 return out end
            while true do
                out[#out + 1] = value()
                local sep = s:sub(pos, pos) pos = pos + 1
                if sep == "]" then break end
            end
            return out
        elseif c == '"' then
            local i, out = pos + 1, {}
            while s:sub(i, i) ~= '"' do out[#out + 1] = s:sub(i, i) i = i + 1 end
            pos = i + 1 return table.concat(out)
        elseif s:sub(pos, pos + 3) == "true" then pos = pos + 4 return true
        elseif s:sub(pos, pos + 4) == "false" then pos = pos + 5 return false
        else
            local a, b = s:find("[%-%d%.]+", pos) pos = b + 1 return tonumber(s:sub(a, b))
        end
    end
    return value()
end
util = { AddNetworkString = function() end, TableToJSON = function(t) return enc(t) end,
         JSONToTable = function(s) return dec(s) end }

local hooks = {}
hook = {
    Add = function(name, id, fn) hooks[name] = hooks[name] or {} hooks[name][id] = fn end,
    Run = function() end,
}
local pendingTimers = {}
timer = {
    Create = function() end,
    Simple = function(delay, fn) pendingTimers[#pendingTimers + 1] = fn end,
}
local function runTimers()
    local list = pendingTimers
    pendingTimers = {}
    for _, fn in ipairs(list) do fn() end
end
concommand = { Add = function() end }

local netSent = {}
net = {
    Receive = function() end,
    Start = function(name) netSent[#netSent + 1] = { name = name } end,
    WriteTable = function(t) netSent[#netSent].data = t end,
    Send = function(ply) netSent[#netSent].to = ply end,
}

-- ── Игроки и мир ────────────────────────────────────────────────────
local ALL = {}
player = { GetAll = function() return ALL end }

local function vec(x, y)
    local v = { x = x or 0, y = y or 0, z = 0 }
    function v:DistToSqr(o) return (self.x - o.x) ^ 2 + (self.y - o.y) ^ 2 end
    function v:Distance(o) return math.sqrt(self:DistToSqr(o)) end
    return v
end

local function mkPlayer(sid, opts)
    opts = opts or {}
    local p = { _valid = true, _sid = sid, _slot = opts.slot or "char1", nw = {}, chat = {}, pos = vec(opts.x or 0, 0),
        _super = opts.super == true }
    function p:IsPlayer() return true end
    function p:Nick() return opts.nick or ("Ник" .. sid:sub(-2)) end
    function p:SteamID64() return self._sid end
    function p:IsSuperAdmin() return self._super end
    function p:GetNWString(k, d) local v = self.nw[k] if v == nil then return d end return v end
    function p:SetNWString(k, v) self.nw[k] = v end
    function p:GetPos() return self.pos end
    function p:Health() return 100 end
    function p:ChatPrint(msg) self.chat[#self.chat + 1] = msg end
    function p:GetEyeTrace() return { Entity = self._aim } end
    p.nw.GRM_RPName = opts.name or ""
    p.nw.GRM_Faction = opts.faction or ""
    p.nw.GRM_Department = opts.dept or ""
    p.nw.GRM_Subdepartment = opts.sub or ""
    p.nw.GRM_Role = opts.role or ""
    ALL[#ALL + 1] = p
    return p
end

-- ── Заглушки соседних модулей ───────────────────────────────────────
GRM = { Identity = {}, Perf = {} }
GRM.Identity.CharacterKey = function(p)
    if IsValid(p) then return p._sid .. ":" .. (p._slot or "char1") end
    return tostring(p or "")
end
GRM.Identity.AccountKey = function(p) return IsValid(p) and p._sid or tostring(p or "") end
GRM.Identity.IsCharacterKey = function(v) return isstring(v) and v:match("^%d+:char[1-3]$") ~= nil end

Factions = {
    ["Полиция Порядка"] = { Roles = { "Сержант", "Комиссар" }, Departments = { "Патруль", "Розыск" },
        Subdepartments = { swat = { name = "СВАТ", parentDept = "Патруль" } } },
    ["Госпиталь"] = { Roles = { "Врач" }, Departments = { "Скорая" }, Subdepartments = {} },
}

GRM.FactionDuty = { IsOnDuty = function(p) return p._duty ~= false end }

GRM.Wanted = { Records = {}, Fines = {
    DebtOf = function(key) return key == "76561190000000002:char1" and 12400 or 0 end,
    For = function(key) return key == "76561190000000002:char1" and { {}, {} } or {} end,
} }
GRM.Documents = { Registry = { passports = {}, badges = {}, military = {}, licenses = {}, milLicenses = {},
    weaponLicenses = {}, businessLicenses = {}, coverBadges = {} } }
GRM.Medical = { Cards = {} }
GRM.Property = { Records = {}, Types = { apartment = "Квартира" } }
GRM.VehicleDealer = { Garages = {} }
GRM.Diplomas = { For = function() return {} end }
GRM.Access = { Register = function() end, Can = function() return false end }
GRM.Audit = { Write = function() end }
GRM.Doors = nil

-- Данные о цели: Курт Вебер, разыскивается, есть В/У и медкарта.
local TKEY = "76561190000000002:char1"
GRM.Wanted.Records[TKEY] = { level = 2, jurisdiction = "civil",
    reasons = { { code = "УК-105", title = "Нападение на сотрудника" }, { code = "УК-222", title = "Хранение оружия" } } }
GRM.Documents.Registry.passports[TKEY] = { gender = "Мужской", birthDate = "12.04.1988",
    nationality = "Гражданин Республики", series = "GRM", number = "011234", status = "Действителен" }
GRM.Documents.Registry.licenses[TKEY] = { number = "ДИ-7712", status = "Действует" }
GRM.Documents.Registry.military[TKEY] = { series = "ВС", number = "4412", rank = "Ефрейтор",
    unit = "3-й полк", status = "Запас", fitness = "А" }
GRM.Medical.Cards[TKEY] = { blood = "II (A) Rh+", allergies = "нет", chronic = "нет",
    fitnessCategory = "А — Годен", entries = { {}, {} } }
GRM.VehicleDealer.Garages[TKEY] = { veh1 = { class = "car_a", name = "Sedan", stored = true, plate = "АА-1234" } }
GRM.Property.Records = { pr1 = { ownerType = "character", ownerKey = TKEY, name = "Квартира 12", type = "apartment" } }
GRM.Documents.Registry.coverBadges[TKEY] = nil

-- Реестр номеров подключаем настоящий: справка обязана печатать ГР-номер.
assert(loadfile("lua/autorun/sh_grm_registry.lua"))()
local R = GRM.Registry

assert(loadfile("lua/autorun/sh_grm_pcboard.lua"))()
local PB = GRM.PCBoard

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

local function findBlock(card, key)
    for _, block in ipairs(card.blocks or {}) do
        if block.key == key then return block end
    end
end
local function blockValue(card, key, label)
    local block = findBlock(card, key)
    if not block then return nil end
    for _, row in ipairs(block.rows or {}) do
        if row[1] == label then return row[2] end
    end
end

-- Игроки: полицейский, комиссар, врач, спецслужбист, цель.
local cop = mkPlayer("76561190000000001", { name = "Ганс Мюллер", faction = "Полиция Порядка",
    dept = "Патруль", role = "Сержант", x = 0 })
local swat = mkPlayer("76561190000000004", { name = "Отто Кёниг", faction = "Полиция Порядка",
    dept = "Патруль", sub = "swat", role = "Сержант", x = 40 })
local medic = mkPlayer("76561190000000005", { name = "Клара Штерн", faction = "Госпиталь",
    dept = "Скорая", role = "Врач", x = 900 })
local target = mkPlayer("76561190000000002", { name = "Курт Вебер", x = 60 })
R.Sync(cop) R.Sync(swat) R.Sync(medic) R.Sync(target)

print("\n=== 1. НАСТРОЙКА ДОСТУПОВ ===")
PB.Config = PB.Normalize({
    settings = { cooldown = 8, perMinute = 3, delay = 3, requireDuty = true, allowHidden = true },
    factions = {
        ["Полиция Порядка"] = {
            level = "police", blocks = {},
            subs = { swat = { level = "special" } },
            roles = { ["Комиссар"] = { level = "special" } },
            depts = { ["Розыск"] = { blocks = { vehicles = true } } },
        },
        ["Госпиталь"] = { level = "medical", blocks = {} },
    },
})
ok(select(1, PB.ResolveAccess("Полиция Порядка", "Патруль", "", "Сержант")) == "police",
    "организация задаёт уровень «Правоохранительный»")
ok(select(1, PB.ResolveAccess("Полиция Порядка", "Патруль", "swat", "Сержант")) == "special",
    "подотдел переопределяет уровень организации")
ok(select(1, PB.ResolveAccess("Полиция Порядка", "Патруль", "", "Комиссар")) == "special",
    "должность переопределяет уровень организации")
local lvlDept, blocksDept = PB.ResolveAccess("Полиция Порядка", "Розыск", "", "Сержант")
ok(lvlDept == "police" and blocksDept.vehicles == true,
    "отдел не меняет уровень, но добавляет свой блок")
ok(select(1, PB.ResolveAccess("Неизвестная контора", "", "", "")) == "none",
    "чужая организация доступа не получает")

print("\n=== 2. МАТРИЦА БЛОКОВ ===")
ok(PB.BlockAllowed("wanted", "police") == true, "правоохранителю виден розыск")
ok(PB.BlockAllowed("military", "police") == false, "правоохранителю НЕ виден военный билет")
ok(PB.BlockAllowed("military", "military") == true, "комендатуре виден военный билет")
ok(PB.BlockAllowed("wanted", "medical") == false, "медику НЕ виден розыск")
ok(PB.BlockAllowed("medical", "medical") == true, "медику видна медкарта")
ok(PB.BlockAllowed("covers", "special") == true, "спецслужбам видны легенды")
ok(PB.BlockAllowed("account", "special") == false, "спецслужбам НЕ видны данные аккаунта")
ok(PB.BlockAllowed("account", "admin") == true, "администрации видно всё")
ok(PB.BlockAllowed("vehicles", "police", { vehicles = true }) == true, "галочка открывает блок сверх уровня")
ok(PB.BlockAllowed("wanted", "police", { wanted = false }) == false, "галочка закрывает блок вопреки уровню")
ok(PB.BlockAllowed("wanted", "none") == false, "без допуска не видно ничего")

print("\n=== 2б. НОВЫЕ УРОВНИ: ЮСТИЦИЯ И ПОЖАРНАЯ СЛУЖБА ===")
ok(PB.LevelName("justice") == "Юстиция", "уровень «Юстиция» объявлен", PB.LevelName("justice"))
ok(PB.LevelName("fire") == "Пожарная служба", "уровень «Пожарная служба» объявлен", PB.LevelName("fire"))
ok(PB.BlockAllowed("wanted", "justice") == true, "юстиции виден розыск и статьи")
ok(PB.BlockAllowed("fines", "justice") == true, "юстиции видны штрафы и задолженности")
ok(PB.BlockAllowed("military", "justice") == true, "юстиции виден воинский учёт (воинские дела)")
ok(PB.BlockAllowed("employment", "justice") == true, "юстиции видно место службы")
ok(PB.BlockAllowed("property", "justice") == true, "юстиции видна недвижимость (иски и аресты)")
ok(PB.BlockAllowed("vehicles", "justice") == true, "юстиции виден транспорт")
ok(PB.BlockAllowed("history", "justice") == true, "юстиция видит, кто пробивал лицо (надзор)")
ok(PB.BlockAllowed("medical", "justice") == false, "медкарта юстиции по умолчанию закрыта")
ok(PB.BlockAllowed("covers", "justice") == false, "легенды прикрытия юстиции не показывают")
ok(PB.BlockAllowed("account", "justice") == false, "данные аккаунта — только администрации")

ok(PB.BlockAllowed("identity", "fire") == true, "пожарным видна личность")
ok(PB.BlockAllowed("marks", "fire") == true, "пожарным видны приметы (опознание пострадавших)")
ok(PB.BlockAllowed("property", "fire") == true, "пожарным виден владелец недвижимости — ключевое на выезде")
ok(PB.BlockAllowed("medical", "fire") == true, "пожарным видна медкарта (первая помощь)")
ok(PB.BlockAllowed("wanted", "fire") == false, "розыск пожарным не показывают")
ok(PB.BlockAllowed("fines", "fire") == false, "штрафы пожарным не показывают")
ok(PB.BlockAllowed("military", "fire") == false, "воинский учёт пожарным не показывают")
ok(PB.BlockAllowed("vehicles", "fire") == false, "транспорт пожарным по умолчанию закрыт")
ok(PB.BlockAllowed("vehicles", "fire", { vehicles = true }) == true,
    "но галочкой транспорт пожарным открывается")

print("\n=== 3. УРОВЕНЬ ИГРОКА И ДОПУСК К КОМАНДЕ ===")
ok(select(1, PB.PlayerLevel(cop)) == "police", "уровень берётся из организации игрока")
ok(select(1, PB.PlayerLevel(swat)) == "special", "подотдел игрока поднимает уровень")
ok(select(1, PB.PlayerLevel(target)) == "none", "гражданскому доступа нет")
ok(PB.CanUse(cop) == true, "сотрудник на службе пользуется планшетом")
cop._duty = false
ok(PB.CanUse(cop) == false, "вне службы планшет не работает")
cop._duty = true

print("\n=== 4. СПРАВКА ПРАВООХРАНИТЕЛЯ ===")
netSent = {}
target.chat = {}
cop._aim = target
local okRun, err = PB.Run(cop, TKEY, { how = "aim" })
ok(okRun == true, "запрос принят", tostring(err))
ok(#target.chat == 1 and target.chat[1]:find("достаёт служебный планшет", 1, true) ~= nil,
    "окружающие видят РП-действие «достаёт планшет»", target.chat[1])
ok(#netSent == 0, "справка не уходит мгновенно — идёт «пробитие»")
runTimers()
ok(#netSent == 1 and netSent[1].name == PB.Net.CARD and netSent[1].to == cop,
    "справка ушла ТОЛЬКО запросившему")
local card = netSent[1].data
ok(card.cid == R.CID(TKEY), "в шапке справки номер гражданина", tostring(card.cid))
ok(card.title == "Курт Вебер", "в шапке имя из реестра", tostring(card.title))
ok(findBlock(card, "wanted") ~= nil, "блок розыска на месте")
ok(blockValue(card, "wanted", "Уровень розыска") == "2", "уровень розыска взят из модуля розыска")
ok(blockValue(card, "wanted", "Статья 1"):find("Нападение", 1, true) ~= nil, "статьи перечислены")
ok(blockValue(card, "fines", "Сумма долга") ~= nil, "долг по штрафам подтянулся")
ok(blockValue(card, "licenses", "В/У гражданское"):find("ДИ%-7712") ~= nil, "гражданское В/У в справке")
ok(findBlock(card, "military") == nil, "военного билета правоохранителю не показали")
ok(findBlock(card, "medical") == nil, "медкарты правоохранителю не показали")
ok(findBlock(card, "covers") == nil, "легенд правоохранителю не показали")
ok(#target.chat == 2 and target.chat[2]:find("пиликает", 1, true) ~= nil,
    "второе РП-действие после обработки запроса")

print("\n=== 5. КУЛДАУН И ЛИМИТ ===")
local okCd, cdErr = PB.Run(cop, TKEY, {})
ok(okCd == false and tostring(cdErr):find("предыдущий запрос", 1, true) ~= nil, "кулдаун держит повтор", tostring(cdErr))
NOW = NOW + 10
ok(PB.Run(cop, TKEY, {}) == true, "после кулдауна запрос проходит")
runTimers()
NOW = NOW + 10
ok(PB.Run(cop, TKEY, {}) == true, "третий запрос в минуту разрешён")
runTimers()
NOW = NOW + 10
local okLimit, limitErr = PB.Run(cop, TKEY, {})
ok(okLimit == false and tostring(limitErr):find("Лимит", 1, true) ~= nil, "четвёртый запрос за минуту отбит", tostring(limitErr))
NOW = NOW + 61
ok(PB.Run(cop, TKEY, {}) == true, "через минуту лимит сбрасывается")
runTimers()

print("\n=== 6. СПЕЦСЛУЖБЫ И СКРЫТЫЙ ЗАПРОС ===")
netSent = {}
target.chat = {}
NOW = NOW + 20
local okHidden = PB.Run(swat, TKEY, { hidden = true, how = "aim" })
runTimers()
ok(okHidden == true, "спецслужбам скрытый запрос разрешён")
ok(#target.chat == 0, "при скрытом запросе окружающие не видят РП-действия")
local hcard = netSent[#netSent].data
ok(hcard.hidden == true, "карточка помечена скрытой")
ok(findBlock(hcard, "military") ~= nil, "спецслужбам виден военный билет")
ok(findBlock(hcard, "employment") ~= nil, "спецслужбам видно место службы")
ok(findBlock(hcard, "vehicles") ~= nil, "спецслужбам виден транспорт")
ok(blockValue(hcard, "vehicles", "ТС 1"):find("Sedan", 1, true) ~= nil, "транспорт взят из гаража дилера")
ok(blockValue(hcard, "property", "Объект 1"):find("Квартира 12", 1, true) ~= nil, "недвижимость подтянулась")
ok(findBlock(hcard, "account") == nil, "данные аккаунта спецслужбам закрыты")

NOW = NOW + 20
local okDeny, denyErr = PB.Run(cop, TKEY, { hidden = true })
ok(okDeny == false and tostring(denyErr):find("Скрытый", 1, true) ~= nil,
    "правоохранителю скрытый запрос запрещён", tostring(denyErr))

print("\n=== 7. МЕДИК ===")
netSent = {}
NOW = NOW + 20
PB.Run(medic, TKEY, {})
runTimers()
local mcard = netSent[#netSent].data
ok(findBlock(mcard, "medical") ~= nil, "медику видна медкарта")
ok(blockValue(mcard, "medical", "Группа крови") == "II (A) Rh+", "группа крови из медкарты")
ok(findBlock(mcard, "wanted") == nil, "медику розыск не показывают")
ok(findBlock(mcard, "identity") ~= nil, "личность видна всем уровням")

print("\n=== 7б. ЮСТИЦИЯ И ПОЖАРНЫЕ В ДЕЛЕ ===")
Factions["Суд"] = { Roles = { "Судья" }, Departments = {}, Subdepartments = {} }
Factions["Пожарная охрана"] = { Roles = { "Брандмейстер" }, Departments = {}, Subdepartments = {} }
PB.Config = PB.Normalize({
    settings = { cooldown = 0, perMinute = 60, delay = 0, requireDuty = false, allowHidden = true },
    factions = {
        ["Полиция Порядка"] = { level = "police", subs = { swat = { level = "special" } } },
        ["Госпиталь"] = { level = "medical" },
        ["Суд"] = { level = "justice" },
        ["Пожарная охрана"] = { level = "fire" },
    },
})
local judge = mkPlayer("76561190000000006", { name = "Эрих Ланге", faction = "Суд", role = "Судья", x = 70 })
local fireman = mkPlayer("76561190000000007", { name = "Пауль Рихтер", faction = "Пожарная охрана",
    role = "Брандмейстер", x = 80 })
R.Sync(judge) R.Sync(fireman)
ok(select(1, PB.PlayerLevel(judge)) == "justice", "судья работает на уровне «Юстиция»")
ok(select(1, PB.PlayerLevel(fireman)) == "fire", "пожарный работает на уровне «Пожарная служба»")

netSent = {}
PB.Run(judge, TKEY, {})
runTimers()
local jcard = netSent[#netSent].data
ok(findBlock(jcard, "wanted") ~= nil and findBlock(jcard, "fines") ~= nil,
    "в справке юстиции есть розыск и штрафы")
ok(findBlock(jcard, "property") ~= nil and findBlock(jcard, "military") ~= nil,
    "в справке юстиции есть недвижимость и воинский учёт")
ok(findBlock(jcard, "medical") == nil and findBlock(jcard, "covers") == nil,
    "медкарты и легенд в справке юстиции нет")

netSent = {}
PB.Run(fireman, TKEY, {})
runTimers()
local fcard = netSent[#netSent].data
ok(findBlock(fcard, "property") ~= nil, "в справке пожарного есть недвижимость")
ok(blockValue(fcard, "property", "Объект 1"):find("Квартира 12", 1, true) ~= nil,
    "объект взят из модуля недвижимости")
ok(findBlock(fcard, "medical") ~= nil, "в справке пожарного есть медкарта")
ok(findBlock(fcard, "wanted") == nil and findBlock(fcard, "fines") == nil,
    "розыска и штрафов пожарному не показывают")
local okHiddenFire = PB.Run(fireman, TKEY, { hidden = true })
ok(okHiddenFire == false, "скрытый запрос пожарным недоступен")

print("\n=== 8. ЖУРНАЛ ===")
ok(#PB.Log >= 6, "все запросы записаны в журнал", tostring(#PB.Log))
local last = PB.Log[#PB.Log]
ok(last.targetKey == TKEY and last.actorKey == GRM.Identity.CharacterKey(fireman),
    "в записи есть кто и кого")
local hiddenLogged = false
for _, row in ipairs(PB.Log) do if row.hidden then hiddenLogged = true end end
ok(hiddenLogged, "скрытый запрос ТОЖЕ попал в журнал")
ok(FS["grm_pcboard/log.json"] ~= nil, "журнал лёг в файл")

netSent = {}
NOW = NOW + 20
PB.Run(cop, TKEY, {})
runTimers()
local histCard
netSent = {}
NOW = NOW + 20
PB.Run(swat, TKEY, {})
runTimers()
histCard = netSent[#netSent].data
local hist = findBlock(histCard, "history")
ok(hist ~= nil and #hist.rows > 0, "спецслужбы видят, кто пробивал это лицо раньше")

print("\n=== 9. СВОЯ КАРТОЧКА И АДМИН ===")
netSent = {}
local civKey = GRM.Identity.CharacterKey(target)
ok(PB.Run(target, civKey, { self = true }) == true, "свою карточку смотрит и гражданский")
runTimers()
local scard = netSent[#netSent].data
ok(scard.self == true and findBlock(scard, "identity") ~= nil, "своя карточка собирается")

local admin = mkPlayer("76561190000000009", { name = "Админ", super = true, x = 500 })
R.Sync(admin)
netSent = {}
NOW = NOW + 20
PB.Run(admin, TKEY, {})
runTimers()
local acard = netSent[#netSent].data
ok(acard.level == "admin", "суперадмин работает на уровне администрации")
ok(findBlock(acard, "account") ~= nil, "администрации видны служебные данные")
ok(blockValue(acard, "account", "Номер игрока") == R.PID("76561190000000002"), "в служебном блоке номер ИГРОКА")

print("\n=== 10. ХРАНЕНИЕ НАСТРОЕК ===")
ok(PB.Save("test"), "настройки доступов сохраняются")
PB.Config = { settings = {}, factions = {} }
PB.Load()
ok(select(1, PB.ResolveAccess("Полиция Порядка", "Патруль", "swat", "Сержант")) == "special",
    "переопределение подотдела пережило перезагрузку")
FS["grm_pcboard/access.json"] = "мусор, не json"
PB.Load()
ok(table.Count(PB.Config.factions) == 0 and PB.Config.settings.cooldown == 8,
    "битый файл не роняет модуль — настройки по умолчанию")

print("\n=== 11. ЗАЩИТА ВВОДА ===")
local dirty = PB.Normalize({ settings = { cooldown = -50, perMinute = 999, delay = 500 },
    factions = { ["X"] = { level = "боженька", blocks = { good = true, [5] = true, bad = "да" } } } })
ok(dirty.settings.cooldown == 0 and dirty.settings.perMinute == 60 and dirty.settings.delay == 30,
    "числа зажаты в границы")
ok(dirty.factions["X"].level == nil, "выдуманный уровень отброшен")
ok(dirty.factions["X"].blocks.good == true and dirty.factions["X"].blocks.bad == nil,
    "в галочки проходят только true/false")

print("\n=== 12. РАЗБОР КОМАНД ЧАТА ===")
PB.Load()
PB.Config = PB.Normalize({
    settings = { cooldown = 0, perMinute = 60, delay = 0, requireDuty = false, allowHidden = true },
    factions = { ["Полиция Порядка"] = { level = "police", subs = { swat = { level = "special" } } } },
})
local say = hooks["PlayerSay"] and hooks["PlayerSay"]["GRM_PCBoard_Chat"]
ok(isfunction(say), "команда зарегистрирована в PlayerSay")
ok(isfunction(hooks["PlayerSayTransform"] and hooks["PlayerSayTransform"]["GRM_PCBoard_ChatEC"]),
    "команда зарегистрирована и в PlayerSayTransform (EasyChat)")
ok(say(cop, "просто болтовня") == nil, "обычная реплика не перехватывается")

-- по прицелу
netSent = {}
cop.chat = {}
cop._aim = target
ok(say(cop, "/pcboard") == "", "команда /pcboard перехвачена")
runTimers()
ok(netSent[#netSent] and netSent[#netSent].data.title == "Курт Вебер", "по прицелу нашли человека")

-- по номеру ГР
netSent = {}
ok(say(cop, "/pcboard " .. R.CID(TKEY)) == "", "поиск по номеру ГР")
runTimers()
ok(netSent[#netSent] and netSent[#netSent].data.title == "Курт Вебер", "номер привёл к тому же лицу")

netSent = {}
say(cop, "/pcboard #" .. R.CID(TKEY))
runTimers()
ok(netSent[#netSent] and netSent[#netSent].data.cid == R.CID(TKEY), "решётка перед номером не мешает")

-- по имени
netSent = {}
say(cop, "/pcboard курт")
runTimers()
ok(netSent[#netSent] and netSent[#netSent].data.title == "Курт Вебер", "поиск по части имени")

-- по номеру транспорта
netSent = {}
say(cop, "/pcboard авто АА-1234")
runTimers()
ok(netSent[#netSent] and netSent[#netSent].data.title == "Курт Вебер", "по номеру транспорта нашли владельца")

-- своя карточка
netSent = {}
say(cop, "/pcboard я")
runTimers()
ok(netSent[#netSent] and netSent[#netSent].data.self == true, "/pcboard я даёт свою карточку")

-- скрытый запрос
netSent = {}
target.chat = {}
say(swat, "/pcboard скрытно " .. R.CID(TKEY))
runTimers()
ok(netSent[#netSent] and netSent[#netSent].data.hidden == true and #target.chat == 0,
    "«/pcboard скрытно» работает и молчит")

cop.chat = {}
say(cop, "/pcboard скрытно " .. R.CID(TKEY))
ok(#cop.chat > 0 and cop.chat[1]:find("Скрытый", 1, true) ~= nil,
    "правоохранителю на скрытый запрос отвечают отказом", cop.chat[1])

-- журнал
cop.chat = {}
say(cop, "/pcboard журнал")
ok(#cop.chat > 1 and cop.chat[1]:find("Ваши последние запросы", 1, true) ~= nil,
    "своя часть журнала печатается в чат", cop.chat[1])
admin.chat = {}
say(admin, "/pcboard журнал")
ok(#admin.chat > 1 and admin.chat[1]:find("Журнал запросов", 1, true) ~= nil,
    "с правом pcboard.audit виден весь журнал", admin.chat[1])

-- цель не найдена / нет доступа
cop.chat = {}
say(cop, "/pcboard несуществующее лицо 12345")
ok(#cop.chat == 1 and cop.chat[1]:find("никого не нашлось", 1, true) ~= nil, "по мусору честный ответ")
target.chat = {}
target._aim = cop
say(target, "/pcboard")
ok(#target.chat == 1 and target.chat[1]:find("нет доступа", 1, true) ~= nil,
    "гражданскому команда отвечает отказом", target.chat[1])
ok(say(cop, "/пробить") == "", "русский псевдоним команды работает")
runTimers()

print(("\nPCBOARD RUNTIME: %d/%d, провалов: %d"):format(total - fails, total, fails))
if fails > 0 then os.exit(1) end
