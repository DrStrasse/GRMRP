--[[ GRM Net Guard v1.0.0: common validation for client intentions. ]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Net = GRM.Net or {}
local N = GRM.Net
N.Version = "1.0.0"
N._buckets = N._buckets or setmetatable({}, { __mode = "k" })

local function deny(reason)
    return false, tostring(reason or "denied")
end

function N.Guard(ply, key, options, context)
    options = istable(options) and options or {}
    context = istable(context) and context or {}
    if not (IsValid(ply) and ply.IsPlayer and ply:IsPlayer()) then return deny("invalid_player") end
    key = tostring(key or "unnamed")

    local bits = tonumber(context.bits) or 0
    if options.maxBits and bits > tonumber(options.maxBits) then return deny("payload_too_large") end

    local now = CurTime()
    local rate = math.max(0.01, tonumber(options.rate) or 1)
    local burst = math.max(1, math.floor(tonumber(options.burst) or 1))
    N._buckets[ply] = N._buckets[ply] or {}
    local bucket = N._buckets[ply][key] or { tokens = burst, at = now }
    bucket.tokens = math.min(burst, bucket.tokens + math.max(0, now - bucket.at) / rate)
    bucket.at = now
    if bucket.tokens < 1 then N._buckets[ply][key] = bucket return deny("rate_limited") end
    bucket.tokens = bucket.tokens - 1
    N._buckets[ply][key] = bucket

    local ent = context.entity
    if options.distance and IsValid(ent) then
        local origin = ply.GetShootPos and ply:GetShootPos() or ply:GetPos()
        local target = ent.NearestPoint and ent:NearestPoint(origin) or ent:GetPos()
        if origin:DistToSqr(target) > tonumber(options.distance) ^ 2 then return deny("too_far") end
    elseif options.requireEntity and not IsValid(ent) then
        return deny("invalid_entity")
    end

    if options.capability then
        if not (GRM.Access and GRM.Access.Can) then return deny("access_unavailable") end
        local allowed, reason = GRM.Access.Can(ply, options.capability, context)
        if not allowed then return deny(reason or "access_denied") end
    end
    if isfunction(options.permission) then
        local ok, allowed, reason = pcall(options.permission, ply, context)
        if not ok or allowed ~= true then return deny(reason or "permission_denied") end
    end
    return true, "ok"
end

function N.String(value, maxChars, allowEmpty)
    if not isstring(value) then return nil, "string_required" end
    value = string.Trim(value)
    if not allowEmpty and value == "" then return nil, "empty_string" end
    maxChars = math.max(1, tonumber(maxChars) or 256)
    if GRM.Utf8Sub then value = GRM.Utf8Sub(value, maxChars) else value = value:sub(1, maxChars) end
    return value
end

function N.Number(value, minimum, maximum, integer)
    value = tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return nil, "invalid_number" end
    if minimum ~= nil then value = math.max(tonumber(minimum), value) end
    if maximum ~= nil then value = math.min(tonumber(maximum), value) end
    if integer then value = math.floor(value) end
    return value
end

if SERVER then hook.Add("PlayerDisconnected", "GRM_NetGuard_Cleanup", function(ply) N._buckets[ply] = nil end) end
-----------------------------------------------------------------------
-- ПОТОКОВАЯ ПЕРЕДАЧА БОЛЬШИХ ТАБЛИЦ (v1.1.0)
--
-- Заказ владельца: большие синхронизации слать не единым пакетом, а
-- последовательно, частями. Крупный net-пакет (снимок организаций — десятки
-- килобайт) занимает канал целиком и даёт рывок у всех получателей.
--
--   GRM.Net.Stream(name, data, targets[, opts])   — сервер: отправить частями
--   GRM.Net.Receive(name, function(data) end)     — клиент: получить целиком
--
-- opts: chunk (байт в куске, по умолчанию 8192), interval (секунд между
-- кусками, по умолчанию 0.05 — то есть примерно кусок за тик).
-----------------------------------------------------------------------
N.Version = "1.1.0"
N.Streams = N.Streams or {}          -- имя -> { буферы приёма }
N._streamSeq = N._streamSeq or 0

local STREAM_CHANNEL = "GRM_Net_Stream"

if SERVER then
    util.AddNetworkString(STREAM_CHANNEL)

    function N.Stream(name, data, targets, opts)
        name = tostring(name or "")
        if name == "" then return false end
        opts = istable(opts) and opts or {}

        local ok, encoded = pcall(util.TableToJSON, istable(data) and data or {})
        if not ok or not isstring(encoded) then return false end
        encoded = util.Compress(encoded) or encoded

        local chunkSize = math.Clamp(math.floor(tonumber(opts.chunk) or 8192), 1024, 32768)
        local interval = math.Clamp(tonumber(opts.interval) or 0.05, 0, 1)

        N._streamSeq = N._streamSeq + 1
        local id = N._streamSeq
        local total = math.max(1, math.ceil(#encoded / chunkSize))

        -- Получателей фиксируем сразу: список игроков может измениться.
        local list = {}
        if istable(targets) then
            for _, ply in ipairs(targets) do if IsValid(ply) then list[#list + 1] = ply end end
        elseif IsValid(targets) then
            list[1] = targets
        end
        if #list == 0 and targets ~= nil then return false end

        local function sendChunk(index)
            local alive = {}
            for _, ply in ipairs(list) do if IsValid(ply) then alive[#alive + 1] = ply end end
            if #list > 0 and #alive == 0 then return end

            local from = (index - 1) * chunkSize + 1
            local part = string.sub(encoded, from, from + chunkSize - 1)

            net.Start(STREAM_CHANNEL)
                net.WriteString(name)
                net.WriteUInt(id, 16)
                net.WriteUInt(index, 16)
                net.WriteUInt(total, 16)
                net.WriteUInt(#part, 16)
                net.WriteData(part, #part)
            if #list > 0 then net.Send(alive) else net.Broadcast() end

            if index < total then
                if interval <= 0 then
                    sendChunk(index + 1)
                else
                    timer.Simple(interval * index, function() sendChunk(index + 1) end)
                end
            end
        end

        sendChunk(1)
        return true, total, #encoded
    end
end

if CLIENT then
    local inbox = {}
    local handlers = {}

    function N.Receive(name, fn)
        if isstring(name) and isfunction(fn) then handlers[name] = fn end
    end

    net.Receive(STREAM_CHANNEL, function()
        local name = net.ReadString()
        local id = net.ReadUInt(16)
        local index = net.ReadUInt(16)
        local total = net.ReadUInt(16)
        local size = net.ReadUInt(16)
        local part = net.ReadData(size)

        local key = name .. ":" .. id
        local box = inbox[key]
        if not box then
            box = { parts = {}, total = total, got = 0 }
            inbox[key] = box
        end
        if not box.parts[index] then
            box.parts[index] = part
            box.got = box.got + 1
        end

        if box.got < box.total then return end
        inbox[key] = nil

        local encoded = table.concat(box.parts)
        local raw = util.Decompress(encoded) or encoded
        local ok, data = pcall(util.JSONToTable, raw, false, true)
        if not ok or not istable(data) then return end

        local fn = handlers[name]
        if fn then pcall(fn, data) end
    end)
end

print("[GRM Net] guard v" .. N.Version .. " loaded")
