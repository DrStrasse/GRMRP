--[[--------------------------------------------------------------------
    GRM Estate Deal v1.0.0 — покупка бизнеса и жилья «одной командой».

    ЗАКАЗ ВЛАДЕЛЬЦА (28.08):

      «Если купил бизнес-зону, то автоматически присваивается владелец
       колонкам, автомату с едой и т.д. Всё оборудование в зоне бизнеса
       сразу автоматически выкупается и освобождается.»

      «Нужно для игроков придумать более красивое и простое меню нежели
       /property_admin. Продумай более адекватную покупку и продажу.»

      «Квартир/жилья также касается. Ближайшие двери к зоне или в зоне
       тоже автоматически приобретаются/продаются.»

    ЧТО БЫЛО НЕ ТАК.

      1) Купив зону, игрок получал ПУСТУЮ территорию. Каждый автомат и
         каждую колонку внутри приходилось выкупать отдельно, своей
         командой, стоя вплотную. Человек платил за бизнес и обнаруживал,
         что бизнеса у него нет.

      2) Покупка жила в /property_admin — админском окне со списком ВСЕХ
         объектов карты и полями вроде «ownerType/ownerKey». Обычному
         игроку там делать нечего.

      3) Зона жилья и двери квартиры existовали порознь: тул рисовал
         коробку, двери привязывались отдельно через другой тул. Купив
         «жильё», человек не мог открыть собственную дверь.

    ЧТО ДЕЛАЕТ ЭТОТ МОДУЛЬ.

      • ES.TransferEquipment — переписывает на нового владельца ВСЁ
        оборудование внутри зоны (автоматы, колонки) и снимает владельца
        при продаже. Одна операция вместо десяти.

      • ES.AttachDoors — притягивает к объекту двери, которые стоят
        внутри зоны или вплотную к ней, если они ещё ничьи. Купил
        квартиру — ключ от её двери у тебя.

      • Окно сделки (/buybusiness, /buyhome, /business) — крупное, с
        ценой, составом и одной кнопкой. Никаких CharacterKey руками.

    ПРИНЦИП: логику владения НЕ дублируем. Деньги, лимиты и запись в
    объект по-прежнему делает sh_grm_property через P.PanelAction —
    здесь только то, чего не хватало: передача содержимого зоны.
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.EstateDeal = GRM.EstateDeal or {}
local DL = GRM.EstateDeal

DL.Version = "1.0.0"
DL.NET = { OPEN = "GRM_EstateDeal_Open", ACT = "GRM_EstateDeal_Act" }

--[[ Насколько далеко от границы зоны дверь ещё считается «дверью этого
     объекта». Двери часто ставят чуть за коробкой, обведённой тулом, а
     требовать идеального попадания — значит гарантировать промахи. ]]
DL.DoorReach = 96

--- В каком радиусе от зоны игрок может оформить сделку.
DL.DealRange = 512

-----------------------------------------------------------------------
-- СЕРВЕР
-----------------------------------------------------------------------
if SERVER then
    util.AddNetworkString(DL.NET.OPEN)
    util.AddNetworkString(DL.NET.ACT)

    -- Ключ персонажа — канон ядра (§5.2.6): одна реализация на проект.
    local charKey = GRM.CharKey

    local function tell(ply, msg, good)
        if GRM.Notify then
            GRM.Notify(ply, msg, good and 110 or 255, good and 220 or 140, good and 130 or 110)
        elseif IsValid(ply) then
            ply:PrintMessage(HUD_PRINTTALK, "[Недвижимость] " .. msg)
        end
    end

    -----------------------------------------------------------------
    -- ПЕРЕДАЧА ОБОРУДОВАНИЯ
    -----------------------------------------------------------------
    --[[ Переписать всё оборудование зоны на ключ владельца.
         key == "" означает «снять владельца» (продажа, выселение).
         Возвращает, сколько единиц затронуто, и разбивку по видам. ]]
    function DL.TransferEquipment(rec, key)
        local ES = GRM.Estate
        if not (ES and ES.ScanZone and istable(rec)) then return 0, {} end
        key = tostring(key or "")

        local scan = ES.ScanZone(rec)
        local moved, byKind = 0, {}

        for _, ent in ipairs(scan.entities or {}) do
            if IsValid(ent) then
                local class = ent:GetClass()
                local done = false

                if class == "grm_vending_machine" then
                    --[[ Автомат: владелец в NW-поле и в самой entity.
                         Пишем оба, потому что сохранение читает второе. ]]
                    ent:SetNWString("GRM_VendOwner", key)
                    ent.GRMVendOwner = key
                    if GRM.VendingBiz and GRM.VendingBiz.MarkDirty then
                        GRM.VendingBiz.MarkDirty()
                    end
                    done = true
                elseif class == "grm_fuel_pump" and ent.SetOwnerKey then
                    ent:SetOwnerKey(key)
                    --[[ Колонке нужна цена: у бесхозной она могла быть
                         нулевой, и новый владелец торговал бы даром. ]]
                    if key ~= "" and ent.GetPriceL and ent.SetPriceL
                        and (ent:GetPriceL() or 0) <= 0 then
                        ent:SetPriceL((GRM.Fuel and GRM.Fuel.PricePerLiter) or 50)
                    end
                    done = true
                end

                if done then
                    moved = moved + 1
                    local info = ES.EquipmentClasses[class]
                    local kind = (info and info.kind) or class
                    byKind[kind] = (byKind[kind] or 0) + 1
                end
            end
        end

        -- Сохраняем один раз в конце, а не после каждой единицы.
        if moved > 0 then
            if GRM.VendingBiz and GRM.VendingBiz.Persist then
                pcall(GRM.VendingBiz.Persist, true)
            end
            if GRM.Fuel and GRM.Fuel.SavePumps then pcall(GRM.Fuel.SavePumps) end
            if ES.InvalidateScan then ES.InvalidateScan(rec) end
        end
        return moved, byKind
    end

    -----------------------------------------------------------------
    -- ПРИВЯЗКА ДВЕРЕЙ
    -----------------------------------------------------------------
    --[[ Дверь считается «дверью объекта», если стоит внутри зоны или
         не дальше DoorReach от её границы. Расширение нужно потому, что
         зону обводят снаружи дома, и дверное полотно нередко оказывается
         на самой грани коробки. ]]
    function DL.DoorNearZone(rec, pos)
        if not (istable(rec) and istable(rec.zone) and pos) then return false end
        local a, b = rec.zone.mins, rec.zone.maxs
        if not (a and b) then return false end
        local r = DL.DoorReach
        return pos.x >= a.x - r and pos.y >= a.y - r and pos.z >= a.z - r
           and pos.x <= b.x + r and pos.y <= b.y + r and pos.z <= b.z + r
    end

    --[[ Притянуть к объекту ничейные двери рядом с зоной.

         Чужие двери НЕ трогаем: если дверь уже принадлежит другому
         объекту, значит там своя квартира, и захват её покупкой соседней
         зоны был бы дырой. ]]
    function DL.AttachDoors(rec)
        local P = GRM.Property
        if not (P and istable(rec) and GRM.Doors and GRM.Doors.IsDoor) then return 0 end
        if not istable(rec.zone) then return 0 end

        rec.doors = istable(rec.doors) and rec.doors or {}
        local have = {}
        for _, id in ipairs(rec.doors) do have[tostring(id)] = true end

        local added = 0
        for _, ent in ipairs(ents.GetAll()) do
            if IsValid(ent) and GRM.Doors.IsDoor(ent) and DL.DoorNearZone(rec, ent:GetPos()) then
                local id = GRM.Doors.GetDoorID and GRM.Doors.GetDoorID(ent)
                if id and not have[tostring(id)] then
                    -- Занятую другим объектом дверь не забираем.
                    local owner = P.GetByDoorID and P.GetByDoorID(id)
                    if not owner then
                        rec.doors[#rec.doors + 1] = id
                        have[tostring(id)] = true
                        added = added + 1
                        if #rec.doors >= (P.Config and P.Config.MaxDoors or 64) then break end
                    end
                end
            end
        end

        if added > 0 then
            if P.Reindex then P.Reindex() end
            if P.Save then P.Save("estate-attach-doors") end
        end
        return added
    end

    -----------------------------------------------------------------
    -- РЕАКЦИЯ НА СМЕНУ ВЛАДЕЛЬЦА
    -----------------------------------------------------------------
    --[[ Главное место модуля. Кто бы ни сменил владельца — окно сделки,
         старое /property, рынок или админ — оборудование и двери
         переезжают вместе с объектом. Одна точка вместо правок в
         пяти местах. ]]
    hook.Add("GRM_PropertyOwnerChanged", "GRM_EstateDeal_Sync", function(rec, reason, ply)
        if not istable(rec) then return end
        local ES = GRM.Estate
        if not (ES and ES.KindOf) then return end
        if ES.KindOf(rec) == "none" then return end

        local owned = tostring(rec.ownerType or "") ~= "none"
        local key = owned and tostring(rec.ownerKey or "") or ""

        --[[ Двери притягиваем только когда объект обретает хозяина: при
             освобождении список дверей остаётся, иначе объект развалится
             и его нельзя будет купить снова. ]]
        if owned then DL.AttachDoors(rec) end

        local moved, byKind = DL.TransferEquipment(rec, key)
        if moved > 0 and IsValid(ply) and owned then
            local parts = {}
            local names = { vending = "автоматов", fuel = "колонок" }
            for kind, n in pairs(byKind) do
                parts[#parts + 1] = (names[kind] or kind) .. ": " .. n
            end
            tell(ply, "Оборудование переоформлено на вас — " ..
                table.concat(parts, ", "), true)
        end
    end)

    -----------------------------------------------------------------
    -- ПОКУПКА ДВЕРИ = ПОКУПКА ОБЪЕКТА
    -----------------------------------------------------------------
    --[[ Обратное направление (заказ владельца 28.08): раньше связь
         работала только «купил зону → получил двери». Обратно — нет:
         человек покупал дверь квартиры за цену двери, получал ключ, а
         сама квартира оставалась свободной и её мог купить другой.

         Теперь дверь, относящаяся к объекту недвижимости, продаётся
         только вместе с ним и по ПОЛНОЙ цене объекта.

         Возвращаем:
           nil   — дверь не наша, пусть модуль дверей продаёт как обычно;
           true  — объект оформлен;
           false — оформить не вышло (нет денег, занято, опечатано). ]]
    function DL.ClaimByDoor(ply, ent, rec, mode)
        local P, ES = GRM.Property, GRM.Estate
        if not (IsValid(ply) and IsValid(ent) and P and ES) then return nil end

        --[[ Ищем объект двумя путями. Сначала по привязке: дверь уже
             числится за объектом. Затем по зоне: тул обвёл территорию,
             но двери к объекту ещё не притянуты — именно этот случай
             владелец и описал («зона должна считывать купленную дверь»). ]]
        local target
        if P.GetByDoor then target = select(1, P.GetByDoor(ent)) end

        if not target and istable(P.Records) then
            local pos = ent:GetPos()
            for _, r in pairs(P.Records) do
                if ES.KindOf and ES.KindOf(r) ~= "none" and istable(r.zone) then
                    if DL.DoorNearZone(r, pos) then target = r break end
                end
            end
        end
        if not istable(target) then return nil end

        -- Объект занят: дверь от чужой квартиры не продаём вообще.
        if tostring(target.ownerType or "none") ~= "none" then
            tell(ply, "Эта дверь относится к объекту «" .. tostring(target.name or "")
                .. "», у которого уже есть владелец.", false)
            return false
        end
        if target.sealed == true then
            tell(ply, "Объект опечатан.", false)
            return false
        end

        --[[ Полная цена объекта, а не цена двери. mode приходит из меню
             двери: «rent» — аренда, иначе покупка навсегда. Сохраняем
             это различие, чтобы кнопка «арендовать» осталась арендой. ]]
        local act = (mode == "rent") and "rent" or "buy"
        local price = act == "rent"
            and (tonumber(target.rentPrice) or 0)
            or (tonumber(target.purchasePrice) or 0)

        tell(ply, ("Дверь принадлежит объекту «%s». %s объект целиком за %d GRM."):format(
            tostring(target.name or ""), act == "rent" and "Аренда" or "Покупка", price), true)

        --[[ Дальше всё делает property: деньги, лимиты, запись владельца.
             Он же бросит GRM_PropertyOwnerChanged, а по нему подтянутся
             двери и оборудование. Свою копию правил не заводим. ]]
        if P.PanelAction then
            P.PanelAction(ply, { action = act, id = target.id })
        end

        -- Успех определяем по факту: появился ли у объекта владелец.
        return tostring(target.ownerType or "none") ~= "none"
    end

    hook.Add("GRM_DoorClaimToProperty", "GRM_EstateDeal_ByDoor", function(ply, ent, rec, mode)
        return DL.ClaimByDoor(ply, ent, rec, mode)
    end)

    -----------------------------------------------------------------
    -- ОСВОБОЖДЕНИЕ ДВЕРИ = ПРОДАЖА ОБЪЕКТА ГОСУДАРСТВУ
    -----------------------------------------------------------------
    --[[ Заказ владельца 28.08: «если я через дверь нажал освободить, то
         дом сразу же должен быть продан государству».

         Раньше кнопка «ОСВОБОДИТЬ» в меню двери снимала владельца ТОЛЬКО
         с двери. Объект оставался за игроком, но без входа: внутрь не
         попасть, продать нельзя, деньги не вернулись. Теперь дверь
         объекта освобождается вместе с ним — и с выплатой.

         Возвращаем:
           nil   — дверь не наша, пусть модуль дверей освобождает как обычно;
           true  — объект продан государству;
           false — продать не вышло (не владелец, касса не снята). ]]
    function DL.ReleaseByDoor(ply, ent, rec)
        local P, ES = GRM.Property, GRM.Estate
        if not (IsValid(ply) and IsValid(ent) and P and ES) then return nil end

        -- Объект ищем так же, как при покупке: по привязке и по зоне.
        local target
        if P.GetByDoor then target = select(1, P.GetByDoor(ent)) end
        if not target and istable(P.Records) then
            local pos = ent:GetPos()
            for _, r in pairs(P.Records) do
                if ES.KindOf and ES.KindOf(r) ~= "none" and istable(r.zone) then
                    if DL.DoorNearZone(r, pos) then target = r break end
                end
            end
        end
        if not istable(target) then return nil end

        -- Свободный объект отдавать нечего: дверь освобождается сама.
        if tostring(target.ownerType or "none") == "none" then return nil end

        --[[ Освобождать чужое нельзя. Проверку прав отдаём property:
             своя копия правил владения — вторая точка для ошибки. ]]
        if not (P.CanManage and P.CanManage(ply, target)) then
            tell(ply, "Это не ваш объект — освобождать нечего.", false)
            return false
        end

        if ES.SellToState then
            local okSell, msg = ES.SellToState(ply, target)
            --[[ Частая причина отказа — несобранная касса бизнеса.
                 Сообщаем её игроку, иначе кнопка выглядит сломанной. ]]
            tell(ply, tostring(msg or (okSell and "Объект продан государству."
                or "Не удалось продать объект.")), okSell)
            return okSell == true
        end

        -- Рынка нет: освобождаем штатно, хотя бы без потери доступа.
        P.PanelAction(ply, { action = "release", id = target.id })
        tell(ply, "Объект освобождён.", true)
        return true
    end

    hook.Add("GRM_DoorReleaseToProperty", "GRM_EstateDeal_ReleaseByDoor", function(ply, ent, rec)
        return DL.ReleaseByDoor(ply, ent, rec)
    end)

    -----------------------------------------------------------------
    -- ДАННЫЕ ДЛЯ ОКНА СДЕЛКИ
    -----------------------------------------------------------------
    --- Объект, с которым игрок может заключить сделку прямо сейчас.
    function DL.TargetOf(ply, kind)
        local P, ES = GRM.Property, GRM.Estate
        if not (IsValid(ply) and P and istable(P.Records) and ES) then return nil end

        local pos = ply:GetPos()
        local best, bestDist

        for _, rec in pairs(P.Records) do
            local k = ES.KindOf and ES.KindOf(rec) or "none"
            local match = (kind == nil) or (k == kind)
            if match and k ~= "none" and istable(rec.zone) then
                local center = ES.ZoneCenter and ES.ZoneCenter(rec)
                if center then
                    local inside = ES.PointInZone and ES.PointInZone(rec, pos)
                    local d = pos:DistToSqr(center)
                    -- Внутри зоны — безусловный приоритет над «рядом».
                    local score = inside and -1 or d
                    if d <= DL.DealRange ^ 2 or inside then
                        if not bestDist or score < bestDist then
                            best, bestDist = rec, score
                        end
                    end
                end
            end
        end
        return best
    end

    --- Всё об объекте для окна сделки.
    function DL.Data(ply, rec)
        local ES = GRM.Estate
        local P = GRM.Property
        local scan = (ES and ES.ScanZone) and ES.ScanZone(rec) or { total = 0, byKind = {} }

        local doorsNear = 0
        if GRM.Doors and GRM.Doors.IsDoor then
            for _, ent in ipairs(ents.GetAll()) do
                if IsValid(ent) and GRM.Doors.IsDoor(ent) and DL.DoorNearZone(rec, ent:GetPos()) then
                    doorsNear = doorsNear + 1
                end
            end
        end

        local mine = tostring(rec.ownerType or "") == "character"
            and tostring(rec.ownerKey or "") == charKey(ply)

        return {
            id = tostring(rec.id or ""),
            name = tostring(rec.name or ""),
            kind = ES and ES.KindOf and ES.KindOf(rec) or "none",
            typeName = (P and P.Types and P.Types[rec.type]) or "Объект",
            vacant = tostring(rec.ownerType or "") == "none",
            mine = mine,
            owner = tostring(rec.ownerName or ""),
            sealed = rec.sealed == true,
            price = math.max(0, math.floor(tonumber(rec.purchasePrice) or 0)),
            rent = math.max(0, math.floor(tonumber(rec.rentPrice) or 0)),
            utility = math.max(0, math.floor(tonumber(rec.utilityRate) or 0)),
            debt = math.max(0, math.floor(tonumber(rec.utilityDebt) or 0)),
            equipment = scan.total or 0,
            byKind = scan.byKind or {},
            doors = doorsNear,
            area = (ES and ES.ZoneArea) and math.floor(ES.ZoneArea(rec) or 0) or 0,
            -- Сколько вернут при продаже государству.
            buyback = (ES and ES.StateBuyback)
                and math.floor((tonumber(rec.purchasePrice) or 0) * ES.StateBuyback) or 0,
        }
    end

    function DL.Open(ply, kind)
        if not IsValid(ply) then return false end
        local rec = DL.TargetOf(ply, kind)
        if not rec then
            tell(ply, kind == "business"
                and "Рядом нет бизнес-объекта. Подойдите к значку."
                or "Рядом нет подходящего объекта. Подойдите к значку.", false)
            return false
        end
        net.Start(DL.NET.OPEN)
            net.WriteTable(DL.Data(ply, rec))
        net.Send(ply)
        return true
    end

    -----------------------------------------------------------------
    -- ДЕЙСТВИЯ
    -----------------------------------------------------------------
    net.Receive(DL.NET.ACT, function(bits, ply)
        if not IsValid(ply) then return end
        if GRM.Net and GRM.Net.Guard
            and not GRM.Net.Guard(ply, "estate.deal", { rate = .4, burst = 3, maxBits = 4096 }, { bits = bits }) then
            return
        end
        local a = net.ReadTable() or {}
        local act = tostring(a.action or "")
        local P = GRM.Property
        if not P then return end

        local rec = P.Records and P.Records[tostring(a.id or "")]
        if not istable(rec) then return end

        -- Сделку заключают на месте, а не из другого конца карты.
        local ES = GRM.Estate
        local center = ES and ES.ZoneCenter and ES.ZoneCenter(rec)
        if center and ply:GetPos():DistToSqr(center) > DL.DealRange ^ 2 then
            local inside = ES.PointInZone and ES.PointInZone(rec, ply:GetPos())
            if not inside then tell(ply, "Подойдите к объекту.", false) return end
        end

        --[[ Деньги, лимиты и запись владельца делает property — мы лишь
             передаём ему намерение. Дублировать эти правила здесь значило
             бы завести вторую точку, где можно ошибиться. ]]
        if act == "buy" then
            P.PanelAction(ply, { action = "buy", id = rec.id })
        elseif act == "rent" then
            P.PanelAction(ply, { action = "rent", id = rec.id })
        elseif act == "sell" then
            if GRM.Estate and GRM.Estate.SellToState then
                local okSell, msg = GRM.Estate.SellToState(ply, rec)
                tell(ply, tostring(msg or (okSell and "Объект продан." or "Не удалось продать.")), okSell)
            else
                P.PanelAction(ply, { action = "release", id = rec.id })
            end
        elseif act == "pay" then
            P.PanelAction(ply, { action = "pay_utilities", id = rec.id })
        elseif act ~= "refresh" then
            return
        end

        timer.Simple(0.1, function()
            if IsValid(ply) and P.Records[rec.id] then
                net.Start(DL.NET.OPEN)
                    net.WriteTable(DL.Data(ply, P.Records[rec.id]))
                net.Send(ply)
            end
        end)
    end)

    -----------------------------------------------------------------
    -- КОМАНДЫ
    -----------------------------------------------------------------
    concommand.Add("grm_buybusiness", function(ply) DL.Open(ply, "business") end)
    concommand.Add("grm_buyhome", function(ply) DL.Open(ply, "estate") end)
    concommand.Add("grm_deal", function(ply) DL.Open(ply, nil) end)

    local CHAT = {
        ["/buybusiness"] = "business",
        ["/бизнес"]      = "business",
        ["/buyhome"]     = "estate",
        ["/жильё"]       = "estate",
        ["/жилье"]       = "estate",
        ["/buyestate"]   = "estate",
    }

    hook.Add("PlayerSay", "GRM_EstateDeal_Chat", function(ply, text)
        local s = string.lower(string.Trim(text or ""))
        local kind = CHAT[s]
        if kind then DL.Open(ply, kind) return "" end
    end)

    --- Диагностика: grm_deal_debug
    concommand.Add("grm_deal_debug", function(ply)
        if not IsValid(ply) then return end
        local function say(t) ply:PrintMessage(HUD_PRINTTALK, t) end
        local rec = DL.TargetOf(ply, nil)
        if not rec then say("[Сделка] рядом объектов нет") return end
        local d = DL.Data(ply, rec)
        say(("[Сделка] %s (%s) · %s"):format(d.name, d.typeName,
            d.vacant and "свободен" or ("владелец: " .. d.owner)))
        say(("  цена %d · оборудование %d · дверей рядом %d · площадь %d м²"):format(
            d.price, d.equipment, d.doors, d.area))
    end)

    if GRM.Modules and GRM.Modules.Register then
        GRM.Modules.Register("estate_deal", {
            label = "Сделки с недвижимостью",
            version = DL.Version,
            Depends = { "estate" },
        })
    end
end

-----------------------------------------------------------------------
-- КЛИЕНТ: ОКНО СДЕЛКИ
-----------------------------------------------------------------------
if CLIENT then
    surface.CreateFont("GRMDeal_Title", { font = "Roboto", size = 30, weight = 800, extended = true, antialias = true })
    surface.CreateFont("GRMDeal_Price", { font = "Roboto", size = 40, weight = 800, extended = true, antialias = true })
    surface.CreateFont("GRMDeal_Row",   { font = "Roboto", size = 16, weight = 600, extended = true, antialias = true })
    surface.CreateFont("GRMDeal_Small", { font = "Roboto", size = 13, weight = 500, extended = true, antialias = true })
    surface.CreateFont("GRMDeal_Btn",   { font = "Roboto", size = 17, weight = 800, extended = true, antialias = true })

    local C = {
        bg    = Color(13, 18, 26, 252),
        head  = Color(21, 29, 42, 255),
        card  = Color(23, 30, 43, 245),
        text  = Color(230, 238, 250),
        dim   = Color(146, 160, 180),
        gold  = Color(245, 198, 70),
        green = Color(96, 200, 130),
        red   = Color(216, 88, 84),
        blue  = Color(96, 168, 245),
    }

    local function send(a)
        net.Start(DL.NET.ACT) net.WriteTable(a) net.SendToServer()
    end

    local function bigBtn(parent, text, sub, col, fn)
        local b = vgui.Create("DButton", parent)
        b:SetText("")
        b.Paint = function(s, w, h)
            local c = s:IsHovered()
                and Color(math.min(255, col.r + 28), math.min(255, col.g + 28), math.min(255, col.b + 28))
                or col
            draw.RoundedBox(8, 0, 0, w, h, c)
            draw.SimpleText(text, "GRMDeal_Btn", w / 2, sub and h / 2 - 9 or h / 2,
                Color(16, 20, 28), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            if sub then
                draw.SimpleText(sub, "GRMDeal_Small", w / 2, h / 2 + 11,
                    Color(30, 38, 48), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end
        b.DoClick = fn
        return b
    end

    local KIND_NAME = { business = "БИЗНЕС", estate = "ЖИЛЬЁ" }
    local EQUIP_NAME = { vending = "торговых автоматов", fuel = "топливных колонок" }

    function DL.Show(d)
        if IsValid(DL._frame) then DL._frame:Remove() end

        local f = vgui.Create("DFrame")
        DL._frame = f
        f:SetTitle("")
        f:SetSize(560, 520)
        f:Center()
        f:MakePopup()
        f:ShowCloseButton(false)
        if GRM.UI and GRM.UI.Track then GRM.UI.Track("estate.deal", f) end

        local accent = d.kind == "business" and C.gold or C.green

        f.Paint = function(_, w, h)
            draw.RoundedBox(10, 0, 0, w, h, C.bg)
            draw.RoundedBoxEx(10, 0, 0, w, 78, C.head, true, true, false, false)
            draw.RoundedBox(0, 0, 76, w, 2, accent)
            draw.SimpleText(KIND_NAME[d.kind] or "ОБЪЕКТ", "GRMDeal_Small", 22, 16, accent)
            draw.SimpleText(d.name ~= "" and d.name or d.typeName, "GRMDeal_Title", 22, 32, C.text)
        end

        local x = vgui.Create("DButton", f)
        x:SetText("✕") x:SetFont("GRMDeal_Title") x:SetTextColor(color_white)
        x:SetSize(36, 32) x:SetPos(f:GetWide() - 46, 14)
        x.Paint = function(s, w, h)
            draw.RoundedBox(6, 0, 0, w, h, s:IsHovered() and Color(168, 60, 60) or Color(44, 30, 34))
        end
        x.DoClick = function() f:Close() end

        -- Цена крупно: главное, ради чего игрок открыл окно.
        local price = vgui.Create("DPanel", f)
        price:SetPos(20, 94) price:SetSize(f:GetWide() - 40, 92)
        price.Paint = function(_, w, h)
            draw.RoundedBox(8, 0, 0, w, h, C.card)
            draw.RoundedBox(0, 0, 0, 3, h, accent)
            if d.sealed then
                draw.SimpleText("ОБЪЕКТ ОПЕЧАТАН", "GRMDeal_Price", 20, 22, C.red)
                draw.SimpleText("Покупка невозможна", "GRMDeal_Small", 22, 66, C.dim)
            elseif d.mine then
                draw.SimpleText("ВАШ ОБЪЕКТ", "GRMDeal_Price", 20, 22, C.green)
                draw.SimpleText("Вернут при продаже: " .. d.buyback .. " GRM",
                    "GRMDeal_Small", 22, 66, C.dim)
            elseif d.vacant then
                draw.SimpleText(d.price .. " GRM", "GRMDeal_Price", 20, 22, accent)
                draw.SimpleText("Аренда: " .. d.rent .. " GRM  ·  ЖКХ: " .. d.utility .. " GRM за период",
                    "GRMDeal_Small", 22, 66, C.dim)
            else
                draw.SimpleText("ЗАНЯТО", "GRMDeal_Price", 20, 22, C.red)
                draw.SimpleText("Владелец: " .. (d.owner ~= "" and d.owner or "неизвестен"),
                    "GRMDeal_Small", 22, 66, C.dim)
            end
        end

        -- Что входит в сделку.
        local body = vgui.Create("DScrollPanel", f)
        body:SetPos(20, 196) body:SetSize(f:GetWide() - 40, 216)

        local function card(tall, paint)
            local p = vgui.Create("DPanel", body)
            p:Dock(TOP) p:DockMargin(0, 0, 0, 8) p:SetTall(tall)
            p.Paint = paint
            return p
        end

        card(34, function(_, w, h)
            draw.SimpleText("ЧТО ВХОДИТ В СДЕЛКУ", "GRMDeal_Small", 2, 12, accent)
        end)

        if d.kind == "business" then
            local lines = {}
            for kind, n in pairs(d.byKind or {}) do
                lines[#lines + 1] = (EQUIP_NAME[kind] or kind) .. ": " .. n
            end
            card(d.equipment > 0 and 68 or 52, function(_, w, h)
                draw.RoundedBox(6, 0, 0, w, h, C.card)
                draw.RoundedBox(0, 0, 0, 3, h, C.blue)
                if d.equipment > 0 then
                    draw.SimpleText("Оборудование: " .. d.equipment .. " шт.",
                        "GRMDeal_Row", 16, 12, C.text)
                    draw.SimpleText(table.concat(lines, "  ·  "), "GRMDeal_Small", 16, 34, C.dim)
                    draw.SimpleText("Переходит к вам автоматически", "GRMDeal_Small", 16, 50, C.green)
                else
                    draw.SimpleText("Оборудования внутри пока нет", "GRMDeal_Row", 16, 16, C.dim)
                end
            end)
        end

        card(52, function(_, w, h)
            draw.RoundedBox(6, 0, 0, w, h, C.card)
            draw.RoundedBox(0, 0, 0, 3, h, C.blue)
            draw.SimpleText("Дверей рядом: " .. d.doors, "GRMDeal_Row", 16, 10, C.text)
            draw.SimpleText(d.doors > 0 and "Ключи перейдут к вам автоматически"
                or "Дверей у объекта нет", "GRMDeal_Small", 16, 30,
                d.doors > 0 and C.green or C.dim)
        end)

        card(44, function(_, w, h)
            draw.RoundedBox(6, 0, 0, w, h, C.card)
            draw.SimpleText("Площадь: " .. d.area .. " м²", "GRMDeal_Row", 16, 12, C.dim)
        end)

        if d.debt > 0 then
            card(44, function(_, w, h)
                draw.RoundedBox(6, 0, 0, w, h, C.card)
                draw.RoundedBox(0, 0, 0, 3, h, C.red)
                draw.SimpleText("Долг по ЖКХ: " .. d.debt .. " GRM", "GRMDeal_Row", 16, 12, C.red)
            end)
        end

        -- Кнопки.
        local bw = (f:GetWide() - 52) / 2
        if d.sealed then
            -- Ничего не предлагаем: объект закрыт.
        elseif d.mine then
            local sell = bigBtn(f, "ПРОДАТЬ ГОСУДАРСТВУ", d.buyback .. " GRM", C.red, function()
                Derma_Query("Продать объект государству за " .. d.buyback .. " GRM?\n" ..
                    "Оборудование и ключи вы потеряете.", "Сделка",
                    "Продать", function() send({ action = "sell", id = d.id }) end, "Отмена")
            end)
            sell:SetPos(20, 428) sell:SetSize(bw, 56)
            if d.debt > 0 then
                local pay = bigBtn(f, "ОПЛАТИТЬ ЖКХ", d.debt .. " GRM", C.green, function()
                    send({ action = "pay", id = d.id })
                end)
                pay:SetPos(32 + bw, 428) pay:SetSize(bw, 56)
            end
        elseif d.vacant then
            local buy = bigBtn(f, "КУПИТЬ", d.price .. " GRM", accent, function()
                send({ action = "buy", id = d.id })
            end)
            buy:SetPos(20, 428) buy:SetSize(bw, 56)
            local rent = bigBtn(f, "АРЕНДОВАТЬ", d.rent .. " GRM / нед.", C.blue, function()
                send({ action = "rent", id = d.id })
            end)
            rent:SetPos(32 + bw, 428) rent:SetSize(bw, 56)
        end
    end

    net.Receive(DL.NET.OPEN, function() DL.Show(net.ReadTable() or {}) end)
end

-- Вечер-18: команда разбирается внутри парсера модуля (не литералом в
-- хуке) — регистрируем её множество в едином внешнем словаре библиотеки,
-- иначе на режиме она стала бы «неизвестной» до цепочки.
if GRM and GRM.Chat and GRM.Chat.RegisterExternalCommands then
    GRM.Chat.RegisterExternalCommands({ "/buybusiness", "/buyestate", "/buyhome", "/бизнес", "/жилье", "/жильё" })
end
