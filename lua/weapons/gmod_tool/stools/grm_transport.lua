--[[--------------------------------------------------------------------
    GRM: транспорт — ЕДИНЫЙ инструмент гаражей, мест выдачи и дилеров.
    Заменяет прежние «GRM: гаражи» и «Точка выдачи транспорта» (удалены).

    ЧТО ВИДНО В РУКАХ С ИНСТРУМЕНТОМ:
      • все гаражи карты — рамкой, с названием, типом и счётчиками;
      • каждое место выдачи — коробкой машины со стрелкой направления и
        подписью «свободно / занято»;
      • стойки вызова и дилеры — своими метками, у дилера линия к гаражу,
        к которому приписаны его покупки;
      • при разметке зоны первый угол подсвечивается, а будущая зона
        рисуется прямо по курсору — видно, что получится, ДО второго клика;
      • внизу экрана всегда подсказка: что делает ЛКМ, ПКМ и R в этом режиме.

    ПОРЯДОК РАБОТЫ:
      1. «Зона гаража» — ЛКМ первый угол, ЛКМ второй угол.
      2. «Место выдачи» — ЛКМ внутри зоны (ставьте столько, сколько машин
         должно разъезжаться одновременно).
      3. «Стойка вызова» — ЛКМ по поверхности.
      4. «Ворота» — ЛКМ по двери.
      5. «Дилер» — ЛКМ поставить, ПКМ — ассортимент и цены.
      6. «Связать дилера» — ПКМ по дилеру: его покупки приписываются к
         выбранному гаражу.
    ПКМ по земле — выбрать гараж под ногами. R — удалить (см. подсказку).
----------------------------------------------------------------------]]

TOOL.Category = "GRM"
TOOL.Name = "#tool.grm_transport.name"
TOOL.Command = nil
TOOL.ConfigName = ""
TOOL.ClientConVar = {
    mode      = "zone",
    name      = "Городской гараж",
    kind      = "public",
    faction   = "",
    fee       = "0",
    lift      = "10",
    direction = "look",
    slotname  = "",
    dealer    = "Автосалон",
    model     = "models/Humans/Group02/male_07.mdl",
}

local NET_REQ  = "GRM_Transport_ToolReq"
local NET_DATA = "GRM_Transport_ToolData"

local MODES = {
    { key = "zone",     label = "Зона гаража (2 клика по углам)",
      lmb = "первый / второй угол зоны", rmb = "выбрать гараж под ногами", r = "Shift+R — удалить гараж" },
    { key = "slot",     label = "Место выдачи машины",
      lmb = "поставить место в выбранном гараже", rmb = "выбрать гараж", r = "удалить ближайшее место" },
    { key = "terminal", label = "Стойка вызова",
      lmb = "поставить стойку", rmb = "выбрать гараж", r = "удалить ближайшую стойку" },
    { key = "door",     label = "Ворота гаража",
      lmb = "привязать дверь к гаражу", rmb = "выбрать гараж", r = "—" },
    { key = "dealer",   label = "Дилер транспорта",
      lmb = "поставить дилера", rmb = "ассортимент и цены дилера", r = "удалить дилера" },
    { key = "link",     label = "Связать дилера с гаражом",
      lmb = "—", rmb = "привязать дилера к выбранному гаражу", r = "—" },
    { key = "dealerpoint", label = "Точка выдачи у дилера (без гаража)",
      lmb = "поставить точку выбранному дилеру", rmb = "выбрать дилера", r = "убрать точку у дилера" },
}

local function modeDef(key)
    for _, m in ipairs(MODES) do if m.key == key then return m end end
    return MODES[1]
end

local function G() return GRM and GRM.Garage end
local function VD() return GRM and GRM.VehicleDealer end

local function notify(ply, text, good)
    if not IsValid(ply) then return end
    if GRM and GRM.Notify then
        GRM.Notify(ply, text, good and 100 or 255, good and 220 or 150, good and 130 or 100)
    else
        ply:ChatPrint("[GRM] " .. tostring(text))
    end
end

local function isDealer(ent)
    return IsValid(ent) and ent:GetClass() == "sent_vehicle_dealer"
end

-----------------------------------------------------------------------
-- КЛИЕНТ: превью и подсказки
-----------------------------------------------------------------------
if CLIENT then
    language.Add("tool.grm_transport.name", "GRM: транспорт (гаражи и дилеры)")
    language.Add("tool.grm_transport.desc", "Гаражи, места выдачи, стойки, ворота и дилеры — одним тулом")
    language.Add("tool.grm_transport.0", "ЛКМ: поставить • ПКМ: выбрать гараж / дилера • R: удалить")

    surface.CreateFont("GRMTool_Head", { font = "Roboto", size = 20, weight = 800, extended = true })
    surface.CreateFont("GRMTool_Body", { font = "Roboto", size = 15, weight = 600, extended = true })
    surface.CreateFont("GRMTool_Small", { font = "Roboto", size = 13, weight = 500, extended = true })

    local data = { zones = {}, dealers = {} }
    net.Receive(NET_DATA, function() data = net.ReadTable() or { zones = {}, dealers = {} } end)

    local function toolActive()
        local ply = LocalPlayer()
        local wep = IsValid(ply) and ply:GetActiveWeapon()
        local active = IsValid(wep) and wep:GetClass() == "gmod_tool"
            and wep.GetMode and wep:GetMode() == "grm_transport"
        return active, ply, wep
    end

    local function curMode()
        local cv = GetConVar("grm_transport_mode")
        return cv and cv:GetString() or "zone"
    end

    -- первый угол зоны, поставленный этим клиентом (для живого превью)
    local corner = nil
    GRM = GRM or {}
    GRM.TransportToolCorner = function(v) corner = v end

    hook.Add("Think", "GRM_TransportTool_Request", function()
        local active, _, wep = toolActive()
        if active and (wep.GRMTransportNext or 0) < CurTime() then
            wep.GRMTransportNext = CurTime() + 1
            net.Start(NET_REQ) net.SendToServer()
        end
        if not active then corner = nil end
    end)

    local COL_ZONE   = Color(70, 170, 255, 210)
    local COL_SEL    = Color(245, 195, 65, 245)
    local COL_FREE   = Color(90, 220, 150, 235)
    local COL_BUSY   = Color(240, 110, 100, 235)
    local COL_TERM   = Color(255, 215, 120, 235)
    local COL_DEALER = Color(140, 220, 255, 235)

    local function label3D(pos, text, sub, col, scale)
        cam.Start3D2D(pos, Angle(0, EyeAngles().y - 90, 90), scale or 0.1)
            local w = math.max(260, string.len(text) * 11)
            draw.RoundedBox(6, -w / 2, -26, w, sub and 52 or 34, Color(10, 15, 22, 232))
            draw.SimpleText(text, "GRMTool_Head", 0, sub and -12 or -8, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            if sub then
                draw.SimpleText(sub, "GRMTool_Small", 0, 12, Color(195, 210, 230), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        cam.End3D2D()
    end

    hook.Add("PostDrawTranslucentRenderables", "GRM_TransportTool_Draw", function(depth, sky, sky3d)
        if depth or sky or sky3d then return end
        local active, ply = toolActive()
        if not active then return end
        local mode = curMode()

        for _, z in ipairs(data.zones or {}) do
            local mn, mx = Vector(z.min.x, z.min.y, z.min.z), Vector(z.max.x, z.max.y, z.max.z)
            local center = (mn + mx) * 0.5
            local col = z.selected and COL_SEL or COL_ZONE
            render.DrawWireframeBox(center, angle_zero, mn - center, mx - center, col, true)
            label3D(center + Vector(0, 0, (mx.z - mn.z) * 0.5 + 14),
                (z.selected and "ВЫБРАН ГАРАЖ: " or "ГАРАЖ: ") .. tostring(z.name),
                ("%s • мест выдачи %d • стоек %d • ворот %d"):format(tostring(z.kindName or ""),
                    z.slots or 0, z.terminals or 0, z.doors or 0), col, 0.1)

            for _, s in ipairs(z.slotList or {}) do
                local p = Vector(s.pos.x, s.pos.y, s.pos.z)
                local a = Angle(0, s.ang and s.ang.y or 0, 0)
                local scol = (s.free == false) and COL_BUSY or COL_FREE
                render.DrawWireframeBox(p + Vector(0, 0, 20), a, Vector(-52, -100, -18), Vector(52, 100, 22), scol, true)
                render.DrawLine(p + Vector(0, 0, 24), p + a:Forward() * 130 + Vector(0, 0, 24), Color(255, 190, 80, 240), true)
                label3D(p + Vector(0, 0, 66), tostring(s.name or "Место"),
                    (s.free == false) and "занято" or "свободно, машина встанет по стрелке", scol, 0.07)
            end

            for _, t in ipairs(z.terminalList or {}) do
                local p = Vector(t.pos.x, t.pos.y, t.pos.z)
                render.DrawWireframeBox(p + Vector(0, 0, 30), angle_zero, Vector(-20, -20, -30), Vector(20, 20, 40), COL_TERM, true)
                label3D(p + Vector(0, 0, 84), "СТОЙКА ВЫЗОВА", "меню гаража по [E]", COL_TERM, 0.06)
            end
        end

        for _, d in ipairs(data.dealers or {}) do
            local p = Vector(d.pos.x, d.pos.y, d.pos.z)
            render.DrawWireframeBox(p + Vector(0, 0, 36), angle_zero, Vector(-22, -22, -36), Vector(22, 22, 40), COL_DEALER, true)
            label3D(p + Vector(0, 0, 96), "ДИЛЕР: " .. tostring(d.name),
                d.garageName ~= "" and ("покупки → гараж «" .. d.garageName .. "»") or "гараж не привязан",
                COL_DEALER, 0.07)
            if d.spawnPos then
                local sp = Vector(d.spawnPos.x, d.spawnPos.y, d.spawnPos.z)
                local sa = Angle(0, d.spawnAng and d.spawnAng.y or 0, 0)
                render.DrawWireframeBox(sp + Vector(0, 0, 10), sa, Vector(-52, -100, -8), Vector(52, 100, 20),
                    Color(255, 185, 70, 235), true)
                render.DrawLine(sp + Vector(0, 0, 14), sp + sa:Forward() * 120 + Vector(0, 0, 14),
                    Color(255, 160, 50, 245), true)
                label3D(sp + Vector(0, 0, 56), "ТОЧКА ВЫДАЧИ ДИЛЕРА",
                    ("высота %d  •  машина встанет по стрелке"):format(math.floor(tonumber(d.lift) or 0)),
                    Color(255, 200, 110), 0.07)
            end
            if d.garageCenter then
                render.DrawLine(p + Vector(0, 0, 40),
                    Vector(d.garageCenter.x, d.garageCenter.y, d.garageCenter.z), COL_DEALER, true)
            end
        end

        -- живое превью зоны: первый угол + то, что получится по курсору
        if mode == "zone" and corner and IsValid(ply) then
            local tr = ply:GetEyeTrace()
            local a, b = corner, tr.HitPos
            local mn = Vector(math.min(a.x, b.x), math.min(a.y, b.y), math.min(a.z, b.z))
            local mx = Vector(math.max(a.x, b.x), math.max(a.y, b.y), math.max(a.z, b.z) + 180)
            local center = (mn + mx) * 0.5
            render.DrawWireframeBox(center, angle_zero, mn - center, mx - center, Color(120, 255, 160, 245), true)
            render.DrawWireframeSphere(a, 12, 8, 8, Color(255, 230, 120, 250), true)
            local side = math.min(mx.x - mn.x, mx.y - mn.y)
            label3D(center + Vector(0, 0, (mx.z - mn.z) * 0.5 + 10), "НОВАЯ ЗОНА ГАРАЖА",
                ("%d x %d юнитов%s"):format(mx.x - mn.x, mx.y - mn.y,
                    side < 200 and "  •  МАЛО: нужна сторона от 200" or "  •  ЛКМ — подтвердить"),
                side < 200 and Color(255, 140, 120) or Color(120, 255, 160), 0.09)
        end
    end)

    --[[ Подсказка на экране: что делает каждая кнопка ИМЕННО СЕЙЧАС.
         Без неё порядок работы приходилось помнить наизусть. ]]
    hook.Add("HUDPaint", "GRM_TransportTool_HUD", function()
        local active = toolActive()
        if not active then return end
        local m = modeDef(curMode())
        local lines = {
            { "ЛКМ", m.lmb },
            { "ПКМ", m.rmb },
            { "R", m.r },
        }
        local w, h = 520, 34 + #lines * 22
        local x, y = 24, ScrH() - h - 120
        draw.RoundedBox(8, x, y, w, h, Color(12, 16, 24, 226))
        draw.RoundedBox(0, x, y, 4, h, Color(245, 195, 65))
        draw.SimpleText("GRM: ТРАНСПОРТ — " .. string.upper(m.label), "GRMTool_Body", x + 14, y + 8,
            Color(245, 205, 90), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        for i, l in ipairs(lines) do
            draw.SimpleText(l[1], "GRMTool_Small", x + 14, y + 28 + (i - 1) * 22, Color(150, 200, 255), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText(l[2], "GRMTool_Small", x + 60, y + 28 + (i - 1) * 22, Color(225, 233, 245), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end
        if curMode() == "zone" and corner then
            draw.SimpleText("Первый угол поставлен — кликните второй", "GRMTool_Small", x + w - 14, y + 8,
                Color(120, 255, 160), TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
        end
    end)

    function TOOL.BuildCPanel(panel)
        panel:AddControl("Header", { Description =
            "Один инструмент на весь транспорт: зона гаража, его МЕСТА ВЫДАЧИ, стойка, ворота и дилеры.\n" ..
            "Машины (личные и служебные) появляются по местам выдачи, а не в одной точке.\n" ..
            "Всё, что уже размечено, видно рамками и подписями прямо в мире." })

        local mode = panel:ComboBox("ЧТО СТАВИМ", "grm_transport_mode")
        for _, m in ipairs(MODES) do mode:AddChoice(m.label, m.key) end

        panel:Help("")
        panel:ControlHelp("ГАРАЖ")
        panel:TextEntry("Название гаража", "grm_transport_name")
        local kind = panel:ComboBox("Тип гаража", "grm_transport_kind")
        kind:AddChoice("Городской — пускает всех", "public")
        kind:AddChoice("Ведомственный — только своя организация", "faction")
        kind:AddChoice("Личный — только владелец", "private")
        local facCombo = panel:ComboBox("Организация (для ведомственного)", "grm_transport_faction")
        facCombo:AddChoice("— не выбрана —", "")
        local function fillFac(rows)
            if not IsValid(facCombo) then return end
            local cur = GetConVar("grm_transport_faction")
            local keep = cur and cur:GetString() or ""
            facCombo:Clear()
            facCombo:AddChoice("— не выбрана —", "")
            for _, row in ipairs(istable(rows) and rows or {}) do
                facCombo:AddChoice(row.name .. (row.key ~= row.name and ("  [" .. row.key .. "]") or ""), row.key)
            end
            if keep ~= "" then facCombo:SetValue(keep) end
        end
        hook.Add("GRM_CompAccess_List", facCombo, function(_, rows) fillFac(rows) end)
        if GRM.CompAccess and istable(GRM.CompAccess.Rows) then fillFac(GRM.CompAccess.Rows) end
        net.Start("GRM_CompAccess_ListReq") net.SendToServer()
        panel:NumSlider("Плата за выезд", "grm_transport_fee", 0, 5000, 0)

        panel:Help("")
        panel:ControlHelp("МЕСТО ВЫДАЧИ")
        panel:TextEntry("Название места (необязательно)", "grm_transport_slotname")
        local dir = panel:ComboBox("Куда смотрит машина", "grm_transport_direction")
        dir:AddChoice("По взгляду при установке", "look")
        dir:AddChoice("Вперёд от дилера", "forward")
        dir:AddChoice("Назад от дилера", "back")
        dir:AddChoice("Влево от дилера", "left")
        dir:AddChoice("Вправо от дилера", "right")
        dir:AddChoice("Север (0°)", "north")
        dir:AddChoice("Восток (90°)", "east")
        dir:AddChoice("Юг (180°)", "south")
        dir:AddChoice("Запад (270°)", "west")
        panel:NumSlider("Высота появления над землёй", "grm_transport_lift", 0, 100, 0)

        panel:Help("")
        panel:ControlHelp("ДИЛЕР")
        panel:TextEntry("Название дилера", "grm_transport_dealer")
        panel:TextEntry("Модель дилера", "grm_transport_model")
        panel:ControlHelp("Точка выдачи у дилера ставится режимом «Точка выдачи у дилера»: " ..
            "ПКМ по дилеру — выбрать, ЛКМ по земле — поставить, R — убрать. " ..
            "Если дилер связан с гаражом, машины всё равно выдаются по местам гаража.")

        panel:Help("ПОРЯДОК: зона → места выдачи (сколько нужно) → стойка → ворота.\n" ..
            "Дилер: поставить, ПКМ — ассортимент, режим «Связать» — приписать его покупки к гаражу.\n" ..
            "Служебная техника закупается организацией в /автопарк и выдаётся в её гараже.")
    end
end

-----------------------------------------------------------------------
-- СЕРВЕР: данные для превью
-----------------------------------------------------------------------
if SERVER then
    util.AddNetworkString(NET_REQ)
    util.AddNetworkString(NET_DATA)

    net.Receive(NET_REQ, function(_, ply)
        local g = G()
        if not (IsValid(ply) and ply:IsSuperAdmin() and g) then return end
        local selected = ply.GRMGarageSelected
        local out = { zones = {}, dealers = {} }

        for _, rec in pairs(g.Garages or {}) do
            local slotList = {}
            for _, s in ipairs(g.SlotState and g.SlotState(rec) or {}) do
                local src
                for _, raw in ipairs(rec.slots or {}) do if raw.id == s.id then src = raw break end end
                slotList[#slotList + 1] = { name = s.name, free = s.free, pos = s.pos, ang = src and src.ang or { y = 0 } }
            end
            local terminalList = {}
            for _, t in ipairs(rec.terminals or {}) do terminalList[#terminalList + 1] = { pos = t.pos } end
            out.zones[#out.zones + 1] = {
                id = rec.id, name = rec.name, kindName = g.KindName(rec.kind),
                min = rec.zone.min, max = rec.zone.max,
                slots = #(rec.slots or {}), terminals = #(rec.terminals or {}), doors = #(rec.doors or {}),
                selected = selected == rec.id,
                slotList = slotList, terminalList = terminalList,
            }
        end

        for _, ent in ipairs(ents.FindByClass("sent_vehicle_dealer")) do
            if IsValid(ent) then
                local dealerID = ent.GetDealerID and ent:GetDealerID() or ""
                local homeName, homeCenter = "", nil
                for _, rec in pairs(g.Garages or {}) do
                    for _, linked in ipairs(rec.linkedDealers or {}) do
                        if tostring(linked) == tostring(dealerID) then
                            homeName = rec.name
                            local c = g.ZoneCenter(rec)
                            homeCenter = { x = c.x, y = c.y, z = c.z }
                        end
                    end
                end
                local p = ent:GetPos()
                local sp, sa, lift = nil, nil, 0
                if ent.GetHasCustomSpawn and ent:GetHasCustomSpawn() and ent.GetSpawnPos then
                    local v = ent:GetSpawnPos()
                    local a = ent.GetSpawnAngle and ent:GetSpawnAngle() or Angle(0, 0, 0)
                    sp = { x = v.x, y = v.y, z = v.z }
                    sa = { p = a.p, y = a.y, r = a.r }
                    lift = ent.GetSpawnLift and ent:GetSpawnLift() or 0
                end
                out.dealers[#out.dealers + 1] = {
                    name = ent.GetDealerName and ent:GetDealerName() or "Дилер",
                    pos = { x = p.x, y = p.y, z = p.z },
                    garageName = homeName, garageCenter = homeCenter,
                    spawnPos = sp, spawnAng = sa, lift = lift,
                }
            end
        end

        net.Start(NET_DATA) net.WriteTable(out) net.Send(ply)
    end)
end

-----------------------------------------------------------------------
-- ОБЩЕЕ
-----------------------------------------------------------------------
--[[ Куда встанет машина. Кроме сторон света есть направления ОТНОСИТЕЛЬНО
     дилера — так удобнее ставить точку выдачи у самого салона. ]]
local function yawFor(tool, ply, relativeTo)
    local dir = tool:GetClientInfo("direction") or "look"
    if dir == "north" then return 0 end
    if dir == "east" then return 90 end
    if dir == "south" then return 180 end
    if dir == "west" then return 270 end
    if IsValid(relativeTo) then
        local base = relativeTo:GetAngles().y
        if dir == "forward" then return base end
        if dir == "back" then return base + 180 end
        if dir == "left" then return base - 90 end
        if dir == "right" then return base + 90 end
    end
    return ply:EyeAngles().y
end

local function selectedGarage(ply)
    local g = G()
    if not g then return nil end
    local id = ply.GRMGarageSelected
    local rec = id and g.Get and g.Get(id) or nil
    if rec then return rec end
    return g.FindByPos and g.FindByPos(ply:GetPos()) or nil
end

function TOOL:LeftClick(trace)
    local mode = self:GetClientInfo("mode") or "zone"

    -- клиентская половина: помним первый угол, чтобы рисовать превью зоны
    if CLIENT then
        if mode == "zone" and IsFirstTimePredicted() then
            if self.GRMCornerCL then
                self.GRMCornerCL = nil
                if GRM and GRM.TransportToolCorner then GRM.TransportToolCorner(nil) end
            else
                self.GRMCornerCL = trace.HitPos
                if GRM and GRM.TransportToolCorner then GRM.TransportToolCorner(trace.HitPos) end
            end
        end
        return true
    end

    local ply = self:GetOwner()
    if not (IsValid(ply) and ply:IsSuperAdmin()) then return false end
    local g = G()
    if not g then notify(ply, "Модуль гаражей не загружен") return false end

    if mode == "zone" then
        if not self.GRMCorner then
            self.GRMCorner = trace.HitPos
            self:SetStage(1)
            notify(ply, "Первый угол зоны поставлен. Кликните второй — рамку видно по курсору.", true)
            return true
        end
        local first, second = self.GRMCorner, trace.HitPos
        self.GRMCorner = nil
        self:SetStage(0)
        local ok, rec = g.Create(ply, first, second, {
            name = self:GetClientInfo("name"),
            kind = self:GetClientInfo("kind"),
            faction = self:GetClientInfo("faction"),
            fee = tonumber(self:GetClientInfo("fee")) or 0,
        })
        if not ok then notify(ply, tostring(rec)) return false end
        ply.GRMGarageSelected = rec.id
        notify(ply, ("Гараж «%s» создан и выбран. Теперь ставьте МЕСТА ВЫДАЧИ."):format(rec.name), true)
        return true
    end

    if mode == "dealerpoint" then
        --[[ Личная точка выдачи дилера: нужна там, где гаража нет вовсе
             (одиночный автосалон у дороги). Если дилер связан с гаражом,
             машины всё равно поедут по местам гаража. ]]
        local vd = VD()
        if not vd then notify(ply, "Модуль дилеров не загружен") return false end
        local dealerEnt = self.GRMDealer
        if not isDealer(dealerEnt) then
            notify(ply, "Сначала ПКМ по дилеру — выбрать, кому ставим точку.")
            return false
        end
        local okPoint, why = vd.SetSpawnPoint(dealerEnt, trace.HitPos, Angle(0, yawFor(self, ply, dealerEnt), 0),
            tonumber(self:GetClientInfo("lift")) or 30)
        notify(ply, okPoint and ("Точка выдачи дилера «%s» сохранена."):format(dealerEnt:GetDealerName())
            or tostring(why or "Не удалось сохранить точку"), okPoint)
        return okPoint == true
    end

    if mode == "dealer" then
        local vd = VD()
        if not vd then notify(ply, "Модуль дилеров не загружен") return false end
        local ent = ents.Create("sent_vehicle_dealer")
        if not IsValid(ent) then return false end
        ent:SetPos(trace.HitPos + trace.HitNormal)
        ent:SetAngles(Angle(0, ply:EyeAngles().y + 180, 0))
        ent:SetDealerName(self:GetClientInfo("dealer"))
        local model = self:GetClientInfo("model")
        if util.IsValidModel(model) then ent:SetDealerModel(model) end
        ent:Spawn()
        ent:Activate()
        local ok, id = vd.SaveDealer(ent)
        notify(ply, ok and ("Дилер создан: " .. tostring(id) .. ". Режим «Связать» — приписать его покупки к гаражу.")
            or "Ошибка сохранения дилера", ok)
        return true
    end

    local rec = selectedGarage(ply)
    if not rec then notify(ply, "Сначала встаньте в зону гаража или выберите его ПКМ.") return false end

    if mode == "slot" then
        local ok, slot = g.AddSlot(rec.id, trace.HitPos, Angle(0, yawFor(self, ply), 0),
            tonumber(self:GetClientInfo("lift")) or 10, self:GetClientInfo("slotname"))
        if not ok then notify(ply, tostring(slot)) return false end
        notify(ply, ("Место «%s» добавлено. Всего мест выдачи: %d."):format(slot.name, #(rec.slots or {})), true)
        return true
    end

    if mode == "terminal" then
        local ok, term = g.AddTerminal(rec.id, trace.HitPos + trace.HitNormal * 2,
            Angle(0, ply:EyeAngles().y + 180, 0))
        if not ok then notify(ply, tostring(term)) return false end
        notify(ply, ("Стойка вызова поставлена у гаража «%s»."):format(rec.name), true)
        return true
    end

    if mode == "door" then
        local door = trace.Entity
        if not (IsValid(door) and GRM.Doors and GRM.Doors.IsDoor and GRM.Doors.IsDoor(door)) then
            notify(ply, "Наведитесь на дверь или ворота.")
            return false
        end
        local doorID = GRM.Doors.GetDoorID and GRM.Doors.GetDoorID(door) or ""
        local ok, msg = g.LinkDoor(rec.id, doorID)
        notify(ply, tostring(msg), ok)
        return ok == true
    end

    if mode == "link" then
        notify(ply, "В режиме «Связать» жмите ПКМ по дилеру.")
        return false
    end

    return false
end

function TOOL:RightClick(trace)
    if CLIENT then return true end
    local ply = self:GetOwner()
    if not (IsValid(ply) and ply:IsSuperAdmin()) then return false end
    local g = G()
    if not g then return false end

    if isDealer(trace.Entity) then
        local mode = self:GetClientInfo("mode") or "zone"
        if mode == "dealerpoint" then
            self.GRMDealer = trace.Entity
            notify(ply, ("Выбран дилер «%s». ЛКМ по земле — точка выдачи."):format(trace.Entity:GetDealerName()), true)
            return true
        end
        if mode == "link" then
            local rec = selectedGarage(ply)
            if not rec then notify(ply, "Сначала выберите гараж (ПКМ по земле в его зоне).") return false end
            local ok, msg = g.LinkDealer(rec.id, trace.Entity:GetDealerID())
            notify(ply, tostring(msg), ok)
            return ok == true
        end
        local vd = VD()
        if not vd then return false end
        net.Start("GRM_VD_AdminOpen")
            net.WriteEntity(trace.Entity)
            net.WriteTable({
                name = trace.Entity:GetDealerName(), model = trace.Entity:GetDealerModel(),
                vehicles = trace.Entity.VD_Vehicles or {},
                hasSpawn = trace.Entity:GetHasCustomSpawn(), hasSpawnZone = trace.Entity:GetHasSpawnZone(),
                delivery = GRM.VehicleDealer.DeliveryMode(trace.Entity),
                showRetrieve = GRM.VehicleDealer.ShowRetrieve(trace.Entity),
                spawnPos = trace.Entity:GetSpawnPos(), spawnAng = trace.Entity:GetSpawnAngle(),
                available = GRM.VehicleDealer.AllVehicleClasses(),
                factions = GRM.VehicleDealer.FactionList(),
                categories = GRM.VehicleDealer.CategoryList(trace.Entity.VD_Vehicles or {}),
            })
        net.Send(ply)
        return true
    end

    --[[ ПКМ по двери объекта недвижимости: гараж продаётся вместе с домом.
         Раньше это умел старый тул — переносим, чтобы ничего не потерять. ]]
    local door = trace.Entity
    if IsValid(door) and GRM.Doors and GRM.Doors.IsDoor and GRM.Doors.IsDoor(door) then
        local sel = selectedGarage(ply)
        local doorID = GRM.Doors.GetDoorID and GRM.Doors.GetDoorID(door) or ""
        local property = GRM.Property and GRM.Property.GetByDoor and GRM.Property.GetByDoor(doorID) or nil
        if sel and property then
            local okLink, msg = g.LinkProperty(sel.id, property.id or property.ID or "")
            notify(ply, tostring(msg or (okLink and "Гараж привязан к объекту недвижимости" or "Не удалось")), okLink)
            return okLink == true
        end
    end

    local rec = g.FindByPos and g.FindByPos(trace.HitPos) or nil
    if not rec then notify(ply, "Здесь нет зоны гаража — встаньте внутрь рамки.") return false end
    ply.GRMGarageSelected = rec.id
    notify(ply, ("Выбран гараж «%s» (мест выдачи: %d)."):format(rec.name, #(rec.slots or {})), true)
    return true
end

function TOOL:Reload(trace)
    if CLIENT then return true end
    local ply = self:GetOwner()
    if not (IsValid(ply) and ply:IsSuperAdmin()) then return false end
    local g = G()
    if not g then return false end

    local mode = self:GetClientInfo("mode") or "zone"

    if mode == "dealerpoint" then
        local vd = VD()
        local ent = isDealer(trace.Entity) and trace.Entity or self.GRMDealer
        if not (vd and isDealer(ent)) then notify(ply, "Наведитесь на дилера.") return false end
        local okClear = vd.ClearSpawnPoint(ent)
        notify(ply, okClear and "Точка выдачи убрана — машины поедут в гараж дилера."
            or "Не удалось убрать точку", okClear)
        return okClear == true
    end

    if mode == "dealer" then
        local ent = trace.Entity
        if not isDealer(ent) then notify(ply, "Наведитесь на дилера.") return false end
        local vd = VD()
        if vd and vd.DeleteDealer then
            ent.VD_PermanentDelete = true
            vd.DeleteDealer(ent)
        end
        ent:Remove()
        notify(ply, "Дилер удалён из карты и базы.", true)
        return true
    end

    if mode == "slot" then
        local ok, msg = g.RemoveNearestSlot(trace.HitPos, 200)
        notify(ply, tostring(msg or (ok and "Место удалено" or "Рядом нет места")), ok)
        return ok == true
    end

    if mode == "terminal" then
        local ent = trace.Entity
        if IsValid(ent) and ent:GetClass() == "grm_garage_terminal" and g.RemoveTerminalByID then
            local id = ent.GetTerminalID and ent:GetTerminalID() or (ent.GRMTerminalID or "")
            local okT, msgT = g.RemoveTerminalByID(id)
            if not okT then
                ent:Remove()
                notify(ply, "Стойка без записи удалена с карты", true)
                return true
            end
            notify(ply, tostring(msgT or "Стойка удалена"), true)
            return true
        end
        local ok, msg = g.RemoveNearestTerminal(trace.HitPos, 200)
        notify(ply, tostring(msg or (ok and "Стойка удалена" or "Рядом нет стойки")), ok)
        return ok == true
    end

    if mode == "zone" then
        if not ply:KeyDown(IN_SPEED) then
            if self.GRMCorner then
                self.GRMCorner = nil
                self:SetStage(0)
                notify(ply, "Разметка зоны отменена.", true)
                return true
            end
            notify(ply, "Shift+R по зоне — удалить гараж.")
            return false
        end
        local rec = g.FindByPos(trace.HitPos)
        if not rec then notify(ply, "Здесь нет гаража.") return false end
        local ok, msg = g.Remove(rec.id, ply)
        notify(ply, tostring(msg or (ok and "Гараж удалён" or "Не удалось")), ok)
        return ok == true
    end

    notify(ply, "R удаляет: место (режим «Место выдачи»), стойку, дилера; Shift+R в режиме зоны — гараж.")
    return false
end
