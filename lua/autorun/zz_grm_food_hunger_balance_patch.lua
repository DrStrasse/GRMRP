--[[--------------------------------------------------------------------
    GRM Food Hunger Balance Patch

    Куда положить:
      garrysmod/addons/grm_food/lua/autorun/zz_grm_food_hunger_balance_patch.lua

    Что делает:
      Чуть ускоряет расход сытости: +0.5 к множителю, то есть x1.5.

    Было в конфиге обычно:
      HungerDrainPerSecond = 0.02

    С этим патчем станет:
      0.02 * 1.5 = 0.03

    Это не слишком быстро:
      100 сытости / 0.03 ≈ 55 минут до нуля без еды.
--------------------------------------------------------------------]]

if SERVER then
    AddCSLuaFile()
end

GRM = GRM or {}
GRM.Food = GRM.Food or {}
GRM.Food.Config = GRM.Food.Config or {}

GRM.Food.BalancePatch = GRM.Food.BalancePatch or {}

-- +0.5 к базовому множителю расхода, то есть x1.5.
GRM.Food.BalancePatch.HungerDrainMultiplier = 1.0

-- Базовое значение, от которого считаем баланс.
-- Если в основном конфиге другое значение, патч возьмёт его как базу.
local baseDrain = tonumber(GRM.Food.Config.HungerDrainPerSecond) or 0.02
local mult = tonumber(GRM.Food.BalancePatch.HungerDrainMultiplier) or 1.5

GRM.Food.Config.HungerDrainPerSecond = baseDrain * mult

print("[GRM Food] Hunger balance patch: HungerDrainPerSecond = " .. tostring(GRM.Food.Config.HungerDrainPerSecond) .. " (x" .. tostring(mult) .. ")")
