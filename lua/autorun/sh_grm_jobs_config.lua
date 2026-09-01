--[[--------------------------------------------------------------------
    GRM Jobs Configuration v2.0.0 (Код 77, расширение v3)
    Типизированные точки/маршруты, транспорт, такса и городская казна.
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Jobs = GRM.Jobs or {}
local JB = GRM.Jobs
JB.ConfigVersion = "2.0.0"

local NET_OPEN = "GRM_JobsAdmin_Open"
local NET_ACT = "GRM_JobsAdmin_Act"
local NET_TAXI = "GRM_JobsTaxi_Open"
local NET_TAXI_SET = "GRM_JobsTaxi_Set"

local POINT_TYPES = {
    all = "Универсальная",
    courier = "Курьер",
    garbage = "Мусорный контейнер",
    dump = "Свалка",
    taxi_pickup = "Посадка такси",
    taxi_dropoff = "Назначение такси",
}
JB.PointTypes = POINT_TYPES

local function clamp(v, lo, hi)
    v = tonumber(v) or lo
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

if SERVER then
    util.AddNetworkString(NET_OPEN)
    util.AddNetworkString(NET_ACT)
    util.AddNetworkString(NET_TAXI)
    util.AddNetworkString(NET_TAXI_SET)

    local DIR = "grm_jobs"
    local CFG_FILE = DIR .. "/config.json"
    local function mapFile() return DIR .. "/points_" .. string.lower(game.GetMap() or "unknown") .. ".json" end
    local function ensureDir() if not file.IsDir(DIR, "DATA") then file.CreateDir(DIR) end end
    local function jsonT(raw)
        local ok, data = pcall(util.JSONToTable, raw or "", false, true)
        return ok and istable(data) and data or nil
    end
    local function quarantine(path, raw)
        if raw and raw ~= "" then file.Write(path .. ".corrupt." .. os.time() .. ".txt", raw) end
    end
    -- Профиль маршрута мусоровоза. Поднятие числа заставляет один раз
    -- переставить контейнеры/вместимость на новые значения даже в уже
    -- сохранённом на сервере конфиге (иначе владелец получил бы старые 2/8).
    local GARBAGE_PROFILE = 3

    local function defaults()
        return {
            version = 2,
            garbageProfile = GARBAGE_PROFILE,
            fundFromState = true,
            taxiMin = 300,
            taxiMax = 2500,
            taxiDefault = 700,
            taxiVehicles = {},
            garbageVehicles = {},
            courierVehicles = {},
            -- Заказ владельца: маршрут из 3 контейнеров, кузов на 3 пакета.
            -- Мусоровоз едет на полигон ТОЛЬКО собрав 3/3.
            garbageStops = 3,
            garbageCapacity = 3,
            garbageSearchTime = 2.5,
            garbageBinCooldown = 90,
            garbageBindRadius = 500,
            garbageDumpRadius = 320,
            garbageUnloadTime = 4,
        }
    end
    local function normalizeCfg(t)
        local d = defaults()
        t = istable(t) and t or {}
        d.fundFromState = t.fundFromState ~= false
        d.taxiMin = math.floor(clamp(t.taxiMin, 0, 100000))
        d.taxiMax = math.floor(clamp(t.taxiMax, d.taxiMin, 100000))
        d.taxiDefault = math.floor(clamp(t.taxiDefault, d.taxiMin, d.taxiMax))
        d.garbageProfile = math.floor(tonumber(t.garbageProfile) or 0)
        if d.garbageProfile < GARBAGE_PROFILE then
            -- Одноразовая миграция старого конфига (2 контейнера / кузов 8).
            d.garbageStops = 3
            d.garbageCapacity = 3
            d.garbageProfile = GARBAGE_PROFILE
            print("[GRM Jobs] миграция маршрута мусоровоза: 3 контейнера, вместимость 3")
        else
            d.garbageStops = math.floor(clamp(t.garbageStops, 1, 8))
            d.garbageCapacity = math.floor(clamp(t.garbageCapacity, 1, 32))
        end
        -- Кузов не может быть меньше маршрута: иначе 3/3 недостижимо и
        -- игрок навсегда застревает между контейнером и полигоном.
        if d.garbageCapacity < d.garbageStops then d.garbageCapacity = d.garbageStops end
        d.garbageSearchTime = clamp(t.garbageSearchTime, .5, 15)
        d.garbageBinCooldown = math.floor(clamp(t.garbageBinCooldown, 10, 1800))
        d.garbageBindRadius = math.floor(clamp(t.garbageBindRadius, 100, 2000))
        d.garbageDumpRadius = math.floor(clamp(t.garbageDumpRadius, 150, 1000))
        d.garbageUnloadTime = clamp(t.garbageUnloadTime, 1, 30)
        d.taxiVehicles = istable(t.taxiVehicles) and t.taxiVehicles or {}
        d.garbageVehicles = istable(t.garbageVehicles) and t.garbageVehicles or {}
        d.courierVehicles = istable(t.courierVehicles) and t.courierVehicles or {}
        return d
    end
    local function normalizePoints(t)
        local out = {}
        t = istable(t) and (t.points or t) or {}
        for _, r in ipairs(t) do
            if istable(r) and istable(r.pos) then
                local typ = POINT_TYPES[tostring(r.type or "all")] and tostring(r.type or "all") or "all"
                out[#out + 1] = {
                    id = tostring(r.id or ("jp_" .. os.time() .. "_" .. #out + 1)),
                    type = typ,
                    name = string.sub(tostring(r.name or POINT_TYPES[typ]), 1, 64),
                    pos = { x = tonumber(r.pos.x) or 0, y = tonumber(r.pos.y) or 0, z = tonumber(r.pos.z) or 0 },
                    created = tonumber(r.created) or os.time(),
                }
            end
        end
        return out
    end
    local function save(path, data, why)
        ensureDir()
        local ok, raw = pcall(util.TableToJSON, data, true)
        if not ok or not raw then return false end
        file.Write(path, raw)
        local check = jsonT(file.Read(path, "DATA") or "")
        if not check then print("[GRM Jobs v3] SAVE FAIL " .. path) return false end
        print("[GRM Jobs v3] SAVE ok: " .. path .. " [" .. tostring(why or "-") .. "]")
        return true
    end
    function JB.LoadWorkConfig()
        ensureDir()
        local raw = file.Read(CFG_FILE, "DATA") or ""
        local cfg = jsonT(raw)
        if raw ~= "" and not cfg then quarantine(CFG_FILE, raw) end
        JB.WorkConfig = normalizeCfg(cfg)
        raw = file.Read(mapFile(), "DATA") or ""
        local pts = jsonT(raw)
        if raw ~= "" and not pts then quarantine(mapFile(), raw) end
        JB.WorkPoints = normalizePoints(pts)
    end
    function JB.SaveWorkConfig(why)
        return save(CFG_FILE, JB.WorkConfig, why) and save(mapFile(), { version = 2, points = JB.WorkPoints }, why)
    end
    function JB.AddWorkPoint(pointType,name,pointPos)
        pointType=POINT_TYPES[tostring(pointType or"")]and tostring(pointType)or nil;if not pointType or not pointPos then return false,"Неизвестный тип точки"end
        local rec={id="jp_"..os.time().."_"..math.random(1000,9999),type=pointType,name=string.sub(string.Trim(tostring(name or"")),1,64),pos={x=pointPos.x,y=pointPos.y,z=pointPos.z+4},created=os.time()};if rec.name==""then rec.name=POINT_TYPES[pointType]end
        JB.WorkPoints[#JB.WorkPoints+1]=rec;JB.SaveWorkConfig("добавлена точка "..pointType);if JB.RefreshGarbageTopology then timer.Simple(0,function()JB.RefreshGarbageTopology("point added")end)end;return true,rec
    end
    function JB.RemoveNearestWorkPoint(point,maxDistance)
        local best,bestIndex,bestDist=nil,nil,(tonumber(maxDistance)or 160)^2
        for i,rec in ipairs(JB.WorkPoints or{})do local p=Vector(rec.pos.x,rec.pos.y,rec.pos.z);local d=p:DistToSqr(point);if d<bestDist then best,bestIndex,bestDist=rec,i,d end end
        if not bestIndex then return false,"Рядом нет точки работы"end;table.remove(JB.WorkPoints,bestIndex);JB.SaveWorkConfig("удалена ближайшая точка");if JB.RefreshGarbageTopology then timer.Simple(0,function()JB.RefreshGarbageTopology("point removed")end)end;return true,best
    end
    JB.LoadWorkConfig()

    local function pointObject(rec)
        local pos = Vector(rec.pos.x, rec.pos.y, rec.pos.z)
        return {
            _grmJobPoint = rec,
            GetPos = function() return pos end,
            GetNWString = function(_, key, fallback)
                if key == "GRM_JobZoneName" then return rec.name end
                return fallback
            end,
        }
    end
    function JB.GetRoutePoints(kind)
        local out, all = {}, {}
        for _, rec in ipairs(JB.WorkPoints or {}) do
            local obj = pointObject(rec)
            all[#all + 1] = obj
            if kind == "all" or rec.type == kind or rec.type == "all" then out[#out + 1] = obj end
        end
        if #out > 0 then return out end
        if kind == "all" then return all end
        return nil -- старые grm_depot остаются фолбэком ядра
    end

    function JB.VehicleTokens(ent)
        if not IsValid(ent) then return{}end;local raw={ent:GetClass(),ent:GetNWString("GRMSpawnName",""),ent:GetNWString("SpawnName",""),ent:GetNWString("VehicleName",""),ent.VehicleName,ent.SpawnName,ent.VD_Class};local out={}
        for _,v in ipairs(raw)do if tostring(v or"")~=""then out[#out+1]=string.lower(tostring(v))end end;return out
    end
    function JB.AllowedVehicleList(workID)
        if workID=="taxi"then return JB.WorkConfig.taxiVehicles elseif workID=="garbage"then return JB.WorkConfig.garbageVehicles elseif workID=="courier"then return JB.WorkConfig.courierVehicles end;return{}
    end
    function JB.IsVehicleClassAllowed(ent,workID)
        if not IsValid(ent)then return false end;local tagged=tostring(ent:GetNWString("GRM_WorkVehicle",ent.GRMWorkVehicle or""));if tagged~=""then return tagged==tostring(workID)end;local list=JB.AllowedVehicleList(workID);if not istable(list)or#list==0 then return true end;local tokens=JB.VehicleTokens(ent)
        for _,allow in ipairs(list)do allow=string.lower(string.Trim(tostring(allow or"")));for _,token in ipairs(tokens)do if allow~=""and token==allow then return true end end end;return false
    end
    function JB.ResolveWorkVehicle(ply,workID)
        if not IsValid(ply)or not ply:InVehicle()then return nil,nil end;local seat=ply:GetVehicle();if not IsValid(seat)then return nil,nil end;local root=seat
        if workID=="garbage"and JB.ResolveGarbageVehicle then root=JB.ResolveGarbageVehicle(seat)or seat else for _=1,3 do local parent=root.GetParent and root:GetParent()or nil;if not IsValid(parent)or parent==root then break end;root=parent end end
        return IsValid(root)and root or seat,seat
    end
    function JB.IsWorkVehicleAllowed(ply,workID)
        local root,seat=JB.ResolveWorkVehicle(ply,workID);if not IsValid(seat)then return false end;local now=CurTime();local cache=ply._grmWorkVehicleCache
        if cache and cache.seat==seat and cache.root==root and cache.workID==workID and cache.untilAt>now then return cache.allowed end
        local seatDriver=seat.GetDriver and seat:GetDriver()or nil;local rootDriver=IsValid(root)and root.GetDriver and root:GetDriver()or nil;local driving=(seatDriver==ply)or(rootDriver==ply)
        if not driving then ply._grmWorkVehicleCache={seat=seat,root=root,workID=workID,untilAt=now+.5,allowed=false};return false end
        local allowed=JB.IsVehicleClassAllowed(root,workID)or(root~=seat and JB.IsVehicleClassAllowed(seat,workID))
        ply._grmWorkVehicleCache={seat=seat,root=root,workID=workID,untilAt=now+.5,allowed=allowed};return allowed
    end
    function JB.GetVehicleCatalog()
        local source=GRM.VehicleDealer and GRM.VehicleDealer.AllVehicleClasses and GRM.VehicleDealer.AllVehicleClasses()or{};if#source==0 then for class,row in pairs(list.Get("Vehicles")or{})do source[#source+1]={class=class,name=row.Name or class,system="source"}end end
        table.sort(source,function(a,b)return tostring(a.name)<tostring(b.name)end);local out={};for i=1,math.min(600,#source)do local v=source[i];out[i]={class=tostring(v.class or""),name=tostring(v.name or v.class or""),system=tostring(v.system or"?")}end;return out
    end

    JB.TaxiFares = JB.TaxiFares or {}
    local function charKey(ply)
        return (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply)) or (ply:SteamID64() .. ":char1")
    end
    function JB.GetTaxiFare(ply, fallback)
        local fare = JB.TaxiFares[charKey(ply)] or JB.WorkConfig.taxiDefault or fallback
        return math.floor(clamp(fare, JB.WorkConfig.taxiMin, JB.WorkConfig.taxiMax))
    end
    function JB.ReserveSystemReward(ply, workID, reward)
        reward = math.max(0, math.floor(tonumber(reward) or 0))
        if not JB.WorkConfig.fundFromState then return true, 0 end
        local E = GRM.Economy
        local get = E and E.StateBudgetGet or GRM.StateBudgetGet
        local add = E and E.StateBudgetAdd
        if not isfunction(get) or not isfunction(add) then return true, 0 end
        if (tonumber(get()) or 0) < reward then return false, "Городская казна не может профинансировать эту работу." end
        add(-reward, "Биржа труда: резерв «" .. tostring(workID) .. "» для " .. ply:Nick())
        return true, reward
    end
    function JB.RefundSystemReward(amount, why)
        amount = math.max(0, math.floor(tonumber(amount) or 0))
        local E = GRM.Economy
        if amount > 0 and E and isfunction(E.StateBudgetAdd) then E.StateBudgetAdd(amount, "Биржа труда: возврат резерва (" .. tostring(why) .. ")") end
    end

    local function snapshot(ply)
        net.Start(NET_OPEN)
            net.WriteTable(JB.WorkConfig or defaults())
            net.WriteTable(JB.WorkPoints or {})
            net.WriteTable(POINT_TYPES)
            net.WriteTable(JB.GetVehicleCatalog())
        net.Send(ply)
    end
    local function openAdmin(ply)if not IsValid(ply)or not ply:IsSuperAdmin()then return end;snapshot(ply)end
    JB.OpenAdmin=openAdmin
    local function parseList(text)
        local out, seen = {}, {}
        for part in string.gmatch(tostring(text or "") .. ",", "(.-),") do
            part = string.lower(string.Trim(part))
            if part ~= "" and #part <= 80 and not seen[part] then seen[part] = true out[#out + 1] = part end
        end
        return out
    end
    net.Receive(NET_ACT, function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        if (ply._grmJobsAdminAt or 0) > CurTime() then return end
        ply._grmJobsAdminAt = CurTime() + 0.25
        local act = net.ReadString()
        if act == "save" then
            local t = net.ReadTable() or {}
            JB.WorkConfig.fundFromState = t.fundFromState ~= false
            JB.WorkConfig.taxiMin = math.floor(clamp(t.taxiMin, 0, 100000))
            JB.WorkConfig.taxiMax = math.floor(clamp(t.taxiMax, JB.WorkConfig.taxiMin, 100000))
            JB.WorkConfig.taxiDefault = math.floor(clamp(t.taxiDefault, JB.WorkConfig.taxiMin, JB.WorkConfig.taxiMax))
            JB.WorkConfig.garbageStops=math.floor(clamp(t.garbageStops,1,8));JB.WorkConfig.garbageCapacity=math.floor(clamp(t.garbageCapacity,1,32));JB.WorkConfig.garbageSearchTime=clamp(t.garbageSearchTime,.5,15);JB.WorkConfig.garbageBinCooldown=math.floor(clamp(t.garbageBinCooldown,10,1800));JB.WorkConfig.garbageBindRadius=math.floor(clamp(t.garbageBindRadius,100,2000));JB.WorkConfig.garbageDumpRadius=math.floor(clamp(t.garbageDumpRadius,150,1000));JB.WorkConfig.garbageUnloadTime=clamp(t.garbageUnloadTime,1,30)
            -- Кузов не меньше маршрута — иначе «собрать 3/3» недостижимо.
            if JB.WorkConfig.garbageCapacity < JB.WorkConfig.garbageStops then
                JB.WorkConfig.garbageCapacity = JB.WorkConfig.garbageStops
            end
            JB.WorkConfig.taxiVehicles=parseList(t.taxiVehicles);JB.WorkConfig.garbageVehicles=parseList(t.garbageVehicles);JB.WorkConfig.courierVehicles=parseList(t.courierVehicles)
            JB.SaveWorkConfig("админ-настройки")
        elseif act == "add_point" then
            local typ = net.ReadString()
            local name = string.sub(string.Trim(net.ReadString()), 1, 64)
            if not POINT_TYPES[typ] then return end
            local tr=ply:GetEyeTrace();local pos=tr and tr.HitPos or ply:GetPos();JB.AddWorkPoint(typ,name,pos)
        elseif act == "remove_point" then
            local id = net.ReadString()
            for i = #JB.WorkPoints, 1, -1 do if JB.WorkPoints[i].id == id then table.remove(JB.WorkPoints, i) break end end
            JB.SaveWorkConfig("удалена точка");if JB.RefreshGarbageTopology then timer.Simple(0,function()JB.RefreshGarbageTopology("admin point removed")end)end
        end
        snapshot(ply)
    end)
    net.Receive(NET_TAXI_SET, function(_, ply)
        if not IsValid(ply) then return end
        local fare = math.floor(clamp(net.ReadUInt(20), JB.WorkConfig.taxiMin, JB.WorkConfig.taxiMax))
        JB.TaxiFares[charKey(ply)] = fare
        ply:ChatPrint("[Такси] Такса установлена: " .. tostring(fare) .. ". Она применится к следующему заказу.")
    end)
    local function openTaxi(ply)
        if JB.OpenTaxiDriverMenu then JB.OpenTaxiDriverMenu(ply)return end
        net.Start(NET_TAXI)
            net.WriteUInt(JB.GetTaxiFare(ply, JB.WorkConfig.taxiDefault), 20)
            net.WriteUInt(JB.WorkConfig.taxiMin, 20)
            net.WriteUInt(JB.WorkConfig.taxiMax, 20)
            net.WriteTable(JB.WorkConfig.taxiVehicles)
        net.Send(ply)
    end
    local function chat(ply, text)
        local low = string.lower(string.Trim(text or ""))
        if low == "/jobs_admin" or low == "/jobadmin" then openAdmin(ply) return true end
        if low == "/taxi" or low == "/такси" then openTaxi(ply) return true end
        return false
    end
    hook.Add("PlayerSayTransform", "GRM_JobsV3_Transform", function(ply, data)
        if istable(data) and isstring(data[1]) and chat(ply, data[1]) then data[1] = "" data.SkipPlayerSay = true end
    end)
    hook.Add("PlayerSay", "GRM_JobsV3_Chat", function(ply, text) if chat(ply, text) then return "" end end)
    concommand.Add("grm_jobs_admin", openAdmin)
else
    surface.CreateFont("GRMJobsCfg_Title", { font = "Roboto", size = 22, weight = 800, extended = true })
    surface.CreateFont("GRMJobsCfg_Text", { font = "Roboto", size = 14, weight = 500, extended = true })
    local C = { bg = Color(8,14,23,248), panel = Color(16,27,42), text = Color(225,238,247), muted = Color(132,160,178), cyan = Color(48,204,255), green = Color(64,222,147), red = Color(244,78,96) }
    local function frame(title, w, h)
        local f = vgui.Create("DFrame") f:SetSize(w,h) f:Center() f:MakePopup() f:SetTitle("") f:ShowCloseButton(false)
        f.Paint=function(_,pw,ph) draw.RoundedBox(9,0,0,pw,ph,C.bg) draw.RoundedBoxEx(9,0,0,pw,52,Color(10,22,37),true,true,false,false) draw.SimpleText(title,"GRMJobsCfg_Title",16,26,C.text,TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER) end
        local x=vgui.Create("DButton",f) x:SetPos(w-42,10) x:SetSize(30,30) x:SetText("✕") x:SetTextColor(color_white) x.Paint=function(s,pw,ph) draw.RoundedBox(4,0,0,pw,ph,s:IsHovered() and C.red or Color(40,55,70)) end x.DoClick=function() f:Close() end
        return f
    end
    local function field(parent, label, value, y)
        local l=vgui.Create("DLabel",parent) l:SetPos(16,y) l:SetSize(250,20) l:SetText(label) l:SetTextColor(C.muted) l:SetFont("GRMJobsCfg_Text")
        local e=vgui.Create("DTextEntry",parent) e:SetPos(270,y-2) e:SetSize(380,24) e:SetValue(tostring(value or "")) return e
    end
    net.Receive(NET_OPEN, function()
        local cfg,points,types,vehicles=net.ReadTable()or{},net.ReadTable()or{},net.ReadTable()or{},net.ReadTable()or{}
        if IsValid(JB._adminFrame)then JB._adminFrame:Remove()end
        local f=frame("РАБОТЫ • ТОЧКИ, ТРАНСПОРТ И ПРАВИЛА",1100,760)JB._adminFrame=f;if GRM.UI and GRM.UI.Track then GRM.UI.Track("jobs.admin",f)end
        local sheet=vgui.Create("DPropertySheet",f)sheet:SetPos(12,60)sheet:SetSize(1076,688)
        local settings=vgui.Create("DPanel",sheet) settings.Paint=function(_,w,h) draw.RoundedBox(6,0,0,w,h,C.panel) end
        local min=field(settings,"Минимальная такса",cfg.taxiMin,20);local max=field(settings,"Максимальная такса",cfg.taxiMax,56);local def=field(settings,"Такса по умолчанию",cfg.taxiDefault,92)
        local tv=field(settings,"Разрешённый транспорт такси",table.concat(cfg.taxiVehicles or{},", "),128);local gv=field(settings,"Разрешённый транспорт мусоровоза",table.concat(cfg.garbageVehicles or{},", "),164);local cv=field(settings,"Разрешённый транспорт доставки",table.concat(cfg.courierVehicles or{},", "),200)
        local gs=field(settings,"Контейнеров в маршруте",cfg.garbageStops,236);local cap=field(settings,"Вместимость мусоровоза (коробок)",cfg.garbageCapacity,272);local searchTime=field(settings,"Время поиска в мусорке, сек",cfg.garbageSearchTime,308);local cooldown=field(settings,"Восстановление мусорки, сек",cfg.garbageBinCooldown,344);local bindRadius=field(settings,"Радиус связи точки с мусоркой",cfg.garbageBindRadius,380);local dumpRadius=field(settings,"Радиус зоны выгрузки",cfg.garbageDumpRadius,416);local unloadTime=field(settings,"Время выгрузки на свалке, сек",cfg.garbageUnloadTime,452)
        local fund=vgui.Create("DCheckBoxLabel",settings)fund:SetPos(16,490)fund:SetSize(600,28)fund:SetText("Финансировать системные работы из городской казны")fund:SetTextColor(C.text)fund:SetValue(cfg.fundFromState and 1 or 0)
        local save=vgui.Create("DButton",settings)save:SetPos(16,536)save:SetSize(760,40)save:SetText("СОХРАНИТЬ ВСЕ НАСТРОЙКИ")save:SetTextColor(color_white)save.Paint=function(s,w,h)draw.RoundedBox(5,0,0,w,h,s:IsHovered()and Color(80,235,165)or C.green)end
        save.DoClick=function()net.Start(NET_ACT)net.WriteString("save")net.WriteTable({taxiMin=tonumber(min:GetValue()),taxiMax=tonumber(max:GetValue()),taxiDefault=tonumber(def:GetValue()),taxiVehicles=tv:GetValue(),garbageVehicles=gv:GetValue(),courierVehicles=cv:GetValue(),garbageStops=tonumber(gs:GetValue()),garbageCapacity=tonumber(cap:GetValue()),garbageSearchTime=tonumber(searchTime:GetValue()),garbageBinCooldown=tonumber(cooldown:GetValue()),garbageBindRadius=tonumber(bindRadius:GetValue()),garbageDumpRadius=tonumber(dumpRadius:GetValue()),garbageUnloadTime=tonumber(unloadTime:GetValue()),fundFromState=fund:GetChecked()})net.SendToServer()end
        sheet:AddSheet("Настройки",settings,"icon16/cog.png")
        local transport=vgui.Create("DPanel",sheet);transport.Paint=function(_,w,h)draw.RoundedBox(6,0,0,w,h,C.panel)end
        local vsearch=vgui.Create("DTextEntry",transport);vsearch:SetPos(16,16);vsearch:SetSize(620,30);vsearch:SetPlaceholderText("Поиск класса / SpawnName / названия транспорта")
        local vlist=vgui.Create("DListView",transport);vlist:SetPos(16,56);vlist:SetSize(760,560);vlist:AddColumn("Название");vlist:AddColumn("Class / SpawnName");vlist:AddColumn("Система");vlist:AddColumn("Разрешён для")
        local selectedClass
        local function values(entry)local set={};for part in(tostring(entry:GetValue()or"")..","):gmatch("(.-),")do part=string.lower(string.Trim(part));if part~=""then set[part]=true end end;return set end
        local function writeValues(entry,set)local arr={};for token in pairs(set)do arr[#arr+1]=token end;table.sort(arr);entry:SetValue(table.concat(arr,", "))end
        local function status(class)local t,g,c=values(tv),values(gv),values(cv);local out={};if t[class]then out[#out+1]="ТАКСИ"end;if g[class]then out[#out+1]="МУСОР"end;if c[class]then out[#out+1]="ДОСТАВКА"end;return#out>0 and table.concat(out," • ")or"—"end
        local function rebuildVehicles()vlist:Clear();local q=string.lower(string.Trim(vsearch:GetValue()or""));for _,v in ipairs(vehicles)do local class=string.lower(tostring(v.class or""));local hay=string.lower(tostring(v.name or"").." "..class.." "..tostring(v.system or""));if q==""or hay:find(q,1,true)then local line=vlist:AddLine(v.name or class,class,v.system or"?",status(class));line.VehicleClass=class end end end
        vlist.OnRowSelected=function(_,_,line)selectedClass=line.VehicleClass end;vsearch.OnChange=rebuildVehicles
        local function assign(entry,on)local class=selectedClass;if not class or class==""then return end;local set=values(entry);set[class]=on and true or nil;writeValues(entry,set);rebuildVehicles()end
        local taxiAdd=vgui.Create("DButton",transport);taxiAdd:SetPos(800,70);taxiAdd:SetSize(240,36);taxiAdd:SetText("Разрешить для ТАКСИ");taxiAdd.DoClick=function()assign(tv,true)end
        local garbageAdd=vgui.Create("DButton",transport);garbageAdd:SetPos(800,116);garbageAdd:SetSize(240,36);garbageAdd:SetText("Разрешить для МУСОРОВОЗА");garbageAdd.DoClick=function()assign(gv,true)end
        local courierAdd=vgui.Create("DButton",transport);courierAdd:SetPos(800,162);courierAdd:SetSize(240,36);courierAdd:SetText("Разрешить для ДОСТАВКИ");courierAdd.DoClick=function()assign(cv,true)end
        local removeAll=vgui.Create("DButton",transport);removeAll:SetPos(800,220);removeAll:SetSize(240,36);removeAll:SetText("Убрать из всех работ");removeAll.DoClick=function()assign(tv,false);assign(gv,false);assign(cv,false)end
        local manual=vgui.Create("DTextEntry",transport);manual:SetPos(800,290);manual:SetSize(240,30);manual:SetPlaceholderText("Ручной Class / SpawnName")
        local manualPick=vgui.Create("DButton",transport);manualPick:SetPos(800,330);manualPick:SetSize(240,32);manualPick:SetText("Выбрать ручное значение");manualPick.DoClick=function()selectedClass=string.lower(string.Trim(manual:GetValue()or""))end
        local hint=vgui.Create("DLabel",transport);hint:SetPos(800,390);hint:SetSize(240,160);hint:SetWrap(true);hint:SetTextColor(C.muted);hint:SetText("Выберите транспорт слева и назначьте работе. Пустой список у работы означает: разрешён любой транспорт. После изменений нажмите «Сохранить все настройки» во вкладке Настройки.")
        rebuildVehicles();sheet:AddSheet("Транспорт работ",transport,"icon16/lorry.png")
        local pp=vgui.Create("DPanel",sheet) pp.Paint=function(_,w,h) draw.RoundedBox(6,0,0,w,h,C.panel) end
        local typ=vgui.Create("DComboBox",pp) typ:SetPos(16,16) typ:SetSize(220,28) typ:SetValue("Тип точки") for id,n in pairs(types) do typ:AddChoice(n,id) end
        local name=vgui.Create("DTextEntry",pp) name:SetPos(246,16) name:SetSize(300,28) name:SetPlaceholderText("Название точки")
        local add=vgui.Create("DButton",pp) add:SetPos(556,16) add:SetSize(190,28) add:SetText("Добавить по прицелу") add.DoClick=function() local _,id=typ:GetSelected() if not id then return end net.Start(NET_ACT) net.WriteString("add_point") net.WriteString(id) net.WriteString(name:GetValue()) net.SendToServer() end
        local state=vgui.Create("DButton",pp)state:SetPos(756,16)state:SetSize(280,28)state:SetText("Состояние мусорок и свалки")state.DoClick=function()RunConsoleCommand("grm_garbage_status")end
        local sc=vgui.Create("DScrollPanel",pp) sc:SetPos(16,56) sc:SetSize(1020,540)
        for _,r in ipairs(points) do local row=vgui.Create("DPanel",sc) row:Dock(TOP) row:DockMargin(0,0,0,6) row:SetTall(44) row.Paint=function(_,w,h) draw.RoundedBox(4,0,0,w,h,Color(22,37,56)) draw.SimpleText((types[r.type] or r.type).." • "..r.name,"GRMJobsCfg_Text",12,12,C.text) end local del=vgui.Create("DButton",row) del:Dock(RIGHT) del:SetWide(100) del:SetText("Удалить") del.DoClick=function() net.Start(NET_ACT) net.WriteString("remove_point") net.WriteString(r.id) net.SendToServer() end sc:AddItem(row) end
        sheet:AddSheet("Точки и маршруты",pp,"icon16/map.png")
    end)
    net.Receive(NET_TAXI, function()
        local cur,min,max,vehicles=net.ReadUInt(20),net.ReadUInt(20),net.ReadUInt(20),net.ReadTable() or {}
        local f=frame("ТАКСИ • ТАРИФ",560,280)
        local s=vgui.Create("DNumSlider",f) s:SetPos(18,78) s:SetSize(520,44) s:SetText("Такса за поездку") s:SetMin(min) s:SetMax(max) s:SetDecimals(0) s:SetValue(cur)
        local l=vgui.Create("DLabel",f) l:SetPos(18,130) l:SetSize(520,48) l:SetText("Разрешённый транспорт: "..(#vehicles>0 and table.concat(vehicles,", ") or "любой автомобиль")) l:SetWrap(true) l:SetTextColor(C.muted)
        local b=vgui.Create("DButton",f) b:SetPos(18,198) b:SetSize(520,40) b:SetText("УСТАНОВИТЬ ТАКСУ") b:SetTextColor(color_white) b.Paint=function(_,w,h) draw.RoundedBox(5,0,0,w,h,C.green) end b.DoClick=function() net.Start(NET_TAXI_SET) net.WriteUInt(math.floor(s:GetValue()),20) net.SendToServer() f:Close() end
    end)
end
