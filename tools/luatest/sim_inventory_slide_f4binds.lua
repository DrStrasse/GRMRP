--[[--------------------------------------------------------------------
    sim_inventory_slide_f4binds — раздвижное окно инвентаря, бинд его
    открытия и единообразие клавиш в F4.

    ЗАКАЗ ВЛАДЕЛЬЦА (31.08): «инвентарь открывается плавно, окно не
    сразу отрисовывается, а как бы выходит слева и справа… одна часть с
    показом персонажа выходит слева, а инвентарь плавно вылетает справа
    в центр. Посмотри что можно сделать с инвентарём + в F4 в настройки
    нужна позиция для бинда кнопки открытия инвентаря и само F4 приведи
    в порядок в плане биндов кнопок, единообразия размеров».

    ЧТО БЫЛО.
      1) Окно инвентаря появлялось мгновенно и целиком, одной панелью.
      2) Бинд открытия инвентаря НЕ СУЩЕСТВОВАЛ: в sh_grm_inventory.lua
         висел хук PlayerBindPress с пустым телом и комментарием
         «Можно добавить бинд на кнопку». Инвентарь открывался только
         командой /inv или через C-меню.
      3) Бинды в F4 верстались вручную, каждый своими координатами:
         замок транспорта — подпись 220 и поле на X=240, соц.анимации —
         подпись 180 и поле на X=160. Размеры не совпадали.

    ЧТО ПРОВЕРЯЕМ. Траекторию выезда считаем БОЕВОЙ функцией A.SlideX,
    загруженной из модуля, а не её пересказом: именно в ней легко
    ошибиться со знаком и отправить панель не в ту сторону.

    Запуск: luajit tools/luatest/sim_inventory_slide_f4binds.lua
----------------------------------------------------------------------]]

local pass, fail = 0, 0
local function ok(v, name, extra)
    if v then pass = pass + 1 print("  ok   " .. name)
    else fail = fail + 1 print("  FAIL " .. name .. "   " .. tostring(extra or "")) end
end
local function near(a, b, eps)
    return math.abs((tonumber(a) or 0) - (tonumber(b) or 0)) <= (eps or 0.001)
end

local function readf(p)
    local fh = assert(io.open(p, "rb"))
    local t = fh:read("*a")
    fh:close()
    return t
end

local invSrc = readf("lua/autorun/client/cl_grm_inventory_ui.lua")
local coreSrc = readf("lua/autorun/sh_grm_inventory.lua")
local f4Src = readf("lua/autorun/sh_grm_f4menu.lua")

-----------------------------------------------------------------------
print("\n=== 1. БОЕВАЯ ФУНКЦИЯ ТРАЕКТОРИИ ===")
-----------------------------------------------------------------------
--[[ Вытаскиваем блок анимации из модуля и исполняем его по-настоящему.
     Стенд, гоняющий копию формулы, не поймает регрессию в модуле. ]]
local animBlock = invSrc:match("(INV%.Anim = INV%.Anim or {}.-\nend)\n\nlocal charPanel")
ok(animBlock ~= nil, "блок анимации найден в модуле")

local A
do
    local env = {
        INV = {},
        math = math,
        ScrW = function() return 1920 end,
        ScrH = function() return 1080 end,
    }
    env.math.Clamp = function(v, lo, hi)
        v = tonumber(v) or lo
        if v < lo then return lo end
        if v > hi then return hi end
        return v
    end
    local chunk = assert(loadstring(animBlock .. "\nreturn INV.Anim"))
    setfenv(chunk, env)
    A = chunk()
end
ok(A ~= nil and A.SlideX ~= nil, "функция выезда доступна")

-----------------------------------------------------------------------
print("\n=== 2. ПОЛОВИНЫ ЕДУТ С РАЗНЫХ СТОРОН ===")
-----------------------------------------------------------------------
local SW = 1920
--[[ Размеры половин 31.08 стали считаться от экрана (A.Layout) вместо
     жёстких A.LeftW / A.RightW — окно теперь во весь экран. Берём их
     оттуда же, откуда берёт сам модуль: проверять надо траекторию, а
     не конкретные числа, которые владелец может ещё раз попросить
     поменять. ]]
local LEFT_W, RIGHT_W, _H, X0 = A.Layout(SW, 1080)
local total = LEFT_W + A.Gap + RIGHT_W
local LEFT_TARGET = X0
local RIGHT_TARGET = X0 + LEFT_W + A.Gap

do
    -- В начале анимации панели ЗА краями экрана, каждая со своей стороны.
    local l0 = A.SlideX(0, LEFT_TARGET, true, LEFT_W, SW)
    local r0 = A.SlideX(0, RIGHT_TARGET, false, RIGHT_W, SW)
    ok(l0 + LEFT_W <= 0, "левая половина стартует за ЛЕВЫМ краем экрана", l0)
    ok(r0 >= SW, "правая половина стартует за ПРАВЫМ краем экрана", r0)

    -- В конце — точно на своих местах.
    ok(near(A.SlideX(1, LEFT_TARGET, true, LEFT_W, SW), LEFT_TARGET, 1),
        "левая доезжает ровно до своего места", A.SlideX(1, LEFT_TARGET, true, LEFT_W, SW))
    ok(near(A.SlideX(1, RIGHT_TARGET, false, RIGHT_W, SW), RIGHT_TARGET, 1),
        "правая доезжает ровно до своего места", A.SlideX(1, RIGHT_TARGET, false, RIGHT_W, SW))
end

do
    --[[ Направление движения. Тут легко перепутать знак и отправить
         панель не в ту сторону — визуально это «окно улетает». ]]
    local prevL, prevR = nil, nil
    local badL, badR = 0, 0
    for i = 0, 20 do
        local t = i / 20
        local l = A.SlideX(t, LEFT_TARGET, true, LEFT_W, SW)
        local r = A.SlideX(t, RIGHT_TARGET, false, RIGHT_W, SW)
        if prevL and l < prevL then badL = badL + 1 end   -- левая едет ВПРАВО
        if prevR and r > prevR then badR = badR + 1 end   -- правая едет ВЛЕВО
        prevL, prevR = l, r
    end
    ok(badL == 0, "левая всё время движется вправо, к центру", badL)
    ok(badR == 0, "правая всё время движется влево, к центру", badR)
end

do
    -- Половины не наезжают друг на друга в конечном положении.
    ok(LEFT_TARGET + LEFT_W <= RIGHT_TARGET,
        "между половинами есть зазор, они не перекрываются",
        RIGHT_TARGET - (LEFT_TARGET + LEFT_W))
    ok(A.Gap > 0, "зазор задан явно", A.Gap)
    ok(X0 >= 0 and X0 + total <= SW, "обе половины помещаются на экран 1920",
        X0 .. "+" .. total)
end

-----------------------------------------------------------------------
print("\n=== 3. ПЛАВНОСТЬ: ЗАМЕДЛЕНИЕ К КОНЦУ ===")
-----------------------------------------------------------------------
do
    ok(near(A.Ease(0), 0), "в начале смещения нет")
    ok(near(A.Ease(1), 1), "в конце — полное смещение")

    --[[ Линейное движение выглядит механически. Проверяем, что путь
         НЕ линеен: за первую половину времени проходится заметно
         больше половины пути. ]]
    ok(A.Ease(0.5) > 0.6, "за половину времени пройдено больше половины пути (ease-out)",
        A.Ease(0.5))

    -- Скорость должна падать, а не расти.
    local prevStep, growing = nil, 0
    for i = 1, 20 do
        local step = A.Ease(i / 20) - A.Ease((i - 1) / 20)
        if prevStep and step > prevStep + 1e-9 then growing = growing + 1 end
        prevStep = step
    end
    ok(growing == 0, "шаг всё время уменьшается — панель мягко тормозит", growing)

    -- Выход за пределы не ломает расчёт.
    ok(near(A.Ease(-5), 0), "отрицательное время не уводит панель за экран")
    ok(near(A.Ease(99), 1), "перелёт по времени не двигает панель дальше места")
end

-----------------------------------------------------------------------
print("\n=== 4. РАЗНЫЕ РАЗРЕШЕНИЯ ЭКРАНА ===")
-----------------------------------------------------------------------
do
    local bad = {}
    for _, sw in ipairs({ 1280, 1600, 1920, 2560, 3840 }) do
        local x0 = math.floor((sw - total) * 0.5)
        local lt, rt = x0, x0 + LEFT_W + A.Gap
        local l1 = A.SlideX(1, lt, true, LEFT_W, sw)
        local r1 = A.SlideX(1, rt, false, RIGHT_W, sw)
        if not near(l1, lt, 1) or not near(r1, rt, 1) then
            bad[#bad + 1] = sw
        end
        -- И на старте всё ещё за краями.
        if A.SlideX(0, lt, true, LEFT_W, sw) + LEFT_W > 0 then bad[#bad + 1] = sw end
        if A.SlideX(0, rt, false, RIGHT_W, sw) < sw then bad[#bad + 1] = sw end
    end
    ok(#bad == 0, "выезд корректен на 1280…3840", table.concat(bad, ","))
end

-----------------------------------------------------------------------
print("\n=== 5. ИСХОДНИК ИНВЕНТАРЯ ===")
-----------------------------------------------------------------------
do
    ok(invSrc:find("DModelPanel", 1, true) ~= nil,
        "в левой половине 3D-модель персонажа")
    ok(invSrc:find("lp:GetModel()", 1, true) ~= nil, "берётся своя модель")
    ok(invSrc:find("SetBodygroup", 1, true) ~= nil,
        "bodygroups копируются — иначе форма превратится в базовую модель")
    ok(invSrc:find("GRM.HUD.BarList", 1, true) ~= nil,
        "полосы состояния берутся из общего реестра, а не считаются заново")
    ok(invSrc:find("GRM_RPName", 1, true) ~= nil, "показывается RP-имя персонажа")
    ok(invSrc:find("GRM_FactionDisplay", 1, true) ~= nil, "и фракция")

    ok(invSrc:find("function INV.CloseGUI", 1, true) ~= nil,
        "есть закрытие с обратным выездом")
    ok(invSrc:find("function INV.IsOpen", 1, true) ~= nil,
        "есть проверка открытости — нужна биндом для переключения")

    --[[ Escape у DFrame зовёт Close(), который просто ПРЯЧЕТ окно.
         Без перехвата половины остались бы висеть за краями экрана,
         а левая панель — на виду. ]]
    ok(invSrc:find("f.Close = function() INV.CloseGUI() end", 1, true) ~= nil,
        "Escape закрывает через анимацию, а не прячет окно")

    local onRemove = invSrc:match("f%.OnRemove = function%(%)(.-)\n    end")
    ok(onRemove and onRemove:find("charPanel:Remove()", 1, true) ~= nil,
        "левая половина удаляется вместе с правой — иначе останется висеть")
end

-----------------------------------------------------------------------
print("\n=== 6. БИНД ОТКРЫТИЯ ИНВЕНТАРЯ ===")
-----------------------------------------------------------------------
do
    --[[ ВОСПРОИЗВЕДЕНИЕ БАГА: раньше тут был хук с ПУСТЫМ телом. ]]
    ok(coreSrc:find("-- Можно добавить бинд на кнопку", 1, true) == nil,
        "ИСПРАВЛЕНО: пустая заглушка бинда убрана")
    ok(coreSrc:find('CreateClientConVar("grm_cl_inv_key"', 1, true) ~= nil,
        "конвар клавиши инвентаря создаётся")

    local hookBody = coreSrc:match('hook%.Add%("PlayerButtonDown", "GRM_Inv_Bind".-\n    end%)')
    ok(hookBody ~= nil, "бинд повешен на нажатие клавиши")
    ok(hookBody and hookBody:find("RequestOpen()", 1, true) ~= nil,
        "по нажатию инвентарь открывается")
    ok(hookBody and hookBody:find("CloseGUI()", 1, true) ~= nil,
        "повторное нажатие закрывает — клавиша работает переключателем")
    ok(hookBody and hookBody:find("IsTyping", 1, true) ~= nil,
        "в чате клавиша не срабатывает")
    ok(hookBody and hookBody:find("IsGameUIVisible", 1, true) ~= nil,
        "при открытом игровом меню тоже не срабатывает")
    ok(hookBody and hookBody:find("invKeyLock", 1, true) ~= nil,
        "есть защита от дребезга при удержании клавиши")

    --[[ По умолчанию бинд ВЫКЛЮЧЕН. Занимать игроку клавишу молча
         нельзя: в GMod она может быть уже под чем-то занята. ]]
    local cv = coreSrc:match('CreateClientConVar%("grm_cl_inv_key",%s*"([^"]*)"')
    ok(cv == "0", "по умолчанию клавиша не назначена", cv)
end

-----------------------------------------------------------------------
print("\n=== 7. F4: ЕДИНООБРАЗИЕ БИНДОВ ===")
-----------------------------------------------------------------------
do
    ok(f4Src:find("local function bindRow", 1, true) ~= nil,
        "ИСПРАВЛЕНО: появился единый конструктор строки бинда")

    -- Ручная вёрстка старых биндов должна была уйти.
    ok(f4Src:find('bindV:SetPos(240, 58)', 1, true) == nil,
        "ручная вёрстка бинда транспорта убрана")
    ok(f4Src:find('binder:SetPos(160, 58)', 1, true) == nil,
        "ручная вёрстка бинда соц.анимаций убрана")

    --[[ Ключевая проверка: все DBinder'ы создаются В ОДНОМ месте.
         Пока их лепят по файлу вручную, размеры снова разъедутся. ]]
    local _, binderCount = f4Src:gsub('vgui%.Create%("DBinder"', "")
    ok(binderCount == 1, "DBinder создаётся ровно в одном месте — размеры не разойдутся",
        binderCount)

    -- Список биндов задан данными, а не копипастой вёрстки.
    ok(f4Src:find("grm_cl_inv_key", 1, true) ~= nil, "инвентарь есть в списке клавиш F4")
    ok(f4Src:find("grm_cl_social_key", 1, true) ~= nil, "соц.анимации на месте")
    ok(f4Src:find("grm_cl_vehlock_key", 1, true) ~= nil, "замок транспорта на месте")

    local binds = f4Src:match("local BINDS = {(.-)\n    }")
    ok(binds ~= nil, "бинды перечислены таблицей")
    if binds then
        local _, n = binds:gsub('grm_cl_', "")
        ok(n == 3, "в списке три клавиши", n)
    end

    -- Высота блока считается от числа строк, а не забита числом.
    ok(f4Src:find("HEAD + #BINDS * BIND_ROW_H", 1, true) ~= nil,
        "высота блока считается по числу биндов — добавление не сломает вёрстку")

    -- Сброс: DBinder не умеет снимать назначение сам.
    local rowBody = f4Src:match("local function bindRow.-\n    return row\nend")
    ok(rowBody and rowBody:find("Сбросить", 1, true) ~= nil,
        "у каждой клавиши есть сброс — иначе бинд не отключить обратно")
    ok(rowBody and rowBody:find("BIND_LABEL_W", 1, true) ~= nil,
        "размеры вынесены в константы, а не вписаны числами")

    --[[ Ширина строки НЕ должна браться от родителя: блок докается, и
         на момент создания его ширина ещё не посчитана. ]]
    ok(rowBody and rowBody:find("parent:GetWide()", 1, true) == nil,
        "ширина строки не зависит от ещё не посчитанной ширины блока")
end

-----------------------------------------------------------------------
print(string.format("\nИТОГО: %d ok, %d FAIL", pass, fail))
os.exit(fail == 0 and 0 or 1)
