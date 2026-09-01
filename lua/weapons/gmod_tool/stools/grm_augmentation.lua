TOOL.Category = "GRM"
TOOL.Name = "#tool.grm_augmentation.name"
TOOL.Command=nil
TOOL.ConfigName=""
TOOL.ClientConVar={type="station"}
local TYPES={station={name="Станция аугментаций",class="grm_augmentation_station"},pod={name="Капсула аугментации",class="grm_augmentation_pod"}}
if CLIENT then
 language.Add("tool.grm_augmentation.name", "GRM Аугментационное оборудование")
 language.Add("tool.grm_augmentation.desc","Расстановка станций и капсул аугментации")
 language.Add("tool.grm_augmentation.0","ЛКМ: установить. ПКМ: удалить. R: отмена")
end
function TOOL:LeftClick(tr)
 if CLIENT then return true end
 local p=self:GetOwner(); if not IsValid(p) or not p:IsSuperAdmin() then return false end
 local t=TYPES[self:GetClientInfo("type")]; if not t then return false end
 local e=ents.Create(t.class); if not IsValid(e) then return false end
 e:SetPos(tr.HitPos); e:SetAngles(Angle(0,p:EyeAngles().y+180,0)); e:Spawn(); e:Activate()
 local ph=e:GetPhysicsObject(); if IsValid(ph) then ph:EnableMotion(false) end
 undo.Create("Аугментационное оборудование"); undo.AddEntity(e); undo.SetPlayer(p); undo.Finish(); return true
end
function TOOL:RightClick(tr)
 if CLIENT then return true end
 local p=self:GetOwner(); if not IsValid(p) or not p:IsSuperAdmin() then return false end
 if IsValid(tr.Entity) and (tr.Entity:GetClass()=="grm_augmentation_station" or tr.Entity:GetClass()=="grm_augmentation_pod") then tr.Entity:Remove(); return true end
 return false
end
function TOOL.BuildCPanel(panel)
 panel:AddControl("Header",{Description="Установка оборудования аугментации"})
 panel:AddControl("ComboBox",{Label="Оборудование",Options={["Станция аугментаций"]={["grm_augmentation_type"]="station"},["Капсула аугментации"]={["grm_augmentation_type"]="pod"}}})
end
