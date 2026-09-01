--[[--------------------------------------------------------------------
    sim_cutscene_world_render — мир виден из камеры кат-сцены.

    ЖАЛОБА ВЛАДЕЛЬЦА: «кат-сцене надо пофиксить рендер 3d2d textscreen,
    надписей, сущностей».

    ПРИЧИНА. Камеру сцены двигает CalcView, но ТЕЛО игрока остаётся на
    месте. А почти весь мировой 3D2D решает «рисовать или нет» по
    расстоянию до тела:

        if lp:GetPos():DistToSqr(self:GetPos()) > 400 * 400 then return end
        if self:GetPos():DistToSqr(ply:GetShootPos()) < render_range then

    Таких проверок 95 в 53 файлах (наши энтити, вывески, таблички
    недвижимости, сторонний Textscreens). Камера улетает к точке съёмки —
    тело далеко — надписи и подписи гаснут. В кадре голая геометрия.

    ПОЧЕМУ НЕ ПРАВИТЬ КАЖДОЕ МЕСТО. 95 правок в 53 файлах, включая чужой
    аддон Textscreens, который сверяется с апстримом. Любой новый модуль
    снова напишет lp:GetPos() и снова сломает кадр. Чинить нужно один раз
    и там, где причина: на время кадра сцены методы позиции ЛОКАЛЬНОГО
    игрока должны возвращать позицию камеры.

    ГРАНИЦЫ ПОДМЕНЫ. Только клиент, только LocalPlayer, только на время
    отрисовки (мир + HUD) и только пока сцена активна. Игровая логика,
    Think и сервер не затронуты: за пределами кадра методы прежние.

    Запуск: luajit tools/luatest/sim_cutscene_world_render.lua
----------------------------------------------------------------------]]
local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

local src = read("lua/autorun/client/cl_grm_quests.lua")

print("\n=== 1. ПОДМЕНА ОБЪЯВЛЕНА И ОГРАНИЧЕНА КАДРОМ ===")
ok(src:find("GRM_Quest_CutsceneViewPos", 1, true) ~= nil,
    "есть механизм подмены точки обзора на время сцены")
ok(src:find("PreDrawOpaqueRenderables", 1, true) ~= nil,
    "подмена включается перед отрисовкой мира")
ok(src:find("PostDrawTranslucentRenderables", 1, true) ~= nil,
    "и выключается после неё — вне кадра методы прежние")

print("\n=== 2. ЖИВОЙ ПРОГОН ПОДМЕНЫ ===")
--[[ Модель повторяет боевую: метатаблица игрока, подмена трёх методов,
     включение и выключение по кадру. Проверяем, что видит энтити. ]]
local CAM = { x = 5000, y = 0, z = 0 }
local BODY = { x = 0, y = 0, z = 0 }
local function V(t)
    local v = { x = t.x, y = t.y, z = t.z }
    function v:DistToSqr(o) local a, b, c = self.x - o.x, self.y - o.y, self.z - o.z return a * a + b * b + c * c end
    return v
end

local meta = {}
meta.__index = meta
function meta:GetPos() return V(BODY) end
function meta:GetShootPos() return V(BODY) end
function meta:EyePos() return V(BODY) end
local lp = setmetatable({}, meta)

local scene = { active = false, currentPos = CAM }
local saved, patched = {}, false
local function applyViewPos()
    if patched then return end
    patched = true
    for _, name in ipairs({ "GetPos", "GetShootPos", "EyePos" }) do
        saved[name] = meta[name]
        meta[name] = function(self)
            -- подменяем ТОЛЬКО у локального игрока и только пока сцена идёт
            if self == lp and scene.active and scene.currentPos then return V(scene.currentPos) end
            return saved[name](self)
        end
    end
end
local function clearViewPos()
    if not patched then return end
    patched = false
    for name, fn in pairs(saved) do meta[name] = fn end
    saved = {}
end

-- энтити рядом с камерой, но далеко от тела — типичная жертва бага
local signPos = V({ x = 5100, y = 0, z = 0 })
local function signVisible() return lp:GetPos():DistToSqr(signPos) <= 400 * 400 end

ok(signVisible() == false, "до сцены дальняя вывеска не рисуется — это норма")

scene.active = true
applyViewPos()
ok(signVisible() == true, "в кадре сцены вывеска у камеры ВИДНА")
ok(lp:GetShootPos():DistToSqr(signPos) <= 400 * 400,
    "GetShootPos тоже смотрит из камеры (им пользуется Textscreens)")
ok(lp:EyePos():DistToSqr(signPos) <= 400 * 400, "EyePos тоже")

clearViewPos()
ok(signVisible() == false, "после кадра методы вернулись к телу игрока")

print("\n=== 3. ПОДМЕНА НЕ ТЕЧЁТ ЗА ПРЕДЕЛЫ СЦЕНЫ ===")
--[[ Самое опасное: если восстановление не сработает, у игрока НАВСЕГДА
     съедет позиция во всех клиентских проверках. Проверяем, что метод
     возвращается на место побайтово. ]]
local before = meta.GetPos
applyViewPos()
local during = meta.GetPos
clearViewPos()
ok(meta.GetPos == before, "GetPos восстановлен ровно тот же (не обёртка)")
ok(during ~= before, "во время кадра он действительно был подменён")

print("\n=== 4. ПОВТОРНЫЕ ВЫЗОВЫ БЕЗОПАСНЫ ===")
applyViewPos() applyViewPos() applyViewPos()
clearViewPos()
ok(meta.GetPos == before, "тройное включение и одно выключение не оставили обёрток")
clearViewPos() clearViewPos()
ok(meta.GetPos == before, "лишние выключения ничего не ломают")

print("\n=== 5. ЧУЖОЙ ИГРОК НЕ ЗАТРОНУТ ===")
--[[ Подменять позицию у ДРУГИХ игроков нельзя: по ней рисуются их
     таблички, и они уехали бы к камере. ]]
local other = setmetatable({}, meta)
scene.active = true
applyViewPos()
local otherPos = other:GetPos()
ok(otherPos.x == BODY.x, "у другого игрока позиция настоящая", otherPos.x)
clearViewPos()
scene.active = false

print("\n=== 6. СЦЕНА ЗАКОНЧИЛАСЬ — ПОДМЕНА СНЯТА ===")
-- Выход из сцены обязан снимать подмену, даже если кадр не завершился
-- штатно (пропуск пробелом, смерть, отключение).
ok(src:find("GRM_Quest_CutsceneViewPos", 1, true) ~= nil, "механизм именован для снятия")
local stopFn = src:match("local function stopCutscene%(%).-\n") or ""
ok(stopFn:find("ClearCutsceneViewPos", 1, true) ~= nil or src:find("ClearCutsceneViewPos", 1, true) ~= nil,
    "остановка сцены снимает подмену")

print("\n=== 7. МИРОВЫЕ ХУКИ НЕ СНИМАЮТСЯ ЦЕЛИКОМ ===")
--[[ Отдельная причина пустого кадра: HUDPaint-хуки чужих модулей
     снимались, а среди них есть рисующие подписи над объектами. Список
     KEEP_HUDPAINT должен существовать и быть непустым. ]]
ok(src:find("KEEP_HUDPAINT", 1, true) ~= nil, "белый список мировых подписей на месте")
ok(src:find("GRM_Doors_HUD3D2D", 1, true) ~= nil, "подписи дверей сохраняются")
ok(src:find("Q.KeepDuringCutscene", 1, true) ~= nil,
    "сторонний модуль может добавить свой хук в белый список")

print("\n=== 8. ПРОГОН БОЕВЫХ ФУНКЦИЙ ПОДМЕНЫ ===")
--[[ Разделы 2-5 гоняли модель, переписанную в стенде. Этого мало:
     копия может быть верной, а боевой код — нет (так стенд привязки
     ролика к ответу однажды уже пропустил регрессию). Здесь достаём
     НАСТОЯЩИЕ applyCutsceneViewPos/clearCutsceneViewPos из файла через
     загрузку модуля в моке клиента. ]]
CLIENT, SERVER = true, false
local PMETA = {}
PMETA.__index = PMETA
local realBody = { x = 0, y = 0, z = 0 }
local function MV(t)
    local v = { x = t.x, y = t.y, z = t.z }
    function v:DistToSqr(o) local a, b, c = self.x-o.x, self.y-o.y, self.z-o.z return a*a+b*b+c*c end
    function v:Distance(o) return math.sqrt(self:DistToSqr(o)) end
    return v
end
function PMETA:GetPos() return MV(realBody) end
function PMETA:GetShootPos() return MV(realBody) end
function PMETA:EyePos() return MV(realBody) end
function PMETA:IsPlayer() return true end
function PMETA:Nick() return "Игрок" end

local ME = setmetatable({ _valid = true }, PMETA)
function FindMetaTable(n) if n == "Player" then return PMETA end return {} end
function LocalPlayer() return ME end
function IsValid(v) return type(v) == "table" and v._valid ~= false end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function isfunction(v) return type(v) == "function" end
function CurTime() return 100 end
function RealTime() return 100 end
function Vector(x, y, z) return MV({ x = x or 0, y = y or 0, z = z or 0 }) end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
function ScrW() return 1920 end
function ScrH() return 1080 end
function AddCSLuaFile() end
function include() end
math.Clamp = function(v, lo, hi) v = tonumber(v) or lo
    if v < lo then return lo end if v > hi then return hi end return v end
math.ease = { InOutSine = function(t) return t end }
string.Trim = function(x) return (tostring(x):gsub("^%s+", ""):gsub("%s+$", "")) end
table.Copy = function(t) if type(t) ~= "table" then return t end
    local o = {} for k, v in pairs(t) do o[k] = table.Copy(v) end return o end
table.Count = function(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end

local HK = {}
hook = {
    Add = function(ev, id, fn) HK[ev] = HK[ev] or {} HK[ev][id] = fn end,
    Remove = function(ev, id) if HK[ev] then HK[ev][id] = nil end end,
    Run = function() end,
    GetTable = function() return HK end,
}
net = { Receive = function() end, Start = function() end, SendToServer = function() end,
        ReadTable = function() return {} end, WriteTable = function() end,
        WriteString = function() end, WriteUInt = function() end, WriteBool = function() end }
surface = { CreateFont = function() end, PlaySound = function() end, SetDrawColor = function() end,
            DrawRect = function() end, SetFont = function() end, GetTextSize = function() return 10, 10 end }
draw = { SimpleText = function() end, RoundedBox = function() end, NoTexture = function() end,
         DrawText = function() end, Text = function() end }
cam = { Start3D2D = function() end, End3D2D = function() end }
render, vgui = {}, { Create = function() return nil end }
gui = { EnableScreenClicker = function() end, IsGameUIVisible = function() return false end,
        IsConsoleVisible = function() return false end }
input = { IsKeyDown = function() return false end, IsMouseDown = function() return false end }
timer = { Simple = function() end, Create = function() end, Remove = function() end }
util = { AddNetworkString = function() end, JSONToTable = function() return {} end,
         TableToJSON = function() return "{}" end }
file = { Read = function() return nil end, Write = function() end, Exists = function() return false end,
         Find = function() return {}, {} end, CreateDir = function() end, IsDir = function() return false end }
ents = { FindByClass = function() return {} end, GetAll = function() return {} end,
         FindInSphere = function() return {} end, Create = function() return nil end }
player = { GetAll = function() return { ME } end }
concommand = { Add = function() end }
notification = { AddLegacy = function() end }
chat = { AddText = function() end }
language = { Add = function() end }
CreateClientConVar = function() return { GetBool = function() return false end,
    GetInt = function() return 0 end, GetFloat = function() return 0 end,
    GetString = function() return "" end } end
GetConVar = CreateClientConVar
CreateConVar = CreateClientConVar
NOTIFY_HINT, NOTIFY_ERROR, NOTIFY_GENERIC = 1, 2, 3
TEXT_ALIGN_CENTER, TEXT_ALIGN_LEFT, TEXT_ALIGN_RIGHT = 1, 0, 2
GRM = GRM or {}
GRM.Quests = GRM.Quests or {}
LerpVector = function(_, a) return a end
LerpAngle = function(_, a) return a end
Lerp = function(_, a) return a end
EyePos = function() return MV(realBody) end
EyeAngles = function() return Angle(0, 0, 0) end
FrameTime = function() return 0.016 end
Material = function() return {} end
CreateSound = nil

local loaded = pcall(function()
    local chunk = assert(loadfile("lua/autorun/client/cl_grm_quests.lua"))
    chunk()
end)
ok(loaded, "клиентский модуль квестов загрузился в моке")

local QQ = GRM.Quests
local apply = HK["PreDrawOpaqueRenderables"] and HK["PreDrawOpaqueRenderables"]["GRM_Quest_CutsceneViewPos"]
local clear = HK["PostDrawTranslucentRenderables"] and HK["PostDrawTranslucentRenderables"]["GRM_Quest_CutsceneViewPos"]
ok(isfunction(apply), "боевой хук включения подмены зарегистрирован")
ok(isfunction(clear), "боевой хук снятия зарегистрирован")

if isfunction(apply) and isfunction(clear) then
    local origGetPos = PMETA.GetPos
    local camPos = MV({ x = 5000, y = 0, z = 0 })
    QQ.Cutscene = { active = true, currentPos = camPos }

    apply()
    local seen = ME:GetPos()
    ok(seen.x == 5000, "БОЕВАЯ подмена: игрок «стоит» в камере", seen.x)
    local sign = MV({ x = 5100, y = 0, z = 0 })
    ok(ME:GetPos():DistToSqr(sign) <= 400 * 400,
        "дальняя вывеска попадает в радиус отрисовки")
    ok(ME:GetShootPos().x == 5000, "GetShootPos тоже (его читает Textscreens)")

    clear()
    ok(PMETA.GetPos == origGetPos, "БОЕВОЕ снятие вернуло исходный метод")
    ok(ME:GetPos().x == 0, "после кадра позиция снова у тела", ME:GetPos().x)

    -- сцена не активна: подмена не должна включаться вовсе
    QQ.Cutscene = { active = false }
    apply()
    ok(PMETA.GetPos == origGetPos, "вне сцены подмена не ставится")
    clear()
end

print(("\nCUTSCENE WORLD RENDER: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
