--[[--------------------------------------------------------------------
    GRM Phone Shop v2
    Полноценный магазин телефонного оборудования.

    Возможности:
      • Интерактивная админ-панель цен и товаров.
      • Добавление товара в магазин из entity под прицелом.
      • Покупка постоянного доступа к товару.
      • Спавн купленного оборудования игроком.
      • Лимиты на заспавненное оборудование.
      • Сохранение каталога, покупок и заспавненного оборудования.
      • Интеграция с GRM Currency.
      • Спецоборудование может требовать доступ через /phone_access.

    Команды игрока:
      /phoneshop, !phoneshop, /teleshop, grm_phone_shop
      /phone_remove, !phone_remove, grm_phone_remove_owned

    Команды админа:
      /phoneshop_admin, !phoneshop_admin, grm_phone_shop_admin
      grm_phone_shop_add_look
      grm_phone_shop_reload
--------------------------------------------------------------------]]

if SERVER then
    AddCSLuaFile()
end

GRM = GRM or {}
GRM.Phone = GRM.Phone or {}
GRM.Phone.Shop = GRM.Phone.Shop or {}
local SHOP = GRM.Phone.Shop

local NET_OPEN          = "GRM_PhoneShop_Open"
local NET_DATA          = "GRM_PhoneShop_Data"
local NET_BUY_ACCESS    = "GRM_PhoneShop_BuyAccess"
local NET_SPAWN         = "GRM_PhoneShop_Spawn"
local NET_REMOVE        = "GRM_PhoneShop_Remove"
local NET_RESULT        = "GRM_PhoneShop_Result"
local NET_ADMIN_OPEN    = "GRM_PhoneShop_AdminOpen"
local NET_ADMIN_DATA    = "GRM_PhoneShop_AdminData"
local NET_ADMIN_SAVE    = "GRM_PhoneShop_AdminSave"
local NET_ADMIN_DELETE  = "GRM_PhoneShop_AdminDelete"
local NET_ADMIN_ADDLOOK = "GRM_PhoneShop_AdminAddLook"
local NET_ADMIN_RESET   = "GRM_PhoneShop_AdminReset"

local DATA_DIR = "grm_phone"
local CATALOG_FILE = DATA_DIR .. "/shop_catalog.json"
local PURCHASES_FILE = DATA_DIR .. "/shop_purchases.json"
local EQUIPMENT_FILE = DATA_DIR .. "/player_equipment.json"

local function cfg()
    return SHOP.Config or {}
end

local function ensureDir()
    if not file.Exists(DATA_DIR, "DATA") then file.CreateDir(DATA_DIR) end
end

local function readJSON(path, fallback)
    fallback = fallback or {}
    if not file.Exists(path, "DATA") then return table.Copy(fallback) end
    local raw = file.Read(path, "DATA") or ""
    if raw == "" then return table.Copy(fallback) end
    local ok, data = pcall(util.JSONToTable, raw)
    if ok and istable(data) then return data end
    return table.Copy(fallback)
end

local function writeJSON(path, data)
    ensureDir()
    file.Write(path, util.TableToJSON(data or {}, true))
end

local function moneyName(amount)
    if GRM and GRM.Format then return GRM.Format(amount) end
    return tostring(amount) .. " GRM"
end

local function canPay(ply, amount)
    if not GRM or not GRM.HasMoney then return true end
    return GRM.HasMoney(ply, amount)
end

local function takeMoney(ply, amount)
    if GRM and GRM.TakeMoney then GRM.TakeMoney(ply, amount) end
end

local function giveMoney(ply, amount)
    if GRM and GRM.GiveMoney then GRM.GiveMoney(ply, amount) end
end

local function steamID(ply)
    if not IsValid(ply) then return "" end
    if GRM.Identity and GRM.Identity.CharacterKey then return GRM.Identity.CharacterKey(ply) end
    local sid64 = ply:SteamID64()
    if sid64 and sid64 ~= "0" then return sid64 end
    return ply:SteamID()
end

local function sanitizeID(s)
    s = string.lower(tostring(s or ""))
    s = string.gsub(s, "[^%w_%-]", "_")
    s = string.Trim(s, "_")
    if s == "" then s = "item" .. tostring(os.time()) end
    return s
end

local function defaultCatalog()
    return {
        phone = {
            id = "phone",
            name = "Стационарный телефон",
            desc = "Обычный стационарный телефон для линии связи.",
            class = "grm_phone",
            model = "models/props/cs_office/phone.mdl",
            price = 500,
            enabled = true,
            special = false,
            maxOwned = 4,
            spawnFrozen = true,
        },
        payphone = {
            id = "payphone",
            name = "Телефонная будка / Таксофон",
            desc = "Уличный телефон. Работает как обычный телефон.",
            class = "grm_payphone",
            model = "models/props_equipment/phone_booth.mdl",
            price = 1500,
            enabled = true,
            special = false,
            maxOwned = 2,
            spawnFrozen = true,
        },
        pbx = {
            id = "pbx",
            name = "АТС станция",
            desc = "Даёт линии связи для телефонов. По умолчанию 60 линий.",
            class = "grm_pbx_station",
            model = "models/props_lab/servers.mdl",
            price = 6000,
            enabled = true,
            special = true,
            maxOwned = 2,
            spawnFrozen = true,
            data = { exchange = "main", active = true, maxLines = 60 },
        },
        wiretap = {
            id = "wiretap",
            name = "Оборудование прослушки",
            desc = "Позволяет прослушивать номер или АТС. Требует доступ спецслужб.",
            class = "grm_phone_wiretap",
            model = "models/props_lab/reciever01a.mdl",
            price = 9000,
            enabled = true,
            special = true,
            maxOwned = 2,
            spawnFrozen = true,
            data = { target = "", exchange = "main", active = false },
        },
        terminal = {
            id = "terminal",
            name = "Компьютер мониторинга связи",
            desc = "Показывает активные телефоны, занятые линии и вызовы.",
            class = "grm_phone_terminal",
            model = "models/props_lab/monitor01b.mdl",
            price = 4500,
            enabled = true,
            special = true,
            maxOwned = 2,
            spawnFrozen = true,
        },
        -- ══ Код 88: мобильные телефоны (предметы инвентаря, invItem — БЕЗ мирового спавна) ══
        mobile_crappy = {
            id = "mobile_crappy",
            name = "Badger Crappy (мобильный)",
            desc = "Дешёвая трубка. Только звонки, слабый приём на окраинах. Кладётся в инвентарь.",
            class = "grm_mobile_line",
            model = "models/ivancorn/gtaiv/electrical/phones/cellphone_badger_crappy.mdl",
            price = 700,
            enabled = true,
            special = false,
            maxOwned = 2,
            spawnFrozen = true,
            invItem = "mobile_crappy",
        },
        mobile_badger = {
            id = "mobile_badger",
            name = "Badger Classic (мобильный)",
            desc = "Звонки, SMS, контакты. Кладётся в инвентарь.",
            class = "grm_mobile_line",
            model = "models/ivancorn/gtaiv/electrical/phones/cellphone_badger.mdl",
            price = 1800,
            enabled = true,
            special = false,
            maxOwned = 2,
            spawnFrozen = true,
            invItem = "mobile_badger",
        },
        mobile_badger_touch = {
            id = "mobile_badger_touch",
            name = "Badger Touch (мобильный)",
            desc = "Сенсорный Badger: SMS, контакты, заметки. Кладётся в инвентарь.",
            class = "grm_mobile_line",
            model = "models/ivancorn/gtaiv/electrical/phones/phone_mobile_badger_touchscreen.mdl",
            price = 3500,
            enabled = true,
            special = false,
            maxOwned = 2,
            spawnFrozen = true,
            invItem = "mobile_badger_touch",
        },
        mobile_lost = {
            id = "mobile_lost",
            name = "The Lost Flip (мобильный)",
            desc = "Байкерская раскладушка: SMS, контакты, заметки. Кладётся в инвентарь.",
            class = "grm_mobile_line",
            model = "models/ivancorn/gtaiv/electrical/phones/cellphone_thelostdamned.mdl",
            price = 4200,
            enabled = true,
            special = false,
            maxOwned = 2,
            spawnFrozen = true,
            invItem = "mobile_lost",
        },
        mobile_tinkle = {
            id = "mobile_tinkle",
            name = "Panoramic Tinkle (смартфон)",
            desc = "Все приложения: биржа, фракция, форум, заметки. Кладётся в инвентарь.",
            class = "grm_mobile_line",
            model = "models/ivancorn/gtaiv/electrical/phones/cellphone_panoramic_tinkle.mdl",
            price = 6500,
            enabled = true,
            special = false,
            maxOwned = 2,
            spawnFrozen = true,
            invItem = "mobile_tinkle",
        },
        mobile_whiz_high = {
            id = "mobile_whiz_high",
            name = "Whiz Highspeed (смартфон)",
            desc = "Флагман Whiz: всё сразу, уверенный приём. Кладётся в инвентарь.",
            class = "grm_mobile_line",
            model = "models/ivancorn/gtaiv/electrical/phones/cellphone_whiz_highspeed.mdl",
            price = 9000,
            enabled = true,
            special = false,
            maxOwned = 2,
            spawnFrozen = true,
            invItem = "mobile_whiz_high",
        },
        mobile_whiz_gold = {
            id = "mobile_whiz_gold",
            name = "Whiz Gold (смартфон)",
            desc = "Золотой Whiz: статус и лучший приёмник в городе. Кладётся в инвентарь.",
            class = "grm_mobile_line",
            model = "models/ivancorn/gtaiv/electrical/phones/cellphone_whiz_gold.mdl",
            price = 14000,
            enabled = true,
            special = false,
            maxOwned = 2,
            spawnFrozen = true,
            invItem = "mobile_whiz_gold",
        },
        -- ══ Код 99: переносной модулятор рации — ключ к /freq и /r (RadioNet v1.4.0) ══
        radio_modulator = {
            id = "radio_modulator",
            name = "Модулятор рации (переносной)",
            desc = "Переносная радиостанция. Активируйте (Использовать в /inv) — откроются радиочастоты: /freq 145.5, /r текст. Выбрасывается и подбирается. Кладётся в инвентарь.",
            class = "prop_physics", -- invItem-ветка: в мире не спавнится
            model = "models/props_lab/reciever01b.mdl",
            price = 1500,
            enabled = true,
            special = false,
            maxOwned = 2,
            spawnFrozen = true,
            invItem = "radio_modulator",
        },
    }
end

SHOP.Config = SHOP.Config or {
    Enabled = true,
    MaxOwnedTotal = 12,
    SpawnDistance = 90,
    RemoveDistance = 180,
    RefundPercent = 0,
    -- Покупка/спавн special=true требуют доступа через /phone_access.
    RequireAccessToBuySpecial = true,
    RequireAccessToSpawnSpecial = true,
}

local function normalizeItem(id, item)
    item = istable(item) and item or {}
    id = sanitizeID(item.id or id)
    return {
        id = id,
        name = tostring(item.name or id),
        desc = tostring(item.desc or ""),
        class = tostring(item.class or "prop_physics"),
        model = tostring(item.model or ""),
        price = math.max(0, math.floor(tonumber(item.price) or 0)),
        enabled = item.enabled ~= false,
        special = item.special == true,
        maxOwned = math.max(0, math.floor(tonumber(item.maxOwned) or 1)),
        spawnFrozen = item.spawnFrozen ~= false,
        data = istable(item.data) and item.data or {},
        -- Код 88: если задан — товар покупается как ПРЕДМЕТ инвентаря (мобильные).
        -- Всегда строка (пустая если нет) — чтобы net.WriteTable передавал корректно
        invItem = (item.invItem ~= nil and tostring(item.invItem) ~= "") and tostring(item.invItem) or "",
    }
end

local function normalizeCatalog(cat)
    local out = {}
    for id, item in pairs(cat or {}) do
        local norm = normalizeItem(id, item)
        out[norm.id] = norm
    end
    return out
end

local function vecToTable(v) return { x = v.x, y = v.y, z = v.z } end
local function angToTable(a) return { p = a.p, y = a.y, r = a.r } end
local function tableToVec(t) return Vector(tonumber(t and t.x) or 0, tonumber(t and t.y) or 0, tonumber(t and t.z) or 0) end
local function tableToAng(t) return Angle(tonumber(t and t.p) or 0, tonumber(t and t.y) or 0, tonumber(t and t.r) or 0) end

-- ============================================================
-- SERVER
-- ============================================================

if SERVER then
    for _, n in ipairs({
        NET_OPEN, NET_DATA, NET_BUY_ACCESS, NET_SPAWN, NET_REMOVE, NET_RESULT,
        NET_ADMIN_OPEN, NET_ADMIN_DATA, NET_ADMIN_SAVE, NET_ADMIN_DELETE,
        NET_ADMIN_ADDLOOK, NET_ADMIN_RESET,
    }) do
        util.AddNetworkString(n)
    end

    SHOP.Catalog = SHOP.Catalog or {}
    SHOP.Purchases = SHOP.Purchases or {}
    SHOP.Owned = SHOP.Owned or {}

    local function notify(ply, ok, msg)
        if not IsValid(ply) then return end
        net.Start(NET_RESULT)
            net.WriteBool(ok and true or false)
            net.WriteString(msg or "")
        net.Send(ply)
        if GRM and GRM.Notify then
            GRM.Notify(ply, msg or "", ok and 100 or 255, ok and 220 or 100, ok and 100 or 100)
        else
            ply:ChatPrint(msg or "")
        end
    end

    function SHOP.LoadCatalog()
        local loaded = readJSON(CATALOG_FILE, {})
        if not next(loaded) then
            loaded = defaultCatalog()
            writeJSON(CATALOG_FILE, loaded)
        else
            -- Mobile rewrite: мобильные товары авторитетны из кода, потому что
            -- они жёстко связаны с item-id инвентаря, моделями ivancorn и лимитами.
            -- Старые сохранённые каталоги могли содержать mobile_touch/mobile_smartphone
            -- или старые модели — лечим при каждом старте.
            local defs = defaultCatalog()
            local changed = false
            loaded.mobile_touch = nil
            loaded.mobile_smartphone = nil
            for id, item in pairs(defs) do
                if item.invItem and item.invItem ~= "" then
                    local oldItem = loaded[id]
                    if not istable(oldItem) or oldItem.model ~= item.model or oldItem.invItem ~= item.invItem then changed = true end
                    loaded[id] = table.Copy(item)
                elseif loaded[id] == nil then
                    loaded[id] = item
                    changed = true
                end
            end
            if changed then writeJSON(CATALOG_FILE, loaded) end
        end
        SHOP.Catalog = normalizeCatalog(loaded)
        return SHOP.Catalog
    end

    function SHOP.SaveCatalog()
        SHOP.Catalog = normalizeCatalog(SHOP.Catalog or {})
        writeJSON(CATALOG_FILE, SHOP.Catalog)
    end

    function SHOP.LoadPurchases()
        SHOP.Purchases = readJSON(PURCHASES_FILE, {})
        return SHOP.Purchases
    end

    function SHOP.SavePurchases()
        writeJSON(PURCHASES_FILE, SHOP.Purchases or {})
    end

    local function hasAccessForSpecial(ply)
        return GRM.Phone and GRM.Phone.HasEquipmentAccess and GRM.Phone.HasEquipmentAccess(ply)
    end

    local function playerHasAccess(ply, itemID)
        local sid = steamID(ply)
        return SHOP.Purchases[sid] and SHOP.Purchases[sid][itemID] == true
    end

    local function grantAccess(ply, itemID)
        local sid = steamID(ply)
        SHOP.Purchases[sid] = SHOP.Purchases[sid] or {}
        SHOP.Purchases[sid][itemID] = true
        SHOP.SavePurchases()
    end

    local function countOwned(ply, itemID)
        local sid = steamID(ply)
        local total = 0
        local perItem = 0
        for _, rec in pairs(SHOP.Owned or {}) do
            if rec.owner == sid then
                total = total + 1
                if rec.itemID == itemID then perItem = perItem + 1 end
            end
        end
        return total, perItem
    end

    local function applyItemData(ent, item, rec)
        if not IsValid(ent) then return end
        item = item or {}
        rec = rec or {}

        if item.model and item.model ~= "" and ent:GetModel() ~= item.model then
            pcall(function() ent:SetModel(item.model) end)
        end

        if ent:GetClass() == "grm_phone" or ent:GetClass() == "grm_payphone" then
            if ent.GetPhoneNumber and ent:GetPhoneNumber() == "" then
                ent:SetPhoneNumber(GRM.Phone.GenerateNumber())
            end
            ent:SetDisplayName(rec.name or item.name or "Телефон")
            ent:SetExchangeID(rec.exchange or item.data and item.data.exchange or "main")
        elseif ent:GetClass() == "grm_pbx_station" then
            ent:SetExchangeID(rec.exchange or item.data and item.data.exchange or "main")
            ent:SetActive(rec.active ~= nil and rec.active or (item.data and item.data.active ~= false))
            ent:SetMaxLines(tonumber(rec.maxLines or item.data and item.data.maxLines) or 60)
        elseif ent:GetClass() == "grm_phone_wiretap" then
            ent:SetTargetNumber(rec.target or item.data and item.data.target or "")
            ent:SetExchangeID(rec.exchange or item.data and item.data.exchange or "main")
            ent:SetActive(rec.active ~= nil and rec.active or (item.data and item.data.active == true))
        elseif ent:GetClass() == "grm_phone_terminal" then
            ent:SetTerminalName(rec.name or item.name or "Мониторинг связи")
        end
    end

    local function makeID(ply, itemID)
        return "phoneeq_" .. os.time() .. "_" .. ply:EntIndex() .. "_" .. sanitizeID(itemID) .. "_" .. math.random(1000, 9999)
    end

    local function recordEntity(ent, ply, itemID, id)
        local item = SHOP.Catalog[itemID]
        if not IsValid(ent) or not item then return nil end

        local rec = {
            id = id or makeID(ply, itemID),
            owner = steamID(ply),
            ownerName = IsValid(ply) and ply:Nick() or "unknown",
            itemID = itemID,
            class = ent:GetClass(),
            model = ent:GetModel() or item.model or "",
            price = item.price or 0,
            pos = vecToTable(ent:GetPos()),
            ang = angToTable(ent:GetAngles()),
            map = game.GetMap(),
            created = os.time(),
        }

        if ent:GetClass() == "grm_phone" or ent:GetClass() == "grm_payphone" then
            rec.number = ent:GetPhoneNumber()
            rec.name = ent:GetDisplayName()
            rec.exchange = ent:GetExchangeID()
        elseif ent:GetClass() == "grm_pbx_station" then
            rec.exchange = ent:GetExchangeID()
            rec.active = ent:GetActive()
            rec.maxLines = ent:GetMaxLines()
        elseif ent:GetClass() == "grm_phone_wiretap" then
            rec.target = ent:GetTargetNumber()
            rec.exchange = ent:GetExchangeID()
            rec.active = ent:GetActive()
        elseif ent:GetClass() == "grm_phone_terminal" then
            rec.name = ent:GetTerminalName()
        end

        return rec
    end

    local function markOwned(ent, rec)
        if not IsValid(ent) or not rec then return end
        ent.GRMPhoneShopOwned = true
        ent.GRMPhoneShopID = rec.id
        ent.GRMPhoneOwnerSteam = rec.owner
        ent.GRMPhoneOwnerName = rec.ownerName
        ent.GRMPhoneItemID = rec.itemID
    end

    function SHOP.SaveOwned()
        local out = {}
        for id, rec in pairs(SHOP.Owned or {}) do
            local ent = rec.ent
            if IsValid(ent) then
                local fresh = recordEntity(ent, { SteamID64 = function() return rec.owner end, Nick = function() return rec.ownerName or "unknown" end, EntIndex = function() return 0 end }, rec.itemID, id)
                if fresh then
                    fresh.ent = ent
                    SHOP.Owned[id] = fresh
                    local copy = table.Copy(fresh)
                    copy.ent = nil
                    out[#out + 1] = copy
                end
            else
                local copy = table.Copy(rec)
                copy.ent = nil
                out[#out + 1] = copy
            end
        end
        writeJSON(EQUIPMENT_FILE, out)
    end

    function SHOP.LoadOwned()
        SHOP.Owned = {}
        local data = readJSON(EQUIPMENT_FILE, {})
        for _, rec in ipairs(data) do
            if rec.map == game.GetMap() and rec.class and rec.id and rec.itemID then
                local item = SHOP.Catalog[rec.itemID] or normalizeItem(rec.itemID, { class = rec.class, model = rec.model, name = rec.itemID })
                local ent = ents.Create(rec.class)
                if IsValid(ent) then
                    ent:SetPos(tableToVec(rec.pos))
                    ent:SetAngles(tableToAng(rec.ang))
                    ent:Spawn()
                    ent:Activate()
                    applyItemData(ent, item, rec)
                    rec.ent = ent
                    markOwned(ent, rec)
                    SHOP.Owned[rec.id] = rec
                end
            end
        end
        print("[GRM Phone Shop] Loaded owned equipment: " .. table.Count(SHOP.Owned))
    end

    local function spawnEquipment(ply, itemID)
        local item = SHOP.Catalog[itemID]
        if not item then return nil, "Товар не найден." end

        local ent = ents.Create(item.class)
        if not IsValid(ent) then return nil, "Не удалось создать entity: " .. tostring(item.class) end

        local pos = ply:GetPos() + ply:GetForward() * (cfg().SpawnDistance or 90) + Vector(0, 0, 8)
        local ang = Angle(0, ply:EyeAngles().y + 180, 0)

        ent:SetPos(pos)
        ent:SetAngles(ang)
        ent:Spawn()
        ent:Activate()

        applyItemData(ent, item, {})

        local phys = ent:GetPhysicsObject()
        if IsValid(phys) and item.spawnFrozen ~= false then phys:EnableMotion(false) end

        local id = makeID(ply, itemID)
        local rec = recordEntity(ent, ply, itemID, id)
        rec.ent = ent
        markOwned(ent, rec)
        SHOP.Owned[id] = rec
        SHOP.SaveOwned()

        return ent
    end

    local function canBuyAccess(ply, itemID)
        local item = SHOP.Catalog[itemID]
        if not item then return false, "Товар не найден." end
        if item.enabled == false then return false, "Товар отключён." end
        if item.invItem and item.invItem ~= "" then
            return false, "Мобильный покупается сразу — жмите «Купить»."
        end
        if item.special and cfg().RequireAccessToBuySpecial ~= false and not hasAccessForSpecial(ply) then
            return false, "Нет доступа к покупке спецоборудования связи."
        end
        return true
    end

    local function canSpawnItem(ply, itemID)
        local item = SHOP.Catalog[itemID]
        if not item then return false, "Товар не найден." end
        if item.enabled == false then return false, "Товар отключён." end
        if item.invItem and item.invItem ~= "" then
            -- Код 88: телефон — предмет инвентаря. Доступ к линии не нужен, лимит по штукам.
            if not (GRM and GRM.Inventory and GRM.Inventory.AddItem) then
                return false, "Модуль инвентаря не загружен."
            end
            local have = GRM.Inventory.CountItem and GRM.Inventory.CountItem(ply, item.invItem) or 0
            if item.maxOwned > 0 and have >= item.maxOwned then
                return false, "У вас уже максимум таких телефонов: " .. tostring(item.maxOwned)
            end
            return true
        end
        if not playerHasAccess(ply, itemID) then return false, "Сначала купите доступ к этому оборудованию." end
        if item.special and cfg().RequireAccessToSpawnSpecial ~= false and not hasAccessForSpecial(ply) then
            return false, "Ваш доступ к спецоборудованию связи отозван."
        end
        local total, perItem = countOwned(ply, itemID)
        if total >= (cfg().MaxOwnedTotal or 12) then return false, "Общий лимит оборудования: " .. tostring(cfg().MaxOwnedTotal or 12) end
        if item.maxOwned > 0 and perItem >= item.maxOwned then return false, "Лимит этого оборудования: " .. tostring(item.maxOwned) end
        return true
    end

    local function sendShopData(ply)
        local catalog = {}
        for id, item in pairs(SHOP.Catalog or {}) do
            catalog[id] = table.Copy(item)
            local isInvItem = item.invItem and item.invItem ~= ""
            local ownedInv = 0
            if isInvItem and GRM and GRM.Inventory and GRM.Inventory.CountItem then
                ownedInv = GRM.Inventory.CountItem(ply, item.invItem) or 0
            end
            catalog[id].ownedCount = ownedInv
            catalog[id].ownedMax = tonumber(item.maxOwned) or 0
            -- Для мобильных «purchased» означает «у игрока уже есть такой предмет в инвентаре».
            -- Это переживает рестарт через grm_inventories.json и сразу видно в /phoneshop.
            catalog[id].purchased = isInvItem and ownedInv > 0 or playerHasAccess(ply, id)
            catalog[id].canBuy, catalog[id].buyReason = canBuyAccess(ply, id)
            catalog[id].canSpawn, catalog[id].spawnReason = canSpawnItem(ply, id)
        end

        net.Start(NET_DATA)
            net.WriteTable(catalog)
            net.WriteUInt(countOwned(ply), 12)
            net.WriteUInt(cfg().MaxOwnedTotal or 12, 12)
        net.Send(ply)
    end

    local function openShop(ply)
        sendShopData(ply)
        net.Start(NET_OPEN)
        net.Send(ply)
    end

    net.Receive(NET_OPEN, function(_, ply)
        openShop(ply)
    end)

    net.Receive(NET_BUY_ACCESS, function(_, ply)
        local itemID = net.ReadString()
        local item = SHOP.Catalog[itemID]

        local ok, reason = canBuyAccess(ply, itemID)
        if not ok then notify(ply, false, reason) return end
        if playerHasAccess(ply, itemID) then notify(ply, false, "Доступ уже куплен.") return end

        local price = tonumber(item.price) or 0
        if not canPay(ply, price) then notify(ply, false, "Недостаточно средств. Нужно: " .. moneyName(price)) return end

        takeMoney(ply, price)
        grantAccess(ply, itemID)
        notify(ply, true, "Куплен доступ: " .. item.name .. " за " .. moneyName(price))
        sendShopData(ply)
    end)

    net.Receive(NET_SPAWN, function(_, ply)
        local itemID = net.ReadString()
        local item = SHOP.Catalog[itemID]

        local ok, reason = canSpawnItem(ply, itemID)
        if not ok then notify(ply, false, reason) return end

        -- Код 88: мобильный телефон — покупка предмета в инвентарь, БЕЗ спавна в мир.
        if item.invItem and item.invItem ~= "" then
            local price = tonumber(item.price) or 0
            if not canPay(ply, price) then
                notify(ply, false, "Недостаточно средств. Нужно: " .. moneyName(price))
                return
            end
            takeMoney(ply, price)
            local instData = tostring(item.invItem or ""):find("mobile_", 1, true) == 1 and { active = false } or nil
            local left = GRM.Inventory.AddItem(ply, item.invItem, 1, instData)
            if (left or 1) > 0 then
                giveMoney(ply, price) -- инвентарь переполнен — возврат денег
                notify(ply, false, "Инвентарь переполнен. Деньги возвращены.")
                return
            end
            notify(ply, true, "Куплено: " .. (item.name or itemID) .. " за " .. moneyName(price) .. ". Телефон в инвентаре.")
            hook.Run("GRM_Mobile_Bought", ply, itemID)
            sendShopData(ply)
            return
        end

        local ent, err = spawnEquipment(ply, itemID)
        if not IsValid(ent) then notify(ply, false, err or "Ошибка спавна.") return end

        notify(ply, true, "Оборудование установлено: " .. (SHOP.Catalog[itemID].name or itemID))
        sendShopData(ply)
    end)

    local function removeNearestOwned(ply)
        local best, bestDist
        local sid = steamID(ply)
        local maxDist = (cfg().RemoveDistance or 180) ^ 2

        for _, rec in pairs(SHOP.Owned or {}) do
            local ent = rec.ent
            if IsValid(ent) and rec.owner == sid then
                local d = ent:GetPos():DistToSqr(ply:GetPos())
                if d <= maxDist and (not bestDist or d < bestDist) then
                    best = rec
                    bestDist = d
                end
            end
        end

        if not best or not IsValid(best.ent) then return false, "Рядом нет вашего телефонного оборудования." end

        local name = SHOP.Catalog[best.itemID] and SHOP.Catalog[best.itemID].name or best.class
        best.ent:Remove()
        SHOP.Owned[best.id] = nil
        SHOP.SaveOwned()

        return true, "Оборудование убрано: " .. tostring(name)
    end

    net.Receive(NET_REMOVE, function(_, ply)
        local ok, msg = removeNearestOwned(ply)
        notify(ply, ok, msg)
        sendShopData(ply)
    end)

    -- Admin actions.
    local function sendAdminData(ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        net.Start(NET_ADMIN_DATA)
            net.WriteTable(SHOP.Catalog or {})
            net.WriteTable(cfg())
        net.Send(ply)
    end

    net.Receive(NET_ADMIN_OPEN, function(_, ply) sendAdminData(ply) end)

    net.Receive(NET_ADMIN_SAVE, function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        local item = net.ReadTable() or {}
        local norm = normalizeItem(item.id, item)
        SHOP.Catalog[norm.id] = norm
        SHOP.SaveCatalog()
        notify(ply, true, "Товар сохранён: " .. norm.name)
        sendAdminData(ply)
    end)

    net.Receive(NET_ADMIN_DELETE, function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        local id = net.ReadString()
        if SHOP.Catalog[id] then
            SHOP.Catalog[id] = nil
            SHOP.SaveCatalog()
            notify(ply, true, "Товар удалён: " .. id)
        end
        sendAdminData(ply)
    end)

    net.Receive(NET_ADMIN_RESET, function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        SHOP.Catalog = normalizeCatalog(defaultCatalog())
        SHOP.SaveCatalog()
        notify(ply, true, "Каталог магазина телефонии сброшен.")
        sendAdminData(ply)
    end)

    local function addLookEntityToCatalog(ply)
        if not IsValid(ply) then return end
        local ent = ply:GetEyeTrace().Entity
        if not IsValid(ent) then notify(ply, false, "Наведитесь на entity.") return end

        local class = ent:GetClass()
        local model = ent:GetModel() or ""
        local id = sanitizeID(class .. "_" .. os.time())
        local name = ent.PrintName or ent:GetNWString("PrintName", "") or class
        if name == "" then name = class end

        SHOP.Catalog[id] = normalizeItem(id, {
            id = id,
            name = name,
            desc = "Добавлено из entity под прицелом: " .. class,
            class = class,
            model = model,
            price = 1000,
            enabled = true,
            special = false,
            maxOwned = 2,
            spawnFrozen = true,
        })
        SHOP.SaveCatalog()
        notify(ply, true, "Добавлено в магазин: " .. name)
        sendAdminData(ply)
    end

    net.Receive(NET_ADMIN_ADDLOOK, function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        addLookEntityToCatalog(ply)
    end)

    concommand.Add("grm_phone_shop_add_look", function(ply)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        addLookEntityToCatalog(ply)
    end)

    -- Commands.
    hook.Add("PlayerSay", "GRM_PhoneShop_Chat", function(ply, text)
        local cmd = string.lower(string.Trim(text or ""))

        if cmd == "/phoneshop" or cmd == "!phoneshop" or cmd == "/teleshop" or cmd == "!teleshop" then
            openShop(ply)
            return ""
        end

        if cmd == "/phoneshop_admin" or cmd == "!phoneshop_admin" then
            if ply:IsSuperAdmin() then
                net.Start(NET_ADMIN_OPEN)
                net.Send(ply)
            end
            return ""
        end

        if cmd == "/phone_remove" or cmd == "!phone_remove" or cmd == "/removephone" or cmd == "!removephone" then
            local ok, msg = removeNearestOwned(ply)
            notify(ply, ok, msg)
            return ""
        end
    end)

    concommand.Add("grm_phone_shop", function(ply) if IsValid(ply) then openShop(ply) end end)
    concommand.Add("grm_phone_shop_admin", function(ply) if IsValid(ply) and ply:IsSuperAdmin() then net.Start(NET_ADMIN_OPEN) net.Send(ply) end end)
    concommand.Add("grm_phone_remove_owned", function(ply) if IsValid(ply) then local ok, msg = removeNearestOwned(ply); notify(ply, ok, msg) end end)
    concommand.Add("grm_phone_shop_reload", function(ply) if IsValid(ply) and not ply:IsSuperAdmin() then return end SHOP.LoadCatalog(); SHOP.LoadPurchases(); notify(ply, true, "Магазин телефонии перезагружен.") end)

    SHOP.LoadCatalog()
    SHOP.LoadPurchases()

--[[ Реестр купленных номеров нужен ТОЛЬКО когда его действительно
     спрашивают: игрок открыл магазин, взял в руки телефон или зашёл на
     сервер. На пустом сервере файл не читается вообще — это чистая
     экономия старта («если игрок сделал А, тогда выполняем Б»). ]]
if GRM.Boot and GRM.Boot.Lazy then
    GRM.Boot.Lazy("phoneshop.owned", function() SHOP.LoadOwned() end,
        { label = "Магазин телефонов: купленные номера (по требованию)" })
    GRM.Boot.OnChat({ "/phoneshop", "!phoneshop", "/teleshop", "!teleshop", "/phoneshop_admin" }, "phoneshop.owned")
    GRM.Boot.OnUseClass("grm_phone_terminal", "phoneshop.owned")
    GRM.Boot.OnUseClass("grm_phone", "phoneshop.owned")
    GRM.Boot.OnFirstPlayer("phoneshop.owned")
    -- Любой внутренний доступ к реестру тоже поднимает его сам.
    local rawOwned = SHOP.LoadOwned
    function SHOP.EnsureOwned()
        if GRM.Boot.Done("phoneshop.owned") then return end
        GRM.Boot.Ensure("phoneshop.owned", "прямой запрос реестра")
    end
    SHOP.LoadOwned = function(...)
        local ok = rawOwned(...)
        if GRM.Boot.Tasks and GRM.Boot.Tasks["phoneshop.owned"] then
            GRM.Boot.Tasks["phoneshop.owned"].state = "done"
        end
        return ok
    end
else
    hook.Add("InitPostEntity", "GRM_PhoneShop_Load", function()
        timer.Simple(1.5, SHOP.LoadOwned)
    end)
end

    hook.Add("ShutDown", "GRM_PhoneShop_Save", function() SHOP.SaveOwned(); SHOP.SavePurchases(); SHOP.SaveCatalog() end)

    timer.Create("GRM_PhoneShop_AutoSave", 60, 0, function() SHOP.SaveOwned(); SHOP.SavePurchases(); SHOP.SaveCatalog() end)

    print("[GRM Phone Shop] Server loaded v2")
else

    local shopData = {}
    local ownedCount = 0
    local ownedMax = 0

    local function moneyText(n) return moneyName(n) end

    net.Receive(NET_DATA, function()
        shopData = net.ReadTable() or {}
        ownedCount = net.ReadUInt(12)
        ownedMax = net.ReadUInt(12)
    end)

    net.Receive(NET_RESULT, function()
        local ok = net.ReadBool()
        local msg = net.ReadString()
        notification.AddLegacy(msg, ok and NOTIFY_GENERIC or NOTIFY_ERROR, 4)
    end)

    local function requestOpenShop()
        net.Start(NET_OPEN)
        net.SendToServer()
    end

    local function buyAccess(id)
        net.Start(NET_BUY_ACCESS)
            net.WriteString(id)
        net.SendToServer()
    end

    local function spawnItem(id)
        net.Start(NET_SPAWN)
            net.WriteString(id)
        net.SendToServer()
    end

    local function removeOwned()
        net.Start(NET_REMOVE)
        net.SendToServer()
    end

    local function rowPaint(item, id)
        return function(_, w, h)
            draw.RoundedBox(8, 0, 0, w, h, Color(32, 36, 48, 245))
            draw.SimpleText(item.name or id, "DermaDefaultBold", 96, 18, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(item.desc or "", "DermaDefault", 96, 42, Color(185, 192, 205), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            local priceLabel = (item.invItem and item.invItem ~= "") and "Цена: " or "Цена доступа: "
            draw.SimpleText(priceLabel .. moneyText(item.price or 0), "DermaDefaultBold", 96, 68, Color(110, 220, 130), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            if item.invItem and item.invItem ~= "" then
                local have = tonumber(item.ownedCount or 0) or 0
                local max = tonumber(item.ownedMax or item.maxOwned or 0) or 0
                local ownText = max > 0 and ("У вас: " .. have .. " / " .. max) or ("У вас: " .. have)
                local ownCol = have > 0 and Color(120, 230, 120) or Color(120, 200, 255)
                draw.SimpleText("Мобильный телефон • предмет в /inv • использовать = открыть меню", "DermaDefault", 96, 88, Color(120, 200, 255), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText(ownText, "DermaDefaultBold", w - 184, 92, ownCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            else
                draw.SimpleText(item.purchased and "Доступ куплен" or "Доступ не куплен", "DermaDefault", 96, 92, item.purchased and Color(120, 230, 120) or Color(255, 185, 85), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
        end
    end

    local function addShopRow(parent, id, item, frame)
        local row = vgui.Create("DPanel", parent)
        row:Dock(TOP)
        row:SetTall(116)
        row:DockMargin(0, 0, 0, 8)
        row.Paint = rowPaint(item, id)

        local icon = vgui.Create("SpawnIcon", row)
        icon:SetModel(item.model or "models/props_junk/cardboard_box004a.mdl")
        icon:SetSize(72, 72)
        icon:SetPos(12, 18)
        if icon.SetTooltip then icon:SetTooltip(item.model or "") end

        local btn = vgui.Create("DButton", row)
        btn:SetSize(150, 34)
        btn:SetPos(480, 42)

        if item.invItem and item.invItem ~= "" then
            local have = tonumber(item.ownedCount or 0) or 0
            local max = tonumber(item.ownedMax or item.maxOwned or 0) or 0
            local atLimit = max > 0 and have >= max
            if atLimit then
                btn:SetText("Уже есть")
                btn:SetEnabled(false)
            else
                btn:SetText(have > 0 and "Купить ещё" or "Купить")
                btn:SetEnabled(item.canSpawn == true)
            end
            if btn.SetTooltip then
                btn:SetTooltip(atLimit and "Лимит этих телефонов уже достигнут" or (item.canSpawn and "Телефон попадёт в инвентарь" or tostring(item.spawnReason or "")))
            end
            btn.DoClick = function()
                spawnItem(id)
                if IsValid(frame) then frame:Close() end
            end
        elseif item.purchased then
            btn:SetText(item.canSpawn and "Поставить" or "Нет доступа")
            btn:SetEnabled(item.canSpawn == true)
            if btn.SetTooltip then btn:SetTooltip(item.canSpawn and "" or tostring(item.spawnReason or "")) end
            btn.DoClick = function()
                spawnItem(id)
                if IsValid(frame) then frame:Close() end
            end
        else
            btn:SetText(item.canBuy and "Купить доступ" or "Нет доступа")
            btn:SetEnabled(item.canBuy == true)
            if btn.SetTooltip then btn:SetTooltip(item.canBuy and "" or tostring(item.buyReason or "")) end
            btn.DoClick = function()
                buyAccess(id)
                if IsValid(frame) then frame:Close() end
            end
        end
    end

    net.Receive(NET_OPEN, function()
        local frame = vgui.Create("DFrame")
        frame:SetTitle("GRM PhoneShop — телефоны и связь")
        frame:SetSize(720, 620)
        frame:Center()
        frame:MakePopup()

        local info = vgui.Create("DLabel", frame)
        info:Dock(TOP)
        info:SetTall(32)
        info:DockMargin(10, 6, 10, 0)
        info:SetText("Оборудование на карте: " .. ownedCount .. " / " .. ownedMax .. "    •    Мобильные телефоны покупаются предметом в инвентарь")
        info:SetTextColor(Color(220, 225, 235))

        local tabs = vgui.Create("DPropertySheet", frame)
        tabs:Dock(FILL)
        tabs:DockMargin(8, 8, 8, 46)

        local mobilePanel = vgui.Create("DScrollPanel", tabs)
        local equipPanel = vgui.Create("DScrollPanel", tabs)
        tabs:AddSheet("Мобильные", mobilePanel, "icon16/phone.png")
        tabs:AddSheet("Оборудование", equipPanel, "icon16/transmit.png")

        local mobileIDs, equipIDs = {}, {}
        for id, item in pairs(shopData) do
            if item.enabled ~= false then
                if item.invItem and item.invItem ~= "" and tostring(item.invItem):find("mobile_", 1, true) == 1 then
                    mobileIDs[#mobileIDs + 1] = id
                else
                    equipIDs[#equipIDs + 1] = id
                end
            end
        end
        local order = { mobile_crappy=1, mobile_badger=2, mobile_badger_touch=3, mobile_lost=4, mobile_tinkle=5, mobile_whiz_high=6, mobile_whiz_gold=7 }
        table.sort(mobileIDs, function(a,b) return (order[a] or 99) < (order[b] or 99) end)
        table.sort(equipIDs)

        for _, id in ipairs(mobileIDs) do addShopRow(mobilePanel, id, shopData[id], frame) end
        for _, id in ipairs(equipIDs) do addShopRow(equipPanel, id, shopData[id], frame) end

        local remove = vgui.Create("DButton", frame)
        remove:Dock(BOTTOM)
        remove:SetTall(34)
        remove:DockMargin(8, 4, 8, 8)
        remove:SetText("Убрать ближайшее моё стационарное оборудование")
        remove.DoClick = function()
            Derma_Query("Убрать ближайшее ваше телефонное оборудование?", "Телефония", "Убрать", function()
                removeOwned()
                if IsValid(frame) then frame:Close() end
            end, "Отмена")
        end
    end)

    -- Admin GUI.
    local adminCatalog = {}

    local function openItemEditor(initial)
        local item = table.Copy(initial or {})
        item.id = item.id or "new_item"

        local f = vgui.Create("DFrame")
        f:SetTitle("Товар магазина телефонии")
        f:SetSize(520, 430)
        f:Center()
        f:MakePopup()

        local y = 36
        local function label(text)
            local l = vgui.Create("DLabel", f)
            l:SetPos(14, y + 4)
            l:SetSize(120, 20)
            l:SetText(text)
        end

        local function entry(text)
            local e = vgui.Create("DTextEntry", f)
            e:SetPos(140, y)
            e:SetSize(360, 26)
            e:SetText(tostring(text or ""))
            y = y + 34
            return e
        end

        label("ID")
        local idE = entry(item.id)
        label("Название")
        local nameE = entry(item.name)
        label("Описание")
        local descE = entry(item.desc)
        label("Class")
        local classE = entry(item.class)
        label("Model")
        local modelE = entry(item.model)
        label("Цена")
        local priceE = entry(item.price or 0)
        label("Лимит")
        local maxE = entry(item.maxOwned or 1)

        local enabled = vgui.Create("DCheckBoxLabel", f)
        enabled:SetPos(140, y)
        enabled:SetSize(200, 24)
        enabled:SetText("Товар включён")
        enabled:SetValue(item.enabled ~= false)
        y = y + 28

        local special = vgui.Create("DCheckBoxLabel", f)
        special:SetPos(140, y)
        special:SetSize(320, 24)
        special:SetText("Спецоборудование: требует доступ телефонии")
        special:SetValue(item.special == true)
        y = y + 28

        local frozen = vgui.Create("DCheckBoxLabel", f)
        frozen:SetPos(140, y)
        frozen:SetSize(320, 24)
        frozen:SetText("Заморозить после установки")
        frozen:SetValue(item.spawnFrozen ~= false)
        y = y + 40

        local save = vgui.Create("DButton", f)
        save:SetPos(14, y)
        save:SetSize(486, 34)
        save:SetText("Сохранить товар")
        save.DoClick = function()
            local out = {
                id = idE:GetText(),
                name = nameE:GetText(),
                desc = descE:GetText(),
                class = classE:GetText(),
                model = modelE:GetText(),
                price = tonumber(priceE:GetText()) or 0,
                maxOwned = tonumber(maxE:GetText()) or 1,
                enabled = enabled:GetChecked(),
                special = special:GetChecked(),
                spawnFrozen = frozen:GetChecked(),
            }
            net.Start(NET_ADMIN_SAVE)
                net.WriteTable(out)
            net.SendToServer()
            f:Close()
        end
    end

    local function openAdmin()
        local frame = vgui.Create("DFrame")
        frame:SetTitle("Админ: магазин телефонного оборудования")
        frame:SetSize(780, 620)
        frame:Center()
        frame:MakePopup()

        local top = vgui.Create("DPanel", frame)
        top:Dock(TOP)
        top:SetTall(42)
        top:DockMargin(8, 8, 8, 0)
        top:SetPaintBackground(false)

        local add = vgui.Create("DButton", top)
        add:Dock(LEFT)
        add:SetWide(180)
        add:SetText("+ Новый товар")
        add.DoClick = function() openItemEditor({ id = "new_item", class = "prop_physics", price = 1000, enabled = true }) end

        local addLook = vgui.Create("DButton", top)
        addLook:Dock(LEFT)
        addLook:SetWide(220)
        addLook:DockMargin(6, 0, 0, 0)
        addLook:SetText("+ Добавить entity под прицелом")
        addLook.DoClick = function()
            net.Start(NET_ADMIN_ADDLOOK)
            net.SendToServer()
        end

        -- Кнопку сброса НЕ держим в правом верхнем углу: она могла пересекаться
        -- с крестиком закрытия DFrame на некоторых разрешениях/скинах и случайно нажиматься.
        local bottom = vgui.Create("DPanel", frame)
        bottom:Dock(BOTTOM)
        bottom:SetTall(44)
        bottom:DockMargin(8, 4, 8, 8)
        bottom:SetPaintBackground(false)

        local reset = vgui.Create("DButton", bottom)
        reset:Dock(LEFT)
        reset:SetWide(230)
        reset:SetText("Сбросить каталог к стандартному")
        reset:SetTextColor(Color(255, 255, 255))
        reset.Paint = function(s, w, h)
            draw.RoundedBox(6, 0, 0, w, h, s:IsHovered() and Color(190, 70, 60) or Color(150, 45, 45))
        end
        reset.DoClick = function()
            Derma_Query(
                "Сбросить каталог товаров к стандартному?\n\nЦены и товары магазина будут заменены дефолтными.",
                "Опасное действие",
                "Сбросить", function()
                    net.Start(NET_ADMIN_RESET)
                    net.SendToServer()
                    frame:Close()
                end,
                "Отмена"
            )
        end

        local closeBtn = vgui.Create("DButton", bottom)
        closeBtn:Dock(RIGHT)
        closeBtn:SetWide(120)
        closeBtn:SetText("Закрыть")
        closeBtn.DoClick = function()
            frame:Close()
        end

        local scroll = vgui.Create("DScrollPanel", frame)
        scroll:Dock(FILL)
        scroll:DockMargin(8, 8, 8, 8)

        local sorted = {}
        for id in pairs(adminCatalog) do sorted[#sorted + 1] = id end
        table.sort(sorted)

        for _, id in ipairs(sorted) do
            local item = adminCatalog[id]
            local row = scroll:Add("DPanel")
            row:Dock(TOP)
            row:SetTall(88)
            row:DockMargin(0, 0, 0, 6)

            row.Paint = function(_, w, h)
                draw.RoundedBox(6, 0, 0, w, h, Color(34, 36, 44, 240))
                draw.SimpleText(item.name or id, "DermaDefaultBold", 12, 16, color_white)
                draw.SimpleText("ID: " .. id .. " | class: " .. tostring(item.class), "DermaDefault", 12, 40, Color(180, 185, 195))
                draw.SimpleText("Цена: " .. moneyText(item.price or 0) .. " | special: " .. tostring(item.special) .. " | enabled: " .. tostring(item.enabled), "DermaDefault", 12, 62, Color(120, 220, 120))
            end

            local edit = vgui.Create("DButton", row)
            edit:SetPos(560, 16)
            edit:SetSize(90, 28)
            edit:SetText("Ред.")
            edit.DoClick = function() openItemEditor(item) end

            local del = vgui.Create("DButton", row)
            del:SetPos(660, 16)
            del:SetSize(90, 28)
            del:SetText("Удалить")
            del.DoClick = function()
                Derma_Query("Удалить товар " .. id .. "?", "Магазин", "Удалить", function()
                    net.Start(NET_ADMIN_DELETE)
                        net.WriteString(id)
                    net.SendToServer()
                    frame:Close()
                end, "Отмена")
            end
        end
    end

    net.Receive(NET_ADMIN_DATA, function()
        adminCatalog = net.ReadTable() or {}
        openAdmin()
    end)

    concommand.Add("grm_phone_shop", function()
        net.Start(NET_OPEN)
        net.SendToServer()
    end)

    concommand.Add("grm_phone_shop_admin", function()
        net.Start(NET_ADMIN_OPEN)
        net.SendToServer()
    end)

    hook.Add("GRMRPChat_ClientCommand", "GRM_PhoneShop_ClientChat", function(ply, text)
        local data = { tostring(text or ""), SkipPlayerSay = false }
            if ply ~= LocalPlayer() then return end
            local cmd = string.lower(string.Trim(data[1] or ""))
            if cmd == "/phoneshop_admin" or cmd == "!phoneshop_admin" then
                net.Start(NET_ADMIN_OPEN)
                net.SendToServer()
                data[1] = ""
                return
            end

        if data.SkipPlayerSay == true then return true end
    end)

    print("[GRM Phone Shop] Client loaded v2")
end

-- Вечер-18: единый словарь slash-команд: имена живого PlayerSay-обработчика
-- вносятся во внешний реестр библиотеки (на режиме сверка идёт ДО ParseSay —
-- без регистрации команда стала бы «неизвестной»).
if GRM and GRM.Chat and GRM.Chat.RegisterExternalCommands then
    GRM.Chat.RegisterExternalCommands({ "/phone_remove", "/phoneshop", "/phoneshop_admin", "/removephone", "/teleshop" })
end
