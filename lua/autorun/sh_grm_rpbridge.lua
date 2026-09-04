--[[ GRM.RPBroadcast — ЕДИНАЯ шина RP-отыгровок серверной originates (вечер-13).

    До этого каждый модуль (документы, образование/дипломы) сам реализовывал
    трёхветочную развилку «EasyChat → GRM_RPChat_Msg → ChatPrint»: дубли кода,
    мёртвая ветка EasyChat (чат вырезан по указанию владельца), а на сервере
    с режимным чатом строки шли МИМО ленты режима. Теперь точка входа одна:

      1) живой владелец чата (GRMRPChat — он же библиотека lua/grm_chat,
         он же алиас GRMChat в смешанных установках) — доставка через его
         RPAction("me") с echo автора, RP-именем, радиусом/явной аудиторией;
      2) владельца нет (слайс-установка без чата) — ChatPrint по аудитории/
         радиусу. ПРЕЖНЯЯ ветка «старая net-шина GRM_RPChat_Msg» ВЫРЕЗАНА
         вечером-15: это привязка к легаси-модулю, а не «своя система»
         (приказ раунда 18–19).

    Правила подключения модулей (записаны в OWNER_REPORTS.md): новый код НЕ
    выбирает канал сам — только GRM.RPBroadcast.
]]

GRM = GRM or {}

function GRM.GetRPName(ply)
    if not IsValid(ply) then return "?" end
    local n = ply:GetNWString("GRM_RPName", "")
    return (n ~= "" and n) or ply:Nick()
end

if not SERVER then return end

-- Порядок обхода не порождает двойную доставку: в новом мире GRMChat —
-- АЛИАС того же стола GRMRPChat (lua/grm_chat/sh_core), цикл возвращается
-- на первом владельце. Отдельный стол «GRMChat» бывает только при смешанной
-- установке старого аддона; его подавитель помечает SUPPRESSED — шина
-- его пропускает и уходит на GRMRPChat; нет ни одного — движковый ChatPrint
-- (вечер-15: ветка легаси-шины GRM_RPChat_Msg из фолбэка ВЫРЕЗАНА).
local CHAT_OWNERS = { "GRMRPChat", "GRMChat" }

--- meText — текст действия без ведущей «* » (шина сама добавит формат).
--- Третьим аргументом — ЦЕЛЕБАРИУС (вечер-15, автоотыгровки документов):
---   nil | number        — радиус в юнитах (400 по умолчанию, бланки веч.-8…12);
---   Player              — строгий адресат («предъявляет вам…» видит только он);
---   table {radius=n, targets={...}, echoAuthor=bool} — аудиторию считает сам
---     модуль (у неё свои побочные эффекты: Learn/счётчик услышавших), а шина
---     доставляет; echoAuthor=false — авторскую строку модуль печатает сам.
--- Возвращает строку-ошибку владельца (или nil), как RPAction.
local function asTargets(t)
    if t == nil then return nil end
    if isplayer(t) then return { t } end
    if istable(t) then
        if isnumber(t.radius) or t.targets ~= nil then
            local list = t.targets
            if isplayer(list) then list = { list } end
            if istable(list) and #list > 0 then return list end
            return nil
        end
        if #t > 0 then return t end -- просто массив слушателей
    end
    return nil
end

function GRM.RPBroadcast(ply, meText, targeting)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    meText = string.Trim(tostring(meText or ""))
    if meText == "" then return end
    local radius, targets, echoAuthor = 400, nil, true
    local rpName = GRM.GetRPName(ply)
    if isnumber(targeting) then
        radius = math.Clamp(targeting, 64, 4096)
    elseif isplayer(targeting) then
        targets = { targeting }
    elseif istable(targeting) then
        radius = math.Clamp(tonumber(targeting.radius) or 400, 64, 4096)
        targets = asTargets(targeting.targets) or asTargets(targeting)
        echoAuthor = targeting.echoAuthor ~= false
        -- «под легендой» отыгровка идёт_mask-name'ом (nameplate), не настоящим
        -- RP-именем: имя — часть сюжета, позволяет передать его модулю.
        if isstring(targeting.rpName) and targeting.rpName ~= "" then
            rpName = targeting.rpName
        end
    end

    for i = 1, #CHAT_OWNERS do
        local owner = rawget(_G, CHAT_OWNERS[i])
        if istable(owner) and istable(owner.Channels) and not owner.SUPPRESSED
            and isfunction(owner.RPAction)
            and (not isfunction(owner.Enabled) or owner.Enabled()) then
            local body = isfunction(owner.Sanitize)
                and owner.Sanitize(meText, owner.HARD_MAX) or meText
            return owner.RPAction("me", ply, body, nil, {
                echoAuthor = echoAuthor, -- серверное событие: автору шлём (у него
                                         -- нет локального эха клиентского ввода)
                rpName = rpName,
                range = radius,
                targets = targets,
            })
        end
    end

    -- Владельца нет: только движковый ChatPrint по аудитории/радиусу.
    local full = "* " .. rpName .. " " .. meText
    if targets then
        for i = 1, #targets do
            if IsValid(targets[i]) then targets[i]:ChatPrint(full) end
        end
        if echoAuthor then ply:ChatPrint(full) end
        return
    end
    local origin = ply:GetPos()
    local pool = (GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()
    for _, p in ipairs(pool) do
        if IsValid(p) and p:GetPos():DistToSqr(origin) <= radius * radius then
            p:ChatPrint(full)
        end
    end
end
