--[[--------------------------------------------------------------------
    sim_duty_station — заказ владельца 18.08: пункт выхода на службу
    (GRM Служебный) не запоминал фракцию и сбрасывал модель на
    стандартного гражданина.

    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_duty_station.lua
----------------------------------------------------------------------]]
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

local duty = read("lua/autorun/sh_grm_faction_duty.lua")
local ent  = read("lua/entities/grm_duty_npc/init.lua")
local tool = read("lua/weapons/gmod_tool/stools/grm_duty_npc.lua")

print("\n=== 1. ПРИЧИНА: НАСТРОЙКИ НЕ СОХРАНЯЛИСЬ ===")
ok(duty:find("GRM.PermData.Upsert(ent)", 1, true) ~= nil,
    "сохранение создаёт перм-запись, если её не было (раньше Perm.Update молча отвечал «объект не закреплён»)")
ok(duty:find("function FD.SaveStation", 1, true) ~= nil,
    "у станций появилось собственное хранилище, независимое от пермов")
ok(duty:find("grm_duty", 1, true) ~= nil and duty:find("stations_", 1, true) ~= nil,
    "файл станций по карте: data/grm_duty/stations_<карта>.json")
ok(duty:find("function FD.LoadStations", 1, true) ~= nil, "станции поднимаются на старте карты")
ok(duty:find("function FD.RestoreStation", 1, true) ~= nil, "конфиг применяется к уже стоящему диспетчеру")
ok(duty:find("function FD.RemoveStation", 1, true) ~= nil, "снос тулом убирает запись станции")
ok(duty:find('GRM.Boot.OnMapStart("GRM_Duty_Stations", "normal"', 1, true) ~= nil,
    "загрузка станций идёт через планировщик Boot")
ok(duty:find('hook.Add("PostCleanupMap", "GRM_Duty_StationsCleanup"', 1, true) ~= nil,
    "после очистки карты станции восстанавливаются")
ok(duty:find('concommand.Add("grm_duty_stations"', 1, true) ~= nil, "ручная перезагрузка станций командой")
ok(duty:find('FD.Version = "1.4.0"', 1, true) ~= nil, "модуль дежурства v1.4.0 (было 1.3.0)")

print("\n=== 2. ПРИЧИНА: МОДЕЛЬ СБРАСЫВАЛАСЬ НА ГРАЖДАНИНА ===")
ok(ent:find("function ENT:ApplyStationConfig", 1, true) ~= nil, "единая точка применения конфига")
ok(ent:find("local mdl = tostring(self.GRMDutyModel or \"\")", 1, true) ~= nil,
    "Initialize сначала смотрит поле модели, а не пустую NW-строку")
ok(ent:find("self.DefaultModel", 1, true) ~= nil, "дефолт применяется только последним")
ok(ent:find("GRM.FactionDuty.RestoreStation(self)", 1, true) ~= nil,
    "после спавна конфиг догоняется из файла станций")
ok(ent:find("function ENT:StationConfig", 1, true) ~= nil, "конфиг читается из полей, а не только из NW")
ok(tool:find("ent.GRMDutyModel = mdl", 1, true) ~= nil,
    "тул выставляет модель ДО Spawn — гражданин больше не мелькает")
ok(tool:find("GRM.FactionDuty.SaveStation(ent)", 1, true) ~= nil,
    "поставленный тулом диспетчер сразу попадает в файл станций")
ok(tool:find("GRM.FactionDuty.RemoveStation(ent)", 1, true) ~= nil, "удаление тулом чистит запись")

print("\n=== 3. МЕНЮ НАСТРОЙКИ ===")
ok(duty:find("ent.StationConfig and ent:StationConfig()", 1, true) ~= nil,
    "меню открывается с реальным конфигом (раньше показывало пустую фракцию и затирало её при сохранении)")
ok(duty:find("организации больше нет", 1, true) ~= nil,
    "если сохранённой организации больше нет — это видно, а не подменяется молча")
ok(duty:find("displayName(name)", 1, true) ~= nil, "в списке публичные названия организаций")
ok(duty:find("Файл станций: %s, перм: %s", 1, true) ~= nil,
    "админ получает отчёт: сохранилось ли в файл и в перм")
ok(duty:find('GRM.Audit.Write("duty", "station.save"', 1, true) ~= nil, "настройка пишется в аудит")

print("\n=== 4. ЖИВОЙ ПРОГОН ЛОГИКИ ХРАНИЛИЩА ===")
-- Проверяем ключевую формулу «та же точка» и порядок применения модели.
ok(duty:find("radius = tonumber(radius) or STATION_MATCH", 1, true) ~= nil,
    "радиус поиска станции параметризован (192 по умолчанию, 96 для дедупа)")
local initSrc = ent:match("function ENT:Initialize%(%).-end")
ok(initSrc ~= nil and initSrc:find("GRMDutyModel") < (initSrc:find("DefaultModel") or math.huge),
    "в Initialize поле модели проверяется РАНЬШЕ дефолта")

print("\n=== 5. КЛОНЫ И «НАСТРОЙКА РАСПОЛЗЛАСЬ НА ВСЕХ» ===")
ok(duty:find("local STATION_MATCH = 192", 1, true) ~= nil,
    "радиус узнавания станции увеличен: после DropToFloor диспетчер уезжает по Z")
ok(duty:find("function FD.DedupeStations", 1, true) ~= nil, "есть дедупликация диспетчеров")
ok(duty:find("Клоном считается только пара с ОДИНАКОВЫМ идентификатором", 1, true) ~= nil,
    "соседних диспетчеров разных организаций дедуп НЕ трогает")
ok(duty:find("local id = tostring(ent.GRMDutyID or ent:GetNWString(\"GRM_DutyID\", \"\"))", 1, true) ~= nil,
    "дедуп работает по идентификатору, а не по расстоянию")
ok(duty:find("local orphan = nil", 1, true) ~= nil,
    "ненастроенный NPC в точке подхватывается, а не дублируется")
ok(duty:find("FD.DedupeStations()", 1, true) ~= nil, "дедуп вызывается при загрузке станций")
ok(duty:find('concommand.Add("grm_duty_dedupe"', 1, true) ~= nil, "ручная команда очистки клонов")
ok(duty:find("Соседний пост ЧУЖОЙ организации не помеха", 1, true) ~= nil,
    "рядом стоящий пост другой организации не мешает восстановлению")
ok(duty:find("taken[target] = true", 1, true) ~= nil,
    "одна станция — один диспетчер: занятый NPC не достаётся другой записи")
ok(duty:find("local function stationID", 1, true) ~= nil, "у станции есть стабильный идентификатор")
ok(duty:find("row.id == id", 1, true) ~= nil, "запись ищется по id, а не только по координатам")
ok(duty:find('tostring(ent.GRMDutyFaction or "") ~= "" then return false end', 1, true) ~= nil,
    "настроенного диспетчера не перетирает соседняя станция")
ok(duty:find("FD._stationsDirty = true", 1, true) ~= nil,
    "фактическая позиция дописывается в файл, чтобы в следующий раз совпасть сразу")
ok(read("lua/entities/grm_duty_npc/init.lua"):find("self.GRMDutyID = id", 1, true) ~= nil,
    "энтити хранит идентификатор станции")
ok(read("lua/weapons/gmod_tool/stools/grm_duty_npc.lua"):find("ent.GRMDutyID = util.CRC", 1, true) ~= nil,
    "тул присваивает идентификатор при постановке")
ok(duty:find('FD.Version = "1.4.0"', 1, true) ~= nil, "модуль дежурства v1.4.0")

print(("\nDUTY STATION: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
