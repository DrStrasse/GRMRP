-- Contracts for GRM Vehicle Dealer & Garage v3.
local function read(p)local f=assert(io.open(p,"rb"));local s=f:read("*a");f:close();return s end
local core,ent,cl,tool,q,doors,perm = read("lua/autorun/sh_grm_vehicle_dealer.lua"),read("lua/entities/sent_vehicle_dealer/init.lua"),read("lua/entities/sent_vehicle_dealer/cl_init.lua"),read("lua/weapons/gmod_tool/stools/grm_transport.lua"),read("lua/autorun/sh_grm_qmenu.lua"),read("lua/autorun/sh_grm_doors.lua"),read("lua/autorun/sh_grm_perm_entities.lua")
local checks,failed=0,0;local function has(s,n)return s:find(n,1,true)~=nil end;local function ok(v,n)checks=checks+1;if v then print("  ok "..checks..". "..n)else failed=failed+1;print("  FAIL "..checks..". "..n)end end
ok(has(core,'VD.Version="3.8.0"'),"dealer v3.8: гаражи, лимит по классу, режимы выдачи, выкуп государством")
ok(has(core,"VD.GarageFile")and has(core,"CharacterKey"),"garage persists per CharacterKey")
ok(has(core,"function VD.VehicleInfo")and has(core,'list.Get("simfphys_vehicles")')and has(core,'list.Get("LVS_Vehicles")'),"Source simfphys and LVS registries")
ok(has(core,"SpawnVehicleSimple")and has(core,"simfphys fallback")and has(core,"LVS SpawnFunction")and has(core,"scripted entity"),"legacy-compatible multi-stage vehicle spawn fallbacks")
    local simpleAt = core:find('attempt("simfphys.SpawnVehicleSimple"', 1, true)
    local guardedAt = core:find('attempt("simfphys.SpawnVehicle"', 1, true)
    ok(simpleAt and guardedAt and simpleAt < guardedAt,
        "simfphys SpawnVehicleSimple вызывается раньше конфликтного SpawnVehicle")
ok(has(core,"function VD.FindDeliveryPosition")and has(core,"function VD.FindSpawnPoint")and has(core,"TraceHull")and has(core,"Площадка выдачи занята"),"delivery point/zone searches safe unoccupied points")
ok(has(core,"hasSpawnZone")and has(core,"spawnZoneMin")and has(core,"spawnZoneMax")and has(core,"SetSpawnPos(hasPad and((padMin+padMax)*.5)or legacyPoint)"),"zone persisted; legacy point stays a point (v3.1.2)")
ok(has(tool,"GRM_Transport_ToolReq")and has(tool,"DrawWireframeBox")and has(tool,"spawnPos"),"transport tool requests and draws garages, slots and dealer points")
ok(has(cl,"self:GetDealerName()")and has(cl,"OBBMaxs().z")and has(cl,"ТРАНСПОРТНЫЙ ЦЕНТР"),"configured dealer name is rendered above NPC")
ok(has(core,'op=="buy"')and has(core,'op=="retrieve"')and has(core,'op=="store"')and has(core,'op=="sell"'),"buy retrieve store and sell operations")
ok(has(core,"saveGarage()")and has(core,"PlayerDisconnected"),"garage saves and stores vehicles on disconnect")
ok(has(core,"function _G.VD_RemoveDealerVehicle"),"context-menu compatibility stores vehicles in garage")
ok(has(core,"GRM_VD_GarageCommand")and has(core,'"/garage"'),"garage chat command opens nearest dealer")
ok(has(core,"function VD.SaveDealer")and has(core,"function VD.LoadDealers")and has(core,"migrateLegacyDealers"),"dealer persistence and legacy migration")
ok(has(ent,"GRM.VehicleDealer.Push")and #ent<2500,"dealer entity is thin and authoritative")
ok(has(cl,"GRM / ТРАНСПОРТНЫЙ ЦЕНТР")and has(cl,"Гараж")and has(cl,"GRM_VD_Result"),"GRM-styled dealer and garage UI")
ok(has(cl,"GRM_VD_AdminOpen")and has(cl,"СОХРАНИТЬ ДИЛЕРА, АССОРТИМЕНТ И ГАРАЖ"),"GRM admin assortment UI")
ok(has(tool,"GRM: транспорт")and has(tool,"SaveDealer"),"unified transport tool auto-saves dealers")
ok(has(q,'id = "grm_transport"')and not has(q,'id = "vehicle_dealer_tool"')and not has(q,'id = "grm_garage",')and has(q,'id = "grm_door_admin"'),"Q-menu exposes ONE transport tool, old ones removed")
ok(not has(perm,"sent_vehicle_dealer = true"),"generic perm cannot duplicate dedicated dealers")
ok(has(doors,"GRM_Doors_SuppressDuplicateHUD"),"door HUD duplicate suppression is persistent")
ok(has(core,"vehicle_dealers")or has(read("lua/autorun/server/sv_grm_persistence_hub.lua"),"vehicle_dealers"),"unified persistence includes dealers")
ok(has(core,"function VD.SetSpawnPoint")and has(core,"function VD.ClearSpawnPoint"),"spawn point API (set/clear)")
ok(has(core,"Точка выдачи занята")and has(core,"dealer:GetSpawnAngle()"),"spawn point fallback and occupied message")
ok(has(tool,"grm_transport_direction")and has(tool,'key = "dealerpoint"')and has(tool,"SetSpawnPoint"),"direction selector and dealer point placement in tool")
ok(has(tool,"ТОЧКА ВЫДАЧИ ДИЛЕРА")and has(tool,"высота %d"),"point marker and lift label drawn")
ok(has(tool,"По взгляду при установке")and has(tool,"Влево от дилера")and has(tool,"Вправо от дилера"),"direction choices: look/left/right")
ok(has(core,"ent:SetPos(base+Vector(0,0,lift))")and has(core,"b2+Vector(0,0,lift)"),"lift re-applied after drop and after async simfphys settle")
-- Т-поза дилера после каждой правки настроек (заказ владельца 19.08).
local shared=read("lua/entities/sent_vehicle_dealer/shared.lua")
local entInit=read("lua/entities/sent_vehicle_dealer/init.lua")
local animFix=read("lua/autorun/server/sv_grm_vehicle_dealer_anim_fix.lua")
ok(has(shared,"function ENT:ApplyIdleAnimation"),"idle-анимация ставится одной общей функцией")
ok(has(shared,"function ENT:ApplyDealerModel"),"смена модели идёт через ApplyDealerModel (модель + idle)")
ok(has(shared,'current ~= "reference"'),"сторож узнаёт Т-позу по последовательности reference")
ok(has(entInit,"self:ApplyIdleAnimation(true)"),"дилер встаёт в idle при создании")
ok(has(entInit,"function ENT:Think")and has(entInit,"self._grmIdleCheck"),"сторож анимации с троттлингом раз в 2 сек")
ok(has(core,"if ent.ApplyDealerModel then ent:ApplyDealerModel(model)"),"загрузка карты не оставляет дилера в Т-позе")
ok(has(core,"if dealer.ApplyDealerModel then dealer:ApplyDealerModel(model)"),"сохранение настроек возвращает анимацию")
ok(has(core,"elseif dealer.ApplyIdleAnimation then dealer:ApplyIdleAnimation(true)end"),
    "даже при пустой/неверной модели анимация чинится")
ok(has(animFix,"if ent.ApplyIdleAnimation then ent:ApplyIdleAnimation(true) return end"),
    "старый патч анимации делегирует энтити, второй копии списка нет")

-- ── 22.08: служебная техника поштучно и класс для нескольких организаций ──
do
    local core = (function()
        local f = io.open("lua/autorun/sh_grm_vehicle_dealer.lua", "rb")
        local t = f:read("*a") f:close() return t
    end)()
    local cl = (function()
        local f = io.open("lua/entities/sent_vehicle_dealer/cl_init.lua", "rb")
        local t = f:read("*a") f:close() return t
    end)()
    local function hasT(src, needle) return src:find(needle, 1, true) ~= nil end

    ok(hasT(core, "local fleetRows={}") and hasT(core, "FL.UnitsOf(faction)"),
        "дилер отдаёт единицы служебного парка поштучно")
    ok(hasT(core, 'net.WriteTable(fleetRows)'), "список единиц уходит клиенту")
    ok(hasT(cl, "local function fleetCell(parent, v)") and hasT(cl, 'showRows(fleetUnits, "fleet")')
        and hasT(cl, "VC.TableRow(parent, {"),
        "у каждой служебной машины своя строка таблицы и свой раздел")
    ok(hasT(core, 'elseif op=="fleet_issue"or op=="fleet_store"then'),
        "выдача и возврат идут по конкретной единице через единый диспетчер")

    ok(hasT(core, "local function findEntry(dealer,class,ply)"),
        "позиция ассортимента ищется с учётом игрока: один класс может стоять несколько раз")
    ok(hasT(cl, "local function countClass(class)") and hasT(cl, "b:SetEnabled(true)"),
        "класс не исчезает из настроек после назначения организации")
    ok(not hasT(cl, "local function exists(class)"), "старая проверка «уже добавлен» убрана")

    local cells = (function()
        local f = io.open("lua/autorun/client/cl_grm_vehicle_cells.lua", "rb")
        local t = f:read("*a") f:close() return t
    end)()
    ok(hasT(cells, "if not info.noPlate then"), "у позиции каталога нет таблички «БЕЗ НОМЕРА»")
    ok(hasT(cl, "noPlate = true"), "каталог помечает свои ячейки как классы, а не машины")
end

-- ── 22.08: единый механизм закупки дилер ↔ автопарк, окно без мерцания ──
do
    local core = (function()
        local f = io.open("lua/autorun/sh_grm_vehicle_dealer.lua", "rb")
        local t = f:read("*a") f:close() return t
    end)()
    local cl = (function()
        local f = io.open("lua/entities/sent_vehicle_dealer/cl_init.lua", "rb")
        local t = f:read("*a") f:close() return t
    end)()
    local fleet = (function()
        local f = io.open("lua/autorun/sh_grm_fleet.lua", "rb")
        local t = f:read("*a") f:close() return t
    end)()
    local function hasT(src, needle) return src:find(needle, 1, true) ~= nil end

    ok(hasT(fleet, "function FL.DealerMarket()"),
        "дилерский ассортимент собирается отдельным списком")
    ok(hasT(fleet, "function FL.DealerEntryID(dealer, entry)"),
        "у дилерской позиции устойчивый идентификатор")
    ok(hasT(fleet, '("dealer:%s:%s:%s"):format(class, faction, tostring(crc))'),
        "id включает цену/категорию — у разных ценников разные позиции")
    ok(hasT(core, "GRM.Fleet.FindMarketForDealer") and hasT(core, "marketReady=inMarket"),
        "служебная карточка дилера получает id только вручную добавленной позиции рынка")
    ok(hasT(core, 'local marketID=net.ReadString()or""'),
        "сервер закупки получает точный id с карточки")
    ok(hasT(core, "local exact=FL.Entry and FL.Entry(marketID) or nil")
        and hasT(core, "Позиция дилера изменилась"),
        "сервер повторно получает именно текущую позицию дилера")
    ok(hasT(fleet, "function FL.FindMarketForDealer(entry)")
        and not hasT(fleet, "for id, entry in pairs(FL.DealerMarket()) do"),
        "дилер сопоставляется только с вручную созданной позицией рынка")
    ok(hasT(core, 'elseif op=="fleet_buy"then'),
        "у дилера есть операция закупки в автопарк")
    ok(hasT(core, "local made,err=FL.Buy(ply,pick.id,1,wantGarage)"),
        "закупка идёт через единый FL.Buy: бюджет, лимиты, гараж")
    ok(hasT(cl, "НЕТ В РЫНКЕ АВТОПАРКА") and hasT(cl, "marketReady == true"),
        "служебная карточка честно требует ручного добавления в рынок")
    ok(hasT(cl, 'send(dealer, "fleet_buy", v.class, targetGarage, tostring(v.marketID or ""))'),
        "кнопка шлёт закупку с выбранным гаражом и точным ID позиции")

    --[[ «Убрать в гараж» должно быть доступно и личной машине, и служебному
         фракционному авто: у дилера в разделе «На карте» активная техника
         автопарка теперь тоже видна и возвращается через fleet_store. ]]
    ok(hasT(core, 'local FL=GRM.Fleet') and hasT(core, "FL.Active and FL.Active[unit.id]"),
        "раздел «На карте» у дилера видит и активные единицы автопарка")
    ok(hasT(core, 'local faction=tostring(ply:GetNWString("GRM_Faction","")or"")'),
        "служебная техника берётся по организации игрока, а не только по выдававшему")
    ok(hasT(cl, 'v.fleet == true') and hasT(cl, 'or (isFleet and "fleet_store" or "remove")'),
        "у служебной техники кнопка «УБРАТЬ В ГАРАЖ» возвращает её через единый диспетчер")
    ok(hasT(cl, "Он вернётся в гараж организации."),
        "подтверждение объясняет: служебная машина вернётся в гараж организации")

    local plates = (function()
        local f = io.open("lua/autorun/sh_grm_plates.lua", "rb")
        local t = f:read("*a") f:close() return t
    end)()
    ok(hasT(plates, "local function snapshotSignature(data)") and hasT(plates, "if sig == PL._sig then return end"),
        "окно учёта не пересобирается, если данные не изменились")
    ok(hasT(plates, "if typingNow() then PL._sigPending = sig return end"),
        "пока игрок печатает, окно учёта не трогают")
    ok(hasT(fleet, "local function stateSignature(data)") and hasT(fleet, "if sig == FL._sig then return end"),
        "окно автопарка тоже перестраивается только по изменению")
    ok(hasT(fleet, "Поля формы уже живут в FL.Form") and hasT(fleet, "FL._sig, FL._sigPending = sig, nil"),
        "живой снимок пересобирается сразу, а поля формы переживают пересборку")
end

print(("VEHICLE DEALER V3: %d/%d failures=%d"):format(checks-failed,checks,failed));if failed>0 then os.exit(1)end
