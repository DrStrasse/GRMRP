--[[ Топливо GRM v1.2: шланг с провисом, сессия заливки, частные колонки. ]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Fuel = GRM.Fuel or {}
local F = GRM.Fuel
F.Version = "1.2.4"
F.File = "grm_fuel.json"
F.PumpFile = "grm_fuel_pumps_" .. string.lower(game.GetMap() or "unknown") .. ".json"
F.PricePerLiter = 8
F.PumpPrice = 15000
F.StationRadius = 700
--[[ ДЛИНА ШЛАНГА (решение владельца 31.08: одна на все колонки).
     Раньше радиус был зашит числами 420 и 430 в двух местах, и шланг
     «не дотягивался» сообщением, а не физически. ]]
F.HoseLength = 360
F.Types = { petrol = "Бензин", diesel = "Дизель", electric = "Заряд" }

function F.UID(ent)
    if GRM.Vehicles and GRM.Vehicles.UID then
        local id = GRM.Vehicles.UID(ent)
        if id ~= "" then return id end
    end
    if IsValid(ent) then return "ent:" .. tostring(ent:EntIndex()) end
    return ""
end

--[[ НАСТОЯЩИЙ ЛИ ЭТО ТРАНСПОРТ (находка 27.08).

     Симптом: игрок садится в обычный стул или кресло — и получает полный
     приборник simfphys: скорость, бак, «Не заводится: поломана».

     Причина: в GMod сиденье это тоже vehicle (prop_vehicle_prisoner_pod),
     поэтому ply:InVehicle() и ent:IsVehicle() для стула возвращают true.
     RootVehicle, не найдя родителя-машины, возвращал САМ СТУЛ — и все
     модули дальше работали с ним как с автомобилем.

     Стул отличается от машины тем, что он одиночный: у него нет ни
     признаков simfphys/LVS, ни родителя-транспорта. ]]
function F.IsRealVehicle(ent)
    if not IsValid(ent) then return false end
    if ent.IsSimfphysCar or ent.Simfphys or ent.IsSimfphys then return true end
    if ent.LVS or ent.IsLVSVehicle or ent.IsLFSVehicle or ent.LFS then return true end
    if ent.IsGlideVehicle or ent.VD_ID then return true end

    local cls = string.lower(ent:GetClass() or "")
    if string.find(cls, "^simfphys_") or string.find(cls, "^gcx_")
        or string.find(cls, "^gmod_sent_vehicle_fphysics")
        or string.find(cls, "^lvs_") or string.find(cls, "^lfs_")
        or string.find(cls, "^lunasflightschool_") then
        return true
    end

    --[[ Ванильные машины (jeep, airboat) — настоящий транспорт.
         А вот prop_vehicle_prisoner_pod сам по себе — это стул: машиной он
         считается только когда прицеплен к корпусу simfphys/LVS. ]]
    if cls == "prop_vehicle_jeep" or cls == "prop_vehicle_airboat" then return true end
    return false
end

--- Корневой транспорт сиденья. nil, если это просто стул.
function F.RootVehicle(ent)
    if not IsValid(ent) then return nil end

    local parent = ent.GetParent and ent:GetParent()
    if IsValid(parent) then
        local VK = GRM.VehicleKeys or _G.VK
        if VK and VK.IsVehicle and VK.IsVehicle(parent) then return parent end
        if F.IsRealVehicle(parent) then return parent end
    end
    for _, name in ipairs({ "BaseVehicle", "SimfphysVehicle", "LVS", "Vehicle" }) do
        local b = ent.GetNWEntity and ent:GetNWEntity(name)
        if IsValid(b) then return b end
        if IsValid(ent[name]) then return ent[name] end
    end

    -- Сам объект — транспорт только если он им действительно является.
    if F.IsRealVehicle(ent) then return ent end
    return nil
end

--[[ ТИПЫ ТОПЛИВА SIMFPHYS.
     Константы определяет база simfphys (simfphys/base_functions.lua).
     Дублируем числами: база может быть не загружена, а сравнивать
     всё равно надо. ]]
F.FUELTYPE = { NONE = 0, PETROL = 1, DIESEL = 2, ELECTRIC = 3 }

--- Есть ли у машины собственный бак (simfphys/LVS отдают его сами).
function F.HasOwnTank(ent)
    return IsValid(ent) and isfunction(ent.GetMaxFuel) and isfunction(ent.SetFuel)
end

--[[ ГОРЛОВИНА БАКА (жалоба владельца 31.08: шланг крепится непонятно куда).

     Раньше точка считалась по габариту: 12 юнитов от края, 8 от правого
     борта, 35% высоты. У настоящих машин горловина задана автором
     конверсии и разбросана по всем трём осям, включая знак Y:

         Vector(17.64, -14.55, 30.06)
         Vector(32.82, -78.31, 81.89)
         Vector(-61.39,  49.54, 15.79)   -- дизель

     Догадкой по габариту в неё не попасть: отсюда «пистолет не находит
     машину» и шланг, тянущийся в пустоту. simfphys отдаёт точку сам:
     ent:GetFuelPos() = LocalToWorld(GetFuelPortPosition()).

     known=false — когда машина горловины не знает: база в этом случае
     ставит Vector(0,0,0), то есть origin. Тогда считаем по габариту,
     как раньше, но помечаем, что это догадка. ]]
function F.FillPort(ent)
    if not IsValid(ent) then return vector_origin, Vector(0, 0, 1), false end
    ent = F.RootVehicle(ent) or ent
    local mn, mx = ent:OBBMins(), ent:OBBMaxs()
    local pos, known = nil, false

    if isfunction(ent.GetFuelPos) then
        local ok, got = pcall(function() return ent:GetFuelPos() end)
        if ok and isvector(got) then
            local lp = ent:WorldToLocal(got)
            local hollow = math.abs(lp.x) < 0.5 and math.abs(lp.y) < 0.5 and math.abs(lp.z) < 0.5
            local inside = lp.x > mn.x - 24 and lp.x < mx.x + 24
                       and lp.y > mn.y - 24 and lp.y < mx.y + 24
                       and lp.z > mn.z - 24 and lp.z < mx.z + 24
            if not hollow and inside then pos, known = got, true end
        end
    end

    if not known then
        pos = ent:LocalToWorld(Vector(mn.x + 12, mx.y - 8, (mn.z + mx.z) * 0.35))
    end

    -- Нормаль: наружу от корпуса. Считаем трассировкой, а не «вектором
    -- от центра», чтобы знак/шланг не уплывал внутрь кузова на машинах
    -- со смещённым origin.
    local center = ent:LocalToWorld((mn + mx) * 0.5)
    local dir = Vector(pos.x - center.x, pos.y - center.y, 0)
    if dir:Length() < 1 then dir = Vector(ent:GetForward().x, ent:GetForward().y, 0) end
    dir.z = 0
    if dir:Length() < 0.05 then dir = Vector(1, 0, 0) end
    dir:Normalize()

    local normal = dir
    if util and isfunction(util.TraceLine) then
        local ok, tr = pcall(function()
            return util.TraceLine({
                start = pos + dir * 48,
                endpos = pos - dir * 24,
                filter = function(e) return e ~= ent end,
                mask = MASK_SOLID,
            })
        end)
        -- Луч идёт ВДОЛЬ -dir, наружная нормаль — ВДОЛЬ dir.
        if ok and istable(tr) and tr.Hit and isvector(tr.HitNormal)
            and tr.HitNormal:Length() > 0.2 then
            local n = Vector(tr.HitNormal.x, tr.HitNormal.y, tr.HitNormal.z)
            n:Normalize()
            if n:Dot(dir) > 0.2 then normal = n end
        end
    end
    return pos, normal, known
end

--- Точка горловины (оставлено для совместимости: раньше так называлась).
function F.TankWorld(ent)
    local pos = F.FillPort(ent)
    return pos
end

function F.GuessType(ent)
    if not IsValid(ent) then return "petrol" end
    --[[ ТИП БЕРЁМ У МАШИНЫ. Раньше угадывали по подстрокам в имени
         класса и модели (truck, kamaz, tesla...): у simfphys тип задан
         числом и проставлен в сеть. Угадывание давало ложные отказы
         «Не тот тип» на машине, которая по данным — бензин. ]]
    if isfunction(ent.GetFuelType) then
        local ok, got = pcall(function() return ent:GetFuelType() end)
        if ok then
            local n = tonumber(got)
            local T = F.FUELTYPE or {}
            if n == T.DIESEL then return "diesel" end
            if n == T.ELECTRIC then return "electric" end
            if n == T.PETROL then return "petrol" end
        end
    end
    local cls = string.lower(ent:GetClass() or "")
    local mdl = string.lower(ent:GetModel() or "")
    if string.find(cls, "electric") or string.find(mdl, "tesla") then return "electric" end
    if string.find(cls, "truck") or string.find(mdl, "kamaz") or string.find(mdl, "ural")
        or string.find(mdl, "diesel") then return "diesel" end
    return "petrol"
end

--[[ ОБЪЁМ БАКА БЕРЁМ У МАШИНЫ.
     Была константа 100 литров на всё: у simfphys свой FuelTankSize на
     модель (65 по умолчанию), и GRM заливал больше, чем влезает.
     Фолбэк 100 остаётся для ванили, у которой своего бака нет. ]]
function F.TankSize(ent)
    if IsValid(ent) and isfunction(ent.GetMaxFuel) then
        local ok, got = pcall(function() return ent:GetMaxFuel() end)
        local n = tonumber(got)
        if ok and n and n > 0 then return n end
    end
    return 100
end

function F.TankWorld(ent)
    if not IsValid(ent) then return vector_origin end
    local mn, mx = ent:OBBMins(), ent:OBBMaxs()
    return ent:LocalToWorld(Vector(mn.x + 12, mx.y - 8, (mn.z + mx.z) * 0.35))
end

function F.CharKey(ply)
    if GRM.Identity and GRM.Identity.CharacterKey then return GRM.Identity.CharacterKey(ply) end
    return IsValid(ply) and (ply:SteamID64() .. ":char1") or ""
end

function F.PriceOf(pump)
    if IsValid(pump) and pump.GetPriceL then
        local p = tonumber(pump:GetPriceL()) or 0
        if p > 0 then return p end
    end
    return F.PricePerLiter or 8
end

if SERVER then
    util.AddNetworkString("GRM_Fuel_Station")
    F.Data = F.Data or {}

    local function jsonT(txt)
        local ok, t = pcall(util.JSONToTable, txt, false, true)
        return (ok and istable(t)) and t or nil
    end

    function F.Load()
        if not file.Exists(F.File, "DATA") then F.Data = {} return end
        F.Data = jsonT(file.Read(F.File, "DATA") or "") or {}
    end

    function F.Save()
        local fn = function()
            local ok, txt = pcall(util.TableToJSON, F.Data or {}, true)
            if ok and txt then file.Write(F.File, txt) end
        end
        if GRM.Perf and GRM.Perf.Coalesce then GRM.Perf.Coalesce("grm_fuel_save", 0.8, fn) else fn() end
    end

    function F.SavePumps()
        local rows = {}
        for _, e in ipairs(ents.FindByClass("grm_fuel_pump")) do
            if IsValid(e) then
                rows[#rows + 1] = {
                    pos = { x = e:GetPos().x, y = e:GetPos().y, z = e:GetPos().z },
                    ang = { p = e:GetAngles().p, y = e:GetAngles().y, r = e:GetAngles().r },
                    kind = e:GetFuelKind(),
                    owner = e:GetOwnerKey(),
                    station = e:GetStationID(),
                    price = e:GetPriceL(),
                    cash = e:GetCash(),
                }
            end
        end
        local fn = function()
            file.Write(F.PumpFile, util.TableToJSON(rows, false) or "[]")
        end
        if GRM.Perf and GRM.Perf.Coalesce then GRM.Perf.Coalesce("grm_fuel_pumps", 1, fn) else fn() end
    end

    function F.SavePumpsNow()
        if GRM.Perf and GRM.Perf.Cancel then pcall(GRM.Perf.Cancel, "grm_fuel_pumps") end
        local rows = {}
        for _, e in ipairs(ents.FindByClass("grm_fuel_pump")) do
            if IsValid(e) then
                rows[#rows + 1] = {
                    pos = { x = e:GetPos().x, y = e:GetPos().y, z = e:GetPos().z },
                    ang = { p = e:GetAngles().p, y = e:GetAngles().y, r = e:GetAngles().r },
                    kind = e:GetFuelKind(),
                    owner = e:GetOwnerKey(),
                    station = e:GetStationID(),
                    price = e:GetPriceL(),
                    cash = e:GetCash(),
                }
            end
        end
        file.Write(F.PumpFile, util.TableToJSON(rows, false) or "[]")
    end

    function F.LoadPumps()
        if not file.Exists(F.PumpFile, "DATA") then return end
        local rows = jsonT(file.Read(F.PumpFile, "DATA") or "")
        if not istable(rows) then return end
        for _, r in ipairs(rows) do
            if istable(r.pos) then
                local spot = Vector(r.pos.x or 0, r.pos.y or 0, r.pos.z or 0)
                local busy
                for _, ex in ipairs(ents.FindInSphere(spot, 8)) do
                    if IsValid(ex) and ex:GetClass() == "grm_fuel_pump" then busy = true break end
                end
                if busy then continue end
                local e = ents.Create("grm_fuel_pump")
                if IsValid(e) then
                    e:SetPos(Vector(r.pos.x, r.pos.y, r.pos.z))
                    if istable(r.ang) then e:SetAngles(Angle(r.ang.p, r.ang.y, r.ang.r)) end
                    e:Spawn()
                    e:SetFuelKind(r.kind ~= "" and r.kind or "petrol")
                    e:SetOwnerKey(r.owner or "")
                    e:SetStationID(r.station or "")
                    e:SetPriceL(tonumber(r.price) or F.PricePerLiter)
                    e:SetCash(math.floor(tonumber(r.cash) or 0))
                end
            end
        end
    end

    function F.Get(uid)
        uid = tostring(uid or "")
        if uid == "" then return nil end
        F.Data[uid] = F.Data[uid] or { liters = 70, typ = "petrol" }
        return F.Data[uid]
    end

    --[[ НАЛОЖЕНИЕ НА БАК SIMFPHYS (решение владельца 31.08: «свой учёт
         поверх»).

         Значение храним САМИ — администрация может поправить литраж
         руками, и бак переживает рестарт и выдачу из гаража. Но у живой
         машины оно обязано совпадать с её собственным баком: пока
         учёт вёлся раздельно, HUD показывал одно, а simfphys считал
         другое — машина не ехала на полном GRM-баке и не глохла
         на пустом.

         Правило: один раз при первом обращении отдаём сохранённое
         значение машине; дальше ЗЕРКАЛИМ её бак к себе, чтобы расход
         на ходу попадал в учёт. ]]
    local function mirrorTank(ent, rec, max)
        if not F.HasOwnTank(ent) then return end
        if not ent.GRMFuelRestored then
            pcall(function() ent:SetFuel(math.Clamp(tonumber(rec.liters) or 0, 0, max)) end)
            ent.GRMFuelRestored = true
            return
        end
        local ok, got = pcall(function() return ent:GetFuel() end)
        local n = tonumber(got)
        if ok and n then rec.liters = math.Clamp(n, 0, max) end
    end

    function F.ApplyNW(ent)
        if not IsValid(ent) then return end
        ent = F.RootVehicle(ent) or ent
        if GRM.Vehicles and GRM.Vehicles.EnsureUID then GRM.Vehicles.EnsureUID(ent) end
        local uid = F.UID(ent)
        if uid == "" then return end
        local rec = F.Get(uid)
        local max = F.TankSize(ent)
        rec.typ = rec.typ or F.GuessType(ent)
        rec.liters = math.Clamp(tonumber(rec.liters) or 40, 0, max)
        mirrorTank(ent, rec, max)
        rec.liters = math.Clamp(tonumber(rec.liters) or 0, 0, max)
        ent:SetNWFloat("GRM_Fuel", rec.liters)
        ent:SetNWFloat("GRM_FuelMax", max)
        ent:SetNWString("GRM_FuelType", rec.typ)
        ent:SetNWBool("GRM_OutOfFuel", rec.liters <= 0.05)
    end

    function F.AddLiters(ent, amount, typ)
        if not IsValid(ent) then return 0 end
        ent = F.RootVehicle(ent) or ent
        F.ApplyNW(ent)
        local rec = F.Get(F.UID(ent))
        if typ and rec.typ ~= typ then return 0, "wrong" end
        local max = F.TankSize(ent)
        local add = math.min(max - rec.liters, math.max(0, tonumber(amount) or 0))
        rec.liters = rec.liters + add
        -- залитое сразу отдаём и собственному баку машины
        if F.HasOwnTank(ent) then
            pcall(function() ent:SetFuel(rec.liters) end)
        end
        F.ApplyNW(ent)
        F.Save()
        return add
    end

    local function killEngine(ent, empty)
        if not IsValid(ent) then return end
        pcall(function()
            if ent.EnableEngine then ent:EnableEngine(false) end
            if ent.StartEngine then ent:StartEngine(false) end
            if ent.SetActive then ent:SetActive(false) end
            if ent.TurnOff then ent:TurnOff() end
            if ent.StopEngine then ent:StopEngine() end
        end)
        if empty then
            ent:SetNWBool("GRM_OutOfFuel", true)
        end
    end

    function F.ClearHose(pump)
        if not IsValid(pump) then return end
        constraint.RemoveConstraints(pump, "Rope")
        constraint.RemoveConstraints(pump, "Winch")
        constraint.RemoveConstraints(pump, "Elastic")
        if IsValid(pump.GRMHoseDummy) then pump.GRMHoseDummy:Remove() end
        pump.GRMHoseDummy = nil
    end

    --[[ ШЛАНГ (жалоба владельца 31.08: «нормальное крепление шлангов
         к баку»).

         Обе функции были ЗАГЛУШКАМИ: и AttachHose, и HoseToTank только
         удаляли веревку. Никакой привязки не существовало — весь
         «шланг с провисом» из шапки файла был клиентским
         render.DrawBeam, который не знал ни про длину, ни про
         препятствия, ни про то, где у машины горловина.

         Теперь шланг — настоящая веревка от колонки к машине, с
         заранее заданной длиной. Провес рисуется на клиенте поверх,
         но конец берётся у веревки, а не вычисляется заново. ]]
    function F.AttachHose(pump, target, lpos)
        if not (IsValid(pump) and IsValid(target)) then return false end
        F.ClearHose(pump)
        if not (constraint and isfunction(constraint.Rope)) then return false end
        local from = Vector(14, -10, 22)
        lpos = isvector(lpos) and lpos or vector_origin
        local span = pump:LocalToWorld(from):Distance(target:LocalToWorld(lpos))
        local slack = math.max(24, (F.HoseLength or 360) - span)
        if slack <= 0 then return false end   -- шланг физически не дотягивается
        pcall(function()
            constraint.Rope(pump, target, 0, 0, from, lpos,
                span, slack, 0, 1.6, "cable/cable2", false)
        end)
        pump.GRMHoseTarget = target
        return true
    end

    --- Дотянуться шлангом от колонки до горловины бака машины.
    function F.HoseToTank(pump, veh)
        if not (IsValid(pump) and IsValid(veh)) then return false end
        local pos = F.FillPort(veh)
        local lpos = veh:WorldToLocal(pos)
        local span = pump:LocalToWorld(Vector(14, -10, 22)):Distance(pos)
        if span > (F.HoseLength or 360) then return false end
        return F.AttachHose(pump, veh, lpos)
    end

    --[[ ШЛАНГ ЖИВЁТ НА КОЛОНКЕ (заказ владельца 31.08: «шланг не должен
         сам выходить из бака и не должен отдаваться игроку»).

         КАК БЫЛО. Колонка выдавала игроку ОРУЖИЕ-пистолет, он носил
         его к машине и вставлял в бак. Таймер заливки каждой итерацией
         проверял, не отошёл ли игрок:

             ply:GetPos():DistToSqr(pump:GetPos()) > 360²  → «шланг натянулся»
             ply:GetPos():DistToSqr(порт)         > 190²  → «отошёл от бака»

         То есть шланг вылетал из бака САМ, стоило игроку сделать шаг.
         А пистолет в руках — это и есть «отдаётся игроку»: предмет,
         который можно выбросить, уронить, унести и потерять.

         КАК ТЕПЕРЬ. Игрок ничего не получает в руки. Он подходит к
         колонке и жмёт E — шланг сам тянется к горловине и остаётся
         там. Заливка идёт БЕЗ игрока: он может сидеть в машине,
         отойти или уехать по делам. Шланг из бака выходит только
         осознанно — повторным E на колонке, — либо по физике, если
         машину утащили дальше длины шланга. ]]

    --- Куда цеплять шланг: машина, на которую смотрит игрок, иначе
    --  ближайшая с горловиной в пределах длины шланга.
    function F.FindTarget(pump, ply)
        if not IsValid(pump) then return nil, "Колонка не найдена" end
        local maxLen = F.HoseLength or 360
        local anchor = pump:LocalToWorld(Vector(14, -10, 22))
        local VK = GRM.VehicleKeys or _G.VK
        local function isVeh(e)
            if not IsValid(e) then return false end
            if VK and VK.IsVehicle then return VK.IsVehicle(e) end
            return F.IsRealVehicle(e)
        end
        local function reachable(veh)
            if not isVeh(veh) then return nil end
            veh = F.RootVehicle(veh) or veh
            if F.FillPort(veh):DistToSqr(anchor) > maxLen * maxLen then return nil end
            return veh
        end

        -- 1) та, на которую смотрит игрок
        if IsValid(ply) and ply.GetEyeTrace then
            local ok, tr = pcall(function() return ply:GetEyeTrace() end)
            if ok and istable(tr) then
                local hit = reachable(tr.Entity)
                if hit then return hit end
            end
        end
        -- 2) ближайшая по горловине
        local best, bestD
        for _, e in ipairs(ents.FindInSphere(pump:GetPos(), maxLen + 220)) do
            local hit = reachable(e)
            if hit then
                local d = F.FillPort(hit):DistToSqr(anchor)
                if not bestD or d < bestD then best, bestD = hit, d end
            end
        end
        if best then return best end
        return nil, "Рядом нет машины с доступной горловиной"
    end

    --- Вставить шланг в бак и начать заливку. Пистолет игроку не выдаётся.
    function F.PlugHose(pump, veh, ply)
        if not IsValid(pump) then return false, "Колонка не найдена" end
        if IsValid(pump.GRMHoseCar) then return false, "Шланг уже в баке" end
        if not IsValid(veh) then return false, "Машина не найдена" end
        veh = F.RootVehicle(veh) or veh
        F.ApplyNW(veh)

        local need = veh:GetNWString("GRM_FuelType", "petrol")
        if need ~= pump:GetFuelKind() then
            return false, "Не тот тип. Нужен: " .. tostring((F.Types or {})[need] or need)
        end
        if not F.HoseToTank(pump, veh) then
            return false, "Шланг не дотягивается до горловины"
        end

        pump.GRMHoseCar = veh
        pump.GRMHoseBy = ply
        pump.GRMFuelFull, pump.GRMFuelNoMoney = nil, nil
        if pump.SetHoseCar then pump:SetHoseCar(veh) end
        pump:SetBusy(true)
        pump:SetSessionL(0)
        pump:SetSessionPay(0)
        pump:SetTankNow(veh:GetNWFloat("GRM_Fuel", 0))
        pump:SetTankMax(veh:GetNWFloat("GRM_FuelMax", F.TankSize(veh)))
        pump:EmitSound("ambient/water/leak_1.wav", 50, 95)
        timer.Create("GRM_Fuel_Pump_" .. pump:EntIndex(), 0.35, 0, function()
            F.PumpTick(pump)
        end)
        return true
    end

    --[[ ОДИН ТАКТ ЗАЛИВКИ.

         Здесь нет ни одной проверки положения ИГРОКА — ровно из-за них
         шланг и вылетал из бака сам. Заливка прекращается только по
         делу:

           • бак полон        — шланг ОСТАЁТСЯ в баке, ждёт человека;
           • деньги кончились — шланг ОСТАЁТСЯ в баке;
           • машина пропала   — шланга больше не существует;
           • машину утащили дальше длины шланга — сорвало по физике.

         В первых двух случаях колонка просто перестаёт качать и
         сообщает об этом один раз: убирает шланг человек, а не таймер. ]]
    function F.PumpTick(pump)
        if not IsValid(pump) then return end
        local veh = pump.GRMHoseCar
        if not IsValid(veh) then
            F.ForgetHose(pump)
            return
        end
        -- машину утащили дальше шланга — это физика, а не «само выпало»
        local anchor = pump:LocalToWorld(Vector(14, -10, 22))
        local maxLen = F.HoseLength or 360
        if F.FillPort(veh):DistToSqr(anchor) > maxLen * maxLen then
            F.UnplugHose(pump, nil, "Машину утащили — шланг сорвало.")
            return
        end

        local ply = pump.GRMHoseBy
        local price = F.PriceOf(pump)
        if not IsValid(ply) then return end   -- игрок вышел: шланг ждёт в баке
        if GRM.HasMoney and not GRM.HasMoney(ply, price) then
            if not pump.GRMFuelNoMoney then
                pump.GRMFuelNoMoney = true
                pump:SetBusy(false)
                if GRM.Notify then GRM.Notify(ply,
                    "Деньги кончились. Шланг в баке — убери его на колонке.", 255, 180, 80) end
            end
            return
        end

        local added = select(1, F.AddLiters(veh, 1.15, pump:GetFuelKind())) or 0
        if added <= 0 then
            if not pump.GRMFuelFull then
                pump.GRMFuelFull = true
                pump:SetBusy(false)
                if GRM.Notify then GRM.Notify(ply,
                    "Бак полон. Шланг в баке — убери его на колонке.", 120, 220, 140) end
            end
            return
        end

        local cost = math.ceil(price * added)
        if GRM.TakeMoney then GRM.TakeMoney(ply, cost, "Заправка") end
        local owner = pump:GetOwnerKey() or ""
        if owner ~= "" then pump:SetCash(pump:GetCash() + cost) end
        pump:SetSessionL((pump:GetSessionL() or 0) + added)
        pump:SetSessionPay((pump:GetSessionPay() or 0) + cost)
        pump:SetTankNow(veh:GetNWFloat("GRM_Fuel", 0))
        pump:SetTankMax(veh:GetNWFloat("GRM_FuelMax", F.TankSize(veh)))
    end

    --- Снять учёт шланга, не трогая деньги (машина пропала).
    function F.ForgetHose(pump)
        if not IsValid(pump) then return end
        timer.Remove("GRM_Fuel_Pump_" .. pump:EntIndex())
        F.ClearHose(pump)
        pump.GRMHoseCar, pump.GRMHoseBy = nil, nil
        pump.GRMFuelFull, pump.GRMFuelNoMoney = nil, nil
        if pump.SetHoseCar then pump:SetHoseCar(NULL) end
        pump:SetBusy(false)
    end

    --[[ УБРАТЬ ШЛАНГ ИЗ БАКА.

         Только осознанно: кнопкой на колонке. Ни таймер, ни расстояние
         до игрока сюда не ведут — иначе это снова «шланг сам вышел». ]]
    function F.UnplugHose(pump, ply, msg)
        if not IsValid(pump) then return false end
        local who = IsValid(ply) and ply or pump.GRMHoseBy
        local sess, pay = pump:GetSessionL() or 0, pump:GetSessionPay() or 0
        F.ForgetHose(pump)
        pump:SetSessionL(0)
        pump:SetSessionPay(0)
        if msg and IsValid(who) and GRM.Notify then GRM.Notify(who, msg, 255, 200, 120) end
        if sess > 0 and IsValid(who) and GRM.Notify then
            GRM.Notify(who, ("Залито %.1f л на %.0f GRM."):format(sess, pay), 120, 220, 140)
        end
        return true
    end

    local function nearbyPumps(origin, radius)
        local out = {}
        for _, e in ipairs(ents.FindByClass("grm_fuel_pump")) do
            if IsValid(e) and e:GetPos():DistToSqr(origin) <= radius * radius then out[#out + 1] = e end
        end
        return out
    end

    function F.IsOwner(ply, pump)
        if not IsValid(ply) or not IsValid(pump) then return false end
        if ply:IsSuperAdmin() then return true end
        return pump:GetOwnerKey() == F.CharKey(ply)
    end

    --[[ МОЖНО ЛИ ВЫКУПИТЬ КОЛОНКУ ЛИЧНО (баг владельца 28.08).

         Симптом: «покупаешь или продаёшь — пишет, что куплено, а на
         деле нет».

         Причина. У автоматов с едой покупка спрашивала
         ES.CanOwnStandalone: точка внутри бизнес-зоны принадлежит
         бизнесу, лично её выкупать нельзя. У колонок этой проверки НЕ
         БЫЛО. Поэтому игрок платил, F.BuyPump честно писал «Колонка
         куплена», ставил себя владельцем — а следом хук
         GRM_PropertyOwnerChanged (или ближайшая пересинхронизация зоны)
         звал DL.TransferEquipment, который переписывает ВСЁ
         оборудование зоны на владельца бизнеса. Владелец колонки
         затирался, деньги пропадали, надпись «куплено» оставалась
         враньём.

         Теперь колонка внутри бизнес-зоны продаётся только вместе с
         бизнесом — как и автомат. ]]
    function F.CanBuyPump(ply, pump)
        if not (IsValid(ply) and IsValid(pump)) then return false, "Нет колонки" end
        if ply:IsSuperAdmin() then return true end
        if not (GRM.Estate and GRM.Estate.CanOwnStandalone) then return true end
        local can, why = GRM.Estate.CanOwnStandalone(pump)
        if not can then return false, tostring(why or "Нужна бизнес-зона") end
        return true
    end

    function F.BuyPump(ply, pump, whole)
        if not IsValid(ply) or not IsValid(pump) then return false, "Нет колонки" end
        if ply:GetPos():DistToSqr(pump:GetPos()) > 220 * 220 then return false, "Подойдите ближе" end
        local list = whole and nearbyPumps(pump:GetPos(), F.StationRadius) or { pump }
        local free = {}
        for _, e in ipairs(list) do
            local o = e:GetOwnerKey() or ""
            if o == "" or o == F.CharKey(ply) then free[#free + 1] = e end
        end
        if #free == 0 then return false, "Нечего выкупать" end

        --[[ Проверяем КАЖДУЮ покупаемую колонку до списания денег.
             Достаточно одной внутри чужого бизнеса, чтобы сделка была
             недействительной: иначе повторяется тот же баг — деньги
             сняты, а владельца перепишет бизнес-зона. ]]
        for _, e in ipairs(free) do
            if (e:GetOwnerKey() or "") == "" then
                local can, why = F.CanBuyPump(ply, e)
                if not can then return false, why end
            end
        end

        local needBuy = 0
        for _, e in ipairs(free) do
            if (e:GetOwnerKey() or "") == "" then needBuy = needBuy + 1 end
        end

        -- Всё уже наше: денег не берём и «куплено» не пишем.
        if needBuy == 0 then
            return false, whole and "Заправка уже ваша" or "Колонка уже ваша"
        end

        local price = needBuy * F.PumpPrice
        if whole and needBuy > 1 then price = math.floor(price * 0.85) end
        if price > 0 then
            if GRM.HasMoney and not GRM.HasMoney(ply, price) then
                return false, "Нужно " .. price .. " GRM"
            end
            if GRM.TakeMoney then GRM.TakeMoney(ply, price, "покупка заправки") end
        end
        local sid = pump:GetStationID()
        if sid == "" then sid = "st_" .. os.time() .. "_" .. math.random(100, 999) end
        local key = F.CharKey(ply)
        for _, e in ipairs(free) do
            e:SetOwnerKey(key)
            e:SetStationID(sid)
            if (e:GetPriceL() or 0) <= 0 then e:SetPriceL(F.PricePerLiter) end
        end
        F.SavePumps()
        if GRM.PermData and GRM.PermData.Upsert then
            for _, e in ipairs(free) do GRM.PermData.Upsert(e) end
        end

        --[[ ПРОВЕРЯЕМ РЕЗУЛЬТАТ, а не верим себе на слово. Если владелец
             после записи не наш (например, зона успела переписать точку),
             честно возвращаем деньги и сообщаем правду. Раньше именно
             здесь рождалось «пишет куплено, а на деле нет». ]]
        local lost = 0
        for _, e in ipairs(free) do
            if IsValid(e) and (e:GetOwnerKey() or "") ~= key then lost = lost + 1 end
        end
        if lost > 0 then
            if price > 0 and GRM.GiveMoney then
                GRM.GiveMoney(ply, price, "возврат за колонку")
            end
            return false, "Колонка относится к бизнесу — покупка отменена, деньги возвращены"
        end

        return true, whole and ("Заправка: " .. #free .. " колонок, " .. price .. " GRM") or ("Колонка куплена за " .. price .. " GRM")
    end

    --[[ ПРОДАЖА КОЛОНКИ. Раньше её просто не было: «продать» игрок мог
         только удалением через «Удалить колонку», то есть терял деньги
         совсем. Возврат — половина цены, как у выкупа государством. ]]
    F.SellRate = 0.5

    function F.SellPump(ply, pump, whole)
        if not (IsValid(ply) and IsValid(pump)) then return false, "Нет колонки" end
        if ply:GetPos():DistToSqr(pump:GetPos()) > 220 * 220 then return false, "Подойдите ближе" end

        local key = F.CharKey(ply)
        local list = whole and nearbyPumps(pump:GetPos(), F.StationRadius) or { pump }
        local mine = {}
        for _, e in ipairs(list) do
            if IsValid(e) and (e:GetOwnerKey() or "") == key then mine[#mine + 1] = e end
        end
        if #mine == 0 then return false, "Это не ваша колонка" end

        --[[ Касса не должна пропасть вместе с колонкой: как у бизнеса,
             сначала снимите выручку. ]]
        local cash = 0
        for _, e in ipairs(mine) do cash = cash + (tonumber(e:GetCash()) or 0) end
        if cash > 0 then return false, "Сначала снимите кассу: " .. math.floor(cash) .. " GRM" end

        local payout = math.floor(#mine * F.PumpPrice * F.SellRate)
        for _, e in ipairs(mine) do
            e:SetOwnerKey("")
            e:SetStationID("")
        end
        if payout > 0 and GRM.GiveMoney then
            GRM.GiveMoney(ply, payout, "продажа колонки")
        end
        F.SavePumps()
        if GRM.PermData and GRM.PermData.Upsert then
            for _, e in ipairs(mine) do GRM.PermData.Upsert(e) end
        end
        return true, ("Продано колонок: %d · получено %d GRM"):format(#mine, payout)
    end

    function F.SetStationPrice(ply, pump, price)
        if not F.IsOwner(ply, pump) then return false, "Это не ваша колонка" end
        price = math.Clamp(math.floor(tonumber(price) or 8), 1, 200)
        local sid = pump:GetStationID()
        for _, e in ipairs(ents.FindByClass("grm_fuel_pump")) do
            if IsValid(e) and (sid == "" and e == pump or e:GetStationID() == sid) and F.IsOwner(ply, e) then
                e:SetPriceL(price)
            end
        end
        F.SavePumps()
        if GRM.PermData and GRM.PermData.Upsert then
            for _, e in ipairs(ents.FindByClass("grm_fuel_pump")) do
                if IsValid(e) and F.IsOwner(ply, e) then GRM.PermData.Upsert(e) end
            end
        end
        return true, "Цена станции: " .. price .. " GRM/л"
    end

    function F.Withdraw(ply, pump)
        --[[ Колонка внутри бизнес-зоны принадлежит бизнесу: касса
             снимается через окно бизнеса вместе с остальными точками.
             Иначе прежний владелец колонки обходил бы владельца зоны. ]]
        if GRM.Estate and GRM.Estate.ZoneAt and IsValid(pump) then
            local zone = GRM.Estate.ZoneAt(pump:GetPos())
            if zone and GRM.Estate.IsBusiness(zone) then
                if not (GRM.Estate.IsOwner(ply, zone) or (IsValid(ply) and ply:IsSuperAdmin())) then
                    return false, "Колонка принадлежит бизнесу «" .. tostring(zone.name or "") .. "»"
                end
                return GRM.Estate.Collect(ply, zone)
            end
        end
        if not F.IsOwner(ply, pump) then return false, "Это не ваша колонка" end
        local sid = pump:GetStationID()
        local sum = 0
        for _, e in ipairs(ents.FindByClass("grm_fuel_pump")) do
            if IsValid(e) and (sid == "" and e == pump or e:GetStationID() == sid) and F.IsOwner(ply, e) then
                sum = sum + (e:GetCash() or 0)
                e:SetCash(0)
            end
        end
        if sum <= 0 then return false, "Касса пуста" end
        if GRM.GiveMoney then GRM.GiveMoney(ply, sum, "касса заправки") end
        F.SavePumps()
        return true, "Снято " .. sum .. " GRM"
    end

    function F.DeletePump(ply, pump)
        if not IsValid(pump) or pump:GetClass() ~= "grm_fuel_pump" then
            return false, "Нет колонки"
        end
        if IsValid(ply) and ply:GetPos():DistToSqr(pump:GetPos()) > 280 * 280 and not ply:IsSuperAdmin() then
            return false, "Подойдите ближе"
        end
        if IsValid(pump.GRMHoseCar) then F.UnplugHose(pump) else F.ForgetHose(pump) end
        local pos = pump:GetPos()
        if GRM.Perm and GRM.Perm.Remove then
            pcall(GRM.Perm.Remove, ply, pump, false)
        end
        if GRM.Perm and GRM.Perm.EraseNear then
            pcall(GRM.Perm.EraseNear, "grm_fuel_pump", pos, 80)
        end
        SafeRemoveEntity(pump)
        F.SavePumpsNow()
        return true, "Колонка снята с карты и из перма"
    end

    net.Receive("GRM_Fuel_Station", function(_, ply)
        if not IsValid(ply) then return end
        ply._grmFuelMenu = ply._grmFuelMenu or 0
        if CurTime() < ply._grmFuelMenu then return end
        ply._grmFuelMenu = CurTime() + 0.25
        local op = string.sub(net.ReadString() or "", 1, 16)
        local ent = net.ReadEntity()
        if not (IsValid(ent) and ent:GetClass() == "grm_fuel_pump") then return end
        local ok, msg
        if op == "buy" then ok, msg = F.BuyPump(ply, ent, false)
        elseif op == "buyall" then ok, msg = F.BuyPump(ply, ent, true)
        elseif op == "sell" then ok, msg = F.SellPump(ply, ent, false)
        elseif op == "sellall" then ok, msg = F.SellPump(ply, ent, true)
        elseif op == "price" then ok, msg = F.SetStationPrice(ply, ent, net.ReadFloat())
        elseif op == "cash" then ok, msg = F.Withdraw(ply, ent)
        elseif op == "del" then
            if not (F.IsOwner(ply, ent) or ply:IsSuperAdmin()) then
                ok, msg = false, "Нельзя снять чужую колонку"
            else
                ok, msg = F.DeletePump(ply, ent)
            end
        else return end
        if GRM.Notify then GRM.Notify(ply, tostring(msg), ok and 120 or 255, ok and 220 or 140, 100) end

        --[[ ПЕРЕРИСОВКА МЕНЮ (заказ владельца 28.08: «кнопка после покупки
             купить колонку/заправку должна исчезать по сути»).

             Раньше клиент закрывал окно сразу по клику и больше ничего не
             ждал. Владелец колонки менялся на сервере, а окно при
             следующем открытии могло показать устаревшее состояние —
             NW-переменная OwnerKey доезжает не мгновенно. Теперь сервер
             сам просит клиента открыть окно заново, уже с актуальным
             владельцем: кнопки покупки исчезают, появляются продажа и
             касса. ]]
        if ok and IsValid(ent) then
            net.Start("GRM_Fuel_Station")
                net.WriteString("refresh")
                net.WriteEntity(ent)
            net.Send(ply)
        end
    end)

    function F.SetEngine(veh, on)
        if not IsValid(veh) then return end
        veh = F.RootVehicle(veh) or veh
        if on then
            if veh:GetNWBool("GRM_VehBroken") then return false, "поломана" end
            if (veh:GetNWFloat("GRM_Fuel", 0) or 0) <= 0.05 then
                killEngine(veh, true)
                return false, "нет топлива"
            end
            veh:SetNWBool("GRM_EngineOn", true)
            veh:SetNWBool("GRM_OutOfFuel", false)
            pcall(function()
                if veh.EnableEngine then veh:EnableEngine(true) end
                if veh.StartEngine then veh:StartEngine(true) end
                if veh.SetActive then veh:SetActive(true) end
            end)
            return true
        end
        veh:SetNWBool("GRM_EngineOn", false)
        killEngine(veh)
        veh:SetNWBool("GRM_OutOfFuel", false)
        return true
    end

    hook.Add("PlayerEnteredVehicle", "GRM_Fuel_IgnOff", function(ply, seat)
        local veh = F.RootVehicle(seat)
        if IsValid(veh) then
            F.ApplyNW(veh)
            F.SetEngine(veh, false)
        end
    end)

    --[[ ЗА РУЛЁМ ЛИ ИГРОК (находка 27.08).

         Симптом: пассажир заводил машину клавишей R со своего места.
         Причина: проверялось только ply:InVehicle(), а пассажирский под —
         это тоже vehicle, и RootVehicle честно приводил его к корпусу.
         Теперь зажигание доступно только с места водителя. ]]
    local function isDriver(ply, veh)
        if not (IsValid(ply) and IsValid(veh)) then return false end
        local seat = ply:GetVehicle()
        if not IsValid(seat) then return false end

        -- simfphys и LVS сами знают, кто у них за рулём.
        for _, getter in ipairs({ "GetDriver", "GetDriverSeat" }) do
            if isfunction(veh[getter]) then
                local ok, res = pcall(veh[getter], veh)
                if ok and IsValid(res) then
                    if res == ply or res == seat then return true end
                    -- GetDriver вернул другого игрока — значит этот не водитель.
                    if res ~= ply and res.IsPlayer and res:IsPlayer() then return false end
                end
            end
        end

        --[[ Ванильный транспорт: сиденье и есть сама машина. Если игрок
             сидит прямо в корпусе, он за рулём. ]]
        if seat == veh then return true end

        -- Иначе это отдельный под: пассажирское место.
        return false
    end

    --[[ ЕСТЬ ЛИ ДОСТУП К МАШИНЕ.

         Симптом: обычный игрок не мог завести даже свою машину, а
         суперадмин заводил любую. Причина: доступ вообще не проверялся,
         а сама выдача ключей живёт в системе VK — заводить должен тот,
         кому машина принадлежит или у кого есть ключ. ]]
    local function canStart(ply, veh)
        if not (IsValid(ply) and IsValid(veh)) then return false end
        if ply:IsSuperAdmin() then return true end
        local VK = GRM.VehicleKeys or _G.VK
        --[[ Если система ключей не знает эту машину (ничья, никем не
             куплена), запрет накладывать не за что: заводит тот, кто сел. ]]
        if not (VK and isfunction(VK.CanInteract)) then return true end
        if VK.OWNER_TYPE and veh.VK_OwnerType == nil then return true end
        return VK.CanInteract(veh, ply, false) == true
    end

    hook.Add("StartCommand", "GRM_Fuel_Ignition", function(ply, cmd)
        if not (IsValid(ply) and ply:InVehicle()) then return end
        if not cmd:KeyDown(IN_RELOAD) then ply._grmIgnWas = false return end
        if ply._grmIgnWas then return end
        ply._grmIgnWas = true
        local veh = F.RootVehicle(ply:GetVehicle())
        if not IsValid(veh) then return end

        if not isDriver(ply, veh) then
            if GRM.Notify then
                GRM.Notify(ply, "Завести можно только с места водителя", 255, 170, 90)
            end
            return
        end
        if not canStart(ply, veh) then
            if GRM.Notify then
                GRM.Notify(ply, "Нет ключей от этой машины", 255, 160, 80)
            end
            return
        end

        local on = not veh:GetNWBool("GRM_EngineOn", false)
        local ok, why = F.SetEngine(veh, on)
        if GRM.Notify then
            if ok then GRM.Notify(ply, on and "Зажигание ВКЛ" or "Зажигание ВЫКЛ", 140, 210, 130)
            else GRM.Notify(ply, "Не заводится: " .. tostring(why), 255, 160, 80) end
        end
    end)

    hook.Add("Think", "GRM_Fuel_Consume", function()
        if GRM.Perf and GRM.Perf.Throttle and not GRM.Perf.Throttle("fuel.tick", 0.5) then return end
        local list = (GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()
        local dirty
        for i = 1, #list do
            local ply = list[i]
            if not (IsValid(ply) and ply:InVehicle()) then continue end
            local veh = F.RootVehicle(ply:GetVehicle())
            if not IsValid(veh) then continue end
            local uid = F.UID(veh)
            if uid == "" then
                F.ApplyNW(veh)
                uid = F.UID(veh)
            end
            if uid == "" then continue end
            local rec = F.Get(uid)
            if rec.liters <= 0.05 then
                if not veh:GetNWBool("GRM_OutOfFuel", false) then killEngine(veh, true) end
                continue
            end
            if veh:GetNWBool("GRM_OutOfFuel", false) then
                veh:SetNWBool("GRM_OutOfFuel", false)
            end
            if not veh:GetNWBool("GRM_EngineOn", false) then
                killEngine(veh, false)
                continue
            end
            if veh:GetNWBool("GRM_VehBroken") then continue end
            local burn = 0.007
            if ply:KeyDown(IN_FORWARD) then burn = burn + 0.016 end
            if ply:KeyDown(IN_SPEED) then burn = burn + 0.01 end
            rec.liters = math.max(0, rec.liters - burn)
            if GRM.Perf and GRM.Perf.NWFloat then
                GRM.Perf.NWFloat(veh, "GRM_Fuel", rec.liters, 0.05)
                GRM.Perf.NWBool(veh, "GRM_OutOfFuel", false)
            else
                veh:SetNWFloat("GRM_Fuel", rec.liters)
                veh:SetNWBool("GRM_OutOfFuel", false)
            end
            dirty = true
        end
        if dirty then F.Save() end
    end)

    hook.Add("OnEntityCreated", "GRM_Fuel_Spawn", function(ent)
        if GRM.Perf and GRM.Perf.Queue then
            GRM.Perf.Queue("fuel.spawn." .. tostring(ent), function()
                if not IsValid(ent) then return end
                local VK = GRM.VehicleKeys or _G.VK
                if VK and VK.IsVehicle and VK.IsVehicle(ent) then F.ApplyNW(ent) end
            end)
            return
        end
        timer.Simple(0.2, function()
            if not IsValid(ent) then return end
            local VK = GRM.VehicleKeys or _G.VK
            if VK and VK.IsVehicle and VK.IsVehicle(ent) then F.ApplyNW(ent) end
        end)
    end)

    function F.ScrubOrphanRopes()
        local ropes = ents.FindByClass("keyframe_rope")
        if #ropes == 0 then return end
        local fn = function(e)
            if not IsValid(e) then return end
            local a = e.Ent1 or e.GetInternalVariable and e:GetInternalVariable("m_hStartPoint")
            local b = e.Ent2 or e.GetInternalVariable and e:GetInternalVariable("m_hEndPoint")
            local dead = (not IsValid(a) and not IsValid(b))
            if dead then SafeRemoveEntity(e) end
        end
        if GRM.Perf and GRM.Perf.Spread then
            GRM.Perf.Spread("fuel.scrub_ropes", ropes, fn, { chunk = 24 })
        else
            for i = 1, #ropes do fn(ropes[i]) end
        end
        for _, pump in ipairs(ents.FindByClass("grm_fuel_pump")) do
            if IsValid(pump) then F.ClearHose(pump) end
        end
    end

    hook.Add("InitPostEntity", "GRM_Fuel_LoadPumps", function()
        timer.Simple(2, function()
            if #ents.FindByClass("grm_fuel_pump") == 0 then F.LoadPumps() end
            F.ScrubOrphanRopes()
        end)
    end)
    hook.Add("ShutDown", "GRM_Fuel_SavePumps", function() F.SavePumpsNow() end)
    hook.Add("EntityRemoved", "GRM_Fuel_PumpGone", function(ent)
        if not IsValid(ent) or ent:GetClass() ~= "grm_fuel_pump" then return end
        timer.Simple(0, function()
            if F.SavePumpsNow then F.SavePumpsNow() end
        end)
    end)

    concommand.Add("grm_fuel_scrub", function(ply)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        F.ScrubOrphanRopes()
        local msg = "[GRM Fuel] сиротские верёвки сняты порциями"
        if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg) else print(msg) end
    end)

    timer.Simple(0, function()
        if GRM.Perm and GRM.Perm.RegisterClass then GRM.Perm.RegisterClass("grm_fuel_pump", true) end
        if not (GRM.PermData and GRM.PermData.Extract) then return end
        GRM.PermData.Extract["grm_fuel_pump"] = function(ent)
            if not IsValid(ent) then return nil end
            return {
                owner = ent:GetOwnerKey(),
                station = ent:GetStationID(),
                price = ent:GetPriceL(),
                cash = ent:GetCash(),
                kind = ent:GetFuelKind(),
            }
        end
        GRM.PermData.Apply["grm_fuel_pump"] = function(ent, data)
            if not (IsValid(ent) and istable(data)) then return end
            if isstring(data.owner) then ent:SetOwnerKey(data.owner) end
            if isstring(data.station) then ent:SetStationID(data.station) end
            if tonumber(data.price) then ent:SetPriceL(tonumber(data.price)) end
            if tonumber(data.cash) then ent:SetCash(math.floor(tonumber(data.cash))) end
            if isstring(data.kind) and data.kind ~= "" then ent:SetFuelKind(data.kind) end
        end
    end)

    F.Load()
    print("[GRM Fuel] server v" .. F.Version)
end

if CLIENT then
    local function send(op, ent, extra)
        net.Start("GRM_Fuel_Station")
        net.WriteString(op)
        net.WriteEntity(ent)
        if extra then extra() end
        net.SendToServer()
    end

    function F.OpenStation(ent)
        if not IsValid(ent) then return end
        if IsValid(F._menu) then F._menu:Remove() end
        local fr = vgui.Create("DFrame")
        F._menu = fr
        fr:SetSize(380, 260)
        fr:Center()
        fr:SetTitle("")
        fr:MakePopup()
        fr:ShowCloseButton(true)
        fr.Paint = function(_, w, h)
            draw.RoundedBox(8, 0, 0, w, h, Color(12, 16, 24, 245))
            draw.SimpleText("ЗАПРАВКА", "DermaLarge", 16, 18, Color(250, 185, 63), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        local own = ent:GetOwnerKey() or ""
        --[[ «Моя ли это колонка» решаем по ключу ПЕРСОНАЖА, а не по факту
             «владелец не пуст»: иначе на чужой колонке показались бы
             кнопки продажи и снятия кассы. ]]
        local myKey = (GRM.Identity and GRM.Identity.CharacterKey
            and GRM.Identity.CharacterKey(LocalPlayer())) or ""
        local mine = own ~= "" and own == myKey
        local price = F.PriceOf(ent)

        local info = vgui.Create("DLabel", fr)
        info:SetPos(16, 44) info:SetSize(348, 40)
        if own == "" then
            info:SetText("Свободна. Колонка " .. F.PumpPrice .. " GRM, комплект рядом −15%.")
        elseif mine then
            info:SetText("Ваша колонка. Касса: " .. tostring(ent:GetCash() or 0) .. " GRM")
        else
            info:SetText("Чужая колонка. Купить нельзя.")
        end
        info:SetWrap(true)

        --[[ КНОПКИ ПО СОСТОЯНИЮ (заказ владельца 28.08).

             Раньше «Купить колонку» и «Купить заправку» висели всегда,
             даже когда объект уже куплен: игрок жал их повторно и видел
             ложное «куплено». Теперь свободная колонка показывает
             покупку, своя — продажу, чужая — ничего. ]]
        if own == "" then
            local buy = vgui.Create("DButton", fr)
            buy:SetPos(16, 92) buy:SetSize(168, 32) buy:SetText("Купить колонку")
            buy.DoClick = function() send("buy", ent) end
            local all = vgui.Create("DButton", fr)
            all:SetPos(196, 92) all:SetSize(168, 32) all:SetText("Купить заправку")
            all.DoClick = function() send("buyall", ent) end
        elseif mine then
            local sell = vgui.Create("DButton", fr)
            sell:SetPos(16, 92) sell:SetSize(168, 32)
            sell:SetText("Продать колонку (" .. math.floor(F.PumpPrice * (F.SellRate or 0.5)) .. " GRM)")
            sell.DoClick = function()
                Derma_Query("Продать колонку за половину цены?", "Заправка", "Продать", function()
                    send("sell", ent)
                end, "Отмена")
            end
            local sellAll = vgui.Create("DButton", fr)
            sellAll:SetPos(196, 92) sellAll:SetSize(168, 32) sellAll:SetText("Продать заправку")
            sellAll.DoClick = function()
                Derma_Query("Продать ВСЕ свои колонки рядом?", "Заправка", "Продать", function()
                    send("sellall", ent)
                end, "Отмена")
            end
        end
        local wang = vgui.Create("DNumberWang", fr)
        wang:SetPos(16, 140) wang:SetSize(120, 28) wang:SetMin(1) wang:SetMax(200) wang:SetValue(price)
        local setp = vgui.Create("DButton", fr)
        setp:SetPos(144, 140) setp:SetSize(220, 28) setp:SetText("Цена GRM / литр (станция)")
        setp.DoClick = function()
            send("price", ent, function() net.WriteFloat(wang:GetValue()) end)
        end
        local cash = vgui.Create("DButton", fr)
        cash:SetPos(16, 184) cash:SetSize(168, 32) cash:SetText("Снять кассу")
        cash.DoClick = function() send("cash", ent) fr:Close() end
        local del = vgui.Create("DButton", fr)
        del:SetPos(196, 184) del:SetSize(168, 32) del:SetText("Удалить колонку")
        del.DoClick = function()
            Derma_Query("Снять колонку с карты и из перма?", "Заправка", "Удалить", function()
                send("del", ent) fr:Close()
            end, "Отмена")
        end
        local hint = vgui.Create("DLabel", fr)
        hint:SetPos(16, 224) hint:SetSize(348, 24)
        hint:SetText("E — пистолет. Shift+E — касса. /permadd — закрепить.")
    end

    --[[ Сервер просит перерисовать окно после удачного действия.

         Ждём кадр перед открытием: NW-переменная OwnerKey прилетает
         отдельным пакетом, и без задержки меню собралось бы по старому
         значению — кнопка «Купить» осталась бы на месте, ровно как
         жаловался владелец. ]]
    net.Receive("GRM_Fuel_Station", function()
        local op = net.ReadString()
        local ent = net.ReadEntity()
        if op ~= "refresh" or not IsValid(ent) then return end
        if not IsValid(F._menu) then return end
        timer.Simple(0.15, function()
            if IsValid(ent) and IsValid(F._menu) then F.OpenStation(ent) end
        end)
    end)

    hook.Add("PlayerButtonDown", "GRM_Fuel_StationKey", function(ply, btn)
        if ply ~= LocalPlayer() or btn ~= KEY_E then return end
        if not input.IsKeyDown(KEY_LSHIFT) and not input.IsKeyDown(KEY_RSHIFT) then return end
        local tr = ply:GetEyeTrace()
        local e = IsValid(tr.Entity) and tr.Entity
        if IsValid(e) and e:GetClass() == "grm_fuel_pump" and ply:GetPos():DistToSqr(e:GetPos()) < 220 * 220 then
            F.OpenStation(e)
            return true
        end
    end)
end
