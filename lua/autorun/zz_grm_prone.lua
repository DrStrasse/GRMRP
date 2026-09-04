--[[ Мост GRM ↔ Prone Mod (SYSTEM PRONE). Сам мод не копируем:
     анимации и модели живут в отдельном аддоне dist/system_prone.zip.
     Здесь только лимбо/стамина и алиасы. ]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Prone = GRM.Prone or {}

--[[ Детект Prone Mod.

     Prone объявляет пустую таблицу `prone` в prone_init.lua, а функции
     (prone.Handle, PLAYER:IsProne) добавляет только в хуке Initialize —
     ПОЗЖЕ загрузки autorun. Поэтому одна проверка в момент загрузки моста
     может наврать «аддон не установлен». Повторяем проверку до первого
     успеха и кэшируем результат; дополнительно признаём мод по конвару
     и факту существования метода IsProne (вдруг API другой версии). ]]
local _proneReady = nil
local function detectProne()
    if _proneReady ~= nil then return _proneReady end
    local hasIsProne = false
    if FindMetaTable then
        local ok, mt = pcall(FindMetaTable, "Player")
        hasIsProne = ok and istable(mt) and isfunction(mt.IsProne)
    end
    local ok = (istable(prone) and isfunction(prone.Handle))
        or hasIsProne
        or (isfunction(prone) and isfunction(prone.Request))
    if ok then _proneReady = true end
    return ok == true
end

function GRM.Prone.ModLoaded()
    -- даём моду до 5 секунд на инициализацию, потом считаем, что его нет
    if _proneReady == nil and CurTime() > (GRM._proneProbeUntil or (CurTime() + 5)) then
        if not detectProne() then _proneReady = false end
    end
    return detectProne()
end

function GRM.Prone.Is(ply)
    if not IsValid(ply) then return false end
    if ply.IsProne and ply:IsProne() then return true end
    return ply:GetNWBool("GRM_Prone", false)
end

-- Мост мог загрузиться раньше Prone: как только тот объявит готовность,
-- проставляем флаг (хук вызывает сам Prone Mod в конце инициализации).
hook.Add("prone.Initialized", "GRM_Prone_Detected", function()
    _proneReady = true
end)
if SERVER then
    hook.Add("InitPostEntity", "GRM_Prone_Detect", function()
        timer.Simple(1, function() detectProne() end)
    end)
end

hook.Add("Think", "GRM_Prone_Mirror", function()
    if CLIENT then return end
    if GRM.Perf and not GRM.Perf.Throttle("prone.mirror", 0.2) then return end
    for _, ply in ipairs((GRM.Perf and GRM.Perf.Players and GRM.Perf.Players()) or player.GetAll()) do
        if IsValid(ply) then
            local on = ply.IsProne and ply:IsProne() or false
            if ply:GetNWBool("GRM_Prone", false) ~= on then
                ply:SetNWBool("GRM_Prone", on)
            end
        end
    end
end)

-- Цикл лечь → встать = отжимание. Сам Prone Mod не трогаем.
if SERVER then
    local MIN_HOLD = 0.55
    local MAX_HOLD = 5.0
    local REP_GAIN = 0.4
    local REP_COST = 9
    local COOLDOWN = 0.45

    hook.Add("prone.OnPlayerEntered", "GRM_Prone_PushDown", function(ply)
        if not IsValid(ply) then return end
        ply._grmPushDownAt = CurTime()
        ply:SetNWBool("GRM_Prone", true)
        if GRM.Movement and GRM.Movement.TrainFitness then
            GRM.Movement.TrainFitness(ply, 0, 3)
        end
    end)

    hook.Add("prone.OnPlayerExitted", "GRM_Prone_PushUp", function(ply)
        if not IsValid(ply) then return end
        ply:SetNWBool("GRM_Prone", false)
        local t0 = tonumber(ply._grmPushDownAt) or 0
        ply._grmPushDownAt = nil
        local held = CurTime() - t0
        if t0 <= 0 or held < MIN_HOLD or held > MAX_HOLD then return end
        if (ply._grmPushAt or 0) > CurTime() then return end
        ply._grmPushAt = CurTime() + COOLDOWN
        if not (GRM.Movement and GRM.Movement.TrainFitness) then return end
        if not GRM.Movement.TrainFitness(ply, REP_GAIN, REP_COST) then
            if GRM.Notify then GRM.Notify(ply, "Нет сил на ещё одно отжимание.", 255, 180, 80) end
            return
        end
        ply._grmPushReps = (ply._grmPushReps or 0) + 1
        if ply._grmPushReps % 5 == 0 then
            local _, mx = GRM.Movement.GetFitness(ply)
            if GRM.Notify then
                GRM.Notify(ply, ("Отжимания: %d. Потолок выносливости %.0f."):format(ply._grmPushReps, mx), 180, 140, 255)
            end
        end
    end)
end

hook.Add("prone.CanEnter", "GRM_Prone_Gates", function(ply)
    if not IsValid(ply) then return false end
    if ply:GetNWBool("GRM_CharacterPending", false) then return false end
    if ply.GRMCharLimbo then return false end
    if ply:GetNWBool("GRM_Arrested", false) then return false end
    if ply:InVehicle() then return false end
end)

if SERVER then
    hook.Add("PlayerSay", "GRM_Prone_Cmd", function(ply, text)
        local t = string.lower(string.Trim(text or ""))
        if t ~= "/prone" and t ~= "!prone" and t ~= "/лечь" then return end
        if GRM.Prone.ModLoaded() then
            if CLIENT then return "" end
            -- сервер: клиентский concommand prone шлёт impulse; зовём Handle
            if isfunction(prone.Handle) then prone.Handle(ply) end
            return ""
        end
        if GRM.Notify then GRM.Notify(ply, "Аддон лежания не установлен (system_prone).", 255, 180, 80) end
        return ""
    end)
end

if CLIENT then
    concommand.Add("grm_prone", function()
        if GRM.Prone.ModLoaded() and isfunction(prone.Request) then
            prone.Request()
        else
            RunConsoleCommand("prone")
        end
    end)
end

-- Вечер-18: единый словарь slash-команд: имена живого PlayerSay-обработчика
-- вносятся во внешний реестр библиотеки (на режиме сверка идёт ДО ParseSay —
-- без регистрации команда стала бы «неизвестной»).
if GRM and GRM.Chat and GRM.Chat.RegisterExternalCommands then
    GRM.Chat.RegisterExternalCommands({ "/prone", "/лечь" })
end
