AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

function ENT:Initialize()
    -- Камера является невидимой точкой конфигурации. Физическая модель
    -- намеренно не создаётся: визуальный маркер камеры больше не нужен.
    self:SetNoDraw(true)
    self:SetMoveType(MOVETYPE_NONE)
    self:SetSolid(SOLID_NONE)
    self:SetUseType(SIMPLE_USE)
end

function ENT:Use(ply)
    if IsValid(ply) and ply:IsSuperAdmin() then
        if GRM and GRM.Arrest and GRM.Arrest.OpenAdmin then GRM.Arrest.OpenAdmin(ply) end
    end
end
