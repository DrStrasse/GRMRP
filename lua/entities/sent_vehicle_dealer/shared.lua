--[[--------------------------------------------------------------------
    sent_vehicle_dealer — shared.lua
    NPC-подобный дилер транспорта. Игрок подходит, нажимает [E],
    выбирает машину из списка — машина спавнится рядом.

    Поддерживает:
      • Фракционные списки транспорта (vehicles[faction] = {...})
      • Глобальный список (vehicles.__global = {...})
      • Хуки VD_PreSpawnCheck / VD_FilterVehicleList / VD_OnVehicleSpawned
      • Интеграцию с GRM_HasVehicleAccess через патч vehicle_dealer.lua
--------------------------------------------------------------------]]

ENT.Type           = "anim"
ENT.Base           = "base_gmodentity"
ENT.PrintName      = "Дилер транспорта"
ENT.Author         = "GRM System v3"
ENT.Category       = "GRM Vehicles"
ENT.Spawnable      = true
ENT.AdminSpawnable = true
ENT.RenderGroup    = RENDERGROUP_OPAQUE

--[[ АНТИ-Т-ПОЗА (заказ владельца 19.08).
     SetModel сбрасывает индекс последовательности в 0 («reference»), и NPC
     встаёт в Т-позу. Раньше idle применялся только при создании энтити, а
     каждое сохранение настроек/перезагрузка карты меняли модель — и дилер
     «раскидывал руки». Теперь анимация ставится ОДНОЙ функцией, и её зовут
     после каждой смены модели, плюс сторож в Think ловит остальные случаи. ]]
ENT.IdleSequences = {
    "idle_all_01", "idle_all", "idle_subtle", "idle_unarmed",
    "idle", "idle01", "pose_standing_01", "pose_standing_02", "stand",
}

function ENT:ApplyIdleAnimation(force)
    if not IsValid(self) then return false end
    local current = string.lower(tostring(self:GetSequenceName(self:GetSequence()) or ""))
    if not force and current ~= "" and current ~= "reference" and current ~= "ragdoll" then return true end

    for _, name in ipairs(self.IdleSequences) do
        local seq = self:LookupSequence(name)
        if seq and seq >= 0 and self:SequenceDuration(seq) > 0 then
            self:ResetSequence(seq)
            self:ResetSequenceInfo()
            self:SetCycle(0)
            self:SetPlaybackRate(1)
            self:SetAutomaticFrameAdvance(true)
            return true
        end
    end

    local seq = self:SelectWeightedSequence(ACT_IDLE)
    if seq and seq >= 0 then
        self:ResetSequence(seq)
        self:ResetSequenceInfo()
        self:SetCycle(0)
        self:SetPlaybackRate(1)
        self:SetAutomaticFrameAdvance(true)
        return true
    end
    return false
end

--- Смена модели без Т-позы: модель, затем анимация.
function ENT:ApplyDealerModel(model)
    model = tostring(model or "")
    if not util.IsValidModel(model) then return false end
    if self:GetModel() ~= model then self:SetModel(model) end
    if SERVER then self:SetDealerModel(model) end
    self:ApplyIdleAnimation(true)
    return true
end

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "DealerID")     -- уникальный ID дилера
    self:NetworkVar("String", 1, "DealerName")   -- отображаемое имя
    self:NetworkVar("String", 2, "DealerModel")  -- путь к модели дилера
    self:NetworkVar("Vector", 0, "SpawnPos")     -- точка спавна транспорта
    self:NetworkVar("Vector", 1, "SpawnZoneMin") -- зона безопасной выдачи
    self:NetworkVar("Vector", 2, "SpawnZoneMax")
    self:NetworkVar("Angle", 0, "SpawnAngle")    -- угол спавна транспорта
    self:NetworkVar("Bool", 0, "HasCustomSpawn") -- legacy-точка
    self:NetworkVar("Bool", 1, "HasSpawnZone")
end
