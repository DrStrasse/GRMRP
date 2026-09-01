--[[ Регрессионный стенд: ЗАВИСАНИЕ Q-МЕНЮ У ИГРОКА БЕЗ ПРАВ.

     ПРИЧИНА (showToolSettings в sh_grm_qmenu.lua). Было:
         CP:InvalidateLayout(true)
         CP:PerformLayout()          -- прямой вызов, так делать нельзя
         ...
         CP:SetTall(math.max(240, bottom + 12))

     Два документированных нарушения (wiki Panel):
       1. «You should not call this function directly. Use
          Panel:InvalidateLayout instead» — прямой вызов PerformLayout
          обходит внутренний флаг движка «раскладка уже идёт», то есть
          снимает штатную защиту от повторного входа.
       2. «SetTall … marks this panel for layout (Panel:InvalidateLayout)»
          и «You should avoid calling SetPos in PerformLayout to avoid
          infinite loops» — установка высоты ВНУТРИ раскладки снова
          заказывает раскладку.
     Вместе это даёт цикл: раскладка → считаем bottom → SetTall → панель
     помечена → раскладка → … Клиент встаёт НАМЕРТВО без ошибки Lua
     (поэтому консоль была пуста).

     Почему не воспроизводилось у суперадмина: при adminsToo=false админ
     получает ВАНИЛЬНОЕ Q и этот код не выполняется вовсе. Наше меню
     открывает только игрок без прав — фриз и «появился» ровно после
     снятия суперадмина.

     Стенд моделирует движок честно: SetTall помечает панель и вызывает
     раскладку повторно. Старый код (без флага и без порога) обязан
     уйти в бесконечность, текущий — сойтись. ]]

local total, fails = 0, 0
local function check(name, ok, extra)
    total = total + 1
    if ok then
        print("  OK   " .. name)
    else
        fails = fails + 1
        print("  FAIL " .. name .. (extra and ("  → " .. tostring(extra)) or ""))
    end
end

local HARD_LIMIT = 5000   -- столько шагов = «клиент завис»

--[[ Мини-движок VGUI: панель с высотой; SetTall помечает её и просит
     раскладку заново — ровно как настоящий Panel. Раскладка зовёт
     переданный расчётчик высоты. ]]
local function makeEngine(fitFn)
    local eng = { steps = 0, sets = 0, overflow = false }
    local cp  = { tall = 240 }

    function cp:GetTall() return self.tall end
    function cp:SetTall(v)
        eng.sets = eng.sets + 1
        local changed = (v ~= self.tall)
        self.tall = v
        -- документированное поведение: SetTall → InvalidateLayout
        if changed then eng.dirty = true end
    end
    -- содержимое DForm: подписи переносятся, поэтому нижняя граница
    -- зависит от текущей высоты панели (округление под полосу прокрутки)
    function cp:Bottom()
        return 288 + (self.tall % 2 == 0 and 1 or 0)
    end

    eng.dirty = true
    while eng.dirty do
        eng.dirty = false
        eng.steps = eng.steps + 1
        if eng.steps > HARD_LIMIT then eng.overflow = true break end
        fitFn(cp)
    end
    return eng, cp
end

--[[ СТАРЫЙ расчёт: без порога и без защиты от повторного входа. ]]
local function fitOld(cp)
    local want = math.max(240, cp:Bottom() + 12)
    cp:SetTall(want)                      -- ставим ВСЕГДА → снова раскладка
end

--[[ ТЕКУЩИЙ расчёт: порог 2 px + флаг повторного входа
     (те же правила, что в showToolSettings → fitCPHeight). ]]
local function fitNew(cp)
    if cp._grmFitting then return end
    cp._grmFitting = true
    local want = math.max(240, cp:Bottom() + 12)
    local have = cp:GetTall()
    if math.abs(have - want) > 2 then
        cp:SetTall(want)
    end
    cp._grmFitting = false
end

print("=== ТЕСТ 1: старый код обязан зациклиться (иначе стенд слеп) ===")
local engOld = makeEngine(fitOld)
check("старый код НЕ сходится — фриз воспроизведён", engOld.overflow,
      not engOld.overflow and ("неожиданно сошёлся за " .. engOld.steps .. " шагов"))

print("\n=== ТЕСТ 2: текущий код сходится ===")
local engNew, cpNew = makeEngine(fitNew)
check("текущий код сходится и не вешает клиент", not engNew.overflow,
      engNew.overflow and "раскладка не сошлась")
check("раскладка завершается за считаные шаги", (not engNew.overflow) and engNew.steps <= 8,
      "шагов: " .. tostring(engNew.steps))
check("высота осталась осмысленной (>=240)", cpNew.tall >= 240,
      "высота " .. tostring(cpNew.tall))

--[[ ТЕСТ 3. Прямой повторный вход: движок зовёт раскладку ИЗНУТРИ SetTall.
     Без флага это рекурсия до переполнения стека. ]]
print("\n=== ТЕСТ 3: повторный вход изнутри SetTall ===")
local reCp = { tall = 240, depth = 0, maxDepth = 0 }
function reCp:GetTall() return self.tall end
function reCp:Bottom() return 400 end
function reCp:SetTall(v)
    self.tall = v
    -- движок немедленно пересчитывает раскладку
    if self.depth < 200 then
        self.depth = self.depth + 1
        self.maxDepth = math.max(self.maxDepth, self.depth)
        fitNew(self)
        self.depth = self.depth - 1
    end
end
local okRe = pcall(fitNew, reCp)
check("повторный вход не рвёт стек", okRe)
check("флаг обрывает рекурсию на первом уровне", reCp.maxDepth <= 1,
      "глубина " .. tostring(reCp.maxDepth))

--[[ ТЕСТ 4. Дрожание ±1 px (округление ширины под полосу прокрутки)
     не должно бесконечно переставлять высоту. ]]
print("\n=== ТЕСТ 4: дрожание в 1 пиксель ===")
local jCp = { tall = 300, sets = 0 }
function jCp:GetTall() return self.tall end
function jCp:Bottom() return 288 + (self.tall % 2 == 0 and 1 or 0) end
function jCp:SetTall(v) self.sets = self.sets + 1 self.tall = v end
for _ = 1, 500 do fitNew(jCp) end
check("дрожание ±1 px гасится порогом", jCp.sets == 0,
      "лишних SetTall: " .. tostring(jCp.sets))

--[[ ТЕСТ 5. Страховка от возврата бага: в коде не должно быть прямого
     вызова PerformLayout и обязаны присутствовать флаг и порог. ]]
print("\n=== ТЕСТ 5: исходник Q-меню ===")
local src = io.open("lua/autorun/sh_grm_qmenu.lua", "r")
if not src then
    src = io.open("../../lua/autorun/sh_grm_qmenu.lua", "r")
end
if src then
    local code = src:read("*a") src:close()
    -- вырезаем комментарии: в пояснении к фиксу вызов упомянут текстом
    local bare = code:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", "")
    local direct = bare:match("CP:PerformLayout%s*%(")
    check("нет прямого вызова CP:PerformLayout()", direct == nil,
          "найден прямой вызов")
    check("UI не зовёт BuildToolPanel",
          not bare:find("QM.BuildToolPanel(tool, CP)", 1, true))
    check("нет самозаказа раскладки (SetTall по ControlPanel)",
          not bare:find("CP:SetTall", 1, true))
else
    check("исходник sh_grm_qmenu.lua найден", false, "файл не открылся")
end

print(("\n=== ИТОГ: %d/%d, failures=%d ==="):format(total - fails, total, fails))
if fails > 0 then os.exit(1) end
