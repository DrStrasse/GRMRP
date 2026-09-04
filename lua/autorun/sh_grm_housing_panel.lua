--[[--------------------------------------------------------------------
    GRM Housing Panel v1.0.0 — окно квартиры. Фаза 4, завершающая.

    ЗАЧЕМ. Всё, что нужно жильцу, было разбросано: ключи и коммуналка в
    /property (окно на 1250 пикселей со списком ВСЕХ объектов карты и
    админ-полями), журнал входов в /housing_log, шкаф на самом шкафу,
    точка входа вообще без интерфейса. Игрок не знал, где что искать.

    ЧТО ЭТО. Одно окно «МОЯ КВАРТИРА» (/home) с четырьмя вкладками:

        ОБЗОР     состояние, аренда, долг, кнопки оплаты и продления
        ЖИЛЬЦЫ    кто имеет ключ, выдать и отобрать
        ЖУРНАЛ    кто заходил (фаза 3)
        ХРАНЕНИЕ  что лежит в шкафу (фаза 2), без беготни к нему

    ЧЕГО ЗДЕСЬ НЕТ И ПОЧЕМУ. Модуль НЕ дублирует серверную логику:
    ключи, коммуналка, продление и освобождение уже реализованы в
    sh_grm_property.lua и вызываются его же net-протоколом. Здесь только
    сбор данных в одну картинку и удобные кнопки. Дублирование правил
    доступа в двух местах — самый быстрый способ получить дыру.

    ГЛАВНОЕ ДОБАВЛЕНИЕ ФАЗЫ (в property): ПРОДЛЕНИЕ АРЕНДЫ. Раньше
    продлить было нечем — аренда молча истекала, человека выселяло
    вместе с ключами и доступом к шкафу. Теперь есть кнопка и
    предупреждение за сутки.

    ВЫДАЧА КЛЮЧА ПО ВЗГЛЯДУ. В /property ключ выдавался вводом
    CharacterKey вида «765611...:char1» руками. Живой человек это не
    наберёт. Здесь — список игроков рядом и кнопка «дать ключ».
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.HousingPanel = GRM.HousingPanel or {}
local HP = GRM.HousingPanel

HP.Version = "1.0.0"
HP.NET = { OPEN = "GRM_HousingPanel_Open", ACT = "GRM_HousingPanel_Act" }

--- В каком радиусе ищем соседей для выдачи ключа.
HP.NearRadius = 320

-----------------------------------------------------------------------
-- СЕРВЕР
-----------------------------------------------------------------------
if SERVER then
    util.AddNetworkString(HP.NET.OPEN)
    util.AddNetworkString(HP.NET.ACT)

    -- Ключ персонажа — канон ядра (§5.2.6): одна реализация на проект.
    local charKey = GRM.CharKey

    local function rpName(ply)
        if not IsValid(ply) then return "" end
        local n = ply:GetNWString("GRM_RPName", "")
        return n ~= "" and n or ply:Nick()
    end

    --[[ Чью квартиру показываем. Приоритет — та, в которой стоим (чтобы
         жилец мог открыть панель прямо дома), иначе своя. ]]
    function HP.TargetOf(ply)
        local HS = GRM.Housing
        if not (HS and IsValid(ply)) then return nil end
        if HS.HousingAt then
            local here = HS.HousingAt(ply:GetPos())
            if istable(here) then
                local P = GRM.Property
                local mine = P and P.HasAccess and P.HasAccess(ply, here)
                if mine or (P and P.CanAdmin and P.CanAdmin(ply)) then return here end
            end
        end
        if HS.HomeOf then return HS.HomeOf(ply) end
        return nil
    end

    --- Игроки рядом — кандидаты на выдачу ключа.
    local function neighbours(ply, rec)
        local out = {}
        local list = (GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()
        for _, p in ipairs(list) do
            if IsValid(p) and p ~= ply then
                if p:GetPos():DistToSqr(ply:GetPos()) <= HP.NearRadius ^ 2 then
                    local key = charKey(p)
                    -- Уже имеющих ключ в список не пихаем: не с чем путать.
                    local has = false
                    for _, field in ipairs({ "employees", "guests" }) do
                        for _, v in ipairs(rec[field] or {}) do
                            if v.key == key then has = true break end
                        end
                    end
                    if not has and key ~= tostring(rec.ownerKey or "") then
                        out[#out + 1] = { key = key, name = rpName(p) }
                    end
                end
            end
        end
        return out
    end

    --- Всё об объекте одним пакетом.
    function HP.Data(ply, rec)
        local HS, ST, SR = GRM.Housing, GRM.HomeStorage, GRM.HousingSearch
        local P = GRM.Property

        local d = {
            id = tostring(rec.id or ""),
            name = tostring(rec.name or "Жильё"),
            typeName = (P and P.Types and P.Types[rec.type]) or "Жильё",
            owner = tostring(rec.ownerName or ""),
            isOwner = HS and HS.IsOwner and HS.IsOwner(ply, rec) or false,
            tenure = tostring(rec.tenure or "none"),
            rentUntil = tonumber(rec.rentUntil) or 0,
            rentPrice = tonumber(rec.rentPrice) or 0,
            utilityDebt = tonumber(rec.utilityDebt) or 0,
            utilityRate = tonumber(rec.utilityRate) or 0,
            --[[ Сколько вернут при продаже государству. Показывается на
                 кнопке отказа: игрок должен видеть сумму ДО того, как
                 согласится, а не узнавать её постфактум. ]]
            buyback = (GRM.Estate and GRM.Estate.StateBuyback)
                and math.floor((tonumber(rec.purchasePrice) or 0) * GRM.Estate.StateBuyback) or 0,
            sealed = rec.sealed == true,
            sealReason = tostring(rec.sealReason or ""),
            doors = #(rec.doors or {}),
            now = os.time(),
            keys = {},
            neighbours = {},
            log = {},
            storage = nil,
            spawnKind = "",
        }

        -- Ключи: сотрудники, гости, временные — одним списком с типом.
        for _, v in ipairs(rec.employees or {}) do
            d.keys[#d.keys + 1] = { key = v.key, name = v.name, kind = "employee" }
        end
        for _, v in ipairs(rec.guests or {}) do
            d.keys[#d.keys + 1] = { key = v.key, name = v.name, kind = "guest" }
        end
        for _, v in ipairs(rec.tempKeys or {}) do
            d.keys[#d.keys + 1] = { key = v.key, name = v.name, kind = "temp",
                expires = tonumber(v.expires) or 0 }
        end

        if d.isOwner then d.neighbours = neighbours(ply, rec) end

        -- Журнал входов из фазы 3 — только тем, кому он положен.
        if SR and SR.CanViewLog and SR.CanViewLog(ply, rec) and SR.LogFor then
            d.log = SR.LogFor(rec)
        end

        -- Шкаф из фазы 2: показываем сводку, чтобы не бежать к нему.
        if ST and ST.SlotsFor then
            local slots = ST.SlotsFor(rec)
            if slots then
                d.storage = {
                    used = ST.UsedSlots(slots),
                    max = ST.MaxSlots,
                    weight = ST.TotalWeight(slots),
                    maxWeight = ST.MaxWeight,
                }
            end
        end

        -- Откуда игрок появится дома (фаза 1).
        if HS and HS.SpawnPoint then
            local _, _, how = HS.SpawnPoint(rec)
            d.spawnKind = tostring(how or "")
        end
        return d
    end

    function HP.Open(ply)
        if not IsValid(ply) then return false end
        local rec = HP.TargetOf(ply)
        if not rec then
            if GRM.Notify then GRM.Notify(ply, "У вас нет жилья.", 255, 180, 90) end
            return false
        end
        net.Start(HP.NET.OPEN)
            net.WriteTable(HP.Data(ply, rec))
        net.Send(ply)
        return true
    end

    --[[ Действия. Намеренно НЕ переписываем логику property: собираем
         тот же пакет и отдаём его штатному обработчику. Одна реализация
         правил — один источник ошибок вместо двух. ]]
    net.Receive(HP.NET.ACT, function(bits, ply)
        if not IsValid(ply) then return end
        if GRM.Net and GRM.Net.Guard
            and not GRM.Net.Guard(ply, "housing.panel", { rate = .3, burst = 4, maxBits = 8192 }, { bits = bits }) then
            return
        end
        local a = net.ReadTable() or {}
        local act = tostring(a.action or "")
        local rec = HP.TargetOf(ply)
        if not istable(rec) then return end

        local P = GRM.Property
        if not P then return end

        if act == "refresh" then
            HP.Open(ply)
            return
        end

        -- Управлять может только владелец (или админ).
        local canManage = P.CanManage and P.CanManage(ply, rec)
        if not canManage then
            if GRM.Notify then GRM.Notify(ply, "Это не ваше жильё.", 255, 120, 100) end
            return
        end

        if act == "give_key" then
            --[[ Ключ по имени, а не по CharacterKey руками. Проверяем,
                 что человек ДЕЙСТВИТЕЛЬНО рядом: иначе можно было бы
                 раздавать ключи через полкарты по подобранному ключу. ]]
            local key = tostring(a.key or "")
            local target = GRM.Identity and GRM.Identity.ResolveCharacter
                and GRM.Identity.ResolveCharacter(key) or nil
            if not IsValid(target) then
                if GRM.Notify then GRM.Notify(ply, "Игрок не найден.", 255, 120, 100) end
                return
            end
            if target:GetPos():DistToSqr(ply:GetPos()) > HP.NearRadius ^ 2 then
                if GRM.Notify then GRM.Notify(ply, "Он слишком далеко.", 255, 120, 100) end
                return
            end
            P.PanelAction(ply, { action = "add_key", id = rec.id, key = key,
                name = rpName(target), kind = a.temp and "temp" or "guest",
                minutes = 1440 })
            if GRM.Notify then
                GRM.Notify(target, "Вам выдали ключ от «" .. tostring(rec.name) .. "».", 120, 220, 150)
            end
        elseif act == "take_key" then
            P.PanelAction(ply, { action = "remove_key", id = rec.id, key = tostring(a.key or "") })
        elseif act == "pay" then
            P.PanelAction(ply, { action = "pay_utilities", id = rec.id })
        elseif act == "extend" then
            P.PanelAction(ply, { action = "extend_rent", id = rec.id })
        elseif act == "release" then
            --[[ Отказ от жилья = продажа государству (единое правило,
                 28.08). Раньше здесь просто обнулялся владелец: игрок
                 терял квартиру и не получал НИЧЕГО, хотя в этом же окне
                 ему показывали «вернут при продаже: N GRM». Теперь
                 деньги действительно возвращаются, а долг по ЖКХ
                 удерживается. ]]
            local ES = GRM.Estate
            if ES and ES.SellToState then
                local okSell, msg = ES.SellToState(ply, rec)
                if GRM.Notify then
                    GRM.Notify(ply, tostring(msg or (okSell and "Объект продан государству."
                        or "Не удалось продать объект.")),
                        okSell and 120 or 255, okSell and 220 or 150, okSell and 150 or 110)
                end
            else
                P.PanelAction(ply, { action = "release", id = rec.id })
            end
        else
            return
        end

        -- Показываем результат сразу: окно не должно врать о состоянии.
        timer.Simple(0.05, function() if IsValid(ply) then HP.Open(ply) end end)
    end)

    concommand.Add("grm_home", function(ply) HP.Open(ply) end)

    hook.Add("PlayerSay", "GRM_HousingPanel_Chat", function(ply, text)
        local s = string.lower(string.Trim(text or ""))
        if s == "/home" or s == "/дом" or s == "/квартира" then
            HP.Open(ply)
            return ""
        end
    end)

    if GRM.Modules and GRM.Modules.Register then
        GRM.Modules.Register("housing_panel", {
            label = "Жильё: окно квартиры",
            version = HP.Version,
            Depends = { "housing" },
        })
    end
end

-----------------------------------------------------------------------
-- КЛИЕНТ
-----------------------------------------------------------------------
if CLIENT then
    surface.CreateFont("GRMHome_Title", { font = "Roboto", size = 23, weight = 800, extended = true, antialias = true })
    surface.CreateFont("GRMHome_Tab",   { font = "Roboto", size = 15, weight = 700, extended = true, antialias = true })
    surface.CreateFont("GRMHome_Row",   { font = "Roboto", size = 15, weight = 600, extended = true, antialias = true })
    surface.CreateFont("GRMHome_Small", { font = "Roboto", size = 13, weight = 500, extended = true, antialias = true })
    surface.CreateFont("GRMHome_Big",   { font = "Roboto", size = 30, weight = 800, extended = true, antialias = true })

    local C = {
        bg    = Color(14, 19, 28, 252),
        head  = Color(22, 30, 44, 255),
        card  = Color(23, 30, 43, 245),
        text  = Color(228, 236, 248),
        dim   = Color(148, 162, 182),
        gold  = Color(245, 198, 70),
        green = Color(96, 200, 130),
        red   = Color(216, 88, 84),
        blue  = Color(96, 168, 245),
    }

    local function send(a)
        net.Start(HP.NET.ACT) net.WriteTable(a) net.SendToServer()
    end

    --- Человеческий срок: «3 сут 4 ч», а не голые секунды.
    local function humanLeft(sec)
        sec = math.max(0, math.floor(tonumber(sec) or 0))
        if sec <= 0 then return "истекла" end
        local d = math.floor(sec / 86400)
        local h = math.floor((sec % 86400) / 3600)
        local m = math.floor((sec % 3600) / 60)
        if d > 0 then return d .. " сут " .. h .. " ч" end
        if h > 0 then return h .. " ч " .. m .. " мин" end
        return m .. " мин"
    end
    HP.HumanLeft = humanLeft

    local function mkBtn(parent, text, col, fn)
        local b = vgui.Create("DButton", parent)
        b:SetText("")
        b.Paint = function(s, w, h)
            local c = s:IsHovered() and Color(math.min(255, col.r + 30),
                math.min(255, col.g + 30), math.min(255, col.b + 30)) or col
            draw.RoundedBox(6, 0, 0, w, h, c)
            draw.SimpleText(text, "GRMHome_Tab", w / 2, h / 2, Color(16, 20, 28),
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        b.DoClick = fn
        return b
    end

    local function card(parent, tall)
        local p = vgui.Create("DPanel", parent)
        p:Dock(TOP) p:DockMargin(0, 0, 0, 8) p:SetTall(tall or 60)
        p.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, C.card) end
        return p
    end

    -----------------------------------------------------------------
    -- ВКЛАДКИ
    -----------------------------------------------------------------
    local function tabOverview(host, d)
        -- Состояние: главное крупно, чтобы читалось с одного взгляда.
        local top = card(host, 92)
        top.Paint = function(_, w, h)
            draw.RoundedBox(6, 0, 0, w, h, C.card)
            draw.RoundedBox(0, 0, 0, 3, h, d.sealed and C.red or C.green)
            draw.SimpleText(d.name, "GRMHome_Big", 16, 14, C.text)
            local sub = d.typeName .. "  ·  дверей: " .. d.doors
            if d.sealed then sub = sub .. "  ·  ОПЕЧАТАНО: " .. d.sealReason end
            draw.SimpleText(sub, "GRMHome_Small", 16, 52, d.sealed and C.red or C.dim)
            draw.SimpleText(d.isOwner and "ВЫ ВЛАДЕЛЕЦ" or ("Владелец: " .. (d.owner ~= "" and d.owner or "нет")),
                "GRMHome_Small", 16, 70, C.dim)
        end

        -- Аренда.
        if d.tenure == "rent" then
            local left = d.rentUntil - d.now
            local warn = left < 86400
            local rent = card(host, 74)
            rent.Paint = function(_, w, h)
                draw.RoundedBox(6, 0, 0, w, h, C.card)
                draw.RoundedBox(0, 0, 0, 3, h, warn and C.red or C.blue)
                draw.SimpleText("АРЕНДА", "GRMHome_Small", 16, 12, warn and C.red or C.blue)
                draw.SimpleText("Осталось: " .. humanLeft(left), "GRMHome_Row", 16, 32, C.text)
                draw.SimpleText(warn and "Скоро закончится — продлите, иначе жильё освободится."
                    or ("Продление стоит " .. d.rentPrice .. " GRM"),
                    "GRMHome_Small", 16, 52, warn and C.red or C.dim)
            end
            if d.isOwner then
                local b = mkBtn(rent, "ПРОДЛИТЬ", C.gold, function() send({ action = "extend" }) end)
                b:SetSize(150, 34)
                b:SetPos(host:GetWide() - 176, 20)
            end
        else
            local own = card(host, 52)
            own.Paint = function(_, w, h)
                draw.RoundedBox(6, 0, 0, w, h, C.card)
                draw.RoundedBox(0, 0, 0, 3, h, C.green)
                draw.SimpleText("В СОБСТВЕННОСТИ", "GRMHome_Small", 16, 10, C.green)
                draw.SimpleText("Аренду продлевать не нужно", "GRMHome_Row", 16, 28, C.text)
            end
        end

        -- Коммуналка.
        local util = card(host, 74)
        local debt = d.utilityDebt
        util.Paint = function(_, w, h)
            draw.RoundedBox(6, 0, 0, w, h, C.card)
            draw.RoundedBox(0, 0, 0, 3, h, debt > 0 and C.red or C.green)
            draw.SimpleText("КОММУНАЛЬНЫЕ", "GRMHome_Small", 16, 12, debt > 0 and C.red or C.green)
            draw.SimpleText(debt > 0 and ("Долг: " .. debt .. " GRM") or "Долга нет",
                "GRMHome_Row", 16, 32, C.text)
            draw.SimpleText("Тариф " .. d.utilityRate .. " GRM за период", "GRMHome_Small", 16, 52, C.dim)
        end
        if d.isOwner and debt > 0 then
            local b = mkBtn(util, "ОПЛАТИТЬ", C.green, function() send({ action = "pay" }) end)
            b:SetSize(150, 34)
            b:SetPos(host:GetWide() - 176, 20)
        end

        -- Шкаф и точка входа — сводкой.
        if d.storage then
            local st = card(host, 56)
            st.Paint = function(_, w, h)
                draw.RoundedBox(6, 0, 0, w, h, C.card)
                draw.RoundedBox(0, 0, 0, 3, h, C.blue)
                draw.SimpleText("ДОМАШНИЙ ШКАФ", "GRMHome_Small", 16, 10, C.blue)
                draw.SimpleText(("Занято %d из %d слотов  ·  %.1f / %d кг"):format(
                    d.storage.used, d.storage.max, d.storage.weight, d.storage.maxWeight),
                    "GRMHome_Row", 16, 30, C.text)
            end
        end

        local spawnText = ({
            manual = "Точка входа задана вручную",
            door   = "Точка входа определяется у двери",
            zone   = "Точка входа — центр зоны",
        })[d.spawnKind] or "Точка входа не настроена"
        local sp = card(host, 48)
        sp.Paint = function(_, w, h)
            draw.RoundedBox(6, 0, 0, w, h, C.card)
            draw.SimpleText(spawnText, "GRMHome_Small", 16, 16, C.dim)
        end

        if d.isOwner then
            local rel = card(host, 52)
            rel.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, C.card) end
            --[[ Текст кнопки честно называет, что произойдёт: объект
                 уходит государству за выкуп, а не «просто освобождается».
                 Раньше человек жал «отказаться» и терял деньги молча. ]]
            local b = mkBtn(rel, "ПРОДАТЬ ГОСУДАРСТВУ", C.red, function()
                Derma_Query(("Продать жильё государству за %d GRM?\nКлючи жильцов будут удалены.")
                    :format(d.buyback or 0), "Жильё",
                    "Продать", function() send({ action = "release" }) end, "Отмена")
            end)
            b:SetSize(260, 34) b:SetPos(16, 9)
        end
    end

    local function tabKeys(host, d)
        if not d.isOwner then
            local c = card(host, 48)
            c.Paint = function(_, w, h)
                draw.RoundedBox(6, 0, 0, w, h, C.card)
                draw.SimpleText("Управлять ключами может только владелец.", "GRMHome_Row", 16, 16, C.dim)
            end
            return
        end

        local head = card(host, 34)
        head.Paint = function(_, w, h)
            draw.SimpleText("У КОГО ЕСТЬ КЛЮЧ", "GRMHome_Small", 4, 12, C.gold)
        end

        if #d.keys == 0 then
            local c = card(host, 44)
            c.Paint = function(_, w, h)
                draw.RoundedBox(6, 0, 0, w, h, C.card)
                draw.SimpleText("Ключ только у вас.", "GRMHome_Row", 16, 14, C.dim)
            end
        end

        for _, k in ipairs(d.keys) do
            local row = card(host, 46)
            local label = ({ employee = "сотрудник", guest = "жилец", temp = "временный" })[k.kind] or k.kind
            local extra = ""
            if k.kind == "temp" and (k.expires or 0) > 0 then
                extra = "  ·  ещё " .. humanLeft(k.expires - d.now)
            end
            row.Paint = function(_, w, h)
                draw.RoundedBox(6, 0, 0, w, h, C.card)
                draw.SimpleText(k.name ~= "" and k.name or k.key, "GRMHome_Row", 16, 8, C.text)
                draw.SimpleText(label .. extra, "GRMHome_Small", 16, 26, C.dim)
            end
            local b = mkBtn(row, "ЗАБРАТЬ", C.red, function()
                send({ action = "take_key", key = k.key })
            end)
            b:SetSize(120, 30) b:SetPos(host:GetWide() - 146, 8)
        end

        local head2 = card(host, 34)
        head2.Paint = function() draw.SimpleText("КТО РЯДОМ", "GRMHome_Small", 4, 12, C.gold) end

        if #d.neighbours == 0 then
            local c = card(host, 44)
            c.Paint = function(_, w, h)
                draw.RoundedBox(6, 0, 0, w, h, C.card)
                draw.SimpleText("Рядом никого нет. Позовите человека и откройте окно снова.",
                    "GRMHome_Small", 16, 15, C.dim)
            end
        end

        for _, n in ipairs(d.neighbours) do
            local row = card(host, 46)
            row.Paint = function(_, w, h)
                draw.RoundedBox(6, 0, 0, w, h, C.card)
                draw.SimpleText(n.name, "GRMHome_Row", 16, 14, C.text)
            end
            local b1 = mkBtn(row, "КЛЮЧ", C.green, function()
                send({ action = "give_key", key = n.key })
            end)
            b1:SetSize(110, 30) b1:SetPos(host:GetWide() - 264, 8)
            local b2 = mkBtn(row, "НА СУТКИ", C.blue, function()
                send({ action = "give_key", key = n.key, temp = true })
            end)
            b2:SetSize(130, 30) b2:SetPos(host:GetWide() - 146, 8)
        end
    end

    local function tabLog(host, d)
        if #d.log == 0 then
            local c = card(host, 48)
            c.Paint = function(_, w, h)
                draw.RoundedBox(6, 0, 0, w, h, C.card)
                draw.SimpleText("Никто чужой не входил.", "GRMHome_Row", 16, 16, C.dim)
            end
            return
        end
        local kinds = (GRM.HousingSearch and GRM.HousingSearch.Kinds) or {}
        for _, e in ipairs(d.log) do
            local k = kinds[tostring(e.kind or "")] or { label = "ВХОД", color = { 150, 160, 180 } }
            local col = Color(k.color[1], k.color[2], k.color[3])
            local hasW = tostring(e.warrantNo or "") ~= "" or tostring(e.reason or "") ~= ""
            local row = card(host, hasW and 72 or 50)
            row.Paint = function(_, w, h)
                draw.RoundedBox(6, 0, 0, w, h, C.card)
                draw.RoundedBox(0, 0, 0, 3, h, col)
                draw.SimpleText(k.label, "GRMHome_Small", 14, 9, col)
                draw.SimpleText(os.date("%d.%m %H:%M", tonumber(e.at) or 0),
                    "GRMHome_Small", w - 14, 9, C.dim, TEXT_ALIGN_RIGHT)
                draw.SimpleText(tostring(e.who or ""), "GRMHome_Row", 14, 26, C.text)
                if hasW then
                    local line = ""
                    if tostring(e.warrantNo or "") ~= "" then line = "Ордер №" .. e.warrantNo end
                    if tostring(e.reason or "") ~= "" then
                        line = line .. (line ~= "" and "  ·  " or "") .. e.reason
                    end
                    draw.SimpleText(line, "GRMHome_Small", 14, 48, C.dim)
                end
            end
        end
    end

    local function tabStorage(host, d)
        local c = card(host, 96)
        c.Paint = function(_, w, h)
            draw.RoundedBox(6, 0, 0, w, h, C.card)
            draw.RoundedBox(0, 0, 0, 3, h, C.blue)
            if not d.storage then
                draw.SimpleText("Шкаф в этом жилье не установлен.", "GRMHome_Row", 16, 16, C.dim)
                draw.SimpleText("Попросите администрацию поставить grm_home_locker внутри квартиры.",
                    "GRMHome_Small", 16, 40, C.dim)
                return
            end
            draw.SimpleText("ДОМАШНИЙ ШКАФ", "GRMHome_Small", 16, 12, C.blue)
            draw.SimpleText(("Занято %d из %d слотов"):format(d.storage.used, d.storage.max),
                "GRMHome_Big", 16, 32, C.text)
            draw.SimpleText(("%.1f из %d кг"):format(d.storage.weight, d.storage.maxWeight),
                "GRMHome_Small", 16, 70, C.dim)

            -- Полоса заполнения: понятнее любых цифр.
            local frac = math.Clamp(d.storage.weight / math.max(1, d.storage.maxWeight), 0, 1)
            draw.RoundedBox(3, w - 236, 40, 220, 10, Color(12, 16, 24))
            draw.RoundedBox(3, w - 236, 40, math.max(2, 220 * frac), 10,
                frac > 0.9 and C.red or C.blue)
        end

        local hint = card(host, 44)
        hint.Paint = function(_, w, h)
            draw.RoundedBox(6, 0, 0, w, h, C.card)
            draw.SimpleText("Открыть содержимое можно у самого шкафа — нажмите на нём E.",
                "GRMHome_Small", 16, 15, C.dim)
        end
    end

    -----------------------------------------------------------------
    -- ОКНО
    -----------------------------------------------------------------
    HP._tab = HP._tab or "overview"

    local TABS = {
        { id = "overview", label = "ОБЗОР",    build = tabOverview },
        { id = "keys",     label = "ЖИЛЬЦЫ",   build = tabKeys },
        { id = "log",      label = "ЖУРНАЛ",   build = tabLog },
        { id = "storage",  label = "ХРАНЕНИЕ", build = tabStorage },
    }

    function HP.Show(d)
        if IsValid(HP._frame) then HP._frame:Remove() end

        local f = vgui.Create("DFrame")
        HP._frame = f
        f:SetTitle("")
        f:SetSize(math.min(820, ScrW() - 60), math.min(620, ScrH() - 60))
        f:Center()
        f:MakePopup()
        f:ShowCloseButton(false)
        if GRM.UI and GRM.UI.Track then GRM.UI.Track("housing.panel", f) end

        f.Paint = function(_, w, h)
            draw.RoundedBox(8, 0, 0, w, h, C.bg)
            draw.RoundedBoxEx(8, 0, 0, w, 52, C.head, true, true, false, false)
            draw.SimpleText("МОЯ КВАРТИРА", "GRMHome_Title", 16, 15, C.gold)
        end

        local x = vgui.Create("DButton", f)
        x:SetText("✕") x:SetFont("GRMHome_Title") x:SetTextColor(color_white)
        x:SetSize(34, 30) x:SetPos(f:GetWide() - 42, 11)
        x.Paint = function(s, w, h)
            draw.RoundedBox(6, 0, 0, w, h, s:IsHovered() and Color(170, 60, 60) or Color(48, 30, 34))
        end
        x.DoClick = function() f:Close() end

        local body = vgui.Create("DScrollPanel", f)
        body:SetPos(14, 96)
        body:SetSize(f:GetWide() - 28, f:GetTall() - 110)

        local function rebuild()
            if GRM.UI and GRM.UI.SafeClear then GRM.UI.SafeClear(body) else body:Clear() end
            for _, t in ipairs(TABS) do
                if t.id == HP._tab then t.build(body, d) break end
            end
        end

        -- Вкладки.
        local tabX = 14
        for _, t in ipairs(TABS) do
            local b = vgui.Create("DButton", f)
            b:SetText("")
            b:SetSize(126, 30)
            b:SetPos(tabX, 58)
            b.Paint = function(s, w, h)
                local on = HP._tab == t.id
                draw.RoundedBox(5, 0, 0, w, h, on and C.gold or (s:IsHovered() and C.card or Color(20, 26, 37)))
                draw.SimpleText(t.label, "GRMHome_Tab", w / 2, h / 2,
                    on and Color(16, 20, 28) or C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            b.DoClick = function() HP._tab = t.id rebuild() end
            tabX = tabX + 132
        end

        rebuild()
    end

    net.Receive(HP.NET.OPEN, function()
        HP.Show(net.ReadTable() or {})
    end)

    concommand.Add("grm_home", function()
        net.Start(HP.NET.ACT) net.WriteTable({ action = "refresh" }) net.SendToServer()
    end)
end

-- Вечер-18: единый словарь slash-команд: имена живого PlayerSay-обработчика
-- вносятся во внешний реестр библиотеки (на режиме сверка идёт ДО ParseSay —
-- без регистрации команда стала бы «неизвестной»).
if GRM and GRM.Chat and GRM.Chat.RegisterExternalCommands then
    GRM.Chat.RegisterExternalCommands({ "/home", "/дом", "/квартира" })
end
