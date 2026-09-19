-- Sequential, confirmed withdrawals; no retries or automatic source substitution.
local transfer=require 'transfer';
local M={};
function M.sources(data,id,env)
    local rows,total={},0;
    for _,bag in ipairs(data or {}) do
        if bag.id~=0 and bag.state=='Client snapshot' then
            for _,item in ipairs(bag.items) do
                if item.id==id then
                    local choice={bag=bag.id}; for k,v in pairs(item) do choice[k]=v end
                    local ok,move=pcall(function() return transfer.prepare(data,choice,0,1,env.equipped,env.access()) end);
                    if ok and move then
                        rows[#rows+1]=choice; total=total+item.count;
                    end
                end
            end
        end
    end
    return rows,total;
end
function M.new(env)
    local self={}; local confirmed=false;
    local leg_env={}; for k,v in pairs(env) do leg_env[k]=v end
    leg_env.changed=function() confirmed=true; env.changed() end;
    local leg=transfer.new(leg_env);
    function self:reset() leg:reset(); self.active=nil; self.pending=nil; self.message=nil end
    function self:cancel() self.active=nil; self.message='Withdrawal stopped. Any sent move will still be checked.' end
    function self:start(id,quantity)
        if self.active or self.pending then return false end
        local key=env.context(); if not key then return false end
        local ok,data=pcall(env.scan);
        if not ok or not data then self.message='Wait for a stable inventory read.'; return false end
        local rows,total=M.sources(data,id,env);
        if type(quantity)~='number' or quantity~=math.floor(quantity) or quantity<1 or quantity>total then self.message='Choose a quantity within the available total.'; return false end
        self.active={rows=rows,index=1,left=quantity,done=0,key=key}; self.message='Withdrawal queued.';
        self:tick(); return self.pending~=nil;
    end
    local function tick()
        local p=self.active;
        if self.pending then
            if p and (env.context()~=p.key or env.now()>=self.pending.deadline) then self:cancel(); p=nil end
            confirmed=false; leg:tick(); self.pending=leg.pending;
            if self.pending then self.message=leg.message; return end
            if not confirmed or not p then return end
            p.left=p.left-p.sent; p.done=p.done+p.sent; p.index=p.index+1;
        end
        if not p then return end
        if p.left==0 then self.message=('Withdrew %d items to Inventory.'):format(p.done); self.active=nil; return end
        if env.context()~=p.key then self:cancel(); return end
        local choice=p.rows[p.index];
        if not choice then self:cancel(); return end
        p.sent=math.min(choice.count,p.left);
        if not leg:start(choice,0,p.sent) then
            self.message=('Stopped after %d items: '):format(p.done)..(leg.message or 'Source changed.'); self.active=nil; return;
        end
        self.pending=leg.pending; self.message=('Withdrawing: %d confirmed. '):format(p.done)..leg.message;
    end
    function self:tick()
        local ok=pcall(tick);
        if not ok then
            self.active=nil; self.pending=leg.pending;
            self.message='Withdrawal stopped: validation unavailable. Any sent move remains locked until confirmed.';
        end
    end
    return self;
end
return M;
