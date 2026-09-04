-- Regression contract: admin hub buttons never use say.
local f=assert(io.open("lua/autorun/sh_grm_admin_hub.lua","rb"));local s=f:read("*a");f:close()
local checks,failed=0,0;local function has(n)return s:find(n,1,true)~=nil end;local function ok(v,n)checks=checks+1;if v then print("  ok "..checks..". "..n)else failed=failed+1;print("  FAIL "..checks..". "..n)end end
ok(has('local NET_LAUNCH = "GRM_HUB_Launch"'),"dedicated launch protocol")
ok(has("LAUNCH_WHITELIST"),"server-side launch whitelist")
ok(has('net.Receive(NET_LAUNCH'),"server handles launch")
ok(has('hook.Run("PlayerSay", ply, command, false, false)'),"server launches command via battle PlayerSay chain (веч.-18, EasyChat-слой вырезан)")
ok(has('if ret == false then'),"handler-отказ (false) виден клиенту; иных веток нет")
ok(has('hook.Run("GRMRPChat_ClientCommand", LocalPlayer(), command) == true'),"client-only admin commands run locally (цепочка библиотеки)")
ok(has("launchAdminCommand(cmd)"),"every clickable menu row uses dispatcher")
ok(not has('LocalPlayer():ConCommand("say " .. cmd)'),"admin hub never writes command into chat")
ok(has('NET_LAUNCH_RESULT'),"visible launch acknowledgement")
ok(has('["/grm_accessories_admin"] = true')and has('["/grm_arrest_admin"] = true')and has('["/grm_persistence"] = true')and has('["/wanted"] = true'),"important admin menus whitelisted")
ok(has('{ "Единая экономика", "/salary_admin"') and not has('{ "Экономика GRM", "!grmmenu"') and not has('{ "Зарплаты", "/salary_admin"'),"single economy shortcut opens authoritative salary/economy panel")
print(("ADMIN HUB LAUNCH: %d/%d failures=%d"):format(checks-failed,checks,failed));if failed>0 then os.exit(1)end
