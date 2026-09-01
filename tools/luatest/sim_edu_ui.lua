-- ======================================================================
-- sim_edu_ui — интерфейс рабочего места учреждения образования и
-- регистрация компьютера деканата в инструментах/реестрах.
--
-- Ловим дефекты, из-за которых кнопку выдачи было НЕ НАЙТИ:
--   1) кнопка «ВЫДАТЬ ДИПЛОМ» существует на вкладке «Выписать диплом»;
--   2) кнопка целиком помещается В ГРАНИЦАХ карточки (раньше её ставили
--      на y=310 при высоте карточки 300 — VGUI обрезал её по краю
--      родителя, и на экране кнопки не было вообще);
--   3) ни один элемент формы не выходит за правый/нижний край карточки;
--   4) grm_comp_education зарегистрирован в инструменте «GRM Служебное
--      оборудование», в PERM_CLASSES и в защите пропов;
--   5) заголовок служебного компьютера переживает рестарт (перм-делегаты).
--
-- Запуск: luajit tools/luatest/sim_edu_ui.lua
-- ======================================================================

local pass, fail = 0, 0
local function ok(cond, msg)
    if cond then pass = pass + 1
    else fail = fail + 1 io.write("  [FAIL] " .. msg .. "\n") end
end

-- ----------------------------------------------------------------------
-- Мок GLua/VGUI: панели помнят родителя, позицию и размер.
-- ----------------------------------------------------------------------
_G.CLIENT, _G.SERVER = true, false
function _G.AddCSLuaFile() end
function _G.include() end
function _G.IsValid(v) return type(v) == "table" and v.__valid ~= false end
function _G.isfunction(v) return type(v) == "function" end
function _G.istable(v) return type(v) == "table" end
function _G.isstring(v) return type(v) == "string" end
_G.math.Clamp = function(v, a, b) if v < a then return a elseif v > b then return b end return v end
_G.string.Trim = function(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
_G.string.Comma = function(v) return tostring(math.floor(tonumber(v) or 0)) end
_G.Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
_G.color_white = _G.Color(255, 255, 255)
_G.CurTime = function() return os.clock() end
_G.LocalPlayer = function() return { __valid = true } end
_G.Derma_StringRequest = function() end
_G.FILL, _G.TOP, _G.LEFT = 1, 2, 3
_G.TEXT_ALIGN_CENTER, _G.TEXT_ALIGN_LEFT, _G.TEXT_ALIGN_RIGHT = 1, 0, 2
_G.NOTIFY_ERROR, _G.NOTIFY_GENERIC = 1, 0
_G.surface = setmetatable({}, { __index = function() return function() end end })
_G.draw = setmetatable({}, { __index = function() return function() end end })
_G.notification = { AddLegacy = function() end }
_G.concommand = { Add = function() end }
_G.RunConsoleCommand = function() end
_G.timer = { Simple = function(_, f) if f then f() end end }
_G.hook = { Add = function() end, Call = function() end, Remove = function() end }
_G.net = setmetatable({}, { __index = function() return function() end end })
_G.util = setmetatable({}, { __index = function() return function() end end })
_G.file = setmetatable({}, { __index = function() return function() end end })
_G.GRM = { Notify = function() end, FormatMoney = function(v) return tostring(v) end }

local allPanels = {}

local Panel = {}
Panel.__index = Panel

local function newPanel(class, parent)
    local p = setmetatable({
        __valid = true, __class = class, __children = {},
        x = 0, y = 0, w = 100, h = 20, __parent = nil,
        __text = "", __visible = true,
    }, Panel)
    allPanels[#allPanels + 1] = p
    if parent and type(parent) == "table" then p:SetParent(parent) end
    return p
end

function Panel:SetParent(pr)
    if self.__parent then
        for i, c in ipairs(self.__parent.__children) do
            if c == self then table.remove(self.__parent.__children, i) break end
        end
    end
    self.__parent = pr
    if pr and pr.__children then pr.__children[#pr.__children + 1] = self end
end
function Panel:GetParent() return self.__parent end
function Panel:GetChildren() return self.__children end
function Panel:SetPos(x, y) self.x, self.y = x, y end
function Panel:GetPos() return self.x, self.y end
function Panel:SetSize(w, h) self.w, self.h = w, h end
function Panel:SetWide(w) self.w = w end
function Panel:SetTall(h) self.h = h end
function Panel:GetWide() return self.w end
function Panel:GetTall() return self.h end
function Panel:SetText(t) self.__text = tostring(t or "") end
function Panel:GetText() return self.__text end
function Panel:SetValue(v) self.__value = v end
function Panel:GetValue() return self.__value or "" end
function Panel:Clear() self.__children = {} end
function Panel:AddItem(p) if p then p:SetParent(self) end end
function Panel:AddChoice(txt, data) self.__choices = self.__choices or {} self.__choices[#self.__choices + 1] = { txt, data } end
function Panel:GetSelected() return "", (self.__choices and self.__choices[1] and self.__choices[1][2]) end
function Panel:GetVBar()
    self.__vbar = self.__vbar or { btnUp = {}, btnDown = {}, btnGrip = {}, SetWide = function() end }
    return self.__vbar
end
-- Всё прочее — молчаливые заглушки. ВАЖНО: служебные поля (__parent и т.п.)
-- обязаны возвращать nil, иначе заглушка подменяет их функцией.
setmetatable(Panel, { __index = function(_, k)
    if type(k) == "string" and k:sub(1, 2) == "__" then return nil end
    return function() end
end })

_G.vgui = { Create = function(class, parent) return newPanel(class, parent) end }

-- ----------------------------------------------------------------------
-- Загружаем клиентскую часть модуля образования
-- ----------------------------------------------------------------------
local src = assert(io.open("lua/autorun/sh_grm_education.lua", "rb"))
local code = src:read("*a") src:close()
assert(loadstring(code, "@sh_grm_education.lua"))()

local EDU = _G.GRM.Education
ok(EDU ~= nil, "GRM.Education должен быть определён")
ok(isfunction(EDU.BuildWorkspace), "EDU.BuildWorkspace должна существовать")

-- Снимок: доступ есть, значит форма выписки обязана строиться
local snap = EDU.Snap
snap.canIssue = true
snap.isSuper = false
snap.isLeader = true
snap.faction = "Университет"
snap.institution = "Государственный университет"
snap.levels = { { id = "bachelor", name = "Бакалавр" } }
snap.forms  = { { id = "full", name = "Очная" } }
snap.characters = { { key = "76561198000000001:char1", name = "Иван Петров", faction = "Гражданские", online = false } }
snap.diplomas = {}
snap.stats = { total = 0, valid = 0, revoked = 0 }

local root = newPanel("DPanel")
root:SetSize(900, 620)
local rebuild = EDU.BuildWorkspace(root)
ok(isfunction(rebuild), "BuildWorkspace возвращает функцию перерисовки")

-- ----------------------------------------------------------------------
-- Ищем кнопку выдачи по всему дереву
-- ----------------------------------------------------------------------
local function findButton(label)
    for _, p in ipairs(allPanels) do
        if p.__class == "DButton" and p.__btnLabel == label then return p end
    end
    return nil
end

-- Кнопки рисуют текст внутри Paint, поэтому метим их через перехват:
-- ищем кнопку как DButton, у которого DoClick назначен и который лежит
-- в той же карточке, что и поле «Специальность». Проще: ищем DButton,
-- чей размер 220x32 (кнопка выдачи) — но надёжнее пройтись по карточке.
local issueBtn
for _, p in ipairs(allPanels) do
    if p.__class == "DButton" and p.h == 32 and p.DoClick then
        issueBtn = p
    end
end
ok(issueBtn ~= nil, "кнопка «ВЫДАТЬ ДИПЛОМ» должна быть создана")

if issueBtn then
    local card = issueBtn:GetParent()
    ok(card ~= nil, "кнопка выдачи должна лежать в карточке формы")
    if card then
        -- Dock в моке не считается, поэтому ширину карточки задаём сами:
        -- так её растянул бы DScrollPanel внутри окна 900px.
        card:SetWide(860)
        -- Прогоняем раскладку так, как это делает VGUI
        if isfunction(card.PerformLayout) then card:PerformLayout(card:GetWide()) end

        local bx, by = issueBtn:GetPos()
        local bw, bh = issueBtn:GetWide(), issueBtn:GetTall()

        -- ГЛАВНАЯ ПРОВЕРКА: кнопка целиком внутри карточки.
        ok(by + bh <= card:GetTall(),
            ("кнопка выдачи обрезается снизу: низ кнопки %d > высота карточки %d")
                :format(by + bh, card:GetTall()))
        ok(bx >= 0 and bx + bw <= card:GetWide(),
            ("кнопка выдачи выходит за правый край: %d > %d"):format(bx + bw, card:GetWide()))
        ok(bh > 0 and bw > 0, "кнопка выдачи должна иметь ненулевой размер")

        -- Ни один элемент формы не должен вылезать за карточку
        local overflow = {}
        for _, ch in ipairs(card:GetChildren()) do
            local cx, cy = ch:GetPos()
            if cx + ch:GetWide() > card:GetWide() + 1 or cy + ch:GetTall() > card:GetTall() + 1 then
                overflow[#overflow + 1] = ch.__class
            end
        end
        ok(#overflow == 0, "элементы формы вылезают за карточку: " .. table.concat(overflow, ", "))
    end
end

-- Форма при узком окне тоже не должна ломаться
if issueBtn then
    local card = issueBtn:GetParent()
    if card then
        for _, width in ipairs({ 520, 700, 900, 1200 }) do
            card:SetWide(width)
            card:PerformLayout(width)
            local bx, by = issueBtn:GetPos()
            ok(by + issueBtn:GetTall() <= card:GetTall(),
                ("при ширине %d кнопка выдачи уходит за низ карточки"):format(width))
            ok(bx + issueBtn:GetWide() <= width,
                ("при ширине %d кнопка выдачи уходит за правый край"):format(width))
        end
    end
end

-- Без доступа форма выписки не строится, но и не падает
snap.canIssue, snap.isSuper = false, false
local root2 = newPanel("DPanel") root2:SetSize(900, 620)
local okBuild = pcall(EDU.BuildWorkspace, root2)
ok(okBuild, "BuildWorkspace не должна падать без доступа")

-- ----------------------------------------------------------------------
-- Регистрация компьютера деканата
-- ----------------------------------------------------------------------
local function readFile(p)
    local f = io.open(p, "rb")
    if not f then return "" end
    local s = f:read("*a") f:close() return s
end

local tool = readFile("lua/weapons/gmod_tool/stools/grm_service_tool.lua")
ok(tool:find('class%s*=%s*"grm_comp_education"'),
    "grm_comp_education должен быть в списке типов инструмента GRM Служебное оборудование")
ok(tool:find("education%s*=%s*{"), "у типа education должен быть ключ в таблице TYPES")

local perm = readFile("lua/autorun/sh_grm_perm_entities.lua")
ok(perm:find("grm_comp_education%s*=%s*true"),
    "grm_comp_education должен быть в PERM_CLASSES (иначе не сохранится на карту)")
ok(perm:find("GetComputerName"),
    "перм должен сохранять заголовок служебного компьютера")

local prot = readFile("lua/autorun/sh_grm_prop_protect.lua")
ok(prot:find("grm_comp_education%s*=%s*true"),
    "grm_comp_education должен быть под защитой пропов")

-- Сущность на месте и открывает рабочее место
local entInit = readFile("lua/entities/grm_comp_education/init.lua")
ok(entInit:find("GRM%.Education%.Open"), "ENT:Use должен открывать рабочее место")
ok(entInit:find("PoweredOn"), "компьютер должен уважать электропитание")

--[[ Табличка станции рисуется общей базой grm_comp_base, а подписи
     станция задаёт данными; динамический заголовок школы («ГИМНАЗИЯ №1»)
     живёт в CompLabels её shared.lua. Раньше проверка искала
     GetComputerName в cl_init.lua — после сведения одиннадцати копий
     Draw в базу это стало проверкой места, а не поведения (§10.1.4).
     Поведение CompLabels проверяет sim_comp_base.lua. ]]
local entShared = readFile("lua/entities/grm_comp_education/shared.lua")
ok(entShared:find("grm_comp_base", 1, true) ~= nil,
    "станция образования наследует общую базу компьютеров")
ok(entShared:find("function ENT:CompLabels") and entShared:find("GetComputerName"),
    "табличка должна показывать заданный инструментом заголовок")

-- Банкомат выписку больше не ведёт
local atm = readFile("lua/autorun/sh_grm_atm.lua")
ok(not atm:find('act%("issue_diploma"'), "в банкомате не должно остаться вызова выписки диплома")

-- ----------------------------------------------------------------------
-- «Мои дипломы»: личный просмотр документа игроком
-- ----------------------------------------------------------------------
ok(isfunction(EDU.OpenMine), "EDU.OpenMine должна открывать окно «Мои дипломы»")
ok(isfunction(EDU.AskMine), "EDU.AskMine должна запрашивать дипломы у сервера")

-- Окно с одним действующим и одним аннулированным бланком
local mine = {
    {
        number = "ГД-2026-000123", institution = "Государственный университет",
        graduateName = "Иван Петров", specialty = "Юриспруденция",
        qualification = "Юрист", level = "bachelor", levelName = "Бакалавр",
        form = "full", formName = "Очная", grade = "отлично", paid = true,
        issued = 1770000000, issuerName = "Декан", signedBy = "Декан",
        note = "", revoked = false, revokeReason = "",
    },
    {
        number = "ГД-2025-000007", institution = "Колледж",
        graduateName = "Иван Петров", specialty = "Слесарь",
        qualification = "", level = "vocational", levelName = "Среднее спец.",
        form = "part", formName = "Заочная", grade = "", paid = false,
        issued = 1740000000, issuerName = "Директор", signedBy = "",
        note = "", revoked = true, revokeReason = "подделка",
    },
}

local before = #allPanels
local frame = EDU.OpenMine(mine)
ok(frame ~= nil, "окно «Мои дипломы» должно создаваться")

-- Бланки: ищем панели, появившиеся после открытия окна, с раскладкой
local blanks = {}
for i = before + 1, #allPanels do
    local p = allPanels[i]
    if p.__class == "DPanel" and isfunction(p.PerformLayout) and #p:GetChildren() >= 10 then
        blanks[#blanks + 1] = p
    end
end
ok(#blanks == 2, ("должно быть 2 бланка, найдено %d"):format(#blanks))

-- Содержимое бланка не должно вылезать за его границы
for bi, b in ipairs(blanks) do
    b:SetWide(600)
    b:PerformLayout(600)
    local bad = 0
    for _, ch in ipairs(b:GetChildren()) do
        local cx, cy = ch:GetPos()
        if cx + ch:GetWide() > 600 + 1 or cy + ch:GetTall() > b:GetTall() + 1 then bad = bad + 1 end
    end
    ok(bad == 0, ("бланк %d: %d полей выходят за границы"):format(bi, bad))
    ok(b:GetTall() > 50, ("бланк %d должен иметь осмысленную высоту"):format(bi))
end

-- Номер бланка обязан быть на виду
local seenNumber = false
for i = before + 1, #allPanels do
    if allPanels[i]:GetText() == "ГД-2026-000123" then seenNumber = true break end
end
ok(seenNumber, "номер бланка должен отображаться в окне")

-- Аннулированный бланк показывает причину
local seenReason = false
for i = before + 1, #allPanels do
    if allPanels[i]:GetText() == "подделка" then seenReason = true break end
end
ok(seenReason, "причина аннулирования должна отображаться")

-- Пустой список не должен падать
ok(pcall(EDU.OpenMine, {}), "окно без дипломов не должно падать")
ok(pcall(EDU.OpenMine), "окно без аргумента не должно падать")

-- Кнопка в C-меню
local ctx = readFile("lua/autorun/sh_grm_ctx.lua")
ok(ctx:find("doc_self_diploma"), "в C-меню должна быть кнопка личного просмотра диплома")
ok(ctx:find("diplomaCount"), "сервер должен сообщать C-меню число дипломов")
ok(ctx:find("GRM%.Education%.AskMine") or ctx:find("AskMine"),
    "кнопка C-меню должна вызывать EDU.AskMine")

-- Кнопка показывается только владельцу диплома и только без прицела на игрока
local edu = readFile("lua/autorun/sh_grm_education.lua")
ok(edu:find("GRM_Edu_MyAsk") and edu:find("GRM_Edu_MyData"),
    "должны быть сетевые строки личного просмотра")
ok(edu:find("D%.For%(ply, true%)"),
    "личный список должен включать аннулированные бланки")
ok(edu:find("concommand%.Add%(\"grm_mydiplomas\""),
    "должна быть консольная команда grm_mydiplomas")

io.write(("\nsim_edu_ui: %d/%d failures=%d\n"):format(pass, pass + fail, fail))
os.exit(fail == 0 and 0 or 1)
