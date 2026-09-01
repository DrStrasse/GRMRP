--[[--------------------------------------------------------------------
    GRM Faction Economy Integration (Код 124)
    Интеграция системы доступов с /factions меню

    Добавляет вкладку "Экономика" в админ-меню фракций
    Суперадмин может выдавать доступы фракциям/ролям/отделам
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.FactionEconomy = GRM.FactionEconomy or {}
local FE = GRM.FactionEconomy

-- Проверка доступа к функции
function FE.HasAccess(ply, permission)
    if not IsValid(ply) then return false end

    -- Суперадмин имеет все доступы
    if ply:IsSuperAdmin() then return true end

    -- Проверяем через систему разрешений
    if GRM.FactionPerms and GRM.FactionPerms.PlayerHasPermission then
        return GRM.FactionPerms.PlayerHasPermission(ply, permission)
    end

    return false
end

-- Проверка доступа для экономики
function FE.CanViewStateBudget(ply)
    return FE.HasAccess(ply, "state_budget_view")
end

function FE.CanEditStateBudget(ply)
    return FE.HasAccess(ply, "state_budget_add") or FE.HasAccess(ply, "state_budget_remove")
end

function FE.CanViewFactionBudgets(ply)
    return FE.HasAccess(ply, "faction_budget_view")
end

function FE.CanEditFactionBudgets(ply)
    return FE.HasAccess(ply, "faction_budget_edit")
end

function FE.CanViewTaxes(ply)
    return FE.HasAccess(ply, "tax_view")
end

function FE.CanEditTaxes(ply)
    return FE.HasAccess(ply, "tax_edit")
end

function FE.CanIssueFines(ply)
    return FE.HasAccess(ply, "fine_issue")
end

function FE.CanSetKomHour(ply)
    return FE.HasAccess(ply, "kom_hour_set") or FE.HasAccess(ply, "kom_hour_remove")
end

function FE.CanPublishLaws(ply)
    return FE.HasAccess(ply, "law_publish")
end

if SERVER then
    print("[GRM] Faction Economy Integration loaded (Код 124)")
end
