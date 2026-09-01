--[[ Живой прогон правил бодигрупп (заказ владельца 27.08):
     меню персонажа сканирует модель, но выдаёт игроку только то, что
     разрешил редактор правил для его организации, отдела и должности.
     Чистые функции грузятся из НАСТОЯЩЕГО модуля.
     Запуск: luajit tools/luatest/sim_bodygroup_rules.lua ]]
local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

SERVER, CLIENT = false, false
function AddCSLuaFile() end
function IsValid(v) return type(v) == "table" and v._valid ~= false end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isfunction(v) return type(v) == "function" end
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

local src = (function()
    local f = io.open("lua/autorun/sh_grm_bodygroup_rules.lua", "rb")
    local t = f:read("*a") f:close() return t
end)()
local charSrc = (function()
    local f = io.open("lua/autorun/sh_grm_character.lua", "rb")
    local t = f:read("*a") f:close() return t
end)()
local function has(hay, n) return hay:find(n, 1, true) ~= nil end

local MODEL = "models/groennerlandinfantry/male_07.mdl"
local FAC   = "828-th Airborne Groennerland Battalion"

print("\n=== 1. КЛЮЧИ И ОБЛАСТИ ===")
-- Пятое поле — должность (ось v5). Пустое = «любая».
ok(BG.Key(MODEL, FAC, "", "") == MODEL .. "|" .. FAC .. "|||", "ключ склеивается из пяти полей",
   BG.Key(MODEL, FAC, "", ""))
ok(BG.Key("MoDeLs/A.MDL", "", "", "") == "models/a.mdl||||", "путь модели приводится к нижнему регистру",
   BG.Key("MoDeLs/A.MDL", "", "", ""))
local m, f2, d2, r2 = BG.ParseKey(BG.Key(MODEL, FAC, "Штаб", "Сержант"))
ok(m == MODEL and f2 == FAC and d2 == "Штаб" and r2 == "Сержант", "ключ разбирается обратно без потерь",
   table.concat({ m, f2, d2, r2 }, " / "))

print("\n=== 2. НОРМАЛИЗАЦИЯ НАСТРОЕК ===")
ok(BG.NormalizeSpec({ mode = "hide", value = 1 }).value == 1, "скрытие хранит своё значение")
ok(BG.NormalizeSpec({ mode = "free" }) == nil, "«доступно игроку» правилом не считается")
ok(BG.NormalizeSpec({ mode = "limit", values = {} }) == nil, "пустой список разрешённых = правила нет")
local lim = BG.NormalizeSpec({ mode = "limit", values = { 3, 1, 1, 0 } })
ok(lim and #lim.values == 3 and lim.values[1] == 0, "список разрешённых чистится от дублей и сортируется",
   lim and table.concat(lim.values, ","))
ok(BG.NormalizeSpec({ mode = "мусор" }) == nil, "неизвестный режим отбрасывается")
local _, cnt = BG.NormalizeGroups({ ["2"] = { mode = "hide", value = 1 }, ["x"] = { mode = "hide" } })
ok(cnt == 1, "нечисловые индексы групп не попадают в правило", cnt)

print("\n=== 3. ПРИОРИТЕТ: ЧЕМ ТОЧНЕЕ ОБЛАСТЬ, ТЕМ СИЛЬНЕЕ ===")
BG.Rules = {
    [BG.Key(MODEL, "", "", "")]                    = { ["3"] = { mode = "limit", values = { 0, 1, 2 } } },
    [BG.Key(MODEL, FAC, "", "")]                   = { ["3"] = { mode = "lock", value = 1 } },
    [BG.Key(MODEL, FAC, "", "Сержант")]            = { ["3"] = { mode = "hide", value = 2 } },
    [BG.Key(MODEL, FAC, "Штаб", "")]               = { ["5"] = { mode = "hide", value = 0 } },
}
local anyone = BG.Resolve(MODEL, {})
ok(anyone[3] and anyone[3].mode == "limit", "без организации действует общее правило модели",
   anyone[3] and anyone[3].mode)
local soldier = BG.Resolve(MODEL, { faction = FAC, role = "Рядовой" })
ok(soldier[3] and soldier[3].mode == "lock", "правило организации перекрывает общее",
   soldier[3] and soldier[3].mode)
local sergeant = BG.Resolve(MODEL, { faction = FAC, role = "Сержант" })
ok(sergeant[3] and sergeant[3].mode == "hide", "правило должности перекрывает правило организации",
   sergeant[3] and sergeant[3].mode)
local hq = BG.Resolve(MODEL, { faction = FAC, dept = "Штаб", role = "Рядовой" })
ok(hq[5] and hq[5].mode == "hide" and hq[3].mode == "lock",
   "правила отдела и организации складываются по разным группам")
ok(BG.Resolve("models/other.mdl", { faction = FAC })[3] == nil, "чужая модель правил не наследует")

print("\n=== 4. ЧТО ВИДИТ ИГРОК ===")
ok(BG.IsVisible(sergeant[3]) == false, "скрытая строка (Armbands) в меню не показывается")
ok(BG.IsVisible(soldier[3]) == true and BG.IsEditable(soldier[3]) == false,
   "закреплённая строка видна, но не редактируется")
ok(BG.IsEditable(nil) == true, "без правила строка редактируется как раньше")
local allowed = BG.AllowedValues(anyone[3], 6)
ok(allowed and #allowed == 3 and allowed[3] == 2, "ограниченная строка переключает только разрешённые варианты",
   allowed and table.concat(allowed, ","))
ok(BG.AllowedValues(nil, 4) == nil, "без правила доступны все варианты модели")
ok(BG.AllowedValues({ mode = "limit", values = { 9 } }, 3)[1] == 0,
   "варианта вне модели быть не может — откат на 0")

print("\n=== 5. СЕРВЕР ОБРЕЗАЕТ ПОДДЕЛАННЫЙ ПАКЕТ ===")
local cheat = { ["3"] = 5, ["5"] = 4, ["7"] = 2 }
local clean = BG.Sanitize(MODEL, cheat, { faction = FAC, dept = "Штаб", role = "Сержант" })
ok(clean["3"] == 2, "скрытая группа получает своё жёсткое значение, а не присланное", tostring(clean["3"]))
ok(clean["5"] == nil, "скрытая группа со значением 0 обнуляется", tostring(clean["5"]))
ok(clean["7"] == 2, "группа без правил остаётся как выбрал игрок", tostring(clean["7"]))
local limited = BG.Sanitize(MODEL, { ["3"] = 4 }, {})
ok(limited["3"] == nil or limited["3"] == 1 or limited["3"] == 2,
   "значение вне списка откатывается к разрешённому", tostring(limited["3"]))
ok(BG.Sanitize(MODEL, nil, {}) ~= nil, "пустой набор бодигрупп — законный ввод")

print("\n=== 6. РЕДАКТОР И ДОСТУП ===")
ok(has(src, 'concommand.Add("grm_bodygroups_admin"'), "есть консольная команда редактора")
ok(has(src, '"/bodygroups_admin"'), "есть чат-команда редактора")
ok(has(src, "ply:IsSuperAdmin()"), "редактор закрыт на суперадмина")
ok(has(src, 'BG.File    = "grm_bodygroup_rules.json"'), "правила лежат в отдельном файле данных")
ok(has(src, "pcall(util.JSONToTable, txt, false, true)"), "JSON читается с третьим аргументом (урок 65)")
ok(has(src, 'net.Receive(NET_SYNC'), "клиент получает правила синхронизацией, а не include")
ok(not has(src, "include("), "модуль не подключает внешних файлов — прошлый редактор падал именно на include")

print("\n=== 7. СВЯЗКА С МЕНЮ ПЕРСОНАЖА ===")
ok(has(charSrc, "GRM.BGRules.Resolve(draft.model"), "меню персонажа спрашивает правила по своей модели")
ok(has(charSrc, 'spec.mode == "hide"'), "скрытые строки не рисуются в «Телосложении»")
ok(has(charSrc, "GRM.BGRules.Sanitize"), "сохранение внешности проходит серверную обрезку")
ok(has(charSrc, "factionSubdepartment"), "в меню уходит подотдел — правила подотделов работают")
ok(has(charSrc, "закреплено организацией"), "закреплённая строка честно подписана игроку")

print(("\n=== ИТОГ: успешно %d, провалено %d ===\n"):format(pass, fail))
if fail > 0 then os.exit(1) end
