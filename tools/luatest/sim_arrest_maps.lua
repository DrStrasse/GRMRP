--[[ Живой прогон разметки ареста по картам (заказ владельца 21.08:
     «точки ареста не должны показываться и срабатывать на другой карте»).
     Грузится РЕАЛЬНЫЙ lua/autorun/sh_grm_arrest.lua (SERVER=true):
     создаём разметку на одной карте, «меняем карту», проверяем, что чужие
     точки не подхватываются, что перенос и очистка работают.
     Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_arrest_maps.lua ]]
local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

SERVER, CLIENT = true, false
function AddCSLuaFile() end
NULL = { _valid = false }
local NOW = 100
function CurTime() return NOW end
function SysTime() return NOW end
function RealTime() return NOW end
function IsValid(v) return type(v) == "table" and v._valid ~= false end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function isfunction(v) return type(v) == "function" end
function isentity(v) return type(v) == "table" and v._valid ~= nil end
function ErrorNoHalt() end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function math.Round(v) return math.floor((tonumber(v) or 0) + 0.5) end
function table.Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
function table.Copy(t) if type(t) ~= "table" then return t end local o = {} for k, v in pairs(t) do o[k] = table.Copy(v) end return o end
function table.HasValue(t, v) for _, x in pairs(t or {}) do if x == v then return true end end return false end
function string.Trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
bit = { bor = function(a) return a end }
FCVAR_ARCHIVE = 1
SOLID_VPHYSICS, MOVETYPE_NONE, MOVETYPE_VPHYSICS = 6, 0, 6
HUD_PRINTTALK = 3

local VMT = {}
VMT.__index = VMT
function VMT:DistToSqr(o) local a, b, c = self.x - o.x, self.y - o.y, self.z - o.z return a * a + b * b + c * c end
function VMT:Distance(o) return math.sqrt(self:DistToSqr(o)) end
VMT.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
VMT.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
VMT.__mul = function(a, b)
    if type(b) == "number" then return Vector(a.x * b, a.y * b, a.z * b) end
    return Vector(a.x * b.x, a.y * b.y, a.z * b.z)
end
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VMT) end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a } end

local HOOKS = {}
hook = {
    Add = function(e, n, fn) HOOKS[e] = HOOKS[e] or {} HOOKS[e][n] = fn end,
    Remove = function() end,
    Run = function(e, ...) for _, fn in pairs(HOOKS[e] or {}) do local r = fn(...) if r ~= nil then return r end end end,
    Call = function(e, _, ...) return hook.Run(e, ...) end,
}
timer = { Simple = function(_, fn) if fn then fn() end end, Create = function() end, Remove = function() end,
          Exists = function() return false end, Adjust = function() end }
local CMDS = {}
concommand = { Add = function(n, fn) CMDS[n] = fn end }
util = { AddNetworkString = function() end, TraceLine = function() return { Hit = false, HitPos = Vector(0,0,0) } end }
local RECV = {}
net = { Receive = function(m, fn) RECV[m] = fn end, Start = function() end, Send = function() end,
        Broadcast = function() end, WriteString = function() end, WriteTable = function() end,
        WriteBool = function() end, WriteUInt = function() end, WriteEntity = function() end,
        ReadString = function() return "" end, ReadTable = function() return {} end, ReadBool = function() return false end }
function CreateConVar(name, def)
    local cv = { value = def }
    function cv:GetInt() return math.floor(tonumber(self.value) or 0) end
    function cv:GetBool() return tostring(self.value) == "1" end
    function cv:GetFloat() return tonumber(self.value) or 0 end
    function cv:GetString() return tostring(self.value) end
    return cv
end
GetConVar = function() return nil end

-- ── карта и файлы ───────────────────────────────────────────────────
local CURRENT_MAP = "rp_city_a"
game = { GetMap = function() return CURRENT_MAP end, MaxPlayers = function() return 32 end }

local FS, DIRS = {}, { ["grm_arrest"] = true }
file = {
    Exists = function(p) return FS[p] ~= nil end,
    Read = function(p) return FS[p] end,
    Write = function(p, s) FS[p] = s end,
    IsDir = function(p) return DIRS[p] == true end,
    CreateDir = function(p) DIRS[p] = true end,
    Delete = function(p) FS[p] = nil end,
    Find = function(pattern)
        local out = {}
        local dir = string.match(tostring(pattern), "^(.-)/%*") or ""
        for path in pairs(FS) do
            local d, name = string.match(path, "^(.*)/([^/]+)$")
            if d == dir and name then out[#out + 1] = name end
        end
        table.sort(out)
        return out, {}
    end,
}

-- честный мини-JSON
local function encode(v)
    local t = type(v)
    if t == "number" then return string.format("%.14g", v) end
    if t == "boolean" then return tostring(v) end
    if t == "string" then return string.format("%q", v) end
    if t == "table" then
        local isArr = #v > 0
        local parts = {}
        if isArr then
            for _, i in ipairs(v) do parts[#parts + 1] = encode(i) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        for k, i in pairs(v) do parts[#parts + 1] = string.format("%q", tostring(k)) .. ":" .. encode(i) end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "null"
end
local function decode(str)
    local pos = 1
    local parseValue
    local function skip()
        while pos <= #str do
            local c = str:sub(pos, pos)
            if c == " " or c == "\t" or c == "\n" or c == "\r" then pos = pos + 1 else break end
        end
    end
    local function parseString()
        pos = pos + 1
        local out = {}
        while pos <= #str do
            local c = str:sub(pos, pos)
            if c == "\\" then out[#out + 1] = str:sub(pos + 1, pos + 1) pos = pos + 2
            elseif c == '"' then pos = pos + 1 return table.concat(out)
            else out[#out + 1] = c pos = pos + 1 end
        end
        return table.concat(out)
    end
    parseValue = function()
        skip()
        local c = str:sub(pos, pos)
        if c == "{" then
            local t = {} pos = pos + 1 skip()
            if str:sub(pos, pos) == "}" then pos = pos + 1 return t end
            while pos <= #str do
                skip()
                local key = parseString()
                skip() pos = pos + 1
                t[key] = parseValue()
                skip()
                local ch = str:sub(pos, pos) pos = pos + 1
                if ch == "}" then break end
            end
            return t
        elseif c == "[" then
            local t = {} pos = pos + 1 skip()
            if str:sub(pos, pos) == "]" then pos = pos + 1 return t end
            while pos <= #str do
                t[#t + 1] = parseValue()
                skip()
                local ch = str:sub(pos, pos) pos = pos + 1
                if ch == "]" then break end
            end
            return t
        elseif c == '"' then return parseString()
        elseif str:sub(pos, pos + 3) == "true" then pos = pos + 4 return true
        elseif str:sub(pos, pos + 4) == "false" then pos = pos + 5 return false
        elseif str:sub(pos, pos + 3) == "null" then pos = pos + 4 return nil
        else
            local num = str:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*", pos)
            if num then pos = pos + #num return tonumber(num) end
            pos = pos + 1
            return nil
        end
    end
    local okParse, value = pcall(parseValue)
    return okParse and value or nil
end
util.TableToJSON = function(t) return encode(t) end
util.JSONToTable = function(s) return decode(tostring(s or "")) end

local ENTS = {}
ents = {
    GetAll = function() return ENTS end,
    FindByClass = function(cls)
        local out = {}
        for _, e in ipairs(ENTS) do if e:GetClass() == cls then out[#out + 1] = e end end
        return out
    end,
    FindInSphere = function() return {} end,
    Create = function(cls)
        local e = { _valid = true, _class = cls, _pos = Vector(0, 0, 0) }
        function e:GetClass() return self._class end
        function e:SetPos(v) self._pos = v end
        function e:GetPos() return self._pos end
        function e:SetAngles() end
        function e:Spawn() end
        function e:Activate() end
        function e:SetModel() end
        function e:Remove() self._valid = false end
        function e:SetNWString() end
        function e:GetNWString(_, d) return d or "" end
        function e:SetNWBool() end
        function e:GetNWBool(_, d) return d or false end
        function e:SetCameraID(v) self._camID = v end
        function e:GetCameraID() return self._camID or "" end
        function e:SetCameraName() end
        function e:SetGroupID() end
        function e:SetArrestGroup() end
        function e:GetPhysicsObject()
            return { IsValid = function() return true end, EnableMotion = function() end,
                     Wake = function() end, SetMass = function() end }
        end
        function e:SetSolid() end
        function e:SetMoveType() end
        function e:PhysicsInit() end
        function e:DrawShadow() end
        function e:SetUseType() end
        ENTS[#ENTS + 1] = e
        return e
    end,
}
player = { GetAll = function() return PLAYERS or {} end }
Factions = {}

GRM = {
    Notify = function() end,
    Identity = { CharacterKey = function(p) return p:SteamID64() .. ":char1" end, FactionMember = function() return nil end },
    Perf = { Players = function() return PLAYERS or {} end, Entities = function(c) return ents.FindByClass(c) end,
             Throttle = function() return true end, Coalesce = function(_, fn) if fn then fn() end end },
    Audit = { Write = function() end, Log = function() end },
    UI = { Track = function() end },
    Boot = { Task = function(_, _, fn) if fn then fn() end end, OnMapStart = function(_, _, fn) if fn then fn() end end },
}

assert(loadfile("lua/autorun/sh_grm_arrest.lua"))()
local A = GRM.Arrest

local function mkPly(nick, super)
    local p = { _valid = true, _pos = Vector(0, 0, 0), nw = {} }
    function p:IsPlayer() return true end
    function p:IsSuperAdmin() return super == true end
    function p:Nick() return nick end
    function p:SteamID64() return nick end
    function p:SteamID() return nick end
    function p:GetPos() return self._pos end
    function p:SetPos(v) self._pos = v end
    function p:EyeAngles() return Angle(0, 0, 0) end
    function p:GetEyeTrace() return { HitPos = Vector(10, 0, 0) } end
    function p:GetNWString(k, d) local v = self.nw[k] if v == nil then return d end return v end
    function p:GetNWBool(k, d) local v = self.nw[k] if v == nil then return d end return v end
    function p:ChatPrint(t) self.chat = (self.chat or "") .. t .. "\n" end
    return p
end
local admin = mkPly("Admin", true)
PLAYERS = { admin }

print("\n=== 1. РАЗМЕТКА ПРИВЯЗАНА К КАРТЕ ===")
ok(isfunction(A.MapName) and A.MapName() == "rp_city_a", "модуль знает текущую карту", A.MapName and A.MapName())
ok(A.MapFile():find("rp_city_a", 1, true) ~= nil, "файл разметки именуется по карте", A.MapFile())

A.AddPrisonZone(Vector(0, 0, 0), Vector(600, 600, 300), "СИЗО А")
ok(#A.Cfg.prisonZones == 1, "зона добавлена")
ok(A.Cfg.prisonZones[1].map == "rp_city_a", "у зоны записана карта", A.Cfg.prisonZones[1].map)
A.Cfg.cameras[#A.Cfg.cameras + 1] = { id = "cam_a", name = "Камера А", map = "rp_city_a",
    pos = { x = 100, y = 0, z = 0 }, ang = { p = 0, y = 0, r = 0 }, spawnID = "spawn_a" }
A.Cfg.spawns[#A.Cfg.spawns + 1] = { id = "spawn_a", name = "Точка А", map = "rp_city_a",
    pos = { x = 120, y = 0, z = 0 }, ang = { p = 0, y = 0, r = 0 } }
A.SaveMapData()
ok(FS["grm_arrest/rp_city_a.json"] ~= nil, "разметка карты записана в свой файл")
ok(FS["grm_arrest.json"] == nil or FS["grm_arrest.json"]:find("cam_a", 1, true) == nil,
   "в общий файл точки больше не попадают")

print("\n=== 2. ИГРОК В ЗОНЕ ЭТОЙ КАРТЫ ===")
admin:SetPos(Vector(300, 300, 50))
ok(A.IsInPrisonZone(admin) == true, "внутри зоны — да")
admin:SetPos(Vector(5000, 5000, 50))
ok(A.IsInPrisonZone(admin) == false, "снаружи — нет")

print("\n=== 3. СМЕНА КАРТЫ: ЧУЖИЕ ТОЧКИ НЕ ПОДХВАТЫВАЮТСЯ ===")
CURRENT_MAP = "rp_city_b"
A.LoadConfig()
ok(#A.Cfg.prisonZones == 0, "на новой карте зон нет", #A.Cfg.prisonZones)
ok(#A.Cfg.cameras == 0 and #A.Cfg.spawns == 0, "камер и точек тоже нет")
admin:SetPos(Vector(300, 300, 50))
ok(A.IsInPrisonZone(admin) == false, "зона другой карты НЕ срабатывает")
ok(A.MapFile():find("rp_city_b", 1, true) ~= nil, "файл теперь другой карты")

A.AddPrisonZone(Vector(-800, -800, 0), Vector(-200, -200, 300), "СИЗО Б")
A.SaveMapData()
ok(#A.Cfg.prisonZones == 1 and A.Cfg.prisonZones[1].map == "rp_city_b", "своя зона на новой карте создалась")
ok(FS["grm_arrest/rp_city_b.json"] ~= nil, "и записана в свой файл")

print("\n=== 4. ВОЗВРАТ НА ПЕРВУЮ КАРТУ ===")
CURRENT_MAP = "rp_city_a"
A.LoadConfig()
ok(#A.Cfg.prisonZones == 1 and A.Cfg.prisonZones[1].name == "СИЗО А", "разметка первой карты вернулась")
ok(#A.Cfg.cameras == 1 and A.Cfg.cameras[1].id == "cam_a", "камеры на месте")

print("\n=== 5. ЗАЩИТА ОТ ЧУЖИХ ЗАПИСЕЙ В ФАЙЛЕ ===")
-- руками подмешиваем в файл карты запись другой карты
local raw = decode(FS["grm_arrest/rp_city_a.json"])
raw.prisonZones[#raw.prisonZones + 1] = { name = "Чужая", map = "rp_city_b",
    min = { x = -50, y = -50, z = 0 }, max = { x = 50, y = 50, z = 100 } }
FS["grm_arrest/rp_city_a.json"] = encode(raw)
A.LoadConfig()
ok(#A.Cfg.prisonZones == 1, "запись с чужой картой отброшена при загрузке", #A.Cfg.prisonZones)

print("\n=== 6. СПИСОК КАРТ, ПЕРЕНОС И ОЧИСТКА ===")
local maps = A.MapsWithData()
ok(#maps == 2 and table.HasValue(maps, "rp_city_a") and table.HasValue(maps, "rp_city_b"),
   "видно обе карты с разметкой", table.concat(maps, ","))
local okImport, msg = A.ImportFromMap("rp_city_b")
ok(okImport == true, "перенос разметки с другой карты работает", msg)
ok(A.Cfg.prisonZones[1].name == "СИЗО Б" and A.Cfg.prisonZones[1].map == "rp_city_a",
   "перенесённая зона стала принадлежать текущей карте")
ok(select(1, A.ImportFromMap("rp_city_a")) == false, "перенос «сам в себя» отклонён")
ok(select(1, A.ImportFromMap("нет_такой_карты")) == false, "перенос с несуществующей карты отклонён")

A.ClearMapData()
ok(#A.Cfg.prisonZones == 0 and #A.Cfg.cameras == 0, "очистка убирает разметку текущей карты")
CURRENT_MAP = "rp_city_b"
A.LoadConfig()
ok(#A.Cfg.prisonZones == 1, "разметка другой карты при этом цела", #A.Cfg.prisonZones)

print("\n=== 7. МИГРАЦИЯ СТАРОГО ОБЩЕГО ФАЙЛА ===")
FS["grm_arrest/rp_city_c.json"] = nil
FS["grm_arrest.json"] = encode({
    groups = { criminals = { name = "Уголовники", cameraIDs = {} } },
    access = { mode = "all", factions = {} },
    cameras = { { id = "old_cam", name = "Старая камера", pos = { x = 1, y = 2, z = 3 }, ang = { p = 0, y = 0, r = 0 }, spawnID = "" } },
    spawns = { { id = "old_spawn", name = "Старая точка", pos = { x = 4, y = 5, z = 6 }, ang = { p = 0, y = 0, r = 0 } } },
    prisonZones = { { name = "Старая зона", min = { x = 0, y = 0, z = 0 }, max = { x = 10, y = 10, z = 10 } } },
})
CURRENT_MAP = "rp_city_c"
A.LoadConfig()
ok(#A.Cfg.cameras == 1 and A.Cfg.cameras[1].id == "old_cam", "старые точки перенесены на текущую карту")
ok(A.Cfg.cameras[1].map == "rp_city_c", "и получили её имя", A.Cfg.cameras[1].map)
ok(FS["grm_arrest/rp_city_c.json"] ~= nil, "создан файл карты")
ok(FS["grm_arrest.json"]:find("old_cam", 1, true) == nil, "из общего файла точки убраны")
ok(FS["grm_arrest.json"]:find("Уголовники", 1, true) ~= nil, "категории в общем файле остались")

print("\n=== 8. КОМАНДЫ ОБСЛУЖИВАНИЯ ===")
ok(isfunction(CMDS["grm_arrest_points"]), "grm_arrest_points объявлена")
ok(isfunction(CMDS["grm_arrest_maps"]), "grm_arrest_maps объявлена")
ok(isfunction(CMDS["grm_arrest_map_clear"]), "grm_arrest_map_clear объявлена")
ok(isfunction(CMDS["grm_arrest_import"]), "grm_arrest_import объявлена")
admin.chat = ""
CMDS["grm_arrest_points"](admin)
ok(tostring(admin.chat):find("карта rp_city_c", 1, true) ~= nil, "отчёт печатает текущую карту", admin.chat)
local other = mkPly("Гражданский", false)
other.chat = ""
CMDS["grm_arrest_map_clear"](other)
ok(#A.Cfg.cameras == 1, "не-суперадмин ничего не чистит")

print(("\nARREST MAPS: %d/%d, провалов: %d"):format(pass, pass + fail, fail))
if fail > 0 then os.exit(1) end
