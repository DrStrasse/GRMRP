--[[--------------------------------------------------------------------
    grm_food_planter — cl_init.lua (клиент горшка, Код 110)
    3D2D-табличка: культура, прогресс %, «ГОТОВО», кулдаун полива.
----------------------------------------------------------------------]]

include("shared.lua")

surface.CreateFont("GRMPlant_T", { font = "Roboto", size = 30, weight = 800, extended = true })
surface.CreateFont("GRMPlant_S", { font = "Roboto", size = 22, weight = 600, extended = true })

function ENT:Draw()
    self:DrawModel()
    if not GRM or not GRM.FoodKitchen then return end
    local lp = LocalPlayer()
    if not IsValid(lp) then return end
    if self:GetPos():DistToSqr(lp:GetPos()) > 350 * 350 then return end

    local ang = self:GetAngles()
    local maxs = self:OBBMaxs()
    local pos = self:GetPos() + ang:Up() * ((maxs and maxs.z or 30) + 26)
    local state = self:GetPlanterState()
    local lines
    if state == 1 then
        local c = GRM.FoodKitchen.Crop(self:GetPlanterCrop())
        local fin = self:GetPlanterFinish() or 0
        local total = (c and tonumber(c.growSeconds)) or 60
        local left = math.max(0, fin - os.time())
        local pct = math.floor((1 - left / total) * 100 + 0.5)
        lines = {
            { txt = tostring(c and c.name or "Грядка"), col = Color(140, 255, 150) },
            { txt = "Растёт: " .. tostring(pct) .. "% (" .. tostring(left) .. " сек)", col = Color(210, 240, 210) },
        }
    elseif state == 2 then
        local c = GRM.FoodKitchen.Crop(self:GetPlanterCrop())
        lines = {
            { txt = tostring(c and c.name or "Грядка"), col = Color(140, 255, 150) },
            { txt = "ГОТОВО — [E] собрать урожай", col = Color(140, 255, 170) },
        }
    else
        lines = {
            { txt = "ГОРШОК", col = Color(140, 255, 150) },
            { txt = "Пусто — [E] посадить (семена за деньги)", col = Color(200, 215, 190) },
        }
    end

    cam.Start3D2D(pos, Angle(0, EyeAngles().y - 90, 90), 0.06)
        local w = 380
        draw.RoundedBox(8, -w / 2, -20, w, 24 + #lines * 30 - 4, Color(12, 16, 22, 215))
        surface.SetDrawColor(120, 230, 140, 170)
        surface.DrawOutlinedRect(-w / 2, -20, w, 24 + #lines * 30 - 4, 1)
        for i, ln in ipairs(lines) do
            draw.SimpleText(ln.txt, i == 1 and "GRMPlant_T" or "GRMPlant_S", 0, -20 + i * 30 - 20, ln.col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    cam.End3D2D()
end
