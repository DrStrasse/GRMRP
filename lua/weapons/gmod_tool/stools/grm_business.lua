--[[--------------------------------------------------------------------
    GRM: бизнес-зона — выделение области бизнеса или жилья прямо на месте.

    ЗАЧЕМ. Раньше объект недвижимости заводился только через админку, а
    оборудование внутри приходилось держать в голове. Этот тул выделяет
    зону на карте и СРАЗУ показывает, что в неё попало: автоматы с едой
    и бензоколонки подсвечиваются, а в подписи видно их количество.

    Привязывать оборудование не нужно: стоит внутри границ — принадлежит
    объекту. Убрали автомат — зона пересчиталась сама.

    ЛКМ — первый угол, ПКМ — второй угол и создание, R — удалить зону.
    Пока ставите зону, видно её будущие границы, площадь и содержимое.
----------------------------------------------------------------------]]

TOOL.Category = "GRM"
TOOL.Name = "#tool.grm_business.name"
TOOL.Command = nil
TOOL.ConfigName = ""
TOOL.ClientConVar = {
    name = "",
    kind = "business",
    price = "85000",
}

if CLIENT then
    language.Add("tool.grm_business.name", "GRM: бизнес-зона")
    language.Add("tool.grm_business.desc", "Зона бизнеса или жилья с автоматическим учётом оборудования")
    language.Add("tool.grm_business.0", "ЛКМ: первый угол • ПКМ: второй угол и создать • R: удалить зону")

    surface.CreateFont("GRMBizTool_Head",  { font = "Roboto", size = 19, weight = 800, extended = true })
    surface.CreateFont("GRMBizTool_Body",  { font = "Roboto", size = 14, weight = 600, extended = true })
    surface.CreateFont("GRMBizTool_Small", { font = "Roboto", size = 12, weight = 500, extended = true })

    local zones, loose = {}, {}
    local corner = nil

    local COL_BIZ    = Color(245, 200, 60, 225)
    local COL_ESTATE = Color(80, 205, 110, 225)
    local COL_NEW    = Color(120, 255, 160, 245)
    local COL_LOOSE  = Color(255, 130, 90, 240)

    net.Receive("GRM_Estate_ToolData", function()
        local data = net.ReadTable() or {}
        zones = data.zones or {}
        loose = data.loose or {}
    end)

    local function toolActive()
        local ply = LocalPlayer()
        local wep = IsValid(ply) and ply:GetActiveWeapon() or nil
        return IsValid(wep) and wep:GetClass() == "gmod_tool"
            and wep.GetMode and wep:GetMode() == "grm_business", ply, wep
    end

    hook.Add("Think", "GRM_BizZone_Request", function()
        local active, _, wep = toolActive()
        if not active then corner = nil return end
        if (wep.GRMBizRequest or 0) < CurTime() then
            wep.GRMBizRequest = CurTime() + 1
            net.Start("GRM_Estate_ToolReq") net.SendToServer()
        end
    end)

    GRM = GRM or {}
    GRM.BusinessToolCorner = function(v) corner = v end

    local function label3D(pos, text, sub, col, scale)
        cam.Start3D2D(pos, Angle(0, EyeAngles().y - 90, 90), scale or 0.1)
            local w = math.max(300, string.len(text) * 11)
            draw.RoundedBox(6, -w / 2, -26, w, sub and 52 or 34, Color(10, 15, 22, 232))
            draw.SimpleText(text, "GRMBizTool_Head", 0, sub and -12 or -8, col,
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            if sub then
                draw.SimpleText(sub, "GRMBizTool_Small", 0, 12, Color(195, 210, 230),
                    TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        cam.End3D2D()
    end

    --- Сколько оборудования попадёт в прямоугольник: считаем на клиенте,
    --- чтобы предпросмотр не дёргал сервер на каждый кадр.
    local function countInside(mn, mx)
        local n = 0
        for _, row in ipairs(loose or {}) do
            if row.x >= mn.x and row.y >= mn.y and row.z >= mn.z
                and row.x <= mx.x and row.y <= mx.y and row.z <= mx.z then
                n = n + 1
            end
        end
        return n
    end

    hook.Add("PostDrawTranslucentRenderables", "GRM_BizZone_Draw", function(depth, sky, sky3d)
        if depth or sky or sky3d then return end
        local active, ply = toolActive()
        if not active then return end

        -- Существующие зоны: цвет по виду объекта.
        for _, zone in ipairs(zones or {}) do
            local mn, mx = zone.mins or {}, zone.maxs or {}
            local mins = Vector(mn.x or 0, mn.y or 0, mn.z or 0)
            local maxs = Vector(mx.x or 0, mx.y or 0, mx.z or 0)
            local center = (mins + maxs) * 0.5
            local col = zone.kind == "estate" and COL_ESTATE or COL_BIZ
            render.DrawWireframeBox(center, angle_zero, mins - center, maxs - center, col, true)

            local title = (zone.kind == "estate" and "ЖИЛЬЁ: " or "БИЗНЕС: ")
                .. tostring(zone.name or "")
            local sub = ("%d м²  •  %s"):format(zone.area or 0,
                zone.vacant and ("СВОБОДНО · " .. tostring(zone.price or 0) .. " GRM")
                or ("владелец: " .. tostring(zone.owner ~= "" and zone.owner or "—")))
            -- Для бизнеса сразу показываем найденное оборудование.
            if zone.kind == "business" then
                sub = sub .. "  •  " .. tostring(zone.summary ~= "" and zone.summary or "пусто")
            end
            label3D(center + Vector(0, 0, (maxs.z - mins.z) * 0.5 + 14), title, sub, col, 0.1)
        end

        --[[ Оборудование вне зон: админ сразу видит, что осталось
             неоформленным, и не ищет автоматы по карте вручную. ]]
        for _, row in ipairs(loose or {}) do
            local pos = Vector(row.x, row.y, row.z + 46)
            render.DrawWireframeSphere(pos, 14, 7, 7, COL_LOOSE, true)
        end

        -- Предпросмотр новой зоны.
        if corner and IsValid(ply) then
            local tr = ply:GetEyeTrace()
            local a, b = corner, tr.HitPos
            local mn = Vector(math.min(a.x, b.x), math.min(a.y, b.y), math.min(a.z, b.z))
            local mx = Vector(math.max(a.x, b.x), math.max(a.y, b.y), math.max(a.z, b.z) + 190)
            local center = (mn + mx) * 0.5
            render.DrawWireframeBox(center, angle_zero, mn - center, mx - center, COL_NEW, true)
            render.DrawWireframeSphere(a, 12, 8, 8, Color(255, 230, 120, 250), true)

            local area = math.floor(((mx.x - mn.x) / 39.37) * ((mx.y - mn.y) / 39.37))
            local inside = countInside(mn, mx)
            local kind = GetConVar("grm_business_kind"):GetString()
            label3D(center + Vector(0, 0, (mx.z - mn.z) * 0.5 + 12),
                kind == "estate" and "НОВАЯ ЗОНА ЖИЛЬЯ" or "НОВАЯ БИЗНЕС-ЗОНА",
                ("%d м²  •  попадёт точек: %d  •  ПКМ — создать"):format(area, inside),
                COL_NEW, 0.09)
        end
    end)

    hook.Add("HUDPaint", "GRM_BizZone_HUD", function()
        if not toolActive() then return end
        local kind = GetConVar("grm_business_kind"):GetString()
        local lines = {
            { "ЛКМ", corner and "переставить первый угол" or "первый угол зоны" },
            { "ПКМ", corner and "второй угол и создать" or "сначала поставьте первый угол" },
            { "R", "удалить зону под прицелом" },
        }
        local w, h = 560, 52 + #lines * 22
        --[[ Подсказка не должна налезать на панель «СОСТОЯНИЕ» (жалоба
             владельца 27.08: «оно в ХУД впадает»). HUD публикует свой
             прямоугольник в GRM.HUD.StatusRect — встаём ровно над ним,
             а если HUD выключен, отступаем от низа экрана по-старому. ]]
        local x, y = 24, ScrH() - h - 120
        local sr = GRM.HUD and GRM.HUD.StatusRect
        if istable(sr) and (tonumber(sr.y) or 0) > 0 then
            x = tonumber(sr.x) or x
            y = (tonumber(sr.y) or y) - h - 14
        end
        -- Совсем к потолку прижимать тоже нельзя: там висит имя тула.
        y = math.max(y, 110)
        draw.RoundedBox(8, x, y, w, h, Color(12, 16, 24, 226))
        draw.RoundedBox(0, x, y, 4, h, kind == "estate" and COL_ESTATE or COL_BIZ)
        draw.SimpleText(kind == "estate" and "GRM: ЗОНА ЖИЛЬЯ" or "GRM: БИЗНЕС-ЗОНА",
            "GRMBizTool_Body", x + 14, y + 8, kind == "estate" and COL_ESTATE or COL_BIZ,
            TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        for i, l in ipairs(lines) do
            draw.SimpleText(l[1], "GRMBizTool_Small", x + 14, y + 28 + (i - 1) * 22,
                Color(150, 200, 255), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText(l[2], "GRMBizTool_Small", x + 60, y + 28 + (i - 1) * 22,
                Color(225, 233, 245), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end
        draw.SimpleText(("зон: %d  •  оборудование вне зон: %d"):format(#(zones or {}), #(loose or {})),
            "GRMBizTool_Small", x + w - 14, y + 8,
            #(loose or {}) > 0 and COL_LOOSE or Color(160, 200, 170),
            TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
        draw.SimpleText("Оборудование внутри зоны учитывается само — привязывать не нужно",
            "GRMBizTool_Small", x + 14, y + h - 20, Color(150, 165, 185),
            TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end)

    function TOOL.BuildCPanel(panel)
        panel:AddControl("Header", { Description =
            "Зона бизнеса или жилья.\n\n" ..
            "Оборудование внутри границ учитывается автоматически: автоматы с едой " ..
            "и бензоколонки не нужно привязывать вручную.\n\n" ..
            "Оранжевыми шарами подсвечено оборудование, которое пока не входит " ..
            "ни в одну зону." })
        panel:TextEntry("Название объекта", "grm_business_name")
        local kind = panel:ComboBox("Вид объекта", "grm_business_kind")
        kind:AddChoice("Бизнес (жёлтый значок)", "business")
        kind:AddChoice("Жильё (зелёный значок)", "estate")
        panel:TextEntry("Цена покупки, GRM", "grm_business_price")
        panel:Help("ЛКМ — первый угол, ПКМ — второй угол и создание.\n" ..
            "R по зоне — удалить её (только если объект свободен).\n" ..
            "Владельцы, аренда и коммунальные — в окне /property_admin.")
    end
end

function TOOL:LeftClick(trace)
    if CLIENT then
        if IsFirstTimePredicted() and GRM and GRM.BusinessToolCorner then
            GRM.BusinessToolCorner(trace.HitPos)
        end
        return true
    end
    local owner = self:GetOwner()
    if not IsValid(owner) or not owner:IsSuperAdmin() then return false end
    self.GRM_BizCorner = trace.HitPos
    if GRM.Notify then
        GRM.Notify(owner, "Первый угол зоны поставлен. ПКМ — второй угол.", 120, 200, 255)
    end
    return true
end

function TOOL:RightClick(trace)
    if CLIENT then
        if IsFirstTimePredicted() and GRM and GRM.BusinessToolCorner then
            GRM.BusinessToolCorner(nil)
        end
        return true
    end
    local owner = self:GetOwner()
    if not IsValid(owner) or not owner:IsSuperAdmin() then return false end

    local a = self.GRM_BizCorner
    if not a then
        if GRM.Notify then GRM.Notify(owner, "Сначала ЛКМ — первый угол зоны.", 255, 170, 90) end
        return false
    end
    if not (GRM.Estate and GRM.Estate.CreateZone) then
        if GRM.Notify then GRM.Notify(owner, "Модуль зон не загружен.", 255, 140, 110) end
        return false
    end

    local ok, msg = GRM.Estate.CreateZone(owner, a, trace.HitPos,
        self:GetClientInfo("name"), self:GetClientInfo("kind"),
        tonumber(self:GetClientInfo("price")) or 0)
    self.GRM_BizCorner = nil
    if GRM.Notify then
        GRM.Notify(owner, tostring(msg), ok and 100 or 255, ok and 220 or 150, ok and 130 or 110)
    end
    return ok == true
end

function TOOL:Reload(trace)
    if CLIENT then
        if IsFirstTimePredicted() and GRM and GRM.BusinessToolCorner then
            GRM.BusinessToolCorner(nil)
        end
        return true
    end
    local owner = self:GetOwner()
    if not IsValid(owner) or not owner:IsSuperAdmin() then return false end
    if not (GRM.Estate and GRM.Estate.DeleteZoneAt) then return false end

    local ok, msg = GRM.Estate.DeleteZoneAt(owner, trace.HitPos)
    if GRM.Notify then
        GRM.Notify(owner, tostring(msg), ok and 100 or 255, ok and 220 or 150, ok and 130 or 110)
    end
    return ok == true
end
