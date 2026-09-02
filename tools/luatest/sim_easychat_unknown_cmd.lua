--[[--------------------------------------------------------------------
    sim_easychat_unknown_cmd — неизвестные / и ! команды EasyChat
    обрабатываются локально и не уходят в глобальный чат.

    Проверяет:
      1. серверный PlayerSay: неизвестная /! команда гасится и уходит
         в concommand.Run, известная не трогается;
      2. серверный PlayerSayPostTransform: любой дошедший /! текст
         гасится;
      3. клиентский PlayerSayPostTransform (EasyChat): неизвестная
         команда гасится и выполняется через LocalPlayer():ConCommand,
         известные (RP-чат, студия, модули) пропускаются;
      4. реестр покрывает все команды, встречающиеся в hook.Add
         ("PlayerSay"/"PlayerSayTransform") файлах.

    Запуск: ./.luabuild/lj/src/luajit tools/luatest/sim_easychat_unknown_cmd.lua
----------------------------------------------------------------------]]
local stub = dofile("tools/luatest/lib_gmod_stub.lua")
stub.install()

local fails, total = 0, 0
local function ok(cond, name, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "  " .. tostring(extra or "")) end
end

-- РАЗДЕЛ 1: сервер (ванильный PlayerSay + EasyChat PostTransform)
print("=== 1. SERVER ===")
local server_calls = {}
_G.concommand.Run = function(ply, cmd, args, argstr)
    server_calls[#server_calls + 1] = { cmd = cmd, args = args, argstr = argstr }
    return true
end

local ply = { __valid = true, __entity = true, isPlayer = true }

local loaded, err = stub.loadModule("lua/autorun/zz_grm_easychat_cmds.lua")
ok(loaded, "модуль поднялся (server)", err)
local G = _G.GRM and _G.GRM.EasyChat
ok(G and type(G.CmdList) == "table" and #G.CmdList >= 500, "реестр заполнен: " .. tostring(G and #G.CmdList or 0))

-- «менеджерские» (ULib/ULX) команды: гасим чат, но НЕ дублируем исполнение
-- our concommand.Run рядом с ULib сложился бы вдвое (noclip вкл+выкл)
local res = hook.Run("PlayerSay", ply, "/noclip", false)
ok(res == "", "PlayerSay /noclip гасится (='')", tostring(res))
ok(#server_calls == 0, "noclip не дублируется concommand.Run", tostring(#server_calls))

local resU = hook.Run("PlayerSay", ply, "!ulx addowner", false)
ok(resU == "", "PlayerSay !ulx гасится", tostring(resU))
ok(#server_calls == 0, "ulx не дублируется")

local res2 = hook.Run("PlayerSay", ply, "!neznakomaya", false)
ok(res2 == "", "PlayerSay !neznakomaya гасится", tostring(res2))
ok(#server_calls == 1 and server_calls[1].cmd == "neznakomaya", "concommand.Run(neznakomaya): " .. tostring(server_calls[1] and server_calls[1].cmd))

-- известные команды не трогаем
local before = #server_calls
ok(hook.Run("PlayerSay", ply, "/me улыбается", false) == nil, "PlayerSay /me пропускается")
ok(hook.Run("PlayerSay", ply, "/studio", false) == nil, "PlayerSay /studio пропускается")
ok(hook.Run("PlayerSay", ply, "!mask", false) == nil, "PlayerSay !mask пропускается")
ok(hook.Run("PlayerSay", ply, "привет как дела", false) == nil, "обычное сообщение не трогается")
ok(#server_calls == before, "известные не вызвали concommand")

-- серверный PostTransform EasyChat: гасит любой дошедший /! текст
local dpsk = { "/me улыбается" }
hook.Run("PlayerSayPostTransform", ply, dpsk, false, false)
ok(dpsk[1] == "", "PostTransform гасит дошедший /me", tostring(dpsk[1]))
ok(dpsk.SkipPlayerSay == true, "PostTransform ставит SkipPlayerSay")

local dpn = { "!что_то_там" }
hook.Run("PlayerSayPostTransform", ply, dpn, false, false)
ok(dpn[1] == "", "PostTransform гасит !что_то_там", tostring(dpn[1]))
ok(#server_calls == before + 2, "PostTransform дважды выполнил локально: " .. #server_calls)

-- менеджерская в PostTransform: гасится, но исполнение — за ULib-цепочкой
local dpm = { "!noclip" }
hook.Run("PlayerSayPostTransform", ply, dpm, false, false)
ok(dpm[1] == "" and dpm.SkipPlayerSay == true, "PostTransform гасит !noclip")
ok(#server_calls == before + 2, "PostTransform не дублирует noclip: " .. #server_calls)

-- РАЗДЕЛ 2: клиент (EasyChat SendGlobalMessage)
print("=== 2. CLIENT ===")
_G.SERVER, _G.CLIENT = false, true
stub.hooks = {}
local client_calls = {}
-- на клиенте «свои» команды движка — только они и исполняются локально
local CLIENT_CMDS = { mat_wireframe = true, rcon = true, quit = true }
_G.ConCommandExists = function(n) return CLIENT_CMDS[tostring(n or "")] == true end
local lp = {
    __valid = true,
    __entity = true,
    isPlayer = true,
    ConCommand = function(self, cmd)
        client_calls[#client_calls + 1] = cmd
    end,
}
_G.LocalPlayer = function() return lp end

local loa2, err2 = stub.loadModule("lua/autorun/zz_grm_easychat_cmds.lua")
ok(loa2, "модуль поднялся (client)", err2)

local function post(dp)
    hook.Run("PlayerSayPostTransform", lp, dp, false, false)
    return dp
end

-- noclip — менеджерская: НЕ гасим и НЕ исполняем локально,
-- пусть уходит на сервер как say (ULib исполнит со своими правами)
local dp1 = { "!noclip" }
post(dp1)
ok(dp1[1] == "!noclip", "client !noclip пропущен на сервер", tostring(dp1[1]))
ok(dp1.SkipPlayerSay == nil, "client noclip не помечен скипом")
ok(#client_calls == 0, "noclip не выполнялся локально", tostring(client_calls[1]))

local dp2 = { "/noclip x" }
post(dp2)
ok(dp2[1] == "/noclip x", "client /noclip x пропущен", tostring(dp2[1]))
ok(#client_calls == 0, "по-прежнему без локального запуска")

-- чистая клиентская команда — гасим и выполняем локально (как раньше)
local dp3 = { "!mat_wireframe 1" }
post(dp3)
ok(dp3[1] == "" and dp3.SkipPlayerSay == true, "клиент гасит mat_wireframe")
ok(client_calls[1] == "mat_wireframe 1", "ConCommand('mat_wireframe 1'): " .. tostring(client_calls[1]))

-- неизвестное и не клиентское — пропускаем: серверный PostTransform
-- исполнит своей concommand и в чат не пустит
local dp4 = { "!servernaya_komanda 42" }
post(dp4)
ok(dp4[1] == "!servernaya_komanda 42", "неклиентская команда уходит на сервер", tostring(dp4[1]))
ok(#client_calls == 1, "без ложного локального запуска")

-- известные команды пропускаются (уходят на сервер / модулям)
local beforeC = #client_calls
local kp = { "/studio" }
post(kp)
ok(kp[1] == "/studio", "клиент /studio пропускает (серверная)", tostring(kp[1]))
local kp2 = { "/me делает" }
post(kp2)
ok(kp2[1] == "/me делает", "клиент /me пропускает (RP-чат)", tostring(kp2[1]))
local kp3 = { "//hello" }
post(kp3)
ok(kp3[1] == "//hello", "клиент // пропускает (LOOC)", tostring(kp3[1]))
local kp4 = { "!mask" }
post(kp4)
ok(kp4[1] == "!mask", "клиент !mask пропускает", tostring(kp4[1]))
local kp5 = { "привет мир" }
post(kp5)
ok(kp5[1] == "привет мир", "обычное сообщение не тронуто")
ok(#client_calls == beforeC, "известные не выполнялись локально")

-- РАЗДЕЛ 3: покрытие реестра
print("=== 3. REGISTRY COVERAGE ===")
local function readAll(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a") f:close()
    return s
end
local function normName(lit)
    -- литерал обязан начинаться с ^?[/!] (иначе это путь/звук/описание)
    local name = string.match(lit, "^%^?[/!]([^%s\"'.,%)]+)")
    if not name or name == "" then return nil end
    if name:find("[*%(%)%%%[%]]") then return nil end
    if name:find("^%d+$") and #name < 3 then return nil end -- "/5" из HUD-строк
    if name:sub(-1) == "_" then return nil end -- фрагменты путей: /root_, /fleet_
    if name == "access" then return nil end -- вкладка, не команда
    if name == "" then return nil end
    return name:lower()
end
local function collectCmds(path)
    local src = readAll(path)
    if not src:find("hook.Add", 1, true) or not src:find("PlayerSay", 1, true) then return {} end
    local found = {}
    for ln in src:gmatch("[^\n]+") do
        if ln:find("==") or ln:find("~=") or ln:find("find%(") or ln:find("match%(")
            or ln:find("] =") or ln:find("handlers%[") or ln:find("resolveCmd%(") then
            for lit in ln:gmatch('["\']([^"\'\n]*[/!][^"\'\n]*)["\']') do
                local name = normName(lit)
                if name and name ~= "" then found[name] = true end
            end
        end
    end
    return found
end

local missing, totalCmds = {}, 0
local scanned = 0
local function scanDir(dir)
    local cmd_list = {}
    local function walk(d)
        local base = d .. "/"
        local f = io.popen("find " .. base .. " -name '*.lua' 2>/dev/null")
        if not f then return end
        for path in f:lines() do
            path = path:gsub("^%s+", ""):gsub("%s+$", "")
            if path ~= "" and not path:find("easychat", 1, true) then
                scanned = scanned + 1
                for name in pairs(collectCmds(path)) do cmd_list[name] = true end
            end
        end
        f:close()
    end
    walk(dir)
    return cmd_list
end

local all = {}
local found1 = scanDir("lua/autorun")
local found2 = scanDir("addons")
for k in pairs(found1) do all[k] = true end
for k in pairs(found2) do all[k] = true end
for name in pairs(all) do
    totalCmds = totalCmds + 1
    if not G.IsKnownCmd(name) then missing[#missing + 1] = name end
end
ok(#missing == 0, "реестр покрывает все команды (" .. totalCmds .. " найдено)", table.concat(missing, ", "))
ok(scanned > 100, "просканировано файлов: " .. scanned)

print(string.format("\n===== sim_easychat_unknown_cmd: %d/%d =====", total - fails, total))
if fails > 0 then os.exit(1) end
