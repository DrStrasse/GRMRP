--[[ GRM Real Time v2.0.0 — точные настенные часы, без погоды и освещения.

     v2.0.0 (антифриз/антитрафик):
       * сервер БОЛЬШЕ НЕ рассылает форматированную строку каждую секунду.
         Раньше SetGlobalString("GRM_RealTime", "HH:MM:SS") уходил всем
         клиентам 60 раз в минуту, вечно, даже когда TAB закрыт. Теперь в сеть
         идёт только эпоха (GlobalInt) и то раз в 5 секунд;
       * клиент считает время сам от эпохи + CurTime и форматирует его
         НЕ ЧАЩЕ РАЗА В СЕКУНДУ (os.date в HUDPaint — это аллокация строки
         каждый кадр и заметный мусор для GC);
       * T.Clock(fmt) — общий кэш os.date для любых HUD-модулей.
]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Time = GRM.Time or {}
local T = GRM.Time

T.Version = "2.1.0"
-- 0 = локальное время системы (часовой пояс ПК/сервера).
-- Можно переопределить конваром grm_time_utc_offset_minutes (в минутах от UTC).
T.DefaultOffsetMinutes = 0
T.SyncInterval = 5

-- Локальный UTC-оффсет системы (с учётом DST) в минутах.
function T.LocalOffsetMinutes()
    local utc = os.time(os.date("!*t"))
    local loc = os.time(os.date("*t"))
    return os.difftime(loc, utc) / 60
end

function T.FormatOffset(timestamp, offsetMinutes)
    local off = tonumber(offsetMinutes)
    if off == nil then off = T.DefaultOffsetMinutes end
    -- off == 0 → локальное время (без сдвига к UTC)
    local shifted = (tonumber(timestamp) or os.time()) + off * 60
    local row
    if off == 0 then
        row = os.date("*t", shifted)
    else
        row = os.date("!*t", shifted)
    end
    return string.format("%02d:%02d:%02d", row.hour, row.min, row.sec)
end

function T.FormatDate(timestamp, offsetMinutes, fmt)
    local off = tonumber(offsetMinutes)
    if off == nil then off = T.DefaultOffsetMinutes end
    local shifted = (tonumber(timestamp) or os.time()) + off * 60
    return off == 0 and os.date(fmt or "%d.%m.%Y", shifted)
        or os.date("!" .. (fmt or "%d.%m.%Y"), shifted)
end

-- Смещение реплицируется конваром, эпоха — глобалом.
-- Значение по умолчанию 0 означает ЛОКАЛЬНОЕ время.
function T.Offset()
    local cv = GetConVar("grm_time_utc_offset_minutes")
    local v = cv and cv:GetInt() or T.DefaultOffsetMinutes
    return math.Clamp(v, -720, 840)
end

-- Текущая серверная эпоха: последний присланный штамп + прошедшее время.
function T.Epoch()
    if SERVER then return os.time() end
    local stamp = GetGlobalInt and GetGlobalInt("GRM_RealTimeEpoch", 0) or 0
    if stamp <= 0 then return os.time() end
    local at = T._stamp == stamp and T._stampAt or nil
    if not at then
        T._stamp, T._stampAt = stamp, CurTime()
        at = T._stampAt
    end
    return stamp + math.max(0, CurTime() - at)
end

-- Строка часов. Пересчитывается не чаще раза в секунду — сколько бы HUD-хуков
-- её ни спрашивали в одном кадре.
function T.GetString()
    local now = T.Epoch()
    local sec = math.floor(now)
    if T._cacheSec == sec and T._cacheStr then return T._cacheStr end
    T._cacheSec = sec
    T._cacheStr = T.FormatOffset(sec, T.Offset())
    return T._cacheStr
end

-- Общий кэшированный os.date для HUD: GRM.Time.Clock("%H:%M:%S  •  %d.%m.%Y").
T._fmtCache = T._fmtCache or {}
function T.Clock(fmt)
    fmt = tostring(fmt or "%H:%M:%S")
    local sec = math.floor(T.Epoch())
    local slot = T._fmtCache[fmt]
    if slot and slot.sec == sec then return slot.text end
    local off = T.Offset()
    local text = (off == 0) and os.date(fmt, sec) or os.date("!"..fmt, sec + off*60)
    T._fmtCache[fmt] = { sec = sec, text = text }
    return text
end

if SERVER then
    CreateConVar("grm_time_utc_offset_minutes", tostring(T.DefaultOffsetMinutes),
        bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED), "GRM wall-clock UTC offset in minutes")

    local function sync()
        SetGlobalInt("GRM_RealTimeEpoch", os.time())
    end
    sync()
    timer.Create("GRM_RealTime_Sync", T.SyncInterval, 0, sync)

    local function tell(p)
        if IsValid(p) then p:ChatPrint("[Время] " .. T.FormatOffset(os.time(), T.Offset())) end
    end
    concommand.Add("grm_time", tell)
    hook.Add("PlayerSay", "GRM_RealTime_Chat", function(p, text)
        local s = string.lower(string.Trim(tostring(text or "")))
        if s == "/time" or s == "/время" then tell(p) return "" end
    end)
    hook.Add("PlayerSayTransform", "GRM_RealTime_EasyChat", function(p, text, pack)
        pack = istable(text) and text or pack
        local raw = istable(text) and text[1] or text
        local s = string.lower(string.Trim(tostring(raw or "")))
        if s ~= "/time" and s ~= "/время" then return end
        tell(p)
        if istable(pack) then pack.SkipPlayerSay = true pack[1] = "" end
    end)
    print("[GRM Time] real clock v" .. T.Version .. " loaded, UTC offset " .. T.Offset() .. " min, sync " .. T.SyncInterval .. "s")
end
