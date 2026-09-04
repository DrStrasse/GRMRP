--[[--------------------------------------------------------------------
    sim_garage_module — заказ владельца 19.08: полноценный модуль гаражей и
    его стыковка с дилером (инструмент зон, места спавна, стойка вызова,
    выдача из гаража, приписка купленного транспорта).

    Проверяет состав модуля и порядок загрузки; живая механика проверяется
    отдельно в sim_garage_runtime.lua.

    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_garage_module.lua
----------------------------------------------------------------------]]
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end
local function maybe(p) local f = io.open(p, "rb") if not f then return "" end local s = f:read("*a") f:close() return s end

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end
local function has(s, n) return s:find(n, 1, true) ~= nil end

local core = read("lua/autorun/sh_grm_garage.lua")
local ui   = read("lua/autorun/client/cl_grm_garage_ui.lua")
local tool = read("lua/weapons/gmod_tool/stools/grm_transport.lua")
local entS = read("lua/entities/grm_garage_terminal/shared.lua")
local entI = read("lua/entities/grm_garage_terminal/init.lua")
local entC = read("lua/entities/grm_garage_terminal/cl_init.lua")
local vd   = read("lua/autorun/sh_grm_vehicle_dealer.lua")
local vdcl = read("lua/entities/sent_vehicle_dealer/cl_init.lua")
local qm   = read("lua/autorun/sh_grm_qmenu.lua")
local hubS = read("lua/autorun/server/sv_grm_persistence_hub.lua")
local hubC = read("lua/autorun/client/cl_grm_persistence_hub.lua")
local f4   = maybe("lua/autorun/sh_grm_f4menu.lua")

print("\n=== 1. СОСТАВ МОДУЛЯ ===")
ok(has(core, 'G.Version = "1.0.0"'), "ядро гаражей есть и версионировано")
ok(has(core, "G.Kinds = {") and has(core, "public") and has(core, "faction") and has(core, "private"),
    "три типа гаража: городской, ведомственный, личный")
ok(has(tool, "TOOL.Category = \"GRM\""), "тул разметки существует")
ok(has(entS, "grm_garage_terminal") or has(entS, "Стойка гаража GRM"), "энтити стойки существует")
ok(has(ui, "function G.OpenWindow"), "клиентское окно гаража существует")

print("\n=== 2. ЗОНЫ И МЕСТА ===")
ok(has(core, "function G.Create"), "создание зоны гаража")
ok(has(core, "G.MinZone"), "минимальный размер зоны задан")
ok(has(core, "function G.AddSlot") and has(core, "function G.RemoveNearestSlot"), "места стоянки добавляются и удаляются")
ok(has(core, "if not G.PosInZone(rec, pos) then return false, \"Место должно быть внутри зоны гаража\""),
    "место обязано быть внутри зоны")
ok(has(core, "function G.FreeSlot"), "поиск свободного места с проверкой габаритов")
ok(has(core, "function G.SlotState"), "занятость мест считается для интерфейса")
ok(has(tool, 'key = "zone"') and has(tool, 'key = "slot"') and has(tool, 'key = "terminal"'),
    "у тула есть режимы: зона, место выдачи, стойка")
ok(has(tool, 'dir:AddChoice("По взгляду при установке", "look")'), "направление выдачи выбирается")

print("\n=== 3. СТОЙКА И ВЫЗОВ МЕНЮ ===")
ok(has(core, "function G.AddTerminal") and has(core, "function G.SpawnTerminals"), "стойки хранятся в записи гаража и поднимаются сами")
ok(has(entI, "G.Push(ply, rec)"), "E на стойке открывает меню гаража")
ok(has(entI, "function ENT:PhysgunPickup() return false end"), "стойку нельзя утащить физганом")
ok(has(core, 'hook.Add("PlayerSay", "GRM_Garage_Chat"') and has(core, 'hook.Add("PlayerSay", "GRM_Garage_ChatEC"'),
    "/garage — оба входа боевые (PlayerSay), имена в реестре библиотеки")
ok(has(core, "if not G.GarageAt(ply) then return false end"),
    "вне гаража команда отдаётся дилеру — конфликта /garage нет")
ok(has(core, "function G.GarageAt"), "гараж определяется по зоне или по стойке рядом")

print("\n=== 4. ВЫДАЧА, УБОРКА, ДОСТУП ===")
ok(has(core, "function G.Retrieve") and has(core, "function G.Store") and has(core, "function G.SetHome"),
    "выдача, уборка и приписка транспорта")
ok(has(core, "function G.CanUse"), "правила доступа к гаражу")
ok(has(core, "if fee > 0 and GRM.TakeMoney"), "плата за выезд списывается")
ok(has(core, 'if home ~= "" and home ~= garage.id then'), "чужой гараж не выдаёт машину")
ok(has(ui, 'G.SendAction(v.onMap and "store" or "retrieve", v.id)'), "кнопка меняет смысл: выдать / убрать")
ok(has(ui, "МЕСТА СТОЯНКИ"), "в окне видно состояние мест")

print("\n=== 5. СТЫКОВКА С ДИЛЕРОМ ===")
ok(has(vd, "function VD.IssueRecord") and has(vd, "function VD.StoreRecord"),
    "выдача/уборка живут в одном слое дилера — гараж их переиспользует")
ok(has(vd, "function VD.Spawn(class,dealer,ply,place)"), "спавн умеет работать по готовому месту гаража")
ok(has(vd, 'elseif op=="store"then local id=net.ReadString();local ok,msg=VD.StoreRecord'),
    "операции дилера переведены на общий слой (без копипасты)")
ok(has(core, 'hook.Add("GRM_VehicleDealerSpawned", "GRM_Garage_AssignHome"'),
    "покупка приписывается к гаражу хуком — дилер про гаражи не знает")
ok(has(core, "function G.HomeGarageFor"), "выбор домашнего гаража: привязанный дилер → личный → ближайший")
ok(has(core, "function G.LinkDealer") and has(tool, "g.LinkDealer(rec.id"), "дилер привязывается к гаражу тулом")
ok(has(core, 'CreateConVar("grm_garage_strict"'), "строгий режим выдачи только в гараже — конваром")
ok(has(vd, "GRM.Garage.DealerIssueBlocked"), "дилер спрашивает гараж, можно ли выдавать здесь")
ok(has(vdcl, 'Гараж: '), "в меню дилера видно, к какому гаражу приписана машина")

print("\n=== 6. ПОРЯДОК ЗАГРУЗКИ И ХРАНЕНИЕ ===")
ok(has(core, 'GRM.Boot.OnMapStart("GRM_Garage_Load", "normal"'), "данные грузятся через планировщик (tier normal)")
ok(has(core, 'GRM.Boot.OnMapStart("GRM_Garage_Terminals", "late"'), "стойки поднимаются отдельной задачей (tier late)")
ok(has(core, 'hook.Add("PostCleanupMap", "GRM_Garage_Cleanup"'), "после очистки карты стойки возвращаются")
ok(has(core, "grm_garage/") and has(core, "string.lower(game.GetMap()"), "файл гаражей — по карте")
ok(has(core, 'print("[GRM Garage] SAVE read-back ПУСТ'), "запись проверяется чтением обратно (стандарт GRM)")
ok(has(core, "GRM.Net.Guard(ply, \"garage.action\""), "приём действий под сетевым guard")
ok(has(core, "GRM.Net.Guard(ply, \"garage.admin\""), "админ-канал тоже под guard")
ok(has(hubS, "garages = { save = function()") and has(hubS, '"garages", "quests"'), "гаражи в хабе сохранений")
ok(has(hubC, '{ id = "garages", name = "Гаражи карты"'), "раздел гаражей виден в /grm_persistence")
ok(has(qm, '{ id = "grm_transport"'), "единый тул зарегистрирован в Q-меню")
ok(f4 == "" or has(f4, "Гараж (/garage"), "подсказка по гаражу есть в F4")

print("\n=== 7. ВОРОТА ГАРАЖА (ДВЕРИ) ===")
local prop = read("lua/autorun/sh_grm_property.lua")
ok(has(core, "function G.LinkDoor"), "двери привязываются к гаражу")
ok(has(core, "function G.ReindexDoors") and has(core, "function G.GarageByDoorID"), "индекс «дверь → гараж»")
ok(has(core, 'return false, ("Эта дверь уже привязана к гаражу'), "одна дверь принадлежит одному гаражу")
ok(has(core, 'hook.Add("GRM_DoorAccessOverride", "GRM_Garage_Doors"'), "ворота слушают владельца гаража")
ok(has(core, "if GRM.Property and GRM.Property.GetByDoorID and GRM.Property.GetByDoorID(id) then return end"),
    "двери объекта недвижимости остаются её правилам — приоритет не спорит")
ok(has(core, "function G.ApplyDoorState"), "ворота запираются вместе со сменой типа гаража")
ok(has(core, "function G.ToggleDoors") and has(ui, 'G.SendAction("doors", "")'), "в меню есть кнопка открыть/закрыть ворота")
ok(has(tool, 'key = "door"') and has(tool, "g.LinkDoor(rec.id, doorID)"), "режим привязки ворот в туле")

print("\n=== 8. ГАРАЖ ВМЕСТЕ С ДОМОМ ===")
ok(has(core, "function G.LinkProperty"), "гараж привязывается к объекту недвижимости")
ok(has(core, "function G.SyncWithProperty"), "владелец дома становится владельцем гаража")
ok(has(core, "rec.baseKind"), "исходный тип гаража запоминается и возвращается")
ok(has(core, 'hook.Add("GRM_PropertyOwnerChanged", "GRM_Garage_FollowProperty"'), "гараж следит за сменой владельца дома")
ok(select(2, prop:gsub('hook%.Run%("GRM_PropertyOwnerChanged"', "")) >= 5,
    "недвижимость сообщает о покупке, аренде, освобождении, выселении и истечении аренды")
ok(has(tool, "GRM.Property.GetByDoor"), "ПКМ по двери дома привязывает гараж к объекту")
ok(has(ui, "продаётся с объектом"), "в админ-списке видно, с каким домом продаётся гараж")

print("\n=== 9. УДАЛЕНИЕ СТОЙКИ ===")
local ent = read("lua/entities/grm_garage_terminal/init.lua")
ok(has(ent, 'return tostring(mode or "") == "grm_garage"'),
    "стойка пускает свой тул: глухое CanTool=false блокировало её же удаление по R")
ok(not has(ent, "function ENT:CanTool() return false end"), "старый глухой запрет убран")
ok(has(ent, "function ENT:PhysgunPickup() return false end"), "физганом стойку по-прежнему не утащить")
ok(has(core, "function G.RemoveTerminalByID"), "есть удаление стойки по её id")
ok(has(tool, 'ent:GetClass() == "grm_garage_terminal" and g.RemoveTerminalByID'),
    "R по стойке удаляет именно её, а не ближайшую")
ok(has(tool, "Стойка без записи удалена с карты"), "осиротевшая стойка тоже убирается")

print("\n=== 10. ВЫБОР ГАРАЖА ПРИ ПОКУПКЕ ===")
local vd = read("lua/autorun/sh_grm_vehicle_dealer.lua")
local vdcl = read("lua/entities/sent_vehicle_dealer/cl_init.lua")
ok(has(core, "function G.ChoicesFor"), "гараж отдаёт список доступных вариантов")
ok(has(core, "function G.ValidateChoice"), "выбор игрока проверяется (доступ, места)")
ok(has(core, "local wanted = tostring(record.requestedGarage or \"\")"), "хук уважает выбор игрока")
ok(has(core, "home = home or G.HomeGarageFor(ply, dealer)"), "если выбор не подошёл — автоподбор, покупка не срывается")
ok(has(vd, 'local wantGarage=net.ReadString()or""'), "дилер принимает выбранный гараж в покупке")
ok(has(vd, 'record.requestedGarage=tostring(wantGarage or"")'), "выбор кладётся в запись для модуля гаражей")
ok(has(vd, "GRM.Garage.ChoicesFor)and GRM.Garage.ChoicesFor(ply,dealer)"), "список гаражей уходит в окно дилера")
ok(has(vdcl, "Гараж: автоматически"), "в окне есть выбор «автоматически»")
ok(has(vdcl, 'send(dealer, "buy", v.class, targetGarage, "store")'), "покупка отправляет выбранный гараж приписки")
ok(has(vdcl, "мест %d/%d"), "видно свободные места в каждом гараже")

print("\n=== ЗАНЯТОСТЬ МЕСТА СЧИТАЕТСЯ ПО ГАБАРИТАМ ===")
do
    local src = (function()
        local f = io.open("lua/autorun/sh_grm_garage.lua", "rb")
        local t = f:read("*a") f:close() return t
    end)()
    local function has(n) return src:find(n, 1, true) ~= nil end
    ok(has("function G.BoxesOverlap(aMin, aMax, bMin, bMax, margin)"),
       "чистая проверка пересечения габаритов объявлена")
    ok(has("function G.SlotBounds(slot)") and has("G.SlotBox"),
       "у места есть свой габарит, а не только точка")
    ok(has("local mn, mx = ent:WorldSpaceAABB()") and has("G.BoxesOverlap(smin, smax"),
       "занятость решается пересечением кузова с местом, а не расстоянием до origin")
    ok(has("G.SlotRadius + 320"),
       "кандидаты ищутся широким радиусом: origin машины может быть далеко от места")
end

print(("\nGARAGE MODULE: %d/%d, провалов: %d"):format(total - fails, total, fails))
if fails > 0 then os.exit(1) end
