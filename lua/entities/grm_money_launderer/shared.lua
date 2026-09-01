--[[--------------------------------------------------------------------
    grm_money_launderer — отмывщик денег / организатор ограбления (находка 179e)

    • Суперадмин через E-меню настраивает: какие фракции могут брать
      задание на ограбление, минимальное число участников, цель (сумма).
    • Игроки разрешённых фракций жмут E → «ВЗЯТЬ ЗАДАНИЕ» (участники).
    • Когда участников >= минимума — запускается ИВЕНТ «ОГРАБЛЕНИЕ»:
      баннер на весь экран «НАЧАТ ИВЕНТ: ОГРАБЛЕНИЕ», музыка music/hl2_song20_submix0.mp3.
    • Таймер 50 минут. Деньги (сумка ограбления / паллеты) сдаются
      отмывщику (E → «СДАТЬ ДЕНЬГИ» / /bag_unload рядом).
    • По истечении: если цель достигнута — победа фракции преступников
      (конкретной, сдавшей больше всех), иначе — госструктуры.
----------------------------------------------------------------------]]
ENT.Type      = "anim"
ENT.Base      = "base_gmodentity"
ENT.PrintName = "Отмывщик денег"
ENT.Author    = "GRM"
ENT.Category  = "GRM — Банк"
ENT.Spawnable = false
ENT.AdminSpawnable = false
ENT.RenderGroup = RENDERGROUP_BOTH

ENT.Model         = "models/humans/group03/male_07.mdl"
ENT.ModelFallback = "models/props_c17/consolebox01a.mdl"

ENT.HeistDuration = 3000   -- 50 минут
ENT.JobRadius     = 250    -- радиус E-взаимодействия
ENT.DepositRadius = 400    -- радиус сдачи денег (/bag_unload)
ENT.PreStartDelay = 40     -- Находка 180f: ожидание 40 сек перед стартом (вступить ещё успеют)

-- Находка 180h: вознаграждение гос.структурам за победу (защиту города).
-- Сумма — пропорционально доставленному отмывщику (MoneyHeld), в рамках
-- [MIN..MAX]; распределяется между гос.фракциями по киллам криминала.
ENT.GovRewardMin = 200000  -- минимум за победу госников
ENT.GovRewardMax = 1000000 -- максимум
-- Находка 180i: множитель выплаты при победе КРИМИНАЛА — не меньше x2
-- от награбленного (MoneyHeld); распределяется между фракциями-
-- участниками пропорционально сданному (FactionDelivered).
ENT.CrimRewardMultiplier = 2

function ENT:SetupDataTables()
    self:NetworkVar("Bool", 0, "Enabled")        -- отмывщик включён
    self:NetworkVar("Bool", 1, "EventActive")    -- идёт ивент
    self:NetworkVar("Int", 0, "MinParticipants") -- минимум участников
    self:NetworkVar("Int", 1, "GoalMoney")       -- цель (сумма)
    self:NetworkVar("Int", 2, "MoneyHeld")       -- сколько сдано
    self:NetworkVar("Int", 3, "ParticipantCount")
    self:NetworkVar("Float", 0, "EventEndsAt")
    -- Находка 180f: время (CurTime) старта ивента после набора минимума;
    -- 0 = ожидание не идёт. Даёт игрокам 40 сек добежать и вступить.
    self:NetworkVar("Float", 1, "PreStartAt")
    self:NetworkVar("String", 0, "AllowedFactions") -- список фракций через запятую (пусто = все)
    self:NetworkVar("String", 1, "WinnerFaction")
    -- Находка 180h: ГОС.СТРУКТУРЫ (чеклист суперадмина) — фракции через
    -- запятую; их победа = награда за защиту города (по киллам).
    self:NetworkVar("String", 2, "GovFactions")
    -- Находка 179f: цель ивента (Рейхсбанк/хранилище) — маркер GPS
    self:NetworkVar("Vector", 0, "HeistTargetPos") -- Vector(0,0,0) = не задана (авто: ближайшее хранилище)
end
