--[[--------------------------------------------------------------------
    GRM Handcuffs - Server Core
--------------------------------------------------------------------]]

if not SERVER then return end

AddCSLuaFile("autorun/sh_grm_handcuffs_config.lua")
AddCSLuaFile("autorun/client/cl_grm_handcuffs.lua")
AddCSLuaFile("weapons/grm_handcuffs/shared.lua")
AddCSLuaFile("weapons/grm_cuffed/shared.lua")

include("autorun/sh_grm_handcuffs_config.lua")

GRM = GRM or {}
GRM.Handcuffs = GRM.Handcuffs or {}

local HC = GRM.Handcuffs

local function cfg()
    return HC.Config or {}
end

local function accessCfg()
    return HC.Access or {}
end

local function snd(key)
    local sounds = cfg().Sounds or {}
    return sounds[key]
end

function HC.Notify(ply, msg)
    if not IsValid(ply) then
        print(msg)
        return
    end

    if GRM and GRM.Notify then
        GRM.Notify(ply, msg, 100, 180, 255)
    else
        ply:ChatPrint(msg)
    end
end

function HC.Emit(ent, key)
    if not IsValid(ent) then return end
    local path = snd(key)
    if path and path ~= "" then
        ent:EmitSound(path, 70, 100, 1, CHAN_AUTO)
    end
end

local function steamIDs(ply)
    if not IsValid(ply) then return "", "", "" end
    local sid, sid64 = ply:SteamID(), ply:SteamID64()
    local ck = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply)) or sid64
    return sid, sid64, ck
end

-- ============================================================
-- ИНТЕГРАЦИЯ С ВАШЕЙ СИСТЕМОЙ ФРАКЦИЙ / FACTIONS.JSON
-- ============================================================

HC.FileSync = HC.FileSync or {
    FactionsFile = "factions.json",
    ExtrasFile = "fw_faction_extras.json",
    DefaultWeaponsFile = "default_weapons.json",
    CacheTTL = 2,

    -- true = если глобальная Factions ещё не загрузилась, читаем data/factions.json напрямую.
    UseFactionsJsonFallback = true,

    -- true = доступ к наручникам автоматически берётся из существующей настройки оружия
    -- Factions Extended: Weapons / RoleWeapons / DepartmentWeapons.
    UseExistingWeaponAssignments = true,

    -- true = если для игрока в существующей системе оружия есть конкретный список оружия,
    -- он считается главным источником доступа. Если grm_handcuffs там нет — доступа нет.
    ExistingWeaponAssignmentsAreAuthoritative = true,

    -- false по умолчанию: если grm_handcuffs лежит в default_weapons.json, это НЕ даёт доступ всем.
    AllowDefaultWeaponsAccess = false,
}

local function readJSONFile(path)
    if not path or path == "" then return nil end
    if not file.Exists(path, "DATA") then return nil end

    local raw = file.Read(path, "DATA")
    if not raw or raw == "" then return nil end

    local ok, data = pcall(util.JSONToTable, raw)
    if ok and istable(data) then return data end

    return nil
end

local function mergeFactionExtras(factionsTable)
    if not istable(factionsTable) then return factionsTable end

    local fs = HC.FileSync or {}
    local extras = nil

    -- Если Factions Extended уже загрузил экстра-поля в глобальную Factions, они уже будут в таблице.
    -- Но если глобальная Factions ещё без extras или мы читаем напрямую factions.json — доклеиваем fw_faction_extras.json.
    if fs.UseFactionsJsonFallback ~= false then
        extras = readJSONFile(fs.ExtrasFile or "fw_faction_extras.json")
    end

    if not istable(extras) then return factionsTable end

    for factionName, extra in pairs(extras) do
        if istable(extra) and istable(factionsTable[factionName]) then
            local f = factionsTable[factionName]

            if istable(extra.Models) then f.Models = extra.Models end
            if istable(extra.RoleModels) then f.RoleModels = extra.RoleModels end
            if istable(extra.DepartmentModels) then f.DepartmentModels = extra.DepartmentModels end

            if istable(extra.Weapons) then f.Weapons = extra.Weapons end
            if istable(extra.RoleWeapons) then f.RoleWeapons = extra.RoleWeapons end
            if istable(extra.DepartmentWeapons) then f.DepartmentWeapons = extra.DepartmentWeapons end
        end
    end

    return factionsTable
end

function HC.ReloadFactionCache()
    local fs = HC.FileSync or {}
    local fac = readJSONFile(fs.FactionsFile or "factions.json") or {}

    HC.FactionsFileCache = mergeFactionExtras(fac)
    HC.FactionsFileCacheTime = CurTime()

    return HC.FactionsFileCache
end

function HC.GetFactionsData()
    local fs = HC.FileSync or {}

    -- 1) Если основная система фракций уже загружена, берём её актуальную глобальную таблицу.
    -- Это важно: админ-меню может изменить фракции без рестарта.
    if istable(Factions) and table.Count(Factions) > 0 then
        local copy = table.Copy(Factions)
        return mergeFactionExtras(copy), "global"
    end

    -- 2) Если глобальной таблицы ещё нет, читаем напрямую garrysmod/data/factions.json.
    if fs.UseFactionsJsonFallback == false then
        return {}, "none"
    end

    if not HC.FactionsFileCache or CurTime() - (HC.FactionsFileCacheTime or 0) > (tonumber(fs.CacheTTL) or 2) then
        HC.ReloadFactionCache()
    end

    return HC.FactionsFileCache or {}, "file"
end

function HC.GetFactionInfo(ply)
    if not IsValid(ply) then return nil, nil, nil, nil end

    local sid, sid64, charKey = steamIDs(ply)
    local data, source = HC.GetFactionsData()

    for factionName, f in pairs(data or {}) do
        if istable(f) and istable(f.Members) then
            -- В вашем коде фракции используют SteamID(), но на всякий случай поддерживаем и SteamID64().
            local member
            if GRM.Identity and GRM.Identity.FactionMember then member = GRM.Identity.FactionMember(f, ply)
            else member = f.Members[sid] or f.Members[sid64] end
            if istable(member) then
                return factionName, member.Role, member.Department, f, source
            end
        end
    end

    return nil, nil, nil, nil, source
end

local function tableAllows(t, key)
    return istable(t) and key ~= nil and t[key] == true
end

local function nestedAllows(t, group, key)
    if not istable(t) or not key then return false end
    if istable(t[group]) and t[group][key] == true then return true end
    if istable(t["*"]) and t["*"][key] == true then return true end
    return false
end

local function listHasWeapon(list, weaponClass)
    if not istable(list) then return false end

    for _, class in ipairs(list) do
        if class == weaponClass then return true end
    end

    return false
end

function HC.GetDefaultWeapons()
    if istable(DEFAULT_WEAPONS) then return DEFAULT_WEAPONS end

    local fs = HC.FileSync or {}
    local data = readJSONFile(fs.DefaultWeaponsFile or "default_weapons.json")
    if istable(data) then return data end

    return {}
end

function HC.ExistingWeaponsGrantAccess(ply)
    local fs = HC.FileSync or {}
    if fs.UseExistingWeaponAssignments == false then return nil, false, "disabled" end

    local weaponClass = cfg().WeaponClass or "grm_handcuffs"
    local factionName, role, dept, f = HC.GetFactionInfo(ply)

    if not factionName or not istable(f) then
        return nil, false, "no_faction"
    end

    -- Повторяем приоритет вашей Factions Extended:
    -- DepartmentWeapons > RoleWeapons > Weapons > default.
    if dept and istable(f.DepartmentWeapons) and istable(f.DepartmentWeapons[dept]) and #f.DepartmentWeapons[dept] > 0 then
        return listHasWeapon(f.DepartmentWeapons[dept], weaponClass), true, "department"
    end

    if role and istable(f.RoleWeapons) and istable(f.RoleWeapons[role]) and #f.RoleWeapons[role] > 0 then
        return listHasWeapon(f.RoleWeapons[role], weaponClass), true, "role"
    end

    if istable(f.Weapons) and #f.Weapons > 0 then
        return listHasWeapon(f.Weapons, weaponClass), true, "faction"
    end

    if fs.AllowDefaultWeaponsAccess then
        local defaults = HC.GetDefaultWeapons()
        if istable(defaults) and #defaults > 0 then
            return listHasWeapon(defaults, weaponClass), true, "default"
        end
    end

    return nil, false, "not_configured"
end

function HC.HasAccess(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return false, "invalid" end

    local ac = accessCfg()
    local fs = HC.FileSync or {}

    if ac.SuperAdminBypass ~= false and ply:IsSuperAdmin() then return true end
    if ac.AdminBypass and ply:IsAdmin() then return true end

    local factionName, role, dept = HC.GetFactionInfo(ply)

    if not factionName then
        if ac.RequireFactionSystem == false then return true end
        return false, "Вы не состоите во фракции с доступом к наручникам."
    end

    -- Запреты всегда имеют приоритет над всеми источниками доступа.
    if tableAllows(ac.DeniedFactions, factionName) then return false, "Вашей фракции запрещены наручники." end
    if nestedAllows(ac.DeniedRoles, factionName, role) then return false, "Вашему рангу запрещены наручники." end
    if nestedAllows(ac.DeniedDepartments, factionName, dept) then return false, "Вашему отделу запрещены наручники." end

    -- 1) Автодоступ из уже существующей модификации Factions Extended.
    -- Если через /weapons_admin для фракции/роли/отдела выдан grm_handcuffs,
    -- то этот игрок имеет право им пользоваться.
    local weaponAllowed, weaponConfigured, level = HC.ExistingWeaponsGrantAccess(ply)
    if weaponConfigured then
        if weaponAllowed then return true end

        if fs.ExistingWeaponAssignmentsAreAuthoritative ~= false then
            return false, "Вашей роли/фракции не выдано оружие grm_handcuffs в /weapons_admin."
        end
    end

    -- 2) Ручной патч доступа zz_grm_handcuffs_access_patch.lua.
    local hasSpecificRoles = istable(ac.AllowedRoles) and (istable(ac.AllowedRoles[factionName]) or istable(ac.AllowedRoles["*"]))
    local hasSpecificDepts = istable(ac.AllowedDepartments) and (istable(ac.AllowedDepartments[factionName]) or istable(ac.AllowedDepartments["*"]))

    if nestedAllows(ac.AllowedRoles, factionName, role) then return true end
    if nestedAllows(ac.AllowedDepartments, factionName, dept) then return true end

    -- Если для этой фракции заданы конкретные роли/отделы, общий AllowedFactions не даёт доступ всем подряд.
    if not hasSpecificRoles and not hasSpecificDepts and tableAllows(ac.AllowedFactions, factionName) then
        return true
    end

    return false, "Недостаточно прав для использования наручников."
end

concommand.Add("grm_cuffs_reload_factions", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    HC.ReloadFactionCache()
    HC.Notify(ply, "[Наручники] Кэш factions.json / fw_faction_extras.json перезагружен.")
end)

concommand.Add("grm_cuffs_debug_access", function(ply, _, args)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end

    local target = ply
    local query = args[1]

    if query and query ~= "" then
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if string.find(string.lower(p:Nick()), string.lower(query), 1, true) or p:SteamID() == query or p:SteamID64() == query then
                target = p
                break
            end
        end
    end

    if not IsValid(target) then
        HC.Notify(ply, "[Наручники] Игрок не найден.")
        return
    end

    local fname, role, dept, _, source = HC.GetFactionInfo(target)
    local weaponAllowed, weaponConfigured, level = HC.ExistingWeaponsGrantAccess(target)
    local ok, reason = HC.HasAccess(target)

    HC.Notify(ply, "[Наручники DEBUG] Игрок: " .. target:Nick())
    HC.Notify(ply, "Фракция: " .. tostring(fname) .. " | Роль: " .. tostring(role) .. " | Отдел: " .. tostring(dept) .. " | source: " .. tostring(source))
    HC.Notify(ply, "Оружие из FactionsExt: configured=" .. tostring(weaponConfigured) .. " allowed=" .. tostring(weaponAllowed) .. " level=" .. tostring(level))
    HC.Notify(ply, "Итоговый доступ: " .. tostring(ok) .. " | " .. tostring(reason or "ok"))
end)

function HC.CanCuffTarget(actor, target)
    if not IsValid(actor) or not actor:IsPlayer() then return false, "invalid actor" end
    if not IsValid(target) or not target:IsPlayer() then return false, "Цель не игрок." end
    if actor == target then return false, "Нельзя надеть наручники на себя." end
    if not actor:Alive() or not target:Alive() then return false, "Игрок должен быть жив." end

    local ok, reason = HC.HasAccess(actor)
    if not ok then return false, reason end

    if target:IsAdmin() and cfg().AllowCuffAdmins == false and not actor:IsSuperAdmin() then
        return false, "Нельзя надеть наручники на администратора."
    end

    if not cfg().AllowSameFactionCuff then
        local af = select(1, HC.GetFactionInfo(actor))
        local tf = select(1, HC.GetFactionInfo(target))
        if af and tf and af == tf then
            return false, "Нельзя надеть наручники на участника своей фракции."
        end
    end

    return true
end

local ensureRestrainedWeapon

function HC.IsCuffed(ply)
    return IsValid(ply) and ply:GetNWBool("GRM_Cuffed", false)
end

function HC.StunPlayer(actor, target, seconds, options)
    if not IsValid(target) or not target:IsPlayer() then return false end
    options = istable(options) and options or {}
    seconds = math.Clamp(tonumber(seconds) or 4, 1, 30)
    target.GRM_StunnedUntil = math.max(tonumber(target.GRM_StunnedUntil) or 0, CurTime() + seconds)
    target:SetNWBool("GRM_Stunned", true)
    target:SetNWFloat("GRM_StunnedUntil", target.GRM_StunnedUntil)
    if not options.silent then target:EmitSound("Weapon_StunStick.Melee_Hit", 75, 100, 1, CHAN_WEAPON) end
    if not options.silentNotify and GRM.Notify then GRM.Notify(target, "Вы оглушены электродубинкой.", 255, 180, 90) end
    --[[ Раньше конец оглушения ждали опросом пять раз в секунду на КАЖДОГО
         оглушённого. Время окончания известно заранее, поэтому достаточно
         одного отложенного вызова: если оглушение продлили, он сам
         перезапишется (имя таймера то же), а лишних тиков не будет. ]]
    local stunName = "GRM_Stun_" .. target:EntIndex()
    local function endStun()
        if not IsValid(target) then return end
        local left = (target.GRM_StunnedUntil or 0) - CurTime()
        if left > 0.05 then
            timer.Create(stunName, left, 1, endStun)   -- оглушение продлили
            return
        end
        target:SetNWBool("GRM_Stunned", false)
        target:SetNWFloat("GRM_StunnedUntil", 0)
        timer.Remove(stunName)
    end
    timer.Create(stunName, math.max(0.1, seconds), 1, endStun)
    return true
end


-- ============================================================
-- ОРУЖИЕ ПРИ СКОВЫВАНИИ
-- ============================================================

local function restrainedClass()
    return cfg().RestrainedWeaponClass or "grm_cuffed"
end

local function ammoKey(ammoID)
    if not ammoID or ammoID < 0 then return nil end
    return game.GetAmmoName(ammoID) or tostring(ammoID)
end

function HC.StoreAndStripWeapons(ply)
    if not IsValid(ply) then return end
    if cfg().StripWeaponsOnCuff == false then return end

    -- Не перезаписываем нормальный loadout, если таймер повторно чистит оружие.
    if not ply.GRM_CuffStoredWeapons then
        local stored = {
            weapons = {},
            ammo = {},
            active = IsValid(ply:GetActiveWeapon()) and ply:GetActiveWeapon():GetClass() or nil,
        }

        for _, wep in ipairs(ply:GetWeapons()) do
            if IsValid(wep) and wep:GetClass() ~= restrainedClass() then
                local class = wep:GetClass()
                stored.weapons[#stored.weapons + 1] = {
                    class = class,
                    clip1 = wep:Clip1(),
                    clip2 = wep:Clip2(),
                }

                local a1 = ammoKey(wep:GetPrimaryAmmoType())
                local a2 = ammoKey(wep:GetSecondaryAmmoType())
                if a1 then stored.ammo[a1] = ply:GetAmmoCount(wep:GetPrimaryAmmoType()) end
                if a2 then stored.ammo[a2] = ply:GetAmmoCount(wep:GetSecondaryAmmoType()) end
            end
        end

        ply.GRM_CuffStoredWeapons = stored
    end

    -- Убираем всё оружие, чтобы физган/оружие не оставалось в руках.
    ply:StripWeapons()
end

function HC.EnforceCuffedWeaponState(ply)
    if not IsValid(ply) or not HC.IsCuffed(ply) then return end
    if ply:GetNWBool("GRM_Arrested", false) then
        ply.GRM_CuffStoredWeapons = nil
        ply:StripWeapons()
        if ply.RemoveAllAmmo then ply:RemoveAllAmmo() end
        return
    end
    if cfg().EnforceNoWeaponsWhileCuffed == false then return end

    for _, wep in ipairs(ply:GetWeapons()) do
        if IsValid(wep) and wep:GetClass() ~= restrainedClass() then
            ply:StripWeapon(wep:GetClass())
        end
    end

    ensureRestrainedWeapon(ply)
end

function HC.RestoreWeaponsAfterUncuff(ply)
    if not IsValid(ply) then return end

    local stored = ply.GRM_CuffStoredWeapons
    ply.GRM_CuffStoredWeapons = nil

    if cfg().RestoreWeaponsOnUncuff == false then return end
    if not istable(stored) then return end

    -- Сначала возвращаем боезапас, потом оружие/обоймы.
    if istable(stored.ammo) then
        for ammoName, amount in pairs(stored.ammo) do
            ply:SetAmmo(tonumber(amount) or 0, ammoName)
        end
    end

    for _, data in ipairs(stored.weapons or {}) do
        if data.class and data.class ~= "" then
            local wep = ply:Give(data.class)
            if IsValid(wep) then
                if tonumber(data.clip1) and tonumber(data.clip1) >= 0 then wep:SetClip1(data.clip1) end
                if tonumber(data.clip2) and tonumber(data.clip2) >= 0 then wep:SetClip2(data.clip2) end
            end
        end
    end

    if stored.active and ply:HasWeapon(stored.active) then
        timer.Simple(0, function()
            if IsValid(ply) and ply:HasWeapon(stored.active) then
                ply:SelectWeapon(stored.active)
            end
        end)
    end
end

function ensureRestrainedWeapon(ply)
    if not IsValid(ply) then return end
    if ply:GetNWBool("GRM_Arrested", false) then
        ply.GRM_CuffStoredWeapons = nil
        ply:StripWeapons()
        if ply.RemoveAllAmmo then ply:RemoveAllAmmo() end
        return
    end
    local class = cfg().RestrainedWeaponClass or "grm_cuffed"

    if not ply:HasWeapon(class) then
        ply:Give(class)
    end

    timer.Simple(0, function()
        if IsValid(ply) and ply:HasWeapon(class) then
            ply:SelectWeapon(class)
        end
    end)
end

local function clearEscortState(target)
    if not IsValid(target) then return end

    -- Чистим хвосты старой parent-реализации после lua_refresh, но никогда
    -- не привязываем игрока обратно и не меняем его мировую позицию.
    if IsValid(target:GetParent()) then target:SetParent(nil) end
    target:Freeze(false)
    target.GRM_CuffEscortDir = nil
    target:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
    target:SetNWBool("GRM_CuffDragged", false)
    target:SetNWEntity("GRM_CuffDragger", NULL)
end

function HC.StopDragging(dragger, target)
    if IsValid(target) then clearEscortState(target) end

    if IsValid(dragger) and dragger.GRM_Captives then
        if IsValid(target) then
            dragger.GRM_Captives[target] = nil
        else
            for captive in pairs(dragger.GRM_Captives) do
                clearEscortState(captive)
            end
            dragger.GRM_Captives = {}
        end
    end
end

function HC.StartDragging(dragger, target)
    if not IsValid(dragger) or not IsValid(target) then return false end
    if not HC.IsCuffed(target) then return false end

    dragger.GRM_Captives = dragger.GRM_Captives or {}

    local count = 0
    for captive in pairs(dragger.GRM_Captives) do
        if IsValid(captive) then count = count + 1 end
    end

    if count >= (cfg().MaxDraggedPlayers or 1) and not dragger.GRM_Captives[target] then
        HC.Notify(dragger, "[Наручники] Вы уже ведёте задержанного.")
        return false
    end

    local old = target:GetNWEntity("GRM_CuffDragger")
    if IsValid(old) and old ~= dragger then
        HC.Notify(dragger, "[Наручники] Этого игрока уже ведёт другой человек.")
        return false
    end

    dragger.GRM_Captives[target] = true
    target.GRM_CuffOriginalCollisionGroup = target.GRM_CuffOriginalCollisionGroup or target:GetCollisionGroup()

    -- Никаких SetParent/Freeze/SetPos: они телепортировали игрока в origin
    -- ведущего, наследовали pitch/roll и бросали его вверх/вниз на лестницах.
    -- Если код обновили через lua_refresh, сначала безопасно снимаем хвосты
    -- старого parent-escort, сохраняя текущие мировые координаты.
    if IsValid(target:GetParent()) then target:SetParent(nil) end
    target:Freeze(false)
    target:SetCollisionGroup(COLLISION_GROUP_DEBRIS)

    -- Начальная сторона берётся из фактического положения задержанного:
    -- при включении сопровождения он не перескакивает мгновенно за спину.
    local offset = target:GetPos() - dragger:GetPos()
    offset.z = 0
    if offset:LengthSqr() > 1 then
        target.GRM_CuffEscortDir = offset:GetNormalized()
    else
        local forward = dragger:GetForward()
        forward.z = 0
        target.GRM_CuffEscortDir = forward:LengthSqr() > 0 and -forward:GetNormalized() or Vector(-1, 0, 0)
    end

    target:SetNWBool("GRM_CuffDragged", true)
    target:SetNWEntity("GRM_CuffDragger", dragger)
    HC.Emit(dragger, "Drag")

    return true
end

function HC.CuffPlayer(actor, target)
    local ok, reason = HC.CanCuffTarget(actor, target)
    if not ok then
        HC.Notify(actor, "[Наручники] " .. tostring(reason))
        HC.Emit(actor, "Error")
        return false
    end

    if HC.IsCuffed(target) then
        HC.Notify(actor, "[Наручники] Игрок уже в наручниках.")
        return false
    end

    target:SetNWBool("GRM_Cuffed", true)
    HC.Cuffed = istable(HC.Cuffed) and HC.Cuffed or {}
    HC.Cuffed[target] = true
    if target.GRM_CuffOriginalCollisionGroup == nil then target.GRM_CuffOriginalCollisionGroup = target:GetCollisionGroup() end
    target:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
    target:SetNWEntity("GRM_CuffOwner", actor)
    target:SetNWFloat("GRM_CuffReleaseProgress", 0)
    target:SetNWBool("GRM_CuffGagged", false)
    target:SetNWBool("GRM_CuffBlindfolded", false)

    -- Сначала полностью убираем оружие игрока, затем выдаём только служебное
    -- состояние "в наручниках". Так физган/оружие не остаётся в руках.
    HC.StoreAndStripWeapons(target)
    ensureRestrainedWeapon(target)

    HC.Emit(target, "CuffSuccess")
    HC.Notify(actor, "[Наручники] Вы задержали " .. target:Nick() .. ".")
    HC.Notify(target, "[Наручники] Вас задержал " .. actor:Nick() .. ".")

    return true
end

function HC.UncuffPlayer(actor, target, silent)
    if not IsValid(target) or not HC.IsCuffed(target) then return false end

    local dragger = target:GetNWEntity("GRM_CuffDragger")
    if IsValid(dragger) then
        HC.StopDragging(dragger, target)
    end
    if target.GRM_CuffOriginalCollisionGroup ~= nil then
        target:SetCollisionGroup(target.GRM_CuffOriginalCollisionGroup)
        target.GRM_CuffOriginalCollisionGroup = nil
    end

    target:SetNWBool("GRM_Cuffed", false)
    if istable(HC.Cuffed) then HC.Cuffed[target] = nil end
    target:SetNWEntity("GRM_CuffOwner", NULL)
    target:SetNWBool("GRM_CuffDragged", false)
    target:SetNWEntity("GRM_CuffDragger", NULL)
    target:SetNWFloat("GRM_CuffReleaseProgress", 0)
    target:SetNWBool("GRM_CuffGagged", false)
    target:SetNWBool("GRM_CuffBlindfolded", false)

    local class = cfg().RestrainedWeaponClass or "grm_cuffed"
    if target:HasWeapon(class) then
        target:StripWeapon(class)
    end

    HC.RestoreWeaponsAfterUncuff(target)

    if not silent then
        if IsValid(actor) then
            HC.Notify(actor, "[Наручники] Вы сняли наручники с " .. target:Nick() .. ".")
        end
        HC.Notify(target, "[Наручники] С вас сняли наручники.")
    end

    HC.Emit(target, "Uncuff")
    return true
end

function HC.ToggleGag(actor, target)
    if not IsValid(target) or not HC.IsCuffed(target) then return false end
    local newVal = not target:GetNWBool("GRM_CuffGagged", false)
    target:SetNWBool("GRM_CuffGagged", newVal)
    HC.Emit(target, "Gag")
    HC.Notify(actor, newVal and "[Наручники] Кляп надет." or "[Наручники] Кляп снят.")
    HC.Notify(target, newVal and "[Наручники] Вам закрыли рот." or "[Наручники] Вам сняли кляп.")
    return true
end

function HC.ToggleBlindfold(actor, target)
    if not cfg().BlindfoldEnabled then return false end
    if not IsValid(target) or not HC.IsCuffed(target) then return false end
    local newVal = not target:GetNWBool("GRM_CuffBlindfolded", false)
    target:SetNWBool("GRM_CuffBlindfolded", newVal)
    HC.Emit(target, "Blindfold")
    HC.Notify(actor, newVal and "[Наручники] Повязка надета." or "[Наручники] Повязка снята.")
    HC.Notify(target, newVal and "[Наручники] Вам закрыли глаза." or "[Наручники] Вам сняли повязку.")
    return true
end

function HC.GetTracePlayer(ply, dist)
    if not IsValid(ply) then return nil end

    local tr = util.TraceLine({
        start = ply:EyePos(),
        endpos = ply:EyePos() + ply:GetAimVector() * (dist or cfg().CuffDistance or 110),
        filter = ply,
        mask = MASK_SHOT,
    })

    if IsValid(tr.Entity) and tr.Entity:IsPlayer() then
        return tr.Entity, tr
    end

    return nil, tr
end

function HC.BeginTimedAction(actor, target, actionName, duration, callback)
    if not IsValid(actor) or not IsValid(target) then return end

    actor.GRM_CuffAction = {
        target = target,
        action = actionName,
        finish = CurTime() + duration,
    }

    local timerName = "GRM_Handcuffs_Action_" .. actor:EntIndex()
    timer.Remove(timerName)

    timer.Create(timerName, duration, 1, function()
        if not IsValid(actor) or not IsValid(target) then return end
        actor.GRM_CuffAction = nil

        if actor:GetPos():DistToSqr(target:GetPos()) > (cfg().CuffDistance or 110) ^ 2 then
            HC.Notify(actor, "[Наручники] Цель слишком далеко.")
            return
        end

        callback(actor, target)
    end)
end


-- ============================================================
-- ТРАНСПОРТ: ПОСАДКА/ВЫСАДКА ЗАДЕРЖАННЫХ
-- Поддержка обычных seats, simfphys и LVS через универсальный поиск passenger seats.
-- ============================================================

local function isVehicleLike(ent)
    if not IsValid(ent) then return false end
    if ent:IsVehicle() then return true end

    local class = string.lower(ent:GetClass() or "")
    if string.find(class, "sim_fphys", 1, true) then return true end
    if string.find(class, "lvs", 1, true) then return true end
    if string.find(class, "gmod_sent_vehicle", 1, true) then return true end

    for _, child in ipairs(ent:GetChildren()) do
        if IsValid(child) and child:IsVehicle() then return true end
    end

    return false
end

local function activeCuffsOrDragging(ply)
    if not IsValid(ply) then return false end

    local wep = ply:GetActiveWeapon()
    if IsValid(wep) and wep:GetClass() == (cfg().WeaponClass or "grm_handcuffs") then
        return true
    end

    if istable(ply.GRM_Captives) then
        for captive in pairs(ply.GRM_Captives) do
            if IsValid(captive) then return true end
        end
    end

    return false
end

local function getDraggedCaptive(ply)
    if not IsValid(ply) or not istable(ply.GRM_Captives) then return nil end

    for captive in pairs(ply.GRM_Captives) do
        if IsValid(captive) and HC.IsCuffed(captive) then
            return captive
        end
    end

    return nil
end

local function addUniqueSeat(out, seat, isDriver, source)
    if not IsValid(seat) or not seat:IsVehicle() then return end

    for _, row in ipairs(out) do
        if row.seat == seat then
            row.isDriver = row.isDriver or isDriver
            row.source = row.source or source
            return
        end
    end

    out[#out + 1] = {
        seat = seat,
        isDriver = isDriver and true or false,
        source = source or "unknown",
    }
end

local function addFromValue(out, value, isDriver, source)
    if IsValid(value) then
        addUniqueSeat(out, value, isDriver, source)
        return
    end

    if not istable(value) then return end

    for _, v in pairs(value) do
        if IsValid(v) then
            addUniqueSeat(out, v, isDriver, source)
        elseif istable(v) then
            addFromValue(out, v, isDriver, source)
        end
    end
end

local function callEntityMethod(ent, methodName)
    if not IsValid(ent) or not ent[methodName] then return nil end

    local ok, result = pcall(ent[methodName], ent)
    if ok then return result end

    return nil
end

function HC.GetVehicleSeatRows(ent)
    local rows = {}
    if not IsValid(ent) then return rows end

    local base = ent
    if ent:IsVehicle() and IsValid(ent:GetParent()) then
        base = ent:GetParent()
    end

    -- Явные driver seats.
    local driverMethods = {
        "GetDriverSeat",
        "GetDriverSeatEntity",
        "GetDriverVehicle",
    }

    for _, method in ipairs(driverMethods) do
        addFromValue(rows, callEntityMethod(base, method), true, method)
        addFromValue(rows, callEntityMethod(ent, method), true, method)
    end

    -- Частые поля у simfphys/LVS/кастомных баз.
    local driverFields = { "DriverSeat", "driverSeat", "Seat", "seat" }
    for _, field in ipairs(driverFields) do
        addFromValue(rows, base[field], true, field)
        addFromValue(rows, ent[field], true, field)
    end

    -- Passenger-only методы. Их НЕ считаем водительскими.
    local passengerMethods = {
        "GetPassengerSeats",
        "GetPassengerSeat",
        "GetPassengerVehicles",
        "GetPassengerPods",
    }

    for _, method in ipairs(passengerMethods) do
        addFromValue(rows, callEntityMethod(base, method), false, method)
        addFromValue(rows, callEntityMethod(ent, method), false, method)
    end

    -- Общие методы/поля seats: там может быть и driver, поэтому если driver явно не известен,
    -- ниже будет fallback с исключением первого сиденья.
    local genericMethods = { "GetSeats", "GetSeatEntities", "GetVehicles" }
    for _, method in ipairs(genericMethods) do
        addFromValue(rows, callEntityMethod(base, method), false, method)
        addFromValue(rows, callEntityMethod(ent, method), false, method)
    end

    local genericFields = {
        "Seats", "seats", "pSeat", "pSeats", "PassengerSeats", "passengerSeats",
        "SeatEnts", "seatEnts", "Vehicles", "vehicles",
    }

    for _, field in ipairs(genericFields) do
        addFromValue(rows, base[field], false, field)
        addFromValue(rows, ent[field], false, field)
    end

    -- Дети entity: simfphys/LVS часто держат prop_vehicle_prisoner_pod как children.
    for _, child in ipairs(base:GetChildren()) do
        if IsValid(child) and child:IsVehicle() then
            addUniqueSeat(rows, child, false, "child")
        end
    end

    for _, child in ipairs(ent:GetChildren()) do
        if IsValid(child) and child:IsVehicle() then
            addUniqueSeat(rows, child, false, "child")
        end
    end

    -- Сам ent тоже может быть seat/vehicle. Если это не prisoner pod, чаще всего это driver.
    if ent:IsVehicle() then
        local class = string.lower(ent:GetClass() or "")
        local parent = ent:GetParent()
        local likelyDriver = class ~= "prop_vehicle_prisoner_pod" and not IsValid(parent)
        addUniqueSeat(rows, ent, likelyDriver, "self")
    end

    -- Последний fallback: ищем nearby vehicle seats, привязанные parent'ом или очень близкие к базе.
    local radius = cfg().VehicleSeatSearchRadius or 420
    local baseParent = IsValid(base:GetParent()) and base:GetParent() or NULL

    for _, v in ipairs(ents.FindInSphere(base:GetPos(), radius)) do
        if IsValid(v) and v:IsVehicle() then
            local related = false

            if v == ent or v == base then related = true end
            if v:GetParent() == base or v:GetParent() == ent then related = true end
            if IsValid(baseParent) and v:GetParent() == baseParent then related = true end
            if v:GetPos():DistToSqr(base:GetPos()) <= 260 * 260 then related = true end

            if related then
                local class = string.lower(v:GetClass() or "")
                local likelyDriver = class ~= "prop_vehicle_prisoner_pod" and not IsValid(v:GetParent())
                addUniqueSeat(rows, v, likelyDriver, "nearby")
            end
        end
    end

    -- Если driver seat явно не найден, исключаем первое сиденье из общего списка.
    -- Это выполняет требование: не садить на 1-е водительское, только 2/3/4.
    local hasDriver = false
    for _, row in ipairs(rows) do
        if row.isDriver then hasDriver = true break end
    end

    table.sort(rows, function(a, b)
        return a.seat:EntIndex() < b.seat:EntIndex()
    end)

    if not hasDriver and cfg().VehicleAllowDriverSeat == false and #rows > 1 then
        rows[1].isDriver = true
        rows[1].source = rows[1].source .. ":fallback_driver_first"
    end

    return rows
end

function HC.FindFreePassengerSeat(ent)
    local rows = HC.GetVehicleSeatRows(ent)

    for _, row in ipairs(rows) do
        local seat = row.seat
        if IsValid(seat) and seat:IsVehicle() and not row.isDriver then
            if not IsValid(seat:GetDriver()) then
                return seat
            end
        end
    end

    return nil
end

function HC.FindCuffedPassenger(ent)
    local rows = HC.GetVehicleSeatRows(ent)

    for _, row in ipairs(rows) do
        local seat = row.seat
        if IsValid(seat) and seat:IsVehicle() and not row.isDriver then
            local passenger = seat:GetDriver()
            if IsValid(passenger) and passenger:IsPlayer() and HC.IsCuffed(passenger) then
                return passenger, seat
            end
        end
    end

    return nil, nil
end

local function exitPosForVehicle(actor, ent)
    local offset = cfg().VehicleExitOffset or 80
    local dir = actor:GetPos() - ent:GetPos()
    dir.z = 0

    if dir:LengthSqr() < 1 then
        dir = actor:GetForward()
        dir.z = 0
    end

    dir:Normalize()

    local pos = ent:GetPos() + dir * offset + Vector(0, 0, 12)
    local tr = util.TraceHull({
        start = pos + Vector(0, 0, 48),
        endpos = pos - Vector(0, 0, 96),
        mins = Vector(-16, -16, 0),
        maxs = Vector(16, 16, 72),
        filter = { actor, ent },
        mask = MASK_PLAYERSOLID,
    })

    if tr.Hit then
        return tr.HitPos + Vector(0, 0, 4)
    end

    return pos
end

function HC.PutCuffedPlayerInVehicle(actor, captive, vehicleEnt)
    if not IsValid(actor) or not IsValid(captive) or not IsValid(vehicleEnt) then return false end
    if not HC.IsCuffed(captive) then return false end
    if captive:InVehicle() then return false end

    local seat = HC.FindFreePassengerSeat(vehicleEnt)
    if not IsValid(seat) then
        HC.Notify(actor, "[Наручники] Нет свободного пассажирского места. Водительское место запрещено.")
        HC.Emit(actor, "Error")
        return false
    end

    HC.StopDragging(actor, captive)

    captive.GRM_CuffForceEnterVehicle = true
    captive:SetPos(seat:GetPos() + Vector(0, 0, 8))
    captive:EnterVehicle(seat)

    timer.Simple(0, function()
        if IsValid(captive) then
            captive.GRM_CuffForceEnterVehicle = nil
            ensureRestrainedWeapon(captive)
        end
    end)

    HC.Notify(actor, "[Наручники] Задержанный посажен на пассажирское место.")
    HC.Notify(captive, "[Наручники] Вас посадили в транспорт.")
    HC.Emit(seat, "Drag")

    return true
end

function HC.ExtractCuffedPlayerFromVehicle(actor, vehicleEnt)
    if not IsValid(actor) or not IsValid(vehicleEnt) then return false end

    local passenger, seat = HC.FindCuffedPassenger(vehicleEnt)
    if not IsValid(passenger) then
        HC.Notify(actor, "[Наручники] В пассажирских сиденьях нет задержанного.")
        return false
    end

    passenger:ExitVehicle()

    timer.Simple(0, function()
        if not IsValid(actor) or not IsValid(passenger) then return end

        passenger:SetPos(exitPosForVehicle(actor, vehicleEnt))
        ensureRestrainedWeapon(passenger)
        HC.StartDragging(actor, passenger)
    end)

    HC.Notify(actor, "[Наручники] Задержанный вытащен из транспорта.")
    HC.Notify(passenger, "[Наручники] Вас вытащили из транспорта.")
    HC.Emit(IsValid(seat) and seat or vehicleEnt, "Drag")

    return true
end

function HC.TryHandleVehicleUse(actor, ent)
    if not IsValid(actor) or not IsValid(ent) then return false end
    if not isVehicleLike(ent) then return false end
    if not activeCuffsOrDragging(actor) then return false end

    local ok, reason = HC.HasAccess(actor)
    if not ok then
        HC.Notify(actor, "[Наручники] " .. tostring(reason))
        return true
    end

    if actor:GetPos():DistToSqr(ent:GetPos()) > (cfg().VehicleUseDistance or 170) ^ 2 then
        HC.Notify(actor, "[Наручники] Подойдите ближе к транспорту.")
        return true
    end

    -- Приоритет 1: если ведём задержанного — посадить его в пассажирское место.
    local captive = getDraggedCaptive(actor)
    if IsValid(captive) and not captive:InVehicle() then
        HC.PutCuffedPlayerInVehicle(actor, captive, ent)
        return true
    end

    -- Приоритет 2: если смотрим на транспорт с задержанным пассажиром — вытащить.
    local passenger = HC.FindCuffedPassenger(ent)
    if IsValid(passenger) then
        HC.ExtractCuffedPlayerFromVehicle(actor, ent)
        return true
    end

    HC.Notify(actor, "[Наручники] Некого посадить или вытащить.")
    return true
end

-- Доступ к выдаче через spawnmenu/физический pickup.
hook.Add("PlayerCanPickupWeapon", "GRM_Handcuffs_AccessPickup", function(ply, wep)
    if IsValid(wep) and wep:GetClass() == (cfg().WeaponClass or "grm_handcuffs") then
        local ok = HC.HasAccess(ply)
        if not ok then return false end
    end
end)

hook.Add("PlayerSwitchWeapon", "GRM_Handcuffs_ForceCuffedWeapon", function(ply, old, new)
    if HC.IsCuffed(ply) then
        if IsValid(new) and new:GetClass() == (cfg().RestrainedWeaponClass or "grm_cuffed") then return end
        ensureRestrainedWeapon(ply)
        return true
    end
end)

hook.Add("StartCommand", "GRM_Handcuffs_BlockControls", function(ply, cmd)
    if IsValid(ply) and ply:GetNWBool("GRM_Stunned", false) then
        cmd:ClearMovement()
        cmd:ClearButtons()
        return
    end
    if not HC.IsCuffed(ply) then return end

    cmd:RemoveKey(IN_ATTACK)
    cmd:RemoveKey(IN_ATTACK2)
    cmd:RemoveKey(IN_RELOAD)
    cmd:RemoveKey(IN_SPEED)
    cmd:RemoveKey(IN_JUMP)
    cmd:RemoveKey(IN_DUCK)

    -- Задержанный не может сам нажимать E для взаимодействия,
    -- освобождения, подбора или передачи. Освободить может только другой игрок.
    -- E не должен позволять выбирать сиденья, открывать Q-объекты или
    -- взаимодействовать с дверями/пропами во время наручников.
    cmd:RemoveKey(IN_USE)

    -- Во время сопровождения собственный WASD задержанного не должен
    -- бороться с серверной плавной траекторией и создавать дёрганье.
    if IsValid(ply:GetNWEntity("GRM_CuffDragger")) then
        cmd:ClearMovement()
    end
end)

hook.Add("SetupMove", "GRM_Handcuffs_Move", function(ply, mv, cmd)
    if not HC.IsCuffed(ply) then return end

    local dragger = ply:GetNWEntity("GRM_CuffDragger")
    if IsValid(dragger) and dragger:Alive() and not dragger:InVehicle() then
        local delta3 = dragger:GetPos() - ply:GetPos()
        local horizontalDistance = Vector(delta3.x, delta3.y, 0):Length()
        local verticalDistance = math.abs(delta3.z)

        -- Через стену, обрыв или другой этаж не тянем вообще. Сопровождение
        -- прекращается вместо телепорта, вертикального импульса или SetPos.
        if horizontalDistance > (cfg().EscortBreakDistance or 420)
            or verticalDistance > (cfg().EscortBreakVerticalDistance or 120) then
            HC.StopDragging(dragger, ply)
            HC.Notify(dragger, "[Наручники] Сопровождение прекращено: задержанный слишком далеко.")
            return
        end

        ply:SetCollisionGroup(COLLISION_GROUP_DEBRIS)

        local dt = math.Clamp(FrameTime(), 0.001, 0.05)
        local leaderVelocity = dragger:GetVelocity()
        leaderVelocity.z = 0

        -- Пока ведущий стоит, сохраняем сторону, с которой задержанного
        -- взяли. При движении плавно переводим его за спину по направлению
        -- фактической скорости, а не по углу камеры.
        local escortDir = ply.GRM_CuffEscortDir or Vector(-1, 0, 0)
        escortDir.z = 0
        if escortDir:LengthSqr() <= 0.001 then escortDir = Vector(-1, 0, 0) end
        escortDir:Normalize()

        if leaderVelocity:LengthSqr() > 25 * 25 then
            local wantedDir = leaderVelocity:GetNormalized() * -1
            local turnBlend = math.Clamp(dt * (cfg().EscortTurnRate or 5), 0, 1)
            escortDir = escortDir + (wantedDir - escortDir) * turnBlend
            escortDir.z = 0
            if escortDir:LengthSqr() > 0.001 then escortDir:Normalize() end
            ply.GRM_CuffEscortDir = escortDir
        end

        local desiredPos = dragger:GetPos() + escortDir * (cfg().DragFollowDistance or 52)
        local correction = desiredPos - ply:GetPos()
        correction.z = 0 -- главное: сопровождение никогда не управляет высотой
        local distance = correction:Length()
        local correctionVelocity = Vector(0, 0, 0)
        if distance > (cfg().EscortDeadZone or 10) then
            correctionVelocity = correction:GetNormalized()
                * ((distance - (cfg().EscortDeadZone or 10)) * (cfg().EscortCorrectionGain or 5.5))
        end

        local wantedVelocity = leaderVelocity + correctionVelocity
        wantedVelocity.z = 0
        local maxEscortSpeed = math.max(1, cfg().EscortMaxSpeed or 300)
        if wantedVelocity:LengthSqr() > maxEscortSpeed * maxEscortSpeed then
            wantedVelocity = wantedVelocity:GetNormalized() * maxEscortSpeed
        end

        -- Ускорение сглажено; вертикальная скорость принадлежит обычной
        -- физике игрока (земля, ступени, падение), поэтому нет подбрасываний.
        local currentVelocity = mv:GetVelocity()
        local blend = math.Clamp(dt * (cfg().EscortAcceleration or 8), 0, 1)
        local smoothVelocity = Vector(
            currentVelocity.x + (wantedVelocity.x - currentVelocity.x) * blend,
            currentVelocity.y + (wantedVelocity.y - currentVelocity.y) * blend,
            currentVelocity.z
        )
        mv:SetVelocity(smoothVelocity)
        mv:SetMaxClientSpeed(maxEscortSpeed)
        mv:SetMaxSpeed(maxEscortSpeed)
        return
    elseif ply:GetNWBool("GRM_CuffDragged", false) then
        HC.StopDragging(IsValid(dragger) and dragger or nil, ply)
    end

    local maxSpeed = mv:GetMaxClientSpeed()
    mv:SetMaxClientSpeed(maxSpeed * (cfg().CuffedWalkSpeedMultiplier or 0.45))
    mv:SetMaxSpeed(mv:GetMaxSpeed() * (cfg().CuffedWalkSpeedMultiplier or 0.45))
end)

hook.Add("CanPlayerEnterVehicle", "GRM_Handcuffs_NoVehicle", function(ply)
    if HC.IsCuffed(ply) and not ply.GRM_CuffForceEnterVehicle then return false end
end)

hook.Add("CanExitVehicle", "GRM_Handcuffs_NoSelfExitVehicle", function(vehicle, ply)
    if HC.IsCuffed(ply) then return false end
end)

hook.Add("PlayerCanPickupItem", "GRM_Handcuffs_NoItemPickup", function(ply)
    if HC.IsCuffed(ply) then return false end
end)

hook.Add("PlayerCanPickupWeapon", "GRM_Handcuffs_NoWeaponPickup", function(ply)
    if HC.IsCuffed(ply) then return false end
end)

hook.Add("PlayerSpawnProp", "GRM_Handcuffs_NoPropSpawn", function(ply)
    if HC.IsCuffed(ply) or ply:GetNWBool("GRM_Stunned", false) then return false end
end)
hook.Add("PlayerSpawnSENT", "GRM_Handcuffs_NoSentSpawn", function(ply)
    if HC.IsCuffed(ply) or ply:GetNWBool("GRM_Stunned", false) then return false end
end)
hook.Add("PlayerSpawnSWEP", "GRM_Handcuffs_NoSWEPSpawn", function(ply)
    if HC.IsCuffed(ply) or ply:GetNWBool("GRM_Stunned", false) then return false end
end)
hook.Add("PlayerSpawnVehicle", "GRM_Handcuffs_NoVehicleSpawn", function(ply)
    if HC.IsCuffed(ply) or ply:GetNWBool("GRM_Stunned", false) then return false end
end)

hook.Add("PlayerUse", "GRM_Handcuffs_ReleaseOrTransfer", function(ply, ent)
    if not IsValid(ply) or not IsValid(ent) then return end

    -- Задержанный не может сам пользоваться E: это закрывает смену
    -- сиденья, выход из транспорта, двери, Q-объекты и подбор предметов.
    if HC.IsCuffed(ply) then return false end

    -- Посадка/высадка задержанных в обычный транспорт, simfphys и LVS.
    if HC.TryHandleVehicleUse(ply, ent) then
        return false
    end

    if not ent:IsPlayer() then return end

    -- Передача задержанного другому игроку через E.
    if ply.GRM_Captives and not HC.IsCuffed(ent) then
        local ok = HC.HasAccess(ent)
        if ok then
            ent.GRM_Captives = ent.GRM_Captives or {}
            for captive in pairs(ply.GRM_Captives) do
                if IsValid(captive) then
                    HC.StopDragging(ply, captive)
                    HC.StartDragging(ent, captive)
                end
            end
            HC.Notify(ply, "[Наручники] Задержанный передан.")
            HC.Notify(ent, "[Наручники] Вам передали задержанного.")
            return false
        end
    end

    if not HC.IsCuffed(ent) then return end

    -- Дополнительная защита: даже если где-то сработает PlayerUse на себя,
    -- сам задержанный не сможет накапливать прогресс снятия.
    if ply == ent and cfg().CanSelfRelease == false then
        return false
    end

    local canRelease = cfg().AnyoneCanReleaseWithUse == true
    if not canRelease and cfg().AccessUsersCanReleaseWithUse ~= false then
        canRelease = HC.HasAccess(ply)
    end

    if not canRelease then return false end

    if ply:GetPos():DistToSqr(ent:GetPos()) > (cfg().ReleaseDistance or 115) ^ 2 then return false end

    ent.GRM_CuffReleaseLast = ent.GRM_CuffReleaseLast or {}
    local last = ent.GRM_CuffReleaseLast[ply] or CurTime()
    local dt = math.Clamp(CurTime() - last, 0, 0.2)
    ent.GRM_CuffReleaseLast[ply] = CurTime()

    local progress = ent:GetNWFloat("GRM_CuffReleaseProgress", 0)
    progress = math.Clamp(progress + (cfg().ReleaseRate or 32) * math.max(dt, 0.03), 0, cfg().ReleaseProgressMax or 100)
    ent:SetNWFloat("GRM_CuffReleaseProgress", progress)

    if progress >= (cfg().ReleaseProgressMax or 100) then
        HC.UncuffPlayer(ply, ent)
    elseif CurTime() >= (ent.GRM_CuffNextReleaseSound or 0) then
        ent.GRM_CuffNextReleaseSound = CurTime() + 0.35
        ent:EmitSound("physics/cardboard/cardboard_box_impact_soft" .. math.random(1, 7) .. ".wav", 55, 100)
    end

    return false
end)

hook.Add("PlayerDisconnected", "GRM_Handcuffs_CuffedRegistry", function(ply)
    if istable(HC.Cuffed) then HC.Cuffed[ply] = nil end
end)

timer.Create("GRM_Handcuffs_ReleaseDecay", 0.25, 0, function()
    -- Аудит нагрузки 18.08: проход по всем игрокам 4 раза в секунду шёл
    -- всегда. Реестр закованных ведёт сам модуль — обычно он пуст.
    if istable(HC.Cuffed) and next(HC.Cuffed) == nil then return end
    for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
        if HC.IsCuffed(ply) then
            local progress = ply:GetNWFloat("GRM_CuffReleaseProgress", 0)
            if progress > 0 then
                ply:SetNWFloat("GRM_CuffReleaseProgress", math.max(0, progress - 3))
            end
        end
    end
end)

timer.Create("GRM_Handcuffs_EnforceNoWeaponsWhileCuffed", 0.35, 0, function()
    -- Аудит 21.08: тот же приём, что и у таймера снятия прогресса — пока
    -- закованных нет, обход всех игроков три раза в секунду не нужен.
    if istable(HC.Cuffed) and next(HC.Cuffed) == nil then return end
    for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
        if HC.IsCuffed(ply) then
            HC.EnforceCuffedWeaponState(ply)
        end
    end
end)

hook.Add("PlayerCanHearPlayersVoice", "GRM_Handcuffs_GagVoice", function(listener, talker)
    if cfg().GagBlocksVoice and IsValid(talker) and talker:GetNWBool("GRM_CuffGagged", false) then
        return false
    end
end)

hook.Add("PlayerSay", "GRM_Handcuffs_GagChat", function(ply)
    if cfg().GagBlocksTextChat and ply:GetNWBool("GRM_CuffGagged", false) then
        return ""
    end
end)

hook.Add("PlayerDeath", "GRM_Handcuffs_ClearOnDeath", function(ply)
    if HC.IsCuffed(ply) then
        HC.UncuffPlayer(nil, ply, true)
    end

    HC.StopDragging(ply)
end)

hook.Add("PlayerDisconnected", "GRM_Handcuffs_ClearOnDisconnect", function(ply)
    HC.StopDragging(ply)
end)

concommand.Add("grm_cuffs_give", function(ply, _, args)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end

    local target = nil
    local query = args[1]

    if not query or query == "" then
        target = IsValid(ply) and ply or nil
    else
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if string.find(string.lower(p:Nick()), string.lower(query), 1, true) or p:SteamID() == query or p:SteamID64() == query then
                target = p
                break
            end
        end
    end

    if not IsValid(target) then
        HC.Notify(ply, "[Наручники] Игрок не найден.")
        return
    end

    target:Give(cfg().WeaponClass or "grm_handcuffs")
    HC.Notify(ply, "[Наручники] Выдано: " .. target:Nick())
end)

print("[GRM Handcuffs] Server loaded.")
