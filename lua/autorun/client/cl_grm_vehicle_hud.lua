-- Свой приборник: скорость, топливо, прочность, места.
if not CLIENT then return end

GRM = GRM or {}
GRM.Fuel = GRM.Fuel or {}

local function hideStock()
    local cmds = {
        "cl_simfphys_hud", "0",
        "cl_simfphys_healthtips", "0",
        "cl_simfphys_ms_cursor", "0",
        "lvs_showhud", "0",
        "lvs_hud", "0",
        "cl_lvs_hud", "0",
    }
    for i = 1, #cmds, 2 do
        if ConVarExists(cmds[i]) then RunConsoleCommand(cmds[i], cmds[i + 1]) end
    end
end
hook.Add("InitPostEntity", "GRM_VehHUD_HideStock", hideStock)
timer.Create("GRM_VehHUD_HideStock", 12, 2, hideStock)

hook.Add("HUDShouldDraw", "GRM_VehHUD_HideNames", function(name)
    local lp = LocalPlayer()
    if not IsValid(lp) or not lp.InVehicle or not lp:InVehicle() then return end
    if name == "CHudHealth" or name == "CHudBattery" or name == "CHudDamageIndicator" then
        return false
    end
end)

surface.CreateFont("GRMVeh_Big", { font = "Roboto", size = 28, weight = 800, extended = true })
surface.CreateFont("GRMVeh_Mid", { font = "Roboto", size = 15, weight = 700, extended = true })
surface.CreateFont("GRMVeh_Sm", { font = "Roboto", size = 12, weight = 600, extended = true })
surface.CreateFont("GRMVeh_Seat", { font = "Roboto", size = 13, weight = 600, extended = true })

--[[ Корневой транспорт сиденья. Возвращает nil для обычного стула:
     раньше фолбэк отдавал сам стул, и приборник simfphys рисовался при
     посадке в любое кресло (находка 27.08). ]]
local function rootVeh(ent)
    if GRM.Fuel and GRM.Fuel.RootVehicle then return GRM.Fuel.RootVehicle(ent) end
    if not IsValid(ent) then return nil end
    local parent = ent:GetParent()
    if IsValid(parent) then return parent end
    -- Без модуля топлива опознаём транспорт по явным признакам баз.
    if ent.IsSimfphysCar or ent.LVS or ent.IsLVSVehicle or ent.IsGlideVehicle then return ent end
    local cls = string.lower(ent:GetClass() or "")
    if cls == "prop_vehicle_jeep" or cls == "prop_vehicle_airboat" then return ent end
    return nil
end

--[[ Палитра HUD транспорта. Все цвета постоянные и создаются один раз
     при загрузке файла: этот модуль перерисовывается каждый кадр, и любой
     Color() внутри хука = мусорная таблица на кадр (§6.1.8). У каждого
     цвета свой смысл — не «общие серые». ]]
local COL_PANEL = Color(10, 14, 22, 230)         -- фон кластера и плашки HP
local COL_SEAT_CARD = Color(10, 14, 22, 228)     -- карточка мест
local COL_BIG = Color(235, 242, 250)             -- цифры скорости
local COL_DIM = Color(140, 160, 180)              -- подписи единиц, «бак не привязан»
local COL_GOOD = Color(90, 200, 120)              -- двигатель вкл, место свободно
local COL_ENG_OFF = Color(200, 140, 90)           -- двигатель выкл
local COL_FUEL_TYPE = Color(250, 185, 63)          -- название вида топлива
local COL_FUEL_OK = Color(240, 170, 50)            -- заполнение бака в норме
local COL_FUEL_NUM = Color(210, 220, 230)          -- литры цифрами
local COL_DANGER = Color(220, 70, 50)              -- критический остаток (бак, HP)
local COL_BROKEN = Color(230, 80, 70)               -- «ПОЛОМКА» и «НЕТ ТОПЛИВА»
local COL_HP_LBL = Color(180, 195, 210)             -- подпись «прочность»
local COL_HP_NUM = Color(200, 210, 220)             -- HP цифрами
local COL_SEAT_TITLE = Color(180, 200, 215)          -- заголовок карточки мест
local COL_SEAT_FREE_N = Color(130, 150, 165)         -- счётчик свободных мест
local COL_SEAT_ROW = Color(220, 228, 236)             -- ярлык ряда
local COL_SEAT_OCCUPIED = Color(230, 160, 90)         -- занятый ряд
local HP_WARM = Color(230, 190, 50)                   -- 50% прочности (низ градиента)
local HP_GOOD = Color(70, 200, 95)                    -- 100% прочности
local HP_CRIT = Color(210, 45, 40)                    -- <22% — плоско, без смешения
local HP_FILL = Color(0, 0, 0, 255)                   -- скретч результата смешения:
                                                      -- бар красится сразу после расчёта

local function lerpColInto(dst, a, b, t)
    t = math.Clamp(t, 0, 1)
    -- округление к целому: движок ждёт целые компоненты цвета
    dst.r = math.floor(a.r + (b.r - a.r) * t + 0.5)
    dst.g = math.floor(a.g + (b.g - a.g) * t + 0.5)
    dst.b = math.floor(a.b + (b.b - a.b) * t + 0.5)
    dst.a = 255
    return dst
end

local function hpColor(pct)
    if pct >= 0.5 then
        return lerpColInto(HP_FILL, HP_WARM, HP_GOOD, (pct - 0.5) / 0.5)
    end
    if pct >= 0.22 then
        return lerpColInto(HP_FILL, COL_DANGER, HP_WARM, (pct - 0.22) / 0.28)
    end
    return HP_CRIT
end

local function addSeat(list, seen, seat, driver)
    if not IsValid(seat) then return end
    if not seat.IsVehicle or not seat:IsVehicle() then return end
    local id = seat:EntIndex()
    if seen[id] then
        if driver then seen[id].driver = true end
        return
    end
    local row = { seat = seat, driver = driver and true or false }
    seen[id] = row
    list[#list + 1] = row
end

local function pullValue(list, seen, val, driver)
    if IsValid(val) then
        addSeat(list, seen, val, driver)
        return
    end
    if not istable(val) then return end
    for _, v in pairs(val) do
        if IsValid(v) then addSeat(list, seen, v, driver)
        elseif istable(v) then pullValue(list, seen, v, driver) end
    end
end

local function callM(ent, name)
    if not IsValid(ent) or not ent[name] then return nil end
    local ok, r = pcall(ent[name], ent)
    if ok then return r end
    return nil
end

local seatCache, seatCacheT, seatCacheEnt = {}, 0, NULL

local function collectSeats(veh)
    if not IsValid(veh) then return {} end
    if seatCacheEnt == veh and CurTime() - seatCacheT < 0.35 then return seatCache end
    local list, seen = {}, {}
    local drv = callM(veh, "GetDriverSeat") or callM(veh, "GetDriverSeatEntity") or veh.DriverSeat or veh.driverSeat
    if istable(drv) then drv = drv[1] or drv.Entity end
    pullValue(list, seen, drv, true)
    pullValue(list, seen, callM(veh, "GetPassengerSeats"), false)
    pullValue(list, seen, veh.pSeat, false)
    pullValue(list, seen, veh.pSeats, false)
    pullValue(list, seen, veh.PassengerSeats, false)
    for _, ch in ipairs(veh:GetChildren()) do
        if IsValid(ch) and ch.IsVehicle and ch:IsVehicle() then
            addSeat(list, seen, ch, false)
        end
    end
    -- Шасси simfphys/LVS — не место. Ваниль без подов — само ТС = водитель.
    local simLike = veh.IsSimfphysCar or veh.LVS or veh.IsLVSVehicle or IsValid(drv)
    if not simLike and veh.IsVehicle and veh:IsVehicle() then
        addSeat(list, seen, veh, true)
    end
    -- Ровно один водитель.
    for i = 1, #list do
        list[i].driver = (IsValid(drv) and list[i].seat == drv) or false
    end
    local hasDriver = false
    for i = 1, #list do
        if list[i].driver then hasDriver = true break end
    end
    if not hasDriver and #list > 0 then list[1].driver = true end
    -- Выкинуть шасси, если оно попало в список вместе с подами.
    local cleaned = {}
    for i = 1, #list do
        if list[i].seat ~= veh or #list == 1 then
            cleaned[#cleaned + 1] = list[i]
        end
    end
    list = cleaned
    table.sort(list, function(a, b)
        if a.driver ~= b.driver then return a.driver end
        return a.seat:EntIndex() < b.seat:EntIndex()
    end)
    seatCache, seatCacheT, seatCacheEnt = list, CurTime(), veh
    return list
end

local function occupantName(seat)
    if not IsValid(seat) then return nil end
    local d
    if seat.GetDriver then
        local ok, r = pcall(seat.GetDriver, seat)
        if ok then d = r end
    end
    if not IsValid(d) and seat.GetPassenger then
        local ok, r = pcall(seat.GetPassenger, seat)
        if ok then d = r end
    end
    if IsValid(d) and d.IsPlayer and d:IsPlayer() then
        return d:Nick()
    end
    return nil
end

local function vehTitle(veh)
    local n
    if veh.GetVehicleName then
        local ok, r = pcall(veh.GetVehicleName, veh)
        if ok then n = r end
    end
    if (not isstring(n) or n == "") and isstring(veh.VehicleName) then n = veh.VehicleName end
    -- Имена с клеймом сторонних паков техники отсекает общий фильтр VK.CleanName
    -- (sh_vehicle_keys; заказ владельца от 02.09.2026 — таких надписей не должно
    -- быть ни в одном модуле, и локальных списков слов здесь больше нет).
    -- Имя отфильтровано — показываем нейтральное «Салон».
    if isfunction(VK and VK.CleanName) then
        local clean = VK.CleanName(isstring(n) and n or nil)
        if clean then return clean end
    elseif isstring(n) and n ~= "" then
        return n
    end
    return "Салон"
end

local function drawHPBar(veh, x, y, w, h)
    local hp = veh:GetNWFloat("GRM_VehHP", -1)
    if hp < 0 then return false end
    local hpmax = math.max(1, veh:GetNWFloat("GRM_VehHPMax", 100))
    local broken = veh:GetNWBool("GRM_VehBroken", false)
    local pct = math.Clamp(hp / hpmax, 0, 1)
    local bx, by, bw, bh = x + 18, y + h - 20, w - 36, 10
    draw.SimpleText(broken and "ПОЛОМКА" or "прочность", "GRMVeh_Sm", bx, by - 14, broken and COL_BROKEN or COL_HP_LBL)
    draw.SimpleText(string.format("%d / %d", math.floor(hp + 0.5), math.floor(hpmax)), "GRMVeh_Sm", bx + bw, by - 14, COL_HP_NUM, TEXT_ALIGN_RIGHT)
    surface.SetDrawColor(28, 32, 40)
    surface.DrawRect(bx, by, bw, bh)
    surface.SetDrawColor(hpColor(pct))
    surface.DrawRect(bx, by, math.max(0, bw * pct), bh)
    surface.SetDrawColor(0, 0, 0, 90)
    surface.DrawOutlinedRect(bx, by, bw, bh, 1)
    return true
end

local function drawSeatCard(veh)
    local seats = collectSeats(veh)
    if #seats == 0 then return end
    local seenWho = {}
    local shown = {}
    for i = 1, #seats do
        local who = occupantName(seats[i].seat)
        if who and seenWho[who] then
            -- один игрок не занимает два ряда
        else
            if who then seenWho[who] = true end
            shown[#shown + 1] = { driver = seats[i].driver, who = who }
        end
    end
    local rowH = 18
    local boxH = 28 + #shown * rowH
    local boxW = 248
    local sx = ScrW() - boxW - 18
    local sy = math.floor(ScrH() * 0.5 - boxH * 0.5)
    draw.RoundedBox(8, sx, sy, boxW, boxH, COL_SEAT_CARD)
    surface.SetDrawColor(55, 117, 151, 170)
    surface.DrawOutlinedRect(sx, sy, boxW, boxH, 1)
    draw.SimpleText(vehTitle(veh), "GRMVeh_Sm", sx + 10, sy + 6, COL_SEAT_TITLE)
    local freeN = 0
    for i = 1, #shown do
        if not shown[i].who then freeN = freeN + 1 end
    end
    draw.SimpleText(string.format("%d мест · свободно %d", #shown, freeN), "GRMVeh_Sm", sx + boxW - 10, sy + 6, COL_SEAT_FREE_N, TEXT_ALIGN_RIGHT)
    for i = 1, #shown do
        local label = "Место " .. i
        if shown[i].driver then label = label .. " (водитель)" end
        local status, col
        if shown[i].who then
            status = "Занято: " .. shown[i].who
            col = COL_SEAT_OCCUPIED
        else
            status = "Свободно"
            col = COL_GOOD
        end
        local ly = sy + 22 + (i - 1) * rowH
        draw.SimpleText(label, "GRMVeh_Seat", sx + 10, ly, COL_SEAT_ROW)
        draw.SimpleText(status, "GRMVeh_Seat", sx + boxW - 10, ly, col, TEXT_ALIGN_RIGHT)
    end
end

hook.Remove("HUDPaint", "GRM_Fuel_HUD")

hook.Add("HUDPaint", "GRM_Vehicle_Cluster", function()
    local lp = LocalPlayer()
    if not IsValid(lp) or not lp.InVehicle or not lp:InVehicle() then return end
    if GRM.AugHUD and GRM.AugHUD.IsActive and GRM.AugHUD.IsActive() then return end
    local veh = rootVeh(lp:GetVehicle())
    if not IsValid(veh) then return end

    local vel = veh:GetVelocity():Length()
    if veh.GetChassis then
        local ch = veh:GetChassis()
        if IsValid(ch) then vel = ch:GetVelocity():Length() end
    end
    local kmh = math.floor(vel * 0.09144)
    local fuel = veh:GetNWFloat("GRM_Fuel", -1)
    local fmax = math.max(1, veh:GetNWFloat("GRM_FuelMax", 100))
    local typ = veh:GetNWString("GRM_FuelType", "petrol")
    local typN = (GRM.Fuel.Types and GRM.Fuel.Types[typ]) or typ
    local empty = fuel >= 0 and fuel <= 0.05
    local hp = veh:GetNWFloat("GRM_VehHP", -1)
    local hpmax = math.max(1, veh:GetNWFloat("GRM_VehHPMax", 100))
    local broken = veh:GetNWBool("GRM_VehBroken", false)

    local w, h = 280, 108
    local x, y = ScrW() / 2 - w / 2, ScrH() - h - 28
    draw.RoundedBox(10, x, y, w, h, COL_PANEL)
    surface.SetDrawColor(55, 117, 151, 180)
    surface.DrawOutlinedRect(x, y, w, h, 1)
    draw.SimpleText(string.format("%d", kmh), "GRMVeh_Big", x + 22, y + 14, COL_BIG)
    draw.SimpleText("км/ч", "GRMVeh_Sm", x + 22, y + 44, COL_DIM)
    local eng = veh:GetNWBool("GRM_EngineOn", false)
    draw.SimpleText(eng and "двиг. ВКЛ  ·  R" or "двиг. ВЫКЛ  ·  R", "GRMVeh_Sm", x + 118, y + 48, eng and COL_GOOD or COL_ENG_OFF)

    if fuel >= 0 then
        local pct = math.Clamp(fuel / fmax, 0, 1)
        local bx, by, bw, bh = x + 118, y + 24, 140, 10
        draw.SimpleText(typN, "GRMVeh_Sm", bx, y + 8, COL_FUEL_TYPE)
        surface.SetDrawColor(30, 36, 46)
        surface.DrawRect(bx, by, bw, bh)
        surface.SetDrawColor(pct < 0.15 and COL_DANGER or COL_FUEL_OK)
        surface.DrawRect(bx, by, bw * pct, bh)
        draw.SimpleText(string.format("%.0f / %.0f л", fuel, fmax), "GRMVeh_Sm", bx, by + 12, COL_FUEL_NUM)
        if empty then
            draw.SimpleText("НЕТ ТОПЛИВА", "GRMVeh_Mid", x + w / 2, y + 62, COL_BROKEN, TEXT_ALIGN_CENTER)
        end
    else
        draw.SimpleText("бак не привязан", "GRMVeh_Sm", x + 118, y + 28, COL_DIM)
    end

    drawHPBar(veh, x, y, w, h)
    drawSeatCard(veh)
end)

hook.Add("HUDPaint", "GRM_Vehicle_LookHP", function()
    local lp = LocalPlayer()
    if not IsValid(lp) or not lp.Alive or not lp:Alive() then return end
    if lp.InVehicle and lp:InVehicle() then return end
    if GRM.AugHUD and GRM.AugHUD.IsActive and GRM.AugHUD.IsActive() then return end
    local tr
    if GRM.Perf and GRM.Perf.EyeTrace then tr = GRM.Perf.EyeTrace(lp, 0.08) else tr = lp:GetEyeTrace() end
    if not tr or not IsValid(tr.Entity) then return end
    local veh = rootVeh(tr.Entity)
    local isV = false
    if GRM.VehicleKeys and GRM.VehicleKeys.IsVehicle then isV = GRM.VehicleKeys.IsVehicle(veh)
    elseif _G.VK and VK.IsVehicle then isV = VK.IsVehicle(veh) end
    if not isV then return end
    if lp:GetPos():DistToSqr(veh:GetPos()) > 280 * 280 then return end
    local w, h = 280, 56
    local x, y = ScrW() / 2 - w / 2, ScrH() - h - 28
    draw.RoundedBox(10, x, y, w, h, COL_PANEL)
    surface.SetDrawColor(55, 117, 151, 180)
    surface.DrawOutlinedRect(x, y, w, h, 1)
    drawHPBar(veh, x, y, w, h)
end)

print("[GRM Fuel] vehicle HUD seats+hp")
