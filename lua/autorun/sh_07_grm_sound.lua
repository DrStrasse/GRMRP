-- Boot-шим: старт подсистемы идёт через планировщик GRM.Boot (приоритеты и
-- бюджет на тик). Если планировщик почему-то не загружен, работаем по-старому.
local function grmBootStart(id, tier, fn)
    if GRM and GRM.Boot and GRM.Boot.OnMapStart then return GRM.Boot.OnMapStart(id, tier, fn) end
    return hook.Add("InitPostEntity", id, fn)
end

--[[--------------------------------------------------------------------
    GRM Sound v1.0.0 — общий звуковой слой

    Зачем:
      1. ПРЕКЭШ. Первое проигрывание непрекэшированного звука подгружает файл
         с диска прямо в кадре — это классический микрофриз «щёлкнул кнопку —
         дёрнулось». Все звуки GRM регистрируются здесь и прекэшируются один
         раз на старте карты.
      2. ЗАЩИТА ОТ ОТСУТСТВУЮЩИХ ФАЙЛОВ. Кастомные звуки (kom_hour.wav и т.п.)
         на сервере может не оказаться. Раньше это давало поток ошибок движка
         на каждое воспроизведение. Теперь путь проверяется один раз, пишется
         ОДНО предупреждение, играет безопасный фолбэк.
      3. КОНТРОЛЬ ЗАЦИКЛЕННЫХ ЗВУКОВ. CreateSound-патчи легко «теряются» при
         удалении entity и продолжают звучать. GRM.Sound.Loop ведёт реестр и
         глушит патч при удалении носителя.
      4. АНТИСПАМ UI. Один и тот же клик, вызванный несколько раз за кадр,
         играет один раз.

    API:
      GRM.Sound.Register(path[, fallback])   — объявить звук (прекэш на старте)
      GRM.Sound.Exists(path)                 — есть ли файл (кэш)
      GRM.Sound.Resolve(path)                — путь или фолбэк
      GRM.Sound.Emit(ent, path, lvl, pitch, vol)
      GRM.Sound.UI(path[, throttle])         — клиентский интерфейсный звук
      GRM.Sound.Loop(ent, path)              — зацикленный патч с реестром
      GRM.Sound.StopLoop(ent[, path])
      GRM.Sound.Check()                      — отчёт: какие файлы не найдены
      консоль: grm_sound_check
----------------------------------------------------------------------]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Sound = GRM.Sound or {}
local S = GRM.Sound

S.Version   = "1.0.0"
S.Registry  = S.Registry or {}   -- path -> { fallback = path }
S._exists   = S._exists or {}    -- кэш file.Exists
S._warned   = S._warned or {}
S._loops    = S._loops or {}     -- ent -> { path -> patch }
S._uiAt     = S._uiAt or {}

-- Безопасный фолбэк: стоковый звук движка, он есть всегда.
S.DefaultFallback = "buttons/button19.wav"

function S.Register(path, fallback)
    path = tostring(path or "")
    if path == "" then return end
    S.Registry[path] = { fallback = fallback or S.DefaultFallback }
    return path
end

function S.Exists(path)
    path = tostring(path or "")
    if path == "" then return false end
    local cached = S._exists[path]
    if cached ~= nil then return cached end
    -- Стоковый контент лежит в VPK и file.Exists его тоже видит.
    local okFile = file.Exists("sound/" .. path, "GAME")
    S._exists[path] = okFile
    return okFile
end

function S.Resolve(path)
    path = tostring(path or "")
    if path == "" then return S.DefaultFallback end
    if S.Exists(path) then return path end
    if not S._warned[path] then
        S._warned[path] = true
        local reg = S.Registry[path]
        print(("[GRM Sound] НЕ НАЙДЕН звук '%s' — играю фолбэк '%s'. Положите файл в garrysmod/sound/%s")
            :format(path, (reg and reg.fallback) or S.DefaultFallback, path))
    end
    local reg = S.Registry[path]
    return (reg and reg.fallback) or S.DefaultFallback
end

function S.Emit(ent, path, level, pitch, volume)
    if not IsValid(ent) then return false end
    local resolved = S.Resolve(path)
    ent:EmitSound(resolved, tonumber(level) or 75, tonumber(pitch) or 100, tonumber(volume) or 1)
    return true
end

function S.Stop(ent, path)
    if not IsValid(ent) or not ent.StopSound then return end
    ent:StopSound(S.Resolve(path))
end

-- Клиентский UI-звук: один и тот же путь не проигрывается чаще, чем раз в
-- throttle секунд (по умолчанию 0.05 — то есть не более одного раза за кадр).
function S.UI(path, throttle)
    if not CLIENT then return false end
    local now = RealTime()
    local key = tostring(path)
    if (S._uiAt[key] or 0) > now then return false end
    S._uiAt[key] = now + (tonumber(throttle) or 0.05)
    surface.PlaySound(S.Resolve(path))
    return true
end

-- Зацикленный звук с реестром: патч гасится при удалении носителя.
function S.Loop(ent, path)
    if not IsValid(ent) then return nil end
    local resolved = S.Resolve(path)
    local slot = S._loops[ent]
    if not slot then slot = {} S._loops[ent] = slot end
    if slot[resolved] then return slot[resolved] end
    local patch = CreateSound(ent, resolved)
    if not patch then return nil end
    slot[resolved] = patch
    patch:Play()
    return patch
end

function S.StopLoop(ent, path)
    local slot = S._loops[ent]
    if not slot then return 0 end
    local stopped = 0
    if path then
        local resolved = S.Resolve(path)
        if slot[resolved] then slot[resolved]:Stop() slot[resolved] = nil stopped = 1 end
        if not next(slot) then S._loops[ent] = nil end
    else
        for _, patch in pairs(slot) do patch:Stop() stopped = stopped + 1 end
        S._loops[ent] = nil
    end
    return stopped
end

hook.Add("EntityRemoved", "GRM_Sound_StopLoops", function(ent)
    if S._loops[ent] then S.StopLoop(ent) end
end)

-----------------------------------------------------------------------
-- Реестр звуков GRM: всё, что реально используется в коде сборки.
-- Кастомные (не стоковые) помечены фолбэком на близкий стоковый звук.
-----------------------------------------------------------------------
local STOCK = {
    "buttons/button3.wav", "buttons/button6.wav", "buttons/button8.wav", "buttons/button9.wav",
    "buttons/button10.wav", "buttons/button11.wav", "buttons/button14.wav", "buttons/button15.wav",
    "buttons/button16.wav", "buttons/button17.wav", "buttons/button18.wav", "buttons/button19.wav",
    "buttons/button24.wav", "buttons/bell1.wav", "buttons/blip1.wav", "buttons/lever4.wav",
    "buttons/lever7.wav", "buttons/lightswitch2.wav", "buttons/combine_button1.wav",
    "buttons/combine_button2.wav", "buttons/combine_button3.wav", "buttons/combine_button7.wav",
    "garrysmod/ui_click.wav", "garrysmod/ui_hover.wav", "garrysmod/save_load1.wav",
    -- Стоковые звуки выбора оружия HL2 — их же использует ванильный селектор.
    "common/wpn_hudon.wav", "common/wpn_hudoff.wav", "common/wpn_moveselect.wav",
    "common/wpn_select.wav", "common/wpn_denyselect.wav",
    "ui/buttonclick.wav", "ui/buttonclickrelease.wav",
    "ambient/alarms/combine_bank_alarm_loop4.wav", "ambient/alarms/klaxon1.wav",
    "ambient/alarms/scanner_alert_pass1.wav", "ambient/alarms/warningbell1.wav",
    "ambient/energy/spark6.wav", "ambient/explosions/explode_4.wav",
    "ambient/fire/gascan_ignite1.wav", "ambient/levels/citadel/field_loop1.wav",
    "ambient/levels/labs/coinslot1.wav", "ambient/machines/combine_terminal_idle4.wav",
    "ambient/machines/floodgate_stop1.wav", "ambient/machines/steam_release_2.wav",
    "ambient/materials/dirt_impact1.wav", "ambient/water/leak_1.wav", "ambient/water/water_splash1.wav",
    "doors/door1_move.wav", "doors/door_latch1.wav", "doors/door_latch3.wav",
    "doors/door_metal_thin_close2.wav", "doors/door_metal_thin_open1.wav",
    "doors/latchbolt.wav", "doors/latchunbolt.wav",
    "items/ammo_pickup.wav", "items/ammocrate_close.wav", "items/ammocrate_open.wav",
    "items/itempickup.wav", "items/suitchargeok1.wav", "items/weapon_drop.wav",
    "npc/barnacle/barnacle_gulp1.wav", "npc/metropolice/die2.wav",
    "npc/metropolice/gear1.wav", "npc/metropolice/gear2.wav", "npc/metropolice/gear3.wav",
    "npc/overwatch/radiovoice/off2.wav", "npc/overwatch/radiovoice/on3.wav",
    "physics/cardboard/cardboard_box_impact_soft4.wav", "physics/metal/metal_box_break1.wav",
    "physics/metal/metal_box_impact_soft1.wav", "physics/metal/metal_chainlink_impact_soft2.wav",
    "physics/metal/metal_solid_impact_hard2.wav",
    "physics/rubber/rubber_tire_impact_soft1.wav", "physics/rubber/rubber_tire_impact_soft2.wav",
    "physics/wood/wood_box_break1.wav", "physics/wood/wood_crate_impact_hard1.wav",
    "physics/wood/wood_crate_impact_hard2.wav",
    "player/breathe1.wav", "music/hl2_song20_submix0.mp3",
    "weapons/c4/c4_disarm.wav",
    "weapons/stunstick/stunstick_impact1.wav", "weapons/stunstick/stunstick_impact2.wav",
    "weapons/stunstick/stunstick_swing1.wav", "weapons/stunstick/stunstick_swing2.wav",
}
for _, path in ipairs(STOCK) do S.Register(path) end

-- Кастомный контент сборки (может отсутствовать у владельца сервера).
S.Register("garrysmod/ui_hover.wav", "buttons/lightswitch2.wav")
S.Register("kom_hour.wav", "ambient/alarms/warningbell1.wav")            -- комендантский час
S.Register("npc/scanner/scanner_siren2.wav", "ambient/alarms/klaxon1.wav") -- вызов пожарного расчёта
S.Register("weapons/extinguisher/fire1.wav", "ambient/machines/steam_release_2.wav")
S.Register("physics/concrete/concrete_break2.wav") -- запасной звук разрушения породы
S.Register("physics/concrete/concrete_break3.wav", "physics/concrete/concrete_break2.wav") -- разрушение узла руды
S.Register("weapons/extinguisher/release1.wav", "ambient/machines/steam_release_2.wav")

-- Звуки отбывающих наказание на сервере (модуль GRM.ServerBan): скелет
-- «стонет», чтобы наказанного было слышно и видно.
S.Register("npc/zombie/zombie_voice_idle1.wav")
S.Register("npc/zombie/zombie_voice_idle2.wav", "npc/zombie/zombie_voice_idle1.wav")
S.Register("npc/zombie/zombie_voice_idle3.wav", "npc/zombie/zombie_voice_idle1.wav")
S.Register("npc/zombie/zombie_voice_idle4.wav", "npc/zombie/zombie_voice_idle1.wav")
S.Register("npc/zombie/zombie_voice_idle5.wav", "npc/zombie/zombie_voice_idle1.wav")
S.Register("npc/zombie/zombie_voice_idle6.wav", "npc/zombie/zombie_voice_idle1.wav")

S.Custom = { "kom_hour.wav", "weapons/extinguisher/fire1.wav", "weapons/extinguisher/release1.wav" }

-----------------------------------------------------------------------
-- Прекэш: один раз на старте карты, вне игрового кадра.
-----------------------------------------------------------------------
local function precacheAll()
    if S._precached then return 0 end
    S._precached = true
    local n = 0
    for path in pairs(S.Registry) do
        if S.Exists(path) then
            util.PrecacheSound(path)
            n = n + 1
        end
    end
    if SERVER then
        -- Кастомные файлы раздаём клиентам, если они реально лежат на сервере.
        for _, path in ipairs(S.Custom) do
            if S.Exists(path) then resource.AddFile("sound/" .. path) end
        end
    end
    print(("[GRM Sound] прекэш: %d звуков из %d зарегистрированных"):format(n, table.Count(S.Registry)))
    return n
end

grmBootStart("GRM_Sound_Precache", "late", function() timer.Simple(1, precacheAll) end)
hook.Add("PostCleanupMap", "GRM_Sound_PrecacheAfterCleanup", function() S._precached = nil timer.Simple(1, precacheAll) end)
timer.Simple(5, precacheAll)  -- страховка, если InitPostEntity уже прошёл

-----------------------------------------------------------------------
-- Диагностика
-----------------------------------------------------------------------
function S.Check()
    local missing, okCount = {}, 0
    for path in pairs(S.Registry) do
        if S.Exists(path) then okCount = okCount + 1 else missing[#missing + 1] = path end
    end
    table.sort(missing)
    return okCount, missing
end

concommand.Add("grm_sound_check", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    local okCount, missing = S.Check()
    local lines = {
        ("[GRM Sound] зарегистрировано %d, найдено %d, отсутствует %d"):format(table.Count(S.Registry), okCount, #missing),
    }
    for _, path in ipairs(missing) do
        local reg = S.Registry[path]
        lines[#lines + 1] = ("   НЕТ: %s  ->  фолбэк %s"):format(path, (reg and reg.fallback) or S.DefaultFallback)
    end
    if #missing == 0 then lines[#lines + 1] = "   все звуки на месте" end
    for _, l in ipairs(lines) do
        if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, l) ply:ChatPrint(l) else print(l) end
    end
end)

print("[GRM Sound] v" .. S.Version .. ": прекэш, фолбэки, реестр зацикленных звуков")
