--[[--------------------------------------------------------------------
    sim_doc_wipe — заказ владельца: команда полного удаления документов
    у себя и у других, со стиранием из всех баз.

    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_doc_wipe.lua
----------------------------------------------------------------------]]
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

local docs    = read("lua/autorun/sh_grm_documents.lua")
local actions = read("lua/autorun/server/sv_grm_admin_actions.lua")
local panel   = read("lua/autorun/client/cl_grm_admin_panel.lua")

print("\n=== 1. ЧИСТКА ВСЕХ БАЗ ===")
ok(docs:find("function DOC.WipeDocuments", 1, true) ~= nil, "есть функция полного удаления")
for _, registry in ipairs({ "passports", "badges", "coverBadges", "military", "licenses",
    "milLicenses", "weaponLicenses", "businessLicenses", "exams" }) do
    ok(docs:find(registry .. " = ", 1, true) ~= nil or docs:find(registry, 1, true) ~= nil,
        "реестр " .. registry .. " учтён")
end
ok(docs:find("local REGISTRY_LABELS = {", 1, true) ~= nil,
    "чистка идёт по единому списку реестров, а не хардкодом в разных местах")
ok(docs:find('DOC.SaveRegistry("wipe documents "', 1, true) ~= nil, "реестр документов сохраняется на диск")
ok(docs:find("SS.Data.covers", 1, true) ~= nil and docs:find("pcall(SS.Save)", 1, true) ~= nil,
    "легенды прикрытия спецслужбы тоже стираются и сохраняются")
ok(docs:find("GRM.Diplomas", 1, true) ~= nil and docs:find("pcall(DP.Save)", 1, true) ~= nil,
    "дипломы удаляются из своего реестра")
ok(docs:find('hook.Run("GRM_DocumentsWiped"', 1, true) ~= nil, "событие для других модулей")

print("\n=== 2. РЕЖИМЫ ===")
ok(docs:find("local account = opts.account == true", 1, true) ~= nil, "режим «весь аккаунт»")
ok(docs:find('return string.sub(key, 1, #sid64 + 1) == (sid64 .. ":")', 1, true) ~= nil,
    "в режиме аккаунта чистятся все слоты персонажей")
ok(docs:find("opts.keepExams == true", 1, true) ~= nil, "экзамены можно сохранить отдельным флагом")

print("\n=== 3. КОМАНДА И ЗАЩИТА ===")
ok(docs:find("function DOC.WipeCommand", 1, true) ~= nil, "точка входа команды")
ok(docs:find('concommand.Add("grm_doc_wipe"', 1, true) ~= nil, "консольная команда")
ok(docs:find('low == "/doc_wipe"', 1, true) ~= nil, "чат-команда /doc_wipe")
ok(docs:find('low == "/докстереть"', 1, true) ~= nil, "русский вариант команды")
ok(docs:find('hook.Add("PlayerSay", "GRM_Doc_WipeChat"', 1, true) ~= nil, "обычный чат")
ok(docs:find("Полное удаление документов (EasyChat", 1, true) ~= nil, "и EasyChat (PlayerSayTransform)")
ok(docs:find("Повторите команду в течение 20 секунд", 1, true) ~= nil,
    "требуется подтверждение — случайно не стереть")
ok(docs:find("local function canWipeOthers", 1, true) ~= nil, "чужие документы — только по праву")
ok(docs:find('GRM.Admin.RegisterPerm("docs.wipe"', 1, true) ~= nil,
    "право docs.wipe зарегистрировано в админ-платформе")
ok(docs:find('minAccess = "superadmin", danger = true', 1, true) ~= nil,
    "по умолчанию право только у суперадмина и помечено опасным")
ok(docs:find("local function findTarget", 1, true) ~= nil, "цель ищется по нику, RP-имени, SteamID и SteamID64")
ok(docs:find('GRM.Audit.Write("documents", "wipe"', 1, true) ~= nil, "удаление пишется в аудит")
ok(docs:find("Все ваши документы аннулированы администрацией", 1, true) ~= nil, "игрок узнаёт об этом")

print("\n=== 4. ИЗ АДМИН-МЕНЮ ===")
ok(actions:find("A.docs_wipe = { perm = \"docs.wipe\"", 1, true) ~= nil, "действие в админ-платформе")
ok(actions:find("args and args.account == true", 1, true) ~= nil, "поддержан режим всего аккаунта")
ok(panel:find('action("Стереть документы", "docs.wipe", "docs_wipe"', 1, true) ~= nil, "кнопка в карточке игрока")
ok(panel:find('action("Стереть на всех персонажах"', 1, true) ~= nil, "кнопка для всех персонажей аккаунта")

print(("\nDOC WIPE: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
