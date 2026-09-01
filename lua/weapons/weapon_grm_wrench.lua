AddCSLuaFile()

SWEP.PrintName = "Ключ ремонта"
SWEP.Author = "GRM"
SWEP.Instructions = "Удерживай ЛКМ по транспорту — чинит прочность и снимает поломку."
SWEP.Spawnable = true
SWEP.AdminOnly = false
SWEP.Category = "GRM"
SWEP.Slot = 3
SWEP.SlotPos = 6
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true
SWEP.ViewModel = "models/weapons/c_arms.mdl"
SWEP.WorldModel = "models/props_c17/tools_wrench01a.mdl"
SWEP.UseHands = true
SWEP.HoldType = "melee"
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
    self:SetModel(self.WorldModel)
end

function SWEP:Deploy()
    self:SetHoldType(self.HoldType)
    return true
end

local function aimVeh(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    local e = tr.Entity
    if GRM.Fuel and GRM.Fuel.RootVehicle then e = GRM.Fuel.RootVehicle(e) or e end
    local VK = GRM.VehicleKeys or _G.VK
    if IsValid(e) and VK and VK.IsVehicle and VK.IsVehicle(e) then
        if ply:GetPos():DistToSqr(e:GetPos()) <= 180 * 180 then return e end
    end
end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 0.2)
    local ply = self:GetOwner()
    if not IsValid(ply) then return end
    if CLIENT then return end
    local veh = aimVeh(ply)
    if not IsValid(veh) then
        if (self._missAt or 0) < CurTime() then
            self._missAt = CurTime() + 1.2
            if GRM.Notify then GRM.Notify(ply, "Наведи ключ на транспорт.", 255, 180, 80) end
        end
        return
    end
    if not (GRM.VehHP and GRM.VehHP.WrenchTick) then return end
    local ok, a, b, cost = GRM.VehHP.WrenchTick(ply, veh)
    if not ok then
        if a and a ~= "целая" and (self._missAt or 0) < CurTime() then
            self._missAt = CurTime() + 1
            if GRM.Notify then GRM.Notify(ply, tostring(a), 255, 170, 80) end
        end
        return
    end
    ply:EmitSound("physics/metal/metal_box_impact_soft" .. math.random(1, 3) .. ".wav", 60, 110, 0.45)
    self:SetNWFloat("RepHP", tonumber(a) or 0)
    self:SetNWFloat("RepMax", tonumber(b) or 100)
end

function SWEP:SecondaryAttack()
end

function SWEP:Reload()
end

if CLIENT then
    function SWEP:DrawWorldModel()
        local ply = self:GetOwner()
        if IsValid(ply) then
            local bone = ply:LookupBone("ValveBiped.Bip01_R_Hand")
            if bone then
                local pos, ang = ply:GetBonePosition(bone)
                if pos then
                    ang:RotateAroundAxis(ang:Right(), 90)
                    ang:RotateAroundAxis(ang:Up(), 90)
                    self:SetRenderOrigin(pos + ang:Forward() * 3 + ang:Right() * 1)
                    self:SetRenderAngles(ang)
                    self:DrawModel()
                    self:SetRenderOrigin()
                    self:SetRenderAngles()
                    return
                end
            end
        end
        self:DrawModel()
    end

    function SWEP:PreDrawViewModel()
        return true
    end

    function SWEP:PostDrawViewModel()
        local ply = self:GetOwner()
        if not IsValid(ply) then return end
        local pos, ang = ply:EyePos(), ply:EyeAngles()
        pos = pos + ang:Forward() * 20 + ang:Right() * 8 - ang:Up() * 7
        ang:RotateAroundAxis(ang:Right(), 20)
        ang:RotateAroundAxis(ang:Up(), 80)
        render.Model({ model = self.WorldModel, pos = pos, angle = ang })
    end

    function SWEP:DrawHUD()
        local lp = LocalPlayer()
        if not IsValid(lp) then return end
        local veh = aimVeh(lp)
        local txt = "ЛКМ удерживать — чинить транспорт"
        draw.SimpleTextOutlined(txt, "DermaDefault", ScrW() / 2, ScrH() - 86, Color(230, 210, 140), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 220))
        if IsValid(veh) then
            local hp = veh:GetNWFloat("GRM_VehHP", self:GetNWFloat("RepHP", -1))
            local mx = math.max(1, veh:GetNWFloat("GRM_VehHPMax", 100))
            if hp >= 0 then
                draw.SimpleTextOutlined(string.format("прочность  %.0f / %.0f", hp, mx), "DermaDefault", ScrW() / 2, ScrH() - 64, Color(200, 230, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, 220))
            end
        end
    end
end
