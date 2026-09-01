TOOL.Category = "GRM"
TOOL.Name = "#tool.grm_citadel_core.name"
TOOL.Command=nil
TOOL.ConfigName=""
TOOL.ClientConVar={type="core"}
if CLIENT then language.Add("tool.grm_citadel_core.name", "GRM Ядро Цитадели"); language.Add("tool.grm_citadel_core.desc","Установка ядра тёмной материи и терминала управления"); language.Add("tool.grm_citadel_core.0","ЛКМ: установить. ПКМ: удалить. R: отмена") end
local types={core={class="grm_citadel_core",name="Ядро Цитадели"},terminal={class="grm_citadel_core_terminal",name="Терминал Ядра"},link={class="",name="Связь терминала с ядром"}}
function TOOL:LeftClick(tr)
 if CLIENT then return true end; local p=self:GetOwner(); if not IsValid(p) or not p:IsSuperAdmin() then return false end; local t=types[self:GetClientInfo("type")] or types.core; if t.class=="" then if tr.Entity:GetClass()~="grm_citadel_core_terminal" then return false end; local core=ents.FindByClass("grm_citadel_core")[1]; if not IsValid(core) then return false end; tr.Entity:SetCore(core); p:ChatPrint("Терминал связан с ядром без ограничения расстояния"); return true end; local e=ents.Create(t.class); if not IsValid(e) then return false end; e:SetPos(tr.HitPos+Vector(0,0,8)); e:SetAngles(Angle(0,p:EyeAngles().y+180,0)); e:Spawn(); e:Activate(); if t.class=="grm_citadel_core" then e:Install() end; undo.Create(t.name); undo.AddEntity(e); undo.SetPlayer(p); undo.Finish(); return true
end
function TOOL:RightClick(tr) if CLIENT then return true end; local p=self:GetOwner(); if not IsValid(p) or not p:IsSuperAdmin() then return false end; if IsValid(tr.Entity) and types[tr.Entity:GetClass()=="grm_citadel_core" and "core" or "terminal"] then tr.Entity:Remove(); return true end return false end
function TOOL.BuildCPanel(panel) panel:AddControl("Header",{Description="Установка и подключение энергетического ядра"}); panel:AddControl("ComboBox",{Label="Оборудование",Options={["Ядро Цитадели"]={["grm_citadel_core_type"]="core"},["Терминал Ядра"]={["grm_citadel_core_type"]="terminal"},["Связать терминал с ядром"]={["grm_citadel_core_type"]="link"}}}) end
