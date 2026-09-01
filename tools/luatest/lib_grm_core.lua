--[[--------------------------------------------------------------------
    lib_grm_core — преамбула стендов: ядро GRM в мок-окружении.

    Зачем. На живом сервере `lua/autorun/` грузится по алфавиту, поэтому
    `sh_00_grm_ui.lua` и `sh_01_grm_core.lua` всегда есть к моменту, когда
    исполняется любой модуль. Стенды же грузили модуль в одиночку — и
    как только общая функция переехала из копии в ядро (GRM.CharKey,
    GRM.UI.Button), стенды начали падать на работающем коде.

    Что делает: доставляет ТОЛЬКО недостающие заглушки GMod (ничего не
    затирает — у каждого стенда своё окружение) и грузит НАСТОЯЩИЕ файлы
    ядра. Никаких копий проверяемой логики (§10.1.4).

    Использование — одной строкой перед загрузкой модулей стенда:
        dofile("tools/luatest/lib_grm_core.lua")()
----------------------------------------------------------------------]]

local function ensureGlobals()
    if _G.SERVER == nil then _G.SERVER, _G.CLIENT = true, false end
    if not _G.AddCSLuaFile then _G.AddCSLuaFile = function() end end
    if not _G.include then _G.include = function() end end
    if not _G.CreateClientConVar then _G.CreateClientConVar = function() end end
    if not _G.isstring then _G.isstring = function(v) return type(v) == "string" end end
    if not _G.isfunction then _G.isfunction = function(v) return type(v) == "function" end end
    if not _G.istable then _G.istable = function(v) return type(v) == "table" end end
    if not _G.isnumber then _G.isnumber = function(v) return type(v) == "number" end end
    if not _G.IsValid then
        _G.IsValid = function(v)
            if v == nil or v == false then return false end
            if type(v) ~= "table" then return true end
            if v.IsValid then return v:IsValid() end
            return v.__valid ~= false and v._valid ~= false and v.valid ~= false
        end
    end
    if not _G.Color then
        _G.Color = function(r, g, b, a)
            return { r = r or 255, g = g or 255, b = b or 255, a = a or 255 }
        end
    end
    if not _G.color_white then _G.color_white = _G.Color(255, 255, 255) end
    if not string.Trim then
        string.Trim = function(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
    end
    if not _G.player then _G.player = { GetAll = function() return {} end } end
end

--- Загрузить настоящий файл ядра. Ошибка загрузки — это ошибка стенда,
--- молчать нельзя: иначе стенд «зелёный» на несуществующем API.
local function loadCoreFile(path)
    local chunk, err = loadfile(path)
    if not chunk then
        error(("lib_grm_core: не загрузился %s: %s"):format(path, tostring(err)), 0)
    end
    chunk()
end

return function()
    ensureGlobals()
    _G.GRM = _G.GRM or {}
    -- Порядок тот же, что и на сервере: UI (sh_00) → контракты (sh_01).
    if not (GRM.UI and GRM.UI.Button) then loadCoreFile("lua/autorun/sh_00_grm_ui.lua") end
    if not GRM.CharKey then loadCoreFile("lua/autorun/sh_01_grm_core.lua") end
    return GRM
end
