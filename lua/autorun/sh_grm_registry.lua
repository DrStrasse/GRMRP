--[[--------------------------------------------------------------------
    GRM Registry v1.0.0 — реестр идентификаторов игроков и персонажей

    Заказ владельца (19.08): «ввести модуль id игроков… к чату id персонажа,
    id игрока привязать и к фракциям… бан по айди игрока для админа и в
    админ меню». Формат номеров — с префиксом (решение владельца).

    ДВА НОМЕРА, И ЭТО ПРИНЦИПИАЛЬНО
      • CID («ГР-1042») — номер ПЕРСОНАЖА, он же личный номер гражданина в
        госреестре. По нему пробивают человека, он печатается в документах,
        он звучит в РП. У одного игрока до трёх персонажей — три CID.
      • PID («ИГ-1042») — номер ИГРОКА (аккаунта). Им пользуется только
        администрация: бан, кик, журналы. Персонажи меняются — PID нет.
      Смешивать нельзя: полиция ловит персонажа, администрация банит игрока.

    ХРАНЕНИЕ  data/grm_identity/registry.json
      accounts[SteamID64]        = { pid = 1042, created, lastNick }
      chars[SteamID64:charN]     = { cid = 4821, pid = 1042, created,
                                     name, retired = false }
      Номера ВЫДАЮТСЯ ПОСЛЕДОВАТЕЛЬНО И НЕ ПЕРЕИСПОЛЬЗУЮТСЯ: удалённый
      персонаж уходит в retired, его номер больше никому не достанется —
      иначе «пробитие по базе» начнёт врать.

    API
      GRM.Registry.CID(ply|charKey)        → "ГР-4821"
      GRM.Registry.PID(ply|accountKey)     → "ИГ-1042"
      GRM.Registry.CIDNumber / PIDNumber   → 4821 / 1042
      GRM.Registry.ByCID(any)              → charKey, запись
      GRM.Registry.ByPID(any)              → accountKey, запись
      GRM.Registry.Resolve(query)          → charKey (CID, имя, SteamID)
      GRM.Registry.Format(prefix, number)  → "ГР-4821"
    NW на игроке: GRM_CID, GRM_PID (PID виден всем, но смысл имеет для админа).

    Команды: /id (свой номер), /id <номер|имя> (админ/допуск), grm_id,
             grm_id_find <номер|имя|SteamID>.
----------------------------------------------------------------------]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Registry = GRM.Registry or {}
local R = GRM.Registry
R.Version = "1.0.0"

-- Префиксы (решение владельца: номера с префиксом).
R.CharPrefix    = "ГР"   -- гражданский реестр: персонаж
R.AccountPrefix = "ИГ"   -- игрок (аккаунт)
R.StartNumber   = 1000   -- нумерация начинается с 1000, чтобы номера выглядели «настоящими»
R.Digits        = 4      -- минимальная ширина номера

function R.Format(prefix, number)
    number = math.floor(tonumber(number) or 0)
    if number <= 0 then return "" end
    return string.format("%s-%0" .. R.Digits .. "d", tostring(prefix or ""), number)
end

--[[ Разбор номера. ВАЖНО: класс %a и string.upper в Lua работают только с
     латиницей, а префиксы у нас кириллические («ГР», «ИГ») — поэтому режем по
     цифрам, а префикс сверяем по таблице. Заодно принимаем латинскую
     раскладку (GR/IG) и нижний регистр: админ печатает быстро, а не точно. ]]
--[[ string.lower не трогает кириллицу, поэтому поиск по имени «курт» не
     находил «Курт Вебер». Свой регистронезависимый привод: латиница через
     string.lower, кириллица — по таблице UTF-8 (А-Я→а-я, Ё→ё). ]]
function R.Lower(text)
    text = string.lower(tostring(text or ""))
    local out, i, len = {}, 1, #text
    while i <= len do
        local b1 = string.byte(text, i)
        if b1 == 0xD0 and i < len then
            local b2 = string.byte(text, i + 1)
            if b2 == 0x81 then out[#out + 1] = string.char(0xD1, 0x91) i = i + 2          -- Ё → ё
            elseif b2 >= 0x90 and b2 <= 0x9F then out[#out + 1] = string.char(0xD0, b2 + 0x20) i = i + 2 -- А-П
            elseif b2 >= 0xA0 and b2 <= 0xAF then out[#out + 1] = string.char(0xD1, b2 - 0x20) i = i + 2 -- Р-Я
            else out[#out + 1] = string.char(b1, b2) i = i + 2 end
        else
            out[#out + 1] = string.char(b1) i = i + 1
        end
    end
    return table.concat(out)
end

R.PrefixAliases = {
    ["ГР"] = "char", ["гр"] = "char", ["GR"] = "char", ["gr"] = "char", ["Гр"] = "char",
    ["ИГ"] = "account", ["иг"] = "account", ["IG"] = "account", ["ig"] = "account", ["Иг"] = "account",
}

--- Что за префикс: "char", "account" или nil (неизвестный).
function R.PrefixKind(prefix)
    prefix = string.Trim(tostring(prefix or ""))
    if prefix == "" then return nil end
    return R.PrefixAliases[prefix]
end

--- Разбор строки вида «ГР-4821», «гр 4821», «GR4821», «4821».
--- Возвращает: вид префикса ("char"/"account"/nil) и номер.
function R.Parse(value)
    local raw = string.Trim(tostring(value or ""))
    if raw == "" then return nil end
    local prefix, digits = raw:match("^(.-)[%s%-_]*(%d+)$")
    if not digits then return nil end
    prefix = string.Trim(tostring(prefix or ""):gsub("[%s%-_]+$", ""))
    if prefix == "" then return nil, tonumber(digits) end
    local kind = R.PrefixKind(prefix)
    if not kind then return false, tonumber(digits) end -- префикс есть, но чужой
    return kind, tonumber(digits)
end

R.Data = R.Data or { accounts = {}, chars = {}, nextChar = R.StartNumber, nextAccount = R.StartNumber }

local function accountKey(value)
    if IsValid(value) and value.IsPlayer and value:IsPlayer() then
        return (GRM.Identity and GRM.Identity.AccountKey and GRM.Identity.AccountKey(value)) or tostring(value:SteamID64() or "")
    end
    local raw = tostring(value or "")
    local base = raw:match("^(%d+):char[1-3]$")
    return base or raw
end

local function charKey(value)
    if IsValid(value) and value.IsPlayer and value:IsPlayer() then
        return (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(value))
            or (tostring(value:SteamID64() or "") .. ":char1")
    end
    return tostring(value or "")
end

R.AccountKeyOf, R.CharKeyOf = accountKey, charKey

-----------------------------------------------------------------------
-- ЧТЕНИЕ (обе стороны там, где данные есть локально)
-----------------------------------------------------------------------
function R.CIDNumber(value)
    if IsValid(value) and value.IsPlayer and value:IsPlayer() and CLIENT then
        local nw = value:GetNWString("GRM_CID", "")
        local _, n = R.Parse(nw)
        return n or 0
    end
    local rec = R.Data.chars[charKey(value)]
    return rec and math.floor(tonumber(rec.cid) or 0) or 0
end

function R.PIDNumber(value)
    if IsValid(value) and value.IsPlayer and value:IsPlayer() and CLIENT then
        local nw = value:GetNWString("GRM_PID", "")
        local _, n = R.Parse(nw)
        return n or 0
    end
    local rec = R.Data.accounts[accountKey(value)]
    return rec and math.floor(tonumber(rec.pid) or 0) or 0
end

function R.CID(value)
    if IsValid(value) and value.IsPlayer and value:IsPlayer() then
        local nw = value:GetNWString("GRM_CID", "")
        if nw ~= "" then return nw end
    end
    return R.Format(R.CharPrefix, R.CIDNumber(value))
end

function R.PID(value)
    if IsValid(value) and value.IsPlayer and value:IsPlayer() then
        local nw = value:GetNWString("GRM_PID", "")
        if nw ~= "" then return nw end
    end
    return R.Format(R.AccountPrefix, R.PIDNumber(value))
end

--- Персонаж по номеру: принимает «ГР-4821», «gr4821», «4821», число.
function R.ByCID(value)
    local kind, number = R.Parse(value)
    if not number then return nil end
    if kind ~= nil and kind ~= "char" then return nil end
    for key, rec in pairs(R.Data.chars) do
        if math.floor(tonumber(rec.cid) or 0) == number then return key, rec end
    end
end

--- Аккаунт по номеру: «ИГ-1042», «ig1042», «1042».
function R.ByPID(value)
    local kind, number = R.Parse(value)
    if not number then return nil end
    if kind ~= nil and kind ~= "account" then return nil end
    for key, rec in pairs(R.Data.accounts) do
        if math.floor(tonumber(rec.pid) or 0) == number then return key, rec end
    end
end

--- Универсальный поиск: номер персонажа, номер игрока, SteamID64, имя.
function R.Resolve(query)
    query = string.Trim(tostring(query or ""))
    if query == "" then return nil end

    local kind, number = R.Parse(query)
    if number then
        if kind == "account" then
            local acc = R.ByPID(query)
            if acc then
                -- Для аккаунта возвращаем активного персонажа, если он известен.
                for key, rec in pairs(R.Data.chars) do
                    if accountKey(key) == acc and not rec.retired then return key, rec, acc end
                end
                return nil, nil, acc
            end
            return nil
        end
        local key, rec = R.ByCID(query)
        if key then return key, rec, accountKey(key) end
        if kind == nil then
            local akey = R.ByPID(query)
            if akey then return nil, nil, akey end
        end
        return nil
    end

    if GRM.Identity and GRM.Identity.IsCharacterKey and GRM.Identity.IsCharacterKey(query) then
        return query, R.Data.chars[query], accountKey(query)
    end
    if query:match("^%d+$") and #query > 10 then
        return nil, nil, query
    end

    -- Поиск по имени персонажа: точное совпадение важнее частичного.
    local lower = R.Lower(query)
    local partial
    for key, rec in pairs(R.Data.chars) do
        local name = R.Lower(rec.name)
        if name ~= "" then
            if name == lower then return key, rec, accountKey(key) end
            if not partial and string.find(name, lower, 1, true) then partial = key end
        end
    end
    if partial then return partial, R.Data.chars[partial], accountKey(partial) end
end

-----------------------------------------------------------------------
-- СЕРВЕР: выдача номеров и хранение
-----------------------------------------------------------------------
if SERVER then
    local DIR = "grm_identity"
    local FILE = DIR .. "/registry.json"

    local function jsonT(raw)
        local ok, t = pcall(util.JSONToTable, raw or "", false, true)
        return ok and istable(t) and t or nil
    end

    --- Сборка снимка реестра. Вынесена отдельно: её же зовёт очередь записи
    --  GRM.Save, чтобы сериализация происходила ОДИН раз на пачку правок.
    local function snapshot()
        return { version = 1, accounts = R.Data.accounts, chars = R.Data.chars,
            nextChar = R.Data.nextChar, nextAccount = R.Data.nextAccount }
    end

    local function writeNow()
        if not file.IsDir(DIR, "DATA") then file.CreateDir(DIR) end
        local ok, raw = pcall(util.TableToJSON, snapshot(), true)
        if not ok or not isstring(raw) then print("[GRM Registry] SAVE FAIL: сериализация") return false end
        file.Write(FILE, raw)
        local back = file.Read(FILE, "DATA")
        if not back or back == "" then
            print("[GRM Registry] SAVE read-back ПУСТ — проверьте права data/")
            return false
        end
        return true
    end

    if GRM.Save and GRM.Save.Register then
        GRM.Save.Register("registry", { file = FILE, label = "Реестр номеров ГР/ИГ",
            delay = 5, priority = 2, build = function()
                if not file.IsDir(DIR, "DATA") then file.CreateDir(DIR) end
                return snapshot()
            end })
    end

    --[[ Раньше каждый вход игрока, каждое имя и каждый новый персонаж писали
         файл немедленно — на заполненном сервере это очередь синхронных
         записей в один тик. Теперь правка только помечает реестр грязным, а
         пишет его общая очередь GRM.Save (не чаще раза в 5 секунд, одна
         запись за тик). force=true — записать сейчас (выключение, команда). ]]
    function R.Save(why, force)
        if GRM.Save and GRM.Save.Mark and not force then
            return GRM.Save.Mark("registry", why) and true or writeNow()
        end
        return writeNow()
    end

    function R.Load()
        R.Data = { accounts = {}, chars = {}, nextChar = R.StartNumber, nextAccount = R.StartNumber }
        local data = jsonT(file.Read(FILE, "DATA") or "")
        if istable(data) then
            for key, rec in pairs(istable(data.accounts) and data.accounts or {}) do
                if isstring(key) and istable(rec) and tonumber(rec.pid) then
                    R.Data.accounts[key] = { pid = math.floor(tonumber(rec.pid)), created = tonumber(rec.created) or os.time(),
                        lastNick = tostring(rec.lastNick or "") }
                end
            end
            for key, rec in pairs(istable(data.chars) and data.chars or {}) do
                if isstring(key) and istable(rec) and tonumber(rec.cid) then
                    R.Data.chars[key] = { cid = math.floor(tonumber(rec.cid)), pid = math.floor(tonumber(rec.pid) or 0),
                        created = tonumber(rec.created) or os.time(), name = tostring(rec.name or ""),
                        retired = rec.retired == true }
                end
            end
            R.Data.nextChar = math.max(R.StartNumber, math.floor(tonumber(data.nextChar) or R.StartNumber))
            R.Data.nextAccount = math.max(R.StartNumber, math.floor(tonumber(data.nextAccount) or R.StartNumber))
        end

        -- Страховка от повреждённого файла: счётчики всегда выше максимума.
        for _, rec in pairs(R.Data.chars) do
            if (tonumber(rec.cid) or 0) >= R.Data.nextChar then R.Data.nextChar = math.floor(rec.cid) + 1 end
        end
        for _, rec in pairs(R.Data.accounts) do
            if (tonumber(rec.pid) or 0) >= R.Data.nextAccount then R.Data.nextAccount = math.floor(rec.pid) + 1 end
        end
        print(("[GRM Registry] загружено: игроков %d, персонажей %d")
            :format(table.Count(R.Data.accounts), table.Count(R.Data.chars)))
        return true
    end

    --- Номер аккаунта: выдаётся один раз и живёт вечно.
    function R.EnsureAccount(ply)
        local key = accountKey(ply)
        if key == "" then return 0 end
        local rec = R.Data.accounts[key]
        if not rec then
            rec = { pid = R.Data.nextAccount, created = os.time(), lastNick = "" }
            R.Data.nextAccount = R.Data.nextAccount + 1
            R.Data.accounts[key] = rec
            R.Save("новый игрок " .. key)
        end
        if IsValid(ply) and ply.Nick then
            local nick = tostring(ply:Nick() or "")
            if nick ~= "" and rec.lastNick ~= nick then rec.lastNick = nick R.Save("ник " .. key) end
        end
        return rec.pid
    end

    --- Номер персонажа: выдаётся при первом появлении персонажа в игре.
    function R.EnsureCharacter(ply, keyOverride)
        local key = keyOverride or charKey(ply)
        if key == "" or not key:find(":char") then return 0 end
        local pid = R.EnsureAccount(ply)
        local rec = R.Data.chars[key]
        if not rec then
            rec = { cid = R.Data.nextChar, pid = pid, created = os.time(), name = "", retired = false }
            R.Data.nextChar = R.Data.nextChar + 1
            R.Data.chars[key] = rec
            R.Save("новый персонаж " .. key)
        end
        if rec.pid ~= pid and pid > 0 then rec.pid = pid R.Save("привязка персонажа " .. key) end

        local name = IsValid(ply) and ply:GetNWString("GRM_RPName", "") or ""
        if name ~= "" and rec.name ~= name then rec.name = name R.Save("имя персонажа " .. key) end
        return rec.cid
    end

    --- Персонаж удалён: номер уходит в архив и больше не выдаётся.
    function R.RetireCharacter(key)
        local rec = R.Data.chars[tostring(key or "")]
        if not rec then return false end
        rec.retired = true
        R.Save("персонаж в архиве " .. tostring(key))
        return true
    end

    --- Обновление NW: номера всегда на игроке, чтобы клиент не спрашивал сеть.
    function R.Sync(ply)
        if not (IsValid(ply) and ply:IsPlayer()) then return end
        local pid = R.EnsureAccount(ply)
        local cid = R.EnsureCharacter(ply)
        local pidText, cidText = R.Format(R.AccountPrefix, pid), R.Format(R.CharPrefix, cid)
        if ply:GetNWString("GRM_PID", "") ~= pidText then ply:SetNWString("GRM_PID", pidText) end
        if ply:GetNWString("GRM_CID", "") ~= cidText then ply:SetNWString("GRM_CID", cidText) end
        return cidText, pidText
    end

    function R.SyncAll()
        for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            R.Sync(ply)
        end
    end

    R.Load()

    hook.Add("PlayerInitialSpawn", "GRM_Registry_Join", function(ply)
        timer.Simple(1, function() if IsValid(ply) then R.Sync(ply) end end)
    end)
    -- Смена персонажа = смена CID: номер должен переключаться сразу.
    hook.Add("GRM_CharacterChanged", "GRM_Registry_CharChanged", function(ply)
        timer.Simple(0, function() if IsValid(ply) then R.Sync(ply) end end)
    end)
    hook.Add("GRM_CharacterDeleted", "GRM_Registry_CharDeleted", function(_, key)
        if isstring(key) then R.RetireCharacter(key) end
    end)

    -- Имя персонажа могло появиться позже номера — подхватываем без спешки.
    timer.Create("GRM_Registry_Names", 30, 0, function()
        local changed = false
        for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(ply) then
                local key = charKey(ply)
                local rec = R.Data.chars[key]
                local name = ply:GetNWString("GRM_RPName", "")
                if rec and name ~= "" and rec.name ~= name then rec.name = name changed = true end
            end
        end
        if changed then R.Save("обновление имён") end
    end)

    -----------------------------------------------------------------
    -- КОМАНДЫ
    -----------------------------------------------------------------
    local function canLookup(ply)
        if not IsValid(ply) then return true end
        if ply:IsSuperAdmin() then return true end
        if GRM.Admin and GRM.Admin.Can then return GRM.Admin.Can(ply, "mod.kick") == true end
        return ply:IsAdmin()
    end

    local function tell(ply, msg)
        if IsValid(ply) then ply:ChatPrint("[Реестр] " .. tostring(msg)) else print("[Реестр] " .. tostring(msg)) end
    end

    function R.Describe(charKeyValue)
        local rec = R.Data.chars[tostring(charKeyValue or "")]
        if not rec then return "запись не найдена" end
        local acc = accountKey(charKeyValue)
        local accRec = R.Data.accounts[acc]
        return ("%s • %s • игрок %s%s"):format(
            R.Format(R.CharPrefix, rec.cid),
            rec.name ~= "" and rec.name or "имя неизвестно",
            R.Format(R.AccountPrefix, accRec and accRec.pid or rec.pid),
            rec.retired and " • АРХИВ" or "")
    end

    local function lookup(ply, query)
        local key, rec, acc = R.Resolve(query)
        if key then
            tell(ply, R.Describe(key))
            if canLookup(ply) and acc then tell(ply, "SteamID64: " .. tostring(acc)) end
            return
        end
        if acc then
            local accRec = R.Data.accounts[acc]
            tell(ply, ("Игрок %s • SteamID64 %s"):format(R.Format(R.AccountPrefix, accRec and accRec.pid or 0), acc))
            return
        end
        tell(ply, "Ничего не найдено по запросу: " .. tostring(query))
    end

    concommand.Add("grm_id", function(ply)
        if not IsValid(ply) then return end
        R.Sync(ply)
        tell(ply, ("Ваш персонаж: %s • Ваш игрок: %s"):format(R.CID(ply), R.PID(ply)))
    end)

    concommand.Add("grm_id_find", function(ply, _, args)
        if IsValid(ply) and not canLookup(ply) then tell(ply, "Нет прав на поиск по реестру") return end
        lookup(ply, table.concat(args or {}, " "))
    end)

    local function chat(ply, text)
        local args = string.Explode(" ", string.Trim(tostring(text or "")))
        local cmd = string.lower(args[1] or "")
        if cmd ~= "/id" and cmd ~= "!id" and cmd ~= "/номер" then return false end
        local query = table.concat(args, " ", 2)
        if query == "" then
            R.Sync(ply)
            tell(ply, ("Ваш персонаж: %s • Ваш игрок: %s"):format(R.CID(ply), R.PID(ply)))
        elseif canLookup(ply) then
            lookup(ply, query)
        else
            tell(ply, "Поиск по реестру доступен администрации")
        end
        return true
    end
    hook.Add("PlayerSay", "GRM_Registry_Chat", function(ply, text) if chat(ply, text) then return "" end end)
    hook.Add("PlayerSayTransform", "GRM_Registry_ChatEC", function(ply, pack)
        if not (istable(pack) and isstring(pack[1])) then return end
        if chat(ply, pack[1]) then pack[1] = "" pack.SkipPlayerSay = true end
    end)

    if GRM.Boot and GRM.Boot.OnMapStart then
        GRM.Boot.OnMapStart("GRM_Registry_Sync", "normal", function() R.SyncAll() end,
            { label = "Реестр: номера игроков и персонажей" })
    end

    print("[GRM Registry] server v" .. R.Version .. " loaded")
end

if CLIENT then
    print("[GRM Registry] client v" .. R.Version .. " loaded")
end
