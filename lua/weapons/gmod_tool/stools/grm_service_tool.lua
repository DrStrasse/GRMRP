--[[--------------------------------------------------------------------
    GRM Service Tool — Служебное оборудование ведомств
    Установка и настройка специализированных служебных компьютеров:
      • Компьютер Полиции Порядка (OrdnungPolizei) — grm_comp_police
      • Компьютер Полевой Жандармерии (Feldgendarmerie) — grm_comp_military_police
      • Компьютер Спецслужб (Gestapo / Komitet) — grm_comp_security
      • Компьютер Военного Комиссариата (Военкомат / Призыв) — grm_comp_military
      • Экзаменационный ПК Автоинспекции (Автошкола / ВАИ / Дорожная Инспекция ПП) — grm_comp_traffic
      • Медицинский Компьютер Госпиталя (Медицинская служба / ВВК) — grm_comp_medical
      • Компьютер учреждения образования (деканат, дипломы) — grm_comp_education
      • Универсальный служебный терминал — grm_doc_computer
----------------------------------------------------------------------]]
TOOL.Category = "GRM"
TOOL.Name = "#tool.grm_service_tool.name"
TOOL.Command = nil
TOOL.ConfigName = ""

TOOL.ClientConVar = {
    type      = "police",
    model     = "models/props/cs_office/computer.mdl",
    title     = "",
    make_perm = "1",
    factions  = "",
}

if CLIENT then
    language.Add("tool.grm_service_tool.name", "GRM Служебное оборудование")
    language.Add("tool.grm_service_tool.desc", "Установка специализированных служебных компьютеров ведомств")
    language.Add("tool.grm_service_tool.0", "ЛКМ: установить компьютер | ПКМ: открыть меню компьютера | R: удалить")
end

local TYPES = {
    police = {
        id        = "police",
        class     = "grm_comp_police",
        label     = "Компьютер Полиции Порядка (OrdnungPolizei)",
        desc      = "Розыск, база штрафов, паспорта, удостоверения OrdnungPolizei",
        defTitle  = "ПОЛИЦИЯ ПОРЯДКА (OrdnungPolizei)",
        defModel  = "models/props/cs_office/computer.mdl",
    },
    military_police = {
        id        = "military_police",
        class     = "grm_comp_military_police",
        label     = "Компьютер Полевой Жандармерии (Feldgendarmerie)",
        desc      = "Военный розыск, штрафы комендатуры, военные билеты, удостоверения Feldgendarmerie",
        defTitle  = "ПОЛЕВАЯ ЖАНДАРМЕРИЯ (Feldgendarmerie)",
        defModel  = "models/props/cs_office/computer.mdl",
    },
    security = {
        id        = "security",
        class     = "grm_comp_security",
        label     = "Компьютер Спецслужб (Gestapo / Komitet)",
        desc      = "Полный оперативный доступ, документы прикрытия, прослушка, удостоверения",
        defTitle  = "СЛУЖБА ГОСБЕЗОПАСНОСТИ (Gestapo / Komitet)",
        defModel  = "models/props_lab/monitor02.mdl",
    },
    military = {
        id        = "military",
        class     = "grm_comp_military",
        label     = "Компьютер Военкомата (Учёт и призыв)",
        desc      = "Выдача военных билетов, учёт призывников/мобрезерва, ВВК",
        defTitle  = "ВОЕННЫЙ КОМИССАРИАТ • УЧЁТ И ПРИЗЫВ",
        defModel  = "models/props/cs_office/computer.mdl",
    },
    army = {
        id        = "army",
        class     = "grm_comp_military_police",
        label     = "Служебный компьютер Вооружённых сил",
        desc      = "Кадры, военники, служебные удостоверения — без розыска и штрафов комендатуры",
        defTitle  = "ВООРУЖЁННЫЕ СИЛЫ • СЛУЖЕБНЫЙ ТЕРМИНАЛ",
        defModel  = "models/props/cs_office/computer.mdl",
    },
    traffic = {
        id        = "traffic",
        class     = "grm_comp_traffic",
        label     = "Экзаменационный ПК Автоинспекции",
        desc      = "Автошкола, Дорожная Инспекция ПП (Права A-E), ВАИ (Военные права и спецдопуски)",
        defTitle  = "АВТОИНСПЕКЦИЯ • АВТОШКОЛА / ВАИ / ДОРОЖНАЯ ИНСПЕКЦИЯ ПП",
        defModel  = "models/props/cs_office/computer.mdl",
    },
    medical = {
        id        = "medical",
        class     = "grm_comp_medical",
        label     = "Медицинский Компьютер Госпиталя",
        desc      = "Медицинские карты, история приёмов, категории годности к службе",
        defTitle  = "МЕДИЦИНСКАЯ СЛУЖБА • ГОСПИТАЛЬ И ВВК",
        defModel  = "models/props_lab/monitor02.mdl",
    },
    education = {
        id        = "education",
        class     = "grm_comp_education",
        label     = "Компьютер Учреждения образования (деканат)",
        desc      = "Выписка государственных дипломов, реестр учреждения, проверка бланков",
        defTitle  = "УЧРЕЖДЕНИЕ ОБРАЗОВАНИЯ • ДЕКАНАТ",
        defModel  = "models/props/cs_office/computer.mdl",
    },
    fire = {
        id        = "fire",
        class     = "grm_comp_fire",
        label     = "Пожарная станция (диспетчерская)",
        desc      = "Дежурство, доступ/оповещение, машины, очаги, журнал тушения",
        defTitle  = "ПОЖАРНАЯ СЛУЖБА • ДИСПЕТЧЕРСКАЯ",
        defModel  = "models/props_lab/monitor01a.mdl",
    },
    civil_vehicle = {
        id        = "civil_vehicle",
        class     = "grm_civil_vehicle_computer",
        label     = "Гражданский транспортный компьютер",
        desc      = "Личный рынок транспорта: покупка наличными или со счёта, постановка в личный гараж",
        defTitle  = "ГРАЖДАНСКИЙ РЫНОК ТРАНСПОРТА",
        defModel  = "models/props_lab/monitor02.mdl",
    },
    cityhall = {
        id        = "cityhall",
        class     = "grm_comp_cityhall",
        label     = "Компьютер мэрии (городская администрация)",
        desc      = "Бизнес-лицензии, городская казна, каталог госуслуг",
        defTitle  = "МЭРИЯ • ГОРОДСКАЯ АДМИНИСТРАЦИЯ",
        defModel  = "models/props_lab/monitor02.mdl",
    },
    court = {
        id        = "court",
        class     = "grm_comp_court",
        label     = "Компьютер юстиции (суд / прокуратура)",
        desc      = "Законы и статьи, розыск, реестр штрафов (гражданская юрисдикция)",
        defTitle  = "ЮСТИЦИЯ • СУД И ПРОКУРАТУРА",
        defModel  = "models/props_lab/monitor02.mdl",
    },
    public = {
        id        = "public",
        class     = "grm_comp_public",
        label     = "Гражданский терминал самообслуживания",
        desc      = "Для жителей: долги, госуслуги, проверка диплома, 911, свои ордера и розыск",
        defTitle  = "ГРАЖДАНСКИЙ ТЕРМИНАЛ • САМООБСЛУЖИВАНИЕ",
        defModel  = "models/props/cs_office/computer.mdl",
    },
    general = {
        id        = "general",
        class     = "grm_doc_computer",
        label     = "Универсальный терминал документов",
        desc      = "Общий терминал оформления всех типов документов",
        defTitle  = "СЛУЖЕБНЫЙ ТЕРМИНАЛ ДОКУМЕНТОВ",
        defModel  = "models/props/cs_office/computer.mdl",
    },
}

local function canUse(ply)
    if not IsValid(ply) then return false end
    if ply:IsSuperAdmin() then return true end
    local fac = ply:GetNWString("GRM_Faction", "")
    if fac ~= "" and (_G.FactionsAPI and _G.FactionsAPI.IsLeader and _G.FactionsAPI.IsLeader(ply, fac)) then
        return true
    end
    return false
end

function TOOL:LeftClick(trace)
    if CLIENT then return true end
    local ply = self:GetOwner()
    if not IsValid(ply) then return false end
    if not canUse(ply) then
        if GRM.Notify then GRM.Notify(ply, "Установка служебного оборудования разрешена только руководству и администраторам.", 255, 120, 100) end
        return false
    end
    if not (trace and trace.Hit) then return false end

    local typeKey = self:GetClientInfo("type") or "police"
    local t = TYPES[typeKey] or TYPES.police

    local chosenMdl = self:GetClientInfo("model")
    if not isstring(chosenMdl) or chosenMdl == "" or not util.IsValidModel(chosenMdl) then
        chosenMdl = t.defModel or "models/props/cs_office/computer.mdl"
    end

    local customTitle = self:GetClientInfo("title")
    if not isstring(customTitle) or customTitle == "" then
        customTitle = t.defTitle or t.label
    end

    local ent = ents.Create(t.class)
    if not IsValid(ent) then return false end

    ent:SetModel(chosenMdl)
    ent:SetPos(trace.HitPos + trace.HitNormal * 8)
    local ang = Angle(0, IsValid(ply) and ply:EyeAngles().y + 180 or 0, 0)
    ent:SetAngles(ang)
    ent:Spawn()
    ent:Activate()

    if ent.SetComputerName then
        ent:SetComputerName(customTitle)
    end
    if ent.SetServiceProfile then
        ent:SetServiceProfile(typeKey == "army" and "army" or (typeKey == "military_police" and "gendarmerie" or ""))
    end
    if GRM.CompAccess and GRM.CompAccess.Set then
        GRM.CompAccess.Set(ent, self:GetClientInfo("factions") or "")
    end

    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(false)
        phys:Wake()
    end

    if GRM.PropProtect and GRM.PropProtect.MarkServerEntity then
        GRM.PropProtect.MarkServerEntity(ent)
    end

    local makePerm = self:GetClientInfo("make_perm") ~= "0"
    if makePerm and GRM.Perm and GRM.Perm.Add then
        pcall(function()
            GRM.Perm.Add(ply, ent)
        end)
    end

    if GRM.Notify then
        GRM.Notify(ply, "Установлено: " .. t.label .. (makePerm and " (сохранено на карту)" or ""), 100, 220, 130)
    end
    return true
end

function TOOL:RightClick(trace)
    if CLIENT then return true end
    local ply = self:GetOwner()
    if not IsValid(ply) or not trace or not IsValid(trace.Entity) then return false end
    local ent = trace.Entity
    local cls = ent:GetClass()

    local isServiceComp = false
    for _, def in pairs(TYPES) do
        if def.class == cls then isServiceComp = true break end
    end

    if not isServiceComp then return false end

    if ent.Use then
        ent:Use(ply)
    end
    return true
end

function TOOL:Reload(trace)
    if CLIENT then return true end
    local ply = self:GetOwner()
    if not IsValid(ply) or not IsValid(trace.Entity) then return false end
    local ent = trace.Entity
    local cls = ent:GetClass()

    local isServiceComp = false
    for _, def in pairs(TYPES) do
        if def.class == cls then isServiceComp = true break end
    end

    if not isServiceComp then
        if GRM.Notify then GRM.Notify(ply, "Наведите прицел на служебный компьютер.", 255, 180, 90) end
        return false
    end

    if not canUse(ply) then
        if GRM.Notify then GRM.Notify(ply, "Нет прав на удаление служебного оборудования.", 255, 120, 100) end
        return false
    end

    if GRM.Perm and GRM.Perm.Remove then
        pcall(function() GRM.Perm.Remove(ply, ent) end)
    end

    ent:Remove()
    if GRM.Notify then GRM.Notify(ply, "Служебный компьютер удалён.", 100, 220, 130) end
    return true
end

if CLIENT then
    function TOOL.BuildCPanel(panel)
        panel:AddControl("Header", { Description = "GRM Служебное оборудование: установка и закрепление специализированных рабочих станций ведомств." })

        local combo = panel:ComboBox("Тип компьютера", "grm_service_tool_type")
        for k, def in pairs(TYPES) do
            combo:AddChoice(def.label, k)
        end

        local comboMdl = panel:ComboBox("3D Модель", "grm_service_tool_model")
        comboMdl:AddChoice("Классический настольный ПК (cs_office)", "models/props/cs_office/computer.mdl")
        comboMdl:AddChoice("Моноблок / Терминал (props_lab)", "models/props_lab/monitor02.mdl")
        comboMdl:AddChoice("Рабочая станция с клавиатурой (C17)", "models/props_c17/computer01_keyboard.mdl")
        comboMdl:AddChoice("Защищённая терминальная консоль (C17)", "models/props_c17/consolebox01a.mdl")

        panel:TextEntry("Заголовок на экране:", "grm_service_tool_title")

        panel:CheckBox("Автоматически сохранять на карте (Perm)", "grm_service_tool_make_perm")

        local facRows = (GRM.CompAccess and GRM.CompAccess.Rows) or {}
        local function writeFactions(set)
            local out = {}
            for k, on in pairs(set) do if on then out[#out + 1] = k end end
            table.sort(out)
            RunConsoleCommand("grm_service_tool_factions", table.concat(out, ","))
        end
        local function checkedSet()
            local set, cv = {}, GetConVar("grm_service_tool_factions")
            for name in string.gmatch((cv and cv:GetString()) or "", "([^,]+)") do
                local s = string.Trim(name)
                if s ~= "" then set[s] = true end
            end
            return set
        end
        panel:ControlHelp("ДОСТУП ЭТОГО КОМПЬЮТЕРА")
        panel:Help("Отметьте организации, которым можно пользоваться ЭТИМ ПК. Пусто — как раньше, по ведомству.")
        local facList = vgui.Create("DScrollPanel", panel)
        facList:SetTall(180)
        panel:AddItem(facList)
        local function rebuildFac()
            if not IsValid(facList) then return end
            facList:Clear()
            local cur = checkedSet()
            for _, row in ipairs(facRows) do
                local cb = vgui.Create("DCheckBoxLabel", facList)
                cb:Dock(TOP) cb:SetTall(18) cb:DockMargin(2, 0, 2, 1)
                cb:SetText(row.name .. (row.key ~= row.name and ("  [" .. row.key .. "]") or ""))
                cb:SetChecked(cur[row.key] == true)
                cb.OnChange = function(_, v)
                    local set = checkedSet()
                    set[row.key] = v == true or nil
                    writeFactions(set)
                end
            end
            if #facRows == 0 then
                local hint = vgui.Create("DLabel", facList)
                hint:Dock(TOP) hint:SetWrap(true) hint:SetTall(36)
                hint:SetText("Список организаций ещё не пришёл — нажмите «Обновить».")
            end
        end
        local facBtns = vgui.Create("DPanel", panel)
        facBtns:SetTall(26) facBtns:SetPaintBackground(false)
        panel:AddItem(facBtns)
        local function smallBtn(txt, w, fn)
            local b = vgui.Create("DButton", facBtns)
            b:Dock(LEFT) b:SetWide(w) b:DockMargin(0, 0, 4, 0) b:SetText(txt) b.DoClick = fn
        end
        smallBtn("Обновить", 90, function()
            net.Start("GRM_CompAccess_ListReq") net.SendToServer()
        end)
        smallBtn("Снять всё", 80, function()
            RunConsoleCommand("grm_service_tool_factions", "")
            rebuildFac()
        end)
        smallBtn("Записать на ПК под прицелом", 200, function()
            local cv = GetConVar("grm_service_tool_factions")
            net.Start("GRM_CompAccess_Apply")
            net.WriteString(cv and cv:GetString() or "")
            net.SendToServer()
        end)
        hook.Add("GRM_CompAccess_List", facList, function(_, rows)
            facRows = istable(rows) and rows or facRows
            rebuildFac()
        end)
        rebuildFac()
        net.Start("GRM_CompAccess_ListReq") net.SendToServer()

        panel:Help(
            "УПРАВЛЕНИЕ:\n" ..
            "• ЛКМ — установить выбранный служебный компьютер\n" ..
            "• ПКМ по компьютеру — открыть его меню (как кнопка [E])\n" ..
            "• R по компьютеру — удалить компьютер (и снять перм)\n\n" ..
            "СПЕЦИАЛИЗАЦИЯ:\n" ..
            "• OrdnungPolizei — Розыск, штрафы, паспорта, ксивы полиции\n" ..
            "• Feldgendarmerie — Военный розыск, штрафы, военники, ксивы ВП\n" ..
            "• Вооружённые силы — Кадры и военники, без розыска и штрафов\n" ..
            "• Gestapo / Komitet — Полный надзор, досье, прикрытие, прослушка\n" ..
            "• Военкомат — Выдача военных билетов, учёт призывников, ВВК\n" ..
            "• Автоинспекция — Права Дорожной Инспекции ПП и ВАИ, спецдопуски\n" ..
            "• Госпиталь — Медкарты пациентов, приёмы врачей, справки\n" ..
            "• Учреждение образования — Выписка дипломов, реестр, проверка бланков"
        )
    end
end
