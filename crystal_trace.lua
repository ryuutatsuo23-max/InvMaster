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
    function self:stop() self.deadline=nil; self.target=nil end
    function self:start()
        self:stop(); self.count=0;
        if not env.write('BEGIN '..(env.label or 'manual crystal withdrawal')..' trace') then return false end
        self.deadline=env.now()+(env.duration or 60); return true;
    end
    function self:observe(direction,id,data)
        if not self.deadline then return end
        if env.now()>=self.deadline or (direction=='in' and (id==0x00A or id==0x00B)) then self:stop(); return end
        local size;
        if direction=='in' and (id==0x032 or id==0x033 or id==0x034) then
            self.target=nil;
            local index=uint(data,id==0x034 and 0x28 or 8,2);
            size=id==0x034 and 0x30 or (id==0x033 and 0x70 or 0x10);
            if not index or #data<size then return end
            local ok,name=pcall(env.name,index);
            if not ok or type(name)~='string' or name:gsub('_',' '):lower()~=npc_name then return end
            self.target=uint(data,4,4);
        elseif direction=='out' and id==0x05B and self.target and uint(data,4,4)==self.target then
            size=0x14; if #data<size then return end
        else return end
        local bytes={}; for i=5,size do bytes[#bytes+1]=('%02X'):format(data:byte(i)) end
        local ok=env.write(('%s 0x%03X payload@04 %s'):format(direction,id,table.concat(bytes,' ')));
        self.count=self.count+1;
        if not ok or self.count>=12 then self:stop() end
    end
    return self;
end
return M;
