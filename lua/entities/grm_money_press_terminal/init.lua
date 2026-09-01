--[[--------------------------------------------------------------------
    grm_money_press_terminal — init (находка 178)
----------------------------------------------------------------------]]
AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

util.AddNetworkString("GRM_PressTerminal_Open")
util.AddNetworkString("GRM_PressTerminal_Action")

function ENT:Initialize()
    local mdl = self.Model
    if not util.IsValidModel(mdl) then
        mdl = self.ModelFallback
        print("[GRM Press Terminal] ВНИМАНИЕ: модель не найдена, фолбэк '" .. tostring(mdl) .. "'")
    end
    self:SetModel(mdl)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then phys:Wake() phys:EnableMotion(false) end
end

local function notify(ply, msg, r, g, b)
    if IsValid(ply) and GRM and GRM.Notify then
        GRM.Notify(ply, msg, r or 200, g or 200, b or 200)
    end
end

-- ближайший станок к терминалу
function ENT:FindPress()
    if not (GRM and GRM.MoneyPress) then return nil end
    local best, bestD = nil, math.huge
    for _, p in pairs(GRM.MoneyPress) do
        if IsValid(p) then
            local d = self:GetPos():DistToSqr(p:GetPos())
            if d < bestD then best, bestD = p, d end
        end
    end
    if bestD <= (self.PressSearchRadius * self.PressSearchRadius) then return best end
    return nil
end

function ENT:CanManage(ply)
    if not IsValid(ply) then return false end
    if ply:IsSuperAdmin() then return true end
    return GRM.Economy and GRM.Economy.CanManageEconomy and GRM.Economy.CanManageEconomy(ply) == true
end

function ENT:SendMenu(ply, press)
    if not IsValid(ply) then return end
    press = press or self:FindPress()
    if not IsValid(press) then
        net.Start("GRM_PressTerminal_Open")
            net.WriteEntity(self)
            net.WriteBool(false) -- станка нет
            net.WriteEntity(NULL)
        net.Send(ply)
        return
    end
    net.Start("GRM_PressTerminal_Open")
        net.WriteEntity(self)
        net.WriteBool(true)
        net.WriteEntity(press)
        net.WriteTable({
            active = press:GetActive(),
            broken = press:GetBroken(),
            heat = press:GetHeat(),
            speedLevel = press:GetSpeedLevel(),
            printAmount = press:GetPrintAmount(),
            printInterval = press:GetPrintInterval(),
            totalPrinted = press:GetTotalPrinted(),
            buffer = press:GetBuffer(),
            upgradeCost = press.UpgradeBaseCost * (math.floor(press:GetSpeedLevel() or 0) + 1),
            coolCost = press.CoolCost,
            maxSpeedLevel = press.MaxSpeedLevel,
        })
    net.Send(ply)
end

function ENT:Use(ply)
    if not IsValid(ply) then return end
    if not self:CanManage(ply) then
        notify(ply, "Терминал банка. Доступ: сотрудники с правом экономики.", 200, 200, 120)
        return
    end
    self:SendMenu(ply)
end

net.Receive("GRM_PressTerminal_Action", function(_, ply)
    if not IsValid(ply) then return end
    local term = net.ReadEntity()
    local action = net.ReadString()
    local press = net.ReadEntity()
    if not IsValid(term) or term:GetClass() ~= "grm_money_press_terminal" then return end
    if not term:CanManage(ply) then notify(ply, "Нет доступа к терминалу банка.", 255, 100, 100) return end
    -- станок должен быть ближайшим к терминалу (анти-чит)
    local found = term:FindPress()
    if not IsValid(press) or press ~= found then
        notify(ply, "Станок не найден рядом с терминалом.", 255, 140, 80)
        return
    end
    if ply:GetPos():DistToSqr(term:GetPos()) > 200 * 200 then return end

    if action == "toggle" then press:PressToggle(ply)
    elseif action == "upgrade" then press:PressUpgrade(ply)
    elseif action == "cool" then press:PressCool(ply)
    end
    term:SendMenu(ply, press)
end)

print("[GRM] Press Terminal entity loaded (находка 178)")
