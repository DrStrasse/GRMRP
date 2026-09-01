include("shared.lua")

surface.CreateFont("GRMDutyNPC_Title", { font="Roboto", size=19, weight=800, extended=true })
surface.CreateFont("GRMDutyNPC_Faction", { font="Roboto", size=22, weight=900, extended=true })
surface.CreateFont("GRMDutyNPC_Text", { font="Roboto", size=13, weight=500, extended=true })
local C_BG=Color(8,14,23,238);local C_OK=Color(48,204,255);local C_OK_LINE=Color(48,204,255,220);local C_BAD=Color(244,78,96);local C_BAD_LINE=Color(244,78,96,220);local C_TEXT=Color(225,238,247);local C_DIM=Color(132,160,178);local LABEL_OFFSET=Vector(0,0,86)

function ENT:Draw()
    self:DrawModel()
    local lp=LocalPlayer()
    if not IsValid(lp) or lp:GetPos():DistToSqr(self:GetPos())>550*550 then return end
    local pos=self:GetPos()+LABEL_OFFSET;local ang=Angle(0,EyeAngles().y-90,90);local fac=self:GetNWString("GRM_DutyFaction","");local display=GRM.Factions and GRM.Factions.DisplayName and GRM.Factions.DisplayName(fac)or fac;local configured=fac~=""and fac~="*"
    cam.Start3D2D(pos,ang,.075)
        draw.RoundedBox(8,-230,-62,460,124,C_BG);surface.SetDrawColor(configured and C_OK_LINE or C_BAD_LINE);surface.DrawOutlinedRect(-230,-62,460,124,2)
        draw.SimpleText(self:GetNWString("GRM_DutyTitle","ПУНКТ ВЫХОДА НА СЛУЖБУ"),"GRMDutyNPC_Title",0,-49,C_TEXT,TEXT_ALIGN_CENTER,TEXT_ALIGN_TOP)
        draw.SimpleText(configured and display or"НЕ НАСТРОЕН","GRMDutyNPC_Faction",0,-15,configured and C_OK or C_BAD,TEXT_ALIGN_CENTER,TEXT_ALIGN_TOP)
        draw.SimpleText(configured and"E — выйти на службу / завершить службу"or"Суперадмин: ПКМ инструментом для настройки","GRMDutyNPC_Text",0,25,C_DIM,TEXT_ALIGN_CENTER,TEXT_ALIGN_TOP)
    cam.End3D2D()
end
