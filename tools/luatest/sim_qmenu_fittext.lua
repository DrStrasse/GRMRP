--[[ Регрессионный стенд: fitText — обрезка подписи инструмента.

     ГДЕ ЭТО РАБОТАЕТ. Строка списка инструментов рисует подпись через
     fitText прямо в row.Paint, то есть ДЛЯ КАЖДОЙ строки КАЖДЫЙ кадр.
     Подпись берётся из language.GetPhrase("tool.<id>.name"), то есть
     приходит из ЧУЖИХ аддонов — её кодировку мы не контролируем.

     ОТКАЗ, который ловим. Цикл сокращения полагался на то, что
     GRM.Utf8Sub обязательно укоротит строку:

         while #cut > 1 do
             cut = GRM.Utf8Sub(cut, GRM.Utf8Len(cut) - 1)
             ...
         end

     Для корректного UTF-8 это так. Но для строки в CP1251 или с
     оборванным символом Utf8Sub возвращает ЕЁ ЖЕ: длина не убывает,
     условие `#cut > 1` навсегда истинно. Клиент встаёт намертво без
     ошибки Lua — ровно то, что видел игрок (консоль пуста).

     Важно: под LuaJIT (наш стенд) библиотеки utf8 нет, под GMod — есть,
     и поведение Utf8Sub на битой строке отличается. Поэтому стенд гоняет
     ОБА окружения: и с utf8, и без него. Фикс обязан держать оба. ]]

local total, fails = 0, 0
local function check(name, ok, extra)
    total = total + 1
    if ok then print("  OK   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. (extra and ("  → " .. tostring(extra)) or "")) end
end

local function isstring(x) return type(x) == "string" end
local function isnumber(x) return type(x) == "number" end
local function istable(x)  return type(x) == "table"  end
local function isfunction(x) return type(x) == "function" end

--[[ Эмуляция utf8.len/utf8.offset из Lua 5.3 — такая библиотека ЕСТЬ в
     Garry's Mod и ОТСУТСТВУЕТ в LuaJIT. Нужна, чтобы проверить поведение
     кода именно так, как он поведёт себя в игре. ]]
local function makeUtf8()
    local u = {}
    local function iscont(b) return b and b >= 128 and b < 192 end
    function u.len(s)
        local i, n = 1, 0
        while i <= #s do
            local b = s:byte(i)
            local size = (b < 128 and 1) or (b < 194 and -1) or (b < 224 and 2)
                      or (b < 240 and 3) or (b < 245 and 4) or -1
            if size < 0 then return nil, i end
            for k = 1, size - 1 do
                if not iscont(s:byte(i + k)) then return nil, i end
            end
            i = i + size ; n = n + 1
        end
        return n
    end
    function u.offset(s, n)
        local i = 1
        if iscont(s:byte(i)) then return nil end
        n = n - 1
        while n > 0 and i <= #s do
            i = i + 1
            while iscont(s:byte(i)) do i = i + 1 end
            n = n - 1
        end
        if n > 0 then return nil end
        return i
    end
    return u
end

-- загрузка UTF-8 хелперов проекта при заданном окружении utf8
local function loadHelpers(withUtf8)
    _G.utf8 = withUtf8 and makeUtf8() or nil
    _G.GRM = {}
    local f = loadfile("lua/autorun/sh_00_grm_ui.lua") or loadfile("../../lua/autorun/sh_00_grm_ui.lua")
    if not f then return nil end
    f()
    return _G.GRM
end

-- «шрифт»: ширина = 7 px на байт; сокращать придётся всерьёз
local surfaceStub = {
    SetFont = function() end,
    GetTextSize = function(t) return #t * 7, 14 end,
}

--[[ СТАРЫЙ fitText — как было в 0cc9b99. Считаем итерации: если их
     больше предела, значит в игре это вечный цикл. ]]
local function fitOld(GRM, txt, maxW, budget)
    local surface = surfaceStub
    surface.SetFont("f")
    local w = select(1, surface.GetTextSize(txt))
    if not isnumber(w) or w <= maxW then return txt, 0 end
    local cut, iter = txt, 0
    while #cut > 1 do
        iter = iter + 1
        if iter > budget then return nil, iter end        -- ЗАВИС
        cut = (GRM and GRM.Utf8Sub) and GRM.Utf8Sub(cut, (GRM.Utf8Len(cut) - 1))
              or string.sub(cut, 1, #cut - 1)
        local ww = select(1, surface.GetTextSize(cut .. "…"))
        if not isnumber(ww) or ww <= maxW then return cut .. "…", iter end
    end
    return txt, iter
end

--[[ НОВЫЙ fitText — копия логики из sh_grm_qmenu.lua: гарантированный
     прогресс (откат на побайтовую обрезку) + предел итераций + кеш. ]]
local function makeFitNew(GRM)
    local cache, calls = {}, { size = 0 }
    local function fit(txt, font, maxW, budget)
        txt = tostring(txt or "")
        local surface = surfaceStub
        maxW = isnumber(maxW) and maxW or 0
        if maxW <= 8 then return "" , 0 end
        local key = txt .. "|" .. tostring(font) .. "|" .. math.floor(maxW)
        if cache[key] ~= nil then return cache[key], -1 end   -- -1 = взято из кеша
        surface.SetFont(font)
        local w = select(1, surface.GetTextSize(txt))
        if not isnumber(w) or w <= maxW then cache[key] = txt return txt, 0 end
        local cut, out, guard = txt, txt, 0
        while #cut > 1 do
            guard = guard + 1
            if guard > 256 then break end
            if budget and guard > budget then return nil, guard end
            local prevLen = #cut
            local nxt
            if GRM and isfunction(GRM.Utf8Sub) and isfunction(GRM.Utf8Len) then
                nxt = GRM.Utf8Sub(cut, GRM.Utf8Len(cut) - 1)
            end
            if not isstring(nxt) or #nxt >= prevLen then
                nxt = string.sub(cut, 1, prevLen - 1)
            end
            cut = nxt
            local ww = select(1, surface.GetTextSize(cut .. "…"))
            if not isnumber(ww) or ww <= maxW then
                out = cut .. "…" cache[key] = out return out, guard
            end
        end
        cache[key] = out
        return out, guard
    end
    return fit, cache
end

-- подписи, которые реально могут прийти из чужих аддонов
local CASES = {
    { "UTF-8 «Источник света»", "Источник света" },
    { "CP1251 «Цвет»",          string.char(0xC6, 0xE2, 0xE5, 0xF2) },
    { "CP1251 длинная",         string.char(0xC8,0xF1,0xF2,0xEE,0xF7,0xED,0xE8,0xEA,0x20,0xF1,0xE2,0xE5,0xF2,0xE0) },
    { "оборванный хвост",       "Цвет" .. string.char(0xD0) },
    { "одиночный ведущий байт", string.char(0xD0, 0xD0, 0xD0, 0xD0) },
    { "ASCII Adv. Duplicator",  "Adv. Duplicator 2" },
}

for _, env in ipairs({ { "БЕЗ utf8 (LuaJIT)", false }, { "С utf8 (как в GMod)", true } }) do
    local envName, withUtf8 = env[1], env[2]
    local GRM = loadHelpers(withUtf8)
    if not GRM then
        check("загрузка sh_00_grm_ui.lua (" .. envName .. ")", false, "файл не найден")
        break
    end

    print("\n=== ОКРУЖЕНИЕ: " .. envName .. " ===")
    local fitNew = makeFitNew(GRM)

    -- сначала показываем, что старый код где-то вис
    local hungOld = 0
    for _, c in ipairs(CASES) do
        local r = fitOld(GRM, c[2], 30, 400)
        if r == nil then hungOld = hungOld + 1 end
    end
    print(("  (старый код завис на %d из %d подписей)"):format(hungOld, #CASES))

    -- главное требование: новый код завершается ВСЕГДА
    for _, c in ipairs(CASES) do
        local name, s = c[1], c[2]
        local okAll = true
        local why
        for _, maxW in ipairs({ 200, 60, 30, 20, 12, 9 }) do
            local r, it = fitNew(s, "f", maxW, 400)
            if r == nil then okAll = false why = "завис при maxW=" .. maxW break end
            if not isstring(r) then okAll = false why = "вернул не строку" break end
        end
        check("завершается: " .. name, okAll, why)
    end

    -- вырожденная ширина не должна уводить в цикл
    local okDeg = true
    for _, maxW in ipairs({ 8, 0, -5, -100 }) do
        local r = fitNew("Источник света", "f", maxW, 400)
        if r == nil then okDeg = false break end
    end
    check("нулевая и отрицательная ширина безопасны", okDeg)
end

--[[ Кеш: fitText зовётся из Paint каждый кадр. Повторный вызов с теми же
     аргументами обязан браться из кеша, иначе это десятки замеров текста
     на строку на кадр. ]]
print("\n=== КЕШ (fitText зовётся из Paint каждый кадр) ===")
local GRM = loadHelpers(true)
local fitCached = makeFitNew(GRM)
local first = select(2, fitCached("Источник света", "f", 40))
local second = select(2, fitCached("Источник света", "f", 40))
check("первый вызов считает", isnumber(first) and first >= 0)
check("повторный вызов берётся из кеша", second == -1,
      "итераций во втором вызове: " .. tostring(second))

--[[ Страховка от возврата бага в исходнике. ]]
print("\n=== ИСХОДНИК Q-МЕНЮ ===")
local fh = io.open("lua/autorun/sh_grm_qmenu.lua", "r")
        or io.open("../../lua/autorun/sh_grm_qmenu.lua", "r")
if fh then
    local code = fh:read("*a") fh:close()
    local bare = code:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", "")
    check("в fitText есть откат на побайтовую обрезку",
          bare:find("#nxt >= prevLen", 1, true) ~= nil)
    check("в fitText есть предел итераций",
          bare:find("guard > 256", 1, true) ~= nil)
    check("результат fitText кешируется",
          bare:find("fitCache", 1, true) ~= nil)
else
    check("исходник найден", false)
end

print(("\n=== ИТОГ: %d/%d, failures=%d ==="):format(total - fails, total, fails))
if fails > 0 then os.exit(1) end
