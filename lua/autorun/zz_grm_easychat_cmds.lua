--[[--------------------------------------------------------------------
    GRM EasyChat: локальная обработка неизвестных / и ! команд.

    Игроки часто пишут в чат /noclip, !studio и прочие команды, у которых
    нет обработчика в модулях. Раньше EasyChat уводил такой текст в
    глобальный чат. Теперь:
      - известные команды модулей (реестр ниже) работают как раньше
        (клиентские гаснут в своих PlayerSayTransform, серверные уходят
        на сервер и обрабатываются там);
      - «менеджерские» команды (noclip, god, ulx, uli, aegis, sam, …) —
        их исполняет СЕРВЕР (ULib/ULX своими PlayerSay-хуками со своей
        проверкой прав). На клиенте они не гасятся и локально не
        запускаются: движковый noclip из клиента режется sv_cheat, а
        локальный запуск рядом с ULib давал двойное переключение (вкл+выкл
        = «баг срабатывания»); если менеджер команду не съел, её
        перехватит серверный PostTransform — в чат она всё равно не
        выйдет;
      - прочее, начинающееся с / или !: если команда известна КЛИЕНТУ
        (mat_*, studio, rcon…) — гасится и выполняется локально; если
        нет — проходит на сервер как обычный say, где серверный
        PostTransform исполнит её консольной командой и в глобальный чат
        не пустит;
      - сервер дублирует защиту для не-EasyChat путей: PlayerSay гасит
        неизвестные (кроме менеджерских — их исполняет ULib), а
        PlayerSayPostTransform EasyChat гасит любой оставшийся / и ! текст
        (известные команды к этому моменту уже обработаны модулями).

    Не путать с RP-чатом: /me, /do, /w, /y, /ooc и алиасы — известные
    команды, их реестр пропускает к серверному обработчику.
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.EasyChat = GRM.EasyChat or {}
local C = GRM.EasyChat

-- Известные чат-команды GRM-модулей (имя без ведущего / или !, нижний
-- регистр). Собраны со всех hook.Add("PlayerSay"/"PlayerSayTransform")
-- в lua/ и addons/. Новую команду модуля добавлять сюда обязательно:
-- иначе она будет перехвачена как неизвестная.
C.CmdList = {
"911", "911_admin", "911_calls", "911_cases", "ach", "ach_reset", "achievements", "acquaintances",
"addonstudio", "addorespawn", "admin", "aid", "alarm_access", "alert", "alert_allow", "alert_deny",
"alertall", "anim", "animstop", "animstudio", "antenna_add", "antenna_remove", "arrest", "augment",
"augmentations", "autobinder", "autopilot", "badge", "bcast_allow", "bcast_deny", "bcast_list",
"bcasters", "binder", "bizlicense", "blicense", "board", "board_add", "board_allow", "board_deny",
"board_list", "board_remove", "bodygroups_admin", "build", "business", "business_accept",
"businesslicense", "buybusiness", "buyhome", "cabinet", "calltaxi", "canceltaxi", "case_requests",
"case_transfer", "cashout", "cctv_access", "cctvaccess", "char", "chars", "check_business",
"check_license", "check_weapon", "civlicense", "civprava", "cleanupoffline", "cleanupprops",
"comp_access", "console_add", "console_remove", "coords", "cover_drop", "cover_new", "cover_use",
"covers", "covert_fine_wipe", "covert_hide", "covert_level", "covert_unhide", "covert_wipe",
"cruise", "d", "db", "delete_saved", "dep", "depb", "dice", "do", "doc_admin", "doc_wipe",
"docadmin", "doccfg", "docrestore", "door", "door_access", "door_audit", "door_guest", "door_kick",
"door_rebuild", "driverlicense", "drop", "dropmoney", "dropweapon", "drugstatus", "econadmin",
"f4", "factions", "fbudget", "feco_admin", "feuer", "feuer_off", "fine", "fines", "fire_access",
"fire_calls", "fire_ignite", "fire_kill", "fire_log", "fire_spots", "fire_trucks", "firelog",
"firetruck", "firetruck_admin", "firetruck_off", "fjoin", "fleet", "fmenu", "forensics", "fpay",
"fpayall", "fr", "frb", "freq", "freqleave", "frooc", "fsettax", "fwithdraw", "g", "giveore",
"gnews", "gps", "grm_access", "grm_accessories_admin", "grm_admin", "grm_admin_panel",
"grm_arrest_admin", "grm_fire_notify", "grm_minimap_admin", "grm_network_admin", "grm_persistence",
"grm_quests_admin", "grm_vending_clear", "grm_vending_load", "grm_vending_save", "grmadmin",
"grmclearvending", "grmloadvending", "grmmenu", "grmsavevending", "gunlicense", "heist_force",
"heist_stop", "heist_target", "heist_target_clear", "home", "hose", "housing_log", "id", "incass",
"incass_deliver", "incass_delivery", "incass_end", "incass_off", "intro", "introduce", "inv",
"inventory", "it", "job", "job_allow", "job_deny", "job_list", "jobadmin", "jobcancel",
"jobcenter_add", "jobcenter_remove", "jobdepot_add", "jobdepot_remove", "jobpost", "jobs",
"jobs_admin", "kom_hour", "laws", "leaders", "license", "license_check", "license_points",
"listorespawns", "loadentities", "lock", "logistics_admin", "looc", "male", "mallicense", "market",
"marks", "mask", "mask_admin", "maskcfg", "maskdesc", "me", "med", "medcard", "medcards",
"members", "menu", "milcard", "military", "militaryid", "millicense", "milprava", "mine_price",
"mine_prices", "mine_tool", "mineclean", "mobile", "model", "models_admin", "money_pack",
"moneydrop", "mybadge", "mycard", "myid", "mylicense", "mypasport", "mysalary", "myudost",
"myvehicles", "name", "narc_status", "number_layout", "number_layout_reset", "ooc", "oreprices",
"pass", "passport", "pc_access", "pcboard", "permadd", "perminfo", "permload", "permowner",
"permremove", "phone", "phone_access", "phone_admin_remove", "phone_remove", "phoneaccess",
"phoneshop", "phoneshop_admin", "photo", "plate_edit", "plate_issue", "plate_status", "plateoff",
"plateon", "plates", "plateyaw", "points", "posedit", "prava", "processlist", "prop_admin",
"property", "property_admin", "propprotect", "qm", "qm_clearprops", "qm_diag", "qm_prop_add",
"qm_prop_addmodel", "qm_prop_del", "qm_prop_list", "qm_seed", "quests", "r", "rack_add",
"rack_remove", "radio", "radio_add", "radio_remove", "radiomic_add", "radiomic_remove",
"refillore", "refreshweapons", "remove_saved", "removeorespawn", "removephone",
"removephone_admin", "rn_log", "rn_net", "rn_status", "roll", "roomtap_access", "roomtap_remove",
"roomtap_requests", "roomtapshop", "root_add", "root_del", "root_list", "root_queue", "rpbinder",
"rpdesc", "rstation_add", "rstation_remove", "rtshop", "salary_admin", "saveentities",
"saveorespawns", "scanvehicles", "setoreprice", "showbadge", "showbizlicense",
"showbusinesslicense", "showcivlicense", "showcivprava", "showdiploma", "showdriverlicense",
"showgunlicense", "showid", "showlicense", "showmed", "showmedcard", "showmil", "showmilitary",
"showmilitaryid", "showmillicense", "showmilprava", "showpass", "showpassport", "showprava",
"showudost", "showvb", "showwarcard", "showweaponlicense", "social", "spawnore", "speaker_add",
"speaker_remove", "spec", "store", "studio", "taxi", "teleshop", "ticket", "ticket_rate",
"tickets", "time", "transport_market", "trunk", "try", "udost", "unarrest", "unlock", "unwarrant",
"vaccess", "vb", "vlist", "vshop", "vshop_admin", "w", "wanted", "wanted_access", "wanted_board",
"wanted_clear", "wanted_custom", "warcard", "wardrobe_add", "wardrobe_remove", "warrant",
"warrants", "weaponlicense", "weapons_admin", "whisper", "wlicense", "y", "yell", "автопарк",
"автопилот", "админ", "адонстудия", "альбом", "аним", "анимации", "анимстудия", "аудит_дверей",
"багажник", "баллы", "бизнес", "биндер", "бинды", "бодигруппы", "бур", "ваиправа", "вб",
"водительское", "водправа", "военник", "военноеву", "военныеводправа", "военныеправа",
"военныйбилет", "время", "ву", "вуваи", "выбить", "вызватьтакси", "вызовы", "вызовы_пожар",
"гражданскиеправа", "граждправа", "дела911", "докадмин", "докстереть", "документ", "документы",
"дом", "доступы", "журнал_жилья", "журнал_пожаров", "журналпожаров", "закон", "законы", "закупка",
"замер", "знакомые", "инкасс", "инкасс_офф", "инкасс_стоп", "кабинет", "квартира", "квесты",
"компьютеры", "комчас", "координаты", "круиз", "ксива", "лидеры", "лицензиябизнес",
"лицензиянаоружие", "мед", "медкарта", "моибаллы", "недвижимость", "номер_layout",
"номер_layout_сброс", "номер_выдать", "номер_вынос", "номер_зеркало", "номер_масштаб",
"номер_наклон", "номер_настройки", "номер_ось", "номер_поворот", "номер_ред", "номер_сброс",
"номер_сдвиг", "номер_статус", "номера", "номерприкрепить", "номерред", "оплатить_штраф",
"орбизнес", "ориентировка", "ороружие", "оружие", "осмотр", "очаги", "очиститьофлайн",
"очиститьпропы", "пас", "паспорт", "передать_дело", "пересборка_дверей", "пк_доступ", "пм",
"пожарка", "пожарка_стоп", "пожарныйрукав", "пожары_лог", "пожары_очаги", "показатьбизнес",
"показатьваи", "показатьводправа", "показатьвоенник", "показатьвоенныеправа",
"показатьвоенныйбилет", "показатьгражданскиеправа", "показатьксиву", "показатьлицензиюбизнес",
"показатьлицензиюоружие", "показатьмедкарту", "показатьоружие", "показатьпаспорт", "показатьправа",
"показатьувв", "показатьудостоверение", "покбизнес", "покваи", "поквб", "поквоенправа", "покву",
"покграждправа", "покдиплом", "покмед", "покоружие", "покпас", "покправа", "покувв", "покудост",
"помощь", "права", "прававаи", "представиться", "предъявитьдиплом", "прикрепить", "приметы",
"проверить_бизнес", "проверить_оружие", "проверить_права", "проппротект", "розыск",
"розыск_уровень", "рукав", "рынок", "сдать", "снятьномер", "состав", "специальный", "ствол",
"стоппоза", "такси", "телефон", "увв", "удост", "удостоверение", "фото", "фракция", "цены_руды",
"-- команды из файлов с нестандартными hook.Add() и LOOC \"//\"",
"/", "garage", "гараж", "grm_alarm_notify", "номер", "accessories_off",
"acc_remove", "снятьаксессуары", "пробить", "repair", "починить", "ремонт",
"diagnose", "vending_buy", "автомат", "dbcheck", "permlist", "spawnmenu",
"точкиспавна", "служба", "prone", "лечь", "duty", "doccopy", "bag_unload",
}

-- Команды админ-менеджеров: исполняются серверными PlayerSay-хуками
-- (ULib/ULX и т.п.) со своей проверкой прав. Клиент их не гасит и никто
-- не дублирует их выполнение локальными ConCommand — двойной noclip
-- выключает noclip.
C.ManagerCmds = {
    noclip = true, god = true,
    ulx = true, uli = true, a = true,
    aegis = true, sam = true, sa = true, slb = true,
}

local known = {}
for _, name in ipairs(C.CmdList) do
    if name ~= "" then known[name] = true end
end

-- Публичная проверка для модулей и стендов.
C.IsKnownCmd = function(name)
    return known[tostring(name or ""):lower()] == true
end

-- Разбор команды: возвращает имя без префикса (нижний регистр) и текст
-- без первого символа, если сообщение начинается с / или !.
-- "//" (LOOC RP-чата) не считается неизвестной командой.
local function splitCommand(text)
    text = string.Trim(tostring(text or ""))
    if text == "" then return end
    local first = string.sub(text, 1, 1)
    if first ~= "/" and first ~= "!" then return end
    if string.sub(text, 1, 2) == "//" then return end
    local word = string.Explode(" ", text)[1] or ""
    local name = string.lower(string.sub(word, 2))
    if name == "" then return end
    return name, string.sub(text, 2)
end

if SERVER then
    -- Локальное выполнение консольной команды у игрока (на сервере).
    local function runServerCommand(ply, text)
        local stripped = string.sub(text, 2)
        local args = string.Explode(" ", stripped)
        local argstr = string.Trim(string.sub(stripped, #(args[1] or "") + 1))
        concommand.Run(ply, args[1] or "", args, argstr)
    end

    -- Ванильный чат (без EasyChat): неизвестные / и ! команды в
    -- глобальный чат не пускаем. Менеджерские только гасим — их в этой же
    -- цепочке исполняет ULib/ULX; наш повторный запуск сложил бы эффект
    -- вдвое (noclip вкл+выкл).
    hook.Add("PlayerSay", "GRM_EasyChat_UnknownCmd_Say", function(ply, text, teamChat)
        local name = splitCommand(text)
        if not name then return end
        if known[string.lower(name)] then return end
        if not C.ManagerCmds[string.lower(name)] then
            runServerCommand(ply, text)
        end
        return ""
    end)

    -- EasyChat: это последний шаг серверной цепочки (после PlayerSay).
    -- Сюда доходит только необработанный текст — гасим любой / или !;
    -- менеджерские исполнены (или не исполнены) ULib-цепочкой, не
    -- повторяем.
    hook.Add("PlayerSayPostTransform", "GRM_EasyChat_UnknownCmd_PostServer", function(ply, datapack, is_team, is_local)
        if not istable(datapack) or not isstring(datapack[1]) then return end
        local name = splitCommand(datapack[1])
        if not name then return end
        if not C.ManagerCmds[string.lower(name)] then
            runServerCommand(ply, datapack[1])
        end
        datapack[1] = ""
        datapack.SkipPlayerSay = true
    end)
end

if CLIENT then
    -- EasyChat-клиент: после всех PlayerSayTransform и PlayerSay хуков.
    -- Менеджерские команды (см. C.ManagerCmds) не трогаем вовсе — пусть
    -- уйдут на сервер как say и ULib/ULX отработают со своей авторизацией.
    -- Остальное неизвестное: клиентская консольная команда — гасим чат и
    -- выполняем локально; не клиентская — пропускаем, серверный
    -- PostTransform подхватит, в глобальный чат текст не выйдет.
    hook.Add("PlayerSayPostTransform", "GRM_EasyChat_UnknownCmd_Post", function(ply, datapack, is_team, is_local)
        if not istable(datapack) or not isstring(datapack[1]) then return end
        local name, stripped = splitCommand(datapack[1])
        if not name then return end
        if C.IsKnownCmd(name) then return end
        if C.ManagerCmds[name] then return end
        if not (isfunction(ConCommandExists) and ConCommandExists(name)) then return end
        datapack[1] = ""
        datapack.SkipPlayerSay = true
        local lp = LocalPlayer()
        if IsValid(lp) and isfunction(lp.ConCommand) then
            lp:ConCommand(stripped)
        end
    end)
end

print("[GRM] EasyChat unknown command guard loaded")
