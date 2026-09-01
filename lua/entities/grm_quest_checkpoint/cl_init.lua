include("shared.lua")

local COL_LABEL = Color(255, 210, 210)
local COL_DIM = Color(180, 150, 150)

--[[ ВИДИМОСТЬ: ТОЛЬКО ПРИ АКТИВНОМ КВЕСТЕ (заказ владельца 30.08:
     «чекпоинт показывается только когда активен какой-либо квест/этап»).

     Маркер — общая для всех энтити на сервере, а квест у каждого свой.
     Значит решать, рисовать ли круг, обязан КЛИЕНТ по своему прогрессу:
     иначе игрок видит красные цели заданий, которых не брал, и по городу
     висит мусор.

     Прогресс уже приходит в Q.ClientRows (GRM_Quest_Sync) — отдельная
     сеть не нужна. ]]
local function shouldShow(self)
    local Q = GRM and GRM.Quests
    if not (Q and istable(Q.ClientRows)) then return false end

    local questID = tostring(self:GetQuestID() or "")
    if questID == "" then return false end
    local cpID = tostring(self:GetCheckpointID() or "")

    for _, row in ipairs(Q.ClientRows) do
        local def = row.definition
        if def and tostring(def.id or "") == questID then
            local p = row.progress
            if not (istable(p) and p.status == "active") then return false end

            --[[ Пройденную одноразовую точку прячем: она больше ничего не
                 сделает, а на карте продолжала бы указывать на цель. ]]
            local once = true
            for _, cp in ipairs(istable(def.checkpoints) and def.checkpoints or {}) do
                if tostring(cp.id or "") == cpID then once = cp.once ~= false break end
            end
            if once and istable(p.checkpoints) and p.checkpoints[cpID] then return false end
            return true
        end
    end
    return false
end

function ENT:Draw()
    --[[ Выход ДО DrawModel: если погасить только подпись, в мире
         останется висеть красный круг без объяснения, что это. ]]
    if not shouldShow(self) then return end

    --[[ ВРАЩЕНИЕ — НА КЛИЕНТЕ (заказ: «чекпоинты крутящиеся»).

         Считаем угол от RealTime и рисуем модель повёрнутой. Гонять угол
         по сети каждый кадр ради украшения — пустая нагрузка и на
         сервер, и на канал: на игровую логику вращение не влияет.

         RealTime, а не CurTime: он не замирает на паузе одиночной игры и
         не дёргается при лагах сервера, поэтому вращение ровное. ]]
    local base = self:GetAngles()
    local spin = (RealTime() * (self.SpinSpeed or 45)) % 360

    self:SetRenderAngles(Angle(base.p, base.y + spin, base.r))
    self:DrawModel()
    self:SetRenderAngles(nil)          -- иначе поворот утечёт на другие проходы

    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local pos = self:GetPos()
    if ply:GetPos():DistToSqr(pos) > 900 * 900 then return end

    local label = self:GetLabel()
    if label == "" then label = "Чекпоинт" end

    local look = (ply:EyeAngles() or Angle(0, 0, 0))
    cam.Start3D2D(pos + Vector(0, 0, 26), Angle(0, look.y - 90, 90), 0.12)
        draw.SimpleText(string.upper(label), "Trebuchet24", 0, -14,
            COL_LABEL, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("цель задания", "Trebuchet24", 0, 12,
            COL_DIM, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    cam.End3D2D()
end

--[[ Маркер полупрозрачный, значит движок обязан рисовать его в
     translucent-проходе. Без этого сквозь него не видно того, что
     позади, и «прозрачность 50%» на глаз пропадает. ]]
function ENT:GetRenderGroup()
    return RENDERGROUP_BOTH
end
