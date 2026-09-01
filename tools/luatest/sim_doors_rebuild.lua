--[[--------------------------------------------------------------------
    sim_doors_rebuild — ДВЕРИ v5.0.0: идентичность, фантомы, пересборка.

    Не только контракт по исходнику: поднимаем shared-часть модуля в моке
    GMod и реально гоняем дедупликатор на поддельных дверях.

    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_doors_rebuild.lua
----------------------------------------------------------------------]]
local stub = dofile("tools/luatest/lib_gmod_stub.lua")
stub.install()

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end
local src = read("lua/autorun/sh_grm_doors.lua")
local function has(s) return src:find(s, 1, true) ~= nil end

print("\n=== 1. КОНТРАКТ ИСХОДНИКА v5.0.0 ===")
ok(has('D.Version = "5.0.0"'), "версия 5.0.0")
ok(has("function D.AllDoors"), "единый список дверей D.AllDoors")
ok(not src:find("for _, ent in ipairs(ents.GetAll()) do\n        if IsValid(ent) and D.IsDoor(ent) then doors", 1, true),
    "полный ents.GetAll() из пересборки идентичности убран")
ok(has("IdentityCellSize"), "конфиг ячейки пространственного хэша")
ok(has("local function forEachCandidatePair"), "перебор только соседних ячеек (не O(n^2))")
ok(has("function D.InvalidateIdentity"), "сброс идентичности с отложенной пересборкой")
ok(has('GRM.Perf.Coalesce("doors.maintenance"'), "обслуживание коалесцируется (без таймера на каждую entity)")
ok(has("PurgeMapDoors"), "дубли полотен самой карты защищены флагом")
ok(has("function D.RebuildAll"), "полная пересборка D.RebuildAll")
ok(has("function D.BuildAuditReport"), "отчёт аудита отдельной функцией")
ok(has('concommand.Add("grm_door_rebuild"'), "консольная команда пересборки")
ok(has('cmd == "/door_rebuild"'), "чат-команда /door_rebuild")
ok(has("dropOrphans"), "режим удаления записей-сирот")
ok(has("GRM.Perf.EyeTrace"), "HUD дверей использует общий кэш трейса")
ok(src:find("timer.Simple(.1,function()", 1, true) == nil, "старый timer.Simple(0.1) на каждую entity удалён")

print("\n=== 2. ЖИВОЙ ПРОГОН ДЕДУПЛИКАТОРА ===")
stub.reset()
local loaded, err = stub.loadModule("lua/autorun/sh_grm_doors.lua")
local D = _G.GRM and _G.GRM.Doors
ok(D ~= nil, "модуль дверей поднялся в моке", err)
ok(type(D.RebuildDoorIdentityCache) == "function", "идентичность доступна")
ok(type(D.PurgeGhostDoors) == "function", "чистка фантомов доступна")

-- Полотно карты + его фантомный дубль в той же точке + отдельная дверь.
local mapDoor   = stub.makeDoor(0, 0, 0, { byMap = true, mapID = 12 })
local phantom   = stub.makeDoor(0, 0, 0, { byMap = false })
local farDoor   = stub.makeDoor(600, 0, 0, { byMap = true, mapID = 13 })

D.RebuildDoorIdentityCache()
local idMap, idPhantom, idFar = D.GetDoorID(mapDoor), D.GetDoorID(phantom), D.GetDoorID(farDoor)
ok(idMap == idPhantom, "фантом склеен с полотном карты в один канонический ID", tostring(idMap) .. " vs " .. tostring(idPhantom))
ok(idFar ~= idMap, "далёкая дверь осталась самостоятельной")
ok(D.GetPrimaryDoor(mapDoor) == D.GetPrimaryDoor(phantom), "у группы один primary")

local purged = D.PurgeGhostDoors()
ok(purged == 1, "ликвидирован ровно один фантом", tostring(purged))
ok(mapDoor.__valid == true, "полотно КАРТЫ уцелело")
ok(phantom.__valid == false, "рантайм-дубль снесён")
ok(farDoor.__valid == true, "нормальная дверь не тронута")

print("\n=== 3. ДВА ПОЛОТНА КАРТЫ НЕ СНОСЯТСЯ БЕЗ FORCE ===")
stub.reset()
local a = stub.makeDoor(0, 0, 0, { byMap = true, mapID = 1 })
local b = stub.makeDoor(0, 0, 0, { byMap = true, mapID = 2 })
D._canonicalDoorIDs = nil
D.RebuildDoorIdentityCache()
local softPurge = D.PurgeGhostDoors()
ok(softPurge == 0 and a.__valid and b.__valid, "по умолчанию геометрия карты не удаляется", tostring(softPurge))
local hardPurge = D.PurgeGhostDoors({ force = true })
ok(hardPurge == 1 and (a.__valid ~= b.__valid), "с force остаётся ровно одно полотно", tostring(hardPurge))

print("\n=== 4. РЕЖИМ ПРОВЕРКИ (dry) НИЧЕГО НЕ УДАЛЯЕТ ===")
stub.reset()
local keep = stub.makeDoor(0, 0, 0, { byMap = true, mapID = 5 })
local ghost = stub.makeDoor(0, 0, 0, { byMap = false })
D._canonicalDoorIDs = nil
D.RebuildDoorIdentityCache()
local found = D.PurgeGhostDoors({ dry = true })
ok(found == 1, "dry находит фантом")
ok(keep.__valid and ghost.__valid, "dry не удаляет ни одной двери")

print("\n=== 5. СЛОЖНОСТЬ: СРАВНЕНИЙ СИЛЬНО МЕНЬШЕ, ЧЕМ n^2 ===")
stub.reset()
local N = 300
for i = 1, N do stub.makeDoor(i * 200, 0, 0, { byMap = true, mapID = i }) end
local realSame = D.IsSamePhysicalDoor
local calls = 0
D.IsSamePhysicalDoor = function(x, y) calls = calls + 1 return realSame(x, y) end
D._canonicalDoorIDs = nil
D.RebuildDoorIdentityCache()
D.IsSamePhysicalDoor = realSame
local worst = N * (N - 1) / 2
ok(calls < worst / 10, ("сравнений %d при худшем случае %d (пространственный хэш работает)"):format(calls, worst))

print("\n=== 6. ГРУППА ИЗ ТРЁХ ПОЛОТЕН СХЛОПЫВАЕТСЯ ЦЕЛИКОМ ===")
stub.reset()
local m = stub.makeDoor(0, 0, 0, { byMap = true, mapID = 7 })
stub.makeDoor(1, 0, 0, { byMap = false })
stub.makeDoor(2, 1, 0, { byMap = false })
D._canonicalDoorIDs = nil
D.RebuildDoorIdentityCache()
ok(#D.GetEquivalentDoors(m) == 3, "все три полотна в одной группе", tostring(#D.GetEquivalentDoors(m)))
local killed = D.PurgeGhostDoors()
ok(killed == 2 and m.__valid, "снесены оба фантома, оригинал жив", tostring(killed))

print(("\nDOORS REBUILD v5: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
