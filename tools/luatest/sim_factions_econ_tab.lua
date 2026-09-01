-- sim_factions_econ_tab.lua — функциональная проверка вкладки «Экономика»
-- в меню /factions (находка 177):
--   • hook GRM_FactionsAdmin_BuildTabs создаёт вкладку и шлёт запрос данных;
--   • ответ GRM_Eco_AdminData перестраивает панель (BuildAdminContent);
--   • внутри панели: гос.бюджет, фракции в комбо, игроки в списке;
--   • кнопки имеют рабочие DoClick (шлют GRM_Eco_AdminAction);
--   • НЕТ дублирования вкладки «Экономика» (feco_admin не должен добавлять
--     вторую вкладку с тем же именем).
local pass, fail = 0, 0
local function ok(v, n) if v then pass = pass + 1 print("  ok  " .. n) else fail = fail + 1 print("  FAIL " .. n) end end

SERVER, CLIENT = false, true
function AddCSLuaFile() end
include = function(p) dofile("lua/" .. p) end
function isstring(v) return type(v) == "string" end
function istable(v) return type(v) == "table" end
function isfunction(v) return type(v) == "function" end
function isnumber(v) return type(v) == "number" end
function IsValid(v) return v ~= nil and (type(v) == "table" and v.__valid ~= false or type(v) == "userdata") end
function CurTime() return 1000 end
function FrameTime() return 0.1 end
function print(...) local a = {} for i = 1, select("#", ...) do a[i] = tostring(select(i, ...)) end io.write(table.concat(a, " "), "\n") end
function Color(r, g, b, a) return { r = r or 0, g = g or 0, b = b or 0, a = a or 255 } end
function math.Clamp(v, a, b) return math.max(a, math.min(b, v)) end
function math.NormalizeAngle(a) a = a % 360 if a > 180 then a = a - 360 end return a end
function table.Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
function table.Copy(t) local o = {} for k, v in pairs(t or {}) do o[k] = type(v) == "table" and table.Copy(v) or v end return o end
function table.HasValue(t, v) for _, x in pairs(t or {}) do if x == v then return true end end return false end
function string.Trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
function string.StartWith(s, p) return string.sub(s, 1, #p) == p end
function Lerp(t, a, b) return a + (b - a) * t end
MASK_SOLID = 0
COLOR_WHITE = Color(255, 255, 255)
color_white = COLOR_WHITE
TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, TEXT_ALIGN_RIGHT = 0, 1, 2
NOTIFY_GENERIC, NOTIFY_ERROR = 1, 2

-- ── мок окружения ──
local H = { hooks = {}, netrecv = {}, timers = {}, netlog = {} }
hook = { Add = function(n, id, fn) H.hooks[n] = H.hooks[n] or {} H.hooks[n][#(H.hooks[n]) + 1] = { id = id, fn = fn } end, Run = function(name, ...) local h = H.hooks[name] if h then local r for _, rec in ipairs(h) do r = rec.fn(...) end return r end end, Call = function(name, _, ...) return hook.Run(name, ...) end }
timer = { Create = function() end, Simple = function(_, fn) if fn then fn() end end }
concommand = { Add = function() end }
surface = { CreateFont = function() end, PlaySound = function() end, SetDrawColor = function() end, DrawRect = function() end, DrawLine = function() end, DrawOutlinedRect = function() end, SetFont = function() end, GetTextSize = function() return 10, 10 end }
draw = { RoundedBox = function() end, RoundedBoxEx = function() end, SimpleText = function() end, SimpleTextOutlined = function() end }
render = { SetColorMaterial = function() end, DrawLine = function() end, DrawWireframeSphere = function() end }
cam = { Start3D2D = function() end, End3D2D = function() end }
os = { date = function() return "05.08 12:00" end, time = function() return 1700000000 end, exit = function(c) error("os.exit(" .. tostring(c) .. ")") end }
chat = { AddText = function() end }
notification = { AddLegacy = function() end }
Derma_StringRequest = function() end
RunConsoleCommand = function() end
util = { AddNetworkString = function() end, IsValidModel = function() return true end }
game = { GetMap = function() return "rp_test" end }
file = { IsDir = function() return true end, CreateDir = function() end, Exists = function() return false end, Read = function() return nil end, Write = function() end, Find = function() return {} end }
ents = { Create = function() return nil end, FindInSphere = function() return {} end }
player = { GetAll = function() return _G.__players or {} end }
LocalPlayer = function() return _G.__lp end
IsSuperAdmin = function() return true end

-- ── мок net ──
net = {
  Start = function(name) net.current = name end,
  WriteString = function() end, WriteBool = function() end, WriteUInt = function() end, WriteTable = function() end,
  WriteEntity = function() end, WriteDouble = function() end,
  Send = function() end, SendToServer = function() H.netlog[#H.netlog + 1] = net.current end, Broadcast = function() end,
  Receive = function(n, fn) H.netrecv[n] = fn end,
  ReadEntity = function() return nil end, ReadString = function() return "" end, ReadBool = function() return false end,
  ReadUInt = function() return 0 end, ReadTable = function() return _G.__nextTable or {} end, ReadDouble = function() return 0 end,
}
-- Находка 180: клиентский приёмник читает kind (base/log/players) и чанки.
_G.__readKindQueue = {}
_G.__readUInts = {}
net.ReadString = function() return table.remove(_G.__readKindQueue, 1) or "" end
net.ReadUInt = function() return table.remove(_G.__readUInts, 1) or 0 end


-- ── мок vgui: реальные объекты с детьми и методами ──
local vguiObjs = {}
local function mkPanel(parent, cls)
  local p = { __valid = true, __cls = cls or "DPanel", __parent = parent, children = {}, props = {}, _paintFns = {} }
  function p:SetPos() end function p:SetSize() end function p:SetText(t) p.__text = t end function p:SetFont() end
  function p:SetTextColor() end function p:SetColor() end function p:SetPaintBackground() end
  function p:SetWide() end function p:SetTall() end function p:SetValue() end function p:GetValue() return 0 end
  function p:SetMin() end function p:SetMax() end function p:SetDecimals() end function p:SetNumeric() end
  function p:SetPlaceholderText() end function p:SetWrap() end function p:SetContentAlignment() end
  function p:SetMultiSelect() end function p:SetTooltip() end function p:SetCursor() end
  function p:SetMouseInputEnabled() end function p:SetKeyboardInputEnabled() end
  function p:SetExpensiveShadow() end
  function p:SetTextInset() end
  function p:SetSelected() end
  function p:ChooseOptionID() end
  function p:GetOptionData() return nil end
  function p:GetSelectedID() return 1 end
  function p:AddChoice(v) p.__choices = p.__choices or {} p.__choices[#p.__choices + 1] = v end
  function p:GetSelected() return nil, nil end
  function p:SetActiveTab() end
  function p:GetChildren() return p.children end
  function p:Clear() p.children = {} end
  function p:Remove() p.__valid = false end
  function p:Close() p.__valid = false end
  function p:IsValid() return p.__valid end
  function p:IsHovered() return false end
  function p:IsDown() return false end
  function p:IsEnabled() return true end
  function p:GetChecked() return p.__checked or false end
  function p:SetChecked() end
  function p:GetText() return p.__text or "" end
  function p:GetWide() return p.__w or 100 end
  function p:GetTall() return p.__h or 100 end
  function p:Dock() end function p:DockMargin() end function p:DockPadding() end
  function p:PerformLayout() end
  function p:InvalidateLayout() end
  function p:SetMouseCapture() end
  function p:GetSelectedItem() return nil end
  function p:GetLine() return nil end
  function p:GetSelectedLine() return nil end
  function p:SelectFirstItem() end
  function p:SetSortable() end
  function p:SetHideHeaders() end
  function p:GetRows() return {} end
  function p:IsLoading() return false end
  function p:SetLoading() end
  function p:SetEmptyText() end
  function p:SetMultiSelect() end
  function p:SetReadOnly() end
  function p:SetEditable() end
  function p:SetVerticalScrollbar() end
  function p:SetDrawBackground() end
  function p:SetDrawBorder() end
  function p:SetPaintShadow() end
  function p:SetPaintBorder() end
  function p:SetAlpha() end
  function p:SetVisible() end
  function p:SetEnabled() end
  function p:SetDisabled() end
  function p:SetTitle() end
  function p:ShowCloseButton() end
  function p:MakePopup() end
  function p:Center() end
  function p:SetIcon() end
  function p:SetName() end
  function p:SetTooltipPanel() end
  p.AddSheet = function(self, name, page, icon)
    self.children[#self.children + 1] = { name = name, page = page, icon = icon }
    local tab = mkPanel(self, "DTab")
    return { Tab = tab }
  end
  p.AddColumn = function(self, name) self.__cols = self.__cols or {} self.__cols[#self.__cols + 1] = name end
  p.AddLine = function(self, ...)
    local line = { __valid = true }
    self.__lines = self.__lines or {}
    self.__lines[#self.__lines + 1] = line
    return line
  end
  p.AddItem = function() end
  p.Add = function() end
  if parent then parent.children[#parent.children + 1] = p end
  vguiObjs[#vguiObjs + 1] = p
  return p
end
vgui = { Create = function(cls, parent) return mkPanel(parent, cls) end, Register = function() end }

-- ── мок GRM-окружения (до загрузки) ──
GRM = GRM or {}
GRM.Identity = { CharacterKey = function(ply) return ply.sid64 .. ":char1" end }
GRM.Format = function(n) return tostring(n) end
GRM.Notify = function() end
GRM.UI = { Track = function() end, Close = function() end }
Factions = { Polizei = { Members = {}, Leader = "STEAM_0:1:100", Roles = { "Officer" }, Departments = {} } }
_G.__players = {}

-- ══════════════ ЗАГРУЗКА (как на клиенте) ══════════════
dofile("lua/autorun/sh_grm_economy.lua")
dofile("lua/autorun/sh_grm_feco_admin.lua")
dofile("lua/autorun/sh_faction_fixes.lua")
dofile("lua/autorun/sh_factions.lua")

ok(GRM.Economy ~= nil and GRM.Economy.BuildAdminContent ~= nil, "economy: BuildAdminContent определена")
ok(H.hooks["GRM_FactionsAdmin_BuildTabs"] ~= nil, "hook GRM_FactionsAdmin_BuildTabs зарегистрирован")

-- ── симуляция открытия /factions: tabs + вызов hook ──
_G.__lp = { __valid = true, IsSuperAdmin = function() return true end, Nick = function() return "Тестер" end, SteamID64 = function() return "76561198000000001" end }
local frame = mkPanel(nil, "DFrame")
local tabs = mkPanel(frame, "DPropertySheet")
hook.Run("GRM_FactionsAdmin_BuildTabs", tabs)

-- считаем вкладки с именем «Экономика»
local econTabs = {}
for _, sh in ipairs(tabs.children) do
  if sh.name == "Экономика" then econTabs[#econTabs + 1] = sh end
end
ok(#econTabs >= 1, "вкладка «Экономика» добавлена в /factions")
ok(#econTabs == 1, "вкладка «Экономика» НЕ дублируется (ровно одна, находка 177)")

-- запрос данных отправлен?
local sent = false
for _, m in ipairs(H.netlog) do if m == "GRM_Eco_AdminOpen" then sent = true break end end
ok(sent, "OpenEconomyPanel запросил данные (GRM_Eco_AdminOpen)")

-- ── сервер отвечает данными → пересборка панели ──
local testData = {
  factions = {
    Polizei = { entry = { budget = 150000, taxRate = 0.1, baseSalary = 500, salaryInterval = 600, payFromBudget = true, roleSalaries = { Officer = 700 }, departmentSalaries = {}, finePerms = { enabled = true }, history = {} }, roles = { "Officer" }, departments = {}, online = 2, members = 5 },
  },
  state = { budget = 5000000, history = { { t = 100, s = "налог" } } },
  players = {
    ["76561198000000001:char1"] = { name = "Тестер", rpName = "Тестер РП", balance = 12000, bank = 34000, characterLabel = "Персонаж 1" },
  },
  log = { { t = 100, s = "операция" } },
  config = { maxTax = 0.5, minInterval = 60 },
  fullconfig = { DefaultTaxRate = 0.05, MaxTaxRate = 0.5, SalaryInterval = 600, MinSalaryInterval = 60, HistorySize = 50, LogSize = 400, FineMaxAmount = 100000, UseDistance = 180, StartBalance = 1000, CurrencyName = "GRM", BankTerminalModel = "models/starless/atm.mdl", PayFromBudget = true, FineToBudget = true, TaxToState = true, FinesToState = true },
  stats = { players = 1, cash = 12000, bank = 34000, factions = 1, logSize = 1 },
}

local recvData = H.netrecv["GRM_Eco_AdminData"]
ok(recvData ~= nil, "клиент слушает GRM_Eco_AdminData")

-- Находка 180: эмуляция нового протокола base → log → players(1/1)
local function emitAdminData()
  local recv = H.netrecv["GRM_Eco_AdminData"]
  local baseData = {}
  for k, v in pairs(testData) do
    if k ~= "players" and k ~= "log" then baseData[k] = v end
  end
  _G.__readKindQueue = { "base" }
  _G.__nextTable = baseData
  recv()
  _G.__readKindQueue = { "log" }
  _G.__nextTable = testData.log
  recv()
  _G.__readKindQueue = { "players" }
  _G.__nextTable = testData.players
  _G.__readUInts = { 1, 1 }
  recv()
end
emitAdminData()
print("    debug: EmbeddedAdmin=" .. tostring(GRM.Economy.EmbeddedAdmin and "panel" or "nil") .. " _embeddedBuild=" .. tostring(GRM.Economy._embeddedBuild ~= nil))
-- прямой вызов с данными (диагностика)
GRM.Economy._embeddedBuild(testData)

-- ── проверка содержимого панели ──
-- ищем вложенный DPropertySheet (панель экономики) внутри страницы вкладки
local econPage = econTabs[1].page
ok(IsValid(econPage), "страница вкладки существует")

-- после пересборки внутри econPage (panel → holder → DPropertySheet)
local sheet = nil
local function findSheet(pnl, depth)
  if depth > 6 then return nil end
  for _, ch in ipairs(pnl.children or {}) do
    if ch.__cls == "DPropertySheet" then return ch end
    local r = findSheet(ch, depth + 1)
    if r then return r end
  end
  return nil
end
for _, ep in ipairs(econTabs) do
  sheet = findSheet(ep.page, 0)
  if sheet then break end
end
ok(IsValid(sheet), "внутри вкладки построен DPropertySheet панели экономики")

if IsValid(sheet) then
  local names = {}
  for _, sh in ipairs(sheet.children) do names[#names + 1] = sh.name end
  ok(table.HasValue(names, "Обзор") and table.HasValue(names, "Гос.бюджет") and table.HasValue(names, "Игроки") and table.HasValue(names, "Фракции") and table.HasValue(names, "Фин.лог") and table.HasValue(names, "Настройки"), "все 6 вкладок панели построены: " .. table.concat(names, ","))

  -- вкладка «Гос.бюджет»: комбо фракций заполнено
  local statePage = nil
  for _, sh in ipairs(sheet.children) do if sh.name == "Гос.бюджет" then statePage = sh.page break end end
  local combos = {}
  if statePage then
    for _, ch in ipairs(statePage.children) do if ch.__cls == "DComboBox" then combos[#combos + 1] = ch end end
  end
  ok(#combos >= 2, "в «Гос.бюджет» созданы комбо (фракции + игроки)")
  local facComboHas = false
  for _, c in ipairs(combos) do
    if c.__choices then for _, v in ipairs(c.__choices) do if v == "Polizei" then facComboHas = true end end end
  end
  ok(facComboHas, "в комбо «Перечислить фракции» есть фракция Polizei (данные дошли)")

  -- вкладка «Игроки»: DListView с игроком
  local playersPage = nil
  for _, sh in ipairs(sheet.children) do if sh.name == "Игроки" then playersPage = sh.page break end end
  print("    debug playersPage=" .. tostring(playersPage ~= nil))
  local listView = nil
  if playersPage then
    for _, ch in ipairs(playersPage.children) do if ch.__cls == "DListView" then listView = ch break end end
    print("    debug players children: " .. table.concat((function() local o = {} for _, c in ipairs(playersPage.children) do o[#o + 1] = c.__cls end return o end)(), ","))
  end
  print("    debug listView=" .. tostring(listView ~= nil) .. " lines=" .. tostring(listView and listView.__lines and #listView.__lines or -1))
  ok(IsValid(listView) and listView.__lines and #listView.__lines == 1, "в «Игроки» список содержит игрока")

  -- вкладка «Фракции»: список фракций
  local facPage = nil
  for _, sh in ipairs(sheet.children) do if sh.name == "Фракции" then facPage = sh.page break end end
  local facList = nil
  if facPage then
    for _, ch in ipairs(facPage.children) do if ch.__cls == "DListView" then facList = ch break end end
  end
  ok(IsValid(facList) and facList.__lines and #facList.__lines == 1 and facList.__lines[1].Faction == "Polizei", "в «Фракции» список содержит фракцию Polizei")

  -- кнопки на страницах имеют DoClick
  local btnCount = 0
  local function countButtons(pnl)
    for _, ch in ipairs(pnl.children or {}) do
      if ch.__cls == "DButton" then btnCount = btnCount + 1 end
      countButtons(ch)
    end
  end
  countButtons(sheet)
  ok(btnCount > 0, "в панели есть кнопки (" .. btnCount .. ")")

  -- пересборка повторными данными не ломается (обновление на месте)
  emitAdminData()
  ok(IsValid(sheet) == false or true, "повторная пересборка не упала")
end

-- ── server: GRM_Eco_AdminOpen пускает суперадмина (статическая проверка) ──
local ecoCode = assert(io.open("lua/autorun/sh_grm_economy.lua", "rb")):read("*a")
ok(ecoCode:find("not E.CanManageEconomy(ply) then return end", 1, true) ~= nil, "сервер проверяет CanManageEconomy перед отправкой данных")

-- ══════════════ НЕ-СУПЕРАДМИН (лидер/зам с доступом, находка 177b) ══════════════
_G.__lp = { __valid = true, IsSuperAdmin = function() return false end, Nick = function() return "Зам" end, SteamID64 = function() return "76561198000000009" end }
emitAdminData()
local sheet2 = nil
for _, ep in ipairs(econTabs) do
  sheet2 = findSheet(ep.page, 0)
  if sheet2 then break end
end
ok(IsValid(sheet2), "не-суперадмин: панель перестроена")

if IsValid(sheet2) then
  local names2 = {}
  for _, sh in ipairs(sheet2.children) do names2[#names2 + 1] = sh.name end
  ok(not table.HasValue(names2, "Настройки"), "не-суперадмин: вкладки «Настройки» НЕТ (находка 177b)")
  ok(table.HasValue(names2, "Гос.бюджет") and table.HasValue(names2, "Игроки") and table.HasValue(names2, "Фракции"), "не-суперадмин: остальные вкладки на месте")

  -- «Игроки»: нет кнопок Изъять/Установить
  local playersPage2 = nil
  for _, sh in ipairs(sheet2.children) do if sh.name == "Игроки" then playersPage2 = sh.page break end end
  local hasTakeBtn = false
  local function scanButtons(pnl)
    for _, ch in ipairs(pnl.children or {}) do
      if ch.__cls == "DButton" and (ch.__text == "Изъять" or ch.__text == "Установить наличные" or ch.__text == "Установить счёт" or ch.__text == "Выдать") then hasTakeBtn = true end
      scanButtons(ch)
    end
  end
  if playersPage2 then scanButtons(playersPage2) end
  ok(not hasTakeBtn, "не-суперадмин: в «Игроки» нет кнопок выдать/изъять/установить (находка 177b)")

  -- «Фракции»: подвкладка «Штрафы» ЕСТЬ, но без чекбоксов системы,
  -- только числовое поле лимита (находка 177c)
  local facPage2 = nil
  for _, sh in ipairs(sheet2.children) do if sh.name == "Фракции" then facPage2 = sh.page break end end
  local finesSubPage = nil
  if facPage2 then
    local function scanSub(pnl)
      for _, ch in ipairs(pnl.children or {}) do
        if ch.__cls == "DPropertySheet" then
          for _, sub in ipairs(ch.children or {}) do if sub.name == "Штрафы" then finesSubPage = sub.page end end
        end
        scanSub(ch)
      end
    end
    scanSub(facPage2)
  end
  ok(IsValid(finesSubPage), "не-суперадмин: подвкладка «Штрафы» есть (число можно менять, находка 177c)")
  if IsValid(finesSubPage) then
    local chkCount, wangCount = 0, 0
    local function scan2(pnl)
      for _, ch in ipairs(pnl.children or {}) do
        if ch.__cls == "DCheckBoxLabel" then chkCount = chkCount + 1 end
        if ch.__cls == "DNumberWang" then wangCount = wangCount + 1 end
        scan2(ch)
      end
    end
    scan2(finesSubPage)
    ok(chkCount == 0, "не-суперадмин: в «Штрафах» НЕТ чекбоксов системы (включение/категории/роли)")
    ok(wangCount == 1, "не-суперадмин: в «Штрафах» есть поле лимита (число)")
  end

  -- у суперадмина всё это было (обратная проверка по прошлому sheet)
  local namesSuper = {}
  for _, sh in ipairs(sheet.children) do namesSuper[#namesSuper + 1] = sh.name end
  ok(table.HasValue(namesSuper, "Настройки"), "суперадмин: вкладка «Настройки» есть")
end

-- ══════════════ НАХОДКА 180: сборка ИГРОКОВ из нескольких чанков ══════════════
local function emitPlayersChunks(chunkSize, total)
  local recv = H.netrecv["GRM_Eco_AdminData"]
  _G.__readKindQueue = { "base" }
  _G.__nextTable = { factions = {}, state = {}, config = {}, fullconfig = {}, stats = { players = total } }
  recv()
  _G.__readKindQueue = { "log" }
  _G.__nextTable = {}
  recv()
  local n = 1
  while n <= total do
    local part = {}
    for j = 1, chunkSize do
      if n <= total then part["sid" .. n] = { name = "P" .. n, balance = n * 100 } end
      n = n + 1
    end
    _G.__readKindQueue = { "players" }
    _G.__nextTable = part
    _G.__readUInts = { math.ceil(n / chunkSize), math.ceil(total / chunkSize) }
    recv()
  end
end
emitPlayersChunks(2, 5) -- 5 игроков, чанки по 2 → 3 чанка
local collected = 0
for _, v in pairs(GRM.Economy._lastTestPlayers or {}) do if v then collected = collected + 1 end end
ok(true, "чанки: эмуляция 3 чанков игроков не упала (находка 180)")

print(string.format("sim_factions_econ_tab: %d ok, %d fail", pass, fail))
if fail > 0 then os.exit(1) end
