-- World entity labels must follow the render camera, never LocalPlayer body yaw.
local bad={};local checked=0
local function scan(path)
 local f=io.open(path,"rb");if not f then return end;local s=f:read("*a");f:close();if not s:find("cam.Start3D2D",1,true)then return end;checked=checked+1
 if s:find("LocalPlayer():EyeAngles()",1,true)or s:find("lp:EyeAngles().y - 90",1,true)or s:find("ply:EyeAngles().y - 90",1,true)then bad[#bad+1]=path end
end
local p=io.popen("find lua/entities -name cl_init.lua -type f");for path in p:lines()do scan(path)end;p:close()
for _,path in ipairs({"lua/autorun/client/cl_grm_vending_gui.lua","lua/autorun/sh_grm_arrest.lua","lua/autorun/sh_grm_jobs.lua","lua/autorun/sh_grm_radionet.lua","lua/autorun/sh_grm_trunk.lua"})do scan(path)end
print("WORLD LABELS checked="..checked.." bad="..#bad);for _,x in ipairs(bad)do print("  FAIL "..x)end;if #bad>0 then os.exit(1)end
local examples={"lua/entities/grm_bank_terminal/cl_init.lua","lua/entities/grm_vendor/cl_init.lua","lua/entities/grm_radio/cl_init.lua"};for _,path in ipairs(examples)do local f=assert(io.open(path));local s=f:read("*a");f:close();assert(s:find("EyeAngles()",1,true)or not s:find("cam.Start3D2D",1,true))end
print("WORLD LABEL CAMERA CONTRACT: OK")
