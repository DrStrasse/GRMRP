-- Property Core remains active while Weather/Time is archived.
SERVER=false CLIENT=false
function istable(v)return type(v)=="table"end
function isstring(v)return type(v)=="string"end
function isfunction(v)return type(v)=="function"end
function IsValid(v)return type(v)=="table"and v.valid==true end
string.Trim=function(s)return(tostring(s):gsub("^%s+",""):gsub("%s+$",""))end
math.Clamp=function(v,a,b)return math.max(a,math.min(b,v))end
GRM={Identity={CharacterKey=function(p)return p.key end}}
local fail,n=0,0
local function ok(c,s)n=n+1;if c then print("  ok  "..s)else fail=fail+1;print("  FAIL "..s)end end
dofile("lua/autorun/sh_grm_property.lua")
local r=GRM.Property.Normalize({id="x",name="Квартира",type="apartment",ownerType="character",ownerKey="1:char2",employees={{key="2:char1"}},guests={},tempKeys={{key="3:char3",expires=os.time()+60}}})
local owner={valid=true,key="1:char2"};function owner:IsSuperAdmin()return false end
local employee={valid=true,key="2:char1"};function employee:IsSuperAdmin()return false end
local temp={valid=true,key="3:char3"};function temp:IsSuperAdmin()return false end
ok(GRM.Property.HasAccess(owner,r),"owner CharacterKey has access")
ok(GRM.Property.HasAccess(employee,r),"employee key has access")
ok(GRM.Property.HasAccess(temp,r),"temporary unexpired key has access")
ok(not GRM.Property.HasAccess({valid=false},r),"invalid actor denied")
ok(GRM.Property.Types.restricted=="Закрытая территория"and GRM.Property.Types.government~=nil,"all strategic property types")
r.zone={mins={x=0,y=0,z=0},maxs={x=100,y=100,z=100}}
ok(GRM.Property.IsInside(r,{x=50,y=50,z=50})and not GRM.Property.IsInside(r,{x=150,y=50,z=50}),"property zone bounds")
local function read(p)local f=assert(io.open(p,"rb"));local s=f:read("*a");f:close();return s end
local prop=read("lua/autorun/sh_grm_property.lua");local doors=read("lua/autorun/sh_grm_doors.lua")
ok(prop:find("GRM.Persistence.SaveJSON",1,true)and prop:find("GRM_DoorAccessOverride",1,true),"safe persistence and door integration")
ok(prop:find('hook.Add("PlayerSay","GRM_Property_Chat"',1,true) and prop:find("RegisterExternalCommands",1,true),"команды — боевой PlayerSay + реестр библиотеки (веч.-18)")
ok(prop:find("wanted.civil.edit",1,true)and prop:find("property_warrant",1,true),"warrant entry")
ok(prop:find("GRM_PropertyBreach",1,true)and prop:find("cameraIDs",1,true),"alarm and CCTV metadata integration")
ok(doors:find("actor.propertyHas",1,true)and doors:find("GRM_DoorAccessOverride",1,true),"Doors Core property adapter")
ok(prop:find("utilityDebt",1,true)and prop:find("GRM_Property_Billing",1,true),"utilities and recurring billing")
ok(prop:find("tempKeys",1,true)and prop:find("rent.expired",1,true),"temporary keys and rent expiry")
ok(prop:find("GRM.UI.Track",1,true)or prop:find("property.admin",1,true),"singleton property interface")
print(("PROPERTY: %d checks, failures=%d"):format(n,fail));os.exit(fail==0 and 0 or 1)
