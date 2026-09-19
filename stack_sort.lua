-- Native stack combining, serialized with transfers by the caller.
local M={};
local function contents(bag)
    if not bag or bag.state~='Client snapshot' then return nil end
    local totals,groups={},{};
    for _,v in ipairs(bag.items) do
        if type(v.extra)~='string' or #v.extra~=28 then return nil end
        local key=v.id..':'..v.extra;
        totals[key]=(totals[key] or 0)+v.count;
        if v.flags==0 and v.price==0 and type(v.stack_size)=='number' and v.stack_size>1 and v.stack_size<=99 then
            local g=groups[key] or {count=0,slots=0,size=v.stack_size}; groups[key]=g;
            g.count=g.count+v.count; g.slots=g.slots+1;
        end
    end
    local saving=0;
    for _,g in pairs(groups) do saving=saving+math.max(0,g.slots-math.ceil(g.count/g.size)) end
    return totals,bag.used-saving,saving;
end
local function equal(a,b)
    if not a or not b then return false end
    for k,v in pairs(a) do if b[k]~=v then return false end end
    for k,v in pairs(b) do if a[k]~=v then return false end end
    return true;
end
function M.new(env)
    local self={pending=nil,message=nil};
    function self:reset() self.pending=nil; self.message=nil end
    function self:start(bag)
        if self.pending then return false end
        local ok=pcall(function()
            local key,reason=env.context();
            if not key then self.message=reason; return end
            if not env.access()[bag] then self.message='Stacking requires access to this bag.'; return end
            local data=env.scan(); local snapshot=data and data[bag+1];
            local totals,expected,saving=contents(snapshot);
            if not totals then self.message='Cannot validate bag contents for stacking.'; return end
            if saving==0 then self.message='No combinable partial stacks in this bag.'; return end
            if env.context()~=key or not env.access()[bag] then self.message='Access changed; no sort sent.'; return end
            self.pending={bag=bag,key=key,totals=totals,expected=expected,deadline=env.now()+8,next_check=0};
            self.message='Stacking requested; waiting for bag confirmation.';
            env.send({0,0,0,0,bag,0,0,0});
        end);
        if not ok then self.message=self.pending and 'Stacking outcome unknown; check the bag. No retry sent.' or 'Could not validate stacking; nothing sent.' end
        return self.pending~=nil;
    end
    function self:tick()
        local p=self.pending; if not p then return end
        local ok=pcall(function()
            if env.context()~=p.key then self.message='Stacking context changed; check the bag. No retry sent.'; return end
            local now=env.now(); if now<p.next_check then return end; p.next_check=now+0.25;
            local data=env.scan(); local bag=data and data[p.bag+1];
            local totals=contents(bag);
            if equal(totals,p.totals) and bag.used<=p.expected then
                if p.confirmed_at and now-p.confirmed_at>=0.25 then
                    self.pending=nil; self.message='Stacks combined; bag contents confirmed.'; env.changed(); return;
                end
                p.confirmed_at=now;
            else p.confirmed_at=nil end
            if now>=p.deadline then self.message='Stacking not confirmed; further moves remain locked. Check the bag before reloading. No retry sent.' end
        end);
        if not ok then self.message='Stacking confirmation unavailable; further moves remain locked. No retry sent.' end
    end
    return self;
end
return M;
