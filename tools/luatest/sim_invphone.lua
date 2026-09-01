-- Симуляция Кода 88/97: телефон в инвентаре ДОЛЖЕН переживать рестарт сервера.
-- Грузит НАСТОЯЩИЙ sh_grm_inventory.lua на моках, телефон кладётся AddItem,
-- «рестарт» = повторный dofile модуля поверх того же диска.
-- находка 114: инвентарь сейвился ТОЛЬКО автотаймером 10с + ShutDown —
-- жёсткий рестарт хоста в окне до 10с после покупки стирал телефон.
----------------------------------------------------------------------

local DATA = "tools/luatest/data"
os.execute("mkdir -p " .. DATA)

string.Trim = string.Trim or function(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
string.StartWith = string.StartWith or function(s, p) return s:sub(1, #p) == p end
table.Count = table.Count or function(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
table.Copy = table.Copy or function(t) local o = {} for k, v in pairs(t or {}) do o[k] = v end return o end
math.Clamp = math.Clamp or function(v, lo, hi) if v < lo then return lo end if v > hi then return hi end return v end
function AddCSLuaFile() end

-- ── честный JSON (копия движка roundtrip_test.lua) ──────────────────
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
            pos = pos + 1
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
-- эмуляция GMod: JSONToTable без 3-го аргумента конвертирует числовые ключи
local function convertKeysR(t)
    local ks = {}
    for k in pairs(t) do ks[#ks + 1] = k end
    for _, k in ipairs(ks) do
        local v = rawget(t, k)
        if isstring(k) then
            local n = tonumber(k)
            if n ~= nil then rawset(t, k, nil) rawset(t, n, v) end
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

-- ── окружение ────────────────────────────────────────────────────────
function istable(x) return type(x) == "table" end
function isstring(x) return type(x) == "string" end
function isnumber(x) return type(x) == "number" end
function isfunction(x) return type(x) == "function" end
function IsValid(o) return o ~= nil and o ~= false and not o.__removed end
HUD_PRINTTALK, HUD_PRINTCENTER = 3, 4
vector_origin = { x = 0, y = 0, z = 0 }

local H = { hooks = {}, timers = {}, netlog = {}, chatlog = {} }
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
net = {
    Start = function(m) H.netlog.cur = { msg = m } end,
    WriteTable = function() end, WriteUInt = function() end, WriteString = function() end,
    WriteBool = function() end, WriteInt = function() end,
    Send = function() H.netlog.cur = nil end, Broadcast = function() H.netlog.cur = nil end,
    Receive = function(m, fn) H.recv = H.recv or {} H.recv[m] = fn end,
    ReadTable = function() return {} end, ReadString = function() return "" end,
    ReadUInt = function() return tonumber(table.remove(H.seq or {}, 1)) or 0 end,
    ReadBool = function() return false end, ReadInt = function() return 0 end,
}
ents = { Create = function() return nil end, FindByClass = function() return {} end }
player = { GetAll = function() return {} end }
game = { GetMap = function() return "gm_test" end }
concommand = { Add = function() end }
weapons = { Get = function() return nil end, IsBasedOn = function() return false end }
surface = nil

local function mkPly(sid64)
    local p = { __sid64 = sid64, __hp = 100, __ar = 0 }
    return setmetatable(p, { __index = function(self, k)
        if k == "SteamID64" then return function() return self.__sid64 end end
        if k == "SteamID" then return function() return "STEAM_0:1:1" end end
        if k == "Nick" then return function() return "P" .. tostring(self.__sid64) end end
        if k == "IsSuperAdmin" then return function() return true end end
        if k == "IsPlayer" then return function() return true end end
        if k == "GetActiveWeapon" then return function() return nil end end
        if k == "GetShootPos" then return function() return vector_origin end end
        if k == "GetAimVector" then return function() return vector_origin end end
        if k == "GetPos" then return function() return vector_origin end end
        if k == "GetNWBool" then return function(_, _, default) return default or false end end
        if k == "PrintMessage" then return function(_, _, txt) H.chatlog[#H.chatlog + 1] = tostring(txt) end end
        if k == "Health" then return function() return self.__hp end end
        if k == "GetMaxHealth" then return function() return 100 end end
        if k == "SetHealth" then return function(_, v) self.__hp = v end end
        if k == "Armor" then return function() return self.__ar end end
        if k == "SetArmor" then return function(_, v) self.__ar = v end end
        if k == "EmitSound" then return function() end end
        return nil
    end })
end
CurTime = CurTime or os.clock

GRM = nil -- гарантированно чистый неймспейс
SERVER, CLIENT = true, false
os.remove(DATA .. "/grm_inventories.json")
os.remove(DATA .. "/grm_inventories_backup.json")
os.remove(DATA .. "/grm_inventories_write_tmp.json")

local traces = {}

-- Ядро GRM (sh_00_grm_ui + sh_01_grm_core) — как на сервере, до модулей.
dofile("tools/luatest/lib_grm_core.lua")()
dofile("lua/autorun/sh_grm_inventory.lua")
GRM.Trace = traces -- отладка (не мешает модулю)

local checks, failed = 0, 0
local function ok(cond, name)
    checks = checks + 1
    if cond then print("  ok " .. tostring(checks) .. ". " .. name)
    else failed = failed + 1 print("  FAIL " .. tostring(checks) .. ". " .. name) end
end

local ply = mkPly("76561198000000012")

-- телефон-деф как в мобильном модуле
GRM.Inventory.RegisterItem("mobile_badger", { type = "item", name = "Телефон: Badger", maxStack = 1, weight = 0.35 })

-- Код 106 (находка 123): статический деф модулятора — ДО любых внешних
-- регистраций (доказательство, что useFunc не зависит от порядка загрузки)
local earlyModDef = GRM.Inventory.GetItemDef("radio_modulator")
ok(istable(earlyModDef) and earlyModDef.useFunc == "radio_toggle" and earlyModDef.maxStack == 1
   and earlyModDef.model == "models/props_lab/reciever01b.mdl",
   "Код 106: деф radio_modulator есть СРАЗУ из sh_grm_inventory (статический, до внешних регистраций)")

print("== 1. Покупка телефона в инвентарь ==")
local left = GRM.Inventory.AddItem(ply, "mobile_badger", 1)
ok((left or 1) == 0, "AddItem: телефон принят (возврат 0)")
ok(GRM.Inventory.CountItem(ply, "mobile_badger") == 1, "CountItem: 1 телефон до рестарта")
-- патроны рядом, дыра в слотах для проверки разрежённой карты
GRM.Inventory.AddItem(ply, "ammo_pistol", 30)
GRM.Inventory.RemoveItem(ply, "mobile_badger", 1)
ok(GRM.Inventory.CountItem(ply, "mobile_badger") == 0, "телефон убран → разрежённая карта слотов (ammo в слоте 2)")
GRM.Inventory.AddItem(ply, "mobile_badger", 1)

print("== 2. Автосейв ==")
ok(H.timers["GRM_Inv_AutoSave"] ~= nil, "автотаймер сейва зарегистрирован")
H.timers["GRM_Inv_AutoSave"]()
ok(file.Exists("grm_inventories.json"), "файл grm_inventories.json создан автотаймером")
ok(file.Exists("grm_inventories_backup.json"), "проверенная резервная копия инвентаря создана вместе с main")
local raw = file.Read("grm_inventories.json") or ""
ok(string.find(raw, "mobile_badger", 1, true) ~= nil, "телефон есть в JSON на диске")

print("== 3. Жёсткий рестарт (процесс убит, только файл) ==")
dofile("lua/autorun/sh_grm_inventory.lua") -- модуль перегружается с нуля
ok(GRM.Inventory.CountItem(ply, "mobile_badger") == 1, "ПОСЛЕ РЕСТАРТА: телефон на месте (CountItem=1)")
ok(GRM.Inventory.CountItem(ply, "ammo_pistol") == 30, "патроны на месте")

print("== 3.5. Битый main восстанавливается из backup без потери документов/предметов ==")
file.Write("grm_inventories.json","{broken json")
dofile("lua/autorun/sh_grm_inventory.lua")
ok(GRM.Inventory.CountItem(ply,"mobile_badger")==1 and GRM.Inventory.CountItem(ply,"ammo_pistol")==30,"backup восстановил полный инвентарь")
ok((file.Read("grm_inventories.json")or""):find("mobile_badger",1,true)~=nil,"main автоматически вылечен из backup")

print("== 4. Дебаунс-автосейв на мутациях (v н114): покупка → файл за 2с ==")
os.remove(DATA .. "/grm_inventories.json")
-- имитируем новую покупку сразу после рестарта — файл стёрт, дебаунс обязан восстановить
GRM.Inventory.AddItem(ply, "mobile_badger", 1)
ok(H.timers["GRM_Inv_SaveSoon"] ~= nil, "дебаунс-таймер GRM_Inv_SaveSoon взведён после AddItem")
H.timers["GRM_Inv_SaveSoon"]()
ok(file.Exists("grm_inventories.json"), "файл восстановлен дебаунсом БЕЗ ожидания 10с")
raw = file.Read("grm_inventories.json") or ""
ok(string.find(raw, "mobile_badger", 1, true) ~= nil, "телефон в файле после дебаунса")

print("== 5. Ключи слотов после JSON — строго числовые (нормализация) ==")
local inv = GRM.Inventory.GetPlayerInv(ply)
local strKeys = 0
for k in pairs(inv.slots or {}) do if isstring(k) then strKeys = strKeys + 1 end end
ok(strKeys == 0, "строковых ключей в слотах после лоада: 0 (нормализованы)")

print("== 6. Rescue: файл, убитый СТАРЫМ лоадером (ключ-число), долечивается ==")
-- эмулируем вред одного цикла старого кода: bare-parse (ключи → double) + пересейв
local bad = util.JSONToTable(file.Read("grm_inventories.json") or "")
file.Write("grm_inventories.json", util.TableToJSON(bad, true))
dofile("lua/autorun/sh_grm_inventory.lua") -- рестарт с фиксом
ok(GRM.Inventory.CountItem(ply, "mobile_badger") == 1, "легаси-файл с битым ключом: телефон ВОССТАНОВЛЕН rescue-цепочкой")
local raw2 = file.Read("grm_inventories.json") or ""
H.timers["GRM_Inv_SaveSoon"] = H.timers["GRM_Inv_SaveSoon"] or nil

print("== 7. Код 99: модулятор рации — toggle живёт в предмете, переживает всё ==")
GRM.Notify = GRM.Notify or function() end
GRM.Inventory.RegisterItem("radio_modulator", { type = "item", name = "Модулятор рации (переносной)", maxStack = 1, useFunc = "radio_toggle" })
GRM.Inventory.AddItem(ply, "radio_modulator", 1)
inv = GRM.Inventory.GetPlayerInv(ply) -- перечитаем после рестартов выше
local slotIdx
for i = 1, 24 do local s = inv.slots[i] if s and s.id == "radio_modulator" then slotIdx = i break end end
ok(slotIdx ~= nil, "модулятор лежит в инвентаре (покупка)")
H.seq = { slotIdx } H.recv["grm_inv_use"](0, ply)
ok(inv.slots[slotIdx] ~= nil and istable(inv.slots[slotIdx].data) and inv.slots[slotIdx].data.on == true, "«Использовать» → модулятор ВКЛ (data.on=true, предмет не тратится)")
H.seq = { slotIdx } H.recv["grm_inv_use"](0, ply)
ok(inv.slots[slotIdx].data.on == false, "повторное использование → ВЫКЛ")
H.seq = { slotIdx } H.recv["grm_inv_use"](0, ply)
ok(inv.slots[slotIdx].data.on == true, "третье → снова ВКЛ")
-- дебаунс-сейв от ресивера + жёсткий рестарт: состояние на диске
H.timers["GRM_Inv_SaveSoon"]()
dofile("lua/autorun/sh_grm_inventory.lua")
-- перезагрузка модуля пересобирает ItemDefs — как в живом GMod, предмет
-- регистрирует свой модуль (RadioNet) при старте, в симе повторяем вручную
GRM.Inventory.RegisterItem("radio_modulator", { type = "item", name = "Модулятор рации (переносной)", maxStack = 1, useFunc = "radio_toggle" })
local inv2 = GRM.Inventory.GetPlayerInv(ply)
local foundOn = false
for i = 1, 24 do local s = inv2.slots[i] if s and s.id == "radio_modulator" then foundOn = istable(s.data) and s.data.on == true end end
ok(foundOn, "ПОСЛЕ РЕСТАРТА модулятор на месте и ВКЛЮЧЁН (slot.data в сейве)")
-- подбор с земли: AddItem возвращает данные экземпляра (Код 99, 4-й аргумент)
GRM.Inventory.AddItem(ply, "radio_modulator", 1, { on = true })
local onCount = 0
for i = 1, 24 do local s = inv2.slots[i] if s and s.id == "radio_modulator" and istable(s.data) and s.data.on == true then onCount = onCount + 1 end end
ok(onCount == 2, "AddItem(+data): второй модулятор лёг со СВОИМ включённым состоянием")

print("== 8. Код 101: медкарта на руках — «Использовать» открывает просмотр, предмет цел ==")
-- симулируем выдачу: врач положил карту с sid64 владельца (см. sh_grm_medical op «issue»)
local patient = mkPly("76561198000000077")
GRM.Inventory.RegisterItem("medcard", { type = "item", name = "Медицинская карта", maxStack = 1, weight = 0.2, useFunc = "medcard_view" })
GRM.Inventory.AddItem(patient, "medcard", 1, { sid64 = "76561198000000077" })
local viewCalls = { n = 0 }
GRM.Medical = GRM.Medical or {}
GRM.Medical.ViewIssued = function(p, data) viewCalls.n = viewCalls.n + 1 viewCalls[viewCalls.n] = data or false end
local pinv = GRM.Inventory.GetPlayerInv(patient)
local mslot
for i = 1, 24 do local s = pinv.slots[i] if s and s.id == "medcard" then mslot = i break end end
ok(mslot ~= nil, "медкарта выдана (в слоте с sid64 владельца)")
H.seq = { mslot } H.recv["grm_inv_use"](0, patient)
ok(viewCalls.n == 1, "useFunc medcard_view: вызван MD.ViewIssued")
ok(viewCalls.n == 1 and istable(viewCalls[1]) and viewCalls[1].sid64 == "76561198000000077",
   "ViewIssued получил ТЕ ЖЕ данные экземпляра (sid64 владельца)")
ok(pinv.slots[mslot] ~= nil and GRM.Inventory.CountItem(patient, "medcard") == 1,
   "медкарта НЕ расходуется при просмотре")
-- предмет-«бланк» без данных: до модуля доходит вызов с nil-data (модуль сам объяснит про пустую карту)
GRM.Inventory.AddItem(patient, "medcard", 1)
local bslot
for i = 1, 24 do local s = pinv.slots[i] if s and s.id == "medcard" and not s.data then bslot = i break end end
if bslot then H.seq = { bslot } H.recv["grm_inv_use"](0, patient) end
ok(bslot ~= nil and viewCalls.n == 2 and viewCalls[2] == false, "отдельный бланк тоже доходит до модуля медицины (data=nil)")

print("== 8.5. Код 109 (находка 126): реестр UseHandlers — «нормальный модуль» ==")
ok(type(GRM.Inventory.RegisterUseHandler) == "function" and istable(GRM.Inventory.UseHandlers),
   "реестр обработчиков использования на месте (RegisterUseHandler/UseHandlers)")
ok(type(GRM.Inventory.UseHandlers["radio_toggle"]) == "function"
   and type(GRM.Inventory.UseHandlers["mobile_open"]) == "function"
   and type(GRM.Inventory.UseHandlers["medcard_view"]) == "function"
   and type(GRM.Inventory.UseHandlers["cash_to_wallet"]) == "function",
   "встроенные обработчики зарегистрированы через реестр (radio/mobile/medcard/cash)")
ok(type(GRM.Inventory.UseItem) == "function", "useItem экспортирована (GRM.Inventory.UseItem)")

print("== 9. Код 106: видимый отказ при предмете без дефа ==")
-- предмет без дефа: раньше — тихий выход («мёртвая кнопка»), теперь — видимый отказ
local notif = {}
GRM.Notify = function(p, txt) notif[#notif + 1] = tostring(txt) end
local invX = GRM.Inventory.GetPlayerInv(ply)
local gslot
for i = 1, 24 do if not (invX.slots[i] and invX.slots[i].id) then gslot = i break end end
ok(gslot ~= nil, "найден свободный слот для призрачного предмета")
invX.slots[gslot or 24] = { id = "ghost_item_x", count = 1 }
H.seq = { gslot or 24 } H.recv["grm_inv_use"](0, ply)
ok(#notif >= 1 and (notif[#notif]:find("не зарегистрирован", 1, true) ~= nil),
   "нет дефа — игрок видит отказ «не зарегистрирован» (диагностика в один скрин)")
invX.slots[gslot or 24] = nil

print("== 10. Код 109 (находка 126): ПАТЧ ЕДЫ ПОСЛЕ инвентаря — ресивер больше НЕ заменяется ==")
-- ЖИВАЯ РЕГРЕССИЯ из заказа владельца: zz_grm_food_inventory_patch раньше
-- ЗАМЕНЯЛ net.Receive("grm_inv_use") своей неполной копией (без radio_toggle)
-- — «жму Использовать — ничего», /freq /r навсегда «нет модулятора».
GRM.Food = GRM.Food or {}
GRM.Food.Config = GRM.Food.Config or { FoodItems = {
    grm_food_apple = { name = "Яблоко", hungerRestore = 20, healthRestore = 0, price = 10, model = "models/props/cs_office/coffee_mug.mdl" },
} }
GRM.Food._hunger = 100
GRM.Food.GetHunger = function() return GRM.Food._hunger end
GRM.Food.RestoreHunger = function(_, n) GRM.Food._hunger = math.min(100, GRM.Food._hunger + (n or 0)) end
scripted_ents = scripted_ents or { GetStored = function() return nil end }
dofile("lua/autorun/zz_grm_food_inventory_patch.lua")
hook.Run("InitPostEntity") -- в живой игре ставит интеграции через timer.Simple (мок — сразу)
ok(H.recv["grm_inv_use"] ~= nil and H.recv["GRM_Vending_Buy"] ~= nil,
   "после патча оба ресивера живы: инвентарный (его!) и автоматный")
ok(type(GRM.Inventory.UseHandlers["grm_food_eat"]) == "function",
   "патч зарегистрировал обработчик еды через API (ресивер не заменял)")
-- предмет еды получил деф с useFunc grm_food_eat
local appleDef = GRM.Inventory.GetItemDef("grm_food_apple")
ok(istable(appleDef) and appleDef.useFunc == "grm_food_eat",
   "патч зарегистрировал деф еды с useFunc grm_food_eat через ItemDefs")

-- ГЛАВНОЕ: модулятор рации по-прежнему переключается ИМЕННО через grm_inv_use
inv = GRM.Inventory.GetPlayerInv(ply)
slotIdx = nil
for i = 1, 24 do local s = inv.slots[i] if s and s.id == "radio_modulator" then slotIdx = i break end end
ok(slotIdx ~= nil, "модулятор всё ещё в инвентаре после подгрузки патча еды")
H.seq = { slotIdx } H.recv["grm_inv_use"](0, ply)
ok(inv.slots[slotIdx] ~= nil and inv.slots[slotIdx].data.on == false,
   "Код 109: ПОСЛЕ ПАТЧА ЕДЫ «Использовать» по модулятору ЖИВО (toggle → ВЫКЛ)")
H.seq = { slotIdx } H.recv["grm_inv_use"](0, ply)
ok(inv.slots[slotIdx].data.on == true,
   "и снова → ВКЛ: замены ресивера больше нет, radio_toggle не тонет")

-- и медкарта не умерла (тот же симптом был у всех «лишних» useFunc)
local pinv2 = GRM.Inventory.GetPlayerInv(patient)
local mslot2
for i = 1, 24 do local s = pinv2.slots[i] if s and s.id == "medcard" then mslot2 = i break end end
if mslot2 then H.seq = { mslot2 } H.recv["grm_inv_use"](0, patient) end
ok(mslot2 ~= nil and viewCalls.n >= 3, "ПОСЛЕ ПАТЧА ЕДЫ медкарта тоже работает (medcard_view жив)")

-- еда: собственный юзкейс патча — через тот же ресивер и реестр
GRM.Inventory.AddItem(ply, "grm_food_apple", 1)
local aslot
for i = 1, 24 do local s = inv.slots[i] if s and s.id == "grm_food_apple" then aslot = i break end end
GRM.Food._hunger = 40
H.seq = { aslot } H.recv["grm_inv_use"](0, ply)
ok(GRM.Food._hunger == 60 and inv.slots[aslot] == nil,
   "еда съедена через реестр: сытость +20, предмет израсходован")
GRM.Inventory.AddItem(ply, "grm_food_apple", 1)
aslot = nil
for i = 1, 24 do local s = inv.slots[i] if s and s.id == "grm_food_apple" then aslot = i break end end
GRM.Food._hunger = 100
H.seq = { aslot } H.recv["grm_inv_use"](0, ply)
ok(GRM.Food._hunger == 100 and inv.slots[aslot] ~= nil,
   "полная сытость → еда не тратится, отказ виден (canUseFoodNow)")

-- сторонний модуль регистрирует useFunc сам — не трогая ресивер
local trixHits = 0
GRM.Inventory.RegisterUseHandler("trix", function() trixHits = trixHits + 1 end)
GRM.Inventory.RegisterItem("trix_item", { type = "item", name = "Триксель", maxStack = 1, useFunc = "trix" })
GRM.Inventory.AddItem(ply, "trix_item", 1)
local tslot
for i = 1, 24 do local s = inv.slots[i] if s and s.id == "trix_item" then tslot = i break end end
H.seq = { tslot } H.recv["grm_inv_use"](0, ply)
ok(trixHits == 1, "свой useFunc («trix») доезжает до обработчика через реестр — расширение без патчей")

-- без обработчика — ВИДИМЫЙ отказ (а не тишина «мёртвой кнопки»)
notif = {}
GRM.Notify = function(p, txt) notif[#notif + 1] = tostring(txt) end
GRM.Inventory.RegisterItem("lost_item", { type = "item", name = "Потеряшка", maxStack = 1, useFunc = "no_such_handler" })
GRM.Inventory.AddItem(ply, "lost_item", 1)
local lslot
for i = 1, 24 do local s = inv.slots[i] if s and s.id == "lost_item" then lslot = i break end end
H.seq = { lslot } H.recv["grm_inv_use"](0, ply)
ok(#notif >= 1 and (notif[#notif]:find("не поднялся", 1, true) ~= nil),
   "useFunc без обработчика → видимый отказ «модуль не поднялся» игроку")
GRM.Notify = function() end -- вернуть тихий стаб

print("")
print(("РЕЗУЛЬТАТ: %d/%d проверок, провалов: %d"):format(checks - failed, checks, failed))
if failed > 0 then os.exit(1) end
print("SIM INVPHONE: OK")
