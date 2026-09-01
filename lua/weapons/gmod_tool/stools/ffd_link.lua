--[[--------------------------------------------------------------------
    FFD Link — Toolgun Module (Код 108, заказ владельца)
    РУЧНАЯ привязка «FFD Keypad / FFD Scanner → FFD Fading Door».

    ЛКМ по кейпаду/сканеру : выбрать контроллер (повторный клик — сброс)
    ЛКМ по FFD-двери       : связать / отвязать её с выбранным контроллером
    ПКМ по контроллеру     : снять ВСЕ его связи
    ПКМ по двери           : отвязать её ото ВСЕХ контроллеров карты
    R                      : сбросить выбор контроллера

    Код 109 (заказ владельца): авто-связи больше НЕТ — без ручных связей
    контроллер не открывает НИ ОДНУ дверь (раньше хватал весь радиус 250).
    Логика хранения — sh_grm_ffdlink.lua (GRM.FFDLink), перм/дубликат
    едут автоматически. Подсветка статуса — TOOL:DrawHUD (дёргается из
    SWEP:DrawHUD тулгана — проверено по исходнику gmod_tool).
----------------------------------------------------------------------]]

TOOL.Category = "GRM"
TOOL.Name = "#tool.ffd_link.name"
TOOL.Command    = nil
TOOL.ConfigName = ""

if CLIENT then
    language.Add("tool.ffd_link.name", "GRM Связь замка с дверью")
    language.Add("tool.ffd_link.desc", "Ручная связь FFD Keypad / Scanner с исчезающими дверями")
    language.Add("tool.ffd_link.0", "ЛКМ: контроллер — выбор, дверь — связать/отвязать | ПКМ: снять связи | R: сброс")
end

local function isController(ent)
    return IsValid(ent) and GRM and GRM.FFDLink
        and GRM.FFDLink.IsController and GRM.FFDLink.IsController(ent)
end

local function isDoor(ent)
    if not IsValid(ent) then return false end
    -- Находка 173: раздвижные двери (isSlidingDoor) — тоже двери для FFD Link
    if ent.isFadingDoor == true or ent.isSlidingDoor == true then return true end -- серверные поля
    if CLIENT then return ent:GetNWBool("FFD_IsDoor", false) == true end
    return false
end

local function tell(ply, msg, r, g, b)
    if GRM and GRM.Notify then
        GRM.Notify(ply, msg, r, g, b)
    elseif IsValid(ply) then
        ply:PrintMessage(HUD_PRINTTALK, tostring(msg))
    end
end

function TOOL:LeftClick(trace)
    local ent = trace.Entity
    if not IsValid(ent) or ent:IsPlayer() or ent:IsNPC() then return false end
    if CLIENT then return true end

    local ply = self:GetOwner()

    -- 1) контроллер: выбрать (повторный клик — сбросить выбор)
    if isController(ent) then
        if self:GetEnt(1) == ent and self:NumObjects() > 0 then
            self:ClearObjects()
            self:SetStage(0)
            tell(ply, "FFD Link: выбор контроллера снят.", 235, 180, 60)
            return true
        end
        self:ClearObjects()
        self:SetObject(1, ent, trace.HitPos, nil, 0, trace.HitNormal)
        self:SetStage(1)
        tell(ply, ("FFD Link: контроллер выбран — %s #%d (связей: %d). Теперь ЛКМ по FFD-дверям.")
            :format(ent:GetClass(), ent:EntIndex(), GRM.FFDLink.Count(ent)), 100, 220, 255)
        return true
    end

    -- 2) дверь: связать/отвязать с выбранным контроллером
    if isDoor(ent) then
        local ctrl = self:GetEnt(1)
        if not isController(ctrl) then
            tell(ply, "FFD Link: сначала ЛКМ выбери контроллер (кейпад или сканер).", 255, 200, 80)
            return false
        end
        local added = GRM.FFDLink.Toggle(ctrl, ent)
        local n = GRM.FFDLink.Count(ctrl)
        if added == true then
            tell(ply, ("FFD Link: дверь #%d СВЯЗАНА с %s #%d (всего связей: %d).")
                :format(ent:EntIndex(), ctrl:GetClass(), ctrl:EntIndex(), n), 100, 220, 100)
            return true
        elseif added == false then
            tell(ply, ("FFD Link: дверь #%d ОТВЯЗАНА от %s #%d (осталось: %d).")
                :format(ent:EntIndex(), ctrl:GetClass(), ctrl:EntIndex(), n), 235, 180, 60)
            return true
        end
        tell(ply, "FFD Link: не удалось переключить связь (лимит " .. (GRM.FFDLink.Count(ctrl) >= 32 and "32" or "?") .. ").", 255, 120, 120)
        return false
    end

    tell(ply, "FFD Link: цель — не контроллер и не FFD-дверь. Нужны grm_keypad / grm_scanner / исчезающая дверь.", 255, 200, 80)
    return false
end

function TOOL:RightClick(trace)
    local ent = trace.Entity
    if not IsValid(ent) or ent:IsPlayer() or ent:IsNPC() then return false end
    if CLIENT then return true end

    local ply = self:GetOwner()

    -- ПКМ по контроллеру: снять ВСЕ его связи
    if isController(ent) then
        local n = GRM.FFDLink.Clear(ent)
        if self:GetEnt(1) == ent then
            self:ClearObjects()
            self:SetStage(0)
        end
        tell(ply, ("FFD Link: %s #%d — снято связей: %d. Контроллер теперь ни к чему не привязан (двери открывать не будет до новой привязки).")
            :format(ent:GetClass(), ent:EntIndex(), n), 235, 180, 60)
        return true
    end

    -- ПКМ по двери: отвязать её ото всех контроллеров сразу
    if isDoor(ent) then
        local n = GRM.FFDLink.RemoveFromAll(ent)
        if n > 0 then
            tell(ply, ("FFD Link: дверь #%d отвязана от %d контроллер(ов)."):format(ent:EntIndex(), n), 235, 180, 60)
        else
            tell(ply, ("FFD Link: дверь #%d ни к чему не привязана."):format(ent:EntIndex()), 255, 200, 80)
        end
        return true
    end

    tell(ply, "FFD Link: ПКМ — по контроллеру (снять его связи) или по двери (отвязать её везде).", 255, 200, 80)
    return false
end

function TOOL:Reload(trace)
    if SERVER and self:NumObjects() > 0 then
        tell(self:GetOwner(), "FFD Link: выбор контроллера сброшен.", 235, 180, 60)
    end
    self:ClearObjects()
    self:SetStage(0)
    return true
end

function TOOL:Holster()
    self:ClearObjects()
    self:SetStage(0)
end

-- ============================================================
-- Клиентский HUD: выбранный контроллер + статус цели под прицелом
-- (TOOL:DrawHUD вызывается из SWEP:DrawHUD тулгана каждый кадр)
-- ============================================================
if CLIENT then
    local function centerText(txt, dy, col)
        draw.SimpleText(txt, "Trebuchet24", ScrW() / 2, ScrH() / 2 + 60 + dy, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    function TOOL:DrawHUD()
        local ctrl = self:GetEnt(1)
        local ok = isController(ctrl)

        if not ok then
            centerText("ЛКМ по кейпаду или сканеру — выбрать контроллер связи", 0, Color(255, 210, 100))
            return
        end

        centerText(("Контроллер: %s #%d · связей: %d")
            :format(ctrl:GetClass(), ctrl:EntIndex(), GRM.FFDLink.LinkedCount(ctrl)), 0, Color(120, 220, 255))

        local lp = LocalPlayer()
        if not IsValid(lp) then return end
        local tr = lp:GetEyeTrace()
        local t = tr and tr.Entity or nil
        if not IsValid(t) then return end

        if isDoor(t) then
            local linked = GRM.FFDLink.LinkedIndexSet(ctrl)[t:EntIndex()] == true
            if linked then
                centerText("Цель: СВЯЗАНА — ЛКМ отвязать, ПКМ отвязать везде", 28, Color(120, 255, 140))
            else
                centerText("Цель: не связана — ЛКМ связать", 28, Color(255, 210, 100))
            end
        elseif isController(t) and t ~= ctrl then
            centerText("ЛКМ — сменить контроллер", 28, Color(200, 200, 220))
        end
    end
end

function TOOL.BuildCPanel(panel)
    panel:AddControl("Header", { Description = "Ручная связка «FFD Keypad / FFD Scanner → конкретные FFD-двери». БЕЗ связей контроллер не открывает ни одну дверь (Код 109: авто-определение по радиусу удалено)." })
    panel:Help("1) ЛКМ по кейпаду или сканеру — выбрать контроллер (повторный ЛКМ — снять выбор).")
    panel:Help("2) ЛКМ по исчезающей двери — связать/отвязать её с выбранным контроллером.")
    panel:Help("ПКМ по контроллеру — снять ВСЕ его связи. ПКМ по двери — отвязать её ото всех контроллеров. R — сброс выбора.")
    panel:Help("Связи переживают рестарт через /permadd и копируются дубликатором вместе с контроллером.")
end
