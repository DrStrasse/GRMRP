--[[--------------------------------------------------------------------
    GRM Saver — permanent remove command patch

    Install as:
      lua/autorun/server/sv_grm_saver_delete_patch.lua

    Commands for admins:
      !remove_saved
      /remove_saved
      !delete_saved
      grm_remove_saved_look

    Looks at an entity, removes it from the world and immediately rewrites
    the appropriate persistence file so it does not return on map restart.
----------------------------------------------------------------------]]

if CLIENT then return end

local RANGE = 450

-- Classes handled by the original generic GRM Saver.
local GENERIC_CLASSES = {
    grm_ore_buyer = true,
    grm_ore_node = true,
    grm_worktable = true,
    grm_storage = true,
    grm_box = true,
}

local function isRemovable(ent)
    if not IsValid(ent) then return false end

    local class = ent:GetClass()

    return GENERIC_CLASSES[class] == true
        or string.StartWith(class, "grm_ind_")
end

local function findAimedEntity(ply)
    local trace = util.TraceLine({
        start = ply:EyePos(),
        endpos = ply:EyePos() + ply:GetAimVector() * RANGE,
        filter = ply,
        mask = MASK_ALL,
    })

    if isRemovable(trace.Entity) then return trace.Entity end

    -- Small fallback around the trace impact point for models with thin hitboxes.
    local closest, bestDistance
    for _, ent in ipairs(ents.FindInSphere(trace.HitPos, 80)) do
        if isRemovable(ent) then
            local distance = ent:GetPos():DistToSqr(trace.HitPos)
            if not bestDistance or distance < bestDistance then
                closest, bestDistance = ent, distance
            end
        end
    end

    return closest
end

local function rewritePersistence(class)
    -- Generic saver: ore buyer/nodes and legacy factory entities.
    if GRM_SaveEntities then
        GRM_SaveEntities()
    end

    -- Производство и логистика (31.08 переписаны: grm_fc_* и grm_logistics_*
    -- заменены на grm_ind_*). Узлы хранят содержимое в GRM.Container,
    -- поэтому удаление любого узла требует перезаписи карты.
    if string.StartWith(class, "grm_ind_")
        and GRM and GRM.Industry and GRM.Industry.Save then
        GRM.Industry.Save()
    end
end

local function permanentlyRemoveLookedEntity(ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end

    local ent = findAimedEntity(ply)
    if not IsValid(ent) then
        ply:ChatPrint("[GRM Saver] Посмотрите на сохраняемую entity в радиусе " .. RANGE .. ".")
        return
    end

    local class = ent:GetClass()
    local model = ent:GetModel() or ""

    -- Remove first. The subsequent save serializes only remaining entities.
    ent:Remove()

    timer.Simple(0.15, function()
        rewritePersistence(class)

        if IsValid(ply) then
            ply:ChatPrint("[GRM Saver] Entity удалена навсегда: " .. class)
            ply:ChatPrint("[GRM Saver] Модель: " .. model)
        end

        print("[GRM Saver] Permanent remove: " .. class .. " | " .. model)
    end)
end

concommand.Add("grm_remove_saved_look", permanentlyRemoveLookedEntity)
concommand.Add("grm_delete_saved_look", permanentlyRemoveLookedEntity)

hook.Add("PlayerSay", "GRM_Saver_PermanentRemoveCommand", function(ply, text)
    local command = string.lower(string.Trim(text or ""))

    if command == "!remove_saved" or command == "/remove_saved"
        or command == "!delete_saved" or command == "/delete_saved" then
        permanentlyRemoveLookedEntity(ply)
        return ""
    end
end)

print("[GRM Saver] Permanent remove command patch loaded")

-- Вечер-18: единый словарь slash-команд: имена живого PlayerSay-обработчика
-- вносятся во внешний реестр библиотеки (на режиме сверка идёт ДО ParseSay —
-- без регистрации команда стала бы «неизвестной»).
if GRM and GRM.Chat and GRM.Chat.RegisterExternalCommands then
    GRM.Chat.RegisterExternalCommands({ "/delete_saved", "/remove_saved" })
end
