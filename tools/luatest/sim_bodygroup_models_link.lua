--[[ Живой прогон связки models_admin ↔ редактор правил бодигрупп.

     Отчёт владельца 27.08: «Поставил Сержанту Комендантской Роты модель,
     установил правила, ничего. Пустота.»

     Разбор дал ТРИ независимые причины:
       1) Модели ДОЛЖНОСТЕЙ (f.PositionModels) вообще не попадали в список
          редактора правил. Админ ставил модель должности в models_admin,
          шёл в /bodygroups_admin — а модели там нет, выбрать нечего.
       2) Правила рассылались клиенту через 3 с после входа, а меню
          персонажа открывалось сразу. Модель успевала собраться БЕЗ
          правил, и вкладка «Телосложение» показывала всё подряд.
       3) Между двумя меню не было связи: область и модель приходилось
          искать руками, и промахнуться было легче, чем попасть.

     Запуск: luajit tools/luatest/sim_bodygroup_models_link.lua ]]
local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

SERVER, CLIENT = false, false
function AddCSLuaFile() end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isfunction(v) return type(v) == "function" end
function IsValid(v) return istable(v) and v._valid ~= false end
function string.Trim(s) return (string.gsub(tostring(s or ""), "^%s*(.-)%s*$", "%1")) end
function string.Explode(sep, str)
    local out = {}
    for piece in string.gmatch(tostring(str or "") .. sep, "(.-)" .. sep) do out[#out + 1] = piece end
    return out
end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function table.HasValue(t, v) for _, x in pairs(t or {}) do if x == v then return true end end return false end
function table.Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
hook = { Add = function() end, Run = function() end }
GRM = {}

assert(loadfile("lua/autorun/sh_grm_bodygroup_rules.lua"))()
local BG = GRM.BGRules

local function body(path)
    local fh = io.open(path, "rb") if not fh then return "" end
    local t = fh:read("*a") fh:close() return t
end
local bgSrc = body("lua/autorun/sh_grm_bodygroup_rules.lua")
local loadSrc = body("lua/autorun/client/cl_grm_faction_loadout_admin.lua")
local charSrc = body("lua/autorun/sh_grm_character.lua")

print("\n=== 1. МОДЕЛИ ДОЛЖНОСТЕЙ ПОПАДАЮТ В РЕДАКТОР ПРАВИЛ ===")
ok(bgSrc:find("f.PositionModels", 1, true) ~= nil,
   "снимок редактора собирает модели должностей — это и была «пустота»")
ok(bgSrc:find('addFactionModels(list, row.display .. " • должность "', 1, true) ~= nil,
   "и помечает их владельцем, чтобы админ понял, откуда модель")
-- Остальные уровни не должны были потеряться.
for _, lvl in ipairs({ "f.Models", "f.RoleModels", "f.DepartmentModels", "sub.models" }) do
    ok(bgSrc:find(lvl, 1, true) ~= nil, "уровень " .. lvl .. " по-прежнему собирается")
end

print("\n=== 2. ПРАВИЛА ПРИХОДЯТ ДО ОТКРЫТИЯ МЕНЮ ПЕРСОНАЖА ===")
ok(charSrc:find("pcall(GRM.BGRules.Sync, ply)", 1, true) ~= nil,
   "правила досылаются прямо перед окном персонажа — гонка закрыта")
ok(charSrc:find('hook.Add("GRM_BodygroupRulesSynced", "GRM_Char_BGRulesLive"', 1, true) ~= nil,
   "если правила доехали позже, вкладка «Телосложение» пересобирается")
ok(charSrc:find('hook.Remove("GRM_BodygroupRulesSynced", "GRM_Char_BGRulesLive")', 1, true) ~= nil,
   "подписка снимается вместе с окном — не течёт")

print("\n=== 3. ПЕРЕХОД ИЗ models_admin В ПРАВИЛА ===")
ok(loadSrc:find('mkBtn(row, "Правила", C.gold', 1, true) ~= nil,
   "у строки модели появилась кнопка «Правила»")
ok(loadSrc:find("GRM.BGRules.Request(focus)", 1, true) ~= nil,
   "она открывает редактор правил с фокусом")
ok(loadSrc:find('node.scope == "position"', 1, true) ~= nil,
   "должность попадает в фокус")
for _, sc in ipairs({ "role", "department", "subdepartment" }) do
    ok(loadSrc:find('node.scope == "' .. sc .. '"', 1, true) ~= nil,
       "область «" .. sc .. "» тоже подставляется автоматически")
end
ok(loadSrc:find("Модуль правил бодигрупп не загружен", 1, true) ~= nil,
   "без модуля правил кнопка честно сообщает об этом, а не молчит")

print("\n=== 4. СЕРВЕР И КЛИЕНТ ПОНИМАЮТ ФОКУС ===")
ok(bgSrc:find("function BG.OpenEditor(ply, focus)", 1, true) ~= nil, "сервер принимает фокус")
ok(bgSrc:find("function BG.Request(focus)", 1, true) ~= nil, "клиент умеет его отправить")
ok(bgSrc:find("function BG.OpenFor(ply, focus)", 1, true) ~= nil,
   "есть публичная точка входа для других модулей")
ok(bgSrc:find('owners = { "из редактора моделей" }', 1, true) ~= nil,
   "модель из фокуса добавляется в список, даже если её нигде нет")
ok(bgSrc:find("local focus = istable(snapshot.focus) and snapshot.focus or nil", 1, true) ~= nil,
   "клиент применяет фокус при открытии")
ok(bgSrc:find("setModel(focus.model)", 1, true) ~= nil, "и сразу встаёт на нужную модель")

print("\n=== 5. ЖИВАЯ ПРОВЕРКА: СЛУЧАЙ ИЗ ОТЧЁТА ===")
-- Сержант Комендантской Роты: подотдел + звание + модель должности.
local MODEL = "models/groennerlandinfantry/male_07.mdl"
local FACN = "828-th Airborne Groennerland Battalion"
BG.Rules = {}
BG.Rules[BG.Key(MODEL, FACN, "komendant_rota", "Сержант", "")] =
    { ["3"] = { mode = "hide", value = 0 } }

local asSub = BG.Resolve(MODEL, { faction = FACN, dept = "shtab",
    sub = "komendant_rota", role = "Сержант" })
ok(asSub[3] and asSub[3].mode == "hide",
   "правило срабатывает, когда рота — ПОДОТДЕЛ", asSub[3] and asSub[3].mode)

local asDept = BG.Resolve(MODEL, { faction = FACN, dept = "komendant_rota", role = "Сержант" })
ok(asDept[3] and asDept[3].mode == "hide",
   "и когда рота — ОТДЕЛ: обе формы дают один ключ", asDept[3] and asDept[3].mode)

local other = BG.Resolve(MODEL, { faction = FACN, dept = "shtab", role = "Сержант" })
ok(other[3] == nil, "сержанта другого подразделения правило не трогает")

-- Регистр пути и лишние пробелы не должны ломать совпадение.
local upper = BG.Resolve("MODELS/GroennerlandInfantry/MALE_07.MDL",
    { faction = FACN, sub = "komendant_rota", role = "Сержант" })
ok(upper[3] and upper[3].mode == "hide", "регистр пути модели не мешает")

-- Должность сильнее звания — порядок не сломан.
BG.Rules[BG.Key(MODEL, FACN, "komendant_rota", "", "rota_head")] =
    { ["3"] = { mode = "lock", value = 1 } }
local boss = BG.Resolve(MODEL, { faction = FACN, sub = "komendant_rota",
    role = "Сержант", position = "rota_head" })
ok(boss[3] and boss[3].mode == "lock",
   "у командира роты своё правило перекрывает правило звания")

print(("\n=== ИТОГ: успешно %d, провалено %d ===\n"):format(pass, fail))
if fail > 0 then os.exit(1) end
