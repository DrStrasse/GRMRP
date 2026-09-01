--[[--------------------------------------------------------------------
    GRM Megaphone (Код 85) — ручной мегафон.
    ЛКМ: вкл/выкл усиление. Пока включён, голос владельца маршрутизируется
    RadioNet: слышно на GRM.RadioNet.MegaRange (≈4.5× обычного голоса),
    без 3D-затухания («из рупора»), с лёгким треском помех.
    ПКМ: только выключить. Смена оружия/смерть — усиление гаснет.
    Админский предмет (выдача: Q-меню / give weapon_grm_megaphone).
----------------------------------------------------------------------]]

SWEP.PrintName     = "Мегафон GRM"
SWEP.Author        = "GRM"
SWEP.Category      = "GRM — RP"
SWEP.Instructions  = "ЛКМ — вкл/выкл усиление голоса; ПКМ — выкл"
SWEP.Spawnable     = true
SWEP.AdminOnly     = true

SWEP.ViewModel     = "models/weapons/c_slam.mdl"
SWEP.WorldModel    = "models/props_wasteland/speakercluster01a.mdl"
SWEP.UseHands      = true
SWEP.ViewModelFOV  = 60
SWEP.HoldType      = "slam"

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
end

local function megaRange()
    return (GRM and GRM.RadioNet and GRM.RadioNet.MegaRange) or 1600
end

local function setMega(ply, on)
    ply._rnMegaOn = on and true or false
    if ply.SetNW2Bool then ply:SetNW2Bool("GRM_MegaOn", ply._rnMegaOn) end
end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 0.4)
    if CLIENT then return end
    local ply = self:GetOwner()
    if not IsValid(ply) then return end
    local on = not ply._rnMegaOn
    setMega(ply, on)
    self:EmitSound(on and "buttons/button15.wav" or "buttons/button18.wav", 62, 100)
    if GRM and GRM.Notify then
        GRM.Notify(ply,
            on and ("Мегафон ВКЛЮЧЁН: голос усилен — слышно на ~" .. tostring(megaRange()) .. " юнитов (с лёгким треском рупора).")
                or "Мегафон ВЫКЛЮЧЕН.",
            on and 100 or 230, on and 220 or 170, 90)
    end
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 0.4)
    if CLIENT then return end
    local ply = self:GetOwner()
    if not IsValid(ply) then return end
    if ply._rnMegaOn then
        setMega(ply, false)
        self:EmitSound("buttons/button18.wav", 62, 100)
        if GRM and GRM.Notify then GRM.Notify(ply, "Мегафон ВЫКЛЮЧЕН.", 230, 170, 90) end
    end
end

function SWEP:Holster()
    if SERVER and IsValid(self:GetOwner()) then setMega(self:GetOwner(), false) end
    return true
end

function SWEP:OnRemove()
    if SERVER and IsValid(self:GetOwner()) then setMega(self:GetOwner(), false) end
end

if CLIENT then
    surface.CreateFont("GRMMega_HUD", { font = "Roboto", size = 16, weight = 700, extended = true })
    function SWEP:DrawHUD()
        local ply = self:GetOwner()
        if not IsValid(ply) then return end
        local on = ply.GetNW2Bool and ply:GetNW2Bool("GRM_MegaOn", false) or false
        local blink = on and ((math.sin(CurTime() * 6) + 1) * 0.5) or 0
        draw.SimpleText(on and "● МЕГАФОН ВКЛ — говорите, вас слышно издалека" or "○ мегафон выключен (ЛКМ — включить)",
            "GRMMega_HUD", ScrW() / 2, ScrH() * 0.72,
            on and Color(120 + blink * 120, 255, 140) or Color(190, 195, 205),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end
