--[[ sim_chat_quarantine — runtime-стенд стража веч.-20: грузит
    gamemodes/grmrp/gamemode/modules/chat/cl_a_grmrp_chat_guard.lua в чистом
    окружении с движковыми заглушками (file.Exists/file.Read/MsgC/isstring) и
    проверяет решение «старый аддон?» на четырёх боевых сценариях. ]]
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
local GUARD = "gamemodes/grmrp/gamemode/modules/chat/cl_a_grmrp_chat_guard.lua"
local src = read(GUARD)
check("страж найден", src ~= nil)

local POISONED = "GRMRPChat.__hud = true\np:SetBounds(8, 10, 900, 120)\n"
local POISONED2 = "p:SetKeyInputEnabled(false)\n"
local CLEAN = "GRMRPChat.__hud = true\np:SetPos(8, 10)\np:SetSize(900, 120)\n"

local function run(hudSrc, inpSrc, exists)
    local warned = 0
    local env = {
        isstring = isstring or function(v) return type(v) == "string" end,
        ipairs = ipairs, pcall = pcall, print = print, type = type,
        Color = function() return nil end,
        MsgC = function() warned = warned + 1 end,
        file = {
            Exists = function() return exists end,
            Read = function(path)
                if path == "grm_chat/cl_hud.lua" then return hudSrc end
                if path == "grm_chat/cl_input.lua" then return inpSrc end
                return nil
            end,
        },
    }
    env._G = env
    local f = loadstring(src)
    setfenv(f, env)
    f()
    return env.GRMRP.IsAddonChatStale(), warned
end

local stale, warned = run(POISONED, CLEAN, true)
check("яд SetBounds в cl_hud → карантин + предупреждение", stale == true and warned > 0)
stale, warned = run(CLEAN, POISONED2, true)
check("яд SetKeyInputEnabled в cl_input → карантин", stale == true and warned > 0)
stale, warned = run(CLEAN, CLEAN, true)
check("свежий аддон → НЕ карантин, молчит", stale == false and warned == 0)
stale, warned = run(nil, nil, false)
check("аддона нет вовсе (соло-режим) → не карантин", stale == false and warned == 0)
stale = run(nil, nil, true)
check("файл есть, но file.Read отдал nil → не гадаем", stale == false)

print(("\nQUARANTINE: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
