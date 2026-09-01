-- Boot-шим: старт подсистемы идёт через планировщик GRM.Boot (приоритеты и
-- бюджет на тик). Если планировщик почему-то не загружен, работаем по-старому.
local function grmBootStart(id, tier, fn)
    if GRM and GRM.Boot and GRM.Boot.OnMapStart then return GRM.Boot.OnMapStart(id, tier, fn) end
    return hook.Add("InitPostEntity", id, fn)
end

--[[--------------------------------------------------------------------
    GRM ATM v1.0.0 — интерактивное меню банкомата в стиле GRM

    Единая точка, где житель решает денежные дела:
      • Мой счёт      — наличные, счёт, внести / снять / перевести;
      • Задолженность — штрафы и счета за услуги, оплата со счёта;
      • Госуслуги     — витрина услуг: заказать и оплатить;
      • Дипломы       — свои дипломы и проверка чужого по номеру;
      • Организация   — счета, каталог услуг, выдача дипломов (лидер);
      • Надзор        — полный доступ суперадмина ко всем базам.

    Банкомат — это устройство: он подчиняется электронике (питание сети,
    осмысленный отказ, если оборудование не работает) и не открывается,
    если терминал занят инкассацией.

    Сеть:
      GRM_ATM_Open  (сервер→клиент)  Entity, Table(снимок данных)
      GRM_ATM_Act   (клиент→сервер)  String(action), Table(args)
      GRM_ATM_Data  (сервер→клиент)  Table(снимок)      — обновление
      GRM_ATM_Result(сервер→клиент)  Bool(ok), String(сообщение)
----------------------------------------------------------------------]]

GRM = GRM or {}
GRM.ATM = GRM.ATM or {}
local A = GRM.ATM
A.Version = "1.1.0"

A.Config = A.Config or {
    UseRange     = 200,     -- дистанция взаимодействия с банкоматом
    RateLimit    = 0.35,    -- пауза между действиями, сек
    MaxServices  = 120,     -- сколько услуг отдаём в витрину
    MaxInvoices  = 120,
    MaxFines     = 120,
    MaxDiplomas  = 150,
    MaxCharacters = 400,    -- сколько персонажей (в т.ч. офлайн) отдаём в выбор
}

-----------------------------------------------------------------------
-- ОБЩЕЕ
-----------------------------------------------------------------------
local function money(v)
    if GRM.FormatMoney then return GRM.FormatMoney(v) end
    return string.Comma(math.floor(tonumber(v) or 0)) .. " GRM"
end
A.Money = money

if SERVER then

util.AddNetworkString("GRM_ATM_Open")
util.AddNetworkString("GRM_ATM_Act")
util.AddNetworkString("GRM_ATM_Data")
util.AddNetworkString("GRM_ATM_Result")

local nextAct = {}   -- ply -> CurTime, антиспам net

local function result(ply, ok, msg)
    if not IsValid(ply) then return end
    net.Start("GRM_ATM_Result")
        net.WriteBool(ok and true or false)
        net.WriteString(tostring(msg or ""))
    net.Send(ply)
end

local function charKey(v)
    if GRM.Services and isfunction(GRM.Services.CharKey) then return GRM.Services.CharKey(v) end
    if IsValid(v) and v:IsPlayer() then
        if GRM.Identity and isfunction(GRM.Identity.CharacterKey) then return GRM.Identity.CharacterKey(v) end
        return tostring(v:SteamID64()) .. ":char1"
    end
    return tostring(v or "")
end

--- Работает ли банкомат: инкассация и питание оборудования.
-- @return true | false, причина
function A.TerminalReady(ent)
    if not IsValid(ent) then return true end   -- меню открыли не от энтити
    if ent.GetNWBool and ent:GetNWBool("GRM_IncassLocked", false) then
        return false, "Терминал на обслуживании (инкассация). Попробуйте позже."
    end

    return true
end

--- Снимок данных для клиента. Отдаём только то, что игроку положено видеть.
function A.Snapshot(ply, ent)
    local S, D = GRM.Services, GRM.Diplomas
    local F = GRM.Wanted and GRM.Wanted.Fines
    local E = GRM.Economy
    local key = charKey(ply)
    local isSuper = ply:IsSuperAdmin()

    local fname = S and S.FactionOf(ply) or nil
    local access = (S and fname) and S.AccessOf(fname) or nil
    local isLeader = (S and fname) and S.IsLeaderOf(ply, fname) or false

    local snap = {
        nick     = ply:Nick(),
        key      = key,
        cash     = isfunction(GRM.GetBalance) and GRM.GetBalance(ply) or 0,
        bank     = (E and isfunction(E.BankBalance)) and E.BankBalance(ply) or 0,
        isSuper  = isSuper,
        faction  = fname or "",
        isLeader = isLeader,
        terminal = IsValid(ent) and (isfunction(ent.GetTerminalName) and ent:GetTerminalName() or "Банк GRM") or "Банк GRM",
        access   = access and {
            canService  = access.canService,
            canInvoice  = access.canInvoice,
            canDiploma  = access.canDiploma,
            maxInvoice  = access.maxInvoice,
            institution = access.institution,
        } or nil,
        categories = S and S.Categories or {},
        levels     = D and D.Levels or {},
        forms      = D and D.Forms or {},
    }

    -- Список организаций-исполнителей: нужен полю «Исполнитель» в каталоге
    -- услуг и при выставлении счетов (задача 10).
    snap.providers = {}
    if S and isfunction(S.ProviderList) then
        for _, p in ipairs(S.ProviderList()) do
            snap.providers[#snap.providers + 1] = {
                name = p.name, institution = p.institution,
                canInvoice = p.canInvoice, maxInvoice = p.maxInvoice,
            }
        end
    end

    -- Задолженность: штрафы + счета
    snap.fines = {}
    if F and isfunction(F.For) then
        for _, rec in ipairs(F.For(key, true)) do
            snap.fines[#snap.fines + 1] = {
                id = rec.id, amount = rec.amount, paid = rec.paid,
                reason = rec.reason, issuerName = rec.issuerName,
                issued = rec.issued, article = rec.article,
            }
            if #snap.fines >= A.Config.MaxFines then break end
        end
    end
    snap.invoices = {}
    if S and isfunction(S.InvoicesFor) then
        for _, rec in ipairs(S.InvoicesFor(key, false)) do
            snap.invoices[#snap.invoices + 1] = {
                id = rec.id, title = rec.title, amount = rec.amount, paid = rec.paid,
                status = rec.status, faction = rec.faction, issuerName = rec.issuerName,
                issued = rec.issued, note = rec.note,
            }
            if #snap.invoices >= A.Config.MaxInvoices then break end
        end
    end
    snap.debt = S and isfunction(S.DebtSummary) and S.DebtSummary(key) or { fines = 0, invoices = 0, total = 0 }

    -- Витрина услуг
    snap.services = {}
    if S and isfunction(S.ListServices) then
        for _, rec in ipairs(S.ListServices({ onlyEnabled = true })) do
            snap.services[#snap.services + 1] = {
                id = rec.id, name = rec.name, category = rec.category,
                price = rec.price, provider = rec.provider, desc = rec.desc,
            }
            if #snap.services >= A.Config.MaxServices then break end
        end
    end

    -- Мои дипломы
    snap.diplomas = {}
    if D and isfunction(D.For) then
        for _, rec in ipairs(D.For(key, true)) do
            snap.diplomas[#snap.diplomas + 1] = {
                number = rec.number, institution = rec.institution, specialty = rec.specialty,
                qualification = rec.qualification, level = rec.level, form = rec.form,
                grade = rec.grade, paid = rec.paid, issued = rec.issued,
                signedBy = rec.signedBy, revoked = rec.revoked, revokeReason = rec.revokeReason,
            }
        end
    end

    -- Кабинет организации: свои счета, свой каталог, свои дипломы
    if fname and (isLeader or isSuper or (access and (access.canInvoice or access.canService or access.canDiploma))) then
        snap.org = { name = fname, invoices = {}, services = {}, diplomas = {} }
        if S and isfunction(S.InvoicesByFaction) then
            for _, rec in ipairs(S.InvoicesByFaction(fname, A.Config.MaxInvoices)) do
                snap.org.invoices[#snap.org.invoices + 1] = {
                    id = rec.id, title = rec.title, amount = rec.amount, paid = rec.paid,
                    status = rec.status, targetName = rec.targetName, target = rec.target,
                    issued = rec.issued, issuerName = rec.issuerName,
                }
            end
        end
        if S and isfunction(S.ListServices) then
            for _, rec in ipairs(S.ListServices({ provider = fname, onlyEnabled = false })) do
                snap.org.services[#snap.org.services + 1] = {
                    id = rec.id, name = rec.name, category = rec.category,
                    price = rec.price, desc = rec.desc, enabled = rec.enabled,
                    provider = rec.provider,
                }
            end
        end
        if D and isfunction(D.ByFaction) then
            for _, rec in ipairs(D.ByFaction(fname, A.Config.MaxDiplomas)) do
                snap.org.diplomas[#snap.org.diplomas + 1] = {
                    number = rec.number, graduateName = rec.graduateName, specialty = rec.specialty,
                    level = rec.level, issued = rec.issued, revoked = rec.revoked, paid = rec.paid,
                }
            end
        end
    end

    -- Список игроков онлайн: для переводов (деньги можно слать только живой сессии)
    snap.players = {}
    for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
        if IsValid(p) and p ~= ply then
            snap.players[#snap.players + 1] = { nick = p:Nick(), key = charKey(p) }
        end
    end

    -- Реестр персонажей (онлайн + офлайн из паспортов и составов фракций).
    -- Нужен там, где адресат — персонаж, а не сессия: счета и дипломы.
    snap.characters = {}
    if S and isfunction(S.CharacterRegistry) then
        local n = 0
        for _, rec in ipairs(S.CharacterRegistry()) do
            snap.characters[#snap.characters + 1] = {
                key = rec.key, name = rec.name, faction = rec.faction, online = rec.online,
            }
            n = n + 1
            if n >= (A.Config.MaxCharacters or 400) then break end
        end
    end

    -- Надзор суперадмина: сводные базы
    if isSuper then
        snap.admin = { invoices = {}, diplomas = {}, factions = {} }
        if S then
            local n = 0
            for i = #S.Invoices, 1, -1 do
                local rec = S.Invoices[i]
                snap.admin.invoices[#snap.admin.invoices + 1] = {
                    id = rec.id, title = rec.title, amount = rec.amount, paid = rec.paid,
                    status = rec.status, targetName = rec.targetName, faction = rec.faction,
                    issuerName = rec.issuerName, issued = rec.issued,
                }
                n = n + 1
                if n >= A.Config.MaxInvoices then break end
            end
        end
        if D then
            local page = D.Page({}, 0, A.Config.MaxDiplomas)
            for _, rec in ipairs(page) do
                snap.admin.diplomas[#snap.admin.diplomas + 1] = {
                    number = rec.number, graduateName = rec.graduateName, institution = rec.institution,
                    specialty = rec.specialty, level = rec.level, issued = rec.issued,
                    revoked = rec.revoked, faction = rec.faction,
                }
            end
        end
        if Factions and S then
            for name, f in pairs(Factions) do
                if istable(f) then
                    local a = S.AccessOf(name)
                    snap.admin.factions[#snap.admin.factions + 1] = {
                        name = name,
                        canService = a.canService, canInvoice = a.canInvoice, canDiploma = a.canDiploma,
                        maxInvoice = a.maxInvoice, institution = a.institution,
                        categories = a.categories,
                    }
                end
            end
            table.sort(snap.admin.factions, function(x, y) return x.name < y.name end)
        end
    end

    return snap
end

--- Открыть банкомат игроку.
function A.Open(ply, ent)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if IsValid(ent) and ply:GetPos():DistToSqr(ent:GetPos()) > (A.Config.UseRange ^ 2) then return end
    local ok, why = A.TerminalReady(ent)
    if not ok then
        if GRM.Notify then GRM.Notify(ply, why, 255, 160, 90) else ply:ChatPrint(why) end
        return
    end
    ply._grmATMEnt = IsValid(ent) and ent or nil
    net.Start("GRM_ATM_Open")
        net.WriteEntity(IsValid(ent) and ent or Entity(0))
        net.WriteTable(A.Snapshot(ply, ent))
    net.Send(ply)
end

local function push(ply)
    if not IsValid(ply) then return end
    local ent = ply._grmATMEnt
    net.Start("GRM_ATM_Data")
        net.WriteTable(A.Snapshot(ply, IsValid(ent) and ent or nil))
    net.Send(ply)
end
A.Push = push

-----------------------------------------------------------------------
-- Обработка действий
-----------------------------------------------------------------------
local handlers={}
local function stampInvoiceATM(ply,rec)
    local ent=IsValid(ply._grmATMEnt)and ply._grmATMEnt or nil;if not rec or not IsValid(ent)then return end
    rec.atmNumber=GRM.Incass and GRM.Incass.GetTerminalNumber and GRM.Incass.GetTerminalNumber(ent)or ent:EntIndex();rec.atmName=ent.GetTerminalName and ent:GetTerminalName()or"Банкомат";rec.orderSource=rec.orderSource~=""and rec.orderSource or"atm_payment"
    if GRM.Services and GRM.Services.SaveInvoices then GRM.Services.SaveInvoices()end
end

-- ── личный счёт ───────────────────────────────────────────
handlers.deposit = function(ply, args)
    local E = GRM.Economy
    if not (E and isfunction(E.BankDeposit)) then return false, "Банк недоступен" end
    local amt = math.floor(tonumber(args.amount) or 0)
    if amt <= 0 then return false, "Введите сумму" end
    local ok, res = E.BankDeposit(ply, amt)
    if not ok then
        return false, res == "cd" and "Слишком быстро, повторите" or "Недостаточно наличных"
    end
    -- комиссия терминала уходит в инкасс-ячейку, как и раньше
    hook.Run("GRM_Incass_TerminalDeposit", ply, amt, IsValid(ply._grmATMEnt) and ply._grmATMEnt or nil)
    return true, ("Внесено на счёт: %s"):format(money(amt))
end

handlers.withdraw = function(ply, args)
    local E = GRM.Economy
    if not (E and isfunction(E.BankWithdraw)) then return false, "Банк недоступен" end
    local amt = math.floor(tonumber(args.amount) or 0)
    if amt <= 0 then return false, "Введите сумму" end
    local ok, res = E.BankWithdraw(ply, amt)
    if not ok then
        return false, res == "cd" and "Слишком быстро, повторите" or "Недостаточно средств на счёте"
    end
    return true, ("Снято со счёта: %s"):format(money(amt))
end

handlers.transfer = function(ply, args)
    local E = GRM.Economy
    if not (E and isfunction(E.BankTransfer)) then return false, "Банк недоступен" end
    local amt = math.floor(tonumber(args.amount) or 0)
    local to = tostring(args.target or "")
    if amt <= 0 then return false, "Введите сумму" end
    if to == "" then return false, "Выберите получателя" end
    if not E.BankTransfer(ply, to, amt) then return false, "Перевод не выполнен: проверьте остаток" end
    local tp = GRM.Services and GRM.Services.FindPlayer(to)
    if IsValid(tp) and GRM.Notify then
        GRM.Notify(tp, ("На ваш счёт поступило %s от %s"):format(money(amt), ply:Nick()), 120, 220, 140)
    end
    return true, ("Переведено %s"):format(money(amt))
end

-- ── оплата задолженности ──────────────────────────────────
handlers.pay_fine = function(ply, args)
    local S = GRM.Services
    if not (S and isfunction(S.PayFine)) then return false, "Модуль оплаты недоступен" end
    return S.PayFine(ply, args.id, args.amount, args.source or "auto")
end

handlers.pay_invoice = function(ply, args)
    local S = GRM.Services
    if not (S and isfunction(S.PayInvoice)) then return false, "Модуль оплаты недоступен" end
    local rec=S.InvoiceByID(args.id);local ok,res=S.PayInvoice(ply,args.id,args.amount,args.source or"auto")
    if not ok then return false,res end;stampInvoiceATM(ply,rec)
    return true,("Оплачено: %s"):format(money(res))
end

--- Оплатить всю задолженность разом.
handlers.pay_all = function(ply, args)
    local S = GRM.Services
    local F = GRM.Wanted and GRM.Wanted.Fines
    if not S then return false, "Модуль оплаты недоступен" end
    local src = args.source or "auto"
    local paid, failed = 0, nil

    if F and isfunction(F.For) then
        for _, rec in ipairs(F.For(ply, true)) do
            local ok, res = S.PayFine(ply, rec.id, rec.amount - rec.paid, src)
            if ok then paid = paid + (tonumber(res) or 0) else failed = failed or res end
        end
    end
    for _, rec in ipairs(S.InvoicesFor(ply, true)) do
        local ok,res=S.PayInvoice(ply,rec.id,rec.amount-rec.paid,src)
        if ok then paid=paid+(tonumber(res)or 0);stampInvoiceATM(ply,rec)else failed=failed or res end
    end

    if paid <= 0 then return false, failed or "Задолженности нет" end
    if failed then
        return true, ("Оплачено %s. Остальное не прошло: %s"):format(money(paid), failed)
    end
    return true, ("Задолженность погашена: %s"):format(money(paid))
end

-- ── заказ услуги ──────────────────────────────────────────
--[[ Житель заказывает услугу прямо в банкомате: создаётся счёт от имени
     организации-исполнителя и тут же оплачивается. Если денег нет, счёт
     остаётся неоплаченным — организация увидит заявку в своём кабинете. ]]
handlers.order_service = function(ply, args)
    local S = GRM.Services
    if not S then return false, "Модуль госуслуг недоступен" end
    local svc = S.ServiceByID(args.id)
    if not svc then return false, "Услуга не найдена" end
    if svc.enabled == false then return false, "Услуга временно не оказывается" end

    local atm=IsValid(ply._grmATMEnt)and ply._grmATMEnt or nil;local atmNumber=GRM.Incass and GRM.Incass.GetTerminalNumber and GRM.Incass.GetTerminalNumber(atm)or(IsValid(atm)and atm:EntIndex()or 0);local atmName=IsValid(atm)and atm.GetTerminalName and atm:GetTerminalName()or"Банкомат"
    local rec = {
        id         = S._nextInvoice,
        target     = charKey(ply),
        targetName=ply:GetNWString("GRM_RPName",ply:Nick()),
        issuer     = "система",
        issuerName = "Банкомат",
        faction    = svc.provider,
        serviceID  = svc.id,
        title      = svc.name,
        amount     = svc.price,
        paid       = 0,
        status     = "unpaid",
        issued=os.time(),orderSource="atm",atmNumber=atmNumber,atmName=tostring(atmName),
        note="Заказано жителем через банкомат",
    }
    if rec.amount <= 0 then return false, "Услуга бесплатна: обратитесь напрямую в организацию" end

    S._nextInvoice = S._nextInvoice + 1
    S.Invoices[#S.Invoices + 1] = rec
    S.SaveInvoices()
    hook.Run("GRM_InvoiceIssued", ply, rec)

    -- сразу пробуем оплатить
    local ok, res = S.PayInvoice(ply, rec.id, rec.amount, args.source or "auto")
    if ok then
        return true, ("Услуга «%s» оплачена (%s). Организация уведомлена."):format(svc.name, money(rec.amount))
    end
    return true, ("Счёт №%d на «%s» создан, но не оплачен: %s"):format(rec.id, svc.name, tostring(res))
end

-- ── кабинет организации ───────────────────────────────────
handlers.issue_invoice = function(ply, args)
    local S = GRM.Services
    if not S then return false, "Модуль госуслуг недоступен" end
    local ok, res = S.IssueInvoice(ply, args.target, {
        serviceID = args.serviceID,
        title     = args.title,
        amount    = args.amount,
        note      = args.note,
        -- Организация-исполнитель, в бюджет которой уйдёт доля оплаты.
        -- Для обычного сотрудника поле игнорируется: IssueInvoice подставит
        -- его собственную фракцию. Смысл поля — выбор у суперадмина.
        faction   = ply:IsSuperAdmin() and args.faction or nil,
    })
    if not ok then return false, res end
    return true, ("Счёт №%d выставлен на %s"):format(res.id, money(res.amount))
end

handlers.cancel_invoice = function(ply, args)
    local S = GRM.Services
    if not S then return false, "Модуль госуслуг недоступен" end
    local ok, res = S.CancelInvoice(ply, args.id, args.reason)
    if not ok then return false, res end
    return true, ("Счёт №%d аннулирован"):format(res.id)
end

handlers.upsert_service = function(ply, args)
    local S = GRM.Services
    if not S then return false, "Модуль госуслуг недоступен" end
    local ok, res = S.UpsertService(ply, {
        id = args.id, name = args.name, category = args.category,
        price = args.price, desc = args.desc, enabled = args.enabled,
        -- Исполнитель: у лидера подменится на его же организацию, суперадмин
        -- вправе завести услугу за любую (задача 10).
        provider = args.provider,
    })
    if not ok then return false, res end
    return true, ("Услуга «%s» сохранена (исполнитель: %s)"):format(res.name, tostring(res.provider or "—"))
end

handlers.delete_service = function(ply, args)
    local S = GRM.Services
    if not S then return false, "Модуль госуслуг недоступен" end
    local ok, res = S.DeleteService(ply, args.id)
    if not ok then return false, res end
    return true, ("Услуга «%s» удалена"):format(res.name)
end

handlers.issue_diploma = function(ply, args)
    local D = GRM.Diplomas
    if not D then return false, "Реестр дипломов недоступен" end
    local ok, res = D.Issue(ply, {
        graduate      = args.graduate,
        specialty     = args.specialty,
        qualification = args.qualification,
        level         = args.level,
        form          = args.form,
        grade         = args.grade,
        institution   = args.institution,
        paid          = args.paid == true,
        invoiceID     = args.invoiceID,
        signedBy      = args.signedBy,
        note          = args.note,
    })
    if not ok then return false, res end
    local gp = GRM.Services and GRM.Services.FindPlayer(res.graduate)
    if IsValid(gp) then D.RenderText(res) end
    return true, ("Диплом %s выдан: %s, «%s»"):format(res.number, res.graduateName, res.specialty)
end

handlers.revoke_diploma = function(ply, args)
    local D = GRM.Diplomas
    if not D then return false, "Реестр дипломов недоступен" end
    local ok, res = D.Revoke(ply, args.number, args.reason)
    if not ok then return false, res end
    return true, ("Диплом %s аннулирован"):format(res.number)
end

--- Проверка диплома по номеру — доступна каждому.
handlers.check_diploma = function(ply, args)
    local D = GRM.Diplomas
    if not D then return false, "Реестр дипломов недоступен" end
    local rec = D.ByNumber(args.number)
    if not rec then return false, "Диплом с номером «" .. tostring(args.number) .. "» в реестре не значится" end
    for _, line in ipairs(string.Explode("\n", D.RenderText(rec))) do ply:ChatPrint(line) end
    if rec.revoked then return true, "Диплом найден, но АННУЛИРОВАН — подробности в чате" end
    return true, "Диплом действителен — бланк выведен в чат"
end

-- ── надзор суперадмина ────────────────────────────────────
handlers.admin_set_access = function(ply, args)
    if not ply:IsSuperAdmin() then return false, "Только суперадмин" end
    local S = GRM.Services
    if not S then return false, "Модуль госуслуг недоступен" end
    local ok, res = S.SetAccess(args.faction, {
        canService  = args.canService,
        canInvoice  = args.canInvoice,
        canDiploma  = args.canDiploma,
        maxInvoice  = args.maxInvoice,
        institution = args.institution,
        categories  = args.categories,
    })
    if not ok then return false, res end
    return true, ("Доступы организации «%s» обновлены"):format(tostring(args.faction))
end

handlers.admin_edit_invoice = function(ply, args)
    if not ply:IsSuperAdmin() then return false, "Только суперадмин" end
    local S = GRM.Services
    if not S then return false, "Модуль госуслуг недоступен" end
    local ok, res = S.AdminEditInvoice(ply, args.id, {
        amount = args.amount, title = args.title, status = args.status, note = args.note,
    })
    if not ok then return false, res end
    return true, ("Счёт №%d изменён"):format(res.id)
end

handlers.admin_delete_invoice = function(ply, args)
    if not ply:IsSuperAdmin() then return false, "Только суперадмин" end
    local S = GRM.Services
    if not S then return false, "Модуль госуслуг недоступен" end
    local ok, res = S.DeleteInvoice(ply, args.id)
    if not ok then return false, res end
    return true, ("Счёт №%d удалён из реестра"):format(res.id)
end

handlers.admin_edit_diploma = function(ply, args)
    if not ply:IsSuperAdmin() then return false, "Только суперадмин" end
    local D = GRM.Diplomas
    if not D then return false, "Реестр дипломов недоступен" end
    local ok, res = D.Edit(ply, args.number, {
        specialty = args.specialty, qualification = args.qualification,
        grade = args.grade, note = args.note, level = args.level, form = args.form,
        institution = args.institution, graduateName = args.graduateName,
    })
    if not ok then return false, res end
    return true, ("Диплом %s изменён"):format(res.number)
end

handlers.admin_delete_diploma = function(ply, args)
    if not ply:IsSuperAdmin() then return false, "Только суперадмин" end
    local D = GRM.Diplomas
    if not D then return false, "Реестр дипломов недоступен" end
    local ok, res = D.Delete(ply, args.number)
    if not ok then return false, res end
    return true, ("Диплом %s удалён из реестра"):format(res.number)
end

handlers.admin_restore_diploma = function(ply, args)
    if not ply:IsSuperAdmin() then return false, "Только суперадмин" end
    local D = GRM.Diplomas
    if not D then return false, "Реестр дипломов недоступен" end
    local ok, res = D.Restore(ply, args.number)
    if not ok then return false, res end
    return true, ("Диплом %s восстановлен"):format(res.number)
end

handlers.refresh = function() return true, "" end

net.Receive("GRM_ATM_Act", function(_, ply)
    if not IsValid(ply) then return end
    local action = net.ReadString()
    local args = net.ReadTable() or {}

    local now = CurTime()
    if (nextAct[ply] or 0) > now then return end
    nextAct[ply] = now + A.Config.RateLimit

    -- дистанция: банкомат нельзя дёргать с другого конца карты
    local ent = ply._grmATMEnt
    if IsValid(ent) and ply:GetPos():DistToSqr(ent:GetPos()) > (A.Config.UseRange ^ 2) then
        result(ply, false, "Вы отошли от банкомата")
        return
    end
    local ready, why = A.TerminalReady(ent)
    if not ready then result(ply, false, why) return end

    local h = handlers[action]
    if not h then result(ply, false, "Неизвестная операция") return end

    local ok, msg = h(ply, args)
    if msg and msg ~= "" then result(ply, ok, msg) end
    push(ply)
end)

hook.Add("PlayerDisconnected", "GRM_ATM_Cleanup", function(ply) nextAct[ply] = nil end)

--[[ Банкомат вызывает GRM.ATM.Open напрямую (см. grm_bank_terminal/init.lua).
     Но старые энтити и сторонние модули зовут E.OpenBankTerminal — перенаправляем
     и их, сохранив прежнюю функцию на случай отката. Делаем это после полной
     загрузки, иначе экономика перезапишет подмену своим определением. ]]
grmBootStart("GRM_ATM_HijackBankTerminal", "normal", function()
    local E = GRM.Economy
    if not (E and isfunction(E.OpenBankTerminal)) then return end
    if E._grmLegacyOpenBank then return end
    E._grmLegacyOpenBank = E.OpenBankTerminal
    E.OpenBankTerminal = function(ply, ent) A.Open(ply, ent) end
end)

end -- SERVER

-----------------------------------------------------------------------
-- КЛИЕНТ
-----------------------------------------------------------------------
if CLIENT then

local function theme()
    local T = GRM.UI and GRM.UI.Theme
    if T and T.Colors then return T.Colors end
    -- фолбэк, если тема ещё не загрузилась
    return {
        bg = Color(8, 14, 23, 248), panel = Color(16, 27, 42, 245), panel2 = Color(22, 37, 56, 245),
        header = Color(10, 22, 37, 255), text = Color(225, 238, 247), muted = Color(132, 160, 178),
        cyan = Color(48, 204, 255), green = Color(64, 222, 147), amber = Color(250, 185, 63),
        red = Color(244, 78, 96), purple = Color(174, 98, 255), line = Color(55, 117, 151, 190),
    }
end

surface.CreateFont("GRM_ATM_Title", { font = "Roboto", size = 26, weight = 800, extended = true })
surface.CreateFont("GRM_ATM_Head",  { font = "Roboto", size = 17, weight = 700, extended = true })
surface.CreateFont("GRM_ATM_Body",  { font = "Roboto", size = 15, weight = 500, extended = true })
surface.CreateFont("GRM_ATM_Small", { font = "Roboto", size = 12, weight = 500, extended = true })
surface.CreateFont("GRM_ATM_Num",   { font = "Roboto", size = 21, weight = 800, extended = true })

local snap = {}
local frame

local function act(action, args)
    net.Start("GRM_ATM_Act")
        net.WriteString(action)
        net.WriteTable(args or {})
    net.SendToServer()
end
_G.GRM_ATM_Act = act

local function money(v)
    if GRM.FormatMoney then return GRM.FormatMoney(v) end
    return string.Comma(math.floor(tonumber(v) or 0)) .. " GRM"
end

local function dateOf(ts)
    return os.date("%d.%m.%Y %H:%M", math.floor(tonumber(ts) or os.time()))
end

--[[ Справочники живут на сервере (модули услуг и дипломов серверные),
     поэтому названия категорий и уровней берём из снимка, а не из GRM.* —
     на клиенте этих таблиц просто нет. ]]
local function nameFrom(list, id, fallback)
    for _, v in ipairs(list or {}) do
        if v.id == id then return v.name end
    end
    return fallback or tostring(id or "")
end
local function catName(id)   return nameFrom(snap.categories, id, "Прочее") end
local function levelName(id) return nameFrom(snap.levels, id, "—") end

-- ── строительные блоки ────────────────────────────────────
local function label(parent, text, font, color, x, y, w, h)
    local C = theme()
    local l = vgui.Create("DLabel", parent)
    l:SetPos(x, y) l:SetSize(w or 400, h or 20)
    l:SetText(text) l:SetFont(font or "GRM_ATM_Body")
    l:SetTextColor(color or C.text)
    return l
end

local function button(parent, text, col, w, h)
    local C = theme()
    local b = vgui.Create("DButton", parent)
    b:SetSize(w or 150, h or 30)
    b:SetText(text) b:SetFont("GRM_ATM_Body")
    b:SetTextColor(C.text)
    b.Paint = function(self, bw, bh)
        local c = col or C.panel2
        if not self:IsEnabled() then c = Color(60, 70, 80, 200)
        elseif self:IsHovered() then c = Color(math.min(c.r + 30, 255), math.min(c.g + 30, 255), math.min(c.b + 30, 255), c.a or 255) end
        draw.RoundedBox(5, 0, 0, bw, bh, c)
    end
    return b
end

--[[ Карточка списка.
     Родителя НЕ назначаем: панель уходит в скролл через sc:AddItem(), а он
     сам парентит её в холст (pnlCanvas) и докует сверху. Если создать
     карточку сразу ребёнком DScrollPanel, а потом ещё раз позвать AddItem,
     панель окажется прямым ребёнком скролла в обход холста: раскладка её
     не учитывает, :Clear() не удаляет, а после смерти родителя
     PerformLayoutInternal падает с «Tried to use a NULL Panel!».
     Для обычных панелей-контейнеров родитель передаётся как обычно. ]]
local function card(parent, h)
    local C = theme()
    local isScroll = istable(parent) and isfunction(parent.AddItem)
    local p = vgui.Create("DPanel", (not isScroll) and parent or nil)
    p:SetTall(h or 64)
    p:Dock(TOP) p:DockMargin(0, 0, 0, 6)
    p.Paint = function(_, w, ph)
        draw.RoundedBox(6, 0, 0, w, ph, C.panel2)
        surface.SetDrawColor(C.line)
        surface.DrawOutlinedRect(0, 0, w, ph, 1)
    end
    return p
end

--[[
    Выбор ПЕРСОНАЖА (не сессии). Список приходит в snap.characters и
    включает офлайн: паспорта и составы фракций. Персонажей на сервере
    много, поэтому обычный DComboBox бесполезен — здесь поле поиска
    фильтрует список по имени, ключу и фракции.

    Возвращает панель со :GetKey() и :SetKey(); высота — 56.
]]
local function charPicker(parent, placeholder, w)
    local C = theme()
    local p = vgui.Create("DPanel", parent)
    p:SetSize(w or 300, 56)
    p.Paint = function() end
    p._key = ""

    local list = vgui.Create("DComboBox", p)
    list:SetPos(0, 26) list:SetSize(w or 300, 28)
    list:SetFont("GRM_ATM_Body")
    list:SetValue(placeholder or "Выберите персонажа...")
    list:SetTextColor(C.text)
    list.Paint = function(_, cw, ch)
        draw.RoundedBox(4, 0, 0, cw, ch, Color(12, 20, 32, 245))
        surface.SetDrawColor(C.line)
        surface.DrawOutlinedRect(0, 0, cw, ch, 1)
    end

    local find = vgui.Create("DTextEntry", p)
    find:SetPos(0, 0) find:SetSize(w or 300, 22)
    find:SetFont("GRM_ATM_Small")
    find:SetPlaceholderText("Поиск по имени, фракции или ключу...")
    find.Paint = function(self, ew, eh)
        draw.RoundedBox(4, 0, 0, ew, eh, Color(10, 16, 26, 240))
        surface.SetDrawColor(C.line)
        surface.DrawOutlinedRect(0, 0, ew, eh, 1)
        self:DrawTextEntryText(C.text, C.cyan, C.muted)
    end

    local function fill(filter)
        filter = string.lower(string.Trim(filter or ""))
        list:Clear()
        list:SetValue(placeholder or "Выберите персонажа...")
        local shown = 0
        for _, ch in ipairs(snap.characters or {}) do
            local name = tostring(ch.name or ch.key or "")
            local fac  = tostring(ch.faction or "")
            local hay  = string.lower(name .. " " .. fac .. " " .. tostring(ch.key or ""))
            if filter == "" or string.find(hay, filter, 1, true) then
                local mark = ch.online and "• " or "  "
                local tail = fac ~= "" and ("  [" .. fac .. "]") or ""
                list:AddChoice(mark .. name .. tail, ch.key)
                shown = shown + 1
                if shown >= 150 then break end
            end
        end
        if shown == 0 then list:SetValue("Ничего не найдено") end
    end
    fill("")

    find.OnChange = function(self) fill(self:GetValue()) end
    list.OnSelect = function(_, _, _, data) p._key = tostring(data or "") end

    p.GetKey = function(self) return self._key or "" end
    p.SetKey = function(self, k) self._key = tostring(k or "") end
    p.PerformLayout = function(self, pw)
        find:SetSize(pw, 22)
        list:SetSize(pw, 28)
    end
    return p
end

local function entry(parent, placeholder, numeric, w, h)
    local C = theme()
    local e = vgui.Create("DTextEntry", parent)
    e:SetSize(w or 160, h or 28)
    e:SetFont("GRM_ATM_Body")
    e:SetPlaceholderText(placeholder or "")
    if numeric then e:SetNumeric(true) end
    e.Paint = function(self, ew, eh)
        draw.RoundedBox(4, 0, 0, ew, eh, Color(12, 20, 32, 245))
        surface.SetDrawColor(C.line)
        surface.DrawOutlinedRect(0, 0, ew, eh, 1)
        self:DrawTextEntryText(C.text, C.cyan, C.text)
    end
    return e
end

local function combo(parent, placeholder, w, h)
    local C = theme()
    local c = vgui.Create("DComboBox", parent)
    c:SetSize(w or 200, h or 28)
    c:SetFont("GRM_ATM_Body")
    c:SetValue(placeholder or "")
    c:SetTextColor(C.text)
    c.Paint = function(self, cw, ch)
        draw.RoundedBox(4, 0, 0, cw, ch, Color(12, 20, 32, 245))
        surface.SetDrawColor(C.line)
        surface.DrawOutlinedRect(0, 0, cw, ch, 1)
    end
    return c
end

local function scroll(parent)
    local C = theme()
    local s = vgui.Create("DScrollPanel", parent)
    local bar = s:GetVBar()
    bar:SetWide(8)
    bar.Paint = function(_, w, h) draw.RoundedBox(4, 0, 0, w, h, Color(10, 18, 28, 200)) end
    bar.btnUp.Paint, bar.btnDown.Paint = function() end, function() end
    bar.btnGrip.Paint = function(_, w, h) draw.RoundedBox(4, 0, 0, w, h, C.line) end
    return s
end

local function empty(parent, text)
    local C = theme()
    local p = card(parent, 44)
    p.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, Color(14, 24, 38, 200)) end
    label(p, text, "GRM_ATM_Body", C.muted, 14, 12, 700, 20)
    return p
end

--[[ Раскладка кнопок в карточке: считаем позиции в PerformLayout самой
     карточки, а не в замыканиях у кнопок. Замыкание держит ссылку на
     родителя и срабатывает, когда ширина ещё не готова, — так рождается
     «Tried to use a NULL Panel». ]]
--[[ Прижать кнопки к правому краю карточки.
     Задача 10: раньше функция ЗАТИРАЛА уже назначенный карточке
     PerformLayout — тексты, разложенные по фактической ширине, теряли
     свою раскладку и вылезали за край. Теперь прежний обработчик
     сохраняется и вызывается первым. ]]
local function layoutRight(pnl, buttons, y, gap)
    pnl._btns = buttons
    local prev = pnl.PerformLayout
    pnl.PerformLayout = function(self, w, h)
        if prev then prev(self, w, h) end
        local x = w - 12
        for i = #self._btns, 1, -1 do
            local b = self._btns[i]
            if IsValid(b) then
                x = x - b:GetWide()
                b:SetPos(x, y or 16)
                x = x - (gap or 6)
            end
        end
    end
end

-- ── вкладки ───────────────────────────────────────────────
local tabs = {}

-- Мой счёт
tabs.account = function(body)
    local C = theme()
    local sc = scroll(body) sc:Dock(FILL)

    local head = card(sc, 96)
    label(head, "ЛИЦЕВОЙ СЧЁТ", "GRM_ATM_Small", C.muted, 14, 10, 300, 16)
    label(head, snap.nick or "", "GRM_ATM_Head", C.text, 14, 28, 400, 22)
    label(head, "Наличные: " .. money(snap.cash or 0), "GRM_ATM_Body", C.green, 14, 58, 300, 22)
    label(head, "На счёте: " .. money(snap.bank or 0), "GRM_ATM_Num", C.cyan, 320, 44, 320, 26)
    sc:AddItem(head)

    -- внести / снять
    local ops = card(sc, 96)
    label(ops, "ОПЕРАЦИИ СО СЧЁТОМ", "GRM_ATM_Small", C.muted, 14, 10, 300, 16)
    local amt = entry(ops, "Сумма...", true, 180, 30)
    amt:SetParent(ops) amt:SetPos(14, 36)
    local bDep = button(ops, "Внести", C.green, 150, 30)
    bDep:SetParent(ops) bDep:SetPos(206, 36)
    bDep.DoClick = function()
        act("deposit", { amount = tonumber(amt:GetValue()) or 0 })
        amt:SetValue("")
    end
    local bWd = button(ops, "Снять", C.amber, 150, 30)
    bWd:SetParent(ops) bWd:SetPos(364, 36)
    bWd.DoClick = function()
        act("withdraw", { amount = tonumber(amt:GetValue()) or 0 })
        amt:SetValue("")
    end
    label(ops, "Деньги на счёте не теряются при смерти — в отличие от наличных.",
        "GRM_ATM_Small", C.muted, 14, 72, 600, 16)
    sc:AddItem(ops)

    -- перевод
    local tr = card(sc, 96)
    label(tr, "ПЕРЕВОД НА ДРУГОЙ СЧЁТ", "GRM_ATM_Small", C.muted, 14, 10, 300, 16)
    local who = combo(tr, "Получатель...", 260, 30)
    who:SetParent(tr) who:SetPos(14, 36)
    for _, p in ipairs(snap.players or {}) do who:AddChoice(p.nick, p.key) end
    local tamt = entry(tr, "Сумма...", true, 150, 30)
    tamt:SetParent(tr) tamt:SetPos(286, 36)
    local bTr = button(tr, "Перевести", C.cyan, 150, 30)
    bTr:SetParent(tr) bTr:SetPos(448, 36)
    bTr.DoClick = function()
        local _, key = who:GetSelected()
        if not key then return end
        act("transfer", { target = key, amount = tonumber(tamt:GetValue()) or 0 })
        tamt:SetValue("")
    end
    label(tr, "Списывается со счёта, зачисляется на счёт получателя.",
        "GRM_ATM_Small", C.muted, 14, 72, 600, 16)
    sc:AddItem(tr)
end

-- Задолженность
tabs.debt = function(body)
    local C = theme()
    local sc = scroll(body) sc:Dock(FILL)
    local d = snap.debt or { fines = 0, invoices = 0, total = 0 }

    local head = card(sc, 86)
    label(head, "ЗАДОЛЖЕННОСТЬ", "GRM_ATM_Small", C.muted, 14, 10, 300, 16)
    label(head, "Штрафы: " .. money(d.fines or 0), "GRM_ATM_Body", C.amber, 14, 32, 260, 20)
    label(head, "Счета: " .. money(d.invoices or 0), "GRM_ATM_Body", C.purple, 14, 56, 260, 20)
    label(head, "Итого: " .. money(d.total or 0), "GRM_ATM_Num",
        (d.total or 0) > 0 and C.red or C.green, 300, 40, 300, 26)
    local bAll = button(head, "Оплатить всё", C.green, 170, 32)
    bAll:SetParent(head)
    bAll:SetEnabled((d.total or 0) > 0)
    bAll.DoClick = function() act("pay_all", { source = "auto" }) end
    layoutRight(head, { bAll }, 28)
    sc:AddItem(head)

    -- штрафы
    local hdr1 = card(sc, 30)
    hdr1.Paint = function() end
    label(hdr1, "НЕОПЛАЧЕННЫЕ ШТРАФЫ", "GRM_ATM_Head", C.amber, 4, 4, 400, 22)
    sc:AddItem(hdr1)

    if #(snap.fines or {}) == 0 then
        sc:AddItem(empty(sc, "Неоплаченных штрафов нет."))
    else
        for _, f in ipairs(snap.fines) do
            local due = (f.amount or 0) - (f.paid or 0)
            local c = card(sc, 70)
            label(c, ("Штраф №%d"):format(f.id or 0), "GRM_ATM_Head", C.text, 14, 8, 200, 20)
            label(c, tostring(f.reason or ""), "GRM_ATM_Small", C.muted, 14, 30, 520, 16)
            label(c, ("Выписал: %s | %s"):format(tostring(f.issuerName or "?"), dateOf(f.issued)),
                "GRM_ATM_Small", C.muted, 14, 48, 520, 16)
            label(c, money(due), "GRM_ATM_Head", C.amber, 560, 24, 160, 22)
            local b = button(c, "Оплатить", C.green, 130, 30)
            b:SetParent(c)
            b.DoClick = function() act("pay_fine", { id = f.id, amount = due, source = "auto" }) end
            layoutRight(c, { b }, 20)
            sc:AddItem(c)
        end
    end

    -- счета
    local hdr2 = card(sc, 34)
    hdr2.Paint = function() end
    label(hdr2, "СЧЕТА ЗА УСЛУГИ", "GRM_ATM_Head", C.purple, 4, 8, 400, 22)
    sc:AddItem(hdr2)

    local anyInv = false
    for _, inv in ipairs(snap.invoices or {}) do
        if inv.status == "unpaid" then anyInv = true end
    end
    if not anyInv then
        sc:AddItem(empty(sc, "Неоплаченных счетов нет."))
    end
    for _, inv in ipairs(snap.invoices or {}) do
        local due = (inv.amount or 0) - (inv.paid or 0)
        local closed = inv.status ~= "unpaid"
        local c = card(sc, 70)
        local col = closed and C.muted or C.text
        label(c, ("Счёт №%d — %s"):format(inv.id or 0, tostring(inv.title or "")), "GRM_ATM_Head", col, 14, 8, 460, 20)
        label(c, ("Организация: %s | %s"):format(tostring(inv.faction ~= "" and inv.faction or "—"), dateOf(inv.issued)),
            "GRM_ATM_Small", C.muted, 14, 30, 520, 16)
        if inv.note and inv.note ~= "" then
            label(c, tostring(inv.note), "GRM_ATM_Small", C.muted, 14, 48, 520, 16)
        end
        if closed then
            label(c, inv.status == "paid" and "ОПЛАЧЕН" or "АННУЛИРОВАН", "GRM_ATM_Body",
                inv.status == "paid" and C.green or C.red, 560, 26, 160, 20)
        else
            label(c, money(due), "GRM_ATM_Head", C.purple, 560, 24, 160, 22)
            local b = button(c, "Оплатить", C.green, 130, 30)
            b:SetParent(c)
            b.DoClick = function() act("pay_invoice", { id = inv.id, amount = due, source = "auto" }) end
            layoutRight(c, { b }, 20)
        end
        sc:AddItem(c)
    end
end

-- Госуслуги
tabs.services = function(body)
    local C = theme()
    local top = vgui.Create("DPanel", body)
    top:Dock(TOP) top:SetTall(40)
    top.Paint = function() end

    --[[ Задача 10: витрина теперь фильтруется не только по категории, но и
         по исполнителю — игрок должен видеть, какая организация оказывает
         услугу и заказать её именно у неё. Карточка перестала быть
         фиксированной: цена и кнопка привязаны к правому краю, а название и
         описание переносятся по строкам вместо обрезки. ]]
    local catFilter, provFilter = "", ""

    local cat = combo(top, "Все категории", 240, 30)
    cat:SetParent(top) cat:SetPos(0, 4)
    cat:AddChoice("Все категории", "")
    for _, c in ipairs(snap.categories or {}) do cat:AddChoice(c.name, c.id) end

    local prov = combo(top, "Любой исполнитель", 240, 30)
    prov:SetParent(top) prov:SetPos(252, 4)
    prov:AddChoice("Любой исполнитель", "")
    -- Исполнитель идентифицируется именем фракции: в snap.providers и в
    -- поле service.provider хранится одно и то же значение.
    for _, p in ipairs(snap.providers or {}) do
        local n = tostring(p.name or "")
        if n ~= "" then prov:AddChoice(n, n) end
    end

    local sc = scroll(body) sc:Dock(FILL)

    local function fill()
        sc:Clear()
        local shown = 0
        for _, s in ipairs(snap.services or {}) do
            local sProv = tostring(s.provider or "")
            local okCat  = (catFilter  == "") or (s.category == catFilter)
            local okProv = (provFilter == "") or (sProv == provFilter)
            if okCat and okProv then
                shown = shown + 1
                local c = card(sc, 84)

                local name = label(c, tostring(s.name or ""), "GRM_ATM_Head", C.text, 14, 8, 400, 20)
                name:SetWrap(true) name:SetAutoStretchVertical(true) name:SetContentAlignment(7)

                local meta = label(c, ("Категория: %s     Исполнитель: %s"):format(
                    catName(s.category),
                    sProv ~= "" and sProv or "не указан"),
                    "GRM_ATM_Small", C.cyan, 14, 30, 400, 16)
                meta:SetWrap(true) meta:SetAutoStretchVertical(true) meta:SetContentAlignment(7)

                local desc
                if s.desc and s.desc ~= "" then
                    desc = label(c, tostring(s.desc), "GRM_ATM_Small", C.muted, 14, 48, 400, 16)
                    desc:SetWrap(true) desc:SetAutoStretchVertical(true) desc:SetContentAlignment(7)
                end

                local price = label(c, money(s.price or 0), "GRM_ATM_Head", C.cyan, 0, 12, 160, 22)
                price:SetContentAlignment(9) -- правый верх

                local b = button(c, "Заказать", C.green, 130, 30)
                b:SetParent(c)
                b.DoClick = function()
                    Derma_Query(("Заказать услугу «%s» за %s?\nИсполнитель: %s"):format(
                        tostring(s.name), money(s.price or 0), sProv ~= "" and sProv or "не указан"),
                        "Подтверждение",
                        "Да, оплатить", function() act("order_service", { id = s.id, source = "auto" }) end,
                        "Отмена", function() end)
                end

                c.PerformLayout = function(self, w)
                    local pad, rightW = 14, 170
                    local textW = math.max(120, w - pad * 2 - rightW)

                    local y = 8
                    for _, el in ipairs({ name, meta, desc }) do
                        if IsValid(el) then
                            el:SetPos(pad, y)
                            el:SetWide(textW)
                            el:InvalidateLayout(true)
                            el:SizeToContentsY()
                            y = y + math.max(16, el:GetTall() or 16) + 2
                        end
                    end

                    price:SetPos(w - pad - 160, 10)
                    b:SetPos(w - pad - 130, math.max(44, y - 34))

                    local need = math.max(y + 10, 84)
                    if math.abs((self:GetTall() or 0) - need) > 1 then self:SetTall(need) end
                end

                sc:AddItem(c)
            end
        end
        if shown == 0 then
            sc:AddItem(empty(sc, "По выбранным фильтрам услуг нет."))
        end
    end

    cat.OnSelect  = function(_, _, _, data) catFilter  = data or "" fill() end
    prov.OnSelect = function(_, _, _, data) provFilter = data or "" fill() end
    fill()
end

-- Дипломы
tabs.diplomas = function(body)
    local C = theme()
    local sc = scroll(body) sc:Dock(FILL)

    local chk = card(sc, 84)
    label(chk, "ПРОВЕРКА ДИПЛОМА ПО РЕЕСТРУ", "GRM_ATM_Small", C.muted, 14, 10, 400, 16)
    local num = entry(chk, "Номер бланка, например ГД-2026-000123", false, 340, 30)
    num:SetParent(chk) num:SetPos(14, 34)
    local bChk = button(chk, "Проверить", C.cyan, 150, 30)
    bChk:SetParent(chk) bChk:SetPos(366, 34)
    bChk.DoClick = function()
        local v = string.Trim(num:GetValue() or "")
        if v == "" then return end
        act("check_diploma", { number = v })
    end
    sc:AddItem(chk)

    local hdr = card(sc, 34)
    hdr.Paint = function() end
    label(hdr, "МОИ ДИПЛОМЫ", "GRM_ATM_Head", C.green, 4, 8, 400, 22)
    sc:AddItem(hdr)

    if #(snap.diplomas or {}) == 0 then
        sc:AddItem(empty(sc, "У вас пока нет дипломов. Обучение проходят в образовательных учреждениях."))
    end
    for _, d in ipairs(snap.diplomas or {}) do
        local c = card(sc, 92)
        local col = d.revoked and C.red or C.text
        label(c, tostring(d.number or ""), "GRM_ATM_Head", col, 14, 8, 260, 20)
        label(c, tostring(d.institution or ""), "GRM_ATM_Body", C.cyan, 14, 30, 460, 18)
        label(c, ("Специальность: %s"):format(tostring(d.specialty or "—")), "GRM_ATM_Small", C.muted, 14, 50, 460, 16)
        label(c, ("Квалификация: %s | %s | %s"):format(
            tostring(d.qualification ~= "" and d.qualification or "—"),
            levelName(d.level),
            d.paid and "платно" or "бесплатно"), "GRM_ATM_Small", C.muted, 14, 68, 520, 16)
        label(c, dateOf(d.issued), "GRM_ATM_Small", C.muted, 560, 12, 160, 16)
        if d.revoked then
            label(c, "АННУЛИРОВАН", "GRM_ATM_Body", C.red, 560, 40, 160, 20)
        else
            label(c, "ДЕЙСТВИТЕЛЕН", "GRM_ATM_Body", C.green, 560, 40, 160, 20)
        end
        sc:AddItem(c)
    end
end

-- Кабинет организации
tabs.org = function(body)
    local C = theme()
    local org = snap.org
    if not org then
        local sc = scroll(body) sc:Dock(FILL)
        sc:AddItem(empty(sc, "Вы не состоите в организации с доступом к услугам."))
        return
    end
    local acc = snap.access or {}

    local sheet = vgui.Create("DPropertySheet", body)
    sheet:Dock(FILL)
    sheet:SetFadeTime(0)
    sheet.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, Color(0, 0, 0, 0)) end

    local function page()
        local p = vgui.Create("DPanel", sheet)
        p.Paint = function() end
        return p
    end

    -- Выставление счетов
    local pInv = page()
    sheet:AddSheet("Счета", pInv, "icon16/report.png")
    do
        local sc = scroll(pInv) sc:Dock(FILL)
        if acc.canInvoice or snap.isSuper then
            --[[ Форма счёта. Задача 10: каждое поле подписано, добавлена
                 ячейка исполнителя (получателя денег), сумма явно помечена
                 как «Сумма к оплате, GRM» — раньше по плейсхолдеру «Сумма...»
                 было непонятно, куда её вписывать. Раскладка считается от
                 фактической ширины, поэтому поля не режутся. ]]
            local f = card(sc, 250)
            label(f, "ВЫСТАВИТЬ СЧЁТ", "GRM_ATM_Small", C.muted, 14, 10, 300, 16)

            local lWho = label(f, "Плательщик", "GRM_ATM_Small", C.muted, 14, 30, 200, 14)
            local who  = charPicker(f, "Начните вводить имя или выберите...", 260)
            who:SetParent(f)

            local lSvc = label(f, "Услуга из каталога", "GRM_ATM_Small", C.muted, 14, 30, 200, 14)
            local svc  = combo(f, "— без привязки —", 260, 28)
            svc:SetParent(f)
            svc:AddChoice("— без привязки —", "")
            for _, s in ipairs(org.services or {}) do
                svc:AddChoice(("%s (%s)"):format(s.name, money(s.price or 0)), s.id)
            end

            -- ── ЯЧЕЙКА ИСПОЛНИТЕЛЯ ────────────────────────────
            local lProv = label(f, "Исполнитель (кому уйдут деньги)", "GRM_ATM_Small", C.muted, 14, 30, 300, 14)
            local provFixed = tostring(org.name or "")
            local provCombo, provLabel
            if snap.isSuper then
                provCombo = combo(f, provFixed ~= "" and provFixed or "Выберите организацию...", 260, 28)
                provCombo:SetParent(f)
                local has = false
                for _, p in ipairs(snap.providers or {}) do
                    if p.canInvoice then
                        provCombo:AddChoice(p.name, p.name)
                        if p.name == provFixed then has = true end
                    end
                end
                if provFixed ~= "" and not has then provCombo:AddChoice(provFixed, provFixed) end
                if provFixed ~= "" then provCombo:SetValue(provFixed) end
            else
                provLabel = label(f, provFixed ~= "" and provFixed or "—", "GRM_ATM_Body", C.cyan, 14, 30, 260, 20)
            end

            local lTitle = label(f, "Назначение платежа", "GRM_ATM_Small", C.muted, 14, 30, 200, 14)
            local title  = entry(f, "За что выставлен счёт", false, 260, 28)
            title:SetParent(f)
            local lAmt = label(f, "Сумма к оплате, GRM", "GRM_ATM_Small", C.muted, 14, 30, 200, 14)
            local amt  = entry(f, "0", true, 150, 28)
            amt:SetParent(f)

            svc.OnSelect = function(_, _, _, data)
                for _, s in ipairs(org.services or {}) do
                    if s.id == data then
                        if string.Trim(title:GetValue() or "") == "" then title:SetValue(s.name) end
                        amt:SetValue(tostring(s.price or 0))
                        -- Услуга задаёт исполнителя: платит-то плательщик ей
                        if IsValid(provCombo) and s.provider and s.provider ~= "" then
                            provCombo:SetValue(s.provider)
                        end
                    end
                end
            end

            local lNote = label(f, "Примечание (необязательно)", "GRM_ATM_Small", C.muted, 14, 30, 260, 14)
            local note  = entry(f, "Комментарий для плательщика", false, 260, 28)
            note:SetParent(f)
            local bIss = button(f, "Выставить счёт", C.green, 170, 28)
            bIss:SetParent(f)
            local lim = label(f, (acc.maxInvoice and acc.maxInvoice > 0)
                    and ("Предел суммы одного счёта: %s"):format(money(acc.maxInvoice))
                    or "Предел суммы счёта не установлен",
                "GRM_ATM_Small", C.muted, 14, 30, 300, 14)

            f.PerformLayout = function(self, w)
                local pad, gap = 14, 12
                local colW = math.max(150, math.floor((w - pad * 2 - gap) / 2))
                local y = 30
                lWho:SetPos(pad, y) lWho:SetSize(colW, 14)
                lSvc:SetPos(pad + colW + gap, y) lSvc:SetSize(colW, 14)
                y = y + 16
                who:SetPos(pad, y) who:SetSize(colW, 28)
                svc:SetPos(pad + colW + gap, y) svc:SetSize(colW, 28)
                y = y + 34
                lProv:SetPos(pad, y) lProv:SetSize(colW, 14)
                lTitle:SetPos(pad + colW + gap, y) lTitle:SetSize(colW, 14)
                y = y + 16
                if IsValid(provCombo) then provCombo:SetPos(pad, y) provCombo:SetSize(colW, 28) end
                if IsValid(provLabel) then provLabel:SetPos(pad, y) provLabel:SetSize(colW, 20) end
                title:SetPos(pad + colW + gap, y) title:SetSize(colW, 28)
                y = y + 34
                lAmt:SetPos(pad, y) lAmt:SetSize(colW, 14)
                lNote:SetPos(pad + colW + gap, y) lNote:SetSize(colW, 14)
                y = y + 16
                amt:SetPos(pad, y) amt:SetSize(colW, 28)
                note:SetPos(pad + colW + gap, y) note:SetSize(colW, 28)
                y = y + 36
                lim:SetPos(pad, y + 8) lim:SetSize(math.max(120, w - pad * 2 - 182), 14)
                bIss:SetPos(w - pad - 170, y) bIss:SetSize(170, 28)
                local need = y + 28 + 14
                if math.abs((self:GetTall() or 0) - need) > 1 then self:SetTall(need) end
            end

            bIss.DoClick = function()
                local key = who:GetKey()
                if not key or key == "" then
                    notification.AddLegacy("Выберите плательщика", NOTIFY_ERROR, 3)
                    return
                end
                local sum = tonumber(amt:GetValue()) or 0
                if sum <= 0 then
                    notification.AddLegacy("Укажите сумму к оплате", NOTIFY_ERROR, 3)
                    return
                end
                local prov = provFixed
                if IsValid(provCombo) then
                    local txt, data = provCombo:GetSelected()
                    prov = tostring(data or txt or provCombo:GetValue() or "")
                end
                local _, sid = svc:GetSelected()
                act("issue_invoice", {
                    target = key, serviceID = sid or "",
                    title = title:GetValue(), amount = sum,
                    note = note:GetValue(), faction = prov,
                })
                title:SetValue("") amt:SetValue("") note:SetValue("")
            end
            sc:AddItem(f)
        else
            sc:AddItem(empty(sc, "Организации не выдан доступ на выставление счетов."))
        end

        local hdr = card(sc, 34) hdr.Paint = function() end
        label(hdr, "ВЫСТАВЛЕННЫЕ СЧЕТА", "GRM_ATM_Head", C.purple, 4, 8, 400, 22)
        sc:AddItem(hdr)

        if #(org.invoices or {}) == 0 then sc:AddItem(empty(sc, "Счетов пока нет.")) end
        for _, inv in ipairs(org.invoices or {}) do
            local c = card(sc, 68)
            local stCol = inv.status == "paid" and C.green or (inv.status == "cancelled" and C.red or C.amber)
            label(c, ("№%d — %s"):format(inv.id or 0, tostring(inv.title or "")), "GRM_ATM_Head", C.text, 14, 8, 420, 20)
            label(c, ("Плательщик: %s | %s"):format(tostring(inv.targetName or "?"), dateOf(inv.issued)),
                "GRM_ATM_Small", C.muted, 14, 30, 460, 16)
            label(c, ("Выставил: %s"):format(tostring(inv.issuerName or "?")), "GRM_ATM_Small", C.muted, 14, 46, 460, 16)
            label(c, money(inv.amount or 0), "GRM_ATM_Body", C.text, 480, 14, 140, 20)
            label(c, inv.status == "paid" and "ОПЛАЧЕН" or (inv.status == "cancelled" and "АННУЛИРОВАН" or "НЕ ОПЛАЧЕН"),
                "GRM_ATM_Small", stCol, 480, 36, 140, 16)
            if inv.status == "unpaid" then
                local b = button(c, "Аннулировать", C.red, 150, 28)
                b:SetParent(c)
                b.DoClick = function()
                    Derma_StringRequest("Аннулирование счёта", "Причина:", "", function(txt)
                        act("cancel_invoice", { id = inv.id, reason = txt })
                    end)
                end
                layoutRight(c, { b }, 20)
            end
            sc:AddItem(c)
        end
    end

    -- Каталог услуг
    local pSrv = page()
    sheet:AddSheet("Каталог услуг", pSrv, "icon16/basket.png")
    do
        local sc = scroll(pSrv) sc:Dock(FILL)
        if (acc.canService or snap.isSuper) and (snap.isLeader or snap.isSuper) then
            --[[ Форма услуги. Задача 10: добавлена ЯВНАЯ ячейка исполнителя.
                 Раньше исполнитель нигде не показывался — игрок не понимал,
                 от чьего имени заводится услуга и куда пойдут деньги.
                 Правило простое и написано прямо в форме:
                   • сотрудник/лидер — исполнитель это его организация, поле
                     показано, но заблокировано;
                   • суперадмин — выбирает организацию из выпадающего списка. ]]
            local f = card(sc, 196)
            label(f, "ДОБАВИТЬ / ИЗМЕНИТЬ УСЛУГУ", "GRM_ATM_Small", C.muted, 14, 10, 300, 16)

            local lNm  = label(f, "Название", "GRM_ATM_Small", C.muted, 14, 32, 200, 14)
            local nm   = entry(f, "Например: Выдача лицензии на оружие", false, 260, 28)
            nm:SetParent(f)
            local lCat = label(f, "Категория", "GRM_ATM_Small", C.muted, 14, 32, 200, 14)
            local cat  = combo(f, "Выберите категорию...", 220, 28)
            cat:SetParent(f)
            for _, c in ipairs(snap.categories or {}) do cat:AddChoice(c.name, c.id) end
            local lPr  = label(f, "Цена, GRM", "GRM_ATM_Small", C.muted, 14, 32, 200, 14)
            local pr   = entry(f, "0", true, 140, 28)
            pr:SetParent(f)

            -- ── ЯЧЕЙКА ИСПОЛНИТЕЛЯ ────────────────────────────
            local lProv = label(f, "Исполнитель услуги", "GRM_ATM_Small", C.muted, 14, 32, 260, 14)
            local provFixed = tostring(org.name or "")
            local provCombo, provLabel
            if snap.isSuper then
                provCombo = combo(f, provFixed ~= "" and provFixed or "Выберите организацию...", 260, 28)
                provCombo:SetParent(f)
                local has = false
                for _, p in ipairs(snap.providers or {}) do
                    provCombo:AddChoice(p.name, p.name)
                    if p.name == provFixed then has = true end
                end
                if provFixed ~= "" and not has then provCombo:AddChoice(provFixed, provFixed) end
                if provFixed ~= "" then provCombo:SetValue(provFixed) end
            else
                provLabel = label(f, provFixed ~= "" and provFixed or "—",
                    "GRM_ATM_Body", C.cyan, 14, 32, 260, 20)
            end
            local hint = label(f, snap.isSuper
                    and "Суперадмин: услугу можно завести за любую организацию из списка."
                    or "Услуга заводится от имени вашей организации — сменить исполнителя нельзя.",
                "GRM_ATM_Small", C.muted, 14, 32, 520, 14)

            local lDs = label(f, "Описание", "GRM_ATM_Small", C.muted, 14, 32, 200, 14)
            local ds  = entry(f, "Что входит в услугу", false, 480, 28)
            ds:SetParent(f)
            local bAdd = button(f, "Сохранить услугу", C.green, 170, 28)
            bAdd:SetParent(f)

            -- Абсолютные координаты резали правый край на узком теле окна:
            -- пересчитываем от фактической ширины карточки.
            f.PerformLayout = function(self, w)
                local pad = 14
                local prW = 130
                local nmW = math.max(140, math.floor((w - pad * 2 - 12 * 2 - prW) * 0.52))
                local catW = math.max(120, w - pad * 2 - 12 * 2 - prW - nmW)
                local y = 30
                lNm:SetPos(pad, y)                    lNm:SetSize(nmW, 14)
                lCat:SetPos(pad + nmW + 12, y)        lCat:SetSize(catW, 14)
                lPr:SetPos(pad + nmW + catW + 24, y)  lPr:SetSize(prW, 14)
                y = y + 16
                nm:SetPos(pad, y)                     nm:SetSize(nmW, 28)
                cat:SetPos(pad + nmW + 12, y)         cat:SetSize(catW, 28)
                pr:SetPos(pad + nmW + catW + 24, y)   pr:SetSize(prW, 28)
                y = y + 34
                lProv:SetPos(pad, y) lProv:SetSize(math.max(160, w - pad * 2), 14)
                y = y + 16
                local provW = math.max(180, math.min(320, w - pad * 2))
                if IsValid(provCombo) then provCombo:SetPos(pad, y) provCombo:SetSize(provW, 28) end
                if IsValid(provLabel) then provLabel:SetPos(pad, y) provLabel:SetSize(provW, 20) end
                hint:SetPos(pad + provW + 12, y + 6)
                hint:SetSize(math.max(80, w - pad * 2 - provW - 12), 14)
                y = y + 34
                lDs:SetPos(pad, y) lDs:SetSize(math.max(160, w - pad * 2), 14)
                y = y + 16
                local btnW = 170
                ds:SetPos(pad, y) ds:SetSize(math.max(160, w - pad * 2 - btnW - 12), 28)
                bAdd:SetPos(w - pad - btnW, y) bAdd:SetSize(btnW, 28)
                local need = y + 28 + 14
                if math.abs((self:GetTall() or 0) - need) > 1 then self:SetTall(need) end
            end

            bAdd.DoClick = function()
                local _, cid = cat:GetSelected()
                local prov = provFixed
                if IsValid(provCombo) then
                    local txt, data = provCombo:GetSelected()
                    prov = tostring(data or txt or provCombo:GetValue() or "")
                end
                if string.Trim(prov) == "" then
                    notification.AddLegacy("Выберите исполнителя услуги", NOTIFY_ERROR, 3)
                    return
                end
                if string.Trim(nm:GetValue() or "") == "" then
                    notification.AddLegacy("Введите название услуги", NOTIFY_ERROR, 3)
                    return
                end
                if not cid then
                    notification.AddLegacy("Выберите категорию услуги", NOTIFY_ERROR, 3)
                    return
                end
                act("upsert_service", {
                    name = nm:GetValue(), category = cid or "other",
                    price = tonumber(pr:GetValue()) or 0, desc = ds:GetValue(),
                    enabled = true, provider = prov,
                })
                nm:SetValue("") pr:SetValue("") ds:SetValue("")
            end
            sc:AddItem(f)
        else
            sc:AddItem(empty(sc, "Каталогом услуг управляет руководитель организации с доступом на услуги."))
        end

        if #(org.services or {}) == 0 then sc:AddItem(empty(sc, "В каталоге организации пока нет услуг.")) end
        for _, s in ipairs(org.services or {}) do
            local c = card(sc, 84)
            local lName = label(c, tostring(s.name or ""), "GRM_ATM_Head",
                s.enabled ~= false and C.text or C.muted, 14, 8, 420, 20)
            local lMeta = label(c, ("%s | %s"):format(
                catName(s.category),
                money(s.price or 0)), "GRM_ATM_Small", C.muted, 14, 30, 420, 16)
            -- Исполнитель виден в каждой строке: у суперадмина в каталоге
            -- могут лежать услуги разных организаций.
            local lProv = label(c, ("Исполнитель: %s"):format(tostring(s.provider or org.name or "—")),
                "GRM_ATM_Small", C.cyan, 14, 46, 420, 16)
            local lDesc
            if s.desc and s.desc ~= "" then
                lDesc = label(c, tostring(s.desc), "GRM_ATM_Small", C.muted, 14, 62, 460, 16)
            end
            c.PerformLayout = function(self, w)
                local right = math.max(160, w - 300)
                lName:SetSize(right, 20)
                lMeta:SetSize(right, 16)
                lProv:SetSize(right, 16)
                if IsValid(lDesc) then lDesc:SetSize(math.max(160, w - 28), 16) end
                local need = (IsValid(lDesc) and 62 + 16 or 46 + 16) + 12
                if math.abs((self:GetTall() or 0) - need) > 1 then self:SetTall(need) end
            end
            if snap.isLeader or snap.isSuper then
                local bOff = button(c, s.enabled ~= false and "Отключить" or "Включить", C.amber, 130, 28)
                bOff:SetParent(c)
                bOff.DoClick = function()
                    act("upsert_service", {
                        id = s.id, name = s.name, category = s.category,
                        price = s.price, desc = s.desc, enabled = not (s.enabled ~= false),
                        -- без исполнителя суперадминская правка чужой услуги
                        -- переписала бы её на «Администрацию»
                        provider = s.provider or org.name,
                    })
                end
                local bDel = button(c, "Удалить", C.red, 110, 28)
                bDel:SetParent(c)
                bDel.DoClick = function()
                    Derma_Query(("Удалить услугу «%s»?"):format(tostring(s.name)), "Подтверждение",
                        "Удалить", function() act("delete_service", { id = s.id }) end,
                        "Отмена", function() end)
                end
                layoutRight(c, { bOff, bDel }, 18)
            end
            sc:AddItem(c)
        end
    end

    -- Дипломы: банкомат — это касса, а не деканат.
    -- Выписка бланков переехала в рабочее место учреждения образования:
    -- вкладка «Учреждение образования» в меню фракций и компьютер
    -- grm_comp_education. Здесь остаётся только денежная часть и справка.
    if acc.canDiploma or snap.isSuper then
        local pDip = page()
        sheet:AddSheet("Дипломы", pDip, "icon16/user_suit.png")
        local sc = scroll(pDip) sc:Dock(FILL)

        local info = card(sc, 118)
        local t1 = label(info, "ВЫПИСКА ДИПЛОМОВ ЗДЕСЬ НЕ ВЕДЁТСЯ", "GRM_ATM_Head", C.amber or C.cyan, 14, 10, 460, 22)
        local t2 = label(info, "Банкомат принимает оплату обучения и проверяет бланки по реестру.",
            "GRM_ATM_Small", C.muted, 14, 36, 620, 16)
        local t3 = label(info, "Бланк выписывают в учреждении образования: компьютер деканата",
            "GRM_ATM_Small", C.muted, 14, 56, 620, 16)
        local t4 = label(info, "или вкладка «Учреждение образования» в меню фракций.",
            "GRM_ATM_Small", C.muted, 14, 76, 620, 16)
        info.PerformLayout = function(_, w)
            local ww = math.max(200, w - 28)
            t1:SetSize(ww, 22) t2:SetSize(ww, 16) t3:SetSize(ww, 16) t4:SetSize(ww, 16)
        end
        sc:AddItem(info)

        local hdr = card(sc, 34) hdr.Paint = function() end
        label(hdr, "ВЫДАННЫЕ ДИПЛОМЫ УЧРЕЖДЕНИЯ", "GRM_ATM_Head", C.green, 4, 8, 460, 22)
        sc:AddItem(hdr)

        if #(org.diplomas or {}) == 0 then sc:AddItem(empty(sc, "Учреждение ещё не выдавало дипломов.")) end
        for _, d in ipairs(org.diplomas or {}) do
            local c = card(sc, 62)
            local lNum = label(c, tostring(d.number or ""), "GRM_ATM_Body", d.revoked and C.red or C.text, 14, 8, 220, 20)
            local lWho = label(c, ("%s — %s"):format(tostring(d.graduateName or "?"), tostring(d.specialty or "")),
                "GRM_ATM_Small", C.muted, 14, 30, 420, 16)
            local lDate = label(c, dateOf(d.issued), "GRM_ATM_Small", C.muted, 0, 12, 150, 16)
            local lStat = label(c, d.revoked and "АННУЛИРОВАН" or "ДЕЙСТВИТЕЛЕН", "GRM_ATM_Small",
                d.revoked and C.red or C.green, 0, 32, 150, 16)
            c.PerformLayout = function(_, w)
                local right = math.max(140, w - 170)
                lNum:SetSize(math.max(120, right), 20)
                lWho:SetSize(math.max(120, right), 16)
                lDate:SetPos(w - 158, 12) lDate:SetSize(150, 16)
                lStat:SetPos(w - 158, 32) lStat:SetSize(150, 16)
            end
            sc:AddItem(c)
        end
    end
end

-- Надзор (суперадмин)
tabs.admin = function(body)
    local C = theme()
    local ad = snap.admin
    if not ad then
        local sc = scroll(body) sc:Dock(FILL)
        sc:AddItem(empty(sc, "Раздел доступен только суперадминистратору."))
        return
    end

    local sheet = vgui.Create("DPropertySheet", body)
    sheet:Dock(FILL)
    sheet:SetFadeTime(0)
    local function page()
        local p = vgui.Create("DPanel", sheet)
        p.Paint = function() end
        return p
    end

    -- Доступы организаций
    local pAcc = page()
    sheet:AddSheet("Доступы организаций", pAcc, "icon16/key.png")
    do
        local sc = scroll(pAcc) sc:Dock(FILL)
        if #(ad.factions or {}) == 0 then sc:AddItem(empty(sc, "Фракций нет.")) end
        for _, fr in ipairs(ad.factions or {}) do
            local c = card(sc, 118)
            label(c, tostring(fr.name or ""), "GRM_ATM_Head", C.cyan, 14, 8, 320, 20)

            local chkS = vgui.Create("DCheckBoxLabel", c)
            chkS:SetPos(14, 34) chkS:SetSize(200, 18)
            chkS:SetText("Оказание услуг") chkS:SetFont("GRM_ATM_Small")
            chkS:SetTextColor(C.text) chkS:SetValue(fr.canService == true)

            local chkI = vgui.Create("DCheckBoxLabel", c)
            chkI:SetPos(220, 34) chkI:SetSize(220, 18)
            chkI:SetText("Выставление счетов") chkI:SetFont("GRM_ATM_Small")
            chkI:SetTextColor(C.text) chkI:SetValue(fr.canInvoice == true)

            local chkD = vgui.Create("DCheckBoxLabel", c)
            chkD:SetPos(450, 34) chkD:SetSize(220, 18)
            chkD:SetText("Выдача дипломов") chkD:SetFont("GRM_ATM_Small")
            chkD:SetTextColor(C.text) chkD:SetValue(fr.canDiploma == true)

            label(c, "Официальное название учреждения", "GRM_ATM_Small", C.muted, 14, 58, 300, 14)
            local inst = entry(c, "Название для бланков...", false, 320, 26)
            inst:SetParent(c) inst:SetPos(14, 74)
            inst:SetValue(tostring(fr.institution or ""))

            local lblMax = label(c, "Предел счёта", "GRM_ATM_Small", C.muted, 346, 58, 200, 14)
            local mx = entry(c, "0 = без предела", true, 150, 26)
            mx:SetParent(c) mx:SetPos(346, 74)
            mx:SetValue(tostring(fr.maxInvoice or 0))

            local b = button(c, "Сохранить", C.green, 150, 28)
            b:SetParent(c) b:SetPos(510, 73)
            -- Три чекбокса и поля не помещались по фиксированным X:
            -- раскладываем от фактической ширины карточки.
            c.PerformLayout = function(_, w)
                local pad, gap = 14, 10
                local colW = math.max(120, math.floor((w - pad * 2 - gap * 2) / 3))
                chkS:SetPos(pad, 34)                         chkS:SetSize(colW, 18)
                chkI:SetPos(pad + colW + gap, 34)            chkI:SetSize(colW, 18)
                chkD:SetPos(pad + (colW + gap) * 2, 34)      chkD:SetSize(colW, 18)

                local btnW, mxW = 150, 140
                local instW = math.max(140, w - pad * 2 - btnW - mxW - gap * 2)
                inst:SetPos(pad, 74)                         inst:SetSize(instW, 26)
                lblMax:SetPos(pad + instW + gap, 58)         lblMax:SetSize(mxW, 14)
                mx:SetPos(pad + instW + gap, 74)             mx:SetSize(mxW, 26)
                b:SetPos(w - pad - btnW, 73)                 b:SetSize(btnW, 28)
            end
            b.DoClick = function()
                act("admin_set_access", {
                    faction = fr.name,
                    canService = chkS:GetChecked(), canInvoice = chkI:GetChecked(),
                    canDiploma = chkD:GetChecked(), institution = inst:GetValue(),
                    maxInvoice = tonumber(mx:GetValue()) or 0,
                })
            end
            sc:AddItem(c)
        end
    end

    -- Реестр счетов
    local pInv = page()
    sheet:AddSheet("Реестр счетов", pInv, "icon16/report_magnify.png")
    do
        local sc = scroll(pInv) sc:Dock(FILL)
        if #(ad.invoices or {}) == 0 then sc:AddItem(empty(sc, "Реестр счетов пуст.")) end
        for _, inv in ipairs(ad.invoices or {}) do
            local c = card(sc, 72)
            local stCol = inv.status == "paid" and C.green or (inv.status == "cancelled" and C.red or C.amber)
            label(c, ("№%d — %s"):format(inv.id or 0, tostring(inv.title or "")), "GRM_ATM_Head", C.text, 14, 8, 420, 20)
            label(c, ("Плательщик: %s | Организация: %s"):format(
                tostring(inv.targetName or "?"), tostring(inv.faction ~= "" and inv.faction or "—")),
                "GRM_ATM_Small", C.muted, 14, 30, 470, 16)
            label(c, ("Выставил: %s | %s"):format(tostring(inv.issuerName or "?"), dateOf(inv.issued)),
                "GRM_ATM_Small", C.muted, 14, 48, 470, 16)
            label(c, money(inv.amount or 0), "GRM_ATM_Body", C.text, 490, 14, 130, 20)
            label(c, inv.status == "paid" and "ОПЛАЧЕН" or (inv.status == "cancelled" and "АННУЛИРОВАН" or "НЕ ОПЛАЧЕН"),
                "GRM_ATM_Small", stCol, 490, 36, 130, 16)

            local bEd = button(c, "Правка", C.amber, 110, 28)
            bEd:SetParent(c)
            bEd.DoClick = function()
                Derma_StringRequest("Правка счёта №" .. tostring(inv.id),
                    "Новая сумма (пусто — не менять):", tostring(inv.amount or 0), function(txt)
                        act("admin_edit_invoice", { id = inv.id, amount = tonumber(txt) })
                    end)
            end
            local bDel = button(c, "Удалить", C.red, 110, 28)
            bDel:SetParent(c)
            bDel.DoClick = function()
                Derma_Query(("Удалить счёт №%d из реестра?"):format(inv.id or 0), "Подтверждение",
                    "Удалить", function() act("admin_delete_invoice", { id = inv.id }) end,
                    "Отмена", function() end)
            end
            layoutRight(c, { bEd, bDel }, 22)
            sc:AddItem(c)
        end
    end

    -- Реестр дипломов
    local pDip = page()
    sheet:AddSheet("Реестр дипломов", pDip, "icon16/page_white_text.png")
    do
        local sc = scroll(pDip) sc:Dock(FILL)
        if #(ad.diplomas or {}) == 0 then sc:AddItem(empty(sc, "Реестр дипломов пуст.")) end
        for _, d in ipairs(ad.diplomas or {}) do
            local c = card(sc, 74)
            label(c, tostring(d.number or ""), "GRM_ATM_Head", d.revoked and C.red or C.text, 14, 8, 240, 20)
            label(c, ("%s — %s"):format(tostring(d.graduateName or "?"), tostring(d.specialty or "")),
                "GRM_ATM_Small", C.muted, 14, 30, 470, 16)
            label(c, ("%s | %s"):format(tostring(d.institution or "—"), dateOf(d.issued)),
                "GRM_ATM_Small", C.muted, 14, 48, 470, 16)
            label(c, d.revoked and "АННУЛИРОВАН" or "ДЕЙСТВИТЕЛЕН", "GRM_ATM_Small",
                d.revoked and C.red or C.green, 490, 26, 150, 16)

            local btns = {}
            if d.revoked then
                local bR = button(c, "Восстановить", C.green, 150, 28)
                bR:SetParent(c)
                bR.DoClick = function() act("admin_restore_diploma", { number = d.number }) end
                btns[#btns + 1] = bR
            else
                local bE = button(c, "Правка", C.amber, 110, 28)
                bE:SetParent(c)
                bE.DoClick = function()
                    Derma_StringRequest("Правка диплома " .. tostring(d.number),
                        "Специальность:", tostring(d.specialty or ""), function(txt)
                            act("admin_edit_diploma", { number = d.number, specialty = txt })
                        end)
                end
                btns[#btns + 1] = bE
            end
            local bD = button(c, "Удалить", C.red, 110, 28)
            bD:SetParent(c)
            bD.DoClick = function()
                Derma_Query(("Удалить диплом %s из реестра?"):format(tostring(d.number)), "Подтверждение",
                    "Удалить", function() act("admin_delete_diploma", { number = d.number }) end,
                    "Отмена", function() end)
            end
            btns[#btns + 1] = bD
            layoutRight(c, btns, 24)
            sc:AddItem(c)
        end
    end
end

-- ── окно ──────────────────────────────────────────────────
local TABS = {
    { id = "account",  name = "Мой счёт",       icon = "icon16/money.png" },
    { id = "debt",     name = "Задолженность",  icon = "icon16/exclamation.png" },
    { id = "services", name = "Госуслуги",      icon = "icon16/basket.png" },
    { id = "diplomas", name = "Дипломы",        icon = "icon16/user_suit.png" },
    { id = "org",      name = "Организация",    icon = "icon16/group.png" },
    { id = "admin",    name = "Надзор",         icon = "icon16/shield.png" },
}

local activeTab = "account"

local function rebuild()
    if not IsValid(frame) then return end
    local C = theme()
    local body = frame._body
    if not IsValid(body) then return end
    body:Clear()

    local fn = tabs[activeTab]
    if fn then fn(body) end

    -- подсветка активной кнопки
    for id, b in pairs(frame._tabBtns or {}) do
        if IsValid(b) then b._active = (id == activeTab) end
    end
end

local function openFrame()
    local C = theme()
    if IsValid(frame) then frame:Remove() end

    -- Задача 10: формы услуг и счетов стали выше (подписи полей + ячейка
    -- исполнителя). Окно тянем от разрешения, чтобы прокрутка не была
    -- единственным способом добраться до кнопки на 720p.
    -- ScrW/ScrH есть только в живом клиенте; в стендах берём 1920x1080.
    local sw = isfunction(ScrW) and ScrW() or 1920
    local sh = isfunction(ScrH) and ScrH() or 1080
    local W = math.min(980, math.max(760, math.floor(sw * 0.66)))
    local H = math.min(700, math.max(520, math.floor(sh * 0.85)))
    frame = vgui.Create("DFrame")
    frame:SetSize(W, H)
    frame:Center()
    frame:SetTitle("")
    frame:ShowCloseButton(false)
    frame:MakePopup()
    frame.Paint = function(_, w, h)
        draw.RoundedBox(9, 0, 0, w, h, C.bg)
        draw.RoundedBoxEx(9, 0, 0, w, 56, C.header, true, true, false, false)
        draw.SimpleText(string.upper(tostring(snap.terminal or "БАНК GRM")), "GRM_ATM_Title",
            20, 20, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Банковский терминал · государственные услуги · реестры",
            "GRM_ATM_Small", 20, 42, C.cyan, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(("Наличные: %s     Счёт: %s"):format(money(snap.cash or 0), money(snap.bank or 0)),
            "GRM_ATM_Head", w - 60, 28, C.green, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end
    if GRM.UI and GRM.UI.Track then GRM.UI.Track("atm", frame) end

    local close = button(frame, "✕", C.red, 30, 28)
    close:SetPos(W - 42, 14)
    close.DoClick = function() frame:Close() end

    -- боковое меню вкладок
    local side = vgui.Create("DPanel", frame)
    side:SetPos(12, 66) side:SetSize(196, H - 78)
    side.Paint = function(_, w, h) draw.RoundedBox(7, 0, 0, w, h, C.panel) end

    local body = vgui.Create("DPanel", frame)
    body:SetPos(216, 66) body:SetSize(W - 228, H - 78)
    body.Paint = function(_, w, h) draw.RoundedBox(7, 0, 0, w, h, C.panel) end
    body.PerformLayout = function(self) self:DockPadding(10, 10, 10, 10) end
    body:DockPadding(10, 10, 10, 10)
    frame._body = body
    frame._tabBtns = {}

    local y = 10
    for _, t in ipairs(TABS) do
        local visible = true
        if t.id == "admin" then visible = snap.isSuper == true end
        if t.id == "org" then visible = snap.org ~= nil end
        if visible then
            local b = vgui.Create("DButton", side)
            b:SetPos(8, y) b:SetSize(180, 38)
            b:SetText(t.name) b:SetFont("GRM_ATM_Body")
            b:SetTextColor(C.text)
            b.Paint = function(self, w, h)
                local col = self._active and C.cyan or (self:IsHovered() and C.panel2 or Color(0, 0, 0, 0))
                if self._active then
                    draw.RoundedBox(6, 0, 0, w, h, Color(C.cyan.r, C.cyan.g, C.cyan.b, 40))
                    surface.SetDrawColor(C.cyan)
                    surface.DrawRect(0, 0, 3, h)
                elseif self:IsHovered() then
                    draw.RoundedBox(6, 0, 0, w, h, C.panel2)
                end
            end
            b.DoClick = function()
                activeTab = t.id
                rebuild()
            end
            frame._tabBtns[t.id] = b
            y = y + 42
        end
    end

    -- подсказка внизу бокового меню
    local hint = vgui.Create("DLabel", side)
    hint:SetPos(12, H - 130) hint:SetSize(172, 60)
    hint:SetFont("GRM_ATM_Small") hint:SetTextColor(C.muted)
    hint:SetWrap(true) hint:SetContentAlignment(7)
    hint:SetText("Оплата проходит со счёта, при нехватке — добирается наличными.")

    rebuild()
end

net.Receive("GRM_ATM_Open", function()
    net.ReadEntity()
    snap = net.ReadTable() or {}
    activeTab = "account"
    openFrame()
end)

net.Receive("GRM_ATM_Data", function()
    snap = net.ReadTable() or {}
    if IsValid(frame) then
        -- вкладка «Организация»/«Надзор» могла пропасть вместе с правами
        if activeTab == "org" and not snap.org then activeTab = "account" end
        if activeTab == "admin" and not snap.isSuper then activeTab = "account" end
        rebuild()
    end
end)

net.Receive("GRM_ATM_Result", function()
    local ok = net.ReadBool()
    local msg = net.ReadString()
    if msg == "" then return end
    notification.AddLegacy(msg, ok and NOTIFY_GENERIC or NOTIFY_ERROR, 5)
    surface.PlaySound(ok and "buttons/button14.wav" or "buttons/button10.wav")
end)

end -- CLIENT
