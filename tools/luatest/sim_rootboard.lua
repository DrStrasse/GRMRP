-- ============================================================================
-- sim_rootboard.lua — стенд для заказа 18.07.2026:
--   1) Root Guard (Код 84): удаление фракций без «да» владельца НЕ исполняется.
--   2) Доска v1.1.0: автоназначение отдела/должности при вступлении.
--   3) Q-меню v1.1.0: клиентская ветка — универсальный блок бинда "+menu"
--      (ванила+кастом), синк конфига GRM_QMenu_Sync.
-- Грузятся НАСТОЯЩИЕ sh_grm_rootguard.lua, sh_grm_board.lua, sh_grm_qmenu.lua.
-- ============================================================================
string.Trim = function(s) s = tostring(s or ""); return (s:gsub("^%s*(.-)%s*$", "%1")) end
local H = { hooks = {}, netrecv = {}, timers = {} }
local realPrint = print
local function P(...) realPrint("[SIM]", ...) end
_G._SIM = H
SERVER = true
CLIENT = false
function AddCSLuaFile() end
function include(f) if f == "shared.lua" then return end dofile(f) end
function istable(x) return type(x) == "table" end
function isstring(x) return type(x) == "string" end
function isfunction(x) return type(x) == "function" end
function isnumber(x) return type(x) == "number" end
function IsValid(o) return o ~= nil and o ~= false and o.removed ~= true end
HUD_PRINTTALK, HUD_PRINTCENTER = 3, 4
table.Count = function(t) local n = 0 for k in pairs(t or {}) do n = n + 1 end return n end
table.HasValue = function(t, val) for _, v in ipairs(istable(t) and t or {}) do if v == val then return true end end return false end
table.Copy = function(t) local r = {} for k, v in pairs(t or {}) do r[k] = istable(v) and table.Copy(v) or v end return r end

-- диск/JSON: снапшот-подход (контроль read-back)
local snaps, written = {}, {}
util = { AddNetworkString = function() end }
util.TableToJSON = function(t) snaps["__last"] = table.Copy(t) return "json" end
util.JSONToTable = function(txt, a, b)
    if txt == nil or txt == "" then return nil end
    return table.Copy(snaps["__last"] or {})
end
file = { Read = function(n) return written[n] end,
         Write = function(n, txt) written[n] = txt end,
         Exists = function(n) return written[n] ~= nil end,
         CreateDir = function() end, Find = function() return {} end,
         Delete = function(n) written[n] = nil end, IsDir = function() return true end, Append = function() end }
hook = { Add = function(name, id, fn) H.hooks[name] = H.hooks[name] or {} H.hooks[name][id] = fn end,
         Run = function(name, ...) local fns = H.hooks[name] or {} for id, fn in pairs(fns) do local r = fn(...) if r ~= nil then return r end end end }
timer = { Create = function() end, Simple = function(d, fn) if type(d) == "function" then d() elseif fn then fn() end end, Remove = function() end, Exists = function() return false end }

local netsent, curFrame = {}, nil
net = { Start = function(m) curFrame = { msg = m, tableV = nil } end,
        WriteString = function() end, WriteBool = function() end,
        WriteUInt = function(v) if curFrame then curFrame.uintV = v end end,
        WriteEntity = function() end,
        WriteTable = function(t) if curFrame then curFrame.tableV = t end end,
        Send = function() netsent[#netsent + 1] = curFrame curFrame = nil end,
        Broadcast = function() netsent[#netsent + 1] = curFrame curFrame = nil end,
        SendToServer = function() end,
        Receive = function(m, fn) H.netrecv[m] = fn end }
local seqVals = {}
net.ReadString = function() return tostring(table.remove(seqVals, 1) or "") end
net.ReadBool = function() local v = table.remove(seqVals, 1) return v == true or v == 1 end
net.ReadUInt = function() return tonumber(table.remove(seqVals, 1)) or 0 end
net.ReadTable = function() return _G._SIM.readTable end
player = { GetAll = function() return H.players or {} end, GetBySteamID = function() return nil end, GetBySteamID64 = function() return nil end }
game = { GetMap = function() return "gm_test" end }
function CurTime() return 1000 end
function SysTime() return 1000 end

-- игроки ---------------------------------------------------------------------
local PMT = {}
PMT.__index = function(t, k)
    if k:match("^SetNW") or k:match("^GetNW") then
        return function(s, key, val)
            if k:match("^Set") then s.nw = s.nw or {} s.nw[key] = val return end
            local v = s.nw and s.nw[key]
            if v == nil then if k:match("Int$") or k:match("Float$") then return 0 elseif k:match("Bool$") then return false end return "" end
            return v
        end
    end
    if k == "SteamID" then return function(s) return s.sid end
    elseif k == "SteamID64" then return function(s) return s.s64 end
    elseif k == "IsPlayer" then return function() return true end
    elseif k == "IsSuperAdmin" then return function(s) return s.super == true end
    elseif k == "Nick" then return function(s) return s.nick end
    elseif k == "ChatPrint" then return function(s, t) P(("CHAT[%s]: %s"):format(s.nick, tostring(t))) end
    elseif k == "PrintMessage" then return function(s, c, t) P(("MSG[%s]: %s"):format(s.nick, tostring(t))) end
    end
    return nil
end
local function mkPly(nick, sid, s64, super)
    return setmetatable({ nick = nick, sid = sid, s64 = s64, super = super }, PMT)
end
-- Владелец сервера: реальный сид из заказа — проверка зашита И в коде, И в тесте
local Root = mkPly("Владелец", "STEAM_0:1:712444114", "76561199049888766", true)
local Fool = mkPly("Идиот", "STEAM_0:1:099000001", "76561198000000021", true)
local Pete = mkPly("Пётр", "STEAM_0:1:000000011", "76561198000000011", false)
local Boss = mkPly("Шеф", "STEAM_0:1:000000012", "76561198000000012", false)
H.players = { Root, Fool, Pete, Boss }

local fails = 0
local function ok(cond, label)
    if cond then P("[OK] " .. label)
    else fails = fails + 1 P("[FAIL] " .. label) end
end
local function lastNet(msg)
    for i = #netsent, 1, -1 do if netsent[i].msg == msg then return netsent[i] end end
    return nil
end

-- мок фракций (для доски и исполнителя root guard) ---------------------------
local BossSid = Boss:SteamID()
Factions = {
    ["Полиция"] = {
        Leader = BossSid, LeaderRoleName = "Лидер",
        Roles = { "Лидер", "Офицер", "Кадет" },
        Departments = { "Основной", "Патруль" },
        Members = { [BossSid] = { Role = "Лидер", Department = "Основной" } },
    },
}
local apiCalls = {}
_G.FactionsAPI = {
    AddMember = function(f, sid) apiCalls.add = { f, sid } return true end,
    RemoveMember = function() return true end,
    GetFactionOf = function() return nil end,
    -- Реальная сигнатура API: IsLeader(steamID|ply, factionName) — плеер
    -- нормализуется через memberKey() (sh_factions.lua). Стаб повторяет это.
    IsLeader = function(ply, f)
        local sid = (type(ply) == "table" and ply:SteamID()) or ply
        return sid == BossSid and f == "Полиция"
    end,
    GetLeader = function(f) return BossSid end,
    PrimeRole = function() return "Кадет" end,
    Save = function() end, List = function() return Factions end,
    DeleteFaction = function(f) apiCalls.del = f return true end,
    Broadcast = function() apiCalls.bcast = true end,
    SetMemberRole = function(f, sid, r) apiCalls.role = { f, sid, r } return true end,
    SetMemberDepartment = function(f, sid, d) apiCalls.dept = { f, sid, d } return true end,
}
local notifyLog = {}
GRM = GRM or {}
GRM.Notify = function(ply, msg) notifyLog[#notifyLog + 1] = tostring(msg) end

-- ═══ 1. ROOT GUARD (реальный сервер) ═══
-- Ядро GRM (sh_00_grm_ui + sh_01_grm_core) — как на сервере, до модулей.
dofile("tools/luatest/lib_grm_core.lua")()
dofile("lua/autorun/sh_grm_rootguard.lua")
ok(GRM.Root ~= nil and GRM.Root.IsRoot ~= nil, "Root Guard загружен")
ok(GRM.Root.IsRoot(Root) == true, "владелец распознан root'ом по зашитому SteamID")
ok(GRM.Root.IsRoot(Fool) == false, "суперадмин-дурак root'ом НЕ является")
ok(GRM.Root.IsRoot(Pete) == false, "обычный игрок root'ом НЕ является")

-- дурак просит удаление фракции → в очередь, НЕ исполнено
local allowed = GRM.Root.Request(Fool, "faction_delete", "Удаление фракции «Полиция»", { faction = "Полиция" })
ok(allowed == false, "дураку: Request вернул false (исполнять запрещено)")
ok(#GRM.Root.Queue == 1, "заявка №1 стала в очередь")
ok(apiCalls.del == nil, "фракция НЕ удалена без подтверждения")
ok(lastNet("GRM_Root_Ask") ~= nil, "root онлайн — окно подтверждения отправлено")

-- root просит сам → мгновенно «да»
ok(GRM.Root.Request(Root, "faction_delete", "x", { faction = "Полиция" }) == true, "root'у: Request вернул true (мгновенно)")
ok(#GRM.Root.Queue == 1, "своих заявок у root нет (сразу исполняло бы UI-путь)")

-- root отклоняет заявку дурака
seqVals = { 1, false }
H.netrecv["GRM_Root_Answer"](0, Root)
ok(apiCalls.del == nil, "после ОТКЛОНЕНИЯ фракция не тронута")
ok(#GRM.Root.Queue == 0, "очередь очищена после ответа")

-- вторая заявка → root одобряет → исполнитель вызывает DeleteFaction
GRM.Root.Request(Fool, "faction_delete", "Удаление фракции «Полиция»", { faction = "Полиция" })
seqVals = { 2, true }
H.netrecv["GRM_Root_Answer"](0, Root)
ok(apiCalls.del == "Полиция", "после ОДОБРЕНИЯ DeleteFaction исполнен")
ok(apiCalls.bcast == true, "broadcast данных фракций после одобрения")
ok(#GRM.Root.Queue == 0, "очередь снова пуста")

-- дурак НЕ может отвечать на заявки: спам-пакет от него игнорируется
GRM.Root.Request(Fool, "faction_delete", "Ещё разок", { faction = "Полиция" })
seqVals = { 3, true }
H.netrecv["GRM_Root_Answer"](0, Fool)
ok(apiCalls.del == "Полиция" and #GRM.Root.Queue == 1, "ответ дурака отброшен — заявка висит (fail-closed)")
-- очередь «пережила» сервер: рестарт = потеря очереди = отказ (документировано); очистим вручную
GRM.Root.Queue = {}

-- root-команды в чате
local chatSay = (H.hooks["PlayerSay"] or {})["GRM_Root_Cmds"]
ok(chatSay ~= nil, "чат-хук root-команд на месте")
ok(chatSay(Fool, "/root_list") == "", "дураку /root_list отказано (пустой ответ-глушение)")
chatSay(Root, "/root_add STEAM_0:1:555000111")
ok(GRM.Root.Cfg == nil, "внутренняя таблица не утекла наружу (Cfg локальный)")
local Extra = mkPly("Помощник", "STEAM_0:1:555000111", "76561198000000099", true)
ok(GRM.Root.IsRoot(Extra) == true, "добавленный корень через /root_add распознан")
H.players[#H.players + 1] = Extra
ok(#GRM.Root.OnlineRoots() == 2, "онлайн-корней теперь двое")
GRM.Root.Request(Fool, "faction_delete", "И снова", { faction = "Полиция" })
seqVals = { 4, true }
H.netrecv["GRM_Root_Answer"](0, Extra)
ok(apiCalls.del == "Полиция", "добавленный корень ОДОБРИЛ заявку — исполнено")
chatSay(Root, "/root_del STEAM_0:1:555000111")
ok(GRM.Root.IsRoot(Extra) == false, "/root_del снял доп. корня")
-- нельзя срезать сид-корень
chatSay(Root, "/root_del STEAM_0:1:712444114")
ok(GRM.Root.IsRoot(Root) == true, "сид-корня команда удалить не может")

-- ═══ 2. ДОСКА v1.1.0 (реальный сервер) ═══
dofile("lua/autorun/sh_grm_board.lua")
ok(GRM.Board ~= nil and GRM.Board.Cfg ~= nil, "доска загружена")
GRM.Board.Cfg.allow["Полиция"] = true
GRM.Board.Cfg.open["Полиция"] = true

-- дурак/игрок НЕ может настраивать зачисление
seqVals = { "Полиция", "Патруль", "Офицер" }
H.netrecv["GRM_Board_Assign"](0, Pete)
ok(GRM.Board.Cfg.assign["Полиция"] == nil, "Петру настройка зачисления запрещена")

-- лидер задаёт: отдел «Патруль», должность «Офицер»
seqVals = { "Полиция", "Патруль", "Офицер" }
H.netrecv["GRM_Board_Assign"](0, Boss)
local asg = GRM.Board.Cfg.assign["Полиция"]
ok(asg ~= nil and asg.dept == "Патруль" and asg.role == "Офицер", "лидер сохранил автозачисление")
ok(snaps["__last"] and snaps["__last"].assign and snaps["__last"].assign["Полиция"] and snaps["__last"].assign["Полиция"].dept == "Патруль", "конфиг assign записан на диск (SaveCfg)")

-- невалидные значения отброшены
seqVals = { "Полиция", "Космос", "Офицер" }
H.netrecv["GRM_Board_Assign"](0, Boss)
ok(GRM.Board.Cfg.assign["Полиция"].dept == "Патруль", "несуществующий отдел отвергнут, старое зачисление цело")
seqVals = { "Полиция", "", "Лидер" }
H.netrecv["GRM_Board_Assign"](0, Boss)
ok(GRM.Board.Cfg.assign["Полиция"].role == "Офицер", "роль лидера как автозачисление отвергнута")

-- Пётр вступает → AddMember + автоназначение отдела/должности
apiCalls.role, apiCalls.dept = nil, nil
seqVals = { "Полиция" }
H.netrecv["GRM_Board_Join"](0, Pete)
ok(apiCalls.add ~= nil and apiCalls.add[1] == "Полиция", "Пётр принят во фракцию через доску")
ok(apiCalls.dept ~= nil and apiCalls.dept[3] == "Патруль", "автозачисление в отдел «Патруль» применено")
ok(apiCalls.role ~= nil and apiCalls.role[3] == "Офицер", "автоназначение должности «Офицер» применено")
local jn = GRM.Board.Cfg.journal["Полиция"]
ok(jn ~= nil and jn[1] ~= nil and jn[1].dept == "Патруль" and jn[1].role == "Офицер", "журнал зафиксировал назначение")

-- сброс в «по умолчанию»: assign удаляется
seqVals = { "Полиция", "", "" }
H.netrecv["GRM_Board_Assign"](0, Boss)
ok(GRM.Board.Cfg.assign["Полиция"] == nil, "сброс возвращает зачисление по умолчанию")

-- ═══ 3. Q-МЕНЮ v1.1.0: клиентская ветка ═══
dofile("lua/autorun/sh_grm_qmenu.lua") -- серверная часть (PushSync и проверки)
ok(GRM.QMenu.Cfg ~= nil and GRM.QMenu.Cfg.playersQ == true, "qmenu: дефолт playersQ=true")
-- Save → PushSync Broadcast
netsent = {}
GRM.QMenu.Save("тест стенда")
local sy = lastNet("GRM_QMenu_Sync")
ok(sy ~= nil and istable(sy.tableV) and sy.tableV.playersQ == true, "qmenu: после Save конфиг рассылается (GRM_QMenu_Sync)")

-- клиентская ветка: перезагружаем файл с CLIENT=true
-- стаб vgui: build-меню v2.0.0 при нажатии Q строит DFrame — в стенде панели не настоящие
local ANYfun; local ANYobj = setmetatable({}, { __index = function() return ANYfun end })
ANYfun = function() return ANYobj end
_G.vgui = { Create = function() return ANYobj end }
if _G._SIM == nil then _G._SIM = {} end
SERVER, CLIENT = false, true
local Me = Pete
function LocalPlayer() return Me end
dofile("lua/autorun/sh_grm_qmenu.lua")
ok(H.netrecv["GRM_QMenu_Sync"] ~= nil, "клиент: приёмник синка зарегистрирован")
-- выключили playersQ и подсинхронили клиента
_G._SIM.readTable = { playersQ = false, allowProps = true, allowRagdolls = true }
H.netrecv["GRM_QMenu_Sync"]()
ok(GRM.QMenu.Cfg.playersQ == false, "клиент: конфиг подхвачен (playersQ=false)")
ok(GRM.QMenu.Cfg.allowVehiclesQ == false, "клиент: слияние поверх дефолтов сохранило вложенные поля")

local bindHook = (H.hooks["PlayerBindPress"] or {})["GRM_QMenu_BindBlock"]
ok(bindHook ~= nil, "клиент: хук PlayerBindPress на месте (универсальный Q-гейт)")
ok(bindHook(Me, "+menu", true) == true, "playersQ=false: бинд +menu ГЛУШИТСЯ (ванила и кастом не стартуют)")
ok(bindHook(Me, "+menu_context", true) == nil, "бинд C не трогаем (там наше GRM-меню)")
ok(bindHook(Me, "+attack", true) == nil, "прочие бинды не трогаем")
ok(bindHook(Me, "+menu", false) == true, "v3.3.0 hold-Q: отпускание +menu тоже глушится (и закрывает меню)")
Me = Root
ok(bindHook(Me, "+menu", true) == nil, "суперадмин — байпас даже при playersQ=false")
Me = Pete
local openHook = (H.hooks["SpawnMenuOpen"] or {})["GRM_QMenu_BlockOpen"]
ok(openHook and openHook() == false, "SpawnMenuOpen: ванильное Q закрыто при playersQ=false")
_G._SIM.readTable = { playersQ = true }
H.netrecv["GRM_QMenu_Sync"]()
ok(GRM.QMenu.Cfg.playersQ == true, "обратное включение долетело до клиента")
ok(bindHook(Me, "+menu", true) == nil, "playersQ=true: бинд +menu проходит свободно")

if fails == 0 then
    P("=== ИТОГ: ВСЕ ПРОВЕРКИ ПРОШЛИ ===")
else
    P("=== ИТОГ: ПРОВАЛОВ: " .. tostring(fails) .. " ===")
    os.exit(1)
end
