-- ======================================================================
-- sim_utf8_trim — обрезка строк по СИМВОЛАМ, а не по байтам.
--
-- Дефект (задача 12, скриншот бланка ГД-2026-000001): в бланке диплома
-- значения обрывались посреди слова —
--   «Высшая Краснознамённая школа КГБ им. Ф.Э.Дзержинског»
--   «Аналитико-прогностическое и социальное управление («
-- Выглядело как «не работает перенос строк», хотя перенос был исправен:
-- до клиента доезжал уже обрезанный текст. Причина — string.sub режет
-- БАЙТЫ, а кириллица в UTF-8 занимает 2 байта на символ, поэтому
-- trim(s, 96) фактически оставлял ~48 русских букв и мог разорвать
-- многобайтовую последовательность пополам (битый символ).
--
-- Проверяем:
--   1) GRM.Utf8Len считает символы, а не байты;
--   2) GRM.Utf8Sub не режет символ пополам (строка остаётся валидной UTF-8);
--   3) реальные строки со скриншота проходят лимит 96 целиком;
--   4) GRM.Utf8Ellipsis укорачивает подписи корректно;
--   5) trim() в дипломах и услугах использует посимвольный лимит.
--
-- Запуск: luajit tools/luatest/sim_utf8_trim.lua
-- ======================================================================

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1
    else fail = fail + 1 io.write("  [FAIL] " .. msg .. "\n") end
end
local function eq(got, want, msg)
    ok(got == want, msg .. "\n         ожидали: " .. tostring(want)
        .. "\n         получили: " .. tostring(got))
end

_G.CLIENT, _G.SERVER = false, true
function _G.AddCSLuaFile() end
function _G.include() end
function _G.IsValid(v) return type(v) == "table" and v.__valid ~= false end
_G.string.Trim = function(s, char)
    if char then return (s:gsub("^" .. char .. "*(.-)" .. char .. "*$", "%1")) end
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

dofile("lua/autorun/sh_00_grm_ui.lua")

--- Строка является валидным UTF-8 (нет оборванных последовательностей).
local function validUtf8(s)
    local i = 1
    while i <= #s do
        local b = s:byte(i)
        local need = (b < 0x80 and 0) or (b >= 0xC0 and b < 0xE0 and 1)
                  or (b >= 0xE0 and b < 0xF0 and 2) or (b >= 0xF0 and b < 0xF8 and 3)
        if need == false or need == nil then return false end
        for k = 1, need do
            local c = s:byte(i + k)
            if not c or c < 0x80 or c >= 0xC0 then return false end
        end
        i = i + need + 1
    end
    return true
end

io.write("\n--- 1. Длина в символах ---\n")

eq(GRM.Utf8Len("Очная"), 5, "«Очная» — 5 символов (а не 10 байт)")
eq(GRM.Utf8Len("Diploma"), 7, "латиница считается как есть")
eq(GRM.Utf8Len(""), 0, "пустая строка — 0")
ok(#"Очная" == 10, "контроль: тех же байт действительно 10")

io.write("\n--- 2. Обрезка не рвёт символ пополам ---\n")

for limit = 1, 12 do
    local out = GRM.Utf8Sub("Дзержинского", limit)
    ok(validUtf8(out), "лимит " .. limit .. ": результат — валидный UTF-8")
    ok(GRM.Utf8Len(out) <= limit, "лимит " .. limit .. ": не превышен")
end
eq(GRM.Utf8Sub("абвгд", 3), "абв", "обрезка ровно по границе символа")
eq(GRM.Utf8Sub("абв", 10), "абв", "лимит больше длины — строка целиком")
eq(GRM.Utf8Sub("абв", 0), "", "нулевой лимит — пустая строка")

io.write("\n--- 3. Реальные строки со скриншота (лимит 96) ---\n")

local inst = "Высшая Краснознамённая школа КГБ им. Ф.Э.Дзержинского"
local qual = "Аналитико-прогностическое и социальное управление (профиль ГБ)"
local sign = "Ю. Андропов, доцент кафедры государственной безопасности"

ok(#inst > 96, "контроль: учреждение длиннее 96 БАЙТ — старый код его резал")
eq(GRM.Utf8Sub(inst, 96), inst, "учреждение проходит лимит 96 символов целиком")
eq(GRM.Utf8Sub(qual, 96), qual, "квалификация проходит целиком")
eq(GRM.Utf8Sub(sign, 64), sign, "подпись проходит лимит 64 целиком")
ok(GRM.Utf8Sub(inst, 96):find("Дзержинского", 1, true) ~= nil,
    "«Дзержинского» больше не обрывается на «Дзержинског»")
ok(GRM.Utf8Sub(qual, 96):find("профиль ГБ", 1, true) ~= nil,
    "скобка «(профиль ГБ)» больше не обрывается")

io.write("\n--- 4. Многоточие ---\n")

eq(GRM.Utf8Ellipsis("Александр Фон Грённер", 14), "Александр Фон…", "длинное имя укорочено с «…»")
eq(GRM.Utf8Ellipsis("Короткое", 14), "Короткое", "короткое имя не трогаем")
ok(GRM.Utf8Len(GRM.Utf8Ellipsis("Александр Фон Грённер", 14)) <= 14,
    "результат укладывается в лимит вместе с многоточием")
ok(validUtf8(GRM.Utf8Ellipsis("Дзержинского", 7)), "результат с «…» — валидный UTF-8")

io.write("\n--- 5. trim() в модулях использует посимвольный лимит ---\n")

local function readFile(path)
    local f = io.open(path, "rb") if not f then return "" end
    local s = f:read("*a") f:close() return s
end

for _, path in ipairs({ "lua/autorun/sh_grm_diplomas.lua", "lua/autorun/sh_grm_services.lua" }) do
    local src = readFile(path)
    local name = path:match("([^/]+)$")
    ok(src:find("GRM.Utf8Sub", 1, true) ~= nil, name .. ": trim() зовёт GRM.Utf8Sub")
    ok(src:find('if n then s = string.sub(s, 1, n) end', 1, true) == nil,
        name .. ": байтовой обрезки в trim() не осталось")
end

local ctx = readFile("lua/autorun/sh_grm_ctx.lua")
ok(ctx:find("GRM.Utf8Ellipsis", 1, true) ~= nil,
    "sh_grm_ctx.lua: подписи контекстного меню режутся посимвольно")
ok(ctx:find('%.%. "…" end') == nil,
    "sh_grm_ctx.lua: байтовых обрезок с многоточием не осталось")

io.write(("\n=== ИТОГ: %d/%d, failures=%d ===\n"):format(pass, pass + fail, fail))
if fail > 0 then os.exit(1) end
