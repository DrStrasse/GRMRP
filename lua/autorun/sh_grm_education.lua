--[[--------------------------------------------------------------------
    GRM Education v1.0.0 — рабочее место учреждения образования

    ЗАЧЕМ ЭТОТ МОДУЛЬ СУЩЕСТВУЕТ
    ----------------------------
    Раньше диплом выписывали через банкомат. Это было неправильно:
    банкомат — это касса, а не деканат. Разделение ответственности:

      • БАНКОМАТ (sh_grm_atm.lua) — только деньги и справки:
        оплата обучения по счёту, проверка чужого диплома по номеру,
        просмотр своих дипломов. Выписывать бланки там больше нельзя.

      • УЧРЕЖДЕНИЕ ОБРАЗОВАНИЯ (этот модуль) — выписка бланков:
        вкладка «Учреждение образования» в меню фракций (F4/меню лидера)
        и отдельная сущность grm_comp_education — компьютер деканата.

    Кто и что может:
      • сотрудник учреждения (фракция с доступом canDiploma) — выписывать
        дипломы и видеть реестр своего учреждения;
      • руководитель учреждения — плюс аннулирование своих дипломов;
      • суперадмин — всё и по любому учреждению.

    Выпускник выбирается из РЕЕСТРА ПЕРСОНАЖЕЙ (GRM.Services.CharacterRegistry):
    онлайн, офлайн из паспортов и составов фракций. Диплом принадлежит
    персонажу (CharacterKey), а не сессии игрока.

    Данные модуль не хранит — источник истины остаётся
    data/grm_services/diplomas.json (sh_grm_diplomas.lua). Миграция не
    требуется: формат записей не менялся.
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Education = GRM.Education or {}

local EDU = GRM.Education
EDU.Version = "1.0.0"

EDU.Config = EDU.Config or {
    UseRange     = 200,     -- дистанция до компьютера деканата
    RateLimit    = 0.35,    -- пауза между действиями, сек
    MaxDiplomas  = 200,     -- сколько записей реестра отдаём клиенту
    MaxCharacters= 400,     -- сколько персонажей отдаём в выбор выпускника
}

-----------------------------------------------------------------------
-- ОБЩЕЕ
-----------------------------------------------------------------------
local function money(v)
    if GRM.FormatMoney then return GRM.FormatMoney(v) end
    return string.Comma(math.floor(tonumber(v) or 0)) .. " GRM"
end

-----------------------------------------------------------------------
-- СЕРВЕР
-----------------------------------------------------------------------
if SERVER then

util.AddNetworkString("GRM_Edu_Open")     -- сервер -> клиент: снимок данных
util.AddNetworkString("GRM_Edu_Data")     -- сервер -> клиент: обновление
util.AddNetworkString("GRM_Edu_Act")      -- клиент -> сервер: действие
util.AddNetworkString("GRM_Edu_Result")   -- сервер -> клиент: итог
util.AddNetworkString("GRM_Edu_Request")  -- клиент -> сервер: дай данные
util.AddNetworkString("GRM_Edu_MyAsk")    -- клиент -> сервер: мои дипломы
util.AddNetworkString("GRM_Edu_MyData")   -- сервер -> клиент: мои дипломы
util.AddNetworkString("GRM_Edu_ShowAsk")  -- клиент -> сервер: показать диплом
util.AddNetworkString("GRM_Edu_ShowView") -- сервер -> клиент: вам показали

local nextAct = {}
local nextMine = {} -- список своих дипломов не должен блокировать немедленное предъявление

local function result(ply, ok, msg)
    if not IsValid(ply) then return end
    net.Start("GRM_Edu_Result")
        net.WriteBool(ok and true or false)
        net.WriteString(tostring(msg or ""))
    net.Send(ply)
    if GRM.Notify then
        GRM.Notify(ply, tostring(msg or ""), ok and 120 or 255, ok and 220 or 140, ok and 150 or 120)
    end
end

--- Может ли игрок работать с рабочим местом учреждения.
-- Единый источник истины — GRM.Diplomas.CanIssue (доступ canDiploma
-- у фракции + байпас суперадмина). Своей копии прав здесь нет намеренно.
function EDU.CanUse(ply)
    local D = GRM.Diplomas
    if not D or not isfunction(D.CanIssue) then return false, nil, "Модуль дипломов не загружен" end
    return D.CanIssue(ply)
end

--- Снимок данных рабочего места.
function EDU.Snapshot(ply)
    local D, S = GRM.Diplomas, GRM.Services
    local can, fname = EDU.CanUse(ply)
    local isSuper = IsValid(ply) and ply:IsSuperAdmin()

    local snap = {
        canIssue    = can and true or false,
        isSuper     = isSuper and true or false,
        faction     = fname or "",
        institution = "",
        isLeader    = false,
        levels      = {},
        forms       = {},
        diplomas    = {},
        characters  = {},
        stats       = { total = 0, valid = 0, revoked = 0 },
    }

    if D then
        for _, l in ipairs(D.Levels or {}) do snap.levels[#snap.levels + 1] = { id = l.id, name = l.name } end
        for _, f in ipairs(D.Forms  or {}) do snap.forms[#snap.forms  + 1] = { id = f.id, name = f.name } end
        if fname and fname ~= "" and isfunction(D.InstitutionOf) then
            snap.institution = D.InstitutionOf(fname)
        end
    end

    if S and isfunction(S.IsLeaderOf) and fname then
        snap.isLeader = S.IsLeaderOf(ply, fname) and true or false
    end

    -- Реестр своего учреждения; суперадмину — весь реестр.
    if D then
        local list
        if isSuper and isfunction(D.Page) then
            list = D.Page({}, 0, EDU.Config.MaxDiplomas)
        elseif fname and isfunction(D.ByFaction) then
            list = D.ByFaction(fname, EDU.Config.MaxDiplomas)
        end
        for _, rec in ipairs(list or {}) do
            snap.diplomas[#snap.diplomas + 1] = {
                number = rec.number, graduate = rec.graduate, graduateName = rec.graduateName,
                institution = rec.institution, faction = rec.faction, specialty = rec.specialty,
                qualification = rec.qualification, level = rec.level, form = rec.form,
                grade = rec.grade, paid = rec.paid, invoiceID = rec.invoiceID,
                issued = rec.issued, revoked = rec.revoked, revokeReason = rec.revokeReason,
                issuerName = rec.issuerName, signedBy = rec.signedBy,
            }
            snap.stats.total = snap.stats.total + 1
            if rec.revoked then snap.stats.revoked = snap.stats.revoked + 1
            else snap.stats.valid = snap.stats.valid + 1 end
        end
    end

    -- Выпускники: персонажи, а не сессии (см. GRM.Services.CharacterRegistry)
    if S and isfunction(S.CharacterRegistry) then
        local n = 0
        for _, rec in ipairs(S.CharacterRegistry()) do
            snap.characters[#snap.characters + 1] = {
                key = rec.key, name = rec.name, faction = rec.faction, online = rec.online,
            }
            n = n + 1
            if n >= EDU.Config.MaxCharacters then break end
        end
    end

    return snap
end

--- Открыть рабочее место (по компьютеру деканата).
function EDU.Open(ply, ent)
    if not (IsValid(ply) and ply:IsPlayer()) then return end
    if IsValid(ent) and ply:GetPos():DistToSqr(ent:GetPos()) > (EDU.Config.UseRange ^ 2) then return end

    local can, _, why = EDU.CanUse(ply)
    if not can then
        if GRM.Notify then GRM.Notify(ply, why or "Нет доступа", 255, 150, 120)
        else ply:ChatPrint(why or "Нет доступа") end
        return
    end

    ply._grmEduEnt = IsValid(ent) and ent or nil
    net.Start("GRM_Edu_Open")
        net.WriteTable(EDU.Snapshot(ply))
    net.Send(ply)
end

--- Дослать свежие данные (после действия).
local function push(ply)
    if not IsValid(ply) then return end
    net.Start("GRM_Edu_Data")
        net.WriteTable(EDU.Snapshot(ply))
    net.Send(ply)
end
EDU.Push = push

-----------------------------------------------------------------------
-- Действия
-----------------------------------------------------------------------
local handlers = {}

handlers.issue = function(ply, a)
    local D = GRM.Diplomas
    if not D then return false, "Модуль дипломов не загружен" end
    local ok, res = D.Issue(ply, {
        graduate      = a.graduate,
        institution   = a.institution,
        specialty     = a.specialty,
        qualification = a.qualification,
        level         = a.level,
        form          = a.form,
        grade         = a.grade,
        paid          = a.paid == true,
        invoiceID     = a.invoiceID,
        signedBy      = a.signedBy,
        note          = a.note,
    })
    if not ok then return false, tostring(res) end
    return true, ("Диплом %s выдан: %s — %s")
        :format(res.number, tostring(res.graduateName), tostring(res.specialty))
end

handlers.revoke = function(ply, a)
    local D = GRM.Diplomas
    if not D then return false, "Модуль дипломов не загружен" end
    local ok, res = D.Revoke(ply, a.number, a.reason)
    if not ok then return false, tostring(res) end
    return true, ("Диплом %s аннулирован"):format(tostring(res.number))
end

handlers.check = function(ply, a)
    local D = GRM.Diplomas
    if not D then return false, "Модуль дипломов не загружен" end
    local rec = D.ByNumber(a.number)
    if not rec then return false, "Диплом с таким номером не найден" end
    return true, ("%s | %s | %s | %s | %s"):format(
        rec.number, tostring(rec.graduateName), tostring(rec.institution),
        tostring(rec.specialty), rec.revoked and "АННУЛИРОВАН" or "ДЕЙСТВИТЕЛЕН")
end

handlers.refresh = function() return true, "" end

--- Правка бланка: учреждение — свой диплом, суперадмин — любой.
handlers.edit = function(ply, a)
    local D = GRM.Diplomas
    if not D or not isfunction(D.Edit) then return false, "Правка недоступна" end
    local ok, res = D.Edit(ply, a.number, a.patch or {})
    if not ok then return false, tostring(res) end
    return true, ("Диплом %s изменён"):format(tostring(a.number))
end

net.Receive("GRM_Edu_Act", function(_, ply)
    if not IsValid(ply) then return end
    local action = net.ReadString()
    local args = net.ReadTable() or {}

    local now = CurTime()
    if (nextAct[ply] or 0) > now then return end
    nextAct[ply] = now + EDU.Config.RateLimit

    -- Если работа идёт от компьютера деканата — проверяем дистанцию.
    -- Из меню фракций сущности нет, тогда проверка не нужна.
    local ent = ply._grmEduEnt
    if IsValid(ent) and ply:GetPos():DistToSqr(ent:GetPos()) > (EDU.Config.UseRange ^ 2) then
        result(ply, false, "Вы отошли от рабочего места")
        return
    end

    local can, _, why = EDU.CanUse(ply)
    if not can then result(ply, false, why or "Нет доступа") return end

    local h = handlers[action]
    if not h then result(ply, false, "Неизвестная операция") return end

    local ok, msg = h(ply, args)
    if msg and msg ~= "" then result(ply, ok, msg) end
    push(ply)
end)

net.Receive("GRM_Edu_Request", function(_, ply)
    if not IsValid(ply) then return end
    local now = CurTime()
    if (nextAct[ply] or 0) > now then return end
    nextAct[ply] = now + EDU.Config.RateLimit
    -- Данные шлём всем, у кого есть доступ; вкладка сама решает, что рисовать.
    push(ply)
end)

--- Личные дипломы игрока.
-- Доступно ВСЕМ без каких-либо прав: это собственный документ персонажа,
-- как паспорт или права. Аннулированные тоже отдаём — владелец должен
-- видеть, что бланк аннулирован, а не думать, что документ потерялся.
function EDU.MyDiplomas(ply)
    local out = {}
    local D = GRM.Diplomas
    if not (IsValid(ply) and D and isfunction(D.For)) then return out end

    for _, rec in ipairs(D.For(ply, true) or {}) do
        out[#out + 1] = {
            number        = rec.number,
            institution   = rec.institution,
            graduateName  = rec.graduateName,
            specialty     = rec.specialty,
            qualification = rec.qualification,
            level         = rec.level,
            levelName     = isfunction(D.LevelName) and D.LevelName(rec.level) or tostring(rec.level or ""),
            form          = rec.form,
            formName      = isfunction(D.FormName) and D.FormName(rec.form) or tostring(rec.form or ""),
            grade         = rec.grade,
            paid          = rec.paid == true,
            issued        = rec.issued,
            issuerName    = rec.issuerName,
            signedBy      = rec.signedBy,
            note          = rec.note,
            revoked       = rec.revoked == true,
            revokeReason  = rec.revokeReason,
        }
    end
    return out
end

--- Показ диплома игроку перед собой — как паспорт или военный билет.
-- Дистанция 200 юнитов и объявление в /me на 400 — те же правила, что
-- у остальных документов (sh_grm_documents.lua), чтобы поведение
-- не отличалось от привычного игрокам.
-- Вечер-13: дубль развилки из sh_grm_documents удалён — одна шина.
local function announce(ply, meText)
    return GRM.RPBroadcast(ply, meText, 400)
end

local function showDiplomaToAim(ply,number)
    if not IsValid(ply) then return false end
    number=string.sub(tostring(number or ""),1,32)
    local target=ply:GetEyeTrace().Entity
    if not (IsValid(target) and target:IsPlayer() and target:Alive()) then
        if GRM.Notify then GRM.Notify(ply,"Наведитесь на игрока перед собой.",255,180,90) end
        return false
    end
    if ply:GetPos():DistToSqr(target:GetPos())>200*200 then
        if GRM.Notify then GRM.Notify(ply,"Игрок слишком далеко — подойдите ближе.",255,180,90) end
        return false
    end
    local mine=EDU.MyDiplomas(ply); local rec
    if number~="" then for _,d in ipairs(mine) do if d.number==number then rec=d break end end
    else for _,d in ipairs(mine) do if not d.revoked then rec=d break end end; rec=rec or mine[1] end
    if not rec then if GRM.Notify then GRM.Notify(ply,"У вас нет такого диплома.",255,140,110) end return false end
    local tName=target:GetNWString("GRM_RPName",""); if tName=="" then tName=target:Nick() end
    announce(ply,("предъявил(а) диплом игроку %s (%s, %s)"):format(tName,rec.number,rec.specialty~="" and rec.specialty or "специальность не указана"))
    net.Start("GRM_Edu_ShowView"); net.WriteTable(rec); net.WriteString((ply:GetNWString("GRM_RPName","")~="" and ply:GetNWString("GRM_RPName","")) or ply:Nick()); net.Send(target)
    if GRM.Notify then GRM.Notify(ply,"Вы предъявили диплом игроку "..tName..".",100,220,130) end
    return true
end
EDU.ShowDiplomaToAim=showDiplomaToAim

local function requestShow(ply,number)
    local now=CurTime(); if (nextAct[ply] or 0)>now then return false end
    nextAct[ply]=now+EDU.Config.RateLimit
    return showDiplomaToAim(ply,number)
end

net.Receive("GRM_Edu_ShowAsk",function(_,ply)
    if not IsValid(ply) then return end
    requestShow(ply,net.ReadString() or "")
end)

local function showChat(ply,text)
    local raw=string.Trim(tostring(text or "")); local low=string.lower(raw); local prefix
    for _,cmd in ipairs({"/showdiploma","/покдиплом","/предъявитьдиплом"}) do if low==cmd or string.sub(low,1,#cmd+1)==cmd.." " then prefix=cmd break end end
    if not prefix then return false end
    if ply._grmEduShowCmdAt==CurTime() then return true end; ply._grmEduShowCmdAt=CurTime()
    requestShow(ply,string.Trim(string.sub(raw,#prefix+1)))
    return true
end
hook.Add("PlayerSayTransform","GRM_Edu_ShowCmdTransform",function(ply,data) if istable(data) and isstring(data[1]) and showChat(ply,data[1]) then data[1]="" data.SkipPlayerSay=true end end)
hook.Add("PlayerSay","GRM_Edu_ShowCmd",function(ply,text) if showChat(ply,text) then return "" end end)

net.Receive("GRM_Edu_MyAsk", function(_, ply)
    if not IsValid(ply) then return end
    local now = CurTime()
    if (nextMine[ply] or 0) > now then return end
    nextMine[ply] = now + 0.2

    net.Start("GRM_Edu_MyData")
        net.WriteTable(EDU.MyDiplomas(ply))
    net.Send(ply)
end)

hook.Add("PlayerDisconnected", "GRM_Edu_Cleanup", function(ply)
    nextAct[ply] = nil
    nextMine[ply] = nil
end)

end -- SERVER

-----------------------------------------------------------------------
-- КЛИЕНТ
-----------------------------------------------------------------------
if CLIENT then

local snap = {}
EDU.Snap = snap

local UI = {
    bg     = Color(16, 22, 34, 250),
    panel  = Color(22, 30, 46, 245),
    panel2 = Color(26, 36, 54, 245),
    line   = Color(60, 80, 110, 200),
    text   = Color(232, 238, 248),
    muted  = Color(150, 168, 192),
    cyan   = Color(90, 180, 255),
    green  = Color(80, 200, 130),
    red    = Color(225, 90, 90),
    gold   = Color(245, 205, 80),
}
EDU.UI = UI

surface.CreateFont("GRM_Edu_Title", { font = "Roboto", size = 22, weight = 700, extended = true })
surface.CreateFont("GRM_Edu_Head",  { font = "Roboto", size = 18, weight = 600, extended = true })
surface.CreateFont("GRM_Edu_Body",  { font = "Roboto", size = 16, weight = 500, extended = true })
surface.CreateFont("GRM_Edu_Small", { font = "Roboto", size = 13, weight = 500, extended = true })

--[[ Задача 10: размеры окон считаются от разрешения экрана, но ScrW/ScrH
     существуют только в живом клиенте — в тестовых стендах их нет. Хелпер
     отдаёт запасное значение, чтобы раскладка была проверяема офлайн. ]]
local function fitW(frac, minW, maxW)
    local sw = isfunction(ScrW) and ScrW() or 1920
    return math.min(maxW, math.max(minW, math.floor(sw * frac)))
end

local function fitH(frac, minH, maxH)
    local sh = isfunction(ScrH) and ScrH() or 1080
    return math.min(maxH, math.max(minH, math.floor(sh * frac)))
end

local function act(action, args)
    net.Start("GRM_Edu_Act")
        net.WriteString(action)
        net.WriteTable(args or {})
    net.SendToServer()
end
EDU.Act = act

local function dateOf(ts)
    ts = tonumber(ts) or 0
    if ts <= 0 then return "—" end
    return os.date("%d.%m.%Y", ts)
end

local function levelName(id)
    for _, l in ipairs(snap.levels or {}) do if l.id == id then return l.name end end
    return "—"
end

local function formName(id)
    for _, f in ipairs(snap.forms or {}) do if f.id == id then return f.name end end
    return "—"
end

-----------------------------------------------------------------------
-- Мелкие элементы
-----------------------------------------------------------------------
local function label(parent, text, font, col, x, y, w, h)
    local l = vgui.Create("DLabel", parent)
    l:SetText(text or "")
    l:SetFont(font or "GRM_Edu_Body")
    l:SetTextColor(col or UI.text)
    l:SetPos(x or 0, y or 0)
    l:SetSize(w or 200, h or 20)
    return l
end

local function button(parent, text, col, w, h)
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b:SetSize(w or 120, h or 30)
    b.Paint = function(self, bw, bh)
        local c = self:IsHovered() and Color(col.r, col.g, col.b, 255) or Color(col.r, col.g, col.b, 190)
        draw.RoundedBox(4, 0, 0, bw, bh, c)
        draw.SimpleText(text, "GRM_Edu_Body", bw / 2, bh / 2, Color(12, 18, 28),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    return b
end

local function entry(parent, placeholder, numeric, w, h)
    local e = vgui.Create("DTextEntry", parent)
    e:SetSize(w or 200, h or 28)
    e:SetFont("GRM_Edu_Body")
    e:SetPlaceholderText(placeholder or "")
    if numeric then e:SetNumeric(true) end
    e.Paint = function(self, ew, eh)
        draw.RoundedBox(4, 0, 0, ew, eh, Color(12, 20, 32, 245))
        surface.SetDrawColor(UI.line)
        surface.DrawOutlinedRect(0, 0, ew, eh, 1)
        self:DrawTextEntryText(UI.text, UI.cyan, UI.muted)
    end
    return e
end

local function combo(parent, placeholder, w, h)
    local c = vgui.Create("DComboBox", parent)
    c:SetSize(w or 200, h or 28)
    c:SetFont("GRM_Edu_Body")
    c:SetValue(placeholder or "")
    c:SetTextColor(UI.text)
    c.Paint = function(_, cw, ch)
        draw.RoundedBox(4, 0, 0, cw, ch, Color(12, 20, 32, 245))
        surface.SetDrawColor(UI.line)
        surface.DrawOutlinedRect(0, 0, cw, ch, 1)
    end
    return c
end

local function scroll(parent)
    local s = vgui.Create("DScrollPanel", parent)
    local bar = s:GetVBar()
    bar:SetWide(8)
    bar.Paint = function(_, w, h) draw.RoundedBox(4, 0, 0, w, h, Color(10, 18, 28, 200)) end
    bar.btnUp.Paint, bar.btnDown.Paint = function() end, function() end
    bar.btnGrip.Paint = function(_, w, h) draw.RoundedBox(4, 0, 0, w, h, UI.line) end
    return s
end

--- Карточка. Ширину НЕ фиксируем: раскладка идёт от фактической ширины
-- родителя в PerformLayout, поэтому содержимое не уезжает за правый край.
local function card(parent, h)
    local isScroll = istable(parent) and isfunction(parent.AddItem)
    local p = vgui.Create("DPanel", (not isScroll) and parent or nil)
    p:SetTall(h or 64)
    p:Dock(TOP) p:DockMargin(0, 0, 0, 6)
    p.Paint = function(_, w, ph)
        draw.RoundedBox(6, 0, 0, w, ph, UI.panel2)
        surface.SetDrawColor(UI.line)
        surface.DrawOutlinedRect(0, 0, w, ph, 1)
    end
    return p
end

local function empty(parent, text)
    local p = card(parent, 44)
    p.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, Color(14, 24, 38, 200)) end
    label(p, text, "GRM_Edu_Body", UI.muted, 14, 12, 700, 20)
    return p
end

--- Выбор персонажа с поиском: онлайн и офлайн (паспорта, составы фракций).
local function charPicker(parent, placeholder, w)
    local p = vgui.Create("DPanel", parent)
    p:SetSize(w or 300, 56)
    p.Paint = function() end
    p._key = ""

    local find = vgui.Create("DTextEntry", p)
    find:SetPos(0, 0) find:SetSize(w or 300, 22)
    find:SetFont("GRM_Edu_Small")
    find:SetPlaceholderText("Поиск: имя, фракция или ключ...")
    find.Paint = function(self, ew, eh)
        draw.RoundedBox(4, 0, 0, ew, eh, Color(10, 16, 26, 240))
        surface.SetDrawColor(UI.line)
        surface.DrawOutlinedRect(0, 0, ew, eh, 1)
        self:DrawTextEntryText(UI.text, UI.cyan, UI.muted)
    end

    local list = vgui.Create("DComboBox", p)
    list:SetPos(0, 26) list:SetSize(w or 300, 28)
    list:SetFont("GRM_Edu_Body")
    list:SetValue(placeholder or "Выберите выпускника...")
    list:SetTextColor(UI.text)
    list.Paint = function(_, cw, ch)
        draw.RoundedBox(4, 0, 0, cw, ch, Color(12, 20, 32, 245))
        surface.SetDrawColor(UI.line)
        surface.DrawOutlinedRect(0, 0, cw, ch, 1)
    end

    local function fill(filter)
        filter = string.lower(string.Trim(filter or ""))
        list:Clear()
        list:SetValue(placeholder or "Выберите выпускника...")
        local shown = 0
        for _, ch in ipairs(snap.characters or {}) do
            local name = tostring(ch.name or ch.key or "")
            local fac  = tostring(ch.faction or "")
            local hay  = string.lower(name .. " " .. fac .. " " .. tostring(ch.key or ""))
            if filter == "" or string.find(hay, filter, 1, true) then
                local tail = fac ~= "" and ("  [" .. fac .. "]") or ""
                list:AddChoice((ch.online and "• " or "  ") .. name .. tail, ch.key)
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
    p.Reload = function(self) fill(find:GetValue()) end
    p.PerformLayout = function(_, pw)
        find:SetSize(pw, 22)
        list:SetSize(pw, 28)
    end
    return p
end
EDU.CharPicker = charPicker

-----------------------------------------------------------------------
-- Панель рабочего места (используется и во фракциях, и в компьютере)
-----------------------------------------------------------------------
--- Строит содержимое рабочего места внутри переданной панели.
-- Возвращает функцию перерисовки: её зовут при получении новых данных.
function EDU.BuildWorkspace(parent)
    if not IsValid(parent) then return function() end end

    local sheet = vgui.Create("DPropertySheet", parent)
    sheet:Dock(FILL)
    sheet:DockMargin(8, 8, 8, 8)
    sheet:SetFadeTime(0)
    sheet.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, Color(0, 0, 0, 0)) end

    local pIssue = vgui.Create("DPanel", sheet) pIssue.Paint = function() end
    local pReg   = vgui.Create("DPanel", sheet) pReg.Paint = function() end
    local pCheck = vgui.Create("DPanel", sheet) pCheck.Paint = function() end
    sheet:AddSheet("Выписать диплом", pIssue, "icon16/page_white_edit.png")
    sheet:AddSheet("Реестр учреждения", pReg, "icon16/book.png")
    sheet:AddSheet("Проверка", pCheck, "icon16/magnifier.png")

    -- ============================ ВЫПИСКА ============================
    local scIssue = scroll(pIssue) scIssue:Dock(FILL)

    local function buildIssue()
        scIssue:Clear()

        if not (snap.canIssue or snap.isSuper) then
            scIssue:AddItem(empty(scIssue,
                "Вашей организации не выдан доступ на выдачу дипломов. Доступ включает суперадмин."))
            return
        end

        local head = card(scIssue, 58)
        label(head, "БЛАНК ГОСУДАРСТВЕННОГО ДИПЛОМА", "GRM_Edu_Head", UI.gold, 14, 10, 420, 22)
        local sub = label(head, ("Учреждение: %s"):format(
            tostring(snap.institution ~= "" and snap.institution or snap.faction or "—")),
            "GRM_Edu_Small", UI.muted, 14, 34, 500, 16)
        head.PerformLayout = function(_, w) sub:SetSize(math.max(200, w - 28), 16) end
        scIssue:AddItem(head)

        -- Форма. Раскладка в PerformLayout: две колонки от фактической ширины,
        -- высота карточки считается по факту (иначе нижний ряд с кнопкой
        -- «ВЫДАТЬ ДИПЛОМ» уезжал за край карточки и обрезался VGUI).
        local f = card(scIssue, 360)

        local lInst = label(f, "Учреждение образования", "GRM_Edu_Small", UI.muted, 14, 12, 260, 14)
        local inst  = entry(f, "Название учреждения...", false, 300, 28)
        inst:SetParent(f)
        inst:SetValue(tostring(snap.institution ~= "" and snap.institution or (snap.faction or "")))

        local lGrad = label(f, "Выпускник (в том числе офлайн)", "GRM_Edu_Small", UI.muted, 14, 12, 300, 14)
        local grad  = charPicker(f, "Выберите выпускника...", 300)
        grad:SetParent(f)

        local lSpec = label(f, "Специальность", "GRM_Edu_Small", UI.muted, 14, 12, 260, 14)
        local spec  = entry(f, "Например: юриспруденция", false, 300, 28)
        spec:SetParent(f)

        local lQual = label(f, "Квалификация", "GRM_Edu_Small", UI.muted, 14, 12, 260, 14)
        local qual  = entry(f, "Например: юрист", false, 300, 28)
        qual:SetParent(f)

        local lLvl = label(f, "Уровень образования", "GRM_Edu_Small", UI.muted, 14, 12, 260, 14)
        local lvl  = combo(f, "Уровень...", 300, 28)
        lvl:SetParent(f)
        for _, l in ipairs(snap.levels or {}) do lvl:AddChoice(l.name, l.id) end

        local lFrm = label(f, "Форма обучения", "GRM_Edu_Small", UI.muted, 14, 12, 260, 14)
        local frm  = combo(f, "Форма...", 300, 28)
        frm:SetParent(f)
        for _, l in ipairs(snap.forms or {}) do frm:AddChoice(l.name, l.id) end

        local lGrade = label(f, "Оценка / отличие", "GRM_Edu_Small", UI.muted, 14, 12, 260, 14)
        local grade  = entry(f, "отлично / с отличием", false, 300, 28)
        grade:SetParent(f)

        local lSign = label(f, "Подпись (должностное лицо)", "GRM_Edu_Small", UI.muted, 14, 12, 260, 14)
        local sign  = entry(f, "Оставьте пустым — подставится ваш ник", false, 300, 28)
        sign:SetParent(f)

        local paidChk = vgui.Create("DCheckBoxLabel", f)
        paidChk:SetSize(240, 20)
        paidChk:SetText("Обучение было платным")
        paidChk:SetFont("GRM_Edu_Small")
        paidChk:SetTextColor(UI.muted)

        local lInv = label(f, "Счёт об оплате (№, необязательно)", "GRM_Edu_Small", UI.muted, 14, 12, 300, 14)
        local invID = entry(f, "№ счёта", true, 140, 28)
        invID:SetParent(f)

        local bIssue = button(f, "ВЫДАТЬ ДИПЛОМ", UI.green, 200, 32)
        bIssue:SetParent(f)

        local hint = label(f, "Счёт должен быть оплачен, иначе бланк не выдаётся. Оплата — в банкомате.",
            "GRM_Edu_Small", UI.muted, 14, 12, 460, 16)

        -- Вся раскладка — от фактической ширины карточки (правый край не режется)
        f.PerformLayout = function(self, w)
            local pad, gap = 14, 12
            local colW = math.max(160, math.floor((w - pad * 2 - gap) / 2))
            local xL, xR = pad, pad + colW + gap
            local y = 12

            local function row(lLeft, cLeft, lRight, cRight, hCtl)
                lLeft:SetPos(xL, y) lLeft:SetSize(colW, 14)
                if lRight then lRight:SetPos(xR, y) lRight:SetSize(colW, 14) end
                cLeft:SetPos(xL, y + 16) cLeft:SetSize(colW, hCtl or 28)
                if cRight then cRight:SetPos(xR, y + 16) cRight:SetSize(colW, hCtl or 28) end
                y = y + 16 + (hCtl or 28) + 10
            end

            -- выпускник — панель на 56px, поэтому строка выше
            lInst:SetPos(xL, y) lInst:SetSize(colW, 14)
            lGrad:SetPos(xR, y) lGrad:SetSize(colW, 14)
            inst:SetPos(xL, y + 16) inst:SetSize(colW, 28)
            grad:SetPos(xR, y + 16) grad:SetSize(colW, 56)
            y = y + 16 + 56 + 10

            row(lSpec, spec, lQual, qual)
            row(lLvl, lvl, lFrm, frm)
            row(lGrade, grade, lSign, sign)

            paidChk:SetPos(xL, y + 4) paidChk:SetSize(colW, 20)
            lInv:SetPos(xR, y) lInv:SetSize(colW, 14)
            invID:SetPos(xR, y + 16) invID:SetSize(math.min(160, colW), 28)
            y = y + 16 + 28 + 10

            bIssue:SetPos(xL, y) bIssue:SetSize(math.min(220, colW), 32)
            hint:SetPos(xR, y + 8) hint:SetSize(colW, 16)

            -- Высота — по фактическому содержимому. Без этого нижний ряд
            -- (кнопка выдачи) оказывался ниже границы карточки и не рисовался.
            local need = y + 32 + 14
            if math.abs((self:GetTall() or 0) - need) > 1 then self:SetTall(need) end
        end

        bIssue.DoClick = function()
            local gkey = grad:GetKey()
            if gkey == "" then
                notification.AddLegacy("Выберите выпускника", NOTIFY_ERROR, 3)
                surface.PlaySound("buttons/button10.wav")
                return
            end
            if string.Trim(spec:GetValue() or "") == "" then
                notification.AddLegacy("Укажите специальность", NOTIFY_ERROR, 3)
                return
            end
            local _, lid = lvl:GetSelected()
            local _, fid = frm:GetSelected()
            act("issue", {
                graduate = gkey,
                institution = inst:GetValue(),
                specialty = spec:GetValue(),
                qualification = qual:GetValue(),
                level = lid or "course",
                form = fid or "full",
                grade = grade:GetValue(),
                signedBy = sign:GetValue(),
                paid = paidChk:GetChecked(),
                invoiceID = tonumber(invID:GetValue()) or 0,
            })
            spec:SetValue("") qual:SetValue("") grade:SetValue("") invID:SetValue("")
        end

        scIssue:AddItem(f)
    end

    -- ============================ РЕЕСТР ============================
    local topReg = vgui.Create("DPanel", pReg)
    topReg:Dock(TOP) topReg:SetTall(38) topReg.Paint = function() end
    local search = entry(topReg, "Поиск: номер, ФИО, специальность...", false, 320, 28)
    search:SetParent(topReg) search:SetPos(0, 4)
    local scReg = scroll(pReg) scReg:Dock(FILL)

    local function buildReg()
        scReg:Clear()
        local q = string.lower(string.Trim(search:GetValue() or ""))
        local stat = card(scReg, 40)
        label(stat, ("Всего: %d    Действительных: %d    Аннулированных: %d")
            :format(snap.stats and snap.stats.total or 0,
                    snap.stats and snap.stats.valid or 0,
                    snap.stats and snap.stats.revoked or 0),
            "GRM_Edu_Body", UI.cyan, 14, 10, 600, 20)
        scReg:AddItem(stat)

        local shown = 0
        for _, d in ipairs(snap.diplomas or {}) do
            local hay = string.lower(table.concat({
                d.number or "", d.graduateName or "", d.specialty or "",
                d.institution or "", d.qualification or "" }, " "))
            if q == "" or string.find(hay, q, 1, true) then
                shown = shown + 1
                local c = card(scReg, 92)
                local col = d.revoked and UI.red or UI.text
                local lNum  = label(c, tostring(d.number or ""), "GRM_Edu_Head", col, 14, 8, 240, 20)
                local lName = label(c, tostring(d.graduateName or "?"), "GRM_Edu_Body", UI.cyan, 14, 30, 320, 18)
                local lSpec = label(c, ("%s | %s | %s"):format(
                    tostring(d.specialty or "—"), levelName(d.level), formName(d.form)),
                    "GRM_Edu_Small", UI.muted, 14, 50, 420, 16)
                local lMore = label(c, ("Выдал: %s    %s    %s"):format(
                    tostring(d.issuerName or "—"), dateOf(d.issued),
                    d.paid and "платно" or "бесплатно"), "GRM_Edu_Small", UI.muted, 14, 68, 420, 16)
                local lStat = label(c, d.revoked and "АННУЛИРОВАН" or "ДЕЙСТВИТЕЛЕН",
                    "GRM_Edu_Small", d.revoked and UI.red or UI.green, 0, 10, 150, 16)

                local bRev
                if (snap.isLeader or snap.isSuper) and not d.revoked then
                    bRev = button(c, "Аннулировать", UI.red, 150, 26)
                    bRev:SetParent(c)
                    bRev.DoClick = function()
                        Derma_StringRequest("Аннулирование диплома",
                            ("Причина аннулирования %s:"):format(tostring(d.number)), "",
                            function(txt) act("revoke", { number = d.number, reason = txt }) end)
                    end
                end

                c.PerformLayout = function(_, w)
                    local right = math.max(160, w - 170)
                    lNum:SetSize(math.max(120, right - 20), 20)
                    lName:SetSize(math.max(120, right - 20), 18)
                    lSpec:SetSize(math.max(120, right - 20), 16)
                    lMore:SetSize(math.max(120, right - 20), 16)
                    lStat:SetPos(w - 158, 10) lStat:SetSize(150, 16)
                    if IsValid(bRev) then bRev:SetPos(w - 164, 52) bRev:SetSize(150, 26) end
                end
                scReg:AddItem(c)
            end
        end
        if shown == 0 then
            scReg:AddItem(empty(scReg, q == "" and "Реестр пуст: дипломы ещё не выдавались."
                or "По запросу ничего не найдено."))
        end
    end
    search.OnChange = function() timer.Simple(0, buildReg) end

    -- ============================ ПРОВЕРКА ============================
    local scChk = scroll(pCheck) scChk:Dock(FILL)
    local function buildCheck()
        scChk:Clear()
        local c = card(scChk, 96)
        label(c, "ПРОВЕРКА ДИПЛОМА ПО ЕДИНОМУ РЕЕСТРУ", "GRM_Edu_Small", UI.muted, 14, 10, 420, 16)
        local num = entry(c, "Номер бланка, например ГД-2026-000123", false, 340, 30)
        num:SetParent(c) num:SetPos(14, 34)
        local b = button(c, "Проверить", UI.cyan, 150, 30)
        b:SetParent(c)
        local hint = label(c, "Результат придёт уведомлением и в чат.", "GRM_Edu_Small", UI.muted, 14, 70, 420, 16)
        b.DoClick = function()
            local v = string.Trim(num:GetValue() or "")
            if v == "" then return end
            act("check", { number = v })
        end
        c.PerformLayout = function(_, w)
            num:SetSize(math.max(160, w - 190), 30)
            b:SetPos(w - 164, 34)
            hint:SetSize(math.max(160, w - 28), 16)
        end
        scChk:AddItem(c)
    end

    local function rebuild()
        if not IsValid(parent) then return end
        buildIssue() buildReg() buildCheck()
    end
    rebuild()
    return rebuild
end

-----------------------------------------------------------------------
-- Вкладка в меню фракций
-----------------------------------------------------------------------
local factionRebuild
hook.Add("GRM_FactionsAdmin_BuildTabs", "GRM_Edu_FactionTab", function(tabs)
    if not IsValid(tabs) then return end
    local lp = LocalPlayer()
    if not IsValid(lp) then return end

    -- Вкладку видит только тот, кому есть что делать: сотрудник учреждения
    -- с доступом или суперадмин. Право проверяет сервер, здесь — только
    -- предварительный показ по последнему снимку.
    local panel = vgui.Create("DPanel")
    panel:SetPaintBackground(false)
    tabs:AddSheet("Учреждение образования", panel, "icon16/user_suit.png")

    local rebuild = EDU.BuildWorkspace(panel)
    factionRebuild = function()
        if IsValid(panel) then rebuild() end
    end

    net.Start("GRM_Edu_Request") net.SendToServer()
    timer.Simple(0.6, function() if IsValid(panel) then rebuild() end end)
end)

-----------------------------------------------------------------------
-- Приём данных
-----------------------------------------------------------------------
local function applySnap(t)
    table.Empty(snap)
    for k, v in pairs(t or {}) do snap[k] = v end
end

net.Receive("GRM_Edu_Data", function()
    applySnap(net.ReadTable())
    if isfunction(factionRebuild) then pcall(factionRebuild) end
    if isfunction(EDU._computerRebuild) then pcall(EDU._computerRebuild) end
end)

net.Receive("GRM_Edu_Result", function()
    local ok = net.ReadBool()
    local msg = net.ReadString()
    if msg == "" then return end
    notification.AddLegacy(msg, ok and NOTIFY_GENERIC or NOTIFY_ERROR, 6)
    surface.PlaySound(ok and "buttons/button14.wav" or "buttons/button10.wav")
end)

-----------------------------------------------------------------------
-- Отдельное окно рабочего места (компьютер деканата)
-----------------------------------------------------------------------
function EDU.OpenFrame()
    -- Задача 10: на 1280x720 и меньше окно 940x660 выходило за экран.
    local W, H = fitW(0.72, 720, 940), fitH(0.85, 480, 660)
    local frame = vgui.Create("DFrame")
    frame:SetSize(W, H)
    frame:Center()
    frame:SetTitle("")
    frame:MakePopup()
    frame:ShowCloseButton(false)
    frame.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, UI.bg)
        draw.RoundedBoxEx(8, 0, 0, w, 44, UI.panel, true, true, false, false)
        draw.SimpleText("УЧРЕЖДЕНИЕ ОБРАЗОВАНИЯ — РАБОЧЕЕ МЕСТО", "GRM_Edu_Title", 16, 22,
            UI.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(tostring(snap.institution ~= "" and snap.institution or (snap.faction or "")),
            "GRM_Edu_Small", w - 52, 22, UI.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    local close = vgui.Create("DButton", frame)
    close:SetSize(30, 26) close:SetPos(W - 40, 9) close:SetText("")
    close.Paint = function(self, w, h)
        draw.RoundedBox(4, 0, 0, w, h, self:IsHovered() and UI.red or Color(50, 62, 84))
        draw.SimpleText("X", "GRM_Edu_Body", w / 2, h / 2, UI.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    close.DoClick = function() frame:Close() end

    local body = vgui.Create("DPanel", frame)
    body:SetPos(0, 44) body:SetSize(W, H - 44)
    body.Paint = function() end

    local rebuild = EDU.BuildWorkspace(body)
    EDU._computerRebuild = function() if IsValid(frame) then rebuild() end end
    frame.OnRemove = function() EDU._computerRebuild = nil end
    return frame
end

net.Receive("GRM_Edu_Open", function()
    applySnap(net.ReadTable())
    EDU.OpenFrame()
end)

-----------------------------------------------------------------------
-- «МОИ ДИПЛОМЫ» — личный просмотр для любого игрока
--
-- Диплом — такой же документ персонажа, как паспорт, поэтому смотрится
-- он так же: кнопка в C-меню, без чата и без банкомата. Прав не нужно
-- никаких: игрок видит только свои бланки.
-----------------------------------------------------------------------

--- Рисует один бланк дипломa в стиле документа (не строчку списка).
local function diplomaBlank(parent, rec)
    local revoked = rec.revoked == true
    local p = card(parent, 390)
    p.Paint = function(_,w,h)
        local paper=revoked and Color(242,224,218) or Color(247,241,220)
        local ink=Color(48,43,35)
        local gold=revoked and Color(145,65,60) or Color(156,119,42)
        draw.RoundedBox(8,0,0,w,h,Color(20,23,30,245))
        draw.RoundedBox(6,5,5,w-10,h-10,paper)
        surface.SetDrawColor(gold); surface.DrawOutlinedRect(9,9,w-18,h-18,3); surface.DrawOutlinedRect(15,15,w-30,h-30,1)
        -- Угловой орнамент и разделители.
        surface.DrawLine(20,28,72,28); surface.DrawLine(28,20,28,50)
        surface.DrawLine(w-72,28,w-20,28); surface.DrawLine(w-28,20,w-28,50)
        draw.SimpleText("ГОСУДАРСТВЕННЫЙ ОБРАЗОВАТЕЛЬНЫЙ ДОКУМЕНТ","GRM_Edu_Small",w/2,24,gold,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
        draw.SimpleText("Д И П Л О М","GRM_Edu_Title",w/2,52,ink,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
        draw.SimpleText(tostring(rec.institution or "Учреждение образования"),"GRM_Edu_Small",w/2,76,Color(83,72,52),TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
        surface.SetDrawColor(gold); surface.DrawLine(40,92,w-40,92)
        -- Печать и декоративный водяной знак.
        draw.SimpleText("D","GRM_Edu_Title",w-72,h-55,Color(gold.r,gold.g,gold.b,35),TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
        surface.SetDrawColor(Color(gold.r,gold.g,gold.b,150)); surface.DrawCircle(w-72,h-55,31,gold.r,gold.g,gold.b,150); surface.DrawCircle(w-72,h-55,25,gold.r,gold.g,gold.b,120)
        draw.SimpleText("ПЕЧАТЬ","GRM_Edu_Small",w-72,h-55,gold,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
        if revoked then
            draw.SimpleText("АННУЛИРОВАН","GRM_Edu_Title",w/2,h/2,Color(175,40,40,80),TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
            surface.SetDrawColor(Color(180,45,45,100)); surface.DrawLine(35,h-36,w-35,36); surface.DrawLine(35,36,w-35,h-36)
        end
    end

    -- Поля бланка: слева подпись, справа значение
    local rows = {
        { "Бланк №",       rec.number or "—" },
        { "Учреждение",    rec.institution or "—" },
        { "Выпускник",     rec.graduateName or "—" },
        { "Специальность", rec.specialty or "—" },
        { "Квалификация",  (rec.qualification ~= "" and rec.qualification) or "—" },
        { "Уровень",       rec.levelName or "—" },
        { "Форма обучения",rec.formName or "—" },
        { "Оценка",        (rec.grade ~= "" and rec.grade) or "—" },
        { "Обучение",      rec.paid and "платное" or "бесплатное" },
        { "Дата выдачи",   dateOf(rec.issued) },
        { "Подпись",       (rec.signedBy ~= "" and rec.signedBy) or rec.issuerName or "—" },
    }
    if rec.note and rec.note ~= "" then rows[#rows + 1] = { "Примечание", rec.note } end
    if revoked and rec.revokeReason and rec.revokeReason ~= "" then
        rows[#rows + 1] = { "Причина аннулирования", rec.revokeReason }
    end

    --[[ Задача 10: длинные значения (специальность, примечание, причина
         аннулирования, название учреждения) не помещались в одну строку и
         обрезались по правому краю бланка. Теперь значение — переносимая
         метка: SetWrap + SetAutoStretchVertical, а высота строки и всего
         бланка считается по фактической высоте текста. Ключ поля прижат к
         верху своей строки, чтобы подпись не «уезжала» от многострочного
         значения. ]]
    local keys, vals = {}, {}
    for i, r in ipairs(rows) do
        keys[i] = label(p, r[1], "GRM_Edu_Small", revoked and Color(130,65,60) or Color(122,93,38), 0, 0, 10, 18)
        keys[i]:SetContentAlignment(7) -- левый верх

        local v = label(p, tostring(r[2]), "GRM_Edu_Body",
            (i == 1) and (revoked and Color(165,45,45) or Color(120,82,20)) or Color(48,43,35), 0, 0, 10, 18)
        v:SetWrap(true)
        v:SetAutoStretchVertical(true)
        v:SetContentAlignment(7)
        vals[i] = v
    end

    -- Раскладка от фактической ширины: правый край не режется
    p.PerformLayout = function(self, w)
        local pad, keyW, gap = 20, 150, 6
        local valW = math.max(80, w - pad * 2 - keyW)
        local y = 106
        for i = 1, #rows do
            local v = vals[i]
            v:SetPos(pad + keyW, y)
            v:SetWide(valW)
            -- пересчёт высоты под перенос: без InvalidateLayout метка
            -- сохраняет старую однострочную высоту
            v:InvalidateLayout(true)
            v:SizeToContentsY()
            local rowH = math.max(18, v:GetTall() or 18)
            keys[i]:SetPos(pad, y) keys[i]:SetSize(keyW - gap, rowH)
            y = y + rowH + 4
        end
        local need = y + 52
        if math.abs((self:GetTall() or 0) - need) > 1 then
            self:SetTall(need)
            --[[ Карточка приклеена через Dock(TOP): смена высоты изнутри
                 PerformLayout не перестраивает docking сама по себе, поэтому
                 бланк оставался ровно 250 px, а лишние строки уходили под
                 нижний край. Просим родителя (и DScrollPanel-канвас)
                 пересчитать раскладку. ]]
            local par = self:GetParent()
            if IsValid(par) then
                par:InvalidateLayout()
                local grand = par:GetParent()
                if IsValid(grand) then grand:InvalidateLayout() end
            end
        end
    end
    return p
end

--- Окно «Мои дипломы».
function EDU.OpenMine(list)
    list = istable(list) and list or {}

    -- Задача 10: бланк с переносом строк стал выше и требует ширины,
    -- иначе значения дробятся на много строк. Окно не должно вылезать
    -- за пределы экрана на маленьких разрешениях.
    local W, H = fitW(0.5, 560, 760), fitH(0.8, 420, 720)
    local frame = vgui.Create("DFrame")
    frame:SetSize(W, H)
    frame:Center()
    frame:SetTitle("")
    frame:MakePopup()
    frame:ShowCloseButton(false)
    frame.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, UI.bg)
        draw.RoundedBoxEx(8, 0, 0, w, 44, UI.panel, true, true, false, false)
        draw.SimpleText("МОИ ДИПЛОМЫ", "GRM_Edu_Title", 16, 22, UI.gold,
            TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(("документов: %d"):format(#list), "GRM_Edu_Small", w - 52, 22,
            UI.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    local close = vgui.Create("DButton", frame)
    close:SetSize(30, 26) close:SetPos(W - 40, 9) close:SetText("")
    close.Paint = function(self, w, h)
        draw.RoundedBox(4, 0, 0, w, h, self:IsHovered() and UI.red or Color(50, 62, 84))
        draw.SimpleText("X", "GRM_Edu_Body", w / 2, h / 2, UI.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    close.DoClick = function() frame:Close() end

    local sc = scroll(frame)
    sc:SetPos(12, 54) sc:SetSize(W - 24, H - 66)

    if #list == 0 then
        empty(sc, "У вашего персонажа нет дипломов. Их выдаёт учреждение образования.")
    else
        for _, rec in ipairs(list) do sc:AddItem(diplomaBlank(sc, rec)) end
    end
    return frame
end

net.Receive("GRM_Edu_MyData", function()
    local list = net.ReadTable()
    -- Режим «выбрать бланк для предъявления» — когда дипломов несколько
    if EDU._pickForShow then
        EDU._pickForShow = nil
        EDU.PickForShow(list)
        return
    end
    EDU.OpenMine(list)
end)

--- Окно предъявления: показывает, ЧЕЙ диплом и кто предъявил.
function EDU.OpenShown(rec, senderName)
    if not istable(rec) then return end

    -- Задача 10: жёсткие 420 px обрезали бланк — в нём 11–13 строк, а с
    -- переносом длинных значений и того больше. Размер считаем от экрана.
    local W, H = fitW(0.5, 560, 760), fitH(0.72, 400, 680)
    local frame = vgui.Create("DFrame")
    frame:SetSize(W, H)
    frame:Center()
    frame:SetTitle("")
    frame:MakePopup()
    frame:ShowCloseButton(false)
    frame.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, UI.bg)
        draw.RoundedBoxEx(8, 0, 0, w, 44, UI.panel, true, true, false, false)
        draw.SimpleText("ВАМ ПРЕДЪЯВИЛИ ДИПЛОМ", "GRM_Edu_Title", 16, 22, UI.gold,
            TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(tostring(senderName or ""), "GRM_Edu_Small", w - 52, 22,
            UI.muted, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    local close = vgui.Create("DButton", frame)
    close:SetSize(30, 26) close:SetPos(W - 40, 9) close:SetText("")
    close.Paint = function(self, w, h)
        draw.RoundedBox(4, 0, 0, w, h, self:IsHovered() and UI.red or Color(50, 62, 84))
        draw.SimpleText("X", "GRM_Edu_Body", w / 2, h / 2, UI.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    close.DoClick = function() frame:Close() end

    local sc = scroll(frame)
    sc:SetPos(12, 54) sc:SetSize(W - 24, H - 66)
    sc:AddItem(diplomaBlank(sc, rec))
    return frame
end

net.Receive("GRM_Edu_ShowView", function()
    local rec = net.ReadTable()
    local sender = net.ReadString()
    EDU.OpenShown(rec, sender)
end)

--- Предъявить диплом игроку перед собой.
function EDU.ShowTo(number)
    net.Start("GRM_Edu_ShowAsk")
        net.WriteString(tostring(number or ""))
    net.SendToServer()
end

--- Если дипломов несколько — сначала спросить, какой предъявлять.
function EDU.PickForShow(list)
    list = istable(list) and list or {}
    if #list == 0 then
        if GRM.Notify then GRM.Notify("У вас нет дипломов.", 255, 140, 110) end
        return
    end
    if #list == 1 then EDU.ShowTo(list[1].number) return end

    local menu = DermaMenu()
    for _, d in ipairs(list) do
        local title = ("%s — %s%s"):format(d.number, d.specialty ~= "" and d.specialty or "—",
            d.revoked and " (аннулирован)" or "")
        menu:AddOption(title, function() EDU.ShowTo(d.number) end)
    end
    menu:Open()
end

--- Точка входа из C-меню: спросить список и выбрать бланк.
function EDU.AskShow()
    EDU._pickForShow = true
    net.Start("GRM_Edu_MyAsk")
    net.SendToServer()
end

--- Запрос своих дипломов (кнопка C-меню, консольная команда).
function EDU.AskMine()
    net.Start("GRM_Edu_MyAsk")
    net.SendToServer()
end

concommand.Add("grm_mydiplomas", function() EDU.AskMine() end)

end -- CLIENT
