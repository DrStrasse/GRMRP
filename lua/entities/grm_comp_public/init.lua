AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Use(ply)
    if not (IsValid(ply) and ply:IsPlayer()) then return end
    if GRM.PublicKiosk and isfunction(GRM.PublicKiosk.Open) then
        GRM.PublicKiosk.Open(ply, self)
    elseif GRM.ATM and isfunction(GRM.ATM.Open) then
        GRM.ATM.Open(ply, self)
    end
end
