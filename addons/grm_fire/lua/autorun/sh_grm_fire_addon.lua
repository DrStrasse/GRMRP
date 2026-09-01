--[[--------------------------------------------------------------------
    GRM Fire Addon — маркер + тонкий API сущностей.
    Не зависит от GRM. Серверный скрипт GRM смотрит GRM_FireAddon / vFireInstalled.
----------------------------------------------------------------------]]
if SERVER then AddCSLuaFile() end

GRM_FireAddon = true
GRM = GRM or {}
GRM.FireAddon = GRM.FireAddon or {}
local A = GRM.FireAddon
A.Version = "0.5.0"

if SERVER then
    if file.Exists("materials/grm/firehose.vmt", "GAME") then
        resource.AddFile("materials/grm/firehose.vmt")
    end
end

A.Models = {
    hydrant  = { "models/props/cs_assault/FireHydrant.mdl", "models/props_pipes/valvewheel001.mdl" },
    cabinet  = { "models/props/cs_office/fire_extinguisher.mdl", "models/props_c17/canister01a.mdl" },
    coil     = { "models/props/cs_assault/wirepipe.mdl", "models/props_c17/GasPipes006a.mdl" },
    pump     = { "models/props_lab/tpplugholder_single.mdl" },
    junction = { "models/props_lab/tpplugholder_single.mdl" },
    nozzle   = { "models/props/cs_assault/wirespout.mdl", "models/props_canal/mattpipe.mdl" },
    detector = { "models/props/cs_office/smoke_detector.mdl", "models/props_lab/reciever01c.mdl" },
    ladder   = { "models/props/de_train/ladderaluminium.mdl", "models/props_c17/metalladder002.mdl", "models/props_c17/metalladder001.mdl" },
    spot     = { "models/props_junk/PopCan01a.mdl" },
}

function A.SafeModel(list)
    list = istable(list) and list or { tostring(list or "") }
    for i = 1, #list do
        local m = list[i]
        if isstring(m) and m ~= "" and util.IsValidModel(m) then return m end
    end
    return "models/hunter/blocks/cube025x025x025.mdl"
end

function A.IsWaterSource(ent)
    if not IsValid(ent) then return false end
    local cls = ent:GetClass()
    if cls == "grm_fire_hydrant" then
        return ent.GetOpen and ent:GetOpen() == true
    end
    if cls == "grm_fire_pump" then
        if not (ent.GetPumpOn and ent:GetPumpOn()) then return false end
        if ent.GetHydrantFeed and ent:GetHydrantFeed() then return true end
        local ag = ent.GetAgent and ent:GetAgent() or "water"
        if ag == "foam" then return (ent.GetFoam and ent:GetFoam() or 0) > 0 end
        if ag == "powder" then return (ent.GetPowder and ent:GetPowder() or 0) > 0 end
        return (ent.GetTank and ent:GetTank() or 0) > 0
    end
    return false
end

function A.GiveExtinguisher(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return false end
    if ply:HasWeapon("weapon_extinguisher") then return true end
    ply:Give("weapon_extinguisher")
    return ply:HasWeapon("weapon_extinguisher")
end

function A.GiveHose(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return false end
    if SERVER and IsValid(ply.GRM_FireHose) then return true end
    if ply:HasWeapon("weapon_grm_hose") then return true end
    ply:Give("weapon_grm_hose")
    return ply:HasWeapon("weapon_grm_hose")
end

function A.Refill(ply, amount)
    if not IsValid(ply) or not ply:IsPlayer() then return false end
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount <= 0 then return false end
    local function add(name, cap)
        local id = game.GetAmmoID(name)
        if not id or id < 0 then return end
        local have = ply:GetAmmoCount(id) or 0
        ply:SetAmmo(math.min(cap, have + amount), id)
    end
    add("firehose_water", 1000)
    add("rb655_extinguisher", 1000)
    return true
end

function A.Ready()
    return vFireInstalled == true
end

-- Лазание по выдвинутой лестнице (без физики пропа).
hook.Add("SetupMove", "GRM_FireLadder_Climb", function(ply, mv)
    if not IsValid(ply) or not ply:Alive() then return end
    if ply.InVehicle and ply:InVehicle() then return end
    -- SetupMove вызывается КАЖДЫЙ тик на КАЖДОГО игрока. Полный скан класса
    -- здесь стоил дороже самой механики лазания — берём event-реестр
    -- GRM.Perf и выходим сразу, если выдвинутых лестниц на карте нет.
    local ladders = (GRM and GRM.Perf and GRM.Perf.Entities) and GRM.Perf.Entities("grm_fire_ladder")
        or ents.FindByClass("grm_fire_ladder")
    if #ladders == 0 then return end
    local pos = ply:GetPos()
    local best, bestD, a, b
    for _, ent in ipairs(ladders) do
        if IsValid(ent) and ent.GetDeployed and ent:GetDeployed() and ent.LadderSegment then
            local p0, p1 = ent:LadderSegment()
            local ab = p1 - p0
            local denom = ab:LengthSqr()
            if denom > 1 then
                local t = math.Clamp((pos - p0):Dot(ab) / denom, 0, 1)
                local near = p0 + ab * t
                local d = pos:DistToSqr(near)
                if d < 46 * 46 and (not best or d < bestD) then
                    best, bestD, a, b = ent, d, p0, p1
                end
            end
        end
    end
    if not IsValid(best) then return end
    local dir = (b - a)
    if dir:LengthSqr() < 1 then return end
    dir:Normalize()
    local wish = 0
    if mv:KeyDown(IN_FORWARD) or mv:KeyDown(IN_JUMP) then wish = 190
    elseif mv:KeyDown(IN_BACK) then wish = -170 end
    local look = ply:GetAimVector():Dot((b - pos):GetNormalized())
    if wish == 0 then
        if not ply:OnGround() and bestD < 36 * 36 then
            mv:SetVelocity(Vector(0, 0, 8))
        end
        return
    end
    if wish > 0 and ply:OnGround() and look < 0.08 then return end
    mv:SetVelocity(dir * wish)
end)

if SERVER then
    print("[GRM Fire Addon] v" .. A.Version .. " loaded (ТС сняли — рукава/насос сразу; огонь = vFire)")
end
