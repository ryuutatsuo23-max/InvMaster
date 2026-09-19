local imgui=require 'imgui';
local model=require 'inventory_model';
local categories=require 'item_categories';
local M={};
local filters={'All items','In multiple bags','Multiple stacks','Equipment copies'};
function M.new()
    local self={};
    function self:reset() self.query={''}; self.filter=0; self.expanded={} end
    self:reset();
    function self:render(snapshot,enabled,save)
        imgui.SetNextItemWidth(-1);
        imgui.InputTextWithHint('##OwnershipSearch','Search item name or ID',self.query,256);
        if imgui.BeginCombo('Show##Ownership',filters[self.filter+1]) then
            for i,label in ipairs(filters) do
                if imgui.Selectable(label..'##OwnershipFilter',self.filter==i-1) then self.filter=i-1 end
            end
            imgui.EndCombo();
        end
        if enabled then categories.render(imgui,enabled,'Ownership',save) end
        local groups=model.ownership(snapshot,self.query[1],self.filter,enabled);
        imgui.Text(('%d item types | Click an item to expand its locations.'):format(#groups));
        imgui.TextWrapped('Totals cover currently readable bags for this character. Equipment copies may have different augments; augments are not decoded.');
        if self.filter==2 then imgui.TextWrapped('Multiple stacks can include full stacks; combining them may not free a slot.') end
        if imgui.BeginChild('OwnershipBody',{0,0}) then
            local _,height=imgui.GetContentRegionAvail();
            if #groups==0 then imgui.TextWrapped('No matches in the available bags.');
            elseif imgui.BeginTable('Ownership',4,ImGuiTableFlags_Resizable+ImGuiTableFlags_Reorderable+ImGuiTableFlags_Sortable+ImGuiTableFlags_ScrollY,{0,math.max(1,height)}) then
                imgui.TableSetupColumn('Item',ImGuiTableColumnFlags_WidthStretch+ImGuiTableColumnFlags_DefaultSort,0,0);
                imgui.TableSetupColumn('Total',ImGuiTableColumnFlags_WidthFixed,50,1);
                imgui.TableSetupColumn('Bags',ImGuiTableColumnFlags_WidthFixed,40,2);
                imgui.TableSetupColumn('Locations / Details',ImGuiTableColumnFlags_WidthStretch,0,3);
                imgui.TableSetupScrollFreeze(0,1); imgui.TableHeadersRow();
                local sort=imgui.TableGetSortSpecs();
                if sort and sort.SpecsCount>0 and sort.Specs then
                    model.sort_ownership(groups,sort.Specs.ColumnUserID,sort.Specs.SortDirection==ImGuiSortDirection_Descending);
                    sort.SpecsDirty=false;
                end
                for _,g in ipairs(groups) do
                    local open=self.expanded[g.id];
                    imgui.TableNextRow(); imgui.TableNextColumn();
                    if imgui.Selectable((open and '[-] ' or '[+] ')..g.name..'##Owned'..g.id,false) then
                        open=not open; self.expanded[g.id]=open;
                    end
                    imgui.TableNextColumn(); imgui.Text(tostring(g.total));
                    imgui.TableNextColumn(); imgui.Text(tostring(#g.locations));
                    imgui.TableNextColumn();
                    local locations={}; for _,v in ipairs(g.locations) do locations[#locations+1]=v.name..': '..v.count end
                    imgui.TextWrapped(table.concat(locations,' | '));
                    if open then
                        for _,row in ipairs(g.rows) do
                            imgui.TableNextRow(); imgui.TableNextColumn(); imgui.Text('  '..row.bag.name);
                            imgui.TableNextColumn(); imgui.Text(tostring(row.item.count));
                            imgui.TableNextColumn(); imgui.Text('');
                            imgui.TableNextColumn();
                            local detail=('Slot %d | ID %d'):format(row.item.slot,g.id);
                            if g.equipment then detail=detail..' | '..(row.variant and ('Data variant '..row.variant) or 'Instance data unavailable') end
                            imgui.TextWrapped(detail);
                        end
                        if g.equipment then
                            imgui.TableNextRow(); imgui.TableNextColumn(); imgui.TextWrapped('Data variants compare raw instance data, not decoded augments or equipment equivalence.');
                        end
                    end
                end
                imgui.EndTable();
            end
        end
        imgui.EndChild();
    end
    return self;
end
return M;
