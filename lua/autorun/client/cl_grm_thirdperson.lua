--[[--------------------------------------------------------------------
    GRM Third Person — свой вид от третьего лица.

    ЗАКАЗ ВЛАДЕЛЬЦА (31.08): «надо бы сделать модуль вида от 3-го лица,
    свой, а не чтобы клавиша в C меню зависела от стороннего аддона, да
    и тем более с настройками в F4 чтобы можно было угол обзора, камеру
    изменять и т.д.»

    ЧТО БЫЛО. Кнопка «3-е лицо» в C-меню звала консольную команду
    simple_thirdperson_enable_toggle — команду ЧУЖОГО аддона. Нет
    аддона на сервере или его переименовали в новой версии — кнопка
    молча не работает. Настроить угол, дальность и плечо было нельзя.

    ЧТО ЗДЕСЬ. Свой CalcView: камера отводится от глаз игрока назад,
    вбок и вверх на заданные величины. Трассировка не даёт камере
    провалиться в стену. Всё настраивается конварами и живёт в
    F4 → Настройки.

    ПОЧЕМУ НЕ ПРОСТО ShouldDrawLocalPlayer. Одного показа модели мало:
    камера остаётся в голове, и игрок смотрит «изнутри себя». Нужен
    именно перенос точки обзора, а прицел при этом обязан оставаться
    честным — куда смотрит игрок, туда и стреляет, поэтому углы камеры
    не трогаем.
----------------------------------------------------------------------]]
if not CLIENT then return end

GRM = GRM or {}
GRM.ThirdPerson = GRM.ThirdPerson or {}
local TP = GRM.ThirdPerson
TP.Version = "1.0.0"

-- Значения по умолчанию подобраны под обычный рост персонажа.
CreateClientConVar("grm_tp_enabled", "0", true, false, "Вид от третьего лица")
CreateClientConVar("grm_tp_dist", "70", true, false, "Отдаление камеры")
CreateClientConVar("grm_tp_right", "22", true, false, "Смещение камеры вбок (плечо)")
CreateClientConVar("grm_tp_up", "4", true, false, "Смещение камеры вверх")
CreateClientConVar("grm_tp_fov", "0", true, false, "Угол обзора (0 = как в игре)")
CreateClientConVar("grm_tp_smooth", "1", true, false, "Плавное движение камеры")
CreateClientConVar("grm_tp_incar", "0", true, false, "Работает в транспорте")
CreateClientConVar("grm_tp_incombat", "1", true, false, "Работает с оружием в руках")

TP.Limits = {
    dist  = { 30, 220 },
    right = { -80, 80 },
    up    = { -30, 40 },
    fov   = { 0, 120 },
}

local function cv(name, def)
    local v = GetConVarNumber(name)
    if v == nil then return def end
    return v
end

local function clampCv(name, def, key)
    local lim = TP.Limits[key]
    local v = cv(name, def)
    if not lim then return v end
    return math.Clamp(v, lim[1], lim[2])
end

--[[ Разрешён ли вид прямо сейчас.

     Отдельной функцией: её же зовёт кнопка C-меню, чтобы не включать
     режим там, где он тут же выключится, и стенд проверяет правила без
     запуска игры. ]]
function TP.Allowed(ply)
    if not IsValid(ply) then return false end
    if not ply:Alive() then return false end
    --[[ В транспорте по умолчанию не лезем: у машин своя камера, и две
         одновременно дают дёрганый вид. Кому надо — включает. ]]
    if ply:InVehicle() and cv("grm_tp_incar", 0) == 0 then return false end
    --[[ Прицеливание. От третьего лица прицел уходит в сторону от
         перекрестья, поэтому по умолчанию вид с оружием разрешён, но
         при ПРИЦЕЛИВАНИИ через мушку всё равно возвращаемся в первое
         лицо — иначе стрелять невозможно. ]]
    if cv("grm_tp_incombat", 1) == 0 then
        local wep = ply:GetActiveWeapon()
        if IsValid(wep) and wep:GetClass() ~= "weapon_physgun"
            and wep:GetClass() ~= "gmod_camera" then
            return false
        end
    end
    --[[ ЧУЖИЕ КАМЕРЫ ВАЖНЕЕ.

         В сборке восемь других обработчиков CalcView: кат-сцена
         квеста, камеры наблюдения, редактор аксессуаров, студия
         анимаций, кровать, ранение (ползком), вход на сервер. Хуки
         зовутся по имени, и наш «GRM_ThirdPerson» встаёт в этом
         списке раньше части из них — вернув свою камеру, мы бы просто
         перебили чужую и сломали, например, кат-сцену.

         Поэтому уступаем сами, явной проверкой каждого режима. ]]
    if GRM.Quests and GRM.Quests.Cutscene and GRM.Quests.Cutscene.active then return false end
    if GRM.Customization and GRM.Customization.EditorActive then return false end
    -- Студия соц.анимаций: сервер поднимает этот флаг на время работы.
    if ply:GetNWBool("GRM_SocStudio") then return false end
    -- Ранение и ползком: там своя камера у тела.
    if ply:GetNWBool("GRM_911_Downed") then return false end
    if ply:GetNWBool("GRM_Prone") then return false end
    -- Кровать: энтити спящего висит прямо на игроке.
    if IsValid(ply.GRMBedEnt) then return false end
    return true
end

--[[ ВКЛЮЧЁН ли режим (галочка игрока) — отдельно от того, ПРИМЕНЯЕТСЯ
     ли он прямо сейчас.

     Разница важна для подписи кнопки в C-меню: сидя в машине вид
     временно не работает, но режим у игрока включён, и писать «Вкл
     3-е лицо» было бы враньём — он его уже включил. ]]
function TP.IsEnabled()
    return cv("grm_tp_enabled", 0) ~= 0
end

-- Работает ли вид в данный момент (с учётом транспорта, смерти и пр.).
function TP.IsOn()
    return TP.IsEnabled() and TP.Allowed(LocalPlayer())
end

function TP.Toggle()
    local on = cv("grm_tp_enabled", 0) ~= 0
    RunConsoleCommand("grm_tp_enabled", on and "0" or "1")
    return not on
end

--[[ Положение камеры.

     Считается чистой функцией, без обращения к игре: стенд гоняет её
     напрямую. origin — глаза игрока, ang — куда он смотрит.

     Порядок слагаемых важен: сначала отходим НАЗАД вдоль взгляда,
     потом вбок и вверх. Если сместить вбок раньше, камера будет
     заворачивать по дуге при повороте головы. ]]
function TP.CameraPos(origin, ang, dist, right, up)
    return origin
        - ang:Forward() * dist
        + ang:Right() * right
        + ang:Up() * up
end

local smoothPos

-- холл трассировки камеры: константы загрузки (§6.1.8)
local TP_HULL_MIN, TP_HULL_MAX = Vector(-6, -6, -6), Vector(6, 6, 6)
hook.Add("CalcView", "GRM_ThirdPerson", function(ply, origin, ang, fov)
    if not TP.IsOn() then
        smoothPos = nil
        return
    end

    local dist  = clampCv("grm_tp_dist", 70, "dist")
    local right = clampCv("grm_tp_right", 22, "right")
    local up    = clampCv("grm_tp_up", 4, "up")

    local want = TP.CameraPos(origin, ang, dist, right, up)

    --[[ Не даём камере уехать в стену. Трассируем ХАЛЛОМ, а не лучом:
         тонкий луч проходит в щель между досками, и камера оказывается
         внутри геометрии, показывая чёрный экран. ]]
    local tr = util.TraceHull({
        start = origin,
        endpos = want,
        filter = ply,
        mins = TP_HULL_MIN,
        maxs = TP_HULL_MAX,
        mask = MASK_SOLID_BRUSHONLY,
    })
    local pos = tr.HitPos
    if tr.Hit then
        -- Отступаем от поверхности, иначе камера «липнет» к стене.
        pos = pos + tr.HitNormal * 4
    end

    --[[ Сглаживание. Без него камера дёргается на каждом уступе:
         трассировка то упирается в косяк, то нет. Приближаемся к
         цели долей за кадр — резкие скачки размазываются, а обычное
         движение остаётся отзывчивым. ]]
    if cv("grm_tp_smooth", 1) ~= 0 and smoothPos then
        smoothPos = LerpVector(math.Clamp(FrameTime() * 14, 0, 1), smoothPos, pos)
    else
        smoothPos = pos
    end

    local view = {
        origin = smoothPos,
        -- Углы НЕ трогаем: прицел должен совпадать с направлением взгляда.
        angles = ang,
        drawviewer = true,
    }
    local customFov = clampCv("grm_tp_fov", 0, "fov")
    if customFov > 0 then view.fov = customFov end
    return view
end)

-- Модель себя видно только когда вид включён.
hook.Add("ShouldDrawLocalPlayer", "GRM_ThirdPerson_Draw", function()
    if TP.IsOn() then return true end
end)

--[[ Модель оружия из рук в третьем лице не рисуем: камера позади
     игрока, и «руки с автоматом» висели бы в воздухе перед объективом.
     Мировая модель в руках персонажа при этом остаётся на месте. ]]
hook.Add("PreDrawViewModel", "GRM_ThirdPerson_HideVM", function()
    if TP.IsOn() then return true end
end)

concommand.Add("grm_thirdperson", function() TP.Toggle() end)
concommand.Add("grm_tp", function() TP.Toggle() end)

print("[GRM ThirdPerson] loaded v" .. TP.Version)
