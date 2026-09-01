--[[ GRM Persistence Core v1.0.0: safe JSON and backend adapters. ]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Persistence = GRM.Persistence or {}
local P = GRM.Persistence
P.Version = "1.0.0"
P.Adapters = P.Adapters or {}

function P.Register(id, adapter)
    id = string.lower(string.Trim(tostring(id or "")))
    if id == "" or not istable(adapter) then return false, "invalid_adapter" end
    if not isfunction(adapter.OwnsClass) and not isfunction(adapter.Owns) then
        return false, "adapter_requires_ownership_predicate"
    end
    adapter.ID = id
    adapter.Priority = tonumber(adapter.Priority) or 0
    P.Adapters[id] = adapter
    return true
end

function P.Unregister(id)
    P.Adapters[string.lower(tostring(id or ""))] = nil
end

function P.Get(id)
    return P.Adapters[string.lower(tostring(id or ""))]
end

function P.Resolve(subject)
    local class = isstring(subject) and subject or (IsValid(subject) and subject.GetClass and subject:GetClass() or "")
    local found = {}
    for id, adapter in pairs(P.Adapters) do
        local ok, owns
        if isfunction(adapter.Owns) then
            ok, owns = pcall(adapter.Owns, subject, class)
        else
            ok, owns = pcall(adapter.OwnsClass, class)
        end
        if ok and owns == true then found[#found + 1] = { id = id, adapter = adapter } end
    end
    table.sort(found, function(a, b)
        if a.adapter.Priority == b.adapter.Priority then return a.id < b.id end
        return a.adapter.Priority > b.adapter.Priority
    end)
    if found[1] then return found[1].adapter, found[1].id, found end
    return nil, nil, found
end

function P.Inspect(subject)
    local adapter, id, conflicts = P.Resolve(subject)
    if not adapter then return nil, "no_backend" end
    local info = { backend = id, conflicts = {} }
    for i = 2, #conflicts do info.conflicts[#info.conflicts + 1] = conflicts[i].id end
    if isfunction(adapter.Inspect) then
        local ok, data = pcall(adapter.Inspect, subject)
        if ok and istable(data) then
            for key, value in pairs(data) do info[key] = value end
        end
    end
    return info
end

function P.Call(operation, subject, ...)
    local adapter, id, conflicts = P.Resolve(subject)
    if not adapter then return false, "no_backend" end
    if #conflicts > 1 then
        hook.Run("GRM_PersistenceConflict", subject, id, conflicts)
    end
    local fn = adapter[operation]
    if not isfunction(fn) then return false, "unsupported_operation", id end
    local ok, a, b, c = pcall(fn, subject, ...)
    if not ok then return false, "backend_error:" .. tostring(a), id end
    return a, b, c, id
end

if SERVER then
    local function ensureDirFor(path)
        local parts, current = string.Explode("/", tostring(path or "")), ""
        for i = 1, math.max(0, #parts - 1) do
            current = current == "" and parts[i] or (current .. "/" .. parts[i])
            if current ~= "" and not file.IsDir(current, "DATA") then file.CreateDir(current) end
        end
    end

    local function clone(value)
        if table.Copy and istable(value) then return table.Copy(value) end
        return value
    end

    function P.Quarantine(path, raw, reason)
        ensureDirFor(path)
        local safe = tostring(path):gsub("%.json$", "")
        local quarantine = safe .. ".corrupt." .. os.time() .. ".json"
        local suffix = 0
        while file.Exists(quarantine, "DATA") do
            suffix = suffix + 1
            quarantine = safe .. ".corrupt." .. os.time() .. "." .. suffix .. ".json"
        end
        file.Write(quarantine, tostring(raw or ""))
        print("[GRM Persistence] quarantine " .. tostring(path) .. " -> " .. quarantine .. " (" .. tostring(reason or "invalid_json") .. ")")
        return quarantine
    end

    function P.LoadJSON(path, defaults, options)
        options = istable(options) and options or {}
        if not file.Exists(path, "DATA") then return clone(defaults), "missing" end
        local raw = file.Read(path, "DATA") or ""
        if string.Trim(raw) == "" then
            local quarantine = P.Quarantine(path, raw, "empty")
            return clone(defaults), "corrupt", quarantine
        end
        -- ignoreConversions=true is mandatory for SteamID64/CharacterKey maps.
        local ok, data = pcall(util.JSONToTable, raw, false, true)
        if not ok or not istable(data) then
            local quarantine = P.Quarantine(path, raw, "decode")
            return clone(defaults), "corrupt", quarantine
        end
        if options.version and tonumber(data.version) ~= tonumber(options.version) then
            if isfunction(options.migrate) then
                local migrated, result = pcall(options.migrate, data, tonumber(data.version) or 0, options.version)
                if not migrated or not istable(result) then return clone(defaults), "migration_failed" end
                data = result
            else
                return data, "version_mismatch"
            end
        end
        if isfunction(options.normalize) then data = options.normalize(data) or data end
        return data, "ok"
    end

    function P.SaveJSON(path, data, options)
        options = istable(options) and options or {}
        if not istable(data) then return false, "table_required" end
        if options.version then data.version = tonumber(options.version) end
        ensureDirFor(path)
        local ok, encoded = pcall(util.TableToJSON, data, options.pretty ~= false)
        if not ok or not isstring(encoded) then return false, "encode_failed" end
        file.Write(path, encoded) -- GMod returns nil; only read-back proves success.
        local readback = file.Read(path, "DATA")
        if readback ~= encoded then return false, "readback_failed" end
        local decodedOk, decoded = pcall(util.JSONToTable, readback, false, true)
        if not decodedOk or not istable(decoded) then return false, "verify_decode_failed" end
        return true, "saved"
    end
end

-- Domain-owned backends keep their storage formats. The registry only gives
-- /perm and future WorldObject tooling one route to discover and call them.
P.Register("vendor", {
    Priority = 100,
    OwnsClass = function(class) return class == "grm_vendor" end,
    Save = function(ent)
        if not (GRM.Vendor and GRM.Vendor.SaveVendor) then return false, "vendor_unavailable" end
        return GRM.Vendor.SaveVendor(ent)
    end,
    Remove = function(ent)
        if not (GRM.Vendor and GRM.Vendor.RemoveVendorSave) then return false, "vendor_unavailable" end
        return GRM.Vendor.RemoveVendorSave(ent)
    end,
    Inspect = function(ent)
        return { uid = tostring(IsValid(ent) and ent.GRMVendorID or ""), persistent = IsValid(ent) and ent.GRMVendorPersistent == true }
    end,
})

local CCTV_CLASSES = { grm_cctv_camera = true, grm_cctv_monitor = true, grm_cctv_server = true }
P.Register("cctv", {
    Priority = 90,
    OwnsClass = function(class) return CCTV_CLASSES[class] == true end,
    Save = function(ent)
        if not (IsValid(ent) and ent.SetPermanent and GRM.CCTV and GRM.CCTV.SavePermanent) then return false, "cctv_unavailable" end
        ent:SetPermanent(true)
        return GRM.CCTV.SavePermanent()
    end,
    Remove = function(ent)
        if not (IsValid(ent) and ent.SetPermanent and GRM.CCTV and GRM.CCTV.SavePermanent) then return false, "cctv_unavailable" end
        ent:SetPermanent(false)
        return GRM.CCTV.SavePermanent()
    end,
    Inspect = function(ent) return { persistent = IsValid(ent) and ent.GetPermanent and ent:GetPermanent() or false } end,
})

local RADIO_CLASSES = { grm_server_rack = true, grm_antenna = true, grm_radio_station = true, grm_net_console = true }
P.Register("radionet", {
    Priority = 90,
    OwnsClass = function(class) return RADIO_CLASSES[class] == true end,
    Save = function(ent)
        if not (GRM.RadioNet and GRM.RadioNet.PersistAdd) then return false, "radionet_unavailable" end
        GRM.RadioNet.PersistAdd(ent)
        return true
    end,
    Remove = function(ent)
        if not (GRM.RadioNet and GRM.RadioNet.PersistRemove) then return false, "radionet_unavailable" end
        GRM.RadioNet.PersistRemove(ent)
        return true
    end,
    Inspect = function(ent) return { persistent = IsValid(ent) } end,
})

print("[GRM Persistence] core v" .. P.Version .. " loaded")
