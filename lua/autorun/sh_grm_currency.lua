--[[--------------------------------------------------------------------
    GRM Currency Core v2.0.3 (Код 42) — ПЕРЕПИСАНО С НУЛЯ

    v2.0.2 (КОРЕНЬ ВСЕЙ САГИ): голый util.JSONToTable калечил ключи SteamID64
    (конверсия ключей в числа по умолчанию — «using Player:SteamID64 as keys
    won't work», офиц. wiki) — свои же файлы читались как «0 записей». Теперь
    ВСЁ чтение идёт через jsonT() с ignoreConversions=true.

    v2.0.1 (репорт «файл 85 байт, в памяти 0, в базе есть счета»): ВСЕЯДНЫЙ
    загрузчик — поднимает map (наш), plain sid->число, array-записи с
    sid-полем, array-записи ПО НИКУ (старые чужие кошельки). Неизвестный
    формат ≤4Кб печатается целиком в консоль (отпечаток чужого писателя).
    Сверка 15с: файл в чужом формате не затирает память, а переписывается
    ЕЁ состоянием (доминирование), печать с троттлингом 60с.

    Простой надёжный контур (без SQL/сторожей/захватов — они не нужны
    и на сервере владельца SQL недоступен):

      ПАМЯТЬ (records по SteamID64)
        └─ save: JSON -> data/grm_wallet.json (+ зеркало _backup.json)
                 -> read-back: перечитали и сравнили (тихой записи нет)
        └─ load: grm_wallet.json -> grm_wallet_backup.json
                 -> grm_currency_backup.json (старый сид)
                 -> битый файл: карантин + regex-спасение записей
        └─ сверка 15с: внешние правки файла поднимаются в игру

    Стражи (маленькие, доказанные):
      * пустая память НИКОГДА не затирает непустой файл (антисвайп);
      * битый файл не равен потере данных (карантин + спасение);
      * вторая копия модуля пропускается (синглтон).

    Печать на каждом шаге: LOAD/SAVE/НОВЫЙ счёт — по консоли
    диагноз ставится за одну строку.
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}

-- ============================================================
-- КОНФИГ
-- ============================================================
GRM.StartBalance  = GRM.StartBalance  or 1000
GRM.CurrencyName  = GRM.CurrencyName  or "GRM"
GRM.MaxBalance    = GRM.MaxBalance    or 2000000000

local DATA_FILE   = "grm_wallet.json"
local BACKUP_FILE = "grm_wallet_backup.json"
local LEGACY_SEED = "grm_currency_backup.json" -- старое зеркало (эпоха grm_currency.json)
local NET_SYNC    = "GRM_Currency_Sync"
local NET_NOTIFY  = "GRM_Currency_Notify"
local AUTOSAVE    = 8   -- сек
local RECONCILE   = 15  -- сек

-- ============================================================
-- ШАРЕД: форматирование
-- ============================================================
function GRM.Format(amount)
    local n = math.floor(tonumber(amount) or 0)
    local neg = n < 0
    n = math.abs(n)
    local s = tostring(n)
    local out, cnt = "", 0
    for i = #s, 1, -1 do
        out = s:sub(i, i) .. out
        cnt = cnt + 1
        if cnt % 3 == 0 and i > 1 then out = " " .. out end
    end
    return (neg and "-" or "") .. out .. " " .. (GRM.CurrencyName or "GRM")
end

-- ============================================================
-- СЕРВЕР
-- ============================================================
if SERVER then
    -- Синглтон: вторая копия файла пропускается.
    if GRM._currencyCoreActive then
        local src = (debug and debug.getinfo and debug.getinfo(1, "S") and debug.getinfo(1, "S").short_src) or "?"
        print("[GRM Currency][!] ВТОРАЯ копия sh_grm_currency.lua ПРОПУЩЕНА, путь: " .. tostring(src))
        print("[GRM Currency][!] Активно ядро v" .. tostring(GRM._currencyCoreVer) ..
              ", путь: " .. tostring(GRM._currencyCoreSrc) .. ". Оставьте ОДНУ копию!")
        return
    end
    GRM._currencyCoreActive = true
    GRM._currencyCoreVer = "2.0.3"
    GRM._currencyCoreSrc = (debug and debug.getinfo and debug.getinfo(1, "S") and debug.getinfo(1, "S").short_src) or "?"

    util.AddNetworkString(NET_SYNC)
    util.AddNetworkString(NET_NOTIFY)
    util.AddNetworkString("grm_balance")      -- легаси для Tab/HUD
    util.AddNetworkString("grm_request_bal")
    util.AddNetworkString("grm_notify")

    -- records[sid64] = { balance = number, name = string }
    local records = {}
    local dirty = false
    -- Счета из массивной базы БЕЗ sid (старые чужие кошельки): поднимаем
    -- по нику при входе игрока
    local pendingByNick = {}
    local fmtBark = 0 -- троттлинг печати «чужой формат» в сверке
    -- Зеркало диска: что лежит в файле по нашим данным (sid -> balance)
    local diskMirror = {}
    local function mirrorFill()
        diskMirror = {}
        for sid, rec in pairs(records) do diskMirror[sid] = rec.balance end
    end
    -- Что мы последний раз реально записали в файл (write-if-changed + read-back)
    local lastSavedTxt = nil

    local function normalize(amount)
        amount = math.floor(tonumber(amount) or 0)
        if amount ~= amount then amount = 0 end -- NaN
        if amount > GRM.MaxBalance then amount = GRM.MaxBalance end
        if amount < 0 then amount = 0 end
        return amount
    end

    local function characterKeyOf(value)
        if IsValid(value) and value:IsPlayer() then
            if GRM.Identity and GRM.Identity.CharacterKey then
                return GRM.Identity.CharacterKey(value)
            end
            return tostring(value:SteamID64() or "") .. ":char1"
        end
        local raw = tostring(value or "")
        if raw:match(":char[1-3]$") then return raw end
        if player and player.GetAll then
            for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                if IsValid(p) and (p:SteamID() == raw or p:SteamID64() == raw) then
                    return characterKeyOf(p)
                end
            end
        end
        if raw:match("^%d+$") then return raw .. ":char1" end
        return raw
    end

    local function persistedCharacterKey(value)
        local raw = tostring(value or "")
        if raw:match(":char[1-3]$") then return raw end
        if raw:match("^%d+$") then return raw .. ":char1" end
        if util.SteamIDTo64 then
            local s64 = util.SteamIDTo64(raw)
            if s64 and s64 ~= "0" then return tostring(s64) .. ":char1" end
        end
        return raw
    end

    local function sidOf(ply)
        if ply == nil then return nil end
        return characterKeyOf(ply)
    end

    local function onlinePlayerOf(key)
        key = tostring(key or "")
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(p) and characterKeyOf(p) == key then return p end
        end
        return nil
    end

    local function migrateRecordKeys()
        local changed = false
        local moved = {}
        for key, rec in pairs(records) do
            local nk = persistedCharacterKey(key)
            if nk ~= key then
                if not records[nk] and not moved[nk] then moved[nk] = rec end
                records[key] = nil
                changed = true
            end
        end
        for key, rec in pairs(moved) do records[key] = rec end
        return changed
    end

    -- Управляющие байты и DEL ломали бы JSON
    local function cleanNick(s)
        s = tostring(s or "?")
        s = string.gsub(s, "[\1-\9\11-\31\127]", "")
        if s == "" then s = "?" end
        if #s > 64 then s = s:sub(1, 64) end
        return s
    end

    -- ========================================================
    -- СОХРАНЕНИЕ
    -- ========================================================
    -- Собственный ДЕТЕРМИНИРОВАННЫЙ сериализатор: всегда "balance"
    -- первым полем. При обрыве записи (краш посреди сейва) regex-
    -- спасение извлекает баланс гарантированно и ПОЛНОСТЬЮ.
    local function jsonStr(s)
        return '"' .. tostring(s or ""):gsub('[%z\1-\31\\"]', function(c)
            local m = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
            return m[c] or string.format("\\u%04x", string.byte(c))
        end) .. '"'
    end

    local function dumpWallet(clean)
        local parts = { "{" }
        local first = true
        for sid, rec in pairs(clean) do
            parts[#parts + 1] = (first and "" or ",") ..
                "\n\t" .. jsonStr(sid) .. ": {" ..
                '\n\t\t"balance": ' .. tostring(rec.balance) .. "," ..
                '\n\t\t"name": ' .. jsonStr(rec.name) ..
                "\n\t}"
            first = false
        end
        if first then return "{}" end
        parts[#parts + 1] = "\n}"
        return table.concat(parts)
    end

    local function sanitizedDump()
        local clean = {}
        for sid, rec in pairs(records) do
            clean[tostring(sid)] = {
                balance = normalize(rec and rec.balance),
                name = cleanNick(rec and rec.name),
            }
        end
        return clean
    end

    -- ВАЖНО (корень всей саги потерь!): голый util.JSONToTable(txt) КАЛЕЧИТ
    -- числовые ключи-строки — по умолчанию ignoreConversions=false, «keys
    -- are converted to numbers wherever possible» (офиц. wiki). SteamID64
    -- (17 цифр > 2^53) превращается в битое число 7.6561199385154e+16 —
    -- запись есть в таблице, но недостижима по строке-сиду навсегда.
    -- Поэтому «файл полный, память пуста». Парсим ТОЛЬКО так:
    local function jsonT(txt)
        local ok, t = pcall(util.JSONToTable, txt, false, true)
        return (ok and istable(t)) and t or nil
    end

    local function saveNow(force, why)
        if not dirty and not force then return end
        local clean = sanitizedDump()
        -- АНТИСВАЙП: пустая память НИКОГДА не затирает непустой файл.
        if next(clean) == nil then
            local prev = lastSavedTxt
            if (not isstring(prev)) and file.Exists(DATA_FILE, "DATA") then
                prev = file.Read(DATA_FILE, "DATA")
            end
            local hadRecords = false
            if isstring(prev) and #prev > 0 then
                local prevTab = jsonT(prev)
                hadRecords = prevTab ~= nil and next(prevTab) ~= nil
            end
            if hadRecords then
                print(("[GRM Currency] SAVE ОТКЛОНЁН (%s): память пуста, а в базе есть счета — базу НЕ затираем")
                    :format(tostring(why or "?")))
                dirty = false
                return
            end
        end
        -- Сериализация под pcall: ошибка не роняет таймеры,
        -- а уходит в аварийный путь (sid|balance|name построчно).
        local okJ, txt = pcall(dumpWallet, clean)
        if not okJ then txt = nil end
        -- Валидность = живой round-trip парсинг движком
        local okRound = isstring(txt) and (jsonT(txt) ~= nil)
        if not okRound then
            local lines = {}
            for sid, rec in pairs(clean) do
                lines[#lines + 1] = sid .. "|" .. tostring(rec.balance) .. "|" .. rec.name
            end
            local rescue = table.concat(lines, "\n")
            file.Write(DATA_FILE, rescue)
            file.Write(BACKUP_FILE, rescue)
            file.Write("grm_wallet_err_" .. os.time() .. ".txt",
                "TableToJSON не собрался; записан аварийный построчный формат")
            lastSavedTxt = rescue
            mirrorFill()
            dirty = false
            print(("[GRM Currency] SAVE: JSON не собрался — записан АВАРИЙНЫЙ формат (%d счетов), данные спасены")
                :format(#lines))
            return
        end
        if txt == lastSavedTxt then dirty = false return end -- без изменений
        file.Write(DATA_FILE, txt)
        file.Write(BACKUP_FILE, txt)
        lastSavedTxt = txt
        mirrorFill()
        dirty = false
        print(("[GRM Currency] SAVE ok: счетов %d, %d байт -> data/%s%s")
            :format(table.Count(records), #txt, DATA_FILE,
                why and (" [" .. tostring(why) .. "]") or ""))
        -- READ-BACK: перечитываем — «тихая» запись станет криком
        local chk = file.Read(DATA_FILE, "DATA")
        if chk ~= txt then
            print(("[GRM Currency][!] ЗАПИСЬ НЕ ПОДТВЕРДИЛАСЬ: сохранено %d байт [%s], на диске %s")
                :format(#txt, tostring(why or "?"),
                    (isstring(chk) and (tostring(#chk) .. " байт") or "файл пропал")))
        end
    end

    -- ========================================================
    -- ЗАГРУЗКА (+ спасение из битого файла regex'ом)
    -- ========================================================
    -- Вытаскивает записи {"balance": N, "name": "X"} по ключу-"sid"
    -- из любого, даже обрубленного/битого текста.
    local function rescueScan(text, dst)
        local rescued = 0
        if not isstring(text) then return 0 end
        -- полные записи (два порядка полей)
        for sid, bal, nm in text:gmatch('"([^"]+)"%s*:%s*{%s*"balance"%s*:%s*(%d+)%s*,%s*"name"%s*:%s*"([^"]*)"') do
            dst[sid] = { balance = normalize(tonumber(bal)), name = cleanNick(nm) }
            rescued = rescued + 1
        end
        for sid, nm, bal in text:gmatch('"([^"]+)"%s*:%s*{%s*"name"%s*:%s*"([^"]*)"%s*,%s*"balance"%s*:%s*(%d+)') do
            if not dst[sid] then
                dst[sid] = { balance = normalize(tonumber(bal)), name = cleanNick(nm) }
                rescued = rescued + 1
            end
        end
        -- поле-уровневое спасение: запись обрублена — берём хотя бы баланс
        for sid, bal in text:gmatch('"([^"]+)"%s*:%s*{%s*"balance"%s*:%s*(%d+)') do
            if not dst[sid] then
                dst[sid] = { balance = normalize(tonumber(bal)), name = "?" }
                rescued = rescued + 1
            end
        end
        return rescued
    end

    -- sid-подобные поля в массивных записях (форматы старых кошельков)
    local SID_FIELDS = { "sid", "sid64", "steamid", "steamid64", "steamID64", "steam", "id", "key" }

    -- ВСЕЯДНЫЙ разбор: известные форматы кошелька -> records/pendingByNick.
    --   map:    {"765...": {"balance": N, "name": "X"}}   — наш формат
    --   plain:  {"765...": N}                             — старый sid->число
    --   array:  [ {"sid64": "765...", "balance": N, ...} ]— чужой с sid-полем
    --   array:  [ {"name": "X", "balance": N} ]           — чужой по никам
    -- Возвращает число найденных записей и метку формата.
    local function parseJSONInto(rawTxt)
        local raw = jsonT(rawTxt)
        if raw == nil then return 0, "corrupt" end
        local n, fmt = 0, "map"
        for sid, rec in pairs(raw) do
            if isstring(sid) then
                if type(rec) == "table" then
                    records[sid] = { balance = normalize(rec.balance), name = tostring(rec.name or "?") }
                    n = n + 1
                elseif tonumber(rec) ~= nil then
                    records[sid] = { balance = normalize(rec), name = "?" }
                    n = n + 1
                    fmt = "plain"
                end
            end
        end
        if n == 0 then
            for _, rec in pairs(raw) do
                if type(rec) == "table" and tonumber(rec.balance) ~= nil then
                    local key = nil
                    for _, f in ipairs(SID_FIELDS) do
                        if isstring(rec[f]) and #rec[f] >= 4 then key = rec[f] break end
                    end
                    if key then
                        records[key] = { balance = normalize(rec.balance), name = tostring(rec.name or "?") }
                        n = n + 1
                        fmt = "array+sid"
                    elseif isstring(rec.name) and cleanNick(rec.name) ~= "?" then
                        pendingByNick[cleanNick(rec.name)] = normalize(rec.balance)
                        n = n + 1
                        fmt = "array+bynick"
                    end
                end
            end
        end
        if n == 0 and next(raw) ~= nil then fmt = "unknown" end
        return n, fmt
    end

    local function loadData()
        records = {}
        local SEEDS = { DATA_FILE, BACKUP_FILE, LEGACY_SEED }
        local corrupt = {}
        -- ПРОХОД 1: первый источник с РАСПОЗНАННЫМИ записями побеждает —
        -- целое зеркало всегда главнее обглоданного основного файла.
        local srcName = nil
        for _, cand in ipairs(SEEDS) do
            if file.Exists(cand, "DATA") then
                local rawTxt = file.Read(cand, "DATA") or ""
                if string.Trim(rawTxt) ~= "" then
                    print(("[GRM Currency] LOAD: источник data/%s (%d байт)"):format(cand, #rawTxt))
                    local n, fmt = parseJSONInto(rawTxt)
                    if n > 0 then
                        srcName = cand
                        print(("[GRM Currency] LOAD: поднято записей %d (формат: %s)"):format(n, fmt))
                        break
                    end
                    if fmt == "corrupt" then
                        corrupt[#corrupt + 1] = { name = cand, txt = rawTxt }
                        print(("[GRM Currency] LOAD: data/%s битый — отложен в карантин, смотрю следующий источник"):format(cand))
                    else
                        print(("[GRM Currency] LOAD: data/%s валиден, но записей не распознано (формат: %s) — смотрю следующий источник")
                            :format(cand, fmt))
                        -- ОТПЕЧАТОК ЧУЖОГО ПИСАТЕЛЯ: маленький файл печатаем целиком
                        if #rawTxt <= 4096 then
                            print("[GRM Currency]   содержимое data/" .. cand .. " целиком:")
                            for line in rawTxt:gmatch("[^\n]+") do print("  | " .. line) end
                        end
                    end
                end
            end
        end
        -- ПРОХОД 2: валидных источников нет — спасаем из битых:
        -- карантин каждого + regex-вытаскивание записей + аварийный
        -- построчный формат sid|balance|name.
        if not srcName and #corrupt > 0 then
            for _, c in ipairs(corrupt) do
                local backup = "grm_wallet_corrupt_" .. os.time() .. ".txt"
                file.Write(backup, c.txt)
                print("[GRM Currency] ОШИБКА парсинга " .. c.name ..
                      " — копия сохранена как data/" .. backup)
                local rescued = rescueScan(c.txt, records)
                if rescued > 0 then
                    print(("[GRM Currency] СПАСЕНИЕ regex'ом из битого %s: записей %d")
                        :format(c.name, rescued))
                    break
                end
                for line in c.txt:gmatch("[^\n]+") do
                    local lsid, lbal, lname = line:match("^(%S+)%|(-?%d+)%|(.*)$")
                    if lsid and lbal and not records[lsid] then
                        records[lsid] = { balance = normalize(tonumber(lbal)), name = cleanNick(lname or "?") }
                    end
                end
                if next(records) ~= nil then
                    print(("[GRM Currency] СПАСЕНИЕ построчного формата из %s"):format(c.name))
                    break
                end
            end
        end
        local migrated = migrateRecordKeys()
        if migrated then
            dirty = true
            print("[GRM Currency] миграция счетов: старые AccountKey преобразованы в CharacterKey/char1")
        end
        if srcName and srcName ~= DATA_FILE and next(records) ~= nil then
            dirty = true -- материализуем в основной файл ближайшим сейвом
            print(("[GRM Currency] МИГРАЦИЯ: счетов %d поднято из data/%s -> data/%s")
                :format(table.Count(records), srcName, DATA_FILE))
        end
        print(("[GRM Currency] LOAD итог: счетов в памяти %d"):format(table.Count(records)))
    end

    local function ensure(sid, nick)
        nick = nick and cleanNick(nick) or nil
        if not records[sid] then
            -- массивная база без sid (чужой кошелёк): поднимаем по нику
            local byNick = nick and pendingByNick[nick]
            if byNick ~= nil then
                records[sid] = { balance = byNick, name = nick or "?" }
                pendingByNick[nick] = nil
                print(("[GRM Currency] счёт %s поднят ПО НИКУ «%s» из массивной базы: %s")
                    :format(sid, nick or "?", GRM.Format(byNick)))
            else
                records[sid] = { balance = normalize(GRM.StartBalance), name = nick or "?" }
            end
            dirty = true
        end
        if nick and nick ~= "" and records[sid].name ~= nick then
            records[sid].name = nick
            dirty = true
        end
        return records[sid]
    end

    -- Отправка актуального баланса онлайн-игроку
    local function pushBalance(ply)
        if not IsValid(ply) or not ply:IsPlayer() then return end
        local rec = records[sidOf(ply)]
        local bal = rec and rec.balance or 0
        ply:SetNW2Int("GRM_Money", bal)
        net.Start(NET_SYNC)
            net.WriteUInt(bal, 32)
        net.Send(ply)
        net.Start("grm_balance")
            net.WriteInt(bal, 32)
        net.Send(ply)
    end

    net.Receive("grm_request_bal", function(_, ply)
        if IsValid(ply) then pushBalance(ply) end
    end)
    -- Маркер для Tab Menu: не переустанавливать свой обработчик grm_request_bal
    GRM._currencyReqBalRcv = true

    local function changed(ply, newBalance, delta, reason)
        hook.Run("GRM_MoneyChanged", ply, newBalance, delta, reason or "")
    end

    -- ========================================================
    -- ПУБЛИЧНОЕ API
    -- ========================================================
    function GRM.GetBalance(ply)
        local sid = sidOf(ply)
        if not sid then return 0 end
        if IsValid(ply) and ply:IsPlayer() then ensure(sid, ply:Nick()) end
        local rec = records[sid]
        return rec and rec.balance or 0
    end

    function GRM.HasMoney(ply, amount)
        amount = math.floor(tonumber(amount) or 0)
        if amount <= 0 then return true end
        return GRM.GetBalance(ply) >= amount
    end

    function GRM.SetBalance(ply, amount, reason)
        local sid = sidOf(ply)
        if not sid then return false end
        local nick = IsValid(ply) and ply:IsPlayer() and ply:Nick() or nil
        local rec = ensure(sid, nick)
        local old = rec.balance
        rec.balance = normalize(amount)
        dirty = true
        saveNow(false, "SetBalance")
        local onlinePly = (IsValid(ply) and ply:IsPlayer()) and ply or onlinePlayerOf(sid)
        if onlinePly then rec.name = onlinePly:Nick() pushBalance(onlinePly) end
        changed(IsValid(ply) and ply or sid, rec.balance, rec.balance - old, reason)
        return true
    end

    function GRM.GiveMoney(ply, amount, reason)
        amount = math.floor(tonumber(amount) or 0)
        if amount <= 0 then return false end
        local sid = sidOf(ply)
        if not sid then return false end
        local nick = IsValid(ply) and ply:IsPlayer() and ply:Nick() or nil
        local rec = ensure(sid, nick)
        rec.balance = normalize(rec.balance + amount)
        dirty = true
        local onlinePly = (IsValid(ply) and ply:IsPlayer()) and ply or onlinePlayerOf(sid)
        if onlinePly then rec.name = onlinePly:Nick() pushBalance(onlinePly) end
        changed(IsValid(ply) and ply or sid, rec.balance, amount, reason)
        return true
    end

    function GRM.TakeMoney(ply, amount, reason)
        amount = math.floor(tonumber(amount) or 0)
        if amount <= 0 then return false end
        local sid = sidOf(ply)
        if not sid then return false end
        local nick = IsValid(ply) and ply:IsPlayer() and ply:Nick() or nil
        local rec = ensure(sid, nick)
        local taken = math.min(amount, rec.balance)
        rec.balance = rec.balance - taken
        dirty = true
        local onlinePly = (IsValid(ply) and ply:IsPlayer()) and ply or onlinePlayerOf(sid)
        if onlinePly then rec.name = onlinePly:Nick() pushBalance(onlinePly) end
        changed(IsValid(ply) and ply or sid, rec.balance, -taken, reason)
        return taken >= amount
    end

    GRM.AddMoney  = GRM.GiveMoney
    GRM.CanAfford = GRM.HasMoney

    function GRM.GetAllBalances()
        local out = {}
        for sid, rec in pairs(records) do
            out[sid] = { balance = rec.balance, name = rec.name }
        end
        return out
    end

    function GRM.Notify(ply, msg, r, g, b)
        if not IsValid(ply) or not ply:IsPlayer() then return end
        local rr = math.Clamp(math.floor(tonumber(r) or 255), 0, 255)
        local gg = math.Clamp(math.floor(tonumber(g) or 255), 0, 255)
        local bb = math.Clamp(math.floor(tonumber(b) or 255), 0, 255)
        net.Start(NET_NOTIFY)
            net.WriteString(tostring(msg or ""))
            net.WriteUInt(rr, 8)
            net.WriteUInt(gg, 8)
            net.WriteUInt(bb, 8)
        net.Send(ply)
        net.Start("grm_notify")
            net.WriteString(tostring(msg or ""))
            net.WriteUInt(rr, 8)
            net.WriteUInt(gg, 8)
            net.WriteUInt(bb, 8)
        net.Send(ply)
        if ply.PrintMessage then pcall(ply.PrintMessage, ply, HUD_PRINTTALK or 2, tostring(msg or "")) end
    end

    -- ========================================================
    -- СВЕРКА «ПАМЯТЬ ↔ БАЗА»: внешние правки файла поднимаем
    -- ========================================================
    local function reconcile(reason)
        if not file.Exists(DATA_FILE, "DATA") then return 0 end
        local rawTxt = file.Read(DATA_FILE, "DATA") or ""
        local raw = jsonT(rawTxt)
        if raw == nil then return 0 end
        -- Файл в ЧУЖОМ формате (нет ни одной sid-записи): принимать нечего.
        -- Если память наша и непуста — доминируем: переписываем файл
        -- своим состоянием и оставляем отпечаток чужого писателя.
        local recognized, anyEntries = 0, 0
        for k, v in pairs(raw) do
            anyEntries = anyEntries + 1
            if isstring(k) and (type(v) == "table" or tonumber(v) ~= nil) then recognized = recognized + 1 end
        end
        if anyEntries > 0 and recognized == 0 then
            if next(records) ~= nil then
                dirty = true
                saveNow(true, "сверка: самолечение чужого формата")
                if os.time() - fmtBark >= 60 then
                    fmtBark = os.time()
                    print(("[GRM Currency] СВЕРКА: файл data/%s в ЧУЖОМ формате (%d записей не наших) — переписан состоянием памяти (%d счетов). На сервере есть другой писатель в этот файл!")
                        :format(DATA_FILE, anyEntries, table.Count(records)))
                    if #rawTxt <= 2048 then
                        print("[GRM Currency]   содержимое чужой записи: " .. rawTxt:gsub("%s+", " "))
                    end
                end
            end
            return 0
        end
        local adopted = 0
        for rawSid, rec in pairs(raw) do
            local sid = isstring(rawSid) and persistedCharacterKey(rawSid) or rawSid
            if isstring(sid) then
                -- терпим и к формату sid -> число
                local recBal, recName
                if type(rec) == "table" then recBal, recName = rec.balance, rec.name
                elseif tonumber(rec) ~= nil then recBal, recName = rec, nil end
                if recBal ~= nil then
                    local diskBal = normalize(recBal)
                    local mirrorBal = diskMirror[sid]
                    local memRec = records[sid]
                    if mirrorBal == nil and memRec == nil then
                        local mem = ensure(sid, tostring(recName or "?"))
                        mem.balance = diskBal
                        diskMirror[sid] = diskBal
                        adopted = adopted + 1
                        print(("[GRM Currency] DB↔MEM [%s] новая запись из базы: %s"):format(reason, sid))
                    elseif mirrorBal ~= nil and diskBal ~= mirrorBal then
                        -- файл менялся снаружи: поднимаем, только если эту
                        -- запись сами не трогали с последней записи диска
                        if memRec and memRec.balance ~= mirrorBal then
                            diskMirror[sid] = diskBal
                        else
                            local mem = memRec or ensure(sid, tostring(recName or "?"))
                            local old = mem.balance
                            if old ~= diskBal then
                                mem.balance = diskBal
                                if recName then mem.name = tostring(recName) end
                                dirty = true
                                adopted = adopted + 1
                                local online = onlinePlayerOf(sid)
                                if online then pushBalance(online) end
                                hook.Run("GRM_MoneyChanged", online or sid, diskBal, diskBal - old,
                                    "Сверка с базой (" .. tostring(reason) .. ")")
                                print(("[GRM Currency] DB↔MEM [%s] %s: %d → %d (поднято из базы)")
                                    :format(reason, sid, old, diskBal))
                            else
                                diskMirror[sid] = diskBal
                            end
                        end
                    end
                end
            end
        end
        return adopted
    end

    concommand.Add("grm_money_check", function(ply)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        local n = reconcile("команда")
        print(("[GRM Currency] сверка завершена: принято изменений из базы: %d"):format(n))
    end)

    hook.Add("PlayerSay", "GRM_Currency_DBCheck", function(ply, text)
        local cmd = string.lower(string.Trim(text or ""))
        if cmd ~= "/dbcheck" and cmd ~= "!dbcheck" then return end
        if not ply:IsSuperAdmin() then
            GRM.Notify(ply, "Только для superadmin.", 255, 100, 100)
            return ""
        end
        local n1 = reconcile("чат /dbcheck")
        local n2 = (hook.Run("GRM_Economy_DBCheck") == true) and 1 or 0
        GRM.Notify(ply, ("Сверка с базой: наличка +%d, экономика %s"):format(
            n1, n2 > 0 and "обновлена" or "без изменений"), 100, 220, 255)
        return ""
    end)

    -- ========================================================
    -- ДРОП/УПАКОВКА ДЕНЕГ (Код 81)
    -- /dropmoney <сумма> — пачка наличных на землю (grm_money_drop);
    -- /money_pack <сумма> — упаковать наличные в инвентарь (предмет
    -- «money», число в стаке = сумма; для багажника/передачи).
    -- Чат-контракт находки 89: PlayerSayTransform + fallback PlayerSay.
    -- ========================================================
    local function handleMoneyCmd(ply, text)
        if not IsValid(ply) then return false end
        local t = string.Trim(tostring(text or ""))
        local first, rest = t:match("^(%S+)%s*(.-)%s*$")
        if not first then return false end
        first = string.lower(first)

        if first == "/dropmoney" or first == "/moneydrop" then
            local amt = math.floor(tonumber(rest) or 0)
            if amt < 1 then
                GRM.Notify(ply, "/dropmoney <сумма> — бросить наличные на землю", 255, 180, 60)
                return true
            end
            if GRM.GetBalance(ply) < amt then
                GRM.Notify(ply, "Не хватает наличных: " .. GRM.Format(GRM.GetBalance(ply)), 255, 100, 100)
                return true
            end
            GRM.TakeMoney(ply, amt, "Выброшены деньги на землю")
            local ent = ents.Create("grm_money_drop")
            if IsValid(ent) then
                ent:SetAmount(amt)
                ent:SetPos(ply:GetPos() + ply:GetForward() * 40 + Vector(0, 0, 24))
                ent:SetAngles(Angle(0, math.random(0, 360), 0))
                ent:Spawn()
                local phys = ent:GetPhysicsObject()
                if IsValid(phys) then phys:SetVelocity(ply:GetForward() * 120 + Vector(0, 0, 60)) end
                GRM.Notify(ply, "Выброшено: " .. GRM.Format(amt), 255, 200, 80)
            else
                GRM.GiveMoney(ply, amt, "Возврат: дроп не создан")
                GRM.Notify(ply, "Ошибка создания дропа — деньги возвращены", 255, 100, 100)
            end
            return true
        end

        if first == "/money_pack" or first == "/cashout" then
            local amt = math.floor(tonumber(rest) or 0)
            if amt < 1 then
                GRM.Notify(ply, "/money_pack <сумма> — упаковать наличные в инвентарь", 255, 180, 60)
                return true
            end
            if not (GRM.Inventory and GRM.Inventory.AddItem) then
                GRM.Notify(ply, "Инвентарь недоступен.", 255, 100, 100)
                return true
            end
            if GRM.GetBalance(ply) < amt then
                GRM.Notify(ply, "Не хватает наличных: " .. GRM.Format(GRM.GetBalance(ply)), 255, 100, 100)
                return true
            end
            GRM.TakeMoney(ply, amt, "Упакованы деньги в инвентарь")
            local left = GRM.Inventory.AddItem(ply, "money", amt)
            local back = 0
            if left == false then back = amt
            elseif isnumber(left) and left > 0 then back = math.floor(left) end
            if back > 0 then GRM.GiveMoney(ply, back, "Возврат: инвентарь полон") end
            if back >= amt then
                GRM.Notify(ply, "Инвентарь полон — деньги возвращены", 255, 100, 100)
            elseif back > 0 then
                GRM.Notify(ply, "Упаковано " .. GRM.Format(amt - back) .. " (не влезло: " .. GRM.Format(back) .. ")", 255, 200, 80)
            else
                GRM.Notify(ply, "Упаковано в инвентарь: " .. GRM.Format(amt), 100, 220, 100)
            end
            return true
        end

        return false
    end

    hook.Add("PlayerSayTransform", "GRM_Currency_MoneyDropCmd", function(ply, datapack)
        if not istable(datapack) then return end
        local msg = datapack[1]
        if not isstring(msg) then return end
        if handleMoneyCmd(ply, msg) then
            datapack[1] = ""
            datapack.SkipPlayerSay = true
        end
    end)

    hook.Add("PlayerSay", "GRM_Currency_MoneyDropFallback", function(ply, text)
        if handleMoneyCmd(ply, text) then return "" end
    end)

    -- ========================================================
    -- ЖИЗНЕННЫЙ ЦИКЛ
    -- ========================================================
    loadData()
    mirrorFill()
    lastSavedTxt = file.Exists(DATA_FILE, "DATA") and (file.Read(DATA_FILE, "DATA") or "") or nil

    local function onInitSpawn(ply)
        if not IsValid(ply) or ply:IsBot() then return end
        local sid = sidOf(ply)
        if not records[sid] then
            -- ПРАВДА в момент «сброса до стартового баланса»
            local cnt = table.Count(records)
            local fsz = file.Exists(DATA_FILE, "DATA") and #(file.Read(DATA_FILE, "DATA") or "") or -1
            print(("[GRM Currency] НОВЫЙ счёт %s (%s): счетов в памяти было %d, файл data/%s = %s байт")
                :format(sid, tostring(ply:Nick()), cnt, DATA_FILE, tostring(fsz)))
            ensure(sid, ply:Nick())
            dirty = true
            saveNow(false, "вход игрока")
        else
            records[sid].name = ply:Nick()
        end
        local tag = "GRM_Currency_FirstSync_" .. sid
        timer.Create(tag, 2, 1, function()
            if IsValid(ply) then
                reconcile("вход игрока")
                pushBalance(ply)
            end
        end)
    end
    hook.Add("PlayerInitialSpawn", "GRM_Currency_Init", onInitSpawn)

    hook.Add("GRM_CharacterChanged", "GRM_Currency_CharacterSync", function(ply)
        if not IsValid(ply) then return end
        local sid = sidOf(ply)
        ensure(sid, ply:Nick())
        dirty = true
        saveNow(false, "смена персонажа")
        pushBalance(ply)
    end)

    hook.Add("PlayerDisconnected", "GRM_Currency_Disconnect", function(ply)
        if not IsValid(ply) then return end
        local rec = records[sidOf(ply)]
        if rec then rec.name = ply:Nick() end
        dirty = true
        saveNow(false, "дисконнект")
    end)

    hook.Add("ShutDown", "GRM_Currency_Shutdown", function()
        dirty = true
        saveNow(false, "shutdown")
    end)

    timer.Create("GRM_Currency_AutoSave", AUTOSAVE, 0, function() saveNow(true, "автосейв 8с") end)
    timer.Create("GRM_Currency_Flush", 5, 0, function() if dirty then saveNow(false, "флаш 5с") end end)
    timer.Create("GRM_Currency_Reconcile", RECONCILE, 0, function()
        local n = reconcile("тик 15с")
        if n > 0 then
            print(("[GRM Currency] сверка: принято %d изменений из базы"):format(n))
        end
    end)

    -- ========================================================
    -- КОНСОЛЬНЫЕ УТИЛИТЫ
    -- ========================================================
    local function canUseConsole(ply)
        return not IsValid(ply) or (IsValid(ply) and ply:IsSuperAdmin())
    end

    local function findTarget(query)
        query = tostring(query or "")
        if records[query] then return query, records[query].name end
        local low = query:lower()
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if p:Nick():lower():find(low, 1, true) then
                return p:SteamID64(), p:Nick(), p
            end
        end
        for sid, rec in pairs(records) do
            if tostring(rec.name):lower():find(low, 1, true) then
                return sid, rec.name
            end
        end
        return nil
    end

    local function moneyCmd(ply, _, args)
        if not canUseConsole(ply) then return end
        local mode, query = tostring(args[1] or ""), tostring(args[2] or "")
        local amount = math.floor(tonumber(args[3] or "") or 0)

        if mode == "save" then dirty = true saveNow(false, "команда save") print("[GRM Currency] сохранено") return end
        if mode == "list" then
            print("[GRM Currency] счетов: " .. tostring(table.Count(records)))
            local n = 0
            for sid, rec in pairs(records) do
                n = n + 1
                print(string.format("  %s | %s | %s", sid, tostring(rec.name), GRM.Format(rec.balance)))
                if n >= 25 then print("  ... (показаны первые 25)") break end
            end
            return
        end
        if mode ~= "give" and mode ~= "take" and mode ~= "set" and mode ~= "info" then
            print("[GRM Currency] grm_money <give|take|set|info|list|save> <SteamID64|ник> [сумма]")
            return
        end
        if query == "" then print("[GRM Currency] укажите цель") return end

        local sid, name, onlinePly = findTarget(query)
        if not sid then print("[GRM Currency] игрок не найден: " .. query) return end
        local target = (IsValid(onlinePly) and onlinePly) or sid

        if mode == "info" then
            print("[GRM Currency] " .. tostring(name) .. " (" .. sid .. "): " .. GRM.Format(GRM.GetBalance(target)))
        elseif mode == "give" then
            GRM.GiveMoney(target, amount)
            print("[GRM Currency] +" .. GRM.Format(amount) .. " → " .. tostring(name) .. " = " .. GRM.Format(GRM.GetBalance(target)))
        elseif mode == "take" then
            GRM.TakeMoney(target, amount)
            print("[GRM Currency] -" .. GRM.Format(amount) .. " → " .. tostring(name) .. " = " .. GRM.Format(GRM.GetBalance(target)))
        elseif mode == "set" then
            GRM.SetBalance(target, amount)
            print("[GRM Currency] " .. tostring(name) .. " = " .. GRM.Format(GRM.GetBalance(target)))
        end
        dirty = true
        saveNow(false, "grm_money")
    end
    concommand.Add("grm_money", moneyCmd)

    print(("[GRM Currency] ядро загружено v2.0.3 (переписано с нуля), путь: %s, база: data/%s, счетов в памяти: %d, файл: %s байт"):format(
        tostring(debug.getinfo(1, "S").short_src), DATA_FILE, table.Count(records),
        file.Exists(DATA_FILE, "DATA") and tostring(#(file.Read(DATA_FILE, "DATA") or "")) or "нет файла"))
end

-- ============================================================
-- КЛИЕНТ
-- ============================================================
if CLIENT then
    GRM.LocalBalance = GRM.LocalBalance or 0

    net.Receive(NET_SYNC, function()
        GRM.LocalBalance = net.ReadUInt(32)
        hook.Run("GRM_LocalMoneyChanged", GRM.LocalBalance)
    end)

    -- Зеркало для Tab (Код 47) и HUD (Код 48)
    GRM.PlayerBalance = GRM.PlayerBalance or GRM.LocalBalance
    hook.Add("GRM_LocalMoneyChanged", "GRM_Currency_MirrorPlayerBalance", function(bal)
        GRM.PlayerBalance = bal
    end)

    net.Receive(NET_NOTIFY, function()
        -- HUD (Код 48) показывает это же уведомление по grm_notify
        if GRM.HUD then
            net.ReadString() net.ReadUInt(8) net.ReadUInt(8) net.ReadUInt(8)
            return
        end
        local msg = net.ReadString()
        local r, g, b = net.ReadUInt(8), net.ReadUInt(8), net.ReadUInt(8)
        local col = Color(r, g, b)
        local ntype = (r >= 200 and g <= 160) and NOTIFY_ERROR or NOTIFY_GENERIC
        notification.AddLegacy(msg, ntype, 4)
        chat.AddText(col, msg)
    end)

    function GRM.Notify(a, b, c, d, e)
        local msg, r, g, bl
        if isentity(a) then msg, r, g, bl = b, c, d, e else msg, r, g, bl = a, b, c, d end
        msg = tostring(msg or "")
        local col = Color(tonumber(r) or 255, tonumber(g) or 255, tonumber(bl) or 255)
        notification.AddLegacy(msg, NOTIFY_GENERIC, 4)
        chat.AddText(col, msg)
    end

    concommand.Add("grm_balance", function()
        chat.AddText(Color(100, 220, 100), "[GRM] Ваш баланс: " .. GRM.Format(GRM.LocalBalance))
    end)

    print("[GRM Currency] client loaded")
end
