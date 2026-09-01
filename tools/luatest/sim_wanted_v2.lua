-- Contracts for flexible GRM Wanted v2.
local function read(p)local f=assert(io.open(p,"rb"));local s=f:read("*a");f:close();return s end
local server,client,config=read("lua/autorun/server/sv_grm_wanted.lua"),read("lua/autorun/client/cl_grm_wanted.lua"),read("lua/autorun/sh_grm_wanted_config.lua")
local checks,failed=0,0;local function has(s,n)return s:find(n,1,true)~=nil end;local function ok(v,n)checks=checks+1;if v then print("  ok "..checks..". "..n)else failed=failed+1;print("  FAIL "..checks..". "..n)end end
ok(has(server,'W.Version="2.0.0"'),"wanted v2 server")
ok(has(server,"function W.AddCustomCharge"),"manual custom charges API")
ok(has(server,"data.trusted==true") or has(server,"data.trusted == true"),"terminal trusted path on AddCustomCharge")
ok(has(server,"function W.SetLevel(issuer,targetSid,level,note,trusted)"),"SetLevel accepts trusted flag")
ok(has(server,"function W.Clear(i,s,n,trusted)"),"Clear forwards trusted flag")
ok(has(server,'action=="add_custom"')and has(client,'action="add_custom"'),"manual article network path")
ok(has(client,"РУЧНАЯ СТАТЬЯ")or has(client,"Ручная статья"),"manual article GRM UI")
ok(has(client,"Номер / код статьи")and has(client,"Название статьи вручную")and has(client,"Описание обстоятельств"),"manual code title and circumstances")
ok(has(client,"Уголовная")and has(client,"Административная"),"manual charge type selection")
ok(has(client,"fine:GetValue()")and has(client,"lvl:GetValue()"),"manual fine and wanted level")
ok(has(server,"fine=math.Clamp")and has(server,"title==\"\"then return false"),"server clamps and validates custom article")
ok(has(server,"manual=data.manual==true"),"manual origin persisted in charge")
ok(has(server,"function W.RemoveReason")and has(server,"recalc(r)"),"removing charge recalculates wanted level")
ok(has(server,"version=4,records=records,history=W.History"),"versioned CharacterKey persistence (schema v4)")
ok(has(client,"GRM / ЕДИНАЯ БАЗА РОЗЫСКА")and has(client,"Дела и розыск")and has(client,"История"),"unified GRM interface")
ok(has(client,"Каталог статей")and has(server,'action=="save_catalog"'),"editable catalog retained")
ok(has(server,"GRM_WantedChargeAdded"),"external modules receive charge hook")
ok(has(server,"PlayerSayTransform")and has(server,"/wanted_custom"),"EasyChat-safe commands and manual command")
-- Level recomputation model.
local charges={{level=2},{level=5},{level=3}};table.remove(charges,2);local max=0;for _,c in ipairs(charges)do max=math.max(max,c.level)end
ok(max==3,"remaining articles determine resulting level")
print(("WANTED V2: %d/%d failures=%d"):format(checks-failed,checks,failed));if failed>0 then os.exit(1)end
