-- ======================================================================
-- sim_qmenu_scroll — воспроизведение и проверка фикса ошибки
--   lua/vgui/dscrollpanel.lua:111: Tried to use a NULL Panel!
--   1. GetTall  2. PerformLayoutInternal  3. dscrollpanel.lua:135
--
-- Модель повторяет поведение движка: DScrollPanel держит служебный холст
-- pnlCanvas и полосу VBar, GetChildren() возвращает ИХ, а не добавленные
-- элементы. PerformLayoutInternal читает self.pnlCanvas:GetTall() — если
-- холст удалён, обращение к мёртвой панели роняет Lua.
--
-- Запуск: luajit tools/luatest/sim_qmenu_scroll.lua
-- ======================================================================

local fails, total = 0, 0
local function check(name, cond, extra)
    total = total + 1
    if cond then print("  OK   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "   " .. tostring(extra or "")) end
end

-- ── модель VGUI ──────────────────────────────────────────────────────
local Panel = {}
Panel.__index = Panel

local function mkPanel(parent, class)
    local p = setmetatable({
        __valid = true, class = class or "DPanel",
        children = {}, tall = 20, docked = nil, parent = nil,
    }, Panel)
    if parent then p:SetParent(parent) end
    return p
end

function Panel:SetParent(np)
    if self.parent then
        for i, c in ipairs(self.parent.children) do
            if c == self then table.remove(self.parent.children, i) break end
        end
    end
    self.parent = np
    if np then np.children[#np.children + 1] = self end
end

function Panel:GetChildren() return self.children end
function Panel:SetTall(v) self.tall = v end

--- Точная имитация движка: обращение к удалённой панели — ошибка Lua.
function Panel:GetTall()
    if not self.__valid then error("Tried to use a NULL Panel!", 0) end
    return self.tall
end

function Panel:Remove()
    for _, c in ipairs(self.children) do c:Remove() end
    self.__valid = false
end

function Panel:Dock(v) self.docked = v end
function Panel:DockMargin() end

--- DPanel:Clear() удаляет всех детей — это законно для обычной панели.
function Panel:Clear()
    for _, c in ipairs(self.children) do c:Remove() end
    self.children = {}
end

-- ── DScrollPanel ─────────────────────────────────────────────────────
local Scroll = setmetatable({}, { __index = Panel })
Scroll.__index = Scroll

local function mkScroll(parent)
    local s = setmetatable(mkPanel(parent, "DScrollPanel"), Scroll)
    s.pnlCanvas = mkPanel(s, "Canvas")
    s.VBar = mkPanel(s, "DVScrollBar")
    return s
end

function Scroll:GetCanvas() return self.pnlCanvas end

--- То, что падает в логе: dscrollpanel.lua:111.
function Scroll:PerformLayoutInternal()
    local _ = self.pnlCanvas:GetTall()   -- ← строка 111
    return true
end

--- AddItem парентит элемент в холст и докует его сверху.
function Scroll:AddItem(pnl)
    pnl:SetParent(self.pnlCanvas)
    pnl:Dock("TOP")
    return pnl
end

--- DScrollPanel:Clear() чистит ХОЛСТ, а не служебные панели.
function Scroll:Clear() self.pnlCanvas:Clear() end

-- ======================================================================
print("\n=== ТЕСТ 1: воспроизведение аварии (как было до фикса) ===")
do
    local sc = mkScroll(nil)
    sc:AddItem(mkPanel(nil, "row"))
    sc:AddItem(mkPanel(nil, "row"))

    check("GetChildren() отдаёт служебные панели, а не элементы",
        #sc:GetChildren() == 2 and sc:GetChildren()[1].class == "Canvas",
        #sc:GetChildren())
    check("добавленные элементы лежат в холсте", #sc:GetCanvas():GetChildren() == 2)

    -- старый способ очистки: удалить всех детей скролла
    for _, ch in ipairs(sc:GetChildren()) do ch:Remove() end

    check("после старой очистки холст мёртв", sc.pnlCanvas.__valid == false)
    local ok, err = pcall(function() return sc:PerformLayoutInternal() end)
    check("PerformLayoutInternal падает с NULL Panel",
        not ok and tostring(err):find("NULL Panel", 1, true) ~= nil, err)
end

print("\n=== ТЕСТ 2: правильная очистка через :Clear() ===")
do
    local sc = mkScroll(nil)
    sc:AddItem(mkPanel(nil, "row"))
    sc:AddItem(mkPanel(nil, "row"))

    sc:Clear()

    check("холст жив", sc.pnlCanvas.__valid == true)
    check("полоса прокрутки жива", sc.VBar.__valid == true)
    check("элементы удалены", #sc:GetCanvas():GetChildren() == 0)
    local ok = pcall(function() return sc:PerformLayoutInternal() end)
    check("раскладка не падает", ok)

    sc:AddItem(mkPanel(nil, "row"))
    check("после очистки можно наполнять заново", #sc:GetCanvas():GetChildren() == 1)
end

print("\n=== ТЕСТ 3: очистка через GetCanvas():GetChildren() ===")
do
    local sc = mkScroll(nil)
    sc:AddItem(mkPanel(nil, "row"))
    for _, ch in ipairs(sc:GetCanvas():GetChildren()) do ch:Remove() end
    sc:GetCanvas().children = {}
    check("холст пережил очистку", sc.pnlCanvas.__valid == true)
    check("раскладка не падает", pcall(function() return sc:PerformLayoutInternal() end))
end

print("\n=== ТЕСТ 4: AddItem против SetParent+Dock ===")
do
    local sc = mkScroll(nil)
    local cp = mkPanel(nil, "ControlPanel")
    sc:AddItem(cp)
    check("AddItem парентит в холст", cp.parent == sc:GetCanvas())
    check("AddItem проставляет Dock(TOP)", cp.docked == "TOP")

    -- как делали раньше: напрямую в скролл
    local sc2 = mkScroll(nil)
    local cp2 = mkPanel(nil, "ControlPanel")
    cp2:SetParent(sc2) cp2:Dock("TOP")
    check("прямой SetParent минует холст", cp2.parent == sc2 and cp2.parent ~= sc2:GetCanvas())
    check("такой сирота не удаляется через :Clear()",
        (function() sc2:Clear() return cp2.__valid end)() == true)
end

print("\n=== ТЕСТ 5: общая панель тула переживает смерть окна ===")
do
    -- controlpanel.Get(name) отдаёт ГЛОБАЛЬНУЮ панель, общую с ванильным Q.
    -- Если фрейм умирает с SetDeleteOnClose(true), панель уезжает с ним.
    local globalCP = mkPanel(nil, "ControlPanel")

    local frame = mkPanel(nil, "DFrame")
    local body = mkScroll(frame)
    body:AddItem(globalCP)

    -- OnRemove по фиксу: отвязать общую панель до смерти фрейма
    local function onRemove()
        if globalCP.__valid then
            globalCP:SetParent(nil)
        end
    end
    onRemove()
    frame:Remove()

    check("окно закрыто", frame.__valid == false)
    check("общая панель тула выжила", globalCP.__valid == true)
    check("панель отвязана от мёртвого окна", globalCP.parent == nil)

    -- контроль: без отвязки панель погибла бы
    local frame2 = mkPanel(nil, "DFrame")
    local body2 = mkScroll(frame2)
    local cp2 = mkPanel(nil, "ControlPanel")
    body2:AddItem(cp2)
    frame2:Remove()
    check("без отвязки панель умирает вместе с окном", cp2.__valid == false)
end

print("\n=== ТЕСТ 6: заглушка emptyBox не копится в скролле ===")
do
    local sc = mkScroll(nil)
    local lay = mkPanel(nil, "DIconLayout")
    sc:AddItem(lay)

    local function clearEmptyBox(s)
        if s._emptyBox and s._emptyBox.__valid then s._emptyBox:Remove() end
        s._emptyBox = nil
    end
    local function emptyBox(s, text)
        clearEmptyBox(s)
        local box = mkPanel(nil, text)
        s:AddItem(box)
        s._emptyBox = box
        return box
    end

    -- три поиска подряд, каждый ничего не нашёл
    for _ = 1, 3 do
        lay:Clear()
        clearEmptyBox(sc)
        emptyBox(sc, "Ничего не найдено")
    end

    local alive = 0
    for _, c in ipairs(sc:GetCanvas():GetChildren()) do
        if c.__valid then alive = alive + 1 end
    end
    check("в холсте только сетка и одна заглушка", alive == 2, alive)
    check("заглушка лежит в холсте, а не прямым ребёнком скролла",
        sc._emptyBox.parent == sc:GetCanvas())
    check("раскладка не падает", pcall(function() return sc:PerformLayoutInternal() end))
end

print("\n=== ТЕСТ 7: исходный код проекта соответствует правилам ===")
do
    local function read(path)
        local fh = io.open(path, "rb")
        if not fh then return nil end
        local s = fh:read("*a") fh:close()
        return s
    end

    local qmenu = read("lua/autorun/sh_grm_qmenu.lua")
    check("sh_grm_qmenu.lua читается", qmenu ~= nil)
    if qmenu then
        check("заглушка каталога снимается перед перестройкой",
            qmenu:find("clearEmptyBox(sc)", 1, true) ~= nil)
        check("окно имеет OnRemove",
            qmenu:find("f.OnRemove", 1, true) ~= nil)
        check("v4 не встраивает чужой ControlPanel",
            qmenu:find("settingsBody:AddItem(CP)", 1, true) == nil)
        local bad = qmenu:find("for _, ch in ipairs(settingsBody:GetChildren()) do", 1, true)
        check("старый опасный обход GetChildren() удалён", bad == nil)
    end

    -- по всему проекту: GetChildren()+Remove допустим только на холсте/DPanel
    local suspicious = {}
    local scan = {
        "lua/autorun/sh_grm_qmenu.lua",
        "lua/autorun/sh_grm_medical.lua",
        "lua/autorun/sh_spawn_points.lua",
        "lua/autorun/sh_grm_atm.lua",
    }
    for _, path in ipairs(scan) do
        local src = read(path)
        if src then
            for line in src:gmatch("[^\n]+") do
                if line:find("GetChildren()", 1, true) and line:find("Remove()", 1, true) then
                    -- допустимо: явный GetCanvas() либо обычная панель-контейнер
                    if not line:find("GetCanvas()", 1, true)
                        and not line:find("canvas", 1, true)
                        and not line:find("parent:GetChildren", 1, true)
                        and not line:find("body:GetChildren", 1, true) then
                        suspicious[#suspicious + 1] = path .. ": " .. line:gsub("^%s+", "")
                    end
                end
            end
        end
    end
    check("опасных обходов GetChildren() не осталось", #suspicious == 0,
        table.concat(suspicious, " | "))

    -- меню банкомата: карточка не должна парентиться в скролл до AddItem
    local atm = read("lua/autorun/sh_grm_atm.lua")
    check("sh_grm_atm.lua читается", atm ~= nil)
    if atm then
        check("card() не парентит панель прямо в DScrollPanel",
            atm:find("local isScroll = istable(parent) and isfunction(parent.AddItem)", 1, true) ~= nil)
        check("card() создаёт панель без родителя-скролла",
            atm:find('vgui.Create("DPanel", (not isScroll) and parent or nil)', 1, true) ~= nil)
    end
end

print(("\n=== ИТОГ: %d/%d, failures=%d ==="):format(total - fails, total, fails))
if fails > 0 then os.exit(1) end
