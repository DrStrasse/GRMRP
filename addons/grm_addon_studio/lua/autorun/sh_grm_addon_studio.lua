--[[--------------------------------------------------------------------
    GRM Addon Studio v1.0 — визуальный редактор-«студия аддона».

    ЗАКАЗ ВЛАДЕЛЬЦА (01.09.2026):

      «Студия с графами, с визуалом с 3д моделями со считыванием аддонов,
       пропов и т.д. — студия создания аддона. Визуальный редактор, в
       котором куча блоков, условий, которые визуально соединяются,
       настраивается цвет-материал, положение, звуки, модели, функционал.
       Когда я собрал примерный визуальный образ, студия компилирует
       образ аддона в виде отдельных строк кода и я эти строки могу
       копировать и направлять тебе, чтобы ты, имея готовое представление,
       более точечно создал мне ядро цитадели, визуальный экран или
       компьютер с полноценным рабочим меню.»

    ЧТО ЗДЕСЬ. Общая часть трёх файлов модуля:

      lua/autorun/sh_grm_addon_studio.lua          — ЭТОТ ФАЙЛ:
          каталог узлов (defs), манифест проекта, нормализация,
          генератор GLua-кода. Чистые функции: никакого surface,
          никакого render — работает в стендах под LuaJIT.
      lua/autorun/server/sv_grm_addon_studio.lua   — права, сеть, слепок
          каталога сущностей, сохранение проектов и снимков.
      lua/autorun/client/cl_grm_addon_studio.lua   — окно: граф, палитра,
          инспектор, 3D-вьюпорт с гизмо, компиляция/копирование.

    ГЛАВНАЯ ИДЕЯ ФОРМАТА. Проект — это НЕ код. Это данные: узлы с полями
    и связи между портами. Генератор раскладывает данные в читаемый
    черновик GLua (по узлу — строки, по связи — пометка, какой выход
    куда приходит). Владелец копирует текст и присылает агенту: агент
    видит и картину (манифест), и намерение (черновик кода), и делает
    реальный модуль точечно, а не догадками.

    ХРАНЕНИЕ. data/grm_studio/<slug>.json через GRM.Persistence.
    Снимки: data/grm_studio/shots/<slug>_<n>.jpg.
----------------------------------------------------------------------]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.AddonStudio = GRM.AddonStudio or {}
local A = GRM.AddonStudio
A.Version = "1.0.0"
A.Format = "grm_addon_studio"
A.FormatVersion = 1
A.MaxNodes = 200
A.MaxEdges = 600
A.MaxTextLen = 8000
A.ProjDir = "grm_studio"
A.ShotsDir = "grm_studio/shots"

-----------------------------------------------------------------------
-- ПРИМИТИВЫ МАНИФЕСТА (детерминированный вывод)
-----------------------------------------------------------------------
--[[ dump. Свой сериализатор, а не util.TableToJSON: стенды должны гонять
     генератор без GMod-заглушек, а вывод — быть стабильным (сортировка
     ключей, фиксированный формат чисел). %q в LuaJIT даёт валидную
     строку и для кавычек, и для перевода строк. ]]
function A.Dump(v, indent)
    indent = indent or ""
    local t = type(v)
    if t == "nil" then return "nil" end
    if t == "boolean" then return v and "true" or "false" end
    if t == "number" then
        if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
        return string.format("%.10g", v)
    end
    if t == "string" then return string.format("%q", v) end
    if t ~= "table" then return tostring(v) end

    --[[ Массив: индексы 1..n без дыр. ВАЖНО: таблица со строковыми
         ключами в LuaJIT имеет #v == 0, и старый вариант «n == #v»
         принимал её за ПУСТОЙ МАССИВ — узлы сериализовались как {}. ]]
    local n = #v
    local isArray = n > 0
    if isArray then
        for i = 1, n do
            if v[i] == nil then isArray = false break end
        end
    end
    if isArray then
        local parts = {}
        for i = 1, n do parts[i] = A.Dump(v[i], indent .. "    ") end
        return "{\n" .. indent .. "    " .. table.concat(parts, ",\n" .. indent .. "    ")
            .. ",\n" .. indent .. "}"
    end

    -- Словарь: стабильный порядок ключей.
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
        parts[#parts + 1] = "[" .. A.Dump(k) .. "] = " .. A.Dump(v[k], indent .. "    ")
    end
    if #parts == 0 then return "{}" end
    return "{\n" .. indent .. "    " .. table.concat(parts, ",\n" .. indent .. "    ")
        .. ",\n" .. indent .. "}"
end

--[[ Замена «недопустимых» символов с сохранением кириллицы.
     `%w` в LuaJIT — только латиница/цифры: "Цитадель" целиком ушёл бы
     в подчёркивания. Баг из стенда: Ident("Студия Аддонов!") давал
     "block". Держим любой байт >= 128 (UTF-8) как есть, остальное — "_". ]]
local function slugChars(s)
    s = tostring(s or "")
    s = string.lower(s)
    s = string.gsub(s, "[^%w_%-]", function(ch)
        if ch:byte() >= 128 then return ch end
        return "_"
    end)
    s = string.gsub(s, "_+", "_")
    s = string.gsub(s, "^_+", "")
    s = string.gsub(s, "_+$", "")
    return s
end

--- Идентификатор из произвольного имени (для timer/hook/переменных).
function A.Ident(name, prefix)
    local s = slugChars(name)
    if s == "" then s = "block" end
    s = string.sub(s, 1, 24)
    if prefix and prefix ~= "" then s = prefix .. "_" .. s end
    return s
end

--- Безопасный slug имени проекта (для имени файла).
function A.Slug(name)
    local s = slugChars(name)
    if s == "" then s = "project_" .. tostring(os.time() % 1000000) end
    return string.sub(s, 1, 48)
end

local function clone(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = clone(v) end
    return out
end
A.Clone = clone

--[[ Объявлена ДО каталога узлов: строки кода узла `variable` зовут её из
     замыкания. Если объявить ниже, вызов читает ГЛОБАЛ и падает в бою
     (см. sim_global_hygiene — чтение local-имени выше объявления). ]]
local function numberToString(v)
    if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
    return string.format("%.10g", v)
end
A.Number = numberToString

-----------------------------------------------------------------------
-- КАТАЛОГ УЗЛОВ
-----------------------------------------------------------------------
--[[ Одна таблица на тип узла: подпись для палитры, поля инспектора,
     порты, подпись карточки и строки кода. Добавить тип — дописать
     элемент сюда; палитра, инспектор и генератор строятся из этого.
     Цвета — числами {r,g,b}, а не Color: общая часть без Derma. ]]
A.Defs = {}

local function def(entry)
    entry.ports = entry.ports or { ["in"] = { "in" }, out = { "out" } }
    entry.fields = entry.fields or {}
    A.Defs[#A.Defs + 1] = entry
end

local COL3 = function(r, g, b) return { r = r, g = g, b = b } end
local POS = function(x, y, z) return { x = x, y = y, z = z } end

--[[ Общие поля визуальных узлов. Триада векторных полей хранится
     числами и раскладывается в Vector(...)/Angle(...) генератором. ]]
local function visualFields(extra)
    local f = {
        { key = "model",  label = "Модель",    type = "model",    def = "models/props_c17/chair02a.mdl" },
        { key = "pos",    label = "Позиция",   type = "vector",   def = POS(0, 0, 0) },
        { key = "ang",    label = "Поворот",   type = "angle",    def = { p = 0, y = 0, r = 0 } },
        { key = "scale",  label = "Масштаб",   type = "number",   def = 1, min = 0.01, max = 10 },
        { key = "color",  label = "Цвет",      type = "color",    def = COL3(255, 255, 255) },
        { key = "material", label = "Материал", type = "material", def = "" },
        { key = "skin",   label = "Skin",      type = "number",   def = 0, min = 0, max = 16 },
    }
    if extra then for _, e in ipairs(extra) do f[#f + 1] = e end end
    return f
end

local function vectorToCtor(v, ctor)
    v = istable(v) and v or {}
    return string.format("%s(%s, %s, %s)", ctor, tonumber(v.x) or 0, tonumber(v.y) or 0, tonumber(v.z) or 0)
end

local function angleToCtor(a)
    a = istable(a) and a or {}
    return string.format("Angle(%s, %s, %s)", tonumber(a.p) or 0, tonumber(a.y) or 0, tonumber(a.r) or 0)
end

-- ВИЗУАЛ -----------------------------------------------------------------
def({
    id = "model", name = "МОДЕЛЬ", cat = "visual", color = COL3(70, 170, 250),
    hint = "Спавн модели: модель, позиция, поворот, масштаб, цвет, материал.",
    fields = visualFields(),
    caption = function(n) local d = n.data or {}
        return tostring(d.model or "") ~= "" and string.sub(tostring(d.model), 16) or "Модель не выбрана" end,
    code = function(n)
        local d = n.data or {}
        local out = { "-- Спавн модели: " .. tostring(d.model or "?") }
        out[#out + 1] = 'local ent = ents.Create("prop_physics") -- узел ' .. n.uid
        out[#out + 1] = 'ent:SetModel(' .. string.format("%q", tostring(d.model or "")) .. ')'
        out[#out + 1] = "ent:SetPos(" .. vectorToCtor(d.pos, "Vector") .. ")"
        out[#out + 1] = "ent:SetAngles(" .. angleToCtor(d.ang) .. ")"
        if tonumber(d.scale) and tonumber(d.scale) ~= 1 then
            out[#out + 1] = "ent:SetModelScale(" .. string.format("%.4g", tonumber(d.scale)) .. ", true)"
        end
        local c = d.color or {}
        out[#out + 1] = string.format("ent:SetColor(Color(%d, %d, %d))", tonumber(c.r) or 255, tonumber(c.g) or 255, tonumber(c.b) or 255)
        if tostring(d.material or "") ~= "" then
            out[#out + 1] = "ent:SetMaterial(" .. string.format("%q", tostring(d.material)) .. ")"
        end
        if tonumber(d.skin) and tonumber(d.skin) ~= 0 then
            out[#out + 1] = "for i = 0, (" .. string.format("%d", tonumber(d.skin)) .. ") do ent:SetSkin(i) end"
        end
        out[#out + 1] = "ent:Spawn()"
        out[#out + 1] = "ent:GetPhysicsObject():Wake() -- физика"
        out[#out + 1] = "-- ВЫХОД: ent (модель в мире)"
        return out
    end,
})

def({
    id = "prop", name = "ПРОП", cat = "visual", color = COL3(70, 170, 250),
    hint = "Проп как объект: модель с коллизией, вес, твёрдость.",
    fields = visualFields({
        { key = "solid", label = "Тип коллизии", type = "select", def = "vphysics",
          opts = { { "vphysics", "Vphysics" }, { "bbox", "BBox" }, { "none", "Нет" } } },
    }),
    caption = function(n) local d = n.data or {}
        return tostring(d.model or "") ~= "" and ("проп " .. string.sub(tostring(d.model), 16)) or "Проп не выбран" end,
    code = function(n)
        local d = n.data or {}
        local out = { "-- Проп: " .. tostring(d.model or "?") }
        out[#out + 1] = 'local ent = ents.Create("prop_physics")'
        out[#out + 1] = "ent:SetModel(" .. string.format("%q", tostring(d.model or "")) .. ")"
        out[#out + 1] = "ent:SetPos(" .. vectorToCtor(d.pos, "Vector") .. ")"
        out[#out + 1] = "ent:SetAngles(" .. angleToCtor(d.ang) .. ")"
        local solid = tostring(d.solid or "vphysics")
        if solid == "bbox" then out[#out + 1] = "ent:SetSolid(SOLID_BBOX)"
        elseif solid == "none" then out[#out + 1] = "ent:SetSolid(SOLID_NONE)" end
        out[#out + 1] = "ent:Spawn()"
        out[#out + 1] = "-- ВЫХОД: ent"
        return out
    end,
})

def({
    id = "entity", name = "ЭНТИТИ", cat = "visual", color = COL3(120, 130, 250),
    hint = "Класс энтити (grm_comp_police, grm_alarm_hub, свет…). Считывает аддоны.",
    fields = {
        { key = "class", label = "Класс", type = "class", def = "grm_comp_police" },
        { key = "pos", label = "Позиция", type = "vector", def = POS(0, 0, 0) },
        { key = "ang", label = "Поворот", type = "angle", def = { p = 0, y = 0, r = 0 } },
        { key = "kv", label = "KeyValues (key=value, строка на пару)", type = "code", def = "" },
    },
    caption = function(n) local d = n.data or {}
        return tostring(d.class or "") ~= "" and tostring(d.class) or "Класс не выбран" end,
    code = function(n)
        local d = n.data or {}
        local out = { "-- Энтити класса: " .. tostring(d.class or "?") }
        out[#out + 1] = 'local ent = ents.Create(' .. string.format("%q", tostring(d.class or "")) .. ')'
        out[#out + 1] = "ent:SetPos(" .. vectorToCtor(d.pos, "Vector") .. ")"
        out[#out + 1] = "ent:SetAngles(" .. angleToCtor(d.ang) .. ")"
        if tostring(d.kv or "") ~= "" then
            for line in tostring(d.kv):gmatch("[^\r\n]+") do
                local k, v = string.match(line, "^%s*([%w_]+)%s*=%s*(.+)$")
                if k then out[#out + 1] = "ent:SetKeyValue(" .. string.format("%q", k) .. ", " .. string.format("%q", v) .. ")" end
            end
        end
        out[#out + 1] = "ent:Spawn()"
        out[#out + 1] = "-- ВЫХОД: ent (готовый объект)"
        return out
    end,
})

def({
    id = "screen", name = "ЭКРАН", cat = "visual", color = COL3(200, 120, 240),
    hint = "Визуальный экран/RenderTarget: на сущности или 3D2D. Выводит страницу-меню.",
    fields = {
        { key = "size", label = "Размер RT", type = "select", def = "512x256",
          opts = { { "512x256", "512x256" }, { "1024x512", "1024x512" }, { "256x128", "256x128" } } },
        { key = "mode", label = "Режим", type = "select", def = "paint",
          opts = { { "paint", "Панель (Derma)" }, { "html", "HTML/DHTML" }, { "mat", "Текстура-материал" } } },
        { key = "page", label = "Страница (id узла menu/page)", type = "text", def = "" },
        { key = "glow", label = "Свечение", type = "check", def = true },
    },
    caption = function(n) local d = n.data or {}
        return tostring(d.size or "512x256") .. (tostring(d.page or "") ~= "" and (" → " .. tostring(d.page)) or "") end,
    code = function(n)
        local d = n.data or {}
        local out = {
            "-- Экран: RT " .. tostring(d.size or "512x256") .. ", режим " .. tostring(d.mode or "paint"),
            'local rt = render.CreateRenderTarget("as_rt_' .. A.Ident(tostring(d.page or "screen")) .. '")',
            "local w, h = " .. string.gsub(tostring(d.size or "512x256"), "x", ", "),
            "hook.Add(\"RenderScene\", \"as_rt\", function()",
            "    render.PushRenderTarget(rt)",
            "    render.Clear(6, 10, 16, 255)",
            "    -- Сюда рисуется страница: paint-меню / DHTML / материал",
            "    render.PopRenderTarget()",
            "end)",
            "-- На сущности: привязать rt к чему-то, например к entity.Atlas:",
            '-- ent:SetMaterial(Material("' .. tostring(d.page or "page") .. '")) -- уточнить при реализации',
        }
        if d.glow ~= false then
            out[#out + 1] = "-- Свечение: динамический свет/аддитив рядом с экраном"
        end
        return out
    end,
})

def({
    id = "light", name = "СВЕТ", cat = "visual", color = COL3(250, 200, 90),
    hint = "Динамический свет: цвет, дальность, яркость, режим.",
    fields = {
        { key = "pos", label = "Позиция", type = "vector", def = POS(0, 40, 0) },
        { key = "color", label = "Цвет", type = "color", def = COL3(255, 230, 180) },
        { key = "range", label = "Дальность", type = "number", def = 300, min = 10, max = 2000 },
        { key = "brightness", label = "Яркость", type = "number", def = 1, min = 0, max = 5 },
        { key = "dynamic", label = "Динамический (движок)", type = "check", def = true },
    },
    caption = function(n) local d = n.data or {}
        return "дальность " .. tostring(tonumber(d.range) or 300) .. ", яркость " .. tostring(tonumber(d.brightness) or 1) end,
    code = function(n)
        local d = n.data or {}
        local c = d.color or {}
        local out = {
            "-- Свет: " .. tostring(tonumber(d.range) or 300) .. " ед., " .. tostring(tonumber(d.brightness) or 1),
            'local l = ents.Create("light")',
            "l:SetPos(" .. vectorToCtor(d.pos, "Vector") .. ")",
            string.format("l:SetKeyValue(\"color\", \"%d %d %d\")", tonumber(c.r) or 255, tonumber(c.g) or 255, tonumber(c.b) or 255),
            string.format("l:SetKeyValue(\"brightness\", \"%.2f\")", tonumber(d.brightness) or 1),
            string.format("l:SetKeyValue(\"distance\", \"%d\")", tonumber(d.range) or 300),
            "l:Spawn()",
        }
        if d.dynamic ~= false then
            out[#out + 1] = "-- Динамическая подсветка (движок сам учитывает угол) — либо через DynamicLight в Think"
        end
        return out
    end,
})

def({
    id = "postprocess", name = "ПОСТОБРАБОТКА", cat = "visual", color = COL3(240, 130, 150),
    hint = "Пост-обработка: цветокоррекция/блюр/размытие для сцены или экрана.",
    fields = {
        { key = "mode", label = "Тип", type = "select", def = "colormod",
          opts = { { "colormod", "ColorModify" }, { "blur", "Размытие RT" }, { "mono", "Монохром" } } },
        { key = "r", label = "R", type = "number", def = 1, min = 0, max = 2 },
        { key = "g", label = "G", type = "number", def = 1, min = 0, max = 2 },
        { key = "b", label = "B", type = "number", def = 1, min = 0, max = 2 },
        { key = "a", label = "A", type = "number", def = 1, min = 0, max = 2 },
        { key = "blur", label = "Сила блюра", type = "number", def = 2, min = 0, max = 16 },
    },
    caption = function(n) local d = n.data or {}
        return "тип " .. tostring(d.mode or "colormod") end,
    code = function(n)
        local d = n.data or {}
        local out = { "-- Пост-обработка: " .. tostring(d.mode or "colormod") }
        if tostring(d.mode or "colormod") == "colormod" then
            out[#out + 1] = string.format("render.PushColorModify(0, { r = %.3f, g = %.3f, b = %.3f, a = %.3f })",
                tonumber(d.r) or 1, tonumber(d.g) or 1, tonumber(d.b) or 1, tonumber(d.a) or 1)
            out[#out + 1] = "-- render.PopColorModify() после отрисовки сцены"
        elseif tostring(d.mode) == "mono" then
            out[#out + 1] = "-- Монохром: серые каналы вместо цветных"
            out[#out + 1] = string.format("render.PushColorModify(0, { r = %.3f, g = %.3f, b = %.3f, a = 1 })",
                (tonumber(d.r) or 1) * 0.5 + 0.5, (tonumber(d.g) or 1) * 0.5 + 0.5, (tonumber(d.b) or 1) * 0.5 + 0.5)
        else
            out[#out + 1] = string.format("local blur = render.BlurRenderTarget(rt, math.max(0, %d), math.max(0, %d))",
                math.floor(tonumber(d.blur) or 2), math.floor(tonumber(d.blur) or 2))
            out[#out + 1] = "-- Применять блюр к RT экрана при каждом кадре"
        end
        return out
    end,
})

-- МЕДИА ----------------------------------------------------------------
def({
    id = "photo", name = "ФОТО", cat = "media", color = COL3(120, 210, 180),
    hint = "Фотоснимок (из студии/GRM.Photo): путь, рамка, вывод на сущность.",
    fields = {
        { key = "path", label = "Файл (data/…)", type = "photo", def = "" },
        { key = "title", label = "Подпись", type = "text", def = "" },
        { key = "w", label = "Ширина", type = "number", def = 256, min = 64, max = 1024 },
        { key = "h", label = "Высота", type = "number", def = 256, min = 64, max = 1024 },
    },
    caption = function(n) local d = n.data or {}
        return tostring(d.path or "") ~= "" and ("кадр: " .. string.sub(tostring(d.path), -32)) or "Фото не снято" end,
    code = function(n)
        local d = n.data or {}
        local out = { "-- Фото: " .. tostring(d.path or "(нет кадра)") }
        if tostring(d.path or "") ~= "" then
            out[#out + 1] = string.format("-- Кадр %sx%s: материал из data/ или прямоугольник на сущности/панели",
                tonumber(d.w) or 256, tonumber(d.h) or 256)
            out[#out + 1] = "-- Вариант: local mat = Material(\"data/" .. tostring(d.path) .. "\") -- драфт, уточнить"
        end
        return out
    end,
})

def({
    id = "sound", name = "ЗВУК", cat = "media", color = COL3(240, 160, 240),
    hint = "Звук: путь, громкость, зацикливание, радиус.",
    fields = {
        { key = "sound", label = "Звук (sound/…)", type = "sound", def = "" },
        { key = "vol", label = "Громкость", type = "number", def = 1, min = 0, max = 1 },
        { key = "pitch", label = "Тон", type = "number", def = 100, min = 50, max = 200 },
        { key = "loop", label = "Зациклить", type = "check", def = false },
        { key = "pos", label = "Позиция", type = "vector", def = POS(0, 0, 0) },
    },
    caption = function(n) local d = n.data or {}
        return tostring(d.sound or "") ~= "" and ("♪ " .. string.sub(tostring(d.sound), 7)) or "Звук не выбран" end,
    code = function(n)
        local d = n.data or {}
        local out = { "-- Звук: " .. tostring(d.sound or "(нет)") }
        if tostring(d.sound or "") ~= "" then
            out[#out + 1] = "sound.Play(" .. string.format("%q", tostring(d.sound))
                .. ", " .. vectorToCtor(d.pos, "Vector") .. ", " .. string.format("%.2f", tonumber(d.vol) or 1)
                .. ", " .. string.format("%d", tonumber(d.pitch) or 100) .. ")"
            if d.loop then
                out[#out + 1] = "-- Зацикливание: звук хранится в SoundEmit / SoundPatch (LoopStart/LoopEnd)"
            end
        end
        return out
    end,
})

-- ЛОГИКА ---------------------------------------------------------------
def({
    id = "variable", name = "ПЕРЕМЕННАЯ", cat = "logic", color = COL3(250, 170, 80),
    hint = "Именованное значение: строка, число, цвет, позиция.",
    fields = {
        { key = "name", label = "Имя", type = "text", def = "value" },
        { key = "value", label = "Значение (строка/число)", type = "long", def = "0" },
    },
    caption = function(n) local d = n.data or {}
        return tostring(d.name or "value") .. " = " .. tostring(d.value or "") end,
    code = function(n)
        local d = n.data or {}
        local num = tonumber(d.value)
        local val = num and numberToString(num) or string.format("%q", tostring(d.value or ""))
        return { "local " .. A.Ident(d.name, "as") .. " = " .. val,
            "-- ВЫХОД: " .. A.Ident(d.name, "as") }
    end,
})

def({
    id = "condition", name = "УСЛОВИЕ", cat = "logic", color = COL3(235, 90, 90),
    hint = "Развилка: сравнение, дистанция, фракция, клавиша, право. Да/Нет.",
    ports = { ["in"] = { "in" }, out = { "out", "else" } },
    fields = {
        { key = "type", label = "Проверка", type = "select", def = "compare",
          opts = { { "compare", "Сравнение" }, { "distance", "Дистанция" }, { "faction", "Фракция" },
                   { "key", "Клавиша" }, { "capability", "Право GRM" } } },
        { key = "a", label = "A", type = "long", def = "" },
        { key = "op", label = "Оператор", type = "select", def = "==",
          opts = { { "==", "==" }, { "~=", "~=" }, { ">", ">" }, { "<", "<" }, { ">=", ">=" }, { "<=", "<=" } } },
        { key = "b", label = "B", type = "long", def = "" },
        { key = "dist", label = "Дистанция (ед.)", type = "number", def = 300, min = 1, max = 5000 },
    },
    caption = function(n) local d = n.data or {}
        local t = d.type or "compare"
        if t == "distance" then return "дистанция < " .. tostring(tonumber(d.dist) or 300) end
        if t == "faction" then return "фракция = " .. tostring(d.a or "") end
        if t == "key" then return "клавиша " .. tostring(d.a or "") end
        if t == "capability" then return "право " .. tostring(d.a or "") end
        return tostring(d.a or "") .. " " .. tostring(d.op or "==") .. " " .. tostring(d.b or "") end,
    code = function(n)
        local d = n.data or {}
        local t = d.type or "compare"
        if t == "distance" then
            return { string.format("if (A:GetPos():DistToSqr(B:GetPos()) < %d^2) then -- ДА",
                tonumber(d.dist) or 300), "    -- ВЫХОД: 'out'", "else -- НЕТ", "    -- ВЫХОД: 'else'", "end" }
        end
        if t == "faction" then
            return { "if (string.lower(ply:GetNWString(\"GRM_Faction\", \"\")) == "
                .. string.format("%q", string.lower(tostring(d.a or ""))) .. ") then -- ДА",
                "    -- ВЫХОД: 'out'", "else -- НЕТ", "    -- ВЫХОД: 'else'", "end" }
        end
        if t == "key" then
            return { "if (ply:KeyDown(" .. string.upper(tostring(d.a or "IN_USE")) .. ")) then -- ДА",
                "    -- ВЫХОД: 'out'", "else -- НЕТ", "    -- ВЫХОД: 'else'", "end" }
        end
        if t == "capability" then
            return { "if (GRM.Access and GRM.Access.Check(ply, " .. string.format("%q", tostring(d.a or "")) .. ")) then -- ДА",
                "    -- ВЫХОД: 'out'", "else -- НЕТ", "    -- ВЫХОД: 'else'", "end" }
        end
        return { "if ((" .. tostring(d.a or "") .. ") " .. tostring(d.op or "==") .. " (" .. tostring(d.b or "") .. ")) then -- ДА",
            "    -- ВЫХОД: 'out'", "else -- НЕТ", "    -- ВЫХОД: 'else'", "end" }
    end,
})

def({
    id = "math", name = "МАТЕМАТИКА", cat = "logic", color = COL3(190, 160, 250),
    hint = "Операция над значениями, результат в переменную.",
    fields = {
        { key = "name", label = "Результат", type = "text", def = "result" },
        { key = "a", label = "A", type = "long", def = "0" },
        { key = "op", label = "Оператор", type = "select", def = "+",
          opts = { { "+", "+" }, { "-", "-" }, { "*", "*" }, { "/", "/" }, { "%", "%" }, { "min", "min" }, { "max", "max" } } },
        { key = "b", label = "B", type = "long", def = "0" },
    },
    caption = function(n) local d = n.data or {}
        return tostring(d.a or "") .. " " .. tostring(d.op or "+") .. " " .. tostring(d.b or "") .. " → " .. tostring(d.name or "result") end,
    code = function(n)
        local d = n.data or {}
        local op = tostring(d.op or "+")
        local expr
        if op == "min" or op == "max" then expr = "math." .. op .. "(" .. tostring(d.a or "0") .. ", " .. tostring(d.b or "0") .. ")"
        else expr = "(" .. tostring(d.a or "0") .. ") " .. op .. " (" .. tostring(d.b or "0") .. ")" end
        return { "local " .. A.Ident(d.name, "as") .. " = " .. expr,
            "-- ВЫХОД: " .. A.Ident(d.name, "as") }
    end,
})

def({
    id = "timer", name = "ТАЙМЕР", cat = "logic", color = COL3(150, 220, 130),
    hint = "Отложенное/повторяемое действие. Выход — тело таймера.",
    ports = { ["in"] = { "in" }, out = { "out", "fire" } },
    fields = {
        { key = "name", label = "Имя", type = "text", def = "timer" },
        { key = "delay", label = "Задержка (с)", type = "number", def = 1, min = 0, max = 3600 },
        { key = "repeats", label = "Повторов", type = "number", def = 0, min = 0, max = 100 },
    },
    caption = function(n) local d = n.data or {}
        return tostring(d.name or "timer") .. " @ " .. tostring(tonumber(d.delay) or 1) .. "с" end,
    code = function(n)
        local d = n.data or {}
        return { "timer.Create(" .. string.format("%q", A.Ident(d.name, "as_timer")) .. ", " .. numberToString(tonumber(d.delay) or 1)
            .. ", " .. numberToString(math.floor(tonumber(d.repeats) or 0)) .. ", function()",
            "    -- ТЕЛО: выход 'fire'", "end)" }
    end,
})

def({
    id = "hook", name = "ХУК", cat = "logic", color = COL3(120, 200, 220),
    hint = "Событие движка/GMod: PlayerSay, InitPostEntity, Think…",
    fields = {
        { key = "event", label = "Событие", type = "text", def = "InitPostEntity" },
        { key = "name", label = "Имя хука", type = "text", def = "hook" },
        { key = "realm", label = "Сторона", type = "select", def = "server",
          opts = { { "server", "Сервер" }, { "client", "Клиент" } } },
    },
    caption = function(n) local d = n.data or {}
        return tostring(d.event or "") .. " (" .. tostring(d.realm or "server") .. ")" end,
    code = function(n)
        local d = n.data or {}
        return { "hook.Add(" .. string.format("%q", tostring(d.event or "")) .. ", " .. string.format("%q", A.Ident(d.name, "as_hook")) .. ", function(...)",
            "    -- ТЕЛО: выход 'out'", "end)" }
    end,
})

def({
    id = "netmsg", name = "NET-СООБЩЕНИЕ", cat = "logic", color = COL3(140, 190, 250),
    hint = "Сообщение клиент↔сервер: имя, направление, полезная нагрузка.",
    fields = {
        { key = "name", label = "Имя сообщения", type = "text", def = "GRM_AS_MyMsg" },
        { key = "dir", label = "Направление", type = "select", def = "c2s",
          opts = { { "c2s", "Клиент → Сервер" }, { "s2c", "Сервер → Клиент" } } },
        { key = "payload", label = "Полезная нагрузка (намерение)", type = "code", def = "net.WriteString(...)" },
    },
    caption = function(n) local d = n.data or {}
        return tostring(d.name or "") .. " (" .. tostring(d.dir or "c2s") .. ")" end,
    code = function(n)
        local d = n.data or {}
        local out = { "util.AddNetworkString(" .. string.format("%q", tostring(d.name or "")) .. ")" }
        if tostring(d.dir or "c2s") == "c2s" then
            out[#out + 1] = "net.Start(" .. string.format("%q", tostring(d.name or "")) .. ")"
            if tostring(d.payload or "") ~= "" then out[#out + 1] = "    " .. tostring(d.payload) end
            out[#out + 1] = "net.SendToServer()"
        else
            out[#out + 1] = "net.Receive(" .. string.format("%q", tostring(d.name or "")) .. ", function(len, ply)",
                "    -- ТЕЛО: выход 'out'", "end)"
        end
        return out
    end,
})

def({
    id = "eval", name = "КОД", cat = "logic", color = COL3(160, 170, 185),
    hint = "Произвольный GLua-код (строки). Пройдёт в черновик как есть.",
    fields = {
        { key = "code", label = "Код (GLua)", type = "code", def = "-- ваш код\nprint(\"hi\")" },
    },
    caption = function(n) local d = n.data or {}
        local first = tostring(d.code or ""):match("^%s*([^\n]+)")
        return first or "Код" end,
    code = function(n)
        local out = { "-- КОД (как введён):" }
        for line in tostring((n.data or {}).code or ""):gmatch("[^\r\n]+") do out[#out + 1] = "    " .. line end
        return out
    end,
})

def({
    id = "merge", name = "СЛИЯНИЕ", cat = "logic", color = COL3(130, 140, 150),
    hint = "Сходятся несколько входов в один выход (порядок).",
    ports = { ["in"] = { "a", "b", "c" }, out = { "out" } },
    fields = {},
    caption = function() return "слияние линий" end,
    code = function() return { "-- СЛИЯНИЕ: линии ниже идут последовательно" } end,
})

-- UI -------------------------------------------------------------------
def({
    id = "menu", name = "МЕНЮ", cat = "ui", color = COL3(80, 190, 160),
    hint = "Окно Derma: заголовок, размер, кнопки, поля, список.",
    fields = {
        { key = "title", label = "Заголовок", type = "text", def = "МЕНЮ" },
        { key = "w", label = "Ширина", type = "number", def = 560, min = 200, max = 1920 },
        { key = "h", label = "Высота", type = "number", def = 400, min = 200, max = 1200 },
        { key = "tabs", label = "Вкладки (строка через ;)", type = "text", def = "" },
    },
    caption = function(n) local d = n.data or {}
        return tostring(d.title or "МЕНЮ") .. " " .. tostring(tonumber(d.w) or 560) .. "x" .. tostring(tonumber(d.h) or 400) end,
    code = function(n)
        local d = n.data or {}
        local out = { "-- Меню: " .. tostring(d.title or "МЕНЮ") }
        out[#out + 1] = 'local f = vgui.Create("DFrame")'
        out[#out + 1] = "f:SetSize(" .. numberToString(tonumber(d.w) or 560) .. ", " .. numberToString(tonumber(d.h) or 400) .. ")"
        out[#out + 1] = "f:SetTitle(" .. string.format("%q", tostring(d.title or "МЕНЮ")) .. ")"
        out[#out + 1] = "f:Center() f:MakePopup()"
        if tostring(d.tabs or "") ~= "" then
            out[#out + 1] = "-- Вкладки: " .. tostring(d.tabs) .. " (реализовать DPropertySheet)"
        end
        out[#out + 1] = "-- Внутрь — узлы button/input/list/text (см. их строки)"
        return out
    end,
})

def({
    id = "page", name = "СТРАНИЦА", cat = "ui", color = COL3(90, 200, 200),
    hint = "Страница служебного компьютера: секции, действия, вывод.",
    fields = {
        { key = "title", label = "Название", type = "text", def = "Страница" },
        { key = "icon", label = "Иконка", type = "text", def = "icon16/page.png" },
        { key = "sections", label = "Секции (строки: кнопка|действие|описание)", type = "code", def = "" },
    },
    caption = function(n) local d = n.data or {}
        return tostring(d.title or "Страница") end,
    code = function(n)
        local d = n.data or {}
        local out = { "-- Страница: " .. tostring(d.title or "Страница"),
            "local PAGE = {", "    title = " .. string.format("%q", tostring(d.title or "Страница")) .. ","
            .. " icon = " .. string.format("%q", tostring(d.icon or "icon16/page.png")) .. ",", "    sections = {},", "}" }
        for line in tostring(d.sections or ""):gmatch("[^\r\n]+") do
            local btn, act, desc = string.match(line, "^%s*([^|]+)|([^|]+)|?(.*)$")
            if btn then
                out[#out + 1] = "table.insert(PAGE.sections, { kind = \"button\", label = "
                    .. string.format("%q", string.Trim(btn)) .. ", action = " .. string.format("%q", string.Trim(act or ""))
                    .. ", desc = " .. string.format("%q", string.Trim(desc or "")) .. " })"
            end
        end
        out[#out + 1] = "return PAGE"
        return out
    end,
})

def({
    id = "button", name = "КНОПКА", cat = "ui", color = COL3(90, 210, 120),
    hint = "Кнопка: подпись, стиль, действие (узел-цель).",
    fields = {
        { key = "label", label = "Подпись", type = "text", def = "ОК" },
        { key = "style", label = "Стиль", type = "select", def = "default",
          opts = { { "default", "Обычная" }, { "danger", "Опасная" }, { "gold", "Акцент" } } },
        { key = "target", label = "Цель (id узла)", type = "text", def = "" },
    },
    caption = function(n) local d = n.data or {}
        return tostring(d.label or "ОК") .. " → " .. tostring(d.target or "?") end,
    code = function(n)
        local d = n.data or {}
        return { 'local b = vgui.Create("DButton", parent)',
            "b:SetText(" .. string.format("%q", tostring(d.label or "ОК")) .. ")",
            "b.DoClick = function() -- цель: " .. tostring(d.target or "(не задана)") .. " end" }
    end,
})

def({
    id = "input", name = "ПОЛЕ ВВОДА", cat = "ui", color = COL3(140, 220, 210),
    hint = "Поле ввода: подпись, плейсхолдер, переменная.",
    fields = {
        { key = "label", label = "Подпись", type = "text", def = "Введите…" },
        { key = "placeholder", label = "Плейсхолдер", type = "text", def = "" },
        { key = "var", label = "Переменная", type = "text", def = "input_value" },
    },
    caption = function(n) local d = n.data or {}
        return tostring(d.label or "поле") .. " → " .. tostring(d.var or "var") end,
    code = function(n)
        local d = n.data or {}
        return { 'local e = vgui.Create("DTextEntry", parent)',
            "e:SetPlaceholderText(" .. string.format("%q", tostring(d.placeholder or "")) .. ")",
            "-- значение при Enter: local " .. A.Ident(d.var, "as") .. " = e:GetValue()" }
    end,
})

def({
    id = "list", name = "СПИСОК", cat = "ui", color = COL3(190, 150, 230),
    hint = "Список строк/колонок для меню.",
    fields = {
        { key = "columns", label = "Колонки (через ;)", type = "text", def = "Имя" },
        { key = "items", label = "Строки (столбец|столбец)", type = "code", def = "" },
    },
    caption = function(n) local d = n.data or {}
        return "колонок: " .. #(string.Explode(";", tostring(d.columns or ""))) end,
    code = function(n)
        local d = n.data or {}
        local out = { 'local l = vgui.Create("DListView", parent)' }
        for col in tostring(d.columns or ""):gmatch("[^;]+") do
            out[#out + 1] = "l:AddColumn(" .. string.format("%q", string.Trim(col)) .. ")"
        end
        for line in tostring(d.items or ""):gmatch("[^\r\n]+") do
            local cells = {}
            for c in line:gmatch("[^|]+") do cells[#cells + 1] = string.Trim(c) end
            out[#out + 1] = "l:AddLine(" .. table.concat(
                (function() local q = {} for _, c in ipairs(cells) do q[#q + 1] = string.format("%q", c) end return q end)(), ", ") .. ")"
        end
        return out
    end,
})

def({
    id = "text", name = "ТЕКСТ", cat = "ui", color = COL3(220, 220, 225),
    hint = "Статичный текст/подсказка на панели.",
    fields = {
        { key = "text", label = "Текст", type = "code", def = "Привет" },
        { key = "font", label = "Шрифт", type = "text", def = "DermaDefaultBold" },
    },
    caption = function(n) local d = n.data or {}
        return tostring(d.text or ""):sub(1, 40) end,
    code = function(n)
        local d = n.data or {}
        return { 'local l = vgui.Create("DLabel", parent)',
            "l:SetFont(" .. string.format("%q", tostring(d.font or "DermaDefaultBold")) .. ")",
            "l:SetText(" .. string.format("%q", tostring(d.text or "")) .. ")" }
    end,
})

-- ПРОЧЕЕ ---------------------------------------------------------------
def({
    id = "chatcmd", name = "ЧАТ-КОМАНДА", cat = "misc", color = COL3(250, 130, 90),
    hint = "Команда в чате/консоли: имя, права, действие.",
    fields = {
        { key = "name", label = "Команда (без /)", type = "text", def = "mycmd" },
        { key = "perm", label = "Право/доступ", type = "text", def = "SuperAdmin" },
        { key = "desc", label = "Описание", type = "text", def = "" },
    },
    caption = function(n) local d = n.data or {}
        return "/" .. tostring(d.name or "mycmd") end,
    code = function(n)
        local d = n.data or {}
        return { "concommand.Add(" .. string.format("%q", tostring(d.name or "mycmd")) .. ", function(ply, cmd, args)",
            "    -- доступ: " .. tostring(d.perm or "SuperAdmin"), "    -- ТЕЛО: выход 'out'", "end)" }
    end,
})

def({
    id = "interact", name = "ВЗАИМОДЕЙСТВИЕ", cat = "misc", color = COL3(250, 200, 70),
    hint = "Use/E: подсказка и действие на объекте/сущности.",
    fields = {
        { key = "object", label = "Объект (id узла)", type = "text", def = "" },
        { key = "prompt", label = "Подсказка", type = "text", def = "Использовать" },
        { key = "dist", label = "Дальность", type = "number", def = 160, min = 20, max = 1000 },
    },
    caption = function(n) local d = n.data or {}
        return tostring(d.prompt or "Использовать") .. " → " .. tostring(d.object or "?") end,
    code = function(n)
        local d = n.data or {}
        return { "-- Взаимодействие: " .. tostring(d.prompt or "Использовать") .. " (" .. tostring(d.object or "?") .. ")",
            "if (ply:KeyDown(IN_USE) and ply:GetPos():DistToSqr(obj:GetPos()) < " .. numberToString((tonumber(d.dist) or 160) ^ 2) .. ") then",
            "    -- ТЕЛО взаимодействия (выход 'out')", "end" }
    end,
})

def({
    id = "export", name = "ЭКСПОРТ", cat = "misc", color = COL3(255, 220, 120),
    hint = "Финальный узел: имя аддона/модуля, место под размещение (тул).",
    once = true,
    fields = {
        { key = "kind", label = "Что собираем", type = "select", def = "module",
          opts = { { "module", "Модуль (autorun)" }, { "entity", "Энтити-класс" },
                   { "screen", "Экран/интерфейс" }, { "computer", "Компьютер-страница" },
                   { "core", "Ядро (цитадель/логика)" }, { "prefab", "Размещаемый префаб" } } },
        { key = "name", label = "Имя", type = "text", def = "my_addon" },
        { key = "path", label = "Файл/папка", type = "text", def = "lua/autorun/sh_my_addon.lua" },
        { key = "placeable", label = "Конструктор размещения (тул + undo)", type = "check", def = true },
        { key = "tool", label = "Имя тула (grm_…)", type = "text", def = "grm_studio_my_addon" },
        { key = "toolcat", label = "Категория тула", type = "text", def = "GRM Studio" },
        { key = "notes", label = "Заметки агенту", type = "code", def = "" },
    },
    caption = function(n) local d = n.data or {}
        return "→ " .. tostring(d.name or "my_addon") .. " (" .. tostring(d.kind or "module") .. ")" end,
    code = function(n)
        local d = n.data or {}
        local out = { "-- ЭКСПОРТ: " .. tostring(d.name or ""), "-- Тип: " .. tostring(d.kind or "module"),
            "-- Путь: " .. tostring(d.path or "") }
        if d.placeable then
            out[#out + 1] = "-- РАЗМЕЩЕНИЕ: тул " .. tostring(d.tool or "grm_studio_prefab")
                .. ", категория " .. tostring(d.toolcat or "GRM Studio") .. " (см. раздел 5 — файл тула)"
        end
        if tostring(d.notes or "") ~= "" then
            out[#out + 1] = "-- ЗАМЕТКИ:"
            for line in tostring(d.notes):gmatch("[^\r\n]+") do out[#out + 1] = "--   " .. line end
        end
        out[#out + 1] = "-- Сюда агент встраивает готовый код по узлам выше"
        return out
    end,
})

-- ЧЕЛОВЕК И МИР --------------------------------------------------------
def({
    id = "player", name = "ИГРОК", cat = "player", color = COL3(90, 200, 255),
    hint = "Параметры игрока: здоровье, броня, скорость, стамина, модель, цвет.",
    fields = {
        { key = "target", label = "Цель (ply / id узла)", type = "text", def = "ply" },
        { key = "health", label = "Здоровье", type = "number", def = 100, min = 1, max = 500 },
        { key = "armor", label = "Броня", type = "number", def = 0, min = 0, max = 500 },
        { key = "speed", label = "Скорость (WalkSpeed)", type = "number", def = 0, min = 0, max = 800 },
        { key = "run", label = "Скорость бега", type = "number", def = 0, min = 0, max = 1200 },
        { key = "stamina", label = "Стамина (0..1)", type = "number", def = 0, min = 0, max = 1 },
        { key = "model", label = "Модель", type = "model", def = "" },
        { key = "color", label = "Цвет", type = "color", def = COL3(255, 255, 255) },
        { key = "gibless", label = "Без гиббса", type = "check", def = false },
        { key = "nofall", label = "Без урона от падения", type = "check", def = false },
    },
    caption = function(n) local d = n.data or {}
        return "HP " .. tostring(tonumber(d.health) or 100) .. " · броня " .. tostring(tonumber(d.armor) or 0) end,
    code = function(n)
        local d = n.data or {}
        local t = tostring(d.target or "ply")
        local out = { "-- Игрок: " .. t }
        out[#out + 1] = "local P = " .. t
        if tonumber(d.health) and tonumber(d.health) > 0 then
            out[#out + 1] = "P:SetHealth(" .. numberToString(tonumber(d.health)) .. ")"
            out[#out + 1] = "P:SetMaxHealth(" .. numberToString(tonumber(d.health)) .. ")"
        end
        if tonumber(d.armor) and tonumber(d.armor) > 0 then
            out[#out + 1] = "P:SetArmor(" .. numberToString(tonumber(d.armor)) .. ")"
        end
        if tonumber(d.speed) and tonumber(d.speed) > 0 then out[#out + 1] = "P:SetWalkSpeed(" .. numberToString(tonumber(d.speed)) .. ")" end
        if tonumber(d.run) and tonumber(d.run) > 0 then out[#out + 1] = "P:SetRunSpeed(" .. numberToString(tonumber(d.run)) .. ")" end
        if tonumber(d.stamina) ~= nil then
            local st = tonumber(d.stamina)
            if st >= 0 and st <= 1 then out[#out + 1] = "P:SetStamina(" .. numberToString(st) .. ")" end
        end
        if tostring(d.model or "") ~= "" then out[#out + 1] = "P:SetModel(" .. string.format("%q", tostring(d.model)) .. ")" end
        local c = d.color or {}
        out[#out + 1] = string.format("P:SetPlayerColor(Vector(%.2f, %.2f, %.2f))", tonumber(c.r) or 255, tonumber(c.g) or 255, tonumber(c.b) or 255)
        if d.gibless then out[#out + 1] = "P:SetNoCollideWithTeammates(true) -- без гиббса: флаг модели" end
        if d.nofall then out[#out + 1] = "P:SetNoFallDamage(true)" end
        return out
    end,
})

def({
    id = "effect", name = "ЭФФЕКТ", cat = "player", color = COL3(250, 130, 220),
    hint = "Экранный/мировой эффект: вспышка, тряска, частицы, звуковой импульс.",
    fields = {
        { key = "type", label = "Тип", type = "select", def = "shake",
          opts = { { "shake", "Тряска экрана" }, { "fade", "Затухание экрана (флеш)" },
                   { "particle", "Частицы (ParticleEffect)" }, { "impact", "Эффект попадания (util.Effect)" } } },
        { key = "pos", label = "Позиция/цель", type = "vector", def = POS(0, 0, 0) },
        { key = "name", label = "Имя эффекта/частиц", type = "text", def = "explosion" },
        { key = "power", label = "Сила", type = "number", def = 1, min = 0, max = 10 },
        { key = "color", label = "Цвет флеша", type = "color", def = COL3(255, 255, 255) },
    },
    caption = function(n) local d = n.data or {}
        return tostring(d.type or "shake") .. " · " .. tostring(d.name or "") end,
    code = function(n)
        local d = n.data or {}
        local t = tostring(d.type or "shake")
        local out = { "-- Эффект: " .. t }
        if t == "shake" then
            out[#out + 1] = string.format("util.ScreenShake(%s, %s, %s, %s)",
                vectorToCtor(d.pos, "Vector"), numberToString((tonumber(d.power) or 1) * 8),
                numberToString((tonumber(d.power) or 1) * 1.5), "5")
        elseif t == "fade" then
            local c = d.color or {}
            out[#out + 1] = string.format("ply:ScreenFade(SCREENFADE_IN, Color(%d, %d, %d), 0.4, 0.4)",
                tonumber(c.r) or 255, tonumber(c.g) or 255, tonumber(c.b) or 255)
        elseif t == "particle" then
            out[#out + 1] = 'ParticleEffect(' .. string.format("%q", tostring(d.name or "explosion")) .. ", "
                .. vectorToCtor(d.pos, "Vector") .. ", Angle(0,0,0))"
        else
            out[#out + 1] = "local ed = EffectData()"
            out[#out + 1] = "ed:SetOrigin(" .. vectorToCtor(d.pos, "Vector") .. ")"
            out[#out + 1] = "ed:SetMagnitude(" .. numberToString(tonumber(d.power) or 1) .. ")"
            out[#out + 1] = "util.Effect(" .. string.format("%q", tostring(d.name or "Impact")) .. ", ed)"
        end
        return out
    end,
})

def({
    id = "material", name = "МАТЕРИАЛ", cat = "player", color = COL3(120, 230, 170),
    hint = "Текстура/материал на объект или модель: путь + цвет + self-illum.",
    fields = {
        { key = "target", label = "Объект (id узла / ent)", type = "text", def = "ent" },
        { key = "material", label = "Материал", type = "material", def = "" },
        { key = "color", label = "Цвет", type = "color", def = COL3(255, 255, 255) },
        { key = "selfillum", label = "Свечение (SelfIllum)", type = "number", def = 0, min = 0, max = 1 },
    },
    caption = function(n) local d = n.data or {}
        return tostring(d.material or "") ~= "" and string.sub(tostring(d.material), 12) or "материал не выбран" end,
    code = function(n)
        local d = n.data or {}
        local c = d.color or {}
        local out = { "-- Материал на " .. tostring(d.target or "ent") }
        if tostring(d.material or "") ~= "" then
            out[#out + 1] = tostring(d.target or "ent") .. ":SetMaterial(" .. string.format("%q", tostring(d.material)) .. ")"
        end
        out[#out + 1] = string.format("%s:SetColor(Color(%d, %d, %d))", tostring(d.target or "ent"), tonumber(c.r) or 255, tonumber(c.g) or 255, tonumber(c.b) or 255)
        if tonumber(d.selfillum) and tonumber(d.selfillum) > 0 then
            out[#out + 1] = "-- SelfIllum: материал с флагом $selfillum или render.SetMaterialOverride"
        end
        return out
    end,
})

def({
    id = "path", name = "ПУТЬ", cat = "player", color = COL3(240, 170, 90),
    hint = "Маршрут точек (x,y,z построчно): для НПС, маркеров, патруля.",
    fields = {
        { key = "points", label = "Точки (x,y,z — построчно)", type = "code", def = "0,0,0\n100,0,0" },
        { key = "loop", label = "Зациклить", type = "check", def = true },
        { key = "speed", label = "Скорость (ед/с)", type = "number", def = 100, min = 10, max = 2000 },
    },
    caption = function(n) local d = n.data or {}
        local p = 0; for _ in tostring(d.points or ""):gmatch("[^\r\n]+") do p = p + 1 end
        return p .. " точек · " .. tostring(tonumber(d.speed) or 100) .. " ед/с" end,
    code = function(n)
        local d = n.data or {}
        local pts = {}
        for line in tostring(d.points or ""):gmatch("[^\r\n]+") do
            local x, y, z = string.match(line, "^%s*(%-?[%d%.]+)%s*,%s*(%-?[%d%.]+)%s*,%s*(%-?[%d%.]+)%s*$")
            if x then pts[#pts + 1] = "    Vector(" .. x .. ", " .. y .. ", " .. z .. ")," end
        end
        local out = { "-- Путь (" .. #pts .. " точек), скорость " .. numberToString(tonumber(d.speed) or 100) }
        out[#out + 1] = "local PATH = {\n" .. table.concat(pts, "\n") .. "\n}"
        if d.loop then out[#out + 1] = "-- Зациклено: индекс = (index % #PATH) + 1" end
        out[#out + 1] = "-- ВЫХОД: PATH (массив Vector)"
        return out
    end,
})

def({
    id = "anchor", name = "КРЕПЛЕНИЕ", cat = "player", color = COL3(160, 190, 250),
    hint = "Привязать объект к другому: родитель, локальные координаты, кость.",
    fields = {
        { key = "parent", label = "Родитель (id узла)", type = "text", def = "" },
        { key = "child", label = "Ребёнок (id узла)", type = "text", def = "" },
        { key = "pos", label = "Локальная позиция", type = "vector", def = POS(0, 0, 0) },
        { key = "ang", label = "Локальный поворот", type = "angle", def = { p = 0, y = 0, r = 0 } },
        { key = "bone", label = "Кость (анимация)", type = "text", def = "" },
    },
    caption = function(n) local d = n.data or {}
        return tostring(d.child or "?") .. " → " .. tostring(d.parent or "?") end,
    code = function(n)
        local d = n.data or {}
        local out = { "-- Крепление: " .. tostring(d.child or "?") .. " к " .. tostring(d.parent or "?") }
        out[#out + 1] = tostring(d.child or "child") .. ":SetParent(" .. tostring(d.parent or "parent") .. ")"
        out[#out + 1] = tostring(d.child or "child") .. ":SetLocalPos(" .. vectorToCtor(d.pos, "Vector") .. ")"
        out[#out + 1] = tostring(d.child or "child") .. ":SetLocalAngles(" .. angleToCtor(d.ang) .. ")"
        if tostring(d.bone or "") ~= "" then
            out[#out + 1] = "-- Кость " .. string.format("%q", tostring(d.bone)) .. ": attachment вместо SetParent при анимации"
        end
        return out
    end,
})

-- КОММУНИКАЦИЯ --------------------------------------------------------
def({
    id = "chat", name = "ЧАТ-СООБЩЕНИЕ", cat = "player", color = COL3(110, 220, 200),
    hint = "Сообщение в чат: текст, кому, формат (объявление/ООС).",
    fields = {
        { key = "text", label = "Текст", type = "code", def = "Текст сообщения" },
        { key = "target", label = "Кому", type = "select", def = "all",
          opts = { { "all", "Всем" }, { "near", "Рядом (радиус)" }, { "ply", "Игроку (узел)" } } },
        { key = "radius", label = "Радиус", type = "number", def = 400, min = 50, max = 3000 },
        { key = "prefix", label = "Префикс", type = "text", def = "" },
    },
    caption = function(n) local d = n.data or {}
        return (tostring(d.text or "") .. ""):sub(1, 42) end,
    code = function(n)
        local d = n.data or {}
        local out = { "-- Чат: " .. tostring(d.target or "all") }
        local msg = string.format("%q", tostring(d.text or ""))
        if tostring(d.prefix or "") ~= "" then msg = string.format("%q", tostring(d.prefix)) .. " .. " .. "ящик-text" end
        out[#out + 1] = "-- Реализация: EasyChat.SendGlobalMessage / ply:ChatPrint — текст: " .. tostring(d.text or "")
        if tostring(d.target or "all") == "near" then
            out[#out + 1] = "for _, p in ipairs(player.GetAll()) do if p:GetPos():DistToSqr(origin:GetPos()) < "
                .. numberToString((tonumber(d.radius) or 400) ^ 2) .. " then p:ChatPrint(" .. string.format("%q", tostring(d.text or "")) .. ") end end"
        elseif tostring(d.target) == "ply" then
            out[#out + 1] = "ply:ChatPrint(" .. string.format("%q", tostring(d.text or "")) .. ")"
        else
            out[#out + 1] = "for _, p in ipairs(player.GetAll()) do p:ChatPrint(" .. string.format("%q", tostring(d.text or "")) .. ") end"
        end
        return out
    end,
})

def({
    id = "chatbutton", name = "КНОПКИ ЧАТА", cat = "player", color = COL3(200, 235, 120),
    hint = "Быстрые кнопки-команды: подпись|команда (по строке). Работает и без EasyChat.",
    fields = {
        { key = "buttons", label = "Кнопки (подпись|команда, построчно)", type = "code", def = "Привет|/me здоровается" },
    },
    caption = function(n) local d = n.data or {}
        local p = 0; for _ in tostring(d.buttons or ""):gmatch("[^\r\n]+") do p = p + 1 end
        return p .. " кнопок" end,
    code = function(n)
        local d = n.data or {}
        local out = { "-- Быстрые кнопки чата" }
        for line in tostring(d.buttons or ""):gmatch("[^\r\n]+") do
            local label, cmd = string.match(line, "^%s*([^|]+)|(.+)$")
            if label and cmd then
                out[#out + 1] = string.format("-- [%s] → %s", string.Trim(label), string.Trim(cmd))
            end
        end
        out[#out + 1] = "-- EasyChat: PlayerSay + PlayerSayTransform (SkipPlayerSay); без него — RunConsoleCommand"
        return out
    end,
})

def({
    id = "keys", name = "КЛАВИШИ", cat = "player", color = COL3(140, 230, 250),
    hint = "Клавиша/настройка ввода: проверка KeyDown, описание для игрока.",
    fields = {
        { key = "key", label = "Клавиша (IN_… / KEY_…)", type = "text", def = "IN_USE" },
        { key = "action", label = "Действие (подпись)", type = "text", def = "Взаимодействие" },
        { key = "mode", label = "Режим", type = "select", def = "hold",
          opts = { { "hold", "Удержание" }, { "press", "Нажатие (раз)" }, { "toggle", "Переключение" } } },
        { key = "bind", label = "Перезаписать бинд (client)", type = "text", def = "" },
    },
    caption = function(n) local d = n.data or {}
        return tostring(d.key or "IN_USE") .. " · " .. tostring(d.action or "") end,
    code = function(n)
        local d = n.data or {}
        local out = { "-- Клавиша: " .. tostring(d.action or "") .. " (" .. tostring(d.key or "IN_USE") .. ", "
            .. tostring(d.mode or "hold") .. ")" }
        if tostring(d.mode or "hold") == "press" then
            out[#out + 1] = "hook.Add(\"PlayerButtonDown\", \"as_keys\", function(ply, key)"
            out[#out + 1] = "    if key == " .. string.format("%q", tostring(d.key or "IN_USE")) .. " then"
            out[#out + 1] = "        -- ТЕЛО: действие (выход 'out')"
            out[#out + 1] = "    end"
            out[#out + 1] = "end)"
        else
            out[#out + 1] = "-- Проверка в Think: if input.IsKeyDown(" .. string.format("%q", tostring(d.key or "IN_USE"))
                .. ") then -- ... end"
        end
        if tostring(d.bind or "") ~= "" then
            out[#out + 1] = "-- Переназначение: input.LookupBinding / concommand: client = "
                .. string.format("%q", tostring(d.bind))
        end
        return out
    end,
})

def({
    id = "music", name = "МУЗЫКА", cat = "media", color = COL3(190, 120, 250),
    hint = "Фоновая музыка/эмбиент: звук, зацикливание, радиус, громкость.",
    fields = {
        { key = "sound", label = "Звук (sound/…)", type = "sound", def = "" },
        { key = "vol", label = "Громкость", type = "number", def = 0.6, min = 0, max = 1 },
        { key = "loop", label = "Зациклить", type = "check", def = true },
        { key = "radius", label = "Радиус слышимости", type = "number", def = 600, min = 50, max = 4000 },
        { key = "pos", label = "Позиция (0,0,0 = у источника)", type = "vector", def = POS(0, 0, 0) },
    },
    caption = function(n) local d = n.data or {}
        return "♪ " .. (tostring(d.sound or ""):sub(7)) .. " · фон" end,
    code = function(n)
        local d = n.data or {}
        local out = { "-- Музыка: " .. tostring(d.sound or "(нет)") .. " (фон, радиус "
            .. numberToString(tonumber(d.radius) or 600) .. ")" }
        if tostring(d.sound or "") ~= "" then
            if d.loop then
                out[#out + 1] = "-- SoundPatch/SoundEmit с loop: начало/конец цикла"
                out[#out + 1] = "local patch = SoundPatch(" .. vectorToCtor(d.pos, "Vector") .. ")"
                out[#out + 1] = "patch:SetSound(" .. string.format("%q", tostring(d.sound)) .. ")"
                out[#out + 1] = "patch:SetVolume(" .. numberToString(tonumber(d.vol) or 0.6) .. ")"
                out[#out + 1] = "patch:SetLoopStart(0.0) patch:SetLoopEnd(1.0) patch:PlayAfter(0.1)"
            else
                out[#out + 1] = "sound.Play(" .. string.format("%q", tostring(d.sound)) .. ", "
                    .. vectorToCtor(d.pos, "Vector") .. ", " .. numberToString(tonumber(d.vol) or 0.6) .. ", 100)"
            end
        end
        return out
    end,
})

A.Cats = {
    { id = "visual", name = "Визуал" },
    { id = "media", name = "Медиа" },
    { id = "logic", name = "Логика" },
    { id = "ui", name = "Интерфейс" },
    { id = "player", name = "Игрок и мир" },
    { id = "misc", name = "Прочее" },
}

function A.DefOf(kind)
    for _, d in ipairs(A.Defs) do if d.id == kind then return d end end
    return A.Defs[1]
end

--- Поля по умолчанию узла (глубокая копия).
function A.Defaults(kind)
    local d = A.DefOf(kind)
    local out = {}
    for _, f in ipairs(d.fields or {}) do out[f.key] = clone(f.def) end
    return out
end

--- Подпись карточки (без surface: чистый текст).
function A.Caption(kind, node)
    local d = A.DefOf(kind)
    if isfunction(d.caption) then
        local ok, s = pcall(d.caption, node)
        if ok and s ~= nil then return tostring(s) end
    end
    return d.name or kind
end

--- Значение по ключу с учетом дефолта.
function A.Field(kind, node, key)
    local d = A.DefOf(kind)
    for _, f in ipairs(d.fields or {}) do
        if f.key == key then
            local v = (node.data or {})[key]
            return v ~= nil and v or clone(f.def)
        end
    end
    return nil
end

-----------------------------------------------------------------------
-- МАНИФЕСТ: нормализация и сериализация
-----------------------------------------------------------------------
--- Глубокое слияние дефолтов со значениями узла (данные приходят вдовой).
function A.NormalizeData(kind, raw)
    local d = A.DefOf(kind)
    local out = {}
    for _, f in ipairs(d.fields or {}) do out[f.key] = clone(f.def) end
    if istable(raw) then
        for k, v in pairs(raw) do
            if out[k] ~= nil and v ~= nil then out[k] = v end
        end
    end
    -- Строки режем, чтобы манифест не раздувался.
    for k, v in pairs(out) do
        if type(v) == "string" and #v > A.MaxTextLen then out[k] = string.sub(v, 1, A.MaxTextLen) end
    end
    return out
end

--- Привести произвольную таблицу к валидному проекту.
function A.Normalize(proj)
    --[[ Пустая строка — то же, что отсутствие: `"" or ...` в Lua даёт "".
         И имя, и id обязаны стать непустыми: id живёт в имени файла. ]]
    local rawName = istable(proj) and string.Trim(tostring(proj.name or "")) or ""
    local rawId = istable(proj) and string.Trim(tostring(proj.id or "")) or ""
    if rawName == "" then rawName = "Новый проект" end
    if rawId == "" then rawId = A.Slug(rawName) end
    local rawDesc = istable(proj) and string.Trim(tostring(proj.desc or "")) or ""
    local out = { format = A.Format, version = A.FormatVersion,
        name = string.sub(rawName, 1, 64),
        id = string.sub(rawId, 1, 48),
        desc = string.sub(rawDesc, 1, 300),
        nodes = {}, edges = {},
        -- Макет окна (конструктор вкладки «МАКЕТ») и его шаблоны.
        layout = A.NormalizeLayout(istable(proj) and proj.layout or nil),
        templates = A.NormalizeTemplates(istable(proj) and proj.templates or nil) }

    local seen = {}
    local rawNodes = istable(proj) and istable(proj.nodes) and proj.nodes or {}
    for i = 1, math.min(#rawNodes, A.MaxNodes) do
        local n = rawNodes[i]
        if istable(n) then
            local kind = tostring(n.kind or "")
            local defOk
            for _, d in ipairs(A.Defs) do if d.id == kind then defOk = d break end end
                if defOk then
                    local uid = tostring(n.uid or ("n" .. i))
                    if not seen[uid] then
                        seen[uid] = true
                        out.nodes[#out.nodes + 1] = {
                            uid = uid,
                            kind = kind,
                            -- Пределы холста студии (3000x2000 минус карточка).
                            x = math.Clamp(tonumber(n.x) or 40, 0, 2960),
                            y = math.Clamp(tonumber(n.y) or 40, 0, 1900),
                            data = A.NormalizeData(kind, n.data),
                        }
                    end
                end
        end
    end

    local byUid = {}
    for _, n in ipairs(out.nodes) do byUid[n.uid] = n end

    local rawEdges = istable(proj) and istable(proj.edges) and proj.edges or {}
    for i = 1, math.min(#rawEdges, A.MaxEdges) do
        local e = rawEdges[i]
        if istable(e) then
            local a, b = byUid[tostring(e.a)], byUid[tostring(e.b)]
            if a and b and tostring(e.a) ~= tostring(e.b) then
                out.edges[#out.edges + 1] = {
                    a = a.uid, ap = string.sub(tostring(e.ap or "out"), 1, 16),
                    b = b.uid, bp = string.sub(tostring(e.bp or "in"), 1, 16),
                }
            end
        end
    end
    return out
end

--- Клонировать проект (для правок в студии, чтобы не мутировать исходник).
function A.CloneProject(proj)
    return A.Normalize(proj)
end

--- Текст манифеста: самодостаточная Lua-таблица (можно вернуть в студию).
--[[ ВАЖНО: не только nodes/edges. Макет окна и шаблоны — часть проекта:
     без них раундтрип молча терял дизайн владельца (поймано стендом
     «макет переживает раундтрип»). ]]
function A.ToLuaText(proj)
    return "{\n    format = " .. string.format("%q", A.Format) .. ",\n    version = " .. A.FormatVersion .. ",\n"
        .. "    name = " .. string.format("%q", proj.name) .. ",\n"
        .. "    id = " .. string.format("%q", proj.id) .. ",\n"
        .. "    desc = " .. string.format("%q", proj.desc) .. ",\n"
        .. "    nodes = " .. A.Dump(proj.nodes, "    ") .. ",\n"
        .. "    edges = " .. A.Dump(proj.edges, "    ") .. ",\n"
        .. "    layout = " .. A.Dump(proj.layout, "    ") .. ",\n"
        .. "    templates = " .. A.Dump(proj.templates, "    ") .. ",\n}"
end

--- Распарсить текст манифеста обратно. Возвращает project или nil.
function A.ParseText(text)
    if not isstring(text) or string.Trim(text) == "" then return nil end
    local chunk = tostring(text)
    -- Срезаем возможную обёртку "local X = (...)" / "return (...)".
    local open = string.find(chunk, "{", 1, true)
    if not open then return nil end
    chunk = string.sub(chunk, open)
    --[[ CompileString возвращает ФУНКЦИЮ, а не результат: сначала
         компилируем, потом вызываем в pcall. ]]
    local fn, err = CompileString("return " .. chunk, "grm_astudio_parse")
    if fn then
        local ok, t = pcall(fn)
        if ok and istable(t) then return A.Normalize(t) end
    end
    -- Фолбэк: вдруг кто-то вставил JSON-вид манифеста.
    local ok, t = pcall(util.JSONToTable, text, false, true)
    if ok and istable(t) then return A.Normalize(t) end
    return nil
end

--- Связи узла: входящие и исходящие (для отрисовки и генератора).
function A.LinksOf(proj)
    local out, into = {}, {}
    for i, e in ipairs(proj.edges or {}) do
        out[e.a] = out[e.a] or {}
        out[e.a][#out[e.a] + 1] = i
        into[e.b] = into[e.b] or {}
        into[e.b][#into[e.b] + 1] = i
    end
    return out, into
end

-----------------------------------------------------------------------
-- ГЕНЕРАТОР КОДА
-----------------------------------------------------------------------
--- Все строки кода одного узла (с рамкой и подписью портов).
local function nodeChunk(proj, n)
    local d = A.DefOf(n.kind)
    local lines = { "-- " .. n.uid .. " · " .. d.name .. " · " .. A.Caption(n.kind, n) }
    local ok, code = pcall(d.code, n, { proj = proj })
    if not ok then
        lines[#lines + 1] = "-- ОШИБКА генератора: " .. tostring(code)
        return lines
    end
    if istable(code) then
        for _, l in ipairs(code) do lines[#lines + 1] = tostring(l) end
    end
    return lines
end

--- Отчёт связей: какая линия куда приходит (для генератора и для владельца).
local function edgeReport(proj)
    local lines = {}
    local byUid = {}
    for _, n in ipairs(proj.nodes) do byUid[n.uid] = n end
    for _, e in ipairs(proj.edges) do
        local a, b = byUid[e.a], byUid[e.b]
        if a and b then
            lines[#lines + 1] = string.format("-- СВЯЗЬ: [%s] %s.%s  →  [%s] %s%s",
                e.a, A.Caption(a.kind, a), e.ap,
                e.b, A.Caption(b.kind, b), e.ap == "else" and " (иначе)" or "")
        end
    end
    return lines
end

--- Полный текст компиляции. Возвращает строку для копирования.
function A.Generate(proj)
    proj = A.Normalize(proj)
    local out = {
        "--[[ =========================================================",
        "     СТУДИЯ АДДОНА · " .. proj.name .. " · ID: " .. proj.id,
        "     Формат: " .. A.Format .. " v" .. A.FormatVersion,
        "     Узлов: " .. #proj.nodes .. ", связей: " .. #proj.edges,
        "     Сгенерировано. Копируй и присылай агенту как задание.",
        "     ========================================================= ]]",
        "",
        "-- 1. МАНИФЕСТ (что нарисовано; для импорта в студию обратно)",
        "local ASPROJECT = " .. A.ToLuaText(proj),
        "",
        "-- 2. ОБЗОР УЗЛОВ",
    }
    local byUid = {}
    for _, n in ipairs(proj.nodes) do
        byUid[n.uid] = n
        out[#out + 1] = string.format("-- [%s] %-9s %s", n.uid, n.kind:upper(), A.Caption(n.kind, n))
    end
    out[#out + 1] = ""
    out[#out + 1] = "-- 3. СВЯЗИ"
    for _, l in ipairs(edgeReport(proj)) do out[#out + 1] = l end
    out[#out + 1] = ""
    out[#out + 1] = "-- 4. ЧЕРНОВИК КОДА ПО УЗЛАМ (точечная реализация агентом)"
    for _, n in ipairs(proj.nodes) do
        out[#out + 1] = ""
        for _, l in ipairs(nodeChunk(proj, n)) do out[#out + 1] = l end
    end

    -- Макет окна: если в проекте есть виджеты — даём готовую buildUI.
    if #(proj.layout.widgets or {}) > 0 then
        out[#out + 1] = ""
        out[#out + 1] = "-- 4.5 МАКЕТ ОКНА (конструктор: вкладка «МАКЕТ»)"
        for _, l in ipairs(A.LayoutToCode(proj.layout, proj)) do out[#out + 1] = l end
    end

    -- Конструктор размещения: тул-файл целиком.
    local exp
    for _, n in ipairs(proj.nodes) do
        if n.kind == "export" and (n.data or {}).placeable then exp = n end
    end
    if exp then
        out[#out + 1] = ""
        out[#out + 1] = "-- 5. ТУЛ РАЗМЕЩЕНИЯ (файл целиком — положить в"
        out[#out + 1] = "--    lua/weapons/gmod_tool/stools/" .. tostring((exp.data or {}).tool or "grm_studio_prefab") .. ".lua )"
        out[#out + 1] = "--" .. string.rep("-", 70)
        --[[ Разбивка без string.Explode: общая часть должна гоняться в
             голом LuaJIT, а не только в GMod. Пустые строки сохраняются. ]]
        local tl = A.ToolFile(proj, exp.data.tool, exp.data.toolcat) .. "\n"
        for line in tl:gmatch("(.-)\r?\n") do out[#out + 1] = line end
        out[#out + 1] = "--" .. string.rep("-", 70)
    end

    out[#out + 1] = ""
    out[#out + 1] = "-- 6. КОНЕЦ КОМПИЛЯЦИИ"
    return table.concat(out, "\n") .. "\n"
end

--- Индекс каталога: массив путей → lookup-таблица для Validate.
function A.CatalogIndex(list)
    local out = {}
    for _, item in ipairs(istable(list) and list or {}) do
        local s = tostring(item)
        out[s] = true
        out[string.lower(s)] = true
    end
    return out
end

--- Краткая статистика для окна.
function A.Stats(proj)
    local byCat = {}
    for _, n in ipairs(proj.nodes or {}) do
        local d = A.DefOf(n.kind)
        byCat[d.cat] = (byCat[d.cat] or 0) + 1
    end
    return { nodes = #(proj.nodes or {}), edges = #(proj.edges or {}), byCat = byCat }
end

-----------------------------------------------------------------------
-- КОНСТРУКТОР ОКОН: макеты и шаблоны
-----------------------------------------------------------------------
--[[ Виджеты макета. Одна таблица на тип: палитра, поля, генератор.
     Макет живёт в проекте (project.layout.widgets) — его видно и в
     студии, и в манифесте, который владелец присылает агенту. ]]
A.WidgetKinds = {
    { id = "button", name = "КНОПКА", color = COL3(90, 210, 120) },
    { id = "label", name = "ТЕКСТ", color = COL3(220, 220, 225) },
    { id = "entry", name = "ПОЛЕ", color = COL3(140, 220, 210) },
    { id = "textarea", name = "ТЕКСТ-ОБЛАСТЬ", color = COL3(150, 200, 220) },
    { id = "check", name = "ЧЕКБОКС", color = COL3(110, 200, 160) },
    { id = "slider", name = "СЛАЙДЕР", color = COL3(250, 190, 90) },
    { id = "select", name = "ВЫБОР", color = COL3(170, 170, 230) },
    { id = "list", name = "СПИСОК", color = COL3(190, 150, 230) },
    { id = "image", name = "КАРТИНКА", color = COL3(120, 210, 180) },
    { id = "model", name = "МОДЕЛЬ 3D", color = COL3(80, 200, 160) },
    { id = "progress", name = "ПРОГРЕСС", color = COL3(250, 160, 90) },
    { id = "panel", name = "ПАНЕЛЬ", color = COL3(90, 130, 170) },
}

A.WidgetDefaults = {
    button = { label = "Кнопка", target = "" },
    label = { text = "Текст" },
    entry = { placeholder = "Ввод…", var = "input" },
    textarea = { placeholder = "Многострочный текст…", var = "notes" },
    check = { label = "Галка" },
    slider = { label = "Параметр", min = 0, max = 100, value = 50 },
    select = { label = "Выбор", options = "Первый;Второй" },
    list = { options = "Вариант 1;Вариант 2" },
    image = { material = "" },
    model = { model = "", fov = 30 },
    progress = { label = "Прогресс", min = 0, max = 100, value = 40 },
    panel = { caption = "Панель" },
}

--[[ РЕЕСТР ВИДОВ ВИДЖЕТА — одна строка на вид, вместо лестниц в трёх файлах.

     Знание «что такое кнопка» было размазано по шести местам: список
     видов, значения по умолчанию, поля инспектора, ветка в генераторе
     кода (sh_), ветка выбора VGUI-класса и ветка настройки виджета (cl_).
     Добавление вида требовало шести правок в двух файлах — забыл одну,
     и виджет либо не рисуется в редакторе, либо не попадает в
     сгенерированный код, либо теряет свойства при «ТЕСТ ОКНА».

     Здесь у вида есть всё, что нужно обеим сторонам:
       class    — VGUI-класс;
       var      — имя локальной переменной в генерируемом коде;
       w, h     — размеры по умолчанию;
       code     — как вид дописывает себя в сгенерированный код;
       setup    — что сделать с живым виджетом сразу после создания
                  (клиент читает это поле, сервер — нет).
     Значения по умолчанию и поля инспектора остаются в своих таблицах:
     они данные, а не поведение.
]]
A.WidgetSpec = {
    button = { class = "DButton", var = "b", w = 100, h = 30,
        code = function(out, w, v, q)
            out[#out + 1] = "    " .. v .. ":SetText(" .. q(w.label or "") .. ")"
            out[#out + 1] = "    " .. v .. ".DoClick = function() -- действие "
                .. tostring(w.target or "(не задано)") .. " end"
        end },
    label = { class = "DLabel", var = "l", w = 100, h = 20,
        code = function(out, w, v, q)
            out[#out + 1] = "    " .. v .. ":SetText(" .. q(w.text or "") .. ")"
        end },
    entry = { class = "DTextEntry", var = "e", w = 160, h = 24,
        code = function(out, w, v, q)
            out[#out + 1] = "    " .. v .. ":SetPlaceholderText(" .. q(w.placeholder or "") .. ")"
        end },
    textarea = { class = "DTextEntry", var = "t", w = 240, h = 80, multiline = true,
        code = function(out, w, v, q)
            out[#out + 1] = "    " .. v .. ":SetMultiline(true)"
            out[#out + 1] = "    " .. v .. ":SetPlaceholderText(" .. q(w.placeholder or "") .. ")"
        end },
    check = { class = "DCheckBox", var = "c", w = 120, h = 24,
        code = function(out, w, v, q)
            out[#out + 1] = "    " .. v .. ":SetText(" .. q(w.label or "") .. ")"
        end },
    slider = { class = "DSlider", var = "s", w = 240, h = 24,
        code = function(out, w, v, _q, num)
            out[#out + 1] = "    " .. v .. ":SetMinMax(" .. num(tonumber(w.min) or 0)
                .. ", " .. num(tonumber(w.max) or 100) .. ")"
            out[#out + 1] = "    " .. v .. ":SetValue(" .. num(tonumber(w.value) or 50) .. ")"
        end },
    select = { class = "DComboBox", var = "c", w = 160, h = 24,
        code = function(out, w, v, q)
            for opt in tostring(w.options or ""):gmatch("[^;]+") do
                out[#out + 1] = "    " .. v .. ":AddChoice(" .. q(string.Trim(opt)) .. ")"
            end
        end },
    list = { class = "DListView", var = "l", w = 240, h = 120, column = "Вариант",
        code = function(out, w, v, q)
            out[#out + 1] = "    " .. v .. ":AddColumn(\"Вариант\")"
            for opt in tostring(w.options or ""):gmatch("[^;]+") do
                out[#out + 1] = "    " .. v .. ":AddLine(" .. q(string.Trim(opt)) .. ")"
            end
        end },
    image = { class = "DImage", var = "img", w = 120, h = 90,
        code = function(out, w, v)
            if tostring(w.material or "") ~= "" then
                out[#out + 1] = "    " .. v .. ":SetMaterial(Material(\""
                    .. string.gsub(tostring(w.material), "\\", "/") .. "\"))"
            end
        end },
    model = { class = "DModelPanel", var = "m", w = 180, h = 180,
        code = function(out, w, v, _q, num)
            out[#out + 1] = "    " .. v .. ":SetFOV(" .. num(tonumber(w.fov) or 30) .. ")"
            if tostring(w.model or "") ~= "" then
                out[#out + 1] = "    " .. v .. ":SetModel(\""
                    .. string.gsub(tostring(w.model), "\\", "/") .. "\")"
                out[#out + 1] = "    " .. v .. ":SetAnimated(true)"
            end
        end },
    progress = { class = "DProgress", var = "p", w = 240, h = 18,
        code = function(out, w, v, _q, num)
            local minV, maxV = tonumber(w.min) or 0, tonumber(w.max) or 100
            local frac = (tonumber(w.value) or minV) - minV
            if maxV > minV then frac = frac / (maxV - minV) end
            out[#out + 1] = "    " .. v .. ":SetFraction(" .. num(math.Clamp(frac, 0, 1)) .. ")"
        end },
    -- Панель — она же запасной вариант для неизвестного вида: лучше
    -- пустая заглушка нужного размера, чем пропущенный виджет.
    panel = { class = "DPanel", var = "c", w = 100, h = 30,
        code = function(out, _w, v)
            out[#out + 1] = "    " .. v .. ":SetPaintBackground(false)"
        end },
}

--- Описание вида виджета. Неизвестный вид — панель-заглушка.
function A.Widget(kind)
    return A.WidgetSpec[tostring(kind or "")] or A.WidgetSpec.panel
end

--- Поля, которые инспектор макета показывает для вида виджета.
function A.WidgetFields(kind)
    local by = {
        button = { { "label", "Подпись" }, { "target", "Действие (uid узла/текст)" } },
        label = { { "text", "Текст" } },
        entry = { { "placeholder", "Плейсхолдер" }, { "var", "Переменная" } },
        textarea = { { "placeholder", "Плейсхолдер" }, { "var", "Переменная" } },
        check = { { "label", "Подпись" } },
        slider = { { "label", "Подпись" }, { "min", "Мин." }, { "max", "Макс." }, { "value", "Текущее" } },
        select = { { "label", "Подпись" }, { "options", "Варианты (;)" } },
        list = { { "options", "Строки (;)" } },
        image = { { "material", "Материал" } },
        model = { { "model", "Модель" }, { "fov", "FOV" } },
        progress = { { "label", "Подпись" }, { "min", "Мин." }, { "max", "Макс." }, { "value", "Текущее" } },
        panel = { { "caption", "Подпись" } },
    }
    local list = by[kind]
    if not list then return { { "caption", "Подпись" } } end
    local out = {}
    for _, row in ipairs(list) do
        out[#out + 1] = { key = row[1], label = row[2],
            type = (row[1] == "min" or row[1] == "max" or row[1] == "value" or row[1] == "fov") and "number"
                or (row[1] == "model" and "model" or (row[1] == "material" and "material" or "text")) }
    end
    return out
end

--- Нормализация ОДНОГО виджета: числа, диапазоны, длина строк.
function A.NormalizeWidget(wgt, opts)
    opts = opts or { w = 1600, h = 1000 }
    local rec = { kind = tostring(wgt.kind or "panel") }
    local x, y = tonumber(wgt.x) or 0, tonumber(wgt.y) or 0
    local w, h = tonumber(wgt.w) or 100, tonumber(wgt.h) or 30
    rec.x = math.Clamp(x, 0, math.max(0, opts.w - 12))
    rec.y = math.Clamp(y, 0, math.max(0, opts.h - 12))
    rec.w = math.Clamp(w, 12, math.max(12, opts.w))
    rec.h = math.Clamp(h, 12, math.max(12, opts.h))
    for k in pairs(A.WidgetDefaults[rec.kind] or {}) do
        if wgt[k] ~= nil then rec[k] = wgt[k] end
    end
    -- Диапазоны числовых пар: min < max, value внутри.
    local minV, maxV = tonumber(rec.min), tonumber(rec.max)
    if minV and maxV then
        if minV > maxV then minV, maxV = maxV, minV end
        rec.min, rec.max = minV, maxV
        local v = tonumber(rec.value)
        if v then rec.value = math.Clamp(v, minV, maxV) end
    end
    -- Строки: пробелы по краям и лимит.
    for k, v in pairs(rec) do
        if type(v) == "string" then
            if k ~= "var" and k ~= "options" then v = string.Trim(v) end
            if #v > A.MaxTextLen then v = string.sub(v, 1, A.MaxTextLen) end
            rec[k] = v
        end
    end
    return rec
end

--- Прилипание к сетке: возвращает {x,y,w,h} кратные grid.
function A.SnapRect(rect, grid)
    rect = rect or {}
    local g = tonumber(grid) or 8
    if g < 2 then g = 8 end
    local function snap(v) return math.floor(v / g + 0.5) * g end
    return { x = snap(tonumber(rect.x) or 0), y = snap(tonumber(rect.y) or 0),
        w = math.max(12, snap(tonumber(rect.w) or 100)), h = math.max(12, snap(tonumber(rect.h) or 30)) }
end

--- Движение: сдвиг с клампом по границам холста.
function A.MoveRect(rect, dx, dy, limit)
    rect = rect or {}
    limit = limit or { w = 1600, h = 1000 }
    local w, h = tonumber(rect.w) or 100, tonumber(rect.h) or 30
    return { x = math.Clamp((tonumber(rect.x) or 0) + (dx or 0), 0, math.max(0, limit.w - w)),
        y = math.Clamp((tonumber(rect.y) or 0) + (dy or 0), 0, math.max(0, limit.h - h)),
        w = w, h = h }
end

--- Ресайз за ребро/угол. edge: строка из букв n/w/e/s (можно "nw").
--[[ Ключевая чистая функция «подтягивания за углы»: правка края не
     трогает противоположный, минимальный размер соблюдается, край не
     выходит за холст. Используется и редактором, и стендом. ]]
function A.GrowRect(rect, edge, dx, dy, limit, minSize)
    rect = rect or {}
    limit = limit or { w = 1600, h = 1000 }
    minSize = minSize or 12
    local x, y = tonumber(rect.x) or 0, tonumber(rect.y) or 0
    local w, h = tonumber(rect.w) or 100, tonumber(rect.h) or 30
    local e = tostring(edge or "")
    if string.find(e, "e", 1, true) then
        w = math.Clamp(w + (dx or 0), minSize, math.max(minSize, limit.w - x))
    end
    if string.find(e, "s", 1, true) then
        h = math.Clamp(h + (dy or 0), minSize, math.max(minSize, limit.h - y))
    end
    if string.find(e, "w", 1, true) then
        local nx = math.Clamp(x + (dx or 0), 0, math.max(0, x + w - minSize))
        w = w + (x - nx)
        x = nx
    end
    if string.find(e, "n", 1, true) then
        local ny = math.Clamp(y + (dy or 0), 0, math.max(0, y + h - minSize))
        h = h + (y - ny)
        y = ny
    end
    return { x = x, y = y, w = w, h = h }
end

--- Нормализация макета: пределы, неизвестные виджеты — мимо.
function A.NormalizeLayout(layout, limit)
    limit = limit or { w = 1600, h = 1000 }
    local out = { w = math.Clamp(tonumber(istable(layout) and layout.w or 800) or 800, 160, limit.w),
        h = math.Clamp(tonumber(istable(layout) and layout.h or 600) or 600, 120, limit.h),
        widgets = {} }
    local raw = istable(layout) and layout.widgets or {}
    local kinds = {}
    for _, k in ipairs(A.WidgetKinds) do kinds[k.id] = true end
    for i = 1, math.min(#raw, 300) do
        local wgt = raw[i]
        if istable(wgt) and kinds[wgt.kind] then
            out.widgets[#out.widgets + 1] = A.NormalizeWidget(wgt, out)
        end
    end
    return out
end

--[[ Полный генератор макета: самодостаточная функция buildUI(parent).
     Виджеты лежат по координатам (как в редакторе), действия комментируем
     ссылкой на узел — агент видит, какая кнопка что должна запускать. ]]
function A.LayoutToCode(layout, proj)
    layout = A.NormalizeLayout(layout)
    local out = {
        "-- Макет окна: " .. math.floor(layout.w) .. "x" .. math.floor(layout.h) .. ", виджетов: " .. #layout.widgets,
        "local function buildUI(parent)",
        "    local root = vgui.Create(\"DPanel\", parent)",
        "    root:Dock(FILL)",
        "    root:SetPaintBackground(false)",
    }
    for _, w in ipairs(layout.widgets) do
        -- Общая часть одинакова для всех видов; специфика — в spec.code
        -- (реестр A.WidgetSpec). Раньше здесь была лестница из
        -- одиннадцати веток, где первые три строки повторялись дословно.
        local spec = A.Widget(w.kind)
        local x, y = numberToString(tonumber(w.x) or 0), numberToString(tonumber(w.y) or 0)
        local quote = function(value) return string.format("%q", tostring(value)) end
        out[#out + 1] = ""
        out[#out + 1] = "    local " .. spec.var .. " = vgui.Create(\"" .. spec.class .. "\", root)"
        out[#out + 1] = "    " .. spec.var .. ":SetPos(" .. x .. ", " .. y .. ")"
        out[#out + 1] = "    " .. spec.var .. ":SetSize("
            .. numberToString(tonumber(w.w) or spec.w) .. ", "
            .. numberToString(tonumber(w.h) or spec.h) .. ")"
        if spec.code then spec.code(out, w, spec.var, quote, numberToString) end
    end
    out[#out + 1] = "    return root"
    out[#out + 1] = "end"
    return out
end

--- Нормализация шаблонов макета (в проекте: templates).
function A.NormalizeTemplates(templates)
    local out = {}
    local seen = {}
    for _, t in ipairs(istable(templates) and templates or {}) do
        if istable(t) then
            local id = string.sub(A.Slug(t.id or t.name), 1, 32)
            if not seen[id] then
                seen[id] = true
                out[#out + 1] = { id = id, name = string.sub(string.Trim(tostring(t.name or id)), 1, 48),
                    layout = A.NormalizeLayout(t.layout) }
            end
        end
    end
    return out
end

-----------------------------------------------------------------------
-- ПРОВЕРКА ПРОЕКТА (валидатор: ошибки и предупреждения)
-----------------------------------------------------------------------
--[[ Валидатор — «тест на работоспособность» без сервера: ищет дыры в
     манифесте (несуществующий класс, модель не в каталоге, порт в никуда,
     битые координаты, пустые обязательные поля) и проверяет синтаксис
     сгенерированного черновика CompileString'ом. Правки без ошибок —
     нормальная заготовка для агента. ]]
function A.Validate(proj, catalog)
    proj = A.Normalize(proj)
    catalog = istable(catalog) and catalog or {}
    local errors, warnings = {}, {}
    local function err(s) errors[#errors + 1] = s end
    local function warn(s) warnings[#warnings + 1] = s end

    if #proj.nodes == 0 then err("нет узлов") end

    local byUid, seen = {}, {}
    for _, n in ipairs(proj.nodes) do
        if byUid[n.uid] then err("дубль uid " .. n.uid) end
        byUid[n.uid] = n
    end

    -- Ссылки и порты.
    for _, e in ipairs(proj.edges) do
        local a, b = byUid[e.a], byUid[e.b]
        if not a or not b then err("связь ссылается на несуществующий узел: " .. tostring(e.a) .. "→" .. tostring(e.b)) end
        if a and b then
            local da, db = A.DefOf(a.kind), A.DefOf(b.kind)
            local okA, okB = false, false
            for _, p in ipairs(da.ports.out or {}) do if p == e.ap then okA = true end end
            for _, p in ipairs(db.ports["in"] or {}) do if p == e.bp then okB = true end end
            if not okA then err("выход " .. tostring(e.ap) .. " не существует у " .. a.kind) end
            if not okB then err("вход " .. tostring(e.bp) .. " не существует у " .. b.kind) end
        end
    end

    -- Обязательные поля по типам + каталоги.
    local hasExport = false
    for _, n in ipairs(proj.nodes) do
        local d = n.data or {}
        if n.kind == "model" or n.kind == "prop" then
            if tostring(d.model or "") == "" then err("узел " .. n.uid .. " (модель) — модель не выбрана") end
            if tostring(d.model or "") ~= "" and not (catalog.models and catalog.models[tostring(d.model)]) then
                warn("модель " .. tostring(d.model) .. " не найдена в каталоге")
            end
        elseif n.kind == "entity" then
            if tostring(d.class or "") == "" then err("узел " .. n.uid .. " (энтити) — класс не выбран") end
            if tostring(d.class or "") ~= "" and not (catalog.ents and catalog.ents[tostring(d.class)]) then
                err("класс " .. tostring(d.class) .. " не найден среди scripted_ents")
            end
        elseif n.kind == "screen" then
            if tostring(d.size or "") == "" then warn("экран без размера") end
        elseif n.kind == "material" or n.kind == "photo" then
            local m = tostring(d.material or d.path or "")
            if m ~= "" and not (catalog.materials and (catalog.materials["materials/" .. m] or catalog.materials[m] or catalog.materials["data/" .. m])) then
                warn("материал/фото " .. m .. " не найдено в каталоге")
            end
        elseif n.kind == "sound" or n.kind == "music" then
            local s = tostring(d.sound or "")
            if s == "" then warn("узел " .. n.uid .. " — звук не выбран") end
            if s ~= "" and not (catalog.sounds and (catalog.sounds[s] or catalog.sounds["sound/" .. s])) then
                warn("звук " .. s .. " не найден в каталоге")
            end
        elseif n.kind == "keys" then
            local k = string.upper(tostring(d.key or ""))
            if k ~= "" and not string.find(k, "^IN_") and not string.find(k, "^KEY_") then
                warn("клавиша " .. tostring(d.key) .. " не похожа на IN_…/KEY_…")
            end
        elseif n.kind == "path" then
            if tostring(d.points or "") == "" then err("путь без точек") end
        elseif n.kind == "export" then
            hasExport = true
            if tostring(d.name or "") == "" then err("экспорт без имени") end
            if d.placeable then
                local tn = tostring(d.tool or "")
                if tn == "" then err("размещение включено, а имя тула пустое") end
                if tn ~= "" and not string.find(tn, "^grm_") then warn("имя тула обычно начинается с grm_") end
            end
        end
        -- Позиция/поворот: должны быть числами.
        local pos, ang = d.pos, d.ang
        if pos and (type(pos.x) ~= "number" or type(pos.y) ~= "number" or type(pos.z) ~= "number") then
            err("узел " .. n.uid .. " — битая позиция")
        end
        if ang and (type(ang.p) ~= "number" or type(ang.y) ~= "number" or type(ang.r) ~= "number") then
            err("узел " .. n.uid .. " — битый поворот")
        end
    end
    if not hasExport then warn("нет узла ЭКСПОРТ — нечего собирать") end

    -- Макет: размеры и координаты.
    local lay = A.NormalizeLayout(proj.layout)
    for _, w in ipairs(lay.widgets) do
        if (tonumber(w.x) or 0) + (tonumber(w.w) or 0) > lay.w + 4 then
            warn("виджет выходит за правый край макета")
        end
    end

    return { errors = errors, warnings = warnings }
end

--- Синтаксис сгенерированного черновика. Возвращает ok, err.
function A.CheckSyntax(proj)
    local text = A.Generate(proj)
    local fn, err = CompileString(text, "grm_astudio_syntax")
    if fn then return true end
    return false, err
end

--- Пустой каталов для валидатора (все поля false — только ошибки).
function A.EmptyCatalog()
    return { models = {}, materials = {}, sounds = {}, ents = {} }
end

-----------------------------------------------------------------------
-- КОНСТРУКТОР РАЗМЕЩЕНИЯ: спавн префаба и файл тула
-----------------------------------------------------------------------
--- Полный текст тул-файла для конструктора размещения.
function A.ToolFile(proj, toolName, toolCat)
    proj = A.Normalize(proj)
    toolName = string.sub(tostring(toolName or "grm_studio_prefab"), 1, 48)
    toolCat = string.sub(tostring(toolCat or "GRM Studio"), 1, 48)
    local out = {
        "--[[ Сгенерировано студией аддона. Тул: ЛКМ — поставить префаб,",
        "     ПКМ — убрать последний. Путь: lua/weapons/gmod_tool/stools/" .. toolName .. ".lua ]]",
        "TOOL.Name = " .. string.format("%q", tostring(proj.name or "Префаб")),
        "TOOL.Category = " .. string.format("%q", toolCat),
        "TOOL.ClientConVar[ \"\" ] = 0",
        "TOOL.Information = { { name = \"left\" }, { name = \"right\" } }",
        "local function prefab(origin, ang)",
        "    local list = {}",
        "    -- узлы проекта (см. раздел «Префаб» компиляции)",
    }
    for _, n in ipairs(proj.nodes) do
        local d = n.data or {}
        if (n.kind == "model" or n.kind == "prop" or n.kind == "entity") and tostring(d.model or d.class or "") ~= "" then
            local cls = n.kind == "entity" and tostring(d.class) or "prop_physics"
            local mdl = n.kind == "entity" and "" or string.format(", %q", tostring(d.model))
            out[#out + 1] = string.format("    local e = ents.Create(%q)%s -- %s", cls, mdl, n.uid)
            out[#out + 1] = string.format("    e:SetPos(origin + %s)", vectorToCtor(d.pos, "Vector"))
            out[#out + 1] = string.format("    e:SetAngles(ang + %s)", angleToCtor(d.ang))
            out[#out + 1] = "    e:Spawn() list[#list + 1] = e"
        elseif n.kind == "light" then
            out[#out + 1] = string.format("    local l = ents.Create(\"light\") -- %s", n.uid)
            out[#out + 1] = string.format("    l:SetPos(origin + %s)", vectorToCtor(d.pos, "Vector"))
            out[#out + 1] = "    l:Spawn() list[#list + 1] = l"
        end
    end
    out[#out + 1] = "    return list"
    out[#out + 1] = "end"
    out[#out + 1] = "TOOL.LeftClick = function(swep)"
    out[#out + 1] = "    local tr = swep:GetOwner():GetEyeTrace()"
    out[#out + 1] = "    if not IsValid(tr.Entity) and tr.HitPos == Vector(0,0,0) then return end"
    out[#out + 1] = "    local ang = tr.HitNormal:Angle()"
    out[#out + 1] = "    local list = prefab(tr.HitPos, ang)"
    out[#out + 1] = "    if #list == 0 then return end"
    out[#out + 1] = "    undo.Create(\"Студия: \" .. TOOL.Name)"
    out[#out + 1] = "        for _, e in ipairs(list) do undo.AddEntity(e) end"
    out[#out + 1] = "    undo.Finish()"
    out[#out + 1] = "    return true"
    out[#out + 1] = "end"
    out[#out + 1] = "TOOL.RightClick = function(swep)"
    out[#out + 1] = "    local tr = swep:GetOwner():GetEyeTrace()"
    out[#out + 1] = "    if IsValid(tr.Entity) then tr.Entity:Remove() end"
    out[#out + 1] = "end"
    -- Валидная Lua: client convar не нужен, но GMod требует TOOL.ClientConVar таблицу.
    out[#out + 1] = "TOOL.ClientConVar = {}"
    out[#out + 1] = "function TOOL:DrawHUD() end"
    return table.concat(out, "\n") .. "\n"
end

--[[ Генератор дополняется разделом макета и тула (см. A.Generate ниже). ]]

-- Реестр модулей (без жёсткой зависимости).
if GRM.Modules and GRM.Modules.Register then
    GRM.Modules.Register("addonstudio", {
        label = "Студия аддонов", version = A.Version,
        Status = function() return "граф, 3D, генератор" end,
    })
end

if SERVER then
    util.AddNetworkString("GRM_AS_Open")
    util.AddNetworkString("GRM_AS_Sync")
    util.AddNetworkString("GRM_AS_Act")
end

print("[GRM Addon Studio] core v" .. A.Version .. " loaded")
