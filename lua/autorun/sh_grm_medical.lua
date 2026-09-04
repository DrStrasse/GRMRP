--[[--------------------------------------------------------------------
    GRM Medical Cards v1.0.0 (Код 86) — медицинские карты пациентов

    Врачи/медики ведут полноценные карты: диагнозы (актив/излечён),
    записи приёмов, назначения, операции, показания (группа крови,
    аллергии, хронические заболевания). Пациент видит свою карту сам.

    ДОСТУП через фракции (подвязка на систему Factions): суперадмин
    вручную включает медицинские фракции и ограничивает доступ по
    РАНГАМ (ролям) и ОТДЕЛАМ этой фракции — UI «Доступ» прямо в окне
    /medcards. Хранение: data/grm_medcards.json (карты, ключи SteamID64 —
    jsonT третьим аргументом, н65), data/grm_medcfg.json (доступы).

    Команды: /medcards (окно: у медика — список пациентов и редактор,
    у прочих — своя карта), /mycard (то же, сразу своя карта),
    консоль grm_medcards.

    v1.1.0 (Код 101, находка 118): ВЫДАЧА МЕДКАРТЫ НА РУКИ. У врача в
    редакторе карты кнопка «Выдать карту на руки» — пациенту падает в
    инвентарь предмет «Медицинская карта» (модель-бумажка, дропается и
    подбирается, sid64 владельца хранится в данных предмета). Кнопка
    «Использовать» в /inv открывает просмотр карты любому держателю
    (RP: физическую карту можно показать). Повторная выдача, пока карта
    есть в инвентаре пациента, закрыта; факт выдачи пишется в карту
    (поле issued + служебная запись журнала kind=«issue»).
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Medical = GRM.Medical or {}
local MD = GRM.Medical

MD.Version   = "2.0.0"
MD.ConfigFile = "grm_medcfg.json"
MD.CardsFile  = "grm_medcards.json"
MD.MaxEntries = 60

MD.BloodTypes = {
    "O(I) Rh+", "O(I) Rh−", "A(II) Rh+", "A(II) Rh−",
    "B(III) Rh+", "B(III) Rh−", "AB(IV) Rh+", "AB(IV) Rh−",
}

MD.FitnessCategories = {
    "А — Годен к военной службе и работе",
    "Б — Годен с незначительными ограничениями",
    "В — Ограниченно годен к службе",
    "Г — Временно не годен (на период лечения)",
    "Д — Не годен к военной службе",
}

MD.EntryKinds = {
    diagnosis    = "Диагноз",
    note         = "Запись приёма",
    vitals       = "Показания",
    prescription = "Назначение",
    operation    = "Операция",
    issue        = "Выдача карты", -- служебный вид: пишется только op «issue» (Код 101)
}

-- ── ЕДИНАЯ МЕДКАРТА: канонизация справочников ──────────────────────────
-- Разные UI когда-то писали разные форматы группы крови и ВВК
-- («I (0) Rh+» против «O(I) Rh+», «Д — Не годен… (освобождён)» против
-- ядра). Эти функции приводят ЛЮБОЙ старый формат к единому (MD.BloodTypes /
-- MD.FitnessCategories). Используются сервером при загрузке/сохранении и
-- доступны клиенту.

-- Группа крови → канонический «O(I) Rh+»… (буква группы + резус).
function MD.NormalizeBlood(v)
    v = tostring(v or "")
    if v == "" then return "" end
    local up = v:upper()
    local group
    if up:find("AB", 1, true) or up:find("IV", 1, true) then group = "AB(IV)"
    elseif up:find("III", 1, true) then group = "B(III)"
    elseif up:find("II", 1, true) then group = "A(II)"
    elseif up:find("A", 1, true) then group = "A(II)"
    elseif up:find("B", 1, true) then group = "B(III)"
    elseif up:find("O", 1, true) or up:find("0", 1, true) or up:find("I", 1, true) then group = "O(I)"
    else return v end
    local rh = (v:find("−", 1, true) or v:find("-", 1, true)) and "−" or "+"
    return group .. " Rh" .. rh
end

-- Категория годности ВВК → каноническая запись по букве (А–Д).
function MD.NormalizeFitness(v)
    v = tostring(v or "")
    if v == "" then return "" end
    local t = string.Trim(v)
    -- уже канонично — не трогаем
    for _, canon in ipairs(MD.FitnessCategories) do
        if t == canon then return canon end
    end
    -- первая буква категории: кириллица А–Д (2 байта в UTF-8) или латиница A–D
    local letter
    local first = t:sub(1, 2)
    if first == "А" or first == "Б" or first == "В" or first == "Г" or first == "Д" then
        letter = first
    else
        local lat = { A = "А", B = "Б", C = "В", D = "Г", E = "Д" }
        letter = lat[t:sub(1, 1):upper()]
    end
    if letter then
        for _, canon in ipairs(MD.FitnessCategories) do
            if canon:sub(1, 2) == letter then return canon end
        end
    end
    return v
end

-- Код 101: медицинская карта как предмет инвентаря («на руки»).
-- sid64 владельца лежит в данных предмета (slot.data.sid64) — дроп,
-- подбор и рестарт привязку не теряют (сейв инвентаря хранит data).
MD.CardItem      = "medcard"
MD.CardItemModel   = "models/props_lab/clipboard.mdl"
MD.CardItemModelFB = "models/props_c17/paper01.mdl" -- фолбэк (н85)

-- Код 106 (находка 123): гард ВНУТРИ регистратора (снаружи он гасил и
-- ретрай на перекошенной загрузке — урок «мёртвой кнопки» модулятора).
local function regMedCard()
    if not (GRM.Inventory and GRM.Inventory.RegisterItem) then return end
    local mdl = MD.CardItemModel
    if util.IsValidModel and not util.IsValidModel(mdl) then mdl = MD.CardItemModelFB end
    GRM.Inventory.RegisterItem(MD.CardItem, {
        type = "item",
        name = "Медицинская карта",
        desc = "Заполненная врачом карта пациента. «Использовать» — посмотреть карту. Не теряйте.",
        icon = "icon16/vcard.png",
        maxStack = 1,
        weight = 0.2,
        model = mdl,
        useFunc = "medcard_view",
    })
end
regMedCard()
timer.Simple(2, regMedCard) -- инвентарь мог подгрузиться позже (ретрай живёт ВСЕГДА)

local NET_OPEN   = "GRM_Med_Open"
local NET_CARD   = "GRM_Med_Card"
local NET_EDIT   = "GRM_Med_Edit"
local NET_ACCESS = "GRM_Med_Access"

-- CharacterKey — персональный владелец медицинской карты.
local function identityKey(ply)
    if IsValid(ply) and ply:IsPlayer() then
        if GRM.Identity and GRM.Identity.CharacterKey then return GRM.Identity.CharacterKey(ply) end
        return tostring(ply:SteamID64() or "")
    end
    local raw = tostring(ply or "")
    if raw:match(":char[1-3]$") then return raw end
    if raw:match("^%d+$") then return raw end
    if util.SteamIDTo64 then
        local s64 = util.SteamIDTo64(raw)
        if s64 and s64 ~= "0" then return tostring(s64) .. ":char1" end
    end
    return raw
end

-- общий помощник: членство с учётом обеих форм ключей (н101)
local function memberRec(f, ply)
    if not (istable(f) and istable(f.Members) and IsValid(ply)) then return nil end
    if GRM.Identity and GRM.Identity.FactionMember then return GRM.Identity.FactionMember(f, ply) end
    return f.Members[ply:SteamID()] or f.Members[ply:SteamID64()]
end
local function factionOf(ply)
    if not istable(Factions) or not IsValid(ply) then return nil end
    for name, f in pairs(Factions) do
        if istable(f) and memberRec(f, ply) then return name, f end
    end
    return nil
end
MD.FactionOf = factionOf

-- ============================================================
-- СЕРВЕР
-- ============================================================
if SERVER then
    for _, s in ipairs({ NET_OPEN, NET_CARD, NET_EDIT, NET_ACCESS }) do util.AddNetworkString(s) end

    local function jsonT(txt)
        local ok, t = pcall(util.JSONToTable, txt, false, true)
        return (ok and istable(t)) and t or nil
    end
    local function defaultCfg()
        return { factions = {} } -- ["Скорая"] = { enabled=true, allRoles=true, roles={}, allDepts=true, depts={} }
    end

    local function loadCfg()
        MD.Cfg = MD.Cfg or defaultCfg()
        local t = jsonT(file.Read(MD.ConfigFile, "DATA") or "")
        if istable(t) and istable(t.factions) then MD.Cfg.factions = t.factions end
    end
    function MD.SaveCfg(why)
        local ok, txt = pcall(util.TableToJSON, MD.Cfg or defaultCfg(), true)
        if ok and txt then
            file.Write(MD.ConfigFile, txt)
            local rb = file.Read(MD.ConfigFile, "DATA")
            print("[GRM Medical] SAVE ok cfg (" .. tostring(why or "?") .. "), read-back: " .. tostring(rb ~= nil))
        end
    end
    loadCfg()

    local function loadCards()
        MD.Cards = MD.Cards or {}
        local t = jsonT(file.Read(MD.CardsFile, "DATA") or "")
        if istable(t) then MD.Cards = t end

        -- ЕДИНАЯ МЕДКАРТА: миграция ключей. Канонический ключ — CharacterKey
        -- (`SteamID64:charN`). Голый SteamID64 и SteamID (STEAM_0:…) сводятся
        -- к `:char1`; дубликат (компьютер когда-то писал и `sid64`, и `sid64:charN`)
        -- схлопывается в ОДНУ запись.
        local remap = {}
        for key, card in pairs(MD.Cards) do
            if istable(card) then
                local ck = identityKey(key)
                if key:match("^%d+$") and not key:find(":", 1, true) then ck = key .. ":char1" end
                if ck ~= key then remap[#remap + 1] = { from = key, to = ck, card = card } end
            end
        end
        local migrated = false
        for _, r in ipairs(remap) do
            if not istable(MD.Cards[r.to]) then MD.Cards[r.to] = r.card end
            MD.Cards[r.from] = nil
            migrated = true
        end

        -- Нормализация справочников (группа крови, ВВК) к единому виду.
        local normalized = false
        for _, card in pairs(MD.Cards) do
            if istable(card) then
                if card.blood ~= nil and card.blood ~= "" then
                    local nb = MD.NormalizeBlood(card.blood)
                    if nb ~= card.blood then card.blood = nb normalized = true end
                end
                if card.fitnessCategory ~= nil and card.fitnessCategory ~= "" then
                    local nf = MD.NormalizeFitness(card.fitnessCategory)
                    if nf ~= card.fitnessCategory then card.fitnessCategory = nf normalized = true end
                end
            end
        end

        if migrated then MD._CardsMigrated = true end
        if migrated or normalized then MD.SaveCards("миграция ключей/справочников") end
    end

    -- Карта заведена? Без авто-создания (в отличие от CardOf — для обыска/документа).
    function MD.HasCard(key)
        key = tostring(key or "")
        if key == "" then return false end
        return istable(MD.Cards and MD.Cards[key])
    end
    function MD.SaveCards(why)
        local ok, txt = pcall(util.TableToJSON, MD.Cards or {}, true)
        if ok and txt then
            file.Write(MD.CardsFile, txt)
            local rb = file.Read(MD.CardsFile, "DATA")
            print("[GRM Medical] SAVE ok cards (" .. tostring(why or "?") .. "), записей: " .. tostring(table.Count(MD.Cards or {})) .. ", read-back: " .. tostring(rb ~= nil))
        end
    end
    MD.Save = MD.SaveCards
    GRM.Medical.SaveCards = MD.SaveCards
    GRM.Medical.Save = MD.SaveCards
    loadCards()
    GRM.Medical.Cards = MD.Cards

    local function rpName(ply)
        if not IsValid(ply) then return "?" end
        local n = ply:GetNWString("GRM_RPName", "")
        return (n ~= "" and n) or ply:Nick()
    end
    MD.RPName = rpName

    -- доступ к ведению карт: фракция включена + ранг/отдел из списков
    function MD.CanTreat(ply)
        if not IsValid(ply) then return false, "?" end
        if ply:IsSuperAdmin() then return true end
        local name, f = factionOf(ply)
        if not name then return false, "Вы не во фракции с медицинским доступом" end
        local c = (MD.Cfg.factions or {})[name]
        if not (istable(c) and c.enabled == true) then
            return false, "Фракция [" .. name .. "] не имеет медицинского доступа (настройка: /medcards → «Доступ» у суперадмина)"
        end
        local m = memberRec(f, ply) or {}
        if c.allRoles ~= true then
            if not (istable(c.roles) and c.roles[tostring(m.Role or "")] == true) then
                return false, "Ваш ранг во фракции не имеет медицинского доступа"
            end
        end
        if c.allDepts ~= true then
            if not (istable(c.depts) and c.depts[tostring(m.Department or "")] == true) then
                return false, "Ваш отдел не имеет медицинского доступа"
            end
        end
        return true
    end

    local function cardOf(sid64)
        sid64 = tostring(sid64 or "")
        if sid64 == "" then return nil end
        local c = MD.Cards[sid64]
        if not istable(c) then
            c = {
                name = "?",
                blood = "",
                allergies = "",
                chronic = "",
                fitnessCategory = "А — Годен к военной службе и работе",
                entries = {},
                created = os.time(),
                updated = 0
            }
            MD.Cards[sid64] = c
        end
        c.entries = istable(c.entries) and c.entries or {}
        if not c.fitnessCategory or c.fitnessCategory == "" then
            c.fitnessCategory = "А — Годен к военной службе и работе"
        end
        return c
    end
    MD.CardOf = cardOf

    local function pushCard(ply, sid64, canEdit)
        net.Start(NET_CARD)
            net.WriteString(sid64)
            net.WriteTable(cardOf(sid64) or {})
            net.WriteBool(canEdit == true)
        net.Send(ply)
    end

    -- главное окно: список пациентов + моя карта + доступы (админу)
    local function pushOpen(ply)
        local doctor = MD.CanTreat(ply)
        local online = {}
        if doctor then
            for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                if IsValid(p) and p ~= ply then
                    online[#online + 1] = { sid64 = identityKey(p), name = rpName(p), fac = factionOf(p) or "—" }
                end
            end
            table.sort(online, function(a, b) return tostring(a.name) < tostring(b.name) end)
        end
        local records = {}
        if doctor then
            local seenOnline = {}
            for _, o in ipairs(online) do seenOnline[o.sid64] = true end
            for sid64, c in pairs(MD.Cards or {}) do
                if not seenOnline[sid64] and istable(c) then
                    records[#records + 1] = { sid64 = sid64, name = tostring(c.name or "?"), fac = "(архив)" }
                end
            end
            table.sort(records, function(a, b) return tostring(a.name) < tostring(b.name) end)
            while #records > 200 do table.remove(records) end
        end
        local access = nil
        if ply:IsSuperAdmin() then
            local fnames = {}
            for name in pairs(Factions or {}) do fnames[#fnames + 1] = name end
            table.sort(fnames)
            access = { cfg = MD.Cfg.factions or {}, factions = fnames }
        end
        net.Start(NET_OPEN)
            net.WriteTable({
                doctor = doctor == true, admin = ply:IsSuperAdmin(),
                online = online, records = records, access = access,
                mySid64 = identityKey(ply),
            })
        net.Send(ply)
    end

    net.Receive(NET_OPEN, function(_, ply)
        if not IsValid(ply) then return end
        pushOpen(ply)
    end)

    net.Receive(NET_CARD, function(_, ply)
        if not IsValid(ply) then return end
        local sid64 = tostring(net.ReadString() or "")
        if sid64 == "" then return end
        local doctor = MD.CanTreat(ply)
        if sid64 ~= identityKey(ply) and not doctor then
            if GRM.Notify then GRM.Notify(ply, "Доступ к чужим картам — только у медиков.", 255, 140, 110) end
            return
        end
        -- актуализируем кэш имени по онлайну
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if identityKey(p) == sid64 then cardOf(sid64).name = rpName(p) break end
        end
        pushCard(ply, sid64, doctor == true)
    end)

    -- Код 101: просмотр карты с физического предмета на руках
    -- («Использовать» в инвентаре, useFunc medcard_view). RP-логика
    -- физического носителя: держишь карту в руках — значит, можешь её
    -- прочитать (и показать врачу/полиции), даже если она чужая.
    -- Править по-прежнему может только персонал с доступом.
    function MD.ViewIssued(ply, data)
        if not IsValid(ply) then return end
        data = istable(data) and data or {}
        local sid64 = tostring(data.ownerKey or data.sid64 or "")
        -- Легаси-карта без instance-data могла принадлежать только текущему
        -- держателю. Чужие современные карты всегда имеют ownerKey.
        if sid64 == "" and MD.HasCard(identityKey(ply)) then sid64 = identityKey(ply) end
        if sid64 == "" then
            if GRM.Notify then GRM.Notify(ply, "Пустой бланк карты — на нём нет печати выдачи. Заполненную выдаёт врач (окно /medcards).", 255, 200, 90) end
            return
        end
        -- актуализируем имя по онлайну (карта могла выехать с давним сейвом)
        local c0 = MD.Cards[sid64]
        if istable(c0) then
            for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                if IsValid(p) and identityKey(p) == sid64 then c0.name = rpName(p) break end
            end
        end
        pushOpen(ply) -- окно: у медика — полная редакция, у прочих — просмотр
        -- карту шлём чуть позже открытия: у пациентского окна есть
        -- авто-запрос своей карты на 0.1с — наш снапшот должен лечь поверх.
        timer.Simple(0.2, function()
            if not IsValid(ply) then return end
            pushCard(ply, sid64, MD.CanTreat(ply) == true)
        end)
    end

    net.Receive(NET_EDIT, function(_, ply)
        if not IsValid(ply) then return end
        if not MD.CanTreat(ply) then
            if GRM.Notify then GRM.Notify(ply, "Нет медицинского доступа.", 255, 140, 110) end
            return
        end
        local op = tostring(net.ReadString() or "")
        local sid64 = tostring(net.ReadString() or "")
        if sid64 == "" then return end
        local card = cardOf(sid64)
        if not card then return end
        local myName = rpName(ply)
        local myFac = factionOf(ply) or "—"

        if op == "vitals" then
            local blood   = tostring(net.ReadString() or "")
            card.allergies= string.sub(string.Trim(tostring(net.ReadString() or "")), 1, 300)
            card.chronic  = string.sub(string.Trim(tostring(net.ReadString() or "")), 1, 300)
            local fitness = tostring(net.ReadString() or "")
            if fitness ~= "" then card.fitnessCategory = fitness end

            local okBlood = false
            for _, b in ipairs(MD.BloodTypes) do if b == blood then okBlood = true break end end
            card.blood = okBlood and blood or ""
            card.updated = os.time()
            MD.SaveCards("vitals " .. sid64)
            pushCard(ply, sid64, true)
            if GRM.Notify then GRM.Notify(ply, "Показания сохранены.", 120, 220, 140) end
            return
        end

        if op == "add" then
            local kind = tostring(net.ReadString() or "")
            if not MD.EntryKinds[kind] then return end
            if kind == "issue" then return end -- служебная: ставит только кнопка выдачи
            local text = string.sub(string.Trim(tostring(net.ReadString() or "")), 1, 500)
            if text == "" then return end
            card.name = tostring(net.ReadString() or card.name or "?")
            card.entries[#card.entries + 1] = {
                ts = os.time(), doctor = myName, doctorSid64 = identityKey(ply),
                doctorFac = myFac, kind = kind, text = text,
                active = (kind == "diagnosis") and true or nil,
            }
            while #card.entries > MD.MaxEntries do table.remove(card.entries, 1) end
            card.updated = os.time()
            MD.SaveCards("entry " .. kind .. " " .. sid64)
            pushCard(ply, sid64, true)
            -- уведомить пациента, если он онлайн
            for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                if identityKey(p) == sid64 and GRM.Notify then
                    GRM.Notify(p, "В вашу мед.карту добавлено: " .. (MD.EntryKinds[kind] or kind) .. " — «" .. text .. "» (" .. myName .. ")", 120, 200, 255)
                end
            end
            return
        end

        if op == "toggle" then
            local idx = math.floor(net.ReadUInt(8))
            local e = card.entries[idx]
            if not istable(e) or e.kind ~= "diagnosis" then return end
            e.active = not (e.active == true)
            card.updated = os.time()
            MD.SaveCards("toggle dx " .. sid64)
            pushCard(ply, sid64, true)
            return
        end

        if op == "del" then
            if not ply:IsSuperAdmin() then return end
            local idx = math.floor(net.ReadUInt(8))
            if not istable(card.entries[idx]) then return end
            table.remove(card.entries, idx)
            card.updated = os.time()
            MD.SaveCards("del entry " .. sid64)
            pushCard(ply, sid64, true)
            return
        end

        -- Код 101: выдать медицинскую карту пациенту «на руки» (предмет инвентаря).
        if op == "issue" then
            if not (GRM.Inventory and GRM.Inventory.AddItem and GRM.Inventory.CountItem) then
                if GRM.Notify then GRM.Notify(ply, "Инвентарь недоступен — выдача карт невозможна.", 255, 140, 110) end
                return
            end
            if sid64 == identityKey(ply) then
                if GRM.Notify then GRM.Notify(ply, "Себе карту выдавать не нужно — своя карта всегда у вас в /mycard.", 255, 200, 90) end
                return
            end
            local patient
            for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                if IsValid(p) and identityKey(p) == sid64 then patient = p break end
            end
            if not IsValid(patient) then
                if GRM.Notify then GRM.Notify(ply, "Пациент не в сети — выдать карту на руки нельзя.", 255, 200, 90) end
                return
            end
            if GRM.Inventory.CountItem(patient, MD.CardItem) > 0 then
                if GRM.Notify then GRM.Notify(ply, "У этого пациента уже есть медкарта на руках.", 255, 200, 90) end
                return
            end
            local left = GRM.Inventory.AddItem(patient, MD.CardItem, 1, { sid64 = sid64, ownerKey = sid64, ownerName = rpName(patient), docType = "medcard" })
            if (left or 1) > 0 then
                if GRM.Notify then GRM.Notify(ply, "В инвентаре пациента нет места.", 255, 140, 110) end
                return
            end
            card.name = rpName(patient)
            card.issued = { ts = os.time(), doctor = myName, doctorSid64 = identityKey(ply) }
            card.entries[#card.entries + 1] = {
                ts = os.time(), doctor = myName, doctorSid64 = identityKey(ply),
                doctorFac = myFac, kind = "issue", text = "Медицинская карта выдана на руки",
            }
            while #card.entries > MD.MaxEntries do table.remove(card.entries, 1) end
            card.updated = os.time()
            MD.SaveCards("issue " .. sid64)
            pushCard(ply, sid64, true)
            if GRM.Notify then
                GRM.Notify(ply, "Медкарта выдана на руки: " .. rpName(patient), 120, 220, 140)
                GRM.Notify(patient, "Врач " .. myName .. " выдал вам медицинскую карту — она в инвентаре (/inv).", 120, 220, 140)
            end
            return
        end
    end)

    net.Receive(NET_ACCESS, function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        local fname = tostring(net.ReadString() or "")
        if fname == "" or not (istable(Factions) and Factions[fname]) then return end
        local upd = net.ReadTable()
        if not istable(upd) then return end
        MD.Cfg.factions = MD.Cfg.factions or {}
        local c = MD.Cfg.factions[fname] or {}
        MD.Cfg.factions[fname] = c
        c.enabled  = upd.enabled == true
        c.allRoles = upd.allRoles ~= false
        c.allDepts = upd.allDepts ~= false
        c.roles = {}
        if istable(upd.roles) then
            for k, v in pairs(upd.roles) do if v == true then c.roles[tostring(k)] = true end end
        end
        c.depts = {}
        if istable(upd.depts) then
            for k, v in pairs(upd.depts) do if v == true then c.depts[tostring(k)] = true end end
        end
        MD.SaveCfg("access " .. fname)
        if GRM.Notify then GRM.Notify(ply, "Мед.доступ фракции [" .. fname .. "] сохранён: " .. (c.enabled and "ВКЛ" or "ВЫКЛ"), 120, 220, 140) end
        pushOpen(ply) -- свежий снапшот в окно
    end)

    -- команды (двойной паттерн н75)
    function MD.HandleChat(ply, text)
        local low = string.lower(string.Trim(text or ""))
        if low == "/medcards" or low == "/mycard" then
            pushOpen(ply)
            return true
        end
        return false
    end
    hook.Add("PlayerSay", "GRM_Med_TransformCmds", function(ply, text, teamSays)
        local datapack = { tostring(text or ""), SkipPlayerSay = false }
            if not istable(datapack) then return end
            local msg = datapack[1]
            if not isstring(msg) then return end
            if MD.HandleChat and MD.HandleChat(ply, msg) then
                datapack[1] = ""
                datapack.SkipPlayerSay = true
            end

        if datapack.SkipPlayerSay == true then return "" end
    end)
    hook.Add("PlayerSay", "GRM_Med_Cmds", function(ply, text)
        if MD.HandleChat and MD.HandleChat(ply, text) then return "" end
    end)
    concommand.Add("grm_medcards", function(ply) if IsValid(ply) then pushOpen(ply) end end)

    print("[GRM Medical] Сервер v" .. MD.Version .. " загружен (Код 86)")
end

-- ============================================================
-- КЛИЕНТ
-- ============================================================
if CLIENT then
    surface.CreateFont("GRMMed_Title", { font = "Roboto", size = 19, weight = 800, extended = true })
    surface.CreateFont("GRMMed_Sub",   { font = "Roboto", size = 14, weight = 700, extended = true })
    surface.CreateFont("GRMMed_Text",  { font = "Roboto", size = 12, weight = 500, extended = true })

    local MC = {
        bg    = Color(18, 26, 30, 252), head = Color(24, 38, 44, 255), panel = Color(30, 44, 50, 245),
        acc   = Color(80, 190, 180), green = Color(60, 190, 110), red = Color(220, 75, 70),
        yellow= Color(230, 180, 60), text = Color(238, 248, 248), dim = Color(155, 175, 180),
    }

    local _frame
    local _open, _card, _cardSid = nil, nil, nil
    local _buildCardView -- форвард (урок ctx: замыканию нужна декларация заранее)

    local function kindLabel(k) return MD.EntryKinds[k] or k end

    local function mkBtn(p, txt, col, w0, h0)
        local b = vgui.Create("DButton", p)
        b:SetText(txt) b:SetFont("GRMMed_Sub") b:SetTextColor(color_white)
        if w0 then b:SetWide(w0) end if h0 then b:SetTall(h0) end
        b.Paint = function(self, pw, ph)
            local cc = col or MC.acc
            if not self:IsEnabled() then cc = Color(60, 65, 75)
            elseif self:IsHovered() then cc = Color(math.min(255, cc.r + 22), math.min(255, cc.g + 22), math.min(255, cc.b + 22)) end
            draw.RoundedBox(5, 0, 0, pw, ph, cc)
        end
        return b
    end

    -- ---------- отрисовка содержимого карты ----------
    _buildCardView = function(parent, x0, w0, card, canEdit)
        if not istable(card) then
            local d = vgui.Create("DLabel", parent)
            d._medCardDyn = true
            d:SetPos(x0, 10) d:SetSize(w0, 30) d:SetFont("GRMMed_Sub") d:SetTextColor(MC.dim)
            d:SetText("Карта не выбрана.")
            return
        end

        local y = 6
        local lbl = vgui.Create("DLabel", parent)
        lbl._medCardDyn = true
        lbl:SetPos(x0, y) lbl:SetSize(w0, 24) lbl:SetFont("GRMMed_Title") lbl:SetTextColor(MC.text)
        lbl:SetText("Пациент: " .. tostring(card.name or "?"))
        y = y + 30

        -- группа крови
        local bl = vgui.Create("DLabel", parent)
        bl._medCardDyn = true
        bl:SetPos(x0, y) bl:SetSize(150, 22) bl:SetFont("GRMMed_Sub") bl:SetTextColor(MC.dim)
        bl:SetText("Группа крови:")
        local bsel = vgui.Create("DComboBox", parent)
        bsel._medCardDyn = true
        bsel:SetPos(x0 + 150, y - 2) bsel:SetSize(190, 26) bsel:SetFont("GRMMed_Text")
        bsel:SetValue(card.blood ~= "" and card.blood or "— не указана —")
        for _, b in ipairs(MD.BloodTypes) do bsel:AddChoice(b, b, card.blood == b) end
        bsel:SetEnabled(canEdit == true)
        y = y + 30

        -- категория годности
        local fl = vgui.Create("DLabel", parent)
        fl._medCardDyn = true
        fl:SetPos(x0, y) fl:SetSize(150, 22) fl:SetFont("GRMMed_Sub") fl:SetTextColor(MC.dim)
        fl:SetText("Категория годности:")
        local fsel = vgui.Create("DComboBox", parent)
        fsel._medCardDyn = true
        fsel:SetPos(x0 + 150, y - 2) fsel:SetSize(340, 26) fsel:SetFont("GRMMed_Text")
        fsel:SetValue(card.fitnessCategory or "А — Годен к военной службе и работе")
        for _, fit in ipairs(MD.FitnessCategories) do fsel:AddChoice(fit, fit, card.fitnessCategory == fit) end
        fsel:SetEnabled(canEdit == true)
        y = y + 34

        local function mkEditBlock(title, key, val)
            local d = vgui.Create("DLabel", parent)
            d._medCardDyn = true
            d:SetPos(x0, y) d:SetSize(w0, 20) d:SetFont("GRMMed_Sub") d:SetTextColor(MC.acc)
            d:SetText(title)
            y = y + 22
            local e = vgui.Create("DTextEntry", parent)
            e._medCardDyn = true
            e:SetPos(x0, y) e:SetSize(w0, 46) e:SetFont("GRMMed_Text")
            e:SetMultiline(true) e:SetText(val or "")
            e:SetEnabled(canEdit == true)
            y = y + 52
            return e
        end
        local eAllerg = mkEditBlock("Аллергии:", "allergies", card.allergies)
        local eChron  = mkEditBlock("Хронические заболевания:", "chronic", card.chronic)

        if canEdit then
            local bVit = mkBtn(parent, "Сохранить показания", MC.green, 220, 30)
            bVit._medCardDyn = true
            bVit:SetPos(x0, y)
            bVit.DoClick = function()
                local _, blood = bsel:GetSelected()
                local _, fitness = fsel:GetSelected()
                net.Start(NET_EDIT)
                    net.WriteString("vitals")
                    net.WriteString(_cardSid or "")
                    net.WriteString(tostring(blood or ""))
                    net.WriteString(eAllerg:GetValue() or "")
                    net.WriteString(eChron:GetValue() or "")
                    net.WriteString(tostring(fitness or ""))
                net.SendToServer()
            end
        end
        y = y + 40

        -- записи
        local dl = vgui.Create("DLabel", parent)
        dl._medCardDyn = true
        dl:SetPos(x0, y) dl:SetSize(w0, 20) dl:SetFont("GRMMed_Sub") dl:SetTextColor(MC.acc)
        dl:SetText("Записи карты (" .. tostring(#(card.entries or {})) .. "):")
        y = y + 24

        local sc = vgui.Create("DScrollPanel", parent)
        sc._medCardDyn = true
        sc:SetPos(x0, y) sc:SetSize(w0, 170)
        local entries = card.entries or {}
        if #entries == 0 then
            local d = vgui.Create("DLabel", sc)
            d:Dock(TOP) d:SetTall(22) d:SetFont("GRMMed_Text") d:SetTextColor(MC.dim)
            d:SetText("Записей пока нет.")
        end
        for i = #entries, 1, -1 do
            local e = entries[i]
            local row = vgui.Create("DPanel", sc)
            row:Dock(TOP) row:DockMargin(0, 0, 0, 4)
            row:SetTall(48)
            local isDx = e.kind == "diagnosis"
            local active = e.active == true
            row.Paint = function(_, pw, ph)
                local cc = MC.panel
                if isDx then cc = active and Color(90, 40, 42, 245) or Color(38, 58, 44, 245) end
                draw.RoundedBox(5, 0, 0, pw, ph, cc)
                local head = os.date("%d.%m.%Y %H:%M", e.ts or 0) .. " • " .. kindLabel(e.kind)
                    .. (isDx and (active and " [АКТИВЕН]" or " [излечён]") or "")
                    .. " • " .. tostring(e.doctor or "?") .. " (" .. tostring(e.doctorFac or "—") .. ")"
                draw.SimpleText(head, "GRMMed_Text", 8, 6, isDx and (active and Color(255, 150, 150) or Color(150, 230, 160)) or MC.acc, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                draw.SimpleText(tostring(e.text or ""), "GRMMed_Text", 8, 24, MC.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            end
            if canEdit and isDx then
                local bt = mkBtn(row, active and "Излечён" or "Вернуть", active and MC.green or MC.yellow, 90, 24)
                bt:SetPos(w0 - 100, 12) bt:SetFont("GRMMed_Text")
                bt.DoClick = function()
                    net.Start(NET_EDIT)
                        net.WriteString("toggle")
                        net.WriteString(_cardSid or "")
                        net.WriteUInt(i, 8)
                    net.SendToServer()
                end
            end
        end
        y = y + 178

        -- форма добавления записи
        if canEdit then
            local ksel = vgui.Create("DComboBox", parent)
            ksel._medCardDyn = true
            ksel:SetPos(x0, y) ksel:SetSize(180, 28) ksel:SetFont("GRMMed_Text")
            ksel:SetValue("Запись приёма")
            for k, lab in pairs(MD.EntryKinds) do
                if k ~= "issue" then ksel:AddChoice(lab, k, k == "note") end -- issue — только кнопкой выдачи (Код 101)
            end

            local txt = vgui.Create("DTextEntry", parent)
            txt._medCardDyn = true
            txt:SetPos(x0 + 188, y) txt:SetSize(w0 - 300, 28) txt:SetFont("GRMMed_Text")
            txt:SetPlaceholderText("текст записи…")

            local bAdd = mkBtn(parent, "Добавить", MC.acc, 104, 28)
            bAdd._medCardDyn = true
            bAdd:SetPos(x0 + w0 - 108, y)
            bAdd.DoClick = function()
                local _, kind = ksel:GetSelected()
                kind = tostring(kind or "note")
                local t = string.Trim(txt:GetValue() or "")
                if t == "" then return end
                net.Start(NET_EDIT)
                    net.WriteString("add")
                    net.WriteString(_cardSid or "")
                    net.WriteString(kind)
                    net.WriteString(t)
                    net.WriteString(tostring(card.name or "?"))
                net.SendToServer()
                txt:SetText("")
            end

            -- Код 101: выдача медкарты пациенту «на руки» (предмет инвентаря)
            local bIssue = mkBtn(parent, "Выдать карту на руки", MC.acc, 190, 28)
            bIssue._medCardDyn = true
            bIssue:SetPos(x0, y + 34)
            bIssue.DoClick = function()
                net.Start(NET_EDIT)
                    net.WriteString("issue")
                    net.WriteString(_cardSid or "")
                net.SendToServer()
            end
            local iss = vgui.Create("DLabel", parent)
            iss._medCardDyn = true
            iss:SetPos(x0 + 200, y + 38) iss:SetSize(w0 - 200, 22)
            iss:SetFont("GRMMed_Text") iss:SetTextColor(MC.dim)
            if istable(card.issued) then
                iss:SetText("выдана на руки: " .. os.date("%d.%m.%Y %H:%M", tonumber(card.issued.ts) or 0)
                    .. " • " .. tostring(card.issued.doctor or "?"))
            else
                iss:SetText("на руки ещё не выдана")
            end
        end
    end

    -- ---------- вкладка доступа (суперадмин) ----------
    local _buildAccessView
    _buildAccessView = function(parent, accData)
        for _, ch in ipairs(parent:GetChildren()) do ch:Remove() end
        if not istable(accData) then
            local d = vgui.Create("DLabel", parent)
            d:SetPos(10, 10) d:SetSize(680, 24) d:SetFont("GRMMed_Sub") d:SetTextColor(MC.dim)
            d:SetText("Нет данных доступа.")
            return
        end
        local fnameList = accData.factions or {}
        local cfg = accData.cfg or {}

        local cmb = vgui.Create("DComboBox", parent)
        cmb:SetPos(10, 10) cmb:SetSize(340, 28) cmb:SetFont("GRMMed_Sub")
        cmb:SetValue("Выберите фракцию…")
        for _, name in ipairs(fnameList) do cmb:AddChoice(name, name) end

        local body = vgui.Create("DPanel", parent)
        body:SetPos(10, 48) body:SetSize(690, 400)
        body.Paint = function(_, pw, ph) draw.RoundedBox(6, 0, 0, pw, ph, MC.panel) end

        local function rebuild(fname)
            for _, ch in ipairs(body:GetChildren()) do ch:Remove() end
            local f = Factions and Factions[fname]
            local roles = (istable(f) and istable(f.Roles) and f.Roles) or {}
            local depts = (istable(f) and istable(f.Departments) and f.Departments) or {}
            local c = cfg[fname] or {}
            local st = { enabled = c.enabled == true, allRoles = c.allRoles ~= false, allDepts = c.allDepts ~= false,
                         roles = {}, depts = {} }
            if istable(c.roles) then for k, v in pairs(c.roles) do st.roles[k] = v == true end end
            if istable(c.depts) then for k, v in pairs(c.depts) do st.depts[k] = v == true end end

            local function chk(x0, y0, label0, val0, fn)
                local cb = vgui.Create("DCheckBoxLabel", body)
                cb:SetPos(x0, y0) cb:SetSize(320, 22) cb:SetFont("GRMMed_Sub") cb:SetTextColor(MC.text)
                cb:SetText(label0) cb:SetChecked(val0 == true)
                cb.OnChange = function(_, v) fn(v == true) end
                return cb
            end

            chk(12, 10, "Фракция — медицинская (доступ к картам)", st.enabled, function(v) st.enabled = v end)
            chk(12, 38, "Все ранги могут вести карты", st.allRoles, function(v) st.allRoles = v end)
            local roleBoxes = {}
            local ry = 66
            for i, r in ipairs(roles) do
                local lbl = vgui.Create("DCheckBoxLabel", body)
                lbl:SetPos(24, ry + (i - 1) * 24) lbl:SetSize(300, 22) lbl:SetFont("GRMMed_Text") lbl:SetTextColor(MC.dim)
                lbl:SetText("ранг: " .. tostring(r)) lbl:SetChecked(st.roles[r] == true)
                lbl.role = r
                lbl.OnChange = function(self, v) st.roles[self.role] = v == true end
                roleBoxes[i] = lbl
            end
            local y2 = 66 + math.max(1, #roles) * 24 + 8
            chk(12, y2, "Все отделы (иначе — только отмеченные)", st.allDepts, function(v) st.allDepts = v end)
            for i, dpt in ipairs(depts) do
                local lbl = vgui.Create("DCheckBoxLabel", body)
                lbl:SetPos(24, y2 + 28 + (i - 1) * 24) lbl:SetSize(300, 22) lbl:SetFont("GRMMed_Text") lbl:SetTextColor(MC.dim)
                lbl:SetText("отдел: " .. tostring(dpt)) lbl:SetChecked(st.depts[dpt] == true)
                lbl.dept = dpt
                lbl.OnChange = function(self, v) st.depts[self.dept] = v == true end
            end

            local bSave = mkBtn(body, "Сохранить доступ", MC.green, 220, 32)
            bSave:SetPos(12, y2 + 34 + math.max(1, #depts) * 24 + 10)
            bSave.DoClick = function()
                net.Start(NET_ACCESS)
                    net.WriteString(fname)
                    net.WriteTable({ enabled = st.enabled, allRoles = st.allRoles, allDepts = st.allDepts,
                                     roles = st.roles, depts = st.depts })
                net.SendToServer()
            end
        end

        cmb.OnSelect = function(_, _, _, data0)
            rebuild(tostring(data0 or ""))
        end
    end

    -- ---------- главное окно ----------
    local function openWindow()
        if IsValid(_frame) then _frame:Remove() _frame = nil end
        net.Start(NET_OPEN) net.SendToServer()
    end

    net.Receive(NET_OPEN, function()
        _open = net.ReadTable() or {}
        local o = _open
        local f = vgui.Create("DFrame")
        _frame = f
        f:SetTitle("") f:SetSize(760, 600) f:Center() f:MakePopup() f:ShowCloseButton(false)
        f.Paint = function(_, pw, ph)
            draw.RoundedBox(8, 0, 0, pw, ph, MC.bg)
            draw.RoundedBoxEx(8, 0, 0, pw, 42, MC.head, true, true, false, false)
            draw.SimpleText("GRM — Медицинские карты", "GRMMed_Title", 14, 21, MC.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        local x = vgui.Create("DButton", f)
        x:SetText("X") x:SetFont("GRMMed_Title") x:SetTextColor(color_white)
        x:SetPos(760 - 40, 7) x:SetSize(32, 28)
        x.Paint = function(self, pw, ph) draw.RoundedBox(4, 0, 0, pw, ph, self:IsHovered() and MC.red or Color(45, 52, 68)) end
        x.DoClick = function() f:Remove() _frame = nil end

        local tabs = vgui.Create("DPropertySheet", f)
        tabs:SetPos(8, 48) tabs:SetSize(744, 544)

        -- вкладка карты (у всех: сперва своя/выбранная)
        local pCard = vgui.Create("DPanel", tabs)
        pCard:SetPaintBackground(false)
        pCard._medScroll = vgui.Create("DScrollPanel", pCard)
        pCard._medScroll:Dock(FILL)
        tabs:AddSheet(" Карта пациента ", pCard, "icon16/heart.png")

        local function redrawCard(card, canEdit)
            local scp = pCard._medScroll
            for _, ch in ipairs(scp:GetCanvas():GetChildren()) do ch:Remove() end
            local wrap = vgui.Create("DPanel")
            wrap:SetSize(710, 940)
            wrap.Paint = function() end
            scp:AddItem(wrap)
            _buildCardView(wrap, 8, 694, card, canEdit)
        end
        f._medRedraw = redrawCard

        if o.doctor then
            -- список пациентов
            local pList = vgui.Create("DPanel", tabs)
            pList:SetPaintBackground(false)
            tabs:AddSheet(" Пациенты ", pList, "icon16/group.png")
            local lv = vgui.Create("DListView", pList)
            lv:Dock(FILL) lv:DockMargin(6, 6, 6, 6) lv:SetMultiSelect(false)
            lv:AddColumn("Пациент") lv:AddColumn("Фракция")
            lv:AddColumn("SteamID64")
            local function fill(rows, tag)
                for _, r in ipairs(rows or {}) do
                    local ln = lv:AddLine(tostring(r.name or "?"), tostring(r.fac or "—"), tostring(r.sid64 or ""))
                    ln.sid64 = tostring(r.sid64 or "")
                end
            end
            fill(o.online, "online")
            fill(o.records, "records")
            lv.OnRowSelected = function(_, _, row)
                _cardSid = row.sid64
                net.Start(NET_CARD)
                    net.WriteString(row.sid64)
                net.SendToServer()
                -- перекинуть на вкладку карты
                tabs:SetActiveTab(tabs.Items[1].Tab)
            end

            -- вкладка доступа (суперадмин)
            if o.admin then
                local pAcc = vgui.Create("DPanel", tabs)
                pAcc:SetPaintBackground(false)
                tabs:AddSheet(" Доступ ", pAcc, "icon16/key.png")
                _buildAccessView(pAcc, o.access)
            end
        else
            -- пациент: просим свою карту
            _cardSid = o.mySid64
            timer.Simple(0.1, function()
                if not IsValid(f) then return end
                net.Start(NET_CARD)
                    net.WriteString(tostring(o.mySid64 or ""))
                net.SendToServer()
            end)
        end
    end)

    net.Receive(NET_CARD, function()
        local sid64 = net.ReadString()
        _card = net.ReadTable() or {}
        local canEdit = net.ReadBool()
        _cardSid = sid64
        if IsValid(_frame) and _frame._medRedraw then
            _frame._medRedraw(_card, canEdit)
        end
    end)

    -- команда/ярлык: сервер присылает OPEN по /medcards; клиентское окно
    -- открывается из net.Receive — отдельной клиентской команды не нужно
    concommand.Add("grm_medcards_cl", openWindow)

    print("[GRM Medical] Клиент v" .. MD.Version .. " загружен")
end

-- Вечер-18: команда разбирается внутри парсера модуля (не литералом в
-- хуке) — регистрируем её множество в едином внешнем словаре библиотеки,
-- иначе на режиме она стала бы «неизвестной» до цепочки.
if GRM and GRM.Chat and GRM.Chat.RegisterExternalCommands then
    GRM.Chat.RegisterExternalCommands({ "/medcards", "/mycard" })
end
