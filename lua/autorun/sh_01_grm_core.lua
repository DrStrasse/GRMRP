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
