-- Independent, read-only organization rules and planner. No sender or game actions.
local transfer=require 'transfer';
local categories=require 'item_categories';
local M={};
-- Preserve plan order and keep both legs of a routed move in the same run.
function M.run_summary(plan)
    local summary={count=0,steps=0,total_steps=0,runs=0};
    local current=0;
    for _,move in ipairs(plan.moves) do
        local cost=move.via_inventory and 2 or 1;
        if summary.runs==0 or current+cost>50 then summary.runs=summary.runs+1; current=0 end
        current=current+cost; summary.total_steps=summary.total_steps+cost;
        if summary.runs==1 then summary.count=summary.count+1; summary.steps=current end
    end
    summary.deferred=#plan.moves-summary.count;
    return summary;
end
function M.signature(snapshot)
    local parts={};
    for _,bag in ipairs(snapshot or {}) do
        parts[#parts+1]=table.concat({bag.id,bag.state,tostring(bag.free),tostring(bag.capacity)},':');
        for _,item in ipairs(bag.items or {}) do
            for _,key in ipairs({'slot','id','count','flags','price','extra','stack_size','item_type','resource_flags'}) do
                local value=tostring(item[key]); parts[#parts+1]=#value..':'..value;
            end
        end
    end
    return table.concat(parts,'|');
end
local function integer(n,low,high)
    return type(n)=='number' and n==n and n==math.floor(n) and n>=low and n<=high;
end
local function destination(n)
    return n==-1 or (integer(n,0,16) and transfer.bags[n]~=nil);
end
function M.normalize(value)
    value=type(value)=='table' and value or {};
    local result={items={},categories={}};
    for _,option in ipairs(categories.options) do
        local v=type(value.categories)=='table' and value.categories[option[1]];
        if destination(v) then result.categories[option[1]]=v end
    end
    for id,rule in pairs(type(value.items)=='table' and value.items or {}) do
        local n=tonumber(id);
        if integer(n,1,65534) and type(rule)=='table' then
            result.items[tostring(n)]={name=type(rule.name)=='string' and rule.name or tostring(n),
                keep=integer(rule.keep,0,7992) and rule.keep or nil,
                destination=destination(rule.destination) and rule.destination or nil,
                protected=rule.protected==true,sell=rule.sell==true};
        end
    end
    return result;
end
function M.rules_signature(value)
    local normalized=M.normalize(value); local parts={};
    for _,option in ipairs(categories.options) do parts[#parts+1]=option[1]..':'..tostring(normalized.categories[option[1]]) end
    local ids={}; for id in pairs(normalized.items) do ids[#ids+1]=id end; table.sort(ids);
    for _,id in ipairs(ids) do
        local r=normalized.items[id]; parts[#parts+1]=id..':'..tostring(r.keep)..':'..tostring(r.destination)..':'..tostring(r.protected)..':'..tostring(r.sell);
    end
    return table.concat(parts,'|');
end
function M.plan(snapshot,rules,env)
    rules=M.normalize(rules);
    local result={moves={},blocked={},protected=0,snapshot_signature=M.signature(snapshot),rules_signature=M.rules_signature(rules),key=env.key};
    local function block(name,reason) result.blocked[#result.blocked+1]=name..': '..reason end
    if not snapshot or not snapshot[1] or snapshot[1].state~='Client snapshot' then
        block('Inventory','Wait for a readable snapshot.'); return result;
    end
    if not env.ready then block('Character',env.reason or 'Wait until idle and ready.'); return result end
    local access=env.access or {};
    local groups,ids,free={},{},{};
    local view={};
    for i,bag in ipairs(snapshot) do
        view[i]={}; for k,v in pairs(bag) do view[i][k]=v end
        free[bag.id]=bag.free or 0;
        if bag.state=='Client snapshot' and transfer.bags[bag.id] then
            for _,item in ipairs(bag.items) do
                if not groups[item.id] then groups[item.id]={}; ids[#ids+1]=item.id end
                groups[item.id][#groups[item.id]+1]={bag=bag.id,item=item};
            end
        end
    end
    for id,rule in pairs(rules.items) do
        local n=tonumber(id);
        if not groups[n] and rule.keep and rule.keep>0 and not rule.protected and rule.destination~=0 and not rule.sell then
            block(rule.name,'Keep target cannot be met: item not found in readable bags.');
        end
    end
    table.sort(ids);
    local function propose(row,target,count)
        local item=row.item;
        local choice={bag=row.bag}; for k,v in pairs(item) do choice[k]=v end
        for _,bag in ipairs(view) do bag.free=free[bag.id] end
        local ok,move,reason=pcall(function()
            local allowed,problem=transfer.plan_route(view,choice,target,access);
            if not allowed then return nil,problem end
            return transfer.prepare(view,choice,row.bag~=0 and target~=0 and 0 or target,count,env.equipped,access);
        end);
        if not ok then reason='Item validation unavailable.'; move=nil end
        if not move then block(item.name,reason or 'Cannot validate move.'); return false end
        result.moves[#result.moves+1]={id=item.id,name=item.name,source=row.bag,destination=target,
            slot=item.slot,count=count,via_inventory=row.bag~=0 and target~=0,choice=choice};
        free[target]=free[target]-1; -- Conservative: reserve a new slot, never assume merging.
        return true;
    end
    for _,id in ipairs(ids) do
        local rows=groups[id]; local rule=rules.items[tostring(id)] or {};
        if rule.protected then result.protected=result.protected+1
        else
            local target=rule.sell and 0 or rule.destination;
            if target==nil then target=rules.categories[categories.classify(rows[1].item)] end
            if target==0 then
                -- Inventory destination means gather every available copy, not a refill quota.
                for _,row in ipairs(rows) do
                    if row.bag~=0 then propose(row,0,row.item.count) end
                end
            else
            local carried=0;
            for _,row in ipairs(rows) do if row.bag==0 then carried=carried+row.item.count end end
            local needed=math.max(0,(rule.keep or 0)-carried);
            local used={};
            for _,row in ipairs(rows) do
                if row.bag~=0 and needed>0 then
                    local n=math.min(needed,row.item.count);
                    if propose(row,0,n) then used[row]=n; needed=needed-n end
                end
            end
            if needed>0 then block(rows[1].item.name,('Keep target short by %d in this plan.'):format(needed)) end
            if target and target~=-1 then
                local retained=rule.keep or 0;
                for _,row in ipairs(rows) do
                    local count=row.item.count;
                    if row.bag==0 then
                        local keep=math.min(retained,count); retained=retained-keep; count=count-keep;
                    end
                    -- Do not propose a second action on a stack already used for refilling.
                    if used[row] then
                        if used[row]<count and row.bag~=target then block(row.item.name,'Remaining source stack deferred until refill is confirmed.') end
                    elseif count>0 and row.bag~=target then propose(row,target,count) end
                end
            end
            end
        end
    end
    return result;
end
return M;
