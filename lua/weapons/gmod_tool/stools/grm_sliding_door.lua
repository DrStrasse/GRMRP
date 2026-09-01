--[[--------------------------------------------------------------------
    GRM Sliding Door Tool (находка 173)
    ЛКМ по пропу — сделать раздвижной дверью (сдвиг с настройками).
    ПКМ по раздвижной двери — открыть/закрыть (тест).
    R — снять механизм (проп вернётся).
    Перм: /permadd по пропу сохранит конфиг; FFD Link — привязка к Keypad/Scanner.
----------------------------------------------------------------------]]
TOOL.Category = "GRM"
TOOL.Name = "#tool.grm_sliding_door.name"
TOOL.Command = nil
TOOL.ConfigName = ""

TOOL.ClientConVar = {
    direction = "left",
    distance = "100",
    speed = "120",
    smooth = "1",
    toggle = "1",
    autoclose = "0",
    closetime = "5",
    soundopen = "",
    soundclose = "",
    soundmove = "",
}

if CLIENT then
    language.Add("tool.grm_sliding_door.name", "GRM Раздвижная дверь")
    language.Add("tool.grm_sliding_door.desc", "Проп → раздвижная дверь со сдвигом и плавностью")
    language.Add("tool.grm_sliding_door.0", "ЛКМ: применить к пропу | ПКМ по двери: открыть/закрыть | R: снять механизм")
end

local function isSliding(ent)
    return IsValid(ent) and GRM.SlidingDoor and GRM.SlidingDoor.IsSliding and GRM.SlidingDoor.IsSliding(ent)
end

-- ЛКМ: применить механизм
function TOOL:LeftClick(trace)
    if CLIENT then return true end
    local ply = self:GetOwner()
    if not IsValid(ply) then return false end
    local ent = trace.Entity
    if not IsValid(ent) or ent:IsPlayer() or ent:IsNPC() or ent:IsWorld() then return false end

    local ok, msg = GRM.SlidingDoor.Apply(ply, ent, {
        direction = self:GetClientInfo("direction"),
        distance = tonumber(self:GetClientInfo("distance")) or 100,
        speed = tonumber(self:GetClientInfo("speed")) or 120,
        smooth = tonumber(self:GetClientInfo("smooth")) or 1,
        toggle = self:GetClientNumber("toggle") == 1,
        autoclose = self:GetClientNumber("autoclose") == 1,
        closeTime = tonumber(self:GetClientInfo("closetime")) or 5,
        soundOpen = self:GetClientInfo("soundopen") or "",
        soundClose = self:GetClientInfo("soundclose") or "",
        soundMove = self:GetClientInfo("soundmove") or "",
    })
    if ok then
        GRM.Notify(ply, "Раздвижная дверь настроена. Свяжите с Keypad/Scanner через FFD Link, сохраните /permadd.", 100, 220, 130)
    else
        GRM.Notify(ply, tostring(msg or "Не удалось"), 255, 120, 100)
    end
    return ok == true
end

-- ПКМ: открыть/закрыть (тест) или удалить механизм (если зажат Shift?)
function TOOL:RightClick(trace)
    if CLIENT then return true end
    local ply = self:GetOwner()
    if not IsValid(ply) then return false end
    local ent = trace.Entity
    if not isSliding(ent) then
        GRM.Notify(ply, "Это не раздвижная дверь: наведите на проп с механизмом.", 255, 180, 90)
        return false
    end
    ent:FadeToggle()
    GRM.Notify(ply, "Дверь: " .. (ent.Sliding_Open and "открыта" or "закрыта"), 100, 220, 255)
    return true
end

-- R: снять механизм
function TOOL:Reload(trace)
    if CLIENT then return true end
    local ply = self:GetOwner()
    if not IsValid(ply) then return false end
    local ent = trace.Entity
    if not isSliding(ent) then
        GRM.Notify(ply, "Наведите на раздвижную дверь.", 255, 180, 90)
        return false
    end
    GRM.SlidingDoor.Remove(ent)
    GRM.Notify(ply, "Механизм раздвижной двери снят, проп возвращён.", 100, 220, 130)
    return true
end

if CLIENT then
    function TOOL.BuildCPanel(panel)
        panel:AddControl("Header", { Description = "Проп → раздвижная дверь: сдвиг с настройками направления, скорости и плавности. Связка с Keypad/Scanner — инструментом FFD Link." })

        local dir = panel:ComboBox("Направление", "grm_sliding_door_direction")
        dir:AddChoice("Влево", "left")
        dir:AddChoice("Вправо", "right")
        dir:AddChoice("Вперёд", "forward")
        dir:AddChoice("Назад", "back")
        dir:AddChoice("Вверх", "up")

        panel:NumSlider("Дистанция сдвига", "grm_sliding_door_distance", 10, 1000, 0)
        panel:NumSlider("Скорость", "grm_sliding_door_speed", 10, 2000, 0)
        panel:NumSlider("Плавность (ease)", "grm_sliding_door_smooth", 0.1, 4, 2)
        panel:CheckBox("Режим переключателя (открыть/закрыть)", "grm_sliding_door_toggle")
        panel:CheckBox("Автозакрытие", "grm_sliding_door_autoclose")
        panel:NumSlider("Задержка автозакрытия (сек)", "grm_sliding_door_closetime", 0.5, 30, 1)

        panel:AddControl("Header", { Description = "ЗВУКИ (пусто = нет звука)" })
        panel:TextEntry("Звук открытия (sound path)", "grm_sliding_door_soundopen")
        panel:TextEntry("Звук закрытия (sound path)", "grm_sliding_door_soundclose")
        panel:TextEntry("Звук движения (sound path)", "grm_sliding_door_soundmove")
        panel:Help("Примеры: doors/door_metal_open1.wav, doors/door_metal_close1.wav, doors/door_move1.wav. Срабатывают: открытие/закрытие — в конце движения; движение — периодически во время сдвига.")

        panel:Help(
            "ЛКМ — применить к пропу (prop_physics/prop_dynamic)\n" ..
            "ПКМ по двери — открыть/закрыть (тест)\n" ..
            "R — снять механизм\n\n" ..
            "СВЯЗЬ С FFD:\n" ..
            "1. Инструмент FFD Link: ЛКМ по Keypad/Scanner → ЛКМ по раздвижной двери\n" ..
            "2. При вводе кода/скане Keypad/Scanner откроет дверь\n\n" ..
            "СОХРАНЕНИЕ:\n" ..
            "/permadd по пропу — переживёт рестарт\n" ..
            "Duplicator (сохранение карты) — тоже поддерживается"
        )
    end
end
