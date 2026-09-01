--[[--------------------------------------------------------------------
    sim_doc_cover_color — цвет удостоверений: запоминание в /doc_admin
    и реальное отражение цвета на корочке.

    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_doc_cover_color.lua
----------------------------------------------------------------------]]
local function read(p) local f = assert(io.open(p, "rb")) local s = f:read("*a") f:close() return s end
local doc = read("lua/autorun/sh_grm_documents.lua")

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end
local function has(s) return doc:find(s, 1, true) ~= nil end

print("\n=== 1. ЗАПОМИНАНИЕ ЦВЕТА В /doc_admin ===")
ok(not has('comboCol:SetValue("Выбрать цвет")'),
    "заглушка «Выбрать цвет» убрана — панель больше не забывает настройку")
ok(has("local function coverPresetName(col)"), "имя пресета вычисляется по сохранённым RGB")
ok(has("comboCol:SetValue(coverPresetName(curCover))"), "при открытии показан реально сохранённый цвет")
ok(has("local saved = istable(cfg.coverColor) and cfg.coverColor or nil"),
    "цвет читается из шаблона организации")
ok(has("mixer:SetColor(Color(curCover.r, curCover.g, curCover.b))"),
    "палитра синхронизируется с сохранённым цветом")

print("\n=== 2. СОХРАНЕНИЕ БЕЗ ПОТЕРЬ ===")
ok(has("fCfg.coverColor = { r = curCover.r, g = curCover.g, b = curCover.b }"),
    "сохраняется живое состояние панели, а не только клик по списку")
ok(not has("local _, colData = comboCol:GetSelected()"),
    "старая ветка «сохранять только при выборе пункта» удалена")
ok(has("fCfg.foilStyle = curFoil"), "стиль тиснения тоже сохраняется всегда")

print("\n=== 3. ПРОИЗВОЛЬНЫЙ ЦВЕТ ===")
ok(has('comboCol:AddChoice("Свой цвет (палитра ниже)"'), "в списке есть пункт своего цвета")
ok(has('local mixer = vgui.Create("DColorMixer", facPnl)'), "палитра доступна прямо в /doc_admin")
ok(has("mixer.ValueChanged = function(_, col)"), "выбор в палитре сразу меняет текущий цвет")

print("\n=== 4. РЕАЛЬНОЕ ОТРАЖЕНИЕ ЦВЕТА ===")
ok(has('local preview = vgui.Create("DPanel", facPnl)'), "в админке есть предпросмотр корочки")
ok(has("Так корочка выглядит у игрока"), "предпросмотр подписан")
ok(has('draw.SimpleText(string.format("RGB %d, %d, %d"'), "показаны точные RGB")
ok(select(2, doc:gsub("math%.min%(255, coverCol%.r", "")) == 3,
    "подсветка обложки больше не выходит за 255 (цвет не «выцветал» на светлых пресетах)")
ok(has("local function badgeTemplate(rec)") and has("DOC.Templates.factions and DOC.Templates.factions[tostring(rec and rec.faction"),
    "корочка игрока берёт цвет из шаблона его организации")
ok(has("local coverCol = tpl.coverColor and Color(tpl.coverColor.r or 18"),
    "рендер удостоверения использует цвет шаблона")
ok(read("lua/autorun/sh_grm_physical_documents.lua"):find(
    'DOC.Templates and DOC.Templates.factions and DOC.Templates.factions[tostring(rec.faction or "")]', 1, true) ~= nil,
    "физический бланк в инвентаре берёт тот же шаблон (цвет совпадает)")

print(("\nDOC COVER COLOR: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
