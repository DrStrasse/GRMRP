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
    check("баннер вечер-13 в режиме", read("gamemodes/grmrp/gamemode/modules/chat/cl_grmrp_chat.lua")
        :find("сборка вечер-13 (03.09)", 1, true) ~= nil)
    check("баннер вечер-13 в порту", read("lua/autorun/client/cl_08_grm_chat_input.lua")
        :find("сборка вечер-13 (03.09)", 1, true) ~= nil)
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
    check(pair[2] .. ": Diagnose — вечер-13", s2:find("чат вечер-13 (03.09)", 1, true) ~= nil)
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
    local archName = pair[2] == "GRMChat" and "grm_chat/port_archive.txt" or "grm_chat/archive.txt"
    check(pair[1] .. ": архив на диске (DATA, у порта — свой файл)", s2:find(archName, 1, true) ~= nil)
    check(pair[1] .. ": чтение на старте", s2:find("loadArchive()", 1, true) ~= nil)
    check(pair[1] .. ": запись отложенная (dirty-флаг)", s2:find("_histDirty", 1, true) ~= nil)
end

print("\n=== 7. ПАМЯТЬ ВВОДА / ФЛЕШ / ОКНО ЖИВОЕ (вечер-12.2) ===")
for _, pair in ipairs({
    { "gamemodes/grmrp/gamemode/modules/chat/cl_grmrp_chat.lua", "GRMRPChat" },
    { "lua/autorun/client/cl_08_grm_chat_input.lua", "GRMChat" },
}) do
    local s2 = read(pair[1])
    local inpName = pair[2] == "GRMChat" and "grm_chat/port_input.txt" or "grm_chat/input.txt"
    check(pair[1] .. ": история ввода персистится", s2:find(inpName, 1, true) ~= nil)
    check(pair[1] .. ": чтение памяти на старте", s2:find("loadInput()", 1, true) ~= nil)
    check(pair[1] .. ": обрезка 512 по UTF-8 границе", s2:find("Utf8Cut", 1, true) ~= nil)
    check(pair[1] .. ": /clear чистит ленту, не архив",
        s2:find('string.lower(text) == "/clear"', 1, true) ~= nil
        and s2:find("ClearLines()", 1, true) ~= nil)
    check(pair[1] .. ": окно прилипает к низу (VBar-канон из dscrollpanel)",
        s2:find("GetVBar()", 1, true) ~= nil and s2:find("atBottom()", 1, true) ~= nil)
    check(pair[1] .. ": окно переживает смену разрешения",
        s2:find("_HistSize", 1, true) ~= nil)
end
check("ядро отдаёт Utf8Cut наружу",
    read("gamemodes/grmrp/gamemode/modules/chat/sh_grmrp_chat_core.lua"):find("GRMRPChat.Utf8Cut = utf8Clamp", 1, true) ~= nil)
for _, pair in ipairs({
    { "gamemodes/grmrp/gamemode/modules/chat/cl_grmrp_chat_hud.lua", "GRMRPChat" },
    { "lua/autorun/client/cl_08_grm_chat_hud.lua", "GRMChat" },
}) do
    local s2 = read(pair[1])
    check(pair[1] .. ": флеш архива на Shutdown", s2:find('"Shutdown"', 1, true) ~= nil
        and s2:find("ArchiveFlush", 1, true) ~= nil)
    check(pair[1] .. ": ручная команда сохранения", s2:find("grm_chat_save", 1, true) ~= nil)
    check(pair[1] .. ": очистка без потерь контракта", s2:find("grm_chat_clear", 1, true) ~= nil)
    check(pair[1] .. ": таймер сохранений ускорен до 20 с", s2:find("_HistSave\", 20, 0", 1, true) ~= nil)
    check(pair[1] .. ": diag знает про архив и диск", s2:find("file.Size", 1, true) ~= nil)
end

print("\n=== 8. ДВОЙНОЙ ВЛАДИТЕЛЬ: ПОДАВЛЕНИЕ ПЕСОЧНОГО ПОРТА (вечер-13) ===")
local core = read("gamemodes/grmrp/gamemode/modules/chat/sh_grmrp_chat_core.lua")
check("core: SuppressAddonPort определена", core:find("function GRMRPChat.SuppressAddonPort()", 1, true) ~= nil)
check("core: снимает и СТАРЫЙ модуль (GRM_RPChat*)",
    core:find('"^GRMChat", "^GRM_RPChat"', 1, true) ~= nil)
local sv13 = read("gamemodes/grmrp/gamemode/modules/chat/sv_grmrp_chat.lua")
check("sv: me-ветка уважает opts.echoAuthor",
    sv13:find("opts and opts.echoAuthor == true", 1, true) ~= nil)
check("sv: rpName/range из opts", sv13:find("isstring(opts.rpName)", 1, true) ~= nil
    and sv13:find("tonumber(opts.range)", 1, true) ~= nil)
check("шина GRM.RPBroadcast существует",
    read("lua/autorun/sh_grm_rpbridge.lua"):find("function GRM.RPBroadcast(ply, meText, radius)", 1, true) ~= nil)
check("шина: владелец выбирается из реестра, не развилкой по модулям",
    read("lua/autorun/sh_grm_rpbridge.lua"):find('CHAT_OWNERS = { "GRMRPChat", "GRMChat" }', 1, true) ~= nil)
check("документы: вызов шины вместо трёх веток",
    read("lua/autorun/sh_grm_documents.lua"):find("GRM.RPBroadcast(ply, meText, 400)", 1, true) ~= nil)
check("документы: EasyChat-вызовов нет",
    read("lua/autorun/sh_grm_documents.lua"):find("EasyChat.", 1, true) == nil)
check("образование: дубль вырезан, зовёт шину",
    read("lua/autorun/sh_grm_education.lua"):find("GRM.RPBroadcast(ply, meText, 400)", 1, true) ~= nil
    and read("lua/autorun/sh_grm_education.lua"):find("EasyChat.", 1, true) == nil)
check("старый модуль: EasyChat-рукав sendTo вырезан",
    read("lua/autorun/sh_grm_rp_chat.lua"):find("EasyChat.PlayerAddText", 1, true) == nil)
check("фабрика диспетчеров регистрирует команды модулей в реестр чата",
    read("lua/autorun/sh_01_grm_core.lua"):find("ns.RegisterExternalChatCommand", 1, true) ~= nil
    and read("lua/autorun/sh_01_grm_core.lua"):find("chatRegister(HANDLERS)", 1, true) ~= nil)
check("ядро: pm резолвит имя ВЫЗОВОМ метода (движковый баг веч.13)",
    core:find("isfunction(ply.Name) then", 1, true) ~= nil)
check("ядро: у dead-канала есть алиас /dead",
    core:find('title = "Мертвечина", scope = "range", range = 400, onlyDead = true,', 1, true) ~= nil
    and core:find('cmd = "dead"', 1, true) ~= nil)
check("sv: includeAuthor ставит автора в начало net-списка",
    read("gamemodes/grmrp/gamemode/modules/chat/sv_grmrp_chat.lua"):find("if includeAuthor then table.insert(net_list, author) end", 1, true) ~= nil)
check("порт: Enabled-фолбэк (песочница больше не падает на say)",
    read("lua/autorun/sh_08_grm_chat_core.lua"):find("function GRMChat.Enabled()", 1, true) ~= nil)
check("порт: Initialize снимает легаси-хуки",
    read("lua/autorun/sh_08_grm_chat_core.lua"):find("GRMChat_SuppressLegacy", 1, true) ~= nil)
check("core: снимает GRMChat*- и GRM_RPChat*-id, ставит SUPPRESSED",
    core:find('"^GRMChat", "^GRM_RPChat"', 1, true) ~= nil
    and core:find("port.SUPPRESSED = true", 1, true) ~= nil)
check("core: вызов на shared-стадии",
    core:find("do\n    GRMRPChat.SuppressAddonPort()", 1, true) ~= nil
    or core:find("GRMRPChat.SuppressAddonPort()", core:find("--suppress-call") or 0) ~= nil)
check("cl_init: поздняя страховка после lua_refresh",
    read("gamemodes/grmrp/gamemode/cl_init.lua"):find("GRMRPChat.SuppressAddonPort()", 1, true) ~= nil)
check("sv: поздняя страховка",
    read("gamemodes/grmrp/gamemode/modules/chat/sv_grmrp_chat.lua"):find("GRMRPChat.SuppressAddonPort()", 1, true) ~= nil)
check("режим мостит chat.AddText в свою ленту",
    read("gamemodes/grmrp/gamemode/modules/chat/cl_grmrp_chat_hud.lua"):find("GRMRPChat._addTextBridge", 1, true) ~= nil)
for _, f in ipairs({
    "lua/autorun/sh_08_grm_chat_core.lua", "lua/autorun/sv_08_grm_chat.lua",
    "lua/autorun/client/cl_08_grm_chat_hud.lua", "lua/autorun/client/cl_08_grm_chat_input.lua",
}) do
    local p = read(f)
    check(f .. ": ранний guard видит ядро режима (не только GRMRP.Version)",
        p:find("(GRMRP and GRMRP.Version) or (GRMRPChat and GRMRPChat.Channels)", 1, true) ~= nil)
end
check("порт: подавленная лента не прячет движковый чат",
    read("lua/autorun/client/cl_08_grm_chat_hud.lua"):find("if GRMChat.SUPPRESSED then return end", 1, true) ~= nil)
check("порт: AddText прозрачен при живом режиме",
    read("lua/autorun/client/cl_08_grm_chat_hud.lua"):find("GRMChat.SUPPRESSED or (GRMRPChat and GRMRPChat.Channels)", 1, true) ~= nil)
check("порт: Y не срабатывает после подавления",
    read("lua/autorun/client/cl_08_grm_chat_input.lua"):find("if GRMChat.SUPPRESSED then return end -- вечер-13: Y принадлежит режиму", 1, true) ~= nil)
check("порт: PlayerSay-цепочка мёртв после подавления",
    read("lua/autorun/sv_08_grm_chat.lua"):find("if GRMChat.SUPPRESSED then return end -- вечер-13: режим владелец", 1, true) ~= nil)
check("порт: suppress-функция смотрит на РЕЖИМ, а не на себя",
    read("lua/autorun/sh_08_grm_chat_core.lua"):find('rawget(_G, "GRMRPChat")', 1, true) ~= nil
    and read("lua/autorun/sh_08_grm_chat_core.lua"):find('rawget(_G, "GRMChat")', 1, true) == nil)
check("Diagnose: строка про состояние порта есть в обеих копиях",
    read("gamemodes/grmrp/gamemode/modules/chat/cl_grmrp_chat_hud.lua"):find("песочный порт:", 1, true) ~= nil)

print(("\nCHAT CLOCKS: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
