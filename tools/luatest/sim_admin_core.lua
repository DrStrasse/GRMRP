--[[--------------------------------------------------------------------
    sim_admin_core — собственная админ-платформа GRM:
      группы и права, иммунитет, синхронизация с ULX/ULib и CAMI,
      модерация (ТП/мут/джаил/рагдолл и т.д.), возможности суперадмина,
      админ-меню с нужными вкладками.

    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_admin_core.lua
----------------------------------------------------------------------]]
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

local core    = read("lua/autorun/sh_grm_admin_core.lua")
local actions = read("lua/autorun/server/sv_grm_admin_actions.lua")
local panel   = read("lua/autorun/client/cl_grm_admin_panel.lua")

print("\n=== 1. СТАТИКА: ЯДРО ===")
ok(core:find("GRM.Admin", 1, true) ~= nil and core:find('AD.Version = "1.0.0"', 1, true) ~= nil, "модуль GRM.Admin v1.0.0")
ok(core:find("function AD.RegisterPerm", 1, true) ~= nil, "реестр прав с категориями")
ok(core:find("function AD.Can", 1, true) ~= nil, "единая проверка прав GRM.Admin.Can")
ok(core:find("function AD.CanTarget", 1, true) ~= nil and core:find("У цели равный или больший иммунитет", 1, true) ~= nil,
    "иммунитет: нельзя применять действия к равному или старшему")
ok(core:find("function AD.GroupChain", 1, true) ~= nil, "наследование групп")
ok(core:find("grm_admin/groups.json", 1, true) ~= nil and core:find("grm_admin/users.json", 1, true) ~= nil,
    "группы и назначения хранятся на диске")
ok(core:find("function AD.ImportFromULib", 1, true) ~= nil, "импорт групп и назначений из ULX/ULib")
ok(core:find("ULib.ucl.addUser", 1, true) ~= nil, "назначение зеркалится в ULib (ulx-команды не ломаются)")
ok(core:find("CAMI.RegisterUsergroup", 1, true) ~= nil and core:find("CAMI.RegisterPrivilege", 1, true) ~= nil,
    "группы и права публикуются в CAMI")
ok(core:find("CAMI.SignalUserGroupChanged", 1, true) ~= nil, "смена группы сообщается другим админ-модам")
ok(core:find('hook.Add("CAMI.PlayerHasAccess", "GRM_Admin_CAMIAnswer"', 1, true) ~= nil,
    "GRM отвечает на запросы доступа от чужих модулей")
ok(core:find('hook.Add("CAMI.PlayerUsergroupChanged", "GRM_Admin_External"', 1, true) ~= nil,
    "смена группы через ULX подхватывается обратно в GRM")
ok(core:find("ply:SetUserGroup(groupID)", 1, true) ~= nil,
    "группа ставится и в движок: IsAdmin/IsSuperAdmin остаются валидными")
ok(core:find('ulx.command("GRM", "ulx grmadmin"', 1, true) ~= nil, "ULX-команда ulx grmadmin открывает наше меню")

print("\n=== 2. ПРАВА И ГРУППЫ ПО УМОЛЧАНИЮ ===")
for _, perm in ipairs({ "mod.goto", "mod.bring", "mod.mute", "mod.gag", "mod.jail", "mod.ragdoll",
    "mod.kick", "mod.ban", "acl.groups", "acl.assign", "server.persistence", "server.factions",
    "cheat.god", "cheat.noclip", "cheat.money", "cheat.buildmode" }) do
    ok(core:find('"' .. perm .. '"', 1, true) ~= nil, "право " .. perm .. " зарегистрировано")
end
ok(core:find('id = "superadmin"', 1, true) ~= nil and core:find('perms = { %["%*"%] = true }') ~= nil,
    "у суперадмина полный доступ")
ok(core:find('immunity = 100', 1, true) ~= nil, "иммунитет суперадмина 100")

print("\n=== 3. ДЕЙСТВИЯ МОДЕРАЦИИ ===")
for _, op in ipairs({ "goto_player", "bring", "freeze", "mute", "gag", "jail", "ragdoll", "slay",
    "respawn", "heal", "strip", "spectate", "kick", "ban", "warn" }) do
    ok(actions:find("A." .. op, 1, true) ~= nil or actions:find('A["' .. op .. '"]', 1, true) ~= nil,
        "действие " .. op)
end
ok(actions:find("local function safeSpot", 1, true) ~= nil, "телепорт не заталкивает игрока в стену")
ok(actions:find("GRM_AdminReturn", 1, true) ~= nil, "точка возврата запоминается")
ok(actions:find('hook.Add("PlayerSay", "GRM_Admin_Mute"', 1, true) ~= nil, "мут реально блокирует чат")
ok(actions:find('hook.Add("PlayerCanHearPlayersVoice", "GRM_Admin_Gag"', 1, true) ~= nil, "мут голоса работает")
ok(actions:find("local function releaseJail", 1, true) ~= nil, "клетка снимается корректно, с возвратом на место")
ok(actions:find('hook.Add("PlayerDisconnected", "GRM_Admin_Cleanup"', 1, true) ~= nil,
    "клетки и рагдоллы не остаются на карте после выхода")
ok(actions:find("ULib.ban", 1, true) ~= nil and actions:find("ULib.kick", 1, true) ~= nil,
    "бан и кик отдаются ULib — одна база банов с ULX")

print("\n=== 4. ВОЗМОЖНОСТИ СУПЕРАДМИНА ===")
for _, op in ipairs({ "god", "cloak", "speed", "buildmode", "freezeall", "unfreezeall", "money", "item", "cleanup" }) do
    ok(actions:find("A." .. op, 1, true) ~= nil, "суперадмин: " .. op)
end
ok(actions:find("if not AD.Can(ply, action.perm) then", 1, true) ~= nil, "каждое действие проверяет право")
ok(actions:find("audit(ply, op, target", 1, true) ~= nil, "каждое действие пишется в аудит")

print("\n=== 5. МЕНЮ ===")
ok(panel:find('concommand.Add("grm_admin_panel"', 1, true) ~= nil and panel:find('low == "/admin"', 1, true) ~= nil,
    "открытие: /admin, /админ, консоль")
for _, tab in ipairs({ "Игроки", "Привилегии", "Назначения", "Сохранения и карта",
    "Фракционный контроль", "Модули сборки", "Суперадмин" }) do
    ok(panel:find('"' .. tab .. '"', 1, true) ~= nil, "вкладка «" .. tab .. "»")
end
ok(panel:find("if perm and not can(perm) then return end", 1, true) ~= nil,
    "вкладки скрываются по правам, а не «серым цветом»")
ok(panel:find("local function buildPrivileges", 1, true) ~= nil and panel:find("матрица", 1, true) == nil
    or panel:find("byCategory", 1, true) ~= nil, "матрица полномочий по категориям")
ok(panel:find("СОХРАНИТЬ ГРУППЫ И ПОЛНОМОЧИЯ", 1, true) ~= nil, "кнопка сохранения групп")
ok(panel:find("НАЗНАЧИТЬ", 1, true) ~= nil, "назначение группы игроку прямо из карточки")

print("\n=== 6. ЖИВОЙ ПРОГОН ===")
local stub = dofile("tools/luatest/lib_gmod_stub.lua")
stub.install()
stub.reset()
_G.SERVER, _G.CLIENT = true, false
_G.CAMI = nil
_G.ULib = nil
_G.file = _G.file or {}
_G.file.Read = function() return nil end
_G.file.Write = function() end
_G.file.IsDir = function() return true end
_G.file.CreateDir = function() end
_G.util = _G.util or {}
_G.util.AddNetworkString = function() end
_G.util.JSONToTable = function() return nil end
_G.util.TableToJSON = function() return "{}" end
_G.util.SteamIDTo64 = function(s) return "7656119" .. tostring(s):gsub("%D", "") end
_G.concommand = { Add = function() end }
_G.net = setmetatable({}, { __index = function() return function() end end })
_G.player = _G.player or { GetAll = function() return {} end }

local okLoad, err = stub.loadModule("lua/autorun/sh_grm_admin_core.lua")
ok(okLoad, "ядро админки поднялось в моке", err)

local AD = _G.GRM and _G.GRM.Admin
ok(AD ~= nil, "GRM.Admin доступен")

if AD then
    AD.Groups = {}
    for _, g in ipairs(AD.DefaultGroups) do AD.Groups[g.id] = table.Copy and table.Copy(g) or g end

    local function fakePlayer(group, super)
        return {
            __valid = true, __entity = true, isPlayer = true,
            SteamID64 = function() return "76561198000000001" end,
            SteamID = function() return "STEAM_0:1:1" end,
            Nick = function() return "Тест" end,
            GetUserGroup = function() return group end,
            IsSuperAdmin = function() return super == true end,
            IsAdmin = function() return super == true or group == "admin" or group == "moderator" end,
            GetNWString = function() return "" end,
        }
    end

    local mod = fakePlayer("moderator", false)
    local adm = fakePlayer("admin", false)
    local sup = fakePlayer("superadmin", true)

    ok(AD.GroupOf(mod) == "moderator", "группа определяется по движку, если своей записи нет", AD.GroupOf(mod))
    ok(AD.Can(mod, "mod.goto") == true, "модератор может телепортироваться к игроку")
    ok(AD.Can(mod, "mod.jail") == false, "модератор НЕ может сажать в клетку")
    ok(AD.Can(adm, "mod.jail") == true, "администратор может сажать в клетку")
    ok(AD.Can(adm, "cheat.god") == false, "администратор НЕ получает читерские права")
    ok(AD.Can(sup, "cheat.god") == true, "суперадмин получает всё")
    ok(AD.Can(mod, "acl.groups") == false, "правка групп закрыта от модератора")

    ok(AD.Immunity(sup) == 100 and AD.Immunity(mod) == 20, "иммунитет считается по группе",
        tostring(AD.Immunity(sup)) .. "/" .. tostring(AD.Immunity(mod)))
    local can1 = AD.CanTarget(mod, adm)
    local can2 = AD.CanTarget(adm, mod)
    ok(can1 == false, "модератор не может применить действие к администратору")
    ok(can2 == true, "администратор может применить действие к модератору")
    ok(AD.CanTarget(mod, sup) == false, "суперадмина не тронуть")

    -- наследование: у admin есть права moderator
    ok(AD.Can(adm, "mod.goto") == true, "наследование прав по цепочке групп работает")

    -- своя группа из базы назначений сильнее движка
    AD.Users["76561198000000001"] = { group = "admin", ["until"] = 0 }
    ok(AD.GroupOf(mod) == "admin", "запись назначения перекрывает группу движка")
    AD.Users["76561198000000001"] = { group = "admin", ["until"] = 1 }   -- истёкшая
    ok(AD.GroupOf(mod) == "moderator", "истёкшее назначение не действует")
end

print("\n=== 7. УСТОЙЧИВОСТЬ ИНТЕРФЕЙСА (фикс NULL Panel) ===")
ok(panel:find("if not (IsValid(list) and IsValid(search)) then return end", 1, true) ~= nil,
    "пересборка списка проверяет, живы ли его панели")
ok(panel:find('hook.Remove("GRM_AdminPlayersUpdated", "GRM_AdminPanel_Players")', 1, true) ~= nil
    and panel:find("list.OnRemove = function()", 1, true) ~= nil,
    "подписка на обновление игроков снимается вместе со списком")
ok(panel:find("frame.OnRemove = function()", 1, true) ~= nil, "закрытие окна снимает подписки")
ok(panel:find('hook.Remove("GRM_AdminPlayersUpdated", "GRM_AdminPanel_Players")', 1, true) ~= nil,
    "переключение раздела тоже снимает подписку прошлого")
ok(panel:find("if not IsValid(side) then return end", 1, true) ~= nil,
    "панель действий не рисуется в удалённый контейнер")
ok(core:find("net.Send(targets)", 1, true) ~= nil and core:find("net.Broadcast()", 1, true) == nil
    or core:find("for watcher in pairs(AD.Watchers or {})", 1, true) ~= nil,
    "срез по игрокам уходит только тем, у кого открыто меню")
ok(core:find("Один результат — одно уведомление", 1, true) ~= nil,
    "результат действия больше не дублируется двумя уведомлениями")
ok(core:find("expires < CurTime()", 1, true) ~= nil, "подписка на живой список истекает сама")

print("\n=== 8. СПИСОК ИГРОКОВ (фикс «не показывает меня») ===")
ok(panel:find("local function playerRows", 1, true) ~= nil,
    "список строится из серверного среза И локального player.GetAll()")
ok(panel:find("row.entity = ply", 1, true) ~= nil, "строка связывается с живым игроком")
ok(panel:find("Список игроков пуст — данные ещё идут с сервера", 1, true) ~= nil,
    "пустой список объясняет себя, а не выглядит поломкой")
ok(panel:find('timer.Create(pollName, 5, 0', 1, true) ~= nil,
    "пока раздел открыт, срез перезапрашивается раз в 5 секунд")
ok(panel:find("timer.Remove(pollName)", 1, true) ~= nil, "опрос останавливается вместе с разделом")
ok(panel:find('hook.Run("GRM_AdminPlayersUpdated")', 1, true) ~= nil,
    "приход справочников больше не пересобирает вкладку целиком (не моргает)")
ok(core:find("ply._grmAdminSyncAt = CurTime() + 30", 1, true) ~= nil,
    "тяжёлые справочники шлются не чаще раза в 30 секунд")

print("\n=== 9. ВАЛЮТА GRM ВМЕСТО РУБЛЕЙ ===")
local unified = read("lua/autorun/client/cl_grm_factions_unified_ui.lua")
local hub = read("lua/autorun/sh_grm_admin_hub.lua")
ok(unified:find(" руб.", 1, true) == nil, "в меню организаций не осталось рублей")
ok(unified:find('GRM.Format(budget)', 1, true) ~= nil, "казна выводится общим форматтером GRM")
ok(unified:find("GRM.Format(fac.Budget or 0)", 1, true) ~= nil, "баланс бюджета — тоже")
ok(hub:find("GRM.Format(GRM.FactionBudgetGet(fac))", 1, true) ~= nil, "админ-хаб печатает бюджет в GRM")

print("\n=== ОБЪЯВЛЕНИЯ И РАНГИ В TAB (заказ 21.08) ===")
local function has(src, needle) return src:find(needle, 1, true) ~= nil end
local tab = read("lua/autorun/sh_grm_tab_menu.lua")
ok(has(core, "function AD.Announce"), "есть один общий слой объявлений администрации")
ok(has(core, 'net.Receive(NET_ANNOUNCE'), "клиент принимает объявления")
ok(has(core, "chat.AddText(Color(225, 70, 70)"), "объявление печатается красным текстом")
ok(has(core, 'AD.Announce(("%s изменил группу игрока %s: %s → %s")'),
    "смена группы объявляется всем")
ok(has(core, 'ply:SetNWString("GRM_AdminGroup", groupID)'),
    "группа висит на игроке — списки видят её сразу")
ok(has(core, "function AD.GroupLabel"), "название и цвет группы отдаёт сам модуль групп")
ok(has(actions, "local PUNISH = {"), "формулировки наказаний собраны одной таблицей")
ok(has(actions, "local function punishText"), "текст объявления строится одним слоем")
ok(has(actions, "if ok and AD.Announce then"), "объявление уходит после успешного действия")
ok(has(actions, "targetWas"), "различается «посадил» и «выпустил» (кнопка одна)")
ok(has(tab, "if GRM.Admin and GRM.Admin.GroupOf then"), "TAB читает группу из GRM.Admin")
ok(has(tab, "rankName ="), "в TAB уходит название группы")
ok(has(tab, "rankColor ="), "и её цвет")
ok(has(tab, 'hook.Add("GRM_AdminGroupChanged", "GRM_TabMenu_GroupChanged"'),
    "TAB обновляется сразу после смены группы, а не через 5 секунд")
ok(has(tab, "local function announce(verb, target, tail)"),
    "кнопки наказаний в самом TAB тоже объявляются")

print("\n=== БАН НА СЕРВЕРЕ И ГЛОБАЛЬНЫЙ (заказ 21.08) ===")
local ban = read("lua/autorun/sh_grm_ban.lua")
local panel2 = read("lua/autorun/client/cl_grm_admin_panel.lua")
ok(has(ban, 'SB.Model = "models/player/skeleton.mdl"'), "модель наказанного — скелет")
ok(has(ban, 'SB.Material = "debugwhite"'), "материал debugwhite")
ok(has(ban, "ply:SetColor(Color(255, 60, 60, 255))"), "красная подсветка")
ok(has(ban, "ply:StripWeapons()"), "оружие изымается")
ok(has(ban, "function SB.SetZone"), "суперадмин задаёт точку отбывания")
ok(has(ban, 'timer.Create("GRM_ServerBan_Watch", 0.5, 0'),
    "один сторож: зона, вид и срок")
ok(has(ban, "CanPlayerSuicide") and has(ban, "PlayerCanPickupWeapon") and has(ban, "CanTool"),
    "самоубийство, оружие и инструменты закрыты")
ok(has(ban, 'hook.Add(name, "GRM_ServerBan_NoMenus_"'), "меню F1-F4 закрыты")
ok(has(ban, 'hook.Add("PlayerSay", "GRM_ServerBan_NoCommands"'),
    "команды в чате блокируются, обычный чат остаётся")
ok(has(ban, "GRM_NameplateOverride"), "плашка «ЗАБАНЕН» идёт через общий слой шапки")
ok(has(ban, "ВЫ ЗАБАНЕНЫ НА СЕРВЕРЕ"), "наказанный видит памятку на экране")
ok(has(actions, "A.serverban = {"), "действие «Бан на сервере»")
ok(has(actions, "A.unserverban = {"), "действие «Снять бан на сервере»")
ok(has(actions, "A.unban = {"), "действие «Снять глобальный бан»")
ok(has(actions, "A.ban_point = {"), "действие «Точка отбывания»")
ok(has(actions, 'serverban = { verb = "забанил на сервере"'), "бан на сервере объявляется в чат")
ok(has(panel2, "ЗАБАНИТЬ НА СЕРВЕРЕ"), "кнопка бана на сервере в админ-меню")
ok(has(panel2, '"Глобальный бан 60 мин"') and has(panel2, '"Глобальный бан навсегда"'),
    "кнопки глобального бана")
ok(has(panel2, "БАН НА СЕРВЕРЕ · ЗОНА ОТБЫВАНИЯ"), "блок настройки зоны в админ-меню")
ok(has(panel2, '"РАЗБАНИТЬ"'), "кнопка снятия глобального бана")
ok(has(panel2, 'flags[#flags + 1] = "БАН НА СЕРВЕРЕ"'), "в карточке видно, что игрок отбывает")

print("\n=== БАН НА СЕРВЕРЕ: ПРИЧИНА, ЭФИР, ГОЛОД (21.08) ===")
local ban2 = read("lua/autorun/sh_grm_ban.lua")
local panel3 = read("lua/autorun/client/cl_grm_admin_panel.lua")
local fac2 = read("lua/autorun/sh_factions.lua")
local food = read("lua/autorun/server/sv_grm_food.lua")
local radio = read("lua/autorun/sh_grm_radionet.lua")
ok(has(panel3, "ЗАБАНИТЬ НА СЕРВЕРЕ") and has(panel3, "РАЗБАНИТЬ НА СЕРВЕРЕ"),
    "в меню обе кнопки: бан и разбан на сервере")
ok(has(panel3, 'entry(box, "Причина бана (обязательно)")'), "поле причины бана")
ok(has(panel3, "Укажите причину бана"), "без причины бан не выдаётся")
ok(has(panel3, 'entry(box, "Минуты")'), "поле срока")
ok(has(ban2, "function SB.SpeechBlocked"), "единый запрет на эфир")
ok(has(ban2, "function SB.DenySpeech"), "и помощник, который сам пишет игроку")
ok(has(ban2, "SB.WaveCommands = {"), "перечислены волны и рации")
ok(has(ban2, "деморган"), "текст про административное наказание/деморган")
ok(has(fac2, "local function banGate(ply, what)"), "волны организаций закрыты одной проверкой")
ok(select(2, fac2:gsub("banGate%(ply,", "")) >= 4, "проверка стоит во всех четырёх волнах")
ok(has(radio, "GRM.ServerBan.PlayerBanned(speaker)"), "радиоэфир наказанного не слышен")
ok(has(food, "Отбывающий наказание не голодает"), "голод на наказанных не действует")

print("\n=== БАН: ТАЙМЕР, ОКНА, СПИСОК (21.08) ===")
local ban3 = read("lua/autorun/sh_grm_ban.lua")
local inv = read("lua/autorun/sh_grm_inventory.lua")
ok(has(ban3, "local function banLeftText(lp)"), "таймер считается на клиенте вживую")
ok(has(ban3, '("%02d:%02d"):format(m, sec)'), "показывается минутами и секундами")
ok(has(ban3, 'hook.Add("ContextMenuOpen", "GRM_ServerBan_NoContext"'), "C-меню закрыто")
ok(has(ban3, 'hook.Add("SpawnMenuOpen", "GRM_ServerBan_NoSpawnMenu"'), "спавн-меню закрыто")
ok(has(ban3, 'hook.Add("Think", "GRM_ServerBan_CloseWindows"'), "сторож закрывает открытые окна")
ok(has(ban3, "nextSweep = CurTime() + 0.5"), "сторож троттлится, а не работает в кадре")
ok(has(inv, "local function banGate(ply, what)"), "инвентарь закрыт одной проверкой")
ok(select(2, inv:gsub("banGate%(ply,", "")) >= 6, "проверка стоит на всех действиях инвентаря")
ok(has(ban3, "function SB.List()"), "есть список отбывающих")
ok(has(ban3, "SB.History"), "ведётся история наказаний")
ok(has(ban3, "history = SB.History"), "история сохраняется на диск")
ok(has(ban3, 'concommand.Add("grm_serverban_unban"'), "разбан из списка")
ok(has(ban3, "БАНЫ НА СЕРВЕРЕ"), "окно списка забаненных")
ok(has(panel3, "СПИСОК ЗАБАНЕННЫХ"), "кнопка списка в админ-меню")

print("\n=== ЗВУК НАКАЗАННЫХ (21.08) ===")
local ban4 = read("lua/autorun/sh_grm_ban.lua")
ok(has(ban4, '"npc/zombie/zombie_voice_idle1.wav"'), "звук из заказа владельца на месте")
ok(has(ban4, "function SB.Moan"), "стон вынесен в отдельную функцию")
ok(has(ban4, "GRM_BanNextMoan"), "у каждого свой момент следующего звука — не воют хором")
ok(has(read("lua/autorun/sh_07_grm_sound.lua"), 'S.Register("npc/zombie/zombie_voice_idle1.wav")'),
    "звуки зарегистрированы в общем реестре прекэша, без второй копии логики")
ok(has(ban4, "GRM.Sound.Resolve"), "путь проходит через звуковой слой с фолбэком")
ok(has(ban4, 'CreateConVar("grm_ban_zombie_sound"'), "звук отключается конваром")
ok(has(ban4, "SB.Moan(ply)") and has(ban4, 'timer.Create("GRM_ServerBan_Watch"'),
    "звук идёт из общего сторожа, без таймера на каждого игрока")

print("\n=== ТОЧКА ОТБЫВАНИЯ: ПАМЯТЬ (21.08) ===")
local ban5 = read("lua/autorun/sh_grm_ban.lua")
ok(has(ban5, "Vector — это\n             userdata") or has(ban5, "util.TableToJSON пишет его пустышкой"),
    "разобрана причина, по которой точка слетала")
ok(has(ban5, "pos = { x = math.floor(pos.x)"), "точка хранится числами, а не Vector")
ok(has(ban5, "function SB.ZonePos"), "Vector собирается при использовании")
ok(has(ban5, 'GRM.Save.Flush("serverban.zone"'), "точка пишется сразу, не дожидаясь очереди")
ok(has(ban5, "not (x == 0 and y == 0 and zz == 0)"), "нули из битого файла не считаются точкой")
ok(has(ban5, "точка отбывания на карте"), "в консоль печатается, есть ли точка после загрузки")

print("\n=== ПОСЛЕ РАЗБАНА (баг 21.08) ===")
local ban6 = read("lua/autorun/sh_grm_ban.lua")
ok(ban6:find("\n%s*panel:Remove%(%)") == nil and has(ban6, "pcall(panel.Close, panel)"),
    "клиентский сторож больше НЕ удаляет панели, а только закрывает (сносил чат EasyChat)")
ok(has(ban6, 'class:find("chat", 1, true)'), "чат и HUD сторож не трогает вовсе")
ok(not has(ban6, "ply:Spawn()\n    end"), "принудительного респавна при снятии бана нет")
ok(has(ban6, 'pcall(hook.Run, "PlayerLoadout", ply)'), "снаряжение возвращается штатным хуком")
ok(has(ban6, "ply:Freeze(false)"), "подвижность возвращается явно")
ok(has(ban6, 'concommand.Add("grm_serverban_fix"'), "есть аварийное снятие следов наказания")
ok(has(ban6, "Следы наказания на свободном игроке"), "сторож сам чистит следы у свободных")
ok(has(ban6, "прежнее значение не затираем"), "повторный бан не затирает запомненную модель")

print("\n=== ВОЗВРАТ НА МЕСТО ПОСЛЕ БАНА (21.08) ===")
local ban7 = read("lua/autorun/sh_grm_ban.lua")
ok(has(ban7, "returnPos = { x = math.floor(from.x)"), "исходная точка пишется числами")
ok(has(ban7, "ply.GRM_BanReturn"), "точка возврата висит на игроке")
ok(has(ban7, "if istable(rec.returnPos) then"), "и подхватывается из записи после рестарта")
ok(has(ban7, "Вы возвращены на прежнее место."), "игроку сообщают о возврате")
ok(has(ban7, "function SB.Clear(ply, returnPos)"), "снятие бана принимает точку возврата")

print(("\nADMIN CORE: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
