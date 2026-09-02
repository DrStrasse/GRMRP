-- GRM Quest Ecosystem v1.0.0 — modern player/admin UI, tracker and cutscenes
if not CLIENT then return end
GRM=GRM or {};GRM.Quests=GRM.Quests or {};local Q=GRM.Quests
Q.ClientRows=Q.ClientRows or {};Q.Cutscene=Q.Cutscene or{active=false}

surface.CreateFont("GRMQ_Title",{font="Roboto",size=26,weight=800,extended=true})
surface.CreateFont("GRMQ_Head",{font="Roboto",size=19,weight=700,extended=true})
surface.CreateFont("GRMQ_Body",{font="Roboto",size=15,weight=500,extended=true})
surface.CreateFont("GRMQ_Small",{font="Roboto",size=12,weight=400,extended=true})
local C={bg=Color(9,14,23,248),panel=Color(19,28,42,248),card=Color(28,39,57,250),hover=Color(39,55,78),blue=Color(65,145,240),green=Color(70,205,125),red=Color(220,75,80),yellow=Color(242,190,75),text=Color(238,244,252),dim=Color(145,160,180)}
local function frame(title,w,h)
 local f=vgui.Create("DFrame");f:SetSize(math.min(w,ScrW()-40),math.min(h,ScrH()-40));f:Center();f:SetTitle("");f:ShowCloseButton(true);f:MakePopup();f.Paint=function(_,pw,ph)draw.RoundedBox(10,0,0,pw,ph,C.bg);draw.RoundedBoxEx(10,0,0,pw,48,Color(16,25,39),true,true,false,false);draw.SimpleText(title,"GRMQ_Title",18,24,C.text,TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER)end;return f
end
local function button(parent,text,x,y,w,h,color,fn)
 local b=vgui.Create("DButton",parent);b:SetPos(x,y);b:SetSize(w,h);b:SetText("");b.DoClick=function(self)surface.PlaySound("buttons/button15.wav");if fn then fn(self)end end
 b.Paint=function(self,pw,ph)local base=color or Color(48,64,86);local col=self:IsDown()and Color(math.max(0,base.r-22),math.max(0,base.g-22),math.max(0,base.b-22))or(self:IsHovered()and Color(math.min(255,base.r+22),math.min(255,base.g+22),math.min(255,base.b+22))or base);draw.RoundedBox(8,0,0,pw,ph,col);surface.SetDrawColor(self:IsHovered()and Color(155,205,255,210)or Color(85,110,145,170));surface.DrawOutlinedRect(0,0,pw,ph,1);draw.SimpleText(text,"GRMQ_Body",pw/2,ph/2+(self:IsDown()and 1 or 0),C.text,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)end;return b
end
local function label(parent,text,x,y,w,h,font,color)
 local l=vgui.Create("DLabel",parent);l:SetPos(x,y);l:SetSize(w,h);l:SetText(text or "");l:SetFont(font or"GRMQ_Body");l:SetTextColor(color or C.text);l:SetWrap(true);return l
end
local function objectiveText(def,p)
 local step=def and def.steps and def.steps[tonumber(p and p.step)or 1];if not step then return"Завершение..."end
 local suffix="";if step.type=="event"or step.type=="item"then suffix=("  %d/%d"):format(tonumber(p.count)or 0,tonumber(step.count)or 1)end
 return tostring(step.title or"Этап")..suffix
end
local function playerOp(op,id)net.Start("GRM_Quest_PlayerOp")net.WriteString(op)net.WriteString(id or "")net.SendToServer()end

net.Receive("GRM_Quest_Sync",function()Q.ClientRows=net.ReadTable()or {}end)
--[[ МУЗЫКА КВЕСТА (заказ владельца 28.08).

     Зациклённый трек играем через sound.PlayURL-независимый путь —
     обычный CreateSound по имени файла: он умеет останавливаться, в
     отличие от surface.PlaySound, который выстреливает и забывает.
     Пустой путь означает «выключить»: так сервер глушит фоновую музыку
     в конце квеста. ]]
net.Receive("GRM_Quest_Music", function()
    local path = net.ReadString()
    local volume = net.ReadFloat()
    local loop = net.ReadBool()

    -- Прошлый зациклённый трек всегда снимаем: иначе они наложатся.
    if Q._musicPatch then
        pcall(function() Q._musicPatch:Stop() end)
        Q._musicPatch = nil
    end
    if path == "" then return end

    if loop then
        local lp = LocalPlayer()
        if not IsValid(lp) then return end
        --[[ CreateSound требует entity-владельца: привязываем к игроку,
             чтобы трек не обрывался при смене комнаты и был слышен
             независимо от позиции. ]]
        if not isfunction(CreateSound) then return end
        local ok, patch = pcall(CreateSound, lp, path)
        if ok and patch then
            Q._musicPatch = patch
            pcall(function()
                patch:SetSoundLevel(0)      -- 0 = слышно везде, без затухания
                patch:PlayEx(math.Clamp(volume or 1, 0.1, 1), 100)
            end)
        end
    else
        surface.PlaySound(path)
    end
end)

--[[ Смерть и смена карты не должны оставлять трек висеть. ]]
hook.Add("PlayerDeath", "GRM_Quest_MusicStop", function(ply)
    if ply == LocalPlayer() and Q._musicPatch then
        pcall(function() Q._musicPatch:Stop() end)
        Q._musicPatch = nil
    end
end)

net.Receive("GRM_Quest_Notice",function()local ok=net.ReadBool();local msg=net.ReadString();local sound=net.ReadString();local duration=net.ReadFloat();local banner=net.ReadBool();local heading=net.ReadString();surface.PlaySound(sound~=""and sound or(ok and"buttons/button14.wav"or"buttons/button10.wav"));if notification then notification.AddLegacy(msg,ok and NOTIFY_GENERIC or NOTIFY_ERROR,duration)end;if banner then Q.NoticeToast={text=msg,heading=heading,untilAt=CurTime()+duration,started=CurTime()}end end)
--[[ Кадровые краски. Все создаются один раз при загрузке файла: тост,
     диалог и трекер перерисовываются каждый кадр, и любой Color() внутри
     их Paint = мусорная таблица на кадр (§6.1.8). Динамический alfa
     (затухание тоста) пишется в .a постоянного цвета — Color в GMod таблица. ]]
local QCOL = {
    toastBg = Color(10, 18, 30, 235), toastHead = Color(242, 190, 75), toastText = Color(245, 248, 252),
    dlgBg = Color(12, 16, 24, 236), dlgClose = Color(40, 48, 60),
    optHover = Color(36, 52, 74), opt = Color(22, 30, 44),
    npcDone = Color(35, 75, 55), npcDoneHover = Color(31, 70, 52),
    stepDone = Color(32, 72, 53),
    trackBg = Color(10, 16, 25, 220), trackChip = Color(14, 24, 38, 225),
}
local QT_TARGET_V = Vector(0, 0, 0)
hook.Add("HUDPaint","GRM_Quest_CompletionNotice",function()
 local t=Q.NoticeToast;if not t then return end
 if CurTime()>t.untilAt then Q.NoticeToast=nil return end
 local fade=math.Clamp(math.min((CurTime()-t.started)*4,(t.untilAt-CurTime())*3),0,1)
 local w=math.min(620,ScrW()-60);local x=ScrW()/2-w/2;local y=105
 QCOL.toastBg.a=math.floor(235*fade)
 draw.RoundedBox(12,x,y,w,78,QCOL.toastBg)
 surface.SetDrawColor(242,190,75,math.floor(255*fade));surface.DrawOutlinedRect(x,y,w,78,2)
 QCOL.toastHead.a=math.floor(255*fade)
 draw.SimpleText(t.heading~=""and t.heading or"УВЕДОМЛЕНИЕ","GRMQ_Small",ScrW()/2,y+16,QCOL.toastHead,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
 QCOL.toastText.a=math.floor(255*fade)
 draw.SimpleText(t.text,"GRMQ_Head",ScrW()/2,y+48,QCOL.toastText,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
end)

local function dialogueNodes(value)
 if isstring(value)then return value~=""and{{id="legacy",text=value,choices={}}}or{}end
 return istable(value)and(value.nodes or value)or{}
end
local function playDialogue(npcName,nodes,onAction)
 nodes=dialogueNodes(nodes);if#nodes==0 then if onAction then onAction("finish")end return end
 if IsValid(Q.TalkFrame)then Q.TalkFrame:Remove()end
 local f=vgui.Create("DFrame");Q.TalkFrame=f
 f:SetSize(math.min(720,ScrW()-80),math.min(420,ScrH()-80));f:SetPos(40,ScrH()-f:GetTall()-48)
 f:SetTitle("");f:ShowCloseButton(false);f:MakePopup();f:SetDraggable(false)
 f.Paint=function(_,w,h)
  draw.RoundedBox(10,0,0,w,h,QCOL.dlgBg)
  surface.SetDrawColor(70,110,150,80);surface.DrawOutlinedRect(0,0,w,h,1)
 end
 local byID={};for i,n in ipairs(nodes)do byID[tostring(n.id or i)]=i end;local index=1
 local function show(i)
  index=math.Clamp(tonumber(i)or 1,1,#nodes);local n=nodes[index]
  -- f — это DFrame: обычный :Clear() сносил его служебные кнопки, после
  -- чего PerformLayout окна спамил «NULL Panel» в консоль каждый кадр.
  if GRM.UI and GRM.UI.SafeClear then GRM.UI.SafeClear(f) else f:Clear() end
  local close=vgui.Create("DButton",f);close:SetSize(28,24);close:SetPos(f:GetWide()-36,10);close:SetText("")
  close.Paint=function(s,w,h)draw.RoundedBox(4,0,0,w,h,s:IsHovered()and C.red or QCOL.dlgClose);draw.SimpleText("X","GRMQ_Body",w/2,h/2,color_white,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)end
  close.DoClick=function()f:Close()end
  label(f,tostring(n.speaker~=""and n.speaker or npcName),20,14,f:GetWide()-70,26,"GRMQ_Head",C.yellow)
  local wrap=vgui.Create("DLabel",f);wrap:SetPos(20,46);wrap:SetSize(f:GetWide()-40,110);wrap:SetWrap(true);wrap:SetFont("GRMQ_Body");wrap:SetTextColor(C.text);wrap:SetText(tostring(n.text or""))
  local choices=istable(n.choices)and n.choices or{}
  local function advance(nextID,action)
   if action and action~=""and onAction then onAction(action)end
   if action=="close"or action=="accept"then f:Close();return end
   local ni=byID[tostring(nextID or"")]or(index+1)
   if ni>#nodes then if onAction then onAction("finish")end;f:Close()else show(ni)end
  end
  local y=168
  local function opt(num,text,fn)
   local b=vgui.Create("DButton",f);b:SetPos(20,y);b:SetSize(f:GetWide()-40,42);b:SetText("")
   b.Paint=function(s,w,h)
    draw.RoundedBox(6,0,0,w,h,s:IsHovered()and QCOL.optHover or QCOL.opt)
    draw.SimpleText(tostring(num),"GRMQ_Head",16,h/2,C.blue,TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER)
    draw.SimpleText(text,"GRMQ_Body",42,h/2,C.text,TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER)
   end
   b.DoClick=function()surface.PlaySound("buttons/button15.wav");fn()end
   y=y+48
  end
  if#choices>0 then
   for ci,ch in ipairs(choices)do opt(ci,ch.text~=""and ch.text or("Ответ "..ci),function()advance(ch.next,ch.action)end)end
  else
   opt(1,index<#nodes and"Продолжить"or"Завершить разговор",function()advance(n.next,"")end)
  end
  label(f,"Esc — выйти",20,f:GetTall()-28,200,18,"GRMQ_Small",C.dim)
 end
 show(1)
end
Q._previewDialogue=playDialogue

local function openNPC()
 local npc=net.ReadEntity();local npcName=net.ReadString();local rows=net.ReadTable()or {};local f=frame(npcName,760,600)
 label(f,"ЗАДАНИЯ И ДИАЛОГИ",20,58,300,24,"GRMQ_Small",C.yellow)
 local scroll=vgui.Create("DScrollPanel",f);scroll:SetPos(18,86);scroll:SetSize(300,490)
 local detail=vgui.Create("DPanel",f);detail:SetPos(330,58);detail:SetSize(412,518);detail.Paint=function(_,w,h)draw.RoundedBox(9,0,0,w,h,C.panel)end
 local function show(row)
  detail:Clear();local d,p=row.definition,row.progress
  label(detail,d.title,18,18,376,34,"GRMQ_Head")
  --[[ Категория и ID рядом (заказ владельца 28.08): ID нужен админу
       прямо в игре — для команд сброса и ссылок из других квестов. ]]
  label(detail,(d.category~=""and d.category or"КВЕСТ").."   ·   "..tostring(d.id or""),18,50,376,18,"GRMQ_Small",C.yellow)
  label(detail,d.summary,18,78,376,100,"GRMQ_Body",C.dim)
  local state=not p and"Доступно"or(p.status=="completed"and"Завершено"or objectiveText(d,p));label(detail,state,18,185,376,48,"GRMQ_Head",p and p.status=="completed"and C.green or C.text)
  local dialogue=not p and d.dialogue.offer or(p.status=="active"and d.dialogue.active or d.dialogue.complete);local nodes=dialogueNodes(dialogue);local preview=nodes[1]and nodes[1].text or"Мне есть что тебе предложить.";label(detail,preview,18,245,376,105,"GRMQ_Body",C.text)
  if#nodes>0 then button(detail,"▶  Начать диалог ("..#nodes.." реплик)",18,382,376,42,C.violet or C.blue,function()playerOp("dialogue",d.id);f:Close()end)end
  if not p and row.available then button(detail,"Принять задание",18,446,180,46,C.blue,function()playerOp("accept",d.id);f:Close()end)
  elseif p and p.status=="active"then button(detail,"Отказаться",18,446,180,46,C.red,function()playerOp("abandon",d.id);f:Close()end)
  elseif p and p.status=="completed"and d.repeatable then button(detail,"Начать квест заново",18,446,180,46,C.green,function()playerOp("restart",d.id);f:Close()end)end
  button(detail,"Закрыть",214,446,180,46,C.card,function()f:Close()end)
 end
 for i,row in ipairs(rows)do local d,p=row.definition,row.progress;local b=button(scroll,d.title,0,(i-1)*76,280,66,p and p.status=="completed"and QCOL.npcDone or C.card,function()show(row)end);b.Paint=function(self,w,h)draw.RoundedBox(8,0,0,w,h,self:IsHovered()and C.hover or(p and p.status=="completed"and QCOL.npcDoneHover or C.card));draw.SimpleText(d.title,"GRMQ_Body",12,13,C.text);draw.SimpleText(not p and"Новое задание"or(p.status=="active"and objectiveText(d,p)or"Завершено"),"GRMQ_Small",12,42,p and p.status=="completed"and C.green or C.dim)end end
 if rows[1]then show(rows[1])else label(detail,"У этого персонажа пока нет заданий.",20,30,370,60,"GRMQ_Head",C.dim)end
end
net.Receive("GRM_Quest_OpenNPC",openNPC)

local function openJournal()
 local f=frame("ЖУРНАЛ ЗАДАНИЙ",860,620);local rows=Q.ClientRows or{};local list=vgui.Create("DScrollPanel",f);list:SetPos(18,62);list:SetSize(350,536);local detail=vgui.Create("DPanel",f);detail:SetPos(382,62);detail:SetSize(460,536);detail.Paint=function(_,w,h)draw.RoundedBox(9,0,0,w,h,C.panel)end
 local function show(row)local d,p=row.definition,row.progress;detail:Clear();label(detail,d.title,18,18,424,38,"GRMQ_Head");label(detail,d.summary,18,68,424,110,"GRMQ_Body",C.dim);label(detail,p.status=="completed"and"ЗАВЕРШЕНО"or objectiveText(d,p),18,190,424,62,"GRMQ_Head",p.status=="completed"and C.green or C.yellow);local y=265;for i,step in ipairs(d.steps or{})do local done=i<(p.step or 1)or p.status=="completed";draw.RoundedBox(6,18,y,424,38,done and QCOL.stepDone or C.card);draw.SimpleText((done and"✓  "or"○  ")..step.title,"GRMQ_Body",30,y+19,done and C.green or C.text,TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER);y=y+44;if y>450 then break end end;if p.status=="active"then button(detail,"Отказаться от задания",18,478,210,40,C.red,function()playerOp("abandon",d.id);f:Close()end)elseif p.status=="completed"and d.repeatable then button(detail,"Начать заново",18,478,210,40,C.green,function()playerOp("restart",d.id);f:Close()end)end end
 local shown=0;for _,row in ipairs(rows)do if row.progress then shown=shown+1;local idx=shown;local d,p=row.definition,row.progress;local b=button(list,d.title,0,(idx-1)*72,330,62,C.card,function()show(row)end);b.Paint=function(self,w,h)draw.RoundedBox(8,0,0,w,h,self:IsHovered()and C.hover or C.card);draw.SimpleText(d.title,"GRMQ_Body",12,16,C.text);draw.SimpleText(p.status=="completed"and"Завершено"or objectiveText(d,p),"GRMQ_Small",12,43,p.status=="completed"and C.green or C.dim)end;if shown==1 then show(row)end end end
 if shown==0 then label(detail,"Активных и завершённых заданий пока нет. Поговорите с персонажами в мире.",24,30,412,100,"GRMQ_Head",C.dim)end
end
net.Receive("GRM_Quest_Journal",openJournal)
concommand.Add("grm_quests",openJournal)

hook.Add("HUDPaint","GRM_Quest_Tracker",function()
 if Q.Cutscene.active or(GRM.CCTV and GRM.CCTV.IsViewing and GRM.CCTV.IsViewing())then return end
 local active={};for _,row in ipairs(Q.ClientRows or {})do if row.progress and row.progress.status=="active"then active[#active+1]=row end end
 if#active==0 then return end;local w=320;local x=ScrW()-w-22;local y=90;draw.RoundedBox(9,x,y,w,36+#active*52,QCOL.trackBg);draw.SimpleText("ЗАДАНИЯ","GRMQ_Head",x+14,y+18,C.yellow,TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER)
 for i,row in ipairs(active)do local yy=y+32+(i-1)*52;draw.RoundedBox(6,x+9,yy,w-18,45,C.card);draw.SimpleText(row.definition.title,"GRMQ_Body",x+18,yy+12,C.text);draw.SimpleText(objectiveText(row.definition,row.progress),"GRMQ_Small",x+18,yy+31,C.dim)
  local step=row.definition.steps and row.definition.steps[row.progress.step or 1];if step and step.type=="visit"then local target
  -- точка строится в переиспользуемом векторе: HUDPaint = каждый кадр (§6.1.8)
  if step.pos then QT_TARGET_V.x=step.pos.x;QT_TARGET_V.y=step.pos.y;QT_TARGET_V.z=step.pos.z;target=QT_TARGET_V
  elseif step.min and step.max then QT_TARGET_V.x=(step.min.x+step.max.x)/2;QT_TARGET_V.y=(step.min.y+step.max.y)/2;QT_TARGET_V.z=(step.min.z+step.max.z)/2;target=QT_TARGET_V end;if target then local screen=target:ToScreen();local dist=math.floor(LocalPlayer():GetPos():Distance(target)/52.49);local mx=math.Clamp(screen.x,36,ScrW()-36);local my=math.Clamp(screen.y,70,ScrH()-70);draw.RoundedBox(16,mx-70,my-18,140,36,QCOL.trackChip);draw.SimpleText("◆ "..tostring(step.title),"GRMQ_Small",mx,my-5,C.yellow,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER);draw.SimpleText(dist.." м","GRMQ_Small",mx,my+10,C.text,TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)end end
 end
end)

-- Cutscene nodes use server-sanitized transforms and local packaged media only.
--[[ Завершение сцены. ВАЖНО: возвращаем чужие HUDPaint, снятые на время
     показа. Забыть об этом — значит оставить игрока без HUD до
     переподключения, и на любом аварийном выходе (смерть, ошибка,
     пропуск пробелом) тоже. Поэтому восстановление стоит здесь, в
     единственной точке выхода, а не рядом с каждым вызовом. ]]
local function stopCutscene()local restore=Q.Cutscene and Q.Cutscene.restoreFrame;if Q.Cutscene and Q.Cutscene.active then net.Start("GRM_Quest_CutsceneStop");net.SendToServer()end;Q.Cutscene={active=false};gui.EnableScreenClicker(false);if Q.StopCutsceneSound then Q.StopCutsceneSound()end;if Q.RestoreCutsceneHUD then Q.RestoreCutsceneHUD()end;if Q.ClearCutsceneViewPos then Q.ClearCutsceneViewPos()end;if IsValid(restore)then restore:SetVisible(true);restore:MakePopup()end end
--[[--------------------------------------------------------------------
    МИР ГЛАЗАМИ КАМЕРЫ СЦЕНЫ (жалоба владельца 30.08: «кат-сцене надо
    пофиксить рендер 3d2d textscreen, надписей, сущностей»).

    ЧТО ПРОИСХОДИЛО. CalcView двигает камеру, но ТЕЛО игрока остаётся
    там, где стояло. А почти весь мировой 3D2D решает «рисовать или нет»
    по расстоянию до тела:

        if lp:GetPos():DistToSqr(self:GetPos()) > 400*400 then return end
        if self:GetPos():DistToSqr(ply:GetShootPos()) < render_range then

    Таких проверок 95 в 53 файлах — наши энтити, вывески, таблички
    недвижимости, метки работ и сторонний Textscreens. Камера улетает к
    точке съёмки, тело далеко, и в кадре остаётся голая геометрия без
    единой подписи.

    ПОЧЕМУ НЕ ПРАВИМ КАЖДОЕ МЕСТО. Девяносто пять правок в полусотне
    файлов, один из которых — чужой аддон, сверяемый с апстримом. И
    любой новый модуль завтра снова напишет lp:GetPos(). Чиним один раз
    в точке причины.

    КАК. На время ОТРИСОВКИ кадра подменяем у ЛОКАЛЬНОГО игрока методы
    позиции так, чтобы они возвращали точку камеры. Весь мировой код без
    единой правки начинает считать расстояние от камеры — ровно то, что
    ему и нужно было.

    ГРАНИЦЫ. Только клиент. Только LocalPlayer (у других игроков позиция
    настоящая, иначе их таблички уехали бы к камере). Только между
    PreDrawOpaqueRenderables и PostDrawTranslucentRenderables, плюс на
    время HUDPaint. Игровая логика, Think, движение и сервер не видят
    подмены вообще.
----------------------------------------------------------------------]]
local viewPosPatched, savedPlayerPos = false, nil
local PATCHED_METHODS = { "GetPos", "GetShootPos", "EyePos" }

local function applyCutsceneViewPos()
    if viewPosPatched then return end
    local scene = Q.Cutscene
    if not (scene and scene.active and scene.currentPos) then return end
    local lp = LocalPlayer()
    if not IsValid(lp) then return end
    local meta = FindMetaTable("Player")
    if not meta then return end

    savedPlayerPos = {}
    for _, name in ipairs(PATCHED_METHODS) do
        local original = meta[name]
        if isfunction(original) then
            savedPlayerPos[name] = original
            meta[name] = function(self, ...)
                --[[ Подменяем только у себя и только пока сцена активна:
                     проверка внутри, потому что кадр может отрисоваться
                     уже после остановки сцены. ]]
                local st = Q.Cutscene
                if self == lp and st and st.active and st.currentPos then
                    return st.currentPos
                end
                return original(self, ...)
            end
        end
    end
    viewPosPatched = true
end

local function clearCutsceneViewPos()
    if not viewPosPatched then return end
    viewPosPatched = false
    local meta = FindMetaTable("Player")
    if meta and istable(savedPlayerPos) then
        --[[ Возвращаем ИСХОДНЫЕ функции, а не «снимаем обёртку»: так
             метод становится побайтово прежним, и повторные
             включения-выключения не оставляют слоёв. ]]
        for name, fn in pairs(savedPlayerPos) do meta[name] = fn end
    end
    savedPlayerPos = nil
end

-- Наружу: остановка сцены обязана снять подмену при ЛЮБОМ выходе.
Q.ClearCutsceneViewPos = clearCutsceneViewPos

--[[ Кадр мира. Opaque идёт раньше translucent, поэтому включаем на
     первом и снимаем на последнем: между ними рисуется всё, включая
     ENT:Draw с их cam.Start3D2D. ]]
hook.Add("PreDrawOpaqueRenderables", "GRM_Quest_CutsceneViewPos", function()
    if Q.Cutscene and Q.Cutscene.active then applyCutsceneViewPos() end
end)
hook.Add("PostDrawTranslucentRenderables", "GRM_Quest_CutsceneViewPos", function()
    clearCutsceneViewPos()
end)

--[[ HUDPaint рисует мировые подписи через ToScreen — им тоже нужна
     позиция камеры, иначе метки над объектами исчезнут или уедут. ]]
hook.Add("PreDrawHUD", "GRM_Quest_CutsceneViewPos", function()
    if Q.Cutscene and Q.Cutscene.active then applyCutsceneViewPos() end
end)
hook.Add("PostDrawHUD", "GRM_Quest_CutsceneViewPos", function()
    clearCutsceneViewPos()
end)

local function linkedCutsceneNodes(nodes)
 local source=table.Copy(nodes or{});local byID={};for i,node in ipairs(source)do byID[tostring(node.id or"")]=i end
 local ordered,seen,index={}, {},1
 while source[index]and not seen[index]and#ordered<32 do seen[index]=true;local node=source[index];ordered[#ordered+1]=node;local linked=byID[tostring(node.next or"")];index=linked or(index+1)end
 return ordered
end
local function nodeTransform(node)return Vector(node.pos.x,node.pos.y,node.pos.z),Angle(node.ang.p,node.ang.y,node.ang.r),tonumber(node.fov)or 75 end
local function startCutscene(nodes,adminPreview)
 nodes=linkedCutsceneNodes(nodes);if#nodes==0 then notification.AddLegacy("В этой фазе нет точек кат-сцены",NOTIFY_HINT,3)return end
 if adminPreview then net.Start("GRM_Quest_CutscenePreview");net.WriteTable(nodes);net.SendToServer()end
 local firstPos,firstAng,firstFov=nodeTransform(nodes[1])
 -- Первая точка — явная стартовая камера. Никакого полёта от тела игрока.
 Q.Cutscene={active=true,nodes=nodes,index=1,phase="hold",phaseStart=CurTime(),currentPos=firstPos,currentAng=firstAng,currentFov=firstFov,fromPos=firstPos,fromAng=firstAng,fromFov=firstFov,soundNode=0}
end
net.Receive("GRM_Quest_Cutscene",function()startCutscene(net.ReadTable()or{},false)end)

--[[ ЭКСПОРТ ЗАПУСКА СЦЕНЫ (жалоба владельца 29.08: «не запускается
     кат-сцена»).

     startCutscene была ЛОКАЛЬНОЙ функцией этого файла. Узловой редактор
     живёт в другом файле и дотянуться до неё не мог: кнопка «Просмотр»
     слала пакет на сервер, а тот лишь настраивал видимость мира (PVS) и
     обратно ничего не присылал. Сцена не начиналась вообще.

     Отдаём функцию наружу — редактор запускает просмотр локально, без
     похода на сервер. ]]
--[[ Проигрывание звука точки кат-сцены.

     Держим ссылку на трек: сцену можно пропустить пробелом, и без
     остановки звук играл бы поверх обычной игры. ]]
function Q.PlayCutsceneSound(path)
    path = string.Trim(tostring(path or ""))
    if path == "" then return end
    -- Пути пишут по-разному: «sound/x.wav» и «x.wav» — движку нужен второй.
    path = path:gsub("^sound/", "")

    Q.StopCutsceneSound()
    local lp = LocalPlayer()
    if IsValid(lp) and isfunction(CreateSound) then
        local ok, patch = pcall(CreateSound, lp, path)
        if ok and patch then
            Q._cutSound = patch
            --[[ SoundLevel 0 — слышно везде: камера сцены может стоять
                 далеко от тела игрока, и обычный звук просто не долетит. ]]
            pcall(function() patch:SetSoundLevel(0) patch:PlayEx(1, 100) end)
            return
        end
    end
    -- Запасной путь: хотя бы разово проиграть.
    surface.PlaySound(path)
end

function Q.StopCutsceneSound()
    if Q._cutSound then
        pcall(function() Q._cutSound:Stop() end)
        Q._cutSound = nil
    end
end

Q.StartCutscene = startCutscene
hook.Add("CalcView","GRM_Quest_CutsceneView",function(ply,pos,angles,fov)
 local s=Q.Cutscene;if not s.active then return end;local node=s.nodes[s.index];if not node then stopCutscene()return end
 local targetPos,targetAng,targetFov=nodeTransform(node);local origin,viewAng,viewFov=targetPos,targetAng,targetFov
 if s.phase=="move"then
  local moveDuration=math.max(.05,tonumber(node.moveDuration)or 1);local t=math.Clamp((CurTime()-s.phaseStart)/moveDuration,0,1);local eased=math.ease.InOutSine(t);origin=LerpVector(eased,s.fromPos,targetPos);viewAng=LerpAngle(eased,s.fromAng,targetAng);viewFov=Lerp(eased,s.fromFov or targetFov,targetFov)
  if t>=1 then s.phase="hold";s.phaseStart=CurTime();s.currentPos=targetPos;s.currentAng=targetAng;s.currentFov=targetFov end
 else
  --[[ ЗВУК ТОЧКИ (жалоба владельца 29.08: «проигрывание звука в
       кат-сцене надо сделать нормально, чтобы работало»).

       Было три беды:
         • звук запускался ТОЛЬКО в фазе hold. Если у точки стоял
           плавный пролёт, ветка move отрабатывала первой и звук
           пропускался совсем;
         • surface.PlaySound не умеет останавливаться: при пропуске
           сцены пробелом трек продолжал играть поверх игры;
         • путь не чистился — «sound/x.wav» с ведущей папкой молча не
           находился, а игрок видел тишину без объяснений.

       Теперь звук ставит Q.PlayCutsceneSound: одна точка входа, чистит
       путь и запоминает трек, чтобы снять его при выходе. ]]
  if s.soundNode~=s.index then s.soundNode=s.index;Q.PlayCutsceneSound(node.sound)end
  if CurTime()-s.phaseStart>=math.max(.05,tonumber(node.duration)or 3)then
   local oldPos,oldAng,oldFov=targetPos,targetAng,targetFov;s.index=s.index+1;local nextNode=s.nodes[s.index]
   if not nextNode then stopCutscene()return end
   s.fromPos=oldPos;s.fromAng=oldAng;s.fromFov=oldFov;s.phaseStart=CurTime();s.phase=nextNode.transition=="move"and"move"or"hold";s.soundNode=0
   if s.phase=="move"then origin,viewAng,viewFov=oldPos,oldAng,oldFov else origin,viewAng,viewFov=nodeTransform(nextNode)end
  end
 end
 return{origin=origin,angles=viewAng,fov=viewFov,znear=2,zfar=32768,drawviewer=false,drawmonitors=true}
end)
--[[ ЧЁРНЫЕ ПОЛОСЫ И ЧИСТЫЙ ЭКРАН (заказ владельца 28.08).

     «Когда проигрываются кат-сцены, полоски чёрные должны быть чёрными,
      а не прозрачными, и худ не должен рисоваться. Во время кат-сцены
      ничего лишнего быть не должно.»

     Что было не так:
       • полосы рисовались с альфой 235 — сквозь них просвечивал мир;
       • HUDPaint кат-сцены шёл в общей очереди, поэтому чужие HUDPaint
         (наш HUD, чат, метки) рисовались ПОВЕРХ полос;
       • стандартный HUD Source (здоровье, патроны, селектор оружия)
         никто не выключал.

     Полосы теперь полностью непрозрачные, а весь остальной HUD на время
     сцены снимается. Рисуем кат-сцену в HUDPaintBackground И в HUDPaint:
     первый идёт раньше чужих хуков, второй кладёт полосы поверх тех,
     кто всё-таки прорвался. ]]

--- Вспомогательное: рамка кат-сцены. Одна точка правды для обоих проходов.
local function drawCutsceneBars()
    local s = Q.Cutscene
    if not s.active then return end
    local n = s.nodes[s.index] or {}
    local w, h = ScrW(), ScrH()

    --[[ Высота полос — доля экрана, а не константа: на 1920x1080 прежние
         62 пикселя выглядели узкой каймой, а на маленьком разрешении
         съедали пол-экрана. 12% сверху и снизу дают киношный кадр 2.35:1. ]]
    local barTop = math.floor(h * 0.12)
    local barBottom = math.floor(h * 0.15)

    -- ПОЛНОСТЬЮ непрозрачный чёрный: мир сквозь полосы просвечивать не должен.
    surface.SetDrawColor(0, 0, 0, 255)
    surface.DrawRect(0, 0, w, barTop)
    surface.DrawRect(0, h - barBottom, w, barBottom)

    if n.image and n.image ~= "" then
        local m = Q._cutsceneMats
        if not m then m = {} Q._cutsceneMats = m end
        local mat = m[n.image]
        if not mat then mat = Material(n.image, "smooth") m[n.image] = mat end
        surface.SetMaterial(mat)
        surface.SetDrawColor(255, 255, 255, 220)
        surface.DrawTexturedRect(w / 2 - 80, barTop + 8, 160, 90)
    end

    -- Подпись и подсказка живут ВНУТРИ нижней полосы, а не на кадре.
    draw.SimpleText(n.caption or "", "GRMQ_Head", w / 2, h - barBottom / 2 - 8,
        C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText("ПРОБЕЛ — пропустить", "GRMQ_Small", w - 18, h - 16,
        C.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
end

hook.Add("HUDPaintBackground", "GRM_Quest_CutsceneHUD", drawCutsceneBars)

--[[ ВЕРХНИЙ ПРОХОД — в DrawOverlay, а не в HUDPaint (правка 28.08).

     Подписи над сущностями теперь рисуются во время сцены, и живут они
     в том же HUDPaint. Порядок хуков внутри одного события Lua не
     гарантирует ничего: метка над дверью могла лечь ПОВЕРХ чёрной
     полосы, если её хук отработал последним.

     DrawOverlay идёт после всего HUDPaint целиком, поэтому полосы
     гарантированно сверху: подписи видны в кадре, но обрезаются
     полосами, как в настоящем кино. ]]
hook.Add("DrawOverlay", "GRM_Quest_CutsceneHUDTop", drawCutsceneBars)

--[[ Стандартный HUD Source: здоровье, патроны, СЕЛЕКТОР ОРУЖИЯ, прицел.
     Возврат false прячет элемент. Чат не трогаем: он рисуется поверх
     полос, но лишать человека переписки на минуту ролика неправильно. ]]
local CUTSCENE_HIDE_HUD = {
    CHudHealth = true, CHudBattery = true, CHudAmmo = true, CHudSecondaryAmmo = true,
    CHudWeaponSelection = true, CHudCrosshair = true, CHudDamageIndicator = true,
    CHudGeiger = true, CHudZoom = true, CHudSuitPower = true, CHudPoisonDamageIndicator = true,
    CHudSquadStatus = true, CHudTrain = true, CHudMessage = true, CHudMenu = true,
}
hook.Add("HUDShouldDraw", "GRM_Quest_CutsceneHideHUD", function(name)
    if not Q.Cutscene.active then return end
    if CUTSCENE_HIDE_HUD[name] then return false end
end)

--[[ ЧУЖИЕ HUDPaint. HUDShouldDraw не властен над хуками аддонов: наш
     собственный HUD, метки над головами и прочее рисуются как обычно и
     лезли бы поверх полос. На время сцены снимаем их и возвращаем при
     любом выходе. Приём тот же, что в CCTV — там эта задача уже решена. ]]
local suppressedHUDPaint = {}
--[[ ЧТО ОСТАВЛЯЕМ РИСОВАТЬСЯ ВО ВРЕМЯ СЦЕНЫ (правка 28.08).

     Владелец: «надо чтобы кат-сцена нормально рендерила подписи ко
     всяким энтити, сущностям, надписи над ними и т.д.»

     Прошлая версия снимала ВСЕ чужие HUDPaint подряд. Это убрало
     мусор — но заодно и подписи над объектами мира: названия дверей,
     таблички недвижимости, имена игроков, метки заданий. В кадре
     кат-сцены оставалась голая геометрия, что для постановочной сцены
     как раз плохо: зритель не понимает, на что смотрит.

     Теперь список ЯВНЫЙ. Здесь только то, что привязано к точке в
     мире — подписи над сущностями и игроками. Всё панельное (полоски
     здоровья, трекер квестов, компас, уведомления, тулы) по-прежнему
     снимается: это интерфейс игрока, в кадре ему делать нечего.

     Принцип отбора: рисует ли хук что-то ЧЕРЕЗ ToScreen у конкретного
     объекта. Если да — это часть мира, оставляем. ]]
local KEEP_HUDPAINT = {
    -- Наши полосы и подпись сцены.
    GRM_Quest_CutsceneHUD = true,
    GRM_Quest_CutsceneHUDTop = true,

    -- Подписи над игроками: имя, профессия, описание, состояние.
    GRM_Nameplate = true,
    GRM_RPDesc = true,
    GRM_Arrest_Label = true,
    GRM_Bleedout_World = true,

    -- Подписи над объектами мира.
    GRM_Doors_HUD3D2D = true,          -- названия и владельцы дверей
    GRM_Estate_Labels = true,          -- жильё и бизнес без привязанной двери
    GRML_EntityLabels = true,          -- логистические точки фракций
    GRM_FC_ScrapBinLabel = true,       -- контейнеры производства
    GRM_FC_Progress = true,            -- прогресс станков над ними
    GRM_ChipControl_WorldTag = true,   -- метки чипованных объектов

    -- Точки назначения: без них в сцене пропадёт цель, к которой ведут.
    GRM_Jobs_GarbageRouteMarkers = true,
    GRM_Jobs_GPSMarker = true,
    GRM_GPS_WorldMarkerHUD = true,
    GRM_GPS_TempMarkers = true,
    GRM_FireDispatch_HUD = true,
}

--[[ Открытая точка расширения: сторонний модуль может попросить не
     снимать свой мировой хук, не правя этот файл.

     GRM.Quests.KeepDuringCutscene("MyAddon_WorldLabels") ]]
function Q.KeepDuringCutscene(id, keep)
    id = tostring(id or "")
    if id == "" then return false end
    KEEP_HUDPAINT[id] = keep ~= false
    return true
end

local function suppressForeignHUD()
    local hooks = hook.GetTable and hook.GetTable().HUDPaint
    if not hooks then return end
    local remove = {}
    for id, fn in pairs(hooks) do
        if not KEEP_HUDPAINT[id] and isstring(id) then
            remove[#remove + 1] = { id = id, fn = fn }
        end
    end
    for _, row in ipairs(remove) do
        suppressedHUDPaint[row.id] = row.fn
        hook.Remove("HUDPaint", row.id)
    end
end

local function restoreForeignHUD()
    for id, fn in pairs(suppressedHUDPaint) do
        --[[ Возвращаем только если за время сцены никто не занял это имя
             заново: иначе затрём свежий хук устаревшей функцией. ]]
        local hooks = hook.GetTable and hook.GetTable().HUDPaint
        if not (hooks and hooks[id]) then hook.Add("HUDPaint", id, fn) end
    end
    suppressedHUDPaint = {}
end

Q.RestoreCutsceneHUD = restoreForeignHUD

--[[ Подхватываем и те HUDPaint, что зарегистрировались уже ПОСЛЕ начала
     сцены: аддоны любят вешать хуки лениво, по первому событию. ]]
hook.Add("Think", "GRM_Quest_CutsceneSuppress", function()
    if not Q.Cutscene.active then return end
    if GRM.Perf and GRM.Perf.Throttle and not GRM.Perf.Throttle("quest.cutscene.hud", 0.5) then return end
    suppressForeignHUD()
end)

--[[ БЛОКИРОВКА УПРАВЛЕНИЯ (заказ владельца: «игрок не должен использовать
     селектор оружия или какие-либо меню»).

     ClearButtons в CreateMove гасит движение и стрельбу, но НЕ трогает
     привязки: invnext/invprev листали оружие, Q открывал спавн-меню,
     C — контекстное. Закрываем всё это отдельно. ]]
hook.Add("PlayerBindPress", "GRM_Quest_CutsceneBinds", function(_, bind, pressed)
    if not Q.Cutscene.active then return end
    bind = tostring(bind or ""):lower()
    --[[ Пропускаем только чат и консоль: человек должен иметь возможность
         написать, что сцена сломалась, и открыть консоль. ]]
    if bind:find("messagemode") or bind:find("toggleconsole") then return end
    return true
end)

hook.Add("SpawnMenuOpen", "GRM_Quest_CutsceneNoSpawn", function()
    if Q.Cutscene.active then return false end
end)
hook.Add("ContextMenuOpen", "GRM_Quest_CutsceneNoContext", function()
    if Q.Cutscene.active then return false end
end)
--[[ Селектор оружия колесом мыши идёт мимо PlayerBindPress. ]]
hook.Add("PlayerSwitchWeapon", "GRM_Quest_CutsceneNoSwitch", function()
    if Q.Cutscene.active then return true end
end)
hook.Add("HUDShouldDraw", "GRM_Quest_CutsceneNoSelector", function(name)
    if Q.Cutscene.active and name == "CHudWeaponSelection" then return false end
end)

hook.Add("PlayerButtonDown","GRM_Quest_CutsceneSkip",function(ply,key)if ply==LocalPlayer()and Q.Cutscene.active and key==KEY_SPACE then stopCutscene()end end)
hook.Add("CreateMove","GRM_Quest_CutsceneLock",function(cmd)if Q.Cutscene.active then cmd:ClearMovement();cmd:ClearButtons()end end)

hook.Add("PlayerDeath","GRM_Quest_CutsceneDeath",function(ply)if ply==LocalPlayer()then stopCutscene()end end)

-- Quest Studio v1.1: visual constructors, no raw JSON required.
local function darkList(parent,x,y,w,h,columns)
 local l=vgui.Create("DListView",parent);l:SetPos(x,y);l:SetSize(w,h);l:SetMultiSelect(false);l.Paint=function(_,pw,ph)draw.RoundedBox(7,0,0,pw,ph,Color(12,19,30))end
 for _,c in ipairs(columns)do local header=l:AddColumn(c[1]);header:SetFixedWidth(c[2]or 100)end;return l
end
local function addDarkLine(list,...)
 local line=list:AddLine(...);for _,column in ipairs(line.Columns or{})do if column.SetTextColor then column:SetTextColor(C.text)end end
 line.Paint=function(self,w,h)local selected=self:IsSelected();draw.RoundedBox(4,1,1,w-2,h-2,selected and C.blue or(self:IsHovered()and C.hover or Color(20,30,45)));for _,column in ipairs(self.Columns or{})do if column.SetTextColor then column:SetTextColor(selected and color_white or C.text)end end end
 return line
end
local function textEntry(parent,title,x,y,w,h,multi)
 label(parent,title,x,y,w,18,"GRMQ_Small",C.dim);local e=vgui.Create("DTextEntry",parent);e:SetPos(x,y+19);e:SetSize(w,h or 28);e:SetMultiline(multi==true);return e
end
local function numberEntry(parent,title,x,y,w,min,max)
 label(parent,title,x,y,w,18,"GRMQ_Small",C.dim);local e=vgui.Create("DNumberWang",parent);e:SetPos(x,y+19);e:SetSize(w,28);e:SetMin(min or 0);e:SetMax(max or 100000);return e
end
local function comboEntry(parent,title,x,y,w,choices)
 label(parent,title,x,y,w,18,"GRMQ_Small",C.dim);local e=vgui.Create("DComboBox",parent);e:SetPos(x,y+19);e:SetSize(w,28);for _,v in ipairs(choices)do e:AddChoice(v[1],v[2])end;e.ValueID=choices[1]and choices[1][2];e.OnSelect=function(_,_,_,data)e.ValueID=data end;return e
end
local function splitCSV(value)local out={};for part in tostring(value or""):gmatch("[^,]+")do part=string.Trim(part);if part~=""then out[#out+1]=part end end;return out end
local function adminStudio(data)
 if IsValid(Q.AdminFrame)then Q.AdminFrame:Remove()end
 local f=frame("GRM QUEST STUDIO · ВИЗУАЛЬНЫЙ КОНСТРУКТОР",1220,780);Q.AdminFrame=f
 local definitions=data.definitions or{};Q.AdminDefinitions=definitions;local work=nil
 local rebuildStages,rebuildRewards,rebuildNodes,rebuildCams,saveWork
 local statusText,statusColor="Выберите квест или создайте новый",C.dim
 local function setStatus(text,color)statusText=tostring(text or"");statusColor=color or C.dim end
 local questList=darkList(f,16,62,300,640,{{"ID",88},{"Квест",155},{"Этапов",52}})
 local tabs=vgui.Create("DPropertySheet",f);tabs:SetPos(328,58);tabs:SetSize(874,646)
 local function panelTab(name,icon)local p=vgui.Create("DPanel",tabs);p.Paint=function(_,w,h)draw.RoundedBox(9,0,0,w,h,C.panel)end;tabs:AddSheet(name,p,icon);return p end
 --[[ Порядок вкладок = порядок работы автора: сначала описать квест,
      потом этапы, потом что за них дают, потом разговоры и ролики.
      Раньше «Награды» стояли до «Этапов», хотя награда выдаётся ПОСЛЕ
      всех этапов — это и создавало путаницу «когда что срабатывает». ]]
 local general=panelTab("1. Основное","icon16/book.png")
 local stages=panelTab("2. Этапы","icon16/flag_blue.png")
 local dialogues=panelTab("3. Диалоги","icon16/comments.png")
 local rewards=panelTab("4. Награды","icon16/money.png")
 local notifications=panelTab("5. Уведомления","icon16/comment.png")
 local cinema=panelTab("6. Кат-сцены","icon16/film.png")

 --[[ ЛЕНТА ЖИЗНЕННОГО ЦИКЛА (заказ владельца 28.08: «непонятно, к чему
      сделано — до квеста / вовремя / после?»).

      Рисуем одну и ту же ось времени на каждой вкладке и подсвечиваем
      тот отрезок, к которому вкладка относится. Так автор всегда видит,
      в какой момент сработает то, что он сейчас настраивает.

      Текст берём из GRM.Quests.Lifecycle — общей таблицы на сервере и
      клиенте. Если поведение изменится, подсказка изменится вместе с
      ним и не разойдётся с кодом. ]]
 local LIFE = Q.Lifecycle or {}
 local function lifecycleStrip(parent,activePhase,y,note)
  local strip=vgui.Create("DPanel",parent);strip:SetPos(12,y or 0);strip:SetSize(850,58)
  strip.Paint=function(_,w,h)
   draw.RoundedBox(8,0,0,w,h,Color(13,21,33))
   surface.SetDrawColor(52,74,102);surface.DrawOutlinedRect(0,0,w,h,1)
   local n=#LIFE;if n==0 then return end
   local pad,gap=10,6
   local cw=(w-pad*2-gap*(n-1))/n
   for i,row in ipairs(LIFE) do
    local x=pad+(i-1)*(cw+gap)
    local on=row.phase==activePhase
    draw.RoundedBox(6,x,8,cw,26,on and Color(46,96,158) or Color(24,36,54))
    if on then surface.SetDrawColor(120,180,255);surface.DrawOutlinedRect(x,8,cw,26,1) end
    draw.SimpleText(row.when,"GRMQ_Small",x+cw/2,21,
     on and Color(235,244,255) or Color(120,140,165),TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER)
    -- Стрелка между этапами: видно, что это последовательность.
    if i<n then draw.SimpleText("→","GRMQ_Small",x+cw+gap/2,21,Color(80,100,125),TEXT_ALIGN_CENTER,TEXT_ALIGN_CENTER) end
   end
   local hint=note
   if not hint then
    for _,row in ipairs(LIFE) do if row.phase==activePhase then hint=row.what break end end
   end
   draw.SimpleText(tostring(hint or ""),"GRMQ_Small",pad,46,Color(150,168,190),TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER)
  end
  return strip
 end

 lifecycleStrip(general,"",8,"Порядок работы: 1 Основное → 2 Этапы → 3 Диалоги (там выдаётся квест) → 4 Награды → 5 Уведомления → 6 Кат-сцены.")
 local g={}
 g.id=textEntry(general,"Уникальный ID",18,78,360);g.title=textEntry(general,"Название квеста",18,136,520);g.category=textEntry(general,"Категория",18,194,250);g.npc=textEntry(general,"ID квестового NPC",286,194,252);g.summary=textEntry(general,"Описание для игрока",18,252,814,64,true);g.prereq=textEntry(general,"Предыдущие квесты через запятую",18,346,520)
 g.flags={};for i,v in ipairs({{"enabled","Квест включён"},{"repeatable","Можно повторять"},{"autoStart","Автостарт новичку"}})do local c=vgui.Create("DCheckBoxLabel",general);c:SetPos(18+(i-1)*220,412);c:SetText(v[2]);c:SetTextColor(C.text);c:SizeToContents();g.flags[v[1]]=c end
 label(general,"БЫСТРЫЙ СТАРТ",18,442,400,22,"GRMQ_Head",C.yellow)
 button(general,"ЛОР + проводник + завод",18,470,250,42,C.blue,function()if not work then return end;work.steps={{type="talk",npc=work.npc~=""and work.npc or"guide",title="Поговорить с проводником",count=1},{type="visit",title="Дойти до завода",pos={x=0,y=0,z=0},radius=180,count=1}};if rebuildStages then rebuildStages()end;if tabs.SwitchToName then tabs:SwitchToName("Этапы")end;setStatus("Шаблон этапов создан — настройте зону завода",C.green);notification.AddLegacy("Шаблон добавлен. Откройте «Этапы» и задайте зону тулом.",NOTIFY_HINT,5)end)
 button(general,"10 руды → 10 видеокарт",280,470,260,42,C.green,function()if not work then return end;work.steps={{type="event",event="mining",target="",count=10,title="Добыть руду 10 раз"},{type="event",event="factory_produce",target="gpu_basic",count=10,title="Произвести 10 видеокарт"}};if rebuildStages then rebuildStages()end;if tabs.SwitchToName then tabs:SwitchToName("Этапы")end;setStatus("Производственная цепочка создана",C.green);notification.AddLegacy("Производственная цепочка добавлена",NOTIFY_GENERIC,4)end)
 button(general,"Подготовить тул для NPC",552,470,250,42,Color(58,82,112),function()if not work then setStatus("Сначала выберите квест",C.red)return end;RunConsoleCommand("grm_quest_tool_mode","npc");RunConsoleCommand("grm_quest_tool_npc_id",g.npc:GetText());RunConsoleCommand("grm_quest_tool_npc_name",g.title:GetText());RunConsoleCommand("gmod_tool","grm_quest_tool");f:Close();notification.AddLegacy("Тул готов: наведитесь на землю и нажмите ЛКМ",NOTIFY_HINT,7)end)
 label(general,"СБРОС ПРОГРЕССА / ПОВТОРНЫЙ ЗАПУСК",18,524,500,22,"GRMQ_Head",C.yellow)
 local resetChoices={{"Мой персонаж","@self"},{"Все персонажи","*"}};for _,p in ipairs(data.onlinePlayers or{})do resetChoices[#resetChoices+1]={p.name.." · "..p.key,p.key}end;g.resetTarget=comboEntry(general,"Чей прогресс сбросить",18,552,420,resetChoices)
 button(general,"Сбросить засчёт",454,571,180,38,C.red,function()if not work then setStatus("Выберите квест",C.red)return end;local target=g.resetTarget.ValueID or"@self";local function send()net.Start("GRM_Quest_AdminOp");net.WriteString("reset_progress");net.WriteString(work.id or"");net.WriteString(target);net.SendToServer();setStatus("Запрошен сброс прогресса",C.yellow)end;if target=="*"then Derma_Query("Сбросить этот квест у ВСЕХ персонажей?","Подтверждение","Сбросить",send,"Отмена")else send()end end)
 label(general,"После сброса квест снова доступен у NPC. Для самостоятельного повтора игроком включите чекбокс «Можно повторять».",18,612,814,28,"GRMQ_Small",C.dim)

 -- Stage constructor
 lifecycleStrip(stages,"active",8)
 local stageList=darkList(stages,12,104,300,440,{{"#",32},{"Тип",74},{"Название",190}});label(stages,"ПОСЛЕДОВАТЕЛЬНОСТЬ ЭТАПОВ",12,78,300,22,"GRMQ_Head",C.yellow)
 local sf={};sf.type=comboEntry(stages,"Тип этапа",328,78,220,{{"Посетить место","visit"},{"Поговорить с NPC","talk"},{"Событие/счётчик","event"},{"Иметь предмет","item"}});sf.title=textEntry(stages,"Название для игрока",566,78,278);sf.desc=textEntry(stages,"Пояснение",328,136,516,44,true);sf.event=textEntry(stages,"Событие",328,208,160);sf.target=textEntry(stages,"Цель события",500,208,172);sf.npc=textEntry(stages,"ID NPC",684,208,160);sf.item=textEntry(stages,"ID предмета",328,266,220);sf.count=numberEntry(stages,"Количество",560,266,120,1,100000);sf.radius=numberEntry(stages,"Радиус точки",692,266,152,24,10000);sf.consume=vgui.Create("DCheckBoxLabel",stages);sf.consume:SetPos(328,328);sf.consume:SetText("Изъять предметы при выполнении");sf.consume:SetTextColor(C.text);sf.consume:SizeToContents()
 local selectedStage=0
 rebuildStages=function()stageList:Clear();for i,s in ipairs(work and work.steps or{})do local line=addDarkLine(stageList,i,s.type,s.title);line._index=i end end
 local function loadStage(i)local s=work and work.steps[i];if not s then return end;selectedStage=i;sf.type:SetValue(({visit="Посетить место",talk="Поговорить с NPC",event="Событие/счётчик",item="Иметь предмет"})[s.type]or s.type);sf.type.ValueID=s.type;sf.title:SetText(s.title or"");sf.desc:SetText(s.description or"");sf.event:SetText(s.event or"");sf.target:SetText(s.target or"");sf.npc:SetText(s.npc or"");sf.item:SetText(s.item or"");sf.count:SetValue(s.count or 1);sf.radius:SetValue(s.radius or 120);sf.consume:SetValue(s.consume and 1 or 0)end
 stageList.OnRowSelected=function(_,_,line)loadStage(line._index)end
 local function applyStage()if not work or selectedStage<1 then return end;local old=work.steps[selectedStage]or{};work.steps[selectedStage]={type=sf.type.ValueID or"event",title=sf.title:GetText(),description=sf.desc:GetText(),event=sf.event:GetText(),target=sf.target:GetText(),npc=sf.npc:GetText(),item=sf.item:GetText(),count=sf.count:GetValue(),radius=sf.radius:GetValue(),consume=sf.consume:GetChecked(),pos=old.pos,min=old.min,max=old.max};rebuildStages();loadStage(selectedStage)end
 button(stages,"+ Новый этап",328,362,160,38,C.blue,function()if not work then return end;work.steps=work.steps or{};work.steps[#work.steps+1]={type="event",title="Новый этап",event="generic",target="",count=1};rebuildStages();loadStage(#work.steps)end)
 button(stages,"Применить",500,362,130,38,C.green,applyStage)
 button(stages,"Удалить",642,362,100,38,C.red,function()if work and selectedStage>0 then table.remove(work.steps,selectedStage);selectedStage=0;rebuildStages()end end)
 button(stages,"↑",754,362,42,38,C.card,function()if work and selectedStage>1 then work.steps[selectedStage],work.steps[selectedStage-1]=work.steps[selectedStage-1],work.steps[selectedStage];selectedStage=selectedStage-1;rebuildStages();loadStage(selectedStage)end end)
 button(stages,"↓",802,362,42,38,C.card,function()if work and selectedStage<#work.steps then work.steps[selectedStage],work.steps[selectedStage+1]=work.steps[selectedStage+1],work.steps[selectedStage];selectedStage=selectedStage+1;rebuildStages();loadStage(selectedStage)end end)
 button(stages,"Настроить зону этим тулом",328,414,250,42,C.yellow,function()if not work or selectedStage<1 then setStatus("Выберите этап visit",C.red)return end;applyStage();if not saveWork(true)then return end;RunConsoleCommand("grm_quest_tool_mode","zone");RunConsoleCommand("grm_quest_tool_quest_id",work.id);RunConsoleCommand("grm_quest_tool_step",selectedStage);RunConsoleCommand("gmod_tool","grm_quest_tool");notification.AddLegacy("Тул готов: ЛКМ — первый угол, ПКМ — второй",NOTIFY_HINT,7)end)
 label(stages,"Этапы выполняются СТРОГО по порядку сверху вниз. Игрок видит только текущий.\n\nevent: mining / factory_produce / inventory_gain / любое событие API. Пустая цель принимает любой предмет или тип руды.",328,466,516,96,"GRMQ_Small",C.dim)

 --[[ ВКЛАДКА «НАГРАДЫ» (переделана 28.08).

      Жалоба владельца: «не понятно, как выстраивать выдачу наград и
      ачивок... как подключить выплаты?»

      Что было не так: поля лежали сплошным списком без объяснения, в
      какой момент они срабатывают. Выглядело так, будто награду надо
      где-то отдельно «подключать».

      Теперь вкладка разбита на два блока с заголовками, отвечающими на
      вопрос «когда»: обе выплаты происходят САМИ в момент завершения
      последнего этапа, подключать ничего не нужно. Отдельная врезка
      объясняет, как выдать деньги ПО ХОДУ разговора — это другой
      механизм, он живёт в диалогах. ]]
 lifecycleStrip(rewards,"complete",8)

 local rw={}

 -- Блок 1: награда самого квеста.
 local rwBox=vgui.Create("DPanel",rewards);rwBox:SetPos(12,74);rwBox:SetSize(850,258)
 rwBox.Paint=function(_,w,h)
  draw.RoundedBox(8,0,0,w,h,Color(15,24,37));surface.SetDrawColor(55,78,105);surface.DrawOutlinedRect(0,0,w,h,1)
  draw.RoundedBox(0,0,0,4,h,C.green)
  draw.SimpleText("НАГРАДА ЗА КВЕСТ","GRMQ_Head",16,18,C.green,TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER)
  draw.SimpleText("Выдаётся автоматически, когда игрок закрывает последний этап. Подключать ничего не нужно.",
   "GRMQ_Small",16,40,C.dim,TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER)
 end
 rw.money=numberEntry(rwBox,"Деньги (0 — не выдавать)",16,60,220,0,100000000)
 rw.itemID=textEntry(rwBox,"ID предмета",250,60,250)
 rw.itemCount=numberEntry(rwBox,"Количество",514,60,120,1,10000)
 rw.list=darkList(rwBox,16,132,618,110,{{"Предмет",420},{"Кол-во",150}})
 local rewardItems={}
 rebuildRewards=function()rw.list:Clear();for id,count in pairs(rewardItems)do local line=addDarkLine(rw.list,id,count);line._id=id end end
 button(rwBox,"Добавить предмет",650,79,186,34,C.green,function()local id=string.Trim(rw.itemID:GetText());if id~=""then rewardItems[id]=math.max(1,rw.itemCount:GetValue());rebuildRewards();setStatus("Предмет добавлен в награду",C.green)end end)
 button(rwBox,"Убрать выбранный",650,121,186,34,C.red,function()local i=rw.list:GetSelectedLine();local l=i and rw.list:GetLine(i);if IsValid(l)then rewardItems[l._id]=nil;rebuildRewards()end end)
 label(rwBox,"Предметы кладутся в инвентарь. Если инвентарь переполнен, предмет пропадёт — не выдавайте десятки штук.",650,164,196,76,"GRMQ_Small",C.dim)

 -- Блок 2: ачивка со СВОЕЙ наградой.
 local achBox=vgui.Create("DPanel",rewards);achBox:SetPos(12,342);achBox:SetSize(850,196)
 achBox.Paint=function(_,w,h)
  draw.RoundedBox(8,0,0,w,h,Color(15,24,37));surface.SetDrawColor(55,78,105);surface.DrawOutlinedRect(0,0,w,h,1)
  draw.RoundedBox(0,0,0,4,h,C.yellow)
  draw.SimpleText("АЧИВКА ЗА ЗАВЕРШЕНИЕ","GRMQ_Head",16,18,C.yellow,TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER)
  draw.SimpleText("Выдаётся сразу после награды квеста. Её деньги — ОТДЕЛЬНАЯ сумма, она не заменяет награду выше.",
   "GRMQ_Small",16,40,C.dim,TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER)
 end
 rw.achEnabled=vgui.Create("DCheckBoxLabel",achBox);rw.achEnabled:SetPos(16,62);rw.achEnabled:SetText("Выдавать ачивку");rw.achEnabled:SetTextColor(C.text);rw.achEnabled:SizeToContents()
 rw.achHidden=vgui.Create("DCheckBoxLabel",achBox);rw.achHidden:SetPos(180,62);rw.achHidden:SetText("Скрытая до получения");rw.achHidden:SetTextColor(C.text);rw.achHidden:SizeToContents()
 rw.achID=textEntry(achBox,"ID ачивки",16,84,210)
 rw.achName=textEntry(achBox,"Название",240,84,300)
 rw.achReward=numberEntry(achBox,"Деньги за ачивку",554,84,180,0,100000000)
 rw.achDesc=textEntry(achBox,"Описание",16,142,718,30)
 label(achBox,"Появится во вкладке достижений F4.",748,161,92,30,"GRMQ_Small",C.dim)

 --[[ Врезка про выплаты по ходу разговора: владелец спрашивал именно
      «как подключить выплаты», и ответов на самом деле два. ]]
 label(rewards,"Нужно выдать деньги ПО ХОДУ разговора, а не в конце? Это делается во вкладке «3. Диалоги»: у ответа игрока выберите действие «Деньги» или «Предмет» и впишите сумму в поле аргумента.",
  12,546,850,44,"GRMQ_Small",C.dim)
 -- Configurable quest notifications
 local nt={};local function notificationEditor(key,title,y)
  local box=vgui.Create("DPanel",notifications);box:SetPos(14,y);box:SetSize(828,164);box.Paint=function(_,w,h)draw.RoundedBox(8,0,0,w,h,Color(15,24,37));surface.SetDrawColor(55,78,105);surface.DrawOutlinedRect(0,0,w,h,1)end;label(box,title,14,10,320,22,"GRMQ_Head",C.yellow);local cfg={};cfg.enabled=vgui.Create("DCheckBoxLabel",box);cfg.enabled:SetPos(630,13);cfg.enabled:SetText("Показывать");cfg.enabled:SetTextColor(C.text);cfg.enabled:SizeToContents();cfg.banner=vgui.Create("DCheckBoxLabel",box);cfg.banner:SetPos(720,13);cfg.banner:SetText("Баннер");cfg.banner:SetTextColor(C.text);cfg.banner:SizeToContents();cfg.text=textEntry(box,"Текст ({title}, {step}, {count})",14,42,500);cfg.sound=textEntry(box,"Звук",526,42,286);cfg.duration=numberEntry(box,"Длительность",14,100,130,1,15);nt[key]=cfg
 end
 lifecycleStrip(notifications,"start",8)
 notificationEditor("start","1. ПРИ ПРИНЯТИИ КВЕСТА",74);notificationEditor("step","2. ПРИ ЗАВЕРШЕНИИ КАЖДОГО ЭТАПА",248);notificationEditor("complete","3. ПРИ ЗАВЕРШЕНИИ КВЕСТА",422)
 label(notifications,"Пример звука: buttons/button14.wav. Баннер выводит крупное уведомление в верхней части экрана. Это только текст на экране — награду выдаёт вкладка «4. Награды».",18,592,810,32,"GRMQ_Small",C.dim)

 -- Dialogue graph constructor
 --[[ ВКЛАДКА «ДИАЛОГИ» (переделана 28.08).

      Жалоба владельца: «как диалоги нормально настроить?»

      Главное, чего не хватало: нигде не было сказано, что квест
      выдаётся ТОЛЬКО ответом с действием «Принять квест». Автор
      заполнял реплики, сохранял — и не мог взять квест у NPC.

      Теперь фаза разговора подсвечивается на ленте жизненного цикла, а
      под выбором фазы висит пояснение, что именно эта фаза делает. ]]
 local dlgStrip=lifecycleStrip(dialogues,"offer",8)
 local dlgPhase=comboEntry(dialogues,"Фаза разговора",12,74,210,{{"До принятия квеста","offer"},{"Во время квеста","active"},{"После завершения","complete"}});local dlgList=darkList(dialogues,12,134,270,411,{{"#",32},{"ID",80},{"Реплика",150}});local dn={};dn.id=textEntry(dialogues,"ID узла",296,74,180);dn.speaker=textEntry(dialogues,"Говорящий",488,74,190);dn.text=textEntry(dialogues,"Текст реплики",296,132,548,60,true);dn.next=textEntry(dialogues,"Следующий ID (пусто = следующая по списку)",296,222,260)
 local choiceList=darkList(dialogues,296,329,548,124,{{"Ответ игрока",300},{"Следующий ID",120},{"Действие",100}});local chText=textEntry(dialogues,"Текст ответа",296,464,200);local chNext=textEntry(dialogues,"Следующий ID",508,464,100);local chAction=comboEntry(dialogues,"Действие",620,464,224,{{"Продолжить",""},{"Принять квест","accept"},{"Закрыть","close"},{"Флаг +","set_flag"},{"Флаг −","clear_flag"},{"Деньги","give_money"},{"Предмет","give_item"},{"Событие","emit"}});local chCond=textEntry(dialogues,"Условие: flag:x / !flag:x / item:id / money:N / fac:Имя / done:id",296,522,270);local chArg=textEntry(dialogues,"Аргумент: сумма для «Деньги», ID для «Предмет»/«Флаг»",578,522,266)
 local selectedNode,selectedChoice=0,0;local currentChoices={}
 local function phaseNodes()if not work then return{}end;work.dialogue=work.dialogue or{offer={},active={},complete={}};local phase=dlgPhase.ValueID or"offer";work.dialogue[phase]=dialogueNodes(work.dialogue[phase]);return work.dialogue[phase]end
 local function rebuildChoices()choiceList:Clear();for i,ch in ipairs(currentChoices)do local line=addDarkLine(choiceList,ch.text,ch.next,(ch.action or"")..((ch.cond and ch.cond~="")and(" ["..ch.cond.."]")or""));line._index=i end end
 rebuildNodes=function()dlgList:Clear();for i,n in ipairs(phaseNodes())do local line=addDarkLine(dlgList,i,n.id,string.sub(n.text or"",1,42));line._index=i end end
 local function loadNode(i)local n=phaseNodes()[i];if not n then return end;selectedNode=i;dn.id:SetText(n.id or"");dn.speaker:SetText(n.speaker or"");dn.text:SetText(n.text or"");dn.next:SetText(n.next or"");currentChoices=table.Copy(n.choices or{});selectedChoice=0;rebuildChoices()end
 dlgPhase.OnSelect=function(_,_,_,data)dlgPhase.ValueID=data;selectedNode=0;rebuildNodes();if IsValid(dlgStrip)then dlgStrip:Remove()end;dlgStrip=lifecycleStrip(dialogues,data=="offer" and "offer" or (data=="active" and "active" or "after"),8);dlgStrip:SetZPos(-1)end;dlgList.OnRowSelected=function(_,_,line)loadNode(line._index)end;choiceList.OnRowSelected=function(_,_,line)local ch=currentChoices[line._index];if ch then selectedChoice=line._index;chText:SetText(ch.text or"");chNext:SetText(ch.next or"");chCond:SetText(ch.cond or"");chArg:SetText(ch.actionArg or"");chAction.ValueID=ch.action or"";local names={accept="Принять квест",close="Закрыть",set_flag="Флаг +",clear_flag="Флаг −",give_money="Деньги",give_item="Предмет",emit="Событие"};chAction:SetValue(names[ch.action]or"Продолжить")end end
 local function applyNode()local nodes=phaseNodes();if selectedNode<1 then return end;nodes[selectedNode]={id=dn.id:GetText(),speaker=dn.speaker:GetText(),text=dn.text:GetText(),next=dn.next:GetText(),choices=table.Copy(currentChoices)};rebuildNodes();loadNode(selectedNode)end
 button(dialogues,"+ Реплика",296,286,110,32,C.blue,function()local nodes=phaseNodes();nodes[#nodes+1]={id=(dlgPhase.ValueID or"offer").."_"..(#nodes+1),speaker=g.npc:GetText(),text="Новая реплика",next="",choices={}};rebuildNodes();loadNode(#nodes)end);button(dialogues,"Применить",414,286,100,32,C.green,applyNode);button(dialogues,"Удалить",522,286,90,32,C.red,function()local nodes=phaseNodes();if selectedNode>0 then table.remove(nodes,selectedNode);selectedNode=0;rebuildNodes()end end);button(dialogues,"↑",620,286,38,32,C.card,function()local n=phaseNodes();if selectedNode>1 then n[selectedNode],n[selectedNode-1]=n[selectedNode-1],n[selectedNode];selectedNode=selectedNode-1;rebuildNodes();loadNode(selectedNode)end end);button(dialogues,"↓",664,286,38,32,C.card,function()local n=phaseNodes();if selectedNode<#n then n[selectedNode],n[selectedNode+1]=n[selectedNode+1],n[selectedNode];selectedNode=selectedNode+1;rebuildNodes();loadNode(selectedNode)end end);button(dialogues,"▶ Тест диалога",712,286,132,32,C.yellow,function()applyNode();playDialogue(g.npc:GetText(),phaseNodes())end)
 button(dialogues,"Холст графа",12,556,270,36,Color(58,82,112),function()if not work then return end;if Q.OpenGraphStudio then Q.OpenGraphStudio({definitions={work}})end end)
 button(dialogues,"+ Ответ",296,582,100,30,C.blue,function()currentChoices[#currentChoices+1]={text=chText:GetText(),next=chNext:GetText(),action=chAction.ValueID or"",actionArg=chArg:GetText(),cond=chCond:GetText()};rebuildChoices()end);button(dialogues,"Изменить",404,582,100,30,C.green,function()if selectedChoice>0 then currentChoices[selectedChoice]={text=chText:GetText(),next=chNext:GetText(),action=chAction.ValueID or"",actionArg=chArg:GetText(),cond=chCond:GetText()};rebuildChoices()end end);button(dialogues,"Удалить",512,582,90,30,C.red,function()if selectedChoice>0 then table.remove(currentChoices,selectedChoice);selectedChoice=0;rebuildChoices()end end)
 label(dialogues,"КВЕСТ ВЫДАЁТСЯ ТОЛЬКО ответом с действием «Принять квест» в фазе «До принятия». Без него игрок не сможет взять задание.",296,556,548,26,"GRMQ_Small",C.yellow)
 label(dialogues,"Реплики идут сверху вниз. «Следующий ID» задаёт переход. Действия «Деньги» и «Предмет» выдают награду прямо в разговоре — это не заменяет награду за квест.",296,584,548,40,"GRMQ_Small",C.dim)

 -- Cutscene visual timeline
 local csStrip=lifecycleStrip(cinema,"start",8)
 local csPhase=comboEntry(cinema,"Фаза показа",12,74,210,{{"При принятии квеста","accept"},{"При завершении квеста","complete"}});local csList=darkList(cinema,12,134,290,416,{{"#",32},{"ID",88},{"Связь",70},{"Титр",95}});local cn={};cn.id=textEntry(cinema,"ID камеры",318,74,160);cn.next=textEntry(cinema,"Следующая камера",490,74,170);cn.transition=comboEntry(cinema,"Переход к этой точке",672,74,172,{{"Мгновенно","cut"},{"Плавный пролёт","move"}});cn.duration=numberEntry(cinema,"Показ точки, сек",318,132,150,.05,30);cn.moveDuration=numberEntry(cinema,"Время пролёта, сек",480,132,160,.05,30);cn.fov=numberEntry(cinema,"FOV",652,132,100,20,120);cn.caption=textEntry(cinema,"Титр / субтитр",318,190,526,48,true);cn.sound=textEntry(cinema,"Путь к звуку",318,262,526);cn.image=textEntry(cinema,"Материал изображения",318,320,526);local selectedCam=0
 local function phaseCams()if not work then return{}end;work.cutscene=work.cutscene or{accept={},complete={}};local phase=csPhase.ValueID or"accept";work.cutscene[phase]=work.cutscene[phase]or{};return work.cutscene[phase]end
 local function relinkCams()local nodes=phaseCams();for i,node in ipairs(nodes)do node.next=nodes[i+1]and tostring(nodes[i+1].id or("camera_"..(i+1)))or"";if i==1 then node.transition="cut"end end end
 local function nextCameraID()local used={};for _,node in ipairs(phaseCams())do used[tostring(node.id or"")]=true end;local i=1;while used["camera_"..i]do i=i+1 end;return"camera_"..i end
 rebuildCams=function()csList:Clear();for i,n in ipairs(phaseCams())do local relation=i==1 and"СТАРТ"or(n.transition=="move"and"ПРОЛЁТ"or"СКЛЕЙКА");local line=addDarkLine(csList,i,n.id or("camera_"..i),relation,string.sub(n.caption or"",1,24));line._index=i end end
 local function loadCam(i)local n=phaseCams()[i];if not n then return end;selectedCam=i;cn.id:SetText(n.id or("camera_"..i));cn.next:SetText(n.next or"");cn.transition.ValueID=n.transition or(i==1 and"cut"or"move");cn.transition:SetValue(cn.transition.ValueID=="move"and"Плавный пролёт"or"Мгновенно");cn.duration:SetValue(n.duration or 3);cn.moveDuration:SetValue(n.moveDuration or 1);cn.fov:SetValue(n.fov or 75);cn.caption:SetText(n.caption or"");cn.sound:SetText(n.sound or"");cn.image:SetText(n.image or"")end
 csPhase.OnSelect=function(_,_,_,data)csPhase.ValueID=data;selectedCam=0;rebuildCams();if IsValid(csStrip)then csStrip:Remove()end;csStrip=lifecycleStrip(cinema,data=="complete" and "complete" or "start",8);csStrip:SetZPos(-1)end;csList.OnRowSelected=function(_,_,line)loadCam(line._index)end
 local function applyCam()local n=phaseCams()[selectedCam];if not n then return end;n.id=cn.id:GetText();n.next=cn.next:GetText();n.transition=selectedCam==1 and"cut"or(cn.transition.ValueID or"cut");n.duration=cn.duration:GetValue();n.moveDuration=cn.moveDuration:GetValue();n.fov=cn.fov:GetValue();n.caption=cn.caption:GetText();n.sound=cn.sound:GetText();n.image=cn.image:GetText();rebuildCams();loadCam(selectedCam)end
 button(cinema,"+ Точка из текущего взгляда",318,382,224,38,C.blue,function()local nodes=phaseCams();local index=#nodes+1;local n={id=nextCameraID(),next="",transition=index==1 and"cut"or"move",moveDuration=1,pos={x=EyePos().x,y=EyePos().y,z=EyePos().z},ang={p=EyeAngles().p,y=EyeAngles().y,r=EyeAngles().r},duration=3,fov=75,caption="",sound="",image=""};if nodes[index-1]and tostring(nodes[index-1].next or"")==""then nodes[index-1].next=n.id end;nodes[index]=n;rebuildCams();loadCam(index)end);button(cinema,"Применить",554,382,108,38,C.green,applyCam);button(cinema,"Удалить",674,382,82,38,C.red,function()local n=phaseCams();if selectedCam>0 then local removed=n[selectedCam];table.remove(n,selectedCam);relinkCams();selectedCam=0;rebuildCams()end end);button(cinema,"↑",768,382,36,38,C.card,function()local n=phaseCams();if selectedCam>1 then n[selectedCam],n[selectedCam-1]=n[selectedCam-1],n[selectedCam];relinkCams();selectedCam=selectedCam-1;rebuildCams();loadCam(selectedCam)end end);button(cinema,"↓",808,382,36,38,C.card,function()local n=phaseCams();if selectedCam<#n then n[selectedCam],n[selectedCam+1]=n[selectedCam+1],n[selectedCam];relinkCams();selectedCam=selectedCam+1;rebuildCams();loadCam(selectedCam)end end)
 button(cinema,"Сделать стартовой",318,430,170,40,C.yellow,function()local n=phaseCams();if selectedCam>1 then local node=table.remove(n,selectedCam);table.insert(n,1,node);relinkCams();selectedCam=1;rebuildCams();loadCam(1)end end);button(cinema,"▶ Эта точка",500,430,140,40,C.yellow,function()applyCam();local n=phaseCams()[selectedCam];if n then f:SetVisible(false);startCutscene({n},true);Q.Cutscene.restoreFrame=f end end);button(cinema,"▶ Вся связка",652,430,140,40,C.green,function()applyCam();local nodes=phaseCams();if#nodes==0 then notification.AddLegacy("Нет точек для проверки",NOTIFY_HINT,3)return end;f:SetVisible(false);startCutscene(nodes,true);Q.Cutscene.restoreFrame=f end)
 button(cinema,"Добавлять точки тулом",318,478,210,40,Color(58,82,112),function()if not work then setStatus("Выберите квест",C.red)return end;if not saveWork(true)then return end;RunConsoleCommand("grm_quest_tool_mode","cutscene");RunConsoleCommand("grm_quest_tool_quest_id",work.id);RunConsoleCommand("grm_quest_tool_phase",csPhase.ValueID or"accept");RunConsoleCommand("gmod_tool","grm_quest_tool");notification.AddLegacy("Первая точка станет стартом. Следующие автоматически связываются.",NOTIFY_HINT,7)end)
 label(cinema,"Камера №1 — старт: сцена мгновенно начинается в ней. Для остальных выберите склейку или плавный пролёт. «Следующая камера» связывает точки по ID; пустое поле использует следующую строку.\n\nКат-сцена НЕ выдаёт награду — это только ролик. Награда настраивается во вкладке «4. Награды».",318,526,526,96,"GRMQ_Small",C.dim)

 local function syncGeneral()if not work then return end;work.id=g.id:GetText();work.title=g.title:GetText();work.category=g.category:GetText();work.npc=g.npc:GetText();work.summary=g.summary:GetText();work.prerequisites=splitCSV(g.prereq:GetText());for k,c in pairs(g.flags)do work[k]=c:GetChecked()end;work.rewards=work.rewards or{};work.rewards.money=rw.money:GetValue();work.rewards.items=table.Copy(rewardItems);work.achievement={enabled=rw.achEnabled:GetChecked(),hidden=rw.achHidden:GetChecked(),id=rw.achID:GetText(),name=rw.achName:GetText(),description=rw.achDesc:GetText(),reward=rw.achReward:GetValue()};work.notifications={};for key,cfg in pairs(nt)do work.notifications[key]={enabled=cfg.enabled:GetChecked(),banner=cfg.banner:GetChecked(),text=cfg.text:GetText(),sound=cfg.sound:GetText(),duration=cfg.duration:GetValue()}end;if selectedStage>0 then applyStage()end;if selectedNode>0 then applyNode()end;if selectedCam>0 then applyCam()end end
 saveWork=function(closeAfter)
  if not work then setStatus("Сначала выберите или создайте квест",C.red)return false end;syncGeneral();if string.Trim(work.id or"")==""then setStatus("Укажите уникальный ID квеста",C.red)return false end;if string.Trim(work.title or"")==""then setStatus("Укажите название квеста",C.red)return false end;work.draft=#(work.steps or{})==0
  setStatus(work.draft and"Сохранение черновика без этапов..."or"Сохранение на сервере...",work.draft and C.yellow or C.green);net.Start("GRM_Quest_AdminOp");net.WriteString("save");net.WriteTable(work);net.SendToServer();if closeAfter then timer.Simple(.08,function()if IsValid(f)then f:Close()end end)end;return true
 end
 local function loadDef(def)work=table.Copy(def);work.steps=work.steps or{};work.rewards=work.rewards or{money=0,items={}};work.dialogue=work.dialogue or{offer={},active={},complete={}};work.cutscene=work.cutscene or{accept={},complete={}};g.id:SetText(work.id or"");g.title:SetText(work.title or"");g.category:SetText(work.category or"");g.npc:SetText(work.npc or"");g.summary:SetText(work.summary or"");g.prereq:SetText(table.concat(work.prerequisites or{},", "));for k,c in pairs(g.flags)do c:SetValue(work[k]and 1 or 0)end;rw.money:SetValue(work.rewards.money or 0);rewardItems=table.Copy(work.rewards.items or{});work.achievement=work.achievement or{};rw.achEnabled:SetValue(work.achievement.enabled and 1 or 0);rw.achHidden:SetValue(work.achievement.hidden and 1 or 0);rw.achID:SetText(work.achievement.id or("quest_"..tostring(work.id)));rw.achName:SetText(work.achievement.name or work.title or"");rw.achDesc:SetText(work.achievement.description or work.summary or"");rw.achReward:SetValue(work.achievement.reward or 0);work.notifications=work.notifications or{};for key,cfg in pairs(nt)do local value=work.notifications[key]or{};cfg.enabled:SetValue(value.enabled~=false and 1 or 0);cfg.banner:SetValue(value.banner==true and 1 or 0);cfg.text:SetText(value.text or(({start="Получен квест: {title}",step="Этап выполнен: {step}",complete="Квест завершён: {title}"})[key]));cfg.sound:SetText(value.sound or"");cfg.duration:SetValue(value.duration or 4)end;selectedStage=0;selectedNode=0;selectedCam=0;rebuildStages();rebuildRewards();rebuildNodes();rebuildCams();setStatus((work.draft and"Черновик: "or"Редактируется: ")..tostring(work.id).." · этапов: "..#work.steps,work.draft and C.yellow or C.green)end
 local function rebuildQuestList()questList:Clear();for _,d in ipairs(definitions)do local line=addDarkLine(questList,d.id,(d.draft and"[ЧЕРНОВИК] "or"")..d.title,#(d.steps or{}));line._def=d end end
 questList.OnRowSelected=function(_,_,line)loadDef(line._def)end;rebuildQuestList()
 button(f,"Новый квест",16,714,130,42,C.blue,function()local draft={draft=true,id="quest_"..os.time(),title="Новый квест",category="История",npc="guide",summary="",enabled=true,repeatable=false,autoStart=false,steps={},rewards={money=0,items={}},prerequisites={},dialogue={offer={},active={},complete={}},cutscene={accept={},complete={}}};loadDef(draft);local line=addDarkLine(questList,draft.id,"[НОВЫЙ] "..draft.title,0);line._def=draft;questList:SelectItem(line);setStatus("Черновик появился в списке. Заполните этапы и нажмите «Сохранить».",C.yellow)end)
 button(f,"Сохранить",154,714,110,42,C.green,function()saveWork(false)end)

 --[[ ПРОВЕРКА КВЕСТА (заказ владельца 28.08: «ничего не понятно в этом
      меню»).

      Раньше о том, что квест собран неправильно, автор узнавал только
      на сервере: подошёл к NPC — а взять нельзя, и почему, неизвестно.
      Кнопка прогоняет тот же Q.Validate, что и сервер, и показывает
      человеческим языком, что именно сломано и что просто подозрительно. ]]
 button(f,"Проверить",372,714,110,42,C.yellow,function()
  if not work then setStatus("Сначала выберите квест",C.red)return end
  syncGeneral()
  local issues=(Q.Validate and Q.Validate(work))or{}
  local errors,warns=0,0
  for _,it in ipairs(issues)do if it.level=="error" then errors=errors+1 else warns=warns+1 end end

  local vf=vgui.Create("DFrame")
  vf:SetSize(660,420);vf:Center();vf:MakePopup();vf:SetTitle("");vf:ShowCloseButton(true)
  vf.Paint=function(_,w,h)
   draw.RoundedBox(10,0,0,w,h,C.bg)
   draw.RoundedBoxEx(10,0,0,w,46,Color(16,25,39),true,true,false,false)
   draw.SimpleText("ПРОВЕРКА КВЕСТА","GRMQ_Title",18,23,C.text,TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER)
   local verdict = errors>0 and "НЕ БУДЕТ РАБОТАТЬ" or (warns>0 and "РАБОТАЕТ, НО ЕСТЬ ЗАМЕЧАНИЯ" or "ВСЁ В ПОРЯДКЕ")
   local vcol = errors>0 and C.red or (warns>0 and C.yellow or C.green)
   draw.SimpleText(verdict,"GRMQ_Head",w-18,23,vcol,TEXT_ALIGN_RIGHT,TEXT_ALIGN_CENTER)
  end

  local scroll=vgui.Create("DScrollPanel",vf);scroll:SetPos(14,56);scroll:SetSize(632,350)
  if #issues==0 then
   local okp=vgui.Create("DPanel",scroll);okp:SetSize(614,64);okp:Dock(TOP);okp:DockMargin(0,0,0,8)
   okp.Paint=function(_,w,h)
    draw.RoundedBox(7,0,0,w,h,Color(20,44,32));draw.RoundedBox(0,0,0,4,h,C.green)
    draw.SimpleText("Ошибок не найдено. Квест можно сохранять.","GRMQ_Body",16,22,C.text,TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER)
    draw.SimpleText("Проверьте на сервере: подойдите к NPC и возьмите задание.","GRMQ_Small",16,44,C.dim,TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER)
   end
  end
  for _,it in ipairs(issues)do
   local isErr=it.level=="error"
   local row=vgui.Create("DPanel",scroll);row:SetSize(614,52);row:Dock(TOP);row:DockMargin(0,0,0,6)
   row.Paint=function(_,w,h)
    draw.RoundedBox(7,0,0,w,h,isErr and Color(46,20,24) or Color(44,37,18))
    draw.RoundedBox(0,0,0,4,h,isErr and C.red or C.yellow)
    draw.SimpleText(isErr and "ОШИБКА" or "ВНИМАНИЕ","GRMQ_Small",16,15,isErr and C.red or C.yellow,TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER)
    draw.SimpleText(tostring(it.text or""),"GRMQ_Small",16,34,C.text,TEXT_ALIGN_LEFT,TEXT_ALIGN_CENTER)
   end
  end
  setStatus(("Проверка: ошибок %d, замечаний %d"):format(errors,warns),
   errors>0 and C.red or (warns>0 and C.yellow or C.green))
 end)
 button(f,"Удалить",490,714,90,42,C.red,function()if not work then setStatus("Выберите квест",C.red)return end;Derma_Query("Удалить квест «"..tostring(work.title).."»?","GRM Quest Studio","Удалить",function()net.Start("GRM_Quest_AdminOp");net.WriteString("delete");net.WriteString(work.id or"");net.SendToServer();setStatus("Удаление...",C.yellow)end,"Отмена")end)
 local status=label(f,"",592,714,600,42,"GRMQ_Body",C.dim);status.Think=function(self)self:SetText(statusText);self:SetTextColor(statusColor)end
 if definitions[1]then loadDef(definitions[1])end
end
--[[ ОКНО РЕДАКТОРА ОТКРЫВАЕТ ТОЛЬКО zz_grm_quest_studio (узловой граф).
     Здесь стоял второй net.Receive на GRM_Quest_AdminOpen, открывавший
     старое вкладочное окно. Два ресивера на одно сообщение — это не «оба
     сработают», а «второй заменит первый»: какой именно останется,
     решал алфавитный порядок загрузки (cl_… против zz_…). Достаточно
     переименовать файл — и у владельца молча открылся бы старый
     редактор вместо графа. Оставляем один явный вход. ]]
net.Receive("GRM_Quest_AdminOpen", function()
    local data = net.ReadTable() or {}
    if Q.OpenGraphStudio then return Q.OpenGraphStudio(data) end
    -- Узловой редактор почему-то не загрузился — открываем старое окно,
    -- чтобы админ не остался вовсе без инструмента.
    adminStudio(data)
end)
concommand.Add("grm_quests_admin",function()net.Start("GRM_Quest_AdminOp")net.WriteString("request")net.SendToServer()end)
print("[GRM Quests] client v1.4.0 loaded")
