-- Boot-шим: старт подсистемы идёт через планировщик GRM.Boot (приоритеты и
-- бюджет на тик). Если планировщик почему-то не загружен, работаем по-старому.
local function grmBootStart(id, tier, fn)
    if GRM and GRM.Boot and GRM.Boot.OnMapStart then return GRM.Boot.OnMapStart(id, tier, fn) end
    return hook.Add("InitPostEntity", id, fn)
end

-- GRM Closed Customization v1.0.0 — client renderer and editors
if not CLIENT then return end

GRM = GRM or {}
GRM.Customization = GRM.Customization or {}
local C = GRM.Customization
C.Catalog = C.Catalog or {}
C.ClientLoadouts = C.ClientLoadouts or {}
C.ActiveRenderPlayers=C.ActiveRenderPlayers or setmetatable({},{__mode="k"})
C.ValidModelCache=C.ValidModelCache or{}
C.RenderCache = C.RenderCache or {}
C.ClientVersion = "1.2.0"

local UI = {
    bg = Color(12, 17, 25, 248), head = Color(22, 30, 43, 252), panel = Color(27, 37, 52, 245),
    card = Color(34, 46, 63, 245), line = Color(67, 86, 110, 210), text = Color(238, 244, 250),
    dim = Color(158, 174, 194), blue = Color(65, 145, 240), green = Color(65, 190, 120),
    red = Color(215, 75, 80), orange = Color(235, 160, 70),
}
surface.CreateFont("GRMCustom_Title", { font = "Roboto", size = 22, weight = 900, extended = true })
surface.CreateFont("GRMCustom_Head", { font = "Roboto", size = 16, weight = 800, extended = true })
surface.CreateFont("GRMCustom_Body", { font = "Roboto", size = 13, weight = 550, extended = true })
surface.CreateFont("GRMCustom_Small", { font = "Roboto", size = 11, weight = 500, extended = true })

local FEEDBACK_SOUNDS = {
    click = "buttons/button15.wav", adjust = "buttons/lightswitch2.wav",
    success = "buttons/button9.wav", error = "buttons/button10.wav", reset = "buttons/button14.wav",
}
local function feedback(kind, text, notify)
    surface.PlaySound(FEEDBACK_SOUNDS[kind] or FEEDBACK_SOUNDS.click)
    if notify and text and text ~= "" then
        notification.AddLegacy(text, kind == "error" and NOTIFY_ERROR or NOTIFY_GENERIC, 3)
    end
end

net.Receive("GRM_Custom_Ack", function()
    local ok = net.ReadBool()
    local action = net.ReadString()
    local message = net.ReadString()
    feedback(ok and "success" or "error", message, true)
    hook.Run("GRM_CustomizationAcknowledged", ok, action, message)
end)

local function deepCopy(t) return istable(t) and table.Copy(t) or {} end
local function v3(t) return Vector(tonumber(t and t.x) or 0, tonumber(t and t.y) or 0, tonumber(t and t.z) or 0) end
local function a3(t) return Angle(tonumber(t and t.p) or 0, tonumber(t and t.y) or 0, tonumber(t and t.r) or 0) end

-- Поворот угла вокруг оси (как Source-порядок: pitch→yaw→roll), но вокруг
-- ЛОКАЛЬНЫХ осей кости, чтобы Yaw (вокруг Up кости) и Roll (вокруг Forward
-- кости) давали РАЗНЫЕ вращения. GMod LocalToWorld так не умеет — он крутит
-- вокруг мировых осей и yaw/roll сливаются в одно.
local function boneLocalAngles(boneAng, offs)
    local p = math.rad(tonumber(offs and offs.p) or 0)
    local y = math.rad(tonumber(offs and offs.y) or 0)
    local r = math.rad(tonumber(offs and offs.r) or 0)
    -- базис кости
    local f, rt, up = boneAng:Forward(), boneAng:Right(), boneAng:Up()
    -- поворот вокруг Up кости (yaw)
    local cosY, sinY = math.cos(y), math.sin(y)
    local f2 = f * cosY + rt * sinY
    local rt2 = -f * sinY + rt * cosY
    -- поворот вокруг Forward (roll) — уже в новом базисе
    local cosR, sinR = math.cos(r), math.sin(r)
    local rt3 = rt2 * cosR + up * sinR
    local up3 = -rt2 * sinR + up * cosR
    -- поворот вокруг Right (pitch)
    local cosP, sinP = math.cos(p), math.sin(p)
    local f4 = f2 * cosP - up3 * sinP
    local up4 = f2 * sinP + up3 * cosP
    return f4:AngleEx(up4)
end
local function btn(parent, text, color)
    local b = vgui.Create("DButton", parent)
    b:SetText(text); b:SetFont("GRMCustom_Body"); b:SetTextColor(color_white)
    b.Paint = function(self, w, h)
        local col = color or UI.blue
        if self:IsHovered() then col = Color(math.min(255, col.r + 18), math.min(255, col.g + 18), math.min(255, col.b + 18)) end
        draw.RoundedBox(6, 0, 0, w, h, col)
    end
    return b
end
local function label(parent, text, font, color)
    local l = vgui.Create("DLabel", parent)
    l:SetText(text or ""); l:SetFont(font or "GRMCustom_Body"); l:SetTextColor(color or UI.text)
    return l
end

function C.GetClientLoadout(ply) return C.ClientLoadouts[ply] or {} end
function C.GetClientEquipped(ply, slot) return C.GetClientLoadout(ply)[slot] end
function C.GetClientItem(equipped) return equipped and C.Catalog[equipped.accessoryID] end
function C.LocalFunctionalItems(functionID)
    local out = {}
    local lp = LocalPlayer()
    for slot, equipped in pairs(IsValid(lp) and C.GetClientLoadout(lp) or {}) do
        local item = C.Catalog[equipped.accessoryID]
        if item and istable(item.functions) and item.functions[functionID] == true then
            out[#out + 1] = { slot = slot, equipped = equipped, item = item }
        end
    end
    return out
end
function C.LocalHasFunction(functionID) return #C.LocalFunctionalItems(functionID) > 0 end
function C.LocalFunctionValue(functionID, key, mode)
    local result = mode == "sum" and 0 or nil
    for _, rec in ipairs(C.LocalFunctionalItems(functionID)) do
        local value = tonumber(rec.item.functionConfig and rec.item.functionConfig[key]) or 0
        if mode == "sum" then result = result + value else result = math.max(result or 0, value) end
    end
    return result or 0
end
function C.RequestSync() net.Start("GRM_Custom_Request") net.SendToServer() end
function C.RequestEditor()
    if GRM.UI then GRM.UI.Close("inventory") end
    net.Start("GRM_Custom_Open") net.SendToServer()
end
function C.EquipInventorySlot(inventorySlot, equipmentSlot)
    net.Start("GRM_Custom_Op")
        net.WriteString("equip_inventory")
        net.WriteUInt(math.Clamp(math.floor(tonumber(inventorySlot) or 0), 0, 255), 8)
        net.WriteString(tostring(equipmentSlot or ""))
    net.SendToServer()
end

function C.UnequipInventorySlot(equipmentSlot)
    net.Start("GRM_Custom_Op")
        net.WriteString("unequip_inventory")
        net.WriteString(tostring(equipmentSlot or ""))
    net.SendToServer()
end

local function removeCached(cache)
    for _, entry in pairs(cache or {}) do if IsValid(entry.ent) then entry.ent:Remove() end end
end
local function clearPlayerCache(ply)
    removeCached(C.RenderCache[ply]);C.RenderCache[ply]=nil
end
local function trackLoadout(ply,loadout)if IsValid(ply)and istable(loadout)and next(loadout)~=nil then C.ActiveRenderPlayers[ply]=true else C.ActiveRenderPlayers[ply]=nil end end
local function validAccessoryModel(model)model=tostring(model or"");local cached=C.ValidModelCache[model];if cached~=nil then return cached end;cached=model~=""and util.IsValidModel(model)==true;C.ValidModelCache[model]=cached;return cached end

net.Receive("GRM_Custom_Catalog", function()
    C.Catalog=net.ReadTable()or{};C.ValidModelCache={}
    if GRM.Inventory and GRM.Inventory.RegisterItem then
        for _, item in pairs(C.Catalog) do
            GRM.Inventory.RegisterItem(item.itemID, {
                type = "item", name = item.name, desc = item.description,
                icon = "icon16/user_suit.png", model = item.model, weight = 0.4,
                maxStack = 1, useFunc = "grm_accessory_equip", accessoryID = item.id,
            })
        end
    end
    hook.Run("GRM_CustomizationUpdated")
end)

net.Receive("GRM_Custom_Sync", function()
    local ply = net.ReadEntity()
    net.ReadString() -- CharacterKey для диагностики/будущего кэша офлайн
    local loadout = net.ReadTable() or {}
    if not IsValid(ply) then return end
    C.ClientLoadouts[ply]=loadout;trackLoadout(ply,loadout)
    -- Не уничтожаем весь render cache при каждом Save/повторном входе.
    -- Оставляем ту же ClientsideModel и её плавное состояние; удаляем
    -- только реально снятые либо заменённые модели.
    local cache = C.RenderCache[ply]
    if cache then
        for slot, entry in pairs(cache) do
            local equipped = loadout[slot]
            local item = equipped and C.Catalog[equipped.accessoryID]
            if not equipped or (item and entry.model ~= item.model) then
                if IsValid(entry.ent) then entry.ent:Remove() end
                cache[slot] = nil
            end
        end
    end
    hook.Run("GRM_CustomizationUpdated", ply)
end)

-- Находка 179z: фонарик (F) вырублен на клиенте. 1) блокируем сам бинд
-- +flashlight (движок даже не попытается включить), 2) принудительно гасим
-- уже включённый (мог быть включён до хука/другим аддоном). Причина:
-- при включённом освещении движок уводит рендер в световой проход, где
-- аксессуары перестают отрисовываться.
hook.Add("PlayerBindPress", "GRM_Customization_NoFlashlightBind", function(ply, bind)
    if bind == "+flashlight" then return true end
end)
hook.Add("Think", "GRM_Customization_FlashlightForceOff", function()
    if GRM.Perf and not GRM.Perf.Throttle("custom.flashlight",.25)then return end
    local lp=LocalPlayer()
    if IsValid(lp) and isfunction(lp.FlashlightIsOn) and lp:FlashlightIsOn() and isfunction(lp.SetFlashlight) then lp:SetFlashlight(false) end
end)

hook.Add("EntityRemoved", "GRM_Customization_CacheCleanup", function(ent)
    if ent:IsPlayer()then clearPlayerCache(ent);C.ClientLoadouts[ent]=nil;C.ActiveRenderPlayers[ent]=nil end
end)

local function getRenderEntity(ply, slot, item, equipped)
    C.RenderCache[ply] = C.RenderCache[ply] or {}
    local cache = C.RenderCache[ply]
    local entry = cache[slot]
    if entry and (entry.model ~= item.model or not IsValid(entry.ent)) then
        if IsValid(entry.ent) then entry.ent:Remove() end
        entry = nil
    end
    if not entry then
        local ent = ClientsideModel(item.model, RENDERGROUP_BOTH)
        if not IsValid(ent) then return nil end
        ent:SetNoDraw(true)
        ent:SetSkin(math.max(0, tonumber(item.skin) or 0))
        ent:SetColor(color_white)
        ent:SetMaterial("")
        ent:SetRenderMode(RENDERMODE_NORMAL)
        ent:SetLOD(0)
        ent:DrawShadow(false)
        entry = {
            ent = ent, model = item.model, scale = -1, lastFrame = -1,
            smoothPos = v3(equipped.position), smoothAng = a3(equipped.angles),
            smoothScale = math.Clamp(tonumber(equipped.scale) or 1, 0.2, 3),
        }
        cache[slot] = entry
    end
    return entry
end

-- Основная точка отрисовки — сразу после актуального скелета игрока.
-- Нет Think/SetPos/network interpolation, поэтому аксессуар не мигает и не
-- догоняет кость на кадр позже, как это бывало в универсальных PAC-outfit.
local function drawAccessories(ply, forceEditorDraw)
    if not IsValid(ply) or not ply:Alive() or ply:IsDormant() then return end
    local lp = LocalPlayer()
    -- Находка 175: свои аксессуары от ПЕРВОГО лица не рисуем НИКОГДА.
    -- Когда камера в 1-м лице, движок не рисует модель игрока — кость
    -- всё равно анимируется, и аксессуар висел бы «в воздухе» в обзоре.
    -- Рисуем себя только когда движок реально отрисовывает модель игрока
    -- (3-е лицо / drawviewer: ShouldDrawLocalPlayer() == true) либо
    -- принудительно в редакторе (forceEditorDraw, камера-орбита).
    if IsValid(lp) and ply == lp and not forceEditorDraw and not lp:ShouldDrawLocalPlayer() then return end
    if IsValid(lp) and lp:GetPos():DistToSqr(ply:GetPos()) > 2500 * 2500 then return end
    local loadout = C.ClientLoadouts[ply]
    if not istable(loadout) then return end

    for slot,equipped in pairs(loadout)do
        local item=C.Catalog[equipped.accessoryID]
        if item and validAccessoryModel(item.model)then
            local entry=getRenderEntity(ply,slot,item,equipped);local boneName=tostring(equipped.bone or item.bone or"")
            if entry and entry.boneName~=boneName then entry.boneName=boneName;entry.boneIndex=ply:LookupBone(boneName)end
            local matrix=entry and entry.boneIndex and ply:GetBoneMatrix(entry.boneIndex)or nil
            if matrix then
                if forceEditorDraw or entry.lastFrame~=FrameNumber()then
                    if not forceEditorDraw then entry.lastFrame = FrameNumber() end
                    -- Сглаживаем только ЛОКАЛЬНУЮ настройку аксессуара.
                    -- Матрица кости остаётся точной в текущем кадре, поэтому
                    -- сглаживание редактора не создаёт PAC-подобного отставания.
                    local blend = math.Clamp(FrameTime() * 14, 0, 1)
                    entry.smoothPos = LerpVector(blend, entry.smoothPos or v3(equipped.position), v3(equipped.position))
                    entry.smoothAng = LerpAngle(blend, entry.smoothAng or a3(equipped.angles), a3(equipped.angles))
                    entry.smoothScale = Lerp(blend, entry.smoothScale or (tonumber(equipped.scale) or 1), math.Clamp(tonumber(equipped.scale) or 1, 0.2, 3))
                    if math.abs((entry.scale or -1) - entry.smoothScale) > 0.002 then
                        entry.ent:SetModelScale(entry.smoothScale, 0)
                        entry.scale = entry.smoothScale
                    end
                    local boneAng = matrix:GetAngles()
                    local pos = matrix:GetTranslation() + boneAng:Forward() * entry.smoothPos.x + boneAng:Right() * entry.smoothPos.y + boneAng:Up() * entry.smoothPos.z
                    local ang = boneLocalAngles(boneAng, entry.smoothAng)
                    entry.ent:SetRenderOrigin(pos)
                    entry.ent:SetRenderAngles(ang)
                    entry.ent:DrawModel()
                    entry.ent:SetRenderOrigin()
                    entry.ent:SetRenderAngles()
                end
            end
        end
    end
end

hook.Add("PostPlayerDraw", "GRM_Customization_DrawAccessories", function(ply)
    if C.EditorActive and ply == LocalPlayer() then return end
    drawAccessories(ply)
end)

-- На некоторых gamemode/third-person связках PostPlayerDraw не вызывается
-- для LocalPlayer даже при drawviewer=true. В редакторе делаем поздний
-- fallback после SetupBones. FrameNumber guard гарантирует, что второго
-- DrawModel в том же кадре не будет.
-- Резервный проход для НЕПРОЗРАЧНЫХ аксессуаров: при включённом фонарике (F)
-- движок переключает рендер в отдельный световой проход, и PostPlayerDraw +
-- ручной DrawModel() может не отрисовать модель (аксессуар «исчезает»).
-- PostDrawOpaqueRenderables рисуется в основном проходе независимо от
-- фонарика — дублируем туда же отрисовку с FrameNumber-guard.
-- Находка 175: раньше здесь рисовался ТОЛЬКО LocalPlayer, поэтому при
-- фонарике аксессуары ВСЕХ ОСТАЛЬНЫХ игроков исчезали. Теперь проходим по
-- всем игрокам (guard не даст второму DrawModel, если PostPlayerDraw уже
-- сработал; свои аксессуары от 1-го лица отсекает drawAccessories).
hook.Add("PostDrawOpaqueRenderables", "GRM_Customization_DrawAccessoriesOpaque", function(drawingDepth, drawingSkybox, drawing3DSkybox)
    if C.EditorActive and LocalPlayer() then return end
    if drawingDepth or drawingSkybox or drawing3DSkybox then return end
    local lp = LocalPlayer()
    if not IsValid(lp) then return end
    for ply in pairs(C.ActiveRenderPlayers)do if IsValid(ply)then drawAccessories(ply)else C.ActiveRenderPlayers[ply]=nil end end
end)

hook.Add("PostDrawTranslucentRenderables", "GRM_Customization_EditorPreviewFallback", function(drawingDepth, drawingSkybox, drawing3DSkybox)
    if not C.EditorActive or drawingDepth or drawingSkybox or drawing3DSkybox then return end
    local lp = LocalPlayer()
    if not IsValid(lp) then return end
    lp:SetupBones()
    -- Это гарантированно финальный main-view pass. Не используем общий
    -- lastFrame: depth/auxiliary passes могли отметить кадр раньше экрана.
    drawAccessories(lp, true)
end)

hook.Add("Think", "GRM_Customization_CacheMaintenance", function()
    C._nextCacheSweep = C._nextCacheSweep or 0
    if CurTime() < C._nextCacheSweep then return end
    C._nextCacheSweep = CurTime() + 5
    for ply, cache in pairs(C.RenderCache) do
        if not IsValid(ply) then removeCached(cache); C.RenderCache[ply] = nil end
    end
end)

--[[ Кадровые краски HUD функций (часы, противогаз, сумка). Создаются
     один раз при загрузке: HUDPaint = каждый кадр, Color() внутри него —
     мусорная таблица на кадр (§6.1.8). ]]
local COL_HUD_WATCH_BG, COL_HUD_WATCH_TEXT = Color(12, 17, 25, 210), Color(120, 210, 255)
local COL_HUD_GAS_BG, COL_HUD_GAS_TEXT = Color(12, 20, 24, 195), Color(115, 225, 155)
local COL_HUD_BAG_BG, COL_HUD_BAG_TEXT, COL_HUD_BAG_HINT = Color(20, 14, 8, 205), Color(255, 200, 90), Color(150, 130, 100)
-- Орбитальная камера редактора: вектор-константы пересчёта вида.
-- Пока редактор открыт CalcView крутится каждый кадр; поля движка-Vector
-- не мутируем (TraceHull держит ссылки), но литералы вынесены.
local CAM_TARGET_UP = Vector(0, 0, 42)
local CAM_HULL_MIN, CAM_HULL_MAX = Vector(-4, -4, -4), Vector(4, 4, 4)
-- углы орбиты — переиспользуемый Angle: редактор всегда один, кадр за
-- кадром поля перезаписываются перед употреблением (тот же приём, что
-- correction.z в sv_grm_handcuffs)
local CAM_ANG = Angle(0, 0, 0)
hook.Add("HUDPaint", "GRM_Customization_FunctionHUD", function()
    if C.EditorActive then return end
    if C.LocalHasFunction("watch") then
        -- os.date в HUDPaint = новая строка каждый кадр. Берём общий кэш
        -- GRM.Time (пересчёт раз в секунду на весь клиент).
        local text = (GRM.Time and GRM.Time.Clock) and GRM.Time.Clock("%H:%M:%S  •  %d.%m.%Y")
            or os.date("%H:%M:%S  •  %d.%m.%Y")
        surface.SetFont("GRMCustom_Body")
        local tw, th = surface.GetTextSize(text)
        local x, y = ScrW() - tw - 24, 72
        draw.RoundedBox(6, x - 9, y - 5, tw + 18, th + 10, COL_HUD_WATCH_BG)
        draw.SimpleText(text, "GRMCustom_Body", x, y, COL_HUD_WATCH_TEXT)
    end
    if C.LocalHasFunction("gasmask") then
        local protection = math.floor(C.LocalFunctionValue("gasmask", "gasProtection", "max") * 100 + 0.5)
        local text = "ПРОТИВОГАЗ  •  ЗАЩИТА " .. protection .. "%"
        draw.RoundedBox(5, ScrW()/2 - 105, 64, 210, 25, COL_HUD_GAS_BG)
        draw.SimpleText(text, "GRMCustom_Small", ScrW()/2, 76, COL_HUD_GAS_TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    -- Находка 178f: сумка ограбления — счётчик и выгрузка
    if C.LocalHasFunction("loot_bag") and IsValid(LocalPlayer()) then
        local cur = LocalPlayer():GetNWInt("GRM_LootBag", 0) or 0
        local maxM = C.LocalFunctionValue("loot_bag", "lootMaxMoney", "max")
        if maxM <= 0 then maxM = 100000 end
        local text = ("СУМКА ОГРАБЛЕНИЯ: %s / %s"):format(
            GRM and GRM.Format and GRM.Format(cur) or tostring(cur),
            GRM and GRM.Format and GRM.Format(maxM) or tostring(maxM))
        draw.RoundedBox(6, ScrW()/2 - 130, 96, 260, 26, COL_HUD_BAG_BG)
        draw.SimpleText(text, "GRMCustom_Small", ScrW()/2, 102, COL_HUD_BAG_TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("/bag_unload — выгрузить в кошелёк", "GRMCustom_Small", ScrW()/2, 118, COL_HUD_BAG_HINT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end)

-- ============================================================
-- ПОЛНОЭКРАННЫЙ РЕДАКТОР
-- ============================================================
local editor = {
    active = false, yaw = 155, pitch = 8, distance = 115,
    gizmoMode = "move", moveStep = 0.1, rotateStep = 1,
}
C.EditorState = editor

local function selectedAccessoryWorld()
    if not editor.active then return end
    local lp = LocalPlayer()
    local equipped = IsValid(lp) and C.ClientLoadouts[lp] and C.ClientLoadouts[lp][editor.selected] or nil
    local item = equipped and C.Catalog[equipped.accessoryID] or nil
    if not item then return end
    local boneIndex = lp:LookupBone(tostring(equipped.bone or item.bone or ""))
    if not boneIndex then return end
    local matrix = lp:GetBoneMatrix(boneIndex)
    if not matrix then return end
    local boneAng = matrix:GetAngles()
    local p3 = v3(equipped.position)
    local pos = matrix:GetTranslation() + boneAng:Forward() * p3.x + boneAng:Right() * p3.y + boneAng:Up() * p3.z
    local ang = boneLocalAngles(boneAng, a3(equipped.angles))
    return pos, boneAng, equipped, ang
end

-- Оси, их цвета и геометрия колец живут в общем модуле GRM.Gizmo:
-- держать здесь вторую копию значит однажды поправить только одну.

local function gizmoGeometry(origin)
    local dist=EyePos():Distance(origin)
    local base=math.Clamp(dist*0.055,12,34)
    local half=4
    local lp=LocalPlayer();local cache=IsValid(lp)and C.RenderCache[lp];local entry=cache and cache[editor.selected]
    if entry and IsValid(entry.ent) then local mn,mx=entry.ent:GetRenderBounds();half=math.max(half,(mx-mn):Length()*(entry.smoothScale or 1)*0.28)end
    return math.Clamp(math.max(base,half+4),12,48),math.Clamp(math.max(base*0.78,half+2),10,42)
end

--[[ Выбор оси перемещения — общий модуль GRM.Gizmo.

     Свой перебор здесь был недетерминированным (pairs по таблице с
     ключами x/y/z): при равном расстоянии до курсора выигрывала
     случайная ось. Отсюда жалоба «беру один, он вращает другой». ]]
local function pickGizmoAxis(mx, my)
    local origin, boneAng = selectedAccessoryWorld()
    if not origin or not GRM.Gizmo then return end
    local axisLength = gizmoGeometry(origin)
    return GRM.Gizmo.Pick("move", origin, boneAng, axisLength, mx, my)
end

--[[ Выбор кольца вращения — общий модуль GRM.Gizmo.

     Прошлый код проверял кольцо ЦЕЛИКОМ, вместе с дальней от камеры
     половиной. Кольцо, повёрнутое ребром, вырождается в отрезок, и
     его обратная сторона перехватывала клики у соседней оси. В модуле
     отбирается только видимая половина. ]]
local function pickRotationAxis(mx, my)
    local origin, boneAng = selectedAccessoryWorld()
    if not origin or not GRM.Gizmo then return end
    local _, radius = gizmoGeometry(origin)
    return GRM.Gizmo.Pick("rotate", origin, boneAng, radius, mx, my)
end

local function pickActiveGizmo(mx, my)
    if editor.gizmoMode == "rotate" then return pickRotationAxis(mx, my) end
    return pickGizmoAxis(mx, my)
end

hook.Add("PostDrawTranslucentRenderables", "GRM_Customization_TransformGizmo", function(drawingDepth, drawingSkybox, drawing3DSkybox)
    if not editor.active or drawingDepth or drawingSkybox or drawing3DSkybox then return end
    local origin, boneAng = selectedAccessoryWorld()
    if not origin or not GRM.Gizmo then return end
    local move, radius = gizmoGeometry(origin)
    local size = editor.gizmoMode == "rotate" and radius or move
    -- Подсветку пересчитываем каждый кадр, пока ось не схвачена.
    if not editor.gizmoAxis then
        local mx, my = gui.MousePos()
        editor.gizmoHover = GRM.Gizmo.Pick(editor.gizmoMode, origin, boneAng, size, mx, my)
    end
    GRM.Gizmo.Draw(editor.gizmoMode, origin, boneAng, size, editor.gizmoHover, editor.gizmoAxis)
end)

hook.Add("HUDPaint", "GRM_Customization_GizmoLabel", function()
    if not editor.active or not GRM.Gizmo then return end
    local axis = editor.gizmoAxis or editor.gizmoHover
    if not axis then return end
    local mx, my = gui.MousePos()
    GRM.Gizmo.DrawLabel(editor.gizmoMode, axis, mx, my)
end)

local function closeEditor(restore)
    if not editor.active then return end
    if restore and IsValid(LocalPlayer())then C.ClientLoadouts[LocalPlayer()]=deepCopy(editor.backup);trackLoadout(LocalPlayer(),C.ClientLoadouts[LocalPlayer()])end
    editor.active = false
    C.EditorActive = false
    net.Start("GRM_Custom_Op") net.WriteString("close") net.SendToServer()
    if IsValid(editor.frame) then editor.frame:Remove() end
    editor.frame = nil
    hook.Run("GRM_CustomizationUpdated", LocalPlayer())
end

hook.Add("CalcView", "GRM_Customization_OrbitCamera", function(ply, origin, angles, fov)
    if not editor.active or ply ~= LocalPlayer() then return end
    local target = ply:GetPos() + CAM_TARGET_UP
    CAM_ANG.p, CAM_ANG.y, CAM_ANG.r = editor.pitch, editor.yaw, 0
    local ang = CAM_ANG
    local wanted = target - ang:Forward() * editor.distance
    local tr = util.TraceHull({ start = target, endpos = wanted, filter = ply, mins = CAM_HULL_MIN, maxs = CAM_HULL_MAX, mask = MASK_SOLID })
    return { origin = tr.HitPos, angles = (target - tr.HitPos):Angle(), fov = 48, drawviewer = true }
end)
hook.Add("ShouldDrawLocalPlayer", "GRM_Customization_DrawLocalPlayer", function()
    if editor.active then return true end
end)
hook.Add("HUDShouldDraw", "GRM_Customization_HideHUD", function()
    if editor.active then return false end
end)

local function slider(parent, text, min, max, value, y, callback)
    local s = vgui.Create("DNumSlider", parent)
    s:SetPos(10, y); s:SetSize(parent:GetWide() - 20, 32); s:SetText(text)
    s:SetMin(min); s:SetMax(max); s:SetDecimals(2); s:SetValue(value or 0)
    if IsValid(s.Label) then s.Label:SetFont("GRMCustom_Small"); s.Label:SetTextColor(UI.text) end
    s.OnValueChanged = function(_, val) callback(tonumber(val) or 0) end
    return s
end

local function openEditor(catalog, loadout)
    if GRM.UI then GRM.UI.Close("inventory") end
    C.Catalog = catalog or C.Catalog
    local lp = LocalPlayer()
    -- Авторитетный GRM_Custom_Sync приходит отдельным пакетом перед Open.
    -- Если loadout не передан, сохраняем уже синхронизированные slots.
    loadout = istable(loadout) and loadout or C.ClientLoadouts[lp] or {}
    C.ClientLoadouts[lp]=deepCopy(loadout);trackLoadout(lp,C.ClientLoadouts[lp]);C.ValidModelCache={}
    -- Не уничтожаем уже видимую ClientsideModel при входе: getRenderEntity
    -- сам заменит её, только если реально изменилась модель каталога.
    editor.active = true; C.EditorActive = true; editor.backup = deepCopy(loadout); editor.selected = C.SlotOrder[1]
    -- Сразу выбираем реально занятый слот, а не всегда «Голову»: иначе
    -- аксессуар руки/туловища визуально есть, но правая панель показывала
    -- пустой первый слот и создавала впечатление, что предмет исчез.
    for _, slotID in ipairs(C.SlotOrder or {}) do
        if C.ClientLoadouts[lp][slotID] then editor.selected = slotID break end
    end

    local frame = vgui.Create("DFrame")
    GRM.UI.Track("customization", frame)
    frame:SetSize(ScrW(), ScrH()); frame:SetPos(0, 0); frame:SetTitle(""); frame:ShowCloseButton(false); frame:MakePopup()
    editor.frame = frame
    frame.Paint = function(_, w, h)
        draw.RoundedBox(0, 0, 0, w, 54, UI.head)
        draw.SimpleText("GRM  /  КАСТОМИЗАЦИЯ ПЕРСОНАЖА", "GRMCustom_Title", 22, 20, UI.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("РЕДАКТОР ПОЛОЖЕНИЯ АКСЕССУАРОВ  //  СИНХРОНИЗИРОВАНО", "GRMCustom_Small", 22, 40, UI.green or Color(90,220,150), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("ЛКМ: камера  •  стрелки/кольца: позиция  •  колесо: масштаб", "GRMCustom_Small", w/2, 27, UI.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    local left = vgui.Create("DPanel", frame); left:SetPos(16, 70); left:SetSize(270, ScrH()-90)
    left.Paint = function(_, w, h) draw.RoundedBox(8,0,0,w,h,UI.panel); surface.SetDrawColor(UI.line or Color(55,117,151,190)); surface.DrawOutlinedRect(0,0,w,h,1) end
    local right = vgui.Create("DPanel", frame); right:SetPos(ScrW()-356,70); right:SetSize(340,ScrH()-90)
    right.Paint = function(_, w,h) draw.RoundedBox(8,0,0,w,h,UI.panel); surface.SetDrawColor(UI.line or Color(55,117,151,190)); surface.DrawOutlinedRect(0,0,w,h,1) end
    local view = vgui.Create("DPanel", frame); view:SetPos(300,70); view:SetSize(ScrW()-672,ScrH()-90); view:SetCursor("sizeall")
    view.Paint = function() end
    view.OnMousePressed = function(self,key)
        if key~=MOUSE_LEFT then return end
        local mx,my=gui.MousePos()
        local axis,sdx,sdy=pickActiveGizmo(mx,my)
        if axis then
            local _,_,equipped=selectedAccessoryWorld()
            editor.gizmoAxis=axis; editor.gizmoDX=sdx; editor.gizmoDY=sdy
            editor.gizmoStartX=mx; editor.gizmoStartY=my
            if editor.gizmoMode == "rotate" then
                --[[ Соответствие «ось → поле угла» лежит в общем модуле.
                     Здесь было x→p, y→y, z→r: сдвинуто на позицию,
                     поэтому кольцо Z крутило roll (вокруг X). Хранилище
                     аксессуаров зовёт yaw полем "y". ]]
                local angleKey = GRM.Gizmo.AngleKey(axis, "y")
                editor.gizmoStartValue=equipped and tonumber((equipped.angles or {})[angleKey]) or 0
            else
                editor.gizmoStartValue=equipped and tonumber((equipped.position or {})[axis]) or 0
            end
        else
            self.drag=true; self.lx,self.ly=mx,my
        end
        self:MouseCapture(true)
    end
    view.OnMouseReleased = function(self,key)
        if key==MOUSE_LEFT then
            local adjusted=editor.gizmoAxis~=nil
            self.drag=false; editor.gizmoAxis=nil; self:MouseCapture(false)
            if adjusted then feedback("adjust","Положение изменено в предпросмотре. Нажмите «Сохранить положение».",true) end
        end
    end
    view.OnCursorMoved = function(self,x,y)
        local mx,my=gui.MousePos()
        if editor.gizmoAxis then
            local _,_,equipped=selectedAccessoryWorld()
            if equipped then
                local projected=(mx-editor.gizmoStartX)*(editor.gizmoDX or 0)+(my-editor.gizmoStartY)*(editor.gizmoDY or 0)
                if editor.gizmoMode == "rotate" then
                    equipped.angles=equipped.angles or {p=0,y=0,r=0}
                    local angleKey=GRM.Gizmo.AngleKey(editor.gizmoAxis, "y")
                    local value=math.NormalizeAngle((editor.gizmoStartValue or 0)+projected*(editor.rotateStep or 1))
                    equipped.angles[angleKey]=value
                    local sliderPanel=editor.angleSliders and editor.angleSliders[editor.gizmoAxis]
                    if IsValid(sliderPanel) then sliderPanel:SetValue(value) end
                else
                    equipped.position=equipped.position or {x=0,y=0,z=0}
                    local value=math.Clamp((editor.gizmoStartValue or 0)+projected*(editor.moveStep or 0.1),-48,48)
                    equipped.position[editor.gizmoAxis]=value
                    local sliderPanel=editor.axisSliders and editor.axisSliders[editor.gizmoAxis]
                    if IsValid(sliderPanel) then sliderPanel:SetValue(value) end
                end
            end
            return
        end
        if not self.drag then return end
        editor.yaw=editor.yaw-(mx-self.lx)*0.35; editor.pitch=math.Clamp(editor.pitch+(my-self.ly)*0.25,-25,50); self.lx,self.ly=mx,my
    end
    view.OnMouseWheeled = function(_,delta) editor.distance=math.Clamp(editor.distance-delta*8,65,210); return true end

    local controls = {}
    local function rebuildRight()
        for _, pnl in ipairs(controls) do if IsValid(pnl) then pnl:Remove() end end
        controls = {}
        local equipped = C.ClientLoadouts[lp][editor.selected]
        local slotDef = C.Slots[editor.selected]
        local head = label(right, slotDef.name, "GRMCustom_Head", UI.text); head:SetPos(12,10); head:SetSize(310,24); controls[#controls+1]=head
        if not equipped then
            local empty=label(right,"Слот пуст. Наденьте подходящий предмет через инвентарь.","GRMCustom_Body",UI.dim); empty:SetPos(12,46); empty:SetSize(310,60); empty:SetWrap(true); controls[#controls+1]=empty
            return
        end
        local item=C.Catalog[equipped.accessoryID]
        local itemLbl=label(right,item and item.name or equipped.accessoryID,"GRMCustom_Body",UI.orange); itemLbl:SetPos(12,38); itemLbl:SetSize(310,22); controls[#controls+1]=itemLbl
        local bone=vgui.Create("DComboBox",right); bone:SetPos(12,66); bone:SetSize(316,28); bone:SetValue(equipped.bone or "кость")
        for _,name in ipairs(slotDef.bones or {}) do bone:AddChoice(name,name) end
        bone.OnSelect=function(_,_,_,data) equipped.bone=data; feedback("adjust","Кость изменена — сохраните положение",true) end; controls[#controls+1]=bone
        equipped.position=equipped.position or {x=0,y=0,z=0}; equipped.angles=equipped.angles or {p=0,y=0,r=0}
        local moveMode=btn(right,"ПЕРЕМЕЩЕНИЕ",UI.blue); moveMode:SetPos(12,100); moveMode:SetSize(153,28); controls[#controls+1]=moveMode
        local rotateMode=btn(right,"ВРАЩЕНИЕ",UI.orange); rotateMode:SetPos(175,100); rotateMode:SetSize(153,28); controls[#controls+1]=rotateMode
        moveMode.Paint=function(self,w,h) draw.RoundedBox(6,0,0,w,h,editor.gizmoMode=="move" and UI.blue or UI.card) end
        rotateMode.Paint=function(self,w,h) draw.RoundedBox(6,0,0,w,h,editor.gizmoMode=="rotate" and UI.orange or UI.card) end
        moveMode.DoClick=function() editor.gizmoMode="move"; feedback("click"); rebuildRight() end
        rotateMode.DoClick=function() editor.gizmoMode="rotate"; feedback("click"); rebuildRight() end

        local y=136
        editor.axisSliders={}; editor.angleSliders={}
        local function add(text,min,max,val,cb) local s=slider(right,text,min,max,val,y,cb); controls[#controls+1]=s; y=y+34; return s end
        editor.axisSliders.x=add("Позиция X",-48,48,equipped.position.x,function(v) equipped.position.x=v end)
        editor.axisSliders.y=add("Позиция Y",-48,48,equipped.position.y,function(v) equipped.position.y=v end)
        editor.axisSliders.z=add("Позиция Z",-48,48,equipped.position.z,function(v) equipped.position.z=v end)
        --[[ Слайдеры углов ПОДПИСАНЫ ОСЬЮ, а не именем поля.

             Раньше здесь было angleSliders.x → Pitch, .y → Yaw,
             .z → Roll, то есть то же сдвинутое соответствие, что и у
             гизмо. После починки маппинга (ось Z крутит yaw, X крутит
             roll) старая привязка обновляла бы ЧУЖОЙ слайдер: тянешь
             кольцо Z, а шевелится строка Pitch.

             Ключ таблицы — ось гизмо, подпись — что реально вращается
             вокруг неё. ]]
        editor.angleSliders.x=add("Вокруг X (Roll)",-180,180,equipped.angles.r,function(v) equipped.angles.r=v end)
        editor.angleSliders.y=add("Вокруг Y (Pitch)",-180,180,equipped.angles.p,function(v) equipped.angles.p=v end)
        editor.angleSliders.z=add("Вокруг Z (Yaw)",-180,180,equipped.angles.y,function(v) equipped.angles.y=v end)
        add("Масштаб",0.2,3,equipped.scale or 1,function(v) equipped.scale=v end)

        local fine=vgui.Create("DPanel",right); fine:SetPos(12,y+2); fine:SetSize(316,94); fine.Paint=function(_,w,h) draw.RoundedBox(6,0,0,w,h,UI.card) end; controls[#controls+1]=fine
        local rotating=editor.gizmoMode=="rotate"
        local fineLabel=label(fine,rotating and "ТОЧНОЕ ВРАЩЕНИЕ" or "ТОЧНОЕ ПЕРЕМЕЩЕНИЕ","GRMCustom_Small",UI.text); fineLabel:SetPos(8,4); fineLabel:SetSize(205,20)
        local currentStep=rotating and editor.rotateStep or editor.moveStep
        local step=vgui.Create("DComboBox",fine); step:SetPos(218,4); step:SetSize(90,22); step:SetValue(tostring(currentStep))
        local stepValues=rotating and {0.25,0.5,1,2.5,5} or {0.05,0.1,0.25,0.5,1}
        for _,v in ipairs(stepValues) do step:AddChoice(tostring(v),v) end
        step.OnSelect=function(_,_,_,data)
            if rotating then editor.rotateStep=tonumber(data) or 1 else editor.moveStep=tonumber(data) or 0.1 end
        end
        local axisColors={x=Color(205,70,70),y=Color(60,175,95),z=Color(65,125,220)}
        -- Подписи кнопок точной подстройки: в режиме вращения это ОСЬ,
        -- вокруг которой крутим, а не имя поля угла.
        local axisLabels={x="X",y="Y",z="Z"}
        local function nudge(axis,direction)
            local sliderPanel=rotating and editor.angleSliders[axis] or editor.axisSliders[axis]
            if not IsValid(sliderPanel) then return end
            local value=sliderPanel:GetValue()+direction*(rotating and editor.rotateStep or editor.moveStep)
            if rotating then value=math.NormalizeAngle(value) else value=math.Clamp(value,-48,48) end
            sliderPanel:SetValue(value)
        end
        for row,axis in ipairs({"x","y","z"}) do
            local axisLabel=label(fine,axisLabels[axis],"GRMCustom_Head",axisColors[axis]); axisLabel:SetPos(9,24+(row-1)*22); axisLabel:SetSize(28,20)
            for col,direction in ipairs({-1,1}) do
                local arrow=btn(fine,direction<0 and "◀" or "▶",axisColors[axis]); arrow:SetPos(42+(col-1)*132,25+(row-1)*22); arrow:SetSize(122,19)
                arrow.DoClick=function() nudge(axis,direction); feedback("adjust") end
                arrow.Think=function(self)
                    if not self:IsDown() then self._repeatAt=nil return end
                    self._repeatAt=self._repeatAt or (CurTime()+0.32)
                    if CurTime()>=self._repeatAt then self._repeatAt=CurTime()+0.055; nudge(axis,direction) end
                end
            end
        end
        y=y+102
        local save=btn(right,"СОХРАНИТЬ ПОЛОЖЕНИЕ",UI.green); save:SetPos(12,y+8); save:SetSize(316,36); controls[#controls+1]=save
        save.DoClick=function() feedback("click"); net.Start("GRM_Custom_Op") net.WriteString("save_transform") net.WriteString(editor.selected) net.WriteTable(equipped) net.SendToServer() end
        local reset=btn(right,"Сбросить к стандартному",UI.blue); reset:SetPos(12,y+50); reset:SetSize(316,32); controls[#controls+1]=reset
        reset.DoClick=function()
            if item then equipped.bone=item.bone; equipped.position=deepCopy(item.position); equipped.angles=deepCopy(item.angles); equipped.scale=item.scale or 1; feedback("reset","Предпросмотр сброшен. Нажмите «Сохранить положение».",true); rebuildRight() end
        end
        local remove=btn(right,"Снять в инвентарь",UI.red); remove:SetPos(12,y+88); remove:SetSize(316,32); controls[#controls+1]=remove
        remove.DoClick=function() feedback("click"); net.Start("GRM_Custom_Op") net.WriteString("unequip") net.WriteString(editor.selected) net.SendToServer() end
    end

    local title=label(left,"СЛОТЫ ЭКИПИРОВКИ","GRMCustom_Head",UI.text); title:SetPos(12,12); title:SetSize(240,24)
    for i,slot in ipairs(C.SlotOrder or {}) do
        local def=C.Slots[slot]; local b=btn(left,def.name,UI.card); b:SetPos(12,46+(i-1)*48); b:SetSize(246,40)
        b.Paint=function(self,w,h)
            local col=editor.selected==slot and UI.blue or (self:IsHovered() and Color(52,68,88) or UI.card)
            draw.RoundedBox(6,0,0,w,h,col)
        end
        b.DoClick=function() editor.selected=slot; rebuildRight() end
        b.Think=function(self)
            local eq=C.ClientLoadouts[lp][slot]; self:SetText(def.name .. (eq and ("  •  "..tostring((C.Catalog[eq.accessoryID] or {}).name or eq.accessoryID)) or "  •  пусто"))
        end
    end
    local freeze=btn(left,"ЗАМОРОЗИТЬ В Т-ПОЗЕ",UI.blue); freeze:SetPos(12,left:GetTall()-168); freeze:SetSize(246,34); freeze.DoClick=function() net.Start("GRM_Custom_Op"); net.WriteString("pose_freeze"); net.SendToServer() end
    local unfreeze=btn(left,"РАЗМОРОЗИТЬ ПЕРСОНАЖА",UI.orange or UI.yellow); unfreeze:SetPos(12,left:GetTall()-128); unfreeze:SetSize(246,34); unfreeze.DoClick=function() net.Start("GRM_Custom_Op"); net.WriteString("pose_unfreeze"); net.SendToServer() end
    local accept=btn(left,"ГОТОВО",UI.green); accept:SetPos(12,left:GetTall()-92); accept:SetSize(246,34)
    accept.DoClick=function()
        feedback("click")
        net.Start("GRM_Custom_Op") net.WriteString("save_all_close") net.WriteTable(C.ClientLoadouts[lp] or {}) net.SendToServer()
        editor.active=false; C.EditorActive=false
        if IsValid(editor.frame) then editor.frame:Remove() end
        editor.frame=nil
    end
    local cancel=btn(left,"ОТМЕНА",UI.red); cancel:SetPos(12,left:GetTall()-50); cancel:SetSize(246,34); cancel.DoClick=function() feedback("click"); closeEditor(true) end
    frame.OnRemove=function() if editor.active then closeEditor(true) end end
    rebuildRight()
end

net.Receive("GRM_Custom_Open", function()
    -- Loadout приходит отдельным GRM_Custom_Sync непосредственно перед Open.
    -- Здесь читается только каталог — исчезновение equipment slots из-за
    -- второй таблицы архитектурно исключено.
    local catalog = net.ReadTable() or {}
    openEditor(catalog)
end)
net.Receive("GRM_Custom_Close", function()
    editor.active = false
    C.EditorActive = false
    if IsValid(editor.frame) then editor.frame:Remove() end
    editor.frame = nil
end)
timer.Create("GRM_Customization_EditorPing", 2, 0, function()
    if editor.active then net.Start("GRM_Custom_Op") net.WriteString("ping") net.SendToServer() end
end)

-- ============================================================
-- АДМИНСКИЙ КАТАЛОГ
-- ============================================================
-- Находка 179c: повторные открытия (сервер шлёт AdminOpen после каждого
-- сохранения) НЕ должны плодить новые окна/панели — старое окно
-- переиспользуется, иначе DScrollPanel из удалённого окна остаётся в
-- раскладке → «Tried to use a NULL Panel!» (dscrollpanel.lua:111).
local adminFrame = nil

local function openAdmin(catalog)
    C.Catalog = catalog or C.Catalog
    if IsValid(adminFrame) then
        -- уже открыто: просто обновляем каталог и список
        adminFrame:InvalidateLayout()
        return
    end
    local f=vgui.Create("DFrame"); GRM.UI.Track("accessories_admin",f); f:SetSize(1120,720); f:Center(); f:MakePopup(); f:SetTitle("GRM — Каталог аксессуаров")
    adminFrame = f
    f.OnRemove = function() if adminFrame == f then adminFrame = nil end end
    local list=vgui.Create("DScrollPanel",f); list:SetPos(10,34); list:SetSize(390,640)
    local form=vgui.Create("DPanel",f); form:SetPos(410,34); form:SetSize(700,640); form.Paint=function(_,w,h) draw.RoundedBox(7,0,0,w,h,UI.panel) end
    local fields={}; local selected=""
    local function entry(name,y,w)
        local l=label(form,name,"GRMCustom_Small",UI.dim); l:SetPos(12,y); l:SetSize(150,20)
        local e=vgui.Create("DTextEntry",form); e:SetPos(160,y); e:SetSize(w or 360,24); fields[name]=e; return e
    end
    entry("ID",14,250); entry("Название",44,360); entry("Категория",74,360); entry("Модель",104,500); entry("Описание",134,500); entry("Цена",164,180)
    local slotCombo=vgui.Create("DComboBox",form); slotCombo:SetPos(160,194); slotCombo:SetSize(250,26)
    local sl=label(form,"Слот","GRMCustom_Small",UI.dim); sl:SetPos(12,194); sl:SetSize(140,20)
    for _,slot in ipairs(C.SlotOrder or {}) do slotCombo:AddChoice(C.Slots[slot].name,slot) end
    local boneCombo=vgui.Create("DComboBox",form); boneCombo:SetPos(160,226); boneCombo:SetSize(360,26)
    local bl=label(form,"Кость","GRMCustom_Small",UI.dim); bl:SetPos(12,226); bl:SetSize(140,20)
    local function fillBones(slot,bone)
        boneCombo:Clear(); for _,v in ipairs((C.Slots[slot] or {}).bones or {}) do boneCombo:AddChoice(v,v) end; boneCombo:SetValue(bone or ((C.Slots[slot] or {}).bones or {})[1] or "")
    end
    slotCombo.OnSelect=function(_,_,_,slot) fillBones(slot) end
    local nums={}; local labels={"Pos X","Pos Y","Pos Z","Pitch","Yaw","Roll","Scale"}
    for i,name in ipairs(labels) do
        local x=12+((i-1)%4)*165; local y=270+math.floor((i-1)/4)*58
        local l=label(form,name,"GRMCustom_Small",UI.dim); l:SetPos(x,y); l:SetSize(150,18)
        local n=vgui.Create("DNumberWang",form); n:SetPos(x,y+20); n:SetSize(150,26); n:SetMin(i==7 and 0.2 or -180); n:SetMax(i==7 and 3 or 180); n:SetDecimals(2); nums[i]=n
    end
    local preview=vgui.Create("DModelPanel",form); preview:SetPos(450,360); preview:SetSize(230,220); preview:SetFOV(35); preview.LayoutEntity=function() end
    fields["Модель"].OnChange=function(self) local m=self:GetValue(); if util.IsValidModel(m) then preview:SetModel(m) end end

    -- Находка 179b: аккуратная сетка функциональных чекбоксов — 2 колонки × 5
    -- строк (шаг 24px), не наезжают друг на друга и не уходят за форму.
    local funcTitle=label(form,"ФУНКЦИОНАЛЬНОЕ ОБОРУДОВАНИЕ","GRMCustom_Head",UI.text); funcTitle:SetPos(12,382); funcTitle:SetSize(410,22)
    local funcChecks={}
    local funcCols={
        {"gasmask","backpack","radio","watch","armor"},
        {"artificial_eye","night_vision","neuro_link","prosthesis","loot_bag"},
    }
    for ci,col in ipairs(funcCols) do
        for ri,functionID in ipairs(col) do
            local def=C.FunctionTypes[functionID] or {name=functionID}
            local x = ci == 1 and 12 or 230
            local y = 406 + (ri-1)*24
            local check=vgui.Create("DCheckBoxLabel",form); check:SetPos(x,y); check:SetSize(200,22)
            check:SetText(def.name); check:SetFont("GRMCustom_Body"); check:SetTextColor(UI.text); funcChecks[functionID]=check
        end
    end
    -- Числовые параметры функций — 2 ряда по 3/2 поля (y 536 и 580)
    local functionNum={}
    local function functionNumber(labelText,key,x,y,default,min,max)
        local l=label(form,labelText,"GRMCustom_Small",UI.dim); l:SetPos(x,y); l:SetSize(140,18)
        local n=vgui.Create("DNumberWang",form); n:SetPos(x,y+19); n:SetSize(140,25); n:SetDecimals(2); n:SetMin(min); n:SetMax(max); n:SetValue(default); functionNum[key]=n
    end
    functionNumber("Защита газа 0..0.98","gasProtection",12,536,0.85,0,0.98)
    functionNumber("Рюкзак +кг","backpackCapacity",160,536,20,0,100)
    functionNumber("Снижение урона","armorReduction",300,536,0.2,0,0.75)
    -- находка 178f: параметры сумки ограбления
    functionNumber("Сумка: макс. GRM","lootMaxMoney",12,580,100000,1000,1000000)
    functionNumber("Сумка: за подход","lootPerUse",160,580,25000,1000,100000)

    local function setForm(id,item)
        selected=id or ""; item=item or {}; fields.ID:SetText(id or ""); fields["Название"]:SetText(item.name or ""); fields["Категория"]:SetText(item.category or ""); fields["Модель"]:SetText(item.model or ""); fields["Описание"]:SetText(item.description or ""); fields["Цена"]:SetText(tostring(item.price or 0))
        slotCombo:SetValue((C.Slots[item.slot] or {}).name or "Голова"); slotCombo._slot=item.slot or "head"; fillBones(item.slot or "head",item.bone)
        local p=item.position or {}; local a=item.angles or {}; local vals={p.x or 0,p.y or 0,p.z or 0,a.p or 0,a.y or 0,a.r or 0,item.scale or 1}; for i,v in ipairs(vals) do nums[i]:SetValue(v) end
        for functionID,check in pairs(funcChecks) do check:SetValue(item.functions and item.functions[functionID] == true) end
        local cfg=item.functionConfig or {}; functionNum.gasProtection:SetValue(cfg.gasProtection or 0.85); functionNum.backpackCapacity:SetValue(cfg.backpackCapacity or 20); functionNum.armorReduction:SetValue(cfg.armorReduction or 0.2)
        functionNum.lootMaxMoney:SetValue(cfg.lootMaxMoney or 100000); functionNum.lootPerUse:SetValue(cfg.lootPerUse or 25000)
        if util.IsValidModel(item.model or "") then preview:SetModel(item.model) end
    end
    slotCombo.OnSelect=function(_,_,_,slot) slotCombo._slot=slot; fillBones(slot) end
    for id,item in SortedPairs(C.Catalog) do
        local b=btn(list,(item.category or "Прочее").."  /  "..item.name,UI.card); b:Dock(TOP); b:SetTall(34); b:DockMargin(0,0,0,4); b.DoClick=function() setForm(id,item) end
    end
    local fresh=btn(list,"+ НОВЫЙ АКСЕССУАР",UI.green); fresh:Dock(TOP); fresh:SetTall(36); fresh.DoClick=function() setForm("",{}) end
    local save=btn(form,"СОХРАНИТЬ В КАТАЛОГ",UI.green); save:SetPos(12,590); save:SetSize(330,36)
    save.DoClick=function()
        feedback("click")
        local id=fields.ID:GetValue(); local bone=boneCombo:GetOptionData(boneCombo:GetSelectedID()) or boneCombo:GetValue()
        local functions={}; for functionID,check in pairs(funcChecks) do functions[functionID]=check:GetChecked() == true end
        local payload={
            name=fields["Название"]:GetValue(), category=fields["Категория"]:GetValue(), model=fields["Модель"]:GetValue(),
            description=fields["Описание"]:GetValue(), price=tonumber(fields["Цена"]:GetValue()) or 0,
            slot=slotCombo._slot or "head", bone=bone,
            position={x=nums[1]:GetValue(),y=nums[2]:GetValue(),z=nums[3]:GetValue()},
            angles={p=nums[4]:GetValue(),y=nums[5]:GetValue(),r=nums[6]:GetValue()}, scale=nums[7]:GetValue(),
            functions=functions,
            functionConfig={gasProtection=functionNum.gasProtection:GetValue(),backpackCapacity=functionNum.backpackCapacity:GetValue(),armorReduction=functionNum.armorReduction:GetValue(),lootMaxMoney=functionNum.lootMaxMoney:GetValue(),lootPerUse=functionNum.lootPerUse:GetValue()},
        }
        net.Start("GRM_Custom_AdminOp") net.WriteString("save") net.WriteString(id) net.WriteTable(payload) net.SendToServer()
    end
    local del=btn(form,"УДАЛИТЬ",UI.red); del:SetPos(352,590); del:SetSize(160,36); del.DoClick=function() if selected~="" then feedback("click"); net.Start("GRM_Custom_AdminOp") net.WriteString("delete") net.WriteString(selected) net.SendToServer() end end
    setForm("",{})
end
net.Receive("GRM_Custom_AdminOpen", function() openAdmin(net.ReadTable() or {}) end)

grmBootStart("GRM_Customization_Request", "late", function() timer.Simple(2, C.RequestSync) end)
print("[GRM Customization] client v" .. tostring(C.Version or "1.0.0") .. " loaded")
