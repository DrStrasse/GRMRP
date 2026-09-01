-- Runtime regression for dedicated GRM Vendor persistence.
SERVER,CLIENT=true,false
function AddCSLuaFile() end
function istable(v)return type(v)=="table"end
function isstring(v)return type(v)=="string"end
function isfunction(v)return type(v)=="function"end
function IsValid(v)return type(v)=="table" and not v.removed end
string.StartWith=string.StartWith or function(s,p)return s:sub(1,#p)==p end
string.Trim=string.Trim or function(s)return tostring(s):match("^%s*(.-)%s*$")end
table.Copy=table.Copy or function(t)local o={} for k,v in pairs(t or{})do o[k]=type(v)=="table" and table.Copy(v)or v end return o end
table.HasValue=table.HasValue or function(t,v)for _,x in pairs(t)do if x==v then return true end end return false end
local Vec={} Vec.__index=Vec
function Vector(x,y,z)return setmetatable({x=x or 0,y=y or 0,z=z or 0},Vec)end
function Vec:DistToSqr(o)local x,y,z=self.x-o.x,self.y-o.y,self.z-o.z return x*x+y*y+z*z end
function Angle(p,y,r)return{p=p or 0,y=y or 0,r=r or 0}end
local FILES,JSON={},{}
util={AddNetworkString=function()end,CRC=function(s)return tostring(#tostring(s)*7919)end,
 TableToJSON=function(t)JSON[#JSON+1]=table.Copy(t);return"#J"..#JSON end,
 JSONToTable=function(s)local i=tonumber(tostring(s):match("#J(%d+)"));return i and table.Copy(JSON[i])end}
file={IsDir=function()return true end,CreateDir=function()end,Exists=function(p)return FILES[p]~=nil end,Read=function(p)return FILES[p]end,Write=function(p,s)FILES[p]=s end}
game={GetMap=function()return"gm_vendor_test"end}
function SysTime()return 1 end
local hooks,commands={},{}
hook={Add=function(n,id,fn)hooks[n]=hooks[n]or{};hooks[n][id]=fn end}
timer={Simple=function(_,fn)fn()end,Create=function()end}
concommand={Add=function(n,fn)commands[n]=fn end}
net={Receive=function()end,Start=function()end,WriteString=function()end,WriteBool=function()end,WriteTable=function()end,WriteEntity=function()end,Send=function()end}
local live={}
local function vendor()
 local e={class="grm_vendor",pos=Vector(),ang=Angle(),model="models/alyx.mdl",VendorType="weapon",nw={}}
 function e:GetClass()return self.class end function e:GetPos()return self.pos end function e:SetPos(v)self.pos=v end
 function e:GetAngles()return self.ang end function e:SetAngles(a)self.ang=a end function e:GetModel()return self.model end function e:SetModel(m)self.model=m end
 function e:SetNWString(k,v)self.nw[k]=v end function e:Spawn()end function e:Activate()end
 function e:GetPhysicsObject()return nil end
 function e:ApplyPermData(d)self.VendorType=d.vendorType;self.DisplayName=d.displayName;self.CustomPrices=d.customPrices;self.CustomLimits=d.customLimits;self.EnabledItems=d.enabledItems;self.GRMVendorID=d.vendorID end
 return e
end
ents={FindByClass=function(c)local o={}for _,e in ipairs(live)do if IsValid(e)and e.class==c then o[#o+1]=e end end return o end,
 Create=function(c)local e=vendor();e.class=c;live[#live+1]=e;return e end}
player={GetAll=function()return{}end}
GRM={Inventory={},Food={},Vendor=nil}

dofile("lua/autorun/sh_grm_vendor.lua")
local V=GRM.Vendor
local checks,failed=0,0
local function ok(v,n)checks=checks+1;if v then print("  ok "..checks..". "..n)else failed=failed+1;print("  FAIL "..checks..". "..n)end end
local e=vendor();e.pos=Vector(10,20,30);e.ang=Angle(0,90,0);e.VendorType="accessory";e.DisplayName="Экипировка полиции";e.CustomPrices={grm_acc_mask=777};e.CustomLimits={grm_acc_mask=2};e.EnabledItems={grm_acc_mask=true,grm_acc_hat=false};live={e}
local saved,id=V.SaveVendor(e)
ok(saved and id~="","specific vendor saved with stable ID")
ok(FILES["grm_vendors/gm_vendor_test.json"]~=nil,"dedicated per-map file written")
local stored=util.JSONToTable(FILES["grm_vendors/gm_vendor_test.json"])
ok(stored and stored.version==2 and stored.map=="gm_vendor_test" and type(stored.vendors)=="table","versioned wrapper avoids JSON array-key ambiguity")
FILES["grm_vendors/gm_vendor_test.json"]=util.TableToJSON({version=2,map="gm_vendor_test",vendors={["1"]=stored.vendors[1]}})
ok(#V.ListSavedVendors()==1,"string-keyed JSON vendor array is read with pairs")
live={}
local loaded,msg=V.LoadMapVendors()
ok(loaded and #live==1,"saved vendor respawned")
local restored=live[1]
ok(restored.VendorType=="accessory" and restored.CustomPrices.grm_acc_mask==777 and restored.CustomLimits.grm_acc_mask==2,"type prices and limits restored")
ok(restored.DisplayName=="Экипировка полиции" and restored.EnabledItems.grm_acc_mask==true and restored.EnabledItems.grm_acc_hat==false,"display name and enabled assortment restored")
V.LoadMapVendors()
ok(#live==1,"repeated load heals without duplicate")
restored.pos=Vector(50,60,70);V.SaveMapVendors();live={};V.SaveMapVendors();V.LoadMapVendors()
ok(#live==1 and live[1].pos.x==50,"save-all captures position and does not wipe absent saved vendor")
local savedID=live[1].GRMVendorID
ok(V.RemoveVendorSaveByID(savedID)==true,"specific vendor can be unsaved by stable ID after live removal")
live={};local emptyOK=V.LoadMapVendors();ok(emptyOK==false and #live==0,"empty database reports failure instead of fake successful load")
local perm=assert(io.open("lua/autorun/sh_grm_perm_entities.lua","rb")):read("*a")
local hub=assert(io.open("lua/autorun/server/sv_grm_persistence_hub.lua","rb")):read("*a")
ok(not perm:find("grm_vendor%s*=%s*true"),"generic perm no longer owns vendor class")
ok(hub:find('vendors%s*=%s*{') and hub:find('"vendors"'),"unified persistence hub includes vendors")
print(("VENDOR PERSISTENCE: %d/%d failures=%d"):format(checks-failed,checks,failed))
if failed>0 then os.exit(1)end
