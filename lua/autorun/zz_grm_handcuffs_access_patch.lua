--[[--------------------------------------------------------------------
    GRM Handcuffs Access / Existing Factions Sync Patch

    Куда положить:
      garrysmod/addons/grm_handcuffs/lua/autorun/zz_grm_handcuffs_access_patch.lua

    Главная идея:
      Наручники должны брать доступ из уже существующей системы фракций на сервере.

    Что читается автоматически:
      1) garrysmod/data/factions.json
         - фракции;
         - участники;
         - роли;
         - отделы.

      2) garrysmod/data/fw_faction_extras.json
         - Weapons;
         - RoleWeapons;
         - DepartmentWeapons.

    Как правильно выдать доступ:
      Через вашу админку оружия /weapons_admin добавьте classname:
        grm_handcuffs

      Можно добавить:
        - всей фракции;
        - конкретному рангу;
        - конкретному отделу.

      Тогда доступ к использованию наручников будет совпадать с тем,
      кому ваша Factions Extended уже выдаёт это оружие.
--------------------------------------------------------------------]]

if SERVER then
    AddCSLuaFile()
end

GRM = GRM or {}
GRM.Handcuffs = GRM.Handcuffs or {}
GRM.Handcuffs.Access = GRM.Handcuffs.Access or {}
GRM.Handcuffs.FileSync = GRM.Handcuffs.FileSync or {}

-- ===================================================================
-- СИНХРОНИЗАЦИЯ С УЖЕ СУЩЕСТВУЮЩИМИ МОДИФИКАЦИЯМИ
-- ===================================================================

-- Читать data/factions.json, если глобальная таблица Factions ещё не загрузилась.
GRM.Handcuffs.FileSync.UseFactionsJsonFallback = true
GRM.Handcuffs.FileSync.FactionsFile = "factions.json"

-- Читать data/fw_faction_extras.json для Weapons/RoleWeapons/DepartmentWeapons.
GRM.Handcuffs.FileSync.ExtrasFile = "fw_faction_extras.json"

-- Читать data/default_weapons.json только если AllowDefaultWeaponsAccess = true.
GRM.Handcuffs.FileSync.DefaultWeaponsFile = "default_weapons.json"

-- Кэш чтения файлов, чтобы не читать JSON каждый кадр.
GRM.Handcuffs.FileSync.CacheTTL = 2

-- ВАЖНО:
-- true = доступ автоматически зависит от вашей выдачи оружия в /weapons_admin.
-- Если игроку по фракции/рангу/отделу выдан grm_handcuffs, он может им пользоваться.
GRM.Handcuffs.FileSync.UseExistingWeaponAssignments = true

-- true = существующая настройка оружия главнее ручного AllowedFactions.
-- Если у ранга/отдела есть свой список оружия и там нет grm_handcuffs — доступа нет.
GRM.Handcuffs.FileSync.ExistingWeaponAssignmentsAreAuthoritative = true

-- false = если grm_handcuffs случайно окажется в default_weapons.json,
-- это не даст доступ всем игрокам сервера.
GRM.Handcuffs.FileSync.AllowDefaultWeaponsAccess = false

-- ===================================================================
-- БАЗОВЫЕ ПРАВА
-- ===================================================================

-- Superadmin всегда может использовать наручники.
GRM.Handcuffs.Access.SuperAdminBypass = true

-- Обычный admin тоже сможет использовать, если true.
GRM.Handcuffs.Access.AdminBypass = false

-- Если true, игрок обязан состоять во фракции с доступом.
GRM.Handcuffs.Access.RequireFactionSystem = true

-- ===================================================================
-- РУЧНОЙ ДОПОЛНИТЕЛЬНЫЙ ДОСТУП
-- ===================================================================

-- По умолчанию пусто, потому что основной доступ теперь берётся из /weapons_admin.
-- Если нужно выдать доступ фракции вручную, добавьте её сюда.
GRM.Handcuffs.Access.AllowedFactions = {
    -- ["Полиция"] = true,
    -- ["SWAT"] = true,
}

-- Доступ по конкретным рангам, если нужно вручную.
GRM.Handcuffs.Access.AllowedRoles = {
    -- ["Полиция"] = {
    --     ["Лидер"] = true,
    --     ["Офицер"] = true,
    -- },
}

-- Доступ по конкретным отделам, если нужно вручную.
GRM.Handcuffs.Access.AllowedDepartments = {
    -- ["Полиция"] = {
    --     ["Патруль"] = true,
    --     ["Спецназ"] = true,
    -- },
}

-- ===================================================================
-- ЗАПРЕТЫ
-- ===================================================================

-- Эти списки имеют приоритет над всем: и над /weapons_admin, и над ручным доступом.
GRM.Handcuffs.Access.DeniedFactions = {
    -- ["Гражданские"] = true,
}

GRM.Handcuffs.Access.DeniedRoles = {
    -- ["Полиция"] = {
    --     ["Кадет"] = true,
    -- },
}

GRM.Handcuffs.Access.DeniedDepartments = {
    -- ["Полиция"] = {
    --     ["Академия"] = true,
    -- },
}

-- ===================================================================
-- КОМАНДЫ ДЛЯ ПРОВЕРКИ
-- ===================================================================

-- Серверная консоль / superadmin:
--   grm_cuffs_reload_factions
--   grm_cuffs_debug_access <ник/SteamID/SteamID64>

print("[GRM Handcuffs] Access sync patch loaded: factions.json + fw_faction_extras.json.")
