--[[
    sim_comp_base.lua — служебные компьютеры GRM на общей базе.

    Что было: одиннадцать станций (мэрия, юстиция, полиция, медицина,
    армия, жандармерия, госбезопасность, пожарные, образование,
    автоинспекция, гражданский терминал) повторяли один и тот же код —
    ENT:Initialize (модель/физика/имя), ENT:Draw (табличка 3D2D из трёх
    строк) и ENT:SetupDataTables. Отличались только подписями и цветами.

    Чем это плохо на практике:
      1. правка таблички (шрифт, отступ, подсказка) требовала одиннадцати
         одинаковых правок — забыл одну, и станция выглядит иначе;
      2. каждая копия Draw создавала ЧЕТЫРЕ Color() на кадр, а
         RenderGroup = RENDERGROUP_BOTH рисует энтити дважды: под сотню
         лишних таблиц в кадр при одиннадцати станциях на карте (§6.1.8).

    Что проверяем:
      * все станции наследуются от grm_comp_base и не переопределяют
        общую механику без причины;
      * подписи и цвета у каждой станции на месте (табличка не пустая);
      * динамические подписи (образование/гражданский/жандармерия)
        работают через CompLabels, а не через свою копию Draw;
      * в ENT:Draw базы НЕТ создания Color/Vector/Angle — защита от
        возврата аллокаций в кадр.

    Откатная проверка (§10.2): возврат Color() внутрь базового Draw и
    возврат ENT.Base = "base_gmodentity" любой станции красят стенд.
]]

local pass, fail = 0, 0
local function ok(cond, name)
    if cond then pass = pass + 1 print("  ok   " .. name)
    else fail = fail + 1 print("  FAIL " .. name) end
end

local ENT_DIR = "lua/entities/"
local STATIONS = {
    "grm_comp_cityhall", "grm_comp_court", "grm_comp_education", "grm_comp_fire",
    "grm_comp_medical", "grm_comp_military", "grm_comp_military_police",
    "grm_comp_police", "grm_comp_public", "grm_comp_security", "grm_comp_traffic",
}

local function read(path)
    local fh = io.open(path, "rb")
    if not fh then return nil end
    local data = fh:read("*a")
    fh:close()
    return data
end

local function stripComments(src)
    src = src:gsub("%-%-%[%[.-%]%]", "")
    return (src:gsub("%-%-[^\n]*", ""))
end

-- ── минимальный GMod ──────────────────────────────────────────────────
function Color(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
RENDERGROUP_BOTH = 0
SOLID_VPHYSICS, MOVETYPE_VPHYSICS, SIMPLE_USE = 6, 6, 3
TEXT_ALIGN_CENTER = 1
function AddCSLuaFile() end
function include() end
function IsValid(v) return v ~= nil and v ~= false end

--- Загрузить shared.lua энтити так, как это делает GMod: наследник видит
--- поля базы через ENT.Base.
local function loadShared(cls, baseEnt)
    local src = read(ENT_DIR .. cls .. "/shared.lua")
    if not src then return nil, "нет shared.lua" end
    local env = setmetatable({}, { __index = _G })
    env.ENT = setmetatable({}, { __index = baseEnt })
    local chunk, err = loadstring(src, cls)
    if not chunk then return nil, err end
    setfenv(chunk, env)
    local okRun, runErr = pcall(chunk)
    if not okRun then return nil, runErr end
    return env.ENT
end

-- ── база ──────────────────────────────────────────────────────────────
local baseEnt = loadShared("grm_comp_base", {})
ok(baseEnt ~= nil, "grm_comp_base загружается")
baseEnt = baseEnt or {}
ok(type(baseEnt.CompLabels) == "function", "база даёт CompLabels")
ok(type(baseEnt.SetupDataTables) == "function", "база даёт SetupDataTables")

local baseInit = read(ENT_DIR .. "grm_comp_base/init.lua") or ""
local baseDraw = read(ENT_DIR .. "grm_comp_base/cl_init.lua") or ""
ok(baseInit:find("function ENT:Initialize", 1, true) ~= nil, "база даёт Initialize")
ok(baseInit:find("function ENT:OnCompInit", 1, true) ~= nil,
    "у базы есть точка расширения OnCompInit (станции со своей логикой)")
ok(baseDraw:find("function ENT:Draw", 1, true) ~= nil, "база даёт Draw")

-- Аллокации в кадре — то, ради чего всё сводилось.
local drawBody = stripComments(baseDraw):match("function ENT:Draw%(%).-\nend")
ok(drawBody ~= nil, "тело базового Draw найдено")
drawBody = drawBody or ""
ok(drawBody:find("Color(", 1, true) == nil,
    "в базовом Draw нет Color() — цвета созданы один раз при загрузке")
ok(drawBody:find("Material(", 1, true) == nil, "в базовом Draw нет Material()")

-- ── станции ───────────────────────────────────────────────────────────
for _, cls in ipairs(STATIONS) do
    local ent, err = loadShared(cls, baseEnt)
    if not ent then
        ok(false, cls .. ": shared.lua не загрузился (" .. tostring(err) .. ")")
    else
        ok(ent.Base == "grm_comp_base", cls .. ": наследуется от grm_comp_base")

        local colors = ent.CompColors
        ok(type(colors) == "table" and colors.bg and colors.title and colors.sub and colors.hint,
            cls .. ": палитра таблички задана целиком")

        local self_ = setmetatable({
            _name = "",
            _army = (cls == "grm_comp_military_police"),
            GetComputerName = function(s) return s._name end,
            IsArmyDesk = function(s) return s._army end,
        }, { __index = ent })

        local title, subtitle, hint = self_:CompLabels()
        ok(type(title) == "string" and title ~= "", cls .. ": заголовок таблички не пустой")
        ok(type(subtitle) == "string", cls .. ": подзаголовок — строка")
        ok(type(hint) == "string" and hint ~= "", cls .. ": подсказка не пустая")

        -- Станция не должна возвращать себе копии общей механики.
        local initSrc = stripComments(read(ENT_DIR .. cls .. "/init.lua") or "")
        local clSrc = stripComments(read(ENT_DIR .. cls .. "/cl_init.lua") or "")
        ok(initSrc:find("function ENT:Initialize", 1, true) == nil,
            cls .. ": своей копии Initialize нет")
        ok(clSrc:find("function ENT:Draw", 1, true) == nil,
            cls .. ": своей копии Draw нет")
    end
end

-- ── динамические подписи ──────────────────────────────────────────────
local edu = loadShared("grm_comp_education", baseEnt)
local eduSelf = setmetatable({ _name = "ГИМНАЗИЯ №1",
    GetComputerName = function(s) return s._name end }, { __index = edu })
ok(select(1, eduSelf:CompLabels()) == "ГИМНАЗИЯ №1",
    "образование: заголовок берётся из имени, заданного инструментом")
eduSelf._name = ""
ok(select(1, eduSelf:CompLabels()) == "УЧРЕЖДЕНИЕ ОБРАЗОВАНИЯ",
    "образование: без имени — значение по умолчанию")

local pub = loadShared("grm_comp_public", baseEnt)
local pubSelf = setmetatable({ _name = "ВОКЗАЛ • ТЕРМИНАЛ 3",
    GetComputerName = function(s) return s._name end }, { __index = pub })
local pTitle, pSub = pubSelf:CompLabels()
ok(pTitle == "ДЛЯ ГРАЖДАН" and pSub == "ВОКЗАЛ • ТЕРМИНАЛ 3",
    "гражданский терминал: под заголовком — имя конкретной станции")

local mp = loadShared("grm_comp_military_police", baseEnt)
local mpSelf = setmetatable({ _name = "", _army = true,
    GetComputerName = function(s) return s._name end,
    IsArmyDesk = function(s) return s._army end }, { __index = mp })
local mTitle, mSub = mpSelf:CompLabels()
ok(mTitle == "ВООРУЖЁННЫЕ СИЛЫ" and mSub == "Служебный терминал",
    "жандармерия: армейский стол подписан как армейский")
mpSelf._army = false
mTitle, mSub = mpSelf:CompLabels()
ok(mTitle == "ПОЛЕВАЯ ЖАНДАРМЕРИЯ" and mSub == "Feldgendarmerie",
    "жандармерия: жандармский стол подписан как жандармский")

-- Профиль службы обязан ставиться при появлении энтити.
local mpInit = stripComments(read(ENT_DIR .. "grm_comp_military_police/init.lua") or "")
ok(mpInit:find("function ENT:OnCompInit", 1, true) ~= nil
    and mpInit:find("SetServiceProfile", 1, true) ~= nil,
    "жандармерия: профиль службы ставится через OnCompInit, а не через копию Initialize")

print(("COMP BASE: %d/%d, провалов: %d"):format(pass, pass + fail, fail))
os.exit(fail > 0 and 1 or 0)
