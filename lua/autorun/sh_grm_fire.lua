--[[--------------------------------------------------------------------
    GRM Fire v1.4.1 (Код 58)
    Серверная обвязка аддона grm_fire + vFire.
    Не содержит моделей/рукава — они в аддоне.
    Права, персист очагов, рандом по точкам, плита, оповещение, учёт тушения v1.4.1.
    Не трогает: FFD, Q-меню, двери, принтер, пресс.
----------------------------------------------------------------------]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Fire = GRM.Fire or {}
local F = GRM.Fire
F.Version = "1.4.1"

F.Config = F.Config or {
    StoveEnabled = true,
    RandomEnabled = true,
    RandomMinSec = 480,
    RandomMaxSec = 900,
    SpotCooldownSec = 2700,
    PersistTTL = 1800,
    MaxIncidents = 8,
    StoveNear = 200,
    StoveChanceNear = 0.008,
    StoveChanceAway = 0.024,
    AnnounceRadius = 420,
}

local function jsonT(txt)
    local ok, t = pcall(util.JSONToTable, txt, false, true)
    return (ok and istable(t)) and t or nil
end

local function tell(ply, msg, r, g, b)
    if IsValid(ply) and GRM.Notify then GRM.Notify(ply, msg, r or 220, g or 200, b or 90)
    elseif IsValid(ply) then ply:ChatPrint("[Пожар] " .. tostring(msg)) end
end

function F.AddonReady()
    return GRM_FireAddon == true
end

function F.VFireReady()
    return vFireInstalled == true and isfunction(CreateVFire)
end

function F.CanFight(ply)
    if not IsValid(ply) then return false end
    if ply:IsSuperAdmin() then return true end
    return true
end

function F.CanFightPro(ply)
    if not IsValid(ply) then return false end
    if ply:IsSuperAdmin() then return true end
    local AM = GRM.Fire and GRM.Fire.AccessManager
    if AM and AM.CanControl then return AM.CanControl(ply) == true end
    return false
end

function F.CanDispatch(ply)
    if not IsValid(ply) then return false end
    if ply:IsSuperAdmin() then return true end
    local AM = GRM.Fire and GRM.Fire.AccessManager
    if AM and AM.CanView then return AM.CanView(ply) == true end
    return false
end

function F.CanManage(ply)
    if not IsValid(ply) then return false end
    return ply:IsSuperAdmin() == true
end

-- Пожарная энтити / помеченная машина. Не банкомат.
function F.IsFireEnt(ent)
    if not IsValid(ent) then return false end
    local cls = ent.GetClass and tostring(ent:GetClass() or "") or ""
    if string.sub(cls, 1, 9) == "grm_fire_" then return true end
    if ent.GetNWBool and ent:GetNWBool("GRM_FireTruck", false) then return true end
    if ent.GetNWBool and ent:GetNWBool("GRM_TruckGear", false) then return true end
    local p = ent.GetParent and ent:GetParent() or nil
    if IsValid(p) and p.GetNWBool and p:GetNWBool("GRM_FireTruck", false) then return true end
    return false
end

-- G у насоса/машины/гидранта — только пожарка. Смотришь на банкомат — инкассация.
function F.IsFireGContext(ply)
    if not IsValid(ply) then return false end
    local tr = ply.GetEyeTrace and ply:GetEyeTrace() or nil
    local hit = (tr and IsValid(tr.Entity)) and tr.Entity or nil
    if IsValid(hit) then
        local cls = hit.GetClass and tostring(hit:GetClass() or "") or ""
        if cls == "grm_bank_terminal" or cls == "grm_bank_vault" then return false end
        if F.IsFireEnt(hit) then return true end
    end
    local seat = ply.GetVehicle and ply:GetVehicle() or nil
    if IsValid(seat) then
        if F.IsFireEnt(seat) then return true end
        local p = seat.GetParent and seat:GetParent() or nil
        if F.IsFireEnt(p) then return true end
    end
    local pos = ply.GetPos and ply:GetPos() or nil
    local duty = ply.GetNWEntity and ply:GetNWEntity("GRM_FireMyTruck") or nil
    if IsValid(duty) and pos and duty.GetPos then
        if pos:DistToSqr(duty:GetPos()) <= 420 * 420 then return true end
    end
    if pos and ents and ents.FindInSphere then
        for _, e in ipairs(ents.FindInSphere(pos, 320)) do
            if not IsValid(e) then
            elseif e.GetClass and e:GetClass() == "grm_fire_pump" then
                return true
            elseif e.GetNWBool and e:GetNWBool("GRM_FireTruck", false) then
                return true
            end
        end
    end
    return false
end

-- Живые очаги vFire одним списком из event-реестра GRM.Perf: на горящем
-- здании их бывают сотни, а ents.FindByClass строит новую таблицу на каждый
-- вызов (а зовут его и таймеры, и проверки очагов, и статистика).
local function liveVfire()
    if GRM and GRM.Perf and GRM.Perf.Entities then return GRM.Perf.Entities("vfire") end
    return ents.FindByClass("vfire")
end
F.LiveVFire = liveVfire

function F.IsBurning(pos)
    if not isvector(pos) then
        if IsValid(pos) and pos.GetPos then pos = pos:GetPos() else return false end
    end
    for _, ent in ipairs(liveVfire()) do
        if IsValid(ent) and ent:GetPos():DistToSqr(pos) < 96 * 96 then return true end
    end
    return false
end

if SERVER then
    local DIR = "grm_fire"
    local dirty, lastSave = false, 0

    local function ensureDir()
        if not file.IsDir(DIR, "DATA") then file.CreateDir(DIR) end
    end

    local function activePath()
        return DIR .. "/active_" .. tostring(game.GetMap() or "nomap") .. ".json"
    end

    local CFG_FILE = DIR .. "/config.json"

    local function clampCfg()
        local c = F.Config
        c.RandomEnabled = c.RandomEnabled ~= false
        c.StoveEnabled = c.StoveEnabled ~= false
        c.RandomMinSec = math.Clamp(math.floor(tonumber(c.RandomMinSec) or 480), 30, 7200)
        c.RandomMaxSec = math.Clamp(math.floor(tonumber(c.RandomMaxSec) or 900), c.RandomMinSec, 10800)
        c.SpotCooldownSec = math.Clamp(math.floor(tonumber(c.SpotCooldownSec) or 2700), 0, 86400)
        c.MaxIncidents = math.Clamp(math.floor(tonumber(c.MaxIncidents) or 8), 1, 24)
        c.PersistTTL = math.Clamp(math.floor(tonumber(c.PersistTTL) or 1800), 60, 86400)
    end

    function F.LoadConfig()
        ensureDir()
        if not file.Exists(CFG_FILE, "DATA") then clampCfg() return F.Config end
        local raw = file.Read(CFG_FILE, "DATA") or ""
        local t = jsonT(raw)
        if not istable(t) then
            local q = CFG_FILE .. ".corrupt." .. os.time()
            file.Write(q, raw)
            print("[GRM Fire] config битый — " .. q)
            clampCfg()
            return F.Config
        end
        if t.random ~= nil then F.Config.RandomEnabled = t.random == true end
        if t.stove ~= nil then F.Config.StoveEnabled = t.stove == true end
        if t.min_sec then F.Config.RandomMinSec = tonumber(t.min_sec) end
        if t.max_sec then F.Config.RandomMaxSec = tonumber(t.max_sec) end
        if t.cooldown then F.Config.SpotCooldownSec = tonumber(t.cooldown) end
        if t.max_incidents then F.Config.MaxIncidents = tonumber(t.max_incidents) end
        if t.ttl then F.Config.PersistTTL = tonumber(t.ttl) end
        clampCfg()
        print("[GRM Fire] LOAD config: random=" .. tostring(F.Config.RandomEnabled)
            .. " " .. F.Config.RandomMinSec .. "-" .. F.Config.RandomMaxSec .. "с")
        return F.Config
    end

    function F.SaveConfig(why)
        ensureDir()
        clampCfg()
        local payload = {
            version = 1,
            random = F.Config.RandomEnabled == true,
            stove = F.Config.StoveEnabled == true,
            min_sec = F.Config.RandomMinSec,
            max_sec = F.Config.RandomMaxSec,
            cooldown = F.Config.SpotCooldownSec,
            max_incidents = F.Config.MaxIncidents,
            ttl = F.Config.PersistTTL,
        }
        local ok, txt = pcall(util.TableToJSON, payload, true)
        if not ok or not isstring(txt) then return false end
        file.Write(CFG_FILE, txt)
        local chk = file.Read(CFG_FILE, "DATA")
        if chk ~= txt then
            print("[GRM Fire] SAVE read-back fail [config " .. tostring(why or "") .. "]")
            return false
        end
        print("[GRM Fire] SAVE config ok [" .. tostring(why or "") .. "]")
        return true
    end

    function F.Snapshot()
        local out = {}
        for _, ent in ipairs(liveVfire()) do
            if not IsValid(ent) then
            else
                local p, n = ent:GetPos(), ent:GetForward()
                out[#out + 1] = {
                    x = p.x, y = p.y, z = p.z,
                    nx = n.x, ny = n.y, nz = n.z,
                    feed = math.floor(tonumber(ent.feed) or 80),
                    life = math.floor(tonumber(ent.life) or 20),
                    started = tonumber(ent._grmStarted) or os.time(),
                    source = tostring(ent._grmSource or "unknown"),
                }
            end
        end
        return out
    end

    function F.SaveActive(reason)
        ensureDir()
        local payload = { version = 1, incidents = F.Snapshot() }
        local ok, txt = pcall(util.TableToJSON, payload, true)
        if not ok or not isstring(txt) then
            print("[GRM Fire] SAVE fail serialize [" .. tostring(reason or "?") .. "]")
            return false
        end
        file.Write(activePath(), txt)
        local chk = file.Read(activePath(), "DATA")
        if chk ~= txt then
            print("[GRM Fire] SAVE read-back fail [" .. tostring(reason or "?") .. "]")
            return false
        end
        dirty = false
        lastSave = CurTime()
        print(("[GRM Fire] SAVE ok %d очагов [%s]"):format(#payload.incidents, tostring(reason or "")))
        return true
    end

    function F.MarkDirty()
        dirty = true
    end

    function F.LoadActive()
        ensureDir()
        local path = activePath()
        if not file.Exists(path, "DATA") then return 0 end
        local raw = file.Read(path, "DATA") or ""
        local t = jsonT(raw)
        if not istable(t) then
            local q = path .. ".corrupt." .. os.time()
            file.Write(q, raw)
            print("[GRM Fire] active битый — карантин " .. q)
            return 0
        end
        local n, now, ttl = 0, os.time(), tonumber(F.Config.PersistTTL) or 1800
        for _, rec in ipairs(istable(t.incidents) and t.incidents or {}) do
            if istable(rec) then
                local started = tonumber(rec.started) or now
                if now - started <= ttl and F.VFireReady() then
                    local pos = Vector(tonumber(rec.x) or 0, tonumber(rec.y) or 0, tonumber(rec.z) or 0)
                    local nrm = Vector(tonumber(rec.nx) or 0, tonumber(rec.ny) or 0, tonumber(rec.nz) or 1)
                    if nrm:LengthSqr() < 0.01 then nrm = Vector(0, 0, 1) end
                    nrm:Normalize()
                    local fire = CreateVFire(game.GetWorld(), pos, nrm, math.max(20, tonumber(rec.feed) or 80))
                    if IsValid(fire) then
                        fire._grmStarted = started
                        fire._grmSource = tostring(rec.source or "persist")
                        if fire.ChangeLife and rec.life then fire:ChangeLife(tonumber(rec.life) or fire.life) end
                        n = n + 1
                    end
                end
            end
        end
        print(("[GRM Fire] LOAD %d очагов с диска"):format(n))
        return n
    end

    local announced = {}
    function F.Announce(pos, source)
        if not isvector(pos) then return end
        local key = math.floor(pos.x / 512) .. ":" .. math.floor(pos.y / 512)
        if announced[key] and CurTime() - announced[key] < 75 then return end
        announced[key] = CurTime()
        local text = "ПОЖАР"
        if source == "stove" then text = "ПОЖАР: плита"
        elseif source == "random" then text = "ПОЖАР: очаг"
        elseif source == "admin" then text = "ПОЖАР (админ)" end
        hook.Run("GRM_FireStarted", pos, source)
        if GRM.Alarm and GRM.Alarm.Log then
            pcall(GRM.Alarm.Log, "main", "fire", text)
        end
        if F.NotifyFactions then F.NotifyFactions("⚠ " .. text, pos) end
        if GRM.Minimap and GRM.Minimap.AddTempPoint then
            GRM.Minimap.AddTempPoint("ПОЖАР", pos, 120)
            if GRM.Minimap.SendTo then
                for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                    if F.CanDispatch(p) or p:IsSuperAdmin() then GRM.Minimap.SendTo(p) end
                end
            end
        end
        print("[GRM Fire] " .. text .. " @ " .. tostring(pos))
    end

    function F.Ignite(pos, source, starter)
        if not F.VFireReady() then return nil, "vFire не загружен" end
        if #liveVfire() >= (tonumber(F.Config.MaxIncidents) or 8) * 12 then
            return nil, "лимит очагов"
        end
        source = tostring(source or "system")
        local nrm = Vector(0, 0, 1)
        local parent = game.GetWorld()
        if isentity(pos) and IsValid(pos) then
            parent = pos
            local p = pos:WorldSpaceCenter()
            local tr = util.TraceLine({ start = p + Vector(0, 0, 8), endpos = p - Vector(0, 0, 64), filter = pos })
            pos = (tr.Hit and tr.HitPos) or p
            nrm = tr.Hit and tr.HitNormal or nrm
        elseif isvector(pos) then
            local tr = util.TraceLine({ start = pos + Vector(0, 0, 16), endpos = pos - Vector(0, 0, 80) })
            if tr.Hit then
                pos = tr.HitPos
                nrm = tr.HitNormal
                if IsValid(tr.Entity) and not tr.Entity:IsWorld() then parent = tr.Entity end
            end
        else
            return nil, "нет позиции"
        end
        local fire = CreateVFire(parent, pos, nrm, 160)
        if IsValid(fire) then
            fire._grmStarted = os.time()
            fire._grmSource = source
            fire._grmStarter = tostring(starter or "")
            F.Announce(pos, source)
            F.MarkDirty()
        end
        return fire
    end

    function F.ExtinguishAround(pos, radius)
        radius = tonumber(radius) or 128
        local n = 0
        for _, ent in ipairs(ents.FindInSphere(pos, radius)) do
            if IsValid(ent) and ent:GetClass() == "vfire" then
                ent:Remove()
                n = n + 1
            end
        end
        if n > 0 then F.MarkDirty() end
        return n
    end

    -- ── права аддона ────────────────────────────────────────
    hook.Add("GRM_FireAddon_CanHose", "GRM_Fire", function(ply)
        if F.CanFightPro(ply) then return end
        return false
    end)
    --[[ ГИДРАНТ (жалоба владельца 28.08):
         «На E открыл гидрант, и закрыть его нельзя, если ты не пожарный.»

         Хук запрещал ЛЮБОЕ действие с гидрантом не-пожарному, включая
         ЗАКРЫТИЕ. Получалась ловушка: человек открывает кран (аддон
         пускал первое нажатие сам), а обратно повернуть уже не может.
         Гидрант остаётся открытым навсегда — хлещет вода, насос считает
         его занятым, а убрать безобразие может только пожарный или админ.

         Правило теперь такое: ОТКРЫВАТЬ — по правам, ЗАКРЫВАТЬ — всем.
         Закрытие возвращает мир в исходное состояние и навредить им
         нельзя; запрещать его бессмысленно. А вот открыть чужой гидрант
         (затопить улицу, слить давление на пожаре) — по-прежнему только
         пожарным.

         Второй аргумент хука — сама энтити гидранта. Если аддон её не
         передал, определить намерение невозможно: тогда ведём себя
         по-старому и спрашиваем права. ]]
    hook.Add("GRM_FireAddon_HydrantUse", "GRM_Fire", function(ply, hydrant)
        if F.CanFightPro(ply) then return end
        -- Гидрант уже открыт — это попытка закрыть. Разрешаем любому.
        if IsValid(hydrant) and hydrant.GetOpen and hydrant:GetOpen() == true then
            return
        end
        return false
    end)
    hook.Add("GRM_FireAddon_PumpUse", "GRM_Fire", function(ply)
        if F.CanFightPro(ply) then return end
        return false
    end)
    hook.Add("GRM_FireAddon_HoseNodeUse", "GRM_Fire", function(ply)
        if F.CanFightPro(ply) then return end
        return false
    end)

    local function isVehicleEnt(ent)
        if not IsValid(ent) then return false end
        if ent.IsVehicle and ent:IsVehicle() then return true end
        local cls = ent:GetClass() or ""
        return string.StartWith(cls, "simfphys_") or string.StartWith(cls, "lvs_")
            or string.StartWith(cls, "glide_") or string.StartWith(cls, "prop_vehicle_")
            or string.find(cls, "vehicle", 1, true) ~= nil
    end

    local function isTruckMounted(ent)
        if not IsValid(ent) then return false end
        if ent._grmTruckGear then return true end
        if ent.GetNWBool and ent:GetNWBool("GRM_TruckGear", false) then return true end
        if ent.GetHostVehicle and IsValid(ent:GetHostVehicle()) then return true end
        local p = ent.GetParent and ent:GetParent() or NULL
        return isVehicleEnt(p)
    end

    -- Бортовой насос/лестница живут с машиной. Перм их ставит в воздухе
    -- после рестарта (ТС уже нет). Рукава — сессия, не карта.
    hook.Add("GRM_PermCanAdd", "GRM_Fire_NoTruckPerm", function(_, ent)
        if not IsValid(ent) then return end
        local cls = ent:GetClass() or ""
        if cls == "grm_fire_hose" or cls == "grm_fire_hose_node" then return false end
        if (cls == "grm_fire_pump" or cls == "grm_fire_ladder") and isTruckMounted(ent) then
            return false
        end
    end)

    hook.Add("GRM_FireAddon_Placed", "GRM_Fire_AutoPerm", function(ent, ply)
        if not IsValid(ent) then return end
        local cls = ent:GetClass() or ""
        if cls == "grm_fire_hose" or cls == "grm_fire_hose_node" then return end
        if (cls == "grm_fire_pump" or cls == "grm_fire_ladder") and isTruckMounted(ent) then
            return
        end
        if GRM.Perm and GRM.Perm.RegisterClass then
            GRM.Perm.RegisterClass(ent:GetClass(), true)
        end
        if GRM.Perm and GRM.Perm.Add and IsValid(ply) then
            local ok, msg = GRM.Perm.Add(ply, ent, { ownerKind = "server", label = "fire" })
            if ok then tell(ply, "Закреплено на карте (перм).", 100, 220, 130)
            elseif msg then tell(ply, "Перм: " .. tostring(msg) .. " — поставьте /permadd.", 255, 190, 90) end
        end
    end)

    local function isFloatingGear(ent)
        if not IsValid(ent) then return false end
        if isTruckMounted(ent) then
            local host = (ent.GetHostVehicle and ent:GetHostVehicle()) or (ent.GetParent and ent:GetParent()) or NULL
            return not IsValid(host)
        end
        local pos = ent:GetPos()
        local tr = util.TraceLine({
            start = pos,
            endpos = pos - Vector(0, 0, 80),
            filter = ent,
            mask = MASK_SOLID_BRUSHONLY,
        })
        return not tr.Hit or pos:Distance(tr.HitPos) > 48
    end

    -- Снести призраков после рестарта и вычистить их из пермов.
    function F.SweepOrphanGear(reason)
        local n = 0
        for _, cls in ipairs({ "grm_fire_hose", "grm_fire_hose_node" }) do
            for _, ent in ipairs(ents.FindByClass(cls)) do
                if IsValid(ent) then ent:Remove() n = n + 1 end
            end
        end
        local dropPos = {}
        for _, cls in ipairs({ "grm_fire_pump", "grm_fire_ladder" }) do
            for _, ent in ipairs(ents.FindByClass(cls)) do
                if IsValid(ent) and isFloatingGear(ent) then
                    dropPos[#dropPos + 1] = { class = cls, pos = ent:GetPos() }
                    if GRM.Perm and GRM.Perm.Remove then
                        pcall(GRM.Perm.Remove, nil, ent, false)
                    end
                    ent:Remove()
                    n = n + 1
                end
            end
        end
        if #dropPos > 0 and file.Exists("grm_perm_entities.json", "DATA") then
            local raw = file.Read("grm_perm_entities.json", "DATA") or ""
            local list = jsonT(raw)
            if istable(list) then
                local map = game.GetMap()
                local keep = {}
                for _, rec in ipairs(list) do
                    local skip = false
                    if istable(rec) and rec.map == map then
                        if rec.class == "grm_fire_hose" or rec.class == "grm_fire_hose_node" then
                            skip = true
                        elseif rec.class == "grm_fire_pump" or rec.class == "grm_fire_ladder" then
                            if istable(rec.data) and rec.data.mounted == true then
                                skip = true
                            else
                                for _, d in ipairs(dropPos) do
                                    if d.class == rec.class and istable(rec.pos) then
                                        local dx = (tonumber(rec.pos.x) or 0) - d.pos.x
                                        local dy = (tonumber(rec.pos.y) or 0) - d.pos.y
                                        local dz = (tonumber(rec.pos.z) or 0) - d.pos.z
                                        if dx * dx + dy * dy + dz * dz <= 36 then skip = true break end
                                    end
                                end
                            end
                        end
                    end
                    if not skip then keep[#keep + 1] = rec end
                end
                if #keep < #list then
                    local ok, txt = pcall(util.TableToJSON, keep, true)
                    if ok and isstring(txt) then
                        file.Write("grm_perm_entities.json", txt)
                        print(("[GRM Fire] перм-призраки: было %d, осталось %d"):format(#list, #keep))
                    end
                end
            end
        end
        if n > 0 then
            print(("[GRM Fire] SweepOrphanGear [%s]: снято %d"):format(tostring(reason or ""), n))
        end
        return n
    end

    hook.Add("GRM_PermRestored", "GRM_Fire_SkipMounted", function(ent, rec)
        if not IsValid(ent) then return end
        local cls = ent:GetClass() or ""
        if cls == "grm_fire_hose" or cls == "grm_fire_hose_node" then
            ent:Remove()
            return
        end
        if (cls == "grm_fire_pump" or cls == "grm_fire_ladder") and istable(rec) and istable(rec.data) and rec.data.mounted then
            ent:Remove()
        end
    end)

    hook.Add("vFireCreated", "GRM_Fire_Track", function(fire)
        if not IsValid(fire) then return end
        fire._grmStarted = fire._grmStarted or os.time()
        F.MarkDirty()
        local pos = fire:GetPos()
        local near = 0
        for _, o in ipairs(liveVfire()) do
            if o ~= fire and IsValid(o) and o:GetPos():DistToSqr(pos) < 400 * 400 then
                near = near + 1
            end
        end
        if near == 0 then F.Announce(pos, fire._grmSource or "fire") end
    end)
    hook.Add("vFireRemoved", "GRM_Fire_Track", function()
        F.MarkDirty()
        if #liveVfire() == 0 and GRM.Minimap and GRM.Minimap.RemoveTempPoint then
            GRM.Minimap.RemoveTempPoint("ПОЖАР")
        end
    end)

    -- ── перм классов + данные ───────────────────────────────
    local function installPerm()
        if not (GRM.Perm and GRM.Perm.RegisterClass) then return end
        for _, cls in ipairs({ "grm_fire_hydrant", "grm_fire_pump", "grm_fire_cabinet", "grm_fire_spot", "grm_fire_ladder" }) do
            GRM.Perm.RegisterClass(cls, true)
        end
        if GRM.PermData then
            GRM.PermData.Extract["grm_fire_hydrant"] = function(ent)
                return { open = ent.GetOpen and ent:GetOpen() == true, ports = ent.GetPortsMax and ent:GetPortsMax() or 2 }
            end
            GRM.PermData.Apply["grm_fire_hydrant"] = function(ent, data)
                if istable(data) and ent.SetOpen then ent:SetOpen(data.open == true) end
                if istable(data) and data.ports and ent.SetPortsMax then ent:SetPortsMax(tonumber(data.ports) or 2) end
            end
            GRM.PermData.Extract["grm_fire_pump"] = function(ent)
                return {
                    tank = ent.GetTank and ent:GetTank() or 0,
                    tankmax = ent.GetTankMax and ent:GetTankMax() or 4000,
                    foam = ent.GetFoam and ent:GetFoam() or 0,
                    foammax = ent.GetFoamMax and ent:GetFoamMax() or 500,
                    powder = ent.GetPowder and ent:GetPowder() or 0,
                    powdermax = ent.GetPowderMax and ent:GetPowderMax() or 250,
                    slots = ent.GetHosesMax and ent:GetHosesMax() or 4,
                    mounted = (ent._grmTruckGear == true)
                        or (ent.GetNWBool and ent:GetNWBool("GRM_TruckGear", false))
                        or false,
                }
            end
            GRM.PermData.Apply["grm_fire_pump"] = function(ent, data)
                if not istable(data) then return end
                if data.tankmax and ent.SetTankMax then ent:SetTankMax(math.min(20000, tonumber(data.tankmax) or 4000)) end
                if data.tank and ent.SetTank then ent:SetTank(math.max(0, tonumber(data.tank) or 0)) end
                if data.foammax and ent.SetFoamMax then ent:SetFoamMax(tonumber(data.foammax) or 500) end
                if data.foam and ent.SetFoam then ent:SetFoam(tonumber(data.foam) or 0) end
                if data.powdermax and ent.SetPowderMax then ent:SetPowderMax(tonumber(data.powdermax) or 250) end
                if data.powder and ent.SetPowder then ent:SetPowder(tonumber(data.powder) or 0) end
                if data.slots and ent.SetHosesMax then ent:SetHosesMax(tonumber(data.slots) or 4) end
            end
            GRM.PermData.Extract["grm_fire_spot"] = function(ent)
                return {
                    weight = ent.GetWeight and ent:GetWeight() or 1,
                    label = ent.GetSpotLabel and ent:GetSpotLabel() or "",
                    cool = ent.GetCoolSec and ent:GetCoolSec() or 0,
                    feed = ent.GetFeed and ent:GetFeed() or 180,
                    on = not (ent.GetSpotOn and ent:GetSpotOn() == false),
                }
            end
            GRM.PermData.Apply["grm_fire_spot"] = function(ent, data)
                if not istable(data) then return end
                if data.weight and ent.SetWeight then ent:SetWeight(math.max(1, tonumber(data.weight) or 1)) end
                if isstring(data.label) and ent.SetSpotLabel then ent:SetSpotLabel(data.label) end
                if data.cool and ent.SetCoolSec then ent:SetCoolSec(math.max(0, tonumber(data.cool) or 0)) end
                if data.feed and ent.SetFeed then ent:SetFeed(math.max(40, tonumber(data.feed) or 180)) end
                if ent.SetSpotOn then ent:SetSpotOn(data.on ~= false) end
            end
        end
    end
    timer.Simple(0, installPerm)
    timer.Simple(2, installPerm)

    -- ── рандом ──────────────────────────────────────────────
    local function pickSpot()
        local spots, weights = {}, {}
        local now = os.time()
        local cd = tonumber(F.Config.SpotCooldownSec) or 2700
        for _, ent in ipairs(ents.FindByClass("grm_fire_spot")) do
            if IsValid(ent) and not (ent.GetSpotOn and ent:GetSpotOn() == false) and not F.IsBurning(ent:GetPos()) then
                local last = ent.GetLastIgnite and tonumber(ent:GetLastIgnite()) or 0
                local own = ent.GetCoolSec and tonumber(ent:GetCoolSec()) or 0
                local need = (own and own > 0) and own or cd
                if last == 0 or now - last >= need then
                    spots[#spots + 1] = ent
                    weights[#weights + 1] = math.max(1, ent.GetWeight and ent:GetWeight() or 1)
                end
            end
        end
        if #spots == 0 then return nil end
        local sum = 0
        for i = 1, #weights do sum = sum + weights[i] end
        local roll = math.Rand(0, sum)
        for i = 1, #spots do
            roll = roll - weights[i]
            if roll <= 0 then return spots[i] end
        end
        return spots[#spots]
    end

    local function scheduleRandom()
        timer.Remove("GRM_Fire_Random")
        if not F.Config.RandomEnabled then return end
        local a = tonumber(F.Config.RandomMinSec) or 480
        local b = tonumber(F.Config.RandomMaxSec) or 900
        if b < a then b = a end
        timer.Create("GRM_Fire_Random", math.Rand(a, b), 1, function()
            if F.Config.RandomEnabled and F.VFireReady() then
                local live = #liveVfire()
                if live < (tonumber(F.Config.MaxIncidents) or 8) * 6 then
                    local spot = pickSpot()
                    if IsValid(spot) then
                        if spot.IgniteSpot then
                            local fire = spot:IgniteSpot(spot.GetFeed and spot:GetFeed() or 180, "system")
                            if IsValid(fire) then
                                fire._grmSource = "random"
                                fire._grmStarted = os.time()
                            end
                        else
                            F.Ignite(spot:GetPos(), "random", "system")
                        end
                    end
                end
            end
            scheduleRandom()
        end)
    end
    F.RescheduleRandom = scheduleRandom
    F.PickSpot = pickSpot

    -- ── плита ───────────────────────────────────────────────
    timer.Create("GRM_Fire_Stove", 2, 0, function()
        if not F.Config.StoveEnabled or not F.VFireReady() then return end
        for _, stove in ipairs((GRM.Perf and GRM.Perf.Entities) and GRM.Perf.Entities("grm_food_stove") or ents.FindByClass("grm_food_stove")) do
            if IsValid(stove) and stove.GetStoveState and stove:GetStoveState() == 1 then
                if F.IsBurning(stove:GetPos()) then
                else
                    local near = false
                    local r = tonumber(F.Config.StoveNear) or 200
                    for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                        if IsValid(p) and p:Alive() and p:GetPos():DistToSqr(stove:GetPos()) <= r * r then
                            near = true
                            break
                        end
                    end
                    local ch = near and (F.Config.StoveChanceNear or 0.008) or (F.Config.StoveChanceAway or 0.024)
                    if math.Rand(0, 1) < ch then
                        if stove.SetStoveState then stove:SetStoveState(0) end
                        if stove.SetStoveRecipe then stove:SetStoveRecipe("") end
                        F.Ignite(stove, "stove", "system")
                    end
                end
            end
        end
    end)

    --[[ СТРАХОВКА ОТ ЗАБЫТОГО ГИДРАНТА.

         Даже с исправленным правом закрытия гидрант можно бросить
         открытым: человек ушёл, вылетел, сменил персонажа. Открытый
         гидрант мешает — насос считает его занятым, а вода хлещет.

         Если рядом нет ни одного подключённого рукава и никто им не
         пользуется дольше минуты, кран закрывается сам. Пожару это не
         помешает: во время работы рукав как раз подключён. ]]
    F.HydrantIdleClose = 60

    local function hydrantWatch()
        local list = (GRM.Perf and GRM.Perf.Entities)
            and GRM.Perf.Entities("grm_fire_hydrant") or ents.FindByClass("grm_fire_hydrant")
        local now = CurTime()
        for _, ent in ipairs(list or {}) do
            if IsValid(ent) and ent.GetOpen and ent:GetOpen() == true then
                -- Подключённый рукав означает, что гидрант в работе.
                local busy = false
                if ent.GetHoses then
                    local h = ent:GetHoses()
                    busy = istable(h) and #h > 0
                elseif ent.GetHoseCount then
                    busy = (tonumber(ent:GetHoseCount()) or 0) > 0
                end
                if busy then
                    ent._grmIdleSince = nil
                else
                    ent._grmIdleSince = ent._grmIdleSince or now
                    if now - ent._grmIdleSince > F.HydrantIdleClose then
                        ent._grmIdleSince = nil
                        if ent.SetOpen then ent:SetOpen(false) end
                    end
                end
            end
        end
    end

    if GRM.Sched then
        -- low: это уборка, точность в секунду не нужна.
        GRM.Sched.Every("fire.hydrantwatch", 10, hydrantWatch, { prio = "low" })
    else
        timer.Create("GRM_Fire_HydrantWatch", 10, 0, hydrantWatch)
    end

    timer.Create("GRM_Fire_Autosave", 15, 0, function()
        if dirty and CurTime() - lastSave > 10 then F.SaveActive("autosave") end
    end)

    hook.Add("ShutDown", "GRM_Fire_Save", function() F.SaveActive("shutdown") end)
    F.LoadConfig()

    if GRM.Boot and GRM.Boot.Task then
        GRM.Boot.Task("fire.state", "normal", function()
            F.LoadConfig()
            F.LoadActive()
            scheduleRandom()
        end, { label = "Пожары: конфиг и активные очаги" })
        -- Чистка бесхозного снаряжения никому не мешает подождать.
        GRM.Boot.Task("fire.sweep", "late", function() F.SweepOrphanGear("boot") end,
            { needs = { "fire.state" }, label = "Пожары: чистка бесхозных рукавов" })
    else
        hook.Add("InitPostEntity", "GRM_Fire_Boot", function()
            timer.Simple(3, function()
                F.LoadConfig()
                F.LoadActive()
                scheduleRandom()
            end)
            timer.Simple(5, function() F.SweepOrphanGear("boot") end)
        end)
    end
    hook.Add("PostCleanupMap", "GRM_Fire_Cleanup", function()
        timer.Simple(2, function() F.LoadActive() end)
        timer.Simple(4, function() F.SweepOrphanGear("cleanup") end)
    end)

    hook.Add("PlayerSay", "GRM_Fire_AdminChat", function(ply, text)
        local t = string.lower(string.Trim(tostring(text or "")))
        if t == "/fire_ignite" or t == "!fire_ignite" then
            if not ply:IsSuperAdmin() then tell(ply, "Только суперадмин.", 255, 100, 100) return "" end
            local tr = ply:GetEyeTrace()
            F.Ignite(tr.HitPos, "admin", (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply)) or ply:SteamID64())
            tell(ply, "Очаг создан.", 100, 220, 130)
            return ""
        end
        if t == "/fire_kill" or t == "!fire_kill" then
            if not ply:IsSuperAdmin() then tell(ply, "Только суперадмин.", 255, 100, 100) return "" end
            local n = F.ExtinguishAround(ply:GetEyeTrace().HitPos, 180)
            tell(ply, "Погашено клеток: " .. tostring(n), 100, 220, 255)
            return ""
        end
    end)

    concommand.Add("grm_fire_ignite", function(ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        F.Ignite(ply:GetEyeTrace().HitPos, "admin", ply:SteamID64())
    end)
    concommand.Add("grm_fire_kill", function(ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        F.ExtinguishAround(ply:GetEyeTrace().HitPos, 180)
    end)

    print("[GRM Fire] v" .. F.Version .. " (Код 58) серверная обвязка")
end

-- Вечер-18: единый словарь slash-команд: имена живого PlayerSay-обработчика
-- вносятся во внешний реестр библиотеки (на режиме сверка идёт ДО ParseSay —
-- без регистрации команда стала бы «неизвестной»).
if GRM and GRM.Chat and GRM.Chat.RegisterExternalCommands then
    GRM.Chat.RegisterExternalCommands({ "/fire_ignite", "/fire_kill" })
end
