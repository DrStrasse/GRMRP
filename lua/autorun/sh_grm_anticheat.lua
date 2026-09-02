--[[--------------------------------------------------------------------
    GRM AntiCheat v1.0.0 — серверная поведенческая эвристика (заказ 02.09)

    Честная граница метода: GMod-сервер в чистом Lua НЕ сканирует память
    клиента и не видит сигнатур чит-меню. Здесь — то, что ловит самые
    массовые читы без клиентского DLL:

      • AIMBOT. При каждом уроне сравнивается направление прицела с
        направлением на реально подбитую точку. «Silent aim» (попал, глядя
        в сторону) — жирный флаг сразу. Идеальное удержание головы на
        дальних дистанциях (средняя угловая ошибка серии < 1° при >=75%
        попаданий в голову) — второй паттерн. Человеческий скилл в эти
        коридоры не залезает; скрипт — залезает всегда.
      • EXPLOIT. Урон сквозь геометрию (трасс от глаза до точки попадания
        обрывается world-брашем); телепорт-блинк (прыжок позиции быстрее
        любого законного ускорения); глаз внутри solids; полёт без опоры;
        аномальная горизонтальная скорость.
      • RAPIDFIRE. Попадания в секунду против потолка оружия.
      • HWID-SWAP. Смена снимка машины прямо в сессии — сигнал чит-лоадера
        или подмены клиента (ловит GRM.ServerBan, см. v1.3).

    Профиль по SteamID64: счётчик подозрений растёт за каждое
    срабатывание и медленно течёт вниз в простое. Пороги:
      25 — строка в ленту админам (вкладка «Античит» /admin-меню);
      80 — действие по grm_ac_action:
           0 журнал · 1 лента (по умолчанию) · 2 кик ·
           3 бан на сервере (деморган) ·
           4 деморган + ГЛОБАЛЬНЫЙ БАН ПО ЖЕЛЕЗУ: запись в GRM.ServerBan
             уходит со снимком машины и IP и движковым banid, поэтому смена
             SteamID или адреса не помогает — добан прилетает автоматически.

    Иммунитет: суперадмины и флагнутые (ply.GRM_ACImmune — стройка,
    отладка). Команды: ac list | clear [sid|all] | status | flag <sid> <вид>
    — из консоли админки или чатом !ac ... (право ac.admin).

    net: GRM_AC_Feed (таблица/ответ), GRM_AC_Query, GRM_AC_Cmd.
    Права: ac.see, ac.admin.
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.AntiCheat = GRM.AntiCheat or {}
local AC = GRM.AntiCheat
AC.Version = "1.0.0"
AC.Net = { FEED = "GRM_AC_Feed", QUERY = "GRM_AC_Query", CMD = "GRM_AC_Cmd" }
AC.Thresh = { notify = 25, action = 80 }
AC.Weight = {
    silentAim = 35, perfectLock = 30, throughWall = 45, teleport = 25,
    inSolid = 30, speedhack = 15, fly = 20, rapidfire = 20, hwidSwap = 40,
}

if SERVER then
    -- Все каналы модуля — разом (урок SB: недовешенная строка = «unpooled
    -- message name» на первом же net.Start).
    for _, name in pairs(AC.Net) do util.AddNetworkString(name) end

    local C_ENABLE = CreateConVar("grm_ac_enable", "1", FCVAR_ARCHIVE, "Античит GRM: 1 — включён")
    local C_ACTION = CreateConVar("grm_ac_action", "1", FCVAR_ARCHIVE, "Действие на пороге: 0 журнал, 1 лента, 2 кик, 3 деморган, 4 деморган+глобал по железу")
    local C_MINDIST = CreateConVar("grm_ac_min_dist", "500", FCVAR_ARCHIVE, "Минимальная дистанция осмысленных выстрелов (юниты)")
    local C_SILENT = CreateConVar("grm_ac_silent_deg", "18", FCVAR_ARCHIVE, "Угол «смотрел не туда» при попадании, градусы")

    local function enabled() return C_ENABLE:GetBool() end
    local function accountKey(ply) return IsValid(ply) and tostring(ply:SteamID64() or "") or "" end
    local function immune(ply)
        if not enabled() or not IsValid(ply) then return true end
        if ply.GRM_ACImmune then return true end
        if ply:IsSuperAdmin() then return true end
        return false
    end

    local profiles = {}
    local feed = {}

    local function profile(sid64)
        local p = profiles[sid64]
        if not p then
            p = { score = 0, flags = {}, last = 0, lockSum = 0, lockN = 0, lockHead = 0,
                hitWin = 0, hitWinAt = 0, prevX = 0, prevY = 0, prevZ = 0, prevT = 0 }
            profiles[sid64] = p
        end
        return p
    end

    local function describe(ply)
        if IsValid(ply) then
            local rp = ply:GetNWString("GRM_RPName", "")
            return (rp ~= "" and rp or ply:Nick()) .. " (" .. accountKey(ply) .. ")"
        end
        return "?"
    end

    local function pushFeed(text, sev)
        feed[#feed + 1] = { t = os.time(), text = text, sev = sev or "info" }
        while #feed > 60 do table.remove(feed, 1) end
    end
    AC.PushFeed = pushFeed

    local function broadcast(text, sev)
        pushFeed(text, sev)
        print("[GRM AntiCheat] " .. text)
    end

    -------------------------------------------------------------------
    -- НАКАЗАНИЕ ПОРОГА
    -------------------------------------------------------------------
    local function engineBan(sid64, minutes)
        local steamid = util.SteamIDFrom64 and util.SteamIDFrom64(sid64) or nil
        if not steamid then return end
        game.ConsoleCommand(("banid %d %s\n"):format(minutes, steamid))
        game.ConsoleCommand("writeid\n")
    end
    AC.EngineBan = engineBan

    local function act(ply, p, mainFlag)
        local action = C_ACTION:GetInt()
        if action <= 1 then return end
        local label = tostring(mainFlag or "аномалия")
        p.score = 0
        local sid64 = accountKey(ply)
        if action == 2 then
            ply:Kick(("Античит GRM: %s. Разбор — у администрации сервера."):format(label))
        elseif action >= 3 then
            if GRM.ServerBan and isfunction(GRM.ServerBan.Ban) then
                GRM.ServerBan.Ban(nil, ply, 120, "Античит: " .. label)
            end
            if action == 4 and GRM.ServerBan and isfunction(GRM.ServerBan.GlobalBan) then
                -- Глобал-бан ПО ЖЕЛЕЗУ: снимок машины и IP едут в запись —
                -- вход с того же железа под другим аккаунтом добанится сам
                -- (индекс + сверка при отчёте клиента, см. sh_grm_ban.lua).
                GRM.ServerBan.GlobalBan(sid64, describe(ply), 0,
                    "Античит (авто): " .. label, nil, ply.GRM_MachineRep,
                    ply.IPAddress and tostring(ply:IPAddress() or "") or "")
                engineBan(sid64, 0)
                ply:Kick("Античит GRM: глобальный бан по оборудованию.")
            end
        end
    end
    AC.ActOnThreshold = act

    -------------------------------------------------------------------
    -- ФЛАГ
    -------------------------------------------------------------------
    function AC.Flag(ply, kind, note)
        if immune(ply) then return end
        local sid64 = accountKey(ply)
        if sid64 == "" then return end
        local p = profile(sid64)
        local w = AC.Weight[kind] or 10
        p.score = math.min(240, p.score + w)
        p.last = os.time()
        p.flags[#p.flags + 1] = { t = os.time(), kind = kind, note = tostring(note or "") }
        while #p.flags > 20 do table.remove(p.flags, 1) end
        local text = ("%s · %s +%d (всего %d)%s"):format(describe(ply), kind, w, p.score,
            note ~= nil and (" · " .. tostring(note)) or "")
        if p.score >= AC.Thresh.notify then broadcast(text, "suspect") else pushFeed(text, "info") end
        if p.score >= AC.Thresh.action then act(ply, p, kind) end
    end

    -------------------------------------------------------------------
    -- AIMBOT
    -------------------------------------------------------------------
    local function angBetween(a1, a2)
        local d = a1:Dot(a2)
        if d > 1 then d = 1 elseif d < -1 then d = -1 end
        return math.deg(math.acos(d))
    end
    AC.AngleBetween = angBetween

    hook.Add("PlayerHurt", "GRM_AC_Hurt", function(victim, attacker, tr)
        if not enabled() or not IsValid(attacker) or not attacker:IsPlayer() then return end
        if immune(attacker) or victim == attacker then return end
        local from = attacker:EyePos()
        local head = victim:EyePos()
        local hitPos = istable(tr) and tr.HitPos or head
        local dist = from:Distance(head)
        local p = profile(accountKey(attacker))

        -- Урон сквозь геометрию: трасс от глаза до точки попадания обрывается
        -- раньше (фильтр снимает и стрелка, и жертву — преграда это мир/проп).
        if dist > 128 then
            local res = util.TraceLine({
                start = from, endpos = hitPos, filter = { attacker, victim }, mask = MASK_SHOT_HULL,
            })
            local frac = tonumber(res.Fraction) or 1
            local blocked = isfunction(res.HitWorld) and res:HitWorld()
                or (res.Hit and not IsValid(res.Entity))
            if frac < 0.92 and blocked then
                AC.Flag(attacker, "throughWall", ("дистанция %d"):format(math.floor(dist)))
            end
        end

        local minDist = C_MINDIST:GetFloat()
        if dist < minDist then return end
        local aimDir = attacker:EyeAngles():Forward()
        local hitDir = (hitPos - from):GetNormal()
        local diff = angBetween(aimDir, hitDir)
        if diff > C_SILENT:GetFloat() then
            AC.Flag(attacker, "silentAim", ("угол %d° на %d юнитов"):format(math.floor(diff), math.floor(dist)))
            return
        end

        -- Серия идеальных попаданий в голову
        p.lockSum = p.lockSum + diff
        p.lockN = p.lockN + 1
        if hitPos:Distance(head + Vector(0, 0, 6)) < 24 then p.lockHead = p.lockHead + 1 end
        if p.lockN >= 8 then
            local avg = p.lockSum / p.lockN
            local headShare = p.lockHead / p.lockN
            if avg < 1.0 and headShare >= 0.75 then
                AC.Flag(attacker, "perfectLock",
                    ("серия: ошибка %.2f°, голова %d%%, попаданий %d"):format(avg, math.floor(headShare * 100), p.lockN))
            end
            p.lockSum, p.lockN, p.lockHead = 0, 0, 0
        end

        -- Rapidfire: окна попаданий по секундам
        local now = CurTime()
        if now - p.hitWinAt > 1 then p.hitWinAt = now p.hitWin = 0 end
        p.hitWin = p.hitWin + 1
        local weapon = attacker:GetActiveWeapon()
        local cap = 4
        if IsValid(weapon) and isfunction(weapon.GetClip) and weapon:GetClip() > 30 then cap = 8 end
        if p.hitWin > cap then
            AC.Flag(attacker, "rapidfire", ("%d попаданий/с"):format(p.hitWin))
            p.hitWin = 0
        end
    end)

    -------------------------------------------------------------------
    -- ДВИЖЕНИЕ: СЭМПЛЕР
    -- Раз в 0.25 с, скалярные сравнения без аллокаций (бюджет §6.1.8);
    -- дорогие проверки (trace-contents) — только подозревшим.
    -------------------------------------------------------------------
    local SUSPECT_AT = 10
    hook.Add("Think", "GRM_AC_Sample", function()
        if not enabled() then return end
        local now = CurTime()
        if now - (AC._lastSample or 0) < 0.25 then return end
        AC._lastSample = now
        for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(ply) and ply:Alive() and not immune(ply) then
                local sid64 = accountKey(ply)
                if sid64 ~= "" then
                    local p = profile(sid64)
                    local pos = ply:GetPos()
                    local dx, dy, dz = pos.x - p.prevX, pos.y - p.prevY, pos.z - p.prevZ
                    local jump = math.sqrt(dx * dx + dy * dy + dz * dz)
                    if p.prevT > 0 and jump > 2200 and not ply:OnGround()
                        and not IsValid(ply:GetVehicle()) then
                        AC.Flag(ply, "teleport", ("прыжок %d за %.2f с"):format(math.floor(jump), math.max(0.01, now - p.prevT)))
                    end
                    p.prevX, p.prevY, p.prevZ, p.prevT = pos.x, pos.y, pos.z, now
                    if p.score >= SUSPECT_AT and not IsValid(ply:GetVehicle()) then
                        local vel = ply:GetVelocity()
                        local hspeed = math.sqrt(vel.x * vel.x + vel.y * vel.y)
                        if ply:OnGround() and hspeed > 950 then
                            AC.Flag(ply, "speedhack", ("скорость %d"):format(math.floor(hspeed)))
                        elseif not ply:OnGround() and vel.z > 240 and not ply:Crouching() then
                            AC.Flag(ply, "fly", ("вертикаль %d"):format(math.floor(vel.z)))
                        end
                        local eye = ply:EyePos()
                        if util.PointContents(eye) == CONTENTS_SOLID then
                            AC.Flag(ply, "inSolid", "глаз в геометрии")
                        end
                    end
                end
            end
        end
    end)

    -------------------------------------------------------------------
    -- ДЕКЕЙ И ОТСИДКА ПРОФИЛЕЙ
    -------------------------------------------------------------------
    timer.Create("GRM_AC_Decay", 30, 0, function()
        if not enabled() then return end
        for sid64, p in pairs(profiles) do
            if p.score > 0 and os.time() - p.last > 120 then
                p.score = math.max(0, p.score - 2)
            end
            if os.time() - p.last > 600 then
                local alive = false
                for _, ply in ipairs(player.GetAll()) do
                    if IsValid(ply) and accountKey(ply) == sid64 then alive = true break end
                end
                if not alive then profiles[sid64] = nil end
            end
        end
    end)

    -------------------------------------------------------------------
    -- ЛЕНТА ДЛЯ АДМИНОВ (вкладка «Античит»)
    -------------------------------------------------------------------
    local function canSee(ply)
        if not IsValid(ply) then return false end
        if ply:IsSuperAdmin() then return true end
        return GRM.Admin and GRM.Admin.Can and GRM.Admin.Can(ply, "anticheat.see") == true
    end
    local function canAdmin(ply)
        if not IsValid(ply) then return false end
        if ply:IsSuperAdmin() then return true end
        return GRM.Admin and GRM.Admin.Can and GRM.Admin.Can(ply, "anticheat.admin") == true
    end
    AC.CanSee, AC.CanAdmin = canSee, canAdmin

    local function rows()
        local out = {}
        for sid64, p in pairs(profiles) do
            if p.score > 0 then
                local lastKind, lastNote = "", ""
                if #p.flags > 0 then
                    lastKind = tostring(p.flags[#p.flags].kind)
                    lastNote = tostring(p.flags[#p.flags].note)
                end
                local nick = "?"
                for _, ply in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
                    if IsValid(ply) and accountKey(ply) == sid64 then nick = describe(ply) break end
                end
                out[#out + 1] = { sid = sid64, nick = nick, score = p.score,
                    kind = lastKind, note = lastNote, hits = p.lockN, at = p.last }
            end
        end
        table.sort(out, function(a, b) return a.score > b.score end)
        return out
    end
    AC.Rows = rows

    local function pack()
        return { rows = rows(), feed = feed, action = C_ACTION:GetInt(), enabled = enabled() }
    end

    timer.Create("GRM_AC_Broadcast", 5, 0, function()
        for _, ply in ipairs(player.GetAll()) do
            if IsValid(ply) and canSee(ply) then
                net.Start(AC.Net.FEED)
                net.WriteTable(pack())
                net.Send(ply)
            end
        end
    end)

    net.Receive(AC.Net.QUERY, function(_, ply)
        if not canSee(ply) then return end
        net.Start(AC.Net.FEED)
        net.WriteTable(pack())
        net.Send(ply)
    end)

    -------------------------------------------------------------------
    -- АДМИН-КОМАНДЫ (консоль админки: `ac ...`; чат: `!ac ...`)
    -------------------------------------------------------------------
    function AC.AdminCmd(actor, line)
        line = string.Trim(tostring(line or "")):lower()
        if line == "" then line = "list" end
        local op, arg = line:match("^(%a+)%s*(.*)$")
        op = op or "list"
        if op == "list" then
            local n = 0
            for sid, p in pairs(profiles) do
                if p.score > 0 then
                    n = n + 1
                    if IsValid(actor) then
                        local f = p.flags[#p.flags]
                        actor:PrintMessage(HUD_PRINTCONSOLE, ("AC · %s · score %d · %s"):format(
                            sid, p.score, tostring(f and f.kind or "-")))
                    end
                end
            end
            return "подозреваемых: " .. n
        elseif op == "clear" then
            if arg == "" or arg == "all" then
                for _, p in pairs(profiles) do p.score = 0 p.flags = {} end
                return "счётчики обнулены (все)"
            end
            local p = profiles[arg]
            if not p then return "профиль не найден: " .. arg end
            p.score = 0
            p.flags = {}
            return "профиль очищен: " .. arg
        elseif op == "status" then
            return ("античит %s · действие %d · пороги %d/%d"):format(
                enabled() and "вкл" or "выкл", C_ACTION:GetInt(), AC.Thresh.notify, AC.Thresh.action)
        elseif op == "flag" then
            local sid, kind = arg:match("^(%d+)%s+(%a+)$")
            if not sid or not kind then return "формат: ac flag <steamid64> <вид>" end
            for _, ply in ipairs(player.GetAll()) do
                if IsValid(ply) and accountKey(ply) == sid then
                    AC.Flag(ply, AC.Weight[kind] and kind or "silentAim", "ручная отметка")
                    return "отмечен " .. describe(ply)
                end
            end
            return "игрок не найден в сети: " .. sid
        end
        return "команды: list · clear [steamid64|all] · status · flag <sid> <вид>"
    end

    net.Receive(AC.Net.CMD, function(_, ply)
        if not canAdmin(ply) then return end
        if GRM.Net and isfunction(GRM.Net.Guard)
            and not GRM.Net.Guard(ply, "ac.cmd", { rate = 0.5, burst = 4 }, {}) then return end
        local okCall, res = pcall(AC.AdminCmd, ply, net.ReadString())
        net.Start(AC.Net.FEED)
        net.WriteTable({ reply = okCall and tostring(res or "") or ("ошибка: " .. tostring(res)) })
        net.Send(ply)
    end)

    hook.Add("PlayerSay", "GRM_AC_Chat", function(ply, text)
        local line = tostring(text or ""):match("^%!ac%s+(.*)$")
        if not line then return end
        if not canAdmin(ply) then return "" end
        ply:PrintMessage(HUD_PRINTCONSOLE, "[AC] " .. AC.AdminCmd(ply, line))
        return ""
    end)

    -- Смена снимка машины прямо в сессии — признак подмены клиента.
    hook.Add("GRM_AC_HwidSwap", "GRM_AC_Core", function(ply)
        AC.Flag(ply, "hwidSwap", "снимок машины изменился в сессии")
    end)

    if GRM.Modules and GRM.Modules.Register then
        GRM.Modules.Register("anticheat", {
            label = "Поведенческий античит", version = AC.Version,
            Status = function()
                return ("действие %d · записей %d"):format(C_ACTION:GetInt(), table.Count(profiles))
            end,
        })
    end
end
