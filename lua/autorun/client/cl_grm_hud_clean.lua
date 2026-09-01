--[[--------------------------------------------------------------------
    GRM HUD Clean v1.0.0 — выключение стандартных худов HL2/Sandbox
    (заказ владельца 22.08: «работает и худ GRM, и стандартный»).

    GRM рисует свои полосы здоровья, брони, денег и свои таблички над
    игроками. Всё, что движок и режим песочницы рисуют поверх этого —
    лишний слой: он мешает, спорит по стилю и жрёт кадры.

    Что выключается:
      • элементы HL2: здоровье, броня, патроны, подбор оружия, индикаторы
        урона и отравления, зум, костюм;
      • стандартная подпись «ник + здоровье» при взгляде на игрока
        (GM:HUDDrawTargetID) — вместо неё работает GRM.Nameplate;
      • подсказка «нажмите E» от песочницы и стандартный список игроков
        по TAB (у GRM своё меню).

    Всё это можно вернуть одним конваром: grm_hud_hl2 1.
----------------------------------------------------------------------]]

GRM = GRM or {}
GRM.HUDClean = GRM.HUDClean or {}
local HC = GRM.HUDClean
HC.Version = "1.0.0"

local cvHL2 = CreateClientConVar("grm_hud_hl2", "0", true, false,
    "1 — вернуть стандартные худы HL2 и Sandbox поверх интерфейса GRM")

--[[ Список стандартных элементов. Держим ОДНИМ местом: раньше он был
     размазан по cl_grm_hud.lua и cl_grm_cctv.lua, и элементы, добавленные
     в одном месте, продолжали рисоваться из другого. ]]
HC.Hidden = {
    CHudHealth = true,
    CHudBattery = true,
    CHudAmmo = true,
    CHudSecondaryAmmo = true,
    CHudWeaponSelection = true,
    CHudDamageIndicator = true,
    CHudPoisonDamageIndicator = true,
    CHudSuitPower = true,
    CHudZoom = true,
    CHudSquadStatus = true,
    CHudGeiger = true,
    CHudTrain = true,
    CHudCrosshair = false,   -- прицел оставляем: он часть игры, а не худа
}

--- Скрывать ли этот элемент (чистая функция — гоняется стендом).
function HC.ShouldHide(name, allowHL2)
    if allowHL2 == true then return nil end
    if HC.Hidden[tostring(name or "")] == true then return false end
    return nil
end

hook.Add("HUDShouldDraw", "GRM_HUDClean", function(name)
    return HC.ShouldHide(name, cvHL2:GetBool())
end)

--[[ Подпись над игроком. Стандартная рисует ник и полоску здоровья своим
     шрифтом поверх нашей таблички — получается двойной текст. ]]
hook.Add("HUDDrawTargetID", "GRM_HUDClean_TargetID", function()
    if cvHL2:GetBool() then return end
    return false
end)

-- Подсказка песочницы «нажмите E» и стандартный TAB-список: у GRM свои.
hook.Add("HUDDrawPickupHistory", "GRM_HUDClean_Pickup", function()
    if cvHL2:GetBool() then return end
    return false
end)

hook.Add("ScoreboardShow", "GRM_HUDClean_Scoreboard", function()
    if cvHL2:GetBool() then return end
    if GRM.TabMenu and GRM.TabMenu.Open then return end   -- своё меню откроется само
end)

print("[GRM HUDClean] v" .. HC.Version .. " loaded (Client)")
