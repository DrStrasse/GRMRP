--[[--------------------------------------------------------------------
    sim_dept_tags — заказ владельца 19.08:
      • меню /factions шире (кнопки разделов не влезали);
      • отделы и подотделы работают и синхронизируются целиком;
      • у отдела и подотдела есть ТЕГ, и он применяется в /fr, /frb,
        /dep, /d, /depb, /db и в шапке над игроком;
      • принадлежность игрока к отделу/подотделу висит на нём NW-строками.

    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_dept_tags.lua
----------------------------------------------------------------------]]
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end
local function has(s, n) return s:find(n, 1, true) ~= nil end

local fac = read("lua/autorun/sh_factions.lua")
local ui  = read("lua/autorun/client/cl_grm_factions_unified_ui.lua")

print("\n=== 1. ХРАНЕНИЕ И НОРМАЛИЗАЦИЯ ТЕГОВ ===")
ok(has(fac, "f.DepartmentTags=istable(f.DepartmentTags)and f.DepartmentTags or{}"), "у фракции есть карта тегов отделов")
ok(has(fac, "f.DepartmentTags[tagKey]=nil"), "тег удалённого отдела вычищается")
ok(has(fac, "sub.tag = factionTrim(sub.tag, 24)"), "тег подотдела нормализуется при загрузке")
ok(has(fac, "function GRM.Factions.DepartmentTag"), "есть общий резолвер тега отдела")
ok(has(fac, "function GRM.Factions.SubdepartmentTag"), "есть общий резолвер тега подотдела")
ok(has(fac, "function GRM.Factions.ChannelTag"), "есть сборщик шапки канала «фракция | отдел | подотдел»")

print("\n=== 2. РЕДАКТИРОВАНИЕ ===")
ok(has(fac, "local function setDepartmentTag"), "серверная функция смены тега отдела")
ok(has(fac, "local function setSubdepartmentTag"), "серверная функция смены тега подотдела")
ok(has(fac, 'action == "setDepartmentTag"'), "действие setDepartmentTag зарегистрировано")
ok(has(fac, 'action == "setSubdepartmentTag"'), "действие setSubdepartmentTag зарегистрировано")
ok(has(ui, 'sendAction("setDepartmentTag"'), "кнопка тега отдела в /factions")
ok(has(ui, 'sendAction("setSubdepartmentTag"'), "кнопка тега подотдела в /factions")

print("\n=== 3. СИНХРОНИЗАЦИЯ ===")
ok(has(fac, "DepartmentTags   = f.DepartmentTags"), "теги отделов уходят клиенту в снимке")
ok(has(fac, "Subdepartments   = f.Subdepartments"), "подотделы уходят клиенту целиком (с тегами)")
ok(has(fac, "Subdepartment=tostring(rec.Subdepartment or rec.Subdept"), "подотдел сотрудника есть в синке состава")
ok(has(fac, 'ply:SetNWString("GRM_Subdepartment", subdept)'), "подотдел висит на игроке NW-строкой")
ok(has(fac, 'ply:SetNWString("GRM_DepartmentTag"'), "тег отдела висит на игроке")
ok(has(fac, 'ply:SetNWString("GRM_SubdepartmentTag"'), "тег подотдела висит на игроке")
ok(has(fac, 'ply:SetNWString("GRM_ChannelTag"'), "готовая шапка канала висит на игроке")
ok(has(fac, "local fname, role, tag, col, dep, dept, subdept = getPlayerFactionData(ply)"),
    "резолвер данных игрока отдаёт и подотдел")

print("\n=== 4. КАНАЛЫ /fr /frb /dep /d /depb /db ===")
local radio = fac:match("net%.Receive%(NET_RADIO,.-end%)") or ""
local radiob = fac:match("net%.Receive%(NET_RADIOB,.-end%)") or ""
ok(has(radio, "GRM.Factions.ChannelTag("), "/fr печатает теги отдела и подотдела")
ok(has(radiob, "GRM.Factions.ChannelTag("), "/frb печатает теги отдела и подотдела")
ok(select(2, fac:gsub("local displayTag=GRM%.Factions%.AppendCID%(GRM%.Factions%.ChannelTag%(", "")) == 2,
    "/dep и /depb (/d, /db) собирают шапку тем же сборщиком (+ номер персонажа)")
ok(has(fac, 'return table.concat(parts," | ")'), "уровни склеиваются одной строкой через | ")
ok(has(fac, "local dTag=GRM.Factions.DepartmentTag(f,departmentKey);if dTag~=\"\"then"),
    "уровень без тега просто пропускается")

print("\n=== 4.1 ЦЕЛОСТНОСТЬ ОТДЕЛ ↔ ПОДОТДЕЛ ===")
ok(has(fac, 'f.Members[key].Subdepartment = ""'), "перевод в другой отдел снимает чужой подотдел")
ok(has(fac, "if parent and parent ~= \"\" and f.Members[key].Department ~= parent then"),
    "назначение подотдела подтягивает родительский отдел")

print("\n=== 5. ШАПКА НАД ИГРОКОМ ===")
-- Пятым аргументом идёт должность (ось v5): в шапке видно и её тег.
ok(has(fac, "local full = GRM.Factions.ChannelTag(fdata, rec.Department, rec.Subdepartment, tag, rec.Position)"),
    "HUD над игроком берёт теги отдела, подотдела и должности")
ok(has(fac, 'local nwTag = ply:GetNWString("GRM_ChannelTag", "")'),
    "при публичном синке шапка берётся с NW-строки игрока")

print("\n=== 6. ОКНО /factions ===")
ok(has(ui, "math.Clamp(ScrW() * 0.95, 1280, 1920)"), "окно стало шире (до 1920)")
ok(has(ui, "math.Clamp(ScrH() * 0.92, 760, 1120)"), "окно стало выше (до 1120)")
ok(not has(ui, "dBtnAddSub:SetPos(right:GetWide()"), "кнопки отдела больше не ставятся абсолютом по ширине панели")
ok(has(ui, 'dBtnRename:Dock(RIGHT)') and has(ui, 'sBtnTag:Dock(RIGHT)'),
    "кнопки отдела и подотдела докнуты вправо — не уезжают за край")
ok(has(ui, 'тег не задан'), "в структуре видно, задан ли тег")

print("\n=== 7. СИСТЕМНЫЙ КЛЮЧ ДОЛЖНОСТИ ===")
local perms = read("lua/autorun/sh_grm_faction_perms.lua")
local dacc  = read("lua/autorun/sh_grm_doors_access.lua")
local doors = read("lua/autorun/sh_grm_doors.lua")
ok(has(fac, "local function setRoleKey"), "ключ должности можно переименовать")
ok(has(fac, 'action == "setRoleKey"'), "действие setRoleKey зарегистрировано")
ok(has(ui, 'sendAction("setRoleKey"'), "кнопка «Ключ» в разделе «Структура»")
ok(has(fac, 'rec.Role == oldKey then rec.Role = newKey'), "сотрудники переводятся на новый ключ")
ok(has(fac, 'if f.LeaderRoleName == oldKey then f.LeaderRoleName = newKey end'), "лидерская должность не отваливается")
ok(has(fac, '"RoleModels", "RoleWeapons", "RoleVehicles"'), "форма, оружие и транспорт роли переезжают")
ok(has(fac, 'renameInArray(f.IncassoSettings.Roles)'), "список инкассации обновляется")
ok(has(fac, 'hook.Run("GRM_FactionRoleKeyRenamed"'), "внешние модули узнают о смене ключа хуком")
ok(has(perms, '"GRM_FactionPerms_RoleKey"'), "права фракции переносятся на новый ключ")
ok(has(dacc, '"GRM_DoorsAccess_RoleKey"'), "галочки доступа к дверям переносятся")
ok(has(doors, '"GRM_Doors_RoleKey"'), "строки «фракция|ранг» в дверях переписываются")

print(("\nDEPT TAGS: %d/%d, провалов: %d"):format(total - fails, total, fails))
if fails > 0 then os.exit(1) end
