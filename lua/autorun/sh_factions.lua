--[[--------------------------------------------------------------------
    Единая система фракций + волна департамента + админ-меню
    ВЕРСИЯ v3.2 — Обновлённый UI, маскировка удалена (FIXED)
    + Чат-команда /factions для суперадмина/лидера
--------------------------------------------------------------------]]

if SERVER then
    AddCSLuaFile()
    AddCSLuaFile("autorun/client/cl_grm_factions_unified_ui.lua")
end

local NET_GET_DATA            = "Factions_GetData"
local NET_SEND_DATA           = "Factions_SendData"
local NET_SYNC_ALL            = "Factions_SyncAll"
local NET_SYNC_DELTA          = "Factions_SyncDelta"   -- дельта: только изменившиеся организации
local NET_ACTION              = "Factions_Action"
local NET_ACTION_RESULT       = "Factions_ActionResult"
local NET_JOIN                = "Factions_Join"
local NET_DECLINE             = "Factions_Decline"
local NET_LEAVE               = "Factions_Leave"
local NET_RADIO               = "Factions_Radio"
local NET_RADIO_MSG           = "Factions_RadioMessage"
local NET_RADIOB              = "Factions_RadioOOC"        -- /frb: рация фракции, нон-РП
local NET_RADIOB_MSG          = "Factions_RadioOOCMessage"
local NET_OPEN_ADMIN          = "Factions_OpenAdminMenu"
local NET_OPEN_LEADER         = "Factions_OpenLeaderMenu"
local NET_DEP                  = "Factions_Dep"
local NET_DEPB                 = "Factions_Depb"
local NET_CHARACTER_CHOICES    = "Factions_CharacterChoices"
local NET_DEP_MSG             = "Factions_DepMsg"
local NET_DEPB_MSG            = "Factions_DepbMsg"
local NET_INVITE_OPEN         = "Factions_InviteOpenV2"
local NET_INVITE_ACTION       = "Factions_InviteActionV2"

GRM=GRM or{};GRM.Factions=GRM.Factions or{}
local function factionTrim(value,maxLen)local s=string.Trim(tostring(value or""));return string.sub(s,1,tonumber(maxLen)or 96)end
function GRM.Factions.DisplayName(value,fallback)
    if istable(value)then local d=factionTrim(value.DisplayName,96);return d~=""and d or tostring(fallback or"")end
    local registration=tostring(value or"");local source=(istable(Factions)and Factions[registration])or(istable(FactionsData)and FactionsData[registration]);local d=istable(source)and factionTrim(source.DisplayName,96)or"";return d~=""and d or registration
end
function GRM.Factions.RegistrationName(value)if isstring(value)then return value end;for name,f in pairs(Factions or FactionsData or{})do if f==value then return name end end;return""end
function GRM.Factions.PlayerDisplayName(ply)if not IsValid(ply)then return""end;local d=ply:GetNWString("GRM_FactionDisplay","");if d~=""then return d end;return GRM.Factions.DisplayName(ply:GetNWString("GRM_Faction",""))end
function GRM.Factions.DepartmentDisplayName(factionValue,departmentKey)
    local f=isstring(factionValue)and((Factions and Factions[factionValue])or(FactionsData and FactionsData[factionValue]))or factionValue;local key=tostring(departmentKey or"");local names=istable(f)and f.DepartmentDisplayNames or nil;local display=names and factionTrim(names[key],96)or"";return display~=""and display or key
end
--[[ ТЕГИ ОТДЕЛОВ И ПОДОТДЕЛОВ (заказ владельца 19.08).
     У фракции всегда был тег (f.Tag), у подотдела — поле tag, у отдела тега не
     было вовсе. Теперь тег есть у всех трёх уровней и служебные каналы
     (/fr, /frb, /dep, /d, /depb, /db) печатают их одной шапкой:
        [ПД | СВАТ | 1-й Взвод]
     Если тег уровня не задан — уровень просто пропускается. ]]
function GRM.Factions.DepartmentTag(factionValue,departmentKey)
    local f=isstring(factionValue)and((Factions and Factions[factionValue])or(FactionsData and FactionsData[factionValue]))or factionValue;local key=tostring(departmentKey or"");if key==""then return""end
    local tags=istable(f)and f.DepartmentTags or nil;return tags and factionTrim(tags[key],24)or""
end
function GRM.Factions.SubdepartmentTag(factionValue,subdeptKey)
    local f=isstring(factionValue)and((Factions and Factions[factionValue])or(FactionsData and FactionsData[factionValue]))or factionValue;local key=tostring(subdeptKey or"");if key==""then return""end
    local subs=istable(f)and f.Subdepartments or nil;local sub=subs and subs[key];return istable(sub)and factionTrim(sub.tag,24)or""
end
--[[ Тег должности (ось v5). Пустой, если должности нет или тег не задан. ]]
function GRM.Factions.PositionTag(factionValue,positionID)
    local key=tostring(positionID or "");if key==""then return""end
    if not(GRM.Positions and GRM.Positions.Get)then return""end
    local f=isstring(factionValue)and((Factions and Factions[factionValue])or(FactionsData and FactionsData[factionValue]))or factionValue
    local pos=GRM.Positions.Get(f or factionValue,key)
    return istable(pos)and factionTrim(pos.tag,24)or""
end
--[[ Шапка служебного канала: тег фракции + отдела + подотдела + должности.
     Пятый аргумент необязательный, поэтому старые вызовы работают как были.
     В эфире сразу видно, что говорит начальник, а не рядовой. ]]
function GRM.Factions.ChannelTag(factionValue,departmentKey,subdeptKey,baseTag,positionID)
    local f=isstring(factionValue)and((Factions and Factions[factionValue])or(FactionsData and FactionsData[factionValue]))or factionValue
    local base=factionTrim(baseTag,64)
    if base==""then base=factionTrim(istable(f)and f.Tag or"",24)end
    if base==""then base=GRM.Factions.DisplayName(isstring(factionValue)and factionValue or GRM.Factions.RegistrationName(factionValue))end
    local parts={base}
    local dTag=GRM.Factions.DepartmentTag(f,departmentKey);if dTag~=""then parts[#parts+1]=dTag end
    local sTag=GRM.Factions.SubdepartmentTag(f,subdeptKey);if sTag~=""then parts[#parts+1]=sTag end
    local pTag=GRM.Factions.PositionTag(f,positionID);if pTag~=""then parts[#parts+1]=pTag end
    return table.concat(parts," | ")
end
function GRM.Factions.RoleDisplayName(factionValue,roleKey)
    local f=isstring(factionValue)and((Factions and Factions[factionValue])or(FactionsData and FactionsData[factionValue]))or factionValue;local key=tostring(roleKey or"");local names=istable(f)and f.RoleDisplayNames or nil;local display=names and factionTrim(names[key],96)or"";return display~=""and display or (key~="" and key or "Участник")
end
function GRM.Factions.ResolveRoleKey(factionValue,roleInput)
    local f=isstring(factionValue)and((Factions and Factions[factionValue])or(FactionsData and FactionsData[factionValue]))or factionValue;local input=tostring(roleInput or"");if not istable(f)then return input end
    if f.RoleDisplayNames and f.RoleDisplayNames[input] then return input end
    if istable(f.RoleDisplayNames) then for k,v in pairs(f.RoleDisplayNames) do if tostring(v)==input then return k end end end
    for _,r in ipairs(f.Roles or{}) do if r==input then return r end end
    return input
end
function GRM.Factions.SubdepartmentDisplayName(factionValue,subdeptKey)
    local f=isstring(factionValue)and((Factions and Factions[factionValue])or(FactionsData and FactionsData[factionValue]))or factionValue;local key=tostring(subdeptKey or"");if key==""then return""end;local names=istable(f)and f.SubdepartmentDisplayNames or nil;local display=names and factionTrim(names[key],96)or"";if display~=""then return display end;if istable(f)and istable(f.Subdepartments)and f.Subdepartments[key]then local d=factionTrim(f.Subdepartments[key].name or f.Subdepartments[key].displayName,96);if d~=""then return d end end;return key
end
function GRM.Factions.ResolveSubdepartmentKey(factionValue,subInput)
    local f=isstring(factionValue)and((Factions and Factions[factionValue])or(FactionsData and FactionsData[factionValue]))or factionValue;local input=tostring(subInput or"");if input==""or not istable(f)then return input end;if f.Subdepartments and f.Subdepartments[input]then return input end;if f.SubdepartmentDisplayNames and f.SubdepartmentDisplayNames[input]then return input end;if istable(f.SubdepartmentDisplayNames)then for k,v in pairs(f.SubdepartmentDisplayNames)do if tostring(v)==input then return k end end end;if istable(f.Subdepartments)then for k,sub in pairs(f.Subdepartments)do if istable(sub)and(sub.name==input or sub.displayName==input)then return k end end end;return input
end
function GRM.Factions.GetSubdepartments(factionValue,parentDeptId)
    local f=isstring(factionValue)and((Factions and Factions[factionValue])or(FactionsData and FactionsData[factionValue]))or factionValue;local out={};if not(istable(f)and istable(f.Subdepartments))then return out end;parentDeptId=parentDeptId and tostring(parentDeptId)or nil
    for k,sub in pairs(f.Subdepartments)do if istable(sub)then if not parentDeptId or tostring(sub.parentDept or"")==parentDeptId then out[#out+1]={id=k,name=tostring(sub.name or(f.SubdepartmentDisplayNames and f.SubdepartmentDisplayNames[k])or k),parentDept=tostring(sub.parentDept or""),tag=tostring(sub.tag or""),quota=tonumber(sub.quota)or 0,head=tostring(sub.head or""),models=istable(sub.models)and sub.models or{},weapons=istable(sub.weapons)and sub.weapons or{},vehicles=istable(sub.vehicles)and sub.vehicles or{}}end end end
    table.sort(out,function(a,b)return a.name:lower()<b.name:lower()end);return out
end

--[[ Номер персонажа в шапке служебного канала (решение владельца 19.08:
     «CID в служебных каналах»). В обычный IC-чат номер НЕ идёт — это прямой
     метагейм. Управляется конваром grm_chat_show_cid (1 по умолчанию). ]]
if SERVER and not ConVarExists("grm_chat_show_cid") then
    CreateConVar("grm_chat_show_cid", "1", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED),
        "1 — показывать номер персонажа (ГР-####) в шапке служебных каналов")
end
function GRM.Factions.AppendCID(tag, ply)
    local cv = GetConVar and GetConVar("grm_chat_show_cid")
    if cv and not cv:GetBool() then return tag end
    if not (GRM.Registry and GRM.Registry.CID) then return tag end
    local cid = GRM.Registry.CID(ply)
    if cid == "" then return tag end
    return tostring(tag or "") .. " | " .. cid
end

-- ============================================================
-- SHARED ЛИДЕРСКИЙ ХЕЛПЕР (изоляция слотов персонажей)
-- ============================================================
local function isCharacterLeaderOfFaction(ply, f)
    if not IsValid(ply) or not istable(f) then return false end
    local ldr = tostring(f.Leader or "")
    local charKey = (GRM.Identity and isfunction(GRM.Identity.CharacterKey) and GRM.Identity.CharacterKey(ply)) or ""
    local sid = (ply.SteamID and ply:SteamID()) or ""
    local sid64 = (ply.SteamID64 and ply:SteamID64()) or ""

    -- 1. Если активна система мультиперсонажей (CharacterKey: sid64:charN)
    if charKey ~= "" then
        -- Прямое точное совпадение ключа персонажа с лидером фракции
        if ldr ~= "" and ldr == charKey then return true end
        -- Проверка по списку участников: активный персонаж имеет роль лидера
        if istable(f.Members) then
            local mem = rawget(f.Members, charKey) or f.Members[charKey]
            if istable(mem) and (mem.Role == f.LeaderRoleName or mem.Role == "Лидер") then
                return true
            end
        end
        -- Если лидер сохранён как старый/немигрированный SteamID/SteamID64:
        -- лидерство даётся ТОЛЬКО если данный персонаж charKey числится в f.Members с ролью лидера!
        if ldr ~= "" and (ldr == sid or ldr == sid64) then
            if istable(f.Members) then
                local mem = rawget(f.Members, charKey) or f.Members[charKey]
                if istable(mem) and (mem.Role == f.LeaderRoleName or mem.Role == "Лидер") then
                    return true
                end
            end
        end
        return false
    end

    -- 2. Режим одного аккаунта (без мультиперсонажей)
    if ldr ~= "" and (ldr == sid or (sid64 ~= "" and ldr == sid64)) then return true end
    if istable(f.Members) then
        local mem = rawget(f.Members, sid) or (sid64 ~= "" and rawget(f.Members, sid64)) or f.Members[sid] or (sid64 ~= "" and f.Members[sid64])
        if istable(mem) and (mem.Role == f.LeaderRoleName or mem.Role == "Лидер") then
            return true
        end
    end
    return false
end

-- ============================================================
-- SERVER
-- ============================================================
if SERVER then
    util.AddNetworkString(NET_GET_DATA)
    util.AddNetworkString(NET_SEND_DATA)
    util.AddNetworkString(NET_SYNC_ALL)
    util.AddNetworkString(NET_SYNC_DELTA)
    util.AddNetworkString(NET_ACTION)
    util.AddNetworkString(NET_ACTION_RESULT)
    util.AddNetworkString(NET_JOIN)
    util.AddNetworkString(NET_DECLINE)
    util.AddNetworkString(NET_LEAVE)
    util.AddNetworkString(NET_RADIO)
    util.AddNetworkString(NET_RADIO_MSG)
    util.AddNetworkString(NET_RADIOB)
    util.AddNetworkString(NET_RADIOB_MSG)
    util.AddNetworkString(NET_OPEN_ADMIN)
    util.AddNetworkString(NET_OPEN_LEADER)
    util.AddNetworkString(NET_DEP)
    util.AddNetworkString(NET_DEPB)
    util.AddNetworkString(NET_CHARACTER_CHOICES)
    util.AddNetworkString(NET_DEP_MSG)
    util.AddNetworkString(NET_DEPB_MSG)
    util.AddNetworkString(NET_INVITE_OPEN)
    util.AddNetworkString(NET_INVITE_ACTION)

    local FACTIONS_FILE = "factions.json"
    local INVITES_FILE  = "invites.json"
    Factions      = nil
    Invites       = nil

    local function safeJSONToTable(data)
        local ok, tbl = pcall(util.JSONToTable, data or "", false, true)
        if ok and istable(tbl) then return tbl end
        return {}
    end

    local function loadFactions()
        if not file.Exists(FACTIONS_FILE, "DATA") then return {} end
        local data = file.Read(FACTIONS_FILE, "DATA")
        if not data or data == "" then return {} end
        return safeJSONToTable(data)
    end

    local function saveFactions(tbl)
        file.Write(FACTIONS_FILE, util.TableToJSON(tbl, true))
    end

    local function loadInvites()
        if not file.Exists(INVITES_FILE, "DATA") then return {} end
        local data = file.Read(INVITES_FILE, "DATA")
        if not data or data == "" then return {} end
        return safeJSONToTable(data)
    end

    local function saveInvites(tbl)
        file.Write(INVITES_FILE, util.TableToJSON(tbl, true))
    end

    -- Character migration: faction membership is stored by CharacterKey.
    -- SteamID/SteamID64 remain readable as compatibility aliases only.
    local function canonicalMemberKey(value)
        if IsValid(value) and value.IsPlayer and value:IsPlayer() then
            return (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(value)) or (value:SteamID64() .. ":char1")
        end
        local raw = tostring(value or "")
        if raw:match(":char[1-3]$") then return raw end
        if raw:match("^%d+$") then return raw .. ":char1" end
        -- A raw SteamID string may be an offline/legacy target. Keep it
        -- readable here; online callers pass the Player object and therefore
        -- resolve to the active CharacterKey. Disk migration below converts
        -- legacy SteamID records deterministically.
        return raw
    end

    local function persistedMemberKey(value)
        local raw = tostring(value or "")
        if raw:match(":char[1-3]$") then return raw end
        if raw:match("^%d+$") then return raw .. ":char1" end
        if util.SteamIDTo64 then
            local s64 = util.SteamIDTo64(raw)
            if s64 and s64 ~= "0" then return tostring(s64) .. ":char1" end
        end
        return raw
    end

    local function legacyAccountKey(value)
        local raw = tostring(value or "")
        if raw:match(":char[1-3]$") then return raw:gsub(":char[1-3]$", "") end
        return raw
    end

    local function installMemberAliases(members)
        if not istable(members) then return end
        local oldIndex = getmetatable(members) and getmetatable(members).__index
        setmetatable(members, { __index = function(t, key)
            if oldIndex then
                local old = type(oldIndex) == "function" and oldIndex(t, key) or oldIndex[key]
                if old ~= nil then return old end
            end
            local ck = persistedMemberKey(key)
            return rawget(t, ck)
        end })
    end

    local function migrateFactionMembers()
        local changed = false
        for _, f in pairs(Factions or {}) do
            if istable(f) then
                f.Members = istable(f.Members) and f.Members or {}
                local moved = {}
                for key, rec in pairs(f.Members) do
                    local ck = persistedMemberKey(key)
                    if ck ~= key then
                        if not rawget(f.Members, ck) then moved[ck] = rec end
                        f.Members[key] = nil
                        changed = true
                    end
                end
                for ck, rec in pairs(moved) do f.Members[ck] = rec end
                if f.Leader then
                    local leaderKey = canonicalMemberKey(f.Leader)
                    if leaderKey ~= f.Leader then f.Leader = leaderKey changed = true end
                end
                installMemberAliases(f.Members)
            end
        end
        return changed
    end

    local function memberKey(value)
        if IsValid(value) and value.IsPlayer and value:IsPlayer() then
            return canonicalMemberKey(value)
        end
        local raw = tostring(value or "")
        if player and player.GetAll then
            for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                if IsValid(ply) and (ply:SteamID() == raw or ply:SteamID64() == raw) then
                    return canonicalMemberKey(ply)
                end
            end
        end
        return canonicalMemberKey(raw)
    end

    local function ensureDefaults(f,registrationName)
        if not f or type(f)~="table"then return false end;local changed=false
        local display=factionTrim(f.DisplayName,96);if display==""then display=factionTrim(registrationName,96)end;if f.DisplayName~=display then f.DisplayName=display;changed=true end

        f.Members     = istable(f.Members)     and f.Members     or {}
        f.Roles       = istable(f.Roles)       and f.Roles       or {}
        f.RoleDisplayNames = istable(f.RoleDisplayNames) and f.RoleDisplayNames or {}
        for _,roleKey in ipairs(f.Roles)do local public=factionTrim(f.RoleDisplayNames[roleKey],96);if public==""then f.RoleDisplayNames[roleKey]=roleKey;changed=true end end
        f.Departments = istable(f.Departments) and f.Departments or {}
        f.DepartmentDisplayNames=istable(f.DepartmentDisplayNames)and f.DepartmentDisplayNames or{}
        f.DepartmentTags=istable(f.DepartmentTags)and f.DepartmentTags or{}
        for _,departmentKey in ipairs(f.Departments)do local public=factionTrim(f.DepartmentDisplayNames[departmentKey],96);if public==""then f.DepartmentDisplayNames[departmentKey]=departmentKey;changed=true end
            local dtag=factionTrim(f.DepartmentTags[departmentKey],24);if f.DepartmentTags[departmentKey]~=dtag then f.DepartmentTags[departmentKey]=dtag;changed=true end end
        for tagKey in pairs(f.DepartmentTags)do if not table.HasValue(f.Departments,tagKey)then f.DepartmentTags[tagKey]=nil;changed=true end end
        f.Subdepartments = istable(f.Subdepartments) and f.Subdepartments or {}
        f.SubdepartmentDisplayNames = istable(f.SubdepartmentDisplayNames) and f.SubdepartmentDisplayNames or {}
        for subKey, sub in pairs(f.Subdepartments) do
            if istable(sub) then
                local public = factionTrim(sub.name or f.SubdepartmentDisplayNames[subKey] or subKey, 96)
                if public == "" then public = subKey end
                sub.id = subKey
                sub.name = public
                sub.tag = factionTrim(sub.tag, 24)
                sub.parentDept = tostring(sub.parentDept or "")
                f.SubdepartmentDisplayNames[subKey] = public
            end
        end
        f.PersonnelArchive=istable(f.PersonnelArchive)and f.PersonnelArchive or{}

        if type(f.LeaderRoleName) ~= "string" or f.LeaderRoleName == "" then
            f.LeaderRoleName = "Лидер"
        end
        local leaderRoleName = f.LeaderRoleName
        if not table.HasValue(f.Roles, leaderRoleName) then
            table.insert(f.Roles, 1, leaderRoleName)
        end

        -- Убрано: автоматическое добавление "Участник" при каждом ensureDefaults
        -- вызывало баг — при переименовании ранга создавался дубликат.
        -- Роль по умолчанию теперь определяется через getDefaultMemberRole()
        --
        -- Код 108 (заказ владельца): «Основной» отдел больше НЕ воскресает
        -- сам. Раньше этот блок вставлял его при КАЖДОМ ensureDefaults, а он
        -- вызывается из каждого действия и каждой рассылки — стоило админу
        -- удалить «Основной», как очередной sync тут же создавал его заново.
        -- Отдел по умолчанию теперь — getDefaultDepartment() (первый реальный
        -- отдел фракции, литерал «Основной» — лишь крайний фолбэк).

        if type(f.Tag) ~= "string" then f.Tag = "" end
        if not istable(f.Color) then f.Color = { r = 255, g = 200, b = 50 } end
        f.Color.r = tonumber(f.Color.r) or 255
        f.Color.g = tonumber(f.Color.g) or 200
        f.Color.b = tonumber(f.Color.b) or 50
        if f.DepAccess == nil then f.DepAccess = false end
        -- Код 127: доступы к государственным услугам, счетам и дипломам
        if f.ServiceAccess == nil then f.ServiceAccess = false end
        if f.InvoiceAccess == nil then f.InvoiceAccess = false end
        if f.DiplomaAccess == nil then f.DiplomaAccess = false end

        if f.Leader and not f.Members[f.Leader] then
            -- Если лидер сохранён как старый SteamID64 или не найден напрямую,
            -- ищем реального персонажа с ролью лидера в f.Members
            local found = nil
            local rawLdr = tostring(f.Leader or "")
            local s64 = (util.SteamIDTo64 and util.SteamIDTo64(rawLdr)) or rawLdr
            for mKey, mRec in pairs(f.Members) do
                if isstring(mKey) and (mKey:find(s64, 1, true) or (rawLdr ~= "" and mKey:find(rawLdr, 1, true))) then
                    if istable(mRec) and (mRec.Role == leaderRoleName or mRec.Role == "Лидер") then
                        found = mKey
                        break
                    end
                end
            end
            if not found then
                for mKey, mRec in pairs(f.Members) do
                    if istable(mRec) and (mRec.Role == leaderRoleName or mRec.Role == "Лидер") then
                        found = mKey
                        break
                    end
                end
            end
            f.Leader = found
        end
        if f.Leader and f.Members[f.Leader] then
            f.Members[f.Leader].Role = f.LeaderRoleName
        end

        -- Код 126 (Инкассация): настройки допуска фракции к инкассации
        if not istable(f.IncassoSettings) then
            f.IncassoSettings = { Enabled = false, Roles = {}, Vehicles = {} }
        end
        local inc = f.IncassoSettings
        inc.Enabled = inc.Enabled == true
        inc.Roles    = istable(inc.Roles)    and inc.Roles    or {}
        inc.Vehicles = istable(inc.Vehicles) and inc.Vehicles or {}
        return changed
    end

    -- Отдел по умолчанию для новых участников: первый реальный отдел или пустая строка
    local function getDefaultDepartment(f)
        ensureDefaults(f)
        return (istable(f.Departments) and f.Departments[1]) or ""
    end

    -- Возвращает роль по умолчанию для новых участников:
    -- последний ранг в списке (не лидерский), либо "Участник" если ролей нет
    local function getDefaultMemberRole(f)
        ensureDefaults(f)
        local roles = f.Roles or {}
        local leaderRole = f.LeaderRoleName or "Лидер"
        -- Ищем последний не-лидерский ранг
        for i = #roles, 1, -1 do
            if roles[i] ~= leaderRole then
                return roles[i]
            end
        end
        -- Если все роли — лидерские (маловероятно), добавляем "Участник"
        table.insert(roles, "Участник")
        saveFactions(Factions)
        return "Участник"
    end

    local function ensureAllDefaults()
        local changed=false;for name,f in pairs(Factions)do if type(f)=="table"and ensureDefaults(f,name)then changed=true end end;return changed
    end

    Factions=loadFactions();Invites=loadInvites();local factionMigrationChanged=migrateFactionMembers();local factionNameMigrationChanged=ensureAllDefaults()
    if factionMigrationChanged or factionNameMigrationChanged then saveFactions(Factions)end

    local function characterDisplay(key)
        key = tostring(key or "")
        local p = GRM.Identity and GRM.Identity.ResolveCharacter and GRM.Identity.ResolveCharacter(key) or nil
        if IsValid(p) then
            local n = p:GetNWString("GRM_RPName", "")
            return n ~= "" and n or p:Nick(), true, p:Nick()
        end
        local account, slot = key:match("^(.-):(char[1-3])$")
        local rec = account and GRM.Char and GRM.Char.Data and GRM.Char and GRM.Char.Data[account]
        local c = rec and rec.slots and rec.slots[slot]
        return (c and c.name and c.name ~= "" and c.name or key), false, "offline"
    end

    local function buildMemberSync(f)
        local out = {}
        for key, rec in pairs(f.Members or {}) do
            if istable(rec) then
                local rp, online, steamNick = characterDisplay(key)
                local onlineP=GRM.Identity and GRM.Identity.ResolveCharacter and GRM.Identity.ResolveCharacter(key) or nil
                local onDuty=IsValid(onlineP) and GRM.FactionDuty and GRM.FactionDuty.IsOnDuty and GRM.FactionDuty.IsOnDuty(onlineP) or false
                local savedDuty=GRM.FactionDuty and GRM.FactionDuty.State and GRM.FactionDuty.State[key]
                local dutyStatus=online and (onDuty and "НА СЛУЖБЕ" or "ВНЕ СЛУЖБЫ") or (savedDuty==false and "ВЫХОДНОЙ" or "НЕ В СЕТИ")
                local location=IsValid(onlineP) and string.format("%.0f %.0f %.0f",onlineP:GetPos().x,onlineP:GetPos().y,onlineP:GetPos().z) or "—"
                out[key] = {
                    -- Номер персонажа в госреестре: по нему кадровик и /pcboard
                    -- находят человека, не зная SteamID.
                    _cid = (GRM.Registry and GRM.Registry.CID and GRM.Registry.CID(key)) or "",
                    Role=rec.Role,Department=rec.Department,Subdepartment=tostring(rec.Subdepartment or rec.Subdept or""),Position=tostring(rec.Position or""),Personnel=rec.Personnel and{joinedAt=rec.Personnel.joinedAt,status=rec.Personnel.status,probationUntil=rec.Personnel.probationUntil}or nil,
                    _characterKey = key, _rpName = rp, _online = online, _steamNick = steamNick,
                    _dutyStatus=dutyStatus, _location=location,
                }
            end
        end
        return out
    end

    local function buildCharacterChoices()
        local out = {}
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(p) and p:IsPlayer() then
                local account = p:SteamID64()
                local chars = GRM.Char and GRM.Char.Data and GRM.Char and GRM.Char.Data[account] and GRM.Char and GRM.Char.Data[account].slots or {}
                for i = 1, (GRM.Char and GRM.Char.MaxSlots or 3) do
                    local id = "char" .. i
                    local c = chars and chars[id]
                    if istable(c) and tostring(c.name or "") ~= "" then
                        local key = account .. ":" .. id
                        out[#out + 1] = {
                            key = key,
                            rpName = tostring(c.name),
                            steamNick = p:Nick(),
                            slot = id,
                            active = GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(p) == key or false,
                            faction = (function()
                                for fname, f in pairs(Factions or {}) do
                                    if istable(f) and rawget(f.Members or {}, key) then return fname end
                                end
                                return ""
                            end)(),
                        }
                    end
                end
            end
        end
        table.sort(out, function(a, b)
            return (a.rpName .. a.key):lower() < (b.rpName .. b.key):lower()
        end)
        return out
    end

    local function sendCharacterChoicesNow(ply)
        --[[ Список персонажей на большом сервере — это килобайты одним
             пакетом ВСЕМ сразу: заметный рывок у каждого клиента. Шлём
             потоком (GRM.Net.Stream): куски по кадрам, приём собирается
             на клиенте. Прямая отправка осталась запасным путём. ]]
        local payload = buildCharacterChoices()
        if GRM.Net and GRM.Net.Stream then
            GRM.Net.Stream(NET_CHARACTER_CHOICES, payload, ply, { chunk = 8192, interval = 0.05 })
            return
        end
        net.Start(NET_CHARACTER_CHOICES)
            net.WriteTable(payload)
        if ply then net.Send(ply) else net.Broadcast() end
    end

    --[[ Список персонажей строится обходом всех слотов всех игроков и уходит
         ВСЕМ. Событий, дёргающих его (вход, смена персонажа, приём в
         организацию), в пиковый момент идёт пачка — сводим в одну рассылку. ]]
    local function sendCharacterChoices(ply)
        if not ply and GRM.Perf and GRM.Perf.Coalesce then
            return GRM.Perf.Coalesce("grm_factions_char_choices", 0.5, function()
                sendCharacterChoicesNow()
            end)
        end
        return sendCharacterChoicesNow(ply)
    end

    local function buildSyncData()
        local data = {}
        for name, f in pairs(Factions) do
            if type(f) == "table" then
                ensureDefaults(f,name)
                local eco = GRM.FactionBudgetGet and tonumber(GRM.FactionBudgetGet(name)) or 0
                local card = tonumber(f.Budget) or 0
                local b = math.max(0, math.floor(math.max(eco, card)))
                local tax = (GRM.FactionTaxGet and GRM.FactionTaxGet(name))
                    or (GRM.Economy and GRM.Economy.TaxRateGet and GRM.Economy.TaxRateGet(name))
                    or 0.05
                data[name] = {
                    Leader           = f.Leader,
                    DisplayName      = f.DisplayName,
                    Roles            = f.Roles,
                    RoleDisplayNames = f.RoleDisplayNames,
                    Departments      = f.Departments,
                    DepartmentDisplayNames=f.DepartmentDisplayNames,
                    DepartmentTags   = f.DepartmentTags,
                    Subdepartments   = f.Subdepartments,
                    SubdepartmentDisplayNames=f.SubdepartmentDisplayNames,
                    Members          = buildMemberSync(f),
                    Tag              = f.Tag,
                    Color            = f.Color,
                    DepAccess        = f.DepAccess,
                    ServiceAccess    = f.ServiceAccess,
                    InvoiceAccess    = f.InvoiceAccess,
                    DiplomaAccess    = f.DiplomaAccess,
                    LeaderRoleName   = f.LeaderRoleName,
                    Budget           = b,
                    TaxRate          = tax,
                    -- v3.1.1: зеркалируем доступ-модели/оружие/госновости для
                    -- вкладки «Расширенные настройки» (синк с /models_admin,
                    -- /weapons_admin, setGNewsAccess — те же серверные поля)
                    -- Должности организации (GRM.Positions): клиенту нужны
                    -- и сами должности, и их наборы моделей/оружия.
                    Positions        = f.Positions,
                    PositionModels   = f.PositionModels,
                    PositionWeapons  = f.PositionWeapons,
                    Models           = f.Models,
                    RoleModels       = f.RoleModels,
                    DepartmentModels = f.DepartmentModels,
                    Weapons          = f.Weapons,
                    RoleWeapons      = f.RoleWeapons,
                    DepartmentWeapons= f.DepartmentWeapons,
                    GNewsAccess      = f.GNewsAccess == true,
                    IncassoSettings  = f.IncassoSettings
                }
            end
        end
        return data
    end

    local function getFactionOfLeader(ply)
        if not IsValid(ply) or not istable(Factions) then return nil end
        for name, f in pairs(Factions) do
            if type(f) == "table" then
                ensureDefaults(f)
                if isCharacterLeaderOfFaction(ply, f) then return name end
            end
        end
        return nil
    end

    local function getPlayerFactionData(plyOrKey)
        if not istable(Factions) then return nil, nil, "", {r=255,g=200,b=50}, false, "", "" end
        local ply = (isentity(plyOrKey) and IsValid(plyOrKey) and plyOrKey:IsPlayer() and plyOrKey) or nil
        local sid = ply and (ply:SteamID() or "") or (isstring(plyOrKey) and plyOrKey or "")
        local sid64 = (ply and ply.SteamID64 and ply:SteamID64()) or (util.SteamIDTo64 and util.SteamIDTo64(sid)) or ""
        local charKey = (ply and GRM.Identity and isfunction(GRM.Identity.CharacterKey) and GRM.Identity.CharacterKey(ply))
            or (isstring(plyOrKey) and plyOrKey:find(":char[1-3]$") and plyOrKey) or ""

        -- 1. Точное совпадение активного персонажа CharacterKey (rawget первым делом)
        if charKey ~= "" then
            for name, f in pairs(Factions) do
                if istable(f) and istable(f.Members) then
                    local rec = rawget(f.Members, charKey)
                    if istable(rec) then
                        return name, rec.Role or "Участник", f.Tag or "", f.Color or {r=255,g=200,b=50}, f.DepAccess == true, rec.Department or "", tostring(rec.Subdepartment or rec.Subdept or "")
                    end
                end
            end
        end

        -- 2. Если персонаж лидер фракции
        if ply then
            for name, f in pairs(Factions) do
                if istable(f) and isCharacterLeaderOfFaction(ply, f) then
                    local leaderRole = f.LeaderRoleName or "Лидер"
                    local mem = (charKey ~= "" and rawget(f.Members, charKey)) or (charKey == "" and (rawget(f.Members, sid) or (sid64 ~= "" and rawget(f.Members, sid64))))
                    local dept = istable(mem) and mem.Department or ""
                    local subdept = istable(mem) and tostring(mem.Subdepartment or mem.Subdept or "") or ""
                    return name, leaderRole, f.Tag or "", f.Color or {r=255,g=200,b=50}, f.DepAccess == true, dept, subdept
                end
            end
        end

        -- 3. Режим одиночного аккаунта (только если charKey пустой)
        if charKey == "" then
            if sid ~= "" then
                for name, f in pairs(Factions) do
                    if istable(f) and istable(f.Members) then
                        local rec = rawget(f.Members, sid)
                        if istable(rec) then
                            return name, rec.Role or "Участник", f.Tag or "", f.Color or {r=255,g=200,b=50}, f.DepAccess == true, rec.Department or "", tostring(rec.Subdepartment or rec.Subdept or "")
                        end
                    end
                end
            end
            if sid64 ~= "" then
                for name, f in pairs(Factions) do
                    if istable(f) and istable(f.Members) then
                        local rec = rawget(f.Members, sid64)
                        if istable(rec) then
                            return name, rec.Role or "Участник", f.Tag or "", f.Color or {r=255,g=200,b=50}, f.DepAccess == true, rec.Department or "", tostring(rec.Subdepartment or rec.Subdept or "")
                        end
                    end
                end
            end
        end

        return nil, nil, "", {r=255,g=200,b=50}, false, "", ""
    end

    local function getFactionOfPlayer(steamID)
        return select(1, getPlayerFactionData(steamID))
    end

    local function getFactionInfoForPlayer(steamID)
        return getPlayerFactionData(steamID)
    end

    local function syncPlayerFactionNW(ply)
        if not IsValid(ply) or not ply:IsPlayer() then return end
        local fname, role, tag, col, dep, dept, subdept = getPlayerFactionData(ply)
        fname = fname or ""
        role = role or ""
        tag = tag or ""
        dept = dept or ""
        subdept = subdept or ""

        ply:SetNWString("GRM_Faction", fname)
        ply:SetNWString("Faction",fname);ply:SetNWString("GRM_FactionDisplay",GRM.Factions.DisplayName(fname))
        ply:SetNWString("GRM_Role", role)
        ply:SetNWString("FactionRole", role)
        ply:SetNWString("GRM_FactionTag", tag)
        ply:SetNWString("FactionTag", tag)
        ply:SetNWString("GRM_Department", dept)
        ply:SetNWString("Department", dept)
        --[[ Отдел и подотдел теперь реально «применяются к игроку»: ключи,
             публичные названия и теги висят на игроке networked-строками, их
             читают HUD, служебные каналы, выдача формы и внешние модули. ]]
        local fData = fname ~= "" and Factions[fname] or nil
        ply:SetNWString("GRM_Subdepartment", subdept)
        ply:SetNWString("Subdepartment", subdept)
        ply:SetNWString("GRM_DepartmentDisplay", dept ~= "" and GRM.Factions.DepartmentDisplayName(fData or fname, dept) or "")
        ply:SetNWString("GRM_SubdepartmentDisplay", subdept ~= "" and GRM.Factions.SubdepartmentDisplayName(fData or fname, subdept) or "")
        ply:SetNWString("GRM_DepartmentTag", dept ~= "" and GRM.Factions.DepartmentTag(fData or fname, dept) or "")
        ply:SetNWString("GRM_SubdepartmentTag", subdept ~= "" and GRM.Factions.SubdepartmentTag(fData or fname, subdept) or "")
        local nwPositionID = ""
        if istable(fData) and istable(fData.Members) then
            local nwRec = GRM.Identity and GRM.Identity.FactionMember
                and GRM.Identity.FactionMember(fData, ply) or nil
            if istable(nwRec) then nwPositionID = tostring(nwRec.Position or "") end
        end
        ply:SetNWString("GRM_ChannelTag", fname ~= ""
            and GRM.Factions.ChannelTag(fData or fname, dept, subdept, tag, nwPositionID) or "")

        --[[ Должность (ось v5) тоже висит на игроке строкой: её читают права
             организаций, правила бодигрупп и служебные каналы. Берём прямо из
             состава, чтобы не менять сигнатуру getPlayerFactionData. ]]
        local positionID, positionName, positionTag = "", "", ""
        if istable(fData) and istable(fData.Members) then
            local rec = GRM.Identity and GRM.Identity.FactionMember
                and GRM.Identity.FactionMember(fData, ply) or nil
            if istable(rec) then
                positionID = tostring(rec.Position or "")
                if positionID ~= "" and GRM.Positions and GRM.Positions.Get then
                    local pos = GRM.Positions.Get(fData, positionID)
                    if pos then
                        positionName = pos.name or ""
                        positionTag = pos.tag or ""
                    else
                        positionID = ""
                    end
                end
            end
        end
        ply:SetNWString("GRM_Position", positionID)
        ply:SetNWString("GRM_PositionDisplay", positionName)
        ply:SetNWString("GRM_PositionTag", positionTag)
    end

    local function syncAllPlayersFactionNW()
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(p) then syncPlayerFactionNW(p) end
        end
    end

    -- Полная рассылка: синк NW всех игроков + сериализация всех фракций/членов
    -- + broadcast всем. Дорогая — не дёргать чаще, чем реально нужно.
    -- Контрольные суммы последнего разосланного состояния: по ним считается
    -- дельта. Полный снимок остаётся только для первого синка игроку.
    local syncHashes, publicHashes = {}, {}
    local PUBLIC_FULL = CreateConVar("grm_factions_public_full", "0",
        bit.bor(FCVAR_ARCHIVE),
        "1 — рассылать полные данные организаций всем игрокам (как раньше), 0 — только тем, кому они нужны")

    local broadcastPending = false
    local function doBroadcastFactionData()
        syncAllPlayersFactionNW()
        --[[ ДЕЛЬТА-СИНК (19.08).
             Раньше каждое изменение рассылало ПОЛНЫЙ снимок всех организаций
             всем игрокам: замер на живом сервере дал 45 620 байт одним
             пакетом Factions_SyncAll — на полном сервере это главный источник
             сетевых рывков. Теперь считаем контрольную сумму по каждой
             организации и шлём только изменившиеся, и только тем, кому они
             нужны: полностью — суперадминам и членам организации, публично
             (название, тэг, цвет) — остальным. ]]
        local data = buildSyncData()

        local changedFull, changedPublic, removed = {}, {}, {}
        local anyFull, anyPublic = false, false

        for name, row in pairs(data) do
            local ok, encoded = pcall(util.TableToJSON, row)
            local crc = ok and isstring(encoded) and util.CRC(encoded) or tostring(math.random())
            if syncHashes[name] ~= crc then
                syncHashes[name] = crc
                changedFull[name] = row
                anyFull = true

                local pub = {
                    DisplayName = row.DisplayName, Tag = row.Tag, Color = row.Color,
                    LeaderRoleName = row.LeaderRoleName, GNewsAccess = row.GNewsAccess,
                }
                local okP, encodedP = pcall(util.TableToJSON, pub)
                local crcP = okP and isstring(encodedP) and util.CRC(encodedP) or crc
                if publicHashes[name] ~= crcP then
                    publicHashes[name] = crcP
                    changedPublic[name] = pub
                    anyPublic = true
                end
            end
        end

        for name in pairs(syncHashes) do
            if not data[name] then
                syncHashes[name] = nil
                publicHashes[name] = nil
                removed[#removed + 1] = name
                anyFull, anyPublic = true, true
            end
        end

        if not anyFull and #removed == 0 then
            sendCharacterChoices()
            return
        end

        -- Полный доступ: суперадмины и члены изменившихся организаций.
        local fullTargets, publicTargets = {}, {}
        local everyoneFull = PUBLIC_FULL and PUBLIC_FULL:GetBool()

        for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(ply) then
                local wantsFull = everyoneFull or ply:IsSuperAdmin()
                if not wantsFull then
                    local own = ply:GetNWString("GRM_Faction", "")
                    if own ~= "" and changedFull[own] then wantsFull = true end
                end
                if wantsFull then fullTargets[#fullTargets + 1] = ply
                else publicTargets[#publicTargets + 1] = ply end
            end
        end

        if #fullTargets > 0 and (anyFull or #removed > 0) then
            net.Start(NET_SYNC_DELTA)
                net.WriteTable({ mode = "full", changed = changedFull, removed = removed })
            net.Send(fullTargets)
        end

        if #publicTargets > 0 and (anyPublic or #removed > 0) then
            net.Start(NET_SYNC_DELTA)
                net.WriteTable({ mode = "public", changed = changedPublic, removed = removed })
            net.Send(publicTargets)
        end

        sendCharacterChoices()
    end

    -- Коалесцируем частые вызовы (одно действие фракции тянет цепочку вызовов,
    -- а каждый приводил к полной сериализации + рассылке всем + клиентской
    -- пересборке UI) в ОДНУ рассылку за тик — убирает микрофризы.
    function broadcastFactionData()
        if broadcastPending then return end
        broadcastPending = true
        timer.Simple(0, function()
            broadcastPending = false
            doBroadcastFactionData()
        end)
    end

    hook.Add("GRM_CharacterChanged", "Factions_CharacterSync", function(ply)
        if not IsValid(ply) then return end
        timer.Simple(0, function()
            if IsValid(ply) then
                syncPlayerFactionNW(ply)
                broadcastFactionData()
            end
        end)
    end)

    -- Форвард-декларация: хук ниже создаётся РАНЬШЕ объявления локальной
    -- sendFactionDataTo, поэтому без неё замыкание читало глобал (nil) и
    -- синк фракций падал при каждом заходе игрока.
    local sendFactionDataTo

    hook.Add("PlayerInitialSpawn", "Factions_SyncOnJoin", function(ply)
        timer.Simple(1.0, function()
            if IsValid(ply) then
                sendFactionDataTo(ply)
                syncPlayerFactionNW(ply)
            end
        end)
    end)

    hook.Add("PlayerSpawn", "Factions_SyncOnSpawn", function(ply)
        timer.Simple(0.2, function()
            if IsValid(ply) then
                syncPlayerFactionNW(ply)
            end
        end)
    end)

    local function createFaction(name,leaderSteamID,displayName)
        name=factionTrim(name,64);displayName=factionTrim(displayName,96);if name==""then return false,"Не указано регистрационное название"end;if displayName==""then displayName=name end
        if Factions[name] then return false, "Фракция с таким именем уже существует" end

        local defaultLeaderRole = "Лидер"
        local members = {}
        local leader  = nil
        if leaderSteamID and leaderSteamID ~= "" then
            leader = memberKey(leaderSteamID)
            members[leader] = { Role = defaultLeaderRole, Department = "" }
        end

        Factions[name] = {
            DisplayName    = displayName,
            Leader         = leader,
            Roles          = { defaultLeaderRole, "Участник" },
            LeaderRoleName = defaultLeaderRole,
            Departments    = {},
            Members        = members,
            Tag            = "",
            Color          = { r = 255, g = 200, b = 50 },
            DepAccess      = false,
            ServiceAccess  = false,
            InvoiceAccess  = false,
            DiplomaAccess  = false
        }
        saveFactions(Factions)
        return true
    end

    local function deleteFaction(name)
        if not Factions[name] then return false, "Фракция не найдена" end
        Factions[name] = nil
        saveFactions(Factions)
        return true
    end

    local function renameFaction(oldName, newName)
        if not oldName or oldName == "" then return false, "Не указано старое название" end
        if not newName or newName == "" then return false, "Не указано новое название" end
        if oldName == newName then return false, "Названия совпадают" end
        if not Factions[oldName] then return false, "Фракция не найдена" end
        if Factions[newName] then return false, "Фракция с таким именем уже существует" end

        Factions[newName] = Factions[oldName]
        Factions[oldName] = nil
        saveFactions(Factions)
        hook.Run("GRM_FactionRenamed", oldName, newName)
        return true
    end

    local function setFactionDisplayName(factionName,displayName)
        local f=Factions[factionName];if not f then return false,"Фракция не найдена"end;displayName=factionTrim(displayName,96);if displayName==""then return false,"Публичное название не указано"end;f.DisplayName=displayName;saveFactions(Factions);return true,"Публичное название сохранено"
    end

    local function setFactionTag(factionName, tag)
        local f = Factions[factionName]
        if not f then return false, "Фракция не найдена" end
        ensureDefaults(f)
        if type(tag) ~= "string" then return false, "Тег должен быть строкой" end
        tag = string.sub(tag, 1, 5)
        f.Tag = tag
        saveFactions(Factions)
        return true
    end

    local function setFactionColor(factionName, r, g, b)
        local f = Factions[factionName]
        if not f then return false, "Фракция не найдена" end
        ensureDefaults(f)
        r = math.Clamp(math.floor(tonumber(r) or 255), 0, 255)
        g = math.Clamp(math.floor(tonumber(g) or 200), 0, 255)
        b = math.Clamp(math.floor(tonumber(b) or 50),  0, 255)
        f.Color = { r = r, g = g, b = b }
        saveFactions(Factions)
        return true
    end

    local function setFactionDepAccess(factionName, enabled)
        local f = Factions[factionName]
        if not f then return false, "Фракция не найдена" end
        ensureDefaults(f)
        f.DepAccess = enabled and true or false
        saveFactions(Factions)
        return true
    end

    --[[ Код 127: доступы организации к государственным услугам.
         Флаг во фракции — «рубильник», подробная настройка (категории,
         предел суммы счёта, официальное название учреждения) живёт в
         GRM.Services.Access и правится в банкомате суперадмином. ]]
    local function setFactionServiceAccess(factionName, kind, enabled)
        local f = Factions[factionName]
        if not f then return false, "Фракция не найдена" end
        ensureDefaults(f)
        enabled = enabled and true or false
        local field = ({ service = "ServiceAccess", invoice = "InvoiceAccess", diploma = "DiplomaAccess" })[tostring(kind)]
        if not field then return false, "Неизвестный вид доступа" end
        f[field] = enabled
        saveFactions(Factions)
        -- держим реестр услуг в согласии с флагом
        local S = GRM and GRM.Services
        if S and isfunction(S.SetAccess) then
            local patch = {}
            if kind == "service" then patch.canService = enabled
            elseif kind == "invoice" then patch.canInvoice = enabled
            else patch.canDiploma = enabled end
            S.SetAccess(factionName, patch)
        end
        return true
    end

    local function addRole(factionName, roleName, displayName)
        local f = Factions[factionName]
        if not f then return false, "Фракция не найдена" end
        ensureDefaults(f, factionName)
        if not roleName or roleName == "" then return false, "Не указана роль" end
        if roleName == f.LeaderRoleName and (not f.RoleDisplayNames or not f.RoleDisplayNames[roleName]) then return false, "Нельзя добавить роль с системным именем лидера" end
        if table.HasValue(f.Roles, roleName) then return false, "Такой ранг уже существует" end
        local public = (displayName and displayName ~= "") and factionTrim(displayName, 96) or roleName
        table.insert(f.Roles, roleName)
        f.RoleDisplayNames[roleName] = public
        saveFactions(Factions)
        return true
    end

    local function removeRole(factionName, roleName)
        local f = Factions[factionName]
        if not f then return false, "Фракция не найдена" end
        ensureDefaults(f, factionName)
        if roleName == f.LeaderRoleName then return false, "Нельзя удалить роль лидера" end
        for i, r in ipairs(f.Roles) do
            if r == roleName then
                table.remove(f.Roles, i)
                f.RoleDisplayNames[roleName] = nil
                local fallback = getDefaultMemberRole(f)
                for key,info in pairs(f.Members)do if info.Role==roleName then local oldRole=info.Role;info.Role=fallback;hook.Run("GRM_FactionMemberRoleChanged",factionName,key,info,oldRole,fallback,nil)end end
                saveFactions(Factions)
                return true
            end
        end
        return false, "Ранг не найден"
    end

    local function renameRole(factionName, roleKey, newDisplayName)
        local f = Factions[factionName]
        if not f then return false, "Фракция не найдена" end
        ensureDefaults(f, factionName)
        if not table.HasValue(f.Roles, roleKey) then return false, "Роль не найдена" end
        newDisplayName = factionTrim(newDisplayName, 96)
        if newDisplayName == "" then return false, "Публичное название должности не указано" end
        -- ВАЖНО: меняется только label в f.RoleDisplayNames.
        -- Ключ roleKey у участников, RoleModels, RoleWeapons, доступы, транспорт, документы и кадровые дела не ломаются!
        f.RoleDisplayNames[roleKey] = newDisplayName
        saveFactions(Factions)
        hook.Run("GRM_FactionRoleDisplayChanged", factionName, roleKey, newDisplayName)
        return true, "Публичное название должности сохранено"
    end

    --[[ СМЕНА СИСТЕМНОГО КЛЮЧА ДОЛЖНОСТИ (заказ владельца 19.08).
         Раньше правилось только публичное название: ключ, придуманный один
         раз, оставался в базе навсегда (и в правах, и в дверях, и у людей).
         Теперь ключ можно переименовать — сама фракция чинится целиком, а
         внешние модули (права, двери, доступы) слушают хук
         GRM_FactionRoleKeyRenamed и переносят свои списки. ]]
    local function setRoleKey(factionName, oldKey, newKey)
        local f = Factions[factionName]
        if not f then return false, "Фракция не найдена" end
        ensureDefaults(f, factionName)
        oldKey = tostring(oldKey or "")
        newKey = factionTrim(newKey, 64)
        if not table.HasValue(f.Roles, oldKey) then return false, "Должность не найдена" end
        if newKey == "" then return false, "Новый системный ключ не указан" end
        if newKey == oldKey then return true, "Ключ не изменился" end
        if table.HasValue(f.Roles, newKey) then return false, "Должность с таким ключом уже есть" end

        for i, key in ipairs(f.Roles) do if key == oldKey then f.Roles[i] = newKey break end end
        if f.RoleDisplayNames then
            local display = f.RoleDisplayNames[oldKey]
            f.RoleDisplayNames[oldKey] = nil
            f.RoleDisplayNames[newKey] = (display and display ~= "") and display or newKey
        end
        if f.LeaderRoleName == oldKey then f.LeaderRoleName = newKey end

        local moved = 0
        for _, rec in pairs(f.Members or {}) do
            if istable(rec) and rec.Role == oldKey then rec.Role = newKey moved = moved + 1 end
        end
        for _, rec in pairs(f.PersonnelArchive or {}) do
            if istable(rec) and rec.Role == oldKey then rec.Role = newKey end
        end

        -- Списки, где ключ должности — ИНДЕКС таблицы.
        for _, field in ipairs({ "RoleModels", "RoleWeapons", "RoleVehicles" }) do
            local tbl = f[field]
            if istable(tbl) and tbl[oldKey] ~= nil then
                tbl[newKey] = tbl[oldKey]
                tbl[oldKey] = nil
            end
        end
        -- Списки, где ключ должности — ЗНАЧЕНИЕ массива.
        local function renameInArray(arr)
            if not istable(arr) then return end
            for i, v in ipairs(arr) do if v == oldKey then arr[i] = newKey end end
        end
        if istable(f.IncassoSettings) then renameInArray(f.IncassoSettings.Roles) end
        for _, dept in pairs(f.MaskDepartments or {}) do
            if istable(dept) then renameInArray(dept.Roles) end
        end
        for _, sub in pairs(f.Subdepartments or {}) do
            if istable(sub) then renameInArray(sub.roles) end
        end

        saveFactions(Factions)
        hook.Run("GRM_FactionRoleKeyRenamed", factionName, oldKey, newKey, moved)
        return true, ("Ключ должности изменён: %s → %s (сотрудников переведено: %d)"):format(oldKey, newKey, moved)
    end

    local function moveRole(factionName, roleName, direction)
        local f = Factions[factionName]
        if not f then return false, "Фракция не найдена" end
        ensureDefaults(f)
        if roleName == f.LeaderRoleName then return false, "Нельзя перемещать роль лидера" end
        for i, r in ipairs(f.Roles) do
            if r == roleName then
                local newIndex = (direction == "up") and (i - 1) or (i + 1)
                if newIndex < 1 or newIndex > #f.Roles then return false, "Крайняя позиция" end
                f.Roles[i], f.Roles[newIndex] = f.Roles[newIndex], f.Roles[i]
                saveFactions(Factions)
                return true
            end
        end
        return false, "Роль не найдена"
    end

    local function addDepartment(factionName, deptName)
        local f = Factions[factionName]
        if not f then return false, "Фракция не найдена" end
        ensureDefaults(f)
        if not deptName or deptName == "" then return false, "Не указан отдел" end
        if table.HasValue(f.Departments, deptName) then return false, "Такой отдел уже существует" end
        table.insert(f.Departments,deptName);f.DepartmentDisplayNames[deptName]=deptName
        saveFactions(Factions)
        return true
    end

    local function removeDepartment(factionName, deptName)
        local f = Factions[factionName]
        if not f then return false, "Фракция не найдена" end
        ensureDefaults(f)
        for i, d in ipairs(f.Departments) do
            if d == deptName then
                table.remove(f.Departments,i);f.DepartmentDisplayNames[deptName]=nil
                local firstDept = (istable(f.Departments) and f.Departments[1]) or ""
                for key,info in pairs(f.Members)do if info.Department==deptName then local oldDept=info.Department;info.Department=firstDept;hook.Run("GRM_FactionMemberDepartmentChanged",factionName,key,info,oldDept,firstDept,nil)end end
                saveFactions(Factions)
                return true
            end
        end
        return false, "Отдел не найден"
    end

    local function renameDepartment(factionName,departmentKey,newDisplayName)
        local f=Factions[factionName];if not f then return false,"Фракция не найдена"end;ensureDefaults(f,factionName);if not table.HasValue(f.Departments,departmentKey)then return false,"Отдел не найден"end;newDisplayName=factionTrim(newDisplayName,96);if newDisplayName==""then return false,"Публичное название отдела не указано"end
        -- ВАЖНО: меняется только label. Department у участников и ключи
        -- DepartmentModels/DepartmentWeapons/SpawnPoints/Access не трогаются.
        f.DepartmentDisplayNames[departmentKey]=newDisplayName;saveFactions(Factions);hook.Run("GRM_FactionDepartmentDisplayChanged",factionName,departmentKey,newDisplayName);return true,"Публичное название отдела сохранено"
    end

    local function moveDepartment(factionName, deptName, direction)
        local f = Factions[factionName]
        if not f then return false, "Фракция не найдена" end
        ensureDefaults(f)
        for i, d in ipairs(f.Departments) do
            if d == deptName then
                local newIndex = (direction == "up") and (i - 1) or (i + 1)
                if newIndex < 1 or newIndex > #f.Departments then return false, "Крайняя позиция" end
                f.Departments[i], f.Departments[newIndex] = f.Departments[newIndex], f.Departments[i]
                saveFactions(Factions)
                return true
            end
        end
        return false, "Отдел не найден"
    end

    local function addMember(factionName, steamID, role, dept)
        local f = Factions[factionName]
        if not f then return false, "Фракция не найдена" end
        ensureDefaults(f)
        local key = memberKey(steamID)
        if f.Members[key] then return false, "Игрок уже во фракции" end
        local existing = getFactionOfPlayer(key)
        if existing then return false, "Игрок уже состоит во фракции " .. existing end
        if role == f.LeaderRoleName then return false, "Лидер назначается только отдельно" end
        if role and not table.HasValue(f.Roles, role) then return false, "Такого ранга нет" end
        if dept and not table.HasValue(f.Departments, dept) then return false, "Такого отдела нет" end
        -- Код 108: дефолтный отдел — первый реальный (а не «Основной» из воздуха)
        local rec = { Role = role or getDefaultMemberRole(f), Department = dept or getDefaultDepartment(f) }
        if isstring(steamID) and not steamID:match(":char[1-3]$") then rec.LegacyKey = steamID end
        f.Members[key]=rec;hook.Run("GRM_FactionMemberJoined",factionName,key,rec,nil,"direct")
        saveFactions(Factions)
        return true
    end

    local function removeMember(factionName,steamID,actor,reason)
        local f = Factions[factionName]
        if not f then return false, "Фракция не найдена" end
        ensureDefaults(f)
        local key = memberKey(steamID)
        if not f.Members[key] then return false, "Игрок не состоит во фракции" end
        if key==f.Leader then
            hook.Run("GRM_FactionMemberRemoved",factionName,key,f.Members[key],actor,reason or"leader_removed");f.Members[key]=nil
            f.Leader = nil
            saveFactions(Factions)
            return true, "Лидер удалён, фракция сохранена без лидера"
        end
        hook.Run("GRM_FactionMemberRemoved",factionName,key,f.Members[key],actor,reason or"dismissed");f.Members[key]=nil
        saveFactions(Factions)
        return true, "Участник удалён"
    end

    local function setMemberRole(factionName,steamID,newRole,actor)
        local f = Factions[factionName]
        if not f then return false, "Фракция не найдена" end
        ensureDefaults(f)
        local key = memberKey(steamID)
        if not f.Members[key] then return false, "Игрок не состоит во фракции" end
        if not table.HasValue(f.Roles, newRole) then return false, "Такого ранга нет" end
        if newRole == f.LeaderRoleName and key ~= f.Leader then
            return false, "Лидер назначается только через смену лидера"
        end
        if key == f.Leader and newRole ~= f.LeaderRoleName then
            return false, "Нельзя изменить роль текущего лидера отдельно"
        end
        local oldRole=f.Members[key].Role;f.Members[key].Role=newRole;hook.Run("GRM_FactionMemberRoleChanged",factionName,key,f.Members[key],oldRole,newRole,actor)
        saveFactions(Factions)
        return true
    end

    local function setMemberDepartment(factionName,steamID,newDept,actor)
        local f = Factions[factionName]
        if not f then return false, "Фракция не найдена" end
        ensureDefaults(f)
        local key = memberKey(steamID)
        if not f.Members[key] then return false, "Игрок не состоит во фракции" end
        if not table.HasValue(f.Departments, newDept) then return false, "Такого отдела нет" end
        local oldDept=f.Members[key].Department;f.Members[key].Department=newDept;hook.Run("GRM_FactionMemberDepartmentChanged",factionName,key,f.Members[key],oldDept,newDept,actor)
        -- Перевод в другой отдел снимает подотдел ЧУЖОГО отдела: иначе в
        -- составе висел подотдел, к которому сотрудник уже не относится, и
        -- по нему же выдавалась форма и печатался тег в рацию.
        local curSub = tostring(f.Members[key].Subdepartment or "")
        if curSub ~= "" then
            local sub = f.Subdepartments and f.Subdepartments[curSub]
            local parent = istable(sub) and tostring(sub.parentDept or "") or ""
            if not istable(sub) or (parent ~= "" and parent ~= newDept) then
                f.Members[key].Subdepartment = ""
                hook.Run("GRM_FactionMemberSubdepartmentChanged", factionName, key, f.Members[key], curSub, "", actor)
            end
        end
        saveFactions(Factions)
        return true
    end

    -- Теги отдела/подотдела: применяются в /fr, /frb, /dep, /d, /depb, /db
    -- и в шапке над игроком.
    local function setDepartmentTag(factionName, departmentKey, newTag)
        local f = Factions[factionName]
        if not f then return false, "Фракция не найдена" end
        ensureDefaults(f, factionName)
        if not table.HasValue(f.Departments, departmentKey) then return false, "Отдел не найден" end
        f.DepartmentTags = f.DepartmentTags or {}
        f.DepartmentTags[departmentKey] = factionTrim(newTag, 24)
        saveFactions(Factions)
        hook.Run("GRM_FactionDepartmentTagChanged", factionName, departmentKey, f.DepartmentTags[departmentKey])
        return true, "Тег отдела сохранён"
    end

    local function setSubdepartmentTag(factionName, subdeptKey, newTag)
        local f = Factions[factionName]
        if not f then return false, "Фракция не найдена" end
        ensureDefaults(f, factionName)
        if not (f.Subdepartments and f.Subdepartments[subdeptKey]) then return false, "Подотдел не найден" end
        f.Subdepartments[subdeptKey].tag = factionTrim(newTag, 24)
        saveFactions(Factions)
        hook.Run("GRM_FactionSubdepartmentTagChanged", factionName, subdeptKey, f.Subdepartments[subdeptKey].tag)
        return true, "Тег подотдела сохранён"
    end

    local function addSubdepartment(factionName, parentDeptId, subdeptKey, displayName, tag, quota)
        local f = Factions[factionName]
        if not f then return false, "Фракция не найдена" end
        ensureDefaults(f, factionName)
        if not parentDeptId or not table.HasValue(f.Departments, parentDeptId) then
            return false, "Родительский отдел не найден"
        end
        subdeptKey = factionTrim(subdeptKey, 64):lower():gsub("[^%w_%-]", "_")
        if subdeptKey == "" then return false, "Не указан системный ключ подотдела" end
        if f.Subdepartments and f.Subdepartments[subdeptKey] then
            return false, "Подотдел с таким системным ключом уже существует"
        end
        displayName = factionTrim(displayName or subdeptKey, 96)
        if displayName == "" then displayName = subdeptKey end
        tag = factionTrim(tag or "", 24)
        quota = math.max(0, math.floor(tonumber(quota) or 0))

        f.Subdepartments = f.Subdepartments or {}
        f.SubdepartmentDisplayNames = f.SubdepartmentDisplayNames or {}
        f.Subdepartments[subdeptKey] = {
            id = subdeptKey,
            name = displayName,
            parentDept = parentDeptId,
            tag = tag,
            quota = quota,
            head = "",
            models = {},
            weapons = {},
            vehicles = {},
        }
        f.SubdepartmentDisplayNames[subdeptKey] = displayName
        saveFactions(Factions)
        hook.Run("GRM_FactionSubdepartmentAdded", factionName, parentDeptId, subdeptKey, displayName)
        return true, "Подотдел успешно добавлен"
    end

    local function removeSubdepartment(factionName, subdeptKey)
        local f = Factions[factionName]
        if not f then return false, "Фракция не найдена" end
        ensureDefaults(f, factionName)
        if not (f.Subdepartments and f.Subdepartments[subdeptKey]) then
            return false, "Подотдел не найден"
        end
        f.Subdepartments[subdeptKey] = nil
        if f.SubdepartmentDisplayNames then f.SubdepartmentDisplayNames[subdeptKey] = nil end
        for key, info in pairs(f.Members or {}) do
            if info.Subdepartment == subdeptKey then
                local oldSub = info.Subdepartment
                info.Subdepartment = ""
                hook.Run("GRM_FactionMemberSubdepartmentChanged", factionName, key, info, oldSub, "", nil)
            end
        end
        saveFactions(Factions)
        hook.Run("GRM_FactionSubdepartmentRemoved", factionName, subdeptKey)
        return true, "Подотдел удалён"
    end

    local function renameSubdepartment(factionName, subdeptKey, newDisplayName)
        local f = Factions[factionName]
        if not f then return false, "Фракция не найдена" end
        ensureDefaults(f, factionName)
        if not (f.Subdepartments and f.Subdepartments[subdeptKey]) then
            return false, "Подотдел не найден"
        end
        newDisplayName = factionTrim(newDisplayName, 96)
        if newDisplayName == "" then return false, "Публичное название подотдела не указано" end
        f.Subdepartments[subdeptKey].name = newDisplayName
        f.SubdepartmentDisplayNames = f.SubdepartmentDisplayNames or {}
        f.SubdepartmentDisplayNames[subdeptKey] = newDisplayName
        saveFactions(Factions)
        hook.Run("GRM_FactionSubdepartmentDisplayChanged", factionName, subdeptKey, newDisplayName)
        return true, "Публичное название подотдела сохранено"
    end

    local function setMemberSubdepartment(factionName, steamID, newSubdept, actor)
        local f = Factions[factionName]
        if not f then return false, "Фракция не найдена" end
        ensureDefaults(f, factionName)
        local key = memberKey(steamID)
        if not f.Members[key] then return false, "Игрок не состоит во фракции" end
        newSubdept = tostring(newSubdept or "")
        if newSubdept ~= "" and not (f.Subdepartments and f.Subdepartments[newSubdept]) then
            return false, "Такого подотдела нет"
        end
        if newSubdept ~= "" then
            local parent = f.Subdepartments[newSubdept].parentDept
            if parent and parent ~= "" and f.Members[key].Department ~= parent then
                local oldDept = f.Members[key].Department
                f.Members[key].Department = parent
                hook.Run("GRM_FactionMemberDepartmentChanged", factionName, key, f.Members[key], oldDept, parent, actor)
            end
        end
        local oldSub = f.Members[key].Subdepartment or ""
        f.Members[key].Subdepartment = newSubdept
        hook.Run("GRM_FactionMemberSubdepartmentChanged", factionName, key, f.Members[key], oldSub, newSubdept, actor)
        saveFactions(Factions)
        return true
    end

    local function changeLeader(factionName, newLeaderSteamID)
        local f = Factions[factionName]
        if not f then return false, "Фракция не найдена" end
        ensureDefaults(f)
        local key = memberKey(newLeaderSteamID)
        if not f.Members[key]then local existing=getFactionOfPlayer(key);if existing then return false,"Игрок уже состоит во фракции "..existing end;f.Members[key]={Role=getDefaultMemberRole(f),Department=getDefaultDepartment(f)};hook.Run("GRM_FactionMemberJoined",factionName,key,f.Members[key],nil,"leader_assignment")end
        local oldLeader=f.Leader;if oldLeader and f.Members[oldLeader]then local oldRole=f.Members[oldLeader].Role;f.Members[oldLeader].Role=getDefaultMemberRole(f);hook.Run("GRM_FactionMemberRoleChanged",factionName,oldLeader,f.Members[oldLeader],oldRole,f.Members[oldLeader].Role,nil)end
        f.Leader=key;local previous=f.Members[key].Role;f.Members[key].Role=f.LeaderRoleName;hook.Run("GRM_FactionMemberRoleChanged",factionName,key,f.Members[key],previous,f.LeaderRoleName,nil);hook.Run("GRM_FactionLeaderChanged",factionName,oldLeader,key)
        saveFactions(Factions)
        return true
    end

    -- Суперадмин назначает СЕБЯ напрямую: это не приглашение и не создаёт
    -- окно самому себе. Можно выбрать обычную роль либо стать лидером.
    local function assignSelfToFaction(ply, factionName, role, dept, subdept, leader)
        if not (IsValid(ply) and ply:IsSuperAdmin()) then return false, "Только суперадмин" end
        local f = Factions[tostring(factionName or "")]
        if not f then return false, "Фракция не найдена" end
        ensureDefaults(f, factionName)
        local selfKey = memberKey(ply)
        local current = getFactionOfPlayer(selfKey)
        if current and current ~= factionName then
            local ok, err = removeMember(current, selfKey, ply, "superadmin_self_reassign")
            if not ok then return false, err end
        end
        if leader == true then
            local ok, err = changeLeader(factionName, selfKey)
            if not ok then return false, err end
        elseif not f.Members[selfKey] then
            local ok, err = addMember(factionName, selfKey, role, dept)
            if not ok then return false, err end
        end
        if leader ~= true then
            local ok, err = setMemberRole(factionName, selfKey, tostring(role or getDefaultMemberRole(f)), ply)
            if not ok then return false, err end
        end
        if dept and tostring(dept) ~= "" then
            local ok, err = setMemberDepartment(factionName, selfKey, tostring(dept), ply)
            if not ok then return false, err end
        end
        if subdept and tostring(subdept) ~= "" then
            local ok, err = setMemberSubdepartment(factionName, selfKey, tostring(subdept), ply)
            if not ok then return false, err end
        end
        syncPlayerFactionNW(ply)
        broadcastFactionData()
        if GRM.Audit and GRM.Audit.Write then GRM.Audit.Write("factions", "self_assign", ply, { faction=factionName, characterKey=selfKey }, { role=role, department=dept, subdepartment=subdept, leader=leader==true }) end
        return true, leader == true and "Вы назначены лидером фракции" or "Вы назначены участником фракции"
    end

    -- --------------------
    -- ПРИГЛАШЕНИЯ
    -- --------------------
    local INVITE_LIFETIME=300
    local function inviteTarget(key)return(GRM.Identity and GRM.Identity.ResolveCharacter and GRM.Identity.ResolveCharacter(key))or nil end
    local function inviteAuthorName(fromPlayer,fromKey)local rp=IsValid(fromPlayer)and fromPlayer:GetNWString("GRM_RPName","")or"";if rp~=""then return rp end;if IsValid(fromPlayer)then return fromPlayer:Nick()end;return select(1,characterDisplay(fromKey))end
    local function normalizeInvite(inv)
        if not istable(inv)then return nil end;inv.faction=tostring(inv.faction or"");inv.from=tostring(inv.from or"");inv.created=tonumber(inv.created or inv.time)or os.time();inv.expires=tonumber(inv.expires)or(inv.created+INVITE_LIFETIME);local rawID=inv.faction.."|"..inv.from.."|"..inv.created;inv.id=tostring(inv.id or("legacy_"..(util.CRC and util.CRC(rawID)or rawID:gsub("[^%w]","_"))));inv.fromName=tostring(inv.fromName or inviteAuthorName(nil,inv.from));local f=Factions[inv.faction]or{};inv.role=tostring(inv.role or getDefaultMemberRole(f));inv.department=tostring(inv.department or getDefaultDepartment(f));return inv
    end
    local function pushInvite(target,inv,closedReason)
        if not IsValid(target)then return end;net.Start(NET_INVITE_OPEN);net.WriteBool(closedReason==nil);if closedReason~=nil then net.WriteString(tostring(closedReason))else local f=Factions[inv.faction]or{};net.WriteString(inv.id);net.WriteString(inv.faction);net.WriteString(GRM.Factions.DisplayName(f,inv.faction));net.WriteString(inv.fromName);net.WriteString(inv.role or getDefaultMemberRole(f));net.WriteString(inv.department or getDefaultDepartment(f));net.WriteUInt(math.max(0,math.floor(inv.expires)),32)end;net.Send(target)
    end
    local function notifyInviteAuthor(inv,text)
        local author=inviteTarget(inv.from);if IsValid(author)then author:PrintMessage(HUD_PRINTTALK,"[Фракция] "..text)end
    end
    local function sendInvite(fromPlayerOrKey,toSteam,factionName,desiredRole,desiredDepartment)
        local f=Factions[factionName];if not f then return false,"Фракция не найдена"end;ensureDefaults(f,factionName);desiredRole=tostring(desiredRole or"");desiredDepartment=tostring(desiredDepartment or"");if desiredRole==""then desiredRole=getDefaultMemberRole(f)end;if desiredRole==f.LeaderRoleName or not table.HasValue(f.Roles,desiredRole)then return false,"Недопустимая стартовая должность"end;if desiredDepartment==""then desiredDepartment=getDefaultDepartment(f)end;if desiredDepartment~=""and not table.HasValue(f.Departments,desiredDepartment)then return false,"Недопустимый стартовый отдел"end
        local fromPlayer=(isentity(fromPlayerOrKey)and IsValid(fromPlayerOrKey)and fromPlayerOrKey)or inviteTarget(fromPlayerOrKey)or player.GetBySteamID(tostring(fromPlayerOrKey or""))or player.GetBySteamID64(tostring(fromPlayerOrKey or""));local fromKey=memberKey(fromPlayer or fromPlayerOrKey);local targetKey=memberKey(toSteam)
        local isSuperAdmin=IsValid(fromPlayer)and fromPlayer:IsSuperAdmin();local isLeader=(f.Leader==fromKey)or(IsValid(fromPlayer)and isCharacterLeaderOfFaction(fromPlayer,f));if not isSuperAdmin and not isLeader then return false,"Недостаточно прав"end
        if targetKey==""then return false,"Не выбран персонаж"end;if targetKey==fromKey then return false,"Нельзя пригласить самого себя"end;if getFactionOfPlayer(targetKey)then return false,"Персонаж уже состоит во фракции"end
        local old=normalizeInvite(Invites[targetKey]);if old and old.expires>os.time()then return false,"У персонажа уже есть активное приглашение от «"..GRM.Factions.DisplayName(old.faction).."»"end
        --[[ Цель ищем ДО записи приглашения. Раньше приглашение сохранялось
             даже когда персонаж не в сети или играет другим персонажем:
             окно ему не приходило, а лидер видел «отправлено». Теперь такой
             случай — честный отказ с объяснением. ]]
        local target=inviteTarget(targetKey)or player.GetBySteamID(tostring(toSteam or""))or player.GetBySteamID64(tostring(toSteam or""))
        if not IsValid(target)then
            return false,"Игрок не в сети или играет другим персонажем — приглашение не доставить"
        end

        local now=os.time();local inv={id="fi_"..now.."_"..math.random(100000,999999),faction=factionName,from=fromKey,fromName=inviteAuthorName(fromPlayer,fromKey),created=now,time=now,expires=now+INVITE_LIFETIME,role=desiredRole,department=desiredDepartment};Invites[targetKey]=inv;saveInvites(Invites)
        pushInvite(target,inv)
        print(("[GRM Factions] приглашение %s → %s (%s), истекает через %d с")
            :format(tostring(fromKey), tostring(targetKey), tostring(factionName), INVITE_LIFETIME))
        if GRM.Audit and GRM.Audit.Write then GRM.Audit.Write("factions","invite.sent",fromPlayer,{characterKey=targetKey,faction=factionName},{inviteID=inv.id,expires=inv.expires})end
        return true,"Приглашение в «"..GRM.Factions.DisplayName(f,factionName).."» отправлено на 5 минут"
    end

    local function acceptInvite(steamID,factionName,inviteID)
        local key=memberKey(steamID);local inv=normalizeInvite(Invites[key]);if not inv then return false,"У вас нет активных приглашений"end
        if inv.expires<=os.time()then Invites[key]=nil;saveInvites(Invites);return false,"Срок приглашения истёк"end
        if inviteID and inviteID~=""and inv.id~=inviteID then return false,"Приглашение уже обновилось"end
        if factionName~=""and inv.faction:lower()~=factionName:lower()then return false,"Активное приглашение выдано фракцией «"..GRM.Factions.DisplayName(inv.faction).."»"end
        factionName=inv.faction;if getFactionOfPlayer(key)then return false,"Вы уже состоите во фракции"end;local f=Factions[factionName];if not f then Invites[key]=nil;saveInvites(Invites);return false,"Фракция больше не существует"end;ensureDefaults(f,factionName)
        f.Members[key]={Role=inv.role or getDefaultMemberRole(f),Department=inv.department or getDefaultDepartment(f)};hook.Run("GRM_FactionMemberJoined",factionName,key,f.Members[key],inv.from,"invite");saveFactions(Factions);Invites[key]=nil;saveInvites(Invites);local ply=inviteTarget(key);local display=GRM.Factions.DisplayName(f,factionName);if IsValid(ply)then pushInvite(ply,inv,"Вы приняты во фракцию «"..display.."»");ply:PrintMessage(HUD_PRINTTALK,"Вы вступили во фракцию «"..display.."»")end;notifyInviteAuthor(inv,(IsValid(ply)and ply:Nick()or key).." принял приглашение в «"..display.."»")
        if GRM.Audit and GRM.Audit.Write then GRM.Audit.Write("factions","invite.accepted",ply,{faction=factionName,characterKey=key},{inviteID=inv.id})end;return true,display
    end
    local function declineInvite(steamID,factionName,inviteID)
        local key=memberKey(steamID);local inv=normalizeInvite(Invites[key]);if not inv then return false,"У вас нет активных приглашений"end;if inviteID and inviteID~=""and inv.id~=inviteID then return false,"Приглашение уже обновилось"end;if factionName~=""and inv.faction~=factionName then return false,"Это приглашение уже не активно"end;Invites[key]=nil;saveInvites(Invites);local display=GRM.Factions.DisplayName(inv.faction);local target=inviteTarget(key);if IsValid(target)then pushInvite(target,inv,"Приглашение в «"..display.."» отклонено")end;notifyInviteAuthor(inv,(IsValid(inviteTarget(key))and inviteTarget(key):Nick()or key).." отклонил приглашение в «"..display.."»");if GRM.Audit and GRM.Audit.Write then GRM.Audit.Write("factions","invite.declined",inviteTarget(key),{faction=inv.faction,characterKey=key},{inviteID=inv.id})end;return true,display
    end

    local function leaveFaction(steamID)
        local key = memberKey(steamID)
        local factionName = getFactionOfPlayer(key)
        if not factionName then return false, "Вы не состоите ни в одной фракции" end
        local f = Factions[factionName]
        if not f then return false, "Фракция не найдена" end
        ensureDefaults(f)
        if f.Leader == key then return false, "Лидер не может покинуть фракцию, используйте увольнение" end
        hook.Run("GRM_FactionMemberRemoved",factionName,key,f.Members[key],steamID,"left_voluntarily");f.Members[key]=nil
        saveFactions(Factions)
        return true
    end

    local function respondTo(ply, success, msg)
        net.Start(NET_ACTION_RESULT)
        net.WriteBool(success and true or false)
        net.WriteString(msg or "")
        net.Send(ply)
    end

    sendFactionDataTo = function(ply)
        -- Первичный снимок весит десятки килобайт. Одним пакетом он занимает
        -- канал целиком и даёт рывок; шлём частями через GRM.Net.Stream, а
        -- прежний одноразовый путь оставляем фолбэком.
        local data = buildSyncData()
        if GRM.Net and GRM.Net.Stream then
            local ok = GRM.Net.Stream("factions.full", data, { ply }, { chunk = 8192, interval = 0.05 })
            if ok then
                sendCharacterChoices(ply)
                return
            end
        end
        net.Start(NET_SEND_DATA)
        net.WriteTable(data)
        net.Send(ply)
        sendCharacterChoices(ply)
    end

    -- --------------------
    -- СЕТЕВЫЕ ОБРАБОТЧИКИ
    -- --------------------
    net.Receive(NET_GET_DATA, function(_, ply) sendFactionDataTo(ply) end)

    net.Receive(NET_ACTION, function(_, ply)
        local action       = net.ReadString()
        local args         = net.ReadTable() or {}
        local isSuperAdmin = ply:IsSuperAdmin()

        local leaderFaction = getFactionOfLeader(ply)
        local isLeader = leaderFaction ~= nil

        local function done(success, msg)
            respondTo(ply, success, msg)
            if success then broadcastFactionData() end
        end

        local function getFactionAndShift()
            if isSuperAdmin then
                local faction = args[1]
                if not faction then done(false, "Не указана фракция") return nil, nil end
                if not Factions[faction] then done(false, "Фракция не существует") return nil, nil end
                return faction, 1
            end
            if not isLeader then done(false, "Недостаточно прав") return nil, nil end
            return leaderFaction, 0
        end

        -- Любая правка ЧУЖОЙ фракции не-root суперадмином проходит Root
        -- Guard. Лидер собственной фракции и root-владелец не попадают в
        -- очередь; остальные действия fail-closed до approval.
        local guarded = {
            setDisplayName=true, renameFaction=true, changeLeader=true,
            setTag=true, setColor=true, setDepAccess=true, setServiceAccess=true,
            addRole=true, removeRole=true, renameRole=true, setRoleKey=true, moveRole=true,
            addDepartment=true, removeDepartment=true, renameDepartment=true, moveDepartment=true,
            addSubdepartment=true, removeSubdepartment=true, renameSubdepartment=true,
            setDepartmentTag=true, setSubdepartmentTag=true, setRole=true, setDepartment=true,
            setSubdepartment=true, removeMember=true, inviteMember=true, assignSelf=true,
            positionSave=true, positionDelete=true, positionAssign=true,
        }
        if guarded[action] and isSuperAdmin and args[1] and GRM.Root and GRM.Root.RequestFactionApproval then
            local targetFaction = tostring(args[1])
            local ownFaction = tostring(getFactionOfPlayer(ply) or "")
            if ownFaction ~= targetFaction and not GRM.Root.IsRoot(ply) then
                if not GRM.Root.RequestFactionApproval(ply, action, targetFaction, args) then
                    done(false, "Изменение чужой фракции ожидает одобрения владельца. После одобрения повторите действие.")
                    return
                end
            end
        end

        if action=="createFaction"then
            if not isSuperAdmin then done(false,"Только суперадмин")return end;local ok,err=createFaction(args[1],args[2],args[1]);done(ok,err)
        elseif action=="createFactionV2"then
            if not isSuperAdmin then done(false,"Только суперадмин")return end;local ok,err=createFaction(args[1],args[3],args[2]);done(ok,err)
        elseif action=="setDisplayName"then
            if not isSuperAdmin then done(false,"Только суперадмин")return end;local ok,err=setFactionDisplayName(args[1],args[2]);done(ok,err)
        elseif action == "renameFaction" then
            if not isSuperAdmin then done(false, "Только суперадмин") return end
            if not args[1] or not args[2] then done(false, "Не указаны параметры") return end
            local ok, err = renameFaction(args[1], args[2])
            done(ok, err)
        elseif action == "deleteFaction" then
            if not isSuperAdmin then done(false, "Только суперадмин") return end
            -- Root Guard (Код 84): не-root суперадмину удаление исполняется
            -- ТОЛЬКО после подтверждения владельцем сервера (fail-closed).
            if GRM and GRM.Root and GRM.Root.Request then
                local allowedNow = GRM.Root.Request(ply, "faction_delete",
                    "Удаление фракции «" .. tostring(args[1]) .. "»",
                    { faction = args[1] })
                if not allowedNow then
                    respondTo(ply, true, "Запрос на удаление «" .. tostring(args[1]) .. "» отправлен владельцу сервера — исполнится после его подтверждения.")
                    return -- НЕ удаляем и НЕ вещаем: фракция остаётся жить
                end
            end
            local ok, err = deleteFaction(args[1])
            done(ok, err)
        elseif action == "changeLeader" then
            if not isSuperAdmin then done(false, "Только суперадмин") return end
            if not args[1] or not args[2] then done(false, "Не указаны параметры") return end
            local ok, err = changeLeader(args[1], args[2])
            done(ok, err)
        elseif action == "setTag" then
            if not isSuperAdmin then done(false, "Только суперадмин") return end
            if not args[1] or not args[2] then done(false, "Не указаны параметры") return end
            local ok, err = setFactionTag(args[1], args[2])
            done(ok, err)
        elseif action == "setColor" then
            if not isSuperAdmin then done(false, "Только суперадмин") return end
            if not args[1] then done(false, "Не указана фракция") return end
            local ok, err = setFactionColor(args[1], args[2], args[3], args[4])
            done(ok, err)
        elseif action == "setDepAccess" then
            if not args[1] then done(false, "Не указана фракция") return end
            if not isSuperAdmin and getFactionOfLeader(ply) ~= args[1] then done(false, "Недостаточно прав") return end
            -- Раздел «Доступы и связь» может быть закрыт суперадмином:
            -- тогда лидер не переключит доступ и в обход интерфейса.
            if GRM.MenuAccess and GRM.MenuAccess.PlayerCan
                and not GRM.MenuAccess.PlayerCan(ply, "access", args[1]) then
                done(false, "Раздел доступов закрыт администрацией")
                return
            end
            local ok, err = setFactionDepAccess(args[1], args[2])
            done(ok, err)
        elseif action == "setServiceAccess" then
            if not args[1] or not args[2] then done(false, "Не указаны параметры") return end
            if not isSuperAdmin and getFactionOfLeader(ply) ~= args[1] then done(false, "Недостаточно прав") return end
            local ok, err = setFactionServiceAccess(args[1], args[2], args[3])
            done(ok, err)
        elseif action == "addRole" then
            local faction, shift = getFactionAndShift()
            if not faction then return end
            local ok, err = addRole(faction, args[1 + shift])
            done(ok, err)
        elseif action == "removeRole" then
            local faction, shift = getFactionAndShift()
            if not faction then return end
            local ok, err = removeRole(faction, args[1 + shift])
            done(ok, err)
        elseif action == "renameRole" then
            local faction, shift = getFactionAndShift()
            if not faction then return end
            local ok, err = renameRole(faction, args[1 + shift], args[2 + shift])
            done(ok, err)
        elseif action == "setRoleKey" then
            local faction, shift = getFactionAndShift()
            if not faction then return end
            local ok, err = setRoleKey(faction, args[1 + shift], args[2 + shift])
            done(ok, err)
        elseif action == "moveRole" then
            local faction, shift = getFactionAndShift()
            if not faction then return end
            local ok, err = moveRole(faction, args[1 + shift], args[2 + shift])
            done(ok, err)
        elseif action == "addDepartment" then
            local faction, shift = getFactionAndShift()
            if not faction then return end
            local ok, err = addDepartment(faction, args[1 + shift])
            done(ok, err)
        elseif action == "removeDepartment" then
            local faction, shift = getFactionAndShift()
            if not faction then return end
            local ok, err = removeDepartment(faction, args[1 + shift])
            done(ok, err)
        elseif action == "renameDepartment" then
            local faction, shift = getFactionAndShift()
            if not faction then return end
            local ok, err = renameDepartment(faction, args[1 + shift], args[2 + shift])
            done(ok, err)
        elseif action == "moveDepartment" then
            local faction, shift = getFactionAndShift()
            if not faction then return end
            local ok, err = moveDepartment(faction, args[1 + shift], args[2 + shift])
            done(ok, err)
        elseif action == "assignSelf" then
            if not isSuperAdmin then done(false, "Только суперадмин") return end
            local ok, err = assignSelfToFaction(ply, args[1], args[2], args[3], args[4], args[5] == true)
            done(ok, err)
        elseif action == "inviteMember" then
            local faction, shift = getFactionAndShift()
            if not faction then return end
            local ok,err=sendInvite(ply,args[1+shift],faction,args[2+shift],args[3+shift])
            done(ok, err)
        elseif action == "removeMember" then
            local faction, shift = getFactionAndShift()
            if not faction then return end
            local ok,err=removeMember(faction,args[1+shift],ply,"dismissed_by_management")
            done(ok, err)
        elseif action == "setRole" then
            local faction, shift = getFactionAndShift()
            if not faction then return end
            local ok,err=setMemberRole(faction,args[1+shift],args[2+shift],ply)
            done(ok, err)
        elseif action == "setDepartment" then
            local faction, shift = getFactionAndShift()
            if not faction then return end
            local ok,err=setMemberDepartment(faction,args[1+shift],args[2+shift],ply)
            done(ok, err)
        elseif action == "addSubdepartment" then
            local faction, shift = getFactionAndShift()
            if not faction then return end
            local ok,err=addSubdepartment(faction,args[1+shift],args[2+shift],args[3+shift],args[4+shift],args[5+shift])
            done(ok, err)
        elseif action == "removeSubdepartment" then
            local faction, shift = getFactionAndShift()
            if not faction then return end
            local ok,err=removeSubdepartment(faction,args[1+shift])
            done(ok, err)
        elseif action == "setDepartmentTag" then
            local faction, shift = getFactionAndShift()
            if not faction then return end
            local ok, err = setDepartmentTag(faction, args[1 + shift], args[2 + shift])
            done(ok, err)
        elseif action == "setSubdepartmentTag" then
            local faction, shift = getFactionAndShift()
            if not faction then return end
            local ok, err = setSubdepartmentTag(faction, args[1 + shift], args[2 + shift])
            done(ok, err)
        elseif action == "renameSubdepartment" then
            local faction, shift = getFactionAndShift()
            if not faction then return end
            local ok,err=renameSubdepartment(faction,args[1+shift],args[2+shift])
            done(ok, err)
        elseif action == "setSubdepartment" then
            local faction, shift = getFactionAndShift()
            if not faction then return end
            local ok,err=setMemberSubdepartment(faction,args[1+shift],args[2+shift],ply)
            done(ok, err)
        --[[ ДОЛЖНОСТИ (ось v5, GRM.Positions). Работают так же, как подотделы:
             суперадмин указывает организацию первым аргументом, лидер правит
             свою. Вся проверка данных — внутри GRM.Positions. ]]
        elseif action == "positionSave" then
            local faction, shift = getFactionAndShift()
            if not faction then return end
            if not (GRM.Positions and GRM.Positions.Set) then done(false, "Модуль должностей не загружен") return end
            local data = istable(args[2 + shift]) and args[2 + shift] or {}
            local ok, err = GRM.Positions.Set(faction, args[1 + shift], data)
            done(ok, err)
        elseif action == "positionDelete" then
            local faction, shift = getFactionAndShift()
            if not faction then return end
            if not (GRM.Positions and GRM.Positions.Delete) then done(false, "Модуль должностей не загружен") return end
            local ok, err = GRM.Positions.Delete(faction, args[1 + shift])
            done(ok, err)
        elseif action == "positionAssign" then
            local faction, shift = getFactionAndShift()
            if not faction then return end
            if not (GRM.Positions and GRM.Positions.Assign) then done(false, "Модуль должностей не загружен") return end
            local ok, err = GRM.Positions.Assign(faction, args[1 + shift], args[2 + shift], ply)
            done(ok, err)
        elseif action == "saveIncasso" then
            -- Код 126: сохранение настроек инкассации фракции (только суперадмин)
            if not isSuperAdmin then done(false, "Только суперадмин") return end
            local factionName = args[1]
            if not factionName or not Factions[factionName] then done(false, "Фракция не существует") return end
            local f = Factions[factionName]
            ensureDefaults(f)
            local enabled = args[2] == true
            local roles   = istable(args[3]) and args[3] or {}
            local vehicles= istable(args[4]) and args[4] or {}
            -- Нормализация: МАССИВЫ, не карты
            local cleanRoles, cleanVeh = {}, {}
            local seenR, seenV = {}, {}
            for _, r in ipairs(roles) do
                if type(r) == "string" and r ~= "" and not seenR[r] then
                    seenR[r] = true
                    cleanRoles[#cleanRoles + 1] = r
                end
            end
            for _, v in ipairs(vehicles) do
                if type(v) == "string" and v ~= "" and not seenV[v] then
                    seenV[v] = true
                    cleanVeh[#cleanVeh + 1] = v
                end
            end
            f.IncassoSettings = { Enabled = enabled, Roles = cleanRoles, Vehicles = cleanVeh }
            saveFactions(Factions)
            -- SAVE ok read-back (находка 65/стандарт GRM)
            local rb = file.Read(FACTIONS_FILE, "DATA")
            print("[GRM Incasso] SAVE ok: настройки инкассации фракции '" .. factionName .. "' сохранены [Код 126 — " .. #cleanRoles .. " ролей, " .. #cleanVeh .. " ТС]")
            if not rb or rb == "" then
                print("[GRM Incasso][!] SAVE read-back ПУСТ для factions.json — возможно проблема с правами data/")
            end
            done(true, "Настройки инкассации сохранены для «" .. factionName .. "»")
        else
            done(false, "Неизвестное действие")
        end
    end)

    net.Receive(NET_JOIN,function(_,ply)local factionName=net.ReadString();local ok,err=acceptInvite(ply,factionName);if ok then broadcastFactionData()else ply:PrintMessage(HUD_PRINTTALK,"Ошибка: "..err)end end)

    net.Receive(NET_DECLINE, function(_, ply)
        local factionName = net.ReadString()
        local ok, err = declineInvite(ply, factionName)
        if ok then ply:PrintMessage(HUD_PRINTTALK, "Вы отклонили приглашение во фракцию «"..GRM.Factions.DisplayName(factionName).."»")
        else ply:PrintMessage(HUD_PRINTTALK, "Ошибка: " .. err) end
    end)

    net.Receive(NET_INVITE_ACTION,function(bits,ply)
        if not IsValid(ply)then return end;if GRM.Net and not GRM.Net.Guard(ply,"factions.invite.action",{rate=.5,burst=2,maxBits=512},{bits=bits})then return end;local op,id=net.ReadString(),net.ReadString();local ok,msg
        if op=="accept"then ok,msg=acceptInvite(ply,"",id);if ok then broadcastFactionData()end elseif op=="decline"then ok,msg=declineInvite(ply,"",id)else return end
        if not ok then pushInvite(ply,{faction="",id=id},"Ошибка: "..tostring(msg))end
    end)

    local function resendInvite(ply,closeMissing)
        if not IsValid(ply)then return end;local key=memberKey(ply);local inv=normalizeInvite(Invites[key]);if not inv then if closeMissing then pushInvite(ply,{},"")end return end;if inv.expires<=os.time()then Invites[key]=nil;saveInvites(Invites);pushInvite(ply,inv,"Срок приглашения истёк");return end;Invites[key]=inv;pushInvite(ply,inv)
    end
    hook.Add("PlayerInitialSpawn","Factions_InviteV2Join",function(ply)timer.Simple(3,function()resendInvite(ply,false)end)end)
    -- Спавн после смерти/смены персонажа тоже возвращает окно приглашения:
    -- иначе человек, погибший в момент выдачи, теряет его насовсем.
    hook.Add("PlayerSpawn","Factions_InviteV2Respawn",function(ply)timer.Simple(2,function()resendInvite(ply,false)end)end)

    --[[ Диагностика: видно, есть ли приглашение и кому оно адресовано.
         Нужна именно потому, что «не пришло» может значить и «не создано»,
         и «создано не тому персонажу». ]]
    concommand.Add("grm_faction_invites",function(ply)
        if IsValid(ply)and not ply:IsSuperAdmin()then return end
        local function out(line)
            if IsValid(ply)then ply:PrintMessage(HUD_PRINTCONSOLE,line)else print(line)end
        end
        local n=0
        for key,row in pairs(Invites or{})do
            local inv=normalizeInvite(row)
            if inv then
                n=n+1
                local target=inviteTarget(key)
                out(("  %s → %s · от %s · %s · осталось %d с"):format(
                    key,tostring(inv.faction),tostring(inv.fromName),
                    IsValid(target)and("в сети: "..target:Nick())or"персонаж НЕ в сети",
                    math.max(0,inv.expires-os.time())))
            end
        end
        out("[GRM Factions] активных приглашений: "..n)
    end)
    hook.Add("GRM_CharacterChanged","Factions_InviteV2Character",function(ply)timer.Simple(.5,function()resendInvite(ply,true)end)end)
    timer.Create("Factions_InviteV2Expire",5,0,function()local changed=false;for key,row in pairs(Invites or{})do local inv=normalizeInvite(row);if not inv or inv.expires<=os.time()then local target=inviteTarget(key);if IsValid(target)and inv then pushInvite(target,inv,"Срок приглашения истёк")end;Invites[key]=nil;changed=true else Invites[key]=inv end end;if changed then saveInvites(Invites)end end)

    net.Receive(NET_LEAVE, function(_, ply)
        local ok, err = leaveFaction(ply)
        if ok then ply:PrintMessage(HUD_PRINTTALK, "Вы покинули фракцию") broadcastFactionData()
        else ply:PrintMessage(HUD_PRINTTALK, "Ошибка: " .. err) end
    end)

    --[[ Отбывающий административное наказание в эфир не выходит: проверка
         одна на все волны, текст — из модуля банов. ]]
    local function banGate(ply, what)
        return GRM.ServerBan and GRM.ServerBan.DenySpeech and GRM.ServerBan.DenySpeech(ply, what) == true
    end

    net.Receive(NET_RADIO, function(_, ply)
        if banGate(ply, "рация фракции") then return end
        local text = net.ReadString()
        if not text or text == "" then return end
        local steam = memberKey(ply)

        local factionName, role = nil, nil
        for name, f in pairs(Factions) do
            if type(f) == "table" then
                ensureDefaults(f)
                if f.Members[steam] then factionName = name role = f.Members[steam].Role break end
            end
        end

        if not factionName then ply:PrintMessage(HUD_PRINTTALK, "Вы не состоите ни в одной фракции.") return end
        local f = Factions[factionName]
        local rec = (f and f.Members and f.Members[steam]) or {}
        -- Шапка канала: тег фракции + теги отдела и подотдела (если заданы).
        local tag=GRM.Factions.ChannelTag(f,rec.Department,rec.Subdepartment,
            (f and f.Tag and f.Tag~="") and f.Tag or GRM.Factions.DisplayName(factionName),rec.Position)
        tag=GRM.Factions.AppendCID(tag,ply)
        -- Формат как у /gnews: шапка отдельной строкой, дальше имя, должность
        -- и текст — раздельными полями, чтобы клиент раскрасил и перенёс строку.
        local rpName = ply:GetNWString("GRM_RPName", "")
        if rpName == "" then rpName = ply:Nick() end
        local roleName = (GRM.Factions and GRM.Factions.RoleDisplayName)
            and GRM.Factions.RoleDisplayName(f, role) or (role or "Участник")
        local col = (f and f.Color) or { r = 255, g = 200, b = 0 }

        local recipients = {}
        for memberSteam, _ in pairs(Factions[factionName].Members) do
            local target = (GRM.Identity and GRM.Identity.ResolveCharacter and GRM.Identity.ResolveCharacter(memberSteam)) or player.GetBySteamID(memberSteam) or player.GetBySteamID64(memberSteam)
            if IsValid(target) then recipients[#recipients + 1] = target end
        end
        if #recipients > 0 then
            net.Start(NET_RADIO_MSG)
                net.WriteUInt(math.Clamp(math.floor(tonumber(col.r) or 255), 0, 255), 8)
                net.WriteUInt(math.Clamp(math.floor(tonumber(col.g) or 200), 0, 255), 8)
                net.WriteUInt(math.Clamp(math.floor(tonumber(col.b) or 0), 0, 255), 8)
                net.WriteString(tag)
                net.WriteString(rpName)
                net.WriteString(roleName)
                net.WriteString(text)
            net.Send(recipients)
        end
    end)

    --[[ /frb — фракционная рация НОН-РП (OOC). Такого канала в сборке не было:
         у госволны OOC-версия есть (/depb, /db), а у своей рации — нет, и
         сотрудники решали организационные вопросы прямо в РП-эфире.
         Получатели те же, что у /fr — только свои. ]]
    net.Receive(NET_RADIOB, function(_, ply)
        if banGate(ply, "рация фракции (OOC)") then return end
        local text = net.ReadString()
        if not text or text == "" then return end
        local steam = memberKey(ply)

        local factionName, role = nil, nil
        for name, f in pairs(Factions) do
            if type(f) == "table" then
                ensureDefaults(f)
                if f.Members[steam] then factionName = name role = f.Members[steam].Role break end
            end
        end
        if not factionName then ply:PrintMessage(HUD_PRINTTALK, "Вы не состоите ни в одной фракции.") return end

        local f = Factions[factionName]
        local recB = (f and f.Members and f.Members[steam]) or {}
        local tag = GRM.Factions.AppendCID(GRM.Factions.ChannelTag(f,recB.Department,recB.Subdepartment,
            (f and f.Tag and f.Tag ~= "") and f.Tag or GRM.Factions.DisplayName(factionName),recB.Position), ply)
        local rpName = ply:GetNWString("GRM_RPName", "")
        if rpName == "" then rpName = ply:Nick() end
        local roleName = (GRM.Factions and GRM.Factions.RoleDisplayName)
            and GRM.Factions.RoleDisplayName(f, role) or (role or "Участник")
        local col = (f and f.Color) or { r = 255, g = 200, b = 0 }

        local recipients = {}
        for memberSteam, _ in pairs(f.Members) do
            local target = (GRM.Identity and GRM.Identity.ResolveCharacter and GRM.Identity.ResolveCharacter(memberSteam))
                or player.GetBySteamID(memberSteam) or player.GetBySteamID64(memberSteam)
            if IsValid(target) then recipients[#recipients + 1] = target end
        end
        if #recipients > 0 then
            net.Start(NET_RADIOB_MSG)
                net.WriteUInt(math.Clamp(math.floor(tonumber(col.r) or 255), 0, 255), 8)
                net.WriteUInt(math.Clamp(math.floor(tonumber(col.g) or 200), 0, 255), 8)
                net.WriteUInt(math.Clamp(math.floor(tonumber(col.b) or 0), 0, 255), 8)
                net.WriteString(tag)
                net.WriteString(rpName)
                net.WriteString(roleName)
                net.WriteString(text)
            net.Send(recipients)
        end
    end)

    net.Receive(NET_DEP, function(_, ply)
        if banGate(ply, "государственная волна") then return end
        local text = net.ReadString()
        if not text or text == "" then return end
        local steam = memberKey(ply)
        local factionName, role, tag, color, depAccess, depKey, subKey = getFactionInfoForPlayer(steam)
        if not factionName then ply:PrintMessage(HUD_PRINTTALK, "[Волна] Вы не состоите ни в одной фракции.") return end
        if not depAccess then ply:PrintMessage(HUD_PRINTTALK, "[Волна] Ваша фракция не имеет доступа к волне департамента.") return end
        local displayTag=GRM.Factions.AppendCID(GRM.Factions.ChannelTag(Factions and Factions[factionName] or factionName,
            depKey, subKey, GRM.Factions.DisplayName(factionName)), ply)
        -- Как /gnews: поля отдельно, перенос строки и раскраску делает клиент.
        local rpName = ply:GetNWString("GRM_RPName", "")
        if rpName == "" then rpName = ply:Nick() end
        local fData = Factions and Factions[factionName]
        local roleName = (GRM.Factions and GRM.Factions.RoleDisplayName)
            and GRM.Factions.RoleDisplayName(fData or factionName, role) or (role or "Участник")

        local recipients = {}
        for _, target in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(target) then
                local targetFaction, _, _, _, targetAccess = getFactionInfoForPlayer(memberKey(target))
                if targetFaction and targetAccess then recipients[#recipients + 1] = target end
            end
        end
        if #recipients > 0 then
            net.Start(NET_DEP_MSG)
            net.WriteUInt(color.r, 8) net.WriteUInt(color.g, 8) net.WriteUInt(color.b, 8)
            net.WriteString(displayTag)
            net.WriteString(rpName)
            net.WriteString(roleName)
            net.WriteString(text)
            net.Send(recipients)
        end
    end)

    net.Receive(NET_DEPB, function(_, ply)
        if banGate(ply, "государственная волна (OOC)") then return end
        local text = net.ReadString()
        if not text or text == "" then return end
        local steam = memberKey(ply)
        local factionName, role, tag, color, depAccess, depKeyB, subKeyB = getFactionInfoForPlayer(steam)
        if not factionName then ply:PrintMessage(HUD_PRINTTALK, "[Волна] Вы не состоите ни в одной фракции.") return end
        if not depAccess then ply:PrintMessage(HUD_PRINTTALK, "[Волна] Ваша фракция не имеет доступа к волне департамента.") return end
        local displayTag=GRM.Factions.AppendCID(GRM.Factions.ChannelTag(Factions and Factions[factionName] or factionName,
            depKeyB, subKeyB, GRM.Factions.DisplayName(factionName)), ply)
        local rpNameB = ply:GetNWString("GRM_RPName", "")
        if rpNameB == "" then rpNameB = ply:Nick() end
        local fDataB = Factions and Factions[factionName]
        local roleNameB = (GRM.Factions and GRM.Factions.RoleDisplayName)
            and GRM.Factions.RoleDisplayName(fDataB or factionName, role) or (role or "Участник")

        net.Start(NET_DEPB_MSG)
        net.WriteUInt(color.r, 8) net.WriteUInt(color.g, 8) net.WriteUInt(color.b, 8)
        net.WriteString(displayTag)
        net.WriteString(rpNameB)
        net.WriteString(roleNameB)
        net.WriteString(text)
        net.Broadcast()
    end)

    hook.Add("PlayerInitialSpawn", "Factions_SyncOnJoin", function(ply)
        timer.Simple(1, function() if IsValid(ply) then broadcastFactionData() end end)
    end)

    -- ============================================================
    -- ЧАТ-КОМАНДА /factions (для суперадмина и лидера)
    -- ВАЖНО: регистрируем в PlayerSayTransform потому что EasyChat
    -- устанавливает SkipPlayerSay=true для команд и PlayerSay не вызывается!
    -- ============================================================
    hook.Add("PlayerSayTransform", "Factions_ChatCommand", function(ply, datapack)
        if not istable(datapack) then return end
        local text = datapack[1]
        if not isstring(text) then return end

        local lower = string.lower(string.Trim(text))
        if lower == "/factions" then
            if ply:IsSuperAdmin() then
                net.Start(NET_OPEN_ADMIN)
                net.Send(ply)
            else
                local leaderFaction = getFactionOfLeader(ply)
                if leaderFaction then
                    net.Start(NET_OPEN_LEADER)
                    net.Send(ply)
                else
                    local econAccess = GRM.Economy and GRM.Economy.CanManageEconomy and GRM.Economy.CanManageEconomy(ply) == true
                    if econAccess then
                        net.Start(NET_OPEN_ADMIN)
                        net.Send(ply)
                    else
                        ply:PrintMessage(HUD_PRINTTALK, "[Фракции] У вас нет прав для использования этой команды.")
                    end
                end
            end
            datapack.SkipPlayerSay = true
            datapack[1] = ""
            return
        end
    end)

    -- ============================================================
    -- ULX КОМАНДЫ (если ULX установлен)
    -- ============================================================
    if not ULib or not ulx then
        print("[Factions] ULX не найден, ULX-команды не зарегистрированы")
    else
        local cmdFactions = ulx.command("Utility", "ulx factions", function(ply)
            if not ply:IsSuperAdmin() then ply:PrintMessage(HUD_PRINTTALK, "У вас нет прав.") return end
            net.Start(NET_OPEN_ADMIN) net.Send(ply)
        end, "factions")
        cmdFactions:defaultAccess(ULib.ACCESS_SUPERADMIN)

        local cmdLeader = ulx.command("Utility", "ulx factions_leader", function(ply)
            local leaderFaction = getFactionOfLeader(ply)
            if not leaderFaction then ply:PrintMessage(HUD_PRINTTALK, "Вы не являетесь лидером.") return end
            net.Start(NET_OPEN_LEADER) net.Send(ply)
        end, "factions_leader")
        cmdLeader:defaultAccess(ULib.ACCESS_ALL)
    end

    -- ============================================================
    -- Публичный API для модулей GRM (доска набора Код 76, радио Код 75 и др.)
    -- Только экспорт ссылок на уже существующие локальные функции —
    -- логика/сейв/формат данных НЕ меняются.
    -- ============================================================
    _G.FactionsAPI = _G.FactionsAPI or {}
    _G.FactionsAPI.AddMember      = function(factionName, steamID) return addMember(factionName, steamID) end
    _G.FactionsAPI.RemoveMember   = function(factionName, steamID) return removeMember(factionName, steamID) end
    _G.FactionsAPI.GetFactionOf   = function(steamID) return getFactionOfPlayer(steamID) end
    _G.FactionsAPI.GetFactionOfLeader = function(ply) return getFactionOfLeader(ply) end
    _G.FactionsAPI.IsLeader       = function(playerOrKey, factionName)
        local f = Factions[factionName]
        if not istable(f) then return false end
        if isentity(playerOrKey) and IsValid(playerOrKey) and playerOrKey:IsPlayer() then
            return isCharacterLeaderOfFaction(playerOrKey, f)
        end
        local key = memberKey(playerOrKey)
        return f.Leader == key
    end
    _G.FactionsAPI.IsMember       = function(factionName, playerOrKey)
        local f = Factions[factionName]
        if not istable(f) then return false end
        local key = memberKey(playerOrKey)
        return f.Members[key] ~= nil or f.Members[playerOrKey] ~= nil
    end
    _G.FactionsAPI.GetMember      = function(factionName, playerOrKey)
        local f = Factions[factionName]
        if not istable(f) then return nil end
        local key = memberKey(playerOrKey)
        return f.Members[key] or f.Members[playerOrKey]
    end
    _G.FactionsAPI.GetLeader      = function(factionName)
        local f = Factions[factionName]
        return istable(f) and f.Leader or nil
    end
    _G.FactionsAPI.PrimeRole      = function(factionName)
        local f = Factions[factionName]
        return istable(f) and getDefaultMemberRole(f) or nil
    end
    _G.FactionsAPI.GetDisplayName=function(factionName)return GRM.Factions.DisplayName(factionName)end
    _G.FactionsAPI.GetRegistrationName=function(value)local raw=tostring(value or"");if Factions[raw]then return raw end;local found;for name,f in pairs(Factions or{})do if GRM.Factions.DisplayName(f,name)==raw then if found then return nil end;found=name end end;return found end
    _G.FactionsAPI.SetDisplayName=function(factionName,displayName)return setFactionDisplayName(factionName,displayName)end
    _G.FactionsAPI.GetRoleDisplayName=function(factionName,roleKey)return GRM.Factions.RoleDisplayName(factionName,roleKey)end
    _G.FactionsAPI.SetRoleDisplayName=function(factionName,roleKey,displayName)return renameRole(factionName,roleKey,displayName)end
    _G.FactionsAPI.RenameRole=function(factionName,roleKey,displayName)return renameRole(factionName,roleKey,displayName)end
    _G.FactionsAPI.ResolveRoleKey=function(factionName,roleInput)return GRM.Factions.ResolveRoleKey(factionName,roleInput)end
    _G.FactionsAPI.AddSubdepartment=function(factionName,parentDeptId,subdeptKey,displayName,tag,quota)return addSubdepartment(factionName,parentDeptId,subdeptKey,displayName,tag,quota)end
    _G.FactionsAPI.RemoveSubdepartment=function(factionName,subdeptKey)return removeSubdepartment(factionName,subdeptKey)end
    _G.FactionsAPI.RenameSubdepartment=function(factionName,subdeptKey,displayName)return renameSubdepartment(factionName,subdeptKey,displayName)end
    _G.FactionsAPI.SetMemberSubdepartment=function(factionName,steamID,subdept)return setMemberSubdepartment(factionName,steamID,subdept)end
    _G.FactionsAPI.GetSubdepartmentDisplayName=function(factionName,subdeptKey)return GRM.Factions.SubdepartmentDisplayName(factionName,subdeptKey)end
    _G.FactionsAPI.GetSubdepartments=function(factionName,parentDeptId)return GRM.Factions.GetSubdepartments(factionName,parentDeptId)end
    _G.FactionsAPI.Save           = function() saveFactions(Factions) end
    _G.FactionsAPI.List           = function()
        -- Compatibility view for older GRM modules. The persisted table keeps
        -- only CharacterKey records; legacy keys exist only in this snapshot.
        local out = {}
        for name, src in pairs(Factions or {}) do
            if istable(src) then
                local dst = {}
                for k, v in pairs(src) do
                    if k ~= "Members" then dst[k] = v end
                end
                dst.Members = {}
                for key, rec in pairs(src.Members or {}) do
                    dst.Members[key] = rec
                    if istable(rec) and isstring(rec.LegacyKey) and rec.LegacyKey ~= key then
                        dst.Members[rec.LegacyKey] = rec
                    end
                end
                out[name] = dst
            end
        end
        return out
    end
    -- Код 84 (Root Guard): прямое удаление — ВЫЗЫВАТЬ ТОЛЬКО из одобренного
    -- исполнителя Root Guard (обходной путь для уже подтверждённых заявок).
    _G.FactionsAPI.DeleteFaction  = function(factionName) return deleteFaction(factionName) end
    _G.FactionsAPI.Broadcast      = function() broadcastFactionData() end
    -- Код 76 v1.1.0 (доска: автоназначение отдела/должности при вступлении):
    _G.FactionsAPI.SetMemberRole       = function(factionName, steamID, role) return setMemberRole(factionName, steamID, role) end
    _G.FactionsAPI.SetMemberDepartment = function(factionName, steamID, dept) return setMemberDepartment(factionName, steamID, dept) end

    print("[Factions] Серверная часть загружена (v3.2 dual names + /factions)")
end

-- ============================================================
-- CLIENT
-- ============================================================
if CLIENT then
    pcall(include, "autorun/client/cl_grm_factions_unified_ui.lua")
    -- Ссылки на живые панели окна фракций. Таблица ЛОКАЛЬНАЯ: раньше
    -- имя `ui` было глобальным и делилось со всеми аддонами сервера —
    -- любой чужой скрипт с такой же переменной затирал наши панели.
    local ui = {}

    --[[ ФОРВАРД-ДЕКЛАРАЦИИ ОБНОВЛЕНИЙ ОКНА.
         Эти функции зовут друг друга и обработчики net вперемешку, часть
         вызовов стоит выше определений. Раньше они объявлялись просто как
         `function имя(...)` — то есть уходили в ГЛОБАЛЬНОЕ пространство
         имён сервера и клиента. Восемь безымянных `updateRanksList`,
         `refreshAllUI` и подобных в общем namespace — прямая заявка на
         конфликт с любым чужим аддоном. Держим локально, а порядок
         вызовов обеспечиваем декларацией здесь. ]]
    local refreshAllUI, updateLeaderRanks, updateLeaderDepartments
    local updateLeaderMemberList, updateRanksList, updateDepartmentsList
    local updateMemberListForFaction, updateDepWavePanel
    FactionsData = FactionsData or {}
    FactionCharacterChoices = FactionCharacterChoices or {}
    local pendingActionCallback = nil
    local pendingDataCallback   = nil
    -- Кэш имён по SteamID. `nameCache or {}` справа читало ГЛОБАЛ (локала
    -- ещё нет в этой точке) — то есть всегда nil, и «или» просто создавало
    -- пустую таблицу. Пишем честно, без иллюзии переиспользования.
    local nameCache             = {}

    -- Цвета UI
    local THEME = {
        bg          = Color(25, 25, 30, 245),
        bgLight     = Color(35, 35, 42, 240),
        bgHover     = Color(50, 50, 60, 250),
        accent      = Color(80, 160, 255),
        accentDark  = Color(50, 120, 200),
        text        = Color(220, 220, 230),
        textDim     = Color(150, 150, 165),
        success     = Color(60, 200, 100),
        danger      = Color(220, 60, 60),
        dangerHover = Color(180, 40, 40),
        border      = Color(60, 60, 75),
        separator   = Color(55, 55, 70),
    }

    surface.CreateFont("Factions_Title", { font = "Roboto", size = 20, weight = 700, antialias = true })
    surface.CreateFont("Factions_Normal", { font = "Roboto", size = 14, weight = 500, antialias = true })
    surface.CreateFont("Factions_Small",  { font = "Roboto", size = 12, weight = 400, antialias = true })
    surface.CreateFont("Factions_HUD",    { font = "Roboto", size = 16, weight = 700, antialias = true })
    surface.CreateFont("Factions_InviteTitle",{font="Roboto",size=28,weight=900,extended=true})
    surface.CreateFont("Factions_InviteBody",{font="Roboto",size=16,weight=600,extended=true})

    local inviteFrame,inviteData
    local function sendInviteDecision(op)
        if not inviteData or inviteData.pending then return end;inviteData.pending=true;net.Start(NET_INVITE_ACTION);net.WriteString(op);net.WriteString(inviteData.id);net.SendToServer();if IsValid(inviteFrame)then for _,child in ipairs(inviteFrame:GetChildren())do if child.SetEnabled then child:SetEnabled(false)end end end
    end
    local function closeInvite(reason)
        if IsValid(inviteFrame)then inviteFrame:Remove()end;inviteFrame=nil;inviteData=nil;if reason and reason~=""then notification.AddLegacy(reason,NOTIFY_GENERIC,6);surface.PlaySound("buttons/button15.wav")end
    end
    local function openInvite(data)
        if IsValid(inviteFrame)then inviteFrame:Remove()end;inviteData=data;local f=vgui.Create("DFrame");inviteFrame=f;f:SetSize(760,440);f:Center();f:MakePopup();f:SetTitle("");f:ShowCloseButton(false);f:SetDeleteOnClose(true);if GRM.UI then GRM.UI.Track("factions.invite",f)end
        f.Paint=function(_,w,h)draw.RoundedBox(12,0,0,w,h,Color(10,15,24,252));draw.RoundedBoxEx(12,0,0,w,76,Color(24,36,54),true,true,false,false);draw.SimpleText("ОФИЦИАЛЬНОЕ ПРИГЛАШЕНИЕ","Factions_Small",24,19,Color(90,180,255));draw.SimpleText(data.display,"Factions_InviteTitle",24,47,color_white,TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER);draw.SimpleText("Регистрационное имя: "..data.faction,"Factions_Small",w-24,48,Color(135,155,180),TEXT_ALIGN_RIGHT,TEXT_ALIGN_CENTER)end
        local from=vgui.Create("DLabel",f);from:SetPos(24,98);from:SetSize(712,30);from:SetFont("Factions_InviteBody");from:SetTextColor(Color(220,230,240));from:SetText("Приглашение выдал:  "..data.fromName)
        local assignment=vgui.Create("DPanel",f);assignment:SetPos(24,145);assignment:SetSize(712,108);assignment.Paint=function(_,w,h)draw.RoundedBox(8,0,0,w,h,Color(22,31,44));draw.SimpleText("НАЗНАЧЕНИЕ ПОСЛЕ ВСТУПЛЕНИЯ","Factions_Small",18,18,Color(90,180,255));draw.SimpleText("Звание:  "..(data.role~=""and data.role or"Участник"),"Factions_InviteBody",18,49,color_white);draw.SimpleText("Отдел:  "..(data.department~=""and data.department or"не назначен"),"Factions_InviteBody",18,78,Color(195,205,220))end
        local terms=vgui.Create("DLabel",f);terms:SetPos(24,270);terms:SetSize(712,45);terms:SetWrap(true);terms:SetFont("Factions_Normal");terms:SetTextColor(Color(150,165,185));terms:SetText("Принимая приглашение, вы вступаете выбранным персонажем. Одновременно состоять в нескольких фракциях нельзя.")
        local timerLabel=vgui.Create("DLabel",f);timerLabel:SetPos(24,322);timerLabel:SetSize(250,30);timerLabel:SetFont("Factions_InviteBody");timerLabel:SetTextColor(Color(255,205,90));timerLabel._next=0;timerLabel.Think=function(self)if CurTime()<self._next then return end;self._next=CurTime()+.2;local left=math.max(0,data.expires-os.time());self:SetText("Осталось: "..math.floor(left/60)..":"..string.format("%02d",left%60));if left<=0 then closeInvite("Срок приглашения истёк")end end
        local decline=vgui.Create("DButton",f);decline:SetPos(392,350);decline:SetSize(160,54);decline:SetText("ОТКЛОНИТЬ");decline:SetFont("Factions_InviteBody");decline:SetTextColor(color_white);decline.Paint=function(s,w,h)draw.RoundedBox(7,0,0,w,h,s:IsHovered()and Color(185,65,75)or Color(135,48,58))end;decline.DoClick=function()sendInviteDecision("decline")end
        local accept=vgui.Create("DButton",f);accept:SetPos(564,350);accept:SetSize(172,54);accept:SetText("ПРИНЯТЬ");accept:SetFont("Factions_InviteBody");accept:SetTextColor(color_white);accept.Paint=function(s,w,h)draw.RoundedBox(7,0,0,w,h,s:IsHovered()and Color(65,210,130)or Color(45,160,98))end;accept.DoClick=function()sendInviteDecision("accept")end
        f.OnRemove=function()if inviteFrame==f then inviteFrame=nil end end;surface.PlaySound("buttons/button24.wav")
    end
    net.Receive(NET_INVITE_OPEN,function()local active=net.ReadBool();if not active then closeInvite(net.ReadString())return end;openInvite({id=net.ReadString(),faction=net.ReadString(),display=net.ReadString(),fromName=net.ReadString(),role=net.ReadString(),department=net.ReadString(),expires=net.ReadUInt(32)})end)

    local function installClientFactionAliases(data)
        for _, f in pairs(data or {}) do
            if istable(f) and istable(f.Members) then
                local raw = f.Members
                setmetatable(raw, { __index = function(t, key)
                    local ck = tostring(key or "")
                    if not ck:match(":char[1-3]$") then
                        if ck:match("^%d+$") then ck = ck .. ":char1"
                        elseif util.SteamIDTo64 then
                            local s64 = util.SteamIDTo64(ck)
                            if s64 and s64 ~= "0" then ck = tostring(s64) .. ":char1" end
                        end
                    end
                    return rawget(t, ck)
                end })
            end
        end
        return data
    end

    local function clientMemberKey(ply)
        if GRM.Identity and GRM.Identity.CharacterKey then return GRM.Identity.CharacterKey(ply) end
        return IsValid(ply) and ply:SteamID() or ""
    end

    local function clientIsLeaderOfFaction(f)
        local ply = LocalPlayer()
        if not IsValid(ply) or not istable(f) then return false end
        return isCharacterLeaderOfFaction(ply, f)
    end

    local function clientGetLeaderFaction(data)
        local ply = LocalPlayer()
        if not IsValid(ply) then return nil end
        for name, f in pairs(data or FactionsData or {}) do
            if istable(f) and isCharacterLeaderOfFaction(ply, f) then
                return name, f
            end
        end
        return nil
    end

    local function safeScrollClear(scroll)
        if IsValid(scroll) and isfunction(scroll.GetCanvas) and IsValid(scroll:GetCanvas()) then
            scroll:Clear()
        end
    end

    local function populateOnlinePlayerCombo(combo, targetEntry)
        if not IsValid(combo) then return end
        combo:Clear()
        combo:AddChoice("-- Выберите активного персонажа онлайн --", "")
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(p) and not p:IsBot() then
                local rpName = (p.GetNWString and p:GetNWString("GRM_RPName", ""))
                if not isstring(rpName) or rpName == "" then rpName = p:Nick() end
                local charKey = (GRM.Identity and isfunction(GRM.Identity.CharacterKey) and GRM.Identity.CharacterKey(p)) or p:SteamID()
                local label = tostring(rpName) .. " [" .. tostring(p:Nick()) .. "] (" .. tostring(p:SteamID()) .. ")"
                combo:AddChoice(label, charKey)
            end
        end
    end

    --[[ Приём дельты: сервер шлёт только изменившиеся организации.
         mode = "full"   — заменяем запись целиком;
         mode = "public" — обновляем публичную часть (название, тэг, цвет),
                           не затирая уже известный состав. ]]
    -- Полный снимок, пришедший частями.
    if GRM.Net and GRM.Net.Receive then
        GRM.Net.Receive("factions.full", function(data)
            FactionsData = installClientFactionAliases(istable(data) and data or {})
            if refreshAllUI then pcall(refreshAllUI, FactionsData) end
            hook.Run("GRM_FactionUIRefreshed", FactionsData)
        end)
    end

    net.Receive(NET_SYNC_DELTA, function()
        local payload = net.ReadTable() or {}
        FactionsData = istable(FactionsData) and FactionsData or {}

        local mode = tostring(payload.mode or "full")
        for name, row in pairs(istable(payload.changed) and payload.changed or {}) do
            if mode == "public" then
                local cur = istable(FactionsData[name]) and FactionsData[name] or {}
                for key, value in pairs(row) do cur[key] = value end
                FactionsData[name] = cur
            else
                FactionsData[name] = row
            end
        end

        for _, name in ipairs(istable(payload.removed) and payload.removed or {}) do
            FactionsData[name] = nil
        end

        -- Алиасы ключей участников (SteamID → SteamID64:charN) нужны и дельте:
        -- без них поиск члена организации на клиенте перестал бы работать.
        FactionsData = installClientFactionAliases(FactionsData)
        if refreshAllUI then pcall(refreshAllUI, FactionsData) end
        hook.Run("GRM_FactionUIRefreshed", FactionsData)
    end)

    net.Receive(NET_SYNC_ALL, function()
        FactionsData = installClientFactionAliases(net.ReadTable() or {})
        refreshAllUI(FactionsData)
    end)

    net.Receive(NET_CHARACTER_CHOICES, function()
        FactionCharacterChoices = net.ReadTable() or {}
    end)

    if GRM.Net and GRM.Net.Receive then
        GRM.Net.Receive(NET_CHARACTER_CHOICES, function(data)
            FactionCharacterChoices = istable(data) and data or {}
        end)
    end

    --[[ Единый вывод служебных каналов — ровно как у /gnews:
             [Канал] [ТЭГ]
             Имя (Должность): текст
         Шапка с тэгом идёт отдельной строкой (\n после тэга), имя, должность
         и сам текст раскрашиваются раздельно. Раньше /dep и /fr клеили всё в
         одну длинную строку одним цветом, и на длинных сообщениях волна
         превращалась в нечитаемое полотно. ]]
    --[[ Единый вывод канала (заказ владельца 18.08 по цветам):
           prefixColor — цвет заголовка канала («[Рация]», «[Волна]»);
           tagColor    — цвет тэга организации в квадратных скобках;
           bodyColor   — цвет ИМЕНИ, ДОЛЖНОСТИ И ТЕКСТА (одним цветом).
         Раньше имя всегда рисовалось голубым, должность — светло-серой, а
         текст — белым, из-за чего «золотая рация» выглядела разноцветной. ]]
    local function printChannel(prefix, prefixColor, tagColor, tag, name, role, text, bodyColor)
        bodyColor = bodyColor or Color(255, 255, 255)
        chat.AddText(
            prefixColor, prefix,
            tagColor, "[" .. tostring(tag or "") .. "]\n",
            bodyColor, tostring(name or ""),
            bodyColor, " (" .. tostring(role or "Участник") .. "): ",
            bodyColor, tostring(text or "")
        )
    end

    -- Цвета каналов держим в одном месте, чтобы не разъезжались.
    local CH_RADIO_GOLD = Color(255, 200, 0)     -- рация: весь текст золотой
    local CH_RADIO_TAG  = Color(225, 60, 60)     -- первый тэг рации — красный
    local CH_DEP_WINE   = Color(170, 45, 60)     -- госволна: всё бордовое

    net.Receive(NET_RADIO_MSG, function()
        local r, g, b = net.ReadUInt(8), net.ReadUInt(8), net.ReadUInt(8)
        local tag, name, role, text = net.ReadString(), net.ReadString(), net.ReadString(), net.ReadString()
        -- Рация: заголовок и весь текст золотые, тэг организации — красный.
        printChannel("[Рация] ", CH_RADIO_GOLD, CH_RADIO_TAG, tag, name, role, text, CH_RADIO_GOLD)
    end)

    net.Receive(NET_RADIOB_MSG, function()
        local r, g, b = net.ReadUInt(8), net.ReadUInt(8), net.ReadUInt(8)
        local tag, name, role, text = net.ReadString(), net.ReadString(), net.ReadString(), net.ReadString()
        -- OOC-рация остаётся приглушённой: её нарочно видно как «не РП».
        printChannel("[Рация OOC] ", Color(150, 160, 175), CH_RADIO_TAG, tag, name,
            "(( " .. tostring(role) .. " ))", "(( " .. tostring(text) .. " ))", Color(170, 180, 195))
    end)

    net.Receive(NET_DEP_MSG, function()
        -- Цвет фракции читаем для тэга, но сам канал остаётся единым
        -- бордово-тёмно-красным — как и было задумано для госволны.
        local r, g, b = net.ReadUInt(8), net.ReadUInt(8), net.ReadUInt(8)
        local tag, name, role, text = net.ReadString(), net.ReadString(), net.ReadString(), net.ReadString()
        -- Госволна: заголовок, тэг, имя, должность и текст — одним бордовым.
        printChannel("[Волна] ", CH_DEP_WINE, CH_DEP_WINE, tag, name, role, text, CH_DEP_WINE)
    end)

    net.Receive(NET_DEPB_MSG, function()
        local r, g, b = net.ReadUInt(8), net.ReadUInt(8), net.ReadUInt(8)
        local tag, name, role, text = net.ReadString(), net.ReadString(), net.ReadString(), net.ReadString()
        printChannel("[Волна OOC] ", CH_DEP_WINE, CH_DEP_WINE, tag, name,
            "(( " .. tostring(role) .. " ))", "(( " .. tostring(text) .. " ))", CH_DEP_WINE)
    end)

    net.Receive(NET_ACTION_RESULT, function()
        local success = net.ReadBool()
        local msg     = net.ReadString()
        if pendingActionCallback then
            local cb = pendingActionCallback
            pendingActionCallback = nil
            cb(success, msg)
        end
    end)

    net.Receive(NET_SEND_DATA, function()
        local data = installClientFactionAliases(net.ReadTable() or {})
        FactionsData = data
        if pendingDataCallback then
            local cb = pendingDataCallback
            pendingDataCallback = nil
            cb(data)
        end
    end)

    local function sendAction(action, args, callback)
        local safeArgs = {}
        for i, v in ipairs(args or {}) do
            local t = type(v)
            if t == "string" or t == "number" or t == "boolean" or t == "table" then
                safeArgs[i] = v
            elseif t ~= "nil" then
                safeArgs[i] = tostring(v)
            end
        end
        net.Start(NET_ACTION)
        net.WriteString(action)
        net.WriteTable(safeArgs)
        net.SendToServer()
        if callback then pendingActionCallback = callback end
    end

    local function requestData(callback)
        net.Start(NET_GET_DATA)
        net.SendToServer()
        if callback then pendingDataCallback = callback end
    end

    local function getData(callback)
        requestData(callback)
    end

    local function getPlayerName(steamID, callback)
        if not steamID or steamID == "" then callback("Нет") return end
        if nameCache[steamID] then callback(nameCache[steamID]) return end
        local steam64 = util.SteamIDTo64(steamID)
        if not steam64 or steam64 == "0" then
            nameCache[steamID] = steamID
            callback(steamID)
            return
        end
        steamworks.RequestPlayerInfo(steam64, function(name)
            nameCache[steamID] = name or steamID
            callback(nameCache[steamID])
        end)
    end

    -- Стилизованная кнопка
    local function styledButton(parent, text, color, hoverColor, textColor)
        local btn = vgui.Create("DButton", parent)
        btn:SetText(text)
        btn:SetFont("Factions_Normal")
        btn:SetTextColor(textColor or Color(255, 255, 255))
        function btn:Paint(w, h)
            local c = self:IsHovered() and (hoverColor or THEME.accentDark) or (color or THEME.accent)
            draw.RoundedBox(4, 0, 0, w, h, c)
        end
        return btn
    end

    local function confirmInvite(factionName,targetKey,role,department,onConfirm)
        local fData=FactionsData and FactionsData[factionName]or{};local display=GRM.Factions.DisplayName(fData,factionName);local w=vgui.Create("DFrame");w:SetSize(610,315);w:Center();w:MakePopup();w:SetTitle("");w:ShowCloseButton(false);w.Paint=function(_,pw,ph)draw.RoundedBox(10,0,0,pw,ph,Color(12,18,27,252));draw.RoundedBoxEx(10,0,0,pw,64,Color(25,38,56),true,true,false,false);draw.SimpleText("ПОДТВЕРЖДЕНИЕ ПРИГЛАШЕНИЯ","Factions_Title",20,32,color_white,TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER)end
        local text=vgui.Create("DLabel",w);text:SetPos(20,82);text:SetSize(570,145);text:SetWrap(true);text:SetFont("Factions_InviteBody");text:SetTextColor(Color(215,225,238));text:SetText("Фракция:  "..display.."\nРегистрационное имя:  "..factionName.."\nПерсонаж:  "..targetKey.."\nЗвание:  "..(role~=""and role or"по умолчанию").."\nОтдел:  "..(department~=""and department or"не назначен").."\n\nПриглашение будет действительно 5 минут.")
        local cancel=styledButton(w,"ОТМЕНА",Color(110,55,65),Color(165,65,75));cancel:SetPos(280,242);cancel:SetSize(140,46);cancel.DoClick=function()w:Close()end
        local send=styledButton(w,"ОТПРАВИТЬ",Color(45,155,98),Color(65,210,130));send:SetPos(432,242);send:SetSize(158,46);send.DoClick=function()send:SetEnabled(false);w:Close();onConfirm()end
        if GRM.UI then GRM.UI.Track("factions.invite.confirm",w)end
    end

    -- Стилизованная панель-секция
    local function sectionPanel(parent, title)
        local panel = vgui.Create("DPanel", parent)
        panel:Dock(TOP) panel:SetTall(30) panel:DockMargin(0, 8, 0, 4) panel:SetPaintBackground(true)
        function panel:Paint(w, h)
            surface.SetDrawColor(THEME.separator)
            surface.DrawRect(0, h - 1, w, 1)
            draw.SimpleText(title, "Factions_Normal", 4, h / 2, THEME.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        return panel
    end

    local function rebuildFactionCombos(data)
        local combos = {
            ui.factionCombo,
            ui.factionCombo3,
            ui.factionComboList,
            ui.factionComboRanks,
            ui.factionComboDepts,
            ui.factionComboDepWave,
            ui.factionComboIncasso
        }
        -- Сортируем имена фракций по алфавиту
        local names = {}
        for n, f in pairs(data or {}) do
            if isstring(n) and n ~= "" and istable(f) then names[#names+1] = n end
        end
        table.sort(names)
        for _, combo in ipairs(combos) do
            if IsValid(combo) then
                local selected = combo:GetValue()
                -- Важно: блокируем OnSelect на время Clear+AddChoice, чтобы он
                -- не дёргал updateIncassoPanel в процессе заполнения.
                local oldOnSelect = combo.OnSelect
                combo.OnSelect = nil
                combo:Clear()
                for _, name in ipairs(names) do combo:AddChoice(name) end
                combo.OnSelect = oldOnSelect
                if selected and data and istable(data[selected]) then
                    combo:SetValue(selected)
                elseif #names > 0 and not selected then
                    combo:SetValue(names[1])
                end
                combo:InvalidateLayout(true)
            end
        end
    end

    -- ============================================================
    -- refreshAllUI — FIX: запрашивает данные с сервера если пусто
    -- ============================================================
    refreshAllUI = function(data)
        -- Если данные не переданы и локальный кеш пуст — запросить с сервера
        if not data and (not FactionsData or table.Count(FactionsData) == 0) then
            getData(function(freshData)
                FactionsData = freshData or {}
                refreshAllUI(FactionsData)
            end)
            return
        end

        data = data or FactionsData
        FactionsData = data

        rebuildFactionCombos(data)

        if IsValid(ui.listView) then
            ui.listView:Clear()
            for name, f in pairs(data or {}) do
                if isstring(name) and istable(f) then
                    local leaderStr = f.Leader or "Нет"
                    local count = table.Count(f.Members or {})
                    local tagStr = (f.Tag and f.Tag ~= "") and ("[" .. f.Tag .. "] ") or ""
                    ui.listView:AddLine(tagStr..GRM.Factions.DisplayName(f,name),name,leaderStr,count)
                end
            end
        end

        updateLeaderRanks(data)
        updateLeaderDepartments(data)
        updateLeaderMemberList(data)
        updateDepWavePanel(data)

        -- Код 126: обновляем вкладку Инкассации если открыта; если фракция не выбрана — берём первую
        if IsValid(ui.factionComboIncasso) and ui.updateIncassoPanel then
            local fName = ui.factionComboIncasso:GetValue()
            if (not fName or fName == "" or not data[fName] or not istable(data[fName])) then
                -- Автовыбор первой фракции из отсортированного списка
                local names = {}
                for n, f in pairs(data or {}) do
                    if isstring(n) and n ~= "" and istable(f) then names[#names + 1] = n end
                end
                table.sort(names)
                if #names > 0 then
                    fName = names[1]
                    ui.factionComboIncasso:SetValue(fName)
                end
            end
            if fName and fName ~= "" and data[fName] and istable(data[fName]) then
                ui.updateIncassoPanel(fName, data)
            end
        end

        -- ══════════════════════════════════════════════════════════════
        -- Код 108 (заказ владельца): «живые» вкладки. Раньше админские
        -- «Ранги»/«Отделы»/«Список» и комбо ролей/отделов строились ОДИН
        -- раз при выборе фракции — пока не перевыбраешь/не перезапустишь
        -- меню, изменения (свои же и чужие, прилетевшие SYNC_ALL-рассылкой)
        -- на экране не появлялись. Теперь ВСЯКИЙ refreshAllUI перестраивает
        -- текущие вкладки по свежим данным — меню закрывать не надо.
        -- ══════════════════════════════════════════════════════════════
        local function selOf(combo)
            if not IsValid(combo) then return nil end
            local v = combo:GetValue()
            if isstring(v) and v ~= "" and data and data[v] then return v end
            return nil
        end

        -- админская вкладка «Ранги»
        local rFac = selOf(ui.factionComboRanks)
        if IsValid(ui.ranksScroll) then
            if rFac then updateRanksList(rFac, data) else safeScrollClear(ui.ranksScroll) end
        end
        -- админская вкладка «Отделы»
        local dFac = selOf(ui.factionComboDepts)
        if IsValid(ui.deptsScroll) then
            if dFac then updateDepartmentsList(dFac, data) else safeScrollClear(ui.deptsScroll) end
        end
        -- админская вкладка «Список» (участники фракции)
        local lFac = selOf(ui.factionComboList)
        if IsValid(ui.memberScroll) then
            if lFac then updateMemberListForFaction(lFac, data) else safeScrollClear(ui.memberScroll) end
        end

        -- комбо ролей/отделов во вкладках «Участники» — тоже живые:
        -- пересобираем списки, выбранное значение сохраняем, если осталось
        local function rebuildRoleDeptCombos(facName, roleCombo, deptCombo)
            if not (IsValid(roleCombo) and IsValid(deptCombo)) then return end
            local f = (facName and data) and data[facName] or nil
            local selR = roleCombo:GetValue()
            local selD = deptCombo:GetValue()
            roleCombo:Clear()
            deptCombo:Clear()
            if istable(f) then
                for _, r in ipairs(f.Roles or {}) do roleCombo:AddChoice(r) end
                for _, d in ipairs(f.Departments or {}) do deptCombo:AddChoice(d) end
                -- выбор сохраняем, если ещё жив; умер — поле гасим явно
                -- (DComboBox:Clear может держать старый текст — находка 125)
                if isstring(selR) and table.HasValue(f.Roles or {}, selR) then roleCombo:SetValue(selR)
                else roleCombo:SetValue("") end
                if isstring(selD) and table.HasValue(f.Departments or {}, selD) then deptCombo:SetValue(selD)
                else deptCombo:SetValue("") end
            else
                roleCombo:SetValue("")
                deptCombo:SetValue("")
            end
        end
        rebuildRoleDeptCombos(selOf(ui.factionCombo3), ui.roleCombo3, ui.deptCombo3)

        -- лидерская вкладка «Участники»: фракция — его собственная
        if IsValid(ui.roleComboLeader) and IsValid(ui.deptComboLeader) then
            local myLead = clientGetLeaderFaction(data)
            rebuildRoleDeptCombos(myLead, ui.roleComboLeader, ui.deptComboLeader)
        end
        hook.Run("GRM_FactionUIRefreshed",data)
    end

    -- ============================================================
    -- ЛИДЕР: РАНГИ
    -- ============================================================
    updateLeaderRanks = function(data)
        if not IsValid(ui.ranksScrollLeader) then return end
        local scroll = ui.ranksScrollLeader
        safeScrollClear(scroll)

        local factionName, f = clientGetLeaderFaction(data)
        if not factionName or not f then return end

        local roles = f.Roles or {}
        for _, roleName in ipairs(roles) do
            local row = vgui.Create("DPanel", scroll)
            row:SetTall(36) row:Dock(TOP) row:DockMargin(0, 2, 0, 2) row:SetPaintBackground(false)

            local edit = vgui.Create("DTextEntry", row)
            edit:SetPos(70, 5) edit:SetSize(160, 26)
            edit:SetText(GRM.Factions.RoleDisplayName(f, roleName))
            edit:SetTooltip("Системный ключ: " .. roleName .. " (настройки и участники останутся привязаны)")
            edit:SetFont("Factions_Normal")

            local leaderRoleName = (f and f.LeaderRoleName) or "Лидер"
            local isLeader = (roleName == leaderRoleName)

            if not isLeader then
                local btnUp = styledButton(row, "▲", THEME.bgLight, THEME.bgHover, THEME.text)
                btnUp:SetPos(5, 5) btnUp:SetSize(28, 26)
                btnUp.DoClick = function()
                    sendAction("moveRole", { roleName, "up" }, function(ok, msg)
                        if ok then notification.AddLegacy("Роль перемещена", NOTIFY_GENERIC, 3) refreshAllUI()
                        else notification.AddLegacy("Ошибка: " .. msg, NOTIFY_ERROR, 3) end
                    end)
                end

                local btnDown = styledButton(row, "▼", THEME.bgLight, THEME.bgHover, THEME.text)
                btnDown:SetPos(37, 5) btnDown:SetSize(28, 26)
                btnDown.DoClick = function()
                    sendAction("moveRole", { roleName, "down" }, function(ok, msg)
                        if ok then notification.AddLegacy("Роль перемещена", NOTIFY_GENERIC, 3) refreshAllUI()
                        else notification.AddLegacy("Ошибка: " .. msg, NOTIFY_ERROR, 3) end
                    end)
                end
            end

            local btnRename = styledButton(row, "✎", THEME.accent, THEME.accentDark)
            btnRename:SetPos(240, 5) btnRename:SetSize(36, 26)
            btnRename.DoClick = function()
                local newName = edit:GetText()
                if newName == "" or newName == roleName then return end
                sendAction("renameRole", { roleName, newName }, function(ok, msg)
                    if ok then notification.AddLegacy("Роль переименована", NOTIFY_GENERIC, 3) refreshAllUI()
                    else notification.AddLegacy("Ошибка: " .. msg, NOTIFY_ERROR, 3) edit:SetText(roleName) end
                end)
            end
            edit.OnEnter = function() if IsValid(btnRename) then btnRename:DoClick() end end

            if not isLeader then
                local btnRemove = styledButton(row, "✕", THEME.danger, THEME.dangerHover)
                btnRemove:SetPos(342,5) btnRemove:SetSize(36, 26)
                btnRemove.DoClick = function()
                    sendAction("removeRole", { roleName }, function(ok, msg)
                        if ok then notification.AddLegacy("Роль удалена", NOTIFY_GENERIC, 3) refreshAllUI()
                        else notification.AddLegacy("Ошибка: " .. msg, NOTIFY_ERROR, 3) end
                    end)
                end
            else
                local lblLeader = vgui.Create("DLabel", row)
                lblLeader:SetPos(282, 8) lblLeader:SetSize(60, 20)
                lblLeader:SetText("★ Лидер") lblLeader:SetFont("Factions_Small")
                lblLeader:SetTextColor(Color(255, 220, 80))
            end
        end

        local addPanel = vgui.Create("DPanel", scroll)
        addPanel:SetTall(40) addPanel:Dock(TOP) addPanel:DockMargin(0, 6, 0, 4) addPanel:SetPaintBackground(false)

        local lbl = vgui.Create("DLabel", addPanel)
        lbl:SetText("Новая роль:") lbl:SetPos(10, 10) lbl:SetSize(80, 20) lbl:SetFont("Factions_Normal")
        lbl:SetTextColor(THEME.text)

        local newEntry = vgui.Create("DTextEntry", addPanel)
        newEntry:SetPos(100, 7) newEntry:SetSize(160, 26) newEntry:SetPlaceholderText("Введите название")
        newEntry:SetFont("Factions_Normal")

        local btnAdd = styledButton(addPanel, "+ Добавить", THEME.success, Color(40, 160, 80))
        btnAdd:SetPos(270, 7) btnAdd:SetSize(100, 26)
        btnAdd.DoClick = function()
            local newRole = newEntry:GetText()
            if newRole == "" then return end
            sendAction("addRole", { newRole }, function(ok, msg)
                if ok then notification.AddLegacy("Роль добавлена", NOTIFY_GENERIC, 3) if IsValid(newEntry) then newEntry:SetText("") end refreshAllUI()
                else notification.AddLegacy("Ошибка: " .. msg, NOTIFY_ERROR, 3) end
            end)
        end
        newEntry.OnEnter = function() if IsValid(btnAdd) then btnAdd:DoClick() end end
    end

    -- ============================================================
    -- ЛИДЕР: ОТДЕЛЫ
    -- ============================================================
    updateLeaderDepartments = function(data)
        if not IsValid(ui.deptsScrollLeader) then return end
        local scroll = ui.deptsScrollLeader
        safeScrollClear(scroll)

        local factionName, f = clientGetLeaderFaction(data)
        if not factionName or not f then return end

        local departments = f.Departments or {}
        for _, deptName in ipairs(departments) do
            local row = vgui.Create("DPanel", scroll)
            row:SetTall(36) row:Dock(TOP) row:DockMargin(0, 2, 0, 2) row:SetPaintBackground(false)

            local btnUp = styledButton(row, "▲", THEME.bgLight, THEME.bgHover, THEME.text)
            btnUp:SetPos(5, 5) btnUp:SetSize(28, 26)
            btnUp.DoClick = function()
                sendAction("moveDepartment", { deptName, "up" }, function(ok, msg)
                    if ok then notification.AddLegacy("Отдел перемещён", NOTIFY_GENERIC, 3) refreshAllUI()
                    else notification.AddLegacy("Ошибка: " .. msg, NOTIFY_ERROR, 3) end
                end)
            end

            local btnDown = styledButton(row, "▼", THEME.bgLight, THEME.bgHover, THEME.text)
            btnDown:SetPos(37, 5) btnDown:SetSize(28, 26)
            btnDown.DoClick = function()
                sendAction("moveDepartment", { deptName, "down" }, function(ok, msg)
                    if ok then notification.AddLegacy("Отдел перемещён", NOTIFY_GENERIC, 3) refreshAllUI()
                    else notification.AddLegacy("Ошибка: " .. msg, NOTIFY_ERROR, 3) end
                end)
            end

            local edit=vgui.Create("DTextEntry",row);edit:SetPos(70,5);edit:SetSize(220,26);local departmentDisplay=GRM.Factions.DepartmentDisplayName(f,deptName);edit:SetText(departmentDisplay);edit:SetPlaceholderText("Публичное название");edit:SetTooltip("Системный ключ: "..deptName..". Настройки и участники останутся привязаны к нему.");edit:SetFont("Factions_Normal")

            local btnRename=styledButton(row,"✎",THEME.accent,THEME.accentDark);btnRename:SetPos(300,5);btnRename:SetSize(36,26)
            btnRename.DoClick = function()
                local newName = edit:GetText()
                if newName==""or newName==departmentDisplay then return end
                sendAction("renameDepartment", { deptName, newName }, function(ok, msg)
                    if ok then notification.AddLegacy("Название отдела обновлено", NOTIFY_GENERIC, 3) refreshAllUI()
                    else notification.AddLegacy("Ошибка: " .. msg, NOTIFY_ERROR, 3) edit:SetText(departmentDisplay) end
                end)
            end

            if #departments > 1 then
                local btnRemove = styledButton(row, "✕", THEME.danger, THEME.dangerHover)
                btnRemove:SetPos(342,5) btnRemove:SetSize(36, 26)
                btnRemove.DoClick = function()
                    sendAction("removeDepartment", { deptName }, function(ok, msg)
                        if ok then notification.AddLegacy("Отдел удалён", NOTIFY_GENERIC, 3) refreshAllUI()
                        else notification.AddLegacy("Ошибка: " .. msg, NOTIFY_ERROR, 3) end
                    end)
                end
            else
                local lblLast = vgui.Create("DLabel", row)
                lblLast:SetPos(282, 8) lblLast:SetSize(100, 20)
                lblLast:SetText("(последний)") lblLast:SetFont("Factions_Small")
                lblLast:SetTextColor(THEME.textDim)
            end
        end

        local addPanel = vgui.Create("DPanel", scroll)
        addPanel:SetTall(40) addPanel:Dock(TOP) addPanel:DockMargin(0, 5, 0, 0) addPanel:SetPaintBackground(false)

        local lbl = vgui.Create("DLabel", addPanel)
        lbl:SetText("Новый отдел:") lbl:SetPos(10, 10) lbl:SetSize(80, 20) lbl:SetFont("Factions_Normal")
        lbl:SetTextColor(THEME.text)

        local newEntry = vgui.Create("DTextEntry", addPanel)
        newEntry:SetPos(100, 7) newEntry:SetSize(160, 26) newEntry:SetFont("Factions_Normal")

        local btnAdd = styledButton(addPanel, "+ Добавить", THEME.success, Color(40, 160, 80))
        btnAdd:SetPos(270, 7) btnAdd:SetSize(100, 26)
        btnAdd.DoClick = function()
            local newDept = newEntry:GetText()
            if newDept == "" then return end
            sendAction("addDepartment", { newDept }, function(ok, msg)
                if ok then notification.AddLegacy("Отдел добавлен", NOTIFY_GENERIC, 3) if IsValid(newEntry) then newEntry:SetText("") end refreshAllUI()
                else notification.AddLegacy("Ошибка: " .. msg, NOTIFY_ERROR, 3) end
            end)
        end
    end

    -- ============================================================
    -- ЛИДЕР: СПИСОК УЧАСТНИКОВ
    -- ============================================================
    updateLeaderMemberList = function(data)
        if not IsValid(ui.memberScrollLeader) then return end
        local scroll = ui.memberScrollLeader
        safeScrollClear(scroll)

        local factionName, f = clientGetLeaderFaction(data)
        if not f then
            if IsValid(ui.leaderTitleLabel) then ui.leaderTitleLabel:SetText("Вы не лидер") end
            return
        end
        if IsValid(ui.leaderTitleLabel) then
            ui.leaderTitleLabel:SetText("Фракция: "..GRM.Factions.DisplayName(factionName))
        end

        local members     = f.Members     or {}
        local roles       = f.Roles       or {}
        local sorted = {}
        for steam, info in pairs(members) do sorted[#sorted + 1] = { steam = steam, info = info } end
        table.sort(sorted, function(a, b)
            if a.steam == f.Leader then return true end
            if b.steam == f.Leader then return false end
            local idxA, idxB = 0, 0
            for i, r in ipairs(roles) do
                if r == a.info.Role then idxA = i end
                if r == b.info.Role then idxB = i end
            end
            return idxA > idxB
        end)

        for _, item in ipairs(sorted) do
            local steam = item.steam
            local info  = item.info
            local isLeaderMember = (steam == f.Leader)

            local row = vgui.Create("DPanel", scroll)
            row:SetTall(32) row:Dock(TOP) row:DockMargin(0, 1, 0, 1)
            function row:Paint(w, h)
                if isLeaderMember then
                    surface.SetDrawColor(255, 220, 80, 20)
                    surface.DrawRect(0, 0, w, h)
                end
            end

            local lblSteam = vgui.Create("DLabel", row)
            lblSteam:SetPos(8, 6) lblSteam:SetSize(200, 20) lblSteam:SetText((info._rpName or steam) .. " [" .. steam .. "]")
            lblSteam:SetFont("Factions_Normal")
            if isLeaderMember then lblSteam:SetTextColor(Color(255, 220, 80)) end

            local lblRole = vgui.Create("DLabel", row)
            lblRole:SetPos(220, 6) lblRole:SetSize(130, 20) lblRole:SetText(info.Role or "Участник")
            lblRole:SetFont("Factions_Normal") lblRole:SetTextColor(THEME.accent)

            local lblDept = vgui.Create("DLabel", row)
            lblDept:SetPos(360, 6) lblDept:SetSize(130, 20) lblDept:SetText((info.Department and info.Department ~= "") and info.Department or "—")
            lblDept:SetFont("Factions_Normal") lblDept:SetTextColor(THEME.textDim)
            local lblDuty=vgui.Create("DLabel",row);lblDuty:SetPos(500,6);lblDuty:SetSize(210,20);lblDuty:SetText(tostring(info._dutyStatus or"НЕ В СЕТИ").."  "..tostring(info._location or"—"));lblDuty:SetFont("Factions_Small");lblDuty:SetTextColor(info._dutyStatus=="НА СЛУЖБЕ" and Color(80,220,130) or THEME.textDim)

            if not info._rpName then
                getPlayerName(steam, function(name)
                    if IsValid(lblSteam) then lblSteam:SetText(name .. " [" .. steam .. "]") end
                end)
            end
        end
    end

    -- ============================================================
    -- АДМИНКА: РАНГИ
    -- ============================================================
    updateRanksList = function(factionName, data)
        if not IsValid(ui.ranksScroll) then return end
        local scroll = ui.ranksScroll
        safeScrollClear(scroll)
        if not factionName or not data or not data[factionName] then return end

        local f = data[factionName]
        local roles = f.Roles or {}

        for _, roleName in ipairs(roles) do
            local row = vgui.Create("DPanel", scroll)
            row:SetTall(36) row:Dock(TOP) row:DockMargin(0, 2, 0, 2) row:SetPaintBackground(false)

            local leaderRoleName = f.LeaderRoleName or "Лидер"
            local isLeader = (roleName == leaderRoleName)

            if not isLeader then
                local btnUp = styledButton(row, "▲", THEME.bgLight, THEME.bgHover, THEME.text)
                btnUp:SetPos(5, 5) btnUp:SetSize(28, 26)
                btnUp.DoClick = function()
                    sendAction("moveRole", { factionName, roleName, "up" }, function(ok, msg)
                        if ok then notification.AddLegacy("Роль перемещена", NOTIFY_GENERIC, 3) refreshAllUI()
                        else notification.AddLegacy("Ошибка: " .. msg, NOTIFY_ERROR, 3) end
                    end)
                end

                local btnDown = styledButton(row, "▼", THEME.bgLight, THEME.bgHover, THEME.text)
                btnDown:SetPos(37, 5) btnDown:SetSize(28, 26)
                btnDown.DoClick = function()
                    sendAction("moveRole", { factionName, roleName, "down" }, function(ok, msg)
                        if ok then notification.AddLegacy("Роль перемещена", NOTIFY_GENERIC, 3) refreshAllUI()
                        else notification.AddLegacy("Ошибка: " .. msg, NOTIFY_ERROR, 3) end
                    end)
                end
            end

            local edit = vgui.Create("DTextEntry", row)
            edit:SetPos(70, 5) edit:SetSize(160, 26)
            edit:SetText(GRM.Factions.RoleDisplayName(f, roleName))
            edit:SetTooltip("Системный ключ: " .. roleName .. " (настройки и участники останутся привязаны)")
            edit:SetFont("Factions_Normal")

            local btnRename = styledButton(row, "✎", THEME.accent, THEME.accentDark)
            btnRename:SetPos(240, 5) btnRename:SetSize(36, 26)
            btnRename.DoClick = function()
                local newName = edit:GetText()
                if newName == "" or newName == roleName then return end
                sendAction("renameRole", { factionName, roleName, newName }, function(ok, msg)
                    if ok then notification.AddLegacy("Роль переименована", NOTIFY_GENERIC, 3) refreshAllUI()
                    else notification.AddLegacy("Ошибка: " .. msg, NOTIFY_ERROR, 3) edit:SetText(roleName) end
                end)
            end

            if not isLeader then
                local btnRemove = styledButton(row, "✕", THEME.danger, THEME.dangerHover)
                btnRemove:SetPos(282, 5) btnRemove:SetSize(36, 26)
                btnRemove.DoClick = function()
                    sendAction("removeRole", { factionName, roleName }, function(ok, msg)
                        if ok then notification.AddLegacy("Роль удалена", NOTIFY_GENERIC, 3) refreshAllUI()
                        else notification.AddLegacy("Ошибка: " .. msg, NOTIFY_ERROR, 3) end
                    end)
                end
            else
                local lblLeader = vgui.Create("DLabel", row)
                lblLeader:SetPos(282, 8) lblLeader:SetSize(60, 20)
                lblLeader:SetText("★ Лидер") lblLeader:SetFont("Factions_Small")
                lblLeader:SetTextColor(Color(255, 220, 80))
            end
        end

        local addPanel = vgui.Create("DPanel", scroll)
        addPanel:SetTall(40) addPanel:Dock(TOP) addPanel:DockMargin(0, 5, 0, 0) addPanel:SetPaintBackground(false)

        local lbl = vgui.Create("DLabel", addPanel)
        lbl:SetText("Новая роль:") lbl:SetPos(10, 10) lbl:SetSize(80, 20) lbl:SetFont("Factions_Normal")
        lbl:SetTextColor(THEME.text)

        local newEntry = vgui.Create("DTextEntry", addPanel)
        newEntry:SetPos(100, 7) newEntry:SetSize(160, 26) newEntry:SetFont("Factions_Normal")

        local btnAdd = styledButton(addPanel, "+ Добавить", THEME.success, Color(40, 160, 80))
        btnAdd:SetPos(270, 7) btnAdd:SetSize(100, 26)
        btnAdd.DoClick = function()
            local newRole = newEntry:GetText()
            if newRole == "" then return end
            sendAction("addRole", { factionName, newRole }, function(ok, msg)
                if ok then notification.AddLegacy("Роль добавлена", NOTIFY_GENERIC, 3) if IsValid(newEntry) then newEntry:SetText("") end refreshAllUI()
                else notification.AddLegacy("Ошибка: " .. msg, NOTIFY_ERROR, 3) end
            end)
        end
    end

    -- ============================================================
    -- АДМИНКА: ОТДЕЛЫ
    -- ============================================================
    updateDepartmentsList = function(factionName, data)
        if not IsValid(ui.deptsScroll) then return end
        local scroll = ui.deptsScroll
        safeScrollClear(scroll)
        if not factionName or not data or not data[factionName] then return end

        local f = data[factionName]
        local departments = f.Departments or {}

        for _, deptName in ipairs(departments) do
            local row = vgui.Create("DPanel", scroll)
            row:SetTall(36) row:Dock(TOP) row:DockMargin(0, 2, 0, 2) row:SetPaintBackground(false)

            local btnUp = styledButton(row, "▲", THEME.bgLight, THEME.bgHover, THEME.text)
            btnUp:SetPos(5, 5) btnUp:SetSize(28, 26)
            btnUp.DoClick = function()
                sendAction("moveDepartment", { factionName, deptName, "up" }, function(ok, msg)
                    if ok then notification.AddLegacy("Отдел перемещён", NOTIFY_GENERIC, 3) refreshAllUI()
                    else notification.AddLegacy("Ошибка: " .. msg, NOTIFY_ERROR, 3) end
                end)
            end

            local btnDown = styledButton(row, "▼", THEME.bgLight, THEME.bgHover, THEME.text)
            btnDown:SetPos(37, 5) btnDown:SetSize(28, 26)
            btnDown.DoClick = function()
                sendAction("moveDepartment", { factionName, deptName, "down" }, function(ok, msg)
                    if ok then notification.AddLegacy("Отдел перемещён", NOTIFY_GENERIC, 3) refreshAllUI()
                    else notification.AddLegacy("Ошибка: " .. msg, NOTIFY_ERROR, 3) end
                end)
            end

            local edit=vgui.Create("DTextEntry",row);edit:SetPos(70,5);edit:SetSize(220,26);local departmentDisplay=GRM.Factions.DepartmentDisplayName(f,deptName);edit:SetText(departmentDisplay);edit:SetPlaceholderText("Публичное название");edit:SetTooltip("Системный ключ: "..deptName..". Настройки и участники останутся привязаны к нему.");edit:SetFont("Factions_Normal")
            local btnRename=styledButton(row,"✎",THEME.accent,THEME.accentDark);btnRename:SetPos(300,5);btnRename:SetSize(36,26);btnRename.DoClick=function()local newName=edit:GetText();if newName==""or newName==departmentDisplay then return end;sendAction("renameDepartment",{factionName,deptName,newName},function(ok,msg)if ok then notification.AddLegacy("Название отдела обновлено",NOTIFY_GENERIC,3);refreshAllUI()else notification.AddLegacy("Ошибка: "..msg,NOTIFY_ERROR,3);edit:SetText(departmentDisplay)end end)end

            if #departments > 1 then
                local btnRemove = styledButton(row, "✕", THEME.danger, THEME.dangerHover)
                btnRemove:SetPos(342,5) btnRemove:SetSize(36, 26)
                btnRemove.DoClick = function()
                    sendAction("removeDepartment", { factionName, deptName }, function(ok, msg)
                        if ok then notification.AddLegacy("Отдел удалён", NOTIFY_GENERIC, 3) refreshAllUI()
                        else notification.AddLegacy("Ошибка: " .. msg, NOTIFY_ERROR, 3) end
                    end)
                end
            end
        end

        local addPanel = vgui.Create("DPanel", scroll)
        addPanel:SetTall(40) addPanel:Dock(TOP) addPanel:DockMargin(0, 5, 0, 0) addPanel:SetPaintBackground(false)

        local lbl = vgui.Create("DLabel", addPanel)
        lbl:SetText("Новый отдел:") lbl:SetPos(10, 10) lbl:SetSize(80, 20) lbl:SetFont("Factions_Normal")
        lbl:SetTextColor(THEME.text)

        local newEntry = vgui.Create("DTextEntry", addPanel)
        newEntry:SetPos(100, 7) newEntry:SetSize(160, 26) newEntry:SetFont("Factions_Normal")

        local btnAdd = styledButton(addPanel, "+ Добавить", THEME.success, Color(40, 160, 80))
        btnAdd:SetPos(270, 7) btnAdd:SetSize(100, 26)
        btnAdd.DoClick = function()
            local newDept = newEntry:GetText()
            if newDept == "" then return end
            sendAction("addDepartment", { factionName, newDept }, function(ok, msg)
                if ok then notification.AddLegacy("Отдел добавлен", NOTIFY_GENERIC, 3) if IsValid(newEntry) then newEntry:SetText("") end refreshAllUI()
                else notification.AddLegacy("Ошибка: " .. msg, NOTIFY_ERROR, 3) end
            end)
        end
    end

    -- ============================================================
    -- АДМИНКА: СПИСОК УЧАСТНИКОВ ФРАКЦИИ (FIX: lblDept:SetSize)
    -- ============================================================
    updateMemberListForFaction = function(factionName, data)
        if not IsValid(ui.memberScroll) then return end
        local scroll = ui.memberScroll
        safeScrollClear(scroll)
        if not factionName or not data or not data[factionName] then return end

        local f = data[factionName]
        local members = f.Members or {}
        local roles = f.Roles or {}
        local sorted = {}
        for steam, info in pairs(members) do sorted[#sorted + 1] = { steam = steam, info = info } end
        table.sort(sorted, function(a, b)
            if a.steam == f.Leader then return true end
            if b.steam == f.Leader then return false end
            return (a.info.Role or "") < (b.info.Role or "")
        end)

        for _, item in ipairs(sorted) do
            local steam = item.steam
            local info  = item.info

            local row = vgui.Create("DPanel", scroll)
            row:SetTall(32) row:Dock(TOP) row:DockMargin(0, 1, 0, 1)
            function row:Paint(w, h)
                if steam == f.Leader then
                    surface.SetDrawColor(255, 220, 80, 20)
                    surface.DrawRect(0, 0, w, h)
                end
            end

            local lblSteam = vgui.Create("DLabel", row)
            lblSteam:SetPos(8, 6) lblSteam:SetSize(220, 20) lblSteam:SetText((info._rpName or steam) .. " [" .. steam .. "]")
            lblSteam:SetFont("Factions_Normal")
            if steam == f.Leader then lblSteam:SetTextColor(Color(255, 220, 80)) end

            local lblRole = vgui.Create("DLabel", row)
            lblRole:SetPos(240, 6) lblRole:SetSize(130, 20) lblRole:SetText(info.Role or "Участник")
            lblRole:SetFont("Factions_Normal") lblRole:SetTextColor(THEME.accent)

            -- FIX: было lblRole:SetSize вместо lblDept:SetSize
            local lblDept = vgui.Create("DLabel", row)
            lblDept:SetPos(380, 6) lblDept:SetSize(130, 20) lblDept:SetText((info.Department and info.Department ~= "") and info.Department or "—")
            lblDept:SetFont("Factions_Normal") lblDept:SetTextColor(THEME.textDim)
            local lblDuty=vgui.Create("DLabel",row);lblDuty:SetPos(520,6);lblDuty:SetSize(210,20);lblDuty:SetText(tostring(info._dutyStatus or"НЕ В СЕТИ").."  "..tostring(info._location or"—"));lblDuty:SetFont("Factions_Small");lblDuty:SetTextColor(info._dutyStatus=="НА СЛУЖБЕ" and Color(80,220,130) or THEME.textDim)

            if not info._rpName then
                getPlayerName(steam, function(name)
                    if IsValid(lblSteam) then lblSteam:SetText(name .. " [" .. steam .. "]") end
                end)
            end
        end
    end

    -- ============================================================
    -- ВОЛНА ДЕПАРТАМЕНТА: ПАНЕЛЬ АДМИНКИ
    -- ============================================================
    updateDepWavePanel = function(data)
        if not IsValid(ui.depWaveScroll) then return end
        local scroll = ui.depWaveScroll
        safeScrollClear(scroll)

        data = data or FactionsData

        local hdr = vgui.Create("DPanel", scroll)
        hdr:Dock(TOP) hdr:SetTall(50) hdr:SetPaintBackground(false)

        local infoLbl = vgui.Create("DLabel", hdr)
        infoLbl:Dock(FILL) infoLbl:DockMargin(5, 5, 5, 5) infoLbl:SetWrap(true)
        infoLbl:SetText("Доступы организаций. Волна: /dep — РП чат, /depb (/db) — OOC чат.\nГосуслуги: оказание услуг, выставление счетов, выдача дипломов (детали — в банкомате).")
        infoLbl:SetFont("Factions_Normal")
        infoLbl:SetTextColor(THEME.text)

        local sortedNames = {}
        for name, f in pairs(data or {}) do
            if isstring(name) and name ~= "" and istable(f) then
                sortedNames[#sortedNames + 1] = name
            end
        end
        table.sort(sortedNames)

        for _, factionName in ipairs(sortedNames) do
            local f = data[factionName]
            -- Код 108: continue→if-обёртка (ванильный Lua, стенды парсят файл напрямую)
            if istable(f) then
                local row = vgui.Create("DPanel", scroll)
                row:Dock(TOP) row:SetTall(74) row:DockMargin(0, 2, 0, 2)

                local fCol = f.Color or { r = 60, g = 60, b = 60 }
                function row:Paint(w, h)
                    draw.RoundedBox(4, 0, 0, w, h, Color(fCol.r * 0.15, fCol.g * 0.15, fCol.b * 0.15, 200))
                    surface.SetDrawColor(fCol.r, fCol.g, fCol.b, 180)
                    surface.DrawRect(0, 0, 4, h)
                end

                local tagStr = (f.Tag and f.Tag ~= "") and ("[" .. f.Tag .. "] ") or ""
                local nameLbl = vgui.Create("DLabel", row)
                nameLbl:SetPos(14, 12) nameLbl:SetSize(300, 20)
                nameLbl:SetText(tagStr..GRM.Factions.DisplayName(f,factionName))
                nameLbl:SetTextColor(Color(fCol.r, fCol.g, fCol.b))
                nameLbl:SetFont("Factions_Normal")

                local chkDep = vgui.Create("DCheckBoxLabel", row)
                chkDep:SetPos(360, 12) chkDep:SetSize(250, 20)
                chkDep:SetText("Доступ к волне (/dep, /depb)")
                chkDep:SetFont("Factions_Normal")
                chkDep:SetValue(f.DepAccess and true or false)
                chkDep.OnChange = function(_, val)
                    sendAction("setDepAccess", { factionName, tobool(val) }, function(ok, msg)
                        if ok then notification.AddLegacy("Настройка обновлена", NOTIFY_GENERIC, 3) refreshAllUI()
                        else notification.AddLegacy("Ошибка: " .. msg, NOTIFY_ERROR, 3) chkDep:SetValue(not tobool(val)) end
                    end)
                end

                -- Код 127: доступы к госуслугам, счетам и дипломам
                local svcKinds = {
                    { kind = "service", field = "ServiceAccess", text = "Оказание услуг",     x = 14 },
                    { kind = "invoice", field = "InvoiceAccess", text = "Выставление счетов", x = 200 },
                    { kind = "diploma", field = "DiplomaAccess", text = "Выдача дипломов",    x = 400 },
                }
                for _, sk in ipairs(svcKinds) do
                    local chk = vgui.Create("DCheckBoxLabel", row)
                    chk:SetPos(sk.x, 44) chk:SetSize(190, 20)
                    chk:SetText(sk.text)
                    chk:SetFont("Factions_Normal")
                    chk:SetValue(f[sk.field] and true or false)
                    chk.OnChange = function(_, val)
                        sendAction("setServiceAccess", { factionName, sk.kind, tobool(val) }, function(ok, msg)
                            if ok then notification.AddLegacy("Доступ обновлён", NOTIFY_GENERIC, 3) refreshAllUI()
                            else notification.AddLegacy("Ошибка: " .. msg, NOTIFY_ERROR, 3) chk:SetValue(not tobool(val)) end
                        end)
                    end
                end
            end
        end
    end

    -- ============================================================
    -- ОСНОВНОЕ МЕНЮ АДМИНА (FIX: Unified Factions UI v2.0)
    -- ============================================================
    function OpenAdminMenu(facName)
        if GRM and GRM.Factions and GRM.Factions.UnifiedUI and GRM.Factions.UnifiedUI.Open then
            GRM.Factions.UnifiedUI.Open(facName)
            return
        end

        local frame = vgui.Create("DFrame")
        frame:SetTitle("")
        frame:SetSize(1280, 860) frame:Center() frame:MakePopup()
        ui.currentFrame = frame

        function frame:Paint(w, h)
            draw.RoundedBox(6, 0, 0, w, h, THEME.bg)
            draw.RoundedBoxEx(6, 0, 0, w, 32, Color(35, 35, 45), true, true, false, false)
            draw.SimpleText("Управление фракциями", "Factions_Title", 12, 16, THEME.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end

        local tabs = vgui.Create("DPropertySheet", frame)
        tabs:Dock(FILL) tabs:DockMargin(4, 36, 4, 4)
        function tabs:Paint(w, h)
            surface.SetDrawColor(THEME.bgLight)
            surface.DrawRect(0, 0, w, h)
        end

        -- Фракции
        local factionList = vgui.Create("DPanel")
        factionList:SetPaintBackground(false)
        local listView = vgui.Create("DListView", factionList)
        listView:Dock(FILL)
        listView:AddColumn("Публичное имя") listView:AddColumn("Регистрационное имя") listView:AddColumn("Лидер") listView:AddColumn("Участников")
        ui.listView = listView

        local btnRefresh = styledButton(factionList, "↻ Обновить", THEME.accent, THEME.accentDark)
        btnRefresh:Dock(BOTTOM) btnRefresh:SetTall(32)
        btnRefresh.DoClick = function()
            getData(function(data)
                FactionsData = data or {}
                refreshAllUI(FactionsData)
            end)
        end
        tabs:AddSheet("Фракции", factionList, "icon16/group.png")

        -- Создание
        local createPanel = vgui.Create("DPanel")
        createPanel:SetPaintBackground(false) createPanel:DockPadding(15, 15, 15, 15)

        sectionPanel(createPanel, "Создание новой фракции")

        local lblName = vgui.Create("DLabel", createPanel)
        lblName:SetText("Регистрационное имя:") lblName:SetPos(15,55) lblName:SetSize(165,20)
        lblName:SetFont("Factions_Normal") lblName:SetTextColor(THEME.text)

        local nameEntry=vgui.Create("DTextEntry",createPanel);nameEntry:SetPos(185,52);nameEntry:SetSize(240,26);nameEntry:SetFont("Factions_Normal");nameEntry:SetPlaceholderText("system_registration_id")
        local lblDisplay=vgui.Create("DLabel",createPanel);lblDisplay:SetText("Публичное имя (RU):");lblDisplay:SetPos(15,90);lblDisplay:SetSize(165,20);lblDisplay:SetFont("Factions_Normal");lblDisplay:SetTextColor(THEME.text)
        local displayEntry=vgui.Create("DTextEntry",createPanel);displayEntry:SetPos(185,87);displayEntry:SetSize(320,26);displayEntry:SetFont("Factions_Normal");displayEntry:SetPlaceholderText("Название для новостей, департамента и UI")

        local lblLeader = vgui.Create("DLabel", createPanel)
        lblLeader:SetText("SteamID лидера (опционально):") lblLeader:SetPos(15, 125) lblLeader:SetSize(220, 20)
        lblLeader:SetFont("Factions_Normal") lblLeader:SetTextColor(THEME.text)

        local leaderEntry = vgui.Create("DTextEntry", createPanel)
        leaderEntry:SetPos(245,122) leaderEntry:SetSize(260,26) leaderEntry:SetFont("Factions_Normal")

        local btnCreate = styledButton(createPanel, "+ Создать фракцию", THEME.success, Color(40, 160, 80))
        btnCreate:SetPos(15,165) btnCreate:SetSize(180,32)
        btnCreate.DoClick = function()
            local name=string.Trim(nameEntry:GetText()or"");local displayName=string.Trim(displayEntry:GetText()or"");if name==""then notification.AddLegacy("Введите регистрационное имя",NOTIFY_ERROR,3)return end;if displayName==""then notification.AddLegacy("Введите публичное русское имя",NOTIFY_ERROR,3)return end
            local leader=leaderEntry:GetText();if leader==""then leader=nil end
            sendAction("createFactionV2",{name,displayName,leader},function(ok,msg)
                if ok then notification.AddLegacy("Фракция создана",NOTIFY_GENERIC,3);if IsValid(nameEntry)then nameEntry:SetText("")end;if IsValid(displayEntry)then displayEntry:SetText("")end;if IsValid(leaderEntry)then leaderEntry:SetText("")end;refreshAllUI()
                else notification.AddLegacy("Ошибка: " .. msg, NOTIFY_ERROR, 3) end
            end)
        end
        tabs:AddSheet("Создать", createPanel, "icon16/add.png")

        -- Редактирование
        local editPanel = vgui.Create("DPanel")
        editPanel:SetPaintBackground(false) editPanel:DockPadding(15, 15, 15, 15)
        local Y = 15

        -- Выбор фракции
        local lblFaction = vgui.Create("DLabel", editPanel)
        lblFaction:SetText("Фракция:") lblFaction:SetPos(15, Y + 3) lblFaction:SetSize(80, 20)
        lblFaction:SetFont("Factions_Normal") lblFaction:SetTextColor(THEME.text)

        local factionCombo = vgui.Create("DComboBox", editPanel)
        factionCombo:SetPos(100, Y) factionCombo:SetSize(260, 26)
        ui.factionCombo = factionCombo
        Y = Y + 40

        -- Кнопки: Удалить, Сменить лидера
        local btnDelete = styledButton(editPanel, "✕ Удалить фракцию", THEME.danger, THEME.dangerHover)
        btnDelete:SetPos(15, Y) btnDelete:SetSize(160, 30)
        btnDelete.DoClick = function()
            local faction = factionCombo:GetValue()
            if not faction or faction == "" then return end
            sendAction("deleteFaction", { faction }, function(ok, msg)
                if ok then notification.AddLegacy("Фракция удалена", NOTIFY_GENERIC, 3) refreshAllUI()
                else notification.AddLegacy("Ошибка: " .. msg, NOTIFY_ERROR, 3) end
            end)
        end

        local btnChangeLeader = styledButton(editPanel, "★ Сменить лидера", THEME.accent, THEME.accentDark)
        btnChangeLeader:SetPos(190, Y) btnChangeLeader:SetSize(160, 30)
        btnChangeLeader.DoClick = function()
            local faction = factionCombo:GetValue()
            if not faction or faction == "" then return end

            local pick = vgui.Create("DFrame")
            pick:SetTitle("Смена лидера — " .. faction)
            pick:SetSize(620, 300)
            pick:Center()
            pick:MakePopup()

            local help = vgui.Create("DLabel", pick)
            help:Dock(TOP)
            help:DockMargin(12, 10, 12, 4)
            help:SetTall(32)
            help:SetWrap(true)
            help:SetText("Выберите персонажа онлайн или укажите его CharacterKey. SteamID аккаунта больше не используется как лидерский ключ.")

            local combo = vgui.Create("DComboBox", pick)
            combo:Dock(TOP)
            combo:DockMargin(12, 4, 12, 4)
            combo:SetTall(30)
            combo:SetValue("Онлайн-персонажи")
            local selectedKey = nil
            function combo:OnSelect(_, _, data) selectedKey = data end
            combo:SetSortItems(false)
            for _, choice in ipairs(FactionCharacterChoices or {}) do
                local active = choice.active and " • АКТИВЕН" or " • неактивен"
                local fac = choice.faction ~= "" and (" • " .. choice.faction) or " • гражданский"
                combo:AddChoice(
                    tostring(choice.rpName or "?") .. "  — игрок: " .. tostring(choice.steamNick or "?") ..
                    "  [" .. tostring(choice.slot or "char?") .. "]" .. active .. fac,
                    tostring(choice.key or "")
                )
            end

            local entry = vgui.Create("DTextEntry", pick)
            entry:Dock(TOP)
            entry:DockMargin(12, 4, 12, 4)
            entry:SetTall(28)
            entry:SetPlaceholderText("CharacterKey для офлайн-персонажа: SteamID64:charN")

            local confirm = styledButton(pick, "Назначить лидером", THEME.accent, THEME.accentDark)
            confirm:Dock(BOTTOM)
            confirm:DockMargin(12, 6, 12, 10)
            confirm:SetTall(32)
            confirm.DoClick = function()
                local key = string.Trim(entry:GetValue() or "")
                key = key ~= "" and key or selectedKey
                if not key or key == "" or not key:match(":char[1-3]$") then
                    notification.AddLegacy("Нужен CharacterKey формата SteamID64:char1/char2/char3", NOTIFY_ERROR, 3)
                    return
                end
                sendAction("changeLeader", { faction, key }, function(ok, msg)
                    if ok then
                        notification.AddLegacy("Лидер изменён", NOTIFY_GENERIC, 3)
                        pick:Close()
                        refreshAllUI()
                    else
                        notification.AddLegacy("Ошибка: " .. msg, NOTIFY_ERROR, 3)
                    end
                end)
            end
        end
        Y = Y + 50

        -- Публичное русское имя не меняет системные ключи и связи.
        local lblDisplayEdit=vgui.Create("DLabel",editPanel);lblDisplayEdit:SetText("Публичное имя (RU):");lblDisplayEdit:SetPos(15,Y+3);lblDisplayEdit:SetSize(145,20);lblDisplayEdit:SetFont("Factions_Normal");lblDisplayEdit:SetTextColor(THEME.text)
        local displayEdit=vgui.Create("DTextEntry",editPanel);displayEdit:SetPos(165,Y);displayEdit:SetSize(260,26);displayEdit:SetFont("Factions_Normal");displayEdit:SetPlaceholderText("Название для публичного интерфейса")
        local btnDisplay=styledButton(editPanel,"Сохранить имя",THEME.success,Color(40,160,80));btnDisplay:SetPos(435,Y);btnDisplay:SetSize(130,26);btnDisplay.DoClick=function()local faction=factionCombo:GetValue();local value=string.Trim(displayEdit:GetText()or"");if not faction or faction==""or value==""then return end;sendAction("setDisplayName",{faction,value},function(ok,msg)if ok then notification.AddLegacy("Публичное имя сохранено",NOTIFY_GENERIC,3);refreshAllUI()else notification.AddLegacy("Ошибка: "..msg,NOTIFY_ERROR,3)end end)end
        Y=Y+42

        -- Переименование регистрационного имени (системного ключа)
        local lblRename = vgui.Create("DLabel", editPanel)
        lblRename:SetText("Регистрационное имя:") lblRename:SetPos(15, Y + 3) lblRename:SetSize(145, 20)
        lblRename:SetFont("Factions_Normal") lblRename:SetTextColor(THEME.text)

        local renameEntry = vgui.Create("DTextEntry", editPanel)
        renameEntry:SetPos(165,Y) renameEntry:SetSize(200,26) renameEntry:SetFont("Factions_Normal");renameEntry:SetPlaceholderText("Новый системный ID")

        local btnRename = styledButton(editPanel, "✎ Переименовать", THEME.accent, THEME.accentDark)
        btnRename:SetPos(375,Y) btnRename:SetSize(140,26)
        btnRename.DoClick = function()
            local faction = factionCombo:GetValue()
            local newName = renameEntry:GetText()
            if not faction or faction == "" or newName == "" then return end
            sendAction("renameFaction", { faction, newName }, function(ok, msg)
                if ok then notification.AddLegacy("Фракция переименована", NOTIFY_GENERIC, 3) if IsValid(renameEntry) then renameEntry:SetText("") end refreshAllUI()
                else notification.AddLegacy("Ошибка: " .. msg, NOTIFY_ERROR, 3) end
            end)
        end
        Y = Y + 50

        -- Тег фракции
        local lblTagSection = vgui.Create("DLabel", editPanel)
        lblTagSection:SetText("Тег фракции (до 5 символов):") lblTagSection:SetPos(15, Y) lblTagSection:SetSize(200, 20)
        lblTagSection:SetFont("Factions_Normal") lblTagSection:SetTextColor(THEME.textDim)
        Y = Y + 28

        local tagEntry = vgui.Create("DTextEntry", editPanel)
        tagEntry:SetPos(15, Y) tagEntry:SetSize(100, 26) tagEntry:SetPlaceholderText("до 5")
        tagEntry:SetFont("Factions_Normal")
        ui.editTagEntry = tagEntry
        tagEntry.OnChange = function()
            local t = tagEntry:GetText()
            if #t > 5 then tagEntry:SetText(string.sub(t, 1, 5)) tagEntry:SetCaretPos(5) end
        end

        local btnSaveTag = styledButton(editPanel, "Сохранить тег", THEME.accent, THEME.accentDark)
        btnSaveTag:SetPos(125, Y) btnSaveTag:SetSize(120, 26)
        btnSaveTag.DoClick = function()
            local faction = factionCombo:GetValue()
            if not faction or faction == "" then return end
            sendAction("setTag", { faction, tagEntry:GetText() }, function(ok, msg)
                if ok then notification.AddLegacy("Тег сохранён", NOTIFY_GENERIC, 3) refreshAllUI()
                else notification.AddLegacy("Ошибка: " .. msg, NOTIFY_ERROR, 3) end
            end)
        end
        Y = Y + 50

        -- Цвет фракции
        local lblColorSection = vgui.Create("DLabel", editPanel)
        lblColorSection:SetText("Цвет фракции:") lblColorSection:SetPos(15, Y) lblColorSection:SetSize(200, 20)
        lblColorSection:SetFont("Factions_Normal") lblColorSection:SetTextColor(THEME.textDim)
        Y = Y + 28

        ui._editColorR = 255
        ui._editColorG = 200
        ui._editColorB = 50

        local colorPreview = vgui.Create("DPanel", editPanel)
        colorPreview:SetPos(380, Y) colorPreview:SetSize(100, 80)
        function colorPreview:Paint(w, h)
            draw.RoundedBox(6, 0, 0, w, h, Color(ui._editColorR or 255, ui._editColorG or 200, ui._editColorB or 50, 255))
            surface.SetDrawColor(THEME.border)
            surface.DrawOutlinedRect(0, 0, w, h)
        end
        ui.editColorPreview = colorPreview

        local function createColorSlider(parent, label, posY, initVal, onChangeFunc)
            local lbl = vgui.Create("DLabel", parent)
            lbl:SetPos(15, posY + 3) lbl:SetSize(20, 20) lbl:SetText(label)
            lbl:SetFont("Factions_Normal") lbl:SetTextColor(THEME.text)
            local slider = vgui.Create("DNumSlider", parent)
            slider:SetPos(40, posY) slider:SetSize(300, 25)
            slider:SetMin(0) slider:SetMax(255) slider:SetDecimals(0) slider:SetValue(initVal)
            slider.OnValueChanged = function(_, val) onChangeFunc(math.floor(val)) end
            return slider
        end

        local sliderR = createColorSlider(editPanel, "R", Y, 255, function(v) ui._editColorR = v end)
        local sliderG = createColorSlider(editPanel, "G", Y + 28, 200, function(v) ui._editColorG = v end)
        local sliderB = createColorSlider(editPanel, "B", Y + 56, 50, function(v) ui._editColorB = v end)
        Y = Y + 90

        local btnSaveColor = styledButton(editPanel, "Сохранить цвет", THEME.accent, THEME.accentDark)
        btnSaveColor:SetPos(15, Y) btnSaveColor:SetSize(150, 30)
        btnSaveColor.DoClick = function()
            local faction = factionCombo:GetValue()
            if not faction or faction == "" then return end
            sendAction("setColor", { faction, ui._editColorR, ui._editColorG, ui._editColorB }, function(ok, msg)
                if ok then notification.AddLegacy("Цвет сохранён", NOTIFY_GENERIC, 3) refreshAllUI()
                else notification.AddLegacy("Ошибка: " .. msg, NOTIFY_ERROR, 3) end
            end)
        end

        factionCombo.OnSelect = function(_, _, faction)
            getData(function(data)
                if not data or not data[faction] then return end
                local f = data[faction]
                if IsValid(tagEntry)then tagEntry:SetText(f.Tag or"")end;if IsValid(displayEdit)then displayEdit:SetText(GRM.Factions.DisplayName(f,faction))end
                if IsValid(renameEntry) then renameEntry:SetText("") end
                local col = f.Color or { r = 255, g = 200, b = 50 }
                ui._editColorR = col.r ui._editColorG = col.g ui._editColorB = col.b
                if IsValid(sliderR) then sliderR:SetValue(col.r) end
                if IsValid(sliderG) then sliderG:SetValue(col.g) end
                if IsValid(sliderB) then sliderB:SetValue(col.b) end
            end)
        end
        tabs:AddSheet("Редактировать", editPanel, "icon16/pencil.png")

        -- Ранги
        local ranksPanel = vgui.Create("DPanel")
        ranksPanel:SetPaintBackground(false) ranksPanel:DockPadding(10, 10, 10, 10)

        local lblR = vgui.Create("DLabel", ranksPanel)
        lblR:SetText("Фракция:") lblR:SetPos(10, 10) lblR:SetSize(80, 20)
        lblR:SetFont("Factions_Normal") lblR:SetTextColor(THEME.text)

        local factionComboRanks = vgui.Create("DComboBox", ranksPanel)
        factionComboRanks:SetPos(100, 7) factionComboRanks:SetSize(240, 26)
        ui.factionComboRanks = factionComboRanks

        local ranksScroll = vgui.Create("DScrollPanel", ranksPanel)
        ranksScroll:SetPos(10, 42) ranksScroll:SetSize(1230, 720)
        ui.ranksScroll = ranksScroll

        factionComboRanks.OnSelect = function(_, _, factionName)
            getData(function(data) updateRanksList(factionName, data) end)
        end
        tabs:AddSheet("Ранги", ranksPanel, "icon16/user.png")

        -- Отделы
        local deptsPanel = vgui.Create("DPanel")
        deptsPanel:SetPaintBackground(false) deptsPanel:DockPadding(10, 10, 10, 10)

        local lblD = vgui.Create("DLabel", deptsPanel)
        lblD:SetText("Фракция:") lblD:SetPos(10, 10) lblD:SetSize(80, 20)
        lblD:SetFont("Factions_Normal") lblD:SetTextColor(THEME.text)

        local factionComboDepts = vgui.Create("DComboBox", deptsPanel)
        factionComboDepts:SetPos(100, 7) factionComboDepts:SetSize(240, 26)
        ui.factionComboDepts = factionComboDepts

        local deptsScroll = vgui.Create("DScrollPanel", deptsPanel)
        deptsScroll:SetPos(10, 42) deptsScroll:SetSize(1230, 720)
        ui.deptsScroll = deptsScroll

        factionComboDepts.OnSelect = function(_, _, factionName)
            getData(function(data) updateDepartmentsList(factionName, data) end)
        end
        tabs:AddSheet("Отделы", deptsPanel, "icon16/brick.png")

        -- Участники (быстро)
        local memberPanel = vgui.Create("DPanel")
        memberPanel:SetPaintBackground(false) memberPanel:DockPadding(15, 10, 15, 10)
        local Y = 10

        local lblF3 = vgui.Create("DLabel", memberPanel)
        lblF3:SetText("Фракция:") lblF3:SetPos(15, Y + 3) lblF3:SetSize(80, 20)
        lblF3:SetFont("Factions_Normal") lblF3:SetTextColor(THEME.text)

        local factionCombo3 = vgui.Create("DComboBox", memberPanel)
        factionCombo3:SetPos(100, Y) factionCombo3:SetSize(280, 26)
        ui.factionCombo3 = factionCombo3
        Y = Y + 36

        local lblOnline = vgui.Create("DLabel", memberPanel)
        lblOnline:SetText("Онлайн:") lblOnline:SetPos(15, Y + 3) lblOnline:SetSize(80, 20)
        lblOnline:SetFont("Factions_Normal") lblOnline:SetTextColor(THEME.text)

        local onlineCombo = vgui.Create("DComboBox", memberPanel)
        onlineCombo:SetPos(100, Y) onlineCombo:SetSize(280, 26)
        onlineCombo:SetFont("Factions_Normal")
        populateOnlinePlayerCombo(onlineCombo)
        Y = Y + 36

        local lblTarget = vgui.Create("DLabel", memberPanel)
        lblTarget:SetText("Ключ/ID:") lblTarget:SetPos(15, Y + 3) lblTarget:SetSize(80, 20)
        lblTarget:SetFont("Factions_Normal") lblTarget:SetTextColor(THEME.textDim)

        local targetEntry = vgui.Create("DTextEntry", memberPanel)
        targetEntry:SetPos(100, Y) targetEntry:SetSize(280, 26) targetEntry:SetFont("Factions_Normal")
        Y = Y + 40

        onlineCombo.OnSelect = function(_, _, _, dataKey)
            if isstring(dataKey) and dataKey ~= "" then
                targetEntry:SetText(dataKey)
            end
        end

        local lblRoleM = vgui.Create("DLabel", memberPanel)
        lblRoleM:SetText("Роль:") lblRoleM:SetPos(15, Y + 3) lblRoleM:SetSize(80, 20)
        lblRoleM:SetFont("Factions_Normal") lblRoleM:SetTextColor(THEME.text)

        local roleCombo = vgui.Create("DComboBox", memberPanel)
        roleCombo:SetPos(100, Y) roleCombo:SetSize(200, 26)
        ui.roleCombo3 = roleCombo -- Код 108: живое комбо (пересборка в refreshAllUI)
        Y = Y + 40

        local lblDeptM = vgui.Create("DLabel", memberPanel)
        lblDeptM:SetText("Отдел:") lblDeptM:SetPos(15, Y + 3) lblDeptM:SetSize(80, 20)
        lblDeptM:SetFont("Factions_Normal") lblDeptM:SetTextColor(THEME.text)

        local deptCombo = vgui.Create("DComboBox", memberPanel)
        deptCombo:SetPos(100, Y) deptCombo:SetSize(200, 26)
        ui.deptCombo3 = deptCombo -- Код 108: живое комбо
        Y = Y + 45

        factionCombo3.OnSelect = function(_, _, value)
            getData(function(data)
                local f = data[value]
                if f then
                    roleCombo:Clear() deptCombo:Clear()
                    for _, role in ipairs(f.Roles or {}) do roleCombo:AddChoice(role) end
                    for _, dept in ipairs(f.Departments or {}) do deptCombo:AddChoice(dept) end
                end
            end)
        end

        local btnInvite = styledButton(memberPanel, "✉ Пригласить", THEME.accent, THEME.accentDark)
        btnInvite:SetPos(15, Y) btnInvite:SetSize(130, 30)
        btnInvite.DoClick = function()
            local faction = factionCombo3:GetValue()
            local steam   = targetEntry:GetText()
            if not faction or faction == "" or steam == "" then return end
            local role,dept=roleCombo:GetValue()or"",deptCombo:GetValue()or"";confirmInvite(faction,steam,role,dept,function()sendAction("inviteMember",{faction,steam,role,dept},function(ok,msg)if ok then notification.AddLegacy(msg~=""and msg or"Приглашение отправлено",NOTIFY_GENERIC,5)else notification.AddLegacy("Ошибка: "..msg,NOTIFY_ERROR,4)end end)end)
        end

        if LocalPlayer():IsSuperAdmin() then
            local btnSelf = styledButton(memberPanel, "★ Назначить себя", Color(54, 160, 112), Color(68, 190, 132))
            btnSelf:SetPos(15, Y + 36) btnSelf:SetSize(190, 30)
            btnSelf.DoClick = function()
                local faction = factionCombo3:GetValue()
                if faction == "" then return end
                local role, dept = roleCombo:GetValue() or "", deptCombo:GetValue() or ""
                sendAction("assignSelf", { faction, role, dept, "", false }, function(ok, msg)
                    notification.AddLegacy(msg or "", ok and NOTIFY_GENERIC or NOTIFY_ERROR, 4)
                end)
            end
            local btnSelfLeader = styledButton(memberPanel, "★ Сделать лидером", Color(170, 120, 48), Color(205, 150, 60))
            btnSelfLeader:SetPos(210, Y + 36) btnSelfLeader:SetSize(190, 30)
            btnSelfLeader.DoClick = function()
                local faction = factionCombo3:GetValue()
                if faction == "" then return end
                local dept = deptCombo:GetValue() or ""
                sendAction("assignSelf", { faction, "", dept, "", true }, function(ok, msg)
                    notification.AddLegacy(msg or "", ok and NOTIFY_GENERIC or NOTIFY_ERROR, 4)
                end)
            end
            Y = Y + 36
        end

        local btnRemoveMember = styledButton(memberPanel, "✕ Удалить", THEME.danger, THEME.dangerHover)
        btnRemoveMember:SetPos(155, Y) btnRemoveMember:SetSize(110, 30)
        btnRemoveMember.DoClick = function()
            local faction = factionCombo3:GetValue()
            local steam   = targetEntry:GetText()
            if not faction or faction == "" or steam == "" then return end
            sendAction("removeMember", { faction, steam }, function(ok, msg)
                if ok then notification.AddLegacy("Удалён", NOTIFY_GENERIC, 3) refreshAllUI()
                else notification.AddLegacy("Ошибка: " .. msg, NOTIFY_ERROR, 3) end
            end)
        end
        Y = Y + 40

        local btnSetRole = styledButton(memberPanel, "★ Назначить роль", THEME.accent, THEME.accentDark)
        btnSetRole:SetPos(15, Y) btnSetRole:SetSize(150, 30)
        btnSetRole.DoClick = function()
            local faction = factionCombo3:GetValue()
            local steam   = targetEntry:GetText()
            local role    = roleCombo:GetValue()
            if not faction or faction == "" or steam == "" or not role then return end
            sendAction("setRole", { faction, steam, role }, function(ok, msg)
                if ok then notification.AddLegacy("Роль назначена", NOTIFY_GENERIC, 3) refreshAllUI()
                else notification.AddLegacy("Ошибка: " .. msg, NOTIFY_ERROR, 3) end
            end)
        end

        local btnSetDept = styledButton(memberPanel, "⬚ Назначить отдел", THEME.accent, THEME.accentDark)
        btnSetDept:SetPos(175, Y) btnSetDept:SetSize(160, 30)
        btnSetDept.DoClick = function()
            local faction = factionCombo3:GetValue()
            local steam   = targetEntry:GetText()
            local dept    = deptCombo:GetValue()
            if not faction or faction == "" or steam == "" or not dept then return end
            sendAction("setDepartment", { faction, steam, dept }, function(ok, msg)
                if ok then notification.AddLegacy("Отдел назначен", NOTIFY_GENERIC, 3) refreshAllUI()
                else notification.AddLegacy("Ошибка: " .. msg, NOTIFY_ERROR, 3) end
            end)
        end
        tabs:AddSheet("Участники", memberPanel, "icon16/user_edit.png")

        -- Список участников
        local memberListPanel = vgui.Create("DPanel")
        memberListPanel:SetPaintBackground(false) memberListPanel:DockPadding(10, 10, 10, 10)

        local lblFL = vgui.Create("DLabel", memberListPanel)
        lblFL:SetText("Фракция:") lblFL:SetPos(10, 10) lblFL:SetSize(80, 20)
        lblFL:SetFont("Factions_Normal") lblFL:SetTextColor(THEME.text)

        local factionComboList = vgui.Create("DComboBox", memberListPanel)
        factionComboList:SetPos(100, 7) factionComboList:SetSize(240, 26)
        ui.factionComboList = factionComboList

        local scrollPanel = vgui.Create("DScrollPanel", memberListPanel)
        scrollPanel:SetPos(10, 42) scrollPanel:SetSize(1230, 720)
        ui.memberScroll = scrollPanel

        factionComboList.OnSelect = function(_, _, factionName)
            getData(function(data) updateMemberListForFaction(factionName, data) end)
        end
        tabs:AddSheet("Список", memberListPanel, "icon16/user_go.png")

        -- Волна департамента
        local depWavePanel = vgui.Create("DPanel")
        depWavePanel:SetPaintBackground(false) depWavePanel:DockPadding(10, 10, 10, 10)
        local depWaveScroll = vgui.Create("DScrollPanel", depWavePanel)
        depWaveScroll:Dock(FILL)
        ui.depWaveScroll = depWaveScroll
        tabs:AddSheet("Волна департамента", depWavePanel, "icon16/transmit.png")

        -- ============================================================

        -- ============================================================
        -- Код 126 — вкладка «Инкассация» (упрощённая вертикальная раскладка, без DHorizontalDivider)
        -- ============================================================
        local incassoPanel = vgui.Create("DPanel")
        incassoPanel:SetPaintBackground(false)
        incassoPanel:DockPadding(12, 12, 12, 12)

        -- Шапка: лейбл + комбо фракции + подсказка (все элементы — через Dock, не абсолют!)
        local incTop = vgui.Create("DPanel", incassoPanel)
        incTop:Dock(TOP) incTop:SetTall(34) incTop:SetPaintBackground(true)
        function incTop:Paint(w, h)
            -- Рисуем фон как остальные панели в админке, чтобы DComboBox мог корректно отобразить выпадающее меню
            draw.RoundedBox(4, 0, 0, w, h, THEME.bgLight)
        end

        local lblIncF = vgui.Create("DLabel", incTop)
        lblIncF:Dock(LEFT) lblIncF:DockMargin(4, 8, 8, 0)
        lblIncF:SetFont("Factions_Normal") lblIncF:SetTextColor(THEME.text)
        lblIncF:SetText("Фракция:")
        lblIncF:SizeToContents()

        local factionComboIncasso = vgui.Create("DComboBox", incTop)
        factionComboIncasso:Dock(LEFT) factionComboIncasso:SetWide(320)
        factionComboIncasso:SetFont("Factions_Normal")
        factionComboIncasso:SetSortItems(false)
        factionComboIncasso:SetZPos(500)
        -- Форсируем обновление списка при открытии
        local oldDoClick = factionComboIncasso.DoClick
        function factionComboIncasso:DoClick()
            -- Перезаполним вариантами из кэша (если список пуст)
            if #self.Choices == 0 and FactionsData then
                self:Clear()
                local names = {}
                for n, _ in pairs(FactionsData) do names[#names+1] = n end
                table.sort(names)
                for _, n in ipairs(names) do self:AddChoice(n) end
            end
            return oldDoClick and oldDoClick(self)
        end
        ui.factionComboIncasso = factionComboIncasso

        local incSaveHint = vgui.Create("DLabel", incTop)
        incSaveHint:Dock(RIGHT) incSaveHint:DockMargin(8, 10, 4, 0)
        incSaveHint:SetFont("Factions_Small") incSaveHint:SetTextColor(THEME.textDim)
        incSaveHint:SetText("Настройки сохраняются в factions.json (Код 126)")
        incSaveHint:SizeToContents()

        -- Заголовок ролей
        local lblRolesHead = vgui.Create("DLabel", incassoPanel)
        lblRolesHead:Dock(TOP) lblRolesHead:DockMargin(4, 12, 4, 4) lblRolesHead:SetTall(22)
        lblRolesHead:SetFont("Factions_Normal") lblRolesHead:SetTextColor(THEME.accent)
        lblRolesHead:SetText("Роли, которым разрешено инкассировать:")

        -- Большой скролл с чекбоксом включения + ролями (левая часть, на всю ширину, высотой ~300)
        local incLeft = vgui.Create("DScrollPanel", incassoPanel)
        incLeft:Dock(TOP) incLeft:SetTall(300) incLeft:DockMargin(0, 0, 0, 8)
        incLeft:SetPaintBackground(false)
        ui.incassoScroll = incLeft

        -- Заголовок секции ТС
        local lblVehHead = vgui.Create("DLabel", incassoPanel)
        lblVehHead:Dock(TOP) lblVehHead:DockMargin(4, 8, 4, 4) lblVehHead:SetTall(22)
        lblVehHead:SetFont("Factions_Normal") lblVehHead:SetTextColor(THEME.accent)
        lblVehHead:SetText("Разрешённые инкассаторские ТС (spawn-name / vehicle class):")

        -- Список добавленных ТС
        local incVehScroll = vgui.Create("DScrollPanel", incassoPanel)
        incVehScroll:Dock(TOP) incVehScroll:SetTall(180) incVehScroll:DockMargin(0, 0, 0, 6)
        ui.incassoVehScroll = incVehScroll

        -- Панель добавления ТС (поле ввода + кнопка) — всё на Dock
        local incVehAdd = vgui.Create("DPanel", incassoPanel)
        incVehAdd:Dock(TOP) incVehAdd:SetTall(34) incVehAdd:DockMargin(0, 2, 0, 2) incVehAdd:SetPaintBackground(false)

        local btnIncassoAddVeh = styledButton(incVehAdd, "+ Добавить ТС", THEME.success, Color(40, 160, 80))
        btnIncassoAddVeh:Dock(LEFT) btnIncassoAddVeh:SetWide(150)

        local incVehCombo = vgui.Create("DComboBox", incVehAdd)
        incVehCombo:Dock(RIGHT) incVehCombo:SetWide(300)
        incVehCombo:SetSortItems(false)
        ui.incassoVehCombo = incVehCombo

        local incVehEntry = vgui.Create("DTextEntry", incVehAdd)
        incVehEntry:Dock(FILL) incVehEntry:DockMargin(8, 2, 8, 2)
        incVehEntry:SetFont("Factions_Normal")
        incVehEntry:SetPlaceholderText("spawn-name класса, напр. simfphys_van")
        ui.incassoVehEntry = incVehEntry

        -- Футер: грязный маркер + кнопка сохранить
        local incFooter = vgui.Create("DPanel", incassoPanel)
        incFooter:Dock(TOP) incFooter:SetTall(40) incFooter:DockMargin(0, 10, 0, 0)
        incFooter:SetPaintBackground(false)

        local btnIncassoSave = styledButton(incFooter, "Сохранить настройки инкассации", THEME.accent, THEME.accentDark)
        btnIncassoSave:Dock(RIGHT) btnIncassoSave:SetWide(280)

        local incDirtyLbl = vgui.Create("DLabel", incFooter)
        incDirtyLbl:Dock(LEFT) incDirtyLbl:DockMargin(6, 12, 0, 0)
        incDirtyLbl:SetFont("Factions_Small")
        incDirtyLbl:SetTextColor(THEME.danger) incDirtyLbl:SetText("")
        incDirtyLbl:SizeToContents()

        ui.incassoVehicles = {}
        ui.incassoDirty = false

        local function setIncassoDirty(v)
            ui.incassoDirty = v and true or false
            if IsValid(incDirtyLbl) then
                incDirtyLbl:SetText(ui.incassoDirty and "● Есть несохранённые изменения" or "")
                incDirtyLbl:SizeToContents()
            end
        end
        local function markIncassoDirty() setIncassoDirty(true) end

        -- Заполнение списка доступных ТС во всех трёх листах
        local function fillVehicleCombo()
            if not IsValid(incVehCombo) then return end
            incVehCombo:Clear()
            incVehCombo:AddChoice("— быстрый выбор ТС (из списка) —", nil, false)
            local added = {}
            for _, listName in ipairs({ "Vehicles", "simfphys_vehicles", "LVS_Vehicles" }) do
                local lst = list.Get(listName)
                if istable(lst) then
                    for clsName in pairs(lst) do
                        if type(clsName) == "string" and clsName ~= "" and not added[clsName] then
                            added[clsName] = true
                            incVehCombo:AddChoice(listName .. ": " .. clsName, clsName)
                        end
                    end
                end
            end
        end

        -- Функция рендера содержимого вкладки для выбранной фракции
        local function updateIncassoPanel(factionName, data)
            if not IsValid(incLeft) or not IsValid(incVehScroll) then return end
            -- Очищаем детей, не трогая DScrollBar-ы (используем флаг _grmChrome)
            for _, child in ipairs(incLeft:GetChildren() or {}) do
                if IsValid(child) and child._grmChrome then child:Remove() end
            end
            for _, child in ipairs(incVehScroll:GetChildren() or {}) do
                if IsValid(child) and child._grmChrome then child:Remove() end
            end
            ui.incassoVehicles = {}
            ui.incassoRoleBoxes = {}
            ui.chkIncassoEnabled = nil
            setIncassoDirty(false)

            local f = data and data[factionName]
            if not f then
                local err = vgui.Create("DLabel", incLeft)
                err._grmChrome = true
                err:Dock(TOP) err:DockMargin(8, 16, 8, 8)
                err:SetText("Фракция «" .. tostring(factionName) .. "» не найдена в данных")
                err:SetFont("Factions_Normal") err:SetTextColor(THEME.danger)
                err:SizeToContents()
                fillVehicleCombo()
                return
            end
            local inc = istable(f.IncassoSettings) and f.IncassoSettings or { Enabled = false, Roles = {}, Vehicles = {} }
            local roles = f.Roles or {}
            local vehList = inc.Vehicles or {}

            -- Включение инкассации
            local chkEnabled = vgui.Create("DCheckBoxLabel", incLeft)
            chkEnabled._grmChrome = true
            chkEnabled:Dock(TOP) chkEnabled:DockMargin(4, 4, 4, 10)
            chkEnabled:SetText("Включить инкассацию для фракции «"..GRM.Factions.DisplayName(f,factionName).."»")
            chkEnabled:SetFont("Factions_Normal") chkEnabled:SetTextColor(THEME.text)
            chkEnabled:SetValue(inc.Enabled == true)
            chkEnabled.OnChange = markIncassoDirty
            ui.chkIncassoEnabled = chkEnabled

            -- Заголовок ролей внутри скролла
            local rSub = vgui.Create("DLabel", incLeft)
            rSub._grmChrome = true
            rSub:Dock(TOP) rSub:DockMargin(4, 8, 4, 6)
            rSub:SetFont("Factions_Small") rSub:SetTextColor(THEME.textDim)
            rSub:SetText("Поставьте галочки напротив ролей, которым разрешено заниматься инкассацией (напр. «Инкассатор», а НЕ «Аудитор»):")
            rSub:SetWrap(true) rSub:SetTall(32)

            for _, roleName in ipairs(roles) do
                local chk = vgui.Create("DCheckBoxLabel", incLeft)
                chk._grmChrome = true
                chk:Dock(TOP) chk:DockMargin(24, 2, 4, 2)
                chk:SetText(roleName)
                chk:SetFont("Factions_Small") chk:SetTextColor(THEME.text)
                local checked = false
                for _, r in ipairs(inc.Roles or {}) do if r == roleName then checked = true break end end
                chk:SetValue(checked)
                chk.OnChange = markIncassoDirty
                ui.incassoRoleBoxes[roleName] = chk
            end

            -- Список ТС
            local function renderVehRow(className)
                local row = vgui.Create("DPanel", incVehScroll)
                row._grmChrome = true
                row:Dock(TOP) row:SetTall(28) row:DockMargin(0, 0, 0, 2)
                function row:Paint(w, h) draw.RoundedBox(4, 0, 0, w, h, THEME.bgLight) end
                local lbl = vgui.Create("DLabel", row)
                lbl:Dock(LEFT) lbl:DockMargin(8, 6, 8, 0)
                lbl:SetFont("Factions_Small") lbl:SetTextColor(THEME.text)
                lbl:SetText(className) lbl:SizeToContents()
                local btnDel = styledButton(row, "✕", THEME.danger, THEME.dangerHover)
                btnDel:Dock(RIGHT) btnDel:SetWide(36) btnDel:DockMargin(4, 3, 4, 3)
                btnDel.DoClick = function()
                    row:Remove()
                    for i, v in ipairs(ui.incassoVehicles) do
                        if v.entry == className then table.remove(ui.incassoVehicles, i) break end
                    end
                    markIncassoDirty()
                end
                ui.incassoVehicles[#ui.incassoVehicles + 1] = { row = row, entry = className }
            end

            for _, v in ipairs(vehList) do
                if type(v) == "string" and v ~= "" then renderVehRow(v) end
            end

            btnIncassoAddVeh.DoClick = function()
                local val = string.Trim(incVehEntry:GetText() or "")
                if val == "" then notification.AddLegacy("Введите spawn-name класса ТС", NOTIFY_ERROR, 3) return end
                for _, ex in ipairs(ui.incassoVehicles) do
                    if ex.entry == val then notification.AddLegacy("Такой класс уже добавлен", NOTIFY_ERROR, 3) return end
                end
                renderVehRow(val)
                incVehEntry:SetText("")
                markIncassoDirty()
            end
            incVehEntry.OnEnter = function() btnIncassoAddVeh:DoClick() end

            fillVehicleCombo()
            function incVehCombo:OnSelect(_, _, _, data)
                if not data then return end
                for _, ex in ipairs(ui.incassoVehicles) do if ex.entry == data then return end end
                renderVehRow(data)
                markIncassoDirty()
                incVehCombo:ChooseOptionID(1)
            end
        end
        ui.updateIncassoPanel = updateIncassoPanel

        btnIncassoSave.DoClick = function()
            local fName = factionComboIncasso:GetValue()
            if not fName or fName == "" then
                notification.AddLegacy("Выберите фракцию", NOTIFY_ERROR, 3); return
            end
            local enabled = IsValid(ui.chkIncassoEnabled) and ui.chkIncassoEnabled:GetChecked() or false
            local roles = {}
            for rn, cb in pairs(ui.incassoRoleBoxes or {}) do
                if IsValid(cb) and cb:GetChecked() then roles[#roles + 1] = rn end
            end
            local vehicles = {}
            local seen = {}
            for _, v in ipairs(ui.incassoVehicles or {}) do
                if type(v.entry) == "string" and v.entry ~= "" and not seen[v.entry] then
                    seen[v.entry] = true; vehicles[#vehicles + 1] = v.entry
                end
            end
            sendAction("saveIncasso", { fName, enabled, roles, vehicles }, function(ok, msg)
                if ok then
                    setIncassoDirty(false)
                    notification.AddLegacy(msg or "Сохранено", NOTIFY_GENERIC, 4)
                    getData(function(d) FactionsData = d or {} refreshAllUI(FactionsData) end)
                else
                    notification.AddLegacy("Ошибка: " .. tostring(msg), NOTIFY_ERROR, 4)
                end
            end)
        end

        factionComboIncasso.OnSelect = function(_, idx, fName)
            -- Используем локальный кэш, а не идём в сеть (сеть приходит с задержкой
            -- и может перетереть выбор старым ответом). Если кэша нет — запрашиваем.
            local function apply(d)
                if ui.updateIncassoPanel then ui.updateIncassoPanel(fName, d or FactionsData or {}) end
            end
            if FactionsData and FactionsData[fName] then
                apply(FactionsData)
            else
                getData(function(data) FactionsData = data or {}; apply(data) end)
            end
        end

        ui.incassoPanel = incassoPanel
        local incSheet = tabs:AddSheet("Инкассация", incassoPanel, "icon16/money.png")
        -- При активации вкладки «Инкассация» — если фракция не выбрана, авто-выбираем первую
        -- и запрашиваем данные. Это спасает от ситуации «открыл вкладку, а там пусто».
        function incassoPanel:PerformLayout()
            if self._incassoFirstInit then return end
            self._incassoFirstInit = true
            timer.Simple(0, function()
                if not IsValid(ui.factionComboIncasso) or not IsValid(incassoPanel) then return end
                local cur = ui.factionComboIncasso:GetValue()
                if cur and cur ~= "" then return end
                local first = ui.factionComboIncasso:GetOptionData(1)
                local firstName = ui.factionComboIncasso:GetOptionText(1)
                if firstName and firstName ~= "" then
                    ui.factionComboIncasso:SetValue(firstName)
                    getData(function(data)
                        if ui.updateIncassoPanel then ui.updateIncassoPanel(firstName, data or FactionsData or {}) end
                    end)
                end
            end)
        end

        -- GRM hook: сторонние модули достраивают вкладки админки (Коды 75/76 — доступы к эфиру, оповещению, доске)
        if hook and hook.Call then
            pcall(hook.Call, "GRM_FactionsAdmin_BuildTabs", nil, tabs)
        end


        -- FIX: При открытии меню запрашиваем данные с сервера (factions.json)
        timer.Simple(0.4, function()
            if IsValid(frame) then
                getData(function(data)
                    FactionsData = data or {}
                    refreshAllUI(FactionsData)
                end)
            end
        end)

        frame.OnClose = function()
            ui.currentFrame = nil
            ui.depWaveScroll = nil
            ui.editTagEntry = nil
            ui.editColorPreview = nil
            -- Код 108: гасим все ссылки «живых» вкладок админки
            ui.listView = nil
            ui.factionCombo = nil
            ui.factionComboRanks = nil
            ui.ranksScroll = nil
            ui.factionComboDepts = nil
            ui.deptsScroll = nil
            ui.factionCombo3 = nil
            ui.roleCombo3 = nil
            ui.deptCombo3 = nil
            ui.factionComboList = nil
            ui.memberScroll = nil
            -- Код 126
            ui.factionComboIncasso = nil
            ui.incassoScroll = nil
            ui.incassoVehScroll = nil
            ui.incassoVehEntry = nil
            ui.incassoVehCombo = nil
            ui.incassoVehicles = nil
            ui.incassoRoleBoxes = nil
            ui.chkIncassoEnabled = nil
            ui.updateIncassoPanel = nil
            ui.incassoPanel = nil
        end

        frame:Show()
    end

    -- ============================================================
    -- МЕНЮ ЛИДЕРА (FIX: Unified Factions UI v2.0)
    -- ============================================================
    function OpenLeaderMenu(facName)
        if GRM and GRM.Factions and GRM.Factions.UnifiedUI and GRM.Factions.UnifiedUI.Open then
            GRM.Factions.UnifiedUI.Open(facName)
            return
        end

        local frame = vgui.Create("DFrame")
        frame:SetTitle("")
        frame:SetSize(1280, 860) frame:Center() frame:MakePopup()
        ui.leaderMenuOpen = true
        ui.currentFrame   = frame

        function frame:Paint(w, h)
            draw.RoundedBox(6, 0, 0, w, h, THEME.bg)
            draw.RoundedBoxEx(6, 0, 0, w, 32, Color(35, 35, 45), true, true, false, false)
            draw.SimpleText("Управление фракцией", "Factions_Title", 12, 16, THEME.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end

        local tabs = vgui.Create("DPropertySheet", frame)
        tabs:Dock(FILL) tabs:DockMargin(4, 36, 4, 4)
        function tabs:Paint(w, h)
            surface.SetDrawColor(THEME.bgLight)
            surface.DrawRect(0, 0, w, h)
        end

        -- Ранги
        local ranksPanel = vgui.Create("DPanel")
        ranksPanel:SetPaintBackground(false) ranksPanel:DockPadding(10, 10, 10, 10)
        local ranksScroll = vgui.Create("DScrollPanel", ranksPanel)
        ranksScroll:SetPos(10, 10) ranksScroll:SetSize(1230, 750)
        ui.ranksScrollLeader = ranksScroll
        tabs:AddSheet("Ранги", ranksPanel, "icon16/user.png")

        -- Отделы
        local deptsPanel = vgui.Create("DPanel")
        deptsPanel:SetPaintBackground(false) deptsPanel:DockPadding(10, 10, 10, 10)
        local deptsScroll = vgui.Create("DScrollPanel", deptsPanel)
        deptsScroll:SetPos(10, 10) deptsScroll:SetSize(1230, 750)
        ui.deptsScrollLeader = deptsScroll
        tabs:AddSheet("Отделы", deptsPanel, "icon16/brick.png")

        -- Участники
        local memberPanel = vgui.Create("DPanel")
        memberPanel:SetPaintBackground(false) memberPanel:DockPadding(15, 10, 15, 10)
        local Y = 10

        local lblOnline = vgui.Create("DLabel", memberPanel)
        lblOnline:SetText("Онлайн:") lblOnline:SetPos(15, Y + 3) lblOnline:SetSize(80, 20)
        lblOnline:SetFont("Factions_Normal") lblOnline:SetTextColor(THEME.text)

        local onlineCombo = vgui.Create("DComboBox", memberPanel)
        onlineCombo:SetPos(100, Y) onlineCombo:SetSize(280, 26)
        onlineCombo:SetFont("Factions_Normal")
        populateOnlinePlayerCombo(onlineCombo)
        Y = Y + 36

        local lblTarget = vgui.Create("DLabel", memberPanel)
        lblTarget:SetText("Ключ/ID:") lblTarget:SetPos(15, Y + 3) lblTarget:SetSize(80, 20)
        lblTarget:SetFont("Factions_Normal") lblTarget:SetTextColor(THEME.textDim)

        local targetEntry = vgui.Create("DTextEntry", memberPanel)
        targetEntry:SetPos(100, Y) targetEntry:SetSize(280, 26) targetEntry:SetFont("Factions_Normal")
        Y = Y + 40

        onlineCombo.OnSelect = function(_, _, _, dataKey)
            if isstring(dataKey) and dataKey ~= "" then
                targetEntry:SetText(dataKey)
            end
        end

        local lblRoleL = vgui.Create("DLabel", memberPanel)
        lblRoleL:SetText("Роль:") lblRoleL:SetPos(15, Y + 3) lblRoleL:SetSize(80, 20)
        lblRoleL:SetFont("Factions_Normal") lblRoleL:SetTextColor(THEME.text)

        local roleCombo = vgui.Create("DComboBox", memberPanel)
        roleCombo:SetPos(100, Y) roleCombo:SetSize(200, 26)
        ui.roleComboLeader = roleCombo -- Код 108: живое комбо (пересборка в refreshAllUI)
        Y = Y + 40

        local lblDeptL = vgui.Create("DLabel", memberPanel)
        lblDeptL:SetText("Отдел:") lblDeptL:SetPos(15, Y + 3) lblDeptL:SetSize(80, 20)
        lblDeptL:SetFont("Factions_Normal") lblDeptL:SetTextColor(THEME.text)

        local deptCombo = vgui.Create("DComboBox", memberPanel)
        deptCombo:SetPos(100, Y) deptCombo:SetSize(200, 26)
        ui.deptComboLeader = deptCombo -- Код 108: живое комбо
        Y = Y + 45

        getData(function(data)
            for _, f in pairs(data or {}) do
                if istable(f) and clientIsLeaderOfFaction(f) then
                    for _, role in ipairs(f.Roles or {}) do roleCombo:AddChoice(role) end
                    for _, dept in ipairs(f.Departments or {}) do deptCombo:AddChoice(dept) end
                    break
                end
            end
        end)

        local btnInvite = styledButton(memberPanel, "✉ Пригласить", THEME.accent, THEME.accentDark)
        btnInvite:SetPos(15, Y) btnInvite:SetSize(130, 30)
        btnInvite.DoClick = function()
            local steam = targetEntry:GetText()
            if steam == "" then return end
            local factionName=clientGetLeaderFaction(FactionsData);if not factionName then notification.AddLegacy("Фракция лидера не найдена",NOTIFY_ERROR,3)return end
            local role,dept=roleCombo:GetValue()or"",deptCombo:GetValue()or"";confirmInvite(factionName,steam,role,dept,function()sendAction("inviteMember",{steam,role,dept},function(ok,msg)if ok then notification.AddLegacy(msg~=""and msg or"Приглашение отправлено",NOTIFY_GENERIC,5)else notification.AddLegacy("Ошибка: "..msg,NOTIFY_ERROR,4)end end)end)
        end

        local btnRemoveMember = styledButton(memberPanel, "✕ Уволить", THEME.danger, THEME.dangerHover)
        btnRemoveMember:SetPos(155, Y) btnRemoveMember:SetSize(110, 30)
        btnRemoveMember.DoClick = function()
            local steam = targetEntry:GetText()
            if steam == "" then return end
            sendAction("removeMember", { steam }, function(ok, msg)
                if ok then notification.AddLegacy("Уволен", NOTIFY_GENERIC, 3) refreshAllUI()
                else notification.AddLegacy("Ошибка: " .. msg, NOTIFY_ERROR, 3) end
            end)
        end
        Y = Y + 40

        local btnSetRole = styledButton(memberPanel, "★ Назначить роль", THEME.accent, THEME.accentDark)
        btnSetRole:SetPos(15, Y) btnSetRole:SetSize(150, 30)
        btnSetRole.DoClick = function()
            local steam = targetEntry:GetText()
            local role  = roleCombo:GetValue()
            if steam == "" or not role then return end
            sendAction("setRole", { steam, role }, function(ok, msg)
                if ok then notification.AddLegacy("Роль назначена", NOTIFY_GENERIC, 3) refreshAllUI()
                else notification.AddLegacy("Ошибка: " .. msg, NOTIFY_ERROR, 3) end
            end)
        end

        local btnSetDept = styledButton(memberPanel, "⬚ Назначить отдел", THEME.accent, THEME.accentDark)
        btnSetDept:SetPos(175, Y) btnSetDept:SetSize(160, 30)
        btnSetDept.DoClick = function()
            local steam = targetEntry:GetText()
            local dept  = deptCombo:GetValue()
            if steam == "" or not dept then return end
            sendAction("setDepartment", { steam, dept }, function(ok, msg)
                if ok then notification.AddLegacy("Отдел назначен", NOTIFY_GENERIC, 3) refreshAllUI()
                else notification.AddLegacy("Ошибка: " .. msg, NOTIFY_ERROR, 3) end
            end)
        end
        tabs:AddSheet("Участники", memberPanel, "icon16/user_edit.png")

        -- Список участников
        local memberListPanel = vgui.Create("DPanel")
        memberListPanel:SetPaintBackground(false) memberListPanel:DockPadding(10, 10, 10, 10)

        local titleLabel = vgui.Create("DLabel", memberListPanel)
        titleLabel:SetPos(10, 10) titleLabel:SetSize(400, 20)
        titleLabel:SetFont("Factions_Title") titleLabel:SetTextColor(THEME.accent)
        ui.leaderTitleLabel = titleLabel

        local scrollPanel = vgui.Create("DScrollPanel", memberListPanel)
        scrollPanel:SetPos(10, 40) scrollPanel:SetSize(1230, 720)
        ui.memberScrollLeader = scrollPanel
        tabs:AddSheet("Список участников", memberListPanel, "icon16/user_go.png")

        -- GRM hook: сторонние модули достраивают вкладки (находка 172 — «Экономика»)
        if hook and hook.Call then
            pcall(hook.Call, "GRM_FactionsAdmin_BuildTabs", nil, tabs)
        end

        -- FIX: При открытии меню лидера запрашиваем данные с сервера (factions.json)
        getData(function(data)
            FactionsData = data or {}
            refreshAllUI(FactionsData)
        end)
        timer.Simple(0.2, function()
            if IsValid(frame) then
                getData(function(data)
                    FactionsData = data or {}
                    refreshAllUI(FactionsData)
                end)
            end
        end)

        frame.OnClose = function()
            ui.leaderMenuOpen = false
            ui.currentFrame = nil
            ui.ranksScrollLeader = nil
            ui.deptsScrollLeader = nil
            ui.memberScrollLeader = nil
            ui.leaderTitleLabel = nil
            ui.roleComboLeader = nil -- Код 108: живые комбо лидера
            ui.deptComboLeader = nil
        end

        frame:Show()
    end

    -- ============================================================
    -- КОМАНДЫ ЧАТА (клиентские)
    -- ============================================================
    hook.Add("PlayerSayTransform", "Factions_PlayerCommands", function(ply, datapack, is_team, is_local)
        if ply ~= LocalPlayer() then return end
        local msg = datapack[1]
        if not msg then return end
        local lower = msg:lower()

        if lower:find("^/fjoin") == 1 then
            local factionName = msg:sub(7):Trim()
            net.Start(NET_JOIN) net.WriteString(factionName) net.SendToServer()
            datapack[1] = "" return
        end
        if lower:find("^/fdecline%s+") == 1 then
            local factionName = msg:sub(10):Trim()
            if factionName == "" then datapack[1] = "" return end
            net.Start(NET_DECLINE) net.WriteString(factionName) net.SendToServer()
            datapack[1] = "" return
        end
        if lower:find("^/fleave%s*") == 1 then
            net.Start(NET_LEAVE) net.SendToServer()
            datapack[1] = "" return
        end
        if lower:find("^/fr%s+") == 1 then
            local text = msg:sub(4)
            if text == "" then datapack[1] = "" return end
            net.Start(NET_RADIO) net.WriteString(text) net.SendToServer()
            datapack[1] = "" return
        end
        -- /frb, /frooc — рация фракции нон-РП (OOC).
        if lower:find("^/frb%s+") == 1 or lower:find("^/frooc%s+") == 1 then
            local cut = lower:find("^/frb%s+") == 1 and 5 or 7
            local text = msg:sub(cut):Trim()
            if text == "" then datapack[1] = "" return end
            net.Start(NET_RADIOB) net.WriteString(text) net.SendToServer()
            datapack[1] = "" return
        end
        if lower:find("^/dep%s+") == 1 or lower:find("^/d%s+") == 1 then
            local offset = (lower:find("^/dep%s+") == 1) and 6 or 3
            local text = msg:sub(offset):Trim()
            if text == "" then datapack[1] = "" return end
            net.Start(NET_DEP) net.WriteString(text) net.SendToServer()
            datapack[1] = "" return
        end
        if lower:find("^/depb%s+") == 1 then
            local text = msg:sub(7):Trim()
            if text == "" then datapack[1] = "" return end
            net.Start(NET_DEPB) net.WriteString(text) net.SendToServer()
            datapack[1] = "" return
        end
        if lower:find("^/db%s+") == 1 then
            local text = msg:sub(4):Trim()
            if text == "" then datapack[1] = "" return end
            net.Start(NET_DEPB) net.WriteString(text) net.SendToServer()
            datapack[1] = "" return
        end
    end)

    -- ============================================================
    -- КОНСОЛЬНЫЕ КОМАНДЫ
    -- ============================================================
    concommand.Add("factions", function()
        if LocalPlayer():IsSuperAdmin() then OpenAdminMenu() return end

        getData(function(data)
            for _, f in pairs(data or {}) do
                if istable(f) and clientIsLeaderOfFaction(f) then OpenLeaderMenu() return end
            end
            -- Находка 172: не лидер, но возможно есть доступ к экономике
            -- (лидер/зам Нацбанка). Просим сервер — он сам решит и пришлёт
            -- NET_OPEN_ADMIN, если CanManageEconomy.
            net.Start(NET_OPEN_ADMIN)
            net.SendToServer()
        end)
    end)

    -- ============================================================
    -- HUD — НАДПИСИ НАД ИГРОКАМИ
    -- ============================================================
    -- Обратный индекс «CharacterKey → {фракция, роль, цвет, тег}».
    -- Раньше HUD для каждого ближнего игрока делал ВЛОЖЕННЫЙ обход всех
    -- фракций (O(игроки × фракции) каждый кадр). Теперь индекс строится
    -- один раз при изменении FactionsData и даёт O(1) на кадр.
    local factionHUDCache = { ref = nil, index = nil }
    local function factionHUDInfo(steam)
        local data = FactionsData
        if factionHUDCache.ref ~= data then
            local idx = {}
            for fname, fdata in pairs(data or {}) do
                if istable(fdata) and istable(fdata.Members) then
                    local col = fdata.Color or {}
                    local cr, cg, cb = tonumber(col.r) or 255, tonumber(col.g) or 200, tonumber(col.b) or 50
                    local tag = (fdata.Tag and fdata.Tag ~= "") and fdata.Tag or ""
                    for memberKey, rec in pairs(fdata.Members) do
                        if istable(rec) then
                            -- Теги отдела и подотдела попадают и в шапку над игроком:
                            -- «[ПД | СВАТ] Полиция [Сержант]».
                            local full = GRM.Factions.ChannelTag(fdata, rec.Department, rec.Subdepartment, tag, rec.Position)
                            if tag == "" and full == GRM.Factions.DisplayName(fname) then full = "" end
                            idx[memberKey] = { fname, rec.Role, Color(cr, cg, cb), full }
                        end
                    end
                end
            end
            factionHUDCache.ref = data
            factionHUDCache.index = idx
        end
        return factionHUDCache.index and factionHUDCache.index[steam]
    end

    hook.Add("HUDPaint", "Factions_HUD", function()
        -- 21.08: шапку организации теперь рисует общий GRM.Nameplate одной
        -- плашкой вместе с именем и описанием. Пока он активен, старая
        -- отрисовка молчит (иначе над головой две подписи внахлёст).
        if GRM.Nameplate and GRM.Nameplate.Active then return end
        local lp = LocalPlayer()
        if not IsValid(lp) then return end
        local radius = GetConVarNumber("rpdesc_radius") or 5000

        -- Кэш списка игроков: player.GetAll() в HUDPaint создавал новую
        -- таблицу 60 раз в секунду (мусор для GC на каждом кадре).
        for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            -- Код 108: continue→инвертированное условие (ванильный Lua)
            if IsValid(ply) and ply:Alive() and ply ~= lp
                and lp:GetPos():Distance(ply:GetPos()) <= radius then
                local info = factionHUDInfo(clientMemberKey(ply))
                if info then
                    local faction, role, fColor, fTag = info[1], info[2], info[3], info[4]
                    -- Готовая шапка приходит с сервера NW-строкой: у игроков без
                    -- полного снимка организаций (публичный синк) отделов в
                    -- FactionsData нет, а тег отдела показать всё равно надо.
                    local nwTag = ply:GetNWString("GRM_ChannelTag", "")
                    if nwTag ~= "" then fTag = nwTag end
                    local pos = ply:GetPos() + Vector(0, 0, 100)
                    local screenPos = pos:ToScreen()
                    if screenPos.visible then
                        local x, y = screenPos.x, screenPos.y

                        local displayFaction = (fTag ~= "") and ("[" .. fTag .. "] " .. faction) or faction
                        local text = displayFaction .. (role and (" [" .. role .. "]") or "")

                        surface.SetFont("Factions_HUD")
                        local tw, th = surface.GetTextSize(text)
                        local padding = 8
                        local w = tw + padding * 2
                        local h = th + padding * 2

                        draw.RoundedBox(4, x - w / 2, y - h / 2, w, h, Color(15, 15, 20, 180))
                        surface.SetDrawColor(fColor.r, fColor.g, fColor.b, 220)
                        surface.DrawRect(x - w / 2, y + h / 2 - 3, w, 3)
                        draw.SimpleText(text, "Factions_HUD", x, y, fColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                    end
                end
            end
        end
    end)

    net.Receive(NET_OPEN_ADMIN, function()
        if OpenUnifiedFactionsMenu then OpenUnifiedFactionsMenu() else OpenAdminMenu() end
    end)
    net.Receive(NET_OPEN_LEADER, function()
        if OpenUnifiedFactionsMenu then OpenUnifiedFactionsMenu() else OpenLeaderMenu() end
    end)

    print("[Factions] Клиентская часть загружена (v3.2 dual names + /factions)")
end
