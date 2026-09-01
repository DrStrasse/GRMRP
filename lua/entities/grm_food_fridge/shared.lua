--[[--------------------------------------------------------------------
    grm_food_fridge — Холодильник. Код 110, заказ владельца.
    Модель заказана: models/props_c17/furniturefridge001a.mdl
    [E] → окно: Положить/Забрать. Срок годности убранной приготовленной
    еды ЗАМОРАЖИВАЕТСЯ (хранится как остаток секунд) и не портится внутри.
----------------------------------------------------------------------]]

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Холодильник"
ENT.Category = "GRM Food"
ENT.Spawnable = true
ENT.AdminSpawnable = true

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "FridgeCount") -- занятых слотов (для таблички)
end

function ENT:KitchenCfg()
    return (GRM and GRM.FoodKitchen and GRM.FoodKitchen.Cfg and GRM.FoodKitchen.Cfg()) or {}
end
