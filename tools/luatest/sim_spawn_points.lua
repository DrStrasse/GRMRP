-- sim_spawn_points.lua — проверка системы точек спавна (находка 157):
-- единый формат сохранения, миграция легаси, валидация ролей/отделов по
-- factions.json, приоритеты выбора точки для игрока.
-- Грузит РЕАЛЬНЫЙ lua/autorun/sh_spawn_points.lua (SERVER=true).
local pass, fail = 0, 0
local function ok(v, n) if v then pass = pass + 1 print("  ok  " .. n) else fail = fail + 1 print("  FAIL " .. n) end end

SERVER, CLIENT = true, false
function AddCSLuaFile() end
function isstring(v) return type(v) == "string" end
function istable(v) return type(v) == "table" end
function isfunction(v) return type(v) == "function" end
function IsValid(v) return v ~= nil and (type(v) == "table" and v.__valid ~= false or type(v) == "userdata") end
function CurTime() return 1000 end
function SysTime() return 1000 end
function table.Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
function math.random() return 1 end
math.Clamp = math.Clamp or function(v, a, b) return math.max(a, math.min(b, v)) end
function print(...) local a = {} for i = 1, select("#", ...) do a[i] = tostring(select(i, ...)) end io.write(table.concat(a, " "), "\n") end

local H = { hooks = {}, netrecv = {}, concommands = {}, seq = {} }
hook = { Add = function(n, id, fn) H.hooks[n] = H.hooks[n] or {} H.hooks[n][id] = fn end }
timer = { Create = function() end, Simple = function() end }
concommand = { Add = function(n, fn) H.concommands[n] = fn end }
util = { AddNetworkString = function() end }
net = {
  Start = function() end, WriteString = function() end, WriteVector = function() end,
  WriteAngle = function() end, WriteInt = function() end, Send = function() end,
  SendToServer = function() end, ReadString = function() return "" end, ReadVector = function() end,
  ReadAngle = function() end, ReadInt = function() return 0 end,
  Receive = function(m, fn) H.netrecv[m] = fn end,
}
game = { GetMap = function() return "gm_test" end }
player = { GetAll = function() return {} end }

-- ── мок файлов: data/<path> → содержимое ──
local files = {}
file = {
  Exists = function(p) return files[p] ~= nil end,
  Read = function(p) return files[p] end,
  Write = function(p, s) files[p] = s end,
}
-- честный JSON (достаточно для наших структур)
local function encode(v, indent)
  indent = indent or 0
  local pad = string.rep("\t", indent)
  local t = type(v)
  if t == "number" then return string.format("%g", v)
  elseif t == "string" then return string.format("%q", v)
  elseif t == "boolean" then return tostring(v)
  elseif t == "table" then
    local isArr = true
    for k in pairs(v) do if type(k) ~= "number" or k < 1 or k > #v then isArr = false break end end
    local parts = {}
    if isArr and #v > 0 then
      for i = 1, #v do parts[#parts + 1] = encode(v[i], indent + 1) end
      return "[\n" .. string.rep("\t", indent + 1) .. table.concat(parts, ",\n" .. string.rep("\t", indent + 1)) .. "\n" .. pad .. "]"
    end
    for k, val in pairs(v) do parts[#parts + 1] = string.format("%q: %s", tostring(k), encode(val, indent + 1)) end
    return "{\n" .. string.rep("\t", indent + 1) .. table.concat(parts, ",\n" .. string.rep("\t", indent + 1)) .. "\n" .. pad .. "}"
  end
  return "null"
end
util.TableToJSON = function(t) return encode(t) end
local function jsonParse(s, pos)
  local c = s:sub(pos, pos)
  if c == "{" then
    local t, i = {}, pos + 1
    while s:sub(i, i) ~= "}" do
      while s:sub(i, i):match("[%s,\n\t]") do i = i + 1 end
      if s:sub(i, i) == "}" then break end
      local k, v
      if s:sub(i, i) == "[" then
        local arr, j = {}, i + 1
        while s:sub(j, j) ~= "]" do
          while s:sub(j, j):match("[%s,\n\t]") do j = j + 1 end
          if s:sub(j, j) == "]" then break end
          local val, nj = jsonParse(s, j)
          arr[#arr + 1] = val
          j = nj
        end
        return arr, j + 1
      else
        k, i = jsonParse(s, i)
        while s:sub(i, i):match("[%s:]") do i = i + 1 end
        v, i = jsonParse(s, i)
        t[k] = v
      end
    end
    return t, i + 1
  elseif c == "[" then
    local arr, i = {}, pos + 1
    while s:sub(i, i) ~= "]" do
      while s:sub(i, i):match("[%s,\n\t]") do i = i + 1 end
      if s:sub(i, i) == "]" then break end
      local val, ni = jsonParse(s, i)
      arr[#arr + 1] = val
      i = ni
    end
    return arr, i + 1
  elseif c == '"' then
    local i = pos + 1
    local out = {}
    while s:sub(i, i) ~= '"' do out[#out + 1] = s:sub(i, i) i = i + 1 end
    return table.concat(out), i + 1
  else
    local num = s:match("^-?%d+%.?%d*", pos)
    if num then return tonumber(num), pos + #num end
    if s:sub(pos, pos + 3) == "true" then return true, pos + 4 end
    if s:sub(pos, pos + 4) == "false" then return false, pos + 5 end
    return nil, pos + 1
  end
end
util.JSONToTable = function(s)
  local ok, t = pcall(jsonParse, s, 1)
  return ok and t or nil
end

-- ── игроки ──ки ──
local PMT = {}
PMT.__index = function(t, k)
  if k == "SteamID" then return function(s) return s.sid end
  elseif k == "SteamID64" then return function(s) return s.s64 end
  elseif k == "IsSuperAdmin" then return function() return true end
  elseif k == "SetPos" then return function() end
  elseif k == "SetAngles" then return function() end
  elseif k == "SetEyeAngles" then return function() end
  elseif k == "PrintMessage" then return function() end
  end
  return nil
end
local function mkPly(sid, s64) return setmetatable({ sid = sid, s64 = s64 }, PMT) end
local V = {}; V.__index = V
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V) end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end

-- ── фракции из «factions.json» ──
local BossSid = "STEAM_0:1:1"
local CopSid = "STEAM_0:1:2"
Factions = {
  ["Полиция"] = {
    Leader = BossSid, LeaderRoleName = "Лидер",
    Roles = { "Лидер", "Офицер", "Кадет" },
    Departments = { "Основной", "Патруль" },
    Members = {
      [BossSid] = { Role = "Лидер", Department = "Основной" },
      [CopSid] = { Role = "Офицер", Department = "Патруль" },
    },
  },
}
GRM = GRM or {}
GRM.Identity = {
  CharacterKey = function(p) return p.s64 .. ":char1" end,
  FactionMember = function(f, ply)
    return f.Members[ply.sid] or f.Members[ply.s64]
  end,
}

-- ══════════════ ЗАГРУЗКА МОДУЛЯ ══════════════
dofile("lua/autorun/sh_spawn_points.lua")
ok(AddGlobalSpawnPoint ~= nil and AddSpawnPointForRole ~= nil, "модуль загружен, API на месте")

-- ══════════════ 1. ЕДИНЫЙ ФОРМАТ СОХРАНЕНИЯ ══════════════
-- Добавляем фракционную точку — файл должен содержать объект {points,roles,departments}
local okAdd, errAdd = AddSpawnPointForFaction("Полиция", Vector(100, 200, 300), Angle(0, 90, 0))
ok(okAdd == true, "фракционная точка добавлена")
local rawF = files["spawn_points_factions_gm_test.json"]
ok(rawF ~= nil and rawF:find("points", 1, true) ~= nil, "файл фракций пишется в едином формате (points)")
ok(rawF:find("departments", 1, true) ~= nil and rawF:find("roles", 1, true) ~= nil, "файл содержит roles и departments")

-- Роль/отдел — тоже в том же файле, ничего не затирается
AddSpawnPointForRole("Полиция", "Офицер", Vector(10, 10, 10), Angle(0, 0, 0))
AddSpawnPointForDepartment("Полиция", "Патруль", Vector(20, 20, 20), Angle(0, 0, 0))
rawF = files["spawn_points_factions_gm_test.json"]
ok(rawF:find("Офицер", 1, true) ~= nil and rawF:find("Патруль", 1, true) ~= nil, "роль и отдел дописаны в тот же файл")
ok(rawF:find('"points"', 1, true) ~= nil and rawF:find('"roles"', 1, true) ~= nil and rawF:find('"departments"', 1, true) ~= nil, "все три ключа на месте (points/roles/departments)")

-- ══════════════ 2. ПЕРЕЗАГРУЗКА ПОСЛЕ «РЕСТАРТА» ══════════════
-- (модуль уже загружен; эмулируем рестарт сбросом таблиц фракции и reload)
Factions["Полиция"].SpawnPoints = nil
Factions["Полиция"].RoleSpawnPoints = nil
Factions["Полиция"].DepartmentSpawnPoints = nil
hook.Run = function() end
-- reload вызывается в InitPostEntity-хуке; дёрнем напрямую через хук
local reloadHook = nil
for _, fn in pairs(H.hooks["InitPostEntity"] or {}) do reloadHook = fn end
ok(reloadHook ~= nil, "хук перезагрузки InitPostEntity на месте")
reloadHook()

local f = Factions["Полиция"]
ok(istable(f.SpawnPoints) and #f.SpawnPoints == 1, "после рестарта фракционные точки восстановлены (1)")
ok(istable(f.RoleSpawnPoints) and istable(f.RoleSpawnPoints["Офицер"]) and #f.RoleSpawnPoints["Офицер"] == 1, "после рестарта точки роли восстановлены")
ok(istable(f.DepartmentSpawnPoints) and istable(f.DepartmentSpawnPoints["Патруль"]) and #f.DepartmentSpawnPoints["Патруль"] == 1, "после рестарта точки отдела восстановлены")

-- ══════════════ 3. МИГРАЦИЯ ЛЕГАСИ-ФОРМАТА ══════════════
files["spawn_points_factions_gm_test.json"] = encode({ ["Полиция"] = { { pos = { x = 5, y = 6, z = 7 }, ang = { p = 0, y = 0, r = 0 } } } })
Factions["Полиция"].SpawnPoints = nil
Factions["Полиция"].RoleSpawnPoints = nil
Factions["Полиция"].DepartmentSpawnPoints = nil
reloadHook()
ok(istable(Factions["Полиция"].SpawnPoints) and #Factions["Полиция"].SpawnPoints == 1, "легаси-массив мигрирован в points")
ok(istable(Factions["Полиция"].RoleSpawnPoints) and istable(Factions["Полиция"].DepartmentSpawnPoints), "легаси: роли/отделы инициализированы пустыми")
ok(files["spawn_points_factions_gm_test.json"]:find('"points"', 1, true) ~= nil, "легаси-файл пересохранён в единый формат")

-- ══════════════ 4. ВАЛИДАЦИЯ РОЛЕЙ/ОТДЕЛОВ ПО factions.json ══════════════
local okBad, errBad = AddSpawnPointForRole("Полиция", "Космонавт", Vector(1, 1, 1), Angle(0, 0, 0))
ok(okBad == false and tostring(errBad):find("не существует", 1, true) ~= nil, "несуществующая роль отклонена с сообщением")
local okBadD, errBadD = AddSpawnPointForDepartment("Полиция", "Космос", Vector(1, 1, 1), Angle(0, 0, 0))
ok(okBadD == false and tostring(errBadD):find("не существует", 1, true) ~= nil, "несуществующий отдел отклонён с сообщением")
ok(AddSpawnPointForRole("Полиция", "Лидер", Vector(1, 1, 1), Angle(0, 0, 0)) == true, "роль лидера разрешена")

-- ══════════════ 5. buildSpawnData: meta из factions.json ══════════════
-- через net-обработчик (отправка данных админу)
local sentData = nil
local origStart = net.Start
net.Start = function() end
net.Send = function() end
-- перехват net.Send невозможен без реального net; проверим через сохранённый payload-хук:
-- вызовем sendSpawnDataToPlayer не можем (local) — проверим через SpawnAdmin_OpenMenu
-- мок: заменим net.Send чтобы поймать таблицу
local captured = nil
net.Send = function() captured = sentData end
net.WriteTable = function(t) sentData = t end
-- переопределим через pcall на прямом вызове внутренностей: используем net.Receive
-- модуль регистрирует net.Receive сам; наш H.netrecv его получил
local openRecv = H.netrecv["SpawnAdmin_OpenMenu"]
ok(openRecv ~= nil, "net.Receive SpawnAdmin_OpenMenu зарегистрирован")
-- временно перехватим net.Send для чтения таблицы
local writeTable = net.WriteTable
net.WriteTable = function(t) captured = t end
net.Send = function() end
openRecv(0, mkPly(BossSid, "76561198000000001"))
net.WriteTable = writeTable
ok(captured ~= nil and istable(captured.factions), "админу отправлены данные")
local fac = captured and captured.factions and captured.factions["Полиция"]
ok(fac ~= nil and istable(fac.rolesList) and #fac.rolesList == 2, "rolesList из factions.json (без роли лидера)")
ok(fac ~= nil and istable(fac.departmentsList) and #fac.departmentsList == 2, "departmentsList из factions.json")
ok(fac ~= nil and fac.leaderRole == "Лидер" and fac.leader == BossSid, "leader/leaderRole из factions.json")

-- ══════════════ 6. ПРИОРИТЕТ ВЫБОРА ТОЧКИ ДЛЯ ИГРОКА ══════════════
-- После легаси-миграции в памяти: 1 фракционная точка (5,6,7), роли/отделы пусты.
-- Добавляем точки роли и отдела заново — проверим приоритеты.
reloadHook()
AddSpawnPointForRole("Полиция", "Офицер", Vector(10, 10, 10), Angle(0, 0, 0))
AddSpawnPointForDepartment("Полиция", "Патруль", Vector(20, 20, 20), Angle(0, 0, 0))
local cop = mkPly(CopSid, "76561198000000002")
local pos, ang = GetSpawnPointForPlayer(cop)
ok(pos ~= nil and pos.x == 10 and pos.y == 10 and pos.z == 10, "приоритет РОЛЬ: офицер получил точку роли (10,10,10)")
-- Игрок без роли/отдела → фракционная точка
local noRole = mkPly("STEAM_0:1:3", "76561198000000003")
Factions["Полиция"].Members["STEAM_0:1:3"] = { Role = nil, Department = nil }
local pos2 = GetSpawnPointForPlayer(noRole)
ok(pos2 ~= nil and pos2.x == 5, "приоритет ФРАКЦИЯ: без роли/отдела — общая точка")
-- Глобальная точка для гражданского
AddGlobalSpawnPoint(Vector(500, 500, 500), Angle(0, 0, 0))
local civ = mkPly("STEAM_0:1:9", "76561198000000009")
local pos3 = GetSpawnPointForPlayer(civ)
ok(pos3 ~= nil and pos3.x == 500, "гражданский получает глобальную точку")

-- ══════════════ 7. ГЛОБАЛЬНЫЕ ТОЧКИ СОХРАНЯЮТСЯ ══════════════
ok(files["spawn_points_global_gm_test.json"] ~= nil and files["spawn_points_global_gm_test.json"]:find("500", 1, true) ~= nil, "глобальные точки сохранены в файл")

-- ══════════════ 8. ОСИ ИЕРАРХИИ: ОДНА МЕХАНИКА НА ВСЕ ЧЕТЫРЕ ══════════════
--[[ Каждая ось (роль / должность / отдел / подотдел) обязана вести себя
     ОДИНАКОВО во всех местах: добавление, чтение, запись в JSON, подъём
     после рестарта и очистка. Раньше механика была скопирована на каждую
     ось отдельно, и цена уже оплачена дважды:
       * находка 157 — загрузчик поднимал не все оси (точки «пропадали»);
       * ось v5 «должность» — забыли ветку в ClearSpawnPoints, точки
         должности нельзя было очистить.
     Проверяем осями в цикле: если у новой оси забыли одно из мест,
     красным станет именно её строка, а не «что-то где-то не работает». ]]
Factions["Полиция"].Subdepartments = { patrol_north = { name = "Север" } }
GRM.Positions = { Get = function(f, id) return tostring(id) == "7" and { id = 7 } or nil end }
Factions["Полиция"].SpawnPoints = nil
Factions["Полиция"].RoleSpawnPoints = nil
Factions["Полиция"].DepartmentSpawnPoints = nil
Factions["Полиция"].SubdeptSpawnPoints = nil
Factions["Полиция"].PositionSpawnPoints = nil
files["spawn_points_factions_gm_test.json"] = nil
reloadHook()

local AXES = {
    { id = "position", key = "7",            bundle = "positions",      member = "Position",
      add = AddSpawnPointForPosition,   get = GetSpawnPointsForPosition,   x = 71 },
    { id = "sub",      key = "patrol_north", bundle = "subdepartments", member = "Subdepartment",
      add = AddSpawnPointForSubdept,    get = GetSpawnPointsForSubdept,    x = 72 },
    { id = "role",     key = "Офицер",       bundle = "roles",          member = "Role",
      add = AddSpawnPointForRole,       get = GetSpawnPointsForRole,       x = 73 },
    { id = "dept",     key = "Патруль",      bundle = "departments",    member = "Department",
      add = AddSpawnPointForDepartment, get = GetSpawnPointsForDepartment, x = 74 },
}

for _, axis in ipairs(AXES) do
    local added = axis.add("Полиция", axis.key, Vector(axis.x, 0, 0), Angle(0, 0, 0))
    ok(added == true, ("ось %s: точка добавляется"):format(axis.id))

    local points = axis.get("Полиция", axis.key)
    ok(istable(points) and #points == 1 and points[1].pos.x == axis.x,
        ("ось %s: точка читается обратно"):format(axis.id))

    local raw = files["spawn_points_factions_gm_test.json"] or ""
    ok(raw:find('"' .. axis.bundle .. '"', 1, true) ~= nil,
        ("ось %s: попадает в JSON под ключом %s"):format(axis.id, axis.bundle))
end

-- Рестарт: ВСЕ оси обязаны подняться из файла (находка 157).
for _, axis in ipairs(AXES) do
    Factions["Полиция"][({ position = "PositionSpawnPoints", sub = "SubdeptSpawnPoints",
        role = "RoleSpawnPoints", dept = "DepartmentSpawnPoints" })[axis.id]] = nil
end
reloadHook()
for _, axis in ipairs(AXES) do
    local points = axis.get("Полиция", axis.key)
    ok(istable(points) and #points == 1 and points[1].pos.x == axis.x,
        ("ось %s: пережила рестарт"):format(axis.id))
end

-- Приоритет: должность точнее подотдела, подотдел — роли, роль — отдела.
Factions["Полиция"].Members[CopSid] = {
    Role = "Офицер", Department = "Патруль",
    Subdepartment = "patrol_north", Position = "7",
}
local narrow = mkPly(CopSid, "76561198000000002")
local pPos = GetSpawnPointForPlayer(narrow)
ok(pPos ~= nil and pPos.x == 71, "приоритет: должность выигрывает у подотдела/роли/отдела")

Factions["Полиция"].Members[CopSid].Position = nil
ok(GetSpawnPointForPlayer(narrow).x == 72, "приоритет: подотдел выигрывает у роли/отдела")
Factions["Полиция"].Members[CopSid].Subdepartment = nil
ok(GetSpawnPointForPlayer(narrow).x == 73, "приоритет: роль выигрывает у отдела")
Factions["Полиция"].Members[CopSid].Role = nil
ok(GetSpawnPointForPlayer(narrow).x == 74, "приоритет: остаётся отдел")

-- Очистка узла работает для КАЖДОЙ оси (для должности раньше не работала).
for _, axis in ipairs(AXES) do
    local cleared = ClearSpawnPoints(axis.id, "Полиция", axis.key)
    ok(cleared == true, ("ось %s: ClearSpawnPoints принимает раздел"):format(axis.id))
    ok(#axis.get("Полиция", axis.key) == 0, ("ось %s: точки узла действительно очищены"):format(axis.id))
end

local badScope, badErr = ClearSpawnPoints("несуществующая", "Полиция", "x")
ok(badScope == false and badErr == "Неизвестный раздел", "неизвестный раздел отвергается с причиной")

-- Валидация узла: несуществующий ключ не создаёт мусорных точек.
local badAdd, badAddErr = AddSpawnPointForSubdept("Полиция", "нет_такого", Vector(1, 1, 1), Angle(0, 0, 0))
ok(badAdd == false and isstring(badAddErr) and badAddErr:find("Подотдел", 1, true) ~= nil,
    "несуществующий подотдел отвергается с человеческой причиной")
local badPos = AddSpawnPointForPosition("Полиция", "999", Vector(1, 1, 1), Angle(0, 0, 0))
ok(badPos == false, "несуществующая должность отвергается")

print(("SPAWN POINTS: %d/%d failures=%d"):format(pass, pass + fail, fail))
if fail > 0 then os.exit(1) end
