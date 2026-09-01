--[[ Капли крови на землю от GRM_Bleed. Сервер решает, клиент рисует decal. ]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.BloodDrops = GRM.BloodDrops or {}
local B = GRM.BloodDrops
B.Version = "1.0.0"

if SERVER then
    util.AddNetworkString("GRM_BloodDrop")
    local last = {}
    timer.Create("GRM_BloodDrops", 0.8, 0, function()
        local now = CurTime()
        for _, ply in ipairs(player.GetAll()) do
            if not IsValid(ply) or not ply:Alive() then continue end
            if ply:InVehicle() then continue end
            if ply:WaterLevel() >= 2 then continue end
            local bleed = ply:GetNWInt("GRM_Bleed", 0)
            if bleed < 8 then continue end
            local sid = ply:SteamID64() or tostring(ply:EntIndex())
            local gap = math.Clamp(2.4 - bleed * 0.018, 0.45, 2.4)
            if (last[sid] or 0) + gap > now then continue end
            last[sid] = now
            local tr = util.TraceLine({
                start = ply:GetPos() + Vector(0, 0, 8),
                endpos = ply:GetPos() - Vector(0, 0, 80),
                filter = ply,
                mask = MASK_SOLID_BRUSHONLY,
            })
            if not tr.Hit then continue end
            net.Start("GRM_BloodDrop")
                net.WriteVector(tr.HitPos + tr.HitNormal)
                net.WriteVector(tr.HitNormal)
                net.WriteUInt(math.Clamp(math.floor(bleed), 0, 100), 8)
            net.SendPVS(tr.HitPos)
        end
    end)
end

if CLIENT then
    net.Receive("GRM_BloodDrop", function()
        local pos = net.ReadVector()
        local nrm = net.ReadVector()
        local str = net.ReadUInt(8)
        local decals = { "Blood", "Blood", "Blood" }
        util.Decal(decals[math.random(1, #decals)], pos + nrm * 2, pos - nrm * 8)
        if str >= 40 then
            local ed = EffectData()
            ed:SetOrigin(pos)
            ed:SetNormal(nrm)
            ed:SetScale(math.Clamp(str / 80, 0.3, 1.2))
            util.Effect("BloodImpact", ed, true, true)
        end
    end)
end
