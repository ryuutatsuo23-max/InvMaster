-- Read-only NPC discovery. Distances from Ashita are squared yalms.
local M={};
function M.new(env)
    local self={};
    function self:reset() self.key=nil; self.cache={} end
    self:reset();
    local function candidate(index,name)
        local ok,entity=pcall(env.read,index);
        if not ok or not entity then return nil end
        if type(entity.name)~='string' or entity.name:gsub('_',' '):lower()~=name:lower() then return nil end
        local id,d,f=entity.id,entity.distance,entity.flags;
        if type(id)~='number' or id<1 or id>4294967295 or id~=math.floor(id) then return nil end
        if type(d)~='number' or d~=d or d<0 or d>36 then return nil end
        if type(f)~='number' or f~=f or math.floor(f/0x200)%2~=1 or math.floor(f/0x4000)%2~=0 then return nil end
        return {index=index,id=id,distance=d};
    end
    function self:find(name,key,pinned,force)
        if key~=self.key then self:reset(); self.key=key end
        if not key then return nil end
        if pinned then
            if pinned.key~=key then return nil end
            local found=candidate(pinned.index,name);
            return found and found.id==pinned.id and found or nil;
        end
        local cache=self.cache[name];
        if force or not cache or env.now()>=cache.next_scan then
            cache={indices={},next_scan=env.now()+0.5}; self.cache[name]=cache;
            for index=1,0x8FF do
                if candidate(index,name) then cache.indices[#cache.indices+1]=index end
            end
        end
        local best;
        for _,index in ipairs(cache.indices) do
            local found=candidate(index,name);
            if found and (not best or found.distance<best.distance) then best=found end
        end
        return best;
    end
    return self;
end
return M;
