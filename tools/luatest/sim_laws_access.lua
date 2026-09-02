--[[ Живой прогон доступов к кодексу: кто может публиковать, изменять и
     удалять статьи, что уходит клиенту и что сервер отвечает на попытку
     без права.
     Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_laws_access.lua ]]
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
function table.Copy(t) if type(t) ~= "table" then return t end local o = {} for k, v in pairs(t) do o[k] = table.Copy(v) end return o end
function ErrorNoHalt() end
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a } end

local hooks = {}
hook = {
    Add = function(n, id, fn) hooks[n] = hooks[n] or {} hooks[n][id] = fn end,
    Remove = function() end,
    Run = function(n, ...) for _, fn in pairs(hooks[n] or {}) do local r = fn(...) if r ~= nil then return r end end end,
}
timer = { Create = function() end, Simple = function(_, fn) fn() end, Remove = function() end }
concommand = { Add = function() end }
local FS = {}
file = { Exists = function(p) return FS[p] ~= nil end, Read = function(p) return FS[p] end,
         Write = function(p, s) FS[p] = s end, IsDir = function() return true end, CreateDir = function() end }
util = { AddNetworkString = function() end, TableToJSON = function() return "{}" end,
         JSONToTable = function() return {} end }

local SENT, packet = {}, nil
local READ = {}
net = {
    Receive = function(name, fn) net["_" .. name] = fn end,
    Start = function(name) packet = { name = name, values = {} } end,
    WriteBool = function(v) if packet then packet.values[#packet.values + 1] = v end end,
    WriteString = function(v) if packet then packet.values[#packet.values + 1] = v end end,
    WriteUInt = function(v) if packet then packet.values[#packet.values + 1] = v end end,
    WriteTable = function(v) if packet then packet.values[#packet.values + 1] = v end end,
    Send = function(to) if packet then packet.to = to SENT[#SENT + 1] = packet end end,
    Broadcast = function() if packet then packet.to = "all" SENT[#SENT + 1] = packet end end,
    ReadString = function() return table.remove(READ, 1) end,
    ReadUInt = function() return table.remove(READ, 1) end,
    ReadTable = function() return table.remove(READ, 1) end,
}
CreateConVar = function() return { GetBool = function() return false end, GetInt = function() return 0 end } end
GetConVar = CreateConVar

local ALL = {}
player = { GetAll = function() return ALL end }

GRM = { Identity = {}, Perf = {}, Audit = { Write = function() end } }
GRM.Perf.Players = function() return ALL end
GRM.Identity.CharacterKey = function(p) return IsValid(p) and (p:SteamID64() .. ":char1") or "" end
GRM.Identity.FactionMember = function(f, p)
    if not (istable(f) and istable(f.Members)) then return nil end
    return f.Members[GRM.Identity.CharacterKey(p)]
end
local NOTIFY = {}
GRM.Notify = function(p, text) NOTIFY[#NOTIFY + 1] = tostring(text) end

local function mkPlayer(nick, sid, super)
    local p = { _valid = true, nick = nick, sid = sid, chat = {}, nw = {}, _super = super }
    function p:IsPlayer() return true end
    function p:Nick() return self.nick end
    function p:SteamID64() return self.sid end
    function p:SteamID() return "STEAM_" .. self.sid end
    function p:IsSuperAdmin() return self._super == true end
    function p:IsAdmin() return self._super == true or self._admin == true end
    function p:GetUserGroup() return self._group or (self._super and "superadmin" or (self._admin and "admin" or "user")) end
    function p:SetUserGroup(g) self._group = g end
    function p:GetNWString(k, d) local v = self.nw[k] if v == nil then return d end return v end
    function p:ChatPrint(m) self.chat[#self.chat + 1] = m end
    ALL[#ALL + 1] = p
    return p
end

-- Права фракций и админ-платформа
Factions = {
    ["Магистрат"] = { Roles = { "Судья", "Секретарь" }, Members = {} },
}
GRM.FactionPerms = {
    Data = { ["Магистрат"] = { roles = { ["Судья"] = { law_publish = true } } } },
}
function GRM.FactionPerms.RoleHasPermission(fac, role, perm)
    local f = GRM.FactionPerms.Data[fac] or {}
    local roles = f.roles or {}
    return roles[role] and roles[role][perm] == true
end
function GRM.FactionPerms.PlayerHasPermission(ply, perm)
    if not IsValid(ply) then return false end
    if ply:IsSuperAdmin() then return true end
    for fname, f in pairs(Factions) do
        local m = GRM.Identity.FactionMember(f, ply)
        if m and GRM.FactionPerms.RoleHasPermission(fname, m.Role or "", perm) then return true end
    end
    return false
end
GRM.FactionEconomy = {
    HasAccess = function(ply, perm) return GRM.FactionPerms.PlayerHasPermission(ply, perm) end,
}
GRM.FactionEconomy.CanPublishLaws = function(ply) return GRM.FactionEconomy.HasAccess(ply, "law_publish") end


assert(loadfile("lua/autorun/sh_grm_admin_core.lua"))()
assert(loadfile("lua/autorun/sh_grm_laws.lua"))()
local LAWS = GRM.Laws

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

local super = mkPlayer("Суперадмин", "76561190000000001", true)
local moder = mkPlayer("Модератор", "76561190000000002")
moder._admin = true
local judge = mkPlayer("Судья", "76561190000000003")
local clerk = mkPlayer("Секретарь", "76561190000000004")
local civ = mkPlayer("Гражданин", "76561190000000005")

Factions["Магистрат"].Members = {
    [GRM.Identity.CharacterKey(judge)] = { Role = "Судья" },
    [GRM.Identity.CharacterKey(clerk)] = { Role = "Секретарь" },
}

print("\n=== 1. ПРАВО ПО УМОЛЧАНИЮ ===")
local AD = GRM.Admin
ok(istable(AD.Perms["laws.edit"]) and AD.Perms["laws.edit"].minAccess == "superadmin",
    "право правки кодекса по умолчанию НЕ выдаётся всем админам",
    AD.Perms["laws.edit"] and AD.Perms["laws.edit"].minAccess)
ok(istable(AD.Perms["laws.remove"]), "удаление статей — отдельное право")

print("\n=== 1б. НЕЗАВИСИМОСТЬ ЯДРА (мосты ликвидированы, заказ 03.09) ===")
local okCall, res = pcall(AD.Can, moder, "laws.edit")
ok(okCall == true, "проверка права не уходит в бесконечную рекурсию",
    okCall and "" or tostring(res))
ok(res == false, "и отвечает по существу", tostring(res))
ok(isfunction(AD.CanLocal), "локальная проверка матрицы — единственный механизм")
local coreSrc = (function() local f = assert(io.open("lua/autorun/sh_grm_admin_core.lua", "rb"))
    local t = f:read("*a") f:close() return t end)()
ok(coreSrc:find("CAMI", 1, true) == nil, "обращений к внешнему мосту в ядре нет вовсе")

print("\n=== 2. КТО МОЖЕТ ПРАВИТЬ ===")
ok(LAWS.CanEdit(super) == true, "суперадмин может")
ok(LAWS.CanEdit(judge) == true, "должность с law_publish может")
ok(LAWS.CanEdit(clerk) == false, "должность без доступа — нет")
ok(LAWS.CanEdit(civ) == false, "гражданин — нет")
ok(LAWS.CanEdit(moder) == false, "модератор без явной выдачи — НЕТ (это и был баг)")

print("\n=== 3. КТО МОЖЕТ УДАЛЯТЬ ===")
ok(LAWS.CanRemove(super) == true, "суперадмин удаляет")
ok(LAWS.CanRemove(judge) == false, "публикация НЕ даёт права удалять")
GRM.FactionPerms.Data["Магистрат"].roles["Судья"].law_remove = true
ok(LAWS.CanRemove(judge) == true, "с галочкой law_remove — удаляет")
GRM.FactionPerms.Data["Магистрат"].roles["Судья"].law_remove = nil

print("\n=== 4. ЧТО УХОДИТ КЛИЕНТУ ===")
local function payloadFor(ply)
    SENT = {}
    LAWS.SendList(ply)
    for _, pk in ipairs(SENT) do
        if pk.name == "GRM_Laws_List" then return pk.values[1] end
    end
end
local p1 = payloadFor(judge)
ok(istable(p1) and p1.canEdit == true, "уполномоченному приходит canEdit = true")
local p2 = payloadFor(civ)
ok(istable(p2) and p2.canEdit == false and p2.canRemove == false,
    "обычному игроку — false, поэтому кнопок в окне нет")

print("\n=== 5. СЕРВЕР НЕ ВЕРИТ КЛИЕНТУ ===")
local function action(ply, op, id, data)
    NOTIFY = {}
    SENT = {}
    READ = { op, id or 0, data or {} }
    net["_GRM_Laws_Action"](0, ply)
    for _, pk in ipairs(SENT) do
        if pk.name == "GRM_Laws_Result" then return pk.values[1], pk.values[2] end
    end
end

local okAdd, msg = action(civ, "add", 0, { title = "Свой закон", text = "Текст" })
ok(okAdd == false and tostring(msg):find("Нет права", 1, true) ~= nil,
    "подделанный пакет от гражданина отбит", tostring(msg))
ok(#LAWS.GetAll() == 0, "статья не появилась", #LAWS.GetAll())

local okJudge = action(judge, "add", 0, { title = "Статья 1", text = "Не сорить", penalty = "Штраф" })
ok(okJudge == true, "уполномоченный публикует")
ok(#LAWS.GetAll() == 1, "статья добавлена", #LAWS.GetAll())

local lawID = LAWS.GetAll()[1].id
local okDel = action(judge, "remove", lawID, {})
ok(okDel == false, "без права удаления статью не снести")
ok(#LAWS.GetAll() == 1, "статья на месте")

local okDelSuper = action(super, "remove", lawID, {})
ok(okDelSuper == true and #LAWS.GetAll() == 0, "суперадмин удаляет")

local okModer = action(moder, "add", 0, { title = "Модератор", text = "Текст" })
ok(okModer == false, "модератор без выдачи публиковать не может")

print("\n=== 5б. ОБНОВЛЕНИЕ У ИГРОКОВ ===")
SENT = {}
LAWS.Viewers = { [judge] = true }
LAWS.BroadcastUpdate()
local changed, listed = false, false
for _, pk in ipairs(SENT) do
    if pk.name == "GRM_Laws_Changed" and pk.to == "all" then changed = true end
    if pk.name == "GRM_Laws_List" and pk.to == judge then listed = true end
end
ok(listed, "у кого окно открыто — получает свежий список адресно")
ok(changed, "а всем уходит сигнал «кодекс изменился» (окно попросит обновление само)")

print("\n=== 6. ИНТЕРФЕЙС (состав) ===")
local function read(path) local f = assert(io.open(path, "rb")) local t = f:read("*a") f:close() return t end
local function has(src, needle) return src:find(needle, 1, true) ~= nil end
local laws = read("lua/autorun/sh_grm_laws.lua")
local fixes = read("lua/autorun/sh_faction_fixes.lua")
local perms = read("lua/autorun/sh_grm_faction_perms.lua")
ok(has(laws, "Режим просмотра: показываем статью текстом"),
    "у зрителя вместо редактора — текст статьи")
ok(has(laws, "Правка кодекса доступна только уполномоченным должностям."),
    "и подпись, почему нельзя править")
ok(has(laws, "Режим просмотра · правка недоступна"), "в шапке окна честный статус")
ok(has(fixes, "local canManageLaws = false"), "раздел настроек законов проверяет право")
ok(has(fixes, "Доступами к законам управляет лидер организации или суперадмин"),
    "без права показывается только состояние")
ok(has(perms, "Доступами организации управляет её лидер или суперадмин."),
    "сервер отвечает на попытку без права, а не молчит")
ok(has(laws, 'net.Receive("GRM_Laws_Changed"'), "клиент реагирует на сигнал об изменении")
ok(has(read("lua/autorun/sh_grm_admin_core.lua"), "мосты ликвидированы"),
    "в ядре зафиксирован урок рекурсии: обращений наружу нет")

print(("\nLAWS ACCESS: %d/%d, провалов: %d"):format(total - fails, total, fails))
if fails > 0 then os.exit(1) end
