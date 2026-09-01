-- C-меню читает физические документы; инвентарь различает своих и чужих.
local function read(p)local f=assert(io.open(p,"rb"));local s=f:read("*a");f:close();return s end
local ctx=read("lua/autorun/sh_grm_ctx.lua");local ui=read("lua/autorun/client/cl_grm_inventory_ui.lua");local med=read("lua/autorun/sh_grm_medical.lua");local pdoc=read("lua/autorun/sh_grm_physical_documents.lua");local e911=read("lua/autorun/sh_grm_911.lua")
local fail=0;local function ok(c,n)if c then print("  ok  "..n)else fail=fail+1 print("  FAIL "..n)end end
ok(ctx:find("local function hasOwnItem",1,true)~=nil,"C-меню имеет проверку физического предмета")
ok(ctx:find('hasOwnItem("passport","passport")',1,true)~=nil,"паспорт требует предмет")
ok(ctx:find('hasOwnItem("military_ticket","military")',1,true)~=nil,"военный билет требует предмет")
ok(ctx:find('hasOwnItem("weapon_license","weaponLicense")',1,true)~=nil and ctx:find('hasOwnItem("business_license","businessLicense")',1,true)~=nil,"обе лицензии требуют предмет")
ok(ctx:find('hasOwnItem("medcard",nil)',1,true)~=nil,"медкарта C-меню требует предмет")
ok(ctx:find("owner==key",1,true)~=nil,"чужой ownerKey не считается своим")
ok(ui:find('"СВОЙ"',1,true)~=nil and ui:find('"ЧУЖОЙ"',1,true)~=nil,"инвентарь помечает свои и чужие документы")
ok(ui:find("Владелец:",1,true)~=nil,"инвентарь показывает владельца и номер")
ok(med:find("data.ownerKey or data.sid64",1,true)~=nil and med:find('docType = "medcard"',1,true)~=nil,"медкарта нормализует ownerKey и открывается")
ok(pdoc:find("ownerName=",1,true)~=nil and e911:find("clamp(t.reviveHealth,30,100)",1,true)~=nil,"копии хранят имя; лечение не ниже 30 HP")
print(("DOCUMENT INVENTORY OWNERSHIP: 10 checks, failures=%d"):format(fail));os.exit(fail==0 and 0 or 1)
