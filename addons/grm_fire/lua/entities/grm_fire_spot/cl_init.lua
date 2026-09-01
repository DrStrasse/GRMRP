include("shared.lua")

local function holdingPlaceTool(ply)
    if not IsValid(ply) then return false end
    if not ply.IsSuperAdmin or not ply:IsSuperAdmin() then return false end
    local wep = ply:GetActiveWeapon()
    if not (IsValid(wep) and wep:GetClass() == "gmod_tool") then return false end
    local mode = ""
    if wep.GetMode then mode = tostring(wep:GetMode() or "") end
    if mode == "" and ply.GetInfo then mode = tostring(ply:GetInfo("gmod_toolmode") or "") end
    return mode == "grm_fire_place"
end

local function coolLeft(ent)
    local last = ent.GetLastIgnite and tonumber(ent:GetLastIgnite()) or 0
    if last <= 0 then return 0 end
    local cd = ent.GetCoolSec and tonumber(ent:GetCoolSec()) or 0
    if cd <= 0 then
        cd = (GRM.Fire and GRM.Fire.Config and tonumber(GRM.Fire.Config.SpotCooldownSec)) or 2700
    end
    local left = (last + cd) - os.time()
    if left < 0 then return 0 end
    return math.floor(left)
end

function ENT:Draw()
end

function ENT:DrawTranslucent()
end

function ENT:DrawSpotMarker()
    local fn = FrameNumber and FrameNumber() or 0
    if self._grmDrew == fn then return end
    self._grmDrew = fn
    local pos = self:GetPos()
    local on = not (self.GetSpotOn and self:GetSpotOn() == false)
    local col = on and Color(255, 110, 40, 210) or Color(120, 120, 130, 180)
    render.SetColorMaterial()
    render.DrawBox(pos, Angle(0, 0, 0), Vector(-7, -7, 0), Vector(7, 7, 16), col)
    render.DrawWireframeBox(pos, Angle(0, 0, 0), Vector(-7, -7, 0), Vector(7, 7, 16), Color(255, 220, 80, 255), true)
    local ang = EyeAngles()
    ang:RotateAroundAxis(ang:Right(), 90)
    ang:RotateAroundAxis(ang:Up(), -90)
    local label = self.GetSpotLabel and self:GetSpotLabel() or "очаг"
    if label == "" then label = "очаг" end
    local w = self.GetWeight and self:GetWeight() or 1
    local left = coolLeft(self)
    local line2 = "вес " .. tostring(w) .. (on and "" or "  ВЫКЛ")
    if left > 0 then line2 = line2 .. "  кд " .. tostring(left) .. "с" end
    cam.Start3D2D(pos + Vector(0, 0, 22), ang, 0.07)
        draw.SimpleText("ОЧАГ  " .. tostring(label), "DermaDefaultBold", 0, 0, Color(255, 190, 80), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(line2, "DermaDefault", 0, 16, Color(230, 230, 235), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    cam.End3D2D()
end

local fireSpotDrawFrame = -1
hook.Add("PostDrawTranslucentRenderables", "GRM_FireSpot_Vis", function(_, sky)
    if sky then return end
    local frame = FrameNumber()
    if fireSpotDrawFrame == frame then return end
    fireSpotDrawFrame = frame
    local ply = LocalPlayer()
    if not holdingPlaceTool(ply) then return end
    -- Покадровый скан класса заменён event-реестром GRM.Perf.
    local spots = (GRM and GRM.Perf and GRM.Perf.Entities) and GRM.Perf.Entities("grm_fire_spot")
        or ents.FindByClass("grm_fire_spot")
    for _, ent in ipairs(spots) do
        if IsValid(ent) and ent.DrawSpotMarker then ent:DrawSpotMarker() end
    end
end)
