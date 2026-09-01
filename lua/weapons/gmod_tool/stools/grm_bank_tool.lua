--[[--------------------------------------------------------------------
    GRM Bank Tool (находка 178)
    Установка банковского оборудования:
      • Хранилище (grm_bank_vault) — ground_locker_small.mdl, отражает
        гос.бюджет, вмещает 500.000 GRM паллетами;
      • Печатный станок (grm_money_press) — hatch_frame.mdl, печатает
        5000 GRM / 10 сек в гос.бюджет, паллеты дропает в хранилище;
      • Терминал станка (grm_money_press_terminal) — holo_wall_unit.mdl,
        запуск/остановка, прокачка скорости, охлаждение.
    Права: суперадмин или доступ к экономике (CanManageEconomy).
----------------------------------------------------------------------]]
TOOL.Category = "GRM"
TOOL.Name = "#tool.grm_bank_tool.name"
TOOL.Command = nil
TOOL.ConfigName = ""

TOOL.ClientConVar = {
    type = "vault",
}

-- Находка 178d: выбранный станок для установки точки выдачи (сервер)
TOOL.PressEnt = nil
-- Находка 179f: выбранный отмывщик для установки цели ивента (сервер)
TOOL.LaundererEnt = nil

if CLIENT then
    language.Add("tool.grm_bank_tool.name", "GRM Банковское оборудование")
    language.Add("tool.grm_bank_tool.desc", "Хранилище, печатный станок и терминал банка")
    language.Add("tool.grm_bank_tool.0", "ЛКМ: установить выбранное оборудование | Права: суперадмин или доступ к экономике")
end

local TYPES = {
    vault       = { id = "vault",       class = "grm_bank_vault",           label = "Хранилище" },
    computer    = { id = "computer",    class = "grm_bank_computer",        label = "Компьютер Управления (Банк)" },
    press       = { id = "press",       class = "grm_money_press",          label = "Печатный станок" },
    terminal    = { id = "terminal",    class = "grm_money_press_terminal", label = "Терминал станка" },
    spawnpoint  = { id = "spawnpoint",  class = "grm_money_press",          label = "Точка выдачи паллет" },
    launderer   = { id = "launderer",   class = "grm_money_launderer",      label = "Отмывщик денег (ивент)" },
    heisttarget = { id = "heisttarget", class = "grm_money_launderer",      label = "Цель ивента (Рейхсбанк)" },
}

local function canUse(ply)
    if not IsValid(ply) then return false end
    if ply:IsSuperAdmin() then return true end
    return GRM.Economy and GRM.Economy.CanManageEconomy and GRM.Economy.CanManageEconomy(ply) == true
end

function TOOL:LeftClick(trace)
    if CLIENT then return true end
    local ply = self:GetOwner()
    if not IsValid(ply) then return false end
    if not canUse(ply) then
        if GRM.Notify then GRM.Notify(ply, "Нет доступа: нужно право управления экономикой (суперадмин или выдано фракции).", 255, 120, 100) end
        return false
    end
    if not (trace and trace.Hit) then return false end

    local t = TYPES[self:GetClientInfo("type") or "vault"] or TYPES.vault

    -- Находка 179f: режим «Цель ивента» — ЛКМ по отмывщику выбирает его,
    -- ЛКМ по хранилищу/месту ставит цель (только суперадмин).
    if t.id == "heisttarget" then
        local hit = trace.Entity
        if IsValid(hit) and hit:GetClass() == "grm_money_launderer" then
            if not ply:IsSuperAdmin() then
                if GRM.Notify then GRM.Notify(ply, "Цель ивента может ставить только суперадмин.", 255, 120, 100) end
                return false
            end
            self.LaundererEnt = hit
            if GRM.Notify then GRM.Notify(ply, "Отмывщик выбран. Наведите на хранилище (Рейхсбанк) и нажмите ЛКМ — цель ивента.", 120, 220, 255) end
            return true
        end
        if IsValid(self.LaundererEnt) then
            if not ply:IsSuperAdmin() then
                if GRM.Notify then GRM.Notify(ply, "Цель ивента может ставить только суперадмин.", 255, 120, 100) end
                return false
            end
            self.LaundererEnt:SetHeistTarget(trace.HitPos)
            if GRM.Notify then GRM.Notify(ply, "Цель ивента установлена: паллеты/Рейхсбанк здесь. Грабители получат GPS-маркер.", 100, 220, 130) end
            self.LaundererEnt = nil
            return true
        end
        if GRM.Notify then GRM.Notify(ply, "Сначала выберите отмывщика (ЛКМ по grm_money_launderer).", 255, 180, 90) end
        return false
    end

    -- Находка 178d: режим «Точка выдачи» — ЛКМ по станку выбирает его,
    -- ЛКМ по месту устанавливает точку (только суперадмин).
    if t.id == "spawnpoint" then
        local hit = trace.Entity
        if IsValid(hit) and hit:GetClass() == "grm_money_press" then
            if not ply:IsSuperAdmin() then
                if GRM.Notify then GRM.Notify(ply, "Точку выдачи может ставить только суперадмин.", 255, 120, 100) end
                return false
            end
            self.PressEnt = hit
            if GRM.Notify then GRM.Notify(ply, "Станок выбран. Наведите на место и нажмите ЛКМ — точка выдачи паллет.", 120, 220, 255) end
            return true
        end
        if IsValid(self.PressEnt) then
            if not ply:IsSuperAdmin() then
                if GRM.Notify then GRM.Notify(ply, "Точку выдачи может ставить только суперадмин.", 255, 120, 100) end
                return false
            end
            local ang = Angle(0, IsValid(ply) and ply:EyeAngles().y or 0, 0)
            self.PressEnt:SetSpawnPoint(trace.HitPos + trace.HitNormal * 4, ang)
            if GRM.Notify then GRM.Notify(ply, "Точка выдачи установлена: паллеты будут спавниться здесь.", 100, 220, 130) end
            self.PressEnt = nil
            return true
        end
        if GRM.Notify then GRM.Notify(ply, "Сначала выберите станок (ЛКМ по grm_money_press).", 255, 180, 90) end
        return false
    end

    -- Находка 179k: отмывщик — НЕ проп, ставим ПРЯМО на поверхность
    -- (как торгаш: tr.HitPos + tr.HitNormal), иначе BBOX-модель висит в воздухе
    local ent = ents.Create(t.class)
    if not IsValid(ent) then return false end
    if t.class == "grm_money_launderer" then
        ent:SetPos(trace.HitPos + trace.HitNormal)
        ent:SetAngles(Angle(0, IsValid(ply) and ply:EyeAngles().y or 0, 0))
    else
        ent:SetPos(trace.HitPos + trace.HitNormal * 12)
        ent:SetAngles(Angle(0, IsValid(ply) and ply:EyeAngles().y or 0, 0))
    end
    ent:Spawn()
    ent:Activate()
    if GRM.PropProtect and GRM.PropProtect.MarkServerEntity then GRM.PropProtect.MarkServerEntity(ent) end
    if t.class == "grm_money_press" and ent.SetPressOwner then ent:SetPressOwner(ply) end
    if GRM.Notify then
        GRM.Notify(ply, "Установлено: " .. t.label .. ". Сохраните /permadd (наведите прицел, /permadd).", 100, 220, 130)
    end
    return true
end

function TOOL:RightClick(trace)
    -- Находка 179j: ПКМ по банковскому оборудованию = открыть его меню (как E)
    if CLIENT then return true end
    local ply = self:GetOwner()
    if not IsValid(ply) or not trace or not IsValid(trace.Entity) then return false end
    local ent = trace.Entity
    local cls = ent:GetClass()
    if cls ~= "grm_bank_vault" and cls ~= "grm_bank_computer" and cls ~= "grm_money_press" and cls ~= "grm_money_press_terminal" and cls ~= "grm_money_launderer" then
        return false
    end
    -- как E: сам Use внутри проверяет права (загрузка/выгрузка/настройка)
    if ent.Use then ent:Use(ply) end
    return true
end

function TOOL:Reload(trace)
    if CLIENT then return true end
    local ply = self:GetOwner()
    if not IsValid(ply) or not IsValid(trace.Entity) then return false end
    local ent = trace.Entity
    local cls = ent:GetClass()
    -- Находка 178d: R по станку в режиме «Точка выдачи» — сброс точки
    local t = TYPES[self:GetClientInfo("type") or "vault"] or TYPES.vault
    if t.id == "heisttarget" and cls == "grm_money_launderer" then
        if not ply:IsSuperAdmin() then
            if GRM.Notify then GRM.Notify(ply, "Цель ивента может ставить только суперадмин.", 255, 120, 100) end
            return false
        end
        ent:SetHeistTarget(Vector(0, 0, 0))
        if GRM.Notify then GRM.Notify(ply, "Цель ивента сброшена (авто: ближайшее хранилище).", 100, 220, 255) end
        return true
    end
    -- Находка 179g: R по отмывщику в ЛЮБОМ режиме — УДАЛИТЬ (суперадмин)
    if cls == "grm_money_launderer" and t.id ~= "heisttarget" then
        if not ply:IsSuperAdmin() then
            if GRM.Notify then GRM.Notify(ply, "Удаление отмывщика — только суперадмин.", 255, 120, 100) end
            return false
        end
        ent:Remove()
        if GRM.Notify then GRM.Notify(ply, "Отмывщик удалён.", 100, 220, 130) end
        return true
    end
    if t.id == "spawnpoint" and cls == "grm_money_press" then
        if not ply:IsSuperAdmin() then
            if GRM.Notify then GRM.Notify(ply, "Точку выдачи может ставить только суперадмин.", 255, 120, 100) end
            return false
        end
        ent:ClearSpawnPoint()
        if GRM.Notify then GRM.Notify(ply, "Точка выдачи сброшена (паллеты снова у станка).", 100, 220, 130) end
        return true
    end
    if cls ~= "grm_bank_vault" and cls ~= "grm_bank_computer" and cls ~= "grm_money_press" and cls ~= "grm_money_press_terminal" and cls ~= "grm_money_launderer" then
        if GRM.Notify then GRM.Notify(ply, "Наведите на банковское оборудование.", 255, 180, 90) end
        return false
    end
    if not canUse(ply) then
        if GRM.Notify then GRM.Notify(ply, "Нет доступа.", 255, 120, 100) end
        return false
    end
    ent:Remove()
    if GRM.Notify then GRM.Notify(ply, "Оборудование удалено.", 100, 220, 130) end
    return true
end

if CLIENT then
    function TOOL.BuildCPanel(panel)
        panel:AddControl("Header", { Description = "Банковское оборудование: хранилище, Компьютер Управления, печатный станок (5000 GRM/10 сек) и терминал станка." })

        local t = panel:ComboBox("Тип", "grm_bank_tool_type")
        t:AddChoice("Хранилище (гос.бюджет)", "vault")
        t:AddChoice("Компьютер Управления (Банк)", "computer")
        t:AddChoice("Печатный станок (5000/10с)", "press")
        t:AddChoice("Терминал станка", "terminal")
        t:AddChoice("Точка выдачи паллет (суперадмин)", "spawnpoint")
        t:AddChoice("Отмывщик денег (ивент ограбление)", "launderer")
        t:AddChoice("Цель ивента — Рейхсбанк (суперадмин)", "heisttarget")

        panel:Help(
            "ЛКМ — установить выбранное оборудование\n" ..
            "ПКМ по оборудованию — открыть меню (хранилище/компьютер/станок)\n" ..
            "R по оборудованию — удалить (суперадмин / доступ к экономике)\n\n" ..
            "КОМПЬЮТЕР УПРАВЛЕНИЯ (Банк):\n" ..
            "• Связывает хранилище, печатный станок и госбюджет.\n" ..
            "• Зачисление наличных хранилища в госбюджет / субсидии фракциям.\n\n" ..
            "ТОЧКА ВЫДАЧИ ПАЛЛЕТ (суперадмин):\n" ..
            "1. В комбо выберите «Точка выдачи паллет».\n" ..
            "2. ЛКМ по печатному станку — выбрать его.\n" ..
            "3. ЛКМ по месту (полу/площадке) — паллеты будут спавниться ТАМ.\n" ..
            "4. R по станку — сбросить точку.\n\n" ..
            "СХЕМА РАБОТЫ:\n" ..
            "1. Ставите ХРАНИЛИЩЕ и КОМПЬЮТЕР УПРАВЛЕНИЯ рядом.\n" ..
            "2. Ставите ПЕЧАТНЫЙ СТАНОК — каждые 10 сек печатает 5000 GRM в буфер, спавнит паллеты.\n" ..
            "3. Паллету подносите к хранилищу, E → «Загрузить».\n" ..
            "4. Управляющий через КОМПЬЮТЕР УПРАВЛЕНИЯ распределяет средства в казну или фракциям."
        )
    end
end
