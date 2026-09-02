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

print("\n=== САМОДИАГНОСТИКА /chatdiag (вечер-8) ===")
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
    local hud1 = read("gamemodes/grmrp/gamemode/modules/chat/cl_grmrp_chat_hud.lua")
    local hud2 = read("lua/autorun/client/cl_08_grm_chat_hud.lua")
    check("режим: Diagnose печатает в ленту через AddLine", hud1:find("function GRMRPChat.Diagnose", 1, true) ~= nil
        and hud1:find('GRMRPChat.AddLine("ooc", "чат-диаг"', 1, true) ~= nil)
    check("порт: Diagnose синхронен", hud2:find("function GRMChat.Diagnose", 1, true) ~= nil
        and hud2:find('GRMChat.AddLine("ooc", "чат-диаг"', 1, true) ~= nil)
end

print(("\nCHAT CLOCKS: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
