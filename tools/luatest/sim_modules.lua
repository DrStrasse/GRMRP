--[[ Живой прогон общего реестра модулей и единой точки права
     (заказ владельца 22.08: «все модули должны знать друг друга»).
     Грузятся РЕАЛЬНЫЕ lua/autorun/sh_03b_grm_modules.lua и sh_03_grm_access.lua.
     Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_modules.lua ]]
local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

SERVER, CLIENT = true, false
function AddCSLuaFile() end
function IsValid(v) return type(v) == "table" and v._valid ~= false end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isnumber(v) return type(v) == "number" end
function isfunction(v) return type(v) == "function" end
function ErrorNoHalt() end
function string.Trim(s) return (string.gsub(tostring(s or ""), "^%s*(.-)%s*$", "%1")) end
HUD_PRINTCONSOLE = 2

local HOOKS = {}
hook = {
    Add = function(e, n, fn) HOOKS[e] = HOOKS[e] or {} HOOKS[e][n] = fn end,
    Run = function(e, ...) for _, fn in pairs(HOOKS[e] or {}) do fn(...) end end,
    Remove = function() end,
}
local CMDS = {}
concommand = { Add = function(n, fn) CMDS[n] = fn end }
player = { GetAll = function() return {} end }
local SPREADS = {}
GRM = {
    Perf = {
        Spread = function(id, list, fn) SPREADS[id] = true for _, v in ipairs(list) do fn(v) end return true end,
        -- настоящий порядок аргументов слоя: (key, delay, fn)
        Coalesce = function(_, delay, fn)
            if isfunction(delay) and not isfunction(fn) then delay, fn = fn, delay end
            if isfunction(fn) then fn() end
        end,
        Players = function() return {} end,
    },
}

assert(loadfile("lua/autorun/sh_03b_grm_modules.lua"))()
local M = GRM.Modules

print("\n=== 1. МОДУЛИ ПРЕДСТАВЛЯЮТСЯ ДРУГ ДРУГУ ===")
ok(isfunction(M.Register) and isfunction(M.Get) and isfunction(M.Has), "реестр объявлен")
local refreshed = {}
M.Register("access", { label = "Доступ", version = "1.1.0" })
M.Register("plates", {
    label = "Номерные знаки", version = "1.2.0", Depends = { "access" },
    Refresh = function(ply, reason) refreshed[#refreshed + 1] = "plates:" .. tostring(reason) end,
    Status = function() return "номеров: 7" end,
})
M.Register("fleet", {
    label = "Автопарк", version = "1.0.0", Depends = { "access", "vehicles" },
    Refresh = function() refreshed[#refreshed + 1] = "fleet" end,
})
ok(M.Has("plates") and M.Get("plates").label == "Номерные знаки", "модуль виден другим по имени")
ok(M.Has("нетакого") == false, "чужого модуля в реестре нет")

print("\n=== 2. ЗАВИСИМОСТИ ВИДНЫ ===")
ok(#M.MissingDeps("plates") == 0, "у знаков зависимость «access» на месте")
local miss = M.MissingDeps("fleet")
ok(#miss == 1 and miss[1] == "vehicles", "автопарк честно сообщает о недостающем слое", table.concat(miss, ","))
M.Register("vehicles", { label = "Транспорт", version = "1.0.0" })
ok(#M.MissingDeps("fleet") == 0, "слой появился — претензий нет")

print("\n=== 3. ОДНО СОБЫТИЕ ОБНОВЛЯЕТ ВСЕХ ===")
refreshed = {}
hook.Run("GRM_AccessChanged", "faction_perms")
ok(#refreshed == 2, "по смене прав обновились оба модуля со снимками", #refreshed)
ok(SPREADS["modules.refresh"] == true, "обход реестра идёт порционно через GRM.Perf.Spread")
refreshed = {}
hook.Run("GRM_FactionRoleChanged")
ok(#refreshed == 2, "смена должности тоже поднимает шину")
refreshed = {}
M.Changed("manual")
ok(#refreshed == 2, "любой модуль может поднять шину сам")

print("\n=== 4. ОТЧЁТ И КОМАНДЫ ===")
local rows = M.Report()
ok(#rows == 4, "в отчёте все зарегистрированные модули", #rows)
local platesRow
for _, r in ipairs(rows) do if r.id == "plates" then platesRow = r end end
ok(platesRow and platesRow.status == "номеров: 7", "статус модуля попадает в отчёт", platesRow and platesRow.status)
ok(platesRow and platesRow.refresh == true, "видно, кто умеет обновляться")
ok(isfunction(CMDS["grm_modules"]) and isfunction(CMDS["grm_modules_refresh"]),
   "команды реестра объявлены")

print("\n=== 5. ЕДИНАЯ ТОЧКА ПРАВА ===")
local ACC = (function()
    local f = io.open("lua/autorun/sh_03_grm_access.lua", "rb")
    local t = f:read("*a") f:close() return t
end)()
local function has(n) return ACC:find(n, 1, true) ~= nil end
ok(has("function A.FactionPermName(capability)"),
   "capability знает своё имя в доступах организации (точки → подчёркивания)")
ok(has('A.RegisterProvider("grm_faction_perms", 40'),
   "право организации спрашивается автоматически")
ok(has('A.RegisterProvider("grm_pcboard_level", 30'),
   "уровень госбазы спрашивается автоматически")
ok(has("function A.Why(ply, capability)") and has('concommand.Add("grm_access_check"'),
   "есть команда «почему нет права»")

local plates = (function()
    local f = io.open("lua/autorun/sh_grm_plates.lua", "rb")
    local t = f:read("*a") f:close() return t
end)()
ok(plates:find('factionPerm = "plates_issue"', 1, true) ~= nil
   and plates:find("levels = { police = true, military = true, admin = true }", 1, true) ~= nil,
   "знаки объявили источники права прямо в capability")
ok(plates:find('GRM.Modules.Register("plates"', 1, true) ~= nil, "знаки представились реестру")

for _, file in ipairs({
    { "lua/autorun/sh_grm_fleet.lua", 'GRM.Modules.Register("fleet"' },
    { "lua/autorun/sh_grm_garage.lua", 'GRM.Modules.Register("garage"' },
    { "lua/autorun/sh_grm_vehicles.lua", 'GRM.Modules.Register("vehicles"' },
    { "lua/autorun/server/sv_grm_alarm.lua", 'GRM.Modules.Register("alarm"' },
    { "lua/autorun/sh_grm_doors.lua", 'GRM.Modules.Register("doors"' },
}) do
    local src = (function()
        local f = io.open(file[1], "rb")
        local t = f:read("*a") f:close() return t
    end)()
    ok(src:find(file[2], 1, true) ~= nil, "в реестре: " .. file[1]:match("([^/]+)$"))
end

print("\n=== 6. СТАРЫЕ МОДУЛИ ТОЖЕ В РЕЕСТРЕ ===")
for _, file in ipairs({
    { "lua/autorun/sh_grm_mobile.lua", 'GRM.Modules.Register("mobile"' },
    { "lua/autorun/sh_grm_phone_access.lua", 'GRM.Modules.Register("phone_access"' },
    { "lua/autorun/sh_grm_cctv_access.lua", 'GRM.Modules.Register("cctv"' },
    { "lua/autorun/sh_grm_wanted_board.lua", 'GRM.Modules.Register("wanted"' },
    { "lua/autorun/sh_grm_arrest.lua", 'GRM.Modules.Register("arrest"' },
    { "lua/autorun/sh_grm_minimap.lua", 'GRM.Modules.Register("minimap"' },
    { "lua/autorun/sh_spawn_points.lua", 'GRM.Modules.Register("spawnpoints"' },
}) do
    local src = (function()
        local f = io.open(file[1], "rb")
        local t = f:read("*a") f:close() return t
    end)()
    ok(src:find(file[2], 1, true) ~= nil, "в реестре: " .. file[1]:match("([^/]+)$"))
end

print("\n=== 7. СВЯЗЬ И НАБЛЮДЕНИЕ ЗНАЮТ ОБЩИЕ ПРАВА ===")
local phone = (function()
    local f = io.open("lua/autorun/sh_grm_phone_access.lua", "rb")
    local t = f:read("*a") f:close() return t
end)()
ok(phone:find('GRM.Access.Register("phone.equipment"', 1, true) ~= nil
   and phone:find('GRM.Access.Register("phone.wiretap"', 1, true) ~= nil,
   "у связи и прослушки есть capability с источниками")
ok(phone:find('GRM.Access.Can(ply, "phone.equipment")', 1, true) ~= nil,
   "проверка доступа к оборудованию учитывает общий слой, а не только свою таблицу")
local cctv = (function()
    local f = io.open("lua/autorun/sh_grm_cctv_access.lua", "rb")
    local t = f:read("*a") f:close() return t
end)()
ok(cctv:find('GRM.Access.Register("cctv.view"', 1, true) ~= nil, "видеонаблюдение объявило права")
local perms = (function()
    local f = io.open("lua/autorun/sh_grm_faction_perms.lua", "rb")
    local t = f:read("*a") f:close() return t
end)()
ok(perms:find("phone_wiretap = ", 1, true) ~= nil and perms:find("cctv_view = ", 1, true) ~= nil,
   "эти права появились в /factions → «Доступы»")

print("\n=== 8. ОПТИМИЗАЦИЯ ЭТОГО ХОДА ===")
local cuffs = (function()
    local f = io.open("lua/autorun/server/sv_grm_handcuffs.lua", "rb")
    local t = f:read("*a") f:close() return t
end)()
ok(cuffs:find("timer.Create(stunName, math.max(0.1, seconds), 1, endStun)", 1, true) ~= nil
   and cuffs:find('timer.Create("GRM_Stun_" .. target:EntIndex(), 0.2, 0', 1, true) == nil,
   "конец оглушения ждём одним таймером, а не опросом 5 раз в секунду")
local radio = (function()
    local f = io.open("lua/autorun/sh_grm_radionet.lua", "rb")
    local t = f:read("*a") f:close() return t
end)()
ok(radio:find('timer.Create("GRM_RN_Watch", 3, 0', 1, true) ~= nil
   and radio:find("local function radioNetEmpty()", 1, true) ~= nil,
   "сторож радиосети реже и не крутится на карте без раций")
ok(radio:find("function RN.EnsureCrackle()", 1, true) ~= nil
   and radio:find('if not next(fxTalkers) then timer.Remove("GRM_RN_Crackle") return end', 1, true) ~= nil,
   "треск помех живёт только во время разговора")

print(("\nMODULES: %d/%d, провалов: %d"):format(pass, pass + fail, fail))
if fail > 0 then os.exit(1) end
