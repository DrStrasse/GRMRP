-- Round-trip тест персистентности GRM currency/economy (мок GMod API + сценарии)
-- Запуск: собрать LuaJIT (github.com/LuaJIT/LuaJIT, ветка v2.1), из КОРНЯ репо:
--   rm -rf tools/luatest/data && ./luajit tools/luatest/roundtrip_test.lua save  (и далее load/bank_reconcile_attack/bank_boot_pick_fresh/corrupt/corrupt_all/treasury_corrupt)

-- GMod API mock + harness для round-trip теста GRM currency/economy
local PHASE = arg[1] or "save"
local DATA = "tools/luatest/data"

os.execute('mkdir -p "' .. DATA .. '"')

SERVER, CLIENT = true, false

-- ── утилиты ────────────────────────────────────────────────
function isstring(v) return type(v) == "string" end
function istable(v) return type(v) == "table" end
function isentity(v) return istable(v) and rawget(v, "__ent") == true end
function IsValid(v) return v ~= nil and (not istable(v) or rawget(v, "__valid") ~= false) and (istable(v) or type(v) == "userdata") end

math.Clamp = math.Clamp or function(v, a, b) if v < a then return a elseif v > b then return b else return v end end
string.Trim = string.Trim or function(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
string.StartWith = string.StartWith or function(s, p) return s:sub(1, #p) == p end
string.Left = string.Left or function(s, n) return s:sub(1, n) end
string.Explode = string.Explode or function(sep, s)
    local out, cur = {}, ""
    for i = 1, #s do
        local c = s:sub(i, i)
        if c == sep then out[#out + 1] = cur cur = "" else cur = cur .. c end
    end
    out[#out + 1] = cur
    return out
end
table.Count = table.Count or function(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
CurTime = CurTime or function() return os.clock() end
isfunction = isfunction or function(v) return type(v) == "function" end
Color = Color or function(r, g, b, a) return { r = r or 255, g = g or 255, b = b or 255, a = a or 255 } end
function AddCSLuaFile() end

-- ── JSON ───────────────────────────────────────────────────
local function jsonEncode(v, pretty, ind)
    ind = ind or ""
    local t = type(v)
    if t == "nil" then return "null"
    elseif t == "boolean" or t == "number" then return tostring(v)
    elseif t == "string" then
        return '"' .. v:gsub('[%z\1-\31\\"]', function(c)
            local m = {['"']='\\"', ['\\']='\\\\', ['\n']='\\n', ['\r']='\\r', ['\t']='\\t'}
            return m[c] or string.format("\\u%04x", c:byte())
        end) .. '"'
    elseif t == "table" then
        local n, isArr = 0, true
        for k in pairs(v) do n = n + 1 end
        if n > 0 then for i = 1, n do if rawget(v, i) == nil then isArr = false break end end
        else isArr = false end
        local nl = pretty and "\n" or ""
        local pad = pretty and (ind .. "\t") or ""
        local parts = {}
        if isArr and n > 0 then
            for i = 1, n do parts[#parts + 1] = pad .. jsonEncode(v[i], pretty, pad) end
            return "[" .. nl .. table.concat(parts, "," .. nl) .. nl .. ind .. "]"
        end
        for k, val in pairs(v) do
            parts[#parts + 1] = pad .. jsonEncode(tostring(k), false) .. (pretty and ": " or ":") .. jsonEncode(val, pretty, pad)
        end
        if #parts == 0 then return "{}" end
        return "{" .. nl .. table.concat(parts, "," .. nl) .. nl .. ind .. "}"
    end
    error("jsonEncode: unsupported " .. t)
end

local function jsonDecode(s)
    local pos = 1
    local function ws() while pos <= #s and s:sub(pos, pos):match("%s") do pos = pos + 1 end end
    local function parseVal()
        ws()
        local c = s:sub(pos, pos)
        if c == "{" then
            local t = {}
            pos = pos + 1 ws()
            if s:sub(pos, pos) == "}" then pos = pos + 1 return t end
            while true do
                ws()
                local k = parseVal()
                ws() assert(s:sub(pos, pos) == ":", "expected : at " .. pos) pos = pos + 1
                t[k] = parseVal()
                ws()
                c = s:sub(pos, pos)
                if c == "," then pos = pos + 1
                elseif c == "}" then pos = pos + 1 return t
                else error("expected , or } at " .. pos) end
            end
        elseif c == "[" then
            local t, i = {}, 1
            pos = pos + 1 ws()
            if s:sub(pos, pos) == "]" then pos = pos + 1 return t end
            while true do
                t[i] = parseVal() i = i + 1
                ws()
                c = s:sub(pos, pos)
                if c == "," then pos = pos + 1
                elseif c == "]" then pos = pos + 1 return t
                else error("expected , or ] at " .. pos) end
            end
        elseif c == '"' then
            pos = pos + 1
            local out = {}
            while pos <= #s do
                c = s:sub(pos, pos)
                if c == '"' then pos = pos + 1 return table.concat(out) end
                if c == "\\" then
                    local e = s:sub(pos + 1, pos + 1)
                    local m = { n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
                    if m[e] then out[#out + 1] = m[e] pos = pos + 2
                    elseif e == "u" then
                        out[#out + 1] = "?" pos = pos + 6
                    else out[#out + 1] = e pos = pos + 2 end
                else out[#out + 1] = c pos = pos + 1 end
            end
            error("unterminated string")
        elseif s:sub(pos, pos + 3) == "true" then pos = pos + 4 return true
        elseif s:sub(pos, pos + 4) == "false" then pos = pos + 5 return false
        elseif s:sub(pos, pos + 3) == "null" then pos = pos + 4 return nil
        else
            local num = s:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*", pos)
            if num and #num > 0 then pos = pos + #num return tonumber(num) end
            error("bad value at " .. pos .. ": " .. s:sub(pos, pos + 10))
        end
    end
    return parseVal()
end

-- Эмуляция ловушки GMod: util.JSONToTable БЕЗ третьего аргумента конвертирует
-- числовые строки-ключи в числа (wiki: «keys are converted to numbers wherever
-- possible. This means using Player:SteamID64 as keys won't work»). Ключ
-- «76561199385153957» превращается в битое double 7.6561199385154e+16.
local function convertKeysR(t)
    local ks = {}
    for k in pairs(t) do ks[#ks + 1] = k end
    for _, k in ipairs(ks) do
        local v = rawget(t, k)
        if isstring(k) then
            local n = tonumber(k)
            if n ~= nil then
                rawset(t, k, nil)
                rawset(t, n, v) -- sid64 не влезает в double точно -> ключ калечится, как в GMod
            end
        end
        if type(v) == "table" then convertKeysR(v) end
    end
end

util = {
    AddNetworkString = function() end,
    TableToJSON = function(t, pretty) return jsonEncode(t, pretty) end,
    JSONToTable = function(s, ignoreLimits, ignoreConversions)
        local ok, t = pcall(jsonDecode, s)
        if not ok then return nil end
        if t ~= nil and not ignoreConversions then convertKeysR(t) end
        return t
    end,
}

-- ── file ───────────────────────────────────────────────────
file = {
    Write = function(name, content)
        local f = io.open(DATA .. "/" .. name, "wb")
        if not f then error("file.Write failed: " .. name) end
        f:write(content) f:close()
    end,
    Read = function(name)
        local f = io.open(DATA .. "/" .. name, "rb")
        if not f then return nil end
        local c = f:read("*a") f:close()
        return c
    end,
    Exists = function(name)
        local f = io.open(DATA .. "/" .. name, "rb");
        if f then f:close() return true end
        return false
    end,
    Append = function(name, content)
        local f = io.open(DATA .. "/" .. name, "ab")
        if f then f:write(content) f:close() end
    end,
}

-- ── net / hook / timer / concommand ────────────────────────
net = {
    Start = function() return true end,
    WriteUInt = function() end, WriteInt = function() end, WriteDouble = function() end,
    WriteString = function() end, WriteTable = function() end, WriteEntity = function() end,
    ReadUInt = function() return 0 end, ReadInt = function() return 0 end, ReadDouble = function() return 0 end,
    ReadString = function() return "" end, ReadTable = function() return {} end, ReadEntity = function() return nil end,
    Send = function() end, SendToServer = function() end, Broadcast = function() end,
    Receive = function() end,
}
local HOOKS = {}
hook = {
    Add = function(ev, id, fn) HOOKS[ev] = HOOKS[ev] or {} HOOKS[ev][id] = fn end,
    Remove = function(ev, id) if HOOKS[ev] then HOOKS[ev][id] = nil end end,
    GetTable = function() return HOOKS end,
    Run = function(ev, ...)
        local ret
        if HOOKS[ev] then for _, fn in pairs(HOOKS[ev]) do ret = fn(...) end end
        return ret
    end,
}
local TIMERS = {}
timer = {
    Create = function(name, delay, reps, fn) TIMERS[name] = { fn = fn } end,
    Simple = function(_, fn) TIMERS[#TIMERS + 1] = { fn = fn } end,
    Remove = function(name) TIMERS[name] = nil end,
}
concommand = { Add = function(name, fn) concommand[name] = fn end }
player = { GetAll = function() return _G.__PLAYERS or {} end }

-- ── фейковый игрок ─────────────────────────────────────────
local NEXT_PID = 1
local function mkPly(nick, sid64, sid)
    NEXT_PID = NEXT_PID + 1
    local p = {
        __ent = true, __valid = true, _eid = NEXT_PID,
        SteamID64 = function() return sid64 end,
        SteamID = function() return sid end,
        Nick = function() return nick end,
        IsPlayer = function() return true end,
        IsBot = function() return false end,
        IsSuperAdmin = function() return true end,
        EntIndex = function(s) return s._eid end,
        SetNW2Int = function() end,
        GetPos = function(s) return s._pos or Vector(0, 0, 0) end,
        SetPos = function(s, v) s._pos = v end,
        GetShootPos = function() return Vector(0, 0, 60) end,
        GetAimVector = function() return Vector(1, 0, 0) end,
        PrintMessage = function() end,
        __nw = {},
        __weps = {},
    }
    function p:SetNWBool(k, v) self.__nw[k] = v end
    function p:GetNWBool(k, d) return self.__nw[k] ~= nil and self.__nw[k] or d end
    function p:SetNWInt(k, v) self.__nw[k] = v end
    function p:GetNWInt(k, d) return self.__nw[k] ~= nil and self.__nw[k] or (d or 0) end
    function p:SetNWString(k, v) self.__nw[k] = v end
    function p:GetNWString(k, d) return self.__nw[k] ~= nil and self.__nw[k] or (d or "") end
    function p:SetNWEntity(k, v) self.__nw[k] = v end
    function p:GetNWEntity(k, d) return self.__nw[k] ~= nil and self.__nw[k] or d end
    function p:GetWeapons() return self.__weps end
    function p:GetWeapon(cls)
        for _, w in ipairs(self.__weps) do if w:GetClass() == cls then return w end end
        return nil
    end
    function p:Give(cls)
        local w = {
            __valid = true,
            _class = cls,
            _amt = 0,
            GetClass = function(s) return s._class end,
            SetCarriedAmount = function(s, a) s._amt = a end,
            GetCarriedAmount = function(s) return s._amt end,
        }
        self.__weps[#self.__weps + 1] = w
        return w
    end
    function p:StripWeapon(cls)
        for i = #self.__weps, 1, -1 do
            if self.__weps[i]:GetClass() == cls then table.remove(self.__weps, i) end
        end
    end
    function p:SelectWeapon() end
    function p:GetVehicle() return self._veh end
    function p:InVehicle() return self._veh ~= nil end
    p.__mt = { __index = function(t, k) return rawget(t, k) end }
    return p
end

-- ================= ТЕСТ СЦЕНАРИЙ ===========================
local function fireHook(ev, ...)
    if HOOKS[ev] then for _, fn in pairs(HOOKS[ev]) do fn(...) end end
end

-- timer.Simple стреляет ОДИН раз: имитируем потребление
local function fireSimpleTimers()
    local list = {}
    for i, t in ipairs(TIMERS) do
        list[#list + 1] = t
        TIMERS[i] = nil
    end
    for _, t in ipairs(list) do t.fn() end
end

GRM = nil
Factions = {
    Polizei = {
        Members = { ["STEAM_0:1:100"] = { Role = "Officer" } },
        Leader = "STEAM_0:1:100", Roles = { "Officer" }, Departments = {},
    },
}

if PHASE == "save" then
    GRM = GRM or {}
    dofile("lua/autorun/sh_grm_currency.lua")
    dofile("lua/autorun/sh_grm_economy.lua")

    local ply = mkPly("Alexander Von Groenner", "76561199385153957", "STEAM_0:1:100")
    _G.__PLAYERS = { ply }
    fireHook("PlayerInitialSpawn", ply)

    print("  баланс на спавне: " .. GRM.GetBalance(ply))
    GRM.SetBalance(ply, 500200, "тест")
    assert(GRM.GetBalance(ply) == 500200, "SetBalance не применился")

    GRM.FactionBudgetAdd("Polizei", 250000, "тестовый взнос")
    assert(GRM.FactionBudgetGet("Polizei") == 250000, "бюджет фракции не применился")
    local ok = GRM.Economy.BankDeposit(ply, 200000)
    assert(ok, "BankDeposit не прошёл")
    assert(GRM.Economy.BankBalance(ply) == 200000, "банк != 200000")
    assert(GRM.GetBalance(ply) == 300200, "наличка после взноса != 300200, а " .. tonumber(GRM.GetBalance(ply)))

    fireHook("ShutDown") -- имитация выключения

    local w = file.Read("grm_wallet.json") or ""
    local tr = file.Read("grm_treasury.json") or ""
    assert(w:find("300200"), "wallet не содержит 300200: " .. w)
    assert(tr:find("Polizei") and tr:find("250000"), "treasury без фракции/бюджета")
    print("PHASE save: OK (wallet=" .. #w .. " байт, treasury=" .. #tr .. " байт)")
    print("  наличка игрока сейчас: " .. GRM.GetBalance(ply) .. ", банк: " .. GRM.Economy.BankBalance(ply) ..
          ", бюджет Polizei: " .. GRM.FactionBudgetGet("Polizei"))

elseif PHASE == "load" then
    dofile("lua/autorun/sh_grm_currency.lua")
    dofile("lua/autorun/sh_grm_economy.lua")

    local ply = mkPly("Alexander Von Groenner", "76561199385153957", "STEAM_0:1:100")
    _G.__PLAYERS = { ply }
    fireHook("PlayerInitialSpawn", ply)

    assert(GRM.GetBalance(ply) == 300200, "РЕСТАРТ: наличка != 300200, а " .. tostring(GRM.GetBalance(ply)))
    assert(GRM.Economy.BankBalance(ply) == 200000, "РЕСТАРТ: банк != 200000, а " .. tostring(GRM.Economy.BankBalance(ply)))
    assert(GRM.FactionBudgetGet("Polizei") == 250000, "РЕСТАРТ: бюджет != 250000")
    print("PHASE load: OK — всё пережило рестарт")

elseif PHASE == "corrupt" then
    -- ломаем wallet: обрез 90% (запись цела, обрублены лишь финальные скобки),
    -- зеркало целое: проверяем rescue И штатный фолбэк на зеркало
    local w = file.Read("grm_wallet.json") or ""
    file.Write("grm_wallet.json", w:sub(1, math.floor(#w * 0.9)))
    -- зеркало оставляем ЦЕЛЫМ: loader обязан поднять либо rescue, либо зеркало
    dofile("lua/autorun/sh_grm_currency.lua")
    local bal = GRM.GetBalance("76561199385153957")
    assert(bal == 300200, "СПАСЕНИЕ из битого файла не сработало: " .. tostring(bal))
    print("PHASE corrupt: OK — запись спасена из обрубленного файла")

elseif PHASE == "corrupt_all" then
    -- обрезаем и основной, и зеркало (90%): возможно только regex-спасение
    local w = file.Read("grm_wallet.json") or ""
    local cut = w:sub(1, math.floor(#w * 0.9))
    file.Write("grm_wallet.json", cut)
    file.Write("grm_wallet_backup.json", cut)
    dofile("lua/autorun/sh_grm_currency.lua")
    local bal = GRM.GetBalance("76561199385153957")
    assert(bal == 300200, "corrupt_all: баланс спасён неточно: " .. tostring(bal))
    print("PHASE corrupt_all: OK — из полностью битых копий спасено: " .. tostring(bal))

elseif PHASE == "treasury_corrupt" then
    local tr = file.Read("grm_treasury.json") or ""
    file.Write("grm_treasury.json", "{CORRUPT")
    file.Write("grm_treasury_backup.json", tr) -- зеркало живое
    dofile("lua/autorun/sh_grm_currency.lua")
    dofile("lua/autorun/sh_grm_economy.lua")
    assert(GRM.FactionBudgetGet("Polizei") == 250000, "treasury не поднялся из зеркала")
    assert(GRM.Economy.BankBalance("76561199385153957") == 200000, "банк пропал из зеркала")
    print("PHASE treasury_corrupt: OK — экономика поднялась из зеркала")

end

-- фазы чужих форматов (v2.0.1): кладём чужой файл и проверяем подъём
local function foreign(phaseName, content, expect)
    if PHASE == phaseName then
        file.Write("grm_wallet.json", content)
        file.Write("grm_wallet_backup.json", content)
        dofile("lua/autorun/sh_grm_currency.lua")
        local ply = mkPly("Alexander Von Groenner", "76561199385153957", "STEAM_0:1:100")
        _G.__PLAYERS = { ply }
        fireHook("PlayerInitialSpawn", ply)
        local bal = GRM.GetBalance(ply)
        assert(bal == expect, phaseName .. ": баланс " .. tostring(bal) .. " != " .. tostring(expect))
        print("PHASE " .. phaseName .. ": OK (" .. tostring(bal) .. ")")
    end
end
foreign("fmt_array_sid", '[\n\t{\n\t\t"sid64": "76561199385153957",\n\t\t"balance": 500200,\n\t\t"name": "Alexander Von Groenner"\n\t}\n]', 500200)
foreign("fmt_array_nick", '[\n\t{\n\t\t"name": "Alexander Von Groenner",\n\t\t"balance": 500200\n\t}\n]', 500200)
foreign("fmt_mapnum", '{\n\t"76561199385153957": 500200\n}', 500200)

-- ── фазы «банк помнит» (economy v3.0.1) ────────────────────────────────
-- bank_reconcile_attack: постаревший ОСНОВНОЙ файл подкидывается ВО ВРЕМЯ
-- работы: сверка обязана отклонить его и перезаписать памятью.
if PHASE == "bank_reconcile_attack" then
    GRM = GRM or {}
    dofile("lua/autorun/sh_grm_currency.lua")
    dofile("lua/autorun/sh_grm_economy.lua")
    assert(GRM.Economy.BankBalance("76561199385153957") == 200000, "bank_attack: банк до атаки не поднялся")
    -- внешняя сущность подменяет основной файл на старый снимок
    local stale = '{"version":2,"factions":{"Polizei":{"budget":250000,"taxRate":0.05,"history":[]}},' ..
        '"accounts":{"76561190000000000":{"balance":777,"name":"Old Timer"}},' ..
        '"state":{"budget":0,"history":[]},"log":[],"config":{}}'
    file.Write("grm_treasury.json", stale)
    assert(TIMERS["GRM_Economy_Reconcile"], "нет таймера сверки экономики")
    TIMERS["GRM_Economy_Reconcile"].fn() -- в GMod это тик 15с
    assert(GRM.Economy.BankBalance("76561199385153957") == 200000,
        "bank_attack: сверка ЗАТЁРЛА банк постаревшим файлом: " .. tostring(GRM.Economy.BankBalance("76561199385153957")))
    local tr = file.Read("grm_treasury.json") or ""
    assert(tr:find("200000"), "bank_attack: файл не самоизлечился, самоизлечение: " .. tr:sub(1, 100))
    print("PHASE bank_reconcile_attack: OK — сверка отклонила старый файл, память перезаписала диск")
end

-- bank_boot_pick_fresh: на рестарте основной файл «постаревший» (0 счетов),
-- зеркало свежее: загрузчик обязан выбрать ЗЕРКАЛО и залечить основной.
if PHASE == "bank_boot_pick_fresh" then
    local stale = '{"version":2,"factions":{"Polizei":{"budget":250000,"taxRate":0.05,"history":[]}},' ..
        '"accounts":{},"state":{"budget":0,"history":[]},"log":[],"config":{}}'
    file.Write("grm_treasury.json", stale)
    GRM = GRM or {}
    dofile("lua/autorun/sh_grm_currency.lua")
    dofile("lua/autorun/sh_grm_economy.lua")
    assert(GRM.Economy.BankBalance("76561199385153957") == 200000,
        "bank_boot: loader выбрал старый основной файл вместо свежего зеркала, банк: " ..
        tostring(GRM.Economy.BankBalance("76561199385153957")))
    print("PHASE bank_boot_pick_fresh: OK — loader предпочёл свежее зеркало старому основному файлу")
end

-- sidkey_trap: ловушка числовых ключей GMod против CharacterKey.
-- Харнесс не грузит Identity, поэтому фаза save пишет кошелёк чистыми sid64,
-- а фаза load мигрирует их в CharacterKey (sid:charN) и переписывает файл.
-- Фаза обязана быть зелёной в ОБОИХ мирах:
--   • sid64-мир (сразу после save): голый JSONToTable калечит ключ (strKeys==0);
--   • char1-мир (после load): голый JSONToTable НЕ калечит «sid:char1» (strKeys>0);
--   • jsonT (ignoreConversions=true) спасает ключ в любом мире.
if PHASE == "sidkey_trap" then
    local sample = '{"76561199385153957":1000,"76561199385153957:char1":2000}'
    local bareS = util.JSONToTable(sample)
    assert(bareS and bareS["76561199385153957:char1"] ~= nil,
        "sidkey_trap: CharacterKey потерян голым парсером (нечисловой суффикс должен выживать)")
    local w = file.Read("grm_wallet.json") or ""
    assert(#w > 0, "sidkey_trap: нет файла кошелька (сначала фаза save)")
    local bareW  = util.JSONToTable(w)
    local fixedW = util.JSONToTable(w, false, true)
    local strKeys = 0
    for k in pairs(bareW or {}) do if isstring(k) then strKeys = strKeys + 1 end end
    if fixedW and fixedW["76561199385153957:char1"] ~= nil then
        -- char1-мир (после load): миграция прошла, ловушка к ключу не применима
        assert(strKeys > 0, "sidkey_trap: char1-ключ потерян голым парсером")
        print("PHASE sidkey_trap: OK — wallet в char1-мире, ловушка числовых ключей не применима, jsonT спасает")
    else
        -- sid64-мир (сразу после save): голый парсер обязан скалечить ключ
        assert(fixedW and fixedW["76561199385153957"] ~= nil,
            "sidkey_trap: ignoreConversions не спас sid64-ключ wallet")
        assert(strKeys == 0, "sidkey_trap: голый парсер не сымитировал калечение числового sid64-ключа")
        print("PHASE sidkey_trap: OK — sid64 калечится голым парсером, jsonT(ignoreConversions=true) спасает")
    end
end

-- bank_nick_mirror: treasury откачены (счета пустые), но есть зеркало
-- electro_balance: счёт по сиду восстанавливается на загрузке,
-- запись без сида — по нику при входе игрока.
if PHASE == "bank_nick_mirror" then
    local stale = '{"version":2,"factions":{"Polizei":{"budget":250000,"taxRate":0.05,"history":[]}},' ..
        '"accounts":{},"state":{"budget":0,"history":[]},"log":[],"config":{}}'
    file.Write("grm_treasury.json", stale)
    file.Write("grm_treasury_backup.json", stale)
    file.Write("grm_bank_nicks.json", '[\n' ..
        '\t{\n\t\t"sid": "76561199385153957",\n\t\t"name": "Alexander Von Groenner",\n\t\t"electro_balance": 200000\n\t},\n' ..
        '\t{\n\t\t"name": "Old Timer Ghost",\n\t\t"electro_balance": 777\n\t}\n]')
    GRM = GRM or {}
    dofile("lua/autorun/sh_grm_currency.lua")
    dofile("lua/autorun/sh_grm_economy.lua")
    assert(GRM.Economy.BankBalance("76561199385153957") == 200000,
        "bank_nick_mirror: счёт не восстановлен из зеркала по сиду: " .. tostring(GRM.Economy.BankBalance("76561199385153957")))
    -- вход игрока без сида в зеркале: подхват по нику
    local ghost = mkPly("Old Timer Ghost", "76561190000111000", "STEAM_0:0:999")
    _G.__PLAYERS = { ghost }
    fireHook("PlayerInitialSpawn", ghost)
    fireSimpleTimers() -- timer.Simple(2с) подхвата
    assert(GRM.Economy.BankBalance(ghost) == 777,
        "bank_nick_mirror: счёт не поднят по нику при входе: " .. tostring(GRM.Economy.BankBalance(ghost)))
    print("PHASE bank_nick_mirror: OK — зеркало electro_balance вернуло счёта и по сиду, и по нику")
end

-- ── моки для перм-энтити (Код 50) ───────────────────────────────
game = game or { GetMap = function() return _G.__MAP or "gm_flatgrass" end }
local VMT = {
    __add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end,
    __mul = function(a, k)
        if type(a) == "number" then a, k = k, a end
        return Vector(a.x * k, a.y * k, a.z * k)
    end,
    __index = {
        DistToSqr = function(self, other)
            local dx = (self.x or 0) - (other.x or 0)
            local dy = (self.y or 0) - (other.y or 0)
            local dz = (self.z or 0) - (other.z or 0)
            return dx * dx + dy * dy + dz * dz
        end,
    },
}
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VMT) end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
HUD_PRINTTALK = HUD_PRINTTALK or 2
util.TraceLine = function() return { Entity = _G.__AIM_ENT } end
local SPAWNED_ENTS = {}
local CREATED_ENTS = {}
local NEXT_EID = 100
ents = ents or {
    Create = function(class)
        NEXT_EID = NEXT_EID + 1
        local e = {
            __ent = true, __valid = true, _class = class, _eid = NEXT_EID,
            __nw = {}, _heldCash = 0, _capacity = 500000,
        }
        function e:EntIndex() return self._eid end
        function e:GetClass() return self._class end
        function e:SetModel(m) self._model = m end
        function e:GetModel() return self._model end
        function e:SetPos(v) self._pos = v end
        function e:GetPos() return self._pos or Vector(0,0,0) end
        function e:SetAngles(a) self._ang = a end
        function e:GetAngles() return self._ang or Angle(0,0,0) end
        function e:Spawn() self._spawned = true SPAWNED_ENTS[#SPAWNED_ENTS + 1] = self end
        function e:Activate() self._active = true end
        function e:GetPhysicsObject()
            return { IsValid = function() return true end, EnableMotion = function() end }
        end
        function e:Remove() self.__valid = false end
        function e:EmitSound() end
        function e:IsVehicle() return self._isVeh == true end
        function e:GetDriver() return self._driver end
        function e:GetChildren() return {} end
        function e:SetNWBool(k, v) self.__nw[k] = v end
        function e:GetNWBool(k, d) return self.__nw[k] ~= nil and self.__nw[k] or (d or false) end
        function e:SetNWInt(k, v) self.__nw[k] = v end
        function e:GetNWInt(k, d) return self.__nw[k] ~= nil and self.__nw[k] or (d or 0) end
        function e:SetNWString(k, v) self.__nw[k] = v end
        function e:GetNWString(k, d) return self.__nw[k] ~= nil and self.__nw[k] or (d or "") end
        function e:SetNWEntity(k, v) self.__nw[k] = v end
        function e:GetNWEntity(k, d) return self.__nw[k] ~= nil and self.__nw[k] or d end
        function e:GetHeldCash() return self._heldCash end
        function e:SetHeldCash(n) self._heldCash = n end
        function e:GetCapacity() return self._capacity end
        function e:SetCapacity(n) self._capacity = n end
        CREATED_ENTS[#CREATED_ENTS + 1] = e
        return e
    end,
    FindInSphere = function(pos, r)
        local out = {}
        for _, e in ipairs(CREATED_ENTS) do
            if e.__valid ~= false and e._pos then
                local d2 = pos:DistToSqr(e._pos)
                if d2 <= (r or 1) * (r or 1) then out[#out + 1] = e end
            end
        end
        return out
    end,
    FindByClass = function(cls)
        local out = {}
        for _, e in ipairs(CREATED_ENTS) do
            if e.__valid ~= false and e:GetClass() == cls then out[#out + 1] = e end
        end
        return out
    end,
}

-- perm: добавить/дедуп/воскрешение после cleanup/снятие/чат-команда
if PHASE == "perm" then
    file.Write("grm_perm_entities.json", "[]") -- изоляция фазы: чистый старт
    GRM = GRM or {}
    dofile("lua/autorun/sh_grm_perm_entities.lua")
    fireHook("InitPostEntity")
    fireSimpleTimers()
    assert(#SPAWNED_ENTS == 0, "perm: без записей что-то заспавнилось")

    local ply = mkPly("Alexander Von Groenner", "76561199385153957", "STEAM_0:1:100")
    local atm = ents.Create("grm_bank_terminal")
    atm:SetModel("models/starless/atm.mdl")
    atm:SetPos(Vector(10, 20, 30))
    atm:SetAngles(Angle(0, 90, 0))
    _G.__AIM_ENT = atm
    concommand["grm_perm_add"](ply, nil, {})
    local txt = file.Read("grm_perm_entities.json") or ""
    assert(txt:find("grm_bank_terminal"), "perm: запись не сохранилась: " .. txt:sub(1, 80))

    concommand["grm_perm_add"](ply, nil, {}) -- дубликат на том же месте
    local t2 = util.JSONToTable(file.Read("grm_perm_entities.json") or "", false, true)
    assert(istable(t2) and #t2 == 1, "perm: дедуп не сработал, записей " .. tostring(istable(t2) and #t2 or -1))

    atm.__valid = false -- «сервер рестартанул / cleanup»
    local before = #SPAWNED_ENTS
    fireHook("PostCleanupMap")
    fireSimpleTimers()
    assert(#SPAWNED_ENTS == before + 1, "perm: энтити не воскресла по карте")
    local back = SPAWNED_ENTS[#SPAWNED_ENTS]
    assert(back:GetClass() == "grm_bank_terminal", "perm: воскрес не тот класс")
    assert(back:GetPos().x == 10 and back:GetPos().y == 20 and back:GetPos().z == 30, "perm: позиция не совпала")
    assert(back:GetAngles().y == 90, "perm: угол не совпал")
    assert(back._grmPerm == true, "perm: нет метки перм-энтити")

    _G.__AIM_ENT = back
    concommand["grm_perm_remove"](ply, nil, {})
    local t3 = util.JSONToTable(file.Read("grm_perm_entities.json") or "", false, true)
    assert(istable(t3) and #t3 == 0, "perm: запись не удалена")
    assert(back.__valid == false, "perm: энтити не удалена с карты")

    _G.__AIM_ENT = atm -- чат-команда до кучи (атм «воскрес» вручную)
    atm.__valid = true
    fireHook("PlayerSay", ply, "/permadd")
    assert((file.Read("grm_perm_entities.json") or ""):find("grm_bank_terminal"), "perm: /permadd чатом не сработал")

    -- /permload: поверх живого энтити — дублёра не ставит...
    local cnt = #SPAWNED_ENTS
    fireHook("PlayerSay", ply, "/permload")
    assert(#SPAWNED_ENTS == cnt, "permload: заспавнил дублёра поверх существующего")
    -- ...а после удаления — восстанавливает из файла немедленно
    atm:Remove()
    fireHook("PlayerSay", ply, "/permload")
    assert(#SPAWNED_ENTS == cnt + 1, "permload: не восстановил из файла")
    local lp = SPAWNED_ENTS[#SPAWNED_ENTS]
    assert(lp:GetPos().x == 10 and lp:GetPos().z == 30 and lp._grmPerm == true, "permload: координаты/метка неверны")
    -- и консольный вариант тоже с антидублем
    fireHook("PlayerSay", ply, "/permload")
    assert(#SPAWNED_ENTS == cnt + 1, "permload: повтор выдал дублёра")

    file.Write("grm_perm_entities.json", "[]") -- убираем за фазой
    print("PHASE perm: OK — перм пишется/дедупится/воскресает после cleanup/снимается, /permload с антидублем, чат и консоль равнозначны")
end

-- ======================= ФАЗА 14: ШТРАФЫ (заказ «/fines») =====================
if PHASE == "fines" then
    GRM = GRM or {}
    dofile("lua/autorun/sh_grm_currency.lua")
    dofile("lua/autorun/sh_grm_economy.lua")
    local E = GRM.Economy

    -- кастомные игроки: НЕ суперадмины (mkPly всегда суперадмин)
    local function mkUser(nick, sid64, sid)
        local p = mkPly(nick, sid64, sid)
        p.IsSuperAdmin = function() return false end
        p.__msgs = {}
        p.PrintMessage = function(_, _, m) p.__msgs[#p.__msgs + 1] = tostring(m) end
        p.GetEyeTrace = function() return { Entity = nil } end
        return p
    end
    local officer = mkUser("Otto Officer", "76561198000000100", "STEAM_0:1:100")   -- Polizei (sid-ключ)
    local medic64 = mkUser("Maria Medic",    "76561198000000200", "STEAM_0:1:200")   -- Medic (s64-ключ!)
    local civ     = mkUser("Karl Buerger",   "76561198000000300", "STEAM_0:1:300")   -- без фракции
    _G.__PLAYERS = { officer, medic64, civ }

    Factions.Medics = {
        Members = { ["76561198000000200"] = { Role = "Санитар", Department = "Основной" } }, -- ключ SteamID64
        Leader = "STEAM_0:9:999", Roles = { "Санитар" }, Departments = { "Основной" },
    }

    -- 1. finePerms выключены по умолчанию → штрафовать нельзя
    local ok, why = E.CanFine(officer, civ)
    assert(ok == false and tostring(why):find("не имеет доступа"), "fines: доступ по умолчанию должен быть закрыт, а: " .. tostring(why))

    -- 2. включаем Polizei: все роли, граждан можно, свои — нельзя
    local fp = E._dev_entry("Polizei").finePerms
    fp.enabled = true fp.allRoles = true fp.ownFaction = false fp.otherFactions = true fp.civilians = true fp.maxAmount = 5000

    ok = E.CanFine(officer, civ)
    assert(ok == true, "fines: officer → гражданин должно быть можно")

    -- 3. нельзя штрафовать своих (ownFaction=false)
    local colleague = mkUser("Paul Officer", "76561198000000400", "STEAM_0:1:400")
    Factions.Polizei.Members["STEAM_0:1:400"] = { Role = "Officer", Department = "Основной" }
    _G.__PLAYERS[#_G.__PLAYERS + 1] = colleague
    ok, why = E.CanFine(officer, colleague)
    assert(ok == false and tostring(why):find("своих"), "fines: ownFaction=false должно резать коллег, а: " .. tostring(why))

    -- 4. член по ключу SteamID64 ТОЖЕ распознаётся (н101 — корневой фикс)
    ok, why = E.CanFine(medic64, civ)
    assert(ok == false and tostring(why):find("Фракция"), "fines: Medic без enabled — отказ, но фракция должна распознаться, а: " .. tostring(why))
    local fm = E._dev_entry("Medics").finePerms
    fm.enabled = true fm.allRoles = true fm.civilians = true
    ok = E.CanFine(medic64, civ)
    assert(ok == true, "fines: s64-ключ: медик теперь может штрафовать граждан")

    -- 5. ранговое ограничение (allRoles=false)
    fm.allRoles = false fm.roles = { ["Санитар"] = true }
    ok = E.CanFine(medic64, civ)
    assert(ok == true, "fines: ранг Санитар в списке — можно")
    Factions.Medics.Members["76561198000000200"].Role = "Пациент"
    ok, why = E.CanFine(medic64, civ)
    assert(ok == false and tostring(why):find("роль"), "fines: чужой ранг — нельзя, а: " .. tostring(why))
    Factions.Medics.Members["76561198000000200"].Role = "Санитар"

    -- 6. сам факт штрафа: деньги — цели минус, бюджет фракции плюс
    GRM.SetBalance(civ, 9000, "тест")
    local poor = mkUser("Poor Peter", "76561198000000500", "STEAM_0:1:500")
    GRM.SetBalance(poor, 0, "тест")
    local b0 = GRM.FactionBudgetGet("Polizei")
    -- суперадминский обход тоже существует (канон mkPly)
    local admin = mkPly("Boss", "76561198000000999", "STEAM_0:9:999")
    local okF, issued = E.Fine(officer, civ, 8000, "проверка") -- лимит 5000 → кап
    assert(okF == true and issued == 5000, "fines: кап по maxAmount не сработал: " .. tostring(issued))
    assert(GRM.GetBalance(civ) == 4000, "fines: неверный баланс цели: " .. GRM.GetBalance(civ))
    assert(GRM.FactionBudgetGet("Polizei") == b0 + 5000, "fines: бюджет фракции не вырос")
    okF, issued = E.Fine(officer, poor, 100, "пустой карман")
    assert(okF == false, "fines: пустой карман должен отказать")
    local okA = E.Fine(admin, colleague, 100, "админ")
    assert(okA == true, "fines: суперадмин обходит права")

    -- 7. /fines (PlayerSay): гражданин — отказ, офицер — статус в чат (PrintMessage)
    _G.__PLAYERS = { officer, medic64, civ }
    local okC, whyC = E.CanFine(civ, officer) -- цель не issuer, иначе ветка "нельзя себя" сработает раньше
    assert(okC == false and tostring(whyC):find("не имеет доступа"), "fines: гражданин не должен иметь доступа: " .. tostring(whyC))
    fireHook("PlayerSay", civ, "/fine 100 тест") -- не должно падать и штрафовать
    assert(GRM.GetBalance(civ) == 4000, "fines: /fine от гражданина прошёл?!")
    fireHook("PlayerSay", officer, "/fines")
    local joined = table.concat(officer.__msgs, " ")
    assert(joined:find("Доступ штрафов"), "fines: /fines не напечатал статус: " .. joined)

    print("PHASE fines: OK — права/ключи sid+s64/кап/бюджет/пустой карман/админ-байпас//fines-статус")
    return
end

-- ======================= ФАЗА 15: ИНКАССАЦИЯ (Код 126 v2.0.0) =================
if PHASE == "incass" then
    GRM = GRM or {}
    dofile("lua/autorun/sh_grm_currency.lua")
    dofile("lua/autorun/sh_grm_economy.lua")
    dofile("lua/autorun/sh_grm_incassation.lua")
    local I = GRM.Incass

    local function mkUser(nick, sid64, sid)
        local p = mkPly(nick, sid64, sid)
        p.IsSuperAdmin = function() return false end
        p.__msgs = {}
        p.PrintMessage = function(_, _, m) p.__msgs[#p.__msgs + 1] = tostring(m) end
        p.GetEyeTrace = function() return { Entity = _G.__AIM_ENT } end
        return p
    end

    local incassator = mkUser("Hans Incass", "76561198000000700", "STEAM_0:1:700")
    local civ = mkUser("Karl Civ", "76561198000000300", "STEAM_0:1:300")
    _G.__PLAYERS = { incassator, civ }

    Factions.Polizei = {
        Members = { ["STEAM_0:1:700"] = { Role = "Officer", Department = "Основной" } },
        Leader = "STEAM_0:1:100", Roles = { "Officer" }, Departments = { "Основной" },
        IncassoSettings = { Enabled = true, Roles = { "Officer" }, Vehicles = { "simfphys_van" } },
    }

    -- 1. CanPlayerIncass: гражданин — отказ, инкассатор — OK
    local ok, err = I.CanPlayerIncass(civ)
    assert(ok == false, "incass: гражданин не должен иметь доступа")
    ok, err = I.CanPlayerIncass(incassator)
    assert(ok == true, "incass: офицер должен иметь доступ, а: " .. tostring(err))

    -- 2. Старт рейса в машине
    local car = ents.Create("prop_vehicle_jeep")
    car._isVeh = true
    car.GRM_IncassSpawnName = "simfphys_van"
    car._driver = incassator
    car:SetPos(Vector(0, 0, 0))
    incassator._veh = car

    local okRun, rid = I.StartRun(incassator)
    assert(okRun == true and rid, "incass: рейс не стартовал: " .. tostring(rid))
    assert(car:GetNWInt("GRM_IncassRun") == rid, "incass: NW runID не записан в машину")
    assert(incassator:GetNWEntity("GRM_IncassMyCar") == car, "incass: GRM_IncassMyCar не записан игроку")

    -- 3. Накопление денег в банкомате (5% от депозита)
    local atm = ents.Create("grm_bank_terminal")
    atm:SetPos(Vector(50, 0, 0))
    fireHook("GRM_Incass_TerminalDeposit", civ, 2000000, atm) -- 5% от 2 млн = 100 000 в банкомате
    local cashInAtm = I.TerminalCash[atm:EntIndex()] or 0
    assert(cashInAtm == 100000, "incass: 5% депозит не начислился в банкомат: " .. tostring(cashInAtm))

    -- 4. Изъятие из банкомата в чемодан (порция 50 000)
    incassator:SetPos(Vector(60, 0, 0))
    local okCol, colAmt = I.CollectFromTerminal(incassator, atm, 50000)
    assert(okCol == true and colAmt == 50000, "incass: сбор не удался: " .. tostring(colAmt))
    assert(I.PlayerBagAmount(incassator) == 50000, "incass: в руке нет чемодана 50000")
    assert(I.TerminalCash[atm:EntIndex()] == 50000, "incass: остаток в терминале не 50000")

    -- 5. Загрузка чемодана в машину
    incassator:SetPos(Vector(10, 0, 0))
    local okLoad, loadAmt = I.LoadBagIntoCar(incassator, car)
    assert(okLoad == true and loadAmt == 50000, "incass: загрузка в машину не удалась: " .. tostring(loadAmt))
    assert(I.PlayerBagAmount(incassator) == 0, "incass: чемодан остался в руке после загрузки")
    assert(car:GetNWInt("GRM_IncassCarCash") == 50000, "incass: в багажнике не 50000")

    -- 6. Разгрузка из машины доступна в ЛЮБОМ месте (не привязана к вольту)
    local okUnloadAny, unloadAmt = I.UnloadBagFromCar(incassator, car)
    assert(okUnloadAny == true and unloadAmt == 50000, "incass: свободная разгрузка машины не удалась: " .. tostring(unloadAmt))
    assert(I.PlayerBagAmount(incassator) == 50000, "incass: чемодан не выдан при свободной разгрузке")
    assert(car:GetNWInt("GRM_IncassCarCash") == 0, "incass: багажник не опустел")

    -- Создаём вольт и сдаём чемодан
    local vault = ents.Create("grm_bank_vault")
    vault:SetPos(Vector(100, 0, 0))
    incassator:SetPos(Vector(90, 0, 0))
    car:SetPos(Vector(80, 0, 0))

    -- 7. Сдача чемодана в хранилище банка (Направление А)
    local okVault, vaultAmt = I.LoadBagIntoVault(incassator, vault)
    assert(okVault == true and vaultAmt == 50000, "incass: сдача в вольт не удалась: " .. tostring(vaultAmt))
    assert(vault:GetHeldCash() == 50000, "incass: в вольте не 50000")
    assert(I.PlayerBagAmount(incassator) == 0, "incass: чемодан остался в руке после сдачи в вольт")

    -- 8. Развозка денег: забор из хранилища -> машина -> загрузка в банкомат (Направление Б)
    local okUnloadVault, fromVaultAmt = I.UnloadBagFromVault(incassator, vault)
    assert(okUnloadVault == true and fromVaultAmt == 50000, "incass: выгрузка из вольта не удалась")
    assert(vault:GetHeldCash() == 0, "incass: в вольте остались деньги после выгрузки")
    assert(I.PlayerBagAmount(incassator) == 50000, "incass: чемодан не в руке после выгрузки из вольта")

    -- Грузим в машину
    local okLoad2 = I.LoadBagIntoCar(incassator, car)
    assert(okLoad2 == true and car:GetNWInt("GRM_IncassCarCash") == 50000, "incass: повторная загрузка в машину не удалась")

    -- Едем к другому банкомату в городе и выгружаем
    local atm2 = ents.Create("grm_bank_terminal")
    atm2:SetPos(Vector(500, 0, 0))
    car:SetPos(Vector(490, 0, 0))
    incassator:SetPos(Vector(495, 0, 0))

    local okUnloadAtm2, unloadAmt2 = I.UnloadBagFromCar(incassator, car)
    assert(okUnloadAtm2 == true and unloadAmt2 == 50000, "incass: разгрузка у банкомата не удалась")

    -- Загружаем деньги из чемодана в банкомат
    local okLoadAtm, loadAtmAmt = I.LoadBagIntoTerminal(incassator, atm2)
    assert(okLoadAtm == true and loadAtmAmt == 50000, "incass: загрузка в банкомат не удалась: " .. tostring(loadAtmAmt))
    assert(I.TerminalCash[atm2:EntIndex()] == 50000, "incass: банкомат 2 не пополнился")
    assert(atm2:GetNWBool("GRM_IncassLocked") == true, "incass: банкомат 2 не заблокирован в режиме инкассации")

    -- Снимаем режим инкассации с банкомата
    local okUnlock = I.UnlockTerminal(incassator, atm2)
    assert(okUnlock == true, "incass: разблокировка банкомата не удалась")
    assert(atm2:GetNWBool("GRM_IncassLocked") == false, "incass: банкомат 2 остался заблокирован")

    -- 9. Завершение рейса /incass_off
    fireHook("PlayerSay", incassator, "/incass_off")
    assert(I.ActiveRuns[rid] == nil, "incass: рейс не закрылся")
    assert(car:GetNWInt("GRM_IncassRun") == 0, "incass: car runID не сброшен")
    assert(incassator:GetNWEntity("GRM_IncassMyCar") == nil or incassator:GetNWEntity("GRM_IncassMyCar") == NULL, "incass: MyCar не сброшен")

    -- 10. Персистентность балансов банкоматов (переживает рестарт!)
    -- Имитируем рестарт сервера: память очищена
    I.TerminalCash = {}
    local atmAfterRestart = ents.Create("grm_bank_terminal")
    atmAfterRestart:SetPos(Vector(500, 0, 0))
    local restored = I.RestoreTerminalCash(atmAfterRestart)
    assert(restored == 50000 and I.GetTerminalCash(atmAfterRestart) == 50000, "incass: баланс банкомата не пережил рестарт: " .. tostring(restored))

    -- Проводим 20 000 000 GRM через банкомат
    fireHook("GRM_Incass_TerminalDeposit", civ, 400000000, atmAfterRestart) -- 5% от 400 млн = 20 млн
    assert(I.GetTerminalCash(atmAfterRestart) == 20050000, "incass: 20 млн не начислились в банкомат")

    -- Снова рестарт
    I.TerminalCash = {}
    local atmAfterRestart2 = ents.Create("grm_bank_terminal")
    atmAfterRestart2:SetPos(Vector(500, 0, 0))
    local restored2 = I.RestoreTerminalCash(atmAfterRestart2)
    assert(restored2 == 20050000 and I.GetTerminalCash(atmAfterRestart2) == 20050000, "incass: 20 млн не пережили рестарт: " .. tostring(restored2))

    print("PHASE incass: OK — старт рейса/двунаправленная инкассация/персистентность баланса банкоматов (20 млн)/свободная разгрузка/финиш рейса")
    return
end

-- ======================= ФАЗА 16: ДОКУМЕНТЫ (Паспорта, Ксивы, Прикрытие) =====================
if PHASE == "documents" then
    GRM = GRM or {}
    dofile("lua/autorun/sh_grm_documents.lua")
    local DOC = GRM.Documents

    local function mkUser(nick, sid64, sid, slot)
        local p = mkPly(nick, sid64, sid)
        p.IsSuperAdmin = function() return false end
        p.__msgs = {}
        p.PrintMessage = function(_, _, m) p.__msgs[#p.__msgs + 1] = tostring(m) end
        p.GetNWString = function(_, k, d)
            if k == "GRM_RPName" then return nick end
            if k == "GRM_CharacterID" then return slot or "char1" end
            if k == "GRM_Faction" then return p.__fac or "" end
            if k == "GRM_Role" then return p.__role or "" end
            if k == "GRM_Department" then return p.__dept or "" end
            return d or ""
        end
        return p
    end

    local citizen = mkUser("Hans Schmidt", "76561199000000001", "STEAM_0:1:1", "char1")
    local officer = mkUser("Klaus Bauer",   "76561199000000002", "STEAM_0:1:2", "char1")
    officer.__fac = "OrdnungPolizei"
    officer.__role = "Инспектор"
    officer.__dept = "ДПС"

    -- 1. Создание и получение паспорта
    local pass = DOC.EnsurePassport(citizen)
    assert(istable(pass), "documents: паспорт не создан")
    assert(pass.charKey == "76561199000000001:char1", "documents: неверный charKey в паспорте")
    assert(pass.fullName == "Hans Schmidt", "documents: неверное ФИО в паспорте")

    -- 2. Создание и получение служебного удостоверения
    local badge = DOC.EnsureBadge(officer)
    assert(istable(badge), "documents: удостоверение не создано")
    assert(badge.faction == "OrdnungPolizei", "documents: неверная фракция в удостоверении")
    assert(badge.number:find("POL-"), "documents: префикс ведомства отсутствует в жетоне")
    assert(badge.permissions.weapon == true and badge.permissions.arrest == true, "documents: спецдопуски не применились")

    -- 3. Выдача военного билета
    DOC.Registry.military = DOC.Registry.military or {}
    DOC.Registry.military["76561199000000001:char1"] = {
        fullName  = "Hans Schmidt",
        rank      = "Сержант",
        vus       = "ВУС-100",
        formation = "Национальная гвардия",
        department= "Штаб",
        position  = "Командир отделения",
        number    = "ВБ-428901",
        status    = "Действителен",
    }

    -- 4. Сохранение и персистентность (переживает рестарт)
    DOC.SaveRegistry("test save")
    DOC.Registry = nil
    DOC.LoadRegistry()

    local passAfter = DOC.Registry.passports["76561199000000001:char1"]
    assert(istable(passAfter) and passAfter.fullName == "Hans Schmidt", "documents: паспорт не пережил рестарт")

    local badgeAfter = DOC.Registry.badges["76561199000000002:char1"]
    assert(istable(badgeAfter) and badgeAfter.faction == "OrdnungPolizei", "documents: удостоверение не пережило рестарт")

    local milAfter = DOC.Registry.military["76561199000000001:char1"]
    assert(istable(milAfter) and milAfter.rank == "Сержант" and milAfter.number == "ВБ-428901", "documents: военный билет не пережил рестарт")

    print("PHASE documents: OK — паспорта/служебные удостоверения/военные билеты/префиксы/спецдопуски/персистентность")
    return
end
