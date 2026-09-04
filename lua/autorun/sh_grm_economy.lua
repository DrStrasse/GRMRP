--[[--------------------------------------------------------------------
    GRM Unified Economy v3.0.4 (Код 43) — ПЕРЕПИСАНО С НУЛЯ

    v3.0.2 (КОРЕНЬ ВСЕЙ САГИ): голый util.JSONToTable калечил числовые
    ключи-строки (wiki: «keys are converted to numbers wherever possible.
    This means using Player:SteamID64 as keys won't work») — счета банка
    после загрузки были «на печати есть», а по строке-сиду недостижимы,
    отсюда вечный «на счету 0». Теперь ВСЁ чтение — через jsonT()
    (ignoreConversions=true) + страховка fixArr для списков.

      * зеркало счетов grm_bank_nicks.json по нику/сиду с полем
        electro_balance (второй контур жизни, как у налички): счёт
        восстанавливается из зеркала при внешнем откате/вайпе treasury,
        записи без сида поднимаются по нику при входе игрока;
      * ЖЁСТКИЕ РАМКИ счёта: целое число в [0 .. GRM.MaxBalance];
      * E.GetElectroBalance / GRM.GetElectroBalance — публичный псевдоним счёта.

    Чистая версия без наслоений (SQL/сторожа файла/захвата — убраны;
    на сервере владельца SQL недоступен, файловый контур доказан).

    v3.0.1 — «банк помнит»:
      * СВЕРКА больше не затирает память файлом: «воскресший»/постаревший
        файл, который стирает чей-то счёт или бюджет, ОТКЛОНЯЕТСЯ, а память
        мгновенно перезаписывает файл обратно («самолечение» — та же
        политика, что у валюты v2.0.1, у которой наличка уже выживает);
      * банковские операции (взнос/снятие/перевод) пишутся на диск СРАЗУ,
        а не «когда-нибудь в ближайший флаш»;
      * загрузчик выбирает САМЫЙ ПОЛНЫЙ источник (основной/зеркало/семена),
        а не первый непустой: старый основной файл проигрывает свежему
        зеркалу, а не наоборот;
      * SAVE ok-печать с причиной каждой записи + рентген счетов при
        загрузке: по консоли видно, что, когда и почему пишется на диск.

    Содержит ВСЮ экономическую часть:
      1) Бюджеты/налоги фракций (ставка 0–50%, налог только с ЗП);
      2) Зарплаты по ролям/отделам/базовая, из бюджета или «воздушные»;
      3) Персональный налог: приоритет GRM.GetPlayerTaxRate (Код 13);
      4) Штрафы /fine — деньги в бюджет фракции штрафующего
         (или в гос.бюджет, или сгорают — по настройке);
      5) Гос.бюджет: налоги/штрафы → состояние; переводы фракциям,
         выплаты игрокам из админ-панели;
      6) Личные банковские счета (банкомат grm_bank_terminal): взнос,
         снятие, переводы счёт→счёт по SteamID64 (офлайн тоже);
      7) Общий фин.лог сервера + истории фракций и гос.бюджета;
      8) Единая админ-панель /feco_admin (=/salary_admin), чат-команды
         !fbudget !fpay !fwithdraw !fpayall !fsettax /mysalary /fine.

    Персистентность — простой надёжный контур:
      ПАМЯТЬ (E.Data)
        └─ save: JSON -> data/grm_treasury.json (+ зеркало _backup.json),
                 write-if-changed, read-back проверка
        └─ load: grm_treasury.json -> _backup -> grm_economy_backup.json
                 -> grm_economy.json -> grm_currency_backup -> grm_wallet_backup
                 (первый непустой по смыслу; битый источник — карантин,
                  НЕ сброс; пустой "[]" считается отсутствием файла)
        └─ сверка 15с + /dbcheck: внешние правки файла поднимаются,
           пустой внешний файл непустую память не затирает (страж).

    Зависит от: ядра валюты (Код 42) и таблицы Factions (Код 10).
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Economy = GRM.Economy or {}
local E = GRM.Economy

-- ============================================================
-- КОНФИГ
-- ============================================================
E.Config = E.Config or {
    DefaultTaxRate     = 0.05,  -- 5%
    MaxTaxRate         = 0.5,   -- потолок 50%
    SalaryInterval     = 600,   -- сек между выплатами (по умолчанию)
    MinSalaryInterval  = 60,
    HistorySize        = 50,    -- записей истории на фракцию/гос.бюджет
    PayFromBudget      = true,  -- ЗП из бюджета по умолчанию
    FineToBudget       = true,  -- штрафы → бюджет фракции штрафующего
    FineMaxAmount      = 100000,
    UseDistance        = 180,
    BankTerminalModel  = "models/starless/atm.mdl",
    TaxToState         = true,  -- налоги с ЗП → гос.бюджет (false → обратно в бюджет фракции)
    FinesToState       = true,  -- штрафы без фракции-получателя → гос.бюджет (false → сгорают)
    LogSize            = 300,   -- записей общего финансового лога
}

local DATA_FILE    = "grm_treasury.json"
local BACKUP_FILE  = "grm_treasury_backup.json"
local BANK_MIRROR_FILE = "grm_bank_nicks.json" -- зеркало счетов по нику/сиду (поле electro_balance)
local LEGACY_BUDGETS = "grm_faction_budgets.json"      -- Код 12
local LEGACY_PLUS    = "grm_faction_economy_plus.json" -- Код 9

local NET_OPEN_ADMIN = "GRM_Eco_AdminOpen"
local NET_ADMIN_DATA = "GRM_Eco_AdminData"
local NET_ADMIN_ACT  = "GRM_Eco_AdminAction"
local NET_OPEN_BANK  = "GRM_Eco_OpenBank"
local NET_BANK_ACT   = "GRM_Eco_BankAction"
local NET_SYNC       = "GRM_Eco_Sync"
local NET_INFO       = "GRM_Eco_Info"

-- ============================================================
-- СЕРВЕР
-- ============================================================
if SERVER then
    -- Синглтон: вторая копия модуля пропускается
    if GRM._economyCoreActive then
        local src = (debug and debug.getinfo and debug.getinfo(1, "S") and debug.getinfo(1, "S").short_src) or "?"
        print("[GRM Economy][!] ВТОРАЯ копия sh_grm_economy.lua ПРОПУЩЕНА, путь: " .. tostring(src))
        print("[GRM Economy][!] Активен модуль v" .. tostring(GRM._economyCoreVer) ..
              ", путь: " .. tostring(GRM._economyCoreSrc) .. ". Оставьте ОДНУ копию!")
        return
    end
    GRM._economyCoreActive = true
    GRM._economyCoreVer = "3.0.4"
    GRM._economyCoreSrc = (debug and debug.getinfo and debug.getinfo(1, "S") and debug.getinfo(1, "S").short_src) or "?"

    util.AddNetworkString(NET_OPEN_ADMIN)
    util.AddNetworkString(NET_ADMIN_DATA)
    util.AddNetworkString(NET_ADMIN_ACT)
    util.AddNetworkString(NET_OPEN_BANK)
    util.AddNetworkString(NET_BANK_ACT)
    util.AddNetworkString(NET_SYNC)
    util.AddNetworkString(NET_INFO)
    util.AddNetworkString("GRM_Bank_Sync")    -- строка «НА СЧЁТУ» в HUD (Код 48)
    util.AddNetworkString("GRM_Bank_Request")
    util.AddNetworkString("GRM_EcoAccess_Request")  -- настройка доступа (суперадмин)
    util.AddNetworkString("GRM_EcoAccess_Data")     -- данные доступа
    util.AddNetworkString("GRM_EcoAccess_Save")     -- сохранить доступ

    E.Data = E.Data or { version = 2, factions = {} }
    local dirty = false

    -- ── ДОСТУП К ЭКОНОМИЧЕСКОМУ МЕНЮ (находка 172) ─────────────
    -- Фракция «Нацбанк» (или любая) получает полномочия: лидер/зам/роли/отделы.
    -- Хранилище: data/grm_economy_access.json
    --   { [factionName] = { enabled=true, roles={}, departments={} } }
    -- Роли ПРИОРИТЕТНЫ: если roles непуст — доступ только по ролям;
    -- иначе (roles пуст) — по отделам; если оба пусты — вся фракция.
    local ACCESS_FILE = "grm_economy_access.json"
    E.Access = E.Access or {}
    local function loadAccess()
        if file.Exists(ACCESS_FILE, "DATA") then
            local ok, t = pcall(util.JSONToTable, file.Read(ACCESS_FILE, "DATA") or "", false, true)
            if ok and istable(t) then E.Access = t end
        end
    end
    local function saveAccess()
        file.CreateDir("grm_economy")
        file.Write(ACCESS_FILE, util.TableToJSON(E.Access, true))
    end
    loadAccess()

    -- Фракция игрока (имя) — как в остальной экономике
    local function economyFactionOf(ply)
        if not IsValid(ply) then return "" end
        local sid, s64 = ply:SteamID(), ply:SteamID64()
        if istable(Factions) then
            for name, f in pairs(Factions) do
                if istable(f) and istable(f.Members) and (f.Members[sid] or f.Members[s64]) then return name end
            end
        end
        return ""
    end
    -- Роль/отдел игрока во фракции
    local function economyMemberInfo(ply, factionName)
        if not IsValid(ply) or factionName == "" then return nil end
        local f = Factions and Factions[factionName]
        if not istable(f) or not istable(f.Members) then return nil end
        local sid, s64 = ply:SteamID(), ply:SteamID64()
        return f.Members[sid] or f.Members[s64]
    end

    -- Может ли игрок управлять экономикой (суперадмин — всегда)
    function E.CanManageEconomy(ply)
        if not IsValid(ply) then return false end
        if ply:IsSuperAdmin() then return true end
        local factionName = economyFactionOf(ply)
        if factionName == "" then return false end
        local acc = E.Access[factionName]
        if not acc or acc.enabled ~= true then return false end
        local member = economyMemberInfo(ply, factionName)
        if not istable(member) then return false end
        local role = tostring(member.Role or "")
        local dept = tostring(member.Department or "")
        local roles = istable(acc.roles) and acc.roles or {}
        local depts = istable(acc.departments) and acc.departments or {}
        local function countMap(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
        -- Роли приоритетны (считаем по pairs — ключи именные, не массив)
        if countMap(roles) > 0 then
            return roles[role] == true
        end
        if countMap(depts) > 0 then
            return depts[dept] == true
        end
        -- ни ролей, ни отделов — вся фракция
        return true
    end

    -- ── Сеть настройки доступа (только суперадмин) ──────────
    net.Receive("GRM_EcoAccess_Request", function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        net.Start("GRM_EcoAccess_Data")
            net.WriteTable(E.Access)
        net.Send(ply)
    end)
    net.Receive("GRM_EcoAccess_Save", function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        local factionName = net.ReadString()
        local enabled = net.ReadBool()
        local roles = net.ReadTable() or {}
        local depts = net.ReadTable() or {}
        if factionName == "" then return end
        E.Access[factionName] = { enabled = enabled == true, roles = roles, departments = depts }
        saveAccess()
        net.Start("GRM_EcoAccess_Data")
            net.WriteTable(E.Access)
        net.Send(ply)
        if GRM.Notify then GRM.Notify(ply, "Доступ к экономике [" .. factionName .. "] сохранён", 100, 220, 130) end
    end)

    -- ── Хелперы ─────────────────────────────────────────────
    local function notify(ply, msg, r, g, b)
        if GRM.Notify then GRM.Notify(ply, msg, r or 100, g or 220, b or 100) return end
        net.Start(NET_INFO) net.WriteString(tostring(msg or "")) net.Send(ply)
    end

    local function money(n) return GRM.Format and GRM.Format(n) or (tostring(n) .. " GRM") end

    -- Ключ персонажа — канон ядра (§5.2.6). Локальная копия убрана: копия разрешения ключа, общая с валютой.
    local characterKeyOf = GRM.CharKeyResolve

    local function persistedCharacterKey(value)
        local raw = tostring(value or "")
        if raw:match(":char[1-3]$") then return raw end
        if raw:match("^%d+$") then return raw .. ":char1" end
        if util.SteamIDTo64 then
            local s64 = util.SteamIDTo64(raw)
            if s64 and s64 ~= "0" then return tostring(s64) .. ":char1" end
        end
        return raw
    end

    -- членство игрока в записи фракции: ключи Members исторически бывают
    -- и SteamID, и SteamID64 (старые данные/модули) — проверяем ОБА (н101)
    local function memberRec(f, ply)
        if not (istable(f) and istable(f.Members) and IsValid(ply)) then return nil end
        local key = characterKeyOf(ply)
        if GRM.Identity and GRM.Identity.FactionMember then return GRM.Identity.FactionMember(f, ply) end
        return f.Members[ply:SteamID()] or f.Members[ply:SteamID64()]
    end

    local function factionOf(ply)
        if not Factions or not IsValid(ply) then return nil end
        for name, f in pairs(Factions) do
            if istable(f) and memberRec(f, ply) then
                return name, f
            end
        end
        return nil
    end

    local function isLeaderOf(ply, f)
        if not IsValid(ply) or not istable(f) then return false end
        local ck = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply)) or ply:SteamID64()
        if tostring(f.Leader or "") == ck then return true end
        local mem = GRM.Identity and GRM.Identity.FactionMember and GRM.Identity.FactionMember(f, ply)
        local leaderRole = f.LeaderRoleName or "Лидер"
        return istable(mem) and (mem.Role == leaderRole or mem.Role == "Лидер")
    end

    local function onlineMembers(name, f)
        local out = {}
        f = f or (Factions and Factions[name])
        if not istable(f) or not istable(f.Members) then return out end
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(p) and memberRec(f, p) then out[#out + 1] = p end
        end
        return out
    end

    -- ── Нормализация записи фракции ─────────────────────────
    local function entry(name)
        E.Data.factions[name] = E.Data.factions[name] or {}
        local e = E.Data.factions[name]
        e.budget             = math.max(0, math.floor(tonumber(e.budget) or 0))
        e.taxRate            = math.Clamp(tonumber(e.taxRate) or E.Config.DefaultTaxRate, 0, E.Config.MaxTaxRate)
        e.baseSalary         = math.max(0, math.floor(tonumber(e.baseSalary) or 0))
        e.salaryInterval     = math.max(E.Config.MinSalaryInterval, math.floor(tonumber(e.salaryInterval) or E.Config.SalaryInterval))
        e.payFromBudget      = e.payFromBudget ~= false
        e.roleSalaries       = istable(e.roleSalaries) and e.roleSalaries or {}
        e.departmentSalaries = istable(e.departmentSalaries) and e.departmentSalaries or {}
        e.history            = istable(e.history) and e.history or {}
        e.nextPay            = tonumber(e.nextPay) or (os.time() + e.salaryInterval)
        -- Права на систему штрафов (по умолчанию ВЫКЛЮЧЕНЫ)
        local fp = istable(e.finePerms) and e.finePerms or {}
        e.finePerms = fp
        fp.enabled       = fp.enabled == true     -- фракция может штрафовать вообще
        fp.allRoles      = fp.allRoles == true    -- штрафовать могут все члены
        fp.roles         = istable(fp.roles) and fp.roles or {}
        fp.ownFaction    = fp.ownFaction ~= false -- цели: свои члены
        fp.otherFactions = fp.otherFactions == true -- цели: другие фракции
        fp.civilians     = fp.civilians ~= false  -- цели: граждане
        fp.maxAmount     = math.max(0, math.floor(tonumber(fp.maxAmount) or 0))
        -- Находка 178: процент со штрафа → гос.бюджет (0-100)
        fp.statePercent  = math.Clamp(math.floor(tonumber(fp.statePercent) or 0), 0, 100)
        return e
    end

    local function addHistory(name, text)
        local h = entry(name).history
        h[#h + 1] = { t = os.time(), s = tostring(text) }
        while #h > E.Config.HistorySize do table.remove(h, 1) end
        dirty = true
    end

    local function stateHist(text)
        local st = E.Data.state
        st.history = istable(st.history) and st.history or {}
        st.history[#st.history + 1] = { t = os.time(), s = tostring(text) }
        while #st.history > E.Config.HistorySize do table.remove(st.history, 1) end
        dirty = true
    end

    -- объявлена раньше E.Fine (ниже) — upvalue
    local function stateAdd(delta, reason)
        local st = E.Data.state
        st.budget = math.max(0, math.floor((tonumber(st.budget) or 0) + delta))
        dirty = true
        if SetGlobalDouble then
            SetGlobalDouble("GRM_StateBudget", st.budget)
            SetGlobalDouble("GRM_CityBudget", st.budget)
        end
        if reason then stateHist(reason) end
        -- Находка 178: банковские хранилища отражают гос.бюджет в реальном
        -- времени (NWVar на каждом хранилище + таймер-страховка).
        if E.SyncVaultsState then E.SyncVaultsState() end
        return st.budget
    end

    -- Публичные обёртки для внешних модулей (реестр штрафов
    -- sh_grm_wanted_fines.lua): пополнение гос.бюджета и чтение доли
    -- государства в штрафах фракции. Локальные stateAdd/entry наружу
    -- не видны, поэтому нужен явный API.
    function E.StateAdd(delta, reason)
        delta = math.floor(tonumber(delta) or 0)
        if delta == 0 then return E.Data and E.Data.state and E.Data.state.budget or 0 end
        return stateAdd(delta, reason)
    end

    function E.FinePercentFor(factionName)
        factionName = tostring(factionName or "")
        if factionName == "" then return 0 end
        if not (E.Data and E.Data.factions and E.Data.factions[factionName]) then return 0 end
        local fp = entry(factionName).finePerms
        return math.Clamp(tonumber(fp and fp.statePercent) or 0, 0, 100)
    end

    -- ── БАНКОВСКИЕ ХРАНИЛИЩА (находка 178) ──────────────────
    -- Реестр живых хранилищ; дисплей хранилища показывает гос.бюджет.
    E.Vaults = E.Vaults or {}
    E.VaultCapacity = 500000 -- каждое хранилище вмещает 500.000 GRM

    function E.RegisterVault(ent)
        if IsValid(ent) then E.Vaults[ent:EntIndex()] = ent end
    end
    function E.UnregisterVault(ent)
        if IsValid(ent) then E.Vaults[ent:EntIndex()] = nil end
    end

    function E.SyncVaultsState()
        local budget = math.floor(tonumber(E.Data and E.Data.state and E.Data.state.budget) or 0)
        for _, v in pairs(E.Vaults) do
            if IsValid(v)and v.SetStateBudget and(not v.GetStateBudget or v:GetStateBudget()~=budget)then v:SetStateBudget(budget)end
        end
    end

    -- Спавн паллеты денег у хранилища (с учётом вместимости).
    -- Находка 178b: паллета НЕ пишется в HeldCash сразу — её надо
    -- ЗАГРУЗИТЬ через E-меню хранилища («Загрузить»). Так исключён
    -- двойной счёт (загрузка уже учтённой паллеты).
    -- Возвращает: сколько реально заспавнено (0 — хранилище заполнено).
    function E.SpawnVaultCash(vault, amount)
        if not IsValid(vault) then return 0 end
        amount = math.max(1, math.floor(tonumber(amount) or 0))
        local held = math.floor(tonumber(vault:GetHeldCash()) or 0)
        local cap = math.max(1, math.floor(tonumber(vault:GetCapacity()) or E.VaultCapacity))
        local free = math.max(0, cap - held)
        if free <= 0 then return 0 end
        local spawnAmt = math.min(amount, free)
        local ent = ents.Create("grm_vault_cash")
        if not IsValid(ent) then return 0 end
        local pos = E.SettleCashPos(vault:GetPos() + Vector(0, 0, 12)) or (vault:GetPos() + Vector(0, 0, 12))
        local ang = Angle(0, math.random(0, 359), 0)
        ent:SetPos(pos)
        ent:SetAngles(ang)
        ent:SetAmount(spawnAmt)
        ent.Vault = vault
        ent:Spawn()
        ent:Activate()
        if vault.EmitSound then vault:EmitSound("physics/wood/wood_crate_impact_hard1.wav", 60, 100) end
        return spawnAmt
    end

    -- Ближайший к игроку отмывщик денег (находка 179e)
    function E.FindNearestLaunderer(ply, radius)
        if not IsValid(ply) then return nil end
        radius = math.max(1, tonumber(radius) or 400)
        local best, bestD = nil, math.huge
        for _, ent in ipairs(ents.FindByClass("grm_money_launderer")) do
            if IsValid(ent) then
                local d = ply:GetPos():DistToSqr(ent:GetPos())
                if d <= radius * radius and d < bestD then best, bestD = ent, d end
            end
        end
        return best
    end

    -- «Укладчик» точки: трасса вниз ищет пол, чтобы паллета/деньги стояли
    -- ровно и не улетали/проваливались (находка 178f).
    function E.SettleCashPos(p)
        if not p then return nil end
        for i = 0, 3 do
            local probe = p + Vector(0, 0, i * 24)
            local tr = util.TraceLine({
                start = probe + Vector(0, 0, 300),
                endpos = probe - Vector(0, 0, 100),
                mask = MASK_SOLID,
            })
            if tr.Hit and not tr.StartSolid then
                return tr.HitPos + Vector(0, 0, 10)
            end
            if not tr.StartSolid then
                return probe + Vector(0, 0, 10)
            end
        end
        return p + Vector(0, 0, 60)
    end

    -- Спавн денег у точки (выгрузка из хранилища, находка 178b/178f):
    --   ≥ 50.000 → паллеты grm_vault_cash (дробление по 100.000, остаток
    --   ≥ 50.000 тоже паллетой, < 50.000 — пачкой money.mdl);
    --   < 50.000 → пачка grm_money_drop (models/props/cs_assault/money.mdl).
    function E.SpawnCashAt(pos, amount, vault)
        if not pos then return 0 end
        amount = math.max(1, math.floor(tonumber(amount) or 0))
        local spawned = 0
        local PALLET_MAX = 100000
        local PALLET_MIN = 50000

        local function mk(class, amt)
            local ent = ents.Create(class)
            if not IsValid(ent) then return end
            local p = E.SettleCashPos(pos)
            ent:SetPos(p)
            ent:SetAngles(Angle(0, math.random(0, 359), 0))
            ent:SetAmount(amt)
            if vault and class == "grm_vault_cash" then ent.Vault = vault end
            ent:Spawn()
            ent:Activate()
            spawned = spawned + amt
        end
        if amount >= PALLET_MIN then
            while amount >= PALLET_MAX do
                mk("grm_vault_cash", PALLET_MAX)
                amount = amount - PALLET_MAX
            end
            if amount >= PALLET_MIN then
                mk("grm_vault_cash", amount)
                amount = 0
            end
            if amount > 0 then mk("grm_money_drop", amount) end
        else
            mk("grm_money_drop", amount)
        end
        return spawned
    end

    -- Дроп денег в БЛИЖАЙШЕЕ к игроку хранилище (пополнение/изъятие из панели).
    -- Возвращает: сколько заспавнено.
    function E.DropCashToVault(ply, amount)
        if not IsValid(ply) or amount <= 0 then return 0 end
        local best, bestD = nil, math.huge
        for _, v in pairs(E.Vaults) do
            if IsValid(v) then
                local d = ply:GetPos():DistToSqr(v:GetPos())
                if d < bestD then best, bestD = v, d end
            end
        end
        if not IsValid(best) then return 0 end
        local spawned = E.SpawnVaultCash(best, amount)
        if spawned < amount and IsValid(ply) and GRM.Notify then
            GRM.Notify(ply, "Хранилище заполнено: вместимость " .. (GRM.Format and GRM.Format(E.VaultCapacity) or tostring(E.VaultCapacity)) .. ". Часть денег не поместилась.", 255, 190, 90)
        end
        return spawned
    end

    local function addLog(text)
        if not istable(E.Data.log) then E.Data.log = {} end
        local lg = E.Data.log
        lg[#lg + 1] = { t = os.time(), s = tostring(text) }
        local max = math.max(50, math.floor(tonumber(E.Config.LogSize) or 300))
        while #lg > max do table.remove(lg, 1) end
        dirty = true
    end
    E.Log = addLog -- публично: другие системы могут писать в фин.лог

    -- Фин.лог: зарплатный спам и строки сверки НЕ пишем
    hook.Add("GRM_MoneyChanged", "GRM_Economy_FinLog", function(ply, newBalance, delta, reason)
        if isstring(reason) then
            if string.StartWith(reason, "Зарплата") then return end
            if string.StartWith(reason, "Сверка с базой") then return end
        end
        local who = "?"
        if IsValid(ply) and ply:IsPlayer() then
            who = ply:Nick()
        elseif isstring(ply) then
            who = ply
            if GRM.GetAllBalances then
                local rec = GRM.GetAllBalances()[ply]
                if rec and rec.name then who = tostring(rec.name) end
            end
        end
        delta = math.floor(tonumber(delta) or 0)
        addLog(("%s %s%s (баланс: %s)%s"):format(
            who,
            delta >= 0 and "+" or "-",
            money(math.abs(delta)),
            money(newBalance),
            (isstring(reason) and reason ~= "") and (" | " .. reason) or ""))
    end)

    -- ── Сохранённые настройки поверх дефолтов ───────────────
    local function applyConfig()
        local c = E.Data.config
        if not istable(c) then return end
        for k, v in pairs(c) do
            if E.Config[k] ~= nil then E.Config[k] = v end
        end
        if tonumber(c.StartBalance) then GRM.StartBalance = tonumber(c.StartBalance) end
        if isstring(c.CurrencyName) and c.CurrencyName ~= "" then GRM.CurrencyName = c.CurrencyName end
    end

    -- ========================================================
    -- ПЕРСИСТЕНТНОСТЬ (простой контур: JSON-файл + зеркало)
    -- ========================================================
    local lastDiskTxt = nil -- что мы последний раз писали/читали
    local pendingNickBank = {} -- зеркало банка без сида: ник -> electro_balance (подхват при входе)

    local function extWasEmpty(t)
        if not istable(t) then return true end
        local hasF = istable(t.factions) and next(t.factions) ~= nil
        local hasA = istable(t.accounts) and next(t.accounts) ~= nil
        local hasL = istable(t.log) and next(t.log) ~= nil
        local hasS = istable(t.state) and istable(t.state.history) and next(t.state.history) ~= nil
        return not (hasF or hasA or hasL or hasS)
    end

    -- ВАЖНО (корень всей саги потерь!): голый util.JSONToTable(txt) КАЛЕЧИТ
    -- числовые ключи-строки — по умолчанию ignoreConversions=false, «keys
    -- are converted to numbers wherever possible» (офиц. wiki). SteamID64
    -- (17 цифр > 2^53) превращается в битое число 7.6561199385154e+16:
    -- счёт «на печати есть», а по строке-сиду недостижим -> «на счету 0».
    -- Парсим ТОЛЬКО так:
    local function jsonT(txt)
        local ok, t = pcall(util.JSONToTable, txt, false, true)
        return (ok and istable(t)) and t or nil
    end

    -- Страховка: если парсер всё же вернул список с ключами-строками —
    -- пересобираем его числовыми индексами (ipairs/#/table.remove не ломаются)
    local function fixArr(a)
        if not istable(a) then return {} end
        if a[1] ~= nil or a["1"] == nil then return a end
        local out, i = {}, 1
        while a[tostring(i)] ~= nil do out[i] = a[tostring(i)] i = i + 1 end
        for k, v in pairs(a) do
            if tonumber(k) == nil then out[k] = v end
        end
        return out
    end

    -- ── Зеркало банка по нику (поле electro_balance) ────────
    -- Второй контур жизни счёта: массив {sid, name, electro_balance}.
    -- Ничто не является КЛЮЧОМ таблицы -> ловушка JSONToTable с числовыми
    -- ключами тут в принципе незаконна. Если кто-то снаружи откатит или
    -- завайпит grm_treasury*.json, при загрузке счета поднимаются из
    -- зеркала (по сиду; записи без сида — по нику при входе, как наличка).
    local function saveBankMirror()
        if not istable(E.Data.accounts) then return end
        local arr = {}
        for sid, acc in pairs(E.Data.accounts) do
            arr[#arr + 1] = {
                sid = tostring(sid),
                name = tostring(istable(acc) and acc.name or "?"),
                electro_balance = math.max(0, math.floor(tonumber(istable(acc) and acc.balance) or 0)),
            }
        end
        table.sort(arr, function(a, b) return a.sid < b.sid end) -- детерминированный вывод
        local okJ, txt = pcall(util.TableToJSON, arr, true)
        if okJ and isstring(txt) and txt ~= "" then
            file.Write(BANK_MIRROR_FILE, txt)
        end
    end

    local function tryJSON(fname)
        if not file.Exists(fname, "DATA") then return nil end
        local txt = file.Read(fname, "DATA") or ""
        if string.Trim(txt) == "[]" then return nil end -- "[]" = файла нет
        local t = jsonT(txt)
        return t, txt
    end

    local function save(force, why)
        if not dirty and not force then return end
        -- АНТИСВАЙП: пустые счета+фракции НЕ затирают непустую базу.
        local myAcc = istable(E.Data.accounts) and next(E.Data.accounts) ~= nil
        local myFac = istable(E.Data.factions) and next(E.Data.factions) ~= nil
        if not myAcc and not myFac then
            local prev = lastDiskTxt
            if (not isstring(prev)) and file.Exists(DATA_FILE, "DATA") then
                prev = file.Read(DATA_FILE, "DATA")
            end
            if isstring(prev) and #prev > 0 then
                local dt = jsonT(prev)
                if dt then
                    local hadAcc = istable(dt.accounts) and next(dt.accounts) ~= nil
                    local hadFac = istable(dt.factions) and next(dt.factions) ~= nil
                    if hadAcc or hadFac then
                        print("[GRM Economy] SAVE ОТКЛОНЁН: память пуста, а в базе есть счета/фракции — базу НЕ затираем (антисвайп)")
                        dirty = false
                        return
                    end
                end
            end
        end
        -- Сериализация под pcall: ошибка откладывает запись, а не роняет таймер
        local okJ, txt = pcall(util.TableToJSON, E.Data, true)
        if not okJ or not isstring(txt) or txt == "" then
            print("[GRM Economy][!] SAVE: сериализация не удалась — повторим ближайшим флашем")
            return -- dirty остаётся
        end
        if txt == lastDiskTxt then dirty = false return end -- без изменений
        file.Write(DATA_FILE, txt)
        file.Write(BACKUP_FILE, txt)
        lastDiskTxt = txt
        dirty = false
        -- READ-BACK: перечитываем — тихая запись станет криком
        local chk = file.Read(DATA_FILE, "DATA")
        if chk ~= txt then
            print(("[GRM Economy][!] ЗАПИСЬ НЕ ПОДТВЕРДИЛАСЬ: сохранено %d байт, на диске %s")
                :format(#txt, (isstring(chk) and (tostring(#chk) .. " байт") or "файл пропал")))
        end
        saveBankMirror() -- зеркало electro_balance по нику/сиду (второй контур жизни счёта)
        print(("[GRM Economy] SAVE ok: фракций %d, счетов %d, %d байт -> data/%s [%s]"):format(
            table.Count(E.Data.factions or {}), table.Count(E.Data.accounts or {}), #txt,
            DATA_FILE, tostring(why or "сейв")))
    end

    local function importLegacy()
        local imported = 0
        -- Код 12: grm_faction_budgets.json = { [name] = { budget, taxRate } }
        local b12 = tryJSON(LEGACY_BUDGETS)
        if b12 then
            local map = b12.factions or b12
            for name, rec in pairs(map) do
                if istable(rec) then
                    local e = entry(name)
                    if (tonumber(rec.budget) or 0) > e.budget then
                        e.budget = math.floor(tonumber(rec.budget))
                    end
                    if rec.taxRate ~= nil then e.taxRate = math.Clamp(tonumber(rec.taxRate) or 0.05, 0, E.Config.MaxTaxRate) end
                    imported = imported + 1
                end
            end
        end
        -- Код 9: grm_faction_economy_plus.json
        local p9 = tryJSON(LEGACY_PLUS)
        if p9 then
            local map = p9.factions or p9
            for name, rec in pairs(map) do
                if istable(rec) and not rec.factions then
                    local e = entry(name)
                    if (tonumber(rec.budget) or 0) > e.budget then
                        e.budget = math.floor(tonumber(rec.budget))
                    end
                    if rec.taxRate ~= nil then e.taxRate = math.Clamp(tonumber(rec.taxRate) or 0.05, 0, E.Config.MaxTaxRate) end
                    e.baseSalary = math.max(e.baseSalary, math.floor(tonumber(rec.baseSalary) or 0))
                    if istable(rec.roleSalaries) then for k, v in pairs(rec.roleSalaries) do e.roleSalaries[k] = math.floor(tonumber(v) or 0) end end
                    if istable(rec.departmentSalaries) then for k, v in pairs(rec.departmentSalaries) do e.departmentSalaries[k] = math.floor(tonumber(v) or 0) end end
                    if rec.payFromBudget ~= nil then e.payFromBudget = rec.payFromBudget == true end
                    if rec.salaryInterval then e.salaryInterval = math.max(E.Config.MinSalaryInterval, math.floor(tonumber(rec.salaryInterval))) end
                    imported = imported + 1
                end
            end
        end
        if imported > 0 then
            dirty = true
            print("[GRM Economy] Импортировано фракционных записей из старых модулей: " .. imported)
        end
    end

    local LOAD_SEEDS = { DATA_FILE, BACKUP_FILE, "grm_economy_backup.json",
                         "grm_economy.json", "grm_currency_backup.json", "grm_wallet_backup.json" }

    -- Выбор источника: САМЫЙ ПОЛНЫЙ, а не первый непустой.
    -- Это ломает схему «внешняя сущность воскресила старый основной файл»:
    -- свежее зеркало всегда перетянет старый grm_treasury.json, а не наоборот.
    local function srcScore(t, tx)
        local a = istable(t.accounts) and table.Count(t.accounts) or 0
        local f = istable(t.factions) and table.Count(t.factions) or 0
        return a * 100000000 + f * 10000 + #(tx or "")
    end

    local function load()
        local t, srcName, srcTxt, best = nil, nil, nil, -1
        for _, srcf in ipairs(LOAD_SEEDS) do
            local tt, tx = tryJSON(srcf)
            if tt and not extWasEmpty(tt) then
                local sc = srcScore(tt, tx)
                if sc > best then t, srcName, srcTxt, best = tt, srcf, tx, sc end
            end
        end
        if not t then t, srcTxt = tryJSON(DATA_FILE) end
        if not t then t, srcTxt = tryJSON(BACKUP_FILE) end
        if t and istable(t.factions) then
            E.Data = t
            if srcName and srcName ~= DATA_FILE then
                print(("[GRM Economy] МИГРАЦИЯ: данные подняты из data/%s -> data/%s"):format(srcName, DATA_FILE))
            end
        else
            if file.Exists(DATA_FILE, "DATA") or file.Exists(BACKUP_FILE, "DATA") then
                local q = "grm_treasury_corruptboot_" .. os.time() .. ".txt"
                local rawB = (file.Read(DATA_FILE, "DATA") or "") .. "\n\n--== BACKUP ==--\n\n" .. (file.Read(BACKUP_FILE, "DATA") or "")
                file.Write(q, rawB)
                print("[GRM Economy] LOAD: база и зеркало биты/пусты — копии в data/" .. q .. ", данные НЕ сброшены молча")
            end
            E.Data = { version = 2, factions = {} }
            importLegacy() -- источников с данными нет: легаси-импорт
        end
        E.Data.accounts = istable(E.Data.accounts) and E.Data.accounts or {}
        -- ЖЁСТКИЕ РАМКИ: поднятые счета приводим к целым [0 .. GRM.MaxBalance]
        do
            local cap = math.max(0, math.floor(tonumber(GRM.MaxBalance) or 2000000000))
            local moved = {}
            for sid, a in pairs(E.Data.accounts) do
                if istable(a) then
                    a.balance = math.Clamp(math.floor(tonumber(a.balance) or 0), 0, cap)
                else
                    E.Data.accounts[sid] = { balance = math.Clamp(math.floor(tonumber(a) or 0), 0, cap), name = "?" }
                end
                local ck = persistedCharacterKey(sid)
                if ck ~= sid then
                    if E.Data.accounts[ck] == nil and moved[ck] == nil then moved[ck] = E.Data.accounts[sid] end
                    E.Data.accounts[sid] = nil
                    dirty = true
                end
            end
            for ck, a in pairs(moved) do E.Data.accounts[ck] = a end
            if next(moved) ~= nil then print("[GRM Economy] старые банковские счета мигрированы в CharacterKey/char1") end
        end
        E.Data.state = istable(E.Data.state) and E.Data.state or { budget = 0, history = {} }
        E.Data.state.budget = math.max(0, math.floor(tonumber(E.Data.state.budget) or 0))
        E.Data.state.history = istable(E.Data.state.history) and E.Data.state.history or {}
        E.Data.log = istable(E.Data.log) and E.Data.log or {}
        E.Data.log = fixArr(E.Data.log)
        E.Data.state.history = fixArr(E.Data.state.history)
        E.Data.config = istable(E.Data.config) and E.Data.config or {}
        applyConfig()
        for name in pairs(E.Data.factions) do entry(name) end
        -- ── Восстановление счетов из зеркала electro_balance ──
        -- treasury — главный источник; зеркало лечит лишь то, чего в нём
        -- НЕТ (внешний откат/вайп). Записи без сида ждут входа по нику.
        do
            local m = tryJSON(BANK_MIRROR_FILE)
            local restored = 0
            if istable(m) then
                local list = istable(m[1]) and m or { m }
                for _, rec in ipairs(list) do
                    if istable(rec) then
                        local cap = math.max(0, math.floor(tonumber(GRM.MaxBalance) or 2000000000))
                        local rbal = math.Clamp(math.floor(tonumber(rec.electro_balance) or 0), 0, cap)
                        local rsid = isstring(rec.sid) and rec.sid or nil
                        if rsid and rsid ~= "" then
                            local rkey = persistedCharacterKey(rsid)
                            if E.Data.accounts[rkey] == nil then
                                E.Data.accounts[rkey] = { balance = rbal, name = tostring(rec.name or "?") }
                                restored = restored + 1
                                print(("[GRM Economy] счёт %s восстановлен из зеркала electro_balance: %d (%s)")
                                    :format(rkey, rbal, tostring(rec.name or "?")))
                            end
                        else
                            local nick = tostring(rec.name or "")
                            if nick ~= "" and rbal > 0 then pendingNickBank[nick] = rbal end
                        end
                    end
                end
            end
            if restored > 0 then
                dirty = true -- материализация/флаш мгновенно залечит treasury
                print("[GRM Economy] банк-зеркало по никам: восстановлено счетов: " .. restored)
            end
        end
        if srcName ~= nil and srcName ~= DATA_FILE then
            dirty = true save(true, "материализация из " .. tostring(srcName)) -- лечим основной файл сразу
        elseif isstring(srcTxt) then
            lastDiskTxt = srcTxt -- помним содержимое диска: сверка не срабатывает вхолостую
        end
        print(("[GRM Economy] LOAD: база data/%s (источник: %s): фракций %d, счетов %d")
            :format(DATA_FILE, tostring(srcName or DATA_FILE),
                table.Count(E.Data.factions), table.Count(E.Data.accounts)))
        -- Рентген счетов: по консоли видно, КТО именно поднялся с диска
        do
            local total, shown = table.Count(E.Data.accounts), 0
            for sid, a in pairs(E.Data.accounts) do
                if shown >= 5 then break end
                print(("[GRM Economy]   счёт %s = %s (%s)"):format(tostring(sid),
                    money(math.floor(tonumber(istable(a) and a.balance) or 0)),
                    tostring(istable(a) and a.name or "?")))
                shown = shown + 1
            end
            if total > shown then print("[GRM Economy]   …и ещё счетов: " .. (total - shown)) end
        end
    end

    -- ========================================================
    -- ЛИЧНЫЕ БАНКОВСКИЕ СЧЕТА (банкомат для всех игроков)
    -- ========================================================
    local function account(sid, nick)
        sid = characterKeyOf(sid)
        if sid == "" or sid == "0" then return nil end
        E.Data.accounts = istable(E.Data.accounts) and E.Data.accounts or {}
        -- Склеиваем возможный дубль number-key (наследие до jsonT) в string-key
        local numKey = tonumber(sid)
        if numKey ~= nil and E.Data.accounts[numKey] ~= nil and E.Data.accounts[sid] == nil then
            E.Data.accounts[sid] = E.Data.accounts[numKey]
            E.Data.accounts[numKey] = nil
            dirty = true
            print("[GRM Economy] account: склеен number-key → string-key для " .. sid)
        end
        local acc = E.Data.accounts[sid]
        if not acc then
            acc = { balance = 0, name = nick or "?" }
            E.Data.accounts[sid] = acc
            dirty = true
        end
        -- ЖЁСТКИЕ РАМКИ: целое число, неотрицательное, не выше GRM.MaxBalance
        local cap = math.max(0, math.floor(tonumber(GRM.MaxBalance) or 2000000000))
        acc.balance = math.Clamp(math.floor(tonumber(acc.balance) or 0), 0, cap)
        if nick and nick ~= "" then acc.name = nick end
        return acc
    end

    local function bankBalOf(sid)
        local acc = E.Data.accounts[characterKeyOf(sid)]
        return math.max(0, math.floor(acc and acc.balance or 0))
    end

    -- Последнее отправленное клиенту значение счёта: ключ персонажа → сумма.
    -- Нужен, чтобы сторож (ниже) видел расхождение «сервер ↔ HUD» и чинил его
    -- даже там, где модуль поменял acc.balance напрямую, минуя API.
    local lastPushedBank = {}

    local function pushBank(ply)
        if not IsValid(ply) or not ply:IsPlayer() then return end
        local key = characterKeyOf(ply)
        local bal = bankBalOf(key)
        lastPushedBank[key] = bal
        net.Start("GRM_Bank_Sync")
            net.WriteDouble(bal) -- Double: UInt32 ломал счета > 4.29 млрд
        net.Send(ply)
    end
    net.Receive("GRM_Bank_Request", function(_, ply) pushBank(ply) end)

    local function pushBankBySid(sid)
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(p) and characterKeyOf(p) == tostring(sid) then pushBank(p) return end
        end
    end

    -- Публичный псевдоним: банкомат и сторонние модули могут явно попросить
    -- пересинхронизировать строку «НА СЧЁТУ» после своей операции.
    function E.PushBank(ply) pushBank(ply) end
    function E.PushBankBySid(sid) pushBankBySid(sid) end

    --[[ СТОРОЖ СИНХРОНИЗАЦИИ (задача 10).
         Историческая причина рассинхрона: счёт меняли в десятке мест, а
         GRM_Bank_Sync слали в двух. Игрок вносил деньги в банкомат и до
         перезахода видел в HUD старую сумму. Чинить каждый вызов по
         отдельности хрупко — любой новый модуль опять забудет пуш.
         Поэтому раз в секунду сверяем «что на сервере» и «что ушло в HUD»
         и досылаем разницу. Трафик копеечный: пуш идёт только при
         фактическом расхождении. ]]
    timer.Create("GRM_Economy_BankSyncWatch", 1, 0, function()
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(p) and p:IsPlayer() then
                local key = characterKeyOf(p)
                if key and key ~= "" and key ~= "0" then
                    local bal = bankBalOf(key)
                    if lastPushedBank[key] ~= bal then pushBank(p) end
                end
            end
        end
    end)

    hook.Add("PlayerDisconnected", "GRM_Economy_BankSyncForget", function(ply)
        if not IsValid(ply) then return end
        lastPushedBank[characterKeyOf(ply)] = nil
    end)

    function E.BankBalance(ply)
        local sid = characterKeyOf(ply)
        if not sid then return 0 end
        local acc = E.Data.accounts[sid]
        return acc and acc.balance or 0
    end

    hook.Add("GRM_CharacterChanged", "GRM_Economy_CharacterSync", function(ply)
        if not IsValid(ply) then return end
        account(characterKeyOf(ply), ply:Nick())
        dirty = true
        save(true, "смена персонажа")
        pushBank(ply)
    end)

    -- «Электронный баланс»:  публичный псевдоним счёта (как GRM.GetBalance у налички)
    E.GetElectroBalance = E.BankBalance
    if not GRM.GetElectroBalance then GRM.GetElectroBalance = E.BankBalance end

    -- Кулдаун банковских операций (анти-даблклик / двойной net)
    local bankOpCD = {} -- sid -> CurTime until

    function E.BankDeposit(ply, amount)
        amount = math.max(0, math.floor(tonumber(amount) or 0))
        if not IsValid(ply) or amount <= 0 then return false, "bad" end
        local sid = characterKeyOf(ply)
        if sid == "" or sid == "0" then return false, "sid" end
        local now = (CurTime and CurTime()) or os.time()
        if (bankOpCD[sid] or 0) > now then return false, "cd" end
        if not (GRM.HasMoney and GRM.HasMoney(ply, amount)) then return false, "cash" end
        local acc = account(sid, ply:Nick())
        if not acc then return false, "acc" end
        local before = acc.balance
        -- Сначала снимаем нал; если не вышло — банк не трогаем
        if not GRM.TakeMoney(ply, amount, "Банкомат: взнос на счёт") then
            return false, "take"
        end
        local cap = math.max(0, math.floor(tonumber(GRM.MaxBalance) or 2000000000))
        acc.balance = math.Clamp(before + amount, 0, cap)
        dirty = true
        bankOpCD[sid] = now + 0.35
        -- Помечаем «недавно меняли банк»: сверка не имеет права откатить взнос
        ply._grmBankTouch = now
        save(true, "взнос на счёт")
        print(("[GRM Economy] DEPOSIT %s (%s): bank %d → %d (+%d), cash taken %d")
            :format(ply:Nick(), sid, before, acc.balance, amount, amount))
        -- HUD-строка «НА СЧЁТУ» живёт на GRM_Bank_Sync: без этого пуша игрок
        -- видел старый счёт до самого перезахода (задача 10, дефект Б1).
        pushBank(ply)
        return true, acc.balance
    end

    function E.BankWithdraw(ply, amount)
        amount = math.max(0, math.floor(tonumber(amount) or 0))
        if not IsValid(ply) or amount <= 0 then return false, "bad" end
        local sid = characterKeyOf(ply)
        if sid == "" or sid == "0" then return false, "sid" end
        local now = (CurTime and CurTime()) or os.time()
        if (bankOpCD[sid] or 0) > now then return false, "cd" end
        local acc = account(sid, ply:Nick())
        if not acc then return false, "acc" end
        local before = acc.balance
        if before < amount then return false, "funds" end
        -- Сначала банк, потом нал: иначе при сбое сейва легко «размножить» деньги
        local cap = math.max(0, math.floor(tonumber(GRM.MaxBalance) or 2000000000))
        acc.balance = math.Clamp(before - amount, 0, cap)
        dirty = true
        bankOpCD[sid] = now + 0.35
        -- Помечаем «недавно меняли банк» — сверка не имеет права поднять старый больший баланс
        ply._grmBankTouch = now
        GRM.GiveMoney(ply, amount, "Банкомат: снятие со счёта")
        save(true, "снятие со счёта")
        print(("[GRM Economy] WITHDRAW %s (%s): bank %d → %d (-%d), cash +%d")
            :format(ply:Nick(), sid, before, acc.balance, amount, amount))
        if acc.balance ~= before - amount and not (before - amount < 0) then
            print("[GRM Economy][!] WITHDRAW anomaly: expected " .. tostring(before - amount) .. " got " .. tostring(acc.balance))
        end
        pushBank(ply) -- задача 10, дефект Б1: HUD-строка «НА СЧЁТУ»
        return true, acc.balance
    end

    -- Счёт -> счёт (получатель может быть офлайн: ключ — SteamID64)
    function E.BankTransfer(ply, toSid, amount)
        amount = math.max(0, math.floor(tonumber(amount) or 0))
        if not IsValid(ply) or amount <= 0 then return false end
        local fromSid = characterKeyOf(ply)
        toSid = tostring(toSid or "")
        if fromSid == "" or toSid == "" or toSid == fromSid then return false end
        local now = (CurTime and CurTime()) or os.time()
        if (bankOpCD[fromSid] or 0) > now then return false end
        local from = account(fromSid, ply:Nick())
        if not from or from.balance < amount then return false end
        local to = account(toSid)
        if not to then return false end
        local cap = math.max(0, math.floor(tonumber(GRM.MaxBalance) or 2000000000))
        local fb, tb = from.balance, to.balance
        from.balance = math.Clamp(fb - amount, 0, cap)
        to.balance = math.Clamp(tb + amount, 0, cap)
        dirty = true
        bankOpCD[fromSid] = now + 0.35
        ply._grmBankTouch = now
        addLog(("Перевод счёт→счёт: %s → %s: %s"):format(ply:Nick(), toSid, money(amount)))
        save(true, "перевод счёт→счёт")
        print(("[GRM Economy] TRANSFER %s → %s: %d; from %d→%d to %d→%d")
            :format(fromSid, toSid, amount, fb, from.balance, tb, to.balance))
        -- Обе стороны перевода: отправитель и (если онлайн) получатель
        pushBank(ply)
        pushBankBySid(toSid)
        return true, from.balance
    end

    -- ── Безналичное списание / зачисление (Код 127: госуслуги, счета) ──
    -- BankWithdraw превращает деньги в наличные, а для оплаты услуг нужно
    -- именно снять со счёта, никому ничего не выдавая на руки.
    -- @return true, новый остаток | false, причина
    function E.BankTake(ply, amount, reason)
        amount = math.max(0, math.floor(tonumber(amount) or 0))
        if not IsValid(ply) or amount <= 0 then return false, "bad" end
        local sid = characterKeyOf(ply)
        if sid == "" or sid == "0" then return false, "sid" end
        local acc = account(sid, ply:Nick())
        if not acc then return false, "acc" end
        local before = acc.balance
        if before < amount then return false, "funds" end
        local cap = math.max(0, math.floor(tonumber(GRM.MaxBalance) or 2000000000))
        acc.balance = math.Clamp(before - amount, 0, cap)
        dirty = true
        ply._grmBankTouch = (CurTime and CurTime()) or os.time()
        save(true, reason or "безналичное списание")
        addLog(("Безнал: %s -%s (%s)"):format(ply:Nick(), money(amount), tostring(reason or "оплата")))
        pushBank(ply)
        return true, acc.balance
    end

    function E.BankGive(ply, amount, reason)
        amount = math.max(0, math.floor(tonumber(amount) or 0))
        if not IsValid(ply) or amount <= 0 then return false, "bad" end
        local sid = characterKeyOf(ply)
        if sid == "" or sid == "0" then return false, "sid" end
        local acc = account(sid, ply:Nick())
        if not acc then return false, "acc" end
        local cap = math.max(0, math.floor(tonumber(GRM.MaxBalance) or 2000000000))
        acc.balance = math.Clamp(acc.balance + amount, 0, cap)
        dirty = true
        ply._grmBankTouch = (CurTime and CurTime()) or os.time()
        save(true, reason or "безналичное зачисление")
        addLog(("Безнал: %s +%s (%s)"):format(ply:Nick(), money(amount), tostring(reason or "зачисление")))
        pushBank(ply)
        return true, acc.balance
    end

    -- Системный ключ фракции: DisplayName / Tag / регистр не должны плодить
    -- вторую казну. Субсидия с ПК банка и закупка флота обязаны бить в одну запись.
    local function resolveFactionKey(name)
        name = tostring(name or "")
        if name == "" then return nil end
        if istable(Factions) and istable(Factions[name]) then return name end
        if FactionsAPI and isfunction(FactionsAPI.GetRegistrationName) then
            local key = FactionsAPI.GetRegistrationName(name)
            if isstring(key) and key ~= "" then return key end
        end
        local low = string.lower(name)
        if istable(Factions) then
            for key, f in pairs(Factions) do
                if istable(f) then
                    if string.lower(tostring(key)) == low then return key end
                    if string.lower(tostring(f.DisplayName or "")) == low then return key end
                    if string.lower(tostring(f.Tag or "")) == low then return key end
                end
            end
        end
        if istable(E.Data.factions) and istable(E.Data.factions[name]) then return name end
        if istable(E.Data.factions) then
            for key in pairs(E.Data.factions) do
                if string.lower(tostring(key)) == low then return key end
            end
        end
        return name
    end
    E.ResolveFactionKey = resolveFactionKey

    -- Все алиасы одной организации: регистрационное имя, витрина, тег, казна в JSON.
    local function factionAliases(name)
        local key = resolveFactionKey(name)
        if not key then return {} end
        local seen, out = {}, {}
        local function add(v)
            v = tostring(v or "")
            if v == "" or seen[v] then return end
            seen[v] = true
            out[#out + 1] = v
        end
        add(key)
        add(name)
        local f = istable(Factions) and Factions[key] or nil
        if istable(f) then
            add(f.DisplayName)
            add(f.displayName)
            add(f.Tag)
        end
        local low = string.lower(key)
        if istable(E.Data.factions) then
            for k in pairs(E.Data.factions) do
                if string.lower(tostring(k)) == low then add(k) end
            end
        end
        return out, key
    end

    local mirrorFactionBudget
    -- Поднять казну из зеркала Factions.Budget / разъехавшихся ключей JSON.
    local function foldFactionBudget(name)
        local aliases, key = factionAliases(name)
        if not key then return 0, nil end
        local best = 0
        for _, alias in ipairs(aliases) do
            local e = istable(E.Data.factions) and E.Data.factions[alias]
            best = math.max(best, math.floor(tonumber(e and e.budget) or 0))
            local fac = istable(Factions) and Factions[alias]
            best = math.max(best, math.floor(tonumber(fac and fac.Budget) or 0))
        end
        local e = entry(key)
        local changed = false
        if best > (tonumber(e.budget) or 0) then
            e.budget = best
            dirty = true
            changed = true
        end
        for _, alias in ipairs(aliases) do
            if alias ~= key and istable(E.Data.factions) and istable(E.Data.factions[alias]) then
                local other = E.Data.factions[alias]
                if (tonumber(other.budget) or 0) > 0 then
                    other.budget = 0
                    dirty = true
                    changed = true
                end
            end
        end
        if changed then mirrorFactionBudget(key, e.budget) end
        return e.budget, key
    end

    mirrorFactionBudget = function(key, amount)
        amount = math.max(0, math.floor(tonumber(amount) or 0))
        if istable(Factions) and istable(Factions[key]) then
            Factions[key].Budget = amount
        end
        if CLIENT and istable(FactionsData) and istable(FactionsData[key]) then
            FactionsData[key].Budget = amount
        end
        if GRM.Perf and GRM.Perf.Coalesce then
            GRM.Perf.Coalesce("grm_eco_fac_budget_" .. tostring(key), 0.2, function()
                if FactionsAPI and isfunction(FactionsAPI.Broadcast) then
                    FactionsAPI.Broadcast()
                end
            end)
        elseif FactionsAPI and isfunction(FactionsAPI.Broadcast) then
            FactionsAPI.Broadcast()
        end
    end

    -- ========================================================
    -- ПУБЛИЧНОЕ API (совместимость с Кодом 13 и др.)
    -- ========================================================
    -- 0 в Lua ложный: «Get() or f.Budget» показывало миллионы из карточки
    -- фракции, а автопарк читал казну и видел ноль. Get ВСЕГДА поднимает
    -- зеркало Factions.Budget в казну и возвращает живую сумму.
    function GRM.FactionBudgetGet(name)
        local amount = foldFactionBudget(name)
        return math.max(0, math.floor(tonumber(amount) or 0))
    end

    function GRM.FactionBudgetAdd(name, delta, silentReason)
        local _, key = foldFactionBudget(name)
        if not key then return 0 end
        delta = math.floor(tonumber(delta) or 0)
        if delta == 0 then return GRM.FactionBudgetGet(key) end
        local e = entry(key)
        e.budget = math.max(0, e.budget + delta)
        dirty = true
        if silentReason then addHistory(key, silentReason) end
        mirrorFactionBudget(key, e.budget)
        if FactionsAPI and isfunction(FactionsAPI.Save) then pcall(FactionsAPI.Save) end
        hook.Run("GRM_FactionBudgetChanged", key, e.budget, delta)
        return e.budget
    end

    function GRM.FactionBudgetSet(name, value)
        local _, key = foldFactionBudget(name)
        if not key then return end
        local e = entry(key)
        e.budget = math.max(0, math.floor(tonumber(value) or 0))
        dirty = true
        mirrorFactionBudget(key, e.budget)
        if FactionsAPI and isfunction(FactionsAPI.Save) then pcall(FactionsAPI.Save) end
        hook.Run("GRM_FactionBudgetChanged", key, e.budget, 0)
        return e.budget
    end

    function E.TaxRateGet(name)
        return GRM.FactionTaxGet(name)
    end

    -- ── Гос.бюджет (публичный доступ для единой админ-панели, Код 82) ──
    function E.StateBudgetGet()
        return math.floor(tonumber(E.Data.state and E.Data.state.budget) or 0)
    end

    function E.StateBudgetAdd(delta, reason)
        return stateAdd(math.floor(tonumber(delta) or 0), reason)
    end

    function E.StateBudgetSet(value, reason)
        E.Data.state.budget = math.max(0, math.floor(tonumber(value) or 0))
        dirty = true
        if SetGlobalDouble then
            SetGlobalDouble("GRM_StateBudget", E.Data.state.budget)
            SetGlobalDouble("GRM_CityBudget", E.Data.state.budget)
        end
        if reason then stateHist(reason) end
        -- Находка 178: синк дисплеев хранилищ
        if E.SyncVaultsState then E.SyncVaultsState() end
        return E.Data.state.budget
    end

    function GRM.StateBudgetGet()
        if SERVER and E.StateBudgetGet then return E.StateBudgetGet() end
        if GetGlobalDouble then return GetGlobalDouble("GRM_StateBudget", 0) end
        return 0
    end

    function GRM.CityBudgetGet()
        return GRM.StateBudgetGet()
    end
    function GRM.CityBudgetAdd(delta, reason)
        return E.StateBudgetAdd(delta, reason)
    end
    E.CityBudgetGet = E.StateBudgetGet
    E.CityBudgetAdd = E.StateBudgetAdd

    -- Сводка по фракции для админ-панелей (не мутирует запись)
    function E.FactionInfo(name)
        local e = E.Data.factions[name]
        if not istable(e) then return nil end
        return {
            budget = math.floor(tonumber(e.budget) or 0),
            taxRate = tonumber(e.taxRate) or 0,
            baseSalary = math.floor(tonumber(e.baseSalary) or 0),
            salaryInterval = math.floor(tonumber(e.salaryInterval) or 0),
            payFromBudget = e.payFromBudget == true,
        }
    end

    function GRM.FactionTaxGet(name)
        local key = resolveFactionKey(name)
        if not key then return E.Config.DefaultTaxRate end
        local e = E.Data.factions[key]
        return e and e.taxRate or E.Config.DefaultTaxRate
    end

    function GRM.FactionTaxSet(name, rate)
        local key = resolveFactionKey(name)
        if not key then return end
        entry(key).taxRate = math.Clamp(tonumber(rate) or 0, 0, E.Config.MaxTaxRate)
        dirty = true
    end

    -- ── Зарплата конкретного игрока ─────────────────────────
    function E.GetSalaryFor(ply)
        local name, f = factionOf(ply)
        if not name then return 0, nil end
        local e = entry(name)
        local info = GRM.Identity.FactionMember(f, ply) or {}
        local gross = (info.Role and math.floor(tonumber(e.roleSalaries[info.Role]) or 0) or 0)
        if gross <= 0 and info.Department then
            gross = math.floor(tonumber(e.departmentSalaries[info.Department]) or 0)
        end
        if gross <= 0 then gross = e.baseSalary end
        return gross, name
    end

    -- Эффективная ставка: персональная (Код 13) > фракционная
    local function taxRateFor(ply, name)
        if GRM.GetPlayerTaxRate then
            local ok, r = pcall(GRM.GetPlayerTaxRate, ply)
            if ok and tonumber(r) then return math.Clamp(tonumber(r), 0, E.Config.MaxTaxRate) end
        end
        return GRM.FactionTaxGet(name)
    end

    -- ── Движок выплат: один таймер на всё ───────────────────
    local function payFaction(name, e)
        local paid, skipped = 0, 0
        for _, ply in ipairs(onlineMembers(name)) do
            local gross = E.GetSalaryFor(ply)
            if gross and gross > 0 then
                if e.payFromBudget and e.budget < gross then
                    notify(ply, "[" .. name .. "] Зарплата не выплачена: бюджет пуст.", 255, 120, 80)
                    skipped = skipped + 1
                else
                    local rate = taxRateFor(ply, name)
                    local tax  = math.floor(gross * rate)
                    local net  = gross - tax
                    if e.payFromBudget then e.budget = e.budget - gross end
                    if E.Config.TaxToState then
                        stateAdd(tax, ("Налог %d%% с ЗП %s [%s]"):format(math.floor(rate * 100), ply:Nick(), name))
                    else
                        e.budget = math.max(0, e.budget + tax)
                    end
                    GRM.GiveMoney(ply, net, "Зарплата [" .. name .. "]")
                    notify(ply, "Зарплата [" .. name .. "]: " .. money(net)
                        .. " (налог " .. math.floor(rate * 100) .. "%)", 100, 220, 100)
                    addHistory(name, "ЗП " .. ply:Nick() .. ": " .. money(net) .. " (налог " .. money(tax) .. ")")
                    paid = paid + 1
                end
            end
        end
        dirty = true
        if paid > 0 then
            addHistory(name, "Выплата зарплат: " .. paid .. " чел." .. (skipped > 0 and (", пропущено бюджетом: " .. skipped) or ""))
        end
    end

    timer.Create("GRM_Economy_SalaryEngine", 20, 0, function()
        local now = os.time()
        for name in pairs(E.Data.factions) do
            local e = entry(name)
            if now >= e.nextPay then
                e.nextPay = now + e.salaryInterval
                payFaction(name, e)
            end
        end
    end)

    -- Подхват счёта ПО НИКУ из зеркала electro_balance при входе (как у налички)
    hook.Add("PlayerInitialSpawn", "GRM_Economy_BankJoin", function(ply)
        timer.Simple(2, function()
            if not IsValid(ply) or not ply:IsPlayer() then return end
            local nick = ply:Nick()
            local want = pendingNickBank[nick]
            if want ~= nil then
                pendingNickBank[nick] = nil
                local sid = characterKeyOf(ply)
                if isstring(sid) and E.Data.accounts[sid] == nil then
                    E.Data.accounts[sid] = { balance = want, name = nick }
                    dirty = true
                    save(true, "счёт поднят ПО НИКУ (зеркало electro_balance)")
                    print(("[GRM Economy] счёт %s поднят ПО НИКУ «%s» из зеркала electro_balance: %d")
                        :format(sid, nick, want))
                    pushBank(ply)
                end
            end
        end)
    end)

    -- ── График сохранений ───────────────────────────────────
    timer.Create("GRM_Economy_AutoSave8s", 8, 0, function() save(true, "автосейв 8с") end)
    hook.Add("ShutDown", "GRM_Economy_Save", function() dirty = true save(true, "shutdown") end)
    timer.Create("GRM_Economy_Flush", 5, 0, function() if dirty then save(false, "флаш 5с") end end)

    -- ========================================================
    -- СВЕРКА «ПАМЯТЬ ↔ БАЗА»
    -- ========================================================
    -- Политика v3.0.1: как у валюты — ПАМЯТЬ ГЛАВНЕЕ. Файл подхватывается
    -- только если он НИЧЕГО не убивает (ручная правка админа «добавить» —
    -- ок; «воскресший» старый файл, стирающий счета, — отклоняется и
    -- мгновенно перезаписывается памятью обратно).
    local lastBark = 0
    local function reconcileEconomy(reason)
        if dirty then return false end
        if not file.Exists(DATA_FILE, "DATA") then return false end
        local txt = file.Read(DATA_FILE, "DATA") or ""
        if txt == lastDiskTxt then return false end
        local t = jsonT(txt)
        if t == nil then return false end
        local gotAcc = istable(t.accounts) and next(t.accounts) ~= nil
        local gotFac = istable(t.factions) and next(t.factions) ~= nil
        local memAcc = istable(E.Data.accounts) and next(E.Data.accounts) ~= nil
        local memFac = istable(E.Data.factions) and next(E.Data.factions) ~= nil
        if not gotAcc and not gotFac and (memAcc or memFac) then
            print("[GRM Economy] DB↔MEM ОТКЛОНЕНО: файл без счетов/фракций, а память непуста — память сохранена (антисвайп)")
            lastDiskTxt = txt
            return false
        end
        if extWasEmpty(t) and not extWasEmpty(E.Data) then
            print("[GRM Economy] DB↔MEM ОТКЛОНЕНО: внешний файл пуст по сути, память нет — память сохранена")
            lastDiskTxt = txt
            return false
        end
        -- АНТИ-ПОТЕРЯ: файл не имеет права убивать то, что уже в памяти.
        -- Если файл уменьшает/теряет чей-то счёт или бюджет фракции — он
        -- «постаревший/воскресший»: отклоняем и перезаписываем памятью.
        local loss = nil
        for sid, acc in pairs(E.Data.accounts or {}) do
            local fb = (istable(t.accounts) and istable(t.accounts[sid]))
                and tonumber(t.accounts[sid].balance) or 0
            local mb = math.floor(tonumber(istable(acc) and acc.balance) or 0)
            if mb > math.floor(fb) then
                loss = ("счёт %s: в памяти %d, в файле %d"):format(tostring(sid), mb, math.floor(fb))
                break
            end
        end
        if not loss then
            for name, e in pairs(E.Data.factions or {}) do
                local fe = istable(t.factions) and t.factions[name] or nil
                local fb = istable(fe) and tonumber(fe.budget) or 0
                local mb = math.floor(tonumber(istable(e) and e.budget) or 0)
                if mb > math.floor(fb) then
                    loss = ("бюджет [%s]: в памяти %d, в файле %d"):format(tostring(name), mb, math.floor(fb))
                    break
                end
            end
        end
        if loss then
            if os.time() - lastBark > 60 then
                lastBark = os.time()
                print("[GRM Economy][!] DB↔MEM ОТКЛОНЕНО: файл моложе памяти и стирает данные (" .. loss ..
                    ") — ПАМЯТЬ ГЛАВНЕЕ, файл перезаписан (самолечение)")
            end
            dirty = true
            save(true, "сверка: самолечение")
            return false
        end
        local oldAccounts = E.Data.accounts
        -- Снимок банков онлайн-игроков: их счёт НЕ перебиваем диском.
        -- Иначе после снятия «воскресший» treasury с БОЛЬШИМ balance
        -- поднимался сверкой (анти-потеря ловит только уменьшение) →
        -- нал уже выдан, счёт снова вырос = «умножение».
        local onlineBank = {}
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(p) and p:IsPlayer() then
                local sid = characterKeyOf(p)
                if sid ~= "" and istable(oldAccounts) and istable(oldAccounts[sid]) then
                    onlineBank[sid] = {
                        balance = math.floor(tonumber(oldAccounts[sid].balance) or 0),
                        name = tostring(oldAccounts[sid].name or p:Nick()),
                        touch = tonumber(p._grmBankTouch) or 0,
                    }
                end
            end
        end
        E.Data = t
        E.Data.version = 2
        E.Data.factions = istable(E.Data.factions) and E.Data.factions or {}
        E.Data.accounts = istable(E.Data.accounts) and E.Data.accounts or {}
        E.Data.state = istable(E.Data.state) and E.Data.state or { budget = 0, history = {} }
        E.Data.log = istable(E.Data.log) and E.Data.log or {}
        E.Data.log = fixArr(E.Data.log)
        E.Data.state.history = fixArr(E.Data.state.history)
        E.Data.config = istable(E.Data.config) and E.Data.config or {}
        if applyConfig then pcall(applyConfig) end
        for name in pairs(E.Data.factions) do entry(name) end
        -- Восстанавливаем online-счета из памяти (авторитет сессии)
        local kept, inflated = 0, 0
        local cap = math.max(0, math.floor(tonumber(GRM.MaxBalance) or 2000000000))
        for sid, mem in pairs(onlineBank) do
            local fileAcc = E.Data.accounts[sid]
            local fileBal = istable(fileAcc) and math.floor(tonumber(fileAcc.balance) or 0) or 0
            local memBal = math.Clamp(mem.balance, 0, cap)
            if fileBal > memBal then
                inflated = inflated + 1
                print(("[GRM Economy] DB↔MEM: онлайн %s — диск %d > память %d, оставляем память (анти-раздутие)")
                    :format(sid, fileBal, memBal))
            end
            E.Data.accounts[sid] = {
                balance = memBal,
                name = mem.name or (istable(fileAcc) and fileAcc.name) or "?",
            }
            kept = kept + 1
        end
        lastDiskTxt = txt
        -- Если правили online-счета — сразу материализуем правду на диск
        if inflated > 0 then
            dirty = true
            save(true, "сверка: анти-раздутие online-счетов")
        end
        local pushed = 0
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(p) and p:IsPlayer() then
                local sid = characterKeyOf(p)
                local oldBal = oldAccounts and oldAccounts[sid] and oldAccounts[sid].balance or 0
                local newBal = E.Data.accounts[sid] and E.Data.accounts[sid].balance or 0
                if oldBal ~= newBal then pushBank(p) pushed = pushed + 1 end
            end
        end
        print(("[GRM Economy] DB↔MEM [%s]: файл поднят, online-счетов сохранено: %d (анти-раздутие: %d), push: %d")
            :format(tostring(reason), kept, inflated, pushed))
        return true
    end
    timer.Create("GRM_Economy_Reconcile", 15, 0, function() reconcileEconomy("тик 15с") end)
    -- Находка 178: страховочный синк дисплеев банковских хранилищ (2с)
    timer.Create("GRM_Economy_VaultSync", 2, 0, function()
        if E.SyncVaultsState then E.SyncVaultsState() end
    end)
    concommand.Add("grm_economy_check", function(ply)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        local ok = reconcileEconomy("команда")
        print("[GRM Economy] сверка завершена: " .. (ok and "подняты изменения из базы" or "расхождений нет"))
    end)

    -- ========================================================
    -- ШТРАФЫ
    -- ========================================================
    function E.CanFine(issuer, target)
        if not IsValid(issuer) or not issuer:IsPlayer() then return true end -- система
        if issuer:IsSuperAdmin() then return true end
        if not IsValid(target) or not target:IsPlayer() then return false, "Нет цели" end
        if target == issuer then return false, "Нельзя штрафовать себя" end

        local iname, ifac = factionOf(issuer)
        if not iname then return false, "Ваша фракция не имеет доступа к системе штрафов" end
        local fp = entry(iname).finePerms
        if not fp.enabled then
            return false, "Фракция [" .. iname .. "] не имеет доступа к системе штрафов"
        end
        if not isLeaderOf(issuer, ifac) and not fp.allRoles then
            local info = memberRec(ifac, issuer) or {}
            if not fp.roles[tostring(info.Role or "")] then
                return false, "Ваша роль во фракции не имеет права штрафовать"
            end
        end
        local tname = factionOf(target)
        if tname == iname then
            if not fp.ownFaction then return false, "[" .. iname .. "] не может штрафовать своих членов" end
        elseif tname then
            if not fp.otherFactions then return false, "[" .. iname .. "] не может штрафовать другие фракции" end
        else
            if not fp.civilians then return false, "[" .. iname .. "] не может штрафовать граждан (без фракции)" end
        end
        return true
    end

    function E.FineMaxFor(ply)
        if IsValid(ply) and ply:IsPlayer() and ply:IsSuperAdmin() then return E.Config.FineMaxAmount end
        local iname = factionOf(ply)
        local fp = iname and entry(iname).finePerms
        if fp and fp.enabled and fp.maxAmount > 0 then
            return math.min(fp.maxAmount, E.Config.FineMaxAmount)
        end
        return E.Config.FineMaxAmount
    end

    function E.Fine(issuer, target, amount, reason)
        if not IsValid(target) or not target:IsPlayer() then return false, "Нет цели" end
        amount = math.floor(tonumber(amount) or 0)
        if amount <= 0 then return false, "Сумма должна быть > 0" end
        local maxFor = E.FineMaxFor and E.FineMaxFor(issuer) or E.Config.FineMaxAmount
        if amount > maxFor then amount = maxFor end
        if GRM.GetBalance(target) <= 0 then return false, "У игрока нет средств" end

        local issued = math.min(amount, GRM.GetBalance(target))
        GRM.TakeMoney(target, issued, "Штраф: " .. tostring(reason or "нарушение"))

        -- Находка 178: процент со штрафа (finePerms.statePercent) — доля,
        -- которая уходит в ГОС.БЮДЖЕТ (банковская система); остальное —
        -- в бюджет штрафующей фракции (по настройке FineToBudget).
        local receiptName = factionOf(issuer)
        local stateShare = 0
        if receiptName and E.Config.FineToBudget then
            local fp = entry(receiptName).finePerms
            local pct = math.Clamp(tonumber(fp and fp.statePercent) or 0, 0, 100)
            if pct > 0 then
                stateShare = math.floor(issued * pct / 100)
            end
            local toFac = issued - stateShare
            if toFac > 0 then
                GRM.FactionBudgetAdd(receiptName, toFac,
                    ("Штраф %s от %s: %s"):format(target:Nick(), IsValid(issuer) and issuer:Nick() or "система", money(toFac)))
            end
            if stateShare > 0 then
                stateAdd(stateShare, ("Штраф %s от %s (доля гос-ва %d%%)"):format(
                    target:Nick(), IsValid(issuer) and issuer:Nick() or "система", math.floor(pct)))
            end
        elseif E.Config.FinesToState then
            stateAdd(issued, ("Штраф %s от %s"):format(target:Nick(), IsValid(issuer) and issuer:Nick() or "система"))
        end

        notify(target,
            ("ШТРАФ: -%s | %s | от: %s"):format(money(issued), tostring(reason or "без причины"),
                IsValid(issuer) and issuer:Nick() or "система"),
            255, 80, 70)
        if IsValid(issuer) and issuer ~= target then
            local dest = " (деньги сгорают)"
            if receiptName and E.Config.FineToBudget then
                dest = " → бюджет [" .. receiptName .. "]"
                if stateShare > 0 then dest = dest .. " + " .. money(stateShare) .. " в гос. (" .. math.floor(stateShare / math.max(1, issued) * 100) .. "%)" end
            elseif E.Config.FinesToState then dest = " → гос.бюджет" end
            notify(issuer, "Штраф выписан: " .. target:Nick() .. " -" .. money(issued) .. dest, 100, 220, 100)
        end
        local tf = factionOf(target)
        if tf and tf ~= receiptName then
            addHistory(tf, ("Штраф %s (-%s) от %s"):format(target:Nick(), money(issued), IsValid(issuer) and issuer:Nick() or "?"))
        end
        hook.Run("GRM_FineIssued", issuer, target, issued, tostring(reason or ""))
        return true, issued
    end

    -- тестовая поверхность для сим-стендов (живая настройка finePerms
    -- идёт через /feco_admin; прямой доступ к записи — ТОЛЬКО для тестов)
    E._dev_entry = entry

    -- ── СИНХРОНИЗАЦИЯ клиентов ──────────────────────────────
    local function syncPlayer(ply)
        local name = factionOf(ply)
        if name then foldFactionBudget(name) end
        net.Start(NET_SYNC)
            net.WriteString(name or "")
            net.WriteTable(name and entry(name) or {})
        net.Send(ply)
    end

    hook.Add("PlayerInitialSpawn", "GRM_Economy_Sync", function(ply)
        timer.Simple(5, function()
            if IsValid(ply) then syncPlayer(ply) pushBank(ply) end
        end)
    end)

    -- ── АДМИН-ПАНЕЛЬ: данные ────────────────────────────────
    local function buildAdminData()
        local factions = {}
        if Factions then
            for name, f in pairs(Factions) do
                if istable(f) then
                    local roles, depts = {}, {}
                    if istable(f.Roles) then for _, r in ipairs(f.Roles) do roles[#roles + 1] = tostring(r) end end
                    if istable(f.Departments) then for _, dd in ipairs(f.Departments) do depts[#depts + 1] = tostring(dd) end end
                    factions[name] = {
                        entry = entry(name),
                        roles = roles,
                        departments = depts,
                        online = #onlineMembers(name, f),
                        members = f.Members and table.Count(f.Members) or 0,
                    }
                end
            end
        end
        for name in pairs(E.Data.factions) do
            if not factions[name] then
                factions[name] = { entry = entry(name), roles = {}, departments = {}, online = 0, members = 0 }
            end
        end

        local players, cashSum, bankSum = {}, 0, 0
        if GRM.GetAllBalances then players = GRM.GetAllBalances() end
        for sid, rec in pairs(players) do
            local slot = tostring(sid):match(":(char[1-3])$")
            local slotNo = slot and tonumber(slot:sub(5)) or nil
            rec.characterLabel = slotNo and ("Персонаж " .. slotNo) or "Аккаунт"
            local online = GRM.Identity and GRM.Identity.ResolveCharacter and GRM.Identity.ResolveCharacter(sid) or nil
            if IsValid(online) then
                rec.rpName = online:GetNWString("GRM_RPName", "")
                if rec.rpName == "" then rec.rpName = rec.name end
                rec.accountName = online:Nick()
            elseif slot and GRM.Char and GRM.Char.Data then
                local account, slotID = tostring(sid):match("^(.-):(char[1-3])$")
                local c = account and GRM.Char.Data[account] and GRM.Char.Data[account].slots and GRM.Char.Data[account].slots[slotID]
                rec.rpName = c and c.name or rec.name
                rec.accountName = rec.name
            else
                rec.rpName = rec.name
                rec.accountName = rec.name
            end
            cashSum = cashSum + (tonumber(rec.balance) or 0)
            local acc = E.Data.accounts[sid]
            rec.bank = acc and acc.balance or 0
            bankSum = bankSum + rec.bank
        end

        local fullcfg = table.Copy(E.Config)
        fullcfg.StartBalance = GRM.StartBalance or 1000
        fullcfg.CurrencyName = GRM.CurrencyName or "GRM"

        -- Находка 180: журнал в ВЫДАЧЕ урезаем до последних 100 записей
        -- (клиенту для вкладки «Фин.лог» больше не нужно; полный журнал
        -- живёт на сервере). Раньше слались все 300 — при большом онлайне
        -- пакет переполнялся (Trying to send an overflowed net message).
        local lg = E.Data.log or {}
        local logOut = {}
        for i = math.max(1, #lg - 99), #lg do logOut[#logOut + 1] = lg[i] end

        return {
            factions = factions,
            state = E.Data.state,
            players = players,
            log = logOut,
            config = {
                maxTax = E.Config.MaxTaxRate, minInterval = E.Config.MinSalaryInterval,
            },
            fullconfig = fullcfg,
            stats = {
                players = table.Count(players), cash = cashSum, bank = bankSum,
                factions = table.Count(E.Data.factions), logSize = #logOut,
            },
        }
    end

    -- Находка 180: отправка админ-данных ЧАНКАМИ. Один net-пакет GMod
    -- ограничен (~64 КБ): при большом онлайне/фракциях/журнале старая
    -- sendAdminData падала с «Trying to send an overflowed net message».
    -- Теперь: base (фракции/конфиги/статы) → log (последние 100) → players
    -- порциями по ECO_PLAYERS_CHUNK. Клиент собирает и строит UI по факту
    -- получения последнего чанка игроков.
    local ECO_PLAYERS_CHUNK = 40
    local function sendAdminData(ply)
        local data = buildAdminData()
        local players = data.players or {}
        local log = data.log or {}
        data.players = nil
        data.log = nil
        -- 1) база: всё кроме игроков и журнала
        net.Start(NET_ADMIN_DATA)
            net.WriteString("base")
            net.WriteTable(data)
        net.Send(ply)
        -- 2) журнал (уже ≤100)
        net.Start(NET_ADMIN_DATA)
            net.WriteString("log")
            net.WriteTable(log)
        net.Send(ply)
        -- 3) игроки чанками (players — map sid→запись; делим по ключам)
        local keys = {}
        for sid in pairs(players) do keys[#keys + 1] = sid end
        table.sort(keys)
        local total = math.max(1, math.ceil(#keys / ECO_PLAYERS_CHUNK))
        for i = 1, total do
            local part = {}
            for j = (i - 1) * ECO_PLAYERS_CHUNK + 1, math.min(i * ECO_PLAYERS_CHUNK, #keys) do
                part[keys[j]] = players[keys[j]]
            end
            net.Start(NET_ADMIN_DATA)
                net.WriteString("players")
                net.WriteUInt(i, 16)
                net.WriteUInt(total, 16)
                net.WriteTable(part)
            net.Send(ply)
        end
    end

    net.Receive(NET_OPEN_ADMIN, function(_, ply)
        if not IsValid(ply) or not E.CanManageEconomy(ply) then return end
        sendAdminData(ply)
    end)

    net.Receive(NET_ADMIN_ACT, function(_, ply)
        if not IsValid(ply) or not E.CanManageEconomy(ply) then return end
        local a = net.ReadTable() or {}
        local name = tostring(a.faction or "")
        local function amt(v) return math.max(0, math.floor(tonumber(v) or 0)) end
        local function sidArg() return tostring(a.sid or "") end

        if a.action == "save_entry" then
            if name == "" then return end
            -- Находка 177b/177c: СИСТЕМУ штрафов (включение, категории целей,
            -- роли) настраивает только суперадмин; лидер/зам/доступные могут
            -- менять лишь ЧИСЛОВОЕ значение (лимит/«процент» штрафа) — как и
            -- налоги/зарплаты. Поэтому fine-блок не отбрасывается целиком:
            -- не-суперадмин сохраняет только maxAmount.
            local e = entry(name)
            e.taxRate        = math.Clamp(tonumber(a.taxRate) or e.taxRate, 0, E.Config.MaxTaxRate)
            e.baseSalary     = math.max(0, math.floor(tonumber(a.baseSalary) or 0))
            e.salaryInterval = math.max(E.Config.MinSalaryInterval, math.floor(tonumber(a.salaryInterval) or e.salaryInterval))
            e.payFromBudget  = a.payFromBudget == true
            if istable(a.roles) then
                e.roleSalaries = {}
                for k, v in pairs(a.roles) do e.roleSalaries[tostring(k)] = math.max(0, math.floor(tonumber(v) or 0)) end
            end
            if istable(a.departments) then
                e.departmentSalaries = {}
                for k, v in pairs(a.departments) do e.departmentSalaries[tostring(k)] = math.max(0, math.floor(tonumber(v) or 0)) end
            end
            if istable(a.fine) then
                local fp = e.finePerms
                if ply:IsSuperAdmin() then
                    fp.enabled       = a.fine.enabled == true
                    fp.allRoles      = a.fine.allRoles == true
                    fp.ownFaction    = a.fine.ownFaction ~= false
                    fp.otherFactions = a.fine.otherFactions == true
                    fp.civilians     = a.fine.civilians ~= false
                    if istable(a.fine.roles) then
                        fp.roles = {}
                        for k, v in pairs(a.fine.roles) do if v == true then fp.roles[tostring(k)] = true end end
                    end
                end
                -- Находка 178: числа (лимит суммы и ПРОЦЕНТ со штрафа в гос.)
                -- могут менять все с доступом к экономике; система — суперадмин.
                fp.maxAmount = math.max(0, math.floor(tonumber(a.fine.maxAmount) or fp.maxAmount))
                fp.statePercent = math.Clamp(math.floor(tonumber(a.fine.statePercent) or (fp.statePercent or 0)), 0, 100)
            end
            dirty = true
            save(true, "админ: настройки фракции")
            addHistory(name, "Настройки обновлены админом " .. ply:Nick())
            addLog("Админ " .. ply:Nick() .. " обновил настройки [" .. name .. "]")
            notify(ply, "Фракция [" .. name .. "] сохранена.", 100, 220, 100)

        elseif a.action == "budget_give" or a.action == "budget_take" then
            if name == "" then return end
            local v = amt(a.amount)
            if a.action == "budget_take" then v = -math.min(v, entry(name).budget) end
            if v ~= 0 then
                GRM.FactionBudgetAdd(name, v, ("Админ %s: %s%s"):format(ply:Nick(), v > 0 and "+" or "", money(math.abs(v))))
                notify(ply, "Бюджет [" .. name .. "]: " .. money(entry(name).budget), 100, 220, 255)
            end

        elseif a.action == "pay_now" then
            if name == "" then return end
            entry(name).nextPay = os.time()
            notify(ply, "Принудительная выплата запрошена для [" .. name .. "].", 255, 200, 80)

        -- ── ГОС.БЮДЖЕТ ──────────────────────────────────────
        elseif a.action == "save_now" then
            dirty = true save(true, "админ: сохранить сейчас")
            notify(ply, "Данные экономики сохранены на диск.", 100, 220, 100)
        elseif a.action == "state_give" then
            local v = amt(a.amount)
            if v <= 0 then return end
            stateAdd(v, ("Админ %s пополнил гос.бюджет: +%s"):format(ply:Nick(), money(v)))
            -- Находка 178: деньги физически дропаются в хранилище (паллеты)
            if E.DropCashToVault then E.DropCashToVault(ply, v) end
            notify(ply, "Гос.бюджет: " .. money(E.Data.state.budget), 235, 180, 60)
        elseif a.action == "state_take" then
            local v = math.min(amt(a.amount), E.Data.state.budget)
            if v <= 0 then return end
            stateAdd(-v, ("Админ %s изъял из гос.бюджета: -%s"):format(ply:Nick(), money(v)))
            -- Находка 178: изъятые деньги дропаются в хранилище (их можно подобрать)
            if E.DropCashToVault then E.DropCashToVault(ply, v) end
            notify(ply, "Гос.бюджет: " .. money(E.Data.state.budget), 235, 180, 60)
        elseif a.action == "state_set" then
            E.Data.state.budget = amt(a.amount)
            dirty = true
            stateHist("Админ " .. ply:Nick() .. " установил гос.бюджет: " .. money(E.Data.state.budget))
            if E.SyncVaultsState then E.SyncVaultsState() end
            notify(ply, "Гос.бюджет: " .. money(E.Data.state.budget), 235, 180, 60)
        elseif a.action == "state_to_faction" then
            if name == "" then return end
            local v = amt(a.amount)
            if v <= 0 then return end
            if E.Data.state.budget < v then notify(ply, "В гос.бюджете только: " .. money(E.Data.state.budget), 255, 100, 100) return end
            stateAdd(-v, ("Перечислено фракции [%s] (админ %s)"):format(name, ply:Nick()))
            GRM.FactionBudgetAdd(name, v, "Трансфер из гос.бюджета: " .. money(v))
            notify(ply, ("В [%s] перечислено %s из гос.бюджета"):format(name, money(v)), 100, 220, 100)
        elseif a.action == "state_pay" then
            local sid, v = sidArg(), amt(a.amount)
            if sid == "" or v <= 0 then return end
            if E.Data.state.budget < v then notify(ply, "В гос.бюджете только: " .. money(E.Data.state.budget), 255, 100, 100) return end
            stateAdd(-v, ("Выплата игроку %s (админ %s)"):format(sid, ply:Nick()))
            GRM.GiveMoney(sid, v, "Выплата из гос.бюджета")
            for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                if IsValid(p) and characterKeyOf(p) == sid then
                    notify(p, "Вам выплачено из гос.бюджета: " .. money(v), 100, 220, 100)
                    break
                end
            end
            notify(ply, "Выплачено " .. money(v) .. " игроку " .. sid, 100, 220, 100)

        -- ── ИГРОКИ: балансы наличных и счетов ───────────────
        -- Находка 177b: изменение балансов игроков — ТОЛЬКО суперадмин
        -- (лидер/зам с доступом к экономике управляют бюджетом, а не
        -- чужими деньгами).
        elseif a.action == "player_give" or a.action == "player_take" or a.action == "player_set" then
            if not ply:IsSuperAdmin() then return end
            local sid, v = sidArg(), amt(a.amount)
            if sid == "" then return end
            if a.action == "player_give" then
                GRM.GiveMoney(sid, v, "Админ " .. ply:Nick() .. ": выдача")
            elseif a.action == "player_take" then
                GRM.TakeMoney(sid, v, "Админ " .. ply:Nick() .. ": изъятие")
            else
                GRM.SetBalance(sid, v, "Админ " .. ply:Nick() .. ": установка баланса")
            end
            local rec = GRM.GetAllBalances and GRM.GetAllBalances()[sid]
            notify(ply, "Баланс обновлён: " .. money(rec and rec.balance or 0), 100, 220, 100)
        elseif a.action == "player_bank_set" then
            if not ply:IsSuperAdmin() then return end
            local sid, v = sidArg(), amt(a.amount)
            if sid == "" then return end
            local acc = account(sid)
            acc.balance = math.Clamp(v, 0, math.max(0, math.floor(tonumber(GRM.MaxBalance) or 2000000000))) -- жёсткие рамки
            dirty = true save(true, "админ: счёт игрока")
            pushBankBySid(sid)
            addLog(("Админ %s установил банковский счёт %s: %s"):format(ply:Nick(), sid, money(v)))
            notify(ply, "Банковский счёт установлен: " .. money(v), 100, 220, 100)

        -- ── ОБЩИЕ НАСТРОЙКИ ─────────────────────────────────
        elseif a.action == "config_save" and istable(a.config) then
            -- Находка 177b: глобальные настройки — только суперадмин.
            if not ply:IsSuperAdmin() then return end
            local c = a.config
            local out = istable(E.Data.config) and E.Data.config or {}
            local function num(key, mn, mx)
                local v = tonumber(c[key])
                if v then out[key] = math.Clamp(math.floor(v * 1000 + 0.5) / 1000, mn, mx) end
            end
            num("DefaultTaxRate", 0, 1)
            num("MaxTaxRate", 0.01, 1)
            num("SalaryInterval", 30, 86400)
            num("MinSalaryInterval", 10, 3600)
            num("HistorySize", 10, 500)
            num("LogSize", 50, 2000)
            num("FineMaxAmount", 100, 100000000)
            num("UseDistance", 50, 1000)
            num("StartBalance", 0, 100000000)
            for _, key in ipairs({ "PayFromBudget", "FineToBudget", "TaxToState", "FinesToState" }) do
                if c[key] ~= nil then out[key] = c[key] == true end
            end
            if isstring(c.CurrencyName) and c.CurrencyName ~= "" then
                out.CurrencyName = string.Left(c.CurrencyName, 16)
            end
            if isstring(c.BankTerminalModel) and string.StartWith(c.BankTerminalModel, "models/")
                and not string.find(c.BankTerminalModel, "..", 1, true) then
                out.BankTerminalModel = string.Left(c.BankTerminalModel, 128)
            end
            E.Data.config = out
            applyConfig()
            dirty = true save(true, "админ: общие настройки")
            addLog("Админ " .. ply:Nick() .. " обновил общие настройки экономики")
            notify(ply, "Настройки экономики сохранены.", 100, 220, 100)
        end

        sendAdminData(ply)
        timer.Simple(0.5, function() for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do if IsValid(p) then syncPlayer(p) end end end)
    end)

    -- ========================================================
    -- БАНКОМАТ (окно взаимодействия с терминалом)
    -- ========================================================
    function E.OpenBankTerminal(ply, ent)
        if not IsValid(ply) or not IsValid(ent) then return end
        if ply:GetPos():DistToSqr(ent:GetPos()) > (E.Config.UseDistance ^ 2) * 4 then return end
        local name = factionOf(ply)
        local players = {}
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(p) and p ~= ply then
                players[#players + 1] = { nick = p:Nick(), sid64 = characterKeyOf(p), characterKey = characterKeyOf(p) }
            end
        end
        net.Start(NET_OPEN_BANK)
            net.WriteEntity(ent)
            net.WriteTable({
                balance = GRM.GetBalance(ply),
                bank = E.BankBalance(ply),
                faction = name or "",
                factionData = name and entry(name) or nil,
                mySalary = select(1, E.GetSalaryFor(ply)),
                leader = name and isLeaderOf(ply, Factions[name]) or false,
                players = players,
            })
        net.Send(ply)
    end

    net.Receive(NET_BANK_ACT, function(_, ply)
        if not IsValid(ply) then return end
        local a = net.ReadTable() or {}
        local name = factionOf(ply)
        local f = name and Factions[name]
        local amt = math.max(0, math.floor(tonumber(a.amount) or 0))

        if a.type == "bank_deposit" then
            if amt <= 0 then return end
            -- потолок разумной операции за клик (анти-мусор net)
            if amt > 2000000000 then return end
            local ok, newbal = E.BankDeposit(ply, amt)
            if not ok then
                local why = newbal -- second return is error tag when false
                if why == "cd" then notify(ply, "Слишком быстро. Подождите долю секунды.", 255, 180, 80)
                else notify(ply, "Недостаточно наличных.", 255, 100, 100) end
                return
            end
            notify(ply, ("Внесено на счёт: %s (счёт: %s)"):format(money(amt), money(newbal)), 100, 220, 100)
            -- Код 126 (Инкассация): терминал получает комиссию в инкасс-ячейку
            local termEnt = a.ent
            hook.Run("GRM_Incass_TerminalDeposit", ply, amt, IsValid(termEnt) and termEnt or nil)
        elseif a.type == "bank_withdraw" then
            if amt <= 0 then return end
            if amt > 2000000000 then return end
            local ok, newbal = E.BankWithdraw(ply, amt)
            if not ok then
                if newbal == "cd" then notify(ply, "Слишком быстро. Подождите долю секунды.", 255, 180, 80)
                else notify(ply, "На счёте только: " .. money(E.BankBalance(ply)), 255, 100, 100) end
                return
            end
            notify(ply, ("Снято со счёта: %s (остаток: %s)"):format(money(amt), money(newbal)), 100, 220, 100)
        elseif a.type == "bank_transfer" then
            if amt <= 0 then return end
            local toSid = tostring(a.to or "")
            local ok = E.BankTransfer(ply, toSid, amt)
            if not ok then notify(ply, "Перевод не выполнен: недостаточно средств на счёте.", 255, 100, 100) return end
            local target
            for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                if IsValid(p) and characterKeyOf(p) == toSid then target = p break end
            end
            notify(ply, ("Переведено %s → %s"):format(money(amt), IsValid(target) and target:Nick() or toSid), 255, 180, 80)
            if IsValid(target) then
                notify(target, "На ваш счёт поступило " .. money(amt) .. " от " .. ply:Nick(), 100, 220, 100)
                pushBank(target)
            end
        elseif a.type == "deposit" then
            if not name then notify(ply, "Вы не во фракции.", 255, 100, 100) return end
            if amt <= 0 then return end
            if not GRM.HasMoney(ply, amt) then notify(ply, "Недостаточно средств.", 255, 100, 100) return end
            GRM.TakeMoney(ply, amt)
            GRM.FactionBudgetAdd(name, amt, ("Взнос %s: %s"):format(ply:Nick(), money(amt)))
            notify(ply, "Внесено в бюджет: " .. money(amt), 100, 220, 100)
        elseif a.type == "withdraw" then
            if not name then notify(ply, "Вы не во фракции.", 255, 100, 100) return end
            if not isLeaderOf(ply, f) then notify(ply, "Только лидер может снимать со счёта фракции.", 255, 100, 100) return end
            if amt <= 0 then return end
            local e = entry(name)
            if e.budget < amt then notify(ply, "В бюджете только: " .. money(e.budget), 255, 100, 100) return end
            GRM.FactionBudgetAdd(name, -amt, ("Лидер %s снял %s"):format(ply:Nick(), money(amt)))
            GRM.GiveMoney(ply, amt)
            notify(ply, "Снято из бюджета: " .. money(amt), 100, 220, 100)
        elseif a.type == "transfer" then
            if amt <= 0 then return end
            local target
            for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                if IsValid(p) and characterKeyOf(p) == tostring(a.to or "") then target = p break end
            end
            if not IsValid(target) then notify(ply, "Получатель не в сети.", 255, 100, 100) return end
            if not GRM.HasMoney(ply, amt) then notify(ply, "Недостаточно средств.", 255, 100, 100) return end
            GRM.TakeMoney(ply, amt)
            GRM.GiveMoney(target, amt)
            notify(ply, "Переведено " .. money(amt) .. " → " .. target:Nick(), 255, 180, 80)
            notify(target, "Получено " .. money(amt) .. " от " .. ply:Nick(), 100, 220, 100)
        end
        syncPlayer(ply)
        pushBank(ply)
    end)

    -- ========================================================
    -- ЧАТ-КОМАНДЫ
    -- ========================================================
    hook.Add("PlayerSay", "GRM_Economy_Chat", function(ply, text)
        local args = string.Explode(" ", string.Trim(text or ""))
        local cmd = string.lower(args[1] or "")

        if cmd == "/feco_admin" or cmd == "!feco_admin" or cmd == "/salary_admin" or cmd == "!salary_admin" then
            if ply:IsSuperAdmin() then net.Start(NET_OPEN_ADMIN) net.Send(ply) end
            return ""
        end

        if cmd == "/mysalary" or cmd == "!mysalary" then
            local gross, name = E.GetSalaryFor(ply)
            if not name then notify(ply, "Вы не во фракции.", 255, 100, 100) return "" end
            local e = entry(name)
            notify(ply, ("Ваша ЗП: %s | налог %d%% | интервал %dс | из бюджета: %s"):format(
                money(gross), math.floor(taxRateFor(ply, name) * 100), e.salaryInterval, e.payFromBudget and "да" or "нет"), 100, 220, 255)
            return ""
        end

        if cmd == "!fbudget" or cmd == "/fbudget" then
            local name = factionOf(ply)
            if not name then notify(ply, "Вы не во фракции.", 255, 100, 100) return "" end
            local e = entry(name)
            notify(ply, ("[%s] Бюджет: %s | Налог: %d%% | База ЗП: %s"):format(
                name, money(e.budget), math.floor(e.taxRate * 100), money(e.baseSalary)), 100, 220, 255)
            return ""
        end

        if cmd == "!fpay" or cmd == "/fpay" then
            local name = factionOf(ply)
            local amt = math.floor(tonumber(args[2]) or 0)
            if not name or amt <= 0 then return "" end
            if not GRM.HasMoney(ply, amt) then notify(ply, "Недостаточно средств.", 255, 100, 100) return "" end
            GRM.TakeMoney(ply, amt)
            GRM.FactionBudgetAdd(name, amt, ("Взнос %s: %s"):format(ply:Nick(), money(amt)))
            notify(ply, "Внесено в бюджет: " .. money(amt), 100, 220, 100)
            syncPlayer(ply)
            return ""
        end

        if cmd == "!fwithdraw" or cmd == "/fwithdraw" then
            local name, f = factionOf(ply)
            local amt = math.floor(tonumber(args[2]) or 0)
            if not name or amt <= 0 then return "" end
            if not isLeaderOf(ply, f) then notify(ply, "Только лидер фракции.", 255, 100, 100) return "" end
            local e = entry(name)
            if e.budget < amt then notify(ply, "В бюджете только: " .. money(e.budget), 255, 100, 100) return "" end
            GRM.FactionBudgetAdd(name, -amt, ("Лидер %s снял %s"):format(ply:Nick(), money(amt)))
            GRM.GiveMoney(ply, amt)
            notify(ply, "Выведено из бюджета: " .. money(amt), 100, 220, 100)
            syncPlayer(ply)
            return ""
        end

        if cmd == "!fpayall" or cmd == "/fpayall" then
            local name, f = factionOf(ply)
            local amt = math.floor(tonumber(args[2]) or 0)
            if not name or amt <= 0 then return "" end
            if not isLeaderOf(ply, f) then notify(ply, "Только лидер фракции.", 255, 100, 100) return "" end
            local members = onlineMembers(name, f)
            local e = entry(name)
            local total = amt * #members
            if e.budget < total then
                notify(ply, "Не хватает бюджета: нужно " .. money(total) .. ", есть " .. money(e.budget), 255, 100, 100)
                return ""
            end
            GRM.FactionBudgetAdd(name, -total, ("Лидер %s выплатил %s × %d"):format(ply:Nick(), money(amt), #members))
            for _, p in ipairs(members) do
                GRM.GiveMoney(p, amt)
                notify(p, "Премия от фракции [" .. name .. "]: " .. money(amt), 100, 200, 255)
            end
            notify(ply, "Выплачено " .. money(amt) .. " × " .. #members .. " (итого " .. money(total) .. ")", 100, 220, 100)
            syncPlayer(ply)
            return ""
        end

        if cmd == "!fsettax" or cmd == "/fsettax" then
            local name, f = factionOf(ply)
            local pct = tonumber(args[2])
            if not name or not pct then return "" end
            if not isLeaderOf(ply, f) then notify(ply, "Только лидер фракции.", 255, 100, 100) return "" end
            GRM.FactionTaxSet(name, pct / 100)
            notify(ply, ("[%s] Налог установлен: %d%%"):format(name, math.floor(GRM.FactionTaxGet(name) * 100)), 100, 220, 100)
            addHistory(name, ("Лидер %s установил налог %d%%"):format(ply:Nick(), math.floor(GRM.FactionTaxGet(name) * 100)))
            syncPlayer(ply)
            return ""
        end

        if cmd == "/fine" or cmd == "!fine" then
            local amt = math.floor(tonumber(args[2]) or 0)
            if amt <= 0 then notify(ply, "/fine <сумма> [причина] — цель в прицеле, или /fine <сумма> <ник> [причина]", 255, 100, 100) return "" end
            -- цель №1: по нику (часть ника, единственное совпадение)
            local target, reason = nil, ""
            local tail = string.Trim(table.concat(args, " ", 3))
            if tail ~= "" then
                local low = string.lower(tail)
                local matches = {}
                for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                    if IsValid(p) and p ~= ply and string.find(string.lower(p:Nick()), low, 1, true) then
                        matches[#matches + 1] = p
                    end
                end
                if #matches == 1 then
                    target = matches[1]
                end
            end
            -- цель №2: игрок в прицеле (остаток строки — причина)
            if not IsValid(target) then
                reason = tail
                local tr = ply:GetEyeTrace()
                target = tr.Entity
                if not (IsValid(target) and target:IsPlayer() and target:GetPos():DistToSqr(ply:GetPos()) <= 250 * 250) then
                    notify(ply, "Смотрите на игрока (до 250 юнитов) или укажите ник: /fine <сумма> <ник> [причина]", 255, 100, 100)
                    return ""
                end
                if target == ply then
                    notify(ply, "Нельзя штрафовать себя.", 255, 100, 100)
                    return ""
                end
            end
            local ok, why = E.CanFine(ply, target)
            if not ok then notify(ply, why or "Нет доступа к системе штрафов.", 255, 100, 100) return "" end
            local okFine, issued = E.Fine(ply, target, amt, reason ~= "" and reason or "нарушение")
            if not okFine and issued then notify(ply, tostring(issued), 255, 100, 100) end
            return ""
        end

        if cmd == "/fines" or cmd == "!fines" then
            -- статус моих полномочий и последние штрафы фракции
            if ply:IsSuperAdmin() then
                notify(ply, "Суперадмин: штрафовать можете любого, лимит " .. money(E.Config.FineMaxAmount) .. ". Настройка доступов фракций: /feco_admin → вкладка фракции → «Штрафы»", 120, 200, 255)
                return ""
            end
            local iname, ifac = factionOf(ply)
            if not iname then notify(ply, "Вы не во фракции — система штрафов недоступна.", 255, 140, 100) return "" end
            local fp = entry(iname).finePerms
            if not fp.enabled then
                notify(ply, "Фракция [" .. iname .. "] не имеет доступа к системе штрафов (включить: /feco_admin суперадмином).", 255, 140, 100)
                return ""
            end
            local mine = {}
            for _, h in ipairs(istable(entry(iname).history) and entry(iname).history or {}) do
                if isstring(h.s) and string.find(h.s, "Штраф", 1, true) then mine[#mine + 1] = os.date("%d.%m %H:%M ", h.t or 0) .. h.s end
            end
            local lines = {
                ("Доступ штрафов [%s]: %s | лимит вашего штрафа: %s"):format(
                    iname,
                    (fp.allRoles and "все роли" or "по ролям") .. (isLeaderOf(ply, ifac) and " (вы лидер — без ограничений)" or ""),
                    money(E.FineMaxFor(ply))),
                "Цели: свои=" .. tostring(fp.ownFaction) .. ", другие фракции=" .. tostring(fp.otherFactions) .. ", граждане=" .. tostring(fp.civilians),
                "Недавние штрафы фракции: " .. (#mine > 0 and "" or "(пусто)"),
            }
            for i = math.max(1, #mine - 4), #mine do lines[#lines + 1] = "  " .. mine[i] end
            for _, ln in ipairs(lines) do ply:PrintMessage(HUD_PRINTTALK, "[Штрафы] " .. ln) end
            notify(ply, "Статус системы штрафов — в чате.", 120, 200, 255)
            return ""
        end
    end)

    hook.Add("PlayerSay", "GRM_Economy_DBCheck", function(ply, text)
        local cmd = string.lower(string.Trim(text or ""))
        if cmd ~= "/dbcheck" and cmd ~= "!dbcheck" then return end
        if not ply:IsSuperAdmin() then
            GRM.Notify(ply, "Только для superadmin.", 255, 100, 100)
            return ""
        end
        local changedEco = reconcileEconomy("чат /dbcheck")
        GRM.Notify(ply, changedEco
            and "Сверка экономики: данные подняты из базы"
            or  "Сверка экономики: расхождений с базой нет",
            100, 220, changedEco and 100 or 255)
        return ""
    end)

    hook.Add("GRM_Economy_DBCheck", "GRM_Economy_DBCheckHook", function()
        return reconcileEconomy("команда")
    end)

    concommand.Add("grm_economy", function(ply, _, cargs)
        if IsValid(ply) and not ply:IsSuperAdmin() then return end
        local mode = tostring(cargs[1] or "")
        if mode == "save" then dirty = true save(true, "команда grm_economy save") print("[GRM Economy] сохранено.")
        elseif mode == "list" then
            print("[GRM Economy] фракций с экономикой: " .. table.Count(E.Data.factions))
            for name in pairs(E.Data.factions) do
                local e = entry(name)
                print(string.format("  [%s] бюджет %s, налог %d%%, ЗП база %s, интервал %ds",
                    name, money(e.budget), math.floor(e.taxRate * 100), money(e.baseSalary), e.salaryInterval))
            end
        elseif mode == "state" then
            print("[GRM Economy] гос.бюджет: " .. money(E.Data.state.budget))
        elseif mode == "accounts" then
            print("[GRM Economy] банковских счетов: " .. table.Count(E.Data.accounts))
        else
            print("[GRM Economy] grm_economy <save|list|state|accounts>")
        end
    end)

    -- ========================================================
    -- СТАРТ
    -- ========================================================
    load()
    if SetGlobalDouble and E.Data and E.Data.state then
        SetGlobalDouble("GRM_StateBudget", tonumber(E.Data.state.budget) or 0)
        SetGlobalDouble("GRM_CityBudget", tonumber(E.Data.state.budget) or 0)
    end
    local function foldAllFactionBudgets()
        if not istable(Factions) then return end
        for name, f in pairs(Factions) do
            if istable(f) then foldFactionBudget(name) end
        end
    end
    hook.Add("InitPostEntity", "GRM_Economy_MirrorFactionBudgets", function()
        timer.Simple(1, foldAllFactionBudgets)
        timer.Simple(5, foldAllFactionBudgets)
    end)
    hook.Add("GRM_FactionUIRefreshed", "GRM_Economy_FoldOnFactionSync", function() end)
    -- После загрузки/рассылки организаций казна могла появиться только в f.Budget.
    timer.Create("GRM_Economy_FoldFactionBudgets", 8, 0, foldAllFactionBudgets)
    hook.Add("GRM_FactionRenamed", "GRM_Economy_RenameKey", function(oldName, newName)
        oldName, newName = tostring(oldName or ""), tostring(newName or "")
        if oldName == "" or newName == "" or oldName == newName then return end
        if istable(E.Data.factions) and istable(E.Data.factions[oldName]) then
            if not E.Data.factions[newName] then
                E.Data.factions[newName] = E.Data.factions[oldName]
            else
                local a, b = E.Data.factions[newName], E.Data.factions[oldName]
                a.budget = math.max(tonumber(a.budget) or 0, tonumber(b.budget) or 0)
            end
            E.Data.factions[oldName] = nil
            dirty = true
        end
    end)
    lastDiskTxt = file.Exists(DATA_FILE, "DATA") and (file.Read(DATA_FILE, "DATA") or "") or nil
    print(("[GRM Economy] Unified Economy v3.0.2 (переписано с нуля) загружена (путь: %s, база: data/%s): фракций %d, счетов %d"):format(
        tostring(debug.getinfo(1, "S").short_src), DATA_FILE,
        table.Count(E.Data.factions), table.Count(E.Data.accounts)))
end

if CLIENT then
    E.Local = E.Local or { faction = "", data = {} }

    function GRM.StateBudgetGet()
        return GetGlobalDouble and GetGlobalDouble("GRM_StateBudget", 0) or 0
    end

    surface.CreateFont("GRM_Eco_Title",  { font = "Roboto", size = 19, weight = 800, extended = true })
    surface.CreateFont("GRM_Eco_Normal", { font = "Roboto", size = 14, weight = 500, extended = true })
    surface.CreateFont("GRM_Eco_Small",  { font = "Roboto", size = 12, weight = 400, extended = true })
    surface.CreateFont("GRMFac_Title",   { font = "Roboto", size = 20, weight = 800, extended = true })
    surface.CreateFont("GRMFac_Sub",     { font = "Roboto", size = 15, weight = 700, extended = true })
    surface.CreateFont("GRMFac_Normal",  { font = "Roboto", size = 13, weight = 500, extended = true })
    surface.CreateFont("GRMFac_Small",   { font = "Roboto", size = 11, weight = 400, extended = true })
    surface.CreateFont("GRMFac_Btn",     { font = "Roboto", size = 13, weight = 600, extended = true })
    surface.CreateFont("GRMFac_StatVal", { font = "Roboto", size = 22, weight = 800, extended = true })

    local C = {
        bg         = Color(16, 20, 28, 252),
        sidebar    = Color(12, 15, 22, 255),
        card       = Color(22, 28, 38, 240),
        cardLight  = Color(28, 36, 48, 240),
        cardHover  = Color(36, 46, 62, 240),
        border     = Color(38, 48, 66, 200),
        borderLight= Color(55, 68, 92, 200),
        accent     = Color(65, 145, 235),
        accentHover= Color(85, 165, 255),
        gold       = Color(245, 195, 65),
        green      = Color(55, 185, 110),
        greenHover = Color(70, 210, 125),
        red        = Color(225, 70, 70),
        redHover   = Color(245, 90, 90),
        text       = Color(240, 244, 250),
        dim        = Color(155, 170, 190),
    }
    local CUI = C
    CUI.panel = C.card
    CUI.yellow = C.gold

    local function money(n) return GRM and GRM.Format and GRM.Format(n) or (tostring(n) .. " GRM") end

    local function frame(title, w, h)
        local f = vgui.Create("DFrame")
        f:SetTitle("") f:SetSize(w, h) f:Center() f:MakePopup()
        -- GRM-FIX: движковый крестик (скин) невидим на тёмной шапке —
        -- прячем его и рисуем свой, контрастный.
        f:ShowCloseButton(false)
        f.Paint = function(_, pw, ph)
            draw.RoundedBox(8, 0, 0, pw, ph, C.bg)
            draw.RoundedBox(8, 0, 0, pw, 46, C.sidebar)
            surface.SetDrawColor(C.border)
            surface.DrawOutlinedRect(0, 0, pw, ph)
            draw.SimpleText(title, "GRMFac_Title", 18, 23, C.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        local bx = vgui.Create("DButton", f)
        bx:SetText("") bx:SetPos(w - 44, 8) bx:SetSize(34, 30)
        bx:SetTooltip("Закрыть")
        bx.DoClick = function() f:Close() end
        bx.Paint = function(_, pw, ph)
            draw.RoundedBox(4, 0, 0, pw, ph, _:IsHovered() and Color(196, 62, 62) or Color(46, 56, 74))
            surface.SetDrawColor(240, 242, 246)
            surface.DrawLine(9, 7, pw - 9, ph - 7)
            surface.DrawLine(9, ph - 7, pw - 9, 7)
        end
        -- помечаем как хром окна: пересборка содержимого (buildAdminUI)
        -- НЕ должна удалять крестик
        bx._grmChrome = true
        return f
    end

    local function btn(p, t, c, w, h)
        local x = vgui.Create("DButton", p)
        x:SetText(t) x:SetFont("GRM_Eco_Normal") x:SetTextColor(color_white)
        if w then x:SetWide(w) end if h then x:SetTall(h) end
        x.Paint = function(s, pw, ph)
            local col = not s:IsEnabled() and Color(70, 75, 84)
                or (s:IsHovered() and Color(math.min(c.r + 20, 255), math.min(c.g + 20, 255), math.min(c.b + 20, 255)) or c)
            draw.RoundedBox(5, 0, 0, pw, ph, col)
        end
        return x
    end

    -- ── Синк собственной фракции ────────────────────────────
    net.Receive(NET_SYNC, function()
        E.Local = { faction = net.ReadString(), data = net.ReadTable() or {} }
        hook.Run("GRM_EconomySynced", E.Local.faction, E.Local.data)
    end)

    -- Банковский счёт для HUD (Код 48): GRM.PlayerBank — живое значение
    net.Receive("GRM_Bank_Sync", function()
        GRM.PlayerBank = net.ReadDouble() or 0 -- v2.3.7: парно к WriteDouble на сервере
        hook.Run("GRM_BankBalanceUpdated", GRM.PlayerBank)
    end)

    net.Receive(NET_INFO, function()
        chat.AddText(Color(120, 220, 120), "[Экономика] ", color_white, net.ReadString())
    end)

    -- ── ЕДИНАЯ АДМИН-ПАНЕЛЬ ЭКОНОМИКИ (обновляется НА МЕСТЕ) ──
    local adminFrame = nil

    local function act(t)
        net.Start(NET_ADMIN_ACT)
            net.WriteTable(t)
        net.SendToServer()
    end

    local function buildAdminUI(d, parentTabs)
        local isSuper = IsValid(LocalPlayer()) and LocalPlayer():IsSuperAdmin() == true
        local host
        if IsValid(parentTabs) then
            host = parentTabs
            if GRM.UI and GRM.UI.SafeClear then GRM.UI.SafeClear(host) else host:Clear() end
        else
            if not IsValid(adminFrame) then return end
            for _, ch in ipairs(adminFrame:GetChildren()) do
                if ch ~= adminFrame.btnClose and ch ~= adminFrame.btnMaxim
                    and ch ~= adminFrame.btnMinim and ch ~= adminFrame.lblTitle
                    and ch ~= adminFrame.imgIcon and not ch._grmChrome then
                    ch:Remove()
                end
            end
            host = adminFrame
        end

        local lastTab = host._tabName or "overview"
        local body = vgui.Create("DPanel", host)
        body:Dock(FILL)
        body:DockMargin(IsValid(parentTabs) and 0 or 0, IsValid(parentTabs) and 0 or 46, 0, 0)
        body:SetPaintBackground(false)

        local sidebar = vgui.Create("DPanel", body)
        sidebar:Dock(LEFT)
        sidebar:SetWide(214)
        sidebar.Paint = function(_, w, h)
            draw.RoundedBoxEx(0, 0, 0, w, h, C.sidebar, false, false, true, false)
            surface.SetDrawColor(C.border.r, C.border.g, C.border.b, 80)
            surface.DrawLine(w - 1, 0, w - 1, h)
        end

        local content = vgui.Create("DPanel", body)
        content:Dock(FILL)
        content:DockMargin(12, 10, 12, 10)
        content:SetPaintBackground(false)

        local function moneyFmt(n) return money(n) end
        local function mkBtn(parent, text, col, hoverCol, doClick)
            local b = vgui.Create("DButton", parent)
            b:SetText("")
            b:SetCursor("hand")
            b.Paint = function(s, w, h)
                local isHov, isDown, isDis = s:IsHovered(), s:IsDown(), not s:IsEnabled()
                local bgCol = col or C.accent
                if isDis then bgCol = Color(34, 40, 52)
                elseif isDown then bgCol = Color(math.max(bgCol.r - 30, 0), math.max(bgCol.g - 30, 0), math.max(bgCol.b - 30, 0))
                elseif isHov then bgCol = hoverCol or C.accentHover end
                draw.RoundedBox(5, 0, isDown and 1 or 0, w, h - (isDown and 1 or 0), bgCol)
                draw.SimpleText(text, "GRMFac_Btn", w / 2, h / 2 + (isDown and 1 or 0), isDis and C.dim or color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            b.DoClick = function()
                surface.PlaySound("ui/buttonclick.wav")
                if doClick then doClick() end
            end
            return b
        end

        local function skinEntry(te)
            if not IsValid(te) then return te end
            te:SetFont("GRMFac_Normal")
            te:SetTextColor(C.text)
            te.Paint = function(s, w, h)
                draw.RoundedBox(4, 0, 0, w, h, Color(24, 30, 40, 245))
                surface.SetDrawColor(C.border)
                surface.DrawOutlinedRect(0, 0, w, h)
                s:DrawTextEntryText(C.text, C.accent, C.text)
            end
            return te
        end

        local function skinCombo(cb)
            if not IsValid(cb) then return cb end
            cb:SetFont("GRMFac_Normal")
            cb:SetTextColor(C.text)
            cb.Paint = function(s, w, h)
                draw.RoundedBox(4, 0, 0, w, h, s:IsHovered() and Color(30, 38, 52, 245) or Color(24, 30, 40, 245))
                surface.SetDrawColor(C.border)
                surface.DrawOutlinedRect(0, 0, w, h)
            end
            return cb
        end

        local function skinListView(lv)
            if not IsValid(lv) then return end
            lv:SetPaintBackground(false)
            lv:SetDataHeight(26)
            lv:SetHeaderHeight(30)
            lv.Paint = function(_, w, h)
                draw.RoundedBox(6, 0, 0, w, h, C.card)
                surface.SetDrawColor(C.border)
                surface.DrawOutlinedRect(0, 0, w, h)
            end
            if lv.Columns then
                for _, col in ipairs(lv.Columns) do
                    if col.Header then
                        col.Header:SetFont("GRMFac_Btn")
                        col.Header:SetTextColor(C.gold)
                        col.Header.Paint = function(s, w, h)
                            draw.RoundedBox(0, 0, 0, w, h, Color(28, 35, 48))
                        end
                    end
                end
            end
        end

        local function skinLine(line)
            if not IsValid(line) then return end
            for _, col in pairs(line.Columns or {}) do
                if IsValid(col) then
                    col:SetFont("GRMFac_Normal")
                    col:SetTextColor(C.text)
                end
            end
            line.Paint = function(s, w, h)
                if s:IsLineSelected() then
                    draw.RoundedBox(4, 0, 0, w, h, Color(40, 62, 96, 240))
                elseif s.Hovered then
                    draw.RoundedBox(4, 0, 0, w, h, Color(30, 40, 56, 220))
                end
            end
        end

        local function card(parent, h)
            local p = vgui.Create("DPanel", parent)
            p:Dock(TOP)
            p:SetTall(h or 88)
            p:DockMargin(0, 0, 0, 8)
            p.Paint = function(_, w, hh)
                draw.RoundedBox(6, 0, 0, w, hh, C.card)
                surface.SetDrawColor(C.border)
                surface.DrawOutlinedRect(0, 0, w, hh)
            end

            return p
        end

        local function histBox(p, list)
            local box = vgui.Create("DScrollPanel", p)
            box:Dock(FILL)
            box:DockMargin(10, 36, 10, 10)
            box.Paint = function(_, w, h)
                draw.RoundedBox(4, 0, 0, w, h, Color(18, 22, 30, 200))
            end
            local bar = box:GetVBar()
            if IsValid(bar) then
                bar:SetWide(6)
                bar.Paint = function(_, w, h) draw.RoundedBox(3, 0, 0, w, h, Color(18, 22, 32)) end
                bar.btnUp.Paint, bar.btnDown.Paint = function() end, function() end
                bar.btnGrip.Paint = function(_, w, h) draw.RoundedBox(3, 0, 0, w, h, C.borderLight) end
            end
            for i = #(list or {}), math.max(1, #(list or {}) - 80), -1 do
                local rec = list[i]
                local l = vgui.Create("DLabel", box)
                l:Dock(TOP) l:SetTall(18) l:DockMargin(8, 1, 4, 1)
                l:SetFont("GRMFac_Small") l:SetTextColor(C.dim)
                l:SetText(os.date("%d.%m %H:%M", rec.t or 0) .. "  ·  " .. tostring(rec.s or ""))
            end
            return box
        end

        local stats = d.stats or {}
        local st = d.state or {}
        local full = d.fullconfig or {}
        local tabButtons = {}

        local function selectTab(key, builder)
            host._tabName = key
            for k, b in pairs(tabButtons) do b.isActive = (k == key) end
            content:Clear()
            if builder then builder(content) end
        end

        local function addTab(key, label, builder)
            local btn = vgui.Create("DButton", sidebar)
            btn:Dock(TOP)
            btn:SetTall(38)
            btn:DockMargin(6, 4, 6, 0)
            btn:SetText("")
            btn.isActive = false
            btn.Paint = function(s, w, h)
                local on, hov = s.isActive, s:IsHovered()
                if on then draw.RoundedBox(6, 0, 0, w, h, C.accent)
                elseif hov then draw.RoundedBox(6, 0, 0, w, h, C.cardHover) end
                draw.SimpleText(label, "GRMFac_Btn", 14, h / 2, (on or hov) and color_white or C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            btn.DoClick = function() selectTab(key, builder) end
            tabButtons[key] = btn
        end

        local function buildOverview(pnl)
            local sc = vgui.Create("DScrollPanel", pnl)
            sc:Dock(FILL)
            local row = vgui.Create("DPanel", sc)
            row:Dock(TOP) row:SetTall(110) row:SetPaintBackground(false)
            row.Paint = function(_, w, h)
                local cw = math.floor((w - 16) / 3)
                local function box(x, title, val, col)
                    draw.RoundedBox(6, x, 0, cw, h, C.card)
                    surface.SetDrawColor(C.border)
                    surface.DrawOutlinedRect(x, 0, cw, h)
                    draw.SimpleText(title, "GRMFac_Small", x + 14, 16, C.dim)
                    draw.SimpleText(val, "GRMFac_StatVal", x + 14, 48, col)
                end
                box(0, "ГОСБЮДЖЕТ", moneyFmt(st.budget or 0), C.gold)
                box(cw + 8, "НАЛИЧНЫЕ", moneyFmt(stats.cash or 0), C.green)
                box((cw + 8) * 2, "СЧЕТА БАНКА", moneyFmt(stats.bank or 0), C.accent)
            end
            local info = card(sc, 120)
            info.Paint = function(_, w, h)
                draw.RoundedBox(6, 0, 0, w, h, C.card)
                surface.SetDrawColor(C.border) surface.DrawOutlinedRect(0, 0, w, h)
                draw.SimpleText("Единая казна GRM", "GRMFac_Sub", 16, 14, C.text)
                draw.SimpleText(("Счетов: %d   ·   фракций: %d   ·   записей лога: %d"):format(stats.players or 0, stats.factions or 0, stats.logSize or 0), "GRMFac_Normal", 16, 44, C.dim)
                draw.SimpleText(isSuper and "Полный доступ суперадмина. Субсидия и закупка бьют в одну казну." or "Режим ведомства: казна и зарплаты. Балансы игроков и глобальные настройки закрыты.", "GRMFac_Small", 16, 70, C.dim)
                draw.SimpleText("Чат /feco_admin  ·  консоль grm_salary_admin  ·  вкладка «Казна» в /factions", "GRMFac_Small", 16, 90, C.dim)
            end
            local bar = card(sc, 56)
            bar:SetPaintBackground(false)
            mkBtn(bar, "Сохранить на диск", C.accent, C.accentHover, function() act({ action = "save_now" }) end):Dock(LEFT)
            bar:GetChildren()[1]:SetWide(200)
            bar:GetChildren()[1]:DockMargin(12, 12, 0, 12)
        end

        local function buildState(pnl)
            local sc = vgui.Create("DScrollPanel", pnl)
            sc:Dock(FILL)
            local head = card(sc, 100)
            head.Paint = function(_, w, h)
                draw.RoundedBox(6, 0, 0, w, h, C.card)
                surface.SetDrawColor(C.border) surface.DrawOutlinedRect(0, 0, w, h)
                draw.SimpleText("ГОСУДАРСТВЕННЫЙ БЮДЖЕТ", "GRMFac_Small", 16, 16, C.dim)
                draw.SimpleText(moneyFmt(st.budget or 0), "GRMFac_StatVal", 16, 44, C.gold)
            end
            local ops = card(sc, 168)
            local amt = vgui.Create("DTextEntry", ops)
            amt:SetPos(16, 16) amt:SetSize(160, 30) amt:SetNumeric(true) amt:SetPlaceholderText("Сумма…")
            skinEntry(amt)
            mkBtn(ops, "Пополнить", C.green, C.greenHover, function() act({ action = "state_give", amount = math.floor(tonumber(amt:GetValue()) or 0) }) end):SetPos(188, 16)
            ops:GetChildren()[#ops:GetChildren()]:SetSize(120, 30)
            mkBtn(ops, "Изъять", C.red, C.redHover, function() act({ action = "state_take", amount = math.floor(tonumber(amt:GetValue()) or 0) }) end):SetPos(316, 16)
            ops:GetChildren()[#ops:GetChildren()]:SetSize(110, 30)
            if isSuper then
                mkBtn(ops, "Установить", C.accent, C.accentHover, function() act({ action = "state_set", amount = math.floor(tonumber(amt:GetValue()) or 0) }) end):SetPos(434, 16)
                ops:GetChildren()[#ops:GetChildren()]:SetSize(120, 30)
            end
            local cmb = vgui.Create("DComboBox", ops)
            cmb:SetPos(16, 60) cmb:SetSize(260, 30) cmb:SetValue("Фракция…")
            skinCombo(cmb)
            for n in pairs(d.factions or {}) do cmb:AddChoice(n, n) end
            mkBtn(ops, "Перечислить из гос.", C.gold, C.cardHover, function()
                local _, nm = cmb:GetSelected()
                if nm then act({ action = "state_to_faction", faction = nm, amount = math.floor(tonumber(amt:GetValue()) or 0) }) end
            end):SetPos(288, 60)
            ops:GetChildren()[#ops:GetChildren()]:SetSize(200, 30)
            local cmb2 = vgui.Create("DComboBox", ops)
            cmb2:SetPos(16, 104) cmb2:SetSize(260, 30) cmb2:SetValue("Игрок…")
            skinCombo(cmb2)
            for sid, rec in pairs(d.players or {}) do
                cmb2:AddChoice(tostring(rec.rpName or rec.name or sid), sid)
            end
            mkBtn(ops, "Выплатить из гос.", C.green, C.greenHover, function()
                local _, sid = cmb2:GetSelected()
                if sid then act({ action = "state_pay", sid = sid, amount = math.floor(tonumber(amt:GetValue()) or 0) }) end
            end):SetPos(288, 104)
            ops:GetChildren()[#ops:GetChildren()]:SetSize(200, 30)
            local hist = card(sc, 360)
            hist.Paint = function(_, w, h)
                draw.RoundedBox(6, 0, 0, w, h, C.card)
                surface.SetDrawColor(C.border) surface.DrawOutlinedRect(0, 0, w, h)
                draw.SimpleText("Операции госбюджета", "GRMFac_Sub", 16, 12, C.text)
            end
            histBox(hist, st.history or {})
        end

        local function buildPlayers(pnl)
            local list = vgui.Create("DListView", pnl)
            list:Dock(FILL)
            list:SetMultiSelect(false)
            list:AddColumn("Игрок / персонаж")
            list:AddColumn("Наличные")
            list:AddColumn("Счёт")
            skinListView(list)
            local sids = {}
            for sid in pairs(d.players or {}) do sids[#sids + 1] = sid end
            table.sort(sids, function(a1, b1)
                return tostring((d.players[a1] or {}).rpName or ""):lower() < tostring((d.players[b1] or {}).rpName or ""):lower()
            end)
            for _, sid in ipairs(sids) do
                local rec = d.players[sid]
                local ln = list:AddLine(tostring(rec.rpName or rec.name or "?") .. "  (" .. tostring(rec.characterLabel or "") .. ")", moneyFmt(rec.balance or 0), moneyFmt(rec.bank or 0))
                ln.Sid = sid
                skinLine(ln)
            end
            local bar = vgui.Create("DPanel", pnl)
            bar:Dock(BOTTOM) bar:SetTall(isSuper and 52 or 36) bar:DockMargin(0, 8, 0, 0)
            bar:SetPaintBackground(false)
            if isSuper then
                local amt = vgui.Create("DTextEntry", bar)
                amt:Dock(LEFT) amt:SetWide(140) amt:SetNumeric(true) amt:SetPlaceholderText("Сумма…")
                skinEntry(amt)
                local function sel()
                    local l = list:GetSelectedLine()
                    return l and list:GetLine(l).Sid
                end
                mkBtn(bar, "Выдать", C.green, C.greenHover, function()
                    local sid = sel()
                    if sid then act({ action = "player_give", sid = sid, amount = math.floor(tonumber(amt:GetValue()) or 0) }) end
                end):Dock(LEFT)
                bar:GetChildren()[#bar:GetChildren()]:SetWide(90)
                bar:GetChildren()[#bar:GetChildren()]:DockMargin(8, 10, 0, 10)
                mkBtn(bar, "Изъять", C.red, C.redHover, function()
                    local sid = sel()
                    if sid then act({ action = "player_take", sid = sid, amount = math.floor(tonumber(amt:GetValue()) or 0) }) end
                end):Dock(LEFT)
                bar:GetChildren()[#bar:GetChildren()]:SetWide(90)
                bar:GetChildren()[#bar:GetChildren()]:DockMargin(6, 10, 0, 10)
                mkBtn(bar, "Наличные", C.accent, C.accentHover, function()
                    local sid = sel()
                    if sid then act({ action = "player_set", sid = sid, amount = math.floor(tonumber(amt:GetValue()) or 0) }) end
                end):Dock(LEFT)
                bar:GetChildren()[#bar:GetChildren()]:SetWide(120)
                bar:GetChildren()[#bar:GetChildren()]:DockMargin(6, 10, 0, 10)
                mkBtn(bar, "Счёт", C.gold, C.cardHover, function()
                    local sid = sel()
                    if sid then act({ action = "player_bank_set", sid = sid, amount = math.floor(tonumber(amt:GetValue()) or 0) }) end
                end):Dock(LEFT)
                bar:GetChildren()[#bar:GetChildren()]:SetWide(90)
                bar:GetChildren()[#bar:GetChildren()]:DockMargin(6, 10, 0, 10)
            else
                local hint = vgui.Create("DLabel", bar)
                hint:Dock(FILL)
                hint:SetFont("GRMFac_Small")
                hint:SetTextColor(C.dim)
                hint:SetText("Просмотр. Изменение балансов — только суперадмин.")
            end
        end

        local function buildFactions(pnl)
            local list = vgui.Create("DListView", pnl)
            list:Dock(LEFT)
            list:SetWide(240)
            list:SetMultiSelect(false)
            list:AddColumn("Организация")
            list:AddColumn("Казна")
            skinListView(list)
            local names = {}
            for n in pairs(d.factions or {}) do names[#names + 1] = n end
            table.sort(names)
            for _, n in ipairs(names) do
                local fd = d.factions[n]
                local ln = list:AddLine(n, moneyFmt(fd.entry and fd.entry.budget or 0))
                ln.Faction = n
                skinLine(ln)
            end
            local editor = vgui.Create("DScrollPanel", pnl)
            editor:Dock(FILL)
            editor:DockMargin(10, 0, 0, 0)

            local function showEditor(name)
                editor:Clear()
                local fd = (d.factions or {})[name]
                if not fd then return end
                host._restoreFaction = name
                local e = fd.entry or {}
                local fp = istable(e.finePerms) and e.finePerms or {}
                local rolesTbl, deptsTbl, fineChks = {}, {}, {}
                local head = card(editor, 86)
                head.Paint = function(_, w, h)
                    draw.RoundedBox(6, 0, 0, w, h, C.card)
                    surface.SetDrawColor(C.border) surface.DrawOutlinedRect(0, 0, w, h)
                    draw.SimpleText(name, "GRMFac_Sub", 16, 14, C.text)
                    draw.SimpleText("онлайн " .. tostring(fd.online or 0) .. " / " .. tostring(fd.members or 0), "GRMFac_Small", 16, 38, C.dim)
                    draw.SimpleText(moneyFmt(e.budget or 0), "GRMFac_StatVal", w - 16, 28, C.gold, TEXT_ALIGN_RIGHT)
                end
                local pay = card(editor, 200)
                local function lab(txt, x, y)
                    local l = vgui.Create("DLabel", pay)
                    l:SetPos(x, y) l:SetSize(200, 20) l:SetFont("GRMFac_Small") l:SetTextColor(C.dim) l:SetText(txt)
                end
                lab("Налог, %", 16, 12)
                local taxW = vgui.Create("DNumberWang", pay)
                taxW:SetPos(16, 32) taxW:SetSize(90, 24)
                taxW:SetMin(0) taxW:SetMax((d.config and math.floor((d.config.maxTax or 0.5) * 100)) or 50)
                taxW:SetValue(math.floor((e.taxRate or 0) * 100))
                lab("База ЗП", 120, 12)
                local baseW = vgui.Create("DNumberWang", pay)
                baseW:SetPos(120, 32) baseW:SetSize(110, 24)
                baseW:SetMin(0) baseW:SetMax(10000000) baseW:SetValue(e.baseSalary or 0)
                lab("Интервал, сек", 246, 12)
                local intW = vgui.Create("DNumberWang", pay)
                intW:SetPos(246, 32) intW:SetSize(90, 24)
                intW:SetMin(30) intW:SetMax(86400) intW:SetValue(e.salaryInterval or 600)
                local pfb = vgui.Create("DCheckBoxLabel", pay)
                pfb:SetPos(16, 68) pfb:SetSize(360, 20)
                pfb:SetText("ЗП из казны фракции") pfb:SetTextColor(C.text)
                pfb:SetValue(e.payFromBudget and 1 or 0)
                local bAmt = vgui.Create("DTextEntry", pay)
                bAmt:SetPos(16, 98) bAmt:SetSize(100, 28) bAmt:SetNumeric(true) bAmt:SetPlaceholderText("Сумма")
                skinEntry(bAmt)
                mkBtn(pay, "+ Казна", C.green, C.greenHover, function()
                    act({ action = "budget_give", faction = name, amount = math.floor(tonumber(bAmt:GetValue()) or 0) })
                end):SetPos(124, 98)
                pay:GetChildren()[#pay:GetChildren()]:SetSize(100, 28)
                mkBtn(pay, "− Казна", C.red, C.redHover, function()
                    act({ action = "budget_take", faction = name, amount = math.floor(tonumber(bAmt:GetValue()) or 0) })
                end):SetPos(232, 98)
                pay:GetChildren()[#pay:GetChildren()]:SetSize(100, 28)

                local rolesCard = card(editor, 200)
                rolesCard.Paint = function(_, w, h)
                    draw.RoundedBox(6, 0, 0, w, h, C.card)
                    surface.SetDrawColor(C.border) surface.DrawOutlinedRect(0, 0, w, h)
                    draw.SimpleText("ЗП по должностям", "GRMFac_Sub", 14, 10, C.text)
                end
                local rolesBox = vgui.Create("DScrollPanel", rolesCard)
                rolesBox:Dock(FILL) rolesBox:DockMargin(10, 34, 10, 8)
                for _, rName in ipairs(fd.roles or {}) do
                    local row = vgui.Create("DPanel", rolesBox)
                    row:Dock(TOP) row:SetTall(26) row:DockMargin(0, 0, 0, 2) row.Paint = nil
                    local l = vgui.Create("DLabel", row) l:Dock(LEFT) l:SetWide(200)
                    l:SetText(rName) l:SetFont("GRMFac_Small") l:SetTextColor(C.text)
                    local wn = vgui.Create("DNumberWang", row) wn:Dock(RIGHT) wn:SetWide(90)
                    wn:SetMin(0) wn:SetMax(10000000) wn:SetValue((e.roleSalaries or {})[rName] or 0)
                    rolesTbl[rName] = wn
                end
                local deptCard = card(editor, 160)
                deptCard.Paint = function(_, w, h)
                    draw.RoundedBox(6, 0, 0, w, h, C.card)
                    surface.SetDrawColor(C.border) surface.DrawOutlinedRect(0, 0, w, h)
                    draw.SimpleText("Надбавки отделов", "GRMFac_Sub", 14, 10, C.text)
                end
                local deptsBox = vgui.Create("DScrollPanel", deptCard)
                deptsBox:Dock(FILL) deptsBox:DockMargin(10, 34, 10, 8)
                for _, dName in ipairs(fd.departments or {}) do
                    local row = vgui.Create("DPanel", deptsBox)
                    row:Dock(TOP) row:SetTall(26) row:DockMargin(0, 0, 0, 2) row.Paint = nil
                    local l = vgui.Create("DLabel", row) l:Dock(LEFT) l:SetWide(200)
                    l:SetText(dName) l:SetFont("GRMFac_Small") l:SetTextColor(C.text)
                    local wn = vgui.Create("DNumberWang", row) wn:Dock(RIGHT) wn:SetWide(90)
                    wn:SetMin(0) wn:SetMax(10000000) wn:SetValue((e.departmentSalaries or {})[dName] or 0)
                    deptsTbl[dName] = wn
                end

                local chEn, chAll, chOwn, chOther, chCiv, maxW, pctW
                local fine = card(editor, isSuper and 280 or 120)
                if isSuper then
                    fine.Paint = function(_, w, h)
                        draw.RoundedBox(6, 0, 0, w, h, C.card)
                        surface.SetDrawColor(C.border) surface.DrawOutlinedRect(0, 0, w, h)
                        draw.SimpleText("Штрафы /fine", "GRMFac_Sub", 14, 10, C.text)
                    end
                    chEn = vgui.Create("DCheckBoxLabel", fine) chEn:SetPos(16, 36) chEn:SetText("Фракции разрешено штрафовать") chEn:SetTextColor(C.text) chEn:SetValue(fp.enabled and 1 or 0)
                    chAll = vgui.Create("DCheckBoxLabel", fine) chAll:SetPos(16, 58) chAll:SetText("Все роли") chAll:SetTextColor(C.text) chAll:SetValue(fp.allRoles and 1 or 0)
                    chOwn = vgui.Create("DCheckBoxLabel", fine) chOwn:SetPos(16, 80) chOwn:SetText("Свои") chOwn:SetTextColor(C.text) chOwn:SetValue(fp.ownFaction and 1 or 0)
                    chOther = vgui.Create("DCheckBoxLabel", fine) chOther:SetPos(120, 80) chOther:SetText("Чужие фракции") chOther:SetTextColor(C.text) chOther:SetValue(fp.otherFactions and 1 or 0)
                    chCiv = vgui.Create("DCheckBoxLabel", fine) chCiv:SetPos(280, 80) chCiv:SetText("Граждане") chCiv:SetTextColor(C.text) chCiv:SetValue(fp.civilians and 1 or 0)
                    maxW = vgui.Create("DNumberWang", fine) maxW:SetPos(16, 110) maxW:SetSize(110, 24) maxW:SetMin(0) maxW:SetMax(1e8) maxW:SetValue(fp.maxAmount or 0)
                    pctW = vgui.Create("DNumberWang", fine) pctW:SetPos(140, 110) pctW:SetSize(80, 24) pctW:SetMin(0) pctW:SetMax(100) pctW:SetValue(fp.statePercent or 0)
                    local rf = vgui.Create("DScrollPanel", fine)
                    rf:SetPos(16, 144) rf:SetSize(320, 120)
                    for _, rName in ipairs(fd.roles or {}) do
                        local c = vgui.Create("DCheckBoxLabel", rf)
                        c:Dock(TOP) c:SetTall(20) c:SetText(rName) c:SetTextColor(C.text)
                        c:SetValue((fp.roles or {})[rName] and 1 or 0)
                        fineChks[rName] = c
                    end
                else
                    fine.Paint = function(_, w, h)
                        draw.RoundedBox(6, 0, 0, w, h, C.card)
                        surface.SetDrawColor(C.border) surface.DrawOutlinedRect(0, 0, w, h)
                        draw.SimpleText("% штрафа в госбюджет", "GRMFac_Sub", 14, 10, C.text)
                    end
                    pctW = vgui.Create("DNumberWang", fine)
                    pctW:SetPos(16, 44) pctW:SetSize(90, 24) pctW:SetMin(0) pctW:SetMax(100) pctW:SetValue(fp.statePercent or 0)
                end

                local function doSave()
                    local roles, depts = {}, {}
                    for k, wn in pairs(rolesTbl) do roles[k] = math.floor(tonumber(wn:GetValue()) or 0) end
                    for k, wn in pairs(deptsTbl) do depts[k] = math.floor(tonumber(wn:GetValue()) or 0) end
                    local payload = {
                        action = "save_entry", faction = name,
                        taxRate = math.Clamp((tonumber(taxW:GetValue()) or 0) / 100, 0, 1),
                        baseSalary = math.floor(tonumber(baseW:GetValue()) or 0),
                        salaryInterval = math.floor(tonumber(intW:GetValue()) or 600),
                        payFromBudget = pfb:GetChecked(),
                        roles = roles, departments = depts,
                    }
                    if isSuper then
                        local froles = {}
                        for k, c in pairs(fineChks) do if c:GetChecked() then froles[k] = true end end
                        payload.fine = {
                            enabled = chEn:GetChecked(), allRoles = chAll:GetChecked(),
                            ownFaction = chOwn:GetChecked(), otherFactions = chOther:GetChecked(),
                            civilians = chCiv:GetChecked(),
                            maxAmount = math.max(0, math.floor(tonumber(maxW:GetValue()) or 0)),
                            statePercent = math.Clamp(math.floor(tonumber(pctW:GetValue()) or 0), 0, 100),
                            roles = froles,
                        }
                    elseif pctW then
                        payload.fine = { statePercent = math.Clamp(math.floor(tonumber(pctW:GetValue()) or 0), 0, 100) }
                    end
                    act(payload)
                end
                local bar = card(editor, 52)
                mkBtn(bar, "Сохранить", C.green, C.greenHover, doSave):Dock(LEFT)
                bar:GetChildren()[1]:SetWide(150)
                bar:GetChildren()[1]:DockMargin(12, 10, 0, 10)
                mkBtn(bar, "Выплатить ЗП сейчас", C.gold, C.cardHover, function()
                    act({ action = "pay_now", faction = name })
                end):Dock(LEFT)
                bar:GetChildren()[2]:SetWide(180)
                bar:GetChildren()[2]:DockMargin(8, 10, 0, 10)
            end
            list.OnRowSelected = function(_, _, ln) showEditor(ln.Faction) end
            local restore = host._restoreFaction
            if restore and (d.factions or {})[restore] then showEditor(restore)
            elseif #names > 0 then showEditor(names[1]) end
        end

        local function buildLog(pnl)
            local top = vgui.Create("DPanel", pnl)
            top:Dock(TOP) top:SetTall(36) top:SetPaintBackground(false)
            mkBtn(top, "Обновить", C.accent, C.accentHover, function()
                net.Start(NET_OPEN_ADMIN) net.SendToServer()
            end):Dock(RIGHT)
            top:GetChildren()[1]:SetWide(120)
            local box = vgui.Create("DPanel", pnl)
            box:Dock(FILL)
            box.Paint = function(_, w, h)
                draw.RoundedBox(6, 0, 0, w, h, C.card)
                surface.SetDrawColor(C.border) surface.DrawOutlinedRect(0, 0, w, h)
                draw.SimpleText("Финансовый журнал", "GRMFac_Sub", 16, 10, C.text)
            end
            histBox(box, d.log or {})
        end

        local function buildCfg(pnl)
            local sc = vgui.Create("DScrollPanel", pnl)
            sc:Dock(FILL)
            local wns, cks = {}, {}
            local function row(txt, key, pct, mx)
                local r = card(sc, 48)
                r.Paint = function(_, w, h)
                    draw.RoundedBox(6, 0, 0, w, h, C.card)
                    draw.SimpleText(txt, "GRMFac_Normal", 16, h / 2, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end
                local wn = vgui.Create("DNumberWang", r)
                wn:Dock(RIGHT) wn:SetWide(120) wn:DockMargin(0, 10, 12, 10)
                wn:SetMin(0) wn:SetMax(mx or 1e8)
                local v = tonumber(full[key]) or 0
                if pct then v = math.floor(v * 100 + 0.5) end
                wn:SetValue(v)
                wns[key] = { wn = wn, pct = pct }
            end
            local function chk(txt, key)
                local r = card(sc, 40)
                local c = vgui.Create("DCheckBoxLabel", r)
                c:Dock(FILL) c:DockMargin(16, 10, 12, 8)
                c:SetText(txt) c:SetTextColor(C.text) c:SetValue(full[key] and 1 or 0)
                cks[key] = c
            end
            row("Налог по умолчанию, %", "DefaultTaxRate", true, 100)
            row("Максимальный налог, %", "MaxTaxRate", true, 100)
            row("Интервал ЗП, сек", "SalaryInterval", false, 86400)
            row("Мин. интервал ЗП, сек", "MinSalaryInterval", false, 3600)
            row("История фракции", "HistorySize", false, 500)
            row("Размер лога", "LogSize", false, 2000)
            row("Макс. штраф", "FineMaxAmount", false, 1e8)
            row("Дистанция банкомата", "UseDistance", false, 1000)
            row("Стартовый баланс", "StartBalance", false, 1e8)
            local nameRow = card(sc, 48)
            local cname = vgui.Create("DTextEntry", nameRow)
            cname:Dock(RIGHT) cname:SetWide(180) cname:DockMargin(0, 10, 12, 10)
            cname:SetText(tostring(full.CurrencyName or "GRM"))
            skinEntry(cname)
            nameRow.Paint = function(_, w, h)
                draw.RoundedBox(6, 0, 0, w, h, C.card)
                draw.SimpleText("Название валюты", "GRMFac_Normal", 16, h / 2, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            local mdlRow = card(sc, 48)
            local cmodel = vgui.Create("DTextEntry", mdlRow)
            cmodel:Dock(RIGHT) cmodel:SetWide(320) cmodel:DockMargin(0, 10, 12, 10)
            cmodel:SetText(tostring(full.BankTerminalModel or "models/starless/atm.mdl"))
            skinEntry(cmodel)
            mdlRow.Paint = function(_, w, h)
                draw.RoundedBox(6, 0, 0, w, h, C.card)
                draw.SimpleText("Модель банкомата", "GRMFac_Normal", 16, h / 2, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            chk("ЗП из бюджета по умолчанию", "PayFromBudget")
            chk("Штрафы в казну штрафующего", "FineToBudget")
            chk("Налоги → госбюджет", "TaxToState")
            chk("Штрафы без фракции → госбюджет", "FinesToState")
            local save = card(sc, 52)
            mkBtn(save, "Сохранить настройки", C.green, C.greenHover, function()
                local out = {}
                for key, rec in pairs(wns) do
                    local v = math.max(0, math.floor(tonumber(rec.wn:GetValue()) or 0))
                    out[key] = rec.pct and math.Clamp(v / 100, 0, 1) or v
                end
                for key, c in pairs(cks) do out[key] = c:GetChecked() end
                local nm = string.Trim(tostring(cname:GetValue() or ""))
                if nm ~= "" then out.CurrencyName = nm end
                local mdl = string.Trim(tostring(cmodel:GetValue() or ""))
                if mdl ~= "" then out.BankTerminalModel = mdl end
                act({ action = "config_save", config = out })
            end):Dock(LEFT)
            save:GetChildren()[1]:SetWide(240)
            save:GetChildren()[1]:DockMargin(12, 10, 0, 10)
        end

        addTab("overview", "Обзор", buildOverview)
        addTab("state", "Госбюджет", buildState)
        addTab("players", "Игроки", buildPlayers)
        addTab("factions", "Казна фракций", buildFactions)
        addTab("log", "Журнал", buildLog)
        if isSuper then addTab("cfg", "Настройки", buildCfg) end

        local order = { "overview", "state", "players", "factions", "log", "cfg" }
        local pick = lastTab
        if not tabButtons[pick] then pick = "overview" end
        if tabButtons[pick] then
            selectTab(pick, ({
                overview = buildOverview, state = buildState, players = buildPlayers,
                factions = buildFactions, log = buildLog, cfg = buildCfg,
            })[pick])
        end
    end

    -- Встраивание панели экономики в другие меню (находка 172: /factions)
    GRM.Economy.EmbeddedAdmin = nil
    function GRM.Economy.BuildAdminContent(parent, d)
        if not IsValid(parent) then return end
        if GRM.UI and GRM.UI.SafeClear then GRM.UI.SafeClear(parent) else parent:Clear() end
        buildAdminUI(d or {}, parent)
        return parent
    end
    function GRM.Economy.EmbedAdminPanel(panel)
        if IsValid(panel) then
            GRM.Economy.EmbeddedAdmin = panel
            panel.OnRemove = function()
                if GRM.Economy.EmbeddedAdmin == panel then GRM.Economy.EmbeddedAdmin = nil end
            end
        else
            GRM.Economy.EmbeddedAdmin = nil
        end
    end

    -- Находка 180: приём админ-данных ЧАНКАМИ (сервер шлёт base → log →
    -- players порциями). Собираем в ecoPending и строим UI по факту
    -- получения последнего чанка игроков.
    local ecoPending = nil
    local ecoPlayersTotal = nil
    local function ecoFinalize()
        local d = ecoPending
        ecoPending = nil
        ecoPlayersTotal = nil
        if not d then return end
        if IsValid(adminFrame) then
            -- окно НЕ переоткрывается; UI пересобирается на месте,
            -- выбранная фракция восстанавливается через _restoreFaction.
            buildAdminUI(d)
        end
        -- обновить встроенную панель (/factions → «Экономика»)
        -- Находка 177: раньше вызывалось _embeddedBuild(EmbeddedAdmin, d) —
        -- build(d) принимал ОДИН аргумент, и в d попадала панель, а данные
        -- терялись: фракции/игроки/гос.бюджет в /factions были пустыми.
        -- Теперь данные всегда во втором аргументе (build защищён и от
        -- вызова с одним аргументом).
        if IsValid(GRM.Economy.EmbeddedAdmin) and isfunction(GRM.Economy._embeddedBuild) then
            GRM.Economy._embeddedBuild(GRM.Economy.EmbeddedAdmin, d)
        end
    end

    net.Receive(NET_ADMIN_DATA, function()
        local kind = net.ReadString()
        if kind == "base" then
            local d = net.ReadTable() or {}
            d.players = {}
            d.log = {}
            ecoPending = d
            ecoPlayersTotal = nil
        elseif kind == "log" then
            if ecoPending then ecoPending.log = net.ReadTable() or {} end
        elseif kind == "players" then
            if not ecoPending then return end
            local idx = net.ReadUInt(16)
            local total = net.ReadUInt(16)
            if not ecoPlayersTotal then ecoPlayersTotal = total end
            local part = net.ReadTable() or {}
            for sid, rec in pairs(part) do ecoPending.players[sid] = rec end
            if idx >= ecoPlayersTotal then ecoFinalize() end
        end
    end)

    net.Receive(NET_OPEN_ADMIN, function()
        if IsValid(adminFrame) then adminFrame:Remove() end
        adminFrame = frame("Казна GRM", math.Clamp(ScrW() * 0.88, 1100, 1680), math.Clamp(ScrH() * 0.86, 680, 980))
        -- открыли пустой каркас — сразу запрашиваем данные у сервера
        net.Start(NET_OPEN_ADMIN) net.SendToServer()
    end)

    -- ── БАНК-ТЕРМИНАЛ (БАНКОМАТ): вкладки — счёт / перевод / фракция ──
    net.Receive(NET_OPEN_BANK, function()
        local ent = net.ReadEntity()
        local d = net.ReadTable() or {}
        local f = frame("Банкомат GRM", 580, 520)

        local sheet = vgui.Create("DPropertySheet", f)
        sheet:Dock(FILL)
        sheet:DockMargin(8, 34, 8, 8)

        local bankBusy = false
        local function bankAction(t, amtEntry, extra)
            if bankBusy then return end
            local raw = string.Trim(tostring(amtEntry:GetValue() or ""))
            -- только цифры (без "1e6" / мусора)
            if raw == "" or string.match(raw, "[^0-9]") then return end
            local a = math.floor(tonumber(raw) or 0)
            if a <= 0 then return end
            bankBusy = true
            net.Start(NET_BANK_ACT)
                -- Код 126: передаём ent (банкомат), чтобы сервер знал, какой терминал пополняется комиссией
                net.WriteTable({ type = t, amount = a, to = extra, ent = ent })
            net.SendToServer()
            -- не закрываем мгновенно — даём серверу ответить; закрытие через 0.2
            timer.Simple(0.2, function()
                if IsValid(f) then f:Close() end
            end)
        end

        local function tabLabel(p, txt, col, x, y)
            local l = vgui.Create("DLabel", p)
            l:SetPos(x, y) l:SetSize(535, 24)
            l:SetText(txt) l:SetFont("GRM_Eco_Title")
            l:SetTextColor(col or CUI.text)
        end
        local function tabSmall(p, txt, col, x, y)
            local l = vgui.Create("DLabel", p)
            l:SetPos(x, y) l:SetSize(535, 20)
            l:SetText(txt) l:SetFont("GRM_Eco_Normal")
            l:SetTextColor(col or CUI.dim)
        end
        local function tabAmt(p, x, y)
            local amt = vgui.Create("DTextEntry", p)
            amt:SetPos(x, y) amt:SetSize(150, 28)
            amt:SetNumeric(true) amt:SetPlaceholderText("Сумма...")
            return amt
        end

        -- ВКЛАДКА 1: личный счёт — доступна ВСЕМ игрокам
        local p1 = vgui.Create("DPanel", sheet)
        p1:SetPaintBackground(false)
        p1.Paint = function(_, w, h) draw.RoundedBox(4, 0, 0, w, h, CUI.panel) end
        p1.Paint = function() end
        sheet:AddSheet("Мой счёт", p1, "icon16/money.png")
        tabLabel(p1, "Наличные: " .. money(d.balance or 0), CUI.green, 14, 12)
        tabLabel(p1, "Счёт в банке: " .. money(d.bank or 0), CUI.yellow, 14, 44)
        local amt1 = tabAmt(p1, 14, 86)
        local dep = btn(p1, "Внести на счёт", CUI.green, 160, 28)
        dep:SetPos(174, 86)
        dep.DoClick = function() bankAction("bank_deposit", amt1) end
        local wd = btn(p1, "Снять со счёта", CUI.accent, 160, 28)
        wd:SetPos(344, 86)
        wd.DoClick = function() bankAction("bank_withdraw", amt1) end
        tabSmall(p1, "Счёт в банке сохраняется всегда: при смерти теряются", CUI.dim, 14, 132)
        tabSmall(p1, "только наличные, деньги на счёте — в безопасности.", CUI.dim, 14, 154)

        -- ВКЛАДКА 2: перевод другому игроку (счёт -> счёт)
        local p2 = vgui.Create("DPanel", sheet)
        p2:SetPaintBackground(false)
        p2.Paint = function(_, w, h) draw.RoundedBox(4, 0, 0, w, h, CUI.panel) end
        p2.Paint = function() end
        sheet:AddSheet("Перевод", p2, "icon16/arrow_right.png")
        tabLabel(p2, "Ваш счёт: " .. money(d.bank or 0), CUI.yellow, 14, 12)
        local combo = vgui.Create("DComboBox", p2)
        combo:SetPos(14, 50) combo:SetSize(330, 28)
        combo:SetValue("Получатель (игроки онлайн)...")
        for _, pl in ipairs(d.players or {}) do combo:AddChoice(pl.nick, pl.sid64) end
        local amt2 = tabAmt(p2, 14, 92)
        local tr = btn(p2, "Перевести со счёта", CUI.green, 190, 28)
        tr:SetPos(174, 92)
        tr.DoClick = function()
            local _, sid = combo:GetSelected()
            if not sid then return end
            bankAction("bank_transfer", amt2, sid)
        end
        tabSmall(p2, "Списывается с вашего счёта, зачисляется на счёт получателя.", CUI.dim, 14, 138)

        -- ВКЛАДКА 3: фракция — только для членов фракции
        if (d.faction or "") ~= "" and d.factionData then
            local p3 = vgui.Create("DPanel", sheet)
        p3:SetPaintBackground(false)
        p3.Paint = function(_, w, h) draw.RoundedBox(4, 0, 0, w, h, CUI.panel) end
            p3.Paint = function() end
            sheet:AddSheet("Фракция", p3, "icon16/group.png")
            tabLabel(p3, d.faction .. ": бюджет " .. money(d.factionData.budget or 0), CUI.green, 14, 12)
            tabSmall(p3, "Налог: " .. math.floor((d.factionData.taxRate or 0) * 100) .. "%"
                .. "  |  Ваша ЗП: " .. money(d.mySalary or 0)
                .. (d.leader and "  |  Вы — ЛИДЕР" or ""), CUI.yellow, 14, 44)
            local amt3 = tabAmt(p3, 14, 76)
            local fdep = btn(p3, "Внести в бюджет (наличные)", CUI.accent, 210, 28)
            fdep:SetPos(174, 76)
            fdep.DoClick = function() bankAction("deposit", amt3) end
            local fwd = btn(p3, "Вывести (лидер)", CUI.yellow, 150, 28)
            fwd:SetPos(394, 76)
            fwd.DoClick = function() bankAction("withdraw", amt3) end

            if istable(d.factionData.history) then
                tabSmall(p3, "Последние операции фракции:", CUI.text, 14, 118)
                local hist = vgui.Create("DScrollPanel", p3)
                hist:SetPos(14, 142) hist:SetSize(535, 290)
                hist.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, CUI.panel) end
                local h = d.factionData.history
                for i = #h, math.max(1, #h - 30), -1 do
                    local rec = h[i]
                    local l = vgui.Create("DLabel", hist)
                    l:Dock(TOP) l:SetTall(16) l:DockMargin(8, 2, 4, 1)
                    l:SetFont("GRM_Eco_Small") l:SetTextColor(CUI.dim)
                    l:SetText(os.date("%d.%m %H:%M", rec.t or 0) .. " — " .. tostring(rec.s or ""))
                end
            end
        end
    end)

    concommand.Add("grm_salary_admin", function()
        net.Start(NET_OPEN_ADMIN) net.SendToServer()
    end)

    print("[GRM Economy] Unified Economy v3.0.3 — клиент загружен")
end

-- Вечер-18: единый словарь slash-команд: имена живого PlayerSay-обработчика
-- вносятся во внешний реестр библиотеки (на режиме сверка идёт ДО ParseSay —
-- без регистрации команда стала бы «неизвестной»).
if GRM and GRM.Chat and GRM.Chat.RegisterExternalCommands then
    GRM.Chat.RegisterExternalCommands({ "/dbcheck", "/feco_admin", "/mysalary", "/salary_admin" })
end
