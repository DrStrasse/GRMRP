-- Boot-шим: старт подсистемы идёт через планировщик GRM.Boot (приоритеты и
-- бюджет на тик). Если планировщик почему-то не загружен, работаем по-старому.
local function grmBootStart(id, tier, fn)
    if GRM and GRM.Boot and GRM.Boot.OnMapStart then return GRM.Boot.OnMapStart(id, tier, fn) end
    return hook.Add("InitPostEntity", id, fn)
end

--[[--------------------------------------------------------------------
    GRM RadioNet v1.0.0 (Код 85) — Радиосеть: стойки, антенны,
    передатчики, мегафон, маршрутизация голоса с «радио-искажением».

    ЗАЧЕМ. До этого модуля радиосвязь/эфир/оповещение работали «по
    волшебству»: микрофон без единого провода вещал на весь город,
    рация била сквозь карту, громкоговорители жили сами по себе.
    Теперь вещанию нужна ИНФРАСТРУКТУРА:

      СЕРВЕРНАЯ СТОЙКА (grm_server_rack, E = питание вкл/выкл)
        — ядро сети. Сама по себе слабый репитер (RN.RackRange).
      АНТЕННА (grm_antenna)
        — работает, если в радиусе RN.LinkDist от АКТИВНОЙ стойки.
          Каждая связанная антенна даёт круг покрытия RN.AntennaRange —
          тем самым УСИЛИВАЕТ частоту/дальность сигнала сети.
      РАДИОПЕРЕДАТЧИК (grm_radio_station)
        — аппаратура передачи: микрофон подключается к ней, она —
          к активной стойке. Цепочка «микрофон → передатчик → стойка →
          антенны» выводит голос/текст в город.

    ЧТО ЗАВЕДЕНО НА СЕТЬ:
      1) Эфир микрофона (Код 75): до приёмников доходит, только если
         микрофон в сети И приёмник в покрытии антенн. Качество сигнала
         q(позиция приёмника) задаёт ВЫПАДЕНИЯ голоса (эмуляция
         радио-искажения: связь на краю покрытия хрипит и рвётся).
      2) ГРОМКАЯ СВЯЗЬ (новый режим микрофона, доступ = /alert_allow):
         голос ведущего звучит УСИЛЕННО (не объёмно, «из рупора») для
         всех, кто рядом с громкоговорителями, подключёнными к сети;
         громкоговорители щёлкают реле, голос идёт с треском/выпадениями
         — чистая Lua не меняет голосовой поток, эффект собран честными
         средствами: маршрутизация PlayerCanHearPlayersVoice + звуки.
      3) Ручная рация (подсистема телефонии): действует, если ОБА
         абонента в покрытии сети; без сети — только прямая дальность
         RN.DirectRadio (поймал собеседника в упор — договорился).
      4) Мегафон (weapon_grm_megaphone): голос владельца слышно на
         RN.MegaRange с эффектом кабельного рупора (треск, без 3D-
         затухания).
      5) /alert (текст, Код 75): теперь звучит только из громкого-
         ворителей, реально подключённых к сети.

    ТЕХНИЧЕСКИ. VoiceRoute(listener, speaker) — единая точка решений
    (возвращает canHear,is3D или nil = «нет мнения»). Телефонный модуль
    (sv_grm_phone) вызывает её ПЕРВОЙ в своём хуке — иначе хуки
    PlayerCanHearPlayersVoice били бы друг друга в случайном порядке
    pairs() (находка 100). Легаси-хук ш_grм_broadcast самоотключается,
    пока RadioNet в сборке.

    КОД 87 (v1.1.0) — NetSys: ИДЕНТИФИКАЦИЯ И ТОЧЕЧНАЯ МАРШРУТИЗАЦИЯ.
    Каждая железка сети получает позывной (RAX/ANT/RST/MIC/SPK/RAD/CON-001…)
    и попадает в реестр (grm_rnsys/<map>.json, переживает рестарт —
    «воскрешение» записей по позиции). Через ПУЛЬТ РАДИОСЕТИ
    (grm_net_console — компьютер, работает у АКТИВНОЙ стойки; суперадмин):
      • список устройств с состоянием/позицией — вкл/выкл ВЫВОД любой
        железки точечно (антенна гаснет — её круг покрытия схлопывается,
        громкоговоритель замолкает, приёмник глохнет, стойка вынимается
        из ядра);
      • ГРУППЫ устройств (напр. «Север»): оповещение /alert с пульта
        идёт на конкретную группу громкоговорителей ИЛИ на весь город;
      • цель ГРОМКОЙ СВЯЗИ микрофона: его голос звучит только из
        громкоговорителей выбранной группы;
      • ПЕЛЕНГ: дистанция/азимут/качество сигнала от пульта до каждого
        устройства; ЖУРНАЛ событий (кто/что/позиция/качество; передачи
        эфира, громкой связи, мегафона, оповещения, переключения) —
        /rn_log печатает последние 12.

    Спавн (суперадмин): /rack_add /antenna_add /rstation_add /console_add
    (+_remove), диагностика: /rn_status. Автоперсистентность:
    grm_rnents/<map>.json (аналог Кода 75, антидубль при рестарте).

    КОД 98 (v1.3.0) — КОМАНДЫ РАЦИИ /freq /r (находка 115: их
    ОБРАБОТЧИКА НЕ БЫЛО ВООБЩЕ). C-меню (sh_grm_ctx, кнопка «Рация»)
    честно слало «say /freq 145.5» и «say /freqleave» в чат — команды
    улетали в пустоту: ни один модуль сборки их не парсил (DarkRP-шного
    радио в сборке тоже нет). Теперь частоты — полноценный текстовый
    эфир радиосети, на той же логике покрытия, что голосовая рация:

      /freq 145.5   — настроить рацию на частоту (1–999.9 шаг 0.1);
                      запоминается за игроком (sid64) до /freqleave.
      /freq         — напомнить текущую частоту (ещё: !freq).
      /freqleave    — отключиться (ещё: /freq off, /freq 0, !-варианты).
      /r <текст>    — сказать в эфир: слышат все, кто на ТОЙ ЖЕ частоте
                      И в досягаемости (правило ручной рации
                      RadioPairOK: оба в сети — хоть через карту; вне
                      сети — только прямая дальность RN.DirectRadio).
                      На прямой дальности текст идёт С ПОМЕХАМИ: чем
                      дальше, тем больше символов съедает шипение («*»).
                      Антифлуд RN.FreqSayDelay, длина RN.FreqMaxLen,
                      передачи журналируются (/rn_log, вид freq_say).

    КОД 99 (v1.4.0) — ЧАСТОТЫ ТОЛЬКО С ПЕРЕНОСНЫМ МОДУЛЯТОРОМ (находка
    116). По заказу: пока у игрока нет радио-железки на руках, /freq и
    /r — бесполезные команды в никуда. Теперь в /phoneshop продаётся
    предмет «Модулятор рации (переносной)» (модель reciever01b, кладётся
    в инвентарь, выбрасывается на землю моделью и подбирается). Доступ к
    частотам = предмет В ИНВЕНТАРЕ + АКТИВИРОВАН (кнопка «Использовать» —
    переключатель ВКЛ/ВЫКЛ; состояние хранится в данных самого предмета,
    поэтому переживает рестарт, дроп и подбор чужими руками — включённая
    рация продаётся/теряется включённой). Гейт стоит на /freq (настройка)
    и /r (передача). Покупка помнится инвентарём (н114), активация —
    slot.data (Код 99 инвентаря v1.2.0: возврат data при подборе).

    КОД 109 (v1.4.2, находка 126 — заказ «нормальный модуль на рации»):
    корень «В инвентаре жму Использовать — ничего» был ВНЕ RadioNet —
    zz_grm_food_inventory_patch.lua ЗАМЕНЯЛ net-ресивер grm_inv_use
    своей неполной копией без radio_toggle (и кошелька/телефона/
    медкарты): клик умирал беззвучно, модулятор никогда не включался,
    /freq и /r всегда отвечали «нет активного модулятора». Инвентарь
    v1.5.0: useFunc-диспетчер на реестре RegisterUseHandler, замена
    ресивера упразднена — модулятор включается, data.on живёт в честном
    сейве инвентаря (дебаунс 2с + ShutDown) и переживает рестарт.
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.RadioNet = GRM.RadioNet or {}
local RN = GRM.RadioNet
local freqIdentity

RN.Version    = "1.4.2"  -- Код 109: useFunc-диспетчер инвентаря — реестр (находка 126):
                         -- патч еды больше НЕ заменяет ресивер, «Использовать»
                         -- модулятора снова включает/выключает рацию; /freq /r живые.

-- настройки сети (юниты = юниты Source; ~40 юн = 1 м)
RN.LinkDist     = 700    -- радиус связывания оборудования со стойкой
RN.AntennaRange = 3200   -- круг покрытия одной связанной антенны
RN.RackRange    = 1200   -- стойка сама = слабый репитер
RN.DirectRadio  = 1500   -- прямая дальность рации вне сети
RN.CoverMinQ    = 0.15   -- мин. качество покрытия для работы
RN.SpeakerRadius = 700   -- радиус слышимости громкоговорителя (совпадает с Кодом 75)
RN.MegaRange    = 1600   -- дальность мегафона
RN.PAQuality    = 0.85   -- «металлическая» громкая связь: базовое качество
RN.MegaQuality  = 0.92   -- качество мегафона
RN.LogCap       = 150    -- глубина журнала событий радиосети

local NET_FX   = "GRM_RN_FX"
local NET_OPEN = "GRM_RN_NetOpen"  -- пульт: сервер → клиент (снапшот)
local NET_OP   = "GRM_RN_NetOp"    -- пульт: клиент → сервер (операции)

-- Реестр устройств (Код 87): каждая сетевая железка получает личный
-- позывной (RAX-001 стойки, ANT-001 антенны, RST-001 передатчики,
-- MIC-001 микрофоны, SPK-001 громкоговорители, RAD-001 приёмники,
-- CON-001 пульты). Идентификация, точечное включение/отключение,
-- группы (вывод на «свой сектор» или на весь город), пеленг (дистанция/
-- азимут/качество от пульта) и журнал событий — через пульт
-- grm_net_console (E по компьютеру рядом с АКТИВНОЙ стойкой).
RN.Kinds = {
    grm_server_rack    = { k = "rack",    p = "RAX", label = "Стойка" },
    grm_antenna        = { k = "antenna", p = "ANT", label = "Антенна" },
    grm_radio_station  = { k = "station", p = "RST", label = "Передатчик" },
    grm_broadcast_mic  = { k = "mic",     p = "MIC", label = "Микрофон" },
    grm_loudspeaker    = { k = "speaker", p = "SPK", label = "Громкоговоритель" },
    grm_radio          = { k = "radio",   p = "RAD", label = "Радиоприёмник" },
    grm_net_console    = { k = "console", p = "CON", label = "Пульт" },
}

-- Код 99: переносной модулятор рации — предмет инвентаря, ключ к частотам.
RN.UnitItem  = "radio_modulator"
RN.UnitModel = "models/props_lab/reciever01b.mdl"       -- по заказу
RN.UnitModelFB = "models/props_lab/reciever01a.mdl"     -- фолбэк (н85)
RN.UnitPrice = 1500                                     -- цена в /phoneshop

-- Регистрация предмета в обоих мирах (клиент видит имя/иконку, сервер —
-- логику). Модель — через IsValidModel с фолбэком (находка 85: нельзя
-- уронить дроп с отсутствующей моделью).
-- Код 106 (находка 123): гард теперь ВНУТРИ регистратора — раньше он
-- стоял снаружи и пропускал ВМЕСТЕ с ретраем: если на конкретной
-- загрузке инвентарь отставал, модулятор терялся насовсем (мёртвая
-- кнопка «Использовать» у владельца). Дубль-страховка: статический деф
-- того же предмета лежит в sh_grm_inventory (v1.4.0) — запись ниже
-- просто перезапишет его тем же содержимым (с проверенной моделью).
local function regRadioUnit()
    if not (GRM.Inventory and GRM.Inventory.RegisterItem) then return end
    local mdl = RN.UnitModel
    if util.IsValidModel and not util.IsValidModel(mdl) then mdl = RN.UnitModelFB end
    GRM.Inventory.RegisterItem(RN.UnitItem, {
        type = "item",
        name = "Модулятор рации (переносной)",
        desc = "Переносная радиостанция. «Использовать» — вкл/выкл. Когда включён: /freq 145.5 — частота, /r текст — эфир. Сеть — любая дистанция, вне сети до 37 м напрямую.",
        icon = "icon16/transmit.png",
        maxStack = 1,
        weight = 0.6,
        model = mdl,
        useFunc = "radio_toggle",
    })
end
regRadioUnit()
timer.Simple(2, regRadioUnit) -- инвентарь мог подгрузиться позже (ретрай живёт ВСЕГДА)

-- ============================================================
-- СЕРВЕР
-- ============================================================
if SERVER then
    util.AddNetworkString(NET_FX)
    util.AddNetworkString(NET_OPEN)
    util.AddNetworkString(NET_OP)

    -- форвард-декларации (урок 97-хотфикса: замыкания выше объявлений)
    local recompute
    local paVoiceHear
    local radioVoiceHear
    local notifyFx
    local deviceOnForEnt
    local deviceInGroupForEnt
    local logEvent
    local consoleOpen

    local function rpName(ply)
        if not IsValid(ply) then return "?" end
        local name = ply:GetNWString("GRM_RPName", "")
        return name ~= "" and name or ply:Nick()
    end

    ----------------------------------------------------------------
    -- Пересчёт топологии сети (кэш для дешёвых запросов голоса)
    ----------------------------------------------------------------
    RN._racks = {}
    RN._activeRacks = {}
    RN._coverage = {}      -- массив {pos=Vector, r=число}
    RN._antsTotal = 0
    RN._antsLinked = 0

    local function nearActiveRack(pos, dist)
        local d2max = dist * dist
        for _, r in ipairs(RN._activeRacks) do
            if IsValid(r) and r:GetPos():DistToSqr(pos) <= d2max then return true end
        end
        return false
    end
    RN.NearActiveRack = nearActiveRack

    -- качество сигнала в точке: 1.0 внутри 55% радиуса ближайшего круга
    -- покрытия, далее плавный спад к краю до 0
    function RN.QualityAt(pos)
        local best = 0
        for _, c in ipairs(RN._coverage) do
            local d2 = pos:DistToSqr(c.pos)
            local r = c.r
            if d2 <= r * r then
                local d = math.sqrt(d2)
                local q = 1
                if d > r * 0.55 then
                    q = 1 - (d - r * 0.55) / (r * 0.45)
                end
                if q > best then best = q end
            end
        end
        return best
    end

    function RN.CoveredAt(pos)
        return RN.QualityAt(pos) >= RN.CoverMinQ
    end

    -- громкоговоритель в сети: рядом активная стойка ИЛИ точка в покрытии;
    -- Код 87: пульт может точечно снять устройство с эфира (rec.off)
    function RN.SpeakerActive(spk)
        if not IsValid(spk) then return false end
        if deviceOnForEnt and not deviceOnForEnt(spk) then return false end
        local pos = spk:GetPos()
        if nearActiveRack(pos, RN.LinkDist) then return true end
        return RN.CoveredAt(pos)
    end

    -- радиоприёмник ловит станцию только в покрытии антенн (+ тот же
    -- точечный запрет с пульта)
    function RN.ReceiverOK(radioEnt)
        if not IsValid(radioEnt) then return false end
        if deviceOnForEnt and not deviceOnForEnt(radioEnt) then return false end
        return RN.CoveredAt(radioEnt:GetPos())
    end

    -- состояние канала микрофона:
    --   2 = в сети (стойка напрямую ИЛИ через пристыкованный передатчик)
    --   1 = передатчик рядом, но сам вне сети (стойка погашена/далеко)
    --   0 = голый микрофон — эфир в город не выйдет
    function RN.MicLink(mic)
        if not IsValid(mic) then return 0 end
        local pos = mic:GetPos()
        if nearActiveRack(pos, RN.LinkDist) then return 2 end
        for _, st in ipairs(ents.FindByClass("grm_radio_station")) do
            if IsValid(st) and st:GetPos():DistToSqr(pos) <= RN.LinkDist * RN.LinkDist then
                if nearActiveRack(st:GetPos(), RN.LinkDist) then return 2 end
                return 1
            end
        end
        return 0
    end

    -- гейт ручной рации: оба в покрытии ИЛИ прямая близость
    function RN.RadioPairOK(speaker, listener)
        if not IsValid(speaker) or not IsValid(listener) then return false end
        local sp, lp = speaker:GetPos(), listener:GetPos()
        if RN.CoveredAt(sp) and RN.CoveredAt(lp) then return true end
        return sp:DistToSqr(lp) <= RN.DirectRadio * RN.DirectRadio
    end

    ----------------------------------------------------------------
    -- «Радио-искажение»: детерминированные выпадения пакетов.
    -- Одинаковый срез времени у сервера = устойчивое решение внутри
    -- среза; вероятность слышать == q.
    ----------------------------------------------------------------
    function RN.Drop(lkey, q)
        if q >= 0.985 then return false end
        if q <= 0 then return true end
        local slice = math.floor((CurTime() or 0) * 5)
        local h = (lkey * 2654435761 + slice * 40503) % 1000
        return h > (q * 1000)
    end

    ----------------------------------------------------------------
    -- ЕДИНАЯ МАРШРУТИЗАЦИЯ ГОЛОСА
    -- Возвращает canHear, is3D  — или nil («нет мнения», пусть решают
    -- локальный голос/телефония/поведение по умолчанию).
    ----------------------------------------------------------------
    local function receiveRadius()
        return (GRM.Broadcast and GRM.Broadcast.ReceiveRadius) or 500
    end

    -- слышимость эфира: слушатель стоит у настроенного приёмника,
    -- приёмник в покрытии; качество покрытия задаёт выпадения
    radioVoiceHear = function(listener, mic)
        local rr = receiveRadius()
        for _, r in ipairs(ents.FindByClass("grm_radio")) do
            if r:GetNWBool("GRM_BC_On", false) and r:GetNWInt("GRM_BC_Mic", 0) == mic:EntIndex() then
                if RN.ReceiverOK(r) and listener:GetPos():DistToSqr(r:GetPos()) <= rr * rr then
                    local q = RN.QualityAt(r:GetPos())
                    if RN.Drop(listener:EntIndex(), q) then return nil end
                    return true
                end
            end
        end
        return nil
    end

    -- громкая связь: слушатель рядом с СЕТЕВЫМ громкоговорителем —
    -- голос звучит усиленно (не 3D) и слегка «хрипит».
    -- Код 87: микрофону пультом назначается цель (группа) — тогда
    -- громкая связь звучит только из громкоговорителей этой группы.
    paVoiceHear = function(listener, mic)
        local target = (IsValid(mic) and mic:GetNWString("GRM_RN_Target", "")) or ""
        local rr = RN.SpeakerRadius
        for _, s in ipairs(ents.FindByClass("grm_loudspeaker")) do
            if RN.SpeakerActive(s)
                and (target == "" or (deviceInGroupForEnt and deviceInGroupForEnt(s, target)))
                and listener:GetPos():DistToSqr(s:GetPos()) <= rr * rr then
                if RN.Drop(listener:EntIndex() + 3, RN.PAQuality) then return nil end
                return true
            end
        end
        return nil
    end

    function RN.VoiceRoute(listener, speaker)
        if not IsValid(listener) or not IsValid(speaker) then return nil end
        if listener == speaker then return nil end
        -- Отбывающий административное наказание в радиоэфир не выходит:
        -- его голос не уходит дальше собственной зоны.
        if GRM.ServerBan and GRM.ServerBan.PlayerBanned and GRM.ServerBan.PlayerBanned(speaker) then
            return false
        end
        -- ближняя зона: физический голос важнее любой аппаратуры,
        -- отдаём решение локальному голосу/телефонии
        local lpos, spos = listener:GetPos(), speaker:GetPos()
        if lpos:DistToSqr(spos) <= 400 * 400 then return nil end
        local now = CurTime()

        -- (1) голос ведущего микрофона (эфир / громкая связь)
        local mic = speaker._grmBCMic
        if IsValid(mic) and mic.BCLive and mic.BCSpeaker == speaker then
            if mic:GetNWBool("GRM_BC_PA", false) then
                local r = paVoiceHear(listener, mic)
                if r ~= nil then
                    speaker._rnTxSeen = now speaker._rnFx = "pa"
                    return r, false
                end
                -- в громкой связи вне громкоговорителей — не звучит
                return false, false
            else
                if RN.MicLink(mic) >= 2 then
                    local r = radioVoiceHear(listener, mic)
                    if r ~= nil then
                        speaker._rnTxSeen = now speaker._rnFx = "radio"
                        return r, false
                    end
                    -- вещает по сети: вне приёмников радиослушателей нет
                    return false, false
                end
                -- микрофон вне сети: эфир не выходит, слышно лишь локально
                return nil
            end
        end

        -- (2) мегафон: усиленный голос с треском
        if speaker._rnMegaOn == true then
            if lpos:DistToSqr(spos) <= RN.MegaRange * RN.MegaRange then
                if RN.Drop(listener:EntIndex() + 7, RN.MegaQuality) then return nil end
                speaker._rnTxSeen = now speaker._rnFx = "mega"
                return true, false
            end
        end

        return nil
    end

    -- собственный хук (при живом телефонном модуле он вызывает
    -- VoiceRoute сам первым делом — наш хук тогда просто дублирует
    -- то же решение, конфликтов нет)
    hook.Add("PlayerCanHearPlayersVoice", "GRM_RadioNet_Voice", function(listener, speaker)
        local c, h = RN.VoiceRoute(listener, speaker)
        if c ~= nil then return c, h end
    end)

    ----------------------------------------------------------------
    -- FX-рассылка «передача идёт/закончена» (щелчки реле, треск)
    ----------------------------------------------------------------
    RN._fxState = {} -- ply → kind или nil
    notifyFx = function(ply, kind, on)
        net.Start(NET_FX)
            net.WriteUInt(ply:EntIndex(), 16)
            net.WriteString(kind or "")
            net.WriteBool(on and true or false)
        net.Broadcast()
    end

    -- релейные щелчки сетевых громкоговорителей (старт/стоп громкой связи)
    local function paRelayClicks(onT)
        local snd = onT and "buttons/button9.wav" or "buttons/button18.wav"
        for _, s in ipairs(ents.FindByClass("grm_loudspeaker")) do
            if RN.SpeakerActive(s) then s:EmitSound(snd, 62, 100) end
        end
    end

    RN._fxLastKind = {}
    timer.Create("GRM_RN_FxWatch", 0.35, 0, function()
        local now = CurTime()
        for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(ply) then
                local active = ply._rnTxSeen and (now - ply._rnTxSeen) < 0.6
                local kind = active and ply._rnFx or nil
                if RN._fxState[ply] ~= kind then
                    if kind then
                        notifyFx(ply, kind, true)
                        if kind == "pa" then paRelayClicks(true) end
                        local n = ply.GetNWString and ply:GetNWString("GRM_RPName", "") or ""
                        if n == "" then n = ply:Nick() end
                        if logEvent then
                            logEvent("tx_" .. tostring(kind), n, freqIdentity(ply), ply:GetPos(),
                                kind == "radio" and "эфир микрофона начат" or kind == "pa" and "ГРОМКАЯ СВЯЗЬ начата" or "мегафон включён")
                        end
                    else
                        notifyFx(ply, RN._fxLastKind[ply] or "radio", false)
                        if RN._fxLastKind[ply] == "pa" then paRelayClicks(false) end
                        if logEvent then
                            logEvent("tx_end", rpName(ply), freqIdentity(ply), ply:GetPos(),
                                "передача «" .. tostring(RN._fxLastKind[ply] or "radio") .. "» завершена")
                        end
                    end
                    RN._fxState[ply] = kind
                end
                if kind then RN._fxLastKind[ply] = kind end
            end
        end
    end)

    ----------------------------------------------------------------
    -- Автоперсистентность энтити сети (паттерн Кода 75)
    ----------------------------------------------------------------
    local PERSIST_CLASSES = { grm_server_rack = true, grm_antenna = true, grm_radio_station = true, grm_net_console = true }
    local function jsonT(txt)
        local ok, t = pcall(util.JSONToTable, txt, false, true)
        return (ok and istable(t)) and t or nil
    end
    local function entsFile()
        if not file.IsDir("grm_rnents", "DATA") then file.CreateDir("grm_rnents") end
        return "grm_rnents/" .. string.lower(game.GetMap() or "unknown") .. ".json"
    end
    RN.Persist = RN.Persist or {}
    local function loadPersist()
        local t = jsonT(file.Read(entsFile(), "DATA") or "")
        RN.Persist = istable(t) and t or {}
    end
    local function savePersist(reason)
        local ok, txt = pcall(util.TableToJSON, RN.Persist or {}, true)
        if ok and txt then
            file.Write(entsFile(), txt)
            local rb = file.Read(entsFile(), "DATA")
            print("[GRM RadioNet] SAVE ok (" .. tostring(reason or "?") .. "), записей: " .. tostring(table.Count(RN.Persist or {})) .. ", read-back: " .. tostring(rb ~= nil))
        end
    end
    loadPersist()

    local function persistKey(class, pos)
        return tostring(class) .. "|" .. string.format("%.0f_%.0f_%.0f", pos.x, pos.y, pos.z)
    end

    function RN.PersistAdd(ent)
        if not IsValid(ent) or RN._restoring then return end
        local class = ent:GetClass()
        if not PERSIST_CLASSES[class] then return end
        local pos, ang = ent:GetPos(), ent:GetAngles()
        RN.Persist[persistKey(class, pos)] = {
            class = class,
            pos = { x = pos.x, y = pos.y, z = pos.z },
            ang = { p = ang.p or 0, y = ang.y or 0, r = ang.r or 0 },
        }
        savePersist("persist add " .. class)
    end

    function RN.PersistRemove(ent)
        if not IsValid(ent) then return end
        local k = persistKey(ent:GetClass(), ent:GetPos())
        if RN.Persist[k] then RN.Persist[k] = nil savePersist("persist remove") end
    end

    -- Код 88.4: авто-свипер персистента — вышки и оборудование сейвятся
    -- ПЕРМАНЕНТНО независимо от способа постановки (чат-команда, Q-меню, дюп).
    -- Переехавшая энтити мигрирует по ключу, удалённая живьём — выпадает из
    -- реестра (иначе реестр воскрешал бы снятое админом после рестарта).
    -- Первый прогон через 15с — заведомо после воскрешения (InitPostEntity+4с).
    local function persistSweep()
        if RN._restoring then return end
        local seen = {}
        for class in pairs(PERSIST_CLASSES) do
            for _, e in ipairs(ents.FindByClass(class)) do
                if IsValid(e) then
                    local k = persistKey(class, e:GetPos())
                    seen[k] = true
                    if not RN.Persist[k] then
                        if e._grmRNKey and RN.Persist[e._grmRNKey] then RN.Persist[e._grmRNKey] = nil end
                        RN.PersistAdd(e)
                    end
                    e._grmRNKey = k
                end
            end
        end
        local lost = 0
        for k, rec in pairs(RN.Persist or {}) do
            if PERSIST_CLASSES[rec.class] and not seen[k] then
                RN.Persist[k] = nil
                lost = lost + 1
            end
        end
        if lost > 0 then savePersist("sweep removal " .. lost) end
    end
    timer.Create("GRM_RN_PersistSweep", 15, 0, persistSweep)
    RN._devSweep = persistSweep -- тест-экспорт (сим)

    function RN.RestoreMap()
        RN._restoring = true
        local restored = 0
        for k, rec in pairs(RN.Persist or {}) do
            if PERSIST_CLASSES[rec.class] and istable(rec.pos) then
                local pos = Vector(tonumber(rec.pos.x) or 0, tonumber(rec.pos.y) or 0, tonumber(rec.pos.z) or 0)
                local dup = false
                for _, e in ipairs(ents.FindByClass(rec.class)) do
                    if IsValid(e) and e:GetPos():DistToSqr(pos) < 64 then dup = true break end
                end
                if not dup then
                    local ent = ents.Create(rec.class)
                    if IsValid(ent) then
                        ent:SetPos(pos)
                        local a = istable(rec.ang) and rec.ang or {}
                        ent:SetAngles(Angle(tonumber(a.p) or 0, tonumber(a.y) or 0, tonumber(a.r) or 0))
                        ent:Spawn() ent:Activate()
                        if GRM.PropProtect and GRM.PropProtect.MarkServerEntity then GRM.PropProtect.MarkServerEntity(ent) end
                        local phys = ent:GetPhysicsObject()
                        if IsValid(phys) then phys:EnableMotion(false) end
                        if rec.class == "grm_server_rack" then ent:SetNWBool("GRM_RN_On", true) end
                        ent._grmRNKey = k -- Код 88.4: свипер узнаёт своих
                        restored = restored + 1
                    end
                end
            end
        end
        RN._restoring = false
        print("[GRM RadioNet] Персистент: записей " .. tostring(table.Count(RN.Persist or {})) .. ", восстановлено " .. tostring(restored))
    end

    grmBootStart("GRM_RN_Restore", "normal", function()
        timer.Simple(4, function() RN.RestoreMap() end)
    end)

    hook.Add("PostCleanupMap", "GRM_RN_Cleanup", function()
        timer.Simple(0.5, function() RN.RestoreMap() end)
    end)

    ----------------------------------------------------------------
    -- Код 87 — NetSys: реестр устройств (идентификация), группы,
    -- точечное включение/маршрутизация, пеленг и журнал событий.
    -- Хранение: grm_rnsys/<map>.json (jsonT с 3-м аргументом, н65).
    ----------------------------------------------------------------
    local function sysFile()
        if not file.IsDir("grm_rnsys", "DATA") then file.CreateDir("grm_rnsys") end
        return "grm_rnsys/" .. string.lower(game.GetMap() or "unknown") .. ".json"
    end
    RN.Sys = RN.Sys or {}
    local function loadSys()
        local t = jsonT(file.Read(sysFile(), "DATA") or "")
        RN.Sys.next    = (istable(t) and istable(t.next))    and t.next    or {}
        RN.Sys.devices = (istable(t) and istable(t.devices)) and t.devices or {}
        RN.Sys.log     = (istable(t) and istable(t.log))     and t.log     or {}
    end
    function RN.SysSave(reason)
        local ok, txt = pcall(util.TableToJSON, {
            next = RN.Sys.next or {}, devices = RN.Sys.devices or {}, log = RN.Sys.log or {},
        }, true)
        if ok and txt then
            file.Write(sysFile(), txt)
            local rb = file.Read(sysFile(), "DATA")
            print("[GRM RadioNet] SYS SAVE ok (" .. tostring(reason or "?") .. "), устройств: "
                .. tostring(table.Count(RN.Sys.devices or {})) .. ", журнал: "
                .. tostring(#(RN.Sys.log or {})) .. ", read-back: " .. tostring(rb ~= nil))
        end
    end
    loadSys()

    -- журнал событий с пеленгом (позиция + качество канала в точке)
    RN._logDirty = false
    logEvent = function(kind, who, sid64, pos, note)
        local q, px, py, pz = 0, 0, 0, 0
        if pos then
            px = math.floor((pos.x or 0) + 0.5) py = math.floor((pos.y or 0) + 0.5) pz = math.floor((pos.z or 0) + 0.5)
            q = math.floor(RN.QualityAt(pos) * 100 + 0.5)
        end
        local log = RN.Sys.log
        log[#log + 1] = { ts = os.time(), kind = tostring(kind or "?"), who = tostring(who or "?"),
            sid64 = tostring(sid64 or ""), x = px, y = py, z = pz, q = q, note = tostring(note or "") }
        while #log > RN.LogCap do table.remove(log, 1) end
        RN._logDirty = true -- сброс на диск таймером: события могут быть частыми
    end
    RN.LogEvent = logEvent
    timer.Create("GRM_RN_LogFlush", 2, 0, function()
        if RN._logDirty then RN._logDirty = false RN.SysSave("журнал событий") end
    end)
    function RN.LogTail(n)
        local out, log = {}, RN.Sys.log or {}
        local from = math.max(1, #log - (n or 12) + 1)
        for i = from, #log do out[#out + 1] = log[i] end
        return out
    end

    -- регистрация: позывной каждой железке; «воскрешение» записи после
    -- рестарта по ближайшей незанятой позиции того же вида (≤32 юн)
    RN._id2ent = {}
    local function registerDevices()
        local seen, id2ent = {}, {}
        for class, meta in pairs(RN.Kinds) do
            for _, e in ipairs(ents.FindByClass(class)) do
                if IsValid(e) then
                    local epos = e:GetPos()
                    local id = e:GetNWString("GRM_NetID", "")
                    if id ~= "" then
                        local rec = RN.Sys.devices[id]
                        if (not istable(rec)) or rec.kind ~= meta.k or seen[id] then id = "" end
                    end
                    if id == "" then
                        local bestD = 32 * 32 + 1
                        for did, rec in pairs(RN.Sys.devices) do
                            if rec.kind == meta.k and not seen[did] and istable(rec.pos) then
                                local dx = (rec.pos.x or 0) - epos.x
                                local dy = (rec.pos.y or 0) - epos.y
                                local dz = (rec.pos.z or 0) - epos.z
                                local d2 = dx * dx + dy * dy + dz * dz
                                if d2 < bestD then id = did bestD = d2 end
                            end
                        end
                        if not istable(RN.Sys.devices[id or ""]) then id = "" end
                    end
                    if id == "" then
                        local n = tonumber(RN.Sys.next[meta.p]) or 1
                        repeat
                            id = meta.p .. "-" .. string.format("%03d", n)
                            n = n + 1
                        until not RN.Sys.devices[id]
                        RN.Sys.next[meta.p] = n
                        RN.Sys.devices[id] = { id = id, kind = meta.k, pos = {}, off = false, groups = {}, born = os.time() }
                        RN.SysSave("реестр: новое устройство " .. id)
                    end
                    local rec = RN.Sys.devices[id]
                    seen[id] = true
                    rec.pos = { x = math.floor(epos.x + 0.5), y = math.floor(epos.y + 0.5), z = math.floor(epos.z + 0.5) }
                    rec.lastSeen = os.time()
                    rec.groups = istable(rec.groups) and rec.groups or {}
                    if e:GetNWString("GRM_NetID", "") ~= id then e:SetNWString("GRM_NetID", id) end
                    if meta.k == "mic" then
                        local tg = tostring(rec.paTarget or "")
                        if e:GetNWString("GRM_RN_Target", "") ~= tg then e:SetNWString("GRM_RN_Target", tg) end
                    end
                    id2ent[id] = e
                end
            end
        end
        RN._id2ent = id2ent
        return seen
    end
    RN._RegisterDevices = registerDevices -- экспорт для стенда

    -- пультный выключатель устройства (nil-устойчиво: до назначения id не душим)
    deviceOnForEnt = function(ent)
        if not IsValid(ent) then return false end
        local id = ent:GetNWString("GRM_NetID", "")
        if id == "" then return true end
        local rec = RN.Sys.devices[id]
        return not (istable(rec) and rec.off == true)
    end
    deviceInGroupForEnt = function(ent, group)
        if not IsValid(ent) then return false end
        local id = ent:GetNWString("GRM_NetID", "")
        local rec = id ~= "" and RN.Sys.devices[id] or nil
        return istable(rec) and istable(rec.groups) and rec.groups[group] == true
    end
    RN.DeviceOnForEnt = deviceOnForEnt
    RN.DeviceInGroupForEnt = deviceInGroupForEnt
    function RN.DeviceId(ent) return IsValid(ent) and ent:GetNWString("GRM_NetID", "") or "" end

    -- пульт радиосети ---------------------------------------------------
    local function consoleLinked(con)
        return IsValid(con) and nearActiveRack(con:GetPos(), RN.LinkDist)
    end
    local function bearingOf(from, to)
        local dx = (to.x or 0) - from.x
        local dy = (to.y or 0) - from.y
        local dz = (to.z or 0) - from.z
        local ang = math.deg(math.atan2(dy, dx))
        if ang < 0 then ang = ang + 360 end
        return math.floor(math.sqrt(dx * dx + dy * dy + dz * dz) + 0.5), math.floor(ang + 0.5)
    end
    local function deviceNetState(rec, e)
        if not IsValid(e) then return "призрак (запись без железа)" end
        local k = rec.kind
        if k == "rack" then return e:GetNWBool("GRM_RN_On", true) and "ядро ВКЛ" or "питание ВЫКЛ" end
        if k == "antenna" then return e:GetNWBool("GRM_RN_Linked", false) and "усиливает сеть" or "нет стойки рядом" end
        if k == "station" then return e:GetNWBool("GRM_RN_Online", false) and "в сети" or "вне сети" end
        if k == "mic" then
            local l = RN.MicLink(e)
            return l >= 2 and "в сети" or (l == 1 and "передатчик ВНЕ сети" or "голый — эфира не будет")
        end
        if k == "speaker" then return RN.SpeakerActive(e) and "в сети" or "вне сети" end
        if k == "radio" then return RN.ReceiverOK(e) and "покрытие OK" or "вне покрытия" end
        if k == "console" then return consoleLinked(e) and "в сети" or "нет стойки рядом" end
        return "?"
    end

    consoleOpen = function(ply, con)
        if not IsValid(ply) or not IsValid(con) then return end
        if not ply:IsSuperAdmin() then
            if GRM.Notify then GRM.Notify(ply, "Доступ к пульту радиосети — только у суперадмина.", 255, 140, 110) end
            return
        end
        if not consoleLinked(con) then
            if GRM.Notify then GRM.Notify(ply, "Пульт ВНЕ СЕТИ: рядом нет АКТИВНОЙ серверной стойки (радиус связи " .. tostring(RN.LinkDist) .. " юн).", 255, 140, 110) end
            return
        end
        recompute()
        local cpos = con:GetPos()
        local devs, groups, gset = {}, {}, {}
        for id, rec in pairs(RN.Sys.devices) do
            local e = RN._id2ent[id]
            local dist, az, q = 0, 0, 0
            if istable(rec.pos) then
                dist, az = bearingOf(cpos, rec.pos)
                q = math.floor(RN.QualityAt(Vector(rec.pos.x or 0, rec.pos.y or 0, rec.pos.z or 0)) * 100 + 0.5)
            end
            local glist = {}
            for g in pairs(rec.groups or {}) do
                glist[#glist + 1] = g
                if not gset[g] then gset[g] = true groups[#groups + 1] = g end
            end
            table.sort(glist)
            local label
            for _, meta in pairs(RN.Kinds) do if meta.k == rec.kind then label = meta.label break end end
            devs[#devs + 1] = {
                id = id, kind = rec.kind, label = label or rec.kind,
                alive = IsValid(e), off = rec.off == true,
                state = deviceNetState(rec, e),
                x = rec.pos and rec.pos.x or 0, y = rec.pos and rec.pos.y or 0, z = rec.pos and rec.pos.z or 0,
                dist = dist, az = az, q = q,
                groups = table.concat(glist, ", "),
                paTarget = rec.kind == "mic" and tostring(rec.paTarget or "") or nil,
                lastSeen = tonumber(rec.lastSeen) or 0,
            }
        end
        table.sort(devs, function(a, b) return tostring(a.id) < tostring(b.id) end)
        table.sort(groups)
        net.Start(NET_OPEN)
            net.WriteUInt(con:EntIndex(), 16)
            net.WriteTable({ idx = con:EntIndex(), devices = devs, groups = groups, log = RN.LogTail(RN.LogCap) })
        net.Send(ply)
    end
    RN.ConsoleOpen = consoleOpen

    -- операции пульта (всё перевалидируется: права + живая связь пульта)
    net.Receive(NET_OP, function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        local con = Entity(net.ReadUInt(16))
        local op = tostring(net.ReadString() or "")
        local a = net.ReadTable()
        if not istable(a) or not IsValid(con) or con:GetClass() ~= "grm_net_console" then return end
        if not consoleLinked(con) then
            if GRM.Notify then GRM.Notify(ply, "Пульт вне сети — операция отклонена.", 255, 140, 110) end
            return
        end

        if op == "refresh" then consoleOpen(ply, con) return end

        if op == "toggle" then
            local id = tostring(a.id or "")
            local rec = RN.Sys.devices[id]
            if not istable(rec) then return end
            local e = RN._id2ent[id]
            if rec.kind == "console" and IsValid(e) and e == con then
                if GRM.Notify then GRM.Notify(ply, "Пульт нельзя отключить сам у себя.", 255, 200, 120) end
                return
            end
            rec.off = not (rec.off == true)
            RN.SysSave("toggle " .. id)
            recompute()
            logEvent("dev_switch", rpName(ply), freqIdentity(ply), IsValid(e) and e:GetPos() or nil,
                rec.off and ("вывод устройства " .. id .. " ВЫКЛЮЧЕН пультом") or ("вывод " .. id .. " возвращён"))
            consoleOpen(ply, con)
            return
        end

        if op == "assign" then
            local id = tostring(a.id or "")
            local g = string.sub(string.Trim(tostring(a.group or "")), 1, 24)
            local rec = RN.Sys.devices[id]
            if not istable(rec) or g == "" then return end
            rec.groups = istable(rec.groups) and rec.groups or {}
            if a.on == true then rec.groups[g] = true else rec.groups[g] = nil end
            RN.SysSave("группа " .. id .. " → «" .. g .. "» " .. tostring(a.on == true))
            consoleOpen(ply, con)
            return
        end

        if op == "group_del" then
            local g = tostring(a.group or "")
            local n = 0
            for _, rec in pairs(RN.Sys.devices) do
                if istable(rec.groups) and rec.groups[g] == true then rec.groups[g] = nil n = n + 1 end
            end
            RN.SysSave("группа «" .. g .. "» удалена (снято устройств: " .. n .. ")")
            consoleOpen(ply, con)
            return
        end

        if op == "dev_del" then
            local id = tostring(a.id or "")
            if IsValid(RN._id2ent[id]) then return end -- живое устройство не выкидываем
            if RN.Sys.devices[id] then
                RN.Sys.devices[id] = nil
                RN.SysSave("запись " .. id .. " удалена")
            end
            consoleOpen(ply, con)
            return
        end

        if op == "mic_target" then
            local id = tostring(a.id or "")
            local rec = RN.Sys.devices[id]
            if not istable(rec) or rec.kind ~= "mic" then return end
            local g = string.sub(string.Trim(tostring(a.group or "")), 1, 24)
            rec.paTarget = (g ~= "") and g or nil
            local e = RN._id2ent[id]
            if IsValid(e) then e:SetNWString("GRM_RN_Target", rec.paTarget or "") end
            RN.SysSave("цель ГРОМКОЙ СВЯЗИ " .. id .. " = " .. (rec.paTarget or "весь город"))
            consoleOpen(ply, con)
            return
        end

        if op == "alert" then
            local text = string.sub(string.Trim(tostring(a.text or "")), 1, 240)
            if #text < 3 then
                if GRM.Notify then GRM.Notify(ply, "Текст оповещения короче 3 символов.", 255, 140, 110) end
                return
            end
            if not (GRM.Broadcast and GRM.Broadcast.SendAlert) then return end
            local target = string.sub(string.Trim(tostring(a.target or "")), 1, 24)
            local name = ply:GetNWString("GRM_RPName", "")
            if name == "" then name = ply:Nick() end
            local okA, msg = GRM.Broadcast.SendAlert(name, text, false, ply, target ~= "" and target or nil)
            if GRM.Notify then GRM.Notify(ply, tostring(msg or (okA and "Оповещение отправлено" or "Ошибка оповещения")), okA and 120 or 255, okA and 220 or 140, 110) end
            consoleOpen(ply, con)
            return
        end

        if op == "log_clear" then
            RN.Sys.log = {}
            RN.SysSave("журнал очищен")
            consoleOpen(ply, con)
            return
        end
    end)

    ----------------------------------------------------------------
    -- Периодический пересчёт сети
    ----------------------------------------------------------------
    recompute = function()
        -- Пересчёт топологии радиосети шёл каждые 0.7 с и делал ПЯТЬ полных
        -- сканов классов подряд. Теперь классы берутся из event-реестров
        -- GRM.Perf — скан заменён готовыми массивами.
        registerDevices()  -- Код 87: позывные/реестр прежде топологии
        local racks = ((GRM.Perf and GRM.Perf.Entities) and GRM.Perf.Entities("grm_server_rack") or ents.FindByClass("grm_server_rack"))
        RN._racks = racks
        local active = {}
        for _, r in ipairs(racks) do
            if IsValid(r) and r:GetNWBool("GRM_RN_On", true) and deviceOnForEnt(r) then active[#active + 1] = r end
        end
        RN._activeRacks = active

        local cov = {}
        for _, r in ipairs(active) do cov[#cov + 1] = { pos = r:GetPos(), r = RN.RackRange } end

        local ants, linked = ((GRM.Perf and GRM.Perf.Entities) and GRM.Perf.Entities("grm_antenna") or ents.FindByClass("grm_antenna")), 0
        for _, a in ipairs(ants) do
            if IsValid(a) then
                local isL = nearActiveRack(a:GetPos(), RN.LinkDist) and deviceOnForEnt(a)
                if a:GetNWBool("GRM_RN_Linked", false) ~= isL then a:SetNWBool("GRM_RN_Linked", isL) end
                if isL then
                    linked = linked + 1
                    cov[#cov + 1] = { pos = a:GetPos(), r = RN.AntennaRange }
                end
            end
        end
        RN._antsTotal = #ants
        RN._antsLinked = linked
        RN._coverage = cov

        for _, m in ipairs(((GRM.Perf and GRM.Perf.Entities) and GRM.Perf.Entities("grm_broadcast_mic") or ents.FindByClass("grm_broadcast_mic"))) do
            if IsValid(m) then
                local l = RN.MicLink(m)
                if m:GetNWInt("GRM_RN_Link", -1) ~= l then m:SetNWInt("GRM_RN_Link", l) end
            end
        end
        for _, st in ipairs(((GRM.Perf and GRM.Perf.Entities) and GRM.Perf.Entities("grm_radio_station") or ents.FindByClass("grm_radio_station"))) do
            if IsValid(st) then
                local on = nearActiveRack(st:GetPos(), RN.LinkDist)
                if st:GetNWBool("GRM_RN_Online", false) ~= on then st:SetNWBool("GRM_RN_Online", on) end
            end
        end
        for _, c in ipairs(((GRM.Perf and GRM.Perf.Entities) and GRM.Perf.Entities("grm_net_console") or ents.FindByClass("grm_net_console"))) do
            if IsValid(c) then
                local on = nearActiveRack(c:GetPos(), RN.LinkDist)
                if c:GetNWBool("GRM_RN_Online", false) ~= on then c:SetNWBool("GRM_RN_Online", on) end
            end
        end
    end
    RN.Recompute = recompute

    --[[ Сторож пересчёта раньше обходил ПЯТЬ реестров сущностей каждые
         0.7 c — и делал это даже на карте без единой рации. Настоящие
         изменения (включили стойку, поставили антенну, сняли устройство)
         и так зовут recompute напрямую, поэтому сторожу достаточно редкого
         прохода: он остался страховкой, а не основным механизмом. ]]
    local function radioNetEmpty()
        local function count(cls)
            local list = (GRM.Perf and GRM.Perf.Entities) and GRM.Perf.Entities(cls) or ents.FindByClass(cls)
            return #(list or {})
        end
        return (count("grm_server_rack") + count("grm_antenna") + count("grm_broadcast_mic")
            + count("grm_radio_station") + count("grm_net_console")) == 0
    end

    timer.Create("GRM_RN_Watch", 3, 0, function()
        if radioNetEmpty() then return end
        recompute()
    end)
    timer.Simple(1, recompute)

    ----------------------------------------------------------------
    -- Диагностика
    ----------------------------------------------------------------
    function RN.StatusLines()
        local spk, spkOn = ents.FindByClass("grm_loudspeaker"), 0
        for _, s in ipairs(spk) do if RN.SpeakerActive(s) then spkOn = spkOn + 1 end end
        local mics = ents.FindByClass("grm_broadcast_mic")
        local m2, m1 = 0, 0
        for _, m in ipairs(mics) do
            local l = RN.MicLink(m)
            if l >= 2 then m2 = m2 + 1 elseif l == 1 then m1 = m1 + 1 end
        end
        local stations = ents.FindByClass("grm_radio_station")
        local stOn = 0
        for _, s in ipairs(stations) do if nearActiveRack(s:GetPos(), RN.LinkDist) then stOn = stOn + 1 end end
        local racksOn = #RN._activeRacks
        local devTotal, devOff, conOn = 0, 0, 0
        for _, rec in pairs(RN.Sys and RN.Sys.devices or {}) do
            devTotal = devTotal + 1
            if rec.off == true then devOff = devOff + 1 end
        end
        for _, c in ipairs(ents.FindByClass("grm_net_console")) do
            if c:GetNWBool("GRM_RN_Online", false) then conOn = conOn + 1 end
        end
        return {
            "Стойки: " .. tostring(racksOn) .. "/" .. tostring(#(RN._racks or {})) .. " активны (питание — клавиша E)",
            "Антенны: " .. tostring(RN._antsLinked) .. "/" .. tostring(RN._antsTotal) .. " связаны со стойками (радиус связи " .. RN.LinkDist .. ", покрытие антенны " .. RN.AntennaRange .. " юн)",
            "Передатчики в сети: " .. tostring(stOn) .. "/" .. tostring(#stations),
            "Микрофоны: в сети " .. tostring(m2) .. ", передатчик вне сети " .. tostring(m1) .. ", голых " .. tostring(#mics - m2 - m1),
            "Громкоговорители в сети: " .. tostring(spkOn) .. "/" .. tostring(#spk),
            "Реестр: " .. tostring(devTotal) .. " устройств с позывными (отключено пультом: " .. tostring(devOff) .. "); пультов в сети: " .. tostring(conOn) .. " (/console_add)",
            "Журнал событий: " .. tostring(#(RN.Sys and RN.Sys.log or {})) .. " записей (/rn_log — последние 12)",
            "Покрытие: " .. tostring(#(RN._coverage or {})) .. " кругов (стойка " .. RN.RackRange .. " юн, антенна " .. RN.AntennaRange .. " юн); рация вне сети — " .. RN.DirectRadio .. " юн напрямую",
            "Радиочастоты (/freq /r, Код 98): абонентов на частотах: " .. tostring(table.Count(RN._freq or {})),
        }
    end

    ----------------------------------------------------------------
    -- Радиоканалы (Код 98): /freq <частота>, /freqleave, /r <текст>.
    -- До этого кода команд /freq /r НЕ СУЩЕСТВОВАЛО на сервере вовсе
    -- (находка 115): C-меню слало их в никуда. Здесь они живут на
    -- правилах радиосети: доставка по RadioPairOK (оба в покрытии
    -- сети ИЛИ прямая дальность), на прямой дальности — помехи в
    -- тексте по мере удаления. Частота помнится за sid64 до явного
    -- /freqleave (смерть/перезаход рацию не сбрасывают).
    ----------------------------------------------------------------
    RN.FreqMin      = 1      -- нижняя граница частоты (МГц)
    RN.FreqMax      = 999.9  -- верхняя (совпадает с подсказкой C-меню)
    RN.FreqSayDelay = 1.5    -- антифлуд: пауза между радиосообщениями
    RN.FreqMaxLen   = 220    -- макс. длина одного сообщения (символов)

    freqIdentity = function(value)
        if IsValid(value) and value.IsPlayer and value:IsPlayer() then
            if GRM.Identity and GRM.Identity.CharacterKey then return GRM.Identity.CharacterKey(value) end
            return tostring(value:SteamID64() or "")
        end
        local raw = tostring(value or "")
        if raw:match(":char[1-3]$") then return raw end
        if raw:match("^%d+$") then return raw .. ":char1" end
        if util.SteamIDTo64 then
            local s64 = util.SteamIDTo64(raw)
            if s64 and s64 ~= "0" then return tostring(s64) .. ":char1" end
        end
        return raw
    end

    RN._freq = RN._freq or {} -- CharacterKey → «145.5»

    -- форвард-декларация (урок 97-хотфикса): needUnit выше объявления
    local freqChat

    -- нормализация: 1..999.9, шаг 0.1 → ключ вида «145.5»; «145.55» — отказ
    function RN.FreqKey(arg)
        local n = tonumber(string.match(tostring(arg or ""), "^%s*(%d+%.?%d*)%s*$"))
        if not n or n < RN.FreqMin or n > RN.FreqMax then return nil end
        local key = string.format("%.1f", n)
        if math.abs(tonumber(key) - n) > 0.0001 then return nil end
        return key
    end

    function RN.FreqOf(ply)
        if not IsValid(ply) then return nil end
        local f = ply._rnFreq
        if f == nil and ply.SteamID64 then f = RN._freq[tostring(freqIdentity(ply) or "")] end
        return f
    end

    -- Код 99 (находка 116): частоты только с железкой — переносной
    -- модулятор должен лежать В ИНВЕНТАРЕ и быть АКТИВИРОВАННЫМ
    -- (data.on == true, «Использовать» в /inv). Состояние в предмете:
    -- выбрасываешь — теряешь связь, подбираешь — она как была.
    function RN.HasRadioUnit(ply)
        if not IsValid(ply) then return false end
        if GRM.Customization and GRM.Customization.HasFunction
            and GRM.Customization.HasFunction(ply, "radio") then return true end
        if not (GRM.Inventory and GRM.Inventory.GetPlayerInv) then return false end
        local inv = GRM.Inventory.GetPlayerInv(ply)
        if not (istable(inv) and istable(inv.slots)) then return false end
        for _, slot in pairs(inv.slots) do
            if istable(slot) and slot.id == RN.UnitItem
                and istable(slot.data) and slot.data.on == true then
                return true
            end
        end
        return false
    end

    local function needUnit(ply)
        freqChat(ply, "[Рация] Нужен АКТИВНЫЙ переносной модулятор: купите в /phoneshop («Модулятор рации») и нажмите «Использовать» в инвентаре (/inv).")
        if GRM.Notify then GRM.Notify(ply, "Нет активного модулятора рации (магазин /phoneshop)", 255, 180, 90) end
    end

    freqChat = function(ply, msg)
        if IsValid(ply) and ply.PrintMessage then ply:PrintMessage(HUD_PRINTTALK, msg) end
    end

    -- безопасный срез по UTF-8 символам (байтовый sub ломал бы кириллицу)
    local function ucut(s, maxChars)
        local cp = (utf8 and utf8.charpattern) or "."
        local out, n = {}, 0
        for ch in string.gmatch(tostring(s or ""), cp) do
            n = n + 1
            if n > maxChars then break end
            out[#out + 1] = ch
        end
        return table.concat(out)
    end

    function RN.FreqSet(ply, arg)
        if not RN.HasRadioUnit(ply) then needUnit(ply) return false end
        local key = RN.FreqKey(arg)
        if not key then
            freqChat(ply, "[Рация] Частота — число 1–999.9 с шагом 0.1. Пример: /freq 145.5")
            return false
        end
        ply._rnFreq = key
        if ply.SteamID64 then RN._freq[tostring(freqIdentity(ply) or "")] = key end
        freqChat(ply, "[Рация] Вы на частоте " .. key .. " МГц. Говорить: /r текст. Отключиться: /freqleave")
        if GRM.Notify then GRM.Notify(ply, "Рация: частота " .. key .. " МГц (/r текст)", 140, 200, 255) end
        if RN.LogEvent then RN.LogEvent("freq_join", rpName(ply),
            ply.SteamID64 and freqIdentity(ply) or "", IsValid(ply) and ply:GetPos() or nil, "частота " .. key) end
        return true
    end

    function RN.FreqInfo(ply)
        local f = RN.FreqOf(ply)
        local unit = RN.HasRadioUnit(ply)
        if f then
            freqChat(ply, "[Рация] Текущая частота: " .. f .. " МГц" .. (unit and "" or " (модулятор ВЫКЛ — эфир закрыт)") .. ". Говорить: /r текст. Отключиться: /freqleave")
        else
            if unit then
                freqChat(ply, "[Рация] Модулятор активен, но частота не настроена. Включить: /freq 145.5")
            else
                freqChat(ply, "[Рация] Рация не настроена. Нужен активный модулятор (/phoneshop) + /freq 145.5")
            end
        end
    end

    function RN.FreqLeave(ply)
        local f = RN.FreqOf(ply)
        if not f then freqChat(ply, "[Рация] Вы и так не на частоте.") return end
        ply._rnFreq = nil
        if ply.SteamID64 then RN._freq[tostring(freqIdentity(ply) or "")] = nil end
        freqChat(ply, "[Рация] Частота " .. f .. " покинута — рация отключена.")
        if RN.LogEvent then RN.LogEvent("freq_leave", rpName(ply),
            ply.SteamID64 and freqIdentity(ply) or "", ply:GetPos(), "частота " .. f) end
    end

    -- помехи текста: часть символов заменяется «*» (шипение); пробелы живут,
    -- кириллица не ломается (идём посимвольно по utf8.charpattern)
    function RN.FreqScramble(s, keep, seed)
        if keep >= 0.985 then return s end
        local cp = (utf8 and utf8.charpattern) or "."
        local out, i = {}, 0
        for ch in string.gmatch(tostring(s or ""), cp) do
            i = i + 1
            if ch == " " then
                out[#out + 1] = ch
            else
                local h = (seed * 2654435761 + i * 40503) % 1000
                out[#out + 1] = (h < keep * 1000) and ch or "*"
            end
        end
        return table.concat(out)
    end

    function RN.FreqSay(ply, raw)
        if not RN.HasRadioUnit(ply) then needUnit(ply) return false end
        local f = RN.FreqOf(ply)
        if not f then
            freqChat(ply, "[Рация] Вы не на частоте — сначала настройтесь: /freq 145.5")
            return false
        end
        local now = CurTime()
        if ply._rnFreqTs and (now - ply._rnFreqTs) < RN.FreqSayDelay then
            freqChat(ply, "[Рация] Не так быстро: следующая передача через " .. tostring(RN.FreqSayDelay) .. " сек.")
            return false
        end
        ply._rnFreqTs = now
        local text = ucut(string.Trim(tostring(raw or "")), RN.FreqMaxLen)
        if text == "" then freqChat(ply, "[Рация] Пустое сообщение в эфир не уходит.") return false end
        local name = rpName(ply)
        local myPos = IsValid(ply) and ply:GetPos() or nil
        local delivered = 0
        for _, lp in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if RN.FreqOf(lp) == f then
                local ok = (lp == ply)
local body = text                if not ok and myPos and IsValid(lp) and lp.GetPos then
                    if RN.RadioPairOK(ply, lp) then
                        ok = true
                        -- оба в сети — текст чистый на любой дистанции;
                        -- прямая дальность — помехи ∝ удалению
                        if not (RN.CoveredAt(myPos) and RN.CoveredAt(lp:GetPos())) then
                            local d = math.sqrt(myPos:DistToSqr(lp:GetPos()))
                            local keep = math.max(0.25, math.min(1, 1.1 - d / RN.DirectRadio))
                            body = RN.FreqScramble(text, keep, lp:EntIndex())
                        end
                    end
                end
                if ok then
                    freqChat(lp, "[Рация " .. f .. "] " .. name .. ": " .. body)
                    delivered = delivered + 1
                end
            end
        end
        if delivered <= 1 then
            freqChat(ply, "[Рация] …в эфире тишина: на этой частоте вас никто не слышит (нет абонентов или все вне связи).")
        end
        if RN.LogEvent then RN.LogEvent("freq_say", name, ply.SteamID64 and freqIdentity(ply) or "", myPos,
            "частота " .. f .. ", слышат " .. tostring(delivered) .. " | " .. text) end
        return true
    end

    -- восстановление частоты при входе: память по sid64 в пределах сессии
    hook.Add("PlayerInitialSpawn", "GRM_RN_FreqSpawn", function(ply)
        if not IsValid(ply) or not ply.SteamID64 then return end
        local f = RN._freq[tostring(freqIdentity(ply) or "")]
        if f then ply._rnFreq = f end
    end)

    ----------------------------------------------------------------
    -- Чат-команды (тот же каркас PlayerSayTransform+PlayerSay,
    -- что у Кода 75 — чат-системы не проглатывают)
    ----------------------------------------------------------------
    local function spawnAtAim(ply, class, label)
        if not IsValid(ply) or not ply:IsSuperAdmin() then
            if IsValid(ply) then ply:PrintMessage(HUD_PRINTTALK, "[" .. label .. "] Только для суперадмина.") end
            return
        end
        local tr = util.TraceLine({ start = ply:GetShootPos(), endpos = ply:GetShootPos() + ply:GetAimVector() * 320, filter = ply })
        if not tr.Hit then ply:PrintMessage(HUD_PRINTTALK, "[" .. label .. "] Прицельтесь в пол/стену рядом.") return end
        local nt = ents.Create(class)
        if not IsValid(nt) then ply:PrintMessage(HUD_PRINTTALK, "[" .. label .. "] Энтити не зарегистрирована!") return end
        nt:SetPos(tr.HitPos + tr.HitNormal * 2)
        local ang = (ply:GetPos() - tr.HitPos):Angle()
        nt:SetAngles(Angle(0, ang.y, 0))
        nt:Spawn() nt:Activate()
        local phys = nt:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
        if class == "grm_server_rack" then nt:SetNWBool("GRM_RN_On", true) end
        RN.PersistAdd(nt)
        recompute()
        local rmCmd = ({ grm_server_rack = "rack_remove", grm_antenna = "antenna_remove",
            grm_radio_station = "rstation_remove", grm_net_console = "console_remove" })[class] or "rstation_remove"
        ply:PrintMessage(HUD_PRINTTALK, "[" .. label .. "] Установлен и СОХРАНЁН на карте автоматически. Снять: /" .. rmCmd .. " прицелом.")
        if GRM.Notify then GRM.Notify(ply, label .. " установлен (персистентно).", 100, 220, 100) end
    end
    local function removeAtAim(ply, class, label)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        local tr = util.TraceLine({ start = ply:GetShootPos(), endpos = ply:GetShootPos() + ply:GetAimVector() * 220, filter = ply })
        local ent = tr.Entity
        if not IsValid(ent) or ent:GetClass() ~= class then
            ply:PrintMessage(HUD_PRINTTALK, "[" .. label .. "] В прицеле нет такой энтити.")
            return
        end
        RN.PersistRemove(ent)
        ent:Remove()
        recompute()
        ply:PrintMessage(HUD_PRINTTALK, "[" .. label .. "] Удалён (и из персистента).")
    end

    hook.Add("PlayerSay", "GRM_RN_TransformCmds", function(ply, text, teamSays)
        local datapack = { tostring(text or ""), SkipPlayerSay = false }
            if not istable(datapack) then return end
            local msg = datapack[1]
            if not isstring(msg) then return end
            if RN.HandleChat and RN.HandleChat(ply, msg) then
                datapack[1] = ""
                datapack.SkipPlayerSay = true
            end

        if datapack.SkipPlayerSay == true then return "" end
    end)

    hook.Add("PlayerSay", "GRM_RN_Cmds", function(ply, text)
        if RN.HandleChat and RN.HandleChat(ply, text) then return "" end
    end)

    function RN.HandleChat(ply, text)
        local low = string.lower(string.Trim(text or ""))
        if low == "/rack_add" then spawnAtAim(ply, "grm_server_rack", "Серверная стойка") return true end
        if low == "/rack_remove" then removeAtAim(ply, "grm_server_rack", "Серверная стойка") return true end
        if low == "/antenna_add" then spawnAtAim(ply, "grm_antenna", "Антенна") return true end
        if low == "/antenna_remove" then removeAtAim(ply, "grm_antenna", "Антенна") return true end
        if low == "/rstation_add" then spawnAtAim(ply, "grm_radio_station", "Радиопередатчик") return true end
        if low == "/rstation_remove" then removeAtAim(ply, "grm_radio_station", "Радиопередатчик") return true end
        if low == "/console_add" then spawnAtAim(ply, "grm_net_console", "Пульт радиосети") return true end
        if low == "/console_remove" then removeAtAim(ply, "grm_net_console", "Пульт радиосети") return true end
        if low == "/rn_log" then
            if not ply:IsSuperAdmin() then ply:PrintMessage(HUD_PRINTTALK, "[Радиосеть] Только для суперадмина.") return true end
            local log = RN.LogTail(12)
            if #log == 0 then ply:PrintMessage(HUD_PRINTTALK, "[Радиосеть] Журнал пуст.") return true end
            ply:PrintMessage(HUD_PRINTTALK, "[Радиосеть] ===== журнал (последние " .. tostring(#log) .. ") =====")
            for _, e in ipairs(log) do
                ply:PrintMessage(HUD_PRINTTALK, ("[Радиосеть] %s | %s | %s | (%d %d %d) q=%d%% | %s"):format(
                    os.date("%H:%M:%S", tonumber(e.ts) or 0), tostring(e.kind), tostring(e.who),
                    tonumber(e.x) or 0, tonumber(e.y) or 0, tonumber(e.z) or 0, tonumber(e.q) or 0, tostring(e.note)))
            end
            return true
        end
        if low == "/rn_status" or low == "/rn_net" then
            if not ply:IsSuperAdmin() then ply:PrintMessage(HUD_PRINTTALK, "[Радиосеть] Только для суперадмина.") return true end
            recompute()
            ply:PrintMessage(HUD_PRINTTALK, "[Радиосеть] ===== диагностика =====")
            for _, ln in ipairs(RN.StatusLines()) do
                ply:PrintMessage(HUD_PRINTTALK, "[Радиосеть] " .. ln)
            end
            return true
        end
        -- Код 98: радиоканалы /freq /r (поглощаем — в игровой чат не уходит)
        if low == "/freq" or low == "!freq" then RN.FreqInfo(ply) return true end
        if low == "/freqleave" or low == "!freqleave"
            or low == "/freq off" or low == "!freq off"
            or low == "/freq 0" or low == "!freq 0" then RN.FreqLeave(ply) return true end
        local farg = string.match(low, "^[!/]freq%s+(%S+)%s*$")
        if farg then RN.FreqSet(ply, farg) return true end
        if low == "/r" or low == "!r" then
            ply:PrintMessage(HUD_PRINTTALK, "[Рация] Формат: /r текст сообщения")
            return true
        end
        local rmsg = string.match(text or "", "^%s*[!/][rR]%s+(.+)$")
        if rmsg then RN.FreqSay(ply, rmsg) return true end
        return false
    end

    print("[GRM RadioNet] Сервер v" .. RN.Version .. " загружен")
end

-- ============================================================
-- КЛИЕНТ: щелчки/треск «радио-искажения»
-- ============================================================
if CLIENT then
    local fxTalkers = {} -- entindex → "radio"/"pa"/"mega"
    net.Receive(NET_FX, function()
        local idx = net.ReadUInt(16)
        local kind = net.ReadString()
        local on = net.ReadBool()
        if on then
            fxTalkers[idx] = kind
            if RN.EnsureCrackle then RN.EnsureCrackle() end
            if kind == "pa" then surface.PlaySound("buttons/combine_button1.wav")
            elseif kind == "mega" then surface.PlaySound("buttons/button15.wav")
            else surface.PlaySound("buttons/button9.wav") end
        else
            if fxTalkers[idx] == "pa" then surface.PlaySound("buttons/button18.wav") end
            fxTalkers[idx] = nil
        end
    end)

    -- треск помех: пока «сетевой» говорящий реально говорит, время от
    -- времени проскакивает щелчок статики; если он рядом физически —
    -- не искажаем (слышим живой голос)
    --[[ Треск помех нужен только пока кто-то говорит в сеть. Держать ради
         этого постоянный таймер два раза в секунду незачем: создаём его на
         время разговора и снимаем, когда говорящих не осталось. ]]
    local function crackleTick()
        local lp = LocalPlayer()
        if not IsValid(lp) then return end
        if not next(fxTalkers) then timer.Remove("GRM_RN_Crackle") return end
        for idx, kind in pairs(fxTalkers) do
            local t = Entity(idx)
            if IsValid(t) and t.IsSpeaking and t:IsSpeaking() then
                local near = t:GetPos():DistToSqr(lp:GetPos()) <= 500 * 500
                if not near then
                    local p = (kind == "pa") and 0.55 or (kind == "mega") and 0.35 or 0.25
                    if math.Rand(0, 1) < p then
                        surface.PlaySound("ambient/energy/spark" .. tostring(math.random(1, 6)) .. ".wav")
                    end
                end
            end
        end
    end

    --- Включить треск, когда появился говорящий (зовётся из приёмника FX).
    function RN.EnsureCrackle()
        if next(fxTalkers) == nil then return end
        if timer.Exists("GRM_RN_Crackle") then return end
        timer.Create("GRM_RN_Crackle", 0.5, 0, crackleTick)
    end

    ----------------------------------------------------------------
    -- Код 87 — окно пульта радиосети (NetSys)
    ----------------------------------------------------------------
    surface.CreateFont("GRMCon_T", { font = "Roboto", size = 18, weight = 800, extended = true })
    surface.CreateFont("GRMCon_S", { font = "Roboto", size = 13, weight = 600, extended = true })
    surface.CreateFont("GRMCon_X", { font = "Roboto", size = 12, weight = 500, extended = true })

    local CC = {
        bg = Color(16, 20, 28, 250), head = Color(26, 32, 44, 255), panel = Color(30, 36, 48, 240),
        acc = Color(90, 170, 250), green = Color(80, 210, 130), red = Color(225, 85, 80),
        yellow = Color(230, 190, 70), text = Color(240, 245, 250), dim = Color(160, 170, 185),
    }
    local _con = { frame = nil, data = nil, lists = {}, auto = false }

    local function sendOp(op, payload)
        if not (_con.data and _con.data.idx) then return end
        net.Start(NET_OP)
            net.WriteUInt(_con.data.idx, 16)
            net.WriteString(op)
            net.WriteTable(payload or {})
        net.SendToServer()
    end

    local function kindLabel(rec) return tostring(rec.label or rec.kind or "?") end

    local function fillDevices()
        local lv = _con.lists.dev
        if not IsValid(lv) or not istable(_con.data) then return end
        lv:Clear()
        for _, d in ipairs(_con.data.devices or {}) do
            local st = d.off and "ВЫКЛЮЧЕН пультом" or tostring(d.state or "?")
            if not d.alive then st = "ПРИЗРАК (железа нет)" end
            local ln = lv:AddLine(d.id, kindLabel(d), st,
                string.format("%d %d %d", d.x or 0, d.y or 0, d.z or 0),
                tostring(d.dist or 0), tostring(d.az or 0) .. "°",
                tostring(d.q or 0) .. "%", tostring(d.groups or ""))
            ln.grmDev = d
        end
        if IsValid(_con.lists.devHead) then
            _con.lists.devHead:SetText("Устройств в реестре: " .. tostring(#(_con.data.devices or {}))
                .. "  (ПКМ по строке — включение/группы/цель громкой связи; автообновление 2 с)")
        end
    end

    local function fillGroups()
        local lv = _con.lists.grp
        if not IsValid(lv) or not istable(_con.data) then return end
        lv:Clear()
        local cnt = {}
        for _, d in ipairs(_con.data.devices or {}) do
            for g in string.gmatch(tostring(d.groups or ""), "[^,%s][^,]*") do
                g = string.Trim(g)
                if g ~= "" then cnt[g] = (cnt[g] or 0) + 1 end
            end
        end
        for _, g in ipairs(_con.data.groups or {}) do
            local ln = lv:AddLine(g, tostring(cnt[g] or 0))
            ln.grmGroup = g
        end
    end

    local function fillLog()
        local lv = _con.lists.log
        if not IsValid(lv) or not istable(_con.data) then return end
        lv:Clear()
        local log = _con.data.log or {}
        for i = #log, 1, -1 do
            local e = log[i]
            lv:AddLine(os.date("%H:%M:%S", tonumber(e.ts) or 0), tostring(e.kind or "?"),
                tostring(e.who or "?"),
                string.format("%d %d %d", tonumber(e.x) or 0, tonumber(e.y) or 0, tonumber(e.z) or 0),
                tostring(tonumber(e.q) or 0) .. "%", tostring(e.note or ""))
        end
    end

    local function onGroupPicked(dev, g)
        sendOp("assign", { id = dev.id, group = g, on = true })
    end

    local function deviceMenu(line)
        local d = line.grmDev
        if not istable(d) then return end
        local m = DermaMenu()
        if d.alive then
            m:AddOption(d.off and "✔ Вернуть вывод (включить)" or "✖ Снять с эфира (выключить)", function()
                sendOp("toggle", { id = d.id })
            end):SetIcon(d.off and "icon16/accept.png" or "icon16/cancel.png")

            local hasGroups = false
            for g in string.gmatch(tostring(d.groups or ""), "[^,%s][^,]*") do
                if not hasGroups then hasGroups = true end
                break
            end

            local plus = m:AddSubMenu("➕ Включить в группу…")
            plus:AddOption("＋ Новая группа…", function()
                Derma_StringRequest("Группа устройства " .. d.id, "Имя группы (например, Север):", "", function(txt)
                    local g = string.sub(string.Trim(tostring(txt or "")), 1, 24)
                    if g ~= "" then onGroupPicked(d, g) end
                end)
            end)
            local gset = {}
            for g in string.gmatch(tostring(d.groups or ""), "[^,%s][^,]*") do gset[string.Trim(g)] = true end
            for _, g in ipairs((_con.data or {}).groups or {}) do
                if not gset[g] then
                    plus:AddOption(g, function() onGroupPicked(d, g) end)
                end
            end

            local minus = m:AddSubMenu("➖ Вывести из группы…")
            local any = false
            for g in string.gmatch(tostring(d.groups or ""), "[^,%s][^,]*") do
                any = true
                local gg = string.Trim(g)
                minus:AddOption(gg, function()
                    sendOp("assign", { id = d.id, group = gg, on = false })
                end)
            end
            if not any then minus:AddOption("(устройство не в группах)", function() end) end

            if d.kind == "mic" then
                local tsub = m:AddSubMenu("🎯 Цель ГРОМКОЙ СВЯЗИ: " .. (d.paTarget ~= nil and d.paTarget ~= "" and d.paTarget or "весь город"))
                tsub:AddOption("Весь город (все громкоговорители)", function()
                    sendOp("mic_target", { id = d.id, group = "" })
                end)
                for _, g in ipairs((_con.data or {}).groups or {}) do
                    tsub:AddOption("Группа «" .. g .. "»", function()
                        sendOp("mic_target", { id = d.id, group = g })
                    end)
                end
            end
        else
            m:AddOption("🗑 Удалить запись о призраке", function()
                Derma_Query("Удалить запись «" .. tostring(d.id) .. "» из реестра? Железа на карте уже нет.",
                    "Реестр радиосети", "Удалить", function() sendOp("dev_del", { id = d.id }) end, "Отмена", function() end)
            end):SetIcon("icon16/bin.png")
        end
        m:Open()
    end

    local function mkBtn(p, txt, col)
        local b = vgui.Create("DButton", p)
        b:SetText(txt) b:SetFont("GRMCon_S") b:SetTextColor(color_white)
        b.Paint = function(self, pw, ph)
            local cc = col or CC.acc
            if self:IsHovered() then cc = Color(math.min(255, cc.r + 25), math.min(255, cc.g + 25), math.min(255, cc.b + 25)) end
            draw.RoundedBox(6, 0, 0, pw, ph, cc)
        end
        return b
    end

    local function openConsoleWindow(data)
        if IsValid(_con.frame) then _con.frame:Remove() end
        _con.data = data
        _con.lists = {}

        local f = vgui.Create("DFrame")
        _con.frame = f
        f:SetSize(980, 660) f:Center() f:MakePopup() f:ShowCloseButton(false) f:SetTitle("")
        f.Paint = function(_, pw, ph)
            draw.RoundedBox(10, 0, 0, pw, ph, CC.bg)
            draw.RoundedBoxEx(10, 0, 0, pw, 44, CC.head, true, true, false, false)
            draw.SimpleText("ПУЛЬТ РАДИОСЕТИ — идентификация, группы, пеленг, журнал", "GRMCon_T", 14, 22, CC.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        local x = mkBtn(f, "X", CC.red, 34, 28) x:SetPos(980 - 42, 8)
        x.DoClick = function() f:Remove() end
        f.OnRemove = function()
            _con.frame = nil
            timer.Remove("GRM_Con_Auto")
        end

        local tabs = vgui.Create("DPropertySheet", f)
        tabs:SetPos(10, 52) tabs:SetSize(960, 598)

        -- ===== Вкладка УСТРОЙСТВА =====
        local pDev = vgui.Create("DPanel", tabs)
        pDev:SetPaintBackground(false)
        local head = vgui.Create("DLabel", pDev)
        head:SetFont("GRMCon_X") head:SetTextColor(CC.dim) head:SetPos(6, 2) head:SetSize(940, 18)
        _con.lists.devHead = head
        local dev = vgui.Create("DListView", pDev)
        dev:SetPos(0, 24) dev:SetSize(936, 520) dev:SetMultiSelect(false)
        dev:SetDataHeight(22)
        dev:AddColumn("ID"):SetFixedWidth(72)
        dev:AddColumn("Тип"):SetFixedWidth(108)
        dev:AddColumn("Статус"):SetFixedWidth(220)
        dev:AddColumn("Позиция"):SetFixedWidth(150)
        dev:AddColumn("До пульта"):SetFixedWidth(74)
        dev:AddColumn("Азим."):SetFixedWidth(52)
        dev:AddColumn("Кач."):SetFixedWidth(50)
        dev:AddColumn("Группы")
        dev.OnRowRightClick = function(_, line) deviceMenu(line) end
        dev.OnRowSelected = function(_, _, line)
            -- одиночный клик тоже открывает действия — удобнее с тачскрином-севера
        end
        _con.lists.dev = dev
        local bRef = mkBtn(pDev, "Обновить", CC.acc, 120, 30) bRef:SetPos(0, 552)
        bRef.DoClick = function() sendOp("refresh") end
        local chk = vgui.Create("DCheckBoxLabel", pDev)
        chk:SetPos(136, 556) chk:SetText("автообновление") chk:SetFont("GRMCon_X") chk:SetTextColor(CC.dim)
        chk:SetChecked(_con.auto == true) chk:SizeToContents()
        chk.OnChange = function(_, on)
            _con.auto = on == true
            timer.Remove("GRM_Con_Auto")
            if _con.auto then
                timer.Create("GRM_Con_Auto", 2, 0, function()
                    if not IsValid(_con.frame) then timer.Remove("GRM_Con_Auto") return end
                    sendOp("refresh")
                end)
            end
        end
        tabs:AddSheet(" Устройства ", pDev, "icon16/drive_network.png")

        -- ===== Вкладка ГРУППЫ =====
        local pGrp = vgui.Create("DPanel", tabs)
        pGrp:SetPaintBackground(false)
        local gl = vgui.Create("DLabel", pGrp)
        gl:SetFont("GRMCon_X") gl:SetTextColor(CC.dim) gl:SetPos(6, 2) gl:SetSize(940, 34)
        gl:SetText("Группы собираются на вкладке «Устройства» (ПКМ → «Включить в группу»). Оповещение с пульта по группе звучит только из её громкоговорителей.")
        local grp = vgui.Create("DListView", pGrp)
        grp:SetPos(0, 40) grp:SetSize(460, 500) grp:SetMultiSelect(false)
        grp:AddColumn("Группа"):SetFixedWidth(300)
        grp:AddColumn("Устройств")
        _con.lists.grp = grp
        local bDel = mkBtn(pGrp, "Удалить выбранную группу", CC.red, 240, 30) bDel:SetPos(0, 552)
        bDel.DoClick = function()
            local _, line = grp:GetSelectedLine()
            if not line or not line.grmGroup then return end
            Derma_Query("Удалить группу «" .. line.grmGroup .. "»? Устройства останутся, только сбросится их принадлежность.",
                "Группы радиосети", "Удалить", function() sendOp("group_del", { group = line.grmGroup }) end, "Отмена", function() end)
        end
        tabs:AddSheet(" Группы ", pGrp, "icon16/folder_link.png")

        -- ===== Вкладка ОПОВЕЩЕНИЕ =====
        local pAl = vgui.Create("DPanel", tabs)
        pAl:SetPaintBackground(false)
        local l1 = vgui.Create("DLabel", pAl)
        l1:SetFont("GRMCon_S") l1:SetText("Куда оповещать:") l1:SetTextColor(CC.text) l1:SetPos(10, 12) l1:SizeToContents()
        _con.combo = vgui.Create("DComboBox", pAl)
        _con.combo:SetPos(160, 8) _con.combo:SetSize(300, 26)
        _con.combo:SetValue("Весь город (все сетевые громкоговорители)")
        _con.combo:AddChoice("Весь город (все сетевые громкоговорители)", "")
        for _, g in ipairs(data.groups or {}) do
            _con.combo:AddChoice("Группа «" .. g .. "»", g)
        end
        _con.combo.OnSelect = function(_, _, _, v) _con.alertTarget = tostring(v or "") end
        _con.alertTarget = ""
        local l2 = vgui.Create("DLabel", pAl)
        l2:SetFont("GRMCon_S") l2:SetText("Текст:") l2:SetTextColor(CC.text) l2:SetPos(10, 50) l2:SizeToContents()
        _con.alertEntry = vgui.Create("DTextEntry", pAl)
        _con.alertEntry:SetPos(160, 46) _con.alertEntry:SetSize(560, 28) _con.alertEntry:SetFont("GRMCon_S")
        _con.alertEntry:SetPlaceholderText("Внимание! В секторе…")
        local bSend = mkBtn(pAl, "Оповестить", CC.yellow, 140, 30) bSend:SetPos(160, 86)
        bSend.DoClick = function()
            local t = string.Trim(tostring(_con.alertEntry:GetValue() or ""))
            if #t < 3 then return end
            sendOp("alert", { target = _con.alertTarget, text = t })
            _con.alertEntry:SetValue("")
        end
        local l3 = vgui.Create("DLabel", pAl)
        l3:SetFont("GRMCon_X") l3:SetTextColor(CC.dim) l3:SetPos(10, 130) l3:SetSize(920, 60)
        l3:SetText("Оповещение звучит ТОЛЬКО из громкоговорителей: (а) подключённых к живой сети (стойка/антенна), "
            .. "(б) не выключенных этим пультом, (в) входящих в выбранную группу (или всех — для «весь город»). "
            .. "Голосом — через режим ГРОМКАЯ СВЯЗЬ у микрофона; его цель задаётся ПКМ по микрофону на вкладке «Устройства».")
        tabs:AddSheet(" Оповещение ", pAl, "icon16/sound.png")

        -- ===== Вкладка ЖУРНАЛ =====
        local pLog = vgui.Create("DPanel", tabs)
        pLog:SetPaintBackground(false)
        local hl = vgui.Create("DLabel", pLog)
        hl:SetFont("GRMCon_X") hl:SetTextColor(CC.dim) hl:SetPos(6, 2) hl:SetSize(940, 18)
        hl:SetText("События сети: кто, что, откуда (пеленг) и с каким качеством канала. Глубина — " .. tostring(RN.LogCap) .. " записей.")
        local lg = vgui.Create("DListView", pLog)
        lg:SetPos(0, 24) lg:SetSize(936, 520) lg:SetMultiSelect(false)
        lg:SetDataHeight(20)
        lg:AddColumn("Время"):SetFixedWidth(64)
        lg:AddColumn("Событие"):SetFixedWidth(90)
        lg:AddColumn("Кто/устройство"):SetFixedWidth(170)
        lg:AddColumn("Позиция"):SetFixedWidth(140)
        lg:AddColumn("Кач."):SetFixedWidth(46)
        lg:AddColumn("Детали")
        _con.lists.log = lg
        local bLR = mkBtn(pLog, "Обновить", CC.acc, 120, 30) bLR:SetPos(0, 552)
        bLR.DoClick = function() sendOp("refresh") end
        local bLC = mkBtn(pLog, "Очистить журнал", CC.red, 160, 30) bLC:SetPos(132, 552)
        bLC.DoClick = function()
            Derma_Query("Стереть весь журнал событий радиосети?", "Журнал", "Стереть", function() sendOp("log_clear") end, "Отмена", function() end)
        end
        tabs:AddSheet(" Журнал+пеленг ", pLog, "icon16/table.png")

        fillDevices() fillGroups() fillLog()
    end

    net.Receive(NET_OPEN, function()
        local idx = net.ReadUInt(16)
        local data = net.ReadTable()
        if not istable(data) then return end
        data.idx = idx
        if IsValid(_con.frame) then
            _con.data = data
            fillDevices() fillGroups() fillLog()
            if IsValid(_con.combo) and _con.combo.grmFilled ~= data then
                _con.combo:Clear()
                _con.combo:AddChoice("Весь город (все сетевые громкоговорители)", "")
                for _, g in ipairs(data.groups or {}) do
                    _con.combo:AddChoice("Группа «" .. g .. "»", g)
                end
                _con.combo.grmFilled = data
            end
        else
            openConsoleWindow(data)
        end
    end)

    ----------------------------------------------------------------
    -- Код 87 — слой ИДЕНТИФИКАЦИИ: позывной устройства над железкой
    ----------------------------------------------------------------
    surface.CreateFont("GRMNetId_S", { font = "Roboto", size = 13, weight = 600, extended = true })
    local _idCache = {}
    timer.Create("GRM_RN_IdCache", 2, 0, function()
        local t = {}
        for class in pairs(RN.Kinds or {}) do
            for _, e in ipairs(ents.FindByClass(class)) do
                if IsValid(e) then t[#t + 1] = e end
            end
        end
        _idCache = t
    end)
local NET_ANG = Angle(0, 0, 90)
local NET_BG = Color(12, 16, 22, 210)
local NET_ID = Color(150, 210, 255)

    hook.Add("PostDrawTranslucentRenderables", "GRM_RN_NetIds", function()
        local lp = LocalPlayer()
        if not IsValid(lp) then return end
        local lpos = lp:GetPos()
        -- плашка id: угол скретчем, краски константами (§6.1.8)
        for _, e in ipairs(_idCache) do
            if IsValid(e) and e:GetPos():DistToSqr(lpos) <= 350 * 350 then
                local id = e:GetNWString("GRM_NetID", "")
                if id ~= "" then
                    local ang = e:GetAngles()
                    local maxs = e:OBBMaxs()
                    local pos = e:GetPos() + ang:Up() * ((maxs and maxs.z or 40) + 26)
                    NET_ANG.y = EyeAngles().y - 90
                    cam.Start3D2D(pos, NET_ANG, 0.055)
                        local tw = 40 + #id * 9
                        draw.RoundedBox(6, -tw, -12, tw * 2, 24, NET_BG)
                        surface.SetDrawColor(90, 170, 250, 160)
                        surface.DrawOutlinedRect(-tw, -12, tw * 2, 24, 1)
                        draw.SimpleText(id, "GRMNetId_S", 0, 0, NET_ID, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                    cam.End3D2D()
                end
            end
        end
    end)

    print("[GRM RadioNet] Клиент v" .. RN.Version .. " загружен")
end

-- Вечер-18: единый словарь slash-команд: имена живого PlayerSay-обработчика
-- вносятся во внешний реестр библиотеки (на режиме сверка идёт ДО ParseSay —
-- без регистрации команда стала бы «неизвестной»).
if GRM and GRM.Chat and GRM.Chat.RegisterExternalCommands then
    GRM.Chat.RegisterExternalCommands({ "/antenna_add", "/antenna_remove", "/consol", "/rack_add", "/rack_remove", "/rstation_add", "/rstation_remove" })
end
