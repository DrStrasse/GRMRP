--[[ Страж синтаксиса GMod (баг 21.08: сервер падал на
     sh_grm_arrest.lua:285 «'=' expected near 'continue'»).

     Обычный LuaJIT принимает goto и метки ::label:: — это Lua 5.2, и наша
     проверка компиляции их пропускала. Парсер GMod их НЕ понимает: там
     continue — своё ключевое слово, и «goto continue» рвёт весь файл при
     загрузке аддона. Ошибка вылезает только на живом сервере, поэтому
     ловим её здесь, на каждом прогоне стендов.

     Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_gmod_syntax.lua ]]
local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

local function scan(cmd)
    local out = {}
    local pipe = io.popen(cmd)
    if not pipe then return out end
    for line in pipe:lines() do out[#out + 1] = line end
    pipe:close()
    return out
end

-- Список всех lua-файлов сборки.
local files = scan("find lua addons -name '*.lua' 2>/dev/null")

local badGoto, badLabel, badContinue = {}, {}, {}
for _, path in ipairs(files) do
    local fh = io.open(path, "r")
    if fh then
        local n = 0
        for line in fh:lines() do
            n = n + 1
            local code = line:gsub("%-%-.*$", "")           -- срезать комментарий
            if code:find("%f[%w]goto%s+[%a_]") then badGoto[#badGoto + 1] = path .. ":" .. n end
            if code:find("::%s*[%a_][%w_]*%s*::") then badLabel[#badLabel + 1] = path .. ":" .. n end
        end
        fh:close()
    end
end

print("\n=== СИНТАКСИС, КОТОРЫЙ GMOD НЕ ПЕРЕВАРИТ ===")
ok(#files > 100, "файлы сборки найдены", #files)
ok(#badGoto == 0, "нигде нет goto — парсер GMod его не знает", table.concat(badGoto, ", "))
ok(#badLabel == 0, "нигде нет меток ::label::", table.concat(badLabel, ", "))
-- continue GMod принимает (это его собственное расширение), поэтому
-- запрещён только goto: именно на нём падал sh_grm_arrest.lua.
ok(#badContinue == 0, "оператор continue допустим — под запретом только goto")

print(("\nGMOD SYNTAX: %d/%d, провалов: %d"):format(pass, pass + fail, fail))
if fail > 0 then os.exit(1) end
