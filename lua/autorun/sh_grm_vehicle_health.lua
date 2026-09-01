--[[ Прочность ТС. Max/текущее = simfphys (MaxHealth/CurHealth), иначе 100. ]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.VehHP = GRM.VehHP or {}
local H = GRM.VehHP
H.Version = "1.1.0"
H.File = "grm_vehicle_hp.json"
H.Max = 100
H.RepairPrice = 45
H.WrenchPerSec = 12
H.WrenchPrice = 8

--[[ Корень транспорта. Для обычного стула возвращает nil: прежний фолбэк
     отдавал сам стул, и модуль принимал кресло за автомобиль. ]]
local function root(ent)
    if GRM.Fuel and GRM.Fuel.RootVehicle then return GRM.Fuel.RootVehicle(ent) end
    if not (IsValid(ent) and ent.GetParent) then return nil end
    local p = ent:GetParent()
    if IsValid(p) then return p end
    if ent.IsSimfphysCar or ent.LVS or ent.IsLVSVehicle or ent.IsGlideVehicle then return ent end
    local cls = string.lower(ent:GetClass() or "")
    if cls == "prop_vehicle_jeep" or cls == "prop_vehicle_airboat" then return ent end
    return nil
end

local function isVeh(ent)
    if not IsValid(ent) then return false end
    local VK = GRM.VehicleKeys or _G.VK
    if VK and VK.IsVehicle then return VK.IsVehicle(ent) == true end
    return (ent.IsVehicle and ent:IsVehicle()) or ent.IsSimfphysCar == true or ent.LVS == true
end

local function uidOf(ent)
    if GRM.Vehicles and GRM.Vehicles.EnsureUID then return GRM.Vehicles.EnsureUID(ent) end
    if GRM.Fuel and GRM.Fuel.UID then return GRM.Fuel.UID(ent) end
    return IsValid(ent) and ("ent:" .. ent:EntIndex()) or ""
end

if SERVER then
    H.Data = H.Data or {}

    local function jsonT(txt)
        local ok, t = pcall(util.JSONToTable, txt, false, true)
        return (ok and istable(t)) and t or nil
    end

    function H.Load()
        if not file.Exists(H.File, "DATA") then H.Data = {} return end
        H.Data = jsonT(file.Read(H.File, "DATA") or "") or {}
    end

    function H.Save()
        local fn = function()
            local ok, txt = pcall(util.TableToJSON, H.Data or {}, false)
            if ok and txt then file.Write(H.File, txt) end
        end
        if GRM.Perf and GRM.Perf.Coalesce then GRM.Perf.Coalesce("grm_vehhp_save", 1.2, fn) else fn() end
    end

    function H.Get(uid)
        uid = tostring(uid or "")
        if uid == "" then return nil end
        H.Data[uid] = H.Data[uid] or { hp = H.Max }
        return H.Data[uid]
    end

    function H.NativeMax(ent)
        if not IsValid(ent) then return H.Max end
        local m
        pcall(function()
            if ent.GetMaxHealth then m = tonumber(ent:GetMaxHealth()) end
            if (not m or m <= 1) and tonumber(ent.MaxHealth) then m = tonumber(ent.MaxHealth) end
            if (not m or m <= 1) and istable(ent.GetVehicleParams) then
                local p = ent:GetVehicleParams()
                if istable(p) then m = tonumber(p.MaxHealth or (p.Engine and p.Engine.MaxHealth)) end
            end
            if (not m or m <= 1) and ent.GetMaxHP then m = tonumber(ent:GetMaxHP()) end
        end)
        if not m or m <= 1 then m = H.Max end
        return math.max(1, m)
    end

    function H.NativeCur(ent)
        if not IsValid(ent) then return nil end
        local c
        pcall(function()
            if ent.GetCurHealth then c = tonumber(ent:GetCurHealth()) end
            if c == nil and ent.GetHP then c = tonumber(ent:GetHP()) end
            if c == nil and ent.Health then c = tonumber(ent:Health()) end
        end)
        return c
    end

    function H.PushNative(ent, hp, mx)
        if not IsValid(ent) then return end
        hp = math.max(0, tonumber(hp) or 0)
        mx = math.max(1, tonumber(mx) or H.NativeMax(ent))
        pcall(function()
            if ent.SetCurHealth then ent:SetCurHealth(hp) end
            if ent.SetHP then ent:SetHP(hp) end
            if ent.SetHealth then ent:SetHealth(hp) end
            if hp > 0 then
                ent.Destroyed = false
                if ent.SetDestroyed then ent:SetDestroyed(false) end
                if ent.SetOnFire then ent:SetOnFire(false) end
                if ent.SetOnSmoke then ent:SetOnSmoke(false) end
                if ent.StopOnFire then ent:StopOnFire() end
            end
            if hp >= mx * 0.999 and ent.RepairVehicle then ent:RepairVehicle() end
        end)
    end

    function H.Ceiling(ent, rec)
        local mx = H.NativeMax(ent)
        rec = rec or H.Get(uidOf(ent))
        if rec.max == nil and rec.hp ~= nil then
            local old = tonumber(rec.hp) or H.Max
            if old <= H.Max + 0.01 then
                rec.hp = (old / H.Max) * mx
            end
        end
        rec.max = mx
        rec.hp = math.Clamp(tonumber(rec.hp) or mx, 0, mx)
        return rec, mx
    end

    function H.Apply(ent)
        if not IsValid(ent) or not isVeh(ent) then return end
        ent = root(ent) or ent
        local rec, mx = H.Ceiling(ent, H.Get(uidOf(ent)))
        if GRM.Perf and GRM.Perf.NWFloat then
            GRM.Perf.NWFloat(ent, "GRM_VehHP", rec.hp, 0.2)
            GRM.Perf.NWFloat(ent, "GRM_VehHPMax", mx, 0.1)
            GRM.Perf.NWBool(ent, "GRM_VehBroken", rec.hp <= 0)
        else
            ent:SetNWFloat("GRM_VehHP", rec.hp)
            ent:SetNWFloat("GRM_VehHPMax", mx)
            ent:SetNWBool("GRM_VehBroken", rec.hp <= 0)
        end
        H.PushNative(ent, rec.hp, mx)
        if rec.hp <= 0 then H.Break(ent) end
        return rec.hp
    end

    function H.Break(ent)
        if not IsValid(ent) then return end
        pcall(function()
            if ent.EnableEngine then ent:EnableEngine(false) end
            if ent.StartEngine then ent:StartEngine(false) end
            if ent.SetActive then ent:SetActive(false) end
            if ent.TurnOff then ent:TurnOff() end
            if ent.StopEngine then ent:StopEngine() end
        end)
        ent:SetNWBool("GRM_VehBroken", true)
        for _, ply in ipairs((GRM.Perf and GRM.Perf.Players and GRM.Perf.Players()) or player.GetAll()) do
            if IsValid(ply) and ply:InVehicle() and root(ply:GetVehicle()) == ent then
                if GRM.Cruise then
                    ply:SetNWBool("GRM_AutoPilot", false)
                    ply:SetNWBool("GRM_CruiseOn", false)
                end
            end
        end
    end

    function H.Hurt(ent, amount, reason)
        if not IsValid(ent) then return 0 end
        ent = root(ent) or ent
        if not isVeh(ent) then return 0 end
        local rec, mx = H.Ceiling(ent, H.Get(uidOf(ent)))
        local before = rec.hp
        rec.hp = math.Clamp(rec.hp - math.max(0, tonumber(amount) or 0), 0, mx)
        H.Apply(ent)
        H.Save()
        if before > 0 and rec.hp <= 0 then
            H.Break(ent)
        end
        return before - rec.hp
    end

    function H.Repair(ent, amount)
        if not IsValid(ent) then return 0 end
        ent = root(ent) or ent
        local rec, mx = H.Ceiling(ent, H.Get(uidOf(ent)))
        local room = mx - rec.hp
        local add = math.min(room, math.max(0, tonumber(amount) or 0))
        rec.hp = rec.hp + add
        if rec.hp > 0 then
            rec.broken = false
            ent:SetNWBool("GRM_VehBroken", false)
            pcall(function()
                if ent.EnableEngine then ent:EnableEngine(true) end
            end)
        end
        if rec.hp >= mx * 0.999 then
            pcall(function()
                if ent.Repair then ent:Repair() end
            end)
            rec.hp = mx
        end
        H.Apply(ent)
        H.Save()
        return add
    end

    function H.WrenchTick(ply, ent)
        if not IsValid(ply) then return false, "нет" end
        ent = root(ent)
        if not isVeh(ent) then return false, "Это не транспорт" end
        if ply:GetPos():DistToSqr(ent:GetPos()) > 180 * 180 then return false, "Ближе" end
        local rec, mx = H.Ceiling(ent, H.Get(uidOf(ent)))
        if rec.hp >= mx then return false, "целая" end
        local add = math.min((H.WrenchPerSec / H.Max) * mx * 0.2, mx - rec.hp)
        local cost = math.ceil((add / mx) * H.Max * H.WrenchPrice)
        if not ply:IsSuperAdmin() and cost > 0 then
            if GRM.HasMoney and not GRM.HasMoney(ply, cost) then
                return false, "Нужно " .. cost .. " GRM"
            end
            if GRM.TakeMoney then GRM.TakeMoney(ply, cost, "ключ ТС") end
        else
            cost = 0
        end
        H.Repair(ent, add)
        return true, rec.hp, mx, cost
    end

    function H.TryRepair(ply, ent)
        if not IsValid(ply) then return false, "Нет игрока" end
        ent = root(ent)
        if not isVeh(ent) then return false, "Это не транспорт" end
        if ply:GetPos():DistToSqr(ent:GetPos()) > 220 * 220 then return false, "Подойди ближе" end
        local rec, mx = H.Ceiling(ent, H.Get(uidOf(ent)))
        local need = mx - rec.hp
        if need <= 0 then return false, "Машина целая" end
        local cost = math.ceil((need / mx) * H.Max * H.RepairPrice)
        if not ply:IsSuperAdmin() then
            if GRM.HasMoney and not GRM.HasMoney(ply, cost) then
                return false, "Нужно " .. cost .. " GRM"
            end
            if GRM.TakeMoney then GRM.TakeMoney(ply, cost, "ремонт ТС") end
        else
            cost = 0
        end
        H.Repair(ent, need)
        return true, string.format("Отремонтировано. −%d GRM. Прочность %d/%d", cost, rec.hp, H.Max)
    end

    hook.Add("EntityTakeDamage", "GRM_VehHP_Dmg", function(ent, dmg)
        if not IsValid(ent) or not dmg then return end
        local veh = root(ent)
        if not isVeh(veh) then
            if IsValid(ent:GetParent()) and isVeh(root(ent:GetParent())) then veh = root(ent:GetParent()) else return end
        end
        local amt = tonumber(dmg:GetDamage()) or 0
        if amt < 1 then return end
        if dmg:IsDamageType(DMG_CRUSH) or dmg:IsDamageType(DMG_VEHICLE) then amt = amt * 0.12
        elseif dmg:IsBulletDamage() then amt = amt * 0.22
        elseif dmg:IsExplosionDamage() then amt = amt * 0.55
        else amt = amt * 0.18 end
        H.Hurt(veh, amt, "dmg")
    end)

    hook.Add("Think", "GRM_VehHP_Crash", function()
        if GRM.Perf and GRM.Perf.Throttle and not GRM.Perf.Throttle("vehhp.crash", 0.2) then return end
        local list = (GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()
        for i = 1, #list do
            local ply = list[i]
            if not (IsValid(ply) and ply:InVehicle()) then continue end
            local veh = root(ply:GetVehicle())
            if not IsValid(veh) then continue end
            local vel = veh:GetVelocity():Length()
            local prev = veh._grmLastVel or vel
            veh._grmLastVel = vel
            local drop = prev - vel
            if drop > 380 then
                H.Hurt(veh, math.Clamp((drop - 380) / 40, 2, 28), "crash")
            end
        end
    end)

    hook.Add("OnEntityCreated", "GRM_VehHP_Spawn", function(ent)
        timer.Simple(0.8, function()
            if not (IsValid(ent) and isVeh(ent)) then return end
            ent = root(ent) or ent
            local rec = H.Get(uidOf(ent))
            local mx = H.NativeMax(ent)
            local cur = H.NativeCur(ent)
            if rec.max == nil and cur and mx > 1 then
                rec.hp = math.Clamp(cur, 0, mx)
                rec.max = mx
            end
            H.Apply(ent)
        end)
    end)

    hook.Add("Think", "GRM_VehHP_SyncNative", function()
        if GRM.Perf and GRM.Perf.Throttle and not GRM.Perf.Throttle("vehhp.sync", 0.7) then return end
        local list = (GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()
        for i = 1, #list do
            local ply = list[i]
            if not (IsValid(ply) and ply:InVehicle()) then continue end
            local veh = root(ply:GetVehicle())
            if not isVeh(veh) then continue end
            local rec, mx = H.Ceiling(veh, H.Get(uidOf(veh)))
            local cur = H.NativeCur(veh)
            if cur and cur + 1 < rec.hp then
                rec.hp = math.Clamp(cur, 0, mx)
                H.Apply(veh)
                H.Save()
            end
        end
    end)

    hook.Add("PlayerSayTransform", "GRM_VehHP_Chat", function(ply, pack)
        if not istable(pack) then return end
        local t = string.lower(string.Trim(pack[1] or ""))
        if t ~= "/repair" and t ~= "/починить" and t ~= "/ремонт" then return end
        local tr = ply:GetEyeTrace()
        local ent = IsValid(tr.Entity) and root(tr.Entity)
        if ply:InVehicle() then ent = root(ply:GetVehicle()) end
        local ok, msg = H.TryRepair(ply, ent)
        if GRM.Notify then GRM.Notify(ply, msg, ok and 120 or 255, ok and 210 or 140, 90) end
        pack[1] = ""
        pack.SkipPlayerSay = true
    end)
    hook.Add("PlayerSay", "GRM_VehHP_ChatRaw", function(ply, text)
        local t = string.lower(string.Trim(tostring(text or "")))
        if t ~= "/repair" and t ~= "/починить" and t ~= "/ремонт" then return end
        local ent = ply:InVehicle() and root(ply:GetVehicle()) or (IsValid(ply:GetEyeTrace().Entity) and root(ply:GetEyeTrace().Entity))
        local ok, msg = H.TryRepair(ply, ent)
        if GRM.Notify then GRM.Notify(ply, msg, ok and 120 or 255, ok and 210 or 140, 90) end
        return ""
    end)

    hook.Add("Think", "GRM_VehHP_HoldBroken", function()
        if GRM.Perf and GRM.Perf.Throttle and not GRM.Perf.Throttle("vehhp.hold", 0.6) then return end
        local list = (GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()
        for i = 1, #list do
            local ply = list[i]
            if IsValid(ply) and ply:InVehicle() then
                local veh = root(ply:GetVehicle())
                if IsValid(veh) and veh:GetNWBool("GRM_VehBroken") then H.Break(veh) end
            end
        end
    end)

    H.Load()
    print("[GRM VehHP] server v" .. H.Version)
end
