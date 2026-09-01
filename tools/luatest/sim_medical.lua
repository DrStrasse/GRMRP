-- Стенд ЕДИНОЙ медкарты: канонизация справочников (кровь/ВВК), HasCard,
-- миграция ключей (голый sid64 → :char1, схлопывание дублей).
SERVER, CLIENT = true, false

-- ── GMod API mock ─────────────────────────────────────────────────────
function AddCSLuaFile() end
function isstring(v) return type(v) == "string" end
function istable(v) return type(v) == "table" end
function isfunction(v) return type(v) == "function" end
function IsValid(v) if v == nil then return false end if istable(v) then return rawget(v, "__valid") ~= false end return false end
function isentity(v) return istable(v) and rawget(v, "__ent") == true end
math.Clamp = math.Clamp or function(v, a, b) if v < a then return a elseif v > b then return b else return v end end
function string.Trim(s) return tostring(s):match("^%s*(.-)%s*$") end
function string.Explode(sep, s) local out, cur = {}, ""; for i = 1, #tostring(s) do local c = tostring(s):sub(i, i); if c == sep then out[#out + 1] = cur; cur = "" else cur = cur .. c end end; out[#out + 1] = cur; return out end
function table.Count(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end; return n end
function table.Copy(t) local o = {}; for k, v in pairs(t or {}) do o[k] = (type(v) == "table") and table.Copy(v) or v end; return o end
function Color(r, g, b, a) return { r = r or 255, g = g or 255, b = b or 255, a = a or 255 } end
function CurTime() return os.clock() end
function SysTime() return os.clock() end

-- Минимальный JSON-декодер (для легаси-файла).
local function jsonDecode(s)
    local pos = 1
    local function ws() while pos <= #s and s:sub(pos, pos):match("%s") do pos = pos + 1 end end
    local parseVal
    local function parseStr()
        pos = pos + 1
        local out = {}
        while pos <= #s do
            local c = s:sub(pos, pos)
            if c == '"' then pos = pos + 1 break end
            if c == "\\" then
                local n = s:sub(pos + 1, pos + 1)
                if n == "n" then out[#out + 1] = "\n" elseif n == "t" then out[#out + 1] = "\t" elseif n == '"' then out[#out + 1] = '"' elseif n == "\\" then out[#out + 1] = "\\" else out[#out + 1] = n end
                pos = pos + 2
            else out[#out + 1] = c pos = pos + 1 end
        end
        return table.concat(out)
    end
    local function parseArr()
        pos = pos + 1 local t = {}
        ws() if s:sub(pos, pos) == "]" then pos = pos + 1 return t end
        while true do t[#t + 1] = parseVal() ws() local c = s:sub(pos, pos) if c == "]" then pos = pos + 1 break elseif c == "," then pos = pos + 1 end end
        return t
    end
    local function parseObj()
        pos = pos + 1 local t = {}
        ws() if s:sub(pos, pos) == "}" then pos = pos + 1 return t end
        while true do ws() local k = parseStr() ws() pos = pos + 1 -- ':'
            t[k] = parseVal() ws() local c = s:sub(pos, pos)
            if c == "}" then pos = pos + 1 break elseif c == "," then pos = pos + 1 end
        end
        return t
    end
    parseVal = function()
        ws() local c = s:sub(pos, pos)
        if c == '"' then return parseStr()
        elseif c == "{" then return parseObj()
        elseif c == "[" then return parseArr()
        elseif c == "t" then pos = pos + 4 return true
        elseif c == "f" then pos = pos + 5 return false
        elseif c == "n" then pos = pos + 4 return nil
        else local j = pos while s:sub(j, j):match("[%d%-%+%.eE]") do j = j + 1 end local n = tonumber(s:sub(pos, j - 1)) pos = j return n end
    end
    return parseVal()
end

local files = {}
file = {
    IsDir = function() return true end, CreateDir = function() end,
    Exists = function(p) return files[p] ~= nil end,
    Read = function(p) return files[p] end,
    Write = function(p, s) files[p] = s end,
}
util = {
    AddNetworkString = function() end,
    JSONToTable = function(txt) return jsonDecode(txt or "") end,
    TableToJSON = function(t, _p) return jsonEncode(t) end,
    IsValidModel = function() return true end,
    SteamIDTo64 = function() return nil end,
}
-- Простой энкодер (для SaveCards миграции — достаточно объекта карт).
function jsonEncode(v)
    local t = type(v)
    if v == nil then return "null" elseif t == "boolean" then return tostring(v)
    elseif t == "number" then return tostring(v)
    elseif t == "string" then return '"' .. v:gsub('[\\"]', function(c) return c == '"' and '\\"' or '\\\\' end) .. '"'
    elseif t == "table" then
        local parts, n = {}, 0
        for k in pairs(v) do n = n + 1 end
        local isArr = true
        for i = 1, n do if v[i] == nil then isArr = false break end end
        if isArr then for i = 1, n do parts[#parts + 1] = jsonEncode(v[i]) end return "[" .. table.concat(parts, ",") .. "]"
        else for k, val in pairs(v) do parts[#parts + 1] = jsonEncode(tostring(k)) .. ":" .. jsonEncode(val) end return "{" .. table.concat(parts, ",") .. "}" end
    end
    error("unsupported " .. t)
end
net = { Start = function() end, WriteString = function() end, WriteTable = function() end, WriteBool = function() end, WriteEntity = function() end, WriteUInt = function() end, Send = function() end, Broadcast = function() end, Receive = function() end }
hook = { Add = function() end, Run = function() end }
timer = { Simple = function() end, Create = function() end }
concommand = { Add = function() end }
player = { GetAll = function() return {} end }
GRM = {
    Identity = { CharacterKey = function(p) return (p and p.sid64 and (p.sid64 .. ":char1")) or "0:char1" end, FactionMember = function() return nil end },
    Inventory = { RegisterItem = function() end },
    Notify = function() end,
}
Factions = {}

-- ── Легаси-файл: голый sid64 + дубль :char1 + старые справочники ────────
local SID = "76561190000000001"
files["grm_medcards.json"] = ('{"%s":{"name":"Пациент","blood":"I (0) Rh+","fitnessCategory":"Д — Не годен к военной службе (освобождён)"},"%s:char1":{"name":"Пациент2","blood":"III (B) Rh-","fitnessCategory":"В — Ограниченно годен к службе (запас)"}}'):format(SID, SID)

local chunk, err = loadfile("lua/autorun/sh_grm_medical.lua")
local pass, fail = 0, 0
local function ok(v, n) if v then pass = pass + 1; print("  ok  " .. n) else fail = fail + 1; print("  FAIL " .. n) end end
ok(chunk ~= nil, "medical parses: " .. tostring(err))
if not chunk then os.exit(1) end
local ran, rerr = pcall(chunk)
ok(ran, "medical server loads: " .. tostring(rerr))
local MD = GRM.Medical
ok(MD ~= nil, "GRM.Medical exposed")

-- Канонизация группы крови.
ok(MD.NormalizeBlood("I (0) Rh+") == "O(I) Rh+", "blood I(0)+ → O(I) Rh+")
ok(MD.NormalizeBlood("II (A) Rh-") == "A(II) Rh−", "blood II(A)- → A(II) Rh−")
ok(MD.NormalizeBlood("III (B) Rh-") == "B(III) Rh−", "blood III(B)- → B(III) Rh−")
ok(MD.NormalizeBlood("IV (AB) Rh−") == "AB(IV) Rh−", "blood IV(AB)− → AB(IV) Rh−")
ok(MD.NormalizeBlood("0(I) Rh+") == "O(I) Rh+", "blood 0(I)+ → O(I) Rh+")
ok(MD.NormalizeBlood("A(II) Rh+") == "A(II) Rh+", "canonical blood stays")
ok(MD.NormalizeBlood("") == "", "empty blood stays empty")

-- Канонизация ВВК.
ok(MD.NormalizeFitness("Д — Не годен к военной службе (освобождён)"):match("^Д — Не годен к военной службе$") ~= nil, "fitness Д (освобождён) → canonical")
ok(MD.NormalizeFitness("В — Ограниченно годен к службе (запас)"):match("^В — Ограниченно годен к службе$") ~= nil, "fitness В (запас) → canonical")
ok(MD.NormalizeFitness("А — Годен к военной службе и работе") == "А — Годен к военной службе и работе", "canonical fitness stays")
ok(MD.NormalizeFitness("") == "", "empty fitness stays empty")

-- Миграция ключей: голый sid64 схлопнут с :char1, справочники нормализованы.
ok(istable(MD.Cards), "cards loaded")
ok(MD.Cards[SID .. ":char1"] ~= nil, "card migrated to canonical :char1 key")
ok(MD.Cards[SID] == nil, "bare sid64 key removed (single record)")
ok(table.Count(MD.Cards) == 1, "exactly one card after dedupe")
local card = MD.Cards[SID .. ":char1"]
ok(card.blood == "B(III) Rh−", "card blood normalized to canonical (" .. tostring(card.blood) .. ")")
ok(card.fitnessCategory == "В — Ограниченно годен к службе", "card fitness normalized to canonical")

-- HasCard без авто-создания.
ok(MD.HasCard(SID .. ":char1") == true, "HasCard true for existing card")
ok(MD.HasCard("76561190000000999:char1") == false, "HasCard false for missing card")
ok(MD.Cards["76561190000000999:char1"] == nil, "HasCard does NOT create empty card")

print(("MEDICAL: %d/%d failures=%d"):format(pass, pass + fail, fail))
if fail > 0 then os.exit(1) end
