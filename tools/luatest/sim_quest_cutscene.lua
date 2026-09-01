--[[ Живой прогон кат-сцен квестов (заказ владельца 28.08).

     «Кат-сцены: когда проигрываются, полоски чёрные должны быть
      чёрными, а не прозрачными, и худ не должен рисоваться. Во время
      кат-сцены ничего лишнего быть не должно. Игрок не должен
      использовать селектор оружия или какие-либо меню.»

     ЧТО БЫЛО НЕ ТАК.

       1) Полосы рисовались Color(0,0,0,235) — сквозь них просвечивал
          мир. «Прозрачные», как и сказал владелец.
       2) Кат-сцена рисовалась в общем HUDPaint, поэтому чужие HUDPaint
          (наш HUD, метки, трекер квестов) ложились ПОВЕРХ полос.
       3) Стандартный HUD Source никто не выключал: здоровье, патроны,
          прицел и селектор оружия оставались на экране.
       4) CreateMove гасил движение, но НЕ привязки: invnext/invprev
          листали оружие, Q открывал спавн-меню, C — контекстное.

     Стенд грузит НАСТОЯЩИЙ клиентский файл и дёргает реальные хуки, а
     не разбирает текст: так проверяется поведение, а не формулировки.

     Запуск: luajit tools/luatest/sim_quest_cutscene.lua ]]

local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

-----------------------------------------------------------------------
-- ОКРУЖЕНИЕ КЛИЕНТА GARRY'S MOD
-----------------------------------------------------------------------
CLIENT, SERVER = true, false
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function isfunction(v) return type(v) == "function" end
function IsValid(v) return istable(v) and v._valid ~= false end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
function Vector(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
function string.Trim(s) return (string.gsub(tostring(s or ""), "^%s*(.-)%s*$", "%1")) end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function table.Copy(t)
    local o = {}
    for k, v in pairs(t or {}) do o[k] = istable(v) and table.Copy(v) or v end
    return o
end
math.ease = { InOutSine = function(t) return t end }
function LerpVector(_, a) return a end
function LerpAngle(_, a) return a end
function Lerp(_, a) return a end

--[[ Рисование ПИШЕМ В ЖУРНАЛ: только так можно проверить, что полоса
     действительно чёрная и непрозрачная, а не поверить комментарию. ]]
local DRAWN = {}
local drawColor = { r = 255, g = 255, b = 255, a = 255 }
surface = {
    CreateFont = function() end,
    SetFont = function() end,
    GetTextSize = function() return 10, 10 end,
    SetDrawColor = function(r, g, b, a)
        if istable(r) then drawColor = { r = r.r, g = r.g, b = r.b, a = r.a or 255 }
        else drawColor = { r = r, g = g, b = b, a = a or 255 } end
    end,
    DrawRect = function(x, y, w, h)
        DRAWN[#DRAWN + 1] = { kind = "rect", x = x, y = y, w = w, h = h,
            r = drawColor.r, g = drawColor.g, b = drawColor.b, a = drawColor.a }
    end,
    DrawOutlinedRect = function() end,
    SetMaterial = function() end,
    DrawTexturedRect = function(x, y, w, h)
        DRAWN[#DRAWN + 1] = { kind = "image", x = x, y = y, w = w, h = h }
    end,
    PlaySound = function() end,
}
draw = {
    RoundedBox = function(_, x, y, w, h, col)
        DRAWN[#DRAWN + 1] = { kind = "rect", x = x, y = y, w = w, h = h,
            r = col and col.r, g = col and col.g, b = col and col.b,
            a = col and (col.a or 255) }
    end,
    RoundedBoxEx = function() end,
    SimpleText = function(txt, _, x, y)
        DRAWN[#DRAWN + 1] = { kind = "text", text = tostring(txt or ""), x = x, y = y }
    end,
    SimpleTextOutlined = function(txt, _, x, y)
        DRAWN[#DRAWN + 1] = { kind = "text", text = tostring(txt or ""), x = x, y = y }
    end,
}

hook = { _t = {} }
function hook.Add(e, i, f) hook._t[e] = hook._t[e] or {}; hook._t[e][i] = f end
function hook.Remove(e, i) if hook._t[e] then hook._t[e][i] = nil end end
function hook.GetTable() return hook._t end
function hook.Run(e, ...)
    for _, f in pairs(hook._t[e] or {}) do local r = f(...) if r ~= nil then return r end end
end

net = setmetatable({}, { __index = function() return function() return "" end end })
vgui = { Create = function() return setmetatable({}, { __index = function() return function() end end }) end }
concommand = { Add = function() end }
timer = { Simple = function() end, Create = function() end }
notification = { AddLegacy = function() end }
gui = { EnableScreenClicker = function() end }
function ScrW() return 1920 end
function ScrH() return 1080 end
local NOW = 100
function CurTime() return NOW end
function RealTime() return NOW end
local LP = { _valid = true }
function LocalPlayer() return LP end
function Material() return {} end
NOTIFY_HINT, KEY_SPACE = 1, 32
TEXT_ALIGN_CENTER, TEXT_ALIGN_RIGHT, TEXT_ALIGN_LEFT = 1, 2, 0
GRM = {}

assert(loadfile("lua/autorun/client/cl_grm_quests.lua"))()
local Q = GRM.Quests
assert(Q, "GRM.Quests не загрузился")

--- Включить кат-сцену как это делает startCutscene.
local function beginCutscene()
    Q.Cutscene = {
        active = true, index = 1, phase = "hold", phaseStart = NOW, soundNode = 0,
        nodes = { { id = "camera_1", caption = "Пролог", duration = 3,
            pos = { x = 0, y = 0, z = 0 }, ang = { p = 0, y = 0, r = 0 }, fov = 75 } },
    }
end
local function endCutscene() Q.Cutscene = { active = false } end

local function paintFrame()
    DRAWN = {}
    hook.Run("HUDPaintBackground")
    for id, fn in pairs(hook._t.HUDPaint or {}) do fn() end
end

-----------------------------------------------------------------------
print("\n=== 1. ПОЛОСЫ ПОЛНОСТЬЮ ЧЁРНЫЕ ===")
-----------------------------------------------------------------------
beginCutscene()
paintFrame()

local bars = {}
for _, d in ipairs(DRAWN) do
    if d.kind == "rect" and d.w and d.w >= ScrW() then bars[#bars + 1] = d end
end
ok(#bars >= 2, "нарисованы обе полосы — верхняя и нижняя", #bars)

local allOpaque, allBlack = true, true
for _, b in ipairs(bars) do
    if (b.a or 255) < 255 then allOpaque = false end
    if (b.r or 0) ~= 0 or (b.g or 0) ~= 0 or (b.b or 0) ~= 0 then allBlack = false end
end
ok(allOpaque,
   "ИСПРАВЛЕНО: полосы полностью непрозрачные — мир сквозь них не видно",
   bars[1] and ("alpha=" .. tostring(bars[1].a)))
ok(allBlack, "и именно чёрные, а не тёмно-серые")

--[[ БАГ ВОСПРОИЗВЕДЁН: старое значение альфы. 235 из 255 — это 8%
     прозрачности, ровно то, на что жаловался владелец. ]]
local OLD_ALPHA = 235
ok(OLD_ALPHA < 255,
   "БАГ ВОСПРОИЗВЕДЁН: прежняя альфа 235 пропускала картинку мира",
   ("%d из 255"):format(OLD_ALPHA))

-- Полосы должны накрывать верх и низ экрана целиком по ширине.
local topBar, bottomBar
for _, b in ipairs(bars) do
    if b.y == 0 then topBar = b
    elseif (b.y + b.h) >= ScrH() - 1 then bottomBar = b end
end
ok(topBar ~= nil, "верхняя полоса прижата к верху экрана")
ok(bottomBar ~= nil, "нижняя — к низу")
ok(topBar and topBar.h > 0 and bottomBar and bottomBar.h > 0, "обе имеют высоту")
ok(topBar and topBar.h + bottomBar.h < ScrH() * 0.5,
   "но вместе не съедают половину экрана — кадр остаётся видимым",
   topBar and (topBar.h + bottomBar.h))

-----------------------------------------------------------------------
print("\n=== 2. ПОДПИСЬ ВНУТРИ ПОЛОСЫ, А НЕ НА КАДРЕ ===")
-----------------------------------------------------------------------
local caption
for _, d in ipairs(DRAWN) do
    if d.kind == "text" and d.text == "Пролог" then caption = d end
end
ok(caption ~= nil, "подпись сцены нарисована")
ok(caption and bottomBar and caption.y >= bottomBar.y,
   "и лежит ВНУТРИ нижней чёрной полосы, а не поверх картинки",
   caption and ("текст y=%d, полоса с y=%d"):format(caption.y, bottomBar.y))

local skipHint
for _, d in ipairs(DRAWN) do
    if d.kind == "text" and tostring(d.text):find("ПРОБЕЛ", 1, true) then skipHint = d end
end
ok(skipHint ~= nil, "подсказка о пропуске на месте")
ok(skipHint and bottomBar and skipHint.y >= bottomBar.y,
   "тоже внутри полосы")

-----------------------------------------------------------------------
print("\n=== 3. СТАНДАРТНЫЙ HUD СПРЯТАН ===")
-----------------------------------------------------------------------
local HIDE = { "CHudHealth", "CHudBattery", "CHudAmmo", "CHudSecondaryAmmo",
    "CHudWeaponSelection", "CHudCrosshair", "CHudDamageIndicator", "CHudZoom" }
local hidden = 0
for _, name in ipairs(HIDE) do
    if hook.Run("HUDShouldDraw", name) == false then hidden = hidden + 1 end
end
ok(hidden == #HIDE, "ИСПРАВЛЕНО: весь стандартный HUD скрыт на время сцены",
   ("%d из %d"):format(hidden, #HIDE))

ok(hook.Run("HUDShouldDraw", "CHudWeaponSelection") == false,
   "СЕЛЕКТОР ОРУЖИЯ скрыт — прямое требование владельца")

-- Чат оставляем: лишать переписки на минуту ролика неправильно.
ok(hook.Run("HUDShouldDraw", "CHudChat") ~= false, "чат не тронут")

-- Вне сцены HUD обязан вернуться.
endCutscene()
local shownBack = 0
for _, name in ipairs(HIDE) do
    if hook.Run("HUDShouldDraw", name) ~= false then shownBack = shownBack + 1 end
end
ok(shownBack == #HIDE, "после сцены HUD снова рисуется — не выключили насовсем",
   ("%d из %d"):format(shownBack, #HIDE))

-----------------------------------------------------------------------
print("\n=== 4. ЧУЖИЕ HUDPaint НЕ ЛЕЗУТ ПОВЕРХ ПОЛОС ===")
-----------------------------------------------------------------------
--[[ Главная причина «лишнего на экране»: HUDShouldDraw не властен над
     хуками аддонов. Вешаем поддельный чужой HUD и проверяем, что на
     время сцены он снимается, а после — возвращается. ]]
local foreignCalls = 0
hook.Add("HUDPaint", "SomeAddon_HUD", function() foreignCalls = foreignCalls + 1 end)
hook.Add("HUDPaint", "GRM_HUD_Main", function() foreignCalls = foreignCalls + 1 end)

paintFrame()
ok(foreignCalls == 2, "вне сцены чужие HUD рисуются как обычно", foreignCalls)

beginCutscene()
hook.Run("Think")     -- именно Think снимает чужие хуки

foreignCalls = 0
paintFrame()
ok(foreignCalls == 0,
   "ИСПРАВЛЕНО: во время сцены чужие HUDPaint не вызываются вообще",
   foreignCalls)

-- А наши полосы при этом обязаны остаться.
local barsStill = 0
for _, d in ipairs(DRAWN) do
    if d.kind == "rect" and d.w and d.w >= ScrW() then barsStill = barsStill + 1 end
end
ok(barsStill >= 2, "полосы кат-сцены никуда не делись", barsStill)

--[[ Хук, зарегистрированный УЖЕ ПОСЛЕ начала сцены, тоже надо поймать:
     аддоны вешают HUDPaint лениво. ]]
local lateCalls = 0
hook.Add("HUDPaint", "LateAddon_HUD", function() lateCalls = lateCalls + 1 end)
hook.Run("Think")
lateCalls = 0
paintFrame()
ok(lateCalls == 0, "поздно зарегистрированный чужой HUD тоже снимается", lateCalls)

-----------------------------------------------------------------------
print("\n=== 5. HUD ВОЗВРАЩАЕТСЯ ПОСЛЕ СЦЕНЫ ===")
-----------------------------------------------------------------------
--[[ Самый опасный сценарий: снять чужие хуки и забыть вернуть. Игрок
     остался бы без HUD до переподключения. ]]
ok(isfunction(Q.RestoreCutsceneHUD), "восстановление вынесено в отдельную точку")

--[[ Восстановление проверяем ШТАТНЫМ выходом из сцены, а не ручным
     вызовом: иначе стенд не заметит, если stopCutscene забудет его
     позвать. Ровно на этом первая версия блока и промахнулась. ]]
hook.Run("PlayerButtonDown", LP, KEY_SPACE)
ok(Q.Cutscene.active ~= true, "сцена завершена штатно, пробелом")

foreignCalls, lateCalls = 0, 0
paintFrame()
ok(foreignCalls == 2, "оба исходных чужих HUD вернулись сами", foreignCalls)
ok(lateCalls == 1, "и поздно добавленный тоже", lateCalls)

--[[ Восстановление не должно затирать хук, если за время сцены кто-то
     занял то же имя заново. ]]
beginCutscene()
hook.Run("Think")
local replaced = 0
hook.Add("HUDPaint", "SomeAddon_HUD", function() replaced = replaced + 1 end)
Q.RestoreCutsceneHUD()
endCutscene()
replaced = 0
paintFrame()
ok(replaced == 1, "свежий хук с тем же именем не затёрт старой копией", replaced)

-- Приводим окружение в порядок для следующих блоков.
hook.Remove("HUDPaint", "SomeAddon_HUD")
hook.Remove("HUDPaint", "GRM_HUD_Main")
hook.Remove("HUDPaint", "LateAddon_HUD")

-----------------------------------------------------------------------
print("\n=== 6. УПРАВЛЕНИЕ ЗАБЛОКИРОВАНО ===")
-----------------------------------------------------------------------
beginCutscene()

--[[ БАГ ВОСПРОИЗВЕДЁН: ClearButtons в CreateMove гасит кнопки движения,
     но привязки идут мимо него — оружие листалось колесом и цифрами. ]]
local BLOCK = { "invnext", "invprev", "slot1", "slot3", "+attack", "+attack2",
    "+menu", "+menu_context", "gm_showspare1", "+use", "+jump", "impulse 100" }
local blocked = 0
for _, bind in ipairs(BLOCK) do
    if hook.Run("PlayerBindPress", LP, bind, true) == true then blocked = blocked + 1 end
end
ok(blocked == #BLOCK,
   "ИСПРАВЛЕНО: привязки заблокированы, включая листание оружия",
   ("%d из %d"):format(blocked, #BLOCK))

ok(hook.Run("PlayerBindPress", LP, "invnext", true) == true,
   "СЕЛЕКТОР ОРУЖИЯ колесом не работает — прямое требование владельца")
ok(hook.Run("PlayerBindPress", LP, "slot1", true) == true,
   "и цифрами тоже")

--[[ Чат и консоль оставляем: человек должен суметь сообщить, что сцена
     сломалась, и открыть консоль. ]]
ok(hook.Run("PlayerBindPress", LP, "messagemode", true) ~= true, "чат работает")
ok(hook.Run("PlayerBindPress", LP, "messagemode2", true) ~= true, "командный чат тоже")
ok(hook.Run("PlayerBindPress", LP, "toggleconsole", true) ~= true, "консоль доступна")

ok(hook.Run("SpawnMenuOpen") == false, "спавн-меню не открыть")
ok(hook.Run("ContextMenuOpen") == false, "контекстное меню тоже")
ok(hook.Run("PlayerSwitchWeapon", LP) == true, "смена оружия запрещена и на уровне движка")

-- Движение и стрельба гасятся в CreateMove.
local cleared = { move = false, buttons = false }
local cmd = {
    ClearMovement = function() cleared.move = true end,
    ClearButtons = function() cleared.buttons = true end,
}
hook.Run("CreateMove", cmd)
ok(cleared.move and cleared.buttons, "движение и кнопки очищаются")

-----------------------------------------------------------------------
print("\n=== 7. ВНЕ СЦЕНЫ НИЧЕГО НЕ ЗАБЛОКИРОВАНО ===")
-----------------------------------------------------------------------
endCutscene()

local free = 0
for _, bind in ipairs(BLOCK) do
    if hook.Run("PlayerBindPress", LP, bind, true) ~= true then free = free + 1 end
end
ok(free == #BLOCK, "ИСПРАВЛЕНО: после сцены все привязки снова работают",
   ("%d из %d"):format(free, #BLOCK))
ok(hook.Run("SpawnMenuOpen") ~= false, "спавн-меню открывается")
ok(hook.Run("ContextMenuOpen") ~= false, "контекстное меню открывается")
ok(hook.Run("PlayerSwitchWeapon", LP) ~= true, "оружие снова переключается")

cleared.move, cleared.buttons = false, false
hook.Run("CreateMove", cmd)
ok(not cleared.move and not cleared.buttons, "управление не гасится")

-- И полосы больше не рисуются.
paintFrame()
local leftovers = 0
for _, d in ipairs(DRAWN) do
    if d.kind == "rect" and d.w and d.w >= ScrW() then leftovers = leftovers + 1 end
end
ok(leftovers == 0, "чёрные полосы исчезли вместе со сценой", leftovers)

-----------------------------------------------------------------------
print("\n=== 8. ПРОПУСК И СМЕРТЬ КОРРЕКТНО ЗАВЕРШАЮТ СЦЕНУ ===")
-----------------------------------------------------------------------
--[[ Здесь проверяем САМОЕ опасное: выход из сцены обязан вернуть чужие
     HUDPaint САМ, без ручного вызова восстановления. Забыть об этом —
     оставить игрока без HUD до переподключения.

     Первая версия блока дёргала Q.RestoreCutsceneHUD() вручную выше по
     стенду и потому не замечала, что stopCutscene её не зовёт. ]]
local afterSkip = 0
hook.Add("HUDPaint", "SomeAddon_HUD", function() afterSkip = afterSkip + 1 end)

beginCutscene()
hook.Run("Think")                      -- чужой хук снят
afterSkip = 0
paintFrame()
ok(afterSkip == 0, "во время сцены чужой HUD молчит", afterSkip)

hook.Run("PlayerButtonDown", LP, KEY_SPACE)
ok(Q.Cutscene.active ~= true, "ПРОБЕЛ прекращает сцену")
afterSkip = 0
paintFrame()
ok(afterSkip == 1,
   "ИСПРАВЛЕНО: пропуск сам вернул чужой HUDPaint, без ручного вызова",
   afterSkip)
ok(hook.Run("HUDShouldDraw", "CHudHealth") ~= false,
   "и стандартный HUD сразу возвращается")
ok(hook.Run("PlayerBindPress", LP, "invnext", true) ~= true,
   "управление разблокировано")

beginCutscene()
hook.Run("Think")
afterSkip = 0
paintFrame()
ok(afterSkip == 0, "перед смертью чужой HUD снова снят")

hook.Run("PlayerDeath", LP)
ok(Q.Cutscene.active ~= true, "смерть игрока тоже прекращает сцену")
afterSkip = 0
paintFrame()
ok(afterSkip == 1,
   "ИСПРАВЛЕНО: и на аварийном выходе HUD возвращается сам — игрок не слепнет",
   afterSkip)
ok(hook.Run("HUDShouldDraw", "CHudHealth") ~= false,
   "стандартный HUD тоже на месте")
hook.Remove("HUDPaint", "SomeAddon_HUD")

-----------------------------------------------------------------------
print("\n=== 9. ПОЛОСЫ ПЕРЕКРЫВАЮТ ПРОРВАВШИЙСЯ ЧУЖОЙ HUD ===")
-----------------------------------------------------------------------
--[[ Снятие чужих хуков ловит не всё: хук, добавленный между Think и
     кадром, успеет отрисоваться. Поэтому полосы рисуются ДВАЖДЫ —
     в HUDPaintBackground (до чужих) и в HUDPaint (после них).

     Проверяем именно перекрытие: в проходе HUDPaint полосы обязаны
     идти ПОСЛЕ чужого рисования, иначе его пиксели останутся сверху. ]]
beginCutscene()
hook.Run("Think")

local order = {}
hook.Add("HUDPaint", "AAA_SneakyHUD", function()
    order[#order + 1] = "foreign"
    DRAWN[#DRAWN + 1] = { kind = "text", text = "лишнее", x = 10, y = 10 }
end)

DRAWN = {}
hook.Run("HUDPaintBackground")
local bgBars = 0
for _, d in ipairs(DRAWN) do
    if d.kind == "rect" and d.w and d.w >= ScrW() then bgBars = bgBars + 1 end
end
ok(bgBars >= 2, "полосы рисуются в фоновом проходе, до чужих хуков", bgBars)

--[[ ВЕРХНИЙ ПРОХОД ПЕРЕЕХАЛ В DrawOverlay (правка 28.08).

     Пока снимались ВСЕ чужие HUDPaint, полосам хватало второго прохода
     в том же HUDPaint. Теперь подписи над сущностями специально
     оставлены и рисуются там же — а порядок хуков внутри одного события
     ничем не гарантирован. Метка над дверью могла лечь ПОВЕРХ полосы.

     DrawOverlay идёт после всего HUDPaint целиком, поэтому полосы
     всегда сверху. ]]
DRAWN = {}
for _, fn in pairs(hook._t.HUDPaint or {}) do fn() end
local barsInHudPaint = 0
for _, d in ipairs(DRAWN) do
    if d.kind == "rect" and d.w and d.w >= ScrW() then barsInHudPaint = barsInHudPaint + 1 end
end
ok(barsInHudPaint == 0,
   "второго прохода в HUDPaint больше нет — он не давал гарантии порядка",
   barsInHudPaint)

DRAWN = {}
hook.Run("DrawOverlay")
local overlayBars = 0
for _, d in ipairs(DRAWN) do
    if d.kind == "rect" and d.w and d.w >= ScrW() then overlayBars = overlayBars + 1 end
end
ok(overlayBars >= 2,
   "ИСПРАВЛЕНО: полосы рисуются в DrawOverlay — гарантированно поверх всех подписей",
   overlayBars)

hook.Remove("HUDPaint", "AAA_SneakyHUD")
endCutscene()

-----------------------------------------------------------------------
print("\n=== 10. ПОДПИСИ НАД СУЩНОСТЯМИ РИСУЮТСЯ В КАДРЕ ===")
-----------------------------------------------------------------------
--[[ Заказ владельца 28.08: «надо чтобы кат-сцена нормально рендерила
     подписи ко всяким энтити, сущностям, надписи над ними и т.д.»

     Прошлая версия снимала ВСЕ чужие HUDPaint и заодно убивала подписи
     над объектами: названия дверей, таблички недвижимости, имена
     игроков. В кадре оставалась голая геометрия. ]]

-- Мировые подписи: рисуют текст у конкретной точки мира.
local WORLD_LABELS = {
    "GRM_Nameplate", "GRM_RPDesc", "GRM_Doors_HUD3D2D", "GRM_Estate_Labels",
    "GRML_EntityLabels", "GRM_FC_ScrapBinLabel", "GRM_FC_Progress",
    "GRM_ChipControl_WorldTag", "GRM_Arrest_Label", "GRM_Bleedout_World",
    "GRM_Jobs_GPSMarker", "GRM_GPS_WorldMarkerHUD", "GRM_FireDispatch_HUD",
}
-- Панельный интерфейс игрока: в кадре ему делать нечего.
local PANEL_HUDS = {
    "GRM_HUD_Main", "GRM_Quest_Tracker", "GRM_Minimap_HUD", "GRM_Jobs_HudLine",
    "GRM_Ach_Toast", "GRM_Weight_Warning", "GRM_Wanted_BadgeV2",
    "GRM_Augmentations_HUD", "SomeRandomAddon_HUD",
}

local worldCalls, panelCalls = 0, 0
for _, id in ipairs(WORLD_LABELS) do
    hook.Add("HUDPaint", id, function() worldCalls = worldCalls + 1 end)
end
for _, id in ipairs(PANEL_HUDS) do
    hook.Add("HUDPaint", id, function() panelCalls = panelCalls + 1 end)
end

-- Вне сцены рисуются все.
worldCalls, panelCalls = 0, 0
paintFrame()
ok(worldCalls == #WORLD_LABELS and panelCalls == #PANEL_HUDS,
   "вне сцены рисуются и подписи, и панели",
   ("подписи %d, панели %d"):format(worldCalls, panelCalls))

beginCutscene()
hook.Run("Think")

worldCalls, panelCalls = 0, 0
paintFrame()
ok(worldCalls == #WORLD_LABELS,
   "ИСПРАВЛЕНО: во время сцены подписи над сущностями рисуются",
   ("%d из %d"):format(worldCalls, #WORLD_LABELS))
ok(panelCalls == 0,
   "а панельный интерфейс по-прежнему скрыт — лишнего в кадре нет",
   panelCalls)

--[[ Проверяем поимённо: пропажа даже одной подписи означает, что в
     сцене не подписан целый класс объектов. ]]
--[[ ВАЖНО: хук вешаем и ТОЛЬКО ПОТОМ прогоняем Think.

     Первая версия цикла добавляла хук уже после Think, поэтому снятие
     до него просто не доходило — проверка проходила даже когда список
     защищённых имён был пуст. Откат «снимать всё подряд» она не
     заметила. Теперь порядок правильный: добавили, дали сцене снять
     лишнее, и только тогда рисуем кадр. ]]
for _, id in ipairs(WORLD_LABELS) do
    local called = false
    hook.Add("HUDPaint", id, function() called = true end)
    hook.Run("Think")
    called = false
    paintFrame()
    ok(called, "рисуется: " .. id)
end

--[[ Полосы обязаны накрывать подписи, а не наоборот: иначе метка над
     дверью торчала бы на чёрной кайме. ]]
DRAWN = {}
paintFrame()
local labelsDrawn = #DRAWN
hook.Run("DrawOverlay")
local afterOverlay = 0
for i = labelsDrawn + 1, #DRAWN do
    local d = DRAWN[i]
    if d.kind == "rect" and d.w and d.w >= ScrW() then afterOverlay = afterOverlay + 1 end
end
ok(afterOverlay >= 2,
   "полосы ложатся ПОСЛЕ подписей — подпись обрезается каймой, как в кино",
   afterOverlay)

--[[ Точка расширения: сторонний модуль может защитить свой мировой хук
     без правки файла квестов. ]]
ok(isfunction(Q.KeepDuringCutscene), "есть открытая точка расширения списка")
local extCalls = 0
hook.Add("HUDPaint", "ThirdParty_WorldLabels", function() extCalls = extCalls + 1 end)
Q.KeepDuringCutscene("ThirdParty_WorldLabels")
hook.Run("Think")
extCalls = 0
paintFrame()
ok(extCalls == 1, "защищённый сторонний хук пережил сцену", extCalls)

Q.KeepDuringCutscene("ThirdParty_WorldLabels", false)
hook.Run("Think")
extCalls = 0
paintFrame()
ok(extCalls == 0, "и снимается обратно, когда защиту убрали", extCalls)

-- Возвращаем окружение в исходное состояние.
hook.Run("PlayerButtonDown", LP, KEY_SPACE)
for _, id in ipairs(WORLD_LABELS) do hook.Remove("HUDPaint", id) end
for _, id in ipairs(PANEL_HUDS) do hook.Remove("HUDPaint", id) end
hook.Remove("HUDPaint", "ThirdParty_WorldLabels")


-----------------------------------------------------------------------
print(("\n== ИТОГ: %d ok, %d FAIL =="):format(pass, fail))
if fail > 0 then os.exit(1) end
