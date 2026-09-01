--[[--------------------------------------------------------------------
    GRM Jobs — Курьер: физическая посылка.

    ЧТО БЫЛО. Шаблон обещал «Доставьте посылку в точку города», но возить
    было нечего: работа сводилась к «дойди до координаты». Ни предмета,
    ни проверки, что ты вообще что-то несёшь. Курьера нельзя было
    ограбить, посылку — потерять или украсть, поэтому у доставки не было
    ни одного пересечения с другими игроками.

    ЧТО СТАЛО. Посылка — энтити grm_parcel в руках. Её роняют при смерти,
    её может подобрать и донести кто угодно, а точка доставки НЕ
    засчитывается, если посылки в руках нет.

    ПОЧЕМУ ОТДЕЛЬНЫЙ ФАЙЛ. Ядро sh_grm_jobs.lua — почти 2000 строк на все
    работы сразу. Класть туда ещё и логику предмета значит продолжать
    ком. Курьерская механика самодостаточна и живёт рядом, как это уже
    сделано для мусора (v5) и такси (v4).
----------------------------------------------------------------------]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Jobs = GRM.Jobs or {}
local JB = GRM.Jobs
JB.CourierVersion = "1.0.0"

--- Ключ персонажа: тот же, что у остальных подсистем работ.
local function charKey(ply)
    if JB.CharacterKey then return JB.CharacterKey(ply) end
    if GRM.Identity and GRM.Identity.CharacterKey then return GRM.Identity.CharacterKey(ply) end
    return (type(ply) == "table" and ply.SteamID64 and (ply:SteamID64() .. ":char1")) or tostring(ply or "")
end

--- Несёт ли игрок посылку прямо сейчас.
function JB.HasParcel(ply)
    if not IsValid(ply) then return false end
    return IsValid(ply:GetNWEntity("GRM_Parcel"))
end

if SERVER then
    local function notify(ply, msg, good)
        if not IsValid(ply) then return end
        if GRM.Notify then
            GRM.Notify(ply, msg, good == false and 255 or 120, good == false and 135 or 220, good == false and 105 or 150)
        else
            ply:ChatPrint("[Доставка] " .. msg)
        end
    end
    local function audit(action, actor, target, details)
        if GRM.Audit and GRM.Audit.Write then GRM.Audit.Write("jobs", action, actor, target or {}, details or {}) end
    end

    --- Выдать посылку под конкретный заказ.
    function JB.GiveParcel(ply, job)
        if not IsValid(ply) then return nil end
        if not istable(job) or job.tplId ~= "courier" then return nil end
        -- Вторую посылку в руки не даём: иначе первую можно бросить и
        -- получить бесконечный источник «грузов».
        local existing = ply:GetNWEntity("GRM_Parcel")
        if IsValid(existing) then return existing end

        local parcel = ents.Create("grm_parcel")
        if not IsValid(parcel) then return nil end
        parcel:SetPos(ply:GetPos() + Vector(0, 0, 40))
        parcel:Spawn()
        parcel:Activate()
        parcel:SetOwnerKey(charKey(ply))
        parcel:SetLabel(tostring(job.zoneName or "Посылка"))
        parcel:AttachTo(ply)
        job.parcelIssued = true
        audit("courier.parcel_issued", ply, {}, { to = tostring(job.zoneName or "") })
        notify(ply, "Посылка у вас в руках. Доставьте её по адресу: " .. tostring(job.zoneName or "точка") .. ".", true)
        return parcel
    end

    --- Сдать посылку в точке доставки: закрывает заказ.
    function JB.DeliverParcel(ply, job)
        if not IsValid(ply) then return false end
        local parcel = ply:GetNWEntity("GRM_Parcel")
        if not IsValid(parcel) then return false end
        parcel:Detach(ply:GetPos())
        parcel:Remove()
        audit("courier.parcel_delivered", ply, {}, { to = tostring(istable(job) and job.zoneName or "") })
        if JB.Complete then JB.Complete(ply) end
        return true
    end

    --[[ Подобрать лежащую посылку. Ради этого всё и затевалось: чужую
         посылку можно отнять и донести самому — но только если у тебя
         тоже есть курьерский заказ, иначе коробка бесполезна. ]]
    function JB.PickupParcel(ply, parcel)
        if not IsValid(ply) or not IsValid(parcel) then return false end
        if IsValid(parcel:GetCarrier()) then return false end
        if JB.HasParcel(ply) then
            notify(ply, "У вас уже есть посылка в руках.", false)
            return false
        end
        local job = JB.GetActiveJob and JB.GetActiveJob(ply)
        if not (istable(job) and job.tplId == "courier") then
            notify(ply, "Посылку принимает только курьер на смене. Возьмите заказ на бирже труда.", false)
            return false
        end
        parcel:AttachTo(ply)
        audit("courier.parcel_taken", ply, {}, { owner = parcel:GetOwnerKey() })
        local mine = parcel:GetOwnerKey() == charKey(ply)
        notify(ply, mine and "Посылка снова у вас." or "Вы подобрали чужую посылку. Донесёте — заказ закроется на вас.", true)
        return true
    end

    --- Уронить посылку из рук (смерть, отказ от работы, выход).
    function JB.DropParcel(ply, reason)
        if not IsValid(ply) then return false end
        local parcel = ply:GetNWEntity("GRM_Parcel")
        if not IsValid(parcel) then return false end
        parcel:Detach(ply:GetPos() + Vector(0, 0, 8))
        audit("courier.parcel_dropped", ply, {}, { reason = tostring(reason or "") })
        return true
    end

    --[[ Смерть курьера НЕ уничтожает посылку: она падает на землю там же.
         Это и есть смысл предмета — груз можно отбить, потерять и
         подобрать, а не «он растворился вместе с владельцем». ]]
    hook.Add("PlayerDeath", "GRM_Courier_DropParcel", function(ply)
        JB.DropParcel(ply, "смерть курьера")
    end)
    hook.Add("PlayerDisconnected", "GRM_Courier_DropParcelLeave", function(ply)
        JB.DropParcel(ply, "курьер вышел с сервера")
    end)

    -- Работа кончилась (провал, отказ, таймаут) — посылка больше не нужна.
    hook.Add("GRM_Jobs_Failed", "GRM_Courier_ClearParcel", function(ply, job)
        if not istable(job) or job.tplId ~= "courier" then return end
        if not IsValid(ply) then return end
        local parcel = ply:GetNWEntity("GRM_Parcel")
        if IsValid(parcel) then
            parcel:Detach(ply:GetPos())
            parcel:Remove()
        end
    end)

    -- Взял курьерский заказ — сразу получил груз. Ядро объявляет о старте
    -- работы хуком GRM_Jobs_Started (не Accepted — имя проверено по коду).
    hook.Add("GRM_Jobs_Started", "GRM_Courier_IssueParcel", function(ply, job)
        if istable(job) and job.tplId == "courier" then JB.GiveParcel(ply, job) end
    end)
end

if CLIENT then
    -- Напоминание в углу: посылка в руках — не абстракция, её видно.
    hook.Add("HUDPaint", "GRM_Courier_ParcelHUD", function()
        local ply = LocalPlayer()
        if not IsValid(ply) then return end
        local parcel = ply:GetNWEntity("GRM_Parcel")
        if not IsValid(parcel) then return end
        local label = parcel.GetLabel and parcel:GetLabel() or ""
        if label == "" then label = "адрес в задании" end
        draw.RoundedBox(7, ScrW() / 2 - 230, ScrH() - 145, 460, 42, Color(14, 20, 28, 230))
        draw.SimpleText("ПОСЫЛКА В РУКАХ  •  " .. string.upper(label), "DermaDefaultBold",
            ScrW() / 2, ScrH() - 124, Color(235, 220, 130), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end)
end
