--[[ Живой прогон смены СИСТЕМНОГО ключа должности во фракции: сама фракция,
     сотрудники, экипировка, инкассация, права, двери.
     Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_role_key_runtime.lua ]]

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

-- Модель фракции и хуков, повторяющая контракт sh_factions.setRoleKey.
local hooks = {}
local function hookAdd(event, name, fn) hooks[event] = hooks[event] or {} hooks[event][name] = fn end
local function hookRun(event, ...) for _, fn in pairs(hooks[event] or {}) do fn(...) end end

local function trim(v, n) return string.sub(tostring(v or ""), 1, n or 96) end
local function hasValue(t, v) for _, x in ipairs(t or {}) do if x == v then return true end end return false end

local Factions = {
    police = {
        Roles = { "chief", "officer", "cadet" },
        RoleDisplayNames = { chief = "Начальник", officer = "Офицер", cadet = "Кадет" },
        LeaderRoleName = "chief",
        Members = {
            ["7656:char1"] = { Role = "officer", Department = "patrol" },
            ["7657:char1"] = { Role = "officer", Department = "patrol" },
            ["7658:char1"] = { Role = "cadet", Department = "patrol" },
        },
        PersonnelArchive = { ["7659:char1"] = { Role = "officer" } },
        RoleModels = { officer = { "models/police.mdl" } },
        RoleWeapons = { officer = { "weapon_pistol" } },
        IncassoSettings = { Enabled = true, Roles = { "officer", "chief" }, Vehicles = {} },
        MaskDepartments = { { Roles = { "officer" }, Models = {} } },
        Subdepartments = { swat = { id = "swat", name = "СВАТ", parentDept = "patrol", roles = { "officer" } } },
    },
}

-- Точная копия правил из sh_factions.lua (контракт функции).
local saved = 0
local function setRoleKey(factionName, oldKey, newKey)
    local f = Factions[factionName]
    if not f then return false, "Фракция не найдена" end
    oldKey = tostring(oldKey or "")
    newKey = trim(newKey, 64)
    if not hasValue(f.Roles, oldKey) then return false, "Должность не найдена" end
    if newKey == "" then return false, "Новый системный ключ не указан" end
    if newKey == oldKey then return true, "Ключ не изменился" end
    if hasValue(f.Roles, newKey) then return false, "Должность с таким ключом уже есть" end

    for i, key in ipairs(f.Roles) do if key == oldKey then f.Roles[i] = newKey break end end
    if f.RoleDisplayNames then
        local display = f.RoleDisplayNames[oldKey]
        f.RoleDisplayNames[oldKey] = nil
        f.RoleDisplayNames[newKey] = (display and display ~= "") and display or newKey
    end
    if f.LeaderRoleName == oldKey then f.LeaderRoleName = newKey end

    local moved = 0
    for _, rec in pairs(f.Members or {}) do
        if type(rec) == "table" and rec.Role == oldKey then rec.Role = newKey moved = moved + 1 end
    end
    for _, rec in pairs(f.PersonnelArchive or {}) do
        if type(rec) == "table" and rec.Role == oldKey then rec.Role = newKey end
    end
    for _, field in ipairs({ "RoleModels", "RoleWeapons", "RoleVehicles" }) do
        local tbl = f[field]
        if type(tbl) == "table" and tbl[oldKey] ~= nil then tbl[newKey] = tbl[oldKey] tbl[oldKey] = nil end
    end
    local function renameInArray(arr)
        if type(arr) ~= "table" then return end
        for i, v in ipairs(arr) do if v == oldKey then arr[i] = newKey end end
    end
    if type(f.IncassoSettings) == "table" then renameInArray(f.IncassoSettings.Roles) end
    for _, dept in pairs(f.MaskDepartments or {}) do renameInArray(dept.Roles) end
    for _, sub in pairs(f.Subdepartments or {}) do renameInArray(sub.roles) end

    saved = saved + 1
    hookRun("GRM_FactionRoleKeyRenamed", factionName, oldKey, newKey, moved)
    return true, ("Ключ должности изменён: %s → %s (сотрудников переведено: %d)"):format(oldKey, newKey, moved)
end

-- Подписчики (повторяют вставленные обработчики модулей).
local PERMS = { Data = { police = { roles = { officer = { ["doors.manage"] = true } } } }, saves = 0 }
hookAdd("GRM_FactionRoleKeyRenamed", "perms", function(faction, oldKey, newKey)
    local fd = PERMS.Data[faction]
    if not (fd and fd.roles and fd.roles[oldKey] ~= nil) then return end
    fd.roles[newKey] = fd.roles[oldKey] fd.roles[oldKey] = nil PERMS.saves = PERMS.saves + 1
end)

local ACCESS = { ManageRoles = { police = { officer = true } }, WarrantRoles = { police = { chief = true } }, ForceRoles = {} }
hookAdd("GRM_FactionRoleKeyRenamed", "access", function(faction, oldKey, newKey)
    for _, field in ipairs({ "ManageRoles", "WarrantRoles", "ForceRoles" }) do
        local bucket = ACCESS[field] and ACCESS[field][faction]
        if bucket and bucket[oldKey] ~= nil then bucket[newKey] = bucket[oldKey] bucket[oldKey] = nil end
    end
end)

local DOORS = { doors = { d1 = { roles = { "police|officer", "police|cadet" } }, d2 = { roles = { "medic|doc" } } }, saves = 0 }
hookAdd("GRM_FactionRoleKeyRenamed", "doors", function(faction, oldKey, newKey)
    local from, to = faction .. "|" .. oldKey, faction .. "|" .. newKey
    local changed = 0
    for _, rec in pairs(DOORS.doors) do
        for i, v in ipairs(rec.roles or {}) do if v == from then rec.roles[i] = to changed = changed + 1 end end
    end
    if changed > 0 then DOORS.saves = DOORS.saves + 1 end
end)

print("\n=== 1. ОТКАЗЫ ===")
ok(select(1, setRoleKey("police", "nope", "x")) == false, "неизвестная должность не переименовывается")
ok(select(1, setRoleKey("police", "officer", "")) == false, "пустой ключ отклоняется")
ok(select(1, setRoleKey("police", "officer", "cadet")) == false, "занятый ключ отклоняется")
ok(select(1, setRoleKey("police", "officer", "officer")) == true, "тот же ключ — не ошибка, но и не правка")

print("\n=== 2. ПЕРЕИМЕНОВАНИЕ ===")
local okRen, msg = setRoleKey("police", "officer", "patrol_officer")
ok(okRen, "ключ должности меняется", msg)
ok(hasValue(Factions.police.Roles, "patrol_officer") and not hasValue(Factions.police.Roles, "officer"),
    "список должностей обновлён")
ok(Factions.police.RoleDisplayNames.patrol_officer == "Офицер" and Factions.police.RoleDisplayNames.officer == nil,
    "публичное название переехало на новый ключ")
ok(Factions.police.Members["7656:char1"].Role == "patrol_officer"
    and Factions.police.Members["7657:char1"].Role == "patrol_officer", "сотрудники переведены")
ok(Factions.police.Members["7658:char1"].Role == "cadet", "чужие должности не тронуты")
ok(Factions.police.PersonnelArchive["7659:char1"].Role == "patrol_officer", "архив кадров тоже переведён")
ok(Factions.police.RoleModels.patrol_officer ~= nil and Factions.police.RoleModels.officer == nil, "модели формы переехали")
ok(Factions.police.RoleWeapons.patrol_officer ~= nil and Factions.police.RoleWeapons.officer == nil, "оружие переехало")
ok(hasValue(Factions.police.IncassoSettings.Roles, "patrol_officer"), "список инкассации обновлён")
ok(hasValue(Factions.police.MaskDepartments[1].Roles, "patrol_officer"), "маскировка обновлена")
ok(hasValue(Factions.police.Subdepartments.swat.roles, "patrol_officer"), "списки подотдела обновлены")
ok(tostring(msg):find("сотрудников переведено: 2") ~= nil, "в ответе видно, сколько людей переведено", msg)

print("\n=== 3. ВНЕШНИЕ МОДУЛИ ПО ХУКУ ===")
ok(PERMS.Data.police.roles.patrol_officer ~= nil and PERMS.Data.police.roles.officer == nil, "права должности перенесены")
ok(PERMS.saves == 1, "права сохранены один раз")
ok(ACCESS.ManageRoles.police.patrol_officer == true and ACCESS.ManageRoles.police.officer == nil,
    "галочки доступа к дверям перенесены")
ok(ACCESS.WarrantRoles.police.chief == true, "чужие галочки не тронуты")
ok(DOORS.doors.d1.roles[1] == "police|patrol_officer" and DOORS.doors.d1.roles[2] == "police|cadet",
    "строки доступа дверей переписаны точечно")
ok(DOORS.doors.d2.roles[1] == "medic|doc", "двери другой фракции не тронуты")
ok(DOORS.saves == 1, "двери сохранены один раз")

print("\n=== 4. ЛИДЕРСКАЯ ДОЛЖНОСТЬ ===")
local okChief = setRoleKey("police", "chief", "commissioner")
ok(okChief and Factions.police.LeaderRoleName == "commissioner", "ключ лидерской должности тянет за собой LeaderRoleName")
ok(hasValue(Factions.police.IncassoSettings.Roles, "commissioner"), "инкассация лидера обновлена")

print(("\nROLE KEY RUNTIME: %d/%d, провалов: %d"):format(total - fails, total, fails))
if fails > 0 then os.exit(1) end
