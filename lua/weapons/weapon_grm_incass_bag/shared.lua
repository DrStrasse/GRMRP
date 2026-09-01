--[[--------------------------------------------------------------------
    weapon_grm_incass_bag — инкасс-чемодан в руке.
    Не оружие, не наносит урон, не стреляет. Просто модель чемодана
    в правой руке как индикатор того, что игрок несёт наличные из
    терминала в машину / из машины в вольт.

    Управление:
      • G на терминал — получить чемодан в руку (если у терминала есть
                       доступная сумма и есть активный рейс).
      • G на инкасс-машину — загрузить чемодан в багажник (сумма в carCash).
      • G на grm_bank_vault — сдать чемодан в хранилище (HeldCash +=).
      • Смена оружия/смерть — чемодан удаляется, деньги НЕ возвращаются
        (игрок должен доставить до конца).
----------------------------------------------------------------------]]

AddCSLuaFile()

SWEP.PrintName     = "Инкасс-чемодан"
SWEP.Author        = "GRM"
SWEP.Category      = "GRM — Инкассация"
SWEP.Instructions  = "G на терминал/машину/вольт"
SWEP.Spawnable     = false
SWEP.AdminOnly     = true

SWEP.ViewModel     = "models/weapons/c_arms_citizen.mdl"
SWEP.WorldModel    = "models/weapons/w_suitcase_passenger.mdl"
SWEP.UseHands      = true
SWEP.ViewModelFOV  = 60
SWEP.HoldType      = "pistol"

SWEP.Primary.ClipSize    = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic   = false
SWEP.Primary.Ammo        = "none"
SWEP.Secondary.ClipSize    = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic   = false
SWEP.Secondary.Ammo        = "none"

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
    self._grmAmount = 0
end

function SWEP:SetCarriedAmount(n) self._grmAmount = math.floor(tonumber(n) or 0) end
function SWEP:GetCarriedAmount() return math.floor(tonumber(self._grmAmount) or 0) end

function SWEP:Deploy()
    self:SetHoldType(self.HoldType)
    return true
end

function SWEP:Holster() return true end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 0.6)
    if CLIENT then return end

    local ply = self:GetOwner()
    if not IsValid(ply) or not ply:IsPlayer() then return end

    local tr = ply:GetEyeTrace()
    local hit = IsValid(tr.Entity) and tr.Entity or nil
    local pPos = ply:GetPos()

    -- 1. Сдача в хранилище банка (grm_bank_vault)
    local vault = (IsValid(hit) and hit:GetClass() == "grm_bank_vault") and hit or nil
    if not IsValid(vault) and GRM.Incass and GRM.Incass.FindNearestVault then
        vault = GRM.Incass.FindNearestVault(pPos, 300)
    end
    if IsValid(vault) and GRM.Incass and GRM.Incass.LoadBagIntoVault then
        GRM.Incass.LoadBagIntoVault(ply, vault)
        return
    end

    -- 2. Загрузка в инкассаторскую машину
    if IsValid(hit) and GRM.Incass and GRM.Incass.LoadBagIntoCar then
        local ok, _ = GRM.Incass.LoadBagIntoCar(ply, hit)
        if ok then return end
    end

    -- 3. Загрузка в банкомат
    if IsValid(hit) and hit:GetClass() == "grm_bank_terminal" and GRM.Incass and GRM.Incass.LoadBagIntoTerminal then
        GRM.Incass.LoadBagIntoTerminal(ply, hit)
        return
    end
end

function SWEP:SecondaryAttack() self:SetNextSecondaryFire(CurTime() + 0.5) end
function SWEP:Reload() end

-- При снятии/удалении — серверу убрать флаг переноски
function SWEP:OnRemove()
    if SERVER then
        local ply = self:GetOwner()
        if IsValid(ply) and ply:IsPlayer() then
            if ply.GRMIncassBagWeapon == self then ply.GRMIncassBagWeapon = nil end
            ply:SetNWEntity("GRMIncass_Bag", NULL)
            ply:SetNWBool("GRMIncass_Carrying", false)
            ply:SetNWInt("GRMIncass_BagAmount", 0)
        end
    end
end

if SERVER then
    function SWEP:Equip(ply)
        ply.GRMIncassBagWeapon = self
        ply:SetNWEntity("GRMIncass_Bag", self)
        ply:SetNWBool("GRMIncass_Carrying", true)
    end
end

if CLIENT then
    -- Отключить отображение viewmodel, чтобы не торчало оружие; игрок должен
    -- видеть только world-mdel в правой руке от третьего лица.
    function SWEP:PreDrawViewModel()
        return true
    end
end
