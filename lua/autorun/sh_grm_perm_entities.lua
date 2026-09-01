--[[--------------------------------------------------------------------
    GRM Perm Entities v1.2.0 (Код 50/Код 89)
    «Пермы» для разворачиваемых энтити GRM: банкомат, таксофон, АТС,
    телефоны, CCTV-камера/монитор/сервер, сигнализация (сенсор/хаб/терминал/
    динамик), кейпад, RoomTap (чип/сервер/терминал), рудный узел/скупщик,
    дилер транспорта. Админ наводит прицел -> команда -> энтити
    переживает рестарт карты и cleanup-кнопку.

    Код 89 (находка 106): «все энтити всех модулей перманентно».
      Добавлены классы: grm_alarm_speaker, grm_keypad, grm_roomtap_chip,
      grm_roomtap_server, grm_roomtap_terminal, grm_ore_node, grm_ore_buyer,
      sent_vehicle_dealer. Лимит 64 -> 256.
      НЕ добавляются (у них и так авто-персистент Код 88.4, двойной
      сейв дал бы дубли): grm_server_rack, grm_antenna, grm_radio_station,
      grm_net_console, grm_loudspeaker. grm_radio/grm_broadcast_mic
      тоже автоперсистентны, оставлены здесь лишь для совместимости
      со старыми базами.
      НЕ добавляются (свой сейв карты со стоком, Код 90):
      grm_logistics_loading, grm_logistics_warehouse, grm_logistics_armory.
      НЕ добавляются (временные по смыслу): grm_item_drop, grm_money_drop,
      grm_ore_chunk (батч-дропы), grm_mobile_line (виртуальная станция),
      grm_logistics_crate (транспортный ящик).

    Хранилище: data/grm_perm_entities.json — МАССИВ записей
    {map, class, model, pos={x,y,z}, ang={p,y,r}}.
    Массив, а не карта: ловушка util.JSONToTable с числовыми
    ключами-строками тут невозможна в принципе (находка 65).
    Чтение всё равно только через jsonT() (ignoreConversions=true).

    Команды (только суперадмин; add/remove — глядя на энтити ≤256 юнитов):
      чат:     /permadd   /permremove   /permlist   /permload
      консоль: grm_perm_add  grm_perm_remove  grm_perm_list  grm_perm_load
      /permload — немедленная загрузка из файла (без рестарта); антидубль:
      на занятое место (тот же класс в радиусе 6 юнитов) второй не ставится.
    Рамки: не больше 256 пермов на карту; дедуп по классу+точке (6 юнитов);
    воскрешённые энтити заморожены (EnableMotion(false)).
----------------------------------------------------------------------]]

-- Код 108: кейпад/сканер несут в rec.data ещё и links — ручные связи
-- с FFD-дверями (sh_grm_ffdlink.lua / инструмент FFD Link); связи
-- разрешаются обратно в энтити по классу+позиции (сфера 15 юнитов).
-- Код 110: перм агрегатов кухни (плита/холодильник/горшок) — состояние
-- (лоток плиты, содержимое холодильника, посадка) едет в rec.data
-- через GRM.PermData-делегаты sh_grm_food_kitchen.lua.
local PERM_VER = "1.6.0"
GRM = GRM or {}
GRM._permEntitiesVer = PERM_VER

-- Код 105 (находка 122): перм с ДАННЫМИ экземпляра. Модули регистрируют
-- GRM.PermData.Extract[class] = fn(ent) -> таблица-данные (или nil) и
-- GRM.PermData.Apply[class] = fn(ent, data). /permadd складывает их в
-- rec.data, спавн после рестарта разворачивает обратно — кейпад
-- восстаёт со своим PIN/режимом/фракциями, FFD-дверь — рабочей дверью.
GRM.PermData = GRM.PermData or { Extract = {}, Apply = {} }
GRM.PermData.Extract = GRM.PermData.Extract or {}
GRM.PermData.Apply = GRM.PermData.Apply or {}

-- ── Цепочки делегатов (Perm Tool, П4) ───────────────────────────────
-- Раньше слот на класс был ОДИН: `Extract[cls] = fn` затирал предыдущего
-- регистранта. На prop_physics это било больно — FFD-двери (stools/
-- ffd_fading_door.lua) и перм-тул обычных пропов претендуют на один класс,
-- и «кто загрузился позже, тот и выиграл».
--
-- Решение без правки девяти существующих файлов-регистрантов: таблицы
-- Extract/Apply подменяются прокси с метатаблицей. Привычный синтаксис
-- `Extract[cls] = fn` продолжает работать, но теперь НАКАПЛИВАЕТ функции
-- в цепочку:
--   Extract[cls] -> композит: вызывает все fn, результаты МЕРЖИТ в одну
--                   таблицу (ключи верхнего уровня не пересекаются:
--                   ffd / sliding / prop / computerName / ...)
--   Apply[cls]   -> композит: вызывает все fn по очереди, каждую в pcall
-- Порядок загрузки перестаёт что-либо решать.
do
    local chains = { extract = {}, apply = {} }
    GRM.PermData._chains = chains

    -- Блок исполняется до объявления хелперов ниже по файлу и до того, как
    -- некоторые стенды успевают определить глобальные istable/isfunction —
    -- поэтому проверки типов здесь локальные и самодостаточные.
    local function istable(v) return type(v) == "table" end
    local function isstring(v) return type(v) == "string" end
    local function isfunction(v) return type(v) == "function" end

    local function composeExtract(list)
        return function(ent)
            local out = nil
            for _, fn in ipairs(list) do
                local okX, res = pcall(fn, ent)
                if okX and istable(res) then
                    out = out or {}
                    for k, v in pairs(res) do out[k] = v end
                end
            end
            return out
        end
    end

    local function composeApply(list)
        return function(ent, data)
            for _, fn in ipairs(list) do pcall(fn, ent, data) end
        end
    end

    local function mkProxy(kind, existing)
        local compose = (kind == "extract") and composeExtract or composeApply
        local proxy = setmetatable({}, {
            __newindex = function(_, class, fn)
                if not isstring(class) then return end
                if fn == nil then chains[kind][class] = nil return end
                if not isfunction(fn) then return end
                local list = chains[kind][class]
                if not list then list = {} chains[kind][class] = list end
                -- повторная регистрация той же функции не дублируется
                for _, f in ipairs(list) do if f == fn then return end end
                list[#list + 1] = fn
            end,
            __index = function(_, class)
                local list = chains[kind][class]
                if not list or #list == 0 then return nil end
                if #list == 1 then return list[1] end
                return compose(list)
            end,
            -- ipairs/pairs по прокси: отдаём классы, у которых есть цепочка
            __pairs = function(self)
                local k
                return function()
                    local v
                    k, v = next(chains[kind], k)
                    if k == nil then return nil end
                    return k, self[k]
                end
            end,
        })
        -- переносим то, что успели зарегистрировать до нас
        if istable(existing) then
            for class, fn in pairs(existing) do
                if isstring(class) and isfunction(fn) then proxy[class] = fn end
            end
        end
        return proxy
    end

    GRM.PermData.Extract = mkProxy("extract", GRM.PermData.Extract)
    GRM.PermData.Apply   = mkProxy("apply", GRM.PermData.Apply)

    -- Явные регистраторы (предпочтительны для нового кода)
    GRM.PermData.AddExtract = function(class, fn) GRM.PermData.Extract[class] = fn end
    GRM.PermData.AddApply   = function(class, fn) GRM.PermData.Apply[class] = fn end
end

if SERVER then
    local PERM_FILE  = "grm_perm_entities.json"
    local PERM_QUOTA_FACTION = 32 -- записей на фракцию
    local PERM_QUOTA_PLAYER  = 8  -- записей на персонажа (если разрешено конваром)

    -- Обычным игрокам закрепление по умолчанию запрещено: иначе карта
    -- за неделю зарастает вечными пропами, которые не чистит cleanup.
    if CreateConVar then
        CreateConVar("grm_perm_players", "0", FCVAR_ARCHIVE,
            "Разрешить обычным игрокам закреплять свои объекты (0/1)")
    end
    local PERM_MAX   = 256 -- Код 89: лимит пермов на карту (было 64)
    local PERM_RANGE = 6   -- юнитов: дедуп при добавлении / поиск при снятии

    -- классы, которым разрешён перм (расширяется здесь)
    local PERM_CLASSES = {
        grm_bank_terminal  = true,
        grm_payphone       = true,
        grm_pbx_station    = true,
        grm_phone_terminal = true,
        grm_phone_wiretap  = true,
        grm_phone          = true,
        -- ВАЖНО: CCTV НЕ здесь! У него своя система сохранения (CCTV.SavePermanent)
        grm_wardrobe       = true,
        -- Broadcast-классы автоперсистентны (Код 88.4) — тут лишь для совместимости со старыми базами
        grm_radio          = true,
        grm_broadcast_mic  = true,
        grm_board          = true,
        -- Биржа труда (Код 77) — модуль и сам автоперсистентен, классы тут для /permadd-совместимости
        grm_jobcenter      = true,
        grm_depot          = true,
        grm_duty_npc       = true,
        -- Охранная сигнализация (Код 62/Код 89)
        grm_alarm_sensor   = true,
        grm_alarm_hub      = true,
        grm_alarm_terminal = true,
        grm_alarm_speaker  = true, -- Код 89
        -- Кейпад прохода (Код 70/Код 89) и сканер фракций (Код 107)
        grm_keypad         = true,
        grm_scanner        = true,
        -- Кухня «GrandEats» (Код 110): плита, холодильник, горшок
        grm_food_stove     = true,
        grm_food_fridge    = true,
        grm_food_planter   = true,
        -- Код 105: prop_physics допускаем именно ради FFD-дверей
        -- (владелец пермит двери; рабочее состояние восстанавливает
        -- GRM.PermData.Apply["prop_physics"] из стула FFD Fading Door)
        prop_physics       = true,
        -- RoomTap: комнатная прослушка (Код 72/Код 89)
        grm_roomtap_chip     = true,
        grm_roomtap_server   = true,
        grm_roomtap_terminal = true,
        -- GRM Vendor имеет собственный data/grm_vendors/<map>.json.
        -- Здесь намеренно НЕ регистрируется: два механизма создавали дубли.
        -- Денежный принтер (Код 115)
        grm_money_printer    = true,
        -- Банковская система (находка 178): хранилище, компьютер, печатный станок, терминал
        grm_bank_vault          = true,
        grm_bank_computer       = true,
        grm_money_press         = true,
        grm_money_press_terminal = true,
        -- Служебные компьютеры ведомств (GRM Служебное оборудование)
        grm_doc_computer        = true,
        grm_comp_police          = true,
        grm_comp_military_police = true,
        grm_comp_security        = true,
        grm_comp_military        = true,
        grm_comp_traffic         = true,
        grm_comp_medical         = true,
        grm_comp_education       = true,
        grm_comp_fire            = true,
        grm_comp_cityhall        = true,
        grm_comp_court           = true,
        grm_comp_public          = true,
        -- Отмывщик денег / ивент «Ограбление» (находка 179e)
        grm_money_launderer     = true,
        -- Лаборатории (Код 120)
        grm_narc_lab         = true,
        grm_med_lab          = true,
        -- GRM Logistics: склады, шкафы, точки погрузки (Код 112)
        grm_logistics_loading   = true,
        grm_logistics_warehouse = true,
        grm_logistics_armory    = true,
        grm_logistics_crate     = true,
        grm_weapon_rack         = true,
        -- Домашний шкаф (жильё, фаза 2): мебель квартиры, обязан пережить
        -- рестарт вместе с содержимым (вещи хранятся отдельным файлом).
        grm_home_locker         = true,
        -- Домашняя кровать: мебель квартиры и точка входа, обязана
        -- пережить рестарт вместе с жильём.
        grm_home_bed            = true,
        -- ВАЖНО: CCTV (grm_cctv_camera/monitor/server) НЕ в PERM_CLASSES!
        -- У CCTV своя система сохранения через CCTV.SavePermanent/LoadPermanent
        -- (grm_cctv/<map>.json). Добавление сюда создаёт дубликаты.
        -- Рудная ветка (Код 89)
        grm_ore_node       = true,
        grm_ore_buyer      = true,
        -- Терминал контроля чипов (находка 169)
        grm_chip_terminal  = true,
        grm_fuel_pump      = true,
        -- sent_vehicle_dealer имеет собственный GRM VehicleDealer v3 persistence.
        -- Здесь намеренно отсутствует, чтобы не создавать второго NPC.
    }

    -- ── Чёрный список: классы, которые пермить НЕЛЬЗЯ ───────
    -- Раньше отказ был молчаливым («класс не в PERM_CLASSES»), и админ
    -- не понимал, это баг или так задумано. Теперь у каждого отказа есть
    -- человеческая причина, она уходит в чат.
    local PERM_BLACKLIST = {
        -- Собственная система сохранения — двойной перм даёт дубли объектов
        grm_cctv_camera   = "у CCTV собственное сохранение (CCTV.SavePermanent)",
        grm_cctv_monitor  = "у CCTV собственное сохранение (CCTV.SavePermanent)",
        grm_cctv_server   = "у CCTV собственное сохранение (CCTV.SavePermanent)",
        grm_vendor        = "у торговца свой сейв (data/grm_vendors/<map>.json)",
        sent_vehicle_dealer = "у дилера транспорта свой сейв (VehicleDealer v3)",
        -- Автоперсистентные модули (Код 88.4) — сохраняются сами
        grm_server_rack   = "модуль сохраняется сам (автоперсистент)",
        grm_antenna       = "модуль сохраняется сам (автоперсистент)",
        grm_radio_station = "модуль сохраняется сам (автоперсистент)",
        grm_net_console   = "модуль сохраняется сам (автоперсистент)",
        grm_loudspeaker   = "модуль сохраняется сам (автоперсистент)",
        -- Временные по смыслу: перм превратил бы мусор в вечный мусор
        grm_item_drop     = "временный объект (выброшенный предмет)",
        grm_money_drop    = "временный объект (выброшенные деньги)",
        grm_ore_chunk     = "временный объект (добытая руда)",
        grm_mobile_line   = "виртуальная станция, не физический объект",
    }

    -- JSON только без конверсии ключей (находка 65)
    local function jsonT(txt)
        local ok, t = pcall(util.JSONToTable, txt, false, true)
        return (ok and istable(t)) and t or nil
    end

    local function tell(ply, msg, r, g, b)
        if IsValid(ply) and ply:IsPlayer() then
            if GRM.Notify then GRM.Notify(ply, msg, r or 100, g or 220, b or 100) return end
            ply:PrintMessage(HUD_PRINTTALK, tostring(msg))
        else
            print("[GRM Perm] " .. tostring(msg))
        end
    end

    -- ── Хранилище ───────────────────────────────────────────
    local function loadList()
        if not file.Exists(PERM_FILE, "DATA") then return {} end
        local txt = file.Read(PERM_FILE, "DATA") or ""
        if string.Trim(txt) == "" or string.Trim(txt) == "[]" then return {} end
        local t = jsonT(txt)
        if not istable(t) then
            local q = "grm_perm_entities_corrupt_" .. os.time() .. ".txt"
            file.Write(q, txt)
            print("[GRM Perm][!] База пермов битая — копия в data/" .. q .. ", работаем с пустой")
            return {}
        end
        -- в базе только массив записей-таблиц
        local out = {}
        for _, rec in ipairs(t) do
            if istable(rec) and isstring(rec.map) and isstring(rec.class) then
                rec.pos = istable(rec.pos) and rec.pos or { x = 0, y = 0, z = 0 }
                rec.ang = istable(rec.ang) and rec.ang or { p = 0, y = 0, r = 0 }
                out[#out + 1] = rec
            end
        end
        return out
    end

    -- ── Формат v2: uid, владение, аудит ─────────────────────
    local uidCounter = 0
    local function newUID()
        uidCounter = uidCounter + 1
        return ("pm_%x_%x_%x"):format(os.time(), uidCounter, math.random(0, 0xFFFF))
    end

    -- Миграция v1 -> v2. Идемпотентна: если у всех записей есть uid, ничего
    -- не делает. Формат файла НЕ меняется (тот же плоский массив) —
    -- добавляются только поля записи, поэтому старый loadList его читает.
    --
    -- ownerKind = "server" для всех старых записей — это РОВНО сегодняшнее
    -- поведение (spawnAll звал MarkServerEntity для всего подряд), поэтому
    -- миграция не меняет поведение ни одного существующего перма.
    local migrationDone = false
    local function migrateList(list)
        if not istable(list) then return list, false end
        local need = false
        for _, rec in ipairs(list) do
            if istable(rec) and not isstring(rec.uid) then need = true break end
        end
        if not need then return list, false end

        -- Бэкап ДО правок, с проверкой чтением. Не удался — миграцию отменяем
        -- и работаем со старым форматом: терять боевую базу нельзя.
        local bakName = ("grm_perm_entities.bak.%d.json"):format(os.time())
        local okJ, raw = pcall(util.TableToJSON, list, true)
        if not okJ or not isstring(raw) or raw == "" then
            print("[GRM Perm][!] МИГРАЦИЯ ОТМЕНЕНА: не удалось сериализовать бэкап")
            return list, false
        end
        file.Write(bakName, raw)
        local chk = file.Read(bakName, "DATA")
        if chk ~= raw then
            print("[GRM Perm][!] МИГРАЦИЯ ОТМЕНЕНА: бэкап не подтвердился (" .. bakName .. ")")
            return list, false
        end

        local n = 0
        for _, rec in ipairs(list) do
            if istable(rec) and not isstring(rec.uid) then
                rec.uid       = newUID()
                rec.ownerKind = isstring(rec.ownerKind) and rec.ownerKind or "server"
                rec.owner     = isstring(rec.owner) and rec.owner or ""
                rec.ownerName = isstring(rec.ownerName) and rec.ownerName or ""
                rec.faction   = isstring(rec.faction) and rec.faction or ""
                if rec.freeze == nil then rec.freeze = true end
                rec.label     = isstring(rec.label) and rec.label or ""
                rec.by        = isstring(rec.by) and rec.by or ""
                rec.byName    = isstring(rec.byName) and rec.byName or "migration"
                rec.at        = tonumber(rec.at) or os.time()
                n = n + 1
            end
        end
        print(("[GRM Perm] МИГРАЦИЯ v1->v2: обновлено записей: %d, бэкап: data/%s")
            :format(n, bakName))
        return list, true
    end

    -- Единая точка чтения: подтягивает миграцию при первом обращении
    local function loadDB()
        local list = loadList()
        if not migrationDone then
            local migrated, changed = migrateList(list)
            list = migrated
            migrationDone = true
            if changed then
                local okJ, txt = pcall(util.TableToJSON, list, true)
                if okJ and isstring(txt) and txt ~= "" then
                    file.Write(PERM_FILE, txt)
                    if file.Read(PERM_FILE, "DATA") ~= txt then
                        print("[GRM Perm][!] Миграция: запись основной базы не подтвердилась")
                    end
                end
            end
        end
        return list
    end

    local function saveList(list)
        local okJ, txt = pcall(util.TableToJSON, list, true)
        if not okJ or not isstring(txt) or txt == "" then
            print("[GRM Perm][!] SAVE: сериализация не удалась — запись пропущена")
            return false
        end
        file.Write(PERM_FILE, txt)
        local chk = file.Read(PERM_FILE, "DATA")
        if chk ~= txt then
            print(("[GRM Perm][!] ЗАПИСЬ НЕ ПОДТВЕРДИЛАСЬ: сохранено %d байт, на диске %s")
                :format(#txt, (isstring(chk) and (tostring(#chk) .. " байт") or "файл пропал")))
            return false
        end
        return true
    end

    local function sameSpot(a, b, classA, classB)
        if classA ~= classB then return false end
        local dx = (tonumber(a.x) or 0) - (tonumber(b.x) or 0)
        local dy = (tonumber(a.y) or 0) - (tonumber(b.y) or 0)
        local dz = (tonumber(a.z) or 0) - (tonumber(b.z) or 0)
        return (dx * dx + dy * dy + dz * dz) <= (PERM_RANGE * PERM_RANGE)
    end

    -- ── Владение, права, квоты ──────────────────────────────
    -- Ключ персонажа — канон ядра (§5.2.6). Локальная копия убрана: копия канона с лишним pcall вокруг своего же кода.
    local charKeyOf = GRM.CharKey

    local function rpNameOf(ply)
        if not IsValid(ply) then return "" end
        local n = ply.GetNWString and ply:GetNWString("GRM_RPName", "") or ""
        if n == "" and ply.Nick then n = ply:Nick() end
        return tostring(n or "")
    end

    local function factionOf(ply)
        if not IsValid(ply) then return "" end
        return tostring(ply.GetNWString and ply:GetNWString("GRM_Faction", "") or "")
    end

    -- Право «закреплять объекты»: суперадмин, либо роль с perm_manage,
    -- либо лидер фракции (совместимо с логикой grm_service_tool).
    local function hasFactionPermRight(ply)
        if not IsValid(ply) then return false end
        if GRM.FactionPerms and GRM.FactionPerms.PlayerHasPermission then
            local okP, res = pcall(GRM.FactionPerms.PlayerHasPermission, ply, "perm_manage")
            if okP and res then return true end
        end
        local fac = factionOf(ply)
        if fac ~= "" and _G.FactionsAPI and _G.FactionsAPI.IsLeader then
            local okL, res = pcall(_G.FactionsAPI.IsLeader, ply, fac)
            if okL and res then return true end
        end
        return false
    end

    local function playersAllowed()
        local cv = GetConVar and GetConVar("grm_perm_players")
        return cv and cv:GetInt() == 1 or false
    end

    local function countBy(list, map, field, value)
        local n = 0
        for _, rec in ipairs(list) do
            if rec.map == map and tostring(rec[field] or "") == value then n = n + 1 end
        end
        return n
    end

    -- Может ли игрок управлять пермами вообще / этой конкретной записью
    local function canManageRec(ply, rec)
        if not IsValid(ply) then return false, "нет игрока" end
        if ply.IsSuperAdmin and ply:IsSuperAdmin() then return true end
        if not istable(rec) then
            -- общий вопрос «может ли пермить хоть что-то»
            if hasFactionPermRight(ply) then return true end
            if playersAllowed() then return true end
            return false, "нужны права суперадмина или руководства фракции"
        end
        local kind = tostring(rec.ownerKind or "server")
        if kind == "faction" then
            local fac = factionOf(ply)
            if fac ~= "" and fac == tostring(rec.faction or "") and hasFactionPermRight(ply) then
                return true
            end
            return false, "объект закреплён за фракцией «" .. tostring(rec.faction or "?") .. "»"
        end
        if kind == "character" then
            if tostring(rec.owner or "") == charKeyOf(ply) then return true end
            return false, "объект закреплён за другим персонажем"
        end
        return false, "объект закреплён как серверное оборудование"
    end

    local function aimEntity(ply)
        if not IsValid(ply) then return nil end
        local tr = util.TraceLine({
            start  = ply:GetShootPos(),
            endpos = ply:GetShootPos() + ply:GetAimVector() * 256,
            filter = ply,
        })
        return tr and tr.Entity or nil
    end

    -- ── Восстановление на карте ─────────────────────────────
    -- Антидубль: не ставим энтити, если того же класса уже стоит на месте
    -- (важно для ручной /permload поверх живой карты)
    local function isOccupied(class, pos)
        local center = Vector(tonumber(pos.x) or 0, tonumber(pos.y) or 0, tonumber(pos.z) or 0)
        for _, ent in ipairs(ents.FindInSphere(center, PERM_RANGE)) do
            if IsValid(ent) and tostring(ent:GetClass() or "") == class then return true end
        end
        return false
    end

    -- Возвращает: сколько заспавнено, сколько пропущено (уже стоят)
    local function spawnAll(reason, onlyClass)
        local map = game.GetMap()
        onlyClass = isstring(onlyClass) and onlyClass ~= "" and onlyClass or nil
        local done, skipped = 0, 0
        for _, rec in ipairs(loadDB()) do
            if rec.map == map and PERM_CLASSES[rec.class] and (not onlyClass or rec.class == onlyClass) then
                if isOccupied(rec.class, rec.pos) then
                    skipped = skipped + 1
                else
                    local ent = ents.Create(rec.class)
                    if IsValid(ent) then
                        if isstring(rec.model) and rec.model ~= "" then
                            pcall(function() ent:SetModel(rec.model) end)
                        end
                        ent:SetPos(Vector(tonumber(rec.pos.x) or 0, tonumber(rec.pos.y) or 0, tonumber(rec.pos.z) or 0))
                        ent:SetAngles(Angle(tonumber(rec.ang.p) or 0, tonumber(rec.ang.y) or 0, tonumber(rec.ang.r) or 0))
                        ent:Spawn()
                        ent:Activate()
                        -- Владение восстанавливается по записи (П1). Раньше
                        -- ЛЮБОЙ перм безусловно становился «серверным», и
                        -- запермленная дверь после рестарта уходила у
                        -- владельца: PP.CanInteract проверяет IsServerEntity
                        -- раньше IsOwner.
                        local kind = tostring(rec.ownerKind or "server")
                        ent._grmPerm = true
                        ent._grmPermKind = kind
                        ent._grmPermUID = rec.uid
                        if kind == "character" and isstring(rec.owner) and rec.owner ~= "" then
                            ent.GRM_PropOwnerCharacterKey = rec.owner
                            ent.GRM_EntityOwnerCharacterKey = rec.owner
                            ent.GRM_EntityOwnerName = tostring(rec.ownerName or "")
                            pcall(function()
                                ent:SetNWString("GRM_PropOwnerCharacterKey", rec.owner)
                                ent:SetNWString("GRM_EntityOwnerCharacterKey", rec.owner)
                                ent:SetNWString("GRM_PropOwnerName", tostring(rec.ownerName or ""))
                                ent:SetNWString("GRM_EntityOwnerName", tostring(rec.ownerName or ""))
                            end)
                        elseif kind == "faction" then
                            ent.GRM_PermFaction = tostring(rec.faction or "")
                            pcall(function()
                                ent:SetNWString("GRM_PermFaction", tostring(rec.faction or ""))
                                ent:SetNWString("GRM_EntityOwnerName", tostring(rec.faction or ""))
                            end)
                        elseif GRM.PropProtect and GRM.PropProtect.MarkServerEntity then
                            GRM.PropProtect.MarkServerEntity(ent)
                            ent._grmPermKind = "server"
                        end
                        pcall(function()
                            ent:SetNWBool("GRM_IsPerm", true)
                            ent:SetNWString("GRM_PermKind", ent._grmPermKind or "server")
                        end)
                        -- freeze=false — объект остаётся подвижным (тележки, качели)
                        if rec.freeze ~= false then
                            local ph = ent:GetPhysicsObject()
                            if IsValid(ph) then ph:EnableMotion(false) end -- перм не катается по карте
                        end
                        -- Код 105: данные экземпляра обратно (PIN кейпада,
                        -- конфиг FFD-двери и т.п.) — после Spawn, чтобы
                        -- NetworkVar'ы уже существовали
                        local applyFn = GRM.PermData and GRM.PermData.Apply and GRM.PermData.Apply[rec.class]
                        if istable(rec.data) and applyFn then
                            pcall(applyFn, ent, rec.data)
                        end
                        -- Модули (сигнализация, банк, электроника) доподключают
                        -- воскрешённый объект к своим реестрам
                        hook.Run("GRM_PermRestored", ent, rec)
                        done = done + 1
                    else
                        print("[GRM Perm][!] Не удалось создать класс " .. tostring(rec.class) .. " — запись пропущена")
                    end
                end
            end
        end
        if GRM.FFDLink and GRM.FFDLink.RefreshAllControllers then
            GRM.FFDLink.RefreshAllControllers()
        end
        print(("[GRM Perm] восстановлено перм-энтити на карте %s: %d, уже на месте: %d (%s)")
            :format(tostring(map), done, skipped, tostring(reason or "?")))
        return done, skipped
    end
    -- Спавн закреплённого оборудования — самая тяжёлая стартовая операция
    -- (создание десятков entity). Отдаём планировщику с приоритетом early:
    -- оборудование обязано стоять до входа игроков, но не обязано появиться
    -- в один тик со всеми остальными загрузками.
    if GRM.Boot and GRM.Boot.Task then
        GRM.Boot.Task("perm.entities", "early", function() spawnAll("GRM.Boot") end,
            { label = "Перм-энтити: спавн оборудования карты" })
    else
        hook.Add("InitPostEntity", "GRM_PermEntities_Spawn", function()
            timer.Simple(1, function() spawnAll("InitPostEntity") end)
        end)
    end
    hook.Add("PostCleanupMap", "GRM_PermEntities_Cleanup", function()
        timer.Simple(0.5, function() spawnAll("PostCleanupMap") end)
    end)

    -- ── Действия ────────────────────────────────────────────
    local function countForMap(list, map)
        local n = 0
        for _, rec in ipairs(list) do if rec.map == map then n = n + 1 end end
        return n
    end

    local function addPerm(ply)
        local ent = aimEntity(ply)
        if not IsValid(ent) then tell(ply, "Наведи прицел на энтити (до 256 юнитов).", 255, 200, 80) return end
        local class = tostring(ent:GetClass() or "")
        local external, backend
        if GRM.Persistence and GRM.Persistence.Resolve then external, backend = GRM.Persistence.Resolve(ent) end
        if external and backend ~= "perm" then
            local ok, result = GRM.Persistence.Call("Save", ent, ply)
            if ok then
                ent:SetNWBool("GRM_IsPerm", true); ent:SetNWString("GRM_PermKind", "external")
                tell(ply, "[ПЕРМ] Объект сохранён backend «" .. tostring(backend) .. "»: " .. tostring(result or "ok") .. ". Двойной перм не создан.", 100, 220, 100)
            else
                tell(ply, "[ПЕРМ] Backend «" .. tostring(backend) .. "» не сохранил объект: " .. tostring(result), 255, 120, 120)
            end
            return
        end
        if not PERM_CLASSES[class] then
            tell(ply, "Класс [" .. class .. "] нельзя пермить (не GRM-разворачиваемое).", 255, 120, 120)
            return
        end
        local list = loadDB()
        local map = game.GetMap()
        if countForMap(list, map) >= PERM_MAX then
            tell(ply, "Лимит пермов на карту: " .. PERM_MAX .. ".", 255, 120, 120)
            return
        end
        local pos = ent:GetPos()
        local np = { x = pos.x, y = pos.y, z = pos.z }
        for _, rec in ipairs(list) do
            if rec.map == map and sameSpot(rec.pos, np, rec.class, class) then
                tell(ply, "Этот " .. class .. " уже в пермах.", 255, 200, 80)
                return
            end
        end
        local ang = ent:GetAngles()
        local model = ""
        pcall(function() model = tostring(ent:GetModel() or "") end)
        local rec = {
            map = map, class = class, model = model,
            pos = np,
            ang = { p = ang.p, y = ang.y, r = ang.r },
            uid = newUID(), ownerKind = "server", owner = "", ownerName = "",
            faction = "", freeze = true, label = "",
            by = tostring(ply:SteamID64() or ""), byName = rpNameOf(ply), at = os.time(),
        }
        -- Код 105: данные экземпляра (PIN кейпада, конфиг двери и т.п.)
        local extractFn = GRM.PermData and GRM.PermData.Extract and GRM.PermData.Extract[class]
        if extractFn then
            local okX, data = pcall(extractFn, ent)
            if okX and istable(data) then rec.data = data end
        end
        list[#list + 1] = rec
        if saveList(list) then
            ent._grmPerm = true
            ent._grmPermKind = "server"
            ent._grmPermUID = rec.uid
            pcall(function()
                ent:SetNWBool("GRM_IsPerm", true)
                ent:SetNWString("GRM_PermKind", "server")
            end)
            if GRM.PropProtect and GRM.PropProtect.MarkServerEntity then
                GRM.PropProtect.MarkServerEntity(ent)
            end
            hook.Run("GRM_PermAdded", ent, rec, ply)
            tell(ply, "[ПЕРМ] " .. class .. " закреплён на карте. Переживёт рестарт и cleanup.", 100, 220, 100)
            print(("[GRM Perm] %s (%s) закрепил %s @ %d %d %d"):format(ply:Nick(), ply:SteamID64() or "?", class, np.x, np.y, np.z))
        else
            tell(ply, "[ПЕРМ] Ошибка записи — смотри консоль сервера.", 255, 120, 120)
        end
    end

    local function removePerm(ply)
        local ent = aimEntity(ply)
        if not IsValid(ent) then tell(ply, "Наведи прицел на перм-энтити.", 255, 200, 80) return end
        local class = tostring(ent:GetClass() or "")
        local external, backend
        if GRM.Persistence and GRM.Persistence.Resolve then external, backend = GRM.Persistence.Resolve(ent) end
        if external and backend ~= "perm" then
            local ok, result = GRM.Persistence.Call("Remove", ent, ply)
            if ok then ent:Remove(); tell(ply, "[ПЕРМ] Объект удалён через backend «" .. tostring(backend) .. "» и снят с карты.", 235, 180, 60)
            else tell(ply, "[ПЕРМ] Backend «" .. tostring(backend) .. "» не подтвердил удаление: " .. tostring(result), 255, 200, 80) end
            return
        end
        local list = loadDB()
        local map = game.GetMap()
        local pos = ent:GetPos()
        local np = { x = pos.x, y = pos.y, z = pos.z }
        local found = false
        -- Находка 179e: ищем запись по классу + ближайшей позиции (даже если
        -- сущность чуть сдвинули физганом — запись всё равно снимется)
        local bestRec, bestDist = nil, math.huge
        for i, rec in ipairs(list) do
            if rec.map == map and rec.class == class then
                local dx = (tonumber(rec.pos and rec.pos.x) or 0) - np.x
                local dy = (tonumber(rec.pos and rec.pos.y) or 0) - np.y
                local dz = (tonumber(rec.pos and rec.pos.z) or 0) - np.z
                local d2 = dx * dx + dy * dy + dz * dz
                if d2 <= (PERM_RANGE * PERM_RANGE) and d2 < bestDist then
                    bestRec, bestDist = i, d2
                end
            end
        end
        if bestRec then
            table.remove(list, bestRec)
            saveList(list)
            ent:Remove()
            found = true
            tell(ply, "[ПЕРМ] " .. class .. " снят с карты (и из базы).", 235, 180, 60)
            print(("[GRM Perm] %s снял перм %s @ %d %d %d"):format(ply:Nick(), class, np.x, np.y, np.z))
        end
        if not found then
            tell(ply, "В радиусе " .. PERM_RANGE .. " юнитов перм-записи для этого энтити нет.", 255, 200, 80)
        end
    end

    -- Находка 179d: автообновление перм-записи при изменении состояния
    -- сущности (HeldCash хранилища, буфер/скорость станка и т.п.).
    -- /permadd фиксирует состояние ОДИН раз — без этого после загрузки
    -- денег в хранилище запись остаётся со старым (0) значением.
    GRM.PermData.UpdateEntry = function(ent)
        if not IsValid(ent) then return false end
        local class = tostring(ent:GetClass() or "")
        if not PERM_CLASSES[class] then return false end
        local extractFn = GRM.PermData and GRM.PermData.Extract and GRM.PermData.Extract[class]
        if not extractFn then return false end
        local idx = ent:EntIndex()
        -- дебаунс: частые вызовы (подбор паллет) пишут файл не каждый раз
        if ent._grmPermSaveAt and CurTime() < ent._grmPermSaveAt then return false end
        ent._grmPermSaveAt = CurTime() + 1.5
        timer.Simple(1.5, function()
            if not IsValid(ent) then return end
            local list = loadDB()
            local map = game.GetMap()
            local pos = ent:GetPos()
            local np = { x = pos.x, y = pos.y, z = pos.z }
            for _, rec in ipairs(list) do
                if rec.map == map and rec.class == class and sameSpot(rec.pos, np, rec.class, class) then
                    local okX, data = pcall(extractFn, ent)
                    if okX and istable(data) then
                        rec.data = data
                        saveList(list)
                    end
                    break
                end
            end
        end)
        return true
    end

    -- Находка 179r: «СОХРАНИТЬ НАСТРОЙКИ» отмывщика (и любых сущностей)
    -- молча теряло настройки, если перм-записи ещё не было: UpdateEntry
    -- no-op, и после рестарта — дефолты. Upsert: запись есть → обновляет
    -- data (как UpdateEntry), нет → создаёт (как /permadd, но без прицела).
    -- Возвращает: "added" / "updated" / "limit" / "invalid" / "noclass" / "savefail".
    GRM.PermData.Upsert = function(ent)
        if not IsValid(ent) then return "invalid" end
        local class = tostring(ent:GetClass() or "")
        if not PERM_CLASSES[class] then return "noclass" end
        local extractFn = GRM.PermData and GRM.PermData.Extract and GRM.PermData.Extract[class]
        local map = game.GetMap()
        local pos = ent:GetPos()
        local np = { x = pos.x, y = pos.y, z = pos.z }
        local list = loadDB()
        -- запись уже есть на месте — обновляем данные экземпляра
        for _, rec in ipairs(list) do
            if rec.map == map and rec.class == class and sameSpot(rec.pos, np, rec.class, class) then
                if extractFn then
                    local okX, data = pcall(extractFn, ent)
                    if okX and istable(data) then rec.data = data end
                end
                saveList(list)
                return "updated"
            end
        end
        -- записи нет — создаём (лимит как в /permadd)
        if countForMap(list, map) >= PERM_MAX then return "limit" end
        local ang = ent:GetAngles()
        local model = ""
        pcall(function() model = tostring(ent:GetModel() or "") end)
        local rec = {
            map = map, class = class, model = model,
            pos = np,
            ang = { p = ang.p, y = ang.y, r = ang.r },
            uid = newUID(), ownerKind = "server", owner = "", ownerName = "",
            faction = "", freeze = true, label = "",
            by = "", byName = "upsert", at = os.time(),
        }
        if extractFn then
            local okX, data = pcall(extractFn, ent)
            if okX and istable(data) then rec.data = data end
        end
        list[#list + 1] = rec
        if saveList(list) then
            ent._grmPerm = true
            ent._grmPermKind = "server"
            ent._grmPermUID = rec.uid
            print(("[GRM Perm] Upsert: создана запись %s @ %d %d %d"):format(class, np.x, np.y, np.z))
            return "added"
        end
        return "savefail"
    end

    -- ══════════════════════════════════════════════════════════
    --  ПУБЛИЧНЫЙ API GRM.Perm (задача 9, Д17)
    --  grm_service_tool.lua:156,210 уже вызывает GRM.Perm.Add(ply, ent)
    --  и GRM.Perm.Remove(ply, ent) — сигнатуры подобраны под них, чтобы
    --  галочка «сделать перманентным» заработала без правки того файла.
    -- ══════════════════════════════════════════════════════════
    GRM.Perm = GRM.Perm or {}
    local P = GRM.Perm

    P.MaxPerMap     = PERM_MAX
    P.QuotaFaction  = PERM_QUOTA_FACTION
    P.QuotaPlayer   = PERM_QUOTA_PLAYER
    P.MatchRange    = PERM_RANGE

    function P.Classes() return PERM_CLASSES end
    function P.Blacklist() return PERM_BLACKLIST end

    -- Модули регистрируют свои классы сами, без правки этого файла
    function P.RegisterClass(class, allowed)
        if not isstring(class) or class == "" then return false end
        PERM_CLASSES[class] = (allowed ~= false)
        return true
    end

    -- Можно ли пермить этот класс. Возвращает: ok, причина отказа
    function P.IsPermable(ent)
        if not IsValid(ent) then return false, "объект не найден" end
        local class = tostring(ent:GetClass() or "")
        local external, backend
        if GRM.Persistence and GRM.Persistence.Resolve then external, backend = GRM.Persistence.Resolve(ent) end
        if external and backend ~= "perm" then return true, "собственный backend: " .. tostring(backend) end
        if PERM_BLACKLIST[class] then return false, PERM_BLACKLIST[class] end
        if not PERM_CLASSES[class] then
            return false, "класс «" .. class .. "» не разрешён для закрепления"
        end
        return true
    end

    function P.CanManage(ply, ent)
        local rec = nil
        if IsValid(ent) then rec = P.Info(ent) end
        return canManageRec(ply, rec)
    end

    -- Поиск записи по объекту: сначала по uid (надёжно), потом по
    -- классу+позиции (для записей до миграции и после ручного сдвига)
    local function findRec(list, ent)
        if not IsValid(ent) then return nil end
        local map = game.GetMap()
        local class = tostring(ent:GetClass() or "")
        local uid = ent._grmPermUID
        if isstring(uid) and uid ~= "" then
            for i, rec in ipairs(list) do
                if rec.uid == uid then return i, rec end
            end
        end
        local pos = ent:GetPos()
        local np = { x = pos.x, y = pos.y, z = pos.z }
        local bestI, bestRec, bestD = nil, nil, math.huge
        for i, rec in ipairs(list) do
            if rec.map == map and rec.class == class then
                local dx = (tonumber(rec.pos and rec.pos.x) or 0) - np.x
                local dy = (tonumber(rec.pos and rec.pos.y) or 0) - np.y
                local dz = (tonumber(rec.pos and rec.pos.z) or 0) - np.z
                local d2 = dx * dx + dy * dy + dz * dz
                if d2 <= (PERM_RANGE * PERM_RANGE) and d2 < bestD then
                    bestI, bestRec, bestD = i, rec, d2
                end
            end
        end
        return bestI, bestRec
    end

    function P.IsPerm(ent)
        if not IsValid(ent) then return false end
        local external, backend
        if GRM.Persistence and GRM.Persistence.Resolve then external, backend = GRM.Persistence.Resolve(ent) end
        if external and backend ~= "perm" then
            local info = GRM.Persistence.Inspect(ent)
            return istable(info) and info.persistent == true
        end
        if ent._grmPerm then return true end
        local _, rec = findRec(loadDB(), ent)
        return rec ~= nil
    end

    function P.Info(ent)
        if not IsValid(ent) then return nil end
        local external, backend
        if GRM.Persistence and GRM.Persistence.Resolve then external, backend = GRM.Persistence.Resolve(ent) end
        if external and backend ~= "perm" then
            local info = GRM.Persistence.Inspect(ent)
            if not (istable(info) and info.persistent == true) then return nil end
            info.class = info.class or ent:GetClass()
            info.ownerKind = info.ownerKind or "server"
            info.external = true
            info.freeze = info.freeze ~= false
            info.byName = info.byName or ("GRM " .. tostring(backend))
            return info
        end
        local _, rec = findRec(loadDB(), ent)
        if rec then rec.backend = rec.backend or "perm" end
        return rec
    end

    if GRM.Persistence and GRM.Persistence.Register then
        GRM.Persistence.Register("perm", {
            Priority = 10,
            OwnsClass = function(class)
                class = tostring(class or "")
                return class ~= "grm_vendor" and PERM_CLASSES[class] == true
            end,
            Save = function(ent, ply, opts) return P.Add(ply, ent, opts) end,
            Remove = function(ent, ply, alsoDelete) return P.Remove(ply, ent, alsoDelete) end,
            Reload = function() return spawnAll("persistence_adapter") end,
            Inspect = function(ent) return P.Info(ent) or { class = IsValid(ent) and ent:GetClass() or "" } end,
        })
    end

    function P.ListForMap(map)
        map = isstring(map) and map or game.GetMap()
        local out = {}
        for _, rec in ipairs(loadDB()) do
            if rec.map == map then out[#out + 1] = rec end
        end
        return out
    end

    -- Точечная загрузка одного класса использует ту же perm-базу и ту же
    -- защиту от дублей. Модулям не требуется заводить второй persistence backend.
    function P.LoadClass(class, reason)
        class = tostring(class or "")
        if class == "" or not PERM_CLASSES[class] then return false, "класс не зарегистрирован" end
        local spawned, skipped = spawnAll(reason or ("ручная загрузка " .. class), class)
        return true, { spawned = spawned, skipped = skipped }
    end

    -- Пометить живой объект как перм (общая часть Add/spawnAll)
    local function markEnt(ent, rec)
        ent._grmPerm = true
        ent._grmPermKind = tostring(rec.ownerKind or "server")
        ent._grmPermUID = rec.uid
        pcall(function()
            ent:SetNWBool("GRM_IsPerm", true)
            ent:SetNWString("GRM_PermKind", ent._grmPermKind)
        end)
        if ent._grmPermKind == "server" and GRM.PropProtect and GRM.PropProtect.MarkServerEntity then
            GRM.PropProtect.MarkServerEntity(ent)
        elseif ent._grmPermKind == "character" and isstring(rec.owner) and rec.owner ~= "" then
            ent.GRM_PropOwnerCharacterKey = rec.owner
            ent.GRM_EntityOwnerCharacterKey = rec.owner
            pcall(function()
                ent:SetNWString("GRM_PropOwnerCharacterKey", rec.owner)
                ent:SetNWString("GRM_EntityOwnerCharacterKey", rec.owner)
                ent:SetNWString("GRM_PropOwnerName", tostring(rec.ownerName or ""))
            end)
        elseif ent._grmPermKind == "faction" then
            ent.GRM_PermFaction = tostring(rec.faction or "")
            pcall(function() ent:SetNWString("GRM_PermFaction", tostring(rec.faction or "")) end)
        end
        if rec.freeze ~= false then
            local ph = ent:GetPhysicsObject()
            if IsValid(ph) then ph:EnableMotion(false) end
        end
    end

    -- Закрепить объект. opts = {ownerKind, owner, ownerName, faction,
    -- freeze, label}. Возвращает: ok(bool), код/сообщение, запись
    function P.Add(ply, ent, opts)
        opts = istable(opts) and opts or {}
        if not IsValid(ent) then return false, "объект не найден" end
        local external, backend
        if GRM.Persistence and GRM.Persistence.Resolve then external, backend = GRM.Persistence.Resolve(ent) end
        if external and backend ~= "perm" then
            if not (IsValid(ply) and ply:IsSuperAdmin()) then return false, "внешний backend доступен только суперадмину" end
            local ok, result = GRM.Persistence.Call("Save", ent, ply, opts)
            if ok then
                ent:SetNWBool("GRM_IsPerm", true); ent:SetNWString("GRM_PermKind", "external")
                local info = GRM.Persistence.Inspect(ent) or { class = ent:GetClass(), backend = backend, external = true }
                return true, "external", info
            end
            return false, tostring(result or ("ошибка backend " .. tostring(backend)))
        end

        local okClass, whyClass = P.IsPermable(ent)
        if not okClass then return false, whyClass end

        local okRight, whyRight = canManageRec(ply, nil)
        if not okRight then return false, whyRight end

        local list = loadDB()
        local map = game.GetMap()

        -- уже в базе? тогда это обновление, а не дубль
        local idx, exist = findRec(list, ent)
        if exist then
            local okOwn, whyOwn = canManageRec(ply, exist)
            if not okOwn then return false, whyOwn end
            return P.Update(ply, ent, opts)
        end

        if countForMap(list, map) >= PERM_MAX then
            return false, ("лимит закреплённых объектов на карту: %d"):format(PERM_MAX)
        end

        -- Вид владения: по умолчанию серверное (как было), суперадмин может
        -- явно выбрать фракционное или личное
        local kind = tostring(opts.ownerKind or "server")
        if kind ~= "server" and kind ~= "faction" and kind ~= "character" then kind = "server" end
        local isSA = IsValid(ply) and ply.IsSuperAdmin and ply:IsSuperAdmin()
        if not isSA then
            -- без прав суперадмина закрепить «серверным» нельзя:
            -- иначе лидер фракции сделал бы объект неприкасаемым для всех
            if hasFactionPermRight(ply) then kind = (kind == "character") and "character" or "faction"
            else kind = "character" end
        end

        local faction = tostring(opts.faction or "")
        if kind == "faction" and faction == "" then faction = factionOf(ply) end
        if kind == "faction" and faction == "" then
            return false, "не удалось определить фракцию для закрепления"
        end

        local owner, ownerName = tostring(opts.owner or ""), tostring(opts.ownerName or "")
        if kind == "character" and owner == "" then
            owner, ownerName = charKeyOf(ply), rpNameOf(ply)
        end

        -- Квоты (защита от «запермил всю карту»)
        if kind == "faction" and not isSA then
            if countBy(list, map, "faction", faction) >= PERM_QUOTA_FACTION then
                return false, ("лимит фракции: %d закреплённых объектов"):format(PERM_QUOTA_FACTION)
            end
        elseif kind == "character" and not isSA then
            if not playersAllowed() then
                return false, "закрепление объектов игроками отключено (grm_perm_players 0)"
            end
            if countBy(list, map, "owner", owner) >= PERM_QUOTA_PLAYER then
                return false, ("лимит персонажа: %d закреплённых объектов"):format(PERM_QUOTA_PLAYER)
            end
        end

        -- Вето для сторонних модулей (зоны, сюжетные ограничения)
        local veto = hook.Run("GRM_PermCanAdd", ply, ent, kind)
        if veto == false then return false, "закрепление запрещено другим модулем" end

        local pos, ang = ent:GetPos(), ent:GetAngles()
        local model = ""
        pcall(function() model = tostring(ent:GetModel() or "") end)

        local rec = {
            map = map, class = tostring(ent:GetClass() or ""), model = model,
            pos = { x = pos.x, y = pos.y, z = pos.z },
            ang = { p = ang.p, y = ang.y, r = ang.r },
            uid = newUID(),
            ownerKind = kind, owner = owner, ownerName = ownerName, faction = faction,
            freeze = (opts.freeze ~= false),
            label = tostring(opts.label or ""),
            by = IsValid(ply) and tostring(ply:SteamID64() or "") or "",
            byName = IsValid(ply) and rpNameOf(ply) or "console",
            at = os.time(),
        }

        local extractFn = GRM.PermData and GRM.PermData.Extract and GRM.PermData.Extract[rec.class]
        if extractFn then
            local okX, data = pcall(extractFn, ent)
            if okX and istable(data) then rec.data = data end
        end

        list[#list + 1] = rec
        if not saveList(list) then return false, "ошибка записи базы — смотри консоль сервера" end

        markEnt(ent, rec)
        hook.Run("GRM_PermAdded", ent, rec, ply)
        print(("[GRM Perm] ADD %s uid=%s kind=%s by=%s")
            :format(rec.class, rec.uid, kind, rec.byName))
        return true, "added", rec
    end

    -- Снять закрепление. Объект НЕ удаляется (П2): админ снимает перм,
    -- чтобы подвинуть постройку, а не чтобы её потерять.
    function P.Remove(ply, ent, alsoDelete)
        if not IsValid(ent) then return false, "объект не найден" end
        local external, backend
        if GRM.Persistence and GRM.Persistence.Resolve then external, backend = GRM.Persistence.Resolve(ent) end
        if external and backend ~= "perm" then
            if not (IsValid(ply) and ply:IsSuperAdmin()) then return false, "внешний backend доступен только суперадмину" end
            local ok, result = GRM.Persistence.Call("Remove", ent, ply)
            if not ok then return false, tostring(result or ("запись backend " .. tostring(backend) .. " не найдена")) end
            ent:SetNWBool("GRM_IsPerm", false); ent:SetNWString("GRM_PermKind", "")
            if alsoDelete then ent:Remove() end
            return true, "external_removed", { class = ent:GetClass(), external = true, backend = backend }
        end
        local list = loadDB()
        local idx, rec = findRec(list, ent)
        if not rec then return false, "объект не закреплён" end

        local okOwn, whyOwn = canManageRec(ply, rec)
        if not okOwn then return false, whyOwn end

        table.remove(list, idx)
        if not saveList(list) then return false, "ошибка записи базы — смотри консоль сервера" end

        ent._grmPerm = nil
        ent._grmPermKind = nil
        ent._grmPermUID = nil
        pcall(function()
            ent:SetNWBool("GRM_IsPerm", false)
            ent:SetNWString("GRM_PermKind", "")
        end)
        local ph = ent:GetPhysicsObject()
        if IsValid(ph) then ph:EnableMotion(true) end

        hook.Run("GRM_PermRemoved", ent, rec, ply)
        print(("[GRM Perm] REMOVE %s uid=%s by=%s")
            :format(tostring(rec.class), tostring(rec.uid), IsValid(ply) and ply:Nick() or "console"))

        if alsoDelete then ent:Remove() end
        return true, "removed", rec
    end

    -- Широкий вырез записи (колонка и т.п.): позиция могла уехать дальше PERM_RANGE.
    function P.EraseNear(class, pos, radius)
        class = tostring(class or "")
        if class == "" or not istable(pos) and not (pos and pos.x) then return 0 end
        radius = tonumber(radius) or 80
        local r2 = radius * radius
        local list = loadDB()
        local map = game.GetMap()
        local n = 0
        for i = #list, 1, -1 do
            local rec = list[i]
            if rec.map == map and rec.class == class then
                local dx = (tonumber(rec.pos and rec.pos.x) or 0) - pos.x
                local dy = (tonumber(rec.pos and rec.pos.y) or 0) - pos.y
                local dz = (tonumber(rec.pos and rec.pos.z) or 0) - pos.z
                if dx * dx + dy * dy + dz * dz <= r2 then
                    table.remove(list, i)
                    n = n + 1
                end
            end
        end
        if n > 0 then saveList(list) end
        return n
    end

    -- Обновить запись под текущее состояние объекта (позиция, данные,
    -- владение, метка). Используется тулом и PhysgunDrop.
    function P.Update(ply, ent, opts)
        opts = istable(opts) and opts or {}
        if not IsValid(ent) then return false, "объект не найден" end
        local external, backend
        if GRM.Persistence and GRM.Persistence.Resolve then external, backend = GRM.Persistence.Resolve(ent) end
        if external and backend ~= "perm" then
            if not (IsValid(ply) and ply:IsSuperAdmin()) then return false, "внешний backend доступен только суперадмину" end
            local ok, result = GRM.Persistence.Call("Save", ent, ply, opts)
            return ok, ok and "external_updated" or tostring(result), GRM.Persistence.Inspect(ent)
        end
        local list = loadDB()
        local _, rec = findRec(list, ent)
        if not rec then return false, "объект не закреплён" end

        local okOwn, whyOwn = canManageRec(ply, rec)
        if not okOwn then return false, whyOwn end

        local pos, ang = ent:GetPos(), ent:GetAngles()
        rec.pos = { x = pos.x, y = pos.y, z = pos.z }
        rec.ang = { p = ang.p, y = ang.y, r = ang.r }
        pcall(function() rec.model = tostring(ent:GetModel() or rec.model or "") end)

        if opts.freeze ~= nil then rec.freeze = (opts.freeze ~= false) end
        if opts.label ~= nil then rec.label = tostring(opts.label) end
        if isstring(opts.ownerKind) and IsValid(ply) and ply:IsSuperAdmin() then
            local kind = opts.ownerKind
            if kind == "server" or kind == "faction" or kind == "character" then
                rec.ownerKind = kind
                if kind == "faction" then
                    rec.faction = tostring(opts.faction or rec.faction or factionOf(ply))
                elseif kind == "character" then
                    rec.owner = tostring(opts.owner or charKeyOf(ply))
                    rec.ownerName = tostring(opts.ownerName or rpNameOf(ply))
                end
            end
        end

        local extractFn = GRM.PermData and GRM.PermData.Extract and GRM.PermData.Extract[rec.class]
        if extractFn then
            local okX, data = pcall(extractFn, ent)
            if okX and istable(data) then rec.data = data end
        end

        if not saveList(list) then return false, "ошибка записи базы — смотри консоль сервера" end
        markEnt(ent, rec)
        hook.Run("GRM_PermUpdated", ent, rec, ply)
        return true, "updated", rec
    end

    -- Перепривязка владения (для /permowner и панели тула)
    function P.SetOwner(ply, ent, kind, value)
        if not IsValid(ply) or not ply:IsSuperAdmin() then
            if not hasFactionPermRight(ply) then return false, "недостаточно прав" end
        end
        return P.Update(ply, ent, {
            ownerKind = kind,
            faction = (kind == "faction") and value or nil,
            owner = (kind == "character") and value or nil,
        })
    end

    -- Совместимость: старые вызовы Upsert/UpdateEntry остаются рабочими
    P.Upsert      = function(ent) return GRM.PermData.Upsert(ent) end
    P.UpdateEntry = function(ent) return GRM.PermData.UpdateEntry(ent) end

    local function loadPerm(ply)
        local spawned, skipped = spawnAll("ручная загрузка")
        if spawned == 0 and skipped == 0 then
            tell(ply, "[ПЕРМ] Для этой карты в базе записей нет.", 255, 200, 80)
        else
            tell(ply, ("[ПЕРМ] Загрузка из базы: восстановлено %d, уже на месте %d."):format(spawned, skipped), 100, 220, 255)
        end
    end

    local function listPerm(ply)
        local list = loadDB()
        local map = game.GetMap()
        local n = 0
        for _, rec in ipairs(list) do
            if rec.map == map then
                n = n + 1
                print(( "[GRM Perm]  #%d %s @ %d %d %d" ):format(n, rec.class,
                    tonumber(rec.pos.x) or 0, tonumber(rec.pos.y) or 0, tonumber(rec.pos.z) or 0))
            end
        end
        tell(ply, ("Пермов на карте %s: %d (в базе всего: %d). Список — в консоли сервера."):format(map, n, #list), 100, 220, 255)
    end

    -- ── Команды ─────────────────────────────────────────────
    local function guarded(fn)
        return function(ply)
            if not IsValid(ply) then print("[GRM Perm] Команда только из игры (сервер-консоль: нет прицела).") return end
            if not ply:IsSuperAdmin() then tell(ply, "Только суперадмин.", 255, 100, 100) return end
            fn(ply)
        end
    end
    concommand.Add("grm_perm_add", guarded(addPerm))
    concommand.Add("grm_perm_remove", guarded(removePerm))
    concommand.Add("grm_perm_list", guarded(listPerm))
    concommand.Add("grm_perm_load", guarded(loadPerm))

    -- Находка 179e: EasyChat ставит SkipPlayerSay для команд → PlayerSay не
    -- вызывается. Дублируем обработку через PlayerSayTransform (как /factions).
    hook.Add("PlayerSayTransform", "GRM_PermEntities_ChatTransform", function(ply, datapack)
        if not istable(datapack) then return end
        local text = datapack[1]
        if not isstring(text) then return end
        local t = string.lower(string.Trim(text))
        if t ~= "/permadd" and t ~= "/permremove" and t ~= "/permlist" and t ~= "/permload" then return end
        if not IsValid(ply) or not ply:IsSuperAdmin() then
            tell(ply, "Только суперадмин.", 255, 100, 100)
            datapack.SkipPlayerSay = true
            datapack[1] = ""
            return
        end
        if t == "/permadd" then addPerm(ply)
        elseif t == "/permremove" then removePerm(ply)
        elseif t == "/permload" then loadPerm(ply)
        else listPerm(ply) end
        datapack.SkipPlayerSay = true
        datapack[1] = ""
    end)

    hook.Add("PlayerSay", "GRM_PermEntities_Chat", function(ply, text)
        local t = string.lower(string.Trim(tostring(text or "")))
        if t ~= "/permadd" and t ~= "/permremove" and t ~= "/permlist" and t ~= "/permload" then return end
        if not IsValid(ply) or not ply:IsSuperAdmin() then
            tell(ply, "Только суперадмин.", 255, 100, 100)
            return ""
        end
        if t == "/permadd" then addPerm(ply)
        elseif t == "/permremove" then removePerm(ply)
        elseif t == "/permload" then loadPerm(ply)
        else listPerm(ply) end
        return ""
    end)

    -- ── /perminfo и /permowner <фракция|me|server> ──────────
    -- Команды с аргументом: старые четыре разбирались точным сравнением,
    -- поэтому обрабатываем отдельно.
    local function infoPerm(ply)
        local ent = aimEntity(ply)
        if not IsValid(ent) then tell(ply, "Наведи прицел на объект.", 255, 200, 80) return end
        local rec = P.Info(ent)
        local backendInfo = GRM.Persistence and GRM.Persistence.Inspect and GRM.Persistence.Inspect(ent) or nil
        if not rec and istable(backendInfo) and backendInfo.persistent == true then
            rec = { class = ent:GetClass(), ownerKind = "server", freeze = true,
                uid = backendInfo.uid or "-", backend = backendInfo.backend, byName = "GRM " .. tostring(backendInfo.backend) }
        end
        if not rec then
            local ok, why = P.IsPermable(ent)
            local backend = istable(backendInfo) and (" Backend: " .. tostring(backendInfo.backend) .. ".") or ""
            tell(ply, "Объект НЕ закреплён." .. backend .. " " .. (ok and "Можно закрепить." or ("Причина: " .. tostring(why))), 255, 200, 80)
            return
        end
        local kind = tostring(rec.ownerKind or "server")
        local whose = (kind == "faction" and ("фракция " .. tostring(rec.faction or "?")))
            or (kind == "character" and ("персонаж " .. tostring(rec.ownerName ~= "" and rec.ownerName or rec.owner)))
            or "серверное оборудование"
        local backend = tostring(rec.backend or (istable(backendInfo) and backendInfo.backend) or "perm")
        tell(ply, ("[ПЕРМ] %s | backend: %s | %s | заморозка: %s | uid: %s")
            :format(tostring(rec.class), backend, whose, rec.freeze == false and "нет" or "да", tostring(rec.uid or "-")), 100, 220, 255)
        tell(ply, ("Закрепил: %s (%s)"):format(tostring(rec.byName or "?"),
            rec.at and os.date("%d.%m.%Y %H:%M", tonumber(rec.at)) or "?"), 160, 190, 210)
    end

    local function ownerPerm(ply, arg)
        local ent = aimEntity(ply)
        if not IsValid(ent) then tell(ply, "Наведи прицел на закреплённый объект.", 255, 200, 80) return end
        arg = string.Trim(tostring(arg or ""))
        local ok, msg
        if arg == "" then
            tell(ply, "Использование: /permowner <фракция> | me | server", 255, 200, 80)
            return
        elseif arg == "server" then
            ok, msg = P.Update(ply, ent, { ownerKind = "server" })
        elseif arg == "me" then
            ok, msg = P.Update(ply, ent, { ownerKind = "character",
                owner = charKeyOf(ply), ownerName = rpNameOf(ply) })
        else
            ok, msg = P.Update(ply, ent, { ownerKind = "faction", faction = arg })
        end
        if ok then tell(ply, "[ПЕРМ] Владение обновлено: " .. arg, 100, 220, 100)
        else tell(ply, "[ПЕРМ] " .. tostring(msg), 255, 120, 120) end
    end

    local function handleArgCmd(ply, text)
        local t = string.Trim(tostring(text or ""))
        local low = string.lower(t)
        if low == "/perminfo" then
            if not IsValid(ply) then return false end
            infoPerm(ply)
            return true
        end
        if low:sub(1, 11) == "/permowner " or low == "/permowner" then
            if not IsValid(ply) then return false end
            if not ply:IsSuperAdmin() and not hasFactionPermRight(ply) then
                tell(ply, "Недостаточно прав.", 255, 100, 100)
                return true
            end
            ownerPerm(ply, t:sub(12))
            return true
        end
        return false
    end

    hook.Add("PlayerSayTransform", "GRM_PermEntities_ChatArgs", function(ply, datapack)
        if not istable(datapack) or not isstring(datapack[1]) then return end
        if handleArgCmd(ply, datapack[1]) then
            datapack.SkipPlayerSay = true
            datapack[1] = ""
        end
    end)

    hook.Add("PlayerSay", "GRM_PermEntities_ChatArgs", function(ply, text)
        if handleArgCmd(ply, text) then return "" end
    end)

    -- Подвинул закреплённый объект физганом — запись едет следом.
    -- Без этого после рестарта объект прыгал на старое место, и админ
    -- считал, что перм «сломался».
    hook.Add("PhysgunDrop", "GRM_PermEntities_FollowMove", function(ply, ent)
        if not IsValid(ent) or not ent._grmPerm then return end
        if ent._grmPermMoveAt and CurTime() < ent._grmPermMoveAt then return end
        ent._grmPermMoveAt = CurTime() + 1.5
        timer.Simple(1.5, function()
            if not IsValid(ent) or not ent._grmPerm then return end
            local list = loadDB()
            local uid = ent._grmPermUID
            for _, rec in ipairs(list) do
                if isstring(uid) and rec.uid == uid then
                    local pos, ang = ent:GetPos(), ent:GetAngles()
                    rec.pos = { x = pos.x, y = pos.y, z = pos.z }
                    rec.ang = { p = ang.p, y = ang.y, r = ang.r }
                    saveList(list)
                    hook.Run("GRM_PermUpdated", ent, rec, ply)
                    break
                end
            end
        end)
    end)

    -- Служебные компьютеры ведомств: заголовок на экране задаётся
    -- инструментом «GRM Служебное оборудование». Без делегатов перм
    -- сохранял только класс/позицию, и после рестарта пользовательский
    -- заголовок сбрасывался на дефолтный из ENT:Initialize.
    for _, class in ipairs({
        "grm_doc_computer", "grm_comp_police", "grm_comp_military_police",
        "grm_comp_security", "grm_comp_military", "grm_comp_traffic",
        "grm_comp_medical", "grm_comp_education",
        "grm_comp_fire", "grm_comp_cityhall", "grm_comp_court", "grm_comp_public",
    }) do
        GRM.PermData.Extract[class] = function(ent)
            if not IsValid(ent) or not isfunction(ent.GetComputerName) then return nil end
            local name = tostring(ent:GetComputerName() or "")
            local out = {}
            if name ~= "" then out.computerName = name end
            if isfunction(ent.GetServiceProfile) then
                local p = tostring(ent:GetServiceProfile() or "")
                if p ~= "" then out.serviceProfile = p end
            end
            return next(out) and out or nil
        end
        GRM.PermData.Apply[class] = function(ent, data)
            if not IsValid(ent) or not istable(data) then return end
            if isstring(data.computerName) and data.computerName ~= ""
                and isfunction(ent.SetComputerName) then
                ent:SetComputerName(data.computerName)
            end
            if isstring(data.serviceProfile) and data.serviceProfile ~= ""
                and isfunction(ent.SetServiceProfile) then
                ent:SetServiceProfile(data.serviceProfile)
            end
        end
    end

    -- Делегаты для логистических entity (Код 112)
    -- GRM.PermData.Extract[class] = fn(ent) -> таблица
    -- GRM.PermData.Apply[class]   = fn(ent, data)
    for _, class in ipairs({"grm_logistics_loading", "grm_logistics_warehouse", "grm_logistics_armory",
        "grm_weapon_rack"}) do
        GRM.PermData.Extract[class] = function(ent)
            if not IsValid(ent) or not ent.GetPermData then return nil end
            return ent:GetPermData()
        end
        GRM.PermData.Apply[class] = function(ent, data)
            if not IsValid(ent) or not ent.ApplyPermData then return end
            ent:ApplyPermData(data)
        end
    end

    print(("[GRM Perm] Perm Entities v%s загружен (путь: %s, база: data/%s)")
        :format(PERM_VER, tostring(debug.getinfo(1, "S").short_src), PERM_FILE))
end
