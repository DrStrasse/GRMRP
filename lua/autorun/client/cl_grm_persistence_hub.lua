if not CLIENT then return end

local rows = {
    { id = "phone", name = "Телефония", desc = "Телефоны, АТС и объекты связи карты." },
    { id = "cctv", name = "CCTV", desc = "Камеры, мониторы и серверы наблюдения." },
    { id = "alarm", name = "Сигнализации", desc = "Хабы, терминалы, динамики и тревожные сети." },
    { id = "factory", name = "Завод", desc = "Станки, мусорки, склады, сток и запасы." },
    { id = "logistics", name = "Логистика", desc = "Погрузочные точки, склады и оружейные шкафы." },
    { id = "vending", name = "Торговые автоматы", desc = "Автоматы еды и их позиции на текущей карте." },
    { id = "roomtap", name = "RoomTap", desc = "Чипы, серверы и терминалы прослушки." },
    { id = "wanted", name = "Розыск", desc = "База розыска и связанные данные." },
    { id = "mining", name = "Рудные узлы", desc = "Сохранённые рудные узлы и оборудование." },
    { id = "doors", name = "Двери", desc = "Двери, категории, замки и ордера текущей карты." },
    { id = "arrest", name = "Арест", desc = "Камеры, точки, группы и привязки системы ареста." },
    { id = "vendors", name = "Торгаши", desc = "Конкретные NPC, типы, позиции, цены и лимиты товаров." },
    { id = "vehicle_dealers", name = "Дилеры и гаражи", desc = "NPC дилеров, точки выдачи, ассортимент и гаражи персонажей." },
    { id = "garages", name = "Гаражи карты", desc = "Зоны гаражей, места стоянки, стойки вызова и привязки дилеров." },
    { id = "quests", name = "Квестовая экосистема", desc = "Квесты, NPC, зоны, кат-сцены и прогресс персонажей." },
    { id = "garbage_bins", name = "Мусорки", desc = "Физические контейнеры мусоровоза; точки маршрута сохраняются отдельно конфигом работ." },
    { id = "electronics", name = "Электроника и интернет", desc = "Компьютеры, роутеры, принтеры, кабели, аккаунты и файлы." },
    { id = "perm", name = "Универсальные entity", desc = "Перм-энтити: кейпады, гардеробы и закреплённые объекты." },
}

local C = {
    bg = Color(12, 17, 25, 252), head = Color(22, 29, 41), card = Color(25, 34, 48),
    text = Color(239, 244, 250), dim = Color(157, 171, 190), blue = Color(72, 153, 255),
    green = Color(70, 201, 128), red = Color(222, 87, 91), orange = Color(241, 157, 78),
}
surface.CreateFont("GRMPersistTitle", { font = "Roboto", size = 21, weight = 900, extended = true })
surface.CreateFont("GRMPersistBody", { font = "Roboto", size = 14, weight = 600, extended = true })
surface.CreateFont("GRMPersistSmall", { font = "Roboto", size = 12, weight = 500, extended = true })

local frame
local function btn(parent, text, color)
    local b = vgui.Create("DButton", parent)
    b:SetText(text) b:SetFont("GRMPersistBody") b:SetTextColor(color_white)
    b.Paint = function(self, w, h)
        local c = color
        if self:IsHovered() then c = Color(math.min(c.r + 18, 255), math.min(c.g + 18, 255), math.min(c.b + 18, 255)) end
        draw.RoundedBox(6, 0, 0, w, h, c)
    end
    return b
end

local function open()
    if IsValid(frame) then frame:MakePopup() return end
    frame = vgui.Create("DFrame")
    frame:SetSize(820, 720) frame:Center() frame:MakePopup() frame:SetTitle("") frame:ShowCloseButton(false)
    frame:SetDeleteOnClose(true)
    frame.Paint = function(_, w, h)
        draw.RoundedBox(10, 0, 0, w, h, C.bg)
        draw.RoundedBoxEx(10, 0, 0, w, 62, C.head, true, true, false, false)
        draw.SimpleText("GRM  /  СОХРАНЕНИЕ КАРТЫ", "GRMPersistSmall", 22, 18, C.blue, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Единая панель персистентности", "GRMPersistTitle", 22, 43, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    frame.OnRemove = function() if frame == frame then frame = nil end end
    local close = btn(frame, "×", C.red) close:SetPos(778, 15) close:SetSize(30, 30) close.DoClick = function() frame:Close() end

    local hint = vgui.Create("DLabel", frame)
    hint:SetPos(22, 77) hint:SetSize(770, 35) hint:SetFont("GRMPersistSmall") hint:SetTextColor(C.dim)
    hint:SetText("Кнопки работают для текущей карты: сохраняют координаты, углы, модели и настройки модулей. Загрузка восстанавливает объекты без ручного поиска команд.") hint:SetWrap(true)

    local allSave = btn(frame, "СОХРАНИТЬ ВСЁ", C.green) allSave:SetPos(22, 120) allSave:SetSize(370, 40)
    local allLoad = btn(frame, "ЗАГРУЗИТЬ ВСЁ", C.blue) allLoad:SetPos(408, 120) allLoad:SetSize(370, 40)
    allSave.DoClick = function() net.Start("GRM_Persistence_Action") net.WriteString("all_save") net.SendToServer() end
    allLoad.DoClick = function() Derma_Query("Загрузить все объекты поверх текущей карты? Модули используют защиту от дублей.", "Загрузка карты", "Загрузить", function() net.Start("GRM_Persistence_Action") net.WriteString("all_load") net.SendToServer() end, "Отмена") end

    local scroll = vgui.Create("DScrollPanel", frame) scroll:SetPos(22, 178) scroll:SetSize(756, 510)
    for _, row in ipairs(rows) do
        local p = vgui.Create("DPanel", scroll) p:Dock(TOP) p:SetTall(66) p:DockMargin(0, 0, 0, 8)
        p.Paint = function(_, w, h) draw.RoundedBox(7, 0, 0, w, h, C.card); draw.RoundedBox(4, 0, 0, 4, h, C.orange) end
        local title = vgui.Create("DLabel", p) title:SetPos(18, 10) title:SetSize(300, 22) title:SetFont("GRMPersistBody") title:SetTextColor(C.text) title:SetText(row.name)
        local desc = vgui.Create("DLabel", p) desc:SetPos(18, 34) desc:SetSize(410, 20) desc:SetFont("GRMPersistSmall") desc:SetTextColor(C.dim) desc:SetText(row.desc)
        local save = btn(p, "Сохранить", C.green) save:SetPos(500, 16) save:SetSize(120, 34)
        local load = btn(p, "Загрузить", C.blue) load:SetPos(632, 16) load:SetSize(110, 34)
        save.DoClick = function() net.Start("GRM_Persistence_Action") net.WriteString(row.id .. "_save") net.SendToServer() end
        load.DoClick = function() net.Start("GRM_Persistence_Action") net.WriteString(row.id .. "_load") net.SendToServer() end
    end
end

net.Receive("GRM_Persistence_Open", open)
net.Receive("GRM_Persistence_Result", function()
    local ok, text = net.ReadBool(), net.ReadString()
    notification.AddLegacy(text, ok and NOTIFY_GENERIC or NOTIFY_ERROR, 6)
    surface.PlaySound(ok and "buttons/button14.wav" or "buttons/button10.wav")
end)

local function requestPersistenceMenu()
    if IsValid(LocalPlayer()) and LocalPlayer():IsSuperAdmin() then
        net.Start("GRM_Persistence_Open") net.SendToServer()
    end
end

concommand.Add("grm_persistence_admin", requestPersistenceMenu)
concommand.Add("grm_persistence", requestPersistenceMenu)

hook.Add("PlayerSayTransform", "GRM_Persistence_Command", function(ply, data)
    if ply ~= LocalPlayer() then return end
    local text = data and data[1] or ""
    if string.lower(string.Trim(text)) == "/grm_persistence" then
        open() data[1] = "" return true
    end
end)
