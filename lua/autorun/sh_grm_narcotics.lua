--[[--------------------------------------------------------------------
    GRM Narcotics v2.0.0 — наркотики, зависимость, отравление, эффекты

    Контракт:
      • предметы: narc_solvent/narc_precursor/narc_equipment + narc_<drug>
      • рецепты: используют реальные item-id ингредиентов
      • useFunc: narc_use_<drug> через безопасный RegisterUseHandler
      • статус: /narc_status
      • медицина может лечить через GRM.Narcotics.ClearAddiction(ply, amount)
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Narcotics = GRM.Narcotics or {}
local NARC = GRM.Narcotics
local function characterTimerKey(ply)
    if IsValid(ply) and GRM.Identity and GRM.Identity.CharacterKey then return GRM.Identity.CharacterKey(ply) end
    return IsValid(ply) and ply:SteamID64() or "0"
end

NARC.Version = "2.0.0"
NARC.Active = NARC.Active or {}

local function clamp(v, lo, hi)
    v = tonumber(v) or lo or 0
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

NARC.Config = NARC.Config or {
    AddictionChance = 0.15,
    MaxAddiction = 100,
    OverdoseDamage = 10,
    WithdrawalDamage = 4,
}

NARC.Ingredients = {
    narc_solvent = {
        name = "Растворитель",
        desc = "Химический растворитель для лабораторного синтеза. Производится из алюминиевой руды.",
        icon = "icon16/bottle.png",
        maxStack = 10,
        weight = 0.5,
        model = "models/jmod/resources/coolant_bottle.mdl",
    },
    narc_precursor = {
        name = "Прекурсор",
        desc = "Химический прекурсор для синтеза. Производится из медной руды.",
        icon = "icon16/box.png",
        maxStack = 10,
        weight = 1.0,
        model = "models/props/cs_office/cardboard_box03.mdl",
    },
    narc_equipment = {
        name = "Оборудование для варки",
        desc = "Расходуемое лабораторное оборудование.",
        icon = "icon16/wrench.png",
        maxStack = 1,
        weight = 5.0,
        model = "models/props_wasteland/laundry_washer003.mdl",
    },
}

NARC.Recipes = {
    marijuana = {
        name = "Марихуана",
        desc = "Слабый наркотик: лёгкая регенерация, небольшой риск зависимости.",
        model = "models/jmod/resources/propellent.mdl",
        ingredients = { narc_solvent = 2, narc_precursor = 1 },
        cook_time = 30,
        yield = 3,
        effect = { duration = 120, speed = 1.05, jump = 1.05, health_regen = 1, addiction = 8, poison = 4 },
    },
    amphetamine = {
        name = "Амфетамин",
        desc = "Стимулятор: скорость и бодрость, высокий риск зависимости.",
        model = "models/bloocobalt/l4d/items/w_eq_pills.mdl",
        ingredients = { narc_solvent = 3, narc_precursor = 3 },
        cook_time = 60,
        yield = 5,
        effect = { duration = 180, speed = 1.20, jump = 1.05, health_regen = 0, addiction = 22, poison = 12 },
    },
    cocaine = {
        name = "Кокаин",
        desc = "Сильный наркотик: мощный краткий эффект, риск передозировки.",
        model = "models/bloocobalt/l4d/items/w_eq_pills.mdl",
        ingredients = { narc_solvent = 5, narc_precursor = 5, narc_equipment = 1 },
        cook_time = 90,
        yield = 7,
        effect = { duration = 90, speed = 1.35, jump = 1.10, damage = 1.25, health_regen = 3, addiction = 38, poison = 25 },
    },
}

function NARC.RegisterItems()
    if not (GRM.Inventory and GRM.Inventory.RegisterItem) then return false end

    for id, item in pairs(NARC.Ingredients) do
        GRM.Inventory.RegisterItem(id, {
            type = "item",
            name = item.name,
            desc = item.desc,
            icon = item.icon,
            maxStack = item.maxStack,
            weight = item.weight,
            model = item.model,
        })
    end

    for id, recipe in pairs(NARC.Recipes) do
        GRM.Inventory.RegisterItem("narc_" .. id, {
            type = "item",
            name = recipe.name,
            desc = recipe.desc or "Наркотическое вещество. Вызывает зависимость.",
            icon = "icon16/pill.png",
            maxStack = 5,
            weight = 0.2,
            model = recipe.model,
            useFunc = "narc_use_" .. id,
        })
    end

    return true
end

NARC.RegisterItems()
timer.Simple(2, NARC.RegisterItems)
timer.Simple(6, NARC.RegisterItems)

if SERVER then
    util.AddNetworkString("GRM_Narc_Status")

    local function notify(ply, msg, r, g, b)
        if GRM.Notify then GRM.Notify(ply, msg, r or 255, g or 120, b or 120)
        elseif IsValid(ply) and ply.ChatPrint then ply:ChatPrint("[Наркотики] " .. tostring(msg or "")) end
    end

    function NARC.GetAddiction(ply)
        return IsValid(ply) and (ply:GetNWInt("GRM_Addiction", 0) or 0) or 0
    end

    function NARC.SetAddiction(ply, value, reason)
        if not IsValid(ply) then return end
        value = clamp(math.floor(tonumber(value) or 0), 0, NARC.Config.MaxAddiction or 100)
        ply:SetNWInt("GRM_Addiction", value)
        ply:SetNWString("GRM_AddictionReason", tostring(reason or ""))
    end

    function NARC.ClearAddiction(ply, amount, reason)
        if not IsValid(ply) then return end
        amount = math.max(0, math.floor(tonumber(amount) or 100))
        NARC.SetAddiction(ply, NARC.GetAddiction(ply) - amount, reason or "treatment")
        ply:SetNWInt("GRM_Poisoned", math.max(0, (ply:GetNWInt("GRM_Poisoned", 0) or 0) - amount))
        notify(ply, "Детоксикация: зависимость снижена", 100, 220, 140)
    end

    function NARC.GetEffect(ply)
        return IsValid(ply) and NARC.Active[ply] or nil
    end

    function NARC.ApplyEffect(ply, drug)
        if not IsValid(ply) or not ply:Alive() then return false end
        drug = tostring(drug or "")
        local recipe = NARC.Recipes[drug]
        local effect = recipe and recipe.effect
        if not effect then return false end

        local now = CurTime()
        local duration = tonumber(effect.duration) or 60
        local untilTime = now + duration

        NARC.Active[ply] = {
            type = drug,
            untilTime = untilTime,
            nextRegen = now,
            nextDamage = now,
            effect = effect,
        }

        ply:SetNWBool("GRM_NarcActive", true)
        ply:SetNWString("GRM_NarcType", drug)
        ply:SetNWFloat("GRM_NarcUntil", untilTime)
        ply:SetNWFloat("GRM_NarcSpeedMul", tonumber(effect.speed) or 1)
        ply:SetNWFloat("GRM_NarcJumpMul", tonumber(effect.jump) or 1)
        ply:SetNWFloat("GRM_NarcDamageMul", tonumber(effect.damage) or 1)

        local add = math.floor(tonumber(effect.addiction) or 0)
        if math.random() >= (NARC.Config.AddictionChance or 0.15) then add = math.floor(add * 0.35) end
        if add > 0 then NARC.SetAddiction(ply, NARC.GetAddiction(ply) + add, drug) end
        local poison = math.floor(tonumber(effect.poison) or 0)
        if poison > 0 then ply:SetNWInt("GRM_Poisoned", clamp((ply:GetNWInt("GRM_Poisoned", 0) or 0) + poison, 0, 100)) end

        timer.Create("GRM_Narc_End_" .. characterTimerKey(ply), duration, 1, function()
            if not IsValid(ply) then return end
            local cur = NARC.Active[ply]
            if cur and cur.type == drug then
                NARC.Active[ply] = nil
                ply:SetNWBool("GRM_NarcActive", false)
                ply:SetNWString("GRM_NarcType", "")
                ply:SetNWFloat("GRM_NarcUntil", 0)
                ply:SetNWFloat("GRM_NarcSpeedMul", 1)
                ply:SetNWFloat("GRM_NarcJumpMul", 1)
                ply:SetNWFloat("GRM_NarcDamageMul", 1)
                notify(ply, "Действие вещества прошло: " .. recipe.name, 180, 180, 220)
            end
        end)

        notify(ply, "Вы употребили: " .. recipe.name, 255, 120, 120)
        return true
    end

    function NARC.RegisterUseHandlers()
        if not (GRM.Inventory and GRM.Inventory.RegisterUseHandler) then return false end
        for id in pairs(NARC.Recipes or {}) do
            GRM.Inventory.RegisterUseHandler("narc_use_" .. id, function(ply, slotIdx)
                if NARC.ApplyEffect(ply, id) then
                    if GRM.Inventory.RemoveFromSlot then GRM.Inventory.RemoveFromSlot(ply, slotIdx, 1)
                    else GRM.Inventory.RemoveItem(ply, "narc_" .. id, 1) end
                end
            end)
        end
        return true
    end

    NARC.RegisterUseHandlers()
    timer.Simple(2, NARC.RegisterUseHandlers)
    timer.Simple(6, NARC.RegisterUseHandlers)

    hook.Add("Think", "GRM_Narc_Tick", function()
        local now = CurTime();if(NARC._tickAt or 0)>now then return end;NARC._tickAt=now+.25
        for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(ply) and ply:Alive() then
                local active = NARC.Active[ply]
                if active and active.untilTime > now then
                    local effect = active.effect or {}
                    if (effect.health_regen or 0) > 0 and (active.nextRegen or 0) <= now then
                        active.nextRegen = now + 1
                        local maxHp = (ply.GetMaxHealth and ply:GetMaxHealth()) or 100
                        if ply:Health() < maxHp then ply:SetHealth(math.min(maxHp, ply:Health() + (effect.health_regen or 0))) end
                    end
                elseif active then
                    NARC.Active[ply] = nil
                    ply:SetNWBool("GRM_NarcActive", false)
                    ply:SetNWString("GRM_NarcType", "")
                    ply:SetNWFloat("GRM_NarcSpeedMul", 1)
                    ply:SetNWFloat("GRM_NarcJumpMul", 1)
                    ply:SetNWFloat("GRM_NarcDamageMul", 1)
                end

                local addiction = NARC.GetAddiction(ply)
                if addiction > 80 and (ply._grmNarcNextOD or 0) <= now then
                    ply._grmNarcNextOD = now + 5
                    ply:TakeDamage(NARC.Config.WithdrawalDamage or NARC.Config.OverdoseDamage or 4, game.GetWorld(), game.GetWorld())
                    notify(ply, "Ломка/передозировка наносит вред", 255, 80, 80)
                end
            end
        end
    end)

    hook.Add("EntityTakeDamage", "GRM_Narc_DamageMul", function(target, dmg)
        local att = dmg:GetAttacker()
        if IsValid(att) and att:IsPlayer() and att:GetNWBool("GRM_NarcActive") then
            local mul = tonumber(att:GetNWFloat("GRM_NarcDamageMul", 1)) or 1
            if mul ~= 1 then dmg:ScaleDamage(mul) end
        end
    end)

    hook.Add("PlayerDisconnected", "GRM_Narc_Cleanup", function(ply)
        NARC.Active[ply] = nil
        timer.Remove("GRM_Narc_End_" .. characterTimerKey(ply))
    end)

    hook.Add("PlayerSay", "GRM_Narc_StatusCmd", function(ply, text)
        local cmd = string.lower(string.Trim(text or ""))
        if cmd == "/narc_status" or cmd == "!narc_status" or cmd == "/drugstatus" then
            local active = ply:GetNWBool("GRM_NarcActive") and ply:GetNWString("GRM_NarcType", "") or "нет"
            ply:ChatPrint("[Наркотики] Активный эффект: " .. tostring(active))
            ply:ChatPrint("[Наркотики] Зависимость: " .. tostring(NARC.GetAddiction(ply)) .. "/100")
            ply:ChatPrint("[Наркотики] Отравление: " .. tostring(ply:GetNWInt("GRM_Poisoned", 0)) .. "/100")
            return ""
        end
    end)

    print("[GRM] Narcotics System loaded v" .. tostring(NARC.Version))
end

-- Вечер-18: единый словарь slash-команд: имена живого PlayerSay-обработчика
-- вносятся во внешний реестр библиотеки (на режиме сверка идёт ДО ParseSay —
-- без регистрации команда стала бы «неизвестной»).
if GRM and GRM.Chat and GRM.Chat.RegisterExternalCommands then
    GRM.Chat.RegisterExternalCommands({ "/drugstatus", "/narc_status" })
end
