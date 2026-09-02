--[[--------------------------------------------------------------------
    sim_menu_showcase — витрина персонажа в меню паузы (замечания
    владельца 03.09 вечер-6: «персонаж мелкий, бодигруппы так и не
    появились»). Контракт исходника:
      • камеру НЕ ставим руками — Layout() DModelPanel сам вписывает
        модель в панель (ручной CamPos на ~120 юнитов = «мелкий»);
      • внешность применяется ПОСЛЕ SetAnimated (контроллер сбрасывал);
      • бодигруппы пишутся и в панель, и в model entity;
      • UpdateStats живой: сменил экипировку — витрина догоняет;
      • размеры: модель не меньше 240px, карточка до 430px шириной.
----------------------------------------------------------------------]]
local fails, total = 0, 0
local function check(name, cond, extra)
    total = total + 1
    if cond then print("  ok   " .. name)
    else fails = fails + 1 print("  FAIL " .. name .. "   " .. tostring(extra or "")) end
end
local f = assert(io.open("gamemodes/grmrp/gamemode/modules/ui/cl_grmrp_menu.lua", "rb"))
local h = f:read("*a") f:close()
local function has(n) return h:find(n, 1, true) ~= nil end

check("ручной камеры нет (авто-вписывание Layout)", not has("SetCamPos(Vector(dist"))
check("camParams вырезан за ненадобностью", not has("local function camParams"))
check("окно модели не меньше 240px", has("240, 440"))
check("карточка раздвинута до 430px", has("320, 430"))
check("внешность — отдельным проходом applySkinGroups", has("local function applySkinGroups(m)"))
check("SetModel+внешность — applyLook", has("m:SetModel(ply:GetModel() or")
    and has("applySkinGroups(m)\n    end"))

-- порядок внутри newModel: SetAnimated -> applyLook
local i1 = h:find("local function newModel", 1, true)
local i2 = h:find("\n    end", i1, true)
local body = h:sub(i1, i2)
local ia = body:find("m:SetAnimated(true)", 1, true)
local ib = body:find("applyLook(m)", 1, true)
check("внешность применяется ПОСЛЕ SetAnimated", ia ~= nil and ib ~= nil and ib > ia)
check("группы пишутся в панель", has("m:SetBodygroup(idx, val)"))
check("группы пишутся в model entity", has("me:SetBodygroup(idx, val)"))
check("индекс bg.id численный страж", has("tonumber(bg.id)"))
check("витрина живая (UpdateStats догоняет экипировку)", has("applySkinGroups(mm)"))
check("пересъёмка при смене модели", has("applyLook(mm) else"))
check("оттиск сборки вечер-7", has("вечер-7 (03.09)"))

print(("\nMENU SHOWCASE: %d/%d, провалов: %d"):format(total - fails, total, fails))
os.exit(fails == 0 and 0 or 1)
