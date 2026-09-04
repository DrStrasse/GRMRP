-- GRM Core contracts: localization, capabilities, grants and infrastructure wiring.
SERVER=false CLIENT=false
function isstring(v)return type(v)=="string"end
function istable(v)return type(v)=="table"end
function isfunction(v)return type(v)=="function"end
function IsValid(v)return type(v)=="table"and v.valid~=false end
string.Trim=function(s)return (tostring(s):gsub("^%s+",""):gsub("%s+$",""))end
string.Explode=function(sep,s)local out={}for part in tostring(s):gmatch("[^"..sep.."]+")do out[#out+1]=part end return out end
hook={Run=function()end}

local fail,checks=0,0
local function ok(c,n)checks=checks+1;if c then print("  ok  "..n)else fail=fail+1;print("  FAIL "..n)end end

dofile("lua/autorun/sh_01_grm_core.lua")
dofile("lua/autorun/sh_02_grm_persistence.lua")
dofile("lua/autorun/sh_03_grm_access.lua")

ok(GRM.Core.Rule("identity.rp_scope")=="character","RP state uses character scope")
ok(GRM.Core.Rule("persistence.require_readback")==true,"read-back is a core rule")
ok(GRM.Lang.Get("core.access.denied",nil,"ru")=="Недостаточно прав.","Russian dictionary")
ok(GRM.Lang.Get("core.access.unknown",{capability="x.y"},"en")=="Unknown capability: x.y","English interpolation")
ok(GRM.Lang.Get("missing.key",nil,"en")=="missing.key","stable key fallback")
ok(GRM.Access.Capabilities["medical.patient.edit"]~=nil,"medical capability registered")
ok(GRM.Access.Capabilities["world.perm.manage"].scope=="account","admin capability has account scope")
ok(GRM.Persistence.Get("vendor")~=nil and GRM.Persistence.Get("cctv")~=nil and GRM.Persistence.Get("radionet")~=nil,"domain adapters registered")
local _, vendorBackend = GRM.Persistence.Resolve("grm_vendor")
local _, cctvBackend = GRM.Persistence.Resolve("grm_cctv_camera")
local _, radioBackend = GRM.Persistence.Resolve("grm_antenna")
ok(vendorBackend=="vendor" and cctvBackend=="cctv" and radioBackend=="radionet","backend routing by class")

local ply={valid=true}
function ply:IsPlayer()return true end
function ply:IsSuperAdmin()return false end
function ply:SteamID64()return "76561198000000001"end
function ply:GetNWString(key,default)local values={GRM_Faction="Hospital",GRM_Role="Doctor",GRM_Department="ER"};return values[key]or default end
GRM.Access.Grants={{capability="medical.patient.edit",subjectType="faction",subject="Hospital",allow=true,enabled=true}}
local allowed,source=GRM.Access.Check(ply,"medical.patient.edit")
ok(allowed==true and source:find("grant:",1,true)==1,"faction grant allows capability")
GRM.Access.Grants[#GRM.Access.Grants+1]={capability="medical.patient.edit",subjectType="character",subject="76561198000000001:char1",allow=false,enabled=true}
allowed=GRM.Access.Check(ply,"medical.patient.edit")
ok(allowed==false,"specific character deny overrides faction allow")
local explicit, explicitSource=GRM.Access.Explicit(ply,"medical.patient.edit")
ok(explicit==false and explicitSource:find("grant:",1,true)==1,"legacy adapters can read explicit decision without recursion")
allowed=GRM.Access.Check(ply,"unknown.capability")
ok(allowed==false,"unknown capability fails closed")

local function read(path)local f=assert(io.open(path,"rb"));local s=f:read("*a");f:close();return s end
local med=read("lua/entities/grm_comp_medical/init.lua")
ok(med:find('capability = "medical.patient.edit"',1,true)~=nil,"medical writes use common capability")
ok(med:find("GRM.Net.Guard",1,true)~=nil,"medical net intentions use Net Guard")
ok(med:find("GRM.Audit.Write",1,true)~=nil,"medical mutations use common audit")
local perm=read("lua/autorun/sh_grm_perm_entities.lua")
ok(perm:find('backend: %s',1,true)~=nil,"/perminfo displays backend")
ok(perm:find('GRM.Persistence.Register("perm"',1,true)~=nil,"central perm adapter registered")
local access=read("lua/autorun/sh_03_grm_access.lua")
ok(access:find('concommand.Add("grm_access"',1,true)~=nil and access:find('hook.Add("PlayerSay", "GRM_AccessCore_Chat"',1,true)~=nil and access:find("RegisterExternalCommands",1,true)~=nil,"unified editor: console + battle chat entry with library registry (веч.-18)")
ok(access:find("GRM_AccessCore_Save",1,true)~=nil and access:find("GRM.Net.Guard",1,true)~=nil,"unified editor save is guarded")
local hub=read("lua/autorun/sh_grm_admin_hub.lua")
ok(hub:find('RunConsoleCommand("grm_access")',1,true)~=nil,"admin hub Access tab opens unified editor")
for _,domain in ipairs({"fire","wanted","cctv","phone"})do
 local src=read("lua/autorun/sh_grm_"..domain.."_access.lua")
 ok(src:find("GRM.Access.Explicit",1,true)~=nil,domain.." honours explicit Core grants")
 ok(src:find("GRM.Net.Guard",1,true)~=nil and src:find("GRM.Audit.Write",1,true)~=nil,domain.." legacy admin writes are guarded and audited")
end
print(("CORE CONTRACTS: %d checks, failures=%d"):format(checks,fail));os.exit(fail==0 and 0 or 1)
