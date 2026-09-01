--[[--------------------------------------------------------------------
    GRM Industry Tool — установка узлов цеха и логистики.

    ОДИН ИНСТРУМЕНТ НА СЕМЬ РОЛЕЙ. В старой сборке узлы цеха
    ставились из пет-меню, а узлы логистики — из спавн-меню, и у
    каждого был свой путь настройки. Теперь роль выбирается в одном
    списке, тип станка — вторым.
----------------------------------------------------------------------]]

TOOL.Category = "GRM"
TOOL.Name = "#tool.grm_industry.name"
TOOL.Command = nil
TOOL.ConfigName = ""

TOOL.ClientConVar = {
    role      = "station",
    kind      = "components",
    label     = "",
    faction   = "",
    make_perm = "1",
}

if CLIENT then
    language.Add("tool.grm_industry.name", "GRM Производство и логистика")
    language.Add("tool.grm_industry.desc", "Установка станков, складов, точек сбыта и логистики")
    language.Add("tool.grm_industry.0", "ЛКМ: установить узел | ПКМ: настроить узел | R: удалить")

    local ROLE_LABELS = {
        supply    = "Источник сырья (металлолом)",
        station   = "Производственный станок",
        storage   = "Склад цеха",
        market    = "Точка сбыта",
        depot     = "Точка отправления (логистика)",
        warehouse = "Склад фракции (логистика)",
        armory    = "Оружейный шкаф фракции",
    }
    local STATION_LABELS = {
        components = "Комплектующие",
        gpu        = "Видеокарты",
        weapon     = "Оружие",
        furnace    = "Печь переплавки брака",
    }

    function TOOL.BuildCPanel(panel)
        panel:AddControl("Header", { Description = "Узлы цеха и логистики. Роль задаётся один раз, тип станка можно менять потом." })
        local role = panel:AddControl("ComboBox", { Label = "Роль узла", Options = {} })
        for id, label in pairs(ROLE_LABELS) do
            role:AddChoice(label, id, false)
        end
        local kind = panel:AddControl("ComboBox", { Label = "Тип станка", Options = {} })
        for id, label in pairs(STATION_LABELS) do
            kind:AddChoice(label, id, false)
        end
        panel:AddControl("TextBox", { Label = "Название узла", Command = "grm_industry_label" })
        panel:AddControl("TextBox", { Label = "Фракция (оставьте пустым для всех)", Command = "grm_industry_faction" })
        panel:AddControl("CheckBox", { Label = "Сохранить на карту (perm)", Command = "grm_industry_make_perm" })
        panel:AddControl("Label", { Text = "ПКМ по станку — сменить тип (опустошив вход и выход)." })
    end

    -- Предпросмотр роли в подсказке инструмента.
    function TOOL:DrawHUD()
        draw.SimpleText("Узел: " .. (ROLE_LABELS[self:GetClientInfo("role")] or "?"),
            "DermaDefaultBold", ScrW() / 2, ScrH() - 120, Color(235, 178, 60), TEXT_ALIGN_CENTER)
    end
end

local CLASSES = {
    supply    = "grm_ind_supply",
    station   = "grm_ind_station",
    storage   = "grm_ind_storage",
    market    = "grm_ind_market",
    depot     = "grm_ind_depot",
    warehouse = "grm_ind_warehouse",
    armory    = "grm_ind_armory",
}

local function canUse(ply)
    if not IsValid(ply) then return false end
    if ply:IsSuperAdmin() then return true end
    local fac = ply:GetNWString("GRM_Faction", "")
    if fac ~= "" and _G.FactionsAPI and _G.FactionsAPI.IsLeader and _G.FactionsAPI.IsLeader(ply, fac) then
        return true
    end
    return false
end

function TOOL:LeftClick(trace)
    if CLIENT then return true end
    local ply = self:GetOwner()
    if not IsValid(ply) then return false end
    if not canUse(ply) then
        if GRM.Notify then GRM.Notify(ply, "Узлы производства ставят администраторы и лидеры фракций.", 255, 120, 100) end
        return false
    end
    if not (trace and trace.Hit) then return false end

    local role = self:GetClientInfo("role") or "station"
    local class = CLASSES[role]
    if not class then return false end

    local ent = ents.Create(class)
    if not IsValid(ent) then return false end
    ent:SetPos(trace.HitPos + trace.HitNormal * 6)
    ent:SetAngles(Angle(0, ply:EyeAngles().y + 180, 0))
    ent:Spawn()
    ent:Activate()

    local kind = self:GetClientInfo("kind") or "components"
    if role == "station" and GRM.Industry and GRM.Industry.Stations then
        if not GRM.Industry.Stations[kind] then kind = "components" end
        ent:SetNodeKind(kind)
    end

    local label = self:GetClientInfo("label")
    if isstring(label) and label ~= "" then ent:SetNodeLabel(label) end
    local faction = self:GetClientInfo("faction")
    if isstring(faction) and faction ~= "" then ent:SetFactionName(faction) end

    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then phys:EnableMotion(false) phys:Wake() end
    if GRM.PropProtect and GRM.PropProtect.MarkServerEntity then GRM.PropProtect.MarkServerEntity(ent) end

    local makePerm = self:GetClientInfo("make_perm") ~= "0"
    if makePerm and GRM.Perm and GRM.Perm.Add then pcall(GRM.Perm.Add, ply, ent) end

    if GRM.Notify then
        GRM.Notify(ply, "Узел установлен" .. (makePerm and " (сохранён на карту)" or ""), 100, 220, 130)
    end
    return true
end

function TOOL:RightClick(trace)
    if CLIENT then return true end
    local ply = self:GetOwner()
    if not IsValid(ply) or not trace or not IsValid(trace.Entity) then return false end
    local ent = trace.Entity
    local cls = ent:GetClass()
    if cls ~= "grm_ind_station" then return false end

    if not canUse(ply) then
        if GRM.Notify then GRM.Notify(ply, "Настраивать станок могут администраторы и лидеры.", 255, 120, 100) end
        return false
    end

    local rec = GRM.Industry and GRM.Industry.NodeFor and GRM.Industry.NodeFor(ent)
    if rec and rec.job and GRM.Industry.Jobs and GRM.Industry.Jobs[rec.job] then
        if GRM.Notify then GRM.Notify(ply, "Сначала остановите работу на станке.", 255, 120, 100) end
        return false
    end

    local kind = self:GetClientInfo("kind") or "components"
    if GRM.Industry and GRM.Industry.Stations and not GRM.Industry.Stations[kind] then kind = "components" end
    if rec and GRM.Container then
        if not GRM.Container.IsEmpty(rec.inID) or not GRM.Container.IsEmpty(rec.outID) then
            if GRM.Notify then GRM.Notify(ply, "Сначала освободите вход и выход станка.", 255, 120, 100) end
            return false
        end
    end

    ent:SetNodeKind(kind)
    if rec then rec.kind = kind end
    local model = GRM.Industry and GRM.Industry.Stations and GRM.Industry.Stations[kind] and GRM.Industry.Stations[kind].model
    if model then ent:SetModel(model) end
    if GRM.Notify then GRM.Notify(ply, "Тип станка: " .. tostring((GRM.Industry.Stations[kind] or {}).name or kind), 100, 220, 130) end
    return true
end

function TOOL:Reload(trace)
    if CLIENT then return true end
    local ply = self:GetOwner()
    if not IsValid(ply) or not canUse(ply) then return false end
    if not (trace and IsValid(trace.Entity)) then return false end
    local ent = trace.Entity
    if not CLASSES[ent.NodeRole or ""] and not string.find(ent:GetClass() or "", "^grm_ind_") then return false end
    if GRM.Perm and GRM.Perm.Remove then pcall(GRM.Perm.Remove, ply, ent) end
    ent:Remove()
    if GRM.Notify then GRM.Notify(ply, "Узел удалён", 100, 220, 130) end
    return true
end
