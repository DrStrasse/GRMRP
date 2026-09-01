--[[--------------------------------------------------------------------
    GRM CCTV — shared configuration (Код 60) v1.2.0
    Видеонаблюдение: камеры, монитор (ПК), серверная стойка сети.
    + pan/zoom, freeze, скриншоты.
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.CCTV = GRM.CCTV or {}

local C = GRM.CCTV

C.Config = C.Config or {
    CameraModel     = "models/props_silo/camera.mdl",
    CameraModelAlt  = "models/props/cs_assault/camera.mdl",
    MonitorModel    = "models/natalya/sims/computer.mdl",
    MonitorModelAlt = "models/props/cs_office/computer.mdl",
    ServerModel     = "models/props_lab/servers.mdl",

    DefaultNetwork = "main",
    MaxNetworkLen  = 32,
    MaxLabelLen    = 48,

    -- Базовый FOV камеры (при спавне / настройка E)
    DefaultFOV = 75,
    MinFOV     = 25,   -- максимальный зум (ближе)
    MaxFOV     = 100,  -- шире

    MaxCamerasPerNetwork = 32,
    MaxMonitorsPerMap    = 24,
    MaxServersPerMap     = 12,

    UseDistance = 140,
    ListRefreshSeconds = 2,
    SaveDir = "grm_cctv",

    -- Доступ живой: /cctv_access и вкладка CCTV в /factions (sh_grm_cctv_access.lua).
    -- Поля ниже — fallback, если access.json ещё пуст.
    Access = {
        SuperAdminBypass = true,
        PublicView = false,
        AllowSteam = {},
        AllowFactions = {},
    },

    DrawLabels = true,
    LabelDistance = 420,
    SwitchCooldown = 0.15,

    -- Обзор мышью
    AllowPan = true,
    PanYawMax = 55,
    PanPitchMax = 35,
    PanSensitivity = 0.06,

    -- Зум (колёсико / клавиши)
    AllowZoom = true,
    ZoomStep = 4,          -- на один тик колёсика / нажатие
    ZoomMinFOV = 25,       -- ближе
    ZoomMaxFOV = 100,      -- дальше
    -- Клавиши зума (см. KEY_* на клиенте): = / + приблизить, - отдалить

    FreezePlayer = true,

    -- Скриншоты
    -- GMod render.Capture пишет в data/ ТОЛЬКО на клиенте того, кто смотрит.
    Screenshots = {
        Enabled = true,
        -- Относительно garrysmod/data/
        -- Итог: data/grm_cctv/screenshots/<сеть>/<камера>/<файл>.jpg
        Dir = "grm_cctv/screenshots",
        Format = "jpeg",       -- "jpeg" | "png"
        Quality = 90,          -- jpeg 1..100
        HideUI = false,        -- false = HUD камеры попадает на скриншот (рекомендуется)
        Cooldown = 1.0,        -- сек между снимками
        -- Захват: RenderView→RT (не framebuffer ViewEntity — иначе часто чёрный кадр)
        -- Имя файла: {map}_{network}_{camid}_{YYYYMMDD_HHMMSS}.jpg
    },

    -- Видеозапись (DVR):
    -- В чистом GMod НЕТ штатного API «пиши framebuffer камеры в файл N минут».
    -- render.Capture — покадровые скрины (тяжёло и не AVI).
    -- Реальные варианты «куда направить запись»:
    --   1) папка скриншотов выше (рекомендуем);
    --   2) внешний demo/SourceTV (tv_record) — серверный demo, не «картинка с камеры»;
    --   3) внешний OBS у оператора.
    -- VideoRecording.Enabled оставляем false; путь — задел под будущий модуль.
    VideoRecording = {
        Enabled = false,
        Dir = "grm_cctv/recordings",
        Note = "Не реализовано движком GMod; используйте скриншоты или OBS.",
    },
}

function C.NormalizeNetwork(value)
    value = string.Trim(tostring(value or C.Config.DefaultNetwork or "main"))
    if value == "" then value = C.Config.DefaultNetwork or "main" end
    value = string.lower(string.sub(value, 1, C.Config.MaxNetworkLen or 32))
    value = string.gsub(value, "[^%w%-%_%.]", "")
    if value == "" then value = "main" end
    return value
end

function C.ClampFOV(fov)
    local cfg = C.Config
    local zmin = tonumber(cfg.ZoomMinFOV) or tonumber(cfg.MinFOV) or 25
    local zmax = tonumber(cfg.ZoomMaxFOV) or tonumber(cfg.MaxFOV) or 100
    fov = tonumber(fov) or cfg.DefaultFOV or 75
    return math.Clamp(math.floor(fov + 0.5), zmin, zmax)
end

print("[GRM CCTV] config v1.2.3")
