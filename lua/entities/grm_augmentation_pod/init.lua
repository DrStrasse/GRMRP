--[[
    GRM Капсула аугментации
    Капсула для кибернетических аугментаций
]]

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.Category = "GRM — Аугментации"
ENT.PrintName = "Капсула аугментации"
ENT.Author = "GRM Team"
ENT.Spawnable = true
ENT.AdminOnly = true

function ENT:SetupDataTables()
    self:NetworkVar("Bool", 0, "Active")
    self:NetworkVar("Bool", 1, "Occupied")
    self:NetworkVar("Entity", 0, "Occupant")
end

if SERVER then
    function ENT:Initialize()
        self:SetModel("models/props_c17/FurnitureFridge001a.mdl")
        self:PhysicsInit(SOLID_BBOX)
        self:SetMoveType(MOVETYPE_NONE)
        self:SetSolid(SOLID_BBOX)
        self:SetCollisionBounds(Vector(-30, -30, 0), Vector(30, 30, 100))

        self:SetUseType(SIMPLE_USE)
        self:SetActive(true)
        self:SetOccupied(false)

        local phys = self:GetPhysicsObject()
        if IsValid(phys) then
            phys:Wake()
            phys:EnableMotion(false)
        end
    end

    function ENT:Use(activator, caller)
        if not IsValid(caller) or not caller:IsPlayer() then return end

        if not self:GetActive() then
            caller:ChatPrint("[Капсула аугментации] Система неактивна.")
            return
        end

        if self:GetOccupied() then
            local occupant = self:GetOccupant()
            if IsValid(occupant) and occupant == caller then
                -- Освобождение капсулы
                self:SetOccupied(false)
                self:SetOccupant(nil)
                caller:ChatPrint("[Капсула аугментации] Вы покинули капсулу.")
            else
                caller:ChatPrint("[Капсула аугментации] Капсула занята.")
            end
            return
        end

        -- Занятие капсулы
        self:SetOccupied(true)
        self:SetOccupant(caller)
        caller:ChatPrint("[Капсула аугментации] Добро пожаловать! Используйте меню для выбора аугментаций.")

        -- Отправка меню аугментаций
        net.Start("GRM_AugmentationPod_Open")
        net.Send(caller)
    end

    function ENT:Think()
        -- Проверка occupants. Раньше Think капсулы выполнялся КАЖДЫЙ тик
        -- (без NextThink) ради одной проверки валидности — теперь дважды в
        -- секунду, а при пустой капсуле ещё реже.
        if self:GetOccupied() then
            local occupant = self:GetOccupant()
            if not IsValid(occupant) then
                self:SetOccupied(false)
                self:SetOccupant(nil)
            end
            self:NextThink(CurTime() + 0.5)
        else
            self:NextThink(CurTime() + 2)
        end
        return true
    end

    -- Обработка запросов на аугментацию из капсулы
    net.Receive("GRM_AugmentationPod_Apply", function(len, ply)
        if GRM.AugmentationAccess and not GRM.AugmentationAccess.Can(ply,"implant") then GRM.AugmentationAccess.Deny(ply); return end
        local augType = net.ReadString()

        -- Проверка что игрок в капсуле
        local inPod = false
        for _, ent in ipairs(ents.FindByClass("grm_augmentation_pod")) do
            if IsValid(ent) and ent:GetOccupant() == ply then
                inPod = true
                break
            end
        end

        if not inPod then
            ply:ChatPrint("[Капсула аугментации] Вы должны находиться в капсуле для аугментации.")
            return
        end

        -- Проверка прав доступа
        if not GRM.Augmentations.CanAccessAugmentation(ply, augType) then
            ply:ChatPrint("[Капсула аугментации] У вас нет прав доступа к этой аугментации.")
            return
        end

        -- Применение аугментации
        local success, errorMsg = GRM.Augmentations.ApplyAugmentation(ply, augType)

        if success then
            local augConfig = GRM.Augmentations.Config[augType]
            ply:ChatPrint("[Капсула аугментации] Аугментация '" .. (augConfig and augConfig.name or augType) .. "' успешно применена!")

            -- Визуальный эффект
            local effect = EffectData()
            effect:SetOrigin(ply:GetPos())
            effect:SetMagnitude(5)
            effect:SetScale(1)
            util.Effect("cball_explode", effect)

            -- Звук
            ply:EmitSound("items/suitchargeok1.wav", 75, 100)
        else
            ply:ChatPrint("[Капсула аугментации] Ошибка: " .. (errorMsg or "Не удалось применить аугментацию."))
        end
    end)

    -- Network string
    util.AddNetworkString("GRM_AugmentationPod_Open")
    util.AddNetworkString("GRM_AugmentationPod_Apply")

else
    -- Client side

    -- GRM UI Fonts для Pod
    surface.CreateFont("GRMAugPod_Title", { font = "Roboto", size = 20, weight = 800, extended = true })
    surface.CreateFont("GRMAugPod_Sub", { font = "Roboto", size = 15, weight = 600, extended = true })
    surface.CreateFont("GRMAugPod_Normal", { font = "Roboto", size = 13, weight = 500, extended = true })
    surface.CreateFont("GRMAugPod_Small", { font = "Roboto", size = 12, weight = 500, extended = true })
    surface.CreateFont("GRMAugPod_Bold", { font = "Roboto", size = 13, weight = 700, extended = true })

    -- GRM Colors
    local GRM_COLORS = {
        bg = Color(15, 20, 30, 250),
        panel = Color(25, 35, 50, 240),
        panel2 = Color(20, 28, 40, 235),
        accent = Color(0, 150, 255),
        accent_hover = Color(50, 180, 255),
        text = Color(220, 230, 240),
        text_dim = Color(140, 150, 170),
        success = Color(50, 200, 100),
        warning = Color(255, 180, 50),
        error = Color(255, 80, 80),
        border = Color(60, 80, 110, 150),
        head = Color(18, 22, 30, 255)
    }

    -- Визуализация капсулы
    function ENT:Draw()
        self:DrawModel()

        -- Подсветка если активна
        if self:GetActive() then
            local col = self:GetOccupied() and Color(255, 100, 100) or Color(100, 255, 100)
            render.SetColorModulation(col.r / 255, col.g / 255, col.b / 255)
        end
    end

    -- HUD при наведении
    -- Краски подписи капсулы (перерисовка каждый кадр; §6.1.8)
    local POD_HEAD = Color(0, 255, 200)
    local POD_BUSY = Color(255, 100, 100)
    local POD_FREE = Color(100, 255, 100)

    hook.Add("HUDPaint", "GRM_AugmentationPod_HUD", function()
        local ply = LocalPlayer()
        local tr = (GRM and GRM.Perf and GRM.Perf.EyeTrace) and GRM.Perf.EyeTrace(ply, 0.05) or (IsValid(ply) and ply:GetEyeTrace())
        if not tr then return end
        local ent = tr.Entity

        if not IsValid(ent) or ent:GetClass() ~= "grm_augmentation_pod" then return end

        local dist = ply:GetPos():Distance(ent:GetPos())
        if dist > 150 then return end

        local screenPos = ent:GetPos():ToScreen()

        draw.SimpleText("КАПСУЛА АУГМЕНТАЦИИ", "DermaDefaultBold", screenPos.x, screenPos.y - 40, POD_HEAD, TEXT_ALIGN_CENTER)

        if ent:GetOccupied() then
            draw.SimpleText("ЗАНЯТО", "DermaDefault", screenPos.x, screenPos.y - 20, POD_BUSY, TEXT_ALIGN_CENTER)
        else
            draw.SimpleText("Нажмите E для использования", "DermaDefault", screenPos.x, screenPos.y - 20, POD_FREE, TEXT_ALIGN_CENTER)
        end
    end)

    -- Меню аугментаций
    net.Receive("GRM_AugmentationPod_Open", function()
        -- Получение доступных аугментаций
        local availableAugs = GRM.Augmentations.GetAvailableAugmentations(LocalPlayer())

        local frame = vgui.Create("DFrame")
        frame:SetTitle("Капсула аугментации - Выбор аугментаций")
        frame:SetSize(650, 500)
        frame:Center()
        frame:MakePopup()

        -- Стилизация в GRM стиле
        frame.Paint = function(self, w, h)
            draw.RoundedBox(8, 0, 0, w, h, Color(15, 20, 30, 250))
            draw.RoundedBoxEx(8, 0, 0, w, 40, Color(25, 35, 50), true, true, false, false)
            surface.SetDrawColor(Color(60, 80, 110, 150))
            surface.DrawLine(0, 40, w, 40)

            draw.SimpleText("КАПСУЛА АУГМЕНТАЦИИ", "DermaLarge", 20, 20, Color(0, 150, 255), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText("v2.0", "DermaDefault", w - 20, 20, Color(140, 150, 170), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end

        local panel = vgui.Create("DPanel", frame)
        panel:Dock(FILL)
        panel:DockMargin(10, 50, 10, 10)
        panel.Paint = function(self, w, h)
            draw.RoundedBox(6, 0, 0, w, h, Color(25, 35, 50, 240))
        end

        -- Заголовок
        local title = vgui.Create("DLabel", panel)
        title:Dock(TOP)
        title:DockMargin(10, 10, 10, 10)
        title:SetText("ДОСТУПНЫЕ АУГМЕНТАЦИИ")
        title:SetFont("DermaLarge")
        title:SetTextColor(Color(220, 230, 240))

        -- Информация об игроке
        local ply = LocalPlayer()
        local infoLabel = vgui.Create("DLabel", panel)
        infoLabel:Dock(TOP)
        infoLabel:DockMargin(10, 0, 10, 10)
        infoLabel:SetText("Игрок: " .. ply:Nick() .. " | HP: " .. ply:Health() .. "/" .. ply:GetMaxHealth() .. " | Armor: " .. ply:Armor())
        infoLabel:SetFont("DermaDefault")
        infoLabel:SetTextColor(Color(140, 150, 170))

        -- Список аугментаций
        if #availableAugs == 0 then
            local noAugsLabel = vgui.Create("DLabel", panel)
            noAugsLabel:Dock(TOP)
            noAugsLabel:DockMargin(10, 50, 10, 10)
            noAugsLabel:SetText("Нет доступных аугментаций для вашего уровня доступа.")
            noAugsLabel:SetFont("DermaDefaultBold")
            noAugsLabel:SetTextColor(Color(255, 180, 50))
            noAugsLabel:SetContentAlignment(5)
        else
            local scrollPanel = vgui.Create("DScrollPanel", panel)
            scrollPanel:Dock(FILL)
            scrollPanel:DockMargin(10, 10, 10, 10)

            -- Группировка по категориям
            local categories = {}
            for _, aug in ipairs(availableAugs) do
                categories[aug.category] = categories[aug.category] or {}
                table.insert(categories[aug.category], aug)
            end

            -- Сортировка категорий
            local categoryOrder = {"civilian", "service", "military", "experimental"}
            local categoryColors = {
                civilian = Color(50, 200, 100),
                service = Color(0, 150, 255),
                military = Color(255, 180, 50),
                experimental = Color(255, 80, 80)
            }
            local categoryNames = {
                civilian = "ГРАЖДАНСКИЕ",
                service = "СЛУЖЕБНЫЕ",
                military = "ВОЕННЫЕ",
                experimental = "ЭКСПЕРИМЕНТАЛЬНЫЕ"
            }

            for _, catKey in ipairs(categoryOrder) do
                local catAugs = categories[catKey]
                if catAugs and #catAugs > 0 then
                    -- Заголовок категории
                    local catLabel = vgui.Create("DLabel", scrollPanel)
                    catLabel:Dock(TOP)
                    catLabel:DockMargin(0, 10, 0, 5)
                    catLabel:SetText(categoryNames[catKey] or catKey:upper())
                    catLabel:SetFont("DermaDefaultBold")
                    catLabel:SetTextColor(categoryColors[catKey] or Color(220, 230, 240))

                    -- Аугментации в категории
                    for _, aug in ipairs(catAugs) do
                        local augPanel = vgui.Create("DPanel", scrollPanel)
                        augPanel:Dock(TOP)
                        augPanel:DockMargin(0, 0, 0, 5)
                        augPanel:SetTall(70)
                        augPanel.Paint = function(self, w, h)
                            draw.RoundedBox(6, 0, 0, w, h, Color(35, 45, 65))
                            surface.SetDrawColor(categoryColors[catKey] or Color(0, 150, 255))
                            surface.DrawOutlinedRect(0, 0, w, h, 2)
                        end

                        local nameLbl = vgui.Create("DLabel", augPanel)
                        nameLbl:SetPos(10, 10)
                        nameLbl:SetText(aug.name)
                        nameLbl:SetFont("DermaDefaultBold")
                        nameLbl:SetTextColor(Color(220, 230, 240))

                        local descLbl = vgui.Create("DLabel", augPanel)
                        descLbl:SetPos(10, 30)
                        descLbl:SetText(aug.description)
                        descLbl:SetFont("DermaDefault")
                        descLbl:SetTextColor(Color(180, 190, 210))

                        local costLbl = vgui.Create("DLabel", augPanel)
                        costLbl:SetPos(10, 50)
                        costLbl:SetText("Стоимость: $" .. aug.cost)
                        costLbl:SetFont("DermaDefault")
                        costLbl:SetTextColor(Color(255, 200, 100))

                        local applyBtn = vgui.Create("DButton", augPanel)
                        applyBtn:SetPos(480, 20)
                        applyBtn:SetSize(130, 30)
                        applyBtn:SetText("ПРИМЕНИТЬ")
                        applyBtn:SetFont("DermaDefaultBold")
                        applyBtn:SetTextColor(Color(220, 230, 240))

                        applyBtn.Paint = function(self, w, h)
                            local col = self:IsHovered() and Color(50, 180, 255) or Color(0, 150, 255)
                            draw.RoundedBox(4, 0, 0, w, h, col)
                        end

                        applyBtn.DoClick = function()
                            net.Start("GRM_AugmentationPod_Apply")
                            net.WriteString(aug.type)
                            net.SendToServer()
                        end
                    end
                end
            end
        end

        -- Кнопка выхода
        local exitBtn = vgui.Create("DButton", frame)
        exitBtn:Dock(BOTTOM)
        exitBtn:DockMargin(10, 0, 10, 10)
        exitBtn:SetTall(45)
        exitBtn:SetText("ПОКИНУТЬ КАПСУЛУ")
        exitBtn:SetFont("DermaDefaultBold")
        exitBtn:SetTextColor(Color(220, 230, 240))

        exitBtn.Paint = function(self, w, h)
            local col = self:IsHovered() and Color(255, 100, 100) or Color(200, 60, 60)
            draw.RoundedBox(6, 0, 0, w, h, col)
        end

        exitBtn.DoClick = function()
            LocalPlayer():ConCommand("impulse 100") -- Выйти из капсулы
            frame:Close()
        end
    end)
end
