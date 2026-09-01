--[[ Живой прогон восстановления физических бланков: почему «восстановлено 0»
     и что теперь видит игрок. Проверяем причины отказа, диагностику и
     успешную выдачу.
     Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_doc_restore.lua ]]
SERVER, CLIENT = true, false
function AddCSLuaFile() end

local NOW = 1000000
function CurTime() return 100 end
function IsValid(v) return type(v) == "table" and v._valid ~= false end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isfunction(v) return type(v) == "function" end
function isnumber(v) return type(v) == "number" end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function string.Trim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
function table.Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
function table.Copy(t) if type(t) ~= "table" then return t end local o = {} for k, v in pairs(t) do o[k] = table.Copy(v) end return o end
function ErrorNoHalt() end
HUD_PRINTCONSOLE = 2

local realTime = os.time
os.time = function(...) return realTime(...) end

local hooks = {}
hook = {
    Add = function(n, id, fn) hooks[n] = hooks[n] or {} hooks[n][id] = fn end,
    Remove = function() end,
    Run = function(n, ...) for _, fn in pairs(hooks[n] or {}) do fn(...) end end,
}
timer = { Create = function() end, Simple = function() end, Remove = function() end }
concommand = { Add = function() end }
net = { Receive = function() end, Start = function() end, WriteString = function() end,
        WriteTable = function() end, Send = function() end, Broadcast = function() end }
util = { AddNetworkString = function() end, TableToJSON = function() return "{}" end,
         JSONToTable = function() return {} end }
file = { Exists = function() return false end, Read = function() return "" end, Write = function() end,
         IsDir = function() return true end, CreateDir = function() end }
CreateConVar = function() return { GetBool = function() return false end, GetInt = function() return 0 end } end
GetConVar = CreateConVar

local ALL = {}
player = { GetAll = function() return ALL end }

GRM = { Identity = {}, Perf = {}, Audit = { Write = function() end } }
GRM.Identity.CharacterKey = function(p) return IsValid(p) and (p:SteamID64() .. ":char1") or "" end
GRM.Perf.Players = function() return ALL end
local NOTIFY = {}
GRM.Notify = function(p, text) NOTIFY[#NOTIFY + 1] = tostring(text) end

-- ── инвентарь ───────────────────────────────────────────────────────
local INV = { slots = {} }
local invHealthy, invSource, saveOK = true, "grm_inventories.json", true
GRM.Inventory = {
    Config = { MaxSlots = 30 },
    GetPlayerInv = function() return INV end,
    SyncSlot = function() end,
    PersistenceHealthy = function() return invHealthy, invSource end,
    SaveNow = function() return saveOK end,
    RegisterItem = function() end,
    GetItemDef = function(id) return { name = id } end,
    AddItem = function(_, id, count, data)
        for i = 1, 30 do
            if not INV.slots[i] then
                INV.slots[i] = { id = id, count = count or 1, data = data }
                return 0
            end
        end
        return count or 1
    end,
}

-- ── реестр документов ───────────────────────────────────────────────
GRM.Documents = {
    RegistryHealthy = true,
    Registry = {
        passports = {}, badges = {}, military = {}, licenses = {}, milLicenses = {},
        weaponLicenses = {}, businessLicenses = {},
    },
    SaveRegistry = function() return true end,
}

local function mkPlayer()
    local p = { _valid = true, nw = {}, chat = {} }
    function p:IsPlayer() return true end
    function p:Nick() return "Курт" end
    function p:SteamID64() return "76561190000000002" end
    function p:SteamID() return "STEAM_0:1:1" end
    function p:IsSuperAdmin() return true end
    function p:GetNWString(k, d) local v = self.nw[k] if v == nil then return d end return v end
    function p:GetNWBool(k, d) local v = self.nw[k] if v == nil then return d end return v end
    function p:SetNWString(k, v) self.nw[k] = v end
    function p:ChatPrint(m) self.chat[#self.chat + 1] = m end
    ALL[#ALL + 1] = p
    return p
end

assert(loadfile("lua/autorun/sh_grm_physical_documents.lua"))()
local DOC = GRM.Documents

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

local ply = mkPlayer()
local KEY = "76561190000000002:char1"
DOC.Registry.passports[KEY] = { fullName = "Курт Вебер", number = "011234", status = "Действителен" }
DOC.Registry.military[KEY] = { fullName = "Курт Вебер", number = "ВС-4412", status = "Действителен" }

local function chat(text)
    ply.chat = {}
    NOTIFY = {}
    local fn = hooks["PlayerSay"] and hooks["PlayerSay"]["GRM_PhysicalDocs_Chat"]
    return fn and fn(ply, text)
end
local function notifyText()
    return table.concat(NOTIFY, " | ")
end
local function chatText()
    return table.concat(ply.chat, " | ")
end

print("\n=== 1. НЕДОСТАЮЩИЕ БЛАНКИ ВИДНЫ ===")
local missing = DOC.MissingPhysicalTypes(ply)
ok(#missing == 2, "в реестре два документа без бланка", #missing)

print("\n=== 2. ЗАБЛОКИРОВАННОЕ ХРАНИЛИЩЕ ===")
invHealthy = false
ok(isstring(DOC.StorageBlockedReason()), "модуль видит блокировку записи")
chat("/docrestore all")
ok(notifyText():find("Восстановлено бланков: 0 из 2", 1, true) ~= nil,
    "счётчик честный: 0 из 2", notifyText())
ok(chatText():find("повреждённого файла", 1, true) ~= nil,
    "ПРИЧИНА теперь пишется в чат, а не проглатывается", chatText())
ok(chatText():find("/docrestore диаг", 1, true) ~= nil, "подсказана диагностика")
invHealthy = true

print("\n=== 3. НЕЗДОРОВЫЙ РЕЕСТР ДОКУМЕНТОВ ===")
DOC.RegistryHealthy = false
ok(isstring(DOC.StorageBlockedReason()), "повреждённый реестр тоже блокирует")
chat("/docrestore all")
ok(chatText():find("Реестр документов", 1, true) ~= nil, "и об этом сообщают", chatText())
DOC.RegistryHealthy = true

print("\n=== 4. УСПЕШНОЕ ВОССТАНОВЛЕНИЕ ===")
chat("/docrestore all")
ok(notifyText():find("Восстановлено бланков: 2 из 2", 1, true) ~= nil,
    "оба бланка выданы", notifyText())
ok(#DOC.MissingPhysicalTypes(ply) == 0, "недостающих больше нет")
ok(chatText() == "", "лишних сообщений об ошибках нет", chatText())

print("\n=== 5. ПОВТОР И КУЛДАУН ===")
chat("/docrestore passport")
ok(notifyText():find("уже находится", 1, true) ~= nil or notifyText():find("Физический документ восстановлен", 1, true) == nil,
    "повторная выдача не дублирует бланк", notifyText())

print("\n=== 6. ДИАГНОСТИКА ===")
chat("/docrestore диаг")
local diag = chatText()
ok(diag:find("Диагностика восстановления", 1, true) ~= nil, "диагностика печатается")
ok(diag:find("Хранилище", 1, true) ~= nil, "видно состояние хранилища")
ok(diag:find("Инвентарь: занято слотов", 1, true) ~= nil, "видно занятость инвентаря")
ok(diag:find("passport", 1, true) ~= nil and diag:find("military", 1, true) ~= nil,
    "по каждому типу — своя строка")

print("\n=== 7. ОТКАЗ ИНВЕНТАРЯ ===")
DOC.Registry.licenses[KEY] = { fullName = "Курт Вебер", number = "ДИ-7712", status = "Действительно" }
saveOK = false
chat("/docrestore license")
ok(notifyText():find("сохранить", 1, true) ~= nil,
    "если сохранение не прошло — игрок это видит", notifyText())
saveOK = true
chat("/docrestore license")
ok(notifyText():find("восстановлен", 1, true) ~= nil, "после починки выдача проходит", notifyText())

print(("\nDOC RESTORE: %d/%d, провалов: %d"):format(total - fails, total, fails))
if fails > 0 then os.exit(1) end
