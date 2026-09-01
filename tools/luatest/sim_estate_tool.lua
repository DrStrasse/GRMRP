--[[ Живой прогон тула бизнес-зоны, фаза 3 (заказ владельца 27.08):
     «нужен модуль бизнеса который будет работать как GRM инструмент
      который выделяет зону бизнеса, а на месте зоны сразу идёт анализ
      наличия автоматов с едой».

     Проверяется:
       1) создание зоны туллом и её границы;
       2) АНАЛИЗ НА МЕСТЕ: сразу видно, сколько оборудования попало;
       3) вид зоны (бизнес/жильё) и цена из панели тула;
       4) удаление зоны и защита занятого объекта;
       5) оборудование вне зон подсвечивается отдельно;
       6) права: тул только для суперадмина.

     Запуск: luajit tools/luatest/sim_estate_tool.lua ]]
local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

SERVER, CLIENT = true, false
function AddCSLuaFile() end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isfunction(v) return type(v) == "function" end
function IsValid(v) return istable(v) and v._valid ~= false end
function string.Trim(s) return (string.gsub(tostring(s or ""), "^%s*(.-)%s*$", "%1")) end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function table.Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
function Vector(x, y, z)
    local v = { x = x or 0, y = y or 0, z = z or 0 }
    function v:DistToSqr(o)
        local dx, dy, dz = self.x - o.x, self.y - o.y, self.z - o.z
        return dx * dx + dy * dy + dz * dz
    end
    return v
end
function CurTime() return 500 end
function ErrorNoHalt() end
function ConVarExists() return true end
function CreateConVar() end
function GetConVar() return { GetInt = function() return 3 end } end
bit = { bor = function(a) return a end }
FCVAR_ARCHIVE, FCVAR_REPLICATED = 1, 2
hook = { Add = function() end, Run = function() end }
timer = { Simple = function() end, Create = function() end }
concommand = { Add = function() end }
util = { AddNetworkString = function() end, TableToJSON = function() return "{}" end,
    Compress = function(x) return x end }
net = setmetatable({}, { __index = function() return function() return "" end end })
local WORLD = {}
ents = { FindByClass = function(c)
    local out = {}
    for _, e in ipairs(WORLD) do if e._class == c and e._valid ~= false then out[#out + 1] = e end end
    return out
end }
GRM = {}

assert(loadfile("lua/autorun/sh_grm_estate.lua"))()
local ES = GRM.Estate

--- Минимальный GRM.Property: только то, чем пользуется тул.
local saved = 0
GRM.Property = {
    Records = {},
    Normalize = function(r)
        r = istable(r) and r or {}
        r.id = tostring(r.id or "")
        r.name = tostring(r.name or "")
        r.type = tostring(r.type or "apartment")
        r.estateKind = tostring(r.estateKind or "")
        r.ownerType = tostring(r.ownerType or "none")
        r.ownerName = tostring(r.ownerName or "")
        r.doors = r.doors or {}
        r.purchasePrice = math.max(0, math.floor(tonumber(r.purchasePrice) or 0))
        return r
    end,
    Reindex = function() end,
    Save = function() saved = saved + 1 end,
}

local function mkEnt(class, pos)
    local e = { _valid = true, _class = class, _pos = pos, GetPos = function(s) return s._pos end }
    WORLD[#WORLD + 1] = e
    return e
end

local admin = { _valid = true, IsSuperAdmin = function() return true end,
    EntIndex = function() return 1 end }
local player1 = { _valid = true, IsSuperAdmin = function() return false end,
    EntIndex = function() return 2 end }

print("\n=== 1. СОЗДАНИЕ ЗОНЫ ТУЛЛОМ ===")
-- Три точки внутри будущей зоны, одна далеко снаружи.
mkEnt("grm_vending_machine", Vector(100, 100, 10))
mkEnt("grm_vending_machine", Vector(200, 200, 10))
mkEnt("grm_fuel_pump", Vector(300, 150, 10))
mkEnt("grm_vending_machine", Vector(5000, 5000, 10))

local okCreate, msg, rec = ES.CreateZone(admin, Vector(0, 0, 0), Vector(400, 400, 0),
    "Торговый угол", "business", 85000)
ok(okCreate == true, "зона создаётся двумя углами", msg)
ok(rec ~= nil and GRM.Property.Records[rec.id] == rec, "объект попал в реестр недвижимости")
ok(saved > 0, "изменение сразу сохраняется на диск")
ok(rec and rec.estateKind == "business", "вид зоны — бизнес")
ok(rec and rec.purchasePrice == 85000, "цена взята из панели тула")
ok(rec and rec.name == "Торговый угол", "название взято из панели")

print("\n=== 2. АНАЛИЗ НА МЕСТЕ (главное в заказе) ===")
ok(tostring(msg):find("внутри точек: 3", 1, true) ~= nil,
   "сразу после создания сказано, сколько оборудования попало", msg)
local scan = ES.ScanZone(rec)
ok(scan.total == 3, "зона видит три точки", scan.total)
ok(scan.byKind.vending == 2 and scan.byKind.fuel == 1,
   "автоматы и колонки посчитаны отдельно")
ok(ES.EquipmentSummary(rec):find("2 автом", 1, true) ~= nil,
   "сводка читаемая", ES.EquipmentSummary(rec))

-- Предпросмотр до создания: тул считает содержимое произвольной коробки.
local preview = ES.ScanBox(Vector(0, 0, 0), Vector(250, 250, 200))
ok(preview.total == 2, "предпросмотр считает, что попадёт в будущую зону", preview.total)
local previewEmpty = ES.ScanBox(Vector(2000, 2000, 0), Vector(2100, 2100, 200))
ok(previewEmpty.total == 0, "пустая область даёт ноль")

print("\n=== 3. ВЫСОТА И РАЗМЕР ЗОНЫ ===")
ok(rec.zone.maxs.z > rec.zone.mins.z + 100,
   "зона автоматически растянута вверх — оборудование на полу попадает внутрь")
local okSmall, whySmall = ES.CreateZone(admin, Vector(0, 0, 0), Vector(10, 10, 0), "Мелочь", "business", 0)
ok(okSmall == false, "слишком узкую зону создать нельзя", whySmall)
ok(tostring(whySmall):find("мала", 1, true) ~= nil, "и причина объяснена", whySmall)

print("\n=== 4. ЗОНА ЖИЛЬЯ ===")
local okHome, msgHome, home = ES.CreateZone(admin, Vector(900, 0, 0), Vector(1100, 200, 0),
    "Квартира 14", "estate", 50000)
ok(okHome == true, "зона жилья создаётся", msgHome)
ok(home and ES.KindOf(home) == "estate", "вид — жильё")
ok(home and home.type == "apartment", "тип подобран под вид автоматически")
ok(ES.KindOf(rec) == "business", "бизнес-зона осталась бизнесом")

local okNoName, _, unnamed = ES.CreateZone(admin, Vector(3000, 0, 0), Vector(3200, 200, 0),
    "", "business", 0)
ok(okNoName and unnamed.name == "Бизнес-объект", "без названия подставляется понятное по умолчанию",
   unnamed and unnamed.name)

print("\n=== 5. УДАЛЕНИЕ ЗОНЫ ===")
local okDel, msgDel = ES.DeleteZoneAt(admin, Vector(3100, 100, 10))
ok(okDel == true, "свободная зона удаляется прицелом", msgDel)
ok(GRM.Property.Records[unnamed.id] == nil, "объект убран из реестра")

-- Занятый объект защищён от случайного сноса.
home.ownerType = "character"
home.ownerName = "Иванов"
local okBusy, msgBusy = ES.DeleteZoneAt(admin, Vector(1000, 100, 10))
ok(okBusy == false, "занятый объект не сносится молча", msgBusy)
ok(tostring(msgBusy):find("Иванов", 1, true) ~= nil, "и сказано, кто владелец", msgBusy)
home.ownerType = "none"
ok(select(1, ES.DeleteZoneAt(admin, Vector(1000, 100, 10))) == true,
   "освободили — теперь удаляется")

local okNone, msgNone = ES.DeleteZoneAt(admin, Vector(9999, 9999, 0))
ok(okNone == false, "в пустом месте удалять нечего", msgNone)

print("\n=== 6. ПРАВА ===")
ok(select(1, ES.CreateZone(player1, Vector(0, 0, 0), Vector(400, 400, 0), "Чужое", "business", 0)) == false,
   "обычный игрок зону не создаёт")
ok(select(1, ES.DeleteZoneAt(player1, Vector(100, 100, 10))) == false,
   "и не удаляет")

print("\n=== 7. ТУЛ И ЕГО ИНТЕРФЕЙС ===")
local function body(path)
    local fh = io.open(path, "rb") if not fh then return "" end
    local t = fh:read("*a") fh:close() return t
end
local tool = body("lua/weapons/gmod_tool/stools/grm_business.lua")
ok(tool ~= "", "файл тула на месте")
ok(tool:find('TOOL.Category = "GRM"', 1, true) ~= nil, "тул в категории GRM")
ok(tool:find("GRM.Estate.CreateZone", 1, true) ~= nil, "ПКМ создаёт зону")
ok(tool:find("GRM.Estate.DeleteZoneAt", 1, true) ~= nil, "R удаляет зону")
ok(tool:find("owner:IsSuperAdmin()", 1, true) ~= nil, "проверка прав на сервере")
ok(tool:find("countInside", 1, true) ~= nil,
   "предпросмотр показывает, сколько точек попадёт — анализ до создания")
ok(tool:find("попадёт точек:", 1, true) ~= nil, "и подписывает это игроку")
ok(tool:find("оборудование вне зон", 1, true) ~= nil,
   "видно оборудование, не вошедшее ни в одну зону")
ok(tool:find("COL_LOOSE", 1, true) ~= nil, "оно подсвечено отдельным цветом")
ok(tool:find('kind:AddChoice("Жильё', 1, true) ~= nil, "в панели можно выбрать вид объекта")
ok(tool:find("grm_business_price", 1, true) ~= nil, "и задать цену вручную — как решил владелец")

local core = body("lua/autorun/sh_grm_estate.lua")
ok(core:find("GRM_Estate_ToolReq", 1, true) ~= nil, "сервер отвечает на запросы тула")
ok(core:find("local function toolSnapshot()", 1, true) ~= nil, "снимок для тула собирается")
ok(core:find("if IsValid(ent) and not claimed[ent] then", 1, true) ~= nil,
   "оборудование вне зон вычисляется как «не занятое ни одной зоной»")
ok(core:find('GRM.Perf.Throttle("estate.tool."', 1, true) ~= nil,
   "запросы тула ограничены по частоте — сервер не захлебнётся")

print(("\n=== ИТОГ: успешно %d, провалено %d ===\n"):format(pass, fail))
if fail > 0 then os.exit(1) end
