-- Passive server updates only; no packet requests or memory scans.
local M = {};
local function uint(data, offset, size)
    if type(data)~='string' or #data<offset+size then return nil end
    local value=0;
    for i=size-1,0,-1 do value=value*256+data:byte(offset+i+1) end
    return value;
end
function M.new()
    local self={};
    function self:reset() self.key=nil; self.player=nil; self.home=false; self.sizes=nil; self.secondary=nil; self.home_byte=nil; self.paid=nil end
    self:reset();
    function self:observe(id,data)
        if id==0x00B then self:reset(); return end
        if id==0x00A then
            self:reset();
            if type(data)~='string' or #data<0x94 then return end
            local player,zone=uint(data,4,4),uint(data,0x30,2);
            local name=data:sub(0x85,0x94):match('^([^%z]+)');
            if not name or player==0 then return end
            self.player=player; self.key=name..':'..player..':'..zone;
            self.home_byte=uint(data,0x80,1); self.home=self.home_byte==1;
        elseif id==0x01C and self.key then
            self.sizes=nil; self.secondary=nil;
            if type(data)~='string' or #data<0x48 then return end
            self.sizes={}; self.secondary={};
            for bag=0,16 do self.sizes[bag]=uint(data,4+bag,1) end
            -- The secondary capacity is zero for disabled Satchel/Locker.
            for _,bag in ipairs({4,5}) do
                self.secondary[bag]=uint(data,0x24+bag*2,2);
                if self.secondary[bag]==0 then self.sizes[bag]=0 end
            end
        elseif id==0x037 and self.key and uint(data,0x24,4)==self.player then
            self.paid=uint(data,0x5C,1);
        end
    end
    function self:allowed(key,satchel_capacity)
        local bags={[0]=true,[6]=true,[7]=true,[8]=true,[10]=true};
        -- Satchel is portable. The SDK already exposes its usable capacity on reload.
        bags[5]=type(satchel_capacity)=='number' and satchel_capacity>=1
            and satchel_capacity<=80 and satchel_capacity==math.floor(satchel_capacity);
        if key~=self.key then return bags end
        for _,bag in ipairs({1,2,4,5,9,11,12,13,14,15,16}) do
            local size=self.sizes and self.sizes[bag];
            -- Live 0x01C values reach 81 for an 80-slot bag. These are wire
            -- sizes, not the usable slot limit checked against the SDK at send time.
            local available=type(size)=='number' and size>0 and size<=81;
            if bag==1 or bag==2 or bag==4 or bag==9 then available=available and self.home end
            if bag>=11 then
                local shift=bag==11 and 0 or (bag==12 and 1 or bag-10);
                available=available and self.paid~=nil and math.floor(self.paid/2^shift)%2==1;
            end
            if bag~=5 or self.sizes then bags[bag]=available==true end
        end
        return bags;
    end
    function self:reason(key,bag)
        if self:allowed(key)[bag] then return nil end
        if bag==5 and (key~=self.key or not self.sizes) then
            return 'Satchel data is unavailable. Wait for inventory loading, then use Refresh.';
        end
        if not self.key then return 'No zone-entry update recorded. Leave and re-enter your Mog House.' end
        if key~=self.key then return 'Recorded zone/player differs from the current context. Run /im status.' end
        if (bag==1 or bag==2 or bag==4 or bag==9) and not self.home then
            return 'The recorded zone entry was not detected as a Mog House. Run /im status.';
        end
        if not self.sizes then return 'Waiting for a complete bag-capacity update. Run /im status.' end
        if not self.sizes[bag] or self.sizes[bag]<=0 then return 'The bag-capacity update reports this container disabled. Run /im status.' end
        if bag>=11 and bag<=16 then return 'Wardrobe unlock is not confirmed by the player update.' end
        return 'Container access is not confirmed. Run /im status.';
    end
    return self;
end
return M;
