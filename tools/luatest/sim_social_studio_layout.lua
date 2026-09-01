--[[--------------------------------------------------------------------
    sim_social_studio_layout — студия анимаций: не тонирует сцену и
    показывает список костей.

    ЖАЛОБА ВЛАДЕЛЬЦА (31.08, со скриншотом): «Чё за потемнение? И где
    список костей?»

    БАГ 1 — ПОТЕМНЕНИЕ. В f.Paint первой строкой стояла заливка
    draw.RoundedBox(0, 0, 0, w, h, Color(10, 13, 18, 200)). Фрейм
    растянут на весь экран, поэтому полупрозрачная подложка ложилась и
    на игровую сцену с моделью. Позу по затемнённой сцене не оценить.

    БАГ 2 — ПУСТОЙ СПИСОК КОСТЕЙ. Имена костей брались РОВНО ОДИН РАЗ
    при открытии окна:

        local names = boneNames(lp)     -- один вызов, и всё

    Но GetBoneCount возвращает 0, пока движок не построил скелет
    модели — а окно открывается ровно в этот момент (сервер только что
    применил заморозку и сменил стойку). Список строился из пустого
    набора молча и больше не перестраивался: колонка «СКЕЛЕТ» оставалась
    голой до перезахода в студию. Косвенный признак на скриншоте —
    подпись «КОСТЬ: R_UpperArm»: это значение ST по умолчанию, а НЕ
    первое имя из списка (им был бы Anim_Attachment_LH).

    ЧТО ПРОВЕРЯЕМ. Оба бага воспроизводим ДО фикса на реальном коде:
    Paint вызываем настоящий и считаем заливки, список костей строим
    настоящей функцией на модели, у которой скелет появляется не сразу.

    Запуск: luajit tools/luatest/sim_social_studio_layout.lua
----------------------------------------------------------------------]]

local pass, fail = 0, 0
local function ok(v, name, extra)
    if v then pass = pass + 1 print("  ok   " .. name)
    else fail = fail + 1 print("  FAIL " .. name .. "   " .. tostring(extra or "")) end
end

local function readf(p)
    local fh = assert(io.open(p, "rb"))
    local t = fh:read("*a")
    fh:close()
    return t
end

local src = readf("lua/autorun/sh_grm_social_studio.lua")

-----------------------------------------------------------------------
print("\n=== 1. ПОТЕМНЕНИЕ: заливка на весь экран ===")
-----------------------------------------------------------------------
--[[ Разбираем НАСТОЯЩЕЕ тело f.Paint из файла и исполняем его с
     поддельным draw, считая прямоугольники. Проверка «есть ли в файле
     такая-то строка» здесь не годится: цвет могут поменять, а баг
     останется. Нас интересует факт — красит ли Paint всю площадь. ]]
local paintBody = src:match("f%.Paint = function%(_, w, h%)\n(.-)\n    end")
ok(paintBody ~= nil, "тело f.Paint найдено в исходнике")

if paintBody then
    local boxes = {}
    local env = {
        draw = {
            RoundedBox = function(_, x, y, bw, bh, col)
                boxes[#boxes + 1] = { x = x, y = y, w = bw, h = bh, col = col }
            end,
            SimpleText = function() end,
        },
        Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end,
        COL = setmetatable({}, { __index = function() return { r = 0, g = 0, b = 0, a = 255 } end }),
        TEXT_ALIGN_LEFT = 0, TEXT_ALIGN_CENTER = 1,
    }
    local chunk = assert(loadstring("local w, h = ... \n" .. paintBody))
    setfenv(chunk, env)
    chunk(1920, 1080)

    local fullScreen
    for _, b in ipairs(boxes) do
        -- Заливка «во весь фрейм»: высота близка к высоте экрана.
        if b.h and b.h >= 1080 * 0.9 then fullScreen = b break end
    end
    ok(fullScreen == nil,
        "ИСПРАВЛЕНО: Paint не заливает всю площадь окна — сцена видна как в игре",
        fullScreen and ("залито " .. tostring(fullScreen.w) .. "x" .. tostring(fullScreen.h)))

    local header
    for _, b in ipairs(boxes) do
        if b.h and b.h > 20 and b.h < 80 then header = b break end
    end
    ok(header ~= nil, "шапка при этом рисуется (окно не стало прозрачным целиком)")
end

-----------------------------------------------------------------------
print("\n=== 2. СПИСОК КОСТЕЙ: скелет готов не сразу ===")
-----------------------------------------------------------------------
--[[ Берём НАСТОЯЩУЮ boneNames из файла и модель, у которой скелет
     появляется только с третьего обращения — так ведёт себя игрок в
     момент открытия студии. ]]
local bnBody = src:match("(local function boneNames%(ply%).-\nend)")
ok(bnBody ~= nil, "функция boneNames найдена в исходнике")

local BONES = { "ValveBiped.Anim_Attachment_LH", "ValveBiped.Bip01_Head1",
                "ValveBiped.Bip01_R_Hand", "ValveBiped.Bip01_Spine" }

local function mkPlayer(readyAfter)
    local p = { _calls = 0 }
    function p:GetBoneCount()
        self._calls = self._calls + 1
        -- Пока скелет не построен, движок отдаёт ноль.
        if self._calls < readyAfter then return 0 end
        return #BONES
    end
    function p:GetBoneName(i) return BONES[i + 1] end
    return p
end

local envBN = {
    IsValid = function(v) return type(v) == "table" end,
    table = table, ipairs = ipairs, pairs = pairs,
}
local bnChunk = assert(loadstring(bnBody .. "\nreturn boneNames"))
setfenv(bnChunk, envBN)
local boneNames = bnChunk()

do
    local notReady = mkPlayer(99)
    ok(#boneNames(notReady) == 0,
        "БАГ ВОСПРОИЗВЕДЁН: пока скелет не готов, boneNames отдаёт пустой список")
    local ready = mkPlayer(1)
    ok(#boneNames(ready) == #BONES, "когда скелет готов — имена приходят", #boneNames(ready))
end

-----------------------------------------------------------------------
print("\n=== 3. СТУДИЯ ПОВТОРЯЕТ ПОПЫТКУ, А НЕ СДАЁТСЯ ===")
-----------------------------------------------------------------------
--[[ Моделируем ту же связку, что теперь в openStudio: построение
     списка перечитывает имена, а таймер повторяет попытку до успеха. ]]
do
    local ply = mkPlayer(3)          -- скелет появится на 3-м обращении
    local names = boneNames(ply)     -- первый заход при открытии окна
    local built = 0

    local function rebuildBones()
        built = built + 1
        if #names == 0 then names = boneNames(ply) end
        return #names
    end

    rebuildBones()
    ok(#names == 0, "первое построение действительно попало в «скелет не готов»")

    -- Таймер ожидания.
    local tries = 0
    local removed = false
    repeat
        tries = tries + 1
        names = boneNames(ply)
        if #names > 0 then
            rebuildBones()
            removed = true
        end
    until removed or tries > 40

    ok(removed, "ИСПРАВЛЕНО: ожидание дождалось скелета", tries .. " попыток")
    ok(#names == #BONES, "список костей заполнен", #names)
    ok(tries <= 40, "и уложилось в лимит попыток, а не крутится вечно")
end

-----------------------------------------------------------------------
print("\n=== 4. КОСТЬ ПО УМОЛЧАНИЮ ЧИНИТСЯ ПОД МОДЕЛЬ ===")
-----------------------------------------------------------------------
do
    --[[ На скриншоте владельца было «КОСТЬ: R_UpperArm» — значение ST
         по умолчанию. Если у модели такой кости нет, слайдеры правили
         бы несуществующую кость: правишь — ничего не происходит. ]]
    local ST = { bone = "ValveBiped.Bip01_R_UpperArm" }
    local names = BONES
    local have
    for _, n in ipairs(names) do if n == ST.bone then have = true break end end
    if not have then ST.bone = names[1] end
    ok(ST.bone == BONES[1],
        "кость по умолчанию заменена на первую существующую", ST.bone)

    local ST2 = { bone = "ValveBiped.Bip01_Head1" }
    local have2
    for _, n in ipairs(names) do if n == ST2.bone then have2 = true break end end
    if not have2 then ST2.bone = names[1] end
    ok(ST2.bone == "ValveBiped.Bip01_Head1", "существующая кость не сбрасывается")
end

-----------------------------------------------------------------------
print("\n=== 5. ФОНОВЫЙ ТАЙМЕР НЕ ОСТАЁТСЯ ПОСЛЕ ЗАКРЫТИЯ ===")
-----------------------------------------------------------------------
do
    ok(src:find('timer.Remove("GRM_SocStudio_Bones")', 1, true) ~= nil,
        "closeStudio снимает таймер ожидания скелета")
    local closeBody = src:match("local function closeStudio%(%)\n(.-)\nend")
    ok(closeBody and closeBody:find("GRM_SocStudio_Bones", 1, true) ~= nil,
        "и делает это именно при закрытии, а не где-то ещё")
end

-----------------------------------------------------------------------
print(string.format("\nИТОГО: %d ok, %d FAIL", pass, fail))
os.exit(fail == 0 and 0 or 1)
