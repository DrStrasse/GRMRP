-- Симуляция Кода 110 (находка 127, «GrandEats»): кухня GRM —
-- плита (рецепты из сырья), холодильник (заморозка срока годности),
-- горшок (выращивание за деньги), порча приготовленного везде, кроме
-- холодильника. Грузит НАСТОЯЩИЕ sh_grm_food_config.lua,
-- sh_grm_inventory.lua, sh_grm_food_kitchen.lua и init.lua трёх
-- агрегатных энтити на моках. Время os.time()/CurTime() управляемое —
-- проверки детерминированные.
----------------------------------------------------------------------

local DATA = "tools/luatest/data"
os.execute("mkdir -p " .. DATA)

string.Trim = string.Trim or function(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
string.StartWith = string.StartWith or function(s, p) return s:sub(1, #p) == p end
table.Count = table.Count or function(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
table.Copy = table.Copy or function(t) local o = {} for k, v in pairs(t or {}) do o[k] = v end return o end
math.Clamp = math.Clamp or function(v, lo, hi) if v < lo then return lo end if v > hi then return hi end return v end
function AddCSLuaFile() end

-- ── честный JSON (как в sim_invphone) ───────────────────────────────
local function jsonEncode(v, pretty, ind)
    ind = ind or ""
    local t = type(v)
    if t == "nil" then return "null"
    elseif t == "boolean" or t == "number" then return tostring(v)
    elseif t == "string" then return '"' .. v:gsub("[%c\"\\]", function(c)
        local m = { ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t", ['"'] = '\\"', ["\\"] = "\\\\" }
        return m[c] or ("\\" .. c) end) .. '"'
    elseif t == "table" then
        local n = 0
        for i = 1, 1e9 do if v[i] ~= nil then n = i else break end end
        local isArr = true
        local cnt = 0
        for k in pairs(v) do cnt = cnt + 1 if type(k) ~= "number" or k < 1 or k > n or k ~= math.floor(k) then isArr = false break end end
        local pad = ind .. "    "
        if isArr then
            if cnt == 0 then return "[]" end
            local parts = {}
            for i = 1, n do parts[#parts + 1] = pad .. jsonEncode(v[i], pretty, pad) end
            return (pretty and "[\n" or "[") .. table.concat(parts, pretty and ",\n" or ",") .. (pretty and ("\n" .. ind) or "") .. "]"
        else
            local parts = {}
            for k, val in pairs(v) do parts[#parts + 1] = pad .. jsonEncode(tostring(k), false) .. (pretty and ": " or ":") .. jsonEncode(val, pretty, pad) end
            return (pretty and "{\n" or "{") .. table.concat(parts, pretty and ",\n" or ",") .. (pretty and ("\n" .. ind) or "") .. "}"
        end
    end
    error("jsonEncode: unsupported " .. t)
end
local function jsonDecode(s)
    local pos = 1
    local parseVal
    local function ws() while true do local c = s:sub(pos, pos) if c == " " or c == "\t" or c == "\n" or c == "\r" then pos = pos + 1 else break end end end
    parseVal = function()
        ws()
        local c = s:sub(pos, pos)
        if c == "{" then
            pos = pos + 1
            local t = {}
            ws()
            if s:sub(pos, pos) == "}" then pos = pos + 1 return t end
            while true do
                ws()
                if s:sub(pos, pos) == "}" then pos = pos + 1 return t end
                local k = parseVal()
                ws()
                if s:sub(pos, pos) ~= ":" then error("expected : at " .. pos) end
                pos = pos + 1
                t[tostring(k)] = parseVal()
                ws()
                c = s:sub(pos, pos)
                if c == "," then pos = pos + 1
                elseif c == "}" then pos = pos + 1 return t
                else error("expected , or } at " .. pos) end
            end
        elseif c == "[" then
            pos = pos + 1
            local t = {}
            local i = 1
            ws()
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
            local out = {}
            while pos <= #s do
                c = s:sub(pos, pos)
                if c == '"' then pos = pos + 1 return table.concat(out) end
                if c == "\\" then
                    local e = s:sub(pos + 1, pos + 1)
                    local m = { n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
                    if m[e] then out[#out + 1] = m[e] pos = pos + 2
                    elseif e == "u" then out[#out + 1] = "?" pos = pos + 6
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

-- ── окружение ────────────────────────────────────────────────────────
function istable(x) return type(x) == "table" end
function isstring(x) return type(x) == "string" end
function isnumber(x) return type(x) == "number" end
function isfunction(x) return type(x) == "function" end
function IsValid(o) return o ~= nil and o ~= false and not o.__removed end
HUD_PRINTTALK, HUD_PRINTCENTER = 3, 4

-- управляемое время: ВСЯ кухня ходит по os.time(), анти-спам по CurTime()
local NOW = 1700000000
local REAL_ostime = os.time
os.time = function() return NOW end
local CURT = 1000
CurTime = function() return CURT end

-- вектора с арифметикой (энтити-файлы делают GetPos()+GetForward()*N)
local VEC = {}
VEC.__index = VEC
VEC.__add = function(a, b) return setmetatable({ x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }, VEC) end
VEC.__mul = function(a, b) local s = isnumber(a) and a or b local v = isnumber(a) and b or a return setmetatable({ x = v.x * s, y = v.y * s, z = v.z * s }, VEC) end
function VEC:DistToSqr(o) local dx, dy, dz = self.x - o.x, self.y - o.y, self.z - o.z return dx * dx + dy * dy + dz * dz end
local function mkVec(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VEC) end
function Vector(x, y, z) return mkVec(x, y, z) end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
local vector_origin = mkVec(0, 0, 0)

local H = { hooks = {}, timers = {}, netlog = {}, chatlog = {}, notifies = {}, sounds = {}, world = {}, writeCount = 0, lastPayload = nil }
hook = {
    Add = function(name, id, fn) H.hooks[name] = H.hooks[name] or {} H.hooks[name][id] = fn end,
    Run = function(name, ...)
        for _, fn in pairs(H.hooks[name] or {}) do local r = fn(...) if r ~= nil then return r end end
    end,
}
timer = {
    Create = function(name, _, _, fn) H.timers[name] = fn end,
    Simple = function(_, fn) if fn then fn() end end,
    Remove = function(name) H.timers[name] = nil end,
    Exists = function(name) return H.timers[name] ~= nil end,
}
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
        local f = io.open(DATA .. "/" .. name, "rb")
        if f then f:close() return true end
        return false
    end,
    IsDir = function() return true end,
    CreateDir = function() end,
    Delete = function(name) os.remove(DATA .. "/" .. name) end,
}
util = {
    AddNetworkString = function() end,
    TableToJSON = function(t, pretty) return jsonEncode(t, pretty) end,
    JSONToTable = function(s, ignoreLimits, ignoreConversions)
        local ok, t = pcall(jsonDecode, s)
        if not ok then return nil end
        return t
    end,
}
net = {
    Start = function(m) H.netlog.cur = { msg = m } end,
    WriteTable = function(t)
        if H.netlog.cur and H.netlog.cur.msg == "GRM_Kitchen_Open" then
            H.writeCount = H.writeCount + 1
            H.lastPayload = t
        end
    end,
    WriteUInt = function() end, WriteString = function() end,
    WriteBool = function() end, WriteInt = function() end,
    Send = function() H.netlog.cur = nil end, Broadcast = function() H.netlog.cur = nil end,
    Receive = function(m, fn) H.recv = H.recv or {} H.recv[m] = fn end,
    ReadTable = function() return H.rtbl or {} end,
    ReadString = function() return table.remove(H.seqStr or {}, 1) or "" end,
    ReadUInt = function() return tonumber(table.remove(H.seq or {}, 1)) or 0 end,
    ReadBool = function() return false end, ReadInt = function() return 0 end,
}
ents = {
    Create = function(class)
        local f = _G["__mkEnt_" .. tostring(class)]
        if not f then return nil end
        local e = f(class)
        H.world[#H.world + 1] = e
        return e
    end,
    FindByClass = function(class)
        local out = {}
        for _, e in ipairs(H.world) do if e.__class == class and not e.__removed then out[#out + 1] = e end end
        return out
    end,
}
function Entity(idx) return H.entityByIdx and H.entityByIdx[tonumber(idx)] or nil end
player = { GetAll = function() return H.allPlayers or {} end }
game = { GetMap = function() return "gm_test" end }
concommand = { Add = function() end }
weapons = { Get = function() return nil end, IsBasedOn = function() return false end }

local ALLSID = 1
local function mkPly(money)
    ALLSID = ALLSID + 1
    local p = { __sid64 = "7656119800000" .. tostring(1000 + ALLSID), __hp = 100, __money = tonumber(money) or 0, __pos = mkVec(0, 0, 0) }
    return setmetatable(p, { __index = function(self, k)
        if k == "SteamID64" then return function() return self.__sid64 end end
        if k == "SteamID" then return function() return "STEAM_0:1:" .. tostring(ALLSID) end end
        if k == "Nick" then return function() return "P" .. tostring(self.__sid64) end end
        if k == "IsSuperAdmin" then return function() return true end end
        if k == "IsPlayer" then return function() return true end end
        if k == "GetPos" then return function() return self.__pos end end
        if k == "GetNWBool" then return function(_, _, default) return default or false end end
        if k == "PrintMessage" then return function(_, _, txt) H.chatlog[#H.chatlog + 1] = tostring(txt) end end
        if k == "ChatPrint" then return function(_, txt) H.chatlog[#H.chatlog + 1] = tostring(txt) end end
        if k == "Health" then return function() return self.__hp end end
        if k == "GetMaxHealth" then return function() return 100 end end
        if k == "SetHealth" then return function(_, v) self.__hp = v end end
        if k == "EmitSound" then return function() end end
        return nil
    end })
end

GRM = nil -- чистый неймспейс
SERVER, CLIENT = false, false

-- чистим данные прошлых прогонов
for _, f in ipairs({ "grm_inventories.json", "grm_hunger.json", "grm_perm_entities.json" }) do
    os.remove(DATA .. "/" .. f)
end

local checks, failed = 0, 0
local function ok(cond, name)
    checks = checks + 1
    if cond then print("  ok " .. tostring(checks) .. ". " .. name)
    else failed = failed + 1 print("  FAIL " .. tostring(checks) .. ". " .. name) end
end

local function lastNotifyHas(sub)
    local m = H.notifies[#H.notifies]
    return isstring(m) and m:find(sub, 1, true) ~= nil
end

-- ══════════════════ 1. КОНФИГ (заказ владельца) ═════════════════════
print("== 1. Код 110: конфиг — заказные позиции и кухня ==")
dofile("lua/autorun/sh_grm_food_config.lua")
local FC = GRM.Food.Config
local K = GRM.Food.Kitchen

ok(istable(FC.FoodItems["grm_food_milk"]) and FC.FoodItems["grm_food_milk"].model == "models/props_junk/garbage_milkcarton002a.mdl"
   and FC.FoodItems["grm_food_milk"].price > 0,
   "заказ 1: молоко с моделью garbage_milkcarton002a")
ok(istable(FC.FoodItems["grm_food_noodles"]) and FC.FoodItems["grm_food_noodles"].model == "models/props_junk/garbage_takeoutcarton001a.mdl"
   and FC.FoodItems["grm_food_noodles"].price > 0,
   "заказ 2: китайская лапша с моделью garbage_takeoutcarton001a")
do
    local vm = {}
    for _, id in ipairs(FC.VendingMachineItems or {}) do vm[id] = true end
    ok(vm["grm_food_milk"] and vm["grm_food_noodles"], "молоко и лапша в меню торгового автомата")
end
ok(K.StoveModel == "models/props_c17/furniturestove001a.mdl", "заказ 4: модель плиты furniturestove001a")
ok(K.FridgeModel == "models/props_c17/furniturefridge001a.mdl", "заказ 5: модель холодильника furniturefridge001a")
ok(FC.FoodItems["grm_food_potato"].raw == true and FC.FoodItems["grm_food_tomato"].raw == true
   and FC.FoodItems["grm_food_carrot"].raw == true,
   "сырые овощи помечены raw (урожай горшка, в автомат не ставятся)")
ok(FC.FoodItems["grm_food_fried_potato"].cooked == true and FC.FoodItems["grm_food_veg_soup"].cooked == true
   and FC.FoodItems["grm_food_milk_shake"].cooked == true and FC.FoodItems["grm_food_fried_noodles"].cooked == true,
   "готовые блюда помечены cooked (срок годности)")
ok(FC.FoodItems["grm_food_spoiled"].spoiled == true, "испорченная еда помечена spoiled")

-- целостность рецептов/культур: все ссылки существуют
do
    local cfgOK = true
    for rid, rec in pairs(K.Recipes or {}) do
        local out = FC.FoodItems[rec.out]
        if not (istable(out) and out.cooked and tonumber(rec.time)) then cfgOK = false end
        for itemID, need in pairs(rec.raw or {}) do
            if not istable(FC.FoodItems[itemID]) or (tonumber(need) or 0) < 1 then cfgOK = false end
        end
    end
    ok(cfgOK, "рецепты плиты: выходы cooked, ингредиенты существуют, время > 0")
    local cropOK = true
    for cid, c in pairs(K.Crops or {}) do
        local it = FC.FoodItems[c.item]
        if not (istable(it) and it.raw == true) or (tonumber(c.yield) or 0) < 1 then cropOK = false end
    end
    ok(cropOK, "культуры горшка ссылаются на существующие raw-овощи")
end
ok(tonumber(K.CookedSpoilSeconds) == 2700 and tonumber(K.SpoilSweepSeconds) == 30, "срок годности 45 мин, свипер 30 сек")

-- ══ 2. ИНВЕНТАРЬ + ЕДИНЫЙ net ПРОТОКОЛ КУХНИ ═══════════════════════
print("== 2. Загрузка инвентаря и модуля кухни ==")
SERVER, CLIENT = true, false
dofile("lua/autorun/sh_grm_inventory.lua")
ok(istable(GRM.Inventory) and isfunction(GRM.Inventory.AddItem), "настоящий инвентарь загружен")

-- дефы еды регистрирует прод-модуль zz_grm_food_inventory_patch; в симе — минимально необходимое
for id, d in pairs(FC.FoodItems) do
    GRM.Inventory.RegisterItem(id, { type = "item", name = d.name, maxStack = 10, weight = 0.3 })
end

-- экономика симовая (семантика автомата: модуль умеет жить и без неё)
H.notifies = {}
GRM.Notify = function(p, msg) H.notifies[#H.notifies + 1] = tostring(msg) end
GRM.HasMoney = function(p, n) return (tonumber(p.__money) or 0) >= (tonumber(n) or 0) end
GRM.TakeMoney = function(p, n) p.__money = (tonumber(p.__money) or 0) - (tonumber(n) or 0) end
GRM.Format = function(n) return tostring(n) .. "р." end

local ply = mkPly(1000)
H.allPlayers = { ply }

dofile("lua/autorun/sh_grm_food_kitchen.lua")
local FK = GRM.FoodKitchen
ok(FK.Version == "1.0.0" and istable(FK.Classes), "кухонный модуль v1.0.0 загружен")
ok(isfunction(H.recv and H.recv["GRM_Kitchen_Op"]), "ресивер GRM_Kitchen_Op зарегистрирован")
ok(timer.Exists("GRM_Kitchen_SpoilSweep"), "таймер свипера порчи зарегистрирован")
ok(FK.Storable("grm_food_milk") and not FK.Storable("grm_food_spoiled") and not FK.Storable("grm_junk_none"),
   "Storable: еда да, мусор/несуществующее — нет")
do
    local permOK = true
    for _, class in ipairs({ "grm_food_stove", "grm_food_fridge", "grm_food_planter" }) do
        if not (isfunction(GRM.PermData.Extract[class]) and isfunction(GRM.PermData.Apply[class])) then permOK = false end
    end
    ok(permOK, "PermData Extract/Apply зарегистрированы для 3 агрегатов")
end

-- модельный фолбэк (находка 85): нет валидатора — модель как есть; валидатор говорит «нет» — фолбэк
ok(FK.SafeModel(K.StoveModel) == K.StoveModel, "SafeModel без util.IsValidModel — отдаёт как есть")
util.IsValidModel = function() return false end
ok(FK.SafeModel(K.StoveModel) == tostring(K.ModelFallback), "SafeModel при «модели нет на сервере» → фолбэк-кружка")
util.IsValidModel = function(m) return isstring(m) and #m > 4 end
ok(FK.SafeModel(K.StoveModel) == K.StoveModel, "SafeModel с валидной моделью — как есть")
util.IsValidModel = function() return true end

-- ══ 3. ЗАГРУЗКА ЭНТИТИ (настоящие init.lua) ═════════════════════════
print("== 3. Загрузка агрегатных энтити ==")
include = function(f) dofile(tostring(H.entDir) .. "/" .. f) end

local ENTS = {}
for _, class in ipairs({ "grm_food_stove", "grm_food_fridge", "grm_food_planter" }) do
    H.entDir = "lua/entities/" .. class
    ENT = {}
    dofile(H.entDir .. "/init.lua")
    ENTS[class] = ENT
    ENT = nil
end
ok(isfunction(ENTS.grm_food_stove.kitchenOp) and isfunction(ENTS.grm_food_stove.BuildKitchenPayload)
   and isfunction(ENTS.grm_food_stove.KitchenPermData) and isfunction(ENTS.grm_food_stove.KitchenPermApply),
   "плита: kitchenOp/BuildKitchenPayload/PermData на месте")
ok(isfunction(ENTS.grm_food_fridge.FridgePut) and isfunction(ENTS.grm_food_planter.ArmPlanterTimer),
   "холодильник: FridgePut; горшок: ArmPlanterTimer")

local ENTIDX = 0
local function mkKitchenEnt(class)
    ENTIDX = ENTIDX + 1
    local E = ENTS[class]
    local e = { __class = class, __nw = {}, __idx = 100 + ENTIDX, __pos = mkVec(0, 0, 0) }
    function e:NetworkVar(t, _, name)
        local def = (t == "Int" or t == "Float") and 0 or (t == "String" and "" or (t == "Bool" and false or nil))
        e["Get" .. name] = function(s) local v = s.__nw[name] if v == nil then return def end return v end
        e["Set" .. name] = function(s, v) s.__nw[name] = v end
    end
    setmetatable(e, { __index = E })
    e:SetupDataTables()
    function e:SetModel(m) self.__model = m end
    function e:GetModel() return self.__model end
    function e:SetModelScale(s) self.__scale = s end
    function e:GetModelScale() return self.__scale or 1 end
    function e:PhysicsInit() end
    function e:SetMoveType() end
    function e:SetSolid() end
    function e:SetUseType() end
    function e:GetPhysicsObject() return nil end
    function e:EmitSound(snd) H.sounds[#H.sounds + 1] = tostring(snd) end
    function e:GetPos() return self.__pos end
    function e:GetForward() return mkVec(1, 0, 0) end
    function e:GetAngles() return Angle(0, 0, 0) end
    function e:EntIndex() return self.__idx end
    function e:GetClass() return self.__class end
    H.entityByIdx = H.entityByIdx or {}
    H.entityByIdx[e.__idx] = e
    e:Initialize()
    return e
end

-- мировые grm_food_item (DropFood)
_G.__mkEnt_grm_food_item = function(class)
    local e = { __class = class, __nw = {} }
    function e:SetPos(p) self.__pos = p end
    function e:GetPos() return self.__pos or mkVec(0, 0, 0) end
    function e:SetAngles() end
    function e:Spawn() self.__spawned = true end
    function e:SetModel(m) self.__model = m end
    function e:SetNWString(k, v) self.__nw[k] = v end
    function e:SetItemID(id) self.__itemID = id end
    function e:SetFoodItemID(id) self.__foodID = id self.GRMFoodItemID = id end
    return e
end

-- ══ 4. ПЛИТА: рецепт → готовка → лоток → выдача со сроком ═══════════
print("== 4. Плита ==")
local stove = mkKitchenEnt("grm_food_stove")
ok(stove.__model == K.StoveModel, "плита заспавнилась заказной моделью")
ok(GRM.Inventory.AddItem(ply, "grm_food_potato", 2) == 0, "сырьё: 2 картофеля в инвентаре")

stove:kitchenOp(ply, "stove_cook", { recipe = "fried_potato" })
ok(stove:GetStoveState() == 1 and stove:GetStoveRecipe() == "fried_potato", "готовка запущена (state=1, рецепт)")
ok(math.abs((tonumber(stove.FinishAt) or 0) - (NOW + 60)) <= 1, "финиш через recipe.time (60 сек)")
ok(GRM.Inventory.CountItem(ply, "grm_food_potato") == 0, "ингредиенты списаны из инвентаря")
ok(timer.Exists("GRM_Kitchen_Stove_" .. tostring(stove:EntIndex())), "таймер плиты взведён")

H.notifies = {}
stove:kitchenOp(ply, "stove_cook", { recipe = "fried_potato" })
ok(lastNotifyHas("занята"), "повторная готовка на занятой плите отклонена")

NOW = NOW + 61
H.timers["GRM_Kitchen_Stove_" .. tostring(stove:EntIndex())]()
ok(stove:GetStoveState() == 0 and #(stove.ReadyDishes or {}) == 1
   and stove.ReadyDishes[1] == "grm_food_fried_potato",
   "по времени блюдо легло на выходной лоток")

stove:kitchenOp(ply, "stove_collect", {})
ok(GRM.Inventory.CountItem(ply, "grm_food_fried_potato") == 1, "готовое блюдо забрано в инвентарь")
do
    local inv = GRM.Inventory.GetPlayerInv(ply)
    local spoilAtOK = false
    for i = 1, 24 do
        local s = inv.slots[i]
        if s and s.id == "grm_food_fried_potato" and istable(s.data) then
            spoilAtOK = math.abs((tonumber(s.data.spoilAt) or 0) - (NOW + 2700)) <= 1
        end
    end
    ok(spoilAtOK, "забранное блюдо несёт data.spoilAt = сейчас + 45 мин")
end

-- отмена: ингредиенты возвращаются
GRM.Inventory.AddItem(ply, "grm_food_potato", 2)
stove:kitchenOp(ply, "stove_cook", { recipe = "fried_potato" })
NOW = NOW + 5
H.notifies = {}
stove:kitchenOp(ply, "stove_cancel", {})
ok(stove:GetStoveState() == 0 and GRM.Inventory.CountItem(ply, "grm_food_potato") == 2,
   "отмена готовки вернула ингредиенты")

-- пэйлоад окна: рецепты с разбором ингредиентов
GRM.Inventory.RemoveItem(ply, "grm_food_potato", 99)
local pl = stove:BuildKitchenPayload(ply)
ok(istable(pl.recipes) and istable(pl.ready) and pl.now == NOW, "BuildKitchenPayload: recipes/ready/now")
do
    local fp
    for _, r in ipairs(pl.recipes) do if r.id == "fried_potato" then fp = r end end
    ok(istable(fp) and fp.can == false and istable(fp.need) and fp.need[1].have == 0,
       "без сырья рецепт помечен can=false, показано 0 в наличии")
end

-- перм: лоток и недожатая готовка переживают рестарт
GRM.Inventory.AddItem(ply, "grm_food_potato", 2)
stove:kitchenOp(ply, "stove_cook", { recipe = "fried_potato" })
NOW = NOW + 10
stove.ReadyDishes = { "grm_food_veg_soup" }
local stovePerm = GRM.PermData.Extract["grm_food_stove"](stove)
ok(stovePerm.recipe == "fried_potato" and math.abs((tonumber(stovePerm.remain) or 0) - 50) <= 1
   and istable(stovePerm.ready) and stovePerm.ready[1] == "grm_food_veg_soup",
   "PermData плиты: рецепт + остаток 50c + лоток")
local stove2 = mkKitchenEnt("grm_food_stove")
GRM.PermData.Apply["grm_food_stove"](stove2, stovePerm)
ok(stove2:GetStoveState() == 1 and stove2:GetStoveRecipe() == "fried_potato"
   and math.abs((tonumber(stove2.FinishAt) or 0) - (NOW + 50)) <= 1
   and istable(stove2.ReadyDishes) and stove2.ReadyDishes[1] == "grm_food_veg_soup",
   "рестарт-применение: готовка продолжается, лоток восстановлен")
stove:kitchenOp(ply, "stove_cancel", {}) -- прибраться

-- ══ 5. ХОЛОДИЛЬНИК: заморозка срока годности ════════════════════════
print("== 5. Холодильник ==")
local fridge = mkKitchenEnt("grm_food_fridge")
ok(fridge.__model == K.FridgeModel, "холодильник заспавнился заказной моделью")

GRM.Inventory.RemoveItem(ply, "grm_food_fried_potato", 99) -- хвост от секции плиты: чистим инвентарь детерминированно
-- две порции с одинаковым остатком складываются в ОДИН слот
FK.GiveFood(ply, "grm_food_fried_potato", 1)
NOW = NOW + 10
FK.GiveFood(ply, "grm_food_fried_potato", 1)
fridge:kitchenOp(ply, "fridge_store", { id = "grm_food_fried_potato", n = 2 })
ok(GRM.Inventory.CountItem(ply, "grm_food_fried_potato") == 0, "обе порции убраны из инвентаря")
ok(#(fridge.FoodSlots or {}) == 1 and fridge.FoodSlots[1].n == 2
   and math.abs((tonumber(fridge.FoodSlots[1].remain) or 0) - 2700) <= 11,
   "порции склеились в один слот с замороженным остатком ~2700c")

NOW = NOW + 500 -- «прошло» 8+ минут: в холодильнике время НЕ тикает
ok(fridge.FoodSlots[1].remain == (2700 - 0) or math.abs(fridge.FoodSlots[1].remain - 2700) <= 11,
   "остаток в холодильнике заморожен: не изменился за 500 сек")
fridge:kitchenOp(ply, "fridge_take", { slot = 1, n = 1 })
do
    local inv = GRM.Inventory.GetPlayerInv(ply)
    local backOK = false
    for i = 1, 24 do
        local s = inv.slots[i]
        if s and s.id == "grm_food_fried_potato" and istable(s.data) then
            -- выданное продолжает портиться с ТОГО ЖЕ остатка
            backOK = math.abs((tonumber(s.data.spoilAt) or 0) - (NOW + (2700 - (2700 - fridge.FoodSlots[1].remain)))) <= 2
                or math.abs((tonumber(s.data.spoilAt) or 0) - (NOW + 2690)) <= 12
        end
    end
    ok(backOK, "взятая порция получила spoilAt = сейчас + сохранённый остаток")
end
ok(#(fridge.FoodSlots or {}) == 1 and fridge.FoodSlots[1].n == 1, "в слоте осталась 1 порция")

-- мусор не храним
H.notifies = {}
GRM.Inventory.AddItem(ply, "grm_food_spoiled", 1)
fridge:kitchenOp(ply, "fridge_store", { id = "grm_food_spoiled", n = 1 })
ok(#fridge.FoodSlots == 1 and lastNotifyHas("нельзя"), "испорченную еду холодильник не принимает")

-- пэйлоад: слоты + что можно положить
do
    local pl2 = fridge:BuildKitchenPayload(ply)
    ok(istable(pl2.slots) and pl2.slots[1] and pl2.slots[1].n == 1 and pl2.slots[1].cooked == true,
       "BuildKitchenPayload: слот отдан с флагом cooked")
    local hasStore = false
    for _, s in ipairs(pl2.store or {}) do if s.id == "grm_food_fried_potato" then hasStore = true end end
    ok(hasStore, "BuildKitchenPayload: из инвентаря предлагается убрать имеющееся")
end

-- перм: слоты едут как есть (время заморожено)
local frPerm = GRM.PermData.Extract["grm_food_fridge"](fridge)
local fridge2 = mkKitchenEnt("grm_food_fridge")
GRM.PermData.Apply["grm_food_fridge"](fridge2, frPerm)
ok(#(fridge2.FoodSlots or {}) == 1 and fridge2.FoodSlots[1].id == "grm_food_fried_potato"
   and fridge2.FoodSlots[1].remain == fridge.FoodSlots[1].remain,
   "перм холодильника: слот и замороженный остаток пережили рестарт")

-- содержимое холодильника свипер НЕ трогает
NOW = NOW + 10000
FK._devSpoilSweep()
ok(#(fridge.FoodSlots or {}) == 1 and fridge2.FoodSlots[1].id == "grm_food_fried_potato",
   "свипер порчи холодильник не трогает — там заморозка")

-- ══ 6. ГОРШОК: семена за деньги, полив, урожай ══════════════════════
print("== 6. Горшок ==")
local planter = mkKitchenEnt("grm_food_planter")
ok(planter.__model == K.PotModel, "пустой горшок — кадка terracotta01")
local moneyBefore = ply.__money
planter:kitchenOp(ply, "planter_plant", { crop = "potato" })
ok(planter:GetPlanterState() == 1 and planter:GetPlanterCrop() == "potato", "картофель посажен (state=1)")
ok(math.abs((tonumber(planter.FinishAt) or 0) - (NOW + 240)) <= 1, "созреет через growSeconds=240")
ok(ply.__money == moneyBefore - 15, "семена списали 15 (как покупка в автомате)")
ok(math.abs((planter:GetModelScale() or 1) - 0.45) < 0.01, "саженец — масштаб 0.45")

H.notifies = {}
planter:kitchenOp(ply, "planter_plant", { crop = "tomato" })
ok(lastNotifyHas("уже что-то растёт"), "вторая посадка на занятый горшок отклонена")

planter:kitchenOp(ply, "planter_water", {})
ok(math.abs((tonumber(planter.FinishAt) or 0) - (NOW + 180)) <= 1, "полив срезал 25% остатка (240→180)")
ok((tonumber(planter.WaterAt) or 0) == NOW + 60, "кулдаун полива 60 сек")
H.notifies = {}
planter:kitchenOp(ply, "planter_water", {})
ok(lastNotifyHas("подождите"), "повторный полив раньше кулдауна отклонён")

NOW = NOW + 181
H.timers["GRM_Kitchen_Planter_" .. tostring(planter:EntIndex())]()
ok(planter:GetPlanterState() == 2 and math.abs((planter:GetModelScale() or 0) - 1.0) < 0.01,
   "по таймеру — урожай готов (state=2, масштаб 1.0)")
GRM.Inventory.RemoveItem(ply, "grm_food_potato", 99) -- детерминизм: ранее в секциях картофель уже ходил
planter:kitchenOp(ply, "planter_harvest", {})
ok(planter:GetPlanterState() == 0 and GRM.Inventory.CountItem(ply, "grm_food_potato") == 3,
   "урожай собран: 3 сырых картофеля, горшок снова пустой кадкой")

-- ленивая догонка: даже без тика таймера созревший урожай собирается
planter:kitchenOp(ply, "planter_plant", { crop = "carrot" })
NOW = NOW + 999
planter:kitchenOp(ply, "planter_harvest", {})
ok(GRM.Inventory.CountItem(ply, "grm_food_carrot") == 3, "ленивая догонка: сбор без тика таймера")

-- без экономики — бесплатно (семантика автомата)
local hm, tm = GRM.HasMoney, GRM.TakeMoney
GRM.HasMoney, GRM.TakeMoney = nil, nil
planter:kitchenOp(ply, "planter_plant", { crop = "tomato" })
ok(planter:GetPlanterState() == 1, "нет модуля денег — посадка бесплатна (как автомат)")
GRM.HasMoney, GRM.TakeMoney = hm, tm
planter:kitchenOp(ply, "planter_harvest", {}) -- ждать не будем — уберём «вручную» через перм-сброс ниже
planter:SetPlanterState(0) planter.PlantedCrop = "" planter:SetPlanterCrop("")

-- перм горшка: культура + остаток + полив
planter:kitchenOp(ply, "planter_plant", { crop = "potato" })
planter:kitchenOp(ply, "planter_water", {})
local plPerm = GRM.PermData.Extract["grm_food_planter"](planter)
local planter2 = mkKitchenEnt("grm_food_planter")
GRM.PermData.Apply["grm_food_planter"](planter2, plPerm)
ok(planter2:GetPlanterState() == 1 and planter2:GetPlanterCrop() == "potato"
   and math.abs((tonumber(planter2.FinishAt) or 0) - (NOW + 180)) <= 2
   and math.abs((tonumber(planter2.WaterAt) or 0) - (NOW + 60)) <= 2,
   "перм горшка: культура/остаток/кулдаун полива пережили рестарт")
NOW = NOW + 500 -- «рестарт занял» дольше срока: сразу готово
local plPerm2 = GRM.PermData.Extract["grm_food_planter"](planter2)
local planter3 = mkKitchenEnt("grm_food_planter")
GRM.PermData.Apply["grm_food_planter"](planter3, { crop = "potato", remain = 0, water = 0 })
ok(planter3:GetPlanterState() == 2, "рестарт после срока: урожай сразу готов (state=2)")

-- ══ 7. ПОРЧА: инвентарь гниёт, мир гниёт ════════════════════════════
print("== 7. Порча приготовленного вне холодильника ==")
GRM.Inventory.RemoveItem(ply, "grm_food_fried_potato", 99)
GRM.Inventory.RemoveItem(ply, "grm_food_spoiled", 99) -- мусор от «холодильного» свипа секции 5
FK.GiveFood(ply, "grm_food_fried_potato", 1)   -- cooked, spoilAt = NOW+2700
GRM.Inventory.AddItem(ply, "grm_food_apple", 1) -- упаковка: НЕ портится
NOW = NOW + 2800
H.notifies = {}
FK._devSpoilSweep()
ok(GRM.Inventory.CountItem(ply, "grm_food_fried_potato") == 0
   and GRM.Inventory.CountItem(ply, "grm_food_spoiled") == 1,
   "просроченное блюдо в инвентаре стало «Испорченной едой»")
ok(GRM.Inventory.CountItem(ply, "grm_food_apple") == 1, "упаковка из автомата не портится")
ok(lastNotifyHas("Испортилось"), "игроку сообщили о порче")

-- мир: grm_food_item с мировым сроком превращается в мусор на месте
local droppedBefore = #H.world
FK.DropFood("grm_food_milk_shake", 1, mkVec(5, 5, 5), Angle(0, 0, 0))
ok(#H.world == droppedBefore + 1 and tonumber(H.world[#H.world].GRMFoodSpoilAt) == NOW + 2700,
   "DropFood кладёт мировой срок годности на cooked-предмет")
NOW = NOW + 2800
FK._devSpoilSweep()
ok(H.world[#H.world].GRMFoodItemID == "grm_food_spoiled" and H.world[#H.world].__foodID == "grm_food_spoiled",
   "просроченный предмет в мире стал мусором через SetFoodItemID")

-- ══ 8. ЕДИНЫЙ ПРОТОКОЛ: диспетчер, живое окно, рамки ═══════════════
print("== 8. Диспетчер GRM_Kitchen_Op: дистанция/антиспам/живое окно ==")
stove.ReadyDishes = {} stove:SyncReadyNW() -- лоток после перм-теста прибран
CURT = 5000
ply.__grmKitchenNextOp = 0
H.writeCount = 0
H.seq = { stove:EntIndex() } H.seqStr = { "stove_collect" } H.rtbl = {}
-- лоток пуст (прибрали выше) → отказ-нотификация, но пэйлоад живого окна ВСЕГДА свежий
H.notifies = {}
H.recv["GRM_Kitchen_Op"](0, ply)
ok(lastNotifyHas("Лоток пуст"), "диспетчер: операция доехала до энтити (лоток пуст)")
ok(H.writeCount == 1 and istable(H.lastPayload) and H.lastPayload.kind == "stove"
   and H.lastPayload.idx == stove:EntIndex(),
   "после операции — живой свежий пэйлоад с kind/idx")

-- анти-спам (быстрый человек, н124): второй пакет в тот же тик — молча
H.recv["GRM_Kitchen_Op"](0, ply)
ok(H.writeCount == 1, "анти-спам 0.2с: мгновенный дубль отброшен")
CURT = CURT + 0.3
H.seq = { stove:EntIndex() } H.seqStr = { "stove_collect" } H.rtbl = {}
H.recv["GRM_Kitchen_Op"](0, ply)
ok(H.writeCount == 2, "после окна кулдауна операция снова принимается")

-- дистанция: дальше UseDistance — вежливый отказ
ply.__pos = mkVec(99999, 0, 0)
CURT = CURT + 0.3
H.notifies = {}
H.seq = { stove:EntIndex() } H.seqStr = { "stove_collect" } H.rtbl = {}
H.recv["GRM_Kitchen_Op"](0, ply)
ok(lastNotifyHas("ближе") and H.writeCount == 2, "дальше 150 юнитов — операция не доходит")
ply.__pos = mkVec(0, 0, 0)

-- чужой класс/битый индекс — молчание без краша
CURT = CURT + 0.3
H.seq = { 99999 } H.seqStr = { "stove_collect" } H.rtbl = {}
H.recv["GRM_Kitchen_Op"](0, ply)
ok(H.writeCount == 2, "битый EntIndex отброшен тихо")

-- ══ 9. СТРАЖИ ПРОДАКШН-ФАЙЛОВ ═══════════════════════════════════════
print("== 9. Регресс-стражи ==")
do
    local clean = true
    for _, f in ipairs({
        "lua/autorun/sh_grm_food_config.lua",
        "lua/autorun/sh_grm_food_kitchen.lua",
        "lua/autorun/client/cl_grm_food_kitchen.lua",
        "lua/entities/grm_food_stove/init.lua",
        "lua/entities/grm_food_fridge/init.lua",
        "lua/entities/grm_food_planter/init.lua",
    }) do
        local fh = io.open(f, "r")
        local src = fh and fh:read("*a") or ""
        if fh then fh:close() end
        if src:find("continue", 1, true) then clean = false end
        if src == "" then clean = false end
    end
    ok(clean, "прод-файлы кухни без `continue` (ванильный LuaJIT, загружаемость стендом)")
end
do
    -- клиентское окно: единый протокол, живое перенаполнение, все операции
    local fh = io.open("lua/autorun/client/cl_grm_food_kitchen.lua", "r")
    local src = fh and fh:read("*a") or ""
    if fh then fh:close() end
    ok(src:find("GRM_Kitchen_Open", 1, true) ~= nil and src:find("stove_cook", 1, true) ~= nil
       and src:find("fridge_take", 1, true) ~= nil and src:find("planter_plant", 1, true) ~= nil
       and src:find("planter_water", 1, true) ~= nil and src:find("planter_harvest", 1, true) ~= nil
       and src:find("stove_collect", 1, true) ~= nil and src:find("stove_cancel", 1, true) ~= nil
       and src:find("fridge_store", 1, true) ~= nil,
       "клиентское окно: полный набор операций обоих видов")
    ok(src:find("openOrRefill", 1, true) ~= nil and src:find("WIN.idx == idx", 1, true) ~= nil,
       "живое окно: повторный пэйлоад перенаполняет, а не множит фреймы")
end
do
    -- перм-модуль v1.6.0 допускает классы кухни
    local fh = io.open("lua/autorun/sh_grm_perm_entities.lua", "r")
    local src = fh and fh:read("*a") or ""
    if fh then fh:close() end
    ok(src:find('PERM_VER = "1.6.0"', 1, true) ~= nil
       and src:find("grm_food_stove", 1, true) ~= nil
       and src:find("grm_food_fridge", 1, true) ~= nil
       and src:find("grm_food_planter", 1, true) ~= nil,
       "sh_grm_perm_entities v1.6.0: классы кухни допущены к /permadd")
end

print("")
print(("РЕЗУЛЬТАТ: %d/%d проверок, провалов: %d"):format(checks - failed, checks, failed))
if failed > 0 then os.exit(1) end
print("SIM FOODKITCHEN: OK")
