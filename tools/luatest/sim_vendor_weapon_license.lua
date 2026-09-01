-- Оружейный торговец: реальные категории лицензии.
function istable(v)return type(v)=="table"end function isstring(v)return type(v)=="string"end function isfunction(v)return type(v)=="function"end function IsValid(v)return type(v)=="table"end
math.Clamp=function(v,a,b)if v<a then return a elseif v>b then return b end return v end
SERVER=false CLIENT=false
local allowed={}
local ply={_key="100:char1",_police=false,IsSuperAdmin=function()return false end,SteamID64=function()return"100"end}
GRM={Identity={CharacterKey=function(p)return p._key end,FactionMember=function(_,p)return p._police and{}or nil end},Documents={HasValidWeaponLicense=function(_,cat)return allowed[cat]==true,allowed[cat]and"Действительна"or"нет категории"end}}
Factions={OrdnungPolizei={Members={}}}
dofile("lua/autorun/sh_grm_vendor.lua")
local V=GRM.Vendor; local fail=0
local function ok(c,n)if c then print("  ok  "..n)else fail=fail+1 print("  FAIL "..n)end end
local function item(id)local t={}for k,v in pairs(V.Catalogs.weapon[id])do t[k]=v end;t.isWeapon=true;return t end
local ak=item("arccw_ak47");local pistol=item("arccw_p228");local shotgun=item("arccw_shotgun")
ok(ak.weaponCategory=="rifled" and pistol.weaponCategory=="short" and shotgun.weaponCategory=="smooth","категории каталога")
ok(V.CanBuyWeapon(ply,ak)==false,"без лицензии автомат запрещён")
allowed.rifled=true;ok(V.CanBuyWeapon(ply,ak)==true,"нарезная лицензия разрешает автомат")
ok(V.CanBuyWeapon(ply,pistol)==false,"нарезная не разрешает пистолет")
allowed.short=true;ok(V.CanBuyWeapon(ply,pistol)==true,"короткоствольная разрешает пистолет")
ok(V.CanBuyWeapon(ply,shotgun)==false,"без гладкоствольной дробовик запрещён")
allowed.smooth=true;ok(V.CanBuyWeapon(ply,shotgun)==true,"гладкоствольная разрешает дробовик")
local baton=item("arrest_stick");ply._police=true;ok(V.CanBuyWeapon(ply,baton)==true,"полиция получает служебный товар")
ply._police=false;ok(V.CanBuyWeapon(ply,baton)==false,"гражданин не получает служебный товар")
print(("VENDOR WEAPON LICENSE: 9 checks, failures=%d"):format(fail));os.exit(fail==0 and 0 or 1)
