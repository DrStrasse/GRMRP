--[[--------------------------------------------------------------------
    GRM Wardrobe (Код 73 — часть ядра персонажей Код 72)
    Энтити гардероба: игроки меняют внешность через меню персонажа,
    админ настраивает, ЧТО именно гардероб разрешает:
      - показывать гражданские модели   (allowCivilian)
      - показывать фракционные модели   (allowFaction)
      - разрешать настройку скинов      (allowSkin)
      - разрешать настройку бодигрупп   (allowBodygroups)
      - особые модели только этого шкафа (cfg.extraModels: {path,...})
      - скрытые модели                  (cfg.hiddenModels: {path,...})
    Конфиг хранится на сервере: data/grm_wardrobes_<map>.json (по позиции).
----------------------------------------------------------------------]]

ENT.Type      = "anim"
ENT.Base      = "base_gmodentity"
ENT.PrintName = "Гардероб GRM"
ENT.Author    = "GRM"
ENT.Category  = "GRM — RP"
ENT.Spawnable = true
ENT.AdminOnly = true

ENT.Model = "models/props_wasteland/controlroom_storagecloset001a.mdl"
-- запасная модель, если основная у клиента отсутствует (проверяется в Initialize)
ENT.ModelFallback = "models/props_c17/FurnitureLocker001a.mdl"

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "Civilian")  -- 0/1
    self:NetworkVar("Int", 1, "Faction")
    self:NetworkVar("Int", 2, "Skin")
    self:NetworkVar("Int", 3, "Bodygroups")
end
