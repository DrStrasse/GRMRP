--[[
    GRM News System
    Система новостей с возможностью публикации
]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.News = GRM.News or {}
local NEWS = GRM.News

-- Конфигурация
NEWS.Config = {
    MaxArticles = 100, -- Максимум статей в базе
    MaxTitleLength = 100,
    MaxContentLength = 5000,
    MaxAuthorLength = 50,
}

-- Хранилище новостей
NEWS.Articles = NEWS.Articles or {}
NEWS.Config_ = NEWS.Config_ or {}

-- Загрузка данных
function NEWS.LoadData()
    if not SERVER then return end

    if not file.Exists("grm_news", "DATA") then
        file.CreateDir("grm_news")
    end

    -- Загрузка статей
    if file.Exists("grm_news/articles.txt", "DATA") then
        local data = file.Read("grm_news/articles.txt", "DATA")
        if data then
            local articles = util.JSONToTable(data)
            if articles then
                NEWS.Articles = articles
            end
        end
    end

    -- Загрузка конфигурации
    if file.Exists("grm_news/config.txt", "DATA") then
        local data = file.Read("grm_news/config.txt", "DATA")
        if data then
            local config = util.JSONToTable(data)
            if config then
                NEWS.Config_ = config
            end
        end
    end
end

-- Сохранение данных
function NEWS.SaveData()
    if not SERVER then return end

    file.Write("grm_news/articles.txt", util.TableToJSON(NEWS.Articles, true))
    file.Write("grm_news/config.txt", util.TableToJSON(NEWS.Config_, true))
end

-- Создание статьи
function NEWS.CreateArticle(author, title, content, category)
    if not author or not title or not content then
        return false, "Недостаточно данных"
    end

    if #NEWS.Articles >= NEWS.Config.MaxArticles then
        return false, "Достигнут максимум статей"
    end

    if #title > NEWS.Config.MaxTitleLength then
        return false, "Заголовок слишком длинный"
    end

    if #content > NEWS.Config.MaxContentLength then
        return false, "Содержимое слишком длинное"
    end

    local article = {
        id = (function() local m=0 for _,a in ipairs(NEWS.Articles) do m=math.max(m,tonumber(a.id) or 0) end return m+1 end)(),
        author = author,
        title = title,
        content = content,
        category = category or "Общее",
        created = os.time(),
        views = 0
    }

    table.insert(NEWS.Articles, article)
    NEWS.SaveData()

    return true, article
end

-- Удаление статьи
function NEWS.DeleteArticle(articleId)
    for i, article in ipairs(NEWS.Articles) do
        if article.id == articleId then
            table.remove(NEWS.Articles, i)
            NEWS.SaveData()
            return true
        end
    end
    return false
end

-- Получение всех статей
function NEWS.UpdateArticle(articleId, title, content, category, editor)
    if #tostring(title or "") == 0 or #tostring(content or "") == 0 then return false, "Пустой заголовок или текст" end
    for _, a in ipairs(NEWS.Articles) do
        if a.id == articleId then
            a.title = string.sub(tostring(title), 1, NEWS.Config.MaxTitleLength)
            a.content = string.sub(tostring(content), 1, NEWS.Config.MaxContentLength)
            a.category = string.sub(tostring(category or a.category), 1, 32)
            a.edited = os.time(); a.editedBy = editor or "Администратор"
            NEWS.SaveData(); return true, a
        end
    end
    return false, "Статья не найдена"
end

function NEWS.GetAllArticles()
    return NEWS.Articles
end

-- Получение статьи по ID
function NEWS.GetArticle(articleId)
    for _, article in ipairs(NEWS.Articles) do
        if article.id == articleId then
            article.views = (article.views or 0) + 1
            NEWS.SaveData()
            return article
        end
    end
    return nil
end

-- СЕРВЕР
if SERVER then
    util.AddNetworkString("GRM_News_GetAll")
    util.AddNetworkString("GRM_News_SendAll")
    util.AddNetworkString("GRM_News_GetArticle")
    util.AddNetworkString("GRM_News_SendArticle")
    util.AddNetworkString("GRM_News_Create")
    util.AddNetworkString("GRM_News_Delete")
    util.AddNetworkString("GRM_News_Update")
    util.AddNetworkString("GRM_News_Result")

    NEWS.LoadData()

    -- Получение всех статей
    net.Receive("GRM_News_GetAll", function(len, ply)
        net.Start("GRM_News_SendAll")
        net.WriteTable(NEWS.Articles)
        net.Send(ply)
    end)

    -- Получение одной статьи
    net.Receive("GRM_News_GetArticle", function(len, ply)
        local articleId = net.ReadUInt(16)
        local article = NEWS.GetArticle(articleId)

        net.Start("GRM_News_SendArticle")
        net.WriteTable(article or {})
        net.Send(ply)
    end)

    -- Создание статьи
    net.Receive("GRM_News_Create", function(len, ply)
        local title = net.ReadString()
        local content = net.ReadString()
        local category = net.ReadString()

        -- Проверка прав (только админы или журналисты)
        if not ply:IsAdmin() and not (GRM.Factions and GRM.Factions.HasRole and GRM.Factions.HasRole(ply, "journalist")) then
            net.Start("GRM_News_Result")
            net.WriteBool(false)
            net.WriteString("У вас нет прав для публикации статей")
            net.Send(ply)
            return
        end

        local author = ply:Nick()
        local success, result = NEWS.CreateArticle(author, title, content, category)

        net.Start("GRM_News_Result")
        net.WriteBool(success)
        net.WriteString(success and "Статья опубликована!" or result)
        net.Send(ply)
    end)

    net.Receive("GRM_News_Update", function(_, ply)
        if not ply:IsAdmin() then net.Start("GRM_News_Result"); net.WriteBool(false); net.WriteString("Нет прав"); net.Send(ply); return end
        local id,title,content,category=net.ReadUInt(16),net.ReadString(),net.ReadString(),net.ReadString()
        local ok,msg=NEWS.UpdateArticle(id,title,content,category,ply:Nick())
        net.Start("GRM_News_Result"); net.WriteBool(ok); net.WriteString(ok and "Статья обновлена" or msg); net.Send(ply)
    end)

    -- Удаление статьи
    net.Receive("GRM_News_Delete", function(len, ply)
        local articleId = net.ReadUInt(16)

        -- Проверка прав (только админы)
        if not ply:IsAdmin() then
            net.Start("GRM_News_Result")
            net.WriteBool(false)
            net.WriteString("У вас нет прав для удаления статей")
            net.Send(ply)
            return
        end

        local success = NEWS.DeleteArticle(articleId)

        net.Start("GRM_News_Result")
        net.WriteBool(success)
        net.WriteString(success and "Статья удалена!" or "Статья не найдена")
        net.Send(ply)
    end)

    print("[GRM News] Server loaded")
end

-- КЛИЕНТ
if CLIENT then
    -- GRM UI Style
    local GRM_COLORS = {
        bg = Color(15, 20, 30, 250),
        panel = Color(25, 35, 50, 240),
        panel2 = Color(20, 28, 40, 235),
        accent = Color(0, 150, 255),
        accent_hover = Color(50, 180, 255),
        text = Color(220, 230, 240),
        text_dim = Color(140, 150, 170),
        success = Color(50, 200, 100),
        warning = Color(255, 180, 50),
        error = Color(255, 80, 80),
        border = Color(60, 80, 110, 150),
        head = Color(18, 22, 30, 255)
    }

    -- GRM Fonts
    surface.CreateFont("GRMNews_Title", { font = "Roboto", size = 20, weight = 800, extended = true })
    surface.CreateFont("GRMNews_Sub", { font = "Roboto", size = 15, weight = 600, extended = true })
    surface.CreateFont("GRMNews_Normal", { font = "Roboto", size = 13, weight = 500, extended = true })
    surface.CreateFont("GRMNews_Small", { font = "Roboto", size = 12, weight = 500, extended = true })
    surface.CreateFont("GRMNews_Bold", { font = "Roboto", size = 13, weight = 700, extended = true })
    surface.CreateFont("GRMNews_Article", { font = "Roboto", size = 14, weight = 500, extended = true })

    -- Открытие новостного портала
    function NEWS.OpenPortal()
        net.Start("GRM_News_GetAll")
        net.SendToServer()
    end

    -- Получение всех статей
    net.Receive("GRM_News_SendAll", function()
        local articles = net.ReadTable()

        -- Создание окна
        local frame = vgui.Create("DFrame")
        frame:SetTitle("GRM News")
        frame:SetSize(900, 650)
        frame:Center()
        frame:MakePopup()

        frame.Paint = function(self, w, h)
            draw.RoundedBox(8, 0, 0, w, h, GRM_COLORS.bg)
            draw.RoundedBoxEx(8, 0, 0, w, 46, GRM_COLORS.head, true, true, false, false)
            surface.SetDrawColor(GRM_COLORS.border)
            surface.DrawLine(0, 46, w, 46)

            draw.SimpleText("GRM NEWS", "GRMNews_Title", 14, 23, GRM_COLORS.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText("Новостной портал", "GRMNews_Normal", w - 20, 23, GRM_COLORS.text_dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end

        -- Левая панель - список статей
        local leftPanel = vgui.Create("DPanel", frame)
        leftPanel:SetPos(10, 56)
        leftPanel:SetSize(350, 584)
        leftPanel.Paint = function(self, w, h)
            draw.RoundedBox(6, 0, 0, w, h, GRM_COLORS.panel)
            surface.SetDrawColor(GRM_COLORS.border)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
        end

        local listTitle = vgui.Create("DLabel", leftPanel)
        listTitle:SetPos(10, 10)
        listTitle:SetSize(330, 30)
        listTitle:SetText("Последние новости")
        listTitle:SetFont("GRMNews_Sub")
        listTitle:SetTextColor(GRM_COLORS.text)

        -- Список статей
        local articleList = vgui.Create("DListView", leftPanel)
        articleList:SetPos(10, 45)
        articleList:SetSize(330, 480)
        articleList:SetMultiSelect(false)
        articleList:AddColumn("Заголовок"):SetFixedWidth(220)
        articleList:AddColumn("Автор"):SetFixedWidth(100)

        articleList.Paint = function(self, w, h)
            draw.RoundedBox(4, 0, 0, w, h, GRM_COLORS.panel2)
        end

        for _, col in ipairs(articleList.Columns or {}) do
            col.Header:SetFont("GRMNews_Bold")
            col.Header:SetTextColor(GRM_COLORS.text_dim)
        end

        -- Сортировка по дате (новые первые)
        local sortedArticles = table.Copy(articles)
        table.sort(sortedArticles, function(a, b) return a.created > b.created end)

        for _, article in ipairs(sortedArticles) do
            local line = articleList:AddLine(article.title, article.author)
            line.articleData = article

            line.Columns[1]:SetTextColor(GRM_COLORS.text)
            line.Columns[2]:SetTextColor(GRM_COLORS.text_dim)
        end

        -- Кнопка создания статьи
        local btnCreate = vgui.Create("DButton", leftPanel)
        btnCreate:SetPos(10, 535)
        btnCreate:SetSize(330, 40)
        btnCreate:SetText("СОЗДАТЬ СТАТЬЮ")
        btnCreate:SetFont("GRMNews_Bold")
        btnCreate:SetTextColor(GRM_COLORS.text)
        btnCreate.Paint = function(self, w, h)
            local col = self:IsHovered() and GRM_COLORS.accent_hover or GRM_COLORS.accent
            draw.RoundedBox(6, 0, 0, w, h, col)
        end
        btnCreate.DoClick = function()
            NEWS.OpenCreateArticle()
        end

        -- Правая панель - содержимое статьи
        local rightPanel = vgui.Create("DPanel", frame)
        rightPanel:SetPos(370, 56)
        rightPanel:SetSize(520, 584)
        rightPanel.Paint = function(self, w, h)
            draw.RoundedBox(6, 0, 0, w, h, GRM_COLORS.panel)
            surface.SetDrawColor(GRM_COLORS.border)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
        end

        local articleTitle = vgui.Create("DLabel", rightPanel)
        articleTitle:SetPos(20, 20)
        articleTitle:SetSize(480, 40)
        articleTitle:SetText("Выберите статью для просмотра")
        articleTitle:SetFont("GRMNews_Sub")
        articleTitle:SetTextColor(GRM_COLORS.text)

        local articleMeta = vgui.Create("DLabel", rightPanel)
        articleMeta:SetPos(20, 65)
        articleMeta:SetSize(480, 20)
        articleMeta:SetText("")
        articleMeta:SetFont("GRMNews_Small")
        articleMeta:SetTextColor(GRM_COLORS.text_dim)

        local selectedArticle
        local articleContent = vgui.Create("DTextEntry", rightPanel)
        articleContent:SetPos(20, 95)
        articleContent:SetSize(480, 420)
        articleContent:SetMultiline(true)
        articleContent:SetEditable(false)
        articleContent:SetFont("GRMNews_Article")
        articleContent:SetText("")
        local editButton=vgui.Create("DButton",rightPanel); editButton:SetPos(20,530); editButton:SetSize(150,34); editButton:SetText("РЕДАКТИРОВАТЬ")
        local deleteButton=vgui.Create("DButton",rightPanel); deleteButton:SetPos(185,530); deleteButton:SetSize(150,34); deleteButton:SetText("УДАЛИТЬ")
        editButton:SetEnabled(false); deleteButton:SetEnabled(false)
        editButton.DoClick=function() if not selectedArticle then return end; articleContent:SetEditable(true); articleContent:RequestFocus(); editButton:SetText("СОХРАНИТЬ") end
        editButton.DoClick=function()
            if not selectedArticle then return end
            if articleContent:IsEditable() then
                net.Start("GRM_News_Update"); net.WriteUInt(selectedArticle.id,16); net.WriteString(selectedArticle.title); net.WriteString(articleContent:GetText()); net.WriteString(selectedArticle.category or "Общее"); net.SendToServer(); articleContent:SetEditable(false); editButton:SetText("РЕДАКТИРОВАТЬ")
            else articleContent:SetEditable(true); articleContent:RequestFocus(); editButton:SetText("СОХРАНИТЬ") end
        end
        deleteButton.DoClick=function() if not selectedArticle then return end; Derma_Query("Удалить статью «"..selectedArticle.title.."»?","GRM News","Удалить",function() net.Start("GRM_News_Delete"); net.WriteUInt(selectedArticle.id,16); net.SendToServer() end,"Отмена") end
        articleList.OnRowSelected = function(lst, rowIndex, line)
            local article = line.articleData
            selectedArticle=article; editButton:SetEnabled(true); deleteButton:SetEnabled(true); articleContent:SetEditable(false); editButton:SetText("РЕДАКТИРОВАТЬ")

            articleTitle:SetText(article.title)
            articleMeta:SetText("Автор: " .. article.author .. " | Категория: " .. article.category .. " | Просмотров: " .. article.views .. " | " .. os.date("%d.%m.%Y %H:%M", article.created))
            articleContent:SetText(article.content)
        end

        -- Автоматический выбор первой статьи
        if #sortedArticles > 0 then
            articleList:SelectItem(articleList:GetLine(1))
        end
    end)

    -- Открытие окна создания статьи
    function NEWS.OpenCreateArticle()
        local frame = vgui.Create("DFrame")
        frame:SetTitle("Создать статью")
        frame:SetSize(700, 600)
        frame:Center()
        frame:MakePopup()

        frame.Paint = function(self, w, h)
            draw.RoundedBox(8, 0, 0, w, h, GRM_COLORS.bg)
            draw.RoundedBoxEx(8, 0, 0, w, 46, GRM_COLORS.head, true, true, false, false)
            surface.SetDrawColor(GRM_COLORS.border)
            surface.DrawLine(0, 46, w, 46)

            draw.SimpleText("СОЗДАНИЕ СТАТЬИ", "GRMNews_Title", 14, 23, GRM_COLORS.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end

        local yPos = 60

        -- Заголовок
        local titleLabel = vgui.Create("DLabel", frame)
        titleLabel:SetPos(20, yPos)
        titleLabel:SetSize(660, 30)
        titleLabel:SetText("Заголовок:")
        titleLabel:SetFont("GRMNews_Bold")
        titleLabel:SetTextColor(GRM_COLORS.text)
        yPos = yPos + 30

        local titleEntry = vgui.Create("DTextEntry", frame)
        titleEntry:SetPos(20, yPos)
        titleEntry:SetSize(660, 30)
        titleEntry:SetFont("GRMNews_Normal")
        titleEntry:SetPlaceholderText("Введите заголовок статьи...")
        yPos = yPos + 40

        -- Категория
        local catLabel = vgui.Create("DLabel", frame)
        catLabel:SetPos(20, yPos)
        catLabel:SetSize(660, 30)
        catLabel:SetText("Категория:")
        catLabel:SetFont("GRMNews_Bold")
        catLabel:SetTextColor(GRM_COLORS.text)
        yPos = yPos + 30

        local catCombo = vgui.Create("DComboBox", frame)
        catCombo:SetPos(20, yPos)
        catCombo:SetSize(660, 30)
        catCombo:SetFont("GRMNews_Normal")
        catCombo:AddChoice("Общее", "Общее")
        catCombo:AddChoice("Политика", "Политика")
        catCombo:AddChoice("Экономика", "Экономика")
        catCombo:AddChoice("Происшествия", "Происшествия")
        catCombo:AddChoice("Спорт", "Спорт")
        catCombo:ChooseOptionID(1)
        yPos = yPos + 40

        -- Содержимое
        local contentLabel = vgui.Create("DLabel", frame)
        contentLabel:SetPos(20, yPos)
        contentLabel:SetSize(660, 30)
        contentLabel:SetText("Содержимое:")
        contentLabel:SetFont("GRMNews_Bold")
        contentLabel:SetTextColor(GRM_COLORS.text)
        yPos = yPos + 30

        local contentEntry = vgui.Create("DTextEntry", frame)
        contentEntry:SetPos(20, yPos)
        contentEntry:SetSize(660, 350)
        contentEntry:SetMultiline(true)
        contentEntry:SetFont("GRMNews_Article")
        contentEntry:SetPlaceholderText("Введите содержимое статьи...")
        yPos = yPos + 360

        -- Кнопка публикации
        local btnPublish = vgui.Create("DButton", frame)
        btnPublish:SetPos(20, yPos)
        btnPublish:SetSize(660, 50)
        btnPublish:SetText("ОПУБЛИКОВАТЬ")
        btnPublish:SetFont("GRMNews_Bold")
        btnPublish:SetTextColor(GRM_COLORS.text)
        btnPublish.Paint = function(self, w, h)
            local col = self:IsHovered() and GRM_COLORS.success or Color(40, 160, 80)
            draw.RoundedBox(6, 0, 0, w, h, col)
        end
        btnPublish.DoClick = function()
            local title = titleEntry:GetValue()
            local content = contentEntry:GetValue()
            local _, category = catCombo:GetSelected()

            if not title or title == "" then
                notification.AddLegacy("Введите заголовок!", NOTIFY_ERROR, 3)
                return
            end

            if not content or content == "" then
                notification.AddLegacy("Введите содержимое!", NOTIFY_ERROR, 3)
                return
            end

            net.Start("GRM_News_Create")
            net.WriteString(title)
            net.WriteString(content)
            net.WriteString(category or "Общее")
            net.SendToServer()

            frame:Close()
        end
    end

    -- Обработка результата
    net.Receive("GRM_News_Result", function()
        local success = net.ReadBool()
        local message = net.ReadString()

        notification.AddLegacy(message, success and NOTIFY_GENERIC or NOTIFY_ERROR, 5)

        if success then
            -- Обновить портал
            timer.Simple(0.5, function()
                NEWS.OpenPortal()
            end)
        end
    end)

    -- Консольная команда
    concommand.Add("grm_news", NEWS.OpenPortal)

    print("[GRM News] Client loaded")
end
