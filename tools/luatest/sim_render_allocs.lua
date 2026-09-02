--[[
    sim_render_allocs.lua — сторож аллокаций в кадре.

    Правило §6.1.8: в render-хуках (HUDPaint, Think, PostDraw*, PreDrawHalos,
    RenderScreenspaceEffects, CalcView) нельзя создавать таблицы —
    `Color()`, `Vector()`, `Angle()`, `Material()`. Каждая такая строка —
    мусорная таблица 60–144 раза в секунду; сборщик Lua потом отдаёт их
    «рывками» кадра, и это ровно те микрофризы, на которые жаловался
    владелец («стоит тик, потом рывок»).

    Стенд следит за файлами, которые УЖЕ вычищены: они не должны
    испортиться обратно. Список расширяется по мере чистки — так уборка
    не откатывается следующей правкой.

    Почему не «весь проект сразу»: в проекте ещё около двух сотен таких
    мест, разом их чинить нельзя (это и правки поведения), а красный
    стенд, который «всегда красный», перестаёт быть сигналом (§10.1).

    Откатная проверка (§10.2): вернуть `Color(...)` в HUDPaint любого
    файла из списка — стенд краснеет с именем файла и строкой.
]]

local CLEANED = {
    "lua/autorun/client/cl_grm_augmentations_hud.lua",
    "lua/autorun/client/cl_grm_handcuffs.lua",
    "lua/autorun/zz_grm_bleedout.lua",
    "lua/entities/grm_comp_base/cl_init.lua",
    "lua/autorun/sh_00_grm_ui.lua",
    -- волна 7 (02.09): транспортный HUD, HUD функций кастомизации,
    -- трекер/тост/диалоги квестов, подписи фракций и плашка коменд. часа
    "lua/autorun/client/cl_grm_vehicle_hud.lua",
    "lua/autorun/client/cl_grm_customization.lua",
    "lua/autorun/client/cl_grm_quests.lua",
    "lua/autorun/sh_factions.lua",
    "lua/autorun/sh_faction_fixes.lua",
    -- волна 7, продолжение: плашки бана/недвижимости/дверей
    "lua/autorun/sh_grm_ban.lua",
    "lua/autorun/sh_grm_estate.lua",
    "lua/autorun/sh_grm_doors.lua",
    -- волна 7, хвост: GPS-метки, радиальный биндер, 911, хало, плашки,
    -- баннер, вес, камера от 3-го лица, капсула, круиз, курьер, выносливость
    "lua/autorun/sh_grm_jobs.lua",
    "lua/autorun/sh_grm_binder.lua",
    "lua/autorun/sh_grm_911.lua",
    "lua/autorun/sh_grm_property.lua",
    "lua/autorun/sh_grm_nameplate.lua",
    "lua/autorun/sh_grm_broadcast.lua",
    "lua/autorun/client/cl_grm_encumbrance.lua",
    "lua/autorun/client/cl_grm_thirdperson.lua",
    "lua/entities/grm_augmentation_pod/init.lua",
    "lua/autorun/sh_grm_cruise.lua",
    "lua/autorun/sh_grm_jobs_courier.lua",
    "lua/autorun/sh_grm_movement.lua",
    "lua/autorun/sh_grm_fire_dispatch.lua",
    "lua/autorun/zz_grm_doors_plus.lua",
    "lua/entities/grm_home_bed/cl_init.lua",
    "lua/autorun/client/cl_grm_cctv.lua",
    "lua/autorun/sh_grm_chip_control.lua",
    -- волна 7, PostDraw-хвост (аудит с исправленным списком хуков):
    -- 3D2D-маркеры знаков, инкассации, сетей, пожарок, камер багажников,
    -- плит, превью квест-тула и индустрии
    "lua/autorun/sh_grm_plates.lua",
    "lua/autorun/sh_grm_radionet.lua",
    "lua/autorun/sh_grm_fire_truck.lua",
    "lua/weapons/gmod_tool/stools/grm_quest_tool.lua",
    "lua/autorun/client/cl_grm_industry_ui.lua",
    "lua/autorun/sh_grm_trunk.lua",
    "lua/autorun/sh_grm_stove_slots.lua",
    -- инструменты-стулы: собственные HUDPaint-оверлеи
    "lua/weapons/gmod_tool/stools/grm_arrest_zone.lua",
    "lua/weapons/gmod_tool/stools/grm_business.lua",
    "lua/weapons/gmod_tool/stools/grm_measure.lua",
    "lua/weapons/gmod_tool/stools/grm_perm_tool.lua",
    "lua/weapons/gmod_tool/stools/grm_transport.lua",
}

-- Хуки, которые вызываются каждый кадр.
local RENDER_HOOKS = {
    HUDPaint = true, HUDPaintBackground = true, Think = true, Tick = true,
    PostDrawOpaqueRenderables = true, PostDrawTranslucentRenderables = true,
    PostDrawHUD = true, PreDrawHalos = true, RenderScreenspaceEffects = true,
    CalcView = true, PostPlayerDraw = true,
}

--[[ Конструкторы таблиц, которые нельзя звать в кадре.
     Ищем ТОЛЬКО самостоятельные вызовы: перед именем не должно быть буквы,
     цифры, '_' или ':'/'.' — иначе ловим безобидные surface.SetDrawColor(),
     render.SetMaterial() и методы vec:Angle(), которые аллоцирует движок,
     а не автор. На ложных срабатываниях сторож быстро стал бы «шумом,
     который все игнорируют». ]]
local FORBIDDEN = { "Color", "Vector", "Angle", "Material" }

local function hasCtor(line, name)
    local pos = 1
    while true do
        local s, e = line:find(name, pos, true)
        if not s then return false end
        local prev = s > 1 and line:sub(s - 1, s - 1) or ""
        local after = line:sub(e + 1, e + 1):match("^%s*%(") and "(" or ""
        if after == "(" and (prev == "" or not prev:match("[%w_:.]")) then
            return true
        end
        pos = e + 1
    end
end

local pass, fail = 0, 0
local function ok(cond, name, extra)
    if cond then
        pass = pass + 1
        print("  ok   " .. name)
    else
        fail = fail + 1
        print("  FAIL " .. name .. (extra and ("\n         " .. extra) or ""))
    end
end

local function read(path)
    local fh = io.open(path, "rb")
    if not fh then return nil end
    local data = fh:read("*a")
    fh:close()
    return data
end

--[[ Комментарии отрезаем построчно, сохраняя нумерацию строк: иначе
     пояснение «раньше здесь был Color()» само провалит проверку. ]]
local function stripComments(src)
    local out = {}
    local inBlock = false
    for line in (src .. "\n"):gmatch("([^\n]*)\n") do
        local code = line
        if inBlock then
            local finish = code:find("]]", 1, true)
            code = finish and code:sub(finish + 2) or ""
            inBlock = not finish
        end
        code = code:gsub("%-%-%[%[.-%]%]", "")
        local blockStart = code:find("%-%-%[%[")
        if blockStart then
            code = code:sub(1, blockStart - 1)
            inBlock = true
        end
        code = code:gsub("%-%-[^\n]*", "")
        out[#out + 1] = code
    end
    return out
end

--- Найти строки render-хуков и вернуть их диапазоны.
local function renderRanges(lines)
    local ranges = {}
    local i = 1
    while i <= #lines do
        local hookName = lines[i]:match('hook%.Add%(%s*"(%w+)"')
        if hookName and RENDER_HOOKS[hookName] then
            local depth, j = 0, i
            repeat
                local code = lines[j]:gsub('"[^"]*"', '""')
                local _, opens = code:gsub("%f[%w](function)%f[%W]", "")
                local _, ifs = code:gsub("%f[%w](if)%f[%W]", "")
                local _, fors = code:gsub("%f[%w](for)%f[%W]", "")
                local _, whiles = code:gsub("%f[%w](while)%f[%W]", "")
                local _, ends = code:gsub("%f[%w](end)%f[%W]", "")
                depth = depth + opens + ifs + fors + whiles - ends
                j = j + 1
            until depth <= 0 or j > #lines
            ranges[#ranges + 1] = { from = i, to = j - 1, hook = hookName }
            i = j
        else
            i = i + 1
        end
    end
    return ranges
end

for _, path in ipairs(CLEANED) do
    local src = read(path)
    if not src then
        ok(false, "файл на месте: " .. path)
    else
        local lines = stripComments(src)
        local ranges = renderRanges(lines)
        local problems = {}
        for _, range in ipairs(ranges) do
            for lineNo = range.from, range.to do
                for _, bad in ipairs(FORBIDDEN) do
                    if hasCtor(lines[lineNo], bad) then
                        problems[#problems + 1] = ("%s:%d — %s(...) в %s")
                            :format(path, lineNo, bad, range.hook)
                    end
                end
            end
        end
        ok(#problems == 0,
            ("%s: в render-хуках нет создания таблиц (проверено хуков: %d)")
                :format(path:match("[^/]+$"), #ranges),
            #problems > 0 and table.concat(problems, "\n         ") or nil)
    end
end

-- Контроль самого стенда: он обязан ловить нарушение, иначе он украшение.
local canary = [[
hook.Add("HUDPaint", "Canary", function()
    draw.RoundedBox(4, 0, 0, 10, 10, Color(1, 2, 3))
end)
]]
local canaryLines = stripComments(canary)
local canaryRanges = renderRanges(canaryLines)
local caught = false
for _, range in ipairs(canaryRanges) do
    for lineNo = range.from, range.to do
        if hasCtor(canaryLines[lineNo], "Color") then caught = true end
    end
end
ok(caught, "сторож ловит Color() внутри HUDPaint (самопроверка)")

local innocent = 'surface.SetDrawColor(1, 2, 3) render.SetMaterial(cached) local a = target:Angle() self:SetColor(c)'
ok(not hasCtor(innocent, "Color") and not hasCtor(innocent, "Material")
    and not hasCtor(innocent, "Angle"),
    "сторож не ругается на SetDrawColor/SetMaterial/метод vec:Angle() (ложная тревога)")
ok(hasCtor("  draw.RoundedBox(4, 0, 0, w, h, Color(1, 2, 3))", "Color")
    and hasCtor("local up = Vector(0, 0, 1)", "Vector"),
    "самостоятельные конструкторы находятся (самопроверка чувствительности)")

print(("RENDER ALLOCS: %d/%d, провалов: %d"):format(pass, pass + fail, fail))
os.exit(fail > 0 and 1 or 0)
