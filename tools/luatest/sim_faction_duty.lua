-- GRM Faction Duty: статус, гражданская работа, модель/оружие и возврат на службу.
string.Trim=function(s)return tostring(s or ""):match("^%s*(.-)%s*$")end
function istable(v)return type(v)=="table"end function isstring(v)return type(v)=="string"end function isfunction(v)return type(v)=="function"end
function IsValid(v)return type(v)=="table"end
local H={hooks={},files={},modelApplies=0,weaponApplies=0}
util={AddNetworkString=function()end,JSONToTable=function(raw)return raw~="" and {records={}} or nil end,TableToJSON=function()return "{}"end,IsValidModel=function()return true end}
file={Read=function(p)return H.files[p]end,Write=function(p,v)H.files[p]=v end}
timer={Simple=function(_,fn)fn()end}
hook={Add=function(n,id,fn)H.hooks[n]=H.hooks[n]or{} H.hooks[n][id]=fn end,Run=function()end}
net={Receive=function()end,Start=function()end,WriteEntity=function()end,WriteString=function()end,WriteBool=function()end,Send=function()end}
AddCSLuaFile=function()end
function CurTime()return 10 end
SERVER=true CLIENT=false
local member={Role="Сотрудник",Department="Отдел"}
local fac={Members={}}
Factions={Police=fac}
GRM={Identity={CharacterKey=function(p)return p._key end,FactionMember=function(_,p)return p._member and member or nil end},Jobs={Active={}},Notify=function()end}
_G.FactionsAPI=nil
DefaultModels={{path="civil.mdl"}}
function GetModelsForPlayer(p)return p:GetNWBool("GRM_FactionOffDuty",false) and DefaultModels or {{path="police.mdl"}} end
function ApplyModelSettings(p,m)p._model=m.path H.modelApplies=H.modelApplies+1 end
function ApplyWeaponsToPlayer(p)H.weaponApplies=H.weaponApplies+1 end
local p={_key="100:char1",_member=true,_nw={}}
function p:IsPlayer()return true end function p:IsSuperAdmin()return false end function p:SteamID64()return"100"end function p:SteamID()return"STEAM_0:0:50"end function p:Nick()return"Офицер"end
function p:GetNWBool(k,d)local v=self._nw[k]if v==nil then return d end return v end function p:SetNWBool(k,v)self._nw[k]=v end function p:SetNWString()end

dofile("lua/autorun/sh_grm_faction_duty.lua")
local FD=GRM.FactionDuty; local fails=0
local function check(n,c)if c then print("[SIM] OK: "..n)else fails=fails+1 print("[SIM] FAIL: "..n)end end
check("член фракции по умолчанию на службе",FD.IsOnDuty(p))
check("на службе гражданская работа закрыта",not FD.CanTakeCivilJob(p))
local ok=FD.Set(p,false,p)
check("можно завершить службу",ok and not FD.IsOnDuty(p) and p:GetNWBool("GRM_FactionOffDuty"))
check("вне службы доступна гражданская работа",FD.CanTakeCivilJob(p))
check("применена гражданская модель и оружие",p._model=="civil.mdl" and H.modelApplies>0 and H.weaponApplies>0)
GRM.Jobs.Active[p._key]={title="Таксист"}
local ok2=FD.Set(p,true,p)
check("нельзя выйти на службу с активной подработкой",not ok2 and not FD.IsOnDuty(p))
GRM.Jobs.Active[p._key]=nil
local ok3=FD.Set(p,true,p)
check("возврат на службу восстанавливает форму",ok3 and FD.IsOnDuty(p) and p._model=="police.mdl")
p._member=false
check("гражданин без фракции может работать",FD.CanTakeCivilJob(p) and not FD.IsOnDuty(p))
local tool=assert(io.open("lua/weapons/gmod_tool/stools/grm_duty_npc.lua","rb")):read("*a")
local draw=assert(io.open("lua/entities/grm_duty_npc/cl_init.lua","rb")):read("*a")
local qmenu=assert(io.open("lua/autorun/sh_grm_qmenu.lua","rb")):read("*a")
check("новый NPC требует существующую фракцию",tool:find("Factions%[fac%]",1,false)~=nil and tool:find('faction = ""',1,true)~=nil)
check("ПКМ открывает отдельный админ-редактор",tool:find("OpenAdmin",1,true)~=nil)
check("Q-меню получает динамический список фракций",qmenu:find('dynamic = "factions"',1,true)~=nil and qmenu:find('payload._factions',1,true)~=nil)
check("tool запрашивает серверный список и явно пишет convar",tool:find("RequestToolFactions",1,true)~=nil and tool:find('RunConsoleCommand("grm_duty_npc_faction"',1,true)~=nil)
check("список обновляется событием без polling timer",tool:find("GRM_DutyToolFactionsUpdated",1,true)~=nil and tool:find("timer.Create",1,true)==nil)
check("3D2D показывает фракцию и ненастроенный статус",draw:find("GRMDutyNPC_Faction",1,true)~=nil and draw:find("НЕ НАСТРОЕН",1,true)~=nil)
print("[SIM] === "..(fails==0 and "ВСЕ ПРОВЕРКИ ПРОШЛИ" or ("ПРОВАЛОВ: "..fails)).." ===")
os.exit(fails==0 and 0 or 1)
