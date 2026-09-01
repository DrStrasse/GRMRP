--[[--------------------------------------------------------------------
    grm_food_planter — Горшок (выращивание овощей). Код 110.
    Пустой → [Е] → выбор культуры, списываются деньги за семена →
    растёт growSeconds → урожай crop.yield штук сырья. Полив раз в
    WaterCooldown сек срезает WaterBoost доли оставшегося времени.
----------------------------------------------------------------------]]

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Горшок (грядка)"
ENT.Category = "GRM Food"
ENT.Spawnable = true
ENT.AdminSpawnable = true

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "PlanterState")  -- 0 пусто, 1 растёт, 2 готово
    self:NetworkVar("Int", 1, "PlanterFinish") -- unix-время созревания
    self:NetworkVar("Int", 2, "PlanterWater")  -- unix-время разрешённого полива
    self:NetworkVar("String", 0, "PlanterCrop")
end

function ENT:KitchenCfg()
    return (GRM and GRM.FoodKitchen and GRM.FoodKitchen.Cfg and GRM.FoodKitchen.Cfg()) or {}
end
