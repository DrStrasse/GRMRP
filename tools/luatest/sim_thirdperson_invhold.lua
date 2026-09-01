--[[--------------------------------------------------------------------
    sim_thirdperson_invhold — свой вид от третьего лица и починка
    удержания клавиши инвентаря.

    ЖАЛОБА ВЛАДЕЛЬЦА (31.08): «Клавиша удержания не срабатывает на
    инвентарь, наверное потому ещё, что инвентарь же прописан в быстром
    доступе в C меню и у него свой режим открытия + надо бы сделать
    модуль вида от 3-го лица, свой, а не чтобы клавиша в C меню
    зависела от стороннего аддона, да и тем более с настройками в F4».

    ПРИЧИНЫ, НАЙДЕННЫЕ В КОДЕ.

    1) УДЕРЖАНИЕ НЕ РАБОТАЛО. MakePopup() включает окну и мышь, И
       КЛАВИАТУРУ. Пока фокус клавиатуры у панели, движок отдаёт
       нажатия ей, а не в игру — хук PlayerButtonUp вообще не
       вызывается, и отпускание клавиши остаётся незамеченным.
       Радиальное меню соц.анимаций работает именно потому, что
       снимает у себя клавиатуру: SetKeyboardInputEnabled(false).
       У инвентаря этой строки не было.

    2) ДОГАДКА ВЛАДЕЛЬЦА ПРО C-МЕНЮ ТОЖЕ ВЕРНА. Кнопка «Инвентарь»
       зовёт concommand grm_inventory, а он только ОТКРЫВАЛ. Окно,
       открытое из C-меню, клавишей не закрывалось как надо.

    3) ТРЕТЬЕ ЛИЦО ЗАВИСЕЛО ОТ ЧУЖОГО АДДОНА: кнопка звала
       simple_thirdperson_enable_toggle. Нет аддона — кнопка молча
       ничего не делает, а подпись в меню при этом переключалась.

    Запуск: luajit tools/luatest/sim_thirdperson_invhold.lua
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
    local t = fh:read("*a") fh:close() return t
end

-----------------------------------------------------------------------
-- Мок GMod.
-----------------------------------------------------------------------
CLIENT, SERVER = true, false
function AddCSLuaFile() end
function istable(v) return type(v) == "table" end
function isfunction(v) return type(v) == "function" end
function isnumber(v) return type(v) == "number" end
function isstring(v) return type(v) == "string" end
function IsValid(v) return istable(v) and v._valid ~= false end
function FrameTime() return 0.016 end
function RealTime() return 100 end
function CurTime() return 100 end

local VM = {}
VM.__index = VM
function VM:Length() return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end
function VM:Distance(o) return (self - o):Length() end
VM.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
VM.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
VM.__mul = function(a, b) return Vector(a.x * b, a.y * b, a.z * b) end
VM.__eq = function(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VM) end

--[[ Углы: базис для yaw. Forward — куда смотрим, Right — вправо от
     взгляда, Up — вверх. Этого хватает для проверки геометрии. ]]
function Angle(p, y, r)
    local a = { p = p or 0, y = y or 0, r = r or 0 }
    local rad = math.rad(a.y)
    local c, s = math.cos(rad), math.sin(rad)
    function a:Forward() return Vector(c, s, 0) end
    function a:Right() return Vector(s, -c, 0) end
    function a:Up() return Vector(0, 0, 1) end
    return a
end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
math.Clamp = function(v, lo, hi)
    v = tonumber(v) or lo
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end
function LerpVector(t, a, b)
    return Vector(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t)
end

local HOOKS = {}
hook = {
    Add = function(e, n, f) HOOKS[e] = HOOKS[e] or {} HOOKS[e][n] = f end,
    Remove = function(e, n) if HOOKS[e] then HOOKS[e][n] = nil end end,
    Run = function() end, Call = function() end,
}
local function callHook(e, ...)
    for _, f in pairs(HOOKS[e] or {}) do
        local r = f(...)
        if r ~= nil then return r end
    end
end

local CVARS = {}
function CreateClientConVar(n, d) CVARS[n] = tostring(d) end
function GetConVarNumber(n) return tonumber(CVARS[n]) end
function GetConVar(n) return { GetInt = function() return math.floor(tonumber(CVARS[n]) or 0) end } end
function RunConsoleCommand(n, v) CVARS[n] = tostring(v) end
concommand = { Add = function() end }
util = {
    TraceHull = function(t)
        -- По умолчанию свободно: препятствие задаём в конкретном тесте.
        if _G.__BLOCK then
            return { Hit = true, HitPos = _G.__BLOCK, HitNormal = Vector(1, 0, 0) }
        end
        return { Hit = false, HitPos = t.endpos, HitNormal = Vector(0, 0, 0) }
    end,
}
MASK_SOLID_BRUSHONLY = 1
GRM = {}

local ply = { _valid = true, _nwb = {}, _alive = true, _veh = false }
function ply:Alive() return self._alive end
function ply:InVehicle() return self._veh end
function ply:GetNWBool(k, d) if self._nwb[k] == nil then return d or false end return self._nwb[k] end
function ply:GetActiveWeapon() return self._wep or { _valid = false } end
function LocalPlayer() return ply end

assert(loadfile("lua/autorun/client/cl_grm_thirdperson.lua"))()
local TP = GRM.ThirdPerson
assert(TP, "модуль третьего лица не загрузился")

-----------------------------------------------------------------------
print("\n=== 1. МОДУЛЬ СВОЙ, БЕЗ ЧУЖОГО АДДОНА ===")
-----------------------------------------------------------------------
do
    local ctx = readf("lua/autorun/sh_grm_ctx.lua")
    --[[ Ищем ВЫЗОВ, а не упоминание: рядом в комментарии объясняется,
         что здесь раньше звалась чужая команда, и поиск по подстроке
         ловил бы этот текст. ]]
    ok(ctx:find('RunConsoleCommand%("simple_thirdperson') == nil,
        "ИСПРАВЛЕНО: вызов чужого аддона убран из C-меню")
    ok(ctx:find("GRM.ThirdPerson.Toggle", 1, true) ~= nil,
        "кнопка зовёт свой модуль")

    --[[ Подпись кнопки раньше читала локальный флаг: он переключался
         даже когда чужой команды не существовало, и меню показывало
         «Выкл», хотя вид не менялся. ]]
    ok(ctx:find("l = function() return (tpOn() and", 1, true) ~= nil,
        "подпись читает реальное состояние модуля, а не свою копию")
    local act = ctx:match("local function actTp%(%).-\nend")
    ok(act and act:find("GRM.Notify", 1, true) ~= nil,
        "если модуля нет — честно сообщаем, а не притворяемся")
end

-----------------------------------------------------------------------
print("\n=== 2. ГЕОМЕТРИЯ КАМЕРЫ ===")
-----------------------------------------------------------------------
do
    local origin = Vector(0, 0, 64)
    local ang = Angle(0, 0, 0)      -- смотрим вдоль +X

    local p = TP.CameraPos(origin, ang, 70, 0, 0)
    ok(near(p.x, -70) and near(p.z, 64),
        "камера отходит НАЗАД вдоль взгляда", p.x .. "," .. p.z)

    -- Плечо: смещение вбок перпендикулярно взгляду.
    local pr = TP.CameraPos(origin, ang, 70, 22, 0)
    ok(near(pr.x, -70), "плечо не меняет отдаление")
    ok(not near(pr.y, 0), "плечо реально сдвигает камеру вбок", pr.y)

    -- Высота.
    local pu = TP.CameraPos(origin, ang, 70, 0, 10)
    ok(near(pu.z, 74), "смещение вверх поднимает камеру", pu.z)

    -- Поворот игрока разворачивает и камеру.
    local turned = TP.CameraPos(origin, Angle(0, 90, 0), 70, 0, 0)
    ok(near(turned.y, -70, 0.01), "при повороте на 90° камера уходит за спину",
        turned.x .. "," .. turned.y)

    -- Больше дистанция — дальше камера.
    local far = TP.CameraPos(origin, ang, 150, 0, 0)
    ok(far:Distance(origin) > p:Distance(origin), "дистанция управляет отдалением")
end

-----------------------------------------------------------------------
print("\n=== 3. КОГДА ВИД ВЫКЛЮЧАЕТСЯ САМ ===")
-----------------------------------------------------------------------
do
    CVARS["grm_tp_enabled"] = "1"
    CVARS["grm_tp_incar"] = "0"
    CVARS["grm_tp_incombat"] = "1"

    ok(TP.IsEnabled(), "режим включён игроком")
    ok(TP.IsOn(), "и применяется")

    ply._veh = true
    ok(not TP.IsOn(), "в транспорте не применяется (у машины своя камера)")
    ok(TP.IsEnabled(), "но остаётся включённым — подпись в меню не соврёт")
    CVARS["grm_tp_incar"] = "1"
    ok(TP.IsOn(), "с разрешением работает и в транспорте")
    ply._veh = false
    CVARS["grm_tp_incar"] = "0"

    ply._alive = false
    ok(not TP.IsOn(), "мёртвым вид не навязываем")
    ply._alive = true

    --[[ Уступаем чужим камерам: иначе перебьём кат-сцену или студию.
         Проверяем каждый режим по его НАСТОЯЩЕМУ признаку. ]]
    ply._nwb["GRM_911_Downed"] = true
    ok(not TP.IsOn(), "при ранении уступаем камере тела")
    ply._nwb["GRM_911_Downed"] = false

    ply._nwb["GRM_Prone"] = true
    ok(not TP.IsOn(), "лёжа уступаем")
    ply._nwb["GRM_Prone"] = false

    ply._nwb["GRM_SocStudio"] = true
    ok(not TP.IsOn(), "в студии анимаций уступаем её камере")
    ply._nwb["GRM_SocStudio"] = false

    ply.GRMBedEnt = { _valid = true }
    ok(not TP.IsOn(), "в кровати уступаем")
    ply.GRMBedEnt = nil

    GRM.Quests = { Cutscene = { active = true } }
    ok(not TP.IsOn(), "в кат-сцене уступаем")
    GRM.Quests = nil

    GRM.Customization = { EditorActive = true }
    ok(not TP.IsOn(), "в редакторе аксессуаров уступаем")
    GRM.Customization = nil

    ok(TP.IsOn(), "после всех помех вид снова работает")
end

-----------------------------------------------------------------------
print("\n=== 4. ПЕРЕКЛЮЧЕНИЕ И ГРАНИЦЫ НАСТРОЕК ===")
-----------------------------------------------------------------------
do
    CVARS["grm_tp_enabled"] = "0"
    ok(TP.Toggle() == true, "Toggle включает")
    ok(CVARS["grm_tp_enabled"] == "1", "и пишет конвар")
    ok(TP.Toggle() == false, "Toggle выключает")
    ok(CVARS["grm_tp_enabled"] == "0", "конвар вернулся")
    CVARS["grm_tp_enabled"] = "1"
end

do
    --[[ Значения приходят из конваров, а их игрок может выставить
         консолью какими угодно. Без ограничения камера уехала бы за
         карту или внутрь головы. ]]
    ok(TP.Limits.dist[1] > 0, "минимальное отдаление больше нуля")
    ok(TP.Limits.dist[2] <= 400, "максимум разумный", TP.Limits.dist[2])
    ok(TP.Limits.fov[1] == 0, "нулевой FOV разрешён — значит «как в игре»")

    CVARS["grm_tp_dist"] = "99999"
    --[[ Плечо и высоту обнуляем: лимит ограничивает именно ОТДАЛЕНИЕ
         назад, а боковое смещение добавляет к общему расстоянию своё.
         Без этого проверка мерила бы сумму и ложно краснела. ]]
    CVARS["grm_tp_right"] = "0"
    CVARS["grm_tp_up"] = "0"
    local view = callHook("CalcView", ply, Vector(0, 0, 64), Angle(0, 0, 0), 90)
    ok(view ~= nil, "камера считается")
    if view then
        ok(view.origin:Distance(Vector(0, 0, 64)) <= TP.Limits.dist[2] + 1,
            "запредельное отдаление обрезано лимитом",
            view.origin:Distance(Vector(0, 0, 64)))
    end
    CVARS["grm_tp_dist"] = "70"
    CVARS["grm_tp_right"] = "22"
    CVARS["grm_tp_up"] = "4"
end

-----------------------------------------------------------------------
print("\n=== 5. КАМЕРА НЕ ЛЕЗЕТ В СТЕНУ И НЕ ЛОМАЕТ ПРИЦЕЛ ===")
-----------------------------------------------------------------------
do
    CVARS["grm_tp_smooth"] = "0"     -- сглаживание мешает точной проверке
    local origin, ang = Vector(0, 0, 64), Angle(0, 0, 0)

    _G.__BLOCK = Vector(-20, 0, 64)  -- стена в 20 юнитах позади
    local view = callHook("CalcView", ply, origin, ang, 90)
    ok(view ~= nil, "при препятствии камера всё равно возвращается")
    if view then
        ok(view.origin:Distance(origin) < 70,
            "камера прижалась к стене, а не ушла сквозь неё",
            view.origin:Distance(origin))
        --[[ Углы обязаны остаться исходными: если их менять, прицел
             разъедется с направлением взгляда и стрелять станет
             невозможно. ]]
        ok(view.angles == ang, "углы обзора не подменяются — прицел честный")
    end
    _G.__BLOCK = nil

    local v2 = callHook("CalcView", ply, origin, ang, 90)
    ok(v2 and v2.drawviewer == true, "модель игрока показывается")

    -- FOV: 0 означает «не трогать».
    CVARS["grm_tp_fov"] = "0"
    local v3 = callHook("CalcView", ply, origin, ang, 90)
    ok(v3 and v3.fov == nil, "нулевой FOV оставляет игровой угол обзора")
    CVARS["grm_tp_fov"] = "75"
    local v4 = callHook("CalcView", ply, origin, ang, 90)
    ok(v4 and v4.fov == 75, "заданный FOV применяется", v4 and v4.fov)
    CVARS["grm_tp_fov"] = "0"

    -- Выключенный режим не должен вмешиваться вообще.
    CVARS["grm_tp_enabled"] = "0"
    ok(callHook("CalcView", ply, origin, ang, 90) == nil,
        "выключённый модуль камеру не трогает")
    ok(callHook("ShouldDrawLocalPlayer") == nil, "и модель не показывает")
    CVARS["grm_tp_enabled"] = "1"
    ok(callHook("ShouldDrawLocalPlayer") == true, "включённый — показывает")
end

-----------------------------------------------------------------------
print("\n=== 6. ИНВЕНТАРЬ: ПОЧЕМУ НЕ РАБОТАЛО УДЕРЖАНИЕ ===")
-----------------------------------------------------------------------
do
    local ui = readf("lua/autorun/client/cl_grm_inventory_ui.lua")
    local core = readf("lua/autorun/sh_grm_inventory.lua")

    --[[ Корень проблемы: MakePopup забирает клавиатуру, и до хука
         PlayerButtonUp нажатия не доходят. ]]
    ok(ui:find("f:SetKeyboardInputEnabled(false)", 1, true) ~= nil,
        "ИСПРАВЛЕНО: окно не забирает клавиатуру — отпускание доходит до хука")

    -- Порядок важен: снимать фокус надо ПОСЛЕ MakePopup.
    local iPopup = ui:find("f:MakePopup()", 1, true)
    local iKb = ui:find("f:SetKeyboardInputEnabled(false)", 1, true)
    ok(iPopup and iKb and iKb > iPopup,
        "клавиатура снимается после MakePopup, иначе он вернёт её обратно")

    --[[ Забрав клавиатуру, мы лишили окно Escape — DFrame его больше
         не увидит, значит закрытие вешаем сами. ]]
    ok(ui:find('hook.Add("PlayerButtonDown", "GRM_Inv_Escape"', 1, true) ~= nil,
        "Escape обработан вручную")
    ok(ui:find('hook.Remove("PlayerButtonDown", "GRM_Inv_Escape")', 1, true) ~= nil,
        "и снимается при закрытии окна — иначе хук копился бы")

    -- Догадка владельца про C-меню.
    local cmd = core:match('concommand%.Add%("grm_inventory".-\n    end%)')
    ok(cmd and cmd:find("IsOpen", 1, true) ~= nil,
        "ИСПРАВЛЕНО: команда из C-меню работает переключателем")
    ok(cmd and cmd:find("CloseGUI", 1, true) ~= nil,
        "открытое окно она закрывает, а не открывает поверх")
end

-----------------------------------------------------------------------
print("\n=== 7. НАСТРОЙКИ В F4 ===")
-----------------------------------------------------------------------
do
    local f4 = readf("lua/autorun/sh_grm_f4menu.lua")
    ok(f4:find("Вид от третьего лица:", 1, true) ~= nil, "в F4 есть блок настроек")
    for _, c in ipairs({ "grm_tp_enabled", "grm_tp_dist", "grm_tp_right",
                         "grm_tp_up", "grm_tp_fov", "grm_tp_smooth",
                         "grm_tp_incar", "grm_tp_incombat" }) do
        ok(f4:find(c, 1, true) ~= nil, "настраивается " .. c)
    end
    --[[ SetConVar сохраняет значение сам: без него настройки слетали бы
         при перезаходе, и владелец крутил бы их каждый раз заново. ]]
    ok(f4:find('s:SetConVar(cvar)', 1, true) ~= nil,
        "слайдеры пишут прямо в конвары — значения сохраняются")
end

-----------------------------------------------------------------------
print(string.format("\nИТОГО: %d ok, %d FAIL", pass, fail))
os.exit(fail == 0 and 0 or 1)
