--[[--------------------------------------------------------------------
    GRM: зона тюрьмы — прямоугольная область, внутри которой разрешён
    арест и содержание.

    Разметка ПРИВЯЗАНА К КАРТЕ: тул показывает только зоны текущей карты,
    а зоны, размеченные в другом городе, сюда не попадают и не срабатывают
    (заказ владельца 21.08).

    ЛКМ — первый угол, ПКМ — второй угол и сохранение, R — удалить зону
    под прицелом. Пока ставите зону, видно её будущие границы и размер.
----------------------------------------------------------------------]]

TOOL.Category = "GRM"
TOOL.Name = "#tool.grm_arrest_zone.name"
TOOL.Command = nil
TOOL.ConfigName = ""
TOOL.ClientConVar = { name = "Тюрьма" }

local function A() return GRM and GRM.Arrest end

if CLIENT then
    language.Add("tool.grm_arrest_zone.name", "GRM: зона тюрьмы")
    language.Add("tool.grm_arrest_zone.desc", "Зона ареста и содержания — своя для каждой карты")
    language.Add("tool.grm_arrest_zone.0", "ЛКМ: первый угол • ПКМ: второй угол и сохранить • R: удалить зону")

    surface.CreateFont("GRMArrestTool_Head", { font = "Roboto", size = 19, weight = 800, extended = true })
    surface.CreateFont("GRMArrestTool_Body", { font = "Roboto", size = 14, weight = 600, extended = true })
    surface.CreateFont("GRMArrestTool_Small", { font = "Roboto", size = 12, weight = 500, extended = true })

    local zones, zoneMap = {}, ""
    local corner = nil

    net.Receive("GRM_Arrest_ZoneData", function()
        zoneMap = net.ReadString()
        zones = net.ReadTable() or {}
    end)

    local function toolActive()
        local ply = LocalPlayer()
        local wep = IsValid(ply) and ply:GetActiveWeapon() or nil
        return IsValid(wep) and wep:GetClass() == "gmod_tool"
            and wep.GetMode and wep:GetMode() == "grm_arrest_zone", ply, wep
    end

    hook.Add("Think", "GRM_ArrestZone_Request", function()
        local active, _, wep = toolActive()
        if not active then corner = nil return end
        if (wep.GRMZoneRequest or 0) < CurTime() then
            wep.GRMZoneRequest = CurTime() + 1
            net.Start("GRM_Arrest_ZoneRequest") net.SendToServer()
        end
    end)

    GRM = GRM or {}
    GRM.ArrestToolCorner = function(v) corner = v end

    local COL = Color(255, 150, 70, 225)
    local COL_NEW = Color(120, 255, 160, 245)

    local function label3D(pos, text, sub, col, scale)
        cam.Start3D2D(pos, Angle(0, EyeAngles().y - 90, 90), scale or 0.1)
            local w = math.max(280, string.len(text) * 11)
            draw.RoundedBox(6, -w / 2, -26, w, sub and 52 or 34, Color(10, 15, 22, 232))
            draw.SimpleText(text, "GRMArrestTool_Head", 0, sub and -12 or -8, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            if sub then
                draw.SimpleText(sub, "GRMArrestTool_Small", 0, 12, Color(195, 210, 230), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        cam.End3D2D()
    end

    hook.Add("PostDrawTranslucentRenderables", "GRM_ArrestZone_Draw", function(depth, sky, sky3d)
        if depth or sky or sky3d then return end
        local active, ply = toolActive()
        if not active then return end

        for _, zone in ipairs(zones or {}) do
            local mn, mx = zone.min or {}, zone.max or {}
            local mins = Vector(mn.x or 0, mn.y or 0, mn.z or 0)
            local maxs = Vector(mx.x or 0, mx.y or 0, mx.z or 0)
            local center = (mins + maxs) * 0.5
            render.DrawWireframeBox(center, angle_zero, mins - center, maxs - center, COL, true)
            label3D(center + Vector(0, 0, (maxs.z - mins.z) * 0.5 + 12),
                "ЗОНА: " .. tostring(zone.name or "Тюрьма"),
                ("%d x %d юнитов  •  карта %s"):format(maxs.x - mins.x, maxs.y - mins.y,
                    string.upper(tostring(zone.map or zoneMap or "?"))), COL, 0.1)
        end

        if corner and IsValid(ply) then
            local tr = ply:GetEyeTrace()
            local a, b = corner, tr.HitPos
            local mn = Vector(math.min(a.x, b.x), math.min(a.y, b.y), math.min(a.z, b.z))
            local mx = Vector(math.max(a.x, b.x), math.max(a.y, b.y), math.max(a.z, b.z) + 160)
            local center = (mn + mx) * 0.5
            render.DrawWireframeBox(center, angle_zero, mn - center, mx - center, COL_NEW, true)
            render.DrawWireframeSphere(a, 12, 8, 8, Color(255, 230, 120, 250), true)
            label3D(center + Vector(0, 0, (mx.z - mn.z) * 0.5 + 10), "НОВАЯ ЗОНА ТЮРЬМЫ",
                ("%d x %d юнитов  •  ПКМ — подтвердить"):format(mx.x - mn.x, mx.y - mn.y), COL_NEW, 0.09)
        end
    end)

    hook.Add("HUDPaint", "GRM_ArrestZone_HUD", function()
        if not toolActive() then return end
        local lines = {
            { "ЛКМ", corner and "переставить первый угол" or "первый угол зоны" },
            { "ПКМ", corner and "второй угол и сохранить" or "сначала поставьте первый угол" },
            { "R", "удалить зону под прицелом" },
        }
        local w, h = 520, 34 + #lines * 22
        local x, y = 24, ScrH() - h - 120
        draw.RoundedBox(8, x, y, w, h, Color(12, 16, 24, 226))
        draw.RoundedBox(0, x, y, 4, h, Color(255, 150, 70))
        draw.SimpleText("GRM: ЗОНА ТЮРЬМЫ — КАРТА " .. string.upper(tostring(zoneMap ~= "" and zoneMap or game.GetMap())),
            "GRMArrestTool_Body", x + 14, y + 8, Color(255, 190, 120), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        for i, l in ipairs(lines) do
            draw.SimpleText(l[1], "GRMArrestTool_Small", x + 14, y + 28 + (i - 1) * 22, Color(150, 200, 255), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText(l[2], "GRMArrestTool_Small", x + 60, y + 28 + (i - 1) * 22, Color(225, 233, 245), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end
        draw.SimpleText(("зон на карте: %d"):format(#(zones or {})), "GRMArrestTool_Small",
            x + w - 14, y + 8, Color(160, 200, 170), TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
    end)

    function TOOL.BuildCPanel(panel)
        panel:AddControl("Header", { Description =
            "Зона тюрьмы: внутри неё разрешён арест и содержание.\n" ..
            "Разметка своя для каждой карты — на другой карте эти зоны не появятся." })
        panel:TextEntry("Название зоны", "grm_arrest_zone_name")
        panel:Help("ЛКМ — первый угол, ПКМ — второй угол и сохранение.\nR по зоне — удалить её.\n" ..
            "Список карт с разметкой и перенос — в окне /arrest_admin.")
    end
end

function TOOL:LeftClick(trace)
    if CLIENT then
        if IsFirstTimePredicted() and GRM and GRM.ArrestToolCorner then
            GRM.ArrestToolCorner(trace.HitPos)
        end
        return true
    end
    local owner = self:GetOwner()
    if not IsValid(owner) or not owner:IsSuperAdmin() then return false end
    self.GRM_FirstCorner = trace.HitPos
    if GRM.Notify then GRM.Notify(owner, "Первый угол зоны поставлен. ПКМ — второй угол.", 120, 200, 255) end
    return true
end

function TOOL:RightClick(trace)
    if CLIENT then
        if IsFirstTimePredicted() and GRM and GRM.ArrestToolCorner then GRM.ArrestToolCorner(nil) end
        return true
    end
    local owner = self:GetOwner()
    if not IsValid(owner) or not owner:IsSuperAdmin() then return false end
    local a = self.GRM_FirstCorner
    if not a then
        if GRM.Notify then GRM.Notify(owner, "Сначала ЛКМ — первый угол зоны.", 255, 170, 90) end
        return false
    end
    local arrest = A()
    if not (arrest and arrest.AddPrisonZone) then return false end
    arrest.AddPrisonZone(a, trace.HitPos, self:GetClientInfo("name"))
    self.GRM_FirstCorner = nil
    if GRM.Notify then
        GRM.Notify(owner, ("Зона тюрьмы сохранена для карты %s."):format(string.upper(arrest.MapName())), 100, 220, 130)
    end
    return true
end

function TOOL:Reload(trace)
    if CLIENT then return true end
    local owner = self:GetOwner()
    if not IsValid(owner) or not owner:IsSuperAdmin() then return false end
    local arrest = A()
    if not arrest then return false end

    local pos = trace.HitPos
    local list = arrest.Cfg and arrest.Cfg.prisonZones or {}
    for i = #list, 1, -1 do
        local zone = list[i]
        local mn, mx = zone.min or {}, zone.max or {}
        if pos.x >= (mn.x or 0) and pos.x <= (mx.x or 0)
            and pos.y >= (mn.y or 0) and pos.y <= (mx.y or 0)
            and pos.z >= ((mn.z or 0) - 64) and pos.z <= ((mx.z or 0) + 64) then
            table.remove(list, i)
            if arrest.SaveMapData then arrest.SaveMapData() end
            if GRM.Notify then GRM.Notify(owner, "Зона тюрьмы удалена.", 255, 180, 120) end
            return true
        end
    end
    if GRM.Notify then GRM.Notify(owner, "Здесь нет зоны тюрьмы.", 255, 170, 90) end
    return false
end
