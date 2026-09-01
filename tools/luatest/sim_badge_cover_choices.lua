-- Выбор официального удостоверения и любой действующей легенды прикрытия.
local function read(p)local f=assert(io.open(p,"rb"));local s=f:read("*a");f:close();return s end
local ctx=read("lua/autorun/sh_grm_ctx.lua");local docs=read("lua/autorun/sh_grm_documents.lua")
local fail=0;local function ok(c,n)if c then print("  ok  "..n)else fail=fail+1 print("  FAIL "..n)end end
ok(ctx:find("result.badgeChoices",1,true)~=nil,"сервер формирует список удостоверений")
ok(ctx:find("GRM.SpecialService.ListCovers",1,true)~=nil,"список включает все легенды")
ok(ctx:find('subType="cover:"',1,true)~=nil,"каждая легенда имеет серверный индекс")
ok(ctx:find("badgeChoiceMenu",1,true)~=nil and ctx:find("DermaMenu",1,true)~=nil,"клиент показывает меню выбора")
ok(ctx:find("choice.active",1,true)~=nil,"активная легенда отмечается звездой")
ok(ctx:find('net.WriteString(tostring(choice.subType',1,true)~=nil,"выбранный subtype отправляется серверу")
ok(docs:find('match("^cover:(%d+)$")',1,true)~=nil,"сервер разбирает только числовой индекс легенды")
ok(docs:find("GRM.SpecialService.CoversOf",1,true)~=nil,"сервер читает авторитетный список")
ok(docs:find('payload.status=="Действителен"',1,true)~=nil,"аннулированную легенду нельзя открыть")
ok(ctx:find('subType="official"',1,true)~=nil,"официальное удостоверение остаётся вариантом")
print(("BADGE/COVER CHOICES: 10 checks, failures=%d"):format(fail));os.exit(fail==0 and 0 or 1)
