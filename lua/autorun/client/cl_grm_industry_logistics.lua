--[[--------------------------------------------------------------------
    GRM Industry — окна логистики.

    ЧТО СТАЛО ИНАЧЕ. В окне склада теперь виден ЗАКАЗ: что именно
    нужно, сколько это стоит, сколько заплатят и когда срок. Раньше
    логист видел кнопку «взять заказ» и угадывал содержимое.
----------------------------------------------------------------------]]

if not CLIENT then return end

GRM = GRM or {}
local I = GRM.Industry
local C = GRM.Container
local UI = I.UI
local NET = I.NET
--[[ Палитру (UI.C) заполняет cl_grm_industry_ui.lua, а файлы в
     lua/autorun/client грузятся по алфавиту — этот файл идёт РАНЬШЕ,
     чем ui. Раньше здесь было `local C_ = UI.C`, и на клиенте всё
     падало при загрузке: «attempt to index local 'UI' (a nil
     value)» — окно просто не появлялось. Читаем поле лениво, в
     момент обращения, когда палитра уже создана. ]]
local C_ = setmetatable({}, { __index = function(_, key)
    local palette = I.UI and I.UI.C
    return palette and palette[key]
end })

-- ================================================================
--  ТОЧКА ОТПРАВЛЕНИЯ
-- ================================================================
local function openDepot(ent, data)
    if not IsValid(ent) then return end
    UI.Fonts()
    local f, top = UI.Window("industry_depot", "Точка отправления — " .. (data.label or ""), 760, 520)

    local card, cardTop = UI.Card(f, "ГРУЗ НА ТОЧКЕ")
    card:SetPos(14, top + 8); card:SetSize(732, 200)

    local list = vgui.Create("DScrollPanel", card)
    list:SetPos(8, cardTop); list:SetSize(716, 200 - cardTop - 8)

    local route = data.route
    local loadedByItem = {}
    if route then
        for _, line in ipairs(route.cargo or {}) do loadedByItem[line.itemID] = line.count end
    end

    for _, entry in ipairs(data.stock or {}) do
        local need, loaded = 0, tonumber(loadedByItem[entry.itemID]) or 0
        if route then
            for _, line in ipairs(route.lines or {}) do
                if line.itemID == entry.itemID then need = line.need end
            end
        end
        local p = vgui.Create("DPanel", list)
        p:Dock(TOP); p:SetTall(30); p:DockMargin(0, 0, 0, 4)
        p.Paint = function(self, w, h)
            draw.RoundedBox(5, 0, 0, w, h, self:IsHovered() and C_.hover or C_.slot)
            draw.SimpleText(I.NameOf(entry.itemID), "GRMInd_Normal", 10, h / 2, C_.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText("на точке ×" .. tostring(entry.count), "GRMInd_Small", 280, h / 2, C_.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            if route then
                draw.SimpleText("в машине " .. loaded .. " / " .. need, "GRMInd_Small", 430, h / 2,
                    loaded >= need and C_.green or C_.yellow, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
        end
        if route and route.phase == "collect" then
            local b = UI.Button(p, "погрузить", C_.green, 100, 22); b:Dock(RIGHT); b:DockMargin(0, 4, 8, 4)
            b.DoClick = function()
                net.Start(NET.action) net.WriteEntity(ent) net.WriteString("order_load")
                    net.WriteString(entry.itemID) net.WriteUInt(math.max(1, need - loaded), 16) net.SendToServer()
                f:Close()
            end
        end
    end
    if #(data.stock or {}) == 0 then
        local empty = vgui.Create("DLabel", list)
        empty:Dock(TOP); empty:SetTall(26); empty:SetText("на точке пусто")
        empty:SetFont("GRMInd_Small"); empty:SetTextColor(C_.dim)
    end

    -- Рейс
    local routeCard, routeTop = UI.Card(f, "РЕЙС")
    routeCard:SetPos(14, top + 220); routeCard:SetSize(732, 230)

    if not route then
        local l = vgui.Create("DLabel", routeCard)
        l:SetPos(12, routeTop + 20); l:SetSize(708, 40); l:SetWrap(true)
        l:SetFont("GRMInd_Normal"); l:SetTextColor(C_.dim)
        l:SetText("Активного рейса нет. Заказ берётся на складе, который в этом грузе нуждается — откройте склад фракции и посмотрите раздел «ЗАКАЗЫ».")
    else
        local phaseText = route.phase == "collect" and "Погрузка" or "В пути"
        local l = vgui.Create("DLabel", routeCard)
        l:SetPos(12, routeTop + 14); l:SetSize(708, 24)
        l:SetFont("GRMInd_Head"); l:SetTextColor(route.phase == "collect" and C_.yellow or C_.accent)
        l:SetText("Стадия: " .. phaseText .. "   ·   Груз: " .. tostring(route.cargoWeight) .. " / " .. tostring(route.cargoCapacity) .. " кг")

        local cargoList = vgui.Create("DScrollPanel", routeCard)
        cargoList:SetPos(12, routeTop + 46); cargoList:SetSize(708, 110)
        for _, line in ipairs(route.cargo or {}) do
            local p = vgui.Create("DPanel", cargoList)
            p:Dock(TOP); p:SetTall(26); p:DockMargin(0, 0, 0, 3)
            p.Paint = function(_, w, h)
                draw.RoundedBox(4, 0, 0, w, h, C_.slot)
                draw.SimpleText(I.NameOf(line.itemID), "GRMInd_Small", 10, h / 2, C_.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText("×" .. tostring(line.count), "GRMInd_Small", 320, h / 2, C_.yellow, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
        end

        if route.phase == "collect" then
            local go = UI.Button(routeCard, "Завершить погрузку и ехать", C_.accent, 300, 34)
            go:SetPos(12, routeTop + 166)
            go.DoClick = function()
                net.Start(NET.action) net.WriteEntity(ent) net.WriteString("order_go") net.SendToServer()
                f:Close()
            end
        else
            local l2 = vgui.Create("DLabel", routeCard)
            l2:SetPos(12, routeTop + 166); l2:SetSize(708, 34); l2:SetWrap(true)
            l2:SetFont("GRMInd_Normal"); l2:SetTextColor(C_.green)
            l2:SetText("Груз в машине. Езжайте на склад и нажмите E у склада — окно откроется с кнопкой сдачи.")
        end

        local cancel = UI.Button(routeCard, "Отказаться от рейса", C_.red, 220, 34)
        cancel:SetPos(470, routeTop + 166)
        cancel.DoClick = function()
            net.Start(NET.action) net.WriteEntity(ent) net.WriteString("route_abandon") net.SendToServer()
            f:Close()
        end
    end
end

-- ================================================================
--  СКЛАД ФРАКЦИИ
-- ================================================================
local function openWarehouse(ent, data)
    if not IsValid(ent) then return end
    UI.Fonts()
    local f, top = UI.Window("industry_warehouse", "Склад — " .. (data.label or ""), 900, 640)

    -- ЗАКАЗЫ
    local orderCard, orderTop = UI.Card(f, "ЗАКАЗЫ СКЛАДА")
    orderCard:SetPos(14, top + 8); orderCard:SetSize(872, 250)

    local orderList = vgui.Create("DScrollPanel", orderCard)
    orderList:SetPos(8, orderTop); orderList:SetSize(856, 250 - orderTop - 8)

    local route = data.route
    for _, order in ipairs(data.orders or {}) do
        local p = vgui.Create("DPanel", orderList)
        p:Dock(TOP); p:SetTall(64); p:DockMargin(0, 0, 0, 5)
        local lines = {}
        for _, line in ipairs(order.lines or {}) do
            lines[#lines + 1] = I.NameOf(line.itemID) .. " ×" .. tostring(line.count)
        end
        p.Paint = function(self, w, h)
            draw.RoundedBox(6, 0, 0, w, h, self:IsHovered() and C_.hover or C_.slot)
            draw.SimpleText(table.concat(lines, ", "), "GRMInd_Normal", 12, 16, C_.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            local left = math.max(0, (tonumber(order.deadline) or 0) - os.time())
            draw.SimpleText("Срок: " .. string.FormattedTime(left, "%02i:%02i") ..
                "   ·   Вес: " .. tostring(order.weight) .. " кг   ·   Ценность: " .. UI.Money(order.value),
                "GRMInd_Small", 12, 42, left < 300 and C_.red or C_.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(UI.Money(order.reward), "GRMInd_Head", w - 150, h / 2, C_.green, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end

        if order.state == "open" and not route then
            local b = UI.Button(p, "взять", C_.accent, 110, 34); b:Dock(RIGHT); b:DockMargin(0, 15, 12, 15)
            b.DoClick = function()
                net.Start(NET.action) net.WriteEntity(ent) net.WriteString("order_take")
                    net.WriteString(order.id) net.SendToServer()
                f:Close()
            end
        elseif order.mine then
            local b = UI.Button(p, "сдать груз", C_.green, 130, 34); b:Dock(RIGHT); b:DockMargin(0, 15, 12, 15)
            b:SetEnabled(route and route.phase == "haul")
            b.DoClick = function()
                net.Start(NET.action) net.WriteEntity(ent) net.WriteString("order_deliver") net.SendToServer()
                f:Close()
            end
        end
    end
    if #(data.orders or {}) == 0 then
        local empty = vgui.Create("DLabel", orderList)
        empty:Dock(TOP); empty:SetTall(26); empty:SetText("заказов нет — склад укомплектован")
        empty:SetFont("GRMInd_Small"); empty:SetTextColor(C_.dim)
    end

    -- СОДЕРЖИМОЕ
    local stockCard, stockTop = UI.Card(f, "НА СКЛАДЕ")
    stockCard:SetPos(14, top + 268); stockCard:SetSize(430, 310)

    local stockList = vgui.Create("DScrollPanel", stockCard)
    stockList:SetPos(8, stockTop); stockList:SetSize(414, 310 - stockTop - 8)
    for _, entry in ipairs(data.stock or {}) do
        local p = vgui.Create("DPanel", stockList)
        p:Dock(TOP); p:SetTall(28); p:DockMargin(0, 0, 0, 3)
        p.Paint = function(_, w, h)
            draw.RoundedBox(4, 0, 0, w, h, C_.slot)
            draw.SimpleText(I.NameOf(entry.itemID), "GRMInd_Small", 10, h / 2, C_.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText("×" .. tostring(entry.count), "GRMInd_Small", 300, h / 2, C_.yellow, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
    if #(data.stock or {}) == 0 then
        local empty = vgui.Create("DLabel", stockList)
        empty:Dock(TOP); empty:SetTall(26); empty:SetText("пусто")
        empty:SetFont("GRMInd_Small"); empty:SetTextColor(C_.dim)
    end

    -- СПРОС
    local demandCard, demandTop = UI.Card(f, "СПРОС СКЛАДА")
    demandCard:SetPos(456, top + 268); demandCard:SetSize(430, 310)

    local demandList = vgui.Create("DScrollPanel", demandCard)
    demandList:SetPos(8, demandTop); demandList:SetSize(414, 310 - demandTop - 44)

    local demandDraft = table.Copy(data.demand or {})

    local function renderDemand()
        demandList:Clear()
        for itemID, name in pairs(data.itemNames or {}) do
            if I.PriceOf(itemID) > 0 then
                local rule = demandDraft[itemID] or { min = 0, max = 0 }
                local p = vgui.Create("DPanel", demandList)
                p:Dock(TOP); p:SetTall(30); p:DockMargin(0, 0, 0, 3)
                p.Paint = function(_, w, h)
                    draw.RoundedBox(4, 0, 0, w, h, C_.slot)
                    draw.SimpleText(name, "GRMInd_Small", 10, h / 2, C_.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end
                local minEntry = vgui.Create("DTextEntry", p)
                minEntry:SetPos(190, 3); minEntry:SetSize(60, 24)
                minEntry:SetText(tostring(rule.min or 0)); minEntry:SetNumeric(true)
                minEntry:SetEnabled(data.canManage == true)
                local maxEntry = vgui.Create("DTextEntry", p)
                maxEntry:SetPos(256, 3); maxEntry:SetSize(60, 24)
                maxEntry:SetText(tostring(rule.max or 0)); maxEntry:SetNumeric(true)
                maxEntry:SetEnabled(data.canManage == true)

                minEntry.OnChange = function(self2)
                    demandDraft[itemID] = demandDraft[itemID] or { min = 0, max = 0 }
                    demandDraft[itemID].min = math.max(0, tonumber(self2:GetValue()) or 0)
                end
                maxEntry.OnChange = function(self2)
                    demandDraft[itemID] = demandDraft[itemID] or { min = 0, max = 0 }
                    demandDraft[itemID].max = math.max(0, tonumber(self2:GetValue()) or 0)
                end
            end
        end
    end
    renderDemand()

    local save = UI.Button(demandCard, "Сохранить спрос", C_.green, 200, 30)
    save:SetPos(8, 310 - 40)
    save:SetEnabled(data.canManage == true)
    save.DoClick = function()
        net.Start(NET.action) net.WriteEntity(ent) net.WriteString("warehouse_demand")
            net.WriteTable(demandDraft) net.SendToServer()
        f:Close()
    end

    if data.canManage ~= true then
        local note = vgui.Create("DLabel", demandCard)
        note:SetPos(216, 310 - 36); note:SetSize(200, 22)
        note:SetFont("GRMInd_Small"); note:SetTextColor(C_.dim)
        note:SetText("правит суперадмин")
    end
end

-- ================================================================
--  ШКАФ ФРАКЦИИ
-- ================================================================
local function openArmory(ent, data)
    if not IsValid(ent) then return end
    UI.Fonts()
    local f, top = UI.Window("industry_armory", "Оружейный шкаф — " .. (data.label or ""), 700, 520)

    local card, cardTop = UI.Card(f, "В ШКАФУ")
    card:SetPos(14, top + 8); card:SetSize(672, 240)

    local list = vgui.Create("DScrollPanel", card)
    list:SetPos(8, cardTop); list:SetSize(656, 240 - cardTop - 8)

    for _, entry in ipairs(data.stock or {}) do
        local p = vgui.Create("DPanel", list)
        p:Dock(TOP); p:SetTall(30); p:DockMargin(0, 0, 0, 4)
        p.Paint = function(self, w, h)
            draw.RoundedBox(5, 0, 0, w, h, self:IsHovered() and C_.hover or C_.slot)
            draw.SimpleText(entry.itemID, "GRMInd_Normal", 10, h / 2, C_.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText("×" .. tostring(entry.count), "GRMInd_Normal", 380, h / 2, C_.yellow, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        local take = UI.Button(p, "взять", C_.accent, 90, 22); take:Dock(RIGHT); take:DockMargin(0, 4, 8, 4)
        take.DoClick = function()
            net.Start(NET.action) net.WriteEntity(ent) net.WriteString("armory_take")
                net.WriteString(entry.itemID) net.SendToServer()
            f:Close()
        end
    end
    if #(data.stock or {}) == 0 then
        local empty = vgui.Create("DLabel", list)
        empty:Dock(TOP); empty:SetTall(26); empty:SetText("шкаф пуст")
        empty:SetFont("GRMInd_Small"); empty:SetTextColor(C_.dim)
    end

    local card2, cardTop2 = UI.Card(f, "СДАЧА ОРУЖИЯ")
    card2:SetPos(14, top + 258); card2:SetSize(672, 210)

    local list2 = vgui.Create("DScrollPanel", card2)
    list2:SetPos(8, cardTop2); list2:SetSize(656, 210 - cardTop2 - 8)

    for _, entry in ipairs(data.carried or {}) do
        local p = vgui.Create("DPanel", list2)
        p:Dock(TOP); p:SetTall(30); p:DockMargin(0, 0, 0, 4)
        p.Paint = function(_, w, h)
            draw.RoundedBox(5, 0, 0, w, h, C_.slot)
            draw.SimpleText(entry.name or entry.itemID, "GRMInd_Normal", 10, h / 2, C_.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        local put = UI.Button(p, "сдать в шкаф", C_.green, 130, 22); put:Dock(RIGHT); put:DockMargin(0, 4, 8, 4)
        put.DoClick = function()
            net.Start(NET.action) net.WriteEntity(ent) net.WriteString("armory_store")
                net.WriteString(entry.itemID) net.SendToServer()
            f:Close()
        end
    end
end

local Openers = {
    depot = openDepot,
    warehouse = openWarehouse,
    armory = openArmory,
}

net.Receive(NET.open, function()
    local ent = net.ReadEntity()
    local data = net.ReadTable() or {}
    local opener = Openers[data.role or ""]
    if opener then opener(ent, data) end
end)

print("[GRM Industry] окна логистики загружены")
