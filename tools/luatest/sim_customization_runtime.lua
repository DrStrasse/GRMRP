-- Runtime simulation of GRM Closed Customization server API.
SERVER, CLIENT = true, false
function AddCSLuaFile() end
function istable(v) return type(v)=="table" end
function isstring(v) return type(v)=="string" end
function isfunction(v) return type(v)=="function" end
function IsValid(v) return type(v)=="table" and not v.removed end
string.Trim = string.Trim or function(s) return tostring(s):match("^%s*(.-)%s*$") end
math.Clamp = math.Clamp or function(v,a,b) return math.max(a,math.min(b,v)) end
math.NormalizeAngle = math.NormalizeAngle or function(a) a=a%360; if a>180 then a=a-360 end; return a end
table.Count = table.Count or function(t) local n=0 for _ in pairs(t or {}) do n=n+1 end return n end
local function copy(v) if type(v)~="table" then return v end local o={} for k,x in pairs(v) do o[k]=copy(x) end return o end
table.Copy = table.Copy or copy

local FILES, JSON = {}, {}
util = {
 AddNetworkString=function() end,
 IsValidModel=function(m) return type(m)=="string" and m:match("^models/.+%.mdl$")~=nil end,
 TableToJSON=function(t) JSON[#JSON+1]=copy(t); return "#J"..#JSON end,
 JSONToTable=function(s) local i=tonumber(tostring(s):match("#J(%d+)")); return i and copy(JSON[i]) or nil end,
}
file = {
 IsDir=function() return true end, CreateDir=function() end,
 Exists=function(p) return FILES[p]~=nil end,
 Read=function(p) return FILES[p] end,
 Write=function(p,s) FILES[p]=s end,
}
local hooks, timers, receivers, commands = {}, {}, {}, {}
hook={Add=function(n,id,fn) hooks[n]=hooks[n] or {}; hooks[n][id]=fn end, Run=function() end}
timer={Create=function(n,_,_,fn) timers[n]=fn end, Simple=function(_,fn) fn() end}
concommand={Add=function(n,fn) commands[n]=fn end}
local readStrings, readTables, readUInts = {}, {}, {}
net={
 Receive=function(n,fn) receivers[n]=fn end, Start=function(n) net.current=n end,
 WriteTable=function() end, WriteEntity=function() end, WriteString=function() end, WriteBool=function() end,
 Send=function() end, Broadcast=function() end,
 ReadString=function() return table.remove(readStrings,1) end,
 ReadTable=function() return table.remove(readTables,1) end,
 ReadUInt=function() return table.remove(readUInts,1) or 0 end,
}
local now=100
function CurTime() return now end

local inventoryDefs, useHandlers = {}, {}
local inv={slots={}}
GRM={
 Notify=function() end,
 GiveMoney=function() end,
 Identity={CharacterKey=function(p) return p.key end},
 Inventory={
  RegisterItem=function(id,d) inventoryDefs[id]=d end,
  RegisterUseHandler=function(id,fn) useHandlers[id]=fn end,
  GetPlayerInv=function() return inv end,
  RemoveFromSlot=function(_,idx,count) local s=inv.slots[idx]; if not s then return false end; s.count=(s.count or 1)-(count or 1); if s.count<=0 then inv.slots[idx]=nil end; return true end,
  AddItem=function(_,id,count) for i=1,24 do if not inv.slots[i] then inv.slots[i]={id=id,count=count or 1}; return 0 end end return count or 1 end,
 },
 Vendor={Catalogs={},Models={},RegisterItem=function(kind,id,d) GRM.Vendor.Catalogs[kind]=GRM.Vendor.Catalogs[kind] or {}; GRM.Vendor.Catalogs[kind][id]=d end},
}
local ply={key="76561198000000001:char1",nw={},super=true,alive=true}
function ply:IsSuperAdmin() return self.super end
function ply:SteamID64() return "76561198000000001" end
function ply:GetNWBool(k,d) local v=self.nw[k]; if v==nil then return d end return v end
function ply:SetNWBool(k,v) self.nw[k]=v end
function ply:GetNWInt(k,d) local v=self.nw[k]; if v==nil then return d or 0 end return v end
function ply:SetNWInt(k,v) self.nw[k]=v end
function ply:Alive() return self.alive end
player={GetAll=function() return {ply} end}

dofile("lua/autorun/sh_grm_customization.lua")
local C=GRM.Customization
local checks,failed=0,0
local function ok(v,label) checks=checks+1; if v then print("  ok "..checks..". "..label) else failed=failed+1; print("  FAIL "..checks..". "..label) end end
ok(type(C)=="table" and C.Version=="1.0.0","module loaded")
ok(type(receivers.GRM_Custom_AdminOp)=="function","admin receiver registered")

readStrings={"save","cap"}
readTables={{name="Police Cap",category="Головные уборы",model="models/props_junk/TrafficCone001a.mdl",description="cap",price=1500,slot="head",bone="ValveBiped.Bip01_Head1",position={x=999,y=2,z=3},angles={p=0,y=400,r=0},scale=9,functions={gasmask=true,backpack=true,radio=true,watch=true,armor=true},functionConfig={gasProtection=5,backpackCapacity=999,armorReduction=4}}}
receivers.GRM_Custom_AdminOp(0,ply)
local item=C.Catalog.cap
ok(item and item.itemID=="grm_acc_cap","admin item entered authoritative catalog")
ok(item.position.x==48 and item.angles.y==40 and item.scale==3,"admin defaults clamped")
ok(item.functions.gasmask and item.functions.backpack and item.functions.radio and item.functions.watch and item.functions.armor,"admin function checkboxes persisted")
ok(item.functionConfig.gasProtection==0.98 and item.functionConfig.backpackCapacity==100 and item.functionConfig.armorReduction==0.75,"functional values clamped")
ok(inventoryDefs.grm_acc_cap and inventoryDefs.grm_acc_cap.useFunc=="grm_accessory_equip","inventory definition registered")
ok(GRM.Vendor.Catalogs.accessory.grm_acc_cap and GRM.Vendor.Catalogs.accessory.grm_acc_cap.price==1500,"accessory vendor catalog registered")

inv.slots[1]={id="grm_acc_cap",count=1}
now=101
readStrings={"equip_inventory","head"}; readUInts={1}
receivers.GRM_Custom_Op(0,ply)
local loadout=C.GetLoadout(ply)
ok(inv.slots[1]==nil and loadout.head and loadout.head.accessoryID=="cap","using inventory item equips it")
ok(C.HasFunction(ply,"gasmask") and C.HasFunction(ply,"radio") and C.GetFunctionValue(ply,"backpack","backpackCapacity","sum")==100,"functional API reads equipped catalog flags")
ok(FILES[C.LoadoutsFile]~=nil,"loadout persisted by CharacterKey")



ply.nw.GRM_CustomEditing=true
now=102
readStrings={"save_all_close"}
readTables={{head={accessoryID="cap",bone="ValveBiped.Bip01_Head1",position={x=-500,y=8,z=9},angles={p=720,y=0,r=0},scale=0.01}}}
receivers.GRM_Custom_Op(0,ply)
loadout=C.GetLoadout(ply)
ok(loadout.head.position.x==-48 and loadout.head.scale==0.2,"malicious editor transform clamped")
ok(ply:GetNWBool("GRM_CustomEditing",true)==false,"save closes and unfreezes editor")
local storedSchema=util.JSONToTable(FILES[C.LoadoutsFile])
ok(storedSchema and storedSchema.version==2 and type(storedSchema.records)=="table","versioned array persistence written")
C.LoadData();loadout=C.GetLoadout(ply)
ok(loadout.head and loadout.head.position.x==-48 and loadout.head.scale==0.2,"transform survives simulated server restart/reload")

ply.nw.GRM_CustomEditing=false
now=103
readStrings={"unequip_inventory","head"}; readTables={}
receivers.GRM_Custom_Op(0,ply)
loadout=C.GetLoadout(ply)
ok(loadout.head==nil,"inventory context action clears equipment slot without editor")
local returned=false for _,s in pairs(inv.slots) do if s.id=="grm_acc_cap" then returned=true end end
ok(returned,"inventory context action returns real item")

-- Equip again, then verify the original editor action remains compatible.
local equipIndex, equipSlot
for idx,s in pairs(inv.slots) do if s.id=="grm_acc_cap" then equipIndex, equipSlot=idx,s break end end
if equipIndex then useHandlers.grm_accessory_equip(ply,equipIndex,equipSlot,inventoryDefs.grm_acc_cap) end
ok(C.GetLoadout(ply).head.position.x==-48 and C.GetLoadout(ply).head.scale==0.2,"inventory unequip/re-equip restores per-accessory transform profile")
ply.nw.GRM_CustomEditing=true
now=104
readStrings={"unequip","head"}; readTables={}
receivers.GRM_Custom_Op(0,ply)
ok(C.GetLoadout(ply).head==nil,"editor unequip remains compatible")

-- Equip again and remove through chat command.
equipIndex,equipSlot=nil,nil
for idx,s in pairs(inv.slots) do if s.id=="grm_acc_cap" then equipIndex,equipSlot=idx,s break end end
if equipIndex then useHandlers.grm_accessory_equip(ply,equipIndex,equipSlot,inventoryDefs.grm_acc_cap) end
local pack={"/acc_remove head"}
hooks.PlayerSayTransform.GRM_Customization_RemoveCommand(ply,pack)
ok(next((C.GetLoadout(ply)))==nil and pack[1]=="","/acc_remove head returns accessory and consumes command")

-- Equip once more, then confiscate as arrest would.
equipIndex,equipSlot=nil,nil
for idx,s in pairs(inv.slots) do if s.id=="grm_acc_cap" then equipIndex,equipSlot=idx,s break end end
if equipIndex then useHandlers.grm_accessory_equip(ply,equipIndex,equipSlot,inventoryDefs.grm_acc_cap) end
ok(C.Confiscate(ply)==1 and next((C.GetLoadout(ply)))==nil,"arrest confiscation destroys worn accessory")


-- ══ СУМКА ОГРАБЛЕНИЯ (находка 178f) — в конце, чтобы не ломать rateOK-очередь ══
now = 300
ok(C.FunctionTypes.loot_bag ~= nil, "loot_bag: тип функции зарегистрирован")
readStrings={"save","bag"}
readTables={{name="Сумка",category="Снаряжение",model="models/props_junk/duffelbag.mdl",description="сумка",price=3000,slot="torso",bone="ValveBiped.Bip01_Spine2",position={x=0,y=0,z=0},angles={p=0,y=0,r=0},scale=1,functions={loot_bag=true},functionConfig={lootMaxMoney=100000,lootPerUse=25000}}}
receivers.GRM_Custom_AdminOp(0,ply)
local bagItem=C.Catalog.bag
ok(bagItem and bagItem.functionConfig.lootMaxMoney==100000 and bagItem.functionConfig.lootPerUse==25000, "loot_bag: конфиг сумки сохранён в каталоге")
inv.slots[1]={id="grm_acc_bag",count=1}
now=301
readStrings={"equip_inventory","torso"}; readUInts={1}
receivers.GRM_Custom_Op(0,ply)
ok(C.HasFunction(ply,"loot_bag"), "loot_bag: сумка надета")
local t1=C.LootBagAdd(ply,300000)
ok(t1==25000 and C.LootBagGet(ply)==25000, "loot_bag: 1-й заход = 25.000 (не все 300.000)")
local t2=C.LootBagAdd(ply,300000)
local t3=C.LootBagAdd(ply,300000)
ok(t2==25000 and t3==25000 and C.LootBagGet(ply)==75000, "loot_bag: 3 захода = 75.000")
local t4=C.LootBagAdd(ply,300000)
ok(t4==25000 and C.LootBagGet(ply)==100000, "loot_bag: 4-й заход = 100.000 (максимум)")
local t5=C.LootBagAdd(ply,300000)
ok(t5==0 and C.LootBagGet(ply)==100000, "loot_bag: сумка полна — 5-й заход 0")
local unloaded,err=C.LootBagUnload(ply)
ok(unloaded==100000 and C.LootBagGet(ply)==0, "loot_bag: /bag_unload выгрузил 100.000 в кошелёк")
C.UnequipSlot(ply,"torso",true,true)
ok(C.LootBagAdd(ply,50000)==0, "loot_bag: без надетой сумки сбор 0")

-- ══ ФОНАРИК + ЗАПОМИНАНИЕ (находка 179z) ══
now = 400
local afHook = hooks.AllowFlashlight and hooks.AllowFlashlight.GRM_Customization_NoFlashlight
ok(type(afHook) == "function" and afHook() == false, "фонарик: AllowFlashlight запрещён глобально (находка 179z)")
-- аксессуар с функцией night_vision (OnEquip ставит NWBool-флаг)
readStrings={"save","nv"}; readUInts={}
readTables={{name="Ночное зрение",category="Глаза",model="models/props_combine/combine_faceplate.mdl",description="НВ",price=9000,slot="face",bone="ValveBiped.Bip01_Head1",position={x=0,y=0,z=0},angles={p=0,y=0,r=0},scale=1,functions={night_vision=true},functionConfig={}}}
receivers.GRM_Custom_AdminOp(0,ply)
local nvItem = C.Catalog.nv
ok(nvItem ~= nil and nvItem.functions.night_vision == true, "запоминание: аксессуар НВ добавлен в каталог")
inv.slots[1]={id="grm_acc_nv",count=1}
now=401
readStrings={"equip_inventory","face"}; readUInts={1}
receivers.GRM_Custom_Op(0,ply)
ok(ply:GetNWBool("GRM_Accessory_night_vision", false) == true, "запоминание: OnEquip выставил флаг при надевании")
-- эмуляция рестарта сервера: NWBool сброшен, лоадаут остался на диске
ply.nw.GRM_Accessory_night_vision = nil
ok(ply:GetNWBool("GRM_Accessory_night_vision", false) == false, "запоминание: после «рестарта» флаг сброшен")
ok(hooks.PlayerInitialSpawn ~= nil and hooks.PlayerInitialSpawn.GRM_Customization_Join ~= nil, "запоминание: хук входа зарегистрирован")
hooks.PlayerInitialSpawn.GRM_Customization_Join(ply)
ok(ply:GetNWBool("GRM_Accessory_night_vision", false) == true, "запоминание: вход восстанавливает OnEquip надетых аксессуаров (находка 179z)")

print(("CUSTOMIZATION RUNTIME: %d/%d, failures=%d"):format(checks-failed,checks,failed))
if failed>0 then os.exit(1) end
