--[[ Живой прогон оружейной стойки (заказ владельца 27.08):
     ячейки, слоты, запоминание что где лежит, крупные ячейки с 3D-показом
     модели, база ArcCW, дизайн в рамках модуля логистики.

     Проверяется:
       1) сетка ячеек и её пределы;
       2) один ствол = одна ячейка, вложения ArcCW сохраняются;
       3) ПАМЯТЬ МЕСТА: сданный ствол возвращается на свою полку;
       4) закрепление ячейки за должностью, званием, отделом (оси v5);
       5) уменьшение сетки не съедает оружие молча;
       6) 3D-модель берётся из ArcCW WorldModel.

     Запуск: luajit tools/luatest/sim_weapon_rack.lua ]]
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
function string.Explode(sep, str)
    local out = {}
    for piece in string.gmatch(tostring(str or "") .. sep, "(.-)" .. sep) do out[#out + 1] = piece end
    return out
end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function table.HasValue(t, v) for _, x in pairs(t or {}) do if x == v then return true end end return false end
function table.Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
function table.Copy(t)
    if type(t) ~= "table" then return t end
    local o = {} for k, v in pairs(t) do o[k] = table.Copy(v) end return o
end
hook = { Add = function() end, Run = function() end }
timer = { Simple = function(_, fn) if fn then fn() end end }
concommand = { Add = function() end }
util = { AddNetworkString = function() end }
file = { Exists = function() return false end, Read = function() return "" end, Write = function() end }
net = setmetatable({}, { __index = function() return function() return "" end end })
function CurTime() return 100 end
function ErrorNoHalt() end

--- Мини-каталог ArcCW: WorldModel и PrintName, как у настоящих SWEP.
local CATALOG = {
    arccw_ak74  = { PrintName = "АК-74", WorldModel = "models/weapons/w_ak74.mdl", Category = "ArcCW" },
    arccw_makarov = { PrintName = "Макаров", WorldModel = "models/weapons/w_pist_makarov.mdl", Category = "ArcCW" },
    arccw_pkm   = { PrintName = "ПКМ", WorldModel = "models/weapons/w_pkm.mdl", Category = "ArcCW" },
}
weapons = { Get = function(c) return CATALOG[tostring(c or "")] end }

GRM = {}
-- Должности нужны по-настоящему: подпись закрепления берёт имя из них.
assert(loadfile("lua/autorun/sh_grm_faction_positions.lua"))()
assert(loadfile("lua/autorun/sh_grm_weapon_rack.lua"))()
local RK = GRM.WeaponRack

-- Организация: Комендантская рота, командир и рядовой.
local FAC = {
    DisplayName = "828-ая дивизия ВДВ",
    Departments = { "komendant" }, Subdepartments = {},
    Roles = { "sergeant", "private" },
    Positions = { rota_head = { id = "rota_head", name = "Командир роты",
        node = "dept:komendant", kind = "head", slots = 1 } },
    Members = {},
}
Factions = { ["828"] = FAC }

local boss = { _entity = true, _valid = true, _key = "1:char1", _wep = nil,
    IsSuperAdmin = function() return false end,
    SteamID64 = function() return "1" end,
    GetPos = function() return { DistToSqr = function() return 0 end } end,
    GetActiveWeapon = function(s) return s._wep end,
    StripWeapon = function(s) s._wep = nil end,
    HasWeapon = function() return false end,
    Give = function(_, cls) return { _valid = true, _class = cls,
        Attachments = {}, Attach = function() end, SetClip1 = function() end } end }
local grunt = { _entity = true, _valid = true, _key = "2:char1", _wep = nil,
    IsSuperAdmin = function() return false end,
    SteamID64 = function() return "2" end,
    GetPos = function() return { DistToSqr = function() return 0 end } end,
    GetActiveWeapon = function(s) return s._wep end,
    StripWeapon = function(s) s._wep = nil end,
    HasWeapon = function() return false end,
    Give = function(_, cls) return { _valid = true, _class = cls,
        Attachments = {}, Attach = function() end, SetClip1 = function() end } end }

FAC.Members["1:char1"] = { Role = "sergeant", Department = "komendant", Position = "rota_head" }
FAC.Members["2:char1"] = { Role = "private", Department = "komendant", Position = "" }
GRM.Identity = {
    CharacterKey = function(p) return p._key end,
    FactionMember = function(f, p) return f.Members[p._key] end,
}

-- Сущность-стойка.
local rackEnt = { _valid = true, _rackID = "rack_test", _faction = "828", _net = "VDV", _mode = true,
    EntIndex = function() return 7 end,
    GetPos = function() return { DistToSqr = function() return 0 end } end,
    GetClass = function() return "grm_weapon_rack" end,
    GetRackID = function(s) return s._rackID end, SetRackID = function(s, v) s._rackID = v end,
    GetFactionName = function(s) return s._faction end, SetFactionName = function(s, v) s._faction = v end,
    GetNetworkID = function(s) return s._net end, SetNetworkID = function(s, v) s._net = v end,
    GetFactionMode = function(s) return s._mode end, SetFactionMode = function(s, v) s._mode = v end }

print("\n=== 1. СЕТКА ЯЧЕЕК ===")
local rack = RK.RackOf(rackEnt)
ok(istable(rack), "стойка создаётся при первом обращении")
ok(#rack.cells == rack.cols * rack.rows, "ячеек ровно столько, сколько клеток сетки",
   #rack.cells .. " при " .. rack.cols .. "x" .. rack.rows)
ok(RK.CountFilled(rack) == 0, "новая стойка пуста")
local big = RK.NormalizeRack({ cols = 99, rows = 99 })
ok(big.cols <= RK.MaxCols and big.rows <= RK.MaxRows, "размер сетки ограничен сверху",
   big.cols .. "x" .. big.rows)

print("\n=== 2. ОДИН СТВОЛ = ОДНА ЯЧЕЙКА, ОБВЕС ArcCW ===")
-- Командир кладёт ПКМ с двумя вложениями.
boss._wep = { _valid = true, GetClass = function() return "arccw_pkm" end,
    Clip1 = function() return 100 end,
    Attachments = { [1] = { Installed = "optic_pso1" }, [3] = { Installed = "grip_bipod" } } }
local okDep, msgDep = RK.Deposit(boss, rackEnt, 1)
ok(okDep == true, "оружие кладётся в ячейку", msgDep)
ok(rack.cells[1].class == "arccw_pkm", "класс сохранён")
ok(rack.cells[1].name == "ПКМ", "имя взято из ArcCW SWEP", rack.cells[1].name)
ok(table.Count(rack.cells[1].attachments or {}) == 2, "вложения ArcCW сохранены",
   table.Count(rack.cells[1].attachments or {}))
ok(rack.cells[1].clip == 100, "патроны в магазине запомнены")
ok(boss._wep == nil, "ствол забран из рук игрока")
ok(RK.CountFilled(rack) == 1, "занята ровно одна ячейка")

boss._wep = { _valid = true, GetClass = function() return "arccw_ak74" end,
    Clip1 = function() return 30 end, Attachments = {} }
RK.Deposit(boss, rackEnt, 2)
ok(rack.cells[2].class == "arccw_ak74" and rack.cells[1].class == "arccw_pkm",
   "второй ствол лёг в свою ячейку, не смешавшись с первым")

print("\n=== 3. ПАМЯТЬ МЕСТА ===")
local okTake, msgTake = RK.Withdraw(boss, rackEnt, 1)
ok(okTake == true, "оружие выдаётся из ячейки", msgTake)
ok(RK.CellFilled(rack.cells[1]) == false, "ячейка освободилась")
ok(rack.cells[1].lastClass == "arccw_pkm", "ячейка помнит, что в ней лежало")

-- Кладём ПКМ снова, НЕ указывая ячейку: он обязан вернуться на своё место.
boss._wep = { _valid = true, GetClass = function() return "arccw_pkm" end,
    Clip1 = function() return 100 end, Attachments = {} }
RK.Deposit(boss, rackEnt, 0)
ok(rack.cells[1].class == "arccw_pkm",
   "сданный ствол вернулся на СВОЮ полку, а не в первую попавшуюся")

-- Ствол без истории занимает первую свободную.
boss._wep = { _valid = true, GetClass = function() return "arccw_makarov" end,
    Clip1 = function() return 8 end, Attachments = {} }
RK.Deposit(boss, rackEnt, 0)
ok(rack.cells[3].class == "arccw_makarov", "новый ствол занял первую свободную ячейку")

print("\n=== 4. ЗАКРЕПЛЕНИЕ ЯЧЕЙКИ (оси v5) ===")
-- Закрепляем ячейку 1 (ПКМ) за должностью командира роты.
rack.cells[1].position = "rota_head"
ok(RK.CellRestricted(rack.cells[1]) == true, "ячейка помечена как закреплённая")
ok(RK.CanUseCell(boss, rack, rack.cells[1]) == true, "командир роты берёт свой пулемёт")
local canGrunt, whyGrunt = RK.CanUseCell(grunt, rack, rack.cells[1])
ok(canGrunt == false, "рядовой пулемёт командира НЕ возьмёт", whyGrunt)
ok(select(1, RK.Withdraw(grunt, rackEnt, 1)) == false, "и выдача ему отклоняется сервером")
ok(RK.CanUseCell(grunt, rack, rack.cells[3]) == true, "незакреплённая ячейка доступна всем своим")

rack.cells[2].role = "sergeant"
ok(RK.CanUseCell(boss, rack, rack.cells[2]) == true, "закрепление по званию: сержант проходит")
ok(RK.CanUseCell(grunt, rack, rack.cells[2]) == false, "рядовой по званию не проходит")

rack.cells[3].dept = "komendant"
ok(RK.CanUseCell(grunt, rack, rack.cells[3]) == true, "по отделу свой проходит")
rack.cells[3].dept = "shtab"
ok(RK.CanUseCell(grunt, rack, rack.cells[3]) == false, "чужой отдел не проходит")
rack.cells[3].dept = ""

local scopeText = RK.CellScopeText(rack, rack.cells[1])
ok(scopeText == "Командир роты", "подпись закрепления читаемая", scopeText)

print("\n=== 5. ИЗМЕНЕНИЕ СЕТКИ БЕЗОПАСНО ===")
local admin = { _entity = true, _valid = true, IsSuperAdmin = function() return true end,
    GetPos = function() return { DistToSqr = function() return 0 end } end }
local okSize, msgSize = RK.Resize(admin, rackEnt, 1, 1)
ok(okSize == false, "нельзя ужать сетку, если в отрезаемых ячейках лежит оружие", msgSize)
ok(rack.cells[2].class == "arccw_ak74", "оружие при этом не пропало")
ok(select(1, RK.Resize(admin, rackEnt, 6, 4)) == true, "расширение сетки проходит")
ok(select(1, RK.Resize(grunt, rackEnt, 4, 2)) == false, "обычный игрок сетку не меняет")

print("\n=== 6. 3D-МОДЕЛЬ ИЗ ArcCW ===")
ok(RK.WeaponModel("arccw_ak74") == "models/weapons/w_ak74.mdl",
   "модель берётся из WorldModel SWEP", RK.WeaponModel("arccw_ak74"))
ok(RK.WeaponModel("нет_такого") == "", "у неизвестного класса модели нет")
ok(RK.WeaponName("arccw_makarov") == "Макаров", "имя берётся из PrintName")
ok(RK.WeaponName("unknown_gun") == "unknown_gun", "иначе показывается класс")

print("\n=== 7. СНИМОК ДЛЯ КЛИЕНТА ===")
local snap = RK.Snapshot(grunt, rackEnt)
ok(istable(snap) and #snap.cells == snap.cols * snap.rows, "снимок содержит все ячейки")
ok(snap.cells[1].allowed == false, "рядовому видно, что ячейка командира ему закрыта")
ok(snap.cells[1].model ~= "", "в снимок уходит модель для 3D-превью")
ok(snap.admin == false, "рядовой не получает админ-часть")
ok(RK.Snapshot(admin, rackEnt).admin == true, "суперадмин получает")
--[[ К этому моменту все три ячейки заняты, поэтому освобождаем одну:
     подсказка «было: …» появляется именно у ПУСТОЙ ячейки с историей. ]]
RK.Withdraw(boss, rackEnt, 2)
local snapAfter = RK.Snapshot(boss, rackEnt)
local emptyCell
for _, c in ipairs(snapAfter.cells) do
    if not c.class and c.lastName then emptyCell = c break end
end
ok(emptyCell ~= nil, "пустая ячейка подсказывает, что в ней лежало",
   emptyCell and emptyCell.lastName)
ok(emptyCell and emptyCell.lastName == "АК-74",
   "подсказка называет именно тот ствол, что лежал", emptyCell and emptyCell.lastName)

print("\n=== 8. ДИЗАЙН И ИНТЕГРАЦИЯ ===")
local function body(path)
    local fh = io.open(path, "rb") if not fh then return "" end
    local t = fh:read("*a") fh:close() return t
end
local ui = body("lua/autorun/client/cl_grm_weapon_rack.lua")
local ent = body("lua/entities/grm_weapon_rack/init.lua")
ok(ui:find("DModelPanel", 1, true) ~= nil, "в ячейке рисуется 3D-модель ствола")
ok(ui:find("cellW, cellH, gap = 188, 150", 1, true) ~= nil, "ячейки крупные")
ok(ui:find('Category = "GRM Faction Logistics"', 1, true) == nil, "UI не дублирует данные сущности")
ok(body("lua/entities/grm_weapon_rack/shared.lua"):find("GRM Faction Logistics", 1, true) ~= nil,
   "стойка стоит в категории логистики")
ok(ent:find("GetPermData", 1, true) ~= nil, "стойка переживает рестарт через PERM-DATA")
ok(ui:find("было: ", 1, true) ~= nil, "память места видна игроку в интерфейсе")

print(("\n=== ИТОГ: успешно %d, провалено %d ===\n"):format(pass, fail))
if fail > 0 then os.exit(1) end
