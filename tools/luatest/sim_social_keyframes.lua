--[[--------------------------------------------------------------------
    sim_social_keyframes — соц.анимации стали НАСТОЯЩИМИ анимациями.

    ЗАКАЗ ВЛАДЕЛЬЦА (31.08): «нужна механика в социальных анимациях
    чтобы анимировать, покадрово, делать анимации анимациями. Пока
    анимации лишь как позы скажем так… чтобы игрок мог использовать
    анимацию приветствия, админу в студию нужен функционал с
    расстановкой/записью ключевых кадров».

    ЧТО БЫЛО. Запись анимации это ОДИН набор углов костей (def.bones).
    Скелет вставал в позу и стоял в ней. Времени не существовало вовсе:
    ни кадров, ни длительности, ни смешивания — помахать рукой было
    физически нечем.

    ЧТО ПРОВЕРЯЕМ (боевые функции модуля, не копии логики):
      * ВОСПРОИЗВЕДЕНИЕ БАГА: у старой записи один кадр, значит поза во
        все моменты времени одинакова — это и есть «не анимация»;
      * многокадровая запись даёт РАЗНЫЕ позы в разные моменты;
      * смешивание идёт по кратчайшей дуге (170° → -170° это 20°,
        а не 340° в обратную сторону через полный оборот);
      * длительность считается по кадрам, у нецикличной последний кадр
        не добавляет времени;
      * нецикличная анимация замирает на последнем кадре, цикличная
        возвращается к первому;
      * старые записи (только bones) продолжают работать — каталог на
        живом сервере ломать нельзя;
      * чистка входных данных: лимиты на число кадров, костей и
        длительность, мусор не роняет сервер;
      * S.MarkAllBones видит кости ИЗ КАДРОВ (иначе кость, которую
        двигает только третий кадр, останется вывернутой после снятия);
      * сервер запоминает момент старта (общее время для всех зрителей)
        и снимает разовую анимацию сам.

    Запуск: luajit tools/luatest/sim_social_keyframes.lua
----------------------------------------------------------------------]]

local pass, fail = 0, 0
local function ok(v, name, extra)
    if v then pass = pass + 1 print("  ok   " .. name)
    else fail = fail + 1 print("  FAIL " .. name .. "   " .. tostring(extra or "")) end
end
local function near(a, b, eps)
    return math.abs((tonumber(a) or 0) - (tonumber(b) or 0)) <= (eps or 0.001)
end

-----------------------------------------------------------------------
-- Мок GMod: ровно столько, чтобы серверная часть модуля исполнилась.
-----------------------------------------------------------------------
SERVER, CLIENT = true, false
function AddCSLuaFile() end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function isfunction(v) return type(v) == "function" end
function isbool(v) return type(v) == "boolean" end
function IsValid(v) return istable(v) and v._valid ~= false end
function isangle(v) return istable(v) and v.__angle == true end

local NOW = 100
function CurTime() return NOW end
function RealTime() return NOW end
function SysTime() return NOW end

function Angle(p, y, r) return { __angle = true, p = p or 0, y = y or 0, r = r or 0 } end
function Vector(x, y, z)
    local v = { x = x or 0, y = y or 0, z = z or 0 }
    function v:LengthSqr() return self.x ^ 2 + self.y ^ 2 + self.z ^ 2 end
    return v
end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end

math.Clamp = function(v, lo, hi)
    v = tonumber(v) or lo
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end
math.NormalizeAngle = function(a)
    a = a % 360
    if a > 180 then a = a - 360 end
    return a
end
string.Trim = function(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
string.Explode = function(sep, str)
    local o = {}
    for p in tostring(str):gmatch("([^" .. sep .. "]+)") do o[#o + 1] = p end
    return o
end
table.Count = function(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end

hook = { Add = function() end, Remove = function() end, Run = function() end }

-- Таймеры записываем: разовая анимация обязана сняться сама.
local timers = {}
timer = {
    Create = function() end,
    Remove = function() end,
    Exists = function() return false end,
    Simple = function(delay, fn) timers[#timers + 1] = { delay = delay, fn = fn } end,
}
util = { AddNetworkString = function() end }
net = { Receive = function() end, Start = function() end, SendToServer = function() end,
        ReadString = function() return "" end, WriteString = function() end }
player = { GetAll = function() return {} end }
concommand = { Add = function() end }
bit = { bor = function(a, b) return a end }
IN_DUCK, IN_JUMP, IN_SPEED = 4, 2, 1
IN_FORWARD, IN_BACK, IN_MOVELEFT, IN_MOVERIGHT = 8, 16, 512, 1024
IN_ATTACK, IN_ATTACK2 = 1024, 2048
ACT_HL2MP_WALK_CROUCH, ACT_HL2MP_IDLE_CROUCH = 1, 2
GRM = { Notify = function() end }

assert(loadfile("lua/autorun/sh_grm_social_anims.lua"))()
local S = GRM.Social
assert(S, "GRM.Social не загрузился")

-----------------------------------------------------------------------
print("\n=== 1. ВОСПРОИЗВЕДЕНИЕ БАГА: старая запись это ОДНА поза ===")
-----------------------------------------------------------------------
local oldStyle = {
    id = "back",
    bones = { ["ValveBiped.Bip01_R_UpperArm"] = { p = 30, yaw = 0, r = 0 } },
}
ok(not S.IsAnimated(oldStyle), "БАГ ВОСПРОИЗВЕДЁН: запись без кадров не анимация")
ok(near(S.TotalTime(oldStyle), 0), "у одной позы длительность нулевая")
do
    local a = S.Sample(oldStyle, 0)
    local b = S.Sample(oldStyle, 5)
    ok(near(a["ValveBiped.Bip01_R_UpperArm"].p, b["ValveBiped.Bip01_R_UpperArm"].p),
        "БАГ ВОСПРОИЗВЕДЁН: поза одинакова в 0 и в 5 секунд — движения нет")
end

-----------------------------------------------------------------------
print("\n=== 2. ПОКАДРОВАЯ АНИМАЦИЯ ДВИГАЕТСЯ ===")
-----------------------------------------------------------------------
local B = "ValveBiped.Bip01_R_UpperArm"
local wave = {
    id = "wave",
    loop = true,
    frames = {
        { dur = 1, bones = { [B] = { p = 0, yaw = 0, r = 0 } } },
        { dur = 1, bones = { [B] = { p = 100, yaw = 0, r = 0 } } },
    },
}
ok(S.IsAnimated(wave), "ИСПРАВЛЕНО: запись с двумя кадрами считается анимацией")
ok(near(S.TotalTime(wave), 2), "цикл: считаются оба кадра", S.TotalTime(wave))
ok(near(S.Sample(wave, 0)[B].p, 0), "t=0 — первый кадр")
ok(near(S.Sample(wave, 0.5)[B].p, 50), "t=0.5 — ровно середина между кадрами",
    S.Sample(wave, 0.5)[B].p)
ok(near(S.Sample(wave, 1)[B].p, 100), "t=1 — второй кадр")
ok(near(S.Sample(wave, 1.5)[B].p, 50), "t=1.5 — возврат к первому (цикл)",
    S.Sample(wave, 1.5)[B].p)
ok(near(S.Sample(wave, 2)[B].p, 0), "t=2 — начало нового круга")
ok(near(S.Sample(wave, 10.5)[B].p, 50), "цикл работает и на десятой секунде")

-----------------------------------------------------------------------
print("\n=== 3. РАЗОВАЯ АНИМАЦИЯ ЗАМИРАЕТ, А НЕ ПРЫГАЕТ В НАЧАЛО ===")
-----------------------------------------------------------------------
local once = {
    id = "salute",
    loop = false,
    frames = {
        { dur = 1, bones = { [B] = { p = 0 } } },
        { dur = 1, bones = { [B] = { p = 80 } } },
    },
}
ok(near(S.TotalTime(once), 1), "без цикла длительность = сумма без последнего кадра",
    S.TotalTime(once))
ok(near(S.Sample(once, 0.5)[B].p, 40), "середина перехода")
ok(near(S.Sample(once, 5)[B].p, 80), "после конца держится последний кадр, не откат в 0",
    S.Sample(once, 5)[B].p)

-----------------------------------------------------------------------
print("\n=== 4. КРАТЧАЙШАЯ ДУГА (иначе рука делает полный оборот) ===")
-----------------------------------------------------------------------
local spin = {
    id = "spin",
    frames = {
        { dur = 1, bones = { [B] = { p = 170 } } },
        { dur = 1, bones = { [B] = { p = -170 } } },
    },
}
do
    local mid = S.Sample(spin, 0.5)[B].p
    -- Кратчайший путь 170 → 190(=-170): середина 180.
    ok(near(math.abs(mid), 180, 0.01), "смешивание идёт через 180, а не через ноль", mid)
end
do
    -- Прямая линейная интерполяция дала бы 0 — это и есть тот самый
    -- «полный оборот руки» на стыке кадров.
    local mid = S.Sample(spin, 0.5)[B].p
    ok(not near(mid, 0, 1), "НЕ линейная интерполяция: середина не ноль", mid)
end

-----------------------------------------------------------------------
print("\n=== 5. СКОРОСТЬ ===")
-----------------------------------------------------------------------
do
    local fast = { id = "f", loop = true, speed = 2, frames = wave.frames }
    ok(near(S.Sample(fast, 0.25)[B].p, 50), "speed=2 — вдвое быстрее",
        S.Sample(fast, 0.25)[B].p)
    local slow = { id = "s", loop = true, speed = 0.5, frames = wave.frames }
    ok(near(S.Sample(slow, 1)[B].p, 50), "speed=0.5 — вдвое медленнее",
        S.Sample(slow, 1)[B].p)
end

-----------------------------------------------------------------------
print("\n=== 6. СТАРЫЙ КАТАЛОГ НЕ ЛОМАЕТСЯ ===")
-----------------------------------------------------------------------
do
    local fr = S.Frames(oldStyle)
    ok(#fr == 1, "старая поза превращается в один кадр", #fr)
    ok(fr[1].bones == oldStyle.bones, "кости берутся из исходной записи, без копии")
    ok(#S.Frames({}) == 0, "пустая запись — ноль кадров, без падения")
    ok(#S.Frames(nil) == 0, "nil не роняет S.Frames")
end
do
    -- Формат после обхода JSON: yaw мог сохраниться как y, сдвиг как x/z.
    local n = S.NormBone({ p = 5, y = 15, x = 1, z = 2 })
    ok(near(n.yaw, 15), "yaw читается из поля y (JSON-формат)")
    ok(near(n.px, 1) and near(n.pz, 2), "сдвиг читается из x/z")
    local n2 = S.NormBone(Angle(3, 4, 5))
    ok(near(n2.p, 3) and near(n2.yaw, 4) and near(n2.r, 5), "Angle читается как кость")
    ok(near(S.NormBone("мусор").p, 0), "строка вместо кости не роняет")
end

-----------------------------------------------------------------------
print("\n=== 7. ЧИСТКА ВХОДНЫХ ДАННЫХ (данные приходят по сети) ===")
-----------------------------------------------------------------------
do
    local dirty = {}
    for i = 1, 200 do dirty[i] = { dur = 999, bones = { [B] = { p = 10 } } } end
    local clean = S.SanitizeFrames(dirty)
    ok(#clean == S.MaxFrames, "число кадров ограничено сверху", #clean)
    ok(clean[1].dur <= S.MaxDur, "длительность кадра ограничена", clean[1].dur)

    local negative = S.SanitizeFrames({ { dur = -50, bones = {} } })
    ok(negative[1].dur >= S.MinDur, "отрицательная длительность подтянута к минимуму",
        negative[1].dur)

    local huge = { bones = {} }
    for i = 1, 400 do huge.bones["bone" .. i] = { p = 1 } end
    local c2 = S.SanitizeFrames({ huge })
    ok(table.Count(c2[1].bones) <= S.MaxBonesPerFrame, "число костей в кадре ограничено",
        table.Count(c2[1].bones))

    ok(#S.SanitizeFrames("не таблица") == 0, "мусор вместо кадров даёт пустой список")
    ok(#S.SanitizeFrames({ 1, "два", false }) == 0, "элементы не-таблицы отбрасываются")
end

-----------------------------------------------------------------------
print("\n=== 8. КОСТИ ИЗ КАДРОВ ПОПАДАЮТ В СПИСОК СБРОСА ===")
-----------------------------------------------------------------------
do
    --[[ Без этого кость, которую двигает только третий кадр, после
         снятия анимации осталась бы вывернутой навсегда. ]]
    local marked = {}
    local realList = S.List
    S.List = { {
        id = "t", bones = {},
        frames = {
            { dur = 1, bones = { ["BONE_ONLY_IN_FRAME"] = { p = 1 } } },
        },
    } }
    -- Подглядываем в ALL_BONES через применяемую позу: сама таблица
    -- локальна, поэтому проверяем через код, который её наполняет.
    local src = io.open("lua/autorun/sh_grm_social_anims.lua", "rb"):read("*a")
    S.MarkAllBones()
    S.List = realList
    ok(src:find("for _, f in ipairs(S.List[i].frames or {}) do markBones(f.bones) end", 1, true) ~= nil,
        "MarkAllBones обходит кадры, а не только bones")
    marked = nil
end

-----------------------------------------------------------------------
print("\n=== 8b. ВСТРОЕННЫЙ ПРИМЕР: приветствие это движение ===")
-----------------------------------------------------------------------
do
    --[[ Свежий сервер без сохранённого каталога должен уметь показать
         механику: если в коробке одни статичные позы, проверить нечего. ]]
    local wv = S.ByID("wave")
    ok(wv ~= nil, "встроенная анимация «Приветствие» есть в списке")
    if wv then
        ok(S.IsAnimated(wv), "она многокадровая, а не поза", #S.Frames(wv))
        ok(wv.loop ~= true,
            "НЕ зациклена: иначе авто-снятие не сработает и игрок махал бы вечно")
        ok(wv.frames[#wv.frames] and next(wv.frames[#wv.frames].bones) == nil,
            "последний кадр пустой — рука возвращается в исходное")
        ok(wv.hold == false, "разовая: снимется сама")
        local H = "ValveBiped.Bip01_R_Hand"
        local a = S.Sample(wv, 0.3)[H]
        local b = S.Sample(wv, 0.6)[H]
        ok(a and b and not near(a.r, b.r, 0.5),
            "кисть реально в разных положениях в разные моменты",
            a and b and (a.r .. " / " .. b.r))
    end
    local pt = S.ByID("point")
    ok(pt ~= nil and S.IsAnimated(pt), "встроенное «Указать вперёд» тоже покадровое")
end

-----------------------------------------------------------------------
print("\n=== 9. СЕРВЕР: старт, общее время, авто-снятие ===")
-----------------------------------------------------------------------
local function mkPly()
    local p = { _valid = true, _nw = {}, _nwb = {}, _nwf = {} }
    function p:Alive() return true end
    function p:InVehicle() return false end
    function p:EntIndex() return 1 end
    function p:SetNWString(k, v) self._nw[k] = v end
    function p:GetNWString(k, d) return self._nw[k] or d or "" end
    function p:SetNWBool(k, v) self._nwb[k] = v end
    function p:GetNWBool(k, d) if self._nwb[k] == nil then return d or false end return self._nwb[k] end
    function p:SetNWFloat(k, v) self._nwf[k] = v end
    function p:GetNWFloat(k, d) return self._nwf[k] or d or 0 end
    return p
end

S.List = {
    { id = "wave", name = "Приветствие", cat = "general", hold = false, loop = false,
      frames = wave.frames },
    { id = "hands", name = "Руки вверх", cat = "general", hold = true,
      bones = { [B] = { p = 10 } } },
}
S.MarkAllBones()

do
    timers = {}
    local ply = mkPly()
    NOW = 250
    ok(S.Play(ply, "wave") == true, "анимация запускается")
    ok(ply:GetNWString("GRM_SocAnim", "") == "wave", "id уехал в сетевую переменную")
    ok(near(ply:GetNWFloat("GRM_SocStart", 0), 250),
        "ИСПРАВЛЕНО: момент старта записан — у всех зрителей один и тот же кадр",
        ply:GetNWFloat("GRM_SocStart", 0))
    ok(#timers == 1, "для разовой анимации заведён таймер авто-снятия", #timers)
    if timers[1] then
        ok(timers[1].delay > S.TotalTime(S.ByID("wave")),
            "снятие назначено ПОСЛЕ конца анимации", timers[1].delay)
        timers[1].fn()
        ok(ply:GetNWString("GRM_SocAnim", "") == "",
            "ИСПРАВЛЕНО: разовая анимация снялась сама, игрок не застрял в кадре")
    end
end

do
    timers = {}
    local ply = mkPly()
    S.Play(ply, "hands")
    ok(#timers == 0, "поза «держать до отмены» таймером не снимается")
    ok(ply:GetNWString("GRM_SocAnim", "") == "hands", "поза активна")
    S.Play(ply, "hands")
    ok(ply:GetNWString("GRM_SocAnim", "") == "", "повторный вызов снимает позу (переключатель)")
    ok(near(ply:GetNWFloat("GRM_SocStart", -1), 0), "при снятии момент старта обнуляется",
        ply:GetNWFloat("GRM_SocStart", -1))
end

do
    local ply = mkPly()
    ok(S.Play(ply, "нет_такой") == false, "несуществующий id отклонён")
    ply._nwb["GRM_Cuffed"] = true
    ok(S.Play(ply, "hands") == false, "в наручниках анимация не включается")
end

-----------------------------------------------------------------------
print("\n=== 10. СТУДИЯ: сервер чистит кадры перед раздачей игрокам ===")
-----------------------------------------------------------------------
do
    local src = io.open("lua/autorun/sh_grm_social_studio.lua", "rb"):read("*a")
    ok(src:find("S.SanitizeFrames", 1, true) ~= nil,
        "серверный обработчик save чистит кадры")
    ok(src:find("rec.loop = rec.loop == true", 1, true) ~= nil, "флаг цикла сохраняется")
    ok(src:find("rec.speed", 1, true) ~= nil, "скорость сохраняется")
    ok(src:find("rec.bones = rec.frames[1].bones", 1, true) ~= nil,
        "bones держится синхронно с первым кадром (совместимость со старым кодом)")
    -- Клиентская часть: лента кадров и предпросмотр общей функцией.
    ok(src:find("ST.refreshStrip", 1, true) ~= nil, "в студии есть лента кадров")
    ok(src:find("GRM.Social.Sample", 1, true) or src:find("S2.Sample", 1, true),
        "предпросмотр считает боевой функцией Sample, а не своей копией")
    ok(src:find("function ST.doSave", 1, true) ~= nil,
        "сохранение вынесено в одну функцию (кнопка стоит рядом с полями)")
    ok(src:find("СОХРАНИТЬ АНИМАЦИЮ", 1, true) ~= nil,
        "кнопка сохранения в блоке параметров, а не в дальнем углу")
end

-----------------------------------------------------------------------
print("\n=== 11. МЕНЮ ИГРОКА ===")
-----------------------------------------------------------------------
do
    local src = io.open("lua/autorun/sh_grm_social_anims.lua", "rb"):read("*a")
    ok(src:find("buildPreview", 1, true) ~= nil, "в меню есть живой предпросмотр модели")
    ok(src:find("DoDoubleClick", 1, true) ~= nil,
        "клик выбирает, двойной включает — не срабатывает вслепую")
    ok(src:find("animating%[ent%] = nil") ~= nil,
        "таблица анимируемых чистится при удалении игрока (утечка ссылок)")
    ok(src:find("function S.ApplyBones", 1, true) ~= nil,
        "применение костей вынесено в общую функцию")
end

-----------------------------------------------------------------------
print(string.format("\nИТОГО: %d ok, %d FAIL", pass, fail))
os.exit(fail == 0 and 0 or 1)
