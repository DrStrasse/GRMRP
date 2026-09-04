--[[
    GRM Ore Spawner – автоматический респавн узлов руды в заданных точках
    (версия БЕЗ проверки валидности – точки ставятся по прицелу)
]]

if SERVER then

    -- ============================================================
    -- КОНФИГУРАЦИЯ
    -- ============================================================
    local SAVE_DIR        = "grm_saves"
    local SPAWN_FILE      = SAVE_DIR .. "/grm_orespawns_" .. game.GetMap() .. ".json"
    local SPAWN_BACKUP    = SAVE_DIR .. "/grm_orespawns_" .. game.GetMap() .. "_backup.json"

    local SPAWN_INTERVAL  = 100  -- 1 минут
    local MIN_ORE_COUNT   = 8    -- минимальное количество узлов на карте
    local OCCUPY_RADIUS   = 48   -- минимальная дистанция между узлами

    local ORE_TYPES = {"copper", "gold", "aluminum", "platinum"}

    -- Глобальная таблица точек (сохраняется между перезагрузками скрипта)
    SpawnPoints = SpawnPoints or {}

    -- ============================================================
    -- ЗАГРУЗКА / СОХРАНЕНИЕ точек (с защитой от сброса)
    -- ============================================================
    local function PointFromTable(t)
        if not istable(t) or not istable(t.pos) then return nil end
        local p = t.pos
        if not (isnumber(p.x) and isnumber(p.y) and isnumber(p.z)) then return nil end
        local a = t.ang or {}
        return {
            pos = Vector(p.x, p.y, p.z),
            ang = Angle(tonumber(a.p) or 0, tonumber(a.y) or 0, tonumber(a.r) or 0),
        }
    end

    local function BackupFile()
        if not file.Exists(SPAWN_FILE, "DATA") then return end
        local raw = file.Read(SPAWN_FILE, "DATA")
        if raw and raw ~= "" then
            file.Write(SPAWN_BACKUP, raw)
        end
    end

    local function LoadSpawnPoints()
        if not file.Exists(SPAWN_FILE, "DATA") then
            print("[GRM Ore Spawner] Файл не найден, создаём новый.")
            SpawnPoints = {}
            return
        end
        local raw = file.Read(SPAWN_FILE, "DATA")
        if not raw or raw == "" then
            print("[GRM Ore Spawner] Файл пустой.")
            SpawnPoints = {}
            return
        end

        local ok, data = pcall(util.JSONToTable, raw)
        if ok and istable(data) then
            local newPoints = {}
            for i, pt in ipairs(data) do
                local point = PointFromTable(pt)
                if point then
                    table.insert(newPoints, point)
                else
                    print("[GRM Ore Spawner] Пропущена повреждённая точка #" .. i)
                end
            end
            if #newPoints > 0 then
                SpawnPoints = newPoints
                print("[GRM Ore Spawner] Загружено точек: " .. #SpawnPoints)
                return
            else
                print("[GRM Ore Spawner] Файл повреждён (нет валидных точек).")
            end
        else
            print("[GRM Ore Spawner] Ошибка парсинга JSON: " .. tostring(data))
        end

        -- Если загрузка не удалась, пробуем восстановить из бэкапа
        if file.Exists(SPAWN_BACKUP, "DATA") then
            print("[GRM Ore Spawner] Пробуем восстановить из резервной копии.")
            local rawBackup = file.Read(SPAWN_BACKUP, "DATA")
            if rawBackup and rawBackup ~= "" then
                local okBack, dataBack = pcall(util.JSONToTable, rawBackup)
                if okBack and istable(dataBack) then
                    local restored = {}
                    for i, pt in ipairs(dataBack) do
                        local point = PointFromTable(pt)
                        if point then
                            table.insert(restored, point)
                        end
                    end
                    if #restored > 0 then
                        SpawnPoints = restored
                        print("[GRM Ore Spawner] Восстановлено из бэкапа: " .. #SpawnPoints)
                        return
                    else
                        print("[GRM Ore Spawner] Бэкап тоже повреждён.")
                    end
                else
                    print("[GRM Ore Spawner] Ошибка парсинга бэкапа.")
                end
            end
        end

        print("[GRM Ore Spawner] Не удалось загрузить точки. Создаём пустой массив.")
        SpawnPoints = {}
    end

    local function SaveSpawnPoints()
        if not file.Exists(SAVE_DIR, "DATA") then
            file.CreateDir(SAVE_DIR)
        end
        BackupFile()

        local out = {}
        for _, p in ipairs(SpawnPoints) do
            table.insert(out, {
                pos = { x = p.pos.x, y = p.pos.y, z = p.pos.z },
                ang = { p = p.ang.p, y = p.ang.y, r = p.ang.r },
            })
        end
        file.Write(SPAWN_FILE, util.TableToJSON(out, true))
        print("[GRM Ore Spawner] Сохранено точек: " .. #SpawnPoints)
    end

    -- ============================================================
    -- УПРАВЛЕНИЕ ТОЧКАМИ (добавление по прицелу, БЕЗ валидности)
    -- ============================================================
    local function AddSpawnPoint(pos, ang)
        table.insert(SpawnPoints, {
            pos = Vector(pos.x, pos.y, pos.z),
            ang = Angle(ang.p, ang.y, ang.r),
        })
        SaveSpawnPoints()
    end

    local function RemoveSpawnPoint(index)
        if index >= 1 and index <= #SpawnPoints then
            table.remove(SpawnPoints, index)
            SaveSpawnPoints()
            return true
        end
        return false
    end

    -- ============================================================
    -- СПАВН РУДЫ (без проверки валидности)
    -- ============================================================
    local function IsOccupied(pos)
        for _, ent in ipairs(ents.FindInSphere(pos, OCCUPY_RADIUS)) do
            if ent:GetClass() == "grm_ore_node" then return true end
        end
        return false
    end

    local function SpawnOreNode(pos, ang)
        local node = ents.Create("grm_ore_node")
        if not IsValid(node) then return false end
        node:SetPos(pos)
        node:SetAngles(ang or Angle(0, 0, 0))
        node:Spawn()
        if node.SetOreType then
            node:SetOreType(ORE_TYPES[math.random(#ORE_TYPES)])
        end
        return true
    end

    local function RefillOreNodes()
        if #SpawnPoints == 0 and file.Exists(SPAWN_FILE, "DATA") then
            LoadSpawnPoints()
        end

        local currentNodes = 0
        for _, ent in ipairs(ents.FindByClass("grm_ore_node")) do
            if IsValid(ent) then
                currentNodes = currentNodes + 1
            end
        end

        if currentNodes >= MIN_ORE_COUNT then
            return
        end
        if #SpawnPoints == 0 then
            local hint = file.Exists(SPAWN_FILE, "DATA")
                and " (файл есть, но загрузить не удалось - проверьте структуру JSON)"
                or " (добавьте точки через !addorespawn)"
            print("[GRM Ore Spawner] Нет точек спавна" .. hint .. ", не могу создать руду.")
            return
        end

        -- Используем ВСЕ точки (без фильтрации по валидности)
        local toSpawn = MIN_ORE_COUNT - currentNodes
        local spawned = 0
        local attempts = 0
        local maxAttempts = toSpawn * 4

        while spawned < toSpawn and attempts < maxAttempts and #SpawnPoints > 0 do
            attempts = attempts + 1
            local point = SpawnPoints[math.random(#SpawnPoints)]
            if not IsOccupied(point.pos) then
                if SpawnOreNode(point.pos, point.ang) then
                    spawned = spawned + 1
                end
            end
        end

        if spawned > 0 then
            print("[GRM Ore Spawner] Восстановлено " .. spawned .. " узлов руды.")
        end
    end

    -- ============================================================
    -- ЗАГРУЗКА ПРИ СТАРТЕ
    -- ============================================================
    LoadSpawnPoints()

if GRM.Boot and GRM.Boot.Task then
    GRM.Boot.Task("ore.nodes", "late", function() RefillOreNodes() end, { label = "Шахта: пополнение жил" })
else
    hook.Add("InitPostEntity", "GRM_OreSpawner_Load", function()
        timer.Simple(3, RefillOreNodes)
    end)
end

    hook.Add("PostCleanupMap", "GRM_OreSpawner_Cleanup", function()
        timer.Simple(0.5, RefillOreNodes)
    end)

    timer.Create("GRM_OreSpawner_Timer", SPAWN_INTERVAL, 0, RefillOreNodes)

    -- ============================================================
    -- ЧАТ-КОМАНДЫ (админские)
    -- ============================================================
    hook.Add("PlayerSay", "GRM_OreSpawner_Commands", function(ply, text)
        if not IsValid(ply) or not ply:IsAdmin() then return end

        local args = string.Explode(" ", text)
        local cmd = args[1] and args[1]:lower() or ""

        if cmd == "!addorespawn" then
            local tr = ply:GetEyeTrace()
            local pos, ang

            if tr.Hit then
                pos = tr.HitPos + tr.HitNormal * 4
                ang = Angle(0, ply:GetAngles().y + 180, 0)
            else
                pos = ply:GetPos()
                ang = ply:GetAngles()
            end

            -- Проверка валидности УБРАНА
            AddSpawnPoint(pos, ang)
            ply:PrintMessage(HUD_PRINTTALK, "[Ore Spawner] Точка спавна добавлена по прицелу.")
            return ""
        end

        if cmd == "!listorespawns" then
            if #SpawnPoints == 0 then
                ply:PrintMessage(HUD_PRINTTALK, "[Ore Spawner] Нет точек.")
            else
                ply:PrintMessage(HUD_PRINTTALK, "[Ore Spawner] Точки спавна (" .. #SpawnPoints .. "):")
                for i, pt in ipairs(SpawnPoints) do
                    ply:PrintMessage(HUD_PRINTTALK, string.format("  %d. %.1f %.1f %.1f", i, pt.pos.x, pt.pos.y, pt.pos.z))
                end
            end
            return ""
        end

        if cmd == "!removeorespawn" then
            local idx = tonumber(args[2])
            if not idx then
                ply:PrintMessage(HUD_PRINTTALK, "[Ore Spawner] Укажите индекс: !removeorespawn <номер>")
                return ""
            end
            if RemoveSpawnPoint(idx) then
                ply:PrintMessage(HUD_PRINTTALK, "[Ore Spawner] Точка #" .. idx .. " удалена.")
            else
                ply:PrintMessage(HUD_PRINTTALK, "[Ore Spawner] Неверный индекс.")
            end
            return ""
        end

        if cmd == "!refillore" then
            RefillOreNodes()
            ply:PrintMessage(HUD_PRINTTALK, "[Ore Spawner] Принудительное восполнение выполнено.")
            return ""
        end

        if cmd == "!saveorespawns" then
            SaveSpawnPoints()
            ply:PrintMessage(HUD_PRINTTALK, "[Ore Spawner] Точки принудительно сохранены.")
            return ""
        end
    end)

    print("[GRM Ore Spawner] Загружен (без проверки валидности). Интервал: " .. SPAWN_INTERVAL .. "с, минимум " .. MIN_ORE_COUNT .. " узлов.")
end

-- Вечер-18: команда разбирается внутри парсера модуля (не литералом в
-- хуке) — регистрируем её множество в едином внешнем словаре библиотеки,
-- иначе на режиме она стала бы «неизвестной» до цепочки.
if GRM and GRM.Chat and GRM.Chat.RegisterExternalCommands then
    GRM.Chat.RegisterExternalCommands({ "/grm_orespawns_" })
end
