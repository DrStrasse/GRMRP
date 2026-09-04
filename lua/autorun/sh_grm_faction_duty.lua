--[[--------------------------------------------------------------------
    GRM Faction Duty v1.2.0 (Код 102)
    Смена статуса «на службе / вне службы» через служебного NPC.
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.FactionDuty = GRM.FactionDuty or {}
local FD = GRM.FactionDuty
FD.Version = "1.4.0"

local NET_OPEN = "GRM_FactionDuty_Open"
local NET_SET = "GRM_FactionDuty_Set"
local NET_ADMIN = "GRM_FactionDuty_Admin"
local NET_ADMIN_SAVE = "GRM_FactionDuty_AdminSave"
local NET_TOOL_REQ = "GRM_FactionDuty_ToolFactionsReq"
local NET_TOOL_DATA = "GRM_FactionDuty_ToolFactionsData"

-- Ключ персонажа — канон ядра (§5.2.6). Локальная копия убрана: копия канона.
local characterKey = GRM.CharKey

local function factionOf(ply)
    if not IsValid(ply) or not istable(Factions) then return nil end
    if _G.FactionsAPI and _G.FactionsAPI.GetFactionOf then
        local name = _G.FactionsAPI.GetFactionOf(ply)
        if name then return name end
    end
    for name, f in pairs(Factions) do
        if istable(f) and istable(f.Members) then
            local member
            if GRM.Identity and GRM.Identity.FactionMember then member = GRM.Identity.FactionMember(f, ply)
            else member = f.Members[characterKey(ply)] or f.Members[ply:SteamID64()] or f.Members[ply:SteamID()] end
            if member then return name, member, f end
        end
    end
    return nil
end
FD.FactionOf = factionOf

if SERVER then
    util.AddNetworkString(NET_OPEN)
    util.AddNetworkString(NET_SET)
    util.AddNetworkString(NET_ADMIN)
    util.AddNetworkString(NET_ADMIN_SAVE)
    util.AddNetworkString(NET_TOOL_REQ)
    util.AddNetworkString(NET_TOOL_DATA)

    local DATA_FILE = "grm_faction_duty.json"
    local STATION_DIR = "grm_duty"

    --[[ ХРАНИЛИЩЕ СТАНЦИЙ (заказ владельца 18.08).
         Раньше настройки диспетчера жили только в NW-строках и надеялись на
         перм-запись: если её не было, «Сохранить» тихо ничего не сохраняло
         (GRM.Perm.Update отвечает «объект не закреплён»), а после рестарта
         фракция терялась и модель сбрасывалась на стандартного гражданина.
         Теперь у станций свой файл по карте — как у дилеров транспорта. ]]
    local function stationFile()
        if not file.IsDir(STATION_DIR, "DATA") then file.CreateDir(STATION_DIR) end
        return STATION_DIR .. "/stations_" .. string.lower(game.GetMap() or "unknown") .. ".json"
    end

    local function readStations()
        local raw = file.Read(stationFile(), "DATA")
        if not raw or raw == "" then return {} end
        local ok, t = pcall(util.JSONToTable, raw, false, true)
        if not ok or not istable(t) then return {} end
        return istable(t.stations) and t.stations or {}
    end

    local function writeStations(rows)
        local ok, raw = pcall(util.TableToJSON, { version = 1, map = game.GetMap(), stations = rows }, true)
        if not ok or not isstring(raw) then return false end
        file.Write(stationFile(), raw)
        return true
    end

    -- Радиусы подобраны по реальной ситуации: после Spawn энтити падает на
    -- пол (DropToFloor) и уезжает по Z на десятки юнитов, поэтому «та же
    -- точка» — это не 64, а 192 юнита. Из-за узкого радиуса восстановление
    -- не узнавало уже стоящего диспетчера и плодило рядом КЛОНА с той же
    -- фракцией — отсюда «настройка расползлась на всех».
    local STATION_MATCH = 192
    local STATION_DEDUPE = 96

    local function dist2(a, b)
        if not (istable(a) and isvector(b)) then return math.huge end
        local dx, dy, dz = (tonumber(a.x) or 0) - b.x, (tonumber(a.y) or 0) - b.y, (tonumber(a.z) or 0) - b.z
        return dx * dx + dy * dy + dz * dz
    end

    local function sameSpot(a, b, radius)
        radius = tonumber(radius) or STATION_MATCH
        return dist2(a, b) <= (radius * radius)
    end

    -- Ближайший диспетчер к точке (или nil).
    local function nearestNPC(pos, radius, list)
        local best, bestD
        for _, ent in ipairs(list or ents.FindByClass("grm_duty_npc")) do
            if IsValid(ent) then
                local d = dist2(pos, ent:GetPos())
                if d <= (radius * radius) and (not bestD or d < bestD) then best, bestD = ent, d end
            end
        end
        return best, bestD
    end

    --[[ ДЕДУП ТОЛЬКО НАСТОЯЩИХ КОПИЙ.
         Соседних диспетчеров НЕ трогаем: два поста разных организаций могут
         стоять вплотную, это нормальная расстановка, и удалять один из них
         нельзя. Клоном считается только пара с ОДИНАКОВЫМ идентификатором
         станции — то есть копия, которую породило прежнее восстановление.
         Если идентификаторы разные, не делаем ничего. ]]
    function FD.DedupeStations()
        local list = ents.FindByClass("grm_duty_npc")
        local seen, removed = {}, 0

        for _, ent in ipairs(list) do
            if IsValid(ent) then
                local id = tostring(ent.GRMDutyID or ent:GetNWString("GRM_DutyID", ""))
                if id ~= "" then
                    local keep = seen[id]
                    if not IsValid(keep) then
                        seen[id] = ent
                    else
                        -- Из копии и оригинала оставляем настроенного и
                        -- закреплённого пермом.
                        local function score(e)
                            local n = 0
                            if tostring(e.GRMDutyFaction or e:GetNWString("GRM_DutyFaction", "")) ~= "" then n = n + 10 end
                            if GRM.Perm and GRM.Perm.IsPerm and GRM.Perm.IsPerm(e) then n = n + 5 end
                            return n - (e:EntIndex() / 100000)
                        end
                        local drop = (score(keep) >= score(ent)) and ent or keep
                        local stay = (drop == ent) and keep or ent
                        if stay.ApplyStationConfig and drop.StationConfig then
                            local cfg = drop:StationConfig()
                            if tostring(cfg.faction or "") ~= ""
                                and tostring(stay.GRMDutyFaction or "") == "" then
                                stay:ApplyStationConfig(cfg)
                            end
                        end
                        seen[id] = stay
                        drop:Remove()
                        removed = removed + 1
                    end
                end
            end
        end

        if removed > 0 then
            print(("[GRM Duty] убрано копий с одинаковым идентификатором: %d"):format(removed))
        end
        return removed
    end

    -- Стабильный идентификатор станции. Раньше запись искалась ТОЛЬКО по
    -- координатам, и два диспетчера, стоящие рядом, делили одну запись —
    -- настройка второго затирала первого. Теперь у каждого свой id.
    local function stationID(ent)
        local id = tostring(ent.GRMDutyID or ent:GetNWString("GRM_DutyID", ""))
        if id ~= "" then return id end
        local pos = ent:GetPos()
        id = util.CRC(table.concat({ game.GetMap(), math.floor(pos.x), math.floor(pos.y),
            math.floor(pos.z), ent:EntIndex(), os.time() }, ":"))
        ent.GRMDutyID = id
        ent:SetNWString("GRM_DutyID", id)
        return id
    end

    -- Сохранить конфигурацию конкретного диспетчера.
    function FD.SaveStation(ent)
        if not IsValid(ent) or ent:GetClass() ~= "grm_duty_npc" then return false end
        local id = stationID(ent)
        local cfg = ent.StationConfig and ent:StationConfig() or {}
        cfg.id = id
        local pos, ang = ent:GetPos(), ent:GetAngles()
        local rows = readStations()

        local updated = false
        for _, row in ipairs(rows) do
            -- Сопоставление строго по id; координаты — только для старых
            -- записей, у которых id ещё нет.
            local match = (tostring(row.id or "") ~= "" and row.id == id)
                or (tostring(row.id or "") == "" and sameSpot(row.pos, pos, STATION_DEDUPE))
            if match then
                row.id = id
                row.faction = cfg.faction
                row.title = cfg.title
                row.model = cfg.model
                row.pos = { x = pos.x, y = pos.y, z = pos.z }
                row.ang = { p = ang.p, y = ang.y, r = ang.r }
                updated = true
                break
            end
        end
        if not updated then
            rows[#rows + 1] = {
                id = id,
                pos = { x = pos.x, y = pos.y, z = pos.z },
                ang = { p = ang.p, y = ang.y, r = ang.r },
                faction = cfg.faction, title = cfg.title, model = cfg.model,
            }
        end
        while #rows > 128 do table.remove(rows, 1) end
        return writeStations(rows), updated and "обновлено" or "создано"
    end

    -- Убрать станцию из файла (диспетчера снесли тулом).
    function FD.RemoveStation(ent)
        if not IsValid(ent) then return false end
        local pos = ent:GetPos()
        local id = tostring(ent.GRMDutyID or ent:GetNWString("GRM_DutyID", ""))
        local rows, removed = readStations(), false
        for i = #rows, 1, -1 do
            local match = (id ~= "" and rows[i].id == id) or (id == "" and sameSpot(rows[i].pos, pos, STATION_DEDUPE))
            if match then
                table.remove(rows, i)
                removed = true
            end
        end
        if removed then writeStations(rows) end
        return removed
    end

    -- Найти конфиг для уже стоящего диспетчера и применить.
    function FD.RestoreStation(ent)
        if not IsValid(ent) or ent:GetClass() ~= "grm_duty_npc" then return false end

        -- Уже настроенного диспетчера чужой станцией не перетираем.
        if tostring(ent.GRMDutyFaction or "") ~= "" then return false end

        local pos = ent:GetPos()
        local best, bestD
        for _, row in ipairs(readStations()) do
            local d = dist2(row.pos, pos)
            if d <= (STATION_MATCH * STATION_MATCH) and (not bestD or d < bestD) then
                best, bestD = row, d
            end
        end
        if not best then return false end
        if ent.ApplyStationConfig then ent:ApplyStationConfig(best) end
        return true
    end

    -- Поднять все станции карты: применить конфиг к найденным NPC и
    -- восстановить пропавшие (например, если перм-запись потерялась).
    function FD.LoadStations()
        local rows = readStations()
        if #rows == 0 then return 0, 0 end

        -- Сначала убираем клонов, оставшихся от прежних восстановлений.
        FD.DedupeStations()

        local existing = ents.FindByClass("grm_duty_npc")
        local restored, created = 0, 0
        local taken = {}

        for _, row in ipairs(rows) do
            -- Каждая станция получает СВОЕГО ближайшего диспетчера и только
            -- его: раньше при промахе радиуса создавался клон рядом с чужим
            -- NPC, и одна настройка «размножалась» по карте.
            local target, bestD

            -- 1) точное совпадение по идентификатору станции
            if tostring(row.id or "") ~= "" then
                for _, ent in ipairs(existing) do
                    if IsValid(ent) and not taken[ent]
                        and tostring(ent.GRMDutyID or ent:GetNWString("GRM_DutyID", "")) == row.id then
                        target = ent
                        break
                    end
                end
            end

            -- 2) иначе — ближайший свободный в радиусе
            for _, ent in ipairs(existing) do
                if not IsValid(target) and IsValid(ent) and not taken[ent] then
                    local d = dist2(row.pos, ent:GetPos())
                    if d <= (STATION_MATCH * STATION_MATCH) and (not bestD or d < bestD) then
                        target, bestD = ent, d
                    end
                end
            end

            if IsValid(target) then
                taken[target] = true
                restored = restored + 1
            else
                --[[ Диспетчера создаём, только если его действительно нет.
                     Соседний пост ЧУЖОЙ организации не помеха: у него свой
                     идентификатор и своя запись, мы просто встанем рядом —
                     так и было задумано. А вот ненастроенный NPC ровно в
                     нашей точке — это наш же диспетчер, потерявший
                     идентификатор: забираем его, а не плодим копию. ]]
                local orphan = nil
                for _, ent in ipairs(existing) do
                    if IsValid(ent) and not taken[ent]
                        and dist2(row.pos, ent:GetPos()) <= (STATION_DEDUPE * STATION_DEDUPE)
                        and tostring(ent.GRMDutyID or ent:GetNWString("GRM_DutyID", "")) == "" then
                        orphan = ent
                        break
                    end
                end

                if IsValid(orphan) then
                    target = orphan
                    taken[target] = true
                    restored = restored + 1
                else
                    target = ents.Create("grm_duty_npc")
                    if IsValid(target) then
                        -- Модель ставим ДО Spawn, иначе Initialize возьмёт
                        -- дефолт и игрок увидит стандартного гражданина.
                        target.GRMDutyModel = tostring(row.model or "")
                        target.GRMDutyFaction = tostring(row.faction or "")
                        target.GRMDutyTitle = tostring(row.title or "")
                        target:SetPos(Vector(row.pos.x, row.pos.y, row.pos.z))
                        if istable(row.ang) then target:SetAngles(Angle(row.ang.p or 0, row.ang.y or 0, row.ang.r or 0)) end
                        target:Spawn()
                        target:Activate()
                        existing[#existing + 1] = target
                        taken[target] = true
                        created = created + 1
                    end
                end
            end

            if IsValid(target) and target.ApplyStationConfig then
                target:ApplyStationConfig(row)
                -- Точку в файле обновляем на фактическую: после DropToFloor
                -- диспетчер стоит ниже, и в следующий раз он найдётся сразу.
                local pos = target:GetPos()
                if dist2(row.pos, pos) > 4 then
                    row.pos = { x = pos.x, y = pos.y, z = pos.z }
                    FD._stationsDirty = true
                end
            end
        end

        if FD._stationsDirty then
            FD._stationsDirty = nil
            writeStations(rows)
        end

        print(("[GRM Duty] станции: применено %d, создано %d"):format(restored, created))
        return restored, created
    end
    local function sendToolFactions(ply)
        if not(IsValid(ply)and ply:IsSuperAdmin())then return end;local names={};for name in pairs(Factions or{})do names[#names+1]=tostring(name)end;table.sort(names,function(a,b)return string.lower(a)<string.lower(b)end)
        net.Start(NET_TOOL_DATA);net.WriteTable(names);net.Send(ply)
    end
    net.Receive(NET_TOOL_REQ,function(bits,ply)if GRM.Net and not GRM.Net.Guard(ply,"duty.tool.factions",{rate=.5,burst=2,maxBits=64},{bits=bits})then return end;sendToolFactions(ply)end)

    local function jsonT(raw)
        local ok, t = pcall(util.JSONToTable, raw or "", false, true)
        return ok and istable(t) and t or nil
    end
    local function load()
        local raw = file.Read(DATA_FILE, "DATA") or ""
        local t = jsonT(raw)
        if raw ~= "" and not t then file.Write(DATA_FILE .. ".corrupt." .. os.time() .. ".txt", raw) end
        FD.State = {}
        for _, r in ipairs(istable(t) and (t.records or t) or {}) do
            if istable(r) and isstring(r.key) and r.key ~= "" then FD.State[r.key] = r.onDuty ~= false end
        end
    end
    local function save(why)
        local rows = {}
        for key, onDuty in pairs(FD.State or {}) do rows[#rows + 1] = { key = key, onDuty = onDuty == true } end
        table.sort(rows, function(a, b) return a.key < b.key end)
        local ok, raw = pcall(util.TableToJSON, { version = 1, records = rows }, true)
        if not ok or not raw then return false end
        file.Write(DATA_FILE, raw)
        if not jsonT(file.Read(DATA_FILE, "DATA") or "") then print("[GRM Duty] SAVE FAIL") return false end
        print("[GRM Duty] SAVE ok [" .. tostring(why or "-") .. "]: " .. #rows .. " записей")
        return true
    end
    load()

    function FD.HasFaction(ply) return factionOf(ply) ~= nil end
    function FD.IsOnDuty(ply)
        if not FD.HasFaction(ply) then return false end
        local state = FD.State[characterKey(ply)]
        if state == nil then return true end -- член фракции впервые входит на службу
        return state == true
    end
    function FD.CanTakeCivilJob(ply)
        if not FD.HasFaction(ply) then return true end
        return not FD.IsOnDuty(ply)
    end

    local function applyAppearance(ply)
        if not IsValid(ply) then return end
        local list = isfunction(GetModelsForPlayer) and GetModelsForPlayer(ply) or nil
        if istable(list) and list[1] and isfunction(ApplyModelSettings) then ApplyModelSettings(ply, list[1]) end
        if isfunction(ApplyWeaponsToPlayer) then ApplyWeaponsToPlayer(ply) end
        if isfunction(sendModelsToPlayer) then sendModelsToPlayer(ply) end
    end

    function FD.Apply(ply)
        if not IsValid(ply) then return end
        local hasFaction = FD.HasFaction(ply)
        local onDuty = hasFaction and FD.IsOnDuty(ply)
        ply:SetNWBool("GRM_FactionOnDuty", onDuty)
        ply:SetNWBool("GRM_FactionOffDuty", hasFaction and not onDuty)
        if not onDuty then
            ply:SetNWBool("IsMasked", false)
            ply:SetNWString("MaskModel", "")
            ply:SetNWString("MaskName", "")
            ply.FactionsExt_MaskEntry = nil
        end
        timer.Simple(0, function() if IsValid(ply) then applyAppearance(ply) end end)
        hook.Run("GRM_FactionDutyChanged", ply, onDuty, factionOf(ply))
        if isfunction(broadcastFactionData) then broadcastFactionData() end
    end

    function FD.Set(ply, onDuty, actor)
        local fac = factionOf(ply)
        if not fac then return false, "Вы не состоите во фракции" end
        onDuty = onDuty == true
        if onDuty and GRM.Jobs and GRM.Jobs.Active and GRM.Jobs.Active[characterKey(ply)] then
            return false, "Сначала завершите или отмените гражданскую работу (/jobcancel)"
        end
        FD.State[characterKey(ply)] = onDuty
        save((onDuty and "выход на службу: " or "уход со службы: ") .. ply:Nick())
        FD.Apply(ply)
        return true, onDuty and "Вы вышли на службу. Форма и снаряжение восстановлены." or "Вы вне службы. Теперь доступны гражданские подработки."
    end

    function FD.Open(ply, ent)
        if not IsValid(ply) or not IsValid(ent) or ent:GetClass() ~= "grm_duty_npc" then return end
        if ply:GetPos():DistToSqr(ent:GetPos()) > 220 * 220 then return end
        local fac = factionOf(ply)
        if not fac then
            if GRM.Notify then GRM.Notify(ply, "Этот пункт предназначен для сотрудников фракций.", 255, 170, 90) end
            return
        end
        local stationFac = ent:GetNWString("GRM_DutyFaction", "")
        if stationFac == "" or stationFac == "*" or not (Factions and Factions[stationFac]) then
            if GRM.Notify then GRM.Notify(ply, "Этот служебный диспетчер не настроен. Суперадмин должен привязать его к фракции.", 255, 170, 90) end
            return
        end
        if stationFac ~= fac then
            if GRM.Notify then GRM.Notify(ply, "Этот пункт обслуживает только фракцию «" .. stationFac .. "».", 255, 130, 110) end
            return
        end
        net.Start(NET_OPEN)
            net.WriteEntity(ent)
            net.WriteString(fac)
            net.WriteBool(FD.IsOnDuty(ply))
            net.WriteString(ent:GetNWString("GRM_DutyTitle", "Пункт выхода на службу"))
        net.Send(ply)
    end

    function FD.OpenAdmin(ply, ent)
        if not IsValid(ply) or not ply:IsSuperAdmin() or not IsValid(ent) or ent:GetClass() ~= "grm_duty_npc" then return end
        if ply:GetPos():DistToSqr(ent:GetPos()) > 300 * 300 then return end
        local factions = {}
        for name in pairs(Factions or {}) do factions[#factions + 1] = name end
        table.sort(factions, function(a,b) return string.lower(a) < string.lower(b) end)
        -- Берём конфиг из полей энтити: NW-строки могут ещё не прийти или
        -- быть пустыми после рестарта, из-за чего меню показывало «не выбрано»
        -- и следующее сохранение затирало фракцию.
        local cfg = ent.StationConfig and ent:StationConfig() or {
            faction = ent:GetNWString("GRM_DutyFaction", ""),
            title = ent:GetNWString("GRM_DutyTitle", "ПУНКТ ВЫХОДА НА СЛУЖБУ"),
            model = ent:GetNWString("GRM_DutyModel", ent:GetModel()),
        }
        net.Start(NET_ADMIN)
            net.WriteEntity(ent)
            net.WriteString(tostring(cfg.faction or ""))
            net.WriteString(tostring(cfg.title or "ПУНКТ ВЫХОДА НА СЛУЖБУ"))
            net.WriteString(tostring(cfg.model or ent:GetModel() or ""))
            net.WriteTable(factions)
        net.Send(ply)
    end

    net.Receive(NET_ADMIN_SAVE, function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() or (ply._grmDutyAdminAt or 0) > CurTime() then return end
        ply._grmDutyAdminAt = CurTime() + 0.5
        local ent = net.ReadEntity()
        local fac = string.sub(string.Trim(net.ReadString() or ""), 1, 80)
        local title = string.sub(string.Trim(net.ReadString() or ""), 1, 80)
        local mdl = string.sub(string.Trim(net.ReadString() or ""), 1, 180)
        if not IsValid(ent) or ent:GetClass() ~= "grm_duty_npc" or ply:GetPos():DistToSqr(ent:GetPos()) > 300 * 300 then return end
        if not (Factions and Factions[fac]) then
            if GRM.Notify then GRM.Notify(ply, "Выберите существующую фракцию.", 255, 130, 110) end
            return
        end
        if title == "" then title = "ПУНКТ ВЫХОДА НА СЛУЖБУ" end
        -- Пишем конфиг в энтити (поля + NW), в файл станций и в перм-запись.
        if ent.ApplyStationConfig then
            ent:ApplyStationConfig({ faction = fac, title = title, model = mdl })
        else
            ent:SetNWString("GRM_DutyFaction", fac)
            ent:SetNWString("GRM_DutyTitle", title)
            if util.IsValidModel(mdl) then ent:SetNWString("GRM_DutyModel", mdl) ent:SetModel(mdl) end
        end

        local savedFile = FD.SaveStation(ent)

        -- Upsert создаёт перм-запись, если её не было: раньше вызывался
        -- GRM.Perm.Update, который на незакреплённом объекте молча отвечал
        -- «объект не закреплён» — настройки не сохранялись вообще.
        local permState = "нет"
        if GRM.PermData and GRM.PermData.Upsert then
            permState = tostring(GRM.PermData.Upsert(ent) or "нет")
        elseif GRM.Perm and GRM.Perm.Update then
            permState = tostring(select(2, GRM.Perm.Update(ply, ent)) or "нет")
        end

        if GRM.Audit and GRM.Audit.Write then
            GRM.Audit.Write("duty", "station.save", ply,
                { faction = fac, title = title, model = mdl }, { file = savedFile == true, perm = permState })
        end

        if GRM.Notify then
            GRM.Notify(ply, ("Диспетчер привязан к «%s». Файл станций: %s, перм: %s.")
                :format(fac, savedFile and "сохранён" or "ОШИБКА", permState), 80, 230, 150)
        end
    end)

    net.Receive(NET_SET, function(_, ply)
        if not IsValid(ply) or (ply._grmDutyActAt or 0) > CurTime() then return end
        ply._grmDutyActAt = CurTime() + 1
        local ent = net.ReadEntity()
        local want = net.ReadBool()
        if not IsValid(ent) or ent:GetClass() ~= "grm_duty_npc" or ply:GetPos():DistToSqr(ent:GetPos()) > 220 * 220 then return end
        local stationFac, fac = ent:GetNWString("GRM_DutyFaction", ""), factionOf(ply)
        if not fac or stationFac == "" or stationFac == "*" or stationFac ~= fac then return end
        local ok, msg = FD.Set(ply, want, ply)
        if GRM.Notify then GRM.Notify(ply, msg, ok and 80 or 255, ok and 230 or 130, ok and 150 or 110) else ply:ChatPrint("[Служба] " .. msg) end
    end)

    local function delayedApply(ply)
        timer.Simple(2, function() if IsValid(ply) then FD.Apply(ply) end end)
    end
    hook.Add("PlayerInitialSpawn", "GRM_Duty_Join", delayedApply)
    hook.Add("PlayerSpawn", "GRM_Duty_Spawn", function(ply) timer.Simple(0.5, function() if IsValid(ply) then FD.Apply(ply) end end) end)
    hook.Add("GRM_CharacterChanged", "GRM_Duty_Character", function(ply) delayedApply(ply) end)
    hook.Add("ShutDown", "GRM_Duty_Save", function() save("shutdown") end)

    -- Регистрация перма отложена: ядро sh_grm_perm_entities.lua грузится позже.
    local function registerPerm()
        if GRM.Perm and GRM.Perm.RegisterClass then GRM.Perm.RegisterClass("grm_duty_npc", true) end
        if not (GRM.PermData and GRM.PermData.Extract and GRM.PermData.Apply) then return end
        GRM.PermData.Extract["grm_duty_npc"] = function(ent)
            local cfg = ent.StationConfig and ent:StationConfig() or {
                faction = ent:GetNWString("GRM_DutyFaction", ""),
                title = ent:GetNWString("GRM_DutyTitle", "ПУНКТ ВЫХОДА НА СЛУЖБУ"),
                model = ent:GetNWString("GRM_DutyModel", ent:GetModel()),
            }
            return { duty = { id = cfg.id, faction = cfg.faction, title = cfg.title, model = cfg.model } }
        end
        GRM.PermData.Apply["grm_duty_npc"] = function(ent, data)
            local d = istable(data) and data.duty or nil
            if not istable(d) then return end
            if ent.ApplyStationConfig then
                ent:ApplyStationConfig({
                    id = tostring(d.id or ""),
                    faction = tostring(d.faction or ""),
                    title = tostring(d.title or "ПУНКТ ВЫХОДА НА СЛУЖБУ"),
                    model = tostring(d.model or ""),
                })
                return
            end
            ent:SetNWString("GRM_DutyFaction", tostring(d.faction or ""))
            ent:SetNWString("GRM_DutyTitle", tostring(d.title or "ПУНКТ ВЫХОДА НА СЛУЖБУ"))
            if util.IsValidModel(tostring(d.model or "")) then
                ent:SetNWString("GRM_DutyModel", d.model)
                ent:SetModel(d.model)
                if ent.RefreshIdle then ent:RefreshIdle(true) end
            end
        end
    end
    timer.Simple(1, registerPerm)
    timer.Simple(4, registerPerm)

    -- Станции поднимаем после перм-энтити: если перм отработал — просто
    -- применяем конфиг, если нет — создаём диспетчера заново.
    local function bootStations()
        timer.Simple(3, function() FD.LoadStations() end)
        timer.Simple(8, function() FD.LoadStations() end)
    end
    if GRM.Boot and GRM.Boot.OnMapStart then
        GRM.Boot.OnMapStart("GRM_Duty_Stations", "normal", bootStations)
    else
        hook.Add("InitPostEntity", "GRM_Duty_Stations", bootStations)
    end
    hook.Add("PostCleanupMap", "GRM_Duty_StationsCleanup", function()
        timer.Simple(1.5, function() FD.LoadStations() end)
    end)

    if concommand and concommand.Add then concommand.Add("grm_duty_dedupe", function(ply)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        local removed = FD.DedupeStations()
        local msg = ("[GRM Duty] убрано дублирующих диспетчеров: %d"):format(removed or 0)
        if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg) else print(msg) end
    end) end

    if concommand and concommand.Add then concommand.Add("grm_duty_stations", function(ply)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        local restored, created = FD.LoadStations()
        local msg = ("[GRM Duty] станции перезагружены: применено %d, создано %d"):format(restored or 0, created or 0)
        if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg) else print(msg) end
    end) end

    local function statusChat(ply, text)
        local low = string.lower(string.Trim(text or ""))
        if low ~= "/duty" and low ~= "/служба" then return false end
        local fac = factionOf(ply)
        if not fac then ply:ChatPrint("[Служба] Вы не состоите во фракции.")
        else ply:ChatPrint("[Служба] " .. fac .. ": " .. (FD.IsOnDuty(ply) and "НА СЛУЖБЕ" or "ВНЕ СЛУЖБЫ") .. ". Смена статуса — у служебного NPC.") end
        return true
    end
    hook.Add("PlayerSay", "GRM_Duty_Transform", function(ply, text, teamSays)
        local data = { tostring(text or ""), SkipPlayerSay = false }
            if istable(data) and isstring(data[1]) and statusChat(ply, data[1]) then data[1] = "" data.SkipPlayerSay = true end
        if data.SkipPlayerSay == true then return "" end
    end)
    hook.Add("PlayerSay", "GRM_Duty_Chat", function(ply, text) if statusChat(ply, text) then return "" end end)
else
    net.Receive(NET_TOOL_DATA,function()local names=net.ReadTable()or{};FD.ToolFactions=names;if GRM.QMenu then GRM.QMenu.FactionNames=names;if IsValid(GRM.QMenu._frame)and isfunction(GRM.QMenu._rebuild)then timer.Simple(0,GRM.QMenu._rebuild)end end;hook.Run("GRM_DutyToolFactionsUpdated",names)end)
    function FD.RequestToolFactions()if(FD._toolFactionReqAt or 0)>CurTime()then return end;FD._toolFactionReqAt=CurTime()+2;net.Start(NET_TOOL_REQ);net.SendToServer()end
    surface.CreateFont("GRMDuty_Title", { font = "Roboto", size = 22, weight = 800, extended = true })
    surface.CreateFont("GRMDuty_Text", { font = "Roboto", size = 14, weight = 500, extended = true })
    net.Receive(NET_ADMIN, function()
        local ent, current, currentTitle, currentModel, factions = net.ReadEntity(), net.ReadString(), net.ReadString(), net.ReadString(), net.ReadTable() or {}
        if not IsValid(ent) then return end
        if IsValid(FD._adminFrame) then FD._adminFrame:Remove() end
        local f=vgui.Create("DFrame") FD._adminFrame=f; f:SetSize(620,390); f:Center(); f:MakePopup(); f:SetTitle("Настройка служебного диспетчера")
        local selectedFaction=current
        local function displayName(name)
            local public=GRM.Factions and GRM.Factions.DisplayName and GRM.Factions.DisplayName(name) or name
            return public~=name and (public.."  ["..name.."]") or name
        end
        local fac=vgui.Create("DComboBox",f); fac:SetPos(20,60); fac:SetSize(580,32)
        fac:SetValue(current ~= "" and displayName(current) or "Выберите фракцию")
        for _,name in ipairs(factions) do fac:AddChoice(displayName(name),name,name==current) end
        -- Если сохранённой фракции больше нет в реестре — показываем это явно,
        -- а не подменяем молча первой попавшейся.
        if current ~= "" and not table.HasValue(factions, current) then
            fac:AddChoice("⚠ "..current.." (организации больше нет)",current,true)
        end
        fac.OnSelect=function(_,_,_,data) selectedFaction=tostring(data or "") end
        local title=vgui.Create("DTextEntry",f); title:SetPos(20,120); title:SetSize(580,30); title:SetValue(currentTitle); title:SetPlaceholderText("Надпись пункта")
        local mdl=vgui.Create("DTextEntry",f); mdl:SetPos(20,180); mdl:SetSize(580,30); mdl:SetValue(currentModel); mdl:SetPlaceholderText("Модель NPC")
        local hint=vgui.Create("DLabel",f); hint:SetPos(20,225); hint:SetSize(580,55); hint:SetWrap(true); hint:SetText("Каждый NPC обслуживает только одну выбранную фракцию. Название фракции автоматически показывается на 3D2D-табличке над ним.")
        local saveBtn=vgui.Create("DButton",f); saveBtn:SetPos(20,305); saveBtn:SetSize(580,42); saveBtn:SetText("СОХРАНИТЬ И ОБНОВИТЬ ПЕРМ")
        saveBtn.DoClick=function() net.Start(NET_ADMIN_SAVE); net.WriteEntity(ent); net.WriteString(tostring(selectedFaction or "")); net.WriteString(title:GetValue()); net.WriteString(mdl:GetValue()); net.SendToServer(); f:Close() end
    end)

    net.Receive(NET_OPEN, function()
        local ent, fac, onDuty, title = net.ReadEntity(), net.ReadString(), net.ReadBool(), net.ReadString()
        if IsValid(FD._frame) then FD._frame:Remove() end
        local f = vgui.Create("DFrame") FD._frame = f
        f:SetSize(580, 330) f:Center() f:MakePopup() f:SetTitle("") f:ShowCloseButton(false)
        f.Paint = function(_, w, h) draw.RoundedBox(9, 0, 0, w, h, Color(8,14,23,248)); draw.RoundedBoxEx(9,0,0,w,54,Color(10,22,37),true,true,false,false); draw.SimpleText(title,"GRMDuty_Title",16,27,Color(225,238,247),TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER) end
        local close=vgui.Create("DButton",f) close:SetPos(536,11) close:SetSize(30,30) close:SetText("✕") close.DoClick=function() f:Close() end
        local info=vgui.Create("DLabel",f) info:SetPos(18,78) info:SetSize(544,88) info:SetFont("GRMDuty_Text") info:SetTextColor(Color(225,238,247)) info:SetWrap(true)
        info:SetText("Фракция: "..fac.."\nТекущий статус: "..(onDuty and "НА СЛУЖБЕ" or "ВНЕ СЛУЖБЫ").."\nНа службе используются форма и вооружение фракции. Вне службы — гражданская одежда и доступ к городским работам.")
        local b=vgui.Create("DButton",f) b:SetPos(18,196) b:SetSize(544,46) b:SetText(onDuty and "ЗАВЕРШИТЬ СЛУЖБУ" or "ВЫЙТИ НА СЛУЖБУ") b:SetTextColor(color_white)
        b.Paint=function(s,w,h) draw.RoundedBox(6,0,0,w,h,onDuty and Color(244,150,70) or Color(64,222,147)) end
        b.DoClick=function() if not IsValid(ent) then return end net.Start(NET_SET) net.WriteEntity(ent) net.WriteBool(not onDuty) net.SendToServer() f:Close() end
        local hint=vgui.Create("DLabel",f) hint:SetPos(18,258) hint:SetSize(544,42) hint:SetFont("GRMDuty_Text") hint:SetTextColor(Color(132,160,178)) hint:SetWrap(true); hint:SetText(onDuty and "После завершения службы вы сможете работать курьером, таксистом или мусоровозом." or "Перед выходом на службу завершите активную гражданскую работу.")
    end)
end

print("[GRM Duty] v" .. FD.Version .. " loaded")

-- Вечер-18: команда разбирается внутри парсера модуля (не литералом в
-- хуке) — регистрируем её множество в едином внешнем словаре библиотеки,
-- иначе на режиме она стала бы «неизвестной» до цепочки.
if GRM and GRM.Chat and GRM.Chat.RegisterExternalCommands then
    GRM.Chat.RegisterExternalCommands({ "/duty", "/stations_", "/служба" })
end
