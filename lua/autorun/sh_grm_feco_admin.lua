--[[--------------------------------------------------------------------
    GRM Feco Admin — вкладка "Экономика" в /factions для суперадмина

    Даёт доступ к:
    - Гос.бюджет (просмотр, пополнение, снятие)
    - Фракционные бюджеты (просмотр, изменение)
    - Налоги (просмотр, изменение ставки)
    - Штрафы (настройка)

    Открывается через /factions → вкладка "Экономика" (только суперадмин)
    Или через !grmmenu / grm_adminmenu
----------------------------------------------------------------------]]

if SERVER then
    AddCSLuaFile()
end

GRM = GRM or {}
GRM.FecoAdmin = GRM.FecoAdmin or {}

-- ================================================================
-- СЕРВЕРНАЯ ЧАСТЬ
-- ================================================================

if SERVER then
    local NET_OPEN = "GRM_FecoAdmin_Open"
    local NET_DATA = "GRM_FecoAdmin_Data"
    local NET_ACTION = "GRM_FecoAdmin_Action"

    util.AddNetworkString(NET_OPEN)
    util.AddNetworkString(NET_DATA)
    util.AddNetworkString(NET_ACTION)

    -- Обработчик открытия меню
    net.Receive(NET_OPEN, function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end

        local data = {}

        data.stateBudget = (GRM.StateBudgetGet and GRM.StateBudgetGet())
            or (GRM.Economy and GRM.Economy.StateBudgetGet and GRM.Economy.StateBudgetGet())
            or 0

        data.factions = {}
        local seen = {}
        local function put(name)
            name = tostring(name or "")
            if name == "" or seen[name] then return end
            seen[name] = true
            local eco = GRM.Economy and GRM.Economy.Data and GRM.Economy.Data.factions and GRM.Economy.Data.factions[name]
            data.factions[name] = {
                budget = (GRM.FactionBudgetGet and GRM.FactionBudgetGet(name))
                    or (eco and eco.budget) or 0,
                taxRate = (eco and eco.taxRate) or 0.05,
                baseSalary = (eco and eco.baseSalary) or 0,
            }
        end
        if istable(Factions) then
            for name in pairs(Factions) do put(name) end
        end
        if GRM.Economy and GRM.Economy.Data and istable(GRM.Economy.Data.factions) then
            for name in pairs(GRM.Economy.Data.factions) do put(name) end
        end

        -- Игроки онлайн с балансами
        data.players = {}
        if GRM.GetAllBalances then
            local balances = GRM.GetAllBalances()
            for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                if IsValid(p) then
                    local sid64 = p:SteamID64()
                    data.players[#data.players + 1] = {
                        name = p:Nick(),
                        sid64 = sid64,
                        balance = balances and balances[sid64] and balances[sid64].balance or 0,
                    }
                end
            end
        end

        net.Start(NET_DATA)
            net.WriteTable(data)
        net.Send(ply)
    end)

    -- Обработчик действий (управление только через банкомат/компьютер банка)
    net.Receive(NET_ACTION, function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        ply:ChatPrint("[GRM Feco] Прямое изменение отключено. Управление финансами осуществляется через Банкомат и Компьютер Управления.")
    end)
end

-- ================================================================
-- КЛИЕНТСКАЯ ЧАСТЬ
-- ================================================================

if CLIENT then
    surface.CreateFont("GRMFeco_Title", {font = "Roboto", size = 18, weight = 800, extended = true})
    surface.CreateFont("GRMFeco_Normal", {font = "Roboto", size = 14, weight = 500, extended = true})
    surface.CreateFont("GRMFeco_Small", {font = "Roboto", size = 12, weight = 400, extended = true})
    surface.CreateFont("GRMFeco_Stat", {font = "Roboto", size = 22, weight = 800, extended = true})

    local CUI = {
        bg = Color(16, 20, 28, 252),
        sidebar = Color(12, 15, 22, 255),
        panel = Color(22, 28, 38, 245),
        accent = Color(65, 145, 235),
        green = Color(55, 185, 105),
        gold = Color(245, 195, 65),
        text = Color(240, 244, 250),
        dim = Color(155, 170, 190),
        border = Color(38, 48, 66, 200),
    }

    local function fmt(n) return GRM.Format and GRM.Format(n) or (tostring(n) .. " GRM") end
    local function dname(n)
        return (GRM.Factions and GRM.Factions.DisplayName and GRM.Factions.DisplayName(n)) or tostring(n)
    end

    local function openFecoAdmin()
        net.Start("GRM_FecoAdmin_Open")
        net.SendToServer()
    end

    net.Receive("GRM_FecoAdmin_Data", function()
        local data = net.ReadTable() or {}
        local frame = vgui.Create("DFrame")
        frame:SetTitle("")
        frame:SetSize(920, 660)
        frame:Center()
        frame:MakePopup()
        frame:ShowCloseButton(false)
        frame.Paint = function(_, w, h)
            draw.RoundedBox(8, 0, 0, w, h, CUI.bg)
            draw.RoundedBoxEx(8, 0, 0, w, 46, CUI.sidebar, true, true, false, false)
            draw.SimpleText("КАЗНА GRM  ·  обзор", "GRMFeco_Title", 16, 23, CUI.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText("правка — компьютер банка / /feco_admin", "GRMFeco_Small", w - 56, 23, CUI.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
        local bx = vgui.Create("DButton", frame)
        bx:SetPos(878, 10) bx:SetSize(30, 26) bx:SetText("")
        bx.Paint = function(s, w, h)
            draw.RoundedBox(4, 0, 0, w, h, s:IsHovered() and Color(196, 62, 62) or Color(36, 46, 62))
            draw.SimpleText("✕", "GRMFeco_Normal", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        bx.DoClick = function() frame:Close() end

        local sc = vgui.Create("DScrollPanel", frame)
        sc:Dock(FILL)
        sc:DockMargin(12, 54, 12, 12)

        local head = vgui.Create("DPanel", sc)
        head:Dock(TOP) head:SetTall(96) head:DockMargin(0, 0, 0, 10)
        head.Paint = function(_, w, h)
            draw.RoundedBox(6, 0, 0, w, h, CUI.panel)
            surface.SetDrawColor(CUI.border) surface.DrawOutlinedRect(0, 0, w, h)
            draw.SimpleText("ГОСУДАРСТВЕННЫЙ БЮДЖЕТ", "GRMFeco_Small", 16, 18, CUI.dim)
            draw.SimpleText(fmt(data.stateBudget or 0), "GRMFeco_Stat", 16, 50, CUI.gold)
        end

        local note = vgui.Create("DPanel", sc)
        note:Dock(TOP) note:SetTall(52) note:DockMargin(0, 0, 0, 10)
        note.Paint = function(_, w, h)
            draw.RoundedBox(6, 0, 0, w, h, CUI.panel)
            draw.SimpleText("Прямые кнопки «пополнить / снять» здесь отключены.", "GRMFeco_Normal", 14, 14, CUI.text)
            draw.SimpleText("Субсидии и казна фракций — компьютер управления банком. Зарплаты и налог — /feco_admin.", "GRMFeco_Small", 14, 34, CUI.dim)
        end

        local names = {}
        for n in pairs(data.factions or {}) do names[#names + 1] = n end
        table.sort(names, function(a, b) return string.lower(dname(a)) < string.lower(dname(b)) end)
        for _, name in ipairs(names) do
            local eco = data.factions[name]
            local row = vgui.Create("DPanel", sc)
            row:Dock(TOP) row:SetTall(64) row:DockMargin(0, 0, 0, 6)
            row.Paint = function(_, w, h)
                draw.RoundedBox(6, 0, 0, w, h, CUI.panel)
                surface.SetDrawColor(CUI.border) surface.DrawOutlinedRect(0, 0, w, h)
                draw.SimpleText(dname(name), "GRMFeco_Normal", 14, 16, CUI.text)
                draw.SimpleText("налог " .. math.floor((eco.taxRate or 0.05) * 100) .. "%   •   база ЗП " .. fmt(eco.baseSalary or 0), "GRMFeco_Small", 14, 40, CUI.dim)
                draw.SimpleText(fmt(eco.budget or 0), "GRMFeco_Title", w - 16, h / 2, CUI.gold, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end
        end

        for _, p in ipairs(data.players or {}) do
            local row = vgui.Create("DPanel", sc)
            row:Dock(TOP) row:SetTall(36) row:DockMargin(0, 0, 0, 3)
            row.Paint = function(_, w, h)
                draw.RoundedBox(5, 0, 0, w, h, CUI.panel)
                draw.SimpleText(tostring(p.name or "?"), "GRMFeco_Normal", 12, h / 2, CUI.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText(fmt(p.balance or 0), "GRMFeco_Normal", w - 12, h / 2, CUI.green, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
            end
        end
    end)

    -- Находка 177: вкладка «Экономика» в /factions больше НЕ добавляется
    -- этим модулем — её добавляет полная панель из sh_faction_fixes.lua
    -- (hook GRM_FactionsAdmin_BuildTabs → FactionsExt_EconomyTab). Раньше
    -- тут была вторая вкладка с тем же именем (обёртка с кнопками), из-за
    -- чего в меню появлялись ДВЕ вкладки «Экономика». Сам модуль (отдельное
    -- окно через grm_feco / grmmenu) остаётся рабочим.

    -- Консольная команда
    concommand.Add("grm_feco", function()
        if LocalPlayer():IsSuperAdmin() then
            net.Start("GRM_Eco_AdminOpen")
            net.SendToServer()
        else
            notification.AddLegacy("Только суперадмин", NOTIFY_ERROR, 3)
        end
    end)
end

print("[GRM Feco Admin] Модуль загружен (Код 113)")
