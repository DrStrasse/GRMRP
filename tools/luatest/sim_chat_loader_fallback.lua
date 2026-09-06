--[[ sim_chat_loader_fallback — веч.-27: форвардеры режима к чат-библиотеке
    переживают ЛЮБУЮ половину установки. Боевой лог владельца:
    «Couldn't include file 'lib\grm_chat\loader.lua'» — gamemode скопирован
    без папки lib/ (выборочная ручная копия), и каждый include бандла падал
    отдельной паникой. Контракт: include бандла только через проверку
    file.Exists(GAME); если библиотеки нет нигде — РОВНО одна инструкция
    ErrorNoHalt и тихая деградация (режим грузится дальше); если аддонский
    лоадер уже отработал (__loader) — бандл-ветку не трогаем вовсе.
    Стенд гоняет реальные тексты четырёх форвардеров в трёх мирах.
----------------------------------------------------------------------]]
local fails, total = 0, 0
local function check(name, cond, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "   " .. tostring(extra or "")) end
end
local DIR = "gamemodes/grmrp/gamemode/modules/chat/"

local function world(inc)
    local G = { included = {}, warned = {}, GRMRP = {}, GRMRPChat = {} }
    G.GRM = {
        LibInclude = function(rel)
            local full = "gamemodes/grmrp/gamemode/" .. rel
            if not (G.file.Exists(full, "GAME")) then return false end
            G.include(rel)
            return true
        end,
        LibChatMissing = function()
            G.ErrorNoHalt("[GRMRP] ВАЖНО: библиотека чата не найдена — распакуйте")
        end,
    }
    G.include = function(f) G.included[#G.included + 1] = f end
    G.ErrorNoHalt = function(...)
        local t = {}
        for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end
        G.warned[#G.warned + 1] = table.concat(t)
    end
    G.Msg = function() end
    G.engine = { ActiveGamemode = function() return "grmrp" end }
    G.isstring = function(v) return type(v) == "string" end
    G.isfunction = function(v) return type(v) == "function" end
    G.istable = function(v) return type(v) == "table" end
    G.file = {
        Exists = function(path, space)
            if space == "LUA" then return inc.addon and path:find("^grm_chat/") ~= nil end
            if space == "GAME" then
                return inc.bundle and path:find("^gamemodes/grmrp/gamemode/lib/grm_chat/") ~= nil
            end
            return false
        end,
    }
    return G
end

local function run(file_, G)
    local f = assert(io.open(DIR .. file_, "rb"))
    local raw = f:read("*a") f:close()
    local chunk = assert(loadstring(raw, file_))
    setfenv(chunk, G)
    return pcall(chunk)
end

local FILES = { "sh_grmrp_chat_core.lua", "cl_grmrp_chat.lua",
    "cl_grmrp_chat_hud.lua", "sv_grmrp_chat.lua" }

print("\n=== A. НИ аддона, НИ бандла: ни одной паники, одна инструкция ===")
for _, f in ipairs(FILES) do
    local G = world({ addon = false, bundle = false })
    local ok = run(f, G)
    check(f .. ": грузится без ошибки", ok)
    check(f .. ": include бандла НЕ зовётся", #G.included == 0)
    if f:find("chat_hud") or f == "sv_grmrp_chat.lua" then
        -- только лоадерные точки печатают инструкцию (ядро/инпут — молча skip)
        local hasWarn = false
        for _, w in ipairs(G.warned) do if w:find("библиотека чата не найдена") then hasWarn = true end end
        check(f .. ": инструкция на месте", hasWarn)
    else
        check(f .. ": без лишного шума", #G.warned == 0)
    end
end

print("\n=== B. Только бандл (соло gamemode-зип): подключаем lib ===")
for _, f in ipairs(FILES) do
    local G = world({ addon = false, bundle = true })
    local ok = run(f, G)
    check(f .. ": без ошибки", ok)
    local want = f:find("core") and "lib/grm_chat/sh_core.lua"
        or (f:find("cl_grmrp_chat%.") and "lib/grm_chat/cl_input.lua"
        or (f:find("chat_hud") and "lib/grm_chat/cl_hud.lua"
        or "lib/grm_chat/sv_net.lua"))
    local found = false
    for _, i in ipairs(G.included) do if i == want then found = true end end
    check(f .. ": incl " .. want, found, table.concat(G.included, ","))
    if f:find("chat_hud") or f == "sv_grmrp_chat.lua" then
        local w = 0
        for _, x in ipairs(G.warned) do if x:find("не найдена") then w = w + 1 end end
        check(f .. ": без инструкции (бандл есть)", w == 0)
    end
end

print("\n=== C. Живой аддон: берём LUA-копию, lib-лоадер не трогаем ===")
for _, f in ipairs(FILES) do
    local G = world({ addon = true, bundle = false })
    local ok = run(f, G)
    check(f .. ": без ошибки", ok)
    local first = G.included[1]
    check(f .. ": include grm_chat/…", first and first:find("^grm_chat/") ~= nil, tostring(first))
    local libUsed = false
    for _, i in ipairs(G.included) do if i:find("lib/", 1, true) then libUsed = true end end
    check(f .. ": записей lib/ нет", not libUsed)
end

print("\n=== D. Аддонский лоадер уже смонтировал: __loader — молчаливый skip ===")
do
    local G = world({ addon = false, bundle = false })
    G.GRMRPChat = { __loader = true }
    for _, f in ipairs({ "cl_grmrp_chat_hud.lua", "sv_grmrp_chat.lua" }) do
        local ok = run(f, G)
        check(f .. ": не падаем", ok)
        local w = 0
        for _, x in ipairs(G.warned) do w = w + 1 end
        check(f .. ": инструкции не нужны (чат жив от аддона)", w == 0)
        for _, i in ipairs(G.included) do
            if i:find("loader") then check(f .. ": lib-лоадер НЕ включаем", false) end
        end
    end
end

print("\n=== E. Стены веч.-27 ===")
local menuSrc = (function()
    local f = assert(io.open("gamemodes/grmrp/gamemode/modules/ui/cl_grmrp_menu.lua", "rb"))
    local s = f:read("*a") f:close() return s
end)()
check("меню: keyboard-захват снят (движковые бинды и ~ живы сами)",
    menuSrc:find("root:SetKeyboardInputEnabled(false)", 1, true) ~= nil)
check("меню: lua-прокси toggleconsole удалён (ULib-блока нет в пути)",
    menuSrc:find('RunConsoleCommand("toggleconsole")', 1, true) == nil
    and menuSrc:find("LookupKeyBinding", 1, true) == nil)
check("меню: оттиск веч.-27", menuSrc:find("вечер-27 (06.09)", 1, true) ~= nil)

print(string.format("\nLOADER FALLBACK: %d/%d, провалов: %d", total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
