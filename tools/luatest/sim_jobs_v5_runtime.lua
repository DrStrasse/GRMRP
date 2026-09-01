-- Focused runtime simulation for Jobs v5 topology and unloading.
SERVER=true;CLIENT=false;function AddCSLuaFile()end;NULL={_valid=false}
local now=100
function CurTime()return now end
function IsValid(v)return type(v)=="table"and v._valid~=false end
function istable(v)return type(v)=="table"end
function Vector(x,y,z)local v={x=x or 0,y=y or 0,z=z or 0};function v:DistToSqr(o)local a,b,c=self.x-o.x,self.y-o.y,self.z-o.z;return a*a+b*b+c*c end;function v:Distance(o)return math.sqrt(self:DistToSqr(o))end;function v:Length2D()return math.sqrt(self.x*self.x+self.y*self.y)end;return v end
function table.Count(t)local n=0;for _ in pairs(t)do n=n+1 end;return n end
util={AddNetworkString=function()end};net={Receive=function()end,Start=function()end,WriteTable=function()end,Send=function()end};hook={Add=function()end};timer={Create=function()end,Simple=function()end};player={GetAll=function()return{}end}
local bins={}
ents={FindByClass=function(cls)return cls=="grm_garbage_bin"and bins or{}end}
local function bin(x,name)local b={_valid=true,_pos=Vector(x,0,0),nw={},ready=0,name=name};function b:GetPos()return self._pos end;function b:SetNWString(k,v)self.nw[k]=v;self.nwWrites=(self.nwWrites or 0)+1 end;function b:GetNWString(k,d)local v=self.nw[k];if v==nil then return d end;return v end;function b:GetReadyAt()return self.ready end;function b:EntIndex()return x end;return b end
bins={bin(20,"A"),bin(1020,"B"),bin(9000,"orphan")}
GRM={Jobs={WorkConfig={garbageBindRadius=200,garbageCapacity=8,garbageUnloadTime=3},WorkPoints={
 {id="p1",type="garbage",name="Сбор 1",pos={x=0,y=0,z=0}},
 {id="p2",type="garbage",name="Сбор 2",pos={x=1000,y=0,z=0}},
 {id="d1",type="dump",name="Свалка",pos={x=2000,y=0,z=0}},
}}}
local JB=GRM.Jobs
local function obj(rec)local p=Vector(rec.pos.x,rec.pos.y,rec.pos.z);return{_grmJobPoint=rec,GetPos=function()return p end}end
function JB.GetRoutePoints(kind)local out={};for _,r in ipairs(JB.WorkPoints)do if r.type==kind then out[#out+1]=obj(r)end end;return out end
local active={tplId="garbage",points={{x=0,y=0,z=0},{x=1000,y=0,z=0},{x=2000,y=0,z=0}},pointNames={"a","b","dump"},pointIndex=1,garbagePointIDs={"p1","p2"},garbageDumpID="d1"}
JB.Active={x=active};JB.SaveActive=function()JB.saved=(JB.saved or 0)+1 end;JB.GetActiveJob=function()return active end;JB.PushTracker=function()end;JB.PushMyState=function()end
assert(loadfile("lua/autorun/sh_grm_jobs_v5.lua"))()
local fail,n=0,0;local function ok(v,msg)n=n+1;if v then print("  ok  "..msg)else fail=fail+1;print("  FAIL "..msg)end end
JB.RefreshGarbageTopology("test")
ok(JB.GarbageBindings.p1==bins[1]and JB.GarbageBindings.p2==bins[2],"nearest bins bind 1:1")
ok(bins[3].nw.GRM_GarbageState=="unbound","orphan bin remains unbound")
local writes=(bins[1].nwWrites or 0)+(bins[2].nwWrites or 0)+(bins[3].nwWrites or 0);local routes=JB.GetRoutePoints("garbage")or{}
ok(#routes==2,"only bound collection points are route candidates")
ok(((bins[1].nwWrites or 0)+(bins[2].nwWrites or 0)+(bins[3].nwWrites or 0))==writes,"unchanged topology emits no repeated NW writes")
JB.WorkPoints[1].pos.x=50;JB.RefreshGarbageTopology("move")
ok(active.points[1].x==50 and (JB.saved or 0)>0,"active route auto-updates and saves moved point")
local snap=JB.GarbageStateSnapshot()
ok(snap.summary.points==2 and snap.summary.bound==2 and snap.summary.bins==3 and snap.summary.dumps==1,"state snapshot reports topology")
local ply={_valid=true,nw={}};function ply:GetNWString(k,d)return self.nw[k]or d end;function ply:SetNWBool(k,v)self.nw[k]=v end;function ply:SetNWFloat(k,v)self.nw[k]=v end;function ply:SetNWEntity(k,v)self.nw[k]=v end;function ply:Nick()return"Driver"end;function ply:ChatPrint()end
local veh={_valid=true,_pos=Vector(2000,0,0),nw={},GRM_GarbageLoad=0};function veh:GetParent()return nil end;function veh:GetNWEntity()return nil end;function veh:GetPos()return self._pos end;function veh:GetVelocity()return Vector(0,0,0)end;function veh:GetDriver()return ply end;function veh:SetNWInt(k,v)self.nw[k]=v end;function veh:GetNWInt(k,d)local v=self.nw[k];if v==nil then return d end;return v end;function veh:SetNWString(k,v)self.nw[k]=v end;function veh:GetNWString(k,d)local v=self.nw[k];if v==nil then return d end;return v end;function veh:SetNWFloat(k,v)self.nw[k]=v end;function veh:GetNWFloat(k,d)local v=self.nw[k];if v==nil then return d end;return v end;function veh:SetNWEntity(k,v)self.nw[k]=v end;function veh:EntIndex()return 77 end
local seat={_valid=true,nw={},GRM_GarbageLoad=2};function seat:GetParent()return veh end;function seat:GetNWEntity()return nil end;function seat:GetNWInt(k,d)return self.nw[k]or d end;function seat:SetNWInt(k,v)self.nw[k]=v end
JB.MarkGarbageTruck(seat,ply,active)
ok(veh.GRM_GarbageLoad==2 and veh.nw.GRM_GarbageLoad==2,"seat cargo migrates to canonical vehicle root")
JB.Complete=function()JB.completed=true end
JB.TickGarbageDump(ply,active,seat,Vector(2000,0,0),170)
ok(active.garbageUnloadAt==103 and veh.nw.GRM_GarbageState=="unloading"and ply.nw.GRM_GarbageUnloading==true,"stationary truck starts replicated timed unload")
now=102;JB.TickGarbageDump(ply,active,seat,Vector(2000,0,0),170)
ok(not JB.completed and veh.GRM_GarbageLoad==2,"cargo remains before timer finishes")
now=104;JB.TickGarbageDump(ply,active,seat,Vector(2000,0,0),170)
ok(JB.completed and veh.GRM_GarbageLoad==0 and veh.nw.GRM_GarbageLoad==0,"finished unload clears cargo and completes route")
print(("JOBS V5 RUNTIME: %d/%d failures=%d"):format(n-fail,n,fail));os.exit(fail==0 and 0 or 1)
