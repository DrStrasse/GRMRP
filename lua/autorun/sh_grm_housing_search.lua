--[[--------------------------------------------------------------------
    GRM Housing Search v1.0.0 — обыск жилья и журнал входов. Фаза 3.

    ЗАЧЕМ. Владелец сказал «да» на вопрос «может ли полиция попасть в
    жильё: ордер, взлом, обыск». Фазы 1-2 научились ПУСКАТЬ по ордеру.
    Здесь появляется главное, ради чего ордер вообще нужен в РП:

        владелец УЗНАЁТ, что у него были, и может это оспорить.

    Без записи и уведомления ордер бессмысленен: полиция заходила бы
    молча, а игрок не понимал, откуда пропали вещи и кто открывал шкаф.

    ЧТО ДЕЛАЕТ МОДУЛЬ.

      1) ЖУРНАЛ ВХОДОВ. Каждый вход в жильё НЕ по своему ключу —
         строка в журнале: кто, когда, на каком основании, номер ордера,
         кто судья. Хранится в самом объекте недвижимости, поэтому виден
         и владельцу, и следствию, и переживает рестарт.

      2) УВЕДОМЛЕНИЕ ВЛАДЕЛЬЦУ. Онлайн — сразу; офлайн — при первом
         входе в игру («пока вас не было, в квартиру входили»).

      3) ВЗЛОМ — ОТДЕЛЬНАЯ СТРОКА. Вход по ордеру законен, взлом — нет.
         В журнале они выглядят по-разному, чтобы в суде было видно
         разницу.

      4) КОМАНДА /housing_log — владелец смотрит, кто у него был.

    ПОЧЕМУ ЖУРНАЛ В ОБЪЕКТЕ, А НЕ В ОТДЕЛЬНОМ ФАЙЛЕ. Записей мало
    (десятки на квартиру), они всегда нужны вместе с объектом и должны
    исчезать вместе с ним. Отдельный файл пришлось бы чистить от
    «сирот» после сноса квартир.

    Аудит (sh_05_grm_audit) при этом тоже пишется — он для админов и
    навсегда, а журнал в объекте для игроков и с лимитом.
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.HousingSearch = GRM.HousingSearch or {}
local SR = GRM.HousingSearch

SR.Version = "1.0.0"

--- Сколько строк журнала держим на объект. Больше не нужно: это не
--- бухгалтерия, а «кто был у меня дома за последнее время».
SR.MaxEntries = 40

--- Сколько живёт запись (14 суток). Старое в суде уже не поднимают.
SR.EntryLifetime = 14 * 86400

--[[ Не спамим владельцу на каждое открытие двери: полиция при обыске
     ходит туда-сюда. Одно уведомление на человека в этот промежуток. ]]
SR.NotifyCooldown = 120

SR.NET = { LOG = "GRM_HousingLog" }

--- Виды записей и как они выглядят игроку.
SR.Kinds = {
    warrant = { label = "ОРДЕР",  color = { 245, 198, 70 } },
    breach  = { label = "ВЗЛОМ",  color = { 235, 90, 80 } },
    admin   = { label = "АДМИН",  color = { 150, 180, 255 } },
    guest   = { label = "ГОСТЬ",  color = { 140, 210, 160 } },
}

-----------------------------------------------------------------------
-- СЕРВЕР
-----------------------------------------------------------------------
if SERVER then
    util.AddNetworkString(SR.NET.LOG)

    local function charKey(ply)
        if GRM.Identity and GRM.Identity.CharacterKey then
            return tostring(GRM.Identity.CharacterKey(ply) or "")
        end
        return IsValid(ply) and (ply:SteamID64() .. ":char1") or ""
    end

    local function rpName(ply)
        if not IsValid(ply) then return "неизвестно" end
        local n = ply:GetNWString("GRM_RPName", "")
        if n ~= "" then return n end
        return ply:Nick()
    end

    --[[ Данные ордера, по которому вошли. Нужны в журнале целиком:
         номер и судья — это то, чем владелец будет оспаривать обыск. ]]
    local function warrantInfo(rec, actorKey)
        local D = GRM.Doors
        if not (D and istable(D.Data) and istable(D.Data.warrants)) then return nil end
        local propID = tostring(rec and rec.id or "")

        -- Сначала ищем ордер именно на это помещение: он точнее.
        for _, w in pairs(D.Data.warrants) do
            if istable(w) and tostring(w.propertyId or "") == propID and propID ~= "" then
                if (not w.status or w.status == "active") then
                    return w
                end
            end
        end
        -- Затем ордер на владельца.
        local ownerKey = tostring(rec and rec.ownerKey or "")
        if ownerKey ~= "" and istable(D.Data.warrants[ownerKey]) then
            local w = D.Data.warrants[ownerKey]
            if not w.status or w.status == "active" then return w end
        end
        return nil
    end

    -----------------------------------------------------------------
    -- ЖУРНАЛ
    -----------------------------------------------------------------
    --- Чистка: обрезаем по сроку и по количеству, старое уходит первым.
    function SR.Trim(rec)
        if not (istable(rec) and istable(rec.entryLog)) then return end
        local now = os.time()
        local kept = {}
        for _, e in ipairs(rec.entryLog) do
            if istable(e) and (now - (tonumber(e.at) or 0)) <= SR.EntryLifetime then
                kept[#kept + 1] = e
            end
        end
        -- Оставляем последние MaxEntries.
        while #kept > SR.MaxEntries do table.remove(kept, 1) end
        rec.entryLog = kept
    end

    --[[ Записать вход. kind: warrant / breach / admin / guest.
         Возвращает саму запись — она же уходит в уведомление. ]]
    function SR.Log(rec, ply, kind, extra)
        if not istable(rec) then return nil end
        kind = SR.Kinds[tostring(kind or "")] and kind or "guest"
        extra = istable(extra) and extra or {}

        rec.entryLog = istable(rec.entryLog) and rec.entryLog or {}

        local entry = {
            at = os.time(),
            kind = kind,
            who = rpName(ply),
            whoKey = charKey(ply),
            faction = IsValid(ply) and ply:GetNWString("GRM_Faction", "") or "",
            what = tostring(extra.what or ""),
        }

        --[[ Данные ордера кладём В ЗАПИСЬ, а не ссылкой на ордер: ордер
             истечёт и удалится, а запись должна остаться доказательством. ]]
        local w = extra.warrant
        if istable(w) then
            entry.warrantNo = tostring(w.number or w.id or "")
            entry.warrantBy = tostring(w.byNick or "")
            entry.judge = tostring(w.approvedByName or "")
            entry.reason = tostring(w.reason or "")
        end

        rec.entryLog[#rec.entryLog + 1] = entry
        SR.Trim(rec)

        local P = GRM.Property
        if P and P.Save then P.Save("housing-entry-log") end
        return entry
    end

    -----------------------------------------------------------------
    -- УВЕДОМЛЕНИЕ ВЛАДЕЛЬЦУ
    -----------------------------------------------------------------
    local function entryText(rec, e)
        local when = os.date("%d.%m %H:%M", tonumber(e.at) or os.time())
        local place = tostring(rec.name or "ваше жильё")
        if e.kind == "warrant" then
            local no = e.warrantNo ~= "" and (" №" .. e.warrantNo) or ""
            return ("[Жильё] %s: обыск по ордеру%s. Вошёл: %s. Основание: %s."):format(
                place, no, e.who, e.reason ~= "" and e.reason or "не указано")
        elseif e.kind == "breach" then
            return ("[Жильё] %s: ВЗЛОМ. %s вскрыл дверь без ордера (%s)."):format(
                place, e.who, when)
        elseif e.kind == "admin" then
            return ("[Жильё] %s: заходила администрация (%s)."):format(place, when)
        end
        return ("[Жильё] %s: входил %s (%s)."):format(place, e.who, when)
    end
    SR.EntryText = entryText

    --[[ Хранилище офлайн-уведомлений. Владельца может не быть на
         сервере в момент обыска — иначе смысл теряется: пришёл в 4 утра,
         обыскал, игрок никогда не узнал. ]]
    SR.Pending = SR.Pending or {}     -- [characterKey] = { текст, ... }
    SR.PendingFile = "grm_housing_pending.json"

    local function jsonT(txt)
        local ok, t = pcall(util.JSONToTable, txt, false, true)
        return (ok and istable(t)) and t or nil
    end

    function SR.LoadPending()
        SR.Pending = {}
        if not file.Exists(SR.PendingFile, "DATA") then return end
        local t = jsonT(file.Read(SR.PendingFile, "DATA") or "")
        if istable(t) then SR.Pending = t end
    end

    function SR.SavePending()
        local ok, txt = pcall(util.TableToJSON, SR.Pending or {}, true)
        if ok and txt then file.Write(SR.PendingFile, txt) end
    end

    SR.LoadPending()

    --[[ Сообщить владельцу. Онлайн — сразу, офлайн — копим до входа.
         Кулдаун на человека: при обыске дверь открывают много раз. ]]
    function SR.NotifyOwner(rec, entry, actor)
        if not (istable(rec) and istable(entry)) then return false end
        local ownerKey = tostring(rec.ownerKey or "")
        if ownerKey == "" or tostring(rec.ownerType or "") ~= "character" then return false end
        -- Себе о себе не сообщаем.
        if ownerKey == tostring(entry.whoKey or "") then return false end

        local text = entryText(rec, entry)

        local target = GRM.Identity and GRM.Identity.ResolveCharacter
            and GRM.Identity.ResolveCharacter(ownerKey) or nil

        if IsValid(target) then
            -- Кулдаун считаем по паре «объект + вошедший».
            local ck = tostring(rec.id or "") .. "|" .. tostring(entry.whoKey or "")
            target._grmHousingTold = target._grmHousingTold or {}
            local last = tonumber(target._grmHousingTold[ck]) or 0
            if CurTime() - last < SR.NotifyCooldown then return false end
            target._grmHousingTold[ck] = CurTime()

            local col = SR.Kinds[entry.kind] and SR.Kinds[entry.kind].color or { 255, 255, 255 }
            if GRM.Notify then
                GRM.Notify(target, text, col[1], col[2], col[3])
            else
                target:PrintMessage(HUD_PRINTTALK, text)
            end
            return true
        end

        --[[ Офлайн: копим. Лимит на человека, чтобы недельное отсутствие
             не превратилось в стену текста при входе. ]]
        SR.Pending[ownerKey] = SR.Pending[ownerKey] or {}
        local list = SR.Pending[ownerKey]
        list[#list + 1] = { at = entry.at, text = text }
        while #list > 10 do table.remove(list, 1) end
        SR.SavePending()
        return true
    end

    --- Выдать накопленное, когда владелец вернулся.
    function SR.FlushPending(ply)
        if not IsValid(ply) then return 0 end
        local key = charKey(ply)
        local list = SR.Pending[key]
        if not (istable(list) and #list > 0) then return 0 end

        ply:PrintMessage(HUD_PRINTTALK, "[Жильё] Пока вас не было, в ваше жильё входили:")
        for _, row in ipairs(list) do
            ply:PrintMessage(HUD_PRINTTALK, "  " .. tostring(row.text or ""))
        end
        local n = #list
        SR.Pending[key] = nil
        SR.SavePending()
        return n
    end

    --[[ Ждём не PlayerInitialSpawn, а подтверждения персонажа: до этого
         игрок сидит в лимбе и ключ персонажа ещё не тот. Ровно та же
         причина, по которой экран точек входа ждёт этот хук. ]]
    hook.Add("GRM_CharacterConfirmed", "GRM_HousingSearch_Pending", function(ply)
        timer.Simple(3, function()
            if IsValid(ply) then SR.FlushPending(ply) end
        end)
    end)
    hook.Add("GRM_CharacterChanged", "GRM_HousingSearch_PendingSwap", function(ply)
        timer.Simple(1, function()
            if IsValid(ply) then SR.FlushPending(ply) end
        end)
    end)

    -----------------------------------------------------------------
    -- ЕДИНАЯ ТОЧКА: ЗАФИКСИРОВАТЬ ВХОД
    -----------------------------------------------------------------
    --[[ Один вход = одна запись. Дверь в GMod дёргается несколько раз
         за одно нажатие (полотна, дубли, партнёр), поэтому склеиваем
         повторы одного человека в один объект по времени. ]]
    SR.RecentWindow = 20

    function SR.Register(rec, ply, kind, extra)
        if not (istable(rec) and IsValid(ply)) then return nil end
        local HS = GRM.Housing
        if HS and HS.IsHousing and not HS.IsHousing(rec) then return nil end

        local ck = charKey(ply)
        rec._entrySeen = istable(rec._entrySeen) and rec._entrySeen or {}
        local seenKey = ck .. "|" .. tostring(kind)
        local last = tonumber(rec._entrySeen[seenKey]) or 0
        if os.time() - last < SR.RecentWindow then return nil end
        rec._entrySeen[seenKey] = os.time()

        local entry = SR.Log(rec, ply, kind, extra)
        if not entry then return nil end

        SR.NotifyOwner(rec, entry, ply)

        if GRM.Audit and GRM.Audit.Write then
            GRM.Audit.Write("housing", "entry." .. tostring(kind), ply,
                { propertyID = tostring(rec.id or "") },
                { warrantNo = entry.warrantNo or "", reason = entry.reason or "" })
        end
        hook.Run("GRM_HousingEntryLogged", rec, entry, ply)
        return entry
    end

    -----------------------------------------------------------------
    -- ИСТОЧНИКИ СОБЫТИЙ
    -----------------------------------------------------------------
    --[[ 1. Дверь открыли не своим ключом. Слушаем тот же хук, что решает
           доступ, но ТОЛЬКО читаем результат: возвращать отсюда ничего
           нельзя, иначе мы переопределим чужое решение. ]]
    hook.Add("GRM_DoorAccessOverride", "GRM_HousingSearch_Watch", function(ply, door)
        local P, HS = GRM.Property, GRM.Housing
        if not (P and P.GetByDoor and HS and HS.CanEnter) then return end
        if not IsValid(ply) then return end
        local rec = P.GetByDoor(door)
        if not (istable(rec) and HS.IsHousing(rec)) then return end

        local allowed, reason = HS.CanEnter(ply, rec)
        if not allowed then return end

        if reason == "warrant_property" or reason == "warrant_owner" then
            SR.Register(rec, ply, "warrant", { warrant = warrantInfo(rec, charKey(ply)),
                what = "вход в помещение" })
        elseif reason == "admin" then
            SR.Register(rec, ply, "admin", { what = "вход в помещение" })
        elseif reason == "key" then
            --[[ Гость с ключом — тоже событие: владелец должен видеть,
                 что его временным ключом пользовались. Но себе о себе
                 не пишем (NotifyOwner это отсекает). ]]
            if tostring(rec.ownerKey or "") ~= charKey(ply) then
                SR.Register(rec, ply, "guest", { what = "вход по ключу" })
            end
        end
        -- Ничего не возвращаем: решение принимает property/housing.
    end)

    --[[ 2. Взлом. Property уже ловит GRM_OnDoorLockpicked для сигнализации,
           но в журнал жилья это не попадало. Взлом — отдельный вид записи:
           в отличие от ордера, он незаконен. ]]
    local function onBreach(actor, door)
        local P, HS = GRM.Property, GRM.Housing
        if not (P and P.GetByDoor and IsValid(actor)) then return end
        local rec = P.GetByDoor(door)
        if not (istable(rec) and HS and HS.IsHousing(rec)) then return end
        SR.Register(rec, actor, "breach", { what = "вскрытие двери" })
    end
    hook.Add("GRM_OnDoorLockpicked", "GRM_HousingSearch_Breach", onBreach)
    hook.Add("GRM_DoorHacked", "GRM_HousingSearch_Hack", onBreach)

    --[[ 3. Обыск шкафа (фаза 2 уже бросает это событие). Смотреть в чужой
           шкаф — более серьёзное вторжение, чем просто войти, поэтому
           отдельная запись с пометкой. ]]
    hook.Add("GRM_HomeStorageSearched", "GRM_HousingSearch_Locker", function(ply, rec, ent, why)
        if not istable(rec) then return end
        SR.Register(rec, ply, "warrant", {
            warrant = warrantInfo(rec, charKey(ply)),
            what = "осмотр домашнего шкафа",
        })
    end)

    -----------------------------------------------------------------
    -- ПРОСМОТР ЖУРНАЛА
    -----------------------------------------------------------------
    --[[ Кто вправе смотреть журнал: владелец (это его дом) и тот, кто
         ведёт розыск (следствию нужна история). Посторонним нельзя —
         иначе журнал сам станет способом слежки за жильцом. ]]
    function SR.CanViewLog(ply, rec)
        if not (IsValid(ply) and istable(rec)) then return false end
        local P = GRM.Property
        if P and P.CanAdmin and P.CanAdmin(ply) then return true end
        if tostring(rec.ownerType or "") == "character"
            and tostring(rec.ownerKey or "") == charKey(ply) then return true end
        if GRM.Access and GRM.Access.Can and GRM.Access.Can(ply, "wanted.civil.edit") == true then
            return true
        end
        return false
    end

    --- Журнал объекта в виде, пригодном для отправки клиенту.
    function SR.LogFor(rec)
        SR.Trim(rec)
        local out = {}
        for _, e in ipairs(rec.entryLog or {}) do
            out[#out + 1] = {
                at = e.at, kind = e.kind, who = e.who, faction = e.faction,
                what = e.what, warrantNo = e.warrantNo, warrantBy = e.warrantBy,
                judge = e.judge, reason = e.reason,
            }
        end
        -- Свежие сверху: это то, что интересует в первую очередь.
        table.sort(out, function(a, b) return (a.at or 0) > (b.at or 0) end)
        return out
    end

    --- Найти жильё игрока: сначала то, в котором стоит, иначе своё.
    local function targetProperty(ply)
        local HS = GRM.Housing
        if not HS then return nil end
        if HS.HousingAt then
            local here = HS.HousingAt(ply:GetPos())
            if here and SR.CanViewLog(ply, here) then return here end
        end
        if HS.HomeOf then return HS.HomeOf(ply) end
        return nil
    end

    function SR.Open(ply)
        if not IsValid(ply) then return false end
        local rec = targetProperty(ply)
        if not rec then
            if GRM.Notify then GRM.Notify(ply, "У вас нет жилья, и вы не в чужом.", 255, 180, 90) end
            return false
        end
        if not SR.CanViewLog(ply, rec) then
            if GRM.Notify then GRM.Notify(ply, "Журнал этого жилья вам недоступен.", 255, 120, 100) end
            return false
        end
        net.Start(SR.NET.LOG)
            net.WriteString(tostring(rec.name or "Жильё"))
            net.WriteTable(SR.LogFor(rec))
        net.Send(ply)
        return true
    end

    concommand.Add("grm_housing_log", function(ply) SR.Open(ply) end)

    hook.Add("PlayerSay", "GRM_HousingSearch_Chat", function(ply, text)
        local s = string.lower(string.Trim(text or ""))
        if s == "/housing_log" or s == "/журнал_жилья" then
            SR.Open(ply)
            return ""
        end
    end)

    hook.Add("ShutDown", "GRM_HousingSearch_Save", function() SR.SavePending() end)

    if GRM.Modules and GRM.Modules.Register then
        GRM.Modules.Register("housing_search", {
            label = "Жильё: обыск и журнал",
            version = SR.Version,
            Status = function()
                return "ожидают уведомления: " .. tostring(table.Count(SR.Pending or {}))
            end,
            Depends = { "housing" },
        })
    end
end

-----------------------------------------------------------------------
-- КЛИЕНТ
-----------------------------------------------------------------------
if CLIENT then
    surface.CreateFont("GRMHLog_Title", { font = "Roboto", size = 21, weight = 800, extended = true, antialias = true })
    surface.CreateFont("GRMHLog_Row",   { font = "Roboto", size = 15, weight = 600, extended = true, antialias = true })
    surface.CreateFont("GRMHLog_Small", { font = "Roboto", size = 13, weight = 500, extended = true, antialias = true })

    local C = {
        bg   = Color(14, 19, 28, 250),
        head = Color(22, 30, 44, 255),
        row  = Color(22, 28, 40, 240),
        text = Color(228, 236, 248),
        dim  = Color(148, 162, 182),
        gold = Color(245, 198, 70),
    }

    net.Receive(SR.NET.LOG, function()
        local name = net.ReadString()
        local rows = net.ReadTable() or {}

        local f = vgui.Create("DFrame")
        f:SetTitle("")
        f:SetSize(math.min(760, ScrW() - 60), math.min(560, ScrH() - 60))
        f:Center()
        f:MakePopup()
        f:ShowCloseButton(false)
        if GRM.UI and GRM.UI.Track then GRM.UI.Track("housing.log", f) end
        f.Paint = function(_, w, h)
            draw.RoundedBox(8, 0, 0, w, h, C.bg)
            draw.RoundedBoxEx(8, 0, 0, w, 52, C.head, true, true, false, false)
            draw.SimpleText("ЖУРНАЛ ВХОДОВ — " .. tostring(name), "GRMHLog_Title", 16, 14, C.gold)
            draw.SimpleText(("записей: %d  ·  хранится 14 суток"):format(#rows),
                "GRMHLog_Small", 16, 35, C.dim)
        end

        local x = vgui.Create("DButton", f)
        x:SetText("✕") x:SetFont("GRMHLog_Title") x:SetTextColor(color_white)
        x:SetSize(34, 30) x:SetPos(f:GetWide() - 42, 11)
        x.Paint = function(s, w, h)
            draw.RoundedBox(6, 0, 0, w, h, s:IsHovered() and Color(170, 60, 60) or Color(48, 30, 34))
        end
        x.DoClick = function() f:Close() end

        local sc = vgui.Create("DScrollPanel", f)
        sc:SetPos(14, 62)
        sc:SetSize(f:GetWide() - 28, f:GetTall() - 76)

        if #rows == 0 then
            local l = vgui.Create("DLabel", sc)
            l:Dock(TOP) l:SetTall(40)
            l:SetFont("GRMHLog_Row") l:SetTextColor(C.dim)
            l:SetText("  Никто чужой не входил.")
            return
        end

        for _, e in ipairs(rows) do
            local kind = SR.Kinds[tostring(e.kind or "")] or SR.Kinds.guest
            local col = Color(kind.color[1], kind.color[2], kind.color[3])

            -- Высота карточки зависит от того, есть ли данные ордера.
            local hasWarrant = tostring(e.warrantNo or "") ~= "" or tostring(e.reason or "") ~= ""
            local p = vgui.Create("DPanel", sc)
            p:Dock(TOP) p:DockMargin(0, 0, 0, 6)
            p:SetTall(hasWarrant and 74 or 50)
            p.Paint = function(_, w, h)
                draw.RoundedBox(6, 0, 0, w, h, C.row)
                draw.RoundedBox(0, 0, 0, 3, h, col)

                draw.SimpleText(kind.label, "GRMHLog_Small", 14, 10, col)
                draw.SimpleText(os.date("%d.%m.%Y  %H:%M", tonumber(e.at) or 0),
                    "GRMHLog_Small", w - 14, 10, C.dim, TEXT_ALIGN_RIGHT)

                local who = tostring(e.who or "неизвестно")
                if tostring(e.faction or "") ~= "" then who = who .. "  ·  " .. e.faction end
                draw.SimpleText(who, "GRMHLog_Row", 14, 26, C.text)

                if tostring(e.what or "") ~= "" then
                    draw.SimpleText(tostring(e.what), "GRMHLog_Small", w - 14, 28, C.dim, TEXT_ALIGN_RIGHT)
                end

                if hasWarrant then
                    local line = ""
                    if tostring(e.warrantNo or "") ~= "" then line = "Ордер №" .. e.warrantNo end
                    if tostring(e.judge or "") ~= "" then
                        line = line .. (line ~= "" and "  ·  " or "") .. "суд: " .. e.judge
                    end
                    if tostring(e.reason or "") ~= "" then
                        line = line .. (line ~= "" and "  ·  " or "") .. e.reason
                    end
                    draw.SimpleText(line, "GRMHLog_Small", 14, 50, C.dim)
                end
            end
        end
    end)
end
