-- sim_launderer_menu.lua — функциональный тест КЛИЕНТСКОГО меню отмывщика
-- (находка 179s: «выбор фракции не сохраняется, нет реакции на изменение чисел»)
--
-- Грузит РЕАЛЬНЫЙ cl_init.lua с моками vgui/net/surface и проверяет полный
-- цикл: открыть меню → отметить/снять фракции (клик по строке!) → изменить
-- числа (GetValue) → «СОХРАНИТЬ НАСТРОЙКИ» → payload net.Start("GRM_Heist_Action")
-- с action="config_full", minP, goal, selected.
local pass, fail = 0, 0
local function ok(v, n) if v then pass = pass + 1 print("  ok  " .. n) else fail = fail + 1 print("  FAIL " .. n) end end

-- ── моки глобалов ──
SERVER = nil
CLIENT = true
istable = function(v) return type(v) == "table" end
isstring = function(v) return type(v) == "string" end
IsValid = function(e) return e and e.__valid ~= false end
string.Trim = string.Trim or function(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
RENDERGROUP_BOTH = 1
color_white = { r = 255, g = 255, b = 255 }
Color = function(r, g, b, a) return { r = r or 0, g = g or 0, b = b or 0, a = a or 255 } end
surface = { CreateFont = function() end }
draw = { RoundedBox = function() end, SimpleText = function() end }
cam = { Start3D2D = function() end, End3D2D = function() end }
LocalPlayer = function() return nil end
CurTime = function() return 1000 end
Angle = function(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
EyeAngles = function() return Angle(0, 0, 0) end
TEXT_ALIGN_CENTER = 1
TEXT_ALIGN_LEFT = 2

-- ── мок vgui ──
TOP = "TOP"
BOTTOM = "BOTTOM"
FILL = "FILL"
local allWidgets = {}
local function mkWidget(type, parent)
  local w = {
    _type = type, _parent = parent, _text = "", _value = nil,
    _min = 0, _max = 100, _decimals = 0, _tall = 0,
    Paint = nil, DoClick = nil, OnValueChanged = nil,
  }
  w.SetTitle = function() end
  w.SetSize = function(_, ww, hh) w._w, w._h = ww, hh end
  w.GetWide = function() return w._w or 600 end
  w.GetTall = function() return w._tall end
  w.Center = function() end
  w.MakePopup = function() end
  w.Remove = function() end
  w.Dock = function(_, d) w._dock = d end
  w.DockMargin = function() end
  w.SetTall = function(_, t) w._tall = t end
  w.SetPaintBackground = function() end
  w.SetPos = function(_, x, y) w._x, w._y = x, y end
  w.SetFont = function() end
  w.SetTextColor = function() end
  w.SetText = function(_, t) w._text = tostring(t or "") end
  w.SetWrap = function() end
  w.SetMin = function(_, m) w._min = m end
  w.SetMax = function(_, m) w._max = m end
  w.SetDecimals = function(_, d) w._decimals = d end
  w.SetValue = function(_, v) w._value = v end
  w.GetValue = function() return w._value or 0 end
  w.IsHovered = function() return false end
  allWidgets[#allWidgets + 1] = w
  return w
end
vgui = { Create = function(type, parent) return mkWidget(type, parent) end }

local function findWidget(pred)
  for _, w in ipairs(allWidgets) do if pred(w) then return w end end
  return nil
end

-- ── мок net ──
local H = { netrecv = {} }
local netLog = {}
net = {
  Start = function(name) netLog.start = name end,
  WriteEntity = function(e) netLog.ent = e end,
  WriteString = function(s) netLog.str = s end,
  WriteUInt = function(v, b) netLog.uint = netLog.uint or {} netLog.uint[#netLog.uint + 1] = { v, b } end,
  WriteTable = function(t) netLog.tbls = netLog.tbls or {} netLog.tbls[#netLog.tbls + 1] = t end,
  SendToServer = function() netLog.sent = true end,
  Receive = function(n, fn) H.netrecv[n] = fn end,
  ReadEntity = function() return testEnt end,
  ReadTable = function() return menuData or {} end,
  ReadString = function() return "" end,
  ReadBool = function() return false end,
  ReadUInt = function() return 0 end,
}
local function resetNet()
  netLog.start = nil; netLog.ent = nil; netLog.str = nil
  netLog.uint = nil; netLog.tbls = nil; netLog.sent = nil
end

-- ── загрузка реальных файлов ──
ENT = {}
include = function(p) dofile("lua/entities/grm_money_launderer/" .. tostring(p)) end
dofile("lua/entities/grm_money_launderer/shared.lua")
dofile("lua/entities/grm_money_launderer/cl_init.lua")

-- ── открытие меню ──
testEnt = { __valid = true }
menuData = {
  enabled = true, eventActive = false,
  minParticipants = 2, participantCount = 0, goalMoney = 500000, moneyHeld = 0,
  allowedFactions = "Mafia", eventEndsAt = 0, isParticipant = false,
  canManage = true, myFaction = "Mafia", factionAllowed = true,
  hasTarget = false, targetPos = nil,
  factionsList = { "Mafia", "Polizei" },
  cooldownLeft = 0, cooldownDuration = 1800,
  govFactions = "Polizei", govKills = { Polizei = 2 },
}
H.netrecv["GRM_Heist_Open"]()

local frame = findWidget(function(w) return w._type == "DFrame" end)
ok(frame ~= nil, "меню: DFrame создан (GRM_Heist_Open)")
-- Находка 179u/179x/179y: кнопка сохранения в нижней панели (SAVE_BAR,
-- Dock BOTTOM) — всегда видна; КОМПАКТНАЯ 170×26, по центру
local saveBar = findWidget(function(w) return w._btnText == "SAVE_BAR" end)
ok(saveBar ~= nil, "меню: панель SAVE_BAR создана (находка 179u)")
ok(saveBar ~= nil and saveBar._dock == "BOTTOM" and saveBar._tall == 40, "меню: SAVE_BAR внизу (Dock BOTTOM, tall 40)")
local saveBtn = findWidget(function(w) return w._type == "DButton" and w._btnText == "💾 СОХРАНИТЬ НАСТРОЙКИ" and w._parent == saveBar end)
ok(saveBtn ~= nil, "меню: кнопка СОХРАНИТЬ НАСТРОЙКИ внутри SAVE_BAR (находка 179u)")
ok(saveBtn ~= nil and saveBtn._w == 170 and saveBtn._h == 26, "меню: кнопка КОМПАКТНАЯ 170x26 (находка 179y)")
saveBar:PerformLayout()
ok(saveBtn ~= nil and saveBtn._x == 215 and saveBtn._y == 7, "меню: кнопка отцентрована в панели (находка 179y)")
-- Находка 180h: чеклист гос.структур
local govRowP = findWidget(function(w) return w._type == "DButton" and w._govName == "Polizei" end)
ok(govRowP ~= nil, "меню: строка гос.структуры Polizei создана (находка 180h)")
local govRowM = findWidget(function(w) return w._type == "DButton" and w._govName == "Mafia" end)
ok(govRowM ~= nil, "меню: строка гос.структуры Mafia создана (находка 180h)")
-- Polizei отмечена из данных (govFactions="Polizei"), Mafia нет
govRowP.DoClick() -- снять Polizei
govRowM.DoClick() -- отметить Mafia
resetNet()
saveBtn.DoClick()
ok(netLog.tbls and netLog.tbls[2] and #netLog.tbls[2] == 1 and netLog.tbls[2][1] == "Mafia", "меню: гос.структуры сохранены (Mafia, находка 180h)")
local minWang = findWidget(function(w) return w._type == "DNumberWang" and w._field == "min" end)
local goalWang = findWidget(function(w) return w._type == "DNumberWang" and w._field == "goal" end)
ok(minWang ~= nil and goalWang ~= nil, "меню: поля DNumberWang (минимум/цель)")
ok(minWang._value == 2 and goalWang._value == 500000, "меню: начальные значения 2 / 500000")
local mafiaRow = findWidget(function(w) return w._type == "DButton" and w._facName == "Mafia" end)
local polizeiRow = findWidget(function(w) return w._type == "DButton" and w._facName == "Polizei" end)
ok(mafiaRow ~= nil and polizeiRow ~= nil, "меню: строки фракций Mafia и Polizei созданы")

-- ── 1. Сохранить без изменений: Mafia отмечена из данных ──
resetNet()
saveBtn.DoClick()
ok(netLog.start == "GRM_Heist_Action" and netLog.str == "config_full" and netLog.sent == true, "сохранение: net.Start GRM_Heist_Action, action config_full")
ok(netLog.uint and netLog.uint[1][1] == 2 and netLog.uint[1][2] == 16, "сохранение: minP=2 (16 бит)")
ok(netLog.uint and netLog.uint[2][1] == 500000 and netLog.uint[2][2] == 32, "сохранение: goal=500000 (32 бита)")
local cdWang = findWidget(function(w) return w._type == "DNumberWang" and w._field == "cd" end)
ok(cdWang ~= nil and cdWang._value == 30, "меню: поле КД (мин) со значением 30 (находка 180c)")
ok(netLog.uint and netLog.uint[3] and netLog.uint[3][1] == 30 and netLog.uint[3][2] == 16, "сохранение: КД 30 мин отправлено (16 бит, находка 180c)")
ok(netLog.tbls and netLog.tbls[1] and #netLog.tbls[1] == 1 and netLog.tbls[1][1] == "Mafia", "сохранение: выбрана Mafia (из данных)")

-- ── 2. Клик по строке Polizei → добавится ──
polizeiRow.DoClick()
resetNet()
saveBtn.DoClick()
ok(netLog.tbls and netLog.tbls[1] and #netLog.tbls[1] == 2 and netLog.tbls[1][1] == "Mafia" and netLog.tbls[1][2] == "Polizei", "клик по строке Polizei → в выборе обе (находка 179s)")

-- ── 3. Клик по Mafia → снимается ──
mafiaRow.DoClick()
resetNet()
saveBtn.DoClick()
ok(netLog.tbls and netLog.tbls[1] and #netLog.tbls[1] == 1 and netLog.tbls[1][1] == "Polizei", "клик по Mafia → снята, осталась Polizei")

-- ── 4. Снять всё → пустой список (любые) ──
polizeiRow.DoClick()
resetNet()
saveBtn.DoClick()
ok(netLog.tbls and netLog.tbls[1] and #netLog.tbls[1] == 0, "пустой выбор → пустой список (любые фракции)")

-- ── 5. Числа: изменение в полях видно при сохранении (GetValue) ──
minWang._value = 7
goalWang._value = 600000
mafiaRow.DoClick()
resetNet()
saveBtn.DoClick()
ok(netLog.uint and netLog.uint[1][1] == 7 and netLog.uint[1][2] == 16, "числа: minP=7 из поля (GetValue, находка 179s)")
ok(netLog.uint and netLog.uint[2][1] == 600000 and netLog.uint[2][2] == 32, "числа: goal=600000 из поля (GetValue, находка 179s)")
ok(netLog.tbls and netLog.tbls[1] and #netLog.tbls[1] == 1 and netLog.tbls[1][1] == "Mafia", "числа: Mafia всё ещё в выборе")

-- ── 6. Переоткрытие меню с новыми данными сервера ──
-- (в проде старое окно удаляется menuFrame:Remove() — имитируем сбросом реестра)
allWidgets = {}
menuData = {
  enabled = true, eventActive = false,
  minParticipants = 7, participantCount = 0, goalMoney = 600000, moneyHeld = 0,
  allowedFactions = "Polizei", eventEndsAt = 0, isParticipant = false,
  canManage = true, myFaction = "Polizei", factionAllowed = true,
  hasTarget = false, targetPos = nil,
  factionsList = { "Mafia", "Polizei" },
}
H.netrecv["GRM_Heist_Open"]()
local minWang2 = findWidget(function(w) return w._type == "DNumberWang" and w._field == "min" end)
local goalWang2 = findWidget(function(w) return w._type == "DNumberWang" and w._field == "goal" end)
ok(minWang2 and minWang2._value == 7 and goalWang2 and goalWang2._value == 600000, "переоткрытие: значения 7/600000 из данных сервера")
local cdWang2 = findWidget(function(w) return w._type == "DNumberWang" and w._field == "cd" end)
ok(cdWang2 ~= nil and cdWang2._value == 30, "переоткрытие: поле КД на месте (находка 180c)")
resetNet()
saveBtn = findWidget(function(w) return w._type == "DButton" and w._btnText == "💾 СОХРАНИТЬ НАСТРОЙКИ" end)
saveBtn.DoClick()
ok(netLog.tbls and netLog.tbls[1] and #netLog.tbls[1] == 1 and netLog.tbls[1][1] == "Polizei", "переоткрытие: выбрана Polizei (сохранённая на сервере)")

-- ══════════════ 7. КД АКТИВЕН (находка 180c) ══════════════
allWidgets = {}
menuData = {
  enabled = true, eventActive = false,
  minParticipants = 2, participantCount = 0, goalMoney = 500000, moneyHeld = 0,
  allowedFactions = "", eventEndsAt = 0, isParticipant = false,
  canManage = false, myFaction = "Mafia", factionAllowed = true,
  hasTarget = false, targetPos = nil,
  factionsList = { "Mafia", "Polizei" },
  cooldownLeft = 120, cooldownDuration = 1800,
}
H.netrecv["GRM_Heist_Open"]()
local cdBlocked = findWidget(function(w) return w._type == "DButton" and w._btnText and w._btnText:find("ОГРАБЛЕНИЕ НА ПЕРЕЗАГРУЗКЕ", 1, true) end)
ok(cdBlocked ~= nil, "КД: заблокированная кнопка «ПЕРЕЗАГРУЗКА» видна (находка 180c)")
local takeBtn = findWidget(function(w) return w._type == "DButton" and w._btnText == "ВЗЯТЬ ЗАДАНИЕ НА ОГРАБЛЕНИЕ" end)
ok(takeBtn == nil, "КД: кнопки «ВЗЯТЬ ЗАДАНИЕ» НЕТ (находка 180c)")
ok(cdBlocked ~= nil and cdBlocked._btnText:find("02:00", 1, true) ~= nil, "КД: на кнопке таймер 02:00 (находка 180c)")

print(string.format("sim_launderer_menu: %d ok, %d fail", pass, fail))
os.exit(fail > 0 and 1 or 0)
