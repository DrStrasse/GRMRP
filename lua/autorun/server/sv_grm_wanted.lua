-- GRM Wanted v2.0 — flexible charges and unified case database
if CLIENT then return end
AddCSLuaFile("autorun/sh_grm_wanted_config.lua");AddCSLuaFile("autorun/client/cl_grm_wanted.lua");include("autorun/sh_grm_wanted_config.lua")
GRM=GRM or{};GRM.Wanted=GRM.Wanted or{};local W=GRM.Wanted;W.Version="2.0.0"
local DIR,DB,CAT="grm_wanted","grm_wanted/database.json","grm_wanted/catalog.json"
local OPEN,DATA,ACT,SYNC,INFO,DETAIL="GRM_Wanted_Open","GRM_Wanted_Data","GRM_Wanted_Act","GRM_Wanted_Sync","GRM_Wanted_Info","GRM_Wanted_List"
for _,n in ipairs({OPEN,DATA,ACT,SYNC,INFO,DETAIL})do util.AddNetworkString(n)end
W.Records=W.Records or{};W.Catalog=W.Catalog or{};W.History=W.History or{}
local function jsonT(s)local ok,t=pcall(util.JSONToTable,s or"",false,true);return ok and istable(t)and t end
local function ensure()if not file.IsDir(DIR,"DATA")then file.CreateDir(DIR)end end
local function write(path,data)local ok,s=pcall(util.TableToJSON,data,true);if not ok or not isstring(s)then return false end;file.Write(path,s);return file.Read(path,"DATA")==s end
local function key(v)if IsValid(v)and v:IsPlayer()then if GRM.Identity and GRM.Identity.CharacterKey then return GRM.Identity.CharacterKey(v)end;return tostring(v:SteamID64())..":char1"end;local s=tostring(v or"");if s:match(":char[1-3]$")then return s end;if s:match("^%d+$")then return s..":char1"end;return s end
local function notify(p,m,r,g,b)if not IsValid(p)then return end;if GRM.Notify then GRM.Notify(p,m,r or 100,g or 220,b or 120)else p:ChatPrint("[Розыск] "..m)end end
local function findPlayer(query)query=string.lower(tostring(query or""));for _,p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll())do if key(p)==query or p:SteamID64()==query or string.find(string.lower(p:Nick()),query,1,true)then return p end end end
local function history(text,actor,target,kind)W.History[#W.History+1]={t=os.time(),s=text,actor=IsValid(actor)and key(actor)or"system",actorName=IsValid(actor)and actor:Nick()or"Система",target=target,kind=kind};while #W.History>(W.Config.HistorySize or 200)do table.remove(W.History,1)end end
local function normalizeArticle(a,index)a=istable(a)and a or{};local id=string.lower(tostring(a.id or("article_"..index))):gsub("[^%w_%-]",""):sub(1,48);if id==""then return end;return{id=id,code=tostring(a.code or id):sub(1,32),type=(a.type=="admin"and"admin"or"crime"),title=tostring(a.title or id):sub(1,96),fine=math.Clamp(math.floor(tonumber(a.fine)or 0),0,100000000),defaultLevel=W.ClampLevel(a.defaultLevel or 1),jurisdiction=(a.jurisdiction=="military" and "military" or "civil"),description=tostring(a.description or""):sub(1,240)}end
-- Каталог v2 (до юрисдикций) не содержал полей jurisdiction и code.
-- На работающих серверах он уже сохранён в data/grm_wanted/catalog.json,
-- поэтому при загрузке недостающие поля восстанавливаются по эталонному
-- W.DefaultCatalog (совпадение по id), а отсутствующие статьи — прежде
-- всего воинские — дописываются. Ручные правки админов не затираются.
local function defaultArticle(id,title,code)
 id=tostring(id or""):lower()
 for _,a in ipairs(W.DefaultCatalog or{})do if tostring(a.id):lower()==id then return a end end
 -- id мог быть переименован админом: пробуем по коду и названию статьи
 local t=string.lower(string.Trim(tostring(title or"")))
 local c=string.lower(string.Trim(tostring(code or"")))
 if t=="" and c=="" then return end
 for _,a in ipairs(W.DefaultCatalog or{})do
  if c~="" and string.lower(tostring(a.code or""))==c then return a end
  if t~="" and string.lower(tostring(a.title or""))==t then return a end
 end
end
function W.LoadCatalog()
 ensure()
 local raw=file.Exists(CAT,"DATA")and jsonT(file.Read(CAT,"DATA"))
 local src=raw and(raw.articles or raw)or W.DefaultCatalog
 local ver=tonumber(raw and raw.version)or 0
 W.Catalog={}
 local seen={}
 for i,a in pairs(src or{})do
  local hadJur=istable(a)and a.jurisdiction~=nil
  local n=normalizeArticle(a,i)
  if n and not seen[n.id]then
   if not hadJur then
    local d=defaultArticle(n.id,n.title,istable(a)and a.code or nil)
    if d then
     n.jurisdiction=d.jurisdiction=="military"and"military"or"civil"
     if(not istable(a)or a.code==nil)and d.code then n.code=tostring(d.code):sub(1,32)end
    end
   end
   seen[n.id]=true;W.Catalog[#W.Catalog+1]=n
  end
 end
 -- дописываем эталонные статьи, которых нет в файле (воинский раздел)
 for i,a in ipairs(W.DefaultCatalog or{})do
  local n=normalizeArticle(a,i)
  if n and not seen[n.id]then seen[n.id]=true;W.Catalog[#W.Catalog+1]=n end
 end
 if #W.Catalog==0 then for i,a in ipairs(W.DefaultCatalog or{})do W.Catalog[#W.Catalog+1]=normalizeArticle(a,i)end end
 if ver<3 then print("[GRM Wanted] каталог статей мигрирован до v3: "..#W.Catalog.." статей")end
 W.SaveCatalog()
end
function W.SaveCatalog()return write(CAT,{version=3,articles=W.Catalog})end
local function catalog(id)for _,a in ipairs(W.Catalog)do if a.id==id then return a end end end
-- v4: к записи добавлены поля межведомственного обмена и спецслужб.
--   shared    — юрисдикции, которым передана копия сведений (Exchange);
--   transfers — история передач дела между структурами;
--   covert    — дело скрыто спецслужбой от ведомств.
-- Их обязательно нужно сохранять, иначе передача сведений и тайные
-- пометки терялись бы при первом же W.Save().
function W.Save()ensure();local records={}
 for sid,r in pairs(W.Records)do
  local row={sid=sid,name=r.name,level=W.ClampLevel(r.level),reasons=r.reasons or{},jurisdiction=r.jurisdiction=="military"and"military"or"civil",updated=r.updated or os.time()}
  if istable(r.shared)and next(r.shared)~=nil then row.shared=r.shared end
  if istable(r.transfers)and #r.transfers>0 then row.transfers=r.transfers end
  if r.covert==true then row.covert=true end
  records[#records+1]=row
 end
 table.sort(records,function(a,b)return a.sid<b.sid end)
 return write(DB,{version=4,records=records,history=W.History})end
-- МИГРАЦИЯ v2 → v3: записям без поля jurisdiction проставляется "civil".
-- Старые базы читаются без потерь; повреждённый файл не затирается, а
-- копируется в database.json.corrupt.<ts>, чтобы данные можно было спасти.
function W.Load()ensure();W.Records={};W.History={};if not file.Exists(DB,"DATA")then return true end
 local raw=file.Read(DB,"DATA");local t=jsonT(raw)
 if not t then local bak=DB..".corrupt."..os.time();if raw then file.Write(bak,raw)end;ErrorNoHalt("[GRM Wanted] database.json повреждён, копия: "..bak.."\n");return false end
 local srcVer=tonumber(t.version)or 2;local migrated=0
 for _,r in pairs(t.records or t)do if istable(r)and r.sid then
  local reasons=istable(r.reasons)and r.reasons or{}
  local j=r.jurisdiction=="military"and"military"or(r.jurisdiction=="civil"and"civil"or nil)
  if not j then j="civil";migrated=migrated+1 end
  for _,c in ipairs(reasons)do if istable(c)and c.jurisdiction~="military"and c.jurisdiction~="civil"then c.jurisdiction=j end end
  local row={sid=key(r.sid),name=tostring(r.name or"?"),level=W.ClampLevel(r.level),reasons=reasons,jurisdiction=j,updated=tonumber(r.updated)or os.time()}
  -- v3→v4: полей могло не быть — тогда они просто остаются пустыми.
  if istable(r.shared)then row.shared={civil=r.shared.civil==true or nil,military=r.shared.military==true or nil}end
  if istable(r.transfers)then row.transfers=r.transfers end
  if r.covert==true then row.covert=true end
  W.Records[key(r.sid)]=row
 end end
 W.History=istable(t.history)and t.history or{}
 if migrated>0 then print(("[GRM Wanted] Миграция v%d→4: юрисдикция 'civil' проставлена %d записям"):format(srcVer,migrated));W.Save()
 elseif srcVer<4 then print(("[GRM Wanted] Миграция v%d→4: добавлены поля обмена сведениями"):format(srcVer));W.Save()end
 return true end
local function record(sid,name,jur)local r=W.Records[sid];if not r then r={sid=sid,name=name or sid,level=0,reasons={},jurisdiction=jur or"civil",updated=os.time()};W.Records[sid]=r end;if name and name~=""then r.name=name end;if not r.sid then r.sid=sid end;if jur and jur~=""then r.jurisdiction=jur end;if r.jurisdiction~="military"then r.jurisdiction="civil"end;return r end
local function recalc(r)local level=0;for _,c in ipairs(r.reasons or{})do level=math.max(level,W.ClampLevel(c.level))end;r.level=level;r.updated=os.time()end
function W.GetLevel(v)local r=W.Records[key(v)];return r and W.ClampLevel(r.level)or 0 end
function W.GetRecord(v)return W.Records[key(v)]end
-- Д4: HUD аугментаций читает булев GRM_Wanted, ядро писало только
-- GRM_WantedLevel — индикатор всегда показывал «НЕТ». Пишем обе.
local function push(p)local r=W.Records[key(p)];local l=r and r.level or 0;p:SetNW2Int("GRM_WantedLevel",l);p:SetNWInt("GRM_WantedLevel",l);p:SetNWBool("GRM_Wanted",l>0);p:SetNWString("GRM_WantedJurisdiction",r and r.jurisdiction or"civil");net.Start(SYNC)net.WriteUInt(l,4)net.WriteString(r and r.name or"")net.Send(p)end
function W.CanView(p)if not IsValid(p)then return false end;if W.Config.SuperAdminBypass~=false and p:IsSuperAdmin()then return true end;return W.AccessManager and W.AccessManager.CanView and W.AccessManager.CanView(p)or false end
function W.CanEdit(p)if not IsValid(p)then return false end;if W.Config.SuperAdminBypass~=false and p:IsSuperAdmin()then return true end;return W.AccessManager and W.AccessManager.CanEdit and W.AccessManager.CanEdit(p)or false end
local function targetName(sid)local p=findPlayer(sid);return IsValid(p)and p:Nick()or(W.Records[sid]and W.Records[sid].name)or sid end

-- ── Юрисдикции ───────────────────────────────────────────────────────
-- "civil"    — Полиция Порядка (Ordnungspolizei), гражданские дела;
-- "military" — Полевая жандармерия (Feldgendarmerie), воинские дела.
-- Принадлежность персонажа определяется его фракцией: список военных
-- фракций настраивается в W.Config.MilitaryFactions, дополнительно
-- работает эвристика по названию (фолбэк для несконфигурированных).
function W.JurisdictionOfPlayer(p)
 if not(IsValid(p)and p:IsPlayer())then return"civil"end
 local f=p:GetNWString("GRM_Faction","")
 if f==""then return"civil"end
 local list=W.Config and W.Config.MilitaryFactions
 if istable(list)then
  if list[f]==true then return"military"end
  if list[f]==false then return"civil"end
 end
 local low=string.lower(f)
 for _,pat in ipairs(W.Config and W.Config.MilitaryPatterns or{})do
  if string.find(low,string.lower(pat),1,true)then return"military"end
 end
 return"civil"
end
-- Юрисдикция по ключу персонажа: онлайн — по фракции, офлайн — по записи.
function W.JurisdictionOfKey(k)
 k=key(k);local p=findPlayer(k)
 if IsValid(p)then return W.JurisdictionOfPlayer(p)end
 local r=W.Records[k]
 return r and r.jurisdiction=="military"and"military"or"civil"
end
-- Может ли сотрудник вести дела указанной юрисдикции.
-- Суперадмин и обладатели доступа "all" видят обе ветки.
function W.CanUseJurisdiction(p,j)
 if not IsValid(p)then return false end
 if W.Config.SuperAdminBypass~=false and p:IsSuperAdmin()then return true end
 if j~="military"and j~="civil"then return false end
 local own=W.JurisdictionOfPlayer(p)
 local AM=W.AccessManager
 if AM and isfunction(AM.JurisdictionOf)then
  local granted=AM.JurisdictionOf(p)
  if granted=="all"then return true end
  if granted=="civil"or granted=="military"then return granted==j end
 end
 return own==j
end
function W.AddCustomCharge(issuer,targetSid,data)
 -- data.trusted: терминал уже проверил T.CanEdit. Юрисдикцию не пропускаем.
 targetSid=key(targetSid);if targetSid==""then return false,"Нет цели"end;data=istable(data)and data or{};if not(data.trusted==true or W.CanEdit(issuer))then return false,"Нет прав"end;local title=string.Trim(tostring(data.title or"")):sub(1,96);if title==""then return false,"Введите название статьи"end
 -- Юрисдикция дела: явно переданная, иначе — по принадлежности цели.
 local jur=data.jurisdiction=="military"and"military"or(data.jurisdiction=="civil"and"civil"or W.JurisdictionOfKey(targetSid))
 if not W.CanUseJurisdiction(issuer,jur)then return false,jur=="military"and"Воинские дела ведёт только Feldgendarmerie"or"Гражданские дела ведёт только Полиция Порядка"end
 local target=findPlayer(targetSid);local r=record(targetSid,IsValid(target)and target:Nick(),jur);local charge={id=tostring(data.id or"custom"):sub(1,48),code=tostring(data.code or"РУЧНАЯ"):sub(1,32),title=title,type=data.type=="admin"and"admin"or"crime",text=tostring(data.text or""):sub(1,300),fine=math.Clamp(math.floor(tonumber(data.fine)or 0),0,100000000),jurisdiction=jur,by=key(issuer),byNick=issuer:Nick(),t=os.time(),level=W.ClampLevel(data.level or 1),manual=data.manual==true}
 r.reasons[#r.reasons+1]=charge;while #r.reasons>(W.Config.MaxReasonsPerPlayer or 32)do table.remove(r.reasons,1)end;recalc(r);history(("%s: + %s %s (ур.%d)"):format(r.name,charge.code,charge.title,charge.level),issuer,targetSid,"charge");W.Save();if IsValid(target)then push(target);notify(target,"Вменена статья: "..charge.code.." "..charge.title.." • розыск "..r.level,235,125,70)end;hook.Run("GRM_WantedChargeAdded",issuer,target,charge,r);return true,r.level
end
-- Д1: терминалы вызывали AddCharge(ply, target, {таблица}) — сигнатура
-- ждёт строковый id статьи, catalog(tostring(table)) не находил ничего и
-- кнопка «В розыск» молча не работала. Теперь таблица принимается и
-- перенаправляется в AddCustomCharge.
function W.AddCharge(issuer,targetSid,articleId,text,forceLevel)
 if istable(articleId)then local d=table.Copy(articleId);if text and text~=""and(d.text or"")==""then d.text=text end;if(tonumber(forceLevel)or 0)>0 then d.level=forceLevel end;return W.AddCustomCharge(issuer,targetSid,d)end
 local a=catalog(tostring(articleId or""));if not a then return false,"Статья каталога не найдена"end
 return W.AddCustomCharge(issuer,targetSid,{id=a.id,code=a.code,title=a.title,type=a.type,text=text,fine=a.fine,jurisdiction=a.jurisdiction,level=(tonumber(forceLevel)or 0)>0 and forceLevel or a.defaultLevel})end
function W.SetLevel(issuer,targetSid,level,note,trusted)targetSid=key(targetSid);if not(trusted==true or W.CanEdit(issuer))then return false,"Нет прав"end;local jur=W.JurisdictionOfKey(targetSid);if not W.CanUseJurisdiction(issuer,jur)then return false,jur=="military" and "Воинские дела ведёт только Feldgendarmerie" or "Гражданские дела ведёт только Полиция Порядка" end;local p=findPlayer(targetSid);local r=record(targetSid,IsValid(p)and p:Nick(),jur);local prevLevel=W.ClampLevel(r.level);level=W.ClampLevel(level);r.level=level;r.updated=os.time();if level==0 then r.reasons={}elseif note and note~=""then r.reasons[#r.reasons+1]={id="manual_level",code="УРОВЕНЬ",title=tostring(note):sub(1,96),type="crime",text="",fine=0,jurisdiction=jur,by=key(issuer),byNick=issuer:Nick(),t=os.time(),level=level,manual=true}end;local oldLevel=prevLevel;history(r.name..": уровень "..level,issuer,targetSid,"level");W.Save();if IsValid(p)then push(p)end;-- Хук нужен модулю ориентировок: по нему уходит «отбой» на волну.
 hook.Run("GRM_WantedLevelChanged",issuer,targetSid,oldLevel,level,note);return true,level end
function W.Clear(i,s,n,trusted)return W.SetLevel(i,s,0,n,trusted)end
function W.RemoveReason(issuer,sid,index)if not W.CanEdit(issuer)then return false,"Нет прав"end;sid=key(sid);local r=W.Records[sid];index=math.floor(tonumber(index)or 0);if not r or not r.reasons[index]then return false,"Статья не найдена"end;local c=table.remove(r.reasons,index);recalc(r);history(r.name..": удалена "..tostring(c.title),issuer,sid,"remove");W.Save();local p=findPlayer(sid);if IsValid(p)then push(p)end;return true,r.level end
local function listPayload()local out={}for sid,r in pairs(W.Records)do if r.level>0 or #(r.reasons or{})>0 then out[#out+1]={sid=sid,name=r.name,level=r.level,reasons=#r.reasons,updated=r.updated,totalFine=(function()local n=0 for _,c in ipairs(r.reasons)do n=n+(tonumber(c.fine)or 0)end return n end)()}end end;table.sort(out,function(a,b)return a.level==b.level and a.name<b.name or a.level>b.level end);return out end
local function online()local o={}for _,p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll())do o[#o+1]={nick=p:Nick(),sid64=key(p),level=W.GetLevel(p)}end;return o end
function W.OpenMenu(p)if not W.CanView(p)then notify(p,"Нет доступа к базе",255,100,100)return end;net.Start(DATA)net.WriteBool(W.CanEdit(p))net.WriteTable(listPayload())net.WriteTable(W.Catalog)net.WriteTable(online())net.WriteTable(W.History)net.WriteTable(W.Levels)net.WriteUInt(W.Config.MaxLevel or 5,4)net.Send(p)end
net.Receive(OPEN,function(_,p)W.OpenMenu(p)end)
net.Receive(ACT,function(_,p)local a=net.ReadTable()or{};local action=tostring(a.action or"");if action=="refresh"then W.OpenMenu(p)return end;if action=="get"then if not W.CanView(p)then return end;local sid=key(a.sid);local r=W.Records[sid];net.Start(DETAIL)net.WriteTable(r and{sid=sid,name=r.name,level=r.level,reasons=r.reasons,updated=r.updated}or{})net.Send(p)return end;if not W.CanEdit(p)then return end
 local ok,res;if action=="add_charge"then ok,res=W.AddCharge(p,a.sid,a.article,a.text,a.level)elseif action=="add_custom"then ok,res=W.AddCustomCharge(p,a.sid,{id="custom",code=a.code,title=a.title,type=a.type,text=a.text,fine=a.fine,level=a.level,manual=true})elseif action=="set_level"then ok,res=W.SetLevel(p,a.sid,a.level,a.text)elseif action=="clear"then ok,res=W.Clear(p,a.sid,a.text)elseif action=="remove_reason"then ok,res=W.RemoveReason(p,a.sid,a.index)elseif action=="save_catalog"and p:IsSuperAdmin()then local clean={}for i,row in pairs(a.catalog or{})do local n=normalizeArticle(row,i);if n then clean[#clean+1]=n end end;if #clean>0 then W.Catalog=clean;ok=W.SaveCatalog();res="Каталог сохранён"else ok=false;res="Каталог пуст"end end;notify(p,ok,tostring(ok and(res=="Каталог сохранён"and res or"Операция выполнена")or res),ok and 100 or 255,ok and 220 or 100,120);W.OpenMenu(p)end)
local function chatCommand(p,text)local args=string.Explode(" ",string.Trim(text or""));local c=string.lower(args[1]or"");if c=="/wanted"or c=="!wanted"or c=="/розыск"then W.OpenMenu(p)return true elseif c=="/wanted_clear"then local t=findPlayer(args[2])or args[2];if t then W.Clear(p,key(t),"Команда")end;return true elseif c=="/wanted_custom"then local t=findPlayer(args[2]);local level=tonumber(args[3]);local title=table.concat(args," ",4);if IsValid(t)and level and title~=""then local ok,e=W.AddCustomCharge(p,key(t),{code="РУЧНАЯ",title=title,level=level,manual=true});notify(p,ok,tostring(e))else notify(p,"/wanted_custom <игрок> <уровень> <статья>",255,180,80)end;return true end end
hook.Add("PlayerSayTransform","GRM_Wanted_Commands",function(p,pack)if not istable(pack)or not isstring(pack[1])then return end;if chatCommand(p,pack[1])then pack[1]="";pack.SkipPlayerSay=true end end);hook.Add("PlayerSay","GRM_Wanted_Fallback",function(p,t)if chatCommand(p,t)then return""end end)
hook.Add("PlayerInitialSpawn","GRM_Wanted_Join",function(p)timer.Simple(2,function()if IsValid(p)then local r=W.Records[key(p)];if r then r.name=p:Nick()end;push(p)end end)end)
concommand.Add("grm_wanted",function(p)if IsValid(p)then W.OpenMenu(p)end end);concommand.Add("grm_wanted_save",function(p)if not IsValid(p)or p:IsSuperAdmin()then W.Save()end end)
W.LoadCatalog();W.Load();print("[GRM Wanted] server v2.0 loaded records="..table.Count(W.Records))
