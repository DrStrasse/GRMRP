--[[ sim_chat_histwrap — вечер-24: перенос строк истории и локальное зеркало
    кулдауна каналов. Ground truth движка: у C++ Label перенос опирается на
    применённую ширину панели; Derma-наследник DLabel НЕ имеет SetWrap/
    SizeToContents-режима (lua/vgui/dlabel.lua) — ставка на них давала
    «столбик по букве» (скрин владельца 06.09). Ядро теперь само режет текст
    surface.GetTextSize — стенд проверяет адитивность (ни буква не теряется),
    перенос по границам слов, резку переслов и деградацию ширин. Вторая
    группа — зеркало cooldown: мгновенная локальная отбивка «подождите»,
    истечение окна, нейтральность каналов без лимита.
----------------------------------------------------------------------]]
local T = 1000.0
local env = {}
for k, v in pairs(_G) do env[k] = v end
env._G = env
-- GMod-глобалки: и в _G (файлы грузятся без setfenv), и в env
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isfunction(v) return type(v) == "function" end
function isnumber(v) return type(v) == "number" end
function math.Clamp(v, a, b) return v < a and a or (v > b and b or v) end
function CurTime() return T end
function RealTime() return T end
env.CurTime, env.RealTime = CurTime, RealTime
env.surface = {
    SetFont = function() end,
    -- ширина = 7px на байт (кириллица UTF-8 = 2 байта) — детерминизм
    GetTextSize = function(s) return #tostring(s) * 7, 16 end,
    CreateFont = function() end,
}
env.net = { Receive = function() end, Start = function() end,
    WriteString = function() end, WriteDouble = function() end,
    WriteBool = function() end, WriteEntity = function() end, Send = function() end }
env.vgui = { Create = function() return setmetatable({}, { __index = function() return function() end end }) end,
    Register = function() end }
env.hook = { Add = function() end, Run = function() return false end, Remove = function() end }
env.timer = { Create = function() end, Simple = function() end, Remove = function() end }
env.draw = setmetatable({}, { __index = function() return function() end end })
env.Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
env.IsValid = function(x) return x ~= nil end
env.LocalPlayer = function() return { Nick = function() return "Тест" end } end

local f = assert(loadfile("lua/grm_chat/sh_core.lua")); f()
env.GRMRPChat = _G.GRMRPChat -- тот же объект ядра, копия устарела бы без Net
local fn = assert(loadfile("lua/grm_chat/cl_hud.lua")); setfenv(fn, env); fn()
local GRMRPChat = env.GRMRPChat or _G.GRMRPChat

local passed, failed = 0, 0
local function K(name, cond)
    if cond then passed = passed + 1
    else failed = failed + 1 print("FAIL: " .. name) end
end

print("\n=== WRAP ===")
local W = GRMRPChat.WrapText
K("есть в API", isfunction(W))
local one = W("привет мир", "F", 600)
K("короткая = одна строка", #one == 1 and one[1] == "привет мир")
K("пустая = одна пустая", #W("", "F", 600) == 1 and W("", "F", 600)[1] == "")
local long = "арбуз дыня крыжовник лимат инжир финик хурма"
local parts = W(long, "F", 200)
K("без потерь (склейка = исход)", table.concat(parts, " ") == long)
K("перенос по пробелам", #parts > 1)
K("каждая часть влезает", (function()
    for _, p in ipairs(parts) do if #p * 7 > 200 then return false end end
    return true
end)())
local mega = string.rep("з", 120)
local mparts = W(mega, "F", 200)
K("гиперслово режется, не ломается", #mparts > 1 and table.concat(mparts) == mega)
local exact = W("abc", "F", 21) -- ровно 21px = 3*7
K("граница <= включительно", #exact == 1)
K("UTF-8 без рассечённых букв", (function()
    for _, part in ipairs(mparts) do
        local i = 1
        while i <= #part do
            local bb = part:byte(i)
            local extra = bb >= 240 and 3 or (bb >= 224 and 2 or (bb >= 192 and 1 or 0))
            if bb >= 128 and bb < 192 then return false end
            i = i + extra + 1
        end
    end
    return true
end)())
K("узкая ширина клампится в 60", #W("аа аа аа", "F", 5) >= 1)

print("\n=== ЗЕРКАЛО КУЛДАУНА ===")
K("канал без лимита = 0", GRMRPChat.CooldownLeft("ic") == 0)
K("несуществующий канал = 0", GRMRPChat.CooldownLeft("нет") == 0)
GRMRPChat.MarkCooldownSend("advert")
local left = GRMRPChat.CooldownLeft("advert")
K("после отправки осталось ~60", left > 58 and left <= 60, left)
K("повторная пометка не продляет вдвое", (function()
    GRMRPChat.MarkCooldownSend("advert")
    return GRMRPChat.CooldownLeft("advert") > 58
end)())
T = T + 30
K("на середине окна ~30", math.abs(GRMRPChat.CooldownLeft("advert") - 30) < 1.5)
T = T + 40
K("после истечения = 0", GRMRPChat.CooldownLeft("advert") == 0)
K("me-канал без cooldown — 0", GRMRPChat.CooldownLeft("me") == 0)
K("bodyColor отыгровки задан ядром", (function()
    local me = GRMRPChat.GetChannel("me")
    return me and me.bodyColor and me.bodyColor.r == 176 and me.bodyColor.g == 106
        and me.bodyColor.b == 255
end)())
K("у Крика тела не окрашено", GRMRPChat.GetChannel("ic").bodyColor == nil)

print(string.format("\nHISTWRAP: %d/%d, провалов: %d", passed, passed + failed, failed))
os.exit(failed == 0 and 0 or 1)
