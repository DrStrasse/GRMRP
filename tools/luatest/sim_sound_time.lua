--[[--------------------------------------------------------------------
    sim_sound_time — звуковой слой GRM.Sound и часы GRM.Time v2.

    Живой прогон в моке GMod + проверка, что все звуковые пути сборки
    зарегистрированы (иначе первый проигрыш = подгрузка с диска в кадре).

    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_sound_time.lua
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

-- Мок файловой системы: «есть» только стоковые пути, kom_hour отсутствует.
local present = {}
_G.file.Exists = function(path) return present[path] == true end
_G.util.PrecacheSound = function(p) _G.__precached = (_G.__precached or 0) + 1 end
_G.resource = { AddFile = function(p) _G.__resources = (_G.__resources or 0) + 1 end }
_G.RealTime = function() return stub.time or 0 end
local uiPlayed = {}
_G.surface.PlaySound = function(p) uiPlayed[#uiPlayed + 1] = p end

for _, p in ipairs({ "sound/buttons/button15.wav", "sound/buttons/button19.wav",
    "sound/ambient/alarms/warningbell1.wav", "sound/doors/door_latch1.wav" }) do present[p] = true end

print("\n=== 1. ЗВУКОВОЙ СЛОЙ ===")
stub.reset()
local loaded, err = stub.loadModule("lua/autorun/sh_07_grm_sound.lua")
ok(loaded, "модуль звука поднялся", err)
local S = _G.GRM and _G.GRM.Sound
ok(S and S.Version == "1.0.0", "версия 1.0.0")

ok(S.Exists("buttons/button15.wav") == true, "существующий файл распознан")
ok(S.Exists("kom_hour.wav") == false, "отсутствующий файл распознан")
ok(S.Resolve("buttons/button15.wav") == "buttons/button15.wav", "существующий путь возвращается как есть")
ok(S.Resolve("kom_hour.wav") == "ambient/alarms/warningbell1.wav",
    "отсутствующий kom_hour подменяется зарегистрированным фолбэком", S.Resolve("kom_hour.wav"))

-- предупреждение печатается ОДИН раз, а не на каждое воспроизведение
local warnedBefore = S._warned["kom_hour.wav"]
S.Resolve("kom_hour.wav") S.Resolve("kom_hour.wav")
ok(warnedBefore == true, "предупреждение об отсутствии пишется один раз")

-- Emit не падает и играет фолбэк
local emitted = {}
local ent = stub.makeEntity({ class = "prop_physics" })
ent.EmitSound = function(_, path) emitted[#emitted + 1] = path end
S.Emit(ent, "kom_hour.wav", 127, 110)
ok(emitted[1] == "ambient/alarms/warningbell1.wav", "Emit сыграл фолбэк вместо потока ошибок", emitted[1])

-- UI-антиспам (клиентская ветка)
_G.CLIENT, _G.SERVER = true, false
stub.time = 100
uiPlayed = {}
for _ = 1, 25 do S.UI("buttons/button15.wav") end
ok(#uiPlayed == 1, ("25 кликов за кадр = 1 звук (было %d)"):format(#uiPlayed))
stub.time = 101
S.UI("buttons/button15.wav")
ok(#uiPlayed == 2, "через кадр звук снова доступен")
_G.CLIENT, _G.SERVER = false, true

-- Зацикленные звуки: реестр и остановка по удалению носителя
local stops = 0
_G.CreateSound = function() return { Play = function() end, Stop = function() stops = stops + 1 end } end
local speaker = stub.makeEntity({ class = "grm_loudspeaker" })
S.Loop(speaker, "buttons/button15.wav")
S.Loop(speaker, "buttons/button15.wav")
ok(S._loops[speaker] ~= nil, "патч зацикленного звука попал в реестр")
_G.hook.Run("EntityRemoved", speaker)
ok(stops == 1 and S._loops[speaker] == nil, "при удалении носителя патч заглушён и вычищен", tostring(stops))

-- Прекэш
_G.__precached = 0
S._precached = nil
stub.runTimers()
ok((_G.__precached or 0) >= 4, ("прекэшированы существующие звуки: %d"):format(_G.__precached or 0))
local okCount, missing = S.Check()
ok(#missing > 0 and okCount >= 4, "Check() отчитывается о найденных и отсутствующих")

print("\n=== 2. ВСЕ ЗВУКИ СБОРКИ ЗАРЕГИСТРИРОВАНЫ ===")
local io_popen = io.popen("grep -rhoP '\"[^\"]*\\.(wav|mp3|ogg)\"' lua addons --include=*.lua | grep -v easychat | sort -u")
local used = {}
for line in io_popen:lines() do
    local path = line:match('^"(.*)"$')
    if path and path ~= ".wav" and not path:match("^sound/") then used[path] = true end
end
io_popen:close()
local unregistered = {}
for path in pairs(used) do
    if not S.Registry[path] then unregistered[#unregistered + 1] = path end
end
table.sort(unregistered)
ok(#unregistered == 0, ("все %d звуковых путей кода есть в реестре прекэша"):format(table.Count(used)),
    table.concat(unregistered, ", "))

print("\n=== 3. ПРИМЕНЕНИЕ ЗВУКОВОГО СЛОЯ ===")
local fixes = read("lua/autorun/sh_faction_fixes.lua")
ok(fixes:find('GRM.Sound.Emit(p, "kom_hour.wav"', 1, true) ~= nil, "комендантский час играет через защищённый слой")
ok(fixes:find('if file.Exists("sound/kom_hour.wav", "GAME") then', 1, true) ~= nil,
    "resource.AddFile для отсутствующего файла больше не вызывается")
local slide = read("lua/autorun/sh_grm_sliding_door.lua")
ok(slide:find("GRM.Sound.Emit(ent, soundMove", 1, true) ~= nil, "звуки раздвижных дверей идут через слой")
local addon = read("addons/grm_fire/lua/autorun/sh_grm_fire_addon.lua")
ok(addon:find('if file.Exists("materials/grm/firehose.vmt", "GAME") then', 1, true) ~= nil,
    "материал рукава раздаётся только при наличии файла")

print("\n=== 4. ЧАСЫ GRM.Time v2 ===")
stub.reset()
_G.GetGlobalInt = function(_, d) return _G.__epoch or d or 0 end
_G.SetGlobalInt = function(_, v) _G.__epoch = v end
_G.SetGlobalString = function() _G.__globalString = true end
_G.bit = { bor = function(a, b) return a end }
local loadedT, errT = stub.loadModule("lua/autorun/sh_grm_realtime.lua")
local T = _G.GRM and _G.GRM.Time
ok(loadedT and T and T.Version == "2.0.0", "часы v2.0.0 подняты", errT)
ok(_G.__globalString ~= true, "форматированная строка больше НЕ рассылается глобалом каждую секунду")
ok(T.SyncInterval >= 5, "эпоха синхронизируется не чаще раза в 5 секунд", tostring(T.SyncInterval))
ok(type(T.Clock) == "function", "есть общий кэш os.date — GRM.Time.Clock")

local calls = 0
local realDate = os.date
os.date = function(...) calls = calls + 1 return realDate(...) end
stub.time = 500
for _ = 1, 60 do T.Clock("%H:%M:%S") end
local firstBurst = calls
for _ = 1, 60 do T.GetString() end
os.date = realDate
ok(firstBurst <= 1, ("60 обращений к часам за кадр = %d вызовов os.date"):format(firstBurst))

local src = read("lua/autorun/sh_grm_realtime.lua")
-- отрезаем шапку-блок комментария, чтобы упоминание «раньше было
-- SetGlobalString» не считалось живым вызовом
local codeOnly = src:gsub("%-%-%[%[.-%]%]", "")
local liveSetGlobalString = false
for line in codeOnly:gmatch("[^\n]+") do
    local body = line:gsub("^%s+", "")
    if not body:match("^%-%-") and body:find("SetGlobalString", 1, true) then liveSetGlobalString = true end
end
ok(not liveSetGlobalString, "живого вызова SetGlobalString в часах не осталось")
ok(read("lua/autorun/client/cl_grm_customization.lua"):find("GRM.Time.Clock", 1, true) ~= nil,
    "часы на HUD кастомизации используют общий кэш")
ok(read("lua/autorun/sh_grm_911.lua"):find("nowEpoch", 1, true) ~= nil,
    "HUD 911 не зовёт os.time дважды на кадр")

print(("\nSOUND + TIME: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
