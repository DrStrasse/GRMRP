--[[--------------------------------------------------------------------
    sim_perms_scroll_curfew — две правки по заказу владельца:
      1) панели доступов больше не прыгают вверх при клике по чекбоксу;
      2) меню комендантского часа (/kom_hour) с кнопками, ползунком,
         причиной и серверной валидацией состояния.

    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_perms_scroll_curfew.lua
----------------------------------------------------------------------]]
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

local perms   = read("lua/autorun/client/cl_grm_faction_perms_ui.lua")
local unified = read("lua/autorun/client/cl_grm_factions_unified_ui.lua")
local fixes   = read("lua/autorun/sh_faction_fixes.lua")
local menu    = read("lua/autorun/client/cl_grm_curfew_menu.lua")

print("\n=== 1. ПАНЕЛЬ ДОСТУПОВ ПО РОЛЯМ: НЕТ ПРЫЖКА СКРОЛЛА ===")
ok(perms:find("v3.0.0", 1, true) ~= nil, "версия панели 3.0.0")
ok(perms:find("local function syncValues", 1, true) ~= nil,
    "значения чекбоксов обновляются точечно, без пересборки")
ok(perms:find("local function structureSignature", 1, true) ~= nil,
    "полная пересборка только при смене состава ролей/доступов")
ok(perms:find("if ui.applying then return end", 1, true) ~= nil,
    "программная установка значения не шлёт пакет обратно (нет цикла)")
ok(perms:find("scroll.VBar:SetScroll(prevScroll)", 1, true) ~= nil,
    "позиция прокрутки восстанавливается даже при вынужденной пересборке")
ok(perms:find("PERMS.Data[factionName][role][permID] = v or nil", 1, true) ~= nil,
    "клик применяется оптимистично — галочка не мигает в ожидании сервера")
ok(perms:find("hook.Remove(\"GRM_FPermDataUpdated\"", 1, true) ~= nil,
    "хук снимается при закрытии окна (нет утечки обработчика)")
ok(perms:find("local catCache", 1, true) ~= nil,
    "категории доступов считаются один раз, а не на каждую роль")

print("\n=== 2. ВКЛАДКА «ДОСТУПЫ И СВЯЗЬ» В /fmenu ===")
ok(unified:find("local function findScroll", 1, true) ~= nil, "поиск скролла для сохранения позиции")
ok(unified:find("newScroll.VBar:SetScroll(keep)", 1, true) ~= nil,
    "refreshView возвращает прокрутку на место")
local accStart = unified:find("local function buildAccessTab", 1, true)
local accEnd = unified:find("-- ════════════", accStart + 10)
local accSeg = unified:sub(accStart, accEnd)
ok(accSeg:find("addAccessToggle", 1, true) ~= nil, "вкладка доступов найдена")
ok(select(2, accSeg:gsub(", refreshView%)", "")) == 0,
    "тумблеры доступов больше НЕ пересобирают вкладку целиком")

print("\n=== 3. СТАРАЯ ВКЛАДКА ДОСТУПОВ (sh_faction_fixes) ===")
ok(fixes:find("local keepScroll = 0", 1, true) ~= nil, "пересборка запоминает прокрутку")
ok(fixes:find("scroll.VBar:SetScroll(keepScroll)", 1, true) ~= nil, "и возвращает её после Clear")

print("\n=== 4. СЕРВЕР КОМЕНДАНТСКОГО ЧАСА ===")
ok(fixes:find('local NET_CURFEW_MENU        = "GRM_Curfew_Menu"', 1, true) ~= nil, "канал состояния меню")
ok(fixes:find('local NET_CURFEW_ACT         = "GRM_Curfew_Act"', 1, true) ~= nil, "канал действий меню")
ok(fixes:find("util.AddNetworkString(NET_CURFEW_MENU)", 1, true) ~= nil, "каналы зарегистрированы")
ok(fixes:find("local function sendCurfewState", 1, true) ~= nil, "сервер отдаёт полное состояние")
ok(fixes:find("net.WriteBool(can == true)", 1, true) ~= nil, "в состоянии есть флаг доступа игрока")
ok(fixes:find("CurfewReason", 1, true) ~= nil and fixes:find("CurfewStartedAt", 1, true) ~= nil,
    "причина и время старта хранятся в состоянии")
ok(fixes:find("startCurfew(ply, minutes * 60, reason)", 1, true) ~= nil, "объявление принимает причину")
ok(fixes:find('if CurfewActive then\n                sendExtResult(ply, false, "Комендантский час уже идёт")', 1, true) ~= nil,
    "повторное объявление отклоняется сервером")
ok(fixes:find('if not CurfewActive then\n                sendExtResult(ply, false, "Комендантский час не активен")', 1, true) ~= nil,
    "остановка неактивного режима отклоняется сервером")
ok(fixes:find('GRM.Net.Guard(ply, "curfew.act"', 1, true) ~= nil, "действия под Net Guard (лимит частоты)")
ok(fixes:find('GRM.Audit.Write("curfew", "start"', 1, true) ~= nil, "объявление пишется в аудит")
ok(fixes:find("if IsValid(p) and p._grmCurfewMenuOpen then sendCurfewState(p) end", 1, true) ~= nil,
    "открытые меню обновляются push-ом, без опроса по таймеру")
ok(fixes:find("local handleCurfewChat", 1, true) ~= nil and fixes:find("handleCurfewChat = function", 1, true) ~= nil,
    "единый обработчик чат-команды с форвард-декларацией (иначе падал как глобал)")
ok(fixes:find('hook.Add("PlayerSay", "FactionsExt_CurfewCommands"', 1, true) ~= nil,
    "команда работает через боевой PlayerSay + реестр библиотеки (веч.-18)")
ok(fixes:find('string.sub(rawTrim, 1, 13) == "/комчас"', 1, true) ~= nil, "русский алиас /комчас")
ok(fixes:find("if num and num > 0 and num <= 120 then duration = num * 60", 1, true) ~= nil,
    "/kom_hour 15 = 15 минут, старый формат в секундах сохранён")

print("\n=== 5. КЛИЕНТСКОЕ МЕНЮ В СТИЛЕ GRM ===")
ok(menu:find("GRMCurfew_Title", 1, true) ~= nil, "свои шрифты GRM")
ok(menu:find("bg     = Color(16, 20, 28, 252)", 1, true) ~= nil, "палитра как в остальных меню сборки")
ok(menu:find("ОБЪЯВИТЬ КОМЕНДАНТСКИЙ ЧАС", 1, true) ~= nil, "кнопка объявления")
ok(menu:find('mkButton(actions, "ОСТАНОВИТЬ"', 1, true) ~= nil, "кнопка остановки")
ok(menu:find("btnStop.Enabled = st.canControl and st.active", 1, true) ~= nil,
    "«Остановить» активна ТОЛЬКО когда ком.час идёт")
ok(menu:find("btnStart.Enabled = st.canControl and not st.active", 1, true) ~= nil,
    "«Объявить» неактивна, пока режим уже идёт")
ok(menu:find('DNumSlider', 1, true) ~= nil and menu:find("Минут", 1, true) ~= nil, "ползунок длительности")
ok(menu:find("for _, m in ipairs({ 5, 10, 15, 30, 60, 120 })", 1, true) ~= nil, "быстрые пресеты времени")
ok(menu:find("DTextEntry", 1, true) ~= nil and menu:find("ПРИЧИНА ОБЪЯВЛЕНИЯ", 1, true) ~= nil,
    "строка ввода причины")
ok(menu:find("140 символов", 1, true) ~= nil, "счётчик длины причины")
ok(menu:find("if sec ~= s.CachedSec then", 1, true) ~= nil,
    "строка таймера пересобирается раз в секунду, а не каждый кадр")
ok(menu:find("body._nextCheck = CurTime() + 0.25", 1, true) ~= nil,
    "валидация кнопок троттлится (4 раза в секунду)")
ok(menu:find("net.Start(NET_MENU)", 1, true) ~= nil and menu:find("timer.Create", 1, true) == nil,
    "меню не опрашивает сервер по таймеру")
ok(menu:find('concommand.Add("grm_curfew"', 1, true) ~= nil, "есть консольная команда")
ok(menu:find("GRM.Sound.UI", 1, true) ~= nil, "звуки через общий слой GRM.Sound")
ok(menu:find('net.WriteString("close")', 1, true) ~= nil, "закрытие меню снимает флаг на сервере")


print("\n=== 6. ЖИВОЙ ПРОГОН ЧАТ-КОМАНДЫ (регресс краша в EasyChat) ===")
--[[ Владелец поймал в бою:
       attempt to call global 'handleCurfewChat' (a nil value)
     Причина: хук PlayerSayTransform создавался ВЫШЕ объявления локальной
     функции, поэтому замыкание читало глобал. Здесь мы реально поднимаем
     модуль в моке GMod и дёргаем оба хука — включая постороннее сообщение
     «!noclip», на котором всё и упало. ]]
local stub = dofile("tools/luatest/lib_gmod_stub.lua")
stub.install()
stub.reset()
_G.CreateConVar = function() return { GetInt = function() return 0 end, GetFloat = function() return 0 end,
    GetBool = function() return false end, GetString = function() return "" end } end
_G.GetConVar = _G.CreateConVar
_G.bit = { bor = function(a) return a end }
_G.FCVAR_ARCHIVE, _G.FCVAR_REPLICATED = 1, 2
_G.HUD_PRINTTALK, _G.HUD_PRINTCENTER, _G.HUD_PRINTCONSOLE = 3, 4, 2
_G.Factions, _G.FactionsData = {}, {}

local loaded, loadErr = stub.loadModule("lua/autorun/sh_faction_fixes.lua")
ok(loaded, "модуль фракций поднялся в моке", loadErr)

local transform = (stub.hooks["PlayerSay"] or {})["FactionsExt_CurfewCommands"]
local playerSay = (stub.hooks["PlayerSay"] or {})["FactionsExt_Commands"]
ok(isfunction(transform), "владелец ком.часа зарегистрирован (боевой PlayerSay)")
ok(isfunction(playerSay), "хук PlayerSay зарегистрирован")

if isfunction(transform) and isfunction(playerSay) then
    local ply = stub.makeEntity({ class = "player", isPlayer = true })
    local cases = { "/kom_hour", "/комчас", "/kom_hour off", "/kom_hour 15", "!noclip", "привет" }
    local allOK, firstErr = true, nil
    local rET, rES
    for _, text in ipairs(cases) do
        local okT, errT = pcall(function() rET = transform(ply, text) end)
        local okS, errS = pcall(function() rES = playerSay(ply, text) end)
        if not okT or not okS then allOK = false firstErr = firstErr or tostring(errT or errS) end
    end
    ok(allOK, "ни одна форма команды и ни одно постороннее сообщение не падают", firstErr)

    local retC
    pcall(function() retC = transform(ply, "/kom_hour") end)
    ok(retC == "", 'команда ком.часа съедена (return "")')

    local other = { "!noclip" }
    pcall(transform, ply, other)
    ok(other.SkipPlayerSay ~= true and other[1] == "!noclip", "чужие сообщения проходят в чат нетронутыми")
end

print(("\nPERMS SCROLL + CURFEW: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
