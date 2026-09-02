--[[
    GRM Core Contracts v1.0.0
    Stable shared rules and localization used by all new GRM modules.
]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Core = GRM.Core or {}
local C = GRM.Core

C.Version = "1.0.0"
C.SchemaVersion = 1
C.Rules = C.Rules or {}

local DEFAULT_RULES = {
    ["identity.rp_scope"] = "character",
    ["identity.admin_scope"] = "account",
    ["net.server_authoritative"] = true,
    ["net.require_rate_limit"] = true,
    ["persistence.require_version"] = true,
    ["persistence.quarantine_corrupt"] = true,
    ["persistence.require_readback"] = true,
    ["inventory.require_transaction"] = true,
    ["ui.singleton_windows"] = true,
    ["ui.default_font"] = "Roboto",
}
for id, value in pairs(DEFAULT_RULES) do
    if C.Rules[id] == nil then C.Rules[id] = value end
end

function C.DefineRule(id, value, description)
    id = tostring(id or "")
    if id == "" then return false, "empty_rule_id" end
    if C.Rules[id] ~= nil and C.Rules[id] ~= value then return false, "rule_already_defined" end
    C.Rules[id] = value
    C.RuleDescriptions = C.RuleDescriptions or {}
    if description then C.RuleDescriptions[id] = tostring(description) end
    return true
end

function C.Rule(id, fallback)
    local value = C.Rules[tostring(id or "")]
    return value == nil and fallback or value
end

--[[ Ключ персонажа — ЕДИНСТВЕННАЯ реализация на проект.

     Правило §2.1: весь RP-стат принадлежит персонажу, ключ = `SteamID64:charN`.
     Правило §5.2.6: одна каноническая функция на сущность.

     Было: локальная `charKey` скопирована в 36 файлов в 25 разных редакциях.
     Редакции разошлись по поведению, и это не косметика, а класс потери
     данных: одни возвращали для строкового ключа `""` (запись уходила в
     пустой ключ), другие — голый `SteamID64` без слота (второй персонаж
     видел чужое имущество), третьи — `nil` при невалидном игроке (падение
     в конкатенации). Один ключ на одни данные — иначе «прогресс пропал».

     Контракт (расширять только здесь):
       игрок           → GRM.Identity.CharacterKey (слот из NW/GRM.Char),
                         при отсутствии Identity — SteamID64:char1;
       "…:charN"       → возвращается как есть (уже ключ персонажа);
       "76561…"        → достраивается слотом char1 (legacy-ключ аккаунта);
       прочая строка   → как есть (имя backend-а, служебный ключ);
       nil/невалидный  → "" (никогда не nil: ключ уходит в конкатенации).

     Живёт в ядре, а не в Identity, осознанно: `sh_01_grm_core.lua` грузится
     раньше всех модулей по алфавиту, поэтому модулю достаточно ранней
     привязки `local charKey = GRM.CharKey`. Слотами по-прежнему владеет
     Identity — ядро только делегирует.
]]
local CHAR_KEY_SUFFIX = ":char[1-3]$"
local ACCOUNT_ONLY = "^%d+$"

-- Фабрика чат-диспетчеров модулей (спецслужба / бюллетени / обмен
-- розыска держали по копии тела; §5.4 п.12). Живёт в ядре, чтобы
-- любые порядки загрузки autorun были пригодны. Разбор «/cmd arg…»,
-- реестр HANDLERS, pcall-защита обработчиков и reply при падении.
GRM.Chat = GRM.Chat or {}
function GRM.Chat.DispatchFactory(tag, HANDLERS, reply)
    return function(ply, text)
        if not isstring(text) then return false end
        local args = string.Explode(" ", string.Trim(text))
        local fn = HANDLERS[string.lower(args[1] or "")]
        if not fn then return false end
        table.remove(args, 1)
        local ok, e = pcall(fn, ply, args)
        if not ok then
            ErrorNoHalt(tag .. " " .. tostring(e) .. "\n")
            reply(ply, false, "Внутренняя ошибка команды")
        end
        return true
    end
end

function GRM.CharKey(value)
    if IsValid(value) and value.IsPlayer and value:IsPlayer() then
        local identity = GRM.Identity
        if identity and isfunction(identity.CharacterKey) then
            local key = identity.CharacterKey(value)
            if isstring(key) and key ~= "" then return key end
        end
        return tostring(value:SteamID64() or value:SteamID() or "") .. ":char1"
    end

    local text = isstring(value) and value or tostring(value or "")
    if text == "" then return "" end
    if text:match(CHAR_KEY_SUFFIX) then return text end
    if text:match(ACCOUNT_ONLY) then return text .. ":char1" end
    return text
end

--[[ Разрешение ключа по «сырому» идентификатору.

     Отличается от GRM.CharKey одним: строку, похожую на SteamID/SteamID64,
     пытается сопоставить с ОНЛАЙН-игроком и взять его активный слот.
     Нужно там, куда ключ приходит из чата, консоли или чужого модуля
     (экономика, валюта): игрок в консоли пишет SteamID, а деньги лежат
     на ключе персонажа — без разрешения перевод уходил бы «в никуда»
     на ключ `SteamID64:char1`, даже если человек играет вторым персонажем.

     Была двумя одинаковыми копиями в sh_grm_currency.lua и
     sh_grm_economy.lua — то есть в двух модулях, работающих с деньгами.

     Обход игроков стоит дорого, поэтому он ПОСЛЕДНИЙ: сначала готовый
     ключ персонажа, потом онлайн-поиск, потом legacy-достройка слота.
]]
function GRM.CharKeyResolve(value)
    if IsValid(value) and value.IsPlayer and value:IsPlayer() then
        return GRM.CharKey(value)
    end

    local raw = isstring(value) and value or tostring(value or "")
    if raw == "" then return "" end
    if raw:match(CHAR_KEY_SUFFIX) then return raw end

    local players = (GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players()
        or (player and player.GetAll and player.GetAll()) or {}
    for _, ply in ipairs(players) do
        if IsValid(ply) and (ply:SteamID() == raw or ply:SteamID64() == raw) then
            return GRM.CharKey(ply)
        end
    end

    return GRM.CharKey(raw)
end

-- Localization is deliberately data-only: gameplay logic must never compare
-- translated labels. Stable IDs remain English dotted identifiers.
GRM.Lang = GRM.Lang or {}
local L = GRM.Lang
L.Version = "1.0.0"
L.Default = L.Default or "ru"
L.Fallback = L.Fallback or "ru"
L.Dictionaries = L.Dictionaries or {}
L.Aliases = L.Aliases or { ["ru-ru"] = "ru", ["en-us"] = "en", ["en-gb"] = "en" }

local function normLocale(locale)
    locale = string.lower(string.Trim(tostring(locale or "")))
    locale = L.Aliases[locale] or locale
    if locale == "" then locale = L.Default end
    return locale
end

function L.Register(locale, rows)
    locale = normLocale(locale)
    if not istable(rows) then return false, "dictionary_required" end
    L.Dictionaries[locale] = L.Dictionaries[locale] or {}
    for key, value in pairs(rows) do
        if isstring(key) and (isstring(value) or isfunction(value)) then
            L.Dictionaries[locale][key] = value
        end
    end
    return true
end

function L.Locale(actor)
    if IsValid(actor) and actor.IsPlayer and actor:IsPlayer() then
        local chosen = ""
        if SERVER and actor.GetInfo then chosen = actor:GetInfo("grm_language") or "" end
        if CLIENT and actor == LocalPlayer() and GetConVar("grm_language") then
            chosen = GetConVar("grm_language"):GetString()
        end
        chosen = normLocale(chosen)
        if L.Dictionaries[chosen] then return chosen end
    end
    return normLocale(L.Default)
end

local function interpolate(value, vars)
    if not istable(vars) then return value end
    return (value:gsub("{([%w_%.%-]+)}", function(key)
        local replacement = vars[key]
        return replacement == nil and ("{" .. key .. "}") or tostring(replacement)
    end))
end

function L.Get(key, vars, locale)
    key = tostring(key or "")
    locale = normLocale(locale)
    local dict = L.Dictionaries[locale] or {}
    local fallback = L.Dictionaries[normLocale(L.Fallback)] or {}
    local value = dict[key]
    if value == nil then value = fallback[key] end
    if value == nil then return key end
    if isfunction(value) then
        local ok, result = pcall(value, vars or {})
        value = ok and result or key
    end
    return interpolate(tostring(value), vars)
end

function L.T(actor, key, vars)
    return L.Get(key, vars, L.Locale(actor))
end

L.Register("ru", {
    ["core.access.denied"] = "Недостаточно прав.",
    ["core.access.unknown"] = "Неизвестное право: {capability}",
    ["core.net.rate_limited"] = "Слишком много запросов. Повторите позже.",
    ["core.net.too_far"] = "Объект слишком далеко.",
    ["core.persistence.corrupt"] = "Повреждённые данные помещены в карантин.",
    ["core.persistence.saved"] = "Данные сохранены.",
    ["core.language.name"] = "Русский",
})
L.Register("en", {
    ["core.access.denied"] = "Access denied.",
    ["core.access.unknown"] = "Unknown capability: {capability}",
    ["core.net.rate_limited"] = "Too many requests. Try again later.",
    ["core.net.too_far"] = "The object is too far away.",
    ["core.persistence.corrupt"] = "Corrupt data was moved to quarantine.",
    ["core.persistence.saved"] = "Data saved.",
    ["core.language.name"] = "English",
})

if CLIENT then
    CreateClientConVar("grm_language", "ru", true, true, "GRM interface language: ru/en")
end

print("[GRM Core] contracts and languages v" .. C.Version .. " loaded")
