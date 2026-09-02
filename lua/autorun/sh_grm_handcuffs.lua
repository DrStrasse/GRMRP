--[[--------------------------------------------------------------------
    GRM Handcuffs — общая часть: проверка «машиноподобности» цели.
    Клиент и сервер держали по копии этого же тела (и она начала бы
    разъезжаться); теперь определение одно, обе стороны берут алиас
    (§5.4 п.12).
----------------------------------------------------------------------]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Handcuffs = GRM.Handcuffs or {}

function GRM.Handcuffs.IsVehicleLike(ent)
    if not IsValid(ent) then return false end
    if ent:IsVehicle() then return true end

    local class = string.lower(ent:GetClass() or "")
    if string.find(class, "sim_fphys", 1, true) then return true end
    if string.find(class, "lvs", 1, true) then return true end
    if string.find(class, "gmod_sent_vehicle", 1, true) then return true end

    for _, child in ipairs(ent:GetChildren()) do
        if IsValid(child) and child:IsVehicle() then return true end
    end

    return false
end
