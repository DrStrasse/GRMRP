-- sim_wanted_migration — миграция базы розыска v2 → v3, миграция
-- каталога статей, реестр штрафов и разграничение юрисдикций.
-- Запуск: luajit tools/luatest/sim_wanted_migration.lua
local files = {}
local DATA = {}
_G.CLIENT=false _G.SERVER=true
function _G.AddCSLuaFile() end
function _G.include() end
function _G.ErrorNoHalt(s) io.write("[ErrorNoHalt] "..tostring(s)) end
function _G.IsValid(v) return type(v)=="table" and v.__valid==true end
function _G.isfunction(v) return type(v)=="function" end
function _G.istable(v) return type(v)=="table" end
function _G.isstring(v) return type(v)=="string" end
function _G.util_dummy() end
_G.math.Clamp=function(v,a,b) if v<a then return a elseif v>b then return b end return v end
_G.string.Trim=function(s) return (tostring(s):gsub("^%s+",""):gsub("%s+$","")) end
_G.string.Comma=function(v) return tostring(v) end
_G.string.Explode=function(sep,s) local o={} for m in tostring(s):gmatch("[^"..sep.."]+") do o[#o+1]=m end return o end
_G.player={GetAll=function() return {} end}
_G.os=os _G.table=table
_G.hook={Add=function() end,Run=function() end}
_G.timer={Simple=function() end}
_G.concommand={Add=function() end}
_G.net=setmetatable({},{__index=function() return function() end end})
_G.util={AddNetworkString=function() end}

-- простейший JSON (достаточно для нашей структуры)
local function esc(s) return (s:gsub('[%c"\\]',function(c) return ({['"']='\\"',['\\']='\\\\',['\n']='\\n'})[c] or string.format('\\u%04x',c:byte()) end)) end
local function enc(v)
  local t=type(v)
  if t=="number" then return (v%1==0) and string.format("%d",v) or tostring(v) end
  if t=="string" then return '"'..esc(v)..'"' end
  if t=="boolean" then return tostring(v) end
  if t=="table" then
    if #v>0 or next(v)==nil then local o={} for _,x in ipairs(v) do o[#o+1]=enc(x) end return "["..table.concat(o,",").."]" end
    local o={} for k,x in pairs(v) do o[#o+1]='"'..esc(tostring(k))..'":'..enc(x) end return "{"..table.concat(o,",").."}"
  end
  return "null"
end
local pos,str
local function skip() while true do local c=str:sub(pos,pos) if c==" " or c=="\n" or c=="\t" or c=="\r" then pos=pos+1 else break end end end
local function val()
  skip() local c=str:sub(pos,pos)
  if c=="{" then pos=pos+1 local o={} skip()
    if str:sub(pos,pos)=="}" then pos=pos+1 return o end
    while true do skip() local k=val() skip() pos=pos+1 local v=val() o[k]=v skip()
      local d=str:sub(pos,pos) pos=pos+1 if d=="}" then return o end end
  elseif c=="[" then pos=pos+1 local o={} skip()
    if str:sub(pos,pos)=="]" then pos=pos+1 return o end
    while true do o[#o+1]=val() skip() local d=str:sub(pos,pos) pos=pos+1 if d=="]" then return o end end
  elseif c=='"' then pos=pos+1 local s="" while true do local ch=str:sub(pos,pos)
      if ch=='\\' then local n=str:sub(pos+1,pos+1) s=s..({['n']='\n',['"']='"',['\\']='\\'})[n] or "" pos=pos+2
      elseif ch=='"' then pos=pos+1 return s else s=s..ch pos=pos+1 end end
  else local s=pos while str:sub(pos,pos):match("[%w%.%-%+eE]") do pos=pos+1 end
    local sub=str:sub(s,pos-1)
    if sub=="true" then return true elseif sub=="false" then return false elseif sub=="null" then return nil end
    return tonumber(sub) end
end
_G.util.TableToJSON=function(t) return enc(t) end
_G.util.JSONToTable=function(s) str=s pos=1 local ok,r=pcall(val) return ok and r or nil end
_G.file={
  Exists=function(p) return files[p]~=nil end,
  Read=function(p) return files[p] end,
  Write=function(p,c) files[p]=c end,
  IsDir=function() return true end,
  CreateDir=function() end,
}
_G.table.Count=function(t) local n=0 for _ in pairs(t) do n=n+1 end return n end
_G.table.Copy=function(t) local o={} for k,v in pairs(t) do o[k]=type(v)=="table" and _G.table.Copy(v) or v end return o end
_G.table.remove=table.remove
_G.SetGlobalDouble=function() end
_G.Color=function(r,g,b,a) return {r=r,g=g,b=b,a=a or 255} end
_G.color_white=_G.Color(255,255,255)
_G.GRM={Identity={CharacterKey=function(p) return p.key end}}


-- ======================================================================
-- sim_services — государственные услуги, счета, дипломы и банкомат.
-- Проверяем: права фракций, выставление и оплату счетов, распределение
-- денег, реестр дипломов, снимок данных банкомата и права суперадмина.
-- Запуск: luajit tools/luatest/sim_services.lua
-- ======================================================================

-- ── доработка мока под фазу 3 ────────────────────────────────────────
_G.CurTime = function() return os.clock() * 1000 end
_G.math.max = math.max
_G.string.rep = string.rep
_G.Derma_Query = function() end
_G.notification = { AddLegacy = function() end }
_G.NOTIFY_GENERIC, _G.NOTIFY_ERROR = 0, 1

local hooks = {}
_G.hook = {
    Add = function(ev, name, fn) hooks[ev] = hooks[ev] or {}; hooks[ev][name] = fn end,
    Remove = function(ev, name) if hooks[ev] then hooks[ev][name] = nil end end,
    Run = function(ev, ...)
        for _, fn in pairs(hooks[ev] or {}) do fn(...) end
    end,
    Call = function(ev, _, ...) return _G.hook.Run(ev, ...) end,
}

local netSent = {}
_G.net = setmetatable({
    Start = function(n) netSent[#netSent + 1] = { name = n, recipients = 0 } end,
    Send = function(t) if netSent[#netSent] then netSent[#netSent].recipients = istable(t) and #t or 1 end end,
    Broadcast = function() end,
    Receive = function() end,
    AddNetworkString = function() end,
}, { __index = function() return function() end end })
_G.util.AddNetworkString = function() end

-- игроки
local PLAYERS = {}
local function mkPlayer(key, nick, faction, super)
    local nw = { GRM_Faction = faction or "", GRM_Role = "Сотрудник", GRM_Department = "", GRM_FactionTag = "" }
    local nwb, nwi = {}, {}
    local p
    p = {
        __valid = true, key = key,
        IsPlayer = function() return true end,
        IsSuperAdmin = function() return super == true end,
        IsAdmin = function() return super == true end,
        Nick = function() return nick end,
        SteamID = function() return "STEAM_0:0:1" end,
        SteamID64 = function() return (key:gsub(":char%d", "")) end,
        GetNWString = function(_, k, d) return nw[k] or d or "" end,
        SetNWString = function(_, k, v) nw[k] = v end,
        GetNWBool = function(_, k, d) if nwb[k] == nil then return d or false end return nwb[k] end,
        SetNWBool = function(_, k, v) nwb[k] = v end,
        SetNWInt = function(_, k, v) nwi[k] = v end,
        SetNW2Int = function(_, k, v) nwi[k] = v end,
        GetNWInt = function(_, k, d) return nwi[k] or d or 0 end,
        ChatPrint = function(_, t) end,
        PrintMessage = function() end,
        _nw = nw,
    }
    PLAYERS[#PLAYERS + 1] = p
    return p
end
_G.player = { GetAll = function() return PLAYERS end, GetBySteamID = function() end, GetBySteamID64 = function() end }

_G.timer = { Simple = function(_, fn) if fn then fn() end end }
_G.concommand = { Add = function() end }
_G.ErrorNoHalt = function(s) io.write("[ErrorNoHalt] " .. tostring(s)) end
_G.GRM.Notify = function() end
_G.GRM.FormatMoney = function(v) return tostring(v) .. " R" end


-- ── доработка мока под фазу 4 ────────────────────────────────────────
_G.string.Comma = function(v)
    local s = tostring(math.floor(tonumber(v) or 0))
    local out = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
    return (out:gsub("^%s+", ""))
end
_G.GRM.FormatMoney = function(v) return _G.string.Comma(v) .. " GRM" end
_G.SortedPairs = function(t) return pairs(t) end

-- экономика: наличные и счета в банке
local CASH, BANK = {}, {}
local STATE_BUDGET, FACTION_BUDGET = 0, {}

_G.GRM.GetBalance = function(p) return CASH[p.key] or 0 end
_G.GRM.HasMoney   = function(p, n) return (CASH[p.key] or 0) >= n end
_G.GRM.TakeMoney  = function(p, n)
    if (CASH[p.key] or 0) < n then return false end
    CASH[p.key] = CASH[p.key] - n
    return true
end
_G.GRM.GiveMoney = function(p, n) CASH[p.key] = (CASH[p.key] or 0) + n return true end
_G.GRM.FactionBudgetAdd = function(name, delta)
    FACTION_BUDGET[name] = (FACTION_BUDGET[name] or 0) + delta
    return FACTION_BUDGET[name]
end
_G.GRM.FactionBudgetGet = function(name) return FACTION_BUDGET[name] or 0 end

_G.GRM.Economy = {
    BankBalance = function(p) return BANK[p.key] or 0 end,
    BankTake = function(p, n)
        if (BANK[p.key] or 0) < n then return false, "funds" end
        BANK[p.key] = BANK[p.key] - n
        return true, BANK[p.key]
    end,
    BankGive = function(p, n) BANK[p.key] = (BANK[p.key] or 0) + n return true, BANK[p.key] end,
    BankDeposit = function(p, n)
        if (CASH[p.key] or 0) < n then return false, "cash" end
        CASH[p.key] = CASH[p.key] - n
        BANK[p.key] = (BANK[p.key] or 0) + n
        return true, BANK[p.key]
    end,
    BankWithdraw = function(p, n)
        if (BANK[p.key] or 0) < n then return false, "funds" end
        BANK[p.key] = BANK[p.key] - n
        CASH[p.key] = (CASH[p.key] or 0) + n
        return true, BANK[p.key]
    end,
    BankTransfer = function(p, to, n)
        if (BANK[p.key] or 0) < n then return false end
        BANK[p.key] = BANK[p.key] - n
        BANK[to] = (BANK[to] or 0) + n
        return true
    end,
    StateAdd = function(delta) STATE_BUDGET = STATE_BUDGET + delta return STATE_BUDGET end,
}

-- фракции
_G.Factions = {
    ["Университет"]     = { Leader = "76561198000000031:char1", Members = {}, LeaderRoleName = "Ректор" },
    ["Городская клиника"] = { Leader = "76561198000000041:char1", Members = {}, LeaderRoleName = "Лидер" },
    ["Ordnungspolizei"] = { Leader = "76561198000000051:char1", Members = {}, LeaderRoleName = "Лидер" },
}
_G.FactionsAPI = { Save = function() end }

files["grm_services/services.json"] = nil
files["grm_services/invoices.json"] = nil
files["grm_services/diplomas.json"] = nil

-- Ядро грузится первым и на живом сервере (sh_01_grm_core.lua), и здесь:
-- модули ниже берут из него канон GRM.CharKey (§5.2.6, одна реализация).
assert(loadfile("lua/autorun/sh_01_grm_core.lua"))()
dofile("lua/autorun/sh_grm_services.lua")
dofile("lua/autorun/sh_grm_diplomas.lua")

local S = GRM.Services
local D = GRM.Diplomas

local fails, total = 0, 0
local function check(name, cond, extra)
    total = total + 1
    if cond then print("  OK   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "   " .. tostring(extra or "")) end
end

-- участники
local rector  = mkPlayer("76561198000000031:char1", "Karl Bauer",   "Университет")
local teacher = mkPlayer("76561198000000032:char1", "Erna Vogt",    "Университет")
local doctor  = mkPlayer("76561198000000041:char1", "Hans Richter", "Городская клиника")
local student = mkPlayer("76561198000000060:char1", "Peter Klein",  "Civilian")
local admin   = mkPlayer("76561198000000001:char1", "Admin",        "", true)

-- членство во фракциях (ключи — CharacterKey)
Factions["Университет"].Members = {
    ["76561198000000031:char1"] = { Role = "Ректор" },
    ["76561198000000032:char1"] = { Role = "Преподаватель" },
}
Factions["Городская клиника"].Members = { ["76561198000000041:char1"] = { Role = "Лидер" } }

CASH[student.key], BANK[student.key] = 2000, 20000
CASH[rector.key] = 500

print("\n=== ТЕСТ 1: доступы организаций ===")
check("по умолчанию счета выставлять нельзя", select(1, S.CanInvoice(rector)) == false)
check("суперадмин обходит запрет", select(1, S.CanInvoice(admin)) == true)

S.SetAccess("Университет", {
    canService = true, canInvoice = true, canDiploma = true,
    institution = "Государственный университет Гродно",
    maxInvoice = 50000, categories = { education = true },
})
check("после выдачи доступа счета разрешены", select(1, S.CanInvoice(rector)) == true)
check("флаг проброшен во фракцию", Factions["Университет"].InvoiceAccess == true)
check("категория образования разрешена", S.FactionCanService("Университет", "education") == true)
check("чужая категория запрещена", S.FactionCanService("Университет", "medical") == false)
check("клинике доступ не выдан", S.FactionCanService("Городская клиника", "medical") == false)

print("\n=== ТЕСТ 2: каталог услуг ===")
local ok, svc = S.UpsertService(rector, {
    name = "Обучение по специальности «Юриспруденция»", category = "education",
    price = 12000, desc = "Полный курс, 2 семестра",
})
check("ректор завёл услугу", ok, svc)
check("исполнитель проставлен автоматически", ok and svc.provider == "Университет")

local okT = S.UpsertService(teacher, { name = "Левый курс", category = "education", price = 100 })
check("рядовой сотрудник каталог не правит", okT == false)

local okMed = S.UpsertService(rector, { name = "Приём врача", category = "medical", price = 500 })
check("услуга чужой категории отклонена", okMed == false)

local okDoc = S.UpsertService(doctor, { name = "Приём врача", category = "medical", price = 500 })
check("клиника без доступа услугу не заведёт", okDoc == false)

check("услуга видна в витрине", #S.ListServices({ onlyEnabled = true }) == 1)

print("\n=== ТЕСТ 3: выставление и оплата счёта ===")
local okI, inv = S.IssueInvoice(rector, student, { serviceID = svc.id, targetName = student:Nick() })
check("счёт выставлен", okI, inv)
check("сумма взята из услуги", okI and inv.amount == 12000, okI and inv.amount)
check("статус — не оплачен", okI and inv.status == "unpaid")
check("долг персонажа посчитан", S.DebtOf(student) == 12000, S.DebtOf(student))

local okOver = S.IssueInvoice(rector, student, { title = "Слишком дорого", amount = 90000 })
check("предел суммы счёта соблюдён", okOver == false)

local okSelf = S.IssueInvoice(rector, rector, { title = "Себе", amount = 100 })
check("нельзя выставить счёт себе", okSelf == false)

local bankBefore = BANK[student.key]
local okP, paid = S.PayInvoice(student, inv.id, nil, "bank")
check("счёт оплачен со счёта в банке", okP, paid)
check("списано ровно 12000", BANK[student.key] == bankBefore - 12000, BANK[student.key])
check("статус стал paid", S.InvoiceByID(inv.id).status == "paid")
check("80% ушли в бюджет университета", GRM.FactionBudgetGet("Университет") == 9600,
    GRM.FactionBudgetGet("Университет"))
check("остаток ушёл государству", STATE_BUDGET == 2400, STATE_BUDGET)
check("долг обнулился", S.DebtOf(student) == 0)

local okAgain = S.PayInvoice(student, inv.id, nil, "bank")
check("повторная оплата отклонена", okAgain == false)

print("\n=== ТЕСТ 4: частичная оплата и авто-источник ===")
local _, inv2 = S.IssueInvoice(rector, student, { title = "Пересдача", amount = 3000 })
local okPart = S.PayInvoice(student, inv2.id, 1000, "bank")
check("частичная оплата прошла", okPart)
check("остаток 2000", S.InvoiceByID(inv2.id).amount - S.InvoiceByID(inv2.id).paid == 2000)
check("счёт всё ещё открыт", S.InvoiceByID(inv2.id).status == "unpaid")

-- обнуляем счёт: остаток должен добраться наличными
BANK[student.key] = 500
CASH[student.key] = 5000
local okAuto = S.PayInvoice(student, inv2.id, 2000, "auto")
check("авто-оплата добрала наличными", okAuto)
check("со счёта снято всё, что было", BANK[student.key] == 0, BANK[student.key])
check("остальное списано наличными", CASH[student.key] == 3500, CASH[student.key])
check("счёт закрыт", S.InvoiceByID(inv2.id).status == "paid")

print("\n=== ТЕСТ 5: аннулирование и права ===")
local _, inv3 = S.IssueInvoice(rector, student, { title = "Ошибочный счёт", amount = 700 })
local okCancelStranger = S.CancelInvoice(doctor, inv3.id, "чужой")
check("чужую организацию к счёту не пускают", okCancelStranger == false)
local okCancel = S.CancelInvoice(rector, inv3.id, "выставлен по ошибке")
check("лидер аннулировал свой счёт", okCancel)
check("статус cancelled", S.InvoiceByID(inv3.id).status == "cancelled")
local okPayCancelled = S.PayInvoice(student, inv3.id, nil, "auto")
check("аннулированный счёт не оплатить", okPayCancelled == false)

print("\n=== ТЕСТ 6: реестр дипломов ===")
local okD, dip = D.Issue(rector, {
    graduate = student, graduateName = student:Nick(),
    specialty = "Юриспруденция", qualification = "Юрист",
    level = "bachelor", form = "full", grade = "с отличием",
    invoiceID = inv.id, paid = true,
})
check("диплом выдан", okD, dip)
check("номер бланка сформирован", okD and dip.number:match("^ГД%-%d%d%d%d%-%d%d%d%d%d%d$") ~= nil, okD and dip.number)
check("учреждение подставлено из настроек", okD and dip.institution == "Государственный университет Гродно")
check("подписант — выдающий", okD and dip.signedBy == "Karl Bauer")
check("диплом ищется по номеру", D.ByNumber(dip.number) ~= nil)
check("поиск нечувствителен к регистру", D.ByNumber(string.lower(dip.number)) ~= nil)
check("диплом привязан к персонажу", #D.For(student) == 1)

local okNoAccess = D.Issue(doctor, { graduate = student, specialty = "Терапия" })
check("клиника без доступа диплом не выдаст", okNoAccess == false)

local okNoSpec = D.Issue(rector, { graduate = student })
check("без специальности диплом не выписать", okNoSpec == false)

-- платное обучение по неоплаченному счёту
local _, invUnpaid = S.IssueInvoice(rector, student, { title = "Второе высшее", amount = 5000 })
local okUnpaid = D.Issue(rector, {
    graduate = student, specialty = "Экономика", invoiceID = invUnpaid.id,
})
check("диплом по неоплаченному счёту не выдаётся", okUnpaid == false)

-- бесплатное обучение
local okFree, dipFree = D.Issue(teacher, {
    graduate = student, specialty = "Основы права", level = "course",
})
check("рядовой сотрудник может выписать диплом", okFree, dipFree)
check("бесплатное обучение помечено", okFree and dipFree.paid == false)
check("номера не повторяются", okFree and dipFree.number ~= dip.number)

print("\n=== ТЕСТ 7: аннулирование и правка диплома ===")
local okRevStranger = D.Revoke(doctor, dip.number, "не наш")
check("чужой диплом не аннулировать", okRevStranger == false)
local okRevTeacher = D.Revoke(teacher, dipFree.number, "ошибка")
check("рядовой сотрудник не аннулирует", okRevTeacher == false)
local okRev = D.Revoke(rector, dipFree.number, "выдан ошибочно")
check("руководитель аннулировал", okRev)
check("пометка проставлена", D.ByNumber(dipFree.number).revoked == true)
check("аннулированный не попадает в действующие", #D.For(student, false) == 1)

local okEd = D.Edit(rector, dip.number, { specialty = "Международное право" })
check("учреждение правит свой диплом", okEd)
check("специальность изменилась", D.ByNumber(dip.number).specialty == "Международное право")
local okEdInst = D.Edit(rector, dip.number, { institution = "Левый вуз" })
check("название учреждения обычному лидеру менять нельзя",
    D.ByNumber(dip.number).institution == "Государственный университет Гродно")

print("\n=== ТЕСТ 8: полномочия суперадмина ===")
local okAdminEdit = D.Edit(admin, dip.number, { institution = "Академия государственной службы" })
check("суперадмин меняет учреждение", okAdminEdit and D.ByNumber(dip.number).institution == "Академия государственной службы")
local okRestore = D.Restore(admin, dipFree.number)
check("суперадмин восстановил диплом", okRestore and D.ByNumber(dipFree.number).revoked == false)
local okDel = D.Delete(admin, dipFree.number)
check("суперадмин удалил запись", okDel and D.ByNumber(dipFree.number) == nil)
local okDelDenied = D.Delete(rector, dip.number)
check("обычному лидеру удаление недоступно", okDelDenied == false)

local okAdminInv = S.AdminEditInvoice(admin, invUnpaid.id, { amount = 1, status = "paid" })
check("суперадмин правит счёт", okAdminInv and S.InvoiceByID(invUnpaid.id).status == "paid")
local okAdminDelInv = S.DeleteInvoice(admin, invUnpaid.id)
check("суперадмин удаляет счёт", okAdminDelInv and S.InvoiceByID(invUnpaid.id) == nil)
local okDelDenied2 = S.DeleteInvoice(rector, inv.id)
check("лидеру удаление счёта недоступно", okDelDenied2 == false)

print("\n=== ТЕСТ 9: сохранение и перезагрузка ===")
S.SaveServices() S.SaveInvoices() D.Save()
local srvCount, invCount, dipCount = table.Count(S.Catalog), #S.Invoices, #D.List
local accBefore = S.AccessOf("Университет").institution
S.LoadServices() S.LoadInvoices() D.Load()
check("каталог пережил перезагрузку", table.Count(S.Catalog) == srvCount, table.Count(S.Catalog))
check("счета пережили перезагрузку", #S.Invoices == invCount, #S.Invoices)
check("дипломы пережили перезагрузку", #D.List == dipCount, #D.List)
check("доступы восстановлены", S.AccessOf("Университет").institution == accBefore)
check("предел суммы восстановлен", S.AccessOf("Университет").maxInvoice == 50000)
check("нумерация дипломов не сбросилась", D._nextNumber > dipCount, D._nextNumber)

-- новый диплом после перезагрузки не должен занять чужой номер
local okAfter, dipAfter = D.Issue(rector, { graduate = student, specialty = "Логистика" })
check("номер после перезагрузки уникален", okAfter and D.ByNumber(dipAfter.number) ~= nil)
local seen = {}
local dup = false
for _, r in ipairs(D.List) do
    if seen[r.number] then dup = true end
    seen[r.number] = true
end
check("дубликатов номеров нет", not dup)

print("\n=== ТЕСТ 10: битый файл не теряет данные ===")
files["grm_services/invoices.json"] = "{ это не json"
S.LoadInvoices()
check("битый json не роняет загрузку", #S.Invoices == 0)
local backed = false
for path in pairs(files) do
    if path:match("^grm_services/invoices%.json%.corrupt%.") then backed = true end
end
check("создана копия повреждённого файла", backed)

print("\n=== ТЕСТ 11: сводка задолженности ===")
files["grm_services/invoices.json"] = nil
S.LoadInvoices()
GRM.Wanted = { Fines = {
    DebtOf = function() return 2500 end,
    For = function() return {} end,
} }
local _, invD = S.IssueInvoice(rector, student, { title = "Общежитие", amount = 800 })
local sum = S.DebtSummary(student)
check("штрафы учтены в сводке", sum.fines == 2500, sum.fines)
check("счета учтены в сводке", sum.invoices == 800, sum.invoices)
check("итог сложен верно", sum.total == 3300, sum.total)

print("\n=== ТЕСТ 12: единая касса Charge ===")
BANK[student.key], CASH[student.key] = 1000, 1000
local okC = S.Charge(student, 1500, "auto", "тест")
check("auto собрал сумму из двух источников", okC)
check("счёт опустошён", BANK[student.key] == 0, BANK[student.key])
check("наличные списаны частично", CASH[student.key] == 500, CASH[student.key])
local okC2 = S.Charge(student, 5000, "auto", "тест")
check("при нехватке денег списание отклонено", okC2 == false)
check("баланс не изменился после отказа", CASH[student.key] == 500 and BANK[student.key] == 0)
local okC3 = S.Charge(student, 400, "cash", "тест")
check("явный источник cash работает", okC3 and CASH[student.key] == 100)
local okC4 = S.Charge(student, 100, "bank", "тест")
check("на пустом счёте bank отказывает", okC4 == false)

print(("\n=== ИТОГ: %d/%d, failures=%d ==="):format(total - fails, total, fails))
if fails > 0 then os.exit(1) end
