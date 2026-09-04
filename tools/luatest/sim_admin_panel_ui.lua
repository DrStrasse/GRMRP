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

print(("\nADMIN PANEL UI: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
