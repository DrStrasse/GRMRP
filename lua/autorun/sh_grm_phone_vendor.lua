--[[--------------------------------------------------------------------
    GRM Phone Vendor v1.0.0 — «Салон связи» (торговец телефонами)

    Заказ владельца: «торговец телефонами нужен».

    Что это:
      • Новый тип торговца в существующем фреймворке GRM.Vendor —
        vendorType = "phone". Отдельный энтити не плодим: используется
        тот же grm_vendor, то же сохранение (perm entities), тот же UI
        киоска и та же админка тулгана.
      • Ассортимент строится ИЗ РЕЕСТРА ТЕЛЕФОНОВ sh_grm_mobile.lua
        (GRM.Mobile.Tiers), а не дублируется руками: добавили модель
        телефона в мобильную систему — она сразу появилась у торговца
        с правильной ценой, моделью и описанием возможностей.
      • Покупка выдаёт предмет инвентаря (mobile_*), тот самый, который
        мобильная система считает «носимым телефоном» (MB.CarriedTier).
      • Скупка (продажа торговцу) работает штатно: 40% от цены.

    Установка на карту:
      Q → Инструменты → GRM → GRM Торговец → тип «Салон связи» → ЛКМ.
      ПКМ по торговцу — цены, лимиты и включение позиций.

    Команды: не нужны, всё через тулган (как у остальных торговцев).
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.PhoneVendor = GRM.PhoneVendor or {}
local PV = GRM.PhoneVendor
PV.Version = "1.0.0"

-- Модель продавца в салоне связи.
PV.NPCModel = "models/humans/group01/male_07.mdl"

local function tierDescription(tier)
    local feats = {}
    feats[#feats + 1] = "звонки"
    if tier.sms then feats[#feats + 1] = "SMS" end
    if tier.contacts then feats[#feats + 1] = "контакты" end
    if tier.notes then feats[#feats + 1] = "заметки" end
    if tier.apps then feats[#feats + 1] = "приложения" end

    local base = tostring(tier.desc or "")
    local line = "Возможности: " .. table.concat(feats, ", ") .. "."
    local q = tonumber(tier.minQ)
    if q then
        line = line .. " Минимальный уровень сигнала: " .. tostring(math.Round(q * 100)) .. "%."
    end
    return (base ~= "" and (base .. " ") or "") .. line
end

-- Собрать каталог из реестра телефонов. Вызывается и при загрузке, и по
-- требованию (мобильная система может догрузиться позже — Boot это учитывает).
function PV.BuildCatalog()
    local MB = GRM.Mobile
    if not (istable(MB) and istable(MB.Tiers)) then return nil end

    local catalog = {}
    local order = istable(MB.Order) and MB.Order or nil
    local keys = {}
    if order then
        for _, k in ipairs(order) do keys[#keys + 1] = k end
    else
        for k in pairs(MB.Tiers) do keys[#keys + 1] = k end
        table.sort(keys)
    end

    for index, key in ipairs(keys) do
        local tier = MB.Tiers[key]
        if istable(tier) and isstring(tier.item) and tier.item ~= "" then
            catalog[tier.item] = {
                name     = tostring(tier.name or key),
                price    = math.max(0, math.floor(tonumber(tier.price) or 0)),
                model    = tostring(tier.model or "models/props_lab/reciever01b.mdl"),
                desc     = tierDescription(tier),
                category = tier.apps and "Смартфоны" or "Телефоны",
                maxStack = 1,
                sortIndex = index,
                phoneTier = key,
            }
        end
    end

    if next(catalog) == nil then return nil end
    return catalog
end

function PV.Register()
    local V = GRM.Vendor
    if not (istable(V) and isfunction(V.RegisterType)) then return false, "GRM.Vendor не загружен" end

    -- Тип регистрируем сразу: иначе LoadMapVendors видит пустой Catalogs.phone
    -- и тихо превращает салон связи в оружейника.
    V.RegisterType("phone", "Салон связи", PV.NPCModel)

    local catalog = PV.BuildCatalog()
    if catalog then V.RegisterType("phone", "Салон связи", PV.NPCModel, catalog) end
    PV.Registered = catalog ~= nil
    if catalog and SERVER then
        for _, ent in ipairs(ents.FindByClass("grm_vendor")) do
            if IsValid(ent) and tostring(ent.VendorType or "") == "phone" then
                ent:SetNWString("VendorType", "phone")
                ent:SetNWString("GRMVendorName", V.GetDisplayName(ent))
                if tostring(ent:GetModel() or "") == (V.Models.weapon or "") then
                    ent:SetModel(PV.NPCModel)
                end
            end
        end
    end
    return catalog ~= nil, catalog and table.Count(catalog) or "каталог позже"
end

-- Регистрируем через Boot: телефоны и вендор — разные файлы, порядок
-- загрузки автозапуска алфавитный и не гарантирован. Boot дожидается,
-- когда обе подсистемы окажутся в памяти, и не занимает кадр стартом.
local function registerWhenReady()
    local ok = PV.Register()
    if ok then return true end
    return false
end

if SERVER or CLIENT then
    timer.Simple(0, function() PV.Register() end)
end

if GRM.Boot and GRM.Boot.Task then
    GRM.Boot.Task("vendor.phone", "normal", function()
        if registerWhenReady() then return end
        -- Мобильная система ещё не поднялась — пробуем ещё раз позже,
        -- максимум 10 попыток по 1 секунде, потом сдаёмся с записью в лог.
        local tries = 0
        timer.Create("GRM_PhoneVendor_Retry", 1, 10, function()
            tries = tries + 1
            if registerWhenReady() then
                timer.Remove("GRM_PhoneVendor_Retry")
            elseif tries >= 10 then
                print("[GRM PhoneVendor] реестр телефонов не найден — торговец не зарегистрирован")
            end
        end)
    end)
else
    hook.Add("InitPostEntity", "GRM_PhoneVendor_Register", function()
        timer.Simple(1, registerWhenReady)
    end)
end

concommand.Add("grm_phone_vendor_reload", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    local ok, detail = PV.Register()
    local msg = ok and ("[GRM PhoneVendor] каталог обновлён, позиций: " .. tostring(detail))
        or ("[GRM PhoneVendor] " .. tostring(detail))
    if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg) else print(msg) end
end)
