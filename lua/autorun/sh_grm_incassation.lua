--[[--------------------------------------------------------------------
    GRM Incassation (Код 126 — «Инкассация») v2.2.2 — ПЕРСИСТЕНТНОСТЬ БАНКОМАТОВ

    Полный цикл работы по ТЗ:
      1. Игрок садится в служебную машину фракции, за рулём пишет /incass —
         старт рейса, машина помечается NW'ами, игроку присваивается инкасс-машина.
         Над машиной активируется 3D2D-индикатор с суммой в багажнике.
      2. НАПРАВЛЕНИЕ А (Сбор денег: Банкомат → Хранилище):
         • Подъехав к банкомату (grm_bank_terminal) — нажимает [G],
           банкомат переходит в режим «ИНКАССАЦИЯ» (3D2D индикатор, блокировка от гражданских).
         • В меню банкомата: «Забрать указанную сумму» / «Забрать ВСЁ» —
           деньги списываются из банкомата, выдаётся чемодан (weapon_grm_incass_bag).
         • Баланс банкомата ПЕРСИСТЕНТЕН: сохраняется в data/grm_atm_cash.json
           и переживает любые рестарты карты и сервера!
         • Подходит к инкасс-машине — [G] — «ЗАГРУЗИТЬ» (чемодан → багажник).
         • Подъехав к хранилищу банка (grm_bank_vault) — [G] на машину — «РАЗГРУЗИТЬ»
           (багажник → чемодан в руку; разгрузка доступна в любом месте).
         • Подходит к вольту — [G] — «ЗАГРУЗИТЬ в хранилище» (HeldCash += N).
      3. НАПРАВЛЕНИЕ Б (Развозка денег: Хранилище → Банкоматы):
         • У вольта (grm_bank_vault) — [G] — «ВЫГРУЗИТЬ из хранилища» (вольт → чемодан 50к).
         • Подходит к машине — [G] — «ЗАГРУЗИТЬ» (чемодан → багажник).
         • Развозит по городу к любым банкоматам.
         • У банкомата — [G] на машину — «РАЗГРУЗИТЬ» (чемодан в руке).
         • Подходит к банкомату — [G] — «ЗАГРУЗИТЬ в банкомат» (чемодан → банкомат).
         • Снимает блокировку банкомата кнопкой «Завершить обслуживание».
      4. Команда /incass_off (/incass_end, /инкасс_стоп, /инкасс_офф, /сдать) —
         завершение рейса, сброс меток ТС/игрока, автоматическое снятие блокировок.

    Зависимости:
      - Код 42 (sh_grm_currency.lua)   — GRM.Notify / GRM.Format
      - Код 43 (sh_grm_economy.lua)    — GRM.Economy.*, вольты, гос.бюджет
      - Factions (sh_factions.lua)     — фракции / роли / IncassoSettings
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Incass = GRM.Incass or {}
local I = GRM.Incass

I.Version    = "2.3.0"
I.Code       = 126
I.ModuleName = "incassation"

-- ── Сетевые строки ────────────────────────────────────────────────
local NET_NOTIFY        = "GRM_Incass_Notify"
local NET_TERM_MENU     = "GRM_Incass_TermMenu"
local NET_TERM_TAKE     = "GRM_Incass_TermTake"
local NET_TERM_LOAD     = "GRM_Incass_TermLoad"
local NET_TERM_UNLOCK   = "GRM_Incass_TermUnlock"
local NET_CAR_MENU      = "GRM_Incass_CarMenu"
local NET_CAR_LOAD      = "GRM_Incass_CarLoad"
local NET_CAR_UNLOAD    = "GRM_Incass_CarUnload"
local NET_VAULT_MENU        = "GRM_Incass_VaultMenu"
local NET_VAULT_LOAD        = "GRM_Incass_VaultLoad"
local NET_VAULT_UNLOAD      = "GRM_Incass_VaultUnload"
local NET_VAULT_DELIVER_RUN = "GRM_Incass_VaultDeliverRun"

if SERVER then
    for _, s in ipairs({
        NET_NOTIFY, NET_TERM_MENU, NET_TERM_TAKE,
        NET_TERM_LOAD, NET_TERM_UNLOCK,
        NET_CAR_MENU, NET_CAR_LOAD, NET_CAR_UNLOAD,
        NET_VAULT_MENU, NET_VAULT_LOAD, NET_VAULT_UNLOAD, NET_VAULT_DELIVER_RUN,
    }) do
        util.AddNetworkString(s)
    end
end

-- ── Конфигурация ─────────────────────────────────────────────────
I.Config = I.Config or {
    MaxCarryPerCar          = 250000, -- макс. наличных в багажнике машины (250 тыс. GRM)
    BagChunk                = 50000,  -- макс. номинал одного чемодана (50 тыс. GRM)
    TerminalDepositCut      = 0.05,   -- 5% от взносов игроков оседает в банкомате
    TerminalMinCollect      = 100,    -- минимум наличных для изъятия
    TerminalCollectCooldown = 120,    -- секунд кулдауна после изъятия
    TerminalRadius          = 220,    -- радиус взаимодействия с банкоматом
    CarInteractRadius       = 250,    -- радиус взаимодействия с машиной
    VaultRadius             = 140,    -- радиус взаимодействия с хранилищем (вплотную; раньше 320 × 1.5 = через стены)
    VaultRequireLineOfSight = true,   -- сдавать можно только когда хранилище видно, а не через соседнюю комнату
    RequireDriverSeat       = true,   -- старт рейса только за рулём (место водителя)
    LockTerminalOnCollect   = true,   -- блокировка банкомата от обычных игроков во время сбора
    NotifyPoliceRadius      = 1200,   -- радиус оповещения админов/полиции при старте
    CarClassCheck           = true,   -- проверка класса машины по фракционному списку
    BagWeaponClass          = "weapon_grm_incass_bag",
}
I.CFG = I.Config -- обратная совместимость

-- ── Состояние подсистемы ─────────────────────────────────────────
I.ActiveRuns          = I.ActiveRuns or {}
I.CarToRun            = I.CarToRun or {}
I.PlyToCar            = I.PlyToCar or {}
I.LockedTerminals     = I.LockedTerminals or {}
I.TerminalCash        = I.TerminalCash or {}
I.TerminalLastCollect = I.TerminalLastCollect or {}
I.NextRunID           = I.NextRunID or 1
I._carAliasCache      = {}

-- ── Вспомогательные утилиты ───────────────────────────────────────
local function isstring(v)   return type(v) == "string" end
local function istable(v)    return type(v) == "table" end
local function isfunction(v) return type(v) == "function" end
local function mRound(n)
    if math.Round then return math.Round(n) end
    return math.floor((tonumber(n) or 0) + 0.5)
end

local function isPly(p)
    return IsValid(p) and p:IsPlayer()
end

local function jsonT(txt)
    if not isstring(txt) or txt == "" then return nil end
    local ok, t = pcall(util.JSONToTable, txt, false, true)
    return (ok and istable(t)) and t or nil
end

local function notify(ply, msg, r, g, b)
    if not isPly(ply) then return end
    r = r or 220
    g = g or 220
    b = b or 220
    if CLIENT then
        chat.AddText(Color(r, g, b), "[ИНКАСС] " .. tostring(msg))
        notification.AddLegacy(tostring(msg), NOTIFY_GENERIC, 5)
        surface.PlaySound("buttons/lightswitch2.wav")
        return
    end
    if GRM.Notify then
        GRM.Notify(ply, msg, r, g, b)
        return
    end
    net.Start(NET_NOTIFY)
        net.WriteString(tostring(msg))
        net.WriteUInt(math.Clamp(r, 0, 255), 8)
        net.WriteUInt(math.Clamp(g, 0, 255), 8)
        net.WriteUInt(math.Clamp(b, 0, 255), 8)
    net.Send(ply)
end
I.Notify = notify

local function formatMoney(n)
    n = math.floor(tonumber(n) or 0)
    if GRM.Format then
        local ok, s = pcall(GRM.Format, n)
        if ok and isstring(s) then return s end
    end
    return tostring(n) .. " GRM"
end
I.FormatMoney = formatMoney

local function isCarEntity(ent)
    if not IsValid(ent) then return false end
    local cls = ent:GetClass() or ""
    if ent:IsVehicle() then return true end
    if string.StartWith(cls, "simfphys_") then return true end
    if string.StartWith(cls, "lvs_") then return true end
    if string.StartWith(cls, "glide_") then return true end
    if string.StartWith(cls, "gmod_sent_vehicle") then return true end
    if string.StartWith(cls, "prop_vehicle_") then return true end
    return false
end

local function getRootVehicle(ent)
    if not IsValid(ent) then return nil end
    local cur = ent
    local seen = {}
    for _ = 1, 8 do
        if not IsValid(cur) then break end
        seen[cur] = true
        if not isfunction(cur.GetParent) then break end
        local okP, p = pcall(cur.GetParent, cur)
        if okP and IsValid(p) and not p:IsPlayer() and not p:IsWorld() and isCarEntity(p) and not seen[p] then
            cur = p
        else
            break
        end
    end
    return cur
end

local function getDriverOf(veh)
    if not IsValid(veh) then return nil end
    local ok, d = pcall(function() return veh:GetDriver() end)
    if ok and IsValid(d) and d:IsPlayer() then return d end
    if isfunction(veh.GetDriverSeat) then
        local okS, s = pcall(veh.GetDriverSeat, veh)
        if okS and IsValid(s) then
            local okD, sd = pcall(s.GetDriver, s)
            if okD and IsValid(sd) and sd:IsPlayer() then return sd end
        end
    end
    if istable(veh:GetChildren()) then
        for _, child in ipairs(veh:GetChildren()) do
            if IsValid(child) and child:IsVehicle() then
                local okC, cd = pcall(child.GetDriver, child)
                if okC and IsValid(cd) and cd:IsPlayer() then return cd end
            end
        end
    end
    return nil
end

local function getVehicleSpawnName(veh)
    if not IsValid(veh) then return nil end
    if isstring(veh.GRM_IncassSpawnName) and veh.GRM_IncassSpawnName ~= "" then
        return veh.GRM_IncassSpawnName
    end
    for _, fn in ipairs({
        "GetSpawn_List", "GetSpawnList", "GetSpawningName",
        "GetVehicleListName", "GetVehicleName",
        "GetLVSVehicleName", "GetVehicleClass",
    }) do
        if isfunction(veh[fn]) then
            local ok, v = pcall(veh[fn], veh)
            if ok and isstring(v) and v ~= "" then return v end
        end
    end
    for _, k in ipairs({
        "SpawnList", "Spawn_List", "SpawnName", "VehicleName",
        "List_ID", "ListName", "LVSVehicleName", "VehicleClassName",
    }) do
        if isstring(veh[k]) and veh[k] ~= "" then return veh[k] end
    end
    if isfunction(veh.GetKeyValues) then
        local ok, kv = pcall(veh.GetKeyValues, veh)
        if ok and istable(kv) then
            for _, k in ipairs({ "vehiclescript", "vehicletype" }) do
                if isstring(kv[k]) and kv[k] ~= "" then return kv[k] end
            end
        end
    end
    if list and isfunction(list.Get) then
        local lists = {
            list.Get("simfphys_vehicles") or {},
            list.Get("Vehicles") or {},
            list.Get("LVS_Vehicles") or {},
        }
        local okM, myMdl = pcall(veh.GetModel, veh)
        local vehModel = (okM and isstring(myMdl)) and string.lower(myMdl) or nil
        for _, lst in pairs(lists) do
            for key, info in pairs(lst) do
                if isstring(key) and vehModel and istable(info) and isstring(info.Model)
                   and string.lower(info.Model) == vehModel then
                    return key
                end
            end
        end
    end
    return veh:GetClass()
end

-- ── Проверка доступа игрока к инкассации ─────────────────────────
function I.GetPlayerIncassoInfo(ply)
    if not isPly(ply) then return nil, nil, nil, nil end
    if not Factions then return nil, nil, nil, nil end
    local sid = ply:SteamID()
    local sid64 = ply.SteamID64 and ply:SteamID64() or nil
    local charKey = (GRM.Identity and isfunction(GRM.Identity.CharacterKey)) and GRM.Identity.CharacterKey(ply) or nil

    for fname, f in pairs(Factions) do
        if istable(f) and istable(f.Members) then
            local member = nil
            if charKey and f.Members[charKey] then
                member = f.Members[charKey]
            elseif f.Members[sid] then
                member = f.Members[sid]
            elseif sid64 and f.Members[sid64] then
                member = f.Members[sid64]
            elseif GRM.Identity and isfunction(GRM.Identity.FactionMember) then
                member = GRM.Identity.FactionMember(f, ply)
            end

            if istable(member) then
                local inc = istable(f.IncassoSettings) and f.IncassoSettings
                    or { Enabled = false, Roles = {}, Vehicles = {} }
                return inc, member.Role or "Участник", fname, f
            end
        end
    end
    return nil, nil, nil, nil
end

function I.CanPlayerIncass(ply)
    if not isPly(ply) then return false, "Невалидный игрок" end
    if isfunction(ply.IsSuperAdmin) and ply:IsSuperAdmin() then
        local inc, roleName, fname = I.GetPlayerIncassoInfo(ply)
        return true, fname or "Администрация", inc or { Enabled = true, Roles = {}, Vehicles = {} }, roleName or "Суперадмин"
    end
    local inc, roleName, fname = I.GetPlayerIncassoInfo(ply)
    if not fname or not inc then
        return false, "Вы не состоите во фракции"
    end
    if not inc.Enabled then
        return false, "Инкассация не включена для вашей фракции («" .. tostring(fname) .. "»)"
    end
    local roleAllowed = false
    for _, r in ipairs(inc.Roles or {}) do
        if r == roleName then
            roleAllowed = true
            break
        end
    end
    if not roleAllowed then
        return false, "Ваша роль («" .. tostring(roleName) .. "») не допущена к инкассации"
    end
    return true, fname, inc, roleName
end

--[[ Флаг «этому игроку положены подсказки инкассации».
     Подсказку у хранилища раньше видели ВСЕ, включая случайных прохожих.
     Право считается на сервере (фракция + роль в IncassoSettings) и
     зеркалится в NW, чтобы клиент не гадал. ]]
if SERVER then
    function I.RefreshAccessFlag(ply)
        if not isPly(ply) then return end
        local ok = I.CanPlayerIncass(ply) == true
        if ply:GetNWBool("GRMIncass_Allowed", false) ~= ok then
            ply:SetNWBool("GRMIncass_Allowed", ok)
        end
        return ok
    end

    function I.RefreshAllAccessFlags()
        for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            I.RefreshAccessFlag(ply)
        end
    end

    hook.Add("PlayerSpawn", "GRM_Incass_AccessFlag", function(ply)
        timer.Simple(1, function() if IsValid(ply) then I.RefreshAccessFlag(ply) end end)
    end)
    hook.Add("GRM_FactionDutyChanged", "GRM_Incass_AccessFlag", function(ply)
        if IsValid(ply) then I.RefreshAccessFlag(ply) end
    end)
    hook.Add("GRM_CharacterChanged", "GRM_Incass_AccessFlag", function(ply)
        timer.Simple(0.5, function() if IsValid(ply) then I.RefreshAccessFlag(ply) end end)
    end)
    -- Состав и роли фракций меняются администрацией: раз в 15 секунд сверяем.
    timer.Create("GRM_Incass_AccessSweep", 15, 0, function() I.RefreshAllAccessFlags() end)
end

function I.IsIncassCarForFaction(veh, factionName)
    if not IsValid(veh) or not factionName then return false end
    local f = Factions and Factions[factionName]
    if not f or not istable(f.IncassoSettings) then return false end
    local allowed = f.IncassoSettings.Vehicles or {}
    if #allowed == 0 then return false end

    local eid = veh:EntIndex()
    if I._carAliasCache[eid] then
        for _, cand in ipairs(I._carAliasCache[eid]) do
            for _, name in ipairs(allowed) do
                if cand == string.lower(name) then return true end
            end
        end
        return false
    end

    local aliases = {}
    local function add(v)
        if isstring(v) and v ~= "" then
            local vl = string.lower(v)
            for _, ex in ipairs(aliases) do if ex == vl then return end end
            aliases[#aliases + 1] = vl
        end
    end

    add(veh:GetClass())
    if isstring(veh.GRM_IncassSpawnName) then add(veh.GRM_IncassSpawnName) end
    for _, fn in ipairs({
        "GetSpawn_List", "GetSpawnList", "GetSpawningName",
        "GetVehicleListName", "GetVehicleName",
        "GetLVSVehicleName", "GetVehicleClass",
    }) do
        if isfunction(veh[fn]) then
            local ok, v = pcall(veh[fn], veh)
            if ok and isstring(v) then add(v) end
        end
    end
    for _, k in ipairs({
        "SpawnList", "Spawn_List", "SpawnName", "VehicleName",
        "List_ID", "ListName", "LVSVehicleName", "VehicleClassName",
    }) do
        if isstring(veh[k]) then add(veh[k]) end
    end
    if isfunction(veh.GetKeyValues) then
        local ok, kv = pcall(veh.GetKeyValues, veh)
        if ok and istable(kv) then
            for _, k in ipairs({ "vehiclescript", "vehicletype" }) do
                if isstring(kv[k]) then add(kv[k]) end
            end
        end
    end
    if isfunction(veh.GetModel) then
        local ok, mdl = pcall(veh.GetModel, veh)
        if ok and isstring(mdl) then
            add(mdl)
            add(mdl:match("([^/\\]+)$"))
        end
    end
    if list and isfunction(list.Get) then
        for _, lstName in ipairs({ "simfphys_vehicles", "Vehicles", "LVS_Vehicles" }) do
            local lst = list.Get(lstName)
            if istable(lst) then
                for key, info in pairs(lst) do
                    if isstring(key) then
                        local okM, myMdl = pcall(veh.GetModel, veh)
                        if okM and isstring(myMdl) and istable(info) and isstring(info.Model)
                           and string.lower(info.Model) == string.lower(myMdl) then
                            add(key)
                        end
                    end
                end
            end
        end
    end

    I._carAliasCache[eid] = aliases
    for _, cand in ipairs(aliases) do
        for _, name in ipairs(allowed) do
            if cand == string.lower(name) then return true end
        end
    end
    return false
end

function I.IsActiveIncassCar(veh)
    if not IsValid(veh) then return false end
    local r = I.CarToRun[veh:EntIndex()]
    return r and I.ActiveRuns[r] and IsValid(I.ActiveRuns[r].car) or false
end

function I.FindNearestTerminal(pos, radius)
    local best, bestD = nil, math.huge
    radius = radius or I.Config.TerminalRadius
    for _, ent in ipairs(ents.FindByClass("grm_bank_terminal")) do
        if IsValid(ent) then
            local d = ent:GetPos():DistToSqr(pos)
            if d < bestD and d <= (radius * radius) then
                best, bestD = ent, d
            end
        end
    end
    return best
end

function I.FindNearestVault(pos, radius)
    radius = radius or I.Config.VaultRadius
    if GRM.Economy and GRM.Economy.Vaults then
        local best, bestD = nil, math.huge
        for _, ent in pairs(GRM.Economy.Vaults) do
            if IsValid(ent) then
                local d = ent:GetPos():DistToSqr(pos)
                if d < bestD and d <= (radius * radius) then
                    best, bestD = ent, d
                end
            end
        end
        if best then return best end
    end
    local best, bestD = nil, math.huge
    for _, ent in ipairs(ents.FindByClass("grm_bank_vault")) do
        if IsValid(ent) then
            local d = ent:GetPos():DistToSqr(pos)
            if d < bestD and d <= (radius * radius) then
                best, bestD = ent, d
            end
        end
    end
    return best
end

function I.NearbyVault(ply)
    if not isPly(ply) then return nil end
    return I.FindNearestVault(ply:GetPos(), I.Config.VaultRadius)
end

-- ── Работа с чемоданом инкассатора в руках ───────────────────────
function I.PlayerBagAmount(ply)
    if not isPly(ply) then return 0 end
    local nw = (ply.GetNWInt and ply:GetNWInt("GRMIncass_BagAmount", 0)) or 0
    if nw > 0 then return nw end
    for _, wp in ipairs(ply:GetWeapons() or {}) do
        if IsValid(wp) and wp:GetClass() == I.Config.BagWeaponClass then
            if isfunction(wp.GetCarriedAmount) then
                local a = math.max(0, math.floor(wp:GetCarriedAmount() or 0))
                if a > 0 then return a end
            elseif wp._grmAmount then
                local a = math.max(0, math.floor(wp._grmAmount or 0))
                if a > 0 then return a end
            end
        end
    end
    return 0
end

function I.GiveBagWeapon(ply, amount)
    if not isPly(ply) then return nil end
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount <= 0 then return nil end
    if I.PlayerBagAmount(ply) > 0 then return nil end

    local w = ply:GetWeapon(I.Config.BagWeaponClass)
    if not IsValid(w) then
        w = ply:Give(I.Config.BagWeaponClass)
    end
    if not IsValid(w) then return nil end

    if isfunction(w.SetCarriedAmount) then
        w:SetCarriedAmount(amount)
    end
    if isfunction(ply.SelectWeapon) then
        ply:SelectWeapon(I.Config.BagWeaponClass)
    end
    ply:SetNWBool("GRMIncass_Carrying", true)
    ply:SetNWInt("GRMIncass_BagAmount", amount)
    return w
end

function I.TakeBagWeapon(ply)
    if not isPly(ply) then return 0 end
    local amt = I.PlayerBagAmount(ply)
    if amt > 0 then
        ply:StripWeapon(I.Config.BagWeaponClass)
    end
    ply:SetNWBool("GRMIncass_Carrying", false)
    ply:SetNWInt("GRMIncass_BagAmount", 0)
    return amt
end

-- ==================================================================
-- СЕРВЕРНАЯ ЧАСТЬ (SERVER) — ПЕРСИСТЕНТНОСТЬ И ЛОГИКА
-- ==================================================================
if SERVER then

local CASH_FILE    = "grm_atm_cash.json"
local CASH_BACKUP  = "grm_atm_cash_backup.json"

local function curMapName()
    return (game and isfunction(game.GetMap) and game.GetMap()) or _G.__MAP or "unknown"
end

-- ── Персистентная база балансов банкоматов ────────────────────────
function I.LoadTerminalCashDatabase()
    local t = nil
    if file.Exists(CASH_FILE, "DATA") then
        t = jsonT(file.Read(CASH_FILE, "DATA") or "")
    end
    if not istable(t) and file.Exists(CASH_BACKUP, "DATA") then
        t = jsonT(file.Read(CASH_BACKUP, "DATA") or "")
    end
    return istable(t) and t or {}
end

function I.SaveTerminalCashDatabase(force, why)
    local curMap = curMapName()
    local records=I.LoadTerminalCashDatabase();local nextNumber=1
    for _,rec in ipairs(records)do if rec.map==curMap then nextNumber=math.max(nextNumber,(tonumber(rec.number)or 0)+1)end end

    -- 1. Собрать живые банкоматы на текущей карте
    for _, ent in ipairs(ents.FindByClass("grm_bank_terminal")) do
        if IsValid(ent) then
            local eid = ent:EntIndex()
            local cash = math.max(0, math.floor(tonumber(I.TerminalCash[eid]) or 0))
            local pos = ent:GetPos()
            local np = { x = mRound(pos.x), y = mRound(pos.y), z = mRound(pos.z) }
            local lastC = math.floor(tonumber(I.TerminalLastCollect[eid]) or 0)
            local name = isfunction(ent.GetTerminalName) and ent:GetTerminalName() or "Банк GRM"

            -- Поиск существующей записи на этой точке
            local found = false
            for _, rec in ipairs(records) do
                if rec.map == curMap and rec.pos and (math.abs(rec.pos.x - np.x) <= 16 and math.abs(rec.pos.y - np.y) <= 16 and math.abs(rec.pos.z - np.z) <= 16) then
                    rec.cash = cash
                    rec.name = name
                    rec.last_collect = lastC
                    if not tonumber(rec.number)or tonumber(rec.number)<=0 then rec.number=nextNumber;nextNumber=nextNumber+1 end
                    rec.updated=os.time();if ent.SetNWInt then ent:SetNWInt("GRM_ATMNumber",rec.number)end
                    found=true
                    break
                end
            end
            if not found then
                local number=nextNumber;nextNumber=nextNumber+1;records[#records+1]={
                    map=curMap,number=number,pos=np,name=name,cash=cash,
                    last_collect = lastC,
                    updated=os.time(),
                };if ent.SetNWInt then ent:SetNWInt("GRM_ATMNumber",number)end
            end
        end
    end

    local txt = util.TableToJSON(records, true)
    if not isstring(txt) or txt == "" then return false end

    file.Write(CASH_FILE, txt)
    file.Write(CASH_BACKUP, txt)

    local chk = file.Read(CASH_FILE, "DATA")
    if chk == txt then
        print(("[GRM Incass] SAVE ATM cash ok: записей %d, %d байт -> data/%s [%s]")
            :format(#records, #txt, CASH_FILE, tostring(why or "автосейв")))
        return true
    end
    return false
end

function I.RestoreTerminalCash(terminal)
    if not IsValid(terminal) or terminal:GetClass() ~= "grm_bank_terminal" then return end
    local eid = terminal:EntIndex()
    local curMap = curMapName()
    local pos = terminal:GetPos()
    local np = { x = mRound(pos.x), y = mRound(pos.y), z = mRound(pos.z) }

    local records = I.LoadTerminalCashDatabase()
    for _, rec in ipairs(records) do
        if rec.map == curMap and rec.pos and (math.abs(rec.pos.x - np.x) <= 16 and math.abs(rec.pos.y - np.y) <= 16 and math.abs(rec.pos.z - np.z) <= 16) then
            local cash = math.max(0, math.floor(tonumber(rec.cash) or 0))
            I.TerminalCash[eid] = cash
            I.TerminalLastCollect[eid] = tonumber(rec.last_collect) or 0
            if isfunction(terminal.SetNWInt)then terminal:SetNWInt("GRM_TerminalCash",cash);terminal:SetNWInt("GRM_ATMNumber",math.max(0,math.floor(tonumber(rec.number)or 0)))end
            if isfunction(terminal.SetTerminalName) and rec.name then
                terminal:SetTerminalName(rec.name)
            end
            print(("[GRM Incass] Банкомат #%d @ %d %d %d: восстановлен баланс %s (%s)")
                :format(eid, np.x, np.y, np.z, formatMoney(cash), tostring(rec.name or "Банк GRM")))
            return cash
        end
    end
    return 0
end
function I.GetTerminalNumber(terminal)
    if not IsValid(terminal)then return 0 end;local number=terminal:GetNWInt("GRM_ATMNumber",0);if number>0 then return number end
    I.SaveTerminalCashDatabase(true,"assign ATM number");I.RestoreTerminalCash(terminal);return terminal:GetNWInt("GRM_ATMNumber",terminal:EntIndex())
end

function I.SetTerminalCash(terminal, amount, why)
    if not IsValid(terminal) then return end
    local eid = terminal:EntIndex()
    local cash = math.max(0, math.floor(tonumber(amount) or 0))
    I.TerminalCash[eid] = cash
    if isfunction(terminal.SetNWInt) then
        terminal:SetNWInt("GRM_TerminalCash", cash)
    end
    I.SaveTerminalCashDatabase(true, why or "SetTerminalCash")
    if GRM.PermData and GRM.PermData.UpdateEntry then
        GRM.PermData.UpdateEntry(terminal)
    end
end

function I.GetTerminalCash(terminal)
    if not IsValid(terminal) then return 0 end
    local eid = terminal:EntIndex()
    if I.TerminalCash[eid] == nil then
        I.RestoreTerminalCash(terminal)
    end
    return math.max(0, math.floor(tonumber(I.TerminalCash[eid]) or 0))
end

local function unlockTerminalsOfRun(runID)
    for eid, rid in pairs(I.LockedTerminals) do
        if rid == runID then
            I.LockedTerminals[eid] = nil
            for _, ent in ipairs(ents.FindByClass("grm_bank_terminal")) do
                if IsValid(ent) and ent:EntIndex() == eid then
                    if isfunction(ent.SetNWBool) then ent:SetNWBool("GRM_IncassLocked", false) end
                    if isfunction(ent.SetNWInt) then ent:SetNWInt("GRM_IncassLockRun", 0) end
                end
            end
        end
    end
end

function I.FinishRun(runID, reason)
    local run = I.ActiveRuns[runID]
    if not run then return end
    unlockTerminalsOfRun(runID)

    if IsValid(run.car) then
        I.CarToRun[run.car:EntIndex()] = nil
        if run.car.SetNWInt then
            run.car:SetNWInt("GRM_IncassRun", 0)
            run.car:SetNWInt("GRM_IncassCarCash", 0)
        end
        if run.car.SetNWString then
            run.car:SetNWString("GRM_IncassUID", "")
            run.car:SetNWString("GRM_IncassSpawnName", "")
            run.car:SetNWString("GRM_IncassFaction", "")
        end
        I._carAliasCache[run.car:EntIndex()] = nil
        run.car.GRM_IncassUID = nil
        run.car.GRM_IncassFaction = nil
        run.car.GRM_IncassSpawnName = nil
        run.car.GRM_IncassDriver = nil
    end

    if IsValid(run.driver) then
        I.PlyToCar[run.driver:EntIndex()] = nil
        if run.driver.SetNWEntity then
            run.driver:SetNWEntity("GRM_IncassMyCar", NULL)
        end
        if I.PlayerBagAmount(run.driver) > 0 then
            I.TakeBagWeapon(run.driver)
        end
        notify(run.driver, "Рейс инкассации #" .. runID .. " завершён: " .. tostring(reason or "штатно"), 100, 220, 130)
    end

    I.ActiveRuns[runID] = nil
    print("[GRM Incass] RUN #" .. runID .. " finished: " .. tostring(reason or ""))
end

function I.CancelRun(plyOrCaller, runID, reason)
    local run = I.ActiveRuns[runID]
    if not run then return false end
    I.FinishRun(runID, tostring(reason or "отмена"))
    return true
end

function I.StartRun(ply)
    if not isPly(ply) then return false, "Игрок невалиден" end
    local ok, fnameOrErr = I.CanPlayerIncass(ply)
    if not ok then return false, fnameOrErr end

    local veh = ply:GetVehicle()
    if I.Config.RequireDriverSeat then
        if not IsValid(veh) then return false, "Сядьте за руль служебной машины" end
        veh = getRootVehicle(veh)
        if not IsValid(veh) then return false, "Не найдено ТС" end
        local drv = getDriverOf(veh)
        if IsValid(drv) and drv ~= ply then
            return false, "Вы должны быть за рулём (водитель), а не пассажиром"
        end
        if not IsValid(drv) then return false, "Сядьте на водительское место" end
    else
        veh = getRootVehicle(ply:GetVehicle())
    end
    if not IsValid(veh) then return false, "Не найдено ТС" end

    for rid, r in pairs(I.ActiveRuns) do
        if IsValid(r.driver) and r.driver == ply then
            return false, "У вас уже идёт рейс #" .. rid .. ". Завершить: /incass_off"
        end
        if IsValid(r.car) and r.car == veh then
            return false, "Эта машина уже в рейсе #" .. rid
        end
    end

    if I.Config.CarClassCheck and not (isfunction(ply.IsSuperAdmin) and ply:IsSuperAdmin()) and not I.IsIncassCarForFaction(veh, fnameOrErr) then
        local spawnNm = getVehicleSpawnName(veh) or veh:GetClass()
        return false, "Этот класс ТС («" .. tostring(veh:GetClass())
            .. (spawnNm and spawnNm ~= veh:GetClass() and "/" .. tostring(spawnNm) or "")
            .. "») не разрешён для инкассации фракции «" .. tostring(fnameOrErr) .. "»"
    end

    local runID = I.NextRunID
    I.NextRunID = I.NextRunID + 1

    local spawnName = getVehicleSpawnName(veh) or veh:GetClass()
    veh.GRM_IncassUID = "INC-" .. runID .. "-" .. os.time()
    veh.GRM_IncassFaction = fnameOrErr
    veh.GRM_IncassSpawnName = spawnName
    veh.GRM_IncassDriver = ply
    I._carAliasCache[veh:EntIndex()] = nil

    I.ActiveRuns[runID] = {
        id = runID,
        uid = veh.GRM_IncassUID,
        car = veh,
        driver = ply,
        faction = fnameOrErr,
        carClass = veh:GetClass(),
        spawnName = spawnName,
        carCash = 0,
        collected = {},
        started = CurTime(),
    }
    I.CarToRun[veh:EntIndex()] = runID
    I.PlyToCar[ply:EntIndex()] = veh

    veh:SetNWInt("GRM_IncassRun", runID)
    veh:SetNWInt("GRM_IncassCarCash", 0)
    veh:SetNWString("GRM_IncassFaction", fnameOrErr)
    veh:SetNWString("GRM_IncassSpawnName", tostring(spawnName))
    veh:SetNWString("GRM_IncassUID", tostring(veh.GRM_IncassUID))
    ply:SetNWEntity("GRM_IncassMyCar", veh)

    notify(ply, "Рейс #" .. runID .. " начат (" .. tostring(spawnName) .. "). Доступен забор и развозка средств по банкоматам. G — меню.", 100, 220, 130)

    for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
        if IsValid(p) and p ~= ply and (isfunction(p.IsAdmin) and p:IsAdmin() or isfunction(p.IsSuperAdmin) and p:IsSuperAdmin())
           and p:GetPos():DistToSqr(ply:GetPos()) <= (I.Config.NotifyPoliceRadius ^ 2) then
            notify(p, "[АДМИН] " .. ply:Nick() .. " начал рейс инкассации #" .. runID, 200, 180, 80)
        end
    end
    print("[GRM Incass] RUN #" .. runID .. " started by " .. ply:Nick())
    return true, runID
end

-- ── Изъятие суммы из терминала в чемодан ─────────────────────────
function I.CollectFromTerminal(ply, terminal, amount)
    if not isPly(ply) or not IsValid(terminal) or terminal:GetClass() ~= "grm_bank_terminal" then
        return false, "Нет терминала"
    end
    local runID = nil
    for rid, r in pairs(I.ActiveRuns) do
        if IsValid(r.driver) and r.driver == ply then
            runID = rid
            break
        end
    end
    if not runID then return false, "У вас нет активного рейса" end

    if ply:GetPos():DistToSqr(terminal:GetPos()) > (I.Config.TerminalRadius ^ 2) then
        return false, "Слишком далеко от терминала"
    end

    local eid = terminal:EntIndex()
    local cash = I.GetTerminalCash(terminal)
    if cash <= 0 then return false, "В банкомате нет наличных для изъятия" end

    local lastT = I.TerminalLastCollect[eid] or 0
    if lastT > 0 and (lastT + I.Config.TerminalCollectCooldown) > CurTime() then
        local left = math.ceil(lastT + I.Config.TerminalCollectCooldown - CurTime())
        return false, "Терминал на кулдауне (ждите " .. left .. " сек)"
    end

    if I.PlayerBagAmount(ply) > 0 then
        return false, "В руках уже есть чемодан — загрузите его в машину (G на машину → ЗАГРУЗИТЬ)"
    end

    local run = I.ActiveRuns[runID]
    local free = math.max(0, I.Config.MaxCarryPerCar - run.carCash)
    if free <= 0 then return false, "Багажник машины полон (" .. formatMoney(I.Config.MaxCarryPerCar) .. ")" end

    amount = math.floor(tonumber(amount) or cash)
    amount = math.Clamp(amount, 1, math.min(cash, free, I.Config.BagChunk))
    if amount <= 0 then return false, "Некорректная сумма" end

    I.TerminalLastCollect[eid] = CurTime()
    I.SetTerminalCash(terminal, cash - amount, "изъятие инкассатором")

    if I.Config.LockTerminalOnCollect then
        I.LockedTerminals[eid] = runID
        if isfunction(terminal.SetNWBool) then terminal:SetNWBool("GRM_IncassLocked", true) end
        if isfunction(terminal.SetNWInt) then terminal:SetNWInt("GRM_IncassLockRun", runID) end
    end

    local w = I.GiveBagWeapon(ply, amount)
    if not IsValid(w) then
        I.SetTerminalCash(terminal, cash, "откат изъятия")
        return false, "Не удалось выдать чемодан"
    end

    terminal:EmitSound("buttons/blip1.wav", 55, 100)
    notify(ply, "Чемодан " .. formatMoney(amount) .. " в руке. Загрузите в машину или вольт.", 100, 220, 130)
    return true, amount
end

-- ── Загрузка чемодана из руки в банкомат (пополнение банкомата) ──
function I.LoadBagIntoTerminal(ply, terminal)
    if not isPly(ply) or not IsValid(terminal) or terminal:GetClass() ~= "grm_bank_terminal" then
        return false, "Нет терминала"
    end
    local runID = nil
    for rid, r in pairs(I.ActiveRuns) do
        if IsValid(r.driver) and r.driver == ply then
            runID = rid
            break
        end
    end
    if not runID then return false, "У вас нет активного рейса" end

    if ply:GetPos():DistToSqr(terminal:GetPos()) > (I.Config.TerminalRadius ^ 2) then
        return false, "Слишком далеко от терминала"
    end

    local amt = I.PlayerBagAmount(ply)
    if amt <= 0 then return false, "В руках нет чемодана с деньгами" end

    local eid = terminal:EntIndex()
    local curCash = I.GetTerminalCash(terminal)
    I.SetTerminalCash(terminal, curCash + amt, "пополнение инкассатором")

    if isfunction(terminal.SetNWBool) then terminal:SetNWBool("GRM_IncassLocked", true) end
    if isfunction(terminal.SetNWInt) then terminal:SetNWInt("GRM_IncassLockRun", runID) end
    I.LockedTerminals[eid] = runID

    I.TakeBagWeapon(ply)
    terminal:EmitSound("ambient/levels/labs/coinslot1.wav", 65, 95)
    notify(ply, "Загружено в банкомат: " .. formatMoney(amt) .. ". Всего в банкомате: " .. formatMoney(curCash + amt), 100, 220, 130)
    return true, amt
end

-- ── Снятие режима блокировки банкомата ────────────────────────────
function I.UnlockTerminal(ply, terminal)
    if not isPly(ply) or not IsValid(terminal) or terminal:GetClass() ~= "grm_bank_terminal" then
        return false, "Нет терминала"
    end
    local eid = terminal:EntIndex()
    local rid = I.LockedTerminals[eid]
    if rid then
        local run = I.ActiveRuns[rid]
        if run and run.driver ~= ply and not (isfunction(ply.IsSuperAdmin) and ply:IsSuperAdmin()) then
            return false, "Этот терминал заблокирован другим инкассатором"
        end
        I.LockedTerminals[eid] = nil
    end
    if isfunction(terminal.SetNWBool) then terminal:SetNWBool("GRM_IncassLocked", false) end
    if isfunction(terminal.SetNWInt) then terminal:SetNWInt("GRM_IncassLockRun", 0) end
    terminal:EmitSound("buttons/button14.wav", 55, 100)
    notify(ply, "Обслуживание банкомата завершено (блокировка снята).", 100, 220, 130)
    return true
end

-- ── Загрузка чемодана в багажник машины ──────────────────────────
function I.LoadBagIntoCar(ply, car)
    if not isPly(ply) or not IsValid(car) then return false, "Нет машины" end
    local runID = I.CarToRun[car:EntIndex()]
    if not runID or not I.ActiveRuns[runID] then return false, "Это не инкассаторская машина" end
    local run = I.ActiveRuns[runID]
    if run.driver ~= ply then return false, "Это не ваша машина рейса" end

    if ply:GetPos():DistToSqr(car:GetPos()) > (I.Config.CarInteractRadius ^ 2) then
        return false, "Подойдите ближе к машине"
    end

    local amt = I.PlayerBagAmount(ply)
    if amt <= 0 then return false, "В руках нет чемодана с деньгами" end
    if run.carCash + amt > I.Config.MaxCarryPerCar then
        return false, "В багажнике недостаточно места"
    end

    I.TakeBagWeapon(ply)
    run.carCash = run.carCash + amt
    car:SetNWInt("GRM_IncassCarCash", run.carCash)
    car:EmitSound("physics/metal/metal_solid_impact_hard" .. math.random(1, 3) .. ".wav", 50, 100)
    notify(ply, "Загружено в машину: " .. formatMoney(amt) .. " (в машине " .. formatMoney(run.carCash) .. " / " .. formatMoney(I.Config.MaxCarryPerCar) .. ")", 100, 220, 130)
    return true, amt
end

-- ── Выгрузка чемодана из багажника машины (в любом месте!) ───────
function I.UnloadBagFromCar(ply, car)
    if not isPly(ply) or not IsValid(car) then return false, "Нет машины" end
    local runID = I.CarToRun[car:EntIndex()]
    if not runID or not I.ActiveRuns[runID] then return false, "Это не инкассаторская машина" end
    local run = I.ActiveRuns[runID]
    if run.driver ~= ply then return false, "Это не ваша машина рейса" end

    if ply:GetPos():DistToSqr(car:GetPos()) > (I.Config.CarInteractRadius ^ 2) then
        return false, "Подойдите ближе к машине"
    end
    if run.carCash <= 0 then
        return false, "В багажнике машины нет денег"
    end
    if I.PlayerBagAmount(ply) > 0 then
        return false, "В руках уже есть чемодан — загрузите его в банкомат или хранилище"
    end

    local take = math.min(I.Config.BagChunk, run.carCash)
    run.carCash = run.carCash - take
    car:SetNWInt("GRM_IncassCarCash", run.carCash)

    local w = I.GiveBagWeapon(ply, take)
    if not IsValid(w) then
        run.carCash = run.carCash + take
        car:SetNWInt("GRM_IncassCarCash", run.carCash)
        return false, "Не удалось взять чемодан"
    end

    car:EmitSound("physics/metal/metal_solid_impact_hard" .. math.random(1, 3) .. ".wav", 50, 100)
    notify(ply, "Чемодан " .. formatMoney(take) .. " в руке. Доставьте в банкомат или банк-хранилище.", 120, 200, 255)
    return true, take
end

--[[ Хранилище должно быть В ЗОНЕ ВИДИМОСТИ: раньше проверялась только
     дистанция, и сдать инкассацию можно было через стену из соседнего
     помещения. Луч от глаз к хранилищу отсекает такие «сдачи сквозь стены». ]]
local function vaultReachable(ply, vault)
    if not (isPly(ply) and IsValid(vault)) then return false end
    local radius = (I.Config and I.Config.VaultRadius) or 140
    if ply:GetPos():DistToSqr(vault:GetPos()) > (radius ^ 2) then
        return false, "Подойдите вплотную к хранилищу"
    end
    if I.Config and I.Config.VaultRequireLineOfSight == false then return true end

    local from = ply:EyePos()
    local to = vault:LocalToWorld(vault:OBBCenter())
    local tr = util.TraceLine({ start = from, endpos = to, filter = { ply, vault }, mask = MASK_SOLID_BRUSHONLY })
    if tr.Hit then
        return false, "Хранилище за стеной — подойдите к нему"
    end
    return true
end
I.VaultReachable = vaultReachable

-- ── Загрузка чемодана в хранилище банка ──────────────────────────
function I.LoadBagIntoVault(ply, vault)
    if not isPly(ply) then return false, "Нет игрока" end
    if not IsValid(vault) or vault:GetClass() ~= "grm_bank_vault" then
        vault = I.FindNearestVault(ply:GetPos(), I.Config.VaultRadius or 350)
    end
    if not IsValid(vault) or vault:GetClass() ~= "grm_bank_vault" then
        return false, "Это не банковское хранилище"
    end
    local reach, why = vaultReachable(ply, vault)
    if not reach then
        return false, why or "Слишком далеко от хранилища"
    end

    local amt = I.PlayerBagAmount(ply)
    if amt <= 0 then
        -- Проверим, возможно игрок сдает весь рейс из машины
        return I.DeliverFullRunIntoVault(ply, vault)
    end
    if not (vault.SetHeldCash and vault.GetHeldCash) then
        return false, "Хранилище не принимает деньги"
    end

    local cap = isfunction(vault.GetCapacity) and math.floor(vault:GetCapacity() or 500000) or 500000
    local curHeld = isfunction(vault.GetHeldCash) and math.floor(vault:GetHeldCash() or 0) or 0
    if curHeld + amt > cap then
        return false, "Хранилище переполнено (вместимость " .. formatMoney(cap) .. ")"
    end

    vault:SetHeldCash(curHeld + amt)
    if GRM.PermData and GRM.PermData.UpdateEntry then
        GRM.PermData.UpdateEntry(vault)
    end

    I.TakeBagWeapon(ply)
    vault:EmitSound("ambient/levels/labs/coinslot1.wav", 65, 95)
    notify(ply, "Загружено в хранилище: " .. formatMoney(amt) .. ". Всего в хранилище: " .. formatMoney(math.floor(vault:GetHeldCash() or 0)), 100, 220, 130)
    return true, amt
end

-- ── Сдача всей собранной инкассации из машины и рук в хранилище ───
function I.DeliverFullRunIntoVault(ply, vault)
    if not isPly(ply) then return false, "Нет игрока" end
    if not IsValid(vault) or vault:GetClass() ~= "grm_bank_vault" then
        vault = I.FindNearestVault(ply:GetPos(), (I.Config.VaultRadius or 350) * 1.5)
    end
    if not IsValid(vault) or vault:GetClass() ~= "grm_bank_vault" then
        return false, "Подъезжайте к банковскому хранилищу (grm_bank_vault)"
    end

    local runID = nil
    for rid, r in pairs(I.ActiveRuns) do
        if IsValid(r.driver) and r.driver == ply then
            runID = rid
            break
        end
    end

    local bagAmt = I.PlayerBagAmount(ply)
    local carAmt = 0
    local myRun = runID and I.ActiveRuns[runID]
    if myRun and IsValid(myRun.car) then
        carAmt = math.max(0, math.floor(myRun.carCash or 0))
    end

    local total = bagAmt + carAmt
    if total <= 0 then
        return false, "В руках и машине нет собранных денег для сдачи"
    end

    local cap = isfunction(vault.GetCapacity) and math.floor(vault:GetCapacity() or 500000) or 500000
    local curHeld = isfunction(vault.GetHeldCash) and math.floor(vault:GetHeldCash() or 0) or 0
    local free = math.max(0, cap - curHeld)
    if total > free then
        return false, "В хранилище недостаточно места (свободно " .. formatMoney(free) .. ")"
    end

    vault:SetHeldCash(curHeld + total)
    if GRM.PermData and GRM.PermData.UpdateEntry then
        GRM.PermData.UpdateEntry(vault)
    end

    if bagAmt > 0 then
        I.TakeBagWeapon(ply)
    end
    if myRun and IsValid(myRun.car) then
        myRun.carCash = 0
        myRun.car:SetNWInt("GRM_IncassCarCash", 0)
    end

    vault:EmitSound("ambient/levels/labs/coinslot1.wav", 75, 95)
    notify(ply, "Успешно сдано в хранилище банка: " .. formatMoney(total) .. "! Всего в хранилище: " .. formatMoney(curHeld + total), 100, 220, 130)

    if runID then
        I.FinishRun(runID, "сдача инкассации в банк (" .. formatMoney(total) .. ")")
    end
    return true, total
end

-- ── Выгрузка чемодана из хранилища (обратная операция) ───────────
function I.UnloadBagFromVault(ply, vault)
    if not isPly(ply) then return false, "Нет игрока" end
    if not IsValid(vault) or vault:GetClass() ~= "grm_bank_vault" then
        vault = I.FindNearestVault(ply:GetPos(), I.Config.VaultRadius or 350)
    end
    if not IsValid(vault) or vault:GetClass() ~= "grm_bank_vault" then
        return false, "Это не банковское хранилище"
    end
    local reach, why = vaultReachable(ply, vault)
    if not reach then
        return false, why or "Слишком далеко от хранилища"
    end
    if not (vault.SetHeldCash and vault.GetHeldCash) then
        return false, "Хранилище не поддерживает выгрузку"
    end

    local held = math.floor(vault:GetHeldCash() or 0)
    if held <= 0 then return false, "В хранилище нет денег" end
    if I.PlayerBagAmount(ply) > 0 then return false, "В руках уже есть чемодан" end

    local take = math.min(I.Config.BagChunk, held)
    vault:SetHeldCash(held - take)
    if GRM.PermData and GRM.PermData.UpdateEntry then
        GRM.PermData.UpdateEntry(vault)
    end

    local w = I.GiveBagWeapon(ply, take)
    if not IsValid(w) then
        vault:SetHeldCash(held)
        if GRM.PermData and GRM.PermData.UpdateEntry then
            GRM.PermData.UpdateEntry(vault)
        end
        return false, "Не удалось взять чемодан"
    end

    vault:EmitSound("ambient/levels/labs/coinslot1.wav", 65, 95)
    notify(ply, "Из хранилища выгружено: " .. formatMoney(take) .. " (в руке). Погрузите в машину для развозки.", 120, 200, 255)
    return true, take
end

-- ── Хуки сервера ─────────────────────────────────────────────────

-- Комиссия 5% от взносов игроков оседает в ячейке инкассации банкомата и сохраняется на диск
hook.Add("GRM_Incass_TerminalDeposit", "GRM_Incass_TerminalDeposit", function(ply, amount, terminal)
    if not IsValid(terminal) or terminal:GetClass() ~= "grm_bank_terminal" then return end
    local cut = math.floor((tonumber(amount) or 0) * (I.Config.TerminalDepositCut or 0.05))
    if cut <= 0 then return end
    local cur = I.GetTerminalCash(terminal)
    I.SetTerminalCash(terminal, cur + cut, "взнос игрока")
end)

-- Блокировка банкомата от обычных игроков во время режима инкассации
hook.Add("PlayerUse", "GRM_Incass_TermLock", function(ply, ent)
    if not isPly(ply) or not IsValid(ent) then return end
    if ent:GetClass() ~= "grm_bank_terminal" then return end
    local isLocked = (isfunction(ent.GetNWBool) and ent:GetNWBool("GRM_IncassLocked", false)) or (I.LockedTerminals[ent:EntIndex()] ~= nil)
    if not isLocked then return end

    local rid = I.LockedTerminals[ent:EntIndex()] or (isfunction(ent.GetNWInt) and ent:GetNWInt("GRM_IncassLockRun", 0)) or 0
    local myRun = nil
    for r2, r in pairs(I.ActiveRuns) do
        if IsValid(r.driver) and r.driver == ply then
            myRun = r2
            break
        end
    end
    if myRun and (myRun == rid or rid == 0) then return end -- инкассатор рейса не блокируется
    notify(ply, "Этот банкомат переведён в режим инкассации. Попробуйте позже.", 255, 180, 80)
    return false
end)

-- Удаление ТС или терминала
hook.Add("EntityRemoved", "GRM_Incass_CarRemoved", function(ent)
    if not IsValid(ent) then return end
    local rid = I.CarToRun[ent:EntIndex()]
    if rid and I.ActiveRuns[rid] then
        I.CancelRun(nil, rid, "машина удалена или уничтожена")
    end
    if ent:GetClass() == "grm_bank_terminal" then
        local eid = ent:EntIndex()
        I.SaveTerminalCashDatabase(true, "удаление банкомата")
        I.TerminalCash[eid] = nil
        I.TerminalLastCollect[eid] = nil
        I.LockedTerminals[eid] = nil
    end
end)

-- Восстановление балансов банкоматов при загрузке карты
local function restoreAllATMsOnMap()
    for _, ent in ipairs(ents.FindByClass("grm_bank_terminal")) do
        if IsValid(ent) then
            I.RestoreTerminalCash(ent)
        end
    end
end

if GRM.Boot and GRM.Boot.Task then
    GRM.Boot.Task("incass.atms", "normal", restoreAllATMsOnMap, { label = "Инкассация: восстановление банкоматов" })
else
    hook.Add("InitPostEntity", "GRM_Incass_RestoreATMs", function()
        timer.Simple(1.5, restoreAllATMsOnMap)
    end)
end

hook.Add("PostCleanupMap", "GRM_Incass_RestoreATMsCleanup", function()
    timer.Simple(1.0, restoreAllATMsOnMap)
end)

hook.Add("ShutDown", "GRM_Incass_ShutDown", function()
    I.SaveTerminalCashDatabase(true, "ShutDown сервера")
end)

-- Дисконнект игрока
hook.Add("PlayerDisconnected", "GRM_Incass_DC", function(ply)
    for rid, r in pairs(I.ActiveRuns) do
        if IsValid(r.driver) and r.driver == ply then
            I.CancelRun(nil, rid, "водитель отключился (" .. ply:Nick() .. ")")
        end
    end
end)

-- Смерть игрока (чемодан теряется)
hook.Add("PlayerDeath", "GRM_Incass_Death", function(ply)
    if I.PlayerBagAmount(ply) > 0 then
        I.TakeBagWeapon(ply)
        notify(ply, "Чемодан выпал из рук при смерти (деньги утеряны).", 255, 120, 120)
    end
end)

-- Чат-команды
hook.Add("PlayerSay", "GRM_Incass_Cmds", function(ply, text)
    if not isPly(ply) then return end
    local t = string.Trim(string.lower(text or ""))
    if t == "/incass" or t == "!incass" or t == "/инкасс" then
        local ok, err = I.StartRun(ply)
        if not ok then notify(ply, err, 255, 100, 100) end
        return ""
    end
    if t == "/incass_delivery" or t == "!incass_delivery" or t == "/incass_deliver" or t == "/сдать" then
        local ok, err = I.DeliverFullRunIntoVault(ply)
        if not ok and err then
            notify(ply, err, 255, 100, 100)
        end
        return ""
    end

    if t == "/incass_off" or t == "!incass_off" or t == "/incass_end"
       or t == "/инкасс_офф" or t == "/инкасс_стоп" then
        local runID = nil
        for rid, r in pairs(I.ActiveRuns) do
            if IsValid(r.driver) and r.driver == ply then
                runID = rid
                break
            end
        end
        if not runID then
            notify(ply, "У вас нет активного рейса инкассации.", 255, 100, 100)
        else
            I.CancelRun(ply, runID, "отмена рейса инкассации")
        end
        return ""
    end
end)

-- ── Сетевые обработчики сервера ──────────────────────────────────
local function sendTerminalMenu(ply, terminal)
    if not isPly(ply) or not IsValid(terminal) or terminal:GetClass() ~= "grm_bank_terminal" then return end
    if ply:GetPos():DistToSqr(terminal:GetPos()) > (I.Config.TerminalRadius ^ 2) then return end
    local myRun = nil
    for _, r in pairs(I.ActiveRuns) do
        if IsValid(r.driver) and r.driver == ply then
            myRun = r
            break
        end
    end
    if not myRun then
        -- молчим: G у пожарки/случайный банкомат рядом не орёт инкассацией
        return
    end

    -- Автоматический переход в режим инкассации при открытии меню инкассатором
    local eid = terminal:EntIndex()
    if isfunction(terminal.SetNWBool) then terminal:SetNWBool("GRM_IncassLocked", true) end
    if isfunction(terminal.SetNWInt) then terminal:SetNWInt("GRM_IncassLockRun", myRun.id) end
    I.LockedTerminals[eid] = myRun.id

    local cash = I.GetTerminalCash(terminal)
    net.Start(NET_TERM_MENU)
        net.WriteEntity(terminal)
        net.WriteInt(cash, 32)
        net.WriteInt(myRun.carCash or 0, 32)
        net.WriteInt(I.Config.MaxCarryPerCar, 32)
        net.WriteInt(I.PlayerBagAmount(ply), 32)
        net.WriteBool(true)
    net.Send(ply)
end

net.Receive(NET_TERM_TAKE, function(_, ply)
    local ent = net.ReadEntity()
    local amt = net.ReadInt(32)
    if not isPly(ply) or not IsValid(ent) then return end
    local ok, err = I.CollectFromTerminal(ply, ent, amt)
    if not ok and err then notify(ply, err, 255, 100, 100) end
end)

net.Receive(NET_TERM_LOAD, function(_, ply)
    local ent = net.ReadEntity()
    if not isPly(ply) or not IsValid(ent) then return end
    local ok, err = I.LoadBagIntoTerminal(ply, ent)
    if not ok and err then notify(ply, err, 255, 100, 100) end
    if ok then
        sendTerminalMenu(ply, ent)
    end
end)

net.Receive(NET_TERM_UNLOCK, function(_, ply)
    local ent = net.ReadEntity()
    if not isPly(ply) or not IsValid(ent) then return end
    local ok, err = I.UnlockTerminal(ply, ent)
    if not ok and err then notify(ply, err, 255, 100, 100) end
end)

local function isFireGContext(ply)
    if GRM.Fire and isfunction(GRM.Fire.IsFireGContext) then
        return GRM.Fire.IsFireGContext(ply) == true
    end
    if not IsValid(ply) then return false end
    local tr = ply.GetEyeTrace and ply:GetEyeTrace()
    local hit = tr and IsValid(tr.Entity) and tr.Entity or nil
    if IsValid(hit) then
        local cls = hit:GetClass() or ""
        if cls == "grm_bank_terminal" or cls == "grm_bank_vault" then return false end
        if string.sub(cls, 1, 9) == "grm_fire_" then return true end
        if hit.GetNWBool and hit:GetNWBool("GRM_FireTruck", false) then return true end
    end
    return false
end

concommand.Add("grm_incass_car_use", function(ply)
    if not isPly(ply) then return end
    if isFireGContext(ply) then return end
    local runID = nil
    for rid, r in pairs(I.ActiveRuns) do
        if IsValid(r.driver) and r.driver == ply then
            runID = rid
            break
        end
    end
    if not runID then return end
    local run = I.ActiveRuns[runID]
    if not run or not IsValid(run.car) then
        I.CancelRun(ply, runID, "машина утеряна")
        return
    end
    if ply:GetPos():DistToSqr(run.car:GetPos()) > (I.Config.CarInteractRadius ^ 2) then return end

    net.Start(NET_CAR_MENU)
        net.WriteEntity(run.car)
        net.WriteInt(run.carCash, 32)
        net.WriteBool(true)
        net.WriteInt(I.PlayerBagAmount(ply), 32)
    net.Send(ply)
end)

net.Receive(NET_CAR_LOAD, function(_, ply)
    local car = net.ReadEntity()
    if not isPly(ply) or not IsValid(car) then return end
    local ok, err = I.LoadBagIntoCar(ply, car)
    if not ok and err then notify(ply, err, 255, 100, 100) end
    if ok then
        local runID = I.CarToRun[car:EntIndex()]
        if runID and I.ActiveRuns[runID] and IsValid(I.ActiveRuns[runID].car) then
            net.Start(NET_CAR_MENU)
                net.WriteEntity(car)
                net.WriteInt(I.ActiveRuns[runID].carCash, 32)
                net.WriteBool(true)
                net.WriteInt(I.PlayerBagAmount(ply), 32)
            net.Send(ply)
        end
    end
end)

net.Receive(NET_CAR_UNLOAD, function(_, ply)
    local car = net.ReadEntity()
    if not isPly(ply) or not IsValid(car) then return end
    local ok, err = I.UnloadBagFromCar(ply, car)
    if not ok and err then notify(ply, err, 255, 100, 100) end
end)

net.Receive(NET_VAULT_MENU, function(_, ply)
    local vault = net.ReadEntity()
    if not isPly(ply) then return end
    if not IsValid(vault) or vault:GetClass() ~= "grm_bank_vault" then
        vault = I.FindNearestVault(ply:GetPos(), (I.Config.VaultRadius or 350) * 1.5)
    end
    if not IsValid(vault) or vault:GetClass() ~= "grm_bank_vault" then return end
    if not vaultReachable(ply, vault) then return end

    local held = 0
    if isfunction(vault.GetHeldCash) then held = math.floor(vault:GetHeldCash() or 0) end

    local carCash = 0
    local myCar = ply:GetNWEntity("GRM_IncassMyCar", NULL)
    if IsValid(myCar) and ply:GetPos():DistToSqr(myCar:GetPos()) <= (450 * 450) then
        local rid = I.CarToRun[myCar:EntIndex()]
        if rid and I.ActiveRuns[rid] then
            carCash = math.max(0, math.floor(I.ActiveRuns[rid].carCash or 0))
        end
    end

    net.Start(NET_VAULT_MENU)
        net.WriteEntity(vault)
        net.WriteInt(held, 32)
        net.WriteInt(I.PlayerBagAmount(ply), 32)
        net.WriteInt(carCash, 32)
    net.Send(ply)
end)

net.Receive(NET_VAULT_LOAD, function(_, ply)
    local vault = net.ReadEntity()
    if not isPly(ply) then return end
    local ok, err = I.LoadBagIntoVault(ply, vault)
    if not ok and err then notify(ply, err, 255, 100, 100) end
end)

net.Receive(NET_VAULT_DELIVER_RUN, function(_, ply)
    local vault = net.ReadEntity()
    if not isPly(ply) then return end
    local ok, err = I.DeliverFullRunIntoVault(ply, vault)
    if not ok and err then notify(ply, err, 255, 100, 100) end
end)

net.Receive(NET_VAULT_UNLOAD, function(_, ply)
    local vault = net.ReadEntity()
    if not isPly(ply) then return end
    local ok, err = I.UnloadBagFromVault(ply, vault)
    if not ok and err then notify(ply, err, 255, 100, 100) end
end)

concommand.Add("grm_incass_term_use", function(ply)
    if not isPly(ply) then return end
    if isFireGContext(ply) then return end
    local tr = ply:GetEyeTrace()
    local ent = tr.Entity
    if not (IsValid(ent) and ent:GetClass() == "grm_bank_terminal") then
        for _, t in ipairs(ents.FindByClass("grm_bank_terminal")) do
            if IsValid(t) and ply:GetPos():DistToSqr(t:GetPos()) <= (250 * 250) then
                ent = t
                break
            end
        end
    end
    if IsValid(ent) and ent:GetClass() == "grm_bank_terminal" then
        sendTerminalMenu(ply, ent)
    end
end)

concommand.Add("grm_incass_vault_use", function(ply)
    if not isPly(ply) then return end
    if isFireGContext(ply) then return end
    local tr = ply:GetEyeTrace()
    local v = (IsValid(tr.Entity) and tr.Entity:GetClass() == "grm_bank_vault") and tr.Entity or nil
    if not IsValid(v) then
        v = I.FindNearestVault(ply:GetPos(), (I.Config.VaultRadius or 350) * 1.5)
    end
    if not IsValid(v) or v:GetClass() ~= "grm_bank_vault" then return end
    if not vaultReachable(ply, v) then return end

    local held = isfunction(v.GetHeldCash) and math.floor(v:GetHeldCash() or 0) or 0
    local bagAmt = I.PlayerBagAmount(ply)

    local carCash = 0
    local myCar = ply:GetNWEntity("GRM_IncassMyCar", NULL)
    if IsValid(myCar) and ply:GetPos():DistToSqr(myCar:GetPos()) <= (450 * 450) then
        local rid = I.CarToRun[myCar:EntIndex()]
        if rid and I.ActiveRuns[rid] then
            carCash = math.max(0, math.floor(I.ActiveRuns[rid].carCash or 0))
        end
    end

    net.Start(NET_VAULT_MENU)
        net.WriteEntity(v)
        net.WriteInt(held, 32)
        net.WriteInt(bagAmt, 32)
        net.WriteInt(carCash, 32)
    net.Send(ply)
end)

concommand.Add("grm_incass_debug", function(ply)
    if not isPly(ply) or not (isfunction(ply.IsSuperAdmin) and ply:IsSuperAdmin()) then return end
    local veh = ply:GetVehicle()
    if not IsValid(veh) then ply:PrintMessage(HUD_PRINTCONSOLE, "[INCASS DEBUG] Вы не в ТС"); return end
    local root = getRootVehicle(veh)
    local spn = getVehicleSpawnName(root)
    ply:PrintMessage(HUD_PRINTCONSOLE, "[INCASS DEBUG] seat=" .. tostring(veh:GetClass()) .. " root=" .. tostring(IsValid(root) and root:GetClass() or "nil"))
    ply:PrintMessage(HUD_PRINTCONSOLE, "[INCASS DEBUG] spawnName=" .. tostring(spn))
    ply:PrintMessage(HUD_PRINTCONSOLE, "[INCASS DEBUG] bagInHands=" .. tostring(I.PlayerBagAmount(ply)))
    local myCar = ply:GetNWEntity("GRM_IncassMyCar", NULL)
    if IsValid(myCar) then
        local rid = I.CarToRun[myCar:EntIndex()]
        ply:PrintMessage(HUD_PRINTCONSOLE, "[INCASS DEBUG] myCar run=" .. tostring(rid) .. " carCash=" .. tostring(rid and I.ActiveRuns[rid] and I.ActiveRuns[rid].carCash))
    end
end)

print("[GRM Incass] SERVER: модуль Код 126 v" .. I.Version .. " загружен")

-- ==================================================================
-- КЛИЕНТСКАЯ ЧАСТЬ (CLIENT)
-- ==================================================================
else

surface.CreateFont("GRMInc_Title",  { font = "Roboto", size = 18, weight = 700, extended = true })
surface.CreateFont("GRMInc_Normal", { font = "Roboto", size = 14, weight = 500, extended = true })
surface.CreateFont("GRMInc_Small",  { font = "Roboto", size = 12, weight = 400, extended = true })
surface.CreateFont("GRMInc_3DHead", { font = "Roboto", size = 20, weight = 900, extended = true })
surface.CreateFont("GRMInc_3DSub",  { font = "Roboto", size = 14, weight = 700, extended = true })

local INC_UI = {
    bg       = Color(25, 28, 36, 245),
    header   = Color(38, 43, 56, 255),
    accent   = Color(220, 170, 60),
    accentDk = Color(170, 120, 30),
    success  = Color(70, 180, 100),
    danger   = Color(210, 70, 70),
    text     = Color(235, 235, 240),
    dim      = Color(160, 165, 178),
}

local function closeFrame(fr)
    if IsValid(fr) then fr:Remove() end
end

local GRM_INC_TERM_FRAME  = nil
local GRM_INC_CAR_FRAME   = nil
local GRM_INC_VAULT_FRAME = nil

local function fmtClient(n)
    n = math.floor(tonumber(n) or 0)
    if GRM.Format then
        local ok, s = pcall(GRM.Format, n)
        if ok and isstring(s) then return s end
    end
    return tostring(n) .. " GRM"
end

-- ── МЕНЮ ТЕРМИНАЛА ───────────────────────────────────────────────
net.Receive(NET_TERM_MENU, function()
    local term     = net.ReadEntity()
    local cash     = net.ReadInt(32)
    local inCar    = net.ReadInt(32)
    local cap      = net.ReadInt(32)
    local bag      = net.ReadInt(32)
    local isLocked = net.ReadBool()

    closeFrame(GRM_INC_TERM_FRAME)
    local f = vgui.Create("DFrame")
    GRM_INC_TERM_FRAME = f
    f:SetSize(450, 400)
    f:Center()
    f:SetTitle("")
    f:MakePopup()

    f.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, INC_UI.bg)
        draw.RoundedBoxEx(8, 0, 0, w, 38, INC_UI.header, true, true, false, false)
        draw.SimpleText("Банкомат (инкассация)", "GRMInc_Title", 12, 19, INC_UI.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local body = vgui.Create("DPanel", f)
    body:Dock(FILL)
    body:DockMargin(12, 46, 12, 12)
    body:SetPaintBackground(false)

    local function line(text, color, dy)
        local l = vgui.Create("DLabel", body)
        l:Dock(TOP)
        l:DockMargin(4, dy or 3, 4, 0)
        l:SetFont("GRMInc_Normal")
        l:SetTextColor(color or INC_UI.text)
        l:SetText(tostring(text))
        l:SizeToContents()
        return l
    end

    line("В банкомате: " .. fmtClient(cash), INC_UI.accent, 4)
    line("В машине: " .. fmtClient(inCar) .. " / " .. fmtClient(cap), INC_UI.dim)
    if bag > 0 then
        line("В руках чемодан: " .. fmtClient(bag), Color(120, 200, 255))
    end
    line("Режим инкассации: " .. (isLocked and "АКТИВЕН (терминал заблокирован для гражданских)" or "ВЫКЛЮЧЕН"), isLocked and Color(255, 180, 70) or INC_UI.dim, 6)

    local amountEntry = vgui.Create("DTextEntry", body)
    amountEntry:Dock(TOP)
    amountEntry:DockMargin(4, 10, 4, 6)
    amountEntry:SetTall(28)
    amountEntry:SetFont("GRMInc_Normal")
    amountEntry:SetNumeric(true)
    amountEntry:SetText(tostring(math.max(0, cash)))

    local function take(amount)
        net.Start(NET_TERM_TAKE)
            net.WriteEntity(term)
            net.WriteInt(amount, 32)
        net.SendToServer()
        closeFrame(f)
    end

    local btnTake = vgui.Create("DButton", body)
    btnTake:Dock(TOP)
    btnTake:DockMargin(4, 4, 4, 3)
    btnTake:SetTall(32)
    btnTake:SetFont("GRMInc_Normal")
    btnTake:SetText("⬇ Забрать указанную сумму (в чемодан)")
    btnTake:SetEnabled(cash > 0 and bag <= 0)
    btnTake.Paint = function(self, w, h)
        local c = self:IsEnabled() and (self:IsHovered() and INC_UI.accentDk or INC_UI.accent) or Color(70, 75, 85)
        draw.RoundedBox(4, 0, 0, w, h, c)
    end
    btnTake.DoClick = function()
        local v = math.floor(tonumber(amountEntry:GetText()) or 0)
        if v > 0 then take(v) end
    end

    local btnTakeAll = vgui.Create("DButton", body)
    btnTakeAll:Dock(TOP)
    btnTakeAll:DockMargin(4, 2, 4, 4)
    btnTakeAll:SetTall(28)
    btnTakeAll:SetFont("GRMInc_Normal")
    btnTakeAll:SetText("⬇ Забрать ВСЁ из банкомата")
    btnTakeAll:SetEnabled(cash > 0 and bag <= 0)
    btnTakeAll.Paint = function(self, w, h)
        local c = self:IsEnabled() and (self:IsHovered() and Color(50, 160, 80) or INC_UI.success) or Color(70, 75, 85)
        draw.RoundedBox(4, 0, 0, w, h, c)
    end
    btnTakeAll.DoClick = function()
        take(math.max(0, cash))
    end

    -- Загрузка чемодана в банкомат (пополнение банкомата деньгами из хранилища)
    local btnLoad = vgui.Create("DButton", body)
    btnLoad:Dock(TOP)
    btnLoad:DockMargin(4, 6, 4, 4)
    btnLoad:SetTall(34)
    btnLoad:SetFont("GRMInc_Normal")
    if bag > 0 then
        btnLoad:SetText("⬆ ЗАГРУЗИТЬ " .. fmtClient(bag) .. " в банкомат (пополнить)")
    else
        btnLoad:SetText("⬆ ЗАГРУЗИТЬ в банкомат (нужен чемодан в руках)")
    end
    btnLoad:SetEnabled(bag > 0)
    btnLoad.Paint = function(self, w, h)
        local c = self:IsEnabled() and (self:IsHovered() and Color(40, 150, 220) or Color(55, 125, 210)) or Color(70, 75, 85)
        draw.RoundedBox(4, 0, 0, w, h, c)
    end
    btnLoad.DoClick = function()
        net.Start(NET_TERM_LOAD)
            net.WriteEntity(term)
        net.SendToServer()
        closeFrame(f)
    end

    -- Завершение обслуживания и снятие блокировки с банкомата
    local btnUnlock = vgui.Create("DButton", body)
    btnUnlock:Dock(BOTTOM)
    btnUnlock:DockMargin(4, 6, 4, 2)
    btnUnlock:SetTall(30)
    btnUnlock:SetFont("GRMInc_Normal")
    btnUnlock:SetText("✔ Завершить обслуживание банкомата (снять блокировку)")
    btnUnlock.Paint = function(self, w, h)
        local c = self:IsHovered() and Color(60, 65, 80) or Color(45, 50, 64)
        draw.RoundedBox(4, 0, 0, w, h, c)
    end
    btnUnlock.DoClick = function()
        net.Start(NET_TERM_UNLOCK)
            net.WriteEntity(term)
        net.SendToServer()
        closeFrame(f)
    end
end)

-- ── МЕНЮ МАШИНЫ ──────────────────────────────────────────────────
net.Receive(NET_CAR_MENU, function()
    local car   = net.ReadEntity()
    local cash  = net.ReadInt(32)
    local _     = net.ReadBool()
    local bag   = net.ReadInt(32)

    closeFrame(GRM_INC_CAR_FRAME)
    local f = vgui.Create("DFrame")
    GRM_INC_CAR_FRAME = f
    f:SetSize(440, 270)
    f:Center()
    f:SetTitle("")
    f:MakePopup()

    f.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, INC_UI.bg)
        draw.RoundedBoxEx(8, 0, 0, w, 38, INC_UI.header, true, true, false, false)
        draw.SimpleText("Инкассаторская машина", "GRMInc_Title", 12, 19, INC_UI.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local body = vgui.Create("DPanel", f)
    body:Dock(FILL)
    body:DockMargin(12, 46, 12, 12)
    body:SetPaintBackground(false)

    local function line(text, color, dy)
        local l = vgui.Create("DLabel", body)
        l:Dock(TOP)
        l:DockMargin(4, dy or 4, 4, 0)
        l:SetFont("GRMInc_Normal")
        l:SetTextColor(color or INC_UI.text)
        l:SetText(tostring(text))
        l:SizeToContents()
        return l
    end

    line("В багажнике: " .. fmtClient(cash) .. " / " .. fmtClient(I.Config and I.Config.MaxCarryPerCar or 250000), INC_UI.accent, 6)
    if bag > 0 then
        line("В руках чемодан: " .. fmtClient(bag), Color(120, 200, 255))
    end

    local function mkBtn(text, enabled, color, fn)
        local b = vgui.Create("DButton", body)
        b:Dock(BOTTOM)
        b:DockMargin(4, 6, 4, 4)
        b:SetTall(38)
        b:SetFont("GRMInc_Normal")
        b:SetText(text)
        b:SetEnabled(enabled)
        b.Paint = function(self, w, h)
            local c = self:IsEnabled() and (self:IsHovered() and INC_UI.accentDk or (color or INC_UI.accent)) or Color(80, 80, 90)
            draw.RoundedBox(4, 0, 0, w, h, c)
        end
        b.DoClick = function(self)
            if self:IsEnabled() then fn() end
        end
        return b
    end

    mkBtn("⬆ ЗАГРУЗИТЬ (чемодан из руки → багажник)", bag > 0, INC_UI.success, function()
        net.Start(NET_CAR_LOAD)
            net.WriteEntity(car)
        net.SendToServer()
        closeFrame(f)
    end)

    mkBtn("⬇ РАЗГРУЗИТЬ (багажник → чемодан в руку)", cash > 0 and bag <= 0, INC_UI.accent, function()
        net.Start(NET_CAR_UNLOAD)
            net.WriteEntity(car)
        net.SendToServer()
        closeFrame(f)
    end)
end)

-- ── МЕНЮ ХРАНИЛИЩА ───────────────────────────────────────────────
net.Receive(NET_VAULT_MENU, function()
    local vault   = net.ReadEntity()
    local held    = net.ReadInt(32)
    local bag     = net.ReadInt(32)
    local carCash = net.ReadInt(32)

    closeFrame(GRM_INC_VAULT_FRAME)
    local f = vgui.Create("DFrame")
    GRM_INC_VAULT_FRAME = f
    f:SetSize(460, 310)
    f:Center()
    f:SetTitle("")
    f:MakePopup()

    f.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, INC_UI.bg)
        draw.RoundedBoxEx(8, 0, 0, w, 38, INC_UI.header, true, true, false, false)
        draw.SimpleText("Банковское хранилище (Сдача инкассации)", "GRMInc_Title", 12, 19, INC_UI.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local body = vgui.Create("DPanel", f)
    body:Dock(FILL)
    body:DockMargin(12, 46, 12, 12)
    body:SetPaintBackground(false)

    local function line(text, color, dy)
        local l = vgui.Create("DLabel", body)
        l:Dock(TOP)
        l:DockMargin(4, dy or 4, 4, 0)
        l:SetFont("GRMInc_Normal")
        l:SetTextColor(color or INC_UI.text)
        l:SetText(tostring(text))
        l:SizeToContents()
        return l
    end

    line("В хранилище сейчас: " .. fmtClient(held), INC_UI.accent, 4)
    if bag > 0 then
        line("Чемодан в руках: " .. fmtClient(bag), Color(120, 220, 140), 2)
    end
    if carCash > 0 then
        line("Собрано в инкассаторской машине: " .. fmtClient(carCash), Color(255, 205, 80), 2)
    end

    local function mkBtn(text, enabled, color, fn)
        local b = vgui.Create("DButton", body)
        b:Dock(BOTTOM)
        b:DockMargin(4, 4, 4, 2)
        b:SetTall(34)
        b:SetFont("GRMInc_Normal")
        b:SetText(text)
        b:SetEnabled(enabled)
        b.Paint = function(self, w, h)
            local c = self:IsEnabled() and (self:IsHovered() and INC_UI.accentDk or (color or INC_UI.accent)) or Color(70, 75, 85)
            draw.RoundedBox(4, 0, 0, w, h, c)
        end
        b.DoClick = function(self)
            if self:IsEnabled() then fn() end
        end
        return b
    end

    mkBtn("⬆ ЗАГРУЗИТЬ ЧЕМОДАН (из рук → в хранилище)", bag > 0, INC_UI.success, function()
        net.Start(NET_VAULT_LOAD)
            net.WriteEntity(vault)
        net.SendToServer()
        closeFrame(f)
    end)

    if carCash > 0 then
        mkBtn("⬆ СДАТЬ ВЕСЬ РЕЙС ИЗ МАШИНЫ (" .. fmtClient(carCash) .. ")", true, Color(35, 140, 190), function()
            net.Start(NET_VAULT_DELIVER_RUN)
                net.WriteEntity(vault)
            net.SendToServer()
            closeFrame(f)
        end)
    end

    mkBtn("⬇ ВЫГРУЗИТЬ (хранилище → чемодан в руку для развозки)", held > 0 and bag <= 0, INC_UI.accent, function()
        net.Start(NET_VAULT_UNLOAD)
            net.WriteEntity(vault)
        net.SendToServer()
        closeFrame(f)
    end)
end)

-- ── Уведомления клиента ──────────────────────────────────────────
net.Receive(NET_NOTIFY, function()
    local m = net.ReadString()
    local r = net.ReadUInt(8)
    local g = net.ReadUInt(8)
    local b = net.ReadUInt(8)
    chat.AddText(Color(r, g, b), "[ИНКАСС] " .. m)
    notification.AddLegacy(m, NOTIFY_GENERIC, 5)
    surface.PlaySound("buttons/lightswitch2.wav")
end)

-- ── 3D2D индикаторы над машиной и банкоматом ─────────────────────
local runVehicles=setmetatable({},{__mode="k"})
hook.Add("EntityNetworkedVarChanged","GRM_Incass_RunRegistry",function(ent,name,_,value)if name=="GRM_IncassRun"then if(tonumber(value)or 0)>0 then runVehicles[ent]=true else runVehicles[ent]=nil end end end)
hook.Add("EntityRemoved","GRM_Incass_RunRegistryRemove",function(ent)runVehicles[ent]=nil end)
timer.Simple(1,function()for _,ent in ipairs(ents.GetAll())do if IsValid(ent)and ent:GetNWInt("GRM_IncassRun",0)>0 then runVehicles[ent]=true end end end)
hook.Add("PostDrawTranslucentRenderables", "GRM_Incass_3D2D", function(depth, skybox)
    if skybox then return end
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    local myPos = ply:GetPos()

    -- 1. Индикатор над инкассаторской машиной: event-driven NW registry.
    for ent in pairs(runVehicles) do
        if IsValid(ent) and ent:GetNWInt("GRM_IncassRun", 0) > 0 then
            local epos = ent:GetPos()
            local d2 = myPos:DistToSqr(epos)
            if d2 <= (500 * 500) then
                local obbMax = isfunction(ent.OBBMaxs) and ent:OBBMaxs() or nil
                local pos = ent:LocalToWorld(Vector(0, 0, (obbMax and obbMax.z or 50) + 20))
                local ang = EyeAngles()
                ang:RotateAroundAxis(ang:Forward(), 90)
                ang:RotateAroundAxis(ang:Right(), 90)

                local carCash = ent:GetNWInt("GRM_IncassCarCash", 0)
                local faction = ent:GetNWString("GRM_IncassFaction", "")
                local cap = I.Config and I.Config.MaxCarryPerCar or 250000

                cam.Start3D2D(pos, Angle(0, ang.y, 90), 0.08)
                    draw.RoundedBox(6, -170, -32, 340, 64, Color(20, 24, 32, 230))
                    draw.RoundedBox(4, -168, -30, 336, 26, Color(35, 42, 56, 245))
                    local title = "ИНКАССАЦИЯ" .. (faction ~= "" and (" • " .. faction) or "")
                    draw.SimpleText(title, "GRMInc_3DHead", 0, -17, Color(245, 185, 65), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                    local sub = "В багажнике: " .. fmtClient(carCash) .. " / " .. fmtClient(cap)
                    draw.SimpleText(sub, "GRMInc_3DSub", 0, 16, Color(230, 235, 245), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                cam.End3D2D()
            end
        end
    end

    -- 2. Индикатор над банкоматом в режиме обслуживания
    local terminals=GRM.Perf and GRM.Perf.Entities and GRM.Perf.Entities("grm_bank_terminal")or ents.FindByClass("grm_bank_terminal")
    for _, ent in ipairs(terminals) do
        if IsValid(ent) and ent:GetNWBool("GRM_IncassLocked", false) then
            local epos = ent:GetPos()
            local d2 = myPos:DistToSqr(epos)
            if d2 <= (450 * 450) then
                local pos = epos + Vector(0, 0, 75)
                local ang = EyeAngles()
                ang:RotateAroundAxis(ang:Forward(), 90)
                ang:RotateAroundAxis(ang:Right(), 90)

                cam.Start3D2D(pos, Angle(0, ang.y, 90), 0.08)
                    draw.RoundedBox(6, -150, -28, 300, 56, Color(25, 20, 20, 235))
                    draw.RoundedBox(4, -148, -26, 296, 24, Color(65, 32, 32, 245))
                    draw.SimpleText("⚠ РЕЖИМ ИНКАССАЦИИ", "GRMInc_3DHead", 0, -14, Color(255, 195, 60), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                    draw.SimpleText("Идёт загрузка / изъятие средств", "GRMInc_3DSub", 0, 14, Color(255, 130, 130), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                cam.End3D2D()
            end
        end
    end
end)

local function getMyIncassCarClient(ply)
    local my = ply:GetNWEntity("GRM_IncassMyCar", NULL)
    if IsValid(my) and my:GetNWInt("GRM_IncassRun", 0) > 0 then return my end
    local veh = ply:GetVehicle()
    if IsValid(veh) then
        local root = getRootVehicle(veh)
        if IsValid(root) and root:GetNWInt("GRM_IncassRun", 0) > 0 then return root end
    end
    return nil
end

-- ── Единая клавиша [G] на клиенте ────────────────────────────────
-- Пожарка живёт своим G. У насоса/машины/гидранта инкассацию не трогаем.
local function isFireGContextClient(ply)
    if GRM.Fire and isfunction(GRM.Fire.IsFireGContext) then
        return GRM.Fire.IsFireGContext(ply) == true
    end
    if not IsValid(ply) then return false end
    local tr = ply.GetEyeTrace and ply:GetEyeTrace()
    local hit = tr and IsValid(tr.Entity) and tr.Entity or nil
    if IsValid(hit) then
        local cls = hit:GetClass() or ""
        if cls == "grm_bank_terminal" or cls == "grm_bank_vault" then return false end
        if string.sub(cls, 1, 9) == "grm_fire_" then return true end
        if hit.GetNWBool and hit:GetNWBool("GRM_FireTruck", false) then return true end
        local par = hit.GetParent and hit:GetParent()
        if IsValid(par) and par.GetNWBool and par:GetNWBool("GRM_FireTruck", false) then return true end
    end
    local seat = ply.GetVehicle and ply:GetVehicle()
    if IsValid(seat) then
        if seat.GetNWBool and seat:GetNWBool("GRM_FireTruck", false) then return true end
        local p = seat.GetParent and seat:GetParent()
        if IsValid(p) and p.GetNWBool and p:GetNWBool("GRM_FireTruck", false) then return true end
    end
    local pos = ply.GetPos and ply:GetPos()
    if pos then
        for _, e in ipairs(ents.FindInSphere(pos, 280)) do
            if IsValid(e) and e:GetClass() == "grm_fire_pump" then return true end
        end
    end
    return false
end

hook.Add("PlayerButtonDown", "GRM_Incass_GKey", function(ply, button)
    if button ~= KEY_G then return end
    if ply ~= LocalPlayer() then return end
    if isFireGContextClient(ply) then return end
    -- без рейса и без чемодана G инкассации нет — пожарка не ловит тост
    local onIncass = getMyIncassCarClient(ply) ~= nil
        or (ply.GetNWBool and ply:GetNWBool("GRMIncass_Carrying", false))
        or ((ply.GetNWInt and ply:GetNWInt("GRMIncass_BagAmount", 0) or 0) > 0)
    if not onIncass then return end

    local tr = ply:GetEyeTrace()
    local hit = IsValid(tr.Entity) and tr.Entity or nil
    local pPos = ply:GetPos()
    if IsValid(hit) then
        local cls = hit:GetClass() or ""
        if string.sub(cls, 1, 9) == "grm_fire_" then return end
        if hit.GetNWBool and hit:GetNWBool("GRM_FireTruck", false) then return end
    end

    -- 1. Банкомат под прицелом или рядом
    local nearTerm = hit
    if not (IsValid(nearTerm) and nearTerm:GetClass() == "grm_bank_terminal") then
        for _, ent in ipairs(ents.FindByClass("grm_bank_terminal")) do
            if IsValid(ent) and pPos:DistToSqr(ent:GetPos()) <= (250 * 250) then
                nearTerm = ent
                break
            end
        end
    end

    if IsValid(nearTerm) and nearTerm:GetClass() == "grm_bank_terminal"
       and pPos:DistToSqr(nearTerm:GetPos()) <= ((I.Config and I.Config.TerminalRadius or 250) ^ 2) then
        RunConsoleCommand("grm_incass_term_use")
        return true
    end

    -- 2. Хранилище под прицелом или рядом
    local nearVault = hit
    if not (IsValid(nearVault) and nearVault:GetClass() == "grm_bank_vault") then
        for _, ent in ipairs(ents.FindByClass("grm_bank_vault")) do
            if IsValid(ent) and pPos:DistToSqr(ent:GetPos()) <= (((I.Config and I.Config.VaultRadius) or 140) ^ 2) then
                nearVault = ent
                break
            end
        end
    end

    if IsValid(nearVault) and nearVault:GetClass() == "grm_bank_vault"
       and pPos:DistToSqr(nearVault:GetPos()) <= ((I.Config and I.Config.VaultRadius or 140) ^ 2) then
        RunConsoleCommand("grm_incass_vault_use")
        return true
    end

    -- 3. Машина под прицелом или рядом
    local car = nil
    local ec = IsValid(hit) and (hit:GetClass() or "") or ""
    if IsValid(hit) and (hit:IsVehicle() or string.StartWith(ec, "simfphys_")
       or string.StartWith(ec, "lvs_") or string.StartWith(ec, "glide_")
       or string.StartWith(ec, "gmod_sent_vehicle") or string.StartWith(ec, "prop_vehicle_")) then
        car = hit
    end
    if not IsValid(car) then
        local veh = ply:GetVehicle()
        if IsValid(veh) then car = getRootVehicle(veh) end
    end
    if not IsValid(car) then
        local myCar = getMyIncassCarClient(ply)
        if IsValid(myCar) and pPos:DistToSqr(myCar:GetPos()) <= (300 * 300) then
            car = myCar
        end
    end

    if IsValid(car) and car:GetNWInt("GRM_IncassRun", 0) > 0
       and pPos:DistToSqr(car:GetPos()) <= (300 * 300) then
        RunConsoleCommand("grm_incass_car_use")
        return true
    end
end)

-- ── HUD инкассации ───────────────────────────────────────────────
hook.Add("HUDPaint", "GRM_Incass_HUD", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local car = getMyIncassCarClient(ply)
    local carrying = ply:GetNWBool("GRMIncass_Carrying", false)
    local bagAmt = ply:GetNWInt("GRMIncass_BagAmount", 0)

    if carrying and bagAmt > 0 then
        draw.SimpleText("ИНКАСС: в руке чемодан " .. fmtClient(bagAmt),
            "GRMInc_Normal", ScrW() / 2, ScrH() - 120, Color(120, 200, 255, 230), TEXT_ALIGN_CENTER)
        draw.SimpleText("[G на машину = загрузить / G на банкомат или хранилище = сдать]",
            "GRMInc_Small", ScrW() / 2, ScrH() - 98, Color(180, 210, 255, 210), TEXT_ALIGN_CENTER)
    elseif IsValid(car) then
        local rid = car:GetNWInt("GRM_IncassRun", 0)
        local cash = car:GetNWInt("GRM_IncassCarCash", 0)
        local txt = "ИНКАСС рейс #" .. rid .. " | в машине: " .. fmtClient(cash)
        if cash >= (I.Config and I.Config.MaxCarryPerCar or 250000) then
            txt = txt .. " (МАШИНА ПОЛНА)"
        else
            txt = txt .. "  [G = меню]"
        end
        draw.SimpleText(txt, "GRMInc_Normal", ScrW() / 2, ScrH() - 120, Color(255, 220, 120, 230), TEXT_ALIGN_CENTER)
    end

    local tr = (GRM.Perf and GRM.Perf.EyeTrace) and GRM.Perf.EyeTrace(ply, 0.05) or ply:GetEyeTrace()
    if not tr then return end
    local pPos = ply:GetPos()
    local targetEnt = IsValid(tr.Entity) and tr.Entity or nil
    if not IsValid(targetEnt) then
        local vaults=GRM.Perf and GRM.Perf.Entities and GRM.Perf.Entities("grm_bank_vault")or ents.FindByClass("grm_bank_vault")
        local reach = ((I.Config and I.Config.VaultRadius) or 140) ^ 2
        for _, ent in ipairs(vaults) do
            if IsValid(ent) and pPos:DistToSqr(ent:GetPos()) <= reach then
                targetEnt = ent
                break
            end
        end
    end

    -- Подсказки видят только сотрудники допущенной фракции (и суперадмин):
    -- обычному прохожему они ни к чему и только путают.
    local allowedHint = ply:GetNWBool("GRMIncass_Allowed", false) or ply:IsSuperAdmin()

    if IsValid(targetEnt) and allowedHint then
        local pos = targetEnt:GetPos()
        local d = pPos:DistToSqr(pos)
        if targetEnt:GetClass() == "grm_bank_terminal" and d <= (250 * 250) and IsValid(car) then
            draw.SimpleText("[G] — открыть меню банкомата (изъять / загрузить)", "GRMInc_Normal",
                ScrW() / 2, ScrH() / 2 + 40, Color(255, 220, 120, 230), TEXT_ALIGN_CENTER)
        elseif targetEnt:GetClass() == "grm_bank_vault"
            and d <= (((I.Config and I.Config.VaultRadius) or 140) ^ 2) then
            draw.SimpleText("[G] — сдать инкассацию в хранилище банка", "GRMInc_Normal",
                ScrW() / 2, ScrH() / 2 + 40, Color(120, 255, 160, 230), TEXT_ALIGN_CENTER)
        end
    end
end)

print("[GRM Incass] CLIENT: модуль Код 126 v" .. I.Version .. " загружен")

end -- if SERVER / CLIENT
