-- Runtime smoke test for real sh_grm_quests.lua server branch.
local pass,fail=0,0
local function ok(v,n)if v then pass=pass+1;print("  ok  "..n)else fail=fail+1;print("  FAIL "..n)end end
SERVER,CLIENT=true,false
local TT=100
function CurTime()return TT end
function AddCSLuaFile()end
function isstring(v)return type(v)=="string"end
function istable(v)return type(v)=="table"end
function isvector(v)return type(v)=="table"and v.__vec end
function isangle(v)return type(v)=="table"and v.__ang end
function IsValid(v)return type(v)=="table"and v.valid~=false end
function string.Trim(s)return tostring(s):match("^%s*(.-)%s*$")end
math.Clamp=function(v,a,b)return math.max(a,math.min(b,v))end
local function copy(v)local o={};for k,x in pairs(v or{})do o[k]=type(x)=="table"and copy(x)or x end;return o end
table.Copy=copy
local V={};V.__index=V
function Vector(x,y,z)return setmetatable({x=x or 0,y=y or 0,z=z or 0,__vec=true},V)end
function V:DistToSqr(o)local x,y,z=self.x-o.x,self.y-o.y,self.z-o.z;return x*x+y*y+z*z end
function Angle(p,y,r)return{p=p or 0,y=y or 0,r=r or 0,__ang=true}end
local files,json={},{ }
file={IsDir=function()return true end,CreateDir=function()end,Exists=function(p)return files[p]~=nil end,Read=function(p)return files[p]end,Write=function(p,s)files[p]=s end}
util={AddNetworkString=function()end,TableToJSON=function(t)local key="J"..tostring(#json+1);json[key]=copy(t);return key end,JSONToTable=function(s)return copy(json[s])end,IsValidModel=function()return true end}
game={GetMap=function()return"gm_test"end}
local hooks={};hook={Add=function(ev,id,fn)hooks[ev]=hooks[ev]or{};hooks[ev][id]=fn end,Run=function(ev,...)for _,fn in pairs(hooks[ev]or{})do fn(...)end end}
timer={Create=function()end,Simple=function(_,fn)fn()end}
concommand={Add=function()end}
ents={FindByClass=function()return{}end,Create=function()return{valid=false}end}
player={GetAll=function()return{}end}
net={Start=function(n)net.name=n end,WriteTable=function()end,WriteBool=function()end,WriteString=function()end,WriteFloat=function()end,Send=function()end,Receive=function()end,ReadString=function()return""end,ReadTable=function()return{}end}
local ply={valid=true,money=0,items={},pos=Vector(0,0,0)}
function ply:SteamID64()return"76561198000000999"end
function ply:IsSuperAdmin()return true end
function ply:Alive()return true end
function ply:GetPos()return self.pos end
GRM={Identity={CharacterKey=function()return"76561198000000999:char2"end},GiveMoney=function(p,n)p.money=p.money+n;return true end,Inventory={AddItem=function(p,id,n)p.items[id]=(p.items[id]or 0)+n;return 0 end,CountItem=function(p,id)return p.items[id]or 0 end,RemoveItem=function(p,id,n)p.items[id]=math.max(0,(p.items[id]or 0)-n);return true end}}
local achRec={u={}};GRM.Ach={Defs={},Register=function(d)GRM.Ach.Defs[d.id]=d end,RecOf=function()return achRec end,Unlock=function(_,d,r)r.u[d.id]=true end,ResetUnlock=function(_,id)achRec.u[id]=nil;return true end}
local chunk,err=loadfile("lua/autorun/sh_grm_quests.lua");ok(chunk~=nil,"real quest core parses: "..tostring(err));if not chunk then os.exit(1)end
local ran,rerr=pcall(chunk);ok(ran,"real quest core executes in server sandbox: "..tostring(rerr));local Q=GRM.Quests
local def,why=Q.NormalizeDefinition({id=" Intro Lore ",title="Введение",enabled=true,steps={{type="event",event="factory_produce",target="gpu_basic",count=2,title="GPU"}},rewards={money=500,items={badge=1}},cutscene={accept={{pos={x=1,y=2,z=3},ang={p=0,y=90,r=0},fov=999,duration=0}}}})
ok(def and def.id=="intro_lore"and def.steps[1].count==2,"definition normalized with safe ID and objective")
ok(def.cutscene.accept[1].fov==120 and def.cutscene.accept[1].duration==.25,"cutscene bounds clamped")
ok(def.cutscene.accept[1].id=="camera_1"and def.cutscene.accept[1].transition=="cut"and def.cutscene.accept[1].moveDuration==1,"cutscene start/link transition defaults normalized")
local legacyScene=Q.NormalizeDefinition({id="legacy_scene",title="Legacy",steps={{type="talk",npc="guide"}},cutscene={accept={{pos={},ang={}},{pos={x=10},ang={}}}}});ok(legacyScene.cutscene.accept[1].transition=="cut"and legacyScene.cutscene.accept[2].transition=="move","legacy camera lists migrate to direct start plus smooth links")
local dialogueDef=Q.NormalizeDefinition({id="dialogue",title="D",steps={{type="talk",npc="guide"}},dialogue={offer={{id="hello",speaker="Guide",text="Hello",choices={{text="Yes",next="job",action="accept"}}},{id="job",text="Work"}}}})
ok(dialogueDef and #dialogueDef.dialogue.offer==2 and dialogueDef.dialogue.offer[1].choices[1].action=="accept","dialogue graph survives server normalization")
local draftDef=Q.NormalizeDefinition({id="draft",title="Draft",draft=true,steps={}});Q.Definitions.draft=draftDef
local draftStarted,draftWhy=Q.Start(ply,"draft");ok(draftDef and draftDef.draft and draftStarted==false and tostring(draftWhy):find("черновиком"),"empty admin draft saves but cannot start for a player")
local disabled=Q.NormalizeDefinition({id="disabled",title="Disabled",enabled=false,repeatable=true,autoStart=true,steps={{type="event",event="x"}}});Q.Definitions.disabled=disabled;local disabledStart=Q.Start(ply,"disabled");ok(disabled.enabled==false and disabled.repeatable and disabled.autoStart and disabledStart==false,"enabled and repeatable checkbox values persist; disabled blocks start")
local autoDef=Q.NormalizeDefinition({id="auto",title="Auto",autoStart=true,steps={{type="event",event="auto_evt"}}});Q.Definitions.auto=autoDef;hooks.PlayerInitialSpawn.GRM_Quest_Join(ply);ok(Q.GetProgress(ply,"auto")and Q.GetProgress(ply,"auto").status=="active","autoStart checkbox starts eligible newcomer quest")
Q.Definitions[def.id]=def
local started=Q.Start(ply,def.id);ok(started==true and Q.GetProgress(ply,def.id).status=="active","quest starts for CharacterKey")
Q.Event(ply,"factory_produce","gpu_mid",5);ok(Q.GetProgress(ply,def.id).step==1,"wrong production target rejected")
Q.Event(ply,"factory_produce","gpu_basic",1);ok(Q.GetProgress(ply,def.id).count==1,"matching event increments progress")
Q.Event(ply,"factory_produce","gpu_basic",1);local p=Q.GetProgress(ply,def.id);ok(p.status=="completed"and ply.money==500 and ply.items.badge==1,"completion grants authoritative money and item rewards")
local repeatDef=Q.NormalizeDefinition({id="repeat",title="Repeat",repeatable=true,achievement={enabled=true,id="repeat_ach",name="Repeat Hero"},steps={{type="event",event="repeat_evt",count=1}}});Q.Definitions["repeat"]=repeatDef;Q.Start(ply,"repeat");Q.Event(ply,"repeat_evt","",1);ok(achRec.u.repeat_ach==true,"quest completion unlocks configured custom achievement");local restarted=Q.Start(ply,"repeat");ok(restarted==true and Q.GetProgress(ply,"repeat").status=="active","repeatable checkbox permits a fresh run after completion")
local removed=Q.ResetProgress("repeat","76561198000000999:char2");ok(removed==1 and Q.GetProgress(ply,"repeat")==nil and achRec.u.repeat_ach==nil,"admin reset clears quest credit and linked achievement by CharacterKey")
ok(files[Q.ProgressFile]~=nil,"progress saved through read-back persistence")
print(("QUEST RUNTIME: %d/%d failures=%d"):format(pass,pass+fail,fail));if fail>0 then os.exit(1)end
