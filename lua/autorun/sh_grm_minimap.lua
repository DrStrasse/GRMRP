-- GRM GPS points / districts v0.2
if SERVER then AddCSLuaFile() end
GRM = GRM or {}
GRM.Minimap = GRM.Minimap or {}
local MM = GRM.Minimap
MM.File = "grm_minimap_" .. string.lower(game.GetMap() or "unknown") .. ".json"
MM.GPSArrivalRadius=120
function MM.HasArrived(current,target,radius,maxVertical)
 if not current or not target then return false end
 radius=math.Clamp(tonumber(radius)or MM.GPSArrivalRadius,64,256);maxVertical=math.Clamp(tonumber(maxVertical)or 180,64,512)
 local dx=(tonumber(current.x)or 0)-(tonumber(target.x)or 0);local dy=(tonumber(current.y)or 0)-(tonumber(target.y)or 0);local dz=math.abs((tonumber(current.z)or 0)-(tonumber(target.z)or 0))
 return dx*dx+dy*dy<=radius*radius and dz<=maxVertical
end

if SERVER then
    util.AddNetworkString("GRM_Minimap_Data")
    util.AddNetworkString("GRM_Minimap_Open")
    util.AddNetworkString("GRM_Minimap_Action")
    MM.Data = MM.Data or { districts = {}, points = {}, overview = nil }

    local function save()
        -- Временные (temp) точки не пишутся на диск — это разовые маркеры
        -- (например, смерть спец-юнита), они живут только в памяти сессии.
        local persisted = { districts = MM.Data.districts, overview = MM.Data.overview, points = {} }
        for _, p in ipairs(MM.Data.points or {}) do
            if not p.temp then persisted.points[#persisted.points + 1] = p end
        end
        file.Write(MM.File, util.TableToJSON(persisted, true))
    end
    local function load()
        if file.Exists(MM.File, "DATA") then
            local ok, d = pcall(util.JSONToTable, file.Read(MM.File, "DATA") or "", false, true)
            if ok and istable(d) then MM.Data = d end
        end
        MM.Data.districts = istable(MM.Data.districts) and MM.Data.districts or {}
        MM.Data.points = istable(MM.Data.points) and MM.Data.points or {}
        MM.Data.overview = istable(MM.Data.overview) and MM.Data.overview or nil
    end
    local function pos(t) return { x = t.x, y = t.y, z = t.z } end
    local sendNow
    --[[ Карта рассылается всем при любом изменении точки, а во время захвата
         точки изменения идут потоком. Рассылку всем коалесцируем: игрок и не
         заметит четверти секунды, зато сеть не пилит пакетами. ]]
    local function send(ply)
        if not IsValid(ply) and GRM.Perf and GRM.Perf.Coalesce then
            return GRM.Perf.Coalesce("grm_minimap_send_all", 0.25, function() sendNow() end)
        end
        return sendNow(ply)
    end

    sendNow = function(ply)
        -- Чистим истёкшие временные маркеры и не отправляем их клиентам
        local now = CurTime()
        for i = #(MM.Data.points or {}), 1, -1 do
            local p = MM.Data.points[i]
            if p and p.temp and (tonumber(p.expires) or 0) <= now then
                table.remove(MM.Data.points, i)
            end
        end
        -- Снимок GPS уходит потоком: точки, зоны и захваты — это большая
        -- таблица, а рассылка шла всем одним пакетом (микрофриз у всех).
        if GRM.Net and GRM.Net.Stream then
            GRM.Net.Stream("GRM_Minimap_Data", MM.Data, IsValid(ply) and ply or nil,
                { chunk = 8192, interval = 0.05 })
        else
            net.Start("GRM_Minimap_Data") net.WriteTable(MM.Data)
            if IsValid(ply) then net.Send(ply) else net.Broadcast() end
        end
    end
    local function nextID(prefix) return prefix .. "_" .. os.time() .. "_" .. math.random(100, 999) end
    function MM.AddPoint(ply, name, pointPos, radius)
        MM.Data.points[#MM.Data.points + 1] = { id = nextID("point"), name = string.sub(string.Trim(name or "GPS-точка"), 1, 48), pos = { x = pointPos.x, y = pointPos.y, z = pointPos.z }, radius = math.Clamp(tonumber(radius) or 180, 100, 2000), capture = 0, capturing = "", owner = "", allowedFactions = {} }
        save(); send(); return true
    end
    -- Временный маркер: живёт duration секунд, не сохраняется на диск.
    -- Используется для событий (смерть спец-юнита) и рассылается точечно.
    -- Точечная отправка данных minimap конкретному игроку (для адресных маркеров)
    function MM.SendTo(ply)
        if IsValid(ply) then send(ply) end
    end

    --[[ Истёкшие временные метки раньше убирались ТОЛЬКО при следующей
         отправке карты: если после события карту никто не запрашивал, метка
         оставалась и на сервере, и на экранах. Теперь сторож раз в 5 секунд
         вычищает просроченное и рассылает обновление — но только когда
         реально что-то удалил. ]]
    timer.Create("GRM_Minimap_TempSweep", 5, 0, function()
        local points = MM.Data and MM.Data.points
        if not istable(points) or #points == 0 then return end
        local now, epochNow = CurTime(), os.time()
        local removed = 0
        for i = #points, 1, -1 do
            local p = points[i]
            if p and p.temp then
                local expired = (tonumber(p.expiresEpoch) and tonumber(p.expiresEpoch) <= epochNow)
                    or (not p.expiresEpoch and (tonumber(p.expires) or 0) <= now)
                if expired then
                    table.remove(points, i)
                    removed = removed + 1
                end
            end
        end
        if removed > 0 then send(nil) end
    end)
    function MM.AddTempPoint(name, pointPos, duration)
        local p = {
            id = nextID("temp"), name = string.sub(string.Trim(name or "Метка"), 1, 64),
            pos = { x = pointPos.x, y = pointPos.y, z = pointPos.z },
            radius = 0, capture = 0, capturing = "", owner = "", allowedFactions = {},
            -- ВАЖНО: срок жизни считаем в ЕДИНОЙ шкале os.time().
            -- Раньше писался серверный CurTime, а клиент сравнивал его со
            -- СВОИМ CurTime (время с момента коннекта) — у только что зашедшего
            -- игрока метка «не истекала» и висела часами. Поле expires
            -- оставлено для совместимости с серверной чисткой.
            temp = true,
            expires = CurTime() + (tonumber(duration) or 120),
            expiresEpoch = os.time() + math.max(5, math.floor(tonumber(duration) or 120)),
        }
        MM.Data.points[#MM.Data.points + 1] = p
        return p.id
    end
    -- Находка 180e: принудительное удаление временных маркеров по имени
    -- (маркер цели ограбления должен исчезать при завершении ивента,
    -- а не жить до expires). Рассылает обновление всем.
    function MM.RemoveTempPoint(name)
        name = string.Trim(tostring(name or ""))
        if name == "" then return false end
        local removed = false
        for i = #(MM.Data.points or {}), 1, -1 do
            local p = MM.Data.points[i]
            if p and p.temp and string.Trim(tostring(p.name or "")) == name then
                table.remove(MM.Data.points, i)
                removed = true
            end
        end
        if removed then send() end
        return removed
    end
    function MM.AddDistrict(ply, name, center, radius)
        MM.Data.districts[#MM.Data.districts + 1] = { id = nextID("district"), name = string.sub(string.Trim(name or "Район"), 1, 48), center = { x = center.x, y = center.y, z = center.z }, radius = math.Clamp(tonumber(radius) or 500, 100, 10000), color = { r = 70, g = 150, b = 240 }, polygon = {}, owner = "" }
        save(); send(); return true
    end
    function MM.SetOverview(point, height)
        MM.Data.overview = { x = point.x, y = point.y, z = point.z, height = math.Clamp(tonumber(height) or 4096, 500, 20000) }
        save(); send(); return true
    end
    function MM.AddDistrictVertex(id, point)
        for _, district in ipairs(MM.Data.districts or {}) do
            if tostring(district.id) == tostring(id) then
                district.polygon = istable(district.polygon) and district.polygon or {}
                district.polygon[#district.polygon + 1] = { x = point.x, y = point.y, z = point.z }
                save(); send(); return true
            end
        end
        return false
    end
    function MM.CloseNearestDistrict(point)
        local nearest, dist
        for _, district in ipairs(MM.Data.districts or {}) do
            local center = district.center or {}
            local d = Vector(center.x or 0, center.y or 0, point.z or 0):DistToSqr(point)
            if not dist or d < dist then nearest, dist = district, d end
        end
        if nearest then nearest.polygonClosed = true; save(); send(); return true end
        return false
    end
    load()

    local function factionOf(ply)
        if not IsValid(ply) then return "" end
        for name, faction in pairs(Factions or {}) do
            if GRM.Identity and GRM.Identity.FactionMember and GRM.Identity.FactionMember(faction, ply) then return tostring(name) end
        end
        return ""
    end

    local function insideDistrict(point, district)
        local poly = district.polygon
        if istable(poly) and #poly >= 3 and district.polygonClosed then
            local inside = false
            for i = 1, #poly do
                local a, b = poly[i], poly[i % #poly + 1]
                if ((a.y > point.y) ~= (b.y > point.y)) and point.x < (b.x - a.x) * (point.y - a.y) / math.max(0.0001, b.y - a.y) + a.x then inside = not inside end
            end
            return inside
        end
        local c = district.center or {}
        return Vector(c.x or 0, c.y or 0, point.z or 0):DistToSqr(point) <= (tonumber(district.radius) or 500)^2
    end

    net.Receive("GRM_Minimap_Open", function(_, ply)
        if IsValid(ply) and ply:IsSuperAdmin() then send(ply) net.Start("GRM_Minimap_Open") net.Send(ply) end
    end)
    net.Receive("GRM_Minimap_Action", function(_, ply)
        if not IsValid(ply) or not ply:IsSuperAdmin() then return end
        local action = net.ReadString()
        if action == "add_district" then
            local name = string.sub(string.Trim(net.ReadString() or "Район"), 1, 48)
            local radius = math.Clamp(net.ReadUInt(16), 100, 10000)
            MM.Data.districts[#MM.Data.districts + 1] = { id = nextID("district"), name = name ~= "" and name or "Район", center = pos(ply:GetPos()), radius = radius, color = { r = 70, g = 150, b = 240 } }
            save(); send()
        elseif action == "add_point" or action == "add_point_at" then
            local name = string.sub(string.Trim(net.ReadString() or "GPS-точка"), 1, 48)
            local radius = math.Clamp(net.ReadUInt(16), 100, 2000)
            local hit
            if action == "add_point_at" then
                hit = Vector(net.ReadFloat(), net.ReadFloat(), net.ReadFloat())
            else
                local tr = ply:GetEyeTrace()
                hit = (tr and tr.HitPos) or ply:GetPos()
            end
            MM.Data.points[#MM.Data.points + 1] = { id = nextID("point"), name = name ~= "" and name or "GPS-точка", pos = pos(hit), radius = radius, capture = 0, capturing = "", owner = "", allowedFactions = {} }
            save(); send()
        elseif action == "rename_point" then
            local id, newName = net.ReadString(), string.sub(string.Trim(net.ReadString() or "GPS-точка"), 1, 64)
            for _, point in ipairs(MM.Data.points or {}) do if tostring(point.id) == id then point.name = newName ~= "" and newName or point.name end end
            save(); send()
        elseif action == "set_point_access" then
            local id, incoming = net.ReadString(), net.ReadTable() or {}
            for _, point in ipairs(MM.Data.points or {}) do
                if tostring(point.id) == id then
                    point.allowedFactions = {}
                    for name, enabled in pairs(incoming) do if isstring(name) and enabled == true then point.allowedFactions[name] = true end end
                end
            end
            save(); send()
        elseif action == "delete_district" or action == "delete_point" then
            local id = net.ReadString()
            local list = action == "delete_district" and MM.Data.districts or MM.Data.points
            for i = #list, 1, -1 do if tostring(list[i].id) == id then table.remove(list, i) end end
            save(); send()
        elseif action == "save" then save(); send(ply)
        elseif action == "load" then load(); send()
        end
    end)
    hook.Add("PlayerInitialSpawn", "GRM_Minimap_Sync", function(ply) timer.Simple(3, function() if IsValid(ply) then send(ply) end end) end)
    concommand.Add("grm_minimap_admin", function(ply) if IsValid(ply) and ply:IsSuperAdmin() then send(ply) net.Start("GRM_Minimap_Open") net.Send(ply) end end)
    hook.Add("PlayerSay", "GRM_Minimap_AdminChat", function(ply, text)
        if IsValid(ply) and ply:IsSuperAdmin() and string.lower(string.Trim(text or "")) == "/grm_minimap_admin" then
            send(ply)
            net.Start("GRM_Minimap_Open") net.Send(ply)
            return ""
        end
    end)
else
    local data = { districts = {}, points = {} }
    MM.ClientData = function() return data end
    local personal = {}
    local rebuildAdmin
    local function applyMapData(t)
        if istable(t) then data = t end
        MM._data = data
        if rebuildAdmin then rebuildAdmin() end
    end
    local MUI = { bg = Color(10, 15, 23, 253), head = Color(19, 28, 41), card = Color(24, 35, 51), card2 = Color(29, 43, 61), line = Color(55, 75, 99), text = Color(235, 242, 250), dim = Color(150, 169, 190), blue = Color(67, 145, 240), green = Color(65, 195, 125), red = Color(215, 75, 84), orange = Color(235, 164, 70) }
    surface.CreateFont("GRMMM_Title", { font = "Roboto", size = 21, weight = 900, extended = true })
    surface.CreateFont("GRMMM_Body", { font = "Roboto", size = 13, weight = 600, extended = true })
    surface.CreateFont("GRMMM_Small", { font = "Roboto", size = 11, weight = 500, extended = true })
    -- Compatibility aliases for clients with an older cached GPS panel.
    surface.CreateFont("GRMChar_Small", { font = "Roboto", size = 11, weight = 500, extended = true })
    surface.CreateFont("GRMChar_Normal", { font = "Roboto", size = 13, weight = 600, extended = true })
    local function styleButton(b, color)
        b:SetFont("GRMMM_Body") b:SetTextColor(MUI.text)
        b.Paint = function(self, w, h) local c = color or MUI.card2; if self:IsHovered() then c = Color(math.min(c.r + 18, 255), math.min(c.g + 18, 255), math.min(c.b + 18, 255)) end draw.RoundedBox(6, 0, 0, w, h, c) end
        return b
    end
    local frame
    --[[ БАЗИС КАМЕРЫ СНИМКА КАРТЫ — ОБЪЯВЛЕН ЗДЕСЬ НАМЕРЕННО.
         Значения задаёт renderMapSnapshot (ниже), а читает mapPos (выше
         по файлу) — чтобы маркеры игроков считались тем же базисом, что
         и сама картинка. Пока `local` стоял только рядом с
         renderMapSnapshot, mapPos видела глобальный nil, всегда падала в
         запасную ветку по границам мира и рисовала метки со сдвигом
         относительно карты. ]]
    local mapRenderCenter, mapRenderSpan
    local function worldBounds()
        local w = game.GetWorld()
        if not IsValid(w) then return Vector(-4096, -4096, -4096), Vector(4096, 4096, 4096) end
        local a, b = w:GetModelBounds()
        return Vector(a.x, a.y, a.z), Vector(b.x, b.y, b.z)
    end
    local function mapPos(v, x, y, size)
        local mn, mx = worldBounds()
        if mapRenderCenter and mapRenderSpan then
            -- Используем тот же базис камеры, что и RenderView. Это убирает
            -- ручные инверсии X/Y и гарантирует совпадение игрока с картой.
            local viewAng = Angle(90, 0, 0)
            local delta = v - mapRenderCenter
            local sx = delta:Dot(viewAng:Right()) / mapRenderSpan
            local sy = -delta:Dot(viewAng:Up()) / mapRenderSpan
            -- Текстура повернута на 180°, поэтому маркеры инвертируются
            -- тем же преобразованием.
            return x + size * 0.5 - sx * size, y + size * 0.5 - sy * size
        end
        local worldX = math.Clamp((v.x - mn.x) / math.max(1, mx.x - mn.x), 0, 1)
        local worldY = math.Clamp((v.y - mn.y) / math.max(1, mx.y - mn.y), 0, 1)
        return x + worldY * size, y + worldX * size
    end
    local function districtAt(v)
        for _, d in ipairs(data.districts or {}) do
            local poly = d.polygon
            local inside = false
            if istable(poly) and #poly >= 3 and d.polygonClosed then
                for i = 1, #poly do
                    local a, b = poly[i], poly[i % #poly + 1]
                    if ((a.y > v.y) ~= (b.y > v.y)) and v.x < (b.x - a.x) * (v.y - a.y) / math.max(0.0001, b.y - a.y) + a.x then inside = not inside end
                end
            else
                local c = d.center or {}
                inside = Vector(c.x or 0, c.y or 0, v.z):DistToSqr(v) <= (tonumber(d.radius) or 500)^2
            end
            if inside then return d end
        end
    end
    local function send(action, extra)
        net.Start("GRM_Minimap_Action") net.WriteString(action) if extra then extra() end net.SendToServer()
    end
    local mapRT = GetRenderTarget("GRM_GRM_Minimap_" .. string.lower(game.GetMap() or "map"), 512, 512, false)
    local mapMat = CreateMaterial("GRM_GRM_Minimap_Mat_" .. string.lower(game.GetMap() or "map"), "UnlitGeneric", {
        ["$basetexture"] = mapRT:GetName(), ["$vertexalpha"] = 1, ["$vertexcolor"] = 1,
    })
    local nextMapRender = 0
    local mapSnapshotReady = false
    -- mapRenderCenter / mapRenderSpan объявлены выше — рядом с mapPos,
    -- которая их читает. Здесь они только заполняются.
    local function renderMapSnapshot()
        if mapSnapshotReady and CurTime() < nextMapRender then return end
        -- Снимок создаётся один раз при загрузке карты. Больше не
        -- смешиваем текущую сцену/комнату с картографическим слоем.
        nextMapRender = math.huge
        mapSnapshotReady = true
        local mn, mx = worldBounds()
        local span = math.max(mx.x - mn.x, mx.y - mn.y)
        -- Камера ниже: меньше «дальнего» слоя и больше читаемых деталей
        -- Не используем mx.z напрямую: у карт часто есть skybox/служебный
        -- верхний слой, из-за которого камера улетает над городом.
        -- Ищем реальную верхнюю поверхность карты трассировками вниз.
        local surfaceZ = mn.z
        local samples = {
            Vector((mn.x + mx.x) * 0.5, (mn.y + mx.y) * 0.5, mx.z + 8192),
            Vector(mn.x + span * 0.25, mn.y + span * 0.25, mx.z + 8192),
            Vector(mx.x - span * 0.25, mx.y + span * 0.25, mx.z + 8192),
            Vector(mn.x + span * 0.25, mx.y - span * 0.25, mx.z + 8192),
            Vector(mx.x - span * 0.25, mx.y - span * 0.25, mx.z + 8192),
        }
        for _, sample in ipairs(samples) do
            local tr = util.TraceLine({ start = sample, endpos = Vector(sample.x, sample.y, mn.z - 8192), mask = MASK_SOLID_BRUSHONLY })
            if tr.Hit then surfaceZ = math.max(surfaceZ, tr.HitPos.z) end
        end
        local overview = data.overview
        local cameraHeight = overview and tonumber(overview.height) or 50
        local center = overview and Vector(overview.x, overview.y, overview.z + cameraHeight)
            or Vector((mn.x + mx.x) * 0.5, (mn.y + mx.y) * 0.5, surfaceZ + cameraHeight)
        mapRenderCenter = center
        mapRenderSpan = span
        render.PushRenderTarget(mapRT)
        render.Clear(7, 12, 19, 255, true, true)
        render.RenderView({
            origin = center,
            angles = Angle(90, 0, 0),
            x = 0, y = 0, w = 512, h = 512,
            -- Перспективная top-down камера над всей картой: это надёжнее
            -- поддерживается RenderView разных версий GMod, чем ortho-поле.
            fov = 90,
            znear = 1, zfar = math.max(8192, span * 3),
            drawskybox = false, drawmonitors = false,
            drawhud = false, drawviewmodel = false, dopostprocess = false,
        })
        render.PopRenderTarget()
    end
    net.Receive("GRM_Minimap_Data", function() applyMapData(net.ReadTable() or data) end)
    if GRM.Net and GRM.Net.Receive then
        GRM.Net.Receive("GRM_Minimap_Data", applyMapData)
    end
    net.Receive("GRM_Minimap_Open", function()
        if IsValid(frame) then frame:Remove() end
        frame = vgui.Create("DFrame") frame:SetSize(980, 720) frame:Center() frame:MakePopup() frame:SetTitle("") frame:ShowCloseButton(false) frame:SetDeleteOnClose(true)
        frame.Paint = function(_, w, h) draw.RoundedBox(10, 0, 0, w, h, MUI.bg); draw.RoundedBoxEx(10, 0, 0, w, 64, MUI.head, true, true, false, false); draw.SimpleText("GRM  /  GPS", "GRMMM_Small", 22, 18, MUI.blue, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER); draw.SimpleText("GPS-точки и навигация", "GRMMM_Title", 22, 43, MUI.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER) end
        local close = styleButton(vgui.Create("DButton", frame), MUI.red) close:SetPos(936, 16) close:SetSize(30, 30) close:SetText("×") close.DoClick = function() frame:Close() end
        local name = vgui.Create("DTextEntry", frame) name:SetPos(22, 82) name:SetSize(370, 34) name:SetFont("GRMMM_Body") name:SetPlaceholderText("Название района или точки") name.Paint = function(self, w, h) draw.RoundedBox(6, 0, 0, w, h, MUI.card2); self:DrawTextEntryText(MUI.text, MUI.blue, MUI.text) end
        local addP = styleButton(vgui.Create("DButton", frame), MUI.orange) addP:SetPos(534, 82) addP:SetSize(420, 34) addP:SetText("+  ДОБАВИТЬ GPS-ТОЧКУ В МЕСТЕ ПРИЦЕЛА") addP.DoClick = function() send("add_point", function() net.WriteString(name:GetValue()); net.WriteUInt(180, 16) end) end
        local sc = vgui.Create("DScrollPanel", frame) sc:SetPos(22, 132) sc:SetSize(932, 550)
        local function editAccess(point)
            local w = vgui.Create("DFrame") w:SetSize(420, 520) w:Center() w:MakePopup() w:SetTitle("Доступ к точке: " .. tostring(point.name))
            local selected = table.Copy(point.allowedFactions or {})
            local list = vgui.Create("DScrollPanel", w) list:Dock(FILL) list:DockMargin(10, 10, 10, 48)
            for factionName in SortedPairs(FactionsData or {}) do
                local c = vgui.Create("DCheckBoxLabel", list) c:Dock(TOP) c:SetTall(30) c:SetText(tostring(factionName)) c:SetValue(selected[factionName] == true)
                c.OnChange = function(_, value) selected[factionName] = value == true end
            end
            local saveAccess = vgui.Create("DButton", w) saveAccess:Dock(BOTTOM) saveAccess:SetTall(34) saveAccess:SetText("Сохранить доступ")
            saveAccess.DoClick = function() send("set_point_access", function() net.WriteString(point.id); net.WriteTable(selected) end) w:Close() end
        end
        rebuildAdmin = function()
            if not IsValid(sc) or not IsValid(frame) then return end
            sc:Clear()
            local title = vgui.Create("DLabel", sc) title:Dock(TOP) title:SetTall(34) title:SetFont("GRMMM_Body") title:SetTextColor(MUI.blue) title:SetText("СОХРАНЕННЫЕ GPS-ТОЧКИ")
            local pt = vgui.Create("DLabel", sc) pt:Dock(TOP) pt:SetTall(40) pt:SetFont("GRMMM_Body") pt:SetTextColor(MUI.orange) pt:SetText("GPS-ТОЧКИ")
            for _, p in ipairs(data.points or {}) do
                local row = vgui.Create("DPanel", sc) row:Dock(TOP) row:SetTall(48) row:DockMargin(0, 0, 0, 5) row.Paint = function(_, w, h) draw.RoundedBox(7, 0, 0, w, h, MUI.card) end
                local l = vgui.Create("DLabel", row) l:Dock(FILL) l:DockMargin(14, 0, 0, 0) l:SetFont("GRMMM_Small") l:SetTextColor(MUI.text) l:SetText(tostring(p.name) .. "   •   GPS-метка   •   " .. tostring(p.id))
                local rename = styleButton(vgui.Create("DButton", row), MUI.blue) rename:Dock(RIGHT) rename:DockMargin(5, 7, 0, 7) rename:SetWide(110) rename:SetText("Подписать") rename.DoClick = function()
                    Derma_StringRequest("Название GPS-точки", "Подпись, которую увидят игроки:", tostring(p.name or "GPS-точка"), function(value) send("rename_point", function() net.WriteString(p.id); net.WriteString(value or "") end) end)
                end
                local b = styleButton(vgui.Create("DButton", row), MUI.red) b:Dock(RIGHT) b:DockMargin(5, 7, 5, 7) b:SetWide(110) b:SetText("Удалить") b.DoClick = function() send("delete_point", function() net.WriteString(p.id) end) end
            end
        end
        timer.Simple(0, rebuildAdmin)
    end)
    local gpsTarget
    local reachedTemp={}
    local arrivalSince,nextArrivalCheck=nil,0
    local function gpsPoint(id)
        for _,point in ipairs(data.points or{})do if tostring(point.id)==tostring(id)then return point end end
        for _,point in ipairs(personal)do if tostring(point.id)==tostring(id)then return point end end
    end
    function MM.ClearGPS()gpsTarget=nil;arrivalSince=nil end
    function MM.SetGPSTarget(id) gpsTarget=id;arrivalSince=nil;if id then reachedTemp[tostring(id)]=nil end end
    function MM.GetGPSTarget() return gpsTarget end
    function MM.OfficialPoints() return data.points or {} end
    function MM.PersonalPoints() return personal end
    function MM.AddPersonal(name, pos)
        name=string.sub(string.Trim(tostring(name or "Моя метка")),1,48)
        local p={id="me_"..os.time().."_"..math.random(100,999),name=name,pos={x=pos.x,y=pos.y,z=pos.z or 0},personal=true}
        personal[#personal+1]=p
        return p
    end
    function MM.RemovePersonal(id)
        for i=#personal,1,-1 do if tostring(personal[i].id)==tostring(id) then table.remove(personal,i) end end
    end
    local COL_GPS_CHAT = Color(255, 210, 75) -- цвет чат-строки «вы прибыл» — не на кадр
    hook.Add("Think","GRM_GPS_AutoArrival",function()
        if not gpsTarget then arrivalSince=nil return end;local now=CurTime();if now<nextArrivalCheck then return end;nextArrivalCheck=now+.15
        local lp=LocalPlayer();if not IsValid(lp)then return end;local point=gpsPoint(gpsTarget);if not point then MM.ClearGPS()return end
        if MM.HasArrived(lp:GetPos(),point.pos,point.arrivalRadius or MM.GPSArrivalRadius,180)then
            arrivalSince=arrivalSince or now
            if now-arrivalSince>=.45 then local name=tostring(point.name or"место назначения");if point.temp then reachedTemp[tostring(point.id)]=true end;MM.ClearGPS();notification.AddLegacy("Вы достигли места назначения.",NOTIFY_GENERIC,5);surface.PlaySound("buttons/button15.wav");chat.AddText(COL_GPS_CHAT,"[GPS] ",color_white,"Вы достигли места назначения: "..name)end
        else arrivalSince=nil end
    end)
    local function openGPS()
        if IsValid(frame) then frame:Close() end
        frame = vgui.Create("DFrame") frame:SetSize(520, 500) frame:Center() frame:MakePopup() frame:SetTitle("GRM — GPS и точки")
        local list = vgui.Create("DScrollPanel", frame) list:SetPos(12, 36) list:SetSize(496, 440)
        for _, p in ipairs(data.points or {}) do
            local b = vgui.Create("DButton", list) b:Dock(TOP) b:SetTall(36) b:DockMargin(0, 0, 0, 5)
            b:SetText(tostring(p.name) .. "  •  GPS-метка")
            b.DoClick = function() gpsTarget=p.id;arrivalSince=nil;reachedTemp[tostring(p.id)]=nil;frame:Close() end
        end
        local clear = vgui.Create("DButton", frame) clear:SetPos(12, 470) clear:SetSize(496, 24) clear:SetText("Сбросить GPS") clear.DoClick = function() MM.ClearGPS();frame:Close() end
    end
    concommand.Add("grm_minimap_admin", function() if IsValid(LocalPlayer()) and LocalPlayer():IsSuperAdmin() then net.Start("GRM_Minimap_Open") net.SendToServer() end end)
    concommand.Add("grm_gps", openGPS)
    hook.Add("PlayerSayTransform", "GRM_Minimap_GPSCommand", function(ply, pack)
        if ply ~= LocalPlayer() then return end
        local text = string.lower(string.Trim(pack and pack[1] or ""))
        if text == "/gps" then pack[1] = "" openGPS() return true end
    end)

    -- Кружок на экране всегда: в кадре — на точке мира, за кадром — на краю экрана.
    -- Стрелку не рисуем: по ней нельзя понять, куда идти через карту.
    local function projectWorldCircle(pos)
        local sw, sh = ScrW(), ScrH()
        local pad = 36
        local scr = pos:ToScreen()
        local x, y = tonumber(scr.x) or (sw / 2), tonumber(scr.y) or (sh / 2)
        local on = (scr.visible ~= false) and x > pad and x < sw - pad and y > pad and y < sh - pad
        if on then return x, y, true end
        local cx, cy = sw * 0.5, sh * 0.5
        local dx, dy = x - cx, y - cy
        if scr.visible == false then dx, dy = -dx, -dy end
        if math.abs(dx) < 0.001 and math.abs(dy) < 0.001 then dx = 1 end
        local sx = (cx - pad) / math.max(0.001, math.abs(dx))
        local sy = (cy - pad) / math.max(0.001, math.abs(dy))
        local t = math.min(sx, sy)
        return cx + dx * t, cy + dy * t, false
    end

    --[[ Цвета маркеров — один раз на файл, а не на кадр (§6.1.8).
         Маркеры рисуются в HUDPaint для КАЖДОЙ временной точки: на карте
         с десятком меток это был десяток мусорных таблиц за кадр. ]]
    local COL_MARKER_OUTLINE = Color(8, 14, 23, 235)
    local COL_GPS_ACTIVE = Color(255, 215, 70)
    local COL_GPS_TEMP = Color(255, 90, 70)
    -- Кружки рисуются последовательно и не вложенные — на кадр хватает одного
    -- переиспользуемого вектора вместо аллокации в HUDPaint (§6.1.8):
    -- поля пишем, сам Vector создаётся один раз при загрузке.
    local GPS_POINT_V = Vector(0, 0, 0)

    local function paintGpsCircle(point, col, rMin, rMax)
        local lp = LocalPlayer()
        if not (IsValid(lp) and istable(point) and istable(point.pos)) then return end
        local target = GPS_POINT_V
        target.x, target.y = point.pos.x, point.pos.y
        target.z = point.pos.z or lp:GetPos().z
        local distance = math.floor(lp:GetPos():Distance(target))
        local x, y = projectWorldCircle(target)
        local radius = math.Clamp((rMin or 10) + distance / 450, rMin or 10, rMax or 22)
        local pulse = math.sin(CurTime() * 4) * 3
        surface.DrawCircle(x, y, radius + pulse, col.r, col.g, col.b, 255)
        surface.DrawCircle(x, y, math.max(3, radius - 4), 8, 14, 23, 240)
        surface.DrawCircle(x, y, 2, col.r, col.g, col.b, 255)
        local sw = ScrW()
        local textX = math.Clamp(x + radius + 12, 12, sw - 12)
        local align = textX > sw - 180 and TEXT_ALIGN_RIGHT or TEXT_ALIGN_LEFT
        draw.SimpleTextOutlined(tostring(point.name or "GPS"), "GRMMM_Body", textX, y - 10, color_white, align, TEXT_ALIGN_CENTER, 2, COL_MARKER_OUTLINE)
        draw.SimpleTextOutlined(distance .. " юн.", "GRMMM_Small", textX, y + 10, col, align, TEXT_ALIGN_CENTER, 2, COL_MARKER_OUTLINE)
    end

    hook.Add("HUDPaint", "GRM_GPS_WorldMarkerHUD", function()
        local lp = LocalPlayer()
        if not IsValid(lp) or not gpsTarget then return end
        local point = gpsPoint(gpsTarget)
        if not point then return end
        paintGpsCircle(point, COL_GPS_ACTIVE, 9, 20)
    end)

    hook.Add("HUDPaint", "GRM_GPS_TempMarkers", function()
        local lp = LocalPlayer()
        if not IsValid(lp) then return end
        local now = CurTime()
        for _, point in ipairs(data.points or {}) do
            local epoch = tonumber(point and point.expiresEpoch)
            local alive = epoch and (epoch > os.time()) or ((tonumber(point and point.expires) or 0) > now)
            if point and point.temp and not reachedTemp[tostring(point.id)] and alive then
                if gpsTarget and tostring(point.id) == tostring(gpsTarget) then
                    -- активная цель уже нарисована жёлтым кружком
                else
                    paintGpsCircle(point, COL_GPS_TEMP, 10, 22)
                end
            end
        end
    end)

    hook.Add("HUDPaint", "GRM_Minimap_HUD", function()
        -- Render-карта отключена: остаётся только GPS/точки/районы и их меню.
        if false then
        local lp = LocalPlayer() if not IsValid(lp) then return end
        renderMapSnapshot()
        local size, x, y = 280, ScrW() - 300, 18
        draw.RoundedBox(8, x - 4, y - 4, size + 8, size + 8, Color(10, 16, 24, 235))
        surface.SetMaterial(mapMat) surface.SetDrawColor(255, 255, 255, 185) surface.DrawTexturedRectRotated(x + size / 2, y + size / 2, size, size, 180)
        surface.SetDrawColor(45, 65, 86, 255) surface.DrawOutlinedRect(x, y, size, size, 2)
        for i = 1, 7 do surface.SetDrawColor(30, 48, 66, 180) surface.DrawLine(x + i * size / 8, y, x + i * size / 8, y + size) surface.DrawLine(x, y + i * size / 8, x + size, y + i * size / 8) end
        local mn, mx = worldBounds()
        local cellW, cellH = (mx.x - mn.x) / 8, (mx.y - mn.y) / 8
        for gx = 0, 7 do for gy = 0, 7 do
            local worldCell = Vector(mn.x + (gx + 0.5) * cellW, mn.y + (gy + 0.5) * cellH, 0)
            local d = districtAt(worldCell)
            if d then
                local col = d.owner ~= "" and Color(80, 190, 120, 48) or Color(70, 140, 220, 34)
                surface.SetDrawColor(col)
                surface.DrawRect(x + gx * size / 8 + 1, y + (7 - gy) * size / 8 + 1, size / 8 - 2, size / 8 - 2)
            end
        end end
        local worldSpan = math.max(mx.x - mn.x, mx.y - mn.y)
        for _, d in ipairs(data.districts or {}) do
            local dx, dy = mapPos(Vector(d.center.x, d.center.y, 0), x, y, size)
            local dr = math.Clamp((tonumber(d.radius) or 500) / worldSpan * size, 6, size / 2)
            surface.SetDrawColor(80, 160, 245, 120)
            if istable(d.polygon) and #d.polygon >= 3 and d.polygonClosed then
                for i = 1, #d.polygon do
                    local a, b = d.polygon[i], d.polygon[i % #d.polygon + 1]
                    local ax, ay = mapPos(Vector(a.x, a.y, 0), x, y, size)
                    local bx, by = mapPos(Vector(b.x, b.y, 0), x, y, size)
                    surface.DrawLine(ax, ay, bx, by)
                end
            else surface.DrawCircle(dx, dy, dr, 80, 160, 245, 120) end
            draw.SimpleText(tostring(d.name) .. (d.owner ~= "" and " • " .. d.owner or ""), "DermaDefaultBold", dx, dy, Color(100, 200, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        for _, p in ipairs(data.points or {}) do
            local px, py = mapPos(Vector(p.pos.x, p.pos.y, 0), x, y, size)
            local col = p.owner ~= "" and Color(100, 220, 140, 255) or Color(240, 180, 70, 255)
            local pr = math.Clamp((tonumber(p.radius) or 180) / worldSpan * size, 4, 34)
            surface.SetDrawColor(col) surface.DrawCircle(px, py, pr, col.r, col.g, col.b, 80)
            surface.SetDrawColor(col) surface.DrawRect(px - 3, py - 3, 6, 6)
            draw.SimpleText(tostring(p.name), "DermaDefault", px, py - 8, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
        end
        local px, py = mapPos(lp:GetPos(), x, y, size)
        surface.SetDrawColor(90, 255, 150, 255) surface.DrawRect(px - 4, py - 4, 8, 8)
        if gpsTarget then
            for _, p in ipairs(data.points or {}) do
                if p.id == gpsTarget then
                    local tx, ty = mapPos(Vector(p.pos.x, p.pos.y, 0), x, y, size)
                    surface.SetDrawColor(255, 220, 90, 220) surface.DrawLine(px, py, tx, ty)
                    draw.SimpleText("GPS " .. math.floor(lp:GetPos():Distance(Vector(p.pos.x, p.pos.y, p.pos.z or lp:GetPos().z))), "DermaDefaultBold", x + size / 2, y + size + 25, Color(255, 220, 90), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
                    break
                end
            end
        end
        if gpsTarget then
            for _, p in ipairs(data.points or {}) do
                if p.id == gpsTarget then
                    local screen = Vector(p.pos.x, p.pos.y, p.pos.z or lp:GetPos().z):ToScreen()
                    local target = Vector(p.pos.x, p.pos.y, p.pos.z or lp:GetPos().z)
                    local relative = (target - lp:GetPos()):Angle().y - lp:EyeAngles().y
                    local arrowX, arrowY = ScrW() / 2, ScrH() - 105
                    local rad = math.rad(relative)
                    local dir = Vector(math.cos(rad), math.sin(rad), 0)
                    local side = Vector(-dir.y, dir.x, 0)
                    surface.SetDrawColor(255, 220, 90, 255)
                    surface.DrawPoly({ { x = arrowX + dir.x * 22, y = arrowY + dir.y * 22 }, { x = arrowX - dir.x * 12 + side.x * 10, y = arrowY - dir.y * 12 + side.y * 10 }, { x = arrowX - dir.x * 12 - side.x * 10, y = arrowY - dir.y * 12 - side.y * 10 } })
                    draw.SimpleText("GPS: " .. tostring(p.name) .. "  •  " .. math.floor(lp:GetPos():Distance(target)) .. " юн.", "DermaDefaultBold", ScrW() / 2, ScrH() - 70, Color(255, 220, 90), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                    break
                end
            end
        end
        local current = "Вне района"
        for _, d in ipairs(data.districts or {}) do if lp:GetPos():DistToSqr(Vector(d.center.x, d.center.y, d.center.z or 0)) <= (tonumber(d.radius) or 0)^2 then current = d.name end end
        draw.SimpleText(current, "DermaDefaultBold", x + size / 2, y + size + 10, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        end
    end)

    -- Мини-карта/атлас сняты. Кружки GPS и временные метки остаются.
    hook.Remove("HUDPaint", "GRM_Minimap_HUD")
    hook.Remove("HUDPaint", "GRM_GPS_HUD")
    hook.Remove("HUDPaint", "GRM_GPS_HUD_OFF")
end


--[[ Модуль представляется общему реестру GRM.Modules: соседи знают, что он
     есть, а шина обновлений сама позовёт его при смене прав, состава,
     должности или персонажа. ]]
if GRM.Modules and GRM.Modules.Register then
    GRM.Modules.Register("minimap", {
        label = "Карта и GPS",
        version = (GRM.Minimap and GRM.Minimap.Version) or "1.0.0",
        Depends = {},
        Status = function() local d = GRM.Minimap.Data or {} return ("точек на карте: %d"):format(#(d.points or {})) end,
    })
end
