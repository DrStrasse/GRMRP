-- Real server clock in TAB and automatic GPS destination completion.
SERVER=false CLIENT=false
GRM={}
function istable(v)return type(v)=="table"end
function isstring(v)return type(v)=="string"end
function isfunction(v)return type(v)=="function"end
function IsValid()return false end
string.Trim=function(s)return(tostring(s):gsub("^%s+",""):gsub("%s+$",""))end
math.Clamp=function(v,a,b)return math.max(a,math.min(b,v))end
game={GetMap=function()return"gm_test"end}
dofile("lua/autorun/sh_grm_realtime.lua")
local mf=assert(io.open("lua/autorun/sh_grm_minimap.lua","rb"));local minimapSource=mf:read("*a");mf:close();local cut=assert(minimapSource:find("\nif SERVER then\n    util.AddNetworkString",1,true));local sharedPrefix=minimapSource:sub(1,cut-1);assert(loadstring(sharedPrefix,"minimap_shared"))()
local fail,n=0,0;local function ok(c,s)n=n+1;if c then print("  ok  "..s)else fail=fail+1;print("  FAIL "..s)end end
ok(GRM.Time.FormatOffset(0,180)=="03:00:00","UTC+3 wall-clock formatting")
ok(GRM.Time.FormatOffset(3661,0)=="01:01:01","HH:MM:SS formatting")
ok(GRM.Minimap.HasArrived({x=0,y=0,z=0},{x=100,y=0,z=20},120,180),"destination reached inside radius")
ok(not GRM.Minimap.HasArrived({x=0,y=0,z=0},{x=140,y=0,z=0},120,180),"destination outside horizontal radius")
ok(not GRM.Minimap.HasArrived({x=0,y=0,z=0},{x=20,y=20,z=300},120,180),"different floor does not trigger arrival")
local function read(p)local f=assert(io.open(p,"rb"));local s=f:read("*a");f:close();return s end
local time=read("lua/autorun/sh_grm_realtime.lua");local tab=read("lua/autorun/sh_grm_tab_menu.lua");local gps=read("lua/autorun/sh_grm_minimap.lua")
ok(time:find("GRM_RealTime_Sync",1,true)and time:find("grm_time_utc_offset_minutes",1,true)and time:find("GRM_RealTimeEpoch",1,true),"server-authoritative real-time sync (эпохой, без строкового глобала)")
ok(time:find("/time",1,true)and time:find("PlayerSayTransform",1,true),"time command supports chat and EasyChat")
ok(tab:find("clockPanel",1,true)and tab:find("GRM.Time.GetString",1,true),"TAB header contains live clock panel")
ok(gps:find("GRM_GPS_AutoArrival",1,true)and gps:find("arrivalSince",1,true),"GPS arrival is stable and automatic")
ok(gps:find("Вы достигли места назначения.",1,true)and gps:find("notification.AddLegacy",1,true),"arrival notification has required text")
ok(gps:find("reachedTemp",1,true)and gps:find("MM.ClearGPS",1,true),"reached target and temporary marker disappear locally")
ok(io.open("lua/autorun/sh_grm_weather.lua","rb")==nil,"Weather module remains absent")
print(("REALTIME/GPS: %d checks, failures=%d"):format(n,fail));os.exit(fail==0 and 0 or 1)
