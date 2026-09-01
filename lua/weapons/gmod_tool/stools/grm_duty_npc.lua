TOOL.Category = "GRM"
TOOL.Name = "#tool.grm_duty_npc.name"
TOOL.Command = nil
TOOL.ConfigName = ""
TOOL.ClientConVar = {
    faction = "",
    title = "ПУНКТ ВЫХОДА НА СЛУЖБУ",
    model = "models/Humans/Group01/Male_07.mdl",
    make_perm = "1",
}

if CLIENT then
    language.Add("tool.grm_duty_npc.name", "GRM Служебный диспетчер")
    language.Add("tool.grm_duty_npc.desc", "NPC для выхода сотрудников на службу и ухода со службы")
    language.Add("tool.grm_duty_npc.0", "ЛКМ: поставить | ПКМ: открыть | R: удалить")
end

function TOOL:LeftClick(tr)
    if CLIENT then return true end
    local ply=self:GetOwner()
    if not IsValid(ply) or not ply:IsSuperAdmin() or not tr or not tr.Hit then return false end
    local ent=ents.Create("grm_duty_npc")
    if not IsValid(ent) then return false end
    local mdl=self:GetClientInfo("model")
    if not util.IsValidModel(mdl or "") then mdl="models/Humans/Group01/Male_07.mdl" end
    local fac=string.sub(string.Trim(self:GetClientInfo("faction") or ""),1,80)
    if not (Factions and Factions[fac]) then
        if GRM.Notify then GRM.Notify(ply,"Сначала укажите точное имя существующей фракции.",255,140,100) end
        ent:Remove()
        return false
    end
    local title=string.sub(string.Trim(self:GetClientInfo("title") or ""),1,80)
    if title=="" then title="ПУНКТ ВЫХОДА НА СЛУЖБУ" end
    -- Поля выставляем ДО Spawn: Initialize берёт модель из них, иначе
    -- диспетчер на мгновение (а после рестарта — навсегда) становился
    -- стандартным гражданином.
    ent.GRMDutyModel = mdl
    ent.GRMDutyFaction = fac
    ent.GRMDutyTitle = title
    ent:SetNWString("GRM_DutyModel",mdl)
    ent:SetNWString("GRM_DutyFaction",fac)
    ent:SetNWString("GRM_DutyTitle",title)
    ent:SetPos(tr.HitPos+tr.HitNormal*2)
    ent:SetAngles(Angle(0,ply:EyeAngles().y+180,0))
    ent:Spawn() ent:Activate()
    if ent.ApplyStationConfig then ent:ApplyStationConfig({faction=fac,title=title,model=mdl}) end
    -- Свой идентификатор станции сразу: иначе два диспетчера рядом делили бы
    -- одну запись, и настройка одного «расползалась» на другого.
    if not ent.GRMDutyID then
        ent.GRMDutyID = util.CRC(table.concat({game.GetMap(), ent:EntIndex(), os.time(), math.random()}, ":"))
        ent:SetNWString("GRM_DutyID", ent.GRMDutyID)
    end
    if self:GetClientInfo("make_perm")~="0" and GRM.Perm and GRM.Perm.Add then GRM.Perm.Add(ply,ent,{ownerKind="server",freeze=true,label="Служебный диспетчер"}) end
    -- Своя запись станции: работает даже без перм-записи.
    if GRM.FactionDuty and GRM.FactionDuty.SaveStation then GRM.FactionDuty.SaveStation(ent) end
    if GRM.Notify then GRM.Notify(ply,"Служебный диспетчер установлен и сохранён за фракцией «"..fac.."».",80,230,150) end
    return true
end

function TOOL:RightClick(tr)
    if CLIENT then return true end
    local ply=self:GetOwner(); local ent=tr and tr.Entity
    if not IsValid(ply) or not IsValid(ent) or ent:GetClass()~="grm_duty_npc" then return false end
    if ply:IsSuperAdmin() and GRM and GRM.FactionDuty and GRM.FactionDuty.OpenAdmin then GRM.FactionDuty.OpenAdmin(ply,ent)
    elseif GRM and GRM.FactionDuty and GRM.FactionDuty.Open then GRM.FactionDuty.Open(ply,ent) end
    return true
end

function TOOL:Reload(tr)
    if CLIENT then return true end
    local ply=self:GetOwner(); local ent=tr and tr.Entity
    if not IsValid(ply) or not ply:IsSuperAdmin() or not IsValid(ent) or ent:GetClass()~="grm_duty_npc" then return false end
    if GRM.Perm and GRM.Perm.Remove then GRM.Perm.Remove(ply,ent,false) end
    if GRM.FactionDuty and GRM.FactionDuty.RemoveStation then GRM.FactionDuty.RemoveStation(ent) end
    ent:Remove()
    return true
end

function TOOL.BuildCPanel(panel)
    panel:AddControl("Header",{Description="Сотрудник фракции по умолчанию находится на службе. У этого NPC он меняет статус, форму и снаряжение."})
    local combo=panel:ComboBox("Фракция (обязательно)","grm_duty_npc_faction");local hookID="GRM_DutyToolPanel_"..tostring(panel)
    local function factionNames()
        local out,seen={},{};local sources={GRM and GRM.FactionDuty and GRM.FactionDuty.ToolFactions,GRM and GRM.QMenu and GRM.QMenu.FactionNames}
        for _,src in ipairs(sources)do for _,name in ipairs(istable(src)and src or{})do name=tostring(name);if name~=""and not seen[name]then seen[name]=true;out[#out+1]=name end end end
        for name in pairs(Factions or{})do name=tostring(name);if name~=""and not seen[name]then seen[name]=true;out[#out+1]=name end end;table.sort(out,function(a,b)return string.lower(a)<string.lower(b)end);return out
    end
    local function refill()
        if not IsValid(combo)then hook.Remove("GRM_DutyToolFactionsUpdated",hookID)return end;local cur=GetConVar("grm_duty_npc_faction");cur=cur and cur:GetString()or"";combo:Clear();local names=factionNames();if#names==0 then combo:SetValue("Загрузка списка фракций...")else combo:SetValue(cur~=""and cur or"Выберите фракцию");for _,name in ipairs(names)do local public=GRM.Factions and GRM.Factions.DisplayName and GRM.Factions.DisplayName(name)or name;combo:AddChoice(public..(public~=name and("  ["..name.."]")or""),name,name==cur)end end
    end
    combo.OnSelect=function(_,_,_,data)if data then RunConsoleCommand("grm_duty_npc_faction",tostring(data))end end
    hook.Add("GRM_DutyToolFactionsUpdated",hookID,refill);local oldRemove=panel.OnRemove;panel.OnRemove=function(self)hook.Remove("GRM_DutyToolFactionsUpdated",hookID);if isfunction(oldRemove)then oldRemove(self)end end
    refill();if GRM and GRM.FactionDuty and GRM.FactionDuty.RequestToolFactions then GRM.FactionDuty.RequestToolFactions()end
    panel:TextEntry("Заголовок","grm_duty_npc_title")
    panel:TextEntry("Модель NPC","grm_duty_npc_model")
    panel:CheckBox("Сохранить на карте","grm_duty_npc_make_perm")
end
