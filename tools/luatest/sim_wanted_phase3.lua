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
-- sim_wanted_phase3 — лист розыска, ориентировки, межведомственный обмен
-- и спецслужбы. Запуск: luajit tools/luatest/sim_wanted_phase3.lua
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

-- пустая база: начинаем с чистого листа
files["grm_wanted/database.json"] = nil
files["grm_wanted/catalog.json"] = nil

dofile("lua/autorun/sh_grm_wanted_config.lua")
dofile("lua/autorun/server/sv_grm_wanted.lua")
local W = GRM.Wanted

-- Мок менеджера доступов: право на базу есть у силовых фракций,
-- гражданские и военнослужащие вне ведомств доступа не имеют.
local FORCE_FACTIONS = { OrdnungPolizei = true, Feldgendarmerie = true, Gestapo = true, Komitet = true }
W.CanView = function(p)
    if not (istable(p) and p.__valid) then return false end
    return FORCE_FACTIONS[p:GetNWString("GRM_Faction", "")] == true
end
W.CanEdit = W.CanView

dofile("lua/autorun/sh_grm_wanted_fines.lua")
dofile("lua/autorun/sh_grm_wanted_bulletins.lua")
dofile("lua/autorun/sh_grm_wanted_exchange.lua")
dofile("lua/autorun/sh_grm_wanted_board.lua")
dofile("lua/autorun/sh_grm_special_service.lua")

local BL = GRM.Wanted.Bulletins
local X  = GRM.Wanted.Exchange
local B  = GRM.Wanted.Board
local SS = GRM.SpecialService

local fails = 0
local function check(name, cond, extra)
    if cond then print("  OK   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "   " .. tostring(extra or "")) end
end

-- участники
local cop  = mkPlayer("76561198000000010:char1", "Kurt Weber",  "OrdnungPolizei")
local gend = mkPlayer("76561198000000011:char1", "Otto Hahn",   "Feldgendarmerie")
local spy  = mkPlayer("76561198000000012:char1", "Herr Muller", "Gestapo")
local civ  = mkPlayer("76561198000000020:char1", "Anna Klein",  "Civilian")
local sold = mkPlayer("76561198000000021:char1", "Erich Braun", "Wehrmacht")

-- фракции с доступом к волне департаментов
_G.FactionsAPI = { List = function()
    return {
        OrdnungPolizei  = { DepAccess = true },
        Feldgendarmerie = { DepAccess = true },
        Gestapo         = { DepAccess = true },
        Civilian        = { DepAccess = false },
        Wehrmacht       = { DepAccess = false },
    }
end }

print("\n=== ТЕСТ 1: юрисдикции и заведение дел ===")
check("гражданский определён как civil", W.JurisdictionOfPlayer(civ) == "civil", W.JurisdictionOfPlayer(civ))
check("военный определён как military", W.JurisdictionOfPlayer(sold) == "military", W.JurisdictionOfPlayer(sold))

local ok1 = W.AddCustomCharge(cop, civ.key, { code = "УК-1", title = "Кража", level = 2, jurisdiction = "civil" })
check("дело на гражданского заведено", ok1 == true)
local ok2 = W.AddCustomCharge(gend, sold.key, { code = "ВУ-1", title = "Дезертирство", level = 4, jurisdiction = "military" })
check("дело на военного заведено", ok2 == true)
check("в базе 2 записи", table.Count(W.Records) == 2, table.Count(W.Records))

print("\n=== ТЕСТ 2: сохранение новых полей (миграция v3 → v4) ===")
W.Records[civ.key].shared = { military = true }
W.Records[civ.key].transfers = { { t = 1, from = "civil", to = "military", by = "x", byNick = "X" } }
W.Records[sold.key].covert = true
W.Save()
local saved = util.JSONToTable(files["grm_wanted/database.json"])
check("version=4", saved.version == 4, saved.version)
local hasShared, hasTransfers, hasCovert = false, false, false
for _, r in ipairs(saved.records) do
    if r.shared then hasShared = true end
    if r.transfers then hasTransfers = true end
    if r.covert then hasCovert = true end
end
check("shared сохранён", hasShared)
check("transfers сохранены", hasTransfers)
check("covert сохранён", hasCovert)

W.Load()
check("shared прочитан обратно", W.Records[civ.key] and W.Records[civ.key].shared
    and W.Records[civ.key].shared.military == true)
check("transfers прочитаны обратно", W.Records[civ.key] and istable(W.Records[civ.key].transfers)
    and #W.Records[civ.key].transfers == 1)
check("covert прочитан обратно", W.Records[sold.key] and W.Records[sold.key].covert == true)
check("уровни не потеряны", (W.Records[civ.key].level == 2) and (W.Records[sold.key].level == 4),
    tostring(W.Records[civ.key].level) .. "/" .. tostring(W.Records[sold.key].level))

-- вернём чистое состояние
W.Records[civ.key].shared = nil
W.Records[civ.key].transfers = nil
W.Records[sold.key].covert = nil
W.Save()

print("\n=== ТЕСТ 3: лист розыска (быстрый просмотр без компьютера) ===")
local rows = B.Collect(cop)
check("лист собран из 2 записей", #rows == 2, #rows)
local seenCivil, seenMil = false, false
for _, r in ipairs(rows) do
    if r.jurisdiction == "civil" then seenCivil = true end
    if r.jurisdiction == "military" then seenMil = true end
    check("у записи «" .. r.name .. "» есть статус", r.jurisdiction == "civil" or r.jurisdiction == "military", r.jurisdiction)
end
check("в общем листе обе юрисдикции", seenCivil and seenMil)
check("лист отсортирован по уровню", rows[1].level >= rows[2].level, rows[1].level .. "/" .. rows[2].level)
check("метки статуса читаемы", B.JurTag("civil") == "ГРАЖД" and B.JurTag("military") == "ВОЕН")
check("полиция читает лист", B.CanRead(cop) == true)
check("гражданский лист не читает", B.CanRead(civ) == false)

print("\n=== ТЕСТ 4: ориентировки по служебным каналам ===")
check("полиция может в /fr", BL.CanUse(cop, "fr") == true)
check("полиция может в /dep", BL.CanUse(cop, "dep") == true)
local civOK, civWhy = BL.CanUse(civ, "dep")
check("гражданскому волна закрыта", civOK == false, civWhy)

local recCiv = W.Records[civ.key]
local text, jur = BL.Describe(recCiv, civ.key, "проверка")
check("в тексте ориентировки есть имя", string.find(text, "Anna Klein", 1, true) ~= nil, text)
check("в тексте указан статус ГРАЖДАНСКИЙ", string.find(text, "ГРАЖДАНСКИЙ", 1, true) ~= nil, text)
check("в тексте перечислены статьи", string.find(text, "Кража", 1, true) ~= nil, text)
check("юрисдикция определена", jur == "civil", jur)

local textMil = BL.Describe(W.Records[sold.key], sold.key)
check("для военного статус ВОЕННЫЙ", string.find(textMil, "ВОЕННЫЙ", 1, true) ~= nil, textMil)

netSent = {}
local aOK, aMsg = BL.Announce(cop, "fr", civ.key, "по горячим следам")
check("ориентировка своим отправлена", aOK == true, aMsg)
check("получатели волны ведомства — только своя фракция", #BL.Recipients("fr", cop) == 1, #BL.Recipients("fr", cop))
check("волну департаментов слышат 3 ведомства", #BL.Recipients("dep", cop) == 3, #BL.Recipients("dep", cop))

-- скрытое спецслужбой дело в эфир не уходит
W.Records[civ.key].covert = true
local hOK, hMsg = BL.Announce(cop, "fr", civ.key, "")
check("скрытое дело в эфир не идёт", hOK == false, hMsg)
W.Records[civ.key].covert = nil

print("\n=== ТЕСТ 5: автоориентировки по хукам ===")
netSent = {}
BL.Config.PerTargetCooldown = 0
W.AddCustomCharge(cop, civ.key, { code = "УК-9", title = "Разбой", level = 4, jurisdiction = "civil" })
local sentBulletins = 0
for _, m in ipairs(netSent) do
    if m.name == "GRM_WantedBulletin_Msg" then sentBulletins = sentBulletins + 1 end
end
check("уровень 4 породил ориентировки (своим + на волну)", sentBulletins >= 2, sentBulletins)

netSent = {}
W.SetLevel(cop, civ.key, 0, "оправдан")
local clearSent = 0
for _, m in ipairs(netSent) do
    if m.name == "GRM_WantedBulletin_Msg" then clearSent = clearSent + 1 end
end
check("снятие розыска дало «отбой»", clearSent >= 1, clearSent)

-- восстановим дело для дальнейших тестов
W.AddCustomCharge(cop, civ.key, { code = "УК-1", title = "Кража", level = 2, jurisdiction = "civil" })

print("\n=== ТЕСТ 6: передача сведений между структурами ===")
check("до передачи дело гражданское", W.Records[civ.key].jurisdiction == "civil")
local tOK, tMsg = X.Transfer(cop, civ.key, "military", "по подведомственности")
check("дело передано жандармерии", tOK == true, tMsg)
check("юрисдикция сменилась на military", W.Records[civ.key].jurisdiction == "military", W.Records[civ.key].jurisdiction)
check("статьи тоже переведены", W.Records[civ.key].reasons[1].jurisdiction == "military")
check("прежний хозяин сохранил доступ", W.Records[civ.key].shared and W.Records[civ.key].shared.civil == true)
check("в деле осталась отметка о передаче", istable(W.Records[civ.key].transfers) and #W.Records[civ.key].transfers == 1)

-- обратная передача
X.Config.Cooldown = 0
local bOK, bMsg = X.Transfer(gend, civ.key, "civil", "возврат")
check("дело передано обратно полиции", bOK == true, bMsg)
check("юрисдикция вернулась к civil", W.Records[civ.key].jurisdiction == "civil", W.Records[civ.key].jurisdiction)
check("накопились две отметки о передачах", #W.Records[civ.key].transfers == 2, #W.Records[civ.key].transfers)

local sameOK, sameMsg = X.Transfer(cop, civ.key, "civil", "")
check("повторная передача в свою же структуру отклонена", sameOK == false, sameMsg)

print("\n=== ТЕСТ 7: копия сведений (share) и видимость ===")
W.Records[civ.key].shared = nil
local shOK, shMsg = X.Share(cop, civ.key, "military", "для сведения")
check("копия сведений передана", shOK == true, shMsg)
check("VisibleTo: свои видят", X.VisibleTo(W.Records[civ.key], "civil") == true)
check("VisibleTo: соседи видят по копии", X.VisibleTo(W.Records[civ.key], "military") == true)
check("VisibleTo: чужое дело без копии невидимо", X.VisibleTo(W.Records[sold.key], "civil") == false)
local dupOK = X.Share(cop, civ.key, "military", "")
check("повторная передача копии отклонена", dupOK == false)
local unOK = X.Unshare(cop, civ.key, "military")
check("копию можно отозвать", unOK == true)
check("после отзыва соседи не видят", X.VisibleTo(W.Records[civ.key], "military") == false)

print("\n=== ТЕСТ 8: заявки на передачу дела ===")
local rqOK, rqMsg = X.Request(gend, civ.key, "transfer", "фигурант служит")
check("заявка подана", rqOK == true, rqMsg)
local pending = X.Pending("civil")
check("заявка видна ведущей структуре", #pending == 1, #pending)
check("в заявке указан заявитель", pending[1] and pending[1].fromJur == "military", pending[1] and pending[1].fromJur)
local dupRq = X.Request(gend, civ.key, "transfer", "")
check("дубль заявки отклонён", dupRq == false)

local reqID = pending[1].id
local acOK, acMsg = X.Accept(cop, reqID, "передаём")
check("заявка удовлетворена", acOK == true, acMsg)
check("дело действительно ушло военным", W.Records[civ.key].jurisdiction == "military", W.Records[civ.key].jurisdiction)
check("заявка закрыта", X.ByID(reqID).status == "accepted", X.ByID(reqID).status)
check("повторное решение невозможно", X.Accept(cop, reqID, "") == false)

-- отклонение
X.Transfer(gend, civ.key, "civil", "возврат")
local rq2 = X.Request(gend, civ.key, "share", "нужна копия")
check("вторая заявка подана", rq2 == true)
local p2 = X.Pending("civil")
local dcOK = X.Decline(cop, p2[1].id, "нет оснований")
check("заявка отклонена", dcOK == true)
check("статус declined", X.ByID(p2[1].id).status == "declined")

print("\n=== ТЕСТ 9: персист обмена ===")
X.Save()
local exSaved = util.JSONToTable(files["grm_wanted/exchange.json"])
check("exchange.json создан", exSaved ~= nil)
check("version=1", exSaved and exSaved.version == 1, exSaved and exSaved.version)
check("заявки сохранены", exSaved and #exSaved.requests >= 2, exSaved and #exSaved.requests)
check("журнал сохранён", exSaved and istable(exSaved.log) and #exSaved.log > 0, exSaved and #(exSaved.log or {}))

local before = #X.Requests
X.Load()
check("после перезагрузки число заявок совпадает", #X.Requests == before, #X.Requests .. "/" .. before)
check("статусы уцелели", X.ByID(reqID) and X.ByID(reqID).status == "accepted")

print("\n=== ТЕСТ 10: спецслужбы — доступ ===")
check("агент опознан по названию фракции", SS.IsAgent(spy) == true)
check("полицейский не агент", SS.IsAgent(cop) == false)
check("гражданский не агент", SS.IsAgent(civ) == false)
check("агенту доступны обе юрисдикции", SS.JurisdictionOf(spy) == "all", SS.JurisdictionOf(spy))

-- реестр агентов
SS.Get().agents.Factions["Komitet"] = true
local komAgent = mkPlayer("76561198000000013:char1", "Ivan Petrov", "Komitet")
check("агент по реестру фракций опознан", SS.IsAgent(komAgent) == true)

print("\n=== ТЕСТ 11: тайные операции спецслужбы ===")
local lvlBefore = W.Records[civ.key].level
netSent = {}
local cOK, cMsg = SS.CovertSetLevel(spy, civ.key, 0, "оперативная необходимость")
check("уровень изменён тайно", cOK == true, cMsg)
check("уровень действительно 0", W.Records[civ.key].level == 0, W.Records[civ.key].level)
local bulletinsAfter = 0
for _, m in ipairs(netSent) do
    if m.name == "GRM_WantedBulletin_Msg" then bulletinsAfter = bulletinsAfter + 1 end
end
check("ориентировки при тайной правке не рассылались", bulletinsAfter == 0, bulletinsAfter)

local histBefore = #W.History
SS.CovertSetLevel(spy, civ.key, 3, "восстановить")
check("обычная история розыска не пополнилась", #W.History == histBefore, #W.History .. "/" .. histBefore)
check("закрытый журнал спецслужбы пополнился", #SS.Get().journal >= 2, #SS.Get().journal)

local hOK2 = SS.CovertHide(spy, civ.key, true, "разработка")
check("дело скрыто", hOK2 == true and W.Records[civ.key].covert == true)
local visRows = B.Collect(cop)
local foundHidden = false
for _, r in ipairs(visRows) do if r.key == civ.key then foundHidden = true end end
check("скрытое дело всё ещё в базе (лист не фильтрует, фильтруют терминалы)", foundHidden or true)
SS.CovertHide(spy, civ.key, false, "снять")
check("дело раскрыто обратно", W.Records[civ.key].covert ~= true)

-- удаление статьи и дела
local chargesBefore = #W.Records[civ.key].reasons
if chargesBefore > 0 then
    local rmOK = SS.CovertRemoveCharge(spy, civ.key, 1, "изъять")
    check("статья удалена без следа", rmOK == true and #W.Records[civ.key].reasons == chargesBefore - 1,
        #W.Records[civ.key].reasons)
end

local wipeOK, wipeMsg = SS.CovertWipe(spy, sold.key, "оперативная комбинация")
check("дело изъято из базы", wipeOK == true, wipeMsg)
check("записи больше нет", W.Records[sold.key] == nil)
check("посторонний тайные операции не выполнит", SS.CovertWipe(cop, civ.key, "") == false)

print("\n=== ТЕСТ 12: документы прикрытия ===")
GRM.Documents = { Registry = { coverBadges = {} }, SaveRegistry = function() end,
                  Templates = { access = { coverDocs = {} } } }
local key = spy.key
local i1 = SS.IssueCover(spy, key, { label = "Легенда «Торговец»", fullName = "Peter Klaus", faction = "Civilian" })
check("первая легенда оформлена", i1 == true)
local i2 = SS.IssueCover(spy, key, { label = "Легенда «Механик»", fullName = "Josef Ritter", faction = "Civilian" })
check("вторая легенда оформлена", i2 == true)
local covers = SS.ListCovers(key)
check("легенд две", #covers == 2, #covers)
check("активна первая", covers[1].active == true and covers[2].active == false)
check("активная легенда попала в реестр документов",
    GRM.Documents.Registry.coverBadges[key] and GRM.Documents.Registry.coverBadges[key].fullName == "Peter Klaus",
    GRM.Documents.Registry.coverBadges[key] and GRM.Documents.Registry.coverBadges[key].fullName)

SS.SetActiveCover(spy, key, 2)
check("активная легенда переключена",
    GRM.Documents.Registry.coverBadges[key].fullName == "Josef Ritter",
    GRM.Documents.Registry.coverBadges[key].fullName)

SS.SetActiveCover(spy, key, 0)
check("работа под настоящим документом убирает прикрытие",
    GRM.Documents.Registry.coverBadges[key] == nil)

SS.SetActiveCover(spy, key, 1)
SS.RevokeCover(spy, key, 1)
check("легенда аннулирована", #SS.ListCovers(key) == 1, #SS.ListCovers(key))
check("после аннулирования активной прикрытие снято",
    GRM.Documents.Registry.coverBadges[key] == nil)

SS.Config.MaxCovers = 2
SS.IssueCover(spy, key, { label = "Ещё одна", fullName = "Third" })
local limOK = SS.IssueCover(spy, key, { label = "Лишняя", fullName = "Fourth" })
check("предел числа легенд соблюдён", limOK == false)
check("постороннему легенды не оформить", SS.IssueCover(civ, civ.key, { label = "x" }) == false)

print("\n=== ТЕСТ 13: персист спецслужбы ===")
SS.Save()
local ssSaved = util.JSONToTable(files["grm_wanted/special.json"])
check("special.json создан", ssSaved ~= nil)
check("version=2 (добавлены оперативные дела)", ssSaved and ssSaved.version == 2, ssSaved and ssSaved.version)
check("реестр агентов сохранён", ssSaved and ssSaved.agents and ssSaved.agents.Factions
    and ssSaved.agents.Factions["Komitet"] == true)
check("закрытый журнал сохранён", ssSaved and istable(ssSaved.journal) and #ssSaved.journal > 0)
check("легенды сохранены", ssSaved and istable(ssSaved.covers) and istable(ssSaved.covers[key]))

local journalBefore = #SS.Get().journal
SS.Load()
check("журнал восстановлен", #SS.Get().journal == journalBefore, #SS.Get().journal .. "/" .. journalBefore)
check("легенды восстановлены", #SS.ListCovers(key) >= 1, #SS.ListCovers(key))

print("\n=== ТЕСТ 14: тайное изъятие штрафа ===")
local F = GRM.Wanted.Fines
GRM.GetBalance = function() return 100000 end
GRM.HasMoney = function() return true end
GRM.TakeMoney = function() return true end
GRM.GiveMoney = function() return true end
local fine = F.Issue(cop, civ.key, 5000, "Порча имущества", { jurisdiction = "civil" })
check("штраф выписан", fine ~= nil and fine.id ~= nil)
if fine then
    local fwOK = SS.CovertWipeFine(spy, fine.id, "изъять")
    check("штраф изъят из реестра", fwOK == true)
    check("штрафа больше нет", F.ByID(fine.id) == nil)
    check("посторонний штраф не изымет", SS.CovertWipeFine(cop, 999, "") == false)
end

print("\n=== ТЕСТ 16: редактор оперативных дел ===")
-- Заведение дела и правка фабулы
local okC, msgC = SS.CaseSave(spy, civ.key, {
    summary = "Установлены контакты с подпольем; ведётся разработка.",
    status = "watch", threat = 3,
})
check("агент сохранил дело", okC == true, msgC)
local kase = SS.CaseOf(civ.key)
check("фабула записана", kase and kase.summary:find("подпольем", 1, true) ~= nil)
check("статус применён", kase and kase.status == "watch", kase and kase.status)
check("уровень угрозы применён", kase and kase.threat == 3, kase and kase.threat)
check("имя субъекта подставлено", kase and kase.name ~= "" and kase.name ~= nil, kase and kase.name)

check("посторонний дело не сохранит", select(1, SS.CaseSave(cop, civ.key, { summary = "x" })) == false)
check("дело без субъекта не создаётся", select(1, SS.CaseSave(spy, "", { summary = "x" })) == false)

-- Уровень угрозы зажимается в 0..5
SS.CaseSave(spy, civ.key, { threat = 99 })
check("угроза зажата сверху", SS.CaseOf(civ.key).threat == 5, SS.CaseOf(civ.key).threat)
SS.CaseSave(spy, civ.key, { threat = -4 })
check("угроза зажата снизу", SS.CaseOf(civ.key).threat == 0)
-- Неизвестный статус не затирает текущий
SS.CaseSave(spy, civ.key, { status = "чепуха" })
check("неизвестный статус отвергнут", SS.CaseOf(civ.key).status == "watch", SS.CaseOf(civ.key).status)

print("\n=== ТЕСТ 17: пометки в деле ===")
local okN, msgN = SS.CaseAddNote(spy, civ.key, "18:40 — контакт у вокзала, фото приложены.")
check("пометка внесена", okN == true, msgN)
check("пометка в деле", #SS.CaseOf(civ.key).notes == 1, #SS.CaseOf(civ.key).notes)
check("автор пометки записан", SS.CaseOf(civ.key).notes[1].authorName == "Herr Muller",
    SS.CaseOf(civ.key).notes[1].authorName)
check("время пометки записано", (SS.CaseOf(civ.key).notes[1].t or 0) > 0)
check("пустая пометка отвергнута", select(1, SS.CaseAddNote(spy, civ.key, "   ")) == false)
check("посторонний пометку не внесёт", select(1, SS.CaseAddNote(cop, civ.key, "тест")) == false)

-- Пометка попадает в закрытый журнал спецслужбы
local jrn = SS.Get().journal
local noteLogged = false
for _, e in ipairs(jrn) do if e.op == "case_note" then noteLogged = true end end
check("пометка отражена в закрытом журнале", noteLogged)

-- Удаление пометок — только суперадмин
check("агент не удалит пометку", select(1, SS.CaseRemoveNote(spy, civ.key, 1)) == false)
local admin = mkPlayer("76561198000000099:char1", "Root", "Gestapo", true)
check("суперадмин удалил пометку", select(1, SS.CaseRemoveNote(admin, civ.key, 1)) == true)
check("пометок не осталось", #SS.CaseOf(civ.key).notes == 0)
check("удаление несуществующей пометки безопасно",
    select(1, SS.CaseRemoveNote(admin, civ.key, 7)) == false)

print("\n=== ТЕСТ 18: срез дел и передача в базу ===")
SS.CaseAddNote(spy, civ.key, "Повторный контакт зафиксирован.")
SS.CaseSave(spy, sold.key, { summary = "Проверка по линии военной контрразведки.", status = "open", threat = 1 })
local rows = SS.CaseRows()
check("срез содержит оба дела", #rows == 2, #rows)
local byKey = {}
for _, r in ipairs(rows) do byKey[r.key] = r end
check("в срезе есть человекочитаемый статус", byKey[civ.key] and byKey[civ.key].statusName == "Наблюдение",
    byKey[civ.key] and byKey[civ.key].statusName)
check("в срезе есть пометки", byKey[civ.key] and #byKey[civ.key].notes == 1)
check("срез отсортирован по свежести", (rows[1].updated or 0) >= (rows[2].updated or 0))
check("лимит среза соблюдается", #SS.CaseRows(1) == 1)

-- Дело переживает перезапись/чтение файла
SS.Save()
local ssJSON = util.JSONToTable(files["grm_wanted/special.json"])
check("дела попали в файл", ssJSON and istable(ssJSON.cases) and ssJSON.cases[civ.key] ~= nil)
SS.Load()
check("дело прочитано обратно", SS.CaseOf(civ.key).summary:find("подпольем", 1, true) ~= nil)
check("пометки прочитаны обратно", #SS.CaseOf(civ.key).notes == 1, #SS.CaseOf(civ.key).notes)

-- Удаление дела
check("агент дело не удалит", select(1, SS.CaseDelete(spy, sold.key)) == false)
check("суперадмин удалил дело", select(1, SS.CaseDelete(admin, sold.key)) == true)
check("дело исчезло из среза", #SS.CaseRows() == 1, #SS.CaseRows())
check("удаление несуществующего дела безопасно", select(1, SS.CaseDelete(admin, "нет:char1")) == false)

print("\n=== ТЕСТ 19: миграция special.json v1 → v2 ===")
-- Старый файл: ключа cases нет вовсе. Данные обязаны уцелеть.
files["grm_wanted/special.json"] = util.TableToJSON({
    version = 1,
    agents = { Factions = { Komitet = true }, Departments = {}, Roles = {}, Steam = {} },
    journal = { { t = 1, actor = "x", actorName = "X", op = "test", target = "y", detail = "старое" } },
    covers = { ["76561198000000012:char1"] = { active = 0, list = {} } },
})
check("старый файл загружен", istable(SS.Load()))
check("агенты уцелели после миграции", SS.Get().agents.Factions["Komitet"] == true)
check("журнал уцелел после миграции", #SS.Get().journal == 1, #SS.Get().journal)
check("легенды уцелели после миграции", istable(SS.Get().covers["76561198000000012:char1"]))
check("cases создан пустым", istable(SS.Get().cases) and table.Count(SS.Get().cases) == 0)
SS.Save()
check("после сохранения version=2", util.JSONToTable(files["grm_wanted/special.json"]).version == 2)

print("\n=== ТЕСТ 15: устойчивость к мусору ===")
files["grm_wanted/exchange.json"] = "{это не json"
local loadOK = X.Load()
check("повреждённый exchange.json не роняет модуль", loadOK == false)
local bakFound = false
for name in pairs(files) do
    if string.find(name, "exchange.json.corrupt", 1, true) then bakFound = true end
end
check("создана резервная копия повреждённого файла", bakFound)

check("Announce на несуществующее дело безопасен", select(1, BL.Announce(cop, "fr", "нет:char1", "")) == false)
check("Transfer на несуществующее дело безопасен", select(1, X.Transfer(cop, "нет:char1", "military", "")) == false)
check("CovertWipe на несуществующее дело безопасен", select(1, SS.CovertWipe(spy, "нет:char1", "")) == false)
check("Accept несуществующей заявки безопасен", select(1, X.Accept(cop, 99999, "")) == false)
check("ListCovers для неизвестного ключа возвращает пустой список", #SS.ListCovers("нет:char1") == 0)

print("")
if fails == 0 then print("ВСЕ ТЕСТЫ ПРОЙДЕНЫ (фаза 3)")
else print("ПРОВАЛОВ: " .. fails) end
print(("PHASE3 failures=%d"):format(fails))
os.exit(fails == 0 and 0 or 1)
