-- sim_perm_upsert.lua — функциональный тест GRM.PermData.Upsert (находка 179r)
--
-- Проблема: «СОХРАНИТЬ НАСТРОЙКИ» отмывщика молча не сохраняло настройки,
-- если перм-записи ещё не было (UpdateEntry = no-op) → после рестарта
-- дефолты. Upsert создаёт запись автоматически (как /permadd без прицела)
-- либо обновляет существующую.
--
-- Стенд грузит РЕАЛЬНЫЙ sh_grm_perm_entities.lua с in-memory моком file
-- (round-trip через память: TableToJSON сохраняет таблицу, JSONToTable её
-- возвращает — честный контур loadList/saveList).
local pass, fail = 0, 0
local function ok(v, n) if v then pass = pass + 1 print("  ok  " .. n) else fail = fail + 1 print("  FAIL " .. n) end end

-- ── глобальные моки ──
SERVER = true
istable = function(v) return type(v) == "table" end
isstring = function(v) return type(v) == "string" end
isfunction = function(v) return type(v) == "function" end
IsValid = function(e) return e and e.__valid ~= false end
Vector = function(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
Angle = function(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
CurTime = function() return 1000 end
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
os = { time = function() return 1700000000 end }
util = {
  AddNetworkString = function() end,
  IsValidModel = function() return true end,
  TraceLine = function() return { Hit = false, Entity = nil } end,
}
local lastTbl = nil
util.TableToJSON = function(t) lastTbl = t return "{}" end
util.JSONToTable = function() return lastTbl end

net = {
  Start = function() end, WriteEntity = function() end, WriteString = function() end,
  WriteBool = function() end, WriteUInt = function() end, WriteFloat = function() end,
  WriteTable = function() end, Send = function() end, Broadcast = function() end,
  Receive = function() end, ReadEntity = function() end, ReadString = function() end,
  ReadBool = function() end, ReadUInt = function() end, ReadTable = function() end,
}
hook = { Add = function() end }
timer = { Simple = function() end, Create = function() end }
concommand = { Add = function() end }
ents = { FindInSphere = function() return {} end, Create = function() return nil end }
player = { GetAll = function() return {} end }
GRM = { Notify = function() end }

-- перм-класс отмывщика + Extract/Apply (как в init.lua отмывщика)
dofile("lua/autorun/sh_grm_perm_entities.lua")

local function mkEnt(cls, idx, x, y, z)
  return {
    __cls = cls, __valid = true, __idx = idx or 1, __pos = Vector(x or 100, y or 100, z or 0),
    __model = "models/humans/group03/male_07.mdl",
    GetClass = function(s) return s.__cls end,
    EntIndex = function(s) return s.__idx end,
    GetPos = function(s) return s.__pos end,
    GetAngles = function() return Angle(0, 0, 0) end,
    GetModel = function(s) return s.__model end,
    IsPlayer = function() return false end,
  }
end

GRM.PermData.Extract["grm_money_launderer"] = function(ent)
  return {
    minParticipants = ent.__minP or 2,
    goalMoney = ent.__goal or 500000,
    allowedFactions = ent.__allowed or "",
  }
end

-- ── 1. Создание записи (записи не было) ──
local ld = mkEnt("grm_money_launderer", 1, 100, 100, 0)
ld.__minP = 7
ld.__goal = 700000
ld.__allowed = "Mafia"
local res1 = GRM.PermData.Upsert(ld)
ok(res1 == "added", "Upsert: создана запись (added)")
ok(#lastTbl == 1, "Upsert: в базе одна запись")
ok(lastTbl[1].class == "grm_money_launderer" and lastTbl[1].map == "rp_test", "Upsert: класс и карта")
ok(lastTbl[1].data and lastTbl[1].data.minParticipants == 7 and lastTbl[1].data.goalMoney == 700000, "Upsert: данные экземпляра сохранены (7/700000)")
ok(lastTbl[1].data.allowedFactions == "Mafia", "Upsert: фракции сохранены")

-- ── 2. Повторный Upsert без изменений = updated ──
local res2 = GRM.PermData.Upsert(ld)
ok(res2 == "updated", "Upsert: повторно = updated (не дублирует)")
ok(#lastTbl == 1, "Upsert: дублей нет")

-- ── 3. Изменение настроек → Upsert обновляет данные ──
ld.__minP = 12
ld.__goal = 1200000
local res3 = GRM.PermData.Upsert(ld)
ok(res3 == "updated", "Upsert: изменение = updated")
ok(lastTbl[1].data.minParticipants == 12 and lastTbl[1].data.goalMoney == 1200000, "Upsert: данные обновлены (12/1200000)")

-- ── 4. Другая позиция = новая запись ──
local ld2 = mkEnt("grm_money_launderer", 2, 500, 500, 0)
ld2.__minP = 3
local res4 = GRM.PermData.Upsert(ld2)
ok(res4 == "added" and #lastTbl == 2, "Upsert: другая позиция = вторая запись")

-- ── 5. Невалид/не-перм-класс ──
ok(GRM.PermData.Upsert(nil) == "invalid", "Upsert: nil = invalid")
local bad = mkEnt("grm_item_drop", 3, 0, 0, 0)
ok(GRM.PermData.Upsert(bad) == "noclass", "Upsert: не-перм-класс = noclass")

-- ── 6. Лимит 256 ──
for i = 1, 254 do
  local e = mkEnt("grm_phone", 100 + i, 1000 + i * 10, 1000, 0)
  GRM.PermData.Upsert(e)
end
-- сейчас записей: 2 (launderer) + 254 (phone) = 256 → лимит
local ldLimit = mkEnt("grm_money_launderer", 999, 9999, 9999, 0)
local resL = GRM.PermData.Upsert(ldLimit)
ok(resL == "limit", "Upsert: лимит 256 = limit")
ok(#lastTbl == 256, "Upsert: база не превысила лимит")

print(string.format("sim_perm_upsert: %d ok, %d fail", pass, fail))
os.exit(fail > 0 and 1 or 0)
