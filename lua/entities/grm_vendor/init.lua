-- GRM Vendor Entity v2.0 — authoritative transactions and persistence
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

for _, name in ipairs({"GRM_Vendor_Open","GRM_Vendor_Buy","GRM_Vendor_Sell","GRM_Vendor_Result"}) do
    util.AddNetworkString(name)
end

local function notify(ply, ok, text)
    if not IsValid(ply) then return end
    net.Start("GRM_Vendor_Result") net.WriteBool(ok == true) net.WriteString(tostring(text or "")) net.Send(ply)
    if GRM.Notify then GRM.Notify(ply, tostring(text or ""), ok and 100 or 255, ok and 220 or 110, ok and 130 or 90) end
end

local function inRange(ply, ent)
    if not IsValid(ply) or not ply:IsPlayer() or not IsValid(ent) or ent:GetClass() ~= "grm_vendor" then return false end
    local distance = GRM.Vendor and GRM.Vendor.Config and GRM.Vendor.Config.UseDistance or 120
    return ply:Alive() and ply:GetPos():DistToSqr(ent:GetPos()) <= distance * distance
end

local function rateOK(ply, key, delay)
    ply.GRMVendorRates = ply.GRMVendorRates or {}
    if CurTime() < (ply.GRMVendorRates[key] or 0) then return false end
    ply.GRMVendorRates[key] = CurTime() + (delay or 0.25)
    return true
end

function ENT:Initialize()
    local V = GRM.Vendor
    self.VendorType = (V and V.ResolveType and V.ResolveType(self.VendorType, self.VendorType)) or self.VendorType or "weapon"
    self.VendorModel=tostring(self.VendorModel or "")
    self:SetModel(util.IsValidModel(self.VendorModel) and self.VendorModel or ((V and V.Models and V.Models[self.VendorType]) or "models/kleiner.mdl"))
    self:SetSolid(SOLID_BBOX)
    self:SetMoveType(MOVETYPE_NONE)
    self:SetCollisionGroup(COLLISION_GROUP_NPC)
    self:SetUseType(SIMPLE_USE)
    self:SetAutomaticFrameAdvance(true)
    self.CustomPrices = istable(self.CustomPrices) and self.CustomPrices or {}
    self.CustomLimits = istable(self.CustomLimits) and self.CustomLimits or {}
    self.EnabledItems = istable(self.EnabledItems) and self.EnabledItems or {}
    self.DisplayName = tostring(self.DisplayName or ""):sub(1, 64)
    self:SetNWString("VendorType", self.VendorType)
    self:SetNWString("GRMVendorID", tostring(self.GRMVendorID or ""))
    self:SetNWString("GRMVendorName", V and V.GetDisplayName(self) or "GRM Торгаш")
    self:SetupIdleAnimation()
end

function ENT:SetupIdleAnimation()
    local sequence = self:SelectWeightedSequence(ACT_IDLE)
    if not sequence or sequence < 0 then
        for _, name in ipairs({"idle_all","idle","idle_unarmed","stand","ref","idle_01"}) do
            sequence = self:LookupSequence(name)
            if sequence and sequence >= 0 then break end
        end
    end
    if sequence and sequence >= 0 then self:ResetSequence(sequence); self:SetPlaybackRate(1); self:ResetSequenceInfo() end
end

function ENT:BuildCatalogPayload()
    local V = GRM.Vendor
    local payload = {}
    for id, item in pairs(V.GetCatalog(self.VendorType)) do
        if V.IsItemEnabled(self, id) then
            payload[id] = {
                name=tostring(item.name or id), desc=tostring(item.desc or ""), category=tostring(item.category or "Прочее"),
                model=tostring(item.model or ""), price=V.GetPrice(self,id,item), sellPrice=V.GetSellPrice(nil,self.VendorType,id),
                limit=V.GetLimit(self,id), license=item.license, hunger=item.hunger, health=item.health,
                maxStack=item.maxStack, isWeapon=self.VendorType == "weapon" or item.isWeapon == true, isEntity=item.isEntity == true,
                weaponCategory=item.weaponCategory, requiresLicense=(self.VendorType=="weapon" and item.license~="police"),
                functions=table.Copy(item.functions or {}), functionConfig=table.Copy(item.functionConfig or {}),
            }
        end
    end
    return payload
end

function ENT:OpenFor(ply)
    if not inRange(ply,self) then return end
    net.Start("GRM_Vendor_Open")
        net.WriteEntity(self)
        net.WriteString(self.VendorType)
        net.WriteString(GRM.Vendor.GetDisplayName(self))
        net.WriteTable(self:BuildCatalogPayload())
    net.Send(ply)
end

function ENT:Use(ply)
    if not rateOK(ply,"open",0.4) then return end
    -- Торговец редкостями может быть настроен как точка входа в единый
    -- гражданский транспортный рынок; каталог/покупки не дублируются в Vendor.
    if self.VendorType == "vehicle_market" and GRM.CivilVehicles and GRM.CivilVehicles.Open then
        GRM.CivilVehicles.Open(ply,self)
        return
    end
    self:OpenFor(ply)
end

local function ownedCount(ply, itemID, item)
    local count = 0
    if item.isWeapon then count = ply:HasWeapon(itemID) and 1 or 0 end
    if GRM.Inventory and GRM.Inventory.CountItem then count = count + (tonumber(GRM.Inventory.CountItem(ply,itemID)) or 0) end
    return count
end

local function grantItem(ply, itemID, item)
    if item.isEntity then
        local entity = ents.Create(tostring(item.class or itemID))
        if not IsValid(entity) then return false, "Не удалось создать объект" end
        entity:SetPos(ply:GetPos()+ply:GetForward()*70+Vector(0,0,24)); entity:SetAngles(Angle(0,ply:EyeAngles().y,0)); entity:Spawn(); entity:Activate()
        if entity.SetPrinterOwner then entity:SetPrinterOwner(ply) else entity:SetOwner(ply) end
        local phys=entity:GetPhysicsObject(); if IsValid(phys) then phys:Wake() end
        return true
    end
    if item.isWeapon then
        if ply:HasWeapon(itemID) then return false, "Это оружие уже есть" end
        return IsValid(ply:Give(itemID)), "Не удалось выдать оружие"
    end
    if not (GRM.Inventory and GRM.Inventory.AddItem) then return false, "Инвентарь не загружен" end
    return (tonumber(GRM.Inventory.AddItem(ply,itemID,1)) or 1) == 0, "Инвентарь заполнен или предмет недоступен"
end

net.Receive("GRM_Vendor_Buy",function(_,ply)
    local ent,itemID=net.ReadEntity(),net.ReadString()
    if not inRange(ply,ent) or not rateOK(ply,"buy",0.3) then return end
    local V,item=GRM.Vendor,GRM.Vendor.GetItem(ent.VendorType,itemID)
    if item then item=table.Copy(item);if ent.VendorType=="weapon"then item.isWeapon=true end end
    if not item or not V.IsItemEnabled(ent,itemID) then notify(ply,false,"Товар отсутствует у этого торговца") return end
    if ply:GetNWBool("GRM_Arrested",false) then notify(ply,false,"Покупки недоступны во время ареста") return end
    local canBuy,licenseWhy=V.CanBuyWeapon(ply,item)
    if not canBuy then notify(ply,false,licenseWhy or "Нет необходимого допуска или лицензии") return end
    local limit=V.GetLimit(ent,itemID)
    if limit>0 and ownedCount(ply,itemID,item)>=limit then notify(ply,false,"Достигнут лимит: "..limit) return end
    local price=V.GetPrice(ent,itemID,item)
    if price>0 and (not GRM.HasMoney or not GRM.HasMoney(ply,price)) then notify(ply,false,"Недостаточно средств: "..(GRM.Format and GRM.Format(price) or price)) return end
    local granted,reason=grantItem(ply,itemID,item)
    if not granted then notify(ply,false,reason or "Товар не выдан") return end
    if price>0 and GRM.TakeMoney then GRM.TakeMoney(ply,price,"Покупка у "..V.GetDisplayName(ent)..": "..tostring(item.name or itemID)) end
    notify(ply,true,"Куплено: "..tostring(item.name or itemID).." за "..(GRM.Format and GRM.Format(price) or price))
    hook.Run("GRM_VendorPurchased",ply,ent,itemID,item,price)
end)

local function removeInventoryAmount(ply,itemID,wanted)
    if not (GRM.Inventory and GRM.Inventory.RemoveItem) then return 0 end
    local before=GRM.Inventory.CountItem and GRM.Inventory.CountItem(ply,itemID) or wanted
    local remaining=tonumber(GRM.Inventory.RemoveItem(ply,itemID,wanted)) or wanted
    local removed=math.Clamp(wanted-remaining,0,math.min(wanted,before))
    return removed
end

net.Receive("GRM_Vendor_Sell",function(_,ply)
    local ent,itemID,wanted=net.ReadEntity(),net.ReadString(),math.Clamp(net.ReadUInt(16),1,1000)
    if not inRange(ply,ent) or not rateOK(ply,"sell",0.35) then return end
    local V,item=GRM.Vendor,GRM.Vendor.GetItem(ent.VendorType,itemID)
    if item then item=table.Copy(item);if ent.VendorType=="weapon"then item.isWeapon=true end end
    if not item or not V.IsItemEnabled(ent,itemID) or item.noSell or item.isEntity then notify(ply,false,"Этот товар не скупается") return end
    local removed=0
    if item.isWeapon and ply:HasWeapon(itemID) and wanted>0 then ply:StripWeapon(itemID); removed=1 end
    if removed<wanted then removed=removed+removeInventoryAmount(ply,itemID,wanted-removed) end
    if removed<=0 then notify(ply,false,"У вас нет этого товара") return end
    local unit=math.floor(V.GetPrice(ent,itemID,item)*(V.Config.SellMultiplier or 0.4))
    local total=math.max(0,removed*unit)
    if total>0 and GRM.GiveMoney then GRM.GiveMoney(ply,total,"Продажа торговцу: "..itemID) end
    notify(ply,true,"Продано: "..removed.." шт. за "..(GRM.Format and GRM.Format(total) or total))
    hook.Run("GRM_VendorSold",ply,ent,itemID,item,removed,total)
end)

function ENT:GetPermData()
    return {vendorType=self.VendorType,vendorID=self.GRMVendorID,displayName=self.DisplayName,model=self:GetModel(),customPrices=self.CustomPrices,customLimits=self.CustomLimits,enabledItems=self.EnabledItems}
end

function ENT:ApplyPermData(data)
    if not istable(data) then return end
    local V=GRM.Vendor
    self.VendorType=V and V.Catalogs[data.vendorType] and data.vendorType or "weapon"
    self.GRMVendorID=tostring(data.vendorID or self.GRMVendorID or "")
    self.GRMVendorPersistent=self.GRMVendorID~=""
    self.DisplayName=tostring(data.displayName or ""):sub(1,64)
    self.CustomPrices=table.Copy(data.customPrices or {})
    self.CustomLimits=table.Copy(data.customLimits or {})
    self.EnabledItems=table.Copy(data.enabledItems or {})
    self.VendorModel=tostring(data.model or self.VendorModel or "")
    self:SetModel(util.IsValidModel(self.VendorModel) and self.VendorModel or (V.Models[self.VendorType] or "models/kleiner.mdl"))
    self:SetNWString("VendorType",self.VendorType); self:SetNWString("GRMVendorID",self.GRMVendorID); self:SetNWString("GRMVendorName",V.GetDisplayName(self))
    self:SetupIdleAnimation()
end

print("[GRM Vendor] Entity server v2.0 loaded")
