--[[--------------------------------------------------------------------
    GRM Fire Addon — рукава.
    Сервер держит граф (источник → узлы → ствол/стык).
    Клиент рисует кабель. Земля-земля ещё и constraint.Rope.
    Права фракций наложит GRM через хуки (nil = можно всем).
----------------------------------------------------------------------]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.FireAddon = GRM.FireAddon or {}
local A = GRM.FireAddon

A.HoseCfg = A.HoseCfg or {
    MaxLength   = 2200,
    LayStep     = 52,
    Width       = 3,
    Material    = "grm/firehose",
    Sag         = 10,
    TruckSlots  = 4,
    HydrantPorts = 2,
    JunctionOut = 2,
    SprayCost        = 8,
    SprayCostWater   = 8,
    SprayCostFoam    = 4,
    SprayCostPowder  = 2,
    SprayDmg         = 10,
    SprayDmgWater    = 10,
    SprayDmgFoam     = 18,
    SprayDmgPowder   = 24,
}
if A.HoseCfg.MaxLength < 2000 then A.HoseCfg.MaxLength = 2200 end
A.HoseCfg.LayStep = 40
A.HoseCfg.Width = 3
A.HoseBeamHalfW = 1.35
A.HoseBeamHalfH = 0.28

A.NODE_SOURCE    = 0
A.NODE_LAY       = 1
A.NODE_JUNCTION  = 2
A.NODE_NOZZLE    = 3

-- Геометрия смотки: чистые x/y, без GMod API. Стенд грузит этот же файл.
local function xy(v)
    if not v then return 0, 0 end
    return tonumber(v.x) or 0, tonumber(v.y) or 0
end

-- t=0 у prev, t=1 у last. off — расстояние до отрезка (зажатый t).
function A.HoseSegProject(p, a, b)
    local px, py = xy(p)
    local ax, ay = xy(a)
    local bx, by = xy(b)
    local abx, aby = bx - ax, by - ay
    local apx, apy = px - ax, py - ay
    local ab2 = abx * abx + aby * aby
    if ab2 < 1 then
        local dx, dy = px - ax, py - ay
        return 0, math.sqrt(dx * dx + dy * dy)
    end
    local t = (apx * abx + apy * aby) / ab2
    local ct = t
    if ct < 0 then ct = 0 elseif ct > 1 then ct = 1 end
    local cx, cy = ax + abx * ct, ay + aby * ct
    local dx, dy = px - cx, py - cy
    return t, math.sqrt(dx * dx + dy * dy)
end

-- Тяга точки к якорю, если дальше maxSeg (2D, земля).
function A.HoseDragPoint(px, py, ax, ay, maxSeg)
    px, py, ax, ay = tonumber(px) or 0, tonumber(py) or 0, tonumber(ax) or 0, tonumber(ay) or 0
    maxSeg = tonumber(maxSeg) or 40
    local dx, dy = px - ax, py - ay
    local d = math.sqrt(dx * dx + dy * dy)
    if d <= maxSeg or d < 0.001 then return px, py, false, d end
    local s = maxSeg / d
    return ax + dx * s, ay + dy * s, true, d
end

function A.HoseShouldCompact(dist, step)
    step = tonumber(step) or 40
    return (tonumber(dist) or 999) < step * 0.42
end

-- "reel" | "rewind" | "lay" | "idle"
-- reel  = ALT, принудительная смотка
-- rewind = шаг назад по линии / S / скорость к предыдущему узлу
-- lay   = ушли вперёд от последнего узла
function A.HoseMoveHint(p, last, prev, opt)
    opt = opt or {}
    local step = tonumber(opt.step) or 40
    local px, py = xy(p)
    local lx, ly = xy(last)
    local rx, ry = xy(prev)
    local dLast = math.sqrt((px - lx) * (px - lx) + (py - ly) * (py - ly))
    local dPrev = math.sqrt((px - rx) * (px - rx) + (py - ry) * (py - ry))
    local t, off = A.HoseSegProject(p, prev, last)

    if opt.reel then
        if dLast <= 380 or dPrev <= 220 or off <= 160 then
            return "reel"
        end
    end

    local along = (t <= 0.93 and off <= 170)
        or (t < 0 and dPrev <= 240)
        or (dPrev + 8 < dLast)

    if opt.back and (off <= 190 or dLast <= 220 or dPrev <= 220) then
        along = true
    end

    if not along and opt.vel then
        local vx, vy = xy(opt.vel)
        local vlen = math.sqrt(vx * vx + vy * vy)
        if vlen > 40 then
            local tx, ty = rx - px, ry - py
            local tlen = math.sqrt(tx * tx + ty * ty)
            if tlen > 1 and off <= 170 then
                local dot = (vx / vlen) * (tx / tlen) + (vy / vlen) * (ty / tlen)
                if dot > 0.35 and t < 1.12 then along = true end
            end
        end
    end

    if along then return "rewind" end
    if dLast >= step then return "lay" end
    return "idle"
end

function A.CanHose(ply, src, why)
    if not IsValid(ply) then return false end
    local r = hook.Run("GRM_FireAddon_CanHose", ply, src, why or "use")
    if r == false then return false end
    return true
end

function A.HoseCountOn(src)
    -- Зовётся из Think насоса (4/сек) и из бортового NW-тика: полный скан
    -- класса заменён event-реестром GRM.Perf.
    local n = 0
    local hoses = (GRM and GRM.Perf and GRM.Perf.Entities) and GRM.Perf.Entities("grm_fire_hose")
        or ents.FindByClass("grm_fire_hose")
    for _, h in ipairs(hoses) do
        if IsValid(h) and h:GetStartEnt() == src then n = n + 1 end
    end
    return n
end

function A.SourceSlots(src)
    if not IsValid(src) then return 0, 0 end
    local cls = src:GetClass()
    if cls == "grm_fire_pump" then
        local max = src.GetHosesMax and src:GetHosesMax() or A.HoseCfg.TruckSlots
        if max <= 0 then max = A.HoseCfg.TruckSlots end
        return A.HoseCountOn(src), max
    end
    if cls == "grm_fire_hydrant" then
        local max = src.GetPortsMax and src:GetPortsMax() or A.HoseCfg.HydrantPorts
        if max <= 0 then max = A.HoseCfg.HydrantPorts end
        return A.HoseCountOn(src), max
    end
    if cls == "grm_fire_hose_node" and src.GetNodeType and src:GetNodeType() == A.NODE_JUNCTION then
        return A.HoseCountOn(src), A.HoseCfg.JunctionOut
    end
    return 0, 0
end

function A.SourceHasFreeSlot(src)
    local used, max = A.SourceSlots(src)
    return used < max
end

if SERVER then
    function A.TakeHose(ply, src)
        if not IsValid(ply) or not IsValid(src) then return nil, "нет цели" end
        if not A.CanHose(ply, src, "take") then return nil, "нет доступа" end
        if IsValid(ply.GRM_FireHose) then return nil, "у вас уже есть рукав" end
        if not A.SourceHasFreeSlot(src) then return nil, "нет свободных рукавов" end
        if src:GetClass() == "grm_fire_hydrant" and src.GetOpen and not src:GetOpen() then
            return nil, "гидрант закрыт"
        end
        if src:GetClass() == "grm_fire_pump" then
            if src.SetPumpOn then src:SetPumpOn(true) end
        end
        local hose = ents.Create("grm_fire_hose")
        if not IsValid(hose) then return nil, "не создался" end
        hose:SetPos(src:WorldSpaceCenter())
        hose:SetStartEnt(src)
        hose:SetMaxLen(A.HoseCfg.MaxLength)
        hose:Spawn()
        hose:Activate()
        local ok, err = hose:DeployTo(ply)
        if not ok then
            hose:Remove()
            return nil, err or "не выдать"
        end
        if src.SetHosesOut and src.GetHosesMax then
            src:SetHosesOut(A.HoseCountOn(src))
        end
        hook.Run("GRM_FireAddon_HoseTaken", ply, src, hose)
        return hose
    end

    function A.ReturnHose(ply, hose)
        hose = hose or (IsValid(ply) and ply.GRM_FireHose)
        if not IsValid(hose) then return false end
        local src = hose:GetStartEnt()
        hose:Rewind()
        if IsValid(src) and src.SetHosesOut then
            src:SetHosesOut(A.HoseCountOn(src))
        end
        hook.Run("GRM_FireAddon_HoseReturned", ply, src, hose)
        return true
    end

    -- E на своём гидранте/насосе: смотать брошенные или свои рукава.
    function A.RewindAtSource(src, ply)
        if not IsValid(src) then return 0 end
        local n = 0
        for _, h in ipairs(ents.FindByClass("grm_fire_hose")) do
            if IsValid(h) and h:GetStartEnt() == src then
                local holder = h.GetHolder and h:GetHolder() or NULL
                if not IsValid(holder) or holder == ply then
                    if A.ReturnHose(ply, h) then n = n + 1 end
                end
            end
        end
        return n
    end

    -- Рукав стартует здесь или стыкован к этому насосу/гидранту.
    function A.HoseTouches(h, src)
        if not IsValid(h) or not IsValid(src) then return false end
        if h.GetStartEnt and h:GetStartEnt() == src then return true end
        local endN = h.GetEndNode and h:GetEndNode() or NULL
        if not IsValid(endN) then return false end
        if endN == src then return true end
        local p = endN.GetParent and endN:GetParent() or NULL
        return p == src
    end

    -- Сразу смотать все рукава источника (машина удалена / насос снят).
    function A.ClearHosesOn(src)
        local n = 0
        for _, h in ipairs(ents.FindByClass("grm_fire_hose")) do
            if IsValid(h) and A.HoseTouches(h, src) then
                local ply = h.GetHolder and h:GetHolder() or NULL
                if A.ReturnHose(IsValid(ply) and ply or nil, h) then n = n + 1
                elseif IsValid(h) then h:Remove() n = n + 1 end
            end
        end
        return n
    end

    -- Рукава без живого насоса/гидранта — смотать немедленно.
    function A.ClearOrphanHoses()
        local n = 0
        for _, h in ipairs(ents.FindByClass("grm_fire_hose")) do
            if IsValid(h) then
                local src = h.GetStartEnt and h:GetStartEnt() or NULL
                if not IsValid(src) then
                    if h.Rewind then h:Rewind() else h:Remove() end
                    n = n + 1
                end
            end
        end
        return n
    end

    function A.GiveHose(ply, src)
        if IsValid(src) then
            local h, err = A.TakeHose(ply, src)
            return h ~= nil, err
        end
        if not IsValid(ply) then return false end
        if ply:HasWeapon("weapon_grm_hose") then return true end
        ply:Give("weapon_grm_hose")
        return ply:HasWeapon("weapon_grm_hose")
    end

    function A.NearestHydrant(pos, maxd)
        if not isvector(pos) then return nil end
        maxd = tonumber(maxd) or 2200
        local best, bestD
        for _, h in ipairs(ents.FindByClass("grm_fire_hydrant")) do
            if IsValid(h) then
                local d = h:GetPos():Distance(pos)
                if d <= maxd and (not best or d < bestD) then
                    best, bestD = h, d
                end
            end
        end
        return best, bestD
    end

    -- Прямая линия насос ↔ гидрант (без игрока в руках).
    function A.LaySupplyLine(src, dst)
        if not IsValid(src) or not IsValid(dst) then return nil, "нет цели" end
        if src == dst then return nil, "тот же объект" end
        if not A.SourceHasFreeSlot(src) then return nil, "нет свободного порта на источнике" end
        if not A.SourceHasFreeSlot(dst) then return nil, "нет свободного порта на насосе" end
        if src:GetClass() == "grm_fire_hydrant" and src.GetOpen and not src:GetOpen() then
            return nil, "гидрант закрыт — откройте E"
        end
        local a = src:WorldSpaceCenter() + Vector(0, 0, 6)
        local b = dst:WorldSpaceCenter() + Vector(0, 0, 6)
        local dist = a:Distance(b)
        local maxL = A.HoseCfg.MaxLength or 2200
        if dist > maxL then return nil, ("далеко (%.0f > %d)"):format(dist, maxL) end
        local hose = ents.Create("grm_fire_hose")
        if not IsValid(hose) then return nil, "не создался рукав" end
        hose:SetPos(a)
        hose:SetStartEnt(src)
        hose:SetMaxLen(maxL)
        hose:Spawn()
        hose:Activate()
        local startN = hose:MakeNode(A.NODE_SOURCE, a, src)
        if not IsValid(startN) then hose:Remove() return nil, "узел" end
        local last = startN
        local step = math.max(36, A.HoseCfg.LayStep or 40)
        local nsteps = math.max(0, math.floor(dist / step) - 1)
        for i = 1, nsteps do
            local p = LerpVector(i / (nsteps + 1), a, b)
            local tr = util.TraceLine({
                start = p + Vector(0, 0, 48),
                endpos = p - Vector(0, 0, 96),
                mask = MASK_SOLID_BRUSHONLY,
            })
            if tr.Hit then p = tr.HitPos + Vector(0, 0, 3) end
            local node = hose:MakeNode(A.NODE_LAY, p)
            if IsValid(node) then
                last:SetNextNode(node)
                hose:Link(last, node)
                last = node
            end
        end
        local dock = hose:MakeNode(A.NODE_SOURCE, b, dst)
        if not IsValid(dock) then hose:Remove() return nil, "стык" end
        last:SetNextNode(dock)
        hose:Link(last, dock)
        hose:SetEndNode(dock)
        hose:SetDocked(true)
        hose:SetHolder(NULL)
        hose:SetLaidLen(math.floor(hose:LaidDistance()))
        if dst.SetPumpOn then dst:SetPumpOn(true) end
        if src.SetHosesOut then src:SetHosesOut(A.HoseCountOn(src)) end
        if dst.SetHosesOut then dst:SetHosesOut(A.HoseCountOn(dst)) end
        hose:EmitSound("buttons/lever7.wav", 65, 100)
        hook.Run("GRM_FireAddon_HoseDocked", hose, dst, nil)
        if hose.BroadcastPath then hose:BroadcastPath() end
        return hose
    end
end

if CLIENT then
    -- Пути с сервера: не зависим от того, доехали ли узлы до клиента.
    A.HosePaths = A.HosePaths or {}

    local COL = Color(205, 42, 28, 255)
    local COL_DARK = Color(90, 14, 10, 255)
    local COL_LIVE = Color(255, 95, 35, 255)

    local function handPos(ply)
        if not IsValid(ply) then return nil end
        local att = ply:LookupAttachment("anim_attachment_RH")
        local dat = att and att > 0 and ply:GetAttachment(att)
        return (dat and dat.Pos) or (ply:WorldSpaceCenter() + Vector(0, 0, 18))
    end

    local function nodeTip(ent)
        if not IsValid(ent) then return nil end
        if ent:IsPlayer() then return handPos(ent) end
        return ent:GetPos() + Vector(0, 0, 7)
    end

    local function sourceTip(src)
        if not IsValid(src) then return nil end
        return src:WorldSpaceCenter() + Vector(0, 0, 6)
    end

    local function dropGround(v)
        if not v then return nil end
        local tr = util.TraceLine({
            start = v + Vector(0, 0, 48),
            endpos = v - Vector(0, 0, 160),
            mask = MASK_SOLID_BRUSHONLY,
        })
        if tr.Hit then return tr.HitPos + Vector(0, 0, 3) end
        return Vector(v.x, v.y, v.z)
    end

    -- Катушка (живо) → земля у машины → колышки как есть → ноги → рука.
    -- Не спрямлять насос→рука по воздуху.
    local function livePts(rec)
        if not rec or not rec.pts then return nil end
        local pts = {}
        for i = 1, #rec.pts do pts[i] = rec.pts[i] end
        if #pts == 0 then return pts end
        local hose = rec.id and Entity(rec.id) or NULL
        local tip
        if IsValid(hose) and hose.GetSrcPos then
            local sp = hose:GetSrcPos()
            if sp and (not sp.LengthSqr or sp:LengthSqr() > 4) then tip = sp end
        end
        if not tip then
            local src = rec.src
            if not IsValid(src) and IsValid(hose) and hose.GetStartEnt then src = hose:GetStartEnt() end
            tip = sourceTip(src)
        end
        if tip then
            pts[1] = tip
            local g = dropGround(tip)
            if g and (not pts[2] or g:DistToSqr(pts[2]) > 36) then
                table.insert(pts, 2, g)
            end
        end
        if rec.docked then
            local tail
            if IsValid(hose) and hose.GetTailPos then
                local tp = hose:GetTailPos()
                if tp and (not tp.LengthSqr or tp:LengthSqr() > 4) then tail = tp end
            end
            if not tail then
                local en = rec.tail
                if not IsValid(en) and IsValid(hose) and hose.GetEndNode then en = hose:GetEndNode() end
                if IsValid(en) then
                    local p = en.GetParent and en:GetParent() or NULL
                    tail = (IsValid(p) and sourceTip(p)) or (en:GetPos() + Vector(0, 0, 6))
                end
            end
            if tail then pts[#pts] = tail end
        elseif IsValid(rec.holder) then
            local feet = dropGround(rec.holder:GetPos())
            if feet then pts[#pts + 1] = feet end
            pts[#pts + 1] = handPos(rec.holder)
        end
        return pts
    end

    -- Плоская лента по земле, не балка в воздухе.
    function A.DrawHoseBeam(a, b, live)
        if not a or not b then return end
        local dir = b - a
        local len = dir:Length()
        if len < 2 or len > 2600 then return end
        dir:Normalize()
        local col = live and COL_LIVE or COL
        render.DrawLine(a, b, col, false)
        render.SetColorMaterial()
        local ang = dir:Angle()
        local mid = (a + b) * 0.5
        local hw = A.HoseBeamHalfW or 1.35
        local hh = A.HoseBeamHalfH or 0.28
        render.DrawBox(mid, ang, Vector(-len * 0.5, -hw, -hh), Vector(len * 0.5, hw, hh), col, true)
        render.DrawLine(a + Vector(0, 0, 0.4), b + Vector(0, 0, 0.4), COL_DARK, false)
    end

    local function collectFromNodes()
        local byHose = {}
        for _, n in ipairs(ents.FindByClass("grm_fire_hose_node")) do
            if IsValid(n) and n.GetHose then
                local hose = n:GetHose()
                local id = IsValid(hose) and hose:EntIndex() or 0
                if id > 0 then
                    byHose[id] = byHose[id] or { hose = hose, segs = {} }
                    local nxt = n.GetNextNode and n:GetNextNode() or NULL
                    if IsValid(nxt) then
                        byHose[id].segs[#byHose[id].segs + 1] = { nodeTip(n), nodeTip(nxt), nxt:IsPlayer() }
                    end
                end
            end
        end
        return byHose
    end

    local function drawPath(id, rec)
        local pts = livePts(rec)
        if not pts then return end
        local holder = rec.holder
        for i = 2, #pts do
            A.DrawHoseBeam(pts[i - 1], pts[i], i == #pts and IsValid(holder) and not rec.docked)
        end
    end

    function A.DrawAllHoses()
        local drawn = {}
        for id, rec in pairs(A.HosePaths) do
            if rec.id and not IsValid(Entity(rec.id)) then
                A.HosePaths[id] = nil
            else
                drawPath(id, rec)
                drawn[id] = true
            end
        end
        local fromNodes = collectFromNodes()
        for id, pack in pairs(fromNodes) do
            if not drawn[id] then
                for _, seg in ipairs(pack.segs) do
                    A.DrawHoseBeam(seg[1], seg[2], seg[3])
                end
            end
        end
    end

    net.Receive("GRM_FireHose_Path", function()
        local id = net.ReadUInt(16)
        local n = net.ReadUInt(8)
        local pts = {}
        for i = 1, n do pts[i] = net.ReadVector() end
        local holder = net.ReadEntity()
        local docked = net.ReadBool()
        local src = net.ReadEntity()
        local tail = net.ReadEntity()
        if n == 0 then
            A.HosePaths[id] = nil
            return
        end
        A.HosePaths[id] = { id = id, pts = pts, holder = holder, docked = docked, src = src, tail = tail }
    end)

    local lastHoseDrawFrame = -1
    hook.Add("PostDrawTranslucentRenderables", "GRM_FireHose_Vis", function(_, sky)
        if sky then return end
        -- Source вызывает translucent render больше одного раза за кадр
        -- (мир/виды/эффекты). Рукав рисуется максимум один раз на FrameNumber.
        local frame = FrameNumber()
        if lastHoseDrawFrame == frame then return end
        lastHoseDrawFrame = frame
        A.DrawAllHoses()
    end)
end
