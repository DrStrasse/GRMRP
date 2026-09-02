--[[--------------------------------------------------------------------
    GRM Wanted Bulletins v1.0.0 — ориентировки по служебным каналам.

    Требование: сведения о розыске должны автоматически уходить в эфир —
    «своим» по волне фракции (/fr) и «соседям» по волне департамента
    (/dep, /d), а также рассылаться вручную кнопкой из листа розыска
    и терминала.

    Каналы:
      "fr"  — волна своей фракции (Factions_Radio). Только свои сотрудники.
      "dep" — общая волна департаментов (Factions_Dep). Все ведомства,
              у которых включён DepAccess. Это и есть «передача сведений
              соседнему ведомству».

    Сообщения не проходят через sh_factions.lua: там обработчики привязаны
    к тексту игрока, а нам нужен свой формат и свои цвета. Получателей
    считаем по тем же правилам (фракция / DepAccess), поэтому эфир слышат
    ровно те же люди.

    Автоориентировки:
      GRM_WantedChargeAdded  → «своим» всегда, на волну — с уровня
                               Config.AutoDepLevel;
      GRM_WantedLevelChanged → снятие розыска (отбой ориентировки);
      GRM_WantedFineIssued   → крупные штрафы (Config.AutoFineAmount).

    Каналы net:
      GRM_WantedBulletin_Send  client → server  (String channel,
                                                 String targetKey,
                                                 String note)
      GRM_WantedBulletin_Msg   server → client  (UInt8 r,g,b,
                                                 String prefix, String text)
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Wanted = GRM.Wanted or {}
GRM.Wanted.Bulletins = GRM.Wanted.Bulletins or {}

local BL = GRM.Wanted.Bulletins
BL.Version = "1.0.0"

local NET_SEND = "GRM_WantedBulletin_Send"
local NET_MSG  = "GRM_WantedBulletin_Msg"

BL.Config = BL.Config or {
    -- уровень розыска, начиная с которого ориентировка автоматически
    -- уходит на общую волну департаментов
    AutoDepLevel   = 3,
    -- автоориентировка «своим» при каждой новой статье
    AutoFrOnCharge = true,
    -- сумма штрафа, с которой о нём сообщают на волну (0 = никогда)
    AutoFineAmount = 25000,
    -- сообщать по волне о снятии розыска
    AutoClear      = true,
    -- пауза между автоориентировками по одной цели, сек
    PerTargetCooldown = 20,
    -- пауза между ручными ориентировками одного сотрудника, сек
    PerActorCooldown  = 3,
    -- максимум статей, перечисляемых в тексте ориентировки
    MaxCharges     = 3,
}

-----------------------------------------------------------------------
-- Общие хелперы
-----------------------------------------------------------------------
-- Ключ персонажа — канон ядра (§5.2.6): одна реализация на проект,
-- ранняя привязка безопасна, sh_01_grm_core.lua грузится первым.
local charKey = GRM.CharKey
BL.CharKey = charKey

function BL.ChannelName(ch)
    if ch == "dep" then return "ВОЛНА ДЕПАРТАМЕНТОВ" end
    return "ВОЛНА ВЕДОМСТВА"
end

if SERVER then
    util.AddNetworkString(NET_SEND)
    util.AddNetworkString(NET_MSG)

    -----------------------------------------------------------------------
    -- Получатели
    -----------------------------------------------------------------------
    local function factionOf(ply)
        return ply:GetNWString("GRM_Faction", "")
    end

    --- Все фракции, у которых включён доступ к волне департаментов.
    local function depFactions()
        local out = {}
        local API = _G.FactionsAPI
        if API and isfunction(API.List) then
            local okList, list = pcall(API.List)
            if okList and istable(list) then
                for name, f in pairs(list) do
                    if istable(f) and f.DepAccess == true then out[name] = true end
                end
            end
        end
        return out
    end
    BL.DepFactions = depFactions

    --- Получатели канала.
    -- @param ch "fr" | "dep"
    -- @param sender игрок-отправитель (для "fr" определяет фракцию)
    function BL.Recipients(ch, sender)
        local out = {}
        if ch == "dep" then
            local allowed = depFactions()
            for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                if IsValid(p) and allowed[factionOf(p)] then out[#out + 1] = p end
            end
            return out
        end

        local mine = IsValid(sender) and factionOf(sender) or ""
        if mine == "" then return out end
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(p) and factionOf(p) == mine then out[#out + 1] = p end
        end
        return out
    end

    --- Может ли игрок пользоваться каналом.
    function BL.CanUse(ply, ch)
        if not (IsValid(ply) and ply:IsPlayer()) then return false, "Нет игрока" end
        if ply:IsSuperAdmin() then return true end

        local fName = factionOf(ply)
        if fName == "" then return false, "Вы не состоите ни в одной фракции" end

        if ch == "dep" then
            if not depFactions()[fName] then
                return false, "Ваша фракция не имеет доступа к волне департамента"
            end
        end

        -- Право работать с розыском: без него ориентировку слать нечего.
        local B = GRM.Wanted.Board
        if B and isfunction(B.CanBroadcast) and B.CanBroadcast(ply) then return true end

        local W = GRM.Wanted
        if W and isfunction(W.CanEdit) and W.CanEdit(ply) then return true end

        return false, "У вас нет прав на рассылку ориентировок"
    end

    -----------------------------------------------------------------------
    -- Отправка
    -----------------------------------------------------------------------
    local function colorFor(ch, jur)
        if ch == "dep" then
            return jur == "military" and Color(174, 98, 255) or Color(48, 204, 255)
        end
        return jur == "military" and Color(200, 150, 255) or Color(250, 185, 63)
    end

    --- Низкоуровневая рассылка текста в канал.
    -- @param ch      "fr" | "dep"
    -- @param sender  игрок или nil (системная ориентировка)
    -- @param text    готовый текст
    -- @param jur     "civil" | "military" — влияет только на цвет
    -- @param targets список получателей (по умолчанию считается сам)
    function BL.Raw(ch, sender, text, jur, targets, prefixOverride)
        text = tostring(text or "")
        if text == "" then return 0 end

        local rec = istable(targets) and targets or BL.Recipients(ch, sender)
        if #rec == 0 then return 0 end

        local col = colorFor(ch, jur)
        local prefix = tostring(prefixOverride or "")
        if prefix == "" then
            prefix = ch == "dep" and "[Волна • ОРИЕНТИРОВКА] " or "[Ведомство • ОРИЕНТИРОВКА] "
        end

        net.Start(NET_MSG)
            net.WriteUInt(col.r, 8) net.WriteUInt(col.g, 8) net.WriteUInt(col.b, 8)
            net.WriteString(prefix)
            net.WriteString(text)
        net.Send(rec)
        return #rec
    end

    --- Текст ориентировки по записи розыска.
    -- @param rec  запись GRM.Wanted.Records
    -- @param key  ключ персонажа
    -- @param note дополнение оператора
    function BL.Describe(rec, key, note)
        local W = GRM.Wanted
        local level = tonumber(rec and rec.level) or 0
        local jur = (rec and rec.jurisdiction == "military") and "military" or "civil"
        local lvName = (W and W.Levels and W.Levels[level] and W.Levels[level].name) or ("уровень " .. level)
        local status = jur == "military" and "ВОЕННЫЙ" or "ГРАЖДАНСКИЙ"

        local charges = {}
        local reasons = (rec and istable(rec.reasons)) and rec.reasons or {}
        for i = #reasons, 1, -1 do
            if #charges >= (BL.Config.MaxCharges or 3) then break end
            local c = reasons[i]
            if istable(c) then
                charges[#charges + 1] = (c.code and c.code ~= "" and (c.code .. " ") or "") .. tostring(c.title or "")
            end
        end

        local parts = {
            ("РАЗЫСКИВАЕТСЯ: %s [%s]"):format(tostring(rec and rec.name or key), status),
            ("уровень %d — %s"):format(level, lvName),
        }
        if #charges > 0 then
            parts[#parts + 1] = "статьи: " .. table.concat(charges, "; ")
        end
        if #reasons > #charges then
            parts[#parts + 1] = ("и ещё %d"):format(#reasons - #charges)
        end

        -- онлайн-подсказка помогает патрулю сориентироваться
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(p) and charKey(p) == key then
                parts[#parts + 1] = "фигурант в сети"
                break
            end
        end

        if note and string.Trim(note) ~= "" then
            parts[#parts + 1] = string.Trim(note)
        end

        return table.concat(parts, " • "), jur
    end

    --- Ориентировка по конкретной записи розыска.
    -- @return успех, сообщение
    function BL.Announce(actor, ch, key, note)
        key = charKey(key)
        if key == "" then return false, "Не указан фигурант" end

        local W = GRM.Wanted
        local rec = W and istable(W.Records) and W.Records[key]
        if not rec then return false, "Запись розыска не найдена" end

        -- Скрытые спецслужбами записи в эфир не уходят.
        if rec.covert == true and not (IsValid(actor) and actor:IsSuperAdmin()) then
            local SS = GRM.SpecialService
            if not (SS and isfunction(SS.IsAgent) and SS.IsAgent(actor)) then
                return false, "Запись розыска не найдена"
            end
        end

        local text, jur = BL.Describe(rec, key, note)
        if IsValid(actor) then
            local tag = actor:GetNWString("GRM_FactionTag", "")
            if tag == "" then tag = actor:GetNWString("GRM_Faction", "") end
            local role = actor:GetNWString("GRM_Role", "")
            local who = tag ~= "" and ("[" .. tag .. "] ") or ""
            text = ("%s%s%s: %s"):format(who, actor:Nick(), role ~= "" and (" (" .. role .. ")") or "", text)
        else
            text = "Автоматическая сводка: " .. text
        end

        local n = BL.Raw(ch, actor, text, jur)
        if n == 0 then return false, "Канал пуст: некому передать" end

        -- Ориентировка — это межведомственное действие, фиксируем.
        local X = GRM.Wanted.Exchange
        if X and isfunction(X.Log) then
            X.Log("bulletin", actor, key, ch, note)
        end
        return true, ("Ориентировка передана (%d получателей)"):format(n)
    end

    -----------------------------------------------------------------------
    -- Автоориентировки
    -----------------------------------------------------------------------
    local lastAuto = {}

    local function autoThrottled(key)
        local now = CurTime()
        local prev = lastAuto[key] or -1000
        if now - prev < (BL.Config.PerTargetCooldown or 20) then return true end
        lastAuto[key] = now
        return false
    end

    hook.Add("GRM_WantedChargeAdded", "GRM_Bulletins_Auto", function(issuer, target, charge, rec)
        if not istable(rec) then return end
        local key = rec.sid or (IsValid(target) and charKey(target)) or ""
        if key == "" then return end
        if rec.covert == true then return end
        if autoThrottled(key) then return end

        local note = "основание: " .. tostring(charge and charge.title or "новая статья")

        if BL.Config.AutoFrOnCharge and IsValid(issuer) then
            BL.Announce(issuer, "fr", key, note)
        end

        local level = tonumber(rec.level) or 0
        if level >= (BL.Config.AutoDepLevel or 3) then
            BL.Announce(issuer, "dep", key, note)
        end
    end)

    hook.Add("GRM_WantedLevelChanged", "GRM_Bulletins_Clear", function(actor, key, oldLevel, newLevel)
        if not BL.Config.AutoClear then return end
        if (tonumber(newLevel) or 0) ~= 0 then return end
        if (tonumber(oldLevel) or 0) < (BL.Config.AutoDepLevel or 3) then return end

        key = charKey(key)
        local W = GRM.Wanted
        local rec = W and istable(W.Records) and W.Records[key]
        local name = (rec and rec.name) or key
        local jur = (rec and rec.jurisdiction) or "civil"
        local who = IsValid(actor) and (actor:Nick() .. ": ") or ""
        BL.Raw("dep", actor, ("%sОТБОЙ ОРИЕНТИРОВКИ — %s снят с розыска"):format(who, name), jur)
    end)

    hook.Add("GRM_WantedFineIssued", "GRM_Bulletins_Fine", function(rec)
        local minAmount = tonumber(BL.Config.AutoFineAmount) or 0
        if minAmount <= 0 or not istable(rec) then return end
        if (tonumber(rec.amount) or 0) < minAmount then return end

        local money = GRM.FormatMoney and GRM.FormatMoney(rec.amount) or tostring(rec.amount)
        BL.Raw("dep", nil, ("Взыскание: %s — %s (%s). Основание: %s")
            :format(tostring(rec.targetName or rec.target), money,
                    tostring(rec.issuerName or "ведомство"), tostring(rec.reason or "нарушение")),
            rec.jurisdiction)
    end)

    -----------------------------------------------------------------------
    -- Приём от клиента (кнопки листа розыска и терминала)
    -----------------------------------------------------------------------
    net.Receive(NET_SEND, function(_, ply)
        if not (IsValid(ply) and ply:IsPlayer()) then return end

        ply.GRM_BulletinNext = ply.GRM_BulletinNext or 0
        if CurTime() < ply.GRM_BulletinNext then return end
        ply.GRM_BulletinNext = CurTime() + (BL.Config.PerActorCooldown or 3)

        local ch   = string.sub(net.ReadString(), 1, 8)
        local key  = string.sub(net.ReadString(), 1, 64)
        local note = string.sub(net.ReadString(), 1, 160)

        if ch ~= "fr" and ch ~= "dep" then ch = "fr" end

        local allowed, why = BL.CanUse(ply, ch)
        if not allowed then
            if GRM.Notify then GRM.Notify(ply, why or "Канал недоступен", 250, 110, 110)
            else ply:ChatPrint("[Ориентировка] " .. tostring(why)) end
            return
        end

        local ok, msg = BL.Announce(ply, ch, key, note)
        if GRM.Notify then
            GRM.Notify(ply, tostring(msg), ok and 110 or 250, ok and 220 or 110, ok and 150 or 110)
        else
            ply:ChatPrint("[Ориентировка] " .. tostring(msg))
        end
    end)

    -----------------------------------------------------------------------
    -- Чат-команды
    -----------------------------------------------------------------------
    local function resolveTarget(arg)
        if not arg or arg == "" then return "" end
        local low = string.lower(arg)
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(p) then
                if charKey(p) == arg or p:SteamID64() == arg then return charKey(p) end
                if string.find(string.lower(p:Nick()), low, 1, true) then return charKey(p) end
                local rp = p:GetNWString("GRM_RPName", "")
                if rp ~= "" and string.find(string.lower(rp), low, 1, true) then return charKey(p) end
            end
        end
        -- офлайн: ищем по базе
        local W = GRM.Wanted
        if W and istable(W.Records) then
            if W.Records[charKey(arg)] then return charKey(arg) end
            for k, r in pairs(W.Records) do
                if istable(r) and string.find(string.lower(tostring(r.name or "")), low, 1, true) then return k end
            end
        end
        return charKey(arg)
    end
    BL.ResolveTarget = resolveTarget

    local function reply(ply, ok, text)
        if not IsValid(ply) then return end
        if GRM.Notify then GRM.Notify(ply, text, ok and 110 or 250, ok and 220 or 110, ok and 150 or 110)
        else ply:ChatPrint("[Ориентировка] " .. text) end
    end

    --- /fr_wanted <цель> [заметка] — ориентировка своим.
    function BL.CmdFr(ply, args)
        local target = resolveTarget(args[1])
        if target == "" then return reply(ply, false, "Использование: /fr_wanted <игрок> [примечание]") end
        local allowed, why = BL.CanUse(ply, "fr")
        if not allowed then return reply(ply, false, why) end
        local ok, msg = BL.Announce(ply, "fr", target, table.concat(args, " ", 2))
        reply(ply, ok, msg)
    end

    --- /dep_wanted <цель> [заметка] — ориентировка соседям по волне.
    function BL.CmdDep(ply, args)
        local target = resolveTarget(args[1])
        if target == "" then return reply(ply, false, "Использование: /dep_wanted <игрок> [примечание]") end
        local allowed, why = BL.CanUse(ply, "dep")
        if not allowed then return reply(ply, false, why) end
        local ok, msg = BL.Announce(ply, "dep", target, table.concat(args, " ", 2))
        reply(ply, ok, msg)
    end

    --- /bulletin <fr|dep|d> <текст> — свободная ориентировка без записи.
    function BL.CmdFree(ply, args)
        local ch = string.lower(tostring(args[1] or ""))
        if ch == "d" then ch = "dep" end
        if ch ~= "fr" and ch ~= "dep" then
            return reply(ply, false, "Использование: /bulletin <fr|dep> <текст>")
        end
        local text = string.Trim(table.concat(args, " ", 2))
        if text == "" then return reply(ply, false, "Пустая ориентировка") end

        local allowed, why = BL.CanUse(ply, ch)
        if not allowed then return reply(ply, false, why) end

        local W = GRM.Wanted
        local jur = (W and isfunction(W.JurisdictionOfPlayer)) and W.JurisdictionOfPlayer(ply) or "civil"
        local tag = ply:GetNWString("GRM_FactionTag", "")
        if tag == "" then tag = ply:GetNWString("GRM_Faction", "") end
        local body = ("[%s] %s: %s"):format(tag ~= "" and tag or "ведомство", ply:Nick(), text)

        local n = BL.Raw(ch, ply, body, jur)
        reply(ply, n > 0, n > 0 and ("Передано (%d получателей)"):format(n) or "Канал пуст: некому передать")
    end

    local HANDLERS = {
        ["/fr_wanted"]   = BL.CmdFr,
        ["/frw"]         = BL.CmdFr,
        ["/ориентировка"] = BL.CmdFr,
        ["/dep_wanted"]  = BL.CmdDep,
        ["/depw"]        = BL.CmdDep,
        ["/dw"]          = BL.CmdDep,
        ["/bulletin"]    = BL.CmdFree,
        ["/orient"]      = BL.CmdFree,
    }
    BL.Handlers = HANDLERS

    local dispatch = GRM.Chat.DispatchFactory("[GRM Bulletins]", HANDLERS, reply)
    BL.Dispatch = dispatch

    hook.Add("PlayerSayTransform", "GRM_Bulletins_Transform", function(ply, pack)
        if not istable(pack) or not isstring(pack[1]) then return end
        if dispatch(ply, pack[1]) then
            pack[1] = ""
            pack.SkipPlayerSay = true
        end
    end)

    hook.Add("PlayerSay", "GRM_Bulletins_Fallback", function(ply, text)
        if dispatch(ply, text) then return "" end
    end)

    concommand.Add("grm_bulletin_fr",  function(ply, _, args) if IsValid(ply) then BL.CmdFr(ply, args or {}) end end)
    concommand.Add("grm_bulletin_dep", function(ply, _, args) if IsValid(ply) then BL.CmdDep(ply, args or {}) end end)
    concommand.Add("grm_bulletin",     function(ply, _, args) if IsValid(ply) then BL.CmdFree(ply, args or {}) end end)

    print("[GRM Wanted Bulletins] сервер v" .. BL.Version .. " загружен")
end

if CLIENT then
    net.Receive(NET_MSG, function()
        local r, g, b = net.ReadUInt(8), net.ReadUInt(8), net.ReadUInt(8)
        local prefix  = net.ReadString()
        local text    = net.ReadString()
        chat.AddText(Color(r, g, b), prefix, Color(235, 240, 245), text)
        surface.PlaySound("buttons/button17.wav")
    end)

    print("[GRM Wanted Bulletins] клиент v" .. BL.Version .. " загружен")
end
