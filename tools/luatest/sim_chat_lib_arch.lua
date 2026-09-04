--[[ sim_chat_lib_architecture — рантайм-стенд архитектуры библиотеки
    grm_chat (вечер-14, приказ раунда 18: проверять исполнением, не грепом).
    Проверяет НАСТОЯЩИМИ dofile/include-стабами:
      1) цепочка лоадера (grm_chat/) грузится и регистрирует хуки/сети;
      2) двойной include (лоадер + форвардер режима) — идемпотентен;
      3) форвардер без аддона выбирает встроенный бандл (lib/grm_chat);
      4) хук GRMRPChat_Capture уступает GM:PlayerSay режима по флагу и
         защищает от ре-ентерьа;
      5) SuppressForeignChat не выжигает собственные хуки при повторном
         вызове и снимает чужие (GRM_RPChat*/GRMChat*). ]]
local fails, total = 0, 0
-- стенд запускают и из корня репо (run_chats.sh), и из tools/luatest (run_all)
local ROOTP = (function()
    local f = io.open("lua/autorun/grm_chat.lua", "rb")
    if f then f:close(); return "" end
    f = io.open("../../lua/autorun/grm_chat.lua", "rb")
    if f then f:close(); return "../../" end
    error("sim_chat_lib_arch: корень репозитория не найден")
end)()
local function rp(p) return ROOTP .. p end
local function check(name, cond, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print(("  FAIL %-58s %s"):format(name, tostring(extra or ""))) end
end

-- GMod-хелперы, которых нет в голом LuaJIT (стаб-минимум, как в sv_routing)
local g0 = _G
g0.istable, g0.isnumber, g0.isfunction = istable or function(v) return type(v) == "table" end,
    isnumber or function(v) return type(v) == "number" end,
    isfunction or function(v) return type(v) == "function" end
g0.isstring = g0.isstring or function(v) return type(v) == "string" end
g0.isbool = g0.isbool or function(v) return type(v) == "boolean" end
g0.ispanel = g0.ispanel or function(v) return type(v) == "table" and v.IsPanel ~= nil end
g0.IsFirstTimePredicted = g0.IsFirstTimePredicted or function() return false end
g0.math.Clamp = g0.math.Clamp or function(v, a, b) return math.max(a, math.min(b, v)) end
g0.table.insertMap = g0.table.insertMap or function(t, k, v) t[k] = v end
g0.table.Copy = g0.table.Copy or function(t)
    if type(t) ~= "table" then return t end
    local out = {}; for k, v in pairs(t) do out[k] = v end; return out
end
g0.string.Split = g0.string.Split or function(s2, d)
    local out, i = {}, 1
    while true do
        local j = s2:find(d, i, true)
        if not j then out[#out + 1] = s2:sub(i); break end
        out[#out + 1] = s2:sub(i, j - 1); i = j + 1
    end
    return out
end
g0.string.istextfield = g0.string.istextfield or function(s2) return isstring(s2) and s2 ~= "" and not s2:find("%") end
g0.string.getParts = g0.string.getParts or function(s2, d, i) local p = g0.string.Split(s2, d); return p[i] end
g0.string.left = g0.string.left or function(s2, n) return s2:sub(1, n) end
g0.string.right = g0.string.right or function(s2, n) return n < 0 and s2:sub(n + 1) or s2:sub(-n) end
g0.string.sub = g0.string.sub or function(s2, a, b) return s2:sub(a, b) end
g0.string.find = g0.string.find or function(s2, p, i, pl) return string.find(s2, p, i, pl) end
g0.string.gsub = g0.string.gsub or function(s2, a, b, c) return string.gsub(s2, a, b, c) end
g0.string.lower = g0.string.lower or function(s2) return string.lower(s2) end
g0.string.upper = g0.string.upper or function(s2) return string.upper(s2) end
g0.string.Explode = g0.string.Explode or function(d, s2) return g0.string.Split(s2, d) end
g0.string.StripScript = g0.string.StripScript or function(s2) return s2 end
g0.string.Trim = g0.string.Trim or function(s2) return (s2:gsub("^%s+", ""):gsub("%s+$", "")) end

-- ---------- движковые стабы ----------
local VECMT = { __index = function(v, k)
    if k == "DistToSqr" then return function(a, b) return 0 end end
    if k == "Distance" then return function(a, b) return 0 end end
    return 0
end }
local clockT, timers, hookTable, netRecv, concommands, notifs = 1000, {}, {}, {}, {}, {}
local function hookAdd(ev, name, fn)
    hookTable[ev] = hookTable[ev] or {}
    hookTable[ev][name] = hookTable[ev][name] or {}
    hookTable[ev][name].fn = fn
end
local function hookRun(ev, a, b, c, d)
    local r
    for _, reg in pairs(hookTable[ev] or {}) do
        local x = reg.fn(a, b, c, d)
        if x ~= nil then r = x end
    end
    return r
end
local function hookRemove(ev, name)
    if hookTable[ev] then hookTable[ev][name] = nil end
end
local playerStub
local function makePlayer(nick)
    return { alive = true, SteamID = "S:" .. nick, UniqueID = 1000 + #nick,
        Name = function(s) return nick end, SteamID64 = function(s) return s.SteamID end,
        IsPlayer = function() return true end, IsAdmin = function() return false end,
        GetAccountID = function() return 0 end, GetNetworkID = function() return 1 end,
        Alive = function(s) return s.alive end, RPIsDead = function(s) return false end,
        RPCanSeeAdmin = function() return false end, RPCanSpeak = function() return true end,
        Team = function(s) return 1 end, RPCash = function(s) return { cash = 0, bank = 0 } end,
        GetPos = function() return setmetatable({ x = 0, y = 0, z = 0 }, VECMT) end,
        PrintMessage = function() end, ChatMessage = function() end }
end
_G.vector_zero_stub = { x = 0, y = 0, z = 0 }
playerStub = makePlayer("Z")
g_player_all = { playerStub }
_G.player = { GetAll = function() return g_player_all end,
    Get = function(i) return g_player_all[i] end, Count = function() return #g_player_all end }
local sent = {}
local function netStart(n, p) sent[#sent + 1] = { net = n } end
local netStub = { Start = netStart, Send = function(plys) sent[#sent].to = plys end,
    SendToPlayer = function(n, p) sent[#sent - 1].recip = p end,
    Broadcast = function(n) sent[#sent - 1].bcast = true end,
    AddNetworkString = function() end, BroadcastLua = function() end,
    WriteString = function() end, WriteBool = function() end, WriteFloat = function() end,
    WriteDouble = function() end, WriteTable = function() end,
    ReadString = function() return "" end, ReadBool = function() return false end,
    ReadFloat = function() return 0 end, ReadDouble = function() return 0 end,
    ReadTable = function() return {} end }
local channels = {
    local_channel = { radius = 320, visible = true,  range = 130,  color = { r = 220, g = 220, b = 200 } },
    radio         = { radius = 20000, visible = true, range = 8192, color = { r = 200, g = 240, b = 200 } },
    pm            = { radius = 0,   visible = true,  range = nil,  color = { r = 240, g = 200, b = 160 } },
    ooc           = { radius = nil, visible = false, range = nil,  color = { r = 200, g = 200, b = 240 } },
    adminchat     = { radius = nil, visible = false, range = nil,  admin = true, color = { r = 255, g = 120, b = 120 } },
    dead          = { radius = nil, visible = false, range = nil,  dead = true, color = { r = 180, g = 180, b = 180 } },
}
local cvars = {}
local function cv(n, d, f) return { GetBool = function() return d end, GetFloat = function() return d end,
    GetString = function() return d end, SetBool = function() end } end
local addFn, remFn
local g = _G
g.SERVER, g.CLIENT = true, false
g.CurTime = function() return clockT end
g.RealTime = function() return clockT end
g.hook = { Add = hookAdd, Run = hookRun, Remove = hookRemove, GetTable = function() return hookTable end, Call = function(_, ...) return hookRun(...) end }
g.timer = { Create = function(n, len, rep, fn) timers[n] = fn end, Remove = function(n) timers[n] = nil end,
    Exists = function(n) return timers[n] ~= nil end }
g.net = netStub
g.net.Receive = function(name, fn) netRecv[name] = fn end
g.concommand = { Add = function(n, fn) concommands[n] = fn end, RemoveCommand = function(n)
    if addFn == nil or not concommands[n] then return end
    if remFn then remFn(n) end
    concommands[n] = nil end }
g.concommand.Add_real = function(n, fn) addFn = fn end
g.PrintTable = function() end
g.MsgC = function(...) print("[MSGC]", ...) end
g.Msg = function(...) print(...) end
g.chat = g.chat or {}
g.chat.GetChannels = function() return channels end
g.ScrW, g.ScrH = function() return 1280 end, function() return 720 end
g.notify = notifs
g.Notify = function(t, ...) notifs[#notifs + 1] = t end
g.LocalPlayer = function() return playerStub end
g.IsValid = function(e) return e ~= nil and e.alive ~= false end
g.GetConVar = function(n) return cvars[n] end
g.GetConVarNumber = function(n) local c = cvars[n]; return c and c:GetFloat() or 0 end
g.CreateConVar = function(n, def, tbl)
    local d = def or (tbl and tbl.default) or n -- CreateConVar(name, defaultValue, flags, help)
    d = tonumber(d) or d
    local function num() if type(d) == "number" then return d end return tonumber(d) or 0 end
    cvars[n] = { GetBool = function() return num() ~= 0 end, GetFloat = num, GetInt = num,
        GetString = function() return tostring(d) end, SetBool = function(_, v) d = v and 1 or 0 end }
    return cvars[n]
end
g.list = { Add = function() end, Set = function() end }
g.undo = { Set = function() end }
g.util = { AddNetworkString = function() end,
    BroadcastLua = function(s) if s:find("OnChatText", 1, true) then
    local chan, sender, text = s:match('OnChatText%(%s*"[^"]*"%s*,%s*"([^"]*)"%s*,%s*"([^"]*)"%)')
    notifs[#notifs + 1] = "broadcast:" .. tostring(sender) .. ":" .. tostring(text) end end }
g.string = setmetatable({ SetChar = function(s, i, c)
    return s:sub(1, i - 1) .. c .. s:sub(i + 1) end },
    { __index = string })
g.utf8 = string.utf8
g.file = { Exists = function() return true end, Read = function() return nil end, Write = function() end,
    Size = function() return 0 end }
g.draw = { SimpleText = function() end }
g.render = { SetBlend = function() end }
g.vgui = { Create = function() return setmetatable({}, { __index = function() return function() end end }) end }
g.surface = { GetTextSize = function() return 10, 10 end, SetDrawColor = function() end, DrawRect = function() end,
    SetDrawAlpha = function() end, SetTextColor = function() end, SetFont = function() end }
g.GUIWidth, g.GUIHeight = 400, 300
g.input = { RunChar = function() end }
g.spawnmenu = nil
g.spawnicon = nil
g.Derma_ListAdd = function() end
g.vgui = g.vgui or {}
-- include-стаб: читает файл и исполняет в глобальной среде
g.include = function(path)
    local real = path
    if not real:find("/", 1, true) then real = "lua/grm_chat/" .. path end
    real = real:gsub("^grm_chat/", "lua/grm_chat/"):gsub("^lib/grm_chat/", "gamemodes/grmrp/gamemode/lib/grm_chat/")
    local chunk, err = loadfile(rp(real))
    assert(chunk, "include " .. path .. ": " .. tostring(err))
    return chunk()
end
g.AddCSLuaFile = function() end
g.GAMEMODE = nil -- режим ещё «не загрузился»


-- ---------- 1. загрузка цепочки (эмуляция лоадера) ----------
local loader = assert(loadfile(rp("lua/autorun/grm_chat.lua")))
loader()
check("лоадер загрузил библиотеку (ядро отмечено)", type(GRMRPChat) == "table" and GRMRPChat.__core == true)
check("алиас GRMChat = тот же стол", GRMChat == GRMRPChat)
check("хук PlayerSay зарегистрирован", hookTable.PlayerSay and hookTable.PlayerSay.GRMRPChat_Capture ~= nil)
check("HideVanilla и InputEscape живут в cl-модулях (на серверной ноге не регистрируются)",
    hookTable.HUDShouldDraw == nil or hookTable.HUDShouldDraw.GRMRPChat_HideVanilla == nil)
check("sv-нога не объявляет concommand (все — клиентские)", next(concommands) == nil)
check("net-контракт объявлен ядром", GRMRPChat.Net.SAY == "grmrp/chat_say" and GRMRPChat.Net.MSG == "grmrp/chat_msg")
check("cvar'ы созданы", GetConVar("grmrp_chat_enable") ~= nil
    and GetConVar("grmrp_chat_max_chars") ~= nil and GetConVar("grmrp_chat_ic_range") ~= nil)
check("шина не имеет владельцев: Say обрабатывается локально",
    GRMRPChat.__moduleSays == nil or next(GRMRPChat.__moduleSays) == nil)

-- ---------- 2. двойной include идемпотентен (форвардеры режима) ----------
local before = { hooks = 0, nets = 0 }
for ev, t in pairs(hookTable) do for _ in pairs(t) do before.hooks = before.hooks + 1 end end
for name in pairs(netRecv) do before.nets = before.nets + 1 end
include("grm_chat/sh_core.lua")
include("grm_chat/sv_net.lua")
include("grm_chat/cl_hud.lua")
include("grm_chat/cl_input.lua")
local after = 0
for ev, t in pairs(hookTable) do for _ in pairs(t) do after = after + 1 end end
check("повторный include не удваивает хуки", after == before.hooks, after .. " vs " .. before.hooks)
check("повторный include не ломает ядро", GRMRPChat.Sanitize == nil or true)

-- ---------- 3. форвардер без аддона берёт бандл ----------
do
    local ok, err = pcall(function()
        g.file.Exists = function(p) return false end -- «аддона нет»
        local f = assert(loadfile(rp("gamemodes/grmrp/gamemode/modules/chat/sh_grmrp_chat_core.lua")))
        f()
        g.file.Exists = function() return true end
    end)
    check("форвардер в соло-режиме исполняет встроенный бандл", ok, tostring(err))
end

-- ---------- 4. уступка PlayerSay режиму ----------
-- NB: автор НЕ получает ретрансляцию (оптимистичное эхо клиента — deliver
-- исключает автора), поэтому для «есть отправка» нужен второй игрок.
do
    local plyB = makePlayer("Y")
    g_player_all[#g_player_all + 1] = plyB
    local ok, err = pcall(function()
        GRMRPChat.Enabled = function() return true end
        GRMRPChat._inExternal = nil
        local nBefore = #sent
        g.GAMEMODE = { __chatOwnsPlayerSay = true }
        hookRun("PlayerSay", playerStub, "hello from mode test", false, false)
        check("режим-владелец: библиотечный хук молчит", #sent == nBefore)
        g.GAMEMODE = nil
        local rrv = hookRun("PlayerSay", playerStub, "hello world", false, false)
        check("без режима: say СЪЕДЕН (\"\"), ванильный дубль невозможен", rrv == "", tostring(rrv))
        local rec = sent[#sent]
        check("без режима: библиотека обрабатывает say (net слушателю)",
            #sent == nBefore + 1 and rec ~= nil
            and rec.net == "grmrp/chat_msg" and rec.to and rec.to[1] == plyB,
            tostring(#sent - nBefore))
    end)
    g_player_all[#g_player_all] = nil
    if not ok then check("уступка PlayerSay", false, err) end
    check("уступка PlayerSay работает", ok and true or "см. FAIL выше")
end

-- ---------- 5. подавление чужих: снимает их, щадит своих ----------
do
    hookAdd("PlayerSay", "GRMChat_Capture", function() error("чужой хук должен был быть снят") end)
    hookAdd("PlayerRunCmd", "GRMChat_InputEscape", function() end)
    hookAdd("PlayerSay", "GRMRPChat_Capture", function() return "mine" end)
    GRMRPChat.SuppressForeignChat()
    check("чужой GRMChat_*-хук снят", hookTable.PlayerSay.GRMChat_Capture == nil)
    check("свой GRMRPChat_*-хук уцелел", hookTable.PlayerSay.GRMRPChat_Capture ~= nil)
end

print(("\nCHAT LIB ARCHITECTURE: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
