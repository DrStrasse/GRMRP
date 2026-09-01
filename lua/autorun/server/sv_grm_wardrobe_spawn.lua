--[[--------------------------------------------------------------------
    GRM Wardrobe — спавн/удаление гардеробов (Код 73)
    Суперадмин:
      /wardrobe_add            — поставить гардероб в точку прицела
      /wardrobe_remove         — снять гардероб из прицела (чистит конфиг)
      concommand grm_wardrobe_add / grm_wardrobe_remove
    Персистентность энтити — через /permadd (перм-класс grm_wardrobe),
    конфигурация (что шкаф разрешает) — автоматически в
    data/grm_wardrobe/<map>.json по позиции.
----------------------------------------------------------------------]]

if not SERVER then return end

local function aimWardrobe(ply)
    local tr = util.TraceLine({
        start = ply:GetShootPos(),
        endpos = ply:GetShootPos() + ply:GetAimVector() * 220,
        filter = ply,
    })
    return tr.Entity
end

local function spawnWardrobe(ply)
    if not IsValid(ply) or not ply:IsSuperAdmin() then
        if IsValid(ply) then ply:PrintMessage(HUD_PRINTTALK, "[Гардероб] Только для суперадмина.") end
        return
    end
    local tr = util.TraceLine({
        start = ply:GetShootPos(),
        endpos = ply:GetShootPos() + ply:GetAimVector() * 320,
        filter = ply,
    })
    if not tr.Hit then ply:PrintMessage(HUD_PRINTTALK, "[Гардероб] Прицельтесь в пол/стену в зоне досягаемости.") return end

    local ent = ents.Create("grm_wardrobe")
    if not IsValid(ent) then ply:PrintMessage(HUD_PRINTTALK, "[Гардероб] Энтити не зарегистрирована!") return end
    local pos = tr.HitPos + tr.HitNormal * 2
    ent:SetPos(pos)
    local ang = (ply:GetPos() - pos):Angle()
    ent:SetAngles(Angle(0, ang.y, 0))
    ent:Spawn()
    ent:Activate()
    ply:PrintMessage(HUD_PRINTTALK, "[Гардероб] Установлен. Закрепить на карте: /permadd (в прицеле на шкаф). Настройка: E → «Настройка гардероба» (суперадмин).")
    if GRM and GRM.Notify then GRM.Notify(ply, "Гардероб установлен.", 100, 220, 100) end
end

local function removeWardrobe(ply)
    if not IsValid(ply) or not ply:IsSuperAdmin() then return end
    local ent = aimWardrobe(ply)
    if not IsValid(ent) or ent:GetClass() ~= "grm_wardrobe" then
        ply:PrintMessage(HUD_PRINTTALK, "[Гардероб] В прицеле нет гардероба.")
        return
    end
    if GRM and GRM.Wardrobe and GRM.Wardrobe.DeleteCfg then pcall(GRM.Wardrobe.DeleteCfg, ent) end
    ent:Remove()
    ply:PrintMessage(HUD_PRINTTALK, "[Гардероб] Удалён. Если шкаф был закреплён пермом — снимите и перм: /permremove.")
end

concommand.Add("grm_wardrobe_add", spawnWardrobe)
concommand.Add("grm_wardrobe_remove", removeWardrobe)

hook.Add("PlayerSay", "GRM_Wardrobe_Cmds", function(ply, text)
    local low = string.lower(string.Trim(text or ""))
    if low == "/wardrobe_add" or low == "!wardrobe_add" then
        spawnWardrobe(ply)
        return ""
    elseif low == "/wardrobe_remove" or low == "!wardrobe_remove" then
        removeWardrobe(ply)
        return ""
    end
end)

print("[GRM Wardrobe] Команды спавна/удаления загружены")
