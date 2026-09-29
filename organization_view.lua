local imgui=require 'imgui';
local model=require 'inventory_model';
local rules=require 'organization';
local categories=require 'item_categories';
local bags=require('transfer').bags;
local M={};
local function destination(label,current,inherit)
    local value=current;
    local preview=current==-1 and 'Leave where it is' or bags[current] or inherit;
    if imgui.BeginCombo(label,preview) then
        if imgui.Selectable(inherit..'##'..label,current==nil) then value=nil end
        if imgui.Selectable('Leave where it is##'..label,current==-1) then value=-1 end
        for id=1,16 do
            if bags[id] and imgui.Selectable(bags[id]..'##'..label,current==id) then value=id end
        end
        imgui.EndCombo();
    end
    return value;
end
function M.new()
    local self={};
    function self:reset(data)
        self.search={''}; self.id=nil; self.draft=nil; self.preview=nil; self.category=categories.options[1][1]; self.category_dest=nil;
        if data then self.category_dest=data.categories[self.category] end
    end
    self:reset();
    function self:invalidate() self.preview=nil end
    local function edit(id,name,data)
        local rule=data.items[tostring(id)] or {};
        self.id=id; self.name=name; self.draft={keep={rule.keep or 0},use_keep={rule.keep~=nil},protected={rule.protected==true},destination=rule.destination};
    end
    function self:render(snapshot,data,save,env)
        local access={}; for id=0,16 do access[#access+1]=tostring(env.access[id]==true) end
        local access_key=table.concat(access,':');
        if self.access_key~=access_key or not env.ready then self:invalidate() end
        self.access_key=access_key;
        imgui.TextWrapped('Review a plan, then explicitly run it. Rules are saved per character and apply to all copies of an item ID, including different augments.');
        if not imgui.BeginTabBar('OrganizationTabs') then return end
        if imgui.BeginTabItem('Item rules') then
        imgui.SetNextItemWidth(-1);
        imgui.InputTextWithHint('##OrganizationSearch','Find an owned item or saved rule',self.search,256);
        local candidates={};
        for _,g in ipairs(model.ownership(snapshot,'',0)) do candidates[g.id]=g.name end
        for id,r in pairs(data.items) do candidates[tonumber(id)]=r.name end
        local ids={}; for id in pairs(candidates) do ids[#ids+1]=id end; table.sort(ids);
        local _,available_height=imgui.GetContentRegionAvail();
        local editor_height=imgui.GetFrameHeightWithSpacing()*9+imgui.GetTextLineHeightWithSpacing()*4;
        local list_height=self.draft and math.max(80,available_height-math.min(editor_height,available_height*0.65)) or math.max(80,available_height);
        if imgui.BeginChild('OrganizationItems',{0,list_height}) then
            for _,id in ipairs(ids) do
                local name=candidates[id];
                if (name..' '..id):lower():find(self.search[1]:lower(),1,true) then
                    local start_x=imgui.GetCursorPosX();
                    if imgui.Selectable(name..'##OrgItem'..id,self.id==id) then edit(id,name,data) end
                    if data.items[tostring(id)] then
                        local width=imgui.CalcTextSize(name);
                        imgui.SameLine(start_x+width+8);
                        imgui.TextColored({0.35,1.0,0.45,1.0},'[rule]');
                    end
                end
            end
        end
        imgui.EndChild();
        if self.draft then
            if imgui.BeginChild('OrganizationEditor',{0,0}) then
            local d=self.draft;
            imgui.Text('Item rule: '..self.name);
            imgui.Checkbox('Leave this item untouched##Org',d.protected);
            imgui.Checkbox('Keep a quantity in Inventory##Org',d.use_keep);
            if d.use_keep[1] then
                imgui.SetNextItemWidth(120);
                imgui.InputInt('Keep quantity##Org',d.keep);
                local n=tonumber(d.keep[1]); if not n or n~=n or n==math.huge or n==-math.huge then n=0 end
                d.keep[1]=math.max(0,math.min(7992,math.floor(n)));
            end
            d.destination=destination('Extra items go to##Org',d.destination,'Use category rule');
            imgui.TextWrapped('Untouched takes priority over all organization rules. Keep targets refill from storage; only extras use the storage destination. These protections do not block your manual moves.');
            if imgui.Button('Apply item rule') then
                data.items[tostring(self.id)]={name=self.name,keep=d.use_keep[1] and d.keep[1] or nil,destination=d.destination,protected=d.protected[1]};
                self:invalidate(); save();
            end
            imgui.SameLine();
            if imgui.Button('Remove item rule') then data.items[tostring(self.id)]=nil; edit(self.id,self.name,data); self:invalidate(); save() end
            end
            imgui.EndChild();
        end
        imgui.EndTabItem();
        end
        if imgui.BeginTabItem('Category rules') then
        local category_label=self.category;
        for _,option in ipairs(categories.options) do if option[1]==self.category then category_label=option[2] end end
        if imgui.BeginCombo('Category##Org',category_label) then
            for _,option in ipairs(categories.options) do
                if imgui.Selectable(option[2]..'##OrgCategory',self.category==option[1]) then self.category=option[1]; self.category_dest=data.categories[self.category] end
            end
            imgui.EndCombo();
        end
        self.category_dest=destination('Category storage##Org',self.category_dest,'No category rule');
        if imgui.Button('Apply category rule') then data.categories[self.category]=self.category_dest; self:invalidate(); save() end
        imgui.TextWrapped('Item destinations override category destinations. No rules are enabled by default.');
        imgui.EndTabItem();
        end
        if imgui.BeginTabItem('Preview') then
        if imgui.Button('View organization plan') then self.preview=rules.plan(snapshot,data,env); self.stack_after={false} end
        if self.preview then
            local p=self.preview;
            imgui.Text(('%d proposed moves | %d notices | %d protected item types'):format(#p.moves,#p.blocked,p.protected));
            imgui.TextWrapped('Only the listed moves will run. Notices are skipped. Stop prevents further sends; a sent move still needs confirmation. No retries.');
            local steps=0; for _,move in ipairs(p.moves) do steps=steps+(move.via_inventory and 2 or 1) end
            imgui.Text(('%d / 50 transfer steps (routes via Inventory use two).'):format(steps));
            if #p.moves>0 then
                imgui.Checkbox('Stack destination bags after this run',self.stack_after);
                if self.stack_after[1] then
                    imgui.TextWrapped('After all moves finish, combine partial stacks in destination bags, one bag at a time. Bags containing untouched items are skipped. Stop cancels remaining stacking.');
                end
            end
            if steps>50 then imgui.TextWrapped('Narrow your rules to at most 50 transfer steps and preview again.')
            elseif #p.moves>0 and env.ready and env.run and imgui.Button('Run organization') then env.run(p,self.stack_after[1]) end
            if #p.moves==0 and #p.blocked==0 then imgui.Text('No moves proposed under the saved rules.') end
            if imgui.BeginChild('OrganizationPlan',{0,0}) then
                for _,move in ipairs(p.moves) do
                    imgui.TextWrapped(('%d x %s: %s (slot %d) -> %s%s'):format(move.count,move.name,bags[move.source],move.slot,bags[move.destination],move.via_inventory and ' via Inventory' or ''));
                end
                for _,reason in ipairs(p.blocked) do
                    imgui.TextColored({1.0,0.35,0.35,1.0},'Notice:');
                    imgui.SameLine();
                    imgui.TextWrapped(reason);
                end
            end
            imgui.EndChild();
        end
        imgui.EndTabItem();
        end
        imgui.EndTabBar();
    end
    return self;
end
return M;
