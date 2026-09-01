--[[--------------------------------------------------------------------
    GRM Money Printer v2.1.0 — shared
----------------------------------------------------------------------]]

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Денежный принтер"
ENT.Author = "GRM"
ENT.Category = "GRM — RP"
ENT.Spawnable = true
ENT.AdminSpawnable = true
ENT.RenderGroup = RENDERGROUP_BOTH

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "Printed")
    self:NetworkVar("Int", 1, "MaxMoney")
    self:NetworkVar("Int", 2, "Heat")
    self:NetworkVar("Int", 3, "PrinterHealth")
    self:NetworkVar("Int", 4, "PrintAmount")
    self:NetworkVar("Int", 5, "PrintInterval")
    self:NetworkVar("Bool", 0, "Active")
    self:NetworkVar("Bool", 1, "Broken")
    self:NetworkVar("String", 0, "OwnerSID64")
    self:NetworkVar("String", 1, "OwnerName")
end
