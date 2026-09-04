--[[--------------------------------------------------------------------
    GRM: координаты — инструмент замеров (заказ владельца 22.08).

    ЗАЧЕМ. Чтобы ставить знаки, места выдачи, точки спавна и любые пропы
    по числам, а не «на глаз», нужно видеть то, что видит движок:
    позицию объекта, его углы, габариты, размер каждой стороны, точку
    попадания, нормаль поверхности и локальные координаты этой точки
    внутри объекта.

    ЧТО ДЕЛАЕТ:
      • ЛКМ  — замерить объект под прицелом: класс, модель, позиция, углы,
               габарит (мин/макс/размер), точка и нормаль поверхности,
               локальные координаты попадания, ближайшая грань;
      • ПКМ  — поставить/снять метку: две метки дают расстояние по прямой
               и по осям X/Y/Z, а также угол между ними;
      • R    — сбросить метки и замер.

    Всё измеренное печатается в консоль (F9/копировать) и показывается
    панелью на экране, а метки видно в мире.

    ЛОГИКА ЗАМЕРА ЧИСТАЯ: GRM.Measure.Describe/SideList/Delta работают на
    обычных таблицах {x,y,z} и потому целиком проверяются стендом.
----------------------------------------------------------------------]]

TOOL.Category = "GRM"
TOOL.Name = "#tool.grm_measure.name"
TOOL.Command = nil
TOOL.ConfigName = ""
TOOL.ClientConVar = {
    decimals = "1",
    world    = "1",
}

if CLIENT then
    language.Add("tool.grm_measure.name", "GRM Координаты")
    language.Add("tool.grm_measure.desc", "Позиция, углы, габариты, стороны и нормали объектов")
    language.Add("tool.grm_measure.0", "ЛКМ: замерить объект • ПКМ: метка и расстояние • R: сброс")
end

GRM = GRM or {}
GRM.Measure = GRM.Measure or {}
local M = GRM.Measure
M.Version = "1.0.0"

-----------------------------------------------------------------------
-- ЧИСТАЯ ЧАСТЬ (без игры — гоняется стендом)
-----------------------------------------------------------------------

local function num(v) return tonumber(v) or 0 end

--- Округление до знаков после запятой.
function M.Round(v, decimals)
    local d = math.max(0, math.floor(tonumber(decimals) or 1))
    local m = 10 ^ d
    return math.floor(num(v) * m + 0.5) / m
end

--- Габарит по мин/макс: размеры сторон и объём.
function M.SideList(mins, maxs)
    mins, maxs = mins or {}, maxs or {}
    local sx = num(maxs.x) - num(mins.x)
    local sy = num(maxs.y) - num(mins.y)
    local sz = num(maxs.z) - num(mins.z)
    return {
        x = sx, y = sy, z = sz,
        volume = sx * sy * sz,
        -- самая тонкая ось: по ней у плоских объектов идёт нормаль лицевой стороны
        thin = (sx <= sy and sx <= sz) and "x" or ((sy <= sz) and "y" or "z"),
        long = (sx >= sy and sx >= sz) and "x" or ((sy >= sz) and "y" or "z"),
    }
end

--- Разница двух точек: по осям, по прямой и по горизонтали.
function M.Delta(a, b)
    a, b = a or {}, b or {}
    local dx, dy, dz = num(b.x) - num(a.x), num(b.y) - num(a.y), num(b.z) - num(a.z)
    return {
        x = dx, y = dy, z = dz,
        length = math.sqrt(dx * dx + dy * dy + dz * dz),
        flat = math.sqrt(dx * dx + dy * dy),
        yaw = math.deg(math.atan2(dy, dx)),
    }
end

--- Человеческие строки замера. info — обычная таблица чисел и строк.
function M.Describe(info, decimals)
    info = info or {}
    local r = function(v) return M.Round(v, decimals) end
    local out = {}
    local function line(text) out[#out + 1] = text end

    line("ОБЪЕКТ: " .. tostring(info.class or "мир"))
    if info.model and info.model ~= "" then line("Модель: " .. tostring(info.model)) end
    if info.name and info.name ~= "" then line("Имя: " .. tostring(info.name)) end

    local p = info.pos or {}
    line(("Позиция: %s %s %s"):format(r(p.x), r(p.y), r(p.z)))
    local a = info.ang or {}
    line(("Углы (p y r): %s %s %s"):format(r(a.p), r(a.y), r(a.r)))

    if info.mins and info.maxs then
        local s = M.SideList(info.mins, info.maxs)
        line(("Габарит: %s × %s × %s"):format(r(s.x), r(s.y), r(s.z)))
        line(("Тонкая ось: %s   длинная ось: %s"):format(s.thin, s.long))
        line(("Мин: %s %s %s   Макс: %s %s %s"):format(
            r(info.mins.x), r(info.mins.y), r(info.mins.z),
            r(info.maxs.x), r(info.maxs.y), r(info.maxs.z)))
    end

    if info.hit then
        line(("Точка на поверхности: %s %s %s"):format(r(info.hit.x), r(info.hit.y), r(info.hit.z)))
    end
    if info.normal then
        line(("Нормаль поверхности: %s %s %s"):format(r(info.normal.x), r(info.normal.y), r(info.normal.z)))
    end
    if info.localHit then
        line(("Локально в объекте: %s %s %s"):format(r(info.localHit.x), r(info.localHit.y), r(info.localHit.z)))
    end
    if info.localNormalAng then
        local n = info.localNormalAng
        line(("Локальные углы поверхности: %s %s %s"):format(r(n.p), r(n.y), r(n.r)))
    end
    if info.distance then line(("Расстояние от вас: %s"):format(r(info.distance))) end
    if info.surface and info.surface ~= "" then line("Материал: " .. tostring(info.surface)) end
    return out
end

--- Строки для пары меток.
function M.DescribeMarks(a, b, decimals)
    local out = {}
    if not a then return out end
    local r = function(v) return M.Round(v, decimals) end
    out[#out + 1] = ("Метка A: %s %s %s"):format(r(a.x), r(a.y), r(a.z))
    if not b then
        out[#out + 1] = "Метка B: не поставлена (ПКМ)"
        return out
    end
    local d = M.Delta(a, b)
    out[#out + 1] = ("Метка B: %s %s %s"):format(r(b.x), r(b.y), r(b.z))
    out[#out + 1] = ("Разница: X %s   Y %s   Z %s"):format(r(d.x), r(d.y), r(d.z))
    out[#out + 1] = ("Расстояние: %s   по земле: %s   курс: %s°"):format(r(d.length), r(d.flat), r(d.yaw))
    return out
end

-----------------------------------------------------------------------
-- ИГРОВАЯ ЧАСТЬ
-----------------------------------------------------------------------

local function vecT(v) return { x = v.x, y = v.y, z = v.z } end
local function angT(a) return { p = a.p, y = a.y, r = a.r } end

--- Собрать замер по трассировке (общая для тула и команды /координаты).
function M.Read(ply, tr)
    if not IsValid(ply) then return nil end
    tr = tr or ((GRM.Perf and GRM.Perf.EyeTrace) and GRM.Perf.EyeTrace(ply) or ply:GetEyeTrace())
    if not tr then return nil end
    local ent = tr.Entity
    local info = {
        hit = vecT(tr.HitPos),
        normal = vecT(tr.HitNormal),
        distance = ply:GetPos():Distance(tr.HitPos),
        surface = tr.HitTexture and tostring(tr.HitTexture) or "",
    }
    if IsValid(ent) and not ent:IsWorld() then
        info.class = ent:GetClass()
        info.model = ent:GetModel() or ""
        info.pos = vecT(ent:GetPos())
        info.ang = angT(ent:GetAngles())
        info.mins = vecT(ent:OBBMins())
        info.maxs = vecT(ent:OBBMaxs())
        info.localHit = vecT(ent:WorldToLocal(tr.HitPos))
        info.localNormalAng = angT(ent:WorldToLocalAngles(tr.HitNormal:Angle()))
        info.name = ent.PrintName or (ent.GetNWString and ent:GetNWString("GRM_Plate", "")) or ""
        info.entIndex = ent:EntIndex()
    else
        info.class = "мир (браш карты)"
        info.pos = vecT(tr.HitPos)
        info.ang = angT(tr.HitNormal:Angle())
    end
    return info
end

if SERVER then
    util.AddNetworkString("GRM_Measure_Data")

    local function send(ply, info, marks)
        if not IsValid(ply) then return end
        net.Start("GRM_Measure_Data")
            net.WriteTable({ info = info or {}, marks = marks or {} })
        net.Send(ply)
    end
    M.Send = send

    local function tell(ply, lines)
        for _, l in ipairs(lines or {}) do ply:PrintMessage(HUD_PRINTCONSOLE, "[GRM Координаты] " .. l) end
    end
    M.TellConsole = tell

    --- Команда: замер объекта под прицелом.
    local function coords(ply)
        if not IsValid(ply) then return end
        local info = M.Read(ply)
        if not info then return end
        send(ply, info, ply.GRMMeasureMarks)
        tell(ply, M.Describe(info, 1))
        if GRM.Notify then GRM.Notify(ply, "Замер отправлен: смотрите панель и консоль.", 120, 200, 255) end
    end
    M.Coords = coords

    concommand.Add("grm_coords", coords)

    local CHAT = { ["/координаты"] = true, ["/coords"] = true, ["/замер"] = true }
    local function chat(ply, text)
        local t = string.lower(string.Trim(tostring(text or "")))
        if CHAT[t] then coords(ply) return "" end
    end
    hook.Add("PlayerSay", "GRM_Measure_Chat", function(ply, text) return chat(ply, text) end)
end

if CLIENT then
    surface.CreateFont("GRMMeasure_Head", { font = "Roboto", size = 18, weight = 800, extended = true })
    surface.CreateFont("GRMMeasure_Body", { font = "Roboto", size = 14, weight = 550, extended = true })

    M.Last = M.Last or {}
    M.Marks = M.Marks or {}

    net.Receive("GRM_Measure_Data", function()
        local t = net.ReadTable() or {}
        M.Last = istable(t.info) and t.info or {}
        M.Marks = istable(t.marks) and t.marks or {}
        M.LastAt = CurTime()
    end)

    --- Панель с замером: висит, пока инструмент в руках.
    local MS_BG = Color(12, 17, 25, 232)
    local MS_ACCENT = Color(90, 175, 255)
    local MS_HEAD = Color(120, 205, 255)
    local MS_BODY = Color(232, 238, 246)

    hook.Add("HUDPaint", "GRM_Measure_HUD", function()
        local lp = LocalPlayer()
        if not IsValid(lp) then return end
        local wep = lp:GetActiveWeapon()
        if not IsValid(wep) or wep:GetClass() ~= "gmod_tool" then return end
        local mode = lp:GetInfo("gmod_toolmode")
        if mode ~= "grm_measure" then return end

        local lines = M.Describe(M.Last, GetConVar("grm_measure_decimals"):GetInt())
        local marks = M.DescribeMarks(M.Marks[1], M.Marks[2], GetConVar("grm_measure_decimals"):GetInt())
        if #marks > 0 then
            lines[#lines + 1] = ""
            for _, l in ipairs(marks) do lines[#lines + 1] = l end
        end

        surface.SetFont("GRMMeasure_Body")
        local wide = 320
        for _, l in ipairs(lines) do
            local w = surface.GetTextSize(l)
            if w + 28 > wide then wide = w + 28 end
        end
        local tall = 44 + #lines * 18
        local x, y = 24, ScrH() * 0.22

        draw.RoundedBox(8, x, y, wide, tall, MS_BG)
        draw.RoundedBox(8, x, y, wide, 6, MS_ACCENT)
        draw.SimpleText("GRM · КООРДИНАТЫ", "GRMMeasure_Head", x + 14, y + 14, MS_HEAD,
            TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        for i, l in ipairs(lines) do
            draw.SimpleText(l, "GRMMeasure_Body", x + 14, y + 38 + (i - 1) * 18, MS_BODY,
                TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end
    end)

    --- Метки в мире.
    -- точки/линейка разметки: позиции в скретче, цвета константами (§6.1.8)
    local MS_DOT = Vector(0, 0, 0)
    local MS_DOT_A = Vector(0, 0, 0)
    local MS_DOT_B = Vector(0, 0, 0)
    local MS_DOT_COL = Color(90, 220, 140, 220)
    local MS_LINE_COL = Color(255, 170, 90, 220)
    local MS_LINK_COL = Color(120, 205, 255)

    hook.Add("PostDrawTranslucentRenderables", "GRM_Measure_Marks", function(depth, sky, sky3d)
        if depth or sky or sky3d then return end
        local lp = LocalPlayer()
        if not IsValid(lp) then return end
        local wep = lp:GetActiveWeapon()
        if not IsValid(wep) or wep:GetClass() ~= "gmod_tool" then return end
        if lp:GetInfo("gmod_toolmode") ~= "grm_measure" then return end

        local a, b = M.Marks[1], M.Marks[2]
        local function dot(p, dst, col)
            render.SetColorMaterial()
            dst.x = p.x
            dst.y = p.y
            dst.z = p.z
            render.DrawSphere(dst, 4, 12, 12, col)
        end
        if a then dot(a, MS_DOT, MS_DOT_COL) end
        if b then dot(b, MS_DOT, MS_LINE_COL) end
        if a and b then
            render.SetColorMaterial()
            MS_DOT_A.x = a.x; MS_DOT_A.y = a.y; MS_DOT_A.z = a.z
            MS_DOT_B.x = b.x; MS_DOT_B.y = b.y; MS_DOT_B.z = b.z
            render.DrawLine(MS_DOT_A, MS_DOT_B, MS_LINK_COL, true)
        end
    end)
end

-----------------------------------------------------------------------
-- ДЕЙСТВИЯ ИНСТРУМЕНТА
-----------------------------------------------------------------------

function TOOL:LeftClick(trace)
    if CLIENT then return true end
    local ply = self:GetOwner()
    if not IsValid(ply) then return false end
    local info = GRM.Measure.Read(ply, trace)
    GRM.Measure.Send(ply, info, ply.GRMMeasureMarks)
    GRM.Measure.TellConsole(ply, GRM.Measure.Describe(info, 1))
    return true
end

function TOOL:RightClick(trace)
    if CLIENT then return true end
    local ply = self:GetOwner()
    if not IsValid(ply) or not trace then return false end
    ply.GRMMeasureMarks = ply.GRMMeasureMarks or {}
    local marks = ply.GRMMeasureMarks
    local p = { x = trace.HitPos.x, y = trace.HitPos.y, z = trace.HitPos.z }
    if #marks >= 2 then marks[1], marks[2] = p, nil else marks[#marks + 1] = p end
    GRM.Measure.Send(ply, GRM.Measure.Read(ply, trace), marks)
    if #marks == 2 then
        GRM.Measure.TellConsole(ply, GRM.Measure.DescribeMarks(marks[1], marks[2], 1))
    end
    return true
end

function TOOL:Reload(trace)
    if CLIENT then return true end
    local ply = self:GetOwner()
    if not IsValid(ply) then return false end
    ply.GRMMeasureMarks = {}
    GRM.Measure.Send(ply, {}, {})
    if GRM.Notify then GRM.Notify(ply, "Метки сброшены.", 200, 200, 200) end
    return true
end

function TOOL.BuildCPanel(panel)
    panel:ClearControls()
    panel:Help("Замер объектов: позиция, углы, габариты, стороны, нормали.\n" ..
        "ЛКМ — замерить объект под прицелом.\n" ..
        "ПКМ — поставить метку (две метки дают расстояние).\n" ..
        "R — сбросить метки.\n" ..
        "Команда в чат: /координаты (или /замер).")
    panel:NumSlider("Знаков после запятой", "grm_measure_decimals", 0, 3, 0)
end
