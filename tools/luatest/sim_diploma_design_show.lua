-- Новый дизайн диплома и все способы предъявления.
local function read(p)local f=assert(io.open(p,"rb"));local s=f:read("*a");f:close();return s end
local edu=read("lua/autorun/sh_grm_education.lua"); local ctx=read("lua/autorun/sh_grm_ctx.lua")
local fail=0; local function ok(c,n)if c then print("  ok  "..n)else fail=fail+1 print("  FAIL "..n)end end
ok(edu:find("Color(247,241,220)",1,true)~=nil,"светлая бумага диплома")
ok(edu:find('draw.SimpleText("Д И П Л О М"',1,true)~=nil,"крупный заголовок диплома")
ok(edu:find("surface.DrawOutlinedRect(9,9,w-18,h-18,3)",1,true)~=nil,"двойная декоративная рамка")
ok(edu:find('draw.SimpleText("ПЕЧАТЬ"',1,true)~=nil and edu:find("surface.DrawCircle",1,true)~=nil,"государственная печать")
ok(edu:find('draw.SimpleText("АННУЛИРОВАН"',1,true)~=nil,"водяной знак аннулирования")
ok(edu:find('"/showdiploma"',1,true)~=nil and edu:find('"/покдиплом"',1,true)~=nil,"чат-команды предъявления")
ok(edu:find("EDU.ShowDiplomaToAim",1,true)~=nil,"серверный API предъявления")
ok(ctx:find('id = "doc_diploma"',1,true)~=nil and ctx:find("AskShow",1,true)~=nil,"кнопка предъявления в C-меню")
ok(edu:find("local nextMine",1,true)~=nil and edu:find("nextMine[ply]",1,true)~=nil,"запрос списка не блокирует последующий показ")
ok(edu:find("EDU.PickForShow",1,true)~=nil,"выбор одного из нескольких дипломов")
print(("DIPLOMA DESIGN/SHOW: 10 checks, failures=%d"):format(fail));os.exit(fail==0 and 0 or 1)
