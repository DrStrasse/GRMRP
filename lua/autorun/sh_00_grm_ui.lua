-- GRM UI lifecycle guard.  All GRM windows use a stable key so repeated
-- network messages/console commands cannot leave identical dialogs stacked.
GRM = GRM or {}
GRM.UI = GRM.UI or {}

function GRM.UI.Track(key, panel)
    if not key or not panel then return panel end
    local frames = GRM.UI._frames or {}
    GRM.UI._frames = frames
    local old = frames[key]
    if IsValid(old) and old ~= panel then old:Remove() end
    frames[key] = panel
    local previous = panel.OnRemove
    panel.OnRemove = function(self)
        if previous then previous(self) end
        if frames[key] == self then frames[key] = nil end
    end
    return panel
end

function GRM.UI.Close(key)
    local frames = GRM.UI._frames or {}
    local panel = frames[key]
    if IsValid(panel) then panel:Remove() end
    if frames[key] == panel then frames[key] = nil end
end

function GRM.UI.IsOpen(key)
    return IsValid(GRM.UI._frames and GRM.UI._frames[key])
end

--[[ БЕЗОПАСНАЯ ОЧИСТКА ПАНЕЛИ (находка 27.08).

     Симптом: спам в консоли у любого игрока, открывшего окно с
     перестраиваемым содержимым:
         lua/vgui/dframe.lua:246: Tried to use a NULL Panel!
           1. SetPos - [C]:-1

     Причина. Panel:Clear() сносит ВСЕХ детей панели. Если панель — это
     DFrame, вместе с содержимым улетают его служебные кнопки btnClose,
     btnMaxim, btnMinim и заголовок lblTitle. Но PerformLayout самого
     DFrame про это не знает и на каждом кадре продолжает звать у них
     SetPos — отсюда «NULL Panel» пачками, пока окно открыто.

     Решение. GRM.UI.SafeClear(panel) убирает только СОДЕРЖИМОЕ и никогда
     не трогает служебную обвязку окна. Для обычных панелей ведёт себя
     как привычный :Clear(). ]]
function GRM.UI.SafeClear(panel)
    if not IsValid(panel) then return false end

    -- Не DFrame — обычная панель, никакой служебной обвязки нет.
    local chrome = {
        panel.btnClose, panel.btnMaxim, panel.btnMinim,
        panel.lblTitle, panel.imgIcon,
    }
    local protected, any = {}, false
    for _, ch in ipairs(chrome) do
        if IsValid(ch) then protected[ch] = true any = true end
    end
    if not any then
        if panel.Clear then panel:Clear() end
        return true
    end

    for _, ch in ipairs(panel:GetChildren() or {}) do
        if IsValid(ch) and not protected[ch] and ch._grmChrome ~= true then
            ch:Remove()
        end
    end
    return true
end

print("[GRM UI] lifecycle guard loaded")

-- Полосы HUD регистрируются из нескольких файлов. Autorun идёт по алфавиту,
-- поэтому RegisterBar должен жить ЗДЕСЬ (грузится первым), иначе вес и
-- сытость тихо не попадали в панель.
if CLIENT then
    GRM.HUD = GRM.HUD or {}
    GRM.HUD.Bars = GRM.HUD.Bars or {}
    function GRM.HUD.RegisterBar(id, def)
        id = tostring(id or "")
        if id == "" or not istable(def) or not isfunction(def.Get) then return false end
        def.id = id
        def.label = tostring(def.label or id)
        def.order = tonumber(def.order) or 100
        GRM.HUD.Bars[id] = def
        return true
    end
    function GRM.HUD.RemoveBar(id) GRM.HUD.Bars[tostring(id or "")] = nil end
    function GRM.HUD.BarList()
        local out = {}
        for _, def in pairs(GRM.HUD.Bars) do out[#out + 1] = def end
        table.sort(out, function(a, b)
            if a.order == b.order then return tostring(a.id) < tostring(b.id) end
            return a.order < b.order
        end)
        return out
    end
end

--[[--------------------------------------------------------------------
    UTF-8 БЕЗОПАСНАЯ ОБРЕЗКА (задача 10, дефект «Дзержинског»)

    string.sub режет БАЙТЫ. Кириллица в UTF-8 — 2 байта на символ, поэтому
    trim(s, 96) обрубал «…Ф.Э.Дзержинского» до «…Ф.Э.Дзержинског» ровно на
    48-м русском символе, а строку «Аналитико-прогностическое и социальное
    управление (профиль ГБ)» — до «…управление (». Это выглядело как
    «нет переноса строк», хотя перенос работал: до клиента просто доезжал
    уже обрезанный текст.

    Хуже того, обрубок мог прийтись на середину многобайтовой
    последовательности — тогда получался битый символ.

    GRM.Utf8Sub считает символы, а не байты, и никогда не рвёт символ
    пополам. Ограничения храним в СИМВОЛАХ.
----------------------------------------------------------------------]]

--- Длина строки в символах UTF-8 (а не в байтах).
function GRM.Utf8Len(s)
    s = tostring(s or "")
    if utf8 and utf8.len then
        local ok, n = pcall(utf8.len, s)
        if ok and n then return n end
    end
    -- Запасной счётчик: продолжения (10xxxxxx) не считаем за символ.
    local n = 0
    for i = 1, #s do
        local b = string.byte(s, i)
        if b < 128 or b >= 192 then n = n + 1 end
    end
    return n
end

--- Обрезать строку до maxChars СИМВОЛОВ, не разрывая символ пополам.
function GRM.Utf8Sub(s, maxChars)
    s = tostring(s or "")
    maxChars = tonumber(maxChars) or 0
    if maxChars <= 0 then return "" end
    if #s <= maxChars then return s end -- байт не больше лимита ⇒ точно влезает

    if utf8 and utf8.offset then
        local ok, off = pcall(utf8.offset, s, maxChars + 1)
        if ok and off then return string.sub(s, 1, off - 1) end
        -- offset вернул nil ⇒ символов меньше лимита, строка целиком
        if ok then return s end
    end

    local chars, i = 0, 1
    while i <= #s do
        local b = string.byte(s, i)
        local size = (b < 128 and 1) or (b < 224 and 2) or (b < 240 and 3) or 4
        if chars + 1 > maxChars then return string.sub(s, 1, i - 1) end
        chars, i = chars + 1, i + size
    end
    return s
end

--- Обрезать до maxChars символов и добавить «…», если строка длиннее.
-- Для подписей в интерфейсе: «Александр Фон Грённер» → «Александр Фон…».
function GRM.Utf8Ellipsis(s, maxChars)
    s = tostring(s or "")
    maxChars = tonumber(maxChars) or 0
    if maxChars <= 0 then return "" end
    if GRM.Utf8Len(s) <= maxChars then return s end
    return GRM.Utf8Sub(s, math.max(1, maxChars - 1)) .. "…"
end

--[[ Кнопка в стиле GRM — одна фабрика на проект.

     Была четырьмя дословными копиями (доска объявлений, вещание, F4-меню,
     работы), различавшимися ТОЛЬКО именем шрифта.

     Кроме дублирования копии стоили кадров: `Paint` создавал по два
     `Color()` каждый кадр наведения (§6.1.8 — не создавать таблицы в
     render-кадре). На экране десятки кнопок, кадр 60 Гц — это мусор
     сборщику на ровном месте. Здесь оба цвета считаются ОДИН раз при
     создании кнопки, в кадре остаётся только выбор готового.
]]
local BTN_DISABLED = Color(60, 65, 75)
local BTN_RADIUS = 6

--- Создать кнопку GRM.
-- @param parent панель-родитель
-- @param text   подпись
-- @param font   шрифт модуля (у каждого модуля свой размерный набор)
-- @param color  базовый цвет; наведение осветляется на +25 по каналу
function GRM.UI.Button(parent, text, font, color)
    local btn = vgui.Create("DButton", parent)
    btn:SetText(text)
    btn:SetFont(font or "DermaDefaultBold")
    btn:SetTextColor(color_white)

    local base = color or Color(48, 204, 255)
    local hover = Color(math.min(255, base.r + 25), math.min(255, base.g + 25),
        math.min(255, base.b + 25))

    btn.Paint = function(self, w, h)
        local fill = base
        if not self:IsEnabled() then
            fill = BTN_DISABLED
        elseif self:IsHovered() then
            fill = hover
        end
        draw.RoundedBox(BTN_RADIUS, 0, 0, w, h, fill)
    end

    return btn
end
