--[[ Живой прогон системы регистрационных номерных знаков (заказ 21.08):
     выдача в Полиции, реестр, физический знак, ручная установка на машину
     спереди и сзади, проверка номера, аннулирование.
     Грузится РЕАЛЬНЫЙ lua/autorun/sh_grm_plates.lua (SERVER=true).
     Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_plates.lua ]]
local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

SERVER, CLIENT = true, false
function AddCSLuaFile() end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function isfunction(v) return type(v) == "function" end
function IsValid(v) return type(v) == "table" and v._valid ~= false end
function CurTime() return 100 end
function SysTime() return 100 end
function ErrorNoHalt() end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function table.Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
function table.Copy(t) if type(t) ~= "table" then return t end local o = {} for k, v in pairs(t) do o[k] = table.Copy(v) end return o end
function string.Trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
FCVAR_ARCHIVE = 1
SOLID_VPHYSICS, SOLID_NONE, MOVETYPE_VPHYSICS, MOVETYPE_NONE = 6, 0, 6, 0
COLLISION_GROUP_NONE, COLLISION_GROUP_WORLD = 0, 1
HUD_PRINTTALK = 3

local VMT = {}
VMT.__index = VMT
function VMT:DistToSqr(o) local a, b, c = self.x - o.x, self.y - o.y, self.z - o.z return a * a + b * b + c * c end
function VMT:Distance(o) return math.sqrt(self:DistToSqr(o)) end
VMT.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
VMT.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
VMT.__mul = function(a, b)
    if type(b) == "number" then return Vector(a.x * b, a.y * b, a.z * b) end
    if type(a) == "number" then return Vector(b.x * a, b.y * a, b.z * a) end
    return Vector(a.x * b.x, a.y * b.y, a.z * b.z)
end
VMT.__unm = function(a) return Vector(-a.x, -a.y, -a.z) end
function VMT:Length() return math.sqrt(self.x * self.x + self.y * self.y + self.z * self.z) end
function VMT:Dot(o) return self.x * o.x + self.y * o.y + self.z * o.z end
function VMT:Normalize()
    local l = self:Length()
    if l > 0 then self.x, self.y, self.z = self.x / l, self.y / l, self.z / l end
    return self
end
function VMT:GetNormalized()
    local l = self:Length()
    if l <= 0 then return Vector(0, 0, 0) end
    return Vector(self.x / l, self.y / l, self.z / l)
end
function VMT:Angle() return Angle(0, 0, 0) end
function VMT:AngleEx() return Angle(0, 0, 0) end
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VMT) end
function Angle(p, y, r)
    local a = { p = p or 0, y = y or 0, r = r or 0 }
    -- В GMod у Angle есть Forward(); в моке его не было, и расчёт
    -- нормали по памяти машины падал. Считаем так же, как движок.
    function a:Forward()
        local yp, yr = math.rad(self.y or 0), math.rad(self.p or 0)
        return Vector(math.cos(yp) * math.cos(yr), math.sin(yp) * math.cos(yr), -math.sin(yr))
    end
    return a
end

local HOOKS = {}
hook = {
    Add = function(e, n, fn) HOOKS[e] = HOOKS[e] or {} HOOKS[e][n] = fn end,
    Remove = function() end,
    Run = function(e, ...) for _, fn in pairs(HOOKS[e] or {}) do local r = fn(...) if r ~= nil then return r end end end,
}
timer = { Simple = function(_, fn) if fn then fn() end end, Create = function() end, Remove = function() end,
          Exists = function() return false end }
concommand = { Add = function() end }
util = { AddNetworkString = function() end }
local NETSENT = {}
net = { Receive = function(m, fn) NETSENT[m] = fn end, Start = function() end, Send = function() end,
        Broadcast = function() end,
        WriteString = function() end, WriteTable = function() end, WriteBool = function() end,
        WriteUInt = function() end, WriteFloat = function() end, WriteInt = function() end,
        ReadString = function() return "" end, ReadTable = function() return {} end }
local CONVARS = {}
function CreateConVar(name, def)
    local cv = { value = def }
    function cv:GetInt() return math.floor(tonumber(self.value) or 0) end
    function cv:GetBool() return tostring(self.value) == "1" end
    function cv:SetValue(v) self.value = v end
    CONVARS[name] = cv
    return cv
end
game = { GetMap = function() return "sim_map" end }
player = { GetAll = function() return {} end }
local WORLD = {}
ents = {
    GetAll = function() return WORLD end,
    FindByClass = function(cls)
        local out = {}
        for _, e in ipairs(WORLD) do if e:GetClass() == cls then out[#out + 1] = e end end
        return out
    end,
    FindInSphere = function(pos, r)
        local out = {}
        for _, e in ipairs(WORLD) do if e:GetPos():Distance(pos) <= r then out[#out + 1] = e end end
        return out
    end,
    Create = function(cls)
        local e = { _valid = true, _class = cls, _pos = Vector(0, 0, 0), _ang = Angle(0, 0, 0), _nw = {}, _children = {} }
        function e:GetClass() return self._class end
        function e:SetPos(v) self._pos = v end
        function e:OBBMins() return Vector(-110, -40, 0) end
    function e:OBBMaxs() return Vector(110, 40, 60) end
    function e:GetForward() return Vector(1, 0, 0) end
    function e:GetUp() return Vector(0, 0, 1) end
    function e:LocalToWorld(v) local p = self:GetPos() return Vector(p.x + v.x, p.y + v.y, p.z + v.z) end
    function e:GetPos() return self._pos end
        function e:SetAngles(a) self._ang = a end
        function e:GetAngles() return self._ang end
        function e:Spawn() end
        function e:Activate() end
        function e:SetModel() end
        function e:SetMaterial() end
        function e:PhysicsInit() end
        function e:SetMoveType() end
        function e:SetSolid() end
        function e:SetUseType() end
        function e:SetCollisionGroup() end
        function e:GetPhysicsObject()
            return { IsValid = function() return true end, EnableMotion = function() end,
                     Wake = function() end, SetMass = function() end }
        end
        function e:SetNWString(k, v) self._nw[k] = v end
        function e:GetNWString(k, d) local v = self._nw[k] if v == nil then return d end return v end
        function e:SetNWBool(k, v) self._nw[k] = v end
        function e:GetNWBool(k, d) local v = self._nw[k] if v == nil then return d end return v end
        function e:SetParent(p)
            if IsValid(self._parent) then
                for i, c in ipairs(self._parent._children) do if c == self then table.remove(self._parent._children, i) break end end
            end
            self._parent = p
            if IsValid(p) then p._children[#p._children + 1] = self end
        end
        function e:GetParent() return self._parent end
        function e:GetChildren() return self._children end
        function e:IsVehicle() return self._class == "sim_car" end
        function e:WorldToLocal(v) return Vector(v.x - self._pos.x, v.y - self._pos.y, v.z - self._pos.z) end
        function e:LocalToWorld(v) return Vector(v.x + self._pos.x, v.y + self._pos.y, v.z + self._pos.z) end
        function e:WorldToLocalAngles(a) return Angle(a.p, a.y, a.r) end
        function e:LocalToWorldAngles(a) return Angle(a.p, a.y, a.r) end
        --[[ SetLocalPos/SetLocalAngles — как в GMod: относительно
             РОДИТЕЛЯ. В моке их не было, поэтому редактор подгонки
             знака стрелками стендом не проверялся вовсе. ]]
        function e:SetLocalPos(v)
            local par = self._parent
            if IsValid(par) and par.LocalToWorld then self._pos = par:LocalToWorld(v)
            else self._pos = v end
        end
        function e:SetLocalAngles(a)
            local par = self._parent
            if IsValid(par) and par.LocalToWorldAngles then self._ang = par:LocalToWorldAngles(a)
            else self._ang = a end
        end
        function e:EmitSound() end
        function e:Remove() self._valid = false end
        function e:SetupPlate(rec)
            self:SetNWString("GRM_Plate", tostring(rec.number or ""))
            self:SetNWString("GRM_PlateType", tostring(rec.type or "civil"))
            self:SetNWString("GRM_PlateStatus", tostring(rec.status or "active"))
            self.GRMPlateOwnerKey = tostring(rec.ownerKey or "")
        end
        WORLD[#WORLD + 1] = e
        return e
    end,
}
-- ── мок файлов: data/<path> → содержимое ──
local files = {}
file = {
  Exists = function(p) return files[p] ~= nil end,
  Read = function(p) return files[p] end,
  Write = function(p, s) files[p] = s end,
}
-- честный JSON (достаточно для наших структур)
local function encode(v, indent)
  indent = indent or 0
  local pad = string.rep("\t", indent)
  local t = type(v)
  if t == "number" then return string.format("%g", v)
  elseif t == "string" then return string.format("%q", v)
  elseif t == "boolean" then return tostring(v)
  elseif t == "table" then
    local isArr = true
    for k in pairs(v) do if type(k) ~= "number" or k < 1 or k > #v then isArr = false break end end
    local parts = {}
    if isArr and #v > 0 then
      for i = 1, #v do parts[#parts + 1] = encode(v[i], indent + 1) end
      return "[\n" .. string.rep("\t", indent + 1) .. table.concat(parts, ",\n" .. string.rep("\t", indent + 1)) .. "\n" .. pad .. "]"
    end
    for k, val in pairs(v) do parts[#parts + 1] = string.format("%q: %s", tostring(k), encode(val, indent + 1)) end
    return "{\n" .. string.rep("\t", indent + 1) .. table.concat(parts, ",\n" .. string.rep("\t", indent + 1)) .. "\n" .. pad .. "}"
  end
  return "null"
end
util.TableToJSON = function(t) return encode(t) end
-- Полноценный мини-разбор JSON: вложенные объекты и массивы, экранирование.
local function jsonDecode(str)
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
            if c == "\\" then
                local n = str:sub(pos + 1, pos + 1)
                if n == "n" then out[#out + 1] = "\n"
                elseif n == "t" then out[#out + 1] = "\t"
                elseif n == "u" then
                    out[#out + 1] = ""
                    pos = pos + 4
                else out[#out + 1] = n end
                pos = pos + 2
            elseif c == '"' then
                pos = pos + 1
                return table.concat(out)
            else
                out[#out + 1] = c
                pos = pos + 1
            end
        end
        return table.concat(out)
    end
    parseValue = function()
        skip()
        local c = str:sub(pos, pos)
        if c == "{" then
            local t = {}
            pos = pos + 1
            skip()
            if str:sub(pos, pos) == "}" then pos = pos + 1 return t end
            while pos <= #str do
                skip()
                local key = parseString()
                skip()
                pos = pos + 1 -- ':'
                t[key] = parseValue()
                skip()
                local ch = str:sub(pos, pos)
                pos = pos + 1
                if ch == "}" then break end
            end
            return t
        elseif c == "[" then
            local t = {}
            pos = pos + 1
            skip()
            if str:sub(pos, pos) == "]" then pos = pos + 1 return t end
            while pos <= #str do
                t[#t + 1] = parseValue()
                skip()
                local ch = str:sub(pos, pos)
                pos = pos + 1
                if ch == "]" then break end
            end
            return t
        elseif c == '"' then
            return parseString()
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
util.JSONToTable = function(s) return jsonDecode(tostring(s or "")) end


-- data/-файлы (mock из json-заготовки выше) уже подключены как `files`
file.IsDir = function() return true end
file.CreateDir = function() end

GRM = GRM or {}
GRM.Identity = { CharacterKey = function(p) return p:SteamID64() .. ":char1" end }
GRM.Notify = function(_, msg) LASTNOTIFY = tostring(msg) end
GRM.Perf = { Entities = function(cls) return ents.FindByClass(cls) end, Players = function() return PLAYERS or {} end }
GRM.Audit = { Write = function() end }

-- Ядро GRM (sh_00_grm_ui + sh_01_grm_core) — как на сервере, до модулей.
dofile("tools/luatest/lib_grm_core.lua")()
assert(loadfile("lua/autorun/sh_grm_plates.lua"))()
local PL = GRM.Plates

local function mkPly(nick, faction, super, sid)
    local p = { _valid = true, nw = { GRM_Faction = faction or "" } }
    function p:IsPlayer() return true end
    function p:IsSuperAdmin() return super == true end
    function p:Nick() return nick end
    function p:SteamID64() return sid or nick end
    function p:GetNWString(k, d) local v = self.nw[k] if v == nil then return d end return v end
    function p:GetPos() return Vector(0, 0, 0) end
    function p:EyeAngles() return Angle(0, 0, 0) end
    function p:GetAimVector() return Vector(1, 0, 0) end
    function p:GetEyeTrace() return { HitPos = Vector(30, 0, 0) } end
    function p:ChatPrint(t) self.chat = (self.chat or "") .. t .. "\n" end
    return p
end

local cop  = mkPly("Копп", "Ordnungspolizei")
local civ  = mkPly("Ганс", "")
local root = mkPly("Root", "", true)
PLAYERS = { cop, civ, root }
player.GetAll = function() return PLAYERS end

print("\n=== 1. НОМЕР: ЧТЕНИЕ, ПРОВЕРКА, ВИД ===")
ok(PL.NormalizeNumber(" а 123 вс ") == "А123ВС", "пробелы и регистр приводятся к канону", PL.NormalizeNumber(" а 123 вс "))
ok(PL.NormalizeNumber("A123BC") == "А123ВС", "латиница читается как кириллица — раскладка не мешает", PL.NormalizeNumber("A123BC"))
ok(PL.NormalizeNumber("A-123_BC") == "А123ВС", "дефисы и подчёркивания игнорируются")
ok(select(1, PL.ValidNumber("А123ВС", "civil")) == true, "гражданский номер A000AA проходит проверку")
ok(select(1, PL.ValidNumber("А12ВС", "civil")) == false, "короткий номер отклонён")
ok(select(1, PL.ValidNumber("Ж123ВС", "civil")) == false, "буква не из набора отклонена")
ok(select(1, PL.ValidNumber("А1В3ВС", "civil")) == false, "цифра на месте буквы отклонена")
ok(PL.FormatNumber("А123ВС", "civil") == "А 123 ВС", "номер показывается группами", PL.FormatNumber("А123ВС", "civil"))
ok(PL.FormatNumber("А1234", "police") == "А 1234", "у полицейской серии своя разбивка", PL.FormatNumber("А1234", "police"))

print("\n=== 2. ГЕНЕРАЦИЯ ===")
local seen, dup = {}, false
for i = 1, 60 do
    local n = PL.GenerateNumber("civil", function(x) return seen[x] end)
    if not n or seen[n] then dup = true end
    seen[n] = true
    if i == 1 then ok(select(1, PL.ValidNumber(n, "civil")) == true, "сгенерированный номер соответствует шаблону", n) end
end
ok(not dup, "генератор не выдаёт занятые номера")
ok(PL.GenerateNumber("police", function() return true end) == nil, "если всё занято — честный nil, а не битый номер")

print("\n=== 3. ДОСТУП ===")
ok(PL.CanIssue(cop) == true, "полицейский может выдавать номера")
ok(PL.CanIssue(civ) == false, "гражданский — нет")
ok(PL.CanIssue(root) == true, "суперадмин может")
ok(PL.CanCheck(civ) == false, "гражданский не пробивает базу")
ok(PL.CanCheck(cop) == true, "служба пробивает")

print("\n=== 4. ВЫДАЧА ===")
local rec, err = PL.Issue({ type = "civil", ownerKey = "civ:char1", ownerName = "Ганс Мюллер",
    by = "cop:char1", byName = "Копп", vehicle = "Opel" })
ok(rec ~= nil, "номер выдан", err)
ok(rec and rec.status == "active", "статус — действителен")
ok(PL.Get(rec.number) == rec, "номер находится в реестре")
ok(#PL.ListFor("civ:char1") == 1, "номер числится за владельцем")
local dup2, errDup = PL.Issue({ type = "civil", number = rec.number, ownerKey = "civ:char1" })
ok(dup2 == nil and tostring(errDup):find("уже выдан", 1, true) ~= nil, "повторная выдача того же номера отклонена", errDup)
local bad, errBad = PL.Issue({ type = "spaceship", ownerKey = "civ:char1" })
ok(bad == nil and isstring(errBad), "неизвестный тип отклонён")
local noOwner = select(2, PL.Issue({ type = "civil" }))
ok(isstring(noOwner), "без владельца номер не выдаётся")

CONVARS["grm_plates_limit"]:SetValue("1")
local overflow, errLimit = PL.Issue({ type = "civil", ownerKey = "civ:char1" })
ok(overflow == nil and tostring(errLimit):find("предел", 1, true) ~= nil, "лимит знаков на персонажа работает", errLimit)
CONVARS["grm_plates_limit"]:SetValue("6")

print("\n=== 5. СТАТУСЫ ===")
ok(select(1, PL.Revoke(rec.number, "Копп")) == true, "номер аннулируется")
ok(PL.Get(rec.number).status == "revoked", "статус записан")
ok(#(PL.Get(rec.number).history or {}) >= 2, "история ведётся")
PL.SetStatus(rec.number, "active", "Копп")
ok(PL.Get(rec.number).status == "active", "и восстанавливается")
ok(select(1, PL.SetStatus(rec.number, "чтототакое", "Копп")) == false, "неизвестный статус отклонён")
ok(select(1, PL.SetStatus("НЕТ000ТТ", "revoked", "Копп")) == false, "несуществующий номер отклонён")

print("\n=== 6. ФИЗИЧЕСКИЙ ЗНАК И РУЧНАЯ УСТАНОВКА ===")
local plate = PL.SpawnPlate(rec.number, Vector(0, 0, 0), Angle(0, 0, 0), civ)
ok(IsValid(plate), "бланк знака создан")
ok(plate:GetNWString("GRM_Plate", "") == rec.number, "на знаке напечатан номер")
ok(select(1, PL.SpawnPlate("АА999ХХ")) == nil, "незарегистрированный номер бланком не выдаётся")

local car = ents.Create("sim_car")
car:SetPos(Vector(0, 0, 0))
car.VD_Class = "simfphys_opel"
-- «Москвич»: от бампера до центра больше сотни юнитов
car.NearestPoint = function(self, pos) return Vector(math.max(-110, math.min(110, pos.x)), 0, 0) end
ok(select(1, PL.Attach(plate, car, civ)) == true, "знак закреплён на машине")
ok(plate:GetParent() == car, "знак стал частью машины")
ok(car:GetNWString("GRM_PlateNumber", "") == rec.number, "номер машины виден для проверки")
ok(#PL.VehiclePlates(car) == 1, "машина знает свои знаки")

-- второй знак: перед и зад
local plate2 = PL.SpawnPlate(rec.number, Vector(0, 0, 0), Angle(0, 0, 0), civ)
PL.Attach(plate2, car, civ)
ok(#PL.VehiclePlates(car) == 2, "на машине можно повесить и передний, и задний знак")

ok(select(1, PL.Detach(plate2, civ)) == true, "знак снимается")
ok(plate2:GetParent() == nil, "снятый знак больше не часть машины")
ok(#PL.VehiclePlates(car) == 1, "второй остался на месте")

print("\n=== 7. КТО МОЖЕТ ТРОГАТЬ ЗНАК ===")
local owner = mkPly("Ганс", "", false, "civ")
ok(PL.CanHandle(owner, plate) == true, "владелец может снять свой знак")
local stranger = mkPly("Чужой", "", false, "other")
ok(PL.CanHandle(stranger, plate) == false, "посторонний — нет")
ok(PL.CanHandle(cop, plate) == true, "сотрудник может изъять знак")

print("\n=== 8. ЗНАКИ ВОЗВРАЩАЮТСЯ ПОСЛЕ ГАРАЖА ===")
-- эмулируем личный транспорт с записью гаража
local garageRec = { id = "veh1", class = "simfphys_opel" }
GRM.VehicleDealer = {
    FindRecord = function(_, id) return id == "veh1" and garageRec or nil end,
    SaveGarages = function() end,
}
car.GRMGarageOwner, car.GRMGarageID = owner, "veh1"
PL.RememberLayout(car)
ok(istable(garageRec.plates) and #garageRec.plates == 1, "раскладка знаков записана в гараж",
   garageRec.plates and #garageRec.plates)
ok(istable(garageRec.plates[1].pos) and isnumber(garageRec.plates[1].pos.x),
   "координаты записаны числами (Vector в JSON не пишется)")

-- машина «убрана и выдана заново»
plate:Remove()
car:Remove()
local car2 = ents.Create("sim_car")
car2:SetPos(Vector(100, 0, 0))
hook.Run("GRM_VehicleIssued", owner, car2, garageRec)
ok(#PL.VehiclePlates(car2) == 1, "после выдачи из гаража знак вернулся на машину", #PL.VehiclePlates(car2))
ok(car2:GetNWString("GRM_PlateNumber", "") == rec.number, "номер снова виден на машине")

print("\n=== 9. ХРАНЕНИЕ РЕЕСТРА ===")
ok(PL.SaveNow() == true, "реестр записан на диск")
local raw = files["grm_plates/registry.json"]
ok(raw ~= nil and raw:find(rec.number, 1, true) ~= nil, "номер попал в файл")
PL.Data.plates = {}
ok(PL.Load() == true and PL.Get(rec.number) ~= nil, "реестр читается обратно")
ok(PL.Get(rec.number).ownerName == "Ганс Мюллер", "владелец пережил перезагрузку")

print("\n=== 10. КОМАНДЫ И СЕТЬ ===")
ok(HOOKS["PlayerSay"] and HOOKS["PlayerSay"]["GRM_Plates_Chat"] ~= nil, "чат-команда зарегистрирована")
local said = HOOKS["PlayerSay"]["GRM_Plates_Chat"]
cop.chat = ""
ok(said(cop, "/номер " .. rec.number) == "", "команда проверки съедается")
ok(tostring(cop.chat):find("Владелец", 1, true) ~= nil, "сотруднику печатается карточка номера", cop.chat)
civ.chat = ""
LASTNOTIFY = nil
said(civ, "/номер " .. rec.number)
ok(tostring(civ.chat) == "" and tostring(LASTNOTIFY):find("служба", 1, true) ~= nil,
   "гражданскому база не открывается", tostring(LASTNOTIFY))
ok(NETSENT[PL.Net.ACT] ~= nil, "приём действий окна зарегистрирован")

print("\n=== 11. ОРИЕНТАЦИЯ НАДПИСИ НА ЗНАКЕ ===")
-- раскладка настраивается: ось, поворот, зеркало, масштаб
ok(istable(PL.Render), "настройка раскладки объявлена")
local base = PL.FaceGeometry(Vector(-12, -36, -0.5), Vector(12, 36, 0.5), { axis = "auto", yaw = 0, scale = 1 })
ok(base.rightAxis == "y" and base.upAxis == "x", "поворот 0°: строка вдоль длинной стороны")
local turned = PL.FaceGeometry(Vector(-12, -36, -0.5), Vector(12, 36, 0.5), { axis = "auto", yaw = 90, scale = 1 })
ok(turned.rightAxis == "x" and turned.upAxis == "y", "поворот 90° меняет оси местами")
ok(turned.w == base.h and turned.h == base.w, "и размеры поля меняются вместе с ними")
local flipped = PL.FaceGeometry(Vector(-12, -36, -0.5), Vector(12, 36, 0.5), { axis = "auto", yaw = 0, flip = true, scale = 1 })
ok(flipped.right.y == -base.right.y, "зеркало разворачивает строку")
local forced = PL.FaceGeometry(Vector(-12, -36, -0.5), Vector(12, 36, 0.5), { axis = "y", yaw = 0, scale = 1 })
ok(forced.thin == "y", "ось лица можно задать вручную, если модель нестандартная")
local scaled = PL.FaceGeometry(Vector(-12, -36, -0.5), Vector(12, 36, 0.5), { axis = "auto", yaw = 0, scale = 0.5 })
ok(math.abs(scaled.w - base.w * 0.5) < 0.01, "масштаб поля учитывается", scaled.w)

-- габариты hunter-плашки: тонкая по Z, длинная сторона — вдоль Y
local face = PL.FaceGeometry(Vector(-12, -36, -0.5), Vector(12, 36, 0.5), { axis = "auto", yaw = 0, scale = 1 })
ok(face.thin == "z", "тонкая ось распознана как толщина знака", face.thin)
ok(face.rightAxis == "y" and face.upAxis == "x",
   "строка номера идёт вдоль ДЛИННОЙ стороны (номер не боком)", face.rightAxis .. "/" .. face.upAxis)
ok(face.w > face.h, "поле знака шире, чем выше", face.w .. "x" .. face.h)
ok(math.abs(face.half - 0.5) < 0.001, "половина толщины посчитана", face.half)
-- знак, повёрнутый в модели иначе: длинная сторона по X
local face2 = PL.FaceGeometry(Vector(-36, -12, -0.5), Vector(36, 12, 0.5), { axis = "auto", yaw = 0, scale = 1 })
ok(face2.rightAxis == "x" and face2.upAxis == "y", "для другой модели строка тоже идёт по длинной стороне")
-- вертикальная плашка (тонкая по Y)
local face3 = PL.FaceGeometry(Vector(-36, -0.5, -12), Vector(36, 0.5, 12), { axis = "auto", yaw = 0, scale = 1 })
ok(face3.thin == "y" and face3.rightAxis == "x", "нормаль и строка считаются и для вертикальной плашки")

print("\n=== 12. КРЕПЛЕНИЕ: ДАЛЁКИЙ ЦЕНТР МАШИНЫ НЕ МЕШАЕТ ===")
local plate3 = PL.SpawnPlate(rec.number, Vector(112, 0, 0), Angle(0, 0, 0), owner)
local farCar = ents.Create("sim_car")
farCar:SetPos(Vector(0, 0, 0))
farCar.NearestPoint = function(self, pos) return Vector(math.max(-110, math.min(110, pos.x)), 0, 0) end
ok(isfunction(PL.HandlePlateUse), "единая обработка [E] по знаку объявлена")
ok(isfunction(PL.LooksLikeVehicle) and PL.LooksLikeVehicle(farCar) == true, "машина распознаётся")
ok(PL.VehicleBase(farCar) == farCar, "база машины — она сама")
local attached = PL.HandlePlateUse(owner, plate3, farCar)
ok(attached == true, "знак у бампера крепится, хотя центр машины в сотне юнитов")
ok(plate3:GetParent() == farCar, "знак стал частью машины")
LASTNOTIFY = nil
PL.HandlePlateUse(owner, plate3)
ok(plate3:GetParent() == nil and tostring(LASTNOTIFY):find("снят", 1, true) ~= nil,
   "повторное [E] снимает знак и сообщает об этом", tostring(LASTNOTIFY))
LASTNOTIFY = nil
PL.HandlePlateUse(stranger, plate3)
ok(tostring(LASTNOTIFY):find("чужой", 1, true) ~= nil, "чужому отвечают отказом, а не молчанием", tostring(LASTNOTIFY))
LASTNOTIFY = nil
local lonely = PL.SpawnPlate(rec.number, Vector(9000, 9000, 0), Angle(0, 0, 0), owner)
PL.HandlePlateUse(owner, lonely)
ok(tostring(LASTNOTIFY):find("Рядом нет транспорта", 1, true) ~= nil,
   "если машины рядом нет — понятная подсказка", tostring(LASTNOTIFY))

print("\n=== 13. ЗНАК В РУКАХ ФИЗГАНА ===")
local held = PL.SpawnPlate(rec.number, Vector(112, 0, 0), Angle(0, 0, 0), owner)
HOOKS["PhysgunPickup"]["GRM_Plates_Held"](owner, held)
ok(owner.GRMHeldPlate == held, "система помнит знак в руках")
owner.GetActiveWeapon = function() return { GetClass = function() return "weapon_physgun" end, _valid = true } end
local blocked = HOOKS["PlayerUse"]["GRM_Plates_UseVehicle"](owner, farCar)
ok(blocked == false, "[E] по машине со знаком в руках не сажает в салон")
ok(held:GetParent() == farCar, "и сразу крепит знак")

print("\n=== 14. НОМЕР ПОМНИТ КОНКРЕТНУЮ МАШИНУ ===")
-- машина с записью гаража: удаляем её вместе со знаком и выдаём заново
local recCar = { id = "veh_2", class = "simfphys_moskvich", name = "Москвич" }
GRM.VehicleDealer = {
    FindRecord = function(_, id) return id == "veh_2" and recCar or nil end,
    SaveGarages = function() end,
}
local myCar = ents.Create("sim_car")
myCar:SetPos(Vector(0, 0, 0))
myCar.GRMGarageOwner, myCar.GRMGarageID = owner, "veh_2"
myCar.NearestPoint = function(self, pos) return Vector(math.max(-110, math.min(110, pos.x)), 0, 0) end
-- картотека: имя машины берётся из записи гаража
local myRec = { id = "veh_2", name = "Москвич" }
GRM.VehicleDealer = GRM.VehicleDealer or {}
GRM.VehicleDealer.FindRecord = function(_, id) return id == "veh_2" and myRec or nil end
GRM.VehicleDealer.SaveGarages = function() end

local number2 = select(1, PL.Issue({ type = "civil", ownerKey = "civ:char1", ownerName = "Ганс Мюллер",
    by = "cop:char1", byName = "Копп" })).number
local myPlate = PL.SpawnPlate(number2, Vector(112, 0, 0), Angle(0, 0, 0), owner)
ok(select(1, PL.Attach(myPlate, myCar, owner)) == true, "знак закреплён на личной машине")
local mount = PL.Get(number2).mount
ok(istable(mount) and mount.vehicleID == "veh:veh_2", "в реестре записан ИДЕНТИФИКАТОР конкретной машины", mount and mount.vehicleID)
ok(istable(mount.pos) and isnumber(mount.pos.x) and istable(mount.ang),
   "запомнено и место установки на кузове")
ok(tostring(mount.vehicle) == "Москвич", "название машины записано для картотеки", mount.vehicle)

-- «машину удалили»: знак уходит вместе с ней, запись остаётся
myPlate:Remove()
myCar:Remove()
ok(#PL.EntitiesOf(number2) == 0, "физического знака больше нет")
ok(PL.Get(number2).mount ~= nil, "но привязка к машине в реестре сохранилась")

-- машина выдана заново (та же запись гаража)
local sameCar = ents.Create("sim_car")
sameCar:SetPos(Vector(500, 0, 0))
sameCar.GRMGarageOwner, sameCar.GRMGarageID = owner, "veh_2"
recCar.plates = nil    -- даже если раскладка в гараже потерялась
local restored = PL.RestoreForVehicle(owner, sameCar, recCar)
ok(restored == 1, "знак вернулся на ту же машину по идентификатору из реестра", restored)
ok(sameCar:GetNWString("GRM_PlateNumber", "") == number2, "номер снова читается на машине")
ok(#PL.VehiclePlates(sameCar) == 1, "дублей знака не появилось")

-- чужая машина знак не получает
local otherCar = ents.Create("sim_car")
otherCar:SetPos(Vector(900, 0, 0))
local otherRec = { id = "veh_3", plates = nil }
ok(PL.RestoreForVehicle(owner, otherCar, otherRec) == 0, "на другую машину чужой знак не встаёт")

print("\n=== 15а. БАЗА НОМЕРОВ НЕ ЗАТИРАЕТСЯ ПУСТОТОЙ ===")
-- пока файл не прочитан, запись запрещена: иначе очередь сохранит пустую
-- таблицу поверх выданных номеров
local keepPlates, keepLoaded = PL.Data.plates, PL._loaded
PL._loaded = false
PL.Data.plates = {}
local savedWhileUnloaded = PL.SaveNow()
ok(savedWhileUnloaded == false, "до загрузки реестр на диск не пишется")
ok(files["grm_plates/registry.json"]:find(rec.number, 1, true) ~= nil,
   "файл с номерами остался целым")
PL._loaded, PL.Data.plates = keepLoaded, keepPlates
ok(PL.SaveNow() == true, "после загрузки запись снова разрешена")

print("\n=== 15. ПОДГОНКА ЗНАКА В ИГРЕ ===")
ok(isfunction(PL.RenderCommand), "команды подгонки объявлены")
local before = PL.Render.yaw
PL.RenderCommand(root, "yaw", 90)
ok(PL.Render.yaw == (before + 90) % 360, "поворот крутится по 90°", PL.Render.yaw)
PL.RenderCommand(root, "axis")
ok(PL.Render.axis ~= "auto", "ось переключается", PL.Render.axis)
PL.RenderCommand(root, "flip")
ok(PL.Render.flip == true, "зеркало переключается")
PL.RenderCommand(root, "scale", 1.5)
ok(math.abs(PL.Render.scale - 1.5) < 0.001, "масштаб задаётся числом")
PL.RenderCommand(root, "offset", 3)
ok(math.abs(PL.Render.offset - 3) < 0.001, "вынос надписи от поверхности настраивается", PL.Render.offset)
local faceOff = PL.FaceGeometry(Vector(-12, -36, -0.5), Vector(12, 36, 0.5),
    { axis = "auto", yaw = 0, scale = 1, offset = 3 })
ok(math.abs(faceOff.offset - 3) < 0.001, "и попадает в геометрию грани — надпись не тонет в пропе")

-- вынос считается по нормали ПЛОСКОСТИ надписи, а не по выбранной оси
local cl = (function()
    local f = io.open("lua/entities/grm_plate/cl_init.lua", "rb")
    local t = f:read("*a") f:close() return t
end)()
ok(cl:find("right:Cross(up)", 1, true) ~= nil,
   "нормаль берётся как векторное произведение осей надписи")
ok(cl:find("local ang = right:AngleEx(nrm)", 1, true) ~= nil,
   "3D2D-угол строится по нормали плоскости, а не по оси up")
ok(cl:find("local function planeAxes(ent, face)", 1, true) ~= nil
   and cl:find("math.abs(dLong.z) <= math.abs(dShort.z)", 1, true) ~= nil,
   "оси строки выбираются АВТОМАТИЧЕСКИ по положению знака в мире")
ok(cl:find("if up.z < 0 then up = up * -1 end", 1, true) ~= nil,
   "верх надписи всегда смотрит вверх — знак можно вешать как угодно")
ok(cl:find("function ENT:Draw()", 1, true) ~= nil
   and cl:find("function ENT:DrawTranslucent()", 1, true) ~= nil
   and cl:find("self:Draw()", 1, true) == nil,
   "надпись рисуется ОДИН раз за кадр (модель в Draw, номер в DrawTranslucent)")
ok(cl:find("local fit = math.min((room * 0.88)", 1, true) ~= nil,
   "номер автоматически вписывается в поле знака по ширине и высоте")
ok(cl:find("nrm = nrm * -1", 1, true) ~= nil and cl:find("right = right * -1", 1, true) ~= nil,
   "номер фиксированно рисуется на внешней, противоположной кузову стороне")
ok(cl:find("local renderScale = 0.60", 1, true) ~= nil,
   "поле номера уменьшено вместе с моделью знака")
ok(cl:find("local lift = (face.thickness or 1) * 0.5", 1, true) ~= nil,
   "надпись лежит на самой поверхности знака, а не висит перед ним")

-- плашка на экране показывается только при взгляде НА ЗНАК
local core = (function()
    local f = io.open("lua/autorun/sh_grm_plates.lua", "rb")
    local t = f:read("*a") f:close() return t
end)()
ok(core:find('lookPlate = (IsValid(ent) and ent:GetClass() == "grm_plate") and ent or nil', 1, true) ~= nil,
   "плашка ловит только сам знак")
ok(core:find('hook.Add("PostDrawTranslucentRenderables", "GRM_Plates_WorldLabel"', 1, true) ~= nil,
   "номер рисуется 3D2D в мире, а не поверх экрана")
ok(core:find('hook.Add("HUDPaint", "GRM_Plates_HUD"', 1, true) == nil,
   "экранной плашки посреди монитора больше нет")
ok(core:find("CurTime() - lookAt > 0.2", 1, true) ~= nil, "трассировка троттлится, покадровых трейсов нет")
PL.RenderCommand(civ, "yaw", 90)
ok(PL.Render.yaw ~= (before + 180) % 360, "обычный игрок настройку не крутит")
ok(PL.SaveRender() == true and files["grm_plates/render.json"] ~= nil, "раскладка сохраняется на диск")

print("\n=== 16. ПОЛНАЯ ПОДГОНКА ЗНАКА ===")
ok(istable(PL.RenderKeys) and #PL.RenderKeys == 10, "набор настроек раскладки объявлен", #PL.RenderKeys)
local norm = PL.NormalizeRender({ axis = "чтото", yaw = 137, scale = 99, offset = -5,
    tiltP = 400, moveX = 100, flip = 1 })
ok(norm.axis == "auto", "неизвестная ось падает в auto")
ok(norm.yaw % 90 == 0, "поворот кратен 90°", norm.yaw)
ok(norm.scale <= 3 and norm.offset >= 0, "масштаб и вынос зажаты в пределах")
ok(norm.tiltP <= 180 and norm.moveX <= 24, "наклон и сдвиг зажаты в пределах")
ok(norm.flip == false, "флаг зеркала — строго логический")

PL.RenderCommand(root, "reset")
ok(PL.Render.tiltP == 0 and PL.Render.moveX == 0, "сброс возвращает раскладку к базовой")
PL.RenderCommand(root, "tiltP", 15)
PL.RenderCommand(root, "tiltY", -30)
PL.RenderCommand(root, "tiltR", 45)
ok(PL.Render.tiltP == 15 and PL.Render.tiltY == -30 and PL.Render.tiltR == 45,
   "наклон крутится по трём осям", PL.Render.tiltP .. "/" .. PL.Render.tiltY .. "/" .. PL.Render.tiltR)
PL.RenderCommand(root, "moveX", 2)
PL.RenderCommand(root, "moveX", 2)
PL.RenderCommand(root, "moveY", -1.5)
ok(PL.Render.moveX == 4 and PL.Render.moveY == -1.5, "сдвиг накапливается по осям знака",
   PL.Render.moveX .. "/" .. PL.Render.moveY)
local faceFull = PL.FaceGeometry(Vector(-12, -36, -0.5), Vector(12, 36, 0.5), PL.Render)
ok(faceFull.tiltR == 45 and faceFull.moveX == 4, "доводка доходит до геометрии грани")
ok(cl:find("ang:RotateAroundAxis(ang:Forward(), face.tiltR)", 1, true) ~= nil
   and cl:find("ang:RotateAroundAxis(ang:Right(), face.tiltP)", 1, true) ~= nil
   and cl:find("ang:RotateAroundAxis(ang:Up(), face.tiltY)", 1, true) ~= nil,
   "все три оси поворота применяются при отрисовке")
ok(cl:find("right * (face.moveX or 0) + up * (face.moveY or 0)", 1, true) ~= nil,
   "ручной сдвиг по-прежнему считается вдоль осей самой надписи")

print("\n=== 17. СНИМОК ОКНА ПОРЦИЯМИ ===")
ok(core:find("GRM.Net.Stream(PL.Net.SYNC", 1, true) ~= nil,
   "снимок реестра уходит потоком, а не одним пакетом")
ok(isfunction(PL.PushSoon), "серия действий схлопывается в одну отправку")

print("\n=== 18. ПАМЯТЬ КРЕПЛЕНИЯ И ПРИВЯЗКА К МАШИНЕ ===")
ok(isfunction(PL.NormalizeMount) and isfunction(PL.NudgeMount), "чистые функции крепления объявлены")
local old = PL.NormalizeMount({ vehicleID = "veh:42", vehicle = "Седан",
    pos = { x = 1, y = 2, z = 3 }, ang = { p = 0, y = 90, r = 0 } })
ok(old.parentKey == "veh:42" and old.parentType == "vehicle",
   "старая запись (только vehicleID) читается как полноценное крепление", old.parentKey)
ok(old.parentName == "Седан" and old.pos.y == 2 and old.ang.y == 90, "координаты и имя сохраняются")
local blank = PL.NormalizeMount(nil)
ok(blank.parentKey == "" and blank.pos.x == 0, "мусор превращается в пустое крепление")

local moved = PL.NudgeMount(old, "move", "z", 4)
ok(moved.pos.z == 7 and old.pos.z == 3, "сдвиг возвращает НОВОЕ крепление, оригинал не портится", moved.pos.z)
local turned = PL.NudgeMount(old, "turn", "yaw", 100)
ok(turned.ang.y == -170, "поворот сворачивается в диапазон -180…180", turned.ang.y)
local _, okAxis = PL.NudgeMount(old, "move", "q", 4)
ok(okAxis == false, "неизвестная ось отбивается")
local far = PL.NudgeMount(old, "move", "x", 9999)
ok(far.pos.x == PL.NudgeLimits.move, "сдвиг зажат пределом", far.pos.x)

local src = (function()
    local f = io.open("lua/autorun/sh_grm_plates.lua", "rb")
    local t = f:read("*a") f:close() return t
end)()
ok(src:find("GRM.Vehicles.EnsureUID", 1, true) ~= nil,
   "личность машины берётся из единого слоя транспорта (UID), а не из класса")
ok(src:find('hook.Add("EntityRemoved", "GRM_Plates_VehicleGone"', 1, true) ~= nil
   and src:find("mount.offMap = true", 1, true) ~= nil,
   "машину убрали с карты — привязка знака осталась за ней")
ok(src:find("function PL.PlateOfVehicleKey(uid)", 1, true) ~= nil,
   "номер машины можно спросить по UID — для окон дилера и госбаз")
ok(src:find("rec.plate = layout[1]", 1, true) ~= nil,
   "номер записывается в карточку машины у дилера")

local dealer = (function()
    local f = io.open("lua/entities/sent_vehicle_dealer/cl_init.lua", "rb")
    local t = f:read("*a") f:close() return t
end)()
ok(dealer:find("local function garageCell(parent, v)", 1, true) ~= nil
   and dealer:find("VC.TableRow(parent, {", 1, true) ~= nil
   and dealer:find("VC.TableHeader(list", 1, true) ~= nil,
   "транспорт у дилера показан табличным списком: одна машина = одна строка")
local cells = (function()
    local f = io.open("lua/autorun/client/cl_grm_vehicle_cells.lua", "rb")
    local t = f:read("*a") f:close() return t
end)()
ok(cells:find('plate ~= "" and plate or "БЕЗ НОМЕРА"', 1, true) ~= nil,
   "в ячейке видно номерной знак машины")
ok(dealer:find("plate = v.plate", 1, true) ~= nil, "номер уходит в ячейку у дилера")

-- 22.08: ячейка одна на все окна — дилер, гараж, автопарк
local garageUI = (function()
    local f = io.open("lua/autorun/client/cl_grm_garage_ui.lua", "rb")
    local t = f:read("*a") f:close() return t
end)()
local fleetSrc = (function()
    local f = io.open("lua/autorun/sh_grm_fleet.lua", "rb")
    local t = f:read("*a") f:close() return t
end)()
ok(garageUI:find("VC.TableRow(list, {", 1, true) ~= nil
   and garageUI:find("VC.TableHeader(list", 1, true) ~= nil,
   "в окне гаража таблица и у личного, и у СЛУЖЕБНОГО транспорта")
ok(fleetSrc:find("VC.TableRow(list, {", 1, true) ~= nil
   and fleetSrc:find("VC.TableHeader(list", 1, true) ~= nil,
   "вкладка «Автопарк» организации тоже табличным списком")
ok(fleetSrc:find('PlateOfVehicleKey("fleet:"', 1, true) ~= nil,
   "у служебной техники в таблице свой номер")
ok(dealer:find("local function garageCard", 1, true) == nil,
   "старые строки-карточки гаража удалены, копий разметки нет")

print("\n=== 19. ГДЕ И КАК РЕГИСТРИРУЮТ НОМЕРА ===")
ok(isfunction(PL.IssueReason), "право выдачи объясняется причиной, а не молча")
local okAdm, whyAdm = PL.IssueReason({ _valid = true,
    IsSuperAdmin = function() return true end,
    GetNWString = function() return "" end })
ok(okAdm == true and tostring(whyAdm):find("суперадмин", 1, true) ~= nil,
   "суперадмин видит основание", tostring(whyAdm))
local okCiv, whyCiv = PL.IssueReason({ _valid = true,
    IsSuperAdmin = function() return false end,
    GetNWString = function() return "" end })
ok(okCiv == false and tostring(whyCiv) ~= "", "гражданскому объясняют, почему нельзя", tostring(whyCiv))
local okCop, whyCop = PL.IssueReason({ _valid = true,
    IsSuperAdmin = function() return false end,
    GetNWString = function() return "OrdnungPolizei" end })
ok(okCop == true and tostring(whyCop):find("Ordnung", 1, true) ~= nil,
   "полиция порядка опознаётся по названию организации", tostring(whyCop))

local psrc = (function()
    local f = io.open("lua/autorun/sh_grm_plates.lua", "rb")
    local t = f:read("*a") f:close() return t
end)()
ok(psrc:find('officerReason = tostring(why or "")', 1, true) ~= nil
   and psrc:find("PL.OfficerReason = tostring(data.officerReason", 1, true) ~= nil,
   "причина уходит в окно вместе со снимком")
ok(psrc:find("ВЫ МОЖЕТЕ РЕГИСТРИРОВАТЬ НОМЕРА", 1, true) ~= nil
   and psrc:find("КАК ПОЛУЧИТЬ НОМЕР", 1, true) ~= nil,
   "в окне видно, кто вы и что делать дальше")
ok(psrc:find('local selfBtn = button(issue, "СЕБЕ"', 1, true) ~= nil,
   "сотрудник может зарегистрировать номер на себя одной кнопкой")
ok(psrc:find('low:find("^/номер_выдать") == 1', 1, true) ~= nil
   and psrc:find('concommand.Add("grm_plate_issue"', 1, true) ~= nil,
   "выдача доступна и командой: /номер_выдать <ник> [тип] [номер]")
ok(psrc:find('low == "/номер_статус"', 1, true) ~= nil,
   "команда /номер_статус объясняет права прямо в чат")

-- 22.08: право нужно не только проверять, но и ВЫДАВАТЬ — значит оно должно
-- быть объявлено в обоих списках, где владелец его ищет.
ok(psrc:find('GRM.Access.Register("plates.issue"', 1, true) ~= nil
   and psrc:find('GRM.Access.Register("plates.check"', 1, true) ~= nil,
   "привилегии объявлены в платформе (/admin → Привилегии)")
local perms = (function()
    local f = io.open("lua/autorun/sh_grm_faction_perms.lua", "rb")
    local t = f:read("*a") f:close() return t
end)()
ok(perms:find("plates_issue = ", 1, true) ~= nil and perms:find("plates_check = ", 1, true) ~= nil,
   "права организации объявлены (/factions → Доступы)")
ok(psrc:find("PlayerHasPermission(ply, \"plates_check\")", 1, true) ~= nil,
   "проверка номеров тоже уважает право организации")
ok(psrc:find("Руководителю: право даётся в /factions", 1, true) ~= nil,
   "в окне написано, где выдать право")

-- 22.08 (вторая жалоба): выдал доступ — окно должно ОБНОВИТЬСЯ, и право
-- из /admin должно доходить до модулей.
ok(psrc:find('hook.Add("GRM_AccessChanged", "GRM_Plates_AccessChanged"', 1, true) ~= nil,
   "после выдачи прав снимок окна рассылается заново")
ok(psrc:find('GRM.Perf.Coalesce("plates.access.push"', 1, true) ~= nil,
   "пачка галочек схлопывается в одну рассылку")
local admin = (function()
    local f = io.open("lua/autorun/sh_grm_admin_core.lua", "rb")
    local t = f:read("*a") f:close() return t
end)()
ok(admin:find('GRM.Access.RegisterProvider("grm_admin_platform"', 1, true) ~= nil
   and admin:find("AD.CanLocal(ply, capability)", 1, true) ~= nil,
   "права /admin работают как capability (мост через провайдер, без CAMI-рекурсии)")
ok(admin:find('hook.Run("GRM_AccessChanged", "admin_platform")', 1, true) ~= nil,
   "админ-платформа сообщает об изменении прав")
ok(perms:find('hook.Run("GRM_AccessChanged", "faction_perms")', 1, true) ~= nil,
   "доступы организаций тоже сообщают")
ok(perms:find('ply:GetNWString("GRM_Faction", "")', 1, true) ~= nil
   and perms:find("PERMS.RoleHasPermission(nwFaction, nwRole, permission)", 1, true) ~= nil,
   "право находится и по NW-полям, если состав организации ключован иначе")

print("\n=== 20. ЖИВОЕ ОКНО УЧЁТА И ЯЧЕЙКИ ЗНАКОВ (22.08) ===")
ok(psrc:find("PL.Viewers = PL.Viewers or {}", 1, true) ~= nil
   and psrc:find("function PL.PushViewers(reason)", 1, true) ~= nil,
   "сервер знает, у кого открыто окно учёта")
ok(psrc:find("PL.PushViewers(why)", 1, true) ~= nil,
   "любая правка реестра рассылается зрителям — терминал обновляется сам")
ok(psrc:find('GRM.Perf.Coalesce("plates.viewers.push"', 1, true) ~= nil,
   "пачка изменений схлопывается в одну рассылку")
ok(psrc:find('elseif act == "watch" then', 1, true) ~= nil,
   "клиент сообщает об открытии и закрытии окна — лишних пакетов нет")
ok(psrc:find('act("watch", { on = false })', 1, true) ~= nil, "закрыли окно — подписка снята")
ok(psrc:find("self.GRMWatchAt = RealTime() + 10", 1, true) ~= nil,
   "есть редкая страховка на случай потерянного пакета")

ok(psrc:find("local function plateGrid(parent)", 1, true) ~= nil,
   "знаки показаны сеткой ячеек, а не строками")
ok(psrc:find('draw.RoundedBox(4, 12, 12, 18, ph, Color(def.band[1]', 1, true) ~= nil,
   "ячейка выглядит как сам знак: поле, цветная полоса, номер")
ok(psrc:find('label = "ЗАЯВИТЬ ОБ УТЕРЕ"', 1, true) ~= nil
   and psrc:find("rec.status == \"revoked\"", 1, true) ~= nil,
   "действия переехали в саму карточку номера")

local dealer2 = (function()
    local f = io.open("lua/entities/sent_vehicle_dealer/cl_init.lua", "rb")
    local t = f:read("*a") f:close() return t
end)()
ok(dealer2:find("local function catalogCard(grid, v)", 1, true) ~= nil
   and dealer2:find("VC.Cell(grid, {", 1, true) ~= nil,
   "каталог дилера (в том числе СЛУЖЕБНЫЕ вкладки) тоже на ячейках")
ok(dealer2:find('if currentMode ~= "active" then', 1, true) ~= nil,
   "сетка включена во всех разделах, кроме «На карте»")

print("\n=== 21. НОМЕРА ТРАНСПОРТА АВТОПАРКА НЕ ВЕШАЮТСЯ САМИ (22.08) ===")
ok(isfunction(PL.ServiceKind), "серия определяется по организации")
ok(PL.ServiceKind("Ordnungspolizei") == "police", "полиция → полицейская серия", PL.ServiceKind("Ordnungspolizei"))
ok(PL.ServiceKind("Feldgendarmerie") == "police", "жандармерия → полицейская серия", PL.ServiceKind("Feldgendarmerie"))
ok(PL.ServiceKind("Militarkomendatur") == "military", "комендатура → военная серия", PL.ServiceKind("Militarkomendatur"))
ok(PL.ServiceKind("Ministerium") == "gov", "прочие ведомства → государственная серия", PL.ServiceKind("Ministerium"))
ok(PL.ServiceKind(nil) == "gov", "без организации — государственная серия")
ok(psrc:find("function PL.EnsureServicePlate(ply, ent, faction, uid)", 1, true) ~= nil,
   "ручной инструмент выдачи служебного номера остался")
ok(psrc:find('hook.Add("GRM_FleetIssued", "GRM_Plates_ServiceAuto"', 1, true) == nil,
   "автоматической выдачи и крепления номера у машин автопарка больше НЕТ")
ok(psrc:find('hook.Add("GRM_FleetIssued", "GRM_Plates_FleetRestore"', 1, true) ~= nil,
   "ручной номер за единицей автопарка возвращается при выдаче")
ok(psrc:find("function PL.RestoreFleetPlate(ent, uid", 1, true) ~= nil
   and psrc:find("local existing = PL.PlateOfVehicleKey(uid)", 1, true) ~= nil,
   "RestoreFleetPlate возвращает существующий номер, новый не создаёт")
ok(psrc:find("function PL.MountOnRear(plate, veh, actor)", 1, true) ~= nil,
   "знак вешается на задний борт по габаритам машины")
ok(psrc:find('CreateConVar("grm_plates_auto_service", "0"', 1, true) ~= nil,
   "автоматика по умолчанию выключена (конвар 0)")
ok(psrc:find('timer.Create("GRM_Plates_ViewersTick", 5, 0', 1, true) ~= nil,
   "открытое окно учёта обновляется само каждые 5 секунд")

print("\n=== 22. КРЕПЛЕНИЕ ПО ЗАМЕРАМ МОДЕЛИ (22.08) ===")
ok(istable(PL.ModelGeometry) and PL.ModelGeometry.thin == "z"
   and PL.ModelGeometry.long == "y" and PL.ModelGeometry.short == "x",
   "оси модели зафиксированы: тонкая z, длинная y, короткая x")
ok(math.abs((PL.ModelGeometry.halfThickness or 0) - 1.225) < 0.001,
   "половина толщины знака взята из замера (3.5 / 2)")
ok(isfunction(PL.SurfaceAngles) and isfunction(PL.PlaceOnSurface),
   "есть постановка знака на поверхность по нормали")
ok(psrc:find("return up:AngleEx(n)", 1, true) ~= nil,
   "углы строятся одной операцией: Forward = верх таблички, Up = нормаль")
ok(psrc:find("ang:RotateAroundAxis(ang:Up(), 180)", 1, true) == nil,
   "старый разворот углов машины на 180° убран — он клал знак ребром")
ok(psrc:find("if math.abs(n:Dot(up)) > 0.95 then", 1, true) ~= nil,
   "знак на полу или потолке не вырождается: верх подбирается заново")
ok(psrc:find("up = up - n * up:Dot(n)", 1, true) ~= nil,
   "верх таблички очищается от составляющей вдоль нормали")
ok(psrc:find("local hitBase = PL.VehicleBase(tr.Entity) or tr.Entity", 1, true) ~= nil,
   "по [E] знак встаёт ровно туда, куда смотрит игрок")
ok(psrc:find("if not ok then ok, err = PL.MountOnRear(plate, veh, ply) end", 1, true) ~= nil,
   "если игрок не смотрит на кузов — знак уходит на задний борт")
ok(psrc:find("function PL.MountOnRear(plate, veh, actor)", 1, true) ~= nil
   and psrc:find("validateMountPoint(veh, mount.pos)", 1, true) ~= nil,
   "точка заднего борта по габаритам с веером лучей и валидацией")

print("\n=== 23. ОБНОВЛЕНИЕ НЕ СБИВАЕТ РАБОТУ (22.08) ===")
ok(psrc:find("PL.Form = PL.Form or {}", 1, true) ~= nil
   and psrc:find("e.OnChange = function(self) PL.Form[key] = self:GetValue() or \"\" end", 1, true) ~= nil,
   "поля запоминают набранный текст между пересборками")
ok(psrc:find('entry(findCard, "Например: А123ВС (можно латиницей)", "find")', 1, true) ~= nil
   and psrc:find('"issue_number")', 1, true) ~= nil
   and psrc:find('"issue_vehicle")', 1, true) ~= nil,
   "поля поиска и регистрации получили свои ключи")
ok(psrc:find("PL.Form.issue_owner = pickedKey", 1, true) ~= nil
   and psrc:find("PL.Form.issue_type = pickedType", 1, true) ~= nil,
   "выбранные владелец и серия не сбрасываются")
ok(psrc:find("function PL.RestoreScroll(list, key)", 1, true) ~= nil
   and psrc:find('PL.RestoreScroll(content, "main")', 1, true) ~= nil,
   "прокрутка возвращается на место после обновления")
ok(psrc:find("if not IsValid(list) or tries > 8 then return end", 1, true) ~= nil,
   "возврат прокрутки повторяется до восьми кадров — холст меряется не сразу")

print("\n=== 24. ПРИВЯЗКА В БАЗЕ: ЛИЧНАЯ И СЛУЖЕБНАЯ (22.08) ===")
do
    -- Личная: машина имеет GRMGarageID/GRMGarageOwner, поэтому Attach пишет
    -- и запись гаража, и реестр номеров; PlateOfVehicleKey должно найти.
    local owner = civ
    local car = ents.Create("sim_car")
    local recID = "veh_789"
    car.GRMGarageID = recID
    car.GRMGarageOwner = owner
    GRM.VehicleDealer = GRM.VehicleDealer or {}
    GRM.VehicleDealer.FindRecord = function(pl, id)
        if pl == owner and id == recID then
            return { id = recID, name = "Седан", plates = {}, plate = "" }
        end
        return nil
    end
    GRM.VehicleDealer.SaveGarages = function() end
    local nrec = { number = "А888ВС", type = "civil", ownerKey = civ:GetNWString("SteamID64", "") .. ":char1" }
    PL.Data.plates[nrec.number] = nrec

    local plate = PL.SpawnPlate(nrec.number, car:GetPos(), car:GetAngles(), owner)
    PL.Attach(plate, car, owner)
    local pf = PL.PlateOfVehicleKey(PL.VehicleIdentity(car))
    ok(pf == nrec.number, "после Attach личная машина в базе привязана", pf)
    ok(nrec.mount ~= nil and tostring(nrec.mount.parentKey) == PL.VehicleIdentity(car),
        "у записи номера есть mount.parentKey")

    -- Служебная: машина имеет GRMFleetID, но записи в личном гараже нет.
    local fleetEnt = ents.Create("sim_car")
    local fleetID = "fu_plate_1"
    fleetEnt.GRMFleetID = fleetID
    GRM.Fleet = GRM.Fleet or {}
    local unit = { id = fleetID, name = "Патрульная", plates = {}, plate = "" }
    GRM.Fleet.Unit = function(id) if tostring(id) == fleetID then return unit end return nil end
    GRM.Fleet.SaveFleet = function() end
    GRM.VehicleDealer.FindRecord = function() return nil end -- нет личной записи

    local fplate = PL.SpawnPlate(nrec.number, fleetEnt:GetPos(), fleetEnt:GetAngles(), owner)
    PL.Attach(fplate, fleetEnt, owner)
    local fpf = PL.PlateOfVehicleKey(PL.VehicleIdentity(fleetEnt))
    ok(fpf == nrec.number, "после Attach служебная машина в базе привязана", fpf)
    ok(unit.plate ~= "" or unit.plates ~= nil, "раскладка/номер записаны в единицу автопарка",
        tostring(unit.plate) .. " / plates=" .. tostring(unit.plates ~= nil))
    ok(tostring(unit.vehicleUID or "") ~= "", "vehicleUID записан в единицу автопарка", tostring(unit.vehicleUID))
end

print("\n=== 25. ПОЛОЖЕНИЕ ЗНАКА НА МОДЕЛИ (22.08) ===")
do
    ok(isfunction(PL.NormalizeLayout), "layout нормализуется")
    ok(isfunction(PL.LayoutFor) and isfunction(PL.SetLayout), "layout читается/сохраняется")

    local layoutCar = ents.Create("sim_car")
    layoutCar._class = "sim_layout_car"
    local lay = PL.SetLayout("sim_layout_car", {
        pos = { x = -100, y = 0, z = 50 },
        normal = { x = -1, y = 0, z = 0 },
        upHint = { x = 0, y = 0, z = 1 },
    })
    ok(lay ~= nil and lay.pos.x == -100, "layout класса сохранён", lay and lay.pos.x)
    local got = PL.LayoutFor(layoutCar)
    ok(got ~= nil and got.pos.x == -100 and got.normal.x == -1, "LayoutFor находит layout класса",
        got and got.pos.x)
    local mp = PL.MountPointFor(layoutCar)
    -- В моке LocalToWorld = GetPos() + v, поэтому точка будет -100,0,50
    ok(mp ~= nil and mp.normal and mp.normal.x < 0 and mp.pos.x == -100, "MountPointFor учитывает layout",
        mp and tostring(mp.pos.x) .. "/" .. (mp and tostring(mp.normal.x)))
    PL.SetLayout("sim_layout_car", nil)
    ok(PL.LayoutFor(layoutCar) == nil, "layout класса сбрасывается")
end

-- ================================================================
print("\n=== КРЕПЛЕНИЕ СЗАДИ: ТОЧКА НА БАМПЕРЕ, А НЕ ПОД КРЫШЕЙ ===")
-- ================================================================
do
    --[[ ЖАЛОБА ВЛАДЕЛЬЦА: «нету нормального крепления сзади, крепит
         хрен пойми как». Причин оказалось две, и обе в поиске точки:

         1. Проверка нормали была ПЕРЕВЁРНУТА: луч идёт из-за пределов
            машины внутрь, то есть вдоль -dir, а наружная нормаль
            смотрит вдоль dir. Проверяли n:Dot(-dir) — для верного
            попадания это -1, поэтому отбрасывались ВСЕ попадания.
            До поверхности кузова дело не доходило, знак всегда
            ставился грубым фолбэком по габариту.

         2. Веер высот шёл сверху вниз (0.82 → 0.22) и останавливался
            на первом удачном — самом ВЕРХНЕМ. Номер уезжал под крышку
            багажника.

         Здесь трассировка настоящая: пересечение луча с габаритом
         машины. Без неё эти две ошибки не поймать — мок не даёт
         util.TraceLine, и код молча уходит в фолбэк. ]]
    local car = ents.Create("sim_mount_car")
    car:SetPos(Vector(0, 0, 0))

    local MN, MX = Vector(-110, -40, 0), Vector(110, 40, 60)   -- габарит мока
    --[[ Габарит КОЛЛИЗИИ уже визуального: у настоящих машин так и
         есть (бампер выступает за коробку столкновений). Без этого
         различия трассировка и фолбэк дают почти одну точку, и
         перевёрнутую проверку нормали не отличить. ]]
    local TB = { min = Vector(-104, -40, 0), max = Vector(104, 40, 60) }
    local H = MX.z - MN.z                                       -- 60
    local FLOOR = MN.z + math.Clamp(H * 0.18, 12, 24)           -- уровень кузова
    local BUMPER_TOP = MN.z + H * 0.45                          -- верх бамперной зоны

    -- Пересечение отрезка с габаритом: возвращает точку и нормаль грани.
    local function hitBox(p0, p1)
        local d = Vector(p1.x - p0.x, p1.y - p0.y, p1.z - p0.z)
        local tmin, axis = 0, 1
        local keys = { "x", "y", "z" }
        for i, k in ipairs(keys) do
            local o, dd = p0[k], d[k]
            if math.abs(dd) < 1e-9 then
                if o < TB.min[k] or o > TB.max[k] then return nil end
            else
                local t1, t2 = (TB.min[k] - o) / dd, (TB.max[k] - o) / dd
                if t1 > t2 then t1, t2 = t2, t1 end
                if t1 > tmin then tmin, axis = t1, i end
                if t2 < tmin then return nil end
            end
        end
        local hit = Vector(p0.x + d.x * tmin, p0.y + d.y * tmin, p0.z + d.z * tmin)
        local n = Vector(0, 0, 0)
        n[keys[axis]] = d[keys[axis]] > 0 and -1 or 1
        return hit, n
    end

    local oldTrace = util.TraceLine
    util.TraceLine = function(opts)
        local hit, n = hitBox(opts.start, opts.endpos)
        if not hit then return {} end
        return { Hit = true, Entity = car, HitPos = hit, HitNormal = n }
    end

    local front, rear = PL.MountEnds(car)
    ok(rear ~= nil, "задняя точка крепления найдена")
    if rear then
        -- Точка на поверхности кузова, а не на отлёте от габарита.
        ok(math.abs(rear.pos.x - TB.min.x) < 3,
            "ЗАДНЯЯ ТОЧКА НАЙДЕНА ТРАССИРОВКОЙ, А НЕ ФОЛБЭКОМ", tostring(rear.pos.x))
        -- Номер вешают на бампер, не под крышку багажника.
        ok(rear.pos.z >= FLOOR and rear.pos.z <= BUMPER_TOP,
            "ЗНАК СТАЛ НА ВЫСОТУ БАМПЕРА, А НЕ ПОД КРЫШУ",
            ("z=%.1f, бампер %.1f..%.1f"):format(rear.pos.z, FLOOR, BUMPER_TOP))
        -- И по центру кормы, а не краем за крыло.
        ok(math.abs(rear.pos.y) <= 22, "знак по центру кормы", tostring(rear.pos.y))
        -- Нормаль смотрит назад.
        ok(rear.normal and rear.normal.x < -0.35, "нормаль смотрит назад",
            rear.normal and tostring(rear.normal.x))
    end
    ok(front ~= nil and front.pos.x > 100, "передняя точка на переднем борте",
        front and tostring(front.pos.x))

    -- Фолбэк (трассировка не достала кузов) тоже обязан давать бампер.
    util.TraceLine = function() return {} end
    local _, rear2 = PL.MountEnds(car)
    ok(rear2 ~= nil, "фолбэк даёт точку")
    if rear2 then
        ok(rear2.pos.z >= FLOOR and rear2.pos.z <= BUMPER_TOP,
            "ФОЛБЭК ТОЖЕ НА ВЫСОТЕ БАМПЕРА", tostring(rear2.pos.z))
        ok(rear2.pos.x < TB.min.x, "фолбэк стоит у задней границы габарита",
            tostring(rear2.pos.x))
    end
    util.TraceLine = oldTrace
end

-- ================================================================
print("\n=== 25. ПАМЯТЬ НОМЕРА И УДАЛЕНИЕ ИЗ БАЗЫ ===")
-- ================================================================
do
    --[[ ЖАЛОБА ВЛАДЕЛЬЦА: «проблемы с запоминанием номеров и стиранием
         их из базы данных служебных компьютеров».

         Память позиции и раскладка знака пишутся в запись гаража.
         Запись ищут так:

             local ply = veh.GRMGarageOwner
             if not (IsValid(ply) and id) then return nil end

         А GRMGarageOwner — это ЭНТИТИ игрока. Владелец вышел с
         сервера — IsValid(ply) ложь, запись не находится, и память
         не пишется и не читается. Номер «забывает», куда его
         поставили. ]]
    local owner = mkPly("Фриц", "")
    local car = ents.Create("sim_car")
    car:SetPos(Vector(0, 0, 0))
    local recID = "veh_mem_1"
    car.GRMGarageID = recID
    car.GRMGarageOwner = owner
    local gRec = { id = recID, name = "Седан", plates = {}, plate = "" }
    local ownerKey = owner:SteamID64() .. ":char1"
    GRM.VehicleDealer = GRM.VehicleDealer or {}
    GRM.VehicleDealer.FindRecord = function(_, id) return id == recID and gRec or nil end
    GRM.VehicleDealer.SaveGarages = function() end
    GRM.VehicleDealer.Garages = { [ownerKey] = { [recID] = gRec } }
    GRM.Fleet = nil

    local nrec = { number = "М777ММ", type = "civil", ownerKey = ownerKey, status = "active" }
    PL.Data.plates[nrec.number] = nrec

    local plate = PL.SpawnPlate(nrec.number, car:LocalToWorld(Vector(-110, 0, 20)),
        car:LocalToWorldAngles(Angle(0, 180, 0)), owner)
    ok(IsValid(plate), "бланк знака создан")
    PL.Attach(plate, car, owner)

    ok(gRec.plateMemory ~= nil, "память позиции записана в запись гаража",
        tostring(gRec.plateMemory))
    ok(istable(gRec.plates) and #gRec.plates >= 1, "раскладка знака записана в гараж",
        tostring(gRec.plates and #gRec.plates))

    -- ВЛАДЕЛЕЦ ВЫШЕЛ С СЕРВЕРА. Машина осталась на карте.
    owner._valid = false
    local mem = PL._readVehicleMemory(car)
    ok(mem ~= nil, "ПАМЯТЬ ПОЗИЦИИ ЧИТАЕТСЯ, КОГДА ВЛАДЕЛЕЦ НЕ В СЕТИ",
        "владелец офлайн — запись гаража не найдена")

    -- Снимаем и вешаем знак обратно при офлайн-владельце: память
    -- должна пережить и запись.
    PL.Detach(plate, nil)
    gRec.plateMemory = nil          -- стираем, чтобы проверить запись заново
    plate:SetPos(car:LocalToWorld(Vector(-90, 10, 40)))
    PL.Attach(plate, car, nil)
    ok(gRec.plateMemory ~= nil, "ПАМЯТЬ ПИШЕТСЯ, КОГДА ВЛАДЕЛЕЦ НЕ В СЕТИ",
        tostring(gRec.plateMemory))
    if istable(gRec.plateMemory) and istable(gRec.plateMemory.pos) then
        ok(math.abs((tonumber(gRec.plateMemory.pos.x) or 0) - (-90)) < 2,
            "запомнена именно новая позиция", tostring(gRec.plateMemory.pos.x))
    end
    owner._valid = true

    -- ── УДАЛЕНИЕ ИЗ БАЗЫ ───────────────────────────────────────────
    local uid = tostring(nrec.vehicleUID or "")
    ok(uid ~= "", "у записи есть UID машины", uid)
    gRec.vehicleUID = uid

    local okDel, errDel = PL.Delete(nrec.number, "инспектор")
    ok(okDel == true, "номер удалён из реестра", tostring(errDel))
    ok(PL.Get(nrec.number) == nil, "НОМЕРА НЕТ В БАЗЕ ПОСЛЕ УДАЛЕНИЯ",
        tostring(PL.Get(nrec.number)))

    local inPayload = false
    local payload = PL.Snapshot and PL.Snapshot() or nil
    if istable(payload) and istable(payload.plates) then
        for _, r in ipairs(payload.plates) do
            if tostring(r.number) == nrec.number then inPayload = true end
        end
    end
    ok(payload == nil or not inPayload, "удалённого номера нет в снимке для компьютеров")

    ok(gRec.plate == nil or gRec.plate == "", "номер стёрт из записи гаража",
        tostring(gRec.plate))
    ok(gRec.plates == nil or #gRec.plates == 0, "раскладка стёрта из записи гаража",
        gRec.plates and tostring(#gRec.plates) or "nil")
    ok(gRec.vehicleUID == nil, "привязка машины к номеру снята", tostring(gRec.vehicleUID))
end

-- ================================================================
print("\n=== 26. АВТО-ТОЧКА НЕ ЗАЛИПАЕТ ===")
-- ================================================================
do
    --[[ ЖАЛОБА ВЛАДЕЛЬЦА: правка расчёта точки крепления ничего не
         меняет — знак всё равно встаёт криво.

         Причина: Attach всегда писал фактическую позицию в память
         машины. Авто-расчёт (MountOnRear) кончается тем же Attach,
         поэтому его результат — даже заведомо неудачный — попадал в
         память и вытеснял авто-точку при каждой следующей установке.
         Исправление расчёта для такой машины уже ничего не меняло:
         она помнила старую кривую точку. ]]
    local owner = mkPly("Отто", "")
    local recID = "veh_auto_1"
    local gRec = { id = recID, name = "Универсал", plates = {}, plate = "" }
    local ownerKey = owner:SteamID64() .. ":char1"
    GRM.VehicleDealer = GRM.VehicleDealer or {}
    GRM.VehicleDealer.FindRecord = function(_, id) return id == recID and gRec or nil end
    GRM.VehicleDealer.SaveGarages = function() end
    GRM.VehicleDealer.Garages = { [ownerKey] = { [recID] = gRec } }
    GRM.Fleet = nil

    local function newCar()
        local c = ents.Create("sim_car")
        c:SetPos(Vector(0, 0, 0))
        c.GRMGarageID = recID
        c.GRMGarageOwner = owner
        c.NearestPoint = function(_, pos)
            return Vector(math.max(-110, math.min(110, pos.x)),
                          math.max(-40, math.min(40, pos.y)),
                          math.max(0, math.min(60, pos.z)))
        end
        return c
    end

    -- А) авто-установка не должна писать память машины
    local car = newCar()
    local nrec = { number = "О001ОО", type = "civil", ownerKey = ownerKey, status = "active" }
    PL.Data.plates[nrec.number] = nrec
    local plate = PL.SpawnPlate(nrec.number, Vector(0, 0, 30), Angle(0, 0, 0), owner)
    PL.MountOnRear(plate, car, owner)
    ok(gRec.plateMemory == nil, "АВТО-ТОЧКА НЕ ПИШЕТСЯ В ПАМЯТЬ МАШИНЫ",
        tostring(gRec.plateMemory))

    -- Б) память, однажды записанная вручную, сохраняется
    local car2 = newCar()
    local plate2 = PL.SpawnPlate(nrec.number, car2:LocalToWorld(Vector(-108, 0, 18)),
        car2:LocalToWorldAngles(Angle(0, 180, 0)), owner)
    PL.Attach(plate2, car2, owner)
    ok(gRec.plateMemory ~= nil, "ручная установка память пишет", tostring(gRec.plateMemory))

    -- В) кривая (устаревшая) память отбрасывается, берётся авто-точка
    local car3 = newCar()
    gRec.plateMemory = { pos = { x = -400, y = 0, z = 20 }, ang = { p = 0, y = 180, r = 0 } }
    local mp = PL.MountPointFor(car3)
    ok(mp ~= nil, "точка найдена и при кривой памяти")
    if mp then
        ok(mp.pos.x > -200, "КРИВАЯ ПАМЯТЬ ОТБРОШЕНА — ВЗЯТА АВТО-ТОЧКА",
            tostring(mp.pos.x) .. " (память была -400)")
    end
    gRec.plateMemory = nil

    -- Г) годная память (на кузове) по-прежнему применяется
    local car4 = newCar()
    gRec.plateMemory = { pos = { x = -108, y = 0, z = 20 }, ang = { p = 0, y = 180, r = 0 } }
    local mp2 = PL.MountPointFor(car4)
    ok(mp2 ~= nil and mp2.exact == true and math.abs(mp2.pos.x - (-108)) < 2,
        "годная память на кузове применяется как есть",
        mp2 and tostring(mp2.pos.x) .. " exact=" .. tostring(mp2.exact))
    gRec.plateMemory = nil
end

-- ================================================================
print("\n=== 27. ПОДГОНКА СТРЕЛКАМИ: ПРЕДЕЛ И ПОЛ КУЗОВА ===")
-- ================================================================
do
    --[[ ЖАЛОБА ВЛАДЕЛЬЦА: «невозможно отодвинуть вперёд или назад
         сверх лимита значений и почему-то под машиной куда-то вниз
         уходит».

         PL.NudgeLimits.move = 64 накладывался на САМУ локальную
         координату: math.Clamp(pos.x, -64, 64). Корма типовой
         машины — это x ≈ -110, то есть за пределами. Первый же
         шаг стрелкой прибивал знак к -64: внутрь кузова, а не на
         корму. По z то же самое: знак уезжал на -64, то есть под
         машину под днище.

         Предел должен считаться от того места, где знак стоял до
         начала подгонки, а не от нуля локальных координат. ]]
    local owner = mkPly("Курт", "")
    local car = ents.Create("sim_car")
    car:SetPos(Vector(0, 0, 0))
    local recID = "veh_nudge_1"
    local gRec = { id = recID, name = "Седан", plates = {}, plate = "" }
    car.GRMGarageID = recID
    car.GRMGarageOwner = owner
    GRM.VehicleDealer = GRM.VehicleDealer or {}
    GRM.VehicleDealer.FindRecord = function(_, id) return id == recID and gRec or nil end
    GRM.VehicleDealer.SaveGarages = function() end
    GRM.VehicleDealer.Garages = { [owner:SteamID64() .. ":char1"] = { [recID] = gRec } }
    GRM.Fleet = nil

    local nrec = { number = "Н002НН", type = "civil",
        ownerKey = owner:SteamID64() .. ":char1", status = "active" }
    PL.Data.plates[nrec.number] = nrec

    -- Ставим знак на корму: x = -110, как у настоящей машины.
    local plate = PL.SpawnPlate(nrec.number, car:LocalToWorld(Vector(-110, 0, 20)),
        car:LocalToWorldAngles(Angle(0, 180, 0)), owner)
    PL.Attach(plate, car, owner)

    local lp0 = car:WorldToLocal(plate:GetPos())
    ok(math.abs(lp0.x - (-110)) < 2, "знак стоит на корме", tostring(lp0.x))

    -- Двигаем НАЗАД на 5: было бы -115. Старый предел прибил бы к -64.
    local okN, errN = PL.NudgeMounted(plate, "move", "x", -5)
    ok(okN == true, "подгонка по x проходит", tostring(errN))
    local lp1 = car:WorldToLocal(plate:GetPos())
    ok(math.abs(lp1.x - (-115)) < 2, "ПОДГОНКА ПО X НЕ ПРИБИВАЕТСЯ К ПРЕДЕЛУ ±64",
        ("стало x=%.1f (было -110, ждали -115)"):format(lp1.x))

    -- Двигаем ВПЕРЁД: тоже должно ходить.
    PL.NudgeMounted(plate, "move", "x", 20)
    local lp2 = car:WorldToLocal(plate:GetPos())
    ok(math.abs(lp2.x - (-95)) < 2, "подгонка вперёд ходит", tostring(lp2.x))

    -- ВНИЗ: знак не должен уезжать под машину. Пол кузова у мока —
    -- wmin.z + clamp(60 * 0.18, 12, 24) = 12.
    local okDown, errDown = PL.NudgeMounted(plate, "move", "z", -8)
    if okDown then
        local lp3 = car:WorldToLocal(plate:GetPos())
        ok(lp3.z >= 12, "ЗНАК НЕ УЕЗЖАЕТ ПОД МАШИНУ", tostring(lp3.z))
    else
        ok(true, "ЗНАК НЕ УЕЗЖАЕТ ПОД МАШИНУ (шаг отклонён: " .. tostring(errDown) .. ")")
    end
    local okSink = select(1, PL.NudgeMounted(plate, "move", "z", -100))
    ok(okSink == false, "попытка увести знак под машину отклоняется", tostring(okSink))

    -- ВВЕРХ ограничение не мешает.
    local okUp = select(1, PL.NudgeMounted(plate, "move", "z", 20))
    ok(okUp == true, "вверх знак двигается", tostring(okUp))
end

print("\n=== 20. РЕЕСТР РЕЖИМОВ ПОДГОНКИ РЕНДЕРА (ГРМ §5.4) ===")
--[[ renderCommand жил лестницей из восьми веток; наклон и сдвиг имели
     общие ветки `tiltP or tiltY or tiltR`. Реестр RENDER_ADJUST обязан
     вести себя байт-в-байт как старая лестница — проверим каждый режим
     ЖИВЫМ вызовом, включая квантование yaw (NormalizeRender) и то, что
     «show» и неизвестный ключ ничего не меняют. ]]
local supRender = { _valid = true, IsSuperAdmin = function() return true end,
    ChatPrint = function() end, GetNWString = function() return "" end }
PL.Render = PL.NormalizeRender({ axis = "auto", yaw = 90, scale = 1, offset = 1.5 })
PL.RenderCommand(supRender, "yaw", "45")
-- 90 + 45 = 135, но yaw квантован шагом 90 — станет 180
ok(PL.Render.yaw == 180, "yaw: шаг применяется и нормализуется", tostring(PL.Render.yaw))
PL.RenderCommand(supRender, "yaw")
ok(PL.Render.yaw == 270, "yaw без аргумента — дефолтный шаг 90", tostring(PL.Render.yaw))
PL.RenderCommand(supRender, "axis")
ok(PL.Render.axis == "x", "ось: цикл auto→x", tostring(PL.Render.axis))
PL.RenderCommand(supRender, "flip")
ok(PL.Render.flip == true, "зеркало переключается")
PL.RenderCommand(supRender, "scale", "10")
ok(PL.Render.scale == 3, "масштаб ограничен сверху (0.2..3)", tostring(PL.Render.scale))
PL.RenderCommand(supRender, "offset", "-5")
ok(PL.Render.offset == 0, "вынос не уходит в отрицательный", tostring(PL.Render.offset))
PL.RenderCommand(supRender, "tiltR", "-200")
ok(PL.Render.tiltR == -180, "наклон по любой из трёх осей зажат −180..180", tostring(PL.Render.tiltR))
PL.RenderCommand(supRender, "moveY", "50")
ok(PL.Render.moveY == 24, "сдвиг зажат ±24", tostring(PL.Render.moveY))
PL.RenderCommand(supRender, "show")
ok(PL.Render.tiltR == -180 and PL.Render.moveY == 24, "show ничего не меняет, только показывает")
PL.RenderCommand(supRender, "неттакой")
ok(PL.Render.yaw == 270, "неизвестный режим молчит, как раньше")
PL.RenderCommand(supRender, "reset")
ok(PL.Render.yaw == 90 and PL.Render.axis == "auto" and PL.Render.scale == 1
    and PL.Render.offset == 1.5 and PL.Render.tiltR == 0,
    "reset возвращает дефолт и стирает наклон")
local civRender = { _valid = true, IsSuperAdmin = function() return false end,
    ChatPrint = function() end, GetNWString = function() return "" end }
local before = PL.Render.yaw
PL.RenderCommand(civRender, "yaw", "90")
ok(PL.Render.yaw == before, "настройки знаков — право только у суперадмина")
ok(type(PL.RenderCommand) == "function" and psrc:find("elseif what ==", 1, true) == nil
    and psrc:find('tiltP" or what', 1, true) == nil,
    "лестницы what нет — только реестр RENDER_ADJUST")

print(("\nPLATES: %d/%d, провалов: %d"):format(pass, pass + fail, fail))
if fail > 0 then os.exit(1) end
