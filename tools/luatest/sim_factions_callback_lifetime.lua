-- Callback не должен обращаться к DTextEntry после refreshAllUI, удаляющего панель.
local f=assert(io.open("lua/autorun/sh_factions.lua","rb"));local s=f:read("*a");f:close()
local fail=0;local function ok(c,n)if c then print("  ok  "..n)else fail=fail+1 print("  FAIL "..n)end end
ok(s:find('refreshAllUI() newEntry:SetText("")',1,true)==nil,"нет SetText после refresh для role/dept")
ok(s:find('refreshAllUI() nameEntry:SetText("")',1,true)==nil,"нет SetText после refresh при создании")
ok(s:find('refreshAllUI() renameEntry:SetText("")',1,true)==nil,"нет SetText после refresh при переименовании")
local count=0;for _ in s:gmatch('if IsValid%(newEntry%) then newEntry:SetText%(""%) end refreshAllUI%(%)')do count=count+1 end
ok(count==4,"четыре формы role/dept очищаются безопасно до refresh")
ok(s:find('if IsValid(nameEntry)then nameEntry:SetText("")end;if IsValid(displayEntry)then displayEntry:SetText("")end;if IsValid(leaderEntry)',1,true)~=nil,"три поля создания защищены IsValid")
ok(s:find('if IsValid(renameEntry) then renameEntry:SetText("") end refreshAllUI()',1,true)~=nil,"поле переименования защищено")
-- Мини-воспроизведение исходного порядка.
local entry={valid=true};function entry:SetText()assert(self.valid,"NULL Panel")end
local function refresh()entry.valid=false end
local oldOK=pcall(function()refresh();entry:SetText("")end)
local newOK=pcall(function()if entry.valid then entry:SetText("")end;refresh()end)
ok(not oldOK,"стенд воспроизводит старое NULL Panel")
ok(newOK,"новый порядок не обращается к NULL Panel")
print(("FACTIONS CALLBACK LIFETIME: 8 checks, failures=%d"):format(fail));os.exit(fail==0 and 0 or 1)
