--[[--------------------------------------------------------------------
    FFD Keypad — Toolgun Module (Код 70, форма Кода 107)
    Инструмент установки электронного Кейпада (grm_keypad) — ТОЛЬКО PIN.
    Фракционный доступ переехал в FFD Scanner (стул ffd_scanner). Толл
    и режим-переключатель удалены из панели и спавна.

    ЛКМ: Разместить Кейпад на поверхности
    ПКМ: Скопировать настройки с существующего Кейпада
----------------------------------------------------------------------]]

TOOL.Category = "GRM"
TOOL.Name = "#tool.ffd_keypad.name"
TOOL.Command = nil
TOOL.ConfigName = ""

TOOL.ClientConVar["password"] = "1234"
TOOL.ClientConVar["key_granted"] = "1"
TOOL.ClientConVar["key_denied"] = "2"
TOOL.ClientConVar["hold_time"] = "5"

if CLIENT then
    language.Add("tool.ffd_keypad.name", "GRM Кодовый замок")
    language.Add("tool.ffd_keypad.desc", "Размещает электронный кейпад — доступ ТОЛЬКО по PIN-коду (фракции — у FFD Scanner)")
    language.Add("tool.ffd_keypad.0", "ЛКМ: Установить Кейпад | ПКМ: Скопировать настройки с объекта")
    -- алиас-стул «keypad» (include-обёртка) — те же подписи, иначе #tool.keypad.*
    language.Add("tool.keypad.name", "GRM Кодовый замок")
    language.Add("tool.keypad.desc", "Размещает электронный кейпад — доступ ТОЛЬКО по PIN-коду (фракции — у FFD Scanner)")
    language.Add("tool.keypad.0", "ЛКМ: Установить Кейпад | ПКМ: Скопировать настройки с объекта")
end

-- ============================================================
-- СЕРВЕРНАЯ ЛОГИКА СОЗДАНИЯ КЕЙПАДА
-- ============================================================
if SERVER then
    function TOOL:SpawnKeypad(ply, trace, pass, kGranted, kDenied, holdTime)
        if not IsValid(ply) or not trace.Hit then return false end

        local ent = ents.Create("grm_keypad")
        if not IsValid(ent) then return false end

        -- Код 104 (находка 121): кейпад-модель смотрит лицом в +X,
        -- любые доп. повороты КЛАДУТ её набок. Чистый HitNormal:Angle().
        ent:SetPos(trace.HitPos + trace.HitNormal * 1.2)
        ent:SetAngles(trace.HitNormal:Angle())

        ent.KeypadOwner = ply
        ent.KeyGranted = math.Clamp(tonumber(kGranted) or 1, 1, 9)
        ent.KeyDenied = math.Clamp(tonumber(kDenied) or 2, 1, 9)
        ent.HoldTime = math.max(0.5, tonumber(holdTime) or 5)

        ent:Spawn()
        ent:Activate()

        local pw = (ENT and ENT.SanitizePin and ENT.SanitizePin(pass)) or string.gsub(string.Trim(tostring(pass or "1234")), "%D", "")
        ent:SetPassword(pw ~= "" and pw or "1234")
        ent:SetMode(0) -- только PIN, навсегда
        ent:SetCost(0)
        ent:SetFaction("")

        local phys = ent:GetPhysicsObject()
        if IsValid(phys) then
            phys:EnableMotion(false) -- Автозаморозка на стене
        end

        if duplicator and duplicator.StoreEntityModifier then
            duplicator.StoreEntityModifier(ent, "GRM_KeypadData", {
                password = pw ~= "" and pw or "1234",
                granted  = tonumber(ent.KeyGranted) or 1,
                denied   = tonumber(ent.KeyDenied) or 2,
                hold     = tonumber(ent.HoldTime) or 5,
                owner    = IsValid(ply) and tostring((GRM.Identity and GRM.Identity.CharacterKey and GRM.Identity.CharacterKey(ply)) or ply:SteamID64() or "") or "",
            })
        end

        undo.Create("FFD Keypad")
            undo.AddEntity(ent)
            undo.SetPlayer(ply)
        undo.Finish()

        return true
    end
end

local function toolPin(tool, ply)
    local function digits(s)
        s = string.gsub(string.Trim(tostring(s or "")), "%D", "")
        if #s > 10 then s = string.sub(s, 1, 10) end
        return s
    end
    local a = digits(tool:GetClientInfo("password"))
    local b = (IsValid(ply) and digits(ply:GetInfo("ffd_keypad_password"))) or ""
    local c = (IsValid(ply) and digits(ply:GetInfo("keypad_password"))) or ""
    if a ~= "" and a ~= "1234" then return a end
    if b ~= "" and b ~= "1234" then return b end
    if c ~= "" and c ~= "1234" then return c end
    if a ~= "" then return a end
    if b ~= "" then return b end
    if c ~= "" then return c end
    return "1234"
end

function TOOL:LeftClick(trace)
    if not trace.Hit then return false end
    if CLIENT then return true end

    local ply = self:GetOwner()
    local ent = trace.Entity
    if IsValid(ent) and ent:GetClass() == "grm_keypad" then
        local ownerOK = ent.KeypadOwner == ply
        if ent.IsKeypadOwner then ownerOK = ent:IsKeypadOwner(ply) end
        if not ownerOK and not ply:IsSuperAdmin() then
            if GRM and GRM.Notify then GRM.Notify(ply, "Чужой кейпад: PIN сменить нельзя.", 255, 140, 110) end
            return false
        end
        local pw = toolPin(self, ply)
        ent:SetPassword(pw)
        if duplicator and duplicator.StoreEntityModifier then
            duplicator.StoreEntityModifier(ent, "GRM_KeypadData", {
                password = pw,
                granted  = tonumber(ent.KeyGranted) or 1,
                denied   = tonumber(ent.KeyDenied) or 2,
                hold     = tonumber(ent.HoldTime) or 5,
                owner    = tostring(ent.OwnerSID64 or ""),
            })
        end
        if GRM and GRM.Notify then
            GRM.Notify(ply, "PIN кейпада обновлён (" .. #pw .. " цифр).", 100, 220, 100)
        end
        return true
    end

    local pass = toolPin(self, ply)
    local kGranted = self:GetClientNumber("key_granted", 1)
    local kDenied = self:GetClientNumber("key_denied", 2)
    local holdTime = self:GetClientNumber("hold_time", 5)

    local ok = self:SpawnKeypad(ply, trace, pass, kGranted, kDenied, holdTime)

    if ok and GRM and GRM.Notify then
        GRM.Notify(ply, "FFD Keypad установлен. PIN: " .. #pass .. " цифр. E по экрану — ввод.", 100, 220, 100)
    end

    return ok
end

function TOOL:RightClick(trace)
    local ent = trace.Entity
    if not IsValid(ent) or ent:GetClass() ~= "grm_keypad" then return false end

    if SERVER then
        local ply = self:GetOwner()
        ply:ConCommand(string.format('ffd_keypad_password %q', string.Trim(tostring(ent:GetPassword() or "1234"))))
        ply:ConCommand(string.format('ffd_keypad_hold_time %s', tostring(ent.HoldTime or 5)))
        ply:ConCommand(string.format('ffd_keypad_key_granted %s', tostring(ent.KeyGranted or 1)))
        ply:ConCommand(string.format('ffd_keypad_key_denied %s', tostring(ent.KeyDenied or 2)))

        if GRM and GRM.Notify then
            GRM.Notify(ply, "Настройки Кейпада скопированы!", 100, 220, 255)
        end
    end

    return true
end

-- ============================================================
-- VGUI ПАНЕЛЬ НАСТРОЙКИ В МЕНЮ ИНСТРУМЕНТОВ
-- ============================================================
function TOOL.BuildCPanel(panel)
    panel:AddControl("Header", { Description = "Кодовый замок FFD Keypad — доступ ТОЛЬКО по PIN-коду. Фракционный доступ проверяет FFD Scanner (отдельный инструмент)." })

    -- Код 102/105 (находка 119/122): хелпер DForm — настоящий живой
    -- контрол (голый AddControl("TextEntry") молча пропускался).
    if panel.TextEntry then
        panel:TextEntry("Пароль (PIN-код):", "ffd_keypad_password")
    else
        panel:AddControl("TextBox", { Label = "Пароль (PIN-код):", Command = "ffd_keypad_password" })
    end

    panel:AddControl("Numpad", { Label = "Сигнал успешного входа (Granted):", Command = "ffd_keypad_key_granted" })
    panel:AddControl("Numpad", { Label = "Сигнал отказа (Denied):", Command = "ffd_keypad_key_denied" })

    panel:AddControl("Slider", { Label = "Время задержки сигнала (сек):", Command = "ffd_keypad_hold_time", Type = "Float", Min = 1, Max = 30 })
end
