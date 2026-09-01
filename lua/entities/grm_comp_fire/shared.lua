--[[--------------------------------------------------------------------
    grm_comp_fire — Пожарная станция (диспетчерская)

    Компьютер пожарной службы (Код 58). Чисто диспетчерский пост: журнал
    пожаров (/fire_log) и журнал вызовов (экстренные вызовы 911 категории
    «Пожар»). Кнопки ствола/рукава и закрепления машины убраны по заказу
    владельца 18.08 — это делается у самой машины (/firetruck,
    /firetruck_off) и у рукавного ящика. Суперадмину дополнительно доступны
    админ-меню пожарки: доступы, оповещение, машины, очаги. Доступ:
    суперадмин, бойцы (FightPro) и диспетчеры (Dispatch).
----------------------------------------------------------------------]]
ENT.Type          = "anim"
ENT.Base          = "grm_comp_base"
ENT.PrintName     = "Пожарная станция (диспетчерская)"
ENT.Author        = "GRM"
ENT.Category      = "GRM — RP"
ENT.Spawnable     = true
ENT.AdminSpawnable= true
ENT.RenderGroup   = RENDERGROUP_BOTH

ENT.Model         = "models/props_lab/monitor01a.mdl"
ENT.ModelFallback = "models/props/cs_office/computer.mdl"

--[[ Станция описывается данными, механика — в grm_comp_base:
     Initialize (модель/физика/имя), Draw (табличка), SetupDataTables. ]]
ENT.DefaultComputerName = "ПОЖАРНАЯ СЛУЖБА • ДИСПЕТЧЕРСКАЯ"
ENT.CompTitle    = "ПОЖАРНАЯ СЛУЖБА"
ENT.CompSubtitle = "Диспетчерская станция"
ENT.CompHint     = "Нажмите [E] для входа"
ENT.CompColors = {
    bg    = Color(24, 18, 16, 240),
    title = Color(235, 120, 60),
    sub   = Color(225, 230, 235),
    hint  = Color(165, 175, 185),
}
