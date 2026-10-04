-- Explicit Inventory-only disposal. No background actions or uncertain retries.
-- Protocol field reference: Windower/Lua packets/fields.lua (0x028, 0x084,
-- 0x085, incoming 0x03C/0x03D). Implemented independently; no addon code copied.
local rules=require 'organization';
local M={};
local outgoing_fields={[0x028]=10,[0x084]=11,[0x085]=8};
local interrupting={[0x01A]=true,[0x05B]=true,[0x00D]=true,[0x00C]=true,[0x084]=true,[0x085]=true,
    [0x028]=true,[0x083]=true,[0x036]=true,[0x029]=true,[0x032]=true,[0x033]=true,
    [0x03A]=true,[0x050]=true,[0x051]=true,[0x052]=true,[0x096]=true};
local function uint(s,o,n)
    if type(s)~='string' or #s<o+n then return nil end
    local v=0; for i=n-1,0,-1 do v=v*256+s:byte(o+i+1) end; return v;
end
local function integer(n,a,b) return type(n)=='number' and n==n and n>=a and n<=b and n==math.floor(n) end
local function bytes(n) return n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256 end
local function equal(a,b)
    if not a or not b then return false end
    for _,k in ipairs({'id','slot','count','flags','price','extra','stack_size','item_type','resource_flags'}) do if a[k]~=b[k] then return false end end
    return true;
end
local function at(bag,slot) for _,v in ipairs(bag.items) do if v.slot==slot then return v end end end
local function total(bag,item)
    local n=0; for _,v in ipairs(bag.items) do if v.id==item.id and v.extra==item.extra then n=n+v.count end end; return n;
end
local function eligible(item,mode,env)
    if not integer(item.id,1,65534) or not integer(item.slot,1,80) or not integer(item.count,1,99)
        or type(item.extra)~='string' or #item.extra~=28 or item.flags~=0 or item.price~=0 then return false,'Locked or incomplete item data.' end
    if env.equipped(0,item.slot) then return false,'Unequip this item first.' end
    if not integer(item.item_type,0,65535) or not integer(item.stack_size,0,99) then return false,'Item resource data unavailable.' end
    if item.stack_size==0 and not (item.item_type==27 and item.count==1) then return false,'Item resource data unavailable.' end
    if item.stack_size>0 and item.count>item.stack_size then return false,'Invalid stack quantity.' end
    if mode=='sell' then
        if not integer(item.resource_flags,0,65535) then return false,'Sale eligibility unavailable.' end
        if math.floor(item.resource_flags/4096)%2==1 then return false,'Cannot be sold to NPCs. Change its marker to Drop only if you want to discard it.' end
    end
    return true;
end
function M.new(env)
    local self={outbox={}};
    function self:busy() return self.pending~=nil end
    local function shop_valid(shop)
        return shop and env.context('sell')==shop.key and env.now()-shop.opened<120 and env.npc(shop.index,shop.id);
    end
    function self:cancel(reason)
        self.preview=nil;
        if self.pending then
            self.pending.stopped=true; self.pending.stop_reason=self.pending.stop_reason or reason;
            local detail=self.pending.stop_reason and (' '..self.pending.stop_reason) or '';
            if self.pending.stage~='sent' then self.pending=nil; self.message='Stopped. No further items processed.'..detail
            else self.message='Stopping after the sent request is confirmed. No further items will be processed.'..detail end
        end
    end
    function self:reset() self:cancel('Character or zone context reset.'); self.shop=nil; self.interaction=nil end
    local function send(id,payload)
        -- Ashita may report injections after AddOutgoingPacket returns. Match only
        -- our queued bytes; other addons must invalidate the reviewed action too.
        for i=#self.outbox,1,-1 do if env.now()-self.outbox[i].time>=8 then table.remove(self.outbox,i) end end
        self.outbox[#self.outbox+1]={id=id,data=payload,time=env.now()};
        local ok,result=pcall(env.send,id,payload);
        return ok and result~=false;
    end
    local function fresh(p)
        if p.stopped or env.context(p.mode)~=p.key or env.busy() or rules.rules_signature(env.rules())~=p.rules then return nil end
        if p.mode=='sell' and (self.shop~=p.shop or not shop_valid(p.shop)) then return nil end
        local data=env.scan(); local bag=data and data[1];
        if not bag or bag.state~='Client snapshot' then return nil end
        local wanted=p.rows[p.index]; local item=at(bag,wanted.slot);
        if not equal(item,wanted) or not eligible(item,p.mode,env) then return nil end
        if env.context(p.mode)~=p.key or env.busy() or rules.rules_signature(env.rules())~=p.rules
            or (p.mode=='sell' and not shop_valid(p.shop)) then return nil end
        return bag,item;
    end
    function self:plan(mode)
        if self:busy() or env.busy() or (mode~='drop' and mode~='sell') then return false end
        self.preview=nil;
        local ok,p=pcall(function()
            local key=env.context(mode); if not key then self.message='Wait until your character is ready.'; return end
            local data=env.scan(); local bag=data and data[1]; if not bag or bag.state~='Client snapshot' then self.message='Inventory is unavailable. Refresh and try again.'; return end
            local p={mode=mode,key=key,rows={},notices={},signature=rules.signature(data),rules=rules.rules_signature(env.rules()),shop=self.shop};
            local normalized=rules.normalize(env.rules());
            for _,item in ipairs(bag.items) do
                local rule=normalized.items[tostring(item.id)];
                if rule and rule[mode] then
                    local allowed,reason=eligible(item,mode,env);
                    if rule.protected then allowed=false; reason='Marked untouched.' end
                    if allowed then local copy={}; for k,v in pairs(item) do copy[k]=v end; p.rows[#p.rows+1]=copy
                    else p.notices[#p.notices+1]=item.name..': '..reason end
                end
            end
            if mode=='sell' and not shop_valid(self.shop) then p.notices[#p.notices+1]='Open a normal NPC shop first, then preview again. Guild shops are not supported.'; p.blocked=true end
            return p;
        end);
        if ok then self.preview=p else self.message='Could not validate disposal preview. Nothing sent.' end
        return self.preview~=nil;
    end
    function self:start()
        local p=self.preview; if not p or p.blocked or #p.rows==0 or self:busy() or env.busy() then return false end
        local ok=pcall(function()
            if p.key~=env.context(p.mode) or p.signature~=rules.signature(env.scan()) or p.rules~=rules.rules_signature(env.rules())
                or (p.mode=='sell' and (p.shop~=self.shop or not shop_valid(p.shop))) then self.preview=nil; self.message='Preview changed. Review a fresh list.'; return end
            p.index=1; p.done=0; p.stage='next'; p.next_at=env.now(); self.pending=p; self.preview=nil;
            self.message='Queued reviewed Inventory stacks.';
        end);
        if not ok then self.message='Could not validate disposal. Nothing sent.' end
        return self.pending~=nil;
    end
    function self:outgoing(e)
        if e.blocked or not interrupting[e.id] then return end
        local ok=pcall(function()
            -- data_modified is the effective packet after Ashita/plugin processing.
            -- Compare the operation fields, not buffer length or reserved padding.
            local data=type(e.data_modified)=='string' and e.data_modified or e.data;
            local last_field=outgoing_fields[e.id];
            if e.injected and last_field and type(data)=='string' then
                for i,v in ipairs(self.outbox) do
                    local matches=e.id==v.id and #data>=#v.data and env.now()-v.time<8
                        and (e.size==nil or (integer(e.size,#v.data,#data)));
                    if matches then for j=5,last_field do if data:byte(j)~=v.data[j] then matches=false; break end end end
                    if matches then table.remove(self.outbox,i); return end
                end
            end
            local reason=('Outgoing action 0x%03X (%s; size %s, buffer %s).'):format(e.id,e.injected and 'injected' or 'manual',tostring(e.size),type(data)=='string' and tostring(#data) or type(data));
            if e.id==0x01A then
                self.shop=nil; self.interaction=nil; self:cancel(reason);
                local id,index,category=uint(data,4,4),uint(data,8,2),uint(data,10,2);
                if category==0 and integer(id,1,4294967295) and integer(index,1,0x8FF) and env.npc(index,id) then
                    self.interaction={id=id,index=index,key=env.context('sell'),opened=env.now()};
                end
            elseif e.id==0x05B or e.id==0x00D or e.id==0x00C then self:cancel(reason); self.shop=nil
            elseif e.id==0x084 or e.id==0x085 or e.id==0x028 or e.id==0x083 or e.id==0x036 or e.id==0x029
                or e.id==0x032 or e.id==0x033 or e.id==0x03A or e.id==0x050 or e.id==0x051 or e.id==0x052 or e.id==0x096 then self:cancel(reason); self.shop=nil end
        end);
        if not ok then self:cancel('Outgoing packet could not be validated.'); self.shop=nil end
    end
    function self:incoming(e)
        if e.blocked or e.injected then return end
        local ok=pcall(function()
            if e.id==0x00A or e.id==0x00B then self:reset(); return end
            if e.id==0x03C and type(e.data)=='string' and #e.data>=16 then
                local t=self.interaction;
                if t and t.key and env.now()-t.opened<30 and t.key==env.context('sell') and env.npc(t.index,t.id) then
                    self.shop={id=t.id,index=t.index,key=t.key,opened=env.now()}; self.interaction=nil;
                end
                return;
            end
            local p=self.pending;
            if e.id~=0x03D or not p or p.mode~='sell' or #e.data<16 then return end
            local price,slot,kind,count=uint(e.data,4,4),uint(e.data,8,1),uint(e.data,9,1),uint(e.data,12,4);
            if slot~=p.rows[p.index].slot then self:cancel('NPC replied for a different Inventory slot.'); return end
            if p.stage=='quote' and kind==0 then
                if env.now()>=p.deadline then self:cancel(); self.message='Sale price arrived too late. No sale confirmation sent.'; return end
                if not integer(price,1,999999999) or not integer(count,1,p.rows[p.index].count) then self:cancel(); self.message='NPC did not offer a valid sale price. Nothing sold.'; return end
                local bag,item=fresh(p); if not bag then self:cancel('Item, rules, character or shop changed during appraisal.'); return end
                p.stage='sent'; p.deadline=env.now()+8; p.before=total(bag,item); p.sale_response=false;
                self.message='Sale requested; waiting for server and Inventory confirmation.';
                send(0x085,{0,0,0,0,1,0,0,0});
            elseif p.stage=='sent' and kind==1 and count==p.rows[p.index].count and price>0 then p.sale_response=true end
        end);
        if not ok then self:cancel(); self.message='Sale response unavailable. Check Inventory; no retry sent.' end
    end
    function self:tick()
        local p=self.pending; if not p then return end
        local ok=pcall(function()
            local now=env.now(); if now<(p.next_at or 0) then return end; p.next_at=now+0.25;
            if p.stage=='sent' then
                if now>=p.deadline then p.stopped=true end
                if env.context(p.mode)~=p.key then p.stopped=true; self.message='Context changed. Outcome unknown; no further items processed.'; return end
                local data=env.scan(); local bag=data and data[1]; local item=p.rows[p.index];
                local matched=bag and bag.state=='Client snapshot' and not at(bag,item.slot) and total(bag,item)==p.before-item.count
                    and (p.mode=='drop' or p.sale_response);
                if matched then
                    if p.confirmed and now-p.confirmed>=0.25 then
                        p.done=p.done+1; p.index=p.index+1; p.stage='next'; p.confirmed=nil; env.changed();
                        if p.stopped or p.index>#p.rows then self.pending=nil; self.message=('%d/%d stacks %s confirmed.%s'):format(p.done,#p.rows,p.mode=='drop' and 'dropped' or 'sold',p.stopped and (' Stopped.'..(p.stop_reason and (' '..p.stop_reason) or '')) or ' Finished.'); return end
                    else p.confirmed=p.confirmed or now end
                else p.confirmed=nil end
                if now>=p.deadline then p.stopped=true; self.message='Disposal not confirmed. Check Inventory before reloading. Further actions locked; no retry sent.' end
                return;
            end
            if p.stage=='quote' then
                if now>=p.deadline or not fresh(p) then self:cancel(); self.message='Sale appraisal stopped or timed out. No sale confirmation sent.' end
                return;
            end
            local bag,item=fresh(p); if not bag then self:cancel(); self.message='Reviewed item, rules, access or shop changed. Review a fresh list.'; return end
            p.before=total(bag,item); p.deadline=now+8;
            if p.mode=='drop' then
                p.stage='sent'; local a,b,c,d=bytes(item.count);
                self.message='Drop requested; waiting for Inventory confirmation.';
                send(0x028,{0,0,0,0,a,b,c,d,0,item.slot,0,0});
            else
                p.stage='quote'; local a,b,c,d=bytes(item.count);
                self.message='Requesting a fresh NPC sale price.';
                if not send(0x084,{0,0,0,0,a,b,c,d,item.id%256,math.floor(item.id/256),item.slot,0}) then self:cancel(); self.message='Appraisal outcome unknown. No sale confirmation sent.' end
            end
        end);
        if not ok then self:cancel(); self.message='Disposal validation unavailable. No retries; check any request already sent.' end
    end
    return self;
end
return M;
