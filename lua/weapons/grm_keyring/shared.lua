--[[--------------------------------------------------------------------
    grm_keyring — Связка ключей (двери + транспорт).

    ЗАКАЗ ВЛАДЕЛЬЦА (31.08): «убрать два разных свепа и сделать единый
    свеп — Связка ключей, при подходе к двери или к машине выдаёт
    подсказку, не на машине, а рядом, и подсказка появляется плавно,
    адекватно, небольшая».

    ЧТО БЫЛО. Два независимых свепа: ds_key_swep для дверей (ЛКМ
    запереть, ПКМ отпереть, R меню двери) и vehicle_keys_swep для
    транспорта (ЛКМ замок, ПКМ двери, R личные ключи). Разные правила
    на одинаковых кнопках, две копии поиска цели и подсказки, и игроку
    надо помнить, какую связку доставать.

    ЧТО ЗДЕСЬ. Один предмет на всё. Логику взаимодействия он НЕ
    ДУБЛИРУЕТ: цель ищет и действия выполняет общий модуль
    GRM.Interact — тот же, что работает с пустыми руками. Свеп нужен
    как «ключи в инвентаре» и как привычный способ: достал связку —
    видишь подсказку.

    Старые классы оставлены в сборке ради уже выданных предметов, но
    из продажи убраны: см. sh_grm_vendor.lua.
----------------------------------------------------------------------]]

AddCSLuaFile()

SWEP.PrintName = "Связка ключей"
SWEP.Author = "GRM"
SWEP.Instructions = "Удерживайте ЛКМ у двери или машины — меню действий"
SWEP.Category = "GRM"
SWEP.Spawnable = true
SWEP.AdminSpawnable = true
SWEP.DrawWeaponSelection = true
SWEP.ViewModel = "models/weapons/c_arms_citizen.mdl"
SWEP.WorldModel = ""
SWEP.UseHands = true
SWEP.HoldType = "normal"
SWEP.Slot = 1
SWEP.SlotPos = 2

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

function SWEP:Initialize()
    self:SetHoldType("normal")
end

function SWEP:Deploy()
    self:SetHoldType("normal")
    return true
end

--[[ Кнопки НЕ обрабатываем.

     ЛКМ уже перехватывает общий модуль в StartCommand: короткое
     нажатие проходит наружу, удержание открывает меню. Если бы свеп
     ещё и сам что-то делал по PrimaryAttack, мы получили бы двойное
     срабатывание — дверь щёлкала бы замком вместе с открытием меню.
     Именно на таком дублировании модуль уже ломался 31.08. ]]
function SWEP:PrimaryAttack() end
function SWEP:SecondaryAttack() end
function SWEP:Reload() end

if CLIENT then
    --[[ Подсказку рисует общий модуль (HUDPaint) — здесь ничего не
         дублируем. Свой DrawHUD означал бы вторую плашку поверх
         первой: у старых свепов было ровно так. ]]
    function SWEP:DrawHUD() end
end
