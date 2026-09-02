--[[--------------------------------------------------------------------
    GRM Interact — интерактивное взаимодействие с дверями и транспортом.

    ЗАКАЗ ВЛАДЕЛЬЦА (31.08): «при подходе к двери у персонажа появлялась
    точка маленькая, и подсказка нажмите Е для взаимодействия, возникает
    возле двери опять же круговое интерактивное живое меню с функцией
    открыть/закрыть и т.д., тоже самое касается двери машины. Можно
    конечно и свеп сохранить… нужно соблюсти стилистику проекта, и при
    этом чтобы текст не был чёрным».

    ЧТО БЫЛО. Управление замками жило только в SWEP «Дверные ключи»:
    надо достать оружие, прицелиться, помнить, что ЛКМ запирает, а ПКМ
    отпирает. У транспорта — свой SWEP со своими правилами. Никакой
    подсказки при подходе не было.

    ЧТО ЗДЕСЬ. Общая точка взаимодействия: подошёл — видишь точку и
    подсказку, зажал E — кольцевое меню с действиями именно для этого
    объекта. SWEP'ы никуда не делись, они работают параллельно.

    ПОЧЕМУ ОБЩИЙ МОДУЛЬ, А НЕ ДВА. Двери и транспорт отличаются только
    набором действий и проверкой прав. Всё остальное — поиск цели,
    подсказка, кольцо, сетевой обмен — одинаково. Два отдельных модуля
    означали бы две копии одного кода и, как это уже бывало в проекте,
    починку только одной из них.

    БЕЗОПАСНОСТЬ. Клиент присылает только «объект + id действия».
    Сервер сам находит цель, сам проверяет дистанцию и права —
    существующими функциями GRM.Doors / VehicleKeys, ничего не
    дублируя. Подделать пакет и открыть чужую дверь нельзя.
----------------------------------------------------------------------]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Interact = GRM.Interact or {}
local I = GRM.Interact
I.Version = "1.0.0"

I.Range = 130            -- дистанция взаимодействия, юниты
I.HintRange = 150        -- на какой дистанции показывать точку и подсказку

local NET_ACT = "GRM_Interact_Act"

-----------------------------------------------------------------------
-- ОБЩЕЕ: определение цели и список действий.
-- Живёт в shared, чтобы клиент рисовал ровно то, что разрешит сервер.
-----------------------------------------------------------------------

--[[ Что перед игроком: дверь, транспорт или ничего.

     Возвращает сущность и вид ("door" / "vehicle"). Отдельной
     функцией: её зовут и клиент (для подсказки), и сервер (для
     проверки) — расхождение здесь означало бы «вижу меню, но действие
     не проходит». ]]
function I.FindTarget(ply, range)
    if not IsValid(ply) then return nil end
    range = range or I.Range

    local tr = util.TraceLine({
        start = ply:GetShootPos(),
        endpos = ply:GetShootPos() + ply:GetAimVector() * range,
        filter = ply,
        mask = MASK_SHOT,
    })
    local ent = tr.Entity
    if not IsValid(ent) then return nil end

    local D = GRM.Doors
    if D and D.IsDoor then
        if D.IsDoor(ent) then return ent, "door" end
        -- Дверная ручка/косяк бывает отдельным энтити на родителе.
        local parent = ent:GetParent()
        if IsValid(parent) and D.IsDoor(parent) then return parent, "door" end
    end

    --[[ Модуль ключей ТС живёт в глобальной таблице VK, а не в
         GRM.VehicleKeys: так он объявлен в sh_vehicle_keys.lua. ]]
    local V = _G.VK
    if V and V.IsVehicle and V.IsVehicle(ent) then return ent, "vehicle" end
    -- Сиденья и части машины: у них родитель — сам транспорт.
    local vp = ent:GetParent()
    if IsValid(vp) and V and V.IsVehicle and V.IsVehicle(vp) then return vp, "vehicle" end

    return nil
end

--[[ ПРИКИДКА ДОСТУПА К ТРАНСПОРТУ НА КЛИЕНТЕ.

     Нужна ТОЛЬКО чтобы нарисовать меню: показать пункт живым или
     приглушённым. Решение всё равно принимает сервер в runAction —
     подделать эту функцию и получить чужую машину нельзя.

     Считаем по тем же полям, что сервер публикует через VK.SyncVehicle
     (NW2), и по тем же правилам, что в VK.CanInteract: владелец, своя
     фракция, бесхозная машина. Чего клиент знать не может — выданные
     ключи от чужой машины — трактуем в пользу игрока: пункт покажем
     живым, а сервер откажет с внятной причиной. Обратный вариант хуже:
     человек с ключом видел бы серые пункты и решил, что всё сломано. ]]
function I.ClientCanVehicle(ent, ply)
    local V = _G.VK
    if not V or not IsValid(ent) or not IsValid(ply) then return false end
    if ply.IsSuperAdmin and ply:IsSuperAdmin() then return true end

    local ownerType, ownerSteam, _, facName = "", "", "", ""
    if V.GetOwnerState then
        ownerType, ownerSteam, _, facName = V.GetOwnerState(ent)
    else
        ownerType = ent:GetNW2String("VK_OwnerType", "")
        ownerSteam = ent:GetNW2String("VK_OwnerSteam", "")
        facName = ent:GetNW2String("VK_FactionName", "")
    end

    -- Бесхозная машина открыта всем: так же считает и сервер.
    if ownerType == "" then return true end

    local OT = V.OWNER_TYPE or { PLAYER = "player", FACTION = "faction" }

    if ownerType == OT.FACTION then
        --[[ Фракцию сверяем по NW-полю игрока: ядро публикует его для
             текущего персонажа, и это ровно то, на что смотрит
             VK.IsFactionMember первым делом. ]]
        local mine = ply:GetNWString("GRM_Faction", "")
        return mine ~= "" and facName ~= "" and mine == facName
    end

    if ownerType == OT.PLAYER then
        if ownerSteam ~= "" and ownerSteam == ply:SteamID64() then return true end
        if ownerSteam ~= "" and ownerSteam == ply:SteamID() then return true end
        --[[ Владелец другой. Ключ мог быть выдан, но клиенту связка не
             приезжает — пусть решает сервер. ]]
        return true
    end

    return true
end

--[[ Владелец ли игрок этой машины — прикидка для показа пункта «Ключи».

     Отдельно от ClientCanVehicle: доступ к замку есть у всей фракции, а
     раздавать ключи вправе только хозяин. Решение, как всегда, за
     сервером — здесь лишь рисование. ]]
function I.ClientIsVehicleOwner(ent, ply)
    local V = _G.VK
    if not V or not IsValid(ent) or not IsValid(ply) then return false end
    if ply.IsSuperAdmin and ply:IsSuperAdmin() then return true end

    local ownerType, ownerSteam = "", ""
    if V.GetOwnerState then
        ownerType, ownerSteam = V.GetOwnerState(ent)
    else
        ownerType = ent:GetNW2String("VK_OwnerType", "")
        ownerSteam = ent:GetNW2String("VK_OwnerSteam", "")
    end
    local OT = V.OWNER_TYPE or { PLAYER = "player" }
    if ownerType ~= OT.PLAYER or ownerSteam == "" then return false end
    return ownerSteam == ply:SteamID64() or ownerSteam == ply:SteamID()
end

--[[ Действия для цели. Один список на клиента и сервер: клиент рисует
     его в кольце, сервер по нему же проверяет, что пришло.

     Каждое действие: id, подпись, и признак «доступно ли сейчас».
     Недоступные не прячем, а показываем приглушёнными — иначе игрок не
     понимает, чего ему не хватает. ]]
function I.Actions(ply, ent, kind)
    local out = {}
    if not IsValid(ply) or not IsValid(ent) then return out end

    if kind == "door" then
        local D = GRM.Doors
        if not D then return out end
        local locked = D.IsDoorLocked and D.IsDoorLocked(ent) or false

        --[[ Право на замок спрашиваем у ядра дверей. Своей проверки
             здесь нет намеренно: правила категорий, совладельцев и
             ордеров живут там, и вторая их копия неизбежно разойдётся
             с первой. ]]
        local canLock, lockWhy = true, nil
        if D.CanToggleLock then
            canLock, lockWhy = D.CanToggleLock(ply, ent, not locked)
        end

        out[#out + 1] = {
            id = locked and "door_unlock" or "door_lock",
            name = locked and "Отпереть" or "Запереть",
            enabled = canLock ~= false,
            why = lockWhy,
            accent = locked and "good" or "warn",
        }
        out[#out + 1] = { id = "door_knock", name = "Постучать", enabled = true }
        out[#out + 1] = { id = "door_menu", name = "Управление", enabled = true }
        return out
    end

    if kind == "vehicle" then
        local V = _G.VK
        if not V then return out end
        --[[ Состояние замка читаем из NW2: сервер синхронизирует его
             именно так (VK.SyncVehicle), и на клиенте поле ent.VK_Locked
             пустое — там оно только серверное. ]]
        local locked = ent:GetNW2Bool("VK_Locked", false)
        if SERVER then locked = ent.VK_Locked == true end

        --[[ ДОСТУП К ТРАНСПОРТУ (баг владельца 31.08: «пытаюсь через Е
             отпереть дверь машины, пишет нет ключа или доступа, хотя
             машина фракционная»).

             VK.CanInteract объявлена ТОЛЬКО на сервере
             (sv_vehicle_keys.lua) и читает серверные поля veh.VK_*. На
             клиенте её просто нет: вызов возвращал nil, и все пункты
             гасли с «Нет ключа или доступа» даже у своей фракции.

             Поэтому: на сервере спрашиваем ядро (оно и решает), а на
             клиенте прикидываем по сетевым полям — только чтобы
             нарисовать меню. Клиентская оценка НИ НА ЧТО не влияет:
             сервер всё равно перепроверяет права сам в runAction. ]]
        local can
        if SERVER then
            can = V.CanInteract and V.CanInteract(ent, ply, false) or false
        else
            can = I.ClientCanVehicle(ent, ply)
        end

        out[#out + 1] = {
            id = locked and "veh_unlock" or "veh_lock",
            name = locked and "Отпереть" or "Запереть",
            enabled = can,
            why = not can and "Нет ключа или доступа" or nil,
            accent = locked and "good" or "warn",
        }
        out[#out + 1] = {
            id = "veh_doors", name = "Открыть двери", enabled = can,
            why = not can and "Нет ключа или доступа" or nil,
        }
        out[#out + 1] = {
            id = "veh_trunk", name = "Багажник", enabled = can,
            why = not can and "Нет ключа или доступа" or nil,
        }

        --[[ ЛИЧНЫЕ КЛЮЧИ — здесь, а не на отдельной клавише.

             В старом свепе транспорта это висело на R и знал о нём
             только тот, кто прочитал подсказку оружия. Управлять
             ключами может ВЛАДЕЛЕЦ, а не всякий, у кого есть доступ:
             член фракции ездит на служебной машине, но раздавать от
             неё ключи не должен. Поэтому отдельная проверка уровня
             владельца, а не общий can. ]]
        local owner
        if SERVER then
            owner = V.CanInteract and V.CanInteract(ent, ply, true) or false
        else
            owner = I.ClientIsVehicleOwner(ent, ply)
        end
        out[#out + 1] = {
            id = "veh_keys", name = "Ключи", enabled = owner,
            why = not owner and "Только владелец машины" or nil,
        }
        return out
    end

    return out
end

-- Название цели для шапки кольца.
function I.TargetName(ent, kind)
    if not IsValid(ent) then return "" end
    if kind == "door" then
        local t = ent:GetNWString("GRM_DoorTitle", "")
        if t ~= "" then return t end
        return "Дверь"
    end
    if kind == "vehicle" then
        local V = _G.VK
        if V and V.GetVehicleDisplayName then
            local n = V.GetVehicleDisplayName(ent)
            if n and n ~= "" then return n end
        end
        return "Транспорт"
    end
    return ""
end

-- Подпись под названием: владелец и состояние замка.
function I.TargetSub(ent, kind)
    if not IsValid(ent) then return "", false end
    if kind == "door" then
        local locked = ent:GetNWBool("GRM_DoorLocked", false)
        local owner = ent:GetNWString("GRM_DoorOwner", "")
        return owner, locked
    end
    if kind == "vehicle" then
        -- NW2: см. VK.SyncVehicle. Имя поля владельца — VK_OwnerNick.
        local locked = ent:GetNW2Bool("VK_Locked", false)
        local owner = ent:GetNW2String("VK_OwnerNick", "")
        local fac = ent:GetNW2String("VK_FactionName", "")
        if owner == "" and fac ~= "" then owner = fac end
        return owner, locked
    end
    return "", false
end

-----------------------------------------------------------------------
if SERVER then
-----------------------------------------------------------------------
util.AddNetworkString(NET_ACT)

local function notify(ply, msg, r, g, b)
    if GRM.Notify then GRM.Notify(ply, msg, r or 255, g or 255, b or 255) end
end

--[[ Выполнение действия.

     Клиент присылает ТОЛЬКО сущность и id действия. Сервер заново
     находит цель, меряет дистанцию и спрашивает права у профильного
     модуля. Иначе поддельный пакет открывал бы любую дверь на карте. ]]
local function runAction(ply, ent, id)
    if not IsValid(ply) or not IsValid(ent) then return end

    -- Дистанция: меряем от глаз до ближайшей точки объекта, а не до
    -- его центра — у длинных ворот центр далеко, и честный игрок
    -- получал бы отказ.
    local near = ent:NearestPoint(ply:GetShootPos())
    if ply:GetShootPos():DistToSqr(near) > (I.Range * 1.35) ^ 2 then
        notify(ply, "Слишком далеко", 255, 160, 90)
        return
    end
    if not ply:Alive() then return end

    local kind
    if GRM.Doors and GRM.Doors.IsDoor and GRM.Doors.IsDoor(ent) then kind = "door"
    elseif _G.VK and _G.VK.IsVehicle and _G.VK.IsVehicle(ent) then kind = "vehicle" end
    if not kind then return end

    --[[ Действие обязано быть в списке, который СЕРВЕР считает
         допустимым для этой цели. Клиент мог прислать «veh_lock» для
         двери или действие, которое ему недоступно. ]]
    local allowed
    for _, a in ipairs(I.Actions(ply, ent, kind)) do
        if a.id == id then allowed = a break end
    end
    if not allowed then return end
    if allowed.enabled == false then
        ply:EmitSound("buttons/button10.wav", 65, 100, 0.7)
        notify(ply, tostring(allowed.why or "Недоступно"), 255, 100, 100)
        return
    end

    local D, V = GRM.Doors, _G.VK

    if id == "door_lock" or id == "door_unlock" then
        local want = (id == "door_lock")
        local okRun, _, forced = D.LockDoor(ent, want)
        if okRun == false then
            notify(ply, "Замок не поддаётся.", 255, 100, 100)
            return
        end
        if forced then
            ply:EmitSound("buttons/button10.wav", 65, 100, 0.7)
            notify(ply, "Эта дверь всегда заперта.", 255, 180, 90)
            return
        end
        ply:EmitSound(want and "doors/door_latch1.wav" or "doors/door_latch3.wav", 65, 100)
        notify(ply, want and "Дверь заперта." or "Дверь отперта.", 120, 220, 140)
        return
    end

    if id == "door_knock" then
        --[[ Стук слышат вокруг двери, а не только владелец: это
             отыгрышное действие, его смысл в том, чтобы человек за
             дверью услышал.

             СВОЙ КУЛДАУН, отдельно от общего ограничителя. Общий даёт
             серию из 4 действий подряд — для замка это нормально, а
             стук при этом бьёт звуком по всем вокруг, и подряд
             четырьмя ударами можно шуметь на весь квартал. Секунда
             между ударами отыгрышу не мешает, а спам обрывает. ]]
        ply._grmKnockAt = ply._grmKnockAt or 0
        if CurTime() < ply._grmKnockAt then return end
        ply._grmKnockAt = CurTime() + 1
        ent:EmitSound("physics/wood/wood_crate_impact_hard2.wav", 75, 100)
        notify(ply, "Вы постучали.", 200, 210, 225)
        return
    end

    if id == "door_menu" then
        if D.OpenDoorMenu then D.OpenDoorMenu(ply) end
        return
    end

    if id == "veh_lock" or id == "veh_unlock" then
        if V.ToggleLock then V.ToggleLock(ply, ent) end
        return
    end

    if id == "veh_doors" then
        if V.ToggleDoors then
            V.ToggleDoors(ent)
            notify(ply, "Двери транспорта переключены.", 120, 220, 140)
        end
        return
    end

    if id == "veh_trunk" then
        --[[ Багажник — отдельная система, и доступ она проверяет сама
             (та же точка входа, что у C-меню). Свою проверку прав тут
             не пишем: разошлась бы с той. Модуля нет в сборке —
             честно говорим, а не молчим: молчание игрок читает как
             «кнопка сломана». ]]
        if GRM.Trunk and GRM.Trunk.RequestToggle then
            GRM.Trunk.RequestToggle(ply)
        else
            notify(ply, "Модуль багажника не загружен.", 255, 180, 90)
        end
        return
    end

    --[[ veh_keys здесь НЕ обрабатывается намеренно.

         Окно выдачи личных ключей живёт в модуле ключей ТС и открывается
         его штатным запросом VK_RequestPlayerList: там сервер сам
         проверяет владельца и сам собирает список игроков. Клиент шлёт
         этот запрос напрямую (см. I.Apply), а мы не заводим вторую копию
         правил — она разошлась бы с оригиналом. ]]
end

net.Receive(NET_ACT, function(len, ply)
    --[[ Ограничитель: кольцо открывается часто, но действия — редко.
         Без него скриптом можно было бы щёлкать замком десятки раз в
         секунду и спамить звуком на всю улицу. ]]
    if GRM.Net and GRM.Net.Guard then
        if not GRM.Net.Guard(ply, "interact.act",
            { rate = 0.3, burst = 4, maxBits = 256 }, { bits = len }) then
            return
        end
    end
    local ent = net.ReadEntity()
    local id = string.sub(tostring(net.ReadString() or ""), 1, 32)
    runAction(ply, ent, id)
end)

print("[GRM Interact] server v" .. I.Version)
return
end

-----------------------------------------------------------------------
-- CLIENT
-----------------------------------------------------------------------
CreateClientConVar("grm_cl_interact", "1", true, false,
    "Показывать точку и подсказку взаимодействия у дверей и транспорта")

surface.CreateFont("GRMInt_Name", { font = "Roboto", size = 19, weight = 700, extended = true })
surface.CreateFont("GRMInt_Hint", { font = "Roboto", size = 15, weight = 600, extended = true })
surface.CreateFont("GRMInt_Small", { font = "Roboto", size = 13, weight = 500, extended = true })
surface.CreateFont("GRMInt_Ring", { font = "Roboto", size = 17, weight = 600, extended = true })

--[[ ПАЛИТРА — та же, что у остальных окон GRM (тёмный фон, светлый
     текст).

     Владелец 31.08 отдельно предупредил: «чтобы текст не был чёрным
     как иногда вы выдаёте, что фон меню тёмный, текст чёрный и ничего
     нечитабельно». Поэтому здесь НЕТ ни одного тёмного цвета текста, а
     все надписи поверх мира рисуются с чёрной обводкой — на светлой
     стене белый текст без неё тоже теряется. ]]
local C = {
    bg      = Color(16, 20, 28, 238),
    ring    = Color(10, 13, 19, 205),
    sector  = Color(62, 132, 220, 110),
    card    = Color(33, 41, 55, 245),
    text    = Color(236, 242, 250),
    dim     = Color(158, 172, 190),
    gold    = Color(245, 195, 65),
    good    = Color(104, 214, 138),
    warn    = Color(240, 170, 90),
    bad     = Color(226, 96, 92),
    shadow  = Color(0, 0, 0, 225),
}

-----------------------------------------------------------------------
-- ПАНЕЛЬ ДЕЙСТВИЙ (переделано 31.08 по заказу владельца).
--
-- «подсказка вылетает — нажмите ЛКМ для взаимодействия, он нажимает и
--  удержанием ЛКМ возникает красивое меню чем-то похожее на круговое,
--  но только прямоугольное и с плавно возникающими кнопками,
--  полупрозрачными, с обводкой».
--
-- ЧТО ИЗМЕНИЛОСЬ ПРОТИВ ПРЕЖНЕЙ ВЕРСИИ:
--   * кольцо заменено вертикальным списком карточек — в прямоугольнике
--     помещается длинная подпись и причина отказа, в секторе они не
--     влезали;
--   * кнопки появляются по очереди с лёгким наездом снизу, а не все
--     разом: глаз успевает проследить список;
--   * выбор мышью обычный, наведением — попадать в сектор по углу для
--     четырёх пунктов было лишним усложнением;
--   * подсказка рисуется РЯДОМ с объектом (проекция его позиции на
--     экран), а не в центре экрана.
-----------------------------------------------------------------------
local P = {
    open = false,
    items = {},
    sel = nil,
    ent = nil,
    kind = nil,
    at = 0,
}
I.Panel = P
-- Наружу отдаём под старым именем: на него смотрят стенды и StartCommand.
I.Radial = P

P.W = 268                 -- ширина карточки
P.H = 46                  -- высота карточки
P.Gap = 8
P.HeadH = 54              -- шапка с названием объекта
P.Appear = 0.055          -- задержка появления между кнопками

local hover = { ent = nil, kind = nil, alpha = 0 }

--[[ Геометрия панели. Отдельной функцией: её же зовёт выбор мышью, и
     рассогласование раскладки с выбором — тот самый класс багов, на
     котором в проекте уже ловились гизмо и кольцо анимаций. ]]
function P.Rect(count, sw, sh)
    local h = P.HeadH + count * P.H + (count - 1) * P.Gap + 16
    local x = math.floor((sw or ScrW()) * 0.5 - P.W * 0.5)
    local y = math.floor((sh or ScrH()) * 0.5 - h * 0.5)
    return x, y, P.W, h
end

function P.ItemRect(i, count, sw, sh)
    local x, y = P.Rect(count, sw, sh)
    return x + 10, y + P.HeadH + (i - 1) * (P.H + P.Gap), P.W - 20, P.H
end

function P.Pick(mx, my, count, sw, sh)
    for i = 1, count do
        local ix, iy, iw, ih = P.ItemRect(i, count, sw, sh)
        if mx >= ix and mx <= ix + iw and my >= iy and my <= iy + ih then return i end
    end
    return nil
end

function I.ClosePanel()
    P.open = false
    P.items, P.sel, P.ent, P.kind = {}, nil, nil, nil
    if IsValid(P.panel) then P.panel:Remove() end
    P.panel = nil
    gui.EnableScreenClicker(false)
end
-- Прежнее имя: его зовут хуки и стенды.
I.CloseRadial = I.ClosePanel

--[[ Краски селектора: прозрачность «дышит» каждый кадр, поэтому это не
    константы, а один скретч-Color (GMod-Color — таблица, draw/surface
    читают поля в момент вызова). Все места потребляют цвет немедленно:
    запись и отрисовка идут подряд, один объект на весь Paint безопасен
    (§6.1.8). ]]
local INT_C = Color(0, 0, 0, 255)
local function intCol(r, g, b, a)
    INT_C.r = r
    INT_C.g = g
    INT_C.b = b
    INT_C.a = a
    return INT_C
end

function I.OpenPanel(ent, kind)
    if IsValid(P.panel) then return end
    local ply = LocalPlayer()
    if not IsValid(ply) or not IsValid(ent) then return end

    P.items = I.Actions(ply, ent, kind)
    if #P.items == 0 then return end
    P.ent, P.kind, P.sel, P.at = ent, kind, nil, RealTime()

    local f = vgui.Create("DPanel")
    P.panel = f
    P.open = true
    f:SetSize(ScrW(), ScrH())
    f:SetPos(0, 0)
    f:SetPaintBackground(false)
    f:MakePopup()
    -- Клавиатуру не забираем: иначе не придёт отпускание ЛКМ и панель
    -- зависнет. Ровно этим болел инвентарь.
    f:SetKeyboardInputEnabled(false)
    gui.EnableScreenClicker(true)
    f.OnRemove = function() P.open = false P.panel = nil end

    f.Paint = function(_, w, h)
        local count = #P.items
        local mx, my = gui.MousePos()
        P.sel = P.Pick(mx, my, count, w, h)

        local x, y, pw, ph = P.Rect(count, w, h)
        local age = RealTime() - P.at

        --[[ Панель тоже въезжает: без этого она «щёлкает» на экране, и
             глазу не за что зацепиться. Ease-out — движение мягко
             тормозит, как у выезда инвентаря. ]]
        local pa = math.Clamp(age / 0.13, 0, 1)
        local pe = 1 - (1 - pa) * (1 - pa) * (1 - pa)
        y = math.floor(y + (1 - pe) * 18)
        local alpha = math.floor(pe * 255)

        -- Подложка: полупрозрачная, с обводкой.
        draw.RoundedBox(8, x, y, pw, ph, intCol(14, 18, 26, math.floor(226 * pe)))
        surface.SetDrawColor(58, 74, 98, math.floor(200 * pe))
        surface.DrawOutlinedRect(x, y, pw, ph, 1)

        -- Шапка: что за объект и заперт ли он.
        local name = I.TargetName(P.ent, P.kind)
        local owner, locked = I.TargetSub(P.ent, P.kind)
        draw.SimpleText(GRM.Utf8Ellipsis(name, 24), "GRMInt_Name", x + 14, y + 16,
            intCol(236, 242, 250, alpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(locked and "ЗАПЕРТО" or "ОТКРЫТО", "GRMInt_Small",
            x + pw - 14, y + 16,
            locked and intCol(226, 96, 92, alpha) or intCol(104, 214, 138, alpha),
            TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        if owner ~= "" then
            draw.SimpleText(GRM.Utf8Ellipsis(owner, 34), "GRMInt_Small", x + 14, y + 36,
                intCol(150, 166, 186, alpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        surface.SetDrawColor(48, 60, 80, math.floor(180 * pe))
        surface.DrawRect(x + 10, y + P.HeadH - 8, pw - 20, 1)

        for i, act in ipairs(P.items) do
            --[[ Кнопки проявляются по очереди. Своя дельта на каждую:
                 список «набегает» сверху вниз и читается как единое
                 движение, а не как вспышка. ]]
            local d = math.Clamp((age - (i - 1) * P.Appear) / 0.16, 0, 1)
            if d > 0 then
                local e = 1 - (1 - d) * (1 - d) * (1 - d)
                local a = math.floor(e * 255)
                local ix, iy, iw, ih = P.ItemRect(i, count, w, h)
                iy = math.floor(iy + (1 - e) * 12 + (1 - pe) * 18)

                local on = (P.sel == i)
                local off = (act.enabled == false)

                -- Полупрозрачная заливка + обводка, как и просили.
                local bg = intCol(30, 38, 52, math.floor(196 * e))
                if off then bg = intCol(30, 30, 36, math.floor(150 * e))
                elseif on then bg = intCol(52, 116, 198, math.floor(232 * e)) end
                draw.RoundedBox(6, ix, iy, iw, ih, bg)

                local edge = intCol(62, 78, 102, math.floor(190 * e))
                if on then edge = intCol(126, 182, 255, math.floor(230 * e)) end
                surface.SetDrawColor(edge)
                surface.DrawOutlinedRect(ix, iy, iw, ih, on and 2 or 1)

                --[[ Цветная полоска слева отделяет опасное действие от
                     обычного, не мешая читать подпись. ]]
                local accent = intCol(90, 110, 140, a)
                if off then accent = intCol(96, 92, 96, a)
                elseif act.accent == "good" then accent = intCol(104, 214, 138, a)
                elseif act.accent == "warn" then accent = intCol(240, 170, 90, a) end
                draw.RoundedBox(2, ix + 6, iy + 9, 3, ih - 18, accent)

                -- Текст только светлый: тёмный на тёмном нечитаем.
                local tcol = intCol(232, 238, 246, a)
                if off then tcol = intCol(150, 146, 150, a)
                elseif on then tcol = intCol(255, 255, 255, a) end
                local hasWhy = off and act.why
                draw.SimpleText(act.name, "GRMInt_Hint", ix + 18,
                    hasWhy and (iy + ih * 0.36) or (iy + ih * 0.5), tcol,
                    TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                if hasWhy then
                    draw.SimpleText(act.why, "GRMInt_Small", ix + 18, iy + ih * 0.7,
                        intCol(198, 132, 132, a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end
            end
        end

        draw.SimpleText("отпустите ЛКМ — применить  ·  ПКМ — отмена", "GRMInt_Small",
            x + pw * 0.5, y + ph + 14, intCol(150, 166, 186, alpha),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    f.OnMousePressed = function(_, key)
        if key == MOUSE_RIGHT then I.ClosePanel() return end
        if key == MOUSE_LEFT then I.Apply() end
    end
end
I.OpenRadial = I.OpenPanel

function I.Apply()
    local act = P.sel and P.items[P.sel]
    local ent = P.ent
    I.ClosePanel()
    if not act or not IsValid(ent) then return end
    if act.enabled == false then
        surface.PlaySound("buttons/button10.wav")
        return
    end
    surface.PlaySound("common/wpn_select.wav")

    --[[ «Ключи» — штатный запрос модуля ключей ТС: он сам проверит
         владельца и сам соберёт список игроков. Своей копии правил не
         заводим, иначе разойдётся с оригиналом. ]]
    if act.id == "veh_keys" then
        net.Start("VK_RequestPlayerList")
            net.WriteEntity(ent)
        net.SendToServer()
        return
    end

    net.Start(NET_ACT)
        net.WriteEntity(ent)
        net.WriteString(act.id)
    net.SendToServer()
end

-----------------------------------------------------------------------
-- Подсказка при подходе: РЯДОМ с объектом, а не в центре экрана.
-----------------------------------------------------------------------
hook.Add("HUDPaint", "GRM_Interact_Hint", function()
    if P.open then return end
    if GetConVarNumber("grm_cl_interact") == 0 then return end
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end
    if ply:InVehicle() then return end

    local ent, kind = I.FindTarget(ply, I.HintRange)

    -- Плавное появление: моргающая подсказка раздражает сильнее, чем
    -- её отсутствие.
    local want = (ent ~= nil) and 1 or 0
    hover.alpha = math.Approach(hover.alpha, want, FrameTime() * 5)
    if ent then hover.ent, hover.kind = ent, kind end
    if hover.alpha <= 0.01 then return end

    local target = hover.ent
    if not IsValid(target) then return end

    --[[ Точку ставим НА ОБЪЕКТ: владелец просил подсказку «не на
         машине, а рядом». Берём центр видимой части объекта и
         проецируем на экран — так надпись привязана к двери или машине,
         а не висит посреди прицела. ]]
    local mins, maxs = target:GetRenderBounds()
    local world = target:LocalToWorld((mins + maxs) * 0.5)
    local scr = world:ToScreen()
    if not scr or scr.visible == false then return end

    local a = math.floor(hover.alpha * 255)
    -- Смещаем вбок от центра объекта, чтобы не перекрывать его.
    local x = math.floor(scr.x) + 26
    local y = math.floor(scr.y)

    local name = I.TargetName(target, hover.kind)
    local _, locked = I.TargetSub(target, hover.kind)

    -- Маленькая точка-якорь у самого объекта.
    surface.SetDrawColor(236, 242, 250, a)
    draw.NoTexture()
    local dot = {}
    for i = 0, 12 do
        local ang = math.rad(i / 12 * 360)
        dot[#dot + 1] = { x = scr.x + math.cos(ang) * 2.5, y = scr.y + math.sin(ang) * 2.5 }
    end
    surface.DrawPoly(dot)
    surface.DrawLine(scr.x + 4, scr.y, x - 6, y)

    --[[ Небольшая плашка: владелец просил «небольшая» и «адекватно».
         Ширину считаем по тексту, чтобы не было пустой простыни. ]]
    surface.SetFont("GRMInt_Hint")
    local tw = surface.GetTextSize(name)
    surface.SetFont("GRMInt_Small")
    local hw = surface.GetTextSize("ЛКМ — действия")
    local bw = math.max(tw, hw) + 22
    local bh = 46

    draw.RoundedBox(6, x, y - bh * 0.5, bw, bh, intCol(14, 18, 26, math.floor(0.9 * a)))
    surface.SetDrawColor(58, 74, 98, math.floor(0.8 * a))
    surface.DrawOutlinedRect(x, y - bh * 0.5, bw, bh, 1)
    -- Полоска состояния слева: заперто или нет, видно без чтения.
    draw.RoundedBox(2, x + 5, y - bh * 0.5 + 8, 3, bh - 16,
        locked and intCol(226, 96, 92, a) or intCol(104, 214, 138, a))

    draw.SimpleText(name, "GRMInt_Hint", x + 14, y - 9,
        intCol(236, 242, 250, a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    draw.SimpleText("ЛКМ — действия", "GRMInt_Small", x + 14, y + 10,
        intCol(150, 166, 186, a), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end)

-----------------------------------------------------------------------
-- ЛКМ: удержание открывает панель, отпускание применяет.
-----------------------------------------------------------------------
local holdStart, holdEnt, holdKind, armed = 0, nil, nil, false
local passAtk = 0        -- сколько тиков доиграть «съеденный» короткий клик
local wasAtk = false     -- держал ли игрок ЛКМ в прошлом тике
I.HoldTime = 0.22        -- сколько держать, чтобы вместо обычного клика пришло меню

--[[ ВСЯ ЛОГИКА КНОПКИ ЖИВЁТ В StartCommand.

     Урок 31.08: PlayerButtonDown вызывается ПОСЛЕ того, как команда
     сформирована и отправлена. Пока мы там поднимали флаг, первый тик
     с зажатой кнопкой уже уходил на сервер — и дверь открывалась
     раньше, чем появлялось меню. Смотреть кнопку надо там же, где
     формируется команда.

     ЛКМ вместо E (заказ владельца): E остаётся штатным «использовать»,
     а меню теперь на ЛКМ. Короткий клик по-прежнему проходит наружу —
     иначе сломались бы удары, стрельба и физган. ]]
local function atkDown(cmd)
    return cmd:KeyDown(IN_ATTACK)
end

--[[ Когда кнопку трогать НЕЛЬЗЯ. С оружием в руках ЛКМ — это выстрел,
     и перехватывать его у двери недопустимо: игрок целился, а получил
     меню. Поэтому меню работает только с пустыми руками или со
     связкой ключей. ]]
local function weaponAllows(ply)
    local wep = ply:GetActiveWeapon()
    if not IsValid(wep) then return true end
    local cls = wep:GetClass()
    return cls == "weapon_fists" or cls == "grm_keyring"
end

hook.Add("StartCommand", "GRM_Interact_Use", function(ply, cmd)
    if ply ~= LocalPlayer() then return end

    -- Доигрываем короткий клик, который сами же и придержали.
    if passAtk > 0 then
        passAtk = passAtk - 1
        cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_ATTACK))
        wasAtk = false
        return
    end

    if P.open then
        cmd:ClearMovement()
        cmd:RemoveKey(IN_ATTACK)
        cmd:RemoveKey(IN_ATTACK2)
        cmd:RemoveKey(IN_USE)
        cmd:SetViewAngles(ply:EyeAngles())
        cmd:SetMouseX(0)
        cmd:SetMouseY(0)
        wasAtk = atkDown(cmd)
        return
    end

    local down = atkDown(cmd)

    if down and not wasAtk then
        wasAtk = true
        armed = false
        if GetConVarNumber("grm_cl_interact") == 0 then return end
        if gui.IsGameUIVisible() or gui.IsConsoleVisible() then return end
        if ply.IsTyping and ply:IsTyping() then return end
        if not ply:Alive() or ply:InVehicle() then return end
        if not weaponAllows(ply) then return end

        local ent, kind = I.FindTarget(ply, I.Range)
        if not ent then return end

        holdStart, holdEnt, holdKind, armed = RealTime(), ent, kind, true
        -- Придерживаем ЭТОТ ЖЕ тик, до отправки на сервер.
        cmd:RemoveKey(IN_ATTACK)
        return
    end

    if down and armed then
        cmd:RemoveKey(IN_ATTACK)
        if RealTime() - holdStart >= I.HoldTime and IsValid(holdEnt) then
            armed = false
            I.OpenPanel(holdEnt, holdKind)
        end
        wasAtk = true
        return
    end

    if not down and wasAtk then
        wasAtk = false
        --[[ Отпустили раньше порога — обычный клик. Возвращаем его игре:
             несколько тиков, а не один, иначе сервер не засчитает. ]]
        if armed and (RealTime() - holdStart) < I.HoldTime then
            passAtk = 3
        end
        armed = false
        return
    end

    wasAtk = down
end)

--[[ Отпускание при ОТКРЫТОЙ панели применяет выбор. Здесь
     PlayerButtonUp уместен: панель уже на экране, гонки с потоком
     команд нет. ]]
hook.Add("PlayerButtonUp", "GRM_Interact_UseUp", function(ply, key)
    if ply ~= LocalPlayer() then return end
    if key ~= MOUSE_LEFT then return end
    if P.open then
        armed = false
        I.Apply()
    end
end)

print("[GRM Interact] client v" .. I.Version)
