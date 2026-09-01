AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

function ENT:Initialize()
    local mdl = self.Model
    if not util.IsValidModel(mdl) then mdl = self.ModelFallback end
    self:SetModel(mdl)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
        --[[ Шкаф не должен ездить по квартире от толчков: это мебель,
             а не ящик. Замороженный он ещё и не проваливается сквозь
             пол на перегруженной карте. ]]
        phys:EnableMotion(false)
    end

    self:SetTotalSlots(GRM.HomeStorage and GRM.HomeStorage.MaxSlots or 30)
    self:UpdateFill()
end

--[[ Обновить подпись «занято слотов». Зовётся при открытии и после
     каждого перекладывания — но сама операция дешёвая, потому что
     считает только непустые слоты уже загруженной таблицы. ]]
function ENT:UpdateFill()
    local ST = GRM.HomeStorage
    if not ST then return end
    local rec = ST.PropertyOf and ST.PropertyOf(self)
    if not rec then
        self:SetUsedSlots(-1)   -- -1 = шкаф вне зоны жилья, показываем предупреждение
        return
    end
    local slots = ST.SlotsFor and ST.SlotsFor(rec)
    self:SetUsedSlots(slots and ST.UsedSlots(slots) or 0)
end

function ENT:Use(activator)
    if not (IsValid(activator) and activator:IsPlayer()) then return end
    local ST = GRM.HomeStorage
    if not (ST and ST.Open) then return end
    -- Антиспам: E зажимают, окно не должно пересоздаваться каждый тик.
    if (self._grmNextUse or 0) > CurTime() then return end
    self._grmNextUse = CurTime() + 0.6
    if ST.Open(activator, self) then
        self:EmitSound("items/ammocrate_open.wav", 65, 105)
        self:UpdateFill()
    end
end

function ENT:OnRemove()
    local ST = GRM.HomeStorage
    if ST and istable(ST.Viewers) and istable(ST.Viewers[self]) then
        for ply in pairs(ST.Viewers[self]) do
            if IsValid(ply) and ST.Close then ST.Close(ply, self) end
        end
        ST.Viewers[self] = nil
    end
end
