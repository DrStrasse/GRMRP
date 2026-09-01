--[[ Живой прогон должностей организаций, фаза 1 (заказ владельца 27.08).

     Проверяется:
       1) три независимые оси: ранг, должность, узел структуры;
       2) вертикаль подчинения выводится из вида должности, а не из руки;
       3) ЕДИНЫЙ порядок выбора формы — тот самый баг, когда превью в меню
          персонажа расходилось с тем, во что игрока реально одевали;
       4) правила бодигрупп получили пятую ось и не потеряли старые правила;
       5) обратная совместимость: без должностей всё работает как раньше.

     Запуск: luajit tools/luatest/sim_faction_positions.lua ]]
local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

SERVER, CLIENT = false, false
function AddCSLuaFile() end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isfunction(v) return type(v) == "function" end
function IsValid(v) return istable(v) and v._valid ~= false end
function string.Trim(s) return (string.gsub(tostring(s or ""), "^%s*(.-)%s*$", "%1")) end
function string.Explode(sep, str)
    local out = {}
    for piece in string.gmatch(tostring(str or "") .. sep, "(.-)" .. sep) do out[#out + 1] = piece end
    return out
end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function table.HasValue(t, v) for _, x in pairs(t or {}) do if x == v then return true end end return false end
function table.Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
function table.Copy(t)
    if type(t) ~= "table" then return t end
    local o = {} for k, v in pairs(t) do o[k] = table.Copy(v) end return o
end
hook = { Add = function() end, Run = function() end }
GRM = {}

assert(loadfile("lua/autorun/sh_grm_faction_positions.lua"))()
local POS = GRM.Positions

-- Патрульная служба из концепции: отдел patrol, подотдел traffic.
local FAC = {
    DisplayName = "Полиция",
    Departments = { "patrol", "detectives" },
    Subdepartments = { traffic = { id = "traffic", name = "Дорожный надзор", parentDept = "patrol" } },
    Roles = { "lieutenant", "sergeant", "private" },
    Positions = {
        patrol_head   = { id = "patrol_head",   name = "Начальник патрульного отдела", node = "dept:patrol", kind = "head",   slots = 1 },
        patrol_deputy = { id = "patrol_deputy", name = "Заместитель начальника",       node = "dept:patrol", kind = "deputy", slots = 1 },
        inspector     = { id = "inspector",     name = "Инспектор",                    node = "dept:patrol", kind = "staff",  slots = 6 },
        chief         = { id = "chief",         name = "Начальник полиции",            node = "root",        kind = "head",   slots = 1 },
    },
    Members = {},
    Models = { { path = "models/faction.mdl" } },
    RoleModels = { sergeant = { { path = "models/rank_sergeant.mdl" } } },
    DepartmentModels = { patrol = { { path = "models/dept_patrol.mdl" } } },
    PositionModels = { patrol_head = { { path = "models/head_uniform.mdl" } } },
}
FAC.Subdepartments.traffic.models = { { path = "models/sub_traffic.mdl" } }
Factions = { ["Полиция"] = FAC }

-- Иванов — лейтенант и начальник отдела. Сидоров — сержант, рядовой инспектор.
local ivanov  = { Role = "lieutenant", Department = "patrol", Position = "patrol_head" }
local petrov  = { Role = "sergeant",   Department = "patrol", Position = "patrol_deputy" }
local sidorov = { Role = "sergeant",   Department = "patrol", Position = "inspector" }
local kozlov  = { Role = "private",    Department = "patrol", Position = "inspector" }
local trafficGuy = { Role = "private", Department = "patrol", Subdepartment = "traffic", Position = "" }
local plain   = { Role = "sergeant",   Department = "patrol" }   -- без должности вообще
FAC.Members = {
    ["1:char1"] = ivanov, ["2:char1"] = petrov, ["3:char1"] = sidorov,
    ["4:char1"] = kozlov, ["5:char1"] = trafficGuy, ["6:char1"] = plain,
}

print("\n=== 1. ТРИ НЕЗАВИСИМЫЕ ОСИ ===")
ok(POS.OfMember(FAC, ivanov).kind == "head", "лейтенант может быть начальником отдела")
ok(POS.OfMember(FAC, sidorov).kind == "staff", "сержант может быть рядовым инспектором")
ok(sidorov.Role == petrov.Role and POS.OfMember(FAC, sidorov).id ~= POS.OfMember(FAC, petrov).id,
   "два сержанта различаются должностью — раньше это было невозможно")
ok(POS.OfMember(FAC, kozlov).id == POS.OfMember(FAC, sidorov).id and kozlov.Role ~= sidorov.Role,
   "одна должность при разных званиях — оси не связаны")
ok(POS.OfMember(FAC, plain) == nil, "без должности участник законен (совместимость)")

print("\n=== 2. ВЕС ВЛАСТИ СЛЕДУЕТ ИЗ ВИДА, А НЕ ИЗ РУКИ ===")
ok(POS.Weight(POS.Get(FAC, "patrol_head")) > POS.Weight(POS.Get(FAC, "patrol_deputy")),
   "начальник весит больше заместителя")
ok(POS.Weight(POS.Get(FAC, "patrol_deputy")) > POS.Weight(POS.Get(FAC, "inspector")),
   "заместитель весит больше рядового сотрудника")
ok(POS.Weight({ kind = "мусор" }) == POS.KindWeight.staff, "неизвестный вид считается рядовым")

print("\n=== 3. ВЕРТИКАЛЬ ПОДЧИНЕНИЯ ===")
ok(POS.HeadOfNode(FAC, "dept:patrol").id == "patrol_head", "начальник узла определяется автоматически")
ok(POS.DeputyOfNode(FAC, "dept:patrol").id == "patrol_deputy", "заместитель узла находится по виду")
ok(POS.Commands(FAC, ivanov, sidorov) == true, "начальник командует своим инспектором")
ok(POS.Commands(FAC, sidorov, ivanov) == false, "инспектор не командует начальником")
ok(POS.Commands(FAC, petrov, sidorov) == true, "заместитель командует рядовым")
ok(POS.Commands(FAC, sidorov, kozlov) == false, "равные должности друг другом не командуют")
local sup = POS.SupervisorFor(FAC, sidorov)
ok(sup and sup.id == "patrol_head", "у инспектора начальник — глава его отдела", sup and sup.id)
local supHead = POS.SupervisorFor(FAC, ivanov)
ok(supHead and supHead.id == "chief", "у начальника отдела начальник — глава организации", supHead and supHead.id)

print("\n=== 4. УЗЛЫ И ЦЕПОЧКА ===")
ok(POS.NodeID("dept", "patrol") == "dept:patrol", "узел отдела")
ok(POS.MemberNode(trafficGuy) == "sub:traffic", "подотдел точнее отдела")
local chain = POS.NodeChain(FAC, "sub:traffic")
ok(chain[1] == "sub:traffic" and chain[2] == "dept:patrol" and chain[3] == "root",
   "цепочка идёт от подотдела к отделу и организации", table.concat(chain, " → "))

print("\n=== 5. ШТАТ ===")
local st = POS.Staffing(FAC, "inspector")
ok(st.taken == 2 and st.slots == 6 and st.free == 4, "занятые и свободные места считаются",
   st.taken .. "/" .. st.slots)
ok(POS.Staffing(FAC, "patrol_head").free == 0, "единственное место начальника занято")
ok(POS.HasFreeSlot(FAC, "patrol_head") == false, "второго начальника назначить нельзя")
ok(POS.HasFreeSlot(FAC, "inspector") == true, "на инспектора места есть")
FAC.Positions.nolimit = { id = "nolimit", name = "Без лимита", node = "root", kind = "staff", slots = 0 }
ok(POS.Staffing(FAC, "nolimit").unlimited == true, "slots = 0 означает «без лимита»")
FAC.Positions.nolimit = nil

print("\n=== 6. ЕДИНЫЙ ПОРЯДОК ФОРМЫ (тот самый баг) ===")
local list, why = POS.ResolveLoadout(FAC, ivanov, "models")
ok(why == "position:patrol_head", "должность сильнее всего: у начальника своя форма", why)
local _, why2 = POS.ResolveLoadout(FAC, trafficGuy, "models")
ok(why2 == "sub:traffic", "ПОДОТДЕЛ учитывается — раньше превью его теряло", why2)
local _, why3 = POS.ResolveLoadout(FAC, sidorov, "models")
ok(why3 == "dept:patrol", "без своей формы должности берётся форма отдела", why3)
local _, why4 = POS.ResolveLoadout(FAC, plain, "models")
ok(why4 == "dept:patrol", "отдел сильнее ранга", why4)
local roleOnly = { Role = "sergeant" }
local _, why5 = POS.ResolveLoadout(FAC, roleOnly, "models")
ok(why5 == "role:sergeant", "без отдела работает форма по званию", why5)
local bare = { Role = "private" }
local _, why6 = POS.ResolveLoadout(FAC, bare, "models")
ok(why6 == "faction", "иначе общая форма организации", why6)

print("\n=== 6б. ОБА МЕСТА ЗОВУТ ОДНУ ФУНКЦИЮ ===")
local function body(path)
    local fh = io.open(path, "rb") if not fh then return "" end
    local t = fh:read("*a") fh:close() return t
end
local fixes = body("lua/autorun/sh_faction_fixes.lua")
local charSrc = body("lua/autorun/sh_grm_character.lua")
ok(fixes:find("GRM.Positions.ResolveLoadout", 1, true) ~= nil,
   "выдача формы в мир идёт через общий расчёт")
ok(charSrc:find("GRM.Positions.ResolveLoadout", 1, true) ~= nil,
   "превью в меню персонажа идёт через тот же расчёт")
ok(charSrc:find("factionPosition", 1, true) ~= nil, "должность уходит в меню персонажа")

print("\n=== 7. ПРАВИЛА БОДИГРУПП: ПЯТАЯ ОСЬ ===")
GRM.BGRules = nil
assert(loadfile("lua/autorun/sh_grm_bodygroup_rules.lua"))()
local BG = GRM.BGRules
local MODEL = "models/head_uniform.mdl"
ok(select(2, pcall(function() return BG.Key(MODEL, "Полиция", "patrol", "sergeant", "inspector") end)) ~= nil
   or BG.Key(MODEL, "Полиция", "patrol", "sergeant", "inspector"):find("|inspector", 1, true) ~= nil,
   "ключ правила содержит должность")
ok(BG.UpgradeKey("models/a.mdl|Полиция|patrol|sergeant") == "models/a.mdl|Полиция|patrol|sergeant|",
   "старый ключ из четырёх частей дочитывается пятой пустой",
   BG.UpgradeKey("models/a.mdl|Полиция|patrol|sergeant"))
ok(BG.UpgradeKey("a|b|c|d|e") == "a|b|c|d|e", "новый ключ не портится")

BG.Rules = BG.UpgradeRules({
    -- старый формат: правило для всех сержантов организации
    [MODEL .. "|Полиция|patrol|sergeant"] = { ["3"] = { mode = "hide", value = 0 } },
    -- новый формат: у начальника отдела нашивка на месте
    [BG.Key(MODEL, "Полиция", "patrol", "", "patrol_head")] = { ["3"] = { mode = "lock", value = 1 } },
})
local rulesSergeant = BG.Resolve(MODEL, { faction = "Полиция", dept = "patrol", role = "sergeant" })
ok(rulesSergeant[3] and rulesSergeant[3].mode == "hide",
   "старое правило по званию продолжает работать после миграции")
local rulesHead = BG.Resolve(MODEL, { faction = "Полиция", dept = "patrol", role = "sergeant", position = "patrol_head" })
ok(rulesHead[3] and rulesHead[3].mode == "lock",
   "должность перекрывает звание: у начальника нашивка видна", rulesHead[3] and rulesHead[3].mode)
local rulesPlain = BG.Resolve(MODEL, { faction = "Полиция", dept = "patrol", role = "sergeant", position = "inspector" })
ok(rulesPlain[3] and rulesPlain[3].mode == "hide",
   "у рядового инспектора с тем же званием строка скрыта")

print("\n=== 8. СОВМЕСТИМОСТЬ ===")
local clean = { DisplayName = "Без должностей", Departments = { "main" }, Roles = { "member" },
    Members = { ["9:char1"] = { Role = "member", Department = "main" } },
    Models = { { path = "models/x.mdl" } } }
ok(POS.OfMember(clean, clean.Members["9:char1"]) == nil, "организация без должностей живёт как раньше")
local _, whyClean = POS.ResolveLoadout(clean, clean.Members["9:char1"], "models")
ok(whyClean == "faction", "и форму получает по-старому", whyClean)
ok(POS.SupervisorFor(clean, clean.Members["9:char1"]) == nil, "без должностей начальника нет")
ok(POS.EnsureDefaults(clean) == true and istable(clean.Positions),
   "нормализация только добавляет пустой список, ничего не создавая")
ok(table.Count(clean.Positions) == 0, "должности сами не появляются")

print(("\n=== ИТОГ: успешно %d, провалено %d ===\n"):format(pass, fail))
if fail > 0 then os.exit(1) end
