-- Документы прикрытия: фракция из списка/вручную и индивидуальный цвет обложки.
local function read(p)local f=assert(io.open(p,"rb"));local s=f:read("*a");f:close();return s end
local ss=read("lua/autorun/sh_grm_special_service.lua");local docs=read("lua/autorun/sh_grm_documents.lua");local ui=read("lua/entities/grm_doc_computer/cl_init.lua")
local fail=0;local function ok(c,n)if c then print("  ok  "..n)else fail=fail+1 print("  FAIL "..n)end end
ok(ss:find("DColorMixer",1,true)~=nil,"терминал спецслужбы имеет палитру")
ok(ss:find("factionCombo",1,true)~=nil and ss:find("factionManual",1,true)~=nil,"спецслужба выбирает фракцию или ручное имя")
ok(ss:find("coverColor={r=col.r",1,true)~=nil,"цвет отправляется серверу")
ok(ss:find("coverColor  = istable(legend.coverColor)",1,true)~=nil,"сервер нормализует RGB")
ok(ss:find("foilStyle",1,true)~=nil,"хранится стиль тиснения")
ok(ui:find("coverMixer",1,true)~=nil and ui:find("DColorMixer",1,true)~=nil,"универсальный компьютер имеет палитру")
ok(ui:find("selectedCoverFaction",1,true)~=nil and ui:find("entCoverFacManual",1,true)~=nil,"универсальный компьютер поддерживает список и ручной ввод")
ok(docs:find("local function badgeTemplate",1,true)~=nil,"рендер строит индивидуальный шаблон")
ok(docs:find("rec.coverColor",1,true)~=nil and docs:find("rec.foilStyle",1,true)~=nil,"цвет и тиснение накладываются на бланк")
ok(docs:find("GRM.SpecialService.IssueCover",1,true)~=nil,"doc computer пишет легенду в единый список спецслужбы")
print(("COVER DESIGN CONFIG: 10 checks, failures=%d"):format(fail));os.exit(fail==0 and 0 or 1)
