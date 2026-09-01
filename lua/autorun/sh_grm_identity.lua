--[[
    GRM Identity Layer v1.0.0

    Account identity and character identity are deliberately separate.
    AccountKey is used for authentication/admin/audit. CharacterKey is used
    for RP state. Modules should use this API instead of calling SteamID()
    directly for character-owned data.
]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Identity = GRM.Identity or {}
local I = GRM.Identity

I.Version = "1.0.0"
I.CharacterPrefix = "char"

local function validPlayer(ply)
    return IsValid(ply) and ply.IsPlayer and ply:IsPlayer()
end

function I.AccountKey(ply)
    if validPlayer(ply) then
        return tostring(ply:SteamID64() or ply:SteamID() or "")
    end
    if isstring(ply) then return ply end
    return ""
end

function I.AccountSteamID(ply)
    if validPlayer(ply) then return tostring(ply:SteamID() or "") end
    return ""
end

function I.ActiveSlot(ply)
    if validPlayer(ply) then
        local slot = ply:GetNWString("GRM_CharacterID", "")
        if slot:match("^char[1-3]$") then return slot end
        if GRM.Char and GRM.Char.GetActiveID then
            local ok, id = pcall(GRM.Char.GetActiveID, ply)
            if ok and isstring(id) and id:match("^char[1-3]$") then return id end
        end
    end
    return "char1"
end

function I.CharacterKey(ply)
    if validPlayer(ply) then
        local nw = ply:GetNWString("GRM_CharacterKey", "")
        if nw ~= "" then return nw end
        return I.AccountKey(ply) .. ":" .. I.ActiveSlot(ply)
    end
    if isstring(ply) and ply:find(":char%d+$") then return ply end
    return tostring(ply or "")
end

function I.CharacterID(ply)
    if validPlayer(ply) then
        return I.ActiveSlot(ply)
    end
    local key = I.CharacterKey(ply)
    return key:match(":(char[1-3])$") or "char1"
end

function I.DataKey(ply, scope)
    if scope == "account" or scope == "auth" or scope == "audit" then
        return I.AccountKey(ply)
    end
    return I.CharacterKey(ply)
end

function I.IsCharacterKey(value)
    return isstring(value) and value:match("^%d+:char[1-3]$") ~= nil
end

function I.IsSameAccount(a, b)
    local ak, bk = I.AccountKey(a), I.AccountKey(b)
    return ak ~= "" and ak == bk
end

function I.IsSameCharacter(a, b)
    local ak, bk = I.CharacterKey(a), I.CharacterKey(b)
    return ak ~= "" and ak == bk
end

function I.Actor(ply)
    return {
        accountKey = I.AccountKey(ply),
        characterKey = I.CharacterKey(ply),
        characterID = I.CharacterID(ply),
    }
end

-- Strict RP membership lookup. Once Character Core is active, SteamID
-- aliases must never grant a character the faction of another slot.
function I.FactionMember(faction, ply)
    if not istable(faction) or not istable(faction.Members) then return nil end
    if validPlayer(ply) then return faction.Members[I.CharacterKey(ply)] end
    return faction.Members[tostring(ply or "")]
end

-- Resolve only online characters. The server remains authoritative: clients
-- must never be allowed to resolve arbitrary keys through a net request.
if SERVER then
    function I.ResolveCharacter(key)
        key = tostring(key or "")
        if not I.IsCharacterKey(key) then return nil end
        for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if I.CharacterKey(ply) == key then return ply end
        end
        return nil
    end

    function I.AssertOwnCharacter(ply, key)
        return validPlayer(ply) and I.CharacterKey(ply) == tostring(key or "")
    end
end

print("[GRM Identity] v" .. I.Version .. " loaded")
