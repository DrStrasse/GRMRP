--[[--------------------------------------------------------------------
    GRM RPDesc v2.1.0 (Код 71) — Описания + игровые (RP) имена над головами
    v2.1.0: над головой дополнительно рисуется ИГРОВОЕ имя персонажа
      (NWString GRM_RPName из Кода 72) — всем игрокам, включая себя
      (от первого и от третьего лица), над блоком описания; общая
      дистанция отрисовки (grm_cl_rpdesc_dist).
    Освежение присланного владельцем модуля RPDesc:
      - Деманглирование web-вставки (HTML-сущности, markdown-ссылки);
      - Хранение на сервере (rpdescs.json — формат СОВМЕСТИМ со старым);
      - Синхронизация между всеми игроками;
      - Отображение над головами ВСЕХ игроков (включая себя) ВСЕГДА;
      - Дистанция отрисовки настраивается (grm_cl_rpdesc_dist, стандарт 200);
      - Лимит длины описания (420 симв.), перенос строк, плавное затухание;
      - Шрифт Roboto с кириллицей, аккуратная плашка с рамкой;
      - Клиентский выключатель grm_cl_rpdesc (0/1) — управляется из F4-меню;
      - API: GRM.RPDesc.Get(ply) / GetRaw(steamID) — для F4 и шапки профиля;
      - Команда /rpdesc (PlayerSayTransform) + concommand grm_rpdesc.
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.RPDesc = GRM.RPDesc or {}
local RD = GRM.RPDesc

RD.MaxLength   = 420    -- жёсткий лимит символов на сервере
RD.DrawDist    = 200    -- стандартный радиус отрисовки (юниты)
RD.MaxLines    = 7      -- максимум строк над головой
RD.Version     = "2.1.0"

local DESC_FILE = "rpdescs.json"

local function identityKey(value)
    if IsValid(value) and value:IsPlayer() then
        if GRM.Identity and GRM.Identity.CharacterKey then return GRM.Identity.CharacterKey(value) end
        return tostring(value:SteamID64() or "") .. ":char1"
    end
    local raw = tostring(value or "")
    if raw:match(":char[1-3]$") then return raw end
    if raw:match("^%d+$") then return raw .. ":char1" end
    if util and util.SteamIDTo64 then
        local s64 = util.SteamIDTo64(raw)
        if s64 and s64 ~= "0" then return tostring(s64) .. ":char1" end
    end
    return raw
end

local function sanitizeDesc(s)
    s = string.Trim(tostring(s or ""))
    -- убираем управляющие символы, схлопываем множественные пробелы
    s = string.gsub(s, "[%c]", function(c)
        if c == "\n" or c == "\r" then return " " end
        return ""
    end)
    s = string.gsub(s, "%s+", " ")
    if #s > RD.MaxLength then s = string.sub(s, 1, RD.MaxLength) end
    return s
end

-- ============================================================
-- СЕРВЕРНАЯ ЧАСТЬ
-- ============================================================
if SERVER then
    util.AddNetworkString("RPDesc_RequestSync")
    util.AddNetworkString("RPDesc_UpdateFromClient")
    util.AddNetworkString("RPDesc_Sync")
    util.AddNetworkString("RPDesc_Update")

    local function loadDescs()
        if not file.Exists(DESC_FILE, "DATA") then return {} end
        local data = file.Read(DESC_FILE, "DATA")
        if not data or data == "" then return {} end
        local ok, tbl = pcall(util.JSONToTable, data)
        if ok and istable(tbl) then return tbl end
        return {}
    end

    local function saveDescs(tbl)
        local ok, txt = pcall(util.TableToJSON, tbl, true)
        if ok and txt then file.Write(DESC_FILE, txt) end
    end

    RPDesc_Descriptions = RPDesc_Descriptions or loadDescs()
    do
        local moved = {}
        for key, desc in pairs(RPDesc_Descriptions) do
            local ck = identityKey(key)
            if ck ~= key and moved[ck] == nil then moved[ck] = desc RPDesc_Descriptions[key] = nil end
        end
        for key, desc in pairs(moved) do RPDesc_Descriptions[key] = desc end
        if next(moved) ~= nil then saveDescs(RPDesc_Descriptions) end
    end

    local function sendAllDescs(ply)
        net.Start("RPDesc_Sync")
            net.WriteTable(RPDesc_Descriptions)
        net.Send(ply)
    end

    local function broadcastUpdate(steamid, desc)
        net.Start("RPDesc_Update")
            net.WriteString(steamid)
            net.WriteString(desc or "")
        net.Broadcast()
    end

    net.Receive("RPDesc_RequestSync", function(_, ply)
        if IsValid(ply) then sendAllDescs(ply) end
    end)

    -- анти-флуд: не чаще раза в 2 секунды
    local nextAllowed = {}
    net.Receive("RPDesc_UpdateFromClient", function(_, ply)
        if not IsValid(ply) then return end
        local now = CurTime()
        if (nextAllowed[ply] or 0) > now then return end
        nextAllowed[ply] = now + 2

        local steamid = identityKey(ply)
        local desc = sanitizeDesc(net.ReadString())

        if desc ~= "" then
            RPDesc_Descriptions[steamid] = desc
        else
            RPDesc_Descriptions[steamid] = nil
        end
        saveDescs(RPDesc_Descriptions)
        broadcastUpdate(steamid, desc)
    end)

    hook.Add("PlayerInitialSpawn", "RPDesc_Sync", function(ply)
        timer.Simple(1, function()
            if IsValid(ply) then sendAllDescs(ply) end
        end)
    end)

    --[[ Установить описание за игрока (меню персонажа): описание живёт у
         персонажа, поэтому его выставляет ядро персонажей при выборе слота
         и при сохранении. ]]
    function RD.SetFor(ply, desc)
        if not IsValid(ply) then return false end
        local key = identityKey(ply)
        local clean = sanitizeDesc(tostring(desc or ""))
        if clean ~= "" then RPDesc_Descriptions[key] = clean else RPDesc_Descriptions[key] = nil end
        saveDescs(RPDesc_Descriptions)
        broadcastUpdate(key, clean)
        return true
    end

    -- API для серверных модулей (F4, профиль)
    function RD.GetRaw(steamID)
        return RPDesc_Descriptions[tostring(steamID or "")] or ""
    end

    print("[GRM RPDesc] Сервер v" .. RD.Version .. " загружен")
end

-- ============================================================
-- КЛИЕНТСКАЯ ЧАСТЬ
-- ============================================================
if CLIENT then
    local TAG = "GRM_RPDesc_Client"
    local descriptions = {}

    CreateClientConVar("grm_cl_rpdesc", "1", true, false)
    CreateClientConVar("grm_cl_rpdesc_dist", tostring(RD.DrawDist), true, false)

    surface.CreateFont("GRM_RPDesc_Font", {
        font = "Roboto", size = 15, weight = 500,
        antialias = true, extended = true,
    })
    surface.CreateFont("GRM_RPDesc_TitleF", { font = "Roboto", size = 18, weight = 800, extended = true })
    surface.CreateFont("GRM_RPName_Font",   { font = "Roboto", size = 19, weight = 800, antialias = true, extended = true })

    -- запрос синхронизации при старте и подключении
    net.Start("RPDesc_RequestSync") net.SendToServer()
    hook.Add("InitPostEntity", TAG, function()
        net.Start("RPDesc_RequestSync") net.SendToServer()
    end)

    net.Receive("RPDesc_Sync", function()
        descriptions = net.ReadTable() or {}
    end)

    net.Receive("RPDesc_Update", function()
        local steamid = net.ReadString()
        local desc = net.ReadString()
        if desc and desc ~= "" then
            descriptions[steamid] = desc
        else
            descriptions[steamid] = nil
        end
    end)

    local function getMySteamID()
        local ply = LocalPlayer()
        return IsValid(ply) and identityKey(ply) or ""
    end

    -- API
    function RD.Get(ply)
        if not IsValid(ply) then return "" end
        return descriptions[identityKey(ply)] or ""
    end
    function RD.GetRaw(steamID)
        return descriptions[tostring(steamID or "")] or ""
    end

    local function setMyDesc(desc)
        desc = sanitizeDesc(desc)
        net.Start("RPDesc_UpdateFromClient")
            net.WriteString(desc or "")
        net.SendToServer()
        local sid = getMySteamID()
        if sid == "" then return end
        if desc ~= "" then descriptions[sid] = desc else descriptions[sid] = nil end
    end

    -----------------------------------------------------------
    -- Окно редактирования
    -----------------------------------------------------------
    local C = {
        bg    = Color(20, 24, 32, 250),
        head  = Color(28, 34, 46, 255),
        panel = Color(32, 38, 50, 245),
        acc   = Color(70, 150, 240),
        green = Color(60, 190, 110),
        red   = Color(220, 75, 70),
        text  = Color(240, 245, 250),
        dim   = Color(160, 170, 185),
    }

    function RD.OpenEditor()
        if IsValid(RD._frame) then RD._frame:Remove() end

        local f = vgui.Create("DFrame")
        RD._frame = f
        f:SetTitle("")
        f:SetSize(480, 380)
        f:Center()
        f:MakePopup()
        f:ShowCloseButton(false)
        f.Paint = function(_, pw, ph)
            draw.RoundedBox(8, 0, 0, pw, ph, C.bg)
            draw.RoundedBoxEx(8, 0, 0, pw, 38, C.head, true, true, false, false)
            draw.SimpleText("Моё описание персонажа (RPDesc)", "GRM_RPDesc_TitleF", 14, 19, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end

        local x = vgui.Create("DButton", f)
        x:SetText("X") x:SetFont("GRM_RPDesc_TitleF") x:SetTextColor(color_white)
        x:SetPos(436, 6) x:SetSize(32, 26)
        x.DoClick = function() f:Close() end
        x.Paint = function(self, pw, ph) draw.RoundedBox(4, 0, 0, pw, ph, self:IsHovered() and C.red or Color(45, 52, 68)) end

        local entry = vgui.Create("DTextEntry", f)
        entry:Dock(FILL) entry:DockMargin(10, 46, 10, 6)
        entry:SetMultiline(true)
        entry:SetVerticalScrollbarEnabled(true)
        entry:SetFont("GRM_RPDesc_Font")
        entry:SetText(descriptions[getMySteamID()] or "")
        entry:SetPlaceholderText("Опишите персонажа: внешность, приметы, характер...")

        local counter = vgui.Create("DLabel", f)
        counter:Dock(BOTTOM) counter:SetTall(18) counter:DockMargin(12, 0, 12, 0)
        counter:SetTextColor(C.dim) counter:SetFont("GRM_RPDesc_Font")
        local function updCounter()
            local n = string.len(entry:GetValue() or "")
            counter:SetText("Символов: " .. n .. " / " .. RD.MaxLength)
        end
        entry.OnChange = updCounter
        updCounter()

        local bot = vgui.Create("DPanel", f)
        bot:Dock(BOTTOM) bot:SetTall(42) bot:SetPaintBackground(false)

        local function mkBtn(txt, col, dockSide, w, fn)
            local b = vgui.Create("DButton", bot)
            b:Dock(dockSide) b:SetWide(w or 110) b:DockMargin(10, 6, 0, 8)
            b:SetText(txt) b:SetFont("GRM_RPDesc_Font") b:SetTextColor(color_white)
            b.Paint = function(self, pw, ph)
                local cc = col
                if self:IsHovered() then cc = Color(math.min(255, cc.r + 25), math.min(255, cc.g + 25), math.min(255, cc.b + 25)) end
                draw.RoundedBox(6, 0, 0, pw, ph, cc)
            end
            b.DoClick = fn
            return b
        end

        mkBtn("Сохранить", C.green, LEFT, 130, function()
            local v = entry:GetValue() or ""
            if string.len(v) > RD.MaxLength then v = string.sub(v, 1, RD.MaxLength) end
            setMyDesc(v)
            notification.AddLegacy("Описание сохранено", NOTIFY_GENERIC, 3)
            f:Close()
        end)
        mkBtn("Удалить", C.red, LEFT, 110, function()
            setMyDesc("")
            notification.AddLegacy("Описание удалено", NOTIFY_UNDO, 3)
            f:Close()
        end)
        mkBtn("Закрыть", C.acc, RIGHT, 110, function() f:Close() end)
    end

    -- команда /rpdesc (контракт проекта — PlayerSayTransform)
    hook.Add("PlayerSayTransform", TAG, function(ply, datapack)
        if ply ~= LocalPlayer() then return end
        local msg = datapack and datapack[1]
        if not msg then return end
        local lower = string.lower(msg)
        if lower == "/rpdesc" or lower == "!rpdesc" then
            RD.OpenEditor()
            datapack[1] = ""
        end
    end)
    concommand.Add("grm_rpdesc", RD.OpenEditor)

    -----------------------------------------------------------
    -- Отрисовка над головами (плавное затухание по дистанции)
    -----------------------------------------------------------
    -- Кэш переноса строк: wrapText вызывался КАЖДЫЙ кадр для каждого ближнего
    -- игрока с описанием и делал surface.GetTextSize на каждое слово (дёшево
    -- по одному, дорого на 60 FPS × N игроков). Результат по (текст, ширина)
    -- стабилен — кэшируем с ограниченным размером.
    local wrapCache = {}
    local wrapCacheSeq = 0
    local function wrapText(text, maxWidth)
        local key = maxWidth .. ":" .. text
        local hit = wrapCache[key]
        if hit then return hit end
        local lines, current = {}, ""
        surface.SetFont("GRM_RPDesc_Font")
        for word in string.gmatch(text, "%S+") do
            local test = (current == "") and word or (current .. " " .. word)
            if (surface.GetTextSize(test) or 0) <= maxWidth then
                current = test
            else
                if current ~= "" then lines[#lines + 1] = current end
                current = word
                if #lines >= RD.MaxLines then break end
            end
        end
        if current ~= "" and #lines < RD.MaxLines then lines[#lines + 1] = current
        elseif #lines == RD.MaxLines then
            lines[#lines] = string.sub(lines[#lines], 1, -2) .. "…"
        end
        -- Ограничиваем кэш, чтобы не расти бесконечно (игроки меняют описания).
        wrapCacheSeq = wrapCacheSeq + 1
        if wrapCacheSeq > 256 then
            wrapCache = { [key] = lines }
            wrapCacheSeq = 0
        else
            wrapCache[key] = lines
        end
        return lines
    end

    -- Плашки каждого игрока пересобираются каждый кадр, а альфа у них
    -- дистанционная: позиция и цвета — скретч-объекты с записью полей
    -- строго перед немедленным потреблением (§6.1.8)
    local RD_POS = Vector(0, 0, 0)
    local RD_C = Color(0, 0, 0, 255)
    local function rdCol(r, g, b, a)
        RD_C.r = r
        RD_C.g = g
        RD_C.b = b
        RD_C.a = a
        return RD_C
    end

    hook.Add("HUDPaint", TAG, function()
        --[[ 21.08. Единая шапка (GRM.Nameplate) рисует имя, тег и описание
             одной плашкой. Снятия хука по имени оказалось мало: файл
             грузится ПОСЛЕ модуля шапки и вешал свой HUDPaint заново — над
             головой было две плашки сразу. Теперь старая отрисовка сама
             молчит, пока новая включена. ]]
        if GRM.Nameplate and GRM.Nameplate.Active then return end
        if GetConVar("grm_cl_rpdesc"):GetInt() == 0 then return end
        local lp = LocalPlayer()
        if not IsValid(lp) or not lp:Alive() then return end

        local maxDist = math.Clamp(GetConVar("grm_cl_rpdesc_dist"):GetFloat(), 50, 1000)
        local maxWidth, pad = 300, 6
        surface.SetFont("GRM_RPDesc_Font")
        local _, lineH = surface.GetTextSize("A")
        surface.SetFont("GRM_RPName_Font")
        local _, nameH = surface.GetTextSize("A")

        for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(ply) and ply:Alive() then
                local masked = ply:GetNWBool("IsMasked", false)
                local rname = masked and "" or string.Trim(tostring(ply:GetNWString("GRM_RPName", "") or ""))
                local desc = masked and string.Trim(ply:GetNWString("GRM_MaskDesc", "")) or (descriptions[identityKey(ply)] or "")
                if rname ~= "" or desc ~= "" then
                    local isSelf = (ply == lp)
                    local alpha = 255
                    local d = lp:GetPos():Distance(ply:GetPos())
                    if isSelf or d <= maxDist then
                        if isSelf then
                            alpha = 200 -- себя рисуем даже в third-person
                        else
                            alpha = math.Clamp(255 * (1.15 - d / maxDist), 60, 255)
                        end
                        local gp = ply:GetPos()
                        local pos = RD_POS
                        pos.x = gp.x
                        pos.y = gp.y
                        pos.z = gp.z + 80
                        local sp = pos:ToScreen()
                            if sp.visible then
                                local topY = sp.y -- верх всего блока; имя уедет ещё выше

                                -- описание (нижний блок, ближе к голове)
                                if desc ~= "" then
                                    local lines = wrapText(desc, maxWidth)
                                    if #lines > 0 then
                                        surface.SetFont("GRM_RPDesc_Font")
                                        local boxW = 0
                                        for _, ln in ipairs(lines) do
                                            local w = surface.GetTextSize(ln) or 0
                                            if w > boxW then boxW = w end
                                        end
                                        boxW = boxW + pad * 2
                                        local boxH = #lines * (lineH + 2) + pad * 2

                                        local bx, by = sp.x - boxW / 2, sp.y - boxH
                                        draw.RoundedBox(6, bx, by, boxW, boxH, rdCol(10, 14, 20, alpha * 0.78))
                                        surface.SetDrawColor(70, 150, 240, alpha * 0.7)
                                        surface.DrawOutlinedRect(bx, by, boxW, boxH, 1)

                                        for i, ln in ipairs(lines) do
                                            draw.SimpleText(ln, "GRM_RPDesc_Font", sp.x, by + pad + (i - 1) * (lineH + 2), rdCol(235, 240, 248, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
                                        end
                                        topY = by
                                    end
                                end

                                -- игровое (RP) имя — самый верхний блок, золотая плашка
                                if rname ~= "" then
                                    surface.SetFont("GRM_RPName_Font")
                                    local nw = surface.GetTextSize(rname) or 0
                                    local nbW, nbH = nw + 22, nameH + 8
                                    local nx, ny = sp.x - nbW / 2, topY - nbH - 4
                                    draw.RoundedBox(6, nx, ny, nbW, nbH, rdCol(12, 16, 24, alpha * 0.85))
                                    surface.SetDrawColor(230, 190, 80, alpha * 0.85)
                                    surface.DrawOutlinedRect(nx, ny, nbW, nbH, 1)
                                    draw.SimpleText(rname, "GRM_RPName_Font", sp.x, ny + 4, rdCol(255, 226, 140, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
                                end
                            end
                        end
                    end
                end
            end
        end)

    print("[GRM RPDesc] Клиент v" .. RD.Version .. " загружен")
end
