--[[--------------------------------------------------------------------
    GRM Fire — панель насосной станции (G после /firetruck).
    Одно окно, без пересборки. Баки читаются с насоса (NW), не через net-спам.
----------------------------------------------------------------------]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Fire = GRM.Fire or {}
local F = GRM.Fire

local NET_OPEN = "GRM_FirePump_Open"
local NET_DATA = "GRM_FirePump_Data"
local NET_ACT  = "GRM_FirePump_Act"

local function tell(ply, msg, r, g, b)
    if IsValid(ply) and GRM.Notify then GRM.Notify(ply, msg, r or 220, g or 180, b or 80)
    elseif IsValid(ply) then ply:ChatPrint("[Насос] " .. tostring(msg)) end
end

local function findPumpFor(ply)
    if not IsValid(ply) then return nil, nil end
    local veh = ply:GetNWEntity("GRM_FireMyTruck")
    if not IsValid(veh) then
        local seat = ply:GetVehicle()
        if IsValid(seat) then
            local p = seat:GetParent()
            if IsValid(p) and p:GetNWBool("GRM_FireTruck", false) then veh = p
            elseif seat:GetNWBool("GRM_FireTruck", false) then veh = seat end
        end
    end
    if IsValid(veh) and F.FindPumpOn then
        local pump = F.FindPumpOn(veh)
        if IsValid(pump) then return pump, veh end
    end
    local tr = ply:GetEyeTrace()
    if IsValid(tr.Entity) then
        if tr.Entity:GetClass() == "grm_fire_pump" then
            return tr.Entity, tr.Entity.GetHostVehicle and tr.Entity:GetHostVehicle() or nil
        end
        if F.IsFireTruck and F.IsFireTruck(tr.Entity) and F.FindPumpOn then
            local pump = F.FindPumpOn(tr.Entity)
            if IsValid(pump) then return pump, tr.Entity end
        end
    end
    for _, e in ipairs(ents.FindInSphere(ply:GetPos(), 280)) do
        if IsValid(e) and e:GetClass() == "grm_fire_pump" then
            return e, e.GetHostVehicle and e:GetHostVehicle() or e:GetParent()
        end
    end
    return nil, nil
end

local function pack(pump)
    local hyd = pump.FindLinkedHydrant and pump:FindLinkedHydrant() or nil
    local cab = pump.FindLinkedCabinet and pump:FindLinkedCabinet() or nil
    return {
        water = pump:GetTank() or 0,
        waterMax = pump:GetTankMax() or 4000,
        foam = pump:GetFoam() or 0,
        foamMax = pump:GetFoamMax() or 500,
        powder = pump:GetPowder() or 0,
        powderMax = pump:GetPowderMax() or 250,
        agent = pump:GetAgent() ~= "" and pump:GetAgent() or "water",
        pumpOn = pump:GetPumpOn() == true,
        filling = pump:GetFilling() == true,
        feed = pump:GetHydrantFeed() == true,
        hydrant = IsValid(hyd),
        cabinet = IsValid(cab),
        hoses = pump:GetHosesOut() or 0,
        hosesMax = pump:GetHosesMax() or 4,
        idx = pump:EntIndex(),
    }
end

if SERVER then
    util.AddNetworkString(NET_OPEN)
    util.AddNetworkString(NET_DATA)
    util.AddNetworkString(NET_ACT)

    local lastAct = {}

    local function send(ply, pump)
        if not IsValid(ply) or not IsValid(pump) then return end
        net.Start(NET_DATA)
            net.WriteTable(pack(pump))
        net.Send(ply)
    end

    function F.OpenPumpPanel(ply)
        if not IsValid(ply) then return false, "нет игрока" end
        if not (F.CanFightPro and F.CanFightPro(ply)) then
            return false, "нет доступа пожарного (галочка Control в /fire_access)"
        end
        local pump = F.EnsureTruckPump and select(1, F.EnsureTruckPump(ply)) or select(1, findPumpFor(ply))
        if not IsValid(pump) then pump = select(1, findPumpFor(ply)) end
        if not IsValid(pump) then return false, "подойдите к пожарной машине. Сядьте и /firetruck, либо /рукав" end
        if ply:GetPos():DistToSqr(pump:GetPos()) > 420 * 420 then
            return false, "слишком далеко от насоса"
        end
        send(ply, pump)
        return true
    end

    net.Receive(NET_OPEN, function(_, ply)
        local ok, err = F.OpenPumpPanel(ply)
        if not ok then tell(ply, err, 255, 140, 90) end
    end)

    net.Receive(NET_ACT, function(_, ply)
        if not IsValid(ply) then return end
        if not (F.CanFightPro and F.CanFightPro(ply)) then return end
        local now = CurTime()
        if (lastAct[ply] or 0) > now then return end
        lastAct[ply] = now + 0.2
        local act = tostring(net.ReadString() or "")
        local extra = tostring(net.ReadString() or "")
        if act == "refresh" or act == "" then return end
        local pump = select(1, findPumpFor(ply))
        if not IsValid(pump) then tell(ply, "насос не найден", 255, 140, 90) return end
        if ply:GetPos():DistToSqr(pump:GetPos()) > 360 * 360 then return end

        if act == "agent" and (extra == "water" or extra == "foam" or extra == "powder") then
            pump:SetAgent(extra)
            tell(ply, "Ствол: " .. (extra == "foam" and "пена" or extra == "powder" and "порошок" or "вода"), 120, 200, 255)
        elseif act == "pump" then
            pump:SetPumpOn(not pump:GetPumpOn())
            pump:EmitSound(pump:GetPumpOn() and "ambient/machines/floodgate_stop1.wav" or "buttons/lever4.wav", 65, 100)
        elseif act == "feed" then
            pump:SetHydrantFeed(not pump:GetHydrantFeed())
            tell(ply, pump:GetHydrantFeed() and "Прямая подача с гидранта — бак воды не тратится."
                or "Подача из бака — вода списывается при тушении.", 120, 200, 255)
        elseif act == "fill" then
            local ag = pump:GetAgent()
            if ag == "" then ag = "water" end
            if ag == "powder" then
                if not IsValid(pump:FindLinkedCabinet()) then
                    tell(ply, "Порошок: встаньте у шкафа огнетушителей.", 255, 160, 80)
                    send(ply, pump)
                    return
                end
            else
                if not IsValid(pump:FindLinkedHydrant()) then
                    tell(ply, "Нет связи с открытым гидрантом. Откройте колонку рядом или стыкуйте рукав.", 255, 160, 80)
                    send(ply, pump)
                    return
                end
            end
            pump:SetFilling(not pump:GetFilling())
            tell(ply, pump:GetFilling() and "Закачка включена." or "Закачка остановлена.", 100, 220, 130)
        elseif act == "drain" then
            local ag = extra ~= "" and extra or (pump:GetAgent() ~= "" and pump:GetAgent() or "water")
            if pump.DrainAgent then pump:DrainAgent(ag, 99999) end
            tell(ply, "Бак слит: " .. ag, 255, 180, 90)
        elseif act == "take" then
            local ok, err
            if F.TakeHoseFromTruck then
                ok, err = F.TakeHoseFromTruck(ply)
            else
                local A = GRM.FireAddon
                if not (A and A.TakeHose) then tell(ply, "аддон рукава не загружен", 255, 140, 90) send(ply, pump) return end
                local h, e = A.TakeHose(ply, pump)
                ok, err = h ~= nil, e
            end
            if ok then
                tell(ply, "Ствол в руках. ЛКМ — лить. S / назад / ALT — смотка. E на насос — вернуть.", 100, 220, 130)
            else
                tell(ply, tostring(err or "не выдать ствол"), 255, 140, 90)
            end
        elseif act == "rewind" then
            local A = GRM.FireAddon
            local n = (A and A.RewindAtSource) and A.RewindAtSource(pump, ply) or 0
            tell(ply, n > 0 and ("Смотано рукавов: " .. n) or "Нет рукава на катушке.", n > 0 and 100 or 255, n > 0 and 220 or 140, n > 0 and 130 or 90)
        elseif act == "link" then
            local A = GRM.FireAddon
            if not A then tell(ply, "аддон рукава не загружен", 255, 140, 90) send(ply, pump) return end
            local held = ply.GRM_FireHose
            if IsValid(held) then
                local start = held.GetStartEnt and held:GetStartEnt() or NULL
                if start == pump then
                    local hyd = A.NearestHydrant and select(1, A.NearestHydrant(pump:GetPos(), 2200)) or nil
                    if not IsValid(hyd) then tell(ply, "Гидрант не найден. Поставьте колонку тулом.", 255, 160, 80)
                    else
                        local ok, err = held:DockTo(hyd, ply)
                        tell(ply, ok and "Рукав стыкован с гидрантом." or tostring(err or "стык не вышел"), ok and 100 or 255, ok and 220 or 140, ok and 130 or 90)
                    end
                elseif IsValid(start) and start:GetClass() == "grm_fire_hydrant" then
                    local ok, err = held:DockTo(pump, ply)
                    tell(ply, ok and "Рукав с гидранта стыкован к насосу." or tostring(err or "стык не вышел"), ok and 100 or 255, ok and 220 or 140, ok and 130 or 90)
                else
                    tell(ply, "Сначала сдайте чужой рукав.", 255, 160, 80)
                end
            else
                local near = pump.FindLinkedHydrant and pump:FindLinkedHydrant() or nil
                if IsValid(near) then
                    tell(ply, "Уже связано: открытый гидрант рядом. Жмите «Закачка».", 100, 220, 130)
                else
                    local hyd, dist = A.NearestHydrant and A.NearestHydrant(pump:GetPos(), 2200) or nil
                    if not IsValid(hyd) then
                        tell(ply, "Гидранта нет в 2200 юн. Поставьте колонку и откройте E.", 255, 160, 80)
                    elseif hyd.GetOpen and not hyd:GetOpen() then
                        tell(ply, "Откройте гидрант (E), затем снова «Связать».", 255, 160, 80)
                    elseif (dist or 9999) <= 380 then
                        tell(ply, "Гидрант рядом — связь есть. Жмите «Закачка».", 100, 220, 130)
                    else
                        local h, err = A.LaySupplyLine(hyd, pump)
                        tell(ply, h and ("Рукав проложен к гидранту (" .. math.floor(dist or 0) .. " юн.).") or tostring(err or "не связать"), h and 100 or 255, h and 220 or 140, h and 130 or 90)
                    end
                end
            end
        else
            return
        end
        if pump.SyncHost then pump:SyncHost() end
        send(ply, pump)
    end)

    concommand.Add("grm_fire_pump_ui", function(ply)
        if not IsValid(ply) then return end
        local ok, err = F.OpenPumpPanel(ply)
        if not ok then tell(ply, err, 255, 140, 90) end
    end)

    print("[GRM Fire] Pump UI server loaded")
end

if CLIENT then
    surface.CreateFont("GRMFirePump_T", { font = "Roboto", size = 18, weight = 700, extended = true })
    surface.CreateFont("GRMFirePump_N", { font = "Roboto", size = 14, weight = 500, extended = true })

    local frame
    local lastG = 0

    local function closeUI()
        if IsValid(frame) then frame:Remove() end
        frame = nil
        if GRM.UI and GRM.UI.Close then GRM.UI.Close("fire_pump") end
    end

    local function live(st)
        st = st or {}
        local pump = Entity(tonumber(st.idx) or -1)
        if not (IsValid(pump) and pump:GetClass() == "grm_fire_pump") then
            return st
        end
        local ag = pump.GetAgent and pump:GetAgent() or st.agent or "water"
        if ag == "" then ag = "water" end
        return {
            water = pump:GetTank() or st.water or 0,
            waterMax = pump:GetTankMax() or st.waterMax or 4000,
            foam = pump:GetFoam() or st.foam or 0,
            foamMax = pump:GetFoamMax() or st.foamMax or 500,
            powder = pump:GetPowder() or st.powder or 0,
            powderMax = pump:GetPowderMax() or st.powderMax or 250,
            agent = ag,
            pumpOn = pump:GetPumpOn() == true,
            filling = pump:GetFilling() == true,
            feed = pump:GetHydrantFeed() == true,
            hydrant = st.hydrant == true,
            cabinet = st.cabinet == true,
            hoses = pump:GetHosesOut() or st.hoses or 0,
            hosesMax = pump:GetHosesMax() or st.hosesMax or 4,
            idx = st.idx,
        }
    end

    local function paintBar(x, y, w, h, frac, col, label, have, maxv)
        draw.RoundedBox(4, x, y, w, h, Color(18, 22, 30, 240))
        local fw = math.floor(w * math.Clamp(frac, 0, 1))
        if fw > 2 then draw.RoundedBox(4, x + 1, y + 1, fw - 2, h - 2, col) end
        draw.SimpleText(string.format("%s  %d / %d", label, have, maxv), "GRMFirePump_N", x + 8, y + h / 2, Color(235, 238, 242), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local function applyFlags(fr, st)
        if not IsValid(fr) then return end
        local s = live(st)
        if IsValid(fr._btnPump) then
            fr._btnPump:SetText(s.pumpOn and "Насос: ВЫКЛЮЧИТЬ" or "Насос: ВКЛЮЧИТЬ")
        end
        if IsValid(fr._btnFill) then
            fr._btnFill:SetText(s.filling and "Закачка: СТОП" or "Закачка с гидранта / шкафа")
        end
        if IsValid(fr._btnFeed) then
            fr._btnFeed:SetText(s.feed and "Прямая подача с гидранта: ВКЛ" or "Прямая подача с гидранта: выкл")
        end
    end

    local function openUI(st)
        if IsValid(frame) then
            frame._st = st
            applyFlags(frame, st)
            return
        end
        local C = {
            bg = Color(8, 14, 23, 248), panel = Color(16, 27, 42, 245),
            text = Color(225, 238, 247), cyan = Color(48, 204, 255),
            red = Color(244, 78, 96), header = Color(10, 22, 37, 255),
        }
        local T = GRM.UI and GRM.UI.Theme
        if T and T.Colors then C = T.Colors end

        frame = vgui.Create("DFrame")
        frame:SetSize(520, 700)
        frame:Center()
        frame:SetTitle("")
        frame:ShowCloseButton(false)
        frame:SetDraggable(true)
        frame:SetSizable(false)
        frame:MakePopup()
        if GRM.UI and GRM.UI.Track then GRM.UI.Track("fire_pump", frame) end
        frame._st = st
        frame.OnRemove = function(self)
            if frame == self then frame = nil end
        end
        frame.Paint = function(self, w, h)
            draw.RoundedBox(9, 0, 0, w, h, C.bg or Color(8, 14, 23, 248))
            draw.RoundedBoxEx(9, 0, 0, w, 52, C.header or Color(10, 22, 37, 255), true, true, false, false)
            draw.SimpleText("НАСОСНАЯ СТАНЦИЯ", "GRMFirePump_T", 16, 18, C.text or color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText("вода · пена · порошок", "GRMFirePump_N", 16, 38, C.cyan or Color(48, 204, 255), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end

        local close = vgui.Create("DButton", frame)
        close:SetPos(480, 12) close:SetSize(28, 28) close:SetText("X")
        close:SetTextColor(C.text or color_white)
        close.Paint = function(self, w, h)
            draw.RoundedBox(4, 0, 0, w, h, self:IsHovered() and (C.red or Color(244, 78, 96)) or (C.panel or Color(16, 27, 42)))
        end
        close.DoClick = closeUI

        local body = vgui.Create("DPanel", frame)
        body:Dock(FILL) body:DockMargin(14, 58, 14, 12)
        body:SetPaintBackground(false)
        body.Paint = function(_, w, h)
            local s = live(frame and frame._st)
            paintBar(0, 4, w, 28, s.water / math.max(1, s.waterMax), Color(50, 140, 230), "ВОДА", s.water, s.waterMax)
            paintBar(0, 38, w, 28, s.foam / math.max(1, s.foamMax), Color(230, 80, 70), "ПЕНА", s.foam, s.foamMax)
            paintBar(0, 72, w, 28, s.powder / math.max(1, s.powderMax), Color(200, 190, 80), "ПОРОШОК", s.powder, s.powderMax)
            local link = s.hydrant and "гидрант: СВЯЗАН — можно качать" or "гидрант: нет связи (откройте E рядом или «Связать»)"
            local cab = s.cabinet and "  ·  шкаф рядом" or ""
            draw.SimpleText(link .. cab, "GRMFirePump_N", 0, 110, s.hydrant and Color(80, 220, 140) or Color(255, 170, 80))
            draw.SimpleText("рукава " .. (s.hoses or 0) .. "/" .. (s.hosesMax or 4) .. "   ствол: " .. tostring(s.agent or "water"), "GRMFirePump_N", 0, 130, Color(200, 205, 215))
        end

        local busy = 0
        local function act(a, extra)
            if CurTime() < busy then return end
            busy = CurTime() + 0.25
            net.Start(NET_ACT)
                net.WriteString(a)
                net.WriteString(extra or "")
            net.SendToServer()
        end

        local function mk(txt, col)
            local b = vgui.Create("DButton", body)
            b:Dock(TOP) b:SetTall(30) b:DockMargin(0, 4, 0, 0)
            b:SetText(txt) b:SetTextColor(color_white)
            b._col = col
            b.Paint = function(self, w, h)
                local c = self._col or col
                if self:IsHovered() then c = Color(math.min(255, c.r + 25), math.min(255, c.g + 25), math.min(255, c.b + 25)) end
                draw.RoundedBox(5, 0, 0, w, h, c)
            end
            return b
        end

        local spacer = vgui.Create("DPanel", body)
        spacer:Dock(TOP) spacer:SetTall(148) spacer:SetPaintBackground(false)

        local bTake = mk("ВЗЯТЬ РУКАВ / СТВОЛ С МАШИНЫ", Color(210, 55, 30))
        bTake:SetTall(38)
        bTake.DoClick = function() act("take") end
        local bRew = mk("Смотать рукава на катушку", Color(90, 80, 50))
        bRew.DoClick = function() act("rewind") end
        local bLink = mk("Связать машину с гидрантом", Color(40, 120, 90))
        bLink.DoClick = function() act("link") end

        local bW = mk("Ствол: ВОДА", Color(40, 110, 190))
        bW.DoClick = function() act("agent", "water") end
        local bF = mk("Ствол: ПЕНА", Color(170, 50, 50))
        bF.DoClick = function() act("agent", "foam") end
        local bP = mk("Ствол: ПОРОШОК", Color(150, 140, 40))
        bP.DoClick = function() act("agent", "powder") end

        frame._btnPump = mk("Насос: ВКЛЮЧИТЬ", Color(70, 90, 110))
        frame._btnPump.DoClick = function() act("pump") end
        frame._btnFill = mk("Закачка с гидранта / шкафа", Color(50, 130, 160))
        frame._btnFill.DoClick = function() act("fill") end
        frame._btnFeed = mk("Прямая подача с гидранта: выкл", Color(90, 70, 40))
        frame._btnFeed.DoClick = function() act("feed") end
        local bD = mk("Слить выбранный бак", Color(140, 50, 50))
        bD.DoClick = function()
            local s = live(frame._st)
            act("drain", s.agent or "water")
        end

        applyFlags(frame, st)
    end

    net.Receive(NET_DATA, function()
        local st = net.ReadTable() or {}
        if IsValid(frame) then
            frame._st = st
            applyFlags(frame, st)
            return
        end
        openUI(st)
    end)

    hook.Add("PlayerButtonDown", "GRM_FirePump_GKey", function(ply, button)
        if button ~= KEY_G then return end
        if ply ~= LocalPlayer() then return end
        if CurTime() < lastG then return end
        lastG = CurTime() + 0.35
        if gui.IsConsoleVisible and gui.IsConsoleVisible() then return end
        if IsValid(vgui.GetKeyboardFocus()) and vgui.GetKeyboardFocus():GetClassName() == "DTextEntry" then return end

        if IsValid(frame) then
            closeUI()
            return
        end

        -- Только у насоса / пожарной машины. Дежурство само по себе G не крадёт
        -- (иначе у банкомата всплывает и насос, и ошибка инкассации).
        if F.IsFireGContext then
            if not F.IsFireGContext(ply) then return end
        else
            local tr = ply:GetEyeTrace()
            local hit = IsValid(tr.Entity) and tr.Entity or nil
            if IsValid(hit) then
                local cls = hit:GetClass() or ""
                if cls == "grm_bank_terminal" or cls == "grm_bank_vault" then return end
                if cls ~= "grm_fire_pump" and not (hit.GetNWBool and hit:GetNWBool("GRM_FireTruck", false)) then
                    local near = false
                    for _, e in ipairs(ents.FindInSphere(ply:GetPos(), 260)) do
                        if IsValid(e) and e:GetClass() == "grm_fire_pump" then near = true break end
                    end
                    if not near then return end
                end
            else
                local near = false
                for _, e in ipairs(ents.FindInSphere(ply:GetPos(), 260)) do
                    if IsValid(e) and e:GetClass() == "grm_fire_pump" then near = true break end
                end
                if not near then return end
            end
        end
        net.Start(NET_OPEN)
        net.SendToServer()
    end)

    print("[GRM Fire] Pump UI client loaded")
end
