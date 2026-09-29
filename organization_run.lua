-- Execute only reviewed moves, using the existing confirmed route engine.
local planner=require 'organization';
local routes=require 'route_transfer';
local stacking=require 'stack_sort';
local M={};
local function access_signature(access)
    local parts={}; for id=0,16 do parts[#parts+1]=tostring(access[id]==true) end
    return table.concat(parts,':');
end
function M.new(env)
    local self={}; local completed=false;
    local function valid(p)
        return p and not p.cancelled and env.context()==p.key and not env.busy()
            and planner.rules_signature(env.rules())==p.rules_signature
            and access_signature(env.access())==p.access;
    end
    local route_env={}; for k,v in pairs(env) do route_env[k]=v end
    route_env.completed=function() completed=true end;
    route_env.continue_route=function() return valid(self.active) end;
    local route=routes.new(route_env);
    local function protected_bag(bag)
        local rules=planner.normalize(env.rules());
        for _,item in ipairs(bag.items) do
            local rule=rules.items[tostring(item.id)];
            if rule and rule.protected then return true end
        end
        return false;
    end
    local stack_completed=false;
    local stack_env={}; for k,v in pairs(env) do stack_env[k]=v end
    stack_env.send=env.send_stack;
    stack_env.validate=function(bag)
        return valid(self.active) and not protected_bag(bag),'Stacking conditions changed; nothing sent.';
    end;
    stack_env.changed=function() stack_completed=true; env.changed() end;
    local stacker=stacking.new(stack_env);
    function self:busy() return self.active~=nil or route.pending~=nil or stacker.pending~=nil end
    function self:cancel(reason)
        reason=reason or 'Stopped. No further moves sent.';
        if self.active then
            self.active.cancelled=true;
            self.active.cancel_reason=self.active.cancel_reason or reason;
            reason=self.active.cancel_reason;
        end
        route:cancel(reason);
    end
    local function finish(reason)
        local p=self.active;
        if p and p.stack_bags then
            reason=reason..(' Stacking: %d bag%s confirmed; %d bag%s skipped to protect untouched items.'):format(p.stacked,p.stacked==1 and '' or 's',p.protected_skips,p.protected_skips==1 and '' or 's');
        end
        self.message=('%d/%d move%s confirmed. %s'):format(p and p.done or 0,p and #p.moves or 0,p and #p.moves==1 and '' or 's',reason);
        self.active=nil;
    end
    function self:start(plan,stack_after)
        if self:busy() or env.busy() then return false end
        local ok,reason=pcall(function()
            local key=env.context(); local data=env.scan();
            if not key or key~=plan.key or planner.signature(data)~=plan.snapshot_signature
                or planner.rules_signature(env.rules())~=plan.rules_signature then
                self.message='Plan changed. View a fresh organization plan.'; return;
            end
            local fresh=planner.plan(data,env.rules(),{ready=true,key=key,access=env.access(),equipped=env.equipped});
            if #fresh.moves~=#plan.moves or #plan.moves==0 then self.message='Plan changed or empty. View a fresh plan.'; return end
            local moves={}; local summary=planner.run_summary(fresh);
            for i,m in ipairs(fresh.moves) do
                local reviewed=plan.moves[i];
                for _,field in ipairs({'id','source','destination','slot','count'}) do
                    if m[field]~=reviewed[field] then self.message='Plan changed. View a fresh plan.'; return end
                end
                if i<=summary.count then moves[i]=m end
            end
            if stack_after and type(env.send_stack)~='function' then self.message='Stacking unavailable; nothing sent.'; return end
            self.active={key=key,rules_signature=plan.rules_signature,access=access_signature(env.access()),moves=moves,index=1,done=0,deferred=summary.deferred};
            if stack_after then
                local p=self.active; p.stack_bags={}; p.stack_index=1; p.stacked=0; p.protected_skips=0;
                local seen={};
                for _,m in ipairs(moves) do
                    if not seen[m.destination] then seen[m.destination]=true; p.stack_bags[#p.stack_bags+1]=m.destination end
                end
            end
            self.message=('Queued: %d move%s.'):format(#moves,#moves==1 and '' or 's');
        end);
        if not ok then self.message='Cannot validate organization plan; nothing sent.' end
        return self.active~=nil;
    end
    local function tick()
        local p=self.active; if not p and not route.pending and not stacker.pending then return end
        if p and not valid(p) then
            self:cancel(env.context()~=p.key
                and 'Stopped: player context changed or is unavailable. No further moves sent.'
                or 'Stopped: rules, access or action availability changed. No further moves sent.');
        end
        if route.pending then
            -- Cancel before checking confirmation: a late success must not launch the next move.
            if env.now()>=route.pending.deadline then self:cancel('Stopped: confirmation timed out. No further moves sent.') end
            completed=false; route:tick(); self.pending=route.pending;
            if route.pending then
                self.message=(p and p.cancelled and 'Stopping: ' or '')..(route.message or 'Awaiting confirmation.');
                return;
            end
            if completed then p.done=p.done+1; p.index=p.index+1
            else finish(route.message or 'Move stopped. Review bags before continuing.'); return end
        end
        if stacker.pending then
            if env.now()>=stacker.pending.deadline then self:cancel('Stopped: stacking confirmation timed out. No further moves sent.') end
            stack_completed=false; stacker:tick(); self.pending=stacker.pending;
            if stacker.pending then
                self.message=(p.cancelled and 'Organization stopping: ' or 'Stacking: ')..(stacker.message or 'Awaiting confirmation.');
                return;
            end
            if stack_completed then p.stacked=p.stacked+1; p.stack_index=p.stack_index+1
            else finish('Stacking stopped. Check bags before continuing.'); return end
        end
        if not p then return end
        if p.cancelled then finish(p.cancel_reason); return end
        if p.index>#p.moves then
            local bag_id=p.stack_bags and p.stack_bags[p.stack_index];
            if bag_id~=nil then
                local data=env.scan(); local bag=data and data[bag_id+1];
                local saving=stacking.savings(bag);
                if not saving then finish('Cannot validate destination bag for stacking. No stacking request sent.'); return end
                if protected_bag(bag) then p.protected_skips=p.protected_skips+1; p.stack_index=p.stack_index+1; return end
                if saving==0 then p.stack_index=p.stack_index+1; return end
                if not stacker:start(bag_id) then finish(stacker.message or 'Stacking unavailable.'); return end
                self.pending=stacker.pending; self.message='Stacking: '..(stacker.message or 'Awaiting confirmation.'); return;
            end
            finish(p.deferred>0
                and ('Run finished. Deferred moves: %d. View a fresh plan and confirm the next run.'):format(p.deferred)
                or 'Finished. Review a new plan for any remaining work.'); return;
        end
        local wanted=p.moves[p.index];
        local data=env.scan();
        local fresh=planner.plan(data,env.rules(),{ready=true,access=env.access(),equipped=env.equipped});
        local found=false;
        for _,m in ipairs(fresh.moves) do
            if m.id==wanted.id and m.source==wanted.source and m.slot==wanted.slot and m.destination==wanted.destination
                and m.count==wanted.count and m.choice.extra==wanted.choice.extra and m.choice.count==wanted.choice.count
                and m.choice.flags==wanted.choice.flags then found=true; break end
        end
        if not found or not valid(p) then finish('Next reviewed move changed or is blocked. View a fresh plan.'); return end
        if not route:start(wanted.choice,wanted.destination,wanted.count) then finish(route.message or 'Move validation failed.'); return end
        self.pending=route.pending; self.message=('Move %d/%d: '):format(p.index,#p.moves)..(route.message or 'Waiting.');
    end
    function self:tick()
        local ok=pcall(tick);
        if not ok then
            self:cancel('Stopped: validation unavailable. No further moves sent.'); self.pending=route.pending or stacker.pending;
            self.message='Organization validation unavailable. Stopped; any pending move stays locked. No retry.';
            if not self.pending then self.active=nil end
        end
    end
    return self;
end
return M;
