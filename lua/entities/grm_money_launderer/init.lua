--[[--------------------------------------------------------------------
    grm_money_launderer — init (находка 179e)
----------------------------------------------------------------------]]
AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

util.AddNetworkString("GRM_Heist_Open")     -- меню отмывщика
util.AddNetworkString("GRM_Heist_Action")   -- действия
util.AddNetworkString("GRM_Heist_Event")    -- баннер/музыка на весь сервер

-- Находка 179t: музыка ивента. Файл — MP3 (music/hl2_song20_submix0.mp3),
-- а Source-движок НЕ умеет зацикливать MP3 (EnableLooping работает только
-- для WAV) — файл проигрывался один раз (~2 сек) и обрывался. Лечение:
-- прекэш звука + «сторожевой» таймер, который держит музыку непрерывно
-- (перезапускает, как только патч перестал играть), пока идёт ивент.
-- Находка 180d: музыка ивента — ПО ОБРАЗЦУ kom_hour (factions extensions):
-- звук играет СЕРВЕР напрямую КАЖДОМУ игроку (p:EmitSound) — приватный
-- звук на полной громкости, БЕЗ позиционного затухания: все слышат
-- одинаково на любой точке карты. Никаких таймеров/патчей/сторожей.
local HEIST_MUSIC = "music/hl2_song20_submix0.mp3"
-- Находка 180e: имя GPS-маркера цели ограбления (удаляется при завершении)
local HEIST_TARGET_NAME = "РЕЙХСБАНК — ЦЕЛЬ ОГРАБЛЕНИЯ"

-- Находка 179v: анти-дубль музыки НА СЕРВЕРЕ. Отмывщиков может быть
-- несколько — глобальный реестр владельца музыки ивента: новый ивент
-- глушит музыку предыдущего (иначе несколько музык = эхо/наложение).
GRM = GRM or {}
GRM.HeistMusicOwner = GRM.HeistMusicOwner or nil -- ent, играющий музыку ивента

-- Находка 180c: ГЛОБАЛЬНЫЙ КУЛДАУН ОГРАБЛЕНИЯ (анти-злоупотребление).
-- После завершения ивента ставится таймер (настраиваемый суперадмином,
-- по умолчанию 30 минут) — пока он не истёк, взять задание на ограбление
-- НЕЛЬЗЯ ни у одного отмывщика (КД глобальный, unix-время — переживает
-- рестарт сервера). Хранится в data/grm_heist_cooldown.json.
GRM.HeistCooldownUntil = GRM.HeistCooldownUntil or 0    -- unix: до этого времени КД активен
GRM.HeistCooldownDuration = GRM.HeistCooldownDuration or 1800 -- секунд (дефолт 30 мин)
local HEIST_COOLDOWN_FILE = "grm_heist_cooldown.json"

local function notify(ply, msg, r, g, b)
    if IsValid(ply) and GRM and GRM.Notify then
        GRM.Notify(ply, msg, r or 200, g or 200, b or 200)
    end
end

local function money(n)
    return GRM and GRM.Format and GRM.Format(math.floor(tonumber(n) or 0)) or (tostring(math.floor(tonumber(n) or 0)) .. " GRM")
end

-- Находка 180c: КД-файл. Чтение через jsonT (ignoreConversions=true, н65),
-- запись с read-back. КД переживает рестарт сервера (unix-время).
local function loadCooldown()
    if not file.Exists(HEIST_COOLDOWN_FILE, "DATA") then return end
    local ok, data = pcall(util.JSONToTable, file.Read(HEIST_COOLDOWN_FILE, "DATA") or "", false, true)
    if ok and istable(data) then
        GRM.HeistCooldownUntil = math.max(0, tonumber(data["until"]) or 0)
        GRM.HeistCooldownDuration = math.max(0, tonumber(data.duration) or 1800)
        if GRM.HeistCooldownUntil > os.time() then
            print(("[GRM Heist] КД ограбления активен: осталось %d сек"):format(GRM.HeistCooldownUntil - os.time()))
        end
    end
end
local function saveCooldown()
    local ok, raw = pcall(util.TableToJSON, { ["until"] = GRM.HeistCooldownUntil or 0, duration = GRM.HeistCooldownDuration or 1800 }, true)
    if ok and isstring(raw) then
        file.Write(HEIST_COOLDOWN_FILE, raw)
        local chk = file.Read(HEIST_COOLDOWN_FILE, "DATA")
        if chk ~= raw then print("[GRM Heist][!] КД-файл не подтверждён записью (read-back)") end
    end
end

-- Находка 180h: учёт киллов криминала госниками. Если гос.структура
-- (отмечена в настройках отмывщика) убивает участника ивента — фракции
-- убийцы засчитывается килл (для пропорциональной награды за победу).
hook.Add("PlayerDeath", "GRM_Heist_GovKills", function(victim, inflictor, attacker)
    if not IsValid(victim) or not victim:IsPlayer() then return end
    if not IsValid(attacker) or not attacker:IsPlayer() then return end
    -- найти активный отмывщик
    local active = nil
    for _, ent in ipairs(ents.FindByClass("grm_money_launderer")) do
        if IsValid(ent) and ent:GetEventActive() then active = ent break end
    end
    if not IsValid(active) then return end
    -- жертва должна быть участником ивента (криминал)
    local sid = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(victim)) or victim:SteamID64() or ""
    sid = tostring(sid)
    if not (active.Participants and active.Participants[sid]) then return end
    if active:RegisterGovKill(attacker) then
        local fac = active:FactionOf(attacker)
        print(("[GRM Heist] Гос.структура [%s] убила криминала (%s) — киллов: %d"):format(
            tostring(fac or "?"), tostring(victim:Nick() or "?"), active.GovKills and active.GovKills[fac] or 0))
    end
end)

function ENT:Initialize()
    local mdl = self.Model
    if not util.IsValidModel(mdl) then
        mdl = self.ModelFallback
        print("[GRM Launderer] ВНИМАНИЕ: модель не найдена, фолбэк '" .. tostring(mdl) .. "'")
    end
    self:SetModel(mdl)
    -- Находка 179g/179i: как у ТОРГАШЕЙ (grm_vendor) — НЕ физический проп,
    -- а «стоящая» энтити: BBOX + MOVETYPE_NONE + NPC-коллизия + автопрокачка
    -- кадров анимации + idle-последовательность (иначе модель человека
    -- стоит в Т-позе).
    self:SetSolid(SOLID_BBOX)
    self:SetMoveType(MOVETYPE_NONE)
    self:SetCollisionGroup(COLLISION_GROUP_NPC)
    self:SetUseType(SIMPLE_USE)
    self:SetAutomaticFrameAdvance(true)

    self:SetEnabled(true)
    self:SetEventActive(false)
    self:SetMinParticipants(2)
    self:SetGoalMoney(500000)
    self:SetMoneyHeld(0)
    self:SetParticipantCount(0)
    self:SetAllowedFactions("")
    self:SetWinnerFaction("")
    self:SetHeistTargetPos(Vector(0, 0, 0))
    self:SetPreStartAt(0) -- Находка 180f: ожидание перед стартом не идёт
    self:SetGovFactions("") -- Находка 180h: гос.структуры (чеклист суперадмина)
    self.Participants = self.Participants or {}   -- [sid] = faction
    self.ParticipantNames = self.ParticipantNames or {} -- Находка 180f: [sid] = РП-имя
    self.FactionDelivered = self.FactionDelivered or {} -- [faction] = amount
    self.GovKills = self.GovKills or {} -- Находка 180h: [фракция] = киллов по криминалу

    -- Находка 180d: прекэш музыки как у kom_hour (factions extensions):
    -- Sound() — глобальный прекэш GMod + util.PrecacheSound (страховка).
    if SERVER then
        pcall(function()
            if Sound then Sound(HEIST_MUSIC) end
            if util.PrecacheSound then util.PrecacheSound(HEIST_MUSIC) end
        end)
    end

    self:SetupIdleAnimation()
end

-- Находка 179i: idle-анимация как у торгашей (grm_vendor:SetupIdleAnimation)
function ENT:SetupIdleAnimation()
    local sequence = self:SelectWeightedSequence(ACT_IDLE)
    if not sequence or sequence < 0 then
        for _, name in ipairs({ "idle_all", "idle", "idle_unarmed", "stand", "ref", "idle_01" }) do
            sequence = self:LookupSequence(name)
            if sequence and sequence >= 0 then break end
        end
    end
    if sequence and sequence >= 0 then
        self:ResetSequence(sequence)
        self:SetPlaybackRate(1)
        self:ResetSequenceInfo()
    end
end

function ENT:OnRemove()
    -- если шёл ивент — гасим музыку/баннер у всех
    if self:GetEventActive() then
        self:BroadcastEvent("end", "ОГРАБЛЕНИЕ ПРЕРВАНО", "", false)
    end
    self:StopHeistMusic()
    -- Находка 180e: маркер цели ограбления исчезает и при прерывании
    if GRM.Minimap and GRM.Minimap.RemoveTempPoint then
        GRM.Minimap.RemoveTempPoint(HEIST_TARGET_NAME)
    end
end

function ENT:CanManage(ply)
    return IsValid(ply) and ply:IsSuperAdmin()
end

-- Находка 179g: список имён ВСЕХ существующих фракций (для чекбоксов)
function ENT:FactionList()
    local out = {}
    if istable(Factions) then
        for name in pairs(Factions) do
            if istable(Factions[name]) then out[#out + 1] = tostring(name) end
        end
    end
    table.sort(out)
    return out
end

-- фракция игрока (через Factions/Identity, как в сканере)
function ENT:FactionOf(ply)
    if not (Factions and IsValid(ply) and ply.SteamID) then return nil end
    for fName, fData in pairs(Factions) do
        local member = GRM.Identity and GRM.Identity.FactionMember and GRM.Identity.FactionMember(fData, ply)
        if not member and not GRM.Identity then
            member = fData.Members[ply:SteamID()] or fData.Members[ply:SteamID64()]
        end
        if istable(fData) and istable(fData.Members) and member then
            return fName
        end
    end
    return nil
end

function ENT:IsFactionAllowed(facName)
    local list = string.Trim(tostring(self:GetAllowedFactions() or ""))
    if list == "" then return true end
    for f in string.gmatch(list, "([^,]+)") do
        if string.Trim(f) == facName then return true end
    end
    return false
end

-- Находка 180h: фракция отмечена суперадмином как ГОС.СТРУКТУРА?
function ENT:IsGovFaction(facName)
    if facName == nil then return false end
    local list = string.Trim(tostring(self:GetGovFactions() or ""))
    if list == "" then return false end
    for f in string.gmatch(list, "([^,]+)") do
        if string.Trim(f) == facName then return true end
    end
    return false
end

-- Находка 180h: зарегистрировать килл госника по участнику-криминалу.
function ENT:RegisterGovKill(attacker)
    if not IsValid(attacker) or not attacker:IsPlayer() then return false end
    local fac = self:FactionOf(attacker)
    if not self:IsGovFaction(fac) then return false end
    self.GovKills = self.GovKills or {}
    self.GovKills[fac] = (self.GovKills[fac] or 0) + 1
    return true
end

function ENT:IsParticipant(ply)
    if not IsValid(ply) then return false end
    local sid = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply)) or ply:SteamID64() or ""
    return self.Participants[tostring(sid)] ~= nil
end

-- Находка 179f: цель ивента — установленная точка, иначе ближайшее
-- хранилище (Рейхсбанк), иначе nil.
function ENT:HeistTarget()
    local tp = self:GetHeistTargetPos()
    if tp and (tp.x ~= 0 or tp.y ~= 0 or tp.z ~= 0) then
        return tp
    end
    local best, bestD = nil, math.huge
    for _, ent in ipairs(ents.FindByClass("grm_bank_vault")) do
        if IsValid(ent) then
            local d = self:GetPos():DistToSqr(ent:GetPos())
            if d < bestD then best, bestD = ent, d end
        end
    end
    if IsValid(best) then return best:GetPos() end
    return nil
end

function ENT:SetHeistTarget(pos)
    self:SetHeistTargetPos(pos or Vector(0, 0, 0))
    if GRM.PermData and GRM.PermData.UpdateEntry then GRM.PermData.UpdateEntry(self) end
    return true
end

-- Раздать маркеры цели участникам (GPS-точка на мини-карте) + уведомление
function ENT:SendHeistTargetMarkers()
    local target = self:HeistTarget()
    if not target then return end
    local dur = math.max(60, tonumber(self.HeistDuration) or 3000)
    local tName = HEIST_TARGET_NAME
    local coord = ("X %.0f  Y %.0f"):format(target.x, target.y)
    for sid in pairs(self.Participants) do
        local p = nil
        for _, pl in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(pl) then
                local key = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(pl)) or pl:SteamID64() or ""
                if tostring(key) == tostring(sid) then p = pl break end
            end
        end
        if IsValid(p) then
            if GRM.Minimap and GRM.Minimap.AddTempPoint then
                GRM.Minimap.AddTempPoint(tName, target, dur)
                if GRM.Minimap.SendTo then GRM.Minimap.SendTo(p) end
            end
            if GRM.Notify then
                GRM.Notify(p, "ЦЕЛЬ ОГРАБЛЕНИЯ: Рейхсбанк (хранилище) — " .. coord .. ". Двигайтесь к локации!", 255, 200, 100)
            end
        end
    end
end

-- ══ ИВЕНТ ══════════════════════════════════════════════════
function ENT:BroadcastEvent(state, title, subtitle, music)
    net.Start("GRM_Heist_Event")
        net.WriteString(state)         -- "start" | "end"
        net.WriteString(tostring(title or ""))
        net.WriteString(tostring(subtitle or ""))
        net.WriteBool(music == true)
        net.WriteFloat(self:GetEventEndsAt() or 0)
        -- Находка 180f: список РП-имён участников («криминал») — для HUD
        net.WriteTable(state == "start" and self:ParticipantList() or {})
    net.Broadcast()
end

function ENT:StartEvent()
    if self:GetEventActive() then return end
    self:SetPreStartAt(0) -- Находка 180f: ожидание завершено — старт
    self:SetEventActive(true)
    self:SetEventEndsAt(CurTime() + self.HeistDuration)
    self:SetMoneyHeld(0)
    self.FactionDelivered = {}
    self:SetWinnerFaction("")
    -- Находка 180d: музыка — ПО ОБРАЗЦУ kom_hour: играем напрямую КАЖДОМУ
    -- игроку (p:EmitSound, громкость 127) — приватный звук без позиционного
    -- затухания, все слышат одинаково на любой точке карты. Без патчей,
    -- таймеров и сторожей. Файл длинный — играет один раз.
    self:StopHeistMusic()
    -- Находка 179v: музыку ивента уже играет ДРУГОЙ отмывщик — глушим её
    -- (глобальный реестр HeistMusicOwner; иначе несколько музык = эхо).
    if GRM.HeistMusicOwner and IsValid(GRM.HeistMusicOwner) and GRM.HeistMusicOwner ~= self then
        pcall(function() GRM.HeistMusicOwner:StopHeistMusic() end)
    end
    for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
        if IsValid(p) and p:IsPlayer() then
            p:EmitSound(HEIST_MUSIC, 127, 110)
        end
    end
    GRM.HeistMusicOwner = self
    -- баннер на весь сервер
    self:BroadcastEvent("start", "НАЧАТ ИВЕНТ: ОГРАБЛЕНИЕ",
        "Участники: " .. self:GetParticipantCount() .. "  •  Цель: " .. money(self:GetGoalMoney()) ..
        "  •  Время: 50 минут  •  Сдайте деньги отмывщику  •  ДВИГАЙТЕСЬ К ЛОКАЦИИ!", true)
    print(("[GRM Heist] ИВЕНТ ОГРАБЛЕНИЕ начат (отмывщик %s, участников %d, цель %s)")
        :format(self:EntIndex(), self:GetParticipantCount(), money(self:GetGoalMoney())))
    -- Находка 179f: грабители получают GPS-маркер на Рейхсбанк (хранилище)
    self:SendHeistTargetMarkers()
end

-- Находка 180d: остановка музыки — как у kom_hour: каждому игроку
-- StopSound (приватный звук глушится напрямую). Без патчей и таймеров.
function ENT:StopHeistMusic()
    -- Находка 179v: этот отмывщик больше не владеет музыкой ивента
    if GRM.HeistMusicOwner == self then GRM.HeistMusicOwner = nil end
    for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
        if IsValid(p) and p:IsPlayer() then
            p:StopSound(HEIST_MUSIC)
        end
    end
    self:StopSound(HEIST_MUSIC)
end

function ENT:EndEvent(criminalsWin, reason)
    -- Находка 180g: принудительная остановка суперадмином работает и при
    -- активном ожидании старта (PreStartAt), и при идущем ивенте.
    if not self:GetEventActive() and not criminalsWin then
        self:SetPreStartAt(0)
        return
    end
    local winnerFac = tostring(self:GetWinnerFaction() or "")
    local title, sub
    if reason == "superadmin" then
        -- Находка 180g: команда /heist_stop — явный заголовок
        title = "ИВЕНТ ОСТАНОВЛЕН СУПЕРАДМИНОМ"
        sub = tostring(sub or "Принудительная остановка")
    elseif criminalsWin and winnerFac ~= "" then
        title = "ОГРАБЛЕНИЕ: ПОБЕДА ФРАКЦИИ [" .. winnerFac .. "]"
        sub = "Деньги доставлены отмывщику: " .. money(self:GetMoneyHeld())
    elseif criminalsWin then
        title = "ОГРАБЛЕНИЕ: ПОБЕДА ПРЕСТУПНИКОВ"
        sub = "Деньги доставлены отмывщику: " .. money(self:GetMoneyHeld())
    else
        title = "ОГРАБЛЕНИЕ: ПОБЕДА ГОСУДАРСТВЕННЫХ СТРУКТУР"
        sub = tostring(reason or "Деньги не доставлены отмывщику за отведённое время")
    end
    self:BroadcastEvent("end", title, sub, false)
    -- Находка 180d: музыка останавливается как у kom_hour (StopSound всем)
    self:StopHeistMusic()
    -- Находка 180e: GPS-маркер цели ограбления ИСЧЕЗАЕТ при завершении
    if GRM.Minimap and GRM.Minimap.RemoveTempPoint then
        GRM.Minimap.RemoveTempPoint(HEIST_TARGET_NAME)
    end
    -- Находка 180h: если победили ГОС.СТРУКТУРЫ (криминал не сдал цель) —
    -- выплачиваем им награду в бюджет фракций: 200.000–1.000.000,
    -- пропорционально доставленному отмывщику (MoneyHeld), распределение
    -- по киллам криминала (каждая отмеченная фракция учитывается).
    if not criminalsWin and reason ~= "superadmin" then
        local held = math.max(0, math.floor(tonumber(self:GetMoneyHeld()) or 0))
        local reward = math.Clamp(held, self.GovRewardMin or 200000, self.GovRewardMax or 1000000)
        local govFactions = {}
        for f in string.gmatch(tostring(self:GetGovFactions() or ""), "([^,]+)") do
            f = string.Trim(f)
            if f ~= "" then govFactions[#govFactions + 1] = f end
        end
        if reward > 0 and #govFactions > 0 then
            local kills = self.GovKills or {}
            local totalKills = 0
            for _, f in ipairs(govFactions) do totalKills = totalKills + (kills[f] or 0) end
            local payouts = {}
            if totalKills > 0 then
                -- пропорционально киллам
                local given = 0
                for i, f in ipairs(govFactions) do
                    local share = math.floor(reward * (kills[f] or 0) / totalKills)
                    payouts[f] = share
                    given = given + share
                end
                -- остаток от округления — первой фракции
                if given < reward and #govFactions > 0 then
                    payouts[govFactions[1]] = (payouts[govFactions[1]] or 0) + (reward - given)
                end
            else
                -- киллов нет — поровну между всеми гос.фракциями
                local share = math.floor(reward / #govFactions)
                local given = 0
                for i, f in ipairs(govFactions) do
                    local s = (i == #govFactions) and (reward - given) or share
                    payouts[f] = s
                    given = given + s
                end
            end
            for f, amount in pairs(payouts) do
                if amount and amount > 0 then
                    if GRM.FactionBudgetAdd then
                        GRM.FactionBudgetAdd(f, amount, "Ограбление: защита города (киллов: " .. (kills[f] or 0) .. ")")
                    end
                    print(("[GRM Heist] Гос.структура [%s] получила %d GRM в бюджет (киллов: %d)"):format(
                        f, amount, kills[f] or 0))
                    -- уведомление членам фракции
                    for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                        if IsValid(p) and p:IsPlayer() and self:FactionOf(p) == f then
                            notify(p, "Гос.структура [" .. f .. "] получила " .. money(amount) .. " в бюджет за защиту города (киллов: " .. (kills[f] or 0) .. ")", 100, 220, 130)
                        end
                    end
                end
            end
        end
    end
    self.GovKills = {}

    -- Находка 180i: выплата при победе КРИМИНАЛА — не меньше x2 от
    -- награбленного (MoneyHeld). Распределение между фракциями-
    -- участниками пропорционально сданному (FactionDelivered), в бюджет
    -- фракций (как госникам в 180h); остаток округления — победившей.
    if criminalsWin and reason ~= "superadmin" then
        local held = math.max(0, math.floor(tonumber(self:GetMoneyHeld()) or 0))
        local payout = held * (self.CrimRewardMultiplier or 2)
        local delivered = self.FactionDelivered or {}
        local totalDelivered = 0
        for _, amt in pairs(delivered) do
            totalDelivered = totalDelivered + math.max(0, math.floor(tonumber(amt) or 0))
        end
        if payout > 0 and totalDelivered > 0 then
            local given = 0
            local names = {}
            for f in pairs(delivered) do names[#names + 1] = f end
            table.sort(names)
            for _, f in ipairs(names) do
                local amt = math.max(0, math.floor(tonumber(delivered[f]) or 0))
                if amt > 0 then
                    local share = math.floor(payout * amt / totalDelivered)
                    if share > 0 and GRM.FactionBudgetAdd then
                        GRM.FactionBudgetAdd(f, share, "Ограбление: победа криминала (сдано: " .. amt .. ")")
                        print(("[GRM Heist] Криминал [%s] получил %d GRM в бюджет (сдано: %d)"):format(f, share, amt))
                        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                            if IsValid(p) and p:IsPlayer() and self:FactionOf(p) == f then
                                notify(p, "Криминальная фракция [" .. f .. "] получила " .. money(share) .. " в бюджет за успешное ограбление!", 255, 200, 100)
                            end
                        end
                    end
                    given = given + share
                end
            end
            -- остаток от округления — победившей фракции
            local winner = tostring(self:GetWinnerFaction() or "")
            if given < payout and winner ~= "" and (delivered[winner] or 0) > 0 and GRM.FactionBudgetAdd then
                GRM.FactionBudgetAdd(winner, payout - given, "Ограбление: победа криминала (остаток)")
                print(("[GRM Heist] Криминал [%s] получил остаток %d GRM в бюджет"):format(winner, payout - given))
            end
        end
    end

    print(("[GRM Heist] ИВЕНТ ОГРАБЛЕНИЕ окончен: %s (%s)"):format(title, sub))
    self:SetEventActive(false)
    self:SetEventEndsAt(0)
    self:SetPreStartAt(0)
    self:SetMoneyHeld(0)
    self:SetWinnerFaction("")
    self.Participants = {}
    self.ParticipantNames = {}
    self.FactionDelivered = {}
    self:SetParticipantCount(0)

    -- Находка 180c: после завершения ограбления (победа/время вышло/
    -- прервано) ставим ГЛОБАЛЬНЫЙ кулдаун — никто не сможет запустить
    -- новое ограбление, пока не истечёт таймер (анти-злоупотребление).
    -- Находка 180g: при принудительной остановке (/heist_stop) КД НЕ
    -- ставится — команда для тестирования, ивент можно запускать снова.
    if reason ~= "superadmin" then
        GRM.HeistCooldownUntil = os.time() + math.max(60, GRM.HeistCooldownDuration or 1800)
        saveCooldown()
        print(("[GRM Heist] КД ограбления установлен: %d сек (до unix %d)"):format(
            math.max(60, GRM.HeistCooldownDuration or 1800), GRM.HeistCooldownUntil))
    end
end
function ENT:TakeJob(ply)
    if not self:GetEnabled() then notify(ply, "Отмывщик не принимает заказы.", 255, 190, 90) return false end
    -- Находка 180c: глобальный КД ограбления — нельзя запустить новое
    -- ограбление, пока не истёк таймер после предыдущего.
    local cdLeft = (GRM.HeistCooldownUntil or 0) - os.time()
    if cdLeft > 0 then
        local mm, ss = math.floor(cdLeft / 60), cdLeft % 60
        notify(ply, string.format("Ограбление на перезагрузке. Новое можно начать через %02d:%02d.", mm, ss), 255, 160, 90)
        return false
    end
    if self:GetEventActive() then notify(ply, "Ивент уже идёт — набор закрыт.", 255, 190, 90) return false end
    if self:IsParticipant(ply) then notify(ply, "Вы уже в списке участников.", 200, 220, 255) return false end
    local fac = self:FactionOf(ply)
    if not self:IsFactionAllowed(fac) then
        notify(ply, "Ваша фракция не может взять задание на ограбление.", 255, 120, 100)
        return false
    end
    local sid = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply)) or ply:SteamID64() or ""
    sid = tostring(sid)
    self.Participants[sid] = tostring(fac or "")
    -- Находка 180f: храним РП-имя участника (для списка «криминала»)
    local rpName = ""
    if ply.GetNWString then rpName = tostring(ply:GetNWString("GRM_RPName", "") or "") end
    if rpName == "" then rpName = ply.Nick and tostring(ply:Nick() or "") or sid end
    self.ParticipantNames = self.ParticipantNames or {}
    self.ParticipantNames[sid] = rpName
    self:SetParticipantCount(self:GetParticipantCount() + 1)
    notify(ply, "Задание принято! Участников: " .. self:GetParticipantCount() .. " / минимум " .. self:GetMinParticipants(), 100, 220, 130)

    local minP = math.max(1, self:GetMinParticipants())
    if self:GetParticipantCount() >= minP then
        -- Находка 180f: минимум набран — НЕ стартуем сразу, а даём 40 сек
        -- добежать/вступить остальным (PreStartAt); старт — в Think.
        local pre = self:GetPreStartAt() or 0
        if pre <= 0 then
            self:SetPreStartAt(CurTime() + (self.PreStartDelay or 40))
            for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                if IsValid(p) then
                    notify(p, "Минимум участников набран! Ивент начнётся через " .. (self.PreStartDelay or 40) .. " сек — успевайте вступить.", 200, 220, 255)
                end
            end
        else
            notify(ply, "Минимум уже набран — ивент начнётся через " .. math.max(0, math.ceil(pre - CurTime())) .. " сек.", 200, 220, 255)
        end
    else
        self:SetPreStartAt(0)
        notify(ply, "Нужно ещё " .. (minP - self:GetParticipantCount()) .. " участников — ивент начнётся автоматически.", 200, 220, 255)
    end
    return true
end

-- Находка 179m/179p: отмена участия — игрок выходит из ивента.
-- Находка 179p: во время ивента отмена ЗАПРЕЩЕНА (сервер тоже отклоняет).
function ENT:LeaveJob(ply)
    if not IsValid(ply) then return false end
    if self:GetEventActive() then
        notify(ply, "ОТМЕНА УЧАСТИЯ В МОМЕНТ ИВЕНТА ЗАПРЕЩЕНА.", 255, 120, 100)
        return false
    end
    local sid = (GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply)) or ply:SteamID64() or ""
    sid = tostring(sid)
    if not self.Participants[sid] then
        notify(ply, "Вы не участвуете в ограблении.", 200, 220, 255)
        return false
    end
    self.Participants[sid] = nil
    if self.ParticipantNames then self.ParticipantNames[sid] = nil end
    self:SetParticipantCount(math.max(0, self:GetParticipantCount() - 1))
    notify(ply, "Вы вышли из ограбления. Участников: " .. self:GetParticipantCount(), 255, 190, 90)

    -- если ивент ещё не начался и участников стало меньше минимума — ничего,
    -- набор продолжится; если ивент УЖЕ идёт — выход не отменяет ивент,
    -- но игрок больше не участник (победа/маркеры — только оставшимся).
    if not self:GetEventActive() then
        local minP = math.max(1, self:GetMinParticipants())
        if self:GetParticipantCount() < minP then
            -- Находка 180f: ожидание перед стартом отменяется (набор продолжится)
            self:SetPreStartAt(0)
            notify(ply, "Участников меньше минимума (" .. minP .. ") — ивент не запустится, пока не наберётся.", 200, 220, 255)
        end
    end
    return true
end

-- Сдать деньги отмывщику (сумка + паллеты рядом). Возвращает сумму.
function ENT:DepositFromBag(ply)
    if not IsValid(ply) then return 0 end
    if not self:GetEventActive() then
        notify(ply, "Ивент не идёт — сдать деньги некому.", 255, 190, 90)
        return 0
    end
    local total = 0
    -- 1) сумка ограбления
    if GRM.Customization and GRM.Customization.LootBagGet then
        local bag = GRM.Customization.LootBagGet(ply)
        if bag > 0 then
            GRM.Customization.LootBagSet(ply, 0)
            total = total + bag
        end
    end
    -- 2) паллеты и деньги рядом (радиус 200)
    if GRM.Economy and GRM.Economy.SpawnCashAt then
        for _, ent in ipairs(ents.FindInSphere(self:GetPos(), 200)) do
            if IsValid(ent) and not ent:IsPlayer() and not ent:IsNPC() and not ent:IsWorld() then
                local cls = ent:GetClass()
                if cls == "grm_vault_cash" or cls == "grm_money_drop" then
                    local amt = math.max(0, math.floor(tonumber(ent:GetAmount() or 0)))
                    if amt > 0 then
                        total = total + amt
                        ent:Remove()
                    end
                end
            end
        end
    end
    if total <= 0 then
        notify(ply, "Нет денег: сумка пуста и рядом нет паллет.", 255, 190, 90)
        return 0
    end
    local fac = tostring(self:FactionOf(ply) or "")
    self.FactionDelivered[fac] = (self.FactionDelivered[fac] or 0) + total
    self:SetMoneyHeld(self:GetMoneyHeld() + total)
    -- победитель — фракция, сдавшая больше всех
    local bestFac, bestAmt = "", -1
    for f, amt in pairs(self.FactionDelivered) do
        if amt > bestAmt then bestFac, bestAmt = f, amt end
    end
    self:SetWinnerFaction(bestFac)
    notify(ply, "Сдано отмывщику: " .. money(total) .. "  (всего: " .. money(self:GetMoneyHeld()) .. " / " .. money(self:GetGoalMoney()) .. ")", 100, 220, 130)
    if self:GetMoneyHeld() >= self:GetGoalMoney() then
        self:EndEvent(true, "Цель достигнута")
    end
    return total
end

function ENT:Think()
    if self:GetEventActive() then
        local ends = self:GetEventEndsAt() or 0
        if ends > 0 and CurTime() >= ends then
            self:EndEvent(self:GetMoneyHeld() >= self:GetGoalMoney(), "Время вышло")
        end
    else
        -- Находка 180f: минимум набран — таймер ожидания 40 сек; по
        -- истечении стартуем. Вступить можно до самого старта.
        local pre = self:GetPreStartAt() or 0
        if pre > 0 and CurTime() >= pre then
            self:StartEvent()
        end
    end
    self:NextThink(CurTime() + 1)
    return true
end

-- Находка 180f: список участников (РП-имена + фракция) для меню и HUD
function ENT:ParticipantList()
    local out = {}
    for sid, fac in pairs(self.Participants) do
        local name = self.ParticipantNames and self.ParticipantNames[sid] or nil
        out[#out + 1] = { name = tostring(name or sid), faction = tostring(fac or "") }
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- ══ МЕНЮ ═══════════════════════════════════════════════════
function ENT:SendMenu(ply)
    if not IsValid(ply) then return end
    net.Start("GRM_Heist_Open")
        net.WriteEntity(self)
        net.WriteTable({
            enabled = self:GetEnabled(),
            eventActive = self:GetEventActive(),
            minParticipants = self:GetMinParticipants(),
            participantCount = self:GetParticipantCount(),
            goalMoney = self:GetGoalMoney(),
            moneyHeld = self:GetMoneyHeld(),
            allowedFactions = tostring(self:GetAllowedFactions() or ""),
            eventEndsAt = self:GetEventEndsAt() or 0,
            isParticipant = self:IsParticipant(ply),
            canManage = self:CanManage(ply),
            myFaction = tostring(self:FactionOf(ply) or ""),
            factionAllowed = self:IsFactionAllowed(self:FactionOf(ply)),
            -- находка 179f: цель ивента (маркер GPS)
            hasTarget = self:HeistTarget() ~= nil,
            targetPos = self:HeistTarget(),
            -- находка 179g: список ВСЕХ существующих фракций для чекбоксов
            factionsList = self:FactionList(),
            -- находка 180c: глобальный КД ограбления (для UI)
            cooldownLeft = math.max(0, (GRM.HeistCooldownUntil or 0) - os.time()),
            cooldownDuration = GRM.HeistCooldownDuration or 1800,
            -- находка 180f: список РП-имён участников + таймер ожидания старта
            participantList = self:ParticipantList(),
            preStartLeft = math.max(0, (self:GetPreStartAt() or 0) - CurTime()),
            -- находка 180h: гос.структуры (чеклист суперадмина) + киллы
            govFactions = tostring(self:GetGovFactions() or ""),
            govKills = self.GovKills or {},
        })
    net.Send(ply)
end

function ENT:Use(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if (self._grmUseT or 0) > CurTime() then return end
    self._grmUseT = CurTime() + 0.4
    self:SendMenu(ply)
end

-- Находка 179r: сохранение настроек в перм-базу с ОБРАТНОЙ СВЯЗЬЮ.
-- Раньше «СОХРАНИТЬ НАСТРОЙКИ» молча ничего не писал, если перм-записи
-- нет (UpdateEntry no-op) — после рестарта настройки слетали. Теперь
-- Upsert сам создаёт запись, если её нет, и игрок ВИДИТ результат.
local function persistConfig(ent, ply)
    if not (GRM.PermData and GRM.PermData.Upsert) then
        notify(ply, "Перм-система недоступна — настройки не переживут рестарт!", 255, 190, 90)
        return
    end
    local res = GRM.PermData.Upsert(ent)
    if res == "added" then
        notify(ply, "Перм-запись СОЗДАНА — настройки переживут рестарт.", 100, 220, 130)
    elseif res == "updated" then
        notify(ply, "Перм-запись ОБНОВЛЕНА — настройки переживут рестарт.", 100, 220, 130)
    elseif res == "limit" then
        notify(ply, "Лимит перм-записей на карту — настройки НЕ сохранены. Снимите лишние (/permremove).", 255, 120, 100)
    elseif res == "savefail" then
        notify(ply, "Ошибка записи перм-базы — смотри консоль сервера.", 255, 120, 100)
    end
end

net.Receive("GRM_Heist_Action", function(_, ply)
    if not IsValid(ply) then return end
    local ent = net.ReadEntity()
    local action = net.ReadString()
    if not IsValid(ent) or ent:GetClass() ~= "grm_money_launderer" then return end
    if ply:GetPos():DistToSqr(ent:GetPos()) > (ent.JobRadius * ent.JobRadius) then return end

    if action == "job" then
        ent:TakeJob(ply)
    elseif action == "leave" then
        -- Находка 179m: отмена участия
        ent:LeaveJob(ply)
    elseif action == "deposit" then
        ent:DepositFromBag(ply)
    elseif action == "set_target" then
        -- находка 179f: цель = то, на что смотрит суперадмин (хранилище)
        if not ent:CanManage(ply) then notify(ply, "Только суперадмин.", 255, 100, 100) return end
        local tr = ply:GetEyeTrace()
        local hit = tr and tr.Entity
        if IsValid(hit) then
            ent:SetHeistTarget(hit:GetPos())
            persistConfig(ent, ply)
            notify(ply, "Цель ивента установлена: " .. tostring(hit:GetClass() or "?") .. " (" .. ("%.0f %.0f %.0f"):format(hit:GetPos().x, hit:GetPos().y, hit:GetPos().z) .. ")", 100, 220, 130)
        else
            notify(ply, "Наведите прицел на хранилище/место цели.", 255, 190, 90)
        end
    elseif action == "clear_target" then
        if not ent:CanManage(ply) then notify(ply, "Только суперадмин.", 255, 100, 100) return end
        ent:SetHeistTarget(Vector(0, 0, 0))
        persistConfig(ent, ply)
        notify(ply, "Цель ивента сброшена (авто: ближайшее хранилище).", 100, 220, 255)
    elseif action == "config" then
        if not ent:CanManage(ply) then notify(ply, "Только суперадмин.", 255, 100, 100) return end
        -- Находка 179r: 16 бит (было 8 — минимум >255 обрезался)
        local minP = math.max(1, math.floor(tonumber(net.ReadUInt(16)) or 2))
        local goal = math.max(1000, math.floor(tonumber(net.ReadUInt(32)) or 500000))
        local allowed = string.sub(string.Trim(net.ReadString() or ""), 1, 200)
        ent:SetMinParticipants(minP)
        ent:SetGoalMoney(goal)
        ent:SetAllowedFactions(allowed)
        persistConfig(ent, ply)
        notify(ply, "Отмывщик настроен: минимум " .. minP .. ", цель " .. money(goal) .. ", фракции [" .. allowed .. "]", 100, 220, 130)
    elseif action == "config_full" then
        -- Находка 179g: полная настройка — минимум, цель, СПИСОК фракций (чекбоксы)
        if not ent:CanManage(ply) then notify(ply, "Только суперадмин.", 255, 100, 100) return end
        local minP = math.max(1, math.floor(tonumber(net.ReadUInt(16)) or 2))
        local goal = math.max(1000, math.floor(tonumber(net.ReadUInt(32)) or 500000))
        local allowedTbl = net.ReadTable() or {}
        local names = {}
        for _, n in ipairs(allowedTbl) do
            if isstring(n) and string.Trim(n) ~= "" then names[#names + 1] = string.Trim(n) end
        end
        table.sort(names)
        local allowed = table.concat(names, ",")
        -- Находка 180c: длительность КД (минуты) — 0 = не менять
        local cdMin = math.max(0, math.floor(tonumber(net.ReadUInt(16)) or 0))
        -- Находка 180h: чеклист гос.структур (таблица имён)
        local govTbl = net.ReadTable() or {}
        local govNames = {}
        for _, n in ipairs(govTbl) do
            if isstring(n) and string.Trim(n) ~= "" then govNames[#govNames + 1] = string.Trim(n) end
        end
        table.sort(govNames)
        ent:SetMinParticipants(minP)
        ent:SetGoalMoney(goal)
        ent:SetAllowedFactions(allowed)
        ent:SetGovFactions(table.concat(govNames, ","))
        if cdMin > 0 then
            GRM.HeistCooldownDuration = math.max(1, math.min(240, cdMin)) * 60
            saveCooldown()
        end
        persistConfig(ent, ply)
        notify(ply, "Отмывщик настроен: минимум " .. minP .. ", цель " .. money(goal) .. ", фракций: " .. #names .. ", КД: " .. math.floor((GRM.HeistCooldownDuration or 1800) / 60) .. " мин, ГОС: " .. #govNames, 100, 220, 130)
    end
    ent:SendMenu(ply)
end)

-- ══ КОМАНДА ЦЕЛИ (находка 179f) ═══════════════════════════
-- /heist_target — суперадмин целится в хранилище (или место), цель
-- ставится ближайшему отмывщику. /heist_target_clear — сброс.
local function heistTargetCmd(ply)
    if not IsValid(ply) or not ply:IsSuperAdmin() then
        if IsValid(ply) then notify(ply, "Только суперадмин.", 255, 100, 100) end
        return
    end
    local tr = ply:GetEyeTrace()
    local hit = tr and tr.Entity
    local launderer = E and E.FindNearestLaunderer and E.FindNearestLaunderer(ply, 2000)
    if not IsValid(launderer) then notify(ply, "Рядом нет отмывщика денег.", 255, 190, 90) return end
    if IsValid(hit) then
        launderer:SetHeistTarget(hit:GetPos())
        notify(ply, "Цель ивента [" .. tostring(hit:GetClass() or "?") .. "] установлена отмывщику.", 100, 220, 130)
    else
        notify(ply, "Наведите прицел на хранилище/место цели.", 255, 190, 90)
    end
end
local function heistTargetClearCmd(ply)
    if not IsValid(ply) or not ply:IsSuperAdmin() then
        if IsValid(ply) then notify(ply, "Только суперадмин.", 255, 100, 100) end
        return
    end
    local launderer = E and E.FindNearestLaunderer and E.FindNearestLaunderer(ply, 2000)
    if IsValid(launderer) then
        launderer:SetHeistTarget(Vector(0, 0, 0))
        notify(ply, "Цель ивента сброшена (авто: ближайшее хранилище).", 100, 220, 255)
    end
end
concommand.Add("grm_heist_target", function(ply) heistTargetCmd(ply) end)
concommand.Add("grm_heist_target_clear", function(ply) heistTargetClearCmd(ply) end)

-- ══ ПРИНУДИТЕЛЬНЫЙ СТАРТ/СТОП (находка 180g) ══════════════
-- /heist_force — суперадмин: запуск ивента, ИГНОРИРУЯ КД и любые условия
-- (для тестирования). /heist_stop — принудительное завершение.
function ENT:ForceStart(ply)
    if self:GetEventActive() then
        notify(ply, "Ивент уже идёт.", 255, 190, 90)
        return false
    end
    -- игнорируем КД полностью
    GRM.HeistCooldownUntil = 0
    saveCooldown()
    self:SetPreStartAt(0)
    self:StartEvent()
    notify(ply, "Ивент ОГРАБЛЕНИЕ принудительно запущен (КД/условия проигнорированы).", 100, 220, 130)
    return true
end
function ENT:ForceStop(ply)
    self:SetPreStartAt(0)
    if not self:GetEventActive() then
        notify(ply, "Ивент не запущен (или не идёт ожидание).", 255, 190, 90)
        return false
    end
    self:EndEvent(false, "superadmin")
    notify(ply, "Ивент принудительно остановлен.", 100, 220, 130)
    return true
end
local function nearestLaunderer(ply)
    if E and E.FindNearestLaunderer then return E.FindNearestLaunderer(ply, 2000) end
    local best, bestD = nil, math.huge
    for _, ent in ipairs(ents.FindByClass("grm_money_launderer")) do
        if IsValid(ent) and IsValid(ply) then
            local d = ply:GetPos():DistToSqr(ent:GetPos())
            if d < bestD then best, bestD = ent, d end
        end
    end
    return best
end
local function heistForceCmd(ply)
    if not IsValid(ply) or not ply:IsSuperAdmin() then
        if IsValid(ply) then notify(ply, "Только суперадмин.", 255, 100, 100) end
        return
    end
    local launderer = nearestLaunderer(ply)
    if not IsValid(launderer) then notify(ply, "Рядом нет отмывщика денег.", 255, 190, 90) return end
    launderer:ForceStart(ply)
end
local function heistStopCmd(ply)
    if not IsValid(ply) or not ply:IsSuperAdmin() then
        if IsValid(ply) then notify(ply, "Только суперадмин.", 255, 100, 100) end
        return
    end
    local launderer = nearestLaunderer(ply)
    if not IsValid(launderer) then notify(ply, "Рядом нет отмывщика денег.", 255, 190, 90) return end
    launderer:ForceStop(ply)
end
concommand.Add("grm_heist_force", function(ply) heistForceCmd(ply) end)
concommand.Add("grm_heist_stop", function(ply) heistStopCmd(ply) end)
hook.Add("PlayerSay", "GRM_Heist_ForceTransform", function(ply, text, teamSays)
    local datapack = { tostring(text or ""), SkipPlayerSay = false }
        if not istable(datapack) or not isstring(datapack[1]) then return end
        local t = string.lower(string.Trim(datapack[1]))
        if t == "/heist_force" then heistForceCmd(ply) datapack[1] = "" datapack.SkipPlayerSay = true
        elseif t == "/heist_stop" then heistStopCmd(ply) datapack[1] = "" datapack.SkipPlayerSay = true end

    if datapack.SkipPlayerSay == true then return "" end
end)
hook.Add("PlayerSay", "GRM_Heist_TargetTransform", function(ply, text, teamSays)
    local datapack = { tostring(text or ""), SkipPlayerSay = false }
        if not istable(datapack) then return end
        local text = datapack[1]
        if not isstring(text) then return end
        local t = string.lower(string.Trim(text))
        if t == "/heist_target" then
            heistTargetCmd(ply)
            datapack.SkipPlayerSay = true
            datapack[1] = ""
        elseif t == "/heist_target_clear" then
            heistTargetClearCmd(ply)
            datapack.SkipPlayerSay = true
            datapack[1] = ""
        end

    if datapack.SkipPlayerSay == true then return "" end
end)

-- ══ ПЕРМ (конфиг переживает рестарт) ═══════════════════════
GRM = GRM or {}
GRM.PermData = GRM.PermData or { Extract = {}, Apply = {} }
GRM.PermData.Extract = GRM.PermData.Extract or {}
GRM.PermData.Apply = GRM.PermData.Apply or {}
GRM.PermData.Extract["grm_money_launderer"] = function(ent)
    local rec = {
        minParticipants = math.floor(ent:GetMinParticipants() or 2),
        goalMoney = math.floor(ent:GetGoalMoney() or 500000),
        allowedFactions = tostring(ent:GetAllowedFactions() or ""),
        -- Находка 180h: чеклист гос.структур сохраняется в перм-базу
        govFactions = tostring(ent:GetGovFactions() or ""),
    }
    -- находка 179f: цель ивента (маркер GPS)
    local tp = ent:GetHeistTargetPos()
    if tp and (tp.x ~= 0 or tp.y ~= 0 or tp.z ~= 0) then
        rec.heistTarget = { x = tp.x, y = tp.y, z = tp.z }
    end
    return rec
end
GRM.PermData.Apply["grm_money_launderer"] = function(ent, data)
    if not istable(data) then return end
    if data.minParticipants then ent:SetMinParticipants(math.max(1, math.floor(tonumber(data.minParticipants) or 2))) end
    if data.goalMoney then ent:SetGoalMoney(math.max(1000, math.floor(tonumber(data.goalMoney) or 500000))) end
    if data.allowedFactions ~= nil then ent:SetAllowedFactions(tostring(data.allowedFactions or "")) end
    if data.govFactions ~= nil then ent:SetGovFactions(tostring(data.govFactions or "")) end
    if istable(data.heistTarget) then
        ent:SetHeistTargetPos(Vector(tonumber(data.heistTarget.x) or 0, tonumber(data.heistTarget.y) or 0, tonumber(data.heistTarget.z) or 0))
    end
end

-- Находка 180c: восстановить КД ограбления из файла (переживает рестарт)
loadCooldown()

print("[GRM] Money Launderer entity loaded (находка 179e)")

-- Вечер-18: команды пересажены с мёртвого входа EasyChat (PlayerSayTransform)
-- на боевой контракт библиотеки GRMRPChat — имена в едином внешнем реестре,
-- иначе чат съел бы их как «неизвестные» и по цепочке PlayerSay вызвал бы
-- обработчики этого файла.
if GRM and GRM.Chat and GRM.Chat.RegisterExternalCommands then
    GRM.Chat.RegisterExternalCommands({ "/heist_force", "/heist_stop", "/heist_target", "/heist_target_clear" })
end
