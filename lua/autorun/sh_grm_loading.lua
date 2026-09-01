--[[--------------------------------------------------------------------
    GRM Loading v1.0.0 — экран входа на проект (заказ владельца 22.08).

    ЧТО ВИДИТ ИГРОК. Первым и единственным окном — чёрный экран, золотая
    надпись GROENNERLAND2036, ниже «ДОБРО ПОЖАЛОВАТЬ НА ПРОЕКТ!» и полоса
    загрузки. Полоса не декоративная: она показывает РЕАЛЬНЫЕ этапы —
    соединение, приём настроек сервера, готовность подсистем (GRM.Boot),
    прогрев моделей и данные персонажа. Когда всё готово, вместо полосы
    появляется кнопка «НАЧАТЬ ИГРАТЬ», и уже по ней открывается окно
    выбора/регистрации персонажа.

    ПОЧЕМУ ТАК. До подтверждения персонажа игрок висит за картой без
    оружия и модели (см. sh_grm_character.lua). Раньше в этот момент он
    смотрел в чёрный экран без объяснений и мог решить, что сервер завис.
    Теперь видно, что именно грузится и сколько осталось.

    ПОРЦИОННОСТЬ. Прогресс сервер считает по своему планировщику
    (GRM.Boot.Status) и отдаёт клиенту редким пакетом — раз в полсекунды и
    только тому, кто ещё грузится. Никаких покадровых расчётов.
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Loading = GRM.Loading or {}
local LD = GRM.Loading
LD.Version = "1.0.0"

LD.Net = { PROGRESS = "GRM_Loading_Progress", READY = "GRM_Loading_Ready" }

-----------------------------------------------------------------------
-- ЧИСТАЯ ЧАСТЬ (гоняется стендом)
-----------------------------------------------------------------------

--- Доля выполнения по этапам. steps — список { done = bool, weight = n }.
function LD.Progress(steps)
    local total, done = 0, 0
    for _, s in ipairs(istable(steps) and steps or {}) do
        local w = math.max(0, tonumber(s.weight) or 1)
        total = total + w
        if s.done then done = done + w end
    end
    if total <= 0 then return 0 end
    return math.Clamp(done / total, 0, 1)
end

--- Название текущего этапа: первый невыполненный.
function LD.CurrentStep(steps)
    for _, s in ipairs(istable(steps) and steps or {}) do
        if not s.done then return tostring(s.label or "") end
    end
    return "Готово"
end

-----------------------------------------------------------------------
-- СЕРВЕР: прогресс подсистем
-----------------------------------------------------------------------
if SERVER then
    util.AddNetworkString(LD.Net.PROGRESS)
    util.AddNetworkString(LD.Net.READY)

    LD.Waiting = LD.Waiting or {}   -- ply -> true, пока не нажал «НАЧАТЬ ИГРАТЬ»

    --- Доля готовности подсистем сервера по планировщику старта.
    function LD.BootShare()
        if not (GRM.Boot and GRM.Boot.Status) then return 1, 0, 0 end
        local ok, rows = pcall(GRM.Boot.Status)
        if not ok or not istable(rows) then return 1, 0, 0 end
        local total, done = 0, 0
        for _, row in ipairs(rows) do
            if not row.lazy then
                total = total + 1
                if row.state == "done" or row.state == "failed" then done = done + 1 end
            end
        end
        if total == 0 then return 1, 0, 0 end
        return done / total, done, total
    end

    local function push(ply)
        if not IsValid(ply) then return end
        local share, done, total = LD.BootShare()
        net.Start(LD.Net.PROGRESS)
            net.WriteFloat(share)
            net.WriteUInt(math.min(done, 4095), 12)
            net.WriteUInt(math.min(total, 4095), 12)
        net.Send(ply)
    end
    LD.Push = push

    --[[ Пока игрок на загрузочном экране, шлём ему прогресс раз в полсекунды.
         Таймер живёт только пока кто-то грузится. ]]
    local function ensureTimer()
        if timer.Exists("GRM_Loading_Push") then return end
        timer.Create("GRM_Loading_Push", 0.5, 0, function()
            local any = false
            for ply in pairs(LD.Waiting) do
                if IsValid(ply) then any = true push(ply) else LD.Waiting[ply] = nil end
            end
            if not any then timer.Remove("GRM_Loading_Push") end
        end)
    end

    hook.Add("PlayerInitialSpawn", "GRM_Loading_Start", function(ply)
        LD.Waiting[ply] = true
        ensureTimer()
        --[[ Конвейер входа стартует ПЕРВЫМ делом: он сразу ставит стадию
             и опускает занавес на клиенте. Раньше экран загрузки
             открывался таймером через 0.5 с, и до него игрок успевал
             увидеть кадр мира — жалоба владельца «пару секунд успеваешь
             увидеть, что персонаж уже заспавнился». ]]
        if GRM.Entry and GRM.Entry.Begin then GRM.Entry.Begin(ply) end
        timer.Simple(1, function() if IsValid(ply) then push(ply) end end)
    end)

    hook.Add("PlayerDisconnected", "GRM_Loading_Clear", function(ply)
        LD.Waiting[ply] = nil
    end)

    --[[ Игрок нажал «НАЧАТЬ ИГРАТЬ» — только теперь открываем окно выбора
         персонажа. До этого оно не всплывает поверх загрузки. ]]
    net.Receive(LD.Net.READY, function(_, ply)
        if not IsValid(ply) then return end
        if GRM.Net and GRM.Net.Guard and not GRM.Net.Guard(ply, "loading.ready", { rate = 1, burst = 2 }) then return end
        LD.Waiting[ply] = nil
        ply.GRMLoadingDone = true
        hook.Run("GRM_LoadingFinished", ply)
        --[[ Стадию двигает конвейер: он же следит, чтобы окно персонажа
             не открылось раньше времени и чтобы занавес не поднялся. ]]
        if GRM.Entry and GRM.Entry.ToCharacter then GRM.Entry.ToCharacter(ply) end
        if GRM.Char and GRM.Char.OpenMenu then GRM.Char.OpenMenu(ply) end
    end)

    --- Ждёт ли игрок ещё на загрузочном экране.
    function LD.IsLoading(ply)
        return IsValid(ply) and LD.Waiting[ply] == true
    end
end

-----------------------------------------------------------------------
-- КЛИЕНТ: сам экран
-----------------------------------------------------------------------
if CLIENT then
    surface.CreateFont("GRMLoad_Title", { font = "Roboto", size = 64, weight = 900, extended = true })
    surface.CreateFont("GRMLoad_Sub",   { font = "Roboto", size = 22, weight = 700, extended = true })
    surface.CreateFont("GRMLoad_Small", { font = "Roboto", size = 15, weight = 500, extended = true })
    surface.CreateFont("GRMLoad_Btn",   { font = "Roboto", size = 20, weight = 800, extended = true })

    local GOLD = Color(226, 184, 92)
    local GOLD_DIM = Color(150, 120, 60)

    LD.Steps = LD.Steps or {}
    LD.BootShare = 0
    LD.Shown = false

    local function steps()
        local lp = LocalPlayer()
        return {
            { label = "Соединение с сервером", weight = 1, done = IsValid(lp) },
            { label = "Приём настроек сервера", weight = 1,
              done = GetConVar("grm_vehicle_precache") ~= nil },
            { label = "Загрузка подсистем сервера", weight = 4, done = LD.BootShare >= 0.999,
              share = LD.BootShare },
            { label = "Прогрев моделей транспорта", weight = 2,
              done = (GRM.VehiclePrecache and GRM.VehiclePrecache.Queued == 0) or false },
            -- Персонаж считается готовым, когда сервер уже принял игрока и
            -- выставил ему состояние выбора (NW-флаг приходит через ~1 c).
            { label = "Данные персонажа", weight = 2,
              done = LD.CharReady == true or (IsValid(lp) and (lp:GetNWBool("GRM_CharacterPending", false)
                  or lp:GetNWString("GRM_CharacterID", "") ~= "")) },
        }
    end

    --- Плавная доля: у этапа подсистем своя внутренняя доля.
    local function share()
        local list = steps()
        local total, done = 0, 0
        for _, s in ipairs(list) do
            local w = math.max(0, tonumber(s.weight) or 1)
            total = total + w
            if s.done then done = done + w
            elseif s.share then done = done + w * math.Clamp(s.share, 0, 1) end
        end
        if total <= 0 then return 0 end
        return math.Clamp(done / total, 0, 1)
    end

    net.Receive(LD.Net.PROGRESS, function()
        LD.BootShare = net.ReadFloat() or 0
        LD.BootDone = net.ReadUInt(12)
        LD.BootTotal = net.ReadUInt(12)
    end)

    local frame, bar, playBtn, stepLabel
    local shown = 0

    function LD.Close()
        if IsValid(frame) then frame:Remove() end
        frame = nil
        LD.Shown = false
        -- Сообщаем остальным: экран свободен, можно показывать своё окно.
        hook.Run("GRM_LoadingClosed")
    end

    function LD.Open()
        if IsValid(frame) then return end
        --[[ Экран входа никогда не ложится поверх уже открытого окна
             персонажа: два полноэкранных окна — это то самое «двоится». ]]
        if GRM.Char and IsValid(GRM.Char._frame) then return end
        LD.Shown = true
        shown = RealTime()

        frame = vgui.Create("DFrame")
        -- Серверный бан не должен закрыть обязательный экран входа: игрок
        -- обязан иметь возможность нажать «НАЧАТЬ ИГРАТЬ».
        frame.GRM_BanAllowed = true
        frame:SetSize(ScrW(), ScrH())
        frame:SetPos(0, 0)
        frame:SetTitle("")
        frame:ShowCloseButton(false)
        frame:SetDraggable(false)
        frame:MakePopup()
        frame.Close = function() end
        frame.OnKeyCodePressed = function(_, key) if key == KEY_ESCAPE then return true end end

        -- Мягкое дыхание: заголовок и линия чуть ярче/тусклее, без дёрганья.
        local function pulse(a0, a1)
            local t = (math.sin(RealTime() * 2.4) + 1) * 0.5
            return Lerp(t, a0, a1)
        end

        frame.Paint = function(_, w, h)
            draw.RoundedBox(0, 0, 0, w, h, Color(0, 0, 0, 255))

            local cy = h * 0.34
            local titleA = pulse(200, 255)
            local subA = pulse(110, 220)
            draw.SimpleText("GROENNERLAND2036", "GRMLoad_Title", w / 2, cy,
                Color(GOLD.r, GOLD.g, GOLD.b, titleA),
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText("ДОБРО ПОЖАЛОВАТЬ НА ПРОЕКТ!", "GRMLoad_Sub", w / 2, cy + 54,
                Color(GOLD_DIM.r, GOLD_DIM.g, GOLD_DIM.b, subA),
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

            surface.SetDrawColor(GOLD.r, GOLD.g, GOLD.b, pulse(50, 160))
            surface.DrawRect(w / 2 - 260, cy + 80, 520, 1)
        end

        local barW, barH = 520, 16
        bar = vgui.Create("DPanel", frame)
        bar:SetSize(barW, barH)
        bar:SetPos(ScrW() / 2 - barW / 2, ScrH() * 0.34 + 130)
        bar.Paint = function(_, w, h)
            local blink = (math.sin(RealTime() * 3.2) + 1) * 0.5
            local fillA = Lerp(blink, 150, 255)
            local outlineA = Lerp(blink, 70, 200)
            draw.RoundedBox(4, 0, 0, w, h, Color(24, 22, 18, 255))
            surface.SetDrawColor(GOLD.r, GOLD.g, GOLD.b, outlineA)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
            local p = share()
            draw.RoundedBox(4, 2, 2, math.max(0, (w - 4) * p), h - 4,
                Color(GOLD.r, GOLD.g, GOLD.b, fillA))
            draw.SimpleText(("%d%%"):format(math.floor(p * 100)), "GRMLoad_Small", w / 2, h / 2,
                Color(20, 18, 14, Lerp(blink, 180, 255)), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end

        stepLabel = vgui.Create("DLabel", frame)
        stepLabel:SetSize(barW, 22)
        stepLabel:SetPos(ScrW() / 2 - barW / 2, ScrH() * 0.34 + 154)
        stepLabel:SetFont("GRMLoad_Small")
        stepLabel:SetTextColor(GOLD_DIM)
        stepLabel:SetContentAlignment(5)

        playBtn = vgui.Create("DButton", frame)
        playBtn:SetText("")
        playBtn:SetSize(320, 46)
        playBtn:SetPos(ScrW() / 2 - 160, ScrH() * 0.34 + 124)
        playBtn:SetVisible(false)
        playBtn.Paint = function(self, w, h)
            local col = self:IsHovered() and Color(246, 210, 120) or GOLD
            draw.RoundedBox(6, 0, 0, w, h, col)
            draw.SimpleText("НАЧАТЬ ИГРАТЬ", "GRMLoad_Btn", w / 2, h / 2, Color(18, 16, 12),
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        playBtn.DoClick = function()
            surface.PlaySound("buttons/button14.wav")
            net.Start(LD.Net.READY) net.SendToServer()
            LD.Close()
        end

        --[[ Этапы сверяем редко. Альфу подписи крутим каждый кадр — иначе
             мигание ступеньками по 250 мс. ]]
        frame.Think = function(self)
            if IsValid(stepLabel) and stepLabel:IsVisible() then
                local a = 110 + math.floor((math.sin(RealTime() * 3.2) + 1) * 0.5 * 120)
                stepLabel:SetTextColor(Color(GOLD_DIM.r, GOLD_DIM.g, GOLD_DIM.b, a))
            end
            if (self.nextCheck or 0) > RealTime() then return end
            self.nextCheck = RealTime() + 0.25

            local ready = share() >= 0.999
            -- страховка: если сервер молчит дольше 45 секунд, пускаем игрока
            if not ready and RealTime() - shown > 45 then ready = true end

            if IsValid(stepLabel) then
                stepLabel:SetText(ready and "Всё готово" or LD.CurrentStep(steps()))
                stepLabel:SetVisible(not ready)
            end
            if IsValid(bar) then bar:SetVisible(not ready) end
            if IsValid(playBtn) then playBtn:SetVisible(ready) end
        end
    end

    -- данные персонажа пришли — этап закрыт
    hook.Add("GRM_CharacterPayload", "GRM_Loading_Char", function() LD.CharReady = true end)

    --[[ Экран открываем как можно раньше. Занавес конвейера (GRM.Entry)
         уже держит чёрный кадр, но окно с полосой должно появиться сразу,
         а не через полсекунды — иначе видно пустой чёрный экран без
         объяснений.

         Первая попытка — немедленно; затем ретраи, потому что стадия
         приходит с сервера NW-полем и может чуть запоздать. ]]
    hook.Add("InitPostEntity", "GRM_Loading_Open", function()
        LD.Open()
        for _, d in ipairs({ 0.1, 0.4, 1, 2 }) do
            timer.Simple(d, function()
                local E = GRM.Entry
                -- Открываем, только если конвейер ещё не выпустил в мир.
                if E and E.ClientInProgress and not E.ClientInProgress() then return end
                LD.Open()
            end)
        end
    end)

    --[[ Стадия сменилась на «выбор персонажа» — экран загрузки обязан
         уйти, даже если игрок не нажимал кнопку (например, сервер сам
         продвинул его после таймаута). ]]
    hook.Add("GRM_EntryStageClient", "GRM_Loading_AutoClose", function(stage)
        local E = GRM.Entry
        if E and stage and stage >= E.Stages.character then LD.Close() end
    end)

    hook.Add("OnReloaded", "GRM_Loading_Reopen", function()
        if LD.Shown then LD.Close() LD.Open() end
    end)

    concommand.Add("grm_loading_show", function() LD.Open() end)
end

print("[GRM Loading] v" .. LD.Version .. " loaded (" .. (SERVER and "Server" or "Client") .. ")")
