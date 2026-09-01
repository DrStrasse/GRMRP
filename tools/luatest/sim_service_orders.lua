-- ATM service receipts in organization computers + duplicate door/menu guards.
local function read(p)local f=assert(io.open(p,"rb"));local s=f:read("*a");f:close();return s end
local orders=read("lua/autorun/sh_grm_service_orders.lua");local services=read("lua/autorun/sh_grm_services.lua");local atm=read("lua/autorun/sh_grm_atm.lua");local inc=read("lua/autorun/sh_grm_incassation.lua");local bank=read("lua/entities/grm_bank_terminal/cl_init.lua");local doors=read("lua/autorun/sh_grm_doors.lua");local char=read("lua/autorun/sh_grm_character.lua")
local fail,n=0,0;local function ok(c,s)n=n+1;if c then print("  ok  "..s)else fail=fail+1;print("  FAIL "..s)end end
ok(inc:find("function I.GetTerminalNumber",1,true)and inc:find("GRM_ATMNumber",1,true),"incassation provides stable ATM number")
ok(inc:find("rec.number=nextNumber",1,true)and inc:find("number=number",1,true),"ATM numbers persist for old and new records")
ok(bank:find("БАНКОМАТ №",1,true),"ATM displays its stable number")
ok(atm:find("stampInvoiceATM",1,true)and atm:find('orderSource="atm"',1,true),"ATM stamps ordered and separately paid invoices")
ok(atm:find("atmNumber=atmNumber",1,true)and atm:find("atmName=tostring",1,true),"service order stores ATM number and name")
ok(services:find("atmNumber=",1,true)and services:find("paidAt=",1,true)and services:find("orderSource=",1,true),"invoice persistence retains receipt metadata")
ok(services:find("function S.OrderedServicesForFaction",1,true),"organization service-order query")
ok(orders:find('tabs:AddSheet("Заказанные услуги"',1,true),"required service computer tab")
ok(orders:find("Игрок / персонаж",1,true)and orders:find("Банкомат",1,true)and orders:find("ОПЛАЧЕНО",1,true),"tab shows player, status, date and ATM")
ok(orders:find("services.orders.request",1,true)and orders:find("GRM.Net.Guard",1,true),"orders request is rate guarded")
local attached=0;for _,d in ipairs({"grm_comp_police","grm_comp_military_police","grm_comp_security","grm_comp_military","grm_comp_traffic","grm_comp_medical","grm_comp_cityhall","grm_comp_court","grm_doc_computer"})do local src=read("lua/entities/"..d.."/cl_init.lua");if src:find("GRM.ServiceOrders.AttachTab",1,true)then attached=attached+1 end end
ok(attached==9,"ordered services attached to all nine organization computers")
ok(doors:find("function D.CollapseDuplicateRecords",1,true)and doors:find("GRM_DoorAlias",1,true),"phantom door records collapse to one canonical door")
ok(doors:find("D.CollapseDuplicateRecords()",1,true)and doors:find("OnEntityCreated",1,true),"door dedup runs before save and after entity changes")
ok(char:find("CH._opening",1,true)and char:find("CH._queuedPayload",1,true),"character menu serializes overlapping payload builds")
ok(char:find("CH._actionPending",1,true)and char:find("character.menu.save",1,true),"character buttons and server save are single-shot")
print(("SERVICE ORDERS/GUARDS: %d checks, failures=%d"):format(n,fail));os.exit(fail==0 and 0 or 1)
