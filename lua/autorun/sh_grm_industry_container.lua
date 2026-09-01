--[[--------------------------------------------------------------------
    GRM Container — единая ёмкость для всего, что хранит предметы.

    ПОЧЕМУ ЭТОТ СЛОЙ ВООБЩЕ ЕСТЬ. В старой сборке «ёмкость» была
    реализована пять раз: инвентарь игрока, FC.StorageData, L.Warehouses,
    грузовой ящик и багажник. Перенести предмет между ними можно было
    только через руки игрока, и каждый перенос писал свой файл своим
    форматом. Любая новая механика (заказ на склад, погрузка в машину,
    выход станка) требовала пятой, шестой, седьмой реализации.

    Здесь одна модель: контейнер с содержимым и необязательным лимитом
    по весу. Конкретное хранилище подключается адаптером.

    ПРАВИЛА.
      * Сервер — единственный владелец содержимого. Клиент получает
        только снимок для отрисовки.
      * Перенос атомарный: либо всё, либо ничего. Неудачная половина
        откатывается, а не оставляет предмет в никуда.
      * Вес считается от справочника GRM.Industry.Items.
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

GRM = GRM or {}
GRM.Container = GRM.Container or {}
--[[ Таблицу создаём здесь, а не ждём ядра. ПО АЛФАВИТУ ЭТОТ ФАЙЛ
     ИДЁТ РАНЬШЕ sh_grm_industry_core.lua (container < core),
     поэтому `local I = GRM.Industry` ниже получал nil. Всё загружалось
     без единой ошибки, а первый же перенос предмета падал:
         attempt to index upvalue 'I' (a nil value)
     Игрок видел «Сбой действия» и не мог взять лом из источника.

     Поля (WeightOf, NameOf, Items) заполняет ядро — они нужны только
     в момент обращения, а не при загрузке, поэтому создавать таблицу
     здесь безопасно. ]]
GRM.Industry = GRM.Industry or {}
local C = GRM.Container

C.Version = "1.0.0"
C.Registry = C.Registry or {}

local I = GRM.Industry

-- ================================================================
--  АДАПТЕРЫ ХРАНИЛИЩ
-- ================================================================
--[[ store — обычный контейнер в реестре (станок, склад, ящик, машина).
     player — виртуальный: владелец предметов остаётся GRM.Inventory. ]]
local Backends = {}

Backends.store = {
    count = function(c, itemID)
        return math.floor(tonumber(c.items[tostring(itemID or "")]) or 0)
    end,
    list = function(c)
        local out = {}
        for id, n in pairs(c.items or {}) do
            n = math.floor(tonumber(n) or 0)
            if n > 0 then out[#out + 1] = { itemID = id, count = n } end
        end
        table.sort(out, function(a, b) return (I.NameOf(a.itemID)) < (I.NameOf(b.itemID)) end)
        return out
    end,
    add = function(c, itemID, n)
        c.items[tostring(itemID)] = math.floor(tonumber(c.items[tostring(itemID)]) or 0) + n
        return true
    end,
    take = function(c, itemID, n)
        local key = tostring(itemID)
        local have = math.floor(tonumber(c.items[key]) or 0)
        if have < n then return false, "not_enough" end
        c.items[key] = have - n
        if c.items[key] <= 0 then c.items[key] = nil end
        return true
    end,
    clear = function(c) c.items = {} end,
}

Backends.player = {
    count = function(c, itemID)
        if not (I and c.Player and IsValid(c.Player)) then return 0 end
        if not (GRM.Inventory and GRM.Inventory.CountItem) then return 0 end
        return math.floor(tonumber(GRM.Inventory.CountItem(c.Player, itemID)) or 0)
    end,
    list = function(c)
        if not (c.Player and IsValid(c.Player)) then return {} end
        if not (GRM.Inventory and GRM.Inventory.GetPlayerInv) then return {} end
        local inv = GRM.Inventory.GetPlayerInv(c.Player)
        local merged, out = {}, {}
        for _, slot in pairs(inv and inv.slots or {}) do
            if slot and slot.id then
                merged[slot.id] = (merged[slot.id] or 0) + math.max(1, tonumber(slot.count) or 1)
            end
        end
        for id, n in pairs(merged) do out[#out + 1] = { itemID = id, count = n } end
        table.sort(out, function(a, b) return (I.NameOf(a.itemID)) < (I.NameOf(b.itemID)) end)
        return out
    end,
    add = function(c, itemID, n)
        if not (c.Player and IsValid(c.Player)) then return false, "no_player" end
        if not (GRM.Inventory and GRM.Inventory.AddItem) then return false, "no_inventory" end
        -- AddItem возвращает, сколько НЕ влезло.
        local left = tonumber(GRM.Inventory.AddItem(c.Player, itemID, n)) or n
        if left > 0 then
            -- Частично добавилось — убираем обратно, перенос должен быть
            -- «всё или ничего», иначе половина груза зависнет в руках.
            local added = n - left
            if added > 0 and GRM.Inventory.RemoveItem then
                GRM.Inventory.RemoveItem(c.Player, itemID, added)
            end
            return false, "no_space"
        end
        return true
    end,
    take = function(c, itemID, n)
        if not (c.Player and IsValid(c.Player)) then return false, "no_player" end
        if not (GRM.Inventory and GRM.Inventory.RemoveItem) then return false, "no_inventory" end
        -- RemoveItem возвращает, сколько НЕ удалось снять.
        local left = tonumber(GRM.Inventory.RemoveItem(c.Player, itemID, n)) or n
        if left > 0 then return false, "not_enough" end
        return true
    end,
    clear = function() return false, "not_supported" end,
}

local function backend(c)
    return Backends[tostring(c and c.kind or "")] or Backends.store
end

-- ================================================================
--  РЕЕСТР
-- ================================================================
function C.Ensure(id, kind, owner, capacity)
    id = tostring(id or "")
    if id == "" then return nil, "bad_id" end
    local c = C.Registry[id]
    if c then
        if owner ~= nil then c.owner = owner end
        if capacity ~= nil then c.capacity = tonumber(capacity) end
        return c
    end
    c = {
        id = id,
        kind = tostring(kind or "store"),
        owner = owner or "",
        capacity = tonumber(capacity) or -1,   -- -1 = без лимита
        items = {},
    }
    C.Registry[id] = c
    return c
end

function C.Get(id)
    return C.Registry[tostring(id or "")]
end

function C.Remove(id)
    C.Registry[tostring(id or "")] = nil
    return true
end

function C.All()
    local out = {}
    for id, c in pairs(C.Registry) do out[#out + 1] = c end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

-- Контейнер игрока виртуальный: его нельзя «создать», только получить.
function C.ForPlayer(ply)
    if not IsValid(ply) then return nil end
    local key = "player:" .. tostring(ply:SteamID64() or ply:EntIndex())
    local c = C.Registry[key]
    if not c then
        c = C.Ensure(key, "player", tostring(ply:SteamID64() or ""), -1)
    end
    c.Player = ply
    return c
end

-- ================================================================
--  ЧТЕНИЕ
-- ================================================================
function C.Count(id, itemID)
    local c = C.Get(id)
    if not c then return 0 end
    return backend(c).count(c, itemID)
end

function C.Has(id, itemID, amount)
    return C.Count(id, itemID) >= math.max(0, math.floor(tonumber(amount) or 0))
end

function C.List(id)
    local c = C.Get(id)
    if not c then return {} end
    return backend(c).list(c)
end

function C.Capacity(id)
    local c = C.Get(id)
    if not c then return -1 end
    return tonumber(c.capacity) or -1
end

function C.Weight(id)
    local total = 0
    for _, line in ipairs(C.List(id)) do
        total = total + I.WeightOf(line.itemID) * line.count
    end
    return math.floor(total * 10) / 10
end

-- Сколько ещё влезет по весу. Для контейнера без лимита — бесконечность.
function C.Free(id)
    local cap = C.Capacity(id)
    if cap < 0 then return math.huge end
    return math.max(0, cap - C.Weight(id))
end

function C.IsEmpty(id)
    return #C.List(id) == 0
end

-- ================================================================
--  ИЗМЕНЕНИЕ
-- ================================================================
function C.Add(id, itemID, amount)
    local c = C.Get(id)
    if not c then return false, "container_missing" end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, "bad_amount" end

    local weight = I.WeightOf(itemID) * amount
    if C.Capacity(id) >= 0 and C.Weight(id) + weight > C.Capacity(id) then
        return false, "no_space"
    end
    return backend(c).add(c, itemID, amount)
end

function C.Take(id, itemID, amount)
    local c = C.Get(id)
    if not c then return false, "container_missing" end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, "bad_amount" end
    return backend(c).take(c, itemID, amount)
end

--[[ ПЕРЕНОС МЕЖДУ КОНТЕЙНЕРАМИ. Атомарный: сначала забираем, потом
     кладём; если положить не удалось — возвращаем источнику. Если и
     возврат не удался, предмет мог бы исчезнуть, поэтому такая
     ситуация не скрывается, а уходит в журнал. ]]
function C.Move(srcID, dstID, itemID, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, "bad_amount" end

    local src, dst = C.Get(srcID), C.Get(dstID)
    if not src then return false, "source_missing" end
    if not dst then return false, "target_missing" end
    if srcID == dstID then return true end

    local weight = I.WeightOf(itemID) * amount
    if C.Capacity(dstID) >= 0 and C.Weight(dstID) + weight > C.Capacity(dstID) then
        return false, "no_space"
    end

    local ok, reason = backend(src).take(src, itemID, amount)
    if not ok then return false, reason or "not_enough" end

    local putOk, putReason = backend(dst).add(dst, itemID, amount)
    if putOk then return true end

    -- Откат. Неудачный откат — потеря предмета, молчать о нём нельзя.
    local backOk = backend(src).add(src, itemID, amount)
    if not backOk and GRM.Audit and GRM.Audit.Write then
        GRM.Audit.Write("industry", "container_rollback_failed", nil, nil,
            { item = tostring(itemID), amount = amount, from = tostring(srcID), to = tostring(dstID) })
    end
    return false, putReason or "add_failed"
end

--[[ ПРИЁМ «СКОЛЬКО ВЛЕЗЕТ». Возвращает, сколько РЕАЛЬНО принято.

     Адаптеры обязаны уметь это честно. Инвентарь игрока ограничен
     СЛОТАМИ, а не весом, поэтому считать влезающее количество по
     килограммам здесь нельзя: получилось бы либо ноль при частичном
     влезании, либо потеря разницы. ]]
Backends.store.addUpTo = function(c, itemID, amount)
    local cap = tonumber(c.capacity) or -1
    local can = amount
    if cap >= 0 then
        local unit = I.WeightOf(itemID)
        if unit > 0 then can = math.min(can, math.floor(math.max(0, cap - C.Weight(c.id)) / unit)) end
    end
    can = math.max(0, math.floor(can))
    if can <= 0 then return 0 end
    Backends.store.add(c, itemID, can)
    return can
end

Backends.player.addUpTo = function(c, itemID, amount)
    if not (c.Player and IsValid(c.Player)) then return 0 end
    if not (GRM.Inventory and GRM.Inventory.AddItem) then return 0 end
    local left = tonumber(GRM.Inventory.AddItem(c.Player, itemID, amount)) or amount
    local put = math.max(0, amount - left)
    return put
end

function C.MoveUpTo(srcID, dstID, itemID, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return 0 end

    local src, dst = C.Get(srcID), C.Get(dstID)
    if not src or not dst then return 0 end

    local want = math.min(amount, C.Count(srcID, itemID))
    if want <= 0 then return 0 end

    local ok = backend(src).take(src, itemID, want)
    if not ok then return 0 end

    local putFn = backend(dst).addUpTo
    local put = putFn and putFn(dst, itemID, want) or 0

    -- Остаток возвращаем: предмет, которого нет ни там ни там, — потеря.
    if put < want then
        local back = backend(src).add(src, itemID, want - put)
        if not back and GRM.Audit and GRM.Audit.Write then
            GRM.Audit.Write("industry", "container_upto_rollback_failed", nil, nil,
                { item = tostring(itemID), amount = want - put, from = tostring(srcID), to = tostring(dstID) })
        end
    end
    return math.floor(put or 0)
end

function C.Clear(id)
    local c = C.Get(id)
    if not c then return false end
    return backend(c).clear(c)
end

-- ================================================================
--  СЕРИАЛИЗАЦИЯ (только контейнеры в реестре)
-- ================================================================
function C.Serialize()
    local out = {}
    for id, c in pairs(C.Registry) do
        if c.kind ~= "player" then
            out[id] = { id = id, kind = c.kind, owner = c.owner, capacity = c.capacity, items = c.items }
        end
    end
    return out
end

function C.Deserialize(data)
    if not istable(data) then return 0 end
    local n = 0
    for id, rec in pairs(data) do
        if istable(rec) then
            local c = C.Ensure(rec.id or id, rec.kind or "store", rec.owner or "", rec.capacity or -1)
            c.items = {}
            if istable(rec.items) then
                for itemID, count in pairs(rec.items) do
                    local n2 = math.floor(tonumber(count) or 0)
                    if n2 > 0 then c.items[tostring(itemID)] = n2 end
                end
            end
            n = n + 1
        end
    end
    return n
end

print("[GRM Container] v" .. C.Version .. " loaded")
