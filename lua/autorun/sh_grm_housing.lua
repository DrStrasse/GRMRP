--[[--------------------------------------------------------------------
    GRM Housing v1.0.0 — жильё на реальных дверях. Фаза 1: ядро.

    РЕШЕНИЕ ВЛАДЕЛЬЦА (27.08), вариант «А»:

        «Жильё = реальные двери на карте. Зона только для маркера и
         подсчёта. Ставите дом → выбираете его двери → купивший получает
         ключ. Спавн — внутрь квартиры.»

    И на два вопроса — «да»:
      • жильё даёт хранилище, отдых и приватность, не только спавн;
      • полиция входит по ордеру, взлом и обыск работают.

    ЧТО ЭТОТ МОДУЛЬ ДЕЛАЕТ И ЧЕГО НЕ ДЕЛАЕТ.

    Он НЕ переписывает недвижимость. Объекты, двери, ключи, аренда,
    коммуналка, опечатка и ордера уже живут в sh_grm_property.lua и
    sh_grm_doors.lua. Здесь только то, чего не хватало именно ЖИЛЬЮ:

      1) ЕДИНОЕ ОПРЕДЕЛЕНИЕ. Раньше «это жильё?» проверялось в трёх
         местах по-разному (type == "apartment" в одном файле,
         estateKind в другом). Теперь одна функция HS.IsHousing.

      2) СПАВН ВНУТРЬ КВАРТИРЫ. Раньше игрока ставили в центр зоны на
         mins.z + 8. Зона обводится тулом СНАРУЖИ дома, поэтому центр
         легко оказывался в стене, на лестнице или под полом. Теперь
         точка ищется от двери и проверяется на пригодность.

      3) ОТДЫХ ДОМА. Дома медленнее тратятся сытость и жажда: жильё
         должно окупать коммуналку хоть чем-то.

      4) ЕДИНАЯ ПРОВЕРКА ВХОДА в правильном порядке приоритетов:
         опечатка → ордер → ключ. Именно так, потому что опечатанный
         объект закрыт и для владельца, а ордер сильнее отсутствия ключа.

    ФАЗЫ 2-4 (хранилище, обыск с уведомлением, окно квартиры) — отдельно,
    см. CONCEPT_HOUSING_V1.md.
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Housing = GRM.Housing or {}
local HS = GRM.Housing

HS.Version = "1.0.0"

-----------------------------------------------------------------------
-- ОБЩАЯ ЧАСТЬ
-----------------------------------------------------------------------

--[[ Насколько медленнее тратятся сытость и жажда дома. 0.45 — примерно
     вдвое; полностью останавливать нельзя, иначе выгодно залогиниться
     дома и уйти на сутки. ]]
local cvRest = CreateConVar("grm_housing_rest", "0.45",
    bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED),
    "Множитель траты сытости и жажды дома (1 — как на улице, 0.45 — вдвое медленнее)")

--- Насколько поднять игрока над полом при спавне, чтобы не застрять в нём.
HS.SpawnLift = 6

--- Как далеко от двери искать пол комнаты.
HS.DoorInset = 48

-- Ключ персонажа — канон ядра (§5.2.6): одна реализация на проект,
-- ранняя привязка безопасна, sh_01_grm_core.lua грузится первым.
local charKey = GRM.CharKey
HS.CharKey = charKey

--[[ ЕДИНОЕ ОПРЕДЕЛЕНИЕ ЖИЛЬЯ.

     Тип «квартира» — основной признак. Но админ может пометить объект
     как жильё явно через estateKind (например, частный дом заведён типом
     «магазин» по ошибке). Явная пометка сильнее типа — так же, как это
     уже работает в GRM.Estate.KindOf. ]]
function HS.IsHousing(rec)
    if not istable(rec) then return false end
    local kind = tostring(rec.estateKind or "")
    if kind == "estate" then return true end
    if kind == "business" then return false end
    return tostring(rec.type or "") == "apartment"
end

--- Все объекты жилья.
function HS.All()
    local out = {}
    local P = GRM.Property
    if not (P and istable(P.Records)) then return out end
    for _, rec in pairs(P.Records) do
        if HS.IsHousing(rec) then out[#out + 1] = rec end
    end
    return out
end

--[[ Живая ли аренда. Просроченная аренда означает, что человек больше
     не жилец: ни спавна, ни отдыха, ни ключа. ]]
function HS.RentAlive(rec)
    if not istable(rec) then return false end
    if tostring(rec.tenure or "") ~= "rent" then return true end
    local untilAt = tonumber(rec.rentUntil) or 0
    if untilAt <= 0 then return true end
    return untilAt >= os.time()
end

--- Кому это жильё принадлежит по-настоящему (владение или живая аренда).
function HS.IsOwner(ply, rec)
    if not (IsValid(ply) and istable(rec)) then return false end
    if tostring(rec.ownerType or "") ~= "character" then return false end
    if tostring(rec.ownerKey or "") ~= charKey(ply) then return false end
    return HS.RentAlive(rec)
end

--[[ ЕДИНАЯ ПРОВЕРКА ВХОДА. Порядок приоритетов важен и он такой:

       1. Опечатка — сильнее всего. Опечатанный объект закрыт даже для
          владельца, иначе опечатка не имеет смысла как мера.
       2. Ордер — сильнее ключа. Полиция входит законно, без ключа.
       3. Ключ — обычный доступ (владелец, жилец, гость, временный ключ).

     Возвращает: можно ли войти, причина (строка-код), человеческий текст. ]]
function HS.CanEnter(ply, rec)
    if not IsValid(ply) then return false, "invalid", "" end
    if not istable(rec) then return true, "not_housing", "" end

    local P = GRM.Property

    -- Админ проходит всегда: иначе он не сможет чинить объекты.
    if P and P.CanAdmin and P.CanAdmin(ply) then
        return true, "admin", "Административный доступ"
    end

    if rec.sealed == true then
        local why = tostring(rec.sealReason or "")
        return false, "sealed",
            "Объект опечатан: " .. (why ~= "" and why or "доступ запрещён")
    end

    --[[ Ордер. Проверяем и ордер на конкретный объект, и ордер на
         владельца — суд может выписать любой из двух. ]]
    local D = GRM.Doors
    if D then
        if D.HasPropertyWarrant and D.HasPropertyWarrant(tostring(rec.id or ""), "search") then
            return true, "warrant_property", "Вход по ордеру на обыск помещения"
        end
        if D.HasWarrant and tostring(rec.ownerType or "") == "character"
            and tostring(rec.ownerKey or "") ~= "" then
            -- Ордер на владельца даёт право войти только тому, кто вправе
            -- вести розыск: иначе любой прохожий заходил бы в квартиру
            -- разыскиваемого.
            local mayAct = GRM.Access and GRM.Access.Can
                and GRM.Access.Can(ply, "wanted.civil.edit") == true
            if mayAct and D.HasWarrant(rec.ownerKey) then
                return true, "warrant_owner", "Вход по ордеру на владельца"
            end
        end
    end

    if P and P.HasAccess and P.HasAccess(ply, rec) then
        if not HS.RentAlive(rec) then
            return false, "rent_expired", "Аренда закончилась."
        end
        return true, "key", "Есть ключ"
    end

    local name = tostring(rec.name or "")
    return false, "no_key",
        "Нет ключа от объекта" .. (name ~= "" and " «" .. name .. "»" or "") .. "."
end

-----------------------------------------------------------------------
-- СЕРВЕР
-----------------------------------------------------------------------
if SERVER then

    --- Найти дверь объекта по её ID (двери живут в мире, а не в записи).
    local function doorByID(id)
        if not (GRM.Doors and GRM.Doors.IsDoor and GRM.Doors.GetDoorID) then return nil end
        for _, e in ipairs(ents.GetAll()) do
            if IsValid(e) and GRM.Doors.IsDoor(e) and GRM.Doors.GetDoorID(e) == id then
                return e
            end
        end
        return nil
    end
    HS.DoorByID = doorByID

    --- Все существующие в мире двери объекта.
    function HS.Doors(rec)
        local out = {}
        if not istable(rec) then return out end
        for _, id in ipairs(rec.doors or {}) do
            local e = doorByID(id)
            if IsValid(e) then out[#out + 1] = e end
        end
        return out
    end

    --[[ ПРИГОДНА ЛИ ТОЧКА ДЛЯ СПАВНА.

         Проверяем ровно то, что ломало старый спавн «в центр зоны»:
         не в стене ли, есть ли под ногами пол, хватает ли места по
         росту стоящего игрока. Хулл-трейс, а не точечный: точечный
         пролезает в щели, куда игрок не влезет. ]]
    local STAND_MINS = Vector(-16, -16, 0)
    local STAND_MAXS = Vector(16, 16, 72)

    function HS.PointFits(pos, ignore)
        if not pos then return false end
        local tr = util.TraceHull({
            start = pos,
            endpos = pos,
            mins = STAND_MINS,
            maxs = STAND_MAXS,
            filter = ignore,
            mask = MASK_PLAYERSOLID,
        })
        if tr.StartSolid or tr.Hit then return false end

        -- Под ногами должен быть пол, иначе игрок появится в воздухе
        -- (или в шахте лифта) и улетит вниз.
        local down = util.TraceLine({
            start = pos + Vector(0, 0, 4),
            endpos = pos - Vector(0, 0, 96),
            filter = ignore,
            mask = MASK_PLAYERSOLID,
        })
        return down.Hit == true
    end

    --[[ ТОЧКА СПАВНА В КВАРТИРЕ.

         Порядок поиска:
           1) точка, заданная админом вручную (rec.housingSpawn) — она
              всегда точнее любой эвристики;
           2) пол рядом с дверью, СО СТОРОНЫ КОМНАТЫ. Пробуем обе стороны
              двери и берём ту, где игрок помещается. Так работает,
              потому что дверь всегда на границе жилья;
           3) центр зоны — прежнее поведение, крайний случай.

         Возвращает позицию и угол (лицом от двери, внутрь комнаты). ]]
    function HS.SpawnPoint(rec)
        if not istable(rec) then return nil end

        --[[ 0) КРОВАТЬ (заказ владельца 28.08). Самый приоритетный
             источник: это явная, поставленная руками метка, которую
             видит и понимает сам игрок. Она точнее и ручной админской
             точки, и тем более эвристики «от двери внутрь комнаты». ]]
        local BED = GRM.HomeBed
        if BED and BED.SpawnPointFor then
            local bpos, bang = BED.SpawnPointFor(rec)
            if bpos then return bpos, bang or Angle(0, 0, 0), "bed" end
        end

        -- 1) Ручная точка.
        local manual = rec.housingSpawn
        if istable(manual) and tonumber(manual.x) then
            local pos = Vector(tonumber(manual.x) or 0, tonumber(manual.y) or 0,
                tonumber(manual.z) or 0)
            return pos, Angle(0, tonumber(manual.yaw) or 0, 0), "manual"
        end

        -- 2) От двери внутрь.
        for _, door in ipairs(HS.Doors(rec)) do
            local dpos = door:GetPos()
            -- У дверей ось Forward смотрит вдоль полотна, поэтому берём
            -- обе горизонтальные стороны и проверяем каждую.
            local fwd = door:GetForward()
            fwd.z = 0
            if fwd:Length() < 0.1 then fwd = Vector(1, 0, 0) end
            fwd:Normalize()
            local right = door:GetRight()
            right.z = 0
            if right:Length() > 0.1 then right:Normalize() end

            local candidates = {
                dpos + fwd * HS.DoorInset,
                dpos - fwd * HS.DoorInset,
                dpos + right * HS.DoorInset,
                dpos - right * HS.DoorInset,
            }
            for _, c in ipairs(candidates) do
                -- Опускаем кандидата на пол.
                local down = util.TraceLine({
                    start = c + Vector(0, 0, 40),
                    endpos = c - Vector(0, 0, 200),
                    mask = MASK_PLAYERSOLID,
                })
                local ground = down.Hit and (down.HitPos + Vector(0, 0, HS.SpawnLift)) or nil
                if ground and HS.PointFits(ground) then
                    --[[ Разворачиваем игрока от двери вглубь комнаты:
                         человек, вошедший домой, стоит лицом в квартиру,
                         а не носом в дверное полотно. ]]
                    local look = (ground - dpos)
                    look.z = 0
                    local yaw = look:Length() > 1 and look:Angle().y or 0
                    return ground, Angle(0, yaw, 0), "door"
                end
            end
        end

        -- 3) Центр зоны — как раньше.
        if GRM.Estate and GRM.Estate.ZoneCenter then
            local center = GRM.Estate.ZoneCenter(rec)
            if center then
                local down = util.TraceLine({
                    start = center + Vector(0, 0, 64),
                    endpos = center - Vector(0, 0, 512),
                    mask = MASK_PLAYERSOLID,
                })
                local ground = down.Hit and (down.HitPos + Vector(0, 0, HS.SpawnLift)) or center
                return ground, Angle(0, 0, 0), "zone"
            end
        end

        return nil
    end

    --- Жильё конкретного игрока (первое подходящее).
    function HS.HomeOf(ply)
        if not IsValid(ply) then return nil end
        local P = GRM.Property
        if not (P and istable(P.Records)) then return nil end
        for _, rec in pairs(P.Records) do
            if HS.IsHousing(rec) and rec.sealed ~= true and HS.RentAlive(rec) then
                if HS.IsOwner(ply, rec) then return rec end
                -- Жилец с ключом тоже вправе появляться дома.
                if tostring(rec.ownerType or "") ~= "none"
                    and P.HasAccess and P.HasAccess(ply, rec) then
                    return rec
                end
            end
        end
        return nil
    end

    --[[ ИГРОК ДОМА? Именно внутри зоны своего жилья. Зона тут уместна:
         для «дома или нет» точность в полметра не нужна, а трейсить
         комнаты каждую секунду дорого. ]]
    function HS.IsHome(ply)
        if not IsValid(ply) then return false, nil end
        local P = GRM.Property
        if not (P and istable(P.Records) and P.IsInside) then return false, nil end
        local pos = ply:GetPos()
        for _, rec in pairs(P.Records) do
            if HS.IsHousing(rec) and istable(rec.zone) and P.IsInside(rec, pos) then
                if rec.sealed ~= true and HS.RentAlive(rec) then
                    if HS.IsOwner(ply, rec)
                        or (P.HasAccess and P.HasAccess(ply, rec) and rec.ownerType ~= "none") then
                        return true, rec
                    end
                end
            end
        end
        return false, nil
    end

    --[[ МНОЖИТЕЛЬ ОТДЫХА. Дома сытость и жажда тратятся медленнее.
         Возвращает 1 на улице и значение конвара дома. ]]
    function HS.RestFactor(ply)
        if not HS.IsHome(ply) then return 1 end
        return math.Clamp(cvRest:GetFloat(), 0.05, 1)
    end

    --[[ Встраиваемся в расход еды и воды через хук, а не правкой чисел
         в sv_grm_food: так модуль питания остаётся независимым, а отдых
         можно отключить одним конваром. ]]
    hook.Add("GRM_Food_DrainScale", "GRM_Housing_Rest", function(ply)
        local f = HS.RestFactor(ply)
        if f < 1 then return f end
    end)

    --[[ Отметка «дома» для клиента: HUD и другие модули могут показать
         игроку, что он отдыхает. Пишем только при изменении — NW-запись
         каждую секунду на каждого игрока это лишний трафик.

         Приоритет low: это индикатор отдыха, а не игровая логика, и
         секунда задержки никому не видна. Обход порционный — проверка
         зон сразу для всех игроков давала бы пик на большом онлайне. ]]
    local function homeFlagFor(ply)
        if not IsValid(ply) then return end
        local home = HS.IsHome(ply)
        if ply:GetNWBool("GRM_AtHome", false) ~= home then
            ply:SetNWBool("GRM_AtHome", home)
        end
    end

    local function homeFlagList()
        return (GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()
    end

    if GRM.Sched then
        GRM.Sched.EverySpread("housing.homeflag", 2, homeFlagList, homeFlagFor,
            { prio = "low", chunk = 8 })
    else
        timer.Create("GRM_Housing_HomeFlag", 2, 0, function()
            for _, ply in ipairs(homeFlagList()) do homeFlagFor(ply) end
        end)
    end


    --[[ ЗАПРЕТ ВХОДА. Подключаемся к тому же хуку, что и недвижимость,
         но НЕ дублируем его логику: property уже отвечает за ключи.
         Наш хук нужен для жилья с просроченной арендой — этот случай
         property не проверял, и бывший жилец продолжал открывать дверь. ]]
    hook.Add("GRM_DoorAccessOverride", "GRM_Housing_Rent", function(ply, door)
        local P = GRM.Property
        if not (P and P.GetByDoor) then return end
        local rec = P.GetByDoor(door)
        if not (istable(rec) and HS.IsHousing(rec)) then return end
        if HS.RentAlive(rec) then return end
        -- Аренда кончилась: пускаем только админа и по ордеру.
        local allowed, reason, text = HS.CanEnter(ply, rec)
        if allowed and (reason == "admin" or reason == "warrant_property"
            or reason == "warrant_owner") then
            return true, reason
        end
        return false, "Аренда этого жилья закончилась."
    end)

    -----------------------------------------------------------------
    -- РУЧНАЯ ТОЧКА СПАВНА (админ)
    -----------------------------------------------------------------
    --[[ Эвристика «от двери» хороша, но в сложной планировке админ
         должен уметь поставить точку сам: встал куда надо и записал. ]]
    function HS.SetSpawn(ply, rec)
        local P = GRM.Property
        if not (IsValid(ply) and istable(rec)) then return false, "Нет объекта" end
        if not (P and P.CanAdmin and P.CanAdmin(ply)) then return false, "Нет прав" end
        local pos = ply:GetPos()
        rec.housingSpawn = { x = pos.x, y = pos.y, z = pos.z, yaw = ply:EyeAngles().y }
        if P.Save then P.Save("housing-spawn") end
        return true, "Точка входа в жильё записана."
    end

    function HS.ClearSpawn(ply, rec)
        local P = GRM.Property
        if not (IsValid(ply) and istable(rec)) then return false, "Нет объекта" end
        if not (P and P.CanAdmin and P.CanAdmin(ply)) then return false, "Нет прав" end
        rec.housingSpawn = nil
        if P.Save then P.Save("housing-spawn-clear") end
        return true, "Точка входа сброшена — снова ищется автоматически."
    end

    --- Объект, внутри зоны которого стоит игрок (для админ-команд).
    function HS.HousingAt(pos)
        local P = GRM.Property
        if not (P and istable(P.Records) and P.IsInside) then return nil end
        for _, rec in pairs(P.Records) do
            if HS.IsHousing(rec) and istable(rec.zone) and P.IsInside(rec, pos) then
                return rec
            end
        end
        return nil
    end

    concommand.Add("grm_housing_setspawn", function(ply)
        if not IsValid(ply) then return end
        local rec = HS.HousingAt(ply:GetPos())
        if not rec then
            ply:PrintMessage(HUD_PRINTTALK, "[Жильё] Встаньте внутри зоны жилья.")
            return
        end
        local ok, msg = HS.SetSpawn(ply, rec)
        ply:PrintMessage(HUD_PRINTTALK, "[Жильё] " .. tostring(msg))
    end)

    concommand.Add("grm_housing_clearspawn", function(ply)
        if not IsValid(ply) then return end
        local rec = HS.HousingAt(ply:GetPos())
        if not rec then
            ply:PrintMessage(HUD_PRINTTALK, "[Жильё] Встаньте внутри зоны жилья.")
            return
        end
        local ok, msg = HS.ClearSpawn(ply, rec)
        ply:PrintMessage(HUD_PRINTTALK, "[Жильё] " .. tostring(msg))
    end)

    --- Диагностика: grm_housing
    concommand.Add("grm_housing", function(ply)
        if not IsValid(ply) then return end
        local function say(t) ply:PrintMessage(HUD_PRINTTALK, t) end
        local all = HS.All()
        say("[Жильё] объектов жилья на карте: " .. #all)

        local home = HS.HomeOf(ply)
        if home then
            local pos, _, how = HS.SpawnPoint(home)
            say("  ваше жильё: " .. tostring(home.name or home.id)
                .. " · дверей: " .. #(home.doors or {})
                .. " · точка спавна: " .. tostring(how or "нет"))
            if not pos then
                say("  ВНИМАНИЕ: точку спавна найти не удалось — задайте grm_housing_setspawn")
            end
        else
            say("  своего жилья нет")
        end

        local atHome, rec = HS.IsHome(ply)
        say("  сейчас дома: " .. (atHome and ("да (" .. tostring(rec.name or rec.id) .. ")") or "нет")
            .. " · множитель трат: " .. string.format("%.2f", HS.RestFactor(ply)))

        local tr = ply:GetEyeTrace()
        if tr and IsValid(tr.Entity) and GRM.Property and GRM.Property.GetByDoor then
            local byDoor = GRM.Property.GetByDoor(tr.Entity)
            if byDoor then
                local allowed, reason, text = HS.CanEnter(ply, byDoor)
                say("  дверь под прицелом: " .. tostring(byDoor.name or byDoor.id)
                    .. " · вход: " .. (allowed and "да" or "нет")
                    .. " (" .. tostring(reason) .. ") " .. tostring(text or ""))
            end
        end
    end)

    if GRM.Modules and GRM.Modules.Register then
        GRM.Modules.Register("housing", {
            label = "Жильё",
            version = HS.Version,
            Status = function()
                return "объектов жилья: " .. tostring(#HS.All())
            end,
            Depends = { "property" },
        })
    end
end
