-- Контракт гражданского рынка: не запускает GMod, проверяет обязательные
-- серверные границы и точки интеграции до установки на сервер.
local pass, fail = 0, 0
local function ok(v, name)
 if v then pass=pass+1;print("  ok   "..name)else fail=fail+1;print("  FAIL "..name)end
end
local function read(p)local f=assert(io.open(p,"rb"));local s=f:read("*a");f:close();return s end
local civil=read("lua/autorun/sh_grm_civil_vehicle_market.lua")
local dealer=read("lua/autorun/sh_grm_vehicle_dealer.lua")
local precache=read("lua/autorun/sh_grm_vehicle_precache.lua")
local vendor=read("lua/entities/grm_vendor/init.lua")
local computer=read("lua/entities/grm_civil_vehicle_computer/init.lua")
ok(civil:find("GRM.CivilVehicles",1,true)~=nil and civil:find("grm_vehicle_market/civil.json",1,true)~=nil,"отдельный реестр гражданского рынка")
ok(civil:find("GRM.Economy.BankTake",1,true)~=nil and civil:find("GRM.TakeMoney",1,true)~=nil,"выбор оплаты наличными или со счёта")
ok(civil:find("GRM_CivilMarketNext",1,true)~=nil and civil:find("DistToSqr(source:GetPos())",1,true)~=nil,"rate-limit и проверка дистанции")
ok(civil:find("CV.Viewers",1,true)~=nil and civil:find("CV.PushViewers",1,true),"watcher и живой push рынка")
ok(civil:find("GRM.Boot.OnMapStart",1,true)~=nil and civil:find("GRM.Save.Register",1,true),"Boot и очередь persistence")
ok(dealer:find("function VD.CreatePersonalRecord",1,true)~=nil,"личная покупка идёт через общий гараж дилера")
ok(dealer:find("GRM.CivilVehicles.FindForDealer",1,true),"дилер показывает только ручной гражданский рынок")
ok(precache:find("GRM.CivilVehicles",1,true),"предзагрузка включает модели гражданского рынка")
ok(vendor:find('self.VendorType == "vehicle_market"',1,true),"торговец открывает общий рынок")
ok(computer:find("GRM.CivilVehicles.Open(ply,self)",1,true),"компьютер открывает рынок с серверной дистанцией")
print(("CIVIL VEHICLE MARKET: %d/%d failures=%d"):format(pass,pass+fail,fail))
if fail>0 then os.exit(1)end
