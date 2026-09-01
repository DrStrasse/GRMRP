TOOL.Category = "GRM";TOOL.Name = "#tool.grm_quest_tool.name";TOOL.Command=nil;TOOL.ConfigName=""
TOOL.ClientConVar={mode="npc",npc_id="guide",npc_name="Проводник",npc_model="models/Humans/Group01/Male_07.mdl",quest_id="intro",step="1",phase="accept",checkpoint_id=""}
if CLIENT then
 language.Add("tool.grm_quest_tool.name", "GRM Квесты — конструктор");language.Add("tool.grm_quest_tool.desc","NPC, зоны целей и точки кат-сцен");language.Add("tool.grm_quest_tool.0","ЛКМ / ПКМ по режиму · панель инструмента слева")
 local preview={id="",nextBuild=0,zones={},nodes={}}
 local function rebuildPreview(id)
  preview.id=id;preview.nextBuild=CurTime()+.5;preview.zones={};preview.nodes={};local def
  for _,row in ipairs(GRM.Quests.AdminDefinitions or{})do if row.id==id then def=row break end end;if not def then return end
  for i,step in ipairs(def.steps or{})do if step.type=="visit"then local mn,mx;if step.min and step.max then mn=Vector(step.min.x,step.min.y,step.min.z);mx=Vector(step.max.x,step.max.y,step.max.z)elseif step.pos then local c=Vector(step.pos.x,step.pos.y,step.pos.z);local r=step.radius or 120;mn=c-Vector(r,r,32);mx=c+Vector(r,r,32)end;if mn then local c=(mn+mx)*.5;preview.zones[#preview.zones+1]={c=c,mn=mn-c,mx=mx-c,title="Этап "..i..": "..tostring(step.title or"")}end end end
  for phase,nodes in pairs(def.cutscene or{})do local byID={};for _,node in ipairs(nodes or{})do byID[tostring(node.id or"")]=node end;for i,node in ipairs(nodes or{})do local p=Vector(node.pos.x,node.pos.y,node.pos.z);local a=Angle(node.ang.p,node.ang.y,node.ang.r);local linked=byID[tostring(node.next or"")]or nodes[i+1];preview.nodes[#preview.nodes+1]={p=p,a=a,col=i==1 and Color(255,205,70)or(phase=="accept"and Color(80,160,255)or Color(90,220,130)),radius=i==1 and 18 or 12,scale=i==1 and .5 or .35,linked=linked and linked.pos and Vector(linked.pos.x,linked.pos.y,linked.pos.z)or nil,linkCol=linked and linked.transition=="move"and Color(90,220,255)or Color(255,130,90),label=(i==1 and"СТАРТ · "or"")..tostring(node.id or("camera_"..i)).." · "..(node.transition=="move"and"ПРОЛЁТ"or"СКЛЕЙКА")}end end
 end
 hook.Add("PostDrawTranslucentRenderables","GRM_QuestTool_Preview",function(depth,sky,sky3d)
  if depth or sky or sky3d then return end;local ply=LocalPlayer();local wep=IsValid(ply)and ply:GetActiveWeapon();if not IsValid(wep)or wep:GetClass()~="gmod_tool"or not wep.GetMode or wep:GetMode()~="grm_quest_tool"then return end
  local cv=GetConVar("grm_quest_tool_quest_id");local wanted=cv and cv:GetString()or"";if preview.id~=wanted or CurTime()>=preview.nextBuild then rebuildPreview(wanted)end;local face=Angle(0,EyeAngles().y-90,90)
  for _,z in ipairs(preview.zones)do render.DrawWireframeBox(z.c,angle_zero,z.mn,z.mx,Color(242,190,75),true);cam.Start3D2D(z.c+Vector(0,0,12),face,.08);draw.SimpleText(z.title,"DermaDefaultBold",0,0,Color(255,220,110),TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER);cam.End3D2D()end
  for _,n in ipairs(preview.nodes)do render.DrawWireframeSphere(n.p,n.radius,8,8,n.col,true);render.DrawLine(n.p,n.p+n.a:Forward()*90,color_white,true);render.Model({model="models/dav0r/camera.mdl",pos=n.p,angle=n.a,scale=n.scale});if n.linked then render.DrawLine(n.p,n.linked,n.linkCol,true)end;cam.Start3D2D(n.p+Vector(0,0,18),face,.06);draw.RoundedBox(5,-150,-18,300,36,Color(10,16,25,235));draw.SimpleText(n.label,"DermaDefaultBold",0,0,n.col,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER);cam.End3D2D()end
 end)
end
local function questNPC(e)return IsValid(e)and e:GetClass()=="grm_quest_npc"end
function TOOL:LeftClick(tr)
 if CLIENT then return true end;local p=self:GetOwner();if not p:IsSuperAdmin()then return false end;local mode=self:GetClientInfo("mode")
 if mode=="npc"then local e=GRM.Quests.SpawnNPC(self:GetClientInfo("npc_id"),self:GetClientInfo("npc_name"),self:GetClientInfo("npc_model"),tr.HitPos+tr.HitNormal,Angle(0,p:EyeAngles().y+180,0));if IsValid(e)then GRM.Notify(p,"Квестовый NPC создан",100,220,130)return true end
 elseif mode=="zone"then self.ZoneFirst=tr.HitPos;self:SetStage(1);GRM.Notify(p,"Первый угол зоны задан. ПКМ — второй.",100,190,255)return true
 elseif mode=="cutscene"then local ok,why=GRM.Quests.AddCutsceneNode(self:GetClientInfo("quest_id"),self:GetClientInfo("phase"),p);GRM.Notify(p,ok and"Точка кат-сцены добавлена"or why,ok and 100 or 255,ok and 220 or 120,100);return ok end
 --[[ ЧЕКПОИНТ. Ставим точку туда, куда смотрит админ: вписывать
      координаты руками в студии — гарантированная ошибка. ID точки
      подставляет сама студия кнопкой «Поставить точку тулом». ]]
 if mode=="checkpoint"then
  local ok,why=GRM.Quests.SetCheckpointPos(self:GetClientInfo("quest_id"),self:GetClientInfo("checkpoint_id"),tr.HitPos+tr.HitNormal*2)
  GRM.Notify(p,ok and"Чекпоинт поставлен"or why,ok and 100 or 255,ok and 220 or 120,100);return ok
 end
 return false
end
function TOOL:RightClick(tr)
 if CLIENT then return true end;local p=self:GetOwner();if not p:IsSuperAdmin()then return false end;local mode=self:GetClientInfo("mode")
 if mode=="zone"and self.ZoneFirst then local ok,why=GRM.Quests.SetVisitZone(self:GetClientInfo("quest_id"),tonumber(self:GetClientInfo("step")),self.ZoneFirst,tr.HitPos);self.ZoneFirst=nil;self:SetStage(0);GRM.Notify(p,ok and"Зона этапа сохранена"or why,ok and 100 or 255,ok and 220 or 120,100);return ok end
 if questNPC(tr.Entity)and GRM.Quests.OpenAdmin then GRM.Quests.OpenAdmin(p);return true end
 return false
end
function TOOL:Reload(tr)if CLIENT then return true end;local p=self:GetOwner();if not p:IsSuperAdmin()or not questNPC(tr.Entity)then return false end;tr.Entity:Remove();GRM.Quests.SaveDefinitions();GRM.Notify(p,"Квестовый NPC удалён",255,160,90);return true end
--[[ РЕВИЗИЯ ПАНЕЛИ (заказ владельца 28.08: «инструмент квестов
     поредактируй, приведи в соответствие, мб есть что либо лишнее»).

     Убрано:
       • «создайте квест в /grm_quests_admin» — команда осталась, но
         студия давно открывается ПКМ по NPC и из F4; ссылка на консоль
         сбивала с толку;
       • ручной слайдер «Номер этапа» — теперь его выставляет сама
         студия при нажатии «Задать зону тулом». Руками его выставляли
         неверно, и зона уезжала в чужой этап;
       • поля NPC показываются только в режиме NPC, поля кат-сцены —
         только в своём: раньше все семь висели всегда.

     Оставлено ровно то, что нужно в конкретном режиме. ]]
if CLIENT then function TOOL.BuildCPanel(p)
 p:AddControl("Header",{Description="Расстановка в мире: NPC, зоны целей и камеры. Сам квест собирается в Quest Studio (ПКМ по NPC)."})
 local combo=p:ComboBox("Режим","grm_quest_tool_mode");combo:AddChoice("Квестовый NPC","npc");combo:AddChoice("Зона этапа visit","zone");combo:AddChoice("Точка кат-сцены","cutscene");combo:AddChoice("Чекпоинт квеста","checkpoint")

 --[[ Показываем поля по режиму. GMod не пересобирает панель при смене
      конвара, поэтому прячем через Think — иначе пришлось бы заставлять
      игрока переоткрывать тул. ]]
 local mode=GetConVar("grm_quest_tool_mode")
 local npcFields={p:TextEntry("ID NPC","grm_quest_tool_npc_id"),
                  p:TextEntry("Имя NPC","grm_quest_tool_npc_name"),
                  p:TextEntry("Модель NPC","grm_quest_tool_npc_model")}
 local questField=p:TextEntry("ID квеста","grm_quest_tool_quest_id")
 local phase=p:ComboBox("Фаза кат-сцены","grm_quest_tool_phase");phase:AddChoice("При принятии","accept");phase:AddChoice("При завершении","complete")
 local cpField=p:TextEntry("ID чекпоинта","grm_quest_tool_checkpoint_id")
 local help=p:Help("")

 p.Think=function()
  local m=mode and mode:GetString() or "npc"
  for _,f in ipairs(npcFields)do if IsValid(f)then f:SetVisible(m=="npc")end end
  if IsValid(questField)then questField:SetVisible(m~="npc")end
  if IsValid(phase)then phase:SetVisible(m=="cutscene")end
  if IsValid(cpField)then cpField:SetVisible(m=="checkpoint")end
  if IsValid(help)then
   help:SetText(({
    npc="ЛКМ — создать NPC.\nПКМ по NPC — открыть Quest Studio.\nR по NPC — удалить.",
    zone="Номер этапа выставляет Studio: нажмите там «Задать зону тулом».\nЛКМ — первый угол, ПКМ — второй.",
    cutscene="Встаньте в позицию камеры и нажмите ЛКМ.\nПервая точка станет стартовой, следующие свяжутся автоматически.",
    checkpoint="ID точки подставляет Studio кнопкой «Поставить точку тулом».\nЛКМ по земле — поставить красный маркер.",
   })[m] or "")
  end
 end
 end end
