--[[--------------------------------------------------------------------
    GRM Sound Browser — выбор звука из всех ресурсов игры и аддонов.

    ЗАКАЗ ВЛАДЕЛЬЦА (29.08):

      «Выбор должен быть из меню звуков, все звуки и саунды игры +
       аддонов должны сканироваться и выводиться в специальное меню,
       открываемое кнопочкой в меню квестов в подменю катсцены в её
       настройках.»

    ЧТО БЫЛО. Путь к звуку вписывали руками в текстовое поле. Ошибся в
    букве — тишина без объяснений; узнать, какие звуки вообще есть на
    сервере, было неоткуда.

    КАК УСТРОЕНО СКАНИРОВАНИЕ. file.Find по "GAME" видит и содержимое
    игры, и распакованные аддоны, и смонтированные .gma — то есть ровно
    то, что доступно клиенту. Обход рекурсивный от папки sound/.

    ПОЧЕМУ ПОРЦИЯМИ. Полное дерево звуков — десятки тысяч файлов. Обойти
    его за один кадр значит подвесить клиент на несколько секунд, и
    человек решит, что игра зависла. Поэтому обход идёт по кадрам через
    Think с бюджетом времени, а окно показывает прогресс.

    РЕЗУЛЬТАТ КЭШИРУЕТСЯ на сессию: второе открытие мгновенное.
----------------------------------------------------------------------]]
if not CLIENT then return end

GRM = GRM or {}
GRM.SoundBrowser = GRM.SoundBrowser or {}
local SB = GRM.SoundBrowser

surface.CreateFont("GRMSB_Title", { font = "Roboto", size = 19, weight = 800, extended = true })
surface.CreateFont("GRMSB_Body",  { font = "Roboto", size = 14, weight = 600, extended = true })
surface.CreateFont("GRMSB_Small", { font = "Roboto", size = 12, weight = 500, extended = true })

local COL = {
    bg = Color(12, 16, 24, 252), side = Color(16, 22, 32), card = Color(26, 34, 46),
    sel = Color(40, 88, 124), accent = Color(70, 190, 200), gold = Color(245, 195, 70),
    text = Color(235, 240, 248), dim = Color(140, 155, 175), green = Color(70, 185, 110),
}

--- Расширения, которые движок умеет проигрывать.
SB.Extensions = { wav = true, mp3 = true, ogg = true }

SB.Cache = SB.Cache or nil      -- готовый список путей
SB.Scanning = false

--[[ Обход дерева порциями. Возвращает состояние, которое двигает
     SB.Step: так сканирование не блокирует кадр. ]]
function SB.NewScan()
    return { queue = { "sound/" }, files = {}, dirs = 0, done = false }
end

--[[ Один шаг обхода. budget — сколько папок обработать за вызов.

     Ограничение по папкам, а не по файлам: одна папка может содержать
     тысячу звуков, и проверять бюджет реже нельзя — просядет кадр. ]]
function SB.Step(state, budget)
    if not istable(state) or state.done then return true end
    budget = math.max(1, math.floor(tonumber(budget) or 12))

    for _ = 1, budget do
        local dir = table.remove(state.queue, 1)
        if not dir then state.done = true break end
        state.dirs = state.dirs + 1

        local files, folders = file.Find(dir .. "*", "GAME")
        for _, f in ipairs(files or {}) do
            local ext = string.lower(string.GetExtensionFromFilename(f) or "")
            if SB.Extensions[ext] then
                --[[ Путь храним БЕЗ ведущего «sound/»: движок ждёт
                     именно такой, а с папкой звук молча не находится. ]]
                state.files[#state.files + 1] = (dir .. f):gsub("^sound/", "")
            end
        end
        for _, sub in ipairs(folders or {}) do
            -- Служебные точки в списке папок приводят к бесконечному обходу.
            if sub ~= "." and sub ~= ".." then
                state.queue[#state.queue + 1] = dir .. sub .. "/"
            end
        end
    end

    if #state.queue == 0 then state.done = true end
    return state.done
end

--[[ Отбор по строке поиска. Регистр не важен: человек ищет «выстрел»,
     а файл называется Weapons/AK47. ]]
function SB.Filter(list, query)
    query = string.lower(string.Trim(tostring(query or "")))
    if query == "" then return list end
    local out = {}
    for _, path in ipairs(list or {}) do
        if string.find(string.lower(path), query, 1, true) then out[#out + 1] = path end
    end
    return out
end

--[[ ПРОСЛУШИВАНИЕ С ОСТАНОВКОЙ (жалоба владельца 29.08: «нажимаю на
     звук, он проигрывает, нажимаю на следующий — он запускает
     следующий, но предыдущий не останавливает»).

     Причина: surface.PlaySound выстреливает звук и забывает о нём —
     остановить его нечем. Перебирая список из десятка треков, человек
     получал какофонию из всех сразу.

     CreateSound даёт объект с методом Stop. Держим ссылку на текущий
     трек и снимаем его перед запуском следующего.

     SoundLevel 0 — звук не затухает с расстоянием: иначе длинный трек
     стихал бы, стоит игроку отойти, пока он слушает. ]]
function SB.Play(path)
    path = string.Trim(tostring(path or ""))
    if path == "" then return end
    -- Пути пишут по-разному: движку нужен вариант без ведущей папки.
    path = path:gsub("^sound/", "")

    SB.Stop()

    local lp = LocalPlayer()
    if IsValid(lp) and isfunction(CreateSound) then
        local ok, patch = pcall(CreateSound, lp, path)
        if ok and patch then
            SB._patch = patch
            pcall(function() patch:SetSoundLevel(0) patch:PlayEx(1, 100) end)
            return
        end
    end
    -- Запасной путь: хотя бы проиграть, если CreateSound недоступен.
    surface.PlaySound(path)
end

function SB.Stop()
    if SB._patch then
        pcall(function() SB._patch:Stop() end)
        SB._patch = nil
    end
end

local function mkBtn(parent, text, col)
    local b = vgui.Create("DButton", parent)
    b:SetText("") b:SetCursor("hand")
    b.Paint = function(s, w, h)
        local c = col or COL.card
        if s:IsHovered() then c = Color(math.min(255, c.r + 24), math.min(255, c.g + 24), math.min(255, c.b + 24)) end
        draw.RoundedBox(6, 0, 0, w, h, c)
        draw.SimpleText(text, "GRMSB_Body", w / 2, h / 2, COL.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    return b
end

--[[ Открыть браузер. onPick(path) вызывается при выборе.

     current — текущее значение: подсвечиваем его в списке, чтобы было
     видно, что именно выбрано сейчас. ]]
function SB.Open(onPick, current)
    if IsValid(SB.Frame) then SB.Frame:Remove() end

    local f = vgui.Create("DFrame")
    SB.Frame = f
    if GRM.UI and GRM.UI.Track then GRM.UI.Track("sound_browser", f) end
    f:SetSize(math.Clamp(ScrW() * 0.5, 720, 1000), math.Clamp(ScrH() * 0.66, 520, 800))
    f:Center() f:MakePopup() f:SetTitle("") f:ShowCloseButton(false)

    local state = SB.Cache and { files = SB.Cache, done = true } or SB.NewScan()
    local shown, selected = {}, tostring(current or "")
    local listPanel, info

    f.Paint = function(_, w, h)
        draw.RoundedBox(10, 0, 0, w, h, COL.bg)
        draw.RoundedBoxEx(10, 0, 0, w, 46, COL.side, true, true, false, false)
        draw.SimpleText("ЗВУКИ ИГРЫ И АДДОНОВ", "GRMSB_Title", 16, 23, COL.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        local status = state.done
            and ("найдено: " .. #state.files)
            or ("сканирование... папок: " .. tostring(state.dirs) .. ", звуков: " .. #state.files)
        draw.SimpleText(status, "GRMSB_Small", w - 60, 23, state.done and COL.dim or COL.accent,
            TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    local close = mkBtn(f, "X", Color(210, 75, 75))
    close:SetSize(30, 24)
    close.DoClick = function() f:Close() end
    f.PerformLayout = function(_, w) if IsValid(close) then close:SetPos(w - 40, 11) end end

    local search = vgui.Create("DTextEntry", f)
    search:SetPos(14, 56) search:SetSize(f:GetWide() - 28, 28)
    search:SetPlaceholderText("Поиск: часть пути или имени файла")

    listPanel = vgui.Create("DScrollPanel", f)
    listPanel:SetPos(14, 92)
    listPanel:SetSize(f:GetWide() - 28, f:GetTall() - 92 - 56)

    info = vgui.Create("DLabel", f)
    info:SetPos(14, f:GetTall() - 50) info:SetSize(f:GetWide() - 240, 20)
    info:SetFont("GRMSB_Small") info:SetTextColor(COL.dim)
    info:SetText(selected ~= "" and selected or "Звук не выбран")

    local rebuild

    local function pickRow(path)
        selected = path
        if IsValid(info) then info:SetText(path) end
        rebuild()
    end

    rebuild = function()
        listPanel:Clear()
        local filtered = SB.Filter(state.files, search:GetValue())
        shown = filtered

        --[[ Показываем не больше 300 строк за раз: список из десятков
             тысяч кнопок вешает интерфейс намертво. Остальное
             отсеивается поиском. ]]
        local limit = math.min(#filtered, 300)
        for i = 1, limit do
            local path = filtered[i]
            local row = vgui.Create("DButton", listPanel)
            row:Dock(TOP) row:SetTall(24) row:DockMargin(0, 0, 4, 2) row:SetText("")
            row.Paint = function(s, w, h)
                local isSel = (path == selected)
                draw.RoundedBox(4, 0, 0, w, h, isSel and COL.sel
                    or (s:IsHovered() and Color(34, 46, 62) or Color(20, 28, 40)))
                draw.SimpleText(path, "GRMSB_Small", 8, h / 2, isSel and COL.text or COL.dim,
                    TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            row.DoClick = function()
                pickRow(path)
                --[[ Клик сразу проигрывает: выбирать звук вслепую
                     бессмысленно. Предыдущий трек при этом глушится —
                     иначе при переборе списка играли бы все разом. ]]
                SB.Play(path)
            end
            row.DoDoubleClick = function()
                pickRow(path)
                if isfunction(onPick) then onPick(path) end
                f:Close()
            end
        end

        if #filtered > limit then
            local more = vgui.Create("DLabel", listPanel)
            more:Dock(TOP) more:SetTall(22) more:DockMargin(0, 4, 4, 0)
            more:SetFont("GRMSB_Small") more:SetTextColor(COL.gold)
            more:SetText(("Показано %d из %d — уточните поиск"):format(limit, #filtered))
        end
        if #filtered == 0 and state.done then
            local none = vgui.Create("DLabel", listPanel)
            none:Dock(TOP) none:SetTall(22)
            none:SetFont("GRMSB_Small") none:SetTextColor(COL.dim)
            none:SetText("Ничего не найдено")
        end
    end

    search.OnChange = function() rebuild() end

    --[[ Закрыли окно — звук обязан замолчать. Иначе выбранный трек
         продолжал бы играть поверх игры, и остановить его было бы
         нечем: окна уже нет. ]]
    f.OnClose = function() SB.Stop() end
    f.OnRemove = function() SB.Stop() end

    local stopBtn = mkBtn(f, "■ Стоп", COL.card)
    stopBtn:SetSize(80, 30) stopBtn:SetPos(f:GetWide() - 378, f:GetTall() - 44)
    stopBtn.DoClick = function() SB.Stop() end

    local play = mkBtn(f, "▶ Прослушать", COL.card)
    play:SetSize(130, 30) play:SetPos(f:GetWide() - 292, f:GetTall() - 44)
    play.DoClick = function()
        if selected ~= "" then SB.Play(selected) end
    end

    local apply = mkBtn(f, "Выбрать", COL.green)
    apply:SetSize(140, 30) apply:SetPos(f:GetWide() - 154, f:GetTall() - 44)
    apply.DoClick = function()
        if selected == "" then
            notification.AddLegacy("Сначала выберите звук", NOTIFY_HINT, 3)
            return
        end
        -- Прослушивание глушим: дальше звук нужен в сцене, а не здесь.
        SB.Stop()
        if isfunction(onPick) then onPick(selected) end
        f:Close()
    end

    --[[ Сканирование по кадрам. Бюджет небольшой: лучше показать список
         на секунду позже, чем подвесить игру. ]]
    if not state.done then
        SB.Scanning = true
        f.Think = function()
            if state.done then return end
            local finished = SB.Step(state, 14)
            if finished then
                SB.Cache = state.files
                SB.Scanning = false
                table.sort(state.files)
                rebuild()
            elseif (state.dirs % 60) == 0 then
                -- Периодически показываем найденное, чтобы окно не пустовало.
                rebuild()
            end
        end
    end

    rebuild()
    return f
end

--- Сбросить кэш: пригодится после монтирования нового аддона.
concommand.Add("grm_sound_rescan", function()
    SB.Cache = nil
    print("[GRM] Список звуков сброшен, следующее открытие пересканирует.")
end)
