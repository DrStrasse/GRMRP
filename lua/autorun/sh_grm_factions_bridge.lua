--[[--------------------------------------------------------------------
    GRM Factions Bridge v1.1.0 (доработка Кодов 75/76/77)
    Вкладка «Доступы» в админ-меню /factions (суперадмин):
    четыре чекбокса на фракцию —
      ДОСКА   — лидер может вести набор через доску объявлений (Код 76);
      ЭФИР    — члены фракции могут запускать эфир у микрофона (Код 75);
      ОПОВЕЩ. — право на /alert и /alertall (Код 75);
      БИРЖА   — лидер публикует заказы биржи труда с эскроу бюджета (Код 77).
    Запись идёт в data/grm_board.json, data/grm_broadcast.json и
    data/grm_jobs.json (те же хранилища, что у чат-команд /board_allow,
    /bcast_allow, /alert_allow, /job_allow).
    Хук билда: GRM_FactionsAdmin_BuildTabs (вызывается из sh_factions).
    v1.1.0: +канал «jobs» (БИРЖА).
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

local NET_GET = "GRM_FAcc_Get"
local NET_SET = "GRM_FAcc_Set"
local NET_DATA = "GRM_FAcc_Data"

-- ============================================================
-- СЕРВЕР
-- ============================================================
if SERVER then
    util.AddNetworkString(NET_GET)
    util.AddNetworkString(NET_SET)
    util.AddNetworkString(NET_DATA)

    local function allFactions()
        local out = {}
        if istable(Factions) then
            for name in pairs(Factions) do out[#out + 1] = name end
        end
        table.sort(out, function(a, b) return a:lower() < b:lower() end)
        return out
    end

    local function accTable(kind)
        if kind == "board" then
            return (GRM.Board and GRM.Board.Cfg and GRM.Board.Cfg.allow) or {}
        elseif kind == "journ" then
            return (GRM.Broadcast and GRM.Broadcast.Cfg and GRM.Broadcast.Cfg.journalists) or {}
        elseif kind == "alert" then
            return (GRM.Broadcast and GRM.Broadcast.Cfg and GRM.Broadcast.Cfg.alerters) or {}
        elseif kind == "jobs" then
            return (GRM.Jobs and GRM.Jobs.Cfg and GRM.Jobs.Cfg.allow) or {}
        end
        return {}
    end

    net.Receive(NET_GET, function(_, ply)
        if not IsValid(ply) then return end
        -- Читать доступы могут суперадмин и любой лидер фракции.
        if not ply:IsSuperAdmin() then
            local isLeader = _G.FactionsAPI and _G.FactionsAPI.GetFactionOfLeader and _G.FactionsAPI.GetFactionOfLeader(ply)
            if not isLeader then return end
        end
        net.Start(NET_DATA)
            net.WriteTable(allFactions())
            net.WriteTable(accTable("board"))
            net.WriteTable(accTable("journ"))
            net.WriteTable(accTable("alert"))
            net.WriteTable(accTable("jobs"))
        net.Send(ply)
    end)

    net.Receive(NET_SET, function(_, ply)
        if not IsValid(ply) then return end
        local kind = net.ReadString()
        local fname = net.ReadString()
        local allow = net.ReadBool()
        if kind ~= "board" and kind ~= "journ" and kind ~= "alert" and kind ~= "jobs" then return end
        if not isstring(fname) or fname == "" then return end
        if not (istable(Factions) and istable(Factions[fname])) then return end
        -- Доступ: суперадмин или лидер СВОЕЙ фракции.
        if not ply:IsSuperAdmin() then
            local isLeader = _G.FactionsAPI and _G.FactionsAPI.IsLeader and _G.FactionsAPI.IsLeader(ply, fname)
            if not isLeader then return end
        end

        if kind == "board" then
            if not (GRM.Board and GRM.Board.Cfg and GRM.Board.SaveCfg) then return end
            GRM.Board.Cfg.allow[fname] = allow and true or nil
            if not allow then GRM.Board.Cfg.open[fname] = nil end
            GRM.Board.SaveCfg()
        elseif kind == "jobs" then
            if not (GRM.Jobs and GRM.Jobs.Cfg and GRM.Jobs.SaveCfg) then return end
            GRM.Jobs.Cfg.allow[fname] = allow and true or nil
            GRM.Jobs.SaveCfg("мост /factions: БИРЖА " .. fname)
        else
            if not (GRM.Broadcast and GRM.Broadcast.Cfg and GRM.Broadcast.SaveCfg) then return end
            local tbl = accTable(kind)
            tbl[fname] = allow and true or nil
            GRM.Broadcast.SaveCfg()
        end
        local labels = { board = "Доска набора", journ = "Эфир (радио)", alert = "Оповещение", jobs = "Биржа труда" }
        ply:PrintMessage(HUD_PRINTTALK, "[Доступы] " .. (labels[kind] or kind) .. " — «" .. fname .. "»: " .. (allow and "ВЫДАН" or "ОТОЗВАН"))

        -- Отправить обновлённые флаги обратно клиенту, чтобы переключатели
        -- в Unified UI отображали актуальное состояние сразу после клика.
        net.Start(NET_DATA)
            net.WriteTable(allFactions())
            net.WriteTable(accTable("board"))
            net.WriteTable(accTable("journ"))
            net.WriteTable(accTable("alert"))
            net.WriteTable(accTable("jobs"))
        net.Send(ply)
    end)

    print("[GRM Bridge] Доступы /factions (сервер) загружены")
end

-- ============================================================
-- КЛИЕНТ
-- ============================================================
if CLIENT then
    surface.CreateFont("GRMFAcc_Sub",    { font = "Roboto", size = 15, weight = 600, extended = true })
    surface.CreateFont("GRMFAcc_Normal", { font = "Roboto", size = 13, weight = 500, extended = true })

    local C = {
        bg    = Color(24, 28, 38, 240),
        panel = Color(32, 38, 50, 245),
        acc   = Color(70, 150, 240),
        green = Color(60, 190, 110),
        red   = Color(220, 75, 70),
        yellow= Color(230, 180, 60),
        teal  = Color(80, 200, 170),
        text  = Color(240, 245, 250),
        dim   = Color(170, 180, 195),
    }

    local curPanel = nil

    local function buildRows(container, factions, board, journ, alert, jobs)
        container:Clear()

        local head = vgui.Create("DPanel", container)
        head:Dock(TOP) head:SetTall(26) head:SetPaintBackground(false)
        local function hl(x, t, col)
            local l = vgui.Create("DLabel", head)
            l:SetPos(x, 2) l:SetSize(140, 22) l:SetFont("GRMFAcc_Sub") l:SetTextColor(col or C.dim)
            l:SetText(t)
        end
        hl(10, "Фракция", C.dim)
        hl(350, "Доска", C.teal)
        hl(500, "Эфир", C.acc)
        hl(650, "Оповещ.", C.red)
        hl(800, "Биржа", C.yellow)

        for _, name in ipairs(factions) do
            local row = vgui.Create("DPanel", container)
            row:Dock(TOP) row:SetTall(28) row:DockMargin(0, 0, 0, 2)
            row.Paint = function(_, pw, ph) draw.RoundedBox(4, 0, 0, pw, ph, C.panel) end

            local nl = vgui.Create("DLabel", row)
            nl:SetPos(10, 3) nl:SetSize(330, 22) nl:SetFont("GRMFAcc_Normal") nl:SetTextColor(C.text)
            nl:SetText(name)

            local function chk(x, get, kind, col)
                local c = vgui.Create("DCheckBoxLabel", row)
                c:SetPos(x, 3) c:SetSize(130, 22)
                c:SetText(get() and "выдан" or "нет")
                c:SetFont("GRMFAcc_Normal") c:SetTextColor(get() and col or C.dim)
                c:SetValue(get() and 1 or 0)
                c.OnChange = function(_, v)
                    net.Start(NET_SET)
                        net.WriteString(kind)
                        net.WriteString(name)
                        net.WriteBool(v)
                    net.SendToServer()
                    c:SetText(v and "выдан" or "нет")
                    c:SetTextColor(v and col or C.dim)
                end
            end
            chk(350, function() return board[name] == true end, "board", C.teal)
            chk(500, function() return journ[name] == true end, "journ", C.acc)
            chk(650, function() return alert[name] == true end, "alert", C.red)
            chk(800, function() return jobs[name] == true end, "jobs", C.yellow)
        end

        if #factions == 0 then
            local none = vgui.Create("DLabel", container)
            none:Dock(TOP) none:SetTall(30) none:SetFont("GRMFAcc_Normal") none:SetTextColor(C.dim)
            none:SetText("Фракций пока нет. Создайте во вкладке «Создать».")
        end
    end

    net.Receive(NET_DATA, function()
        local factions = net.ReadTable() or {}
        local board = net.ReadTable() or {}
        local journ = net.ReadTable() or {}
        local alert = net.ReadTable() or {}
        local jobs = net.ReadTable() or {}
        -- Кэш для Unified Factions UI (и любых других потребителей).
        GRM.FAcc = GRM.FAcc or {}
        GRM.FAcc.factions = factions
        GRM.FAcc.board = board
        GRM.FAcc.journ = journ
        GRM.FAcc.alert = alert
        GRM.FAcc.jobs = jobs
        if IsValid(curPanel) and IsValid(curPanel._rows) then
            buildRows(curPanel._rows, factions, board, journ, alert, jobs)
        end
        hook.Run("GRM_FAccDataUpdated")
    end)

    hook.Add("GRM_FactionsAdmin_BuildTabs", "GRM_Bridge_Tab", function(tabs)
        if not IsValid(tabs) then return end

        local panel = vgui.Create("DPanel")
        panel:SetPaintBackground(false)
        panel:DockPadding(8, 8, 8, 8)

        local info = vgui.Create("DLabel", panel)
        info:Dock(TOP) info:SetTall(44) info:SetFont("GRMFAcc_Normal") info:SetTextColor(C.dim)
        info:SetText("ДОСКА — лидер фракции может открывать набор через доску объявлений и видеть журнал вступивших. ЭФИР — члены фракции запускают эфир у микрофонных стоек. ОПОВЕЩЕНИЕ — право на команды /alert и /alertall. БИРЖА — лидер публикует заказы биржи труда (награда резервируется с бюджета фракции). Суперадмин может всё без галочек.")
        info:SetWrap(true) info:SetAutoStretchVertical(true)

        local rows = vgui.Create("DScrollPanel", panel)
        rows:Dock(FILL) rows:DockMargin(0, 6, 0, 6)
        panel._rows = rows

        local bRefresh = vgui.Create("DButton", panel)
        bRefresh:Dock(BOTTOM) bRefresh:SetTall(30)
        bRefresh:SetText("Обновить список")
        bRefresh:SetFont("GRMFAcc_Sub") bRefresh:SetTextColor(color_white)
        bRefresh.Paint = function(self, w, h)
            draw.RoundedBox(5, 0, 0, w, h, self:IsHovered() and Color(90, 170, 250) or C.acc)
        end
        bRefresh.DoClick = function()
            net.Start(NET_GET) net.SendToServer()
        end

        curPanel = panel
        tabs:AddSheet("Доступы", panel, "icon16/key.png")
        timer.Simple(0.2, function()
            if IsValid(panel) then net.Start(NET_GET) net.SendToServer() end
        end)
    end)

    print("[GRM Bridge] Доступы /factions (клиент) загружены")
end
