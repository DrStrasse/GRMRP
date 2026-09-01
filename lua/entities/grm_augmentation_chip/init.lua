AddCSLuaFile("shared.lua")
include("shared.lua")

function ENT:Initialize()
    self:SetModel("models/bull/gates/logic.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
    end

    self:SetImplanted(false)
end

function ENT:Use(activator, caller)
    if not IsValid(caller) or not caller:IsPlayer() then return end

    -- Если чип уже имплантирован, нельзя взять
    if self:GetImplanted() then
        caller:ChatPrint("[Аугментации] Этот чип уже имплантирован!")
        return
    end

    -- Получение данных чипа
    local chipId = self:GetChipID()
    local chipData = GRM.AugChips.ChipDatabase[chipId]

    if not chipData then
        caller:ChatPrint("[Аугментации] Ошибка: данные чипа не найдены!")
        return
    end

    -- Добавление чипа в инвентарь как предмет
    if GRM.Inventory and GRM.Inventory.AddItem then
        local remaining = GRM.Inventory.AddItem(caller, "augmentation_chip", 1, {
            chipId = chipId,
            chipName = chipData.name,
            chipCategory = chipData.category,
            chipLevel = chipData.level,
            chipModifiers = chipData.modifiers
        })

        if remaining > 0 then
            caller:ChatPrint("[Аугментации] Инвентарь полон! Невозможно подобрать чип.")
            return
        end

        caller:ChatPrint("[Аугментации] Чип добавлен в инвентарь: " .. chipData.name)
        caller:ChatPrint("[Аугментации] Используйте чип из инвентаря для имплантации.")
    else
        caller:ChatPrint("[Аугментации] Ошибка: система инвентаря недоступна!")
        return
    end

    -- Удаление физической модели
    self:Remove()
end

function ENT:OnRemove()
    -- Очистка при удалении
end
