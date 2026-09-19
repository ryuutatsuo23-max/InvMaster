-- Saved item-type collections. This module never requests game actions.
local imgui=require 'imgui';
local model=require 'inventory_model';
local M={};
local function clean_name(value)
    if type(value)~='string' then return '' end
    return value:gsub('[%c#]',''):match('^%s*(.-)%s*$'):sub(1,48);
end
local function members(value)
    local result={};
    if type(value)=='table' then
        for id,name in pairs(value) do
            local n=tonumber(id);
            if n and n>=1 and n<=65535 and n==math.floor(n) and type(name)=='string' then
                result[tostring(n)]=name;
            end
        end
    end
    return result;
end
function M.normalize(value)
    value=type(value)=='table' and value or {};
    local result={favorites=members(value.favorites),bags={}};
    for _,bag in ipairs(type(value.bags)=='table' and value.bags or {}) do
        if type(bag)=='table' and clean_name(bag.name)~='' then
            result.bags[#result.bags+1]={name=clean_name(bag.name),items=members(bag.items)};
        end
    end
    return result;
end
function M.rename(data,index,name)
    name=clean_name(name);
    if name=='' then return false,'Enter a bag name.' end
    if name:lower()=='favourites' then return false,'Favourites is reserved.' end
    for i,bag in ipairs(data.bags) do
        if i~=index and bag.name:lower()==name:lower() then return false,'That bag name already exists.' end
    end
    if index then data.bags[index].name=name
    else data.bags[#data.bags+1]={name=name,items={}} end
    return true;
end
function M.rows(snapshot,items,query)
    local owned={};
    for _,group in ipairs(model.ownership(snapshot,'',0)) do owned[tostring(group.id)]=group end
    local rows={};
    for id,name in pairs(items) do
        local g=owned[id];
        local label=g and g.name or name;
        if model.matches({id=id,name=label,full_name=label},query) then
            local locations={};
            if g then for _,v in ipairs(g.locations) do locations[#locations+1]=v.name..': '..v.count end end
            rows[#rows+1]={id=id,name=label,total=g and g.total or 0,locations=table.concat(locations,' | ')};
        end
    end
    table.sort(rows,function(a,b) if a.name~=b.name then return a.name:lower()<b.name:lower() end; return tonumber(a.id)<tonumber(b.id) end);
    return rows;
end
function M.new()
    local self={};
    function self:reset() self.selected=0; self.name={''}; self.search={''}; self.add_search={''}; self.message=nil; self.confirm=false; self.withdraw_id=nil; self.withdraw_quantity={1} end
    self:reset();
    function self:popup(data,item,save)
        local id=tostring(item.id);
        local favorite={data.favorites[id]~=nil};
        if imgui.Checkbox('Favourite item type',favorite) then data.favorites[id]=favorite[1] and item.name or nil; save() end
        imgui.SetNextItemWidth(260);
        if imgui.BeginCombo('Virtual bags','Add / remove membership') then
            if #data.bags==0 then imgui.TextWrapped('Create a virtual bag in Customization first.') end
            for i,bag in ipairs(data.bags) do
                local checked={bag.items[id]~=nil};
                if imgui.Checkbox(bag.name..'##Virtual'..i,checked) then bag.items[id]=checked[1] and item.name or nil; save() end
            end
            imgui.EndCombo();
        end
        imgui.Separator();
    end
    function self:render(snapshot,data,save,withdraw)
        imgui.TextWrapped('Favourites and virtual bags group item types across your real bags. Membership edits do not move items. Right-click an item to withdraw. Saved per character; all copies of an item ID share membership.');
        if not data.bags[self.selected] then self.selected=0 end
        local bag=data.bags[self.selected];
        if imgui.BeginCombo('Collection',bag and bag.name or 'Favourites') then
            if imgui.Selectable('Favourites##Collection',self.selected==0) then self.selected=0; self.confirm=false end
            for i,v in ipairs(data.bags) do
                if imgui.Selectable(v.name..'##Collection'..i,self.selected==i) then self.selected=i; self.name[1]=v.name; self.confirm=false end
            end
            imgui.EndCombo();
        end
        bag=data.bags[self.selected];
        local items=bag and bag.items or data.favorites;
        imgui.SetNextItemWidth(240);
        imgui.InputTextWithHint('##VirtualName','Virtual bag name (e.g. Ore)',self.name,128);
        imgui.SameLine();
        if imgui.Button('Create bag') then
            local ok,reason=M.rename(data,nil,self.name[1]); self.message=reason;
            if ok then self.selected=#data.bags; self.confirm=false; save() end
        end
        if bag then
            imgui.SameLine();
            if imgui.Button('Rename bag') then local ok,reason=M.rename(data,self.selected,self.name[1]); self.message=reason; if ok then save() end end
            if imgui.Button('Delete virtual bag') then self.confirm=true end
            if self.confirm then
                imgui.TextWrapped('Delete this virtual bag and its memberships? Real items remain untouched.');
                if imgui.Button('Confirm deletion') then table.remove(data.bags,self.selected); self.selected=0; self.confirm=false; save() end
                imgui.SameLine(); if imgui.Button('Cancel deletion') then self.confirm=false end
            end
        end
        if self.message then imgui.TextWrapped(self.message) end
        -- Re-resolve after create/delete before presenting or editing memberships.
        bag=data.bags[self.selected]; items=bag and bag.items or data.favorites;
        imgui.Separator();
        imgui.Text('Add to '..(bag and bag.name or 'Favourites'));
        imgui.SetNextItemWidth(-1);
        imgui.InputTextWithHint('##CollectionAdd','Search owned items to add',self.add_search,256);
        if self.add_search[1]:find('%S') then
            if imgui.BeginChild('CollectionCandidates',{0,120}) then
                for _,g in ipairs(model.ownership(snapshot,self.add_search[1],0)) do
                    local id=tostring(g.id);
                    if not items[id] and imgui.Selectable('+ '..g.name..'##AddCollection'..id,false) then items[id]=g.name; save() end
                end
            end
            imgui.EndChild();
        end
        imgui.InputTextWithHint('##CollectionSearch','Search this collection',self.search,256);
        local rows=M.rows(snapshot,items,self.search[1]);
        imgui.Text(('%d item types | Category filters do not hide collection members.'):format(#rows));
        imgui.TextWrapped('Zero means not found in readable bags. Membership stays saved when an item is absent.');
        local open_withdraw=false;
        if imgui.BeginChild('CollectionBody',{0,0}) then
            local _,height=imgui.GetContentRegionAvail();
            if imgui.BeginTable('Collections',4,ImGuiTableFlags_ScrollY,{0,math.max(1,height)}) then
                imgui.TableSetupColumn('Item'); imgui.TableSetupColumn('Total'); imgui.TableSetupColumn('Real locations'); imgui.TableSetupColumn('Membership');
                imgui.TableSetupScrollFreeze(0,1); imgui.TableHeadersRow();
                for _,row in ipairs(rows) do
                    imgui.TableNextRow(); imgui.TableNextColumn();
                    imgui.Selectable(row.name..'##Withdraw'..row.id,false);
                    if withdraw and imgui.IsItemClicked(1) and not withdraw.busy() then
                        self.withdraw_id=tonumber(row.id); self.withdraw_name=row.name; self.withdraw_quantity[1]=1; open_withdraw=true;
                    end
                    imgui.TableNextColumn(); imgui.Text(tostring(row.total));
                    imgui.TableNextColumn(); imgui.TextWrapped(row.locations~='' and row.locations or 'Not in readable bags');
                    imgui.TableNextColumn();
                    if imgui.Button('Remove##Collection'..row.id) then items[row.id]=nil; save() end
                end
                imgui.EndTable();
            end
        end
        imgui.EndChild();
        if open_withdraw then imgui.OpenPopup('Collection withdrawal') end
        imgui.SetNextWindowSize({440,0},ImGuiCond_Always);
        if imgui.BeginPopup('Collection withdrawal') then
            if not withdraw or not self.withdraw_id or withdraw.busy() then imgui.CloseCurrentPopup()
            else
                local total=withdraw.available(self.withdraw_id);
                imgui.TextWrapped(self.withdraw_name..' -> Inventory');
                imgui.TextWrapped(('Available outside Inventory: %d. Requires Inventory space; unavailable or locked sources are excluded.'):format(total));
                if total>0 then
                    imgui.SetNextItemWidth(120);
                    imgui.InputInt('Withdraw quantity',self.withdraw_quantity);
                    self.withdraw_quantity[1]=math.max(1,math.min(total,math.floor(tonumber(self.withdraw_quantity[1]) or 1)));
                    imgui.SameLine(); if imgui.Button('All##Withdraw') then self.withdraw_quantity[1]=total end
                    imgui.TextWrapped('Moves copies of this item ID one stack at a time, including different augments. Stops if space, source identity or access changes.');
                    if imgui.Button('Withdraw to Inventory') then withdraw.start(self.withdraw_id,self.withdraw_quantity[1]); imgui.CloseCurrentPopup() end
                end
                if imgui.Button('Close##Withdraw') then imgui.CloseCurrentPopup() end
            end
            imgui.EndPopup();
        end
    end
    return self;
end
return M;
