--[[--------------------------------------------------------------------
    GRM RP Chat v1.2.0 (Код 62; команды других модулей не перехватываются)
    /me /do /it /try /roll /w /y /looc /ooc + локальный чат по радиусу.

    Работает с EasyChat (PlayerSay на сервере) и без него.
    Конфиг: GRM.Chat.Config (sh_grm_chat_config.lua).
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Chat = GRM.Chat or {}
local C = GRM.Chat
C.Config = C.Config or {}

local NET_MSG = "GRM_RPChat_Msg"

local function cfg()
    return C.Config or {}
end

local function col(name, fallback)
    local colors = cfg().Colors or {}
    return colors[name] or fallback or Color(255, 255, 255)
end

local function radiusSqr(key, default)
    local r = tonumber(cfg()[key]) or default or 355
    return r * r
end

-- ============================================================
-- SERVER
-- ============================================================
if SERVER then
    util.AddNetworkString(NET_MSG)

    -- Синглтон
    if GRM._rpChatActive then
        print("[GRM RPChat] duplicate load skipped")
        return
    end
    GRM._rpChatActive = true
    GRM._rpChatVer = "1.2.1" -- (print ниже врал про 1.2.0 при поле 1.1.0 — мелочь, сведена)

    local function sendTo(ply, parts)
        -- parts = { Color, "text", Color, "text", ... }
        -- Вечер-13: рукав EasyChat вырезан (чат вынесен в GRM-системы;
        -- указание владельца). Собственный net-канал — единственный путь.
        if not IsValid(ply) then return end
        net.Start(NET_MSG)
            net.WriteUInt(#parts, 8)
            for i = 1, #parts do
                local v = parts[i]
                if IsColor(v) or (istable(v) and v.r and v.g and v.b) then
                    net.WriteBool(true)
                    net.WriteUInt(v.r or 255, 8)
                    net.WriteUInt(v.g or 255, 8)
                    net.WriteUInt(v.b or 255, 8)
                else
                    net.WriteBool(false)
                    net.WriteString(tostring(v or ""))
                end
            end
        net.Send(ply)
    end

    local function broadcastNear(originPly, maxDistSqr, parts, includeSelf)
        if not IsValid(originPly) then return 0 end
        local origin = originPly:GetPos()
        local others = 0
        for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(ply) then
                if ply == originPly then
                    if includeSelf ~= false then sendTo(ply, parts) end
                elseif origin:DistToSqr(ply:GetPos()) <= maxDistSqr then
                    sendTo(ply, parts)
                    others = others + 1
                end
            end
        end
        return others
    end

    local function broadcastAll(parts, filterFn)
        for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(ply) and (not filterFn or filterFn(ply)) then
                sendTo(ply, parts)
            end
        end
    end

    local function nick(ply)
        return IsValid(ply) and ply:Nick() or "?"
    end

    -- ── handlers return true if consumed ────────────────────
    local handlers = {}

    handlers["/me"] = function(ply, args)
        local text = table.concat(args, " ", 2)
        if text == "" then return true end
        local parts = {
            col("me", Color(200, 160, 255)),
            "* " .. nick(ply) .. " " .. text,
        }
        broadcastNear(ply, radiusSqr("LocalRadius", 355), parts)
        return true
    end

    handlers["/do"] = function(ply, args)
        local text = table.concat(args, " ", 2)
        if text == "" then return true end
        local parts = {
            col("doChat", Color(160, 210, 255)),
            "* " .. text .. " ((" .. nick(ply) .. "))",
        }
        broadcastNear(ply, radiusSqr("LocalRadius", 355), parts)
        return true
    end

    handlers["/it"] = function(ply, args)
        local text = table.concat(args, " ", 2)
        if text == "" then return true end
        local parts = {
            col("it", Color(190, 190, 210)),
            "** " .. text,
        }
        broadcastNear(ply, radiusSqr("LocalRadius", 355), parts)
        return true
    end

    handlers["/try"] = function(ply, args)
        local text = table.concat(args, " ", 2)
        local ok = math.random(1, 100) <= 50
        local resultCol = ok and col("tryGood", Color(100, 220, 100)) or col("tryBad", Color(230, 90, 90))
        local resultTxt = ok and "удачно" or "неудачно"
        local parts = {
            resultCol,
            "* " .. nick(ply) .. " " .. (text ~= "" and (text .. " — ") or "") .. resultTxt,
        }
        broadcastNear(ply, radiusSqr("LocalRadius", 355), parts)
        return true
    end

    handlers["/dice"] = function(ply, args)
        return handlers["/roll"](ply, args)
    end

    handlers["/roll"] = function(ply, args)
        local maxN = math.floor(tonumber(args[2]) or 100)
        if maxN < 2 then maxN = 100 end
        if maxN > 1000000 then maxN = 1000000 end
        local val = math.random(1, maxN)
        local parts = {
            col("roll", Color(255, 220, 120)),
            "* " .. nick(ply) .. " выбрасывает " .. tostring(val) .. " из " .. tostring(maxN),
        }
        broadcastNear(ply, radiusSqr("LocalRadius", 355), parts)
        return true
    end

    handlers["/w"] = function(ply, args)
        local text = table.concat(args, " ", 2)
        if text == "" then return true end
        local parts = {
            col("whisper", Color(180, 180, 180)),
            nick(ply) .. " шепчет: " .. text,
        }
        broadcastNear(ply, radiusSqr("WhisperRadius", 120), parts)
        return true
    end
    handlers["/whisper"] = handlers["/w"]

    handlers["/y"] = function(ply, args)
        local text = table.concat(args, " ", 2)
        if text == "" then return true end
        local parts = {
            col("yell", Color(255, 210, 120)),
            nick(ply) .. " кричит: " .. text,
        }
        broadcastNear(ply, radiusSqr("YellRadius", 700), parts)
        return true
    end
    handlers["/yell"] = handlers["/y"]

    handlers["/looc"] = function(ply, args)
        local text = table.concat(args, " ", 2)
        if text == "" then return true end
        local parts = {
            col("looc", Color(255, 165, 0)),
            "[LOOC] ",
            col("name", Color(100, 200, 255)),
            nick(ply),
            col("looc", Color(255, 165, 0)),
            ": " .. text,
        }
        broadcastNear(ply, radiusSqr("LOOCRadius", 355), parts)
        return true
    end
    handlers["//"] = handlers["/looc"]

    handlers["/ooc"] = function(ply, args)
        local text = table.concat(args, " ", 2)
        if text == "" then return true end
        if cfg().OOCOnlyAdmin and not ply:IsAdmin() and not ply:IsSuperAdmin() then
            sendTo(ply, { col("system", Color(255, 200, 80)), "[Чат] OOC только для администрации." })
            return true
        end
        local parts = {
            col("ooc", Color(255, 255, 255)),
            "[OOC] ",
            col("name", Color(100, 200, 255)),
            nick(ply),
            col("ooc", Color(255, 255, 255)),
            ": " .. text,
        }
        broadcastAll(parts)
        return true
    end
    handlers["/g"] = handlers["/ooc"]

    -- алиасы без слэша для надёжности после lower
    local function resolveCmd(raw)
        raw = string.Trim(tostring(raw or ""))
        local lower = string.lower(raw)
        if handlers[lower] then return handlers[lower], lower end
        -- поддержка !me
        if string.sub(lower, 1, 1) == "!" then
            local alt = "/" .. string.sub(lower, 2)
            if handlers[alt] then return handlers[alt], alt end
        end
        return nil, lower
    end

    local function handleRPChat(ply, text)
        if not IsValid(ply) or not ply:IsPlayer() then return end
        text = string.Trim(tostring(text or ""))
        if text == "" then return end

        -- кляп
        if ply.GetNWBool and ply:GetNWBool("GRM_CuffGagged", false) then
            return "" -- handcuffs hook may also catch
        end

        local args = string.Explode(" ", text)
        local fn = resolveCmd(args[1])
        if fn then
            local ok, err = pcall(fn, ply, args)
            if not ok then
                print("[GRM RPChat] error in " .. tostring(args[1]) .. ": " .. tostring(err))
            end
            return "" -- съели сообщение, не пускать в обычный чат
        end

        -- Неизвестная этому модулю slash/bang-команда должна пройти дальше
        -- по цепочке PlayerSay. Раньше RP-chat принимал её за локальную речь,
        -- возвращал "" и случайным порядком хуков ломал /mask, /arrest,
        -- /grm_arrest_admin и остальные команды модулей без transform-хука.
        local prefix = string.sub(text, 1, 1)
        if prefix == "/" or prefix == "!" then return end

        -- Обычный чат: локальный радиус, если ForceNormalChatLocal
        if cfg().ForceNormalChatLocal ~= false then
            local msg = text
            local parts = {
                col("name", Color(100, 200, 255)),
                nick(ply),
                col("localChat", Color(235, 235, 235)),
                ": " .. msg,
            }
            local others = broadcastNear(ply, radiusSqr("LocalRadius", 355), parts)
            -- Код 88.1 (репорт «чат закрыт»): молчание больше НЕ молчит.
            -- Если в радиусе никого — отправитель сразу видит системную строку,
            -- а не «сообщение пропало».
            if others == 0 then
                local now = CurTime()
                local last = C._aloneHint and C._aloneHint[ply] or 0
                if now - last >= 8 then -- троттл, чтобы не спамить при диалоге-пустышке
                    C._aloneHint = C._aloneHint or {}
                    C._aloneHint[ply] = now
                    local r = math.floor(math.sqrt(radiusSqr("LocalRadius", 355)))
                    sendTo(ply, {
                        col("system", Color(255, 200, 80)),
                        "[Чат] Рядом никого нет — вас никто не слышит (локальный чат ~"
                            .. tostring(r) .. " юн). Громче: /y, глобально: /ooc, в трубку: по телефону.",
                    })
                end
            end
            return ""
        end
    end

    -- Основной хук: высокий приоритет через имя с "!" (порядок не гарантирован,
    -- но возвращаем "" чтобы EasyChat и ваниль не дублировали).
    hook.Add("PlayerSay", "GRM_RPChat_PlayerSay", function(ply, text, teamChat)
        local result = handleRPChat(ply, text)
        if result == "" then return "" end
    end)

    -- EasyChat: иногда текст идёт через transform; если команда — SkipPlayerSay + очистка
    hook.Add("PlayerSayTransform", "GRM_RPChat_Transform", function(ply, datapack, is_team, is_local)
        if not istable(datapack) then return end
        local msg = datapack[1]
        if not isstring(msg) then return end
        local first = string.lower(string.Explode(" ", string.Trim(msg))[1] or "")
        local fn = resolveCmd(first)
        if fn then
            -- обработаем на сервере в PlayerSay; на клиенте transform тоже может сработать
            if SERVER then
                handleRPChat(ply, msg)
                datapack[1] = ""
                datapack.SkipPlayerSay = true
                return
            end
        end
    end)

    print("[GRM RPChat] server v1.2.0 (pass-through чужих команд) — /me /do /it /try /roll /w /y /looc /ooc + local")
end

-- ============================================================
-- CLIENT
-- ============================================================
if CLIENT then
    net.Receive(NET_MSG, function()
        local n = net.ReadUInt(8)
        local parts = {}
        for i = 1, n do
            local isCol = net.ReadBool()
            if isCol then
                parts[#parts + 1] = Color(net.ReadUInt(8), net.ReadUInt(8), net.ReadUInt(8))
            else
                parts[#parts + 1] = net.ReadString()
            end
        end
        chat.AddText(unpack(parts))
    end)

    -- Подсказка в консоль
    concommand.Add("grm_rpchat_help", function()
        chat.AddText(Color(200, 160, 255), "[RP Chat] ", color_white,
            "/me /do /it /try /roll [N] /w /y /looc (//) /ooc (/g)")
    end)

    print("[GRM RPChat] client v1.0.0")
end
