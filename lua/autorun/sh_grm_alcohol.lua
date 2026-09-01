--[[ Алкоголь, варка пива/кваса, алкотестер. ]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Alcohol = GRM.Alcohol or {}
local A = GRM.Alcohol
A.Version = "1.0.0"
A.NET = "GRM_Alco_Test"

function A.Get(ply)
    if not IsValid(ply) then return 0 end
    return tonumber(ply:GetNWFloat("GRM_Alcohol", 0)) or 0
end

function A.Label(v)
    v = tonumber(v) or 0
    if v < 0.15 then return "трезв", Color(120, 220, 130)
    elseif v < 0.4 then return "следы", Color(220, 210, 80)
    elseif v < 0.8 then return "лёгкое опьянение", Color(240, 170, 50)
    elseif v < 1.5 then return "опьянение", Color(240, 110, 50)
    else return "сильное опьянение", Color(230, 50, 50) end
end

if SERVER then
    util.AddNetworkString(A.NET)

    function A.Add(ply, amount)
        if not IsValid(ply) then return 0 end
        local v = math.Clamp(A.Get(ply) + (tonumber(amount) or 0), 0, 4)
        ply:SetNWFloat("GRM_Alcohol", v)
        return v
    end

    timer.Create("GRM_Alcohol_Decay", 2, 0, function()
        for _, ply in ipairs(player.GetAll()) do
            local v = A.Get(ply)
            if v > 0 then
                ply:SetNWFloat("GRM_Alcohol", math.max(0, v - 0.012))
            end
        end
    end)

    hook.Add("SetupMove", "GRM_Alcohol_Move", function(ply, mv)
        local v = A.Get(ply)
        if v < 0.35 then return end
        local mul = math.Clamp(1 - (v - 0.35) * 0.22, 0.45, 1)
        mv:SetMaxClientSpeed(mv:GetMaxClientSpeed() * mul)
        if v >= 1.2 then
            local wob = math.sin(CurTime() * 3 + ply:EntIndex()) * (v - 1) * 18
            mv:SetSideSpeed(mv:GetSideSpeed() + wob)
        end
    end)

    function A.Test(tester, target)
        if not (IsValid(tester) and IsValid(target) and target:IsPlayer()) then return false, "нет цели" end
        if tester:GetPos():DistToSqr(target:GetPos()) > 120 * 120 then return false, "подойдите ближе" end
        local v = math.Round(A.Get(target), 2)
        local lab = A.Label(v)
        net.Start(A.NET)
            net.WriteEntity(target)
            net.WriteFloat(v)
        net.Send(tester)
        if GRM.Notify then
            GRM.Notify(tester, string.format("Алкотестер: %s — %.2f ‰ (%s)", target:GetNWString("GRM_RPName", target:Nick()), v, lab), 100, 200, 220)
        end
        return true, v
    end
end

if CLIENT then
    net.Receive(A.NET, function()
        local t = net.ReadEntity()
        local v = net.ReadFloat()
        local lab = select(1, A.Label(v))
        chat.AddText(Color(80, 180, 220), "[Алкотестер] ", color_white,
            (IsValid(t) and (t:GetNWString("GRM_RPName", t:Nick())) or "?") .. string.format(" — %.2f ‰ · %s", v, lab))
    end)

    hook.Add("RenderScreenspaceEffects", "GRM_Alcohol_CC", function()
        local lp = LocalPlayer()
        if not IsValid(lp) then return end
        local v = A.Get(lp)
        if v < 0.5 then return end
        local a = math.Clamp((v - 0.5) / 2.5, 0, 0.55)
        DrawMotionBlur(0.12 + a * 0.25, a * 0.7, 0.01)
        DrawSharpen(0.4 + a, 0.3)
    end)
end
