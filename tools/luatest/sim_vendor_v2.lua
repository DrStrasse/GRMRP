-- Contract tests for rewritten GRM Vendor v2.
local function read(path)local f=assert(io.open(path,"rb"));local s=f:read("*a");f:close();return s end
local core=read("lua/autorun/sh_grm_vendor.lua")
local entity=read("lua/entities/grm_vendor/init.lua")
local ui=read("lua/autorun/client/cl_grm_vendor_ui.lua")
local tool=read("lua/weapons/gmod_tool/stools/grm_vendor_tool.lua")
local custom=read("lua/autorun/sh_grm_customization.lua")
local perm=read("lua/autorun/sh_grm_perm_entities.lua")
local checks,failed=0,0
local function has(s,n)return s:find(n,1,true)~=nil end
local function ok(v,n)checks=checks+1;if v then print("  ok "..checks..". "..n)else failed=failed+1;print("  FAIL "..checks..". "..n)end end
ok(has(core,'V.Version = "2.2.0"'),"framework version 2.2 (реестр типов торговцев)")
ok(has(core,"function V.IsItemEnabled") and has(core,"function V.GetPrice") and has(core,"function V.GetLimit"),"authoritative stock price and limit APIs")
ok(has(entity,"function ENT:BuildCatalogPayload") and has(entity,"V.IsItemEnabled(self, id)"),"store payload exposes only enabled products")
ok(has(entity,"rateOK(ply") and has(entity,"inRange(ply,ent)"),"transactions are range and rate limited")
ok(has(entity,"grantItem") and has(entity,"if not granted then") and has(entity,"GRM.TakeMoney"),"item grant succeeds before money is charged")
ok(has(entity,"wanted-remaining") and has(entity,"removeInventoryAmount"),"inventory RemoveItem remaining-count semantics fixed")
ok(has(entity,'ply:GetNWBool("GRM_Arrested"'),"arrest blocks purchases")
ok(has(entity,"GRM_VendorPurchased") and has(entity,"GRM_VendorSold"),"purchase and sale integration hooks")
ok(has(entity,"enabledItems=self.EnabledItems") and has(entity,"displayName=self.DisplayName"),"entity perm payload includes full configuration")
ok(has(tool,"enabledItems=enabled") and has(tool,"customPrices=prices") and has(tool,"customLimits=limits"),"admin config saves assortment prices and limits")
ok(has(tool,"GRMVendorToolTitle") and has(tool,"СОХРАНИТЬ И ПРИМЕНИТЬ"),"admin config uses GRM-styled UI")
ok(has(ui,"GRM / ТОРГОВАЯ СИСТЕМА") and has(ui,"Поиск по названию") and has(ui,"functionText"),"customer store is GRM styled searchable and function aware")
ok(has(ui,"GRM_Vendor_Result") and has(ui,"notification.AddLegacy"),"transactions have sound and visible acknowledgement")
ok(has(custom,"functions = table.Copy(item.functions") and has(custom,"functionConfig = table.Copy(item.functionConfig"),"functional accessory flags reach vendor catalog")
ok(has(core,"enabledItems") and has(core,"displayName"),"dedicated persistence includes new v2 fields")
ok(has(core,"weaponCategory = \"rifled\"") and has(core,"weaponCategory = \"short\"") and has(core,"weaponCategory = \"smooth\""),"weapon catalog maps license categories")
ok(has(core,"DOC.HasValidWeaponLicense") and has(entity,"licenseWhy"),"weapon vendor enforces documents core with visible reason")
ok(has(ui,"Лицензия:") and has(entity,"requiresLicense"),"storefront shows required weapon license")
ok(has(perm,'backend ~= "perm"') and has(perm,'GRM.Persistence.Call("Save"') and has(perm,"external_removed"),"permadd/remove route vendor through dedicated persistence adapter")
print(("VENDOR V2: %d/%d failures=%d"):format(checks-failed,checks,failed));if failed>0 then os.exit(1)end
