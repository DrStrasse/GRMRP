--[[ Живой прогон шрифтов интерфейса (заказ владельца 27.08).

     Симптом в консоли:
        SetFontInternal: font doesn't exist (GRMSocEd_Small)
        2. openStudio - sh_grm_social_studio.lua:653

     Причина: в модуле объявлены только GRMSocEd_H и GRMSocEd_B, а метка
     статуса просила несуществующий GRMSocEd_Small. Lua такую опечатку не
     ловит — она всплывает уже у игрока при открытии окна.

     Этот стенд проверяет ВСЕ файлы репозитория: каждый шрифт, который
     где-то запрашивается, должен быть где-то создан.

     Запуск: luajit tools/luatest/sim_fonts_declared.lua ]]
local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

--[[ Штатные шрифты GMod и Derma: их создаёт движок, объявлять не нужно. ]]
local STOCK = {
    DermaDefault = true, DermaDefaultBold = true, DermaLarge = true,
    Default = true, DefaultBold = true, DefaultSmall = true, DefaultFixed = true,
    DefaultFixedDropShadow = true, Trebuchet18 = true, Trebuchet24 = true,
    ChatFont = true, TargetID = true, TargetIDSmall = true, Marlett = true,
    HudHintTextLarge = true, HudHintTextSmall = true, HudSelectionText = true,
    CloseCaption_Normal = true, BudgetLabel = true, MenuLarge = true,
    GModNotify = true, GModToolName = true, GModToolSubtitle = true,
    DebugOverlay = true, HUDNumber = true, HUDNumber5 = true,
}

--- Собираем объявленные и запрошенные шрифты по всему дереву lua/.
local created, used = {}, {}

local pipe = io.popen("find lua -name '*.lua' | sort")
local files = 0
for path in pipe:lines() do
    files = files + 1
    local fh = io.open(path, "rb")
    if fh then
        local src = fh:read("*a")
        fh:close()

        -- Объявления: surface.CreateFont("Имя", …)
        for name in src:gmatch('CreateFont%s*%(%s*"([^"]+)"') do created[name] = true end
        --[[ Объявления в цикле: HUD и тема UI создают шрифты пачкой из
             таблицы, поэтому имя в CreateFont — переменная. Такие имена
             собираем из самих таблиц. ]]
        for name in src:gmatch('{%s*"(GRM[%w_]+)"%s*,%s*%d+') do created[name] = true end
        for prefix in src:gmatch('CreateFont%s*%(%s*"([%w_]+)"%s*%.%.') do
            created["__prefix:" .. prefix] = true
        end

        -- Запросы: SetFont("Имя") и draw.SimpleText(текст, "Имя", …)
        for name in src:gmatch('SetFont%s*%(%s*"([^"]+)"') do
            used[name] = used[name] or {}
            used[name][path] = true
        end
        for name in src:gmatch('draw%.SimpleText%b()') do
            local font = name:match('^draw%.SimpleText%(.-,%s*"([^"]+)"')
            if font then
                used[font] = used[font] or {}
                used[font][path] = true
            end
        end
    end
end
pipe:close()

--- Шрифт объявлен, если создан явно или подходит под собранный в цикле префикс.
local function isDeclared(name)
    if created[name] or STOCK[name] then return true end
    for key in pairs(created) do
        local prefix = key:match("^__prefix:(.+)$")
        if prefix and name:sub(1, #prefix) == prefix then return true end
    end
    return false
end

print("\n=== 1. КОНКРЕТНЫЙ СЛУЧАЙ ИЗ ОТЧЁТА ===")
local function body(path)
    local fh = io.open(path, "rb") if not fh then return "" end
    local t = fh:read("*a") fh:close() return t
end
local studio = body("lua/autorun/sh_grm_social_studio.lua")
ok(studio:find('SetFont("GRMSocEd_Small")', 1, true) == nil,
   "студия анимаций больше не просит несуществующий GRMSocEd_Small")
ok(studio:find('statusL:SetFont("GRMSocEd_B")', 1, true) ~= nil,
   "метка статуса использует объявленный шрифт")
ok(studio:find('CreateFont("GRMSocEd_B"', 1, true) ~= nil, "и этот шрифт действительно создаётся")

local docs = body("lua/autorun/sh_grm_documents.lua")
ok(docs:find('"GRMDoc_Title"', 1, true) == nil,
   "та же опечатка в документах исправлена (GRMDoc_Title не создавался)")
ok(docs:find('CreateFont("GRMDoc_CoverTitle"', 1, true) ~= nil,
   "используется объявленный GRMDoc_CoverTitle")

print("\n=== 2. СПЛОШНАЯ ПРОВЕРКА ВСЕХ ФАЙЛОВ ===")
local missing = {}
for name, where in pairs(used) do
    -- Пропускаем строки, которые попали в выборку как текст, а не имя шрифта:
    -- имена шрифтов не содержат пробелов, запятых и кириллицы.
    local looksLikeFont = name:match("^[%w_]+$") ~= nil
    if looksLikeFont and not isDeclared(name) then
        local list = {}
        for f in pairs(where) do list[#list + 1] = f end
        table.sort(list)
        missing[#missing + 1] = name .. "  →  " .. table.concat(list, ", ")
    end
end
table.sort(missing)
for _, line in ipairs(missing) do print("       " .. line) end
ok(#missing == 0, "во всём репозитории нет запросов к необъявленным шрифтам",
   #missing > 0 and (#missing .. " шт.") or nil)

print(("\n   просмотрено файлов: %d, объявлено шрифтов: %d"):format(files,
    (function() local n = 0 for k in pairs(created) do if not k:match("^__prefix:") then n = n + 1 end end return n end)()))

print(("\n=== ИТОГ: успешно %d, провалено %d ===\n"):format(pass, fail))
if fail > 0 then os.exit(1) end
