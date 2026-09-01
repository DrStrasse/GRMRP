--[[--------------------------------------------------------------------
    grm_food_stove — Плита (готовка). Код 110, заказ владельца.
    Модель заказана: models/props_c17/furniturestove001a.mdl
    [E] → окно плиты (cl_grm_food_kitchen): выбор рецепта с живой
    проверкой ингредиентов, прогресс готовки, выходной лоток.
----------------------------------------------------------------------]]

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Плита (готовка)"
ENT.Category = "GRM Food"
ENT.Spawnable = true
ENT.AdminSpawnable = true

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "StoveState")   -- 0 свободна, 1 готовит
    self:NetworkVar("Int", 1, "StoveFinish")  -- unix-время готовности
    self:NetworkVar("Int", 2, "StoveReady")   -- блюд на выходном лотке
    --[[ Момент начала готовки. Нужен для честного прогресс-бара НАД
         плитой: без него клиент знает только «сколько осталось» и не
         может посчитать долю — за 10 секунд до конца бар выглядел бы
         одинаково и для минутного, и для часового рецепта.

         Время начала, а не длительность: длительность рецепта админ
         может поменять на ходу, а начало — факт. ]]
    self:NetworkVar("Int", 3, "StoveStart")
    --[[ Занятость четырёх конфорок битовой маской: 4 бита в одном поле
         вместо четырёх NetworkVar. Клиент по ней подсвечивает кубики. ]]
    self:NetworkVar("Int", 4, "StoveSlots")
    self:NetworkVar("String", 0, "StoveRecipe")
end

--[[ Доля готовности 0..1. Общая для 3D2D-таблички и любого другого
     потребителя — чтобы прогресс считался в ОДНОМ месте и не разъезжался
     между окном и плитой. ]]
function ENT:StoveProgress()
    if self:GetStoveState() ~= 1 then return 0 end
    local a = tonumber(self:GetStoveStart()) or 0
    local b = tonumber(self:GetStoveFinish()) or 0
    local total = b - a
    if total <= 0 then return 0 end
    local left = b - os.time()
    return math.Clamp(1 - (left / total), 0, 1)
end

function ENT:KitchenCfg()
    return (GRM and GRM.FoodKitchen and GRM.FoodKitchen.Cfg and GRM.FoodKitchen.Cfg()) or {}
end
