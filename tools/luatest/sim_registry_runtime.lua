--[[ Живой прогон реестра номеров: выдача PID/CID, префиксы, уникальность,
     архив, разбор запросов и поиск.
     Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_registry_runtime.lua ]]
SERVER, CLIENT = true, false
function AddCSLuaFile() end

function CurTime() return 100 end
function IsValid(v) return type(v) == "table" and v._valid ~= false end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isfunction(v) return type(v) == "function" end
function string.Trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
function string.Explode(sep, str) local o = {} for p in tostring(str):gmatch("[^" .. sep .. "]+") do o[#o+1] = p end return o end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function table.Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
function table.concat_safe(t, sep, i, j) return table.concat(t, sep, i, j) end

local FS = {}
file = { IsDir = function() return true end, CreateDir = function() end,
         Write = function(p, s) FS[p] = s end, Read = function(p) return FS[p] end,
         Exists = function(p) return FS[p] ~= nil end }

-- Мини-JSON.
local function enc(v)
    local t = type(v)
    if t == "number" or t == "boolean" then return tostring(v) end
    if t == "string" then return string.format("%q", v) end
    local parts = {}
    if #v > 0 then for _, i in ipairs(v) do parts[#parts+1] = enc(i) end return "[" .. table.concat(parts, ",") .. "]" end
    for k, i in pairs(v) do parts[#parts+1] = string.format("%q", tostring(k)) .. ":" .. enc(i) end
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
        elseif c == '"' then
            local i, out = pos + 1, {}
            while s:sub(i, i) ~= '"' do out[#out+1] = s:sub(i, i) i = i + 1 end
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
         JSONToTable = function(s) return dec(s) end, SteamIDFrom64 = function(x) return "STEAM:" .. tostring(x) end }
hook = { Add = function() end, Run = function() end }
timer = { Create = function() end, Simple = function() end }
concommand = { Add = function() end }
net = { Receive = function() end }
player = { GetAll = function() return {} end }
GRM = { Identity = {}, Perf = {} }
GRM.Identity.AccountKey = function(p) return IsValid(p) and p._sid or tostring(p or "") end
GRM.Identity.CharacterKey = function(p)
    if IsValid(p) then return p._sid .. ":" .. (p._slot or "char1") end
    return tostring(p or "")
end
GRM.Identity.IsCharacterKey = function(v) return isstring(v) and v:match("^%d+:char[1-3]$") ~= nil end

-- Ядро GRM (sh_00_grm_ui + sh_01_grm_core) — как на сервере, до модулей.
dofile("tools/luatest/lib_grm_core.lua")()
assert(loadfile("lua/autorun/sh_grm_registry.lua"))()
local R = GRM.Registry

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

local function mkPlayer(sid, slot, rpName)
    local p = { _valid = true, _sid = sid, _slot = slot or "char1", nw = {} }
    function p:IsPlayer() return true end
    function p:Nick() return "Nick" .. sid:sub(-2) end
    function p:SteamID64() return self._sid end
    function p:GetNWString(k, d) local v = self.nw[k] if v == nil then return d end return v end
    function p:SetNWString(k, v) self.nw[k] = v end
    if rpName then p.nw.GRM_RPName = rpName end
    return p
end

print("\n=== 1. ФОРМАТ НОМЕРОВ ===")
ok(R.Format("ГР", 4821) == "ГР-4821", "номер печатается с префиксом", R.Format("ГР", 4821))
ok(R.Format("ИГ", 42) == "ИГ-0042", "номер добивается нулями до 4 знаков", R.Format("ИГ", 42))
ok(R.Format("ГР", 0) == "", "нулевой номер не печатается")
local pre, num = R.Parse("ГР-4821")
ok(pre == "char" and num == 4821, "разбор «ГР-4821» (кириллический префикс распознан)", tostring(pre))
local _, num2 = R.Parse("4821")
ok(num2 == 4821, "разбор голого числа")
local pre3, num3 = R.Parse("гр 1000")
ok(pre3 == "char" and num3 == 1000, "разбор в нижнем регистре и с пробелом", tostring(pre3))
ok(select(1, R.Parse("gr-1000")) == "char", "принимается латинская раскладка GR")
ok(select(1, R.Parse("ig1000")) == "account", "принимается латинская раскладка IG")
ok(R.Lower("Курт Вебер") == "курт вебер", "регистронезависимый привод кириллицы", R.Lower("Курт Вебер"))
ok(R.Parse("не номер") == nil, "мусор не превращается в номер")

print("\n=== 2. ВЫДАЧА ===")
local a = mkPlayer("76561190000000001", "char1", "Ганс Мюллер")
local cidA, pidA = R.Sync(a)
ok(cidA == "ГР-1000" and pidA == "ИГ-1000", "первому игроку и персонажу выданы номера с 1000", cidA .. " " .. pidA)
ok(a.nw.GRM_CID == cidA and a.nw.GRM_PID == pidA, "номера повешены на игрока NW-строками")

local cidAgain = R.Sync(a)
ok(cidAgain == cidA, "повторный вход не выдаёт новый номер")

a._slot = "char2"
local cidA2 = R.Sync(a)
ok(cidA2 == "ГР-1001", "второй персонаж того же игрока получил свой номер", cidA2)
ok(R.PID(a) == pidA, "номер ИГРОКА при смене персонажа не меняется")

local b = mkPlayer("76561190000000002", "char1", "Курт Вебер")
local cidB, pidB = R.Sync(b)
ok(cidB == "ГР-1002" and pidB == "ИГ-1001", "второму игроку — свои номера", cidB .. " " .. pidB)

print("\n=== 3. ПОИСК ===")
local key, rec = R.ByCID("ГР-1002")
ok(key == "76561190000000002:char1" and rec.name == "Курт Вебер", "поиск персонажа по номеру")
ok(select(1, R.ByCID("ИГ-1002")) == nil, "чужой префикс не находит персонажа")
local akey = R.ByPID("ИГ-1001")
ok(akey == "76561190000000002", "поиск аккаунта по номеру игрока")

local rKey, rRec, rAcc = R.Resolve("ГР-1000")
ok(rKey == "76561190000000001:char1" and rAcc == "76561190000000001", "Resolve по номеру персонажа")
local _, _, accByPid = R.Resolve("ИГ-1001")
ok(accByPid == "76561190000000002", "Resolve по номеру игрока даёт аккаунт")
local nameKey = R.Resolve("курт")
ok(nameKey == "76561190000000002:char1", "Resolve по части имени")
ok(R.Resolve("несуществующий") == nil, "Resolve не выдумывает результат")

print("\n=== 4. ХРАНЕНИЕ И АРХИВ ===")
ok(R.Save("test"), "реестр сохраняется в файл")
R.Data = { accounts = {}, chars = {}, nextChar = 1, nextAccount = 1 }
R.Load()
ok(R.CIDNumber("76561190000000001:char1") == 1000, "номера переживают перезагрузку")
ok(R.Data.nextChar == 1003 and R.Data.nextAccount == 1002, "счётчики восстановлены выше максимума",
    R.Data.nextChar .. "/" .. R.Data.nextAccount)

ok(R.RetireCharacter("76561190000000001:char2"), "персонаж уходит в архив")
ok(R.Data.chars["76561190000000001:char2"].retired == true, "запись помечена архивной")
local c = mkPlayer("76561190000000003", "char1", "Отто Кёниг")
local cidC = R.Sync(c)
ok(cidC == "ГР-1003", "номер архивного персонажа НЕ переиспользуется", cidC)

print("\n=== 5. ЗАЩИТА ОТ ПОВРЕЖДЁННОГО ФАЙЛА ===")
FS["grm_identity/registry.json"] = '{"version":1,"chars":{"76561190000000009:char1":{"cid":5000,"pid":9}},"nextChar":1,"nextAccount":1}'
R.Load()
ok(R.Data.nextChar == 5001, "счётчик поднялся выше найденного максимума", R.Data.nextChar)
FS["grm_identity/registry.json"] = "мусор, не json"
R.Load()
ok(table.Count(R.Data.chars) == 0 and R.Data.nextChar == 1000, "битый файл не роняет реестр")

print(("\nREGISTRY RUNTIME: %d/%d, провалов: %d"):format(total - fails, total, fails))
if fails > 0 then os.exit(1) end
