-- sim_perm_tool.lua — функциональный тест перма-проп-инструмента GRM (Задача 9)
--
-- Проверяет публичный API GRM.Perm поверх РЕАЛЬНОГО sh_grm_perm_entities.lua
-- с in-memory моком file (тот же контур, что у sim_perm_upsert):
--   • Д17 — GRM.Perm.Add/Remove существуют и работают (галочка служебного тула)
--   • П1  — владелец не теряет доступ: ownerKind сохраняется в записи
--   • П2  — Remove снимает закрепление, но НЕ удаляет объект
--   • П3  — поиск записи по uid, а не только по «класс + 6 юнитов»
--   • П4  — цепочки делегатов: два Extract/Apply на один класс не затирают друг друга
--   • миграция v1 -> v2 идемпотентна и делает бэкап
--   • квоты фракции/персонажа и чёрный список классов
local pass, fail = 0, 0
local function ok(v, n) if v then pass = pass + 1 print("  ok  " .. n) else fail = fail + 1 print("  FAIL " .. n) end end

-- ── глобальные моки ──
SERVER = true
CLIENT = false
istable = function(v) return type(v) == "table" end
isstring = function(v) return type(v) == "string" end
isfunction = function(v) return type(v) == "function" end
isnumber = function(v) return type(v) == "number" end
IsValid = function(e) return e ~= nil and e.__valid ~= false end
Vector = function(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
Angle = function(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
CurTime = function() return 1000 end
FCVAR_ARCHIVE = 128
string.Trim = string.Trim or function(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end

local mem = {}
file = {
  Exists = function(p) return mem[p] ~= nil end,
  Read = function(p) return mem[p] end,
  Write = function(p, txt) mem[p] = txt end,
  Find = function() return {} end,
  CreateDir = function() end,
  IsDir = function() return true end,
}
game = { GetMap = function() return "rp_test" end }
local osTime = 1700000000
os = { time = function() return osTime end, date = function() return "01.01.2024 00:00" end,
       exit = function(c) if c and c ~= 0 then error("exit " .. c) end end }
util = {
  AddNetworkString = function() end,
  IsValidModel = function() return true end,
  TraceLine = function() return { Hit = false, Entity = nil } end,
}

-- «JSON» через память: сохраняем ссылку на таблицу по её тексту-ключу
local blobs, blobN = {}, 0
util.TableToJSON = function(t)
  blobN = blobN + 1
  local key = "blob#" .. blobN
  -- глубокая копия: иначе тест не отличит записанное от живой таблицы
  local function copy(v)
    if type(v) ~= "table" then return v end
    local o = {}
    for k, vv in pairs(v) do o[k] = copy(vv) end
    return o
  end
  blobs[key] = copy(t)
  return key
end
util.JSONToTable = function(txt) return blobs[txt] end

local hooksRun = {}
hook = {
  Add = function() end,
  Run = function(name, ...) hooksRun[name] = (hooksRun[name] or 0) + 1 end,
}
timer = { Simple = function() end, Create = function() end }
concommand = { Add = function() end }
ents = { FindInSphere = function() return {} end, Create = function() return nil end,
         FindByClass = function() return {} end }
player = { GetAll = function() return {} end }
net = {
  Start = function() end, WriteEntity = function() end, WriteString = function() end,
  WriteBool = function() end, WriteUInt = function() end, Send = function() end,
  Receive = function() end,
}
local convars = { grm_perm_players = 0 }
CreateConVar = function(n, v) convars[n] = tonumber(v) or 0 return nil end
GetConVar = function(n)
  return { GetInt = function() return convars[n] or 0 end }
end
GRM = { Notify = function() end }

-- Ядро GRM (sh_00_grm_ui + sh_01_grm_core) — как на сервере, до модулей.
dofile("tools/luatest/lib_grm_core.lua")()
dofile("lua/autorun/sh_grm_perm_entities.lua")

-- ── фабрики ──
local nwStore = setmetatable({}, { __mode = "k" })
local function mkEnt(cls, idx, x, y, z)
  local e
  e = {
    __cls = cls, __valid = true, __idx = idx or 1, __pos = Vector(x or 100, y or 100, z or 0),
    __model = "models/props/cs_office/computer.mdl",
    GetClass = function(s) return s.__cls end,
    EntIndex = function(s) return s.__idx end,
    GetPos = function(s) return s.__pos end,
    SetPos = function(s, p) s.__pos = p end,
    GetAngles = function() return Angle(0, 0, 0) end,
    SetAngles = function() end,
    GetModel = function(s) return s.__model end,
    SetModel = function(s, m) s.__model = m end,
    IsPlayer = function() return false end,
    IsNPC = function() return false end,
    Remove = function(s) s.__valid = false s.__removed = true end,
    GetPhysicsObject = function(s)
      s.__phys = s.__phys or { __valid = true, EnableMotion = function(p, b) s.__motion = b end,
                               Wake = function() end }
      return s.__phys
    end,
    SetNWString = function(s, k, v) nwStore[s] = nwStore[s] or {} nwStore[s][k] = v end,
    SetNWBool = function(s, k, v) nwStore[s] = nwStore[s] or {} nwStore[s][k] = v end,
    GetNWString = function(s, k, d) return (nwStore[s] or {})[k] or d or "" end,
    GetNWBool = function(s, k, d) local v = (nwStore[s] or {})[k] if v == nil then return d end return v end,
  }
  return e
end

local function mkPly(name, superadmin, faction, charKey)
  local p
  p = {
    __valid = true, __sa = superadmin and true or false,
    IsPlayer = function() return true end,
    IsSuperAdmin = function(s) return s.__sa end,
    Nick = function() return name end,
    SteamID64 = function() return "7656119" .. tostring(#name) end,
    GetNWString = function(s, k, d)
      if k == "GRM_Faction" then return faction or "" end
      if k == "GRM_RPName" then return name end
      return d or ""
    end,
    KeyDown = function() return false end,
    ChatPrint = function() end,
    __charKey = charKey or ("key_" .. name),
  }
  return p
end

GRM.Identity = { CharacterKey = function(p) return p.__charKey end }

local admin  = mkPly("Admin", true)
local leader = mkPly("Leader", false, "OrdnungPolizei")
local civil  = mkPly("Civil", false, "")

-- права фракции: лидеру даём perm_manage, гражданскому нет
GRM.FactionPerms = {
  PlayerHasPermission = function(p, perm)
    return p == leader and perm == "perm_manage"
  end,
}
GRM.PropProtect = {
  MarkServerEntity = function(ent)
    ent.GRM_EntityOwnerType = "server"
    ent._grmPerm = true
  end,
}

local function dbCount()
  local n = 0
  for _ in ipairs(GRM.Perm.ListForMap("rp_test")) do n = n + 1 end
  return n
end

-- ══ 1. Д17: API существует ══
ok(istable(GRM.Perm), "GRM.Perm существует (Д17)")
ok(isfunction(GRM.Perm.Add) and isfunction(GRM.Perm.Remove), "GRM.Perm.Add/Remove существуют (Д17)")
ok(isfunction(GRM.Perm.Update) and isfunction(GRM.Perm.Info)
   and isfunction(GRM.Perm.IsPerm) and isfunction(GRM.Perm.ListForMap), "полный набор API на месте")

-- ══ 2. Закрепление админом (серверное) ══
local comp = mkEnt("grm_comp_police", 1, 100, 100, 0)
local okAdd, msgAdd, recAdd = GRM.Perm.Add(admin, comp)
ok(okAdd and msgAdd == "added", "Add: админ закрепил служебный компьютер")
ok(isstring(recAdd.uid) and recAdd.uid ~= "", "Add: записи присвоен uid (П3)")
ok(recAdd.ownerKind == "server", "Add: по умолчанию серверное оборудование")
ok(comp._grmPerm == true and comp._grmPermKind == "server", "Add: объект помечен как перм")
ok(comp.__motion == false, "Add: объект заморожен")
ok(dbCount() == 1, "Add: в базе одна запись")
ok((hooksRun["GRM_PermAdded"] or 0) >= 1, "Add: хук GRM_PermAdded вызван")

-- ══ 3. Повторное закрепление того же объекта = обновление, не дубль ══
local okAdd2, msgAdd2 = GRM.Perm.Add(admin, comp)
ok(okAdd2 and msgAdd2 == "updated", "Add повторно = updated")
ok(dbCount() == 1, "Add повторно: дубля нет")

-- ══ 4. П3: поиск по uid работает после сдвига объекта ══
comp:SetPos(Vector(4000, 4000, 0)) -- уехал далеко за PERM_RANGE
local infoMoved = GRM.Perm.Info(comp)
ok(infoMoved ~= nil and infoMoved.uid == recAdd.uid, "Info: запись найдена по uid после сдвига (П3)")

-- ══ 5. П1: владение фракции сохраняется в записи ══
local door = mkEnt("prop_physics", 2, 200, 200, 0)
local okF, msgF, recF = GRM.Perm.Add(leader, door, { ownerKind = "faction" })
ok(okF, "Add: лидер фракции закрепил объект: " .. tostring(msgF))
ok(recF and recF.ownerKind == "faction" and recF.faction == "OrdnungPolizei", "Add: ownerKind=faction, фракция записана (П1)")
ok(door._grmPermKind == "faction", "Add: объект помечен как фракционный, а не серверный (П1)")

-- ══ 6. Лидер не может закрепить как «серверное» ══
local srvTry = mkEnt("grm_comp_police", 3, 300, 300, 0)
local okS, _, recS = GRM.Perm.Add(leader, srvTry, { ownerKind = "server" })
ok(okS and recS.ownerKind == "faction", "Add: лидеру подменён server -> faction (не даём неприкасаемость)")

-- ══ 7. Гражданский без прав закрепить не может ══
local civEnt = mkEnt("prop_physics", 4, 400, 400, 0)
local okC, whyC = GRM.Perm.Add(civil, civEnt)
ok(not okC, "Add: гражданский без прав получил отказ")
ok(isstring(whyC) and whyC ~= "", "Add: отказ с человеческой причиной: " .. tostring(whyC))

-- ══ 8. Конвар grm_perm_players включает личные закрепления ══
convars.grm_perm_players = 1
local okC2, msgC2, recC2 = GRM.Perm.Add(civil, civEnt, { ownerKind = "character" })
ok(okC2, "Add: при grm_perm_players=1 игрок закрепляет свой объект: " .. tostring(msgC2))
ok(recC2 and recC2.ownerKind == "character" and recC2.owner == civil.__charKey, "Add: владение записано на персонажа")
convars.grm_perm_players = 0

-- ══ 9. Чёрный список ══
local drop = mkEnt("grm_item_drop", 5, 500, 500, 0)
local okB, whyB = GRM.Perm.Add(admin, drop)
ok(not okB, "Add: временный объект (grm_item_drop) закрепить нельзя")
ok(isstring(whyB) and whyB:find("временн"), "Add: причина отказа объясняет, почему: " .. tostring(whyB))
local cctv = mkEnt("grm_cctv_camera", 6, 600, 600, 0)
local okB2, whyB2 = GRM.Perm.Add(admin, cctv)
ok(not okB2 and isstring(whyB2) and whyB2:find("CCTV"), "Add: CCTV отклонён (своё сохранение)")

-- ══ 10. П2: Remove снимает закрепление, объект остаётся ══
local before = dbCount()
local okR, msgR = GRM.Perm.Remove(admin, comp)
ok(okR and msgR == "removed", "Remove: закрепление снято")
ok(comp.__removed ~= true and IsValid(comp), "Remove: объект НЕ удалён с карты (П2)")
ok(comp._grmPerm == nil, "Remove: метка перма снята с объекта")
ok(comp.__motion == true, "Remove: физика разморожена")
ok(dbCount() == before - 1, "Remove: запись удалена из базы")
ok((hooksRun["GRM_PermRemoved"] or 0) >= 1, "Remove: хук GRM_PermRemoved вызван")

-- ══ 11. Чужой фракционный объект гражданскому не снять ══
local okR2, whyR2 = GRM.Perm.Remove(civil, door)
ok(not okR2, "Remove: гражданский не снимает фракционное закрепление")
ok(isstring(whyR2) and whyR2:find("фракц"), "Remove: причина отказа названа: " .. tostring(whyR2))

-- ══ 12. Квота фракции ══
local made = 0
for i = 1, 40 do
  local e = mkEnt("prop_physics", 100 + i, 2000 + i * 20, 2000, 0)
  local okQ = GRM.Perm.Add(leader, e, { ownerKind = "faction" })
  if okQ then made = made + 1 end
end
ok(made < 40, "Квота фракции сработала (создано " .. made .. " из 40)")
local facCount = 0
for _, rec in ipairs(GRM.Perm.ListForMap("rp_test")) do
  if rec.ownerKind == "faction" and rec.faction == "OrdnungPolizei" then facCount = facCount + 1 end
end
ok(facCount <= GRM.Perm.QuotaFaction, "Квота фракции не превышена: " .. facCount .. " <= " .. GRM.Perm.QuotaFaction)

-- ══ 13. П4: цепочки делегатов не затирают друг друга ══
local calls = {}
GRM.PermData.AddExtract("grm_test_chain", function(ent) calls[#calls + 1] = "e1" return { a = 1 } end)
GRM.PermData.AddExtract("grm_test_chain", function(ent) calls[#calls + 1] = "e2" return { b = 2 } end)
local ex = GRM.PermData.Extract["grm_test_chain"]
ok(isfunction(ex), "Цепочки: Extract вернул функцию-композит (П4)")
local merged = ex(mkEnt("grm_test_chain", 7))
ok(#calls == 2, "Цепочки: вызваны ОБА Extract-делегата (П4)")
ok(istable(merged) and merged.a == 1 and merged.b == 2, "Цепочки: результаты слиты в одну таблицу")

local applied = {}
GRM.PermData.AddApply("grm_test_chain", function(ent, d) applied[#applied + 1] = "a1" end)
GRM.PermData.AddApply("grm_test_chain", function(ent, d) applied[#applied + 1] = "a2" end)
GRM.PermData.Apply["grm_test_chain"](mkEnt("grm_test_chain", 8), { a = 1 })
ok(#applied == 2, "Цепочки: вызваны ОБА Apply-делегата (П4)")

-- присваивание через прокси (старый стиль модулей) тоже работает
GRM.PermData.Extract["grm_test_legacy"] = function() return { legacy = true } end
local lg = GRM.PermData.Extract["grm_test_legacy"]
ok(isfunction(lg) and lg({}).legacy == true, "Цепочки: старый стиль присваивания сохранён")

-- ══ 14. Update: позиция и метка ══
local upEnt = mkEnt("grm_comp_medical", 9, 700, 700, 0)
GRM.Perm.Add(admin, upEnt)
upEnt:SetPos(Vector(760, 700, 0))
local okU = GRM.Perm.Update(admin, upEnt, { label = "приёмный покой", freeze = false })
local recU = GRM.Perm.Info(upEnt)
ok(okU and recU and recU.label == "приёмный покой", "Update: метка сохранена")
ok(recU and math.abs((recU.pos.x or 0) - 760) < 0.01, "Update: позиция записи поехала за объектом")
ok(recU and recU.freeze == false, "Update: заморозку можно отключить")

-- ══ 15. Миграция v1 -> v2 ══
-- Готовим «старую» базу без uid, как на боевом сервере
local oldDB = {
  { map = "rp_test", class = "grm_comp_police", model = "m.mdl",
    pos = { x = 10, y = 20, z = 30 }, ang = { p = 0, y = 90, r = 0 } },
  { map = "rp_test", class = "grm_atm", model = "m.mdl",
    pos = { x = 40, y = 50, z = 60 }, ang = { p = 0, y = 0, r = 0 }, data = { cash = 5000 } },
}
mem["grm_perm_entities.json"] = util.TableToJSON(oldDB)
-- сбрасываем модуль, чтобы миграция отработала заново
GRM.Perm = nil
GRM.PermData = nil
package.loaded["perm"] = nil
dofile("lua/autorun/sh_grm_perm_entities.lua")

local migrated = GRM.Perm.ListForMap("rp_test")
ok(#migrated == 2, "Миграция: обе старые записи на месте")
ok(isstring(migrated[1].uid) and migrated[1].uid ~= "", "Миграция: uid проставлен")
ok(migrated[1].ownerKind == "server", "Миграция: старые записи = серверные (поведение не изменилось)")
ok(migrated[1].freeze == true, "Миграция: freeze=true (как было)")
ok(migrated[2].data and migrated[2].data.cash == 5000, "Миграция: данные экземпляра не потеряны")

local bakFound = nil
for name in pairs(mem) do
  if name:find("grm_perm_entities%.bak%.") then bakFound = name end
end
ok(bakFound ~= nil, "Миграция: бэкап создан (" .. tostring(bakFound) .. ")")
local bak = util.JSONToTable(mem[bakFound])
ok(istable(bak) and #bak == 2 and bak[1].uid == nil, "Миграция: бэкап содержит ИСХОДНЫЕ записи без uid")

-- идемпотентность: повторная загрузка не плодит бэкапы и не меняет uid
local uidBefore = migrated[1].uid
local bakCountBefore = 0
for name in pairs(mem) do if name:find("bak") then bakCountBefore = bakCountBefore + 1 end end
local again = GRM.Perm.ListForMap("rp_test")
local bakCountAfter = 0
for name in pairs(mem) do if name:find("bak") then bakCountAfter = bakCountAfter + 1 end end
ok(again[1].uid == uidBefore, "Миграция идемпотентна: uid не переписан")
ok(bakCountAfter == bakCountBefore, "Миграция идемпотентна: второй бэкап не создан")

print(string.format("sim_perm_tool: %d ok, %d fail", pass, fail))
if fail > 0 then os.exit(1) end
