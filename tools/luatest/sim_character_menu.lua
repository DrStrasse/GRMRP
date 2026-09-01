--[[ Живой прогон меню персонажа v2 (заказ владельца 22.08):
     окно на весь экран без крестика, мир закрыт до выбора персонажа,
     игрок ждёт за картой и после выбора попадает на точку спавна,
     описание персонажа живёт в его записи.
     Чистые функции грузятся из НАСТОЯЩЕГО lua/autorun/sh_grm_character.lua,
     остальное проверяется по контракту исходника.
     Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_character_menu.lua ]]
local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

SERVER, CLIENT = false, false
function AddCSLuaFile() end
function IsValid(v) return type(v) == "table" and v._valid ~= false end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isfunction(v) return type(v) == "function" end
function string.Trim(s) return (string.gsub(tostring(s or ""), "^%s*(.-)%s*$", "%1")) end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function Vector(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
hook = { Add = function() end, Run = function() end }
GRM = {}

assert(loadfile("lua/autorun/sh_grm_character.lua"))()
local CH = GRM.Char

local src = (function()
    local f = io.open("lua/autorun/sh_grm_character.lua", "rb")
    local t = f:read("*a") f:close() return t
end)()
local function has(n) return src:find(n, 1, true) ~= nil end

print("\n=== 1. ОПИСАНИЕ ПЕРСОНАЖА ===")
ok(isfunction(CH.CleanDesc), "чистая функция описания объявлена")
ok(CH.CleanDesc("  Ветеран войны  ") == "Ветеран войны", "пробелы по краям убираются",
   CH.CleanDesc("  Ветеран войны  "))
ok(CH.CleanDesc("Строка\1\2с мусором") == "Строкас мусором", "управляющие символы вырезаются",
   CH.CleanDesc("Строка\1\2с мусором"))
ok(CH.Len(CH.CleanDesc(("Я"):rep(500))) == CH.DescMax, "длина режется по СИМВОЛАМ, а не байтам",
   CH.Len(CH.CleanDesc(("Я"):rep(500))))
ok(CH.CleanDesc(nil) == "", "пустое описание — законный ответ")
ok(has("function CH.SetDesc(ply, text, slot)") and has('saveChars("setdesc")'),
   "описание сохраняется в записи персонажа")
ok(has("GRM.RPDesc.SetFor(ply, tostring(c.desc"), "при выборе персонажа описание уходит в RPDesc")

print("\n=== 2. ЛИМБ ДО ВЫБОРА ===")
ok(has("CH.LimboPos = Vector(0, 0, 15500)"), "точка ожидания вынесена за карту")
ok(has("function CH.SendToLimbo(ply)") and has("ply:StripWeapons()") and has("ply:SetNoDraw(true)")
   and has("ply:SetNotSolid(true)") and has("ply:GodEnable()"),
   "в лимбе игрок без оружия, без модели, без коллизии и неуязвим")
ok(has("if locked == true then\n            CH.SendToLimbo(ply)"),
   "лимб включается вместе с блокировкой выбора")
--[[ Переработано 27.08 (конвейер входа GRM.Entry). Выпуск из лимба
     больше не мгновенный: при первичном входе управление передаётся
     конвейеру, который сначала спросит точку входа и только потом
     выпустит в мир. Подробности — sim_entry_pipeline.lua. ]]
ok(has("CH.ConfirmedToEntry(ply)") and has("if ply.GRMCharLimbo then CH.ReleaseFromLimbo(ply) end"),
   "подтверждение персонажа передаёт управление конвейеру входа")

print("\n=== 3. ТОЧКА СПАВНА ПОСЛЕ ВЫБОРА ===")
ok(has("function CH.PlaceOnSpawnPoint(ply)") and has("_G.GetSpawnPointForPlayer(ply)"),
   "точка берётся из системы точек спавна (/spawnmenu)")
ok(has('ents.FindByClass("info_player_start")'), "если точек нет — запасной вариант карты")
--[[ Хук GRM_Char_PlaceAfterSelect удалён намеренно (жалоба владельца
     27.08 «нажми любую — ничего не происходит»): он ставил игрока на
     фракционную точку после Spawn и затирал выбранную точку входа.
     Теперь позицию выставляет ровно один владелец — GRM.Entry. ]]
ok(not has('hook.Add("PlayerSpawn", "GRM_Char_PlaceAfterSelect"'),
   "затирающий позицию хук убран: точку ставит только конвейер входа")
ok(has("function CH.FinishEntry(ply)"),
   "спавн вынесен в CH.FinishEntry — её зовёт конвейер после выбора точки")

print("\n=== 4. ОКНО НА ВЕСЬ ЭКРАН И БЕЗ ВЫХОДА ===")
ok(has("f:SetSize(ScrW(), ScrH())") and has("f:SetPos(0, 0)"), "окно занимает весь экран")
ok(has("f:ShowCloseButton(false)") and has("if mandatory then\n            f.Close = function() end"),
   "обязательное окно не закрывается крестиком")
ok(has("if mandatory and key == KEY_ESCAPE then return true end"), "ESC окно не закрывает")
ok(has('hook.Add("OnPauseMenuShow", "GRM_Char_BlockPause"'), "игровое меню по ESC тоже заблокировано")
ok(has('hook.Add("Think", "GRM_Char_KeepMenu"'), "если окно всё же пропало — оно возвращается само")
ok(has("if IsValid(CH._frame) then CH._frame:Remove() CH._frame = nil end"),
   "второе окно не наслаивается на первое")
-- 22.08: кнопки закрытия в окне быть не должно (прямое требование)
ok(not has('draw.SimpleText("ЗАКРЫТЬ"'), "кнопки «ЗАКРЫТЬ» в меню персонажа нет")
ok(has("Кнопки закрытия в окне НЕТ"), "решение зафиксировано в коде комментарием")

print("\n=== 4б. КОНФЛИКТ С ЭКРАНОМ ВХОДА ===")
ok(has("if GRM.Loading and GRM.Loading.IsLoading and GRM.Loading.IsLoading(ply) then")
   and has("ply.GRMCharMenuPending = previewSlot or true"),
   "сервер не шлёт окно, пока игрок на загрузочном экране — запрос откладывается")
ok(has('hook.Add("GRM_LoadingFinished", "GRM_Char_MenuAfterLoading"'),
   "после кнопки «НАЧАТЬ ИГРАТЬ» отложенное окно уходит игроку")
ok(has("if GRM.Loading and GRM.Loading.Shown then") and has("CH._afterLoading = istable(payload)"),
   "клиент придерживает снимок, если экран входа ещё висит")
ok(has('hook.Add("GRM_LoadingClosed", "GRM_Char_ShowAfterLoading"'),
   "как только экран закрылся — придержанное окно показывается")
local ld = (function()
    local f = io.open("lua/autorun/sh_grm_loading.lua", "rb")
    local t = f:read("*a") f:close() return t
end)()
ok(ld:find("if GRM.Char and IsValid(GRM.Char._frame) then return end", 1, true) ~= nil,
   "и наоборот: экран входа не ложится поверх открытого окна персонажа")
ok(ld:find('hook.Run("GRM_LoadingClosed")', 1, true) ~= nil, "о закрытии экрана сообщается хуком")

print("\n=== 5. МИР ЗАКРЫТ ДО ВЫБОРА ===")
ok(has('hook.Add("HUDShouldDraw", "GRM_Char_HideHUD"'), "весь HUD скрыт (в т.ч. выбор оружия)")
ok(has('hook.Add("PlayerBindPress", "GRM_Char_BlockBinds"'), "хот-бары и бинды не срабатывают")
ok(has('hook.Add("SpawnMenuOpen", "GRM_Char_BlockSpawnMenu"'), "Q-меню закрыто")
ok(has('hook.Add("StartCommand", "GRM_Char_BlockInput"'), "движение и кнопки на сервере обнуляются")

print("\n=== 5б. ОРУЖИЕ ТОЛЬКО ПОСЛЕ ПОЯВЛЕНИЯ ===")
ok(has('hook.Add("PlayerLoadout", "GRM_Char_BlockLoadout"') and has("return true"),
   "стандартный набор (физган, тулган) в лимбе не выдаётся")
ok(has("if _G.ApplyWeaponsToPlayer then"),
   "набор выдаётся после постановки на точку спавна")
local fixes = (function()
    local fh = io.open("lua/autorun/sh_faction_fixes.lua", "rb")
    local t = fh:read("*a") fh:close() return t
end)()
ok(fixes:find('if ply:GetNWBool("GRM_CharacterPending", false) then', 1, true) ~= nil,
   "выдача оружия из /weapons_admin ждёт выбора персонажа")

print("\n=== 5в. ОКНО ЗАКРЫВАЕТСЯ ПОСЛЕ ВЫБОРА ===")
ok(has("net.Receive(NET_CLOSE, function()") and has("CH._frame:Remove()"),
   "по команде сервера окно сносится, а не Close (у обязательного окна он отключён)")
ok(has("CH._reopenAt = RealTime() + 2"), "сторож окна не открывает его обратно сразу после закрытия")

print("\n=== 6. ЖИВАЯ МОДЕЛЬ И ВКЛАДКИ ===")
ok(has("local function applyPreview(fullModel)") and has("ent:SetBodygroup(tonumber(g) or 0"),
   "изменения применяются к модели сразу, без пересборки окна")
ok(has('addTab("look", "ВНЕШНОСТЬ")') and has('addTab("body", "ТЕЛОСЛОЖЕНИЕ")')
   and has('addTab("info", "ИМЯ И ОПИСАНИЕ")'), "три вкладки настроек")
ok(has("rebuildBodygroups = function()") and has("ent:GetBodygroupCount(i)"),
   "бодигруппы читаются с реальной модели")
ok(has("preview.OnCursorMoved = function(self, x)"), "модель крутится мышью, без ползунков")
ok(not has("skinSlider"), "лишние ползунки убраны")

print("\n=== 7. СОХРАНЕНИЕ ===")
ok(has("net.WriteTable({\n                    slot = activeSlot or \"char1\", name = draft.name, desc = draft.desc,"),
   "имя, описание и внешность уходят одним пакетом")
ok(has('if d.desc ~= nil then CH.SetDesc(ply, d.desc, d.slot) end'), "сервер принимает описание")

local f4 = (function()
    local fh = io.open("lua/autorun/sh_grm_f4menu.lua", "rb")
    local t = fh:read("*a") fh:close() return t
end)()
ok(f4:find('mkBtn(b2, "МЕНЮ ПЕРСОНАЖА"', 1, true) ~= nil, "в F4 есть кнопка «МЕНЮ ПЕРСОНАЖА»")

print(("\nCHARACTER MENU: %d/%d, провалов: %d"):format(pass, pass + fail, fail))
if fail > 0 then os.exit(1) end
