--[[--------------------------------------------------------------------
    sim_forward_locals — защита от бага «локальная функция используется
    раньше своего объявления».

    ПОЧЕМУ ЭТО ВАЖНО. В Lua имя, встреченное до `local`-объявления,
    компилируется как ОБРАЩЕНИЕ К ГЛОБАЛУ. Файл при этом грузится без
    единой ошибки, а падает уже в бою — при первом же вызове:

        attempt to call global 'handleCurfewChat' (a nil value)

    Именно так упал комендантский час в EasyChat, и такой же скрытый баг
    нашёлся ещё в четырёх местах (синк фракций при заходе игрока,
    автозакрытие fading-двери в двух файлах, подсчёт чипов телефона).
    Лечится форвард-декларацией: `local X` выше, `X = function(...)` ниже.

    Стенд разбирает исходники (без комментариев и строк) и падает, если
    такой паттерн появился снова.

    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_forward_locals.lua
----------------------------------------------------------------------]]
local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

-- Список файлов сборки (без EasyChat — это внешний аддон).
local files = {}
do
    local p = io.popen("find lua addons -name '*.lua' | grep -v easychat | sort")
    for line in p:lines() do files[#files + 1] = line end
    p:close()
end

-- Вырезаем комментарии и строковые литералы: иначе упоминание имени в
-- шапке файла считается «использованием».
local function stripNoise(src)
    src = src:gsub("%-%-%[%[.-%]%]", " ")          -- блочные комментарии
    src = src:gsub("%[%[.-%]%]", " ")              -- длинные строки
    local out = {}
    for line in (src .. "\n"):gmatch("([^\n]*)\n") do
        line = line:gsub("%-%-.*$", "")            -- строчные комментарии
        line = line:gsub('"[^"]*"', '""')          -- строки в кавычках
        line = line:gsub("'[^']*'", "''")
        out[#out + 1] = line
    end
    return out
end

local problems = {}
for _, path in ipairs(files) do
    local lines = stripNoise(read(path))

    -- Объявления local-функций и их первое появление в коде.
    local declared = {}
    for i, line in ipairs(lines) do
        local name = line:match("^%s*local function ([A-Za-z_][%w_]*)")
        if name and not declared[name] then declared[name] = i end
        local fwd = line:match("^%s*local ([A-Za-z_][%w_]*)%s*$")
        if fwd and not declared[fwd] then declared[fwd] = i end
        local assigned = line:match("^%s*local ([A-Za-z_][%w_]*)%s*=")
        if assigned and not declared[assigned] then declared[assigned] = i end
    end

    for name, declLine in pairs(declared) do
        if #name >= 4 then
            for i = 1, declLine - 1 do
                -- вызов имени: name( ... ), но не method:name( ) и не table.name( )
                if lines[i]:find("[^%w_%.:]" .. name .. "%s*%(") or lines[i]:find("^" .. name .. "%s*%(") then
                    problems[#problems + 1] = ("%s:%d использует '%s', объявленную только на строке %d")
                        :format(path, i, name, declLine)
                    break
                end
            end
        end
    end
end

print("\n=== ПРОВЕРКА ПОРЯДКА ОБЪЯВЛЕНИЙ ===")
print(("  просмотрено файлов: %d"):format(#files))
ok(#problems == 0, "нет обращений к local-функциям до их объявления",
    #problems > 0 and ("\n     " .. table.concat(problems, "\n     ")) or nil)

print("\n=== ТОЧКИ, ГДЕ ЭТО УЖЕ ЛОВИЛОСЬ ===")
local fixes = read("lua/autorun/sh_faction_fixes.lua")
ok(fixes:find("local handleCurfewChat", 1, true) ~= nil and fixes:find("handleCurfewChat = function", 1, true) ~= nil,
    "комендантский час: форвард-декларация на месте")
local factions = read("lua/autorun/sh_factions.lua")
ok(factions:find("local sendFactionDataTo", 1, true) ~= nil and factions:find("sendFactionDataTo = function", 1, true) ~= nil,
    "синк фракций при заходе игрока: форвард-декларация на месте")
local ffd = read("lua/autorun/sh_grm_ffdlink.lua")
ok(ffd:find("local fadeOff", 1, true) ~= nil and ffd:find("fadeOff = function", 1, true) ~= nil,
    "автозакрытие fading-двери (FFD Link): форвард-декларация на месте")
local tool = read("lua/weapons/gmod_tool/stools/ffd_fading_door.lua")
ok(tool:find("local fadeOff", 1, true) ~= nil and tool:find("fadeOff = function", 1, true) ~= nil,
    "автозакрытие fading-двери (тулза): форвард-декларация на месте")
local mobile = read("lua/autorun/sh_grm_mobile.lua")
ok(mobile:find("local tierRank", 1, true) ~= nil and mobile:find("tierRank = function", 1, true) ~= nil,
    "подсчёт чипов телефона: форвард-декларация на месте")
--[[ Старый цех держал на каждую работу отдельный timer.Create и снимал его
     по имени, вычисленному функцией qteTimerName(ent). Новый цех таймеров
     на работу не создаёт вовсе: задачи живут в I.Jobs и их крутит один
     общий тик. Проверяем именно это — отсутствие таймеров на работу. ]]
local industry = read("lua/autorun/server/sv_grm_industry.lua")
-- Считаем только вызовы: слово timer.Create встречается и в комментарии.
local timerCount = select(2, industry:gsub("timer%.Create%(", ""))
ok(timerCount == 2, "в цехе ровно два общих таймера (тик задач и сырьё), не по таймеру на работу",
    timerCount)
ok(industry:find('timer.Remove', 1, true) == nil,
    "снимать таймер по вычисленному имени больше не нужно — задач как таймеров нет")
ok(industry:find("I.Jobs[job.id] = job", 1, true) ~= nil
    and industry:find("I.Jobs[job.id] = nil", 1, true) ~= nil,
    "задача регистрируется и снимается как объект, а не как таймер")

print(("\nFORWARD LOCALS: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
