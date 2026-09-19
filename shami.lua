-- Shami retrieval/exchange controller. One fresh menu, one response, no retries.
local M={};
M.seals={1126,1127,2955,2956,2957};
local retrieve={2,1,3,4,5};
M.orbs={
    {name='Cloudy Orb',id=1551,seal=1,cost=20}, {name='Sky Orb',id=1552,seal=1,cost=30},
    {name='Star Orb',id=1131,seal=1,cost=40}, {name='Comet Orb',id=1177,seal=1,cost=50},
    {name='Moon Orb',id=1130,seal=1,cost=60}, {name='Clotho Orb',id=1175,seal=2,cost=30},
    {name='Lachesis Orb',id=1178,seal=2,cost=30}, {name='Atropos Orb',id=1180,seal=2,cost=30},
    {name='Themis Orb',id=1553,seal=2,cost=99}, {name='Phobos Orb',id=3351,seal=3,cost=30},
    {name='Deimos Orb',id=3352,seal=3,cost=50}, {name='Zelos Orb',id=3454,seal=4,cost=30},
    {name='Bia Orb',id=3455,seal=4,cost=50}, {name='Microcosmic Orb',id=4062,seal=5,cost=10},
    {name='Macrocosmic Orb',id=4063,seal=5,cost=20},
};
local function uint(s,o,n)
    if type(s)~='string' or #s<o+n then return nil end
    local v=0; for i=n-1,0,-1 do v=v*256+s:byte(o+i+1) end; return v;
end
local function packet(size,fields)
    local p={}; for i=1,size do p[i]=0 end
    for _,f in ipairs(fields) do local v=f[2]; for i=1,f[3] do p[f[1]+i]=v%256; v=math.floor(v/256) end end
    return p;
end
function M.plan(mode,index,quantity)
    if type(index)~='number' or index~=math.floor(index) then return nil end
    if mode=='withdraw' and M.seals[index] and type(quantity)=='number' and quantity==math.floor(quantity) and quantity>=1 and quantity<=9999 then
        return {item=M.seals[index],count=quantity,seal=index,cost=quantity,option=(quantity+1)*256-retrieve[index],slots=math.ceil(quantity/99)};
    end
    if mode=='orb' and M.orbs[index] then
        local orb=M.orbs[index];
        return {item=orb.id,count=1,seal=orb.seal,cost=orb.cost,option=index,slots=1,orb=orb.name};
    end
    return nil;
end
local function total(bag,id)
    local n=0; for _,item in ipairs(bag.items) do if item.id==id then n=n+item.count end end; return n;
end
local function valid(data,p)
    local bag=data and data[1];
    if not bag or bag.state~='Client snapshot' or not bag.free or bag.free<p.slots then return nil,'Not enough verified free Inventory slots.' end
    if p.orb then
        for _,b in ipairs(data) do
            if b.state=='Client snapshot' and total(b,p.item)>0 then return nil,'This orb is already in a readable bag.' end
        end
    end
    return bag;
end
function M.new(env)
    local self={};
    function self:reset() self.pending=nil; self.message=nil end
    local function same(a,b) return a and b and a.key==b.key and a.id==b.id and a.index==b.index and a.zone==b.zone end
    function self:start(mode,index,quantity)
        if self.pending then return false end
        local plan=M.plan(mode,index,quantity);
        if not plan then self.message='This Shami operation is not enabled.'; return false end
        local npc,reason=env.target(true);
        if not npc or npc.zone~=246 then self.message=reason or 'Target Shami in Port Jeuno.'; return false end
        local bag,problem=valid(env.scan(),plan); if not bag then self.message=problem; return false end
        plan.npc=npc; plan.stage='menu'; plan.deadline=env.now()+8; self.pending=plan;
        self.message='Requesting a fresh Shami menu...';
        local ok=pcall(env.send,0x01A,packet(28,{{4,npc.id,4},{8,npc.index,2}}));
        if not ok then self.message='Interaction outcome unknown; no retry sent.' end
        return true;
    end
    function self:observe(e)
        local p=self.pending; if not p or p.stage~='menu' or e.injected or e.blocked then return end
        if e.id~=0x032 and e.id~=0x033 and e.id~=0x034 then return end
        local function reject(reason) self.pending=nil; self.message=reason..' Use the normal NPC menu.' end
        if e.id~=0x034 or uint(e.data,4,4)~=p.npc.id or uint(e.data,0x28,2)~=p.npc.index or uint(e.data,0x2A,2)~=246 or uint(e.data,0x2C,2)~=322 then reject('Unverified Shami menu; nothing sent.'); return end
        if env.now()>=p.deadline or not same(env.target(false,p.npc),p.npc) then reject('Interaction changed; nothing sent.'); return end
        local balance=uint(e.data,8+(p.seal-1)*2,2);
        local bag,problem=valid(env.scan(),p);
        if not balance or balance<p.cost then reject('Insufficient stored seals/crests.'); return end
        if not bag then reject(problem); return end
        p.before=total(bag,p.item); p.stage='confirm'; p.deadline=env.now()+10; p.next_check=env.now();
        e.blocked=true; self.message='Shami request sent; waiting for Inventory confirmation.';
        local ok=pcall(env.send,0x05B,packet(20,{{4,p.npc.id,4},{8,p.option,4},{12,p.npc.index,2},{16,246,2},{18,322,2}}));
        if not ok then self.message='Request outcome unknown. Check Inventory; no retry sent.' end
    end
    function self:manual_action(e)
        if self.pending and self.pending.stage=='menu' and e.id==0x05B and not e.injected and not e.blocked then self.pending=nil; self.message='Manual NPC response observed; Shami operation cancelled.' end
    end
    function self:tick()
        local p=self.pending; if not p then return end
        if p.stage=='menu' then
            if env.now()>=p.deadline or not same(env.target(false,p.npc),p.npc) then self.pending=nil; self.message='No verified Shami menu received; nothing spent.' end
            return;
        end
        if env.key()~=p.npc.key then self.message='Character context changed; Shami outcome unknown.'; return end
        if env.now()<p.next_check then return end; p.next_check=env.now()+0.25;
        local data=env.scan(); local bag=data and data[1];
        if bag and bag.state=='Client snapshot' and total(bag,p.item)==p.before+p.count then
            if p.confirmed and env.now()-p.confirmed>=0.25 then
                self.pending=nil; self.message=p.orb and ('Received '..p.orb..' from Shami.') or ('Received %d seal(s)/crest(s) from Shami.'):format(p.count); env.changed(); return;
            end
            p.confirmed=p.confirmed or env.now();
        else p.confirmed=nil end
        if env.now()>=p.deadline then self.message='Shami result not confirmed. Check Inventory; further requests locked. No retry sent.' end
    end
    return self;
end
return M;
