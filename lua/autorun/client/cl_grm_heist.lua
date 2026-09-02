--[[--------------------------------------------------------------------
    GRM Heist — клиент ивента «Ограбление» (находка 179e/179o)
    • Огромный баннер вверху экрана: «НАЧАТ ИВЕНТ: ОГРАБЛЕНИЕ» и итоги;
    • обратный отсчёт до конца ивента (50 минут);
    • музыка играет С СЕРВЕРА (CreateSound на отмывщике, звук слышен на
      всей карте) — клиент музыку сам не запускает.
----------------------------------------------------------------------]]
if not CLIENT then return end

surface.CreateFont("GRMHeist_Banner", { font = "Roboto", size = 64, weight = 1000, extended = true })
surface.CreateFont("GRMHeist_Sub", { font = "Roboto", size = 22, weight = 700, extended = true })
surface.CreateFont("GRMHeist_Timer", { font = "Roboto", size = 26, weight = 900, extended = true })

GRM = GRM or {}
GRM.Heist = GRM.Heist or {}
local Heist = GRM.Heist

Heist.Banner = nil      -- { text, sub, until }
Heist.EventEndsAt = 0   -- реальное время конца (для отсчёта)

net.Receive("GRM_Heist_Event", function()
    local state = net.ReadString()
    local title = net.ReadString()
    local subtitle = net.ReadString()
    local music = net.ReadBool()
    local endsAt = net.ReadFloat()
    -- Находка 180f: список РП-имён участников («криминал») для HUD
    local participants = net.ReadTable() or {}

    if state == "start" then
        Heist.Banner = { text = title, sub = subtitle, ["until"] = CurTime() + 10 }
        Heist.EventEndsAt = endsAt
        Heist.Participants = participants
        -- музыка уже играет с сервера (см. StartEvent отмывщика)
        surface.PlaySound("buttons/button15.wav")
    elseif state == "end" then
        Heist.Banner = { text = title, sub = subtitle, ["until"] = CurTime() + 12 }
        Heist.EventEndsAt = 0
        Heist.Participants = nil
    end
end)

-- Плашка баннера гаснет по альфе — цвет не константа, а скретч с записью
-- полей перед отрисовкой; статичные краски — константы загрузки (§6.1.8)
local HEIST_C = Color(0, 0, 0, 255)
local function heistCol(r, g, b, a)
    HEIST_C.r = r
    HEIST_C.g = g
    HEIST_C.b = b
    HEIST_C.a = a
    return HEIST_C
end
local HEIST_TIMER_BG = Color(20, 10, 10, 210)
local HEIST_TIMER_TX = Color(255, 150, 90)
local HEIST_LIST_BG = Color(15, 10, 10, 185)
local HEIST_LIST_TX = Color(255, 200, 120)

hook.Add("HUDPaint", "GRM_Heist_HUD", function()
    local lp = LocalPlayer()
    if not IsValid(lp) then return end

    -- баннер (огромная надпись вверху экрана)
    local b = Heist.Banner
    if b and b["until"] > CurTime() then
        local alpha = 255
        if b["until"] - CurTime() < 1.5 then alpha = math.floor(255 * (b["until"] - CurTime()) / 1.5) end
        draw.SimpleText(b.text, "GRMHeist_Banner", ScrW() / 2, ScrH() * 0.14, heistCol(255, 120, 80, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        if b.sub and b.sub ~= "" then
            draw.SimpleText(b.sub, "GRMHeist_Sub", ScrW() / 2, ScrH() * 0.14 + 52, heistCol(245, 240, 220, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        -- подложка для читаемости
        draw.RoundedBox(4, ScrW()/2 - 420, ScrH() * 0.14 - 40, 840, 120, heistCol(10, 12, 18, 120))
    end

    -- отсчёт во время ивента (персистентный, пока активен)
    if Heist.EventEndsAt > 0 and CurTime() < Heist.EventEndsAt then
        local left = math.max(0, math.floor(Heist.EventEndsAt - CurTime()))
        local mm, ss = math.floor(left / 60), left % 60
        local txt = ("ОГРАБЛЕНИЕ  •  %02d:%02d"):format(mm, ss)
        draw.RoundedBox(6, ScrW()/2 - 130, 8, 260, 34, HEIST_TIMER_BG)
        draw.SimpleText(txt, "GRMHeist_Timer", ScrW()/2, 25, HEIST_TIMER_TX, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    -- Находка 180f: список РП-имён участников («криминал») слева вверху
    if Heist.Participants and #Heist.Participants > 0 and Heist.EventEndsAt > 0 and CurTime() < Heist.EventEndsAt then
        local names = {}
        for _, r in ipairs(Heist.Participants) do
            local f = tostring(r.faction or "")
            names[#names + 1] = tostring(r.name or "?") .. (f ~= "" and (" [" .. f .. "]") or "")
        end
        local text = "УЧАСТНИКИ (КРИМИНАЛ):\n" .. table.concat(names, "\n")
        local x, y = 12, 56
        draw.RoundedBox(6, x, y, 240, 18 + #Heist.Participants * 17, HEIST_LIST_BG)
        draw.SimpleText(text, "GRMHeist_Sub", x + 12, y + 10, HEIST_LIST_TX, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end
end)
