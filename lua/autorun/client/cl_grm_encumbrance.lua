--[[--------------------------------------------------------------------

    GRM Encumbrance — client HUD and inventory companion panel

----------------------------------------------------------------------]]

if not CLIENT then return end

include("autorun/sh_grm_encumbrance_config.lua")

GRM = GRM or {}
GRM.Encumbrance = GRM.Encumbrance or {}
local E = GRM.Encumbrance
local NET_SYNC = "GRM_Weight_Sync"

surface.CreateFont("GRMWeight_Label", { font = "Roboto", size = 11, weight = 600, extended = true })
surface.CreateFont("GRMWeight_Value", { font = "Roboto", size = 14, weight = 800, extended = true })
surface.CreateFont("GRMWeight_Title", { font = "Roboto", size = 18, weight = 800, extended = true })

E.ClientState = E.ClientState or {
    weight = 0, capacity = E.Config.Capacity or 50, hard = 62.5,
    multiplier = 1, overloaded = false, blocked = false,
    inventory = 0, weapons = 0, ammo = 0,
}

net.Receive(NET_SYNC, function()
    local state = E.ClientState
    state.weight = net.ReadFloat()
    state.capacity = net.ReadFloat()
    state.hard = net.ReadFloat()
    state.multiplier = net.ReadFloat()
    state.overloaded = net.ReadBool()
    state.blocked = net.ReadBool()
    state.inventory = net.ReadFloat()
    state.weapons = net.ReadFloat()
    state.ammo = net.ReadFloat()
    if net.BytesLeft and net.BytesLeft() >= 4 then state.body = net.ReadFloat() else state.body = state.body or 0 end
    hook.Run("GRM_InventoryWeightUpdated", state)
end)

local function weightColor(state)
    if state.blocked then return Color(220, 70, 65) end
    if state.overloaded then return Color(235, 178, 60) end
    if state.weight / math.max(1, state.capacity) >= 0.5 then return Color(90, 185, 255) end
    return Color(80, 205, 125)
end

--[[ Вес тоже показывает общая панель состояния (заказ владельца 22.08):
     раньше полоса стояла по центру снизу и спорила за место с сытостью и
     выносливостью. Предупреждения о перегрузе остались отдельной строкой
     по центру — это важное сообщение, а не постоянный индикатор. ]]
if GRM.HUD and GRM.HUD.RegisterBar then
    GRM.HUD.RegisterBar("weight", {
        label = "ВЕС", order = 60,
        Get = function()
            local state = E.ClientState
            local hard = math.max(1, state.hard or 1)
            return state.weight, hard,
                string.format("%.1f / %.0f кг", state.weight or 0, state.capacity or 0),
                weightColor(state)
        end,
    })
end

hook.Add("HUDPaint", "GRM_Weight_Warning", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end
    local state = E.ClientState
    if not (state.blocked or state.overloaded) then return end
    local sw, sh = ScrW(), ScrH()
    draw.SimpleText(state.blocked and "ПРЕДЕЛ ПЕРЕНОСА — НЕЛЬЗЯ ПОДНИМАТЬ НОВОЕ" or "ПЕРЕГРУЗ: БЕГ ОТКЛЮЧЁН",
        "GRMWeight_Label", sw / 2, sh - 150,
        state.blocked and Color(255, 110, 100) or Color(255, 200, 90), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
end)

concommand.Add("grm_weight", function()
    local panel = vgui.Create("DFrame")
    GRM.UI.Track("encumbrance", panel)
    panel:SetTitle(""); panel:SetSize(315, 155)
    panel:SetPos(ScrW() / 2 + 230, ScrH() / 2 - 180)
    panel:MakePopup(); panel:SetDeleteOnClose(true)
    panel.Paint = function(_, w, h)
        local state = E.ClientState
        local color = weightColor(state)
        draw.RoundedBox(7, 0, 0, w, h, Color(20, 25, 34, 248))
        draw.RoundedBoxEx(7, 0, 0, w, 32, Color(31, 40, 54), true, true, false, false)
        draw.SimpleText("Переносимый вес", "GRMWeight_Title", 12, 16, Color(240, 244, 250), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local fraction = math.Clamp(state.weight / math.max(1, state.hard), 0, 1)
        draw.RoundedBox(4, 12, 48, w - 24, 18, Color(35, 40, 50))
        draw.RoundedBox(4, 12, 48, (w - 24) * fraction, 18, color)
        draw.SimpleText(string.format("%.1f / %.1f кг", state.weight, state.capacity), "GRMWeight_Value", w / 2, 57, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(string.format("Инвентарь: %.1f кг", state.inventory), "GRMWeight_Label", 14, 81, Color(205, 214, 228))
        draw.SimpleText(string.format("Оружие: %.1f кг", state.weapons), "GRMWeight_Label", 14, 101, Color(205, 214, 228))
        draw.SimpleText(string.format("Тело (еда): %.1f кг", state.body or 0), "GRMWeight_Label", 14, 121, Color(205, 214, 228))
        draw.SimpleText("Скорость: " .. math.floor(state.multiplier * 100) .. "%", "GRMWeight_Label", w - 14, 121, color, TEXT_ALIGN_RIGHT)
    end
end)

print("[GRM] Encumbrance client loaded")
