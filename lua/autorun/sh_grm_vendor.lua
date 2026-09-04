-- Boot-шим: старт подсистемы идёт через планировщик GRM.Boot (приоритеты и
-- бюджет на тик). Если планировщик почему-то не загружен, работаем по-старому.
local function grmBootStart(id, tier, fn)
    if GRM and GRM.Boot and GRM.Boot.OnMapStart then return GRM.Boot.OnMapStart(id, tier, fn) end
    return hook.Add("InitPostEntity", id, fn)
end

--[[--------------------------------------------------------------------
    GRM Vendor Framework v2.0 (Код 111)
    Единый фреймворк торгашей: оружие / руда / еда / редкости.
    Один энтити-класс grm_vendor, тип задаётся в data (vendorType).
    Каталоги — shared, расширяются аддонами, синхронизируются с
    реальными модулями GRM (Mining, Food, OreDefs).
    UI — единый «киоск» в стиле HUD v10.2 (Roboto, тёмная тема).
    Админка — toolgun grm_vendor_tool (спавн/настройка цен/лимитов).
    Персистентность — через sh_grm_perm_entities (Код 50).
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Vendor = GRM.Vendor or {}
local V = GRM.Vendor
V.Version = "2.2.1"

-- ============================================================
-- КОНФИГ
-- ============================================================
V.Config = {
    UseDistance    = 120,     -- дистанция взаимодействия
    MaxVendors     = 64,      -- лимит на карту (доп. к perm)
    SellMultiplier = 0.4,     -- скупка = 40% от цены продажи
}

-- ============================================================
-- МОДЕЛИ NPC ПО ТИПУ
-- ============================================================
V.Models = {
    weapon = "models/mossman.mdl",
    ore    = "models/kleiner.mdl",
    food   = "models/barney.mdl",
    rare   = "models/gman_high.mdl",
    accessory = "models/alyx.mdl",
}

-- v2.2.0: типы торговцев — общий реестр. Раньше список был захардкожен
-- и в этом файле, и в тулгане: новый торговец приходилось вписывать в двух
-- местах. Теперь модуль регистрирует свой тип сам (V.RegisterType).
V.TypeNames = V.TypeNames or {}
V.TypeNames.weapon    = V.TypeNames.weapon or "Арсенал"
V.TypeNames.ore       = V.TypeNames.ore or "Скупщик руды"
V.TypeNames.food      = V.TypeNames.food or "Продукты"
V.TypeNames.rare      = V.TypeNames.rare or "Редкости"
V.TypeNames.accessory = V.TypeNames.accessory or "Аксессуары"
V.TypeNames.phone     = V.TypeNames.phone or "Салон связи"
V.Models.phone        = V.Models.phone or "models/humans/group01/male_07.mdl"

function V.ResolveType(kind, fallback)
    kind = tostring(kind or "")
    if kind ~= "" and (V.TypeNames[kind] or V.Catalogs[kind]) then return kind end
    if kind ~= "" and kind ~= "weapon" then return kind end
    fallback = tostring(fallback or "")
    if fallback ~= "" then return fallback end
    return "weapon"
end

function V.RegisterType(key, label, model, catalog)
    key = tostring(key or "")
    if key == "" then return false end
    V.TypeNames[key] = tostring(label or key)
    if model and model ~= "" then V.Models[key] = model end
    V.Catalogs[key] = V.Catalogs[key] or {}
    if istable(catalog) then
        for id, data in pairs(catalog) do V.Catalogs[key][id] = data end
    end
    return true
end

function V.TypeList()
    local out = {}
    for key, label in pairs(V.TypeNames) do out[#out + 1] = { key = key, name = label } end
    table.sort(out, function(a, b) return string.lower(a.name) < string.lower(b.name) end)
    return out
end

-- ============================================================
-- КАТАЛОГИ (shared, регистрируются до загрузки энтити)
-- ============================================================
V.Catalogs = V.Catalogs or {}
V.Catalogs.accessory = V.Catalogs.accessory or {}
V.Catalogs.phone = V.Catalogs.phone or {}

-- 1) ОРУЖИЕ — ArcCW (базовый набор; расширяется через V.RegisterItem)
V.Catalogs.weapon = V.Catalogs.weapon or {
    ["arccw_ak47"]        = { name = "AK-47 (ArcCW)",     price = 12000, model = "models/weapons/w_rif_ak47.mdl",    category = "Автоматы",  license = "gun", weaponCategory = "rifled" },
    ["arccw_m4a1"]        = { name = "M4A1 (ArcCW)",      price = 13000, model = "models/weapons/w_rif_m4a1.mdl",    category = "Автоматы",  license = "gun", weaponCategory = "rifled" },
    ["arccw_p228"]        = { name = "P228 (ArcCW)",      price = 3500,  model = "models/weapons/w_pist_p228.mdl",   category = "Пистолеты", license = "gun", weaponCategory = "short" },
    ["arccw_deagle"]      = { name = "Desert Eagle (ArcCW)", price = 6500, model = "models/weapons/w_pist_deagle.mdl", category = "Пистолеты", license = "gun", weaponCategory = "short" },
    ["arccw_shotgun"]     = { name = "Remington 870 (ArcCW)", price = 9000, model = "models/weapons/w_shotgun.mdl",   category = "Дробовики", license = "gun", weaponCategory = "smooth" },
    ["arccw_mp5"]         = { name = "MP5 (ArcCW)",       price = 8500,  model = "models/weapons/w_smg_mp5.mdl",     category = "ПП",        license = "gun", weaponCategory = "rifled" },
    ["arrest_stick"]      = { name = "Полицейская дубинка", price = 500, model = "models/weapons/w_stunbaton.mdl",   category = "Спецназ",   license = "police" },
}

-- 2) РУДА — базовые цены, синхронизируются с GRM.OrePrices
V.Catalogs.ore = V.Catalogs.ore or {
    ["ore_copper"]    = { name = "Медная руда",   price = 50,  model = "models/props_junk/rock001a.mdl", oreType = "copper" },
    ["ore_gold"]      = { name = "Золотая руда",  price = 200, model = "models/props_junk/rock001a.mdl", oreType = "gold" },
    ["ore_aluminum"]  = { name = "Алюминиевая",   price = 80,  model = "models/props_junk/rock001a.mdl", oreType = "aluminum" },
    ["ore_platinum"]  = { name = "Платиновая",    price = 350, model = "models/props_junk/rock001a.mdl", oreType = "platinum" },
}

-- 3) ЕДА — синхронизируется с GRM.Food.Config.FoodItems
V.Catalogs.food = V.Catalogs.food or {
    ["grm_food_apple"]  = { name = "Яблоко",   price = 20,  model = "models/props/cs_italy/orange.mdl",                  hunger = 15, health = 2 },
    ["grm_food_bread"]  = { name = "Хлеб",     price = 44,  model = "models/props_junk/garbage_bag001a.mdl",             hunger = 25, health = 3 },
    ["grm_food_water"]  = { name = "Вода",     price = 10,  model = "models/props_junk/garbage_plasticbottle003a.mdl",  hunger = 10, health = 0 },
    ["grm_food_soda"]   = { name = "Газировка", price = 15, model = "models/props_junk/PopCan01a.mdl",                   hunger = 5,  health = 0 },
}

-- 5) РЕДКОСТИ: itemID -> { name, price, model, desc, maxStack, isWeapon }
-- isWeapon=true → выдаётся через ply:Give() (SWEP), иначе через GRM.Inventory.AddItem()
V.Catalogs.rare = V.Catalogs.rare or {
    -- SWEP (оружие) — продаются через ply:Give()
    ["ds_lockpick"]          = { name = "Взломщик (QTE)",        price = 2500,  model = "models/weapons/w_c4.mdl",            desc = "Взлом дверей, кейпадов и сканеров через QTE-мини-игру", maxStack = 1, isWeapon = true },
    -- Единая связка вместо прежних двух свепов (двери + транспорт).
    -- Старые классы остались в сборке ради уже выданных предметов,
    -- но из продажи убраны, чтобы не плодить дубли на руках.
    ["grm_keyring"]          = { name = "Связка ключей",       price = 500,   model = "models/weapons/w_keys.mdl",          desc = "Двери и транспорт: удерживайте ЛКМ рядом — меню действий", maxStack = 1, isWeapon = true },
    ["ds_battering_ram"]     = { name = "Полицейский таран",   price = 5000,  model = "models/weapons/w_rocket_launcher.mdl", desc = "Вскрытие дверей по ордеру",         maxStack = 1, isWeapon = true, license = "police" },
    ["grm_handcuffs"]        = { name = "Наручники",           price = 1500,  model = "models/weapons/w_cuffs.mdl",         desc = "Задержание подозреваемых",           maxStack = 1, isWeapon = true, license = "police" },
    ["weapon_grm_megaphone"] = { name = "Мегафон",             price = 3000,  model = "models/props_lab/tpplug.mdl",        desc = "Громкая связь для оповещений",       maxStack = 1, isWeapon = true },

    -- Предметы инвентаря — продаются через GRM.Inventory.AddItem()
    ["item_repair_kit"]      = { name = "Ремкомплект",         price = 5000,  model = "models/props_c17/tools_wrench.mdl",  desc = "Ремонт транспорта",                  maxStack = 3 },
    ["radio_modulator"]      = { name = "Модулятор рации",     price = 8000,  model = "models/props_lab/citizenradio.mdl",  desc = "Доступ к зашумлённым частотам",      maxStack = 1 },
    ["item_healthkit"]       = { name = "Аптечка",             price = 300,   model = "models/items/healthkit.mdl",         desc = "Лечит 25 HP",                        maxStack = 5 },
    ["item_battery"]         = { name = "Батарея",             price = 250,   model = "models/items/battery.mdl",           desc = "Восстанавливает 15 брони",           maxStack = 5 },
    ["grm_money_printer"]    = { name = "Денежный принтер",     price = 25000, model = "models/props_lab/reciever01b.mdl",   desc = "Редкий аппарат для печати GRM. Спавнится рядом и привязывается к покупателю.", maxStack = 1, isEntity = true, class = "grm_money_printer", noSell = true },
}

-- ============================================================
-- СИНХРОНИЗАЦИЯ С РЕАЛЬНЫМИ МОДУЛЯМИ GRM
-- ============================================================

-- Синхронизация цен руды из GRM.OrePrices (sh_grm_ore_admin.lua)
if GRM.OrePrices then
    for oreType, price in pairs(GRM.OrePrices) do
        local id = "ore_" .. oreType
        if V.Catalogs.ore[id] then
            V.Catalogs.ore[id].price = price
        end
    end
end

-- Синхронизация еды из GRM.Food.Config.FoodItems (sh_grm_food_config.lua)
if GRM.Food and GRM.Food.Config and GRM.Food.Config.FoodItems then
    for id, data in pairs(GRM.Food.Config.FoodItems) do
        if V.Catalogs.food[id] then
            V.Catalogs.food[id].price = data.price or V.Catalogs.food[id].price
            V.Catalogs.food[id].hunger = data.hungerRestore
            V.Catalogs.food[id].health = data.healthRestore
        end
    end
end

-- Автодобавление руд из sh_grm_ore_defs.lua (RegisterOre)
if GRM.OreDefs then
    for id, def in pairs(GRM.OreDefs) do
        if not V.Catalogs.ore[id] then
            V.Catalogs.ore[id] = {
                name    = def.name or id,
                price   = (GRM.OrePrices and GRM.OrePrices[def.oreType or id:gsub("ore_","")]) or 50,
                model   = def.model or "models/props_junk/rock001a.mdl",
                oreType = def.oreType or id:gsub("ore_",""),
            }
        end
    end
end

-- ============================================================
-- API
-- ============================================================

function V.GetCatalog(vendorType)
    return V.Catalogs[vendorType] or {}
end

function V.GetItem(vendorType, id)
    return V.GetCatalog(vendorType)[id]
end

function V.IsItemEnabled(ent, id)
    if not IsValid(ent) then return false end
    local enabled = ent.EnabledItems
    if not istable(enabled) or next(enabled) == nil then return true end
    return enabled[tostring(id or "")] == true
end

function V.GetPrice(ent, id, item)
    item = item or (IsValid(ent) and V.GetItem(ent.VendorType, id))
    if not item then return 0 end
    local custom = IsValid(ent) and ent.CustomPrices and ent.CustomPrices[id]
    return math.Clamp(math.floor(tonumber(custom) or tonumber(item.price) or 0), 0, 100000000)
end

function V.GetLimit(ent, id)
    return math.Clamp(math.floor(tonumber(IsValid(ent) and ent.CustomLimits and ent.CustomLimits[id]) or 0), 0, 10000)
end

function V.GetDisplayName(ent)
    if IsValid(ent) and tostring(ent.DisplayName or "") ~= "" then return tostring(ent.DisplayName):sub(1, 64) end
    return V.TypeNames[IsValid(ent) and ent.VendorType or ""] or "GRM Торгаш"
end

function V.GetSellPrice(ply, vendorType, id)
    local item = V.GetItem(vendorType, id)
    if not item or item.noSell or item.isEntity then return 0 end
    return math.floor((item.price or 0) * V.Config.SellMultiplier)
end

-- Проверка лицензии на оружие (использует Factions из sh_factions.lua)
function V.CanBuyWeapon(ply, item)
    if not IsValid(ply) or not istable(item) then return false, "Некорректный покупатель или товар" end
    if ply:IsSuperAdmin() then return true end

    if item.license == "admin" then return false, "Товар доступен только суперадминистратору" end
    if item.license == "police" then
        for name, faction in pairs(Factions or {}) do
            local low=string.lower(tostring(name))
            if (low:find("polizei",1,true) or low:find("полици",1,true) or low:find("жандар",1,true))
                and GRM.Identity and GRM.Identity.FactionMember and GRM.Identity.FactionMember(faction,ply) then return true end
        end
        return false, "Требуется служебный допуск полиции или жандармерии"
    end

    -- Любое огнестрельное оружие оружейного торговца требует действующую
    -- лицензию именно нужной категории, а не декоративный флаг «gun».
    if item.isWeapon and (item.license == "gun" or item.weaponCategory) then
        local DOC=GRM.Documents
        if not (DOC and DOC.HasValidWeaponLicense) then return false, "Система лицензий на оружие не загружена" end
        local charKey=(GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply)) or (ply:SteamID64()..":char1")
        local category=tostring(item.weaponCategory or "short")
        local ok,why=DOC.HasValidWeaponLicense(charKey,category)
        if not ok then return false,"Нужна действующая лицензия на оружие: "..category.." ("..tostring(why or "нет допуска")..")" end
    end
    return true
end

-- Регистрация каталога из аддонов
function V.RegisterCatalog(vendorType, items)
    V.Catalogs[vendorType] = V.Catalogs[vendorType] or {}
    for id, data in pairs(items or {}) do
        V.Catalogs[vendorType][id] = data
    end
end

-- Регистрация одной позиции
function V.RegisterItem(vendorType, id, data)
    V.Catalogs[vendorType] = V.Catalogs[vendorType] or {}
    V.Catalogs[vendorType][id] = data
end

-- Регистрация модели NPC для нового типа
function V.RegisterModel(vendorType, model)
    V.Models[vendorType] = model
end

-- ============================================================
-- ВАЛИДНАЯ ПЕРСИСТЕНТНОСТЬ ТОРГАШЕЙ
-- ============================================================
if SERVER then
    local DATA_DIR = "grm_vendors"
    local function mapFile()
        if not file.IsDir(DATA_DIR, "DATA") then file.CreateDir(DATA_DIR) end
        return DATA_DIR .. "/" .. string.lower(game.GetMap() or "unknown") .. ".json"
    end
    local function jsonT(raw)
        local ok, data = pcall(util.JSONToTable, raw or "", false, true)
        return ok and istable(data) and data or nil
    end
    local function readRecords()
        if not file.Exists(mapFile(), "DATA") then return {} end
        local raw = file.Read(mapFile(), "DATA") or ""
        local data = jsonT(raw)
        if not data then
            print("[GRM Vendor][!] Не удалось разобрать " .. mapFile() .. " (" .. #raw .. " байт)")
            return {}
        end
        -- v2 хранит wrapper.vendors; старый формат был голым массивом.
        -- pairs намеренно: ignoreConversions=true на некоторых сборках GMod
        -- оставляет индексы JSON-массива строками, и ipairs видел 0 записей.
        local source = istable(data.vendors) and data.vendors or (istable(data.records) and data.records or data)
        local out = {}
        for _, rec in pairs(source) do
            if istable(rec) and isstring(rec.id) and istable(rec.pos) and istable(rec.ang) then out[#out + 1] = rec end
        end
        table.sort(out, function(a,b) return tostring(a.id) < tostring(b.id) end)
        return out
    end
    local function writeRecords(records)
        local wrapper = { version = 2, map = game.GetMap(), vendors = records or {} }
        local ok, raw = pcall(util.TableToJSON, wrapper, true)
        if not ok or not isstring(raw) then return false end
        file.Write(mapFile(), raw)
        if file.Read(mapFile(), "DATA") ~= raw then return false end
        local verify = jsonT(raw)
        local source = verify and verify.vendors
        if not istable(source) then return false end
        local valid = 0
        for _, rec in pairs(source) do if istable(rec) and isstring(rec.id) then valid = valid + 1 end end
        if valid ~= #(records or {}) then
            print(("[GRM Vendor][!] Read-back parse mismatch: ожидалось %d, прочитано %d"):format(#(records or {}), valid))
            return false
        end
        return true
    end
    local function vecData(v) return { x = v.x, y = v.y, z = v.z } end
    local function angData(a) return { p = a.p, y = a.y, r = a.r } end
    local function vec(t) return Vector(tonumber(t.x) or 0, tonumber(t.y) or 0, tonumber(t.z) or 0) end
    local function ang(t) return Angle(tonumber(t.p) or 0, tonumber(t.y) or 0, tonumber(t.r) or 0) end
    local function ensureID(ent)
        if not IsValid(ent) then return "" end
        local id = tostring(ent.GRMVendorID or "")
        if id == "" then
            local p = ent:GetPos()
            id = "vendor_" .. util.CRC(table.concat({game.GetMap(), ent.VendorType or "weapon", p.x, p.y, p.z, SysTime(), math.random()}, ":"))
            ent.GRMVendorID = id
        end
        ent:SetNWString("GRMVendorID", id)
        return id
    end
    local function makeRecord(ent)
        local id = ensureID(ent)
        local p, a = ent:GetPos(), ent:GetAngles()
        return {
            id = id, vendorType = tostring(ent.VendorType or "weapon"), model = tostring(ent:GetModel() or ""),
            pos = vecData(p), ang = angData(a), customPrices = table.Copy(ent.CustomPrices or {}),
            customLimits = table.Copy(ent.CustomLimits or {}), enabledItems = table.Copy(ent.EnabledItems or {}),
            displayName = tostring(ent.DisplayName or ""):sub(1, 64),
        }
    end
    local function findRecord(records, id)
        for index, rec in ipairs(records) do if tostring(rec.id) == tostring(id) then return rec, index end end
    end
    local function findLive(rec)
        for _, ent in ipairs(ents.FindByClass("grm_vendor")) do
            if IsValid(ent) then
                if tostring(ent.GRMVendorID or "") == tostring(rec.id) then return ent end
                if ent:GetPos():DistToSqr(vec(rec.pos)) <= 8 * 8 then return ent end
            end
        end
    end
    local function applyRecord(ent, rec)
        if not IsValid(ent) then return false end
        ent.GRMVendorID = tostring(rec.id)
        ent.GRMVendorPersistent = true
        ent.VendorType = V.ResolveType(rec.vendorType, rec.vendorType)
        ent.CustomPrices = table.Copy(rec.customPrices or {})
        ent.CustomLimits = table.Copy(rec.customLimits or {})
        ent.EnabledItems = table.Copy(rec.enabledItems or {})
        ent.DisplayName = tostring(rec.displayName or ""):sub(1, 64)
        ent:SetNWString("GRMVendorID", ent.GRMVendorID)
        ent:SetNWString("GRMVendorName", V.GetDisplayName(ent))
        if ent.ApplyPermData then
            ent:ApplyPermData({vendorType=ent.VendorType,model=rec.model,customPrices=ent.CustomPrices,customLimits=ent.CustomLimits,enabledItems=ent.EnabledItems,displayName=ent.DisplayName,vendorID=ent.GRMVendorID})
        else
            ent:SetNWString("VendorType", ent.VendorType)
            ent:SetModel(V.Models[ent.VendorType] or rec.model or "models/kleiner.mdl")
        end
        return true
    end
    local function spawnRecord(rec)
        local existing = findLive(rec)
        if IsValid(existing) then applyRecord(existing, rec); return existing, false end
        local ent = ents.Create("grm_vendor")
        if not IsValid(ent) then return nil, false end
        ent.VendorType = V.ResolveType(rec.vendorType, rec.vendorType)
        ent.GRMVendorID = tostring(rec.id)
        ent.CustomPrices = table.Copy(rec.customPrices or {})
        ent.CustomLimits = table.Copy(rec.customLimits or {})
        ent.EnabledItems = table.Copy(rec.enabledItems or {})
        ent.DisplayName = tostring(rec.displayName or ""):sub(1, 64)
        ent.VendorModel = tostring(rec.model or "")
        ent:SetPos(vec(rec.pos)); ent:SetAngles(ang(rec.ang)); ent:Spawn(); ent:Activate()
        applyRecord(ent, rec)
        local phys = ent:GetPhysicsObject(); if IsValid(phys) then phys:EnableMotion(false); phys:Sleep() end
        if GRM.PropProtect and GRM.PropProtect.MarkServerEntity then GRM.PropProtect.MarkServerEntity(ent) end
        return ent, true
    end

    function V.SaveVendor(ent)
        if not IsValid(ent) or ent:GetClass() ~= "grm_vendor" then return false, "Торгаш не найден" end
        local records, rec = readRecords(), makeRecord(ent)
        local _, index = findRecord(records, rec.id)
        if index then records[index] = rec else records[#records + 1] = rec end
        ent.GRMVendorPersistent = true
        return writeRecords(records), rec.id
    end
    function V.RemoveVendorSaveByID(id)
        id = tostring(id or "")
        if id == "" then return false end
        local records, removed = readRecords(), false
        for i = #records, 1, -1 do
            if tostring(records[i].id) == id then table.remove(records, i); removed = true end
        end
        return removed and writeRecords(records) or false
    end
    function V.RemoveVendorSave(ent)
        if not IsValid(ent) or ent:GetClass() ~= "grm_vendor" then return false end
        local records, id = readRecords(), tostring(ent.GRMVendorID or "")
        local removed = false
        for i = #records, 1, -1 do
            if records[i].id == id or ent:GetPos():DistToSqr(vec(records[i].pos)) <= 8 * 8 then table.remove(records, i); removed = true end
        end
        ent.GRMVendorPersistent = nil
        return removed and writeRecords(records) or false
    end
    function V.SaveMapVendors()
        -- Save-all обновляет/добавляет живых торговцев, но НЕ удаляет
        -- отсутствующие записи. Иначе Save после cleanup/временного удаления
        -- превращал валидную базу в [] и последующий Load «ничего не делал».
        local records = readRecords()
        local updated = 0
        for _, ent in ipairs(ents.FindByClass("grm_vendor")) do
            if IsValid(ent) then
                local rec = makeRecord(ent)
                local _, index = findRecord(records, rec.id)
                if index then records[index] = rec else records[#records + 1] = rec end
                ent.GRMVendorPersistent = true
                updated = updated + 1
            end
        end
        table.sort(records, function(a,b) return a.id < b.id end)
        if not writeRecords(records) then return false, "ошибка записи/read-back" end
        return true, ("обновлено живых %d, в базе всего %d"):format(updated, #records)
    end
    function V.LoadMapVendors()
        local records = readRecords()
        if #records == 0 then return false, "в базе этой карты нет сохранённых торгашей: data/" .. mapFile() end
        local spawned, healed, failed = 0, 0, 0
        for _, rec in ipairs(records) do
            local ent, created = spawnRecord(rec)
            if IsValid(ent) then if created then spawned = spawned + 1 else healed = healed + 1 end else failed = failed + 1 end
        end
        if failed > 0 then return false, ("создано %d, уже стояло %d, ошибок %d"):format(spawned, healed, failed) end
        return true, ("создано %d, уже стояло/обновлено %d"):format(spawned, healed)
    end
    function V.ListSavedVendors() return readRecords() end

    -- Старые grm_vendor из универсального perm-файла переносим один раз,
    -- затем удаляем оттуда, чтобы два механизма никогда не создавали дубль.
    local function migrateLegacyPerm()
        local path = "grm_perm_entities.json"
        if not file.Exists(path, "DATA") then return end
        local legacy = jsonT(file.Read(path, "DATA")); if not legacy then return end
        local keep, records, changed = {}, readRecords(), false
        for _, old in ipairs(legacy) do
            if old.class == "grm_vendor" and old.map == game.GetMap() then
                local id = "vendor_legacy_" .. util.CRC(util.TableToJSON(old) or tostring(#records + 1))
                if not findRecord(records, id) then
                    records[#records + 1] = {id=id,vendorType=old.data and old.data.vendorType or "weapon",model=old.model,pos=old.pos,ang=old.ang,customPrices=old.data and old.data.customPrices or {},customLimits=old.data and old.data.customLimits or {}}
                end
                changed = true
            else keep[#keep + 1] = old end
        end
        if changed then writeRecords(records); local ok, raw=pcall(util.TableToJSON,keep,true); if ok then file.Write(path,raw) end end
    end

    local function aimVendor(ply)
        local tr = ply:GetEyeTrace(); local ent = tr and tr.Entity
        if IsValid(ent) and ent:GetClass()=="grm_vendor" and ply:GetPos():DistToSqr(ent:GetPos())<=300*300 then return ent end
    end
    local function message(ply, ok, text)
        if GRM.Notify then GRM.Notify(ply,text,ok and 100 or 255,ok and 220 or 120,ok and 130 or 90) else ply:ChatPrint("[Торгаши] "..text) end
    end
    --[[ АДМИНСКИЕ КОМАНДЫ ТОРГАШЕЙ — таблица вместо лестницы `elseif cmd ==`.
         Права проверяются ОДИН раз до диспетчеризации: раньше проверка
         жила снаружи лестницы, но каждую новую команду приходилось
         вписывать внутрь простыни, и легко было добавить её мимо
         проверки. Контракт: (ply, argument). ]]
    local VENDOR_COMMANDS = {
        save = function(ply)
            local ok, id = V.SaveVendor(aimVendor(ply))
            message(ply, ok, ok and ("Торгаш сохранён: " .. id) or tostring(id))
        end,

        remove = function(ply, argument)
            -- Снять можно и по прицелу, и по ID: торгаша могло уже не быть
            -- на карте, а запись о нём осталась.
            local ent = aimVendor(ply)
            local ok = IsValid(ent) and V.RemoveVendorSave(ent) or V.RemoveVendorSaveByID(argument)
            message(ply, ok, ok and "Торгаш снят с сохранения"
                or "Наведи на торгаша или укажи ID: /vendor_unsave vendor_...")
        end,

        save_all = function(ply)
            local ok, text = V.SaveMapVendors()
            message(ply, ok, text)
        end,

        load = function(ply)
            local ok, text = V.LoadMapVendors()
            message(ply, ok, text)
        end,

        list = function(ply)
            local list = V.ListSavedVendors()
            message(ply, true, "Сохранено торгашей: " .. #list)
            for i, r in ipairs(list) do
                print(("[GRM Vendor] #%d %s %s @ %.0f %.0f %.0f")
                    :format(i, r.id, r.vendorType, r.pos.x, r.pos.y, r.pos.z))
            end
        end,
    }

    local function command(ply, cmd, argument)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        local run = VENDOR_COMMANDS[cmd]
        if run then run(ply, argument) end
    end
    concommand.Add("grm_vendor_save",function(p) command(p,"save") end)
    concommand.Add("grm_vendor_unsave",function(p,_,args) command(p,"remove",args[1]) end)
    concommand.Add("grm_vendor_save_all",function(p) command(p,"save_all") end)
    concommand.Add("grm_vendor_load",function(p) command(p,"load") end)
    hook.Add("PlayerSay", "GRM_Vendor_PersistenceCommands", function(ply, text, teamSays)
        local pack = { tostring(text or ""), SkipPlayerSay = false }
            if not istable(pack) or not isstring(pack[1]) then return end
            local text=string.Trim(pack[1]); local name,argument=text:match("^(%S+)%s*(.-)$")
            local map={['/vendor_save']='save',['/vendor_unsave']='remove',['/vendor_save_all']='save_all',['/vendor_load']='load',['/vendor_list']='list'}
            local cmd=map[string.lower(name or "")]; if not cmd then return end
            command(ply,cmd,argument); pack[1]=""; pack.SkipPlayerSay=true

        if pack.SkipPlayerSay == true then return "" end
    end)
    grmBootStart("GRM_Vendor_PersistenceLoad","normal",function() timer.Simple(1.4,function() migrateLegacyPerm(); V.LoadMapVendors() end) end)
    hook.Add("PostCleanupMap","GRM_Vendor_PersistenceCleanup",function() timer.Simple(0.8,function() V.LoadMapVendors() end) end)
end

print("[GRM Vendor] Framework v"..V.Version.." loaded (Code 111)")
