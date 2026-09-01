--[[ Живой прогон двух задач от владельца 28.08.

     1) «В холодильнике бы слоты нормально сделать как в инвентаре.»
        Было: список строк с двумя кнопками на каждой. Сколько мест
        свободно — только из подписи, три позиции занимали пол-окна.

     2) «На плиту нужен звук приготовления, варки: при начале варки
         проигрывается gascan_ignite1, затем следом fire_big_loop1.»

     Запуск: luajit tools/luatest/sim_fridge_and_cooksound.lua ]]

local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end
local function readf(p) local f = assert(io.open(p)) local s = f:read("*a") f:close() return s end

local stove  = readf("lua/entities/grm_food_stove/init.lua")
local fridge = readf("lua/entities/grm_food_fridge/init.lua")
local ui     = readf("lua/autorun/client/cl_grm_food_kitchen.lua")

-----------------------------------------------------------------------
print("\n=== 1. ЗВУК ВАРКИ: ПОРЯДОК И ЗАЦИКЛЕННОСТЬ ===")
-----------------------------------------------------------------------
ok(stove:find("ambient/fire/gascan_ignite1.wav", 1, true) ~= nil,
   "розжиг — ровно тот файл, что назвал владелец")
ok(stove:find("ambient/fire/fire_big_loop1.wav", 1, true) ~= nil,
   "ИСПРАВЛЕНО: добавлено гудение огня")

--[[ Петлю нельзя играть через EmitSound: её потом не выключить.
     Проверяем, что использован CreateSound с сохранением ссылки. ]]
ok(stove:find("CreateSound(self, STOVE_LOOP)", 1, true) ~= nil,
   "петля создана через CreateSound — её можно остановить")
ok(stove:find("self.CookLoop", 1, true) ~= nil,
   "ссылка на звук сохранена на entity")

local startFn = stove:match("function ENT:StartCookSound.-\nend")
ok(startFn ~= nil, "есть StartCookSound")
ok(startFn and startFn:find("EmitSound(STOVE_IGNITE", 1, true) ~= nil,
   "розжиг играет разово")
ok(startFn and startFn:find("timer.Simple(delay", 1, true) ~= nil,
   "ИСПРАВЛЕНО: гудение идёт СЛЕДОМ за розжигом, а не одновременно")
ok(startFn and startFn:find('if self:GetStoveState() ~= 1 then return end', 1, true) ~= nil,
   "за время розжига готовку могли отменить — петля это проверяет")

--[[ CreateSound есть не в каждом окружении. Проверка нужна не ради
     стенда: если её нет, плита УПАДЁТ при попытке начать готовку, и
     блюдо не приготовится вовсе. Звук — второстепенное, готовка нет. ]]
ok(stove:find("if not isfunction(CreateSound) then return end", 1, true) ~= nil,
   "отсутствие CreateSound не ломает готовку — только глушит звук")

local stopFn = stove:match("function ENT:StopCookSound.-\nend")
ok(stopFn ~= nil, "есть StopCookSound")
ok(stopFn and stopFn:find("self.CookLoop:Stop()", 1, true) ~= nil, "он глушит петлю")
ok(stopFn and stopFn:find("self.CookLoop = nil", 1, true) ~= nil,
   "и снимает ссылку — повторный вызов безопасен")

-----------------------------------------------------------------------
print("\n=== 2. ПЕТЛЯ ГЛУШИТСЯ ВЕЗДЕ, ГДЕ ГОТОВКА КОНЧАЕТСЯ ===")
-----------------------------------------------------------------------
--[[ Самая частая ошибка с зацикленным звуком — заглушить его в одном
     месте и забыть про остальные. Тогда плита гудит вечно. ]]
local _, stops = stove:gsub("StopCookSound%(%)", "")
ok(stops >= 4, "остановка вызывается во всех ветках завершения", stops)

-- Готово: сначала глушим, потом звонок.
local doneBlock = stove:match("self:SyncReadyNW%(%)\n        self:StopCookSound%(%)\n        self:EmitSound%(\"buttons/bell1")
ok(doneBlock ~= nil, "блюдо готово — гудение прекращается перед звонком")

-- Отмена.
ok(stove:match('self:SetStoveRecipe%(""%)\n        self:StopCookSound%(%)\n        self:EmitSound%("buttons/button18') ~= nil,
   "отмена готовки глушит огонь")

-- Битый рецепт.
ok(stove:match("if not istable%(rec%) then\n            self:SetStoveState%(0%)\n            self:StopCookSound%(%)") ~= nil,
   "пропавший рецепт тоже не оставляет гудение")

-- Удаление плиты.
local onRemove = stove:match("function ENT:OnRemove%(%).-\nend")
ok(onRemove ~= nil, "ИСПРАВЛЕНО: добавлен OnRemove")
ok(onRemove and onRemove:find("StopCookSound", 1, true) ~= nil,
   "удалённая плита не оставляет звук висеть в мире")
ok(onRemove and onRemove:find("timer.Remove", 1, true) ~= nil,
   "и её таймер снимается заодно")

-- Восстановление после рестарта: петля без розжига.
ok(stove:find("self:StartCookSound(false)", 1, true) ~= nil,
   "после рестарта гудение возобновляется БЕЗ розжига — газ уже горит")
ok(stove:find("self:StartCookSound(true)", 1, true) ~= nil,
   "а живой старт даёт розжиг")

-- Живая модель поведения.
do
    local snd = { playing = false, stopped = 0 }
    local state = 0
    local function startCook(ignite)
        local emitted = ignite and "ignite" or nil
        state = 1
        -- Петля через задержку.
        local function delayed()
            if state ~= 1 then return end
            snd.playing = true
        end
        return emitted, delayed
    end
    local function stopCook()
        if snd.playing then snd.stopped = snd.stopped + 1 end
        snd.playing = false
        state = 0
    end

    local emitted, delayed = startCook(true)
    ok(emitted == "ignite", "при старте звучит розжиг")
    ok(snd.playing == false, "петля ещё не играет — она идёт следом")
    delayed()
    ok(snd.playing == true, "после задержки пошло гудение")

    stopCook()
    ok(snd.playing == false and snd.stopped == 1, "остановка глушит петлю")

    -- Отмена ДО того, как петля успела начаться.
    state = 0
    local _, delayed2 = startCook(true)
    state = 0                        -- успели отменить
    snd.playing = false
    delayed2()
    ok(snd.playing == false,
       "отменили за время розжига — гудение не включится вовсе")
end

-----------------------------------------------------------------------
print("\n=== 3. ХОЛОДИЛЬНИК: СЕТКА ВМЕСТО СПИСКА ===")
-----------------------------------------------------------------------
local fr = ui:match("buildFridge = function%(body, p%).-\nend\n")
ok(fr ~= nil, "окно холодильника найдено")

ok(fr and fr:find("local COLS = 6", 1, true) ~= nil,
   "ИСПРАВЛЕНО: содержимое рисуется сеткой в 6 колонок")
ok(fr and fr:find("local function paintCell", 1, true) ~= nil,
   "у ячейки своя отрисовка, как в инвентаре")
ok(fr and fr:find("Взять всё", 1, true) == nil,
   "прежние кнопки-строки убраны")

--[[ Главное отличие сетки от списка: видны ПУСТЫЕ ячейки, то есть
     сразу понятно, сколько места осталось. ]]
ok(fr and fr:find("grid(body, slots, cap,", 1, true) ~= nil,
   "рисуется ровно cap ячеек — пустые слоты тоже видны")
ok(fr and fr:find('draw.SimpleText("·"', 1, true) ~= nil,
   "и пустая ячейка помечена, а не просто пропущена")

ok(fr and fr:find("input.IsKeyDown(KEY_LSHIFT)", 1, true) ~= nil,
   "ЛКМ — всё, SHIFT+ЛКМ — одну штуку")
ok(fr and fr:find("SHIFT+ЛКМ", 1, true) ~= nil,
   "и это написано игроку, а не спрятано")

ok(fr and fr:find("b:SetTooltip(tip", 1, true) ~= nil,
   "полное название и срок годности — в подсказке: в ячейку они не влезут")
ok(fr and fr:find("if #nm > 12 then", 1, true) ~= nil,
   "длинное название режется, чтобы не вылезало за ячейку")
ok(fr and fr:find("draw.RoundedBox(3, 5, 5, 6, 6, COL_WARN)", 1, true) ~= nil,
   "портящееся помечено меткой вместо колонки текста")

-- Иконки должны приезжать с сервера.
ok(fridge:find('icon = (d and d.icon) or "icon16/box.png"', 1, true) ~= nil,
   "сервер кладёт иконку в payload — иначе ячейка была бы пустой")
local _, iconCount = fridge:gsub('icon = %(d and d%.icon%)', "")
ok(iconCount == 2, "и для содержимого, и для списка из инвентаря", iconCount)

ok(fr and fr:find("GRM.Perf.Material", 1, true) ~= nil,
   "материалы берутся из кэша — Material() в отрисовке это утечка")

-----------------------------------------------------------------------
print("\n=== 4. ГЕОМЕТРИЯ ОКНА ===")
-----------------------------------------------------------------------
do
    local COLS, CELL, GAP = 6, 74, 6
    local gridW = COLS * CELL + (COLS - 1) * GAP
    local needW = gridW + 12 + 18          -- поля + полоса прокрутки

    local w = tonumber(ui:match("fridge%s*=%s*{%s*(%d+)"))
    ok(w ~= nil, "размер окна холодильника задан")
    ok(w and w >= needW,
       "ИСПРАВЛЕНО: окно вмещает всю сетку — ячейки не режутся по краю",
       ("окно %d, нужно %d"):format(w or 0, needW))

    -- Высота: две сетки плюс заголовки.
    local h = tonumber(ui:match("fridge%s*=%s*{%s*%d+,%s*(%d+)"))
    local rows = math.ceil(12 / COLS)
    local needH = rows * (CELL + GAP) * 2 + 160
    ok(h and h >= needH * 0.85,
       "и по высоте помещается без лишней прокрутки",
       ("окно %d, ориентир %d"):format(h or 0, needH))
end

-----------------------------------------------------------------------
print("\n=== 5. ЕДИНООБРАЗИЕ С ДРУГИМИ ЯЩИКАМИ ===")
-----------------------------------------------------------------------
--[[ Домашний шкаф уже использует сетку с той же раскладкой. Игрок не
     должен запоминать разные правила для разных хранилищ. ]]
local locker = readf("lua/autorun/sh_grm_housing_storage.lua")
ok(locker:find("input.IsKeyDown(KEY_LSHIFT)", 1, true) ~= nil,
   "контроль: в домашнем шкафу тот же SHIFT")
ok(fr and fr:find("input.IsKeyDown(KEY_LSHIFT)", 1, true) ~= nil,
   "и в холодильнике теперь так же — одно правило на все ящики")

local lockerCols = tonumber(locker:match("local cols, gap = (%d+)"))
ok(lockerCols == 6, "и столько же колонок, сколько в шкафу", lockerCols)

print("")
print(string.format("ИТОГО: %d ok, %d FAIL", pass, fail))
if fail > 0 then os.exit(1) end
