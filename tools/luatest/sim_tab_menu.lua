--[[--------------------------------------------------------------------
    sim_tab_menu — заказ владельца 19.08: TAB-меню шире, пинг видно,
    аватарки Steam, оформление в стиле GRM.

    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_tab_menu.lua
----------------------------------------------------------------------]]
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

local s = read("lua/autorun/sh_grm_tab_menu.lua")

print("\n=== 1. РАЗМЕР ===")
ok(s:find("local W = math.Clamp(math.floor(SW * 0.92), 1100, 1720)", 1, true) ~= nil,
    "ширина считается от экрана, а не фиксированные 960")
ok(s:find("local H = math.Clamp(math.floor(SH * 0.86), 640, 1000)", 1, true) ~= nil, "высота тоже")
ok(s:find("local detailW  = math.Clamp(math.floor(W * 0.28), 320, 460)", 1, true) ~= nil,
    "панель деталей масштабируется вместе с окном")
ok(s:find("local dw = math.max(260, pw - 8)", 1, true) ~= nil, "карточка игрока занимает всю панель")

print("\n=== 2. ПИНГ ВИДНО ===")
ok(s:find('draw.SimpleText("ПИНГ", "GRMT_Small", w - 24', 1, true) ~= nil, "у пинга своя колонка в шапке")
ok(s:find('draw.SimpleText(ping .. " ms", "GRMT_Small", w - 30', 1, true) ~= nil,
    "пинг рисуется в своей колонке справа, а не под именем")
ok(s:find("draw.RoundedBox(4, w - 86, h / 2 - 11, 62, 22", 1, true) ~= nil, "под пинг выделена плашка")
ok(s:find("local lit = (i == 1) or (i == 2 and ping < 150) or (i == 3 and ping < 80)", 1, true) ~= nil,
    "рядом индикатор качества связи из трёх полос")
ok(s:find("self:SetTextColor(value < 80 and C.GREEN or value < 150 and C.GOLD or C.RED)", 1, true) ~= nil,
    "в карточке пинг тоже цветной (и обновляется вживую)")

print("\n=== 3. АВАТАРКИ STEAM ===")
ok(s:find('local avatar = vgui.Create("AvatarImage", row)', 1, true) ~= nil, "аватар в строке списка")
ok(s:find('avatar:SetSteamID(tostring(pd.sid64), 64)', 1, true) ~= nil, "аватар берётся по SteamID64")
ok(s:find('local bigAvatar = vgui.Create("AvatarImage", sp)', 1, true) ~= nil, "крупный аватар в карточке игрока")
ok(s:find('bigAvatar:SetSteamID(tostring(pd.sid64), 128)', 1, true) ~= nil, "в карточке аватар большего разрешения")
ok(s:find("avatar:SetMouseInputEnabled(false)", 1, true) ~= nil, "аватар не перехватывает клик по строке")
ok(s:find('pd.sid64 ~= "0"', 1, true) ~= nil, "у ботов без SteamID аватар не запрашивается")

print("\n=== 4. СТИЛЬ GRM ===")
ok(s:find("BG       = Color(16,  20,  28,  252)", 1, true) ~= nil, "фон как в /factions и /admin")
ok(s:find("GOLD     = Color(245, 195, 65,  255)", 1, true) ~= nil, "золото GRM")
ok(s:find('titleLbl:SetText("GRM · ИГРОКИ НА СЕРВЕРЕ")', 1, true) ~= nil, "заголовок в общем стиле")
ok(s:find("titleLbl:SetTextColor(C.GOLD)", 1, true) ~= nil, "заголовок золотой")
ok(s:find("draw.RoundedBoxEx(8, 0, 0, w, 44, C.DARK, true, true, false, false)", 1, true) ~= nil,
    "шапка окна скруглена как у остальных меню GRM")
ok(s:find("local ROW_H = 56", 1, true) ~= nil, "строки выше — помещается аватар и две подписи")
ok(s:find('draw.SimpleText("ОРГАНИЗАЦИЯ"', 1, true) ~= nil, "организация вынесена в отдельную колонку")
ok(s:find('surface.DrawOutlinedRect(11, (h - 40) / 2 - 1, 42, 42, 1)', 1, true) ~= nil,
    "аватар обведён рамкой цвета ранга")

print("\n=== 5. ЖИВЫЕ ЗНАЧЕНИЯ, ПОКА ДЕРЖИШЬ TAB (заказ 21.08) ===")
ok(s:find("local function livePing(pd)", 1, true) ~= nil, "пинг берётся у живой entity, а не из снимка")
ok(s:find("local ping = livePing(pd)", 1, true) ~= nil, "строка списка рисует живой пинг каждый кадр")
ok(s:find("pingLbl.Think = function(self)", 1, true) ~= nil, "в карточке игрока пинг обновляется сам")
ok(s:find("self._next = CurTime() + 0.5", 1, true) ~= nil, "обновление throttled — два раза в секунду")
ok(s:find("local function playerBySID(sid64)", 1, true) ~= nil, "поиск игрока по SteamID кэшируется")
ok(s:find("(CurTime() - _plyBySIDAt) > 1", 1, true) ~= nil,
    "кэш живёт секунду — player.GetAll() не зовётся в отрисовке")
ok(s:find("local function rosterKey(data)", 1, true) ~= nil, "состав игроков сравнивается по ключу")
ok(s:find("if sameRoster then", 1, true) ~= nil,
    "при неизменном составе поля обновляются на месте, без пересборки списка")
ok(s:find("if not sameRoster and IsValid(_frame)", 1, true) ~= nil,
    "пересборка (и сброс прокрутки) только когда кто-то зашёл или вышел")
ok(s:find("GRM.TabMenu.RefreshInterval = 2", 1, true) ~= nil,
    "снимок с сервера приходит чаще — баланс и группы тоже свежие")

print(("\nTAB MENU: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
