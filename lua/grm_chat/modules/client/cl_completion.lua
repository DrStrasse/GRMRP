--[[ Модуль (client): АВТОДОПОЛНЕНИЕ слэш-команд (по мотивам
    easychat modules/cmds_auto_completion.lua). Кандидаты — единый словарь
    GRMRPChat.CatalogCommands (отыгрыши + каналы + команды модулей + локальные).
    Shift+Tab — перебор; правая стрелка ПРИ открытом меню — принять; Esc —
    скрыть. ВАЖНО (правило веч.-8): Enter этот модуль НЕ трогает — Enter
    всегда отправляет. ]]
if not (GRMRPChat and hook and hook.Add and vgui) then return end

local LOCAL_CMDS = {
    clear = true, chatdiag = true, mute = true, unmute = true,
    mutes = true, emotes = true, help = true,
}

local st = { items = {}, sel = 0, menu = nil }

local function refresh(entry)
    st.items, st.sel = {}, 0
    if not (IsValid(entry) and GRMRPChat.CompleteCandidates) then return end
    local catalog = GRMRPChat.CatalogCommands(LOCAL_CMDS)
    st.items = GRMRPChat.CompleteCandidates(entry:GetValue(), catalog, 7)
end

local function accept(entry)
    local it = st.items[st.sel]
    if not it then return false end
    entry:SetText(it.name .. " ")
    if entry.SetCaretPos then entry:SetCaretPos(#it.name + 1) end
    st.items, st.sel = {}, 0
    return true
end

hook.Add("GRMRPChat_InputBuilt", "grm_chat.completion", function(frame, entry)
    if not IsValid(entry) then return end
    refresh(entry)

    if IsValid(st.menu) then st.menu:Remove() end
    local menu = vgui.Create("EditablePanel", entry:GetParent())
    st.menu = menu
    menu:Dock(TOP)
    menu:SetTall(0)
    menu:SetMouseInputEnabled(false)
    menu:SetKeyboardInputEnabled(false)
    menu.Paint = function(p, w, _h)
        if #st.items == 0 then return end
        local h = #st.items * 20 + 6
        surface.SetDrawColor(12, 20, 33, 240)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(56, 84, 120, 160)
        surface.DrawOutlinedRect(0, 0, w, h)
        for i, it in ipairs(st.items) do
            local y = 4 + (i - 1) * 20
            if i == st.sel then
                surface.SetDrawColor(48, 204, 255, 36)
                surface.DrawRect(2, y - 1, w - 4, 19)
            end
            draw.SimpleText(it.name, "GRMRP_Chat14", 8, y,
                Color(140, 220, 255), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText(it.hint, "GRMRP_Chat14", 116, y,
                Color(132, 160, 178), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end
    end

    local baseChanged = entry.OnTextChanged
    entry.OnTextChanged = function(pp, ...)
        if baseChanged then baseChanged(pp, ...) end
        refresh(pp)
    end
    local baseTyped = entry.OnKeyCodeTyped
    entry.OnKeyCodeTyped = function(pp, code)
        if #st.items > 0 and code == KEY_TAB and input and input.IsShiftDown
            and input.IsShiftDown() then
            st.sel = st.sel % #st.items + 1
            return true
        end
        if code == KEY_RIGHT and st.sel > 0 then
            if accept(pp) then return true end
        end
        if #st.items > 0 and code == KEY_ESCAPE then
            st.items, st.sel = {}, 0
            return true -- сначала закрыть меню, ещё Esc — окно
        end
        if baseTyped then return baseTyped(pp, code) end
    end
end)
