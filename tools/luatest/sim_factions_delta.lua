--[[--------------------------------------------------------------------
    sim_factions_delta — дельта-синк организаций: вместо полного снимка
    (45 КБ одним пакетом) сервер шлёт только изменившиеся организации и
    только тем, кому они нужны.

    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_factions_delta.lua
----------------------------------------------------------------------]]
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

local s = read("lua/autorun/sh_factions.lua")

print("\n=== 1. КАНАЛ ===")
ok(s:find('local NET_SYNC_DELTA          = "Factions_SyncDelta"', 1, true) ~= nil, "своя net-строка для дельты")
ok(s:find("util.AddNetworkString(NET_SYNC_DELTA)", 1, true) ~= nil, "строка зарегистрирована")
ok(s:find("net.Receive(NET_SYNC_DELTA, function()", 1, true) ~= nil, "клиент принимает дельту")
ok(s:find("net.Receive(NET_SYNC_ALL, function()", 1, true) ~= nil,
    "полный снимок остался — он нужен при заходе игрока")

print("\n=== 2. ЧТО ИМЕННО ШЛЁТСЯ ===")
ok(s:find("local syncHashes, publicHashes = {}, {}", 1, true) ~= nil,
    "контрольные суммы состояния по каждой организации")
ok(s:find("if syncHashes[name] ~= crc then", 1, true) ~= nil, "шлём только изменившиеся организации")
ok(s:find("removed[#removed + 1] = name", 1, true) ~= nil, "удалённые организации тоже уходят дельтой")
ok(s:find("local pub = {", 1, true) ~= nil and s:find("DisplayName = row.DisplayName, Tag = row.Tag, Color = row.Color", 1, true) ~= nil,
    "для посторонних формируется публичная часть: название, тэг, цвет")
ok(s:find("if publicHashes[name] ~= crcP then", 1, true) ~= nil,
    "публичная часть шлётся, только если изменилась именно она")

print("\n=== 3. КОМУ ШЛЁТСЯ ===")
ok(s:find("local wantsFull = everyoneFull or ply:IsSuperAdmin()", 1, true) ~= nil,
    "полные данные — суперадминам")
ok(s:find('if own ~= "" and changedFull[own] then wantsFull = true end', 1, true) ~= nil,
    "и членам изменившейся организации")
ok(s:find("net.Send(fullTargets)", 1, true) ~= nil and s:find("net.Send(publicTargets)", 1, true) ~= nil,
    "две адресные рассылки вместо Broadcast")
ok(s:find("net.Broadcast()", 1, true) == nil or s:find("NET_SYNC_ALL)\n        net.WriteTable(buildSyncData())\n        net.Broadcast()", 1, true) == nil,
    "полный снимок больше не рассылается всем при каждом изменении")
ok(s:find('CreateConVar("grm_factions_public_full", "0"', 1, true) ~= nil,
    "есть аварийный конвар: вернуть прежнее поведение одной командой")

print("\n=== 4. КЛИЕНТ ===")
ok(s:find('if mode == "public" then', 1, true) ~= nil, "публичная дельта мержится, а не затирает состав")
ok(s:find("FactionsData[name] = row", 1, true) ~= nil, "полная дельта заменяет запись целиком")
ok(s:find("for _, name in ipairs(istable(payload.removed)", 1, true) ~= nil, "удаление применяется")
ok(s:find("FactionsData = installClientFactionAliases(FactionsData)", 1, true) ~= nil,
    "алиасы ключей участников проставляются и после дельты")
ok(s:find('hook.Run("GRM_FactionUIRefreshed", FactionsData)', 1, true) ~= nil,
    "интерфейсы обновляются тем же хуком, что и раньше")

print("\n=== 5. НИЧЕГО НЕ СЛОМАНО ===")
ok(s:find("sendCharacterChoices()", 1, true) ~= nil, "выбор персонажей по-прежнему уходит")
ok(s:find("function broadcastFactionData()", 1, true) ~= nil, "внешний контракт broadcastFactionData сохранён")
ok(s:find("if not anyFull and #removed == 0 then", 1, true) ~= nil,
    "если ничего не изменилось — сеть не трогаем вовсе")

print("\n=== 6. ПОТОКОВАЯ ОТПРАВКА ЧАСТЯМИ ===")
local net_ = read("lua/autorun/sh_04_grm_net.lua")
local fixes = read("lua/autorun/sh_faction_fixes.lua")
ok(net_:find("function N.Stream", 1, true) ~= nil, "есть потоковая отправка больших таблиц")
ok(net_:find("function N.Receive", 1, true) ~= nil, "и приём с обратной сборкой")
ok(net_:find("util.Compress(encoded)", 1, true) ~= nil, "данные сжимаются перед нарезкой")
ok(net_:find("local chunkSize = math.Clamp(math.floor(tonumber(opts.chunk) or 8192), 1024, 32768)", 1, true) ~= nil,
    "размер куска ограничен и настраивается")
ok(net_:find("timer.Simple(interval * index", 1, true) ~= nil, "куски уходят последовательно, а не залпом")
ok(net_:find("if #list > 0 and #alive == 0 then return end", 1, true) ~= nil,
    "если получатели вышли — поток прекращается")
ok(s:find('GRM.Net.Stream("factions.full"', 1, true) ~= nil, "полный снимок организаций идёт частями")
ok(s:find('GRM.Net.Receive("factions.full"', 1, true) ~= nil, "клиент собирает снимок обратно")
ok(fixes:find('GRM.Net.Stream("factions.ext"', 1, true) ~= nil, "расширенные настройки тоже частями")
ok(fixes:find('GRM.Net.Receive("factions.ext"', 1, true) ~= nil, "и собираются на клиенте")
ok(s:find("net.Start(NET_SEND_DATA)", 1, true) ~= nil, "старый одноразовый путь остался фолбэком")

print(("\nFACTIONS DELTA: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
