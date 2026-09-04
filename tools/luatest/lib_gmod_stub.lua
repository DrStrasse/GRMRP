--[[--------------------------------------------------------------------
    lib_gmod_stub — минимальное мок-окружение GMod для стендов.

    Даёт ровно столько API, чтобы shared-часть модулей GRM исполнилась в
    LuaJIT: hook / timer / ents / util / player / NW-заглушки и фабрика
    поддельных entity (в т.ч. дверей с AABB).

    Использование:
        local stub = dofile("tools/luatest/lib_gmod_stub.lua")
        stub.install()
        stub.loadModule("lua/autorun/sh_grm_doors.lua")   -- pcall внутри
----------------------------------------------------------------------]]
local S = {}

local function noop() end

function S.install()
    _G.SERVER, _G.CLIENT = true, false
    _G.AddCSLuaFile = noop
    _G.include = noop
    _G.CurTime = function() return S.time or 0 end
    _G.FrameNumber = function() return S.frame or 0 end
    _G.RealTime = _G.CurTime
    _G.SysTime = _G.CurTime
    _G.ErrorNoHalt = function(...) end
    _G.Msg = noop
    _G.MsgN = noop

    _G.istable = function(v) return type(v) == "table" end
    _G.isstring = function(v) return type(v) == "string" end
    _G.isnumber = function(v) return type(v) == "number" end
    _G.isfunction = function(v) return type(v) == "function" end
    _G.isbool = function(v) return type(v) == "boolean" end
    _G.isentity = function(v) return type(v) == "table" and v.__entity == true end
    _G.IsValid = function(v) return type(v) == "table" and v.__valid == true end
    _G.IsEntity = _G.isentity

    math.Clamp = function(v, lo, hi) v = tonumber(v) or 0 if v < lo then return lo end if v > hi then return hi end return v end
    math.Round = function(v, d) local m = 10 ^ (d or 0) return math.floor((tonumber(v) or 0) * m + 0.5) / m end
    string.Trim = function(s, c) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
    string.Explode = function(sep, str)
        local out = {}
        for piece in tostring(str):gmatch("([^" .. sep .. "]+)") do out[#out + 1] = piece end
        return out
    end
    table.Count = function(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
    table.Copy = function(t)
        if type(t) ~= "table" then return t end
        local out = {}
        for k, v in pairs(t) do out[k] = type(v) == "table" and table.Copy(v) or v end
        return out
    end
    table.HasValue = function(t, v) for _, x in pairs(t or {}) do if x == v then return true end end return false end

    -- Вектор
    local vecMeta = {}
    vecMeta.__index = vecMeta
    function vecMeta:DistToSqr(o) local dx, dy, dz = self.x - o.x, self.y - o.y, self.z - o.z return dx * dx + dy * dy + dz * dz end
    function vecMeta:Distance(o) return math.sqrt(self:DistToSqr(o)) end
    function vecMeta:LengthSqr() return self.x ^ 2 + self.y ^ 2 + self.z ^ 2 end
    function vecMeta:Length() return math.sqrt(self:LengthSqr()) end
    function vecMeta:Dot(o) return self.x * o.x + self.y * o.y + self.z * o.z end
    vecMeta.__add = function(a, b) return _G.Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
    vecMeta.__sub = function(a, b) return _G.Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
    vecMeta.__eq = function(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end
    _G.Vector = function(x, y, z) return setmetatable({ x = tonumber(x) or 0, y = tonumber(y) or 0, z = tonumber(z) or 0 }, vecMeta) end
    _G.Angle = function(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
    _G.Color = function(r, g, b, a) return { r = r or 0, g = g or 0, b = b or 0, a = a or 255 } end

    -- hook
    S.hooks = {}
    _G.hook = {
        Add = function(event, id, fn) S.hooks[event] = S.hooks[event] or {} S.hooks[event][id] = fn end,
        Remove = function(event, id) if S.hooks[event] then S.hooks[event][id] = nil end end,
        Run = function(event, ...)
            for _, fn in pairs(S.hooks[event] or {}) do local r = fn(...) if r ~= nil then return r end end
        end,
        Call = function(event, _, ...) return _G.hook.Run(event, ...) end,
        GetTable = function() return S.hooks end,
    }

    -- timer
    S.timers = {}
    _G.timer = {
        Simple = function(delay, fn) S.timers[#S.timers + 1] = { at = (S.time or 0) + (delay or 0), fn = fn, reps = 1 } end,
        Create = function(id, delay, reps, fn) S.timers[id] = { at = (S.time or 0) + (delay or 0), fn = fn, reps = reps } end,
        Remove = function(id) S.timers[id] = nil end,
        Exists = function(id) return S.timers[id] ~= nil end,
        Adjust = function() return true end,
    }
    function S.runTimers()
        local list = S.timers
        S.timers = {}
        for _, t in pairs(list) do if t and t.fn then t.fn() end end
    end

    -- entity-реестр
    S.entities = {}
    _G.ents = {
        GetAll = function() local o = {} for _, e in ipairs(S.entities) do if e.__valid then o[#o + 1] = e end end return o end,
        FindByClass = function(cls)
            local o = {}
            for _, e in ipairs(S.entities) do if e.__valid and e.class == cls then o[#o + 1] = e end end
            return o
        end,
        FindInSphere = function(pos, r)
            local o = {}
            for _, e in ipairs(S.entities) do
                if e.__valid and e:GetPos():DistToSqr(pos) <= r * r then o[#o + 1] = e end
            end
            return o
        end,
        Create = function(cls) return S.makeEntity({ class = cls }) end,
    }

    _G.player = { GetAll = function() local o = {} for _, e in ipairs(S.entities) do if e.__valid and e.isPlayer then o[#o + 1] = e end end return o end }
    _G.util = {
        JSONToTable = function() return nil end,
        TableToJSON = function() return "{}" end,
        AddNetworkString = noop,
        NetworkStringToID = function() return 0 end,
        TraceLine = function() return { Hit = false } end,
    }
    _G.file = {
        Exists = function() return false end,
        Read = function() return "" end,
        Write = noop,
        CreateDir = noop,
        IsDir = function() return true end,
    }
    _G.net = setmetatable({}, { __index = function() return noop end })
    _G.concommand = { Add = function(name, fn) S.commands = S.commands or {} S.commands[name] = fn end }
    _G.game = { GetMap = function() return "gm_test" end, GetWorld = function() return S.world end }
    _G.GetConVar = function() return { GetInt = function() return 1 end, GetFloat = function() return 1 end, GetBool = function() return true end, GetString = function() return "" end } end
    _G.CreateConVar = _G.GetConVar
    _G.GetConVarNumber = function() return 1 end
    -- Конвар-флаги и bit нужны модулям, создающим свои конвары.
    _G.FCVAR_ARCHIVE = 128
    _G.FCVAR_REPLICATED = 8192
    _G.FCVAR_NOTIFY = 256
    _G.bit = _G.bit or { bor = function(a, b) return (a or 0) + (b or 0) end,
        band = function(a) return a or 0 end, bnot = function(a) return -(a or 0) end }
    _G.surface = setmetatable({}, { __index = function() return noop end })
    _G.draw = setmetatable({}, { __index = function() return noop end })
    -- Вечер-17: фантомы движка = nil (как в реальном GMod) — вызов
    -- «attempt to call method 'X' (a nil value)» роняет стенд, а не молчит.
    local PHANTOM_VGUI = { SetKeyInputEnabled = true, SetReadOnly = true,
        SetBounds = true }
    _G.vgui = { Create = function()
        return setmetatable({}, { __index = function(_, k)
            if PHANTOM_VGUI[k] then return nil end
            return noop
        end })
    end }
    _G.language = { Add = noop }
    _G.list = { Set = noop, Get = function() return {} end }
    _G.duplicator = { RegisterEntityModifier = noop }
    _G.cleanup = { Add = noop }
    _G.undo = setmetatable({}, { __index = function() return noop end })

    S.time, S.frame = 0, 0
    return S
end

-- Фабрика поддельных entity
local entMeta = {}
entMeta.__index = entMeta
function entMeta:GetClass() return self.class end
function entMeta:GetPos() return self.pos end
function entMeta:SetPos(v) self.pos = v end
function entMeta:WorldSpaceCenter() return self.center or self.pos end
function entMeta:WorldSpaceAABB() return self.mins, self.maxs end
function entMeta:MapCreationID() return self.mapID or -1 end
function entMeta:CreatedByMap() return self.byMap == true end
function entMeta:EntIndex() return self.index end
function entMeta:GetParent() return self.parent end
function entMeta:SetNWBool(k, v) self.nw[k] = v end
function entMeta:GetNWBool(k, d) local v = self.nw[k] if v == nil then return d end return v end
function entMeta:SetNWString(k, v) self.nw[k] = v end
function entMeta:GetNWString(k, d) return self.nw[k] or d or "" end
function entMeta:SetNWInt(k, v) self.nw[k] = v end
function entMeta:GetNWInt(k, d) return self.nw[k] or d or 0 end
function entMeta:SetNWFloat(k, v) self.nw[k] = v end
function entMeta:GetNWFloat(k, d) return self.nw[k] or d or 0 end
function entMeta:GetInternalVariable() return false end
function entMeta:Fire() end
function entMeta:IsPlayer() return self.isPlayer == true end
function entMeta:SteamID() return self.steamid or "STEAM_0:0:1" end
function entMeta:SteamID64() return self.steamid64 or "76561190000000001" end
function entMeta:Nick() return self.nick or "Тестер" end
function entMeta:IsSuperAdmin() return self.superadmin == true end
function entMeta:IsAdmin() return self.superadmin == true end
function entMeta:PrintMessage(_, msg) self.lastMessage = msg end
function entMeta:ChatPrint(msg) self.lastMessage = msg end
function entMeta:GetModel() return self.model or "models/player/kleiner.mdl" end
function entMeta:EmitSound() end
function entMeta:Alive() return true end
function entMeta:Remove() self.__valid = false S.removed = (S.removed or 0) + 1 end

local nextIndex = 1
function S.makeEntity(t)
    t = t or {}
    local e = setmetatable(t, entMeta)
    e.__entity = true
    e.__valid = true
    e.nw = {}
    e.index = t.index or nextIndex
    nextIndex = nextIndex + 1
    e.pos = t.pos or _G.Vector(0, 0, 0)
    e.class = t.class or "prop_physics"
    S.entities[#S.entities + 1] = e
    return e
end

-- Дверь: AABB 4 x 48 x 96 вокруг позиции
function S.makeDoor(x, y, z, opts)
    opts = opts or {}
    local pos = _G.Vector(x, y, z)
    local e = S.makeEntity({
        class = opts.class or "prop_door_rotating",
        pos = pos,
        byMap = opts.byMap == true,
        mapID = opts.mapID,
    })
    e.center = pos
    e.mins = _G.Vector(x - 2, y - 24, z)
    e.maxs = _G.Vector(x + 2, y + 24, z + 96)
    return e
end

function S.reset()
    S.entities = {}
    S.removed = 0
    nextIndex = 1
end

function S.loadModule(path)
    local f = assert(io.open(path, "rb"))
    local src = f:read("*a")
    f:close()
    local chunk = assert(loadstring(src, "@" .. path))
    local ok, err = pcall(chunk)
    return ok, err
end

return S
