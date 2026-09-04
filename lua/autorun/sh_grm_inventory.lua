--[[--------------------------------------------------------------------
    GRM Inventory System v1.7.0 (Код 109)
    Полноценный инвентарь с ячейками для патронов, оружия и предметов

    v1.5.0 (Код 109, находка 126 — заказ владельца «нормальный модуль на
    рации»): useFunc-диспетчер переведён на РЕЕСТР обработчиков
    GRM.Inventory.RegisterUseHandler. Корень бага «в инвентаре жму
    Использовать — ничего»: zz_grm_food_inventory_patch.lua не мог
    расширить ЛОКАЛЬНУЮ useItem хуком и поэтому ЗАМЕНЯЛ net-ресивер
    «grm_inv_use» своей неполной копией без radio_toggle/mobile_open/
    cash_to_wallet/medcard_view — клик умирал беззвучно, модулятор
    никогда не включался, а значит /freq и /r всегда отвечали «нет
    активного модулятора» (в т.ч. после рестарта). Теперь замена
    ресивера не нужна никому: обработчик регистрируется API-вызовом;
    отсутствие обработчика = ВИДИМЫЙ отказ игроку + строка в консоль.

    Возможности:
      • Сетка инвентаря с настраиваемым количеством слотов
      • Хранение: оружие, патроны, предметы
      • Перетаскивание предметов (drag & drop)
      • Подбор предметов с земли / выброс из инвентаря
      • Использование предметов (экипировка оружия, применение патронов)
      • Сохранение инвентаря в файл (персистентность)
    v1.1.0 (Код 97, находка 114): ЛОАДЕР калечил весь инвентарь при рестарте —
    bare util.JSONToTable конвертировал sid64-ключ в битый double → записи
    сиротели («пропадают купленные телефоны» — пропадало ВСЁ). Теперь:
    jsonT 3-им аргументом (н65), нормализация ключей слотов в числа,
    ленивое sid64-rescue для уже битых сейвов, дебаунс-автосейв 2с на любых
    мутациях (окно 10с автотаймера закрыто), read-back SAVE-печать.
    v1.2.0 (Код 99, находка 116): (а) useFunc «radio_toggle» — переносной
    модулятор рации: «Использовать» переключает ВКЛ/ВЫКЛ, состояние живёт
    в данных САМОГО предмета (slot.data.on) — переживает рестарт (сейв
    инвентаря), падает в дроп и возвращается при подборе; (б) AddItem
    получил необязательный 4-й параметр data — grm_item_drop раньше
    терял данные не-оружейных предметов при подборе (включённый
    модулятор поднимался бы сброшенным).
    v1.4.0 (Код 106, находка 123): статический деф radio_modulator в
    ItemDefs (живая гарантия useFunc при любом порядке загрузки), useItem
    без тихих выходов — нет дефа = видимый отказ игроку + строка в консоль.
    v1.3.0 (Код 101, находка 118): useFunc «medcard_view» — медицинская
    карта на руках: «Использовать» открывает просмотр карты владельца
    (sid64 — в slot.data предмета, поэтому переживает дроп/подбор и
    рестарт). Предмет НЕ тратится. Сам просмотр — на стороне модуля
    медицины (MD.ViewIssued).
      • Синхронизация сервер ↔ клиент
      • Стакирование одинаковых предметов (патроны)
      • Интеграция с GRM Currency

    Команды:
      /inv или /inventory — открыть инвентарь

    Типы предметов:
      "weapon"  — оружие (не стакируется)
      "ammo"    — патроны (стакируются)
      "item"    — предметы (стакируются по настройке)
--------------------------------------------------------------------]]

GRM = GRM or {}
GRM.Inventory = GRM.Inventory or {}

-- ================================================================
--  КОНФИГУРАЦИЯ
-- ================================================================
GRM.Inventory.Config = {
    MaxSlots       = 24,         -- Количество слотов инвентаря
    MaxStack       = 999,        -- Максимальный стак для патронов
    ItemMaxStack   = 10,         -- Максимальный стак для предметов
    SaveInterval   = 10,         -- Интервал автосохранения (секунды)
    DropDistance   = 80,         -- Дистанция выброса предмета
}

-- ================================================================
--  ОПРЕДЕЛЕНИЯ ПРЕДМЕТОВ (Shared)
-- ================================================================
-- Реестр всех возможных предметов
GRM.Inventory.ItemDefs = {
    -- === ПАТРОНЫ ===
    ["ammo_pistol"] = {
        type = "ammo",
        name = "Пистолетные патроны",
        desc = "Стандартные патроны калибра 9мм",
        icon = "icon16/bullet_blue.png",
        ammoType = "Pistol",
        maxStack = 120,
        weight = 0.1,
    },
    ["ammo_smg1"] = {
        type = "ammo",
        name = "Патроны SMG",
        desc = "Патроны для пистолетов-пулемётов",
        icon = "icon16/bullet_orange.png",
        ammoType = "SMG1",
        maxStack = 240,
        weight = 0.1,
    },
    ["ammo_ar2"] = {
        type = "ammo",
        name = "Патроны AR2",
        desc = "Энергетические патроны для AR2",
        icon = "icon16/bullet_purple.png",
        ammoType = "AR2",
        maxStack = 120,
        weight = 0.2,
    },
    ["ammo_357"] = {
        type = "ammo",
        name = "Патроны .357",
        desc = "Мощные патроны калибра .357 Magnum",
        icon = "icon16/bullet_red.png",
        ammoType = "357",
        maxStack = 36,
        weight = 0.3,
    },
    ["ammo_buckshot"] = {
        type = "ammo",
        name = "Картечь",
        desc = "Патроны для дробовика",
        icon = "icon16/bullet_yellow.png",
        ammoType = "Buckshot",
        maxStack = 48,
        weight = 0.2,
    },
    ["ammo_crossbow"] = {
        type = "ammo",
        name = "Болты арбалета",
        desc = "Стальные болты для арбалета",
        icon = "icon16/bullet_green.png",
        ammoType = "XBowBolt",
        maxStack = 12,
        weight = 0.5,
    },
    ["ammo_rpg"] = {
        type = "ammo",
        name = "Ракеты RPG",
        desc = "Ракеты для гранатомёта",
        icon = "icon16/bomb.png",
        ammoType = "RPG_Round",
        maxStack = 6,
        weight = 2.0,
    },
    ["ammo_grenade"] = {
        type = "ammo",
        name = "Гранаты",
        desc = "Осколочные гранаты",
        icon = "icon16/bomb.png",
        ammoType = "Grenade",
        maxStack = 6,
        weight = 1.0,
    },
    ["ammo_smg1_grenade"] = {
        type = "ammo",
        name = "Гранаты SMG",
        desc = "Подствольные гранаты для SMG",
        icon = "icon16/bomb.png",
        ammoType = "SMG1_Grenade",
        maxStack = 6,
        weight = 1.0,
    },

    -- === ПРЕДМЕТЫ ===
    ["item_healthkit"] = {
        type = "item",
        name = "Аптечка",
        desc = "Восстанавливает 25 HP",
        icon = "icon16/heart.png",
        maxStack = 5,
        weight = 1.0,
        useFunc = "heal_25",
    },
    ["item_battery"] = {
        type = "item",
        name = "Батарея",
        desc = "Восстанавливает 15 брони",
        icon = "icon16/shield.png",
        maxStack = 5,
        weight = 1.0,
        useFunc = "armor_15",
    },
    ["item_lockpick"] = {
        type = "item",
        name = "Взломщик",
        desc = "Позволяет вскрывать замки, кейпады и сканеры",
        icon = "icon16/key.png",
        maxStack = 3,
        weight = 0.5,
    },
    ["item_repair_kit"] = {
        type = "item",
        name = "Ремкомплект",
        desc = "Для ремонта транспорта",
        icon = "icon16/wrench.png",
        maxStack = 3,
        weight = 2.0,
    },

    -- === ДЕНЬГИ (физические, Код 81) ===
    -- Число в стаке = сумма. Дроп на землю — моделью cs_assault/money.mdl
    -- (см. grm_item_drop: def.model). Хранится в инвентаре и багажнике.
    ["money"] = {
        type = "item",
        name = "Деньги",
        desc = "Пачка наличных (число = сумма). Использование — обналичить в кошелёк.",
        icon = "icon16/money.png",
        maxStack = 50000,
        weight = 0.001,
        model = "models/props/cs_assault/money.mdl",
        useFunc = "cash_to_wallet",
    },

    -- === МОДУЛЯТОР РАЦИИ (Код 99/106, находка 123) ===
    -- СТАТИЧЕСКИЙ деф: гарантия useFunc при ЛЮБОМ порядке загрузки модулей.
    -- Раньше дефом владел только RadioNet (внешняя регистрация с ретраем
    -- ВНУТРИ гарда на GRM.Inventory): если на конкретной загрузке сервера
    -- порядок файлов переворачивался, деф не появлялся вообще НИКОГДА
    -- (ретрай тоже пропускался), а useItem молча выходил — «мёртвая
    -- кнопка Использовать». RadioNet переписывает это же определение
    -- своим (с валидацией модели) — содержимое идентично.
    ["radio_modulator"] = {
        type = "item",
        name = "Модулятор рации (переносной)",
        desc = "Переносная радиостанция. «Использовать» — вкл/выкл. Когда включён: /freq 145.5 — частота, /r текст — эфир. Сеть — любая дистанция, вне сети до 37 м напрямую.",
        icon = "icon16/transmit.png",
        maxStack = 1,
        weight = 0.6,
        model = "models/props_lab/reciever01b.mdl",
        useFunc = "radio_toggle",
    },

    -- === ЧИПЫ АУГМЕНТАЦИЙ ===
    ["mobile_crappy"] = { type = "item", name = "Телефон: Badger Crappy", desc = "Дешёвая трубка. Только звонки.", icon = "icon16/phone.png", maxStack = 1, weight = 0.35, model = "models/ivancorn/gtaiv/electrical/phones/cellphone_badger_crappy.mdl", useFunc = "mobile_open" },
    ["mobile_badger"] = { type = "item", name = "Телефон: Badger Classic", desc = "Звонки, SMS, контакты.", icon = "icon16/phone.png", maxStack = 1, weight = 0.35, model = "models/ivancorn/gtaiv/electrical/phones/cellphone_badger.mdl", useFunc = "mobile_open" },
    ["mobile_badger_touch"] = { type = "item", name = "Телефон: Badger Touch", desc = "Сенсорный Badger.", icon = "icon16/phone.png", maxStack = 1, weight = 0.35, model = "models/ivancorn/gtaiv/electrical/phones/phone_mobile_badger_touchscreen.mdl", useFunc = "mobile_open" },
    ["mobile_lost"] = { type = "item", name = "Телефон: The Lost Flip", desc = "Раскладушка.", icon = "icon16/phone.png", maxStack = 1, weight = 0.35, model = "models/ivancorn/gtaiv/electrical/phones/cellphone_thelostdamned.mdl", useFunc = "mobile_open" },
    ["mobile_tinkle"] = { type = "item", name = "Телефон: Panoramic Tinkle", desc = "Смартфон.", icon = "icon16/phone.png", maxStack = 1, weight = 0.35, model = "models/ivancorn/gtaiv/electrical/phones/cellphone_panoramic_tinkle.mdl", useFunc = "mobile_open" },
    ["mobile_whiz_high"] = { type = "item", name = "Телефон: Whiz Highspeed", desc = "Флагман Whiz.", icon = "icon16/phone.png", maxStack = 1, weight = 0.35, model = "models/ivancorn/gtaiv/electrical/phones/cellphone_whiz_highspeed.mdl", useFunc = "mobile_open" },
    ["mobile_whiz_gold"] = { type = "item", name = "Телефон: Whiz Gold", desc = "Золотой Whiz.", icon = "icon16/phone.png", maxStack = 1, weight = 0.35, model = "models/ivancorn/gtaiv/electrical/phones/cellphone_whiz_gold.mdl", useFunc = "mobile_open" },

    ["augmentation_chip"] = {
        type = "item",
        name = "Чип аугментации",
        desc = "Программируемый чип для аугментаций. Использовать для имплантации.",
        icon = "icon16/cog.png",
        maxStack = 5,
        weight = 0.1,
        model = "models/bull/gates/logic.mdl",
        useFunc = "augment_chip_implant",
    },
}

-- Функция регистрации нового предмета (для аддонов)
function GRM.Inventory.RegisterItem(id, data)
    if not id or not data then return end
    GRM.Inventory.ItemDefs[id] = data
end

-- Получить определение предмета
function GRM.Inventory.GetItemDef(itemID)
    return GRM.Inventory.ItemDefs[itemID]
end

-- Получить максимальный стак для предмета
function GRM.Inventory.GetMaxStack(itemID)
    local def = GRM.Inventory.ItemDefs[itemID]
    if not def then return 1 end
    if def.type == "weapon" then return 1 end
    return def.maxStack or GRM.Inventory.Config.MaxStack
end

-- ================================================================
--  РЕЕСТР ОБРАБОТЧИКОВ ИСПОЛЬЗОВАНИЯ (Код 109, находка 126 — «нормальный
--  модуль» для таких предметов, как модулятор рации)
-- ================================================================
-- Раньше useFunc обрабатывался захардкоженным if-elseif внутри ЛОКАЛЬНОЙ
-- useItem — расширить её хуком было нельзя, поэтому патч еды просто
-- ЗАМЕНЯЛ net.Receive("grm_inv_use") своей неполной копией, в которой
-- radio_toggle/cash_to_wallet/mobile_open/medcard_view отсутствовали:
-- «Использовать» по модулятору умирало БЕЗ ЗВУКА («жму — ничего»,
-- заказ владельца Кода 109). Теперь обработчик — регистрируемая точка:
--   GRM.Inventory.RegisterUseHandler("my_usefunc", function(ply, slotIdx, slot, def) ... end)
-- Хендлер ПОЛНОСТЬЮ владеет потоком (сам решает уведомления/расход).
-- Свой обработчик нельзя регистрировать заменой ресивера — только API.
GRM.Inventory.UseHandlers = GRM.Inventory.UseHandlers or {}

function GRM.Inventory.RegisterUseHandler(useFunc, fn)
    if not isstring(useFunc) or useFunc == "" or not isfunction(fn) then return false end
    GRM.Inventory.UseHandlers[useFunc] = fn
    return true
end

-- ================================================================
--  СЕРВЕР
-- ================================================================
if SERVER then
    AddCSLuaFile()

    util.AddNetworkString("grm_inv_sync")
    util.AddNetworkString("grm_inv_update_slot")
    util.AddNetworkString("GRM_Inv_AdminOpen")     -- суперадмин: просмотр чужого инвентаря
    util.AddNetworkString("GRM_Inv_AdminData")     -- данные чужого инвентаря админу
    util.AddNetworkString("GRM_Inv_AdminAction")   -- суперадмин: изъять предмет
    util.AddNetworkString("grm_inv_action")
    util.AddNetworkString("grm_inv_result")
    util.AddNetworkString("grm_inv_open")
    util.AddNetworkString("grm_inv_drop")
    util.AddNetworkString("grm_inv_use")
    util.AddNetworkString("grm_inv_move")
    util.AddNetworkString("grm_inv_split")

    local INV_FILE = "grm_inventories.json"
    local INV_BACKUP_FILE = "grm_inventories_backup.json"
    local INV_TEMP_FILE = "grm_inventories_write_tmp.json"
    -- v1.7: CharacterKey inventory + verified main/temporary/backup chain.
    local Inventories = {}
    local persistenceHealthy = true
    local persistenceRevision = 0

    local function decodeInventories(raw)
        if not isstring(raw) or string.Trim(raw) == "" then return nil,"empty" end
        local ok,t=pcall(util.JSONToTable,raw,false,true)
        if not(ok and istable(t))then return nil,"decode" end
        local out={};local revision=istable(t._grm_meta)and tonumber(t._grm_meta.revision)or 0
        for k,rec in pairs(t)do
            if k~="_grm_meta"and istable(rec)then
                local sk=isnumber(k)and string.format("%.0f",k)or k
                if isstring(sk)and sk~=""then
                    local rawSlots=rec.slots
                    if not istable(rawSlots)then
                        local looks=false;for kk,vv in pairs(rec)do if tonumber(kk)~=nil and istable(vv)and vv.id then looks=true break end end
                        if looks then rawSlots=rec end
                    end
                    local slots={};for kk,vv in pairs(rawSlots or{})do if istable(vv)and vv.id then slots[tonumber(kk)or kk]=vv end end
                    rec.slots=slots;out[sk]=rec
                end
            end
        end
        return out,nil,revision
    end
    local function inventoryScore(data)local score=0;for _,rec in pairs(data or{})do score=score+10;for _ in pairs(rec.slots or{})do score=score+1 end end;return score end
    local function persistenceError(msg)if ErrorNoHalt then ErrorNoHalt(msg.."\n")else print(msg)end end
    local function quarantineInventory(path,raw,why)
        if not isstring(raw)or raw==""then return end
        local q="grm_inventory_corrupt_"..tostring(os.time()).."_"..path:gsub("[^%w]","_")..".json"
        file.Write(q,raw);persistenceError("[GRM Inv] повреждён "..path.." ("..tostring(why).."), карантин: "..q)
    end
    local function loadInventories()
        local existed=false;local best,bestPath,bestRevision,bestScore=nil,nil,-1,-1
        for _,path in ipairs({INV_FILE,INV_TEMP_FILE,INV_BACKUP_FILE})do
            if file.Exists(path,"DATA")then
                existed=true;local raw=file.Read(path,"DATA")or"";local decoded,why,revision=decodeInventories(raw)
                if decoded then local score=inventoryScore(decoded);if revision>bestRevision or(revision==bestRevision and score>bestScore)then best,bestPath,bestRevision,bestScore=decoded,path,revision,score end
                else quarantineInventory(path,raw,why)end
            end
        end
        if best then persistenceRevision=bestRevision;if bestPath~=INV_FILE then print("[GRM Inv] восстановление из "..bestPath.." rev="..bestRevision.." score="..bestScore)end;return best,true,bestPath end
        if existed then persistenceError("[GRM Inv] все источники повреждены; пустой реестр НЕ будет записан поверх данных");return{},false,"corrupt"end
        return{},true,"new"
    end
    local function verifiedWrite(path,encoded)
        file.Write(path,encoded)
        local rb=file.Read(path,"DATA")or"";if rb~=encoded then return false,"readback" end
        local decoded=decodeInventories(rb);if not decoded then return false,"verify_decode" end
        return true
    end
    local function saveInventories(why)
        if not persistenceHealthy then print("[GRM Inv][!] SAVE BLOCKED: boot persistence unhealthy ("..tostring(why or"?")..")")return false end
        local nextRevision=persistenceRevision+1;local payload={};for key,value in pairs(Inventories)do payload[key]=value end;payload._grm_meta={version=2,revision=nextRevision,savedAt=os.time()}
        local ok,enc=pcall(util.TableToJSON,payload,true)
        if not ok or not isstring(enc)or not decodeInventories(enc)then print("[GRM Inv][!] сериализация/проверка не удалась ("..tostring(why or"?")..")")return false end
        local tempOK,tempWhy=verifiedWrite(INV_TEMP_FILE,enc);if not tempOK then print("[GRM Inv][!] temp SAVE FAIL: "..tostring(tempWhy))return false end
        local mainOK,mainWhy=verifiedWrite(INV_FILE,enc);if not mainOK then print("[GRM Inv][!] main SAVE FAIL: "..tostring(mainWhy))return false end
        local backupOK,backupWhy=verifiedWrite(INV_BACKUP_FILE,enc);if not backupOK then print("[GRM Inv][!] backup SAVE FAIL: "..tostring(backupWhy))return false end
        persistenceRevision=nextRevision;if file.Delete then file.Delete(INV_TEMP_FILE)end
        return true
    end
    -- дебаунс-автосейв 2с на любых мутациях: закрывает окно 10с автотаймера
    local function saveSoon(why)
        timer.Create("GRM_Inv_SaveSoon", 2, 1, function()
            saveInventories("дебаунс: " .. tostring(why or "?"))
        end)
    end
    GRM.Inventory._devSaveSoon = saveSoon -- тест-экспорт

    local loadedInventories,loadedHealthy,loadedSource=loadInventories()
    Inventories=loadedInventories or{};persistenceHealthy=loadedHealthy~=false
    GRM.Inventory.PersistenceHealthy=function()return persistenceHealthy,loadedSource end
    GRM.Inventory.SaveNow=function(why)return saveInventories("immediate: "..tostring(why or"api"))end

    --[[ ВЫХОД ИЗ БЛОКИРОВКИ (21.08). Если инвентарь загрузился из
         повреждённого файла, запись блокируется НА ВСЮ СЕССИЮ: ни выдача
         бланков, ни подобранные предметы не сохраняются, и внешне это
         выглядит как «функция просто не работает». Раньше снять блокировку
         было нечем — только рестарт с ручной правкой файла.
         Теперь суперадмин видит предупреждение и может принять текущее
         состояние (лучшую из уцелевших копий) как рабочее. ]]
    function GRM.Inventory.UnblockPersistence(why)
        persistenceHealthy = true
        local ok = saveInventories("unblock: " .. tostring(why or "админ"))
        if not ok then persistenceHealthy = false end
        return ok
    end

    if not persistenceHealthy then
        print("[GRM Inv][!] ВНИМАНИЕ: инвентарь загружен из повреждённого файла (" ..
            tostring(loadedSource) .. "). Сохранение ЗАБЛОКИРОВАНО.")
        print("[GRM Inv][!] Проверить: grm_inv_health · Снять блокировку: grm_inv_unblock confirm")
    end

    concommand.Add("grm_inv_health", function(ply)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        local line = ("[GRM Inv] хранилище: %s · источник: %s · записей: %d")
            :format(persistenceHealthy and "в порядке" or "ЗАБЛОКИРОВАНО",
                tostring(loadedSource), table.Count(Inventories or {}))
        if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
    end)

    concommand.Add("grm_inv_unblock", function(ply, _, args)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        local function out(line)
            if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, line) else print(line) end
        end
        if persistenceHealthy then out("[GRM Inv] блокировки нет, сохранение работает") return end
        if tostring(args and args[1] or "") ~= "confirm" then
            out("[GRM Inv] ВНИМАНИЕ: текущее состояние (" .. tostring(loadedSource) ..
                ") станет основным файлом. Подтвердите: grm_inv_unblock confirm")
            return
        end
        out(GRM.Inventory.UnblockPersistence("команда админа")
            and "[GRM Inv] блокировка снята, инвентари сохранены"
            or "[GRM Inv] снять блокировку не удалось — смотрите ошибки записи выше")
    end)
    if persistenceHealthy and loadedSource~=INV_FILE and loadedSource~="new"then timer.Simple(0,function()saveInventories("heal from "..tostring(loadedSource))end)end

    -- Автосохранение
    local function steamKey(ply)
        if not IsValid(ply) then return nil end
        local sid = ply:SteamID64()
        if not sid or sid == "0" then return nil end
        return sid
    end

    local function inventoryKey(ply)
        local sid = steamKey(ply)
        if not sid then return nil, nil end
        if GRM.Char and GRM.Char.GetActiveKey then
            local ok, key = pcall(GRM.Char.GetActiveKey, ply)
            key = ok and tostring(key or "") or ""
            if key ~= "" and key ~= "0" then return key, sid end
        end
        return sid, sid
    end

    function GRM.Inventory.GetInventoryKey(ply)
        local key = inventoryKey(ply)
        return key
    end

    local function normalizeSlots(rec)
        rec = istable(rec) and rec or { slots = {} }
        local slots = {}
        for kk, vv in pairs(rec.slots or {}) do
            if istable(vv) then slots[tonumber(kk) or kk] = vv end
        end
        rec.slots = slots
        return rec
    end

    timer.Create("GRM_Inv_AutoSave", tonumber(GRM.Inventory.Config.SaveInterval) or 10, 0, function()
        saveInventories("авто")
    end)

    -- ── Получить инвентарь игрока ────────────────────────────────
    local function getLegacySteamInv(ply, sid)
        if not Inventories[sid] then
            -- находка 114: ленивое самолечение записи, покалеченной старым лоадером
            local num = tonumber(sid)
            if num then
                local cand, cnt = nil, 0
                for k in pairs(Inventories) do
                    if k ~= sid then
                        local kn = isnumber(k) and k or (isstring(k) and tonumber(k) or nil)
                        if kn and math.abs(kn - num) < 64 then cand, cnt = k, cnt + 1 end
                    end
                end
                if cnt == 1 then
                    Inventories[sid] = Inventories[cand]
                    Inventories[cand] = nil
                    saveSoon("sid64-rescue")
                    print("[GRM Inv] запись с битым ключом восстановлена → " .. sid)
                end
            end
        end
        if not Inventories[sid] then Inventories[sid] = { slots = {} } end
        return normalizeSlots(Inventories[sid])
    end

    function GRM.Inventory.GetPlayerInv(ply)
        if not IsValid(ply) then return nil end
        local key, sid = inventoryKey(ply)
        if not key then return nil end

        -- No character core / no character key: exact old behavior for compatibility and old rescue tests.
        if key == sid then return getLegacySteamInv(ply, sid) end

        -- Character inventory: migrate old SteamID64 inventory into char1 only.
        if not Inventories[key] and Inventories[sid] and tostring(key):find(tostring(sid) .. ":char1", 1, true) == 1 then
            Inventories[key] = normalizeSlots(Inventories[sid])
            Inventories[sid] = nil
            saveSoon("migrate sid64 inventory -> char1")
            print("[GRM Inv] инвентарь SteamID64 перенесён на CharacterKey → " .. tostring(key))
        end

        if not Inventories[key] then Inventories[key] = { slots = {} } end
        return normalizeSlots(Inventories[key])
    end

    -- ── Синхронизация с клиентом ─────────────────────────────────
    function GRM.Inventory.SyncToClient(ply)
        if not IsValid(ply) then return end
        local inv = GRM.Inventory.GetPlayerInv(ply)
        if not inv then return end
        net.Start("grm_inv_sync")
            net.WriteTable(inv.slots or {})
        net.Send(ply)
    end

    function GRM.Inventory.SyncSlot(ply, slotIdx)
        if not IsValid(ply) then return end
        local inv = GRM.Inventory.GetPlayerInv(ply)
        if not inv then return end
        net.Start("grm_inv_update_slot")
            net.WriteUInt(slotIdx, 8)
            net.WriteTable(inv.slots[slotIdx] or {})
        net.Send(ply)
    end

    -- ── Добавить предмет в инвентарь ─────────────────────────────
    -- Возвращает: количество, которое НЕ удалось добавить (0 = всё добавлено)
    -- Код 99: необязательный data — данные экземпляра (подбор с земли:
    -- grm_item_drop возвращает включённое состояние модулятора и т.п.).
    -- Применяется только к НОВОМУ слоту (слияние в существующий стак
    -- данные жертвы не трогает — они остаются у стака-приёмника).
    function GRM.Inventory.AddItem(ply, itemID, count, data)
        if not IsValid(ply) then return count end
        if ply:GetNWBool("GRM_Arrested", false) then return count or 1 end
        local inv = GRM.Inventory.GetPlayerInv(ply)
        if not inv then return count end

        local def = GRM.Inventory.GetItemDef(itemID)
        if not def then return count end

        count = count or 1
        local maxStack = GRM.Inventory.GetMaxStack(itemID)
        local remaining = count
        local extra = istable(data) and table.Copy(data) or nil

        -- Сначала пытаемся добавить в существующие стаки
        if def.type ~= "weapon" then
            for i = 1, GRM.Inventory.Config.MaxSlots do
                if remaining <= 0 then break end
                local slot = inv.slots[i]
                if slot and slot.id == itemID and (slot.count or 0) < maxStack then
                    local canAdd = math.min(remaining, maxStack - (slot.count or 0))
                    slot.count = (slot.count or 0) + canAdd
                    remaining = remaining - canAdd
                    GRM.Inventory.SyncSlot(ply, i)
                end
            end
        end

        -- Затем ищем пустые слоты
        while remaining > 0 do
            local emptySlot = nil
            for i = 1, GRM.Inventory.Config.MaxSlots do
                if not inv.slots[i] or not inv.slots[i].id then
                    emptySlot = i
                    break
                end
            end
            if not emptySlot then break end -- Инвентарь полон
            local toAdd = math.min(remaining, maxStack)
            inv.slots[emptySlot] = {
                id = itemID,
                count = toAdd,
            }
            if extra then
                inv.slots[emptySlot].data = table.Copy(extra)
                extra = nil -- данные экземпляра уходят только с первым новым слотом
            end
            remaining = remaining - toAdd
            GRM.Inventory.SyncSlot(ply, emptySlot)
        end

        local added = math.max(0, (tonumber(count) or 1) - remaining)
        if added > 0 then hook.Run("GRM_QuestEvent", ply, "inventory_gain", tostring(itemID), added, { source = "inventory" }) end
        saveSoon("add " .. tostring(itemID))
        return remaining
    end

    -- ── Добавить оружие в инвентарь ──────────────────────────────
    function GRM.Inventory.AddWeapon(ply, weaponClass, clip1, clip2)
        if not IsValid(ply) then return false end
        if ply:GetNWBool("GRM_Arrested", false) then return false end
        local inv = GRM.Inventory.GetPlayerInv(ply)
        if not inv then return false end

        -- Ищем пустой слот
        local emptySlot = nil
        for i = 1, GRM.Inventory.Config.MaxSlots do
            if not inv.slots[i] or not inv.slots[i].id then
                emptySlot = i
                break
            end
        end
        if not emptySlot then return false end -- Инвентарь полон

        inv.slots[emptySlot] = {
            id = "weapon:" .. weaponClass,
            count = 1,
            data = {
                class = weaponClass,
                clip1 = clip1 or 0,
                clip2 = clip2 or 0,
            }
        }
        GRM.Inventory.SyncSlot(ply, emptySlot)
        saveSoon("addweapon")
        return true
    end

    -- ── Удалить предмет из слота ─────────────────────────────────
    function GRM.Inventory.RemoveFromSlot(ply, slotIdx, count)
        if not IsValid(ply) then return false end
        local inv = GRM.Inventory.GetPlayerInv(ply)
        if not inv then return false end

        local slot = inv.slots[slotIdx]
        if not slot or not slot.id then return false end
        count = count or 1
        slot.count = (slot.count or 1) - count
        if slot.count <= 0 then
            inv.slots[slotIdx] = nil
        end
        GRM.Inventory.SyncSlot(ply, slotIdx)
        saveSoon("removefromslot")
        return true
    end

    -- ── Удалить предмет по ID ────────────────────────────────────
    function GRM.Inventory.RemoveItem(ply, itemID, count)
        if not IsValid(ply) then return count end
        local inv = GRM.Inventory.GetPlayerInv(ply)
        if not inv then return count end

        count = count or 1
        local remaining = count
        for i = 1, GRM.Inventory.Config.MaxSlots do
            if remaining <= 0 then break end
            local slot = inv.slots[i]
            if slot and slot.id == itemID then
                local toRemove = math.min(remaining, slot.count or 1)
                slot.count = (slot.count or 1) - toRemove
                remaining = remaining - toRemove
                if slot.count <= 0 then
                    inv.slots[i] = nil
                end
                GRM.Inventory.SyncSlot(ply, i)
            end
        end
        saveSoon("remove " .. tostring(itemID))
        return remaining
    end

    -- ── Подсчёт предмета в инвентаре ─────────────────────────────
    function GRM.Inventory.CountItem(ply, itemID)
        if not IsValid(ply) then return 0 end
        local inv = GRM.Inventory.GetPlayerInv(ply)
        if not inv then return 0 end

        local total = 0
        for i = 1, GRM.Inventory.Config.MaxSlots do
            local slot = inv.slots[i]
            if slot and slot.id == itemID then
                total = total + (slot.count or 1)
            end
        end
        return total
    end

    -- ── Проверить, есть ли свободные слоты ───────────────────────
    function GRM.Inventory.HasFreeSlot(ply)
        if not IsValid(ply) then return false end
        local inv = GRM.Inventory.GetPlayerInv(ply)
        if not inv then return false end

        for i = 1, GRM.Inventory.Config.MaxSlots do
            if not inv.slots[i] or not inv.slots[i].id then
                return true
            end
        end
        return false
    end

    -- ── Использование предмета ───────────────────────────────────
    local function useItem(ply, slotIdx)
        if not IsValid(ply) then return end
        local inv = GRM.Inventory.GetPlayerInv(ply)
        if not inv then return end

        local slot = inv.slots[slotIdx]
        if not slot or not slot.id then return end
        local itemID = slot.id

        -- Оружие — экипировать
        if string.StartWith(itemID, "weapon:") then
            local weaponClass = slot.data and slot.data.class
            if not weaponClass then return end

            -- Проверяем, нет ли уже этого оружия
            if ply:HasWeapon(weaponClass) then
                GRM.Notify(ply, "У вас уже есть это оружие", 255, 100, 100)
                return
            end
            local wep = ply:Give(weaponClass)
            if IsValid(wep) then
                if slot.data.clip1 and slot.data.clip1 > 0 then
                    wep:SetClip1(slot.data.clip1)
                end
                -- Удаляем из инвентаря
                inv.slots[slotIdx] = nil
                GRM.Inventory.SyncSlot(ply, slotIdx)
                GRM.Notify(ply, "Оружие экипировано", 100, 220, 100)
            end
            return
        end

        -- Патроны — добавить в запас
        local def = GRM.Inventory.GetItemDef(itemID)
        if not def then
            -- Код 106 (находка 123): тихий return прятал «мёртвую кнопку»
            -- (модулятор рации без дефа на перекошенной загрузке). Теперь
            -- мимо не пройти: игрок видит причину, админ — строку в консоли.
            GRM.Notify(ply, "Предмет «" .. tostring(itemID) .. "» не зарегистрирован (модуль не поднялся) — сообщите админу", 255, 140, 110)
            print("[GRM Inventory][!] useItem: нет дефа «" .. tostring(itemID) .. "» у " .. tostring(ply:Nick()))
            return
        end
        if def.type == "ammo" and def.ammoType then
            local amount = slot.count or 1
            ply:GiveAmmo(amount, def.ammoType, true)
            inv.slots[slotIdx] = nil
            GRM.Inventory.SyncSlot(ply, slotIdx)
            GRM.Notify(ply, "Получено " .. amount .. "x " .. def.name, 100, 220, 100)
            return
        end

        -- Предметы — использовать функцию.
        -- Код 109 (находка 126): ДИСПЕТЧЕР ЧЕРЕЗ РЕЕСТР UseHandlers.
        -- Захардкоженный if-elseif умер: раньше патч еды, не сумев
        -- расширить local-функцию useItem хуком, просто ЗАМЕНЯЛ net-ресивер
        -- «grm_inv_use» своей неполной копией — и обработчики radio_toggle/
        -- cash_to_wallet/mobile_open/medcard_view тихо умирали («жму
        -- Использовать — ничего», заказ владельца). Теперь: есть useFunc —
        -- обязан быть и зарегистрированный обработчик, иначе ВИДИМЫЙ отказ.
        if def.type == "item" and def.useFunc then
            local handler = (GRM.Inventory.UseHandlers or {})[def.useFunc]
            if not handler then
                GRM.Notify(ply, "«" .. tostring(def.name or itemID) .. "»: модуль-обработчик «" .. tostring(def.useFunc) .. "» не поднялся — сообщите админу", 255, 140, 110)
                print("[GRM Inventory][!] useItem: нет обработчика «" .. tostring(def.useFunc) .. "» (предмет «" .. tostring(itemID) .. "») у " .. tostring(ply:Nick()))
                return
            end
            local okH, err = pcall(handler, ply, slotIdx, slot, def)
            if not okH then
                GRM.Notify(ply, "«" .. tostring(def.name or itemID) .. "»: внутренняя ошибка модуля — сообщите админу", 255, 140, 110)
                print("[GRM Inventory][!] useItem: обработчик «" .. tostring(def.useFunc) .. "» упал: " .. tostring(err))
            end
            return
        end

        GRM.Notify(ply, "Этот предмет нельзя использовать", 255, 180, 60)
    end
    GRM.Inventory.UseItem = useItem -- Код 109: публичная точка (диагностика/сим)

    -- ── Встроенные обработчики useFunc (та же логика, что была захардко-
    -- жена в useItem, но теперь через реестр: единый путь для всех) ──
    GRM.Inventory.RegisterUseHandler("heal_25", function(ply, slotIdx, slot, def)
        if ply:Health() < ply:GetMaxHealth() then
            ply:SetHealth(math.min(ply:GetMaxHealth(), ply:Health() + 25))
            GRM.Inventory.RemoveFromSlot(ply, slotIdx, 1)
            GRM.Notify(ply, "Использовано: " .. tostring(def and def.name or "Аптечка"), 100, 220, 100)
        else
            GRM.Notify(ply, "Здоровье уже полное", 255, 180, 60)
        end
    end)
    GRM.Inventory.RegisterUseHandler("armor_15", function(ply, slotIdx, slot, def)
        if ply:Armor() < 100 then
            ply:SetArmor(math.min(100, ply:Armor() + 15))
            GRM.Inventory.RemoveFromSlot(ply, slotIdx, 1)
            GRM.Notify(ply, "Использовано: " .. tostring(def and def.name or "Бронежилет"), 100, 220, 100)
        else
            GRM.Notify(ply, "Броня уже полная", 255, 180, 60)
        end
    end)
    GRM.Inventory.RegisterUseHandler("cash_to_wallet", function(ply, slotIdx, slot, def)
        -- Деньги: число в стаке = сумма, обналичиваем ВЕСЬ стак
        local inv = GRM.Inventory.GetPlayerInv(ply)
        if not inv then return end
        local amt = math.max(0, math.floor(tonumber(slot.count) or 0))
        if amt > 0 and GRM.GiveMoney then
            inv.slots[slotIdx] = nil
            GRM.Inventory.SyncSlot(ply, slotIdx)
            GRM.GiveMoney(ply, amt, "Обналичены деньги из инвентаря")
            GRM.Notify(ply, "Обналичено: " .. (GRM.Format and GRM.Format(amt) or tostring(amt)), 100, 220, 100)
            hook.Run("GRM_Money_Cashed", ply, amt)
        end
    end)
    GRM.Inventory.RegisterUseHandler("mobile_open", function(ply, slotIdx, slot, def)
        -- Mobile contract: «Использовать» НЕ открывает UI. Оно активирует
        -- выбранную трубку как рабочую. Открыть меню: СТРЕЛКА ВВЕРХ.
        local inv = GRM.Inventory.GetPlayerInv(ply)
        if inv and inv.slots then
            for i, s in pairs(inv.slots) do
                if s and s.id and GRM.Mobile and GRM.Mobile.IsMobileItem and GRM.Mobile.IsMobileItem(s.id) then
                    s.data = istable(s.data) and s.data or {}
                    s.data.active = (i == slotIdx)
                    GRM.Inventory.SyncSlot(ply, i)
                end
            end
            saveSoon("mobile activate")
        else
            slot.data = istable(slot.data) and slot.data or {}
            slot.data.active = true
            GRM.Inventory.SyncSlot(ply, slotIdx)
            saveSoon("mobile activate")
        end
        if GRM.Mobile and GRM.Mobile.PushState then GRM.Mobile.PushState(ply) end
        GRM.Notify(ply, "Телефон активирован. Открыть — СТРЕЛКА ВВЕРХ, закрыть — СТРЕЛКА ВНИЗ.", 100, 220, 100)
    end)
    GRM.Inventory.RegisterUseHandler("radio_toggle", function(ply, slotIdx, slot, def)
        -- Код 99: переносной модулятор рации — ВКЛ/ВЫКЛ живёт в данных
        -- самого предмета: рестарт/дроп/подбор состояние не теряют.
        -- Предмет НЕ тратится. Доступ к /freq и /r проверяет RadioNet
        -- (RN.HasRadioUnit: предмет в инвентаре И data.on == true).
        slot.data = istable(slot.data) and slot.data or {}
        slot.data.on = not (slot.data.on == true)
        GRM.Inventory.SyncSlot(ply, slotIdx)
        saveSoon("радио-модулятор on=" .. tostring(slot.data.on))
        if slot.data.on then
            GRM.Notify(ply, "Модулятор ВКЛ: /freq 145.5 — частота, /r текст — эфир", 120, 210, 255)
        else
            GRM.Notify(ply, "Модулятор ВЫКЛ — радиочастоты закрыты", 255, 200, 90)
        end
        if slot.data.on and GRM.RadioNet and GRM.RadioNet.FreqInfo then
            GRM.RadioNet.FreqInfo(ply)
        end
    end)
    GRM.Inventory.RegisterUseHandler("medcard_view", function(ply, slotIdx, slot, def)
        -- Код 101: медицинская карта на руках — предмет НЕ тратится.
        -- sid64 владельца лежит в slot.data (выдача/дроп/подбор).
        if GRM.Medical and GRM.Medical.ViewIssued then
            GRM.Medical.ViewIssued(ply, slot.data)
        else
            GRM.Notify(ply, "Модуль медкарт не загружен", 255, 140, 110)
        end
    end)
    GRM.Inventory.RegisterUseHandler("augment_chip_implant", function(ply, slotIdx, slot, def)
        -- Чип аугментации: использование открывает меню имплантации
        if GRM.AugChips and GRM.AugChips.OpenImplantMenu then
            -- Передаем slotIdx в chipData для последующего удаления из инвентаря
            local chipData = slot.data or {}
            chipData.slotIdx = slotIdx
            GRM.AugChips.OpenImplantMenu(ply, chipData)
            -- Предмет НЕ тратится при открытии меню, тратится при успешной имплантации
        else
            GRM.Notify(ply, "Модуль аугментаций не загружен", 255, 140, 110)
        end
    end)

    -- ── Выброс предмета ──────────────────────────────────────────
    local function dropItem(ply, slotIdx, count)
        if not IsValid(ply) then return end
        local inv = GRM.Inventory.GetPlayerInv(ply)
        if not inv then return end

        local slot = inv.slots[slotIdx]
        if not slot or not slot.id then return end
        local sdata = istable(slot.data) and slot.data or {}
        local DOC = GRM.Documents
        if DOC and DOC.PhysicalRecord then
            local owner = tostring(sdata.ownerKey or "")
            local typ = sdata.docType
            if owner ~= "" and typ then
                local rec = DOC.PhysicalRecord(owner, typ)
                if istable(rec) and rec.unlosable == true then
                    if GRM.Notify then GRM.Notify(ply, "Этот документ помечен как нетеряемый — выбросить нельзя.", 255, 180, 90) end
                    return
                end
            end
        end
        count = math.min(count or 1, slot.count or 1)
        if count <= 0 then return end

        -- Создаём entity дропа
        local ent = ents.Create("grm_item_drop")
        if not IsValid(ent) then return end

        local pos = ply:GetPos() + ply:GetForward() * GRM.Inventory.Config.DropDistance + Vector(0, 0, 20)
        ent:SetPos(pos)
        ent:SetAngles(Angle(0, math.random(0, 360), 0))
        -- ItemID и данные экземпляра должны быть установлены ДО Spawn:
        -- Initialize выбирает по ним модель (документ → бланк/clipboard).
        ent:SetItemID(slot.id)
        ent:SetItemCount(count)
        local dropDef = GRM.Inventory.GetItemDef(slot.id)
        if dropDef and dropDef.name then ent:SetDisplayName(tostring(dropDef.name)) end
        if slot.data then ent.ItemData = table.Copy(slot.data) end
        ent:Spawn()

        local phys = ent:GetPhysicsObject()
        if IsValid(phys) then
            phys:SetVelocity(ply:GetForward() * 150 + Vector(0, 0, 80))
        end

        -- Удаляем из инвентаря
        slot.count = (slot.count or 1) - count
        if slot.count <= 0 then
            inv.slots[slotIdx] = nil
        end
        GRM.Inventory.SyncSlot(ply, slotIdx)

        GRM.Notify(ply, "Выброшено", 100, 220, 100)
    end

    -- ── Перемещение предмета между слотами ───────────────────────
    local function moveItem(ply, fromSlot, toSlot)
        if not IsValid(ply) then return end
        if fromSlot == toSlot then return end
        if fromSlot < 1 or fromSlot > GRM.Inventory.Config.MaxSlots then return end
        if toSlot < 1 or toSlot > GRM.Inventory.Config.MaxSlots then return end

        local inv = GRM.Inventory.GetPlayerInv(ply)
        if not inv then return end

        local from = inv.slots[fromSlot]
        local to = inv.slots[toSlot]

        if not from or not from.id then return end

        -- Если целевой слот пуст — просто перемещаем
        if not to or not to.id then
            inv.slots[toSlot] = from
            inv.slots[fromSlot] = nil
        -- Если тот же предмет — пытаемся стакировать
        elseif to.id == from.id and not string.StartWith(from.id, "weapon:") then
            local maxStack = GRM.Inventory.GetMaxStack(from.id)
            local canAdd = math.min(from.count or 1, maxStack - (to.count or 0))
            if canAdd > 0 then
                to.count = (to.count or 0) + canAdd
                from.count = (from.count or 1) - canAdd
                if from.count <= 0 then
                    inv.slots[fromSlot] = nil
                end
            else
                -- Меняем местами
                inv.slots[fromSlot] = to
                inv.slots[toSlot] = from
            end
        else
            -- Разные предметы — меняем местами
            inv.slots[fromSlot] = to
            inv.slots[toSlot] = from
        end

        GRM.Inventory.SyncSlot(ply, fromSlot)
        GRM.Inventory.SyncSlot(ply, toSlot)
    end

    -- ── Разделение стака ─────────────────────────────────────────
    local function splitStack(ply, slotIdx, splitCount)
        if not IsValid(ply) then return end
        local inv = GRM.Inventory.GetPlayerInv(ply)
        if not inv then return end

        local slot = inv.slots[slotIdx]
        if not slot or not slot.id then return end
        if string.StartWith(slot.id, "weapon:") then return end
        if (slot.count or 1) <= 1 then return end

        splitCount = math.Clamp(splitCount, 1, (slot.count or 1) - 1)

        -- Ищем пустой слот
        local emptySlot = nil
        for i = 1, GRM.Inventory.Config.MaxSlots do
            if not inv.slots[i] or not inv.slots[i].id then
                emptySlot = i
                break
            end
        end
        if not emptySlot then
            GRM.Notify(ply, "Нет свободных слотов", 255, 100, 100)
            return
        end

        slot.count = slot.count - splitCount
        inv.slots[emptySlot] = {
            id = slot.id,
            count = splitCount,
        }

        GRM.Inventory.SyncSlot(ply, slotIdx)
        GRM.Inventory.SyncSlot(ply, emptySlot)
    end

    -- ── Убрать оружие в инвентарь (из рук) ───────────────────────
    function GRM.Inventory.StoreActiveWeapon(ply)
        if not IsValid(ply) then return false end
        local wep = ply:GetActiveWeapon()
        if not IsValid(wep) then
            GRM.Notify(ply, "Нет активного оружия", 255, 100, 100)
            return false
        end

        local class = wep:GetClass()
        if class == "weapon_fists" then
            GRM.Notify(ply, "Кулаки нельзя убрать в инвентарь", 255, 100, 100)
            return false
        end

        local clip1 = wep:Clip1()
        local clip2 = wep:Clip2()

        if not GRM.Inventory.HasFreeSlot(ply) then
            GRM.Notify(ply, "Инвентарь полон!", 255, 100, 100)
            return false
        end

        local ok = GRM.Inventory.AddWeapon(ply, class, clip1, clip2)
        if ok then
            ply:StripWeapon(class)
            GRM.Notify(ply, "Оружие убрано в инвентарь", 100, 220, 100)
            return true
        end
        return false
    end

    -- ── Подбор патронов с игрока (при смерти или вручную) ─────────
    function GRM.Inventory.StoreAmmoFromPlayer(ply, ammoType, amount)
        if not IsValid(ply) or amount <= 0 then return 0 end

        -- Находим itemID по ammoType
        local itemID = nil
        for id, def in pairs(GRM.Inventory.ItemDefs) do
            if def.type == "ammo" and def.ammoType == ammoType then
                itemID = id
                break
            end
        end
        if not itemID then return amount end

        local notAdded = GRM.Inventory.AddItem(ply, itemID, amount)
        local added = amount - notAdded
        if added > 0 then
            ply:RemoveAmmo(added, ammoType)
        end
        return notAdded
    end

    -- ── Сетевые обработчики ──────────────────────────────────────
    -- Открытие инвентаря
    -- ── АДМИН: просмотр и изъятие предметов из чужого инвентаря (находка 170) ──
    -- Админ смотрит на игрока и через C-меню открывает его инвентарь.
    net.Receive("GRM_Inv_AdminOpen", function(_, admin)
        if not IsValid(admin) or not admin:IsSuperAdmin() then return end
        local idx = net.ReadUInt(16)
        local target = nil
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(p) and p:EntIndex() == idx then target = p break end
        end
        if not IsValid(target) then
            net.Start("GRM_Inv_AdminData") net.WriteUInt(0, 16) net.WriteTable({}) net.Send(admin)
            return
        end
        local inv = GRM.Inventory.GetPlayerInv(target)
        net.Start("GRM_Inv_AdminData")
            net.WriteUInt(idx, 16)
            net.WriteTable(inv and inv.slots or {})
        net.Send(admin)
    end)

    -- Админ изымает предмет: удаляем из инвентаря цели, синкаем обоим
    net.Receive("GRM_Inv_AdminAction", function(_, admin)
        if not IsValid(admin) or not admin:IsSuperAdmin() then return end
        local idx = net.ReadUInt(16)
        local slotIdx = net.ReadUInt(8)
        local count = math.max(1, math.floor(tonumber(net.ReadUInt(16)) or 1))
        local op = net.ReadString()
        local target = nil
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(p) and p:EntIndex() == idx then target = p break end
        end
        if not IsValid(target) then return end
        local inv = GRM.Inventory.GetPlayerInv(target)
        local slot = inv and inv.slots[slotIdx] or nil
        if not slot then return end
        local id = slot.id

        if op == "dup" then
            -- МНОЖЕНИЕ/КОПИРОВАНИЕ (находка 171): добавить столько же предметов
            -- с сохранением data экземпляра (рация/медкарта/чип и т.п.)
            local have = tonumber(slot.count) or 1
            local addCount = math.max(1, count)
            local data = istable(slot.data) and table.Copy(slot.data) or nil
            local left = GRM.Inventory.AddItem(target, id, addCount, data)
            local added = addCount - (tonumber(left) or 0)
            if added > 0 then
                GRM.Inventory.SyncToClient(target)
                if GRM.Inventory.SyncToClient then GRM.Inventory.SyncToClient(admin) end
                if GRM.Notify then
                    GRM.Notify(admin, "Дублировано у " .. target:Nick() .. ": " .. tostring(id) .. " x" .. tostring(added), 100, 220, 130)
                end
            else
                if GRM.Notify then GRM.Notify(admin, "Не удалось добавить (инвентарь полон?)", 255, 150, 90) end
            end
        else
            -- ИЗЪЯТИЕ
            local have = tonumber(slot.count) or 1
            local remove = math.min(count, have)
            local left = GRM.Inventory.RemoveItem(target, id, remove)
            local removed = remove - (tonumber(left) or 0)
            if removed > 0 then
                GRM.Inventory.SyncToClient(target)
                if GRM.Inventory.SyncToClient then GRM.Inventory.SyncToClient(admin) end
                if GRM.Notify then
                    GRM.Notify(target, "Администрация изъяла: " .. tostring(id) .. " x" .. tostring(removed), 255, 120, 100)
                    GRM.Notify(admin, "Изъято у " .. target:Nick() .. ": " .. tostring(id) .. " x" .. tostring(removed), 100, 220, 130)
                end
            end
        end
        -- обновить данные админу
        local inv2 = GRM.Inventory.GetPlayerInv(target)
        net.Start("GRM_Inv_AdminData")
            net.WriteUInt(idx, 16)
            net.WriteTable(inv2 and inv2.slots or {})
        net.Send(admin)
    end)

    --[[ Отбывающий административное наказание не пользуется инвентарём:
         одна проверка на все действия — открытие, использование, выброс,
         перенос, разделение и уборка оружия. ]]
    local function banGate(ply, what)
        return GRM.ServerBan and GRM.ServerBan.DenySpeech
            and GRM.ServerBan.DenySpeech(ply, what or "инвентарь") == true
    end

    net.Receive("grm_inv_open", function(_, ply)
        if banGate(ply, "инвентарь") then return end
        GRM.Inventory.SyncToClient(ply)
        net.Start("grm_inv_open")
        net.Send(ply)
    end)

    -- Использование предмета
    net.Receive("grm_inv_use", function(_, ply)
        if banGate(ply, "использование предметов") then return end
        local slotIdx = net.ReadUInt(8)
        useItem(ply, slotIdx)
        saveSoon("use")
    end)

    -- Выброс предмета
    net.Receive("grm_inv_drop", function(_, ply)
        if banGate(ply, "выброс предметов") then return end
        local slotIdx = net.ReadUInt(8)
        local count = net.ReadUInt(16)
        dropItem(ply, slotIdx, count)
        saveSoon("drop")
    end)

    -- Перемещение предмета
    net.Receive("grm_inv_move", function(_, ply)
        if banGate(ply, "инвентарь") then return end
        local fromSlot = net.ReadUInt(8)
        local toSlot = net.ReadUInt(8)
        moveItem(ply, fromSlot, toSlot)
        saveSoon("move")
    end)

    -- Разделение стака
    net.Receive("grm_inv_split", function(_, ply)
        if banGate(ply, "инвентарь") then return end
        local slotIdx = net.ReadUInt(8)
        local splitCount = net.ReadUInt(16)
        splitStack(ply, slotIdx, splitCount)
        saveSoon("split")
    end)

    -- Действие (убрать оружие)
    net.Receive("grm_inv_action", function(_, ply)
        if banGate(ply, "инвентарь") then return end
        local action = net.ReadString()
        if action == "store_weapon" then
            GRM.Inventory.StoreActiveWeapon(ply)
            saveSoon("store_weapon")
        end
    end)

    -- ── Хуки ─────────────────────────────────────────────────────
    hook.Add("PlayerInitialSpawn", "GRM_Inv_Join", function(ply)
        timer.Simple(3, function()
            if IsValid(ply) then
                GRM.Inventory.SyncToClient(ply)
            end
        end)
    end)

    hook.Add("GRM_CharacterChanged","GRM_Inv_CharacterSave",function(ply)
        saveInventories("character switch");timer.Simple(.1,function()if IsValid(ply)then GRM.Inventory.SyncToClient(ply)end end)
    end)
    hook.Add("PlayerDisconnected", "GRM_Inv_Leave", function(ply)
        saveInventories("disconnect")
    end)

    hook.Add("ShutDown", "GRM_Inv_Shutdown", function()
        saveInventories()
    end)

    -- ── Чат-команды ──────────────────────────────────────────────

    -- ── /drop — выбросить активное оружие на землю ───────────
    function GRM.Inventory.DropActiveWeapon(ply)
        if not IsValid(ply) or not ply:IsPlayer() then return false end
        local wep = ply:GetActiveWeapon()
        if not IsValid(wep) then
            if GRM.Notify then GRM.Notify(ply, "Нет оружия в руках", 255, 180, 60) end
            return false
        end
        local class = wep:GetClass()
        if class == "weapon_fists" or class == "weapon_physgun" or class == "gmod_tool"
            or class == "weapon_physcannon" or class == "weapon_crowbar" then
            if GRM.Notify then GRM.Notify(ply, "Это нельзя выбросить", 255, 180, 60) end
            return false
        end
        -- SWEP наручников / ключей — не дропаем служебное
        if class == "grm_handcuffs" or class == "grm_cuffed" or class == "grm_keyring" then
            if GRM.Notify then GRM.Notify(ply, "Служебное оружие нельзя выбросить", 255, 180, 60) end
            return false
        end

        local itemID = "weapon:" .. class

        local ent = ents.Create("grm_item_drop")
        if not IsValid(ent) then
            -- fallback: engine drop
            ply:DropWeapon(wep)
            if GRM.Notify then GRM.Notify(ply, "Оружие выброшено (fallback)", 100, 220, 100) end
            return true
        end

        local dist = (GRM.Inventory.Config and GRM.Inventory.Config.DropDistance) or 80
        local pos = ply:GetShootPos() + ply:GetAimVector() * 40
        -- slightly forward of player feet if aim is bad
        if not pos or pos:DistToSqr(ply:GetPos()) > 40000 then
            pos = ply:GetPos() + ply:GetForward() * dist + Vector(0, 0, 30)
        end
        ent:SetPos(pos)
        ent:SetAngles(Angle(0, ply:EyeAngles().y, 0))
        ent:SetItemID(itemID)
        ent:SetItemCount(1)
        ent:SetDisplayName(wep:GetPrintName() ~= "" and wep:GetPrintName() or class)
        -- Не сохраняем clip1/clip2 — при подборе оружие даётся с дефолтными патронами (ply:Give)
        -- Иначе ply:Give добавляет патроны в резерв + clip1 из data = дублирование (баг)
        ent.ItemData = { class = class }
        ent:Spawn()
        ent:Activate()

        local phys = ent:GetPhysicsObject()
        if IsValid(phys) then
            phys:SetVelocity(ply:GetAimVector() * 180 + Vector(0, 0, 60))
        end

        ply:StripWeapon(class)
        if GRM.Notify then GRM.Notify(ply, "Оружие выброшено: " .. (ent:GetDisplayName() or class), 100, 220, 100) end
        return true
    end

    hook.Add("PlayerSay", "GRM_Inv_ChatCmds", function(ply, text)
        local cmd = string.Trim(string.lower(text or ""))
        local args = string.Explode(" ", cmd)
        local c0 = args[1] or ""

        if c0 == "/inv" or c0 == "/inventory" or c0 == "!inv" or c0 == "!inventory" then
            GRM.Inventory.SyncToClient(ply)
            net.Start("grm_inv_open")
            net.Send(ply)
            return ""
        end

        if c0 == "/store" or c0 == "!store" then
            GRM.Inventory.StoreActiveWeapon(ply)
            return ""
        end

        -- /drop — оружие из рук на землю (entity grm_item_drop)
        if c0 == "/drop" or c0 == "!drop" or c0 == "/dropweapon" or c0 == "!dropweapon" then
            GRM.Inventory.DropActiveWeapon(ply)
            return ""
        end
    end)

    print("[GRM] Inventory v1.7.0 (Код 109) — сервер загружен")
end

-- ================================================================
--  КЛИЕНТ
-- ================================================================
if CLIENT then
    GRM.Inventory.LocalSlots = GRM.Inventory.LocalSlots or {}

    net.Receive("grm_inv_sync", function()
        GRM.Inventory.LocalSlots = net.ReadTable() or {}
        hook.Run("GRM_InventoryUpdated")
    end)

    net.Receive("grm_inv_update_slot", function()
        local idx = net.ReadUInt(8)
        local data = net.ReadTable()
        if data and data.id then
            GRM.Inventory.LocalSlots[idx] = data
        else
            GRM.Inventory.LocalSlots[idx] = nil
        end
        hook.Run("GRM_InventoryUpdated")
    end)

    net.Receive("grm_inv_open", function()
        GRM.Inventory.OpenGUI()
    end)

    -- ── АДМИН: просмотр чужого инвентаря (находка 170) ──
    -- Суперадмин через C-меню открывает инвентарь игрока: видит слоты и
    -- может изымать предметы кнопками «Изъять 1» / «Изъять все».
    GRM.Inventory.AdminView = GRM.Inventory.AdminView or { target = nil, slots = {}, open = false }
    local AV = GRM.Inventory.AdminView

    function GRM.Inventory.OpenAdminView(targetIdx)
        AV.target = targetIdx
        AV.open = true
        -- показываем поверх обычного инвентаря отдельное окно
        if GRM.Inventory.OpenGUI then GRM.Inventory.OpenGUI() end
    end

    function GRM.Inventory.CloseAdminView()
        AV.open = false
        AV.target = nil
        AV.slots = {}
    end

    net.Receive("GRM_Inv_AdminData", function()
        local idx = net.ReadUInt(16)
        local slots = net.ReadTable() or {}
        AV.target = idx
        AV.slots = slots
        AV.open = true
        hook.Run("GRM_InventoryUpdated")
    end)

    -- Админ изымает предмет (1 шт или все)
    function GRM.Inventory.AdminTake(slotIdx, all)
        if not AV.open or not AV.target then return end
        local slot = AV.slots[slotIdx]
        if not slot or not slot.id then return end
        local count = all and (tonumber(slot.count) or 1) or 1
        net.Start("GRM_Inv_AdminAction")
            net.WriteUInt(AV.target, 16)
            net.WriteUInt(slotIdx, 8)
            net.WriteUInt(count, 16)
            net.WriteString("take")
        net.SendToServer()
    end

    -- МНОЖЕНИЕ/КОПИРОВАНИЕ (находка 171): дублировать предмет цели
    function GRM.Inventory.AdminDup(slotIdx, count)
        if not AV.open or not AV.target then return end
        local slot = AV.slots[slotIdx]
        if not slot or not slot.id then return end
        local c = math.max(1, math.floor(tonumber(count) or 1))
        net.Start("GRM_Inv_AdminAction")
            net.WriteUInt(AV.target, 16)
            net.WriteUInt(slotIdx, 8)
            net.WriteUInt(c, 16)
            net.WriteString("dup")
        net.SendToServer()
    end

    -- Запрос открытия
    function GRM.Inventory.RequestOpen()
        net.Start("grm_inv_open")
        net.SendToServer()
    end

    -- Действия
    function GRM.Inventory.UseSlot(slotIdx)
        net.Start("grm_inv_use")
            net.WriteUInt(slotIdx, 8)
        net.SendToServer()
    end

    function GRM.Inventory.DropSlot(slotIdx, count)
        net.Start("grm_inv_drop")
            net.WriteUInt(slotIdx, 8)
            net.WriteUInt(count or 1, 16)
        net.SendToServer()
    end

    function GRM.Inventory.MoveSlot(fromSlot, toSlot)
        net.Start("grm_inv_move")
            net.WriteUInt(fromSlot, 8)
            net.WriteUInt(toSlot, 8)
        net.SendToServer()
    end

    function GRM.Inventory.SplitSlot(slotIdx, count)
        net.Start("grm_inv_split")
            net.WriteUInt(slotIdx, 8)
            net.WriteUInt(count, 16)
        net.SendToServer()
    end

    function GRM.Inventory.StoreWeapon()
        net.Start("grm_inv_action")
            net.WriteString("store_weapon")
        net.SendToServer()
    end

    --[[ КЛАВИША ОТКРЫТИЯ (заказ владельца 31.08: «в F4 в настройки
         нужна позиция для бинда кнопки открытия инвентаря»).

         Здесь была ПУСТАЯ заглушка: хук висел, тело — комментарий
         «можно добавить бинд». Инвентарь открывался только командой
         /inv или из C-меню.

         Значение по умолчанию 0 — выключено. Ставить сюда I нельзя:
         в GMod эта клавиша занята под другое, и молча перехватывать
         её у игрока неправильно. Клавишу назначает сам игрок в
         F4 → Настройки. ]]
    CreateClientConVar("grm_cl_inv_key", "0", true, false,
        "Клавиша открытия инвентаря (KEY_*, 0 = выключено)")

    --[[ РЕЖИМ УДЕРЖАНИЯ (заказ владельца 31.08: «инвентарь надо сделать
         удерживаемым, если он активируется на бинд»).

         Работает как радиальное меню соц.анимаций: зажал — окно
         открыто, отпустил — закрылось. Так же, как там, короткое
         НАЖАТИЕ оставляет окно висеть: клавишу отпускают через
         считанные миллисекунды, и без этого порога окно закрывалось бы
         в том же кадре, в котором открылось.

         Выключается конваром: кому-то привычнее обычный переключатель. ]]
    CreateClientConVar("grm_cl_inv_hold", "1", true, false,
        "1 — инвентарь открыт, пока держите клавишу; 0 — переключатель")

    local invKeyLock = 0
    local invOpenedAt = 0
    local invHoldArmed = false

    hook.Add("PlayerButtonDown", "GRM_Inv_Bind", function(ply, key)
        if ply ~= LocalPlayer() then return end
        local want = math.floor(GetConVarNumber("grm_cl_inv_key") or 0)
        if want <= 0 or key ~= want then return end
        -- Не мешаем набору текста и открытому игровому меню.
        if gui.IsGameUIVisible() or gui.IsConsoleVisible() then return end
        if IsValid(ply) and ply.IsTyping and ply:IsTyping() then return end
        -- Защита от дребезга: удержание клавиши шлёт событие пачкой.
        local now = RealTime()
        if now < invKeyLock then return end
        invKeyLock = now + 0.3
        --[[ Повторное нажатие ЗАКРЫВАЕТ окно: клавиша работает
             переключателем, как и ожидается от инвентаря. Без этого
             игрок жал бы клавишу и лез мышью к крестику. ]]
        if GRM.Inventory.IsOpen and GRM.Inventory.IsOpen() then
            invHoldArmed = false
            if GRM.Inventory.CloseGUI then GRM.Inventory.CloseGUI() end
            return
        end
        invOpenedAt = now
        invHoldArmed = GetConVarNumber("grm_cl_inv_hold") ~= 0
        GRM.Inventory.RequestOpen()
    end)

    --[[ Отпустили клавишу — закрываем, если это было именно удержание.

         Порог 0.25 с тот же, что у радиального меню: за меньшее время
         клавишу отпускают при обычном клике, и окно исчезло бы
         мгновенно.

         IsBusy: пока предмет тащат мышью или открыто контекстное меню,
         не закрываем — иначе перетаскивание оборвётся на полпути, а
         меню останется висеть поверх игры без своего окна. Окно в этом
         случае просто остаётся открытым, и закрыть его можно обычным
         повторным нажатием клавиши или крестиком. ]]
    hook.Add("PlayerButtonUp", "GRM_Inv_BindUp", function(ply, key)
        if ply ~= LocalPlayer() then return end
        if not invHoldArmed then return end
        if key ~= math.floor(GetConVarNumber("grm_cl_inv_key") or 0) then return end
        if RealTime() - invOpenedAt < 0.25 then
            -- Короткое нажатие: окно остаётся, дальше работает как обычно.
            invHoldArmed = false
            return
        end
        if GRM.Inventory.IsBusy and GRM.Inventory.IsBusy() then return end
        invHoldArmed = false
        if GRM.Inventory.IsOpen and GRM.Inventory.IsOpen() then
            if GRM.Inventory.CloseGUI then GRM.Inventory.CloseGUI() end
        end
    end)

    --[[ Команда работает ПЕРЕКЛЮЧАТЕЛЕМ (баг 31.08).

         Раньше она только открывала. C-меню зовёт именно её («Инвентарь»
         в быстром доступе), поэтому окно, открытое оттуда, клавишей уже
         не закрывалось: бинд видел открытое окно и закрывал его, а
         кнопка C-меню — открывала заново. Владелец описал это как «у
         него свой режим открытия».

         Теперь оба входа ведут себя одинаково. ]]
    concommand.Add("grm_inventory", function()
        if GRM.Inventory.IsOpen and GRM.Inventory.IsOpen() then
            if GRM.Inventory.CloseGUI then GRM.Inventory.CloseGUI() return end
        end
        GRM.Inventory.RequestOpen()
    end)

    print("[GRM] Inventory v1.7.0 — клиент загружен")
end

-- Вечер-18: единый словарь slash-команд: имена живого PlayerSay-обработчика
-- вносятся во внешний реестр библиотеки (на режиме сверка идёт ДО ParseSay —
-- без регистрации команда стала бы «неизвестной»).
if GRM and GRM.Chat and GRM.Chat.RegisterExternalCommands then
    GRM.Chat.RegisterExternalCommands({ "/drop", "/dropweapon", "/inv", "/inventory", "/store" })
end
