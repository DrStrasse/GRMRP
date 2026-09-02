--[[--------------------------------------------------------------------
    sim_chat_clocks — лента чата живёт на ОДНИХ часах (урок 03.09 вечер-6:
    «отправка есть, отрисовки нет ни по одному каналу» — возраст строки
    считался RealTime()-CurTime(), разница = аптайм машины, строки рождались
    мёртвыми). Контракт: штампы и возраст — CurTime(); серверные t из пакета
    для возраста НЕ используется; вызовов RealTime() в paint нет.
----------------------------------------------------------------------]]
local fails, total = 0, 0
local function check(name, cond, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "   " .. tostring(extra or "")) end
end
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

for _, pair in ipairs({
    { "gamemodes/grmrp/gamemode/modules/chat/cl_grmrp_chat_hud.lua", "GRMRPChat" },
    { "lua/autorun/client/cl_08_grm_chat_hud.lua", "GRMChat" },
}) do
    local path, ns = pair[1], pair[2]
    local s = read(path)
    check(ns .. ": paint на CurTime", s:find("local nowRT = CurTime()", 1, true) ~= nil)
    check(ns .. ": ноль вызовов RealTime()", s:find("= RealTime()", 1, true) == nil)
    check(ns .. ": входящая строка штампуется клиентским CurTime",
        s:find(ns .. ".AddLine(chanId, name, text, CurTime())", 1, true) ~= nil)
    check(ns .. ": серверное время читается, но в возраст не входит",
        s:find("net.ReadDouble()", 1, true) ~= nil
        and s:find("\n" .. ns .. ".AddLine(chanId, name, text, t)", 1, true) == nil)
    check(ns .. ": само-эхо на CurTime", s:find("name, text, CurTime(), true", 1, true) ~= nil)
end

print("\n=== 3. ЛЕНТА = DERMA-ПАНЕЛЬ (не HUDPaint) — вечер-9 ===")
for _, pair in ipairs({
    { "gamemodes/grmrp/gamemode/modules/chat/cl_grmrp_chat_hud.lua", "GRMRPChat" },
    { "lua/autorun/client/cl_08_grm_chat_hud.lua", "GRMChat" },
}) do
    local s2 = read(pair[1])
    check(pair[2] .. ": рисует EditablePanel", s2:find('vgui.Create("EditablePanel")', 1, true) ~= nil)
    check(pair[2] .. ": HUDPaint-хука ленты больше нет", s2:find('hook.Add("HUDPaint"', 1, true) == nil)
    check(pair[2] .. ": панель не перехватывает мышь и клавиши",
        s2:find("SetMouseInputEnabled(false)", 1, true) ~= nil
        and s2:find("SetKeyInputEnabled(false)", 1, true) ~= nil)
    check(pair[2] .. ": панель создаётся лениво из push",
        s2:find("ensureFeed() --", 1, true) ~= nil)
    check(pair[2] .. ": переклейка на смену размера экрана",
        s2:find('OnScreenSizeChanged", "' .. (pair[2] == "GRMRPChat" and "GRMRPChat_FeedPos" or "GRMChat_FeedPos") .. '"', 1, true) ~= nil
        or s2:find("OnScreenSizeChanged", 1, true) ~= nil)
end

print("\n=== 4. ОТТИСК СБОРКИ В ЛЕНТЕ + /chatdiag ===")
do
    local diag = {
        { "gamemodes/grmrp/gamemode/modules/chat/cl_grmrp_chat.lua", "GRMRPChat" },
        { "lua/autorun/client/cl_08_grm_chat_input.lua", "GRMChat" },
    }
    for _, pair in ipairs(diag) do
        local s2 = read(pair[1])
    check(pair[2] .. ": /chatdiag перехвачендо отправки", s2:find('"/chatdiag"', 1, true) ~= nil
        and s2:find(pair[2] .. ".Diagnose()", 1, true) ~= nil)
    end
    check("баннер вечер-12 в режиме", read("gamemodes/grmrp/gamemode/modules/chat/cl_grmrp_chat.lua")
        :find("сборка вечер-12 (03.09)", 1, true) ~= nil)
    check("баннер вечер-12 в порту", read("lua/autorun/client/cl_08_grm_chat_input.lua")
        :find("сборка вечер-12 (03.09)", 1, true) ~= nil)
    local hud1 = read("gamemodes/grmrp/gamemode/modules/chat/cl_grmrp_chat_hud.lua")
    local hud2 = read("lua/autorun/client/cl_08_grm_chat_hud.lua")
    check("режим: Diagnose печатает в ленту через AddLine", hud1:find("function GRMRPChat.Diagnose", 1, true) ~= nil
        and hud1:find('GRMRPChat.AddLine("ooc", "чат-диаг"', 1, true) ~= nil)
    check("порт: Diagnose синхронен", hud2:find("function GRMChat.Diagnose", 1, true) ~= nil
        and hud2:find('GRMChat.AddLine("ooc", "чат-диаг"', 1, true) ~= nil)
end

print("\n=== 5. РАЗМЕР И ПОЛОСЫ ЛЕНТЫ (вечер-10) ===")
for _, pair in ipairs({
    { "gamemodes/grmrp/gamemode/modules/chat/cl_grmrp_chat_hud.lua", "GRMRPChat" },
    { "lua/autorun/client/cl_08_grm_chat_hud.lua", "GRMChat" },
}) do
    local s2 = read(pair[1])
    check(pair[2] .. ": текст ленты 17px (жалоба «маленький»)",
        s2:find("size = 17, weight = 400", 1, true) ~= nil)
    check(pair[2] .. ": чип канала 15px", s2:find("size = 15, weight = 700", 1, true) ~= nil)
    check(pair[2] .. ": полоса меряется по факту (GetTextSize чипа)",
        s2:find('cw = surface.GetTextSize("[" .. tag .. "]")', 1, true) ~= nil)
    check(pair[2] .. ": фон строки — rounded, по ширине строки",
        s2:find("draw.RoundedBox(5, x - 8", 1, true) ~= nil)
    check(pair[2] .. ": акцент канала слева", s2:find("draw.RoundedBox(0, x - 8", 1, true) ~= nil)
    check(pair[2] .. ": старой гадалки «130 + tw» нет", s2:find("130 + tw", 1, true) == nil)
    check(pair[2] .. ": ленты шире (900px)", s2:find("math.min(900, ScrW() - 32)", 1, true) ~= nil)
    check(pair[2] .. ": Diagnose — вечер-12", s2:find("чат вечер-12 (03.09)", 1, true) ~= nil)
end

print("\n=== 6. ИСТОРИЯ/ХРАНЕНИЕ (вечер-12) ===")
for _, pair in ipairs({
    { "gamemodes/grmrp/gamemode/modules/chat/cl_grmrp_chat.lua", "GRMRPChat" },
    { "lua/autorun/client/cl_08_grm_chat_input.lua", "GRMChat" },
}) do
    local s2 = read(pair[1])
    check(pair[1] .. ": история не зовёт фантомный :Close()",
        s2:find("histPanel:Close()", 1, true) == nil and s2:find("win:Close()", 1, true) == nil)
    check(pair[1] .. ": история через Remove", s2:find("histPanel:Remove()", 1, true) ~= nil)
    check(pair[1] .. ": источник истории — архив, не кормовая лента",
        s2:find(pair[2] .. ".archive or " .. pair[2] .. ".lines", 1, true) ~= nil)
    check(pair[1] .. ": живое пополнение окна", s2:find("_HistRefr", 1, true) ~= nil)
end
for _, pair in ipairs({
    { "gamemodes/grmrp/gamemode/modules/chat/cl_grmrp_chat_hud.lua", "GRMRPChat" },
    { "lua/autorun/client/cl_08_grm_chat_hud.lua", "GRMChat" },
}) do
    local s2 = read(pair[1])
    check(pair[1] .. ": push пишет архив", s2:find(pair[2] .. ".archive, entry", 1, true) ~= nil)
    check(pair[1] .. ": строки несут wallT", s2:find("wallT = os.time()", 1, true) ~= nil)
    check(pair[1] .. ": архив на диске (DATA)", s2:find("grm_chat/archive.txt", 1, true) ~= nil)
    check(pair[1] .. ": чтение на старте", s2:find("loadArchive()", 1, true) ~= nil)
    check(pair[1] .. ": запись отложенная (dirty-флаг)", s2:find("_histDirty", 1, true) ~= nil)
end

print(("\nCHAT CLOCKS: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
