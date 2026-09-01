--[[ Живой прогон экрана входа GROENNERLAND2036 и чистки стандартных худов
     (заказ владельца 22.08).
     Чистые функции грузятся из НАСТОЯЩИХ файлов, остальное — контракт.
     Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_loading.lua ]]
local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

SERVER, CLIENT = false, false
function AddCSLuaFile() end
function IsValid(v) return type(v) == "table" and v._valid ~= false end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isfunction(v) return type(v) == "function" end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
hook = { Add = function() end, Run = function() end }
GRM = {}

assert(loadfile("lua/autorun/sh_grm_loading.lua"))()
local LD = GRM.Loading

print("\n=== 1. ПРОГРЕСС СЧИТАЕТСЯ ПО ЭТАПАМ ===")
ok(isfunction(LD.Progress) and isfunction(LD.CurrentStep), "чистые функции прогресса объявлены")
local steps = {
    { label = "Соединение", weight = 1, done = true },
    { label = "Настройки", weight = 1, done = true },
    { label = "Подсистемы", weight = 4, done = false },
    { label = "Персонаж", weight = 2, done = false },
}
ok(math.abs(LD.Progress(steps) - (2 / 8)) < 0.001, "вес этапов учитывается", LD.Progress(steps))
ok(LD.CurrentStep(steps) == "Подсистемы", "показывается первый незавершённый этап", LD.CurrentStep(steps))
steps[3].done, steps[4].done = true, true
ok(LD.Progress(steps) == 1 and LD.CurrentStep(steps) == "Готово", "всё выполнено — сто процентов")
ok(LD.Progress(nil) == 0 and LD.CurrentStep({}) == "Готово", "мусор не ломает расчёт")

print("\n=== 2. КОНТРАКТ ЭКРАНА ===")
local src = (function()
    local f = io.open("lua/autorun/sh_grm_loading.lua", "rb")
    local t = f:read("*a") f:close() return t
end)()
local function has(n) return src:find(n, 1, true) ~= nil end
ok(has('draw.SimpleText("GROENNERLAND2036"'), "золотой заголовок проекта")
ok(has('draw.SimpleText("ДОБРО ПОЖАЛОВАТЬ НА ПРОЕКТ!"'), "приветствие под заголовком")
ok(has("local GOLD = Color(226, 184, 92)") and has("Color(0, 0, 0, 255)"), "чёрный фон, золотые буквы")
ok(has('draw.SimpleText("НАЧАТЬ ИГРАТЬ"'), "кнопка вместо полосы, когда всё готово")
ok(has("playBtn:SetVisible(ready)") and has("bar:SetVisible(not ready)"),
   "полоса и кнопка меняются местами по готовности")
ok(has("frame.Close = function() end") and has("key == KEY_ESCAPE then return true"),
   "экран не закрыть ни крестиком, ни ESC")
ok(has("self.nextCheck = RealTime() + 0.25"), "этапы сверяются 4 раза в секунду, а не каждый кадр")
ok(has("RealTime() - shown > 45"), "страховка: зависший сервер не запирает игрока навсегда")

print("\n=== 3. СЕРВЕР ОТДАЁТ РЕАЛЬНУЮ ГОТОВНОСТЬ ===")
ok(has("function LD.BootShare()") and has("GRM.Boot.Status"),
   "доля считается по планировщику старта GRM.Boot")
ok(has('timer.Create("GRM_Loading_Push", 0.5, 0'), "прогресс шлётся редко и только грузящимся")
ok(has("if not any then timer.Remove"), "таймер умирает, когда грузящихся нет")
ok(has("net.Receive(LD.Net.READY") and has("GRM.Char.OpenMenu(ply)"),
   "по кнопке открывается окно персонажа")
ok(has("function LD.IsLoading(ply)"), "остальные модули могут спросить, грузится ли игрок")

local ch = (function()
    local f = io.open("lua/autorun/sh_grm_character.lua", "rb")
    local t = f:read("*a") f:close() return t
end)()
ok(ch:find("GRM.Loading.IsLoading(ply)", 1, true) ~= nil,
   "меню персонажа не всплывает поверх загрузки")
ok(ch:find("if GRM.Loading and GRM.Loading.Shown then return end", 1, true) ~= nil,
   "сторож окна персонажа тоже ждёт конца загрузки")

print("\n=== 4. СТАНДАРТНЫЕ ХУДЫ ВЫКЛЮЧЕНЫ ===")
local hud = (function()
    local f = io.open("lua/autorun/client/cl_grm_hud_clean.lua", "rb")
    local t = f:read("*a") f:close() return t
end)()
local function hhas(n) return hud:find(n, 1, true) ~= nil end
ok(hhas("CHudHealth = true") and hhas("CHudBattery = true") and hhas("CHudSuitPower = true"),
   "здоровье, броня и костюм HL2 скрыты")
ok(hhas('hook.Add("HUDDrawTargetID"'), "стандартная подпись «ник + здоровье» над игроком убрана")
ok(hhas("CHudCrosshair = false"), "прицел оставлен — это часть игры, а не худ")
ok(hhas('CreateClientConVar("grm_hud_hl2"'), "всё возвращается одним конваром")

print(("\nLOADING: %d/%d, провалов: %d"):format(pass, pass + fail, fail))
if fail > 0 then os.exit(1) end
