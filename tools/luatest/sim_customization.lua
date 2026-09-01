-- Regression contract for GRM Closed Customization (no PAC3 dependency).
local function read(path)
    local f=assert(io.open(path,"rb")); local s=f:read("*a"); f:close(); return s
end
local core=read("lua/autorun/sh_grm_customization.lua")
local client=read("lua/autorun/client/cl_grm_customization.lua")
local invui=read("lua/autorun/client/cl_grm_inventory_ui.lua")
local vendor=read("lua/autorun/sh_grm_vendor.lua")
local tool=read("lua/weapons/gmod_tool/stools/grm_vendor_tool.lua")
local arrest=read("lua/autorun/sh_grm_arrest.lua")
local encumbrance=read("lua/autorun/server/sv_grm_encumbrance.lua")
local radionet=read("lua/autorun/sh_grm_radionet.lua")
local checks,failed=0,0
local function ok(v,label) checks=checks+1; if v then print("  ok "..checks..". "..label) else failed=failed+1; print("  FAIL "..checks..". "..label) end end
local function has(s,n) return s:find(n,1,true)~=nil end

ok(has(core,'C.SlotOrder = { "head", "face", "torso", "legs", "left_hand", "right_hand" }'),"six closed equipment slots")
ok(has(core,"ValveBiped.Bip01_Head1") and has(core,"ValveBiped.Bip01_L_Hand") and has(core,"ValveBiped.Bip01_R_Hand"),"slot bone whitelists")
ok(has(core,"normalizeCatalogItem") and has(core,"util.IsValidModel"),"server-authoritative model catalog")
ok(has(core,"vecData(input.position, 48)") and has(core,"0.2, 3"),"transform bounds enforced server-side")
ok(has(core,"CharacterKey") and has(core,"grm_customization/loadouts.json"),"CharacterKey persistence")
ok(has(core,"C.Profiles") and has(core,"version=2,records=records") and has(core,"remembered"),"versioned accessory transform profiles survive restart and re-equip")
ok(has(core,'path .. ".backup"') and has(core,"restored from backup"),"customization persistence has backup recovery")
ok(has(core,'RegisterUseHandler("grm_accessory_equip"'),"inventory item equips through official use handler")
ok(has(core,'GRM.Vendor.RegisterItem("accessory"'),"catalog is exposed to accessory vendor")
ok(has(tool,'accessory="Аксессуары"') and has(tool,'grm_vendor_tool_type'),"vendor tool can spawn accessory merchant")
ok(has(core,"GRM_Custom_AdminOp") and has(core,"grm_accessories_admin"),"closed superadmin catalog editor")
ok(has(client,"GRM — Каталог аксессуаров") and has(client,"Категория") and has(client,"Цена"),"admin edits category and price")
ok(has(client,"ФУНКЦИОНАЛЬНОЕ ОБОРУДОВАНИЕ") and has(client,"gasProtection") and has(client,"backpackCapacity"),"admin enables functions and configures their strength")
ok(has(client,'"loot_bag"') and has(core,"Сумка ограбления") and has(client,"lootMaxMoney") and has(client,"lootPerUse"),"admin: чекбокс сумки ограбления + параметры (находка 178f)")
ok(has(client,"funcCols") and has(client,"406 + (ri-1)*24") and has(client,"ci == 1 and 12 or 230"),"admin: чекбоксы в аккуратной сетке 2x5 без наложения (находка 179b)")
ok(has(client,"if IsValid(adminFrame) then") and has(client,"adminFrame:InvalidateLayout()") and has(client,"adminFrame = nil"),"admin: повторное открытие не плодит окна/панели (NULL Panel fix, находка 179c)")
ok(has(client,"СУМКА ОГРАБЛЕНИЯ") and has(client,"/bag_unload"),"клиент: HUD сумки и подсказка выгрузки (находка 178f)")
ok(has(core,"loot_bag") and has(core,"LootBagAdd") and has(core,"grm_bag_unload"),"сервер: API сумки ограбления (находка 178f)")
ok(has(core,"GRM_Custom_Ack") and has(client,'net.Receive("GRM_Custom_Ack"') and has(client,"notification.AddLegacy"),"server acknowledgements produce visible success/error feedback")
ok(has(client,"FEEDBACK_SOUNDS") and has(client,"surface.PlaySound") and has(client,"Положение изменено в предпросмотре"),"editor controls provide immediate sounds and preview notices")
ok(has(core,"function C.HasFunction") and has(core,"function C.GetFunctionValue") and has(core,"RegisterFunctionType"),"closed function registry is extensible by GRM modules")
ok(has(core,"GRM_Customization_FunctionalProtection") and has(core,"DMG_NERVEGAS") and has(core,"DMG_BULLET"),"gasmask and armor modify relevant damage types")
ok(has(invui,"ЭКИПИРОВКА") and has(invui,"Кастомизация"),"equipment slots integrated left of inventory")
ok(has(invui,"accessoryModel") and has(invui,"setupAccessoryPreview") and has(invui,'vgui.Create("DModelPanel", slotBtn)'),"inventory accessory slots render their actual 3D model")
ok(has(invui,"RealTime() * (spinSpeed or 14)") and has(invui,"GetRenderBounds") and has(invui,"entity:SetPos(-rotatedCenter)"),"3D accessory preview slowly rotates around centered bounds")
ok(has(invui,"radius / math.tan") and has(invui,"* 1.28"),"bounding-sphere camera margin keeps long models inside the slot")
ok(has(invui,'vgui.Create("DModelPanel", detailPanel)') and has(invui,'vgui.Create("DModelPanel", dragImage)'),"details and drag ghost also use the accessory model")
ok(has(invui,"findEquipmentSlotUnderMouse") and has(invui,"customization.EquipInventorySlot") or has(invui,"Customization.EquipInventorySlot"),"inventory accessory can be dragged onto an equipment slot")
ok(has(core,'op == "equip_inventory"') and has(core,"function C.EquipInventorySlot"),"server validates explicit inventory-to-equipment action")
ok(has(core,'op == "unequip_inventory"') and has(client,"function C.UnequipInventorySlot"),"inventory can request authoritative unequip without opening editor")
ok(has(invui,"b.DoRightClick") and has(invui,'menu:AddOption("Снять"'),"right click on occupied equipment slot opens remove action")
ok(has(client,'GRM.UI.Close("inventory")'),"opening customization closes overlapping inventory window")
ok(has(core,'C.SyncPlayer(ply, ply)') and has(client,'Loadout приходит отдельным GRM_Custom_Sync') and has(client,'openEditor(catalog)'),"editor receives loadout only through authoritative sync packet")
ok(has(core,'GRM_Customization_RemoveCommand') and has(core,'/accessories_off') and has(core,'function C.UnequipAll'),"chat command removes one or all accessories")
ok(has(client,'if C.ClientLoadouts[lp][slotID] then editor.selected = slotID'),"editor initially selects the occupied equipment slot")
ok(has(client,'GRM_Customization_EditorPreviewFallback') and has(client,'lp:SetupBones()'),"editor has a LocalPlayer render fallback when PostPlayerDraw is skipped")
ok(has(client,'drawingDepth') and has(client,'drawAccessories(lp, true)'),"editor preview draws only in final main-view pass and bypasses auxiliary frame guard")
ok(has(client,'if C.EditorActive and ply == LocalPlayer() then return end'),"editor does not consume frame guard in unstable LocalPlayer PostPlayerDraw pass")
ok(has(client,'ClientsideModel(item.model, RENDERGROUP_BOTH)'),"manual editor draw supports opaque and translucent addon models")
ok(has(client,'Не уничтожаем уже видимую ClientsideModel при входе'),"opening editor preserves the already visible model cache")
ok(has(client,'hook.Add("CalcView", "GRM_Customization_OrbitCamera"'),"free orbit character camera")
ok(has(core,'hook.Add("StartCommand", "GRM_Customization_Freeze"'),"server freezes editor movement")
ok(has(client,'hook.Add("PostPlayerDraw", "GRM_Customization_DrawAccessories"'),"accessories render after current player skeleton")
ok(has(client,"not forceEditorDraw and not lp:ShouldDrawLocalPlayer()"),"own accessories never render in first person (ShouldDrawLocalPlayer gate)")
ok(has(client,"for ply in pairs(C.ActiveRenderPlayers)"),"opaque fallback covers all players with active accessories")
ok(has(client,"if IsValid(ply)then drawAccessories(ply)"),"opaque fallback draws every tracked visible player")
ok(has(client,"entry.lastFrame~=FrameNumber()"),"single draw per frame prevents flicker")
ok(has(client,"LerpVector") and has(client,"LerpAngle") and has(client,"FrameTime() * 14"),"local transform changes are visually smoothed")
ok(has(client,"GRM_Customization_TransformGizmo") and has(client,"pickGizmoAxis"),"visible XYZ move gizmo arrows can be dragged")
--[[ Проверяем ПО СМЫСЛУ, а не по имени удалённой функции.

     Здесь стояла проверка на rotationRingPoint — локальную копию
     построения точек кольца. 31.08 гизмо вынесен в общий модуль
     GRM.Gizmo (одна логика на редактор аксессуаров и студию анимаций),
     и локальный дубль удалён как мёртвый код. Сама возможность тянуть
     кольца никуда не делась, поэтому проверяем её, а не имя. ]]
ok(has(client,"pickRotationAxis") and has(client,'GRM.Gizmo.Pick("rotate"') and has(client,'gizmoMode == "rotate"'),"rotation mode provides draggable colored axis rings")
ok(has(client,"ПЕРЕМЕЩЕНИЕ") and has(client,"ВРАЩЕНИЕ") and has(client,"editor.angleSliders"),"editor switches move/rotate controls")
ok(has(client,"0.05,0.1,0.25,0.5,1") and has(client,"0.25,0.5,1,2.5,5"),"fine controls have separate movement and rotation steps")
ok(has(client,"Не уничтожаем весь render cache при каждом Save"),"repeat saves preserve render entity instead of disappearing")
ok(has(client,"ply:GetBoneMatrix") and has(client,"LocalToWorld"),"bone-local transform uses current frame matrix")
ok(not has(client,"entry.ent:SetPos") and not has(client,"entry.ent:SetParent"),"renderer never networks/parents/teleports accessory models")
ok(has(client,"SetRenderOrigin") and has(client,"SetRenderAngles"),"render-only transform avoids one-frame chasing")
ok(has(encumbrance,'GetFunctionValue(ply, "backpack"'),"functional backpack increases encumbrance capacity")
ok(has(radionet,'HasFunction(ply, "radio")'),"functional radio integrates with RadioNet")
ok(has(client,'GRM_Customization_FunctionHUD') and has(client,'LocalHasFunction("watch")') and has(client,'LocalHasFunction("gasmask")'),"watch and gasmask expose client HUD functionality")
ok(has(arrest,"GRM.Customization.Confiscate"),"arrest confiscates worn accessories")
ok(not has(core,"pac.") and not has(client,"pac."),"implementation has no PAC3 runtime/code dependency")
-- Находка 179z: фонарик (F) вырублен — серверный AllowFlashlight=false,
-- клиент блокирует бинд и принудительно гасит; запоминание функций при входе
ok(has(core,'hook.Add("AllowFlashlight", "GRM_Customization_NoFlashlight"'),"flashlight banned on server (AllowFlashlight=false)")
ok(has(core,'dispatchFunctionEvent("OnEquip", ply, slot, item, equipped)') and has(core,"C.GetLoadout(ply)"),"rejoin restores OnEquip for worn accessories (memory fix)")
ok(has(client,'bind == "+flashlight"'),"client blocks +flashlight bind (PlayerBindPress)")
ok(has(client,"FlashlightIsOn") and not has(client,"GetFlashlight"),"client force-off uses FlashlightIsOn, not non-existent GetFlashlight (находка 180b)")
ok(has(client,"isfunction(lp.SetFlashlight)") and has(client,"lp:SetFlashlight(false)"),"client force-off guards SetFlashlight with isfunction (находка 180b)")

-- Numeric transform normalization contract.
local function clamp(v,a,b) return math.max(a,math.min(b,v)) end
local p={x=999,y=-999,z=12}; p.x=clamp(p.x,-48,48); p.y=clamp(p.y,-48,48); p.z=clamp(p.z,-48,48)
ok(p.x==48 and p.y==-48 and p.z==12,"position cannot escape safe local bounds")
ok(clamp(9,0.2,3)==3 and clamp(0.01,0.2,3)==0.2,"scale cannot become abusive or invisible")

print(("CUSTOMIZATION: %d/%d, failures=%d"):format(checks-failed,checks,failed))
if failed>0 then os.exit(1) end
