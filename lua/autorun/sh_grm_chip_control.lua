--[[--------------------------------------------------------------------
    GRM Chip Control (находка 169) — контроль и регистрация чипов

    • Реестр носителей имплантированных чипов (для терминала контроля).
    • При смерти носителя ЭКСПЕРИМЕНТАЛЬНОГО чипа:
        - звук смерти комбайна npc/metropolice/die2.wav;
        - текстовое уведомление членам фракций, у которых во вкладке
          «Расширенные настройки» /factions включено
          «Уведомлять о смерти носителей экспериментальных чипов»
          (ChipDeathAlert в fw_faction_extras.json);
        - временная GPS-метка «В данном районе убит/умер специальный юнит»
          (temp-точка minimap, живёт 120с, видна только получившим синк).
    • Журнал событий (реестр + смерти) для терминала grm_chip_terminal.
----------------------------------------------------------------------]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.ChipControl = GRM.ChipControl or {}
local CC = GRM.ChipControl
CC.Version = "1.0.0"
CC.Events = CC.Events or {}          -- журнал: {time, type, name, sid, faction, pos}
CC.MaxEvents = 50
CC.DeathMarkerDuration = 120         -- секунд живёт GPS-маркер смерти

-- Публичный звук смерти комбайна (для клиента и сервера)
CC.DeathSound = "npc/metropolice/die2.wav"

-- ============================================================
-- РЕЕСТР НОСИТЕЛЕЙ
-- ============================================================
-- Все носители имплантированных чипов (онлайн и офлайн из CHIPS.PlayerChips)
function CC.ListCarriers()
    local out = {}
    local seen = {}
    -- онлайн-игроки
    for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
        if IsValid(p) then
            local key = CC.CarrierKey(p)
            seen[key] = true
            local chips = CC.CarrierChips(p)
            if #chips > 0 then
                out[#out + 1] = {
                    key = key, name = p:Nick(), sid = p:SteamID64(),
                    faction = CC.FactionOf(p), chips = chips,
                    online = true, special = CC.HasExperimental(p),
                }
            end
        end
    end
    -- офлайн из хранилища чипов
    if GRM.AugChips and istable(GRM.AugChips.PlayerChips) then
        for key, list in pairs(GRM.AugChips.PlayerChips) do
            if not seen[key] and istable(list) then
                local implanted = {}
                local special = false
                for _, c in ipairs(list) do
                    if c and c.implanted then
                        implanted[#implanted + 1] = { id = c.id, name = c.name, category = c.category, active = c.active ~= false }
                        if c.category == "experimental" then special = true end
                    end
                end
                if #implanted > 0 then
                    out[#out + 1] = {
                        key = key, name = key, sid = key,
                        faction = CC.FactionOfKey(key), chips = implanted,
                        online = false, special = special,
                    }
                end
            end
        end
    end
    return out
end

-- Ключ носителя (CharacterKey)
function CC.CarrierKey(ply)
    if GRM.Identity and GRM.Identity.CharacterKey then return GRM.Identity.CharacterKey(ply) end
    return tostring(ply:SteamID64()) .. ":char1"
end

-- Чипы игрока (имплантированные)
function CC.CarrierChips(ply)
    local out = {}
    if GRM.AugChips and GRM.AugChips.GetPlayerChips then
        for _, c in ipairs(GRM.AugChips.GetPlayerChips(ply) or {}) do
            if c and c.implanted then
                out[#out + 1] = { id = c.id, name = c.name, category = c.category, active = c.active ~= false }
            end
        end
    end
    return out
end

-- Есть ли у игрока имплантированный экспериментальный чип
function CC.HasExperimental(ply)
    if not IsValid(ply) then return false end
    if GRM.AugChips and GRM.AugChips.GetPlayerChips then
        for _, c in ipairs(GRM.AugChips.GetPlayerChips(ply) or {}) do
            if c and c.implanted and c.category == "experimental" then return true end
        end
    end
    return false
end

-- Фракция игрока (имя или "")
function CC.FactionOf(ply)
    if not IsValid(ply) then return "" end
    local sid, s64 = ply:SteamID(), ply:SteamID64()
    if istable(Factions) then
        for name, f in pairs(Factions) do
            if istable(f) and istable(f.Members) and (f.Members[sid] or f.Members[s64]) then return name end
        end
    end
    return ""
end
function CC.FactionOfKey(key)
    -- офлайн: ищем по ключу в Members (sid:s64:char1 или sid64:char1)
    if istable(Factions) then
        for name, f in pairs(Factions) do
            if istable(f) and istable(f.Members) then
                for sid in pairs(f.Members) do
                    if tostring(key) == tostring(sid) .. ":char1" or tostring(key) == tostring(CC.SID64of(sid)) .. ":char1" then
                        return name
                    end
                end
            end
        end
    end
    return ""
end
function CC.SID64of(sid)
    if util.SteamIDTo64 then local s = util.SteamIDTo64(sid) if s and s ~= "0" then return s end end
    return sid
end

-- Включено ли уведомление у фракции (ChipDeathAlert из FactionsExt extras)
function CC.AlertEnabledFor(factionName)
    if factionName == "" then return false end
    local cfg = FactionsExt and FactionsExt[factionName]
    return (cfg and cfg.ChipDeathAlert == true) or false
end

-- ============================================================
-- СЕРВЕР
-- ============================================================
if SERVER then
    util.AddNetworkString("GRM_ChipControl_Open")     -- терминал: открыть меню
    util.AddNetworkString("GRM_ChipControl_Data")     -- терминал: данные (реестр+журнал)
    util.AddNetworkString("GRM_ChipDeath_Alert")      -- уведомление членам фракций
    util.AddNetworkString("GRM_ChipControl_AdminData")   -- админ: данные цели (чипы+инвентарь)
    util.AddNetworkString("GRM_ChipControl_AdminExtract")-- админ: изъять чип
    util.AddNetworkString("GRM_ChipControl_AdminRemove") -- админ: удалить предмет из инвентаря

    local function logEvent(ev)
        CC.Events[#CC.Events + 1] = ev
        if #CC.Events > CC.MaxEvents then table.remove(CC.Events, 1) end
    end

    -- ── АДМИН (суперадмин): изъятие чипов и предметов ──────────────
    local function targetBySID(sid64)
        if not sid64 or sid64 == "" then return nil end
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(p) and p:SteamID64() == sid64 then return p end
        end
        return nil
    end

    -- Пакет данных цели: имплантированные чипы + содержимое инвентаря
    local function adminPayload(target)
        local chips = {}
        if GRM.AugChips and GRM.AugChips.GetPlayerChips then
            for _, c in ipairs(GRM.AugChips.GetPlayerChips(target) or {}) do
                if c and c.implanted then
                    chips[#chips + 1] = { id = c.id, name = c.name, category = c.category, active = c.active ~= false }
                end
            end
        end
        local items = {}
        if GRM.Inventory and GRM.Inventory.GetPlayerInv then
            local inv = GRM.Inventory.GetPlayerInv(target)
            if inv and istable(inv.slots) then
                for i = 1, (GRM.Inventory.Config and GRM.Inventory.Config.MaxSlots) or 24 do
                    local slot = inv.slots[i]
                    if slot and slot.id then
                        items[#items + 1] = { slot = i, id = slot.id, count = tonumber(slot.count) or 1 }
                    end
                end
            end
        end
        return { chips = chips, items = items }
    end

    net.Receive("GRM_ChipControl_AdminData", function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        local sid64 = net.ReadString()
        local target = targetBySID(sid64)
        if not IsValid(target) then return end
        net.Start("GRM_ChipControl_AdminData")
            net.WriteString(sid64)
            net.WriteTable(adminPayload(target))
        net.Send(ply)
    end)

    -- Изъятие (конфискация) чипа: снятие эффектов + полное удаление записи
    net.Receive("GRM_ChipControl_AdminExtract", function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        local sid64 = net.ReadString()
        local chipId = net.ReadString()
        local target = targetBySID(sid64)
        if not IsValid(target) or chipId == "" then return end
        if GRM.AugChips and GRM.AugChips.RemoveChip then
            if GRM.AugChips.RemoveChip(target, chipId) then
                if GRM.AugChips.SyncChips then GRM.AugChips.SyncChips(target) end
                if GRM.AugChips.RecomputeEffects then GRM.AugChips.RecomputeEffects(target) end
                if GRM.Notify then GRM.Notify(target, "Ваш чип изъят администрацией.", 255, 120, 100) end
                if GRM.Notify then GRM.Notify(ply, "Чип изъят у " .. target:Nick() .. ".", 100, 220, 130) end
                logEvent({ time = os.time(), type = "extract", name = target:Nick(), sid = sid64, faction = CC.FactionOf(target), pos = { x = 0, y = 0, z = 0 } })
            end
        end
        net.Start("GRM_ChipControl_AdminData")
            net.WriteString(sid64)
            net.WriteTable(adminPayload(target))
        net.Send(ply)
    end)

    -- Удаление/изъятие предметов из инвентаря цели
    net.Receive("GRM_ChipControl_AdminRemove", function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        local sid64 = net.ReadString()
        local itemID = net.ReadString()
        local count = math.max(1, math.floor(tonumber(net.ReadUInt(16)) or 1))
        local target = targetBySID(sid64)
        if not IsValid(target) or itemID == "" then return end
        if GRM.Inventory and GRM.Inventory.RemoveItem then
            local left = GRM.Inventory.RemoveItem(target, itemID, count)
            local removed = count - (tonumber(left) or 0)
            if removed > 0 then
                if GRM.Inventory.SyncToClient then GRM.Inventory.SyncToClient(target) end
                if GRM.Notify then GRM.Notify(target, "Администрация изъяла: " .. itemID .. " x" .. removed, 255, 120, 100) end
                if GRM.Notify then GRM.Notify(ply, "Изъято у " .. target:Nick() .. ": " .. itemID .. " x" .. removed, 100, 220, 130) end
            else
                if GRM.Notify then GRM.Notify(ply, "Предмет не найден у игрока: " .. itemID, 255, 150, 90) end
            end
        end
        net.Start("GRM_ChipControl_AdminData")
            net.WriteString(sid64)
            net.WriteTable(adminPayload(target))
        net.Send(ply)
    end)

    -- Прямой доступ к чипам офлайн-носителя (для терминала: показать все)
    function CC.PushTerminalData(ply)
        if not IsValid(ply) then return end
        net.Start("GRM_ChipControl_Data")
            net.WriteTable({ carriers = CC.ListCarriers(), events = CC.Events })
        net.Send(ply)
    end

    net.Receive("GRM_ChipControl_Open", function(_, ply)
        if IsValid(ply) then CC.PushTerminalData(ply) end
    end)

    -- Уведомление члену фракции: звук + текст
    local function notifyMember(member, deadName, pos)
        if not IsValid(member) then return end
        local msg = "⚠ В данном районе убит/умер специальный юнит — носитель экспериментального чипа: " .. deadName
        net.Start("GRM_ChipDeath_Alert")
            net.WriteString(msg)
            net.WriteVector(pos or member:GetPos())
        net.Send(member)
    end

    -- СМЕРТЬ НОСИТЕЛЯ ЭКСПЕРИМЕНТАЛЬНОГО ЧИПА
    hook.Add("PlayerDeath", "GRM_ChipControl_Death", function(victim, inflictor, attacker)
        if not IsValid(victim) then return end
        -- Только носители экспериментальных чипов
        if not CC.HasExperimental(victim) then return end

        local deadName = victim:Nick()
        local pos = victim:GetPos()
        local victimFaction = CC.FactionOf(victim)
        logEvent({ time = os.time(), type = "death", name = deadName, sid = victim:SteamID64(), faction = victimFaction, pos = { x = pos.x, y = pos.y, z = pos.z } })

        -- Собираем фракции, у которых включено уведомление
        local alertFactions = {}
        if istable(Factions) then
            for name, f in pairs(Factions) do
                if CC.AlertEnabledFor(name) then
                    alertFactions[#alertFactions + 1] = { name = name, f = f }
                end
            end
        end

        local sentTo = {}
        for _, af in ipairs(alertFactions) do
            local f = af.f
            if istable(f) and istable(f.Members) then
                for _, member in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                    if IsValid(member) and member ~= victim and not sentTo[member] then
                        local sid, s64 = member:SteamID(), member:SteamID64()
                        if f.Members[sid] or f.Members[s64] then
                            sentTo[member] = true
                            notifyMember(member, deadName, pos)
                        end
                    end
                end
            end
        end

        -- Временная GPS-метка (видна только тем, кому отправлен синк minimap)
        if #alertFactions > 0 and GRM.Minimap and GRM.Minimap.AddTempPoint then
            local id = GRM.Minimap.AddTempPoint("В данном районе убит/умер специальный юнит", pos, CC.DeathMarkerDuration)
            -- точечный синк minimap каждому уведомлённому
            for member in pairs(sentTo) do
                if IsValid(member) and GRM.Minimap.SendTo then GRM.Minimap.SendTo(member) end
            end
        end

        -- Консоль-лог
        print("[GRM ChipControl] Смерть спец-юнита: " .. deadName .. " (фракция: " .. victimFaction .. "), уведомлены фракции: " .. #alertFactions)
    end)

    -- Регистрация в журнале имплантаций/извлечений (для терминала)
    hook.Add("GRM_AugmentationStateUpdated", "GRM_ChipControl_LogState", function()
        -- лёгкая фиксация: не спамим, журнал наполняется смертями; имплантации
        -- видны в реестре носителей (ListCarriers) в реальном времени.
    end)

    print("[GRM ChipControl] server v" .. CC.Version .. " loaded")
end

-- ============================================================
-- КЛИЕНТ
-- ============================================================
if CLIENT then
    -- Уведомление: звук смерти комбайна + текст + нотификация
    net.Receive("GRM_ChipDeath_Alert", function()
        local msg = net.ReadString()
        local pos = net.ReadVector()
        surface.PlaySound(CC.DeathSound)
        chat.AddText(Color(255, 90, 70), "[СООБЩЕНИЕ] ", Color(235, 235, 235), msg)
        notification.AddLegacy(msg, NOTIFY_GENERIC, 8)
        -- Текстовый маркер в мире на месте смерти (на 8 сек)
        local untilT = CurTime() + 8
        -- краски мира-маркера: по одной аллокации на сообщение вместо двух
        -- на кадр восьмисекундной метки (§6.1.8)
        local tagCol, tagOut = Color(255, 170, 150), Color(8, 14, 23, 235)
        hook.Add("HUDPaint", "GRM_ChipControl_WorldTag", function()
            if CurTime() > untilT then hook.Remove("HUDPaint", "GRM_ChipControl_WorldTag") return end
            local screen = pos:ToScreen()
            if screen.visible then
                draw.SimpleTextOutlined("⚠ " .. msg, "GRMMM_Body", screen.x, screen.y - 40, tagCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, tagOut)
            end
        end)
    end)

    -- Терминал: меню контроля чипов
    function CC.OpenTerminalMenu()
        net.Start("GRM_ChipControl_Open") net.SendToServer()
    end

    net.Receive("GRM_ChipControl_Data", function()
        local data = net.ReadTable() or {}
        local carriers = data.carriers or {}
        local events = data.events or {}
        local C = { bg = Color(13, 19, 28, 252), head = Color(21, 30, 43), panel = Color(25, 36, 51), card = Color(31, 46, 64), accent = Color(55, 164, 247), green = Color(58, 205, 119), red = Color(220, 79, 78), warn = Color(247, 181, 61), text = Color(235, 241, 248), dim = Color(151, 168, 187) }
        if not surface.CreateFont then return end
        surface.CreateFont("GRMCC_Title", { font = "Roboto", size = 22, weight = 800, extended = true })
        surface.CreateFont("GRMCC_Head", { font = "Roboto", size = 15, weight = 700, extended = true })
        surface.CreateFont("GRMCC_Text", { font = "Roboto", size = 13, weight = 500, extended = true })
        surface.CreateFont("GRMCC_Small", { font = "Roboto", size = 11, weight = 500, extended = true })

        local frame = vgui.Create("DFrame")
        GRM.UI.Track("chip_control", frame)
        frame:SetTitle(""); frame:SetSize(980, 640); frame:Center(); frame:MakePopup(); frame:ShowCloseButton(false)
        frame.Paint = function(self, w, h)
            draw.RoundedBox(9, 0, 0, w, h, C.bg)
            draw.RoundedBoxEx(9, 0, 0, w, 56, C.head, true, true, false, false)
            draw.SimpleText("КОНТРОЛЬ ЧИПОВ", "GRMCC_Title", 20, 20, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText("GRM // CHIP REGISTRY  •  спец-юниты под наблюдением", "GRMCC_Small", 20, 42, C.accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText("BIO-LINK ONLINE", "GRMCC_Small", w - 20, 20, C.green, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
        local close = vgui.Create("DButton", frame)
        close:SetPos(frame:GetWide() - 42, 14); close:SetSize(28, 28); close:SetText("X"); close:SetTextColor(C.text)
        close.Paint = function(self, w, h) draw.RoundedBox(4, 0, 0, w, h, self:IsHovered() and C.red or C.panel) end
        close.DoClick = function() frame:Close() end

        local sheet = vgui.Create("DPropertySheet", frame)
        sheet:Dock(FILL); sheet:DockMargin(14, 64, 14, 14)
        sheet.Paint = function(_, w, h) draw.RoundedBox(7, 0, 0, w, h, C.panel) end

        -- Вкладка: Носители
        local carriersPanel = vgui.Create("DPanel"); carriersPanel:SetPaintBackground(false)
        local sc = vgui.Create("DScrollPanel", carriersPanel); sc:Dock(FILL); sc:DockMargin(4, 4, 4, 4)
        if #carriers == 0 then
            local l = vgui.Create("DLabel", sc); l:Dock(TOP); l:SetTall(40); l:SetFont("GRMCC_Head"); l:SetTextColor(C.dim)
            l:SetText("Носителей имплантированных чипов не зарегистрировано.")
        end
        for _, c in ipairs(carriers) do
            local row = vgui.Create("DPanel", sc); row:Dock(TOP); row:SetTall(54); row:DockMargin(0, 0, 0, 6)
            row.Paint = function(_, w, h)
                draw.RoundedBox(6, 0, 0, w, h, C.card)
                local special = c.special == true
                surface.SetDrawColor(special and C.red or (c.online and C.green or C.dim))
                surface.DrawOutlinedRect(0, 0, w, h, special and 2 or 1)
                draw.SimpleText(c.name or "?", "GRMCC_Head", 14, 10, C.text)
                draw.SimpleText((special and "⚠ СПЕЦИАЛЬНЫЙ ЮНИТ" or "Носитель") .. "  •  " .. (c.faction ~= "" and c.faction or "без фракции") .. "  •  " .. (c.online and "В СЕТИ" or "ОФЛАЙН"), "GRMCC_Small", 14, 32, special and C.warn or C.dim)
                local chipNames = {}
                for _, ch in ipairs(c.chips or {}) do chipNames[#chipNames + 1] = tostring(ch.name or ch.id) end
                draw.SimpleText(table.concat(chipNames, ", "), "GRMCC_Small", w - 14, 10, C.accent, TEXT_ALIGN_RIGHT)
            end
        end
        sheet:AddSheet("Носители", carriersPanel, "icon16/user.png")

        -- Вкладка: Журнал событий
        local eventsPanel = vgui.Create("DPanel"); eventsPanel:SetPaintBackground(false)
        local sc2 = vgui.Create("DScrollPanel", eventsPanel); sc2:Dock(FILL); sc2:DockMargin(4, 4, 4, 4)
        if #events == 0 then
            local l = vgui.Create("DLabel", sc2); l:Dock(TOP); l:SetTall(40); l:SetFont("GRMCC_Head"); l:SetTextColor(C.dim)
            l:SetText("Журнал пуст. Смерти носителей экспериментальных чипов фиксируются здесь.")
        end
        for i = #events, 1, -1 do
            local ev = events[i]
            local row = vgui.Create("DPanel", sc2); row:Dock(TOP); row:SetTall(44); row:DockMargin(0, 0, 0, 5)
            row.Paint = function(_, w, h)
                draw.RoundedBox(6, 0, 0, w, h, C.card)
                draw.SimpleText(os.date("%H:%M:%S", ev.time or 0), "GRMCC_Small", 12, 6, C.dim)
                draw.SimpleText(ev.type == "death" and "☠ СМЕРТЬ СПЕЦ-ЮНИТА" or tostring(ev.type), "GRMCC_Head", 12, 22, ev.type == "death" and C.red or C.accent)
                draw.SimpleText(tostring(ev.name or "?") .. "  •  " .. tostring(ev.faction or ""), "GRMCC_Text", w - 12, 22, C.text, TEXT_ALIGN_RIGHT)
            end
        end
        sheet:AddSheet("Журнал", eventsPanel, "icon16/book.png")

        -- Вкладка: Инфо
        local infoPanel = vgui.Create("DPanel"); infoPanel:SetPaintBackground(false)
        local sc3 = vgui.Create("DScrollPanel", infoPanel); sc3:Dock(FILL); sc3:DockMargin(8, 8, 8, 8)
        local function il(text, col)
            local l = vgui.Create("DLabel", sc3); l:Dock(TOP); l:SetTall(26); l:SetFont("GRMCC_Text"); l:SetTextColor(col or C.dim); l:SetText(text); l:SetWrap(true); l:SetAutoStretchVertical(true)
        end
        il("СИСТЕМА КОНТРОЛЯ ЧИПОВ", C.accent)
        il("• Терминал ведёт реестр носителей имплантированных чипов (онлайн и офлайн).", C.text)
        il("• Носители ЭКСПЕРИМЕНТАЛЬНЫХ чипов помечаются как «специальный юнит».", C.warn)
        il("• При смерти спец-юнита члены фракций с включённым уведомлением (/factions → Расширенные настройки → «Уведомлять о смерти носителей экспериментальных чипов») получают звук npc/metropolice/die2.wav, текстовое уведомление и GPS-метку «В данном районе убит/умер специальный юнит».", C.text)
        il("• GPS-метка временная (120 секунд) и видна только уведомлённым.", C.dim)
        sheet:AddSheet("Инфо", infoPanel, "icon16/information.png")

        -- ── ВКЛАДКА «АДМИН» (только суперадмин): изъятие чипов и предметов ──
        local lp = LocalPlayer()
        if IsValid(lp) and lp:IsSuperAdmin() then
            local adminPanel = vgui.Create("DPanel"); adminPanel:SetPaintBackground(false)
            local topBar = vgui.Create("DPanel", adminPanel); topBar:Dock(TOP); topBar:SetTall(40); topBar:DockMargin(4, 4, 4, 4); topBar:SetPaintBackground(false)
            local playerCombo = vgui.Create("DComboBox", topBar)
            playerCombo:SetPos(0, 4); playerCombo:SetSize(320, 30); playerCombo:SetFont("GRMCC_Text")
            local playersList = {}
            for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                if IsValid(p) then
                    playersList[#playersList + 1] = { nick = p:Nick(), sid64 = p:SteamID64() }
                end
            end
            table.sort(playersList, function(a, b) return a.nick:lower() < b.nick:lower() end)
            for _, pl in ipairs(playersList) do
                playerCombo:AddChoice(pl.nick .. "  [" .. pl.sid64 .. "]", pl.sid64)
            end
            local showBtn = vgui.Create("DButton", topBar)
            showBtn:SetPos(330, 4); showBtn:SetSize(140, 30); showBtn:SetText("ПОКАЗАТЬ"); showBtn:SetFont("GRMCC_Text"); showBtn:SetTextColor(C.text)
            showBtn.Paint = function(self, w, h) draw.RoundedBox(5, 0, 0, w, h, self:IsHovered() and Color(80, 190, 255) or C.accent) end
            local adminScroll = vgui.Create("DScrollPanel", adminPanel); adminScroll:Dock(FILL); adminScroll:DockMargin(4, 0, 4, 4)

            local function adminRender(data)
                adminScroll:Clear()
                local t = data or { chips = {}, items = {} }
                local chips = t.chips or {}
                local items = t.items or {}
                local function head(text, col)
                    local l = vgui.Create("DLabel", adminScroll); l:Dock(TOP); l:SetTall(24); l:SetFont("GRMCC_Head"); l:SetTextColor(col or C.accent); l:SetText(text)
                end
                head("ЧИПЫ (" .. #chips .. "):", C.accent)
                if #chips == 0 then
                    local l = vgui.Create("DLabel", adminScroll); l:Dock(TOP); l:SetTall(20); l:SetFont("GRMCC_Small"); l:SetTextColor(C.dim); l:SetText("Имплантированных чипов нет.")
                end
                for _, c in ipairs(chips) do
                    local row = vgui.Create("DPanel", adminScroll); row:Dock(TOP); row:SetTall(40); row:DockMargin(0, 0, 0, 4)
                    row.Paint = function(_, w, h) draw.RoundedBox(5, 0, 0, w, h, C.card); draw.SimpleText(c.name or c.id, "GRMCC_Text", 10, 10, C.text); draw.SimpleText(tostring(c.category) .. (c.active ~= false and " • ONLINE" or " • OFF"), "GRMCC_Small", 10, 26, c.active ~= false and C.green or C.dim) end
                    local extract = vgui.Create("DButton", row); extract:Dock(RIGHT); extract:SetWide(110); extract:DockMargin(4, 6, 6, 6); extract:SetText("ИЗЪЯТЬ"); extract:SetFont("GRMCC_Small"); extract:SetTextColor(C.text)
                    extract.Paint = function(self, w, h) draw.RoundedBox(4, 0, 0, w, h, self:IsHovered() and Color(230, 100, 90) or C.red) end
                    extract.DoClick = function()
                        net.Start("GRM_ChipControl_AdminExtract")
                            net.WriteString(playerCombo:GetSelected() or "")
                            net.WriteString(c.id or "")
                        net.SendToServer()
                    end
                end
                head("ИНВЕНТАРЬ (" .. #items .. "):", C.green)
                if #items == 0 then
                    local l = vgui.Create("DLabel", adminScroll); l:Dock(TOP); l:SetTall(20); l:SetFont("GRMCC_Small"); l:SetTextColor(C.dim); l:SetText("Инвентарь пуст.")
                end
                for _, it in ipairs(items) do
                    local row = vgui.Create("DPanel", adminScroll); row:Dock(TOP); row:SetTall(38); row:DockMargin(0, 0, 0, 4)
                    row.Paint = function(_, w, h) draw.RoundedBox(5, 0, 0, w, h, C.card); draw.SimpleText(it.id .. "  x" .. tostring(it.count), "GRMCC_Text", 10, 10, C.text) end
                    local del1 = vgui.Create("DButton", row); del1:Dock(RIGHT); del1:SetWide(96); del1:DockMargin(4, 6, 6, 6); del1:SetText("УДАЛИТЬ 1"); del1:SetFont("GRMCC_Small"); del1:SetTextColor(C.text)
                    del1.Paint = function(self, w, h) draw.RoundedBox(4, 0, 0, w, h, self:IsHovered() and Color(230, 110, 90) or C.red) end
                    del1.DoClick = function()
                        net.Start("GRM_ChipControl_AdminRemove")
                            net.WriteString(playerCombo:GetSelected() or "")
                            net.WriteString(it.id or "")
                            net.WriteUInt(1, 16)
                        net.SendToServer()
                    end
                    local delAll = vgui.Create("DButton", row); delAll:Dock(RIGHT); delAll:SetWide(110); delAll:DockMargin(4, 6, 6, 6); delAll:SetText("УДАЛИТЬ ВСЕ"); delAll:SetFont("GRMCC_Small"); delAll:SetTextColor(C.text)
                    delAll.Paint = function(self, w, h) draw.RoundedBox(4, 0, 0, w, h, self:IsHovered() and Color(180, 80, 70) or Color(150, 60, 55)) end
                    delAll.DoClick = function()
                        net.Start("GRM_ChipControl_AdminRemove")
                            net.WriteString(playerCombo:GetSelected() or "")
                            net.WriteString(it.id or "")
                            net.WriteUInt(math.max(1, tonumber(it.count) or 1), 16)
                        net.SendToServer()
                    end
                end
            end

            showBtn.DoClick = function()
                local sid64 = playerCombo:GetSelected() or ""
                if sid64 == "" then return end
                net.Start("GRM_ChipControl_AdminData")
                    net.WriteString(sid64)
                net.SendToServer()
            end

            -- выбор игрока сразу показывает его данные
            playerCombo.OnSelect = function(_, _, _, data)
                net.Start("GRM_ChipControl_AdminData")
                    net.WriteString(tostring(data or ""))
                net.SendToServer()
            end

            sheet:AddSheet("Админ", adminPanel, "icon16/star.png")
            -- хук обновления данных админ-вкладки
            GRM.ChipControl._adminRender = adminRender
            GRM.ChipControl._adminCombo = playerCombo
        end

        frame:MakePopup()
    end)

    -- Админ-данные цели (обновление вкладки «Админ»)
    net.Receive("GRM_ChipControl_AdminData", function()
        local sid64 = net.ReadString()
        local data = net.ReadTable() or {}
        if GRM.ChipControl and GRM.ChipControl._adminRender then
            GRM.ChipControl._adminRender(data)
        end
    end)

    print("[GRM ChipControl] client v" .. CC.Version .. " loaded")
end
