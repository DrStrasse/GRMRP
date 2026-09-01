--[[--------------------------------------------------------------------
    GRM Entry v1.0.0 — единый конвейер входа в игру.

    ЖАЛОБА ВЛАДЕЛЬЦА (27.08):

        «Перезашёл — на пару секунд видно, что персонаж УЖЕ заспавнился,
         потом возникает окно загрузки, нажал "Начать играть", возникло
         меню, выбрал персонажа, заспавнился, и уже через наносекунду
         меню выбора точки входа. Нажми любую — ничего не происходит.
         Меню должно быть плавным, код выполняться шаг за шагом,
         порционно: нажал начать играть, выбрал перса, выбрал где зайти,
         и ТОЛЬКО ПОТОМ спавн персонажа.»

    ПОЧЕМУ ЭТО ЛОМАЛОСЬ. Вход был размазан по трём модулям, и каждый
    считал себя последним:

      • sh_grm_loading   — показывал экран через 0.5 с ПОСЛЕ входа в мир,
                           поэтому кадр мира успевал мелькнуть;
      • sh_grm_character — в ReleaseFromLimbo делал Spawn() и сразу
                           PlaceOnSpawnPoint(), то есть ставил игрока
                           в мир ЕЩЁ ДО того, как спросил, куда он хочет;
      • sh_grm_spawnpick — предлагал выбор точки, когда игрок уже стоял
                           на карте. И самое главное: его SetPos потом
                           перетирался хуками PlayerSpawn и кодом
                           первичной регистрации.

    ВОТ ПОЧЕМУ «НАЖМИ ЛЮБУЮ — НИЧЕГО НЕ ПРОИСХОДИТ»: выбор применялся,
    а следом чужой код возвращал игрока обратно на фракционную точку.

    ЧТО ТЕПЕРЬ. Одна машина состояний, один владелец процесса. Стадии
    строго по порядку, каждая начинается только после завершения
    предыдущей:

        limbo → loading → character → spawnpoint → world

      limbo      игрок за картой: без модели, без оружия, заморожен;
      loading    чёрный экран, полоса, кнопка «НАЧАТЬ ИГРАТЬ»;
      character  окно выбора персонажа;
      spawnpoint окно «ВЫБЕРИТЕ ТОЧКУ ВХОДА»;
      world      и только здесь — реальный спавн, модель, оружие, HUD.

    ПОРЦИОННОСТЬ. Переходы идут через очередь шагов (E.Step): каждый шаг
    выполняется отдельным тиком, а не всё в одном кадре. Так вход не
    даёт фриза на слабом клиенте и этапы не наезжают друг на друга.

    ЗАНАВЕС. Пока стадия меньше world, клиент рисует сплошной чёрный
    экран поверх всего и прячет HUD. Игрок физически не может увидеть
    мир до того, как выбрал, где появиться.
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Entry = GRM.Entry or {}
local E = GRM.Entry

E.Version = "1.0.0"

--- Стадии. Числами, чтобы сравнивать «дальше/раньше» и слать одним UInt.
E.Stages = {
    limbo      = 1,
    loading    = 2,
    character  = 3,
    spawnpoint = 4,
    world      = 5,
}

E.StageName = {
    [1] = "limbo", [2] = "loading", [3] = "character",
    [4] = "spawnpoint", [5] = "world",
}

--- NW-поле, по которому клиент понимает, что рисовать.
E.NW = "GRM_EntryStage"

--- Сколько ждём между порциями конвейера.
E.StepDelay = 0.08

--[[ Страховка: если игрок почему-то застрял на стадии дольше этого
     времени, конвейер доводит его до мира сам. Лучше пустить в игру
     не идеально, чем оставить в чёрном экране навсегда. ]]
E.StageTimeout = 60

function E.StageOf(ply)
    if not IsValid(ply) then return 0 end
    return ply:GetNWInt(E.NW, 0)
end

--- Игрок ещё не в мире: занавес, блокировка HUD, ввода и выдачи оружия.
function E.InProgress(ply)
    local s = E.StageOf(ply)
    return s > 0 and s < E.Stages.world
end

-----------------------------------------------------------------------
-- СЕРВЕР
-----------------------------------------------------------------------
if SERVER then

    --[[ ОЧЕРЕДЬ ПОРЦИЙ. Владелец просил «код должен выполняться
         постепенно, шаг за шагом, порционно». Вместо того чтобы делать
         всю работу перехода в одном кадре, складываем её в очередь и
         выполняем по одному шагу за тик. ]]
    E.Queue = E.Queue or {}

    function E.Step(ply, name, fn)
        if not IsValid(ply) then return end
        E.Queue[ply] = E.Queue[ply] or {}
        table.insert(E.Queue[ply], { name = name, fn = fn })
    end

    local function pump()
        for ply, list in pairs(E.Queue) do
            if not IsValid(ply) then
                E.Queue[ply] = nil
            elseif #list > 0 then
                local step = table.remove(list, 1)
                -- Один шаг за тик: ошибка в шаге не должна рвать конвейер.
                local ok, err = pcall(step.fn, ply)
                if not ok then
                    ErrorNoHalt("[GRM Entry] шаг '" .. tostring(step.name)
                        .. "' упал: " .. tostring(err) .. "\n")
                end
                if #list == 0 then E.Queue[ply] = nil end
            else
                E.Queue[ply] = nil
            end
        end
    end
    --[[ Конвейер входа — critical: игрок в это время смотрит в чёрный
         экран, и пропуск шага он видит немедленно как «завис вход».
         Планировщик такие задачи не откладывает даже при просадке.

         `when` — важная деталь: пока никто не входит, задача вообще
         ничего не стоит, проверяется только пустота таблицы. ]]
    if GRM.Sched then
        GRM.Sched.Every("entry.pump", E.StepDelay, pump, {
            prio = "critical",
            when = function() return next(E.Queue) ~= nil end,
        })
    else
        timer.Create("GRM_Entry_Pump", E.StepDelay, 0, pump)
    end

    --[[ Перевести игрока на стадию. Назад по конвейеру не ходим: только
         явный сброс (новый вход, смена персонажа) начинает всё заново. ]]
    function E.SetStage(ply, stage, force)
        if not IsValid(ply) then return false end
        stage = tonumber(stage) or 0
        local cur = E.StageOf(ply)
        if not force and stage <= cur then return false end
        ply:SetNWInt(E.NW, stage)
        ply.GRMEntryStageAt = CurTime()
        hook.Run("GRM_EntryStage", ply, stage, cur)
        return true
    end

    function E.Reset(ply)
        if not IsValid(ply) then return end
        E.Queue[ply] = nil
        ply.GRMEntryDone = nil
        E.SetStage(ply, E.Stages.limbo, true)
    end

    -----------------------------------------------------------------
    -- ПЕРЕХОДЫ
    -----------------------------------------------------------------

    --- Вход в игру: сразу в лимб, экран загрузки.
    function E.Begin(ply)
        if not IsValid(ply) then return end
        E.Reset(ply)
        E.Step(ply, "to_loading", function(p)
            E.SetStage(p, E.Stages.loading)
        end)
    end

    --- Игрок нажал «НАЧАТЬ ИГРАТЬ» → окно персонажа.
    function E.ToCharacter(ply)
        if not IsValid(ply) then return false end
        if E.StageOf(ply) >= E.Stages.character then return false end
        E.Step(ply, "to_character", function(p)
            E.SetStage(p, E.Stages.character)
        end)
        return true
    end

    --[[ Персонаж подтверждён. Здесь решается главное: показывать ли
         экран точек входа. Если вариантов больше одного — показываем,
         и игрок ОСТАЁТСЯ в лимбе. Мир он увидит только после выбора. ]]
    function E.ToSpawnPoint(ply)
        if not IsValid(ply) then return false end
        if E.StageOf(ply) >= E.Stages.spawnpoint then return false end

        E.Step(ply, "to_spawnpoint", function(p)
            E.SetStage(p, E.Stages.spawnpoint)
        end)

        E.Step(ply, "offer_points", function(p)
            local SP = GRM.SpawnPick
            -- Модуль точек не загружен или выбирать не из чего — сразу в мир.
            if not (SP and SP.Offer) then E.ToWorld(p) return end
            local shown = SP.Offer(p)
            if not shown then E.ToWorld(p) end
        end)
        return true
    end

    --[[ ФИНАЛ: игрок появляется в мире. Всё, что раньше делалось
         вразнобой — спавн, позиция, оружие — теперь строго по порядку
         и ровно один раз. ]]
    function E.ToWorld(ply, point)
        if not IsValid(ply) then return false end
        if ply.GRMEntryDone then return false end
        ply.GRMEntryDone = true

        --[[ Точку запоминаем ДО спавна: движок при Spawn() сам поставит
             игрока на info_player_start, и наши хуки могут перетереть
             выбор. Поэтому ставим позицию ПОСЛЕ спавна, из сохранённого. ]]
        ply.GRMEntryPoint = istable(point) and point or nil

        E.Step(ply, "release", function(p)
            local CH = GRM.Char
            if CH and CH.FinishEntry then CH.FinishEntry(p) end
        end)

        E.Step(ply, "place", function(p)
            local pt = p.GRMEntryPoint
            if istable(pt) and pt.pos then
                p:SetPos(pt.pos)
                if pt.ang then p:SetEyeAngles(Angle(0, pt.ang.y or 0, 0)) end
            end
        end)

        E.Step(ply, "loadout", function(p)
            -- Оружие выдаём в самом конце: до этого его просто некому носить.
            if _G.ApplyWeaponsToPlayer then _G.ApplyWeaponsToPlayer(p) end
        end)

        --[[ РАЗМОРОЗКА ОТДЕЛЬНЫМ ШАГОМ, И ОБЯЗАТЕЛЬНО ПОСЛЕДНИМ.

             В лимбе игрок заморожен, невидим и бесплотен. Снимать это
             «где-то по пути» нельзя: любой чужой хук на PlayerSpawn
             (модели фракций, арест, аугментации) мог заново заморозить
             или спрятать. Поэтому приводим игрока в рабочее состояние
             ровно перед выходом в мир и не полагаемся на то, что кто-то
             уже это сделал. ]]
        E.Step(ply, "unfreeze", function(p)
            p.GRMCharLimbo = nil
            p:Freeze(false)
            p:SetMoveType(MOVETYPE_WALK)
            p:SetNoDraw(false)
            p:DrawShadow(true)
            p:SetNotSolid(false)
            p:SetNoTarget(false)
            p:GodDisable()
        end)

        E.Step(ply, "to_world", function(p)
            p.GRMEntryPoint = nil
            E.SetStage(p, E.Stages.world)
            hook.Run("GRM_EntryFinished", p)
            --[[ Контрольная разморозка через тик: если чужой хук на
                 PlayerSpawn заморозил игрока после нас, он всё равно
                 сможет двигаться. Дешевле одной проверки, чем ловить
                 каждый источник заморозки по отдельности. ]]
            timer.Simple(0.1, function()
                if not IsValid(p) then return end
                if E.StageOf(p) ~= E.Stages.world then return end
                -- Арест и «тяжёлое ранение» замораживают законно.
                if p:GetNWBool("GRM_Arrested", false) then return end
                if p:GetNWBool("GRM_911_Downed", false) then return end
                if p.IsFlagSet and p:IsFlagSet(FL_FROZEN) then p:Freeze(false) end
            end)
        end)
        return true
    end

    -----------------------------------------------------------------
    -- СТРАХОВКА ОТ ЗАВИСАНИЯ
    -----------------------------------------------------------------
    --[[ Любой сбой в цепочке не должен оставлять игрока в чёрном экране.
         Раз в 5 секунд смотрим, не завис ли кто на стадии. ]]
    --[[ Сторож — low: он лишь страховка от зависания, и секунда
         задержки роли не играет. При просадке сервера его отложат
         первым, и это правильно. ]]
    local function watchdog()
        local list = (GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()
        for _, ply in ipairs(list) do
            if IsValid(ply) and E.InProgress(ply) then
                local at = tonumber(ply.GRMEntryStageAt) or 0
                if at > 0 and CurTime() - at > E.StageTimeout then
                    ErrorNoHalt("[GRM Entry] " .. ply:Nick() .. " завис на стадии "
                        .. tostring(E.StageName[E.StageOf(ply)]) .. ", пускаем в мир\n")
                    ply.GRMEntryStageAt = CurTime()
                    E.ToWorld(ply)
                end
            end
        end
    end


    if GRM.Sched then
        GRM.Sched.Every("entry.watchdog", 5, watchdog, { prio = "low" })
    else
        timer.Create("GRM_Entry_Watchdog", 5, 0, watchdog)
    end

    hook.Add("PlayerDisconnected", "GRM_Entry_Clear", function(ply)
        E.Queue[ply] = nil
    end)

    -----------------------------------------------------------------
    -- ЖЁСТКИЕ БЛОКИРОВКИ, ПОКА ИГРОК НЕ В МИРЕ
    -----------------------------------------------------------------
    --[[ Владелец просил: «убираем человека в начале, чтобы его не
         спавнило, не выдавало оружия, вообще ничего». Ниже — именно это,
         на уровне движка, а не надежда на то, что модули договорятся. ]]

    hook.Add("PlayerLoadout", "GRM_Entry_NoLoadout", function(ply)
        if not E.InProgress(ply) then return end
        ply:StripWeapons()
        if ply.RemoveAllAmmo then ply:RemoveAllAmmo() end
        return true    -- «экипировка выдана», движок ничего не добавляет
    end)

    hook.Add("PlayerSpawn", "GRM_Entry_KeepLimbo", function(ply)
        if not E.InProgress(ply) then return end
        --[[ КРИТИЧНО: финал входа сам вызывает Spawn() (шаг «release»), и
             стадия в этот момент ещё spawnpoint. Без этой проверки мы
             ловили собственный спавн и возвращали игрока в лимб — а лимб
             это Freeze(true). Дальше шаги ставили позицию и оружие, но
             заморозку снимать было уже некому.

             Жалоба владельца: «персонаж появился, всё выдало, но
             персонаж заморожен, не может сдвинуться». Как только начат
             выпуск в мир (GRMEntryDone), удерживать лимб нельзя. ]]
        if ply.GRMEntryDone then return end
        local CH = GRM.Char
        if CH and CH.EnforceLimbo then
            timer.Simple(0, function()
                if not IsValid(ply) or ply.GRMEntryDone then return end
                if E.InProgress(ply) then CH.EnforceLimbo(ply) end
            end)
        end
    end)

    hook.Add("PlayerShouldTakeDamage", "GRM_Entry_NoDamage", function(ply)
        if E.InProgress(ply) then return false end
    end)

    hook.Add("PlayerCanPickupWeapon", "GRM_Entry_NoPickup", function(ply)
        if E.InProgress(ply) then return false end
    end)

    hook.Add("CanPlayerSuicide", "GRM_Entry_NoSuicide", function(ply)
        if E.InProgress(ply) then return false end
    end)

    hook.Add("PlayerSay", "GRM_Entry_NoChat", function(ply)
        -- Писать в чат из чёрного экрана нельзя: игрока ещё нет в мире.
        if E.InProgress(ply) then return "" end
    end)

    --- Диагностика: grm_entry
    concommand.Add("grm_entry", function(ply)
        local function out(t)
            if IsValid(ply) then ply:PrintMessage(HUD_PRINTTALK, t) else print(t) end
        end
        local list = (GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()
        out("[Вход] стадии игроков:")
        for _, p in ipairs(list) do
            local s = E.StageOf(p)
            out(("  %s — %s%s"):format(p:Nick(), tostring(E.StageName[s] or s),
                E.Queue[p] and (" (в очереди: " .. #E.Queue[p] .. ")") or ""))
        end
    end)

    if GRM.Modules and GRM.Modules.Register then
        GRM.Modules.Register("entry", {
            label = "Конвейер входа",
            version = E.Version,
            Status = function()
                local n = 0
                for _, p in ipairs(player.GetAll()) do
                    if E.InProgress(p) then n = n + 1 end
                end
                return "входят сейчас: " .. n
            end,
        })
    end
end

-----------------------------------------------------------------------
-- КЛИЕНТ: ЗАНАВЕС
-----------------------------------------------------------------------
if CLIENT then
    --[[ Пока стадия меньше world, поверх всего лежит сплошной чёрный
         экран. Это и есть ответ на «до надписи пару секунд успеваешь
         увидеть, что персонаж заспавнился»: увидеть больше нечего. ]]
    local function inProgress()
        local lp = LocalPlayer()
        if not IsValid(lp) then return false end
        return E.InProgress(lp)
    end
    E.ClientInProgress = inProgress

    --[[ Рисуем на HUDPaintBackground: это САМЫЙ нижний слой HUD, но он
         поверх мира. Окна VGUI (загрузка, персонаж, точки входа) выше
         занавеса, поэтому остаются видимыми. ]]
    hook.Add("HUDPaintBackground", "GRM_Entry_Curtain", function()
        if not inProgress() then return end
        surface.SetDrawColor(0, 0, 0, 255)
        surface.DrawRect(0, 0, ScrW(), ScrH())
    end)

    --[[ Клиентское событие смены стадии. NW-поля не дают хука, поэтому
         опрашиваем его редко (4 раза в секунду) и сообщаем остальным
         модулям только по факту изменения. Дешевле, чем гонять сеть. ]]
    E._lastStage = 0
    local function stageWatch()
        local lp = LocalPlayer()
        if not IsValid(lp) then return end
        local s = E.StageOf(lp)
        if s ~= E._lastStage then
            local prev = E._lastStage
            E._lastStage = s
            hook.Run("GRM_EntryStageClient", s, prev)
        end
    end


    -- HUD и прицел не показываем: мира ещё нет.
    --[[ Слежение за стадией — critical на клиенте: от него зависит,
         поднимется ли занавес. Но пока игрок в мире, задача бесплатна. ]]
    if GRM.Sched then
        GRM.Sched.Every("entry.stagewatch", 0.25, stageWatch, { prio = "critical" })
    else
        timer.Create("GRM_Entry_StageWatch", 0.25, 0, stageWatch)
    end

    hook.Add("HUDShouldDraw", "GRM_Entry_HideHUD", function()
        if inProgress() then return false end
    end)

    -- Мир не рисуем вовсе: экономим кадр и гарантируем чёрный экран.
    hook.Add("RenderScene", "GRM_Entry_NoScene", function()
        if inProgress() then return true end
    end)

    hook.Add("CalcView", "GRM_Entry_LockView", function(ply, pos, ang, fov)
        if not inProgress() then return end
        -- Камера замерла: никаких рывков и «полёта» до появления в мире.
        return { origin = pos, angles = ang, fov = fov, drawviewer = false }
    end)

    hook.Add("PreDrawHalos", "GRM_Entry_NoHalos", function()
        if inProgress() then return true end
    end)

    hook.Add("ShouldDrawLocalPlayer", "GRM_Entry_NoSelf", function()
        if inProgress() then return false end
    end)
end
