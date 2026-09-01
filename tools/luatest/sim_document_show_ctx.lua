-- Лицензии: рабочие команды предъявления + кнопки C-меню + адаптивная раскладка.
local function read(p)local f=assert(io.open(p,"rb"));local s=f:read("*a");f:close();return s end
local docs=read("lua/autorun/sh_grm_documents.lua")
local ctx=read("lua/autorun/sh_grm_ctx.lua")
local fail=0
local function ok(c,n)if c then print("  ok  "..n)else fail=fail+1 print("  FAIL "..n)end end
ok(docs:find('showDocToTarget(ply, "weaponLicense")',1,true)~=nil,"чат-команда предъявления оружейной лицензии")
ok(docs:find('showDocToTarget(ply, "businessLicense")',1,true)~=nil,"чат-команда предъявления бизнес-лицензии")
ok(docs:find('net.WriteString("weaponLicense") net.WriteTable(forView(wl, ply))',1,true)~=nil,"сервер отправляет дизайн оружейной лицензии цели")
ok(docs:find('net.WriteString("businessLicense") net.WriteTable(forView(bl, ply))',1,true)~=nil,"сервер отправляет дизайн бизнес-лицензии цели")
ok(ctx:find("result.hasWeaponLicense",1,true)~=nil and ctx:find("result.hasBusinessLicense",1,true)~=nil,"снимок C-меню содержит обе лицензии")
ok(ctx:find('id = "doc_weapon_lic"',1,true)~=nil and ctx:find('id = "doc_business_lic"',1,true)~=nil,"кнопки предъявления в C-меню")
ok(ctx:find('id = "doc_self_weapon_lic"',1,true)~=nil and ctx:find('id = "doc_self_business_lic"',1,true)~=nil,"кнопки личного просмотра в C-меню")
ok(ctx:find('net.WriteString("weaponLicense")',1,true)~=nil and ctx:find('net.WriteString("businessLicense")',1,true)~=nil,"кнопки отправляют правильные docType")
ok(ctx:find("rowsPerCol",1,true)~=nil and ctx:find("totalW",1,true)~=nil,"C-меню раскладывается в колонки")
ok(docs:find('"/покоружие"',1,true)~=nil and docs:find('"/покбизнес"',1,true)~=nil,"короткие русские команды показа")
print(("DOCUMENT SHOW CTX: 10 checks, failures=%d"):format(fail));os.exit(fail==0 and 0 or 1)
