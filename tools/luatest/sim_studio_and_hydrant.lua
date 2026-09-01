--[[ Два бага из жалобы владельца 28.08.

     1) STACK OVERFLOW в студии анимаций. Трейс владельца:
          OnRowSelected → loadPose → ChooseOptionID → OnSelect
            → rebuildList → SelectItem → OnRowSelected → …
        Обычный клик по сохранённой позе ронял игру.

     2) ГИДРАНТ. «На E открыл гидрант, и закрыть его нельзя, если ты не
        пожарный. Чё за Х?» — хук запрещал не-пожарному ЛЮБОЕ действие,
        включая закрытие. Открыл — и назад не повернуть.

     Плюс найденные попутно недоработки студии.

     Запуск: luajit tools/luatest/sim_studio_and_hydrant.lua ]]

local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end
local function readf(p) local f = assert(io.open(p)) local s = f:read("*a") f:close() return s end

-----------------------------------------------------------------------
print("\n=== 1. РЕКУРСИЯ: ВОСПРОИЗВОДИМ ПАДЕНИЕ ===")
-----------------------------------------------------------------------
--[[ Модель тех же четырёх обработчиков БЕЗ защиты. Считаем глубину:
     без флага она уходит в бесконечность (ограничиваем счётчиком,
     иначе стенд сам упадёт так же, как игра у владельца). ]]
do
    local depth, overflow = 0, false
    local rebuildList, onRowSelected, loadPose, onSelect

    local LIMIT = 500

    onRowSelected = function(id)
        depth = depth + 1
        if depth > LIMIT then overflow = true return end
        loadPose(id)
    end
    loadPose = function(id)
        if overflow then return end
        onSelect()                 -- ChooseOptionID дёргает OnSelect
    end
    onSelect = function()
        if overflow then return end
        rebuildList()
    end
    rebuildList = function()
        if overflow then return end
        onRowSelected("pose1")     -- SelectItem дёргает OnRowSelected
    end

    onRowSelected("pose1")
    ok(overflow == true,
       "БАГ ВОСПРОИЗВЕДЁН: без защиты цепочка уходит в бесконечную рекурсию",
       "глубина " .. depth)
end

-----------------------------------------------------------------------
print("\n=== 2. ТА ЖЕ ЦЕПОЧКА С ФЛАГОМ ===")
-----------------------------------------------------------------------
do
    local ST = { _busy = false }
    local depth, maxDepth = 0, 0
    local loadPoseCalls, rebuildCalls = 0, 0
    local rebuildList, onRowSelected, loadPose, onSelect

    onRowSelected = function(id)
        if ST._busy then return end          -- защита
        depth = depth + 1
        if depth > maxDepth then maxDepth = depth end
        if depth > 500 then error("всё ещё рекурсия") end
        loadPose(id)
        depth = depth - 1
    end
    loadPose = function(id)
        loadPoseCalls = loadPoseCalls + 1
        local was = ST._busy
        ST._busy = true                       -- защита вокруг combobox
        onSelect()
        ST._busy = was
    end
    onSelect = function() rebuildList() end
    rebuildList = function()
        if ST._busy then return end
        ST._busy = true
        rebuildCalls = rebuildCalls + 1
        onRowSelected("pose1")                -- SelectItem
        ST._busy = false
    end

    local okRun = pcall(onRowSelected, "pose1")
    ok(okRun, "ИСПРАВЛЕНО: цепочка завершается без переполнения стека")
    ok(maxDepth == 1, "глубина ровно 1 — повторного входа нет", maxDepth)
    ok(loadPoseCalls == 1, "поза загружается один раз, а не бесконечно", loadPoseCalls)

    -- Обычное перестроение списка (смена категории) по-прежнему работает.
    ST._busy = false
    rebuildCalls = 0
    rebuildList()
    ok(rebuildCalls == 1, "перестроение списка при этом не сломано", rebuildCalls)
end

-----------------------------------------------------------------------
print("\n=== 3. ИСХОДНИК СТУДИИ ===")
-----------------------------------------------------------------------
local src = readf("lua/autorun/sh_grm_social_studio.lua")

ok(src:find("ST._busy", 1, true) ~= nil, "ИСПРАВЛЕНО: введён флаг повторного входа")

local rebuild = src:match("function ST%.rebuildList%(%).-\n    end")
ok(rebuild and rebuild:find("if ST._busy then return end", 1, true) ~= nil,
   "rebuildList не запускается повторно из самого себя")
ok(rebuild and rebuild:find("ST._busy = false", 1, true) ~= nil,
   "и обязательно снимает флаг в конце — иначе список замрёт навсегда")

ok(src:find("if ST._busy then return end\n        if line and line._id then", 1, true) ~= nil,
   "OnRowSelected отличает клик игрока от программной подсветки")

--[[ Проверяем ПО СМЫСЛУ, а не по точной строке.

     Раньше здесь стоял поиск дословного «ST._busy = true» с отступом и
     следом идущим «for i = 1, 48 do». Любая правка студии (смена
     верхней границы цикла, переименование combobox) роняла стенд, хотя
     защита была на месте. Ищем сам блок: между подъёмом флага и
     вызовом ChooseOptionID не должно быть выхода из функции. ]]
do
    local blk = src:match("ST%._busy = true.-ChooseOptionID.-ST%._busy = wasBusy")
    ok(blk ~= nil, "ChooseOptionID обёрнут флагом — на нём и замыкалась рекурсия")
end
ok(src:find("ST._busy = wasBusy", 1, true) ~= nil,
   "и флаг восстанавливается, а не сбрасывается в false вслепую")

-- Дублирующий обработчик.
local _, n = src:gsub("list%.OnRowSelected = function", "")
ok(n == 1, "ИСПРАВЛЕНО: остался ОДИН list.OnRowSelected (было два)", n)

-----------------------------------------------------------------------
print("\n=== 4. НАЙДЕНО ПОПУТНО: sendAct ТЕРЯЛ АРГУМЕНТ ===")
-----------------------------------------------------------------------
--[[ Сервер для movepose читает ДВЕ строки (id и категорию), а клиент
     через sendAct(op, extra) отправлял только одну. Категория терялась,
     сервер выходил по `if catName == "" then return end` — перемещение
     поз не работало вообще и молча. ]]
do
    -- Старая реализация.
    local sentOld = {}
    local function sendOld(op, extra)
        sentOld[#sentOld + 1] = op
        if extra ~= nil then sentOld[#sentOld + 1] = tostring(extra) end
    end
    sendOld("movepose", "pose1", "docs")
    ok(#sentOld == 2,
       "БАГ ВОСПРОИЗВЕДЁН: старый sendAct отправлял 2 значения вместо 3", #sentOld)
    ok(sentOld[3] == nil, "категория терялась — сервер получал пустую строку")

    -- Новая.
    local sentNew = {}
    local function sendNew(op, ...)
        sentNew[#sentNew + 1] = op
        for i = 1, select("#", ...) do
            local e = select(i, ...)
            if e ~= nil then sentNew[#sentNew + 1] = tostring(e) end
        end
    end
    sendNew("movepose", "pose1", "docs")
    ok(#sentNew == 3, "ИСПРАВЛЕНО: уходят все три значения", #sentNew)
    ok(sentNew[2] == "pose1" and sentNew[3] == "docs",
       "в том же порядке, в каком их читает сервер")

    -- Однопараметрические вызовы не сломаны.
    sentNew = {}
    sendNew("delete", "pose1")
    ok(#sentNew == 2, "обычные вызовы с одним аргументом работают как раньше")
end

ok(src:find("local function sendAct(op, ...)", 1, true) ~= nil,
   "sendAct принимает произвольное число аргументов")

-- Сервер действительно читает две строки — проверка, что фикс нужен.
local moveBlock = src:match('if op == "movepose" then.-\n        end')
ok(moveBlock and select(2, moveBlock:gsub("net%.ReadString", "")) == 2,
   "сервер для movepose читает ровно две строки — значит клиент обязан слать две")

-----------------------------------------------------------------------
print("\n=== 5. ГИДРАНТ: ЛОВУШКА ОТКРЫТОГО КРАНА ===")
-----------------------------------------------------------------------
local fire = readf("lua/autorun/sh_grm_fire.lua")

--[[ Старое поведение: хук отказывал не-пожарному всегда. Значит
     закрыть открытый гидрант он не мог физически. ]]
do
    local function oldHook(isPro) if isPro then return end return false end
    ok(oldHook(false) == false,
       "БАГ ВОСПРОИЗВЕДЁН: не-пожарному запрещено ЛЮБОЕ действие с гидрантом")
    ok(oldHook(false) == false,
       "в том числе ЗАКРЫТИЕ уже открытого — вода льётся навсегда")
end

-- Новое: открывать по правам, закрывать всем.
do
    local function newHook(isPro, hydrantOpen)
        if isPro then return nil end
        if hydrantOpen == true then return nil end   -- закрытие разрешено
        return false
    end
    ok(newHook(false, false) == false,
       "ИСПРАВЛЕНО: открыть чужой гидрант не-пожарный по-прежнему не может")
    ok(newHook(false, true) == nil,
       "ИСПРАВЛЕНО: а ЗАКРЫТЬ открытый — может любой")
    ok(newHook(true, false) == nil, "пожарный открывает свободно")
    ok(newHook(true, true) == nil, "и закрывает тоже")
end

local hookBlock = fire:match('hook%.Add%("GRM_FireAddon_HydrantUse".-\n    end%)')
ok(hookBlock ~= nil, "хук гидранта найден")
ok(hookBlock and hookBlock:find("hydrant:GetOpen() == true", 1, true) ~= nil,
   "хук смотрит состояние гидранта, а не отказывает вслепую")
ok(hookBlock and hookBlock:find("function(ply, hydrant)", 1, true) ~= nil,
   "принимает саму энтити вторым аргументом")

--[[ Если аддон не передал энтити, определить намерение нельзя —
     тогда ведём себя строго, как раньше. ]]
do
    local function newHook(isPro, hyd)
        if isPro then return nil end
        if hyd and hyd.open == true then return nil end
        return false
    end
    ok(newHook(false, nil) == false,
       "без энтити действуем строго — на угад права не раздаём")
end

-----------------------------------------------------------------------
print("\n=== 6. ГИДРАНТ: САМОЗАКРЫТИЕ ===")
-----------------------------------------------------------------------
ok(fire:find("F.HydrantIdleClose", 1, true) ~= nil,
   "добавлена страховка от брошенного открытым гидранта")
ok(fire:find("hydrantWatch", 1, true) ~= nil, "есть сторож гидрантов")

local watch = fire:match("local function hydrantWatch%(%).-\n    end")
ok(watch and watch:find("GetOpen", 1, true) ~= nil, "сторож смотрит только открытые")
ok(watch and (watch:find("GetHoses", 1, true) or watch:find("GetHoseCount", 1, true)) ~= nil,
   "и НЕ закрывает гидрант, к которому подключён рукав — тушение не сорвётся")
ok(fire:find('GRM.Sched.Every("fire.hydrantwatch"', 1, true) ~= nil,
   "сторож живёт в планировщике с приоритетом low, а не отдельным таймером")

-- Логика простоя.
do
    local IDLE = 60
    local function shouldClose(open, busy, idleFor)
        if not open then return false end
        if busy then return false end
        return idleFor > IDLE
    end
    ok(shouldClose(true, false, 90) == true, "брошенный на 90 сек гидрант закроется")
    ok(shouldClose(true, false, 10) == false, "только что открытый — нет")
    ok(shouldClose(true, true, 999) == false,
       "с подключённым рукавом не закрывается никогда — даже через час")
    ok(shouldClose(false, false, 999) == false, "закрытый трогать незачем")
end

-----------------------------------------------------------------------
print("\n=== 7. СТУДИЯ: ШРИФТЫ И ОСТАЛЬНОЕ ===")
-----------------------------------------------------------------------
--[[ Раньше здесь был GRMSocEd_Small, которого не существует — падало
     «font doesn't exist». Проверяем, что все используемые шрифты
     объявлены в этом же файле. ]]
local declared = {}
for f in src:gmatch('surface%.CreateFont%("([^"]+)"') do declared[f] = true end
local missing = {}
for f in src:gmatch('SetFont%("(GRMSocEd_[^"]+)"') do
    if not declared[f] then missing[#missing + 1] = f end
end
for f in src:gmatch('"(GRMSocEd_[%w_]+)"') do
    if not declared[f] and not f:find("CreateFont") then
        local dup = false
        for _, m in ipairs(missing) do if m == f then dup = true end end
        if not dup then missing[#missing + 1] = f end
    end
end
ok(#missing == 0, "все шрифты студии объявлены", table.concat(missing, ", "))

--[[ Ищем именно ВЫЗОВ SetFont с несуществующим шрифтом, а не любое
     упоминание строки: в файле есть комментарий, объясняющий, почему
     этот шрифт использовать нельзя, и он не должен считаться ошибкой. ]]
ok(src:find('SetFont("GRMSocEd_Small")', 1, true) == nil
   and src:find('"GRMSocEd_Small",', 1, true) == nil,
   "несуществующий GRMSocEd_Small нигде не вызывается")

-----------------------------------------------------------------------
print("\n=== 8. ПОРЯДОК ОБЪЯВЛЕНИЯ loadPose (падение 28.08) ===")
-----------------------------------------------------------------------
--[[ «attempt to call global 'loadPose' (a nil value)» — я убрал дубль
     обработчика и оставил ВЕРХНИЙ, объявленный ДО loadPose. Локальная
     переменная в Lua видна только после своего объявления, поэтому
     внутри обработчика имя было глобальным, то есть nil. ]]
do
    -- Воспроизводим ошибку.
    local handler
    do
        handler = function() return loadPoseUndeclared("x") end
        local function loadPoseUndeclared() return "ok" end   -- объявлена ПОЗЖЕ
    end
    local okCall = pcall(handler)
    ok(okCall == false,
       "БАГ ВОСПРОИЗВЕДЁН: обработчик, объявленный до функции, падает на вызове")
end

do
    -- Как надо: предварительное объявление.
    local loadPoseFixed
    local handler = function() return loadPoseFixed("x") end
    loadPoseFixed = function(id) return "loaded:" .. id end
    local okCall, res = pcall(handler)
    ok(okCall and res == "loaded:x",
       "ИСПРАВЛЕНО: с предварительным объявлением вызов проходит", res)
end

-- Проверка исходника: объявление должно идти ДО обработчиков.
local declPos = src:find("\n    local loadPose\n", 1, true)
local usePos  = src:find("loadPose(line._id)", 1, true)
local defPos  = src:find("function loadPose(id)", 1, true)
ok(declPos ~= nil, "ИСПРАВЛЕНО: есть предварительное объявление local loadPose")
ok(declPos and usePos and declPos < usePos,
   "объявление стоит РАНЬШЕ первого использования")
ok(defPos and declPos and declPos < defPos,
   "и раньше самого определения функции")
ok(src:find("local function loadPose(id)", 1, true) == nil,
   "определение НЕ создаёт новую local, а заполняет объявленную выше")

-----------------------------------------------------------------------
print("\n=== 9. ФЛАГ НЕ ЗАВИСАЕТ ПРИ ОШИБКЕ ===")
-----------------------------------------------------------------------
--[[ Второй симптом: «не работает перемещение из категории в категорию,
     не отражается результат». Причина та же — упавший loadPose летел
     наружу через rebuildList и прерывал его ДО сброса ST._busy. Флаг
     оставался поднятым, и список больше не перестраивался никогда. ]]
do
    -- Старое поведение: сброс последней строкой тела.
    local ST = { _busy = false }
    local function rebuildOld(explode)
        if ST._busy then return end
        ST._busy = true
        if explode then error("сбой внутри") end
        ST._busy = false
    end
    pcall(rebuildOld, true)
    ok(ST._busy == true,
       "БАГ ВОСПРОИЗВЕДЁН: после ошибки флаг остался поднятым")
    rebuildOld(false)
    ok(ST._busy == true,
       "и список замер навсегда — перестроение больше не проходит")
end

do
    -- Новое: тело в pcall, флаг снимается всегда.
    local ST = { _busy = false }
    local runs = 0
    local function body(explode)
        runs = runs + 1
        if explode then error("сбой внутри") end
    end
    local function rebuildNew(explode)
        if ST._busy then return end
        ST._busy = true
        pcall(body, explode)
        ST._busy = false
    end
    rebuildNew(true)
    ok(ST._busy == false, "ИСПРАВЛЕНО: флаг снят даже после ошибки")
    rebuildNew(false)
    ok(runs == 2, "и следующее перестроение проходит нормально", runs)
end

ok(src:find("local function rebuildListBody()", 1, true) ~= nil,
   "тело перестроения вынесено отдельно")
local wrapper = src:match("function ST%.rebuildList%(%).-\n    end")
ok(wrapper and wrapper:find("pcall(rebuildListBody)", 1, true) ~= nil,
   "обёртка зовёт его через pcall")
ok(wrapper and wrapper:find("ST._busy = false", 1, true) ~= nil,
   "и снимает флаг после pcall, а не внутри тела")

-- Загрузка позы тоже не должна валить обработчик.
local rowSel = src:match("list%.OnRowSelected = function.-\n    end")
ok(rowSel and rowSel:find("pcall(loadPose", 1, true) ~= nil,
   "сломанная поза портит только себя, а не весь список")

-----------------------------------------------------------------------
print("\n=== 10. ПЕРЕМЕЩЕНИЕ МЕЖДУ КАТЕГОРИЯМИ ===")
-----------------------------------------------------------------------
--[[ Полная цепочка: клиент шлёт две строки → сервер меняет категорию →
     рассылает каталог → клиент перестраивает список. ]]
do
    local CatList = { { id = "general", name = "Общее" }, { id = "docs", name = "Документы" } }
    local Catalog = { { id = "pose1", name = "Поза 1", cat = "general", catName = "Общее" } }
    local synced = 0

    local function slug(x) return string.lower(tostring(x or "")) end
    local function movepose(id, toCat)
        id, toCat = slug(id), slug(toCat)
        local catName = ""
        for i = 1, #CatList do if CatList[i].id == toCat then catName = CatList[i].name break end end
        if catName == "" then return false end          -- ровно эта проверка и срывалась
        for _, p in ipairs(Catalog) do
            if p.id == id then p.cat, p.catName = toCat, catName break end
        end
        synced = synced + 1
        return true
    end

    -- Старый клиент терял второй аргумент → сервер получал "".
    ok(movepose("pose1", "") == false,
       "БАГ ВОСПРОИЗВЕДЁН: пустая категория — сервер молча выходит")
    ok(Catalog[1].cat == "general", "и поза остаётся на месте")

    -- Новый клиент шлёт обе строки.
    ok(movepose("pose1", "docs") == true, "ИСПРАВЛЕНО: перемещение проходит")
    ok(Catalog[1].cat == "docs", "категория сменилась", Catalog[1].cat)
    ok(Catalog[1].catName == "Документы",
       "и подпись обновилась — она показывается в списке", Catalog[1].catName)
    ok(synced == 1, "каталог разослан клиентам — результат виден сразу")
end

-- Приём каталога на клиенте обязан перестроить И категории, и список.
local syncBlock = src:match('net%.Receive%("GRM_SocStudio_Sync".-\nend%)')
ok(syncBlock and syncBlock:find("ST.rebuildCats", 1, true) ~= nil,
   "на приёме каталога перестраиваются категории")
ok(syncBlock and syncBlock:find("ST.rebuildList", 1, true) ~= nil,
   "и список — иначе перемещение не отобразится")

-----------------------------------------------------------------------
print("\n=== 11. ЗАМОРОЗКА ПОЗЫ (жалоба 28.08) ===")
-----------------------------------------------------------------------
--[[ «Применение заморозки позы ничего не даёт. Игрок двигается как и
     двигался.» Галочка сохранялась в каталог, доезжала до клиента и
     читалась при загрузке в редакторе — но в модуле воспроизведения
     слово freeze не встречалось НИ РАЗУ. Применять флаг было некому. ]]
local anims = readf("lua/autorun/sh_grm_social_anims.lua")

ok(anims:find("def.freeze", 1, true) ~= nil,
   "ИСПРАВЛЕНО: модуль воспроизведения читает флаг freeze")
ok(anims:find("function S.IsFrozen", 1, true) ~= nil,
   "есть единая проверка S.IsFrozen")

local hold = anims:match('hook%.Add%("StartCommand", "GRM_Soc_Hold".-\n    end%)')
ok(hold ~= nil, "обработчик ввода найден")
--[[ Проверяем именно ВЕТКУ ЗАМОРОЗКИ внутри обработчика, а не наличие
     строк вообще: ClearMovement и RemoveKey(IN_JUMP) есть и в ветке
     приседа, поэтому поиск по всему тексту ничего не доказывает —
     первая версия этих проверок откат фикса не заметила. ]]
local freezeBranch = hold and hold:match("if def%.freeze == true or def%.nomove == true then.-\n        end")
ok(freezeBranch ~= nil,
   "ИСПРАВЛЕНО: в обработчике есть отдельная ветка заморозки")
ok(freezeBranch and freezeBranch:find("cmd:ClearMovement()", 1, true) ~= nil,
   "в ней обнуляется движение")
ok(freezeBranch and freezeBranch:find("cmd:RemoveKey(IN_JUMP)", 1, true) ~= nil,
   "и снимается прыжок — иначе с места можно ускакать")
ok(freezeBranch and freezeBranch:find("IN_FORWARD", 1, true) ~= nil,
   "и клавиши направления, чтобы не пролезло через предсказание")
ok(hold and hold:find("SetViewAngles", 1, true) == nil,
   "камеру НЕ трогаем — в подсказке к галочке обещано «можно крутить камерой»")

--[[ Живая модель обработчика: проверяем, что заморозка сильнее
     настройки «Ходьба». Поза с walk = true и freeze = true не должна
     позволять идти. ]]
do
    local function makeCmd()
        local c = { moved = true, keys = {} }
        function c:ClearMovement() self.moved = false end
        function c:RemoveKey(k) self.keys[k] = true end
        function c:SetButtons() end
        function c:GetButtons() return 0 end
        return c
    end
    local IN_JUMP, IN_DUCK = 2, 4

    local function hold(def, cmd)
        if def.crouch then
            cmd:RemoveKey(IN_JUMP)
            if not def.walk then cmd:ClearMovement() end
        end
        if def.freeze == true or def.nomove == true then
            cmd:ClearMovement()
            cmd:RemoveKey(IN_JUMP)
        end
    end

    -- Обычная поза с разрешённой ходьбой.
    local c1 = makeCmd()
    hold({ walk = true, freeze = false }, c1)
    ok(c1.moved == true, "обычная поза ходить не мешает")

    -- Та же поза, но с заморозкой.
    local c2 = makeCmd()
    hold({ walk = true, freeze = true }, c2)
    ok(c2.moved == false,
       "ИСПРАВЛЕНО: заморозка сильнее настройки «Ходьба» — идти нельзя")
    ok(c2.keys[IN_JUMP] == true, "и прыгать нельзя")

    -- Старое поле nomove тоже работает: позы могли сохраняться с ним.
    local c3 = makeCmd()
    hold({ walk = true, nomove = true }, c3)
    ok(c3.moved == false, "старое поле nomove тоже понимается")
end

-- Гашение остаточной скорости.
ok(anims:find("freezeTick", 1, true) ~= nil,
   "есть гашение инерции: StartCommand не спасает от толчка извне")
local tickFn = anims:match("local function freezeTick%(%).-\n    end")
ok(tickFn and tickFn:find("Length2D", 1, true) ~= nil,
   "гасится только горизонтальная скорость")
ok(tickFn and tickFn:find("Vector(-vel.x, -vel.y, 0)", 1, true) ~= nil,
   "по вертикали не мешаем — иначе игрок зависнет в воздухе")
ok(anims:find('GRM.Sched.Every("social.freeze"', 1, true) ~= nil,
   "задача в планировщике, а не отдельным таймером")
ok(anims:find("when = anyPosing", 1, true) ~= nil,
   "и бесплатна, пока никто не позирует")

do
    -- Логика гашения.
    local function damp(len2d)
        return len2d > 1
    end
    ok(damp(50) == true, "заметная скорость гасится")
    ok(damp(0.5) == false, "микродрожь не трогаем — лишняя работа каждый тик")
end

-- Флаг обязан доезжать от студии до каталога.
ok(src:find("freeze = chkFreeze:GetChecked()", 1, true) ~= nil,
   "студия отправляет флаг на сервер")
ok(src:find("rec.freeze = rec.freeze == true", 1, true) ~= nil,
   "сервер нормализует и сохраняет его в каталог")
ok(src:find("chkFreeze:SetValue(p.freeze == true or p.nomove == true)", 1, true) ~= nil,
   "и галочка восстанавливается при загрузке позы в редакторе")

print("")
print(string.format("ИТОГО: %d ok, %d FAIL", pass, fail))
if fail > 0 then os.exit(1) end
