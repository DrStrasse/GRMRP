-- ======================================================================
-- sim_qmenu_freeze — воспроизведение ЗАВИСАНИЯ Q-меню у игрока без прав.
--
-- Симптом: игрок снял с себя права суперадмина, нажал Q — игра встала
-- намертво (не ошибка в консоли, а именно вечный цикл: ошибка бы просто
-- закрыла меню).
--
-- Стенд поднимает клиентскую часть sh_grm_qmenu.lua с минимальным vgui и
-- дёргает ровно тот путь, который проходит игрок: PlayerBindPress("+menu").
-- Чтобы вечный цикл не подвесил и сам тест, ставим debug-хук-сторожа:
-- он рвёт выполнение после лимита инструкций и печатает место зацикливания.
--
-- Запуск: luajit tools/luatest/sim_qmenu_freeze.lua
-- ======================================================================
_G.CLIENT, _G.SERVER = true, false
function _G.AddCSLuaFile() end
function _G.include() end

function _G.istable(x) return type(x) == "table" end
function _G.isstring(x) return type(x) == "string" end
function _G.isnumber(x) return type(x) == "number" end
function _G.isfunction(x) return type(x) == "function" end
function _G.IsValid(o)
    if o == nil or o == false then return false end
    if type(o) == "table" then return not o.__removed end
    return true
end
_G.Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
_G.math.Clamp = function(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
_G.string.Trim = function(s) return (tostring(s or ""):gsub("^%s*(.-)%s*$", "%1")) end
_G.string.Explode = function(sep, s)
    local o = {} for m in tostring(s):gmatch("[^" .. sep .. "]+") do o[#o + 1] = m end return o
end
_G.TEXT_ALIGN_LEFT, _G.TEXT_ALIGN_RIGHT, _G.TEXT_ALIGN_CENTER = 0, 2, 1
_G.TOP, _G.FILL, _G.LEFT, _G.RIGHT, _G.BOTTOM = 1, 5, 2, 3, 4
_G.HUD_PRINTTALK, _G.HUD_PRINTCENTER = 3, 4
_G.ScrW = function() return 1920 end
_G.ScrH = function() return 1080 end
_G.CurTime = function() return os.clock() end
_G.RealTime = function() return os.clock() end
_G.SysTime = function() return os.clock() end
_G.FrameTime = function() return 0.016 end
_G.color_white = Color(255, 255, 255)

local hooks = {}
_G.hook = {
    Add = function(ev, id, fn) hooks[ev] = hooks[ev] or {} hooks[ev][id] = fn end,
    Remove = function(ev, id) if hooks[ev] then hooks[ev][id] = nil end end,
    GetTable = function() return hooks end,
    Run = function(ev, ...)
        for _, fn in pairs(hooks[ev] or {}) do
            local r = fn(...) if r ~= nil then return r end
        end
    end,
    Call = function(ev, _, ...) return _G.hook.Run(ev, ...) end,
}
_G.timer = { Simple = function() end, Create = function() end, Remove = function() end }
_G.concommand = { Add = function() end }
_G.net = setmetatable({}, { __index = function() return function() end end })
_G.surface = {
    SetFont = function() end,
    GetTextSize = function(t) return #tostring(t) * 7, 14 end,
    PlaySound = function() end,
    CreateFont = function() end,
    SetDrawColor = function() end,
    DrawRect = function() end,
}
_G.draw = setmetatable({
    SimpleText = function() end, RoundedBox = function() end, RoundedBoxEx = function() end,
}, { __index = function() return function() end end })
_G.util = setmetatable({
    JSONToTable = function() return nil end, TableToJSON = function() return "{}" end,
}, { __index = function() return function() end end })
_G.file = { Read = function() return nil end, Write = function() end, Exists = function() return false end,
    CreateDir = function() end, IsDir = function() return false end }
_G.language = { Add = function() end, GetPhrase = function(k) return k end }
_G.spawnmenu = setmetatable({}, { __index = function() return function() end end })
_G.controlpanel = { Get = function() return nil end, Create = function() return nil end }
_G.weapons = { GetStored = function() return nil end }
_G.list = { Get = function() return {} end }
_G.gui = { EnableScreenClicker = function() end }
_G.RunConsoleCommand = function() end
_G.LocalPlayer = function() return _G.__LP end
_G.CreateClientConVar = function() return { GetBool = function() return false end,
    GetInt = function() return 0 end, GetString = function() return "" end } end
_G.GetConVar = function() return nil end

-- ── минимальный vgui ────────────────────────────────────────────────
function newPanel(class)
    local p
    p = {
        __class = class, __children = {}, __visible = true, __w = 400, __h = 300, __x = 0, __y = 0,
        SetSize = function(s, w, h) s.__w, s.__h = w, h end,
        SetTall = function(s, h) s.__h = h end,
        SetWide = function(s, w) s.__w = w end,
        GetTall = function(s) return s.__h end,
        GetWide = function(s) return s.__w end,
        GetBottom = function(s) return s.__y + s.__h end,
        SetPos = function(s, x, y) s.__x, s.__y = x, y end,
        GetPos = function(s) return s.__x, s.__y end,
        Dock = function() end, DockMargin = function() end, DockPadding = function() end,
        SetParent = function(s, par)
            s.__parent = par
            if type(par) == "table" and par.__children then par.__children[#par.__children + 1] = s end
        end,
        GetParent = function(s) return s.__parent end,
        GetChildren = function(s) return s.__children end,
        Add = function(s, c) s.__children[#s.__children + 1] = c return c end,
        AddItem = function(s, c) s.__children[#s.__children + 1] = c c.__parent = s return c end,
        Clear = function(s) s.__children = {} end,
        Remove = function(s) s.__removed = true end,
        SetVisible = function(s, v) s.__visible = v end, IsVisible = function(s) return s.__visible end,
        SetText = function(s, t) s.__text = t end, GetText = function(s) return s.__text or "" end,
        SetFont = function() end, SetTextColor = function() end, SetWrap = function() end,
        SetTooltip = function() end, SetContentAlignment = function() end,
        SetMouseInputEnabled = function() end, SetKeyboardInputEnabled = function() end,
        SetCursor = function() end, SetDrawOnTop = function() end, SetZPos = function() end,
        SetPaintBackground = function() end, SetPaintBackgroundEnabled = function() end,
        SetTitle = function() end, ShowCloseButton = function() end, SetDeleteOnClose = function() end,
        Center = function() end, MakePopup = function() end, Close = function(s) s.__removed = true end,
        InvalidateLayout = function() end, PerformLayout = function() end,
        SizeToContents = function() end, SizeToContentsY = function() end,
        IsHovered = function() return false end, HasFocus = function() return false end,
        SetValue = function() end, GetValue = function() return "" end,
        SetPlaceholderText = function() end, SetEnabled = function() end,
        SetImage = function() end, SetModel = function() end, SetMin = function() end,
        SetMax = function() end, SetDecimals = function() end, SetConVar = function() end,
        AddChoice = function() end, ChooseOptionID = function() end, SetSortItems = function() end,
        SetVBarVisible = function() end, GetCanvas = function(s) return s end,
        SetScrollbarWidth = function() end, SetSpacing = function() end,
        SetMultiline = function() end, SetEditable = function() end, SetNumeric = function() end,
        SetTextInset = function() end, SetHeaderHeight = function() end,
        AddColumn = function() return { SetWidth = function() end } end,
        AddLine = function() return { SetSortValue = function() end, Columns = {} } end,
        SetColor = function() end, SetAlpha = function() end,
    }
    p.VBar = { SetWide = function() end, __visible = true, SetVisible = function() end }
    --[[ Панель GMod имеет сотни методов. Стенд не обязан их перечислять:
         любой неизвестный метод считаем безвредной заглушкой-пустышкой,
         иначе тест падает на СВОЕЙ неполноте (SetSpaceX и т.п.) и маскирует
         настоящий дефект, ради которого он написан. ]]
    return setmetatable(p, { __index = function(_, k)
        if type(k) == "string" and k:match("^[A-Z]") then
            return function() end
        end
        return nil
    end })
end
_G.vgui = { Create = function(class, parent)
    local p = newPanel(class)
    if parent then p:SetParent(parent) end
    return p
end }

_G.GRM = _G.GRM or {}
_G.GRM.Notify = function() end
dofile("lua/autorun/sh_00_grm_ui.lua")

-- ── игрок БЕЗ прав ──────────────────────────────────────────────────
local function mkPly(super)
    return {
        __sa = super,
        IsSuperAdmin = function(s) return s.__sa end,
        IsAdmin = function(s) return s.__sa end,
        IsPlayer = function() return true end,
        Nick = function() return "Tester" end,
        SteamID = function() return "STEAM_0:0:1" end,
        SteamID64 = function() return "76561198000000010" end,
        GetNWBool = function(_, _, d) return d or false end,
        GetNWString = function(_, _, d) return d or "" end,
        GetNWInt = function(_, _, d) return d or 0 end,
        PrintMessage = function() end,
        ConCommand = function() end,
    }
end

dofile("lua/autorun/sh_grm_qmenu.lua")
local QM = GRM.QMenu

local fails, total = 0, 0
local function check(name, cond, extra)
    total = total + 1
    if cond then print("  OK   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "   " .. tostring(extra or "")) end
end

--[[ Сторож вечного цикла. Обычный pcall тут не спасёт: зависание — это не
     ошибка, а бесконечное выполнение, поэтому ограничиваем число VM-инструкций
     и по превышении бросаем ошибку с местом, где код крутится. ]]
local function runGuarded(fn, budget)
    budget = budget or 8e6
    local where
    local co = coroutine.create(function() fn() end)
    debug.sethook(co, function()
        local info = debug.getinfo(2, "Sl")
        where = info and (info.short_src .. ":" .. tostring(info.currentline)) or "?"
        error("WATCHDOG: превышен лимит инструкций (вечный цикл) у " .. tostring(where), 2)
    end, "", budget)
    local ok, err = coroutine.resume(co)
    debug.sethook(co)
    return ok, err, where
end

print("\n=== ТЕСТ 1: конфиг по умолчанию, игрок БЕЗ прав ===")
_G.__LP = mkPly(false)
QM.Cfg = QM.Cfg or {}
QM.Cfg.playersQ = false      -- ванильное Q закрыто игрокам
QM.Cfg.grmBuildMenu = true   -- наше меню включено
QM.Cfg.allowProps = true

local bindFn = hooks["PlayerBindPress"] and hooks["PlayerBindPress"]["GRM_QMenu_BindBlock"]
check("хук PlayerBindPress зарегистрирован", isfunction(bindFn))

local ok, err, where = runGuarded(function()
    bindFn(_G.__LP, "+menu", true)
end)
check("нажатие Q не подвешивает игру", ok, err)
if not ok then print("     ↳ место зацикливания: " .. tostring(where)) end
check("меню открылось", IsValid(QM._frame), "frame=" .. tostring(QM._frame))

print("\n=== ТЕСТ 2: повторное открытие/закрытие ===")
local ok2, err2, where2 = runGuarded(function()
    bindFn(_G.__LP, "+menu", false)
    bindFn(_G.__LP, "+menu", true)
    bindFn(_G.__LP, "+menu", false)
end)
check("цикл открытие→закрытие не виснет", ok2, err2)
if not ok2 then print("     ↳ место зацикливания: " .. tostring(where2)) end

print("\n=== ТЕСТ 3: игрок-админ ===")
_G.__LP = mkPly(true)
QM._frame = nil
local ok3, err3, where3 = runGuarded(function()
    if isfunction(QM.OpenMenu) then QM.OpenMenu() end
end)
check("у админа меню открывается без зависания", ok3, err3)
if not ok3 then print("     ↳ место зацикливания: " .. tostring(where3)) end

--[[ ТЕСТ 4. Главный подозреваемый: при открытии меню строится панель настроек
     РАНЕЕ ВЫБРАННОГО инструмента (QM._activeTool). Там зовётся настоящий
     BuildCPanel настоящего stool, и там же считается автовысота по детям
     ControlPanel. Именно этот путь у админа не выполнялся: с adminsToo=false
     админ видит ВАНИЛЬНОЕ Q, а наше меню открывается только у игрока. ]]
print("\n=== ТЕСТ 4: открытие с уже выбранным инструментом ===")

-- «Живая» ControlPanel: ведёт себя как настоящая — AddControl создаёт детей.
local function mkControlPanel()
    local cp = newPanel("ControlPanel")
    cp.AddControl = function(s, _, _)
        local c = newPanel("DPanel")
        c:SetParent(s)
        return c
    end
    cp.AddPanel = function(s, c) c:SetParent(s) return c end
    cp.Help = function(s) return s:AddControl("Header", {}) end
    cp.CheckBox = function(s) return s:AddControl("Checkbox", {}) end
    cp.NumSlider = function(s) return s:AddControl("Slider", {}) end
    cp.Button = function(s) return s:AddControl("Button", {}) end
    return cp
end
local madeCP = mkControlPanel()
_G.controlpanel = { Get = function() return madeCP end, Create = function() return madeCP end }

-- Настоящий stool из проекта — со своим BuildCPanel.
local realTool = { Mode = "grm_perm_tool" }
realTool.BuildCPanel = function(panel)
    panel:AddControl("Header", { Text = "GRM" })
    panel:AddControl("Checkbox", { Label = "Заморозка" })
end
_G.weapons = { GetStored = function() return { Tool = { grm_perm_tool = realTool } } end }

_G.__LP = mkPly(false)
QM._frame = nil
QM._activeTool = "grm_perm_tool"
local ok4, err4, where4 = runGuarded(function()
    QM.OpenMenu()
end)
check("меню с выбранным инструментом не виснет", ok4, err4)
if not ok4 then print("     ↳ место зацикливания: " .. tostring(where4)) end

--[[ ТЕСТ 5. Автовысота панели считается по ДЕТЯМ ControlPanel, а сама панель
     лежит внутри DScrollPanel. Если ребёнок окажется той же панелью (или
     цепочка родитель↔ребёнок замкнётся), обход детей и раскладка скролла
     начнут ходить по кругу — это классическое «намертво» без ошибки. ]]
print("\n=== ТЕСТ 5: самоссылающийся ребёнок панели ===")
local loopCP = mkControlPanel()
loopCP.__children[#loopCP.__children + 1] = loopCP   -- панель — сама себе ребёнок
_G.controlpanel = { Get = function() return loopCP end, Create = function() return loopCP end }
QM._frame = nil
QM._activeTool = "grm_perm_tool"
local ok5, err5, where5 = runGuarded(function()
    QM.OpenMenu()
end, 4e6)
check("циклическая иерархия панелей не вешает клиент", ok5, err5)
if not ok5 then print("     ↳ место зацикливания: " .. tostring(where5)) end

print(("\n=== ИТОГ: %d/%d, failures=%d ==="):format(total - fails, total, fails))
if fails > 0 then os.exit(1) end
