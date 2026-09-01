--[[ Живой прогон шапки над головой v3: режимы видимости имени, знакомства
     (представился / показал документ / пробил по базе), маскировка, номер
     гражданина по настройке, тег только на службе, особые приметы.
     Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_nameplate_runtime.lua ]]
SERVER, CLIENT = true, false
function AddCSLuaFile() end

local NOW = 100
function CurTime() return NOW end
function IsValid(v) return type(v) == "table" and v._valid ~= false end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isfunction(v) return type(v) == "function" end
function string.Trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
function string.Explode(sep, str)
    local out = {}
    for part in tostring(str):gmatch("[^" .. sep .. "]+") do out[#out + 1] = part end
    return out
end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function table.Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
bit = { bor = function(...) return 0 end }
FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY = 1, 2, 4

local CVARS = {}
function CreateConVar(name, default) CVARS[name] = tostring(default) return nil end
function GetConVar(name)
    if CVARS[name] == nil then return nil end
    return {
        GetString = function() return CVARS[name] end,
        GetFloat = function() return tonumber(CVARS[name]) or 0 end,
        GetBool = function() return CVARS[name] ~= "0" end,
    }
end

local FS = {}
file = { IsDir = function() return true end, CreateDir = function() end,
         Write = function(p, s) FS[p] = s end, Read = function(p) return FS[p] end,
         Exists = function(p) return FS[p] ~= nil end }

local function enc(v)
    local t = type(v)
    if t == "number" or t == "boolean" then return tostring(v) end
    if t == "string" then return string.format("%q", v) end
    local parts = {}
    if #v > 0 then for _, i in ipairs(v) do parts[#parts + 1] = enc(i) end return "[" .. table.concat(parts, ",") .. "]" end
    for k, i in pairs(v) do parts[#parts + 1] = string.format("%q", tostring(k)) .. ":" .. enc(i) end
    return "{" .. table.concat(parts, ",") .. "}"
end
local function dec(s)
    local pos = 1
    local function value()
        while s:sub(pos, pos):match("%s") do pos = pos + 1 end
        local c = s:sub(pos, pos)
        if c == "{" then
            pos = pos + 1 local out = {}
            if s:sub(pos, pos) == "}" then pos = pos + 1 return out end
            while true do
                local k = value() pos = pos + 1
                out[k] = value()
                local sep = s:sub(pos, pos) pos = pos + 1
                if sep == "}" then break end
            end
            return out
        elseif c == "[" then
            pos = pos + 1 local out = {}
            if s:sub(pos, pos) == "]" then pos = pos + 1 return out end
            while true do
                out[#out + 1] = value()
                local sep = s:sub(pos, pos) pos = pos + 1
                if sep == "]" then break end
            end
            return out
        elseif c == '"' then
            local i, out = pos + 1, {}
            while s:sub(i, i) ~= '"' do out[#out + 1] = s:sub(i, i) i = i + 1 end
            pos = i + 1 return table.concat(out)
        elseif s:sub(pos, pos + 3) == "true" then pos = pos + 4 return true
        elseif s:sub(pos, pos + 4) == "false" then pos = pos + 5 return false
        else
            local a, b = s:find("[%-%d%.]+", pos) pos = b + 1 return tonumber(s:sub(a, b))
        end
    end
    return value()
end
util = { AddNetworkString = function() end, TableToJSON = function(t) return enc(t) end,
         JSONToTable = function(s) return dec(s) end }

local hooks = {}
hook = {
    Add = function(name, id, fn) hooks[name] = hooks[name] or {} hooks[name][id] = fn end,
    Remove = function(name, id) if hooks[name] then hooks[name][id] = nil end end,
    Run = function(name, ...)
        for _, fn in pairs(hooks[name] or {}) do fn(...) end
    end,
}
timer = { Create = function() end, Simple = function() end }
concommand = { Add = function() end }

local netSent = {}
net = {
    Receive = function(name, fn) net["_" .. name] = fn end,
    Start = function(name) netSent[#netSent + 1] = { name = name } end,
    WriteString = function(v) netSent[#netSent].str = v end,
    WriteTable = function(t) netSent[#netSent].data = t end,
    Send = function(p) netSent[#netSent].to = p end,
}

local ALL = {}
player = { GetAll = function() return ALL end }

local function vec(x)
    local v = { x = x or 0, y = 0, z = 0 }
    function v:DistToSqr(o) return (self.x - o.x) ^ 2 end
    function v:Distance(o) return math.abs(self.x - o.x) end
    return v
end

GRM = { Identity = {}, Perf = {} }
GRM.Identity.CharacterKey = function(p)
    if IsValid(p) then return p._sid .. ":" .. (p._slot or "char1") end
    return tostring(p or "")
end

local function mkPlayer(sid, opts)
    opts = opts or {}
    local p = { _valid = true, _sid = sid, _slot = "char1", nw = {}, nwb = {}, chat = {}, pos = vec(opts.x or 0) }
    function p:IsPlayer() return true end
    function p:Nick() return opts.nick or "Ник" end
    function p:SteamID64() return self._sid end
    function p:GetNWString(k, d) local v = self.nw[k] if v == nil then return d end return v end
    function p:SetNWString(k, v) self.nw[k] = v end
    function p:GetNWBool(k, d) local v = self.nwb[k] if v == nil then return d end return v end
    function p:SetNWBool(k, v) self.nwb[k] = v end
    function p:GetPos() return self.pos end
    function p:ChatPrint(m) self.chat[#self.chat + 1] = m end
    function p:GetEyeTrace() return { Entity = self._aim } end
    function p:Alive() return opts.dead ~= true end
    p.nw.GRM_RPName = opts.name or ""
    ALL[#ALL + 1] = p
    return p
end

GRM.Documents = { Registry = { passports = {} } }
GRM.FactionDuty = { IsOnDuty = function(p) return p.nwb.GRM_FactionOnDuty == true end }
GRM.Audit = { Write = function() end }
GRM.Notify = function() end

assert(loadfile("lua/autorun/sh_grm_nameplate.lua"))()
local NP = GRM.Nameplate

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

local cop = mkPlayer("76561190000000001", { name = "Ганс Мюллер", x = 0 })
local civ = mkPlayer("76561190000000002", { name = "Курт Вебер", x = 50 })
local far = mkPlayer("76561190000000003", { name = "Отто Кёниг", x = 900 })
local COP, CIV, FAR = GRM.Identity.CharacterKey(cop), GRM.Identity.CharacterKey(civ), GRM.Identity.CharacterKey(far)
GRM.Documents.Registry.passports[CIV] = { gender = "Мужской" }
GRM.Documents.Registry.passports[FAR] = { gender = "Женский" }

print("\n=== 1. РЕЖИМЫ ВИДИМОСТИ ИМЕНИ ===")
ok(NP.Mode() == "docs", "по умолчанию имя скрыто до предъявления документа", NP.Mode())
CVARS["grm_nameplate_mode"] = "открытый режим"
ok(NP.Mode() == "docs", "мусор в конваре не ломает режим")
CVARS["grm_nameplate_mode"] = "open"
ok(NP.Mode() == "open", "режим open читается")
CVARS["grm_nameplate_mode"] = "docs"
ok(NP.NameVisible("open", false, false, false) == true, "в режиме open имя видно незнакомым")
ok(NP.NameVisible("docs", false, false, false) == false, "в режиме docs незнакомец скрыт")
ok(NP.NameVisible("docs", true, false, false) == true, "знакомому имя видно")
ok(NP.NameVisible("docs", false, true, false) == true, "госслужащему с допуском имя видно (если включено)")
ok(NP.NameVisible("docs", false, false, true) == true, "себя игрок видит всегда")
ok(NP.GovNames() == false, "показ имён госслужащим по умолчанию ВЫКЛЮЧЕН")
ok(NP.CidMode() == "gov", "номер по умолчанию виден только госслужащим")
ok(NP.IntroDist() == 200, "радиус «представиться» по умолчанию 200")

print("\n=== 2. ПОДПИСЬ НЕЗНАКОМЦА ===")
ok(NP.UnknownLabel(civ) == "Неизвестный (муж.)", "пол берётся из паспорта", NP.UnknownLabel(civ))
ok(NP.UnknownLabel(far) == "Неизвестная (жен.)", "женский вариант подписи")
ok(NP.UnknownLabel(cop) == "Неизвестный", "без паспорта — просто «Неизвестный»")
NP.Refresh(civ)
ok(civ.nw.GRM_UnknownLabel == "Неизвестный (муж.)", "подпись висит на игроке NW-строкой")

print("\n=== 3. ЗНАКОМСТВА ===")
ok(NP.Knows(COP, CIV) == false, "изначально никто никого не знает")
ok(NP.Knows(COP, COP) == true, "себя человек знает всегда")
ok(NP.Learn(cop, civ, "test") == true, "знакомство записывается")
ok(NP.Knows(COP, CIV) == true, "после знакомства имя открыто")
ok(NP.Knows(CIV, COP) == false, "знакомство ОДНОСТОРОННЕЕ (узнал один — знает один)")
ok(NP.Learn(cop, civ, "test") == false, "повторное знакомство не дублируется")
ok(NP.Learn(cop, cop, "test") == false, "сам с собой не знакомится")
ok(NP.Forget(cop, civ) == true and NP.Knows(COP, CIV) == false, "знакомство можно снять")

print("\n=== 4. ПРЕДСТАВИТЬСЯ ===")
civ.chat, far.chat, cop.chat = {}, {}, {}
ok(NP.Introduce(cop) == true, "команда «представиться» отработала")
ok(#civ.chat == 1 and civ.chat[1]:find("представляется", 1, true) ~= nil, "рядом стоящий услышал")
ok(NP.Knows(CIV, COP) == true, "услышавший запомнил имя")
ok(#far.chat == 0 and NP.Knows(FAR, COP) == false, "далёкий игрок не услышал и не запомнил")
cop.chat = {}
ok(NP.Introduce(cop) == false, "повтор в течение 5 секунд отбит")
NOW = NOW + 10
ok(NP.Introduce(cop) == true, "через паузу можно представиться снова")

print("\n=== 5. МАСКИРОВКА ===")
NP.Forget(civ, cop)
cop.nwb.IsMasked = true
cop.nw.MaskName = "Курьер Пауль"
civ.chat = {}
NOW = NOW + 10
NP.Introduce(cop)
ok(civ.chat[1]:find("Курьер Пауль", 1, true) ~= nil, "под легендой человек называет легенду", civ.chat[1])
ok(NP.Knows(CIV, COP) == false, "под легендой знакомство НЕ записывается — запомнили не того")
cop.nwb.IsMasked = false

print("\n=== 6. ПРЕДЪЯВЛЕНИЕ ДОКУМЕНТА ===")
NP.Forget(civ, cop)
cop._aim = civ
civ.chat, cop.chat = {}, {}
ok(NP.ShowDocument(cop) == true, "документ предъявлен")
ok(civ.chat[1]:find("предъявляет вам документ", 1, true) ~= nil, "цель видит РП-действие")
ok(NP.Knows(CIV, COP) == true, "цель узнала имя")
ok(NP.Knows(FAR, COP) == false, "посторонний имя НЕ узнал")
cop._aim = nil
cop.chat = {}
ok(NP.ShowDocument(cop) == false and cop.chat[1]:find("наведитесь", 1, true) ~= nil,
    "без цели команда честно отвечает")
cop._aim = far
far.pos = vec(900)
cop.chat = {}
ok(NP.ShowDocument(cop) == false, "издалека документ не покажешь")

print("\n=== 7. ОПОЗНАНИЕ ЧЕРЕЗ /pcboard ===")
NP.Forget(cop, civ)
hook.Run("GRM_PCBoardIdentified", cop, CIV, "police")
ok(NP.Knows(COP, CIV) == true, "пробитие по базе = сотрудник запомнил лицо")

print("\n=== 8. ОСОБЫЕ ПРИМЕТЫ ===")
ok(NP.Marks(CIV) == "", "по умолчанию примет нет")
NP.SetMarks(civ, "  Шрам   через  левую бровь  ")
ok(NP.Marks(CIV) == "Шрам через левую бровь", "приметы сохраняются без лишних пробелов", NP.Marks(CIV))
local long = string.rep("а", 400)
NP.SetMarks(civ, long)
ok(#NP.Marks(CIV) <= NP.MaxMarks, "длина примет ограничена", #NP.Marks(CIV))
NP.SetMarks(civ, "")
ok(NP.Marks(CIV) == "", "приметы можно стереть")

print("\n=== 9. ФЛАГ ДОПУСКА К БАЗЕ ===")
GRM.PCBoard = { PlayerLevel = function(p) return p == cop and "police" or "none" end }
cop.nwb.GRM_FactionOnDuty = true
NP.Refresh(cop)
NP.Refresh(civ)
ok(cop.nwb.GRM_GovAccess == true, "сотрудник на службе помечен как имеющий допуск")
ok(civ:GetNWBool("GRM_GovAccess", false) == false, "у гражданского флага допуска нет")
cop.nwb.GRM_FactionOnDuty = false
NP.Refresh(cop)
ok(cop.nwb.GRM_GovAccess == false, "вне службы флаг снимается")

print("\n=== 10. ХРАНЕНИЕ ===")
ok(NP.Save(true), "знакомства сохраняются в файл")
ok(NP.SaveMarks(true), "приметы сохраняются в файл")
NP.SetMarks(civ, "Татуировка на кисти")
NP.Save(true) NP.SaveMarks(true)
NP.Known, NP.MarksData = {}, {}
NP.Load()
ok(NP.Knows(COP, CIV) == true, "знакомства переживают перезагрузку")
ok(NP.Marks(CIV) == "Татуировка на кисти", "приметы переживают перезагрузку")
FS["grm_identity/acquaintance.json"] = "мусор, не json"
NP.Load()
ok(table.Count(NP.Known) == 0, "битый файл не роняет модуль")

print("\n=== 11. КОМАНДЫ ЧАТА ===")
local say = hooks["PlayerSay"] and hooks["PlayerSay"]["GRM_Nameplate_Chat"]
ok(isfunction(say), "команды зарегистрированы в PlayerSay")
ok(isfunction(hooks["PlayerSayTransform"] and hooks["PlayerSayTransform"]["GRM_Nameplate_ChatEC"]),
    "команды зарегистрированы и в PlayerSayTransform (EasyChat)")
ok(say(cop, "привет") == nil, "обычная реплика не перехватывается")
NOW = NOW + 20
ok(say(cop, "/представиться") == "", "команда /представиться работает")
cop._aim = civ
civ.pos = vec(50)
ok(say(cop, "/паспорт") == "", "команда /паспорт работает")
cop.chat = {}
ok(say(cop, "/знакомые") == "", "команда /знакомые работает")
ok(#cop.chat > 0, "список знакомых печатается")

print(("\nNAMEPLATE RUNTIME: %d/%d, провалов: %d"):format(total - fails, total, fails))
if fails > 0 then os.exit(1) end
