--[[--------------------------------------------------------------------
    GRM Bleedout v1.0 — доработка ранений / оживления / трупа.

    Референс: REVIVE SYSTEM.zip (Improved Revive / IRS). Модели и HUD
    оттуда не копируются. Поведение ложится на GRM.Emergency (911):
      • ползание вместо полной заморозки;
      • удержание E — стабилизация / реанимация с прогрессом;
      • удержание R — самопомощь аптечкой/адреналином;
      • пробел — сдаться (истечь кровью);
      • лимит падений за жизнь;
      • добивание уроном, пока лежит;
      • крик боли и оповещение рядом стоящих.
----------------------------------------------------------------------]]
if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Emergency = GRM.Emergency or {}
local EM = GRM.Emergency
EM.Bleedout = EM.Bleedout or {}
local B = EM.Bleedout
B.Version = "1.0.0"

B.Config = B.Config or {
    crawl          = true,
    crawlSpeed     = 46,
    holdStabilize  = 5,
    holdRevive     = 8,
    holdSelfRevive = 10,
    allowSuicide   = true,
    suicideHold    = 3,
    maxDownsLife   = 3,
    executeDmg     = 28,
    alertRadius    = 1100,
    painInterval   = 5,
}

local PAIN = {
    "vo/npc/male01/pain01.wav", "vo/npc/male01/pain02.wav", "vo/npc/male01/pain03.wav",
    "vo/npc/male01/help01.wav", "vo/npc/male01/imhurt01.wav",
}

local function downed(ply)
    return IsValid(ply) and ply:IsPlayer() and ply:GetNWBool("GRM_911_Downed")
end

local function cfg(k, fallback)
    local c = B.Config or {}
    if c[k] ~= nil then return c[k] end
    return fallback
end

if SERVER then
    util.AddNetworkString("GRM_Bleedout_Alert")

    local function restoreBody(ply)
        if not IsValid(ply) then return end
        local rag = ply._grm911Ragdoll
        if IsValid(rag) then rag:Remove() end
        ply._grm911Ragdoll = nil
        ply:SetNWEntity("GRM_911_Ragdoll", NULL)
        ply:SetNoDraw(false)
        ply:DrawShadow(true)
        if ply._grm911OldCollision then ply:SetCollisionGroup(ply._grm911OldCollision) end
        ply:Freeze(false)
    end

    hook.Add("GRM_911_Downed", "GRM_Bleedout_OnDown", function(ply)
        if not IsValid(ply) then return end
        ply._grmBleedouts = (tonumber(ply._grmBleedouts) or 0) + 1
        local maxD = math.max(0, tonumber(cfg("maxDownsLife", 3)) or 0)
        if maxD > 0 and ply._grmBleedouts > maxD then
            ply._grm911ForceDeath = true
            timer.Simple(0, function()
                if IsValid(ply) and ply:Alive() then ply:Kill() end
            end)
            return
        end
        restoreBody(ply)
        ply:SetNWFloat("GRM_911_Hold", 0)
        ply:SetNWString("GRM_911_HoldKind", "")
        ply:SetNWString("GRM_911_HoldBy", "")
        local r = tonumber(cfg("alertRadius", 1100)) or 1100
        local name = ply:GetNWString("GRM_RPName", "")
        if name == "" then name = ply:Nick() end
        local rec = {}
        for _, p in ipairs((GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()) do
            if IsValid(p) and p ~= ply and p:GetPos():DistToSqr(ply:GetPos()) <= r * r then
                rec[#rec + 1] = p
            end
        end
        if #rec > 0 then
            net.Start("GRM_Bleedout_Alert")
                net.WriteString(name)
            net.Send(rec)
        end
        ply._grmPainAt = CurTime() + 2
    end)

    hook.Add("PlayerSpawn", "GRM_Bleedout_ResetLife", function(ply)
        ply._grmBleedouts = 0
        ply._grmHold = nil
    end)

    hook.Remove("CalcMainActivity", "GRM_911_Lie")
    hook.Remove("StartCommand", "GRM_911_Restrict")
    hook.Add("StartCommand", "GRM_Bleedout_Restrict", function(ply, cmd)
        if not downed(ply) then return end
        cmd:RemoveKey(IN_ATTACK)
        cmd:RemoveKey(IN_ATTACK2)
        cmd:RemoveKey(IN_ATTACK3)
        cmd:RemoveKey(IN_JUMP)
        cmd:RemoveKey(IN_SPEED)
        cmd:RemoveKey(IN_RELOAD)
        if not cfg("crawl", true) then
            cmd:ClearMovement()
        end
    end)

    hook.Remove("EntityTakeDamage", "GRM_911_Damage")
    hook.Add("EntityTakeDamage", "GRM_911_Damage", function(target, dmg)
        if not EM.Config or not EM.Config.enabled then return end
        if not (IsValid(target) and target:IsPlayer() and target:Alive()) then return end
        -- Урон нужен и здесь, и ниже в журнале ран, поэтому берётся один
        -- раз на весь обработчик: раньше `local amt` жил только внутри
        -- ветки «раненый», а запись в журнал читала снаружи глобал nil.
        local amt = dmg:GetDamage()
        if target:GetNWBool("GRM_911_Downed") then
            local need = tonumber(cfg("executeDmg", 28)) or 28
            if amt >= need then
                target._grm911ForceDeath = true
                target:SetNWBool("GRM_911_Downed", false)
                target:Freeze(false)
                timer.Simple(0, function()
                    if IsValid(target) and target:Alive() then target:Kill() end
                end)
                return
            end
            dmg:SetDamage(0)
            return true
        end
        local att = dmg:GetAttacker()
        target._grm911Wounds = target._grm911Wounds or {}
        target._grm911Wounds[#target._grm911Wounds + 1] = {
            at = os.time(), damage = math.floor(amt),
            dtype = dmg:GetDamageType(),
            attacker = IsValid(att) and (att:IsPlayer() and att:Nick() or att:GetClass()) or "мир",
        }
        while #target._grm911Wounds > 12 do table.remove(target._grm911Wounds, 1) end
        if target._grm911ForceDeath then return end
        if dmg:GetDamage() >= target:Health() and EM.Down then
            EM.Down(target, dmg)
            dmg:SetDamage(0)
            return true
        end
    end)

    hook.Add("GRM_911_Revived", "GRM_Bleedout_Speed", function(_, target)
        if not IsValid(target) then return end
        target:SetWalkSpeed(200)
        target:SetRunSpeed(400)
        target:SetMaxSpeed(400)
    end)

    local function lookDowned(ply)
        local tr = ply:GetEyeTrace()
        local ent = tr.Entity
        if IsValid(ent) and ent:GetNWBool("GRM_911_WoundedRagdoll") and IsValid(ent._grm911Patient) then
            ent = ent._grm911Patient
        end
        if downed(ent) and ply:GetPos():DistToSqr(ent:GetPos()) <= 110 * 110 then return ent end
        return nil
    end

    local function finishHold(actor, target, kind)
        if kind == "stabilize" then
            local ok, msg = EM.Stabilize(actor, target)
            if GRM.Notify then GRM.Notify(actor, msg, ok and 80 or 255, ok and 220 or 120, ok and 150 or 110) end
        elseif kind == "revive" then
            local ok, msg = EM.Revive(actor, target)
            if GRM.Notify then GRM.Notify(actor, msg, ok and 80 or 255, ok and 220 or 120, ok and 150 or 110) end
        elseif kind == "self" then
            local ok, msg = EM.Revive(actor, actor)
            if GRM.Notify then GRM.Notify(actor, msg, ok and 80 or 255, ok and 220 or 120, ok and 150 or 110) end
        elseif kind == "suicide" then
            target._grm911ForceDeath = true
            target:SetNWBool("GRM_911_Downed", false)
            target:Freeze(false)
            target:Kill()
        end
    end

    timer.Create("GRM_Bleedout_Think", 0.1, 0, function()
        local now = CurTime()
        local list = (GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()
        for _, ply in ipairs(list) do
            if not IsValid(ply) then
            elseif downed(ply) then
                if cfg("crawl", true) then
                    local sp = tonumber(cfg("crawlSpeed", 46)) or 46
                    ply:SetWalkSpeed(sp)
                    ply:SetRunSpeed(sp)
                    ply:SetMaxSpeed(sp)
                end
                if (ply._grmPainAt or 0) <= now then
                    ply._grmPainAt = now + (tonumber(cfg("painInterval", 5)) or 5) + math.Rand(0, 3)
                    ply:EmitSound(PAIN[math.random(#PAIN)], 70, 100, 0.7)
                end
                -- самопомощь / суицид
                local kind, need = "", 0
                if ply:KeyDown(IN_WALK) and EM.HasReviveItem and select(1, EM.HasReviveItem(ply)) then
                    kind, need = "self", tonumber(cfg("holdSelfRevive", 10)) or 10
                elseif cfg("allowSuicide", true) and ply:KeyDown(IN_JUMP) then
                    kind, need = "suicide", tonumber(cfg("suicideHold", 3)) or 3
                end
                if kind ~= "" then
                    ply._grmHold = ply._grmHold or { t = 0, kind = kind }
                    if ply._grmHold.kind ~= kind then ply._grmHold = { t = 0, kind = kind } end
                    ply._grmHold.t = ply._grmHold.t + 0.1
                    ply:SetNWFloat("GRM_911_Hold", math.Clamp(ply._grmHold.t / need, 0, 1))
                    ply:SetNWString("GRM_911_HoldKind", kind)
                    ply:SetNWString("GRM_911_HoldBy", ply:Nick())
                    if ply._grmHold.t >= need then
                        ply._grmHold = nil
                        ply:SetNWFloat("GRM_911_Hold", 0)
                        finishHold(ply, ply, kind)
                    end
                elseif not ply._grmBeingHeld then
                    ply._grmHold = nil
                    ply:SetNWFloat("GRM_911_Hold", 0)
                    ply:SetNWString("GRM_911_HoldKind", "")
                end
            else
                -- чужой: держит E
                    local tgt = lookDowned(ply)
                if tgt and ply:KeyDown(IN_USE) and not ply:KeyDown(IN_WALK) then
                    local canRevive = EM.IsMedic and select(1, EM.IsMedic(ply))
                    local kind
                    if canRevive then
                        kind = "revive"
                    elseif not tgt:GetNWBool("GRM_911_Stable") then
                        kind = "stabilize"
                    end
                    if kind then
                            local need = kind == "revive" and (tonumber(cfg("holdRevive", 8)) or 8)
                                or (tonumber(cfg("holdStabilize", 5)) or 5)
                            ply._grmHold = ply._grmHold or { t = 0, kind = kind, tgt = tgt }
                            if ply._grmHold.tgt ~= tgt or ply._grmHold.kind ~= kind then
                                ply._grmHold = { t = 0, kind = kind, tgt = tgt }
                            end
                            ply._grmHold.t = ply._grmHold.t + 0.1
                            tgt._grmBeingHeld = true
                            tgt:SetNWFloat("GRM_911_Hold", math.Clamp(ply._grmHold.t / need, 0, 1))
                            tgt:SetNWString("GRM_911_HoldKind", kind)
                            local by = ply:GetNWString("GRM_RPName", "")
                            if by == "" then by = ply:Nick() end
                            tgt:SetNWString("GRM_911_HoldBy", by)
                            if ply._grmHold.t >= need then
                                local k, t = ply._grmHold.kind, ply._grmHold.tgt
                                ply._grmHold = nil
                                if IsValid(t) then
                                    t._grmBeingHeld = nil
                                    t:SetNWFloat("GRM_911_Hold", 0)
                                    finishHold(ply, t, k)
                                end
                            end
                    end
                else
                    if ply._grmHold and IsValid(ply._grmHold.tgt) then
                        ply._grmHold.tgt._grmBeingHeld = nil
                        ply._grmHold.tgt:SetNWFloat("GRM_911_Hold", 0)
                        ply._grmHold.tgt:SetNWString("GRM_911_HoldKind", "")
                    end
                    ply._grmHold = nil
                end
            end
        end
    end)

    print("[GRM Bleedout] server v" .. B.Version .. " loaded")
end

hook.Remove("CalcMainActivity", "GRM_911_Lie")
hook.Add("CalcMainActivity", "GRM_Bleedout_Anim", function(ply, vel)
    if not (IsValid(ply) and ply:GetNWBool("GRM_911_Downed")) then return end
    if vel and vel:Length2D() > 8 then
        return ACT_HL2MP_WALK_CROUCH, -1
    end
    return ACT_HL2MP_IDLE_CROUCH, -1
end)
hook.Add("UpdateAnimation", "GRM_Bleedout_AnimRate", function(ply, vel)
    if not (IsValid(ply) and ply:GetNWBool("GRM_911_Downed")) then return end
    ply:SetPlaybackRate((vel and vel:Length2D() or 0) > 8 and 0.7 or 0.4)
end)

if CLIENT then
    net.Receive("GRM_Bleedout_Alert", function()
        local name = net.ReadString()
        chat.AddText(Color(244, 78, 96), "[911] ", Color(235, 240, 245), name .. " тяжело ранен и нуждается в помощи.")
        surface.PlaySound("buttons/button17.wav")
    end)

    hook.Add("RenderScreenspaceEffects", "GRM_Bleedout_CC", function()
        local lp = LocalPlayer()
        if not IsValid(lp) or not lp:GetNWBool("GRM_911_Downed") then return end
        local tab = {
            ["$pp_colour_addr"] = 0.06,
            ["$pp_colour_addg"] = 0,
            ["$pp_colour_addb"] = 0,
            ["$pp_colour_brightness"] = -0.12,
            ["$pp_colour_contrast"] = 0.85,
            ["$pp_colour_colour"] = 0.35,
            ["$pp_colour_mulr"] = 0,
            ["$pp_colour_mulg"] = 0,
            ["$pp_colour_mulb"] = 0,
        }
        DrawColorModify(tab)
        DrawMotionBlur(0.25, 0.55, 0.02)
    end)

    hook.Add("CalcView", "GRM_Bleedout_CrawlView", function(ply, pos, ang, fov)
        if not IsValid(ply) or not ply:GetNWBool("GRM_911_Downed") then return end
        if IsValid(ply:GetNWEntity("GRM_911_Ragdoll")) then return end
        return {
            origin = pos + Vector(0, 0, -28) - ang:Forward() * 18,
            angles = ang + Angle(8, 0, 6),
            fov = fov,
            drawviewer = true,
        }
    end)

    hook.Add("HUDPaint", "GRM_Bleedout_World", function()
        local lp = LocalPlayer()
        if not IsValid(lp) then return end
        local nowE = (GRM.Time and GRM.Time.Epoch) and math.floor(GRM.Time.Epoch()) or os.time()
        for _, p in ipairs(player.GetAll()) do
            if p ~= lp and downed(p) then
                local pos = p:GetPos() + Vector(0, 0, 42)
                local scr = pos:ToScreen()
                if scr.visible then
                    local left = math.max(0, p:GetNWInt("GRM_911_DeathAt", nowE) - nowE)
                    draw.SimpleText("✚ РАНЕН · " .. left .. " с", "DermaDefaultBold", scr.x, scr.y, Color(244, 78, 96), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
            end
        end
        if not lp:GetNWBool("GRM_911_Downed") then
            local tr = lp:GetEyeTrace()
            local ent = tr.Entity
            if IsValid(ent) and ent:GetNWBool("GRM_911_WoundedRagdoll") then ent = ent._grm911Patient end
            if downed(ent) and lp:GetPos():DistToSqr(ent:GetPos()) <= 110 * 110 then
                local prog = ent:GetNWFloat("GRM_911_Hold", 0)
                local kind = ent:GetNWString("GRM_911_HoldKind", "")
                local label = kind == "revive" and "Реанимация" or "Стабилизация"
                draw.SimpleText("Удерживайте [E] — " .. label, "DermaLarge", ScrW() / 2, ScrH() * 0.72, Color(230, 240, 245), TEXT_ALIGN_CENTER)
                draw.SimpleText("меню помощи: /aid  ·  ALT+E", "DermaDefault", ScrW() / 2, ScrH() * 0.72 + 46, Color(170, 180, 190), TEXT_ALIGN_CENTER)
                if prog > 0 then
                    local w = 280
                    draw.RoundedBox(4, ScrW() / 2 - w / 2, ScrH() * 0.72 + 28, w, 10, Color(20, 20, 28, 220))
                    draw.RoundedBox(4, ScrW() / 2 - w / 2, ScrH() * 0.72 + 28, w * prog, 10, Color(70, 200, 120))
                end
            end
            return
        end
        local left = math.max(0, lp:GetNWInt("GRM_911_DeathAt", nowE) - nowE)
        local prog = lp:GetNWFloat("GRM_911_Hold", 0)
        local kind = lp:GetNWString("GRM_911_HoldKind", "")
        local hint = "Ползком [WASD]  ·  Пробел удержать — сдаться"
        if kind == "self" then hint = "Самопомощь…"
        elseif kind == "suicide" then hint = "Сдаётесь…"
        elseif kind == "revive" then hint = "Вас поднимают: " .. lp:GetNWString("GRM_911_HoldBy", "")
        elseif kind == "stabilize" then hint = "Вас стабилизируют: " .. lp:GetNWString("GRM_911_HoldBy", "")
        end
        draw.RoundedBox(8, ScrW() / 2 - 260, ScrH() - 168, 520, 108, Color(18, 8, 12, 230))
        draw.SimpleText("ТЯЖЁЛОЕ РАНЕНИЕ · " .. left .. " с", "DermaLarge", ScrW() / 2, ScrH() - 140, Color(244, 78, 96), TEXT_ALIGN_CENTER)
        draw.SimpleText(hint, "DermaDefaultBold", ScrW() / 2, ScrH() - 108, Color(230, 235, 240), TEXT_ALIGN_CENTER)
        if prog > 0 then
            draw.RoundedBox(4, ScrW() / 2 - 140, ScrH() - 88, 280, 10, Color(30, 20, 24, 220))
            draw.RoundedBox(4, ScrW() / 2 - 140, ScrH() - 88, 280 * prog, 10, Color(240, 180, 70))
        end
    end)

    print("[GRM Bleedout] client v" .. B.Version .. " loaded")
end
