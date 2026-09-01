TOOL.Category = "GRM"
TOOL.Name = "#tool.grm_minimap.name"
TOOL.Command = nil
TOOL.ConfigName = ""

if CLIENT then
    language.Add("tool.grm_minimap.name", "GRM Районы и точки карты")
    language.Add("tool.grm_minimap.desc", "Размещение GPS-точек, районов и точек захвата")
    language.Add("tool.grm_minimap.0", "ЛКМ: установить GPS-точку | R: открыть настройки GPS")
end

function TOOL:LeftClick(trace)
    if CLIENT then return true end
    if not IsValid(self:GetOwner()) or not self:GetOwner():IsSuperAdmin() then return false end
    if GRM.Minimap and GRM.Minimap.AddPoint then
        GRM.Minimap.AddPoint(self:GetOwner(), "Точка захвата", trace.HitPos, 180)
        self:GetOwner():ChatPrint("[Мини-карта] Точка захвата установлена. Откройте /grm_minimap_admin для настройки.")
        return true
    end
    return false
end

function TOOL:RightClick()
    -- Территории и захваты отключены. Инструмент работает только как
    -- размещатель обычных GPS-точек по ЛКМ.
    return false
end

function TOOL:Reload(trace)
    if CLIENT then return true end
    if IsValid(self:GetOwner()) and self:GetOwner():IsSuperAdmin() then
        self:GetOwner():ConCommand("grm_minimap_admin")
        return true
    end
    return false
end
