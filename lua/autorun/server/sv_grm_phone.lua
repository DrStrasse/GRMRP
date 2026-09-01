--[[--------------------------------------------------------------------
    GRM Phone Lines System - Server
--------------------------------------------------------------------]]

if not SERVER then return end

AddCSLuaFile("autorun/sh_grm_phone_config.lua")
AddCSLuaFile("autorun/client/cl_grm_phone.lua")
AddCSLuaFile("entities/grm_phone/shared.lua")
AddCSLuaFile("entities/grm_phone/cl_init.lua")
AddCSLuaFile("entities/grm_payphone/shared.lua")
AddCSLuaFile("entities/grm_payphone/cl_init.lua")
AddCSLuaFile("entities/grm_pbx_station/shared.lua")
AddCSLuaFile("entities/grm_pbx_station/cl_init.lua")
AddCSLuaFile("entities/grm_phone_wiretap/shared.lua")
AddCSLuaFile("entities/grm_phone_wiretap/cl_init.lua")
AddCSLuaFile("entities/grm_phone_terminal/shared.lua")
AddCSLuaFile("entities/grm_phone_terminal/cl_init.lua")

include("autorun/sh_grm_phone_config.lua")

GRM = GRM or {}
GRM.Phone = GRM.Phone or {}
local P = GRM.Phone

P.Calls = P.Calls or {}
P.NextCallID = P.NextCallID or 1
P.PlayerDevice = P.PlayerDevice or {}
P.Monitoring = P.Monitoring or {}

local NET_OPEN_PHONE   = "GRM_Phone_OpenPhone"
local NET_OPEN_PBX     = "GRM_Phone_OpenPBX"
local NET_OPEN_WIRETAP = "GRM_Phone_OpenWiretap"
local NET_OPEN_TERMINAL = "GRM_Phone_OpenTerminal"
local NET_ACTION       = "GRM_Phone_Action"
local NET_SYNC         = "GRM_Phone_Sync"
local NET_INFO         = "GRM_Phone_Info"
local NET_TEXT         = "GRM_Phone_Text"

for _, n in ipairs({ NET_OPEN_PHONE, NET_OPEN_PBX, NET_OPEN_WIRETAP, NET_OPEN_TERMINAL, NET_ACTION, NET_SYNC, NET_INFO, NET_TEXT }) do
    util.AddNetworkString(n)
end

local function cfg() return P.Config or {} end
local function soundPath(key) return cfg().Sounds and cfg().Sounds[key] or nil end

local function notify(ply, msg, bad)
    if not IsValid(ply) then return end
    net.Start(NET_INFO)
        net.WriteString(msg or "")
        net.WriteBool(bad and true or false)
    net.Send(ply)
end

local function emit(ent, key)
    if not IsValid(ent) then return end
    local s = soundPath(key)
    if s and s ~= "" then ent:EmitSound(s, 65, 100) end
end

local RECORD_DIR = "grm_phone_records"

local function ensureRecordDir()
    if not file.Exists(RECORD_DIR, "DATA") then file.CreateDir(RECORD_DIR) end
end

local function recordLine(line)
    ensureRecordDir()
    local date = os.date("%Y-%m-%d")
    file.Append(RECORD_DIR .. "/" .. date .. ".txt", "[" .. os.date("%H:%M:%S") .. "] " .. tostring(line or "") .. "\n")
end

local function getFactionInfo(ply)
    if not IsValid(ply) or not Factions then return nil, nil, nil end
    local sid, sid64 = ply:SteamID(), ply:SteamID64()
    local charKey = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply)) or sid64
    for name, f in pairs(Factions) do
        if istable(f) and istable(f.Members) then
            local m = GRM.Identity.FactionMember(f, ply)
            if istable(m) then return name, m.Role, m.Department end
        end
    end
    return nil, nil, nil
end

local function nestedAllows(t, group, key)
    if not istable(t) or not key then return false end
    if istable(t[group]) and t[group][key] == true then return true end
    if istable(t["*"]) and t["*"][key] == true then return true end
    return false
end

function P.HasEquipmentAccess(ply)
    if not IsValid(ply) then return false end
    local ac = cfg().Access or {}
    if ac.SuperAdminBypass ~= false and ply:IsSuperAdmin() then return true end
    if ac.AdminBypass and ply:IsAdmin() then return true end

    local faction, role, dept = getFactionInfo(ply)
    if not faction then return false end
    if istable(ac.AllowedFactions) and ac.AllowedFactions[faction] == true then return true end
    if nestedAllows(ac.AllowedRoles, faction, role) then return true end
    if nestedAllows(ac.AllowedDepartments, faction, dept) then return true end
    return false
end

local function allPhones()
    local out = {}
    for _, ent in ipairs(ents.FindByClass("grm_phone")) do out[#out + 1] = ent end
    for _, ent in ipairs(ents.FindByClass("grm_payphone")) do out[#out + 1] = ent end
    for _, ent in ipairs(ents.FindByClass("grm_mobile_line")) do out[#out + 1] = ent end -- Код 88: сотовые линии
    return out
end

local function isPhoneEntity(ent)
    if not IsValid(ent) then return false end
    local class = ent:GetClass()
    return class == "grm_phone" or class == "grm_payphone" or class == "grm_mobile_line"
end

local function updatePhoneVisual(phone, state)
    if not IsValid(phone) then return end
    if phone:GetClass() ~= "grm_phone" then return end -- будка модель не меняет

    local c = cfg()
    local onHook = c.PhoneModelOnHook or c.PhoneModel or "models/props/cs_office/phone.mdl"
    local offHook = c.PhoneModelOffHook or "models/props/cs_office/phone_p1.mdl"

    if state == "dialing" or state == "call" then
        phone:SetModel(offHook)
    else
        phone:SetModel(onHook)
    end
end

local function allPBX()
    return ents.FindByClass("grm_pbx_station")
end

local function allWiretaps()
    return ents.FindByClass("grm_phone_wiretap")
end

local function allTerminals()
    return ents.FindByClass("grm_phone_terminal")
end

function P.GenerateNumber()
    for _ = 1, 2000 do
        local n = tostring(math.random(cfg().MinNumber or 1000, cfg().MaxNumber or 9999))
        if not P.FindPhoneByNumber(n) then return n end
    end
    return tostring(math.random(10000, 99999))
end

function P.FindPhoneByNumber(number)
    number = tostring(number or "")
    if number == "" then return nil end
    for _, ent in ipairs(allPhones()) do
        if IsValid(ent) and ent:GetPhoneNumber() == number then return ent end
    end
    return nil
end

function P.FindPBX(exchangeID)
    exchangeID = tostring(exchangeID or "main")
    for _, ent in ipairs(allPBX()) do
        if IsValid(ent) and ent:GetExchangeID() == exchangeID then return ent end
    end
    return nil
end

function P.IsExchangeActive(exchangeID)
    if cfg().RequireActivePBX == false then return true end
    local pbx = P.FindPBX(exchangeID)
    return IsValid(pbx) and pbx:GetActive()
end

function P.GetExchangeUsage(exchangeID)
    exchangeID = tostring(exchangeID or "main")
    local used = 0
    for _, call in pairs(P.Calls or {}) do
        if call and IsValid(call.from) and IsValid(call.to) then
            local a = call.from:GetExchangeID()
            local b = call.to:GetExchangeID()
            if a == exchangeID or b == exchangeID then
                used = used + 1
            end
        end
    end
    return used
end

function P.GetExchangeMaxLines(exchangeID)
    local pbx = P.FindPBX(exchangeID)
    if IsValid(pbx) then
        return math.max(tonumber(pbx:GetMaxLines()) or 0, 0)
    end
    return tonumber(cfg().PBXDefaultMaxLines) or 60
end

function P.HasFreeExchangeLine(exchangeID)
    if cfg().RequireActivePBX == false and not IsValid(P.FindPBX(exchangeID)) then return true end
    return P.GetExchangeUsage(exchangeID) < P.GetExchangeMaxLines(exchangeID)
end

local function setPhoneState(phone, state, callID, other)
    if not IsValid(phone) then return end
    state = state or "idle"
    phone:SetLineState(state)
    phone:SetCallID(callID or 0)
    phone:SetOtherPhone(IsValid(other) and other or NULL)
    updatePhoneVisual(phone, state)
end

local function getCall(id)
    return P.Calls[tonumber(id) or 0]
end

local function endCall(call, reason)
    if not call then return end
    recordLine("CALL END #" .. tostring(call.id) .. " reason=" .. tostring(reason or "unknown"))
    P.Calls[call.id] = nil
    for _, ph in ipairs({ call.from, call.to }) do
        if IsValid(ph) then
            setPhoneState(ph, "idle", 0, NULL)
            ph.CurrentUser = nil
            emit(ph, "Hangup")
        end
    end
end

-- Код 88: внешний сброс разговора (потеря сигнала сотовой и т.п.)
function P.ForceEndCall(call, reason) endCall(call, reason) end

local function canUsePhone(ply, phone)
    if not IsValid(ply) or not IsValid(phone) then return false end
    -- Код 88: сотовая линия — «рука» это наличие телефона в инвентаре
    if phone.IsMobile then
        return (GRM.Mobile and GRM.Mobile.CanUseLine and GRM.Mobile.CanUseLine(ply, phone)) == true
    end
    return ply:GetPos():DistToSqr(phone:GetPos()) <= (cfg().MaxUseDistance or 180) ^ 2
end

local function attachUserToPhone(ply, phone)
    if not canUsePhone(ply, phone) then return false end
    if IsValid(phone.CurrentUser) and phone.CurrentUser ~= ply then
        notify(ply, "Телефон уже занят другим игроком.", true)
        return false
    end
    phone.CurrentUser = ply
    P.PlayerDevice[ply] = phone
    return true
end

local function detachUser(ply)
    local ent = P.PlayerDevice[ply]
    if IsValid(ent) and ent.CurrentUser == ply then ent.CurrentUser = nil end
    P.PlayerDevice[ply] = nil
    P.Monitoring[ply] = nil
end

local function phoneCanCall(a, b)
    if not IsValid(a) or not IsValid(b) then return false, "Телефон не найден." end
    if a == b then return false, "Нельзя позвонить самому себе." end
    if a:GetLineState() ~= "idle" then return false, "Ваша линия занята." end
    if b:GetLineState() ~= "idle" then return false, "Номер занят." end

    local exA, exB = a:GetExchangeID(), b:GetExchangeID()
    -- Код 88: сотовая линия вместо АТС требует сигнала сети RadioNet
    if a.IsMobile then
        if not (GRM.Mobile and GRM.Mobile.LineOnline and GRM.Mobile.LineOnline(a)) then
            return false, "Нет сигнала сотовой связи (покрытие сети / телефон в инвентаре)."
        end
    elseif not P.IsExchangeActive(exA) then return false, "АТС вашей линии отключена." end
    if b.IsMobile then
        if not (GRM.Mobile and GRM.Mobile.LineOnline and GRM.Mobile.LineOnline(b)) then
            return false, "Абонент вне зоны покрытия сотовой связи."
        end
    elseif not P.IsExchangeActive(exB) then return false, "АТС вызываемой линии отключена." end
    -- сотовая сеть соединяет с любой линией; АТС↔АТС — по старому правилу
    if exA ~= exB and not (a.IsMobile or b.IsMobile) and cfg().AllowCrossExchangeCalls ~= true then return false, "Между этими АТС нет соединения." end
    if not a.IsMobile and not P.HasFreeExchangeLine(exA) then return false, "На вашей АТС нет свободных линий." end
    if exB ~= exA and not b.IsMobile and not P.HasFreeExchangeLine(exB) then return false, "На вызываемой АТС нет свободных линий." end
    return true
end

function P.Dial(ply, phone, number)
    if not attachUserToPhone(ply, phone) then return end
    number = tostring(number or "")
    local target = P.FindPhoneByNumber(number)

    local ok, err = phoneCanCall(phone, target)
    if not ok then notify(ply, err, true) emit(phone, "Deny") return end

    local id = P.NextCallID
    P.NextCallID = id + 1

    local call = { id = id, from = phone, to = target, answered = false, started = CurTime(), exchange = phone:GetExchangeID() }
    P.Calls[id] = call

    setPhoneState(phone, "dialing", id, target)
    setPhoneState(target, "ringing", id, phone)

    emit(phone, "Dial")
    emit(target, "Ring")
    notify(ply, "Вызов номера " .. number .. "...")

    recordLine("CALL START #" .. id .. " " .. phone:GetPhoneNumber() .. " -> " .. target:GetPhoneNumber())
end

function P.Answer(ply, phone)
    if not attachUserToPhone(ply, phone) then return end

    local call = getCall(phone:GetCallID())
    if not call or call.to ~= phone or phone:GetLineState() ~= "ringing" then notify(ply, "Нет входящего вызова.", true) return end

    call.answered = true
    call.answeredAt = CurTime()

    setPhoneState(call.from, "call", call.id, call.to)
    setPhoneState(call.to, "call", call.id, call.from)

    emit(call.from, "Pickup")
    emit(call.to, "Pickup")

    recordLine("CALL ANSWERED #" .. call.id .. " " .. call.from:GetPhoneNumber() .. " <-> " .. call.to:GetPhoneNumber())
end

function P.Hangup(ply, phone)
    if not IsValid(phone) then return end
    local call = getCall(phone:GetCallID())
    if call then endCall(call, "hangup") else setPhoneState(phone, "idle", 0, NULL) end

    if phone.CurrentUser == ply then phone.CurrentUser = nil end
    if P.PlayerDevice[ply] == phone then P.PlayerDevice[ply] = nil end
end

function P.SyncEntity(ent, ply)
    if not IsValid(ent) then return end
    net.Start(NET_SYNC)
        net.WriteEntity(ent)
        net.WriteString(ent:GetClass())
    if isPhoneEntity(ent) then
        net.WriteString(ent:GetPhoneNumber())
        net.WriteString(ent:GetDisplayName())
        net.WriteString(ent:GetExchangeID())
        net.WriteString(ent:GetLineState())
        net.WriteUInt(ent:GetCallID(), 16)
    elseif ent:GetClass() == "grm_pbx_station" then
        net.WriteString(ent:GetExchangeID())
        net.WriteBool(ent:GetActive())
        net.WriteUInt(math.Clamp(ent:GetMaxLines(), 0, 4095), 12)
    elseif ent:GetClass() == "grm_phone_wiretap" then
        net.WriteString(ent:GetTargetNumber())
        net.WriteString(ent:GetExchangeID())
        net.WriteBool(ent:GetActive())
    end
    if IsValid(ply) then net.Send(ply) else net.Broadcast() end
end

function P.OpenPhoneMenu(ply, phone)
    if not IsValid(ply) or not IsValid(phone) then return end
    net.Start(NET_OPEN_PHONE)
        net.WriteEntity(phone)
        net.WriteString(phone:GetPhoneNumber())
        net.WriteString(phone:GetDisplayName())
        net.WriteString(phone:GetExchangeID())
        net.WriteString(phone:GetLineState())
        net.WriteUInt(phone:GetCallID(), 16)
    net.Send(ply)
end

function P.OpenPBXMenu(ply, ent)
    if not P.HasEquipmentAccess(ply) then notify(ply, "Нет доступа к оборудованию АТС.", true) return end
    net.Start(NET_OPEN_PBX)
        net.WriteEntity(ent)
        net.WriteString(ent:GetExchangeID())
        net.WriteBool(ent:GetActive())
        net.WriteUInt(math.Clamp(ent:GetMaxLines(), 0, 4095), 12)
    net.Send(ply)
end

function P.OpenWiretapMenu(ply, ent)
    if not P.HasEquipmentAccess(ply) then notify(ply, "Нет доступа к оборудованию прослушки.", true) return end
    net.Start(NET_OPEN_WIRETAP)
        net.WriteEntity(ent)
        net.WriteString(ent:GetTargetNumber())
        net.WriteString(ent:GetExchangeID())
        net.WriteBool(ent:GetActive())
    net.Send(ply)
end

function P.BuildTerminalData()
    local phones = {}
    for _, ph in ipairs(allPhones()) do
        if IsValid(ph) then
            phones[#phones + 1] = {
                number = ph:GetPhoneNumber(),
                name = ph:GetDisplayName(),
                exchange = ph:GetExchangeID(),
                state = ph:GetLineState(),
                callID = ph:GetCallID(),
                class = ph:GetClass(),
            }
        end
    end
    table.sort(phones, function(a, b) return tostring(a.number) < tostring(b.number) end)

    local exchanges = {}
    for _, pbx in ipairs(allPBX()) do
        if IsValid(pbx) then
            local id = pbx:GetExchangeID()
            exchanges[#exchanges + 1] = {
                exchange = id,
                active = pbx:GetActive(),
                used = P.GetExchangeUsage(id),
                max = P.GetExchangeMaxLines(id),
            }
        end
    end
    table.sort(exchanges, function(a, b) return tostring(a.exchange) < tostring(b.exchange) end)

    local calls = {}
    for _, call in pairs(P.Calls or {}) do
        if call and IsValid(call.from) and IsValid(call.to) then
            calls[#calls + 1] = {
                id = call.id,
                from = call.from:GetPhoneNumber(),
                to = call.to:GetPhoneNumber(),
                fromExchange = call.from:GetExchangeID(),
                toExchange = call.to:GetExchangeID(),
                answered = call.answered == true,
                age = math.floor(CurTime() - (call.started or CurTime())),
            }
        end
    end
    table.sort(calls, function(a, b) return a.id < b.id end)

    return { phones = phones, exchanges = exchanges, calls = calls }
end

function P.OpenTerminalMenu(ply, ent)
    if not P.HasEquipmentAccess(ply) then notify(ply, "Нет доступа к компьютеру мониторинга связи.", true) return end
    net.Start(NET_OPEN_TERMINAL)
        net.WriteEntity(ent)
        net.WriteTable(P.BuildTerminalData())
    net.Send(ply)
end

local function actionRequiresEnt(ply, ent)
    if not IsValid(ent) then return false end
    if ply:GetPos():DistToSqr(ent:GetPos()) > (cfg().MaxUseDistance or 180) ^ 2 then notify(ply, "Вы слишком далеко от оборудования.", true) return false end
    return true
end

net.Receive(NET_ACTION, function(_, ply)
    local action = net.ReadString()
    local ent = net.ReadEntity()
    if not actionRequiresEnt(ply, ent) then return end

    if action == "phone_dial" then P.Dial(ply, ent, net.ReadString()) return end
    if action == "phone_answer" then P.Answer(ply, ent) return end
    if action == "phone_hangup" then P.Hangup(ply, ent) return end
    if action == "phone_pickup" then attachUserToPhone(ply, ent) emit(ent, "Pickup") return end

    if action == "phone_release" then
        -- Положить трубку: если есть активный/исходящий/входящий вызов — завершает его,
        -- иначе просто освобождает телефон для другого игрока.
        if isPhoneEntity(ent) and ent:GetLineState() ~= "idle" then
            P.Hangup(ply, ent)
        else
            detachUser(ply)
            emit(ent, "Hangup")
        end
        return
    end

    if action == "pbx_set" then
        if not P.HasEquipmentAccess(ply) then return end
        ent:SetExchangeID(net.ReadString())
        ent:SetActive(net.ReadBool())
        local maxLines = net.ReadUInt(12)
        if maxLines > 0 then ent:SetMaxLines(math.Clamp(maxLines, 1, 4095)) end
        P.SyncEntity(ent)
        emit(ent, "Switch")
        return
    end

    if action == "wiretap_set" then
        if not P.HasEquipmentAccess(ply) then return end
        ent:SetTargetNumber(net.ReadString())
        ent:SetExchangeID(net.ReadString())
        ent:SetActive(net.ReadBool())
        P.SyncEntity(ent)
        emit(ent, "Switch")
        return
    end

    if action == "wiretap_monitor" then
        if not P.HasEquipmentAccess(ply) then return end
        P.Monitoring[ply] = ent
        ent.CurrentUser = ply
        notify(ply, "Прослушка включена.")
        recordLine("WIRETAP MONITOR " .. ply:Nick() .. "(" .. ply:SteamID() .. ") target=" .. ent:GetTargetNumber() .. " exchange=" .. ent:GetExchangeID())
        return
    end

    if action == "terminal_refresh" then
        if not P.HasEquipmentAccess(ply) then return end
        if ent:GetClass() == "grm_phone_terminal" then
            P.OpenTerminalMenu(ply, ent)
        end
        return
    end

    if action == "wiretap_stop" then
        P.Monitoring[ply] = nil
        if ent.CurrentUser == ply then ent.CurrentUser = nil end
        notify(ply, "Прослушка выключена.")
        return
    end
end)

local function getCallForPlayer(ply)
    local dev = P.PlayerDevice[ply]
    if not IsValid(dev) or not isPhoneEntity(dev) then return nil, nil end
    if dev:GetLineState() ~= "call" then return nil, dev end
    local call = getCall(dev:GetCallID())
    if not call or not call.answered then return nil, dev end
    return call, dev
end

local function callIncludesPhone(call, phone)
    return call and IsValid(phone) and (call.from == phone or call.to == phone)
end

local function wiretapMatchesCall(tap, call)
    if not IsValid(tap) or not tap:GetActive() or not call then return false end
    local targetNumber = tap:GetTargetNumber()
    local exchangeID = tap:GetExchangeID()
    local matchNumber = targetNumber ~= "" and (call.from:GetPhoneNumber() == targetNumber or call.to:GetPhoneNumber() == targetNumber)
    local matchExchange = exchangeID ~= "" and (call.from:GetExchangeID() == exchangeID or call.to:GetExchangeID() == exchangeID)
    return matchNumber or matchExchange
end

local function sendPhoneText(recipients, speaker, call, msg, intercepted)
    if #recipients <= 0 then return end
    net.Start(NET_TEXT)
        net.WriteEntity(speaker)
        net.WriteUInt(call.id or 0, 16)
        net.WriteString(call.from:GetPhoneNumber())
        net.WriteString(call.to:GetPhoneNumber())
        net.WriteString(msg)
        net.WriteBool(intercepted and true or false)
    net.Send(recipients)
end

hook.Add("PlayerSay", "GRM_Phone_LineTextChat", function(ply, text)
    if not IsValid(ply) then return end
    text = string.Trim(tostring(text or ""))
    if text == "" then return end

    -- Команды не перехватываем.
    local first = string.sub(text, 1, 1)
    if first == "/" or first == "!" then return end

    local call, dev = getCallForPlayer(ply)
    if not call then return end

    local recipients = {}
    local tapped = {}
    for _, target in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
        if target ~= ply then
            local tCall, tDev = getCallForPlayer(target)
            if tCall and tCall.id == call.id and callIncludesPhone(call, tDev) then
                recipients[#recipients + 1] = target
            end
            local tap = P.Monitoring[target]
            if IsValid(tap) and wiretapMatchesCall(tap, call) then
                tapped[#tapped + 1] = target
            end
        end
    end

    sendPhoneText(recipients, ply, call, text, false)
    sendPhoneText(tapped, ply, call, text, true)

    -- Отправителю тоже показываем, что сообщение ушло именно в телефонную линию.
    sendPhoneText({ ply }, ply, call, text, false)

    recordLine("PHONE TEXT #" .. call.id .. " " .. ply:Nick() .. "(" .. ply:SteamID() .. ") " .. call.from:GetPhoneNumber() .. "<->" .. call.to:GetPhoneNumber() .. ": " .. text)

    if #tapped > 0 then
        recordLine("WIRETAP TEXT COPY #" .. call.id .. " tapped_listeners=" .. #tapped .. " msg=" .. text)
    end

    return ""
end)

-- Ring timeout / distance cleanup.
timer.Create("GRM_Phone_CallThink", 1, 0, function()
    local now = CurTime()
    for id, call in pairs(P.Calls) do
        if not IsValid(call.from) or not IsValid(call.to) then
            -- Код 88.1: энтити погибла в разговоре — НЕ просто трём запись,
            -- а возвращаем выживший телефон в idle (иначе «линия занята» навсегда).
            for _, ph in ipairs({ call.from, call.to }) do
                if IsValid(ph) and ph:GetCallID() == id then
                    setPhoneState(ph, "idle", 0, NULL)
                    local cu = IsValid(ph) and ph.CurrentUser or nil
                    if IsValid(cu) then notify(cu, "Линия разъединена (телефон собеседника удалён).", true) end
                    ph.CurrentUser = nil
                    emit(ph, "Hangup")
                end
            end
            recordLine("CALL DROP #" .. tostring(id) .. " reason=dead_entity")
            P.Calls[id] = nil
        elseif not call.answered and now - call.started > (cfg().RingTimeout or 35) then
            endCall(call, "timeout")
        elseif call.answered then
            -- Код 88.1 («чат закрыт»): обе трубки брошены >3с — звонок-призрак.
            -- Пока звонок жив, чат держащего трубку уходит в линию; если из
            -- линии все ушли, это молчаливый капкан для собеседника.
            local holdA = IsValid(call.from) and IsValid(call.from.CurrentUser) and canUsePhone(call.from.CurrentUser, call.from)
            local holdB = IsValid(call.to) and IsValid(call.to.CurrentUser) and canUsePhone(call.to.CurrentUser, call.to)
            if holdA or holdB then
                call.aloneSince = nil
            else
                call.aloneSince = call.aloneSince or now
                if now - call.aloneSince >= 3 then
                    endCall(call, "abandoned")
                end
            end
        end
    end

    -- Код 88.1: самолечение «застрявших» линий — состояние вызова без записи звонка.
    for _, phone in ipairs(allPhones()) do
        if IsValid(phone) then
            local st = phone:GetLineState()
            if st ~= "idle" and not getCall(phone:GetCallID()) then
                setPhoneState(phone, "idle", 0, NULL)
                phone.CurrentUser = nil
                recordLine("LINE HEAL " .. phone:GetPhoneNumber() .. " state=" .. tostring(st))
            end
        end
    end

    for ply, ent in pairs(P.PlayerDevice) do
        if not IsValid(ply) or not IsValid(ent) or not canUsePhone(ply, ent) then detachUser(ply) end
    end

    for ply, ent in pairs(P.Monitoring) do
        if not IsValid(ply) or not IsValid(ent) or not ent:GetActive() or not canUsePhone(ply, ent) then P.Monitoring[ply] = nil end
    end
end)

hook.Add("PlayerDisconnected", "GRM_Phone_Cleanup", function(ply)
    -- Код 88.1 (репорт «чат закрыт»): отключившийся в разговоре НЕ должен
    -- оставлять вечный звонок — иначе второй абонент продолжает писать
    -- в пустую трубку (его чат глушится ретранслятором) до собственного hangup.
    local dev = P.PlayerDevice[ply]
    if IsValid(dev) and isPhoneEntity(dev) then
        local call = getCall(dev:GetCallID())
        if call then
            -- других держателей трубки запоминаем ДО endCall (он обнуляет CurrentUser)
            local others = {}
            for _, ph in ipairs({ call.from, call.to }) do
                local other = IsValid(ph) and ph.CurrentUser or nil
                if IsValid(other) and other ~= ply then others[#others + 1] = other end
            end
            endCall(call, "disconnect")
            for _, other in ipairs(others) do
                notify(other, "Собеседник отключился — линия разъединена.", true)
            end
        end
    end
    detachUser(ply)
end)

-- ============================================================
-- VOICE INTEGRATION
-- ============================================================

local function localVoice(listener, speaker)
    return listener:GetPos():DistToSqr(speaker:GetPos()) <= (cfg().LocalVoiceRadius or 355) ^ 2
end

local function radioVoice(listener, speaker)
    if not RadioFrequencies then return false end
    local sk = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(speaker)) or speaker:SteamID64()
    local lk = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(listener)) or listener:SteamID64()
    local sf = RadioFrequencies[sk]
    local lf = RadioFrequencies[lk]
    if not (sf and lf and sf == lf) then return false end
    -- RadioNet (Код 85): частота ловится только в покрытии сети
    -- (стойка+антенны); вне сети — прямая дальность рации
    local rn = GRM and GRM.RadioNet
    if rn and rn.RadioPairOK and not rn.RadioPairOK(speaker, listener) then return false end
    return true
end

local function phoneVoice(listener, speaker)
    local speakerDev = P.PlayerDevice[speaker]
    local listenerDev = P.PlayerDevice[listener]

    if IsValid(speakerDev) and isPhoneEntity(speakerDev) and speakerDev:GetLineState() == "call" then
        local call = getCall(speakerDev:GetCallID())
        if call and call.answered then
            if IsValid(listenerDev) and isPhoneEntity(listenerDev) and listenerDev:GetCallID() == call.id then
                return true
            end
        end
    end

    -- Wiretap listener.
    local tap = P.Monitoring[listener]
    if IsValid(tap) and tap:GetActive() then
        local targetNumber = tap:GetTargetNumber()
        local exchangeID = tap:GetExchangeID()
        if IsValid(speakerDev) and isPhoneEntity(speakerDev) then
            local call = getCall(speakerDev:GetCallID())
            if call and call.answered then
                local matchNumber = targetNumber ~= "" and (call.from:GetPhoneNumber() == targetNumber or call.to:GetPhoneNumber() == targetNumber)
                local matchExchange = exchangeID ~= "" and (call.from:GetExchangeID() == exchangeID or call.to:GetExchangeID() == exchangeID)
                if matchNumber or matchExchange then return true end
            end
        end
    end
    return false
end

local function installVoiceHook()
    if cfg().RemoveKnownVoiceHooks then
        hook.Remove("PlayerCanHearPlayersVoice", "RadioVoiceChat")
        hook.Remove("PlayerCanHearPlayersVoice", "LocalVoiceChat")
    end

    hook.Add("PlayerCanHearPlayersVoice", "GRM_Phone_IntegratedVoice", function(listener, speaker)
        if not IsValid(listener) or not IsValid(speaker) then return false, false end
        if listener == speaker then return false, false end

        -- RadioNet (Код 85) решает ПЕРВЫМ: эфир/громкая связь/мегафон.
        -- Без явной консультации хуки PlayerCanHearPlayersVoice итера-
        -- рируются в случайном порядке pairs() и душат друг друга.
        local rn = GRM and GRM.RadioNet
        if rn and rn.VoiceRoute then
            local c, h = rn.VoiceRoute(listener, speaker)
            if c ~= nil then return c, h end
        end

        local canLocal = localVoice(listener, speaker)
        if canLocal then return true, true end
        if cfg().IntegrateRadioVoice and radioVoice(listener, speaker) then return true, false end
        if phoneVoice(listener, speaker) then return true, false end
        return false, false
    end)
end

installVoiceHook()
timer.Simple(2, installVoiceHook)

-- ============================================================
-- PERSISTENCE
-- ============================================================

local SAVE_DIR = "grm_phone"
local function savePath() return SAVE_DIR .. "/" .. string.lower(game.GetMap() or "unknown") .. ".json" end
local function ensureDir() if not file.Exists(SAVE_DIR, "DATA") then file.CreateDir(SAVE_DIR) end end

local function entRecord(ent)
    local class = ent:GetClass()
    local rec = { class = class, pos = ent:GetPos(), ang = ent:GetAngles() }
    if class == "grm_phone" or class == "grm_payphone" then
        rec.number = ent:GetPhoneNumber(); rec.name = ent:GetDisplayName(); rec.exchange = ent:GetExchangeID()
    elseif class == "grm_pbx_station" then
        rec.exchange = ent:GetExchangeID(); rec.active = ent:GetActive(); rec.maxLines = ent:GetMaxLines()
    elseif class == "grm_phone_terminal" then
        rec.name = ent:GetTerminalName()
    elseif class == "grm_phone_wiretap" then
        rec.target = ent:GetTargetNumber(); rec.exchange = ent:GetExchangeID(); rec.active = ent:GetActive()
    end
    return rec
end

local function vecToTable(v) return { x = v.x, y = v.y, z = v.z } end
local function angToTable(a) return { p = a.p, y = a.y, r = a.r } end
local function tableToVec(t) return Vector(t.x or 0, t.y or 0, t.z or 0) end
local function tableToAng(t) return Angle(t.p or 0, t.y or 0, t.r or 0) end

local function serializeRecord(rec)
    local out = table.Copy(rec)
    out.pos = vecToTable(rec.pos)
    out.ang = angToTable(rec.ang)
    return out
end

function P.SaveMapEntities(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then notify(ply, "Только superadmin.", true) return end
    ensureDir()
    local list = {}
    for _, class in ipairs({ "grm_phone", "grm_payphone", "grm_pbx_station", "grm_phone_wiretap", "grm_phone_terminal" }) do
        for _, ent in ipairs(ents.FindByClass(class)) do
            -- Купленное игроками оборудование сохраняется отдельной системой магазина,
            -- чтобы не было дублей после grm_phone_save.
            if not ent.GRMPhoneShopOwned then
                list[#list + 1] = serializeRecord(entRecord(ent))
            end
        end
    end
    file.Write(savePath(), util.TableToJSON(list, true))
    notify(ply, "Сохранено телефонного оборудования: " .. #list)
end

function P.LoadMapEntities(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then notify(ply, "Только superadmin.", true) return end
    if not file.Exists(savePath(), "DATA") then return end

    --[[ СНАЧАЛА ЧИТАЕМ, ПОТОМ СНОСИМ (находка аудита 31.08).

         Раньше телефоны удалялись ДО разбора файла. Если JSON повреждён
         (обрыв записи при падении сервера, полный диск), разбор возвращал
         nil, `or {}` подставлял пустоту — и восстанавливать было нечего.
         Вся телефонная сеть карты исчезала молча.

         Это был единственный загрузчик проекта без pcall: остальные
         одиннадцать обёрнуты и уводят битый файл в карантин. ]]
    local raw = file.Read(savePath(), "DATA") or ""
    local parsed, data = pcall(util.JSONToTable, raw)
    if not (parsed and istable(data)) then
        --[[ Битый файл НЕ затираем: уводим в карантин, иначе следующее
             сохранение запишет пустоту поверх и данные исчезнут
             окончательно. Имя с меткой времени, как в валюте и
             документах. ]]
        local quarantine = SAVE_DIR .. "/corrupt_" .. os.time() .. "_"
            .. string.lower(game.GetMap() or "unknown") .. ".json"
        if raw ~= "" then file.Write(quarantine, raw) end
        ErrorNoHalt("[GRM Phone] Файл телефонов повреждён, карантин: " .. quarantine .. "\n")
        notify(ply, "Файл телефонов повреждён. Ничего не удалено, копия в " .. quarantine, true)
        return
    end

    -- Данные целы — только теперь убираем старое.
    for _, class in ipairs({ "grm_phone", "grm_payphone", "grm_pbx_station", "grm_phone_wiretap", "grm_phone_terminal" }) do
        for _, ent in ipairs(ents.FindByClass(class)) do ent:Remove() end
    end

    local count = 0
    for _, rec in ipairs(data) do
        local ent = ents.Create(rec.class)
        if IsValid(ent) then
            ent:SetPos(tableToVec(rec.pos or {})); ent:SetAngles(tableToAng(rec.ang or {})); ent:Spawn(); ent:Activate()
            if GRM.PropProtect and GRM.PropProtect.MarkServerEntity then GRM.PropProtect.MarkServerEntity(ent) end
            if rec.class == "grm_phone" or rec.class == "grm_payphone" then
                ent:SetPhoneNumber(rec.number or P.GenerateNumber()); ent:SetDisplayName(rec.name or (rec.class == "grm_payphone" and "Таксофон" or "Телефон")); ent:SetExchangeID(rec.exchange or "main")
                updatePhoneVisual(ent, "idle")
            elseif rec.class == "grm_pbx_station" then
                ent:SetExchangeID(rec.exchange or "main"); ent:SetActive(rec.active ~= false); ent:SetMaxLines(tonumber(rec.maxLines) or cfg().PBXDefaultMaxLines or 60)
            elseif rec.class == "grm_phone_terminal" then
                ent:SetTerminalName(rec.name or "Мониторинг связи")
            elseif rec.class == "grm_phone_wiretap" then
                ent:SetTargetNumber(rec.target or ""); ent:SetExchangeID(rec.exchange or "main"); ent:SetActive(rec.active == true)
            end
            count = count + 1
        end
    end
    notify(ply, "Загружено телефонного оборудования: " .. count)
end

concommand.Add("grm_phone_save", function(ply) P.SaveMapEntities(ply) end)
concommand.Add("grm_phone_load", function(ply) P.LoadMapEntities(ply) end)

if GRM.Boot and GRM.Boot.Task then
    GRM.Boot.Task("phone.map", "normal", function() P.LoadMapEntities(nil) end, { label = "Телефония: оборудование карты" })
else
hook.Add("InitPostEntity", "GRM_Phone_LoadMap", function()
    timer.Simple(1, function() P.LoadMapEntities(nil) end)
end)
end

hook.Add("PostCleanupMap", "GRM_Phone_Cleanup", function()
    timer.Simple(0.5, function() P.LoadMapEntities(nil) end)
end)

-- ============================================================
-- ADMIN REMOVE TOOL / COMMANDS
-- ============================================================

local PHONE_CLASSES = {
    ["grm_phone"] = true,
    ["grm_payphone"] = true,
    ["grm_pbx_station"] = true,
    ["grm_phone_wiretap"] = true,
    ["grm_phone_terminal"] = true,
}

local function isPhoneSystemEntity(ent)
    return IsValid(ent) and PHONE_CLASSES[ent:GetClass()] == true
end

local function findAimedPhoneEntity(ply, range)
    if not IsValid(ply) then return nil end
    local tr = util.TraceLine({
        start = ply:EyePos(),
        endpos = ply:EyePos() + ply:GetAimVector() * (range or 350),
        filter = ply,
        mask = MASK_ALL,
    })
    if isPhoneSystemEntity(tr.Entity) then
        return tr.Entity
    end

    -- Небольшой fallback: если луч попал не точно в entity, ищем ближайшее оборудование около hitpos.
    local hitPos = tr.HitPos or (ply:EyePos() + ply:GetAimVector() * (range or 350))
    local best, bestDist
    for class in pairs(PHONE_CLASSES) do
        for _, ent in ipairs(ents.FindByClass(class)) do
            if IsValid(ent) then
                local d = ent:GetPos():DistToSqr(hitPos)
                if d <= 96 * 96 and (not bestDist or d < bestDist) then
                    best = ent
                    bestDist = d
                end
            end
        end
    end
    return best
end

local function removeFromShopStorage(ent)
    if not IsValid(ent) then return false end
    if not ent.GRMPhoneShopID then return false end
    local id = ent.GRMPhoneShopID
    if GRM and GRM.Phone and GRM.Phone.Shop and GRM.Phone.Shop.Owned then
        GRM.Phone.Shop.Owned[id] = nil
        if GRM.Phone.Shop.SaveOwned then
            GRM.Phone.Shop.SaveOwned()
        elseif GRM.Phone.Shop.Save then
            GRM.Phone.Shop.Save()
        end
    end
    return true
end

local function cleanupCallsForRemovedEntity(ent)
    if not IsValid(ent) then return end
    if isPhoneEntity(ent) then
        local call = getCall(ent:GetCallID())
        if call then
            endCall(call, "admin_remove")
        end
    end
    for ply, dev in pairs(P.PlayerDevice or {}) do
        if dev == ent then
            detachUser(ply)
        end
    end
    for ply, tap in pairs(P.Monitoring or {}) do
        if tap == ent then
            P.Monitoring[ply] = nil
        end
    end
end

function P.AdminRemoveEntity(ply, ent)
    if IsValid(ply) and not ply:IsAdmin() and not ply:IsSuperAdmin() then
        notify(ply, "Только admin/superadmin может удалять телефонное оборудование.", true)
        return false
    end

    if not isPhoneSystemEntity(ent) then
        notify(ply, "Наведитесь на телефон, таксофон, АТС, прослушку или компьютер связи.", true)
        return false
    end

    local class = ent:GetClass()
    local info = class
    if isPhoneEntity(ent) then
        info = class .. " №" .. ent:GetPhoneNumber()
    elseif class == "grm_pbx_station" then
        info = "АТС " .. ent:GetExchangeID()
    elseif class == "grm_phone_wiretap" then
        info = "Прослушка " .. ent:GetTargetNumber() .. " / " .. ent:GetExchangeID()
    elseif class == "grm_phone_terminal" then
        info = ent:GetTerminalName()
    end

    cleanupCallsForRemovedEntity(ent)
    local wasShopOwned = removeFromShopStorage(ent)
    ent:Remove()

    -- Важно: после удаления сразу перезаписываем карту. Так случайно сохранённый телефон
    -- исчезнет из data/grm_phone/<map>.json. Купленное игроком оборудование удаляется
    -- из player_equipment.json через removeFromShopStorage().
    timer.Simple(0, function()
        P.SaveMapEntities(nil)
    end)

    local msg = "Удалено телефонное оборудование: " .. tostring(info)
    if wasShopOwned then msg = msg .. " (также удалено из базы покупок игрока)" end
    notify(ply, msg, false)
    print("[GRM Phone] " .. msg)
    return true
end

concommand.Add("grm_phone_remove_look", function(ply)
    if not IsValid(ply) then return end
    local ent = findAimedPhoneEntity(ply, 450)
    P.AdminRemoveEntity(ply, ent)
end)

concommand.Add("grm_phone_admin_remove", function(ply)
    if not IsValid(ply) then return end
    local ent = findAimedPhoneEntity(ply, 450)
    P.AdminRemoveEntity(ply, ent)
end)

hook.Add("PlayerSay", "GRM_Phone_AdminRemoveChat", function(ply, text)
    local cmd = string.lower(string.Trim(text or ""))
    if cmd == "/phone_admin_remove" or cmd == "!phone_admin_remove" or cmd == "/removephone_admin" or cmd == "!removephone_admin" then
        local ent = findAimedPhoneEntity(ply, 450)
        P.AdminRemoveEntity(ply, ent)
        return ""
    end
end)

print("[GRM Phone] Server loaded")
