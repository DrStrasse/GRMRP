--[[--------------------------------------------------------------------
    sim_menu_showcase — витрина персонажа в меню паузы. Контракт сверен
    с ДВИЖКОВЫМ исходником базового DModelPanel
    (garrysmod/lua/vgui/dmodelpanel.lua, официальный репозиторий):
    у панели есть SetModel/GetModel/GetEntity/SetFOV/SetCamPos/SetLookAt/
    SetAnimated/SetAnimSpeed/SetAmbientLight — и НЕТ SetSkin, SetBodygroup,
    GetModelEntity, SetMouseInputEnabled и авторазмера Layout. Внешность —
    только через GetEntity() (как в движковом GenerateExample), кадр —
    расчётный. Прошлые «под guard вызовы» несуществующих методов молча
    пропускались: «бодигруппы так и не появились», «персонаж мелкий»
    (владелец, 03.09 вечер-6/7).
----------------------------------------------------------------------]]
local fails, total = 0, 0
local function check(name, cond, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "   " .. tostring(extra or "")) end
end
local f = assert(io.open("gamemodes/grmrp/gamemode/modules/ui/cl_grmrp_menu.lua", "rb"))
local h = f:read("*a") f:close()
local function has(n) return h:find(n, 1, true) ~= nil end

print("\n=== 1. НИКАКИХ ФАНТОМНЫХ МЕТОДОВ ПАНЕЛИ ===")
for _, fake in ipairs({ "m:SetSkin(", "m:SetBodygroup(", ":GetModelEntity(",
    ":SetMouseInputEnabled(", ":SetModelScale(" }) do
    check("нет вызова несуществующего: " .. fake, not has(fake))
end

print("\n=== 2. ВНЕШНОСТЬ ЧЕРЕЗ GetEntity (движковый канон) ===")
check("skin/groups пишутся на m:GetEntity()", has("local e = m.GetEntity and m:GetEntity()"))
check("валидность entity — страж", has("if not IsValid(e) then return end"))
check("скин: e:SetSkin(sk)", has("e:SetSkin(sk)"))
check("бодигруппы: e:SetBodygroup(idx, val)", has("e:SetBodygroup(idx, val)"))
check("индекс группы — tonumber(bg.id)", has("tonumber(bg.id)"))
check("чтение значения с живого игрока", has("ply:GetBodygroup(idx)"))
check("GetModel для сверки смены модели", has("mm:GetModel()"))

print("\n=== 3. КАДР: РАСЧЁТНАЯ КАМЕРА (авторазмера у панели нет) ===")
check("FOV портретный задан", has("m:SetFOV(fov)"))
check("дистанция из высоты модели и fill-коэффициента",
    has("(hh / 0.92) / (2 * math.tan(math.rad(fov * 0.5)))"))
check("camPos ставится явно (дефолт 50,50,50 мелок)", has("m:SetCamPos(Vector(-d * 0.71"))
check("взгляд — в середину роста", has("m:SetLookAt(Vector(0, 0, hh * 0.5))"))
check("подсветка поднята (тёмный ambient дефолта)", has("m:SetAmbientLight(Color(120, 124, 132))"))
check("OBB-рост застрахован clamp", has("math.Clamp((mx.z or 72) - (mn.z or 0), 48, 200)"))

print("\n=== 4. ПОРЯДОК И ЖИВОСТЬ ===")
do
    local i1 = h:find("local function newModel", 1, true)
    local i2 = h:find("\n    end", i1, true)
    local body = h:sub(i1, i2)
    local ia = body:find("m:SetAnimated(true)", 1, true)
    local ib = body:find("applyLook(m)", 1, true)
    check("внешность применяется ПОСЛЕ SetAnimated", ia ~= nil and ib ~= nil and ib > ia)
end
check("живой догон в UpdateStats (без пересъёмки)", has("applySkinGroups(mm)"))
check("смена модели — полная пересъёмка", has("applyLook(mm) else"))

print("\n=== 5. РАЗМЕР И ОТТИСК ===")
check("окно модели не меньше 240px", has("240, 440"))
check("карточка раздвинута до 430px", has("320, 430"))
check("оттиск сборки вечер-11", has("вечер-11 (03.09)"))

print("\n=== 3. ДЕНЬГИ: КАРТОЧКА + КАССЕТЫ (вечер-11) ===")
check("карточка: «На счёту» рядом с «Деньги»", has('statRow(card, statsBase + 84, "На счёту")'))
check("карточка: баланс с фолбеком на аддонский GRM.PlayerBalance",
    has("GRM.PlayerBalance"))
check("карточка: GRMRP.Economy через pcall (нет — не креш)", has("pcall(eco, pl)"))
check("семь строк статов в карточке", has("statsBase + 7 * 28 + 18"))

print("\n=== 2. СТАРЫЕ ОКНА, БЛЮР, ESC (вечер-10) ===")
check("блюр кадра за меню (Derma_DrawBackgroundBlur)", has("Derma_DrawBackgroundBlur(s, s.animStart)"))
check("настройки — диалог движка через очередь", has('Menu.OpenGameuiWith("OpenOptionsDialog")'))
check("сетевая игра — старое окно браузера движка", has('Menu.OpenGameuiWith("OpenServerBrowser")'))
check("мастерская — стандартное меню, не внешняя URL", has("Menu.OpenGameuiWith(nil)"))
check("gui.OpenURL из меню вырезан", not has("gui.OpenURL"))
check("подавления на фиксированные 30 секунд нет", not has("CurTime() + 30"))
check("сессия gameui помечается своей", has("Menu.ownsGameui = true"))
check("команда ждёт реального menu-состояния", has("if Menu.pendingCmd then"))
check("ESC сперва отдаёт верхний слой (ввод/история чата)",
    has("GRMRPChat.INPUT_OPEN or GRMRPChat.HIST_OPEN"))
check("фолбек-копия групп 1..8 для кривых списков", has("ply:GetBodygroup(i)"))

print(("\nMENU SHOWCASE: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
