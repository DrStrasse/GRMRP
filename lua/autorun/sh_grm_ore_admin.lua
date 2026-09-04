--[[--------------------------------------------------------------------
    GRM Ore Admin v2.0.0 — админ-команды шахты.

    ВАЖНАЯ НАХОДКА 19.08: этот файл держал ВТОРОЙ приёмник продажи руды
    (сетевое сообщение grm_ore_sell) — такой же был в скупщике. В GMod
    повторная регистрация ЗАТИРАЕТ предыдущую, поэтому реально работал тот,
    что загрузился последним, а правки во втором просто не действовали
    (в т.ч. проверка дистанции и цен). Теперь продажа живёт ровно в одном
    месте — GRM.Mining.Sell, а здесь только команды администрации.

    Команды (админ):
      !spawnore <тип>              — поставить узел руды по прицелу
      !setoreprice <тип> <цена>    — цена скупки (сохраняется в файл)
      !oreprices                   — показать цены
      !giveore <игрок> <тип> <кол> — выдать руду в инвентарь
      !mineclean                   — убрать все валяющиеся куски руды
----------------------------------------------------------------------]]
if not SERVER then return end

GRM = GRM or {}
GRM.Mining = GRM.Mining or {}
local M = GRM.Mining

local function oreTypes()
    return M.OreOrder or { "copper", "gold", "aluminum", "platinum" }
end

local function isOre(t)
    if M.IsOre then return M.IsOre(t) end
    return table.HasValue(oreTypes(), t)
end

local function tell(ply, msg)
    if IsValid(ply) then ply:PrintMessage(HUD_PRINTTALK, "[Шахта] " .. tostring(msg)) else print("[Шахта] " .. tostring(msg)) end
end

local function findPlayer(name)
    if not name or name == "" then return nil end
    local lower = string.lower(name)
    for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
        if IsValid(ply) and string.find(string.lower(ply:Nick()), lower, 1, true) then return ply end
    end
end

local function handle(ply, text)
    if not (IsValid(ply) and ply:IsAdmin()) then return false end
    local args = string.Explode(" ", string.Trim(tostring(text or "")))
    local cmd = string.lower(args[1] or "")

    if cmd == "!spawnore" then
        local oreType = string.lower(args[2] or "")
        if not isOre(oreType) then
            tell(ply, "Типы руды: " .. table.concat(oreTypes(), ", "))
            return true
        end
        local node = ents.Create("grm_ore_node")
        if not IsValid(node) then tell(ply, "Не удалось создать узел") return true end
        local tr = ply:GetEyeTrace()
        node:SetPos(tr.HitPos + tr.HitNormal * 10)
        node:Spawn()
        node:SetOreType(oreType)
        tell(ply, "Узел руды создан: " .. ((M.OreName and M.OreName(oreType)) or oreType))
        return true
    end

    if cmd == "!setoreprice" then
        if not M.SetPrice then tell(ply, "Модуль шахты не загружен") return true end
        local ok, msg = M.SetPrice(args[2], args[3])
        tell(ply, ok and msg or ("Ошибка: " .. tostring(msg) .. ". Использование: !setoreprice <тип> <цена>"))
        return true
    end

    if cmd == "!oreprices" then
        tell(ply, "Цены скупки:")
        for _, ore in ipairs(oreTypes()) do
            local price = (GRM.OrePrices or {})[ore] or 0
            tell(ply, ("  %s — %s"):format((M.OreName and M.OreName(ore)) or ore, GRM.Format and GRM.Format(price) or price))
        end
        return true
    end

    if cmd == "!giveore" then
        local target = findPlayer(args[2])
        local oreType = string.lower(args[3] or "")
        local amount = math.floor(tonumber(args[4]) or 0)
        if not IsValid(target) then tell(ply, "Игрок не найден. Использование: !giveore <игрок> <тип> <количество>") return true end
        if not isOre(oreType) then tell(ply, "Типы руды: " .. table.concat(oreTypes(), ", ")) return true end
        if amount <= 0 then tell(ply, "Количество должно быть больше нуля") return true end
        if not (GRM.Inventory and GRM.Inventory.AddItem) then tell(ply, "Инвентарь недоступен") return true end

        local notAdded = GRM.Inventory.AddItem(target, "ore_" .. oreType, amount)
        if notAdded == 0 then
            tell(ply, ("Выдано %d ед. руды игроку %s"):format(amount, target:Nick()))
            if GRM.Notify then GRM.Notify(target, ("Администрация выдала вам руду: %d ед."):format(amount), 120, 220, 140) end
        else
            tell(ply, ("Инвентарь игрока переполнен, добавлено только %d"):format(amount - notAdded))
        end
        return true
    end

    if cmd == "!mineclean" then
        local removed = 0
        for _, e in ipairs(ents.FindByClass("grm_ore_chunk")) do
            if IsValid(e) then e:Remove() removed = removed + 1 end
        end
        tell(ply, "Убрано кусков руды: " .. removed)
        return true
    end

    return false
end

hook.Add("PlayerSay", "GRM_OreAdminCmds", function(ply, text)
    if handle(ply, text) then return "" end
end)
hook.Add("PlayerSay", "GRM_OreAdminCmdsEC", function(ply, text, teamSays)
    local pack = { tostring(text or ""), SkipPlayerSay = false }
        if not (istable(pack) and isstring(pack[1])) then return end
        if handle(ply, pack[1]) then pack[1] = "" pack.SkipPlayerSay = true end

    if pack.SkipPlayerSay == true then return "" end
end)

print("[GRM Ore Admin] v2.0.0 — команды администрации шахты загружены")
