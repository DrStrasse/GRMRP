--[[ Живой прогон редактора бодигрупп после отчёта владельца 27.08:
     «При удалении правила сбрасывает меню, что неудобно + багает саму
      структуру по сути и модель не всегда назначается».

     Три отдельные причины, все чинятся здесь:
       1) СБРОС МЕНЮ. Сервер после каждой правки заново открывал ВЕСЬ
          редактор: окно уничтожалось и создавалось с нуля, поэтому
          выбранные организация, отдел, должность и модель слетали.
       2) «БАГАЕТ СТРУКТУРУ». Модель могли убрать из фракции ПОСЛЕ того,
          как для неё завели правило. Правило продолжало действовать на
          игроков, но в списке моделей его было не найти и не снять.
       3) «МОДЕЛЬ НЕ ВСЕГДА НАЗНАЧАЕТСЯ». DModelPanel читает модель не
          мгновенно; одной проверки через 0.05 с не хватало, и правая
          колонка писала «нет настраиваемых частей».

     Запуск: luajit tools/luatest/sim_bodygroup_editor_live.lua ]]
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
local src = body("lua/autorun/sh_grm_bodygroup_rules.lua")

print("\n=== 1. МЕНЮ БОЛЬШЕ НЕ СБРАСЫВАЕТСЯ ===")
ok(src:find("BG._editorRefresh", 1, true) ~= nil, "появилось точечное обновление редактора")
ok(src:find("if BG._editorRefresh then", 1, true) ~= nil,
   "синхронизация правил обновляет открытый редактор на месте")
-- Пересоздание редактора после правки должно было исчезнуть.
local actBlock = src:match('net%.Receive%(NET_ACT.-\n    end%)') or ""
ok(actBlock ~= "" and not actBlock:find("BG.OpenEditor(ply)", 1, true),
   "сервер больше НЕ открывает редактор заново после сохранения и удаления")
ok(src:find("Правила уже разосланы через BG.Sync", 1, true) ~= nil,
   "причина зафиксирована в комментарии для будущих правок")
ok(src:find("rebuildSaved()", 1, true) ~= nil and src:find("rebuildModels()", 1, true) ~= nil,
   "обновление перерисовывает списки, а не окно")

print("\n=== 1б. ВЫБОР АДМИНА ПЕРЕЖИВАЕТ ПРАВКУ ===")
-- В обновлении не должно быть ни одной строки, сбрасывающей выбор.
local refreshBlock = src:match("BG%._editorRefresh = function%(%).-\n        end") or ""
ok(refreshBlock ~= "", "блок обновления найден")
ok(not refreshBlock:find("sel.model = ", 1, true), "модель не сбрасывается")
ok(not refreshBlock:find("sel.faction = ", 1, true), "организация не сбрасывается")
ok(not refreshBlock:find("sel.position = ", 1, true), "должность не сбрасывается")
ok(not refreshBlock:find("openEditor", 1, true), "окно не пересоздаётся")

print("\n=== 1в. ОКНО ЗАКРЫЛИ — ОБНОВЛЕНИЕ СНИМАЕТСЯ ===")
ok(src:find("local prevOnRemove = f.OnRemove", 1, true) ~= nil,
   "чужой OnRemove (GRM.UI.Track) не затирается, а вызывается следом")
ok(src:find("BG._editorRefresh = nil", 1, true) ~= nil,
   "при закрытии окна обновление снимается — не течёт в пустоту")
ok(src:find("if not IsValid(f) then BG._editorRefresh = nil return end", 1, true) ~= nil,
   "и защита на случай, если окно исчезло раньше")

print("\n=== 2. ПРАВИЛО НЕЛЬЗЯ ПОТЕРЯТЬ ИЗ ВИДУ ===")
ok(src:find("любая модель с правилами всегда попадает в список", 1, true) ~= nil,
   "модель с правилами добавляется в общий список принудительно")
ok(src:find('addModel(path, "есть правила")', 1, true) ~= nil,
   "и помечена, чтобы админ понял, откуда она взялась")
ok(src:find('add(path, "правило вне списка", true)', 1, true) ~= nil,
   "в списке организации показываются её правила на моделях вне списка")
ok(src:find("orphan[path] = true", 1, true) ~= nil, "без дублей")

print("\n=== 3. МОДЕЛЬ ДОЖИДАЕТСЯ ЗАГРУЗКИ ===")
ok(src:find("local function awaitModel(token, tries)", 1, true) ~= nil,
   "ожидание загрузки модели вынесено в отдельную функцию")
ok(src:find("awaitModel(modelToken, 12)", 1, true) ~= nil,
   "до 12 попыток вместо одной проверки через 0.05 с")
ok(src:find("if ready or tries <= 0 then return end", 1, true) ~= nil,
   "как только части прочитались — прекращаем, лишних кадров не тратим")
ok(src:find("modelToken = modelToken + 1", 1, true) ~= nil,
   "быстрое переключение моделей не смешивает результаты: у каждой свой токен")
ok(src:find("if not IsValid(f) or token ~= modelToken then return end", 1, true) ~= nil,
   "ожидание от прошлой модели молча прекращается")
ok(src:find("local function frameCamera()", 1, true) ~= nil,
   "камера кадрируется отдельно и не мешает ожиданию")

print("\n=== 4. ЛОГИКА ПРАВИЛ НЕ ЗАДЕТА ===")
local MODEL = "models/groennerlandinfantry/male_07.mdl"
local FACN = "828-th Airborne"
BG.Rules = {
    [BG.Key(MODEL, "", "", "", "")] = { ["3"] = { mode = "limit", values = { 0, 1 } } },
    [BG.Key(MODEL, FACN, "", "sergeant", "")] = { ["3"] = { mode = "hide", value = 0 } },
    [BG.Key(MODEL, FACN, "", "", "cmd")] = { ["3"] = { mode = "lock", value = 1 } },
}
local plain = BG.Resolve(MODEL, { faction = FACN, role = "sergeant" })
ok(plain[3] and plain[3].mode == "hide", "правило звания работает")
local boss = BG.Resolve(MODEL, { faction = FACN, role = "sergeant", position = "cmd" })
ok(boss[3] and boss[3].mode == "lock", "должность по-прежнему сильнее звания")
ok(BG.HasAnyRule(MODEL) == true, "модель с правилами опознаётся")
ok(BG.HasAnyRule("models/other.mdl") == false, "чужая модель — нет")

-- Удаление правила не должно рушить остальные.
BG.Rules[BG.Key(MODEL, FACN, "", "sergeant", "")] = nil
local after = BG.Resolve(MODEL, { faction = FACN, role = "sergeant", position = "cmd" })
ok(after[3] and after[3].mode == "lock", "после удаления одного правила остальные целы")
local fallback = BG.Resolve(MODEL, { faction = FACN, role = "sergeant" })
ok(fallback[3] and fallback[3].mode == "limit",
   "и область падает на общее правило модели, а не теряется", fallback[3] and fallback[3].mode)

print(("\n=== ИТОГ: успешно %d, провалено %d ===\n"):format(pass, fail))
if fail > 0 then os.exit(1) end
