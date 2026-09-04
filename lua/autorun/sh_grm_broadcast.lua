-- Boot-шим: старт подсистемы идёт через планировщик GRM.Boot (приоритеты и
-- бюджет на тик). Если планировщик почему-то не загружен, работаем по-старому.
local function grmBootStart(id, tier, fn)
    if GRM and GRM.Boot and GRM.Boot.OnMapStart then return GRM.Boot.OnMapStart(id, tier, fn) end
    return hook.Add("InitPostEntity", id, fn)
end

--[[--------------------------------------------------------------------
    GRM Broadcast v1.2.0 (Код 75) — Радиовещание и массовое оповещение
    v1.2.0: интеграция с RadioNet (Код 85): эфир до приёмников доходит
      только в покрытии сети (микрофон↔передатчик↔стойка↔антенны) и с
      «радио-искажением» у края покрытия; новый режим микрофона ГРОМКАЯ
      СВЯЗЬ (доступ /alert_allow): голос звучит усиленно из сетевых
      громкоговорителей с треском; /alert срабатывает только на громко-
      говорителях, реально подключённых к сети; легаси-хук голоса ниже
      самоотключается, пока RadioNet в сборке (маршрутизация там).
    v1.1.1: +хуки GRM_BC_BroadcastStart(ply, station) и GRM_BC_Alert
      (ply, text, global) — метрики ачивок (Код 78).
    v1.1.0: команды обрабатываются через PlayerSayTransform + fallback
      PlayerSay (EasyChat-хуки не проглатывают — репорт «/alertall не
      работает»); АВТОперсистентность энтити (grm_bcents/<map>.json) —
      /speaker_add и пр. больше НЕ требуют /permadd, воскресают после
      рестарта с антидублем.
    Три энтити:
      - grm_broadcast_mic  — микрофонная стойка (журналисты/СМИ): E →
        название станции, «Начать эфир». В эфире ГОЛОС и ТЕКСТ спикера
        ретранслируются слушателям возле настроенных радиоприёмников.
      - grm_radio          — домашний приёмник (citizenradio): E → список
        живых станций, настройка станции / выключение.
      - grm_loudspeaker    — уличный громкоговоритель оповещения района.
    Массовое оповещение: /alert текст (возле громкоговорителей),
    /alertall текст (всем). Доступ: суперадмин или фракции из списка
    (/alert_allow Фракция, /alert_deny Фракция; журналисты:
    /bcast_allow Фракция, /bcast_deny Фракция — суперадмин всегда может).
    Спавн: /radiomic_add /radio_add /speaker_add (суперадмин) + /permadd.
    Конфиг: data/grm_broadcast.json
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Broadcast = GRM.Broadcast or {}
local BC = GRM.Broadcast

BC.Version       = "1.3.0"  -- Код 88.4: авто-свипер персистента (устройства перманентны любым способом постановки)
BC.ReceiveRadius = 500   -- радиус слышимости от приёмника
BC.MicMaxDist    = 250   -- спикер должен стоять у микрофона
BC.SpeakerRadius = 700   -- радиус громкоговорителя оповещения
BC.AlertDuration = 8     -- секунды показа оповещения
BC.ConfigFile    = "grm_broadcast.json"

local NET_RADIO_OPEN = "GRM_BC_RadioOpen"
local NET_RADIO_SET  = "GRM_BC_RadioSet"
local NET_MIC_OPEN   = "GRM_BC_MicOpen"
local NET_MIC_SET    = "GRM_BC_MicSet"
local NET_LINE       = "GRM_BC_Line"
local NET_ALERT      = "GRM_BC_Alert"

-- ============================================================
-- СЕРВЕР
-- ============================================================
if SERVER then
    util.AddNetworkString(NET_RADIO_OPEN)
    util.AddNetworkString(NET_RADIO_SET)
    util.AddNetworkString(NET_MIC_OPEN)
    util.AddNetworkString(NET_MIC_SET)
    util.AddNetworkString(NET_LINE)
    util.AddNetworkString(NET_ALERT)

    -- конфиг доступа ------------------------------------------------
    local function jsonT(txt)
        local ok, t = pcall(util.JSONToTable, txt, false, true)
        return (ok and istable(t)) and t or nil
    end
    local function defaultCfg()
        return { journalists = {}, alerters = {}, micNames = {} }
    end
    local function loadCfg()
        BC.Cfg = BC.Cfg or defaultCfg()
        local t = jsonT(file.Read(BC.ConfigFile, "DATA") or "")
        if istable(t) then
            BC.Cfg.journalists = istable(t.journalists) and t.journalists or {}
            BC.Cfg.alerters    = istable(t.alerters)    and t.alerters    or {}
            BC.Cfg.micNames    = istable(t.micNames)    and t.micNames    or {}
        end
    end
    function BC.SaveCfg()
        local ok, txt = pcall(util.TableToJSON, BC.Cfg or defaultCfg(), true)
        if ok and txt then file.Write(BC.ConfigFile, txt) end
    end
    loadCfg()

    -- автоперсистентность энтити (без /permadd): радио/микрофон/громкоговорители
    -- сохраняются на карту при постановке и воскресают после рестарта -------
    local PERSIST_CLASSES = { grm_radio = true, grm_broadcast_mic = true, grm_loudspeaker = true }
    local function entsFile()
        if not file.IsDir("grm_bcents", "DATA") then file.CreateDir("grm_bcents") end
        return "grm_bcents/" .. string.lower(game.GetMap() or "unknown") .. ".json"
    end
    BC.Persist = BC.Persist or {}
    local function loadPersist()
        local t = jsonT(file.Read(entsFile(), "DATA") or "")
        BC.Persist = istable(t) and t or {}
    end
    local function savePersist()
        local ok, txt = pcall(util.TableToJSON, BC.Persist or {}, true)
        if ok and txt then file.Write(entsFile(), txt) end
    end
    loadPersist()

    local function persistKey(class, pos)
        return tostring(class) .. "|" .. string.format("%.0f_%.0f_%.0f", pos.x, pos.y, pos.z)
    end

    function BC.PersistAdd(ent)
        if not IsValid(ent) or BC._restoring then return end
        local class = ent:GetClass()
        if not PERSIST_CLASSES[class] then return end
        local pos, ang = ent:GetPos(), ent:GetAngles()
        BC.Persist[persistKey(class, pos)] = {
            class = class,
            pos = { x = pos.x, y = pos.y, z = pos.z },
            ang = { p = ang.p or 0, y = ang.y or 0, r = ang.r or 0 },
        }
        savePersist()
    end

    function BC.PersistRemove(ent)
        if not IsValid(ent) then return end
        local k = persistKey(ent:GetClass(), ent:GetPos())
        if BC.Persist[k] then BC.Persist[k] = nil savePersist() end
    end

    -- Код 88.4: авто-свипер персистента (зеркало RadioNet): радио/микрофон/
    -- громкоговорители сейвятся перманентно ЛЮБЫМ способом постановки;
    -- переезд = миграция ключа, удаление живьём = выпадение из реестра.
    local function persistSweep()
        if BC._restoring then return end
        local seen = {}
        for class in pairs(PERSIST_CLASSES) do
            for _, e in ipairs(ents.FindByClass(class)) do
                if IsValid(e) then
                    local k = persistKey(class, e:GetPos())
                    seen[k] = true
                    if not BC.Persist[k] then
                        if e._grmBCKey and BC.Persist[e._grmBCKey] then BC.Persist[e._grmBCKey] = nil end
                        BC.PersistAdd(e)
                    end
                    e._grmBCKey = k
                end
            end
        end
        local lost = 0
        for k, rec in pairs(BC.Persist or {}) do
            if PERSIST_CLASSES[rec.class] and not seen[k] then
                BC.Persist[k] = nil
                lost = lost + 1
            end
        end
        if lost > 0 then savePersist() end
    end
    timer.Create("GRM_BC_PersistSweep", 17, 0, persistSweep)
    BC._devSweep = persistSweep -- тест-экспорт (сим)

    function BC.RestoreMap()
        BC._restoring = true
        for k, rec in pairs(BC.Persist or {}) do
            if PERSIST_CLASSES[rec.class] and istable(rec.pos) then
                local pos = Vector(tonumber(rec.pos.x) or 0, tonumber(rec.pos.y) or 0, tonumber(rec.pos.z) or 0)
                local dup = false
                for _, e in ipairs(ents.FindByClass(rec.class)) do
                    if IsValid(e) and e:GetPos():DistToSqr(pos) < 64 then dup = true break end
                end
                if not dup then
                    local ent = ents.Create(rec.class)
                    if IsValid(ent) then
                        ent:SetPos(pos)
                        local a = istable(rec.ang) and rec.ang or {}
                        ent:SetAngles(Angle(tonumber(a.p) or 0, tonumber(a.y) or 0, tonumber(a.r) or 0))
                        ent:Spawn() ent:Activate()
                        if GRM.PropProtect and GRM.PropProtect.MarkServerEntity then GRM.PropProtect.MarkServerEntity(ent) end
                        local phys = ent:GetPhysicsObject()
                        if IsValid(phys) then phys:EnableMotion(false) end
                    end
                end
            end
        end
        BC._restoring = false
        print("[GRM Broadcast] Персистент: проверено записей — " .. tostring(table.Count(BC.Persist or {})))
    end

    -- воскрешение после рестарта (антидубль: если рядом уже есть — пропускаем)
    grmBootStart("GRM_BC_Restore", "normal", function()
        timer.Simple(3, function() BC.RestoreMap() end)
    end)

    hook.Add("PostCleanupMap", "GRM_BC_Cleanup", function()
        timer.Simple(0.5, function() BC.RestoreMap() end)
    end)

    -- помощники доступа ----------------------------------------------
    local function factionOf(ply)
        if not IsValid(ply) or not istable(Factions) then return nil end
        local sid, s64 = ply:SteamID(), ply:SteamID64()
        for name, f in pairs(Factions) do
            if istable(f) and istable(f.Members) and (f.Members[sid] or f.Members[s64]) then
                return name
            end
        end
        return nil
    end
    BC.FactionOf = factionOf

    function BC.IsJournalist(ply)
        if IsValid(ply) and ply:IsSuperAdmin() then return true end
        local fac = factionOf(ply)
        return fac ~= nil and (BC.Cfg.journalists or {})[fac] == true
    end
    function BC.IsAlerter(ply)
        if IsValid(ply) and ply:IsSuperAdmin() then return true end
        local fac = factionOf(ply)
        return fac ~= nil and (BC.Cfg.alerters or {})[fac] == true
    end

    local function rpName(ply)
        local n = ply:GetNWString("GRM_RPName", "")
        return (n ~= "" and n) or ply:Nick()
    end
    BC.RPName = rpName

    local function cfgKey(pos)
        return string.format("%.0f_%.0f_%.0f", pos.x, pos.y, pos.z)
    end
    function BC.MicName(ent)
        local n = (BC.Cfg.micNames or {})[cfgKey(ent:GetPos())]
        if isstring(n) and n ~= "" then return n end
        return "ГРМ-Радио"
    end
    function BC.SetMicName(ent, name)
        name = string.Trim(tostring(name or ""))
        name = string.sub(name, 1, 40)
        BC.Cfg.micNames[cfgKey(ent:GetPos())] = name
        BC.SaveCfg()
        if IsValid(ent) then ent:SetNWString("GRM_BC_Station", name) end
    end

    -- эфир ------------------------------------------------------------
    function BC.StartLive(ply, ent)
        if not IsValid(ply) or not IsValid(ent) then return end
        -- спикер может вести только один эфир
        for _, m in ipairs(ents.FindByClass("grm_broadcast_mic")) do
            if m ~= ent and m.BCSpeaker == ply and m.BCLive then BC.StopLive(m, "переключение") end
        end
        if ent.BCLive and IsValid(ent.BCSpeaker) and ent.BCSpeaker ~= ply then
            if GRM.Notify then GRM.Notify(ply, "Микрофон занят: в эфире " .. rpName(ent.BCSpeaker), 255, 120, 90) end
            return false
        end
        ent.BCLive = true
        BC.LiveCount = (BC.LiveCount or 0) + 1
        ent.BCSpeaker = ply
        ply._grmBCMic = ent
        ent:SetNWBool("GRM_BC_Live", true)
        ent:SetNWString("GRM_BC_Speaker", rpName(ply))
        ent:SetNWString("GRM_BC_Last", "")
        ent:EmitSound("npc/overwatch/radiovoice/on3.wav", 65, 100)
        hook.Run("GRM_BC_BroadcastStart", ply, tostring(ent:GetNWString("GRM_BC_Station", "ГРМ-Радио")))
        local pa = ent:GetNWBool("GRM_BC_PA", false)
        if GRM.Notify then
            if pa then
                GRM.Notify(ply, "ВЫ В ГРОМКОЙ СВЯЗИ: голос звучит усиленно из всех сетевых громкоговорителей (с эффектом рупора). Не отходите от микрофона.", 120, 200, 255)
            else
                GRM.Notify(ply, "ВЫ В ЭФИРЕ: " .. ent:GetNWString("GRM_BC_Station", "ГРМ-Радио") .. ". Говорите в голосовой чат и пишите текстовые реплики — их услышат/прочтут слушатели у радиоприёмников. Не отходите от микрофона.", 100, 220, 100)
            end
        end
        -- предупреждения инфраструктуры (RadioNet, Код 85)
        local RNm = GRM.RadioNet
        if RNm then
            if pa then
                local any = false
                for _, s in ipairs(ents.FindByClass("grm_loudspeaker")) do
                    if RNm.SpeakerActive and RNm.SpeakerActive(s) then any = true break end
                end
                if not any and GRM.Notify then
                    GRM.Notify(ply, "ВНИМАНИЕ: ни один громкоговоритель не подключён к радиосети — громкая связь никуда не уйдёт! (стойка/антенна: /rn_status)", 255, 140, 90)
                end
            elseif RNm.MicLink and RNm.MicLink(ent) < 2 and GRM.Notify then
                GRM.Notify(ply, "ВНИМАНИЕ: микрофон вне радиосети (стойка/передатчик далеко или обесточены) — приёмники НЕ примут эфир, вас слышно только рядом. Диагностика: /rn_status", 255, 140, 90)
            end
        end
        return true
    end

    function BC.StopLive(ent, reason)
        if not IsValid(ent) then return end
        ent.BCLive = false
        BC.LiveCount = math.max(0, (BC.LiveCount or 1) - 1)
        local sp = ent.BCSpeaker
        ent.BCSpeaker = nil
        if IsValid(sp) then
            sp._grmBCMic = nil
            if GRM.Notify then GRM.Notify(sp, "Эфир завершён" .. (reason and (" (" .. tostring(reason) .. ")") or "") .. ".", 255, 200, 90) end
        end
        ent:SetNWBool("GRM_BC_Live", false)
        ent:SetNWString("GRM_BC_Speaker", "")
        ent:EmitSound("npc/overwatch/radiovoice/off2.wav", 65, 100)
    end

    -- сторож: спикер отошёл/умер → эфир гаснет
    timer.Create("GRM_BC_LiveWatch", 0.5, 0, function()
        -- Аудит нагрузки 18.08: сканирование микрофонов шло каждые полсекунды
        -- даже когда в эфире никого. Счётчик живых эфиров ведёт сам модуль.
        if (BC.LiveCount or 0) <= 0 then return end
        local mics=GRM.Perf and GRM.Perf.Entities and GRM.Perf.Entities("grm_broadcast_mic")or ents.FindByClass("grm_broadcast_mic")
        for _, ent in ipairs(mics) do
            if ent.BCLive then
                local sp = ent.BCSpeaker
                if not IsValid(sp) or not sp:Alive()
                    or sp:GetPos():DistToSqr(ent:GetPos()) > BC.MicMaxDist * BC.MicMaxDist then
                    BC.StopLive(ent, "спикер покинул микрофон")
                end
            end
        end
    end)

    -- голос через радио ------------------------------------------------
    hook.Add("PlayerCanHearPlayersVoice", "GRM_BC_Voice", function(listener, speaker)
        -- RadioNet (Код 85) — единая точка маршрутов голоса в сборке
        if GRM.RadioNet and GRM.RadioNet.VoiceRoute then return end
        if not IsValid(listener) or not IsValid(speaker) then return end
        local mic = speaker._grmBCMic
        if not IsValid(mic) or not mic.BCLive or mic.BCSpeaker ~= speaker then return end
        -- Проверка слышимости зовётся на каждого слушателя каждой реплики:
        -- полный скан приёмников заменён event-реестром.
        local radios = (GRM.Perf and GRM.Perf.Entities) and GRM.Perf.Entities("grm_radio") or ents.FindByClass("grm_radio")
        for _, r in ipairs(radios) do
            if IsValid(r) and r:GetNWBool("GRM_BC_On", false) and r:GetNWInt("GRM_BC_Mic", 0) == mic:EntIndex() then
                if listener:GetPos():DistToSqr(r:GetPos()) <= BC.ReceiveRadius * BC.ReceiveRadius then
                    return true, false -- слышно глобально (эффект радио)
                end
            end
        end
    end)

    -- текстовые заголовки ----------------------------------------------
    local function listenersOf(micIdx)
        local RNm = GRM.RadioNet
        if RNm and RNm.MicLink then
            local mic = Entity(micIdx)
            if not IsValid(mic) or RNm.MicLink(mic) < 2 then return {} end -- вне сети текст не ретранслируется
        end
        local set, out = {}, {}
        for _, r in ipairs(ents.FindByClass("grm_radio")) do
            local covered = true
            if RNm and RNm.ReceiverOK then covered = RNm.ReceiverOK(r) end
            if covered and r:GetNWBool("GRM_BC_On", false) and r:GetNWInt("GRM_BC_Mic", 0) == micIdx then
                for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                    if not set[p] and p:GetPos():DistToSqr(r:GetPos()) <= BC.ReceiveRadius * BC.ReceiveRadius then
                        set[p] = true
                        out[#out + 1] = p
                    end
                end
            end
        end
        return out
    end

    -- слушатели ГРОМКОЙ СВЯЗИ: все рядом с громкоговорителями в сети
    local function paListenersOf()
        local RNm = GRM.RadioNet
        local set, out = {}, {}
        for _, s in ipairs(ents.FindByClass("grm_loudspeaker")) do
            local active = true
            if RNm and RNm.SpeakerActive then active = RNm.SpeakerActive(s) end
            if active then
                for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                    if not set[p] and p:GetPos():DistToSqr(s:GetPos()) <= BC.SpeakerRadius * BC.SpeakerRadius then
                        set[p] = true
                        out[#out + 1] = p
                    end
                end
            end
        end
        return out
    end
    BC.PAListeners = paListenersOf

    hook.Add("PlayerSay", "GRM_BC_SayRelay", function(ply, text)
        if not IsValid(ply) then return end
        local mic = ply._grmBCMic
        if not IsValid(mic) or not mic.BCLive or mic.BCSpeaker ~= ply then return end
        text = string.Trim(tostring(text or ""))
        if text == "" or string.sub(text, 1, 1) == "/" or string.sub(text, 1, 1) == "!" then return end
        text = string.sub(text, 1, 200)
        local station = mic:GetNWString("GRM_BC_Station", "ГРМ-Радио")
        local name = rpName(ply)
        mic:SetNWString("GRM_BC_Last", os.date("%H:%M ") .. text)
        local plys
        if mic:GetNWBool("GRM_BC_PA", false) then
            plys = paListenersOf()
            station = "ГРОМКАЯ СВЯЗЬ: " .. station
        else
            plys = listenersOf(mic:EntIndex())
        end
        if #plys > 0 then
            net.Start(NET_LINE)
                net.WriteString(station)
                net.WriteString(name)
                net.WriteString(text)
            net.Send(plys)
        end
    end)

    -- массовое оповещение -----------------------------------------------
    -- Код 87: пятый параметр targetGroup (группа RadioNet) — оповещение
    -- звучит только из громкоговорителей этой группы (пульт радиосети).
    function BC.SendAlert(fromName, text, global, srcPly, targetGroup)
        text = string.Trim(tostring(text or ""))
        if #text < 3 then return false, "Текст оповещения короче 3 символов" end
        text = string.sub(text, 1, 240)
        targetGroup = (isstring(targetGroup) and targetGroup ~= "") and targetGroup or nil
        local targets = {}
        if global then
            for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do targets[#targets + 1] = p end
        else
            local RNm = GRM.RadioNet
            local speakers = ents.FindByClass("grm_loudspeaker")
            if #speakers == 0 then return false, "В городе не установлено громкоговорителей (/speaker_add + /permadd). Глобально: /alertall" end
            local marked, anyActive = {}, false
            for _, sp in ipairs(speakers) do
                local usable = true
                if RNm and RNm.SpeakerActive then usable = RNm.SpeakerActive(sp) end
                if usable and targetGroup then
                    usable = (RNm and RNm.DeviceInGroupForEnt) and RNm.DeviceInGroupForEnt(sp, targetGroup) or false
                end
                if usable then
                    anyActive = true
                    sp:SetNWBool("GRM_BC_Alert", true)
                    sp:EmitSound("ambient/alarms/warningbell1.wav", 78, 100)
                    timer.Create("GRM_BC_SpkOff" .. sp:EntIndex(), BC.AlertDuration, 1, function()
                        if IsValid(sp) then sp:SetNWBool("GRM_BC_Alert", false) end
                    end)
                    for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                        if not marked[p] and p:GetPos():DistToSqr(sp:GetPos()) <= BC.SpeakerRadius * BC.SpeakerRadius then
                            marked[p] = true
                            targets[#targets + 1] = p
                        end
                    end
                end
            end
            if not anyActive then
                if targetGroup then
                    return false, "В группе «" .. targetGroup .. "» нет активных сетевых громкоговорителей (состав — на пульте радиосети). Глобально: /alertall"
                end
                return false, "Ни один громкоговоритель не подключён к радиосети (нужны активная стойка/антенна — диагностика: /rn_status). Глобально: /alertall"
            end
        end
        if #targets == 0 then return false, "Рядом с громкоговорителями" .. (targetGroup and (" группы «" .. targetGroup .. "»") or "") .. " никого нет. Глобально: /alertall" end
        net.Start(NET_ALERT)
            net.WriteString(fromName)
            net.WriteString(text)
        net.Send(targets)
        if IsValid(srcPly) then hook.Run("GRM_BC_Alert", srcPly, text, global and true or false) end
        -- Код 87: журнал радиосети (пеленг: позиция источника + качество)
        if GRM.RadioNet and GRM.RadioNet.LogEvent then
            GRM.RadioNet.LogEvent("alert", tostring(fromName),
                IsValid(srcPly) and srcPly:SteamID64() or "",
                IsValid(srcPly) and srcPly:GetPos() or nil,
                "оповещение" .. (targetGroup and (" → группа «" .. targetGroup .. "»") or (global and " (глобальное)" or ""))
                    .. ": «" .. string.sub(text, 1, 60) .. "» (" .. #targets .. " чел.)")
        end
        return true, "Оповещение передано (" .. #targets .. " чел.)" .. (targetGroup and (" → группа «" .. targetGroup .. "»") or "")
    end

    -- админ-команды доступа ----------------------------------------------
    local function listToText(tbl)
        local out = {}
        for k, v in pairs(tbl or {}) do if v then out[#out + 1] = k end end
        table.sort(out)
        return (#out > 0) and table.concat(out, ", ") or "(пусто — только суперадмины)"
    end

    -- спавн энтити --------------------------------------------------------
    local function spawnAtAim(ply, class, label)
        if not IsValid(ply) or not ply:IsSuperAdmin() then
            if IsValid(ply) then ply:PrintMessage(HUD_PRINTTALK, "[" .. label .. "] Только для суперадмина.") end
            return
        end
        local tr = util.TraceLine({ start = ply:GetShootPos(), endpos = ply:GetShootPos() + ply:GetAimVector() * 320, filter = ply })
        if not tr.Hit then ply:PrintMessage(HUD_PRINTTALK, "[" .. label .. "] Прицельтесь в пол/стену рядом.") return end
        local nt = ents.Create(class)
        if not IsValid(nt) then ply:PrintMessage(HUD_PRINTTALK, "[" .. label .. "] Энтити не зарегистрирована!") return end
        nt:SetPos(tr.HitPos + tr.HitNormal * 2)
        local ang = (ply:GetPos() - tr.HitPos):Angle()
        nt:SetAngles(Angle(0, ang.y, 0))
        nt:Spawn() nt:Activate()
        BC.PersistAdd(nt) -- персистентность вшита: /permadd больше не нужен
        ply:PrintMessage(HUD_PRINTTALK, "[" .. label .. "] Установлен и СОХРАНЁН на карте автоматически. Снять: /" .. (class == "grm_radio" and "radio" or class == "grm_broadcast_mic" and "radiomic" or "speaker") .. "_remove прицелом.")
        if GRM.Notify then GRM.Notify(ply, label .. " установлен (персистентно).", 100, 220, 100) end
    end
    local function removeAtAim(ply, class, label)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        local tr = util.TraceLine({ start = ply:GetShootPos(), endpos = ply:GetShootPos() + ply:GetAimVector() * 220, filter = ply })
        local ent = tr.Entity
        if not IsValid(ent) or ent:GetClass() ~= class then
            ply:PrintMessage(HUD_PRINTTALK, "[" .. label .. "] В прицеле нет такой энтити.")
            return
        end
        BC.PersistRemove(ent)
        ent:Remove()
        ply:PrintMessage(HUD_PRINTTALK, "[" .. label .. "] Удалён (и из персистента).")
    end

    hook.Add("PlayerSay", "GRM_BC_TransformCmds", function(ply, text, teamSays)
        local datapack = { tostring(text or ""), SkipPlayerSay = false }
            if not istable(datapack) then return end
            local msg = datapack[1]
            if not isstring(msg) then return end
            -- EasyChat-дружественно: обрабатываем команды ПЕРЕД PlayerSay,
            -- чтобы их никто не проглотил по цепочке хуков
            if BC.HandleChat and BC.HandleChat(ply, msg) then
                datapack[1] = ""
                datapack.SkipPlayerSay = true
            end

        if datapack.SkipPlayerSay == true then return "" end
    end)

    hook.Add("PlayerSay", "GRM_BC_AdminCmds", function(ply, text)
        if BC.HandleChat and BC.HandleChat(ply, text) then return "" end
    end)
    -- единый обработчик чат-команд (вызывается из PlayerSayTransform и PlayerSay)
    function BC.HandleChat(ply, text)
        local t = string.Trim(text or "")
        local low = string.lower(t)
        -- оповещения
        if string.sub(low, 1, 7) == "/alert " then
            if not BC.IsAlerter(ply) then ply:PrintMessage(HUD_PRINTTALK, "[Оповещение] Нет доступа (см. /alert_allow у суперадмина).") return true end
            local ok, msg = BC.SendAlert(rpName(ply), string.sub(t, 8), false, ply)
            ply:PrintMessage(HUD_PRINTTALK, "[Оповещение] " .. tostring(msg))
            return true
        end
        if string.sub(low, 1, 10) == "/alertall " then
            if not BC.IsAlerter(ply) then ply:PrintMessage(HUD_PRINTTALK, "[Оповещение] Нет доступа.") return true end
            local ok, msg = BC.SendAlert(rpName(ply), string.sub(t, 11), true, ply)
            ply:PrintMessage(HUD_PRINTTALK, "[Оповещение] " .. tostring(msg))
            return true
        end
        if low == "/alert" or low == "/alertall" then
            ply:PrintMessage(HUD_PRINTTALK, "[Оповещение] Формат: /alert текст оповещения (возле громкоговорителей) или /alertall текст (всем игрокам)")
            return true
        end
        -- доступ журналистов/оповестителей (суперадмин)
        local function editAccess(tbl, name, add)
            if not ply:IsSuperAdmin() then ply:PrintMessage(HUD_PRINTTALK, "[Радио] Только для суперадмина.") return true end
            local fname = string.Trim(name or "")
            if fname == "" or not (istable(Factions) and Factions[fname]) then
                ply:PrintMessage(HUD_PRINTTALK, "[Радио] Укажите точное имя фракции (см. /factions).")
                return true
            end
            tbl[fname] = add and true or nil
            BC.SaveCfg()
            ply:PrintMessage(HUD_PRINTTALK, "[Радио] " .. (add and "Выдан доступ: " or "Отобран доступ: ") .. fname)
            return true
        end
        if string.sub(low, 1, 13) == "/bcast_allow " and editAccess(BC.Cfg.journalists, string.sub(t, 14), true) then return true end
        if string.sub(low, 1, 12) == "/bcast_deny " and editAccess(BC.Cfg.journalists, string.sub(t, 13), false) then return true end
        if string.sub(low, 1, 13) == "/alert_allow " and editAccess(BC.Cfg.alerters, string.sub(t, 14), true) then return true end
        if string.sub(low, 1, 12) == "/alert_deny " and editAccess(BC.Cfg.alerters, string.sub(t, 13), false) then return true end
        if low == "/bcast_list" then
            ply:PrintMessage(HUD_PRINTTALK, "[Радио] Журналисты: " .. listToText(BC.Cfg.journalists) .. " | Оповестители: " .. listToText(BC.Cfg.alerters))
            return true
        end
        -- спавн/удаление энтити
        if low == "/radiomic_add" then spawnAtAim(ply, "grm_broadcast_mic", "Микрофон") return true end
        if low == "/radiomic_remove" then removeAtAim(ply, "grm_broadcast_mic", "Микрофон") return true end
        if low == "/radio_add" then spawnAtAim(ply, "grm_radio", "Радиоприёмник") return true end
        if low == "/radio_remove" then removeAtAim(ply, "grm_radio", "Радиоприёмник") return true end
        if low == "/speaker_add" then spawnAtAim(ply, "grm_loudspeaker", "Громкоговоритель") return true end
        if low == "/speaker_remove" then removeAtAim(ply, "grm_loudspeaker", "Громкоговоритель") return true end
        return false
    end

    -- меню приёмника: открытие/настройка ---------------------------------
    function BC.OpenRadioMenu(ply, ent)
        local stations = {}
        for _, m in ipairs(ents.FindByClass("grm_broadcast_mic")) do
            stations[#stations + 1] = {
                idx = m:EntIndex(),
                station = m:GetNWString("GRM_BC_Station", "ГРМ-Радио"),
                live = m:GetNWBool("GRM_BC_Live", false),
                speaker = m:GetNWString("GRM_BC_Speaker", ""),
            }
        end
        net.Start(NET_RADIO_OPEN)
            net.WriteUInt(ent:EntIndex(), 16)
            net.WriteInt(ent:GetNWInt("GRM_BC_Mic", 0), 16)
            net.WriteTable(stations)
        net.Send(ply)
    end

    net.Receive(NET_RADIO_SET, function(_, ply)
        if not IsValid(ply) then return end
        local ent = Entity(net.ReadUInt(16))
        local micIdx = net.ReadInt(16)
        if not IsValid(ent) or ent:GetClass() ~= "grm_radio" then return end
        if ply:GetPos():DistToSqr(ent:GetPos()) > 250 * 250 then return end
        if micIdx <= 0 then
            ent:SetNWBool("GRM_BC_On", false)
            ent:SetNWInt("GRM_BC_Mic", 0)
            if GRM.Notify then GRM.Notify(ply, "Приёмник выключен.", 220, 180, 90) end
            return
        end
        local mic = Entity(micIdx)
        if not IsValid(mic) or mic:GetClass() ~= "grm_broadcast_mic" then return end
        ent:SetNWBool("GRM_BC_On", true)
        ent:SetNWInt("GRM_BC_Mic", micIdx)
        if GRM.Notify then GRM.Notify(ply, "Настроен на станцию: " .. mic:GetNWString("GRM_BC_Station", "ГРМ-Радио") .. ". Слышимость ~" .. BC.ReceiveRadius .. " юнитов.", 100, 220, 100) end
    end)

    -- меню микрофона -------------------------------------------------------
    function BC.OpenMicMenu(ply, ent)
        local RNm = GRM.RadioNet
        local link = 2
        if RNm and RNm.MicLink then link = RNm.MicLink(ent) end
        net.Start(NET_MIC_OPEN)
            net.WriteUInt(ent:EntIndex(), 16)
            net.WriteString(ent:GetNWString("GRM_BC_Station", "ГРМ-Радио"))
            net.WriteBool(ent:GetNWBool("GRM_BC_Live", false))
            net.WriteString(ent:GetNWString("GRM_BC_Speaker", ""))
            net.WriteBool(ent:GetNWBool("GRM_BC_PA", false))
            net.WriteUInt(link, 2)
        net.Send(ply)
    end

    net.Receive(NET_MIC_SET, function(_, ply)
        if not IsValid(ply) then return end
        local ent = Entity(net.ReadUInt(16))
        local act = net.ReadString()
        local name = net.ReadString()
        if not IsValid(ent) or ent:GetClass() ~= "grm_broadcast_mic" then return end
        if ply:GetPos():DistToSqr(ent:GetPos()) > BC.MicMaxDist * BC.MicMaxDist then return end
        if not BC.IsJournalist(ply) then
            if GRM.Notify then GRM.Notify(ply, "Нет доступа к микрофону (журналисты: /bcast_allow у суперадмина).", 255, 120, 90) end
            return
        end
        if act == "name" then
            BC.SetMicName(ent, name)
            ply:PrintMessage(HUD_PRINTTALK, "[Радио] Станция переименована: " .. BC.MicName(ent))
        elseif act == "pa-on" then
            -- громкая связь = массовое оповещение голосом: доступ как у /alert
            if not BC.IsAlerter(ply) then
                if GRM.Notify then GRM.Notify(ply, "Громкая связь доступна оповестителям (/alert_allow Фракция — у суперадмина).", 255, 120, 90) end
                return
            end
            ent:SetNWBool("GRM_BC_PA", true)
            if GRM.Notify then GRM.Notify(ply, "Режим ГРОМКАЯ СВЯЗЬ: эфир пойдёт через сетевые громкоговорители города.", 120, 200, 255) end
        elseif act == "pa-off" then
            ent:SetNWBool("GRM_BC_PA", false)
            if GRM.Notify then GRM.Notify(ply, "Режим радиоэфира восстановлен.", 220, 190, 100) end
        elseif act == "start" then
            BC.StartLive(ply, ent)
        elseif act == "stop" then
            if ent.BCSpeaker == ply or ply:IsSuperAdmin() then BC.StopLive(ent, "ведущий завершил") end
        end
    end)

    -- консольное оповещение (из server console / rcon)
    concommand.Add("grm_alert", function(ply, _, args)
        if IsValid(ply) and not BC.IsAlerter(ply) then return end
        local ok, msg = BC.SendAlert(IsValid(ply) and rpName(ply) or "Сервер", table.concat(args or {}, " "), true, ply)
        if IsValid(ply) then ply:PrintMessage(HUD_PRINTTALK, "[Оповещение] " .. tostring(msg))
        else print("[GRM Broadcast] " .. tostring(msg)) end
    end)

    print("[GRM Broadcast] Сервер v" .. BC.Version .. " загружен")
end

-- ============================================================
-- КЛИЕНТ
-- ============================================================
if CLIENT then
    surface.CreateFont("GRMBC_Title",  { font = "Roboto", size = 20, weight = 800, extended = true })
    surface.CreateFont("GRMBC_Sub",    { font = "Roboto", size = 15, weight = 600, extended = true })
    surface.CreateFont("GRMBC_Normal", { font = "Roboto", size = 13, weight = 500, extended = true })
    surface.CreateFont("GRMBC_Alert",  { font = "Roboto", size = 26, weight = 900, extended = true })
    surface.CreateFont("GRMBC_AlertS", { font = "Roboto", size = 16, weight = 600, extended = true })

    local C = {
        bg    = Color(20, 24, 32, 252),
        head  = Color(28, 34, 46, 255),
        panel = Color(32, 38, 50, 245),
        acc   = Color(70, 150, 240),
        green = Color(60, 190, 110),
        red   = Color(220, 75, 70),
        yellow= Color(230, 180, 60),
        text  = Color(240, 245, 250),
        dim   = Color(160, 170, 185),
    }

    -- Кнопка — общая фабрика GRM.UI (§5.4): копии в четырёх модулях
    -- различались только шрифтом и создавали по два Color() на кадр.
    local function mkBtn(p, txt, col)
        return GRM.UI.Button(p, txt, "GRMBC_Sub", col or C.acc)
    end

    local function mkFrame(w, h, title)
        local f = vgui.Create("DFrame")
        f:SetTitle("") f:SetSize(w, h) f:Center() f:MakePopup() f:ShowCloseButton(false)
        f.Paint = function(_, pw, ph)
            draw.RoundedBox(8, 0, 0, pw, ph, C.bg)
            draw.RoundedBoxEx(8, 0, 0, pw, 40, C.head, true, true, false, false)
            draw.SimpleText(title, "GRMBC_Title", 14, 20, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        local x = vgui.Create("DButton", f)
        x:SetText("X") x:SetFont("GRMBC_Title") x:SetTextColor(color_white)
        x:SetPos(w - 40, 6) x:SetSize(32, 26)
        x.DoClick = function() f:Close() end
        x.Paint = function(self, pw, ph) draw.RoundedBox(4, 0, 0, pw, ph, self:IsHovered() and C.red or Color(45, 52, 68)) end
        return f
    end

    -- ---------- меню приёмника ----------
    net.Receive(NET_RADIO_OPEN, function()
        local entIdx = net.ReadUInt(16)
        local curMic = net.ReadInt(16)
        local stations = net.ReadTable() or {}

        local f = mkFrame(560, 420, "Радиоприёмник")
        local info = vgui.Create("DLabel", f)
        info:SetPos(14, 46) info:SetSize(532, 20) info:SetFont("GRMBC_Normal") info:SetTextColor(C.dim)
        info:SetText("Слышимость около приёмника. Подстроитесь к живой станции.")

        local sc = vgui.Create("DScrollPanel", f)
        sc:SetPos(10, 70) sc:SetSize(540, 280)

        local function send(micIdx)
            net.Start(NET_RADIO_SET)
                net.WriteUInt(entIdx, 16)
                net.WriteInt(micIdx, 16)
            net.SendToServer()
            f:Close()
        end

        if #stations == 0 then
            local none = vgui.Create("DLabel", sc)
            none:Dock(TOP) none:SetTall(30) none:SetFont("GRMBC_Sub") none:SetTextColor(C.dim)
            none:SetText("Станций не найдено (микрофоны не установлены).")
        end
        for _, st in ipairs(stations) do
            local row = vgui.Create("DPanel", sc)
            row:Dock(TOP) row:SetTall(56) row:DockMargin(0, 0, 0, 4)
            local tuned = (curMic == st.idx)
            row.Paint = function(_, pw, ph)
                draw.RoundedBox(6, 0, 0, pw, ph, tuned and Color(44, 66, 96) or C.panel)
                draw.SimpleText(st.station, "GRMBC_Sub", 10, 16, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                local live = st.live and ("В ЭФИРЕ: " .. (st.speaker ~= "" and st.speaker or "ведущий")) or "молчит"
                local lc = st.live and C.red or C.dim
                draw.SimpleText(live, "GRMBC_Normal", 10, 40, lc, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            local b = mkBtn(row, tuned and "Слушаете" or "Слушать", tuned and C.green or C.acc)
            b:SetPos(440, 12) b:SetSize(90, 32) b:SetFont("GRMBC_Normal")
            b.DoClick = function() send(st.idx) end
        end

        local bOff = mkBtn(f, "Выключить приёмник", C.red)
        bOff:SetPos(10, 366) bOff:SetSize(200, 36)
        bOff.DoClick = function() send(0) end
    end)

    -- ---------- меню микрофона ----------
    net.Receive(NET_MIC_OPEN, function()
        local entIdx = net.ReadUInt(16)
        local station = net.ReadString()
        local live = net.ReadBool()
        local speaker = net.ReadString()
        local pamode = net.ReadBool()
        local link = net.ReadUInt(2)

        local f = mkFrame(560, 470, "Микрофонная стойка (эфир)")
        local st = vgui.Create("DLabel", f)
        st:SetPos(14, 46) st:SetSize(532, 20) st:SetFont("GRMBC_Sub")
        st:SetText(live and ("СТАТУС: " .. (pamode and "ГРОМКАЯ СВЯЗЬ — " or "В ЭФИРЕ — ") .. speaker) or "СТАТУС: молчит")
        st:SetTextColor(live and C.red or C.dim)

        -- сеть (RadioNet, Код 85)
        local netl = vgui.Create("DLabel", f)
        netl:SetPos(14, 70) netl:SetSize(532, 18) netl:SetFont("GRMBC_Normal")
        if link >= 2 then
            netl:SetText("Радиосеть: ПОДКЛЮЧЁН (эфир уйдёт в город)")
            netl:SetTextColor(C.green)
        elseif link == 1 then
            netl:SetText("Радиосеть: передатчик рядом, но ВНЕ СЕТИ (проверьте стойку!)")
            netl:SetTextColor(C.yellow)
        else
            netl:SetText("Радиосеть: НЕТ СВЯЗИ — эфир в город не выйдет (стойка/передатчик)")
            netl:SetTextColor(C.red)
        end

        local lbl = vgui.Create("DLabel", f)
        lbl:SetPos(14, 94) lbl:SetSize(532, 18) lbl:SetFont("GRMBC_Normal") lbl:SetTextColor(C.dim)
        lbl:SetText("Позывной станции (виден слушателям у приёмников):")

        local entry = vgui.Create("DTextEntry", f)
        entry:SetPos(14, 116) entry:SetSize(400, 32) entry:SetFont("GRMBC_Sub")
        entry:SetText(station)

        local bName = mkBtn(f, "Сохранить", C.acc)
        bName:SetPos(424, 116) bName:SetSize(122, 32)
        bName.DoClick = function()
            net.Start(NET_MIC_SET)
                net.WriteUInt(entIdx, 16)
                net.WriteString("name")
                net.WriteString(entry:GetValue() or "")
            net.SendToServer()
        end

        -- режим: радиоэфир / громкая связь (Код 85)
        local bMode = mkBtn(f, pamode and "РЕЖИМ: ГРОМКАЯ СВЯЗЬ (клик — в радиоэфир)" or "РЕЖИМ: РАДИОЭФИР (клик — громкая связь)", pamode and Color(90, 130, 220) or C.acc)
        bMode:SetPos(14, 160) bMode:SetSize(532, 38)
        bMode.DoClick = function()
            net.Start(NET_MIC_SET)
                net.WriteUInt(entIdx, 16)
                net.WriteString(pamode and "pa-off" or "pa-on")
                net.WriteString("")
            net.SendToServer()
            f:Close()
        end

        local bLive = mkBtn(f, live and "ЗАВЕРШИТЬ ЭФИР" or (pamode and "НАЧАТЬ ГРОМКУЮ СВЯЗЬ" or "НАЧАТЬ ЭФИР"), live and C.red or C.green)
        bLive:SetPos(14, 208) bLive:SetSize(532, 46)
        bLive.DoClick = function()
            net.Start(NET_MIC_SET)
                net.WriteUInt(entIdx, 16)
                net.WriteString(live and "stop" or "start")
                net.WriteString("")
            net.SendToServer()
            f:Close()
        end

        local hint = vgui.Create("DLabel", f)
        hint:SetPos(14, 266) hint:SetSize(532, 188) hint:SetFont("GRMBC_Normal") hint:SetTextColor(C.dim)
        hint:SetText("РАДИОЭФИР: голос и реплики слышат/читают слушатели у приёмников. ГРОМКАЯ СВЯЗЬ (доступ оповестителя — /alert_allow): голос звучит УСИЛЕННО из всех громкоговорителей города с эффектом рупора. Оба режима требуют живой радиосети: серверная стойка + (передатчик) + антенны — иначе эфир услышат только стоящие рядом. Качество сигнала на краю покрытия антенн падает: голос слушателей хрипит и выпадает. Не отходите дальше ~2.5 м от микрофона — эфир прервётся сам. Доступ к эфиру: /bcast_allow ИмяФракции.")
        hint:SetWrap(true) hint:SetAutoStretchVertical(true)
    end)

    -- ---------- текстовая строка эфира ----------
    net.Receive(NET_LINE, function()
        local station = net.ReadString()
        local name = net.ReadString()
        local text = net.ReadString()
        chat.AddText(Color(90, 170, 250), "[📻 " .. station .. "] ",
            Color(240, 220, 140), name .. ": ",
            color_white, text)
        surface.PlaySound("buttons/button16.wav")
    end)

    -- ---------- баннер массового оповещения ----------
    local alertData = nil
    net.Receive(NET_ALERT, function()
        alertData = {
            from = net.ReadString(),
            text = net.ReadString(),
            untilT = CurTime() + BC.AlertDuration,
        }
        surface.PlaySound("npc/overwatch/radiovoice/on3.wav")
    end)

    -- Альфа баннера гаснет к концу оповещения — один скретч-Color на три
    -- места (все потребляются немедленно; §6.1.8)
    local BC_C = Color(0, 0, 0, 255)
    local function bcCol(r, g, b, al)
        BC_C.r = r
        BC_C.g = g
        BC_C.b = b
        BC_C.a = al
        return BC_C
    end

    hook.Add("HUDPaint", "GRM_BC_AlertBanner", function()
        if not alertData then return end
        local left = alertData.untilT - CurTime()
        if left <= 0 then alertData = nil return end
        local a = math.Clamp(left * 2, 0, 1) * 255
        local blink = (math.sin(CurTime() * 8) + 1) * 0.5
        local w = math.min(900, ScrW() - 120)
        local x, y = (ScrW() - w) / 2, 60
        draw.RoundedBox(8, x, y, w, 92, bcCol(140, 20, 20, a * 0.92))
        surface.SetDrawColor(255, 80 + blink * 120, 60, a)
        surface.DrawOutlinedRect(x, y, w, 92, 3)
        draw.SimpleText("ВНИМАНИЕ! ОПОВЕЩЕНИЕ ГОРОДА", "GRMBC_Alert", ScrW() / 2, y + 18, bcCol(255, 235, 230, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(alertData.text, "GRMBC_AlertS", ScrW() / 2, y + 52, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("Источник: " .. alertData.from, "GRMBC_Normal", ScrW() / 2, y + 76, bcCol(255, 200, 190, a), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end)

    print("[GRM Broadcast] Клиент v" .. BC.Version .. " загружен")
end

-- Вечер-18: единый словарь slash-команд: имена живого PlayerSay-обработчика
-- вносятся во внешний реестр библиотеки (на режиме сверка идёт ДО ParseSay —
-- без регистрации команда стала бы «неизвестной»).
if GRM and GRM.Chat and GRM.Chat.RegisterExternalCommands then
    GRM.Chat.RegisterExternalCommands({ "/alert", "/alertall" })
end
