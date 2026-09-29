-- Explicitly reviewed trades, at most eight stacks per confirmed batch.
local preview=require 'crystal_deposit_preview';
local M={};
local function uint(s,o,n)
    if type(s)~='string' or #s<o+n then return nil end
    local v=0; for i=n-1,0,-1 do v=v*256+s:byte(o+i+1) end; return v;
end
local function packet(size,fields)
    local p={}; for i=1,size do p[i]=0 end
    for _,f in ipairs(fields) do local v=f[2]; for i=1,f[3] do p[f[1]+i]=v%256; v=math.floor(v/256) end end
    return p;
end
-- env.target verifies the NPC name, range and render state on every lookup.
local function integer(v,maximum) return type(v)=='number' and v>=1 and v<=maximum and v==math.floor(v) end
function M.supported(npc)
    return npc and npc.name=='Ephemeral Moogle' and npc.key~=nil
        and integer(npc.zone,65535) and integer(npc.id,4294967295) and integer(npc.index,0x8FF);
end
local function same(a,b) return a and b and a.key==b.key and a.id==b.id and a.index==b.index and a.zone==b.zone end
local function balances(data,offset)
    local values={}; for i=1,8 do
        local v=uint(data,offset+(i-1)*2,2); if not v or v>5000 then return nil end; values[i]=v;
    end
    return values;
end
local function total(bag,id)
    if not bag or bag.id~=0 or bag.state~='Client snapshot' then return nil end
    local n=0; for _,item in ipairs(bag.items) do if item.id==id then n=n+item.count end end; return n;
end
local function same_row(a,b)
    if not a or not b then return false end
    for _,key in ipairs({'slot','id','count','source_count','extra','flags','price'}) do if a[key]~=b[key] then return false end end
    return true;
end
local function checked_rows(bag,rows)
    if not bag or bag.state~='Client snapshot' or bag.id~=0 then return false end
    local slots={}; for _,item in ipairs(bag.items) do slots[item.slot]=item end
    local seen={};
    for _,row in ipairs(rows) do
        local item=slots[row.slot];
        if seen[row.slot] or not item or item.id~=row.id or item.count~=row.source_count
            or item.extra~=row.extra or item.flags~=0 or item.price~=0 or item.stack_size==nil
            or item.stack_size<item.count or item.stack_size>12 then return false end
        seen[row.slot]=true;
    end
    return true;
end
local function units(rows)
    local result={0,0,0,0,0,0,0,0};
    for _,r in ipairs(rows) do local cluster=r.id>=4104; local i=r.id-(cluster and 4103 or 4095); result[i]=result[i]+r.count*(cluster and 12 or 1) end
    return result;
end
function M.selection(bag,element,loose,clusters)
    local p=preview.plan(bag,element,loose,clusters,0,{},nil,false);
    if #p.notices>0 or #p.rows~=1 or (loose>0 and clusters>0) or p.rows[1].count>12 then return nil end
    return p;
end
function M.new(env)
    local self={};
    local function uncertain(reason)
        self.pending.stage='uncertain'; self.message=reason..' Check bags and the NPC dialogue before reloading. No retry sent.';
    end
    local function send(id,data)
        local ok,result=pcall(env.send,id,data);
        if not ok or result==false then uncertain('Request outcome unknown.'); return false end
        return true;
    end
    function self:cancel()
        local p=self.pending; if not p then return end
        if p.stage=='uncertain' then return end
        p.stop_requested=true;
        if p.stage=='balance' or p.stage=='next' then self.pending=nil; self.message=('Deposit stopped; %d trade%s confirmed. No further trades sent.'):format(p.done,p.done==1 and '' or 's')
        else self.message='Stopping after the sent trade confirms. No further trades will be sent.' end
    end
    local function response(p,automated)
        return packet(20,{{4,p.npc.id,4},{12,p.npc.index,2},{14,automated,1},{16,p.npc.zone,2},{18,p.menu,2}});
    end
    local function matches_balance(p,values)
        if not values then return false end
        for i=1,8 do if values[i]~=p.before[i]+p.units_by_element[i] then return false end end
        return true;
    end
    local function begin_batch(p)
        p.rows={};
        for i=p.next_row,math.min(#p.all_rows,p.next_row+7) do p.rows[#p.rows+1]=p.all_rows[i] end
        p.units_by_element=units(p.rows); p.params={0,0,0,0,0,0,0,0}; p.item_counts={};
        p.units=0;
        for _,r in ipairs(p.rows) do
            local cluster=r.id>=4104; local i=r.id-(cluster and 4103 or 4095);
            p.params[i]=p.params[i]+r.count*(cluster and 1 or 65536);
            p.item_counts[r.id]=(p.item_counts[r.id] or 0)+r.count;
        end
        for _,n in ipairs(p.units_by_element) do p.units=p.units+n end
        p.menu=nil; p.stage='balance'; p.deadline=env.now()+10; p.confirmed_at=nil; p.balance_confirmed=nil;
        self.message=('Deposit trade %d/%d: refreshing stored balances...'):format(p.done+1,p.batch_count);
        send(0x10F,{0,0,0,0});
    end
    local function start_rows(npc,rows)
        local frozen={}; for i,row in ipairs(rows) do frozen[i]={}; for k,v in pairs(row) do frozen[i][k]=v end end
        self.pending={npc=npc,all_rows=frozen,next_row=1,done=0,confirmed_units=0,batch_count=math.ceil(#rows/8)};
        begin_batch(self.pending);
    end
    function self:start(element,loose,clusters,reviewed)
        if self.pending then return false end
        local ok=pcall(function()
            local npc,reason=env.target(true);
            if not M.supported(npc) then self.message=reason or 'A verified Ephemeral Moogle must be within 6 yalms.'; return end
            local bag=env.inventory(); local plan=M.selection(bag,element,loose,clusters);
            if not plan or not reviewed or not same_row(plan.rows[1],reviewed.rows and reviewed.rows[1]) then
                self.message='Choose one unchanged Inventory stack (up to 12 crystals or clusters), then preview again.'; return;
            end
            start_rows(npc,plan.rows);
        end);
        if not ok then
            if self.pending then uncertain('Deposit validation unavailable.') else self.message='Cannot validate deposit; nothing sent.' end
        end
        return self.pending~=nil;
    end
    function self:start_all(reviewed)
        if self.pending then return false end
        local ok=pcall(function()
            local npc,reason=env.target(true);
            if not M.supported(npc) then self.message=reason or 'A verified Ephemeral Moogle must be within 6 yalms.'; return end
            local fresh=preview.all(env.inventory(),{0,0,0,0,0,0,0,0},npc,nil,false);
            if not reviewed or not reviewed.can_start or not fresh.can_start or #fresh.rows~=#reviewed.rows then self.message='Deposit-all selection changed or is blocked. Preview again.'; return end
            for i,row in ipairs(fresh.rows) do if not same_row(row,reviewed.rows[i]) then self.message='Inventory changed. Preview Deposit all again.'; return end end
            start_rows(npc,fresh.rows);
        end);
        if not ok then if self.pending then uncertain('Deposit-all validation unavailable.') else self.message='Cannot validate Deposit all; nothing sent.' end end
        return self.pending~=nil;
    end
    local function observe(e)
        local p=self.pending; if not p or e.injected or e.blocked or p.stage=='uncertain' then return end
        if env.key()~=p.npc.key then
            if p.stage=='balance' or p.stage=='next' then self:cancel() else uncertain('Player context changed.') end; return;
        end
        if env.now()>=p.deadline then
            if p.stage=='balance' or p.stage=='next' then self:cancel() else uncertain('Deposit confirmation timed out.') end; return;
        end
        if p.stage=='balance' and e.id==0x113 then
            local values=balances(e.data,0xE8);
            local npc=env.target(true,p.npc); local bag=env.inventory();
            local remaining={}; for i=p.next_row,#p.all_rows do remaining[#remaining+1]=p.all_rows[i] end
            local within_cap=values~=nil;
            if values then for i,n in ipairs(units(remaining)) do if values[i]+n>5000 then within_cap=false end end end
            if not within_cap or not same(npc,p.npc) or not checked_rows(bag,remaining) then
                self.pending=nil; self.message='Balance, NPC or Inventory changed; no trade sent. Preview again.'; return;
            end
            p.before=values; p.before_totals={}; for id=4096,4111 do p.before_totals[id]=total(bag,id) end
            p.stage='menu'; p.deadline=env.now()+10;
            self.message=('Deposit trade %d/%d sent; waiting for the verified Moogle menu.'):format(p.done+1,p.batch_count);
            local fields={{4,p.npc.id,4},{0x3A,p.npc.index,2},{0x3C,#p.rows,1}};
            for i,r in ipairs(p.rows) do fields[#fields+1]={8+(i-1)*4,r.count,4}; fields[#fields+1]={0x30+i-1,r.slot,1} end
            send(0x036,packet(64,fields));
        elseif p.stage=='menu' and (e.id==0x032 or e.id==0x033 or e.id==0x034) then
            local menu=uint(e.data,0x2C,2);
            local valid=e.id==0x034 and type(e.data)=='string' and #e.data>=0x30
                and uint(e.data,4,4)==p.npc.id and uint(e.data,0x28,2)==p.npc.index
                and uint(e.data,0x2A,2)==p.npc.zone and menu and menu>0
                and same(env.target(false,p.npc),p.npc);
            if valid then
                for i=1,8 do
                    if uint(e.data,8+(i-1)*4,4)~=p.params[i] then valid=false end
                end
            end
            if not valid then uncertain('Unverified trade menu; no automatic response sent.'); return end
            p.menu=menu; p.stage='update'; p.deadline=env.now()+10; e.blocked=true;
            self.message='Deposit menu verified; waiting for the stored-balance update.';
            send(0x05B,response(p,1));
        elseif p.stage=='update' and e.id==0x05C then
            if type(e.data)~='string' or #e.data<0x24 or not same(env.target(false,p.npc),p.npc)
                or not matches_balance(p,balances(e.data,4)) then uncertain('Unexpected deposit balance update.'); return end
            p.stage='inventory'; p.deadline=env.now()+10;
            self.message='Stored balance updated; confirming the Inventory decrease.';
        elseif p.stage=='final' and e.id==0x113 then
            if not matches_balance(p,balances(e.data,0xE8)) then uncertain('Final stored balance does not match the deposit.'); return end
            p.balance_confirmed=true;
        elseif p.stage~='balance' and (e.id==0x032 or e.id==0x033 or e.id==0x034) then
            uncertain('Another NPC menu interrupted deposit confirmation.');
        end
    end
    function self:observe(e)
        local ok=pcall(observe,e);
        if not ok and self.pending then uncertain('Deposit response validation unavailable.') end
    end
    function self:manual_action(e)
        local p=self.pending;
        if not p or e.injected or e.blocked then return end
        if e.id==0x036 or e.id==0x05B or e.id==0x01A or e.id==0x096 then
            if p.stage=='balance' or p.stage=='next' then self:cancel() else uncertain('Another action interrupted the deposit.') end
        end
    end
    local function tick()
        local p=self.pending; if not p or p.stage=='uncertain' then return end
        if env.key()~=p.npc.key or env.now()>=p.deadline then
            if p.stage=='balance' or p.stage=='next' then self:cancel() else uncertain('Deposit context changed or confirmation timed out.') end; return;
        end
        if p.stage=='next' then
            if p.stop_requested then self:cancel(); return end
            if same(env.target(true,p.npc),p.npc) then begin_batch(p) end
            return;
        end
        if p.stage~='inventory' and p.stage~='final' then return end
        local bag=env.inventory(); local inventory_matches=true;
        for id=4096,4111 do if total(bag,id)~=p.before_totals[id]-(p.item_counts[id] or 0) then inventory_matches=false end end
        if inventory_matches then
            if not p.confirmed_at then p.confirmed_at=env.now(); return end
            if env.now()-p.confirmed_at<0.25 then return end
            if p.stage=='inventory' then
                if not same(env.target(false,p.npc),p.npc) then uncertain('Moogle no longer available.'); return end
                p.stage='final'; p.confirmed_at=nil; p.deadline=env.now()+10;
                if not send(0x05B,response(p,0)) then return end
                self.message='Deposit dialogue finished; refreshing balances for final confirmation.';
                send(0x10F,{0,0,0,0});
            elseif p.balance_confirmed then
                p.done=p.done+1; p.confirmed_units=p.confirmed_units+p.units; p.next_row=p.next_row+#p.rows; env.changed();
                if not p.stop_requested and p.next_row<=#p.all_rows then
                    p.stage='next'; p.deadline=env.now()+10;
                    self.message=('Deposit: %d/%d trades confirmed. Waiting for the Moogle to be ready.'):format(p.done,p.batch_count);
                else
                    self.pending=nil;
                    self.message=('Deposited %d crystal unit%s; Inventory and stored balance confirmed. %d/%d trade%s confirmed.%s'):format(p.confirmed_units,p.confirmed_units==1 and '' or 's',p.done,p.batch_count,p.batch_count==1 and '' or 's',p.stop_requested and ' Stopped; no further trades sent.' or '');
                end
            end
        else p.confirmed_at=nil end
    end
    function self:tick()
        local ok=pcall(tick); if not ok and self.pending then uncertain('Deposit confirmation unavailable.') end
    end
    return self;
end
return M;
