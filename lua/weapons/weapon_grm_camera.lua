if SERVER then AddCSLuaFile() end

SWEP.PrintName = "Служебная камера"
SWEP.Author = "GRM"
SWEP.Instructions = "ЛКМ — снимок. ПКМ удерживать — зум. R — сброс зума."
SWEP.Category = "GRM Police"
SWEP.Spawnable = true
SWEP.AdminOnly = false
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = false
SWEP.UseHands = false
SWEP.ViewModel = "models/weapons/c_arms_animations.mdl"
SWEP.WorldModel = "models/MaxOfS2D/camera.mdl"
SWEP.ViewModelFOV = 62
SWEP.Primary = { ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none" }
SWEP.Secondary = { ClipSize = -1, DefaultClip = -1, Automatic = true, Ammo = "none" }
SWEP.ShootSound = Sound("NPC_CScanner.TakePhoto")

function SWEP:SetupDataTables()
    self:NetworkVar("Float", 0, "Zoom")
end

function SWEP:Initialize()
    self:SetHoldType("camera")
    if SERVER and self:GetZoom() <= 0 then self:SetZoom(75) end
end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 1.0)
    if not SERVER then return end
    local owner = self:GetOwner()
    if not (IsValid(owner) and owner:IsPlayer()) then return end
    net.Start("GRM_Photo_Capture")
    net.Send(owner)
    self:EmitSound(self.ShootSound, 65, 100, 0.7)
end

function SWEP:SecondaryAttack()
end

function SWEP:Tick()
    local owner = self:GetOwner()
    if not IsValid(owner) or not owner:IsPlayer() then return end
    if CLIENT and owner ~= LocalPlayer() then return end
    local cmd = owner:GetCurrentCommand()
    if not cmd or not cmd:KeyDown(IN_ATTACK2) then return end
    local current = self:GetZoom()
    if current <= 0 then current = 75 end
    self:SetZoom(math.Clamp(current + cmd:GetMouseY() * FrameTime() * 6.6, 8, 120))
end

function SWEP:Reload()
    local owner = self:GetOwner()
    if IsValid(owner) then self:SetZoom(75) end
end

function SWEP:TranslateFOV(fov)
    local z = self:GetZoom()
    if z <= 0 then return fov end
    return z
end

function SWEP:AdjustMouseSensitivity()
    local z = self:GetZoom()
    if z <= 0 then return nil end
    return z / 80
end

function SWEP:ShouldDropOnDie()
    return false
end

function SWEP:DrawWorldModel()
    self:DrawModel()
end

if CLIENT then
    local pending = false
    local naming = false

    hook.Add("GRM_PhotoDoCapture", "GRM_Cam", function()
        pending = true
    end)

    hook.Add("PostRender", "GRM_CamCapture", function()
        if not pending or naming then return end
        local ply = LocalPlayer()
        if not IsValid(ply) then return end
        local wep = ply:GetActiveWeapon()
        if not IsValid(wep) or wep:GetClass() ~= "weapon_grm_camera" then
            pending = false
            return
        end
        pending = false

        local cw = math.min(320, ScrW())
        local ch = math.min(240, ScrH())
        local cx = math.max(0, math.floor((ScrW() - cw) / 2))
        local cy = math.max(0, math.floor((ScrH() - ch) / 2))
        local data
        for _, q in ipairs({ 22, 14, 8 }) do
            data = render.Capture({
                format = "jpeg", quality = q,
                x = cx, y = cy, w = cw, h = ch,
            })
            if data and #data <= 12000 then break end
        end
        if not data or data == "" then
            notification.AddLegacy("Не удалось снять кадр.", NOTIFY_ERROR, 3)
            return
        end

        local tr = ply:GetEyeTrace()
        local subject = ""
        if IsValid(tr.Entity) and tr.Entity:IsPlayer() then
            local n = tr.Entity:GetNWString("GRM_RPName", "")
            if n == "" then n = tr.Entity:Nick() end
            subject = n
        end

        naming = true
        Derma_StringRequest("Снимок", "Название кадра", "Кадр " .. os.date("%H:%M:%S"), function(title)
            naming = false
            net.Start("GRM_Photo_Upload")
                net.WriteString(title ~= "" and title or "Кадр")
                net.WriteString(subject)
                net.WriteString("none")
                net.WriteUInt(cw, 16)
                net.WriteUInt(ch, 16)
                net.WriteUInt(#data, 16)
                net.WriteData(data, #data)
            net.SendToServer()
        end, function() naming = false end)
    end)

    function SWEP:DrawHUD()
        if pending then return end
        local z = self:GetZoom()
        if z <= 0 then z = 75 end
        local cx, cy = ScrW() * 0.5, ScrH() * 0.5
        surface.SetDrawColor(255, 255, 255, 180)
        surface.DrawOutlinedRect(cx - 160, cy - 120, 320, 240, 1)
        surface.DrawLine(cx - 10, cy, cx + 10, cy)
        surface.DrawLine(cx, cy - 10, cx, cy + 10)
        draw.SimpleText(string.format("FOV %.0f  ЛКМ снимок", z), "DermaDefaultBold", cx, ScrH() - 72, Color(255, 255, 255, 220), TEXT_ALIGN_CENTER)
        local tr = LocalPlayer():GetEyeTrace()
        if IsValid(tr.Entity) and tr.Entity:IsPlayer() then
            local n = tr.Entity:GetNWString("GRM_RPName", "")
            if n == "" then n = tr.Entity:Nick() end
            draw.SimpleText("в кадре: " .. n, "DermaDefault", cx, ScrH() - 52, Color(230, 80, 70), TEXT_ALIGN_CENTER)
        end
    end

    function SWEP:HUDShouldDraw(name)
        if name == "CHudWeaponSelection" or name == "CHudChat" then return true end
        return false
    end

    function SWEP:FreezeMovement()
        local o = self:GetOwner()
        if not IsValid(o) then return false end
        return o:KeyDown(IN_ATTACK2) or o:KeyReleased(IN_ATTACK2)
    end

    function SWEP:PreDrawViewModel()
        return true
    end
end
