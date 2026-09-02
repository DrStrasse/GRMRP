TOOL.Category = "GRM"
TOOL.Name = "#tool.grm_lab_tool.name"
TOOL.Command = nil
TOOL.ConfigName = ""

TOOL.ClientConVar = {
    type = "narc",
}

local LAB_TYPES = {
    narc = {
        name = "Лаборатория наркотиков",
        class = "grm_narc_lab",
        model = "models/props_wasteland/laundry_washer003.mdl",
    },
    med = {
        name = "Медицинская лаборатория",
        class = "grm_med_lab",
        model = "models/props_wasteland/laundry_washer003.mdl",
    },
}

if CLIENT then
    language.Add("tool.grm_lab_tool.name", "GRM Лаборатория")
    language.Add("tool.grm_lab_tool.desc", "Спавн лабораторий: наркотиков / медицины")
    language.Add("tool.grm_lab_tool.0", "ЛКМ: Поставить лабораторию. R: Удалить. Z: Отмена")
end

function TOOL:LeftClick(tr)
    if not tr.Hit then return false end
    if CLIENT then return true end

    local ply = self:GetOwner()
    if not IsValid(ply) or not ply:IsSuperAdmin() then
        GRM.Notify(ply, "Только суперадмин!", 255, 100, 100)
        return false
    end

    local labType = self:GetClientInfo("type")
    if not LAB_TYPES[labType] then
        GRM.Notify(ply, "Неизвестный тип лаборатории: " .. tostring(labType), 255, 100, 100)
        return false
    end

    local labInfo = LAB_TYPES[labType]
    local ent = ents.Create(labInfo.class)
    if not IsValid(ent) then return false end

    -- Позиционируем НАД землёй (учитываем размер пропа)
    local mins, maxs = ent:OBBMins(), ent:OBBMaxs()
    local height = maxs.z - mins.z
    ent:SetPos(tr.HitPos + Vector(0, 0, height / 2))
    ent:SetAngles(Angle(0, ply:EyeAngles().y + 180, 0))
    ent.LabType = labType -- ВАЖНО: передаём тип на сервер
    ent:Spawn()
    ent:Activate()

    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(false)
        phys:Sleep()
    end

    undo.Create("GRM_Lab")
        undo.AddEntity(ent)
        undo.SetPlayer(ply)
    undo.Finish()

    ply:ChatPrint("[Лаборатория] Поставлен: " .. labInfo.name)
    return true
end

function TOOL:RightClick(tr)
    if CLIENT then return true end

    local ply = self:GetOwner()
    if not IsValid(ply) or not ply:IsSuperAdmin() then return false end

    local ent = tr.Entity
    if not IsValid(ent) then return false end

    if ent:GetClass() == "grm_narc_lab" or ent:GetClass() == "grm_med_lab" then
        ent:Remove()
        ply:ChatPrint("[Лаборатория] Удалён")
        return true
    end

    return false
end

--- R — то же удаление, что и ПКМ: раньше тело было продублировано
--- байт-в-байт (волна дедупа 1, 02.09.2026). Поведение по описанию
--- инструмента: «R — удалить лабораторию».
TOOL.Reload = TOOL.RightClick

function TOOL.BuildCPanel(CPanel)
    CPanel:AddControl("Header", {
        Description = "Спавн лабораторий: наркотиков и медицинских"
    })

    CPanel:AddControl("ComboBox", {
        Label = "Тип лаборатории",
        Options = {
            ["Лаборатория наркотиков"] = { type = "narc" },
            ["Медицинская лаборатория"] = { type = "med" },
        }
    })

    CPanel:Help("ЛКМ — поставить лабораторию\nR — удалить лабораторию\nZ — отмена последнего")
end
