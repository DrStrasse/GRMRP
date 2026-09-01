--[[--------------------------------------------------------------------
    sim_military_rank — заказ владельца 19.08: воинское звание в военном
    билете должно вписываться вручную (как в военном водительском), и в
    компьютере военкомата должна быть видимая строка для этого.

    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_military_rank.lua
----------------------------------------------------------------------]]
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

local mil  = read("lua/entities/grm_comp_military/cl_init.lua")
local comp = read("lua/entities/grm_doc_computer/cl_init.lua")
local docs = read("lua/autorun/sh_grm_documents.lua")

print("\n=== 1. КОМПЬЮТЕР ВОЕНКОМАТА ===")
ok(mil:find("local entMilRankCustom = vgui.Create(\"DTextEntry\", milPnl)", 1, true) ~= nil,
    "появилось поле ручного ввода звания")
ok(mil:find('entMilRankCustom:SetPlaceholderText("или своё звание вручную")', 1, true) ~= nil,
    "подсказка в поле")
ok(mil:find("comboMilRank.OnSelect = function(_, _, value)", 1, true) ~= nil,
    "выбор из списка подставляется в поле (как у ВУС)")
ok(mil:find("local chosenRank = string.Trim(entMilRankCustom:GetText())", 1, true) ~= nil,
    "при выдаче берётся ручное звание")
ok(mil:find('if chosenRank == "" then chosenRank = comboMilRank:GetValue() end', 1, true) ~= nil,
    "если ручное пустое — берётся выбранное из списка")
ok(mil:find("rank        = chosenRank,", 1, true) ~= nil, "в билет уходит выбранное звание")
ok(mil:find('entMilRankCustom:SetText(ex.rank or "")', 1, true) ~= nil,
    "при открытии существующего билета звание подставляется в поле")

print("\n=== 2. ПОДПИСИ ПОЛЕЙ (их не было вовсе) ===")
ok(mil:find("local function fieldLabel", 1, true) ~= nil, "добавлен помощник подписей")
for _, label in ipairs({ "ФИО военнослужащего:", "Воинское звание (выбор / ручной ввод):",
    "Военно-учётная специальность (ВУС):", "Воинское формирование:", "Подразделение:",
    "Должность:", "Категория годности:", "Номер бланка:", "Кем выдан:" }) do
    ok(mil:find('"' .. label .. '"', 1, true) ~= nil, "подпись «" .. label .. "»")
end

print("\n=== 3. ОБЩИЙ КОМПЬЮТЕР ДОКУМЕНТОВ ===")
ok(comp:find("comboMilRank.OnSelect = function(_, _, value)", 1, true) ~= nil,
    "военный билет: список синхронизирован с полем ручного ввода")
ok(comp:find("entMilRankCustom:SetText(ex.rank or \"\")", 1, true) ~= nil,
    "военный билет: существующее звание подставляется")

print("\n=== 4. ВОЕННОЕ ВОДИТЕЛЬСКОЕ ===")
ok(comp:find("local entRankCustom = vgui.Create(\"DTextEntry\", formContainer)", 1, true) ~= nil,
    "у военного водительского тоже появился ручной ввод звания")
ok(comp:find("comboRank.OnSelect = function(_, _, value)", 1, true) ~= nil, "список подставляется в поле")
ok(comp:find("rank          = (string.Trim(entRankCustom:GetText()) ~= \"\"", 1, true) ~= nil,
    "ручное звание имеет приоритет при выдаче")

print("\n=== 5. СЕРВЕР ===")
ok(docs:find("if isstring(data.rank) then data.rank = string.sub(string.Trim(data.rank), 1, 48) end", 1, true) ~= nil,
    "звание подрезается по длине, чтобы бланк не поехал")
ok(select(2, docs:gsub('if data%.rank == "" then data%.rank = "Рядовой" end', "")) >= 2,
    "пустое звание заменяется значением по умолчанию и в билете, и в правах")

print(("\nMILITARY RANK: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
