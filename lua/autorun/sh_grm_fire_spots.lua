--[[--------------------------------------------------------------------
    GRM Fire — точки очага: таймеры, список, поджечь / снять.
    /fire_spots  SuperAdmin. Не трогает Q HOLD и factions.
----------------------------------------------------------------------]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Fire = GRM.Fire or {}
local F = GRM.Fire

local NET_REQ  = "GRM_FireSpot_Req"
local NET_DATA = "GRM_FireSpot_Data"
local NET_SAVE = "GRM_FireSpot_Save"
local NET_ACT  = "GRM_FireSpot_Act"

local function tell(ply, msg, r, g, b)
    if IsValid(ply) and GRM.Notify then GRM.Notify(ply, msg, r or 220, g or 180, b or 80)
    elseif IsValid(ply) then ply:ChatPrint("[Пожар] " .. tostring(msg)) end
end

if SERVER then
    util.AddNetworkString(NET_REQ)
    util.AddNetworkString(NET_DATA)
    util.AddNetworkString(NET_SAVE)
    util.AddNetworkString(NET_ACT)

    local function packSpots()
        local out = {}
        for _, ent in ipairs(ents.FindByClass("grm_fire_spot")) do
            if IsValid(ent) then
                local p = ent:GetPos()
                out[#out + 1] = {
                    idx = ent:EntIndex(),
                    label = ent.GetSpotLabel and ent:GetSpotLabel() or "очаг",
                    weight = ent.GetWeight and ent:GetWeight() or 1,
                    last = ent.GetLastIgnite and ent:GetLastIgnite() or 0,
                    cool = ent.GetCoolSec and ent:GetCoolSec() or 0,
                    feed = ent.GetFeed and ent:GetFeed() or 180,
                    on = not (ent.GetSpotOn and ent:GetSpotOn() == false),
                    x = math.floor(p.x), y = math.floor(p.y), z = math.floor(p.z),
                }
            end
        end
        return out
    end

    local function send(ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        local c = F.Config or {}
        net.Start(NET_DATA)
            net.WriteTable({
                random = c.RandomEnabled ~= false,
                stove = c.StoveEnabled ~= false,
                min_sec = tonumber(c.RandomMinSec) or 480,
                max_sec = tonumber(c.RandomMaxSec) or 900,
                cooldown = tonumber(c.SpotCooldownSec) or 2700,
                max_incidents = tonumber(c.MaxIncidents) or 8,
            })
            net.WriteTable(packSpots())
        net.Send(ply)
    end

    net.Receive(NET_REQ, function(_, ply) send(ply) end)

    net.Receive(NET_SAVE, function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        local t = net.ReadTable() or {}
        F.Config = F.Config or {}
        if t.random ~= nil then F.Config.RandomEnabled = t.random == true end
        if t.stove ~= nil then F.Config.StoveEnabled = t.stove == true end
        if t.min_sec then F.Config.RandomMinSec = tonumber(t.min_sec) end
        if t.max_sec then F.Config.RandomMaxSec = tonumber(t.max_sec) end
        if t.cooldown then F.Config.SpotCooldownSec = tonumber(t.cooldown) end
        if t.max_incidents then F.Config.MaxIncidents = tonumber(t.max_incidents) end
        if F.SaveConfig then F.SaveConfig("панель очагов") end
        if F.RescheduleRandom then F.RescheduleRandom() end
        tell(ply, "Таймеры очагов сохранены.", 100, 220, 130)
        send(ply)
    end)

    net.Receive(NET_ACT, function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        local act = tostring(net.ReadString() or "")
        local idx = tonumber(net.ReadUInt(16)) or 0
        local extra = tostring(net.ReadString() or "")
        if act == "ignite_look" then
            local tr = ply:GetEyeTrace()
            local hit = IsValid(tr.Entity) and tr.Entity or nil
            if IsValid(hit) and hit:GetClass() == "grm_fire_spot" and hit.IgniteSpot then
                local fire, err = hit:IgniteSpot(hit.GetFeed and hit:GetFeed() or 180, ply:SteamID64())
                tell(ply, IsValid(fire) and "Точка подожжена." or tostring(err or "не поджечь"), IsValid(fire) and 100 or 255, IsValid(fire) and 220 or 140, 90)
            else
                F.Ignite(tr.HitPos, "admin", ply:SteamID64())
                tell(ply, "Очаг в прицеле.", 100, 220, 130)
            end
            send(ply)
            return
        end
        local ent = Entity(idx)
        if not (IsValid(ent) and ent:GetClass() == "grm_fire_spot") then
            tell(ply, "Точка не найдена.", 255, 140, 90)
            send(ply)
            return
        end
        if act == "ignite" then
            local fire, err = ent:IgniteSpot(ent.GetFeed and ent:GetFeed() or 180, ply:SteamID64())
            tell(ply, IsValid(fire) and ("Подожжено: " .. tostring(ent:GetSpotLabel())) or tostring(err or "не поджечь"),
                IsValid(fire) and 100 or 255, IsValid(fire) and 220 or 140, 90)
        elseif act == "delete" then
            if GRM.Perm and GRM.Perm.Remove then pcall(GRM.Perm.Remove, ply, ent, false) end
            ent:Remove()
            tell(ply, "Точка снята.", 255, 180, 90)
        elseif act == "toggle" then
            local on = not (ent.GetSpotOn and ent:GetSpotOn() == false)
            if ent.SetSpotOn then ent:SetSpotOn(not on) end
            if GRM.PermData and GRM.PermData.UpdateEntry then pcall(GRM.PermData.UpdateEntry, ent) end
            tell(ply, (not on) and "Точка включена." or "Точка выключена.", 120, 200, 255)
        elseif act == "label" then
            extra = string.Trim(extra)
            if extra == "" then extra = "очаг" end
            if #extra > 32 then extra = string.sub(extra, 1, 32) end
            if ent.SetSpotLabel then ent:SetSpotLabel(extra) end
            if GRM.PermData and GRM.PermData.UpdateEntry then pcall(GRM.PermData.UpdateEntry, ent) end
        elseif act == "weight" then
            local w = math.Clamp(math.floor(tonumber(extra) or 1), 1, 99)
            if ent.SetWeight then ent:SetWeight(w) end
            if GRM.PermData and GRM.PermData.UpdateEntry then pcall(GRM.PermData.UpdateEntry, ent) end
        end
        send(ply)
    end)

    hook.Add("GRM_FireAddon_SpotUse", "GRM_FireSpots", function(ply, ent)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        send(ply)
    end)

    local function open(ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then
            tell(ply, "Только суперадмин.", 255, 100, 100)
            return
        end
        send(ply)
    end
    concommand.Add("grm_fire_spots", open)
    hook.Add("PlayerSay", "GRM_FireSpots_Chat", function(ply, text)
        local t = string.lower(string.Trim(tostring(text or "")))
        if t == "/fire_spots" or t == "!fire_spots" or t == "/очаги" or t == "/пожары_очаги" then
            open(ply)
            return ""
        end
    end)
    hook.Add("PlayerSay", "GRM_FireSpots_ChatT", function(ply, text, teamSays)
        local datapack = { tostring(text or ""), SkipPlayerSay = false }
            if not istable(datapack) or type(datapack[1]) ~= "string" then return end
            local t = string.lower(string.Trim(datapack[1]))
            if t == "/fire_spots" or t == "!fire_spots" or t == "/очаги" or t == "/пожары_очаги" then
                open(ply)
                datapack.SkipPlayerSay = true
                datapack[1] = ""
            end

        if datapack.SkipPlayerSay == true then return "" end
    end)

    print("[GRM Fire] Spots admin loaded")
end

if CLIENT then
    surface.CreateFont("GRMFireSpot_T", { font = "Roboto", size = 18, weight = 700, extended = true })
    surface.CreateFont("GRMFireSpot_N", { font = "Roboto", size = 13, weight = 500, extended = true })

    local frame
    local function openUI(cfg, spots)
        cfg = cfg or {}
        spots = spots or {}
        if IsValid(frame) then frame:Remove() end
        frame = vgui.Create("DFrame")
        frame:SetSize(620, 640)
        frame:Center()
        frame:SetTitle("")
        frame:ShowCloseButton(false)
        frame:MakePopup()
        if GRM.UI and GRM.UI.Track then GRM.UI.Track("fire_spots", frame) end
        frame.Paint = function(_, w, h)
            draw.RoundedBox(8, 0, 0, w, h, Color(18, 20, 28, 250))
            draw.SimpleText("ОЧАГИ И ТАЙМЕРЫ", "GRMFireSpot_T", 14, 18, Color(235, 235, 240), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        local x = vgui.Create("DButton", frame)
        x:SetPos(580, 10) x:SetSize(28, 28) x:SetText("X") x:SetTextColor(color_white)
        x.Paint = function(self, w, h)
            draw.RoundedBox(4, 0, 0, w, h, self:IsHovered() and Color(220, 70, 70) or Color(40, 44, 56))
        end
        x.DoClick = function() if IsValid(frame) then frame:Remove() end end

        local body = vgui.Create("DScrollPanel", frame)
        body:Dock(FILL) body:DockMargin(12, 44, 12, 52)

        local function row()
            local p = vgui.Create("DPanel", body)
            p:Dock(TOP) p:SetTall(28) p:DockMargin(0, 2, 0, 0) p:SetPaintBackground(false)
            return p
        end

        local rOn = row()
        local chkR = vgui.Create("DCheckBoxLabel", rOn)
        chkR:Dock(FILL) chkR:SetText("Случайное воспламенение точек") chkR:SetTextColor(color_white)
        chkR:SetValue(cfg.random == true and 1 or 0)

        local rSt = row()
        local chkS = vgui.Create("DCheckBoxLabel", rSt)
        chkS:Dock(FILL) chkS:SetText("Плита может загореться") chkS:SetTextColor(color_white)
        chkS:SetValue(cfg.stove == true and 1 or 0)

        local function num(parent, label, val, minv, maxv)
            local lab = vgui.Create("DLabel", parent)
            lab:Dock(LEFT) lab:SetWide(240) lab:SetText(label) lab:SetTextColor(Color(200, 205, 215))
            local nw = vgui.Create("DNumberWang", parent)
            nw:Dock(RIGHT) nw:SetWide(110) nw:SetMin(minv) nw:SetMax(maxv) nw:SetValue(val)
            return nw
        end
        local nMin = num(row(), "Интервал мин, сек", tonumber(cfg.min_sec) or 480, 30, 7200)
        local nMax = num(row(), "Интервал макс, сек", tonumber(cfg.max_sec) or 900, 30, 10800)
        local nCd  = num(row(), "Кулдаун точки, сек", tonumber(cfg.cooldown) or 2700, 0, 86400)
        local nMaxI = num(row(), "Лимит инцидентов", tonumber(cfg.max_incidents) or 8, 1, 24)

        local hint = vgui.Create("DLabel", body)
        hint:Dock(TOP) hint:SetTall(36) hint:DockMargin(0, 8, 0, 4)
        hint:SetText("Точки на карте: " .. tostring(#spots) .. "   ·   видны с тулом «Пожарное железо»")
        hint:SetTextColor(Color(255, 170, 80))

        for _, rec in ipairs(spots) do
            local line = vgui.Create("DPanel", body)
            line:Dock(TOP) line:SetTall(34) line:DockMargin(0, 2, 0, 0)
            line.Paint = function(_, w, h) draw.RoundedBox(4, 0, 0, w, h, Color(32, 36, 48, 245)) end
            local lab = vgui.Create("DLabel", line)
            lab:Dock(FILL) lab:DockMargin(8, 0, 4, 0)
            local st = rec.on == false and "ВЫКЛ" or "вкл"
            lab:SetText(string.format("%s  ×%d  %s  @ %d %d %d", tostring(rec.label or "очаг"), tonumber(rec.weight) or 1, st, rec.x or 0, rec.y or 0, rec.z or 0))
            lab:SetTextColor(color_white)
            local function act(a)
                net.Start(NET_ACT)
                    net.WriteString(a)
                    net.WriteUInt(tonumber(rec.idx) or 0, 16)
                    net.WriteString("")
                net.SendToServer()
            end
            local bD = vgui.Create("DButton", line)
            bD:Dock(RIGHT) bD:SetWide(70) bD:SetText("Снять")
            bD.DoClick = function() act("delete") end
            local bI = vgui.Create("DButton", line)
            bI:Dock(RIGHT) bI:SetWide(80) bI:SetText("Поджечь")
            bI.DoClick = function() act("ignite") end
            local bT = vgui.Create("DButton", line)
            bT:Dock(RIGHT) bT:SetWide(70) bT:SetText(rec.on == false and "Вкл" or "Выкл")
            bT.DoClick = function() act("toggle") end
        end

        local bot = vgui.Create("DPanel", frame)
        bot:Dock(BOTTOM) bot:SetTall(44) bot:SetPaintBackground(false)
        local save = vgui.Create("DButton", bot)
        save:Dock(RIGHT) save:SetWide(160) save:DockMargin(6, 6, 10, 6)
        save:SetText("Сохранить таймеры")
        save.DoClick = function()
            net.Start(NET_SAVE)
                net.WriteTable({
                    random = chkR:GetChecked() == true,
                    stove = chkS:GetChecked() == true,
                    min_sec = nMin:GetValue(),
                    max_sec = nMax:GetValue(),
                    cooldown = nCd:GetValue(),
                    max_incidents = nMaxI:GetValue(),
                })
            net.SendToServer()
        end
        local look = vgui.Create("DButton", bot)
        look:Dock(LEFT) look:SetWide(180) look:DockMargin(10, 6, 6, 6)
        look:SetText("Поджечь в прицеле")
        look.DoClick = function()
            net.Start(NET_ACT)
                net.WriteString("ignite_look")
                net.WriteUInt(0, 16)
                net.WriteString("")
            net.SendToServer()
        end
    end

    net.Receive(NET_DATA, function()
        openUI(net.ReadTable() or {}, net.ReadTable() or {})
    end)

    concommand.Add("grm_fire_spots", function()
        net.Start(NET_REQ) net.SendToServer()
    end)
end

-- Вечер-18: команды пересажены с мёртвого входа EasyChat (PlayerSayTransform)
-- на боевой контракт библиотеки GRMRPChat — имена в едином внешнем реестре,
-- иначе чат съел бы их как «неизвестные» и по цепочке PlayerSay вызвал бы
-- обработчики этого файла.
if GRM and GRM.Chat and GRM.Chat.RegisterExternalCommands then
    GRM.Chat.RegisterExternalCommands({ "/fire_spots", "/очаги", "/пожары_очаги" })
end
