-- /leaders всем; /members свой состав, суперадмину все.
function istable(v)return type(v)=="table"end function isstring(v)return type(v)=="string"end function isfunction(v)return type(v)=="function"end function IsValid(v)return type(v)=="table"end
string.Trim=function(s)return tostring(s or""):match("^%s*(.-)%s*$")end
AddCSLuaFile=function()end;SERVER=true
hook={Add=function()end};timer={Create=function()end}
local function P(name,key,super)local p={name=name,key=key,super=super,msg={}};function p:IsSuperAdmin()return self.super end;function p:GetNWString(k,d)return k=="GRM_RPName"and self.name or d end;function p:Nick()return self.name end;function p:GetPos()return{x=1,y=2,z=3}end;function p:ChatPrint(t)self.msg[#self.msg+1]=t end;return p end
local a=P("Альфа","1:char1",false);local b=P("Бета","2:char1",false);local admin=P("Админ","9:char1",true);local outsider=P("Гость","3:char1",false)
local online={[a.key]=a,[b.key]=b}
GRM={Identity={ResolveCharacter=function(k)return online[k]end,FactionMember=function(f,p)return f.Members[p.key]end},FactionDuty={IsOnDuty=function(p)return p==a end,State={}}}
Factions={Police={Leader=a.key,Members={[a.key]={Role="Лидер",Department="Штаб"}}},Army={Leader=b.key,Members={[b.key]={Role="Командир",Department="Часть"}}}}
dofile("lua/autorun/sh_grm_faction_roster.lua")
local R=GRM.FactionRoster;local fail=0;local function ok(c,n)if c then print("  ok  "..n)else fail=fail+1 print("  FAIL "..n)end end
R.PrintMembers(a,"");ok(table.concat(a.msg,"\n"):find("Police",1,true)and not table.concat(a.msg,"\n"):find("Army",1,true),"участник видит только свою фракцию")
a.msg={};R.PrintMembers(a,"Army");ok(not table.concat(a.msg,"\n"):find("Army",1,true),"участник не может запросить чужую")
R.PrintMembers(outsider,"");ok(table.concat(outsider.msg,"\n"):find("не состоите",1,true),"игрок без фракции не видит состав")
R.PrintMembers(admin,"");local all=table.concat(admin.msg,"\n");ok(all:find("Police",1,true)and all:find("Army",1,true)and all:find("ВСЕ ФРАКЦИИ",1,true),"суперадмин видит все сгруппированные составы")
outsider.msg={};R.PrintLeaders(outsider);local leaders=table.concat(outsider.msg,"\n");ok(leaders:find("Police",1,true)and leaders:find("Army",1,true),"leaders доступна обычному игроку")
ok(leaders:find("В СЕТИ",1,true),"leaders показывает онлайн-статус")
ok(all:find("НА СЛУЖБЕ",1,true)and all:find("1 2 3",1,true),"состав показывает duty и координаты")
print(("ROSTER PERMISSIONS: 7 checks, failures=%d"):format(fail));os.exit(fail==0 and 0 or 1)
