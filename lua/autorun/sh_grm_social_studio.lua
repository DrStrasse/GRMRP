--[[ Студия соц.анимаций: гизмо костей, T-pose/sequence, сейв, доступ игрокам.
     Не PAC3: свой слой, без копирования аддона. ]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Social = GRM.Social or {}
local S = GRM.Social
S.StudioFile = "grm_social_poses.json"

local function jsonT(txt)
    local ok, t = pcall(util.JSONToTable, txt, false, true)
    return (ok and istable(t)) and t or nil
end

local function slug(s)
    s = string.lower(string.Trim(tostring(s or "")))
    s = string.gsub(s, "[^%w_%-]+", "_")
    if s == "" then s = "pose_" .. tostring(os.time() % 100000) end
    return string.sub(s, 1, 32)
end

if SERVER then
    util.AddNetworkString("GRM_SocStudio_Open")
    util.AddNetworkString("GRM_SocStudio_Sync")
    util.AddNetworkString("GRM_SocStudio_Act")

    S.Catalog = S.Catalog or {}

    function S.LoadCatalog()
        if not file.Exists(S.StudioFile, "DATA") then
            S.Catalog = {}
            S.CatList = { { id = "general", name = "Общее" }, { id = "docs", name = "Документы" } }
            return
        end
        local t = jsonT(file.Read(S.StudioFile, "DATA") or "")
        if istable(t) and istable(t.poses) then
            S.Catalog = t.poses
            S.CatList = istable(t.cats) and t.cats or {}
        else
            S.Catalog = istable(t) and t or {}
            S.CatList = {}
        end
        if #(S.CatList or {}) == 0 then
            S.CatList = { { id = "general", name = "Общее" }, { id = "docs", name = "Документы" } }
        end
        if S.ApplyCatalog then S.ApplyCatalog(S.Catalog, S.CatList) end
    end

    function S.SaveCatalog()
        local fn = function()
            local ok, txt = pcall(util.TableToJSON, { poses = S.Catalog or {}, cats = S.CatList or {} }, false)
            if ok and txt then file.Write(S.StudioFile, txt) end
        end
        if GRM.Perf and GRM.Perf.Coalesce then GRM.Perf.Coalesce("grm_socstudio_save", 0.4, fn) else fn() end
    end

    function S.SyncCatalog(ply)
        net.Start("GRM_SocStudio_Sync")
        net.WriteTable({ poses = S.Catalog or {}, cats = S.CatList or {} })
        if IsValid(ply) then net.Send(ply) else net.Broadcast() end
    end

    local function admin(ply)
        return IsValid(ply) and ply:IsSuperAdmin()
    end

    local function setFreeze(ply, on, stance, seq)
        if not IsValid(ply) then return end
        ply._grmSocStudio = on and true or nil
        ply:SetNWBool("GRM_SocStudio", on == true)
        ply:SetNWString("GRM_SocStance", on and (stance or "tpose") or "")
        ply:SetNWString("GRM_SocSeq", on and (seq or "") or "")
        if ply.Freeze then ply:Freeze(on == true) end
        if not on then
            ply:SetNWString("GRM_SocAnim", "")
        end
    end

    function S.StudioOpen(ply)
        if not admin(ply) then return end
        S.LoadCatalog()
        setFreeze(ply, true, "tpose", "")
        S.SyncCatalog(ply)
        net.Start("GRM_SocStudio_Open")
        net.Send(ply)
    end

    net.Receive("GRM_SocStudio_Act", function(_, ply)
        if not admin(ply) then return end
        if GRM.Perf and GRM.Perf.Throttle and not GRM.Perf.Throttle("socstudio." .. ply:EntIndex(), 0.05) then return end
        local op = string.sub(tostring(net.ReadString() or ""), 1, 16)
        if op == "close" then
            setFreeze(ply, false)
            return
        end
        if op == "ping" then
            ply._grmSocStudio = true
            return
        end
        if op == "stance" then
            local st = string.sub(net.ReadString() or "tpose", 1, 16)
            ply:SetNWString("GRM_SocStance", st)
            return
        end
        if op == "seq" then
            ply:SetNWString("GRM_SocSeq", string.sub(net.ReadString() or "", 1, 64))
            return
        end
        if op == "save" then
            local rec = net.ReadTable() or {}
            rec.id = slug(rec.id or rec.name)
            rec.name = string.sub(string.Trim(tostring(rec.name or rec.id)), 1, 48)
            rec.players = rec.players ~= false
            rec.crouch = rec.crouch == true
            rec.walk = rec.walk ~= false
            rec.hold = rec.hold ~= false
            rec.stance = tostring(rec.stance or "idle")
            rec.sequence = tostring(rec.sequence or "")
            rec.bones = istable(rec.bones) and rec.bones or {}
            --[[ КЛЮЧЕВЫЕ КАДРЫ. Чистим на сервере: данные приходят от
                 клиента, и даже у админа может быть кривой каталог —
                 а раздаётся он потом ВСЕМ игрокам. ]]
            rec.frames = (S.SanitizeFrames and S.SanitizeFrames(rec.frames)) or {}
            if #rec.frames > 0 then
                --[[ bones держим синхронно с первым кадром: старый код
                     (бинды, предпросмотр, телефонная поза) читает
                     именно его и не знает про кадры. ]]
                rec.bones = rec.frames[1].bones or {}
            elseif istable(rec.bones) and next(rec.bones) then
                rec.frames = { { dur = 0.5, bones = rec.bones } }
            end
            rec.loop = rec.loop == true
            rec.speed = math.Clamp(tonumber(rec.speed) or 1, 0.1, 4)
            rec.prop = tostring(rec.prop or "")
            rec.freeze = rec.freeze == true
            rec.nomove = rec.nomove == true
            rec.cat = slug(rec.cat or rec.catName or "general")
            rec.catName = string.sub(string.Trim(tostring(rec.catName or rec.cat)), 1, 32)
            S.CatList = S.CatList or {}
            local haveCat
            for i = 1, #S.CatList do
                if S.CatList[i].id == rec.cat then
                    if rec.catName ~= "" then S.CatList[i].name = rec.catName end
                    haveCat = true
                    break
                end
            end
            if not haveCat then
                S.CatList[#S.CatList + 1] = { id = rec.cat, name = rec.catName ~= "" and rec.catName or rec.cat }
            end
            local found
            for i = 1, #(S.Catalog or {}) do
                if S.Catalog[i].id == rec.id then S.Catalog[i] = rec found = true break end
            end
            if not found then
                S.Catalog = S.Catalog or {}
                S.Catalog[#S.Catalog + 1] = rec
            end
            S.SaveCatalog()
            if S.ApplyCatalog then S.ApplyCatalog(S.Catalog) end
            S.SyncCatalog()
            if GRM.Notify then GRM.Notify(ply, "Поза сохранена: " .. rec.name, 120, 210, 140) end
            return
        end
        if op == "delete" then
            local id = slug(net.ReadString())
            for i = #(S.Catalog or {}), 1, -1 do
                if S.Catalog[i].id == id then table.remove(S.Catalog, i) end
            end
            S.SaveCatalog()
            S.SyncCatalog()
            return
        end
        if op == "addcat" then
            local name = string.sub(string.Trim(tostring(net.ReadString() or "")), 1, 32)
            if name == "" then return end
            local id = slug(name)
            S.CatList = S.CatList or {}
            for i = 1, #S.CatList do if S.CatList[i].id == id then return end end
            S.CatList[#S.CatList + 1] = { id = id, name = name }
            S.SaveCatalog()
            S.SyncCatalog()
            return
        end
        if op == "delcat" then
            local id = slug(net.ReadString())
            if id == "general" then return end
            S.CatList = S.CatList or {}
            for i = #S.CatList, 1, -1 do if S.CatList[i].id == id then table.remove(S.CatList, i) end end
            -- позы удалённой категории уходят в «Общее»
            for _, p in ipairs(S.Catalog or {}) do
                if p.cat == id then p.cat, p.catName = "general", "Общее" end
            end
            if #S.CatList == 0 then S.CatList = { { id = "general", name = "Общее" } } end
            S.SaveCatalog()
            S.SyncCatalog()
            return
        end
        if op == "renamecat" then
            local id = slug(net.ReadString())
            local name = string.sub(string.Trim(tostring(net.ReadString() or "")), 1, 32)
            if name == "" then return end
            for i = 1, #(S.CatList or {}) do
                if S.CatList[i].id == id then
                    S.CatList[i].name = name
                    for _, p in ipairs(S.Catalog or {}) do if p.cat == id then p.catName = name end end
                    break
                end
            end
            S.SaveCatalog()
            S.SyncCatalog()
            return
        end
        if op == "movepose" then
            local id = slug(net.ReadString())
            local toCat = slug(net.ReadString())
            local catName = ""
            for i = 1, #(S.CatList or {}) do
                if S.CatList[i].id == toCat then catName = S.CatList[i].name break end
            end
            if catName == "" then return end
            for _, p in ipairs(S.Catalog or {}) do
                if p.id == id then p.cat, p.catName = toCat, catName break end
            end
            S.SaveCatalog()
            S.SyncCatalog()
            return
        end
    end)

    hook.Add("CalcMainActivity", "GRM_SocStudio_Act", function(ply)
        if not IsValid(ply) or not ply:GetNWBool("GRM_SocStudio") then return end
        local st = ply:GetNWString("GRM_SocStance", "tpose")
        local named = ply:GetNWString("GRM_SocSeq", "")
        if named ~= "" and ply.LookupSequence then
            local seq = ply:LookupSequence(named)
            if seq and seq >= 0 then return ACT_INVALID, seq end
        end
        if st == "crouch" then return ACT_HL2MP_IDLE_CROUCH, -1 end
        if st == "idle" then return ACT_HL2MP_IDLE, -1 end
        if ply.LookupSequence then
            local seq = ply:LookupSequence("reference")
            if not seq or seq < 0 then seq = ply:LookupSequence("ragdoll") end
            if seq and seq >= 0 then return ACT_INVALID, seq end
        end
        return ACT_HL2MP_IDLE, -1
    end)

    hook.Add("StartCommand", "GRM_SocStudio_Hold", function(ply, cmd)
        if not IsValid(ply) or not ply:GetNWBool("GRM_SocStudio") then return end
        cmd:ClearMovement()
        cmd:RemoveKey(IN_JUMP)
        cmd:RemoveKey(IN_ATTACK)
        cmd:RemoveKey(IN_ATTACK2)
    end)

    hook.Add("PlayerDeath", "GRM_SocStudio_Death", function(ply) setFreeze(ply, false) end)
    hook.Add("PlayerDisconnected", "GRM_SocStudio_Disc", function(ply) setFreeze(ply, false) end)

    hook.Add("PlayerSay", "GRM_SocStudio_Chat", function(ply, text)
        local t = string.lower(string.Trim(tostring(text or "")))
        if t == "/animstudio" or t == "/анимстудия" or t == "/posedit" then
            S.StudioOpen(ply)
            return ""
        end
    end)

    hook.Add("PlayerInitialSpawn", "GRM_SocStudio_Join", function(ply)
        timer.Simple(3, function() if IsValid(ply) then S.SyncCatalog(ply) end end)
    end)

    concommand.Add("grm_anim_studio", function(ply)
        if IsValid(ply) then S.StudioOpen(ply) end
    end)

    S.LoadCatalog()
    print("[GRM Social Studio] server")
    return
end

-----------------------------------------------------------------------
-- CLIENT
-----------------------------------------------------------------------
surface.CreateFont("GRMSocEd_H", { font = "Roboto", size = 16, weight = 800, extended = true })
surface.CreateFont("GRMSocEd_B", { font = "Roboto", size = 13, weight = 500, extended = true })

local ST = { on = false, yaw = 160, pitch = 6, dist = 90, bone = "ValveBiped.Bip01_R_UpperArm", bones = {}, mode = "rotate" }

net.Receive("GRM_SocStudio_Sync", function()
    local payload = net.ReadTable() or {}
    local poses = istable(payload.poses) and payload.poses or (istable(payload) and payload or {})
    local cats  = istable(payload.cats)  and payload.cats  or {}
    if #cats == 0 then cats = { { id = "general", name = "Общее" }, { id = "docs", name = "Документы" } } end
    ST.catalog = poses
    ST.cats = cats
    if GRM.Social and GRM.Social.ApplyCatalog then GRM.Social.ApplyCatalog(poses, cats) end
    if ST.rebuildCats then ST.rebuildCats() end
    if ST.rebuildList then ST.rebuildList() end
end)

--[[ БАГ (найден 28.08). Функция принимала РОВНО ОДИН аргумент, а
     «Переместить в…» вызывает её с двумя: sendAct("movepose", id, cat).
     Второй молча терялся, сервер читал пустую строку вместо категории,
     не находил её в списке и выходил по `if catName == "" then return end`.
     Перемещение поз не работало вообще и делало это тихо.

     Теперь принимаем произвольное число аргументов. Таблица по-прежнему
     уходит как таблица, остальное — строками, в том же порядке, в каком
     их читает сервер. ]]
local function sendAct(op, ...)
    net.Start("GRM_SocStudio_Act")
    net.WriteString(op)
    local n = select("#", ...)
    for i = 1, n do
        local extra = select(i, ...)
        if extra ~= nil then
            if istable(extra) then net.WriteTable(extra)
            else net.WriteString(tostring(extra)) end
        end
    end
    net.SendToServer()
end

local function boneNames(ply)
    local out = {}
    if not IsValid(ply) or not ply.GetBoneCount then return out end
    for i = 0, (ply:GetBoneCount() or 1) - 1 do
        local n = ply:GetBoneName(i)
        if n and n ~= "" and n ~= "__INVALIDBONE__" then out[#out + 1] = n end
    end
    table.sort(out)
    return out
end

local function recOf(name)
    ST.bones[name] = ST.bones[name] or { p = 0, yaw = 0, r = 0, px = 0, py = 0, pz = 0 }
    return ST.bones[name]
end

local function applyLocal()
    local lp = LocalPlayer()
    if not IsValid(lp) then return end
    for i = 0, (lp:GetBoneCount() or 1) - 1 do
        lp:ManipulateBoneAngles(i, Angle(0, 0, 0))
        lp:ManipulateBonePosition(i, Vector(0, 0, 0))
    end
    for name, rec in pairs(ST.bones) do
        local b = lp:LookupBone(name)
        if b then
            lp:ManipulateBoneAngles(b, Angle(rec.p or 0, rec.yaw or 0, rec.r or 0))
            lp:ManipulateBonePosition(b, Vector(rec.px or 0, rec.py or 0, rec.pz or 0))
        end
    end
end

local function boneWorld()
    local lp = LocalPlayer()
    if not IsValid(lp) then return end
    local idx = lp:LookupBone(ST.bone)
    if not idx then return end
    local mtx = lp:GetBoneMatrix(idx)
    if not mtx then return end
    return mtx:GetTranslation(), mtx:GetAngles()
end

-- Оси, цвета и геометрия колец — в общем модуле GRM.Gizmo.

local function gizmoLen(o)
    return math.Clamp(EyePos():Distance(o) * 0.055, 12, 32)
end

--[[ Выбор оси и отрисовка — общий модуль GRM.Gizmo (cl_grm_gizmo.lua).

     Здесь был свой экземпляр той же логики, слово в слово повторявший
     код редактора аксессуаров, вместе со всеми его бедами: перебор
     осей через pairs() (недетерминированный порядок — «беру один,
     вращает другой»), проверка колец целиком вместе с дальней
     половиной и полное отсутствие подсветки.

     Держать два одинаковых куска в двух файлах — гарантия, что
     починят один и забудут второй. Теперь оба редактора зовут одну
     функцию. ]]
local function pickGizmo(mx, my)
    local o, ang = boneWorld()
    if not o then return end
    if not GRM.Gizmo then return end
    return GRM.Gizmo.Pick(ST.mode, o, ang, gizmoLen(o), mx, my)
end

hook.Add("PostDrawTranslucentRenderables", "GRM_SocStudio_Gizmo", function(depth, sky)
    if not ST.on or depth or sky then return end
    local o, a = boneWorld()
    if not o or not GRM.Gizmo then return end
    --[[ Что схватится под курсором, считаем каждый кадр: подсветка
         обязана следовать за мышью, а не появляться после клика. Пока
         ось тянут, hover не пересчитываем — активная важнее. ]]
    if not ST.gzAxis then
        local mx, my = gui.MousePos()
        ST.gzHover = GRM.Gizmo.Pick(ST.mode, o, a, gizmoLen(o), mx, my)
    end
    GRM.Gizmo.Draw(ST.mode, o, a, gizmoLen(o), ST.gzHover, ST.gzAxis)
end)

--[[ Подпись оси у курсора: 2D поверх всего, в мире такой текст
     нечитаем. ScreenSpaceEffects не подходит — нужен именно HUD-слой. ]]
hook.Add("HUDPaint", "GRM_SocStudio_GizmoLabel", function()
    if not ST.on or not GRM.Gizmo then return end
    local axis = ST.gzAxis or ST.gzHover
    if not axis then return end
    local mx, my = gui.MousePos()
    GRM.Gizmo.DrawLabel(ST.mode, axis, mx, my)
end)

hook.Add("CalcView", "GRM_SocStudio_Cam", function(ply)
    if not ST.on or ply ~= LocalPlayer() then return end
    local tgt = ply:GetPos() + Vector(0, 0, 40)
    local ang = Angle(ST.pitch, ST.yaw, 0)
    local want = tgt - ang:Forward() * ST.dist
    local tr = util.TraceHull({ start = tgt, endpos = want, filter = ply, mins = Vector(-4, -4, -4), maxs = Vector(4, 4, 4) })
    return { origin = tr.HitPos, angles = (tgt - tr.HitPos):Angle(), fov = 50, drawviewer = true }
end)
hook.Add("ShouldDrawLocalPlayer", "GRM_SocStudio_DrawMe", function()
    if ST.on then return true end
end)
hook.Add("CalcMainActivity", "GRM_SocStudio_ActCl", function(ply)
    if not ST.on or ply ~= LocalPlayer() then return end
    local st = ply:GetNWString("GRM_SocStance", "tpose")
    local named = ply:GetNWString("GRM_SocSeq", "")
    if named ~= "" then
        local seq = ply:LookupSequence(named)
        if seq and seq >= 0 then return ACT_INVALID, seq end
    end
    if st == "crouch" then return ACT_HL2MP_IDLE_CROUCH, -1 end
    if st == "idle" then return ACT_HL2MP_IDLE, -1 end
    local seq = ply:LookupSequence("reference")
    if not seq or seq < 0 then seq = ply:LookupSequence("ragdoll") end
    if seq and seq >= 0 then return ACT_INVALID, seq end
end)

--[[ ПРЕДПРОСМОТР И КАДРЫ В СТУДИИ.

     ST.frames — массив кадров редактируемой анимации, ST.frameIdx —
     номер текущего. ST.bones ВСЕГДА ссылается на таблицу костей
     текущего кадра: так весь старый код (слайдеры, гизмо, applyLocal)
     работает без единой правки, просто теперь он правит кадр, а не
     единственную позу. ]]
surface.CreateFont("GRMSocEd_T", { font = "Roboto", size = 15, weight = 700, extended = true })
surface.CreateFont("GRMSocEd_S", { font = "Roboto", size = 12, weight = 500, extended = true })

local COL = {
    bg     = Color(18, 23, 32, 250),
    panel  = Color(24, 30, 41, 252),
    card   = Color(34, 42, 56),
    cardOn = Color(62, 138, 224),
    line   = Color(48, 58, 74),
    text   = Color(232, 238, 246),
    dim    = Color(150, 165, 182),
    gold   = Color(245, 195, 65),
    green  = Color(52, 148, 92),
    red    = Color(170, 66, 62),
}

local function copyBones(src)
    local out = {}
    for name, rec in pairs(src or {}) do
        out[name] = {
            p = tonumber(rec.p) or 0, yaw = tonumber(rec.yaw or rec.y) or 0, r = tonumber(rec.r) or 0,
            px = tonumber(rec.px or rec.x) or 0, py = tonumber(rec.py) or 0, pz = tonumber(rec.pz or rec.z) or 0,
        }
    end
    return out
end

-- Кадры не могут быть пустыми: редактировать «ничто» нельзя.
local function ensureFrames()
    if not istable(ST.frames) or #ST.frames == 0 then
        ST.frames = { { dur = 0.5, bones = istable(ST.bones) and ST.bones or {} } }
    end
    ST.frameIdx = math.Clamp(math.floor(tonumber(ST.frameIdx) or 1), 1, #ST.frames)
    ST.frames[ST.frameIdx].bones = ST.frames[ST.frameIdx].bones or {}
    ST.bones = ST.frames[ST.frameIdx].bones
    return ST.frames[ST.frameIdx]
end

--[[ Описание анимации в том виде, в каком её понимает модуль
     воспроизведения. Предпросмотр обязан считаться ТОЙ ЖЕ функцией
     GRM.Social.Sample, что и в игре: иначе студия покажет одно, а
     игроки увидят другое. ]]
function ST.PreviewDef()
    return { id = "__preview", frames = ST.frames or {}, loop = ST.loop == true, speed = ST.speed or 1 }
end

local function applyBonesLocal(bones)
    local lp = LocalPlayer()
    if not IsValid(lp) then return end
    for i = 0, (lp:GetBoneCount() or 1) - 1 do
        lp:ManipulateBoneAngles(i, Angle(0, 0, 0))
        lp:ManipulateBonePosition(i, Vector(0, 0, 0))
    end
    for name, rec in pairs(bones or {}) do
        local b = lp:LookupBone(name)
        if b then
            lp:ManipulateBoneAngles(b, Angle(rec.p or 0, rec.yaw or 0, rec.r or 0))
            lp:ManipulateBonePosition(b, Vector(rec.px or 0, rec.py or 0, rec.pz or 0))
        end
    end
end

--[[ Показать то, что должно быть видно СЕЙЧАС: либо текущий кадр, либо
     проигрываемую анимацию. Один вход вместо разбросанных applyLocal —
     раньше фоновой таймер пинга затирал бы предпросмотр текущим
     кадром каждые две секунды. ]]
function ST.applyCurrent()
    if not ST.on then return end
    if ST.playing then
        local S2 = GRM.Social
        local t = RealTime() - (ST.playStart or RealTime())
        if S2 and S2.Sample then
            applyBonesLocal(S2.Sample(ST.PreviewDef(), t))
            -- Разовый прогон сам останавливается на последнем кадре.
            if not ST.loop and S2.TotalTime and t > S2.TotalTime(ST.PreviewDef()) + 0.2 then
                ST.playing = false
                if ST.syncPlayBtn then ST.syncPlayBtn() end
            end
        end
        return
    end
    applyLocal()
end

hook.Add("Think", "GRM_SocStudio_Preview", function()
    if not ST.on or not ST.playing then return end
    ST.applyCurrent()
end)

local function closeStudio()
    if not ST.on then return end
    ST.on = false
    ST.playing = false
    -- Ожидание скелета могло не дождаться: снимаем явно, чтобы таймер
    -- не тикал в фоне после закрытия окна.
    timer.Remove("GRM_SocStudio_Bones")
    sendAct("close")
    if IsValid(ST.frame) then ST.frame:Remove() end
    ST.frame = nil
    local lp = LocalPlayer()
    if IsValid(lp) then
        for i = 0, (lp:GetBoneCount() or 1) - 1 do
            lp:ManipulateBoneAngles(i, Angle(0, 0, 0))
            lp:ManipulateBonePosition(i, Vector(0, 0, 0))
        end
    end
end

-- Кнопка одного вида: не плодим copy-paste на каждый DButton.
local function flatBtn(parent, text, col, fn, font)
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b.Paint = function(s, w, h)
        local c = col
        if s:IsHovered() then c = Color(math.min(255, c.r + 26), math.min(255, c.g + 26), math.min(255, c.b + 26)) end
        draw.RoundedBox(5, 0, 0, w, h, c)
        draw.SimpleText(isfunction(text) and text() or text, font or "GRMSocEd_B", w / 2, h / 2,
            COL.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    b.DoClick = fn
    return b
end

local function sectionTitle(parent, txt)
    local l = vgui.Create("DLabel", parent)
    l:Dock(TOP) l:SetTall(22) l:DockMargin(0, 0, 0, 4)
    l:SetFont("GRMSocEd_T") l:SetTextColor(COL.gold) l:SetText(txt)
    return l
end

local function fieldLabel(parent, txt)
    local l = vgui.Create("DLabel", parent)
    l:Dock(TOP) l:SetTall(16)
    l:SetFont("GRMSocEd_S") l:SetTextColor(COL.dim) l:SetText(txt)
    return l
end

local function openStudio()
    if IsValid(ST.frame) then ST.frame:Remove() end
    ST.on = true
    ST.playing = false
    ST.loop = ST.loop == true
    ST.speed = ST.speed or 1
    ST.frames = { { dur = 0.5, bones = {} } }
    ST.frameIdx = 1
    ensureFrames()
    local lp = LocalPlayer()
    local names = boneNames(lp)
    ST.bone = names[1] or ST.bone

    local f = vgui.Create("DFrame")
    ST.frame = f
    f:SetSize(ScrW(), ScrH())
    f:SetPos(0, 0)
    f:SetTitle("")
    f:ShowCloseButton(false)
    f:MakePopup()
    f.Paint = function(_, w, h)
        --[[ НИКАКОЙ заливки на весь экран.

             Здесь стояло draw.RoundedBox(0,0,0,w,h, Color(10,13,18,200)).
             Фрейм растянут на весь экран, поэтому подложка тонировала
             и саму сцену с моделью — владелец 31.08: «чё за
             потемнение?». Сцену обязано быть видно как в игре, иначе
             по ней не оценишь позу. Рисуем только шапку, панели
             красят себя сами. ]]
        draw.RoundedBox(0, 0, 0, w, 52, Color(14, 18, 26, 252))
        draw.RoundedBox(0, 0, 51, w, 1, COL.line)
        draw.SimpleText("СТУДИЯ АНИМАЦИЙ", "GRMSocEd_H", 20, 26, COL.gold, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("ЛКМ по сцене — орбита  ·  колесо — приблизить  ·  гизмо/слайдеры — кость  ·  кадры внизу",
            "GRMSocEd_B", 210, 26, COL.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    f.OnRemove = function() if ST.on then closeStudio() end end

    local xBtn = flatBtn(f, "✕ ЗАКРЫТЬ", Color(58, 66, 82), function() closeStudio() end)
    xBtn:SetPos(ScrW() - 132, 12) xBtn:SetSize(120, 28)

    -------------------------------------------------------------------
    -- Каркас: слева библиотека и параметры, справа кости, снизу кадры.
    -------------------------------------------------------------------
    local body = vgui.Create("DPanel", f)
    body:SetPos(0, 52)
    body:SetSize(ScrW(), ScrH() - 52)
    body:SetPaintBackground(false)

    local left = vgui.Create("DPanel", body)
    left:Dock(LEFT) left:SetWide(330) left:DockMargin(10, 10, 5, 10) left:DockPadding(10, 10, 10, 10)
    left.Paint = function(_, w, h) draw.RoundedBox(8, 0, 0, w, h, COL.panel) end

    local right = vgui.Create("DPanel", body)
    right:Dock(RIGHT) right:SetWide(340) right:DockMargin(5, 10, 10, 10) right:DockPadding(10, 10, 10, 10)
    right.Paint = function(_, w, h) draw.RoundedBox(8, 0, 0, w, h, COL.panel) end

    local tl = vgui.Create("DPanel", body)
    tl:Dock(BOTTOM) tl:SetTall(152) tl:DockMargin(5, 5, 5, 10) tl:DockPadding(10, 8, 10, 8)
    tl.Paint = function(_, w, h) draw.RoundedBox(8, 0, 0, w, h, COL.panel) end

    local view = vgui.Create("DPanel", body)
    view:Dock(FILL) view:DockMargin(5, 10, 5, 5)
    view:SetPaintBackground(false)
    view.OnMousePressed = function(s, key)
        if key ~= MOUSE_LEFT then return end
        local mx, my = gui.MousePos()
        local axis, dx, dy = pickGizmo(mx, my)
        if axis then
            local rec = recOf(ST.bone)
            ST.gzAxis, ST.gzDX, ST.gzDY = axis, dx, dy
            ST.gzX, ST.gzY = mx, my
            if ST.mode == "rotate" then
                --[[ Поле угла берём из общей таблицы соответствия.
                     Раньше здесь стояло x→p, y→yaw, z→r — соответствие
                     было сдвинуто, и кольцо Z крутило roll (вокруг X).
                     См. G.AngleKeyOf в cl_grm_gizmo.lua. ]]
                ST.gzVal = rec[GRM.Gizmo.AngleKey(axis, "yaw")] or 0
            else
                ST.gzVal = (axis == "x" and rec.px) or (axis == "y" and rec.py) or rec.pz
            end
            -- Тянуть кость во время проигрывания бессмысленно: кадр
            -- всё равно перезапишется следующим тиком. Останавливаем.
            ST.playing = false
            if ST.syncPlayBtn then ST.syncPlayBtn() end
        else
            s.drag = true
            s.lx, s.ly = mx, my
        end
        s:MouseCapture(true)
    end
    view.OnMouseReleased = function(s)
        s.drag = false
        ST.gzAxis = nil
        s:MouseCapture(false)
        if ST.refreshSliders then ST.refreshSliders() end
        if ST.refreshStrip then ST.refreshStrip() end
    end
    view.OnCursorMoved = function(s)
        local mx, my = gui.MousePos()
        if ST.gzAxis then
            local rec = recOf(ST.bone)
            local proj = (mx - (ST.gzX or mx)) * (ST.gzDX or 0) + (my - (ST.gzY or my)) * (ST.gzDY or 0)
            if ST.mode == "rotate" then
                local v = math.NormalizeAngle((ST.gzVal or 0) + proj * 0.45)
                -- То же соответствие, что и при захвате оси.
                rec[GRM.Gizmo.AngleKey(ST.gzAxis, "yaw")] = v
            else
                local v = math.Clamp((ST.gzVal or 0) + proj * 0.04, -20, 20)
                if ST.gzAxis == "x" then rec.px = v
                elseif ST.gzAxis == "y" then rec.py = v
                else rec.pz = v end
            end
            applyLocal()
            if ST.refreshSliders then ST.refreshSliders() end
            return
        end
        if not s.drag then return end
        ST.yaw = ST.yaw - (mx - (s.lx or mx)) * 0.35
        ST.pitch = math.Clamp(ST.pitch + (my - (s.ly or my)) * 0.25, -30, 50)
        s.lx, s.ly = mx, my
    end
    view.OnMouseWheeled = function(_, d)
        ST.dist = math.Clamp(ST.dist - d * 8, 50, 220)
        return true
    end

    -------------------------------------------------------------------
    -- ЛЕВО: параметры анимации (низ) + библиотека (верх).
    --
    -- Жалоба владельца 31.08: «название задаётся с одной стороны, а
    -- сохранить кнопка вообще справа». Теперь имя, ID, категория,
    -- галочки и САМА кнопка сохранения лежат в одном блоке, кнопка —
    -- прямо под полями, к которым относится.
    -------------------------------------------------------------------
    local props = vgui.Create("DPanel", left)
    props:Dock(BOTTOM) props:SetTall(302) props:DockMargin(0, 8, 0, 0) props:DockPadding(8, 6, 8, 8)
    props.Paint = function(_, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Color(30, 37, 50, 255))
    end
    sectionTitle(props, "ПАРАМЕТРЫ АНИМАЦИИ")

    fieldLabel(props, "Название (видят игроки)")
    local nameE = vgui.Create("DTextEntry", props)
    nameE:Dock(TOP) nameE:SetTall(24) nameE:DockMargin(0, 0, 0, 6)
    nameE:SetPlaceholderText("Приветствие")

    fieldLabel(props, "ID (латиницей, без пробелов)")
    local idE = vgui.Create("DTextEntry", props)
    idE:Dock(TOP) idE:SetTall(24) idE:DockMargin(0, 0, 0, 6)
    idE:SetPlaceholderText("wave")

    fieldLabel(props, "Категория")
    local catSel = vgui.Create("DComboBox", props)
    catSel:Dock(TOP) catSel:SetTall(24) catSel:DockMargin(0, 0, 0, 6)
    catSel:SetValue("Общее")

    local flags = vgui.Create("DPanel", props)
    flags:Dock(TOP) flags:SetTall(42) flags:DockMargin(0, 0, 0, 6)
    flags:SetPaintBackground(false)
    local function mkChk(x, y, w, txt, def, tip)
        local c = vgui.Create("DCheckBoxLabel", flags)
        c:SetPos(x, y) c:SetWide(w) c:SetText(txt) c:SetValue(def and 1 or 0)
        c:SetTextColor(COL.text)
        if tip then c:SetTooltip(tip) end
        return c
    end
    local chkP = mkChk(0, 2, 100, "Игрокам", true, "Показывать анимацию в меню игроков")
    local chkC = mkChk(104, 2, 90, "Присед", false)
    local chkW = mkChk(200, 2, 100, "Ходьба", true, "Можно идти во время анимации")
    local chkFreeze = mkChk(0, 22, 150, "Заморозить", false, "Игрок не сможет двигаться, пока идёт анимация")
    local chkHold = mkChk(160, 22, 150, "Держать до отмены", true,
        "Выкл — разовая анимация: доиграет и снимется сама")

    local saveB = flatBtn(props, "СОХРАНИТЬ АНИМАЦИЮ", COL.green, function()
        if not ST.doSave then return end
        ST.doSave()
    end, "GRMSocEd_T")
    saveB:Dock(TOP) saveB:SetTall(34) saveB:DockMargin(0, 2, 0, 4)

    local newB = flatBtn(props, "СОЗДАТЬ НОВУЮ", Color(58, 66, 82), function()
        if ST.newAnim then ST.newAnim() end
    end)
    newB:Dock(TOP) newB:SetTall(24)

    --[[ БАЗОВАЯ СТОЙКА. Кости крутятся ОТНОСИТЕЛЬНО текущей анимации
         модели, поэтому автору важно видеть исходник: на T-pose удобно
         строить позу с нуля, на «Стойке» — проверять, как она ляжет в
         игре. Раньше этот выбор жил среди полей сохранения и выглядел
         как свойство анимации, хотя он только для просмотра. ]]
    sectionTitle(left, "БАЗА ПРОСМОТРА")
    local baseRow = vgui.Create("DPanel", left)
    baseRow:Dock(TOP) baseRow:SetTall(26) baseRow:DockMargin(0, 0, 0, 8)
    baseRow:SetPaintBackground(false)
    local stance = vgui.Create("DComboBox", baseRow)
    stance:Dock(LEFT) stance:SetWide(150) stance:DockMargin(0, 0, 4, 0)
    stance:AddChoice("T-pose", "tpose", true)
    stance:AddChoice("Стойка", "idle")
    stance:AddChoice("Присед", "crouch")
    stance.OnSelect = function(_, _, _, v) sendAct("stance", v or "tpose") end
    local seq = vgui.Create("DComboBox", baseRow)
    seq:Dock(FILL)
    seq:SetValue("движение (нет)")
    seq:AddChoice("движение (нет)", "", true)
    if IsValid(lp) and lp.GetSequenceList then
        local seen = {}
        for _, n in ipairs(lp:GetSequenceList() or {}) do
            if not seen[n] then
                seen[n] = true
                seq:AddChoice(n, n)
            end
        end
    end
    seq.OnSelect = function(_, _, _, v) sendAct("seq", v or "") end

    sectionTitle(left, "БИБЛИОТЕКА")

    local catRow = vgui.Create("DPanel", left)
    catRow:Dock(TOP) catRow:SetTall(26) catRow:DockMargin(0, 0, 0, 4)
    catRow:SetPaintBackground(false)
    local catBox = vgui.Create("DComboBox", catRow)
    catBox:Dock(FILL) catBox:DockMargin(0, 0, 4, 0)
    catBox:SetValue("Все категории")
    local catNew = flatBtn(catRow, "+ КАТ.", Color(46, 110, 70), function()
        Derma_StringRequest("Новая категория", "Название категории", "", function(n)
            n = string.Trim(n or "")
            if n ~= "" then sendAct("addcat", n) end
        end)
    end)
    catNew:Dock(RIGHT) catNew:SetWide(66)

    local catDel = flatBtn(left, "Удалить текущую категорию", Color(84, 48, 48), function()
        local id = IsValid(catBox) and catBox:GetOptionData(catBox:GetSelectedID()) or "general"
        if id == "general" or id == "all" then return end
        Derma_Query("Удалить категорию и перенести анимации в «Общее»?", "Категория",
            "Удалить", function() sendAct("delcat", id) end, "Отмена", function() end)
    end, "GRMSocEd_S")
    catDel:Dock(TOP) catDel:SetTall(22) catDel:DockMargin(0, 0, 0, 6)

    local statusL = vgui.Create("DLabel", left)
    statusL:Dock(BOTTOM) statusL:SetTall(18)
    statusL:SetFont("GRMSocEd_B") statusL:SetTextColor(Color(110, 200, 130)) statusL:SetText("")
    function ST.setStatus(txt) if IsValid(statusL) then statusL:SetText(txt or "") end end

    local list = vgui.Create("DListView")
    list:SetParent(left)
    list:Dock(FILL)
    list:AddColumn("Сохранённые анимации")
    list:SetMultiSelect(false)

    -------------------------------------------------------------------
    -- Категории в двух списках сразу: фильтр библиотеки и выбор для
    -- сохраняемой анимации. Раньше это был ОДИН combobox на две роли,
    -- из-за чего смена фильтра молча меняла категорию сохранения.
    -------------------------------------------------------------------
    function ST.rebuildCats()
        local cats = ST.cats or (GRM.Social and GRM.Social.CatList) or {}
        if #cats == 0 then cats = { { id = "general", name = "Общее" } } end
        if IsValid(catBox) then
            local keep = catBox:GetOptionData(catBox:GetSelectedID() or 0) or "all"
            catBox:Clear()
            catBox:AddChoice("Все категории", "all", keep == "all")
            for _, c in ipairs(cats) do
                catBox:AddChoice(c.name or c.id, c.id, c.id == keep)
            end
        end
        if IsValid(catSel) then
            local keep2 = catSel:GetOptionData(catSel:GetSelectedID() or 0) or "general"
            catSel:Clear()
            local sel = false
            for _, c in ipairs(cats) do
                local on = c.id == keep2
                catSel:AddChoice(c.name or c.id, c.id, on)
                if on then sel = true end
            end
            if not sel then catSel:ChooseOptionID(1) end
        end
    end
    ST.rebuildCats()
    catBox.OnSelect = function() if ST.rebuildList then ST.rebuildList() end end

    local function rebuildListBody()
        list:Clear()
        local keep = IsValid(catBox) and catBox:GetOptionData(catBox:GetSelectedID() or 0) or "all"
        for _, p in ipairs(ST.catalog or {}) do
            if keep == "all" or (p.cat or "general") == keep then
                local frames = (GRM.Social and GRM.Social.Frames) and GRM.Social.Frames(p) or {}
                -- Сразу видно, поза это или настоящая анимация.
                local mark = #frames > 1 and ("▶ " .. #frames .. "к  ") or "● "
                local line = list:AddLine(mark .. (p.name or p.id))
                line._id = p.id
                if p.id == ST.selectedID then list:SelectItem(line) end
            end
        end
    end

    --[[ Флаг повторного входа снимается ВСЕГДА (pcall): иначе ошибка
         внутри навсегда замораживала список — так уже ловили 28.08. ]]
    function ST.rebuildList()
        if not IsValid(list) then return end
        if ST._busy then return end
        ST._busy = true
        local ok, err = pcall(rebuildListBody)
        ST._busy = false
        if not ok then
            ErrorNoHalt("[GRM Studio] сбой перестроения списка: " .. tostring(err) .. "\n")
        end
    end

    -- Объявление заранее: обработчики ниже ссылаются на функцию, которая
    -- определена дальше по файлу (локальные видны только после себя).
    local loadPose

    list.OnRowSelected = function(_, _, line)
        if ST._busy then return end
        if line and line._id then
            local ok, err = pcall(loadPose, line._id)
            if not ok then
                ErrorNoHalt("[GRM Studio] не удалось загрузить '" .. tostring(line._id) .. "': " .. tostring(err) .. "\n")
            end
        end
    end
    list.OnRowRightClick = function(_, _, line)
        if not (line and line._id) then return end
        local menu = DermaMenu()
        menu:AddOption("Загрузить", function() loadPose(line._id) end)
        local move = menu:AddSubMenu("Переместить в…")
        for _, c in ipairs(ST.cats or { { id = "general", name = "Общее" } }) do
            move:AddOption(c.name or c.id, function() sendAct("movepose", line._id, c.id) end)
        end
        menu:AddOption("Удалить", function()
            Derma_Query("Удалить «" .. tostring(line._id) .. "»?", "Удаление", "Удалить", function()
                ST.selectedID = nil
                sendAct("delete", line._id)
                notification.AddLegacy("Анимация удалена", NOTIFY_UNDO, 3)
            end, "Отмена", function() end)
        end)
        menu:Open()
    end
    ST.rebuildList()

    -------------------------------------------------------------------
    -- ПРАВО: кости и трансформация.
    -------------------------------------------------------------------
    local trans = vgui.Create("DPanel", right)
    trans:Dock(BOTTOM) trans:SetTall(330) trans:DockMargin(0, 8, 0, 0) trans:DockPadding(8, 6, 8, 8)
    trans.Paint = function(_, w, h) draw.RoundedBox(6, 0, 0, w, h, Color(30, 37, 50, 255)) end

    local boneNameL = vgui.Create("DLabel", trans)
    boneNameL:Dock(TOP) boneNameL:SetTall(20)
    boneNameL:SetFont("GRMSocEd_T") boneNameL:SetTextColor(COL.gold)
    boneNameL:SetText("КОСТЬ")

    local modeRow = vgui.Create("DPanel", trans)
    modeRow:Dock(TOP) modeRow:SetTall(28) modeRow:DockMargin(0, 2, 0, 6)
    modeRow:SetPaintBackground(false)
    local moveB = vgui.Create("DButton", modeRow)
    moveB:Dock(LEFT) moveB:SetWide(150) moveB:SetText("")
    local rotB = vgui.Create("DButton", modeRow)
    rotB:Dock(RIGHT) rotB:SetWide(150) rotB:SetText("")
    local function paintMode(s, w, h, on, col, txt)
        draw.RoundedBox(5, 0, 0, w, h, on and col or Color(40, 48, 62))
        draw.SimpleText(txt, "GRMSocEd_B", w / 2, h / 2, COL.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    moveB.Paint = function(s, w, h) paintMode(s, w, h, ST.mode == "move", Color(65, 145, 235), "ПЕРЕМЕЩЕНИЕ") end
    rotB.Paint = function(s, w, h) paintMode(s, w, h, ST.mode == "rotate", Color(230, 150, 60), "ВРАЩЕНИЕ") end
    moveB.DoClick = function() ST.mode = "move" end
    rotB.DoClick = function() ST.mode = "rotate" end

    local sliders = {}
    local function addSl(label, key, mn, mx)
        local s = vgui.Create("DNumSlider", trans)
        s:Dock(TOP) s:SetTall(26)
        s:SetText(label) s:SetMin(mn) s:SetMax(mx) s:SetDecimals(1)
        s:SetDark(false)
        if IsValid(s.Label) then
            s.Label:SetTextColor(COL.text)
            s.Label:SetFont("GRMSocEd_B")
        end
        if IsValid(s.TextArea) then s.TextArea:SetTextColor(COL.text) end
        s.OnValueChanged = function(_, v)
            if ST._syncing then return end
            local rec = recOf(ST.bone)
            rec[key] = tonumber(v) or 0
            applyLocal()
            if ST.refreshStrip then ST.refreshStrip() end
        end
        sliders[key] = s
        return s
    end
    --[[ Подписи по ОСИ ГИЗМО, а не по имени поля. Голые «Pitch/Yaw/Roll»
         не подсказывают, какое кольцо их крутит, и рассинхрон с гизмо
         (кольцо Z ↔ поле yaw) заметить было невозможно. ]]
    addSl("Вокруг X (Roll)", "r", -180, 180)
    addSl("Вокруг Y (Pitch)", "p", -180, 180)
    addSl("Вокруг Z (Yaw)", "yaw", -180, 180)
    addSl("Сдвиг X", "px", -20, 20)
    addSl("Сдвиг Y", "py", -20, 20)
    addSl("Сдвиг Z", "pz", -20, 20)

    --[[ Флаг _syncing обязателен: SetValue дёргает OnValueChanged, и без
         него простое обновление слайдеров записывало бы значения назад
         в кость — при переключении кадров это стирало данные. ]]
    function ST.refreshSliders()
        local rec = recOf(ST.bone)
        ST._syncing = true
        for k, s in pairs(sliders) do
            if IsValid(s) then s:SetValue(tonumber(rec[k]) or 0) end
        end
        ST._syncing = false
        if IsValid(boneNameL) then
            boneNameL:SetText("КОСТЬ: " .. string.gsub(tostring(ST.bone or ""), "ValveBiped.Bip01_", ""))
        end
    end

    local resetRow = vgui.Create("DPanel", trans)
    resetRow:Dock(TOP) resetRow:SetTall(28) resetRow:DockMargin(0, 6, 0, 0)
    resetRow:SetPaintBackground(false)
    local rb1 = flatBtn(resetRow, "СБРОС КОСТИ", Color(72, 82, 100), function()
        ST.bones[ST.bone] = { p = 0, yaw = 0, r = 0, px = 0, py = 0, pz = 0 }
        applyLocal()
        ST.refreshSliders()
        if ST.refreshStrip then ST.refreshStrip() end
    end)
    rb1:Dock(LEFT) rb1:SetWide(150)
    local rb2 = flatBtn(resetRow, "СБРОС КАДРА", Color(96, 62, 62), function()
        local fr = ensureFrames()
        for k in pairs(fr.bones) do fr.bones[k] = nil end
        applyLocal()
        ST.refreshSliders()
        if ST.refreshStrip then ST.refreshStrip() end
    end)
    rb2:Dock(RIGHT) rb2:SetWide(150)

    local copyRow = vgui.Create("DPanel", trans)
    copyRow:Dock(TOP) copyRow:SetTall(26) copyRow:DockMargin(0, 6, 0, 0)
    copyRow:SetPaintBackground(false)
    local cb1 = flatBtn(copyRow, "КОПИРОВАТЬ ПОЗУ", Color(58, 70, 92), function()
        ST.clip = copyBones(ensureFrames().bones)
        ST.setStatus("Поза кадра скопирована")
    end, "GRMSocEd_S")
    cb1:Dock(LEFT) cb1:SetWide(150)
    local cb2 = flatBtn(copyRow, "ВСТАВИТЬ В КАДР", Color(58, 70, 92), function()
        if not istable(ST.clip) then ST.setStatus("Буфер пуст") return end
        local fr = ensureFrames()
        fr.bones = copyBones(ST.clip)
        ST.bones = fr.bones
        applyLocal()
        ST.refreshSliders()
        if ST.refreshStrip then ST.refreshStrip() end
    end, "GRMSocEd_S")
    cb2:Dock(RIGHT) cb2:SetWide(150)

    sectionTitle(right, "СКЕЛЕТ")
    local search = vgui.Create("DTextEntry", right)
    search:Dock(TOP) search:SetTall(24) search:DockMargin(0, 0, 0, 6)
    search:SetPlaceholderText("поиск кости: hand, spine, head…")

    local bonesc = vgui.Create("DScrollPanel", right)
    bonesc:Dock(FILL)

    --[[ БАГ (владелец 31.08: «где список костей?»).

         Имена костей брались РОВНО ОДИН РАЗ при открытии окна. Но
         GetBoneCount у игрока даёт 0, пока движок не построил скелет
         модели — а студия как раз в этот момент и открывается (сервер
         только что дёрнул заморозку и сменил стойку). Пустой список
         строился молча, и колонка «СКЕЛЕТ» оставалась голой до
         перезахода. Видно это было и по подписи «КОСТЬ: R_UpperArm» —
         значение по умолчанию, а не первое имя из списка.

         Лечим двумя вещами: имена перечитываем при КАЖДОМ построении,
         и пока их нет — пробуем снова (ниже по таймеру). ]]
    local function rebuildBones()
        if not IsValid(bonesc) then return end
        bonesc:Clear()
        if #names == 0 then names = boneNames(LocalPlayer()) end
        if #names > 0 then
            -- Кость по умолчанию могла не существовать у этой модели.
            local have
            for _, n in ipairs(names) do if n == ST.bone then have = true break end end
            if not have then
                ST.bone = names[1]
                if ST.refreshSliders then ST.refreshSliders() end
            end
        end
        local q = string.lower(string.Trim(IsValid(search) and search:GetValue() or ""))
        for _, n in ipairs(names) do
            local shortN = string.gsub(n, "ValveBiped.Bip01_", "")
            if q == "" or string.find(string.lower(shortN), q, 1, true) then
                local b = vgui.Create("DButton", bonesc)
                b:Dock(TOP) b:SetTall(20) b:DockMargin(0, 0, 0, 1) b:SetText("")
                b.Paint = function(_, w, h)
                    local on = ST.bone == n
                    -- Изменённые кости подсвечиваем: сразу видно, что
                    -- участвует в кадре, а что нет.
                    local touched = istable(ST.bones) and ST.bones[n] ~= nil
                    draw.RoundedBox(3, 0, 0, w, h, on and COL.cardOn or COL.card)
                    draw.SimpleText(shortN, "GRMSocEd_S", 8, h / 2,
                        touched and COL.gold or COL.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                end
                b.DoClick = function()
                    ST.bone = n
                    ST.refreshSliders()
                end
            end
        end
    end
    search.OnChange = rebuildBones
    rebuildBones()
    ST.refreshSliders()

    --[[ Скелет мог быть ещё не готов (см. комментарий выше). Дожидаемся
         его короткими попытками, а не одним «авось успело». Как только
         кости появились — строим список и прекращаем. Таймер именной и
         снимается вместе с окном, поэтому в фоне ничего не остаётся. ]]
    if #names == 0 then
        local tries = 0
        timer.Create("GRM_SocStudio_Bones", 0.25, 0, function()
            tries = tries + 1
            if not ST.on or not IsValid(bonesc) or tries > 40 then
                timer.Remove("GRM_SocStudio_Bones")
                return
            end
            names = boneNames(LocalPlayer())
            if #names > 0 then
                rebuildBones()
                timer.Remove("GRM_SocStudio_Bones")
            end
        end)
    end

    -------------------------------------------------------------------
    -- НИЗ: лента ключевых кадров.
    -------------------------------------------------------------------
    local tlTop = vgui.Create("DPanel", tl)
    tlTop:Dock(TOP) tlTop:SetTall(28) tlTop:DockMargin(0, 0, 0, 6)
    tlTop:SetPaintBackground(false)

    local tlTitle = vgui.Create("DLabel", tlTop)
    tlTitle:Dock(LEFT) tlTitle:SetWide(180)
    tlTitle:SetFont("GRMSocEd_T") tlTitle:SetTextColor(COL.gold)
    tlTitle:SetText("КЛЮЧЕВЫЕ КАДРЫ")

    local playB
    function ST.syncPlayBtn()
        if IsValid(playB) then playB:InvalidateLayout() end
    end
    playB = flatBtn(tlTop, function() return ST.playing and "■ СТОП" or "▶ ПРОСМОТР" end, Color(52, 120, 190), function()
        ST.playing = not ST.playing
        ST.playStart = RealTime()
        if not ST.playing then applyLocal() end
    end, "GRMSocEd_T")
    playB:Dock(RIGHT) playB:SetWide(140)

    local loopChk = vgui.Create("DCheckBoxLabel", tlTop)
    loopChk:Dock(RIGHT) loopChk:SetWide(110) loopChk:DockMargin(0, 6, 8, 0)
    loopChk:SetText("Зациклить") loopChk:SetTextColor(COL.text)
    loopChk:SetValue(ST.loop and 1 or 0)
    loopChk.OnChange = function(_, v) ST.loop = v == true end

    local speedSl = vgui.Create("DNumSlider", tlTop)
    speedSl:Dock(RIGHT) speedSl:SetWide(210)
    speedSl:SetText("Скорость") speedSl:SetMin(0.2) speedSl:SetMax(3) speedSl:SetDecimals(2)
    speedSl:SetValue(ST.speed or 1) speedSl:SetDark(false)
    if IsValid(speedSl.Label) then speedSl.Label:SetTextColor(COL.text) speedSl.Label:SetFont("GRMSocEd_B") end
    if IsValid(speedSl.TextArea) then speedSl.TextArea:SetTextColor(COL.text) end
    speedSl.OnValueChanged = function(_, v) ST.speed = math.Clamp(tonumber(v) or 1, 0.1, 4) end

    local durSl = vgui.Create("DNumSlider", tlTop)
    durSl:Dock(RIGHT) durSl:SetWide(260) durSl:DockMargin(0, 0, 8, 0)
    durSl:SetText("Кадр, сек") durSl:SetMin(0.05) durSl:SetMax(5) durSl:SetDecimals(2)
    durSl:SetValue(0.5) durSl:SetDark(false)
    if IsValid(durSl.Label) then durSl.Label:SetTextColor(COL.text) durSl.Label:SetFont("GRMSocEd_B") end
    if IsValid(durSl.TextArea) then durSl.TextArea:SetTextColor(COL.text) end
    durSl.OnValueChanged = function(_, v)
        if ST._syncing then return end
        local fr = ensureFrames()
        fr.dur = math.Clamp(tonumber(v) or 0.5, 0.05, 10)
        if ST.refreshStrip then ST.refreshStrip() end
    end

    local btnRow = vgui.Create("DPanel", tl)
    btnRow:Dock(BOTTOM) btnRow:SetTall(26) btnRow:DockMargin(0, 6, 0, 0)
    btnRow:SetPaintBackground(false)

    local strip = vgui.Create("DHorizontalScroller", tl)
    strip:Dock(FILL)
    strip:SetOverlap(-6)

    --[[ Переключение кадра. Кадр — это отдельная поза, поэтому меняем
         ST.bones (на неё смотрят слайдеры и гизмо) и сразу показываем
         результат: без этого админ правил бы один кадр, глядя на другой. ]]
    local function selectFrame(i)
        ST.frameIdx = math.Clamp(i, 1, #(ST.frames or { 1 }))
        ensureFrames()
        ST.playing = false
        ST._syncing = true
        if IsValid(durSl) then durSl:SetValue(ST.frames[ST.frameIdx].dur or 0.5) end
        ST._syncing = false
        applyLocal()
        ST.refreshSliders()
        if ST.refreshStrip then ST.refreshStrip() end
    end

    function ST.refreshStrip()
        if not IsValid(strip) then return end
        strip:Clear()
        ensureFrames()
        for i, fr in ipairs(ST.frames) do
            local card = vgui.Create("DButton")
            card:SetSize(96, 56)
            card:SetText("")
            card.Paint = function(_, w, h)
                local on = i == ST.frameIdx
                draw.RoundedBox(6, 0, 0, w, h, on and COL.cardOn or COL.card)
                draw.SimpleText("КАДР " .. i, "GRMSocEd_T", w / 2, 14, COL.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                draw.SimpleText(string.format("%.2f с", tonumber(fr.dur) or 0.5), "GRMSocEd_S", w / 2, 32,
                    COL.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                local n = 0
                for _ in pairs(fr.bones or {}) do n = n + 1 end
                draw.SimpleText(n .. " костей", "GRMSocEd_S", w / 2, 46,
                    on and COL.text or COL.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            card.DoClick = function() selectFrame(i) end
            card.DoRightClick = function()
                local menu = DermaMenu()
                menu:AddOption("Вставить копию после", function()
                    table.insert(ST.frames, i + 1, { dur = fr.dur or 0.5, bones = copyBones(fr.bones) })
                    selectFrame(i + 1)
                end)
                menu:AddOption("Сдвинуть влево", function()
                    if i > 1 then
                        ST.frames[i], ST.frames[i - 1] = ST.frames[i - 1], ST.frames[i]
                        selectFrame(i - 1)
                    end
                end)
                menu:AddOption("Сдвинуть вправо", function()
                    if i < #ST.frames then
                        ST.frames[i], ST.frames[i + 1] = ST.frames[i + 1], ST.frames[i]
                        selectFrame(i + 1)
                    end
                end)
                menu:AddOption("Удалить кадр", function()
                    if #ST.frames <= 1 then return end
                    table.remove(ST.frames, i)
                    selectFrame(math.min(i, #ST.frames))
                end)
                menu:Open()
            end
            strip:AddPanel(card)
        end
        local total = (GRM.Social and GRM.Social.TotalTime) and GRM.Social.TotalTime(ST.PreviewDef()) or 0
        if IsValid(tlTitle) then
            tlTitle:SetText(string.format("КАДРЫ: %d · %.2f с", #ST.frames, total))
        end
    end

    local addB = flatBtn(btnRow, "+ КАДР (копия текущего)", COL.green, function()
        local fr = ensureFrames()
        table.insert(ST.frames, ST.frameIdx + 1, { dur = fr.dur or 0.5, bones = copyBones(fr.bones) })
        selectFrame(ST.frameIdx + 1)
    end)
    addB:Dock(LEFT) addB:SetWide(210) addB:DockMargin(0, 0, 6, 0)
    local addEmptyB = flatBtn(btnRow, "+ ПУСТОЙ", Color(58, 70, 92), function()
        table.insert(ST.frames, ST.frameIdx + 1, { dur = 0.5, bones = {} })
        selectFrame(ST.frameIdx + 1)
    end)
    addEmptyB:Dock(LEFT) addEmptyB:SetWide(120) addEmptyB:DockMargin(0, 0, 6, 0)
    local delB = flatBtn(btnRow, "УДАЛИТЬ КАДР", COL.red, function()
        if #ST.frames <= 1 then ST.setStatus("Последний кадр удалить нельзя") return end
        table.remove(ST.frames, ST.frameIdx)
        selectFrame(math.min(ST.frameIdx, #ST.frames))
    end)
    delB:Dock(LEFT) delB:SetWide(150)
    local hintL = vgui.Create("DLabel", btnRow)
    hintL:Dock(FILL) hintL:DockMargin(10, 0, 0, 0)
    hintL:SetFont("GRMSocEd_S") hintL:SetTextColor(COL.dim)
    hintL:SetText("Один кадр = поза. Два и больше = анимация: ПКМ по кадру — копия/порядок/удаление.")

    ST.refreshStrip()

    -------------------------------------------------------------------
    -- Загрузка / сохранение.
    -------------------------------------------------------------------
    function loadPose(id)
        for _, p in ipairs(ST.catalog or {}) do
            if p.id == id then
                ST.selectedID = id
                idE:SetText(p.id or "")
                nameE:SetText(p.name or "")
                chkP:SetValue(p.players ~= false)
                chkC:SetValue(p.crouch == true)
                chkW:SetValue(p.walk ~= false)
                chkFreeze:SetValue(p.freeze == true or p.nomove == true)
                chkHold:SetValue(p.hold ~= false)
                ST.loop = p.loop == true
                if IsValid(loopChk) then loopChk:SetValue(ST.loop and 1 or 0) end
                ST.speed = math.Clamp(tonumber(p.speed) or 1, 0.1, 4)
                if IsValid(speedSl) then
                    ST._syncing = true
                    speedSl:SetValue(ST.speed)
                    ST._syncing = false
                end
                --[[ ChooseOptionID дёргает OnSelect. Здесь у списка
                     категорий сохранения обработчика нет, но флаг
                     ставим всё равно: 28.08 именно на этой строке
                     замыкалась рекурсия
                     OnRowSelected → loadPose → OnSelect → rebuildList →
                     SelectItem → OnRowSelected, и игра падала по
                     переполнению стека. Стоит кому-то повесить сюда
                     обработчик — цепочка вернётся. Флаг ВОССТАНАВЛИВАЕМ,
                     а не гасим в false: loadPose могли вызвать изнутри
                     перестроения списка. ]]
                if IsValid(catSel) then
                    local wasBusy = ST._busy
                    ST._busy = true
                    for i = 1, 64 do
                        local d = catSel:GetOptionData(i)
                        if not d then break end
                        if d == (p.cat or "general") then catSel:ChooseOptionID(i) break end
                    end
                    ST._busy = wasBusy
                end
                --[[ Кадры берём через общий S.Frames: он же превращает
                     старую позу (только bones) в один кадр. Если бы
                     студия делала это по-своему, старые записи после
                     пересохранения могли бы поехать. ]]
                local src = (GRM.Social and GRM.Social.Frames) and GRM.Social.Frames(p) or {}
                ST.frames = {}
                for _, fr in ipairs(src) do
                    ST.frames[#ST.frames + 1] = { dur = tonumber(fr.dur) or 0.5, bones = copyBones(fr.bones) }
                end
                if #ST.frames == 0 then ST.frames = { { dur = 0.5, bones = {} } } end
                ST.frameIdx = 1
                selectFrame(1)
                ST.setStatus("Загружено: " .. tostring(p.name or id))
                if ST.rebuildList then ST.rebuildList() end
                return
            end
        end
    end

    function ST.newAnim()
        ST.selectedID = nil
        idE:SetText("")
        nameE:SetText("")
        chkP:SetValue(true) chkC:SetValue(false) chkW:SetValue(true)
        chkFreeze:SetValue(false) chkHold:SetValue(true)
        ST.loop = false
        if IsValid(loopChk) then loopChk:SetValue(0) end
        ST.frames = { { dur = 0.5, bones = {} } }
        ST.frameIdx = 1
        selectFrame(1)
        ST.setStatus("Новая анимация")
    end

    function ST.doSave()
        local nm = string.Trim(nameE:GetValue() or "")
        if nm == "" then
            ST.setStatus("Укажите название")
            notification.AddLegacy("Название обязательно", NOTIFY_ERROR, 3)
            return
        end
        local catId = IsValid(catSel) and catSel:GetOptionData(catSel:GetSelectedID()) or "general"
        local catName = IsValid(catSel) and catSel:GetValue() or "Общее"
        ensureFrames()
        --[[ id пустой — сервер сам сделает его из названия (slug). Так
             админу не надо придумывать латиницу для каждой анимации. ]]
        sendAct("save", {
            id = string.Trim(idE:GetValue() or ""),
            name = nm,
            players = chkP:GetChecked(),
            crouch = chkC:GetChecked(),
            walk = chkW:GetChecked(),
            freeze = chkFreeze:GetChecked(),
            hold = chkHold:GetChecked(),
            loop = ST.loop == true,
            speed = ST.speed or 1,
            stance = "idle",
            sequence = "",
            bones = ST.frames[1] and ST.frames[1].bones or {},
            frames = ST.frames,
            cat = catId,
            catName = catName,
        })
        ST.setStatus("Сохранено: " .. nm .. " (" .. #ST.frames .. " кадр(ов))")
    end
end

net.Receive("GRM_SocStudio_Open", function() openStudio() end)

-- Клиентская команда для каталога админки / F4: серверный concommand
-- grm_anim_studio есть только на сервере, поэтому здесь открываем студией локально.
concommand.Add("grm_anim_studio", function()
    -- сначала просим сервер открыть студию (заморозка, синк каталога)
    net.Start("GRM_SocStudio_Act")
        net.WriteString("open")
    net.SendToServer()
    -- и открываем окно у себя
    openStudio()
end)
--[[ Пинг держит серверную заморозку. applyCurrent, а НЕ applyLocal:
     иначе каждые две секунды предпросмотр анимации сбивался бы на
     текущий кадр. ]]
timer.Create("GRM_SocStudio_Ping", 2, 0, function()
    if ST.on then
        sendAct("ping")
        if ST.applyCurrent then ST.applyCurrent() end
    end
end)

print("[GRM Social Studio] client")
