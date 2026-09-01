--[[--------------------------------------------------------------------
    GRM Services Commands v1.0.0 — чат и консоль для услуг, счетов, дипломов

    Команды дублируются как /слэш и как concommand grm_*: чат удобнее
    игрокам, консоль — администраторам и биндам. Регистрация двойным
    хуком (PlayerSayTransform + PlayerSay), как в модулях розыска.

    Игроку:      /debt, /myinvoices, /pay, /paydebt, /diploma, /mydiplomas
    Организации: /invoice, /invoice_cancel, /service_add, /services,
                 /diploma_issue, /diploma_revoke
    Суперадмину: /svc_access, /invoice_del, /diploma_del, /diplomas_all
----------------------------------------------------------------------]]

if CLIENT then return end

local function S() return GRM.Services end
local function D() return GRM.Diplomas end

local function money(v)
    if GRM.FormatMoney then return GRM.FormatMoney(v) end
    return string.Comma(math.floor(tonumber(v) or 0)) .. " GRM"
end

local function say(ply, msg, r, g, b)
    if not IsValid(ply) then print(msg) return end
    if GRM.Notify then GRM.Notify(ply, msg, r or 140, g or 200, b or 255)
    else ply:ChatPrint(msg) end
end

local function chat(ply, msg)
    if IsValid(ply) then ply:ChatPrint(msg) else print(msg) end
end

--- Разбор аргументов с поддержкой "строк в кавычках".
local function parseArgs(str)
    local out = {}
    for quoted, plain in string.gmatch(tostring(str or ""), '"([^"]*)"%s*|?([^%s"]*)') do
        if quoted ~= "" then out[#out + 1] = quoted end
        if plain ~= "" then out[#out + 1] = plain end
    end
    if #out == 0 then
        for w in string.gmatch(tostring(str or ""), "%S+") do out[#out + 1] = w end
    end
    return out
end

--- Поиск игрока по части ника / SteamID / ключу персонажа.
local function findTarget(query)
    query = string.lower(string.Trim(tostring(query or "")))
    if query == "" then return nil end
    for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
        if IsValid(p) then
            if string.lower(p:Nick()):find(query, 1, true)
                or string.lower(p:SteamID()) == query
                or p:SteamID64() == query then
                return p
            end
        end
    end
    return nil
end

-----------------------------------------------------------------------
-- Обработчики
-----------------------------------------------------------------------
local CMD = {}

-- ── игрок ─────────────────────────────────────────────────
CMD.debt = function(ply)
    local s = S()
    if not s then return say(ply, "Модуль госуслуг недоступен", 255, 120, 120) end
    local d = s.DebtSummary(ply)
    chat(ply, ("[Задолженность] Штрафы: %s | Счета: %s | Всего: %s")
        :format(money(d.fines), money(d.invoices), money(d.total)))
    if d.total > 0 then chat(ply, "Оплата — в банкомате или командой /paydebt") end
end

CMD.myinvoices = function(ply)
    local s = S()
    if not s then return end
    local list = s.InvoicesFor(ply, false)
    if #list == 0 then return say(ply, "Счетов на ваше имя нет.") end
    chat(ply, "── Ваши счета ──")
    for _, rec in ipairs(list) do
        local st = rec.status == "paid" and "оплачен"
            or (rec.status == "cancelled" and "аннулирован" or "НЕ ОПЛАЧЕН")
        chat(ply, ("№%d | %s | %s | %s | %s")
            :format(rec.id, rec.title, money(rec.amount - rec.paid), st,
                rec.faction ~= "" and rec.faction or "—"))
    end
end

CMD.pay = function(ply, args)
    local s = S()
    if not s then return end
    local id = tonumber(args[1])
    if not id then return say(ply, "Использование: /pay <№счёта> [сумма]", 255, 200, 120) end
    local ok, res = s.PayInvoice(ply, id, tonumber(args[2]), "auto")
    if ok then say(ply, ("Оплачено %s по счёту №%d"):format(money(res), id), 120, 220, 140)
    else say(ply, tostring(res), 255, 140, 140) end
end

CMD.paydebt = function(ply)
    local s = S()
    if not s then return end
    local F = GRM.Wanted and GRM.Wanted.Fines
    local paid, failed = 0, nil
    if F and isfunction(F.For) then
        for _, rec in ipairs(F.For(ply, true)) do
            local ok, res = s.PayFine(ply, rec.id, rec.amount - rec.paid, "auto")
            if ok then paid = paid + (tonumber(res) or 0) else failed = failed or res end
        end
    end
    for _, rec in ipairs(s.InvoicesFor(ply, true)) do
        local ok, res = s.PayInvoice(ply, rec.id, rec.amount - rec.paid, "auto")
        if ok then paid = paid + (tonumber(res) or 0) else failed = failed or res end
    end
    if paid > 0 then say(ply, ("Оплачено: %s"):format(money(paid)), 120, 220, 140) end
    if failed then say(ply, "Не всё удалось погасить: " .. tostring(failed), 255, 180, 120) end
    if paid == 0 and not failed then say(ply, "Задолженности нет.") end
end

CMD.diploma = function(ply, args)
    local d = D()
    if not d then return end
    local num = args[1]
    if not num then return say(ply, "Использование: /diploma <номер бланка>", 255, 200, 120) end
    local rec = d.ByNumber(num)
    if not rec then return say(ply, "В реестре такого диплома нет.", 255, 140, 140) end
    for _, line in ipairs(string.Explode("\n", d.RenderText(rec))) do chat(ply, line) end
end

CMD.mydiplomas = function(ply)
    local d = D()
    if not d then return end
    local list = d.For(ply, true)
    if #list == 0 then return say(ply, "У вас нет дипломов.") end
    chat(ply, "── Ваши дипломы ──")
    for _, rec in ipairs(list) do
        chat(ply, ("%s | %s | %s | %s%s"):format(rec.number, rec.institution, rec.specialty,
            d.LevelName(rec.level), rec.revoked and " | АННУЛИРОВАН" or ""))
    end
end

CMD.services = function(ply, args)
    local s = S()
    if not s then return end
    local list = s.ListServices({ onlyEnabled = true, query = args[1] })
    if #list == 0 then return say(ply, "Услуг не найдено.") end
    chat(ply, "── Государственные услуги ──")
    local n = 0
    for _, rec in ipairs(list) do
        chat(ply, ("[%s] %s — %s | %s"):format(s.CategoryName(rec.category), rec.name,
            money(rec.price), rec.provider))
        n = n + 1
        if n >= 30 then chat(ply, "… список обрезан, полный — в банкомате") break end
    end
end

-- ── организация ───────────────────────────────────────────
CMD.invoice = function(ply, args)
    local s = S()
    if not s then return end
    if #args < 3 then
        return say(ply, 'Использование: /invoice <ник> <сумма> "<назначение>"', 255, 200, 120)
    end
    local target = findTarget(args[1])
    if not target then return say(ply, "Игрок не найден", 255, 140, 140) end
    local ok, res = s.IssueInvoice(ply, target, {
        amount = tonumber(args[2]),
        title  = table.concat(args, " ", 3),
        targetName = target:Nick(),
    })
    if ok then say(ply, ("Счёт №%d выставлен на %s (%s)"):format(res.id, target:Nick(), money(res.amount)), 120, 220, 140)
    else say(ply, tostring(res), 255, 140, 140) end
end

CMD.invoice_cancel = function(ply, args)
    local s = S()
    if not s then return end
    local id = tonumber(args[1])
    if not id then return say(ply, "Использование: /invoice_cancel <№> [причина]", 255, 200, 120) end
    local ok, res = s.CancelInvoice(ply, id, table.concat(args, " ", 2))
    if ok then say(ply, ("Счёт №%d аннулирован"):format(id), 200, 200, 200)
    else say(ply, tostring(res), 255, 140, 140) end
end

CMD.service_add = function(ply, args)
    local s = S()
    if not s then return end
    if #args < 3 then
        return say(ply, 'Использование: /service_add <категория> <цена> "<название>"', 255, 200, 120)
    end
    local ok, res = s.UpsertService(ply, {
        category = args[1], price = tonumber(args[2]), name = table.concat(args, " ", 3),
    })
    if ok then say(ply, ("Услуга «%s» сохранена (%s)"):format(res.name, money(res.price)), 120, 220, 140)
    else say(ply, tostring(res), 255, 140, 140) end
end

CMD.diploma_issue = function(ply, args)
    local d = D()
    if not d then return end
    if #args < 2 then
        return say(ply, 'Использование: /diploma_issue <ник> "<специальность>" [квалификация]', 255, 200, 120)
    end
    local target = findTarget(args[1])
    if not target then return say(ply, "Выпускник не найден (должен быть онлайн)", 255, 140, 140) end
    local ok, res = d.Issue(ply, {
        graduate = target, graduateName = target:Nick(),
        specialty = args[2], qualification = args[3],
    })
    if ok then say(ply, ("Диплом %s выдан: %s"):format(res.number, res.graduateName), 120, 220, 140)
    else say(ply, tostring(res), 255, 140, 140) end
end

CMD.diploma_revoke = function(ply, args)
    local d = D()
    if not d then return end
    local num = args[1]
    if not num then return say(ply, "Использование: /diploma_revoke <номер> [причина]", 255, 200, 120) end
    local ok, res = d.Revoke(ply, num, table.concat(args, " ", 2))
    if ok then say(ply, ("Диплом %s аннулирован"):format(res.number), 200, 200, 200)
    else say(ply, tostring(res), 255, 140, 140) end
end

--[[ ПАРАМЕТРЫ ДОСТУПА /svc_access — таблица вместо лестницы `elseif kind ==`.
     Заодно видно, что «включено» значит одно и то же для всех флагов:
     раньше выражение `value ~= "0" and value ~= "off"` было переписано
     трижды, и разойтись ему ничто не мешало. ]]
local function flagOn(value)
    return value ~= "0" and value ~= "off"
end

local ACCESS_FIELDS = {
    service = function(patch, value) patch.canService = flagOn(value) end,
    invoice = function(patch, value) patch.canInvoice = flagOn(value) end,
    diploma = function(patch, value) patch.canDiploma = flagOn(value) end,
    max = function(patch, value) patch.maxInvoice = tonumber(value) or 0 end,
    -- Название учреждения — весь остаток команды: в нём бывают пробелы.
    name = function(patch, _value, args) patch.institution = table.concat(args, " ", 3) end,
}

-- ── суперадмин ────────────────────────────────────────────
CMD.svc_access = function(ply, args)
    if IsValid(ply) and not ply:IsSuperAdmin() then
        return say(ply, "Только суперадмин", 255, 140, 140)
    end
    local s = S()
    if not s then return end
    if #args < 2 then
        return say(ply, 'Использование: /svc_access "<фракция>" <service|invoice|diploma|max|name> [значение]', 255, 200, 120)
    end
    local faction, kind, value = args[1], string.lower(args[2]), args[3]
    local patch = {}
    local applyPatch = ACCESS_FIELDS[kind]
    if not applyPatch then
        return say(ply, "Неизвестный параметр: " .. kind, 255, 140, 140)
    end
    applyPatch(patch, value, args)

    local ok, res = s.SetAccess(faction, patch)
    if ok then
        say(ply, ("Доступы «%s»: услуги=%s, счета=%s, дипломы=%s, предел=%s")
            :format(faction, tostring(res.canService), tostring(res.canInvoice),
                tostring(res.canDiploma), money(res.maxInvoice)), 120, 220, 140)
    else say(ply, tostring(res), 255, 140, 140) end
end

CMD.invoice_del = function(ply, args)
    if IsValid(ply) and not ply:IsSuperAdmin() then return say(ply, "Только суперадмин", 255, 140, 140) end
    local s = S()
    if not s then return end
    local ok, res = s.DeleteInvoice(ply, tonumber(args[1]))
    say(ply, ok and ("Счёт №" .. tostring(args[1]) .. " удалён") or tostring(res),
        ok and 200 or 255, ok and 200 or 140, ok and 200 or 140)
end

CMD.diploma_del = function(ply, args)
    if IsValid(ply) and not ply:IsSuperAdmin() then return say(ply, "Только суперадмин", 255, 140, 140) end
    local d = D()
    if not d then return end
    local ok, res = d.Delete(ply, args[1])
    say(ply, ok and ("Диплом " .. tostring(args[1]) .. " удалён") or tostring(res),
        ok and 200 or 255, ok and 200 or 140, ok and 200 or 140)
end

CMD.diplomas_all = function(ply, args)
    if IsValid(ply) and not ply:IsSuperAdmin() then return say(ply, "Только суперадмин", 255, 140, 140) end
    local d = D()
    if not d then return end
    local page, total = d.Page({ query = args[1] }, 0, 40)
    chat(ply, ("── Реестр дипломов (%d из %d) ──"):format(#page, total))
    for _, rec in ipairs(page) do
        chat(ply, ("%s | %s | %s | %s%s"):format(rec.number, rec.graduateName,
            rec.specialty, rec.institution, rec.revoked and " | АННУЛИРОВАН" or ""))
    end
end

--[[ Правка одного поля бланка. Нужна как ручное продолжение починки:
     значения, чей хвост уничтожен обрезкой байтами, восстановить неоткуда,
     их вводят заново. Права проверяет сам D.Edit (руководитель учреждения,
     учреждение/выпускник — только суперадмин). ]]
local EDITABLE = {
    specialty = true, qualification = true, grade = true, note = true,
    signedBy = true, level = true, form = true,
    institution = true, graduateName = true, number = true,
}
CMD.diploma_edit = function(ply, args)
    local d = D()
    if not d then return end
    local num, field = args[1], string.lower(tostring(args[2] or ""))
    local value = args[3]
    if not num or field == "" or value == nil then
        return say(ply, 'Использование: /diploma_edit <номер> <поле> "<значение>"', 255, 200, 120)
    end
    if not EDITABLE[field] then
        local keys = {}
        for k in pairs(EDITABLE) do keys[#keys + 1] = k end
        table.sort(keys)
        return say(ply, "Поле можно менять только из списка: " .. table.concat(keys, ", "), 255, 200, 120)
    end
    local ok, res = d.Edit(ply, num, { [field] = value })
    if not ok then return say(ply, tostring(res), 255, 140, 140) end
    say(ply, ("%s | %s = «%s»"):format(res.number, field, tostring(res[field])), 120, 220, 140)
end

--[[ Разовая починка дипломов, обрезанных байтовым string.sub (задача 12).
     По умолчанию — РЕЖИМ ПРОСМОТРА: показывает, что будет изменено, и
     ничего не пишет. Запись только по явному «apply», потому что это
     госреестр. Перед записью D.Repair кладёт бэкап diplomas.bak.<ts>.json. ]]
CMD.diploma_repair = function(ply, args)
    if IsValid(ply) and not ply:IsSuperAdmin() then return say(ply, "Только суперадмин", 255, 140, 140) end
    local d = D()
    if not d or not isfunction(d.Repair) then return say(ply, "Модуль дипломов не загружен", 255, 140, 140) end

    local apply = tostring(args[1] or ""):lower()
    apply = (apply == "apply" or apply == "1" or apply == "yes")

    local ok, rep = d.Repair(ply, apply)
    if not ok then return say(ply, tostring(rep), 255, 140, 140) end

    chat(ply, ("── Починка дипломов (%s) ──"):format(apply and "ЗАПИСЬ" or "просмотр, изменений не внесено"))
    chat(ply, ("Просмотрено записей: %d | битых хвостов: %d | к изменению: %d")
        :format(rep.scanned, rep.fixedTails, rep.changed))

    if #rep.restored == 0 and #rep.unrecoverable == 0 then
        return say(ply, "Обрезанных записей не найдено — реестр в порядке.", 120, 220, 140)
    end

    if #rep.restored > 0 then
        chat(ply, ("Восстановлено по канону (%d):"):format(#rep.restored))
        for i, r in ipairs(rep.restored) do
            if i > 20 then chat(ply, ("  …ещё %d"):format(#rep.restored - 20)) break end
            chat(ply, ("  %s | %s: «%s» → «%s»"):format(r.number, r.field, r.from, r.to))
        end
    end

    if #rep.unrecoverable > 0 then
        chat(ply, ("Восстановить нельзя — хвост утрачен, введите заново (%d):"):format(#rep.unrecoverable))
        for i, r in ipairs(rep.unrecoverable) do
            if i > 20 then chat(ply, ("  …ещё %d"):format(#rep.unrecoverable - 20)) break end
            chat(ply, ("  %s | %s: «%s»"):format(r.number, r.field, r.value))
        end
        chat(ply, "Правка: /diploma_edit <номер> <поле> <значение>")
    end

    if not apply and rep.changed > 0 then
        say(ply, "Это предпросмотр. Для записи: /diploma_repair apply", 255, 200, 120)
    end
end

-----------------------------------------------------------------------
-- Регистрация
-----------------------------------------------------------------------
--[[ Один обработчик на оба хука: PlayerSayTransform используют
     чат-аддоны, PlayerSay — ванильный чат. Флаг SkipPlayerSay не даёт
     обработать команду дважды. ]]
local function handleChat(ply, text)
    local raw = string.Trim(tostring(text or ""))
    local prefix = raw:sub(1, 1)
    if prefix ~= "/" and prefix ~= "!" then return end

    local body = raw:sub(2)
    local cmd = string.lower(body:match("^(%S+)") or "")
    if cmd == "" then return end
    local h = CMD[cmd]
    if not h then return end

    local rest = string.Trim(body:sub(#cmd + 1))
    h(ply, parseArgs(rest))
    return ""
end

hook.Add("PlayerSayTransform", "GRM_Services_Commands", function(pack)
    if not istable(pack) then return end
    local res = handleChat(pack.ply or pack.Player, pack.text or pack.Text)
    if res ~= nil then
        pack.SkipPlayerSay = true
        pack.text = ""
        return ""
    end
end)

hook.Add("PlayerSay", "GRM_Services_Commands", function(ply, text)
    return handleChat(ply, text)
end)

-- Консольные дубли: grm_debt, grm_invoice, …
for name, fn in pairs(CMD) do
    concommand.Add("grm_" .. name, function(ply, _, args)
        fn(ply, args or {})
    end)
end

--- Открыть банкомат по команде: работает у терминала или у компьютера,
--- чтобы вкладка «Госуслуги» в электронике не упиралась в пустоту.
concommand.Add("grm_atm", function(ply)
    if not (IsValid(ply) and GRM.ATM) then return end
    local best, bestDist
    for _, e in ipairs(ents.FindInSphere(ply:GetPos(), GRM.ATM.Config.UseRange)) do
        if IsValid(e) then
            local cls = e:GetClass()
            local isDevice = isfunction(e.GetDeviceID) and e:GetDeviceID() ~= ""
            if cls == "grm_bank_terminal" or cls == "grm_bank_computer" or isDevice then
                local d = ply:GetPos():DistToSqr(e:GetPos())
                if not bestDist or d < bestDist then best, bestDist = e, d end
            end
        end
    end
    if not IsValid(best) then
        say(ply, "Подойдите к банкомату или компьютеру, подключённому к сети.", 255, 200, 120)
        return
    end
    GRM.ATM.Open(ply, best)
end)

print("[GRM Services] команды загружены: /debt, /pay, /invoice, /diploma_issue, /svc_access …")
