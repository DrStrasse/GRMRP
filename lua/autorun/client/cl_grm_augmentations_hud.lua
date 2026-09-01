-- Boot-шим: старт подсистемы идёт через планировщик GRM.Boot (приоритеты и
-- бюджет на тик). Если планировщик почему-то не загружен, работаем по-старому.
local function grmBootStart(id, tier, fn)
    if GRM and GRM.Boot and GRM.Boot.OnMapStart then return GRM.Boot.OnMapStart(id, tier, fn) end
    return hook.Add("InitPostEntity", id, fn)
end

--[[
    GRM Augmentations HUD
    Отображение активных аугментаций и чипов на экране
]]

if not CLIENT then return end

GRM = GRM or {}
GRM.AugHUD = GRM.AugHUD or {}
local HUD = GRM.AugHUD

-- Настройки HUD
HUD.Config = {
    Enabled = true,
    ShowChips = true,
    ShowEffects = true,
    Position = {x = 20, y = ScrH() - 260},
    AutoRefresh = 5, -- секунды
}

-- GRM UI Style
local GRM_COLORS = {
    bg = Color(15, 20, 30, 200),
    panel = Color(25, 35, 50, 220),
    accent = Color(0, 150, 255),
    text = Color(220, 230, 240),
    text_dim = Color(140, 150, 170),
    success = Color(50, 200, 100),
    warning = Color(255, 180, 50),
    error = Color(255, 80, 80),
    border = Color(60, 80, 110, 150)
}

-- GRM Fonts
surface.CreateFont("GRMAugHUD_Title", { font = "Roboto", size = 16, weight = 700, extended = true })
surface.CreateFont("GRMAugHUD_Normal", { font = "Roboto", size = 13, weight = 500, extended = true })
surface.CreateFont("GRMAugHUD_Small", { font = "Roboto", size = 11, weight = 500, extended = true })

-- Кэш данных
HUD.CachedChips = {}
HUD.LastUpdate = 0
HUD.HasServerSync = false
function HUD.IsActive() return #HUD.GetActiveChips() > 0 end

function HUD.GetActiveChips()
    local out={}
    for _, chip in ipairs(HUD.CachedChips or {}) do
        if chip.implanted and chip.active ~= false then out[#out+1]=chip end
    end
    return out
end
HUD.Signal = {phase = 0, pulse = 0, bootUntil = 0}
--[[ ЦВЕТА КАДРА — считаются ОДИН раз, а не в каждом HUDPaint.

     Было: тактический HUD создавал 22 таблицы Color() и две служебные
     таблицы за кадр. При 144 Гц это больше трёх тысяч мусорных таблиц в
     секунду на ровном месте — сборщик Lua потом отдаёт их «рывками»
     кадра (§6.1.8: не создавать таблицы в render-кадре).

     Цвета, зависящие от пульса, нельзя сделать константами — у них
     меняется альфа. Для них держим ОДИН объект и правим поле .a:
     draw.* читает цвет сразу, копия ему не нужна. ]]
local COL_PROFILE = {
    civilian = Color(70, 190, 255),
    service = Color(70, 220, 170),
    military = Color(255, 190, 65),
    experimental = Color(255, 75, 90),
}
local COL_WARN_TEXT = Color(255, 170, 60)
local COL_PANEL = Color(8, 15, 24, 190)
local COL_CONSOLE = Color(5, 12, 18, 145)
local COL_ACCESSORY = Color(180, 220, 235)
local COL_CASH = Color(105, 225, 135)
local COL_CASH_VALUE = Color(220, 240, 230)
local COL_BANK = Color(100, 190, 255)
local COL_BANK_VALUE = Color(215, 230, 245)
local COL_HP = Color(100, 230, 130)
local COL_ARMOR = Color(100, 180, 255)
local COL_STABLE = Color(80, 220, 130)
local COL_IP = Color(180, 210, 225, 160)
local COL_DOOR_BG = Color(8, 18, 28, 225)
local COL_DOOR_TITLE = Color(80, 220, 255)
local COL_DOOR_TEXT = Color(230, 240, 245)

-- Автоскан и подсветка цели: та же логика «создать один раз».
local COL_HALO_CIVIL = Color(70, 210, 255)
local COL_HALO_EXPERIMENTAL = Color(255, 70, 100)
local COL_HALO_MILITARY = Color(255, 190, 50)
local COL_SCAN_TITLE = Color(80, 210, 255)
local COL_SCAN_NAME = Color(225, 235, 245)
local COL_SCAN_DIM = Color(160, 180, 200)
local COL_SCAN_FACTION = Color(100, 210, 160)
local COL_SCAN_HURT = Color(255, 100, 90)
local COL_SCAN_OK = Color(100, 230, 130)
local COL_SCAN_SERVICE = Color(255, 190, 70)

-- Панель автоскана выезжает: у неё альфа зависит от прогресса.
local COL_SCAN_BG = Color(7, 15, 24, 225)

-- Панель канала аугментации.
local COL_LINK_BG = Color(8, 16, 25, 205)
local COL_LINK_TITLE = Color(100, 220, 255)
local COL_LINK_BAR_BG = Color(30, 55, 70, 220)
local COL_LINK_BAR = Color(40, 210, 255, 210)

-- Плашка «CHIP ONLINE» плавно затухает: у трёх её цветов меняется альфа.
local COL_ONLINE_BG = Color(15, 20, 30, 230)
local COL_ONLINE_TITLE = Color(80, 210, 255, 255)
local COL_ONLINE_NAME = Color(220, 230, 240, 255)

-- Переиспользуемые (меняется только альфа/оттенок в кадре).
local COL_PULSE_WARN = Color(255, 130, 60, 180)
local COL_LINK_LINE = Color(70, 190, 255, 75)

-- Список каналов биоконсоли: постоянная часть строится один раз,
-- переменная (телефон, фракции, инвентарь) дописывается по событию
-- загрузки модулей, а не пересобирается каждый кадр.
local CONSOLE_LINKS = { "BIOCORE", "PACKET", "TLS", "AUTH" }
local consoleLinksBuilt = false

local function consoleLinks()
    if consoleLinksBuilt then return CONSOLE_LINKS end
    if GRM.Phone then CONSOLE_LINKS[#CONSOLE_LINKS + 1] = "PHONE" end
    if Factions or GRM.Factions then CONSOLE_LINKS[#CONSOLE_LINKS + 1] = "FACTION" end
    if GRM.Inventory then CONSOLE_LINKS[#CONSOLE_LINKS + 1] = "INVENTORY" end
    if GRM.Mobile then CONSOLE_LINKS[#CONSOLE_LINKS + 1] = "MOBILE" end
    -- Модули догружаются на старте карты; после первого кадра с полным
    -- набором список фиксируем.
    consoleLinksBuilt = #CONSOLE_LINKS > 4
    return CONSOLE_LINKS
end

HUD.CombineOverlay = Material("effects/combine_binocoverlay")
HUD.FaultUntil = 0
HUD.Profile = "civilian"
HUD.LastScanSound = 0
HUD.ScanStarted = 0
HUD.ConsoleLines = {}
for i=1,12 do HUD.ConsoleLines[i] = "[LINK] 10.24."..math.random(1,254).."."..math.random(1,254).." :: GRM/"..(i%3==0 and "BANK" or i%3==1 and "BIO" or "NET").." :: PACKET "..math.random(1000,9999) end

net.Receive("GRM_AugChip_Sync", function()
    HUD.CachedChips = net.ReadTable() or {}
    HUD.HasServerSync = true
    HUD.LastUpdate = CurTime()
    hook.Run("GRM_AugmentationStateUpdated")
end)

-- Обновление данных
function HUD.UpdateData()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    -- Серверный список является авторитетным. Не затираем его локальной пустой таблицей.
    if not HUD.HasServerSync and GRM.AugChips then
        HUD.CachedChips = GRM.AugChips.GetPlayerChips(ply) or {}
    end
    HUD.LastUpdate = CurTime()
end

-- Автообновление
timer.Create("GRM_AugHUD_AutoRefresh", HUD.Config.AutoRefresh, 0, function()
    HUD.UpdateData()
end)

-- HUD Paint
hook.Add("HUDPaint", "GRM_Augmentations_ChipsHUD", function()
    if not HUD.Config.Enabled then return end

    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end

    -- Проверка наличия аугментаций
    if not GRM.AugChips then return end

    local chips = HUD.CachedChips or {}
    local implantedChips = {}

    for _, chip in ipairs(chips) do
        if chip.implanted and chip.active ~= false then
            table.insert(implantedChips, chip)
        end
    end

    if #implantedChips == 0 then return end

    local x, y = HUD.Config.Position.x, HUD.Config.Position.y
    local panelWidth = 320
    local panelHeight = 76 + (#implantedChips * 29)

    -- Фон панели
    draw.RoundedBox(6, x, y, panelWidth, panelHeight, GRM_COLORS.bg)
    surface.SetDrawColor(GRM_COLORS.border)
    surface.DrawOutlinedRect(x, y, panelWidth, panelHeight, 1)

    -- Заголовок
    draw.RoundedBoxEx(6, x, y, panelWidth, 30, GRM_COLORS.panel, true, true, false, false)
    draw.SimpleText("🔧 АУГМЕНТАЦИИ", "GRMAugHUD_Title", x + 10, y + 15, GRM_COLORS.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    draw.SimpleText(#implantedChips, "GRMAugHUD_Small", x + panelWidth - 10, y + 15, GRM_COLORS.text_dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

    -- Список чипов
    local chipY = y + 48
    draw.SimpleText("SYSTEM ONLINE  •  БИОСВЯЗЬ АКТИВНА", "GRMAugHUD_Small", x + 10, y + 35, GRM_COLORS.success, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    for _, chip in ipairs(implantedChips) do
        local catConfig = GRM.AugChips.Config.ChipCategories[chip.category]
        local catColor = catConfig and catConfig.color or GRM_COLORS.text

        -- Иконка статуса
        local statusIcon = chip.hasComplications and "⚠️" or "✓"
        local statusColor = chip.hasComplications and GRM_COLORS.warning or GRM_COLORS.success

        draw.SimpleText(statusIcon, "GRMAugHUD_Normal", x + 10, chipY, statusColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        -- Название чипа
        draw.SimpleText(chip.name, "GRMAugHUD_Normal", x + 30, chipY, GRM_COLORS.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        -- Категория
        draw.SimpleText(catConfig and catConfig.name or chip.category, "GRMAugHUD_Small", x + panelWidth - 10, chipY, catColor, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

        chipY = chipY + 29
    end
end)

-- Нативный Combine-подобный экранный оверлей GMod.
-- Материал входит в стандартный контент HL2/GMod; если его нет, HUD остаётся рабочим.
hook.Add("RenderScreenspaceEffects", "GRM_AugHUD_CombineOverlay", function()
    if not HUD.Config.Enabled then return end
    local chips = HUD.CachedChips or {}
    local active = false
    local profile = "civilian"
    for _, chip in ipairs(chips) do if chip.implanted and chip.active ~= false then active = true; profile = chip.category or profile end end
    HUD.Profile = profile
    if not active then return end
    if HUD.CombineOverlay and not HUD.CombineOverlay:IsError() then
        local pulse = 0.88 + math.sin(RealTime() * 1.7) * 0.08
        DrawMaterialOverlay("effects/combine_binocoverlay", 0.12 * pulse)
    end
end)

hook.Add("HUDPaint", "GRM_AugHUD_TacticalChrome", function()
    if not HUD.Config.Enabled then return end
    local ply=LocalPlayer(); if not IsValid(ply) or not ply:Alive() then return end
    local active={}; local complications=false
    for _,chip in ipairs(HUD.CachedChips or {}) do if chip.implanted and chip.active ~= false then active[#active+1]=chip; complications=complications or chip.hasComplications end end
    if #active==0 then return end
    local sw,sh=ScrW(),ScrH(); local t=RealTime(); local pulse=0.5+math.sin(t*2.2)*0.5
    local accent=COL_PROFILE[HUD.Profile] or COL_PROFILE.civilian
    -- Угловые сканирующие рамки.
    surface.SetDrawColor(accent.r,accent.g,accent.b,130+80*pulse)
    local m=28; local l=82
    surface.DrawLine(m,m,m+l,m); surface.DrawLine(m,m,m,m+l); surface.DrawLine(sw-m,m,sw-m-l,m); surface.DrawLine(sw-m,m,sw-m,m+l)
    surface.DrawLine(m,sh-m,m+l,sh-m); surface.DrawLine(m,sh-m,m,sh-m-l); surface.DrawLine(sw-m,sh-m,sw-m-l,sh-m); surface.DrawLine(sw-m,sh-m,sw-m,sh-m-l)
    -- Диагностическая строка с бегущим текстом.
    local diag=string.format("GRM BIO-LINK // PROFILE:%s // CHIPS:%d // POS %.0f %.0f %.0f // %s",string.upper(HUD.Profile),#active,ply:GetPos().x,ply:GetPos().y,ply:GetPos().z,complications and "WARNING: COMPLICATIONS" or "STATUS: NOMINAL")
    local offset=(t*85)%math.max(1,surface.GetTextSize(diag)+sw)
    draw.SimpleText(diag,"GRMAugHUD_Small",sw-offset,sh-42,complications and COL_WARN_TEXT or accent,TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER)
    -- Связанные аксессуары: показываем функциональные модули рядом с чипами.
    local accessoryNames={}
    if GRM.Customization and GRM.Customization.GetClientLoadout and GRM.Customization.Catalog then
        local loadout=GRM.Customization.GetClientLoadout(LocalPlayer()) or {}
        for slot,equipped in pairs(loadout) do
            local item=GRM.Customization.Catalog[equipped.accessoryID]
            if item and item.functions then
                for id,on in pairs(item.functions) do if on then accessoryNames[#accessoryNames+1]=item.name or id break end end
            end
        end
    end
    if #accessoryNames>0 then
        local ax,ay=sw-265,sh-410; draw.RoundedBox(5,ax,ay,235,75,COL_PANEL); draw.SimpleText("АКСЕССУАРЫ", "GRMAugHUD_Title",ax+12,ay+16,accent)
        for i=1,math.min(2,#accessoryNames) do draw.SimpleText("[ON] "..accessoryNames[i],"GRMAugHUD_Small",ax+12,ay+25+i*18,COL_ACCESSORY) end
    end

    -- Деньги: синхронизируемся с теми же полями, что и стандартный GRM HUD.
    local moneyX, moneyY = sw-265, sh-315
    draw.RoundedBox(5,moneyX,moneyY,235,88,COL_PANEL); draw.SimpleText("ФИНАНСОВЫЙ КАНАЛ","GRMAugHUD_Title",moneyX+12,moneyY+16,accent)
    draw.SimpleText("НАЛИЧКА", "GRMAugHUD_Small", moneyX+12,moneyY+40,COL_CASH); draw.SimpleText(GRM.Format and GRM.Format(GRM.PlayerBalance or 0) or tostring(GRM.PlayerBalance or 0),"GRMAugHUD_Normal",moneyX+223,moneyY+40,COL_CASH_VALUE,TEXT_ALIGN_RIGHT,TEXT_ALIGN_CENTER)
    draw.SimpleText("НА СЧЕТУ", "GRMAugHUD_Small", moneyX+12,moneyY+64,COL_BANK); draw.SimpleText(GRM.PlayerBank ~= nil and (GRM.Format and GRM.Format(GRM.PlayerBank) or tostring(GRM.PlayerBank)) or "—","GRMAugHUD_Normal",moneyX+223,moneyY+64,COL_BANK_VALUE,TEXT_ALIGN_RIGHT,TEXT_ALIGN_CENTER)

    -- Биометрия.
    local x,y=sw-265,sh-190
    draw.RoundedBox(5,x,y,235,105,COL_PANEL); draw.SimpleText("BIOMETRICS","GRMAugHUD_Title",x+12,y+16,accent)
    draw.SimpleText("HP  "..ply:Health().." / "..ply:GetMaxHealth(),"GRMAugHUD_Normal",x+12,y+43,COL_HP)
    draw.SimpleText("ARMOR  "..ply:Armor(),"GRMAugHUD_Normal",x+12,y+66,COL_ARMOR)
    draw.SimpleText(complications and "СТАТУС: НЕСТАБИЛЕН" or "СТАТУС: СТАБИЛЕН","GRMAugHUD_Small",x+12,y+88,complications and COL_WARN_TEXT or COL_STABLE)
    if complications then COL_PULSE_WARN.a = 180 + 70 * pulse
        draw.SimpleText("⚠ ОСЛОЖНЕНИЯ", "GRMAugHUD_Warning",sw/2,sh*.28,COL_PULSE_WARN,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER) end
    -- Полупрозрачная диагностическая консоль с живыми сетевыми строками.
    local cx,cy=sw-355,sh-500; draw.RoundedBox(5,cx,cy,325,135,COL_CONSOLE); draw.SimpleText("GRM BIOCONSOLE // SECURE LINK","GRMAugHUD_Small",cx+10,cy+15,accent)
    local links = consoleLinks()
    for i=1,12 do local yy=cy+30+(i-1)*8; local channel=links[((i+math.floor(t*2))%#links)+1]; local line=string.format("[%s] 10.24.%d.%d :: %s :: PKT %04d",channel,(ply:AccountID()%254),(i%254),channel,math.floor(t*10+i)%10000); COL_LINK_LINE.r, COL_LINK_LINE.g, COL_LINK_LINE.b = accent.r, accent.g, accent.b
        draw.SimpleText(line,"GRMAugHUD_Small",cx+10,yy,COL_LINK_LINE,TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER) end
    local ip="10.24."..((ply:AccountID() or 1)%254).."."..((ply:UserID() or 1)%254)
    draw.SimpleText("IP "..ip.."  //  TLS-BIO/1.4  //  AES-256","GRMAugHUD_Small",cx+10,cy+125,COL_IP)
end)

hook.Add("HUDPaint", "GRM_AugHUD_DoorPrompt", function()
    local lp=LocalPlayer()
    if not IsValid(lp) then return end
    -- Проверяем НАЛИЧИЕ чипа взлома напрямую (не зависит от HUD.IsActive):
    -- подсказка должна появляться, если у игрока есть экспериментальный чип
    -- с doorHack, даже если другие чипы неактивны.
    local hasChip = false
    if GRM.AugChips and GRM.AugChips.HasDoorHack then
        hasChip = GRM.AugChips.HasDoorHack(lp) ~= nil
    else
        for _,c in ipairs(HUD.CachedChips or {}) do
            if c.category=="experimental" and c.implanted and c.active ~= false and
                ((c.modifiers or {}).doorHack=="enabled" or (c.modifiers or {}).doorHack==true or
                 (c.modifiers or {}).doorHack=="включен" or string.find(string.upper(c.name or ""),"DOOR")) then
                hasChip=true break
            end
        end
    end
    if not hasChip then return end
    local tr=(GRM.Perf and GRM.Perf.EyeTrace) and GRM.Perf.EyeTrace(lp,0.05) or lp:GetEyeTrace(); if not tr then return end; local e=tr.Entity
    if not IsValid(e) or not ({func_door=true,func_door_rotating=true,prop_door_rotating=true,prop_physics=true})[e:GetClass()] then return end
    if tr.HitPos:DistToSqr(lp:EyePos()) > 10000 then return end
    local w,h=470,64; local x,y=ScrW()/2-w/2,ScrH()*.43
    draw.RoundedBox(6,x,y,w,h,COL_DOOR_BG); surface.SetDrawColor(70,210,255,220); surface.DrawOutlinedRect(x,y,w,h,2)
    draw.SimpleText("ДВЕРНОЙ ПРОТОКОЛ", "GRMAugHUD_Title", ScrW()/2,y+18,COL_DOOR_TITLE,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
    draw.SimpleText("НАЖМИТЕ E — ВЗЛОМАТЬ НА 30 СЕКУНД + 10 СЕКУНД УДЕРЖАНИЕ", "GRMAugHUD_Normal",ScrW()/2,y+43,COL_DOOR_TEXT,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
end)

local function resolveFaction(target)
    local sid=target:SteamID64(); local charKey=(GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(target)) or (tostring(sid)..":char1")
    local data=FactionsData or (GRM.FactionsData)
    if istable(data) then
        for name,f in pairs(data) do
            local members=f.Members or f.members or f.players or f.Players
            if istable(members) then
                local member=members[charKey] or members[sid]
                if istable(member) then return tostring(name), tostring(member.role or member.Role or member.rank or member.Rank or "Житель") end
                if member then return tostring(name), "Участник" end
                for key,rec in pairs(members) do
                    local msid=istable(rec) and (rec.characterKey or rec.character_key or rec.steamid64 or rec.sid or rec.SteamID64) or key
                    if tostring(msid)==tostring(charKey) or tostring(msid)==tostring(sid) then
                        return tostring(name), istable(rec) and tostring(rec.role or rec.Role or rec.rank or rec.Rank or "Участник") or "Участник"
                    end
                end
            end
        end
    end
    return target:GetNWString("GRM_Faction", "Гражданское лицо"), target:GetNWString("GRM_Role", "Житель")
end
hook.Add("PreDrawHalos", "GRM_AugHUD_PlayerScanOutline", function()
    if not HUD.IsActive() then return end
    local tr=(GRM.Perf and GRM.Perf.EyeTrace) and GRM.Perf.EyeTrace(LocalPlayer(),0.05) or LocalPlayer():GetEyeTrace(); if not tr then return end; local e=tr.Entity
    if IsValid(e) and e:IsPlayer() and e~=LocalPlayer() and tr.HitPos:DistToSqr(LocalPlayer():EyePos())<350000 then
        -- Цвет обводки — готовая константа: выбираем, а не создаём.
        local col = COL_HALO_CIVIL
        for _, c in ipairs(HUD.GetActiveChips()) do
            if c.category == "experimental" then col = COL_HALO_EXPERIMENTAL
            elseif c.category == "military" then col = COL_HALO_MILITARY end
        end
        halo.Add({e},col,2,2,1,true,true)
    end
end)

hook.Add("HUDPaint", "GRM_AugHUD_AutoScan", function()
    if not HUD.IsActive() then return end
    local ply=LocalPlayer(); local tr=(GRM.Perf and GRM.Perf.EyeTrace) and GRM.Perf.EyeTrace(ply,0.05) or ply:GetEyeTrace(); if not tr then return end; local target=tr.Entity
    if not IsValid(target) or not target:IsPlayer() or target==ply or tr.HitPos:DistToSqr(ply:EyePos())>350000 then HUD.ScanStarted=0; return end
    if CurTime()-HUD.LastScanSound > 2 then HUD.LastScanSound=CurTime(); surface.PlaySound("buttons/blip1.wav") end
    local chips=HUD.GetActiveChips(); if HUD.ScanStarted==0 then HUD.ScanStarted=CurTime() end; local scanProgress=math.Clamp((CurTime()-HUD.ScanStarted)*3,0,1); local military=false; for _,c in ipairs(chips) do if c.category=="military" or c.category=="experimental" then military=true end end
    local w,h=390,military and 190 or 140; local x,y=ScrW()-w-38,ScrH()*.50+(1-scanProgress)*35
    COL_SCAN_BG.a = 225 * scanProgress
    draw.RoundedBox(7,x,y,w,h,COL_SCAN_BG); surface.SetDrawColor(70,200,255,220*scanProgress); surface.DrawOutlinedRect(x,y,w,h,2)
    draw.SimpleText("АВТОСКАН // "..(military and "СЛУЖЕБНЫЙ ПРОФИЛЬ" or "ГРАЖДАНСКИЙ ПРОФИЛЬ"),"GRMAugHUD_Title",x+14,y+18,COL_SCAN_TITLE)
    local nick=target:Nick(); local faction,role=resolveFaction(target)
    draw.SimpleText("РП-ИМЯ: "..nick,"GRMAugHUD_Normal",x+14,y+48,COL_SCAN_NAME); draw.SimpleText("ПОЛ: не определён  |  ID: "..(target:UserID() or "?"),"GRMAugHUD_Small",x+14,y+69,COL_SCAN_DIM); draw.SimpleText("ФРАКЦИЯ: "..faction.."  |  РОЛЬ: "..role,"GRMAugHUD_Small",x+14,y+88,COL_SCAN_FACTION)
    local hp=math.max(0,target:Health()); local mx=math.max(1,target:GetMaxHealth()); draw.SimpleText("СОСТОЯНИЕ: "..hp.." / "..mx,"GRMAugHUD_Normal",x+14,y+112,hp/mx<.35 and COL_SCAN_HURT or COL_SCAN_OK)
    if military then draw.SimpleText("РОЗЫСК: "..(target:GetNWBool("GRM_Wanted",false) and "ДА" or "НЕТ").."  |  ШТРАФЫ: данные доступа","GRMAugHUD_Small",x+14,y+137,COL_SCAN_SERVICE); draw.SimpleText("СЛУЖЕБНЫЙ ИД: "..target:GetNWString("GRM_ServiceID", "не выдан"),"GRMAugHUD_Small",x+14,y+157,COL_SCAN_SERVICE) end
end)

-- Постоянный интерфейс аугментации: мягкий импульс, scanline и статус канала.
hook.Add("HUDPaint", "GRM_AugHUD_LiveInterface", function()
    if not HUD.Config.Enabled then return end
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end
    local chips = HUD.CachedChips or {}
    local active = {}
    for _, chip in ipairs(chips) do if chip.implanted and chip.active ~= false then active[#active + 1] = chip end end
    if #active == 0 then return end
    HUD.Signal.phase = (HUD.Signal.phase + FrameTime() * 2.4) % (math.pi * 2)
    local pulse = 0.5 + math.sin(HUD.Signal.phase) * 0.5
    local w, h = 280, 76
    local x, y = ScrW() - w - 24, 24
    draw.RoundedBox(6, x, y, w, h, COL_LINK_BG)
    surface.SetDrawColor(40, 190, 255, 110 + pulse * 90)
    surface.DrawOutlinedRect(x, y, w, h, 1)
    draw.SimpleText("AUGMENTATION LINK", "GRMAugHUD_Title", x + 12, y + 17, COL_LINK_TITLE, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    draw.SimpleText("ЧИПОВ: " .. #active .. "   //   СИНХРОНИЗАЦИЯ", "GRMAugHUD_Small", x + 12, y + 37, GRM_COLORS.text_dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    local bar = math.Clamp(0.72 + pulse * 0.18, 0, 1)
    draw.RoundedBox(2, x + 12, y + 53, w - 24, 5, COL_LINK_BAR_BG)
    draw.RoundedBox(2, x + 12, y + 53, (w - 24) * bar, 5, COL_LINK_BAR)
    draw.SimpleText("СИСТЕМА СТАБИЛЬНА", "GRMAugHUD_Small", x + w - 12, y + 68, GRM_COLORS.success, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
end)

-- Активационный экран после имплантации: не исчезает мгновенно, а плавно затухает.
-- Консольные команды
concommand.Add("grm_aughud_toggle", function()
    HUD.Config.Enabled = not HUD.Config.Enabled
    chat.AddText(HUD.Config.Enabled and Color(100, 255, 100) or Color(255, 100, 100),
        "[GRM] HUD аугментаций ", HUD.Config.Enabled and "включен" or "выключен")
end)

concommand.Add("grm_aughud_refresh", function()
    HUD.UpdateData()
    chat.AddText(Color(100, 200, 255), "[GRM] Данные HUD обновлены")
end)

-- Инициализация
grmBootStart("GRM_AugHUD_Init", "late", function()
    HUD.UpdateData()
end)

print("[GRM AugHUD] Augmentations HUD loaded")

-- Мгновенная обратная связь: сработка чипа, HUD-уведомление и сканирующая анимация.
HUD.Activation = HUD.Activation or {name = "", untilTime = 0}
net.Receive("GRM_AugChip_Activated", function()
    HUD.Activation.name = net.ReadString()
    net.ReadTable()
    HUD.Activation.untilTime = CurTime() + 5
    HUD.Signal.bootUntil = CurTime() + 1.2
    HUD.UpdateData()

end)
hook.Add("HUDPaint", "GRM_AugHUD_Activation", function()
    if not HUD.Config.Enabled or not HUD.Activation or HUD.Activation.untilTime <= CurTime() then return end
    local left = HUD.Activation.untilTime - CurTime()
    local a = math.min(255, left * 180)
    local w, h = 360, 54
    local x, y = (ScrW() - w) * 0.5, ScrH() * 0.18
    COL_ONLINE_BG.a = a * 0.9
    draw.RoundedBox(6, x, y, w, h, COL_ONLINE_BG)
    surface.SetDrawColor(0, 190, 255, a)
    surface.DrawOutlinedRect(x, y, w, h, 2)
    COL_ONLINE_TITLE.a = a
    draw.SimpleText("CHIP ONLINE", "GRMAugHUD_Title", x + 16, y + 16, COL_ONLINE_TITLE, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    COL_ONLINE_NAME.a = a
    draw.SimpleText(HUD.Activation.name, "GRMAugHUD_Normal", x + 16, y + 38, COL_ONLINE_NAME, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    surface.SetDrawColor(80, 210, 255, a)
    surface.DrawRect(x + 12, y + 49, (w - 24) * math.Clamp(left / 3, 0, 1), 2)
end)


hook.Add("RenderScreenspaceEffects", "GRM_AugHUD_ActivationPulse", function()
    if not HUD.Signal or HUD.Signal.bootUntil <= CurTime() then return end
    local t = math.Clamp((HUD.Signal.bootUntil - CurTime()) / 1.2, 0, 1)
    DrawColorModify({["$pp_colour_addr"] = 0, ["$pp_colour_addg"] = 0.02 * t,
        ["$pp_colour_addb"] = 0.04 * t, ["$pp_colour_brightness"] = 0.04 * t,
        ["$pp_colour_contrast"] = 1 + 0.12 * t, ["$pp_colour_colour"] = 1})
end)


net.Receive("GRM_AugChip_Rejection", function()
    HUD.FaultUntil = CurTime() + 1.4
    surface.PlaySound("buttons/button10.wav")
end)
hook.Add("RenderScreenspaceEffects", "GRM_AugHUD_RejectionFault", function()
    if HUD.FaultUntil <= CurTime() then return end
    local k=math.Clamp((HUD.FaultUntil-CurTime())/1.4,0,1)
    DrawColorModify({["$pp_colour_addr"]=0.08*k,["$pp_colour_addg"]=-0.03*k,["$pp_colour_addb"]=-0.03*k,["$pp_colour_brightness"]=-0.06*k,["$pp_colour_contrast"]=1+0.25*k,["$pp_colour_colour"]=0.85})
end)
