-- GRM Tickets: собственная система обращений игрок -> администрация
if SERVER then AddCSLuaFile() end
GRM = GRM or {}
GRM.Tickets = GRM.Tickets or {}
local T = GRM.Tickets
T.File = "grm_tickets.json"
T.NextID = T.NextID or 0
T.Active = T.Active or {}
T.History = T.History or {}
T.Zones = T.Zones or {}

local function rpName(ply)
    if not IsValid(ply) then return "Неизвестно" end
    local n = ply:GetNWString("GRM_RPName", "")
    return n ~= "" and n or ply:Nick()
end

if SERVER then
    local NET_CREATE, NET_ADMIN, NET_ACTION, NET_REPLY, NET_ADMIN_REQ, NET_ZONE = "GRM_Ticket_Create", "GRM_Ticket_AdminData", "GRM_Ticket_AdminAction", "GRM_Ticket_Reply", "GRM_Ticket_AdminRequest", "GRM_Ticket_ZoneAction"
    for _, n in ipairs({ NET_CREATE, NET_ADMIN, NET_ACTION, NET_REPLY, NET_ADMIN_REQ, NET_ZONE }) do util.AddNetworkString(n) end
    util.AddNetworkString("GRM_Ticket_Rate")
    util.AddNetworkString("GRM_Ticket_PlayerData")
    util.AddNetworkString("GRM_Ticket_PlayerReply")

    local function save()
        file.Write(T.File, util.TableToJSON({ nextID = T.NextID, active = T.Active, history = T.History, zones = T.Zones }, true))
    end
    local function load()
        if not file.Exists(T.File, "DATA") then return end
        local ok, d = pcall(util.JSONToTable, file.Read(T.File, "DATA") or "")
        if ok and istable(d) then T.NextID = tonumber(d.nextID) or 0; T.Active = istable(d.active) and d.active or {}; T.History = istable(d.history) and d.history or {}; T.Zones = istable(d.zones) and d.zones or {} end
    end
    load()

    local function notifyAdmins(text)
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(p) and p:IsAdmin() then p:ChatPrint("[GRM Тикеты] " .. text) end
        end
    end
    local function sendAdmin(ply)
        if not IsValid(ply) or not ply:IsAdmin() then return end
        local list = {}
        for _, ticket in pairs(T.Active) do list[#list + 1] = ticket end
        table.sort(list, function(a, b) return (a.id or 0) > (b.id or 0) end)
        net.Start(NET_ADMIN) net.WriteTable({ tickets = list, zones = T.Zones, history = T.History }) net.Send(ply)
    end
    local sendPlayerTicket
    local function create(ply, text)
        text = string.sub(string.Trim(tostring(text or "")), 1, 500)
        if text == "" then return false, "Опишите проблему" end
        if IsValid(ply) then
            for _, t in pairs(T.Active) do if t.account == ply:SteamID64() then return false, "У вас уже есть открытый тикет" end end
        end
        T.NextID = T.NextID + 1
        local ticket = { id = T.NextID, account = IsValid(ply) and ply:SteamID64() or "", name = rpName(ply), text = text, status = "open", admin = "", created = os.time(), messages = {} }
        T.Active[ticket.id] = ticket
        notifyAdmins("Новый тикет #" .. ticket.id .. " от " .. ticket.name .. ".")
        if IsValid(ply) then ply:ChatPrint("[GRM Тикеты] Тикет #" .. ticket.id .. " создан. Ожидайте ответа администрации."); sendPlayerTicket(ticket) end
        save(); return true, ticket.id
    end
    local function findPlayer(ticket)
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do if IsValid(p) and p:SteamID64() == ticket.account then return p end end
    end
    sendPlayerTicket = function(ticket)
        local owner = findPlayer(ticket)
        if IsValid(owner) then net.Start("GRM_Ticket_PlayerData") net.WriteTable(ticket) net.Send(owner) end
    end

    net.Receive(NET_ADMIN_REQ, function(_, ply)
        if IsValid(ply) and ply:IsAdmin() then sendAdmin(ply) end
    end)
    net.Receive(NET_ZONE, function(_, ply)
        if not IsValid(ply) or not ply:IsAdmin() then return end
        local action = net.ReadString()
        if action == "add" then
            T.Zones[#T.Zones + 1] = { id = #T.Zones + 1, name = "Админ-зона " .. (#T.Zones + 1), pos = { x = ply:GetPos().x, y = ply:GetPos().y, z = ply:GetPos().z }, createdBy = rpName(ply) }
            save(); sendAdmin(ply)
        elseif action == "delete" then
            local id = net.ReadUInt(16)
            for i = #T.Zones, 1, -1 do if T.Zones[i].id == id then table.remove(T.Zones, i) end end
            save(); sendAdmin(ply)
        elseif action == "teleport_zone" then
            local ticket = T.Active[net.ReadUInt(24)]
            local zone = T.Zones[net.ReadUInt(16)]
            local owner = ticket and findPlayer(ticket)
            if IsValid(owner) and zone then owner:SetPos(Vector(zone.pos.x, zone.pos.y, zone.pos.z)); owner:ChatPrint("[GRM Тикеты] Вы телепортированы в админ-зону.") end
        end
    end)
    net.Receive("GRM_Ticket_Rate", function(_, ply)
        local id, stars = net.ReadUInt(24), math.Clamp(net.ReadUInt(3), 1, 5)
        local ticket = nil
        for _, item in ipairs(T.History) do if item.id == id then ticket = item break end end
        if ticket and ticket.account == ply:SteamID64() then ticket.rating = stars; save(); ply:ChatPrint("[GRM Тикеты] Оценка сохранена: " .. stars .. "/5.") end
    end)
    net.Receive(NET_CREATE, function(_, ply)
        local ok, result = create(ply, net.ReadString())
        if not ok and IsValid(ply) then ply:ChatPrint("[GRM Тикеты] " .. result) end
    end)
    net.Receive(NET_ACTION, function(_, ply)
        if not IsValid(ply) or not ply:IsAdmin() then return end
        local action, id = net.ReadString(), net.ReadUInt(24)
        local ticket = T.Active[id]
        if not ticket then return end
        if action == "tp_to_player" then local owner = findPlayer(ticket); if IsValid(owner) then ply:SetPos(owner:GetPos()) end
        elseif action == "bring_player" then local owner = findPlayer(ticket); if IsValid(owner) then owner:SetPos(ply:GetPos()); owner:ChatPrint("[GRM Тикеты] Администратор вызвал вас к себе.") end
        elseif action == "claim" then ticket.status = "claimed"; ticket.admin = rpName(ply); notifyAdmins("Тикет #" .. id .. " взял " .. rpName(ply) .. ".")
        elseif action == "close" then ticket.status = "closed"; ticket.closedBy = rpName(ply); ticket.closed = os.time(); T.History[#T.History + 1] = ticket; T.Active[id] = nil; local owner = findPlayer(ticket); if IsValid(owner) then owner:ChatPrint("[GRM Тикеты] Тикет #" .. id .. " закрыт. Оцените работу: /ticket_rate " .. id); sendPlayerTicket(ticket) end
        end
        save(); sendAdmin(ply)
    end)
    net.Receive("GRM_Ticket_PlayerReply", function(_, ply)
        local id = net.ReadUInt(24)
        local text = string.sub(string.Trim(net.ReadString() or ""), 1, 500)
        local ticket = T.Active[id]
        if not IsValid(ply) or not ticket or ticket.account ~= ply:SteamID64() or text == "" then return end
        ticket.messages[#ticket.messages + 1] = { from = rpName(ply), text = text, time = os.time() }
        notifyAdmins("Новое сообщение в тикете #" .. id .. ".")
        save(); sendPlayerTicket(ticket)
    end)
    net.Receive(NET_REPLY, function(_, ply)
        if not IsValid(ply) or not ply:IsAdmin() then return end
        local id, text = net.ReadUInt(24), string.sub(string.Trim(net.ReadString() or ""), 1, 500)
        local ticket = T.Active[id] if not ticket or text == "" then return end
        ticket.messages[#ticket.messages + 1] = { from = rpName(ply), text = text, time = os.time() }
        local owner = findPlayer(ticket)
        if IsValid(owner) then owner:ChatPrint("[Тикет #" .. id .. "] " .. rpName(ply) .. ": " .. text); sendPlayerTicket(ticket) end
        ticket.status = "claimed"; ticket.admin = rpName(ply); save(); sendAdmin(ply)
    end)
    hook.Add("PlayerInitialSpawn", "GRM_Tickets_RestorePlayerWindow", function(ply)
        timer.Simple(2, function()
            if not IsValid(ply) then return end
            for _, ticket in pairs(T.Active) do if ticket.account == ply:SteamID64() then sendPlayerTicket(ticket) break end end
        end)
    end)
    concommand.Add("grm_tickets", function(ply) if IsValid(ply) and ply:IsAdmin() then sendAdmin(ply) end end)
    concommand.Add("grm_ticket", function(ply) if IsValid(ply) then ply:ChatPrint("Использование: /ticket текст обращения") end end)
    hook.Add("PlayerSay", "GRM_Tickets_Chat", function(ply, text)
        local msg = string.Trim(text or ""); local low = string.lower(msg)
        if low:sub(1, 13) == "/ticket_rate " then
            local args = string.Explode(" ", msg:sub(14)); local id, stars = tonumber(args[1] or 0), math.Clamp(tonumber(args[2] or 0) or 0, 1, 5)
            if id and stars > 0 then local ticket; for _, item in ipairs(T.History) do if item.id == id then ticket = item break end end; if ticket and ticket.account == ply:SteamID64() then ticket.rating = stars; save(); ply:ChatPrint("[GRM Тикеты] Оценка сохранена: " .. stars .. "/5.") end end
            return ""
        end
        if low:sub(1, 8) == "/ticket " or low:sub(1, 8) == "!ticket " then create(ply, msg:sub(9)); return "" end
        if low == "/tickets" or low == "!tickets" then if ply:IsAdmin() then sendAdmin(ply) end return "" end
    end)
else
    local C = { bg = Color(10, 16, 24, 250), head = Color(20, 30, 44), card = Color(26, 39, 56), blue = Color(70, 155, 245), green = Color(65, 195, 125), red = Color(215, 75, 85), text = Color(235, 242, 250), dim = Color(160, 175, 195) }
    surface.CreateFont("GRMTicketTitle", { font = "Roboto", size = 20, weight = 900, extended = true })
    surface.CreateFont("GRMTicketBody", { font = "Roboto", size = 13, weight = 600, extended = true })
    local function button(parent, text, col)
        local b = vgui.Create("DButton", parent) b:SetText(text) b:SetFont("GRMTicketBody") b:SetTextColor(color_white)
        b.Paint = function(self, w, h) local c = self:IsHovered() and Color(math.min(col.r + 18, 255), math.min(col.g + 18, 255), math.min(col.b + 18, 255)) or col; draw.RoundedBox(6, 0, 0, w, h, c) end return b
    end
    local function openRating(id)
        local f = vgui.Create("DFrame") f.GRM_BanAllowed=true f:SetSize(420, 150) f:Center() f:MakePopup() f:SetTitle("GRM — Оценка тикета #" .. tostring(id))
        local l = vgui.Create("DLabel", f) l:SetPos(16, 32) l:SetSize(388, 24) l:SetText("Оцените работу администратора:") l:SetTextColor(C.dim)
        for i = 1, 5 do local b = button(f, string.rep("★", i), Color(200, 155, 45)) b:SetPos(16 + (i - 1) * 77, 70) b:SetSize(68, 36) b.DoClick = function() net.Start("GRM_Ticket_Rate") net.WriteUInt(tonumber(id) or 0, 24) net.WriteUInt(i, 3) net.SendToServer() f:Close() end end
    end
    local playerFrame
    local currentPlayerTicket
    local function showPlayerTicket(ticket)
        currentPlayerTicket = ticket
        if IsValid(playerFrame) then playerFrame:Remove() end
        playerFrame = vgui.Create("DFrame") playerFrame.GRM_BanAllowed=true playerFrame:SetSize(430, 280) playerFrame:SetPos(ScrW() - 450, ScrH() - 310) playerFrame:SetTitle("GRM — Тикет #" .. tostring(ticket.id)) playerFrame:MakePopup()
        local info = vgui.Create("DLabel", playerFrame) info:SetPos(12, 32) info:SetSize(405, 45) info:SetText("Статус: " .. tostring(ticket.status) .. "\nВаше обращение: " .. tostring(ticket.text)) info:SetTextColor(C.dim) info:SetWrap(true)
        local list = vgui.Create("DScrollPanel", playerFrame) list:SetPos(12, 82) list:SetSize(405, 105)
        for _, msg in ipairs(ticket.messages or {}) do local line = vgui.Create("DLabel", list) line:Dock(TOP) line:SetTall(24) line:SetText(tostring(msg.from) .. ": " .. tostring(msg.text)) line:SetTextColor(C.text) end
        if ticket.status ~= "closed" then
            local entry = vgui.Create("DTextEntry", playerFrame) entry:SetPos(12, 195) entry:SetSize(300, 30) entry:SetPlaceholderText("Сообщение администрации")
            local send = button(playerFrame, "Отправить", C.blue) send:SetPos(320, 195) send:SetSize(97, 30) send.DoClick = function() net.Start("GRM_Ticket_PlayerReply") net.WriteUInt(ticket.id, 24) net.WriteString(entry:GetValue()) net.SendToServer() entry:SetText("") end
        end
    end
    net.Receive("GRM_Ticket_PlayerData", function() showPlayerTicket(net.ReadTable() or {}) end)

    local function openCreate()
        local f = vgui.Create("DFrame")
        f.GRM_BanAllowed = true
        if GRM.UI and GRM.UI.Track then GRM.UI.Track("ticket_create", f) end
        f:SetSize(680, 360) f:Center() f:MakePopup() f:SetTitle("") f:ShowCloseButton(false)
        f.Paint = function(_, w, h) draw.RoundedBox(10, 0, 0, w, h, C.bg); draw.RoundedBoxEx(10, 0, 0, w, 58, C.head, true, true, false, false); draw.SimpleText("GRM  /  ОБРАЩЕНИЕ", "GRMTicketBody", 18, 17, C.blue, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER); draw.SimpleText("Новый тикет", "GRMTicketTitle", 18, 40, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
        local close = button(f, "×", C.red) close:SetPos(638, 14) close:SetSize(28, 28) close.DoClick = function() f:Close() end
        local hint = vgui.Create("DLabel", f) hint:SetPos(18, 70) hint:SetSize(640, 35) hint:SetText("Опишите проблему. Администрация увидит игровое имя вашего персонажа.") hint:SetTextColor(C.dim) hint:SetWrap(true)
        local entry = vgui.Create("DTextEntry", f) entry:SetPos(18, 112) entry:SetSize(644, 140) entry:SetMultiline(true) entry:SetPlaceholderText("Что произошло?")
        local send = button(f, "ОТПРАВИТЬ ТИКЕТ", C.green) send:SetPos(18, 278) send:SetSize(644, 40)
        send.DoClick = function() net.Start("GRM_Ticket_Create") net.WriteString(entry:GetValue()) net.SendToServer() f:Close() end
    end
    local function openAdmin(payload)
        local list = istable(payload) and (payload.tickets or payload) or {}
        local zones = istable(payload) and payload.zones or {}
        local history = istable(payload) and payload.history or {}
        local f = vgui.Create("DFrame")
        f.GRM_BanAllowed = true
        if GRM.UI and GRM.UI.Track then GRM.UI.Track("ticket_admin", f) end
        f:SetSize(1080, 760) f:Center() f:MakePopup() f:SetTitle("") f:ShowCloseButton(false)
        f.Paint = function(_, w, h) draw.RoundedBox(10, 0, 0, w, h, C.bg); draw.RoundedBoxEx(10, 0, 0, w, 58, C.head, true, true, false, false); draw.SimpleText("GRM  /  ЦЕНТР ТИКЕТОВ", "GRMTicketBody", 18, 17, C.blue, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER); draw.SimpleText("Обращения игроков", "GRMTicketTitle", 18, 40, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
        local closeFrame = button(f, "×", C.red) closeFrame:SetPos(1038, 14) closeFrame:SetSize(28, 28) closeFrame.DoClick = function() f:Close() end
        local toolbar = vgui.Create("DPanel", f) toolbar:SetPos(10, 66) toolbar:SetSize(1060, 42) toolbar:SetPaintBackground(false) toolbar:SetZPos(10)
        local addZone = button(toolbar, "+ Админ-зона здесь", C.green) addZone:SetPos(8, 5) addZone:SetSize(230, 32) addZone.DoClick = function() net.Start("GRM_Ticket_ZoneAction") net.WriteString("add") net.SendToServer() end
        local zoneInfo = vgui.Create("DLabel", toolbar) zoneInfo:SetPos(250, 11) zoneInfo:SetSize(790, 22) zoneInfo:SetText("Админ-зон: " .. tostring(#(zones or {})) .. " • история: " .. tostring(#(history or {}))) zoneInfo:SetTextColor(C.dim)
        local sc = vgui.Create("DScrollPanel", f) sc:SetPos(10, 116) sc:SetSize(1060, 624) sc:SetZPos(1)
        for _, t in ipairs(list or {}) do
            local p = vgui.Create("DPanel", sc) p:Dock(TOP) p:SetTall(160) p:DockMargin(0, 0, 0, 8) p.Paint = function(_, w, h) draw.RoundedBox(7, 0, 0, w, h, C.card) end
            local l = vgui.Create("DLabel", p) l:SetPos(14, 10) l:SetSize(620, 24) l:SetFont("GRMTicketTitle") l:SetTextColor(C.text) l:SetText("#" .. t.id .. "  •  " .. tostring(t.name) .. "  •  " .. tostring(t.status))
            local body = vgui.Create("DLabel", p) body:SetPos(14, 42) body:SetSize(620, 42) local transcript = tostring(t.text); for _, msg in ipairs(t.messages or {}) do transcript = transcript .. "\n" .. tostring(msg.from) .. ": " .. tostring(msg.text) end; body:SetText(transcript) body:SetTextColor(C.dim) body:SetWrap(true)
            local reply = vgui.Create("DTextEntry", p) reply:SetPos(14, 92) reply:SetSize(500, 30) reply:SetPlaceholderText("Ответ игроку")
            local rb = button(p, "Ответить", C.blue) rb:SetPos(524, 92) rb:SetSize(100, 30) rb.DoClick = function() net.Start("GRM_Ticket_Reply") net.WriteUInt(t.id, 24) net.WriteString(reply:GetValue()) net.SendToServer() end
            local claim = button(p, "Взять", C.green) claim:SetPos(650, 22) claim:SetSize(100, 30) claim.DoClick = function() net.Start("GRM_Ticket_AdminAction") net.WriteString("claim") net.WriteUInt(t.id, 24) net.SendToServer() end
            local close = button(p, "Закрыть", C.red) close:SetPos(760, 22) close:SetSize(100, 30) close.DoClick = function() net.Start("GRM_Ticket_AdminAction") net.WriteString("close") net.WriteUInt(t.id, 24) net.SendToServer() end
            local tp = button(p, "К игроку", C.blue) tp:SetPos(650, 58) tp:SetSize(100, 30) tp.DoClick = function() net.Start("GRM_Ticket_AdminAction") net.WriteString("tp_to_player") net.WriteUInt(t.id, 24) net.SendToServer() end
            local bring = button(p, "К админу", C.orange or Color(220, 150, 70)) bring:SetPos(760, 58) bring:SetSize(100, 30) bring.DoClick = function() net.Start("GRM_Ticket_AdminAction") net.WriteString("bring_player") net.WriteUInt(t.id, 24) net.SendToServer() end
            local zone = button(p, "В зону", C.green) zone:SetPos(650, 92) zone:SetSize(210, 30) zone.DoClick = function()
                local menu = DermaMenu()
                for _, z in ipairs(zones or {}) do menu:AddOption(tostring(z.name or ("Зона " .. z.id)), function() net.Start("GRM_Ticket_ZoneAction") net.WriteString("teleport_zone") net.WriteUInt(t.id, 24) net.WriteUInt(tonumber(z.id) or 0, 16) net.SendToServer() end) end
                menu:Open()
            end
        end
        if #history > 0 then
            local hTitle = vgui.Create("DLabel", sc) hTitle:Dock(TOP) hTitle:SetTall(34) hTitle:SetText("ИСТОРИЯ ЗАКРЫТЫХ ТИКЕТОВ") hTitle:SetTextColor(C.blue) hTitle:SetFont("GRMTicketBody")
            for _, t in ipairs(history) do
                local h = vgui.Create("DLabel", sc) h:Dock(TOP) h:SetTall(52) h:DockMargin(0, 0, 0, 5) h:SetText("#" .. tostring(t.id) .. " • " .. tostring(t.name) .. " • закрыл: " .. tostring(t.closedBy or "—") .. " • оценка: " .. (t.rating and (t.rating .. "/5") or "нет") .. "\n" .. tostring(t.text)) h:SetTextColor(C.dim) h:SetWrap(true)
            end
        end
    end
    net.Receive("GRM_Ticket_AdminData", function() openAdmin(net.ReadTable() or {}) end)
    concommand.Add("grm_ticket", openCreate)
    concommand.Add("grm_tickets", function() net.Start("GRM_Ticket_AdminRequest") net.SendToServer() end)
    hook.Add("ShowTeam", "GRM_Tickets_F2", function(ply)
        if ply == LocalPlayer() and IsValid(ply) and ply:IsAdmin() then RunConsoleCommand("grm_tickets"); return true end
    end)
    hook.Add("PlayerBindPress", "GRM_Tickets_F2Bind", function(ply, bind, pressed)
        if ply == LocalPlayer() and pressed and string.find(string.lower(bind or ""), "gm_showteam", 1, true) and ply:IsAdmin() then RunConsoleCommand("grm_tickets"); return true end
    end)
    hook.Add("PlayerButtonDown", "GRM_Tickets_F2Button", function(ply, button)
        if ply == LocalPlayer() and button == KEY_F2 and ply:IsAdmin() then RunConsoleCommand("grm_tickets") end
    end)
    local f2Down = false
    hook.Add("Think", "GRM_Tickets_F2Poll", function()
        if GRM.Perf and not GRM.Perf.Throttle("tickets.f2poll",.05)then return end
        local down = input.IsKeyDown(KEY_F2)
        if down and not f2Down and IsValid(LocalPlayer()) and LocalPlayer():IsAdmin() then RunConsoleCommand("grm_tickets") end
        f2Down = down
    end)
    hook.Add("PlayerSayTransform", "GRM_Tickets_ClientCommands", function(ply, data)
        if ply ~= LocalPlayer() then return end
        local msg = string.lower(string.Trim(data and data[1] or ""))
        if msg == "/ticket" then openCreate(); data[1] = "" return true end
        local rid = string.match(msg, "^/ticket_rate%s+(%d+)$")
        if rid then openRating(rid); data[1] = "" return true end
        if msg == "/tickets" then RunConsoleCommand("grm_tickets"); data[1] = "" return true end
    end)
end
