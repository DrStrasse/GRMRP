--[[--------------------------------------------------------------------
    GRM Perm Tool — закрепление объектов на карте (Задача 9)

    Собственный перма-проп-инструмент GRM. Закреплённый объект переживает
    рестарт сервера и cleanup карты, синхронизирован с проп-протектором
    (GRM.PropProtect) и с системой данных экземпляров (GRM.PermData).

    УПРАВЛЕНИЕ:
      ЛКМ            — закрепить объект (или обновить уже закреплённый)
      Shift + ЛКМ    — закрепить БЕЗ заморозки (объект остаётся подвижным)
      ПКМ            — информация о закреплении
      R (перезарядка)— снять закрепление; сам объект НЕ удаляется

    Вся логика прав, квот и записи — в GRM.Perm (sh_grm_perm_entities.lua).
    Инструмент только вызывает API и показывает результат.
----------------------------------------------------------------------]]
TOOL.Category = "GRM"
TOOL.Name = "#tool.grm_perm_tool.name"
TOOL.Command    = nil
TOOL.ConfigName = ""

TOOL.ClientConVar = {
    owner   = "server", -- server | faction | character
    faction = "",
    freeze  = "1",
    label   = "",
}

if CLIENT then
    -- Задача 12: после унификации названий инструмент стало не найти —
    -- привычное слово «перм» пропало из подписи. Возвращаем его в имя,
    -- сохраняя единый префикс «GRM ».
    language.Add("tool.grm_perm_tool.name", "GRM Перм-проп (закрепление)")
    language.Add("tool.grm_perm_tool.desc", "Перм пропов: закреплённые объекты переживают рестарт сервера и cleanup")
    language.Add("tool.grm_perm_tool.0", "ЛКМ: закрепить/обновить | Shift+ЛКМ: без заморозки | ПКМ: информация | R: снять закрепление")
end

local function notify(ply, msg, r, g, b)
    if not IsValid(ply) then return end
    if GRM and GRM.Notify then
        GRM.Notify(ply, msg, r or 200, g or 210, b or 225)
    else
        ply:ChatPrint(msg)
    end
end

if SERVER then
    util.AddNetworkString("GRM_PermTool_Snapshot")

    -- Отправка клиенту сведений о закреплении для оверлея.
    -- Метод вызывается как self:SendPermSnapshot(...), поэтому первым
    -- аргументом приходит сам TOOL — его игнорируем.
    local function sendSnapshot(_self, ply, ent, rec)
        if not IsValid(ply) then return end
        net.Start("GRM_PermTool_Snapshot")
        net.WriteEntity(IsValid(ent) and ent or NULL)
        net.WriteBool(rec ~= nil)
        if rec then
            net.WriteString(tostring(rec.class or ""))
            net.WriteString(tostring(rec.ownerKind or "server"))
            net.WriteString(tostring(rec.ownerName ~= "" and rec.ownerName or rec.faction or ""))
            net.WriteString(tostring(rec.label or ""))
            net.WriteString(tostring(rec.byName or ""))
            net.WriteBool(rec.freeze ~= false)
        end
        net.Send(ply)
    end

    TOOL.SendPermSnapshot = sendSnapshot
end

-- Собрать опции закрепления из панели инструмента
function TOOL:GatherOpts()
    local ply = self:GetOwner()
    local kind = self:GetClientInfo("owner")
    if kind ~= "server" and kind ~= "faction" and kind ~= "character" then kind = "server" end

    local faction = self:GetClientInfo("faction") or ""
    if kind == "faction" and faction == "" and IsValid(ply) then
        faction = ply:GetNWString("GRM_Faction", "")
    end

    -- Shift на ЛКМ — быстрый способ закрепить без заморозки, не лазая в панель
    local freeze = self:GetClientInfo("freeze") ~= "0"
    if IsValid(ply) and ply:KeyDown(IN_SPEED) then freeze = false end

    return {
        ownerKind = kind,
        faction   = faction,
        freeze    = freeze,
        label     = self:GetClientInfo("label") or "",
    }
end

function TOOL:LeftClick(trace)
    if CLIENT then return true end
    local ply = self:GetOwner()
    if not IsValid(ply) then return false end

    local ent = trace and trace.Entity
    if not IsValid(ent) then
        notify(ply, "Наведите прицел на объект, который нужно закрепить.", 255, 200, 90)
        return false
    end
    if ent:IsPlayer() or ent:IsNPC() then
        notify(ply, "Закреплять можно только объекты, не существ.", 255, 200, 90)
        return false
    end

    if not (GRM and GRM.Perm and GRM.Perm.Add) then
        notify(ply, "Система закрепления не загружена (GRM.Perm отсутствует).", 255, 120, 120)
        return false
    end

    local ok, msg, rec = GRM.Perm.Add(ply, ent, self:GatherOpts())
    if not ok then
        notify(ply, "[ЗАКРЕПЛЕНИЕ] " .. tostring(msg), 255, 120, 120)
        return false
    end

    local what = (msg == "updated") and "обновлено" or "выполнено"
    notify(ply, ("[ЗАКРЕПЛЕНИЕ] %s: %s%s"):format(what, tostring(rec and rec.class or ent:GetClass()),
        (rec and rec.freeze == false) and " (без заморозки)" or ""), 100, 220, 120)
    if self.SendPermSnapshot then self:SendPermSnapshot(ply, ent, rec) end
    return true
end

function TOOL:RightClick(trace)
    if CLIENT then return true end
    local ply = self:GetOwner()
    if not IsValid(ply) then return false end

    local ent = trace and trace.Entity
    if not IsValid(ent) then
        notify(ply, "Наведите прицел на объект.", 255, 200, 90)
        return false
    end
    if not (GRM and GRM.Perm) then return false end

    local rec = GRM.Perm.Info and GRM.Perm.Info(ent) or nil
    if not rec then
        local can, why = GRM.Perm.IsPermable(ent)
        notify(ply, can and "Объект не закреплён. Можно закрепить (ЛКМ)."
            or ("Объект не закреплён. " .. tostring(why)), 255, 200, 90)
        if self.SendPermSnapshot then self:SendPermSnapshot(ply, ent, nil) end
        return true
    end

    local kind = tostring(rec.ownerKind or "server")
    local whose = (kind == "faction" and ("фракция " .. tostring(rec.faction or "?")))
        or (kind == "character" and ("персонаж " .. tostring(rec.ownerName ~= "" and rec.ownerName or rec.owner)))
        or "серверное оборудование"
    notify(ply, ("[ЗАКРЕПЛЕНО] %s | %s | заморозка: %s")
        :format(tostring(rec.class), whose, rec.freeze == false and "нет" or "да"), 120, 210, 255)
    if rec.label and rec.label ~= "" then
        notify(ply, "Метка: " .. tostring(rec.label), 170, 195, 215)
    end
    notify(ply, ("Закрепил: %s (%s)"):format(tostring(rec.byName or "?"),
        rec.at and os.date("%d.%m.%Y %H:%M", tonumber(rec.at)) or "?"), 170, 195, 215)

    if self.SendPermSnapshot then self:SendPermSnapshot(ply, ent, rec) end
    return true
end

function TOOL:Reload(trace)
    if CLIENT then return true end
    local ply = self:GetOwner()
    if not IsValid(ply) then return false end

    local ent = trace and trace.Entity
    if not IsValid(ent) then
        notify(ply, "Наведите прицел на закреплённый объект.", 255, 200, 90)
        return false
    end
    if not (GRM and GRM.Perm and GRM.Perm.Remove) then return false end

    -- Объект остаётся на карте: снятие закрепления ≠ удаление постройки
    local ok, msg = GRM.Perm.Remove(ply, ent, false)
    if not ok then
        notify(ply, "[ЗАКРЕПЛЕНИЕ] " .. tostring(msg), 255, 120, 120)
        return false
    end
    notify(ply, "[ЗАКРЕПЛЕНИЕ] Снято. Объект остался на карте — удалить можно физганом/тулом.", 235, 185, 70)
    if self.SendPermSnapshot then self:SendPermSnapshot(ply, ent, nil) end
    return true
end

if CLIENT then
    local snap = { ent = NULL, has = false, at = 0 }

    net.Receive("GRM_PermTool_Snapshot", function()
        local ent = net.ReadEntity()
        local has = net.ReadBool()
        snap = { ent = ent, has = has, at = CurTime() }
        if has then
            snap.class     = net.ReadString()
            snap.ownerKind = net.ReadString()
            snap.ownerName = net.ReadString()
            snap.label     = net.ReadString()
            snap.byName    = net.ReadString()
            snap.freeze    = net.ReadBool()
        end
    end)

    -- Оверлей живёт 8 секунд после действия: постоянная панель на экране
    -- мешала бы строить, а «мигнувшее» уведомление в чате теряется.
    local PT_GOLD = Color(245, 205, 80)
    local PT_KIND = Color(180, 205, 230)
    local PT_DIM = Color(160, 175, 195)
    local PT_BG = Color(10, 15, 22, 230)

    hook.Add("HUDPaint", "GRM_PermTool_Overlay", function()
        if not snap.has or not IsValid(snap.ent) then return end
        if CurTime() - (snap.at or 0) > 8 then return end

        local wep = LocalPlayer():GetActiveWeapon()
        if not IsValid(wep) or wep:GetClass() ~= "gmod_tool" then return end

        local pos = snap.ent:GetPos():ToScreen()
        if not pos.visible then return end

        local kind = snap.ownerKind or "server"
        local kindText = (kind == "faction" and "ФРАКЦИЯ: " .. (snap.ownerName or "?"))
            or (kind == "character" and "ЛИЧНЫЙ: " .. (snap.ownerName or "?"))
            or "СЕРВЕРНОЕ ОБОРУДОВАНИЕ"

        -- Строки пересобираются каждый кадр (меняется содержимое) — а вот
        -- краски теперь константы загрузки (§6.1.8)
        local lines = {
            { "★ ЗАКРЕПЛЁН НА КАРТЕ", PT_GOLD },
            { kindText, PT_KIND },
            { "Класс: " .. tostring(snap.class or "?"), PT_DIM },
            { "Заморозка: " .. (snap.freeze and "да" or "нет"), PT_DIM },
        }
        if snap.label and snap.label ~= "" then
            lines[#lines + 1] = { "Метка: " .. snap.label, PT_DIM }
        end

        local w, lh = 250, 18
        local h = 12 + #lines * lh
        local x, y = pos.x - w / 2, pos.y - h - 20
        draw.RoundedBox(6, x, y, w, h, PT_BG)
        draw.RoundedBox(6, x, y, 3, h, PT_GOLD)
        for i, ln in ipairs(lines) do
            draw.SimpleText(ln[1], "DermaDefault", x + 12, y + 6 + (i - 1) * lh, ln[2],
                TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end
    end)

    function TOOL.BuildCPanel(panel)
        panel:AddControl("Header", {
            Description = "Закрепление объектов на карте: закреплённый объект переживает рестарт сервера и cleanup, "
                .. "и защищён проп-протектором от чужого физгана и удаления.",
        })

        local combo = panel:ComboBox("Кому принадлежит", "grm_perm_tool_owner")
        combo:AddChoice("Серверное оборудование (только админы)", "server")
        combo:AddChoice("Фракция (руководство фракции)", "faction")
        combo:AddChoice("Личный объект персонажа", "character")

        panel:TextEntry("Фракция (пусто = ваша текущая):", "grm_perm_tool_faction")
        panel:TextEntry("Метка (для списка закреплений):", "grm_perm_tool_label")
        panel:CheckBox("Заморозить объект при закреплении", "grm_perm_tool_freeze")

        panel:Help(
            "УПРАВЛЕНИЕ:\n" ..
            "• ЛКМ — закрепить объект (повторно по закреплённому — обновить позицию и настройки)\n" ..
            "• Shift + ЛКМ — закрепить без заморозки (объект остаётся подвижным)\n" ..
            "• ПКМ — показать сведения о закреплении\n" ..
            "• R — снять закрепление; сам объект при этом НЕ удаляется\n\n" ..
            "ПРАВА:\n" ..
            "• Суперадмин — любые объекты и любой вид владения\n" ..
            "• Руководство фракции (право «perm_manage») — закрепление за фракцией\n" ..
            "• Игроки — только если включён конвар grm_perm_players 1\n\n" ..
            "ОГРАНИЧЕНИЯ:\n" ..
            "• Модули со своим сохранением (CCTV, торговцы, дилер транспорта, серверные\n" ..
            "  стойки и антенны) закреплять не нужно — они сохраняются сами\n" ..
            "• Временные объекты (выброшенные предметы, деньги, руда) закреплять нельзя\n\n" ..
            "ЧАТ-КОМАНДЫ:\n" ..
            "• /permlist — список закреплений на карте\n" ..
            "• /perminfo — сведения об объекте под прицелом\n" ..
            "• /permowner <фракция|me|server> — сменить владение\n" ..
            "• /permload — перезагрузить закрепления с диска"
        )
    end
end
