--[[--------------------------------------------------------------------
    grm_food_stove — cl_init.lua (клиент плиты, Код 110)
    3D2D-табличка над плитой: состояние, блюдо, остаток секунд, лоток.
    Окно — cl_grm_food_kitchen.lua по [E].
----------------------------------------------------------------------]]

include("shared.lua")

surface.CreateFont("GRMStove_T", { font = "Roboto", size = 30, weight = 800, extended = true })
surface.CreateFont("GRMStove_S", { font = "Roboto", size = 22, weight = 600, extended = true })

function ENT:Draw()
    self:DrawModel()
    if not GRM or not GRM.FoodKitchen then return end
    local lp = LocalPlayer()
    if not IsValid(lp) then return end
    if self:GetPos():DistToSqr(lp:GetPos()) > 350 * 350 then return end

    local ang = self:GetAngles()
    local maxs = self:OBBMaxs()
    local pos = self:GetPos() + ang:Up() * ((maxs and maxs.z or 40) + 14)
    local state = self:GetStoveState()

    --[[ ПРОГРЕСС-БАР НАД ПЛИТОЙ (заказ владельца 28.08: «прогресс бар
         готовки должен быть также как в меню и над плитой тоже»).

         Раньше здесь были только секунды остатка: «— 47 сек». Понять по
         ним, много ли осталось, нельзя — для минутного рецепта это
         почти конец, для получасового только начало. Полоса показывает
         долю, как в окне кухни.

         Долю считает сама entity (ENT:StoveProgress) — одна формула на
         окно и на табличку, чтобы они не расходились. ]]
    local cooking = state == 1
    local frac = cooking and self:StoveProgress() or 0
    local lines
    if cooking then
        local rec = GRM.FoodKitchen.Recipe(self:GetStoveRecipe())
        local left = math.max(0, (self:GetStoveFinish() or 0) - os.time())
        lines = {
            { txt = "ПЛИТА", col = Color(255, 210, 120) },
            { txt = "«" .. tostring(rec and rec.name or "…") .. "» — " .. tostring(left) .. " сек", col = Color(255, 240, 200) },
        }
    else
        local n = self:GetStoveReady() or 0
        lines = {
            { txt = "ПЛИТА", col = Color(255, 210, 120) },
            { txt = n > 0 and ("Готово блюд: " .. tostring(n) .. " — [E]") or "Свободна — [E]", col = n > 0 and Color(140, 255, 170) or Color(200, 210, 225) },
        }
    end

    cam.Start3D2D(pos, Angle(0, EyeAngles().y - 90, 90), 0.06)
        local w = 360
        -- Под полосу нужна своя высота: без неё текст налезал бы на бар.
        local h = 24 + #lines * 30 - 4 + (cooking and 26 or 0)
        draw.RoundedBox(8, -w / 2, -20, w, h, Color(12, 16, 22, 215))
        surface.SetDrawColor(255, 180, 90, 170)
        surface.DrawOutlinedRect(-w / 2, -20, w, h, 1)
        for i, ln in ipairs(lines) do
            draw.SimpleText(ln.txt, i == 1 and "GRMStove_T" or "GRMStove_S", 0, -20 + i * 30 - 20, ln.col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end

        if cooking then
            local bw, bh = w - 40, 14
            local bx, by = -bw / 2, -20 + #lines * 30 + 2
            draw.RoundedBox(3, bx, by, bw, bh, Color(30, 24, 18, 235))
            draw.RoundedBox(3, bx, by, math.max(2, bw * frac), bh, Color(255, 168, 64, 245))
            surface.SetDrawColor(255, 200, 120, 120)
            surface.DrawOutlinedRect(bx, by, bw, bh, 1)
            draw.SimpleText(math.floor(frac * 100) .. "%", "GRMStove_S", 0, by + bh / 2,
                Color(24, 18, 12), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    cam.End3D2D()
end
