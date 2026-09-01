--[[--------------------------------------------------------------------
    Расстановка железа пожарных. SuperAdmin.
    Категория GRM — общая вкладка со всеми инструментами.
    ЛКМ — поставить / навесить насос или лестницу на машину /
          по существующей точке — записать вес/метку.
    ПКМ по точке очага — поджечь сейчас.
    R — удалить нашу сущность (ищет рядом, если луч не попал).
----------------------------------------------------------------------]]
TOOL.Category = "GRM"
TOOL.Name = "#tool.grm_fire_place.name"
TOOL.Command = nil
TOOL.ConfigName = ""
TOOL.ClientConVar = {
    type = "hydrant",
    weight = "1",
    label = "очаг",
    feed = "180",
}

if CLIENT then
    language.Add("tool.grm_fire_place.name", "GRM Пожарное железо")
    language.Add("tool.grm_fire_place.desc", "Гидрант, насос, шкаф, точка очага, лестница")
    language.Add("tool.grm_fire_place.0", "ЛКМ: поставить / настроить точку | ПКМ по точке: поджечь | R: удалить")
end

local TYPES = {
    hydrant = { class = "grm_fire_hydrant", label = "Гидрант" },
    pump    = { class = "grm_fire_pump",    label = "Насос (призрак, 4 рукава)" },
    cabinet = { class = "grm_fire_cabinet", label = "Шкаф огнетушителей" },
    spot    = { class = "grm_fire_spot",    label = "Точка очага" },
    ladder  = { class = "grm_fire_ladder",  label = "Пожарная лестница" },
}

local function can(ply)
    return IsValid(ply) and ply:IsSuperAdmin()
end

local function isCar(ent)
    if not IsValid(ent) then return false end
    if ent.IsVehicle and ent:IsVehicle() then return true end
    local cls = ent:GetClass() or ""
    return string.find(cls, "vehicle", 1, true) or string.StartWith(cls, "simfphys_")
        or string.StartWith(cls, "lvs_") or string.StartWith(cls, "glide_")
end

local function isFireClass(c)
    c = tostring(c or "")
    return string.sub(c, 1, 9) == "grm_fire_"
end

local function findFireTarget(trace)
    if not trace then return nil end
    if IsValid(trace.Entity) and isFireClass(trace.Entity:GetClass()) then
        return trace.Entity
    end
    local origin = trace.HitPos or (IsValid(trace.Entity) and trace.Entity:GetPos()) or nil
    if not origin then return nil end
    local best, bestD
    for _, e in ipairs(ents.FindInSphere(origin, 80)) do
        if IsValid(e) and isFireClass(e:GetClass()) then
            local d = e:GetPos():DistToSqr(origin)
            if not best or d < bestD then best, bestD = e, d end
        end
    end
    return best
end

local function applySpotCvars(ent, tool)
    if not IsValid(ent) or ent:GetClass() ~= "grm_fire_spot" then return end
    local w = math.Clamp(math.floor(tonumber(tool:GetClientInfo("weight")) or 1), 1, 99)
    local feed = math.Clamp(math.floor(tonumber(tool:GetClientInfo("feed")) or 180), 40, 800)
    local lab = string.Trim(tostring(tool:GetClientInfo("label") or "очаг"))
    if lab == "" then lab = "очаг" end
    if #lab > 32 then lab = string.sub(lab, 1, 32) end
    if ent.SetWeight then ent:SetWeight(w) end
    if ent.SetFeed then ent:SetFeed(feed) end
    if ent.SetSpotLabel then ent:SetSpotLabel(lab) end
    if ent.SetSpotOn then ent:SetSpotOn(true) end
end

function TOOL:LeftClick(trace)
    if CLIENT then return true end
    local ply = self:GetOwner()
    if not can(ply) or not trace or not trace.Hit then return false end
    local t = TYPES[self:GetClientInfo("type") or "hydrant"] or TYPES.hydrant

    local hit = findFireTarget(trace)
    if IsValid(hit) and hit:GetClass() == "grm_fire_spot" and t.class == "grm_fire_spot" then
        applySpotCvars(hit, self)
        if GRM.PermData and GRM.PermData.UpdateEntry then pcall(GRM.PermData.UpdateEntry, hit) end
        if ply.ChatPrint then ply:ChatPrint("[Пожар] Точка обновлена: " .. tostring(hit:GetSpotLabel()) .. " ×" .. tostring(hit:GetWeight())) end
        return true
    end

    if t.class == "grm_fire_pump" and isCar(trace.Entity) then
        local pump = ents.Create("grm_fire_pump")
        if not IsValid(pump) then return false end
        pump:SetPos(trace.HitPos + trace.HitNormal * 8)
        pump:Spawn()
        pump:Activate()
        pump:AttachToVehicle(trace.Entity, Vector(0, -46, 16), Angle(0, 90, 0))
        hook.Run("GRM_FireAddon_Placed", pump, ply)
        if ply.ChatPrint then ply:ChatPrint("[Пожар] Насос-призрак на борту. 4 рукава. Без коллизии.") end
        return true
    end

    if t.class == "grm_fire_ladder" and isCar(trace.Entity) then
        local lad = ents.Create("grm_fire_ladder")
        if not IsValid(lad) then return false end
        lad:SetPos(trace.HitPos + trace.HitNormal * 8)
        lad:Spawn()
        lad:Activate()
        lad:AttachToVehicle(trace.Entity, Vector(0, 50, 12), Angle(0, 0, 0))
        hook.Run("GRM_FireAddon_Placed", lad, ply)
        if ply.ChatPrint then ply:ChatPrint("[Пожар] Лестница на борту. E — выдвинуть.") end
        return true
    end

    local ent = ents.Create(t.class)
    if not IsValid(ent) then return false end
    ent:SetPos(trace.HitPos + trace.HitNormal * 4)
    ent:SetAngles(Angle(0, ply:EyeAngles().y, 0))
    ent:Spawn()
    ent:Activate()
    if t.class == "grm_fire_spot" then applySpotCvars(ent, self) end
    hook.Run("GRM_FireAddon_Placed", ent, ply)
    if ply.ChatPrint then ply:ChatPrint("[Пожар] Поставлено: " .. t.label) end
    return true
end

function TOOL:RightClick(trace)
    if CLIENT then return true end
    local ply = self:GetOwner()
    if not can(ply) or not trace then return false end
    local ent = findFireTarget(trace)
    if IsValid(ent) and ent:GetClass() == "grm_fire_spot" then
        if not ent.IgniteSpot then return false end
        local fire, err = ent:IgniteSpot(ent.GetFeed and ent:GetFeed() or 180, ply:SteamID64())
        if IsValid(fire) then
            if ply.ChatPrint then ply:ChatPrint("[Пожар] Точка «" .. tostring(ent:GetSpotLabel()) .. "» подожжена.") end
            return true
        end
        if ply.ChatPrint then ply:ChatPrint("[Пожар] Не поджечь: " .. tostring(err or "нет vFire")) end
        return false
    end
    if ply.ChatPrint then ply:ChatPrint("[Пожар] ПКМ — по точке очага (видна, когда этот тул в руках).") end
    return false
end

function TOOL:Reload(trace)
    if CLIENT then return true end
    local ply = self:GetOwner()
    if not can(ply) then return false end
    local ent = findFireTarget(trace)
    if not IsValid(ent) then
        if ply.ChatPrint then ply:ChatPrint("[Пожар] В прицеле нет пожарного железа.") end
        return false
    end
    local c = ent:GetClass()
    if c == "grm_fire_hydrant" or c == "grm_fire_pump" or c == "grm_fire_cabinet" or c == "grm_fire_spot"
        or c == "grm_fire_hose" or c == "grm_fire_hose_node" or c == "grm_fire_ladder" then
        if GRM.Perm and GRM.Perm.Remove then pcall(GRM.Perm.Remove, ply, ent, false) end
        ent:Remove()
        if ply.ChatPrint then ply:ChatPrint("[Пожар] Удалено: " .. c) end
        return true
    end
    return false
end

if CLIENT then
    function TOOL:DrawHUD()
        local n = 0
        for _, e in ipairs(ents.FindByClass("grm_fire_spot")) do
            if IsValid(e) then n = n + 1 end
        end
        local y = ScrH() - 110
        draw.SimpleText("Пожарное железо  ·  точек очага: " .. n, "DermaDefaultBold", 18, y, Color(255, 170, 70))
        draw.SimpleText("ЛКМ — поставить / обновить точку   ПКМ по точке — поджечь   R — удалить", "DermaDefault", 18, y + 16, Color(220, 220, 225))
        draw.SimpleText("Точки видны только с этим тулом. Таймеры: /fire_spots", "DermaDefault", 18, y + 32, Color(180, 185, 195))
    end

    function TOOL.BuildCPanel(panel)
        panel:AddControl("Header", { Description = "Железо пожарных. Точки очага видны, пока этот тул в руках." })
        local t = panel:ComboBox("Тип", "grm_fire_place_type")
        t:AddChoice("Гидрант (2 порта)", "hydrant")
        t:AddChoice("Насос машины (призрак, 4 рукава)", "pump")
        t:AddChoice("Шкаф огнетушителей", "cabinet")
        t:AddChoice("Точка очага", "spot")
        t:AddChoice("Пожарная лестница", "ladder")
        panel:NumSlider("Вес точки (шанс)", "grm_fire_place_weight", 1, 20, 0)
        panel:TextEntry("Метка очага", "grm_fire_place_label")
        panel:NumSlider("Сила воспламенения", "grm_fire_place_feed", 40, 400, 0)
        panel:Help(
            "ТОЧКА ОЧАГА:\n" ..
            "ЛКМ по земле — поставить. ЛКМ по точке — записать вес/метку.\n" ..
            "ПКМ по точке — поджечь сейчас.\n" ..
            "R — удалить (ищет рядом, даже если луч скользнул).\n" ..
            "Маркер виден только суперадмину с этим тулом в руках.\n" ..
            "Таймеры рандома: чат /fire_spots\n\n" ..
            "ЛКМ по полу — поставить железо.\n" ..
            "ЛКМ по машине (насос/лестница) — навесить сбоку.\n" ..
            "НАСОС: после /firetruck клавиша G — баки."
        )
    end
end
