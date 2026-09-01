--[[--------------------------------------------------------------------
    sim_gnews_format.lua
    Тест форматирования /gnews с переносом строки.
----------------------------------------------------------------------]]

local pass, fail = 0, 0
local function ok(v, msg)
    if v then
        pass = pass + 1
        print("  ok  " .. msg)
    else
        fail = fail + 1
        print("  FAIL " .. msg)
    end
end

print("=== ТЕСТ: Форматирование /gnews с переносом строки ===")
local fixesCode = assert(io.open("lua/autorun/sh_faction_fixes.lua", "rb")):read("*a")

ok(fixesCode:find('"[Гос.Новости] "', 1, true) ~= nil, "Заголовок [Гос.Новости]")
ok(fixesCode:find('"[" .. tag .. "]\\n"', 1, true) ~= nil, "Перенос строки \\n после тега фракции")
ok(fixesCode:find('playerName,', 1, true) ~= nil, "Вывод RP-имени на второй строке")
ok(fixesCode:find('" (" .. role .. "): "', 1, true) ~= nil, "Вывод звания/должности в скобках с двоеточием")
ok(fixesCode:find('RoleDisplayName', 1, true) ~= nil, "Резолвер публичного звания/должности в GNews")

print(string.format("\nРЕЗУЛЬТАТ: Пройдено проверок: %d/%d (провалов: %d)", pass, pass + fail, fail))
if fail > 0 then os.exit(1) end
print("ALL GNEWS FORMATTING TESTS PASSED!")
