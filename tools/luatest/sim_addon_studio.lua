--[[--------------------------------------------------------------------
    sim_addon_studio — общая часть «Студии аддонов»: каталог узлов,
    нормализация манифеста, раундтрип и генератор GLua-кода.

    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_addon_studio.lua
----------------------------------------------------------------------]]
local stub = dofile("tools/luatest/lib_gmod_stub.lua")
stub.install()

-- Стенд обязан проверять источник: если AddNetworkString/CompileString
-- не пришли из стаба, модуль не поднимется и «зелёный» отчёт лжёт.
if not _G.AddCSLuaFile then
    _G.AddCSLuaFile = function() end
end
if not _G.util or not _G.util.AddNetworkString then
    _G.util = _G.util or {}
    _G.util.AddNetworkString = function() end
end
_G.CompileString = function(src, name)
    return loadstring(src, name)
end

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

local function read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a") f:close()
    return s
end

local loaded, err = stub.loadModule("addons/grm_addon_studio/lua/autorun/sh_grm_addon_studio.lua")
ok(loaded, "модуль общей части поднялся", err)
local A = _G.GRM and _G.GRM.AddonStudio
ok(A and A.Version == "1.0.0", "версия 1.0.0")

print("\n=== 1. КАТАЛОГ УЗЛОВ ===")
local ids, cats, allDefs = {}, {}, {}
for _, d in ipairs(A.Defs) do
    ids[d.id] = (ids[d.id] or 0) + 1
    cats[d.cat] = true
    allDefs[#allDefs + 1] = d.id
end
ok(#A.Defs >= 20, "узлов достаточно для редактора аддона: " .. #A.Defs)
local dup = false
for id, n in pairs(ids) do if n > 1 then dup = true print("    дубль: " .. id) end end
ok(not dup, "id узлов уникальны")
local catOk = true
for _, c in ipairs(A.Cats) do if not cats[c.id] then catOk = false end end
ok(catOk, "категории палитры ссылаются на существующие cat")
local portOk, fieldOk = true, true
for _, d in ipairs(A.Defs) do
    local ports = d.ports or {}
    if type(ports["in"]) ~= "table" or type(ports.out) ~= "table" or #ports["in"] == 0 or #ports.out == 0 then
        portOk = false print("    плохие порты: " .. d.id)
    end
    local seen = {}
    for _, f in ipairs(d.fields or {}) do
        if seen[f.key] then fieldOk = false print("    дубль поля: " .. d.id .. "." .. f.key) end
        seen[f.key] = true
        if A.Defaults(d.id)[f.key] == nil then
            fieldOk = false print("    дефолт поля не в Defaults: " .. d.id .. "." .. f.key)
        end
    end
end
ok(portOk, "у каждого узла есть входы и выходы")
ok(fieldOk, "поля инспектора уникальны и покрыты дефолтами")

-- Дефолты — глубокие копии: правка одного узла не трогает другой.
local d1 = A.Defaults("model")
local d2 = A.Defaults("model")
d1.pos.x = 99
ok(d2.pos.x == 0, "Defaults — независимые копии (позиция)")

print("\n=== 2. НОРМАЛИЗАЦИЯ ===")
local dirty = {
    name = "Вывеска «Цитадель»",
    id = "",
    nodes = {
        { uid = "n1", kind = "model", x = 40, y = 40, data = { model = "models/props_c17/chair02a.mdl", pos = { x = 1, y = 2, z = 3 } } },
        { uid = "n1", kind = "entity", x = -100, y = 99999, data = { class = "grm_comp_police" } },
        { uid = "n9", kind = "unknown_kind", data = {} },
    },
    edges = {
        { a = "n1", ap = "out", b = "n1", bp = "in" },
        { a = "n1", ap = "out", b = "n2", bp = "in" },
        { a = "zz", ap = "out", b = "n2", bp = "in" },
    },
}
local norm = A.Normalize(dirty)
-- Дубль uid (n1 у двух узлов) и неизвестный тип отбрасываются целиком:
-- переименовывать опасно, связи уже адресуют существующий n1.
ok(#norm.nodes == 1 and norm.nodes[1].kind == "model", "неизвестный тип и дубль uid отброшены", #norm.nodes)
ok(norm.nodes[1].x == 40 and norm.nodes[1].y == 40, "координаты первого узла не тронуты")
ok(#norm.edges == 0, "петля и ссылки на отсутствующих отброшены", #norm.edges)
ok(norm.id ~= "", "пустой id заменён slug'ом")
-- Узлы с разными uid и разными типами сохраняются оба.
local mixed = A.Normalize({ nodes = {
    { uid = "n1", kind = "model", x = 0, y = 0, data = {} },
    { uid = "n2", kind = "entity", x = -100, y = 99999, data = { class = "grm_comp_police" } },
} })
ok(#mixed.nodes == 2, "разные узлы сохраняются")
ok(mixed.nodes[2].x == 0 and mixed.nodes[2].y == 1900, "координаты приведены в холст")

print("\n=== 3. МАНИФЕСТ: РАУНДТРИП ===")
local proj = A.Normalize({
    name = 'Цитадель "второе ядро"',
    id = "citadel_core",
    desc = "Ядро цитадели: экран + терминал",
    nodes = {
        { uid = "n1", kind = "entity", x = 40, y = 60, data = { class = "grm_citadel_core", kv = "model = models/props_c17/console01.mdl" } },
        { uid = "n2", kind = "screen", x = 340, y = 60, data = { size = "512x256", page = "menu_main" } },
        { uid = "n3", kind = "menu", x = 640, y = 60, data = { title = "Ядро", w = 640, h = 420 } },
        { uid = "n4", kind = "button", x = 940, y = 60, data = { label = "ПУСК", target = "n3" } },
        { uid = "n5", kind = "condition", x = 340, y = 320, data = { type = "faction", a = "Орден", op = "==", b = "" } },
        { uid = "n6", kind = "sound", x = 640, y = 320, data = { sound = "sound/ambient/alarms/klaxon1.wav", vol = 0.8 } },
        { uid = "n7", kind = "export", x = 1200, y = 60, data = { kind = "core", name = "citadel_core", path = "lua/autorun/sh_citadel_core.lua" } },
    },
    edges = {
        { a = "n1", ap = "out", b = "n2", bp = "in" },
        { a = "n2", ap = "out", b = "n3", bp = "in" },
        { a = "n3", ap = "out", b = "n4", bp = "in" },
        { a = "n5", ap = "else", b = "n6", bp = "in" },
    },
})
local text = A.ToLuaText(proj)
ok(string.find(text, '["format"] = "grm_addon_studio"') ~= nil, "манифест содержит формат")
ok(string.find(text, "Цитадель") ~= nil, "кириллица сохраняется в манифесте")

-- Распарсить обратно: стаб CompileString = loadstring.
local parsed = A.ParseText("return " .. text)
ok(istable(parsed), "ParseText возвращает проект")
ok(parsed and parsed.id == "citadel_core" and parsed.name == 'Цитадель "второе ядро"',
    "имя с кавычками переживает раундтрип")
ok(parsed and #parsed.nodes == 7 and #parsed.edges == 4, "узлы и связи на месте", parsed and #parsed.nodes)
ok(parsed and parsed.nodes[2].data.page == "menu_main", "данные узла на месте")
local cond = nil
for _, n in ipairs(parsed.nodes or {}) do if n.kind == "condition" then cond = n end end
ok(cond and cond.data.a == "Орден", "кириллическое значение условия на месте")

print("\n=== 4. ГЕНЕРАТОР КОДА ===")
local code = A.Generate(proj)
ok(string.find(code, "СТУДИЯ АДДОНА") ~= nil, "шапка компиляции есть")
ok(string.find(code, "local ASPROJECT") ~= nil, "манифест в тексте компиляции")
ok(string.find(code, 'ents%.Create%("grm_citadel_core"%)') ~= nil, "entity: класс из аддона попал в код")
ok(string.find(code, 'render%.CreateRenderTarget') ~= nil, "screen: рендер-таргет попал в код")
ok(string.find(code, 'vgui%.Create%("DFrame"%)') ~= nil, "menu: окно Derma попал в код")
ok(string.find(code, 'SetText%("ПУСК"%)') ~= nil, "button: подпись кнопки попала в код")
ok(string.find(code, "фракция") ~= nil or string.find(code, "GRM_Faction") ~= nil, "condition: проверка фракции")
ok(string.find(code, "sound%.Play") ~= nil, "sound: звук попал в код")
ok(string.find(code, "СВЯЗЬ") ~= nil, "отчёт связей есть")
ok(string.find(code, "иначе") ~= nil, "связь по ветке «иначе» помечена")
ok(string.find(code, "ЭКСПОРТ") ~= nil, "узел экспорта виден")
ok(string.find(code, "sh_citadel_core.lua") ~= nil, "путь экспорта виден в коде")

print("\n=== 5. ПОВЕДЕНИЕ НА ОТКАТАХ ===")
-- Узел без модели: генератор не должен падать и должен писать модели.
local dumb = A.Generate(A.Normalize({
    name = "Пустой",
    nodes = { { uid = "n1", kind = "model", x = 0, y = 0, data = { model = "" } } },
}))
ok(string.find(dumb, 'ent:SetModel%(%""%)') ~= nil, "пустая модель не роняет генератор")
-- [[ Найденная на откате ловушка: `(` и `)` в pattern — метасимволы
--     захвата, а не скобки. Без `%` поиск `ent:SetModel("")` молча не
--     находит строку, хотя она в тексте есть. ]]
-- Перебор строк: длинная кириллическая строка режется нормализацией.
local long = A.Normalize({ name = "x", nodes = {
    { uid = "n1", kind = "text", x = 0, y = 0, data = { text = string.rep("я", 20000) } },
} })
ok(#(long.nodes[1].data.text or "") <= A.MaxTextLen, "длинные строки режутся")

print("\n=== 6. ПОДПИСИ И IDENT ===")
ok(A.Ident("Студия Аддонов!") ~= "" and A.Ident("Студия Аддонов!") ~= nil, "Ident из кириллицы")
ok(A.Slug('Цитадель "v2"') == "Цитадель_v2", "Slug из имени с кавычками")
ok(A.Caption("model", { data = { model = "models/props_c17/chair02a.mdl" } }) ~= "", "подпись карточки не пустая")
ok(A.Stats(proj).nodes == 7 and A.Stats(proj).edges == 4, "статистика корректна")

print("\n=== 7. НОВЫЕ ТИПЫ: ИГРОК, ЭФФЕКТЫ, ПУТИ, ПРИВЯЗКИ, ЧАТ, КЛАВИШИ, МУЗЫКА ===")
local need = { player = true, effect = true, material = true, path = true, anchor = true,
    chat = true, chatbutton = true, keys = true, music = true }
local haveAll = true
for _, d in ipairs(A.Defs) do need[d.id] = nil end
for id in pairs(need) do haveAll = false print("    нет типа: " .. id) end
ok(haveAll, "все заказанные типы в каталоге")

local function genNode(kind, data)
    local p = A.Normalize({ name = "t", nodes = { { uid = "n1", kind = kind, x = 0, y = 0, data = data } } })
    return A.Generate(p)
end
--[[ Поиск с ПЛЕЙНЫМ флагом: `SetHealth(150)` содержит скобки — в
     pattern они метасимволы, а `%150` — «обратная ссылка» и валит
     `find` ошибкой «invalid capture index». Ловушка уже наступала в
     этом же стенде с `ent:SetModel("")`. ]]
local function has(needle, hay) return string.find(hay or "", needle, 1, true) ~= nil end
local p = genNode("player", { health = 150, armor = 50 })
ok(has("SetHealth(150)", p), "player: здоровье")
ok(has("SetArmor(50)", p), "player: броня")
ok(has("util.ScreenShake", genNode("effect", { type = "shake" })), "effect: тряска экрана")
ok(has("ParticleEffect", genNode("effect", { type = "particle", name = "explosion" })), "effect: частицы")
ok(has(":SetMaterial(", genNode("material", { material = "models/props/chair.vmt" })), "material: текстура")
local pathCode = genNode("path", { points = "0,0,0\n100,0,0\n0,100,0" })
ok(has("local PATH", pathCode), "path: таблица точек")
ok(has(":SetParent(", genNode("anchor", { child = "n1", parent = "n2" })), "anchor: крепление")
ok(has("ChatPrint", genNode("chat", { text = "Привет" })), "chat: сообщение")
ok(has("/me", genNode("chatbutton", { buttons = "Привет|/me здоровается" })), "chatbutton: быстрые команды")
ok(has("PlayerButtonDown", genNode("keys", { key = "IN_USE", mode = "press" })), "keys: клавиши")
ok(has("SoundPatch", genNode("music", { sound = "sound/music/track.wav", loop = true })), "music: фоновый звук")

print("\n=== 8. ВАЛИДАТОР (тест на работоспособность) ===")
local good = A.Normalize({
    name = "Хороший", nodes = {
        { uid = "n1", kind = "entity", data = { class = "grm_comp_police" } },
        { uid = "n2", kind = "export", data = { name = "x", kind = "module" } },
    }, edges = {},
})
local cat = A.CatalogIndex({ "grm_comp_police", "models/a/b.mdl" })
local res = A.Validate(good, { ents = cat, models = cat })
ok(#res.errors == 0, "чистый проект: ошибок нет", table.concat(res.errors, "; "))

local bad = A.Normalize({ name = "bad", nodes = {
    { uid = "n1", kind = "entity", data = { class = "no_such_class" } },
    { uid = "n2", kind = "model", data = { model = "" } },
    { uid = "n3", kind = "condition", data = { type = "compare", a = "1", op = "==", b = "2" } },
}, edges = { { a = "n1", ap = "bogus", b = "n2", bp = "no" } } })
res = A.Validate(bad, { ents = cat, models = cat })
local errJoin = table.concat(res.errors, "\n")
ok(string.find(errJoin, "не найден среди") ~= nil, "несуществующий класс — ошибка")
ok(string.find(errJoin, "модель не выбрана") ~= nil, "пустая модель — ошибка")
ok(string.find(errJoin, "не существует") ~= nil, "несуществующий порт — ошибка")
local noExport = A.Normalize({ name = "без экспорта", nodes = {
    { uid = "n1", kind = "model", data = { model = "models/a/b.mdl" } },
} })
res = A.Validate(noExport, { ents = cat, models = cat, sounds = {} })
ok(#res.warnings >= 1, "нет узла экспорта → предупреждение", table.concat(res.warnings, "; "))

-- Синтаксис черновика.
local okSyn, synErr = A.CheckSyntax(good)
ok(okSyn, "черновик компилируется", synErr)

print("\n=== 9. КОНСТРУКТОР ОКОН: МАКЕТ И ШАБЛОНЫ ===")
local withLayout = A.Normalize({
    name = "Меню", nodes = { { uid = "n1", kind = "menu", x = 0, y = 0, data = { title = "Меню" } },
        { uid = "n2", kind = "export", data = { name = "m", kind = "module" } } },
    layout = { w = 900, h = 700, widgets = {
        { kind = "button", x = 10, y = 10, w = 120, h = 30, label = "ПУСК" },
        { kind = "entry", x = 150, y = 10, w = 200, h = 30, placeholder = "Логин" },
        { kind = "slider", x = 10, y = 50, w = 300, h = 30, min = 0, max = 100, value = 42 },
        { kind = "bogus", x = 0, y = 0, w = 10, h = 10 },
    } },
    templates = {
        { id = "t1", name = "Основной", layout = { w = 800, h = 600, widgets = {
            { kind = "label", x = 5, y = 5, w = 100, h = 20, text = "Привет" } } } },
        { id = "t1", name = "Дубль (отброшен)", layout = {} },
    },
})
ok(#withLayout.layout.widgets == 3, "неизвестный виджет отброшен", #withLayout.layout.widgets)
ok(withLayout.layout.widgets[1].label == "ПУСК", "значение виджета сохраняется (не дефолт)")
ok(withLayout.layout.widgets[3].value == 42, "значение слайдера сохраняется")
ok(#withLayout.templates == 1 and withLayout.templates[1].name == "Основной", "шаблон один, дубль отброшен")

-- Раундтрип макета внутри проекта.
local mtext = A.ToLuaText(withLayout)
local mback = A.ParseText("return " .. mtext)
ok(mback and #mback.layout.widgets == 3, "макет переживает раундтрип")
ok(mback and #mback.templates == 1 and mback.templates[1].layout.widgets[1].text == "Привет",
    "шаблон переживает раундтрип")

local layCode = A.LayoutToCode(withLayout.layout)
local layText = table.concat(layCode, "\n")
ok(has("function buildUI", layText), "генератор макета: buildUI")
ok(has("SetPos(10,", layText), "генератор макета: координаты")
ok(has('SetText("ПУСК")', layText), "генератор макета: подпись кнопки")

print("\n=== 10. КОНСТРУКТОР РАЗМЕЩЕНИЯ: ТУЛ И UNDO ===")
local place = A.Normalize({
    name = "Ядро цитадели", nodes = {
        { uid = "n1", kind = "entity", x = 0, y = 0, data = { class = "grm_citadel_core" } },
        { uid = "n2", kind = "light", x = 0, y = 0, data = { pos = { x = 0, y = 0, z = 50 } } },
        { uid = "n3", kind = "export", x = 0, y = 0, data = { name = "citadel", kind = "prefab",
            placeable = true, tool = "grm_studio_citadel", toolcat = "GRM Studio" } },
    },
})
local tool = A.ToolFile(place, "grm_studio_citadel", "GRM Studio")
ok(has("TOOL.LeftClick", tool), "тул: LeftClick")
ok(has("undo.Create", tool), "тул: undo")
ok(has('ents.Create("grm_citadel_core")', tool), "тул: класс ядра цитадели")
ok(has("grm_studio_citadel.lua", tool), "тул: имя файла в шапке")
local full = A.Generate(place)
ok(has("5. ТУЛ РАЗМЕЩЕНИЯ", full), "компиляция содержит раздел тула")
ok(has("6. КОНЕЦ", full), "компиляция закрыта")

print("\n=== 11. КОНСТРУКТОР ОКОН: НОВЫЕ ВИДЖЕТЫ И ГЕОМЕТРИЯ ===")
local wKinds = {}
for _, k in ipairs(A.WidgetKinds) do wKinds[k.id] = true end
ok(wKinds.model and wKinds.progress and wKinds.select and wKinds.textarea,
    "в палитре есть модель 3D, прогресс, выбор, текст-область")
local wf = A.WidgetFields("slider")
local hasNum = false
for _, f in ipairs(wf) do if f.type == "number" then hasNum = true end end
ok(#wf >= 3 and hasNum, "у слайдера есть подпись и числовые min/max/value")

-- Нормализация виджета: диапазоны и пределы.
local nw = A.NormalizeWidget({ kind = "slider", min = 100, max = 10, value = 500, x = -50, y = 20 }, { w = 800, h = 600 })
ok(nw.min == 10 and nw.max == 100 and nw.value == 100, "min>max меняются местами, value клампится")
ok(nw.x == 0 and nw.w >= 12, "координаты и размеры в пределах холста")

-- Снап к сетке.
local sr = A.SnapRect({ x = 13, y = 17, w = 100, h = 34 }, 8)
local function gridOk(r)
    for _, v in ipairs({ r.x, r.y, r.w, r.h }) do if v % 8 ~= 0 then return false end end
    return true
end
ok(gridOk(sr) and sr.x == 16, "SnapRect кратен сетке 8")
sr = A.SnapRect({ x = 13, y = 17, w = 40, h = 30 }, 4)
ok(sr.x == 12 and sr.w == 40, "сетка 4: тоже кратна")

-- Движение с клампом по границам холста.
local mv = A.MoveRect({ x = 790, y = 590, w = 100, h = 30 }, 50, 50, { w = 800, h = 600 })
ok(mv.x == 700 and mv.y == 570, "MoveRect не выпускает за край")

-- Ресайз за рёбра: правый край двигает только w, левый — x и w.
local g0 = A.GrowRect({ x = 10, y = 10, w = 100, h = 50 }, "e", 20, 0, { w = 800, h = 600 }, 12)
ok(g0.w == 120 and g0.x == 10, "GrowRect: правый край")
local g1 = A.GrowRect({ x = 10, y = 10, w = 100, h = 50 }, "w", 20, 0, { w = 800, h = 600 }, 12)
ok(g1.x == 30 and g1.w == 80, "GrowRect: левый край (правый неподвижен)")
local g2 = A.GrowRect({ x = 10, y = 10, w = 100, h = 50 }, "nw", 20, 20, { w = 800, h = 600 }, 12)
ok(g2.x == 30 and g2.y == 30 and g2.w == 80 and g2.h == 30, "GrowRect: угол nw")
local g3 = A.GrowRect({ x = 10, y = 10, w = 20, h = 20 }, "w", 500, 0, { w = 800, h = 600 }, 12)
ok(g3.w == 12 and g3.x == 18, "GrowRect: минимальный размер при сжатии")

-- Новые виды в генераторе buildUI.
local rich = A.Normalize({ name = "rich", nodes = { { uid = "n1", kind = "export", data = { name = "r", kind = "module" } } },
    layout = { w = 900, h = 700, widgets = {
        { kind = "model", x = 10, y = 10, w = 180, h = 180, model = "models/props/c17/chair02a.mdl" },
        { kind = "progress", x = 200, y = 10, w = 240, h = 18, min = 0, max = 200, value = 50 },
        { kind = "select", x = 200, y = 40, w = 160, h = 24, options = "А;Б" },
        { kind = "textarea", x = 200, y = 80, w = 240, h = 60 },
    } } })
local rc = A.LayoutToCode(rich.layout)
local rt = table.concat(rc, "\n")
ok(has('vgui.Create("DModelPanel"', rt) and has("SetModel", rt), "buildUI: модель 3D")
ok(has('vgui.Create("DProgress"', rt) and has("SetFraction", rt), "buildUI: прогресс")
ok(has('vgui.Create("DComboBox"', rt) and has("AddChoice", rt), "buildUI: выбор")
ok(has("SetMultiline", rt), "buildUI: текст-область")
local rfull = A.Generate(rich)
ok(has("4.5 МАКЕТ ОКНА", rfull) and has("DModelPanel", rfull), "компиляция: раздел макета с новыми виджетами")

-- Раундтрип с новыми видами виджетов.
local rtext = A.ToLuaText(rich)
local rback = A.ParseText("return " .. rtext)
ok(rback and #rback.layout.widgets == 4 and rback.layout.widgets[1].kind == "model"
    and rback.layout.widgets[2].value == 50, "новые виджеты переживают раундтрип")

print("\n=== 12. ВАЛИДАТОР: МАКЕТ И ПРЕДПРОСМОТР ===")
local wide = A.Normalize({ name = "wide", nodes = { { uid = "n1", kind = "export", data = { name = "w", kind = "module" } } },
    layout = { w = 400, h = 300, widgets = { { kind = "button", x = 300, y = 10, w = 200, h = 30, label = "За краем" } } } })
res = A.Validate(wide, {})
local wJoin = table.concat(res.warnings, "\n")
ok(has("выходит за правый край", wJoin), "виджет за краем — предупреждение")
local okRich, richErr = A.CheckSyntax(rich)
ok(okRich, "черновик с новыми виджетами компилируется", richErr)

print("\n=== 13. КЛИЕНТСКИЙ UI: БЕЗ НЕСУЩЕСТВУЮЩИХ МЕТОДОВ DERMA ===")
--[[ Боевой отчёт владельца: «attempt to call method 'SetReadOnly' (a nil
     value)» в mkCodeTab — в GMod у DTextEntry SetReadOnly нет, падает всё
     окно студии. Стенд читает клиентский файл и требует правильный API. ]]
local clientSrc = read("addons/grm_addon_studio/lua/autorun/client/cl_grm_addon_studio.lua")
local serverSrc = read("addons/grm_addon_studio/lua/autorun/server/sv_grm_addon_studio.lua")
-- В комментарии слово «SetReadOnly» допустимо — ловим именно ВЫЗОВ.
ok(not has(":SetReadOnly(", clientSrc), "в клиенте нет вызова SetReadOnly (GMod DTextEntry его не имеет)")
ok(has("SetEditable(false)", clientSrc), "вывод кода — SetEditable(false): копировать можно, править нельзя")
-- Тот же приём в генераторе: buildUI не должен звать несуществующее.
ok(not has("SetReadOnly", table.concat(A.LayoutToCode({ w = 800, h = 600, widgets = {} }), "\n")),
    "генератор макета не использует SetReadOnly")
--[[ DScrollPanel: у него GetChildren() = {canvas, vbar}; чистка детей
     самого скролла сносит vbar («Tried to use a NULL Panel»). Все очистки
     в клиенте должны идти через GetCanvas() или DPanel-холдер из V.state.
     Проверка построчная: для каждой очистки смотрим ближайшее связывание
     переменной выше и классифицируем его (GetCanvas — безопасно). ]]
local clientLines = {}
for line in clientSrc:gmatch("[^\n]+") do clientLines[#clientLines + 1] = line end
local stateKind = {}
for _, line in ipairs(clientLines) do
    local field, var = string.match(line, "V%.state%.([%w_]+)%s*=%s*([%w_]+)")
    if field and var then
        for _, decl in ipairs(clientLines) do
            local kind = string.match(decl, "^%s*local " .. var .. "%s*=%s*vgui%.Create%(\"([%w_]+)\"")
            if kind then stateKind[field] = kind break end
        end
    end
end
local function bindingAbove(idx, name)
    for j = idx - 1, 1, -1 do
        local b = string.match(clientLines[j], "^%s*local " .. name .. "%s*=%s*(.+)%s*$")
        if b then return b end
    end
    return nil
end
local badClear = {}
for i, line in ipairs(clientLines) do
    -- Любой обход GetChildren() (и прямое удаление, и снапшот в kids):
    -- у DScrollPanel это canvas + vbar, vbar нельзя трогать.
    local name = has(":GetChildren()", line)
        and string.match(line, "ipairs%(([%w_]+)%:GetChildren") or nil
    if name then
        local b = bindingAbove(i, name) or ""
        if has("GetCanvas()", b) then
            -- канвас: безопасно
        elseif has("vgui.Create(\"DScrollPanel\"", b) then
            badClear[#badClear + 1] = name
        else
            local field = string.match(b, "V%.state%.([%w_]+)")
            if field and stateKind[field] == "DScrollPanel" then
                badClear[#badClear + 1] = name
            elseif field then
                -- DPanel-холдер из state: безопасно
            else
                badClear[#badClear + 1] = name .. "(unresolved)" -- нераспознанное связывание
            end
        end
    end
end
-- Параметры-хелперы (renderLayoutWidgets(parent), clearPanel(p)): без
-- GetCanvas-гарда они сносят vbar, когда получают DScrollPanel.
if not has("parent.GetCanvas and parent:GetCanvas()", clientSrc) then
    badClear[#badClear + 1] = "renderLayoutWidgets(parent)"
end
if not has("p.GetCanvas and p:GetCanvas()", clientSrc) then
    badClear[#badClear + 1] = "clearPanel(p)"
end
ok(#badClear == 0, "нет очистки GetChildren() самого DScrollPanel (нужен GetCanvas())", table.concat(badClear, ", "))

--[[ 3D-ВЬЮПОРТ. cam.Start3D(eye, ang, fov, x, y, w, h): x,y — ЭКРАННЫЕ
     координаты. В Paint панели это не (0,0) — иначе сцена рисуется в
     левом верхнем углу всего экрана (оси «улетали» на холст, панель
     оставалась пустой). Нужен panel:LocalToScreen(0,0). ]]
ok(has("local sx, sy = self:LocalToScreen(0, 0)", clientSrc),
    "вьюпорт: сцена рисуется в координатах панели (LocalToScreen)")
ok(has("cam.Start3D(eye, ang, 55, sx or 0, sy or 0", clientSrc),
    "вьюпорт: cam.Start3D получает sx,sy панели, а не (0,0)")
-- Dock(FILL) у вьюпорта должен создаваться ПОСЛЕ кнопок BOTTOM — иначе
-- вьюпорт занимает всю панель и кнопки ложатся поверх сцены.
local fillAt = has("vp:Dock(FILL)", clientSrc) and string.find(clientSrc, "vp:Dock(FILL)", 1, true) or 0
local moveAt = has("local modeMove = modeBtn(", clientSrc) and string.find(clientSrc, "local modeMove = modeBtn(", 1, true) or 0
ok(fillAt > moveAt, "вьюпорт: Dock(FILL) создаётся после кнопок BOTTOM")

--[[ 4) МАКЕТ/МЕНЮ/ШИРИНА. Боевой отчёт: «ТЕСТ ОКНА» сносил детей самого
     DFrame (заголовок + кнопки) → «dframe.lua:246 Tried to use a NULL
     Panel»; «attempt to call global 'DMenu' (a table value)» — глобал
     DMenu перекрыт сторонним аддоном; узкие карточки/палитра — подписи
     не влезали; невалидная модель обрывала рендер. ]]
ok(has("parent._asLayoutContent", clientSrc),
    "макет: контент-холдер — дети DFrame не сносятся (NULL Panel)")
ok(not has("= DMenu()", clientSrc),
    "меню создаются vgui.Create(\"DMenu\") — глобал DMenu может быть таблицей")
ok(has("util.IsValidModel", clientSrc),
    "вьюпорт: невалидная модель даёт каркас, а не ошибку render.Model")
ok(has("local function clipText", clientSrc),
    "надписи обрезаются по ширине через clipText (UTF-8, многоточие)")
ok(has("CARD_W, CARD_H, PORT = 300", clientSrc),
    "карточки шире (300) — подпись помещается")
ok(has("SetWide(280)", clientSrc),
    "палитра шире (280) — названия кнопок влезают")

--[[ 5) ОТДЕЛЬНЫЙ АДДОН. Владелец: «Аддон-студию вынести в отдельный
     аддон, из модуля GRM убрать». Файлы живут в addons/grm_addon_studio/
     и собираются отдельным архивом; в lua/autorun их быть не должно
     (иначе студия попадёт в grm_single_addon.zip второй раз). ]]
local function exists(p)
    local f = io.open(p, "rb")
    if not f then return false end
    f:close() return true
end
local hasAddonJson = exists("addons/grm_addon_studio/addon.json")
local hasAddonCl = exists("addons/grm_addon_studio/lua/autorun/client/cl_grm_addon_studio.lua")
local hasAddonSv = exists("addons/grm_addon_studio/lua/autorun/server/sv_grm_addon_studio.lua")
ok(hasAddonJson, "аддон: есть addon.json")
ok(hasAddonCl and hasAddonSv, "аддон: cl+sv на месте")
local inMainSh = exists("lua/autorun/sh_grm_addon_studio.lua")
local inMainCl = exists("lua/autorun/client/cl_grm_addon_studio.lua")
local inMainSv = exists("lua/autorun/server/sv_grm_addon_studio.lua")
ok(not inMainSh and not inMainCl and not inMainSv,
    "аддон: в lua/autorun файлов студии нет (не дублируется в основной сборке)")
ok(has("no_grm_persistence", serverSrc or ""), "аддон: без GRM.Persistence — честный отказ, не nil")

-- ══════════════ 14. РЕЕСТР ВИДОВ ВИДЖЕТА (без лестниц) ══════════════
--[[ Вид виджета описан ОДНОЙ строкой A.WidgetSpec, и это знание общее
     для генератора кода (sh_) и редактора (cl_). Раньше знание было
     размазано по шести местам: список видов, значения по умолчанию,
     поля инспектора, ветка в генераторе, ветка выбора VGUI-класса и
     ветка настройки виджета. Добавить вид = шесть правок в двух файлах;
     забытая правка означала «виджет есть в редакторе, но не попадает в
     сгенерированный код» — и это замечали уже на готовом аддоне.

     Проверяем ЦИКЛОМ по всем видам: у каждого есть класс, переменная,
     размеры и генератор кода, каждый реально попадает в вывод, и на
     каждый настраиваемый вид есть обработчик в клиентском диспетчере. ]]
-- clientSrc уже прочитан выше (раздел 13) — второй раз не читаем.

ok(istable(A.WidgetSpec) and isfunction(A.Widget), "реестр A.WidgetSpec и A.Widget на месте")
ok(clientSrc:find("WIDGET_APPLY", 1, true) ~= nil,
    "клиент настраивает виджеты таблицей-диспетчером WIDGET_APPLY")
ok(clientSrc:find('if w.kind == "button" then', 1, true) == nil,
    "лестница `if w.kind ==` в клиенте не вернулась")

-- Виды, у которых нет настраиваемых свойств, обработчика не требуют.
local NO_APPLY = { panel = true }

for _, kindRow in ipairs(A.WidgetKinds) do
    local id = kindRow.id
    local spec = A.Widget(id)
    ok(istable(spec) and isstring(spec.class) and spec.class ~= "",
        ("вид %s: задан VGUI-класс"):format(id))
    ok(isstring(spec.var) and tonumber(spec.w) and tonumber(spec.h),
        ("вид %s: заданы переменная и размеры по умолчанию"):format(id))
    ok(isfunction(spec.code), ("вид %s: умеет дописать себя в код"):format(id))

    local code = table.concat(A.LayoutToCode({ w = 400, h = 300,
        widgets = { { kind = id, x = 10, y = 10 } } }, {}), "\n")
    ok(code:find('vgui.Create("' .. spec.class .. '"', 1, true) ~= nil,
        ("вид %s: попадает в сгенерированный код как %s"):format(id, spec.class))

    if not NO_APPLY[id] then
        ok(clientSrc:find("    " .. id .. " = function(ctrl, w)", 1, true) ~= nil,
            ("вид %s: есть обработчик в клиентском диспетчере"):format(id))
    end
end

-- Неизвестный вид не должен ронять генератор и не должен исчезать молча.
local fallback = A.Widget("выдуманный_вид")
ok(fallback == A.WidgetSpec.panel, "неизвестный вид сводится к панели-заглушке")

print(string.format("\nADDON STUDIO: %d/%d, провалов: %d", total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
