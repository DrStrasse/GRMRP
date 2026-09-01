--[[--------------------------------------------------------------------
    GRM Photo — лёгкий конвейер.
    Кадры на диске по id, в net только сжатый jpeg по запросу.
    Показ: DHTML data-uri, без Source-материалов (розовая клетка).
----------------------------------------------------------------------]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Photo = GRM.Photo or {}
local P = GRM.Photo
P.Version = "2.0.0"
P.Config = { MaxBytes = 12000, MaxPerPlayer = 12, MaxMail = 24, MaxTitle = 48 }

local DIR, IDX, MAIL = "grm_photos", "grm_photos/index.json", "grm_photos/mail.json"

local function jsonLoad(path)
    if not file.Exists(path, "DATA") then return {} end
    local ok, t = pcall(util.JSONToTable, file.Read(path, "DATA") or "", false, true)
    return (ok and istable(t)) and t or {}
end

local function jsonSave(path, t)
    if not file.Exists(DIR, "DATA") then file.CreateDir(DIR) end
    file.Write(path, util.TableToJSON(t, false) or "{}")
end

local function rpName(ply)
    if not IsValid(ply) then return "?" end
    local n = ply:GetNWString("GRM_RPName", "")
    return n ~= "" and n or ply:Nick()
end

if GRM.Inventory and GRM.Inventory.RegisterItem then
    GRM.Inventory.RegisterItem("grm_photo", {
        type = "item", name = "Фотоснимок", desc = "Кадр. Использовать — открыть.",
        icon = "icon16/camera.png", maxStack = 1, weight = 0.05,
        model = "models/props_lab/frame002a.mdl", useFunc = "grm_photo_view",
    })
    GRM.Inventory.RegisterItem("grm_wanted_poster", {
        type = "item", name = "Лист розыска", desc = "Ориентировка. Использовать — лист.",
        icon = "icon16/page_error.png", maxStack = 5, weight = 0.08,
        model = "models/props_junk/garbage_newspaper001a.mdl", useFunc = "grm_poster_view",
    })
end

function P.CanOfficial(ply)
    if not IsValid(ply) then return false end
    if ply:IsSuperAdmin() then return true end
    if GRM.Wanted and isfunction(GRM.Wanted.CanView) and GRM.Wanted.CanView(ply) then return true end
    local f = string.lower(ply:GetNWString("GRM_Faction", ""))
    return f ~= "" and (f:find("ordnung", 1, true) or f:find("polizei", 1, true) or f:find("полиц", 1, true)
        or f:find("жандарм", 1, true) or f:find("feldgendarmerie", 1, true) or f:find("военн", 1, true)
        or f:find("journalist", 1, true) or f:find("журнал", 1, true))
end

if SERVER then
    for _, n in ipairs({ "GRM_Photo_Capture", "GRM_Photo_Upload", "GRM_Photo_List", "GRM_Photo_Get",
        "GRM_Photo_Blob", "GRM_Photo_Mail", "GRM_Photo_MailList", "GRM_Photo_Print",
        "GRM_Photo_OpenUI", "GRM_Photo_Notify", "GRM_Photo_Sheet" }) do
        util.AddNetworkString(n)
    end

    P.Index = P.Index or jsonLoad(IDX)
    P.Mail = P.Mail or jsonLoad(MAIL)
    P.Public = P.Public or {}

    local function saveSoon()
        local fn = function() jsonSave(IDX, P.Index) jsonSave(MAIL, P.Mail) end
        if GRM.Perf and GRM.Perf.Coalesce then GRM.Perf.Coalesce("grm_photo_save", 1.2, fn) else fn() end
    end

    function P.ReadBytes(id)
        local path = DIR .. "/" .. tostring(id) .. ".jpg"
        if not file.Exists(path, "DATA") then return nil end
        return file.Read(path, "DATA")
    end

    local function findPhoto(id)
        id = tostring(id or "")
        for _, rec in ipairs(P.Index) do if rec.id == id then return rec end end
    end

    local function albumOf(sid)
        local out = {}
        for _, rec in ipairs(P.Index) do if rec.owner == sid then out[#out + 1] = rec end end
        return out
    end

    local function notify(ply, msg, ok)
        if not IsValid(ply) then return end
        net.Start("GRM_Photo_Notify") net.WriteString(tostring(msg or "")) net.WriteBool(ok and true or false) net.Send(ply)
    end

    local function sendPacked(ply, netName, id, extra)
        local bytes = P.ReadBytes(id)
        if not bytes then return false end
        local packed = util.Compress(bytes) or bytes
        if #packed > 20000 then return false end
        net.Start(netName)
            net.WriteString(id)
            if extra then extra() end
            net.WriteUInt(#packed, 16)
            net.WriteData(packed, #packed)
        net.Send(ply)
        return true
    end

    function P.SendSheet(ply, id, headline, body)
        if not IsValid(ply) then return end
        sendPacked(ply, "GRM_Photo_Sheet", id, function()
            net.WriteString(string.sub(tostring(headline or ""), 1, 80))
            net.WriteString(string.sub(tostring(body or ""), 1, 160))
        end)
    end

    local function sendList(ply)
        local list = albumOf(ply:SteamID64())
        net.Start("GRM_Photo_List")
            net.WriteUInt(math.min(#list, 16), 8)
            for i = 1, math.min(#list, 16) do
                local r = list[i]
                net.WriteString(r.id or "")
                net.WriteString(string.sub(r.title or "", 1, 48))
                net.WriteString(string.sub(r.subject or "", 1, 48))
            end
        net.Send(ply)
    end

    local function sendMail(ply, inbox)
        inbox = inbox == "military" and "military" or "civil"
        local rows = {}
        for _, m in ipairs(P.Mail) do if m.inbox == inbox then rows[#rows + 1] = m end end
        net.Start("GRM_Photo_MailList")
            net.WriteString(inbox)
            local n = math.min(#rows, 20)
            net.WriteUInt(n, 8)
            for i = #rows, math.max(1, #rows - n + 1), -1 do
                local m = rows[i]
                net.WriteString(tostring(m.photoId or ""))
                net.WriteString(string.sub(m.fromName or "", 1, 40))
                net.WriteString(string.sub(m.subject or "", 1, 40))
                net.WriteString(string.sub(m.caption or "", 1, 60))
            end
        net.Send(ply)
    end

    net.Receive("GRM_Photo_Upload", function(_, ply)
        if not IsValid(ply) then return end
        ply._grmPhotoNext = ply._grmPhotoNext or 0
        if CurTime() < ply._grmPhotoNext then return end
        ply._grmPhotoNext = CurTime() + 2
        local title = string.sub(net.ReadString() or "", 1, 48)
        local subject = string.sub(net.ReadString() or "", 1, 48)
        net.ReadString()
        net.ReadUInt(16) net.ReadUInt(16)
        local n = net.ReadUInt(16)
        if n <= 0 or n > P.Config.MaxBytes then notify(ply, "Кадр слишком большой.", false) return end
        local data = net.ReadData(n)
        if not data or #data ~= n then notify(ply, "Кадр повреждён.", false) return end
        local sid = ply:SteamID64()
        if #albumOf(sid) >= P.Config.MaxPerPlayer then notify(ply, "Альбом полон.", false) return end
        if title == "" then title = "Кадр " .. os.date("%H:%M") end
        local id = string.format("%08x", tonumber(util.CRC(sid .. SysTime() .. n)) or math.random(1, 0x7fffffff))
        if not file.Exists(DIR, "DATA") then file.CreateDir(DIR) end
        file.Write(DIR .. "/" .. id .. ".jpg", data)
        P.Index[#P.Index + 1] = { id = id, owner = sid, title = title, subject = subject, created = os.time() }
        saveSoon()
        if GRM.Inventory and GRM.Inventory.AddItem then
            GRM.Inventory.AddItem(ply, "grm_photo", 1, { photoId = id, title = title, subject = subject })
        end
        notify(ply, "Снимок сохранён.", true)
        sendList(ply)
    end)

    net.Receive("GRM_Photo_Get", function(_, ply)
        if not IsValid(ply) then return end
        ply._grmPhotoGet = ply._grmPhotoGet or 0
        if CurTime() < ply._grmPhotoGet then return end
        ply._grmPhotoGet = CurTime() + 0.25
        local id = string.sub(net.ReadString() or "", 1, 16)
        local rec = findPhoto(id)
        if not rec then return end
        local ok = rec.owner == ply:SteamID64() or P.Public[id] or P.CanOfficial(ply)
        if not ok then
            for _, m in ipairs(P.Mail) do if m.photoId == id then ok = true break end end
        end
        if not ok then return end
        sendPacked(ply, "GRM_Photo_Blob", id)
    end)

    net.Receive("GRM_Photo_Mail", function(_, ply)
        if not (IsValid(ply) and P.CanOfficial(ply)) then return end
        local photoId = string.sub(net.ReadString() or "", 1, 16)
        local inbox = net.ReadString() == "military" and "military" or "civil"
        local caption = string.sub(net.ReadString() or "", 1, 80)
        local rec = findPhoto(photoId)
        if not rec then notify(ply, "Фото не найдено.", false) return end
        if rec.owner ~= ply:SteamID64() and not ply:IsSuperAdmin() then return end
        if #P.Mail >= P.Config.MaxMail then table.remove(P.Mail, 1) end
        P.Mail[#P.Mail + 1] = {
            photoId = photoId, inbox = inbox, fromName = rpName(ply),
            caption = caption, subject = rec.subject or "", created = os.time(),
        }
        P.Public[photoId] = true
        saveSoon()
        notify(ply, "Снимок в почте ведомства.", true)
    end)

    net.Receive("GRM_Photo_Print", function(_, ply)
        if IsValid(ply) then notify(ply, "Печать фотороботов снята со сборки.", false) end
    end)

    net.Receive("GRM_Photo_OpenUI", function(_, ply)
        if not IsValid(ply) then return end
        sendList(ply)
        if P.CanOfficial(ply) then
            sendMail(ply, ply.GRM_CompTerminalJur == "military" and "military" or "civil")
        end
    end)

    if GRM.Inventory and GRM.Inventory.RegisterUseHandler then
        GRM.Inventory.RegisterUseHandler("grm_photo_view", function(ply, _, slot)
            local id = slot.data and slot.data.photoId
            if id then P.SendSheet(ply, id, slot.data.title or "Снимок", slot.data.subject or "") end
        end)
        GRM.Inventory.RegisterUseHandler("grm_poster_view", function(ply, _, slot)
            local d = slot.data or {}
            if d.photoId then
                P.Public[d.photoId] = true
                P.SendSheet(ply, d.photoId, d.headline or "ВНИМАНИЕ! РОЗЫСК!", d.body or "")
            end
        end)
    end

    hook.Add("PlayerSay", "GRM_Photo_Cmd", function(ply, text)
        local t = string.Trim(string.lower(text or ""))
        if t == "/фото" or t == "/photo" or t == "/альбом" then
            net.Start("GRM_Photo_OpenUI") net.Send(ply)
            sendList(ply)
            return ""
        end
    end)

    print("[GRM Photo] v" .. P.Version .. " server")
end

if not CLIENT then return end

P.Album, P.MailRows, P.B64 = P.Album or {}, P.MailRows or {}, P.B64 or {}

local function remember(id, packed)
    if not id or not packed or packed == "" then return end
    local raw = util.Decompress(packed) or packed
    P.B64[id] = util.Base64Encode(raw)
    hook.Run("GRM_PhotoBlob", id)
end

local function htmlFor(id, stamp)
    local b = P.B64[id]
    if not b then return "<body style='margin:0;background:#111;color:#888;font:14px sans-serif;text-align:center;padding-top:40%'>загрузка…</body>" end
    local bar = stamp and "<div style='position:absolute;top:0;left:0;right:0;background:rgba(160,20,20,.75);color:#fff;font:bold 16px sans-serif;text-align:center;padding:6px'>ВНИМАНИЕ! РОЗЫСК!</div>" or ""
    return "<body style='margin:0;background:#0c1016;overflow:hidden'>" .. bar
        .. "<img src='data:image/jpeg;base64," .. b .. "' style='width:100%;height:100%;object-fit:contain'/></body>"
end

function P.BindHTML(pnl, id, stamp)
    if not IsValid(pnl) then return end
    pnl:SetHTML(htmlFor(id, stamp))
end

net.Receive("GRM_Photo_Notify", function()
    notification.AddLegacy(net.ReadString(), net.ReadBool() and NOTIFY_GENERIC or NOTIFY_ERROR, 4)
end)

net.Receive("GRM_Photo_List", function()
    local n = net.ReadUInt(8)
    P.Album = {}
    for i = 1, n do
        P.Album[i] = { id = net.ReadString(), title = net.ReadString(), subject = net.ReadString() }
    end
    hook.Run("GRM_PhotoAlbum")
end)

net.Receive("GRM_Photo_MailList", function()
    local inbox = net.ReadString()
    local n = net.ReadUInt(8)
    P.MailRows[inbox] = {}
    for i = 1, n do
        P.MailRows[inbox][i] = {
            photoId = net.ReadString(), fromName = net.ReadString(),
            subject = net.ReadString(), caption = net.ReadString(),
        }
    end
    hook.Run("GRM_PhotoMail")
end)

net.Receive("GRM_Photo_Blob", function()
    local id = net.ReadString()
    local n = net.ReadUInt(16)
    if n > 0 then remember(id, net.ReadData(n)) end
end)

net.Receive("GRM_Photo_Sheet", function()
    local id = net.ReadString()
    local head, body = net.ReadString(), net.ReadString()
    local n = net.ReadUInt(16)
    if n > 0 then remember(id, net.ReadData(n)) end
    if P.OpenSheet then P.OpenSheet(id, head, body, true) end
end)

net.Receive("GRM_Photo_Capture", function() hook.Run("GRM_PhotoDoCapture") end)
net.Receive("GRM_Photo_OpenUI", function() if P.OpenStudio then P.OpenStudio() end end)

function P.RequestBlob(id)
    if not id or id == "" or P.B64[id] then
        if id and P.B64[id] then hook.Run("GRM_PhotoBlob", id) end
        return
    end
    net.Start("GRM_Photo_Get") net.WriteString(id) net.SendToServer()
end

function P.SendMail(photoId, inbox, caption)
    net.Start("GRM_Photo_Mail")
        net.WriteString(photoId or "") net.WriteString(inbox or "civil") net.WriteString(caption or "")
    net.SendToServer()
end

function P.PrintPoster()
    notification.AddLegacy("Печать фотороботов снята со сборки.", NOTIFY_ERROR, 4)
end

function P.OpenSheet(id, headline, body)
    if IsValid(P._sheet) then P._sheet:Remove() end
    local fr = vgui.Create("DFrame")
    P._sheet = fr
    fr:SetSize(520, 600) fr:Center() fr:SetTitle("") fr:MakePopup()
    fr.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, Color(12, 16, 24, 250))
        draw.SimpleText(headline ~= "" and headline or "ЛИСТ", "DermaDefaultBold", w / 2, 16, Color(230, 70, 60), TEXT_ALIGN_CENTER)
    end
    local html = vgui.Create("DHTML", fr)
    html:SetPos(12, 32) html:SetSize(496, 470)
    P.BindHTML(html, id, true)
    local lab = vgui.Create("DLabel", fr)
    lab:SetPos(12, 508) lab:SetSize(496, 40) lab:SetWrap(true) lab:SetTextColor(Color(210, 218, 226))
    lab:SetText(tostring(body or ""))
    local close = vgui.Create("DButton", fr)
    close:SetPos(12, 554) close:SetSize(496, 32) close:SetText("Закрыть") close:SetTextColor(color_white)
    close.Paint = function(s, w, h) draw.RoundedBox(4, 0, 0, w, h, s:IsHovered() and Color(70, 80, 95) or Color(40, 48, 60)) end
    close.DoClick = function() fr:Close() end
    hook.Add("GRM_PhotoBlob", "GRM_PhotoSheet", function(got)
        if got == id and IsValid(html) then P.BindHTML(html, id, true) end
    end)
end

function P.OpenStudio()
    if IsValid(P._frame) then P._frame:Remove() end
    local fr = vgui.Create("DFrame")
    P._frame = fr
    fr:SetSize(800, 520) fr:Center() fr:SetTitle("") fr:MakePopup()
    fr.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, Color(12, 16, 24, 250))
        draw.SimpleText("АЛЬБОМ", "DermaDefaultBold", 14, 14, Color(230, 80, 70), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    local list = vgui.Create("DListView", fr)
    list:SetPos(12, 32) list:SetSize(260, 360)
    list:AddColumn("Снимок") list:AddColumn("Объект")
    local html = vgui.Create("DHTML", fr)
    html:SetPos(284, 32) html:SetSize(500, 300)
    html:SetHTML(htmlFor("", false))
    local cur = ""
    local function refill()
        list:Clear()
        for _, r in ipairs(P.Album or {}) do
            local line = list:AddLine(r.title or r.id, r.subject ~= "" and r.subject or "—")
            line._id = r.id
        end
    end
    refill()
    list.OnRowSelected = function(_, _, line)
        if not line or not line._id then return end
        cur = line._id
        P.RequestBlob(cur)
        P.BindHTML(html, cur, false)
    end
    hook.Add("GRM_PhotoAlbum", "GRM_PhotoStudio", function() if IsValid(list) then refill() end end)
    hook.Add("GRM_PhotoBlob", "GRM_PhotoStudio", function(id)
        if id == cur and IsValid(html) then P.BindHTML(html, cur, false) end
    end)
    local cap = vgui.Create("DTextEntry", fr)
    cap:SetPos(284, 340) cap:SetSize(500, 24) cap:SetPlaceholderText("Подпись")
    local function mk(x, y, w, txt, col, fn)
        local b = vgui.Create("DButton", fr)
        b:SetPos(x, y) b:SetSize(w, 28) b:SetText(txt) b:SetTextColor(color_white)
        b.Paint = function(s, bw, bh)
            draw.RoundedBox(4, 0, 0, bw, bh, s:IsHovered() and col or Color(col.r * 0.7, col.g * 0.7, col.b * 0.7))
        end
        b.DoClick = fn
    end
    mk(12, 404, 260, "На полицейский ПК", Color(50, 110, 190), function() if cur ~= "" then P.SendMail(cur, "civil", cap:GetValue()) end end)
    mk(12, 436, 260, "На ПК жандармерии", Color(140, 90, 40), function() if cur ~= "" then P.SendMail(cur, "military", cap:GetValue()) end end)
    mk(284, 404, 500, "Закрыть", Color(50, 55, 65), function() fr:Close() end)
end

function P.AttachTab(tabs)
end

print("[GRM Photo] v" .. P.Version .. " client")
