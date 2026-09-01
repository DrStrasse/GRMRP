--[[ GRM Audit Core v1.0.0: one append-only JSONL journal. ]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Audit = GRM.Audit or {}
local A = GRM.Audit
A.Version = "1.0.0"
A.MaxDetailDepth = 3
A.MaxString = 512

local function safe(value, depth, seen)
    local kind = type(value)
    if kind == "string" then
        if GRM.Utf8Sub then return GRM.Utf8Sub(value, A.MaxString) end
        return value:sub(1, A.MaxString)
    end
    if kind == "number" or kind == "boolean" then return value end
    if kind ~= "table" or depth >= A.MaxDetailDepth then return tostring(value) end
    seen = seen or {}
    if seen[value] then return "<cycle>" end
    seen[value] = true
    local out, count = {}, 0
    for key, child in pairs(value) do
        count = count + 1
        if count > 64 then out._truncated = true break end
        out[tostring(key):sub(1, 96)] = safe(child, depth + 1, seen)
    end
    seen[value] = nil
    return out
end

function A.Actor(ply)
    if not (IsValid(ply) and ply.IsPlayer and ply:IsPlayer()) then
        return { accountKey = "console", characterKey = "", name = "console" }
    end
    local actor = GRM.Identity and GRM.Identity.Actor and GRM.Identity.Actor(ply) or {
        accountKey = tostring(ply:SteamID64() or ""),
        characterKey = tostring(ply:SteamID64() or "") .. ":char1",
    }
    actor.name = ply:GetNWString("GRM_RPName", "")
    if actor.name == "" then actor.name = ply:Nick() end
    return actor
end

if SERVER then
    local function journalPath(timestamp)
        return "grm_core/audit/" .. os.date("%Y-%m-%d", timestamp) .. ".jsonl"
    end

    function A.Write(domain, action, actor, target, details)
        domain = tostring(domain or "core"):lower():gsub("[^a-z0-9_%-]", "_"):sub(1, 48)
        action = tostring(action or "unknown"):lower():gsub("[^a-z0-9_%.%-]", "_"):sub(1, 64)
        local stamp = os.time()
        local row = {
            version = 1, at = stamp, domain = domain, action = action,
            actor = A.Actor(actor), target = safe(target or {}, 0), details = safe(details or {}, 0),
        }
        local ok, encoded = pcall(util.TableToJSON, row, false)
        if not ok or not isstring(encoded) then return false, "encode_failed" end
        if not file.IsDir("grm_core", "DATA") then file.CreateDir("grm_core") end
        if not file.IsDir("grm_core/audit", "DATA") then file.CreateDir("grm_core/audit") end
        file.Append(journalPath(stamp), encoded .. "\n")
        hook.Run("GRM_AuditWritten", row)
        return true, row
    end

    hook.Add("GRM_PersistenceConflict", "GRM_Audit_PersistenceConflict", function(subject, selected, conflicts)
        local class = IsValid(subject) and subject:GetClass() or tostring(subject)
        local ids = {}
        for _, row in ipairs(conflicts or {}) do ids[#ids + 1] = row.id end
        A.Write("persistence", "backend.conflict", nil, { class = class }, { selected = selected, candidates = ids })
    end)
else
    function A.Write() return false, "server_only" end
end

print("[GRM Audit] core v" .. A.Version .. " loaded")
