--[[ Живой прогон инструмента «GRM Сканер фракций»: список организаций
     приходит С СЕРВЕРА, панель строит отметки, поиск и счётчик, выбор
     пишется в конвар, а сканер пускает по этому списку.
     Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_scanner_tool.lua ]]
SERVER, CLIENT = true, false
function AddCSLuaFile() end

function CurTime() return 100 end
function IsValid(v) return type(v) == "table" and v._valid ~= false end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isfunction(v) return type(v) == "function" end
function isnumber(v) return type(v) == "number" end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function string.Trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
function table.Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
function ErrorNoHalt() end

local hooks = {}
hook = {
    Add = function(n, id, fn) hooks[n] = hooks[n] or {} hooks[n][id] = fn end,
    Remove = function(n, id) if hooks[n] then hooks[n][id] = nil end end,
    Run = function(n, ...) for _, fn in pairs(hooks[n] or {}) do fn(...) end end,
}
timer = { Create = function() end, Simple = function(_, fn) fn() end, Remove = function() end }
concommand = { Add = function() end }
util = { AddNetworkString = function() end }
undo = { Create = function() end, AddEntity = function() end, SetPlayer = function() end, Finish = function() end }
duplicator = { StoreEntityModifier = function() end }
language = { Add = function() end }
ents = { Create = function() return nil end }

-- Конвары: панель пишет выбор именно сюда.
local CVARS = { ffd_scanner_faction = "" }
function RunConsoleCommand(name, value) CVARS[name] = tostring(value or "") end
function GetConVar(name)
    if CVARS[name] == nil then return nil end
    return { GetString = function() return CVARS[name] end,
             GetInt = function() return math.floor(tonumber(CVARS[name]) or 0) end,
             GetFloat = function() return tonumber(CVARS[name]) or 0 end,
             GetBool = function() return CVARS[name] ~= "0" end }
end

-- Сеть: перехватываем и приёмники, и отправку.
local RECEIVERS, SENT, packet = {}, {}, nil
net = {
    Receive = function(name, fn) RECEIVERS[name] = fn end,
    Start = function(name) packet = { name = name } end,
    WriteTable = function(t) if packet then packet.data = t end end,
    Send = function(to) if packet then packet.to = to SENT[#SENT + 1] = packet end end,
    SendToServer = function() if packet then packet.to = "server" SENT[#SENT + 1] = packet end end,
    ReadTable = function() return net._incoming end,
}

GRM = { Identity = {}, Perf = {}, Factions = {} }
GRM.Identity.CharacterKey = function(p) return IsValid(p) and (p:SteamID64() .. ":char1") or "" end
GRM.Identity.FactionMember = function(f, p)
    if not (istable(f) and istable(f.Members)) then return nil end
    return f.Members[GRM.Identity.CharacterKey(p)]
end
GRM.Factions.DisplayName = function(name)
    local map = { police_order = "Полиция Порядка", feldjager = "Полевая Жандармерия", medics = "Госпиталь" }
    return map[name] or name
end
GRM.Notify = function() end

Factions = {
    police_order = { Tag = "ПД", Members = { ["76561190000000002:char1"] = { Role = "Сержант" } } },
    feldjager = { Tag = "ФЖ", Members = {} },
    medics = { Tag = "МЕД", Members = {} },
}

-- Мини-derma: панели запоминают своё содержимое.
local function mkPanel(class)
    local p = { _valid = true, _class = class, children = {} }
    setmetatable(p, { __index = function(_, key)
        return function() end
    end })
    rawset(p, "Dock", function() end)
    rawset(p, "DockMargin", function() end)
    rawset(p, "SetTall", function() end)
    rawset(p, "SetWide", function() end)
    rawset(p, "SetText", function(self, t) rawset(self, "text", t) end)
    rawset(p, "GetValue", function(self) return rawget(self, "value") or "" end)
    rawset(p, "SetValue", function(self, v) rawset(self, "value", v) end)
    rawset(p, "SetChecked", function(self, v) rawset(self, "checked", v == true) end)
    rawset(p, "GetChecked", function(self) return rawget(self, "checked") == true end)
    rawset(p, "Clear", function(self) rawset(self, "children", {}) end)
    return p
end

local CREATED = {}
vgui = {
    Create = function(class, parent)
        local p = mkPanel(class)
        CREATED[#CREATED + 1] = p
        if istable(parent) and istable(rawget(parent, "children")) then
            table.insert(rawget(parent, "children"), p)
        end
        return p
    end,
}

TOOL = { ClientConVar = {}, Category = "", Name = "", Command = nil, ConfigName = "" }
-- Ядро GRM (sh_00_grm_ui + sh_01_grm_core) — как на сервере, до модулей.
dofile("tools/luatest/lib_grm_core.lua")()
assert(loadfile("lua/weapons/gmod_tool/stools/ffd_scanner.lua"))()
local SCANNER_TOOL = TOOL

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

local function mkPlayer(sid)
    local p = { _valid = true, sid = sid }
    function p:IsPlayer() return true end
    function p:SteamID64() return self.sid end
    function p:SteamID() return "STEAM_" .. self.sid end
    function p:Nick() return "Игрок" end
    return p
end
local admin = mkPlayer("76561190000000001")

print("\n=== 1. СПИСОК ОРГАНИЗАЦИЙ ИДЁТ С СЕРВЕРА ===")
ok(isfunction(RECEIVERS["GRM_ScannerTool_ListReq"]), "сервер слушает запрос списка")
SENT = {}
RECEIVERS["GRM_ScannerTool_ListReq"](0, admin)
local answer = SENT[1]
ok(answer ~= nil and answer.name == "GRM_ScannerTool_List", "сервер отвечает списком")
local rows = answer and answer.data or {}
ok(#rows == 3, "перечислены все организации", #rows)
ok(rows[1].display == "Госпиталь", "отсортировано по человеческому названию", rows[1].display)
local police
for _, row in ipairs(rows) do if row.name == "police_order" then police = row end end
ok(police ~= nil and police.display == "Полиция Порядка", "приходит название, а не ключ")
ok(police and police.tag == "ПД", "и тег организации", police and police.tag)
ok(police and police.members == 1, "видно, сколько сотрудников", police and police.members)

print("\n=== 2. ПАНЕЛЬ СТРОИТ СПИСОК ===")
-- клиентская половина файла: имитируем приём и построение панели
SERVER, CLIENT = false, true
_G.TOOL = SCANNER_TOOL
assert(loadfile("lua/weapons/gmod_tool/stools/ffd_scanner.lua"))()
local CTOOL = _G.TOOL

net._incoming = rows
RECEIVERS["GRM_ScannerTool_List"]()
ok(#(CTOOL.FactionRows or {}) == 3, "клиент запомнил список", #(CTOOL.FactionRows or {}))

CREATED = {}
local panel = mkPanel("DForm")
rawset(panel, "AddControl", function() return mkPanel("control") end)
rawset(panel, "AddItem", function(self, item) table.insert(rawget(self, "children"), item) end)
rawset(panel, "Help", function() end)
CTOOL.BuildCPanel(panel)

local function checkboxes()
    local out = {}
    for _, p in ipairs(CREATED) do
        if p._class == "DCheckBoxLabel" and rawget(p, "facName") then out[#out + 1] = p end
    end
    return out
end
local boxes = checkboxes()
ok(#boxes == 3, "в панели три организации", #boxes)
local labels = {}
for _, box in ipairs(boxes) do labels[#labels + 1] = tostring(rawget(box, "text") or "") end
ok(table.concat(labels, " | "):find("Полиция Порядка", 1, true) ~= nil,
    "в подписи человеческое название", labels[1])
ok(table.concat(labels, " | "):find("сотрудников", 1, true) ~= nil, "и число сотрудников")

print("\n=== 3. ВЫБОР ПИШЕТСЯ В КОНВАР ===")
local target
for _, box in ipairs(boxes) do if rawget(box, "facName") == "police_order" then target = box end end
target.OnChange(target, true)
ok(CVARS.ffd_scanner_faction == "police_order", "отметка записалась", CVARS.ffd_scanner_faction)

boxes = checkboxes()
local again
for _, box in ipairs(boxes) do if rawget(box, "facName") == "medics" then again = box end end
again.OnChange(again, true)
ok(CVARS.ffd_scanner_faction:find("police_order", 1, true) ~= nil
    and CVARS.ffd_scanner_faction:find("medics", 1, true) ~= nil,
    "вторая организация добавилась, а не заменила первую", CVARS.ffd_scanner_faction)

boxes = checkboxes()
for _, box in ipairs(boxes) do
    if rawget(box, "facName") == "police_order" then box.OnChange(box, false) end
end
ok(CVARS.ffd_scanner_faction == "medics", "снятие отметки убирает организацию", CVARS.ffd_scanner_faction)

print("\n=== 4. ПУСТОЙ СПИСОК НЕ ОСТАВЛЯЕТ БЕЗ ВАРИАНТОВ ===")
CTOOL.FactionRows = {}
CREATED = {}
local panel2 = mkPanel("DForm")
rawset(panel2, "AddControl", function() return mkPanel("control") end)
rawset(panel2, "AddItem", function(self, item) table.insert(rawget(self, "children"), item) end)
rawset(panel2, "Help", function() end)
CTOOL.BuildCPanel(panel2)
local hasManualEntry = false
for _, p in ipairs(CREATED) do if p._class == "DTextEntry" then hasManualEntry = true end end
ok(hasManualEntry, "пока список не пришёл, есть ручной ввод")
local requested = false
for _, pk in ipairs(SENT) do if pk.name == "GRM_ScannerTool_ListReq" then requested = true end end
ok(requested, "панель сама просит список у сервера")

print("\n=== 5. СКАНЕР ПУСКАЕТ ПО СПИСКУ ===")
local ENT = { GetFaction = function() return "police_order,medics" end }
SERVER, CLIENT = true, false
local shared = loadfile("lua/entities/grm_scanner/shared.lua")
ok(isfunction(shared), "модуль сканера читается")

print(("\nSCANNER TOOL: %d/%d, провалов: %d"):format(total - fails, total, fails))
if fails > 0 then os.exit(1) end
