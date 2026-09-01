--[[--------------------------------------------------------------------
    GRM Comp Terminal v1.0.1 — общая серверная логика служебных
    терминалов Полиции Порядка и Полевой жандармерии.

    Закрывает дефекты аудита:
      Д2 — у жандармерии не было своего обработчика (клиент слал команды
           в полицейский канал); теперь у каждого терминала свой канал;
      Д5 — net.Receive не проверял права: приём проверяет CanEdit,
           юрисдикцию, валидность и дистанцию до терминала, rate-limit;
      Д6 — ENT:Use слал клиенту Documents.Registry и всю базу розыска
           целиком; теперь уходит только срез своей юрисдикции с
           ограничением по количеству записей;
      Д8 — разделение гражданской и военной юрисдикций;
      Д11 — цель ищется не только среди онлайн-игроков.
----------------------------------------------------------------------]]

if CLIENT then return end

GRM = GRM or {}
GRM.CompTerminal = GRM.CompTerminal or {}
local T = GRM.CompTerminal
T.Version = "1.2.0 — ходатайства на ордер"

util.AddNetworkString("GRM_CompTerminal_Act")
util.AddNetworkString("GRM_CompTerminal_Result")
util.AddNetworkString("GRM_CompTerminal_Fines")

-- Максимум записей розыска и штрафов, отправляемых при открытии.
-- Полный дамп базы в net-сообщении упирался в лимит 64 КБ.
T.MaxRecordsSent = 150
T.MaxFinesSent   = 120
T.UseRange       = 200   -- юнитов от терминала

local function notify(ply, msg, r, g, b)
    if not IsValid(ply) then return end
    if GRM.Notify then GRM.Notify(ply, msg, r or 255, g or 120, b or 100)
    else ply:ChatPrint("[Терминал] " .. msg) end
end
T.Notify = notify

-- Ключ персонажа — канон ядра (§5.2.6): одна реализация на проект,
-- ранняя привязка безопасна, sh_01_grm_core.lua грузится первым.
local charKey = GRM.CharKey
T.CharKey = charKey

-----------------------------------------------------------------------
-- Права
-----------------------------------------------------------------------
--- Может ли игрок работать с терминалом указанной юрисдикции.
-- Единый источник истины — GRM.Wanted.CanView/CanEdit (AccessManager,
-- data/grm_wanted/access.json). Старая эвристика по названию фракции
-- остаётся ФОЛБЭКОМ: если доступы ещё не настроены, сервер не должен
-- внезапно потерять работающие терминалы.
function T.CanManage(ply, jurisdiction, ent)
    if not (IsValid(ply) and ply:IsPlayer()) then return false end
    if ply:IsSuperAdmin() then return true end
    if IsValid(ent) and GRM.CompAccess and GRM.CompAccess.GetRaw(ent) ~= ""
        and not GRM.CompAccess.Allowed(ent, ply) then
        return false
    end

    local W = GRM.Wanted
    if W and isfunction(W.CanView) then
        local granted = W.CanView(ply)
        if granted then
            -- доступ есть — сверяем юрисдикцию
            if isfunction(W.CanUseJurisdiction) then
                return W.CanUseJurisdiction(ply, jurisdiction)
            end
            return true
        end
    end

    -- Фолбэк: эвристика по названию фракции + бейджи документов.
    local fName = ply:GetNWString("GRM_Faction", "")
    if fName == "" then return false end
    local low = string.lower(fName)

    local armyDesk = IsValid(ent) and ent.IsArmyDesk and ent:IsArmyDesk()
    local patterns
    if armyDesk then
        -- ПК ВС: не жандармерия. «Вооружённые силы» не содержит «военн».
        if low == "вс" or low == "vs" or low == "bundeswehr" then return true end
        patterns = { "вооруж", "armed", "armee", "bundeswehr", "вермахт", "wehr", "army" }
    elseif jurisdiction == "military" then
        patterns = { "feldgendarmerie", "жандарм", "военн", "комендат" }
    else
        patterns = { "ordnung", "polizei", "полиц", "порядк" }
    end

    for _, pat in ipairs(patterns) do
        if string.find(low, pat, 1, true) then return true end
    end

    local docs = GRM.Documents and GRM.Documents.Templates and GRM.Documents.Templates.access
    if istable(docs) then
        if jurisdiction == "military" and istable(docs.military) and docs.military[fName] == true then return true end
        if istable(docs.badges) and docs.badges[fName] == true then return true end
    end
    return false
end

--- Право изменять записи (объявлять/снимать розыск, штрафовать).
function T.CanEdit(ply, jurisdiction)
    if not (IsValid(ply) and ply:IsPlayer()) then return false end
    if ply:IsSuperAdmin() then return true end
    local W = GRM.Wanted
    if W and isfunction(W.CanEdit) and W.CanEdit(ply) then
        if isfunction(W.CanUseJurisdiction) then
            return W.CanUseJurisdiction(ply, jurisdiction)
        end
        return true
    end
    -- Фолбэк совпадает с CanManage, чтобы не сломать текущие сервера.
    return T.CanManage(ply, jurisdiction, ply.GRM_CompTerminalEnt)
end

-----------------------------------------------------------------------
-- Сбор данных для клиента
-----------------------------------------------------------------------
local function onlinePlayers(jurisdiction)
    local out = {}
    local W = GRM.Wanted
    for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
        if IsValid(p) then
            local rp = p:GetNWString("GRM_RPName", "")
            if rp == "" then rp = p:Nick() end
            local j = (W and isfunction(W.JurisdictionOfPlayer)) and W.JurisdictionOfPlayer(p) or "civil"
            out[#out + 1] = {
                key          = charKey(p),
                steamID64    = p:SteamID64() or "0",
                rpName       = rp,
                nick         = p:Nick(),
                faction      = p:GetNWString("GRM_Faction", ""),
                role         = p:GetNWString("GRM_Role", ""),
                department   = p:GetNWString("GRM_Department", ""),
                jurisdiction = j,
                -- подсказка оператору: «свой» ли это клиент терминала
                foreign      = (j ~= jurisdiction),
            }
        end
    end
    return out
end

--- Срез базы розыска по юрисдикции (Д6, Д8).
-- Возвращает МАП key -> запись: клиенты терминалов обходят его через
-- pairs() и берут ключ как идентификатор цели, поэтому форму менять
-- нельзя, иначе _targetKey станет числом.
-- @param includeCovert  показывать дела, скрытые спецслужбой (только для
--                        её собственного терминала)
local function wantedSlice(jurisdiction, limit, includeCovert)
    local out, n = {}, 0
    local W = GRM.Wanted
    if not (W and istable(W.Records)) then return out end

    -- Сортируем по времени обновления, чтобы срез был осмысленным.
    local X = GRM.Wanted and GRM.Wanted.Exchange
    local keys = {}
    for k, r in pairs(W.Records) do
        -- Дела, скрытые спецслужбой, ведомственным терминалам не видны.
        if istable(r) and (r.level or 0) > 0 and (includeCovert == true or r.covert ~= true) then
            -- Своя юрисдикция ИЛИ переданная копия сведений (Exchange).
            local visible
            if X and isfunction(X.VisibleTo) then
                visible = X.VisibleTo(r, jurisdiction)
            else
                local j = r.jurisdiction == "military" and "military" or "civil"
                visible = (jurisdiction == "all" or j == jurisdiction)
            end
            if visible then
                keys[#keys + 1] = { k = k, u = tonumber(r.updated) or 0 }
            end
        end
    end
    table.sort(keys, function(a, b) return a.u > b.u end)

    for _, e in ipairs(keys) do
        if n >= limit then break end
        local r = W.Records[e.k]
        local reasons = {}
        for _, c in ipairs(r.reasons or {}) do
            reasons[#reasons + 1] = {
                code = c.code, title = c.title, level = c.level,
                fine = c.fine, t = c.t, byNick = c.byNick,
            }
        end
        n = n + 1
        local own = r.jurisdiction == "military" and "military" or "civil"
        out[e.k] = {
            key          = e.k,
            name         = r.name,
            level        = r.level,
            -- признак «гражданский / военный» для общего листа
            jurisdiction = own,
            -- дело чужой структуры, доступное нам по переданным сведениям
            foreign      = (jurisdiction ~= "all" and own ~= jurisdiction) or nil,
            updated      = r.updated,
            reasons      = reasons,
            covert       = r.covert == true or nil,
            photoPath    = r.photoPath or r.photorobot or nil,
            photoBy      = r.photoAttachedBy or nil,
            photoAt      = r.photoAttachedAt or nil,
        }
    end
    return out
end
T.WantedSlice = wantedSlice

--- Срез реестра штрафов (Д3).
local function finesSlice(jurisdiction, limit)
    local F = GRM.Wanted and GRM.Wanted.Fines
    if not (F and isfunction(F.Page)) then return {} end
    local page = F.Page(jurisdiction, { status = "all" }, 0, limit)
    local out = {}
    for _, rec in ipairs(page) do
        out[#out + 1] = {
            id         = rec.id,
            target     = rec.target,
            targetName = rec.targetName,
            issuerName = rec.issuerName,
            amount     = rec.amount,
            paid       = rec.paid,
            reason     = rec.reason,
            status     = rec.status,
            issued     = rec.issued,
        }
    end
    return out
end
T.FinesSlice = finesSlice

--- Каталог статей своей юрисдикции — для выпадающего списка (Д12).
--- Срез реестра документов (Д6).
-- Раньше уходил ВЕСЬ GRM.Documents.Registry — все паспорта и бейджи
-- сервера. Клиент читает реестр только чтобы подставить существующие
-- данные для выбранной цели, поэтому отдаём записи лишь по онлайн-
-- игрокам, доступным в выпадающих списках.
local function registrySlice(online)
    local reg = GRM.Documents and GRM.Documents.Registry
    local out = { passports = {}, badges = {}, military = {} }
    if not istable(reg) then return out end

    for _, section in ipairs({ "passports", "badges", "military", "coverBadges", "licenses", "milLicenses" }) do
        out[section] = out[section] or {}
        local src = reg[section]
        if istable(src) then
            for _, p in ipairs(online) do
                local rec = src[p.key]
                if rec ~= nil then out[section][p.key] = rec end
            end
        end
    end
    return out
end
T.RegistrySlice = registrySlice

--- Срез шаблонов документов: клиентам нужны только настройки бланков,
-- не таблицы доступа.
local function templatesSlice()
    local tpls = GRM.Documents and GRM.Documents.Templates
    if not istable(tpls) then return {} end
    local out = {}
    for _, k in ipairs({ "passport", "military", "license", "militaryLicense", "factions" }) do
        if istable(tpls[k]) then out[k] = tpls[k] end
    end
    return out
end
T.TemplatesSlice = templatesSlice

--- Открытые заявки на передачу сведений, адресованные нашей структуре.
local function requestSlice(jurisdiction)
    local X = GRM.Wanted and GRM.Wanted.Exchange
    if not (X and isfunction(X.Pending)) then return {} end
    local okReq, list = pcall(X.Pending, jurisdiction)
    if not (okReq and istable(list)) then return {} end
    local out = {}
    for _, r in ipairs(list) do
        out[#out + 1] = {
            id         = r.id,
            fromName   = r.fromName,
            fromJur    = r.fromJur,
            targetKey  = r.targetKey,
            targetName = r.targetName,
            kind       = r.kind,
            note       = r.note,
            created    = r.created,
        }
        if #out >= 40 then break end
    end
    return out
end
T.RequestSlice = requestSlice

local function warrantSlice()
    local D = GRM.Doors
    if not (D and isfunction(D.ListWarrants)) then return {} end
    local list = D.ListWarrants(nil, true) or {}
    local out = {}
    for _, w in ipairs(list) do
        if istable(w) then
            out[#out + 1] = {
                id = w.id, number = w.number, sid = w.sid, type = w.type,
                name = w.name, reason = w.reason, status = w.status,
                byNick = w.byNick, approvedByName = w.approvedByName,
                issuerFaction = w.issuerFaction, source = w.source,
                expires = w.expires, issued = w.issued, propertyId = w.propertyId,
            }
        end
        if #out >= 80 then break end
    end
    return out
end
T.WarrantSlice = warrantSlice

local function catalogSlice(jurisdiction)
    local W = GRM.Wanted
    local out = {}
    for _, a in ipairs((W and W.Catalog) or {}) do
        local j = a.jurisdiction == "military" and "military" or "civil"
        if jurisdiction == "all" or j == jurisdiction then
            out[#out + 1] = {
                id = a.id, code = a.code, title = a.title,
                type = a.type, fine = a.fine, defaultLevel = a.defaultLevel,
            }
        end
    end
    return out
end
T.CatalogSlice = catalogSlice

-----------------------------------------------------------------------
-- Открытие терминала
-----------------------------------------------------------------------
function T.Open(ent, ply, channel)
    if not (IsValid(ent) and IsValid(ply) and ply:IsPlayer()) then return end
    local jur = ent.Jurisdiction or "civil"

    if not T.CanManage(ply, jur, ent) then
        notify(ply, ent.AccessDeniedMsg or "Доступ к терминалу запрещён.")
        return
    end

    ply.GRM_CompTerminalEnt = ent
    ply.GRM_CompTerminalJur = jur

    local online = onlinePlayers(jur)

    -- Порядок первых шести полей совпадает с прежним протоколом
    -- терминалов, поэтому клиент старой версии продолжает читать
    -- сообщение корректно. Новые поля дописаны в конец.
    net.Start(channel)
        net.WriteEntity(ent)
        net.WriteTable(online)
        net.WriteTable(templatesSlice())
        net.WriteTable(registrySlice(online))
        net.WriteTable(wantedSlice(jur, T.MaxRecordsSent))
        net.WriteString(ply:GetNWString("GRM_Faction", ""))
        net.WriteBool(ply:IsSuperAdmin())
        -- расширение протокола
        net.WriteString(jur)
        net.WriteBool(T.CanEdit(ply, jur))
        net.WriteTable(finesSlice(jur, T.MaxFinesSent))
        net.WriteTable(catalogSlice(jur))
        -- v1.2: заявки соседнего ведомства на передачу сведений
        net.WriteTable(requestSlice(jur))
        net.WriteTable(warrantSlice())
    net.Send(ply)
end

-----------------------------------------------------------------------
-- Приём команд
-----------------------------------------------------------------------
local function result(ply, ok, msg)
    if not IsValid(ply) then return end
    net.Start("GRM_CompTerminal_Result")
        net.WriteBool(ok and true or false)
        net.WriteString(tostring(msg or ""))
    net.Send(ply)
end
T.Result = result

--- Проверка «игрок реально стоит у своего терминала».
local function validTerminal(ply, jur)
    local ent = ply.GRM_CompTerminalEnt
    if not IsValid(ent) then return false, "Терминал недоступен" end
    if (ent.Jurisdiction or "civil") ~= jur then return false, "Юрисдикция терминала не совпадает" end
    if ply:GetPos():DistToSqr(ent:GetPos()) > (T.UseRange * T.UseRange) then
        return false, "Отойдя от терминала, работать с базой нельзя"
    end
    return true
end

net.Receive("GRM_CompTerminal_Act", function(_, ply)
    if not (IsValid(ply) and ply:IsPlayer()) then return end

    -- rate-limit: защита от спама пакетами
    ply.GRM_CompActNext = ply.GRM_CompActNext or 0
    if CurTime() < ply.GRM_CompActNext then return end
    ply.GRM_CompActNext = CurTime() + 0.4

    local act    = string.lower(string.sub(net.ReadString(), 1, 24))
    local jur    = net.ReadString() == "military" and "military" or "civil"
    local target = string.sub(net.ReadString(), 1, 64)
    local text   = string.sub(net.ReadString(), 1, 240)
    local num    = net.ReadUInt(32)
    local extra  = string.sub(net.ReadString(), 1, 128)

    -- Д5: полноценная проверка на приёме, а не только в ENT:Use.
    local okEnt, whyEnt = validTerminal(ply, jur)
    if not okEnt then return result(ply, false, whyEnt) end
    if not T.CanEdit(ply, jur) then
        return result(ply, false, "У вас нет прав на изменение базы")
    end

    local desk = ply.GRM_CompTerminalEnt
    local armyDesk = IsValid(desk) and desk.IsArmyDesk and desk:IsArmyDesk()
    if armyDesk and (act == "wanted_add" or act == "wanted_clear"
        or act == "fine_issue" or act == "fine_cancel") then
        return result(ply, false, "На терминале Вооружённых сил нет розыска и штрафов комендатуры")
    end

    local W = GRM.Wanted
    local F = W and W.Fines

    -- ── Розыск: объявить ──────────────────────────────────────────
    if act == "wanted_add" then
        if not (W and isfunction(W.AddCustomCharge)) then return result(ply, false, "Модуль розыска недоступен") end
        local key = charKey(target)
        if key == "" then return result(ply, false, "Не выбран нарушитель") end

        local level = math.Clamp(num, 1, (W.Config and W.Config.MaxLevel) or 5)
        local data
        if extra ~= "" then
            -- статья из каталога
            local art
            for _, a in ipairs(W.Catalog or {}) do if a.id == extra then art = a break end end
            if not art then return result(ply, false, "Статья каталога не найдена") end
            data = {
                id = art.id, code = art.code, title = art.title, type = art.type,
                fine = art.fine, jurisdiction = jur, text = text,
                level = level > 0 and level or art.defaultLevel,
            }
        else
            if string.Trim(text) == "" then return result(ply, false, "Укажите статью или основание") end
            data = {
                id = "terminal", code = jur == "military" and "ВУ-ПР" or "УК-ПР",
                title = text, type = "crime", jurisdiction = jur,
                level = level, manual = true,
            }
        end

        -- T.CanEdit уже проверен выше. Ядро розыска без trusted режет
        -- строгим W.CanEdit (AccessManager / access.json) — офицер
        -- ведомства открывает терминал по фолбэку фракции и ловит «Нет прав».
        data.trusted = true
        local ok, err = W.AddCustomCharge(ply, key, data)
        return result(ply, ok and true or false, ok and ("Ориентировка внесена: " .. data.title) or tostring(err))
    end

    -- ── Розыск: снять ─────────────────────────────────────────────
    if act == "wanted_clear" then
        if not (W and isfunction(W.Clear)) then return result(ply, false, "Модуль розыска недоступен") end
        local key = charKey(target)
        if key == "" then return result(ply, false, "Не выбрана запись") end
        local ok, err = W.Clear(ply, key, text ~= "" and text or "Снят с розыска в терминале", true)
        return result(ply, ok and true or false, ok and "Розыск снят" or tostring(err))
    end

    -- ── Штраф: выписать ───────────────────────────────────────────
    if act == "fine_issue" then
        if not (F and isfunction(F.Issue)) then return result(ply, false, "Реестр штрафов недоступен") end
        local key = charKey(target)
        if key == "" then return result(ply, false, "Не выбран нарушитель") end
        if num <= 0 then return result(ply, false, "Сумма должна быть больше нуля") end

        -- Лимит суммы берём из прав фракции в экономике.
        local E = GRM.Economy
        local maxFor = (E and isfunction(E.FineMaxFor)) and E.FineMaxFor(ply) or num
        if num > maxFor then
            return result(ply, false, ("Превышен лимит: максимум %s"):format(F.Money(maxFor)))
        end

        local rec, err = F.Issue(ply, key, num, text ~= "" and text or "Нарушение", {
            jurisdiction = jur,
            article      = extra,
        })
        if not rec then return result(ply, false, tostring(err)) end
        return result(ply, true, ("Штраф №%d на %s выписан"):format(rec.id, F.Money(rec.amount)))
    end

    -- ── Штраф: аннулировать ───────────────────────────────────────
    if act == "fine_cancel" then
        if not (F and isfunction(F.Cancel)) then return result(ply, false, "Реестр штрафов недоступен") end
        local ok, err = F.Cancel(ply, num, text ~= "" and text or "решение органа")
        return result(ply, ok and true or false, ok and ("Штраф №" .. num .. " аннулирован") or tostring(err))
    end

    -- ── Ориентировка по служебному каналу ─────────────────────────
    -- Кнопки терминала «Сообщить своим» / «Передать на волну».
    if act == "bulletin_fr" or act == "bulletin_dep" then
        local BL = W and W.Bulletins
        if not (BL and isfunction(BL.Announce)) then
            return result(ply, false, "Модуль ориентировок недоступен")
        end
        local ch = act == "bulletin_dep" and "dep" or "fr"
        local allowed, why = BL.CanUse(ply, ch)
        if not allowed then return result(ply, false, tostring(why)) end
        local ok, msg = BL.Announce(ply, ch, charKey(target), text)
        return result(ply, ok and true or false, tostring(msg))
    end

    -- ── Межведомственная передача сведений ────────────────────────
    if act == "case_transfer" or act == "case_share" or act == "case_request" then
        local X = W and W.Exchange
        if not (X and isfunction(X.Transfer)) then
            return result(ply, false, "Модуль обмена недоступен")
        end
        local key = charKey(target)
        if key == "" then return result(ply, false, "Не выбрано дело") end
        local to = (W.Records and W.Records[key] and W.Records[key].jurisdiction == "military")
            and "civil" or "military"

        local ok, msg
        if act == "case_transfer" then
            ok, msg = X.Transfer(ply, key, to, text)
        elseif act == "case_share" then
            ok, msg = X.Share(ply, key, to, text)
        else
            ok, msg = X.Request(ply, key, extra == "share" and "share" or "transfer", text)
        end
        return result(ply, ok and true or false, tostring(msg))
    end

    -- ── Решение по заявке соседнего ведомства ─────────────────────
    if act == "case_accept" or act == "case_decline" then
        local X = W and W.Exchange
        if not (X and isfunction(X.Accept)) then
            return result(ply, false, "Модуль обмена недоступен")
        end
        local ok, msg
        if act == "case_accept" then ok, msg = X.Accept(ply, num, text)
        else ok, msg = X.Decline(ply, num, text) end
        return result(ply, ok and true or false, tostring(msg))
    end

    -- ── Фоторобот: прикрепить к делу ────────────────────────────
    if act == "attach_photo" or act == "photo_attach" or act == "case_attach_photo" then
        return result(ply, false, "Фоторобот и печать ориентировок сняты со сборки")
    end

    if act == "warrant_request" then
        local D = GRM.Doors
        if not (D and isfunction(D.RequestWarrant)) then
            return result(ply, false, "Модуль ордеров недоступен")
        end
        local key = charKey(target)
        if key == "" then return result(ply, false, "Не выбран фигурант") end
        local wType = extra ~= "" and extra or "search"
        local mins = math.Clamp(num > 0 and num or 60, 5, 24 * 60)
        local src = jur == "military" and "gendarmerie" or "police"
        local ok, w = D.RequestWarrant(ply, key, wType, mins, text ~= "" and text or "Ходатайство на ордер", "", src)
        if not ok then return result(ply, false, tostring(w)) end
        local numTxt = (istable(w) and w.number) and (" №" .. tostring(w.number)) or ""
        return result(ply, true, "Ходатайство" .. numTxt .. " передано в Прокуратуру")
    end

    -- ── Обновить данные ───────────────────────────────────────────
    if act == "refresh" then
        net.Start("GRM_CompTerminal_Fines")
            net.WriteTable(wantedSlice(jur, T.MaxRecordsSent))
            net.WriteTable(finesSlice(jur, T.MaxFinesSent))
            net.WriteTable(requestSlice(jur))
            net.WriteTable(warrantSlice())
        net.Send(ply)
        return
    end

    result(ply, false, "Неизвестная команда")
end)

-----------------------------------------------------------------------
-- Совместимость: старый канал полицейского терминала.
-- Клиенты предыдущей версии продолжают работать, но теперь с полной
-- проверкой прав (раньше её не было вовсе).
-----------------------------------------------------------------------
local function legacyAct(_, ply)
    if not (IsValid(ply) and ply:IsPlayer()) then return end
    ply.GRM_CompActNext = ply.GRM_CompActNext or 0
    if CurTime() < ply.GRM_CompActNext then return end
    ply.GRM_CompActNext = CurTime() + 0.4

    local act    = net.ReadString()
    local target = net.ReadString()
    local reason = net.ReadString()
    local level  = net.ReadUInt(4)

    local jur = ply.GRM_CompTerminalJur or "civil"
    if not T.CanEdit(ply, jur) then
        return notify(ply, "У вас нет прав на изменение базы розыска.")
    end

    local W = GRM.Wanted
    if not W then return end
    local key = charKey(target)
    if key == "" then return end

    if act == "add" then
        local ok, err = W.AddCustomCharge(ply, key, {
            id = "terminal", code = jur == "military" and "ВУ-ПР" or "УК-ПР",
            title = reason ~= "" and reason or "Ориентировка",
            type = "crime", jurisdiction = jur,
            level = math.Clamp(level, 1, 5), manual = true,
            trusted = true,
        })
        notify(ply, ok and "Ориентировка внесена." or tostring(err), ok and 120 or 255, ok and 220 or 120, ok and 140 or 100)
    elseif act == "clear" then
        local ok, err = W.Clear(ply, key, reason ~= "" and reason or "Снят с розыска", true)
        notify(ply, ok and "Розыск снят." or tostring(err), ok and 120 or 255, ok and 220 or 120, ok and 140 or 100)
    end
end

-- Гражданский терминал (исторический канал).
net.Receive("GRM_CompPolice_WantedAct", legacyAct)
-- Д2: у военного терминала свой канал. Раньше его клиент писал в
-- полицейский, из-за чего сообщение обрабатывалось как гражданское,
-- а util.AddNetworkString("GRM_CompMilPolice_Act") висел без приёмника.
net.Receive("GRM_CompMilPolice_Act", legacyAct)

print("[GRM CompTerminal] v" .. T.Version .. " загружен")
