--[[--------------------------------------------------------------------
    grm_money_launderer — клиент: 3D2D + E-меню (находка 179e)
----------------------------------------------------------------------]]
include("shared.lua")

surface.CreateFont("GRMLaunder_Title", { font = "Roboto", size = 15, weight = 900, extended = true })
surface.CreateFont("GRMLaunder_Normal", { font = "Roboto", size = 12, weight = 600, extended = true })
surface.CreateFont("GRMLaunder_Small", { font = "Roboto", size = 10, weight = 500, extended = true })

local function money(n)
    return GRM and GRM.Format and GRM.Format(tonumber(n) or 0) or (tostring(math.floor(tonumber(n) or 0)) .. " GRM")
end

--[[ ПОСЛЕДНИЕ ДАННЫЕ МЕНЮ — ОБЪЯВЛЕНЫ ДО ENT:Draw, КОТОРАЯ ИХ ЧИТАЕТ.
     Табличка над отмывщиком показывает остаток кулдауна из этой таблицы.
     Раньше объявление стояло ниже Draw, поэтому Draw обращалась к
     глобалу nil: КД на табличке не появлялся никогда. ]]
local lastMenuData = {}

function ENT:Draw()
    self:DrawModel()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    if ply:GetPos():DistToSqr(self:GetPos()) > 700 * 700 then return end

    local pos = self:GetPos() + self:GetUp() * 78
    local ang = Angle(0, EyeAngles().y - 90, 90)
    cam.Start3D2D(pos, ang, 0.07)
        local w, h = 320, 112
        draw.RoundedBox(8, -w/2, -h/2, w, h, Color(8, 12, 18, 225))
        draw.RoundedBox(6, -w/2 + 5, -h/2 + 5, w - 10, h - 10, Color(16, 24, 34, 235))
        draw.SimpleText("ОТМЫВЩИК ДЕНЕГ", "GRMLaunder_Title", 0, -46, Color(120, 210, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        local active = self:GetEventActive()
        local col = active and Color(255, 120, 90) or Color(120, 230, 150)
        -- Находка 180c: 3D2D показывает и КД (GRM.HeistCooldownLeft — NWVar
        -- не нужен: клиент получает cooldownLeft через SendMenu; здесь
        -- фолбэк по переданным данным не доступен — рисуем только если
        -- ивент не активен и есть известный КД из последнего меню).
        local cdLeft3D = 0
        if not active and lastMenuData and lastMenuData.cooldownLeft then cdLeft3D = math.max(0, math.floor(tonumber(lastMenuData.cooldownLeft) or 0)) end
        -- Находка 180f: ожидание старта — PreStartAt это NWVar, клиент читает сам
        local preLeft3D = math.max(0, math.floor((self:GetPreStartAt() or 0) - CurTime()))
        local line
        if active then
            line = "ИВЕНТ: ОГРАБЛЕНИЕ  •  " .. tostring(math.max(0, math.floor((self:GetEventEndsAt() or 0) - CurTime()))) .. " сек"
        elseif preLeft3D > 0 then
            line = "СТАРТ ЧЕРЕЗ " .. string.format("%02d:%02d", math.floor(preLeft3D / 60), preLeft3D % 60)
            col = Color(255, 200, 90)
        elseif cdLeft3D > 0 then
            line = "ПЕРЕЗАГРУЗКА: " .. string.format("%02d:%02d", math.floor(cdLeft3D / 60), cdLeft3D % 60)
            col = Color(255, 170, 90)
        else
            line = "Набор участников: " .. tostring(self:GetParticipantCount() or 0) .. " / " .. tostring(self:GetMinParticipants() or 2)
        end
        draw.SimpleText(line, "GRMLaunder_Title", 0, -24, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("Сдано: " .. money(self:GetMoneyHeld() or 0) .. " / " .. money(self:GetGoalMoney() or 0), "GRMLaunder_Normal", 0, 4, Color(255, 220, 90), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("E — взять задание / сдать деньги / настройка", "GRMLaunder_Small", 0, 30, Color(140, 155, 175), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        local allowed = tostring(self:GetAllowedFactions() or "")
        draw.SimpleText(allowed ~= "" and ("Фракции: " .. allowed) or "Фракции: любые", "GRMLaunder_Small", 0, 46, Color(110, 130, 150), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    cam.End3D2D()
end

-- ── E-меню ──
local C = {
    bg = Color(15, 20, 30, 248), panel = Color(30, 40, 56, 245), blue = Color(75, 155, 255),
    green = Color(80, 220, 130), red = Color(230, 85, 75), yellow = Color(245, 195, 70),
    text = Color(245, 248, 255), dim = Color(160, 172, 190),
}
local menuFrame = nil
-- Находка 180c: последние данные меню нужны 3D2D-табличке для КД.
-- lastMenuData объявлена в начале файла (до ENT:Draw); второе `local`
-- здесь создавало бы ВТОРУЮ переменную, и табличка продолжала бы читать
-- пустую первую.

local function act(ent, action, a, b, c, d, e)
    if not IsValid(ent) then return end
    net.Start("GRM_Heist_Action")
        net.WriteEntity(ent)
        net.WriteString(action)
        if action == "config" then
            net.WriteUInt(math.max(1, math.floor(tonumber(a) or 2)), 16)
            net.WriteUInt(math.max(1000, math.floor(tonumber(b) or 500000)), 32)
            net.WriteString(tostring(c or ""))
        elseif action == "config_full" then
            net.WriteUInt(math.max(1, math.floor(tonumber(a) or 2)), 16)
            net.WriteUInt(math.max(1000, math.floor(tonumber(b) or 500000)), 32)
            net.WriteTable(istable(c) and c or {})
            -- Находка 180c: длительность КД ограбления (минуты)
            net.WriteUInt(math.max(0, math.floor(tonumber(d) or 0)), 16)
            -- Находка 180h: чеклист гос.структур
            net.WriteTable(istable(e) and e or {})
        end
    net.SendToServer()
end

net.Receive("GRM_Heist_Open", function()
    local ent = net.ReadEntity()
    local d = net.ReadTable() or {}
    if not IsValid(ent) then return end
    lastMenuData = d
    local saveFn = nil -- заполняется в canManage-блоке (находка 179u)
    -- Находка 180c: формат оставшегося времени КД
    local function fmtCD(s)
        s = math.max(0, math.floor(tonumber(s) or 0))
        return string.format("%02d:%02d", math.floor(s / 60), s % 60)
    end

    if IsValid(menuFrame) then menuFrame:Remove() end
    menuFrame = vgui.Create("DFrame")
    menuFrame:SetTitle("")
    menuFrame:SetSize(620, 880)
    menuFrame:Center()
    menuFrame:MakePopup()
    menuFrame.Paint = function(_, w, h)
        draw.RoundedBox(9, 0, 0, w, h, C.bg)
        draw.RoundedBoxEx(9, 0, 0, w, 52, Color(26, 36, 52, 250), true, true, false, false)
        draw.SimpleText("ОТМЫВЩИК ДЕНЕГ — ОГРАБЛЕНИЕ", "GRMLaunder_Title", 16, 26, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    local body = vgui.Create("DPanel", menuFrame)
    body:Dock(FILL)
    body:DockMargin(12, 62, 12, 12)
    body:SetPaintBackground(false)

    local info = vgui.Create("DPanel", body)
    info:Dock(TOP)
    info:SetTall(140)
    info:DockMargin(0, 0, 0, 10)
    info.Paint = function(_, w, h)
        draw.RoundedBox(8, 0, 0, w, h, C.panel)
        local active = d.eventActive
        local col = active and C.red or C.green
        -- Находка 180c: при активном КД статус — «ПЕРЕЗАГРУЗКА»
        local cdLeft = math.max(0, math.floor(tonumber(d.cooldownLeft) or 0))
        local status = "НАБОР УЧАСТНИКОВ"
        -- Находка 180f: идёт ожидание старта 40 сек
        local preLeft = math.max(0, math.floor(tonumber(d.preStartLeft) or 0))
        if preLeft > 0 then status = "СТАРТ ЧЕРЕЗ " .. fmtCD(preLeft) col = Color(255, 200, 90) end
        if cdLeft > 0 then status = "ПЕРЕЗАГРУЗКА: " .. fmtCD(cdLeft) col = Color(255, 170, 90) end
        if active then status = "ИВЕНТ ИДЁТ: ОГРАБЛЕНИЕ" col = C.red end
        draw.SimpleText(status, "GRMLaunder_Title", 14, 18, col, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Участники: " .. tostring(d.participantCount or 0) .. " / минимум " .. tostring(d.minParticipants or 2), "GRMLaunder_Normal", 14, 46, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Сдано отмывщику: " .. money(d.moneyHeld or 0) .. " / " .. money(d.goalMoney or 0), "GRMLaunder_Normal", 14, 70, C.yellow, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Ваша фракция: " .. tostring(d.myFaction or "—") .. (d.factionAllowed and "  (доступна)" or "  (НЕ доступна)"), "GRMLaunder_Small", 14, 96, d.factionAllowed and C.green or C.red, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        -- находка 179f: цель ивента
        local tp = d.targetPos
        local tTxt = tp and ("Цель: Рейхсбанк (" .. ("%.0f %.0f"):format(tp.x, tp.y) .. ")") or "Цель: авто (ближайшее хранилище)"
        draw.SimpleText(tTxt, "GRMLaunder_Small", 14, 116, d.hasTarget and Color(255, 200, 120) or C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end

    -- Находка 180f: список РП-имён участников («криминал»)
    local plist = istable(d.participantList) and d.participantList or {}
    if #plist > 0 then
        local pnl = vgui.Create("DPanel", body)
        pnl:Dock(TOP)
        pnl:SetTall(math.min(110, 34 + math.ceil(#plist / 2) * 16))
        pnl:DockMargin(0, 0, 0, 8)
        pnl.Paint = function(_, w, h)
            draw.RoundedBox(8, 0, 0, w, h, C.panel)
            draw.SimpleText("УЧАСТНИКИ (КРИМИНАЛ): " .. #plist, "GRMLaunder_Small", 10, 9, C.yellow, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        local names = {}
        for _, r in ipairs(plist) do names[#names + 1] = tostring(r.name or "?") end
        local lbl = vgui.Create("DLabel", pnl)
        lbl:SetPos(10, 26)
        lbl:SetSize(560, pnl:GetTall() - 32)
        lbl:SetFont("GRMLaunder_Small")
        lbl:SetTextColor(C.text)
        lbl:SetWrap(true)
        lbl:SetText(table.concat(names, ", "))
    end

    local function addBtn(text, col, fn, tall)
        local b = vgui.Create("DButton", body)
        b:Dock(TOP)
        b:SetTall(tall or 40)
        b:DockMargin(0, 0, 0, 8)
        b:SetText("")
        b._btnText = text -- диагн. метка (тесты/отладка)
        b.Paint = function(self, w, h)
            local c = self:IsHovered() and Color(math.min(col.r + 25, 255), math.min(col.g + 25, 255), math.min(col.b + 25, 255)) or col
            draw.RoundedBox(7, 0, 0, w, h, c)
            draw.SimpleText(text, "GRMLaunder_Normal", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        b.DoClick = fn
        return b
    end

    -- Взять задание / отменить участие (находка 179m)
    if not d.eventActive then
        if d.cooldownLeft and d.cooldownLeft > 0 then
            -- Находка 180c: КД активен — кнопка заблокирована с таймером
            addBtn("⏳ ОГРАБЛЕНИЕ НА ПЕРЕЗАГРУЗКЕ: " .. fmtCD(d.cooldownLeft), Color(80, 80, 90), function() end)
        elseif d.preStartLeft and d.preStartLeft > 0 then
            -- Находка 180f: минимум набран — идёт ожидание старта 40 сек
            addBtn("⏳ ИВЕНТ НАЧНЁТСЯ ЧЕРЕЗ " .. fmtCD(d.preStartLeft), Color(110, 110, 90), function() end)
        elseif d.isParticipant then
            addBtn("✓ ВЫ В СПИСКЕ УЧАСТНИКОВ", Color(90, 100, 120), function() end)
            addBtn("✕ ОТМЕНИТЬ УЧАСТИЕ", C.red, function()
                act(ent, "leave")
            end)
        else
            addBtn("ВЗЯТЬ ЗАДАНИЕ НА ОГРАБЛЕНИЕ", C.green, function()
                act(ent, "job")
            end)
        end
    elseif d.eventActive and d.isParticipant then
        -- Находка 179p: во время ивента отмена ЗАПРЕЩЕНА — кнопка
        -- заблокирована (серая), с понятной подписью
        addBtn("✕ ОТМЕНА УЧАСТИЯ В МОМЕНТ ИВЕНТА ЗАПРЕЩЕНА", Color(80, 80, 90), function() end, 40)
    end
    -- Сдать деньги (во время ивента)
    if d.eventActive then
        addBtn("СДАТЬ ДЕНЬГИ (сумка + паллеты рядом)", C.yellow, function()
            act(ent, "deposit")
        end)
    end

    -- Настройка (суперадмин) — находка 179g: полноценное меню с чекбоксами
    if d.canManage then
        addBtn("⚑ ЦЕЛЬ: хранилище под прицелом", C.yellow, function()
            act(ent, "set_target")
        end)
        addBtn("✕ Сбросить цель (авто: хранилище)", Color(120, 110, 130), function()
            act(ent, "clear_target")
        end)

        -- заголовок настройки
        local cfgTitle = vgui.Create("DLabel", body)
        cfgTitle:Dock(TOP)
        cfgTitle:SetTall(24)
        cfgTitle:SetFont("GRMLaunder_Title")
        cfgTitle:SetTextColor(C.text)
        cfgTitle:SetText("НАСТРОЙКА (суперадмин)")

        -- минимум участников
        local minRow = vgui.Create("DPanel", body)
        minRow:Dock(TOP)
        minRow:SetTall(30)
        minRow:SetPaintBackground(false)
        local minLbl = vgui.Create("DLabel", minRow)
        minLbl:SetPos(4, 6) minLbl:SetSize(180, 20) minLbl:SetFont("GRMLaunder_Small")
        minLbl:SetTextColor(C.text) minLbl:SetText("Минимум участников:")
        -- Находка 179s: значение читается из ПОЛЯ (GetValue) в момент
        -- сохранения — не из замыкания, обновляемого колбэком (OnValueChanged
        -- мог не срабатывать, и уходили старые числа).
        local minWang = vgui.Create("DNumberWang", minRow)
        minWang:SetPos(190, 2) minWang:SetSize(90, 24)
        minWang:SetMin(1) minWang:SetMax(32) minWang:SetDecimals(0)
        minWang:SetValue(d.minParticipants or 2)
        minWang._field = "min" -- диагн. метка (тесты/отладка)

        -- цель (сумма)
        local goalRow = vgui.Create("DPanel", body)
        goalRow:Dock(TOP)
        goalRow:SetTall(30)
        goalRow:SetPaintBackground(false)
        local goalLbl = vgui.Create("DLabel", goalRow)
        goalLbl:SetPos(4, 6) goalLbl:SetSize(180, 20) goalLbl:SetFont("GRMLaunder_Small")
        goalLbl:SetTextColor(C.text) goalLbl:SetText("Цель (сумма):")
        local goalWang = vgui.Create("DNumberWang", goalRow)
        goalWang:SetPos(190, 2) goalWang:SetSize(140, 24)
        goalWang:SetMin(1000) goalWang:SetMax(100000000) goalWang:SetDecimals(0)
        goalWang:SetValue(d.goalMoney or 500000)
        goalWang._field = "goal" -- диагн. метка (тесты/отладка)

        -- Находка 180c: КД между ограблениями (минуты)
        local cdRow = vgui.Create("DPanel", body)
        cdRow:Dock(TOP)
        cdRow:SetTall(30)
        cdRow:SetPaintBackground(false)
        local cdLbl = vgui.Create("DLabel", cdRow)
        cdLbl:SetPos(4, 6) cdLbl:SetSize(180, 20) cdLbl:SetFont("GRMLaunder_Small")
        cdLbl:SetTextColor(C.text) cdLbl:SetText("КД между ограблениями (мин):")
        local cdWang = vgui.Create("DNumberWang", cdRow)
        cdWang:SetPos(190, 2) cdWang:SetSize(90, 24)
        cdWang:SetMin(1) cdWang:SetMax(240) cdWang:SetDecimals(0)
        cdWang:SetValue(math.max(1, math.floor((d.cooldownDuration or 1800) / 60)))
        cdWang._field = "cd" -- диагн. метка (тесты/отладка)

        -- фракции: чекбоксы в скролле (список существующих)
        local facLbl = vgui.Create("DLabel", body)
        facLbl:Dock(TOP)
        facLbl:SetTall(20)
        facLbl:SetFont("GRMLaunder_Small")
        facLbl:SetTextColor(C.text)
        facLbl:SetText("Фракции, которым можно брать задание (пусто = любые):")

        local facScroll = vgui.Create("DScrollPanel", body)
        facScroll:Dock(TOP)
        facScroll:SetTall(150)
        facScroll:DockMargin(0, 0, 0, 4)
        facScroll.Paint = function(_, w, h)
            draw.RoundedBox(6, 0, 0, w, h, C.panel)
        end

        local allowedSet = {}
        if istable(d.allowedFactions) then
            for _, f in ipairs(d.allowedFactions) do allowedSet[f] = true end
        elseif isstring(d.allowedFactions) then
            for f in string.gmatch(d.allowedFactions or "", "([^,]+)") do
                allowedSet[string.Trim(f)] = true
            end
        end
        -- Находка 179s: строки фракций — ЦЕЛИКОМ кликабельные кнопки
        -- (у DCheckBoxLabel клик работал только по квадратику 20×20, по
        -- названию — нет; «выбор не сохранялся»). Состояние хранится в
        -- facState и читается при сохранении.
        local facState = {}
        local facList = istable(d.factionsList) and d.factionsList or {}
        if #facList == 0 then
            local l = vgui.Create("DLabel", facScroll)
            l:Dock(TOP) l:SetTall(24) l:SetFont("GRMLaunder_Small") l:SetTextColor(C.dim)
            l:SetText("Фракций пока нет — создайте их в /factions.")
        end
        for _, fname in ipairs(facList) do
            facState[fname] = allowedSet[fname] == true
            local row = vgui.Create("DButton", facScroll)
            row:Dock(TOP)
            row:SetTall(26)
            row:DockMargin(2, 1, 2, 1)
            row:SetText("")
            row._facName = fname -- диагн. метка (тесты/отладка)
            row.Paint = function(self, w, h)
                local on = facState[fname]
                local bg = self:IsHovered() and Color(48, 62, 84, 245) or Color(32, 44, 62, 245)
                draw.RoundedBox(4, 0, 0, w, h, bg)
                -- квадрат-«чекбокс»
                draw.RoundedBox(3, 8, h / 2 - 7, 14, 14, on and C.blue or Color(18, 26, 38, 255))
                if on then
                    draw.SimpleText("✔", "GRMLaunder_Small", 15, h / 2 + 1, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
                draw.SimpleText(fname, "GRMLaunder_Small", 30, h / 2 + 1, on and C.text or C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            row.DoClick = function()
                facState[fname] = not facState[fname]
            end
        end

        -- Находка 180h: ЧЕКЛИСТ ГОС.СТРУКТУР (кто получает награду за
        -- победу/защиту города; учитываются по киллам криминала)
        local govLbl = vgui.Create("DLabel", body)
        govLbl:Dock(TOP)
        govLbl:SetTall(20)
        govLbl:SetFont("GRMLaunder_Small")
        govLbl:SetTextColor(C.yellow)
        govLbl:SetText("ГОС.СТРУКТУРЫ (награда за победу — по киллам криминала):")

        local govScroll = vgui.Create("DScrollPanel", body)
        govScroll:Dock(TOP)
        govScroll:SetTall(140)
        govScroll:DockMargin(0, 0, 0, 4)
        govScroll.Paint = function(_, w, h)
            draw.RoundedBox(6, 0, 0, w, h, C.panel)
        end

        local govSet = {}
        for f in string.gmatch(tostring(d.govFactions or ""), "([^,]+)") do
            govSet[string.Trim(f)] = true
        end
        local govState = {}
        local govKills = istable(d.govKills) and d.govKills or {}
        if #facList == 0 then
            local l = vgui.Create("DLabel", govScroll)
            l:Dock(TOP) l:SetTall(24) l:SetFont("GRMLaunder_Small") l:SetTextColor(C.dim)
            l:SetText("Фракций пока нет — создайте их в /factions.")
        end
        for _, fname in ipairs(facList) do
            govState[fname] = govSet[fname] == true
            local row = vgui.Create("DButton", govScroll)
            row:Dock(TOP)
            row:SetTall(24)
            row:DockMargin(2, 1, 2, 1)
            row:SetText("")
            row._govName = fname -- диагн. метка (тесты/отладка)
            row.Paint = function(self, w, h)
                local on = govState[fname]
                local bg = self:IsHovered() and Color(48, 62, 84, 245) or Color(32, 44, 62, 245)
                draw.RoundedBox(4, 0, 0, w, h, bg)
                draw.RoundedBox(3, 8, h / 2 - 6, 12, 12, on and Color(255, 200, 90) or Color(18, 26, 38, 255))
                if on then
                    draw.SimpleText("✔", "GRMLaunder_Small", 14, h / 2 + 1, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
                local k = govKills[fname] or 0
                draw.SimpleText(fname .. (k > 0 and ("  •  киллов: " .. k) or ""), "GRMLaunder_Small", 26, h / 2 + 1, on and C.text or C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            row.DoClick = function()
                govState[fname] = not govState[fname]
            end
        end

        -- сохранить: кнопка вынесена в ФИКСИРОВАННУЮ нижнюю панель
        -- (находка 179u: в TOP-стеке она уезжала за нижний край окна
        -- и была не видна — особенно при активном ивенте с лишними
        -- кнопками). saveFn вызывается из панели внизу окна.
        saveFn = function()
            local selected = {}
            for fname, on in pairs(facState) do
                if on then selected[#selected + 1] = fname end
            end
            table.sort(selected)
            -- Находка 179s: числа читаются из полей (GetValue) — всегда
            -- текущее значение, независимо от колбэков.
            local mv = math.max(1, math.floor(tonumber(minWang:GetValue()) or 2))
            local gv = math.max(1000, math.floor(tonumber(goalWang:GetValue()) or 500000))
            -- Находка 180c: длительность КД (минуты)
            local cdv = math.max(1, math.floor(tonumber(cdWang:GetValue()) or 30))
            -- Находка 180h: выбранные гос.структуры
            local govSel = {}
            for fname, on in pairs(govState) do
                if on then govSel[#govSel + 1] = fname end
            end
            table.sort(govSel)
            act(ent, "config_full", mv, gv, selected, cdv, govSel)
        end
    end

    local hint = vgui.Create("DLabel", body)
    hint:Dock(BOTTOM)
    hint:SetTall(48)
    hint:SetFont("GRMLaunder_Small")
    hint:SetTextColor(C.dim)
    hint:SetWrap(true)
    hint:SetText("Когда участников станет достаточно — автоматически начнётся ивент «ОГРАБЛЕНИЕ» (50 минут, баннер на весь сервер, музыка). Деньги сдаются отмывщику: сумка ограбления / паллеты рядом / /bag_unload рядом с ним.")

    -- Находка 179u/179x/179y: кнопка «СОХРАНИТЬ НАСТРОЙКИ» — в нижней
    -- панели, КОМПАКТНАЯ (170×26, мелкий шрифт), по центру.
    if saveFn then
        local saveBar = vgui.Create("DPanel", body)
        saveBar:Dock(BOTTOM)
        saveBar:SetTall(40)
        saveBar:DockMargin(0, 0, 0, 6)
        saveBar:SetPaintBackground(false)
        saveBar._btnText = "SAVE_BAR" -- диагн. метка (тесты/отладка)
        local sb = vgui.Create("DButton", saveBar)
        sb:SetSize(170, 26)
        sb._btnText = "💾 СОХРАНИТЬ НАСТРОЙКИ" -- диагн. метка (тесты/отладка)
        sb.Paint = function(self, w, h)
            local c = self:IsHovered() and Color(110, 240, 160) or C.green
            draw.RoundedBox(5, 0, 0, w, h, c)
            draw.SimpleText("💾 СОХРАНИТЬ НАСТРОЙКИ", "GRMLaunder_Small", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        sb.DoClick = saveFn
        function saveBar:PerformLayout()
            sb:SetSize(170, 26)
            sb:SetPos(math.max(0, (self:GetWide() - 170) / 2), math.max(0, (self:GetTall() - 26) / 2))
        end
    end
end)
