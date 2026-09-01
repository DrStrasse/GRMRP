--[[ Живой прогон РП-имён (заказ владельца 21.08): длинные фамилии можно,
     эмодзи и цифры нельзя, чужое имя занять нельзя.
     Грузится РЕАЛЬНЫЙ lua/autorun/sh_grm_character.lua (SERVER=true).
     Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_char_names.lua ]]
local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

SERVER, CLIENT = true, false
function AddCSLuaFile() end
function ErrorNoHalt() end
function Msg() end
function MsgN() end
function IsValid(v) return type(v) == "table" and v._valid ~= false end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function isfunction(v) return type(v) == "function" end
function CurTime() return 100 end
function Entity() return { _valid = false } end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
function Vector(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
function Angle(p, y, r) return { p = p, y = y, r = r } end
FCVAR_ARCHIVE, HUD_PRINTTALK = 1, 3
function string.Trim(s) return (string.gsub(tostring(s or ""), "^%s*(.-)%s*$", "%1")) end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function table.Copy(t)
    if type(t) ~= "table" then return t end
    local o = {} for k, v in pairs(t) do o[k] = table.Copy(v) end return o
end
function table.Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end

local HOOKS = {}
hook = {
    Add = function(e, n, fn) HOOKS[e] = HOOKS[e] or {} HOOKS[e][n] = fn end,
    Remove = function() end,
    Run = function(e, ...) for _, fn in pairs(HOOKS[e] or {}) do local r = fn(...) if r ~= nil then return r end end end,
    Call = function(e, _, ...) return hook.Run(e, ...) end,
}
timer = { Simple = function(_, fn) if fn then fn() end end, Create = function() end,
          Remove = function() end, Exists = function() return false end }
local CMDS = {}
concommand = { Add = function(n, fn) CMDS[n] = fn end }
util = {
    AddNetworkString = function() end,
    TableToJSON = function() return "{}" end,
    JSONToTable = function() return {} end,
}
net = { Receive = function() end, Start = function() end, Send = function() end,
        WriteTable = function() end, ReadTable = function() return {} end,
        WriteString = function() end, ReadString = function() return "" end }
FILES = {}
file = {
    Exists = function(n) return FILES[n] ~= nil end,
    Read = function(n) return FILES[n] end,
    Write = function(n, t) FILES[n] = t end,
    Delete = function(n) FILES[n] = nil end,
    CreateDir = function() end,
}
local CONVARS = {}
function CreateConVar(name, def)
    local cv = { value = def }
    function cv:GetInt() return math.floor(tonumber(self.value) or 0) end
    function cv:GetBool() return tostring(self.value) ~= "0" end
    function cv:GetString() return tostring(self.value) end
    function cv:SetValue(v) self.value = v end
    CONVARS[name] = cv
    return cv
end
function GetConVar(n) return CONVARS[n] end
local PLAYERS = {}
player = { GetAll = function() return PLAYERS end, GetHumans = function() return PLAYERS end }
ents = { FindByClass = function() return {} end, Create = function() return { _valid = false } end }
GRM = { Notify = function() end, Audit = { Write = function() end },
        Net = { Guard = function() return true end } }

assert(loadfile("lua/autorun/sh_grm_character.lua"))()
local CH = GRM.Char

local function mkPly(sid, nick)
    local p = { _valid = true, _nw = {}, chat = "" }
    function p:IsPlayer() return true end
    function p:IsSuperAdmin() return true end
    function p:Nick() return nick end
    function p:SteamID64() return sid end
    function p:SetNWString(k, v) self._nw[k] = v end
    function p:GetNWString(k, d) return self._nw[k] or d or "" end
    function p:SetNWBool(k, v) self._nw[k] = v end
    function p:GetNWBool(k, d) local v = self._nw[k] if v == nil then return d end return v end
    function p:Freeze() end
    function p:ChatPrint(t) self.chat = self.chat .. t .. "\n" end
    function p:PrintMessage(_, t) self.chat = self.chat .. t .. "\n" end
    PLAYERS[#PLAYERS + 1] = p
    return p
end

print("\n=== 1. UTF-8 БЕЗ СЮРПРИЗОВ ===")
ok(CH.Len("Александр") == 9, "кириллица считается символами, а не байтами", CH.Len("Александр"))
ok(CH.IsLetter("Ё") and CH.IsLetter("ё") and CH.IsLetter("я") and CH.IsLetter("W"), "буквы опознаются")
ok(CH.IsLetter("7") == false and CH.IsLetter("!") == false, "цифры и знаки — не буквы")
ok(CH.IsLetter("😀") == false, "эмодзи — не буква")
ok(CH.UpperChar("ё") == "Ё" and CH.LowerChar("Я") == "я", "регистр кириллицы свой, не string.lower")
ok(CH.Lower("ГРЁННЕР") == "грённер", "строка целиком в нижний регистр", CH.Lower("ГРЁННЕР"))

print("\n=== 2. ЧТО РАЗРЕШЕНО ===")
local good = {
    "Александр Фон Грённер",
    "Мария Готтен-Фон-Штоцкая",
    "Иван Петров",
    "Jean-Luc Picard",
    "Пётр О'Брайен",
}
for _, n in ipairs(good) do
    local res, err = CH.ValidateName(n)
    ok(res == n, "принято: " .. n, err)
end
ok(CH.ValidateName("  иван   петров  ") == "Иван Петров", "лишние пробелы убираются, буквы поднимаются",
   tostring(CH.ValidateName("  иван   петров  ")))

print("\n=== 3. ЧТО ЗАПРЕЩЕНО ===")
local bad = {
    ["Иван😀 Петров"] = "эмодзи",
    ["Иван Петров228"] = "цифры",
    ["Ivan <admin>"] = "скобки и служебные символы",
    ["Иван"] = "одно слово без фамилии",
    ["Ив П"] = "слишком короткие части",
    ["Иван  -Петров"] = "разделители подряд",
    ["-Иван Петров"] = "разделитель в начале",
    ["Ааааа Петров"] = "четыре одинаковые буквы подряд",
    ["Иван Петров Сидоров Кузнецов Смирнов"] = "слишком много слов",
    ["Ии"] = "короче минимума",
    ["Александрррр"] = "одно слово и повтор",
    ["Иван Петровvvvvvvvvvvvvvvvvvvvvvvvv"] = "слишком длинная часть",
}
for n, why in pairs(bad) do
    local res, err = CH.ValidateName(n)
    ok(res == nil and isstring(err), "отклонено (" .. why .. "): " .. n, tostring(res))
end
ok(CH.ValidateName(("Я"):rep(40) .. " Петров") == nil, "имя длиннее 32 символов не проходит")

print("\n=== 4. КЛЮЧ СРАВНЕНИЯ ===")
ok(CH.NameKey("Мария Готтен-Фон-Штоцкая") == CH.NameKey("мария готтен фон штоцкая"),
   "регистр и дефисы не спасают от совпадения")
ok(CH.NameKey("Пётр Семёнов") == CH.NameKey("Петр Семенов"), "Ё и Е считаются одной буквой")
ok(CH.NameKey("Иван Петров") ~= CH.NameKey("Иван Сидоров"), "разные имена — разные ключи")

print("\n=== 5. ИМЯ ЗАНЯТО ===")
local a = mkPly("111", "A")
local b = mkPly("222", "B")
ok(CH.SetName(a, "Александр Фон Грённер") == true, "первый занял имя")
ok(a:GetNWString("GRM_RPName", "") == "Александр Фон Грённер", "имя разослано клиентам")
local okB, errB = CH.SetName(b, "александр фон грённер")
ok(okB == false and tostring(errB):find("занято", 1, true) ~= nil, "второй тем же именем не проходит", errB)
ok(CH.SetName(b, "Мария Готтен-Фон-Штоцкая") == true, "другое имя проходит")
ok(CH.SetName(a, "Александр Фон Грённер") == true, "своё же имя переустановить можно")
local sid, slot = CH.FindNameOwner("Мария Готтен-Фон-Штоцкая")
ok(sid == "222" and slot == "char1", "поиск владельца имени работает", tostring(sid) .. "/" .. tostring(slot))
ok(CH.FindNameOwner("Кто Тоневедомый") == nil, "свободное имя ничьё")

local okEmoji, errEmoji = CH.SetName(b, "Мария😀 Готтен")
ok(okEmoji == false and isstring(errEmoji), "сервер не принимает эмодзи даже мимо окна", errEmoji)

print("\n=== 6. ВЫКЛЮЧАТЕЛЬ И КОМАНДА ===")
ok(isfunction(CMDS["grm_name_owner"]), "команда grm_name_owner объявлена")
a.chat = ""
CMDS["grm_name_owner"](a, nil, { "Мария", "Готтен-Фон-Штоцкая" })
ok(a.chat:find("занято", 1, true) ~= nil, "команда показывает владельца", a.chat)
a.chat = ""
CMDS["grm_name_owner"](a, nil, { "Никто", "Ничей" })
ok(a.chat:find("свободно", 1, true) ~= nil, "и свободное имя тоже", a.chat)
CONVARS["grm_name_unique"]:SetValue("0")
ok(CH.SetName(b, "Александр Фон Грённер") == true, "с выключенным конваром дубли разрешены")
CONVARS["grm_name_unique"]:SetValue("1")

print(("\nCHAR NAMES: %d/%d, провалов: %d"):format(pass, pass + fail, fail))
if fail > 0 then os.exit(1) end
