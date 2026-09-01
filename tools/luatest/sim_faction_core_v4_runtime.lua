-- Runtime simulation of personnel lifecycle inside factions.json records.
SERVER=true;CLIENT=false;function AddCSLuaFile()end;function istable(v)return type(v)=="table"end;function IsValid(v)return type(v)=="table"and v.valid==true end;function table.Copy(v)local o={};for k,x in pairs(v or{})do o[k]=type(x)=="table"and table.Copy(x)or x end;return o end
local hooks={};hook={Add=function(name,id,fn)hooks[name]=hooks[name]or{};hooks[name][id]=fn end,Run=function(name,...)for _,fn in pairs(hooks[name]or{})do fn(...)end end};timer={Simple=function(_,fn)fn()end};local saves=0;FactionsAPI={Save=function()saves=saves+1 end}
local member={Role="Офицер",Department="patrol"};Factions={police={DisplayName="Полиция",Departments={"patrol"},DepartmentDisplayNames={patrol="Патрульная служба"},Members={['1:char1']=member}}}
GRM={Identity={CharacterKey=function(p)return p.key end},FactionCore=nil};local actor={valid=true,key="9:char1",GetNWString=function(_,_,d)return d end,Nick=function()return"Начальник"end,SteamID64=function()return"9"end,IsPlayer=function()return true end}
assert(loadfile("lua/autorun/sh_grm_factions_core_v4.lua"))();local C=GRM.FactionCore;local fail,n=0,0;local function ok(v,msg)n=n+1;if v then print("  ok  "..msg)else fail=fail+1;print("  FAIL "..msg)end end
ok(member.Personnel and member.Personnel.status=="active","legacy member receives personnel file")
local recruit={Role="Стажёр",Department="patrol"};hook.Run("GRM_FactionMemberJoined","police","2:char1",recruit,actor,"invite");Factions.police.Members['2:char1']=recruit
ok(recruit.Personnel.hiredBy=="9:char1"and recruit.Personnel.history[1].type=="joined","join records recruiter and history")
hook.Run("GRM_FactionMemberRoleChanged","police","2:char1",recruit,"Стажёр","Офицер",actor);hook.Run("GRM_FactionMemberDepartmentChanged","police","2:char1",recruit,"patrol","detectives",actor)
ok(#recruit.Personnel.history==3 and recruit.Personnel.history[2].details.to=="Офицер","role/department changes append history")
local setOK=C.SetProbation("police","2:char1",os.time()+86400,actor)
ok(setOK and recruit.Personnel.status=="probation"and recruit.Personnel.probationUntil>os.time(),"probation state is persisted")
hook.Run("GRM_FactionMemberRemoved","police","2:char1",recruit,actor,"test");ok(Factions.police.PersonnelArchive['2:char1']~=nil and recruit.Personnel.status=="dismissed","dismissal archives personnel record")
ok(C.Revision>=4 and saves>=2,"domain revision and persistence advance")
print(("FACTION CORE V4 RUNTIME: %d/%d failures=%d"):format(n-fail,n,fail));os.exit(fail==0 and 0 or 1)
