--[[ Модуль (client): ПИКЕР отыгрышей (по мотивам vgui/emote_picker.lua
    EasyChat). Кнопка-строка над чипами в Y-окне: список каталога
    GRMRPChat.CatalogCommands kind=отыгрыш — клик вставляет «/cmd » в поле
    и ставит каретку; никакого самоотправления (влад. веч.-14: украшать, не
    подменять функционал). /emotes — тот же список всплывающим меню. ]]
if not (GRMRPChat and hook and hook.Add and vgui and isfunction(GRMRPChat.CatalogCommands)) then
    return
end

local function openMenu(entry)
    if not DermaMenu or not IsValid(entry) then return end
    local menu = DermaMenu()
    local seen = {}
    for _, it in ipairs(GRMRPChat.CatalogCommands({ emotes = true })) do
        if it.kind == "отыгрыш" and not seen[it.name] then
            seen[it.name] = true
            local opt = menu:AddOption(it.name .. " — " .. it.hint,
                function()
                    if not IsValid(entry) then return end
                    entry:SetText(it.name .. " ")
                    if entry.SetCaretPos then
                        entry:SetCaretPos(#it.name + 1)
                    end
                    entry:RequestFocus()
                end)
            if opt and opt.SetFont then opt:SetFont("GRMRP_Chat14") end
        end
    end
    menu:Open()
end

hook.Add("GRMRPChat_InputBuilt", "grm_chat.picker", function(frame, entry)
    if not IsValid(frame) or not IsValid(entry) then return end
    if IsValid(frame.grmChatPicker) then return end
    local btn = vgui.Create("DButton", frame)
    frame.grmChatPicker = btn
    btn:Dock(TOP)
    btn:SetTall(22)
    btn:SetText("")
    -- вечер-22: пикер докован в то же окно — дорастит frame на свою высоту,
    -- иначе FILL-поле ввода сжимается (шрифт 19px в 8 px = «текст режет»).
    if isfunction(frame.SetTall) and isfunction(frame.GetTall) then
        frame:SetTall(frame:GetTall() + 22)
    end
    btn.DoClick = function() openMenu(entry) end
    btn.Paint = function(p, w, h)
        surface.SetDrawColor(18, 30, 48, 200)
        surface.DrawRect(0, 0, w, h)
        draw.SimpleText("≡ отыгровки / команды — Shift+Tab", "GRMRP_ChatChip",
            8, 4, Color(120, 200, 160))
    end
end)

hook.Add("GRMRPChat_ClientCommand", "grm_chat.emotes_cmd", function(ply, text)
    if ply ~= LocalPlayer() then return end
    local t = tostring(text or "")
    if t:sub(1, 8) ~= "/emotes" then return end
    openMenu(GRMRPChat.GetInputEntry and GRMRPChat.GetInputEntry())
    return true
end)
