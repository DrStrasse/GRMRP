--[[--------------------------------------------------------------------
    GRM Alarm Integration (находка 179h)
    Связывает сигнализацию с устройствами доступа:
      • Кейпады (grm_keypad): неверный PIN, взлом взломщиком, полный ввод;
      • Сканеры (grm_scanner): отказ доступа, взлом;
      • Двери (FFD/sliding/обычные): взлом (ds_lockpick), взлом чипом,
        принудительное открытие (таран/ордер не считается — это законно);
      • Всё пишется в ЖУРНАЛ СИГНАЛИЗАЦИИ (A.Log) с пометкой kind="breach"
        и идёт ОПОВЕЩЕНИЕ нужным фракциям (настраивает суперадмин).
    Настройка оповещаемых фракций: /grm_alarm_notify (суперадмин, чекбоксы)
    или /grm_admin → Сигнализация → «Фракции для оповещения».
----------------------------------------------------------------------]]
if SERVER then
    AddCSLuaFile()
    AddCSLuaFile("autorun/client/cl_grm_alarm_notify.lua")
end

GRM = GRM or {}
GRM.AlarmNotify = GRM.AlarmNotify or {}
local AN = GRM.AlarmNotify

local FILE = "grm_alarm_notify_factions.json"
AN.Data = istable(AN.Data) and AN.Data or { factions = {} }
local DATA = AN.Data  -- { ["Mafia"] = true, ... } (пусто = никто)

-- ── загрузка/сохранение ────────────────────────────────────
local function ensureDir()
    if not file.IsDir("grm_alarm", "DATA") then file.CreateDir("grm_alarm") end
end
function AN.Save()
    ensureDir()
    local ok, txt = pcall(util.TableToJSON, DATA, true)
    if ok and isstring(txt) then file.Write(FILE, txt) end
end
function AN.Load()
    ensureDir()
    if not file.Exists(FILE, "DATA") then return end
    local t = nil
    local ok, res = pcall(util.JSONToTable, file.Read(FILE, "DATA") or "", false, true)
    if ok and istable(res) then t = res end
    if istable(t) and istable(t.factions) then
        DATA.factions = {}
        for k, v in pairs(t.factions) do if v == true then DATA.factions[tostring(k)] = true end end
    end
end
AN.Load()

function AN.GetFactions()
    return DATA.factions
end

-- оповещаемая ли фракция (пустой список = никто не оповещается)
function AN.IsNotified(facName)
    if facName == nil or facName == "" then return false end
    return DATA.factions[tostring(facName)] == true
end

function AN.NotifyFactions(text, pos)
    for facName in pairs(DATA.factions) do
        -- шлём всем членам оповещаемых фракций (онлайн)
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(p) and AN.FactionOf(p) == facName then
                if GRM.Notify then
                    GRM.Notify(p, text, 255, 120, 80)
                end
            end
        end
    end
    -- метка на мини-карте (временный маркер тревоги) — если есть API
    if pos and GRM.Minimap and GRM.Minimap.AddTempPoint then
        -- Метка взлома живёт минуту: дальше она только мешает и путает
        -- патрули (заказ владельца 19.08).
        if GRM.Minimap.RemoveTempPoint then GRM.Minimap.RemoveTempPoint("ВЗЛОМ/ВМЕШАТЕЛЬСТВО") end
        GRM.Minimap.AddTempPoint("ВЗЛОМ/ВМЕШАТЕЛЬСТВО", pos, 60)
        if GRM.Minimap.SendTo then
            for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                if IsValid(p) then GRM.Minimap.SendTo(p) end
            end
        end
    end
end

-- фракция игрока
function AN.FactionOf(ply)
    if not IsValid(ply) then return nil end
    if Factions then
        for name, f in pairs(Factions) do
            local member = GRM.Identity and GRM.Identity.FactionMember and GRM.Identity.FactionMember(f, ply)
            if not member and not GRM.Identity then
                member = istable(f) and istable(f.Members) and (f.Members[ply:SteamID()] or f.Members[ply:SteamID64()])
            end
            if member then return name end
        end
    end
    return nil
end

-- ══ СОБЫТИЕ ВМЕШАТЕЛЬСТВА ══════════════════════════════════
-- text — что случилось; ent — устройство; pos — точка; kind — "breach"
function AN.Report(text, ent, pos, kind)
    text = tostring(text or "Вмешательство в устройство доступа")
    -- 1) в журнал сигнализации (kind="breach")
    if GRM.Alarm and GRM.Alarm.Log then
        local netID = "main"
        if IsValid(ent) and ent.GetNetworkID then
            local nid = ent:GetNetworkID()
            if nid and nid ~= "" then netID = nid end
        end
        GRM.Alarm.Log(netID, kind or "breach", text)
    end
    -- 2) оповещение фракций + маркер
    local p = pos or (IsValid(ent) and ent:GetPos() or nil)
    AN.NotifyFactions("⚠ " .. text, p)
    print(("[GRM Alarm][!] %s"):format(text))
end

-- ── ИНТЕГРАЦИЯ: хуки устройств ─────────────────────────────
-- Кейпад: неверный PIN (ProcessDeny от человека) — вмешательство
hook.Add("GRM_KeypadDenied", "GRM_AlarmNotify_KeypadDenied", function(ply, kp)
    if not IsValid(ply) or not IsValid(kp) then return end
    AN.Report("Кейпад: неверный PIN (" .. ply:Nick() .. ")", kp, kp:GetPos())
end)
-- Кейпад/сканер: взлом взломщиком (уже есть хук GRM_OnDeviceHacked)
hook.Add("GRM_OnDeviceHacked", "GRM_AlarmNotify_DeviceHacked", function(ply, target)
    if not IsValid(ply) or not IsValid(target) then return end
    local cls = target:GetClass()
    if cls == "grm_keypad" then
        AN.Report("ВЗЛОМ КЕЙПАДА (" .. ply:Nick() .. ")", target, target:GetPos())
    elseif cls == "grm_scanner" then
        AN.Report("ВЗЛОМ СКАНЕРА (" .. ply:Nick() .. ")", target, target:GetPos())
    elseif target.isFadingDoor or target.isSlidingDoor then
        AN.Report("ВЗЛОМ ЭЛЕКТРОНИКИ ДВЕРИ (" .. ply:Nick() .. ")", target, target:GetPos())
    end
end)
-- Обычная дверь: взлом (ds_lockpick)
hook.Add("GRM_OnDoorLockpicked", "GRM_AlarmNotify_DoorLockpicked", function(ply, door)
    if not IsValid(ply) or not IsValid(door) then return end
    AN.Report("ВЗЛОМ ЗАМКА ДВЕРИ (" .. ply:Nick() .. ")", door, door:GetPos())
end)
-- Взлом двери чипом (аугментация doorHack) — если есть хук
hook.Add("GRM_DoorHacked", "GRM_AlarmNotify_DoorHacked", function(ply, door)
    if not IsValid(ply) or not IsValid(door) then return end
    AN.Report("ВЗЛОМ ДВЕРИ ЧИПОМ (" .. ply:Nick() .. ")", door, door:GetPos())
end)
-- Сканер: отказ доступа (подозрительный)
hook.Add("GRM_ScannerDenied", "GRM_AlarmNotify_ScannerDenied", function(ply, scanner)
    if not IsValid(ply) or not IsValid(scanner) then return end
    AN.Report("Сканер: отказ доступа (" .. ply:Nick() .. ")", scanner, scanner:GetPos())
end)

-- ══ НАСТРОЙКА ФРАКЦИЙ (суперадмин) ═════════════════════════
-- Находка 179h-fix: AddNetworkString — ТОЛЬКО на сервере (на клиенте её нет)
if SERVER then
    util.AddNetworkString("GRM_AlarmNotify_Open")
    util.AddNetworkString("GRM_AlarmNotify_Save")
    util.AddNetworkString("GRM_AlarmNotify_Data")

    net.Receive("GRM_AlarmNotify_Open", function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        net.Start("GRM_AlarmNotify_Data")
            net.WriteTable(DATA)
            net.WriteTable(AN.FactionList())
        net.Send(ply)
    end)
    net.Receive("GRM_AlarmNotify_Save", function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        local selected = net.ReadTable() or {}
        DATA.factions = {}
        for _, n in ipairs(selected) do
            if isstring(n) and string.Trim(n) ~= "" then DATA.factions[string.Trim(n)] = true end
        end
        AN.Save()
        if GRM.Notify then GRM.Notify(ply, "Фракции оповещения сохранены: " .. (#(DATA.factions) > 0 and table.concat(selected, ", ") or "никто"), 100, 220, 130) end
    end)
end -- if SERVER (сеть настройки)

function AN.FactionList()
    local out = {}
    if istable(Factions) then
        for name in pairs(Factions) do
            if istable(Factions[name]) then out[#out + 1] = tostring(name) end
        end
    end
    table.sort(out)
    return out
end

-- чат-команда /grm_alarm_notify (суперадмин, EasyChat-совместимо)
if SERVER then
    local function openNotifyMenu(ply)
        if not IsValid(ply) then return end
        if not ply:IsSuperAdmin() then
            if GRM.Notify then GRM.Notify(ply, "Только суперадмин.", 255, 100, 100) end
            return
        end
        net.Start("GRM_AlarmNotify_Open")
        net.SendToServer()
    end
    concommand.Add("grm_alarm_notify", function(ply) openNotifyMenu(ply) end)
    hook.Add("PlayerSay", "GRM_AlarmNotify_Chat", function(ply, text, teamSays)
        local datapack = { tostring(text or ""), SkipPlayerSay = false }
            if not istable(datapack) then return end
            local text = datapack[1]
            if not isstring(text) then return end
            if string.lower(string.Trim(text)) ~= "/grm_alarm_notify" then return end
            openNotifyMenu(ply)
            datapack.SkipPlayerSay = true
            datapack[1] = ""

        if datapack.SkipPlayerSay == true then return "" end
    end)
end

print("[GRM Alarm] Integration loaded (находка 179h): взломы кейпадов/сканеров/дверей → журнал + оповещение фракций")

-- Вечер-18: команды пересажены с мёртвого входа EasyChat (PlayerSayTransform)
-- на боевой контракт библиотеки GRMRPChat — имена в едином внешнем реестре,
-- иначе чат съел бы их как «неизвестные» и по цепочке PlayerSay вызвал бы
-- обработчики этого файла.
if GRM and GRM.Chat and GRM.Chat.RegisterExternalCommands then
    GRM.Chat.RegisterExternalCommands({ "/grm_alarm_notify" })
end
