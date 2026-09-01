--[[--------------------------------------------------------------------
    ds_battering_ram — Полицейский таран v2.0.0 (Код 67 / Doors v4.0)
    Модель: models/weapons/w_rocket_launcher.mdl

    Назначение: Силовое вскрытие запертых дверей при наличии судебного ордера
    на обыск (Search Warrant), специального права ForceDoor или прав суперадмина.

    ЛКМ: 3-шаговый цикл силовых ударов по дверному полотну.
    При успехе замок срывается, и обе половины двустворчатой двери
    распахиваются синхронно.
----------------------------------------------------------------------]]

AddCSLuaFile()

SWEP.PrintName = "Полицейский таран"
SWEP.Author = "GRM"
SWEP.Instructions = "ЛКМ: 3 силовых удара по запертой двери (требуется судебный ордер на обыск или право ForceDoor)"
SWEP.Category = "GRM"
SWEP.Spawnable = true
SWEP.AdminSpawnable = true
SWEP.DrawWeaponSelection = true
SWEP.ViewModel = "models/weapons/c_rpg.mdl"
SWEP.WorldModel = "models/weapons/w_rocket_launcher.mdl"
SWEP.UseHands = true
SWEP.HoldType = "rpg"

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

local COOLDOWN = 1.2
local REQUIRED_STRIKES = 3

function SWEP:Initialize()
    self:SetHoldType("rpg")
    self._strikes = 0
end

function SWEP:Deploy()
    self:SetHoldType("rpg")
    self._strikes = 0
    return true
end

function SWEP:GetAimedDoor()
    local ply = self:GetOwner()
    if not IsValid(ply) then return nil end

    local tr = util.TraceLine({
        start = ply:GetShootPos(),
        endpos = ply:GetShootPos() + ply:GetAimVector() * 95,
        filter = ply,
        mask = MASK_SHOT,
    })

    local ent = tr.Entity
    if IsValid(ent) then
        if GRM and GRM.Doors and GRM.Doors.IsDoor and GRM.Doors.IsDoor(ent) then
            return ent
        end
        if IsValid(ent:GetParent()) and GRM and GRM.Doors and GRM.Doors.IsDoor and GRM.Doors.IsDoor(ent:GetParent()) then
            return ent:GetParent()
        end
    end
    return nil
end

function SWEP:PrimaryAttack()
    if CurTime() < (self._nextAction or 0) then return end
    self._nextAction = CurTime() + COOLDOWN
    self:SetNextPrimaryFire(self._nextAction)

    if CLIENT and not IsFirstTimePredicted() then return end

    local door = self:GetAimedDoor()
    if not IsValid(door) then return end

    local ply = self:GetOwner()
    if not IsValid(ply) then return end

    if SERVER then
        if not (GRM and GRM.Doors) then return end

        local rec = GRM.Doors.GetRecord and select(1, GRM.Doors.GetRecord(door))
        local hasForce = GRM.Doors.AccessManager and GRM.Doors.AccessManager.CanForceDoor and GRM.Doors.AccessManager.CanForceDoor(ply)
        local hasWarrant = false
        local ownerKey = rec and tostring(rec.owner_key or rec.owner_sid or "") or ""
        local propertyId = rec and tostring(rec.property_id or "") or ""

        if rec and rec.owner_type == "player" and ownerKey ~= "" then
            hasWarrant = GRM.Doors.HasWarrant and GRM.Doors.HasWarrant(ownerKey, "search")
        end
        if not hasWarrant and propertyId ~= "" and GRM.Doors.HasPropertyWarrant then
            hasWarrant = GRM.Doors.HasPropertyWarrant(propertyId, "search")
        end

        if not hasForce and not hasWarrant and not ply:IsSuperAdmin() then
            ply:EmitSound("buttons/button10.wav", 65, 100, 0.8)
            if GRM.Notify then
                GRM.Notify(ply, "Вскрытие запрещено: у вас нет судебного ордера на обыск или права ForceDoor!", 255, 90, 90)
            end
            return
        end

        door._grmRamStrikes = (door._grmRamStrikes or 0) + 1
        local strikes = door._grmRamStrikes

        if strikes < REQUIRED_STRIKES then
            ply:EmitSound("physics/wood/wood_plank_impact_hard" .. math.random(1, 4) .. ".wav", 80, 100)
            ply:EmitSound("physics/metal/metal_box_impact_hard" .. math.random(1, 3) .. ".wav", 80, 100)
            ply:ViewPunch(Angle(-3, 0, 0))

            if GRM.Notify then
                GRM.Notify(ply, ("Удар по двери: %d / %d"):format(strikes, REQUIRED_STRIKES), 245, 180, 70)
            end
        else
            door._grmRamStrikes = 0
            ply:EmitSound("physics/wood/wood_box_break1.wav", 85, 100)
            ply:EmitSound("physics/metal/metal_box_break1.wav", 85, 100)
            ply:ViewPunch(Angle(-6, 0, 0))

            if GRM.Doors.BreachDoor then
                GRM.Doors.BreachDoor(door, ply, "battering_ram")
            else
                GRM.Doors.LockDoor(door, false, { noAutoLock = true })
                door:Fire("Open", "", 0.05)
                local partner = GRM.Doors.GetPartnerDoor and GRM.Doors.GetPartnerDoor(door)
                if IsValid(partner) then
                    GRM.Doors.LockDoor(partner, false, { noAutoLock = true })
                    partner:Fire("Open", "", 0.05)
                end
            end

            if GRM.Notify then
                GRM.Notify(ply, "Дверь выбита! Замок сорван.", 100, 220, 100)
            end
        end
    end

    self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
end

function SWEP:SecondaryAttack()
    self:PrimaryAttack()
end

if CLIENT then
    surface.CreateFont("RAM_HUD_Title", { font = "Roboto", size = 15, weight = 700, extended = true })
    surface.CreateFont("RAM_HUD_Sub",   { font = "Roboto", size = 12, weight = 500, extended = true })

    function SWEP:DrawHUD()
        local ply = self:GetOwner()
        if ply ~= LocalPlayer() then return end

        local door = self:GetAimedDoor()
        if not IsValid(door) then return end

        local sw, sh = ScrW(), ScrH()
        local bw, bh = 340, 68
        local cx, cy = sw / 2, sh / 2 + 100

        draw.RoundedBox(8, cx - bw / 2, cy, bw, bh, Color(18, 22, 32, 240))
        surface.SetDrawColor(235, 120, 50)
        surface.DrawOutlinedRect(cx - bw / 2, cy, bw, bh, 2)

        draw.SimpleText("ПОЛИЦЕЙСКИЙ ТАРАН", "RAM_HUD_Title", cx, cy + 18, Color(240, 245, 250), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("ЛКМ — Силовой удар (3 удара для выбивания замка)", "RAM_HUD_Sub", cx, cy + 42, Color(235, 180, 80), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end
