-- Coordinates at most two confirmed moves. Never retries a sent request.
local transfer=require 'transfer';
local M={};
local function matches(a,b) return a and b and a.id==b.id and a.extra==b.extra end
function M.received(before,bag,item,quantity)
    if not bag or bag.state~='Client snapshot' then return nil end
    local old,now={},{};
    for _,v in ipairs(before or {}) do old[v.slot]=v end
    for _,v in ipairs(bag.items) do now[v.slot]=v end
    local candidate;
    for slot,v in pairs(old) do
        if matches(v,item) and (not matches(now[slot],item) or now[slot].count<v.count) then return nil end
    end
    for _,v in ipairs(bag.items) do
        if matches(v,item) then
            local previous=old[v.slot];
            if previous and not matches(previous,item) then return nil end
            local delta=v.count-(previous and previous.count or 0);
            if delta>0 then
                if candidate or delta~=quantity then return nil end
                candidate={bag=0}; for k,value in pairs(v) do candidate[k]=value end
            end
        end
    end
    return candidate;
end
function M.new(env)
    local self={pending=nil,message=nil,plan=nil};
    local completed=false;
    local leg_env={}; for k,v in pairs(env) do leg_env[k]=v end
    leg_env.changed=function() completed=true end;
    local leg=transfer.new(leg_env);
    local function sync()
        self.pending=leg.pending;
        self.message=leg.message;
        if self.plan and self.message then
            self.message=('Step %d/2: '):format(self.plan.step)..self.message;
        end
    end
    local function stop(reason)
        local plan=self.plan;
        leg:reset(); self.plan=nil; self.pending=nil;
        self.message=('Stopped after step 1: %d x %s reached Inventory. %s'):format(plan.quantity,plan.item.name,reason);
        env.changed();
    end
    function self:reset() leg:reset(); self.plan=nil; self.pending=nil; self.message=nil; completed=false end
    function self:start(choice,destination,quantity)
        if self.pending then return false end
        local two=choice and choice.bag~=0 and destination~=nil and destination~=0 and choice.bag~=destination;
        if not two then
            local result=leg:start(choice,destination,quantity); sync(); return result;
        end
        local ok,err=pcall(function()
            local data,reason=env.scan();
            local allowed,problem=transfer.plan_route(data,choice,destination,env.access and env.access());
            if not allowed then self.message=reason or problem; return end
            if leg:start(choice,0,quantity) then
                local p=leg.pending;
                self.plan={step=1,source=choice.bag,destination=destination,quantity=quantity,
                    item=p.item,before=p.before_inventory,key=p.key};
            end
            sync();
        end);
        if not ok then
            sync(); self.message=self.pending and 'Request outcome unknown; check your bags. No retry sent.' or 'Could not validate route; nothing sent.';
        end
        return self.pending~=nil;
    end
    function self:tick()
        if not self.pending then return end
        local ok=pcall(function()
            local plan=self.plan;
            if plan and plan.step==1 and (env.context()~=plan.key or env.now()>=leg.pending.deadline) then
                plan.cancelled=true;
            end
            local current=leg.pending;
            completed=false; leg:tick(); sync();
            if not completed then return end
            if not plan then env.changed(); if env.completed then env.completed(current.destination) end; return end
            if plan.step==2 then
                self.message=('Moved %d x %s: %s to %s via Inventory.'):format(plan.quantity,plan.item.name,transfer.bags[plan.source],transfer.bags[plan.destination]);
                self.plan=nil; env.changed(); if env.completed then env.completed(plan.destination) end; return;
            end
            if plan.cancelled then stop('Automatic continuation was cancelled after a delay or context change.'); return end
            local data=env.scan();
            local choice=M.received(plan.before,data and data[1],plan.item,plan.quantity);
            if not choice then stop('Could not identify one received stack safely; no second move sent.'); return end
            if env.context()~=plan.key then stop('Player context changed; no second move sent.'); return end
            -- Advance before sending: uncertain API outcomes must not repeat this step.
            plan.step=2;
            if not leg:start(choice,plan.destination,plan.quantity) then
                stop(leg.message or 'The destination is unavailable; no second move sent.'); return;
            end
            sync();
        end);
        if not ok then
            if self.plan and not leg.pending then
                stop('Could not validate the next step; no second move sent.');
            else sync(); self.message='Move outcome unknown; check your bags. No retry sent.' end
        end
    end
    return self;
end
return M;
