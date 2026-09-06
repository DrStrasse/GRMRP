--[[ sim_grmrp_console — контракт кастомной консоли режима (вечер-28,
    gamemodes/grmrp/gamemode/modules/ui/cl_grmrp_console.lua).

    Проверяется ДУБЛЬ информации старой «Консоли сервера» (lua/autorun
    cl_grm_admin_panel.lua) без переспорки за net-канал:
      1) модуль грузится без GRMRPMenu (автономность, клиент-only);
      2) приём — hook GRM_AdminConsoleLine; net.Receive на чужом канале
         ЗАПРЕЩЁН (один читатель буфера — второй съел бы пакет панели);
      3) формат блока несётся как есть (побайтовый дубль старой ленты);
      4) история AD.ConsoleLines проигрывается ровно один раз, в верном
         порядке, без задвоения перекрытого хвоста;
      5) колпак буфера CON.Cap (старая панель не чистила ленту вовсе);
      6) ввод: net.Start(имя из GRM.Admin.Net.CONSOLE) + WriteString(Trim);
         локального эха нет;
      7) без аддона — просмотр + ровно одна отговорка за сессию, не краш;
      8) read-only поля: только реальные методы движка (SetKbInput(false),
         карета в конец под guard'ом SetCaretPos);
      9) Close/Open: буфер переживает окно, история не задваивается.

    Запуск: ./.luabuild/lj/bin/luajit tools/luatest/sim_grmrp_console.lua
----------------------------------------------------------------------]]
local fails, total = 0, 0
local function check(name, cond, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print(("  FAIL %-58s %s"):format(name, tostring(extra or ""))) end
end
local function read(p)
    local f = io.open(p, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local SRC = "gamemodes/grmrp/gamemode/modules/ui/cl_grmrp_console.lua"
local src = read(SRC)
check("файл консоли на месте", src ~= nil)
if not src then os.exit(1) end

print("\n=== 0. СТАТИЧЕСКИЕ СТЕНЫ ===")
check("клиент-only", src:find("if SERVER then return end", 1, true) ~= nil)
check("приём только через широковещательный хук",
    src:find('hook.Add("GRM_AdminConsoleLine", "GRMRPConsole"', 1, true) ~= nil
    and src:find("net.Receive(", 1, true) == nil)
check("отправка — Start+WriteString (чужими чтецами не притворяемся)",
    src:find("net.WriteString(line)", 1, true) ~= nil)
check("движковая консоль не трогается (ни RunConsoleCommand, ни game.ConsoleCommand)",
    src:find("RunConsoleCommand", 1, true) == nil
    and src:find("game.ConsoleCommand", 1, true) == nil)
check("read-only — реальный приём, фантома SetReadOnly-вызова нет",
    src:find("out:SetKeyboardInputEnabled(false)", 1, true) ~= nil
    and src:find(":SetReadOnly(", 1, true) == nil)
check("имя канала берётся из реестра GRM.Admin.Net, а не строкой",
    src:find("names.CONSOLE", 1, true) ~= nil
    and src:find('net.Start("GRM_Admin_Console")', 1, true) == nil)

------------------------------------------------------------------ стенд
local function mkPanel(caretSupport)
    local p = { __panel = true, __value = "", __caret = nil, __sets = 0 }
    function p:SetText(v) p.__value = tostring(v) p.__sets = p.__sets + 1 end
    function p:GetValue() return p.__value end
    function p:SetKeyboardInputEnabled(v) p.__kb = v end
    if caretSupport ~= false then
        function p:SetCaretPos(n) p.__caret = n end
    end
    p.Remove = function(s) s.__removed = true end
    for _, k in ipairs({ "SetSize", "SetPos", "MakePopup", "Dock", "DockMargin",
        "SetMultiline", "SetFont", "SetPlaceholderText", "SetTextColor",
        "SetBackgroundColor", "RequestFocus", "SetWide", "SetTall",
        "SetPaintBackground" }) do
        p[k] = function() end
    end
    return p
end

local function buildWorld(opt)
    opt = opt or {}
    local W = {
        fonts = {}, hooks = {}, netLog = {}, panels = {},
        hist = opt.hist or {},
    }
    local ENV = {
        SERVER = false,
        ipairs = ipairs, pairs = pairs, tostring = tostring, tonumber = tonumber,
        type = type, pcall = pcall, error = error, print = print, select = select,
        table = table, os = os, rawset = rawset, rawget = rawget, next = next,
        string = setmetatable({ Trim = function(s)
            return (tostring(s):gsub("^%s+", ""):gsub("%s+$", ""))
        end }, { __index = string }),
        math = setmetatable({ Clamp = function(v, a, b)
            return v < a and a or (v > b and b or v)
        end }, { __index = math }),
        Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end,
        TEXT_ALIGN_LEFT = 0, TEXT_ALIGN_CENTER = 1, TEXT_ALIGN_RIGHT = 2,
        RIGHT = 3, BOTTOM = 4, TOP = 5, LEFT = 6, FILL = 7,
        COLOR = {},
        IsValid = function(x)
            return type(x) == "table" and rawget(x, "__panel") == true
                and not rawget(x, "__removed")
        end,
        isfunction = function(v) return type(v) == "function" end,
        istable = function(v) return type(v) == "table" end,
        isstring = function(v) return type(v) == "string" end,
        isnumber = function(v) return type(v) == "number" end,
        ScrW = function() return 1280 end,
        ScrH = function() return 720 end,
        surface = { CreateFont = function(n) W.fonts[n] = true end },
        draw = { RoundedBox = function() end, RoundedBoxEx = function() end,
            SimpleText = function() end, SetDrawColor = function() end,
            DrawOutlinedRect = function() end },
        hook = { Add = function(nm, cl, fn) W.hooks[cl] = fn end },
        vgui = { Create = function()
            local p = mkPanel(opt.caret ~= false)
            W.panels[#W.panels + 1] = p
            return p
        end },
        net = {
            Start = function(n) W.curMsg = { ch = n, str = nil, sent = false }
                W.netLog[#W.netLog + 1] = W.curMsg end,
            WriteString = function(s) if W.curMsg then W.curMsg.str = s end end,
            SendToServer = function()
                if W.curMsg then W.curMsg.sent = true end end,
        },
        GRM = opt.noAdmin and {} or {
            Admin = {
                Net = { CONSOLE = "GRM_Admin_Console",
                    CONSOLE_OUT = "GRM_Admin_ConsoleOut" },
                ConsoleLines = W.hist,
            },
        },
    }
    ENV._G = ENV
    local fn = assert(loadstring(src, SRC))
    setfenv(fn, ENV)
    local okL, errL = pcall(fn)
    W.loaded, W.loadErr = okL, errL
    W.ENV = ENV
    return W
end

-- Верная хронология старого меню: панель пишет в AD.ConsoleLines ДО
-- hook.Run (cl_grm_admin_panel.lua, buildConsole → onLine); пустых
-- пакетов сервер не шлёт — в историю идёт только непустая строка.
local function deliver(W, block)
    block = tostring(block or "")
    if block ~= "" then W.hist[#W.hist + 1] = block end
    local fn = W.hooks["GRMRPConsole"]
    if fn then fn(block) end
    return fn ~= nil
end

print("\n=== 1. ЗАГРУЗКА И ПОДПИСКА ===")
local W = buildWorld({})
check("модуль загрузился БЕЗ GRMRPMenu (автономность)", W.loaded, W.loadErr)
check("шрифт создан самим модулем (не одалживается у меню)",
    W.fonts["GRMRP_ConBody"] == true and W.fonts["GRMRP_ConSmall"] == true)
check("хук старой консоли подписан", W.hooks["GRMRPConsole"] ~= nil)
local CON = W.ENV.GRMRPConsole
check("CON.Cap = 600", CON.Cap == 600)
check("Channel() читает реестр GRM.Admin.Net", CON.Channel() == "GRM_Admin_Console")

print("\n=== 2. ЛЕНТА ДО ОТКРЫТИЯ: буфер живой, окна нет ===")
check("доставка прошла через хук", deliver(W, "L1 live"))
deliver(W, "")
check("без окна ни одна панель не создана", #W.panels == 0)
check("IsOpen false до открытия", CON.IsOpen() == false)

print("\n=== 3. ОТКРЫТИЕ: ИСТОРИЯ ПОД БУФЕРОМ, ПОРЯДОК ЦЕЛ ===")
-- H1 — строка, пришедшая ДО загрузки gamemode-скриптов (лежит только в
-- истории старой панели); L1 пришла через хук и осела в истории тоже
-- (deliver писал hist) — переигрывание не должно её дублировать.
table.insert(W.hist, 1, "H1")
local out, root
CON.Open()
root, out = CON.root, CON.out
check("поле вывода построено", out ~= nil and root ~= nil)
local outv = out:GetValue()
local nH1 = select(2, outv:gsub("H1", ""))
local nL1 = select(2, outv:gsub("L1 live", ""))
check("H1 ровно один раз, L1 ровно один раз (перекрытие убрано)",
    nH1 == 1 and nL1 == 1, outv)
check("порядок: H1 раньше L1", outv:find("H1", 1, true) < outv:find("L1 live", 1, true))
check("поле вывода read-only: клавиатура снята, мышь осталась", out.__kb == false)
check("карета в конце (multiline-прокрутка за каретой)", out.__caret == #outv,
    tostring(out.__caret))
check("IsOpen true после Open", CON.IsOpen() == true)
local panelCount = #W.panels
CON.Open()
check("повторный Open — no-op (окна не плодятся)", #W.panels == panelCount)

print("\n=== 4. ЖИВОЙ ДОГОН: append без пересборки ===")
local setsBefore = out.__sets
deliver(W, "L2 live")
check("новая строка дописана", (out:GetValue() or ""):find("L2 live", 1, true) ~= nil)
check("append — одно SetValue-обращение (ленту не пересобираем)",
    out.__sets == setsBefore + 1, out.__sets)
check("карета снова в хвосте", out.__caret == #out:GetValue())
setsBefore = out.__sets
deliver(W, "")
check("пустая вставка игнорируется", out.__sets == setsBefore)

print("\n=== 5. КОЛПАК БУФЕРА (600) ===")
local W5 = buildWorld({})
local C5 = W5.ENV.GRMRPConsole
C5.Open()
for i = 1, 650 do deliver(W5, "line" .. i) end
local v5 = C5.out:GetValue()
local seen = {}
for _, m in pairs(W5.panels) do
    for s in (m.__value or ""):gmatch("line%d+") do seen[s] = true end
end
check("L650 видна (младшие не съедены)", seen["line650"] == true)
check("line1 вытеснена колпаком", seen["line1"] == nil)
check("line51 в буфере (600-й с конца)", seen["line51"] == true)
local lineCount = (function()
    local s = v5:find("line51", 1, true)
    return s ~= nil
end)()
check("поле пересобрано после сдвига (rebuild, не гора хвостов)", lineCount)

print("\n=== 6. ОТПРАВКА ===")
W.netLog = {}
local setsPre = out.__sets
local okRun = CON.Run("  status  ")
check("Run возвращает true при живом канале", okRun == true)
local msg = W.netLog[1]
check("net.Start — имя из реестра", msg ~= nil and msg.ch == "GRM_Admin_Console")
check("строка тримминута", msg ~= nil and msg.str == "status")
check("SendToServer выполнен", msg ~= nil and msg.sent == true)
check("локального эха нет (поле вывода не тронуто)", out.__sets == setsPre)
check("Run(\"\") == false, пакетов нет", CON.Run("") == false and #W.netLog == 1)

print("\n=== 7. OnEnter ПОЛЯ ВВОДА ===")
W.netLog = {}
local inp = CON.input
inp.__value = " bans "
inp:OnEnter(inp.__value)
check("Enter: команда отправлена", #W.netLog == 1 and W.netLog[1].str == "bans")
check("Enter: поле очищено", inp.__value == "")

print("\n=== 8. БЕЗ АДДОНА: ПРОСМОТР + ОДНА ОТГОВОРКА ===")
local W3 = buildWorld({ noAdmin = true })
check("загрузился без GRM.Admin.Net", W3.loaded, W3.loadErr)
local C3 = W3.ENV.GRMRPConsole
check("Channel() = nil без аддона", C3.Channel() == nil)
C3.Open()
C3.Close()
C3.Open()
-- считаем ТОЛЬКО текущее окно: value закрытых панелей остаётся в стенде
local joined = C3.out and (C3.out:GetValue() or "") or ""
check("отговорка ровно одна за два открытия",
    select(2, joined:gsub("ДУБЛЬ ленты", "")) == 1, joined)
check("Run без канала: false и ни одного net.Start",
    C3.Run("status") == false and #W3.netLog == 0)
check("инструкция Run — про полный зип (без внешних URL)",
    (C3.out:GetValue() or ""):find("grm_full_code.zip", 1, true) ~= nil)

print("\n=== 9. CLOSE/OPEN: БУФЕР ПЕРЕЖИВАЕТ ОКНО ===")
local r9 = CON.root
CON.Close()
check("root удалён, IsOpen false", r9.__removed == true and CON.IsOpen() == false)
deliver(W, "L3 live")
CON.Open()
local out2 = CON.out
check("после пересоздания окна буфер цел (L2 и L3 видны)",
    (out2:GetValue() or ""):find("L2 live", 1, true) ~= nil
    and (out2:GetValue() or ""):find("L3 live", 1, true) ~= nil)
check("переигрывание истории НЕ задвоило L2 (replay однократен)",
    select(2, (out2:GetValue() or ""):gsub("L2 live", "")) == 1)

print("\n=== 10. ОТСУТСТВИЕ SetCaretPos — НЕ КРАШ ===")
local W4 = buildWorld({ caret = false })
local C4 = W4.ENV.GRMRPConsole
check("модуль загрузился", W4.loaded, W4.loadErr)
deliver(W4, "x")
local okOpen = pcall(C4.Open)
check("Open без SetCaretPos жив", okOpen)
check("append без SetCaretPos жив", pcall(function() deliver(W4, "y") end))
check("строки на месте и без кареты", (C4.out:GetValue() or ""):find("y", 1, true) ~= nil)

print("\n=== 11. ТОГГЛЕР ===")
local C6W = buildWorld({})
local C6 = C6W.ENV.GRMRPConsole
C6.Toggle()
local opened = C6.IsOpen()
C6.Toggle()
check("Toggle открывает и закрывает", opened and not C6.IsOpen())

print(string.format("\nGRM CONSOLE: %d/%d, провалов: %d", total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
