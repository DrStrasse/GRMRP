--[[--------------------------------------------------------------------
    GRM Keypad Weapon v1.1.0 (Код 104, находка 121: спавн строго в +X без
    доп. поворотов) — «классический»
    кейпад-оружие (SWEP class: keypad) в духе патриарховских keypad-модов:
    в руках выглядит как тулган, ЛКМ ставит grm_keypad, ПКМ снимает.

    Отличия от сломавшихся FFD-модов (у владельца вылезали их ошибки):
      • SWEP:ViewModelDrawn защищён от ОБОИХ стилей вызова хука (часть
        аддонов зовёт его «dot-стилем» ViewModelDrawn(vm) — у FFD-свепов
        внутри колон-версии vm становился nil → краш на любой попытке
        отрисовки рук).
      • Каждое действие имеет обратную связь (звук + GRM.Notify): стул
        ffd_keypad этого не делал — «нажал и тишина».
      • Анти-спам: мягкий лимит 24 своих кейпада на игрока для этого
        инструмента (дальше — вежливый отказ).

    ЛКМ: Разместить Кейпад (PIN/режимы — как у grm_keypad)
    ПКМ: Снять свой Кейпад (суперадмин — любой)
----------------------------------------------------------------------]]

AddCSLuaFile()

SWEP.ClassName   = "keypad"
SWEP.PrintName   = "Keypad (GRM)"
SWEP.Category    = "GRM SWEP"
SWEP.Spawnable   = true            -- мягкий лист в категории оружия Q-меню
SWEP.AdminOnly   = false

SWEP.Base        = "weapon_base"
SWEP.HoldType    = "normal"
SWEP.ViewModelFOV  = 62
SWEP.ViewModelFlip = false
SWEP.UseHands    = true
SWEP.ViewModel   = "models/weapons/c_toolgun.mdl"
SWEP.WorldModel  = "models/weapons/w_toolgun.mdl"
SWEP.ShowViewModel  = true
SWEP.ShowWorldModel = true

SWEP.Primary.ClipSize    = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic   = false
SWEP.Primary.Ammo        = "none"
SWEP.Secondary.ClipSize    = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic   = false
SWEP.Secondary.Ammo        = "none"

-- мягкий анти-спам лимит: свои кейпады, поставленные этим инструментом
SWEP.MaxOwnKeypads = 24

function SWEP:Trace()
    local ply = self:GetOwner()
    return util.TraceLine({
        start  = ply:GetShootPos(),
        endpos = ply:GetShootPos() + ply:GetAimVector() * 140,
        filter = ply,
    })
end

function SWEP:CountOwnKeypads(ply)
    local n = 0
    for _, e in ipairs(ents.FindByClass("grm_keypad")) do
        if IsValid(e) and e.KeypadOwner == ply then n = n + 1 end
    end
    return n
end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 0.4)
    if CLIENT then return true end
    local ply = self:GetOwner()
    if not IsValid(ply) then return false end
    local tr = self:Trace()
    if not tr.Hit then return false end

    -- кап: 24 своих кейпада — потолок этого инструмента
    if self:CountOwnKeypads(ply) >= (self.MaxOwnKeypads or 24) then
        if GRM and GRM.Notify then
            GRM.Notify(ply, "Лимит: не больше " .. tostring(self.MaxOwnKeypads or 24) .. " своих кейпадов (снимите лишние ПКМ).", 255, 200, 90)
        end
        return false
    end

    local kat = ents.Create("grm_keypad")
    if not IsValid(kat) then return false end
    -- Код 104: чистый HitNormal:Angle() без поворотов (модель лицом в +X)
    kat:SetPos(tr.HitPos + tr.HitNormal * 1.2)
    kat:SetAngles(tr.HitNormal:Angle())
    kat.KeypadOwner = ply
    kat.KeyGranted = 1
    kat.KeyDenied  = 2
    kat.HoldTime   = 5
    kat:Spawn()
    kat:Activate()
    local pw = "1234"
    if IsValid(ply) and ply.GetInfo then
        local function digits(s)
            s = string.gsub(string.Trim(tostring(s or "")), "%D", "")
            if #s > 10 then s = string.sub(s, 1, 10) end
            return s
        end
        local a = digits(ply:GetInfo("ffd_keypad_password"))
        local b = digits(ply:GetInfo("keypad_password"))
        if a ~= "" then pw = a elseif b ~= "" then pw = b end
    end
    if kat.SetPassword then kat:SetPassword(pw) end
    local phys = kat:GetPhysicsObject()
    if IsValid(phys) then phys:EnableMotion(false) end

    undo.Create("GRM Keypad")
        undo.AddEntity(kat)
        undo.SetPlayer(ply)
    undo.Finish()

    self:EmitSound("buttons/button15.wav", 70, 100)
    if GRM and GRM.Notify then
        GRM.Notify(ply, "Кейпад установлен. Настройка PIN/режимов — тулганом «FFD Keypad» (Q → Инструменты → GRM).", 120, 220, 140)
    end
    return true
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 0.4)
    if CLIENT then return true end
    local ply = self:GetOwner()
    if not IsValid(ply) then return false end
    local tr = self:Trace()
    local ent = tr.Entity
    if not (IsValid(ent) and ent:GetClass() == "grm_keypad") then return false end
    -- Снять можно только СВОЙ кейпад (суперадмин — любой).
    -- IsKeypadOwner (Код 105): учитывает и OwnerSID64, куда попадает
    -- владелец после перм-восстановления кейпада на карте.
    local ownerOK = (ent.KeypadOwner == ply)
    if ent.IsKeypadOwner then ownerOK = ent:IsKeypadOwner(ply) end
    if not ownerOK and not ply:IsSuperAdmin() then
        if GRM and GRM.Notify then GRM.Notify(ply, "Чужой кейпад снять нельзя.", 255, 140, 110) end
        return false
    end
    ent:Remove()
    self:EmitSound("buttons/button6.wav", 70, 110)
    if GRM and GRM.Notify then GRM.Notify(ply, "Кейпад снят.", 180, 220, 120) end
    return true
end

function SWEP:Reload() return true end

function SWEP:Holster() return true end
function SWEP:OnDrop() return true end

-- находка 120: FFD-свепы падали, когда ViewModelDrawn звался «dot-стилем»
-- (self = вм-энтити, vm = nil → vm:GetModel() = nil-call). Принимаем ОБА
-- стиля: метод-колон (self=SWEP, vm=энтити) и dot (единственный аргумент).
function SWEP:ViewModelDrawn(vm)
    if vm == nil then vm = self end -- dot-стиль: первый аргумент и есть вм
    if type(vm) == "table" then return end -- SWEP-таблица без энтити-плашки
    if not IsValid(vm) or vm.GetModel == nil then return end
    local model = vm:GetModel()
    if not isstring(model) or model == "" then return end
    -- Дополнительно ничего не рисуем: тулган рендерит движок.
end

if CLIENT then
    language.Add("keypad", "Keypad (GRM)")
end
