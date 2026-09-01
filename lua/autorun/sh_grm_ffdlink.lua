-- Boot-шим: старт подсистемы идёт через планировщик GRM.Boot (приоритеты и
-- бюджет на тик). Если планировщик почему-то не загружен, работаем по-старому.
local function grmBootStart(id, tier, fn)
    if GRM and GRM.Boot and GRM.Boot.OnMapStart then return GRM.Boot.OnMapStart(id, tier, fn) end
    return hook.Add("InitPostEntity", id, fn)
end

--[[--------------------------------------------------------------------
    GRM FFD Link v1.2.0 (Код 108 → Код 109 → Код 110, память и персист)
    РУЧНАЯ связь «контроллер → исчезающие / раздвижные двери»:
      контроллер = grm_keypad или grm_scanner, дверь = любой проп с
      isFadingDoor (инструмент FFD Fading Door) или isSlidingDoor
      (инструмент GRM Раздвижная дверь).

    Код 110 (защита памяти и персистентность):
      * resolveEntry учитывает и текущую позицию, и базовую позицию
        раздвижной двери (Sliding_BasePos), допуск до 32 юнитов с приоритетом
        живых дверей — открытая/движущаяся раздвижная дверь НЕ теряется;
      * Fade НЕ стирает привязанные двери (prune=false при обычной работе);
      * FFD_MakeFadingDoor, PermData (Extract/Apply для prop_physics и
        prop_dynamic) и duplicator-модификаторы зарегистрированы прямо в
        autorun — перм-двери и раздвижные двери восстанавливаются на старте
        сервера ещё до взятия тулгана в руки;
      * RefreshAllControllers гарантирует синк NW-состояния после спавна пермов.
----------------------------------------------------------------------]]

if SERVER then
    AddCSLuaFile()
end

GRM = GRM or {}
GRM.FFDLink = GRM.FFDLink or {}
GRM._ffdLinkVer = "1.2.0"

-- какие энтити могут быть контроллерами связи
local CONTROLLERS = {
    grm_keypad  = true,
    grm_scanner = true,
}

-- shared: контроллер ли это (работает и на клиенте — по классу)
function GRM.FFDLink.IsController(ent)
    if not IsValid(ent) then return false end
    return CONTROLLERS[tostring(ent:GetClass() or "")] == true
end

-- ============================================================
-- SERVER: хранилище, mutate, resolve, персист
-- ============================================================
if SERVER then
    local MAX_LINKS  = 32   -- защита от раздувания одного контроллера
    local FIND_RANGE = 48   -- сфера выборки при разрешении записи
    local ACCEPT     = 32.0 -- юнитов: допуск совпадения позиции

    -- округление до 0.1: позиции переживают JSON-переупаковку перм-базы
    local function r1(v) return math.floor((tonumber(v) or 0) * 10 + 0.5) / 10 end

    -- записанная дверь -> живая энтити (класс + позиция в допуске ACCEPT)
    local function resolveEntry(e)
        if not istable(e) or not isstring(e.class) then return nil end
        local center = Vector(tonumber(e.x) or 0, tonumber(e.y) or 0, tonumber(e.z) or 0)
        local best, bestD = nil, ACCEPT * ACCEPT
        local candidates = ents.FindInSphere(center, FIND_RANGE)
        for _, ent in ipairs(candidates) do
            if IsValid(ent) then
                local cls = tostring(ent:GetClass() or "")
                local matchClass = (cls == e.class)
                    or (e.class == "prop_physics" and cls == "prop_dynamic")
                    or (e.class == "prop_dynamic" and cls == "prop_physics")
                if matchClass then
                    local p = ent.Sliding_BasePos or ent:GetPos()
                    local d = p:DistToSqr(center)
                    if ent.isFadingDoor or ent.isSlidingDoor then
                        if d <= bestD then best, bestD = ent, d end
                    elseif d <= bestD then
                        best, bestD = ent, d
                    end
                end
            end
        end
        return best
    end
    GRM.FFDLink._resolveEntry = resolveEntry -- для стула/тестов

    -- NW-зеркало для клиента (число + EntIndex'ы разрешённых дверей)
    function GRM.FFDLink.RefreshNW(ctrl)
        if not IsValid(ctrl) then return end
        local idxs = {}
        local n = 0
        for _, e in ipairs(ctrl.FFDLink_Doors or {}) do
            n = n + 1
            local ent = resolveEntry(e)
            if ent then idxs[#idxs + 1] = tostring(ent:EntIndex()) end
        end
        ctrl:SetNWInt("FFDLinkN", n)
        ctrl:SetNWString("FFDLinkIdx", table.concat(idxs, ","))
    end

    -- Обновить все контроллеры на карте (после InitPostEntity / PostCleanupMap)
    function GRM.FFDLink.RefreshAllControllers()
        for class, _ in pairs(CONTROLLERS) do
            for _, ctrl in ipairs(ents.FindByClass(class)) do
                if IsValid(ctrl) then
                    GRM.FFDLink.RefreshNW(ctrl)
                end
            end
        end
    end

    grmBootStart("GRM_FFDLink_RefreshPostEntity", "normal", function()
        timer.Simple(1.5, function()
            if GRM.FFDLink and GRM.FFDLink.RefreshAllControllers then
                GRM.FFDLink.RefreshAllControllers()
            end
        end)
    end)

    hook.Add("PostCleanupMap", "GRM_FFDLink_RefreshCleanup", function()
        timer.Simple(1.0, function()
            if GRM.FFDLink and GRM.FFDLink.RefreshAllControllers then
                GRM.FFDLink.RefreshAllControllers()
            end
        end)
    end)

    -- сериализуемая копия (для перм-базы и дубликатора)
    function GRM.FFDLink.ExportData(ctrl)
        local out = {}
        if not IsValid(ctrl) then return out end
        for _, e in ipairs(ctrl.FFDLink_Doors or {}) do
            if istable(e) and isstring(e.class) then
                out[#out + 1] = {
                    class = e.class,
                    x = tonumber(e.x) or 0,
                    y = tonumber(e.y) or 0,
                    z = tonumber(e.z) or 0,
                }
            end
        end
        return out
    end

    -- обратная развёртка (перм-Apply / дубликат)
    function GRM.FFDLink.ImportData(ctrl, links)
        if not IsValid(ctrl) then return end
        local out = {}
        if istable(links) then
            for _, e in ipairs(links) do
                if istable(e) and isstring(e.class) and e.class ~= "" and #out < MAX_LINKS then
                    out[#out + 1] = {
                        class = e.class,
                        x = tonumber(e.x) or 0,
                        y = tonumber(e.y) or 0,
                        z = tonumber(e.z) or 0,
                    }
                end
            end
        end
        ctrl.FFDLink_Doors = out
        GRM.FFDLink.RefreshNW(ctrl)
    end

    -- дубликатор: связи едут вместе с контроллером
    local function dupeStore(ctrl)
        if not (duplicator and duplicator.StoreEntityModifier) then return end
        pcall(function()
            if #(ctrl.FFDLink_Doors or {}) > 0 then
                duplicator.StoreEntityModifier(ctrl, "FFD_LinkList", { links = GRM.FFDLink.ExportData(ctrl) })
            elseif duplicator.ClearEntityModifier then
                duplicator.ClearEntityModifier(ctrl, "FFD_LinkList")
            end
        end)
    end
    if duplicator and duplicator.RegisterEntityModifier then
        duplicator.RegisterEntityModifier("FFD_LinkList", function(ply, ent, data)
            if istable(data) and istable(data.links) then
                GRM.FFDLink.ImportData(ent, data.links)
            end
        end)
    end

    function GRM.FFDLink.Count(ctrl)
        return (IsValid(ctrl) and istable(ctrl.FFDLink_Doors)) and #ctrl.FFDLink_Doors or 0
    end

    -- индекс записи этой двери в списке контроллера (или nil)
    function GRM.FFDLink.FindIndex(ctrl, door)
        if not (IsValid(ctrl) and IsValid(door)) then return nil end
        local class = tostring(door:GetClass() or "")
        local p = door.Sliding_BasePos or door:GetPos()
        local x, y, z = r1(p.x), r1(p.y), r1(p.z)
        for i, e in ipairs(ctrl.FFDLink_Doors or {}) do
            if (e.class == class or (e.class == "prop_physics" and class == "prop_dynamic") or (e.class == "prop_dynamic" and class == "prop_physics"))
                and math.abs((tonumber(e.x) or 0) - x) <= 1.0
                and math.abs((tonumber(e.y) or 0) - y) <= 1.0
                and math.abs((tonumber(e.z) or 0) - z) <= 1.0 then
                return i
            end
            if resolveEntry(e) == door then
                return i
            end
        end
        return nil
    end

    function GRM.FFDLink.Add(ctrl, door)
        if not (GRM.FFDLink.IsController(ctrl) and IsValid(door)) then return false end
        ctrl.FFDLink_Doors = istable(ctrl.FFDLink_Doors) and ctrl.FFDLink_Doors or {}
        if #ctrl.FFDLink_Doors >= MAX_LINKS then return false end
        if GRM.FFDLink.FindIndex(ctrl, door) then return false end
        local class = tostring(door:GetClass() or "")
        if class == "" then return false end
        local p = door.Sliding_BasePos or door:GetPos()
        ctrl.FFDLink_Doors[#ctrl.FFDLink_Doors + 1] = { class = class, x = r1(p.x), y = r1(p.y), z = r1(p.z) }
        GRM.FFDLink.RefreshNW(ctrl)
        dupeStore(ctrl)
        return true
    end

    function GRM.FFDLink.Remove(ctrl, door)
        local i = GRM.FFDLink.FindIndex(ctrl, door)
        if not i then return false end
        table.remove(ctrl.FFDLink_Doors, i)
        GRM.FFDLink.RefreshNW(ctrl)
        dupeStore(ctrl)
        return true
    end

    -- переключатель: true — связь появилась, false — снята, nil — ошибка
    function GRM.FFDLink.Toggle(ctrl, door)
        if not (GRM.FFDLink.IsController(ctrl) and IsValid(door)) then return nil end
        if GRM.FFDLink.Add(ctrl, door) then return true end
        if GRM.FFDLink.Remove(ctrl, door) then return false end
        return nil -- лимит MAX_LINKS и странные классы
    end

    -- снять ВСЕ связи контроллера; возврат — сколько снято
    function GRM.FFDLink.Clear(ctrl)
        if not GRM.FFDLink.IsController(ctrl) then return 0 end
        local n = GRM.FFDLink.Count(ctrl)
        ctrl.FFDLink_Doors = {}
        GRM.FFDLink.RefreshNW(ctrl)
        dupeStore(ctrl)
        return n
    end

    -- убрать ЭТУ дверь из всех контроллеров карты; возврат — число затронутых
    function GRM.FFDLink.RemoveFromAll(door)
        if not IsValid(door) then return 0 end
        local touched = 0
        for class, _ in pairs(CONTROLLERS) do
            for _, ctrl in ipairs(ents.FindByClass(class)) do
                if IsValid(ctrl) and GRM.FFDLink.FindIndex(ctrl, door) then
                    GRM.FFDLink.Remove(ctrl, door)
                    touched = touched + 1
                end
            end
        end
        return touched
    end

    -- живые двери контроллера (без дублей энтити).
    function GRM.FFDLink.Resolve(ctrl, prune)
        local doors, keep, changed = {}, {}, false
        for _, e in ipairs(ctrl.FFDLink_Doors or {}) do
            local ent = resolveEntry(e)
            if ent then
                keep[#keep + 1] = e
                local dup = false
                for _, d in ipairs(doors) do if d == ent then dup = true break end end
                if not dup then doors[#doors + 1] = ent end
            else
                changed = true
            end
        end
        if prune and changed then
            ctrl.FFDLink_Doors = keep
            GRM.FFDLink.RefreshNW(ctrl)
            dupeStore(ctrl)
        end
        return doors
    end

    -- открыть/закрыть привязанные двери; возврат: сколько сработало, список.
    -- prune = false: обычная активация никогда не затирает память о дверях!
    function GRM.FFDLink.Fade(ctrl, activate)
        local doors = GRM.FFDLink.Resolve(ctrl, false)
        local n = 0
        for _, d in ipairs(doors) do
            if IsValid(d) and (d.isFadingDoor or d.isSlidingDoor) then
                if activate and d.FadeActivate then
                    d:FadeActivate()
                    n = n + 1
                elseif not activate and d.FadeDeactivate then
                    d:FadeDeactivate()
                    n = n + 1
                end
            end
        end
        return n, doors
    end

    -- ============================================================
    -- AUTORUN: ПЕРМ FFD И РАЗДВИЖНЫХ ДВЕРЕЙ + DUPLICATOR
    -- ============================================================
    local function applyFadeState(ent, active)
        if not IsValid(ent) or not ent.isFadingDoor then return end
        local reverse = ent.FFD_Reversed == true
        local shouldFade = active
        if reverse then shouldFade = not active end

        if shouldFade then
            ent:SetNotSolid(true)
            ent:SetRenderMode(RENDERMODE_TRANSCOLOR)
            ent:SetColor(Color(255, 255, 255, 40))
            ent:DrawShadow(false)
            local phys = ent:GetPhysicsObject()
            if IsValid(phys) then phys:EnableCollisions(false) end
            ent.FFD_IsFaded = true
            ent:SetNWBool("FFD_Faded", true)
        else
            ent:SetNotSolid(false)
            ent:SetRenderMode(RENDERMODE_NORMAL)
            ent:SetColor(Color(255, 255, 255, 255))
            ent:DrawShadow(true)
            local phys = ent:GetPhysicsObject()
            if IsValid(phys) then phys:EnableCollisions(true) end
            ent.FFD_IsFaded = false
            ent:SetNWBool("FFD_Faded", false)
        end
    end

local fadeOff
    local function fadeOn(ply, ent)
        if not IsValid(ent) or not ent.isFadingDoor then return end
        if ent.FFD_IsActive then return end
        ent.FFD_IsActive = true
        applyFadeState(ent, true)
        ent:EmitSound("doors/door1_move.wav", 65, 110, 0.6)
        -- fadeOff объявлена ниже — вызов идёт из таймера, поэтому нужна
        -- форвард-декларация (иначе автозакрытие двери падало с nil).
        if ent.FFD_AutoClose and tonumber(ent.FFD_CloseTime) and ent.FFD_CloseTime > 0 then
            timer.Create("FFD_AutoClose_" .. ent:EntIndex(), ent.FFD_CloseTime, 1, function()
                if IsValid(ent) and ent.isFadingDoor and ent.FFD_IsActive then
                    fadeOff(ply, ent)
                end
            end)
        end
    end

    fadeOff = function(ply, ent)
        if not IsValid(ent) or not ent.isFadingDoor then return end
        if not ent.FFD_IsActive then return end
        timer.Remove("FFD_AutoClose_" .. ent:EntIndex())
        ent.FFD_IsActive = false
        applyFadeState(ent, false)
        ent:EmitSound("doors/door_latch1.wav", 65, 100, 0.6)
    end

    local function fadeToggle(ply, ent)
        if not IsValid(ent) or not ent.isFadingDoor then return end
        if ent.FFD_IsActive then fadeOff(ply, ent) else fadeOn(ply, ent) end
    end

    if numpad and numpad.Register then
        numpad.Register("FFD_Fade_On", function(ply, ent)
            if not IsValid(ent) or not ent.isFadingDoor then return end
            if ent.FFD_Toggle then fadeToggle(ply, ent) else fadeOn(ply, ent) end
        end)
        numpad.Register("FFD_Fade_Off", function(ply, ent)
            if not IsValid(ent) or not ent.isFadingDoor then return end
            if not ent.FFD_Toggle then fadeOff(ply, ent) end
        end)
    end

    function GRM.FFD_MakeFadingDoor(ply, ent, key, reversed, toggle, autoclose, closeTime, skipDupe)
        if not IsValid(ent) then return false end
        if ent.isFadingDoor and ent.FFD_NumDown and numpad and numpad.Remove then
            numpad.Remove(ent.FFD_NumDown)
            numpad.Remove(ent.FFD_NumUp)
        end

        ent.isFadingDoor = true
        ent.FFD_Reversed = reversed == true or reversed == 1
        ent.FFD_Toggle = toggle == true or toggle == 1
        ent.FFD_AutoClose = autoclose == true or autoclose == 1
        ent.FFD_CloseTime = math.max(0.5, tonumber(closeTime) or 5)
        ent.FFD_Key = key
        ent.FFD_OwnerSID64 = IsValid(ply) and tostring((GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply)) or ply:SteamID64() or "") or tostring(ent.FFD_OwnerSID64 or "")
        ent:SetNWBool("FFD_IsDoor", true)

        if IsValid(ply) and numpad and numpad.OnDown then
            ent.FFD_NumDown = numpad.OnDown(ply, key, "FFD_Fade_On", ent)
            ent.FFD_NumUp = numpad.OnUp(ply, key, "FFD_Fade_Off", ent)
        end

        ent.FadeActivate = function() fadeOn(ply, ent) end
        ent.FadeDeactivate = function() fadeOff(ply, ent) end
        ent.FadeToggle = function() fadeToggle(ply, ent) end

        ent.FFD_IsActive = false
        applyFadeState(ent, false)

        if not skipDupe and duplicator and duplicator.StoreEntityModifier then
            duplicator.StoreEntityModifier(ent, "FFD_FadingDoor", {
                key = key,
                reversed = reversed,
                toggle = toggle,
                autoclose = autoclose,
                time = closeTime,
            })
        end

        return true
    end

    if duplicator and duplicator.RegisterEntityModifier then
        duplicator.RegisterEntityModifier("FFD_FadingDoor", function(ply, ent, data)
            if istable(data) then
                GRM.FFD_MakeFadingDoor(ply, ent, data.key, data.reversed, data.toggle, data.autoclose, data.time, true)
            end
        end)
    end

    -- Регистрация PermData Extract/Apply для prop_physics и prop_dynamic в autorun
    local function propPermExtract(ent)
        if not IsValid(ent) then return nil end
        if ent.isSlidingDoor and ent.Sliding then
            local s = ent.Sliding
            return {
                sliding = {
                    direction = tostring(s.direction or "left"),
                    distance = tonumber(s.distance) or 100,
                    speed = tonumber(s.speed) or 120,
                    smooth = tonumber(s.smooth) or 1,
                    toggle = s.toggle == true,
                    autoclose = s.autoclose == true,
                    closeTime = tonumber(s.closeTime) or 5,
                    owner = tostring(s.owner or ""),
                    soundOpen = tostring(s.soundOpen or ""),
                    soundClose = tostring(s.soundClose or ""),
                    soundMove = tostring(s.soundMove or ""),
                },
            }
        end
        if ent.isFadingDoor then
            return {
                ffd = {
                    key = tonumber(ent.FFD_Key) or 1,
                    reversed = ent.FFD_Reversed == true,
                    toggle = ent.FFD_Toggle == true,
                    autoclose = ent.FFD_AutoClose == true,
                    time = tonumber(ent.FFD_CloseTime) or 5,
                    owner = tostring(ent.FFD_OwnerSID64 or ""),
                },
            }
        end
        return nil
    end

    local function propPermApply(ent, t)
        if not (IsValid(ent) and istable(t)) then return end
        if istable(t.sliding) then
            local d = t.sliding
            local ownerPly = nil
            local want = tostring(d.owner or "")
            if want ~= "" then
                for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                    if IsValid(p) and tostring((GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(p)) or p:SteamID64() or "") == want then ownerPly = p break end
                end
            end
            if GRM.SlidingDoor and GRM.SlidingDoor.Apply then
                GRM.SlidingDoor.Apply(ownerPly, ent, {
                    direction = d.direction, distance = d.distance,
                    speed = d.speed, smooth = d.smooth,
                    toggle = d.toggle, autoclose = d.autoclose, closeTime = d.closeTime,
                    soundOpen = d.soundOpen, soundClose = d.soundClose, soundMove = d.soundMove,
                })
            end
            return
        end
        if istable(t.ffd) then
            local d = t.ffd
            local ownerPly = nil
            local want = tostring(d.owner or "")
            if want ~= "" then
                for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                    if IsValid(p) and tostring((GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(p)) or p:SteamID64() or "") == want then ownerPly = p break end
                end
            end
            GRM.FFD_MakeFadingDoor(ownerPly, ent, tonumber(d.key) or 1, d.reversed, d.toggle, d.autoclose, tonumber(d.time) or 5, true)
            ent.FFD_OwnerSID64 = want
        end
    end

    GRM.PermData = GRM.PermData or { Extract = {}, Apply = {} }
    GRM.PermData.Extract = GRM.PermData.Extract or {}
    GRM.PermData.Apply = GRM.PermData.Apply or {}
    GRM.PermData.Extract["prop_physics"] = propPermExtract
    GRM.PermData.Apply["prop_physics"]   = propPermApply
    GRM.PermData.Extract["prop_dynamic"] = propPermExtract
    GRM.PermData.Apply["prop_dynamic"]   = propPermApply

    print("[GRM FFD Link] v" .. GRM._ffdLinkVer .. ": ручные связи и персистентность дверей готовы")
end

-- ============================================================
-- CLIENT: NW-зеркало для стула FFD Link (количество + подсветка)
-- ============================================================
if CLIENT then
    function GRM.FFDLink.LinkedCount(ctrl)
        if not IsValid(ctrl) then return 0 end
        return tonumber(ctrl:GetNWInt("FFDLinkN", 0)) or 0
    end

    -- сет EntIndex'ей дверей, разрешённых этим контроллером
    function GRM.FFDLink.LinkedIndexSet(ctrl)
        local set = {}
        if not IsValid(ctrl) then return set end
        local s = tostring(ctrl:GetNWString("FFDLinkIdx", "") or "")
        for tok in string.gmatch(s, "([^,]+)") do
            local i = tonumber(tok)
            if i then set[i] = true end
        end
        return set
    end
end
