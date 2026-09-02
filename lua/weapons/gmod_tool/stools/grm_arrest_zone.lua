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

    -- плашка подписи: угол — скретч, краски — константы (§6.1.8). Слить три
    -- копии label3D в общий хелпер — кандидат следующей волны (шрифты и
    -- минимальные ширины различаются).
    local LBL_ANG = Angle(0, 0, 90)
    local LBL_BG = Color(10, 15, 22, 232)
    local LBL_SUB = Color(195, 210, 230)

    local function label3D(pos, text, sub, col, scale)
        LBL_ANG.y = EyeAngles().y - 90
        cam.Start3D2D(pos, LBL_ANG, scale or 0.1)
            local w = math.max(280, string.len(text) * 11)
            draw.RoundedBox(6, -w / 2, -26, w, sub and 52 or 34, LBL_BG)
            draw.SimpleText(text, "GRMArrestTool_Head", 0, sub and -12 or -8, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            if sub then
                draw.SimpleText(sub, "GRMArrestTool_Small", 0, 12, LBL_SUB, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        cam.End3D2D()
    end

    -- Обводка зон рисуется каждый кадр: боксы/подписи без аллокаций —
    -- геометрия в скретч-векторах (потребление немедленное, цикл зон
    -- последовательный; §6.1.8)
    local AZ_MIN = Vector(0, 0, 0)
    local AZ_MAX = Vector(0, 0, 0)
    local AZ_CENTER = Vector(0, 0, 0)
    local AZ_EXT_MIN = Vector(0, 0, 0)
    local AZ_EXT_MAX = Vector(0, 0, 0)
    local AZ_CORNER_COL = Color(255, 230, 120, 250)

    hook.Add("PostDrawTranslucentRenderables", "GRM_ArrestZone_Draw", function(depth, sky, sky3d)
        if depth or sky or sky3d then return end
        local active, ply = toolActive()
        if not active then return end

        for _, zone in ipairs(zones or {}) do
            local mn, mx = zone.min or {}, zone.max or {}
            local mins, maxs = AZ_MIN, AZ_MAX
            mins.x = mn.x or 0; mins.y = mn.y or 0; mins.z = mn.z or 0
            maxs.x = mx.x or 0; maxs.y = mx.y or 0; maxs.z = mx.z or 0
            local center = AZ_CENTER
            center.x = (mins.x + maxs.x) * 0.5
            center.y = (mins.y + maxs.y) * 0.5
            center.z = (mins.z + maxs.z) * 0.5
            AZ_EXT_MIN.x = mins.x - center.x; AZ_EXT_MIN.y = mins.y - center.y; AZ_EXT_MIN.z = mins.z - center.z
            AZ_EXT_MAX.x = maxs.x - center.x; AZ_EXT_MAX.y = maxs.y - center.y; AZ_EXT_MAX.z = maxs.z - center.z
            render.DrawWireframeBox(center, angle_zero, AZ_EXT_MIN, AZ_EXT_MAX, COL, true)
            center.z = center.z + (maxs.z - mins.z) * 0.5 + 12
            label3D(center,
                "ЗОНА: " .. tostring(zone.name or "Тюрьма"),
                ("%d x %d юнитов  •  карта %s"):format(maxs.x - mins.x, maxs.y - mins.y,
                    string.upper(tostring(zone.map or zoneMap or "?"))), COL, 0.1)
        end

        if corner and IsValid(ply) then
            local tr = ply:GetEyeTrace()
            local a, b = corner, tr.HitPos
            local mn, mx = AZ_MIN, AZ_MAX
            mn.x = math.min(a.x, b.x); mn.y = math.min(a.y, b.y); mn.z = math.min(a.z, b.z)
            mx.x = math.max(a.x, b.x); mx.y = math.max(a.y, b.y); mx.z = math.max(a.z, b.z) + 160
            local center = AZ_CENTER
            center.x = (mn.x + mx.x) * 0.5
            center.y = (mn.y + mx.y) * 0.5
            center.z = (mn.z + mx.z) * 0.5
            AZ_EXT_MIN.x = mn.x - center.x; AZ_EXT_MIN.y = mn.y - center.y; AZ_EXT_MIN.z = mn.z - center.z
            AZ_EXT_MAX.x = mx.x - center.x; AZ_EXT_MAX.y = mx.y - center.y; AZ_EXT_MAX.z = mx.z - center.z
            render.DrawWireframeBox(center, angle_zero, AZ_EXT_MIN, AZ_EXT_MAX, COL_NEW, true)
            render.DrawWireframeSphere(a, 12, 8, 8, AZ_CORNER_COL, true)
            center.z = center.z + (mx.z - mn.z) * 0.5 + 10
            label3D(center, "НОВАЯ ЗОНА ТЮРЬМЫ",
                ("%d x %d юнитов  •  ПКМ — подтвердить"):format(mx.x - mn.x, mx.y - mn.y), COL_NEW, 0.09)
        end
    end)

    -- Палитра подсказки: константы загрузки файла, не по 6 Color() на кадр
    -- (§6.1.8)
    local AZ_BG = Color(12, 16, 24, 226)
    local AZ_BAR = Color(255, 150, 70)
    local AZ_HEAD = Color(255, 190, 120)
    local AZ_LABEL = Color(150, 200, 255)
    local AZ_VALUE = Color(225, 233, 245)
    local AZ_FOOT = Color(160, 200, 170)

    hook.Add("HUDPaint", "GRM_ArrestZone_HUD", function()
        if not toolActive() then return end
        local lines = {
            { "ЛКМ", corner and "переставить первый угол" or "первый угол зоны" },
            { "ПКМ", corner and "второй угол и сохранить" or "сначала поставьте первый угол" },
            { "R", "удалить зону под прицелом" },
        }
        local w, h = 520, 34 + #lines * 22
        local x, y = 24, ScrH() - h - 120
        draw.RoundedBox(8, x, y, w, h, AZ_BG)
        draw.RoundedBox(0, x, y, 4, h, AZ_BAR)
        draw.SimpleText("GRM: ЗОНА ТЮРЬМЫ — КАРТА " .. string.upper(tostring(zoneMap ~= "" and zoneMap or game.GetMap())),
            "GRMArrestTool_Body", x + 14, y + 8, AZ_HEAD, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        for i, l in ipairs(lines) do
            draw.SimpleText(l[1], "GRMArrestTool_Small", x + 14, y + 28 + (i - 1) * 22, AZ_LABEL, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText(l[2], "GRMArrestTool_Small", x + 60, y + 28 + (i - 1) * 22, AZ_VALUE, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end
        draw.SimpleText(("зон на карте: %d"):format(#(zones or {})), "GRMArrestTool_Small",
            x + w - 14, y + 8, AZ_FOOT, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
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
