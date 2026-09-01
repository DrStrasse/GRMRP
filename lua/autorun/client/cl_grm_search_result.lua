--[[--------------------------------------------------------------------
    GRM Search Result UI - Client (Код 121)
    Показывает результаты обыска с чекбоксами для изъятия
----------------------------------------------------------------------]]

if SERVER then return end

net.Receive("GRM_Search_Result", function()
    local searcher = net.ReadEntity()
    local target = net.ReadEntity()
    local foundCount = net.ReadUInt(8)

    local found = {}
    for i = 1, foundCount do
        local type = net.ReadString()
        local id = net.ReadString()
        local count = net.ReadUInt(8)
        found[#found + 1] = {type = type, id = id, count = count}
    end

    -- Создаём окно результатов
    local frame = vgui.Create("DFrame")
    GRM.UI.Track("search_result", frame)
    frame:SetTitle("Обыск: " .. target:Nick())
    frame:SetSize(500, 400)
    frame:Center()
    frame:MakePopup()
    frame:SetDraggable(true)
    frame:ShowCloseButton(true)

    local scroll = vgui.Create("DScrollPanel", frame)
    scroll:Dock(FILL)
    scroll:DockMargin(8, 30, 8, 8)

    if #found == 0 then
        local label = vgui.Create("DLabel", scroll)
        label:Dock(TOP)
        label:SetTall(30)
        label:SetText("Ничего не найдено")
        label:SetTextColor(Color(100, 220, 100))
        label:SetFont("DermaDefault")
    else
        local label = vgui.Create("DLabel", scroll)
        label:Dock(TOP)
        label:SetTall(30)
        label:SetText("Найдено запрещённых предметов (отметьте для изъятия):")
        label:SetTextColor(Color(255, 200, 100))
        label:SetFont("DermaDefaultBold")

        for i, item in ipairs(found) do
            local row = vgui.Create("DPanel", scroll)
            row:Dock(TOP)
            row:SetTall(50)
            row:DockMargin(0, 2, 0, 2)

            row.Paint = function(self, w, h)
                draw.RoundedBox(4, 0, 0, w, h, Color(40, 40, 40, 200))
            end

            -- Чекбокс
            local checkbox = vgui.Create("DCheckBoxLabel", row)
            checkbox:Dock(LEFT)
            checkbox:DockMargin(8, 0, 0, 0)
            checkbox:SetText("")
            checkbox:SetValue(false)

            -- Информация о предмете
            local icon = item.type == "weapon" and "" or "📦"
            local text = string.format("%s %s × %d", icon, item.id, item.count)

            local infoLabel = vgui.Create("DLabel", row)
            infoLabel:Dock(FILL)
            infoLabel:DockMargin(40, 0, 0, 0)
            infoLabel:SetText(text)
            infoLabel:SetTextColor(Color(255, 200, 100))
            infoLabel:SetFont("DermaDefault")

            -- Кнопка "Изъять"
            local btnConfiscate = vgui.Create("DButton", row)
            btnConfiscate:Dock(RIGHT)
            btnConfiscate:SetWide(80)
            btnConfiscate:DockMargin(0, 5, 8, 5)
            btnConfiscate:SetText("Изъять")
            btnConfiscate:SetFont("DermaDefault")
            btnConfiscate.Paint = function(self, w, h)
                local col = self:IsHovered() and Color(255, 100, 100) or Color(200, 80, 80)
                draw.RoundedBox(4, 0, 0, w, h, col)
            end
            btnConfiscate.DoClick = function()
                net.Start("GRM_Search_Confiscate")
                    net.WriteEntity(target)
                    net.WriteString(item.type)
                    net.WriteString(item.id)
                    net.WriteUInt(item.count or 1, 8)
                net.SendToServer()

                -- Удаляем строку из UI
                row:Remove()

                -- Если все изъяты, закрываем окно
                if scroll:GetCanvas():GetChildCount() <= 1 then
                    timer.Simple(0.5, function()
                        if IsValid(frame) then frame:Close() end
                    end)
                end
            end
        end
    end

    -- Кнопка "Изъять всё"
    if #found > 0 then
        local btnAll = vgui.Create("DButton", frame)
        btnAll:Dock(BOTTOM)
        btnAll:SetTall(30)
        btnAll:DockMargin(8, 0, 8, 8)
        btnAll:SetText("Изъять ВСЁ")
        btnAll:SetFont("DermaDefaultBold")
        btnAll.Paint = function(self, w, h)
            local col = self:IsHovered() and Color(255, 80, 80) or Color(200, 60, 60)
            draw.RoundedBox(4, 0, 0, w, h, col)
        end
        btnAll.DoClick = function()
            -- Изъяем все предметы по очереди
            for _, item in ipairs(found) do
                net.Start("GRM_Search_Confiscate")
                    net.WriteEntity(target)
                    net.WriteString(item.type)
                    net.WriteString(item.id)
                    net.WriteUInt(item.count or 1, 8)
                net.SendToServer()
            end
            frame:Close()
        end
    end
end)
