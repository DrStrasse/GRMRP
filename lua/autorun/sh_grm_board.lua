--[[--------------------------------------------------------------------
    GRM Recruit Board v1.0.0 (Код 76) — Доска набора во фракции
    Логика меню доски объявлений (энтити grm_board):
      - Игрок E → список фракций с ОТКРЫТЫМ набором → «Вступить» →
        автоматическое вступление через FactionsAPI.AddMember (та же
        структура данных, что у /fjoin — сохранение/формат не дублируется).
      - Лидер фракции с доступом видит кнопки «Открыть/Закрыть набор» и
        журнал вступивших (ник, RP-имя, SteamID, время — последние 20).
      - Суперадмин E → раздел «Доступ к доске»: чекбоксы по всем фракциям
        (доступ к доске набора), плюс чат-команды:
        /board_allow Фракция, /board_deny Фракция, /board_list.
      - Лидеру в онлайне при вступлении — уведомление+сообщение в чат.
    Данные: data/grm_board.json (доступ, флаги набора, журнал).
    Спавн доски: /board_add /board_remove (суперадмин) + /permadd.
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Board = GRM.Board or {}
local BD = GRM.Board

BD.Version      = "1.1.0" -- автоназначение отдела/должности при вступлении (Cfg.assign, заказ 18.07)
BD.DataFile     = "grm_board.json"
BD.JournalMax   = 20

local NET_OPEN   = "GRM_Board_Open"
local NET_JOIN   = "GRM_Board_Join"
local NET_TOGGLE = "GRM_Board_Toggle"
local NET_ADMIN  = "GRM_Board_Admin"
local NET_ASSIGN = "GRM_Board_Assign" -- v1.1.0: лидер/суперадмин задаёт отдел+должность автозачисления

-- ============================================================
-- СЕРВЕР
-- ============================================================
if SERVER then
    util.AddNetworkString(NET_OPEN)
    util.AddNetworkString(NET_JOIN)
    util.AddNetworkString(NET_TOGGLE)
    util.AddNetworkString(NET_ADMIN)
    util.AddNetworkString(NET_ASSIGN)

    local function jsonT(txt)
        local ok, t = pcall(util.JSONToTable, txt, false, true)
        return (ok and istable(t)) and t or nil
    end
    local function defaultCfg()
        return { allow = {}, open = {}, journal = {}, assign = {} }
    end
    local function loadCfg()
        BD.Cfg = BD.Cfg or defaultCfg()
        local t = jsonT(file.Read(BD.DataFile, "DATA") or "")
        if istable(t) then
            BD.Cfg.allow   = istable(t.allow)   and t.allow   or {}
            BD.Cfg.open    = istable(t.open)    and t.open    or {}
            BD.Cfg.journal = istable(t.journal) and t.journal or {}
            BD.Cfg.assign  = istable(t.assign)  and t.assign  or {} -- v1.1.0
        end
    end
    function BD.SaveCfg()
        local ok, txt = pcall(util.TableToJSON, BD.Cfg or defaultCfg(), true)
        if ok and txt then file.Write(BD.DataFile, txt) end
    end
    loadCfg()

    local function rpName(ply)
        local n = ply:GetNWString("GRM_RPName", "")
        return (n ~= "" and n) or ply:Nick()
    end

    -- фракция игрока (обе ключ-формы)
    local function factionOfPly(ply)
        if _G.FactionsAPI and _G.FactionsAPI.GetFactionOf then
            return _G.FactionsAPI.GetFactionOf(ply)
        end
        if istable(Factions) then
            local sid, s64 = ply:SteamID(), ply:SteamID64()
            for name, f in pairs(Factions) do
                if istable(f) and istable(f.Members) and (f.Members[sid] or f.Members[s64]) then return name end
            end
        end
        return nil
    end

    local function isLeader(ply, fname)
        if _G.FactionsAPI and _G.FactionsAPI.IsLeader then
            return _G.FactionsAPI.IsLeader(ply, fname)
        end
        return false
    end

    -- может ли игрок управлять набором этой фракции
    local function canManage(ply, fname)
        return BD.Cfg.allow[fname] == true and (ply:IsSuperAdmin() or isLeader(ply, fname))
    end

    local function leaderDisplay(fname)
        local sid = (_G.FactionsAPI and _G.FactionsAPI.GetLeader) and _G.FactionsAPI.GetLeader(fname) or nil
        if not sid and istable(Factions) and istable(Factions[fname]) then sid = Factions[fname].Leader end
        if not sid then return "—" end
        local p = (GRM.Identity and GRM.Identity.ResolveCharacter and GRM.Identity.ResolveCharacter(sid)) or player.GetBySteamID(sid) or player.GetBySteamID64(sid)
        if IsValid(p) then return rpName(p) end
        return tostring(sid)
    end

    function BD.OpenBoardMenu(ply, ent)
        local factions = {}
        if istable(Factions) then
            for name, f in pairs(Factions) do
                if istable(f) then
                    -- v1.1.0: списки отделов/должностей для настройки автозачисления
                    local depts = {}
                    for _, d in ipairs(istable(f.Departments) and f.Departments or {}) do
                        depts[#depts + 1] = tostring(d)
                    end
                    local roles = {}
                    for _, r in ipairs(istable(f.Roles) and f.Roles or {}) do
                        if r ~= f.LeaderRoleName then roles[#roles + 1] = tostring(r) end
                    end
                    local asg = istable(BD.Cfg.assign) and BD.Cfg.assign[name] or nil
                    factions[#factions + 1] = {
                        name = name,
                        allowed = BD.Cfg.allow[name] == true,
                        open = BD.Cfg.open[name] == true,
                        leader = leaderDisplay(name),
                        members = istable(f.Members) and table.Count(f.Members) or 0,
                        canManage = canManage(ply, name),
                        depts = depts,
                        roles = roles,
                        adept = (istable(asg) and tostring(asg.dept or "")) or "",
                        arole = (istable(asg) and tostring(asg.role or "")) or "",
                    }
                end
            end
        end
        table.sort(factions, function(a, b) return a.name:lower() < b.name:lower() end)

        local myJournal = {}
        for _, fr in ipairs(factions) do
            if fr.canManage then
                myJournal[fr.name] = BD.Cfg.journal[fr.name] or {}
            end
        end

        net.Start(NET_OPEN)
            net.WriteBool(ply:IsSuperAdmin())
            net.WriteString(factionOfPly(ply) or "")
            net.WriteTable(factions)
            net.WriteTable(myJournal)
        net.Send(ply)
    end

    -- вступление через доску -------------------------------------------
    net.Receive(NET_JOIN, function(_, ply)
        if not IsValid(ply) then return end
        local fname = net.ReadString()
        if not isstring(fname) or fname == "" then return end
        local f = istable(Factions) and Factions[fname] or nil
        if not istable(f) then
            if GRM.Notify then GRM.Notify(ply, "Фракция не найдена.", 255, 120, 90) end
            return
        end
        if BD.Cfg.allow[fname] ~= true or BD.Cfg.open[fname] ~= true then
            if GRM.Notify then GRM.Notify(ply, "Набор во фракцию «" .. fname .. "» сейчас закрыт.", 255, 180, 90) end
            return
        end
        local have = factionOfPly(ply)
        if have then
            if GRM.Notify then GRM.Notify(ply, "Вы уже состоите во фракции «" .. have .. "». Сначала выйдите: /fleave", 255, 180, 90) end
            return
        end
        if not (_G.FactionsAPI and _G.FactionsAPI.AddMember) then
            if GRM.Notify then GRM.Notify(ply, "Модуль фракций недоступен.", 255, 120, 90) end
            return
        end
        local ok, err = _G.FactionsAPI.AddMember(fname, ply)
        if not ok then
            if GRM.Notify then GRM.Notify(ply, tostring(err or "Не удалось вступить."), 255, 120, 90) end
            return
        end

        -- v1.1.0: автоназначение отдела/должности (Cfg.assign, задаётся лидером у доски)
        local asg = istable(BD.Cfg.assign) and BD.Cfg.assign[fname] or nil
        local asgParts = {}
        if istable(asg) then
            if isstring(asg.dept) and asg.dept ~= "" and _G.FactionsAPI.SetMemberDepartment then
                local okD = pcall(_G.FactionsAPI.SetMemberDepartment, fname, ply, asg.dept)
                if okD then asgParts[#asgParts + 1] = "отдел «" .. asg.dept .. "»" end
            end
            if isstring(asg.role) and asg.role ~= "" and _G.FactionsAPI.SetMemberRole then
                local okR = pcall(_G.FactionsAPI.SetMemberRole, fname, ply, asg.role)
                if okR then asgParts[#asgParts + 1] = "должность «" .. asg.role .. "»" end
            end
        end
        local asgText = (#asgParts > 0) and table.concat(asgParts, ", ") or nil

        -- журнал + сведения лидеру
        local rec = {
            nick = rpName(ply),
            rp = rpName(ply),
            sid = ply:SteamID(),
            time = os.time(),
            dept = istable(asg) and asg.dept or nil,
            role = istable(asg) and asg.role or nil,
        }
        BD.Cfg.journal[fname] = istable(BD.Cfg.journal[fname]) and BD.Cfg.journal[fname] or {}
        table.insert(BD.Cfg.journal[fname], 1, rec)
        while #BD.Cfg.journal[fname] > BD.JournalMax do table.remove(BD.Cfg.journal[fname]) end
        BD.SaveCfg()

        hook.Run("GRM_Board_Joined", ply, fname)
        if GRM.Notify then GRM.Notify(ply, "Вы вступили во фракцию «" .. fname .. "» через доску объявлений!", 100, 220, 100) end
        if asgText then
            ply:PrintMessage(HUD_PRINTTALK, "[Доска] Вы вступили во фракцию " .. fname .. ". Зачисление: " .. asgText .. ".")
        else
            ply:PrintMessage(HUD_PRINTTALK, "[Доска] Вы вступили во фракцию " .. fname .. ". Ранг по умолчанию: " .. tostring((_G.FactionsAPI.PrimeRole and _G.FactionsAPI.PrimeRole(fname)) or "—"))
        end

        local lsid = (_G.FactionsAPI.GetLeader and _G.FactionsAPI.GetLeader(fname)) or (istable(f) and f.Leader)
        local leader = lsid and player.GetBySteamID(lsid) or nil
        if not IsValid(leader) then
            for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                if p ~= ply and isLeader(p, fname) then leader = p break end
            end
        end
        if IsValid(leader) then
            local msg = "По доске объявлений вступил: " .. rec.rp .. " (Steam: " .. rec.nick .. ", " .. rec.sid .. ")"
                .. (asgText and (" — зачислен: " .. asgText) or "")
            leader:PrintMessage(HUD_PRINTTALK, "[Доска • " .. fname .. "] " .. msg)
            if GRM.Notify then GRM.Notify(leader, msg, 100, 200, 255) end
        end
    end)

    -- v1.1.0: лидер (с доступом)/суперадмин задаёт отдел/должность автозачисления
    net.Receive(NET_ASSIGN, function(_, ply)
        if not IsValid(ply) then return end
        local fname = net.ReadString()
        local dept  = string.Trim(net.ReadString() or "")
        local role  = string.Trim(net.ReadString() or "")
        if not isstring(fname) or fname == "" then return end
        if not canManage(ply, fname) then
            if GRM.Notify then GRM.Notify(ply, "Настраивать зачисление может лидер фракции с доступом к доске.", 255, 120, 90) end
            return
        end
        local f = istable(Factions) and Factions[fname] or nil
        if not istable(f) then return end
        if dept ~= "" and not (istable(f.Departments) and table.HasValue(f.Departments, dept)) then
            ply:PrintMessage(HUD_PRINTTALK, "[Доска] Отдел «" .. dept .. "» не существует во фракции «" .. fname .. "».")
            return
        end
        if role ~= "" and (not istable(f.Roles) or not table.HasValue(f.Roles, role) or role == f.LeaderRoleName) then
            ply:PrintMessage(HUD_PRINTTALK, "[Доска] Должность «" .. role .. "» недопустима (нет во фракции или это роль лидера).")
            return
        end
        BD.Cfg.assign = istable(BD.Cfg.assign) and BD.Cfg.assign or {}
        if dept == "" and role == "" then
            BD.Cfg.assign[fname] = nil
        else
            BD.Cfg.assign[fname] = { dept = (dept ~= "" and dept) or nil, role = (role ~= "" and role) or nil }
        end
        BD.SaveCfg()
        local desc = {}
        if dept ~= "" then desc[#desc + 1] = "отдел «" .. dept .. "»" end
        if role ~= "" then desc[#desc + 1] = "должность «" .. role .. "»" end
        ply:PrintMessage(HUD_PRINTTALK, "[Доска] Автозачисление «" .. fname .. "»: "
            .. ((#desc > 0) and table.concat(desc, ", ") or "по умолчанию (последний ранг, основной отдел)"))
    end)

    -- лидер открывает/закрывает набор ------------------------------------
    net.Receive(NET_TOGGLE, function(_, ply)
        if not IsValid(ply) then return end
        local fname = net.ReadString()
        local wantOpen = net.ReadBool()
        if not isstring(fname) or fname == "" then return end
        if not canManage(ply, fname) then
            if GRM.Notify then GRM.Notify(ply, "Управлять набором может лидер фракции с доступом (суперадмин выдаёт доступ у доски).", 255, 120, 90) end
            return
        end
        BD.Cfg.open[fname] = wantOpen and true or nil
        BD.SaveCfg()
        ply:PrintMessage(HUD_PRINTTALK, "[Доска] Набор во фракцию «" .. fname .. "»: " .. (wantOpen and "ОТКРЫТ" or "закрыт"))
    end)

    -- суперадмин управляет доступом ---------------------------------------
    net.Receive(NET_ADMIN, function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        local fname = net.ReadString()
        local allow = net.ReadBool()
        if not isstring(fname) or fname == "" then return end
        if not (istable(Factions) and istable(Factions[fname])) then return end
        BD.Cfg.allow[fname] = allow and true or nil
        if not allow then BD.Cfg.open[fname] = nil end
        BD.SaveCfg()
        ply:PrintMessage(HUD_PRINTTALK, "[Доска] Доступ к доске «" .. fname .. "»: " .. (allow and "ВЫДАН" or "ОТОЗВАН"))
    end)

    -- чат-команды (дубли, для удобства) ------------------------------------
    hook.Add("PlayerSay", "GRM_Board_Cmds", function(ply, text)
        local t = string.Trim(text or "")
        local low = string.lower(t)
        local function edit(name, allow)
            if not ply:IsSuperAdmin() then ply:PrintMessage(HUD_PRINTTALK, "[Доска] Только для суперадмина.") return true end
            local fname = string.Trim(name or "")
            if fname == "" or not (istable(Factions) and istable(Factions[fname])) then
                ply:PrintMessage(HUD_PRINTTALK, "[Доска] Укажите точное имя фракции (см. /factions).")
                return true
            end
            BD.Cfg.allow[fname] = allow and true or nil
            if not allow then BD.Cfg.open[fname] = nil end
            BD.SaveCfg()
            ply:PrintMessage(HUD_PRINTTALK, "[Доска] Доступ «" .. fname .. "»: " .. (allow and "выдан" or "отозван"))
            return true
        end
        if string.sub(low, 1, 13) == "/board_allow " and edit(string.sub(t, 14), true) then return "" end
        if string.sub(low, 1, 12) == "/board_deny " and edit(string.sub(t, 13), false) then return "" end
        if low == "/board_list" then
            local out = {}
            for k, v in pairs(BD.Cfg.allow) do
                if v then out[#out + 1] = k .. (BD.Cfg.open[k] and " (набор открыт)" or "") end
            end
            table.sort(out)
            ply:PrintMessage(HUD_PRINTTALK, "[Доска] Доступ: " .. ((#out > 0) and table.concat(out, ", ") or "(пусто)"))
            return ""
        end
        if low == "/board_add" then
            if not ply:IsSuperAdmin() then ply:PrintMessage(HUD_PRINTTALK, "[Доска] Только для суперадмина.") return "" end
            local tr = util.TraceLine({ start = ply:GetShootPos(), endpos = ply:GetShootPos() + ply:GetAimVector() * 320, filter = ply })
            if not tr.Hit then ply:PrintMessage(HUD_PRINTTALK, "[Доска] Прицельтесь в пол/стену рядом.") return "" end
            local ent = ents.Create("grm_board")
            if not IsValid(ent) then ply:PrintMessage(HUD_PRINTTALK, "[Доска] Энтити не зарегистрирована!") return "" end
            ent:SetPos(tr.HitPos + tr.HitNormal * 2)
            local ang = (ply:GetPos() - tr.HitPos):Angle()
            ent:SetAngles(Angle(0, ang.y, 0))
            ent:Spawn() ent:Activate()
            ply:PrintMessage(HUD_PRINTTALK, "[Доска] Установлена. Закрепите пермом: /permadd (в прицеле), снять: /board_remove и /permremove.")
            return ""
        end
        if low == "/board_remove" then
            if not ply:IsSuperAdmin() then return "" end
            local tr = util.TraceLine({ start = ply:GetShootPos(), endpos = ply:GetShootPos() + ply:GetAimVector() * 220, filter = ply })
            local ent = tr.Entity
            if not IsValid(ent) or ent:GetClass() ~= "grm_board" then
                ply:PrintMessage(HUD_PRINTTALK, "[Доска] В прицеле нет доски объявлений.")
                return ""
            end
            ent:Remove()
            ply:PrintMessage(HUD_PRINTTALK, "[Доска] Удалена.")
            return ""
        end
    end)

    print("[GRM Board] Сервер v" .. BD.Version .. " загружен")
end

-- ============================================================
-- КЛИЕНТ
-- ============================================================
if CLIENT then
    surface.CreateFont("GRMBoard_Title",  { font = "Roboto", size = 20, weight = 800, extended = true })
    surface.CreateFont("GRMBoard_Sub",    { font = "Roboto", size = 15, weight = 600, extended = true })
    surface.CreateFont("GRMBoard_Normal", { font = "Roboto", size = 13, weight = 500, extended = true })

    local C = {
        bg    = Color(20, 24, 32, 252),
        head  = Color(28, 34, 46, 255),
        panel = Color(32, 38, 50, 245),
        acc   = Color(70, 150, 240),
        green = Color(60, 190, 110),
        teal  = Color(80, 200, 170),
        red   = Color(220, 75, 70),
        yellow= Color(230, 180, 60),
        text  = Color(240, 245, 250),
        dim   = Color(160, 170, 185),
    }

    -- Кнопка — общая фабрика GRM.UI (§5.4): копии в четырёх модулях
    -- различались только шрифтом и создавали по два Color() на кадр.
    local function mkBtn(p, txt, col)
        return GRM.UI.Button(p, txt, "GRMBoard_Sub", col or C.acc)
    end

    net.Receive(NET_OPEN, function()
        local isSuperAdmin = net.ReadBool()
        local myFaction = net.ReadString()
        local factions = net.ReadTable() or {}
        local journal = net.ReadTable() or {}

        if IsValid(BD._frame) then BD._frame:Remove() end
        local f = vgui.Create("DFrame")
        BD._frame = f
        f:SetTitle("")
        f:SetSize(900, 660)
        f:Center()
        f:MakePopup()
        f:ShowCloseButton(false)
        f.Paint = function(_, pw, ph)
            draw.RoundedBox(8, 0, 0, pw, ph, C.bg)
            draw.RoundedBoxEx(8, 0, 0, pw, 44, C.head, true, true, false, false)
            draw.SimpleText("Доска объявлений — набор во фракции", "GRMBoard_Title", 14, 22, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        local x = vgui.Create("DButton", f)
        x:SetText("X") x:SetFont("GRMBoard_Title") x:SetTextColor(color_white)
        x:SetPos(856, 8) x:SetSize(32, 28)
        x.DoClick = function() f:Close() end
        x.Paint = function(self, pw, ph) draw.RoundedBox(4, 0, 0, pw, ph, self:IsHovered() and C.red or Color(45, 52, 68)) end

        local sc = vgui.Create("DScrollPanel", f)
        sc:Dock(FILL) sc:DockMargin(10, 52, 10, 10)

        local function block(h, title, accent)
            local b = vgui.Create("DPanel", sc)
            b:Dock(TOP) b:SetTall(h) b:DockMargin(0, 0, 0, 6)
            b.Paint = function(_, pw, ph)
                draw.RoundedBox(6, 0, 0, pw, ph, C.panel)
                draw.SimpleText(title, "GRMBoard_Sub", 10, 14, accent or C.teal, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            return b
        end

        -- набор (для всех)
        local open = {}
        for _, fr in ipairs(factions) do if fr.open then open[#open + 1] = fr end end
        local b1h = 30 + math.max(1, #open) * 56 + 8
        local b1 = block(b1h, "Открыт набор (вступление — автоматически):", C.teal)
        if #open == 0 then
            local none = vgui.Create("DLabel", b1)
            none:SetPos(14, 30) none:SetSize(840, 24) none:SetFont("GRMBoard_Normal") none:SetTextColor(C.dim)
            none:SetText("Сейчас ни одна фракция не ведёт набор. Загляните позже.")
        end
        for i, fr in ipairs(open) do
            local row = vgui.Create("DPanel", b1)
            row:SetPos(10, 28 + (i - 1) * 56) row:SetSize(860, 52)
            row.Paint = function(_, pw, ph)
                draw.RoundedBox(5, 0, 0, pw, ph, Color(26, 32, 42))
                draw.SimpleText(fr.name, "GRMBoard_Sub", 10, 14, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText("Лидер: " .. tostring(fr.leader) .. " • Состав: " .. tostring(fr.members), "GRMBoard_Normal", 10, 36, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            local bJoin = mkBtn(row, myFaction == "" and "Вступить" or "Вы во фракции", myFaction == "" and C.green or Color(70, 78, 92))
            bJoin:SetPos(700, 10) bJoin:SetSize(150, 32) bJoin:SetFont("GRMBoard_Normal")
            bJoin:SetEnabled(myFaction == "")
            bJoin.DoClick = function()
                net.Start(NET_JOIN)
                    net.WriteString(fr.name)
                net.SendToServer()
                timer.Simple(0.4, function() if IsValid(f) then f:Close() end end)
            end
        end

        -- управление лидера
        local managed = {}
        for _, fr in ipairs(factions) do if fr.canManage then managed[#managed + 1] = fr end end
        if #managed > 0 then
            local b2h = 30 + #managed * 56 + 8
            local b2 = block(b2h, "Управление набором (вы — лидер с доступом):", C.yellow)
        -- v1.1.0: окно автозачисления (отдел + должность для вступающих)
        local function openAssignFrame(fr2)
            local af = vgui.Create("DFrame")
            af:SetTitle("") af:SetSize(440, 240) af:Center() af:MakePopup() af:ShowCloseButton(true)
            af.Paint = function(_, pw, ph)
                draw.RoundedBox(8, 0, 0, pw, ph, C.bg)
                draw.RoundedBoxEx(8, 0, 0, pw, 38, C.head, true, true, false, false)
                draw.SimpleText("Автозачисление — «" .. fr2.name .. "»", "GRMBoard_Sub", 12, 19, C.yellow, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end

            local info = vgui.Create("DLabel", af)
            info:SetPos(14, 44) info:SetSize(412, 18)
            info:SetFont("GRMBoard_Normal") info:SetTextColor(C.dim)
            info:SetText("Вступивший через доску попадёт сразу сюда (лидеру придёт отчёт):")

            local dl = vgui.Create("DLabel", af)
            dl:SetPos(14, 70) dl:SetSize(120, 22) dl:SetFont("GRMBoard_Normal") dl:SetTextColor(C.text)
            dl:SetText("Отдел:")
            local cbDept = vgui.Create("DComboBox", af)
            cbDept:SetPos(140, 70) cbDept:SetSize(286, 24)
            cbDept:SetValue(fr2.adept ~= "" and fr2.adept or "— по умолчанию —")
            cbDept:AddChoice("— по умолчанию —", "", fr2.adept == "")
            for _, d in ipairs(fr2.depts or {}) do cbDept:AddChoice(tostring(d), tostring(d), fr2.adept == d) end

            local rl = vgui.Create("DLabel", af)
            rl:SetPos(14, 102) rl:SetSize(120, 22) rl:SetFont("GRMBoard_Normal") rl:SetTextColor(C.text)
            rl:SetText("Должность:")
            local cbRole = vgui.Create("DComboBox", af)
            cbRole:SetPos(140, 102) cbRole:SetSize(286, 24)
            cbRole:SetValue(fr2.arole ~= "" and fr2.arole or "— по умолчанию —")
            cbRole:AddChoice("— по умолчанию —", "", fr2.arole == "")
            for _, r in ipairs(fr2.roles or {}) do cbRole:AddChoice(tostring(r), tostring(r), fr2.arole == r) end

            local save = mkBtn(af, "Сохранить зачисление", C.green)
            save:SetPos(14, 140) save:SetSize(412, 34) save:SetFont("GRMBoard_Normal")
            save.DoClick = function()
                local _, dv = cbDept:GetSelected()
                local _, rv = cbRole:GetSelected()
                net.Start(NET_ASSIGN)
                    net.WriteString(fr2.name)
                    net.WriteString(tostring(dv or ""))
                    net.WriteString(tostring(rv or ""))
                net.SendToServer()
                fr2.adept, fr2.arole = tostring(dv or ""), tostring(rv or "") -- локальное отражение до следующего открытия доски
                af:Close()
            end

            local rst = mkBtn(af, "Сбросить (по умолчанию)", Color(110, 118, 132))
            rst:SetPos(14, 182) rst:SetSize(412, 26) rst:SetFont("GRMBoard_Normal")
            rst.DoClick = function()
                net.Start(NET_ASSIGN)
                    net.WriteString(fr2.name)
                    net.WriteString("")
                    net.WriteString("")
                net.SendToServer()
                fr2.adept, fr2.arole = "", ""
                af:Close()
            end
        end
        for i, fr in ipairs(managed) do
                local row = vgui.Create("DPanel", b2)
                row:SetPos(10, 28 + (i - 1) * 56) row:SetSize(860, 52)
                row._fr = fr
                row.Paint = function(self, pw, ph)
                    local fr2 = self._fr
                    draw.RoundedBox(5, 0, 0, pw, ph, Color(26, 32, 42))
                    draw.SimpleText(fr2.name, "GRMBoard_Sub", 10, 14, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    local ast = ""
                    if (fr2.arole or "") ~= "" or (fr2.adept or "") ~= "" then
                        ast = " • зачисление: " .. ((fr2.adept or "") ~= "" and fr2.adept or "основной отдел")
                            .. " / " .. ((fr2.arole or "") ~= "" and fr2.arole or "по умолчанию")
                    end
                    draw.SimpleText((fr2.open and "Набор: ОТКРЫТ" or "Набор: закрыт") .. ast, "GRMBoard_Normal", 10, 36, fr2.open and C.green or C.red, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end
                local bAsg = mkBtn(row, "Отдел/должность", C.acc)
                bAsg:SetPos(390, 10) bAsg:SetSize(140, 32) bAsg:SetFont("GRMBoard_Normal")
                bAsg.DoClick = function() openAssignFrame(fr) end
                local bTgl = mkBtn(row, fr.open and "Закрыть набор" or "Открыть набор", fr.open and C.red or C.green)
                bTgl:SetPos(540, 10) bTgl:SetSize(150, 32) bTgl:SetFont("GRMBoard_Normal")
                bTgl.DoClick = function()
                    net.Start(NET_TOGGLE)
                        net.WriteString(fr.name)
                        net.WriteBool(not fr.open)
                    net.SendToServer()
                    fr.open = not fr.open
                end
                local entries = journal[fr.name] or {}
                local bJrn = mkBtn(row, "Журнал (" .. #entries .. ")", C.acc)
                bJrn:SetPos(700, 10) bJrn:SetSize(150, 32) bJrn:SetFont("GRMBoard_Normal")
                bJrn.DoClick = function()
                    local jf = vgui.Create("DFrame")
                    jf:SetTitle("") jf:SetSize(640, 460) jf:Center() jf:MakePopup() jf:ShowCloseButton(false)
                    jf.Paint = function(_, pw, ph)
                        draw.RoundedBox(8, 0, 0, pw, ph, C.bg)
                        draw.RoundedBoxEx(8, 0, 0, pw, 40, C.head, true, true, false, false)
                        draw.SimpleText("Журнал вступивших — «" .. fr.name .. "»", "GRMBoard_Title", 14, 20, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                    end
                    local jx = vgui.Create("DButton", jf)
                    jx:SetText("X") jx:SetFont("GRMBoard_Title") jx:SetTextColor(color_white)
                    jx:SetPos(596, 6) jx:SetSize(32, 26)
                    jx.DoClick = function() jf:Close() end
                    jx.Paint = function(self, pw, ph) draw.RoundedBox(4, 0, 0, pw, ph, self:IsHovered() and C.red or Color(45, 52, 68)) end
                    local jsc = vgui.Create("DScrollPanel", jf)
                    jsc:Dock(FILL) jsc:DockMargin(10, 48, 10, 10)
                    if #entries == 0 then
                        local nl = vgui.Create("DLabel", jsc)
                        nl:Dock(TOP) nl:SetTall(30) nl:SetFont("GRMBoard_Normal") nl:SetTextColor(C.dim)
                        nl:SetText("Пока никто не вступал через доску.")
                    end
                    for _, e in ipairs(entries) do
                        local r = vgui.Create("DPanel", jsc)
                        r:Dock(TOP) r:SetTall(52) r:DockMargin(0, 0, 0, 4)
                        local rp, nick, sid, when = tostring(e.rp or e.nick or "?"), tostring(e.nick or "?"), tostring(e.sid or "?"), tonumber(e.time) or 0
                        local asgLine = ""
                        if (e.dept or "") ~= "" or (e.role or "") ~= "" then
                            asgLine = "  •  зачислен: " .. tostring(e.dept or "осн. отдел") .. " / " .. tostring(e.role or "по умолч.")
                        end
                        r.Paint = function(_, pw, ph)
                            draw.RoundedBox(5, 0, 0, pw, ph, C.panel)
                            draw.SimpleText(rp .. "  (Steam: " .. nick .. ")", "GRMBoard_Sub", 10, 14, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                            draw.SimpleText(sid .. "  •  " .. (when > 0 and os.date("%d.%m.%Y %H:%M", when) or "—") .. asgLine, "GRMBoard_Normal", 10, 36, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                        end
                    end
                end
            end
        end

        -- доступ (суперадмин)
        if isSuperAdmin then
            local b3h = 30 + #factions * 30 + 8
            local b3 = block(b3h, "Доступ к доске набора (суперадмин):", C.red)
            for i, fr in ipairs(factions) do
                local chk = vgui.Create("DCheckBoxLabel", b3)
                chk:SetPos(14, 28 + (i - 1) * 30) chk:SetSize(700, 26)
                chk:SetText(fr.name .. " — «" .. tostring(fr.leader) .. "»")
                chk:SetFont("GRMBoard_Normal") chk:SetTextColor(C.text)
                chk:SetValue(fr.allowed and 1 or 0)
                chk.OnChange = function(_, v)
                    net.Start(NET_ADMIN)
                        net.WriteString(fr.name)
                        net.WriteBool(v)
                    net.SendToServer()
                end
            end
        end
    end)

    print("[GRM Board] Клиент v" .. BD.Version .. " загружен")
end

-- Вечер-18: команда разбирается внутри парсера модуля (не литералом в
-- хуке) — регистрируем её множество в едином внешнем словаре библиотеки,
-- иначе на режиме она стала бы «неизвестной» до цепочки.
if GRM and GRM.Chat and GRM.Chat.RegisterExternalCommands then
    GRM.Chat.RegisterExternalCommands({ "/board_add", "/board_list", "/board_remove" })
end
