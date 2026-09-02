--[[ Круиз — потолок. Автопилот — сам крутит газ (W + тяга + simfphys-клавиши). ]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Cruise = GRM.Cruise or {}
local C = GRM.Cruise
C.Version = "1.1.0"

--[[ Корень транспорта — общий помощник GRM.Core.VehRoot (волна дедупа 1).
     Для обычного стула возвращает nil: прежний фолбэк отдавал сам стул,
     и модуль принимал кресло за автомобиль. ]]
local function root(ent) return GRM.Core.VehRoot(ent) end

local function physOf(ent)
    if not IsValid(ent) then return nil end
    local ph = ent:GetPhysicsObject()
    if IsValid(ph) then return ph, ent end
    if ent.GetChassis then
        local ch = ent:GetChassis()
        if IsValid(ch) then
            ph = ch:GetPhysicsObject()
            if IsValid(ph) then return ph, ch end
        end
    end
    return nil, ent
end

local function kmh(ent)
    local ph, body = physOf(ent)
    if IsValid(ph) then return ph:GetVelocity():Length() * 0.09144 end
    if IsValid(body) then return body:GetVelocity():Length() * 0.09144 end
    return 0
end

local function clear(ply)
    if not IsValid(ply) then return end
    ply:SetNWBool("GRM_AutoPilot", false)
    ply:SetNWBool("GRM_CruiseOn", false)
    ply:SetNWInt("GRM_CruiseKmh", 0)
    local veh = IsValid(ply:GetVehicle()) and root(ply:GetVehicle())
    if IsValid(veh) and istable(veh.PressedKeys) then
        veh.PressedKeys["W"] = false
        veh.PressedKeys[IN_FORWARD] = false
    end
end

local function wakeEngine(veh)
    if not IsValid(veh) then return end
    pcall(function()
        if veh.StartEngine then veh:StartEngine(true) end
        if veh.EnableEngine then veh:EnableEngine(true) end
        if veh.SetActive then veh:SetActive(true) end
        if veh.TurnOn then veh:TurnOn() end
        if veh.ForceHandbrake then veh:ForceHandbrake(false) end
        if veh.HandBrake then veh.HandBrake = false end
    end)
end

local function pressW(veh, on)
    if not IsValid(veh) then return end
    veh.PressedKeys = veh.PressedKeys or {}
    veh.PressedKeys["W"] = on == true
    veh.PressedKeys[IN_FORWARD] = on == true
    pcall(function()
        if veh.SetThrottle then veh:SetThrottle(on and 1 or 0) end
        if veh.SetNWFloat then veh:SetNWFloat("Throttle", on and 1 or 0) end
    end)
end

if SERVER then
    util.AddNetworkString("GRM_Cruise")

    local function setMode(ply, mode, speed)
        if not IsValid(ply) or not ply:InVehicle() then
            return false, "Садись за руль."
        end
        speed = math.Clamp(math.floor(tonumber(speed) or 0), 0, 200)
        if speed <= 0 or mode == "off" then
            clear(ply)
            return true, "Круиз и автопилот сняты."
        end
        ply:SetNWInt("GRM_CruiseKmh", speed)
        local veh = root(ply:GetVehicle())
        if mode == "auto" then
            ply:SetNWBool("GRM_AutoPilot", true)
            ply:SetNWBool("GRM_CruiseOn", true)
            wakeEngine(veh)
            pressW(veh, true)
            return true, "Автопилот " .. speed .. " км/ч. S или /cruise 0 — стоп."
        end
        ply:SetNWBool("GRM_AutoPilot", false)
        ply:SetNWBool("GRM_CruiseOn", true)
        pressW(veh, false)
        return true, "Круиз: не быстрее " .. speed .. " км/ч."
    end

    net.Receive("GRM_Cruise", function(_, ply)
        if not IsValid(ply) then return end
        ply._grmCruise = ply._grmCruise or 0
        if CurTime() < ply._grmCruise then return end
        ply._grmCruise = CurTime() + 0.15
        local ok, msg = setMode(ply, string.sub(net.ReadString() or "", 1, 8), net.ReadUInt(8))
        if GRM.Notify then GRM.Notify(ply, msg, ok and 120 or 255, ok and 210 or 140, 90) end
    end)

    hook.Add("PlayerLeaveVehicle", "GRM_Cruise_Leave", function(ply) clear(ply) end)
    hook.Add("PlayerDeath", "GRM_Cruise_Die", function(ply) clear(ply) end)

    hook.Add("Think", "GRM_Cruise_Drive", function()
        if GRM.Perf and GRM.Perf.Throttle and not GRM.Perf.Throttle("cruise.drv", 0.05) then return end
        local list = (GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()
        local any
        for i = 1, #list do
            local p = list[i]
            if IsValid(p) and p:GetNWBool("GRM_CruiseOn") then any = true break end
        end
        if not any then return end
        for _, ply in ipairs(list) do
            if not (IsValid(ply) and ply:InVehicle() and ply:GetNWBool("GRM_CruiseOn")) then continue end
            local cap = ply:GetNWInt("GRM_CruiseKmh", 0)
            if cap <= 0 then continue end
            local veh = root(ply:GetVehicle())
            if not IsValid(veh) then continue end
            local speed = kmh(veh)
            local ph = physOf(veh)
            if ply:GetNWBool("GRM_AutoPilot") then
                if ply:KeyDown(IN_BACK) then
                    clear(ply)
                    if GRM.Notify then GRM.Notify(ply, "Автопилот снят.", 180, 210, 140) end
                    continue
                end
                if (ply._grmWakeAt or 0) < CurTime() then
                    ply._grmWakeAt = CurTime() + 2
                    wakeEngine(veh)
                end
                local need = speed < cap - 0.6
                pressW(veh, need or (speed < cap + 0.4))
                if need and IsValid(ph) then
                    local mass = math.max(80, ph:GetMass())
                    local boost = math.Clamp((cap - speed) / 18, 0.2, 1.1)
                    ph:ApplyForceCenter(veh:GetForward() * mass * 520 * boost)
                    ph:Wake()
                elseif speed > cap + 1 and IsValid(ph) then
                    ph:SetVelocity(ph:GetVelocity() * (cap / math.max(0.2, speed)))
                    pressW(veh, false)
                end
            elseif speed > cap + 0.8 and IsValid(ph) then
                ph:SetVelocity(ph:GetVelocity() * (cap / math.max(0.2, speed)))
            end
        end
    end)

    local function chatCmd(ply, text)
        local t = string.lower(string.Trim(tostring(text or "")))
        local mode, num
        local n = t:match("(%d+)") or ""
        if string.sub(t, 1, 11) == "/autopilot" or string.find(t, "^/автопилот", 1, false) then
            mode = (n == "" or n == "0") and "off" or "auto"
            num = tonumber(n) or 0
        elseif string.sub(t, 1, 7) == "/cruise" or string.find(t, "^/круиз", 1, false) then
            mode = (n == "" or n == "0") and "off" or "cruise"
            num = tonumber(n) or 0
        end
        if not mode then return end
        local ok, msg = setMode(ply, mode, num)
        if GRM.Notify then GRM.Notify(ply, msg, ok and 120 or 255, ok and 210 or 140, 90) end
        return true
    end

    hook.Add("PlayerSayTransform", "GRM_Cruise_Chat", function(ply, pack)
        if not istable(pack) then return end
        if chatCmd(ply, pack[1]) then pack[1] = "" pack.SkipPlayerSay = true end
    end)
    hook.Add("PlayerSay", "GRM_Cruise_ChatRaw", function(ply, text)
        if chatCmd(ply, text) then return "" end
    end)
    concommand.Add("grm_autopilot", function(ply, _, a)
        if IsValid(ply) then setMode(ply, "auto", tonumber(a and a[1]) or 0) end
    end)
    concommand.Add("grm_cruise", function(ply, _, a)
        if IsValid(ply) then setMode(ply, "cruise", tonumber(a and a[1]) or 0) end
    end)

    print("[GRM Cruise] server v" .. C.Version)
end

if CLIENT then
    hook.Add("StartCommand", "GRM_Cruise_Keys", function(ply, cmd)
        if ply ~= LocalPlayer() then return end
        if not IsValid(ply) or not ply.InVehicle or not ply:InVehicle() then return end
        if not ply:GetNWBool("GRM_AutoPilot") then return end
        if bit.band(cmd:GetButtons(), IN_BACK) ~= 0 then return end
        local cap = ply:GetNWInt("GRM_CruiseKmh", 0)
        if cap <= 0 then return end
        local speed = kmh(root(ply:GetVehicle()))
        if speed < cap + 0.5 then
            cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_FORWARD))
            cmd:SetForwardMove(10000)
        else
            cmd:SetForwardMove(0)
            cmd:SetButtons(bit.band(cmd:GetButtons(), bit.bnot(IN_FORWARD)))
        end
    end)

    local CRUISE_TEXT = Color(250, 185, 63)
    local CRUISE_OUTLINE = Color(0, 0, 0, 220)

    hook.Add("HUDPaint", "GRM_Cruise_HUD", function()
        local lp = LocalPlayer()
        if not IsValid(lp) or not lp.InVehicle or not lp:InVehicle() then return end
        if not lp:GetNWBool("GRM_CruiseOn") then return end
        local cap = lp:GetNWInt("GRM_CruiseKmh", 0)
        local mode = lp:GetNWBool("GRM_AutoPilot") and "АВТОПИЛОТ" or "КРУИЗ"
        draw.SimpleTextOutlined(mode .. "  " .. cap .. " км/ч", "DermaDefault", ScrW() / 2, ScrH() - 132,
            CRUISE_TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, CRUISE_OUTLINE)
    end)
end
