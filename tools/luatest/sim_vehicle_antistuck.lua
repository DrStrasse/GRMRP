-- Anti-stuck: ближайший выход, без верхнего этажа/стены/сырого fallback.
SERVER=true CLIENT=false
function AddCSLuaFile()end function istable(v)return type(v)=="table"end function isnumber(v)return type(v)=="number"end function isfunction(v)return type(v)=="function"end function IsValid(v)return type(v)=="table"and v.valid~=false end
local M={};M.__index=M;M.__add=function(a,b)return Vector(a.x+b.x,a.y+b.y,a.z+b.z)end;M.__sub=function(a,b)return Vector(a.x-b.x,a.y-b.y,a.z-b.z)end;M.__mul=function(a,b)if type(a)=="number"then return Vector(a*b.x,a*b.y,a*b.z)end return Vector(a.x*b,a.y*b,a.z*b)end;M.__unm=function(a)return Vector(-a.x,-a.y,-a.z)end
function M:LengthSqr()return self.x*self.x+self.y*self.y+self.z*self.z end function M:Normalize()local l=math.sqrt(self:LengthSqr());if l>0 then self.x,self.y,self.z=self.x/l,self.y/l,self.z/l end return self end function M:DistToSqr(o)local d=self-o;return d:LengthSqr()end
function Vector(x,y,z)return setmetatable({x=x or 0,y=y or 0,z=z or 0},M)end
vector_origin=Vector(0,0,0);math.Clamp=function(v,a,b)return math.max(a,math.min(b,v))end
MASK_PLAYERSOLID=1;MOVETYPE_NOCLIP=8;COLLISION_GROUP_DEBRIS_TRIGGER=2;COLLISION_GROUP_PLAYER=5
local upperMode=false;local wallMode=false
util={TraceLine=function(t)local p=t.endpos+Vector(0,0,72);local z=(upperMode or p.x>40) and 100 or 0;return{Hit=true,StartSolid=false,HitPos=Vector(p.x,p.y,z),HitNormal=Vector(0,0,1)}end,TraceHull=function(t)if t.start.x~=t.endpos.x or t.start.y~=t.endpos.y then return{Hit=wallMode,StartSolid=false}end return{Hit=false,StartSolid=false}end}
hook={Add=function()end};timer={Create=function()end,Simple=function()end};concommand={Add=function()end};player={GetAll=function()return{}end};ents={FindInSphere=function()return{}end}
function CurTime() return 10 end
local function ent(pos,isVeh,parent)
 local e={valid=true,pos=pos,parent=parent};function e:IsVehicle()return isVeh end;function e:GetClass()return isVeh and "prop_vehicle_prisoner_pod" or "sim_fphys_base"end;function e:GetParent()return self.parent end;function e:GetPos()return self.pos end;function e:GetRight()return Vector(0,1,0)end;function e:GetForward()return Vector(1,0,0)end;function e:GetChildren()return{}end;function e:OBBMins()return Vector(-45,-25,-15)end;function e:OBBMaxs()return Vector(45,25,35)end;function e:LocalToWorld(v)return self.pos+v end;function e:WorldToLocal(v)return v-self.pos end;function e:EntIndex()return isVeh and 2 or 1 end;return e
end
local base=ent(Vector(0,0,20),false,nil);local seat=ent(Vector(0,0,28),true,base)
local ply={valid=true,pos=Vector(0,0,0)};function ply:GetPos()return self.pos end;function ply:GetRight()return Vector(0,1,0)end;function ply:GetForward()return Vector(1,0,0)end;function ply:EntIndex()return 3 end

dofile("lua/autorun/zz_grm_vehicle_antistuck.lua")
local AS=GRM.VehicleAntiStuck;local fail=0;local function ok(c,n)if c then print("  ok  "..n)else fail=fail+1 print("  FAIL "..n)end end
local pos=AS.FindSafeExitPos(ply,seat)
ok(pos~=nil,"находит безопасную точку рядом")
ok(pos.z<=24,"не выбирает верхний этаж")
ok(math.sqrt((pos.x)^2+(pos.y)^2)<=180,"не переносит далеко")
upperMode=true;local none=AS.FindSafeExitPos(ply,seat);ok(none==nil,"без безопасной точки не использует сырой fallback")
upperMode=false;wallMode=true;local wall=AS.FindSafeExitPos(ply,seat);ok(wall==nil,"не телепортирует сквозь стену")
ok(AS.Config.PushVelocity==0,"после выхода нет отбрасывающего толчка")
local src=assert(io.open("lua/autorun/zz_grm_vehicle_antistuck.lua","rb")):read("*a")
ok(src:find("MaxUpwardDelta",1,true)and src:find("MaxExitDistance",1,true),"есть вертикальный и горизонтальный лимиты")
ok(src:find("return nil,nil,base",1,true)~=nil,"финальный отказ безопасен")
print(("VEHICLE ANTISTUCK: 8 checks, failures=%d"):format(fail));os.exit(fail==0 and 0 or 1)
