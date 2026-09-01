--[[--------------------------------------------------------------------
    GRM Fire Truck (Код 58) — пожарная машина как у инкассации.
    Какой ТС считать пожарным: список spawn-name/класса в
    data/grm_fire/trucks.json (по фракции), либо уже навешенный насос,
    либо суперадмин пометил /firetruck.
    Установка: тул «насос» на машину  ИЛИ  сел в разрешённое ТС → /firetruck
----------------------------------------------------------------------]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Fire = GRM.Fire or {}
local F = GRM.Fire

F.TruckCfg = F.TruckCfg or {
    HoseSlots = 4,
    TankMax = 4000,
    FoamMax = 500,
    PowderMax = 250,
    PumpOffset = Vector(0, -46, 16),
    PumpAng = Angle(0, 90, 0),
}
if (F.TruckCfg.TankMax or 0) < 4000 then F.TruckCfg.TankMax = 4000 end

local TRUCK_FILE = "grm_fire/trucks.json"
local NET_TREQ = "GRM_FireTruck_Open"
local NET_TDATA = "GRM_FireTruck_Data"
local NET_TSAVE = "GRM_FireTruck_Save"

local function jsonT(txt)
    local ok, t = pcall(util.JSONToTable, txt, false, true)
    return (ok and istable(t)) and t or nil
end

local function tell(ply, msg, r, g, b)
    if IsValid(ply) and GRM.Notify then GRM.Notify(ply, msg, r or 220, g or 180, b or 80)
    elseif IsValid(ply) then ply:ChatPrint("[Пожар] " .. tostring(msg)) end
end

local function isCarEntity(ent)
    if not IsValid(ent) then return false end
    local cls = ent:GetClass() or ""
    if ent.IsVehicle and ent:IsVehicle() then return true end
    if string.StartWith(cls, "simfphys_") then return true end
    if string.StartWith(cls, "lvs_") then return true end
    if string.StartWith(cls, "glide_") then return true end
    if string.StartWith(cls, "gmod_sent_vehicle") then return true end
    if string.StartWith(cls, "prop_vehicle_") then return true end
    return false
end

local function getRootVehicle(ent)
    if not IsValid(ent) then return nil end
    local cur, seen = ent, {}
    for _ = 1, 8 do
        if not IsValid(cur) or seen[cur] then break end
        seen[cur] = true
        local p = isfunction(cur.GetParent) and cur:GetParent() or nil
        if IsValid(p) and not p:IsPlayer() and not p:IsWorld() and isCarEntity(p) then
            cur = p
        else
            break
        end
    end
    return isCarEntity(cur) and cur or nil
end

local function getDriverOf(veh)
    if not IsValid(veh) then return nil end
    local ok, d = pcall(function() return veh:GetDriver() end)
    if ok and IsValid(d) and d:IsPlayer() then return d end
    if isfunction(veh.GetDriverSeat) then
        local okS, s = pcall(veh.GetDriverSeat, veh)
        if okS and IsValid(s) then
            local okD, sd = pcall(s.GetDriver, s)
            if okD and IsValid(sd) and sd:IsPlayer() then return sd end
        end
    end
    for _, child in ipairs(veh:GetChildren() or {}) do
        if IsValid(child) and child.IsVehicle and child:IsVehicle() then
            local okC, cd = pcall(child.GetDriver, child)
            if okC and IsValid(cd) and cd:IsPlayer() then return cd end
        end
    end
    return nil
end

local function addAlias(aliases, v)
    if not isstring(v) or v == "" then return end
    local vl = string.lower(v)
    for i = 1, #aliases do if aliases[i] == vl then return end end
    aliases[#aliases + 1] = vl
end

function F.VehicleAliases(veh)
    local aliases = {}
    if not IsValid(veh) then return aliases end
    addAlias(aliases, veh:GetClass())
    if isstring(veh.GRM_FireSpawnName) then addAlias(aliases, veh.GRM_FireSpawnName) end
    for _, fn in ipairs({
        "GetSpawn_List", "GetSpawnList", "GetSpawningName",
        "GetVehicleListName", "GetVehicleName",
        "GetLVSVehicleName", "GetVehicleClass",
    }) do
        if isfunction(veh[fn]) then
            local ok, v = pcall(veh[fn], veh)
            if ok then addAlias(aliases, v) end
        end
    end
    for _, k in ipairs({
        "SpawnList", "Spawn_List", "SpawnName", "VehicleName",
        "List_ID", "ListName", "LVSVehicleName", "VehicleClassName",
    }) do
        if isstring(veh[k]) then addAlias(aliases, veh[k]) end
    end
    if isfunction(veh.GetModel) then
        local ok, mdl = pcall(veh.GetModel, veh)
        if ok and isstring(mdl) then
            addAlias(aliases, mdl)
            addAlias(aliases, mdl:match("([^/\\]+)$"))
        end
    end
    if list and isfunction(list.Get) then
        local okM, myMdl = pcall(veh.GetModel, veh)
        local vehModel = (okM and isstring(myMdl)) and string.lower(myMdl) or nil
        for _, lstName in ipairs({ "simfphys_vehicles", "Vehicles", "LVS_Vehicles" }) do
            local lst = list.Get(lstName)
            if istable(lst) and vehModel then
                for key, info in pairs(lst) do
                    if isstring(key) and istable(info) and isstring(info.Model)
                        and string.lower(info.Model) == vehModel then
                        addAlias(aliases, key)
                    end
                end
            end
        end
    end
    return aliases
end

local function normalizeTruckData(data)
    data = istable(data) and data or {}
    data.version = 1
    local rows = {}
    local src = data.factions
    if istable(src) then
        if src[1] then
            for _, rec in ipairs(src) do
                if istable(rec) and isstring(rec.name) and rec.name ~= "" then
                    local roles, vehs = {}, {}
                    for _, r in ipairs(istable(rec.roles) and rec.roles or {}) do
                        if isstring(r) and r ~= "" then roles[#roles + 1] = r end
                    end
                    for _, v in ipairs(istable(rec.vehicles) and rec.vehicles or {}) do
                        if isstring(v) and v ~= "" then vehs[#vehs + 1] = v end
                    end
                    rows[#rows + 1] = {
                        name = rec.name,
                        enabled = rec.enabled == true,
                        roles = roles,
                        vehicles = vehs,
                    }
                end
            end
        else
            for name, rec in pairs(src) do
                if istable(rec) then
                    rows[#rows + 1] = {
                        name = tostring(name),
                        enabled = rec.enabled == true,
                        roles = istable(rec.roles) and rec.roles or {},
                        vehicles = istable(rec.vehicles) and rec.vehicles or {},
                    }
                end
            end
        end
    end
    data.factions = rows
    return data
end

function F.GetTruckRow(factionName)
    factionName = tostring(factionName or "")
    for _, rec in ipairs((F.TruckData and F.TruckData.factions) or {}) do
        if rec.name == factionName then return rec end
    end
    return nil
end

function F.PlayerFireInfo(ply)
    if not IsValid(ply) or not istable(Factions) then return nil, nil, nil end
    for name, f in pairs(Factions) do
        if istable(f) and istable(f.Members) then
            local m = GRM.Identity and GRM.Identity.FactionMember and GRM.Identity.FactionMember(f, ply)
            if istable(m) then return name, m.Role or "Участник", f end
        end
    end
    return nil, nil, nil
end

function F.CanUseFireTruck(ply)
    if not IsValid(ply) then return false, "нет игрока" end
    if ply:IsSuperAdmin() then
        local fname = F.PlayerFireInfo(ply)
        return true, fname or "Администрация", F.GetTruckRow(fname) or { enabled = true, roles = {}, vehicles = {} }
    end
    if not (F.CanFightPro and F.CanFightPro(ply)) then
        return false, "нет доступа пожарного (галочка в /fire_access)"
    end
    local fname, role = F.PlayerFireInfo(ply)
    if not fname then return false, "вы не во фракции" end
    local row = F.GetTruckRow(fname)
    if not row or not row.enabled then
        return false, "для фракции «" .. fname .. "» пожарные машины не включены (/fire_trucks)"
    end
    if #(row.roles or {}) > 0 then
        local ok = false
        for _, r in ipairs(row.roles) do if r == role then ok = true break end end
        if not ok then return false, "роль «" .. tostring(role) .. "» не допущена к машине" end
    end
    return true, fname, row
end

function F.IsListedFireTruck(veh, factionName)
    if not IsValid(veh) then return false end
    local row = F.GetTruckRow(factionName)
    if not row or not row.enabled then return false end
    local allowed = row.vehicles or {}
    if #allowed == 0 then return false end
    local aliases = F.VehicleAliases(veh)
    for _, cand in ipairs(aliases) do
        for _, name in ipairs(allowed) do
            if cand == string.lower(name) then return true end
        end
    end
    return false
end

function F.FindPumpOn(veh)
    if not IsValid(veh) then return nil end
    for _, e in ipairs(ents.FindByClass("grm_fire_pump")) do
        if IsValid(e) then
            local host = e.GetHostVehicle and e:GetHostVehicle() or nil
            if host == veh or e:GetParent() == veh then return e end
        end
    end
    return nil
end

function F.IsFireTruck(veh)
    if not IsValid(veh) then return false end
    veh = getRootVehicle(veh) or veh
    if veh.GetNWBool and veh:GetNWBool("GRM_FireTruck", false) then return true end
    if IsValid(F.FindPumpOn(veh)) then return true end
    return false
end

function F.GetRootVehicle(ent)
    return getRootVehicle(ent)
end

--[[ ЧИСТОЕ ПРАВИЛО СТРОКИ ПОЖАРКИ (гоняется стендом без игры).

     Заказ владельца 22.08: счётчики воды и пены показываются, ТОЛЬКО когда
     боец смотрит на свою машину или сидит в ней — и только тому, у кого
     есть доступ к системе тушения. Раньше хватало «стоять рядом», а после
     /firetruck строка загоралась у любого, кто оказался в кабине. ]]
function F.TruckHUDVisible(crew, seated, looking, dist, maxDist)
    if crew ~= true then return false end
    if seated == true then return true end
    if looking ~= true then return false end
    return (tonumber(dist) or math.huge) <= (tonumber(maxDist) or 0)
end

function F.NearbyFireVehicle(ply)
    if not IsValid(ply) then return nil end
    local duty = ply.GetNWEntity and ply:GetNWEntity("GRM_FireMyTruck")
    if IsValid(duty) then return getRootVehicle(duty) or duty end
    local seat = ply.GetVehicle and ply:GetVehicle()
    if IsValid(seat) then
        local root = getRootVehicle(seat)
        if IsValid(root) then return root end
    end
    local tr = ply.GetEyeTrace and ply:GetEyeTrace()
    if tr and IsValid(tr.Entity) then
        local root = getRootVehicle(tr.Entity)
        if IsValid(root) and (F.IsFireTruck(root) or IsValid(F.FindPumpOn(root))) then return root end
        if IsValid(root) then
            local ok, fname = F.CanUseFireTruck(ply)
            if ok and F.IsListedFireTruck(root, fname) then return root end
        end
        if tr.Entity:GetClass() == "grm_fire_pump" then
            local host = tr.Entity.GetHostVehicle and tr.Entity:GetHostVehicle() or tr.Entity:GetParent()
            if IsValid(host) then return getRootVehicle(host) or host end
        end
    end
    for _, e in ipairs(ents.FindInSphere(ply:GetPos(), 320)) do
        if not IsValid(e) then
        elseif e:GetClass() == "grm_fire_pump" then
            local host = e.GetHostVehicle and e:GetHostVehicle() or e:GetParent()
            if IsValid(host) then return getRootVehicle(host) or host end
        elseif F.IsFireTruck(e) then
            return getRootVehicle(e) or e
        end
    end
    return nil
end

function F.EnsureTruckPump(ply, veh)
    if not IsValid(ply) then return nil, "нет игрока" end
    local ok, errOrName = F.CanUseFireTruck(ply)
    if not ok then return nil, errOrName end
    veh = IsValid(veh) and (getRootVehicle(veh) or veh) or F.NearbyFireVehicle(ply)
    if not IsValid(veh) then return nil, "подойдите к пожарной машине (или сядьте и /firetruck)" end
    local listed = F.IsListedFireTruck(veh, errOrName)
    local already = F.IsFireTruck(veh)
    if not listed and not already and not ply:IsSuperAdmin() then
        return nil, "это ТС не пожарное — /firetruck с водительского или внесите класс в /fire_trucks"
    end
    local pump, err = F.AttachPump(veh, ply)
    if not IsValid(pump) then return nil, err or "насос не создался" end
    veh:SetNWBool("GRM_FireTruck", true)
    veh:SetNWString("GRM_FireFaction", tostring(errOrName or ""))
    ply:SetNWEntity("GRM_FireMyTruck", veh)
    if F.PublishCrewFlag then F.PublishCrewFlag(ply) end
    return pump, veh
end

function F.TakeHoseFromTruck(ply)
    local pump, err = F.EnsureTruckPump(ply)
    if not IsValid(pump) then return false, err end
    local A = GRM.FireAddon
    if not (A and A.TakeHose) then return false, "аддон рукава не загружен (grm_fire_addon.zip)" end
    local h, e = A.TakeHose(ply, pump)
    if h then return true end
    return false, e or "не выдать рукав"
end

function F.AttachPump(veh, ply)
    if not IsValid(veh) then return nil, "нет ТС" end
    local exist = F.FindPumpOn(veh)
    if IsValid(exist) then return exist end
    if not F.AddonReady or not F.AddonReady() then
        return nil, "аддон grm_fire не загружен"
    end
    local pump = ents.Create("grm_fire_pump")
    if not IsValid(pump) then return nil, "не создался насос" end
    pump:SetPos(veh:GetPos() + Vector(0, 0, 40))
    pump:Spawn()
    pump:Activate()
    local cfg = F.TruckCfg
    if pump.AttachToVehicle then
        pump:AttachToVehicle(veh, cfg.PumpOffset, cfg.PumpAng)
    else
        pump:SetParent(veh)
        pump:SetLocalPos(cfg.PumpOffset)
        pump:SetLocalAngles(cfg.PumpAng)
    end
    if pump.SetHosesMax then pump:SetHosesMax(cfg.HoseSlots) end
    if pump.SetTankMax then pump:SetTankMax(cfg.TankMax or 4000) end
    if pump.SetTank then pump:SetTank(cfg.TankMax or 4000) end
    if pump.SetFoamMax then pump:SetFoamMax(cfg.FoamMax or 500) end
    if pump.SetFoam then pump:SetFoam(cfg.FoamMax or 500) end
    if pump.SetPowderMax then pump:SetPowderMax(cfg.PowderMax or 250) end
    if pump.SetPowder then pump:SetPowder(cfg.PowderMax or 250) end
    if pump.SetAgent then pump:SetAgent("water") end
    if pump.SetPumpOn then pump:SetPumpOn(true) end
    if pump.SyncHost then pump:SyncHost() end
    pump._grmTruckGear = true
    if pump.SetNWBool then pump:SetNWBool("GRM_TruckGear", true) end
    -- не пермим: после рестарта ТС нет, насос остаётся в воздухе
    return pump
end

function F.CommissionTruck(ply)
    if not IsValid(ply) then return false, "нет игрока" end
    local ok, fnameOrErr, row = F.CanUseFireTruck(ply)
    if not ok then return false, fnameOrErr end
    local seat = ply:GetVehicle()
    if not IsValid(seat) then return false, "сядьте за руль пожарной машины" end
    local veh = getRootVehicle(seat)
    if not IsValid(veh) then return false, "ТС не найдено" end
    local drv = getDriverOf(veh)
    if IsValid(drv) and drv ~= ply and not ply:IsSuperAdmin() then
        return false, "нужно водительское место"
    end
    local listed = F.IsListedFireTruck(veh, fnameOrErr)
    local already = F.IsFireTruck(veh)
    if not listed and not already and not ply:IsSuperAdmin() then
        local aliases = table.concat(F.VehicleAliases(veh), ", ")
        return false, "этот класс ТС не в списке пожарных («" .. tostring(fnameOrErr) .. "»). Алиасы: " .. aliases
    end
    local pump, err = F.AttachPump(veh, ply)
    if not IsValid(pump) then return false, err end
    local spawnName = F.VehicleAliases(veh)[1] or veh:GetClass()
    veh.GRM_FireSpawnName = spawnName
    veh:SetNWBool("GRM_FireTruck", true)
    veh:SetNWString("GRM_FireFaction", tostring(fnameOrErr or ""))
    veh:SetNWString("GRM_FireSpawnName", tostring(spawnName))
    veh:SetNWInt("GRM_FireHoses", pump.GetHosesMax and pump:GetHosesMax() or 4)
    veh:SetNWInt("GRM_FireTank", pump.GetTank and pump:GetTank() or 0)
    ply:SetNWEntity("GRM_FireMyTruck", veh)
    if F.PublishCrewFlag then F.PublishCrewFlag(ply) end
    tell(ply, "Машина принята. G — панель (взять рукав, связать с гидрантом). E по машине/насосу — ствол. Гидрант: откройте E, подъезд ~6 м или кнопка «Связать».", 100, 220, 130)
    print("[GRM Fire] truck commissioned by " .. ply:Nick() .. " class=" .. veh:GetClass())
    return true, veh, pump
end

function F.DecommissionTruck(ply)
    local veh = IsValid(ply) and ply:GetNWEntity("GRM_FireMyTruck") or NULL
    if not IsValid(veh) then
        local seat = IsValid(ply) and ply:GetVehicle()
        veh = getRootVehicle(seat)
    end
    if not IsValid(veh) or not F.IsFireTruck(veh) then
        return false, "нет активной пожарной машины"
    end
    local pump = F.FindPumpOn(veh)
    if IsValid(pump) and GRM.FireAddon and GRM.FireAddon.HoseCountOn then
        if GRM.FireAddon.HoseCountOn(pump) > 0 then
            return false, "сначала верните рукава на катушку"
        end
    end
    veh:SetNWBool("GRM_FireTruck", false)
    veh:SetNWString("GRM_FireFaction", "")
    if IsValid(ply) then
        ply:SetNWEntity("GRM_FireMyTruck", NULL)
        if F.PublishCrewFlag then F.PublishCrewFlag(ply) end
    end
    tell(ply, "Пожарная машина снята с дежурства (насос на борту остаётся).", 200, 200, 120)
    return true
end

if SERVER then
    util.AddNetworkString(NET_TREQ)
    util.AddNetworkString(NET_TDATA)
    util.AddNetworkString(NET_TSAVE)

    local function ensureDir()
        if not file.IsDir("grm_fire", "DATA") then file.CreateDir("grm_fire") end
    end

    function F.LoadTrucks()
        ensureDir()
        if not file.Exists(TRUCK_FILE, "DATA") then
            F.TruckData = normalizeTruckData({})
            return F.TruckData
        end
        local raw = file.Read(TRUCK_FILE, "DATA") or ""
        local t = jsonT(raw)
        if not istable(t) then
            local q = TRUCK_FILE .. ".corrupt." .. os.time()
            file.Write(q, raw)
            print("[GRM Fire] trucks битый — " .. q)
            F.TruckData = normalizeTruckData({})
            return F.TruckData
        end
        F.TruckData = normalizeTruckData(t)
        return F.TruckData
    end

    function F.SaveTrucks(data)
        ensureDir()
        F.TruckData = normalizeTruckData(data or F.TruckData)
        local ok, txt = pcall(util.TableToJSON, F.TruckData, true)
        if not ok or not isstring(txt) then return false end
        file.Write(TRUCK_FILE, txt)
        local chk = file.Read(TRUCK_FILE, "DATA")
        if chk ~= txt then
            print("[GRM Fire] trucks SAVE read-back fail")
            return false
        end
        print("[GRM Fire] SAVE trucks ok [" .. #(F.TruckData.factions or {}) .. " фракций]")
        return true
    end
    F.LoadTrucks()

    local function factionNames()
        local out = {}
        if istable(Factions) then
            for n, f in pairs(Factions) do
                if istable(f) then out[#out + 1] = tostring(n) end
            end
        end
        table.sort(out)
        return out
    end

    local function rolesOf(name)
        local f = Factions and Factions[name]
        return (istable(f) and istable(f.Roles)) and f.Roles or {}
    end

    local function vehicleCatalog()
        local out, seen = {}, {}
        if list and isfunction(list.Get) then
            for _, listName in ipairs({ "Vehicles", "simfphys_vehicles", "LVS_Vehicles" }) do
                local lst = list.Get(listName)
                if istable(lst) then
                    for clsName in pairs(lst) do
                        if isstring(clsName) and clsName ~= "" and not seen[clsName] then
                            seen[clsName] = true
                            out[#out + 1] = clsName
                        end
                    end
                end
            end
        end
        table.sort(out)
        return out
    end

    local function sendTruckUI(ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        net.Start(NET_TDATA)
            net.WriteTable(F.TruckData or normalizeTruckData({}))
            net.WriteTable(factionNames())
            local roleMap = {}
            for _, n in ipairs(factionNames()) do roleMap[n] = rolesOf(n) end
            net.WriteTable(roleMap)
            net.WriteTable(vehicleCatalog())
        net.Send(ply)
    end

    net.Receive(NET_TREQ, function(_, ply) sendTruckUI(ply) end)
    net.Receive(NET_TSAVE, function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        local data = net.ReadTable() or {}
        F.SaveTrucks(data)
        sendTruckUI(ply)
        tell(ply, "Список пожарных машин сохранён.", 100, 220, 130)
    end)

    local function openTrucks(ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then
            tell(ply, "Только суперадмин.", 255, 100, 100)
            return
        end
        sendTruckUI(ply)
    end

    local function handleChat(ply, text)
        local t = string.lower(string.Trim(tostring(text or "")))
        if t == "/firetruck" or t == "!firetruck" or t == "/feuer" or t == "/пожарка" or t == "/пм" then
            local ok, err = F.CommissionTruck(ply)
            if not ok then tell(ply, err, 255, 120, 80) end
            return true
        end
        if t == "/firetruck_off" or t == "/пожарка_стоп" or t == "/feuer_off" then
            local ok, err = F.DecommissionTruck(ply)
            if not ok then tell(ply, err, 255, 120, 80) end
            return true
        end
        if t == "/fire_trucks" or t == "!fire_trucks" or t == "/firetruck_admin" then
            openTrucks(ply)
            return true
        end
        if t == "/рукав" or t == "/hose" or t == "/ствол" or t == "!hose" or t == "/пожарныйрукав" then
            local ok, err = F.TakeHoseFromTruck(ply)
            if ok then tell(ply, "Ствол в руках. ЛКМ — лить. Назад по рукаву — смотка.", 100, 220, 130)
            else tell(ply, tostring(err or "не выдать"), 255, 120, 80) end
            return true
        end
        return false
    end

    hook.Add("PlayerSay", "GRM_FireTruck_Chat", function(ply, text)
        if handleChat(ply, text) then return "" end
    end)
    hook.Add("PlayerSayTransform", "GRM_FireTruck_ChatT", function(ply, datapack)
        if not istable(datapack) or not isstring(datapack[1]) then return end
        if handleChat(ply, datapack[1]) then
            datapack.SkipPlayerSay = true
            datapack[1] = ""
        end
    end)

    concommand.Add("grm_fire_trucks", openTrucks)
    concommand.Add("grm_firetruck", function(ply)
        if not IsValid(ply) then return end
        local ok, err = F.CommissionTruck(ply)
        if not ok then tell(ply, err, 255, 120, 80) end
    end)

    hook.Add("PlayerEnteredVehicle", "GRM_FireTruck_Hint", function(ply, veh)
        timer.Simple(0.4, function()
            if not IsValid(ply) or not IsValid(veh) then return end
            local root = getRootVehicle(veh)
            if not IsValid(root) then return end
            local ok, fname = F.CanUseFireTruck(ply)
            if not ok then return end
            if F.IsListedFireTruck(root, fname) or F.IsFireTruck(root) then
                F.EnsureTruckPump(ply, root)
                tell(ply, "Пожарная машина. G — взять рукав / связать гидрант. Или /рукав. E по голубому насосу сбоку.", 120, 200, 255)
            end
        end)
    end)

    hook.Add("Think", "GRM_FireTruck_NW", function()
        if (F._truckNwAt or 0) > CurTime() then return end
        F._truckNwAt = CurTime() + 1
        local pumps=GRM.Perf and GRM.Perf.Entities and GRM.Perf.Entities("grm_fire_pump")or ents.FindByClass("grm_fire_pump")
        for _,pump in ipairs(pumps)do if IsValid(pump)then local veh=pump.GetHostVehicle and pump:GetHostVehicle()or pump:GetParent();if IsValid(veh)and veh:GetNWBool("GRM_FireTruck",false)then
            local tank=pump.GetTank and pump:GetTank()or 0;if not GRM.Perf or not GRM.Perf.NWInt then veh:SetNWInt("GRM_FireTank",tank)else GRM.Perf.NWInt(veh,"GRM_FireTank",tank)end
            if GRM.FireAddon and GRM.FireAddon.HoseCountOn and pump.GetHosesMax then local out,total=GRM.FireAddon.HoseCountOn(pump),pump:GetHosesMax();if GRM.Perf and GRM.Perf.NWInt then GRM.Perf.NWInt(veh,"GRM_FireHosesOut",out);GRM.Perf.NWInt(veh,"GRM_FireHoses",total)else veh:SetNWInt("GRM_FireHosesOut",out);veh:SetNWInt("GRM_FireHoses",total)end end
        end end end
    end)

    -- Машину снесли — смотать рукава и снять бортовое.
    -- Не требовать IsValid: в EntityRemoved ТС уже часто «невалидно».
    function F.DropTruckGear(veh)
        if not isentity(veh) then return 0 end
        local n = 0
        local A = GRM.FireAddon
        for _, e in ipairs(ents.FindByClass("grm_fire_pump")) do
            if IsValid(e) then
                local host = e.GetHostVehicle and e:GetHostVehicle() or NULL
                local par = e.GetParent and e:GetParent() or NULL
                local match = (host == veh) or (par == veh)
                if not match and (e._grmTruckGear or (e.GetNWBool and e:GetNWBool("GRM_TruckGear", false))) then
                    if not IsValid(host) and not IsValid(par) then match = true end
                end
                if match then
                    if A and A.ClearHosesOn then n = n + (A.ClearHosesOn(e) or 0) end
                    e:Remove()
                    n = n + 1
                end
            end
        end
        for _, e in ipairs(ents.FindByClass("grm_fire_ladder")) do
            if IsValid(e) then
                local host = e.GetHostVehicle and e:GetHostVehicle() or NULL
                local par = e.GetParent and e:GetParent() or NULL
                if host == veh or par == veh then
                    e:Remove()
                    n = n + 1
                end
            end
        end
        for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(ply) and ply.GetNWEntity and ply:GetNWEntity("GRM_FireMyTruck") == veh then
                ply:SetNWEntity("GRM_FireMyTruck", NULL)
            end
        end
        if A and A.ClearOrphanHoses then n = n + (A.ClearOrphanHoses() or 0) end
        return n
    end

    local function looksLikeTruck(ent)
        if not isentity(ent) then return false end
        local cls = ""
        pcall(function() cls = ent:GetClass() or "" end)
        if cls == "grm_fire_pump" or cls == "grm_fire_hose" or cls == "grm_fire_hose_node" then
            return false
        end
        local marked = false
        pcall(function()
            marked = ent.GetNWBool and ent:GetNWBool("GRM_FireTruck", false)
        end)
        if marked then return true end
        local veh = false
        pcall(function() veh = ent.IsVehicle and ent:IsVehicle() end)
        if veh then return true end
        if string.StartWith(cls, "simfphys_") or string.StartWith(cls, "lvs_")
            or string.StartWith(cls, "glide_") or string.StartWith(cls, "gmod_sent_vehicle")
            or string.StartWith(cls, "prop_vehicle_") then
            return true
        end
        if string.find(cls, "vehicle", 1, true) then return true end
        return false
    end

    hook.Add("EntityRemoved", "GRM_FireTruck_DropGear", function(ent)
        if not isentity(ent) then return end
        local cls = ""
        pcall(function() cls = ent:GetClass() or "" end)
        local A = GRM.FireAddon
        if cls == "grm_fire_pump" then
            if A and A.ClearHosesOn then A.ClearHosesOn(ent) end
            timer.Simple(0, function()
                if A and A.ClearOrphanHoses then A.ClearOrphanHoses() end
            end)
            return
        end
        if not looksLikeTruck(ent) then return end
        F.DropTruckGear(ent)
        timer.Simple(0, function()
            if A and A.ClearOrphanHoses then A.ClearOrphanHoses() end
        end)
    end)

    --[[ ПУБЛИКАЦИЯ ДОСТУПА ПОЖАРНОГО.
         Клиент не может сам спросить менеджер доступа — данные о правах
         живут на сервере. Поэтому право «работать с пожарной машиной»
         выкладывается одним флагом GRM_FireCrew, и строку с водой и пеной
         видит только тот, кому она положена (заказ владельца 22.08).
         Считается редко: на спавне, при постановке/снятии с дежурства и
         раз в 20 секунд — сама проверка обходит фракции, в кадре ей не место. ]]
    function F.PublishCrewFlag(ply)
        if not IsValid(ply) or not ply:IsPlayer() then return end
        local can = F.CanUseFireTruck(ply) == true
        if ply:GetNWBool("GRM_FireCrew", false) ~= can then
            ply:SetNWBool("GRM_FireCrew", can)
        end
    end

    function F.PublishCrewFlags()
        local list = (GRM.Perf and GRM.Perf.Players and GRM.Perf.Players()) or player.GetAll()
        for _, ply in ipairs(list) do F.PublishCrewFlag(ply) end
    end

    hook.Add("PlayerSpawn", "GRM_FireTruck_CrewFlag", function(ply)
        timer.Simple(1, function() F.PublishCrewFlag(ply) end)
    end)
    hook.Add("GRM_FireAccessChanged", "GRM_FireTruck_CrewFlag", function() F.PublishCrewFlags() end)
    hook.Add("GRM_CharacterChanged", "GRM_FireTruck_CrewFlag", function(ply)
        timer.Simple(0.5, function() F.PublishCrewFlag(ply) end)
    end)
    timer.Create("GRM_FireTruck_CrewFlags", 20, 0, function() F.PublishCrewFlags() end)

    print("[GRM Fire] Truck v1.0 loaded")
end

if CLIENT then
    surface.CreateFont("GRMFireTrk_Title", { font = "Roboto", size = 18, weight = 700, extended = true })
    surface.CreateFont("GRMFireTrk_N", { font = "Roboto", size = 14, weight = 500, extended = true })
    surface.CreateFont("GRMFireTrk_3D", { font = "Roboto", size = 20, weight = 800, extended = true })

    local THEME = {
        bg = Color(22, 24, 30, 250), panel = Color(32, 36, 46, 245),
        text = Color(230, 235, 240), green = Color(70, 180, 110), accent = Color(220, 110, 50),
    }

    net.Receive(NET_TDATA, function()
        local data = net.ReadTable() or { factions = {} }
        local facNames = net.ReadTable() or {}
        local roleMap = net.ReadTable() or {}
        local catalog = net.ReadTable() or {}
        data = normalizeTruckData(data)

        if IsValid(F._tframe) then F._tframe:Remove() end
        local frame = vgui.Create("DFrame")
        F._tframe = frame
        frame:SetTitle("")
        frame:SetSize(860, 640)
        frame:Center()
        frame:MakePopup()
        frame.Paint = function(_, w, h)
            draw.RoundedBox(8, 0, 0, w, h, THEME.bg)
            draw.SimpleText("Пожарные машины", "GRMFireTrk_Title", 14, 18, THEME.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end

        local top = vgui.Create("DPanel", frame)
        top:Dock(TOP) top:SetTall(36) top:DockMargin(10, 36, 10, 4)
        top:SetPaintBackground(false)
        local combo = vgui.Create("DComboBox", top)
        combo:Dock(LEFT) combo:SetWide(280)
        combo:SetValue("Фракция…")
        for _, n in ipairs(facNames) do combo:AddChoice(n) end

        local hint = vgui.Create("DLabel", top)
        hint:Dock(FILL) hint:DockMargin(12, 8, 0, 0)
        hint:SetText("Включите фракцию, отметьте роли, добавьте spawn-name ТС (как инкассация).")
        hint:SetTextColor(Color(170, 175, 185))

        local body = vgui.Create("DScrollPanel", frame)
        body:Dock(FILL) body:DockMargin(10, 4, 10, 52)

        local state = { enabled = false, roles = {}, vehicles = {} }

        local function rowOf(name)
            for _, rec in ipairs(data.factions or {}) do
                if rec.name == name then return rec end
            end
        end

        local function rebuild(fname)
            body:Clear()
            local rec = rowOf(fname) or { name = fname, enabled = false, roles = {}, vehicles = {} }
            state.enabled = rec.enabled == true
            state.roles = {}
            for _, r in ipairs(rec.roles or {}) do state.roles[r] = true end
            state.vehicles = {}
            for _, v in ipairs(rec.vehicles or {}) do state.vehicles[#state.vehicles + 1] = v end

            local chk = vgui.Create("DCheckBoxLabel", body)
            chk:Dock(TOP) chk:DockMargin(6, 6, 6, 8)
            chk:SetText("Включить пожарные машины для «" .. fname .. "»")
            chk:SetTextColor(THEME.text)
            chk:SetValue(state.enabled and 1 or 0)
            chk.OnChange = function(_, v) state.enabled = v and true or false end

            local rl = vgui.Create("DLabel", body)
            rl:Dock(TOP) rl:SetTall(22) rl:DockMargin(6, 8, 6, 2)
            rl:SetText("Роли (пусто = все роли фракции с доступом FightPro):")
            rl:SetTextColor(THEME.accent)

            for _, role in ipairs(roleMap[fname] or {}) do
                local c = vgui.Create("DCheckBoxLabel", body)
                c:Dock(TOP) c:DockMargin(20, 2, 6, 2)
                c:SetText(role) c:SetTextColor(THEME.text)
                c:SetValue(state.roles[role] and 1 or 0)
                c.OnChange = function(_, v) state.roles[role] = v and true or nil end
            end

            local vl = vgui.Create("DLabel", body)
            vl:Dock(TOP) vl:SetTall(22) vl:DockMargin(6, 12, 6, 2)
            vl:SetText("Разрешённые ТС (spawn-name / класс, как у инкассации):")
            vl:SetTextColor(THEME.accent)

            local listP = vgui.Create("DPanel", body)
            listP:Dock(TOP) listP:SetTall(160) listP:DockMargin(6, 4, 6, 4)
            listP:SetPaintBackground(false)
            local vehList = vgui.Create("DListView", listP)
            vehList:Dock(FILL)
            vehList:AddColumn("Класс / spawn-name")
            local function redrawVeh()
                vehList:Clear()
                for _, v in ipairs(state.vehicles) do vehList:AddLine(v) end
            end
            redrawVeh()

            local addRow = vgui.Create("DPanel", body)
            addRow:Dock(TOP) addRow:SetTall(32) addRow:DockMargin(6, 2, 6, 6)
            addRow:SetPaintBackground(false)
            local entry = vgui.Create("DTextEntry", addRow)
            entry:Dock(LEFT) entry:SetWide(260)
            entry:SetPlaceholderText("simfphys_… / класс")
            local add = vgui.Create("DButton", addRow)
            add:Dock(LEFT) add:SetWide(110) add:DockMargin(6, 0, 0, 0)
            add:SetText("Добавить")
            add.DoClick = function()
                local s = string.Trim(entry:GetValue() or "")
                if s == "" then return end
                for _, v in ipairs(state.vehicles) do if v == s then return end end
                state.vehicles[#state.vehicles + 1] = s
                entry:SetText("")
                redrawVeh()
            end
            local cat = vgui.Create("DComboBox", addRow)
            cat:Dock(FILL) cat:DockMargin(6, 0, 0, 0)
            cat:SetValue("Каталог ТС…")
            for _, cls in ipairs(catalog) do cat:AddChoice(cls, cls) end
            cat.OnSelect = function(_, _, _, id)
                if not id then return end
                for _, v in ipairs(state.vehicles) do if v == id then return end end
                state.vehicles[#state.vehicles + 1] = id
                redrawVeh()
            end
            vehList.OnRowRightClick = function(_, lineId)
                local line = vehList:GetLine(lineId)
                if not line then return end
                local name = line:GetColumnText(1)
                for i, v in ipairs(state.vehicles) do
                    if v == name then table.remove(state.vehicles, i) break end
                end
                redrawVeh()
            end
        end

        combo.OnSelect = function(_, _, fname) rebuild(fname) end

        local bot = vgui.Create("DPanel", frame)
        bot:Dock(BOTTOM) bot:SetTall(44) bot:SetPaintBackground(false)
        local save = vgui.Create("DButton", bot)
        save:Dock(RIGHT) save:SetWide(170) save:DockMargin(6, 6, 10, 6)
        save:SetText("Сохранить")
        save.Paint = function(self, w, h)
            draw.RoundedBox(6, 0, 0, w, h, self:IsHovered() and Color(90, 200, 120) or THEME.green)
        end
        save.DoClick = function()
            local fname = combo:GetValue()
            if not fname or fname == "" or fname == "Фракция…" then return end
            local roles = {}
            for r, on in pairs(state.roles) do if on then roles[#roles + 1] = r end end
            local found
            for i, rec in ipairs(data.factions or {}) do
                if rec.name == fname then found = i break end
            end
            local rec = { name = fname, enabled = state.enabled, roles = roles, vehicles = state.vehicles }
            data.factions = data.factions or {}
            if found then data.factions[found] = rec else data.factions[#data.factions + 1] = rec end
            net.Start(NET_TSAVE) net.WriteTable(data) net.SendToServer()
        end
        local how = vgui.Create("DLabel", bot)
        how:Dock(FILL) how:DockMargin(12, 12, 8, 0)
        how:SetText("ПКМ по строке ТС — убрать. Игрок: сел → /firetruck")
        how:SetTextColor(Color(170, 175, 185))
    end)

    concommand.Add("grm_fire_trucks", function()
        net.Start(NET_TREQ) net.SendToServer()
    end)

    local renderTrucks=setmetatable({},{__mode="k"})
    hook.Add("EntityNetworkedVarChanged","GRM_FireTruck_RenderRegistry",function(ent,name,_,value)if name=="GRM_FireTruck"then if value==true then renderTrucks[ent]=true else renderTrucks[ent]=nil end end end)
    hook.Add("EntityRemoved","GRM_FireTruck_RenderRegistryRemove",function(ent)renderTrucks[ent]=nil end)
    timer.Simple(1,function()for _,ent in ipairs(ents.GetAll())do if IsValid(ent)and ent.GetNWBool and ent:GetNWBool("GRM_FireTruck",false)then renderTrucks[ent]=true end end end)
    hook.Add("PostDrawTranslucentRenderables", "GRM_FireTruck_3D", function(_, sky)
        if sky then return end
        local lp = LocalPlayer()
        if not IsValid(lp) then return end
        for ent in pairs(renderTrucks) do
            if IsValid(ent) and ent.GetNWBool and ent:GetNWBool("GRM_FireTruck", false) then
                if lp:GetPos():DistToSqr(ent:GetPos()) > 520 * 520 then
                else
                    local obb = isfunction(ent.OBBMaxs) and ent:OBBMaxs() or Vector(0, 0, 50)
                    local pos = ent:LocalToWorld(Vector(0, 0, (obb.z or 50) + 18))
                    local ang = Angle(0, EyeAngles().y - 90, 90)
                    local fac = ent:GetNWString("GRM_FireFaction", "")
                    local tank = ent:GetNWInt("GRM_FireTank", 0)
                    local foam = ent:GetNWInt("GRM_FireFoam", 0)
                    local powder = ent:GetNWInt("GRM_FirePowder", 0)
                    local out = ent:GetNWInt("GRM_FireHosesOut", 0)
                    local maxh = ent:GetNWInt("GRM_FireHoses", 4)
                    cam.Start3D2D(pos, ang, 0.08)
                        draw.RoundedBox(6, -180, -28, 360, 56, Color(28, 18, 14, 230))
                        draw.SimpleText("ПОЖАРНАЯ" .. (fac ~= "" and (" · " .. fac) or ""), "GRMFireTrk_3D", 0, -10, Color(255, 150, 70), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                        draw.SimpleText("вода " .. tank .. "  пена " .. foam .. "  порошок " .. powder .. "  рукава " .. out .. "/" .. maxh, "GRMFireTrk_N", 0, 14, Color(230, 230, 235), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                    cam.End3D2D()
                end
            end
        end
    end)

    --[[ СТРОКА ПОЖАРКИ ВНИЗУ ЭКРАНА.

         История правок:
           • сперва она держалась на NW-ссылке «моя машина» — приняв машину
             на дежурство, боец видел счётчики ВСЕГДА, хоть на другом конце
             карты;
           • потом добавилась близость — и строка загоралась просто оттого,
             что человек проходил мимо, а в кабине её видел вообще любой,
             даже без доступа к системе тушения (заказ владельца 22.08).

         Теперь правило одно и жёсткое (F.TruckHUDVisible):
           • у игрока должен быть доступ пожарного — сервер публикует его
             одним флагом GRM_FireCrew, клиент ничего не решает сам;
           • и он либо СИДИТ в пожарной машине, либо СМОТРИТ на неё
             (трассировка, не радиус) с расстояния не больше
             grm_fire_hud_dist. ]]
    local hudDist = CreateClientConVar("grm_fire_hud_dist", "350", true, false,
        "На каком расстоянии от пожарной машины видна строка с водой и пеной")

    -- Взгляд считаем не каждый кадр: трассировка дорогая, а строке хватает
    -- пяти обновлений в секунду.
    local lookVeh, lookAt = nil, 0
    local function lookedTruck(ply)
        if CurTime() - lookAt > 0.2 then
            lookAt = CurTime()
            lookVeh = nil
            local tr = (GRM.Perf and GRM.Perf.EyeTrace) and GRM.Perf.EyeTrace(ply) or ply:GetEyeTrace()
            local ent = tr and tr.Entity or nil
            if IsValid(ent) then
                local root = (F.GetRootVehicle and F.GetRootVehicle(ent)) or ent
                if IsValid(root) and root.GetNWBool and root:GetNWBool("GRM_FireTruck", false) then
                    lookVeh = root
                end
            end
        end
        return IsValid(lookVeh) and lookVeh or nil
    end

    local function seatedTruck(ply)
        local seat = ply:GetVehicle()
        if not IsValid(seat) then return nil end
        local p = seat:GetParent()
        if IsValid(p) and p:GetNWBool("GRM_FireTruck", false) then return p end
        if seat:GetNWBool("GRM_FireTruck", false) then return seat end
        return nil
    end

    hook.Add("HUDPaint", "GRM_FireTruck_HUD", function()
        local ply = LocalPlayer()
        if not IsValid(ply) then return end
        local crew = ply:GetNWBool("GRM_FireCrew", false)
        if not crew then return end

        local seat = seatedTruck(ply)
        local look = (not seat) and lookedTruck(ply) or nil
        local veh = seat or look
        if not IsValid(veh) then return end

        local maxDist = math.Clamp(hudDist:GetInt(), 80, 4000)
        local dist = ply:GetPos():Distance(veh:GetPos())
        if not F.TruckHUDVisible(crew, seat ~= nil, look ~= nil, dist, maxDist) then return end

        local tank = veh:GetNWInt("GRM_FireTank", 0)
        local foam = veh:GetNWInt("GRM_FireFoam", 0)
        local powder = veh:GetNWInt("GRM_FirePowder", 0)
        local out = veh:GetNWInt("GRM_FireHosesOut", 0)
        local maxh = veh:GetNWInt("GRM_FireHoses", 4)
        draw.SimpleText("ПОЖАРКА  вода " .. tank .. "  пена " .. foam .. "  порошок " .. powder .. "  рукава " .. out .. "/" .. maxh .. "  G — насос",
            "GRMFireTrk_N", ScrW() / 2, ScrH() - 118, Color(255, 170, 90, 230), TEXT_ALIGN_CENTER)
    end)

    print("[GRM Fire] Truck client loaded")
end
