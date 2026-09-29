-- Read-only deposit planning. No sender, event response or trade execution.
local M={};
local function integer(n,low,high)
    return type(n)=='number' and n==n and n==math.floor(n) and n>=low and n<=high;
end
function M.plan(bag,element,loose,clusters,stored,npc,reason,busy)
    local p={rows={},notices={},loose=0,clusters=0};
    local function notice(s) p.notices[#p.notices+1]=s end
    if not integer(element,1,8) or not integer(loose,0,5000) or not integer(clusters,0,416) then
        notice('Choose valid whole quantities.'); return p;
    end
    p.units=loose+clusters*12;
    if p.units==0 then notice('Choose at least one crystal or cluster.') end
    if busy then notice('Wait for the current action to finish.') end
    if not npc then notice(reason or 'No verified Ephemeral Moogle within 6 yalms.') end
    if integer(stored,0,5000) then
        p.projected=stored+p.units;
        if p.projected>5000 then notice('Requested units exceed the 5000 limit using the last known balance.') end
    else notice('Stored balance is unknown or invalid. Refresh balances before trading.') end
    if not bag or bag.id~=0 or bag.state~='Client snapshot' then notice('Wait for readable Inventory contents.'); return p end
    p.free=bag.free;
    local needed={[4095+element]=loose,[4103+element]=clusters};
    for _,item in ipairs(bag.items) do
        if needed[item.id]~=nil then
            local usable=item.flags==0 and item.price==0 and type(item.extra)=='string' and #item.extra==28
                and integer(item.slot,1,80) and integer(item.count,1,99)
                and integer(item.stack_size,1,99) and item.count<=item.stack_size;
            if usable then
                local field=item.id==4095+element and 'loose' or 'clusters';
                p[field]=p[field]+item.count;
                local n=math.min(needed[item.id],item.count);
                if n>0 then p.rows[#p.rows+1]={slot=item.slot,id=item.id,count=n,name=item.name,source_count=item.count,extra=item.extra,flags=item.flags,price=item.price}; needed[item.id]=needed[item.id]-n end
            else notice(('Inventory slot %d is locked or cannot be validated.'):format(item.slot or 0)) end
        end
    end
    if needed[4095+element]>0 or needed[4103+element]>0 then notice('Not enough eligible crystals or clusters in Inventory.') end
    if #p.rows>8 then notice('This selection uses more than eight trade slots. Choose a smaller quantity.') end
    return p;
end
function M.all(bag,stored,npc,reason,busy)
    local p={rows={},notices={},units_by_element={0,0,0,0,0,0,0,0},can_start=true};
    local function block(s) p.notices[#p.notices+1]=s; p.can_start=false end
    if not npc then block(reason or 'No verified nearby Ephemeral Moogle.') end
    if busy then block('Wait for the current action to finish.') end
    if not bag or bag.id~=0 or bag.state~='Client snapshot' then block('Wait for readable Inventory contents.'); return p end
    for _,item in ipairs(bag.items) do
        if integer(item.id,4096,4111) then
            local cluster=item.id>=4104; local element=item.id-(cluster and 4103 or 4095);
            if item.flags==0 and item.price==0 and type(item.extra)=='string' and #item.extra==28
                and integer(item.slot,1,80) and integer(item.count,1,12) and integer(item.stack_size,item.count,12) then
                p.rows[#p.rows+1]={slot=item.slot,id=item.id,count=item.count,name=item.name,source_count=item.count,extra=item.extra,flags=item.flags,price=item.price};
                p.units_by_element[element]=p.units_by_element[element]+item.count*(cluster and 12 or 1);
            else p.notices[#p.notices+1]=('Skipped locked or unvalidated crystal stack in slot %d.'):format(item.slot or 0) end
        end
    end
    table.sort(p.rows,function(a,b) return a.slot<b.slot end);
    if #p.rows==0 then block('No eligible crystals or clusters in Inventory.') end
    for i,units in ipairs(p.units_by_element) do
        if units>0 then
            if not stored or not integer(stored[i],0,5000) then block('Refresh stored balances before confirming Deposit all.'); break
            elseif stored[i]+units>5000 then block(('Element %d would exceed 5000 stored units. Reduce that element before using Deposit all.'):format(i)) end
        end
    end
    p.batches=math.ceil(#p.rows/8);
    return p;
end
function M.new()
    local self={element=1,loose={0},clusters={0},show=false};
    function self:reset() self.element=1; self.loose={0}; self.clusters={0}; self.show=false; self.open=false; self.all_preview=nil end
    function self:render(names,balances,env)
        local imgui=require 'imgui';
        imgui.Separator();
        if imgui.Button('Preview deposit all crystals / clusters') then
            local npc,reason=env.target(true);
            self.all_preview=M.all(env.inventory(),balances,npc,reason,env.busy());
        end
        if self.all_preview then
            local p=self.all_preview;
            imgui.Text(('%d Inventory stacks in %d trade(s), up to 8 stacks each.'):format(#p.rows,p.batches or 0));
            imgui.TextWrapped('Only these reviewed stacks will be deposited. Stop cancels later trades; a trade already sent finishes confirmation. No retries.');
            for i,units in ipairs(p.units_by_element) do if units>0 then imgui.Text(names[i]..': '..units..' crystal units') end end
            for _,row in ipairs(p.rows) do imgui.Text(('%d x %s — Inventory slot %d'):format(row.count,row.name,row.slot)) end
            for _,notice in ipairs(p.notices) do imgui.TextColored({1,0.35,0.35,1},'Notice:'); imgui.SameLine(); imgui.TextWrapped(notice) end
            local npc=env.target(true);
            if not require('crystal_deposit').supported(npc) then imgui.TextWrapped('Stand within 6 yalms of an available Ephemeral Moogle.')
            elseif p.can_start and not env.busy() and env.deposit_all and imgui.Button('Confirm deposit all') then env.deposit_all(p); self.all_preview=nil end
            if imgui.Button('Cancel deposit all preview') then self.all_preview=nil end
        end
        if imgui.Button('Plan crystal deposit') then self.open=not self.open end
        if not self.open then return end
        imgui.TextWrapped('Select crystals or clusters already in Inventory, then preview. Nothing is traded until you explicitly confirm.');
        if imgui.BeginCombo('Element##Deposit',names[self.element]) then
            for i,name in ipairs(names) do if imgui.Selectable(name..'##DepositElement',i==self.element) then self.element=i; self.show=false end end
            imgui.EndCombo();
        end
        imgui.SetNextItemWidth(120); if imgui.InputInt('Loose crystals##Deposit',self.loose) then self.show=false end
        imgui.SetNextItemWidth(120); if imgui.InputInt('Clusters##Deposit',self.clusters) then self.show=false end
        if imgui.Button('Preview crystal deposit') then self.show=true end
        if not self.show then return end
        local npc,reason=env.target(true);
        local p=M.plan(env.inventory(),self.element,self.loose[1],self.clusters[1],balances and balances[self.element],npc,reason,env.busy());
        if npc then imgui.Text('Nearby Ephemeral Moogle verified within 6 yalms.') end
        if p.units then imgui.Text(('%d crystal units selected (each cluster counts as 12).'):format(p.units)) end
        imgui.Text(('Eligible in Inventory: %d crystals, %d clusters.'):format(p.loose,p.clusters));
        if p.projected then imgui.Text(('Estimated stored total: %d / 5000. Last known balance; not a fresh trade check.'):format(p.projected)) end
        for _,row in ipairs(p.rows) do imgui.Text(('%d x %s — Inventory slot %d'):format(row.count,row.name,row.slot)) end
        for _,message in ipairs(p.notices) do imgui.TextColored({1,0.35,0.35,1},'Notice:'); imgui.SameLine(); imgui.TextWrapped(message) end
        local controller=require 'crystal_deposit';
        if not controller.supported(npc) then
            imgui.TextWrapped('Stand within 6 yalms of an available Ephemeral Moogle.');
        elseif not controller.selection(env.inventory(),self.element,self.loose[1],self.clusters[1]) then
            imgui.TextWrapped('For an active deposit, select one Inventory stack: up to 12 loose crystals OR 12 clusters of one element.');
        elseif #p.notices==0 and env.deposit then
            imgui.TextWrapped('Confirm trades the listed stack after a fresh balance check. Once sent, the trade cannot be undone; the verified dialogue and confirmation will finish. No retries.');
            if imgui.Button('Confirm crystal deposit') then env.deposit(self.element,self.loose[1],self.clusters[1],p); self.show=false end
        end
    end
    return self;
end
return M;
