--[[--------------------------------------------------------------------
    GRM Admin Console v1.0.0 — серверная консоль внутри админ-меню
    (заказ 02.09). Право: server.console (суперадмин;Danger — полная
    власть над cvar'ами и конфигами). Вкладка «Консоль» в /admin шлёт
    строку по каналу GRM_Admin_Console; ответ и эхо коллегам — через
    GRM_Admin_ConsoleOut. Каждая строка: guard-лимит, журнал, аудит.

    Встроенные команды (считаются в Lua, движок не трогаем):
      status · get <cvar> · set <cvar> <val> · bans · history
      ac <команда античита>   — мост к GRM.AntiCheat.AdminCmd
    Всё остальное — raw в game.ConsoleCommand.
----------------------------------------------------------------------]]

GRM = GRM or {}
GRM.Admin = GRM.Admin or {}
local AD = GRM.Admin

--- Аудит в том же формате, что у GRM.Admin Actions: единая лента «mod.*».
local function audit(actor, action, target, details)
    if GRM.Audit and GRM.Audit.Write then
        GRM.Audit.Write("admin", "mod." .. tostring(action), actor,
            { nick = IsValid(target) and target:Nick() or "", steamid64 = IsValid(target) and tostring(target:SteamID64() or "") or "" },
            istable(details) and details or {})
    end
end

-------------------------------------------------------------------
-- КОНСОЛЬ (перенесена из sv_grm_admin_actions; заказ 02.09)
--
-- Вкладка «Консоль» в /admin: то же, что системная консоль сервера, но
-- из игрового меню. Право server.console (суперадмин по умолчанию).
-- Опасность осознанная: строка — это полная власть над cvar'ами и
-- конфигами, поэтому канал закрыт guard'ом, а каждая строка уходит в
-- аудит и в эхо остальным носителям права (никто не «работает тихо»).
--
-- Встроенные команды (без движка, считаются в Lua):
--   status | get <cvar> | set <cvar> <значение> | bans | ac <команда>
-- Всё остальное — raw-строчка в game.ConsoleCommand.
-----------------------------------------------------------------------
local CONSOLE_LOG = {}
AD.ConsoleLog = CONSOLE_LOG

local function logline(text)
    CONSOLE_LOG[#CONSOLE_LOG + 1] = { t = os.time(), text = tostring(text) }
    while #CONSOLE_LOG > 60 do table.remove(CONSOLE_LOG, 1) end
end

local function sanitize(line)
    line = tostring(line or ""):gsub("[\r\n\t]+", " ")
    if #line > 300 then line = string.sub(line, 1, 300) end
    return string.Trim(line)
end

local function consoleRun(actor, line)
    local low = line:lower()
    if low == "" then return "" end
    -- 1) Встроенные команды.
    if low == "status" then
        return ("карта %s · игроков %d/%d · аптайм %d мин · античит: %s")
            :format(tostring(game.GetMap()), #player.GetAll(),
                math.floor(game.MaxPlayers()), math.floor(CurTime() / 60),
                GRM.AntiCheat and "v" .. tostring(GRM.AntiCheat.Version) or "нет")
    elseif low:sub(1, 3) == "get" then
        local name = string.Trim(line:sub(4))
        local cvar = name ~= "" and GetConVar(name) or nil
        if not cvar then return "cvar не найден: " .. name end
        return ("%s = %s (дефолт %s)"):format(name, tostring(cvar:GetString()), tostring(cvar:GetDefault()))
    elseif low:sub(1, 3) == "set" then
        local name, value = string.Trim(line:sub(4)):match("^(%S+)%s*(.*)$")
        name = string.Trim(tostring(name or ""))
        if name == "" then return "формат: set <cvar> <значение>" end
        local cvar = GetConVar(name)
        if not cvar then
            cvar = CreateConVar(name, "0", FCVAR_NONE, "создано консолью админки")
        end
        local old = tostring(cvar:GetString())
        local ok = pcall(cvar.SetString, cvar, string.Trim(tostring(value or "")))
        if not ok then return "cvar защищён или значение не подошло: " .. name end
        return ("%s: %s → %s"):format(name, old, tostring(cvar:GetString()))
    elseif low == "bans" then
        local lines = {}
        local sb = GRM.ServerBan
        if sb and sb.Bans then
            local n = 0
            for sid, rec in pairs(sb.Bans) do
                n = n + 1
                lines[#lines + 1] = ("деморган · %s · %s"):format(sid,
                    isfunction(sb.Describe) and sb.Describe(rec) or "")
            end
            lines[#lines + 1] = "деморганов: " .. n
        else
            lines[#lines + 1] = "деморган: модуль не загружен"
        end
        if sb and isfunction(sb.GlobalList) then
            for _, row in ipairs(sb.GlobalList()) do
                lines[#lines + 1] = ("глобал · %s · %s · %s%s")
                    :format(tostring(row.sid64), tostring(row.name), tostring(row.reason),
                        row.hwid ~= "" and " · hwid" or " · без железа")
            end
        end
        return table.concat(lines, "\n")
    elseif low:sub(1, 2) == "ac" and (low == "ac" or low:sub(3, 3) == " ") then
        if not (GRM.AntiCheat and isfunction(GRM.AntiCheat.AdminCmd)) then
            return "античит не загружен"
        end
        return tostring(GRM.AntiCheat.AdminCmd(actor, string.Trim(line:sub(3))))
    elseif low:sub(1, 7) == "history" then
        local out = {}
        for _, row in ipairs(CONSOLE_LOG) do
            out[#out + 1] = os.date("%H:%M:%S", row.t) .. " " .. row.text
        end
        return #out > 0 and table.concat(out, "\n") or "журнал пуст"
    end
    -- 2) Raw — движку.
    game.ConsoleCommand(line .. "\n")
    return "выполнено: " .. line
end
AD.ConsoleRun = consoleRun

if AD.Net and AD.Net.CONSOLE then
    net.Receive(AD.Net.CONSOLE, function(_, ply)
        if not IsValid(ply) or not isfunction(AD.Can) or AD.Can(ply, "server.console") ~= true then return end
        if GRM.Net and GRM.Net.Guard
            and not GRM.Net.Guard(ply, "adm.console", { rate = 0.5, burst = 3 }, {}) then return end
        local line = sanitize(net.ReadString())
        if line == "" then return end
        local okCall, res = pcall(consoleRun, ply, line)
        local out = okCall and tostring(res or "ок") or ("ошибка: " .. tostring(res))
        logline(("%s: %s  ⇒  %s"):format(ply:Nick(), line, out:gsub("%s+", " ")))
        audit(ply, "console", nil, { line = line, out = string.sub(out, 1, 240) })
        local payload = { admin = tostring(ply:Nick()), line = line, text = out, t = os.time() }
        net.Start(AD.Net.CONSOLE_OUT)
        net.WriteTable(payload)
        net.Send(ply)
        -- Эхо коллегам по праву: работа админа не должна быть невидимой.
        local others = {}
        for _, p in ipairs(player.GetAll()) do
            if IsValid(p) and p ~= ply and isfunction(AD.Can) and AD.Can(p, "server.console") == true then
                others[#others + 1] = p
            end
        end
        if #others > 0 then
            net.Start(AD.Net.CONSOLE_OUT)
            net.WriteTable(payload)
            net.Send(others)
        end
    end)
end
