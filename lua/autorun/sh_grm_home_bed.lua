--[[--------------------------------------------------------------------
    GRM Home Bed v1.0.0 — домашняя кровать.

    ЗАКАЗ ВЛАДЕЛЬЦА (28.08): «для жилья нужна энтити домашней кровати,
    которая будет точкой сохранения/входа/выхода —
    models/props/de_inferno/bed.mdl».

    ТРИ ФУНКЦИИ, КАК И ПРОСИЛИ.

      ВХОД. Появляясь дома, игрок встаёт у своей кровати. Раньше точку
      искала эвристика «пол у двери со стороны комнаты»: в сложной
      планировке она промахивалась, и приходилось задавать место
      админской командой grm_housing_setspawn. Кровать — явная и
      понятная игроку метка, поэтому она приоритетнее эвристики.

      ВЫХОД. Лёг спать — вышел из игры лёжа. Вернулся — там же.

      СОХРАНЕНИЕ. Место запоминается СРАЗУ при укладывании, а не ждёт
      автоснимка позиции (он раз в 30 секунд). Лёг и выключил игру —
      точка уже на диске.

    ЧЕГО МОДУЛЬ НЕ ДЕЛАЕТ. Он не заводит своего владельца и своих прав:
    кровать принадлежит объекту недвижимости, в чьей зоне стоит, а кто
    имеет доступ — решает GRM.Housing.CanEnter. Дублировать правила в
    двух местах — верный способ получить дыру.
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.HomeBed = GRM.HomeBed or {}
local B = GRM.HomeBed

B.Version = "1.0.0"

--- Насколько приподнять лежащего над кроватью.
B.LieHeight = 18

--- В каком радиусе от кровати игрок появляется, вставая с неё.
B.WakeOffset = 34

-----------------------------------------------------------------------
-- СЕРВЕР
-----------------------------------------------------------------------
if SERVER then

    -- Ключ персонажа — канон ядра (§5.2.6): одна реализация на проект.
    local charKey = GRM.CharKey

    local function tell(ply, msg, good)
        if GRM.Notify then
            GRM.Notify(ply, msg, good and 120 or 255, good and 220 or 150, good and 150 or 110)
        elseif IsValid(ply) then
            ply:PrintMessage(HUD_PRINTTALK, "[Кровать] " .. msg)
        end
    end

    -----------------------------------------------------------------
    -- ПРИВЯЗКА К ЖИЛЬЮ
    -----------------------------------------------------------------
    --[[ Кровать принадлежит квартире, в чьей зоне стоит. Тот же принцип,
         что у домашнего шкафа: продали жильё — кровать перешла новому
         хозяину сама, без отдельной перепривязки. ]]
    function B.PropertyOf(ent)
        if not IsValid(ent) then return nil end
        local HS = GRM.Housing
        if not (HS and HS.HousingAt) then return nil end
        return HS.HousingAt(ent:GetPos())
    end

    --- Кровать этого объекта недвижимости (первая найденная).
    function B.BedOf(rec)
        if not istable(rec) then return nil end
        local list = (GRM.Perf and GRM.Perf.Entities)
            and GRM.Perf.Entities("grm_home_bed") or ents.FindByClass("grm_home_bed")
        for _, ent in ipairs(list or {}) do
            if IsValid(ent) then
                local own = B.PropertyOf(ent)
                if istable(own) and tostring(own.id) == tostring(rec.id) then return ent end
            end
        end
        return nil
    end

    --[[ Точка входа от кровати: рядом с ней, а НЕ в ней. Ставить игрока
         внутрь модели нельзя — застрянет. Берём место сбоку и разворачиваем
         лицом к кровати. ]]
    function B.SpawnPointFor(rec)
        local bed = B.BedOf(rec)
        if not IsValid(bed) then return nil end
        local pos = bed:GetPos() + bed:GetRight() * B.WakeOffset + Vector(0, 0, 6)

        --[[ Сбоку может быть стена: проверяем, помещается ли игрок, и
             при неудаче пробуем другую сторону, потом изножье. ]]
        local HS = GRM.Housing
        local tries = {
            pos,
            bed:GetPos() - bed:GetRight() * B.WakeOffset + Vector(0, 0, 6),
            bed:GetPos() - bed:GetForward() * B.WakeOffset + Vector(0, 0, 6),
        }
        for _, p in ipairs(tries) do
            if not (HS and HS.PointFits) or HS.PointFits(p) then
                local look = (bed:GetPos() - p)
                look.z = 0
                local yaw = look:Length() > 1 and look:Angle().y or bed:GetAngles().y
                return p, Angle(0, yaw, 0)
            end
        end
        -- Всё занято — ставим прямо над кроватью, это лучше, чем никуда.
        return bed:GetPos() + Vector(0, 0, B.LieHeight), Angle(0, bed:GetAngles().y, 0)
    end

    -----------------------------------------------------------------
    -- СОН
    -----------------------------------------------------------------
    --[[ Уложить игрока. Замораживаем ВВОД, а не ply:Freeze(): последний
         запирает игрока средствами движка, и любой чужой код, снявший
         его (админ-действия, респавн, транспорт), рассинхронил бы
         состояние навсегда. Та же причина, по которой так сделана
         заморозка поз в социальных анимациях. ]]
    function B.LieDown(ply, bed)
        if not (IsValid(ply) and IsValid(bed)) then return false end
        if IsValid(bed:GetSleeper()) then
            tell(ply, "Кровать занята.", false)
            return false
        end
        if ply:InVehicle() then return false end
        if ply:GetNWBool("GRM_Arrested", false) then
            tell(ply, "Под арестом не поспишь.", false)
            return false
        end

        local rec = B.PropertyOf(bed)
        if not istable(rec) then
            tell(ply, "Кровать не относится ни к одному жилью.", false)
            return false
        end

        --[[ Права спрашиваем у модуля жилья: свой список ключей завёл бы
             вторую точку правды. Опечатка, ордер и просроченная аренда
             при этом работают сами собой. ]]
        local HS = GRM.Housing
        if HS and HS.CanEnter then
            local allowed, _, why = HS.CanEnter(ply, rec)
            if not allowed then
                tell(ply, tostring(why or "Это не ваше жильё."), false)
                return false
            end
        end

        bed:SetSleeper(ply)
        ply.GRMBedEnt = bed
        ply:SetPos(bed:GetPos() + Vector(0, 0, B.LieHeight))
        ply:SetMoveType(MOVETYPE_NONE)

        --[[ ТОЧКА СОХРАНЕНИЯ. Записываем СРАЗУ, а не ждём автоснимка:
             человек лёг и в ту же секунду может закрыть игру. ]]
        local SP = GRM.SpawnPick
        if SP and SP.Remember then SP.Remember(ply, true) end

        hook.Run("GRM_HomeBedSleep", ply, bed, rec)
        tell(ply, "Вы легли. Нажмите E, чтобы встать.", true)
        return true
    end

    --- Поднять игрока. Безопасно звать повторно и для того, кто не спит.
    function B.GetUp(ply)
        if not IsValid(ply) then return false end
        local bed = ply.GRMBedEnt
        ply.GRMBedEnt = nil
        if IsValid(bed) and bed:GetSleeper() == ply then bed:SetSleeper(NULL) end

        ply:SetMoveType(MOVETYPE_WALK)
        if IsValid(bed) then
            local pos = bed:GetPos() + bed:GetRight() * B.WakeOffset + Vector(0, 0, 8)
            local HS = GRM.Housing
            if not (HS and HS.PointFits) or HS.PointFits(pos) then ply:SetPos(pos) end
        end
        hook.Run("GRM_HomeBedWake", ply, bed)
        return true
    end

    function B.IsSleeping(ply)
        return IsValid(ply) and IsValid(ply.GRMBedEnt)
    end

    --[[ Пока игрок лежит, он не ходит. StartCommand, а не Freeze — см.
         комментарий к LieDown. Камеру НЕ трогаем: осмотреться лёжа можно. ]]
    hook.Add("StartCommand", "GRM_HomeBed_Hold", function(ply, cmd)
        if not B.IsSleeping(ply) then return end
        cmd:ClearMovement()
        cmd:RemoveKey(IN_JUMP)
        cmd:RemoveKey(IN_ATTACK)
        cmd:RemoveKey(IN_ATTACK2)
    end)

    -- Смерть, арест и респавн поднимают: лежать «мёртвым» нельзя.
    hook.Add("PlayerDeath", "GRM_HomeBed_Death", function(ply) B.GetUp(ply) end)
    hook.Add("PlayerSpawn", "GRM_HomeBed_Spawn", function(ply) B.GetUp(ply) end)

    --[[ Игрок вышел лёжа — запоминаем кровать как место выхода. Именно
         это и просил владелец: «точка выхода». ]]
    hook.Add("PlayerDisconnected", "GRM_HomeBed_Disc", function(ply)
        if not B.IsSleeping(ply) then return end
        local SP = GRM.SpawnPick
        if SP and SP.Remember then SP.Remember(ply, true) end
        B.GetUp(ply)
    end)

    --[[ Кровать перестала принадлежать жилью (продали, снесли зону) —
         обновляем подпись у всех кроватей этого объекта. ]]
    hook.Add("GRM_PropertyOwnerChanged", "GRM_HomeBed_Relink", function()
        local list = (GRM.Perf and GRM.Perf.Entities)
            and GRM.Perf.Entities("grm_home_bed") or ents.FindByClass("grm_home_bed")
        for _, ent in ipairs(list or {}) do
            if IsValid(ent) and ent.UpdateLink then ent:UpdateLink() end
        end
    end)

    --- Диагностика: grm_home_bed
    concommand.Add("grm_home_bed", function(ply)
        if not IsValid(ply) then return end
        local function say(t) ply:PrintMessage(HUD_PRINTTALK, t) end
        local HS = GRM.Housing
        local rec = HS and HS.HomeOf and HS.HomeOf(ply)
        if not rec then say("[Кровать] У вас нет жилья.") return end

        local bed = B.BedOf(rec)
        say("[Кровать] жильё: " .. tostring(rec.name or rec.id))
        if IsValid(bed) then
            local pos = B.SpawnPointFor(rec)
            say(("  кровать найдена · точка входа: %s"):format(
                pos and ("%.0f %.0f %.0f"):format(pos.x, pos.y, pos.z) or "не найдена"))
        else
            say("  кровати нет — точка входа ищется от двери")
        end
    end)

    if GRM.Modules and GRM.Modules.Register then
        GRM.Modules.Register("home_bed", {
            label = "Домашняя кровать",
            version = B.Version,
            Depends = { "housing" },
        })
    end
end
