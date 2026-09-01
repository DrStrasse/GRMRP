--[[--------------------------------------------------------------------
    GRM Labs Craft UI v2.0.0 — client
----------------------------------------------------------------------]]

if SERVER then return end

GRM = GRM or {}
GRM.NarcCraft = GRM.NarcCraft or {}

surface.CreateFont("GRM_Craft_Title", {font="Roboto", size=22, weight=800, extended=true})
surface.CreateFont("GRM_Craft_Normal", {font="Roboto", size=15, weight=600, extended=true})
surface.CreateFont("GRM_Craft_Small", {font="Roboto", size=12, weight=500, extended=true})

local C = {
    bg=Color(18,22,32,248), top=Color(30,38,54,248), card=Color(34,43,62,246),
    accent=Color(70,155,255), green=Color(70,205,120), red=Color(225,80,75),
    text=Color(240,244,250), dim=Color(166,176,191), yellow=Color(245,195,70)
}

local function startCraft(labType, recipeID)
    net.Start("GRM_NarcCraft_Start")
        net.WriteString(labType or "narc")
        net.WriteString(recipeID or "")
    net.SendToServer()
end

local function openUI(data)
    data = istable(data) and data or { labType="narc", title="Лаборатория", recipes={} }
    local f = vgui.Create("DFrame")
    GRM.UI.Track("narcotics_craft", f)
    f:SetTitle("")
    f:SetSize(760, 560)
    f:Center()
    f:MakePopup()
    f:ShowCloseButton(true)
    f.Paint = function(_, w, h)
        draw.RoundedBox(10, 0, 0, w, h, C.bg)
        draw.RoundedBoxEx(10, 0, 0, w, 58, C.top, true, true, false, false)
        draw.SimpleText(data.title or "Лаборатория", "GRM_Craft_Title", 18, 29, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Выберите рецепт. Ингредиенты подсвечены по наличию.", "GRM_Craft_Small", w - 18, 31, C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    local scroll = vgui.Create("DScrollPanel", f)
    scroll:Dock(FILL)
    scroll:DockMargin(12, 70, 12, 12)

    if not data.recipes or #data.recipes == 0 then
        local empty = vgui.Create("DLabel", scroll)
        empty:Dock(TOP); empty:SetTall(80); empty:SetText("Нет рецептов для этой лаборатории")
        empty:SetFont("GRM_Craft_Normal"); empty:SetTextColor(C.dim)
        return
    end

    for _, r in ipairs(data.recipes) do
        local row = vgui.Create("DPanel", scroll)
        row:Dock(TOP)
        row:SetTall(118)
        row:DockMargin(0, 0, 0, 8)
        row.Paint = function(_, w, h)
            draw.RoundedBox(8, 0, 0, w, h, C.card)
            draw.SimpleText(r.name or r.id, "GRM_Craft_Normal", 14, 18, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText("Время: " .. tostring(r.time or 0) .. " сек  •  Выход: " .. tostring(r.yield or 1), "GRM_Craft_Small", 14, 42, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            local x = 14
            for _, ing in ipairs(r.ingredients or {}) do
                local txt = tostring(ing.id) .. ": " .. tostring(ing.have or 0) .. "/" .. tostring(ing.need or 0)
                draw.SimpleText(txt, "GRM_Craft_Small", x, 72, ing.ok and C.green or C.red, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                x = x + 165
            end
        end
        local btn = vgui.Create("DButton", row)
        btn:SetSize(150, 34)
        btn:SetPos(590, 42)
        btn:SetText(r.can and "Начать" or "Не хватает")
        btn:SetEnabled(r.can == true)
        btn.DoClick = function()
            startCraft(data.labType, r.id)
            f:Close()
        end
    end
end

net.Receive("GRM_NarcCraft_Open", function()
    openUI(net.ReadTable() or {})
end)

net.Receive("GRM_NarcCraft_Progress", function()
    local name = net.ReadString()
    local t = net.ReadUInt(16)
    notification.AddLegacy("Процесс: " .. name .. " (" .. t .. " сек)", NOTIFY_GENERIC, 5)
end)

net.Receive("GRM_NarcCraft_Done", function()
    local name = net.ReadString()
    notification.AddLegacy(name .. " готово!", NOTIFY_GENERIC, 5)
end)

print("[GRM] Labs Craft UI Client loaded v2")
