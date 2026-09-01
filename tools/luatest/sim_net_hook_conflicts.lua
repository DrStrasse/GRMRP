--[[--------------------------------------------------------------------
    sim_net_hook_conflicts — два обработчика на одно сообщение.

    ПОЧЕМУ ЭТО ОПАСНО. net.Receive("X", f) не добавляет обработчик в
    список — он ЗАМЕНЯЕТ предыдущий. Если два наших файла принимают одно
    и то же сообщение в одном realm, работать будет ровно один, и какой
    именно — решает АЛФАВИТНЫЙ порядок загрузки autorun. Переименуй файл
    (или добавь новый на «z») — и поведение сервера меняется само собой,
    без единой правки логики.

    Так и было найдено:
      * GRM_Quest_AdminOpen принимали и cl_grm_quests (старое вкладочное
        окно), и zz_grm_quest_studio (узловой граф). Побеждал zz_ просто
        потому, что «z» позже «c»;
      * GRM_AugChip_Sync принимали cl_grm_augmentation_interface и
        cl_grm_augmentations_hud. Побеждал hud, а вариант interface не
        выставлял LastUpdate — при другом порядке имён HUD перестал бы
        видеть свежесть данных.

    ЧТО СЧИТАЕТСЯ НОРМОЙ:
      * одно имя в SERVER-файле и в CLIENT-файле — это разные машины;
      * осознанная замена через hook.Remove(...) прямо перед hook.Add(...)
        — так zz_grm_bleedout заменяет обработчик урона из sh_grm_911;
      * защита флагом (`if not GRM._tabBalRcv then`) — так сделано в
        валюте и еде.

    Запуск: luajit tools/luatest/sim_net_hook_conflicts.lua
----------------------------------------------------------------------]]
local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

local files = {}
do
    local p = io.popen("find lua addons -name '*.lua' | grep -v easychat | sort")
    for line in p:lines() do files[#files + 1] = line end
    p:close()
end

--- Realm файла: по каталогу и по ранним `if CLIENT/SERVER then return end`.
local function realmOf(path, src)
    if path:find("/client/", 1, true) or path:find("cl_", 1, true) then return "client" end
    if path:find("/server/", 1, true) or path:find("sv_", 1, true) then return "server" end
    local head = src:sub(1, 2000)
    if head:find("if CLIENT then return end", 1, true) then return "server" end
    if head:find("if not SERVER then return end", 1, true) then return "server" end
    if head:find("if SERVER then return end", 1, true) then return "client" end
    if head:find("if not CLIENT then return end", 1, true) then return "client" end
    return "shared"
end

--- Строки файла без комментариев: упоминание net.Receive в пояснении
--- не должно считаться живым обработчиком (наступали на это).
local function codeLines(src)
    local out, inBlock = {}, false
    for line in (src .. "\n"):gmatch("([^\n]*)\n") do
        local code = line
        if inBlock then
            local close = code:find("]]", 1, true)
            if close then inBlock = false code = code:sub(close + 2) else code = "" end
        end
        local blockAt = code:find("%-%-%[%[")
        if blockAt then
            local rest = code:sub(blockAt)
            if not rest:find("]]", 1, true) then inBlock = true end
            code = code:sub(1, blockAt - 1)
        end
        out[#out + 1] = code:gsub("%-%-.*$", "")
    end
    return out
end

print("\n=== 1. NET.RECEIVE: ОДНО СООБЩЕНИЕ — ОДИН ПРИЁМНИК В REALM ===")

local receivers = {}
for _, path in ipairs(files) do
    local src = read(path)
    local realm = realmOf(path, src)
    local lines = codeLines(src)
    local guarded = src:find("GRM%._%w+Rcv") ~= nil or src:find("_balRcv", 1, true) ~= nil
    for i, line in ipairs(lines) do
        local msg = line:match('net%.Receive%(%s*"([^"]+)"')
        if msg then
            receivers[msg] = receivers[msg] or {}
            table.insert(receivers[msg], { path = path, realm = realm, line = i, guarded = guarded })
        end
    end
end

local clashes = {}
for msg, list in pairs(receivers) do
    -- группируем по realm; shared считаем совместимым и с client, и с server
    local byRealm = {}
    for _, r in ipairs(list) do
        local key = r.realm
        byRealm[key] = byRealm[key] or {}
        table.insert(byRealm[key], r)
    end
    for realm, group in pairs(byRealm) do
        local files_seen, unguarded = {}, 0
        for _, r in ipairs(group) do
            if not files_seen[r.path] then
                files_seen[r.path] = true
                if not r.guarded then unguarded = unguarded + 1 end
            end
        end
        if unguarded > 1 then
            local where = {}
            for _, r in ipairs(group) do where[#where + 1] = r.path .. ":" .. r.line end
            clashes[#clashes + 1] = ("%s [%s]: %s"):format(msg, realm, table.concat(where, ", "))
        end
    end
end
table.sort(clashes)
ok(#clashes == 0, "нет сообщений с двумя незащищёнными приёмниками",
    #clashes > 0 and ("\n     " .. table.concat(clashes, "\n     ")) or nil)

print("\n=== 2. ХУКИ: ОДНА ПАРА (СОБЫТИЕ, ИМЯ) — ОДИН ВЛАДЕЛЕЦ ===")
-- Такая же ловушка: hook.Add с уже занятым именем заменяет обработчик.
-- Допустимо только явное hook.Remove тем же именем перед добавлением.
local hooks = {}
for _, path in ipairs(files) do
    local lines = codeLines(read(path))
    local removed = {}
    for i, line in ipairs(lines) do
        local ev, nm = line:match('hook%.Remove%(%s*"([^"]+)"%s*,%s*"([^"]+)"')
        if ev then removed[ev .. "\0" .. nm] = true end
        local ev2, nm2 = line:match('hook%.Add%(%s*"([^"]+)"%s*,%s*"([^"]+)"')
        if ev2 then
            local key = ev2 .. "\0" .. nm2
            hooks[key] = hooks[key] or {}
            table.insert(hooks[key], { path = path, line = i, replaces = removed[key] == true })
        end
    end
end

local hookClashes = {}
for key, list in pairs(hooks) do
    local files_seen, plain = {}, 0
    for _, h in ipairs(list) do
        if not files_seen[h.path] then
            files_seen[h.path] = true
            if not h.replaces then plain = plain + 1 end
        end
    end
    if plain > 1 then
        local ev, nm = key:match("^(.-)%z(.*)$")
        local where = {}
        for _, h in ipairs(list) do where[#where + 1] = h.path .. ":" .. h.line end
        hookClashes[#hookClashes + 1] = ("%s / %s: %s"):format(ev, nm, table.concat(where, ", "))
    end
end
table.sort(hookClashes)
ok(#hookClashes == 0, "нет хуков с двумя владельцами без hook.Remove",
    #hookClashes > 0 and ("\n     " .. table.concat(hookClashes, "\n     ")) or nil)

print("\n=== 3. КОНКРЕТНЫЕ НАХОДКИ ===")

local quests = read("lua/autorun/client/cl_grm_quests.lua")
local studio = read("lua/autorun/client/zz_grm_quest_studio.lua")
ok(quests:find('net.Receive("GRM_Quest_AdminOpen"', 1, true) ~= nil,
    "квесты: приём открытия редактора — в cl_grm_quests")
ok(studio:find('net.Receive("GRM_Quest_AdminOpen"', 1, true) == nil,
    "квесты: студия больше не перехватывает то же сообщение")
ok(quests:find("if Q.OpenGraphStudio then return Q.OpenGraphStudio(data) end", 1, true) ~= nil,
    "квесты: узловой редактор выбирается ЯВНО, а не порядком загрузки файлов")

local augUI = read("lua/autorun/client/cl_grm_augmentation_interface.lua")
local augHUD = read("lua/autorun/client/cl_grm_augmentations_hud.lua")
ok(augUI:find('net.Receive("GRM_AugChip_Sync"', 1, true) == nil,
    "аугментации: окно не перехватывает синхронизацию чипов")
ok(augHUD:find('net.Receive("GRM_AugChip_Sync"', 1, true) ~= nil,
    "аугментации: единственный приёмник — HUD")
ok(augUI:find('hook.Add("GRM_AugmentationStateUpdated"', 1, true) ~= nil,
    "аугментации: окно обновляется по хуку, который шлёт HUD")

local bleed = read("lua/autorun/zz_grm_bleedout.lua")
ok(bleed:find('hook.Remove("EntityTakeDamage", "GRM_911_Damage")', 1, true) ~= nil,
    "кровотечение: замена обработчика урона 911 объявлена явно")

print(("\nNET/HOOK CONFLICTS: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
