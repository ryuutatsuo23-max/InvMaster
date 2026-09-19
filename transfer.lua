-- One explicit transfer at a time. No automatic retry and no batch queue.
local M = {};
M.bags = {[0]='Inventory',[1]='Safe',[2]='Storage',[4]='Locker',[5]='Satchel',
    [6]='Sack',[7]='Case',[8]='Wardrobe',[9]='Safe 2',[10]='Wardrobe 2',
    [11]='Wardrobe 3',[12]='Wardrobe 4',[13]='Wardrobe 5',[14]='Wardrobe 6',
    [15]='Wardrobe 7',[16]='Wardrobe 8'};
local portable = {[0]=true,[6]=true,[7]=true};
function M.route(data,choice,destination,access)
    access=access or portable;
    if not choice or not M.bags[choice.bag] or not M.bags[destination]
        or choice.bag==destination or (choice.bag~=0 and destination~=0) then
        return false, 'Move between Inventory and one storage container.';
    end
    if access[choice.bag]~=true or access[destination]~=true then
        return false, 'Container access is unavailable. Enter your Mog House again to update access.';
    end
    local source,target=data and data[choice.bag+1],data and data[destination+1];
    if not source or not target or source.state~='Client snapshot' or target.state~='Client snapshot' then
        return false, 'Wait for consistent container data.';
    end
    if not target.free or target.free<1 then return false, 'Destination needs at least one free slot.' end
    if destination==8 or destination>=10 then
        local flags=choice.resource_flags;
        if type(flags)~='number' or flags~=flags or flags<0 or flags~=math.floor(flags)
            or math.floor(flags/0x800)%2~=1 then
            return false, 'Wardrobes accept equipment only.';
        end
    end
    return true;
end
-- UI route preview; individual packet validation remains single-leg only.
function M.plan_route(data,choice,destination,access)
    if not choice or choice.bag==0 or destination==0 or choice.bag==destination then
        return M.route(data,choice,destination,access);
    end
    local ok,reason=M.route(data,choice,0,access);
    if not ok then return false,'Via Inventory: '..reason end
    local intermediate={bag=0,resource_flags=choice.resource_flags};
    return M.route(data,intermediate,destination,access);
end
local function valid_number(n, lo, hi)
    return type(n)=='number' and n==n and n==math.floor(n) and n>=lo and n<=hi;
end
local function same(a,b)
    return a and b and a.id==b.id and a.extra==b.extra;
end
local function total(bag,item)
    local n=0;
    for _, other in ipairs(bag.items) do
        if other.id==item.id and (item.stack_size>1 or other.extra==item.extra) then n=n+other.count end
    end
    return n;
end
local function at(bag,slot)
    for _, item in ipairs(bag.items) do if item.slot==slot then return item end end
end
function M.prepare(data, choice, destination, quantity, equipped, access)
    local allowed,reason=M.route(data,choice,destination,access);
    if not allowed then return nil,reason end
    local source, target=data and data[choice.bag+1], data and data[destination+1];
    if not source or not target or source.state~='Client snapshot' or target.state~='Client snapshot'
        or not valid_number(source.capacity,1,80) or not valid_number(target.capacity,1,80) then
        return nil, 'Both containers must have consistent, available data.';
    end
    if not valid_number(choice.slot,1,source.capacity) then return nil, 'Invalid source slot.' end
    local item=at(source, choice.slot);
    if not same(item,choice) or item.count~=choice.count or item.flags~=choice.flags then
        return nil, 'Selected slot changed. Select the item again.';
    end
    local fresh={bag=choice.bag,resource_flags=item.resource_flags};
    allowed,reason=M.route(data,fresh,destination,access);
    if not allowed then return nil,reason end
    if type(item.extra)~='string' or #item.extra~=28 or item.flags~=0 or item.price~=0 or item.id==65535 then
        return nil, 'Item is locked, in use, or its identity data is unavailable.';
    end
    if not valid_number(item.stack_size,1,99) or not valid_number(item.item_type,0,65535) then
        return nil, 'Item resource data is unavailable.';
    end
    if item.item_type==10 or item.item_type==11 or item.item_type==12 or item.item_type==14 then
        return nil, 'Furniture transfers are not supported in this version.';
    end
    if equipped(choice.bag,choice.slot) then return nil, 'Unequip this item before moving it.' end
    if not valid_number(quantity,1,item.count) or quantity>item.stack_size then return nil, 'Choose a valid quantity from this slot.' end
    -- Require a spare slot even if merging might work, until stack handling is live-tested.
    if not target.free or target.free<1 then return nil, 'Destination needs at least one free slot.' end
    return {source=choice.bag,destination=destination,slot=choice.slot,item=item,quantity=quantity,
        before_source=total(source,item),before_target=total(target,item),
        before_inventory=destination==0 and target.items or nil};
end
function M.packet(move)
    local n=move.quantity;
    return {0,0,0,0,n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256,
        move.source,move.destination,move.slot,82};
end
function M.new(env)
    local self={pending=nil,message=nil};
    function self:reset()
        self.pending=nil; self.message=nil;
    end
    function self:start(choice,destination,quantity)
        if self.pending then return false end
        local ok, err=pcall(function()
            local key,reason=env.context();
            if not key then self.message=reason; return end
            local data,read_error=env.scan();
            local move,problem=M.prepare(data,choice,destination,quantity,env.equipped,env.access and env.access());
            if not move then self.message=read_error or problem; return end
            -- A second context check immediately before sending prevents stale-character work.
            if env.context()~=key then self.message='Player context changed; nothing sent.'; return end
            local allowed,reason=M.route(data,choice,destination,env.access and env.access());
            if not allowed then self.message=reason; return end
            move.key=key; move.sent=env.now(); move.next_check=move.sent; move.deadline=move.sent+8;
            self.pending=move;
            self.message='Move requested; waiting for inventory confirmation.';
            -- Pending is set before the call: an uncertain API outcome must never cause a retry.
            if env.send(M.packet(move))==false then self.message='Request outcome unknown; checking inventory. No retry will be sent.' end
        end);
        if not ok then
            self.message=self.pending and 'Request outcome unknown; checking inventory. No retry will be sent.' or 'Could not validate transfer; nothing sent.';
        end
        return self.pending~=nil;
    end
    function self:tick()
        local p=self.pending;
        if not p then return end
        local ok=pcall(function()
            local key=env.context();
            if key~=p.key then
                self.message='Player context unavailable or changed. Move outcome unknown; check your bags.'; return;
            end
            local now=env.now();
            if now<p.next_check then return end
            p.next_check=now+0.25;
            local data=env.scan();
            local source,target=data and data[p.source+1],data and data[p.destination+1];
            local confirmed=source and target and source.state=='Client snapshot' and target.state=='Client snapshot'
                and total(source,p.item)==p.before_source-p.quantity and total(target,p.item)==p.before_target+p.quantity;
            if confirmed then
                if p.confirmed_at and now-p.confirmed_at>=0.25 then
                    self.message=('Moved %d x %s: %s to %s.'):format(p.quantity,p.item.name,M.bags[p.source],M.bags[p.destination]);
                    self.pending=nil; env.changed(); return;
                end
                p.confirmed_at=now;
            else p.confirmed_at=nil end
            if now>=p.deadline then
                self.message='Move not confirmed. Check your bags; further moves are locked until confirmed or the addon is reloaded. No retry sent.';
            end
        end);
        if not ok then self.message='Inventory confirmation unavailable; move remains locked. No retry sent.' end
    end
    return self;
end
return M;
