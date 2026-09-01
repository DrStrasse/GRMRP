AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

--- Модель стойки: обычный оружейный шкаф, вписывается в логистику.
ENT.RackModel = "models/props_c17/lockers001a.mdl"

function ENT:Initialize()
    self:SetModel(self.RackModel)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
        -- Стойка не должна улетать от толчка: это часть интерьера базы.
        phys:EnableMotion(false)
    end

    if self:GetRackID() == "" then
        self:SetRackID("rack_" .. self:EntIndex() .. "_" .. math.floor(CurTime() * 100))
    end
    if self:GetFactionMode() == nil then self:SetFactionMode(true) end
end

function ENT:Use(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if GRM.WeaponRack and GRM.WeaponRack.Open then
        GRM.WeaponRack.Open(ply, self)
    end
end

--[[ PERM-DATA: стойка переживает рестарт вместе с настройками.
     Содержимое ячеек лежит в своём файле по RackID, поэтому здесь
     сохраняем только привязку сущности. ]]
function ENT:GetPermData()
    return {
        rackID = self:GetRackID(),
        factionName = self:GetFactionName(),
        networkID = self:GetNetworkID(),
        factionMode = self:GetFactionMode(),
    }
end

function ENT:SetPermData(d)
    if not istable(d) then return end
    if isstring(d.rackID) and d.rackID ~= "" then self:SetRackID(d.rackID) end
    self:SetFactionName(tostring(d.factionName or ""))
    self:SetNetworkID(tostring(d.networkID or ""))
    self:SetFactionMode(d.factionMode ~= false)
end
