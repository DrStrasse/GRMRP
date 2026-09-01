TOOL.Category = "GRM"
TOOL.Name = "#tool.grm_property.name"
TOOL.Command = nil
TOOL.ConfigName = ""

if CLIENT then
    language.Add("tool.grm_property.name", "GRM Недвижимость")
    language.Add("tool.grm_property.desc", "Выбор дверей для помещения/здания")
    language.Add("tool.grm_property.0", "ЛКМ: добавить/убрать дверь • ПКМ: открыть управление • R: очистить выбор")
end

local function resolve(tr)
    local ent = tr and tr.Entity
    if GRM.Property and GRM.Property.ResolveDoor then
        return GRM.Property.ResolveDoor(ent)
    end
    return IsValid(ent) and ent or nil
end

function TOOL:LeftClick(tr)
    if CLIENT then return true end
    local p = self:GetOwner()
    if not (GRM.Property and GRM.Property.CanAdmin and GRM.Property.CanAdmin(p)) then return false end
    local door = resolve(tr)
    if not IsValid(door) then
        p:ChatPrint("[Недвижимость] Смотрите на дверь (func_door / вращающуюся / раздвижную).")
        return false
    end
    local ok, on, id = GRM.Property.ToggleDoorSelection(p, door)
    if ok then
        p:ChatPrint("[Недвижимость] " .. (on and "Добавлена дверь: " or "Убрана дверь: ") .. tostring(id))
    else
        p:ChatPrint("[Недвижимость] Эту дверь нельзя отметить.")
    end
    return ok == true
end

function TOOL:RightClick()
    if CLIENT then return true end
    local p = self:GetOwner()
    if GRM.Property and GRM.Property.CanAdmin and GRM.Property.CanAdmin(p) and GRM.Property.OpenAdmin then
        GRM.Property.OpenAdmin(p)
        return true
    end
    return false
end

function TOOL:Reload()
    if CLIENT then return true end
    local p = self:GetOwner()
    if GRM.Property and GRM.Property.CanAdmin and GRM.Property.CanAdmin(p) then
        GRM.Property.Selections = GRM.Property.Selections or {}
        GRM.Property.Selections[p] = {}
        if SERVER then
            net.Start("GRM_Property_Sel") net.WriteUInt(0, 8) net.Send(p)
        end
        p:ChatPrint("[Недвижимость] Выбор дверей очищен.")
        return true
    end
    return false
end

function TOOL.BuildCPanel(panel)
    if not IsValid(panel) then return end
    panel:Help("1. Наведите на дверь — она подсветится голубым.")
    panel:Help("2. ЛКМ отмечает дверь зелёным.")
    panel:Help("3. ПКМ открывает меню. «Создать из отмеченных дверей».")
    panel:Button("Открыть управление", "grm_property_admin")
end
