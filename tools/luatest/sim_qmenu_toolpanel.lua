-- ======================================================================
-- sim_qmenu_toolpanel — панели настроек инструментов в «GRM Стройка+».
--
-- Дефект (задача 13, скриншоты): в кастомном Q-меню у КАЖДОГО инструмента
-- висело «У инструмента «colour» нет настраиваемых параметров» — не было
-- ни RGB-палитры, ни ползунков, ни кнопок бинда на Numpad, ни списка
-- материалов. В ванильном Q те же инструменты показывают полные панели.
--
-- Причина: все stool объявляют панель как
--     function TOOL.BuildCPanel(panel)        -- ТОЧКА, один аргумент
-- а меню звало её как метод:
--     pcall(tool.BuildCPanel, tool, CP)       -- лишний первый аргумент
-- Внутри panel:AddControl(...) уходил на таблицу инструмента →
-- «attempt to call method 'AddControl' (a nil value)». pcall глотал
-- ошибку, built оставался false → показывалась заглушка.
--
-- Проверяем:
--   1) QM.BuildToolPanel зовёт BuildCPanel с ОДНИМ аргументом (панелью);
--   2) контролы реально доезжают до панели (RGB, слайдер, Numpad, комбо);
--   3) поддержан и colon-синтаксис (TOOL:BuildCPanel);
--   4) настоящая ошибка внутри стула возвращается наверх, а не глотается;
--   5) панель без BuildCPanel, но с готовыми контролами считается собранной;
--   6) реальные stool проекта строятся без ошибок на моке ControlPanel;
--   7) подписи инструментов берутся из language (как в ванильном Q).
--
-- Запуск: luajit tools/luatest/sim_qmenu_toolpanel.lua
-- ======================================================================

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1
    else fail = fail + 1 io.write("  [FAIL] " .. msg .. "\n") end
end
local function eq(got, want, msg)
    ok(got == want, msg .. "  (ожидали " .. tostring(want) .. ", получили " .. tostring(got) .. ")")
end

-- ----------------------------------------------------------------------
-- Мок ControlPanel: запоминает добавленные контролы.
-- ----------------------------------------------------------------------
local function mkPanel()
    local p = { controls = {}, children = {} }
    -- Возвращаемый виджет должен терпеть любые методы (AddChoice,
    -- SetPaintBackground, Dock, SetValue…): в GMod это полноценная панель.
    local anyWidget = { __index = function(_, k)
        if type(k) == "string" then return function() end end
        return nil
    end }
    function p:AddControl(kind, data)
        local w = setmetatable({ kind = kind, data = data or {} }, anyWidget)
        self.controls[#self.controls + 1] = w
        self.children[#self.children + 1] = { kind = kind }
        return w
    end
    function p:GetChildren() return self.children end
    function p:Help(t) return self:AddControl("Help", { Text = t }) end
    function p:CheckBox(l, c) return self:AddControl("Checkbox", { Label = l, Command = c }) end
    function p:NumSlider(l, c) return self:AddControl("Slider", { Label = l, Command = c }) end
    function p:TextEntry(l, c) return self:AddControl("TextEntry", { Label = l, Command = c }) end
    function p:Button(l, c) return self:AddControl("Button", { Label = l, Command = c }) end
    function p:ComboBox(l, c) return self:AddControl("ComboBox", { Label = l, Command = c }) end
    function p:ControlHelp(t) return self:AddControl("Help", { Text = t }) end
    function p:Clear() self.controls, self.children = {}, {} end
    -- Виджеты, которые ControlPanel возвращает наружу (ComboBox/TextEntry и
    -- т.п.), имеют собственные методы: AddChoice, SetPaintBackground, Dock…
    -- Без них реальные stool падали бы в тесте, хотя в GMod работают.
    setmetatable(p, { __index = function(_, k)
        if type(k) == "string" then return function() end end
        return nil
    end })
    function p:AddPanel() end
    function p:Has(kind)
        for _, c in ipairs(self.controls) do if c.kind == kind then return true end end
        return false
    end
    return p
end

-- Загружаем только нужную функцию: файл целиком тянет за собой GMod.
_G.GRM = _G.GRM or {}
_G.GRM.QMenu = _G.GRM.QMenu or {}
local QM = _G.GRM.QMenu

do
    local src = io.open("lua/autorun/sh_grm_qmenu.lua", "rb"):read("*a")
    local body = src:match("(function QM%.BuildToolPanel.-\nend)\n")
    assert(body, "не найдено тело QM.BuildToolPanel — тест устарел")
    local chunk = assert(loadstring("local QM = ... \n" .. body .. "\nreturn QM"))
    chunk(QM)
end
ok(type(QM.BuildToolPanel) == "function", "QM.BuildToolPanel извлечена из модуля")

io.write("\n--- 1. Вызов с ОДНИМ аргументом (корень дефекта) ---\n")

local seen = {}
local dotTool = {}
function dotTool.BuildCPanel(panel)
    seen.argc = select("#", panel)
    seen.first = panel
    panel:AddControl("Header", { Description = "Цвет" })
end

local cp = mkPanel()
local built, err = QM.BuildToolPanel(dotTool, cp)
ok(built, "панель инструмента собрана")
eq(err, nil, "ошибки нет")
ok(seen.first == cp, "первым аргументом пришла ПАНЕЛЬ, а не таблица инструмента")
ok(seen.first ~= dotTool, "инструмент НЕ передан первым аргументом (старый дефект)")
eq(#cp.controls, 1, "контрол доехал до панели")

io.write("\n--- 2. Реальные типы контролов доезжают ---\n")

local rich = {}
function rich.BuildCPanel(panel)
    panel:AddControl("Header",   { Description = "Источник света" })
    panel:AddControl("Color",    { Label = "Цвет света", Red = "r", Green = "g", Blue = "b" })
    panel:AddControl("Slider",   { Label = "Яркость", Command = "light_brightness", Min = 0, Max = 10 })
    panel:AddControl("Slider",   { Label = "Радиус", Command = "light_size", Min = 0, Max = 1024 })
    panel:AddControl("Numpad",   { Label = "Клавиша переключения", Command = "light_key" })
    panel:AddControl("Checkbox", { Label = "Переключение по нажатию", Command = "light_toggle" })
    panel:AddControl("ComboBox", { Label = "Материал", Options = {} })
end
local cp2 = mkPanel()
ok(QM.BuildToolPanel(rich, cp2), "богатая панель собрана")
ok(cp2:Has("Color"),    "RGB-палитра цвета на месте")
ok(cp2:Has("Slider"),   "ползунки на месте")
ok(cp2:Has("Numpad"),   "кнопка бинда клавиши на месте")
ok(cp2:Has("Checkbox"), "чекбокс на месте")
ok(cp2:Has("ComboBox"), "выпадающий список на месте")
eq(#cp2.controls, 7, "все 7 контролов добавлены")

io.write("\n--- 3. Colon-синтаксис тоже поддержан ---\n")

local colonTool = {}
function colonTool:BuildCPanel(panel)
    -- self — инструмент, panel — панель
    if type(self) ~= "table" or type(panel) ~= "table" then error("плохие аргументы") end
    panel:AddControl("Header", { Description = "colon" })
end
local cp3 = mkPanel()
ok(QM.BuildToolPanel(colonTool, cp3), "стул с colon-синтаксисом собран запасным путём")
eq(#cp3.controls, 1, "контрол colon-стула добавлен")

io.write("\n--- 4. Настоящая ошибка не глотается ---\n")

local broken = {}
function broken.BuildCPanel(panel) error("внутренняя поломка стула") end
local cp4 = mkPanel()
local b4, e4 = QM.BuildToolPanel(broken, cp4)
eq(b4, false, "сломанный стул не считается собранным")
ok(type(e4) == "string" and e4:find("внутренняя поломка", 1, true) ~= nil,
    "текст ошибки возвращается наверх для лога")

io.write("\n--- 5. Панель без BuildCPanel ---\n")

local noBuild = {}
local cp5 = mkPanel()
eq(QM.BuildToolPanel(noBuild, cp5), false, "пустой инструмент — заглушка уместна")
local cp6 = mkPanel()
cp6:AddControl("Header", { Description = "заранее" })
ok(QM.BuildToolPanel(noBuild, cp6), "непустая панель считается собранной")
eq(QM.BuildToolPanel(nil, cp6), false, "nil-инструмент не роняет функцию")

io.write("\n--- 6. Реальные stool проекта строятся ---\n")

-- Мок GLua ровно настолько, чтобы прочитать stool-файлы.
_G.CLIENT, _G.SERVER = true, false
_G.TOOL = nil
function _G.AddCSLuaFile() end
function _G.include() end
_G.language = { phrases = {} }
function _G.language.Add(k, v) _G.language.phrases[k] = v end
function _G.language.GetPhrase(k) return _G.language.phrases[k] or k end
_G.concommand = { Add = function() end }
_G.net = { Receive = function() end, Start = function() end, SendToServer = function() end,
           WriteString = function() end, WriteEntity = function() end, WriteBool = function() end }
_G.hook = { Add = function() end, Run = function() end }
_G.surface = { CreateFont = function() end, SetFont = function() end,
               GetTextSize = function() return 10, 10 end }
_G.util = { AddNetworkString = function() end, PrecacheModel = function() end }
_G.list = { Set = function() end, Get = function() return {} end }
_G.cvars = { AddChangeCallback = function() end }
_G.CreateClientConVar = function() return { GetInt = function() return 0 end,
                                            GetString = function() return "" end,
                                            GetBool = function() return false end } end
_G.GetConVar = _G.CreateClientConVar
_G.Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
_G.Material = function() return {} end
_G.Vector = function() return {} end
_G.Angle = function() return {} end
_G.IsValid = function(v) return v ~= nil and v ~= false end
_G.istable = function(v) return type(v) == "table" end
_G.isstring = function(v) return type(v) == "string" end
_G.isnumber = function(v) return type(v) == "number" end
_G.isfunction = function(v) return type(v) == "function" end
_G.vgui = { Create = function() return mkPanel() end }
_G.draw = { RoundedBox = function() end, SimpleText = function() end }
_G.string.Trim = function(s) return (tostring(s or ""):gsub("^%s*(.-)%s*$", "%1")) end

local function loadStool(path)
    _G.TOOL = { ClientConVar = {}, Category = "", Name = "", Mode = "" }
    setmetatable(_G.TOOL, { __index = function() return function() end end })
    local f = loadfile(path)
    if not f then return nil, "не читается" end
    local okRun, errRun = pcall(f)
    if not okRun then return nil, errRun end
    return _G.TOOL
end

local stools = {}
do
    local p = io.popen("ls lua/weapons/gmod_tool/stools/*.lua 2>/dev/null")
    if p then
        for line in p:lines() do stools[#stools + 1] = line end
        p:close()
    end
end
ok(#stools > 0, "stool-файлы найдены (" .. #stools .. ")")

local withPanel, builtOk = 0, 0
for _, path in ipairs(stools) do
    local tool = loadStool(path)
    if tool and rawget(tool, "BuildCPanel") then
        withPanel = withPanel + 1
        local panel = mkPanel()
        local b = QM.BuildToolPanel(tool, panel)
        local name = path:match("([^/]+)%.lua$")
        if b and #panel.controls > 0 then
            builtOk = builtOk + 1
        else
            io.write("  [FAIL] " .. name .. ": панель не построилась\n")
            fail = fail + 1
        end
    end
end
ok(withPanel > 0, "инструменты с BuildCPanel есть (" .. withPanel .. ")")
eq(builtOk, withPanel, "ВСЕ инструменты с панелью строятся без ошибок")

io.write("\n--- 7. Подписи как в ванильном Q ---\n")

local src = io.open("lua/autorun/sh_grm_qmenu.lua", "rb"):read("*a")
ok(src:find("language.GetPhrase", 1, true) ~= nil,
    "подпись инструмента берётся из language.GetPhrase")
ok(src:find("toolLabel(t)", 1, true) ~= nil,
    "строка списка использует toolLabel, а не сырой t.label")
ok(src:find("fillSchema", 1, true) ~= nil,
    "настройки строятся из схемы, не из чужого BuildCPanel")
ok(src:find("pcall(bcp, panel)", 1, true) ~= nil,
    "BuildCPanel зовётся с одним аргументом")
local codeOnly = src:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", "")
ok(codeOnly:find("pcall(tool.BuildCPanel, tool, CP)", 1, true) == nil,
    "старого ошибочного вызова не осталось в коде")

io.write("\n--- 8. Библиотеки проверяются как таблицы ---\n")

ok(codeOnly:find("isfunction(controlpanel)", 1, true) == nil,
    "controlpanel не проверяется как функция (он таблица)")
ok(src:find("ResolveSchema", 1, true) ~= nil,
    "схема резолвится без controlpanel")
for _, lib in ipairs({ "weapons", "language", "spawnmenu", "net", "draw", "hook", "util" }) do
    ok(codeOnly:find("isfunction(" .. lib .. ")", 1, true) == nil,
        "библиотека " .. lib .. " не проверяется как функция")
end

io.write(("\n=== ИТОГ: %d/%d, failures=%d ===\n"):format(pass, pass + fail, fail))
if fail > 0 then os.exit(1) end
