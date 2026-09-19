-- One requested NPC interaction followed by one verified menu response. No retries.
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
function M.response(npc,element,quantity)
    return packet(20,{{4,npc.id,4},{8,quantity+element*65536+0x40000000,4},{12,npc.index,2},{16,npc.zone,2},{18,npc.menu,2}});
end
function M.space(quantity) return math.ceil(math.floor(quantity/12)/12)+(quantity%12>0 and 1 or 0) end
local function totals(bag,element)
    local loose,clusters=0,0;
    for _,item in ipairs(bag.items) do
        if item.id==4095+element then loose=loose+item.count end
        if item.id==4103+element then clusters=clusters+item.count end
    end
    return loose,clusters;
end
function M.new(env)
    local self={};
    function self:reset() self.pending=nil; self.message=nil end
    local function same(a,b) return a and b and a.key==b.key and a.id==b.id and a.index==b.index and a.zone==b.zone end
    function self:start(element,quantity)
        if self.pending then return false end
        if type(element)~='number' or element<1 or element>8 or element~=math.floor(element)
            or type(quantity)~='number' or quantity<1 or quantity>65535 or quantity~=math.floor(quantity) then return false end
        local npc,reason=env.target(true);
        if not npc then self.message=reason; return false end
        if npc.zone~=234 then self.message='This first version supports the tested Bastok Mines Moogle only.'; return false end
        local bag=env.inventory();
        if not bag or bag.state~='Client snapshot' or bag.free<M.space(quantity) then self.message='Not enough verified free Inventory slots.'; return false end
        self.pending={stage='menu',npc=npc,element=element,quantity=quantity,deadline=env.now()+8};
        self.message='Requesting the selected Moogle menu...';
        -- State precedes the send so an uncertain result can never trigger a retry.
        local ok=pcall(env.send,0x01A,packet(28,{{4,npc.id,4},{8,npc.index,2}}));
        if not ok then self.message='Interaction outcome unknown. No retry sent.' end
        return true;
    end
    function self:observe(e)
        local p=self.pending;
        if not p or p.stage~='menu' or e.injected or e.blocked then return end
        if e.id~=0x032 and e.id~=0x033 and e.id~=0x034 then return end
        local function reject(reason) self.pending=nil; self.message=reason..' Use the normal NPC menu.' end
        if e.id~=0x034 or uint(e.data,4,4)~=p.npc.id or uint(e.data,0x28,2)~=p.npc.index
            or uint(e.data,0x2A,2)~=p.npc.zone or uint(e.data,0x2C,2)~=617 then reject('Unverified menu; no withdrawal sent.'); return end
        if env.now()>=p.deadline or not same(env.target(false,p.npc),p.npc) then reject('Interaction changed; no withdrawal sent.'); return end
        local stored=uint(e.data,8+(p.element-1)*2,2);
        local bag=env.inventory();
        if not stored or stored<p.quantity or not bag or bag.state~='Client snapshot' or bag.free<M.space(p.quantity) then
            reject('Stored balance or Inventory space is insufficient.'); return;
        end
        p.npc.menu=617; p.before_loose,p.before_clusters=totals(bag,p.element);
        p.stage='confirm'; p.deadline=env.now()+10; p.next_check=env.now();
        -- Only this verified, requested menu is suppressed. Other menus remain native.
        e.blocked=true;
        self.message='Crystal withdrawal requested; waiting for Inventory confirmation.';
        local ok=pcall(env.send,0x05B,M.response(p.npc,p.element,p.quantity));
        if not ok then self.message='Withdrawal outcome unknown. Check Inventory; no retry sent.' end
    end
    function self:manual_action(e)
        if self.pending and self.pending.stage=='menu' and not e.injected and not e.blocked and e.id==0x05B then
            self.pending=nil; self.message='Manual NPC response observed; automatic withdrawal cancelled.';
        end
    end
    function self:tick()
        local p=self.pending; if not p then return end
        if p.stage=='menu' then
            if env.now()>=p.deadline or not same(env.target(false,p.npc),p.npc) then self.pending=nil; self.message='No verified Moogle menu received; no withdrawal sent.' end
            return;
        end
        if env.key()~=p.npc.key then self.message='Player context changed; withdrawal outcome unknown.'; return end
        if env.now()<p.next_check then return end
        p.next_check=env.now()+0.25;
        local bag=env.inventory();
        if bag and bag.state=='Client snapshot' then
            local loose,clusters=totals(bag,p.element);
            if loose==p.before_loose+p.quantity%12 and clusters==p.before_clusters+math.floor(p.quantity/12) then
                if p.confirmed and env.now()-p.confirmed>=0.25 then
                    self.pending=nil; self.message=('Received %d cluster(s) and %d crystal(s).'):format(math.floor(p.quantity/12),p.quantity%12); env.changed(); return;
                end
                p.confirmed=p.confirmed or env.now();
            else p.confirmed=nil end
        end
        if env.now()>=p.deadline then self.message='Crystal withdrawal not confirmed. Check Inventory; further withdrawals locked. No retry sent.' end
    end
    return self;
end
return M;
