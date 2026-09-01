--[[--------------------------------------------------------------------
    GRM Medical Full v2.1.0 — лечение, препараты, диагностика

    Не заменяет medcards (`sh_grm_medical.lua`), а дополняет их:
      • статусы пациента: bleed/pain/infection/poison/addiction
      • препараты: painkillers/antibiotics/adrenaline/detox/advanced kit
      • /diagnose для медиков
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.MedicalFull = GRM.MedicalFull or {}
local MED = GRM.MedicalFull
MED.Version = "2.1.0"

local function clamp(v, lo, hi)
    v = tonumber(v) or lo or 0
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

MED.Config = MED.Config or {
    BleedRate = 2,
    BleedDamage = 1,
    InfectionRate = 1,
    MaxPain = 100,
}

MED.Recipes = {
    painkillers = {
        name = "Обезболивающее",
        model = "models/bloocobalt/l4d/items/w_eq_pills.mdl",
        ingredients = { narc_solvent = 2, narc_precursor = 1 },
        yield = 5,
        time = 20,
        effect = { pain = -50 },
    },
    antibiotics = {
        name = "Антибиотики",
        model = "models/bloocobalt/l4d/items/w_eq_pills.mdl",
        ingredients = { narc_solvent = 3, narc_precursor = 2 },
        yield = 4,
        time = 30,
        effect = { infection = -40 },
    },
    adrenaline = {
        name = "Адреналин",
        model = "models/jmod/resources/coolant_bottle.mdl",
        ingredients = { narc_solvent = 5, narc_precursor = 3, narc_equipment = 1 },
        yield = 2,
        time = 45,
        effect = { health = 30, bleed = -20 },
    },
    detox = {
        name = "Детокс-комплект",
        model = "models/healthvial.mdl",
        ingredients = { narc_solvent = 4, narc_precursor = 2 },
        yield = 2,
        time = 40,
        effect = { addiction = -35, poisoned = -50 },
    },
}

function MED.RegisterItems()
    if not (GRM.Inventory and GRM.Inventory.RegisterItem) then return false end
    for id, recipe in pairs(MED.Recipes) do
        GRM.Inventory.RegisterItem("med_" .. id, {
            type = "item",
            name = recipe.name,
            desc = "Медицинский препарат. Применение: из инвентаря.",
            icon = "icon16/pill.png",
            maxStack = 10,
            weight = 0.3,
            model = recipe.model,
            useFunc = "med_use_" .. id,
        })
    end
    GRM.Inventory.RegisterItem("med_kit_advanced", {
        type = "item",
        name = "Расширенная аптечка",
        desc = "Лечит 50 HP и останавливает кровотечение.",
        icon = "icon16/heart.png",
        maxStack = 3,
        weight = 2.0,
        model = "models/props/cs_office/cardboard_box03.mdl",
        useFunc = "med_use_kit",
    })
    return true
end
MED.RegisterItems()
timer.Simple(2, MED.RegisterItems)
timer.Simple(6, MED.RegisterItems)

if SERVER then
    util.AddNetworkString("GRM_Med_Scan")
    util.AddNetworkString("GRM_Med_Treat")
    util.AddNetworkString("GRM_Med_Status")

    local function notify(ply, msg, r, g, b)
        if GRM.Notify then GRM.Notify(ply, msg, r or 100, g or 220, b or 100)
        elseif IsValid(ply) and ply.ChatPrint then ply:ChatPrint("[Медицина] " .. tostring(msg or "")) end
    end

    function MED.IsMedic(ply)
        if not IsValid(ply) then return false end
        if ply:IsSuperAdmin() then return true end
        if GRM.Medical and GRM.Medical.CanTreat then
            local ok = GRM.Medical.CanTreat(ply)
            if ok then return true end
        end
        if Factions and Factions["Медики"] and istable(Factions["Медики"].Members) then
            local ck = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply)) or ply:SteamID64()
    return GRM.Identity.FactionMember(Factions["Медики"], ply) ~= nil
        end
        return false
    end

    function MED.Status(target)
        if not IsValid(target) then return {} end
        return {
            health = target:Health(),
            bleed = target:GetNWInt("GRM_Bleed", 0),
            pain = target:GetNWInt("GRM_Pain", 0),
            infection = target:GetNWInt("GRM_Infection", 0),
            poisoned = target:GetNWInt("GRM_Poisoned", 0),
            addiction = target:GetNWInt("GRM_Addiction", 0),
            narc = target:GetNWBool("GRM_NarcActive") and target:GetNWString("GRM_NarcType", "") or "нет",
        }
    end

    function MED.ApplyDrug(ply, medID, slotIdx)
        if not IsValid(ply) then return false end
        local recipe = MED.Recipes[medID]
        if not recipe then return false end
        local e = recipe.effect or {}
        if e.health then ply:SetHealth(math.min((ply.GetMaxHealth and ply:GetMaxHealth()) or 100, ply:Health() + e.health)) end
        if e.bleed then ply:SetNWInt("GRM_Bleed", clamp((ply:GetNWInt("GRM_Bleed", 0) or 0) + e.bleed, 0, 100)) end
        if e.pain then ply:SetNWInt("GRM_Pain", clamp((ply:GetNWInt("GRM_Pain", 0) or 0) + e.pain, 0, 100)) end
        if e.infection then ply:SetNWInt("GRM_Infection", clamp((ply:GetNWInt("GRM_Infection", 0) or 0) + e.infection, 0, 100)) end
        if e.poisoned then ply:SetNWInt("GRM_Poisoned", clamp((ply:GetNWInt("GRM_Poisoned", 0) or 0) + e.poisoned, 0, 100)) end
        if e.addiction then
            if GRM.Narcotics and GRM.Narcotics.ClearAddiction and e.addiction < 0 then
                GRM.Narcotics.ClearAddiction(ply, math.abs(e.addiction), "detox")
            else
                ply:SetNWInt("GRM_Addiction", clamp((ply:GetNWInt("GRM_Addiction", 0) or 0) + e.addiction, 0, 100))
            end
        end
        if GRM.Inventory and GRM.Inventory.RemoveFromSlot then GRM.Inventory.RemoveFromSlot(ply, slotIdx, 1)
        elseif GRM.Inventory then GRM.Inventory.RemoveItem(ply, "med_" .. medID, 1) end
        notify(ply, "Применено: " .. recipe.name)
        return true
    end

    function MED.RegisterUseHandlers()
        if not (GRM.Inventory and GRM.Inventory.RegisterUseHandler) then return false end
        for id in pairs(MED.Recipes) do
            GRM.Inventory.RegisterUseHandler("med_use_" .. id, function(ply, slotIdx)
                MED.ApplyDrug(ply, id, slotIdx)
            end)
        end
        GRM.Inventory.RegisterUseHandler("med_use_kit", function(ply, slotIdx)
            ply:SetHealth(math.min((ply.GetMaxHealth and ply:GetMaxHealth()) or 100, ply:Health() + 50))
            ply:SetNWInt("GRM_Bleed", 0)
            if GRM.Inventory.RemoveFromSlot then GRM.Inventory.RemoveFromSlot(ply, slotIdx, 1) else GRM.Inventory.RemoveItem(ply, "med_kit_advanced", 1) end
            notify(ply, "Раны перевязаны, кровотечение остановлено")
        end)
        return true
    end
    MED.RegisterUseHandlers()
    timer.Simple(2, MED.RegisterUseHandlers)
    timer.Simple(6, MED.RegisterUseHandlers)

    hook.Add("Think", "GRM_MedFull_Tick", function()
        local now = CurTime();if(MED._tickAt or 0)>now then return end;MED._tickAt=now+.25
        for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(ply) and ply:Alive() then
                local bleed = ply:GetNWInt("GRM_Bleed", 0)
                if bleed > 0 and (ply._grmMedBleedAt or 0) <= now then
                    ply._grmMedBleedAt = now + 1
                    ply:TakeDamage(MED.Config.BleedDamage or 1, game.GetWorld(), game.GetWorld())
                    ply:SetNWInt("GRM_Bleed", math.max(0, bleed - (MED.Config.BleedRate or 2)))
                end
                local inf = ply:GetNWInt("GRM_Infection", 0)
                if inf > 0 and (ply._grmMedInfAt or 0) <= now then
                    ply._grmMedInfAt = now + 2
                    ply:TakeDamage(1, game.GetWorld(), game.GetWorld())
                    ply:SetNWInt("GRM_Infection", clamp(inf + (MED.Config.InfectionRate or 1), 0, 100))
                end
            end
        end
    end)

    hook.Add("PlayerSay", "GRM_Med_Diagnose", function(ply, text)
        local cmd = string.lower(string.Trim(text or ""))
        if cmd ~= "/diagnose" and cmd ~= "!diagnose" then return end
        if not MED.IsMedic(ply) then ply:ChatPrint("Только медики могут использовать диагностику") return "" end
        local tr = ply:GetEyeTrace()
        local target = tr.Entity
        if not IsValid(target) or not target:IsPlayer() then ply:ChatPrint("Наведитесь на игрока") return "" end
        local st = MED.Status(target)
        ply:ChatPrint("=== Диагностика: " .. target:Nick() .. " ===")
        ply:ChatPrint(string.format("  Здоровье: %d/100", st.health or 0))
        ply:ChatPrint(string.format("  Кровотечение: %d%%", st.bleed or 0))
        ply:ChatPrint(string.format("  Боль: %d%%", st.pain or 0))
        ply:ChatPrint(string.format("  Инфекция: %d%%", st.infection or 0))
        ply:ChatPrint(string.format("  Отравление: %d%%", st.poisoned or 0))
        ply:ChatPrint(string.format("  Зависимость: %d%%", st.addiction or 0))
        ply:ChatPrint("  Наркотический эффект: " .. tostring(st.narc or "нет"))
        if (st.bleed or 0) > 0 then ply:ChatPrint("  ⚠ ТРЕБУЕТСЯ: Перевязка") end
        if (st.pain or 0) > 50 then ply:ChatPrint("  ⚠ ТРЕБУЕТСЯ: Обезболивающее") end
        if (st.infection or 0) > 30 then ply:ChatPrint("  ⚠ ТРЕБУЕТСЯ: Антибиотики") end
        if (st.addiction or 0) > 30 or (st.poisoned or 0) > 30 then ply:ChatPrint("  ⚠ ТРЕБУЕТСЯ: Детокс-комплект") end
        return ""
    end)

    print("[GRM] Medical Full loaded v" .. tostring(MED.Version))
end
