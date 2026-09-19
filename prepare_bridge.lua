-- Bounded CraftMaster requests use the existing InvMaster transfer validator.
local transfer=require 'transfer';
local withdraw=require 'withdraw';
local M={};
function M.parse(text)
    if type(text)~='string' or #text>400 then return nil end
    local token,key,expires,list=text:match('^(%d+%-%d+%-%d+) ([%w_:]+) (%d+) ([%d=,]+)$');
    if not token then return nil end
    local targets,seen={},{};
    for entry in (list..','):gmatch('(.-),') do
        local id,n=entry:match('^(%d+)=(%d+)$'); id,n=tonumber(id),tonumber(n);
        if not id or not n or id<1 or id>65534 or n<1 or n>7992 or seen[id] then return nil end
        seen[id]=true; targets[#targets+1]={id=id,count=n};
    end
    if #targets<1 or #targets>9 then return nil end
    return {token=token,key=key,expires=tonumber(expires),targets=targets};
end
local function total(data,id)
    local bag=data and data[1]; if not bag or bag.state~='Client snapshot' then return nil end
    local n=0; for _,item in ipairs(bag.items) do if item.id==id then n=n+item.count end end; return n;
end
function M.new(env)
    local self={active=nil,message=nil}; local confirmed=false; local seen={};
    local leg_env={}; for k,v in pairs(env) do leg_env[k]=v end
    leg_env.changed=function() confirmed=true; env.changed() end;
    local leg=transfer.new(leg_env);
    function self:busy() return self.active~=nil or leg.pending~=nil end
    local function reply(p,code) env.reply(p.token,code) end
    function self:cancel(token)
        local p=self.active;
        if p and (not token or p.token==token) then
            p.cancelled=true; self.message='Preparation stopped; any sent move will still be checked.';
        end
    end
    function self:request(text)
        local p=M.parse(text); if not p then return end
        if seen[p.token] then return end
        seen[p.token]=p.expires;
        if p.expires<=env.wall() or p.expires>env.wall()+60 or env.context()~=p.key then reply(p,'context'); return end
        if self:busy() or env.busy() then reply(p,'busy'); return end
        local ok,data=pcall(env.scan); if not ok or not data then reply(p,'read'); return end
        local moves=0;
        for _,target in ipairs(p.targets) do
            local have=total(data,target.id); if not have then reply(p,'read'); return end
            local left=math.max(0,target.count-have);
            if left>0 then
                local rows,available=withdraw.sources(data,target.id,env);
                if available<left then reply(p,'materials'); return end
                for _,row in ipairs(rows) do
                    if left<=0 then break end
                    moves=moves+1; left=left-math.min(left,row.count);
                end
            end
        end
        -- Conservative reservation: each source stack can occupy a new slot.
        if data[1].free<moves+1 then reply(p,'space'); return end
        self.active=p; p.index=1; self.message='Preparing CraftMaster materials.'; reply(p,'accepted');
    end
    function self:tick()
        for token,expires in pairs(seen) do if env.wall()>expires+120 then seen[token]=nil end end
        local p=self.active;
        if p and (env.wall()>=p.expires or env.context()~=p.key) then p.cancelled=true end
        if leg.pending then
            confirmed=false; leg:tick();
            if leg.pending then
                if p and env.now()>=leg.pending.deadline then
                    self.message=leg.message; reply(p,'uncertain'); self.active=nil;
                end
                return;
            end
            if p and not confirmed then p.cancelled=true end
        end
        if not p then return end
        if p.cancelled then reply(p,'stopped'); self.active=nil; return end
        if env.busy() then reply(p,'busy'); self.active=nil; return end
        local ok,data=pcall(env.scan);
        if not ok or not data then reply(p,'read'); self.active=nil; return end
        for _,target in ipairs(p.targets) do
            local have=total(data,target.id);
            if not have then reply(p,'read'); self.active=nil; return end
            if have<target.count then
                if data[1].free<2 then reply(p,'space'); self.active=nil; return end
                local rows=withdraw.sources(data,target.id,env);
                local row=rows[1];
                if not row then reply(p,'materials'); self.active=nil; return end
                if not leg:start(row,0,math.min(row.count,target.count-have)) then
                    self.message=leg.message; reply(p,'transfer'); self.active=nil;
                end
                return;
            end
        end
        self.message='CraftMaster materials are ready in Inventory.'; reply(p,'done'); self.active=nil;
    end
    return self;
end
return M;
