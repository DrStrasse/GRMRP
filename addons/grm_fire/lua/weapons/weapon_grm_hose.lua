--[[--------------------------------------------------------------------
    Ствол пожарного рукава. Работает только если рукав подключён и есть напор.
    ЛКМ — лить. ПКМ — бросить/поднять ствол (линия остаётся). R — узел-тройник.
----------------------------------------------------------------------]]
AddCSLuaFile()

SWEP.PrintName = "Пожарный рукав"
SWEP.Author = "GRM"
SWEP.Category = "GRM Fire"
SWEP.Instructions = "ЛКМ: лить  ПКМ: бросить  R: узел  S/назад/ALT: смотка  E на насос: свернуть"
SWEP.Spawnable = true
SWEP.AdminOnly = false
SWEP.UseHands = true

SWEP.ViewModel = "models/weapons/c_firehose_grm.mdl"
SWEP.WorldModel = "models/weapons/w_firehose_grm.mdl"
if not util.IsValidModel(SWEP.ViewModel) then
    SWEP.ViewModel = "models/weapons/c_slam.mdl"
end
if not util.IsValidModel(SWEP.WorldModel) then
    SWEP.WorldModel = "models/props_canal/mattpipe.mdl"
end
SWEP.ViewModelFOV = 90
SWEP.HoldType = "shotgun"

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = true
SWEP.Primary.Ammo = "none"
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
end

local function hoseOf(ply)
    return IsValid(ply) and ply.GRM_FireHose or nil
end

function SWEP:Deploy()
    self:SendWeaponAnim(ACT_VM_DRAW)
    return true
end

function SWEP:Holster()
    if SERVER and self.Sound then self.Sound:Stop() self.Sound = nil end
    return true
end

function SWEP:OnRemove()
    if SERVER and self.Sound then self.Sound:Stop() self.Sound = nil end
end

function SWEP:OnDrop()
    if SERVER and self.Sound then self.Sound:Stop() self.Sound = nil end
    if not SERVER then return end
    local ply = self:GetOwner()
    if not IsValid(ply) then return end
    local hose = ply.GRM_FireHose
    if IsValid(hose) then hose:DropNozzle() end
end

function SWEP:DoSprayEffect()
    local owner = self:GetOwner()
    if not IsValid(owner) then return end
    local ed = EffectData()
    ed:SetAttachment(1)
    ed:SetEntity(owner)
    ed:SetOrigin(owner:GetShootPos())
    ed:SetNormal(owner:GetAimVector())
    ed:SetScale(1.15)
    util.Effect("fire_hose_effect", ed)
end

function SWEP:PrimaryAttack()
    if self:GetNextPrimaryFire() > CurTime() then return end
    self:SetNextPrimaryFire(CurTime() + 0.09)
    local ply = self:GetOwner()
    if not IsValid(ply) then return end

    if CLIENT then
        if ply == LocalPlayer() then self:DoSprayEffect() end
        return
    end

    local hose = hoseOf(ply)
    if not IsValid(hose) then
        if GRM and GRM.Notify then GRM.Notify(ply, "Рукав не подключён.", 255, 160, 80) end
        return
    end
    hose:RefreshPressure()
    if not hose:GetPressurized() then
        if (self._DryWarn or 0) < CurTime() then
            self._DryWarn = CurTime() + 1.6
            if GRM and GRM.Notify then
                GRM.Notify(ply, "Нет напора: откройте гидрант или включите насос.", 255, 170, 80)
            else
                ply:ChatPrint("[Рукав] Нет напора.")
            end
        end
        return
    end

    local pump = hose:SupplyPump()
    local cfg = GRM.FireAddon and GRM.FireAddon.HoseCfg or {}
    local agent = "water"
    if IsValid(pump) and pump.GetAgent then
        agent = pump:GetAgent()
        if agent == "" then agent = "water" end
    end
    local cost = cfg.SprayCostWater or cfg.SprayCost or 8
    local dmg = cfg.SprayDmgWater or cfg.SprayDmg or 10
    if agent == "foam" then
        cost = cfg.SprayCostFoam or 4
        dmg = cfg.SprayDmgFoam or 18
    elseif agent == "powder" then
        cost = cfg.SprayCostPowder or 2
        dmg = cfg.SprayDmgPowder or 24
    end
    if IsValid(pump) and pump.Consume then
        if not pump:Consume(cost, agent) then
            if GRM and GRM.Notify then GRM.Notify(ply, "Бак («" .. agent .. "») пуст. G — панель насоса.", 255, 140, 80) end
            return
        end
    end

    if not self.Sound then
        self.Sound = CreateSound(ply, "weapons/extinguisher/fire1.wav")
        self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
    end
    if self.Sound then self.Sound:Play() end

    local tr = ply:GetEyeTrace()
    local pos = tr.HitPos
    local dmg = (GRM.FireAddon.HoseCfg and GRM.FireAddon.HoseCfg.SprayDmg) or 10
    for _, ent in ipairs(ents.FindInSphere(pos, 110)) do
        if IsValid(ent) and ply:GetPos():Distance(ent:GetPos()) <= 420 then
            if vFireIsVFireEnt and vFireIsVFireEnt(ent) and ent.SoftExtinguish then
                ent:SoftExtinguish(dmg)
                if ent.Prioritize then ent:Prioritize(2) end
            elseif ent:IsOnFire() then
                ent:Extinguish()
            end
        end
    end
    self:DoSprayEffect()
end

function SWEP:SecondaryAttack()
    if self:GetNextSecondaryFire() > CurTime() then return end
    self:SetNextSecondaryFire(CurTime() + 0.45)
    if CLIENT then return end
    local ply = self:GetOwner()
    local hose = hoseOf(ply)
    if not IsValid(hose) then return end
    hose:DropNozzle()
end

function SWEP:Reload()
    if (self._NextJ or 0) > CurTime() then return end
    self._NextJ = CurTime() + 0.6
    if CLIENT then return end
    local ply = self:GetOwner()
    local hose = hoseOf(ply)
    if not IsValid(hose) then return end
    if not hose:PlaceJunction(ply) then
        if GRM and GRM.Notify then GRM.Notify(ply, "Узел: отойдите от источника (нужна укладка).", 255, 180, 90) end
    elseif GRM and GRM.Notify then
        GRM.Notify(ply, "Узел поставлен. E — взять второй рукав или стыковать другой.", 120, 220, 140)
    end
end

function SWEP:Think()
    if CLIENT then return end
    local ply = self:GetOwner()
    if not IsValid(ply) then return end
    if self.Sound and self.Sound:IsPlaying() and not ply:KeyDown(IN_ATTACK) then
        self.Sound:Stop()
        self.Sound = nil
        self:EmitSound("weapons/extinguisher/release1.wav", 70, math.random(95, 110))
        self:SendWeaponAnim(ACT_VM_IDLE)
    end
end

if CLIENT then
    surface.CreateFont("GRMHose_HUD", { font = "Roboto", size = 17, weight = 700, extended = true })
    function SWEP:DrawHUD()
        local ply = self:GetOwner()
        if not IsValid(ply) then return end
        local hose = ply.GRM_FireHose
        if not IsValid(hose) and ply.GetNW2Entity then hose = ply:GetNW2Entity("GRM_FireHose") end
        if not IsValid(hose) then
            for _, h in ipairs(ents.FindByClass("grm_fire_hose")) do
                if IsValid(h) and h.GetHolder and h:GetHolder() == ply then hose = h break end
            end
        end
        local x, y = ScrW() / 2, ScrH() * 0.78
        if not IsValid(hose) then
            draw.SimpleText("рукав не подключён — E на гидрант / насос", "GRMHose_HUD", x, y, Color(230, 180, 90), TEXT_ALIGN_CENTER)
            return
        end
        local laid = hose:GetLaidLen() or 0
        local maxl = hose:GetMaxLen() or 2200
        local press = hose:GetPressurized()
        local col = press and Color(90, 210, 255) or Color(255, 170, 80)
        local tankTxt = ""
        local pump = hose.GetStartEnt and hose:GetStartEnt() or NULL
        if not (IsValid(pump) and pump:GetClass() == "grm_fire_pump") then
            local endN = hose.GetEndNode and hose:GetEndNode() or NULL
            pump = IsValid(endN) and endN.GetParent and endN:GetParent() or NULL
        end
        if IsValid(pump) and pump.GetTank then
            local ag = (pump.GetAgent and pump:GetAgent()) or "water"
            if ag == "" then ag = "water" end
            local have, mx
            if ag == "foam" then have, mx = pump:GetFoam(), pump:GetFoamMax()
            elseif ag == "powder" then have, mx = pump:GetPowder(), pump:GetPowderMax()
            else have, mx = pump:GetTank(), pump:GetTankMax() end
            tankTxt = string.format("   %s %d/%d л", ag == "foam" and "пена" or (ag == "powder" and "порошок" or "вода"), have or 0, mx or 0)
        end
        draw.SimpleText(
            string.format("%s%s   %d / %d юн   S / назад / ALT — смотка   G — насос",
                press and "НАПОР" or "нет напора", tankTxt, laid, maxl),
            "GRMHose_HUD", x, y, col, TEXT_ALIGN_CENTER)
    end
end
