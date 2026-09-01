-- Симуляция сервера GMod для sh_grm_qmenu.lua v3.0.0 (Код 91, находка 108)
-- «GRM Стройка+»: гейты спавна/toolgun, меню-пропы (каталог/лимит/рейт),
-- куратор каталога (add/del/seed), настройки из меню, защита мебели от
-- remover, undo/cleanup-регистрация, /qm и легаси-команды — БЕЗ GMod.
----------------------------------------------------------------------

string.Trim = function(s) s = tostring(s or ""); return (s:gsub("^%s*(.-)%s*$", "%1")) end
math.Clamp = math.Clamp or function(v, lo, hi) if v < lo then return lo end if v > hi then return hi end return v end

local H = { hooks = {}, timers = {}, netlog = {}, chatlog = {}, concommands = {}, players = {} }
_G._SIM = H
local realPrint = print
local function P(...) realPrint(...) end

function istable(x) return type(x) == "table" end
function isstring(x) return type(x) == "string" end
function isnumber(x) return type(x) == "number" end
function isfunction(x) return type(x) == "function" end
function IsValid(o) return o ~= nil and o ~= false and not o.__removed end
HUD_PRINTTALK, HUD_PRINTCENTER = 3, 4
Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end

-- вектора --------------------------------------------------------------
local VMT = {}
VMT.__index = function(self, k)
  if k == "DistToSqr" then return function(s, o) local dx,dy,dz = s.x-o.x, s.y-o.y, s.z-o.z return dx*dx+dy*dy+dz*dz end end
  if k == "Angle" then return function() return { p = 0, y = 0, r = 0 } end end
  return nil
end
VMT.__add = function(a, b) return V(a.x + (b.x or 0), a.y + (b.y or 0), a.z + (b.z or 0)) end
VMT.__sub = function(a, b) return V(a.x - (b.x or 0), a.y - (b.y or 0), a.z - (b.z or 0)) end
VMT.__mul = function(a, b)
  if type(a) == "number" then return V(a * b.x, a * b.y, a * b.z) end
  return V(a.x * b, a.y * b, a.z * b)
end
function V(x, y, z) return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VMT) end
Vector = V
Angle = function(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end

-- энтити -----------------------------------------------------------------
local REG = { byClass = {}, byIdx = {}, nextIdx = 1 }
local function mkEnt(class, model)
  local e = { __class = class, __pos = V(0, 0, 0), __ang = Angle(0,0,0), __idx = REG.nextIdx, __dt = {}, __model = model or "" }
  REG.nextIdx = REG.nextIdx + 1
  e = setmetatable(e, { __index = function(self, k)
    if k == "GetPos" then return function() return self.__pos end end
    if k == "SetPos" then return function(_, p) self.__pos = p end end
    if k == "GetAngles" then return function() return self.__ang end end
    if k == "SetAngles" then return function(_, a) self.__ang = a end end
    if k == "GetClass" then return function() return self.__class end end
    if k == "EntIndex" then return function() return self.__idx end end
    if k == "GetModel" then return function() return self.__model end end
    if k == "SetModel" then return function(_, m) self.__model = m end end
    if k == "Spawn" then return function() end end
    if k == "Activate" then return function() end end
    if k == "GetPhysicsObject" then return function() return { Wake = function() end, EnableMotion = function() end, IsValid = function() return true end } end end
    if k == "Remove" then return function() self.__removed = true
      local list = REG.byClass[self.__class] or {}
      for i, xx in ipairs(list) do if xx == self then table.remove(list, i) break end end
      REG.byIdx[self.__idx] = nil end end
    local gk = k:match("^Get(%w+)$")
    if gk then return function() return self.__dt[gk] end end
    local sk = k:match("^Set(%w+)$")
    if sk then return function(_, val) self.__dt[sk] = val end end
    return nil
  end })
  REG.byClass[class] = REG.byClass[class] or {}
  table.insert(REG.byClass[class], e)
  REG.byIdx[e.__idx] = e
  return e
end
ents = {
  Create = function(c) return mkEnt(c) end,
  FindByClass = function(c) return REG.byClass[c] or {} end,
}
Entity = function(i) return REG.byIdx[i] end

-- игроки -------------------------------------------------------------------
local function mkPly(id, sa)
  local p = { __pos = V(0, 0, 0), __idx = id, __sa = sa and true or false, __weapons = {}, __cmds = {}, __aim = { Entity = nil } }
  p = setmetatable(p, { __index = function(self, k)
    if k == "GetPos" then return function() return self.__pos end end
    if k == "SetPos" then return function(_, v) self.__pos = v end end
    if k == "EntIndex" then return function() return self.__idx end end
    if k == "IsSuperAdmin" then return function() return self.__sa end end
    if k == "IsPlayer" then return function() return true end end
    if k == "Alive" then return function() return true end end
    if k == "SteamID" then return function() return "STEAM_0:1:" .. tostring(id) end end
    if k == "SteamID64" then return function() return "765611980000000" .. tostring(10 + id) end end
    if k == "GetNWBool" then return function() return false end end
    if k == "GetNWString" then return function() return "" end end
    if k == "SetNWBool" then return function() end end
    if k == "SetNWString" then return function() end end
    if k == "Nick" then return function() return "P" .. tostring(id) end end
    if k == "EyePos" then return function() return self.__pos + V(0, 0, 64) end end
    if k == "GetAimVector" then return function() return V(0, 0, -1) end end
    if k == "GetEyeTrace" then return function() return self.__aim end end
    if k == "PrintMessage" then return function(_, _, txt) H.chatlog[#H.chatlog + 1] = tostring(txt) end end
    if k == "HasWeapon" then return function(_, cls) return self.__weapons[cls] == true end end
    if k == "Give" then return function(_, cls) self.__weapons[cls] = true end end
    if k == "StripWeapon" then return function(_, cls) self.__weapons[cls] = nil end end
    if k == "SelectWeapon" then return function(_, cls) self.__sel = cls end end
    if k == "ConCommand" then return function(_, cmd) self.__cmds[#self.__cmds + 1] = tostring(cmd) end end
    return nil
  end })
  return p
end

-- окружение -----------------------------------------------------------------
local FILES = {}
local SNAP = nil
util = {
  AddNetworkString = function() end,
  TableToJSON = function(t) SNAP = t return "TBL" end,
  JSONToTable = function() return SNAP end,
  TraceLine = function() return H.tr or { HitPos = V(0, 0, 0), HitNormal = V(0, 0, 1) } end,
  IsValidModel = function(m) return H.validModels and H.validModels[m] == true or false end,
}
file = {
  Read = function(p) return FILES[p] end,
  Write = function(p, d) FILES[p] = d end,
  Exists = function(p) return FILES[p] ~= nil end,
  IsDir = function() return true end,
  CreateDir = function() end,
}
hook = {
  Add = function(name, id, fn) H.hooks[name] = H.hooks[name] or {} H.hooks[name][id] = fn end,
  Run = function(name, ...)
    for _, fn in pairs(H.hooks[name] or {}) do
      local r = fn(...)
      if r ~= nil then return r end
    end
  end,
}
timer = { Create = function(_, _, _, fn) H.lastTimer = fn end, Simple = function(_, fn) if fn then fn() end end }
player = { GetAll = function() return H.players or {} end }
game = { GetMap = function() return "gm_test" end }
math.randomseed(1)
concommand = { Add = function(n, fn) H.concommands[n] = fn end }
net = {
  Start = function(m) H.netlog.cur = { msg = m, f = {} } end,
  WriteUInt = function(v) H.netlog.cur.f[#H.netlog.cur.f + 1] = v end,
  WriteString = function(v) H.netlog.cur.f[#H.netlog.cur.f + 1] = v end,
  WriteBool = function(v) H.netlog.cur.f[#H.netlog.cur.f + 1] = v and "T" or "F" end,
  WriteTable = function(v) H.netlog.cur.f[#H.netlog.cur.f + 1] = v end,
  Send = function() if H.netlog.cur then H.netlog[#H.netlog + 1] = H.netlog.cur H.netlog.cur = nil end end,
  Broadcast = function() if H.netlog.cur then H.netlog.latestBroadcast = H.netlog.cur H.netlog.cur = nil end end,
  Receive = function(m, fn) H.netrecv[m] = fn end,
}
H.netrecv = {}
net.ReadUInt = function() return tonumber(table.remove(H.seq, 1)) or 0 end
net.ReadString = function() return tostring(table.remove(H.seq, 1) or "") end
net.ReadBool = function() local v = table.remove(H.seq, 1) return v == true or v == "T" end
H.seq = {}
TT = 1000
CurTime = function() return TT end
AddCSLuaFile = function() end

SERVER = true CLIENT = false
dofile("lua/autorun/sh_grm_qmenu.lua")
local QM = GRM.QMenu

local checks, failed = 0, 0
local function ok(cond, name)
  checks = checks + 1
  if cond then P("  ok " .. tostring(checks) .. ". " .. name)
  else failed = failed + 1 P("  FAIL " .. tostring(checks) .. ". " .. name) end
end
local function findNet(m)
  for i = #H.netlog, 1, -1 do if H.netlog[i].msg == m then return H.netlog[i] end end
  return nil
end
local function lastFeed()
  for i = #H.netlog, 1, -1 do if H.netlog[i].msg == "GRM_QMenu_Feedback" then return H.netlog[i] end end
  return nil
end
local function fireRecv(msg, ply, seq) H.seq = seq or {} H.netrecv[msg](0, ply) end
local function say(ply, text) H.hooks.PlayerSay["GRM_QMenu_Cmds"](ply, text) end

local admin = mkPly(1, true)
local pl = mkPly(2, false)
local pl2 = mkPly(3, false)

P("== 1. Дефолт конфига и круговой сейв/лоад ==")
ok(QM.Cfg.playersQ == true, "дефолт: ванильное Q открыто")
ok(QM.Cfg.grmBuildMenu == true, "дефолт: меню стройки включено")
ok(QM.Cfg.protectFurniture == true, "дефолт v3: защита мебели включена")
ok(QM.Cfg.menuPropCap == 24, "дефолт: лимит 24")
ok(QM.Cfg.adminsToo == false, "дефолт v3.2: суперадмин с ванильным Q (adminsToo=false)")
QM.Cfg.playersQ = false
QM.Cfg.propList = { "models/props_c17/furnituretable001a.mdl" }
ok(QM.Save("тест") == true, "Save отработал")
SNAP.protectFurniture = nil -- эмуляция старого файла БЕЗ нового поля v3
QM.Cfg = nil
QM = GRM.QMenu
QM.Load("тестовый лоад")
ok(QM.Cfg.playersQ == false, "playersQ=false доехал из файла")
ok(QM.Cfg.protectFurniture == true, "новое поле v3 дополнилось дефолтом")
ok(#QM.Cfg.propList == 1, "каталог доехал")

P("== 2. Гейты CanSpawn/CanUseTool ==")
ok(QM.CanSpawn(admin, "npc") == true, "суперадмин: NPC можно всегда")
ok(QM.CanSpawn(pl, "npc") == false, "игрок: NPC закрыт дефолтом")
ok(QM.CanSpawn(pl, "prop") == true, "игрок: пропы открыты дефолтом")
ok(QM.CanSpawn(pl, "vehicle") == false, "игрок: транспорт из Q закрыт")
local denyW = QM.CanUseTool(pl, "dynamite")
ok(denyW == false, "динамит в чёрном списке — запрет")
ok(QM.CanUseTool(pl, "weld") == true, "сварка разрешена дефолтом")
QM.Cfg.whitelistMode = true
ok(QM.CanUseTool(pl, "weld") == false, "белый режим: сварка вне списка — запрет")
QM.Cfg.toolAllow.weld = true
ok(QM.CanUseTool(pl, "weld") == true, "белый режим: сварка в toolAllow — можно")
QM.Cfg.whitelistMode = false
ok(QM.CanOpenQ(pl) == false, "playersQ=false → CanOpenQ игроку закрыто")
ok(QM.CanOpenQ(admin) == true, "суперадмину CanOpenQ всегда открыто")

P("== 3. Меню-пропы: каталог, валидация, лимит, рейт ==")
H.validModels = { ["models/props_c17/furnituretable001a.mdl"] = true, ["models/props_c17/oildrum001.mdl"] = true, ["models/x.mdl"] = true }
H.tr = { HitPos = V(0, 0, 0), HitNormal = V(0, 0, 1) }
local inCat = "models/props_c17/furnituretable001a.mdl"
ok(QM.CanSpawnMenuProp(pl, inCat) == true, "игроку можно модель из каталога")
local whyFree
_, whyFree = QM.CanSpawnMenuProp(pl, "models/x.mdl")
ok(whyFree ~= nil and string.find(whyFree, "вне каталога") ~= nil, "вне каталога — отказ (propsFree=false)")
ok(QM.CanSpawnMenuProp(pl, "models/../evil.mdl") == false, "путь с '..' отклонён")
QM.Cfg.propsFree = true
ok(QM.CanSpawnMenuProp(pl, "models/x.mdl") == true, "propsFree=true: любая модель")
QM.Cfg.propsFree = false
TT = 1000
local okSpawn, ent = QM.SpawnMenuProp(pl, inCat)
ok(okSpawn == true and IsValid(ent), "спавн из каталога — создан")
ok(ent:GetModel() == inCat, "модель на месте")
ok(ent.GRM_MenuOwner == pl, "владелец меню-пропа присвоен")
TT = TT + 0.1
local okFast = QM.SpawnMenuProp(pl, inCat)
ok(okFast == false, "рейт-лимит 0.4с: быстрый повтор отклонён")
TT = TT + 1
local okSpawn2, ent2 = QM.SpawnMenuProp(pl, inCat)
ok(okSpawn2 == true, "после паузы спавнится")
ok(#(QM._menuProps[pl] or {}) == 2, "реестр считает 2 пропа")
QM.Cfg.menuPropCap = 2
TT = TT + 1
local okCap = QM.SpawnMenuProp(pl, inCat)
ok(okCap == false, "лимит кэпа: третий не ставится")
QM.Cfg.menuPropCap = 24
local okAdmin, _ = QM.SpawnMenuProp(admin, "models/props_c17/oildrum001.mdl")
ok(okAdmin == true, "суперадмин спавнит вне каталога (байпас)")
local whyBad = select(2, QM.SpawnMenuProp(admin, "models/ghost.mdl"))
ok(string.find(tostring(whyBad), "не существует") ~= nil, "невалидная модель отклонена сервером")

P("== 4. undo/cleanup-регистрация (guard) ==")
_G.undo = { calls = {} }
undo.Create = function(n) undo.cur = { name = n, ents = {} } end
undo.AddEntity = function(e) undo.cur.ents[#undo.cur.ents + 1] = e end
undo.SetPlayer = function(p) undo.cur.ply = p end
undo.Finish = function() undo.calls[#undo.calls + 1] = undo.cur end
_G.cleanup = { added = {} }
cleanup.Add = function(p, t, e) cleanup.added[#cleanup.added + 1] = { p = p, t = t, e = e } end
TT = TT + 1
local okU, entU = QM.SpawnMenuProp(pl, inCat)
ok(okU == true, "спавн для undo-теста")
ok(#undo.calls >= 1 and undo.calls[#undo.calls].ents[1] == entU, "проп зарегистрирован в undo (Z работает)")
ok(#cleanup.added >= 1 and cleanup.added[#cleanup.added].e == entU, "проп зарегистрирован в cleanup движка")

P("== 5. Сеть: спавн/удаление/очистка + feedback-счётчик ==")
entU:Remove() -- освобождаем место под кэпом
TT = TT + 1 -- пауза против рейт-лимита
fireRecv("GRM_QMenu_SpawnProp", pl, { inCat })
local f1 = lastFeed()
ok(f1 ~= nil and f1.f[1] == 1 and f1.f[2] >= 1, "спавн через сеть → счётчик N обновлён")
fireRecv("GRM_QMenu_SpawnProp", pl, { "models/out.mdl" })
local f2 = lastFeed()
ok(f2 ~= nil and f2.f[1] == 2 and string.find(tostring(f2.f[2]), "вне каталога") ~= nil, "отказ спавна → тост с причиной")
-- «убрать проп в прицеле»: свой vs чужой
local ownList = QM._menuProps[pl]
local ownProp = nil
for _, e in ipairs(ownList or {}) do if IsValid(e) then ownProp = e break end end
ok(IsValid(ownProp), "у игрока есть свой проп для прицела")
pl.__aim = { Entity = ownProp, HitPos = V(0,0,0), HitNormal = V(0,0,1) }
fireRecv("GRM_QMenu_RemoveOne", pl, {})
ok(not IsValid(ownProp), "свой проп в прицеле удалён")
pl2.__aim = { Entity = QM._menuProps[pl][1], HitPos = V(0,0,0), HitNormal = V(0,0,1) }
fireRecv("GRM_QMenu_RemoveOne", pl2, {})
ok(IsValid(QM._menuProps[pl][1]), "чужой проп в прицеле НЕ удалён")
fireRecv("GRM_QMenu_ClearProps", pl, {})
local left = 0
for _, e in ipairs(QM._menuProps[pl] or {}) do if IsValid(e) then left = left + 1 end end
ok(left == 0, "очистка сняла все меню-пропы")

P("== 6. Куратор каталога и seed ==")
fireRecv("GRM_QMenu_Curate", pl, { 1, "models/x.mdl" })
local added = false
for _, m in ipairs(QM.Cfg.propList) do if m == "models/x.mdl" then added = true end end
ok(not added, "игроку куратор запрещён")
fireRecv("GRM_QMenu_Curate", admin, { 1, "models/x.mdl" })
added = false
for _, m in ipairs(QM.Cfg.propList) do if m == "models/x.mdl" then added = true end end
ok(added, "суперадмин добавил модель в каталог")
fireRecv("GRM_QMenu_Curate", admin, { 2, "models/x.mdl" })
added = false
for _, m in ipairs(QM.Cfg.propList) do if m == "models/x.mdl" then added = true end end
ok(not added, "суперадмин убрал модель из каталога")
-- seed: только валидные модели попадают
H.validModels["models/props_c17/furnituretable002a.mdl"] = true
H.validModels["models/props_junk/wood_crate001a.mdl"] = true
local before = #QM.Cfg.propList
fireRecv("GRM_QMenu_Seed", admin, {})
local after1 = #QM.Cfg.propList
-- валидны и вне каталога: furnituretable002a + wood_crate001a + oildrum001 (уже валиден с секции 3)
ok(after1 == before + 3, "seed долил ровно 3 валидные модели (остальные на сервере отсутствуют)")
fireRecv("GRM_QMenu_Seed", admin, {})
ok(#QM.Cfg.propList == after1, "повторный seed — 0 добавлений (дедуп)")

P("== 7. Настройки из меню (SetOpt) ==")
fireRecv("GRM_QMenu_SetOpt", pl, { "playersQ", false, false })
ok(QM.Cfg.playersQ == false, "игрок не может крутить настройки (осталось false=текущее)")
QM.Cfg.playersQ = true
fireRecv("GRM_QMenu_SetOpt", pl, { "playersQ", false, true })
ok(QM.Cfg.playersQ == true, "игроку SetOpt вообще запрещён")
fireRecv("GRM_QMenu_SetOpt", admin, { "playersQ", false, false })
ok(QM.Cfg.playersQ == false, "суперадмин выключил ванильное Q из меню")
fireRecv("GRM_QMenu_SetOpt", admin, { "hackMe", false, true })
ok(QM.Cfg.playersQ == false, "неизвестный ключ игнорируется")
fireRecv("GRM_QMenu_SetOpt", admin, { "menuPropCap", true, 9999 })
ok(QM.Cfg.menuPropCap == 500, "menuPropCap зажат до 500")
fireRecv("GRM_QMenu_SetOpt", admin, { "menuPropCap", true, 24 })
ok(QM.Cfg.menuPropCap == 24, "menuPropCap вернулся к 24")
fireRecv("GRM_QMenu_SetOpt", admin, { "protectFurniture", false, false })
ok(QM.Cfg.protectFurniture == false, "защита мебели выключается из меню")
fireRecv("GRM_QMenu_SetOpt", admin, { "protectFurniture", false, true })
fireRecv("GRM_QMenu_SetOpt", admin, { "adminsToo", false, true })
ok(QM.Cfg.adminsToo == true, "v3.2: adminsToo включается из меню (предпросмотр)")
fireRecv("GRM_QMenu_SetOpt", admin, { "adminsToo", false, false })
ok(QM.Cfg.adminsToo == false, "v3.2: adminsToo выключается обратно")

P("== 8. Защита мебели от remover (CanTool-hook) ==")
TT = TT + 1
local _, ownE = QM.SpawnMenuProp(pl, inCat)
local grmEnt = mkEnt("grm_cctv_camera")
local neutral = mkEnt("prop_physics")
local canToolFn = H.hooks.CanTool["GRM_QMenu_CanTool"]
ok(canToolFn(pl, { Entity = ownE }, "remover") == nil, "remover: свой меню-проп — можно")
ok(canToolFn(pl, { Entity = neutral }, "remover") == false, "remover: чужой проп — отказ")
ok(canToolFn(pl, { Entity = grmEnt }, "remover") == false, "remover: GRM-мебель — отказ")
ok(canToolFn(admin, { Entity = grmEnt }, "remover") == nil, "remover: суперадмин — байпас")
ok(canToolFn(pl, { Entity = ownE }, "weld") == nil, "другие инструменты без владельческой проверки")

P("== 9. Тулган и выбор инструмента ==")
fireRecv("GRM_QMenu_Toolgun", pl, { true })
ok(pl:HasWeapon("gmod_tool") == true, "тулган выдан при разрешённых инструментах")
fireRecv("GRM_QMenu_SetTool", pl, { "dynamite" })
ok(#pl.__cmds == 0, "запрещённый инструмент не ушёл в ConCommand")
fireRecv("GRM_QMenu_SetTool", pl, { "weld" })
ok(#pl.__cmds == 1 and string.find(pl.__cmds[1], "weld"), "разрешённый инструмент → gmod_tool weld")
fireRecv("GRM_QMenu_Toolgun", pl, { false })
ok(pl:HasWeapon("gmod_tool") == false, "тулкан убран")

P("== 10. /qm и легаси-команды ==")
say(pl, "/qm")
ok(findNet("GRM_QMenu_Open") ~= nil, "/qm → открытый push меню")
H.chatlog = {}
say(admin, "/qm_prop_addmodel models/abc.mdl")
local inCat2 = false
for _, m in ipairs(QM.Cfg.propList) do if m == "models/abc.mdl" then inCat2 = true end end
ok(inCat2, "/qm_prop_addmodel добавил в каталог")
say(admin, "/qm_prop_del models/abc.mdl")
inCat2 = false
for _, m in ipairs(QM.Cfg.propList) do if m == "models/abc.mdl" then inCat2 = true end end
ok(not inCat2, "/qm_prop_del убрал из каталога")
local dp = { "/qm" }
H.hooks.PlayerSayTransform["GRM_QMenu_TransformCmds"](pl, dp)
ok(dp[1] == "", "PlayerSayTransform глушит команду (SkipPlayerSay)")

P("== 11. Чистка при дисконнекте ==")
H.hooks.PlayerDisconnected["GRM_QMenu_Disconnect"](pl)
ok(QM._menuProps[pl] == nil and QM._spawnRate[pl] == nil, "реестр и рейт сняты при дисконнекте")

P("")
P(("РЕЗУЛЬТАТ: %d/%d проверок, провалов: %d"):format(checks - failed, checks, failed))
if failed > 0 then os.exit(1) end
P("SIM QMENU: OK")
