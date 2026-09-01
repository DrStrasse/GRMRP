-- Физические документы: 7 типов, шесть копий, данные владельца, просмотр и дроп.
function istable(v)return type(v)=="table"end function isstring(v)return type(v)=="string"end function isfunction(v)return type(v)=="function"end function IsValid(v)return type(v)=="table"end
AddCSLuaFile=function()end
local H={handlers={},defs={},sent=nil,hooks={}}
timer={Simple=function(_,fn)fn()end}
hook={Add=function(n,id,fn)H.hooks[n]=H.hooks[n]or{} H.hooks[n][id]=fn end,Run=function()end}
net={Start=function(n)H.sent={name=n,fields={}}end,WriteString=function(v)table.insert(H.sent.fields,v)end,WriteTable=function(v)table.insert(H.sent.fields,v)end,WriteBool=function(v)table.insert(H.sent.fields,v)end,Send=function()end}
player={GetAll=function()return{}end}
string.Trim=function(s)return tostring(s or ""):match("^%s*(.-)%s*$")end
SERVER=true CLIENT=false
local inv={slots={}}
local target={_key="100:char1",SteamID64=function()return"100"end,IsPlayer=function()return true end,Nick=function()return"Владелец"end}
GRM={Identity={CharacterKey=function(p)return p._key end},Notify=function()end,Inventory={
 RegisterItem=function(id,d)H.defs[id]=d end,
 RegisterUseHandler=function(id,fn)H.handlers[id]=fn end,
 GetPlayerInv=function()return inv end,
 AddItem=function(_,id,count,data)for i=1,24 do if not inv.slots[i]then inv.slots[i]={id=id,count=count,data=data};return 0 end end return count end,
}}
GRM.Documents={Registry={},Templates={passport={},military={},license={},militaryLicense={},weaponLicense={},businessLicense={},factions={Police={}}}}
local buckets={passports="P-1",badges="B-1",military="M-1",licenses="L-1",milLicenses="ML-1",weaponLicenses="W-1",businessLicenses="BL-1"}
for bucket,num in pairs(buckets)do GRM.Documents.Registry[bucket]={ [target._key]={number=num,fullName="Иван Тест",faction="Police",status="Действителен"} } end

dofile("lua/autorun/sh_grm_physical_documents.lua")
local DOC=GRM.Documents; local fails=0
local function ok(c,n)if c then print("  ok  "..n)else fails=fails+1 print("  FAIL "..n)end end
local count=0 for _ in pairs(DOC.PhysicalDefs)do count=count+1 end
ok(count==7,"семь физических типов документов")
ok(H.defs.passport and H.defs.passport.maxStack==1 and H.defs.passport.model=="models/props_lab/clipboard.mdl","паспорт — отдельный бланк")
ok(H.defs.weapon_license and H.defs.business_license,"оружейная и бизнес-лицензии зарегистрированы")
for i=1,6 do local yes=DOC.GivePhysicalCopy(target,"passport",target._key,target); ok(yes,"копия паспорта "..i.."/6") end
local seventh,msg=DOC.GivePhysicalCopy(target,"passport",target._key,target)
ok(not seventh and tostring(msg):find("6",1,true),"седьмая копия запрещена")
ok(DOC.CountPhysicalCopies(target,"passport",target._key)==6,"подсчёт копий по владельцу")
local stolen=inv.slots[1]
local holder={_key="200:char1",SteamID64=function()return"200"end,IsPlayer=function()return true end}
H.handlers.doc_physical_view(holder,1,stolen,H.defs.passport)
ok(H.sent and H.sent.name=="GRM_Doc_ReceiveView" and H.sent.fields[1]=="passport" and H.sent.fields[2].number=="P-1","подобранная копия показывает документ исходного владельца")
local docsrc=assert(io.open("lua/autorun/sh_grm_documents.lua","rb")):read("*a")
local invsrc=assert(io.open("lua/autorun/sh_grm_inventory.lua","rb")):read("*a")
ok(docsrc:find("DOC.GivePhysicalCopy(targetPly",1,true)~=nil,"служебный компьютер автоматически выдаёт бланк")
local setID=assert(invsrc:find("ent:SetItemID(slot.id)",1,true)); local spawn=assert(invsrc:find("ent:Spawn()",setID,true)); ok(setID<spawn,"ItemID установлен до Spawn для правильной модели")
print(("PHYSICAL DOCUMENTS: failures=%d"):format(fails)); os.exit(fails==0 and 0 or 1)
