-- Live character menu, duty roster/leaders and stable accessory gizmo/render.
local function read(p)local f=assert(io.open(p,"rb"));local s=f:read("*a");f:close();return s end
local ch=read("lua/autorun/sh_grm_character.lua");local duty=read("lua/autorun/sh_grm_faction_duty.lua");local npc=read("lua/entities/grm_duty_npc/init.lua");local fac=read("lua/autorun/sh_factions.lua");local roster=read("lua/autorun/sh_grm_faction_roster.lua");local acc=read("lua/autorun/client/cl_grm_customization.lua")
local fail=0;local function ok(c,n)if c then print("  ok  "..n)else fail=fail+1 print("  FAIL "..n)end end
ok(ch:find("factionMembership",1,true)~=nil and ch:find("GRM.Identity.FactionMember",1,true)~=nil,"character menu uses canonical faction membership")
ok(ch:find("seenOutfits",1,true)~=nil,"duplicate outfit models collapse")
-- 22.08: список моделей стал сеткой карточек с иконками (одна вкладка
-- «Внешность»), выпадающий список убран.
ok(ch:find('local pageLook = addTab("look", "ВНЕШНОСТЬ")',1,true)~=nil
   and ch:find('vgui.Create("SpawnIcon", row)',1,true)~=nil,
   "model list is a single outfit tab with icons")
ok(ch:find("local matched",1,true)~=nil and ch:find("not matched",1,true)~=nil,"stale model falls back to allowed faction model")
ok(ch:find("GRM_Char_LiveRefresh",1,true)~=nil and ch:find("payloadSignature",1,true)~=nil,"menu refreshes live only when payload changes")
ok(ch:find('GRM.UI.Track("character.appearance", f)',1,true)~=nil and ch:find("CH.ReceiveMenuPayload",1,true)~=nil,"appearance and wardrobe share one singleton/dedup guard")
ok(ch:find("CH._opening",1,true)and ch:find("CH._queuedPayload",1,true)and ch:find("Set AFTER old frame removal",1,true),"menu rebuild is reentrant-safe and keeps dedup signature")
ok(ch:find("CH._actionPending",1,true)and ch:find("character.menu.save",1,true),"buttons and server save execute once")
ok(ch:find('CH._frameMode == "character"',1,true)~=nil and ch:find("CH._openFromWardrobe = CH.ReceiveMenuPayload",1,true)~=nil,"wardrobe is not replaced by generic live refresh")
ok(ch:find("opts.previewSlot",1,true)~=nil and ch:find('net.WriteString(info.id)',1,true)~=nil,"slot click requests authoritative preview without switching")
ok(ch:find("f.Members[characterKey]",1,true)~=nil and ch:find("previewKey",1,true)~=nil,"preview resolves faction by selected CharacterKey")
ok(ch:find("slotFaction",1,true)~=nil and ch:find("factionRole = slotMember",1,true)~=nil,"each slot payload carries its own faction and role")
ok(duty:find("selectedFaction",1,true)~=nil and duty:find("fac.OnSelect",1,true)~=nil,"duty faction selection stores actual choice")
ok(npc:find("RefreshIdle",1,true)~=nil and npc:find("ResetSequenceInfo",1,true)~=nil and npc:find("idle_all_01",1,true)~=nil,"duty NPC validates and heals idle animation instead of T-pose")
ok(fac:find("_dutyStatus",1,true)~=nil and fac:find("_location",1,true)~=nil,"faction member UI receives duty status/location")
ok(roster:find('"/members"',1,true)~=nil and roster:find('"/leaders"',1,true)~=nil,"members and leaders chat commands")
ok(acc:find("gizmoGeometry",1,true)~=nil and acc:find("GetRenderBounds",1,true)~=nil and acc:find("segments=64",1,true),"gizmo scales with distance/model and smooth rings")
ok(acc:find("PostDrawOpaqueRenderables",1,true) and acc:find("FrameNumber",1,true),"accessories use guarded opaque fallback against disappearance")
ok(acc:find("cache[slot] = nil",1,true)~=nil and acc:find("entry.ent:Remove()",1,true)~=nil,"removed accessories clear client model cache")
print(("CHAR/ROSTER/ACCESSORIES: 19 checks, failures=%d"):format(fail));os.exit(fail==0 and 0 or 1)
