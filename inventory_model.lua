-- Read-only inventory model. No game commands, packets, or item transfers.
local M = {};
local categories=require 'item_categories';
M.containers = {
    'Inventory', 'Safe', 'Storage', 'Temporary', 'Locker', 'Satchel', 'Sack',
    'Case', 'Wardrobe', 'Safe 2', 'Wardrobe 2', 'Wardrobe 3', 'Wardrobe 4',
    'Wardrobe 5', 'Wardrobe 6', 'Wardrobe 7', 'Wardrobe 8', 'Recycle',
};
local function integer(n, low, high)
    return type(n) == 'number' and n == n and n >= low and n <= high and n == math.floor(n);
end
local function normalize(text)
    return tostring(text or ''):lower():gsub("['%-%._]", ''):gsub('%s+', ' ');
end
function M.matches(item, query)
    local haystack = normalize(item.name .. ' ' .. item.full_name .. ' ' .. item.id);
    for word in normalize(query):gmatch('%S+') do
        if not haystack:find(word, 1, true) then return false end
    end
    return true;
end
function M.scan(inventory, resources)
    local snapshot = {};
    local before = inventory:GetContainerUpdateCounter();
    for id = 0, #M.containers - 1 do
        local bag = {id=id, name=M.containers[id+1], items={}, state='Unavailable'};
        snapshot[#snapshot+1] = bag;
        local ok = pcall(function()
            local capacity = inventory:GetContainerCountMax(id);
            if not integer(capacity, 1, 256) then return end
            local used = inventory:GetContainerCount(id);
            if not integer(used, 0, capacity) then bag.state='Updating'; return end
            local occupied = 0;
            for slot=1, capacity do
                local item = inventory:GetContainerItem(id, slot);
                if item and item.Id ~= 0 then
                    if not integer(item.Id, 1, 65535) or not integer(item.Count, 1, 4294967295) then
                        bag.state='Updating'; bag.items={}; return;
                    end
                    local resource = resources:GetItemById(item.Id);
                    local name = resource and resource.Name and resource.Name[1];
                    local full = resource and resource.LogNameSingular and resource.LogNameSingular[1];
                    if type(name) ~= 'string' or name == '' then name='Item #' .. item.Id end
                    if type(full) ~= 'string' then full=name end
                    bag.items[#bag.items+1] = {id=item.Id, slot=slot, count=item.Count, name=name, full_name=full,
                        flags=item.Flags, price=item.Price, extra=item.Extra,
                        stack_size=resource and resource.StackSize, item_type=resource and resource.Type,
                        equip_slots=resource and resource.Slots, resource_flags=resource and resource.Flags};
                    occupied=occupied+1;
                end
            end
            if occupied ~= used then bag.state='Updating'; bag.items={}; return end
            bag.used, bag.capacity, bag.free = used, capacity, capacity-used;
            bag.state='Client snapshot';
        end);
        if not ok then bag.state='Read error'; bag.items={}; bag.used=nil; bag.capacity=nil; bag.free=nil; end
    end
    if inventory:GetContainerUpdateCounter() ~= before then return nil, 'Inventory is updating; waiting for a stable read.' end
    return snapshot;
end
-- Column indices are logical IDs, independent of dragged display order.
function M.sort(rows, column, descending)
    local function value(row)
        if column == 1 then return row.bag.name:lower() end
        if column == 2 then return row.item.count end
        if column == 3 then return row.item.slot end
        return row.item.name:lower();
    end
    table.sort(rows, function(a,b)
        local av,bv=value(a),value(b);
        if av ~= bv then
            if descending then return av > bv end
            return av < bv;
        end
        local an,bn=a.item.name:lower(),b.item.name:lower();
        if an ~= bn then return an < bn end
        if a.bag.id ~= b.bag.id then return a.bag.id < b.bag.id end
        return a.item.slot < b.item.slot;
    end);
end
function M.search(snapshot, query, selected, enabled)
    local rows, quantity = {}, 0;
    for _, bag in ipairs(snapshot or {}) do
        if bag.state == 'Client snapshot' and (selected == nil or selected == bag.id) then
            for _, item in ipairs(bag.items) do
                if M.matches(item, query) and categories.matches(item,enabled) then
                    rows[#rows+1]={item=item, bag=bag}; quantity=quantity+item.count;
                end
            end
        end
    end
    M.sort(rows, 0, false);
    return rows, quantity;
end
-- Group by resource ID, never display name. Keep each slot and its extra data.
function M.ownership(snapshot,query,filter,enabled)
    local indexed,groups={},{};
    for _,bag in ipairs(snapshot or {}) do
        if bag.state=='Client snapshot' then
            for _,item in ipairs(bag.items) do
                local g=indexed[item.id];
                if not g then
                    g={id=item.id,name=item.name,total=0,rows={},locations={},by_bag={},variants={},variant_count=0,matched=false,equipment=false,stackable=false};
                    indexed[item.id]=g; groups[#groups+1]=g;
                end
                g.matched=g.matched or (M.matches(item,query) and categories.matches(item,enabled));
                g.total=g.total+item.count;
                local flags=item.resource_flags;
                g.equipment=g.equipment or (integer(flags,0,4294967295) and math.floor(flags/0x800)%2==1);
                g.stackable=g.stackable or (type(item.stack_size)=='number' and item.stack_size>1);
                local location=g.by_bag[bag.id];
                if not location then location={id=bag.id,name=bag.name,count=0}; g.by_bag[bag.id]=location; g.locations[#g.locations+1]=location end
                location.count=location.count+item.count;
                local variant;
                if type(item.extra)=='string' and #item.extra==28 then
                    variant=g.variants[item.extra];
                    if not variant then g.variant_count=g.variant_count+1; variant=g.variant_count; g.variants[item.extra]=variant end
                end
                g.rows[#g.rows+1]={bag=bag,item=item,variant=variant};
            end
        end
    end
    local result={};
    for _,g in ipairs(groups) do
        local include=filter==nil or filter==0
            or (filter==1 and #g.locations>1)
            or (filter==2 and g.stackable and #g.rows>1)
            or (filter==3 and g.equipment and #g.rows>1);
        if g.matched and include then
            table.sort(g.locations,function(a,b) return a.id<b.id end);
            table.sort(g.rows,function(a,b) if a.bag.id~=b.bag.id then return a.bag.id<b.bag.id end; return a.item.slot<b.item.slot end);
            result[#result+1]=g;
        end
    end
    M.sort_ownership(result,0,false);
    return result;
end
function M.sort_ownership(groups,column,descending)
    local function value(g)
        if column==1 then return g.total end
        if column==2 then return #g.locations end
        if column==3 then
            local names={}; for _,location in ipairs(g.locations) do names[#names+1]=location.name:lower() end
            return table.concat(names,' | ');
        end
        return g.name:lower();
    end
    table.sort(groups,function(a,b)
        local av,bv=value(a),value(b);
        if av~=bv then if descending then return av>bv end; return av<bv end
        if a.name:lower()~=b.name:lower() then return a.name:lower()<b.name:lower() end
        return a.id<b.id;
    end);
end
return M;
