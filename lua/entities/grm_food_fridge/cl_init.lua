--[[--------------------------------------------------------------------
    grm_food_fridge — cl_init.lua (клиент холодильника, Код 110)
    3D2D-табличка: занято слотов / всего. Окно — cl_grm_food_kitchen.
----------------------------------------------------------------------]]

include("shared.lua")

surface.CreateFont("GRMFridge_T", { font = "Roboto", size = 30, weight = 800, extended = true })
surface.CreateFont("GRMFridge_S", { font = "Roboto", size = 22, weight = 600, extended = true })

function ENT:Draw()
    self:DrawModel()
    local lp = LocalPlayer()
    if not IsValid(lp) then return end
    if self:GetPos():DistToSqr(lp:GetPos()) > 350 * 350 then return end

    local ang = self:GetAngles()
    local maxs = self:OBBMaxs()
    local pos = self:GetPos() + ang:Up() * ((maxs and maxs.z or 50) + 14)
    local n = self:GetFridgeCount() or 0
    local cap = 12
    if GRM and GRM.FoodKitchen and GRM.FoodKitchen.Cfg then
        cap = tonumber((GRM.FoodKitchen.Cfg() or {}).FridgeSlots) or 12
    end

    cam.Start3D2D(pos, Angle(0, EyeAngles().y - 90, 90), 0.06)
        local w = 340
        draw.RoundedBox(8, -w / 2, -20, w, 54, Color(12, 16, 22, 215))
        surface.SetDrawColor(120, 200, 255, 170)
        surface.DrawOutlinedRect(-w / 2, -20, w, 54, 1)
        draw.SimpleText("ХОЛОДИЛЬНИК", "GRMFridge_T", 0, -3, Color(150, 220, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("Занято: " .. tostring(n) .. "/" .. tostring(cap) .. " — [E]", "GRMFridge_S", 0, 22, Color(200, 215, 235), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    cam.End3D2D()
end
