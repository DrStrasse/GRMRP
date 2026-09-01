--[[--------------------------------------------------------------------
    GRM Fire Dispatch v1.0.0 — вызовы пожарной службы с принятием

    Заказ владельца (18.08): «нужно настроить, чтобы пожарным нормально
    приходило уведомление о пожаре с необходимостью принятия вызова».

    Как работает:
      • Возгорание (или вызов 911 категории «Пожар») создаёт ВЫЗОВ.
      • Всем пожарным — бойцам (FightPro), диспетчерам и сотрудникам
        фракций из /grm_fire_notify — прилетает карточка на экран:
        адрес-ориентир, источник, расстояние, кнопки ПРИНЯТЬ / ОТКАЗАТЬСЯ
        и обратный отсчёт. Звук сирены, дубль в чат.
      • Принявший получает метку на карте и HUD-стрелку с расстоянием,
        остальным приходит «вызов принял такой-то».
      • Если за 45 секунд никто не принял — повторное оповещение (до 3 раз),
        отдельно уведомляются диспетчеры и суперадмины.
      • Тушение закрывает вызов автоматически; всё пишется в журнал вызовов
        (виден в компьютере пожарной станции).

    Команды: /fire_calls (список активных вызовов), консоль grm_fire_calls.
    Файл журнала: data/grm_fire/calls.json
----------------------------------------------------------------------]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Fire = GRM.Fire or {}
local F = GRM.Fire
F.Dispatch = F.Dispatch or {}
local D = F.Dispatch
D.Version = "1.0.0"

D.ReminderDelay = 45      -- через сколько секунд напомнить, если никто не принял
D.MaxReminders  = 3
D.CallTTL       = 1800    -- вызов живёт максимум 30 минут
D.RecallGuard   = 60      -- сколько секунд после закрытия не создавать новый вызов рядом
D.CardTimeout   = 60      -- сколько секунд карточка висит у пожарного

local NET_NEW    = "GRM_FireCall_New"
local NET_ACT    = "GRM_FireCall_Act"
local NET_STATE  = "GRM_FireCall_State"
local NET_LIST   = "GRM_FireCall_List"
local NET_LISTRQ = "GRM_FireCall_ListReq"

local CALLS_FILE = "grm_fire/calls.json"

-----------------------------------------------------------------------
-- ОБЩЕЕ
-----------------------------------------------------------------------
D.Calls = D.Calls or {}      -- активные и недавние вызовы (id -> запись)

function D.SourceName(source)
    local names = {
        fire = "Возгорание",
        stove = "Возгорание на плите",
        random = "Случайное возгорание",
        arson = "Поджог",
        call911 = "Вызов 911",
        vehicle = "Горит транспорт",
        electric = "Замыкание проводки",
    }
    return names[tostring(source or "")] or "Возгорание"
end

-- Сирена вызова — через звуковой слой GRM (прекэш + фолбэк).
if GRM.Sound and GRM.Sound.Register then
    GRM.Sound.Register("npc/scanner/scanner_siren2.wav", "buttons/button17.wav")
end

-----------------------------------------------------------------------
-- СЕРВЕР
-----------------------------------------------------------------------
if SERVER then
    util.AddNetworkString(NET_NEW)
    util.AddNetworkString(NET_ACT)
    util.AddNetworkString(NET_STATE)
    util.AddNetworkString(NET_LIST)
    util.AddNetworkString(NET_LISTRQ)

    local function jsonT(txt)
        local ok, t = pcall(util.JSONToTable, txt, false, true)
        return (ok and istable(t)) and t or nil
    end

    local function ensureDir()
        if not file.IsDir("grm_fire", "DATA") then file.CreateDir("grm_fire") end
    end

    function D.SaveCalls()
        ensureDir()
        local rows = {}
        for _, call in pairs(D.Calls) do
            rows[#rows + 1] = {
                id = call.id, source = call.source, status = call.status,
                created = call.created, acceptedAt = call.acceptedAt, closedAt = call.closedAt,
                acceptedName = call.acceptedName, closedReason = call.closedReason,
                x = math.floor(call.origin.x), y = math.floor(call.origin.y), z = math.floor(call.origin.z),
                area = call.area, callerName = call.callerName, text = call.text,
            }
        end
        table.sort(rows, function(a, b) return (a.created or 0) > (b.created or 0) end)
        while #rows > 200 do table.remove(rows) end
        local ok, encoded = pcall(util.TableToJSON, { version = 1, calls = rows }, true)
        if ok and isstring(encoded) then file.Write(CALLS_FILE, encoded) end
        return rows
    end

    function D.LoadCalls()
        local raw = file.Read(CALLS_FILE, "DATA")
        local t = raw and jsonT(raw) or nil
        D.History = (istable(t) and istable(t.calls)) and t.calls or {}
        return D.History
    end

    -- Журнал вызовов для компьютера пожарной станции.
    function D.LogRows(limit)
        limit = tonumber(limit) or 100
        local rows = {}
        for _, call in pairs(D.Calls) do
            rows[#rows + 1] = {
                id = call.id, text = call.text or D.SourceName(call.source),
                caller = call.callerName or "Автоматическая система",
                status = call.status, assigned = call.acceptedName or "",
                created = call.created, x = math.floor(call.origin.x),
                y = math.floor(call.origin.y), z = math.floor(call.origin.z),
                area = call.area,
            }
        end
        for _, row in ipairs(D.History or {}) do
            local dup = false
            for _, r in ipairs(rows) do if r.id == row.id then dup = true break end end
            if not dup then
                rows[#rows + 1] = {
                    id = row.id, text = row.text or D.SourceName(row.source),
                    caller = row.callerName or "Автоматическая система",
                    status = row.status, assigned = row.acceptedName or "",
                    created = row.created, x = row.x, y = row.y, z = row.z, area = row.area,
                }
            end
        end
        table.sort(rows, function(a, b) return (a.created or 0) > (b.created or 0) end)
        while #rows > limit do table.remove(rows) end
        return rows
    end

    -- Кто должен получать вызовы: бойцы, диспетчеры, фракции из /grm_fire_notify,
    -- плюс суперадмины (им — как контроль).
    function D.Responders()
        local out, seen = {}, {}
        local players = (GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()

        local notifyFactions = (F.NotifyData and istable(F.NotifyData.factions)) and F.NotifyData.factions or {}

        for _, ply in ipairs(players) do
            if IsValid(ply) and not seen[ply] then
                local take = false
                if isfunction(F.CanFightPro) and F.CanFightPro(ply) == true then take = true end
                if not take and isfunction(F.CanDispatch) and F.CanDispatch(ply) == true then take = true end
                if not take then
                    local fac = ply:GetNWString("GRM_Faction", "")
                    if fac ~= "" and notifyFactions[fac] == true then take = true end
                end
                if not take and ply:IsSuperAdmin() then take = true end
                if take then
                    seen[ply] = true
                    out[#out + 1] = ply
                end
            end
        end
        return out
    end

    local function areaName(pos)
        -- Ориентир: ближайшая именованная точка карты, если модуль карты есть.
        if GRM.Minimap and istable(GRM.Minimap.Data) and istable(GRM.Minimap.Data.points) then
            local best, bestD
            for _, p in ipairs(GRM.Minimap.Data.points) do
                if istable(p) and istable(p.pos) and not p.temp then
                    local d = pos:DistToSqr(Vector(p.pos.x, p.pos.y, p.pos.z))
                    if not bestD or d < bestD then best, bestD = p, d end
                end
            end
            if best and bestD and bestD <= (4000 * 4000) then
                return tostring(best.name or "")
            end
        end
        return ""
    end

    local function pushCall(call, ply)
        net.Start(NET_NEW)
            net.WriteUInt(call.id, 16)
            net.WriteString(call.source or "fire")
            net.WriteString(call.text or "")
            net.WriteString(call.area or "")
            net.WriteString(call.callerName or "")
            net.WriteVector(call.origin)
            net.WriteUInt(math.max(0, math.floor(D.CardTimeout)), 16)
        if IsValid(ply) then net.Send(ply) else
            local list = D.Responders()
            if #list == 0 then return end
            net.Send(list)
        end
    end

    local function broadcastState(call)
        local targets = D.Responders()
        if #targets == 0 then return end
        net.Start(NET_STATE)
            net.WriteUInt(call.id, 16)
            net.WriteString(call.status)
            net.WriteString(call.acceptedName or "")
        net.Send(targets)
    end

    local function tellResponders(text, r, g, b)
        for _, ply in ipairs(D.Responders()) do
            if GRM.Notify then GRM.Notify(ply, text, r or 255, g or 150, b or 80) end
            ply:ChatPrint("[Пожарная служба] " .. tostring(text))
        end
    end

    --[[ Создать вызов. origin — место, source — причина, extra:
         { callerName, text } для вызовов от игроков (911). ]]
    function D.CreateCall(origin, source, extra)
        if not isvector(origin) then return nil end
        extra = istable(extra) and extra or {}

        --[[ Не плодим вызовы на один и тот же очаг. Второй страховкой —
             ТОЛЬКО ЧТО ЗАКРЫТЫЙ вызов рядом: во время тушения очаг гаснет и
             вспыхивает кусками, и раньше каждая вспышка давала пожарным
             новый вызов «на тот же дом». Минуту после закрытия новый вызов
             в этом месте не создаём. ]]
        for _, call in pairs(D.Calls) do
            if call.origin:DistToSqr(origin) <= 600 * 600 then
                if call.status ~= "closed" then return call end
                if (CurTime() - (call.closedCT or 0)) < (D.RecallGuard or 60) then return call end
            end
        end

        D._nextID = (D._nextID or 0) + 1
        local call = {
            id = D._nextID,
            origin = Vector(origin.x, origin.y, origin.z),
            source = tostring(source or "fire"),
            area = areaName(origin),
            text = tostring(extra.text or ""),
            callerName = tostring(extra.callerName or "Автоматическая система"),
            status = "pending",
            created = os.time(),
            createdAt = CurTime(),
            reminders = 0,
            declined = {},
        }
        if call.text == "" then
            call.text = D.SourceName(call.source) .. (call.area ~= "" and (" · " .. call.area) or "")
        end
        D.Calls[call.id] = call

        pushCall(call)
        tellResponders("НОВЫЙ ВЫЗОВ #" .. call.id .. ": " .. call.text .. ". Требуется принятие.", 255, 130, 70)
        if GRM.Sound and GRM.Sound.Emit then
            for _, ply in ipairs(D.Responders()) do
                GRM.Sound.Emit(ply, "npc/scanner/scanner_siren2.wav", 70, 100, 0.55)
            end
        end
        D.SaveCalls()
        return call
    end

    function D.AcceptCall(ply, id)
        local call = D.Calls[tonumber(id) or 0]
        if not call or call.status == "closed" then return false, "Вызов уже закрыт" end
        if call.status == "accepted" then
            return false, "Вызов уже принял " .. tostring(call.acceptedName or "другой расчёт")
        end
        if not (IsValid(ply) and (ply:IsSuperAdmin()
            or (isfunction(F.CanFightPro) and F.CanFightPro(ply))
            or (isfunction(F.CanDispatch) and F.CanDispatch(ply)))) then
            return false, "Вы не в пожарном расчёте"
        end

        call.status = "accepted"
        call.acceptedAt = os.time()
        call.acceptedName = (GRM.Factions and GRM.Factions.PlayerDisplayName and ply:GetNWString("GRM_RPName", "") ~= "")
            and ply:GetNWString("GRM_RPName", "") or ply:Nick()
        call.acceptedBy = ply

        -- Метка на карте для расчёта и HUD-стрелка принявшему.
        if GRM.Minimap and GRM.Minimap.AddTempPoint then
            call.markerID = GRM.Minimap.AddTempPoint("ВЫЗОВ #" .. call.id .. " · ПОЖАР", call.origin, 900)
        end

        broadcastState(call)
        tellResponders("Вызов #" .. call.id .. " принял " .. call.acceptedName .. ".", 90, 200, 130)
        if GRM.Audit and GRM.Audit.Write then
            GRM.Audit.Write("fire", "call.accept", ply, { id = call.id, area = call.area }, {})
        end
        D.SaveCalls()
        return true, "Вызов принят"
    end

    function D.DeclineCall(ply, id)
        local call = D.Calls[tonumber(id) or 0]
        if not call or not IsValid(ply) then return false end
        call.declined[ply:SteamID64() or tostring(ply)] = true
        return true, "Вызов отклонён"
    end

    function D.CloseCall(id, reason)
        local call = D.Calls[tonumber(id) or 0]
        if not call or call.status == "closed" then return false end
        call.status = "closed"
        call.closedAt = os.time()
        call.closedCT = CurTime()
        call.closedReason = tostring(reason or "")
        if call.markerID and GRM.Minimap and GRM.Minimap.RemoveTempPoint then
            GRM.Minimap.RemoveTempPoint("ВЫЗОВ #" .. call.id .. " · ПОЖАР")
        end
        broadcastState(call)
        tellResponders("Вызов #" .. call.id .. " закрыт" ..
            (call.closedReason ~= "" and (": " .. call.closedReason) or "") .. ".", 120, 190, 240)
        D.SaveCalls()
        return true
    end

    -- Очаг открылся → вызов.
    hook.Add("GRM_FireIncidentOpened", "GRM_FireDispatch_Open", function(inc)
        if not istable(inc) or not isvector(inc.origin) then return end
        local call = D.CreateCall(inc.origin, inc.source or "fire", {})
        if call then
            call.incidentID = inc.id
            inc.callID = call.id
        end
    end)

    -- Пожар потушен → закрываем вызов.
    hook.Add("GRM_FireExtinguished", "GRM_FireDispatch_Close", function(pos, inc)
        local id = istable(inc) and inc.callID or nil
        if id then D.CloseCall(id, "пожар потушен") return end
        if not isvector(pos) then return end
        for _, call in pairs(D.Calls) do
            if call.status ~= "closed" and call.origin:DistToSqr(pos) <= 900 * 900 then
                D.CloseCall(call.id, "пожар потушен")
            end
        end
    end)

    -- Вызов 911 категории «Пожар» → тот же диспетчерский вызов.
    hook.Add("GRM_911_Call", "GRM_FireDispatch_911", function(ply, rec)
        if not istable(rec) or tostring(rec.category or "") ~= "fire" then return end
        local pos = istable(rec.pos) and Vector(rec.pos.x, rec.pos.y, rec.pos.z) or (IsValid(ply) and ply:GetPos())
        if not isvector(pos) then return end
        D.CreateCall(pos, "call911", {
            callerName = tostring(rec.callerName or "Гражданин"),
            text = "Вызов 911: " .. tostring(rec.text or "сообщение о пожаре"),
        })
    end)

    net.Receive(NET_ACT, function(_, ply)
        if not IsValid(ply) then return end
        if GRM.Net and GRM.Net.Guard and not GRM.Net.Guard(ply, "fire.call.act", { rate = 0.4, burst = 4 }, {}) then return end
        local id = net.ReadUInt(16)
        local op = net.ReadString()

        local ok, msg
        if op == "accept" then ok, msg = D.AcceptCall(ply, id)
        elseif op == "decline" then ok, msg = D.DeclineCall(ply, id)
        elseif op == "close" then
            if ply:IsSuperAdmin() or (isfunction(F.CanDispatch) and F.CanDispatch(ply)) then
                ok = D.CloseCall(id, "закрыт диспетчером " .. ply:Nick())
                msg = ok and "Вызов закрыт" or "Вызов уже закрыт"
            else
                ok, msg = false, "Закрывать вызовы может диспетчер"
            end
        else
            return
        end

        if GRM.Notify and msg then
            GRM.Notify(ply, tostring(msg), ok and 100 or 255, ok and 220 or 150, ok and 130 or 90)
        end
    end)

    net.Receive(NET_LISTRQ, function(_, ply)
        if not IsValid(ply) then return end
        local allowed = ply:IsSuperAdmin()
            or (isfunction(F.CanFightPro) and F.CanFightPro(ply))
            or (isfunction(F.CanDispatch) and F.CanDispatch(ply))
        if not allowed then
            if GRM.Notify then GRM.Notify(ply, "Список вызовов доступен пожарному расчёту.", 255, 140, 100) end
            return
        end
        net.Start(NET_LIST)
            net.WriteTable(D.LogRows(60))
        net.Send(ply)
    end)

    -- Напоминания и уборка просроченных вызовов.
    timer.Create("GRM_FireDispatch_Tick", 5, 0, function()
        if not next(D.Calls) then return end
        local now = CurTime()
        for id, call in pairs(D.Calls) do
            if call.status == "pending" then
                local waited = now - (call.createdAt or now)
                local due = (call.reminders + 1) * D.ReminderDelay
                if waited >= due and call.reminders < D.MaxReminders then
                    call.reminders = call.reminders + 1
                    pushCall(call)
                    tellResponders(("Вызов #%d не принят (%d с): %s"):format(call.id, math.floor(waited), call.text), 255, 110, 70)
                end
            end
            if call.status == "closed" and (now - (call.createdAt or now)) > 300 then
                D.Calls[id] = nil
            elseif (now - (call.createdAt or now)) > D.CallTTL then
                D.CloseCall(id, "истёк срок вызова")
            end
        end
    end)

    local function chatCalls(ply, low)
        if low == "/fire_calls" or low == "!fire_calls" or low == "/вызовы_пожар" then
            net.Start(NET_LIST)
                net.WriteTable(D.LogRows(60))
            net.Send(ply)
            return true
        end
        return false
    end

    hook.Add("PlayerSay", "GRM_FireDispatch_Chat", function(ply, text)
        if chatCalls(ply, string.lower(string.Trim(text or ""))) then return "" end
    end)
    hook.Add("PlayerSayTransform", "GRM_FireDispatch_ChatTr", function(ply, pack)
        if not istable(pack) or not isstring(pack[1]) then return end
        if chatCalls(ply, string.lower(string.Trim(pack[1]))) then
            pack[1] = ""
            pack.SkipPlayerSay = true
        end
    end)

    if GRM.Boot and GRM.Boot.OnMapStart then
        GRM.Boot.OnMapStart("GRM_FireDispatch_Load", "normal", function() D.LoadCalls() end)
    else
        hook.Add("InitPostEntity", "GRM_FireDispatch_Load", function() D.LoadCalls() end)
    end
end

-----------------------------------------------------------------------
-- КЛИЕНТ
-----------------------------------------------------------------------
if CLIENT then
    surface.CreateFont("GRMFireCall_Title", { font = "Roboto", size = 22, weight = 800, extended = true })
    surface.CreateFont("GRMFireCall_Body",  { font = "Roboto", size = 15, weight = 600, extended = true })
    surface.CreateFont("GRMFireCall_Small", { font = "Roboto", size = 12, weight = 500, extended = true })

    local C = {
        bg    = Color(18, 14, 14, 246),
        panel = Color(30, 22, 20, 250),
        head  = Color(180, 60, 35),
        text  = Color(240, 235, 232),
        dim   = Color(180, 170, 165),
        green = Color(60, 180, 105),
        red   = Color(200, 65, 60),
        gold  = Color(245, 190, 70),
    }

    D.ActiveCard = D.ActiveCard or nil
    D.MyCall = D.MyCall or nil     -- принятый вызов: { id, origin }

    local function closeCard()
        if IsValid(D.ActiveCard) then D.ActiveCard:Remove() end
        D.ActiveCard = nil
    end

    local function openCard(id, source, text, area, caller, origin, timeout)
        closeCard()

        local w, h = 420, 210
        local pnl = vgui.Create("DPanel")
        D.ActiveCard = pnl
        pnl:SetSize(w, h)
        pnl:SetPos(ScrW() - w - 24, 120)
        pnl.expires = SysTime() + math.max(10, timeout)
        pnl.Paint = function(self, pw, ph)
            draw.RoundedBox(8, 0, 0, pw, ph, C.bg)
            draw.RoundedBoxEx(8, 0, 0, pw, 38, C.head, true, true, false, false)
            draw.SimpleText("ВЫЗОВ #" .. id .. " · ПОЖАР", "GRMFireCall_Title", 14, 19, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

            local left = math.max(0, math.ceil(self.expires - SysTime()))
            draw.SimpleText(left .. " с", "GRMFireCall_Body", pw - 14, 19, C.gold, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

            draw.SimpleText(text ~= "" and text or D.SourceName(source), "GRMFireCall_Body", 14, 52, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            if area ~= "" then
                draw.SimpleText("Район: " .. area, "GRMFireCall_Small", 14, 76, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            end
            draw.SimpleText("Источник: " .. D.SourceName(source), "GRMFireCall_Small", 14, 94, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            if caller ~= "" then
                draw.SimpleText("Заявитель: " .. caller, "GRMFireCall_Small", 14, 112, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            end

            local lp = LocalPlayer()
            if IsValid(lp) and isvector(origin) then
                local dist = math.floor(lp:GetPos():Distance(origin) / 52.49)
                draw.SimpleText("Расстояние: ~" .. dist .. " м", "GRMFireCall_Small", pw - 14, 112, C.gold, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
            end
        end

        local function mk(label, col, x, fn)
            local b = vgui.Create("DButton", pnl)
            b:SetText("")
            b:SetPos(x, h - 52)
            b:SetSize(190, 38)
            b.Paint = function(self, bw, bh)
                local c = self:IsHovered() and Color(math.min(255, col.r + 25), math.min(255, col.g + 25), math.min(255, col.b + 25)) or col
                draw.RoundedBox(6, 0, 0, bw, bh, c)
                draw.SimpleText(label, "GRMFireCall_Body", bw / 2, bh / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            b.DoClick = fn
            return b
        end

        local function act(op)
            net.Start(NET_ACT)
                net.WriteUInt(id, 16)
                net.WriteString(op)
            net.SendToServer()
            surface.PlaySound(op == "accept" and "buttons/button14.wav" or "buttons/button10.wav")
            closeCard()
        end

        mk("ПРИНЯТЬ ВЫЗОВ", C.green, 14, function()
            D.MyCall = { id = id, origin = origin, text = text ~= "" and text or D.SourceName(source) }
            act("accept")
        end)
        mk("ОТКАЗАТЬСЯ", C.red, 216, function() act("decline") end)

        pnl.Think = function(self)
            if SysTime() >= self.expires then closeCard() end
        end

        surface.PlaySound("npc/scanner/scanner_siren2.wav")
    end

    net.Receive(NET_NEW, function()
        local id      = net.ReadUInt(16)
        local source  = net.ReadString()
        local text    = net.ReadString()
        local area    = net.ReadString()
        local caller  = net.ReadString()
        local origin  = net.ReadVector()
        local timeout = net.ReadUInt(16)
        openCard(id, source, text, area, caller, origin, timeout)
    end)

    net.Receive(NET_STATE, function()
        local id     = net.ReadUInt(16)
        local status = net.ReadString()
        local who    = net.ReadString()

        if IsValid(D.ActiveCard) and status ~= "pending" then closeCard() end
        if D.MyCall and D.MyCall.id == id and status == "closed" then D.MyCall = nil end
        if status == "accepted" and who ~= "" then
            chat.AddText(C.head, "[Пожарная служба] ", C.text, "Вызов #" .. id .. " принял ", C.gold, who)
        end
    end)

    -- HUD-подсказка принявшему: куда ехать и сколько осталось.
    hook.Add("HUDPaint", "GRM_FireDispatch_HUD", function()
        local call = D.MyCall
        if not call or not isvector(call.origin) then return end
        local lp = LocalPlayer()
        if not IsValid(lp) then return end

        local screen = call.origin:ToScreen()
        local dist = math.floor(lp:GetPos():Distance(call.origin) / 52.49)
        local x = math.Clamp(screen.x, 90, ScrW() - 90)
        local y = math.Clamp(screen.y, 80, ScrH() - 140)

        draw.RoundedBox(8, x - 88, y - 26, 176, 52, Color(24, 14, 12, 225))
        draw.SimpleText("ВЫЗОВ #" .. call.id, "GRMFireCall_Body", x, y - 12, C.gold, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(dist .. " м · " .. tostring(call.text or ""), "GRMFireCall_Small", x, y + 10, C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end)

    -- Список вызовов (/fire_calls и кнопка в компьютере станции).
    function D.OpenList(rows)
        local frame = vgui.Create("DFrame")
        if GRM.UI and GRM.UI.Track then GRM.UI.Track("fire_calls_list", frame) end
        frame:SetSize(math.min(900, ScrW() - 80), math.min(560, ScrH() - 120))
        frame:Center()
        frame:MakePopup()
        frame:SetTitle("")
        frame:ShowCloseButton(false)
        frame.Paint = function(_, w, h)
            draw.RoundedBox(8, 0, 0, w, h, C.bg)
            draw.RoundedBoxEx(8, 0, 0, w, 42, C.head, true, true, false, false)
            draw.SimpleText("ВЫЗОВЫ ПОЖАРНОЙ СЛУЖБЫ", "GRMFireCall_Title", 16, 21, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText("Записей: " .. #rows, "GRMFireCall_Small", w - 16, 21, C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end

        local close = vgui.Create("DButton", frame)
        close:SetSize(28, 24) close:SetText("✕") close:SetFont("GRMFireCall_Body") close:SetTextColor(C.dim)
        close.Paint = function(s, w, h) draw.RoundedBox(4, 0, 0, w, h, s:IsHovered() and C.red or Color(50, 36, 32)) end
        close.DoClick = function() frame:Close() end
        frame.PerformLayout = function(self, w) if IsValid(close) then close:SetPos(w - 36, 9) end end

        local list = vgui.Create("DListView", frame)
        list:Dock(FILL) list:DockMargin(12, 52, 12, 52)
        list:SetMultiSelect(false)
        list:AddColumn("№"):SetFixedWidth(55)
        list:AddColumn("Время"):SetFixedWidth(135)
        list:AddColumn("Описание")
        list:AddColumn("Район"):SetFixedWidth(150)
        list:AddColumn("Статус"):SetFixedWidth(110)
        list:AddColumn("Принял"):SetFixedWidth(150)

        local STATUS = { pending = "ОЖИДАЕТ", accepted = "Принят", closed = "Закрыт" }
        for _, r in ipairs(rows) do
            local line = list:AddLine(tostring(r.id), os.date("%d.%m %H:%M", tonumber(r.created) or 0),
                tostring(r.text or ""), tostring(r.area or ""),
                STATUS[tostring(r.status or "")] or tostring(r.status or ""), tostring(r.assigned or ""))
            line.CallID = r.id
            line.CallStatus = r.status
            line.CallOrigin = Vector(r.x or 0, r.y or 0, r.z or 0)
            line.CallText = r.text
        end

        local accept = vgui.Create("DButton", frame)
        accept:Dock(BOTTOM) accept:SetTall(38) accept:DockMargin(12, 0, 12, 12) accept:SetText("")
        accept.Paint = function(self, w, h)
            draw.RoundedBox(6, 0, 0, w, h, self:IsHovered() and Color(75, 200, 120) or C.green)
            draw.SimpleText("ПРИНЯТЬ ВЫБРАННЫЙ ВЫЗОВ", "GRMFireCall_Body", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        accept.DoClick = function()
            local line = list:GetSelectedLine() and list:GetLine(list:GetSelectedLine())
            if not line or not line.CallID then
                notification.AddLegacy("Выберите вызов в списке", NOTIFY_HINT, 3)
                return
            end
            if line.CallStatus == "closed" then
                notification.AddLegacy("Этот вызов уже закрыт", NOTIFY_ERROR, 3)
                return
            end
            D.MyCall = { id = line.CallID, origin = line.CallOrigin, text = line.CallText }
            net.Start(NET_ACT)
                net.WriteUInt(line.CallID, 16)
                net.WriteString("accept")
            net.SendToServer()
            surface.PlaySound("buttons/button14.wav")
            frame:Close()
        end
    end

    net.Receive(NET_LIST, function()
        D.OpenList(net.ReadTable() or {})
    end)

    function D.RequestList()
        net.Start(NET_LISTRQ)
        net.SendToServer()
    end

    concommand.Add("grm_fire_calls", function() D.RequestList() end)
end

print("[GRM Fire Dispatch] v" .. D.Version .. " loaded")
