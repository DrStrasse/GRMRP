--[[ sim_admin_panel_ui — контракт «никаких фантомных методов панелей»
     (вечер-10). Живые крахи 03.09 вечер-9 (присланы владельцем со стеками):
       1) cl_grm_admin_panel.lua:1389 attempt to call method 'SetReadOnly'
          (a nil value) — у DTextEntry нет SetReadOnly; по движковому
          garrysmod/lua/vgui/dtextentry.lua там SetEditable/SetDisabled/
          AllowInput. Вызов ронял всю сборку вкладки «Консоль» (builder).
       2) cl_grm_admin_panel.lua:1427 VBar:GetCanvas — VBar живёт у
          DScrollPanel (dscrollpanel.lua), у multiline DTextEntry его нет;
       3) cl_grmrp_chat.lua:126 — тот же класс: scroll.VBar:GetCanvas() в
          таймере истории (Timer Failed) — история открывалась и креша.
     Контракт стенда: по клиентскому коду запрещены вызовы phantom-методов;
     read-only вывод = SetKeyboardInputEnabled(false) (мышь остаётся —
     текст выделяется); автоскролл консоли = SetCaretPos (реальный метод);
     прокрутка истории = ScrollToChild (реальный метод DScrollPanel).
----------------------------------------------------------------------]]
local fails, total = 0, 0
local function check(name, cond, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "   " .. tostring(extra or "")) end
end
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end
local function has(s, n) return s:find(n, 1, true) ~= nil end

local files = {
    "lua/autorun/client/cl_grm_admin_panel.lua",
    "lua/autorun/client/cl_grm_hud.lua",
    "lua/grm_chat/cl_input.lua",
    "lua/grm_chat/cl_hud.lua",
    "gamemodes/grmrp/gamemode/modules/ui/cl_grmrp_menu.lua",
    "gamemodes/grmrp/gamemode/lib/grm_chat/cl_input.lua",
    "gamemodes/grmrp/gamemode/lib/grm_chat/cl_hud.lua",
}

print("\n=== 1. ЗАПРЕЩЁННЫЕ ФАНТОМЫ (все клиентские файлы) ===")
for _, p in ipairs(files) do
    local s = read(p)
    check(p .. ": нет :SetReadOnly(", not has(s, ":SetReadOnly("))
    check(p .. ": нет :SetKeyInputEnabled( (реально: SetKeyboardInputEnabled)",
        not has(s, ":SetKeyInputEnabled("))
    check(p .. ": нет VBar:GetCanvas(", not has(s, "VBar:GetCanvas("))
    check(p .. ": нет VBar:SetY(", not has(s, "VBar:SetY("))
end

print("\n=== 2. ЗАМЕНИЛИ ПРАВИЛЬНО (админка) ===")
do
    local adm = read("lua/autorun/client/cl_grm_admin_panel.lua")
    check("read-only лога — клавиатура off, мышь on",
        has(adm, "out:SetKeyboardInputEnabled(false)"))
    check("автоскролл консоли — SetCaretPos в конец",
        has(adm, "out:SetCaretPos(#"))
    check("SetCaretPos застрахован Existence-guard'ом", has(adm, "if out.SetCaretPos then"))
end

print("\n=== 3. ИСТОРИЯ ЧАТА (реальные API + размер) ===")
for _, pair in ipairs({
    { "lua/grm_chat/cl_input.lua", "scroll" },
    { "gamemodes/grmrp/gamemode/lib/grm_chat/cl_input.lua", "scroll" },
}) do
    local s2 = read(pair[1])
    check(pair[1] .. ": прокрутка — ScrollToChild(lastLine)",
        has(s2, "scroll:ScrollToChild(lastLine)"))
    check(pair[1] .. ": таймер guarded (scroll+lastLine+метод)",
        has(s2, "IsValid(scroll) and IsValid(lastLine) and isfunction(scroll.ScrollToChild)"))
    check(pair[1] .. ": окно истории крупное (62% экрана)",
        has(s2, "math.Clamp(ScrW() * 0.62, 760, 1400)"))
    check(pair[1] .. ": высота окна 72%", has(s2, "math.Clamp(ScrH() * 0.72, 480, 1120)"))
end

print("\n=== 4. RUNTIME: трейс владельца 04.09 (AddSystem→push→ensureFeed) ===")
-- Краш боевого клиента: ensureFeed звал фантом «SetKeyInputEnabled».
-- СТРИКТ-среда: vgui-панель отдаёт nil на фантомы движка (как реальный
-- GMod) — любой возврат к фантому роняет эту секцию, а не «зелёнёт».
do
    local isT = function(v) return type(v) == "table" end
    local PHANTOM = { SetKeyInputEnabled = true, SetReadOnly = true }
    local panelMT
    local function newPanel() return setmetatable({ __panel = true }, panelMT) end
    panelMT = { __index = function(p, k)
        if PHANTOM[k] then return nil end
        if rawget(p, k) ~= nil then return rawget(p, k) end
        if k == "GetChildren" then return function() return {} end end
        if k == "GetParent" then return function() return nil end end
        return function() return nil end
    end }

    local saved = {}
    local function G(k, v) saved[k] = rawget(_G, k) _G[k] = v end
    local curT = 1000
    G("SERVER", false) G("CLIENT", true)
    G("istable", isT) G("isstring", function(v) return type(v) == "string" end)
    G("isnumber", function(v) return type(v) == "number" end)
    G("isfunction", function(v) return type(v) == "function" end)
    G("IsValid", function(x) return isT(x) and x.__panel == true end)
    G("CurTime", function() return curT end)
    G("RealTime", function() return curT + 4e6 end)
    G("ScrW", function() return 1920 end) G("ScrH", function() return 1080 end)
    G("Color", function(r, g, b, a) return { r = r or 255, g = g or 255, b = b or 255, a = a or 255 } end)
    local noopM = setmetatable({}, { __index = function() return function() return nil end end })
    G("surface", noopM) G("draw", noopM)
    G("chat", { AddText = function() end })
    G("timer", { Create = function() end, Remove = function() end, Simple = function(_, f) f() end })
    G("concommand", { Add = function() end, Remove = function() end })
    G("hook", { Add = function() end, Remove = function() end, Run = function() end,
        GetTable = function() return {} end })
    local inbox = {}
    local recvs = {}
    G("net", { Receive = function(n, f) recvs[n] = f end,
        Start = function() end, End = function() end, Send = function() end,
        Broadcast = function() end,
        WriteString = function() end, WriteFloat = function() end,
        WriteDouble = function() end, WriteBool = function() end,
        WriteTable = function() end, WriteEntity = function() end,
        ReadString = function() return table.remove(inbox, 1) end,
        ReadDouble = function() return table.remove(inbox, 1) end,
        ReadFloat = function() return 0 end, ReadBool = function() return false end,
        ReadTable = function() return {} end, ReadEntity = function() return nil end })
    G("vgui", { Create = function() return newPanel() end,
        GetFocusPanel = function() return nil end })
    G("CreateConVar", function(n, d)
        return { GetFloat = function() return tonumber(d) or 0 end,
                 GetInt = function() return math.floor(tonumber(d) or 0) end,
                 GetBool = function() return (tonumber(d) or 0) ~= 0 end,
                 GetString = function() return tostring(d) end } end)
    G("GetConVar", function() return nil end)
    G("RunConsoleCommand", function() end)
    G("Notify", function() end)
    G("LocalPlayer", function() return nil end)
    G("GAMEMODE", { __chatOwnsStartChat = true })
    if not math.Clamp then math.Clamp = function(v, a, b) return math.max(a, math.min(b, v)) end end

    local ok, err = pcall(dofile, "lua/grm_chat/sh_core.lua")
    check("cl-среда: sh_core грузится на клиенте (без режима)", ok, err)
    ok, err = pcall(dofile, "lua/grm_chat/cl_hud.lua")
    check("cl: cl_hud грузится (net.Receive реестра)", ok, err)
    ok, err = pcall(function() GRMRPChat.EnsureFeed() end)
    check("cl: ensureFeed — ленту строит БЕЗ фантомов (краш 174:174)", ok, err)
    ok, err = pcall(function() GRMRPChat.AddSystem("проверка боевого пути") end)
    check("cl: AddSystem → push (путь трейса OpenInput→AddSystem)", ok, err)
    ok, err = pcall(function() GRMRPChat.AddLine("ooc", "Вася", "привет", CurTime()) end)
    check("cl: AddLine оверлей не падает", ok, err)
    ok, err = pcall(function()
        local feed = GRMRPChat.EnsureFeed()
        feed.Paint(feed, 900, 480)
    end)
    check("cl: Paint ленты (шрифт-фолбеки GetTextSize) без краха", ok, err)
    ok, err = pcall(function()
        inbox = { "ooc", "Вася", "привет", 999 }
        recvs[GRMRPChat.Net.MSG]()
    end)
    check("cl: приём grmrp/chat_msg → в ленту", ok, err)
    ok, err = pcall(function() chat.AddText("сторонний аддон пишет в чат") end)
    check("cl: chat.AddText-мост не крэшит", ok, err)
    local nLines = isT(GRMRPChat.lines) and #GRMRPChat.lines or -1
    check("cl: строки накапливаются (4: AddSystem/AddLine/net/мост)", nLines == 4, nLines)

    for k, v in pairs(saved) do _G[k] = v end
    GRMRPChat = nil
end

print(("\nADMIN PANEL UI: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
