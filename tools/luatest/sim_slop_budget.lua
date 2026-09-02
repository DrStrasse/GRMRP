--[[ sim_slop_budget.lua — нулевой бюджет лестниц cond-chain.

    Волны 1–6 вычистили `if x == "a" elseif x == "b" ...` (детектор
    audit_slop --kind cond-chain) с 23 находок до нуля. Стенд не даёт
    лестницам вернуться и держит два уровня проверки:

    1) ДЕТЕРМИНИНИРОВАННЫЙ (всегда): для каждого файла, уже переведённого
       на реестры, подпись старой лестницы обязана отсутствовать. Это
       сторож именно против откатов — работает без Python и зависимостей.

    2) МЕТРИКА ДЕРЕВА (когда есть python3+luaparser): total-счётчик
       audit_slop по cond-chain обязан быть нулевым по всему дереву.
       Без инструментов стенд печатает явный SKIP метрики, но не FAIL:
       gate-инструкции всё равно прогоняют audit_slop вручную, а
       вечнокрасный стенд из-за окружения бессмысленен (§10.1 — стенд
       краснеет на баг, а не на отсутствие тулчейна).

    Запуск из корня репозитория: luajit tools/luatest/sim_slop_budget.lua ]]
local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

local function readAll(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

print("== 1. Вычищенные лестницы не возвращаются (по подписям) ==")
local CLEANED = {
    ["lua/autorun/sh_grm_jobs.lua"] = {
        'elseif currentTab == "',
    },
    ["lua/autorun/sh_grm_mobile.lua"] = {
        "elseif a.id",
        '\n        elseif M.screen == "',
    },
    ["lua/autorun/sh_grm_plates.lua"] = {
        'elseif what == "',
    },
    ["lua/autorun/client/zz_grm_quest_studio.lua"] = {
        'elseif block.kind == "',
    },
    ["lua/autorun/sh_grm_special_service.lua"] = {
        'elseif op == "',
    },
    ["lua/autorun/sh_grm_augmentation_chips.lua"] = {
        'elseif modKey == "',
    },
    ["lua/autorun/sh_faction_fixes.lua"] = {
        'elseif saveType == "',
    },
    ["lua/autorun/sh_grm_vendor.lua"] = {
        'elseif cmd == "',
    },
}
for path, sigs in pairs(CLEANED) do
    local src = readAll(path)
    ok(src ~= nil, ("файл на месте: %s"):format(path))
    if src then
        for _, sig in ipairs(sigs) do
            ok(src:find(sig, 1, true) == nil,
                ("%s: нет следов `%s`"):format(path:match("[^/]+$") or path, sig))
        end
    end
end

print("\n== 2. Контракты реестров этой волны ==")
-- jobs: вкладки описаны реестром с билдером и правом
local jobs = readAll("lua/autorun/sh_grm_jobs.lua") or ""
ok(jobs:find("local TABS = {", 1, true) ~= nil
    and jobs:find("build = buildPublishTab, show = canP", 1, true) ~= nil
    and jobs:find("TAB_BY_ID[currentTab]", 1, true) ~= nil,
    "вкладки биржи — реестр TABS с правом в записи, диспетчер по id")
-- plates: режимы подгонки — записи RENDER_ADJUST, наклон/сдвиг генерируются
local plates = readAll("lua/autorun/sh_grm_plates.lua") or ""
ok(plates:find("local RENDER_ADJUST = {", 1, true) ~= nil
    and plates:find('RENDER_ADJUST[f]', 1, true) ~= nil
    and plates:find('ipairs({ "tiltP", "tiltY", "tiltR" })', 1, true) ~= nil,
    "режимы рендера знаков — реестр, три оси наклона из одной формулы")
-- quest studio: заголовок и сохранение живут в типе блока
local qstudio = readAll("lua/autorun/client/zz_grm_quest_studio.lua") or ""
ok(qstudio:find("Q_BY_ID[block.kind]", 1, true) ~= nil
    and qstudio:find("def.save(out, b, b.data or {})", 1, true) ~= nil
    and qstudio:find("local Q_BY_ID = {}", 1, true) ~= nil,
    "тип блока знает caption и save; студии — только диспетчер")
-- mobile: реестр приложений — единственный источник гейтинга
local mob = readAll("lua/autorun/sh_grm_mobile.lua") or ""
ok(mob:find("MB.AppDefs", 1, true) ~= nil
    and mob:find("function appAllowed(def, tier)", 1, true) ~= nil
    and mob:find("local build = SCREENS[M.screen]", 1, true) ~= nil
    and mob:find("function SCREENS.home(add)", 1, true) ~= nil,
    "телефон: MB.AppDefs + SCREENS вместо трёх копий гейтинга")

print("\n== 3. Метрика всего дерева (audit_slop cond-chain == 0) ==")
local function capture(cmd)
    local p = io.popen(cmd)
    if not p then return nil end
    local s = p:read("*a")
    p:close()
    return s
end
local help = capture("python3 tools/audit_slop.py --help 2>/dev/null")
if help and help:find("usage", 1, true) then
    -- самопроверка детектора: ловушка обязана быть найдена, иначе метрика пуста
    local trapPath = ".luabuild/ladder_trap.lua"
    local w = io.open(trapPath, "wb")
    if w then
        w:write([[
local act = ...
if act == "one" then A()
elseif act == "two" then B()
elseif act == "three" then C()
elseif act == "four" then D()
elseif act == "five" then E()
end
]])
        w:close()
    end
    local trap = w and capture("python3 tools/audit_slop.py --root . --file " .. trapPath .. " 2>/dev/null") or ""
    ok(trap:find("cond-chain", 1, true) ~= nil,
        "детектор живой: ловушка-лестница найдена", trap ~= "" and "в выводе нет cond-chain" or nil)

    local report = capture("python3 tools/audit_slop.py 2>/dev/null") or ""
    local n = tonumber(report:match("cond%-chain%s+(%d+)")) or 0
    ok(report:find("файлов", 1, true) ~= nil, "отчёт по дереву получен")
    ok(n == 0, "cond-chain по всему дереву — ноль", ("найдено: %d"):format(n))
    for line in report:gmatch("[^\n]*cond%-chain[^\n]*") do print("     • " .. line) end
else
    print("  SKIP: python3 + luaparser недоступны — метрика дерева не проверена")
end

print(("\nSLOP BUDGET: %d/%d, провалов: %d"):format(total - fails, total, fails))
if fails > 0 then os.exit(1) end
