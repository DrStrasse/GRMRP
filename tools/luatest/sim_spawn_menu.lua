--[[ Живой прогон нового меню точек спавна (заказ 21.08):
     дерево «организация → отдел → подотдел → должность», точки подотделов,
     очистка узла, поиск, приоритет выдачи точки игроку.
     Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_spawn_menu.lua ]]
local pass, fail = 0, 0
local function ok(v, n, extra)
  if v then pass = pass + 1 print("  ok   " .. n)
  else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

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

local H = { hooks = {}, netrecv = {}, concommands = {} }
hook = { Add = function(n, id, fn) H.hooks[n] = H.hooks[n] or {} H.hooks[n][id] = fn end,
         Run = function() end }
timer = { Create = function() end, Simple = function() end }
concommand = { Add = function(n, fn) H.concommands[n] = fn end }
util = { AddNetworkString = function() end }
local NETLOG = {}
net = {
  Start = function(m) NETLOG[#NETLOG + 1] = m end, WriteString = function() end, WriteVector = function() end,
  WriteAngle = function() end, WriteInt = function() end, Send = function() end,
  WriteTable = function() end, SendToServer = function() end, ReadString = function() return "" end, ReadVector = function() end,
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


-- ── игроки ──
local PMT = {}
PMT.__index = function(t, k)
  if k == "SteamID" then return function(s) return s.sid end
  elseif k == "SteamID64" then return function(s) return s.s64 end
  elseif k == "IsSuperAdmin" then return function() return true end
  elseif k == "SetPos" then return function(s, p) s.pos = p end
  elseif k == "SetAngles" then return function() end
  elseif k == "SetEyeAngles" then return function() end
  elseif k == "PrintMessage" then return function(s, _, m) s.msg = m end
  end
  return nil
end
local function mkPly(sid, s64) return setmetatable({ sid = sid, s64 = s64 }, PMT) end
local V = {}; V.__index = V
function Vector(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, V) end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end

-- ── организация со структурой: отделы, подотделы, должности ──
local Boss  = "STEAM_0:1:1"
local Opera = "STEAM_0:1:2"
local Kadet = "STEAM_0:1:3"
Factions = {
  ["police"] = {
    DisplayName = "Полиция", Tag = "ПД",
    Leader = Boss, LeaderRoleName = "leader",
    Roles = { "leader", "officer", "cadet" },
    RoleDisplayNames = { leader = "Начальник", officer = "Офицер", cadet = "Кадет" },
    Departments = { "patrol", "crime" },
    DepartmentDisplayNames = { patrol = "Патрульная служба", crime = "Уголовный розыск" },
    DepartmentTags = { patrol = "ППС", crime = "УР" },
    Subdepartments = {
      sub_dps = { id = "sub_dps", name = "ДПС", parentDept = "patrol", tag = "ДПС", quota = 5 },
      sub_swat = { id = "sub_swat", name = "СОБР", parentDept = "crime", tag = "СОБР", quota = 3 },
    },
    Members = {
      [Boss]  = { Role = "leader", Department = "patrol" },
      [Opera] = { Role = "officer", Department = "crime", Subdepartment = "sub_swat" },
      [Kadet] = { Role = "cadet", Department = "patrol" },
    },
  },
  ["medic"] = {
    DisplayName = "Медицина", Leader = "STEAM_0:1:9", LeaderRoleName = "leader",
    Roles = { "leader", "doctor" }, RoleDisplayNames = { doctor = "Врач" },
    Departments = {}, Subdepartments = {}, Members = {},
  },
}
GRM = GRM or {}
GRM.Identity = {
  CharacterKey = function(p) return p.s64 .. ":char1" end,
  FactionMember = function(f, ply) return f.Members[ply.sid] or f.Members[ply.s64] end,
}

dofile("lua/autorun/sh_spawn_points.lua")
local SP = GRM.SpawnPoints

print("\n=== 1. API ПОДОТДЕЛОВ ===")
ok(isfunction(AddSpawnPointForSubdept) and isfunction(RemoveSpawnPointFromSubdept)
   and isfunction(GetSpawnPointsForSubdept), "функции точек подотделов объявлены")
ok(isfunction(ClearSpawnPoints), "очистка узла объявлена")

local okSub = AddSpawnPointForSubdept("police", "sub_swat", Vector(11, 12, 13), Angle(0, 45, 0))
ok(okSub == true, "точка подотдела добавлена")
local okBad, errBad = AddSpawnPointForSubdept("police", "sub_ghost", Vector(1, 1, 1), Angle(0, 0, 0))
ok(okBad == false and tostring(errBad):find("не существует", 1, true) ~= nil,
   "несуществующий подотдел отклонён", errBad)
ok(#GetSpawnPointsForSubdept("police", "sub_swat") == 1, "точка читается обратно")

print("\n=== 2. СОХРАНЕНИЕ И ПЕРЕЗАГРУЗКА ===")
local raw = files["spawn_points_factions_gm_test.json"]
ok(raw ~= nil and raw:find("subdepartments", 1, true) ~= nil, "в файле появился ключ subdepartments")
ok(raw:find("sub_swat", 1, true) ~= nil, "ключ подотдела записан")
AddSpawnPointForDepartment("police", "patrol", Vector(20, 20, 20), Angle(0, 0, 0))
AddSpawnPointForRole("police", "officer", Vector(30, 30, 30), Angle(0, 0, 0))
AddSpawnPointForFaction("police", Vector(40, 40, 40), Angle(0, 0, 0))
Factions["police"].SubdeptSpawnPoints = nil
Factions["police"].DepartmentSpawnPoints = nil
local reloadHook
for _, fn in pairs(H.hooks["InitPostEntity"] or {}) do reloadHook = fn end
reloadHook()
ok(istable(Factions["police"].SubdeptSpawnPoints)
   and #(Factions["police"].SubdeptSpawnPoints["sub_swat"] or {}) == 1,
   "после рестарта точки подотдела на месте")
ok(#(Factions["police"].DepartmentSpawnPoints["patrol"] or {}) == 1, "точки отдела тоже на месте")

print("\n=== 3. ПРИОРИТЕТ: ПОДОТДЕЛ ВЫШЕ ДОЛЖНОСТИ ===")
local opera = mkPly(Opera, "76561198000000002")
local pos = GetSpawnPointForPlayer(opera)
ok(pos ~= nil and pos.x == 11, "оперативник СОБР получил точку подотдела (11,12,13)", pos and pos.x)
local kadet = mkPly(Kadet, "76561198000000003")
local pos2 = GetSpawnPointForPlayer(kadet)
ok(pos2 ~= nil and pos2.x == 20, "кадет без подотдела получил точку отдела (20)", pos2 and pos2.x)
Factions["police"].Members[Kadet].Department = nil
local pos3 = GetSpawnPointForPlayer(kadet)
ok(pos3 ~= nil and pos3.x == 40, "без отдела — общая точка организации (40)", pos3 and pos3.x)
Factions["police"].Members[Kadet].Department = "patrol"

print("\n=== 4. ДАННЫЕ ДЛЯ МЕНЮ (структура организации) ===")
local captured
local writeTable = net.WriteTable
net.WriteTable = function(t) captured = t end
H.netrecv["SpawnAdmin_OpenMenu"](0, mkPly(Boss, "76561198000000001"))
net.WriteTable = writeTable
local fac = captured and captured.factions and captured.factions["police"]
ok(fac ~= nil, "данные пришли")
ok(fac.displayName == "Полиция", "публичное название организации")
ok(istable(fac.subList) and #fac.subList == 2, "список подотделов", fac and #(fac.subList or {}))
local dps
for _, s in ipairs(fac.subList or {}) do if s.id == "sub_dps" then dps = s end end
ok(dps ~= nil and dps.parent == "patrol" and dps.name == "ДПС", "подотдел знает родительский отдел")
ok(fac.deptNames and fac.deptNames["crime"] == "Уголовный розыск", "публичные названия отделов")
ok(fac.roleNames and fac.roleNames["officer"] == "Офицер", "публичные названия должностей")
ok(captured.map == "gm_test", "карта передана в меню")

print("\n=== 5. ДЕРЕВО МЕНЮ ===")
local data = captured
local rows = SP.BuildTree(data, "", {})
ok(rows[1] and rows[1].kind == "global", "первой строкой — глобальные точки")
local facRow
for _, r in ipairs(rows) do if r.kind == "faction" and r.faction == "police" then facRow = r end end
ok(facRow ~= nil and facRow.expandable == true, "организация — раскрывающийся узел")
ok(facRow.count == SP.FactionTotal(data.factions["police"]), "у организации счётчик всех её точек")
local collapsed = #rows
rows = SP.BuildTree(data, "", { ["fac:police"] = true })
ok(#rows > collapsed, "раскрытие организации показывает дочерние узлы")
local kinds = {}
for _, r in ipairs(rows) do kinds[r.kind] = (kinds[r.kind] or 0) + 1 end
ok(kinds["facpoints"] == 1, "есть узел «Точки организации»")
ok(kinds["dept"] == 2, "оба отдела показаны", kinds["dept"])
ok(kinds["role"] == 2, "должности без роли лидера", kinds["role"])
ok((kinds["sub"] or 0) == 0, "подотделы скрыты, пока отдел свёрнут")

rows = SP.BuildTree(data, "", { ["fac:police"] = true, ["dept:police/crime"] = true })
local subRow
for _, r in ipairs(rows) do if r.kind == "sub" then subRow = r end end
ok(subRow ~= nil and subRow.key == "sub_swat", "раскрытый отдел показал свой подотдел")
ok(subRow.depth == 2, "подотдел глубже отдела")
ok(subRow.count == 1, "у подотдела виден счётчик точек", subRow.count)

print("\n=== 6. ПОИСК ===")
rows = SP.BuildTree(data, "СОБР", {})
local found, facSeen = false, false
for _, r in ipairs(rows) do
  if r.kind == "sub" and r.key == "sub_swat" then found = true end
  if r.kind == "faction" and r.faction == "medic" then facSeen = true end
end
ok(found, "поиск находит подотдел и раскрывает путь к нему")
ok(not facSeen, "организации без совпадений скрыты")
rows = SP.BuildTree(data, "медиц", {})
local medicSeen = false
for _, r in ipairs(rows) do if r.kind == "faction" and r.faction == "medic" then medicSeen = true end end
ok(medicSeen, "поиск по названию организации работает")

print("\n=== 7. ЛЕГАСИ-УЗЛЫ НЕ ТЕРЯЮТСЯ ===")
Factions["police"].DepartmentSpawnPoints["ghost_dept"] = { { pos = { x = 1, y = 2, z = 3 }, ang = { p = 0, y = 0, r = 0 } } }
local cap2
net.WriteTable = function(t) cap2 = t end
H.netrecv["SpawnAdmin_OpenMenu"](0, mkPly(Boss, "76561198000000001"))
net.WriteTable = writeTable
rows = SP.BuildTree(cap2, "", { ["fac:police"] = true })
local ghost
for _, r in ipairs(rows) do if r.kind == "dept" and r.key == "ghost_dept" then ghost = r end end
ok(ghost ~= nil and ghost.note == "вне структуры", "точки удалённого отдела видно и можно снести")

print("\n=== 8. ХЛЕБНАЯ КРОШКА И ВЫБОРКА ТОЧЕК ===")
ok(SP.SelectionPath(data, { scope = "global" }) == "Глобальные точки", "путь: глобальные")
local pathSub = SP.SelectionPath(data, { scope = "sub", faction = "police", key = "sub_swat" })
ok(pathSub:find("Полиция", 1, true) and pathSub:find("Уголовный розыск", 1, true)
   and pathSub:find("СОБР", 1, true), "путь подотдела показывает организацию и отдел", pathSub)
ok(#SP.PointsFor(data, { scope = "sub", faction = "police", key = "sub_swat" }) == 1, "точки подотдела читаются")
ok(#SP.PointsFor(data, { scope = "role", faction = "police", key = "officer" }) == 1, "точки должности читаются")
ok(#SP.PointsFor(data, { scope = "faction", faction = "police" }) == 1, "точки организации читаются")
ok(#SP.PointsFor(data, { scope = "sub", faction = "police", key = "нет" }) == 0, "у пустого узла ноль точек")

print("\n=== 9. ОЧИСТКА УЗЛА ===")
local clr = H.netrecv["SpawnAdmin_ClearPoints"]
ok(clr ~= nil, "обработчик очистки зарегистрирован")
net.ReadString = (function()
  local seq, i = { "sub", "police", "sub_swat" }, 0
  return function() i = i + 1 return seq[i] or "" end
end)()
clr(0, mkPly(Boss, "76561198000000001"))
ok(#GetSpawnPointsForSubdept("police", "sub_swat") == 0, "все точки подотдела удалены")
ok(#GetSpawnPointsForFaction("police") == 1, "соседний узел не пострадал")
ok(ClearSpawnPoints("global") == true and #GetGlobalSpawnPoints() == 0, "глобальные точки чистятся")
local okBadScope, errScope = ClearSpawnPoints("что-то", "police")
ok(okBadScope == false and errScope ~= nil, "неизвестный раздел отклонён")

print("\n=== 10. КОМАНДА ЧАТА ===")
ok(H.hooks["PlayerSay"] ~= nil and H.hooks["PlayerSay"]["GRM_SpawnPoints_ChatCmd"] ~= nil,
   "серверная команда /spawnmenu зарегистрирована (ванильный чат тоже открывает меню)")
string.Trim = function(x) return (tostring(x):gsub("^%s+", ""):gsub("%s+$", "")) end
local said = H.hooks["PlayerSay"]["GRM_SpawnPoints_ChatCmd"]
local boss = mkPly(Boss, "76561198000000001")
ok(said(boss, "/spawnmenu") == "", "команда съедается и не уходит в чат")
ok(said(boss, "привет") == nil, "обычная реплика не трогается")

print(("\nSPAWN MENU: %d/%d, провалов: %d"):format(pass, pass + fail, fail))
if fail > 0 then os.exit(1) end
