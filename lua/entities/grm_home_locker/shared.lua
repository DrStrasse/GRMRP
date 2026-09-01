--[[--------------------------------------------------------------------
    grm_home_locker — домашний шкаф (жильё, фаза 2).

    Ставится ВНУТРИ квартиры. Владельца сам не хранит: принадлежит тому
    объекту недвижимости, в чьей зоне стоит (см. GRM.HomeStorage.PropertyOf).
    Так продажа квартиры автоматически передаёт шкаф новому хозяину.
----------------------------------------------------------------------]]

ENT.Type      = "anim"
ENT.Base      = "base_gmodentity"
ENT.PrintName = "Домашний шкаф"
ENT.Author    = "GRM"
ENT.Category  = "GRM — RP"
ENT.Spawnable = true
ENT.AdminOnly = true

ENT.Model = "models/props_c17/FurnitureCabinet001a.mdl"
-- Запасная модель: если основной нет у клиента, шкаф не должен стать ошибкой.
ENT.ModelFallback = "models/props_wasteland/controlroom_storagecloset001a.mdl"

function ENT:SetupDataTables()
    --[[ Заполненность гоняем через DataTable, а не через частые NW-строки:
         подпись на шкафу обновляется у всех, кто рядом, без своей сети. ]]
    self:NetworkVar("Int", 0, "UsedSlots")
    self:NetworkVar("Int", 1, "TotalSlots")
end
