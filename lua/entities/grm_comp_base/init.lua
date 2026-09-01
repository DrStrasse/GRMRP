--[[--------------------------------------------------------------------
    grm_comp_base — серверная часть базы служебных компьютеров.
----------------------------------------------------------------------]]
AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    -- Модель проверяем до установки: отсутствующая в контенте модель даёт
    -- ошибку и «невидимый» компьютер, поэтому у каждой станции есть
    -- запасная из базового HL2/CSS-контента.
    local mdl = self.Model
    if not util.IsValidModel(mdl) then mdl = self.ModelFallback end
    self:SetModel(mdl)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    -- Имя могло быть задано инструментом «GRM Служебное оборудование»
    -- ДО Initialize — перезаписывать его нельзя.
    if self:GetComputerName() == "" and self.DefaultComputerName ~= "" then
        self:SetComputerName(self.DefaultComputerName)
    end

    self:OnCompInit()

    -- Компьютер не должен уезжать от толчка игрока или взрыва.
    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
        phys:EnableMotion(false)
    end
end

--- Точка расширения для станции (доп. поля, таймеры). По умолчанию пусто.
function ENT:OnCompInit()
end
