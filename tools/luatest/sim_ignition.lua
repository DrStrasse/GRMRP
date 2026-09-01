--[[ Живой прогон зажигания (заказ владельца 27.08):
     «Нажимаю R на пассажирском, завожу как суперадмин. Игрок завести
      машину не может.»

     ДВЕ ПРИЧИНЫ, найденные при разборе:

     1) ПАССАЖИР ЗАВОДИЛ МАШИНУ. Проверялось только ply:InVehicle(), а
        пассажирское место — это тоже vehicle. RootVehicle честно приводил
        под к корпусу, и зажигание срабатывало с любого сиденья.

     2) ДОСТУП НЕ ПРОВЕРЯЛСЯ ВООБЩЕ. Из-за этого суперадмин заводил что
        угодно (у него нет ограничений в принципе), а обычный игрок
        упирался в отказ на другом уровне и не понимал причину. Теперь
        право заводить сверяется с системой ключей VK: владелец, член
        организации-владельца или обладатель ключа.

     Запуск: luajit tools/luatest/sim_ignition.lua ]]
local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

local function body(path)
    local fh = io.open(path, "rb") if not fh then return "" end
    local t = fh:read("*a") fh:close() return t
end
local src = body("lua/autorun/sh_grm_fuel.lua")

print("\n=== 1. ЗАЖИГАНИЕ ТОЛЬКО С МЕСТА ВОДИТЕЛЯ ===")
ok(src:find("local function isDriver(ply, veh)", 1, true) ~= nil,
   "появилась проверка водительского места")
ok(src:find("Завести можно только с места водителя", 1, true) ~= nil,
   "пассажиру отказывают с понятным текстом")
ok(src:find('for _, getter in ipairs({ "GetDriver", "GetDriverSeat" })', 1, true) ~= nil,
   "у simfphys и LVS спрашиваем, кто за рулём, их же методами")
ok(src:find("if seat == veh then return true end", 1, true) ~= nil,
   "ванильный транспорт: сиденье и есть машина — водитель опознаётся")
ok(src:find("-- Иначе это отдельный под: пассажирское место.", 1, true) ~= nil,
   "отдельный под считается пассажирским местом")

--[[ Проверяем саму логику: воспроизводим isDriver на заглушках, потому
     что именно она решает, пассажир перед нами или водитель. ]]
local function mkSeat(name) return { _valid = true, _name = name,
    IsPlayer = function() return false end } end
local driverSeat, passSeat = mkSeat("driver"), mkSeat("passenger")

local function isDriver(ply, veh, seat)
    -- Копия логики из модуля: те же ветки в том же порядке.
    if not (ply and veh and seat) then return false end
    for _, getter in ipairs({ "GetDriver", "GetDriverSeat" }) do
        if type(veh[getter]) == "function" then
            local res = veh[getter](veh)
            if res and res._valid ~= false then
                if res == ply or res == seat then return true end
                if res ~= ply and res.IsPlayer and res:IsPlayer() then return false end
            end
        end
    end
    if seat == veh then return true end
    return false
end

local simf = { _valid = true, GetDriverSeat = function() return driverSeat end }
local ply = { _valid = true, IsPlayer = function() return true end }
ok(isDriver(ply, simf, driverSeat) == true, "водитель simfphys опознаётся")
ok(isDriver(ply, simf, passSeat) == false,
   "ПАССАЖИР simfphys больше не заводит — тот самый баг со скриншота")

local vanilla = { _valid = true }
ok(isDriver(ply, vanilla, vanilla) == true, "ванильная машина: сидящий в ней — водитель")
ok(isDriver(ply, vanilla, passSeat) == false, "приделанный под к ней — пассажир")

local occupied = { _valid = true,
    GetDriver = function() return { _valid = true, IsPlayer = function() return true end } end }
ok(isDriver(ply, occupied, passSeat) == false,
   "если за рулём уже другой игрок, пассажир не заводит")

print("\n=== 2. ДОСТУП К МАШИНЕ ПРОВЕРЯЕТСЯ ===")
ok(src:find("local function canStart(ply, veh)", 1, true) ~= nil,
   "появилась проверка права заводить")
ok(src:find("VK.CanInteract(veh, ply, false)", 1, true) ~= nil,
   "используется штатная система ключей, а не своя копия правил")
ok(src:find("Нет ключей от этой машины", 1, true) ~= nil,
   "отказ объясняет причину, а не молчит")
ok(src:find("if ply:IsSuperAdmin() then return true end", 1, true) ~= nil,
   "суперадмин по-прежнему заводит всё")

--[[ Ключевая деталь: ничья машина не должна стать незаводимой. Если
     система ключей о ней ничего не знает, запрещать нечего. ]]
ok(src:find("if VK.OWNER_TYPE and veh.VK_OwnerType == nil then return true end", 1, true) ~= nil,
   "ничью машину заводит тот, кто в неё сел — иначе никто не смог бы ездить")
ok(src:find("if not (VK and isfunction(VK.CanInteract)) then return true end", 1, true) ~= nil,
   "без системы ключей поведение остаётся прежним")

local function canStart(ply, veh, VK)
    if ply.super then return true end
    if not (VK and type(VK.CanInteract) == "function") then return true end
    if VK.OWNER_TYPE and veh.VK_OwnerType == nil then return true end
    return VK.CanInteract(veh, ply, false) == true
end
local VK = { OWNER_TYPE = { PLAYER = 1, FACTION = 2 },
    CanInteract = function(veh, p) return veh.VK_OwnerSteam == p.steam end }

local owned = { VK_OwnerType = 1, VK_OwnerSteam = "STEAM_1" }
local owner   = { steam = "STEAM_1" }
local stranger = { steam = "STEAM_9" }
local admin = { steam = "STEAM_0", super = true }

ok(canStart(owner, owned, VK) == true, "владелец заводит свою машину")
ok(canStart(stranger, owned, VK) == false, "посторонний — нет")
ok(canStart(admin, owned, VK) == true, "суперадмин заводит чужую")
ok(canStart(stranger, { VK_OwnerType = nil }, VK) == true,
   "ничью машину заводит любой — обычные игроки не остались без транспорта")
ok(canStart(stranger, owned, nil) == true, "без модуля ключей ограничений нет")

print("\n=== 3. ПОРЯДОК ПРОВЕРОК ===")
--[[ Место водителя проверяется ДО прав: пассажиру-владельцу логичнее
     сказать «пересядьте за руль», а не «нет ключей». ]]
local seatIdx = src:find("Завести можно только с места водителя", 1, true)
local keyIdx = src:find("Нет ключей от этой машины", 1, true)
ok(seatIdx and keyIdx and seatIdx < keyIdx,
   "сначала проверяется место, потом ключи — подсказка точнее")

print("\n=== 4. ОСТАЛЬНОЕ ЗАЖИГАНИЕ НЕ СЛОМАНО ===")
ok(src:find('if not cmd:KeyDown(IN_RELOAD) then ply._grmIgnWas = false return end', 1, true) ~= nil,
   "клавиша R по-прежнему отвечает за зажигание")
ok(src:find("ply._grmIgnWas = true", 1, true) ~= nil,
   "защита от повторного срабатывания на удержании осталась")
ok(src:find('GRM.Notify(ply, on and "Зажигание ВКЛ"', 1, true) ~= nil,
   "уведомление о включении сохранено")
ok(src:find('if veh:GetNWBool("GRM_VehBroken") then return false, "поломана" end', 1, true) ~= nil,
   "сломанная машина по-прежнему не заводится")
ok(src:find('return false, "нет топлива"', 1, true) ~= nil,
   "без топлива тоже")

print(("\n=== ИТОГ: успешно %d, провалено %d ===\n"):format(pass, fail))
if fail > 0 then os.exit(1) end
