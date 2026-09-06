--[[ sim_chat_modules — runtime-стенд автозагрузчика и модулей grm_chat
    (веч.-21). Реальные файлы loader.lua и modules/* исполняются в двух
   Realm-прогонах (SERVER / CLIENT) с моками file/hook/net/timer/vgui.
    Проверяется: загрузка/изоляция, каталог, CompleteCandidates/MentionHit,
    mute-семантика с сохранением, join/leave cvar, completion state-machine
    (Shift+Tab → принять; Enter НЕ перехвачен — веч.-8). ]]
local fails, total = 0, 0
local function check(name, cond, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print(("  FAIL %-58s %s"):format(name, tostring(extra or ""))) end
end

local KEY_TAB, KEY_RIGHT, KEY_ESCAPE = 15, 106, 1

local function mkPanel(cls)
    local p = { __cls = cls, __dead = false, text = "" }
    function p:Remove() self.__dead = true end
    function p:Dock() end
    function p:SetTall(v) self.tall = v end
    function p:SetVisible(v) self.visible = v end
    function p:SetMouseInputEnabled() end
    function p:SetKeyboardInputEnabled() end
    function p:SetText(v) self.text = v end
    function p:GetValue() return self.text end
    function p:GetParent() return nil end
    function p:GetWide() return 400 end
    function p:SetFont() end
    function p:RequestFocus() self.focused = true end
    function p:SetCaretPos(v) self.caret = v end
    return p
end

local function newEnv(realm, fsRoot)
    local env = {
        SERVER = realm == "SERVER", CLIENT = realm == "CLIENT",
        KEY_TAB = KEY_TAB, KEY_RIGHT = KEY_RIGHT, KEY_ESCAPE = KEY_ESCAPE,
        istable = function(v) return type(v) == "table" end,
        isfunction = function(v) return type(v) == "function" end,
        isstring = function(v) return type(v) == "string" end,
        Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end,
        IsValid = function(v) return v ~= nil and v.__dead ~= false or v ~= nil end,
        ErrorNoHalt = function() end,
        print = print,
    }
    -- IsValid: для таблиц — «в живых», если не Remove()нуты
    env.IsValid = function(v) return type(v) == "table" and not v.__dead or v ~= nil end
    env.istable = function(v) return type(v) == "table" end
    env.isfunction = function(v) return type(v) == "function" end
    env.isstring = function(v) return type(v) == "string" end

    local hooks = {}
    env.hook = {
        Add = function(nm, name, fn) hooks[nm .. "|" .. name] = fn end,
        Run = function() end, Remove = function() end,
    }
    env._hooks = hooks
    local timers = {}
    env.timer = { Simple = function(_, fn) timers[#timers + 1] = fn end }
    env._timers = timers
    local sounds, sent = {}, {}
    env.surface = { PlaySound = function(f) sounds[#sounds + 1] = f end }
    env.net = { Start = function() end, WriteString = function(_, v) sent[v] = true end,
        WriteDouble = function() end, Broadcast = function() sent.broadcast = true end }
    env._sent = sent
    env._snd = sounds
    local cvars = {}
    local function mkCv(nm, def)
        cvars[nm] = { v = def, GetBool = function(s)
            return s.v == "1" or s.v == true end, GetFloat = function(s) return tonumber(s.v) or 0 end }
        return cvars[nm]
    end
    env.GetConVar = function(nm) return cvars[nm] end
    env.CreateConVar = mkCv
    env._cvars = cvars
    env.FCVAR_REPLICATED, env.FCVAR_NOTIFY, env.FCVAR_ARCHIVE = 1, 2, 4

    local wrote, dataFiles = {}, {}
    env.file = {
        Find = function(pattern)
            local dir = pattern:match("^(.*)/%*%.lua$")
            if not dir then return {}, {} end
            dir = dir:gsub("^grm_chat/", "")
            local pipe = io.popen("ls " .. fsRoot .. "/" .. dir .. " 2>/dev/null")
            local out = pipe:read("*a") or ""
            pipe:close()
            local files = {}
            for line in out:gmatch("[^\n]+") do
                if line:match("%.lua$") then files[#files + 1] = line end
            end
            return files, {}
        end,
        Exists = function(p) return dataFiles[p] ~= nil end,
        Read = function(p) return dataFiles[p] end,
        Write = function(p, c) dataFiles[p] = c; wrote[p] = c end,
    }
    env._dataFiles, env._wrote = dataFiles, wrote
    local csCount = 0
    env.AddCSLuaFile = function() csCount = csCount + 1 end
    env._cs = function() return csCount end

    local entries = {}
    env.vgui = {
        Create = function(cls, parent)
            local p = mkPanel(cls)
            if cls == "DTextEntry" then entries[#entries + 1] = p end
            return p
        end,
    }
    env._entries = entries
    env.DermaMenu = function()
        local m = { opts = {} }
        function m:AddOption(label, cb)
            local o = {}
            m.opts[#m.opts + 1] = { label = label, cb = cb, opt = o }
            o.SetFont = function() end
            return o
        end
        function m:Open() m.open = true end
        env._lastMenu = m
        return m
    end
    env.input = { IsShiftDown = function() return env._shift == true end }
    env.LocalPlayer = function() return env._me end

    env.include = function(path)
        local rel = path:gsub("^grm_chat/", "")
        local f = assert(io.open(fsRoot .. "/" .. rel, "rb"))
        local code = f:read("*a")
        f:close()
        local chunk = assert(loadstring(code, path))
        setfenv(chunk, env)
        chunk()
    end
    setmetatable(env, { __index = _G })
    return env
end

local CORE = [[
    GRMRPChat.RP = {
        me = { chan = "me" }, ["do"] = { chan = "me" },
        it = { chan = "me", echo = true }, try = { chan = "me", echo = true },
        roll = { chan = "dice", echo = true },
    }
    GRMRPChat.Channels = {
        y = { id = "y", title = "Крик", cmd = "y", scope = "range" },
        ooc = { id = "ooc", title = "OOC", cmd = "ooc", scope = "world" },
        me = { id = "me", title = "Отыгровка", cmd = "me", scope = "range" },
    }
    GRMRPChat.ExternalCommands = { admingive = true, lootsay = true }
    GRMRPChat.Sanitize = function(s) return tostring(s or "") end
    GRMRPChat.GetChannel = function(id) return GRMRPChat.Channels[id] end
    GRMRPChat.AddSystem = function(t)
        GRMRPChat._sys = GRMRPChat._sys or {}
        GRMRPChat._sys[#GRMRPChat._sys + 1] = t
    end
    GRMRPChat.BroadcastSystem = function(t)
        GRMRPChat._bc = GRMRPChat._bc or {}
        GRMRPChat._bc[#GRMRPChat._bc + 1] = t
    end
]]

local FS = "lua/grm_chat"

local function boot(realm)
    local env = newEnv(realm, FS)
    env.GRMRPChat = {}
    local pre = assert(loadstring(CORE, "core"))
    setfenv(pre, env)
    pre()
    env.GRMRPChat._bc = {}
    env.GRMRPChat._sys = {}
    local chunk = assert(loadfile(FS .. "/loader.lua"))
    setfenv(chunk, env)
    chunk()
    return env
end

print("\n=== SERVER: загрузчик, каталог, join/leave ===")
local sv = boot("SERVER")
local G = sv.GRMRPChat
check("shared-модуль загружен", G.Modules["sh_emotes"] and G.Modules["sh_emotes"].state == "loaded")
check("sv-модуль загружен", G.Modules["sv_joinleave"] and G.Modules["sv_joinleave"].state == "loaded")
check("cl-модули НЕ тронуты сервером", G.Modules["cl_mentions"] == nil)
check("AddCSLuaFile разослал модули", sv._cs() >= 2, sv._cs())
local cat = G.CatalogCommands({ emotes = true })
local byName = {}
for _, it in ipairs(cat) do byName[it.name] = it end
check("каталог: /me как отыгрыш", byName["/me"] and byName["/me"].kind == "отыгрыш")
check("каталог: /ooc как канал", byName["/ooc"] and byName["/ooc"].kind == "канал")
check("каталог: внешняя команда /admingive", byName["/admingive"] and byName["/admingive"].kind == "модуль")
check("каталог: локальная /emotes", byName["/emotes"] and byName["/emotes"].kind == "локально")
local cand = G.CompleteCandidates("/m", cat, 7)
check("complete('/m') → только /me", #cand == 1 and cand[1].name == "/me", #cand)
check("complete('текст') → пусто", #G.CompleteCandidates("привет", cat, 7) == 0)
check("mention: чужая строка с ником", G.MentionHit("Петя", "Вася", "ВАСЯ, подойди") == true)
check("mention: своя строка", G.MentionHit("Вася", "Вася", "Вася") == false)
check("mention: короткий ник игнор", G.MentionHit("Петя", "V", "V тут?") == false)

sv._me = { IsValid = function() return true end, Nick = function() return "Вася" end }
local spawn = sv._hooks["PlayerInitialSpawn|grm_chat.joinleave"]
spawn({ IsValid = function() return true end, Nick = function() return "Вася" end })
check("joinleave default off → молчим", #G._bc == 0 and #sv._timers == 0)
sv._cvars["grmrp_chat_joinleave"].v = "1"
spawn({ IsValid = function() return true end, Nick = function() return "Вася" end })
for _, fn in ipairs(sv._timers) do fn() end
check("joinleave on: приветствие в broadcast", #G._bc == 1 and G._bc[1]:find("присоединился") ~= nil, G._bc[1])
sv._hooks["PlayerDisconnect|grm_chat.joinleave"]({ IsValid = function() return true end, Nick = function() return "Вася" end })
check("joinleave on: прощание", #G._bc == 2 and G._bc[2]:find("покинул") ~= nil)

print("\n=== CLIENT: mute-каналы, mentions, completion, picker ===")
local cl = boot("CLIENT")
local C = cl.GRMRPChat
check("cl-модули загружены", C.Modules["cl_mentions"].state == "loaded"
    and C.Modules["cl_channels"].state == "loaded"
    and C.Modules["cl_completion"].state == "loaded"
    and C.Modules["cl_picker"].state == "loaded")
check("sv-модули не тронуты клиентом", C.Modules["sv_joinleave"] == nil)

local cc = cl._hooks["GRMRPChat_ClientCommand|grm_chat.channels"]
cl._me = { IsValid = function() return true end, Nick = function() return "Вася" end }
C.LocalPlayer = function() return cl._me end
local r = cc(cl._me, "/mute ooc")
check("/mute ooc → потреблён + в списке", r == true and C.MutedChannels.ooc == true)
check("/mute сохраняет на диск", cl._wrote["grm_chat_mutes.txt"] == "ooc", cl._wrote["grm_chat_mutes.txt"])
r = cc(cl._me, "/mute bogus")
check("/mute bogus → не сеть, а подсказка", r == true and C._sys and C._sys[#C._sys]:find("нет такого") ~= nil)
local msg = cl._hooks["GRMRPChat_Message|grm_chat.channels"]
local line = { chan = { id = "ooc" } }
msg(line)
check("подавленный канал → line.muted", line.muted == true)
line = { chan = { id = "y" } }
msg(line)
check("живой канал — не muted", line.muted == nil)
r = cc(cl._me, "/unmute ooc")
check("/unmute снимает", r == true and C.MutedChannels.ooc == nil)

local mline = { name = "Петя", text = "Вася, зайди в кабинет" }
cl._hooks["GRMRPChat_Message|grm_chat.mentions"](mline)
check("mention перекрасил и пометил", mline.color and mline.color.r == 255 and mline.mention == true)
check("mention дзынькнул", #cl._snd == 1)

local e2 = mkPanel("DTextEntry")
local eframe = mkPanel("EditablePanel")
cl._hooks["GRMRPChat_InputBuilt|grm_chat.completion"](eframe, e2)
e2.text = "/m"
if e2.OnTextChanged then e2:OnTextChanged(e2) end
cl._shift = true
e2.OnKeyCodeTyped(e2, KEY_TAB)
e2.OnKeyCodeTyped(e2, KEY_RIGHT)
check("Shift+Tab + Right → принято /me", e2.text == "/me ", e2.text)
check("completion НЕ трогает OnEnter (веч.-8)", e2.OnEnter == nil)

cl._hooks["GRMRPChat_InputBuilt|grm_chat.picker"](eframe, e2)
check("пикер: кнопка прицеплена к окну", eframe.grmChatPicker ~= nil
    and not eframe.grmChatPicker.__dead)
C.GetInputEntry = function() return e2 end
local pr = cl._hooks["GRMRPChat_ClientCommand|grm_chat.emotes_cmd"]
local rr = pr(cl._me, "/emotes")
check("/emotes → меню с отыгрышами", rr == true and cl._lastMenu
    and #cl._lastMenu.opts >= 5)
e2.text = ""
if cl._lastMenu and cl._lastMenu.opts[1] then
    cl._lastMenu.opts[1].cb()
    check("клик пункта вставляет команду и каретку",
        e2.text:sub(1, 1) == "/" and e2.caret == #e2.text, e2.text)
end

print(("\nCHAT MODULES: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
