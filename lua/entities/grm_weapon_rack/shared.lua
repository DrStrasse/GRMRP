--[[ Оружейная стойка GRM: сущность-контейнер с ячейками.
     Вся логика хранения живёт в lua/autorun/sh_grm_weapon_rack.lua —
     здесь только сама сущность и её сетевые поля. ]]

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "GRM: Оружейная стойка"
ENT.Category = "GRM Faction Logistics"
ENT.Spawnable = true
ENT.AdminSpawnable = true

function ENT:SetupDataTables()
    -- Ключ записи в data/grm_weapon_racks.json.
    self:NetworkVar("String", 0, "RackID")
    self:NetworkVar("String", 1, "FactionName")
    self:NetworkVar("String", 2, "NetworkID")
    self:NetworkVar("Bool", 0, "FactionMode")
end
