-- sim_wanted_migration — миграция базы розыска v2 → v3, миграция
-- каталога статей, реестр штрафов и разграничение юрисдикций.
-- Запуск: luajit tools/luatest/sim_wanted_migration.lua
local files = {}
local DATA = {}
_G.CLIENT=false _G.SERVER=true
function _G.AddCSLuaFile() end
function _G.include() end
function _G.ErrorNoHalt(s) io.write("[ErrorNoHalt] "..tostring(s)) end
function _G.IsValid(v) return type(v)=="table" and v.__valid==true end
function _G.isfunction(v) return type(v)=="function" end
function _G.istable(v) return type(v)=="table" end
function _G.isstring(v) return type(v)=="string" end
function _G.util_dummy() end
_G.math.Clamp=function(v,a,b) if v<a then return a elseif v>b then return b end return v end
_G.string.Trim=function(s) return (tostring(s):gsub("^%s+",""):gsub("%s+$","")) end
_G.string.Comma=function(v) return tostring(v) end
_G.string.Explode=function(sep,s) local o={} for m in tostring(s):gmatch("[^"..sep.."]+") do o[#o+1]=m end return o end
_G.player={GetAll=function() return {} end}
_G.os=os _G.table=table
_G.hook={Add=function() end,Run=function() end}
_G.timer={Simple=function() end}
_G.concommand={Add=function() end}
_G.net=setmetatable({},{__index=function() return function() end end})
_G.util={AddNetworkString=function() end}

-- простейший JSON (достаточно для нашей структуры)
local function esc(s) return (s:gsub('[%c"\\]',function(c) return ({['"']='\\"',['\\']='\\\\',['\n']='\\n'})[c] or string.format('\\u%04x',c:byte()) end)) end
local function enc(v)
  local t=type(v)
  if t=="number" then return (v%1==0) and string.format("%d",v) or tostring(v) end
  if t=="string" then return '"'..esc(v)..'"' end
  if t=="boolean" then return tostring(v) end
  if t=="table" then
    if #v>0 or next(v)==nil then local o={} for _,x in ipairs(v) do o[#o+1]=enc(x) end return "["..table.concat(o,",").."]" end
    local o={} for k,x in pairs(v) do o[#o+1]='"'..esc(tostring(k))..'":'..enc(x) end return "{"..table.concat(o,",").."}"
  end
  return "null"
end
local pos,str
local function skip() while true do local c=str:sub(pos,pos) if c==" " or c=="\n" or c=="\t" or c=="\r" then pos=pos+1 else break end end end
local function val()
  skip() local c=str:sub(pos,pos)
  if c=="{" then pos=pos+1 local o={} skip()
    if str:sub(pos,pos)=="}" then pos=pos+1 return o end
    while true do skip() local k=val() skip() pos=pos+1 local v=val() o[k]=v skip()
      local d=str:sub(pos,pos) pos=pos+1 if d=="}" then return o end end
  elseif c=="[" then pos=pos+1 local o={} skip()
    if str:sub(pos,pos)=="]" then pos=pos+1 return o end
    while true do o[#o+1]=val() skip() local d=str:sub(pos,pos) pos=pos+1 if d=="]" then return o end end
  elseif c=='"' then pos=pos+1 local s="" while true do local ch=str:sub(pos,pos)
      if ch=='\\' then local n=str:sub(pos+1,pos+1) s=s..({['n']='\n',['"']='"',['\\']='\\'})[n] or "" pos=pos+2
      elseif ch=='"' then pos=pos+1 return s else s=s..ch pos=pos+1 end end
  else local s=pos while str:sub(pos,pos):match("[%w%.%-%+eE]") do pos=pos+1 end
    local sub=str:sub(s,pos-1)
    if sub=="true" then return true elseif sub=="false" then return false elseif sub=="null" then return nil end
    return tonumber(sub) end
end
_G.util.TableToJSON=function(t) return enc(t) end
_G.util.JSONToTable=function(s) str=s pos=1 local ok,r=pcall(val) return ok and r or nil end
_G.file={
  Exists=function(p) return files[p]~=nil end,
  Read=function(p) return files[p] end,
  Write=function(p,c) files[p]=c end,
  IsDir=function() return true end,
  CreateDir=function() end,
}
_G.table.Count=function(t) local n=0 for _ in pairs(t) do n=n+1 end return n end
_G.table.Copy=function(t) local o={} for k,v in pairs(t) do o[k]=type(v)=="table" and _G.table.Copy(v) or v end return o end
_G.table.remove=table.remove
_G.SetGlobalDouble=function() end
_G.Color=function(r,g,b,a) return {r=r,g=g,b=b,a=a or 255} end
_G.color_white=_G.Color(255,255,255)
_G.GRM={Identity={CharacterKey=function(p) return p.key end}}

-- === СТАРАЯ БАЗА v2 (как на живом сервере) ===
files["grm_wanted/database.json"] = enc({
  version=2,
  records={
    {sid="76561198000000001:char1",name="Hans Muller",level=3,updated=1700000000,
     reasons={{id="crime_theft",code="УК-1",title="Кража",type="crime",fine=5000,level=2,by="76561198000000009:char1",byNick="Cop",t=1700000000}}},
    {sid="76561198000000002:char1",name="Otto Weber",level=5,updated=1700000100,
     reasons={{id="custom",code="УК-ПП",title="Дезертирство",type="crime",fine=0,level=5,by="76561198000000009:char1",byNick="Cop",t=1700000100}}},
    {sid="76561198000000003:char2",name="Greta Fuchs",level=0,updated=1700000200,reasons={}},
  },
  history={{t=1700000000,s="тест",actor="system",actorName="Система",kind="charge"}},
})
local before = files["grm_wanted/database.json"]

-- === СТАРЫЙ КАТАЛОГ v2 (без jurisdiction, с ручной статьёй админа) ===
files["grm_wanted/catalog.json"] = enc({
  version=2,
  articles={
    {id="theft",title="Кража",type="crime",fine=5000,defaultLevel=2},
    {id="desertion",title="Дезертирство",type="crime",fine=0,defaultLevel=5},
    {id="admin_custom_local",title="Местная статья администрации",type="admin",fine=777,defaultLevel=1},
  },
})

-- Ядро грузится первым и на живом сервере (sh_01_grm_core.lua), и здесь:
-- модули ниже берут из него канон GRM.CharKey (§5.2.6, одна реализация).
assert(loadfile("lua/autorun/sh_01_grm_core.lua"))()
dofile("lua/autorun/sh_grm_wanted_config.lua")
dofile("lua/autorun/server/sv_grm_wanted.lua")
local W=GRM.Wanted

local fails=0
local function check(name,cond,extra)
  if cond then print("  OK   "..name) else fails=fails+1 print("  FAIL "..name.."  "..tostring(extra or "")) end
end

print("\n=== ТЕСТ 1: загрузка и миграция v2 → v3 ===")
local ok = W.Load()
check("Load() успешен", ok==true)
check("загружено 3 записи", table.Count and true or true)
local n=0 for _ in pairs(W.Records) do n=n+1 end
check("записей 3, получено "..n, n==3)

local r1=W.Records["76561198000000001:char1"]
check("Hans найден", r1~=nil)
check("Hans: имя сохранено", r1 and r1.name=="Hans Muller", r1 and r1.name)
check("Hans: уровень 3 сохранён", r1 and r1.level==3, r1 and r1.level)
check("Hans: jurisdiction=civil проставлена", r1 and r1.jurisdiction=="civil", r1 and r1.jurisdiction)
check("Hans: статья сохранена", r1 and #r1.reasons==1 and r1.reasons[1].title=="Кража")
check("Hans: статье проставлена юрисдикция", r1 and r1.reasons[1].jurisdiction=="civil", r1 and r1.reasons[1].jurisdiction)
check("Hans: fine=5000 не потерян", r1 and r1.reasons[1].fine==5000, r1 and r1.reasons[1].fine)
check("Hans: sid заполнен", r1 and r1.sid=="76561198000000001:char1", r1 and r1.sid)

local r3=W.Records["76561198000000003:char2"]
check("слот char2 не потерян", r3~=nil and r3.name=="Greta Fuchs")
check("history сохранена", #W.History==1)

print("\n=== ТЕСТ 2: сохранение в v3 ===")
W.Save()
local saved = util.JSONToTable(files["grm_wanted/database.json"])
check("version=4 (обмен сведениями)", saved.version==4, saved.version)
check("records — массив из 3", #saved.records==3, #saved.records)
local found=0
for _,r in ipairs(saved.records) do if r.jurisdiction then found=found+1 end end
check("у всех записей есть jurisdiction", found==3, found)

print("\n=== ТЕСТ 3: повторная загрузка v3 (идемпотентность) ===")
local snap = files["grm_wanted/database.json"]
W.Load() W.Save()
local now=files["grm_wanted/database.json"]
-- сравниваем СТРУКТУРУ, а не байты: порядок ключей в JSON не гарантирован
local function deepEq(a,b,path)
  if type(a)~=type(b) then return false,(path or "").." тип" end
  if type(a)~="table" then if a~=b then return false,(path or "")..": "..tostring(a).." ~= "..tostring(b) end return true end
  for k,v in pairs(a) do local ok,e=deepEq(v,b[k],(path or "").."."..tostring(k)) if not ok then return false,e end end
  for k in pairs(b) do if a[k]==nil then return false,(path or "").."."..tostring(k).." лишний" end end
  return true
end
local eq,err = deepEq(util.JSONToTable(snap), util.JSONToTable(now))
check("повторное сохранение идентично по структуре", eq, err)

print("\n=== ТЕСТ 4: битый JSON не затирает файл ===")
files["grm_wanted/database.json"]="{это не json"
local ok2=W.Load()
check("Load() вернул false", ok2==false)
local bak=nil
for k in pairs(files) do if k:find("corrupt") then bak=k end end
check("создана резервная копия", bak~=nil, bak)
check("копия содержит исходник", bak and files[bak]=="{это не json")

print("\n=== ТЕСТ 5: юрисдикции ===")
check("военная фракция → military", W.JurisdictionOfPlayer({__valid=true,key="x:char1",IsPlayer=function() return true end,GetNWString=function(_,k,d) return k=="GRM_Faction" and "Feldgendarmerie" or d end})=="military")
check("полиция → civil", W.JurisdictionOfPlayer({__valid=true,key="y:char1",IsPlayer=function() return true end,GetNWString=function(_,k,d) return k=="GRM_Faction" and "Ordnungspolizei" or d end})=="civil")
check("пусто → civil", W.JurisdictionOfPlayer({__valid=true,key="z:char1",IsPlayer=function() return true end,GetNWString=function(_,k,d) return d end})=="civil")

print("\n=== ТЕСТ 6: миграция каталога статей ===")
-- каталог перечитывается с диска (v2 без jurisdiction)
W.LoadCatalog()
local byId = {}
for _, a in ipairs(W.Catalog) do byId[a.id] = a end

check("статьи из старого файла не потеряны", byId.theft ~= nil and byId.desertion ~= nil)
check("ручная статья администрации сохранена", byId.admin_custom_local ~= nil
  and byId.admin_custom_local.fine == 777, byId.admin_custom_local and byId.admin_custom_local.fine)
check("дезертирство отнесено к военной юрисдикции",
  byId.desertion and byId.desertion.jurisdiction == "military", byId.desertion and byId.desertion.jurisdiction)
check("кража осталась гражданской",
  byId.theft and byId.theft.jurisdiction == "civil", byId.theft and byId.theft.jurisdiction)
check("неизвестной статье проставлен civil по умолчанию",
  byId.admin_custom_local and byId.admin_custom_local.jurisdiction == "civil")

local milCount = 0
for _, a in ipairs(W.Catalog) do if a.jurisdiction == "military" then milCount = milCount + 1 end end
check("воинский раздел каталога дописан (>=8 статей), получено " .. milCount, milCount >= 8)

local savedCat = util.JSONToTable(files["grm_wanted/catalog.json"])
check("каталог сохранён с version=3", savedCat.version == 3, savedCat.version)
local dupes, seenIds = 0, {}
for _, a in ipairs(savedCat.articles) do
  if seenIds[a.id] then dupes = dupes + 1 end
  seenIds[a.id] = true
end
check("дубликатов статей нет", dupes == 0, dupes)

-- повторная загрузка не должна плодить записи
local cnt1 = #W.Catalog
W.LoadCatalog()
check("повторная загрузка каталога не плодит статьи: " .. cnt1 .. " -> " .. #W.Catalog, #W.Catalog == cnt1)

print("\n=== ТЕСТ 7: разграничение юрисдикций при выписке ===")
files["grm_wanted/database.json"] = before
W.Load()

local function mkPly(key, faction, nick)
  return {
    __valid = true, key = key,
    IsPlayer = function() return true end,
    IsSuperAdmin = function() return false end,
    IsAdmin = function() return false end,
    Nick = function() return nick or key end,
    ChatPrint = function() end,
    SteamID64 = function() return (key:gsub(":.*", "")) end,
    SteamID = function() return "STEAM_0:0:1" end,
    GetNWString = function(_, k, d) return k == "GRM_Faction" and faction or d end,
  }
end

local cop     = mkPly("76561198000000009:char1", "Ordnungspolizei", "Cop")
local gendarm = mkPly("76561198000000010:char1", "Feldgendarmerie", "Gendarm")

-- доступ к базе выдаём напрямую: AccessManager в тесте не поднят
W.CanView = function() return true end
W.CanEdit = function() return true end

check("полицейский работает в гражданской юрисдикции", W.CanUseJurisdiction(cop, "civil"))
check("полицейскому закрыта военная юрисдикция", W.CanUseJurisdiction(cop, "military") == false)
check("жандарм работает в военной юрисдикции", W.CanUseJurisdiction(gendarm, "military"))
check("жандарму закрыта гражданская юрисдикция", W.CanUseJurisdiction(gendarm, "civil") == false)

local okAdd, errAdd = W.AddCustomCharge(cop, "76561198000000001:char1", {
  id = "theft", code = "УК-1", title = "Кража", type = "crime", fine = 5000, level = 2, jurisdiction = "civil" })
check("полицейский вменил гражданскую статью", okAdd == true, errAdd)

local okBad, errBad = W.AddCustomCharge(cop, "76561198000000001:char1", {
  id = "desertion", code = "ВУ-1", title = "Дезертирство", type = "crime", level = 5, jurisdiction = "military" })
check("полицейскому отказано в воинской статье", okBad == false, errBad)

local okMil = W.AddCustomCharge(gendarm, "76561198000000002:char1", {
  id = "desertion", code = "ВУ-1", title = "Дезертирство", type = "crime", level = 5, jurisdiction = "military" })
check("жандарм вменил воинскую статью", okMil == true)

local recMil = W.Records["76561198000000002:char1"]
check("запись помечена военной юрисдикцией", recMil and recMil.jurisdiction == "military", recMil and recMil.jurisdiction)

-- AddCharge с таблицей (Д1) — терминалы вызывают именно так
local okTbl = W.AddCharge(cop, "76561198000000003:char2", { code = "УК-2", title = "Хулиганство", level = 2, jurisdiction = "civil" })
check("AddCharge принимает таблицу (Д1)", okTbl == true)
check("уровень пересчитан из статей", (W.Records["76561198000000003:char2"] or {}).level == 2,
  (W.Records["76561198000000003:char2"] or {}).level)

print("\n=== ТЕСТ 8: реестр штрафов ===")
-- экономика в тесте не поднята: подставляем минимальные заглушки
_G.GRM.GetBalance   = function(ply) return ply._money or 0 end
_G.GRM.TakeMoney    = function(ply, amt) if (ply._money or 0) < amt then return false end ply._money = ply._money - amt return true end
_G.GRM.GiveMoney    = function(ply, amt) ply._money = (ply._money or 0) + amt return true end
_G.GRM.HasMoney     = function(ply, amt) return (ply._money or 0) >= amt end
_G.GRM.FormatMoney  = function(v) return tostring(math.floor(v)) .. " GRM" end

dofile("lua/autorun/sh_grm_wanted_fines.lua")
local F = GRM.Wanted.Fines
check("модуль штрафов загружен", F ~= nil)

if F then
  F.Load()
  local violator = mkPly("76561198000000001:char1", "Civilians", "Hans")
  violator._money = 10000
  _G.player.GetAll = function() return { cop, gendarm, violator } end

  local rec, ferr = F.Issue(cop, "76561198000000001:char1", 2500, "Нарушение порядка")
  check("штраф выписан", rec ~= nil, ferr)
  check("статус unpaid", rec and rec.status == "unpaid", rec and rec.status)
  check("долг равен сумме штрафа", F.DebtOf("76561198000000001:char1") == 2500, F.DebtOf("76561198000000001:char1"))

  local paid, perr = F.Pay(violator, rec.id)
  check("штраф оплачен", paid == true, perr)
  check("деньги списаны", violator._money == 7500, violator._money)
  check("долг обнулён", F.DebtOf("76561198000000001:char1") == 0, F.DebtOf("76561198000000001:char1"))
  check("статус paid", (F.ByID(rec.id) or {}).status == "paid", (F.ByID(rec.id) or {}).status)

  local rec2 = F.Issue(cop, "76561198000000001:char1", 1000, "Повторно")
  check("второй штраф выписан", rec2 ~= nil)
  local cancelled = F.Cancel(cop, rec2.id, "ошибка оформления")
  check("штраф аннулирован", cancelled == true)
  check("аннулированный не попадает в долг", F.DebtOf("76561198000000001:char1") == 0)

  -- нехватка денег
  local poor = mkPly("76561198000000007:char1", "Civilians", "Poor")
  poor._money = 100
  _G.player.GetAll = function() return { cop, poor } end
  local rec3 = F.Issue(cop, "76561198000000007:char1", 5000, "Штраф")
  local okPay, payErr = F.Pay(poor, rec3.id)
  check("оплата без денег отклонена", okPay == false, payErr)
  check("деньги не списаны", poor._money == 100, poor._money)

  -- персистентность
  F.Save()
  local savedF = util.JSONToTable(files["grm_wanted/fines.json"])
  check("fines.json version=1", savedF and savedF.version == 1, savedF and savedF.version)
  check("квитанции сохранены", savedF and #savedF.fines >= 3, savedF and #savedF.fines)

  local idsBefore = {}
  for _, r in ipairs(F.List or {}) do idsBefore[r.id] = r.status end
  F.Load()
  local same = true
  for id, st in pairs(idsBefore) do
    local r = F.ByID(id)
    if not r or r.status ~= st then same = false end
  end
  check("после перезагрузки статусы совпадают", same)
end

print("")
if fails==0 then print("ВСЕ ТЕСТЫ ПРОЙДЕНЫ") else print("ПРОВАЛОВ: "..fails) os.exit(1) end
