-- Opt-in, bounded read-only capture of one named NPC menu session.
local M={};
local function uint(data,offset,size)
    if type(data)~='string' or #data<offset+size then return nil end
    local value=0; for i=size-1,0,-1 do value=value*256+data:byte(offset+i+1) end
    return value;
end
function M.new(env)
    local self={};
    local npc_name=env.npc_name or 'ephemeral moogle';
    function self:stop() self.deadline=nil; self.target=nil; self.trade_target=nil; self.trade_index=nil end
    function self:start(deposit)
        self:stop(); self.count=0;
        self.deposit=deposit==true;
        if not env.write('BEGIN '..(self.deposit and 'manual crystal deposit' or env.label or 'manual crystal withdrawal')..' trace') then return false end
        self.deadline=env.now()+(env.duration or 60); return true;
    end
    function self:observe(direction,id,data)
        if not self.deadline then return end
        if env.now()>=self.deadline or (direction=='in' and (id==0x00A or id==0x00B)) then self:stop(); return end
        if type(data)~='string' then return end
        local size,first= nil,5;
        if self.deposit and direction=='out' and id==0x036 then
            size=0x40; if type(data)~='string' or #data<size then return end
            local index=uint(data,0x3A,2); local target=uint(data,4,4);
            if index<1 or index>0x8FF or target==0 then return end
            local ok,name=pcall(env.name,index);
            local id_ok,server_id=pcall(env.id,index);
            if not ok or not id_ok or type(name)~='string' or name:gsub('_',' '):lower()~=npc_name or server_id~=target then return end
            self.trade_target=target; self.trade_index=index; self.target=nil;
        elseif direction=='in' and (id==0x032 or id==0x033 or id==0x034) then
            self.target=nil;
            local index=uint(data,id==0x034 and 0x28 or 8,2);
            size=id==0x034 and 0x30 or (id==0x033 and 0x70 or 0x10);
            if not index or #data<size then return end
            local ok,name=pcall(env.name,index);
            if not ok or type(name)~='string' or name:gsub('_',' '):lower()~=npc_name then return end
            if self.deposit and (self.trade_target~=uint(data,4,4) or self.trade_index~=index) then return end
            self.target=uint(data,4,4);
        elseif self.deposit and direction=='in' and self.target and id==0x05C then
            size=0x24; if #data<size then return end
        elseif self.deposit and direction=='in' and self.target and id==0x113 then
            size=0xF8; first=0xE9; if #data<size then return end -- Crystal balances only.
        elseif direction=='out' and id==0x05B and self.target and uint(data,4,4)==self.target then
            size=0x14; if #data<size then return end
        else return end
        local bytes={}; for i=first,size do bytes[#bytes+1]=('%02X'):format(data:byte(i)) end
        local ok=env.write(('%s 0x%03X payload@%02X %s'):format(direction,id,first-1,table.concat(bytes,' ')));
        self.count=self.count+1;
        if not ok or self.count>=(self.deposit and 24 or 12) then self:stop() end
    end
    return self;
end
return M;
