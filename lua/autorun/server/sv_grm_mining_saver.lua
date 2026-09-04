--[[--------------------------------------------------------------------
    GRM Saver — постоянное сохранение оборудования на карте

    Включая:
      grm_ore_buyer  — скупщик руды
      grm_ore_node
      grm_worktable
      grm_storage
      grm_box

    Установка:
      lua/autorun/server/sv_grm_saver.lua

    ВАЖНО: замените этим файлом старый GRM Saver. Не запускайте обе
    версии одновременно, иначе они будут одновременно загружать/удалять
    одни и те же entity.
----------------------------------------------------------------------]]

if CLIENT then return end

local SAVE_DIR = "grm_saves"
local SAVE_FILE = SAVE_DIR .. "/" .. string.lower(game.GetMap() or "unknown") .. ".json"

-- Режим сохранения: по умолчанию ТОЛЬКО вручную через !saveentities.
-- Автозагрузка при старте карты остаётся включённой.
-- Если когда-нибудь понадобится автосейв, измените значения ниже.
local AUTO_SAVE_INTERVAL = 0        -- секунды; 0 = выключено
local AUTO_SAVE_ON_CHANGE = false   -- не перезаписывать файл при спавне/удалении entity
local SAVE_ON_SHUTDOWN = false      -- не перезаписывать ручной сейв при выключении сервера

local CLASSES_TO_SAVE = {

    grm_ore_buyer = true, -- СКУПЩИК РУДЫ
    grm_ore_node = true,


}

local State = {
    loading = false,
    queued = false,
}

local function ensureDirectory()
    if not file.Exists(SAVE_DIR, "DATA") then
        file.CreateDir(SAVE_DIR)
    end
end

local function isPersistentEntity(ent)
    return IsValid(ent) and CLASSES_TO_SAVE[ent:GetClass()] == true
end

local function vectorToTable(vec)
    return { x = vec.x, y = vec.y, z = vec.z }
end

local function angleToTable(ang)
    return { p = ang.p, y = ang.y, r = ang.r }
end

local function tableToVector(data)
    return Vector(
        tonumber(data and (data.x or data[1])) or 0,
        tonumber(data and (data.y or data[2])) or 0,
        tonumber(data and (data.z or data[3])) or 0
    )
end

local function tableToAngle(data)
    return Angle(
        tonumber(data and (data.p or data[1])) or 0,
        tonumber(data and (data.y or data[2])) or 0,
        tonumber(data and (data.r or data[3])) or 0
    )
end

function GRM_SaveEntities()
    if State.loading then return 0 end

    ensureDirectory()

    local records = {}
    local perClass = {}

    for _, ent in ipairs(ents.GetAll()) do
        if isPersistentEntity(ent) then
            local physics = ent:GetPhysicsObject()
            local class = ent:GetClass()
            perClass[class] = (perClass[class] or 0) + 1

            records[#records + 1] = {
                class = ent:GetClass(),
                model = ent:GetModel() or "",
                pos = vectorToTable(ent:GetPos()),
                ang = angleToTable(ent:GetAngles()),
                frozen = IsValid(physics) and not physics:IsMotionEnabled() or false,
            }
        end
    end

    local json = util.TableToJSON(records, true)
    if not json then
        ErrorNoHalt("[GRM Saver] Не удалось сериализовать список entity.\n")
        return 0
    end

    file.Write(SAVE_FILE, json)

    local parts = {}
    for class, amount in pairs(perClass) do
        parts[#parts + 1] = class .. "=" .. amount
    end
    table.sort(parts)

    print("[GRM Saver] Сохранено entity: " .. #records .. " (" .. table.concat(parts, ", ") .. ")")

    return #records
end

local function queueSave()
    if State.loading or not AUTO_SAVE_ON_CHANGE then return end

    timer.Remove("GRM_Saver_QueuedSave")
    timer.Create("GRM_Saver_QueuedSave", 2, 1, function()
        State.queued = false
        GRM_SaveEntities()
    end)

    State.queued = true
end

function GRM_ClearSavedEntities()
    State.loading = true

    for _, ent in ipairs(ents.GetAll()) do
        if isPersistentEntity(ent) then
            ent:Remove()
        end
    end
end

function GRM_LoadEntities()
    ensureDirectory()

    if not file.Exists(SAVE_FILE, "DATA") then
        print("[GRM Saver] Нет сохранения для карты: " .. game.GetMap())
        State.loading = false
        return 0
    end

    local raw = file.Read(SAVE_FILE, "DATA") or ""
    if raw == "" then
        State.loading = false
        return 0
    end

    local ok, records = pcall(util.JSONToTable, raw)
    if not ok or not istable(records) then
        ErrorNoHalt("[GRM Saver] Файл сохранения повреждён: " .. SAVE_FILE .. "\n")
        State.loading = false
        return 0
    end

    GRM_ClearSavedEntities()

    local expected = 0
    local count = 0
    local loadedByClass = {}
    local failed = {}

    for index, record in ipairs(records) do
        if istable(record) and CLASSES_TO_SAVE[record.class] then
            expected = expected + 1
            local ent = ents.Create(record.class)

            if IsValid(ent) then
                ent:SetPos(tableToVector(record.pos))
                ent:SetAngles(tableToAngle(record.ang))

                -- Нужен до Spawn для entity, чья физика зависит от модели.
                if isstring(record.model) and record.model ~= "" then
                    ent:SetModel(record.model)
                end

                ent:Spawn()
                ent:Activate()

                if record.frozen then
                    timer.Simple(0, function()
                        if not IsValid(ent) then return end

                        local physics = ent:GetPhysicsObject()
                        if IsValid(physics) then
                            physics:EnableMotion(false)
                            physics:Sleep()
                        end
                    end)
                end

                count = count + 1
                loadedByClass[record.class] = (loadedByClass[record.class] or 0) + 1
            else
                failed[#failed + 1] = "#" .. index .. " " .. tostring(record.class)
                ErrorNoHalt("[GRM Saver] Не удалось создать entity #" .. index .. ": " .. tostring(record.class) .. "\n")
            end
        elseif istable(record) then
            failed[#failed + 1] = "#" .. index .. " unsupported: " .. tostring(record.class)
        else
            failed[#failed + 1] = "#" .. index .. " invalid record"
        end
    end

    -- Пока завершались Spawn() и EntityRemoved(), не даём хукам перезаписать
    -- файл пустым списком. Затем включаем обычное автосохранение.
    timer.Simple(1, function()
        State.loading = false
        queueSave()
    end)

    local loadedParts = {}
    for class, amount in pairs(loadedByClass) do
        loadedParts[#loadedParts + 1] = class .. "=" .. amount
    end
    table.sort(loadedParts)

    print("[GRM Saver] Загружено entity: " .. count .. " из " .. expected .. " (" .. table.concat(loadedParts, ", ") .. ")")

    if #failed > 0 then
        print("[GRM Saver] НЕ ЗАГРУЖЕНО: " .. table.concat(failed, "; "))
    end

    return count
end

-- При AUTO_SAVE_ON_CHANGE=true новый скупщик/оборудование будет сохранён
-- вскоре после спавна. По умолчанию включён ручной режим.
hook.Add("OnEntityCreated", "GRM_Saver_PersistentCreated", function(ent)
    timer.Simple(0, function()
        if isPersistentEntity(ent) then
            queueSave()
        end
    end)
end)

-- Правильное имя глобального хука удаления — EntityRemoved.
hook.Add("EntityRemoved", "GRM_Saver_PersistentRemoved", function(ent)
    if State.loading then return end

    if ent and CLASSES_TO_SAVE[ent:GetClass()] then
        queueSave()
    end
end)

if GRM.Boot and GRM.Boot.Task then
    GRM.Boot.Task("mining.saver", "late", function() GRM_LoadEntities() end, { label = "Сейвер шахты: восстановление entity" })
else
hook.Add("InitPostEntity", "GRM_Saver_AutoLoad", function()
    timer.Simple(5, function()
        GRM_LoadEntities()
    end)
end)
end

hook.Add("PostCleanupMap", "GRM_Saver_Cleanup", function()
    timer.Simple(0.5, function()
        GRM_LoadEntities()
    end)
end)

if AUTO_SAVE_INTERVAL > 0 then
    timer.Create("GRM_Saver_AutoSave", AUTO_SAVE_INTERVAL, 0, function()
        GRM_SaveEntities()
    end)
else
    timer.Remove("GRM_Saver_AutoSave")
end

if SAVE_ON_SHUTDOWN then
    hook.Add("ShutDown", "GRM_Saver_SaveOnShutdown", function()
        GRM_SaveEntities()
    end)
else
    hook.Remove("ShutDown", "GRM_Saver_SaveOnShutdown")
end

hook.Add("PlayerSay", "GRM_Saver_Commands", function(ply, text)
    if not IsValid(ply) or not ply:IsAdmin() then return end

    local command = string.lower(string.Trim(text or ""))

    if command == "!saveentities" or command == "/saveentities" then
        local count = GRM_SaveEntities()
        ply:ChatPrint("[GRM Saver] Сохранено entity: " .. count)
        return ""
    end

    if command == "!loadentities" or command == "/loadentities" then
        local count = GRM_LoadEntities()
        ply:ChatPrint("[GRM Saver] Загружено entity: " .. count)
        return ""
    end
end)

concommand.Add("grm_saveentities", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then return end
    GRM_SaveEntities()
end)

concommand.Add("grm_loadentities", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then return end
    GRM_LoadEntities()
end)

print("[GRM Saver] Loaded. Persistent ore buyer enabled for map: " .. game.GetMap())

-- Вечер-18: единый словарь slash-команд: имена живого PlayerSay-обработчика
-- вносятся во внешний реестр библиотеки (на режиме сверка идёт ДО ParseSay —
-- без регистрации команда стала бы «неизвестной»).
if GRM and GRM.Chat and GRM.Chat.RegisterExternalCommands then
    GRM.Chat.RegisterExternalCommands({ "/loadentities", "/saveentities" })
end
