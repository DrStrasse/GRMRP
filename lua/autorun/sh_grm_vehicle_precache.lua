--[[--------------------------------------------------------------------
    GRM Vehicle Precache v1.0.0 — предзагрузка моделей транспорта
    (заказ владельца 22.08: «модели у дилера показываются только после
    первого спавна машины, и то не все»).

    ПОЧЕМУ ТАК БЫЛО. DModelPanel и SpawnIcon рисуют модель только если она
    уже загружена движком. Модели транспорта появляются в памяти, когда
    машину впервые спавнят на карте, — до этого окно дилера показывает
    пустое место. На сервере то же самое: не прекэшированная модель при
    первом спавне даёт паузу.

    ЧТО ДЕЛАЕМ. При старте карты собираем ВЕСЬ список транспорта (source,
    simfphys, LVS, плюс то, что реально выставлено у дилеров и закуплено в
    автопарки) и грузим модели ЗАРАНЕЕ.

    ГЛАВНОЕ — ПОРЦИОННО. Список бывает на сотни машин, и грузить его одним
    куском значит подарить игрокам фриз на входе. Поэтому:
      • старт вешается на GRM.Boot (тир idle — после всего важного);
      • сам обход идёт через GRM.Perf.Spread — по нескольку моделей за
        кадр, с бюджетом общего планировщика;
      • на клиенте модель «прогревается» временной ClientsideModel и тут же
        удаляется — так её видит и SpawnIcon, и DModelPanel;
      • размер порции настраивается конваром, всю работу можно выключить.

    Настройки:
      grm_vehicle_precache        1  — включить предзагрузку
      grm_vehicle_precache_chunk  4  — сколько моделей за один заход
    Команды:
      grm_vehicles_precache        — запустить принудительно (админ/клиент)
      grm_vehicles_precache_status — что уже загружено
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.VehiclePrecache = GRM.VehiclePrecache or {}
local VP = GRM.VehiclePrecache
VP.Version = "1.0.0"

VP.Done = VP.Done or {}     -- model -> true
VP.Queued = VP.Queued or 0

-----------------------------------------------------------------------
-- ЧИСТАЯ ЧАСТЬ (гоняется стендом)
-----------------------------------------------------------------------

--- Похоже ли это на путь к модели.
function VP.ValidModel(path)
    path = tostring(path or "")
    if path == "" then return false end
    if not string.find(path, ".mdl", 1, true) then return false end
    return true
end

--- Собрать уникальный список моделей из нескольких источников.
--  sources — список таблиц { model = "..." } либо строк.
function VP.Collect(sources)
    local out, seen = {}, {}
    for _, src in ipairs(istable(sources) and sources or {}) do
        for _, item in pairs(istable(src) and src or {}) do
            local model = isstring(item) and item or (istable(item) and (item.model or item.Model)) or nil
            model = model and string.lower(tostring(model)) or nil
            if model and VP.ValidModel(model) and not seen[model] then
                seen[model] = true
                out[#out + 1] = model
            end
        end
    end
    table.sort(out)
    return out
end

--- Сколько ещё не загружено (для отчёта команды).
function VP.Pending(models, done)
    local n = 0
    for _, m in ipairs(istable(models) and models or {}) do
        if not (istable(done) and done[m]) then n = n + 1 end
    end
    return n
end

-----------------------------------------------------------------------
-- ИГРОВАЯ ЧАСТЬ
-----------------------------------------------------------------------

local cvOn = CreateConVar("grm_vehicle_precache", "1",
    bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED),
    "Заранее подгружать модели транспорта, чтобы они сразу были видны в окнах")
local cvChunk = CreateConVar("grm_vehicle_precache_chunk", "4",
    bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED),
    "Сколько моделей транспорта грузить за один заход (порционность)")

--- Все модели транспорта, которые вообще могут понадобиться.
function VP.ModelList()
    local sources = {}

    local VD = GRM.VehicleDealer
    if VD and VD.AllVehicleClasses then
        local ok, all = pcall(VD.AllVehicleClasses)
        if ok and istable(all) then sources[#sources + 1] = all end
    else
        sources[#sources + 1] = list.Get("Vehicles") or {}
        sources[#sources + 1] = list.Get("simfphys_vehicles") or {}
        sources[#sources + 1] = list.Get("LVS_Vehicles") or {}
    end

    -- то, что реально выставлено у дилеров и закуплено организациями:
    -- эти модели нужны в первую очередь
    if SERVER and VD and VD.VehicleInfo then
        local extra = {}
        for _, dealer in ipairs(ents.FindByClass("sent_vehicle_dealer")) do
            for _, entry in ipairs(IsValid(dealer) and dealer.VD_Vehicles or {}) do
                local info = VD.VehicleInfo(entry.class)
                if info and info.model then extra[#extra + 1] = info.model end
            end
        end
        local FL = GRM.Fleet
        if FL and istable(FL.Market) then
            for _, entry in pairs(FL.Market) do
                if istable(entry) and entry.model then extra[#extra + 1] = entry.model end
            end
        end
        local CV = GRM.CivilVehicles
        if CV and istable(CV.Data) and istable(CV.Data.entries) then
            for _, entry in pairs(CV.Data.entries) do
                if istable(entry) and entry.model then extra[#extra + 1] = entry.model end
            end
        end
        sources[#sources + 1] = extra
    end

    return VP.Collect(sources)
end

--- Загрузить одну модель. На клиенте «прогреваем» её временной моделью:
--  иначе SpawnIcon и DModelPanel покажут пустоту до первого спавна.
function VP.Load(model)
    if not VP.ValidModel(model) then return false end
    if VP.Done[model] then return true end
    VP.Done[model] = true

    util.PrecacheModel(model)

    if CLIENT then
        local ent = ClientsideModel(model, RENDERGROUP_OPAQUE)
        if IsValid(ent) then
            ent:SetNoDraw(true)
            ent:SetPos(Vector(0, 0, -16000))
            -- модель уже в памяти: держать её незачем
            ent:Remove()
        end
    end
    return true
end

--- Запустить предзагрузку порциями. Возвращает, сколько поставлено в очередь.
function VP.Run(force)
    if not force and not cvOn:GetBool() then return 0 end
    local models = VP.ModelList()
    local todo = {}
    for _, m in ipairs(models) do
        if not VP.Done[m] then todo[#todo + 1] = m end
    end
    VP.Queued = #todo
    if #todo == 0 then return 0 end

    local chunk = math.Clamp(cvChunk:GetInt(), 1, 32)
    if GRM.Perf and GRM.Perf.Spread then
        -- порционно и с приоритетом ниже игровых задач
        GRM.Perf.Spread("vehicles.precache." .. (SERVER and "sv" or "cl"), todo, function(model)
            VP.Load(model)
        end, {
            chunk = chunk, priority = -5,
            onDone = function()
                VP.Queued = 0
                print(("[GRM Vehicles] предзагружено моделей транспорта: %d"):format(#todo))
            end,
        })
    else
        -- без слоя производительности всё равно не одним куском:
        -- редкий таймер (полсекунды) и та же порция
        local i = 1
        timer.Create("GRM_VehiclePrecache", 0.5, 0, function()
            for _ = 1, chunk do
                local m = todo[i]
                if not m then timer.Remove("GRM_VehiclePrecache") VP.Queued = 0 return end
                VP.Load(m)
                i = i + 1
            end
            VP.Queued = math.max(0, #todo - i + 1)
        end)
    end
    return #todo
end

--[[ Старт: тир idle — модели грузятся ПОСЛЕ всего важного (карты, дверей,
     экономики, персонажей), чтобы вход на сервер не тормозил. ]]
if GRM.Boot and GRM.Boot.OnMapStart then
    GRM.Boot.OnMapStart("vehicles.precache", "idle", function() VP.Run() end)
else
    hook.Add("InitPostEntity", "GRM_VehiclePrecache", function()
        timer.Simple(15, function() VP.Run() end)
    end)
end

-- Дилеров могли поставить уже после старта: обновляем список без спешки.
hook.Add("GRM_VehicleDealerSaved", "GRM_VehiclePrecache", function()
    if GRM.Perf and GRM.Perf.Coalesce then
        GRM.Perf.Coalesce("vehicles.precache.resave", 5, function() VP.Run() end)
    else
        timer.Simple(5, function() VP.Run() end)
    end
end)

concommand.Add("grm_vehicles_precache", function(ply)
    if SERVER and IsValid(ply) and not ply:IsSuperAdmin() then return end
    local n = VP.Run(true)
    local text = ("[GRM Vehicles] поставлено в очередь моделей: %d"):format(n)
    if IsValid(ply) then ply:ChatPrint(text) else print(text) end
end)

concommand.Add("grm_vehicles_precache_status", function(ply)
    local models = VP.ModelList()
    local left = VP.Pending(models, VP.Done)
    local text = ("[GRM Vehicles] всего моделей: %d, загружено: %d, в очереди: %d"):format(
        #models, #models - left, VP.Queued)
    if IsValid(ply) then ply:ChatPrint(text) else print(text) end
end)

print("[GRM Vehicles] Precache v" .. VP.Version .. " loaded (" .. (SERVER and "Server" or "Client") .. ")")
