--[[--------------------------------------------------------------------
    GRM Nameplate v1.0.0 — единая шапка над головой (этап 2 концепции
    CONCEPT_PCBOARD_IDENTITY.md)

    Было: ДВА независимых HUDPaint — описание из `sh_grm_rpdesc.lua` и шапка
    организации из `sh_factions.lua`. Каждый со своим радиусом, своей
    плашкой и своим проходом по всем игрокам каждый кадр. Отсюда двойные
    фоны, «прыгающие» подписи и лишняя работа на кадр.

    Стало: один проход, одна плашка, один радиус:

        ┌───────────────────────────────┐
        │  Ганс Мюллер          ГР-4821 │  имя (или «Неизвестный»), номер
        │  [ПД | СВАТ] Сержант          │  тег и должность — только на службе
        │  «Хромает на левую ногу»      │  описание, курсивом
        └───────────────────────────────┘

    Решение владельца: имя незнакомым НЕ показывается — «Неизвестный» до
    предъявления документа. Знакомство появляется, когда человек:
      • представился рядом стоящим (`/представиться`);
      • предъявил документ конкретному человеку (`/паспорт`);
      • был опознан через государственную базу (`/pcboard`) — сотрудник
        запомнил лицо.
    Знакомства хранятся на сервере (data/grm_identity/acquaintance.json) и
    переживают перезаход: один раз познакомились — знаете навсегда.

    Особые приметы (`/приметы`) видно НЕ над головой, а только при осмотре
    и в справке `/pcboard` — внешность и приметы это разные вещи.
----------------------------------------------------------------------]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Nameplate = GRM.Nameplate or {}
local NP = GRM.Nameplate
NP.Version = "1.0.0"

NP.Net = {
    SYNC  = "GRM_Nameplate_Sync",   -- полный список знакомых
    LEARN = "GRM_Nameplate_Learn",  -- новое знакомство
    MARKS = "GRM_Nameplate_Marks",  -- сохранение особых примет
}

--[[ Режимы видимости имени. Конвары создаёт СЕРВЕР и они реплицируются:
     клиент их только читает (создавать реплицируемый конвар на клиенте
     нельзя — это ошибка движка, а не «на всякий случай»). ]]
if SERVER then
    CreateConVar("grm_nameplate_mode", "docs",
        bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY),
        "Имя над головой: open — видно всем, acquainted — только знакомым, docs — «Неизвестный» до предъявления документа")
    CreateConVar("grm_nameplate_cid", "gov",
        bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED),
        "Номер гражданина над головой: never / gov (госслужащим на службе) / all")
    CreateConVar("grm_nameplate_gov_names", "0",
        bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED),
        "1 — госслужащий с допуском к базе видит имена без знакомства")
    CreateConVar("grm_nameplate_intro_dist", "200",
        bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED),
        "Радиус, в котором слышно, как человек представляется")
end

local function cvarString(name, default)
    local cv = GetConVar(name)
    if not cv then return default end
    local value = cv:GetString()
    if value == nil or value == "" then return default end
    return value
end
local function cvarNumber(name, default)
    local cv = GetConVar(name)
    if not cv then return default end
    return tonumber(cv:GetFloat()) or default
end

NP.MaxMarks = 240

function NP.Mode()
    local mode = string.lower(cvarString("grm_nameplate_mode", "docs"))
    if mode ~= "open" and mode ~= "acquainted" then return "docs" end
    return mode
end

function NP.CidMode()
    local mode = string.lower(cvarString("grm_nameplate_cid", "gov"))
    if mode ~= "never" and mode ~= "all" then return "gov" end
    return mode
end

function NP.GovNames() return cvarNumber("grm_nameplate_gov_names", 0) >= 1 end
function NP.IntroDist() return math.Clamp(cvarNumber("grm_nameplate_intro_dist", 200), 50, 1000) end

-- Ключ персонажа — канон ядра (§5.2.6). Локальная копия убрана: копия канона.
local charKeyOf = GRM.CharKey
NP.CharKey = charKeyOf

--[[ Единое правило видимости имени. Одна функция и на сервере (проверки
     команд), и на клиенте (отрисовка) — иначе плашка и логика разъезжаются.
     known    — смотрящий знаком с целью;
     govSees  — у смотрящего есть допуск к базе и включена настройка. ]]
function NP.NameVisible(mode, known, govSees, isSelf)
    if isSelf then return true end
    if mode == "open" then return true end
    if known then return true end
    if govSees then return true end
    return false
end

-----------------------------------------------------------------------
-- СЕРВЕР
-----------------------------------------------------------------------
if SERVER then
    for _, name in pairs(NP.Net) do util.AddNetworkString(name) end

    local DIR = "grm_identity"
    local FILE = DIR .. "/acquaintance.json"
    local MARKS_FILE = DIR .. "/marks.json"

    NP.Known = NP.Known or {}   -- [viewerKey] = { [targetKey] = timestamp }
    NP.MarksData = NP.MarksData or {}

    local function jsonT(raw)
        local ok, t = pcall(util.JSONToTable, raw or "", false, true)
        return (ok and istable(t)) and t or nil
    end

    local function ensureDir()
        if not file.IsDir(DIR, "DATA") then file.CreateDir(DIR) end
    end

    local dirty, marksDirty = false, false

    --[[ Диск трогаем через общую очередь GRM.Save: знакомство пишется на
         каждое «представился/показал документ», а таких событий в час пик
         десятки. Очередь сводит их в одну запись. ]]
    if GRM.Save and GRM.Save.Register then
        GRM.Save.Register("nameplate.known", { file = FILE, label = "Знакомства над головой",
            delay = 8, build = function()
                ensureDir()
                dirty = false
                return { version = 1, known = NP.Known }
            end })
        GRM.Save.Register("nameplate.marks", { file = MARKS_FILE, label = "Особые приметы",
            delay = 8, build = function()
                ensureDir()
                marksDirty = false
                return { version = 1, marks = NP.MarksData }
            end })
    end

    function NP.Save(force)
        if not (dirty or force) then return false end
        if GRM.Save and GRM.Save.Mark and not force then return GRM.Save.Mark("nameplate.known", "знакомство") end
        ensureDir()
        local ok, raw = pcall(util.TableToJSON, { version = 1, known = NP.Known }, true)
        if not ok or not isstring(raw) then return false end
        file.Write(FILE, raw)
        dirty = false
        return true
    end

    function NP.SaveMarks(force)
        if not (marksDirty or force) then return false end
        if GRM.Save and GRM.Save.Mark and not force then return GRM.Save.Mark("nameplate.marks", "приметы") end
        ensureDir()
        local ok, raw = pcall(util.TableToJSON, { version = 1, marks = NP.MarksData }, true)
        if not ok or not isstring(raw) then return false end
        file.Write(MARKS_FILE, raw)
        marksDirty = false
        return true
    end

    function NP.Load()
        NP.Known, NP.MarksData = {}, {}
        local data = jsonT(file.Read(FILE, "DATA") or "")
        if istable(data) and istable(data.known) then
            for viewer, rows in pairs(data.known) do
                if isstring(viewer) and istable(rows) then
                    local clean = {}
                    for target, ts in pairs(rows) do
                        if isstring(target) then clean[target] = tonumber(ts) or os.time() end
                    end
                    NP.Known[viewer] = clean
                end
            end
        end
        local marks = jsonT(file.Read(MARKS_FILE, "DATA") or "")
        if istable(marks) and istable(marks.marks) then
            for key, text in pairs(marks.marks) do
                if isstring(key) and isstring(text) then NP.MarksData[key] = text end
            end
        end
        return true
    end

    --- Знаком ли смотрящий с целью.
    function NP.Knows(viewerKey, targetKey)
        viewerKey, targetKey = tostring(viewerKey or ""), tostring(targetKey or "")
        if viewerKey == "" or targetKey == "" then return false end
        if viewerKey == targetKey then return true end
        local rows = NP.Known[viewerKey]
        return istable(rows) and rows[targetKey] ~= nil
    end

    local function playerByKey(key)
        for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(ply) and charKeyOf(ply) == key then return ply end
        end
    end

    --- Знакомство. Одностороннее: узнал я — знаю только я.
    function NP.Learn(viewer, target, why)
        local viewerKey, targetKey = charKeyOf(viewer), charKeyOf(target)
        if viewerKey == "" or targetKey == "" or viewerKey == targetKey then return false end
        NP.Known[viewerKey] = NP.Known[viewerKey] or {}
        if NP.Known[viewerKey][targetKey] then return false end
        NP.Known[viewerKey][targetKey] = os.time()
        dirty = true

        local ply = IsValid(viewer) and viewer or playerByKey(viewerKey)
        if IsValid(ply) then
            net.Start(NP.Net.LEARN)
            net.WriteString(targetKey)
            net.Send(ply)
        end
        if GRM.Audit and GRM.Audit.Write then
            GRM.Audit.Write("nameplate", "learn", IsValid(viewer) and viewer or nil,
                { target = targetKey }, { why = tostring(why or "") })
        end
        return true
    end

    function NP.Forget(viewer, target)
        local viewerKey, targetKey = charKeyOf(viewer), charKeyOf(target)
        local rows = NP.Known[viewerKey]
        if not (istable(rows) and rows[targetKey]) then return false end
        rows[targetKey] = nil
        dirty = true
        return true
    end

    function NP.SyncTo(ply)
        if not IsValid(ply) then return end
        local rows = NP.Known[charKeyOf(ply)] or {}
        local list = {}
        for key in pairs(rows) do list[#list + 1] = key end
        net.Start(NP.Net.SYNC)
        net.WriteTable(list)
        net.Send(ply)
    end

    -------------------------------------------------------------------
    -- ПОДПИСЬ «НЕИЗВЕСТНЫЙ»
    -------------------------------------------------------------------
    --- Незнакомец подписан не голым словом: пол берём из паспорта, чтобы
    --  «Неизвестный (муж.)» звучало как описание, а не как заглушка.
    function NP.UnknownLabel(ply)
        local reg = (GRM.Documents and istable(GRM.Documents.Registry)) and GRM.Documents.Registry or nil
        local pass = reg and reg.passports and reg.passports[charKeyOf(ply)] or nil
        local gender = istable(pass) and tostring(pass.gender or "") or ""
        if gender:find("Жен") then return "Неизвестная (жен.)" end
        if gender:find("Муж") then return "Неизвестный (муж.)" end
        return "Неизвестный"
    end

    --- NW-поля, от которых зависит отрисовка: подпись незнакомца и флаг
    --  «этот игрок сам имеет допуск к базе» (для показа номера и имён).
    function NP.Refresh(ply)
        if not (IsValid(ply) and ply:IsPlayer()) then return end
        local label = NP.UnknownLabel(ply)
        if ply:GetNWString("GRM_UnknownLabel", "") ~= label then ply:SetNWString("GRM_UnknownLabel", label) end

        local hasAccess = false
        if GRM.PCBoard and GRM.PCBoard.PlayerLevel then
            local ok, level = pcall(GRM.PCBoard.PlayerLevel, ply)
            if ok and level and level ~= "none" then
                local duty = GRM.FactionDuty and GRM.FactionDuty.IsOnDuty and GRM.FactionDuty.IsOnDuty(ply)
                hasAccess = duty ~= false
            end
        end
        if ply:GetNWBool("GRM_GovAccess", false) ~= hasAccess then ply:SetNWBool("GRM_GovAccess", hasAccess) end
    end

    function NP.RefreshAll()
        for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            NP.Refresh(ply)
        end
    end

    -------------------------------------------------------------------
    -- ОСОБЫЕ ПРИМЕТЫ
    -------------------------------------------------------------------
    function NP.Marks(key) return NP.MarksData[tostring(key or "")] or "" end

    function NP.SetMarks(ply, text)
        local key = charKeyOf(ply)
        if key == "" then return false end
        text = string.Trim(tostring(text or ""))
        text = string.gsub(text, "%s+", " ")
        if GRM.Utf8Sub then text = GRM.Utf8Sub(text, NP.MaxMarks) else text = string.sub(text, 1, NP.MaxMarks) end
        if text == "" then NP.MarksData[key] = nil else NP.MarksData[key] = text end
        marksDirty = true
        NP.SaveMarks()
        return true
    end

    net.Receive(NP.Net.MARKS, function(_, ply)
        if not IsValid(ply) then return end
        ply.GRM_NPMarksNext = ply.GRM_NPMarksNext or 0
        if CurTime() < ply.GRM_NPMarksNext then return end
        ply.GRM_NPMarksNext = CurTime() + 2
        NP.SetMarks(ply, net.ReadString())
        if GRM.Notify then GRM.Notify(ply, "Особые приметы сохранены.", 100, 220, 130)
        else ply:ChatPrint("[Приметы] Сохранено.") end
    end)

    -------------------------------------------------------------------
    -- КОМАНДЫ ЗНАКОМСТВА
    -------------------------------------------------------------------
    local function rpName(ply)
        local name = IsValid(ply) and string.Trim(ply:GetNWString("GRM_RPName", "")) or ""
        if name ~= "" then return name end
        return IsValid(ply) and ply:Nick() or "?"
    end

    local function nearPlayers(ply, radius)
        local out, pos = {}, ply:GetPos()
        for _, other in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(other) and other ~= ply and other:GetPos():DistToSqr(pos) <= radius * radius then
                out[#out + 1] = other
            end
        end
        return out
    end

    local function tell(ply, msg)
        if IsValid(ply) then ply:ChatPrint("[Знакомство] " .. tostring(msg)) end
    end

    --- «Представиться»: все рядом стоящие узнают имя. Маскировка сильнее —
    --  под легендой человек называет легенду, а не себя.
    function NP.Introduce(ply)
        if not IsValid(ply) then return false end
        ply.GRM_NPIntroNext = ply.GRM_NPIntroNext or 0
        if CurTime() < ply.GRM_NPIntroNext then
            tell(ply, "Вы только что представлялись, подождите немного.")
            return false
        end
        ply.GRM_NPIntroNext = CurTime() + 5

        local radius = NP.IntroDist()
        local masked = ply:GetNWBool("IsMasked", false)
        local name = masked and ply:GetNWString("MaskName", "") or rpName(ply)
        if name == "" then name = rpName(ply) end

        local heard = 0
        for _, other in ipairs(nearPlayers(ply, radius)) do
            other:ChatPrint("* " .. name .. " представляется окружающим.")
            -- Под легендой знакомство НЕ записывается: люди запомнили не того.
            if not masked then NP.Learn(other, ply, "introduce") end
            heard = heard + 1
        end
        ply:ChatPrint("* Вы представляетесь окружающим как " .. name .. ".")
        tell(ply, heard > 0 and ("Вас услышали: " .. heard) or "Рядом никого нет.")
        return true
    end

    --- «Показать документ»: имя узнаёт ровно тот, кому показали.
    function NP.ShowDocument(ply)
        if not IsValid(ply) then return false end
        local tr = ply:GetEyeTrace()
        local target = tr.Entity
        if not (IsValid(target) and target:IsPlayer() and target:GetPos():DistToSqr(ply:GetPos()) <= 150 * 150) then
            tell(ply, "Подойдите ближе и наведитесь на человека.")
            return false
        end

        local masked = ply:GetNWBool("IsMasked", false)
        local name = masked and ply:GetNWString("MaskName", "") or rpName(ply)
        local cid = (GRM.Registry and GRM.Registry.CID) and GRM.Registry.CID(ply) or ""

        target:ChatPrint("* " .. name .. " предъявляет вам документ.")
        if masked then
            target:ChatPrint("[Документ] " .. name .. " (документ прикрытия)")
        else
            target:ChatPrint("[Документ] " .. name .. (cid ~= "" and (" · " .. cid) or ""))
            NP.Learn(target, ply, "document")
        end
        ply:ChatPrint("* Вы предъявляете документ игроку " .. rpName(target) .. ".")
        return true
    end

    --- Опознание через государственную базу: сотрудник запоминает лицо.
    hook.Add("GRM_PCBoardIdentified", "GRM_Nameplate_PCBoard", function(actor, targetKey)
        if IsValid(actor) and isstring(targetKey) then NP.Learn(actor, targetKey, "pcboard") end
    end)

    local function command(ply, text)
        local args = string.Explode(" ", string.Trim(tostring(text or "")))
        local cmd = string.lower(args[1] or "")
        if cmd == "/представиться" or cmd == "!представиться" or cmd == "/intro" or cmd == "/introduce" then
            NP.Introduce(ply)
            return true
        end
        if cmd == "/паспорт" or cmd == "!паспорт" or cmd == "/showid" or cmd == "/документ" then
            NP.ShowDocument(ply)
            return true
        end
        if cmd == "/знакомые" or cmd == "/acquaintances" then
            local rows = NP.Known[charKeyOf(ply)] or {}
            local n = 0
            for key in pairs(rows) do
                n = n + 1
                if n <= 20 then
                    local describe = (GRM.Registry and GRM.Registry.Describe) and GRM.Registry.Describe(key) or key
                    ply:ChatPrint("  " .. describe)
                end
            end
            tell(ply, n == 0 and "Вы пока ни с кем не знакомы." or ("Знакомых лиц: " .. n))
            return true
        end
        return false
    end

    hook.Add("PlayerSay", "GRM_Nameplate_Chat", function(ply, text)
        if command(ply, text) then return "" end
    end)
    hook.Add("PlayerSayTransform", "GRM_Nameplate_ChatEC", function(ply, pack)
        if not (istable(pack) and isstring(pack[1])) then return end
        if command(ply, pack[1]) then pack[1] = "" pack.SkipPlayerSay = true end
    end)

    concommand.Add("grm_introduce", function(ply) if IsValid(ply) then NP.Introduce(ply) end end)
    concommand.Add("grm_showid", function(ply) if IsValid(ply) then NP.ShowDocument(ply) end end)

    -------------------------------------------------------------------
    -- СТАРТ
    -------------------------------------------------------------------
    NP.Load()

    hook.Add("PlayerInitialSpawn", "GRM_Nameplate_Join", function(ply)
        timer.Simple(4, function()
            if not IsValid(ply) then return end
            NP.Refresh(ply)
            NP.SyncTo(ply)
        end)
    end)
    hook.Add("GRM_CharacterChanged", "GRM_Nameplate_CharChanged", function(ply)
        timer.Simple(0.5, function()
            if not IsValid(ply) then return end
            NP.Refresh(ply)
            NP.SyncTo(ply)
        end)
    end)
    hook.Add("GRM_FactionDutyChanged", "GRM_Nameplate_Duty", function(ply) NP.Refresh(ply) end)

    -- Обновление раз в 15 секунд: подписи и флаг допуска меняются редко,
    -- держать это в Think или в HUD-цикле незачем.
    timer.Create("GRM_Nameplate_Refresh", 15, 0, function()
        NP.RefreshAll()
        NP.Save()
        NP.SaveMarks()
    end)

    if GRM.Boot and GRM.Boot.OnMapStart then
        GRM.Boot.OnMapStart("GRM_Nameplate_Load", "normal", function()
            NP.Load()
            NP.RefreshAll()
        end, { label = "Шапка над головой: знакомства и приметы" })
    end

    -- При выключении пишем сами и немедленно: очередь до следующего тика
    -- уже не доживёт.
    hook.Add("ShutDown", "GRM_Nameplate_Save", function()
        NP.Save(true)
        NP.SaveMarks(true)
    end)

    print("[GRM Nameplate] server v" .. NP.Version .. " loaded")
end

-----------------------------------------------------------------------
-- КЛИЕНТ
-----------------------------------------------------------------------
if CLIENT then
    local known = {}
    NP.KnownSet = known

    net.Receive(NP.Net.SYNC, function()
        known = {}
        for _, key in ipairs(net.ReadTable() or {}) do
            if isstring(key) then known[key] = true end
        end
        NP.KnownSet = known
    end)
    net.Receive(NP.Net.LEARN, function()
        local key = net.ReadString()
        if isstring(key) and key ~= "" then known[key] = true end
    end)

    local cvEnable = CreateClientConVar("grm_cl_nameplate", "1", true, false,
        "Показывать шапку над головами")

    --[[ Флаг для СТАРЫХ отрисовок: пока он поднят, `sh_grm_rpdesc.lua` и
         `Factions_HUD` не рисуют ничего. Выключил новую шапку конваром —
         старые вернулись, поведение не теряется. ]]
    NP.Active = cvEnable:GetBool()
    cvars.AddChangeCallback("grm_cl_nameplate", function(_, _, value)
        NP.Active = tostring(value) ~= "0"
    end, "GRM_Nameplate_ActiveFlag")
    local cvDist = CreateClientConVar("grm_cl_nameplate_dist", "200", true, false,
        "Радиус отрисовки шапки над головой")
    local cvDesc = CreateClientConVar("grm_cl_nameplate_desc", "1", true, false,
        "Показывать описание внешности под именем")

    surface.CreateFont("GRM_NP_Name", { font = "Roboto", size = 19, weight = 800, antialias = true, extended = true })
    surface.CreateFont("GRM_NP_Tag",  { font = "Roboto", size = 16, weight = 700, antialias = true, extended = true })
    surface.CreateFont("GRM_NP_Desc", { font = "Roboto", size = 15, weight = 500, antialias = true, extended = true })

    local COL = {
        name    = Color(255, 226, 140),
        unknown = Color(190, 196, 208),
        desc    = Color(228, 234, 244),
        box     = Color(10, 14, 20, 200),
        border  = Color(70, 150, 240, 180),
        cid     = Color(150, 200, 255),
    }

    -- Перенос строк описания кэшируется: surface.GetTextSize на каждое слово
    -- каждый кадр — это ровно та работа, ради которой два HUD и объединяли.
    local wrapCache, wrapSeq = {}, 0
    local function wrapText(text, maxWidth, font, maxLines)
        local cacheKey = font .. ":" .. maxWidth .. ":" .. text
        local hit = wrapCache[cacheKey]
        if hit then return hit end
        local lines, current = {}, ""
        surface.SetFont(font)
        for word in string.gmatch(text, "%S+") do
            local test = (current == "") and word or (current .. " " .. word)
            if (surface.GetTextSize(test) or 0) <= maxWidth then
                current = test
            else
                if current ~= "" then lines[#lines + 1] = current end
                current = word
                if #lines >= maxLines then break end
            end
        end
        if current ~= "" and #lines < maxLines then lines[#lines + 1] = current end
        wrapSeq = wrapSeq + 1
        if wrapSeq > 256 then wrapCache, wrapSeq = { [cacheKey] = lines }, 0 else wrapCache[cacheKey] = lines end
        return lines
    end

    -- Ключ персонажа — канон ядра (§5.2.6). Локальная копия убрана: та же копия ещё раз, на клиенте.
    local charKeyClient = GRM.CharKey

    local function factionColor(name)
        local data = FactionsData or {}
        local row = data[name]
        local col = istable(row) and row.Color or nil
        if istable(col) then
            return Color(tonumber(col.r) or 255, tonumber(col.g) or 200, tonumber(col.b) or 50)
        end
        return Color(235, 200, 90)
    end

    --- Всё, что нужно нарисовать над конкретным игроком. Вынесено из цикла
    --  отрисовки: логику видимости проверяет стенд, а не глаз.
    function NP.Describe(ply, lp)
        if not (IsValid(ply) and IsValid(lp)) then return nil end
        local isSelf = ply == lp
        local mode = NP.Mode()
        local masked = ply:GetNWBool("IsMasked", false)
        local key = charKeyClient(ply)

        local govSees = NP.GovNames() and lp:GetNWBool("GRM_GovAccess", false)
        local isKnown = known[key] == true
        local visible = NP.NameVisible(mode, isKnown, govSees, isSelf)

        local out = { self = isSelf, known = isKnown, masked = masked }

        if masked then
            -- Легенда сильнее знакомства: люди видят прикрытие, а не человека.
            local maskName = string.Trim(ply:GetNWString("MaskName", ""))
            out.name = maskName ~= "" and maskName or (ply:GetNWString("GRM_UnknownLabel", "") ~= "" and
                ply:GetNWString("GRM_UnknownLabel", "") or "Неизвестный")
            out.nameKnown = false
        elseif visible then
            local rp = string.Trim(ply:GetNWString("GRM_RPName", ""))
            out.name = rp ~= "" and rp or ply:Nick()
            out.nameKnown = true
        else
            local label = string.Trim(ply:GetNWString("GRM_UnknownLabel", ""))
            out.name = label ~= "" and label or "Неизвестный"
            out.nameKnown = false
        end

        -- Номер гражданина: никогда / только госслужащему на службе / всем.
        local cidMode = NP.CidMode()
        local cid = string.Trim(ply:GetNWString("GRM_CID", ""))
        if cid ~= "" and out.nameKnown and not masked then
            if cidMode == "all" or isSelf then out.cid = cid
            elseif cidMode == "gov" and lp:GetNWBool("GRM_GovAccess", false) then out.cid = cid end
        end

        -- Тег организации и должность — только когда человек НА СЛУЖБЕ.
        if ply:GetNWBool("GRM_FactionOnDuty", false) and not masked then
            local tag = string.Trim(ply:GetNWString("GRM_ChannelTag", ""))
            local role = string.Trim(ply:GetNWString("GRM_Role", ""))
            local faction = string.Trim(ply:GetNWString("GRM_FactionDisplay", ply:GetNWString("GRM_Faction", "")))
            local line = ""
            if tag ~= "" then line = "[" .. tag .. "]" elseif faction ~= "" then line = faction end
            if role ~= "" then line = (line ~= "" and (line .. " ") or "") .. role end
            if line ~= "" then
                out.tag = line
                out.tagColor = factionColor(faction)
            end
        end

        if cvDesc:GetBool() then
            local desc = masked and string.Trim(ply:GetNWString("GRM_MaskDesc", ""))
                or ((GRM.RPDesc and GRM.RPDesc.Get) and GRM.RPDesc.Get(ply) or "")
            if desc ~= "" then out.desc = desc end
        end

        if not ply:Alive() then
            out.name = "Тело"
            out.tag = nil
            out.cid = nil
        end

        -- Другие модули могут заменить содержимое плашки (например, бан на
        -- сервере рисует «ЗАБАНЕН»). Отрисовка при этом остаётся одна.
        local override = hook.Run("GRM_NameplateOverride", ply, out)
        if istable(override) then out = override end
        return out
    end

    local PAD, MAXW = 8, 300

    local function drawPlate(info, sx, sy, alpha)
        surface.SetFont("GRM_NP_Name")
        local nameW, nameH = surface.GetTextSize(info.name)
        local cidW = 0
        if info.cid then
            surface.SetFont("GRM_NP_Tag")
            cidW = (surface.GetTextSize("  " .. info.cid) or 0)
        end
        local tagW, tagH = 0, 0
        if info.tag then
            surface.SetFont("GRM_NP_Tag")
            tagW, tagH = surface.GetTextSize(info.tag)
        end
        local lines = info.desc and wrapText(info.desc, MAXW, "GRM_NP_Desc", 3) or nil
        local descH, descW = 0, 0
        if lines and #lines > 0 then
            surface.SetFont("GRM_NP_Desc")
            local _, lineH = surface.GetTextSize("A")
            descH = #lines * (lineH + 2)
            for _, line in ipairs(lines) do
                local w = surface.GetTextSize(line) or 0
                if w > descW then descW = w end
            end
        end

        local boxW = math.max(nameW + cidW, tagW, descW) + PAD * 2
        local boxH = nameH + (info.tag and (tagH + 2) or 0) + (descH > 0 and (descH + 4) or 0) + PAD * 2
        local bx, by = sx - boxW * 0.5, sy - boxH

        draw.RoundedBox(6, bx, by, boxW, boxH, Color(COL.box.r, COL.box.g, COL.box.b, alpha * 0.78))
        surface.SetDrawColor(COL.border.r, COL.border.g, COL.border.b, alpha * 0.55)
        surface.DrawOutlinedRect(bx, by, boxW, boxH, 1)

        local y = by + PAD
        local nameColor = info.nameKnown and COL.name or COL.unknown
        draw.SimpleText(info.name, "GRM_NP_Name", sx - cidW * 0.5, y,
            Color(nameColor.r, nameColor.g, nameColor.b, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        if info.cid then
            draw.SimpleText(info.cid, "GRM_NP_Tag", sx + (nameW * 0.5) - cidW * 0.5 + 6, y + 3,
                Color(COL.cid.r, COL.cid.g, COL.cid.b, alpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end
        y = y + nameH

        if info.tag then
            local col = info.tagColor or COL.name
            draw.SimpleText(info.tag, "GRM_NP_Tag", sx, y + 2, Color(col.r, col.g, col.b, alpha),
                TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            y = y + tagH + 2
        end

        if lines and #lines > 0 then
            surface.SetFont("GRM_NP_Desc")
            local _, lineH = surface.GetTextSize("A")
            for i, line in ipairs(lines) do
                draw.SimpleText(line, "GRM_NP_Desc", sx, y + 4 + (i - 1) * (lineH + 2),
                    Color(COL.desc.r, COL.desc.g, COL.desc.b, alpha * 0.92), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            end
        end
    end

    hook.Add("HUDPaint", "GRM_Nameplate", function()
        if not cvEnable:GetBool() then return end
        local lp = LocalPlayer()
        if not IsValid(lp) then return end

        local maxDist = math.Clamp(cvDist:GetFloat(), 50, 1000)
        for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(ply) and ply ~= lp then
                local dist = lp:GetPos():Distance(ply:GetPos())
                if dist <= maxDist then
                    local info = NP.Describe(ply, lp)
                    if info then
                        -- В транспорте кости игрока сидят низко: плашка
                        -- уезжала в кузов. Берём высоту от самой машины.
                        local anchor, height = ply, 84
                        local veh = ply.GetVehicle and ply:GetVehicle() or nil
                        if IsValid(veh) then
                            anchor = veh
                            height = math.max(60, (veh:OBBMaxs().z - veh:OBBMins().z) + 20)
                        end
                        local screen = (anchor:GetPos() + Vector(0, 0, height)):ToScreen()
                        if screen.visible then
                            drawPlate(info, screen.x, screen.y, math.Clamp(255 * (1.15 - dist / maxDist), 60, 255))
                        end
                    end
                end
            end
        end
    end)

    --[[ Старые шапки убираются здесь, а не правкой чужих файлов: оба модуля
         регистрируют свои HUDPaint при загрузке, а `sh_grm_rpdesc.lua`
         грузится ПОСЛЕ нас (алфавит autorun). Поэтому снимаем хуки после
         полной загрузки и подстраховываемся вторым проходом. ]]
    local function dropLegacyHUD()
        hook.Remove("HUDPaint", "Factions_HUD")
        hook.Remove("HUDPaint", "GRM_RPDesc")
        hook.Remove("HUDPaint", "RPDesc")
        hook.Remove("HUDPaint", "GRM_RPDesc_v2")
    end
    hook.Add("InitPostEntity", "GRM_Nameplate_DropLegacy", function()
        dropLegacyHUD()
        timer.Simple(1, dropLegacyHUD)
        timer.Simple(5, dropLegacyHUD)
    end)
    timer.Simple(1, dropLegacyHUD)
    timer.Simple(10, dropLegacyHUD)

    -------------------------------------------------------------------
    -- РЕДАКТОР ОСОБЫХ ПРИМЕТ
    -------------------------------------------------------------------
    function NP.OpenMarksEditor()
        if IsValid(NP._marksFrame) then NP._marksFrame:Remove() end
        local frame = vgui.Create("DFrame")
        NP._marksFrame = frame
        frame:SetSize(520, 320)
        frame:Center()
        frame:SetTitle("")
        frame:MakePopup()
        frame.Paint = function(_, w, h)
            draw.RoundedBox(8, 0, 0, w, h, Color(20, 25, 34, 250))
            draw.RoundedBox(8, 0, 0, w, 56, Color(32, 40, 53, 245))
            draw.SimpleText("ОСОБЫЕ ПРИМЕТЫ", "GRM_NP_Name", 16, 10, Color(226, 184, 92))
            draw.SimpleText("Видно при осмотре и в справке /pcboard — над головой приметы не показываются.",
                "GRM_NP_Desc", 16, 32, Color(160, 172, 190))
        end

        local entry = vgui.Create("DTextEntry", frame)
        entry:Dock(FILL)
        entry:DockMargin(12, 64, 12, 8)
        entry:SetMultiline(true)
        entry:SetFont("GRM_NP_Desc")
        entry:SetPlaceholderText("Шрам через левую бровь, хромает, татуировка на кисти…")
        entry:SetText(NP.MyMarks or "")

        local save = vgui.Create("DButton", frame)
        save:Dock(BOTTOM)
        save:SetTall(34)
        save:DockMargin(12, 0, 12, 12)
        save:SetText("")
        save.Paint = function(self, w, h)
            draw.RoundedBox(6, 0, 0, w, h, self:IsHovered() and Color(110, 215, 145) or Color(92, 200, 130))
            draw.SimpleText("Сохранить", "GRM_NP_Desc", w * 0.5, h * 0.5, Color(20, 25, 34),
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        save.DoClick = function()
            local text = entry:GetValue() or ""
            NP.MyMarks = text
            net.Start(NP.Net.MARKS)
            net.WriteString(text)
            net.SendToServer()
            frame:Close()
        end
    end
    concommand.Add("grm_marks", function() NP.OpenMarksEditor() end)

    hook.Add("OnPlayerChat", "GRM_Nameplate_ChatCl", function(ply, text)
        if ply ~= LocalPlayer() then return end
        local msg = string.lower(string.Trim(tostring(text or "")))
        if msg == "/приметы" or msg == "!приметы" or msg == "/marks" then
            NP.OpenMarksEditor()
            return true
        end
    end)

    --[[ Диагностика: одной командой видно, кто рисует над головами. Нужна
         именно потому, что «две плашки сразу» — это чужой HUDPaint, и без
         списка хуков это гадание. ]]
    concommand.Add("grm_nameplate_debug", function()
        local legacy = {}
        for name in pairs(hook.GetTable()["HUDPaint"] or {}) do
            if isstring(name) and (name:find("RPDesc") or name == "Factions_HUD") then
                legacy[#legacy + 1] = name
            end
        end
        local n = 0
        for _ in pairs(known) do n = n + 1 end
        print("[GRM Nameplate] активна: " .. tostring(NP.Active) ..
            " · режим: " .. NP.Mode() .. " · номер: " .. NP.CidMode() ..
            " · имена госслужащим: " .. tostring(NP.GovNames()))
        print("[GRM Nameplate] знакомых лиц: " .. n ..
            " · радиус: " .. cvDist:GetFloat() .. " · описание: " .. tostring(cvDesc:GetBool()))
        print("[GRM Nameplate] старые отрисовки в HUDPaint: " ..
            (#legacy > 0 and table.concat(legacy, ", ") .. " (молчат, пока активна новая)" or "нет"))
    end)

    print("[GRM Nameplate] client v" .. NP.Version .. " loaded")
end
