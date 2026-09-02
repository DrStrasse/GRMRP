--[[--------------------------------------------------------------------
    sim_veh_name_clean — водяной знак «Comedy Effect» запрещён во всех
    модулях (заказ владельца от 02.09.2026).

    Сторонние паки техники вписывают своё клеймо в имя машины, и оно
    текло в надписи: заголовок окна ключей, карточку сидений, C-меню,
    подсказку наведения, багажник, каталог дилера, журнал автоучёта.
    Теперь фильтр один — VK.CleanName/VK.NameMarks в sh_vehicle_keys.lua;
    все точки показа имён делегируют ему. Правила, за которыми следит
    этот тест:
      1) VK.CleanName режет имена с меткой (любой регистр, подстрока) и
         пропускает чистые имена без изменений;
      2) VK.GetVehicleDisplayName при грязном источнике переходит к
         следующему кандидату; когда грязно всё (даже класс) — возвращает
         нейтральное «Транспорт», а не сырое имя;
      3) литералы-маркеры живут ТОЛЬКО в sh_vehicle_keys.lua — ни в одном
         другом файле lua/ и addons/ слова «comedy» нет (локальные
         фильтры плодить запрещено — они и есть прошлая ошибка);
      4) потребители (карточка сидений, V.Title, дилер, флот, рынок)
         ссылаются на общий фильтр, а не на свои списки слов.

    Запуск: luajit tools/luatest/sim_veh_name_clean.lua
----------------------------------------------------------------------]]

local pass, fail = 0, 0
local function ok(v, name, extra)
    if v then pass = pass + 1 print("  ok   " .. name)
    else fail = fail + 1 print("  FAIL " .. name .. "   " .. tostring(extra or "")) end
end
local function readf(p)
    local fh = assert(io.open(p, "rb"))
    local t = fh:read("*a") fh:close() return t
end

-----------------------------------------------------------------------
-- Минимальный мок GMod: шаренг-загрузка модуля VK.
-----------------------------------------------------------------------
SERVER, CLIENT = true, false
function AddCSLuaFile() end
function istable(v) return type(v) == "table" end
function isfunction(v) return type(v) == "function" end
function isstring(v) return type(v) == "string" end
function IsValid(v) return istable(v) and v._valid ~= false end
hook = { Add = function() end, Remove = function() end, Run = function() end }
net = { Start = function() end, WriteEntity = function() end, WriteString = function() end,
    SendToServer = function() end }
timer = { Simple = function() end, Create = function() end, Remove = function() end }
util = { AddNetworkString = function() end }
concommand = { Add = function() end }
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
function Material(m) return m end
_G.LISTS = {}
list = { Get = function(n) return _G.LISTS[n] end }
GRM = { Notify = function() end }

assert(loadfile("lua/autorun/sh_vehicle_keys.lua"))()

-----------------------------------------------------------------------
-- 1) Семантика VK.CleanName.
-----------------------------------------------------------------------
ok(VK.CleanName("Волга 3110") == "Волга 3110", "чистое имя проходит без изменений")
ok(VK.CleanName("Toyota Camry (Comedy Effect)") == nil, "имя с подписью отсекается")
ok(VK.CleanName("comedy") == nil, "нижний регистр тоже ловится")
ok(VK.CleanName("EFFECTS volvo") == nil, "слово effect* ловится в любом слове")
ok(VK.CleanName("") == nil and VK.CleanName(nil) == nil and VK.CleanName(7) == nil,
    "пустота/не-строка — nil")

-----------------------------------------------------------------------
-- 2) GetVehicleDisplayName: спуск по кандидатам без клейма.
-----------------------------------------------------------------------
local function veh(t)
    t._valid = true
    t.GetVehicleName = t.GetVehicleName or function() error("no name") end
    t.GetClass = t.GetClass or function() return t._class or "simfphys_generic" end
    return t
end

local v = veh({ GetVehicleName = function() return "Comedy Effect" end, PrintName = "Скаут-бугги" })
ok(VK.GetVehicleDisplayName(v) == "Скаут-бугги", "грязное GetVehicleName → PrintName")

v = veh({ GetVehicleName = function() return "УАЗ — comedy pack" end, PrintName = "effect thing",
    VehicleName = "Волга ГАЗ-24" })
ok(VK.GetVehicleDisplayName(v) == "Волга ГАЗ-24", "два грязных источника → VehicleName")

_G.LISTS["Vehicles"] = { simfphys_generic = { Name = "Comedy Effect Special" } }
v = veh({ _class = "simfphys_generic", GetVehicleName = function() return "Comedy Effect" end,
    PrintName = "Comedy Effect" })
ok(VK.GetVehicleDisplayName(v) == "simfphys_generic", "грязная запись списка → класс")

v = veh({ _class = "comedy_car01", GetVehicleName = function() return "Comedy Effect" end,
    PrintName = "Comedy Effect", VehicleName = "comedy ride" })
local shown = VK.GetVehicleDisplayName(v)
ok(shown == "Транспорт", "всё клеймо, даже класс → нейтральное слово", shown)
_G.LISTS["Vehicles"] = nil

ok(VK.GetVehicleDisplayName({ _valid = false }) == "Транспорт", "невалидная сущность — Транспорт")

-----------------------------------------------------------------------
-- 3) Литералы-маркеры — только в sh_vehicle_keys.lua.
-----------------------------------------------------------------------
local pipe = assert(io.popen("find lua addons -name '*.lua' | sort"))
local files = {}
for line in pipe:lines() do files[#files + 1] = line end
pipe:close()
local offenders, checked = {}, 0
for _, path in ipairs(files) do
    local fh = io.open(path, "rb")
    if fh then
        local src = fh:read("*a"):lower()
        fh:close()
        checked = checked + 1
        if src:find("comedy", 1, true) and path ~= "lua/autorun/sh_vehicle_keys.lua" then
            offenders[#offenders + 1] = path
        end
    end
end
ok(#offenders == 0, "ни в одном другом модуле литерала подписи нет (просмотрено " .. checked .. " файлов)",
    table.concat(offenders, ", "))
ok(readf("lua/autorun/sh_vehicle_keys.lua"):lower():find("comedy", 1, true) ~= nil,
    "список маркеров живёт в общем фильтре")

-----------------------------------------------------------------------
-- 4) Потребители делегируют общему фильтру.
-----------------------------------------------------------------------
local hud = readf("lua/autorun/client/cl_grm_vehicle_hud.lua")
ok(hud:find("VK.CleanName", 1, true) ~= nil, "карточка сидений зовёт общий фильтр")
ok(hud:lower():find("string.find(low") == nil, "локальный фильтр слов из HUD удалён")

local vehs = readf("lua/autorun/sh_grm_vehicles.lua")
ok(vehs:find("VK.CleanName", 1, true) ~= nil and vehs:find("cleanName(ent:GetNWString", 1, true) ~= nil,
    "V.Title фильтрует и имена, и NW-подпись")

local dealer = readf("lua/autorun/sh_grm_vehicle_dealer.lua")
ok(dealer:find("nameV", 1, true) ~= nil, "дилер прогоняет каталог через имя-фильтр")
ok(dealer:find('SetNWString("GRM_VehicleName",nameV', 1, true) ~= nil,
    "NW-имя спавна пишется уже чистым")

local fleet = readf("lua/autorun/sh_grm_fleet.lua")
ok(fleet:find("VK.CleanName(unit.name)", 1, true) ~= nil, "парк чистится на загрузке реестра")

local civ = readf("lua/autorun/sh_grm_civil_vehicle_market.lua")
ok(civ:find("cleanNm(e.name,e.class)", 1, true) ~= nil, "рынок отдаёт клиенту фильтрованные имена")

-- Старый HUD ключей тоже не плодит литералов (совпадение с проверкой sim_keyring_panel).
local old = readf("lua/autorun/client/cl_vehicle_hud.lua")
ok(old:find("Comedy", 1, true) == nil, "в cl_vehicle_hud.lua упоминаний нет")

print(("\nVEH NAME CLEAN: %d/%d, провалов: %d"):format(pass, pass + fail, fail))
os.exit(fail == 0 and 0 or 1)
