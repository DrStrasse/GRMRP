--[[--------------------------------------------------------------------
    sim_net_guard_watch — сторож новых серверных обработчиков.

    НАХОДКА АУДИТА 31.08 (п. 3.1). Из 357 серверных net.Receive через
    общий GRM.Net.Guard проходят только 53. Остальные защищаются вручную
    и по-разному: где-то IsSuperAdmin, где-то локальные inRange/rateOK,
    где-то проверка владельца.

    Сейчас это работает — критичные проверены глазами при аудите. Но
    каждый НОВЫЙ обработчик, написанный без единого правила, легко
    окажется голым: клиент шлёт пакет, сервер выполняет. Заметить такое
    можно только чтением кода, а его 568 файлов.

    ЧТО ДЕЛАЕТ ЭТОТ СТЕНД. Не требует переписывать 300 существующих
    мест — он фиксирует ТЕКУЩЕЕ состояние списком и падает, если
    появился НОВЫЙ обработчик без единого признака валидации.

    Правило простое: добавил серверный net.Receive — добавь проверку
    (права, владелец, дистанция или лимит частоты). Не можешь — впиши
    имя в ALLOWED ниже с объяснением, почему безопасно.

    Запуск: luajit tools/luatest/sim_net_guard_watch.lua
----------------------------------------------------------------------]]
local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

--[[ Признаки валидации. Список широкий намеренно: проверка часто живёт
     во вспомогательной функции (inRange, rateOK, canManage), и требовать
     именно Guard() значило бы завалить стенд ложными провалами. ]]
--[[ AD.Can( — центральный вход своей библиотеки прав GRM (с 03.09 единственный). ]]
local AUTH = "IsSuperAdmin\0IsAdmin(\0IsUserGroup\0Access.Can\0Guard(" ..
    "\0inRange(\0rateOK(\0DistToSqr\0Distance(\0hasAdminAccess" ..
    "\0AD.Can(\0IsListenServerHost\0GetOwner()\0OwnerKey\0CharacterKey(ply" ..
    "\0charKey(ply\0CurTime() <\0Cooldown\0cooldown\0_next\0NextUse"
local AUTH_LIST = {}
for piece in AUTH:gmatch("[^%z]+") do AUTH_LIST[#AUTH_LIST + 1] = piece end

local function hasAuth(body)
    for _, needle in ipairs(AUTH_LIST) do
        if body:find(needle, 1, true) then return true end
    end
    -- функции вида canDoSomething( / CanDoSomething(
    if body:find("[Cc]an%u%w*%s*%(") then return true end
    return false
end

local files = {}
do
    local p = io.popen("find lua addons -name '*.lua' | grep -v easychat | sort")
    for line in p:lines() do files[#files + 1] = line end
    p:close()
end

--[[ РАЗРЕШЁННЫЕ БЕЗ ЯВНОЙ ПРОВЕРКИ.

     Каждое имя здесь прочитано глазами при аудите 31.08. В основном это
     обработчики, которые только ОТВЕЧАЮТ данными самому спросившему
     (открыть своё меню, обновить свой список) — подделать такой пакет
     можно, но получишь ты только собственные данные.

     Добавляя сюда новое имя, объясни в комментарии, почему безопасно. ]]
local ALLOWED = {}

local naked, seen = {}, {}
for _, path in ipairs(files) do
    local fh = io.open(path, "rb")
    if fh then
        local src = fh:read("*a") fh:close()
        for m, args in src:gmatch("net%.Receive%(%s*([^,]-),%s*function%s*%(([^)]*)%)") do
            local n = 0
            for a in args:gmatch("[^,]+") do
                if a:match("%S") then n = n + 1 end
            end
            if n >= 2 then                       -- серверный: есть игрок
                local at = src:find("net.Receive(" .. m, 1, true)
                local body = ""
                if at then
                    local nxt = src:find("net.Receive", at + 20, true)
                    body = src:sub(at, nxt or math.min(#src, at + 4000))
                end
                if not hasAuth(body) then
                    local key = path .. "|" .. m
                    if not seen[key] and not ALLOWED[m] then
                        seen[key] = true
                        naked[#naked + 1] = key
                    end
                end
            end
        end
    end
end
table.sort(naked)

print(("\n=== СЕРВЕРНЫЕ ОБРАБОТЧИКИ БЕЗ ПРИЗНАКОВ ВАЛИДАЦИИ ==="))
print(("  найдено: %d"):format(#naked))

--[[ ПОРОГ. Это «замок на будущее», а не требование переписать всё
     наследие разом. Число зафиксировано по состоянию на 31.08: стенд
     падает, если оно ВЫРОСЛО, то есть появился новый голый обработчик.

     Уменьшать порог при каждой правке — правильно и приветствуется. ]]
local BASELINE = 97

ok(#naked <= BASELINE,
    ("новых незащищённых обработчиков не появилось (порог %d)"):format(BASELINE),
    #naked > BASELINE and ("стало %d, добавились:\n     %s"):format(
        #naked, table.concat(naked, "\n     ")) or nil)

if #naked < BASELINE then
    print(("  (порог можно опустить до %d — стало чище)"):format(#naked))
end

print("\n=== ЯДРО ЗАЩИТЫ НА МЕСТЕ ===")
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end
local netcore = read("lua/autorun/sh_04_grm_net.lua")
ok(netcore:find("function N.Guard", 1, true) ~= nil, "GRM.Net.Guard существует")
ok(netcore:find("rate_limited", 1, true) ~= nil, "в нём есть лимит частоты")
ok(netcore:find("payload_too_large", 1, true) ~= nil, "и предел размера пакета")
ok(netcore:find("too_far", 1, true) ~= nil, "и проверка дистанции")
ok(netcore:find("capability", 1, true) ~= nil, "и проверка прав")

print(("\nNET GUARD WATCH: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
