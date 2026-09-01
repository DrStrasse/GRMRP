--[[--------------------------------------------------------------------
    GRM Mining v2.0.0 — шахта: руда, добыча, инструмент, скупка

    Заказ владельца (19.08): «давно не фиксили код скупщика руды, надо всё
    что касается торгашей и шахты mine исправить, пофиксить, доработать,
    особенно дизайн GRM окон + получение и сдача инструмента
    weapon_jackhammer_sd, которым добывается руда».

    ЧТО БЫЛО НЕ ТАК
      • цены на руду жили только в памяти: рестарт — и всё сбрасывалось
        на дефолт, а «!setoreprice» приходилось вбивать заново;
      • продажа доверяла клиенту тип руды, но не проверяла дистанцию до
        скупщика — продать можно было с другого конца карты;
      • бур выдавался через ply:Give без единой проверки: если аддона с
        weapon_jackhammer_sd на сервере нет, кнопка «молчала», а игрок мог
        набрать сколько угодно буров и уносить их с собой;
      • добыча слала net-пакет прогресса на КАЖДЫЙ удар без троттлинга и
        печатала отладку в консоль сервера при каждом ударе киркой;
      • окна скупщика были на голом Derma.

    ЧТО СТАЛО
      • GRM.Mining — единый слой: типы руды, цены (с файлом
        data/grm_mining/prices.json), конфиг, выдача/сдача инструмента;
      • продажа считается на сервере, с проверкой дистанции до скупщика,
        поштучно или «всё разом», с аудитом;
      • инструмент выдаётся под ЗАЛОГ (конвар), строго один на руки,
        снимается при смерти/выходе, залог возвращается при сдаче;
      • прогресс добычи троттлится и рисуется в стиле GRM;
      • отладочная печать убрана (осталась под grm_mining_debug 1).

    Команды: /mine_prices, /mine_price <руда> <цена> (админ),
             grm_mining_prices, grm_mining_price, grm_mining_tool_return.
    Конвары: grm_mining_deposit, grm_mining_debug.
----------------------------------------------------------------------]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Mining = GRM.Mining or {}
local M = GRM.Mining
M.Version = "2.0.0"

-- Типы руды: порядок важен для интерфейса скупщика.
M.OreOrder = { "copper", "aluminum", "gold", "platinum" }
M.Ores = {
    copper   = { name = "Медная руда",       color = Color(200, 120, 50),  default = 50 },
    aluminum = { name = "Алюминиевая руда",  color = Color(200, 200, 210), default = 75 },
    gold     = { name = "Золотая руда",      color = Color(255, 215, 0),   default = 100 },
    platinum = { name = "Платиновая руда",   color = Color(120, 180, 255), default = 150 },
}

-- Инструмент добычи. Первый найденный на сервере класс и будет выдаваться:
-- в сборке может стоять любой из вариантов SD-джекхаммера.
M.ToolClasses = { "weapon_jackhammer_sd", "weapon_jackhammer", "jackhammer_sd" }

M.Config = {
    UseDistance   = 260,   -- дальность работы со скупщиком
    ProgressRate  = 0.2,   -- как часто слать прогресс добычи (сек)
    ChunkPickup   = 96,    -- радиус подбора соседних кусков одним нажатием
}

function M.OreName(ore) local o = M.Ores[tostring(ore or "")] return o and o.name or tostring(ore or "") end
function M.OreColor(ore) local o = M.Ores[tostring(ore or "")] return o and o.color or Color(220, 220, 220) end
function M.IsOre(ore) return M.Ores[tostring(ore or "")] ~= nil end
function M.ItemID(ore) return "ore_" .. tostring(ore or "") end

--- Класс инструмента, который реально зарегистрирован на сервере.
function M.ToolClass()
    for _, class in ipairs(M.ToolClasses) do
        if weapons and weapons.GetStored and weapons.GetStored(class) then return class end
    end
    -- Ничего не нашли — отдаём канонический класс, вызывающий покажет причину.
    return M.ToolClasses[1], false
end

function M.IsMiningTool(class)
    class = string.lower(tostring(class or ""))
    if class == "" then return false end
    for _, c in ipairs(M.ToolClasses) do if class == string.lower(c) then return true end end
    return string.find(class, "jackhammer", 1, true) ~= nil
end

-----------------------------------------------------------------------
-- СЕРВЕР
-----------------------------------------------------------------------
if SERVER then
    util.AddNetworkString("grm_ore_progress")
    util.AddNetworkString("grm_ore_buyer_open")
    util.AddNetworkString("grm_ore_sell")
    util.AddNetworkString("grm_ore_buyer_give_jackhammer")
    util.AddNetworkString("grm_ore_buyer_return_jackhammer")

    local DEPOSIT = CreateConVar("grm_mining_deposit", "0", bit.bor(FCVAR_ARCHIVE),
        "Залог за бур: списывается при выдаче и возвращается при сдаче (0 — бесплатно)")
    local DEBUG = CreateConVar("grm_mining_debug", "0", bit.bor(FCVAR_ARCHIVE),
        "1 — печатать отладку шахты в консоль сервера")

    local DIR = "grm_mining"
    local PRICE_FILE = DIR .. "/prices.json"

    local function dbg(...) if DEBUG:GetBool() then print("[GRM Mining]", ...) end end
    local function notify(ply, msg, ok)
        if not IsValid(ply) then return end
        if GRM.Notify then GRM.Notify(ply, msg, ok == false and 255 or 100, ok == false and 130 or 220, ok == false and 100 or 130)
        else ply:ChatPrint("[Шахта] " .. tostring(msg)) end
    end
    local function audit(action, ply, target, details)
        if GRM.Audit and GRM.Audit.Write then GRM.Audit.Write("mining", action, ply, target or {}, details or {}) end
    end

    ------------------------------------------------------------------
    -- ЦЕНЫ (с файлом: раньше сбрасывались после каждого рестарта)
    ------------------------------------------------------------------
    local function defaults()
        local out = {}
        for ore, def in pairs(M.Ores) do out[ore] = def.default end
        return out
    end

    function M.SavePrices(why)
        if not file.IsDir(DIR, "DATA") then file.CreateDir(DIR) end
        local ok, raw = pcall(util.TableToJSON, { version = 1, prices = GRM.OrePrices }, true)
        if not ok or not isstring(raw) then return false end
        file.Write(PRICE_FILE, raw)
        local back = file.Read(PRICE_FILE, "DATA")
        if not back or back == "" then
            print("[GRM Mining] SAVE read-back ПУСТ — проверьте права data/")
            return false
        end
        dbg("цены сохранены", tostring(why or "-"))
        return true
    end

    function M.LoadPrices()
        GRM.OrePrices = defaults()
        local raw = file.Read(PRICE_FILE, "DATA") or ""
        if raw ~= "" then
            local ok, data = pcall(util.JSONToTable, raw, false, true)
            local src = ok and istable(data) and (data.prices or data) or nil
            if istable(src) then
                for ore, price in pairs(src) do
                    if M.IsOre(ore) then GRM.OrePrices[ore] = math.max(0, math.floor(tonumber(price) or 0)) end
                end
            end
        end
        return GRM.OrePrices
    end

    function M.SetPrice(ore, price)
        ore = string.lower(tostring(ore or ""))
        if not M.IsOre(ore) then return false, "Неизвестный тип руды" end
        -- Отрицательную цену раньше «спасал» math.max(0, …) и молча ставил 0:
        -- админ думал, что ошибся в команде, а скупка тихо выключалась.
        local value = tonumber(price)
        if not value or value < 0 then return false, "Некорректная цена" end
        price = math.floor(value)
        GRM.OrePrices[ore] = price
        M.SavePrices("цена " .. ore)
        return true, ("Цена «%s»: %s"):format(M.OreName(ore), GRM.Format and GRM.Format(price) or price)
    end

    GRM.OrePrices = GRM.OrePrices or {}
    M.LoadPrices()

    ------------------------------------------------------------------
    -- ИНСТРУМЕНТ: ВЫДАЧА И СДАЧА
    ------------------------------------------------------------------
    local function hasTool(ply)
        for _, class in ipairs(M.ToolClasses) do
            if ply:HasWeapon(class) then return true, class end
        end
        return false
    end
    M.HasTool = hasTool

    function M.GiveTool(ply, buyer)
        if not IsValid(ply) then return false end
        if IsValid(buyer) and ply:GetPos():DistToSqr(buyer:GetPos()) > M.Config.UseDistance ^ 2 then
            return false, "Подойдите к скупщику ближе"
        end
        if hasTool(ply) then return false, "Бур уже у вас на руках" end

        local class, registered = M.ToolClass()
        if registered == false then
            return false, "Аддон бура не установлен на сервере (" .. class .. ") — сообщите администрации"
        end

        local deposit = math.max(0, DEPOSIT:GetInt())
        if deposit > 0 then
            if GRM.HasMoney and not GRM.HasMoney(ply, deposit) then
                return false, ("Нужен залог %s"):format(GRM.Format and GRM.Format(deposit) or deposit)
            end
            if GRM.TakeMoney then GRM.TakeMoney(ply, deposit, "Залог за бур") end
            ply.GRMMiningDeposit = deposit
        else
            ply.GRMMiningDeposit = 0
        end

        local wep = ply:Give(class)
        if not IsValid(wep) and not hasTool(ply) then
            -- Выдача не удалась — залог возвращаем сразу, а не «когда-нибудь».
            if (ply.GRMMiningDeposit or 0) > 0 and GRM.GiveMoney then
                GRM.GiveMoney(ply, ply.GRMMiningDeposit, "Возврат залога: бур не выдан")
            end
            ply.GRMMiningDeposit = nil
            return false, "Сервер не смог выдать бур"
        end

        ply:SelectWeapon(class)
        audit("tool.give", ply, { class = class }, { deposit = deposit })
        return true, deposit > 0
            and ("Бур выдан. Залог %s вернётся при сдаче."):format(GRM.Format and GRM.Format(deposit) or deposit)
            or "Бур выдан. Не забудьте сдать его после смены."
    end

    function M.ReturnTool(ply, silentNoTool)
        if not IsValid(ply) then return false end
        local has = hasTool(ply)
        if not has then
            if silentNoTool then return false end
            return false, "Бура на руках нет"
        end
        for _, class in ipairs(M.ToolClasses) do
            if ply:HasWeapon(class) then ply:StripWeapon(class) end
        end
        local deposit = math.max(0, tonumber(ply.GRMMiningDeposit) or 0)
        ply.GRMMiningDeposit = nil
        if deposit > 0 and GRM.GiveMoney then GRM.GiveMoney(ply, deposit, "Возврат залога за бур") end
        audit("tool.return", ply, {}, { deposit = deposit })
        return true, deposit > 0
            and ("Бур сдан, залог %s возвращён."):format(GRM.Format and GRM.Format(deposit) or deposit)
            or "Бур сдан."
    end

    -- Бур не должен уезжать с игроком в могилу и из сессии: иначе он копится.
    hook.Add("PlayerDeath", "GRM_Mining_ToolOnDeath", function(ply)
        if not IsValid(ply) then return end
        if not hasTool(ply) then return end
        for _, class in ipairs(M.ToolClasses) do
            if ply:HasWeapon(class) then ply:StripWeapon(class) end
        end
        notify(ply, "Бур потерян при смерти — получите новый у скупщика.", false)
    end)
    hook.Add("PlayerDisconnected", "GRM_Mining_ToolOnLeave", function(ply)
        if IsValid(ply) then ply.GRMMiningDeposit = nil end
    end)

    ------------------------------------------------------------------
    -- ПРОДАЖА
    ------------------------------------------------------------------
    -- Сколько руды у игрока по типам (по инвентарю, а не по словам клиента).
    function M.CountOres(ply)
        local out = {}
        local inv = GRM.Inventory and GRM.Inventory.GetPlayerInv and GRM.Inventory.GetPlayerInv(ply)
        if not (istable(inv) and istable(inv.slots)) then return out end
        for _, slot in pairs(inv.slots) do
            if istable(slot) and isstring(slot.id) then
                local ore = slot.id:match("^ore_(.+)$")
                if ore and M.IsOre(ore) then out[ore] = (out[ore] or 0) + (tonumber(slot.count) or 1) end
            end
        end
        return out
    end

    --- Продажа одного типа руды. ore = "all" продаёт всё сразу.
    function M.Sell(ply, ore, buyer)
        if not IsValid(ply) then return false end
        if IsValid(buyer) and ply:GetPos():DistToSqr(buyer:GetPos()) > M.Config.UseDistance ^ 2 then
            return false, "Подойдите к скупщику ближе"
        end
        if not (GRM.Inventory and GRM.Inventory.GetPlayerInv) then return false, "Инвентарь недоступен" end

        local wanted = {}
        if ore == "all" then
            for _, id in ipairs(M.OreOrder) do wanted[id] = true end
        elseif M.IsOre(ore) then
            wanted[ore] = true
        else
            return false, "Неизвестный тип руды"
        end

        local inv = GRM.Inventory.GetPlayerInv(ply)
        if not (istable(inv) and istable(inv.slots)) then return false, "Инвентарь недоступен" end

        local sold, earned, byOre = 0, 0, {}
        for idx, slot in pairs(inv.slots) do
            if istable(slot) and isstring(slot.id) then
                local kind = slot.id:match("^ore_(.+)$")
                local price = kind and wanted[kind] and math.max(0, math.floor(tonumber(GRM.OrePrices[kind]) or 0)) or 0
                if kind and wanted[kind] and price > 0 then
                    local count = tonumber(slot.count) or 1
                    if GRM.Inventory.RemoveFromSlot(ply, idx, count) then
                        sold = sold + count
                        earned = earned + count * price
                        byOre[kind] = (byOre[kind] or 0) + count
                    end
                end
            end
        end

        if sold <= 0 then return false, "Подходящей руды нет (или на неё не назначена цена)" end
        if GRM.GiveMoney then GRM.GiveMoney(ply, earned, "Продажа руды") end
        audit("ore.sell", ply, { buyer = IsValid(buyer) and buyer:EntIndex() or 0 }, { sold = sold, earned = earned, ores = byOre })
        hook.Run("GRM_QuestEvent", ply, "ore_sell", tostring(ore), sold, {})
        return true, ("Продано %d ед. руды на %s"):format(sold, GRM.Format and GRM.Format(earned) or earned)
    end

    ------------------------------------------------------------------
    -- ДОБЫЧА
    ------------------------------------------------------------------
    hook.Add("EntityTakeDamage", "GRM_OreNodeDamage", function(target, dmginfo)
        if not IsValid(target) or target:GetClass() ~= "grm_ore_node" then return end
        local attacker = dmginfo:GetAttacker()
        if not (IsValid(attacker) and attacker:IsPlayer()) then return end
        local wep = attacker:GetActiveWeapon()
        if not (IsValid(wep) and M.IsMiningTool(wep:GetClass())) then
            if (attacker.GRMMiningHint or 0) < CurTime() then
                attacker.GRMMiningHint = CurTime() + 6
                notify(attacker, "Руда добывается только буром — получите его у скупщика.", false)
            end
            return
        end
        if target.TakeDamageCustom then
            target:TakeDamageCustom(dmginfo:GetDamage(), attacker)
            dmginfo:SetDamage(0)
        end
    end)

    --- Прогресс добычи клиенту (с троттлингом — раньше пакет шёл на каждый удар).
    function M.PushProgress(ply, node, frac, force)
        if not (IsValid(ply) and IsValid(node)) then return end
        local now = CurTime()
        if not force and (ply.GRMMiningNextPush or 0) > now then return end
        ply.GRMMiningNextPush = now + M.Config.ProgressRate
        net.Start("grm_ore_progress")
            net.WriteEntity(node)
            net.WriteFloat(math.Clamp(tonumber(frac) or 0, 0, 1))
        net.Send(ply)
    end

    ------------------------------------------------------------------
    -- СЕТЬ
    ------------------------------------------------------------------
    local function guard(ply, key, bits)
        if GRM.Net and GRM.Net.Guard then
            return GRM.Net.Guard(ply, key, { rate = 0.3, burst = 3, maxBits = 512 }, { bits = bits }) == true
        end
        return IsValid(ply)
    end

    local function nearestBuyer(ply)
        local best, bestD = nil, M.Config.UseDistance ^ 2
        for _, e in ipairs(ents.FindByClass("grm_ore_buyer")) do
            if IsValid(e) then
                local d = ply:GetPos():DistToSqr(e:GetPos())
                if d < bestD then best, bestD = e, d end
            end
        end
        return best
    end
    M.NearestBuyer = nearestBuyer

    function M.PushBuyer(ply, buyer)
        if not IsValid(ply) then return end
        local rows = {}
        local counts = M.CountOres(ply)
        for _, ore in ipairs(M.OreOrder) do
            rows[#rows + 1] = {
                id = ore, name = M.OreName(ore),
                price = math.max(0, math.floor(tonumber(GRM.OrePrices[ore]) or 0)),
                count = counts[ore] or 0,
            }
        end
        local class, registered = M.ToolClass()
        net.Start("grm_ore_buyer_open")
            net.WriteEntity(IsValid(buyer) and buyer or NULL)
            net.WriteTable(rows)
            net.WriteBool(M.HasTool(ply) and true or false)
            net.WriteUInt(math.max(0, DEPOSIT:GetInt()), 24)
            net.WriteBool(registered ~= false)
        net.Send(ply)
    end

    net.Receive("grm_ore_sell", function(bits, ply)
        if not guard(ply, "mining.sell", bits) then return end
        local ore = tostring(net.ReadString() or "")
        local buyer = nearestBuyer(ply)
        if not IsValid(buyer) then notify(ply, "Скупщик не найден рядом", false) return end
        local ok, msg = M.Sell(ply, ore, buyer)
        notify(ply, msg, ok)
        M.PushBuyer(ply, buyer)
    end)

    net.Receive("grm_ore_buyer_give_jackhammer", function(bits, ply)
        if not guard(ply, "mining.tool.give", bits) then return end
        local buyer = nearestBuyer(ply)
        if not IsValid(buyer) then notify(ply, "Скупщик не найден рядом", false) return end
        local ok, msg = M.GiveTool(ply, buyer)
        notify(ply, msg, ok)
        M.PushBuyer(ply, buyer)
    end)

    net.Receive("grm_ore_buyer_return_jackhammer", function(bits, ply)
        if not guard(ply, "mining.tool.return", bits) then return end
        local buyer = nearestBuyer(ply)
        if not IsValid(buyer) then notify(ply, "Скупщик не найден рядом", false) return end
        local ok, msg = M.ReturnTool(ply)
        notify(ply, msg, ok)
        M.PushBuyer(ply, buyer)
    end)

    ------------------------------------------------------------------
    -- КОМАНДЫ
    ------------------------------------------------------------------
    local function pricesToChat(ply)
        local function out(msg) if IsValid(ply) then ply:ChatPrint(msg) else print(msg) end end
        out("[Шахта] Цены скупки:")
        for _, ore in ipairs(M.OreOrder) do
            out(("  %s — %s"):format(M.OreName(ore), GRM.Format and GRM.Format(GRM.OrePrices[ore] or 0) or tostring(GRM.OrePrices[ore] or 0)))
        end
    end

    concommand.Add("grm_mining_prices", function(ply) pricesToChat(ply) end)
    concommand.Add("grm_mining_price", function(ply, _, args)
        if IsValid(ply) and not ply:IsAdmin() then return end
        local ok, msg = M.SetPrice(args[1], args[2])
        if IsValid(ply) then ply:ChatPrint("[Шахта] " .. tostring(msg)) else print(msg) end
    end)
    concommand.Add("grm_mining_tool_return", function(ply)
        if not IsValid(ply) then return end
        local ok, msg = M.ReturnTool(ply)
        notify(ply, msg, ok)
    end)

    local function chat(ply, text)
        local args = string.Explode(" ", string.Trim(tostring(text or "")))
        local cmd = string.lower(args[1] or "")
        if cmd == "/mine_prices" or cmd == "/цены_руды" then pricesToChat(ply) return true end
        if cmd == "/mine_price" then
            if not ply:IsAdmin() then notify(ply, "Только администрация.", false) return true end
            local ok, msg = M.SetPrice(args[2], args[3])
            notify(ply, msg, ok)
            return true
        end
        if cmd == "/mine_tool" or cmd == "/бур" then
            local buyer = nearestBuyer(ply)
            if not IsValid(buyer) then notify(ply, "Подойдите к скупщику руды.", false) return true end
            M.PushBuyer(ply, buyer)
            return true
        end
        return false
    end
    hook.Add("PlayerSay", "GRM_Mining_Chat", function(ply, text) if chat(ply, text) then return "" end end)
    hook.Add("PlayerSayTransform", "GRM_Mining_ChatEC", function(ply, pack)
        if not (istable(pack) and isstring(pack[1])) then return end
        if chat(ply, pack[1]) then pack[1] = "" pack.SkipPlayerSay = true end
    end)

    list.Set("SpawnableEntities", "grm_ore_node", {
        PrintName = "Узел руды (медь/алюминий/золото/платина)",
        ClassName = "grm_ore_node",
        Category = "GRM MINE",
    })

    print("[GRM Mining] server v" .. M.Version .. " loaded")
end

-----------------------------------------------------------------------
-- КЛИЕНТ: прогресс добычи в стиле GRM
-----------------------------------------------------------------------
if CLIENT then
    surface.CreateFont("GRMMine_Bar", { font = "Roboto", size = 15, weight = 700, extended = true })

    local node, progress, until_ = nil, 0, 0

    net.Receive("grm_ore_progress", function()
        node = net.ReadEntity()
        progress = net.ReadFloat()
        until_ = CurTime() + 1.2
    end)

    hook.Add("HUDPaint", "GRM_Mining_ProgressBar", function()
        if CurTime() > until_ or not IsValid(node) then return end
        local ply = LocalPlayer()
        if not IsValid(ply) then return end
        local wep = ply:GetActiveWeapon()
        if not (IsValid(wep) and GRM.Mining.IsMiningTool(wep:GetClass())) then return end

        local w, h = 320, 44
        local x, y = ScrW() / 2 - w / 2, ScrH() * 0.62
        local ore = node.GetNWString and node:GetNWString("GRM_OreType", "") or ""
        local col = GRM.Mining.OreColor(ore)

        draw.RoundedBox(8, x, y, w, h, Color(12, 17, 25, 240))
        surface.SetDrawColor(38, 48, 66, 220)
        surface.DrawOutlinedRect(x, y, w, h)
        draw.SimpleText(ore ~= "" and GRM.Mining.OreName(ore) or "Добыча руды", "GRMMine_Bar", x + 12, y + 11,
            Color(240, 244, 250), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(math.floor(progress * 100) .. "%", "GRMMine_Bar", x + w - 12, y + 11,
            Color(245, 195, 65), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        draw.RoundedBox(4, x + 12, y + 26, w - 24, 8, Color(30, 38, 52))
        draw.RoundedBox(4, x + 12, y + 26, (w - 24) * math.Clamp(progress, 0, 1), 8, col)
    end)

    print("[GRM Mining] client v" .. M.Version .. " loaded")
end
