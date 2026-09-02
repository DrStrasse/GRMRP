include("shared.lua")

local cableMat
local function mat()
    if not cableMat then cableMat = Material("cable/cable2") end
    return cableMat
end

local function sag(a, b, segs)
    local out = {}
    local dist = a:Distance(b)
    local drop = math.Clamp(18 + dist * 0.12, 14, 86)
    for i = 0, segs do
        local t = i / segs
        local p = LerpVector(t, a, b)
        p.z = p.z - drop * 4 * t * (1 - t)
        out[i + 1] = p
    end
    return out
end

--[[ ШЛАНГ РИСУЕТСЯ ОТ КОЛОНКИ К ГОРЛОВИНЕ.

     Раньше конец шланга был привязан к пистолету в руках игрока:
     пошёл — и шланг пошёл за тобой, а из бака вылетел. Теперь шланг
     лежит на колонке: либо висит на крючке, либо тянется к горловине
     той машины, в чей бак он вставлен. ]]
function ENT:Draw()
    self:DrawModel()
    local a = self:LocalToWorld(Vector(14, -10, 22))
    local dest
    local car = self.GetHoseCar and self:GetHoseCar() or nil
    local holder = self:GetUser()
    if IsValid(car) then
        dest = (GRM.Fuel and GRM.Fuel.FillPort) and GRM.Fuel.FillPort(car)
            or car:WorldSpaceCenter()
    elseif IsValid(holder) then
        dest = holder:EyePos()                        -- пистолет в руках
    else
        dest = self:LocalToWorld(Vector(6, -12, 4))   -- крючок на колонке
    end
    if dest then
        local pts = sag(a, dest, 14)
        render.SetMaterial(mat())
        for i = 1, #pts - 1 do
            render.DrawBeam(pts[i], pts[i + 1], 3.4, 0, 1, Color(28, 24, 20, 255))
        end
    end
    local lp = LocalPlayer()
    if not IsValid(lp) or lp:GetPos():DistToSqr(self:GetPos()) > 280000 then return end
    local ang = self:LocalToWorldAngles(Angle(0, 90, 90))
    cam.Start3D2D(self:LocalToWorld(Vector(10, 0, 52)), ang, 0.07)
        draw.RoundedBox(6, -130, -70, 260, 132, Color(12, 16, 24, 235))
        local kind = (GRM.Fuel and GRM.Fuel.Types and GRM.Fuel.Types[self:GetFuelKind()]) or self:GetFuelKind()
        local price = math.max(1, self:GetPriceL() > 0 and self:GetPriceL() or ((GRM.Fuel and GRM.Fuel.PricePerLiter) or 8))
        draw.SimpleText(kind or "Бензин", "DermaLarge", 0, -52, Color(250, 190, 60), TEXT_ALIGN_CENTER)
        draw.SimpleText(string.format("%.0f GRM / л", price), "DermaDefault", 0, -28, Color(210, 220, 230), TEXT_ALIGN_CENTER)
        local sess = self:GetSessionL() or 0
        local pay = self:GetSessionPay() or 0
        local now, mx = self:GetTankNow() or 0, math.max(1, self:GetTankMax() or 100)
        if self:GetBusy() or sess > 0 then
            draw.SimpleText(string.format("залито сейчас  %.1f л", sess), "DermaDefault", 0, -6, Color(120, 220, 140), TEXT_ALIGN_CENTER)
            draw.SimpleText(string.format("к оплате  %.0f GRM", pay), "DermaDefault", 0, 12, Color(250, 185, 63), TEXT_ALIGN_CENTER)
            local pct = math.Clamp(now / mx, 0, 1)
            surface.SetDrawColor(35, 40, 50)
            surface.DrawRect(-90, 30, 180, 10)
            surface.SetDrawColor(240, 170, 50)
            surface.DrawRect(-90, 30, 180 * pct, 10)
            draw.SimpleText(string.format("бак  %.0f / %.0f л", now, mx), "DermaDefault", 0, 50, Color(200, 210, 220), TEXT_ALIGN_CENTER)
        else
            local own = self:GetOwnerKey() or ""
            local hint
            if IsValid(car) then
                hint = "шланг в баке  ·  E — выбрать литры"
            elseif IsValid(holder) then
                hint = (holder == LocalPlayer()) and "пистолет в руках  ·  E на машине — вставить"
                    or "пистолет у другого игрока"
            else
                hint = "E — взять шланг   SHIFT+E — касса"
            end
            draw.SimpleText(hint, "DermaDefault", 0, 4, Color(200, 210, 220), TEXT_ALIGN_CENTER)
            draw.SimpleText(own ~= "" and "частная колонка" or "свободна · можно выкупить", "DermaDefault", 0, 24, Color(140, 160, 180), TEXT_ALIGN_CENTER)
        end
    cam.End3D2D()
end
