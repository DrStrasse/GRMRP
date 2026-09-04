--[[ sim_chat_clocks — статические контракты библиотеки чата grm_chat
    (вечер-14: источник lua/grm_chat + байтовый близнец режима
    gamemode/lib/grm_chat). Секции: часы ленты (урок веч.-6), лента-панель
    (веч.-9), оттиск/диагностика, размеры (веч.-10), история/хранение
    (веч.-12), память ввода/окно (веч.-12.2), подавление чужих и шина
    модулей (веч.-13), архитектура библиотеки (веч.-14). ]]
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
local FILES = {
    core = { "lua/grm_chat/sh_core.lua", "gamemodes/grmrp/gamemode/lib/grm_chat/sh_core.lua" },
    sv = { "lua/grm_chat/sv_net.lua", "gamemodes/grmrp/gamemode/lib/grm_chat/sv_net.lua" },
    hud = { "lua/grm_chat/cl_hud.lua", "gamemodes/grmrp/gamemode/lib/grm_chat/cl_hud.lua" },
    inp = { "lua/grm_chat/cl_input.lua", "gamemodes/grmrp/gamemode/lib/grm_chat/cl_input.lua" },
}

print("\n=== 1/2. ЧАСЫ ЛЕНТЫ (CurTime, веч.-6) ===")
for _, path in ipairs(FILES.hud) do
    local s = read(path)
    check(path .. ": paint на CurTime", s:find("local nowRT = CurTime()", 1, true) ~= nil)
    check(path .. ": ноль вызовов RealTime()", s:find("= RealTime()", 1, true) == nil)
    check(path .. ": входящая строка штампуется клиентским CurTime",
        s:find("GRMRPChat.AddLine(chanId, name, text, CurTime())", 1, true) ~= nil)
    check(path .. ": серверное время читается, но в возраст не входит",
        s:find("net.ReadDouble()", 1, true) ~= nil
        and s:find("\nGRMRPChat.AddLine(chanId, name, text, t)", 1, true) == nil)
    check(path .. ": самотсвечение автора на CurTime",
        s:find("name, text, CurTime(), true", 1, true) ~= nil)
    check(path .. ": лента ДЕРЖИТСЯ открытым вводом/историей",
        s:find("INPUT_OPEN or GRMRPChat.HIST_OPEN", 1, true) ~= nil)
end

print("\n=== 3. ЛЕНТА = DERMA-ПАНЕЛЬ (веч.-9) ===")
for _, path in ipairs(FILES.hud) do
    local s = read(path)
    check(path .. ": рисует EditablePanel", s:find('vgui.Create("EditablePanel")', 1, true) ~= nil)
    check(path .. ": HUDPaint-хука ленты больше нет", s:find('hook.Add("HUDPaint"', 1, true) == nil)
    check(path .. ": панель не перехватывает мышь/клавиши",
        s:find("SetMouseInputEnabled(false)", 1, true) ~= nil
        and s:find("SetKeyInputEnabled(false)", 1, true) ~= nil)
    check(path .. ": панель ленива (из push)", s:find("ensureFeed()", 1, true) ~= nil)
    check(path .. ": переклейка на смену экрана",
        s:find("GRMRPChat_FeedPos", 1, true) ~= nil)
end

print("\n=== 4. ОТТИСК СБОРКИ + /chatdiag ===")
for _, path in ipairs(FILES.inp) do
    local s = read(path)
    check(path .. ": /chatdiag перехвачен до отправки",
        s:find('"/chatdiag"', 1, true) ~= nil and s:find("GRMRPChat.Diagnose()", 1, true) ~= nil)
    check(path .. ": баннер вечер-15", s:find("сборка вечер-16 (04.09)", 1, true) ~= nil)
end
for _, path in ipairs(FILES.hud) do
    local s = read(path)
    check(path .. ": Diagnose пишет в ленту",
        s:find("function GRMRPChat.Diagnose", 1, true) ~= nil
        and s:find('GRMRPChat.AddLine("ooc", "чат-диаг"', 1, true) ~= nil)
    check(path .. ": Diagnose — вечер-15", s:find("чат вечер-16 (04.09)", 1, true) ~= nil)
end

print("\n=== 5. РАЗМЕРЫ ЛЕНТЫ (веч.-10) ===")
for _, path in ipairs(FILES.hud) do
    local s = read(path)
    check(path .. ": текст 17px", s:find("size = 17, weight = 400", 1, true) ~= nil)
    check(path .. ": чип 15px", s:find("size = 15, weight = 700", 1, true) ~= nil)
    check(path .. ": полоса по факту (GetTextSize)",
        s:find('cw = surface.GetTextSize("[" .. tag .. "]")', 1, true) ~= nil)
    check(path .. ": фон rounded по ширине строки", s:find("draw.RoundedBox(5, x - 8", 1, true) ~= nil)
    check(path .. ": акцент канала слева", s:find("draw.RoundedBox(0, x - 8", 1, true) ~= nil)
    check(path .. ": старой гадалки «130 + tw» нет", s:find("130 + tw", 1, true) == nil)
    check(path .. ": ленты шире (900px)", s:find("math.min(900, ScrW() - 32)", 1, true) ~= nil)
end

print("\n=== 6. ИСТОРИЯ/ХРАНЕНИЕ (веч.-12) ===")
for _, path in ipairs(FILES.inp) do
    local s = read(path)
    check(path .. ": история не зовёт фантомный :Close()",
        s:find("histPanel:Close()", 1, true) == nil and s:find("win:Close()", 1, true) == nil)
    check(path .. ": история через Remove", s:find("histPanel:Remove()", 1, true) ~= nil)
    check(path .. ": источник истории — архив, не лента",
        s:find("GRMRPChat.archive or GRMRPChat.lines", 1, true) ~= nil)
    check(path .. ": живое пополнение окна", s:find("_HistRefr", 1, true) ~= nil)
    check(path .. ": ScrollToChild канон (не VBar:GetCanvas)",
        s:find("ScrollToChild", 1, true) ~= nil)
end
for _, path in ipairs(FILES.hud) do
    local s = read(path)
    check(path .. ": push пишет архив", s:find("GRMRPChat.archive, entry", 1, true) ~= nil)
    check(path .. ": строки несут wallT", s:find("wallT = os.time()", 1, true) ~= nil)
    check(path .. ": архив на диске (DATA)", s:find("grm_chat/archive.txt", 1, true) ~= nil)
    check(path .. ": чтение на старте", s:find("loadArchive()", 1, true) ~= nil)
    check(path .. ": запись отложенная (dirty)", s:find("_histDirty", 1, true) ~= nil)
end

print("\n=== 7. ПАМЯТЬ ВВОДА / ОКНО ЖИВОЕ (веч.-12.2) ===")
for _, path in ipairs(FILES.inp) do
    local s = read(path)
    check(path .. ": история ввода персистится", s:find("grm_chat/input.txt", 1, true) ~= nil)
    check(path .. ": чтение памяти на старте", s:find("loadInput()", 1, true) ~= nil)
    check(path .. ": обрезка 512 по UTF-8 границе", s:find("Utf8Cut", 1, true) ~= nil)
    check(path .. ": /clear чистит ленту, не архив",
        s:find('string.lower(text) == "/clear"', 1, true) ~= nil
        and s:find("ClearLines()", 1, true) ~= nil)
    check(path .. ": окно прилипает к низу (VBar-канон)",
        s:find("GetVBar()", 1, true) ~= nil and s:find("atBottom()", 1, true) ~= nil)
    check(path .. ": окно переживает смену разрешения", s:find("_HistSize", 1, true) ~= nil)
    check(path .. ": Y-вход единый (переехал из хвоста порта)",
        s:find('hook.Add("HUDKeyPress", "GRMRPChat_Y"', 1, true) ~= nil
        and s:find("GAMEMODE and GAMEMODE.__chatOwnsStartChat", 1, true) ~= nil)
end
check("ядро отдаёт Utf8Cut наружу",
    read(FILES.core[1]):find("GRMRPChat.Utf8Cut = utf8Clamp", 1, true) ~= nil)
for _, path in ipairs(FILES.hud) do
    local s = read(path)
    check(path .. ": флеш на Shutdown", s:find('"Shutdown"', 1, true) ~= nil
        and s:find("ArchiveFlush", 1, true) ~= nil)
    check(path .. ": ручная команда сохранения", s:find("grm_chat_save", 1, true) ~= nil)
    check(path .. ": очистка", s:find("grm_chat_clear", 1, true) ~= nil)
    check(path .. ": владение командами помечено (__cc)", s:find("GRMRPChat.__cc", 1, true) ~= nil)
    check(path .. ": таймер сохранений 20 с", s:find('_HistSave", 20, 0', 1, true) ~= nil)
    check(path .. ": diag знает про архив и диск", s:find("file.Size", 1, true) ~= nil)
    check(path .. ": hide ванильного чата — у библиотеки (единый хук)",
        s:find('hook.Add("HUDShouldDraw", "GRMRPChat_HideVanilla"', 1, true) ~= nil)
end

print("\n=== 8. ПОДАВЛЕНИЕ ЧУЖИХ + ШИНА МОДУЛЕЙ (веч.-13/14) ===")
do
    local core = read(FILES.core[1])
    check("core: SuppressForeignChat определена",
        core:find("function GRMRPChat.SuppressForeignChat()", 1, true) ~= nil)
    check("core: снимает GRM_RPChat*/GRMChat*, не трогая себя (GRMRPChat_*)",
        core:find('PREFIXES = { "GRMChat", "GRM_RPChat" }', 1, true) ~= nil
        and core:find("id:sub(1, #pat) == pat", 1, true) ~= nil
        and core:find("port == GRMRPChat then port = nil", 1, true) ~= nil)
    check("core: конкоманды режима не самоудаляются (__cc)",
        core:find("if not (GRMRPChat.__cc and GRMRPChat.__cc[c]) then", 1, true) ~= nil)
    local sv = read(FILES.sv[1])
    check("sv: единый вход PlayerSay с уступкой режиму",
        sv:find('hook.Add("PlayerSay", "GRMRPChat_Capture"', 1, true) ~= nil
        and sv:find("GAMEMODE and GAMEMODE.__chatOwnsPlayerSay", 1, true) ~= nil)
    check("sv: ре-ентерь guard", sv:find('if GRMRPChat._inExternal then return "" end', 1, true) ~= nil)
    check("sv: external-роутинг в цепочку", sv:find('hook.Run, "PlayerSay"', 1, true) ~= nil)
    check("sv: me-ветка + opts.echoAuthor", sv:find("opts and opts.echoAuthor == true", 1, true) ~= nil)
    check("sv: rpName/range из opts", sv:find("isstring(opts.rpName)", 1, true) ~= nil
        and sv:find("tonumber(opts.range)", 1, true) ~= nil)
    check("sv: includeAuthor реально добавляет автора",
        sv:find("if includeAuthor then table.insert(net_list, author) end", 1, true) ~= nil)
    check("sv: пустое RP-тело → подсказка", sv:find('опишите действие после команды', 1, true) ~= nil)
    check("sv: DeferToModules выведен (портов больше нет)",
        sv:find("DeferToModules", 1, true) == nil)
    check("ядро: pm резолвит имя вызовом метода", core:find("isfunction(ply.Name) then", 1, true) ~= nil)
    check("ядро: dead-канал имеет алиас /dead", core:find('cmd = "dead"', 1, true) ~= nil)
    check("инициализатор: __core-гард идемпотентности",
        core:find("GRMRPChat.__core then return end", 1, true) ~= nil)
    check("режим: shared больше не дублирует Enabled (переехал в ядро)",
        (function()
            local sh = read("gamemodes/grmrp/gamemode/shared.lua")
            return sh:find("function GRMRPChat.Enabled()", 1, true) == nil
                and sh:find("единая библиотека", 1, true) ~= nil
        end)())
    check("режим: init помечает владение say",
        read("gamemodes/grmrp/gamemode/init.lua"):find("GM.__chatOwnsPlayerSay = true", 1, true) ~= nil)
    check("режим: cl_init помечает StartChat и зовёт SuppressForeignChat",
        (function()
            local ci = read("gamemodes/grmrp/gamemode/cl_init.lua")
            return ci:find("GM.__chatOwnsStartChat = true", 1, true) ~= nil
                and ci:find("SuppressForeignChat", 1, true) ~= nil
        end)())
    check("шина GRM.RPBroadcast существует (единая для модулей, веч.-15 targeting)",
        read("lua/autorun/sh_grm_rpbridge.lua"):find("function GRM.RPBroadcast(ply, meText, targeting)", 1, true) ~= nil)
    check("шина: список владельцев",
        read("lua/autorun/sh_grm_rpbridge.lua"):find('CHAT_OWNERS = { "GRMRPChat", "GRMChat" }', 1, true) ~= nil)
    check("документы: вызов шины вместо трёх веток; EasyChat-вызовов нет",
        read("lua/autorun/sh_grm_documents.lua"):find("GRM.RPBroadcast(ply, meText, 400)", 1, true) ~= nil
        and read("lua/autorun/sh_grm_documents.lua"):find("EasyChat.", 1, true) == nil)
    check("образование: дубль вырезан, зовёт шину",
        read("lua/autorun/sh_grm_education.lua"):find("GRM.RPBroadcast(ply, meText, 400)", 1, true) ~= nil
        and read("lua/autorun/sh_grm_education.lua"):find("EasyChat.", 1, true) == nil)
    check("легаси-модули чата УДАЛЕНЫ (веч.-16; подавитель — для старых установок)",
        read("lua/autorun/sh_grm_rp_chat.lua") == nil
        and read("lua/autorun/sh_grm_chat_config.lua") == nil)
    check("sv: say-контракт потребления (строка не утекает движку)",
        sv:find('if #body == 0 and not (extra and GRMRPChat.RP[extra.cmd or ""]) then return "" end', 1, true) ~= nil
        and sv:find('return nil, #targets', 1, true) ~= nil)
    check("sv: молчание видно — подсказка «никто не слышит» с троттлом",
        sv:find("никто не слышит", 1, true) ~= nil and sv:find("soloHintT", 1, true) ~= nil)
    check("фабрика диспетчеров регистрирует команды модулей в реестр чата",
        read("lua/autorun/sh_01_grm_core.lua"):find("ns.RegisterExternalChatCommand", 1, true) ~= nil
        and read("lua/autorun/sh_01_grm_core.lua"):find("chatRegister(HANDLERS)", 1, true) ~= nil)
    check("Diagnose: строка про чужих владельцев есть",
        read(FILES.hud[1]):find("чужие владельцы чата:", 1, true) ~= nil)
    -- вечер-15: ни одна автоотыгровка не минует шину; старая net-легаси мертва
    local br = read("lua/autorun/sh_grm_rpbridge.lua")
    check("шина: привязка к GRM_RPChat_Msg ВЫРЕЗАНА (net-легаси мертва)",
        br:find('net.Start("GRM_RPChat_Msg")', 1, true) == nil)
    check("шина: адресность (Player/список/таблица) реализована",
        br:find("asTargets", 1, true) ~= nil and br:find("isplayer", 1, true) ~= nil)
    check("шина: rpName легенды пробрасывается",
        br:find("targeting.rpName", 1, true) ~= nil)
    check("sv: deliver умеет forcedTargets (явная аудитория)",
        sv:find("forcedTargets", 1, true) ~= nil and sv:find("opts and istable(opts.targets)", 1, true) ~= nil)
    check("nameplate: представление/предъявление — через шину, не ChatPrint-циклом",
        (function()
            local np = read("lua/autorun/sh_grm_nameplate.lua")
            return np:find('GRM.RPBroadcast(ply, "представляется окружающим."', 1, true) ~= nil
                and np:find('GRM.RPBroadcast(ply, "предъявляет вам документ."', 1, true) ~= nil
                and np:find('other:ChatPrint("* "', 1, true) == nil
                and np:find('target:ChatPrint("* "', 1, true) == nil
        end)())
    check("pcboard: meAction = шина (ручной радиус-цикл вырезан)",
        (function()
            local pb = read("lua/autorun/sh_grm_pcboard.lua")
            return pb:find("return GRM.RPBroadcast(actor, text, 355)", 1, true) ~= nil
                and pb:find('ply:ChatPrint("* "', 1, true) == nil
        end)())
    check("911: осмотр — шина",
        (function()
            local n9 = read("lua/autorun/sh_grm_911.lua")
            return n9:find('GRM.RPBroadcast(ply, "осматривает пострадавшего.", 355)', 1, true) ~= nil
                and n9:find('p:ChatPrint("* "', 1, true) == nil
        end)())
end

print("\n=== 9. АРХИТЕКТУРА БИБЛИОТЕКИ (веч.-14, по образцу EasyChat) ===")
do
    local loader = read("lua/autorun/grm_chat.lua")
    check("лоадер существует", loader ~= nil)
    if loader then
        check("лоадер: реестр модулей (EasyChat-style)",
            loader:find("MODULES_SHARED", 1, true) ~= nil
            and loader:find("MODULES_SERVER", 1, true) ~= nil
            and loader:find("MODULES_CLIENT", 1, true) ~= nil)
        check("лоадер: AddCSLuaFile+include по realm",
            loader:find("AddCSLuaFile(\"grm_chat/\" .. f)", 1, true) ~= nil
            and loader:find("include(\"grm_chat/\" .. f)", 1, true) ~= nil)
    end
    for _, name in ipairs({ "sh_grmrp_chat_core", "sv_grmrp_chat", "cl_grmrp_chat", "cl_grmrp_chat_hud" }) do
        local p = "gamemodes/grmrp/gamemode/modules/chat/" .. name .. ".lua"
        local s = read(p)
        check("форвардер тонкий: " .. name,
            s ~= nil and #s < 1200 and s:find('include("grm_chat/', 1, true) ~= nil
                and s:find('include("lib/grm_chat/', 1, true) ~= nil)
    end
    for key, pair in pairs(FILES) do
        local a, b = read(pair[1]), read(pair[2])
        check("бандл побайтово равен библиотеке: " .. key, a ~= nil and a == b)
    end
    for _, gone in ipairs({
        "lua/autorun/sh_08_grm_chat_core.lua", "lua/autorun/sv_08_grm_chat.lua",
        "lua/autorun/client/cl_08_grm_chat_input.lua", "lua/autorun/client/cl_08_grm_chat_hud.lua",
    }) do
        check("порт выведен: " .. gone, read(gone) == nil)
    end
    local core = read(FILES.core[1])
    check("алиас единого стола: GRMChat = GRMRPChat (без конвертации)",
        core:find("if not GRMChat then GRMChat = GRMRPChat end", 1, true) ~= nil)
    check("Net/Enabled живут в библиотеке",
        core:find('GRMRPChat.Net = { SAY = "grmrp/chat_say", MSG = "grmrp/chat_msg" }', 1, true) ~= nil
        and core:find("function GRMRPChat.Enabled()", 1, true) ~= nil)
    check("реalm-гарды в каждом файле",
        read(FILES.sv[1]):find("if not SERVER then return end", 1, true) ~= nil
        and read(FILES.hud[1]):find("if SERVER then return end", 1, true) ~= nil
        and read(FILES.inp[1]):find("if SERVER then return end", 1, true) ~= nil)
    check("ни одного упоминания *_08_grm_chat в боевом коде",
        (function()
            for _, pair in pairs(FILES) do
                for _, p in ipairs(pair) do
                    local s = read(p)
                    if s:find("_08_grm_chat", 1, true) then return false end
                end
            end
            return true
        end)())
end

print(("\nCHAT CLOCKS: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
