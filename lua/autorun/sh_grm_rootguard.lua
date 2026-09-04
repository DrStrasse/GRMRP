--[[--------------------------------------------------------------------
    GRM Root Guard v1.0.0 (Код 84) — защита от «идиота-суперадмина»

    Заказ владельца (18.07.2026): гарантия, что назначенный суперадмин
    НЕ сможет выполнить деструктивные действия (первый защищённый вид —
    удаление фракций) без подтверждения ВЛАДЕЛЬЦА СЕРВЕРА, привязанного
    к конкретному Steam-профилю.

    СИД-ВЛАДЕЛЬЦЫ — зашиты в SEED_ROOTS ниже (только их нельзя убрать извне
    данными/командами; доп. корни хранятся в data/grm_rootguard.json).

    Семантика FAIL-CLOSED — без явного «да» от root действие не исполняется:
      • запросивший — root          → исполняется сразу;
      • root онлайн                 → всплывающее окно «одобрить/отклонить»;
      • root оффлайн                → заявка висит в очереди (фракции целы);
      • рестарт сервера             → очередь обнуляется = консервативный ОТКАЗ.
    Обхода через UI нет: гейт стоит в центральном обработчике NET_ACTION
    (sh_factions.lua, действие deleteFaction). Прямой lua_run — это уже
    уровень доступа к консоли сервера, из GMod не закрывается в принципе.

    API для модулей сборки:
      GRM.Root.IsRoot(ply)                            → bool
      GRM.Root.Request(actor, kind, title, payload)   → bool allowedNow
          allowedNow=true  → звать своё удаление самому (root);
          allowedNow=false → заявка принята в очередь (см. done-текст).
      GRM.Root.RegisterExecutor(kind, fn(payload)→ok,err)
    Команды root: /root_list, /root_queue, /root_add STEAM_, /root_del STEAM_
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Root = GRM.Root or {}
local RG = GRM.Root

RG.Version  = "1.0.0"
RG.DataFile = "grm_rootguard.json"

-- ═══ ВЛАДЕЛЕЦ СЕРВЕРА (сид; НЕ убирается командами/данными) ═══
local SEED_ROOTS = {
    ["STEAM_0:1:712444114"] = true, -- владелец сборки (заказ 18.07.2026)
}

local NET_ASK    = "GRM_Root_Ask"
local NET_ANSWER = "GRM_Root_Answer"

RG.Queue = RG.Queue or {}          -- очередь заявок (только память: fail-closed)
RG._seq  = RG._seq or 0
RG.Executors = RG.Executors or {}  -- kind → fn(payload) → ok, err

-- ============================================================
-- ОБЩЕЕ
-- ============================================================
function RG.RegisterExecutor(kind, fn)
    if isstring(kind) and isfunction(fn) then RG.Executors[kind] = fn end
end

-- Исполнитель удаления фракции по одобренной заявке (FactionsAPI.DeleteFaction
-- — осознанный экспорт; вызывается ТОЛЬКО здесь, уже после root-«да»).
RG.RegisterExecutor("faction_delete", function(payload)
    local fname = istable(payload) and tostring(payload.faction or "") or ""
    if fname == "" then return false, "пустая фракция" end
    if not (_G.FactionsAPI and _G.FactionsAPI.DeleteFaction) then
        return false, "модуль фракций недоступен"
    end
    local ok, err = _G.FactionsAPI.DeleteFaction(fname)
    if _G.FactionsAPI.Broadcast then pcall(_G.FactionsAPI.Broadcast) end
    return ok, err
end)

-- Одноразовые разрешения на конкретное межфракционное действие. Executor
-- выдаёт permit только после клика root; следующий идентичный net-action
-- его потребляет. Так root guard остаётся fail-closed и не исполняет
-- клиентские payload напрямую.
RG.FactionPermits = RG.FactionPermits or {}
RG.RegisterExecutor("faction_approval", function(payload)
    if not istable(payload) or tostring(payload.token or "") == "" then return false, "битая заявка" end
    RG.FactionPermits[tostring(payload.token)] = CurTime() + 120
    return true
end)

function RG.RequestFactionApproval(actor, action, faction, payload)
    if RG.IsRoot(actor) then return true end
    local raw = util.TableToJSON({ action=tostring(action), faction=tostring(faction), args=payload or {}, sid=actor:SteamID() }, false) or ""
    local token = util.CRC and util.CRC(raw) or raw
    local untilAt = tonumber(RG.FactionPermits[token]) or 0
    if untilAt > CurTime() then RG.FactionPermits[token] = nil return true end
    local title = ("Правка фракции «%s»: %s"):format(tostring(faction), tostring(action))
    RG.Request(actor, "faction_approval", title, { token=token, faction=faction, action=action })
    return false
end

-- ============================================================
-- СЕРВЕР
-- ============================================================
if SERVER then
    util.AddNetworkString(NET_ASK)
    util.AddNetworkString(NET_ANSWER)

    local Cfg = { extra = {}, extra64 = {} } -- доп. корни из data-файла

    local function loadCfg()
        if not file.Exists(RG.DataFile, "DATA") then return end
        local raw = file.Read(RG.DataFile, "DATA") or ""
        if raw == "" then return end
        local okT, t = pcall(util.JSONToTable, raw, false, true) -- нахождение 65
        if not (okT and istable(t)) then
            print("[GRM Root][!] конфиг повреждён — работают только сид-корни")
            return
        end
        for sid, v in pairs(t.extra or {}) do
            if isstring(sid) and v == true then Cfg.extra[sid] = true end
        end
        for s64, v in pairs(t.extra64 or {}) do
            if isstring(s64) and v == true then Cfg.extra64[s64] = true end
        end
    end
    local function saveCfg()
        local ok, txt = pcall(util.TableToJSON, Cfg, true)
        if ok and txt then file.Write(RG.DataFile, txt) end
    end
    loadCfg()

    function RG.IsRoot(ply)
        if not IsValid(ply) then return false end
        if SEED_ROOTS[ply:SteamID()] then return true end
        if Cfg.extra[ply:SteamID()] == true then return true end
        if Cfg.extra64[ply:SteamID64()] == true then return true end
        return false
    end

    local function onlineRoots()
        local out = {}
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if RG.IsRoot(p) then out[#out + 1] = p end
        end
        return out
    end
    RG.OnlineRoots = onlineRoots

    local function notify(ply, msg, r, g, b)
        if not IsValid(ply) then return end
        if GRM.Notify then GRM.Notify(ply, msg, r or 255, g or 200, b or 120)
        else ply:PrintMessage(HUD_PRINTTALK, "[Root] " .. msg) end
    end

    -- снапшот очереди корням (живое окно подтверждений)
    local function pushAsk()
        local roots = onlineRoots()
        if #roots == 0 then return end
        local snap = {}
        for _, q in ipairs(RG.Queue) do
            snap[#snap + 1] = {
                id = q.id, kind = q.kind, title = q.title,
                actor = q.actor_name, actor_sid = q.actor_sid, ts = q.ts,
            }
        end
        for _, r in ipairs(roots) do
            net.Start(NET_ASK)
                net.WriteTable(snap)
            net.Send(r)
        end
    end

    -- Точка входа для защищённых действий. Возврат: true = уже можно (root),
    -- false = ушло в очередь (действие НЕ исполнять!).
    function RG.Request(actor, kind, title, payload)
        if not IsValid(actor) then return false end
        if RG.IsRoot(actor) then return true end
        if not RG.Executors[kind] then return true end -- вид без гейта (страховка от регрессий)
        RG._seq = (RG._seq or 0) + 1
        local q = {
            id = RG._seq, kind = kind, title = tostring(title or kind),
            payload = payload, actor = actor,
            actor_sid = actor:SteamID(), actor_name = actor:Nick(),
            ts = os.time(),
        }
        table.insert(RG.Queue, q)
        print(("[GRM Root] заявка #%d (%s) от %s — ожидает одобрения владельца")
            :format(q.id, q.title, q.actor_name))
        notify(actor, "Отправлено владельцу сервера на подтверждение (заявка #" .. q.id .. "): " .. q.title, 255, 200, 90)
        actor:PrintMessage(HUD_PRINTTALK, "[Root] Действие «" .. q.title .. "» исполнится ТОЛЬКО после подтверждения владельца сервера.")
        local roots = onlineRoots()
        if #roots > 0 then
            pushAsk()
            notify(roots[1], "Заявка #" .. q.id .. " от " .. q.actor_name .. ": " .. q.title, 255, 170, 80)
        end
        return false
    end

    net.Receive(NET_ANSWER, function(_, ply)
        if not IsValid(ply) or not RG.IsRoot(ply) then return end
        local id = tonumber(net.ReadUInt(16)) or 0
        local approve = net.ReadBool() == true
        local idx = nil
        for i, q in ipairs(RG.Queue) do
            if q.id == id then idx = i break end
        end
        if not idx then return end
        local q = table.remove(RG.Queue, idx)
        if approve then
            local ex = RG.Executors[q.kind]
            local okCall, ret1, ret2 = pcall(ex, q.payload)
            local ok = (okCall == true and ret1 ~= false) and true or false
            local errTxt = (okCall and ret1 == false) and tostring(ret2 or "?")
                or (not okCall and tostring(ret1) or nil)
            print(("[GRM Root] заявка #%d ОДОБРЕНА %s (%s): %s — %s")
                :format(q.id, ply:Nick(), ply:SteamID(), q.title, ok and "исполнено" or ("ошибка: " .. tostring(errTxt or "?"))))
            if IsValid(q.actor) then
                if ok then
                    notify(q.actor, "Владелец ОДОБРИЛ заявку #" .. q.id .. ": " .. q.title, 120, 230, 130)
                    q.actor:PrintMessage(HUD_PRINTTALK, "[Root] Одобрено и исполнено: " .. q.title)
                else
                    notify(q.actor, "Заявка #" .. q.id .. " одобрена, но исполнение не удалось: " .. tostring(errTxt), 255, 150, 110)
                end
            end
            notify(ply, "Исполнено: " .. q.title, 120, 230, 130)
        else
            print(("[GRM Root] заявка #%d ОТКЛОНЕНА %s (%s): %s")
                :format(q.id, ply:Nick(), ply:SteamID(), q.title))
            if IsValid(q.actor) then
                notify(q.actor, "Владелец ОТКЛОНИЛ заявку #" .. q.id .. ": " .. q.title, 255, 120, 100)
                q.actor:PrintMessage(HUD_PRINTTALK, "[Root] Отклонено владельцем: " .. q.title)
            end
        end
        pushAsk() -- живое обновление окна (пустая очередь закроет окно)
    end)

    -- root зашёл: приветствие + свежая очередь
    hook.Add("PlayerInitialSpawn", "GRM_Root_Hello", function(ply)
        timer.Simple(6, function()
            if not IsValid(ply) or not RG.IsRoot(ply) then return end
            ply:PrintMessage(HUD_PRINTTALK, "[Root] Защита владельца активна. Командование: /root_list /root_queue /root_add /root_del")
            if #RG.Queue > 0 then
                notify(ply, "Очередь подтверждений: " .. #RG.Queue .. " заявок — окно откроется автоматически.", 255, 190, 90)
                pushAsk()
            end
        end)
    end)

    -- root-команды
    hook.Add("PlayerSay", "GRM_Root_Cmds", function(ply, text)
        local low = string.lower(string.Trim(text or ""))
        if string.sub(low, 1, 6) ~= "/root_" then return end
        if not RG.IsRoot(ply) then
            ply:PrintMessage(HUD_PRINTTALK, "[Root] Команды владельца сервера вам недоступны.")
            return ""
        end
        if low == "/root_list" then
            local names = {}
            for sid in pairs(SEED_ROOTS) do names[#names + 1] = sid .. " (сид)" end
            for sid in pairs(Cfg.extra) do names[#names + 1] = sid end
            for s64 in pairs(Cfg.extra64) do names[#names + 1] = s64 .. " (sid64)" end
            table.sort(names)
            ply:PrintMessage(HUD_PRINTTALK, "[Root] Корни: " .. table.concat(names, ", "))
            return ""
        end
        if low == "/root_queue" then
            if #RG.Queue == 0 then
                ply:PrintMessage(HUD_PRINTTALK, "[Root] Очередь подтверждений пуста.")
            else
                for _, q in ipairs(RG.Queue) do
                    ply:PrintMessage(HUD_PRINTTALK, ("[Root] #%d [%s] %s — от %s (%s)")
                        :format(q.id, q.kind, q.title, q.actor_name, q.actor_sid))
                end
                ply:PrintMessage(HUD_PRINTTALK, "[Root] Окно подтверждения открывается автоматически; обновить — /root_queue ещё раз или дождаться нового пуша.")
                pushAsk()
            end
            return ""
        end
        if string.sub(low, 1, 10) == "/root_add " then
            local sid = string.Trim(string.sub(text, 11))
            if not sid:match("^STEAM_%d:%d:%d+$") and not sid:match("^76561%d+$") then
                ply:PrintMessage(HUD_PRINTTALK, "[Root] Формат: /root_add STEAM_0:x:yyyyyyyy (или SteamID64 76561…)")
                return ""
            end
            if sid:match("^76561") then Cfg.extra64[sid] = true else Cfg.extra[sid] = true end
            saveCfg()
            ply:PrintMessage(HUD_PRINTTALK, "[Root] Добавлен корень: " .. sid .. " (сид-корень изменить нельзя — он зашит в код)")
            print("[GRM Root] добавлен корень " .. sid .. " (оп: " .. ply:Nick() .. ")")
            return ""
        end
        if string.sub(low, 1, 10) == "/root_del " then
            local sid = string.Trim(string.sub(text, 11))
            if SEED_ROOTS[sid] then
                ply:PrintMessage(HUD_PRINTTALK, "[Root] Сид-корня нельзя удалить (он зашит в sh_grm_rootguard.lua).")
                return ""
            end
            Cfg.extra[sid] = nil
            Cfg.extra64[sid] = nil
            saveCfg()
            ply:PrintMessage(HUD_PRINTTALK, "[Root] Удалён из корней (если был): " .. sid)
            return ""
        end
        ply:PrintMessage(HUD_PRINTTALK, "[Root] Команды: /root_list /root_queue /root_add STEAM_ /root_del STEAM_")
        return ""
    end)

    print("[GRM Root] Защита владельца v" .. RG.Version .. " загружена (Код 84). Сид-корней: " .. tostring(table.Count(SEED_ROOTS)))
end

-- ============================================================
-- КЛИЕНТ: окно подтверждений
-- ============================================================
if CLIENT then
    surface.CreateFont("GRMRoot_Title", { font = "Roboto", size = 19, weight = 800, extended = true })
    surface.CreateFont("GRMRoot_Sub",   { font = "Roboto", size = 14, weight = 600, extended = true })
    surface.CreateFont("GRMRoot_Text",  { font = "Roboto", size = 12, weight = 500, extended = true })

    local C = {
        bg = Color(16, 18, 26, 252), head = Color(46, 30, 36, 255),
        panel = Color(30, 34, 46, 245), text = Color(240, 245, 250),
        dim = Color(165, 172, 188), acc = Color(235, 175, 80),
        green = Color(70, 190, 110), red = Color(215, 80, 75),
    }
    local frame = nil

    net.Receive(NET_ASK, function()
        local q = net.ReadTable() or {}
        if IsValid(frame) then frame:Remove() frame = nil end
        if #q == 0 then return end

        frame = vgui.Create("DFrame")
        local f = frame
        f:SetTitle("")
        f:SetSize(620, 120 + #q * 86 + 30)
        f:Center()
        f:MakePopup()
        f:ShowCloseButton(false)
        f.Paint = function(_, w, h)
            draw.RoundedBox(8, 0, 0, w, h, C.bg)
            draw.RoundedBoxEx(8, 0, 0, w, 44, C.head, true, true, false, false)
            draw.SimpleText("ПОДТВЕРЖДЕНИЕ ВЛАДЕЛЬЦА СЕРВЕРА", "GRMRoot_Title", 14, 22, C.acc, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        local x = vgui.Create("DButton", f)
        x:SetText("X") x:SetFont("GRMRoot_Title") x:SetTextColor(color_white)
        x:SetPos(576, 8) x:SetSize(32, 28)
        x.DoClick = function() f:Close() end
        x.Paint = function(self, w, h) draw.RoundedBox(4, 0, 0, w, h, self:IsHovered() and C.red or Color(45, 50, 66)) end

        local head = vgui.Create("DLabel", f)
        head:SetPos(14, 50) head:SetSize(592, 24)
        head:SetFont("GRMRoot_Text") head:SetTextColor(C.dim)
        head:SetText("Защищённые действия исполнятся ТОЛЬКО после вашего «одобрить». Заявок: " .. #q)

        local sc = vgui.Create("DScrollPanel", f)
        sc:SetPos(10, 78) sc:SetSize(600, #q * 86)

        for i, e in ipairs(q) do
            local row = vgui.Create("DPanel", sc)
            row:SetPos(0, (i - 1) * 86) row:SetSize(584, 80)
            row._e = e
            row.Paint = function(self, w, h)
                local e2 = self._e
                draw.RoundedBox(5, 0, 0, w, h, C.panel)
                draw.SimpleText("#" .. tostring(e2.id) .. "  " .. tostring(e2.title), "GRMRoot_Sub", 12, 16, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText("от: " .. tostring(e2.actor) .. " (" .. tostring(e2.actor_sid) .. ")  •  " .. os.date("%d.%m %H:%M", tonumber(e2.ts) or 0), "GRMRoot_Text", 12, 40, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            local yes = vgui.Create("DButton", row)
            yes:SetPos(350, 44) yes:SetSize(105, 28) yes:SetText("")
            yes._id = e.id
            yes.Paint = function(self, w, h)
                draw.RoundedBox(4, 0, 0, w, h, self:IsHovered() and Color(90, 215, 130) or C.green)
                draw.SimpleText("ОДОБРИТЬ", "GRMRoot_Text", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            yes.DoClick = function(self)
                net.Start(NET_ANSWER)
                    net.WriteUInt(self._id, 16)
                    net.WriteBool(true)
                net.SendToServer()
                self:SetEnabled(false)
            end
            local no = vgui.Create("DButton", row)
            no:SetPos(462, 44) no:SetSize(105, 28) no:SetText("")
            no._id = e.id
            no.Paint = function(self, w, h)
                draw.RoundedBox(4, 0, 0, w, h, self:IsHovered() and Color(235, 100, 95) or C.red)
                draw.SimpleText("ОТКЛОНИТЬ", "GRMRoot_Text", w / 2, h / 2, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
            no.DoClick = function(self)
                net.Start(NET_ANSWER)
                    net.WriteUInt(self._id, 16)
                    net.WriteBool(false)
                net.SendToServer()
                self:SetEnabled(false)
            end
        end
    end)

    print("[GRM Root] Клиент защиты владельца загружен")
end

-- Вечер-18: единый словарь slash-команд: имена живого PlayerSay-обработчика
-- вносятся во внешний реестр библиотеки (на режиме сверка идёт ДО ParseSay —
-- без регистрации команда стала бы «неизвестной»).
if GRM and GRM.Chat and GRM.Chat.RegisterExternalCommands then
    GRM.Chat.RegisterExternalCommands({ "/root_", "/root_list", "/root_queue" })
end
