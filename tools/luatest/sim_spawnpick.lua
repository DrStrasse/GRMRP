--[[ Живой прогон точек входа (заказ владельца 27.08):
     «Надо вход и выход проработать — спавн фракции/отдела, личный спавн
      (дома) или на месте выхода. После выбора персонажа тёмный экран и
      крупные слоты по центру с подписью ВЫБЕРИТЕ ТОЧКУ ВХОДА.»

     Проверяется:
       1) три источника точки и их подписи;
       2) экран не показывается, когда выбирать не из чего;
       3) запоминание места выхода и защита от абуза (смерть, арест, лимб);
       4) дом не работает опечатанный и с просроченной арендой;
       5) нельзя вернуться в чужое закрытое помещение;
       6) сервер проверяет выбор, а не верит клиенту.

     Запуск: luajit tools/luatest/sim_spawnpick.lua ]]
local pass, fail = 0, 0
local function ok(v, n, extra)
    if v then pass = pass + 1 print("  ok   " .. n)
    else fail = fail + 1 print("  FAIL " .. n .. "  " .. tostring(extra or "")) end
end

SERVER, CLIENT = true, false
function AddCSLuaFile() end
function istable(v) return type(v) == "table" end
function isstring(v) return type(v) == "string" end
function isfunction(v) return type(v) == "function" end
function IsValid(v) return istable(v) and v._valid ~= false end
function string.Trim(s) return (string.gsub(tostring(s or ""), "^%s*(.-)%s*$", "%1")) end
function math.Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function table.Count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
function Vector(x, y, z) return { x = x or 0, y = y or 0, z = z or 0 } end
function Angle(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
function ErrorNoHalt() end
game = { GetMap = function() return "rp_city" end }
hook = { Add = function() end, Run = function() end }
timer = { Simple = function() end, Create = function() end, Remove = function() end }
concommand = { Add = function() end }
util = { AddNetworkString = function() end }
file = { Exists = function() return false end, Read = function() return "" end, Write = function() end }
net = setmetatable({}, { __index = function() return function() return "" end end })
player = { GetAll = function() return {} end }
GRM = {}

-- Ядро GRM (sh_00_grm_ui + sh_01_grm_core) — как на сервере, до модулей.
dofile("tools/luatest/lib_grm_core.lua")()
assert(loadfile("lua/autorun/sh_grm_spawnpick.lua"))()
local SP = GRM.SpawnPick

--- Игрок-заглушка.
local function mkPly(opts)
    opts = opts or {}
    local nw = opts.nw or {}
    return {
        _valid = true, _key = opts.key or "1:char1", _pos = opts.pos or Vector(10, 20, 30),
        -- Настоящий игрок GMod всегда отвечает на :IsPlayer();
        -- без этого мок не проходит канон GRM.CharKey.
        IsPlayer = function() return true end,
        SteamID64 = function() return "1" end,
        GetPos = function(s) return s._pos end,
        EyeAngles = function() return Angle(0, 90, 0) end,
        SetPos = function(s, v) s._pos = v end,
        SetEyeAngles = function() end,
        Alive = function() return opts.dead ~= true end,
        InVehicle = function() return opts.inVehicle == true end,
        GetNWBool = function(_, k, d) if nw[k] ~= nil then return nw[k] end return d or false end,
        GetNWString = function(_, k, d) return nw[k] or d or "" end,
        PrintMessage = function() end,
    }
end
GRM.Identity = { CharacterKey = function(p) return p._key end }

print("\n=== 1. ИСТОЧНИК: ФРАКЦИЯ ===")
local factionPos = Vector(500, 500, 64)
_G.GetSpawnPointForPlayer = function() return factionPos, Angle(0, 45, 0) end
GRM.Factions = { DisplayName = function(n) return "828-ая дивизия ВДВ" end }

local soldier = mkPly({ nw = { GRM_Faction = "828", GRM_DepartmentDisplay = "Штаб" } })
local fp = SP.FactionPoint(soldier)
ok(fp ~= nil and fp.pos == factionPos, "фракционная точка берётся из общей системы спавна")
ok(fp and fp.label:find("Штаб", 1, true) ~= nil,
   "подпись уточняет подразделение — видно, куда поставят", fp and fp.label)

local offduty = mkPly({ nw = { GRM_Faction = "828", GRM_FactionOffDuty = true } })
ok(SP.FactionPoint(offduty) == nil, "вне службы фракционная точка недоступна")
local civil = mkPly({ nw = {} })
ok(SP.FactionPoint(civil) == nil, "гражданскому фракционная точка не положена")

print("\n=== 2. ИСТОЧНИК: ДОМ ===")
GRM.Property = {
    Records = {},
    Normalize = function(r) return r end,
    HasAccess = function(ply, r) return r.ownerKey == ply._key end,
    IsInside = function(r, pos)
        local a, b = r.zone.mins, r.zone.maxs
        return pos.x >= a.x and pos.y >= a.y and pos.z >= a.z
            and pos.x <= b.x and pos.y <= b.y and pos.z <= b.z
    end,
}
local flat = {
    id = "flat14", name = "Квартира 14", type = "apartment",
    ownerType = "character", ownerKey = "1:char1", tenure = "owned",
    sealed = false, rentUntil = 0,
    zone = { mins = { x = 0, y = 0, z = 0 }, maxs = { x = 100, y = 100, z = 100 } },
}
GRM.Property.Records = { flat14 = flat }

local owner = mkPly({ key = "1:char1" })
local hp = SP.HomePoint(owner)
ok(hp ~= nil, "владелец жилья получает точку «Дом»")
ok(hp and hp.label == "Квартира 14", "подпись — название объекта", hp and hp.label)
ok(hp and hp.pos.x == 50 and hp.pos.y == 50, "точка в центре зоны жилья")

local stranger = mkPly({ key = "9:char1" })
ok(SP.HomePoint(stranger) == nil, "чужому человеку дом не предлагается")

flat.sealed = true
ok(SP.HomePoint(owner) == nil, "опечатанное жильё домом не считается")
flat.sealed = false

flat.tenure = "rent"
flat.rentUntil = os.time() - 100
ok(SP.HomePoint(owner) == nil, "просроченная аренда убирает вариант «Дом»")
flat.rentUntil = os.time() + 100000
ok(SP.HomePoint(owner) ~= nil, "живая аренда — дом работает")
flat.tenure = "owned"

local office = { id = "off", name = "Офис", type = "office", ownerType = "character",
    ownerKey = "1:char1", tenure = "owned", sealed = false, rentUntil = 0,
    zone = { mins = { x = 500, y = 0, z = 0 }, maxs = { x = 600, y = 100, z = 100 } } }
GRM.Property.Records = { off = office }
ok(SP.HomePoint(owner) == nil, "офис — не жильё, точкой входа не становится")
GRM.Property.Records = { flat14 = flat }

print("\n=== 3. ИСТОЧНИК: ГДЕ ВЫШЕЛ ===")
SP.Data = {}
SP.Remember(owner)
ok(SP.Data["1:char1"] ~= nil, "позиция при выходе запоминается")
local lp = SP.LastPoint(owner)
ok(lp ~= nil and lp.pos.x == 10, "и возвращается как точка входа")

SP.Data["1:char1"].map = "gm_other"
ok(SP.LastPoint(owner) == nil, "точка с другой карты не предлагается")
SP.Data["1:char1"].map = "rp_city"

SP.Data["1:char1"].at = os.time() - (SP.LastLifetime + 10)
ok(SP.LastPoint(owner) == nil, "просроченная точка забывается")
SP.Data["1:char1"].at = os.time()

print("\n=== 3б. ЗАЩИТА ОТ АБУЗА ===")
ok(SP.CanRemember(mkPly({ dead = true })) == false, "мёртвый игрок точку не сохраняет")
ok(SP.CanRemember(mkPly({ nw = { GRM_Arrested = true } })) == false,
   "арестованный тоже — иначе это телепорт в тюрьму")
local inLimbo = mkPly({}) inLimbo.GRMCharLimbo = true
ok(SP.CanRemember(inLimbo) == false, "игрок в лимбе не сохраняет позицию")
ok(SP.CanRemember(mkPly({ nw = { GRM_CharacterPending = true } })) == false,
   "не выбравший персонажа тоже")
--[[ Поведение изменено 27.08 по жалобе владельца «где вышел не запоминает»:
     раньше выход из игры в машине не сохранялся ВООБЩЕ, то есть вся поездка
     пропадала. Теперь запоминаем позицию самой машины (SP.RememberPos),
     а игрока ставим рядом на землю. ]]
ok(SP.CanRemember(mkPly({ inVehicle = true })) == true,
   "выход из игры в машине теперь запоминается (берём позицию машины)")
ok(SP.CanRemember(mkPly({})) == true, "обычный игрок сохраняет нормально")

print("\n=== 4. ЧУЖОЕ ЗАКРЫТОЕ ПОМЕЩЕНИЕ ===")
-- Игрок вышел внутри чужой квартиры: вернуться туда нельзя.
local intruder = mkPly({ key = "9:char1", pos = Vector(50, 50, 10) })
SP.Data["9:char1"] = { pos = { x = 50, y = 50, z = 10 }, ang = { y = 0 },
    at = os.time(), map = "rp_city" }
ok(SP.LastPoint(intruder) == nil,
   "нельзя вернуться в чужой дом через точку выхода")
ok(SP.PointAllowed(owner, Vector(50, 50, 10)) == true,
   "а хозяин к себе возвращается свободно")
ok(SP.PointAllowed(intruder, Vector(900, 900, 10)) == true,
   "улица доступна всем")

print("\n=== 5. ЭКРАН ПОКАЗЫВАЕТСЯ ТОЛЬКО КОГДА ЕСТЬ ВЫБОР ===")
SP.Data = {}
local lonely = mkPly({ key = "5:char1" })
GRM.Property.Records = {}
ok(#SP.Options(lonely) == 0, "нет вариантов — список пуст")
ok(SP.Offer(lonely) == false, "экран не показывается")

GRM.Property.Records = { flat14 = flat }
local homeOnly = mkPly({ key = "1:char1" })
ok(#SP.Options(homeOnly) == 1, "один вариант")
ok(SP.Offer(homeOnly) == false, "экран не показывается, игрока ставят сразу")
ok(homeOnly._pos.x == 50, "и он оказывается дома", homeOnly._pos.x)

local rich = mkPly({ key = "1:char1", nw = { GRM_Faction = "828" } })
SP.Data["1:char1"] = { pos = { x = 700, y = 700, z = 10 }, ang = { y = 0 },
    at = os.time(), map = "rp_city" }
local opts = SP.Options(rich)
ok(#opts == 3, "фракция, дом и место выхода — три варианта", #opts)
ok(SP.Offer(rich) == true, "вот теперь экран нужен")
ok(rich.GRMSpawnPickPending == true, "и сервер ждёт ответа игрока")

print("\n=== 6. ВЫБОР ПРОВЕРЯЕТСЯ НА СЕРВЕРЕ ===")
local function body(path)
    local fh = io.open(path, "rb") if not fh then return "" end
    local t = fh:read("*a") fh:close() return t
end
local src = body("lua/autorun/sh_grm_spawnpick.lua")
ok(src:find("if not ply.GRMSpawnPickPending then return end", 1, true) ~= nil,
   "пакет без активного экрана игнорируется")
ok(src:find("for _, opt in ipairs(SP.Options(ply)) do", 1, true) ~= nil,
   "сервер сверяет выбор со списком доступных, а не верит клиенту")
ok(SP.Resolve(rich, "нет_такого") == nil, "неизвестный вид точки отклоняется")
ok(SP.Apply(rich, "нет_такого") == false, "и применить его нельзя")

print("\n=== 7. ИНТЕРФЕЙС И ВСТРАИВАНИЕ ===")
local charSrc = body("lua/autorun/sh_grm_character.lua")
ok(charSrc:find('hook.Run("GRM_CharacterConfirmed", ply)', 1, true) ~= nil,
   "модуль персонажей сообщает о подтверждении — на этом держится экран")
ok(src:find("ВЫБЕРИТЕ ТОЧКУ ВХОДА", 1, true) ~= nil, "подпись как в заказе")
ok(src:find("Color(6, 8, 13, 245)", 1, true) ~= nil, "фон тёмный")
ok(src:find("local size, gap = 190, 26", 1, true) ~= nil, "слоты крупные и квадратные")
ok(src:find("if key == KEY_ESCAPE then return true end", 1, true) ~= nil,
   "экран нельзя закрыть, не выбрав точку")
ok(src:find('icon = "icon16/house.png"', 1, true) ~= nil, "у слотов есть значки")

print(("\n=== ИТОГ: успешно %d, провалено %d ===\n"):format(pass, fail))
if fail > 0 then os.exit(1) end
