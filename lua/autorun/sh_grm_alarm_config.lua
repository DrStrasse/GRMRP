--[[--------------------------------------------------------------------
    GRM Alarm / Security System — config (Код 63)
    Режимы: 1 Выкл | 2 Под охраной | 3 Пассивный контроль
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Alarm = GRM.Alarm or {}
local A = GRM.Alarm

A.MODE_OFF     = 1
A.MODE_ARMED   = 2
A.MODE_PASSIVE = 3

A.Config = A.Config or {
    SensorModel   = "models/bull/various/gyroscope.mdl",
    HubModel      = "models/props_lab/reciever_cart.mdl",
    TerminalModel = "models/props/cs_office/computer.mdl",
    -- Код 89: динамик сирены
    SpeakerModel  = "models/props_wasteland/speakercluster01a.mdl",
    SpeakerModelFallback = "models/props_lab/citizenradio.mdl",

    DefaultNetwork = "main",
    MaxNetworkLen  = 32,
    MaxLabelLen    = 48,

    UseDistance = 140,
    -- Радиус датчика движения (юниты)
    DefaultSensorRadius = 220,
    MinSensorRadius = 64,
    MaxSensorRadius = 800,

    -- Как часто хаб/датчики сканируют игроков (сек)
    ScanInterval = 0.35,
    -- Кулдаун повторной фиксации того же игрока на датчике (сек)
    TriggerCooldown = 4,
    -- Длительность сирены (0 = пока не сбросят)
    SirenDuration = 45,
    -- Звук сирены (зацикливается автоматически — EnableLooping в StartSiren/динамиках).
    -- Проверенные стоковые HL2-сирены (все есть в базовом контенте GMod):
    --   ambient/alarms/combine_bank_alarm_loop1.wav .. loop4.wav  — электронная тревога (текущая — loop4)
    --   ambient/alarms/citadel_alarm1.wav                        — тревога Цитадели
    --   ambient/alarms/alarm1.wav .. alarm4.wav                  — классическая сирена HL2
    --   ambient/alarms/klaxon1.wav                               — клаксон
    --   ambient/alarms/klaxon2.wav
    SirenSound = "ambient/alarms/combine_bank_alarm_loop4.wav",
    SirenLevel = 80,
    SirenVolume = 1,

    SaveDir = "grm_alarm",
    LogRetentionDays = 14,
    MaxLogLinesMemory = 400,

    SuperAdminBypass = true,
    DrawLabels = true,
    LabelDistance = 420,
}

A.ModeNames = A.ModeNames or {
    [1] = "Выключено",
    [2] = "Под охраной",
    [3] = "Пассивный контроль",
}

A.ModeColors = A.ModeColors or {
    [1] = Color(160, 160, 160),
    [2] = Color(80, 200, 100),
    [3] = Color(80, 160, 230),
}

function A.NormalizeNetwork(value)
    value = string.Trim(tostring(value or A.Config.DefaultNetwork or "main"))
    if value == "" then value = A.Config.DefaultNetwork or "main" end
    value = string.lower(string.sub(value, 1, A.Config.MaxNetworkLen or 32))
    value = string.gsub(value, "[^%w%-%_%.]", "")
    if value == "" then value = "main" end
    return value
end

function A.ClampMode(m)
    m = math.floor(tonumber(m) or 1)
    if m < 1 then m = 1 end
    if m > 3 then m = 3 end
    return m
end

function A.ModeName(m)
    m = A.ClampMode(m)
    return (A.ModeNames and A.ModeNames[m]) or ("Режим " .. m)
end

print("[GRM Alarm] config v1.1.0")
