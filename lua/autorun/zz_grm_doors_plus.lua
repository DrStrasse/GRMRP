--[[ Двери+: гость на время, стук, выбивание с прогрессом. ]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
local D = GRM.Doors
if not D then return end

local NET_KICK = "GRM_DoorKick"

if SERVER then
    util.AddNetworkString(NET_KICK)

    local oldEval = D.EvaluateAccess
    if oldEval and not D._plusEval then
        D.EvaluateAccess = function(rec, actor)
            local acc = oldEval(rec, actor)
            if not istable(acc) or not istable(rec) or not istable(actor) then return acc end
            local key = tostring(actor.key or "")
            local now = os.time()
            if istable(rec.guests) and key ~= "" then
                for i = #rec.guests, 1, -1 do
                    local g = rec.guests[i]
                    if istable(g) and tostring(g.key) == key then
                        if (tonumber(g.untilAt) or 0) > now then
                            acc.has_key = true
                            acc.walk_locked = true
                            acc.lock = acc.lock or false
                        else
                            table.remove(rec.guests, i)
                        end
                    end
                end
            end
            return acc
        end
        D._plusEval = true
    end

    function D.AddGuest(ent, targetKey, minutes)
        if not D.GetRecord then return false end
        local rec, id = D.GetRecord(ent)
        if not rec then return false end
        rec.guests = rec.guests or {}
        local untilT = os.time() + math.Clamp(math.floor(tonumber(minutes) or 60), 5, 24 * 60) * 60
        for _, g in ipairs(rec.guests) do
            if tostring(g.key) == tostring(targetKey) then g.untilAt = untilT return true end
        end
        rec.guests[#rec.guests + 1] = { key = tostring(targetKey), untilAt = untilT }
        rec._ephemeral = nil
        if D.SaveDoors then D.SaveDoors("guest") end
        return true
    end

    hook.Add("PlayerUse", "GRM_DoorsPlus_Knock", function(ply, ent)
        if not D.IsDoor or not D.IsDoor(ent) then return end
        if not D.IsDoorLocked or not D.IsDoorLocked(ent) then return end
        if D.CanAccessDoor and select(1, D.CanAccessDoor(ply, ent)) then return end
        ply._grmDoorKnock = ply._grmDoorKnock or 0
        if CurTime() < ply._grmDoorKnock then return end
        ply._grmDoorKnock = CurTime() + 1.1
        ent:EmitSound("physics/wood/wood_crate_impact_hard" .. math.random(2, 3) .. ".wav", 72, math.random(90, 110))
        if GRM.Notify then GRM.Notify(ply, "Вы постучали в дверь.", 200, 200, 210) end
    end)

    function D.StartKick(ply, ent)
        if not (IsValid(ply) and IsValid(ent) and D.IsDoor(ent)) then return false end
        if not D.IsDoorLocked(ent) then
            if GRM.Notify then GRM.Notify(ply, "Дверь не заперта.", 255, 180, 80) end
            return false
        end
        local rec = D.GetRecord and select(1, D.GetRecord(ent))
        local acc = D.EvaluateAccess and D.EvaluateAccess(rec, { superadmin = ply:IsSuperAdmin(), key = "" })
        local need = 8
        if ply:IsSuperAdmin() then need = 3 end
        local fac = ply:GetNWString("GRM_Faction", "")
        if fac ~= "" then need = 6 end
        ply._grmKick = { ent = ent, start = CurTime(), need = need }
        net.Start(NET_KICK) net.WriteBool(true) net.WriteFloat(need) net.Send(ply)
        return true
    end

    hook.Add("Think", "GRM_DoorsPlus_Kick", function()
        for _, ply in ipairs(player.GetAll()) do
            local k = ply._grmKick
            if not k then continue end
            if not ply:KeyDown(IN_RELOAD) or not IsValid(k.ent) then
                ply._grmKick = nil
                net.Start(NET_KICK) net.WriteBool(false) net.WriteFloat(0) net.Send(ply)
                continue
            end
            if ply:GetPos():DistToSqr(k.ent:GetPos()) > 140 * 140 then
                ply._grmKick = nil
                net.Start(NET_KICK) net.WriteBool(false) net.WriteFloat(0) net.Send(ply)
                continue
            end
            if CurTime() - k.start >= k.need then
                ply._grmKick = nil
                net.Start(NET_KICK) net.WriteBool(false) net.WriteFloat(0) net.Send(ply)
                if D.BreachDoor then D.BreachDoor(k.ent, ply, "kick") end
                k.ent:EmitSound("physics/wood/wood_crate_break" .. math.random(1, 4) .. ".wav", 85, 100)
                if GRM.Notify then GRM.Notify(ply, "Дверь выбита. Замок сломан.", 240, 140, 80) end
            end
        end
    end)

    hook.Add("PlayerSay", "GRM_DoorsPlus_Chat", function(ply, text)
        local t = string.Trim(text or "")
        local low = string.lower(t)
        if low == "/door_kick" or low == "/выбить" then
            local tr = ply:GetEyeTrace()
            if D.IsDoor(tr.Entity) then D.StartKick(ply, tr.Entity) end
            return ""
        end
        if string.sub(low, 1, 12) == "/door_guest " then
            local mins = tonumber(string.match(t, "(%d+)$")) or 60
            local tr = ply:GetEyeTrace()
            if not D.IsDoor(tr.Entity) then return "" end
            local rec = D.GetRecord and select(1, D.GetRecord(tr.Entity))
            local acc = rec and D.EvaluateAccess(rec, {
                superadmin = ply:IsSuperAdmin(),
                key = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply)) or "",
            })
            if not (acc and (acc.own or acc.admin or acc.is_owner)) then
                if GRM.Notify then GRM.Notify(ply, "Только владелец может звать гостей.", 255, 140, 80) end
                return ""
            end
            local aim = ply:GetEyeTrace().Entity
            -- guest = nearest other player
            local near, nd = nil, 160 * 160
            for _, p in ipairs(player.GetAll()) do
                if p ~= ply and IsValid(p) then
                    local d = ply:GetPos():DistToSqr(p:GetPos())
                    if d < nd then near, nd = p, d end
                end
            end
            if not IsValid(near) then
                if GRM.Notify then GRM.Notify(ply, "Рядом никого нет.", 255, 180, 80) end
                return ""
            end
            local key = GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(near) or (near:SteamID64() .. ":char1")
            if D.AddGuest(tr.Entity, key, mins) then
                if GRM.Notify then GRM.Notify(ply, near:Nick() .. " — гость на " .. mins .. " мин.", 120, 220, 140) end
            end
            return ""
        end
    end)
end

if CLIENT then
    local kickUntil, kickNeed = 0, 0
    net.Receive(NET_KICK, function()
        local on = net.ReadBool()
        kickNeed = net.ReadFloat()
        kickUntil = on and (CurTime() + kickNeed) or 0
    end)
    hook.Add("HUDPaint", "GRM_DoorsPlus_KickHUD", function()
        if kickUntil <= CurTime() then return end
        local left = kickUntil - CurTime()
        local pct = 1 - left / math.max(0.1, kickNeed)
        local w, h = 220, 12
        local x, y = ScrW() / 2 - w / 2, ScrH() / 2 + 70
        draw.SimpleText("Выбиваем дверь… держите R", "DermaDefaultBold", x + w / 2, y - 16, Color(255, 160, 80), TEXT_ALIGN_CENTER)
        surface.SetDrawColor(30, 30, 30, 200) surface.DrawRect(x, y, w, h)
        surface.SetDrawColor(230, 90, 60) surface.DrawRect(x, y, w * pct, h)
    end)
end
