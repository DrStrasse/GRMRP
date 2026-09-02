-- Boot-шим: старт подсистемы идёт через планировщик GRM.Boot (приоритеты и
-- бюджет на тик). Если планировщик почему-то не загружен, работаем по-старому.
local function grmBootStart(id, tier, fn)
    if GRM and GRM.Boot and GRM.Boot.OnMapStart then return GRM.Boot.OnMapStart(id, tier, fn) end
    return hook.Add("InitPostEntity", id, fn)
end

--[[--------------------------------------------------------------------
    GRM HUD v10.8 — Полноценный HUD для Sandbox
    v10.8: grm_money_diag — самодиагностика денежного трека (владелец
           вечер-11: «деньги не отражает»: данные шли, вопрос был в слое
           отрисовки — теперь видно и то, и другое: баланс, счёт, давность
           последнего grm_balance).    v10.7: деньги переехали в ДВЕ НИЖНИЕ КАССЕТЫ «СОСТОЯНИЯ» (контракт
           sim_hud_bars, ожидавший с вечера-8): верхний левый угол занят
           подсказкой инструмента — движок рисует tool-HUD поверх попопов,
           и «НАЛИЧНЫЕ/СЧЁТ» под ним терялись (владелец, вечер-10: «деньги
           не отражает, где наличка и счёт?»). Кассеты всегда в панели —
           перекрыть нечем.
    v10.6: селектор — «листать невозможно» (владелец 03.09 вечер-9): обход
           слотов был зашит в 1..6, а когда our обход не мог сдвинуться,
           бинд всё равно глотался (return true) — колесо молчало целиком.
           Теперь: слоты 1..10 (TFA/CW/ARC9 живут за шестёркой), оружие из
           «неудобных» слотов не выбрасывается, а при нулевом ходе бинд
           уходит движку (ванильное листание сохраняется); ширина бара —
           по факту инвентаря; grm_sel_diag — самодиагностика «доходят ли
           бинды и что с ними стало».
    v10.5: колесо ПЕРЕКЛЮЧАЕТ оружие сразу, как ванильный GMod (заказ
           владельца 03.09 вечер-6: «селектор так и не починили» = тик
           колеса не менял оружие; бар GRM — визуальный слой, ЛКМ только
           закрывает его). Физган-занятость по-прежнему глотает колесо.
    v10.4: колесо и клавиши слотов только двигают подсветку; таймаут
           закрывает панель без смены оружия. Выбор выполняется лишь ЛКМ.
    v10.3: колесо/слоты/таймаут селектора НЕ сменяют оружие, пока
           физган или гравиган держит проп (IN_ATTACK). Иначе при
           вращении/подтягивании пропа бар открывался, через 3 с
           input.SelectWeapon снимал физган — проп падал.
    v10.2: разделённые строки денег «НАЛИЧКА» (кошелёк, ядро валюты)
           и «НА СЧЁТУ» (банк, экономика → GRM_Bank_Sync)
    v10.1: ресивер grm_balance рассылает хук GRM_BalanceUpdated
           (мгновенное обновление Tab Menu); сумма рисуется через
           GRM.Format (имя валюты из экономики), $ — только fallback
    Путь: garrysmod/addons/grm_hud/lua/autorun/client/cl_grm_hud.lua
    (Код 48; сохранено агентом: снят ГМЛ-манглинг веб-вставки — восстановлены < > * _)
--------------------------------------------------------------------]]
if not CLIENT then return end

GRM = GRM or {}
GRM.HUD = GRM.HUD or {}
GRM.HUD.Config = {
    -- Каноническая палитра GRM/XUI (cl_grm_ui_theme.lua):
    -- почти чёрный сине-стальной, неоновые акценты.
    bgColor        = Color(8, 14, 23, 150),
    bgShadow       = Color(0, 0, 0, 36),
    panelHeader    = Color(10, 22, 37, 165),
    lineColor      = Color(55, 117, 151, 190),
    textColor      = Color(225, 238, 247, 255),
    labelColor     = Color(132, 160, 178, 255),
    hpColorFull    = Color(64, 222, 147, 255),
    hpColorMid     = Color(250, 185, 63, 255),
    hpColorLow     = Color(244, 78, 96, 255),
    armorColor     = Color(48, 204, 255, 255),
    moneyColor     = Color(64, 222, 147, 255),
    bankColor      = Color(95, 170, 255, 255),
    ammoColor      = Color(250, 185, 63, 255),
    ammo2Color     = Color(180, 180, 190, 255),
    slotBg         = Color(16, 27, 42, 225),
    slotBorder     = Color(55, 117, 151, 190),
    slotActive     = Color(48, 204, 255, 255),
    slotHover      = Color(60, 120, 200, 150),
    slotText       = Color(200, 205, 215, 255),
    slotKeyColor   = Color(255, 200, 60, 255),
    animSpeed       = 8,
    selectorTimeout = 3,
}

--[[--------------------------------------------------------------------
    ЕДИНАЯ ПАНЕЛЬ СОСТОЯНИЯ (переработка 22.08 по заказу владельца).

    Было: здоровье и броня рисовались здесь, сытость — в своём файле по
    АБСОЛЮТНЫМ координатам (x = ScrW() - 1066, y = 1044 — на других
    разрешениях улетало), вес — по центру снизу, выносливость — ещё где-то.
    Полосы жили каждая своей жизнью, налезали друг на друга и появлялись в
    разных углах экрана.

    Стало: один список полос. Модуль не рисует ничего сам — он объявляет
    свою полосу и отдаёт значение:

        GRM.HUD.RegisterBar("hunger", {
            label = "СЫТОСТЬ", order = 30,
            Get = function() return value, max, "текст", Color(...) end,
        })

    Панель сама решает, где всё это стоит, какой ширины и в каком порядке,
    и растёт по высоте под количество полос. Порядок задаётся числом order:
    10 здоровье, 20 броня, 30 выносливость, 40 дыхание, 50 сытость, 55 жажда, 60 вес.
----------------------------------------------------------------------]]
GRM.HUD.Bars = GRM.HUD.Bars or {}

function GRM.HUD.RegisterBar(id, def)
    id = tostring(id or "")
    if id == "" or not istable(def) or not isfunction(def.Get) then return false end
    def.id = id
    def.label = tostring(def.label or id)
    def.order = tonumber(def.order) or 100
    GRM.HUD.Bars[id] = def
    return true
end

function GRM.HUD.RemoveBar(id) GRM.HUD.Bars[tostring(id or "")] = nil end

-- Autorun грузится по алфавиту: Food/Movement могут выполниться РАНЬШЕ HUD
-- и тогда не увидеть RegisterBar. Базовые провайдеры регистрируются здесь
-- повторно; если модуль загрузился позже, он просто заменит тот же id своим
-- более детальным вариантом.
GRM.HUD.RegisterBar("hunger", {
    label = "СЫТОСТЬ", order = 50,
    Get = function()
        local food = GRM.Food or {}
        local cfg = food.Config or {}
        local max = tonumber(cfg.HungerMax) or 100
        local value = math.Clamp(tonumber(food.ClientHunger) or max, 0, max)
        local frac = value / math.max(1, max)
        local color = frac < 0.2 and Color(220, 90, 30) or (frac < 0.5 and Color(240, 150, 40) or Color(250, 175, 45))
        local text = frac <= 0 and "ГОЛОДАНИЕ" or (math.floor(value) .. "%")
        return value, max, text, color
    end,
})

GRM.HUD.RegisterBar("stamina", {
    label = "ВЫНОСЛИВОСТЬ", order = 30,
    Get = function()
        local move = GRM.Movement or {}
        local max = tonumber(move.Config and move.Config.StaminaMax) or 100
        local value = math.Clamp(tonumber(GRM.LocalStamina) or max, 0, max)
        local frac = value / math.max(1, max)
        local color = frac < 0.3 and Color(130, 45, 200) or (frac < 0.6 and Color(155, 70, 230) or Color(175, 90, 255))
        return value, max, math.floor(value) .. "%", color
    end,
})

--- Полосы по порядку (чистая функция — гоняется стендом).
function GRM.HUD.BarList()
    local out = {}
    for _, def in pairs(GRM.HUD.Bars) do out[#out + 1] = def end
    table.sort(out, function(a, b)
        if a.order == b.order then return a.id < b.id end
        return a.order < b.order
    end)
    return out
end

-- ШРИФТЫ
if not GRM.HUD._fontsCreated then
    GRM.HUD._fontsCreated = true
    local fonts = {
        {"GRM_HUD_Label",      10, 600},
        {"GRM_HUD_Value",      14, 700},
        {"GRM_HUD_ValueLg",    18, 700},
        {"GRM_HUD_Money",      13, 700},
        {"GRM_HUD_Ammo",       28, 700},
        {"GRM_HUD_Ammo2",      16, 600},
        {"GRM_Notify",         13, 500},
        {"GRM_SlotKey",        11, 700},
        {"GRM_SlotName",       11, 500},
        {"GRM_SlotNameActive", 12, 600},
    }
    for _, f in ipairs(fonts) do
        surface.CreateFont(f[1], {
            font      = "Roboto",
            size      = f[2],
            weight    = f[3],
            extended  = true,
            antialias = true,
        })
    end
end
surface.CreateFont("GRM_HUD_Name", { font = "Roboto", size = 16, weight = 700, extended = true, antialias = true })
surface.CreateFont("GRM_HUD_Meta", { font = "Roboto", size = 12, weight = 500, extended = true, antialias = true })
surface.CreateFont("GRM_HUD_TimeBig", { font = "Roboto", size = 26, weight = 800, extended = true, antialias = true })
surface.CreateFont("GRM_HUD_TimeDate", { font = "Roboto", size = 15, weight = 700, extended = true, antialias = true })

-- БАЛАНС
GRM.PlayerBalance = GRM.PlayerBalance or 0
if not GRM.HUD._balRcv then
    GRM.HUD._balRcv = true
    net.Receive("grm_balance", function()
        local bal = net.ReadInt(32)
        GRM.PlayerBalance = bal
        GRM.HUD._balT = CurTime() -- штамп получения — для grm_money_diag
        -- Фан-аут для Tab Menu (Код 47) и других модулей: HUD грузится
        -- последним и перекрывает их ресиверы, поэтому рассылаем хук.
        hook.Run("GRM_BalanceUpdated", bal)
    end)
end

-- Вечер-12: самодиагностика денег (по образцу grm_sel_diag): отличает
-- «данные не приходят» от «данные есть, но их негде увидеть».
if concommand and concommand.Add then
    concommand.Add("grm_money_diag", function()
        local lp = LocalPlayer()
        print(string.format("[GRM money] v10.8 наличка=%s · счёт=%s · NW2=%s · net %s",
            tostring(GRM.PlayerBalance), tostring(GRM.PlayerBank),
            IsValid(lp) and tostring(lp:GetNW2Int("GRM_Money", -1)) or "—",
            GRM.HUD._balT and string.format("%.1fс назад", CurTime() - GRM.HUD._balT) or "НИКОГДА"))
        if GRM.HUD._balT == nil then
            print("[GRM money] ВЫВОД: grm_balance ни разу не приходил — виновата синхронизация экономики (сервер), а не HUD")
        end
    end)
end

-- УВЕДОМЛЕНИЯ
GRM.Notifications = GRM.Notifications or {}
if not GRM.HUD._notRcv then
    GRM.HUD._notRcv = true
    net.Receive("grm_notify", function()
        GRM.AddNotification(net.ReadString(), 5, Color(net.ReadUInt(8), net.ReadUInt(8), net.ReadUInt(8), 255))
    end)
end

function GRM.AddNotification(text, duration, color)
    duration = duration or 5
    color = color or Color(255, 255, 255, 255)
    table.insert(GRM.Notifications, 1, { text = text, time = CurTime(), duration = duration, color = color, alpha = 0, yOff = 12 })
    while #GRM.Notifications > 6 do table.remove(GRM.Notifications) end
end

grmBootStart("GRM_HUD_ReqBal", "late", function()
    timer.Simple(1, function()
        local function pooled(name)
            return util.NetworkStringToID and util.NetworkStringToID(name) ~= 0
        end
        if pooled("grm_request_bal") then
            net.Start("grm_request_bal")
            net.SendToServer()
        end
        if pooled("GRM_Bank_Request") then
            net.Start("GRM_Bank_Request")
            net.SendToServer()
        end
    end)
end)

-- АНИМАЦИЯ
local anim = { hp = 100, armor = 0, bal = 0, bank = 0, ammo1 = 0, ammo2 = 0 }
local actual = { hp = 100, maxHp = 100, armor = 0, bal = 0, bank = 0, ammo1 = 0, ammo2 = 0, alive = true }
local lastUpdate = 0

local function UpdateValues()
    local now = CurTime()
    if now - lastUpdate < 0.05 then return end
    lastUpdate = now
    local lp = LocalPlayer()
    if not IsValid(lp) then actual.alive = false; return end
    actual.alive = lp:Alive()
    actual.hp = lp:Health()
    actual.maxHp = math.max(lp:GetMaxHealth(), 1)
    actual.armor = lp:Armor()
    actual.bal = GRM.PlayerBalance or 0
    actual.bank = GRM.PlayerBank or 0
    local wep = lp:GetActiveWeapon()
    if IsValid(wep) then
        actual.ammo1 = wep:Clip1() or 0
        actual.ammo2 = lp:GetAmmoCount(wep:GetPrimaryAmmoType()) or 0
    else
        actual.ammo1 = -1
        actual.ammo2 = 0
    end
end

local function AnimateValues()
    local spd = GRM.HUD.Config.animSpeed * FrameTime()
    anim.hp    = Lerp(spd, anim.hp, actual.hp)
    anim.armor = Lerp(spd, anim.armor, actual.armor)
    anim.bal   = Lerp(spd * 0.5, anim.bal, actual.bal)
    anim.bank  = Lerp(spd * 0.5, anim.bank, actual.bank)
    anim.ammo1 = Lerp(spd * 2, anim.ammo1, actual.ammo1)
    anim.ammo2 = Lerp(spd * 2, anim.ammo2, actual.ammo2)
end

-- СЕЛЕКТОР ОРУЖИЯ
local MAXSLOT = 10 -- GMod: реальные интерфейсы доходят до 10-го слота
local selector = { active = false, slot = 1, pos = 1, lastInput = 0, alpha = 0, weapons = {}, lastRefresh = 0, maxSlot = 0, seen = 0 }

--[[ Звуки селектора оружия — стоковые HL2, ровно те же, что играет ванильный
     выбор оружия. Раньше наш селектор листался молча: визуально работает, а
     на слух — «мёртвый». Проигрываем через GRM.Sound (там прекэш и защита
     от отсутствующего файла), с фолбэком на surface.PlaySound. ]]
local SELECTOR_SND = {
    open   = "common/wpn_hudon.wav",
    close  = "common/wpn_hudoff.wav",
    move   = "common/wpn_moveselect.wav",
    pick   = "common/wpn_select.wav",
    deny   = "common/wpn_denyselect.wav",
}

local function selectorSound(kind, throttle)
    local path = SELECTOR_SND[kind]
    if not path then return end
    if GRM.Sound and GRM.Sound.UI then
        GRM.Sound.UI(path, throttle or 0.02)
    elseif surface and surface.PlaySound then
        surface.PlaySound(path)
    end
end
GRM.HUD.SelectorSound = selectorSound

local function RefreshWeapons()
    local now = CurTime()
    if now - selector.lastRefresh < 0.2 then return end
    selector.lastRefresh = now
    local lp = LocalPlayer()
    if not IsValid(lp) then return end
    selector.weapons = {}
    selector.maxSlot = 0
    for _, wep in ipairs(lp:GetWeapons()) do
        if IsValid(wep) then
            -- slot -1 / хвосты за 6-кой (дробные BaseSlot у TFA-подобных):
            -- не выбрасываем, а зажимаем в 1..10, иначе оружие исчезало
            -- из листания совсем
            local s = math.Clamp((tonumber(wep:GetSlot()) or 0) + 1, 1, MAXSLOT)
            local p = (tonumber(wep:GetSlotPos()) or 0) + 1
            if not selector.weapons[s] then selector.weapons[s] = {} end
            table.insert(selector.weapons[s], { weapon = wep, name = wep:GetPrintName() or wep:GetClass(), slotPos = p })
            if s > selector.maxSlot then selector.maxSlot = s end
        end
    end
    for s, weps in pairs(selector.weapons) do table.sort(weps, function(a, b) return a.slotPos < b.slotPos end) end
end

-- Мгновенный выбор «по тику»: подсветка = и есть смена оружия (ваниль).
local function PickCurrent()
    local slotWeps = selector.weapons[selector.slot]
    local wep = slotWeps and slotWeps[selector.pos] and slotWeps[selector.pos].weapon
    if IsValid(wep) then input.SelectWeapon(wep) end
end

local function CloseSelector(silent)
    if selector.active and not silent then selectorSound("close") end
    selector.active = false
end

local function FindCurrentWeapon()
    local lp = LocalPlayer()
    if not IsValid(lp) then return end
    local activeWep = lp:GetActiveWeapon()
    if IsValid(activeWep) then
        local curSlot = math.Clamp((tonumber(activeWep:GetSlot()) or 0) + 1, 1, MAXSLOT)
        selector.slot = curSlot
        local slotWeps = selector.weapons[curSlot]
        if slotWeps then
            for i, w in ipairs(slotWeps) do
                if w.weapon == activeWep then selector.pos = i; return end
            end
        end
        selector.pos = 1
    else
        selector.slot = 1; selector.pos = 1
    end
end

local function NextWeapon()
    local slotWeps = selector.weapons[selector.slot]
    if slotWeps and #slotWeps > 0 then
        selector.pos = selector.pos + 1
        if selector.pos > #slotWeps then
            for offset = 1, MAXSLOT do
                local nextSlot = ((selector.slot - 1 + offset) % MAXSLOT) + 1
                if selector.weapons[nextSlot] and #selector.weapons[nextSlot] > 0 then
                    selector.slot = nextSlot; selector.pos = 1; return
                end
            end
        end
    else
        for offset = 1, MAXSLOT do
            local nextSlot = ((selector.slot - 1 + offset) % MAXSLOT) + 1
            if selector.weapons[nextSlot] and #selector.weapons[nextSlot] > 0 then
                selector.slot = nextSlot; selector.pos = 1; return
            end
        end
    end
end

local function PrevWeapon()
    local slotWeps = selector.weapons[selector.slot]
    if slotWeps and #slotWeps > 0 then
        selector.pos = selector.pos - 1
        if selector.pos < 1 then
            for offset = 1, MAXSLOT do
                local prevSlot = ((selector.slot - 1 - offset) % MAXSLOT) + 1
                if selector.weapons[prevSlot] and #selector.weapons[prevSlot] > 0 then
                    selector.slot = prevSlot; selector.pos = #selector.weapons[prevSlot]; return
                end
            end
        end
    else
        for offset = 1, MAXSLOT do
            local prevSlot = ((selector.slot - 1 - offset) % MAXSLOT) + 1
            if selector.weapons[prevSlot] and #selector.weapons[prevSlot] > 0 then
                selector.slot = prevSlot; selector.pos = #selector.weapons[prevSlot]; return
            end
        end
    end
end

local function GRM_HUD_MobileOpen()
    local MB = GRM and GRM.Mobile
    if not MB then return false end
    if MB.ClientBlocksInput and MB.ClientBlocksInput() then return true end
    return MB.ClientIsOpen and MB.ClientIsOpen() == true
end

-- Физган/гравиган: ЛКМ = луч/захват, E+мышь = вращение, колесо = дистанция.
-- Селектор не должен в это время ни открываться, ни автовыбирать оружие.
local BUILD_WEP = {
    weapon_physgun = true,
    weapon_physcannon = true,
}

function GRM.HUD.IsBuildWeapon(ply)
    if not IsValid(ply) then return false end
    local wep = ply.GetActiveWeapon and ply:GetActiveWeapon()
    if not IsValid(wep) then return false end
    local cls = wep.GetClass and wep:GetClass() or ""
    return BUILD_WEP[cls] == true
end

function GRM.HUD.IsPropToolBusy(ply)
    if not GRM.HUD.IsBuildWeapon(ply) then return false end
    if not ply.KeyDown then return false end
    return ply:KeyDown(IN_ATTACK) == true
end

local function AbortSelectorQuiet()
    selector.active = false
    selector.alpha = 0
end

-- Кольцевой лог решений селектора (для grm_sel_diag): «колесо жмёт, тишина»
-- различимо без дебаггера — бинды видны? глотаются? кем?
local SELLOG = {}
local function sellog(line)
    SELLOG[#SELLOG + 1] = string.format("%6.1f %s", CurTime(), line)
    if #SELLOG > 8 then table.remove(SELLOG, 1) end
end

hook.Add("PlayerBindPress", "GRM_HUD_Selector", function(ply, bind, pressed)
    if not pressed then return end
    selector.seen = selector.seen + 1 -- для grm_sel_diag: доходят ли бинды
    if not IsValid(ply) or not ply:Alive() then return end
    if GRM_HUD_MobileOpen() then
        bind = string.lower(tostring(bind or ""))
        selector.active = false
        selector.alpha = 0
        if bind == "invnext" then if GRM.Mobile.ClientWheel then GRM.Mobile.ClientWheel(1) end return true end
        if bind == "invprev" then if GRM.Mobile.ClientWheel then GRM.Mobile.ClientWheel(-1) end return true end
        if bind == "+attack3" or bind == "attack3" or bind == "mouse3" or bind == "+mouse3" then if GRM.Mobile.ClientSelect then GRM.Mobile.ClientSelect() end return true end
        if bind:match("^slot%d") or bind == "lastinv" or bind == "phys_swap" then return true end
        if bind == "+attack" or bind == "+attack2" or bind == "+reload" or bind == "+use" then return true end
        if bind == "+jump" or bind == "+duck" or bind == "+speed" or bind == "+walk" then return true end
        return true
    end
    local b = string.lower(tostring(bind or ""))
    -- Пока луч физгана/гравигана держит проп: глотаем смену оружия,
    -- бар не открываем, SelectWeapon не зовём. Дистанцию крутит сам
    -- физган по дельте колеса (не через invnext).
    if GRM.HUD.IsPropToolBusy(ply) then
        if b == "invnext" or b == "invprev" or b == "lastinv" or b == "phys_swap"
            or string.match(b, "^slot%d+$") then
            AbortSelectorQuiet()
            return true
        end
        if b == "+attack" or b == "+attack2" then
            AbortSelectorQuiet()
            return
        end
    end
    if bind == "invnext" then
        RefreshWeapons()
        if not selector.active then selector.active = true selectorSound("open", 0.05) FindCurrentWeapon() end
        local was = selector.slot .. ":" .. selector.pos
        NextWeapon()
        -- Щелчок только когда выбор реально сдвинулся (одно оружие в руках —
        -- звука нет, как в ванильном селекторе). Движение = и есть выбор.
        if was ~= (selector.slot .. ":" .. selector.pos) then
            selectorSound("move")
            PickCurrent()
            selector.lastInput = CurTime()
            return true
        end
        -- Сдвинуться нечем: НЕ глотаем — пусть листает движок (его обход
        -- видит все слоты мира). Вечер-9 урок: return true при нулевом ходе
        -- и был «невозможно листать».
        sellog("invnext: ход нулевой → пас движку")
        selector.lastInput = CurTime()
        return
    elseif bind == "invprev" then
        RefreshWeapons()
        if not selector.active then selector.active = true selectorSound("open", 0.05) FindCurrentWeapon() end
        local was = selector.slot .. ":" .. selector.pos
        PrevWeapon()
        if was ~= (selector.slot .. ":" .. selector.pos) then
            selectorSound("move")
            PickCurrent()
            selector.lastInput = CurTime()
            return true
        end
        sellog("invprev: ход нулевой → пас движку")
        selector.lastInput = CurTime()
        return
    end
    for i = 1, MAXSLOT do
        if bind == "slot" .. i then
            RefreshWeapons()
            local slotWeps = selector.weapons[i]
            local has = slotWeps and #slotWeps > 0
            if selector.active and selector.slot == i then
                if has then selector.pos = (selector.pos % #slotWeps) + 1 end
                selectorSound(has and "move" or "deny")
            else
                if not selector.active then selectorSound("open", 0.05) end
                selector.active = true selector.slot = i selector.pos = 1
                selectorSound(has and "move" or "deny")
            end
            if has then PickCurrent() end
            selector.lastInput = CurTime()
            return true
        end
    end
    -- ЛКМ больше не «подтверждает» (выбор случился тиком): только закрывает
    -- бар. Обе формы бинда — конфиги вида `bind mouse1 attack` реальны.
    if (bind == "+attack" or bind == "attack") and selector.active then CloseSelector(); return true end
    if (bind == "+attack2" or bind == "attack2") and selector.active then CloseSelector(); return true end
end)

-- Самодиагностика (вечер-10, по образцу /chatdiag): «селектор не работает»
-- перестаёт быть слепым пятном. В консоли: версия, живой ли хук, сколько
-- биндов дошло, что с ними стало, инвентарь по слотам.
if concommand and concommand.Add then
    concommand.Add("grm_sel_diag", function()
        local lp = LocalPlayer()
        local wep = IsValid(lp) and lp:GetActiveWeapon()
        print(string.format("[GRM sel] v10.6 (вечер-10) bind seen=%d, active=%s, выбор=%d:%d",
            selector.seen, tostring(selector.active), selector.slot, selector.pos))
        print(string.format("[GRM sel] в руке: %s (slot=%s) · mobile=%s · propbusy=%s",
            IsValid(wep) and tostring(wep:GetClass()) or "—",
            IsValid(wep) and tostring(wep:GetSlot()) or "—",
            tostring(GRM_HUD_MobileOpen()), tostring(GRM.HUD.IsPropToolBusy(lp))))
        for s = 1, MAXSLOT do
            local list = selector.weapons[s]
            if list and #list > 0 then print("[GRM sel] слот " .. s .. ": " .. #list .. " шт") end
        end
        for i = 1, #SELLOG do print("[GRM sel] " .. SELLOG[i]) end
        if selector.seen == 0 then
            print("[GRM sel] ВЫВОД: к our хуку не приходило НИ ОДНОГО бинда —")
            print("[GRM sel] проверьте привязки «След. оружие»/«Пред. оружие» (мышь) в настройках.")
        end
    end)
end

local hideElements = {
    ["CHudHealth"]          = true,
    ["CHudBattery"]         = true,
    ["CHudAmmo"]            = true,
    ["CHudSecondaryAmmo"]   = true,
    ["CHudWeaponSelection"] = true,
}
hook.Add("HUDShouldDraw", "GRM_HUD_Hide", function(name)
    if hideElements[name] then return false end
end)

-- ОТРИСОВКА
local function DrawMainHUD()
    -- При активных чипах аугментаций обычный HUD не рисуется: его место
    -- занимает био-интерфейс (BIOMETRICS/ФИНАНСОВЫЙ КАНАЛ в cl_grm_augmentations_hud.lua)
    if GRM.AugHUD and GRM.AugHUD.IsActive and GRM.AugHUD.IsActive() then return end
    UpdateValues()
    AnimateValues()
    if not actual.alive then return end

    local cfg = GRM.HUD.Config
    local sh, sw = ScrH(), ScrW()

    --[[ Собираем ВСЁ, что нужно показать, в один список: сначала здоровье и
         броня (они всегда), затем полосы, которые объявили другие модули
         (выносливость, дыхание, сытость, вес). Панель считает свою высоту
         под фактическое число полос — ничего не налезает и не висит в
         пустоте. ]]
    local rows = {}

    local hpFrac = math.Clamp(anim.hp / actual.maxHp, 0, 1)
    local hpColor
    if hpFrac > 0.6 then hpColor = cfg.hpColorFull
    elseif hpFrac > 0.3 then
        local t = (hpFrac - 0.3) / 0.3
        hpColor = Color(Lerp(t, cfg.hpColorMid.r, cfg.hpColorFull.r), Lerp(t, cfg.hpColorMid.g, cfg.hpColorFull.g), Lerp(t, cfg.hpColorMid.b, cfg.hpColorFull.b), 255)
    else
        local t = hpFrac / 0.3
        hpColor = Color(Lerp(t, cfg.hpColorLow.r, cfg.hpColorMid.r), Lerp(t, cfg.hpColorLow.g, cfg.hpColorMid.g), Lerp(t, cfg.hpColorLow.b, cfg.hpColorMid.b), 255)
    end
    rows[#rows + 1] = { label = "ЗДОРОВЬЕ", frac = hpFrac, color = hpColor,
        text = math.Round(anim.hp) .. " / " .. actual.maxHp }

    -- Броня показывается всегда (даже 0), чтобы игрок видел полосу,
    -- которую надо пополнять — она не «пропадает» из HUD.
    rows[#rows + 1] = { label = "БРОНЯ", frac = math.Clamp(anim.armor / 100, 0, 1),
        color = cfg.armorColor, text = tostring(math.Round(anim.armor)) }

    for _, def in ipairs(GRM.HUD.BarList()) do
        local ok, value, max, text, color, hidden = pcall(def.Get)
        if ok and not hidden and value ~= nil then
            max = math.max(1, tonumber(max) or 100)
            rows[#rows + 1] = {
                label = def.label,
                frac = math.Clamp((tonumber(value) or 0) / max, 0, 1),
                color = color or cfg.armorColor,
                text = text or (math.Round(tonumber(value) or 0) .. " / " .. math.Round(max)),
            }
        end
    end

    local lp = LocalPlayer()
    local rpName = IsValid(lp) and lp:GetNWString("GRM_RPName", "") or ""
    if rpName == "" and IsValid(lp) then rpName = lp:Nick() end
    local facKey = IsValid(lp) and lp:GetNWString("GRM_Faction", "") or ""
    local facName = "Гражданский"
    if facKey ~= "" then
        facName = (GRM.Factions and GRM.Factions.DisplayName and GRM.Factions.DisplayName(facKey)) or facKey
    end
    local roleName = IsValid(lp) and lp:GetNWString("GRM_Role", "") or ""
    if roleName ~= "" then
        if GRM.Factions and GRM.Factions.RoleDisplayName and Factions and Factions[facKey] then
            roleName = GRM.Factions.RoleDisplayName(Factions[facKey], roleName) or roleName
        end
        facName = facName .. " · " .. roleName
    end

    local cashTxt = (GRM.Format and GRM.Format(math.Round(anim.bal))) or ("$" .. string.Comma(math.Round(anim.bal)))
    local bankTxt = (GRM.PlayerBank ~= nil)
        and ((GRM.Format and GRM.Format(math.Round(anim.bank))) or ("$" .. string.Comma(math.Round(anim.bank))))
        or "—"

    local hx, hy, hw, hh = 16, 16, 356, 72
    draw.RoundedBox(8, hx, hy, hw, hh, Color(8, 14, 23, 150))
    surface.SetDrawColor(cfg.lineColor.r, cfg.lineColor.g, cfg.lineColor.b, 85)
    surface.DrawOutlinedRect(hx, hy, hw, hh, 1)

    if IsValid(lp) then
        pcall(function()
            if not IsValid(GRM.HUD._avatar) then
                local av = vgui.Create("AvatarImage")
                av:SetSize(44, 44)
                av:SetPaintedManually(true)
                av:SetMouseInputEnabled(false)
                av:SetKeyboardInputEnabled(false)
                GRM.HUD._avatar = av
            end
            if GRM.HUD._avatarPly ~= lp then
                GRM.HUD._avatar:SetPlayer(lp, 64)
                GRM.HUD._avatarPly = lp
            end
            GRM.HUD._avatar:SetPos(hx + 10, hy + 10)
            GRM.HUD._avatar:SetSize(44, 44)
            GRM.HUD._avatar:PaintManual()
        end)
    end
    draw.SimpleText(rpName, "GRM_HUD_Name", hx + 64, hy + 12, cfg.textColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    draw.SimpleText(facName, "GRM_HUD_Meta", hx + 64, hy + 34, cfg.labelColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

    -- ID игрока (CharacterKey)
    local cid = IsValid(lp) and (lp:GetNWString("GRM_CharacterKey", "") or "") or ""
    if cid == "" then cid = IsValid(lp) and (lp:SteamID64() or "") or "" end
    draw.SimpleText("ID: " .. tostring(cid), "GRM_HUD_Label", hx + 64, hy + 50,
        cfg.labelColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

    -- Реальное время: отдельная плашка в правом верхнем углу.
    -- Источник общий с таблистой (GRM.Time) — секунды/минуты совпадают.
    do
        local clock, date
        if GRM and GRM.Time and GRM.Time.Clock then
            clock = GRM.Time.Clock("%H:%M:%S")
            date  = GRM.Time.Clock("%d.%m.%Y")
        else
            local rt = os.date("*t")
            clock = string.format("%02d:%02d:%02d", rt.hour, rt.min, rt.sec)
            date  = string.format("%02d.%02d.%d", rt.day, rt.month, rt.year)
        end
        surface.SetFont("GRM_HUD_TimeBig")
        local tw = surface.GetTextSize(clock)
        local bx, by, bw, bh = sw - 16 - (tw + 28), 16, tw + 28, 64
        draw.RoundedBox(8, bx, by, bw, bh, Color(8, 14, 23, 170))
        surface.SetDrawColor(cfg.lineColor.r, cfg.lineColor.g, cfg.lineColor.b, 95)
        surface.DrawOutlinedRect(bx, by, bw, bh, 1)
        draw.SimpleText(clock, "GRM_HUD_TimeBig", bx + bw / 2, by + 17, Color(240, 200, 90), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(date, "GRM_HUD_TimeDate", bx + bw / 2, by + 47, Color(210, 190, 150), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    local pw = 320
    local pad, rowH, gap = 10, 24, 4
    local headerH = 24
    local moneyH = 40 -- кассеты финансов (нижняя строка панели, sim_hud_bars)
    local ph = headerH + pad + #rows * (rowH + gap) + moneyH + pad - gap
    ph = math.min(ph, sh - 48)
    local px, py = 16, math.max(16, sh - 28 - ph)

    GRM.HUD.StatusRect = { x = px, y = py, w = pw, h = ph }

    draw.RoundedBox(8, px + 2, py + 2, pw, ph, cfg.bgShadow)
    draw.RoundedBox(8, px, py, pw, ph, cfg.bgColor)
    surface.SetDrawColor(cfg.lineColor.r, cfg.lineColor.g, cfg.lineColor.b, 90)
    surface.DrawOutlinedRect(px, py, pw, ph, 1)
    draw.RoundedBoxEx(8, px, py, pw, headerH, cfg.panelHeader, true, true, false, false)
    draw.RoundedBox(0, px, py, 3, headerH, cfg.hpColorFull)
    draw.SimpleText("СОСТОЯНИЕ", "GRM_HUD_Value", px + 12, py + headerH / 2, cfg.textColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

    local x, w = px + pad, pw - pad * 2
    local y = py + headerH + pad
    for _, row in ipairs(rows) do
        local fillW = math.max(0, (w - 3) * row.frac)
        draw.RoundedBox(4, x, y, w, rowH, Color(17, 29, 45, 120))
        if fillW > 0 then
            draw.RoundedBox(4, x + 3, y + 3, math.max(2, fillW), rowH - 6,
                Color(row.color.r, row.color.g, row.color.b, 150))
        end
        draw.RoundedBox(2, x, y, 3, rowH, row.color)
        draw.SimpleText(row.label, "GRM_HUD_Label", x + 10, y + rowH / 2, cfg.textColor,
            TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(row.text, "GRM_HUD_Value", x + w - 8, y + rowH / 2, cfg.textColor,
            TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        y = y + rowH + gap
    end

    -- Вечер-11: финансы — две нижние кассеты «СОСТОЯНИЯ». Наличку видно
    -- даже с зажатой «мышкой» в руках: панель снизу перекрыть нечем.
    y = y - gap
    local cellW = math.floor((w - gap) / 2)
    for i, cell in ipairs({
        { label = "НАЛИЧНЫЕ", value = cashTxt, color = cfg.moneyColor },
        { label = "СЧЁТ", value = bankTxt, color = cfg.bankColor or cfg.moneyColor },
    }) do
        local cx = x + (i - 1) * (cellW + gap)
        draw.RoundedBox(4, cx, y, cellW, moneyH - 6, Color(17, 29, 45, 150))
        draw.RoundedBox(2, cx, y, 3, moneyH - 6, cell.color)
        draw.SimpleText(cell.label, "GRM_HUD_Label", cx + 10, y + (moneyH - 6) / 2 - 7,
            cfg.labelColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(cell.value, "GRM_HUD_Money", cx + cellW - 10, y + (moneyH - 6) / 2 + 7,
            cell.color, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    -- ── патроны: отдельный блок справа снизу ────────────────────────
    if actual.ammo1 >= 0 then
        local ax, ay = sw - 16 - 160, sh - 16 - 64
        local aw, ah = 160, 58
        draw.RoundedBox(8, ax + 2, ay + 2, aw, ah, cfg.bgShadow)
        draw.RoundedBox(8, ax, ay, aw, ah, cfg.bgColor)
        surface.SetDrawColor(cfg.lineColor.r, cfg.lineColor.g, cfg.lineColor.b, math.floor(cfg.lineColor.a or 255))
        surface.DrawOutlinedRect(ax, ay, aw, ah)
        draw.SimpleText("ПАТРОНЫ", "GRM_HUD_Label", ax + aw - 10, ay + 6, cfg.labelColor, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
        local ammoStr = tostring(math.Round(anim.ammo1))
        draw.SimpleText(ammoStr, "GRM_HUD_Ammo", ax + 12, ay + ah / 2 + 4, cfg.ammoColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        surface.SetFont("GRM_HUD_Ammo")
        local ammoW = surface.GetTextSize(ammoStr)
        draw.SimpleText(" / " .. math.Round(anim.ammo2), "GRM_HUD_Ammo2", ax + 14 + ammoW, ay + ah / 2 + 6, cfg.ammo2Color, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
end

local function DrawWeaponSelector()
    if GRM_HUD_MobileOpen and GRM_HUD_MobileOpen() then selector.active = false; selector.alpha = 0; return end
    local lpBusy = LocalPlayer()
    -- Захват физганом: бар гасим сразу, таймаут НЕ вызывает SelectWeapon
    if GRM.HUD.IsPropToolBusy(lpBusy) then
        AbortSelectorQuiet()
        return
    end
    local cfg = GRM.HUD.Config
    -- Таймаут только закрывает интерфейс. Подсвеченное оружие никогда не
    -- выбирается без явного подтверждения ЛКМ.
    if selector.active and CurTime() - selector.lastInput > cfg.selectorTimeout then CloseSelector() end
    local targetAlpha = selector.active and 255 or 0
    selector.alpha = math.Approach(selector.alpha, targetAlpha, FrameTime() * 900)
    if selector.alpha < 1 then return end
    local sw = ScrW()
    local alpha = selector.alpha / 255
    RefreshWeapons()
    -- вечер-10: бар по фактической геометрии инвентаря (до 10 слотов),
    -- пустые хвосты не раздуваем, привычная сетка — минимум 6.
    local totalSlots = math.Clamp(selector.maxSlot or 6, 6, MAXSLOT)
    local slotW, slotH, slotGap, headerH, padding = (totalSlots > 6 and 150 or 170), 30, 5, 26, 6
    local totalW = totalSlots * (slotW + slotGap) - slotGap
    if totalW > sw - 40 then
        slotW = math.floor((sw - 40 - totalSlots * slotGap) / totalSlots)
        totalW = totalSlots * (slotW + slotGap) - slotGap
    end
    local startX, startY = (sw - totalW) / 2, 20
    for slot = 1, totalSlots do
        local sx = startX + (slot - 1) * (slotW + slotGap)
        local slotWeps = selector.weapons[slot] or {}
        local numWeps = #slotWeps
        local colH = headerH + math.max(numWeps, 1) * (slotH + 2) + padding
        local isActiveSlot = (selector.slot == slot)
        local bgA = isActiveSlot and (210 * alpha) or (170 * alpha)
        draw.RoundedBox(6, sx, startY, slotW, colH, Color(cfg.slotBg.r, cfg.slotBg.g, cfg.slotBg.b, bgA))
        if isActiveSlot then
            surface.SetDrawColor(cfg.slotActive.r, cfg.slotActive.g, cfg.slotActive.b, 200 * alpha)
            surface.DrawOutlinedRect(sx, startY, slotW, colH, 2)
        else
            surface.SetDrawColor(cfg.slotBorder.r, cfg.slotBorder.g, cfg.slotBorder.b, 100 * alpha)
            surface.DrawOutlinedRect(sx, startY, slotW, colH, 1)
        end
        draw.SimpleText(tostring(slot), "GRM_SlotKey", sx + 8, startY + 5, Color(cfg.slotKeyColor.r, cfg.slotKeyColor.g, cfg.slotKeyColor.b, 255 * alpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText("СЛОТ " .. slot, "GRM_HUD_Label", sx + 22, startY + 6, Color(cfg.labelColor.r, cfg.labelColor.g, cfg.labelColor.b, 200 * alpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        if numWeps > 0 then
            for i, wepData in ipairs(slotWeps) do
                local wy = startY + headerH + (i - 1) * (slotH + 2)
                local isSelected = isActiveSlot and (selector.pos == i)
                if isSelected then
                    draw.RoundedBox(4, sx + 3, wy, slotW - 6, slotH, Color(cfg.slotActive.r, cfg.slotActive.g, cfg.slotActive.b, 70 * alpha))
                    surface.SetDrawColor(cfg.slotActive.r, cfg.slotActive.g, cfg.slotActive.b, 255 * alpha)
                    surface.DrawRect(sx + 3, wy + 5, 3, slotH - 10)
                end
                local lp = LocalPlayer()
                local activeWep = IsValid(lp) and lp:GetActiveWeapon()
                local isEquipped = IsValid(activeWep) and activeWep == wepData.weapon
                local nameFont = isSelected and "GRM_SlotNameActive" or "GRM_SlotName"
                local nameColor
                if isEquipped then nameColor = Color(cfg.hpColorFull.r, cfg.hpColorFull.g, cfg.hpColorFull.b, 255 * alpha)
                elseif isSelected then nameColor = Color(255, 255, 255, 255 * alpha)
                else nameColor = Color(cfg.slotText.r, cfg.slotText.g, cfg.slotText.b, 200 * alpha) end
                local displayName = wepData.name
                if #displayName > 20 then displayName = string.sub(displayName, 1, 18) .. ".." end
                draw.SimpleText(displayName, nameFont, sx + 14, wy + slotH / 2, nameColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                if isEquipped then
                    draw.SimpleText("●", "GRM_SlotKey", sx + slotW - 12, wy + slotH / 2, Color(cfg.hpColorFull.r, cfg.hpColorFull.g, cfg.hpColorFull.b, 200 * alpha), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
                end
            end
        else
            draw.SimpleText("— пусто —", "GRM_SlotName", sx + slotW / 2, startY + headerH + 10, Color(70, 70, 80, 140 * alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        end
    end

    if selector.active then
        local hintX = startX + totalW + 16
        local hintY = startY + 4
        local hints = {{"ЛКМ","Выбрать"},{"ПКМ","Отмена"},{"Колесо","Листать"},{"1-10","Слот"}}
        for i, hint in ipairs(hints) do
            local hy = hintY + (i - 1) * 18
            draw.SimpleText(hint[1], "GRM_SlotKey", hintX, hy, Color(cfg.slotKeyColor.r, cfg.slotKeyColor.g, cfg.slotKeyColor.b, 180 * alpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText(hint[2], "GRM_HUD_Label", hintX + 48, hy + 1, Color(cfg.labelColor.r, cfg.labelColor.g, cfg.labelColor.b, 160 * alpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end
    end
end

local function DrawNotifications()
    local sw, sh = ScrW(), ScrH()
    local nx, baseY = sw - 20, sh - 130
    for i = #GRM.Notifications, 1, -1 do
        local n = GRM.Notifications[i]
        local elapsed = CurTime() - n.time
        if elapsed > n.duration then table.remove(GRM.Notifications, i)
        else
            local tA, tY = 255, 0
            if elapsed < 0.35 then tA = (elapsed / 0.35) * 255; tY = (1 - elapsed / 0.35) * 10
            elseif elapsed > n.duration - 0.6 then tA = ((n.duration - elapsed) / 0.6) * 255 end
            n.alpha = math.Approach(n.alpha or 0, tA, FrameTime() * 700)
            n.yOff = math.Approach(n.yOff or 0, tY, FrameTime() * 500)
            local idx = #GRM.Notifications - i
            local y = baseY - idx * 26 - n.yOff
            surface.SetFont("GRM_Notify")
            local tw = surface.GetTextSize(n.text)
            draw.RoundedBox(4, nx - tw - 22, y - 10, tw + 16, 22, Color(12, 14, 20, n.alpha * 0.75))
            draw.SimpleText(n.text, "GRM_Notify", nx - 8, y, Color(n.color.r, n.color.g, n.color.b, n.alpha), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
    end
end

hook.Add("HUDPaint", "GRM_HUD_Main", function()
    local ok, err = pcall(DrawMainHUD)
    if not ok and (GRM.HUD._lastErr or "") ~= tostring(err) then
        GRM.HUD._lastErr = tostring(err)
        ErrorNoHalt("[GRM HUD] " .. tostring(err) .. "\n")
    end
    pcall(DrawWeaponSelector)
    pcall(DrawNotifications)
end)

grmBootStart("GRM_HUD_Welcome", "late", function()
    timer.Simple(4, function()
        if IsValid(LocalPlayer()) then GRM.AddNotification("HUD v10.5 — шапка и деньги слева сверху", 5, Color(100, 180, 255)) end
    end)
end)

print("[GRM] HUD v10.8 загружен")
