--[[ GRMAPI — реестр stub-интерфейсов режима (архитектура WIKI 4.16.2)

    межмодульный вызов нереализованной функции НЕ падает и НЕ теряется:
    он буферизуется и исполняется после реализации (GRMAPI.define →
    немедленный флеш, или GRMAPI.finish в конце загрузки). Это снимает
    требование порядка загрузки модулей и лечит класс багов
    «local-функция ниже места вызова» на уровне системы.

    Сигнатуры (description/parameters/returns) обязательны — они же
    документация (`grmrp_api_dump`), они же контракт для будущих портов.
]]

GRMAPI = GRMAPI or {}

local stubs = {}
local pending = {}          -- имя → очередь вызовов {args}
local MAX_PENDING = 256     -- потолок на имя: незакрытый stub не должен
                            -- раздувать память (урок unbounded-буферов)

local REALMS = { Shared = true, Server = true, Client = true }

local function isNonEmptyString(v)
    return isstring(v) and #v > 0
end

local function checkParam(p)
    return istable(p)
        and isNonEmptyString(p.name)
        and isNonEmptyString(p.description)
        and isNonEmptyString(p.type)
        and (p.optional == nil or isbool(p.optional))
end

local function checkValue(v)
    return istable(v)
        and isNonEmptyString(v.name)
        and isNonEmptyString(v.description)
        and isNonEmptyString(v.type)
end

-- Разрешение имени метатаблицы в рантайме загрузки (Player/Entity/GM/GRMRP...).
local function resolveMeta(name)
    if name == "GM" then return GRMRP.GM or _G.GM end
    local tbl = _G[name]
    if istable(tbl) then return tbl end
    if name == "Player" or name == "Entity" or name == "Vector" or name == "Angle" then
        return FindMetaTable(name)
    end
    return nil
end

local function flush(name)
    local queue = pending[name]
    if not queue then return end
    pending[name] = nil
    local info = stubs[name]
    if not info or not info.impl then return end
    for i = 1, #queue do
        local ok, err = pcall(info.impl, unpack(queue[i]))
        if not ok then
            GRMRP.ErrorNoHalt("GRMAPI: отложенный вызов «", name, "» упал: ", err)
        end
    end
end

--[[ GRMAPI.stub{
        name        = "chat.sendSystem",   -- путь внутри метатаблицы
        metatable   = "GRMRPChat",
        description = "...",
        parameters  = { {name=..., description=..., type=..., optional=bool}, ... },
        returns     = { {name=..., description=..., type=...}, ... },   -- необязательно
        realm       = "Server",                                          -- необязательно
    }
    Возвращает функцию-заглушку: вызов до реализации буферизуется. ]]
function GRMAPI.stub(spec)
    if not istable(spec) then error("GRMAPI.stub: spec должен быть таблицей", 2) end
    if not isNonEmptyString(spec.name) then error("GRMAPI.stub: нет name", 2) end
    if not isNonEmptyString(spec.description) then error("GRMAPI.stub: нет description", 2) end
    if not istable(spec.parameters) then error("GRMAPI.stub: нет parameters", 2) end
    for i = 1, #spec.parameters do
        if not checkParam(spec.parameters[i]) then
            error("GRMAPI.stub: некорректный параметр №" .. i .. " у «" .. spec.name .. "»", 2)
        end
    end
    if spec.returns then
        for i = 1, #spec.returns do
            if not checkValue(spec.returns[i]) then
                error("GRMAPI.stub: некорректное возвращаемое значение №" .. i .. " у «" .. spec.name .. "»", 2)
            end
        end
    end
    if spec.realm and not REALMS[spec.realm] then
        error("GRMAPI.stub: realm должен быть Shared/Server/Client", 2)
    end
    if stubs[spec.name] then
        error("GRMAPI.stub: дубль имени «" .. spec.name .. "»", 2)
    end

    local info = {
        name = spec.name,
        description = spec.description,
        parameters = spec.parameters,
        returns = spec.returns or {},
        realm = spec.realm or "Shared",
        metatable = spec.metatable or "GRMRP",
        impl = nil
    }
    stubs[spec.name] = info

    local name = spec.name
    return function(...)
        if info.impl then return info.impl(...) end
        local q = pending[name]
        if not q then q = {} pending[name] = q end
        if #q < MAX_PENDING then
            table.insert(q, { ... })
        else
            GRMRP.ErrorNoHalt("GRMAPI: очередь «", name, "» переполнена — вызов брошен")
        end
    end
end

-- Реализация: вешает функцию на метатаблицу, флешит очередь, помечает stub.
function GRMAPI.define(name, fn)
    local info = stubs[name]
    if not info then error("GRMAPI.define: неизвестный stub «" .. tostring(name) .. "»", 2) end
    if not isfunction(fn) then error("GRMAPI.define: «" .. name .. "»: ожидается функция", 2) end
    local meta = resolveMeta(info.metatable)
    if not meta then error("GRMAPI.define: метатаблица «" .. info.metatable .. "» не найдена", 2) end
    info.impl = fn
    meta[name] = fn
    flush(name)
    return fn
end

-- Прямая реализация без предварительного stub (внутримодульные хелпы).
function GRMAPI.provide(name, fn, metatableName)
    if stubs[name] then return GRMAPI.define(name, fn) end
    local meta = resolveMeta(metatableName or "GRMRP")
    if meta then meta[name] = fn end
end

-- Сброс неотложенных вызовов после полной загрузки: незакрытые stub'ы
-- объявляются ошибкой конфигурации (не молчим — §9.3).
function GRMAPI.finish()
    for name, q in pairs(pending) do
        if #q > 0 then
            GRMRP.ErrorNoHalt("GRMAPI: stub «", name, "» не реализован, ",
                #q, " отложенных вызовов сброшены")
        end
        pending[name] = nil
    end
end

function GRMRP_API_Dump(includeClient)
    local lines = {}
    for name in SortedPairs(stubs) do
        local s = stubs[name]
        table.insert(lines, string.format("%-40s [%s] %s — %s%s",
            name, s.realm, s.metatable,
            s.impl and "реализован" or "НЕ реализован",
            "\n  " .. s.description))
    end
    local text = table.concat(lines, "\n")
    if SERVER then
        PrintMessage(HUD_PRINTTALK, "GRMAPI stubs (" .. tostring(#lines) .. "):\n" .. text)
        for _, ply in ipairs(player.GetAll()) do
            if includeClient or ply:IsSuperAdmin() then
                ply:ChatPrint("GRMAPI: " .. #lines .. " stub'ов, детали в консоли")
            end
        end
    end
    return text
end

concommand.Add("grmrp_api_dump", function(ply)
    if IsValid(ply) and not ply:IsListenServerHost() and not ply:IsSuperAdmin() then
        if not GRMRP.Can or not GRMRP.Can(ply, "api.dump") then return end
    end
    GRMRP_API_Dump(false)
end)
