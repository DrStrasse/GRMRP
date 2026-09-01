--[[ Живой прогон безопасной очистки панелей (заказ владельца 27.08):
     «Какой-то модуль сбоит связанный с pcboard» —
     lua/vgui/dframe.lua:246: Tried to use a NULL Panel! (SetPos).

     Причина: Panel:Clear() на DFrame сносит служебные кнопки окна
     (btnClose/btnMaxim/btnMinim/lblTitle), а PerformLayout самого DFrame
     продолжает звать у них SetPos каждый кадр.

     Здесь проверяется настоящая GRM.UI.SafeClear из ядра UI и то, что
     все перестраиваемые окна перешли на неё.
     Запуск: luajit tools/luatest/sim_ui_safeclear.lua ]]
local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

SERVER, CLIENT = false, false
function AddCSLuaFile() end
function istable(v) return type(v) == "table" end
function isfunction(v) return type(v) == "function" end
hook = { Add = function() end, Run = function() end }
GRM = {}

--- Мини-макет VGUI: панель с детьми, как в игре.
local Panel = {}
Panel.__index = Panel
local function newPanel(name)
    return setmetatable({ _name = name, _valid = true, _children = {} }, Panel)
end
function Panel:Add(child) self._children[#self._children + 1] = child child._parent = self return child end
--- В движке GetChildren() отдаёт КОПИЮ списка, поэтому удаление ребёнка
--- во время обхода безопасно. Макет обязан вести себя так же.
function Panel:GetChildren()
    local copy = {}
    for i, ch in ipairs(self._children) do copy[i] = ch end
    return copy
end
function Panel:Remove()
    self._valid = false
    if self._parent then
        for i, ch in ipairs(self._parent._children) do
            if ch == self then table.remove(self._parent._children, i) break end
        end
    end
end
function Panel:Clear()
    -- Ровно как движок: сносит ВСЕХ детей, включая служебные кнопки.
    for _, ch in ipairs(self:GetChildren()) do ch._valid = false end
    self._children = {}
end
--- Имитация DFrame:PerformLayout (dframe.lua:246) — то, что и падало.
function Panel:PerformLayout()
    for _, key in ipairs({ "btnClose", "btnMaxim", "btnMinim", "lblTitle" }) do
        local b = self[key]
        if b ~= nil then
            if b._valid == false then error("Tried to use a NULL Panel!", 0) end
        end
    end
    return true
end

function IsValid(v) return istable(v) and v._valid ~= false end

assert(loadfile("lua/autorun/sh_00_grm_ui.lua"))()

local function newFrame()
    local f = newPanel("DFrame")
    f.btnClose = f:Add(newPanel("btnClose"))
    f.btnMaxim = f:Add(newPanel("btnMaxim"))
    f.btnMinim = f:Add(newPanel("btnMinim"))
    f.lblTitle = f:Add(newPanel("lblTitle"))
    return f
end

print("\n=== 1. ВОСПРОИЗВОДИМ САМУ ОШИБКУ ===")
local broken = newFrame()
broken:Add(newPanel("content"))
broken:Clear()
local okCall, err = pcall(function() return broken:PerformLayout() end)
ok(okCall == false and tostring(err):find("NULL Panel", 1, true) ~= nil,
   "обычный :Clear() на DFrame ломает раскладку окна — та самая dframe.lua:246", tostring(err))

print("\n=== 2. SafeClear ЧИНИТ ПРИЧИНУ ===")
ok(isfunction(GRM.UI.SafeClear), "GRM.UI.SafeClear объявлен в ядре UI")
local frame = newFrame()
frame:Add(newPanel("content1"))
frame:Add(newPanel("content2"))
GRM.UI.SafeClear(frame)
ok(frame:PerformLayout() == true, "после SafeClear раскладка окна больше не падает")
ok(IsValid(frame.btnClose) and IsValid(frame.btnMaxim)
   and IsValid(frame.btnMinim) and IsValid(frame.lblTitle),
   "кнопки закрытия/сворачивания и заголовок остаются живыми")
local left = 0
for _, ch in ipairs(frame:GetChildren()) do
    if ch._name == "content1" or ch._name == "content2" then left = left + 1 end
end
ok(left == 0, "содержимое при этом действительно очищено", left)
ok(#frame:GetChildren() == 4, "в окне остаётся ровно служебная обвязка", #frame:GetChildren())

print("\n=== 3. ОБЫЧНЫЕ ПАНЕЛИ РАБОТАЮТ КАК РАНЬШЕ ===")
local plain = newPanel("DPanel")
plain:Add(newPanel("row1"))
plain:Add(newPanel("row2"))
GRM.UI.SafeClear(plain)
ok(#plain:GetChildren() == 0, "у панели без обвязки SafeClear чистит всё", #plain:GetChildren())
ok(GRM.UI.SafeClear(nil) == false, "мёртвая панель не роняет вызов")
local removed = newPanel("gone") removed._valid = false
ok(GRM.UI.SafeClear(removed) == false, "уже удалённая панель просто игнорируется")

print("\n=== 4. ПОВТОРНАЯ ПЕРЕСБОРКА (окно перестраивают много раз) ===")
local repeated = newFrame()
for i = 1, 25 do
    repeated:Add(newPanel("body" .. i))
    GRM.UI.SafeClear(repeated)
    if not repeated:PerformLayout() then break end
end
ok(repeated:PerformLayout() == true, "25 пересборок подряд — ни одной NULL Panel")
ok(IsValid(repeated.btnClose), "обвязка пережила все пересборки")

print("\n=== 5. ВСЕ ОКНА ПЕРЕВЕДЕНЫ НА SafeClear ===")
local function body(path)
    local fh = io.open(path, "rb")
    if not fh then return "" end
    local t = fh:read("*a") fh:close() return t
end
local files = {
    ["планшет госбазы (/pcboard)"] = "lua/autorun/client/cl_grm_pcboard_ui.lua",
    ["экономика (вкладка в /factions)"] = "lua/autorun/sh_grm_economy.lua",
    ["доступы организаций"] = "lua/autorun/client/cl_grm_faction_perms_ui.lua",
    ["модели и оружие узлов"] = "lua/autorun/client/cl_grm_faction_loadout_admin.lua",
    ["диалоги квестов"] = "lua/autorun/client/cl_grm_quests.lua",
    ["багажник"] = "lua/autorun/sh_grm_trunk.lua",
}
for label, path in pairs(files) do
    local src = body(path)
    ok(src:find("GRM.UI.SafeClear", 1, true) ~= nil, label .. " использует SafeClear", path)
end

--- Голых Clear() на переменных-окнах остаться не должно.
local leftovers = {}
--[[ Ищем только ЖИВОЙ код: строки внутри пояснений (и обычных «--», и
     блочных комментариев с отступом) к делу не относятся. ]]
local p = io.popen([[grep -rn "host:Clear()\|frame:Clear()\|wrap:Clear()\|parent:Clear()" ]] ..
    [[lua/ --include=*.lua | grep -v SafeClear ]] ..
    [[| grep -v ":[0-9]*: *--" | grep -vi ":[0-9]*: *[А-Яа-я]" ]])
for line in p:lines() do leftovers[#leftovers + 1] = line end
p:close()
ok(#leftovers == 0, "не осталось прямых :Clear() на панелях-окнах", leftovers[1])

print(("\n=== ИТОГ: успешно %d, провалено %d ===\n"):format(pass, fail))
if fail > 0 then os.exit(1) end
