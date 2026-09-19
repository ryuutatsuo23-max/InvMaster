addon.name = 'invmaster';
addon.author = 'DragoHorse';
addon.version = '0.14.0';
addon.desc = 'Item search, storage overview and individual transfers.';
require 'common';
local imgui = require 'imgui';
local settings = require 'settings';
local model = require 'inventory_model';
local bag_monitor = require 'bag_monitor';
local categories = require 'item_categories';
local transfers = require 'transfer';
local bag_access = require('bag_access').new();
local ownership_view = require('ownership_view').new();
local customization = require('customization');
local custom_view = customization.new();
local crystal_trace=require('crystal_trace').new({
    now=os.clock,
    name=function(index) return AshitaCore:GetMemoryManager():GetEntity():GetName(index) end,
    write=function(line)
        local file=io.open(addon.path..'crystal-menu-trace.log','a');
        if not file then return false end
        file:write(os.date('%Y-%m-%d %H:%M:%S')..' '..line..'\n'); file:close(); return true;
    end,
});
local shami_trace=require('crystal_trace').new({
    npc_name='shami',label='manual Shami menu',duration=120,
    now=os.clock,
    name=function(index) return AshitaCore:GetMemoryManager():GetEntity():GetName(index) end,
    write=function(line)
        local file=io.open(addon.path..'shami-menu-trace.log','a');
        if not file then return false end
        file:write(os.date('%Y-%m-%d %H:%M:%S')..' '..line..'\n'); file:close(); return true;
    end,
});
local nearby_npc=require('nearby_npc').new({now=os.clock,read=function(index)
    local entity=AshitaCore:GetMemoryManager():GetEntity();
    local name=entity:GetName(index);
    if name~='Shami' and name~='Ephemeral Moogle' and name~='Ephemeral_Moogle' then return nil end
    return {name=name,id=entity:GetServerId(index),distance=entity:GetDistance(index),flags=entity:GetRenderFlags0(index)};
end});
local currency=require 'currency';
local currency_data;
local currency_refresh_message,currency_refresh_deadline;
local currency_next_request=0;
local currency_refresh_due=false;
local crystal_withdrawer;
local shami_controller;
local withdraw_module=require 'withdraw';
local withdrawer;
local mover,sorter,sort_request;
local preparer;
local function other_busy() return (shami_controller and shami_controller.pending) or (crystal_withdrawer and crystal_withdrawer.pending) or (withdrawer and (withdrawer.active or withdrawer.pending)) or (mover and mover.pending) or (sorter and sorter.pending) or sort_request~=nil end
local function busy() return other_busy() or (preparer and preparer:busy()) end
local choice, destination;
local quantity={1};
local window, query = {false}, {''};
local focus_items=false;
local profile, profile_name, profile_id;
local selected, snapshot, last_read, next_read;
local context_key;
local status = 'Waiting for character data.';
local function reset()
    if preparer then preparer:cancel() end
    snapshot, last_read, selected, context_key = nil, nil, nil, nil;
    next_read = 0;
    choice, destination=nil, nil; quantity[1]=1;
    if mover then mover:reset() end
    if sorter then sorter:reset() end
    sort_request=nil;
    currency_data=profile and currency.restore(profile.currency_cache,profile_name,profile_id) or nil;
    currency_refresh_due=false;
    currency_refresh_message,currency_refresh_deadline=nil,nil; currency_next_request=0;
    crystal_trace:stop();
    shami_trace:stop();
    if crystal_withdrawer then crystal_withdrawer:reset() end
    if shami_controller then shami_controller:reset() end
    currency.reset();
    nearby_npc:reset();
    if withdrawer then withdrawer:reset() end
end
local function refresh_interval(value)
    if type(value) ~= 'number' or value ~= value or value == math.huge or value == -math.huge then return 2 end
    return math.max(1, math.min(60, math.floor(value)));
end
local function apply_profile(data)
    bag_access:reset();
    ownership_view:reset();
    custom_view:reset();
    profile = data; profile_name, profile_id = settings.name, settings.server_id;
    if type(data.hide_unavailable) ~= 'boolean' then data.hide_unavailable=true end
    if type(data.auto_stack) ~= 'boolean' then data.auto_stack=false end
    data.refresh_seconds=refresh_interval(data.refresh_seconds);
    data.categories=categories.normalize(data.categories);
    data.monitor=bag_monitor.normalize(data.monitor);
    data.customization=customization.normalize(data.customization);
    window[1]=false; query[1]=''; reset();
end
local function ready()
    local player=GetPlayerEntity();
    return profile and settings.logged_in and player and player.Name == profile_name and player.ServerId == profile_id
        and settings.name == profile_name and settings.server_id == profile_id;
end
local function transfer_context()
    if not ready() then return nil, 'Wait for your character profile.' end
    local mm=AshitaCore:GetMemoryManager();
    if mm:GetPlayer():GetIsZoning() ~= 0 then return nil, 'Wait until zoning is finished.' end
    local index=mm:GetParty():GetMemberTargetIndex(0);
    local hp=index and index~=0 and mm:GetEntity():GetHPPercent(index) or nil;
    if not index or index==0 or mm:GetEntity():GetStatus(index)~=0 or type(hp)~='number' or not (hp>0 and hp<=100) then
        return nil, 'Transfers require an idle, living character.';
    end
    return profile_name .. ':' .. profile_id .. ':' .. mm:GetParty():GetMemberZone(0);
end
local function crystal_key()
    if not ready() then return nil end
    local mm=AshitaCore:GetMemoryManager();
    if mm:GetPlayer():GetIsZoning()~=0 then return nil end
    return profile_name..':'..profile_id..':'..mm:GetParty():GetMemberZone(0);
end
local currency_refresh={
    request=function()
        if not crystal_key() then currency_refresh_message='Wait until your character is ready and zoning has finished.'; return end
        if os.clock()<currency_next_request then return end
        currency_next_request=os.clock()+5; currency_refresh_deadline=os.clock()+10;
        currency_refresh_message='Requesting fresh stored balances...';
        local ok,result=pcall(function() return AshitaCore:GetPacketManager():AddOutgoingPacket(0x10F,{0,0,0,0}) end);
        if not ok or result==false then currency_refresh_message='Refresh request outcome unknown. No retry sent.' end
    end,
    status=function()
        if currency_refresh_deadline and os.clock()>=currency_refresh_deadline then
            currency_refresh_message='No fresh balances received yet. You can press Refresh balances again.';
            currency_refresh_deadline=nil;
        end
        return currency_refresh_message;
    end,
};
local function crystal_target(idle,npc_name,pinned,force)
    npc_name=npc_name or 'Ephemeral Moogle';
    local ok,npc,reason=pcall(function()
        local key=crystal_key(); if not key then return nil,'Wait for your character and zone.' end
        if idle and not transfer_context() then return nil,'Finish your current action or NPC conversation first.' end
        local found=nearby_npc:find(npc_name,key,pinned,force);
        if not found then return nil,npc_name..' not available within 6 yalms.' end
        found.key=key; found.zone=AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0);
        return found;
    end);
    if not ok then return nil,'NPC data unavailable.' end
    return npc,reason;
end
crystal_withdrawer=require('crystal_withdraw').new({
    now=os.clock,key=crystal_key,target=function(idle,pinned) return crystal_target(idle,'Ephemeral Moogle',pinned,idle) end,
    inventory=function()
        local ok,data=pcall(model.scan,AshitaCore:GetMemoryManager():GetInventory(),AshitaCore:GetResourceManager());
        return ok and data and data[1] or nil;
    end,
    send=function(id,packet) return AshitaCore:GetPacketManager():AddOutgoingPacket(id,packet) end,
    changed=function() next_read=0; currency_refresh_due=true end,
});
local crystal_ui={busy=busy,target=crystal_target,
    start=function(element,count) if not busy() then crystal_withdrawer:start(element,count) end end};
local function shami_target(idle,pinned,force) return crystal_target(idle,'Shami',pinned,force) end
shami_controller=require('shami').new({
    now=os.clock,key=crystal_key,target=function(idle,pinned) return shami_target(idle,pinned,idle) end,
    scan=function()
        local ok,data=pcall(model.scan,AshitaCore:GetMemoryManager():GetInventory(),AshitaCore:GetResourceManager());
        return ok and data or nil;
    end,
    send=function(id,packet) return AshitaCore:GetPacketManager():AddOutgoingPacket(id,packet) end,
    changed=function() next_read=0; currency_refresh_due=true end,
});
local shami_ui={busy=busy,target=shami_target,
    start=function(mode,index,count) if not busy() then shami_controller:start(mode,index,count) end end};
local function current_access()
    local key=transfer_context();
    if not key then return {} end
    local ok,capacity=pcall(function() return AshitaCore:GetMemoryManager():GetInventory():GetContainerCountMax(5) end);
    return bag_access:allowed(key,ok and capacity or nil);
end
local function equipped(bag,slot)
    local inv=AshitaCore:GetMemoryManager():GetInventory();
    for index=0,15 do
        local entry=inv:GetEquippedItem(index);
        if not entry or type(entry.Index)~='number' or entry.Index~=entry.Index or entry.Index<0 or entry.Index>65535 or entry.Index~=math.floor(entry.Index) then error('Equipment data unavailable') end
        if math.floor(entry.Index/256)==bag and entry.Index%256==slot then return true end
    end
    return false;
end
mover=require('route_transfer').new({
    now=os.clock, context=transfer_context,
    scan=function() return model.scan(AshitaCore:GetMemoryManager():GetInventory(), AshitaCore:GetResourceManager()); end,
    equipped=equipped,
    access=current_access,
    send=function(packet) return AshitaCore:GetPacketManager():AddOutgoingPacket(0x029,packet); end,
    changed=function() next_read=0; choice=nil; destination=nil; end,
    completed=function(bag) if profile.auto_stack then sort_request=bag end end,
});
sorter=require('stack_sort').new({
    now=os.clock,context=transfer_context,access=current_access,
    scan=function() return model.scan(AshitaCore:GetMemoryManager():GetInventory(),AshitaCore:GetResourceManager()); end,
    send=function(packet) return AshitaCore:GetPacketManager():AddOutgoingPacket(0x03A,packet); end,
    changed=function() next_read=0; choice=nil; destination=nil; end,
});
local withdraw_env={
    now=os.clock,context=transfer_context,access=current_access,equipped=equipped,
    scan=function() return model.scan(AshitaCore:GetMemoryManager():GetInventory(),AshitaCore:GetResourceManager()); end,
    send=function(packet) return AshitaCore:GetPacketManager():AddOutgoingPacket(0x029,packet); end,
    changed=function() next_read=0; choice=nil; destination=nil end,
};
withdrawer=withdraw_module.new(withdraw_env);
local prepare_env={}; for k,v in pairs(withdraw_env) do prepare_env[k]=v end
prepare_env.wall=os.time; prepare_env.busy=other_busy;
prepare_env.reply=function(token,code)
    AshitaCore:GetChatManager():QueueCommand(-1,'/cm prepare_result '..token..' '..code);
end;
preparer=require('prepare_bridge').new(prepare_env);
local withdraw_ui={
    available=function(id) local _,total=withdraw_module.sources(snapshot,id,withdraw_env); return total end,
    busy=busy,
    start=function(id,count) if not busy() then withdrawer:start(id,count) end end,
};
local function select_item(row)
    choice={bag=row.bag.id};
    for key,value in pairs(row.item) do choice[key]=value end
    quantity[1]=1;
    destination=row.bag.id==0 and 6 or 0;
    mover.message=nil;
end
local function render_transfer()
    if not choice then
        imgui.TextWrapped('Select an item name to move it to/from Inventory.');
        return;
    end
    imgui.TextWrapped(('Selected: %s | %s, slot %d'):format(choice.name,model.containers[choice.bag+1],choice.slot));
    if not transfers.bags[choice.bag] then
        imgui.TextWrapped('Transfers for this container are not available yet.');
        if imgui.Button('Clear selection') then choice=nil; imgui.CloseCurrentPopup() end
        return;
    end
    if busy() then return end
    local access=current_access();
    local options={}; local selected_available=false;
    for id=0,16 do
        if transfers.plan_route(snapshot,choice,id,access) then
            options[#options+1]=id;
            if destination==id then selected_available=true end
        end
    end
    if not selected_available then destination=nil end
    if #options==0 then
        local key,reason=transfer_context();
        if not key then imgui.TextWrapped(reason);
        elseif access[choice.bag]~=true then
            imgui.TextWrapped(model.containers[choice.bag+1] .. ' source access is not confirmed.');
            imgui.TextWrapped(bag_access:reason(key,choice.bag));
        elseif choice.bag~=0 then
            local _,problem=transfers.route(snapshot,choice,0,access);
            imgui.TextWrapped('Cannot move to Inventory: ' .. (problem or 'No eligible route.'));
        else
            imgui.TextWrapped('No accessible destination with free space for this item.');
        end
        if imgui.Button('Clear selection') then choice=nil; imgui.CloseCurrentPopup() end
        return;
    end
    imgui.SetNextItemWidth(260);
    if imgui.BeginCombo('Move to', transfers.bags[destination] or 'Choose container') then
        for _, id in ipairs(options) do
            if imgui.Selectable(transfers.bags[id], destination==id) then destination=id end
        end
        imgui.EndCombo();
    end
    imgui.SetNextItemWidth(120);
    if imgui.InputInt('Quantity', quantity) then quantity[1]=math.max(1,math.min(choice.count,quantity[1])) end
    imgui.SameLine();
    if imgui.Button('All') then quantity[1]=choice.count end
    if choice.bag~=0 and destination and destination~=0 then
        imgui.TextWrapped('Route: '..model.containers[choice.bag+1]..' -> Inventory -> '..model.containers[destination+1]);
    end
    if imgui.Button('Move item') then
        if mover:start(choice,destination,quantity[1]) then imgui.CloseCurrentPopup() end;
    end
    imgui.SameLine();
    if not busy() and imgui.Button('Clear selection') then choice=nil; imgui.CloseCurrentPopup() end
end
local function poll()
    if not ready() then reset(); status='Waiting for a matching character profile.'; return end
    local mm=AshitaCore:GetMemoryManager();
    if mm:GetPlayer():GetIsZoning() ~= 0 then reset(); status='Zoning; inventory data is unavailable.'; return end
    local key=profile_name .. ':' .. profile_id .. ':' .. mm:GetParty():GetMemberZone(0);
    if key ~= context_key then
        reset(); context_key=key; next_read=os.clock()+3;
        status='Waiting for inventory data after login or zoning.';
    end
    if os.clock() < next_read then return end
    next_read=os.clock()+profile.refresh_seconds;
    local data, reason=model.scan(mm:GetInventory(), AshitaCore:GetResourceManager());
    snapshot=data;
    if data then
        last_read=os.clock();
        local available=0; for _, bag in ipairs(data) do if bag.state == 'Client snapshot' then available=available+1 end end
        status=('%d / %d containers read'):format(available, #model.containers);
    else last_read=nil; status=reason; end
end
local function render_items()
    imgui.SetNextItemWidth(-1);
    imgui.InputTextWithHint('##search', 'Search item name or ID (e.g. knuckles)', query, 256);
    local preview=selected ~= nil and model.containers[selected+1] or 'All containers';
    if imgui.BeginCombo('Location', preview) then
        if imgui.Selectable('All containers', selected == nil) then selected=nil end
        for _, bag in ipairs(snapshot or {}) do
            if bag.state == 'Client snapshot' and imgui.Selectable(bag.name, selected == bag.id) then selected=bag.id end
        end
        imgui.EndCombo();
    end
    categories.render(imgui,profile.categories,'Items',settings.save);
    local rows, count=model.search(snapshot, query[1], selected,profile.categories);
    imgui.Text(('%d matching slots | %d items'):format(#rows, count));
    imgui.TextWrapped('Right-click an item for transfer and Stack bag options.');
    local open_actions=false;
    if imgui.BeginChild('ItemsBody', {0,0}) then
        local _, height=imgui.GetContentRegionAvail();
        if #rows == 0 then
            imgui.TextWrapped('No matches in the available client snapshot. This does not confirm that you do not own the item.');
        elseif imgui.BeginTable('Items', 4, ImGuiTableFlags_Resizable + ImGuiTableFlags_Reorderable + ImGuiTableFlags_Sortable + ImGuiTableFlags_ScrollY, {0,math.max(1,height)}) then
            imgui.TableSetupColumn('Item', ImGuiTableColumnFlags_WidthStretch + ImGuiTableColumnFlags_DefaultSort, 0, 0);
            imgui.TableSetupColumn('Location', ImGuiTableColumnFlags_WidthFixed, 100, 1);
            imgui.TableSetupColumn('Qty', ImGuiTableColumnFlags_WidthFixed, 40, 2);
            imgui.TableSetupColumn('Slot', ImGuiTableColumnFlags_WidthFixed, 40, 3);
            imgui.TableSetupScrollFreeze(0,1);
            imgui.TableHeadersRow();
            local sorting=imgui.TableGetSortSpecs();
            if sorting and sorting.SpecsCount > 0 and sorting.Specs then
                model.sort(rows, sorting.Specs.ColumnUserID, sorting.Specs.SortDirection == ImGuiSortDirection_Descending);
                sorting.SpecsDirty=false;
            end
            for _, row in ipairs(rows) do
                imgui.TableNextRow(); imgui.TableNextColumn();
                local label=row.item.name .. '##' .. row.bag.id .. '_' .. row.item.slot;
                imgui.Selectable(label, choice~=nil and choice.bag==row.bag.id and choice.slot==row.item.slot);
                if imgui.IsItemClicked(1) and not busy() then
                    select_item(row); open_actions=true;
                end
                imgui.TableNextColumn(); imgui.Text(row.bag.name);
                imgui.TableNextColumn(); imgui.Text(tostring(row.item.count));
                imgui.TableNextColumn(); imgui.Text(tostring(row.item.slot));
            end
            imgui.EndTable();
        end
    end
    imgui.EndChild();
    -- Open and render at the same ID scope, outside the scrolling table.
    if open_actions then imgui.OpenPopup('Item actions') end
    -- Wrapped text and default widget widths otherwise feed back into popup auto-sizing.
    imgui.SetNextWindowSize({440,0},ImGuiCond_Always);
    if imgui.BeginPopup('Item actions') then
        if not choice or busy() then imgui.CloseCurrentPopup();
        else
            custom_view:popup(profile.customization,choice,settings.save);
            if current_access()[choice.bag] and transfers.bags[choice.bag] then
                if imgui.Button('Stack bag') then
                    sort_request=choice.bag; choice=nil; destination=nil; imgui.CloseCurrentPopup();
                end
            end
            if choice then render_transfer() end
        end
        imgui.EndPopup();
    end
end
local function render_storage()
    if imgui.BeginChild('StorageBody', {0,0}) then
        local _, height=imgui.GetContentRegionAvail();
        if imgui.BeginTable('Storage', 3, ImGuiTableFlags_ScrollY, {0,math.max(1,height)}) then
            imgui.TableSetupColumn('Container'); imgui.TableSetupColumn('Slots'); imgui.TableSetupColumn('Free / Status');
            imgui.TableSetupScrollFreeze(0,1);
            imgui.TableHeadersRow();
            for _, bag in ipairs(snapshot or {}) do
                if not profile.hide_unavailable or bag.state ~= 'Unavailable' then
                    imgui.TableNextRow(); imgui.TableNextColumn(); imgui.Text(bag.name);
                    imgui.TableNextColumn();
                    imgui.Text(bag.capacity and ('%d / %d'):format(bag.used, bag.capacity) or '--');
                    imgui.TableNextColumn(); imgui.Text(bag.free and tostring(bag.free) or bag.state);
                end
            end
            imgui.EndTable();
        end
    end
    imgui.EndChild();
end
local function render()
    if not window[1] then return end
    imgui.SetNextWindowSize({960,600}, ImGuiCond_FirstUseEver);
    if imgui.Begin('InvMaster###FindMyStuff', window) then
        imgui.TextWrapped((ready() and profile_name or 'No character') .. ' | ' .. status);
        if ready() then
            for _, state in ipairs({'Unavailable', 'Updating', 'Read error'}) do
                local names={};
                for _, bag in ipairs(snapshot or {}) do
                    if bag.state == state then names[#names+1]=bag.name end
                end
                if #names > 0 then imgui.TextWrapped(state .. ': ' .. table.concat(names, ', ')); end
            end
            if imgui.Button('Refresh') then next_read=0 end
            imgui.SameLine(); imgui.TextWrapped(('Auto-refresh: %ds | '):format(profile.refresh_seconds) .. (last_read and ('Last read: %ds ago'):format(math.max(0,math.floor(os.clock()-last_read))) or 'No snapshot'));
            imgui.TextWrapped('Transfers between accessible bags; storage-to-storage moves go via Inventory.');
            if mover.message then imgui.TextWrapped(mover.message); end
            if shami_controller.message then imgui.TextWrapped(shami_controller.message) end
            if crystal_withdrawer.message then imgui.TextWrapped(crystal_withdrawer.message) end
            if withdrawer.message then imgui.TextWrapped(withdrawer.message) end
            if preparer.message then imgui.TextWrapped(preparer.message) end
            if preparer.active and imgui.Button('Stop preparation') then preparer:cancel() end
            if withdrawer.active and imgui.Button('Stop withdrawal') then withdrawer:cancel() end
            if sorter.message then imgui.TextWrapped(sorter.message); end
            if imgui.BeginTabBar('MainTabs') then
                if imgui.BeginTabItem('Items',nil,focus_items and ImGuiTabItemFlags_SetSelected or 0) then focus_items=false; render_items(); imgui.EndTabItem(); end
                if imgui.BeginTabItem('Ownership') then ownership_view:render(snapshot,profile.categories,settings.save); imgui.EndTabItem(); end
                if imgui.BeginTabItem('Customization') then custom_view:render(snapshot,profile.customization,settings.save,withdraw_ui); imgui.EndTabItem(); end
                if imgui.BeginTabItem('Currency') then currency.render(currency_data,crystal_ui,shami_ui,currency_refresh); imgui.EndTabItem(); end
                if imgui.BeginTabItem('Storage') then render_storage(); imgui.EndTabItem(); end
                if imgui.BeginTabItem('Settings') then
                    local seconds={profile.refresh_seconds};
                    imgui.SetNextItemWidth(120);
                    if imgui.InputInt('Auto-refresh interval (seconds)', seconds) then
                        profile.refresh_seconds=refresh_interval(seconds[1]);
                        next_read=os.clock()+profile.refresh_seconds;
                        settings.save();
                    end
                    imgui.TextWrapped('1-60 seconds. Refresh reads immediately without changing this interval.');
                    local hide={profile.hide_unavailable};
                    if imgui.Checkbox('Hide unavailable containers', hide) then profile.hide_unavailable=hide[1]; settings.save(); end
                    local auto={profile.auto_stack};
                    if imgui.Checkbox('Auto-stack destination after transfers',auto) then profile.auto_stack=auto[1]; settings.save(); end
                    imgui.TextWrapped('Unavailable may mean locked, unsupported, or not loaded. Disable this option to see every container.');
                    bag_monitor.settings(profile.monitor,settings.save);
                    imgui.Separator(); imgui.Text('InvMaster ' .. addon.version .. ' | DragoHorse');
                    imgui.TextWrapped('/im - toggle window. /im find <name> - search. /im refresh - request a fresh snapshot. /im status - access diagnostics.');
                    imgui.TextWrapped('Storage-to-storage transfers use Inventory as an intermediate step. If the second step cannot proceed, items remain in Inventory. Stack bag combines partial stacks using the game sort request. No automatic retries.');
                    imgui.TextWrapped('Satchel, Sack and Case work without Mog House entry. Enter your Mog House after loading to learn home-storage access. Wardrobes accept equipment only. Temporary, Recycle and Nomad Moogle access are not supported.');
                    imgui.TextWrapped('Slot rows stay separate, including items with the same name. Augments are not decoded in this version. NPC storage, delivery boxes and storage-slip contents are not included.');
                    imgui.EndTabItem();
                end
                imgui.EndTabBar();
            end
        end
    end
    imgui.End();
end
apply_profile(settings.load(T{hide_unavailable=true, refresh_seconds=2, auto_stack=false}));
settings.register('settings', 'invmaster_profile', apply_profile);
ashita.events.register('packet_in', 'invmaster_access', function(e)
    if e.injected or e.blocked then return end
    crystal_trace:observe('in',e.id,e.data);
    shami_trace:observe('in',e.id,e.data);
    crystal_withdrawer:observe(e);
    shami_controller:observe(e);
    -- Saved balances survive zoning; they remain labelled as last known.
    if e.id==0x113 and ready() and AshitaCore:GetMemoryManager():GetPlayer():GetIsZoning()==0 then
        local decoded=currency.decode(e.data);
        if decoded then
            decoded.time=os.time(); decoded.owner_name=profile_name; decoded.owner_id=profile_id;
            profile.currency_cache=currency.restore(decoded,profile_name,profile_id);
            currency_data=currency.restore(profile.currency_cache,profile_name,profile_id);
            currency_refresh_deadline=nil; currency_refresh_message=nil;
            settings.save();
        end
    end
    bag_access:observe(e.id,e.data);
end);
ashita.events.register('packet_out','invmaster_crystal_trace',function(e)
    if e.id==0x096 then preparer:cancel() end
    if not e.injected and not e.blocked then crystal_trace:observe('out',e.id,e.data) end
    if not e.injected and not e.blocked then shami_trace:observe('out',e.id,e.data) end
    crystal_withdrawer:manual_action(e);
    shami_controller:manual_action(e);
end);
ashita.events.register('command', 'invmaster_command', function(e)
    local cmd, rest=e.command:match('^(%S+)%s*(.*)$');
    if not cmd then return end
    cmd=cmd:lower();
    if cmd~='/im' and cmd~='/invmaster' and cmd~='/fms' then return end
    e.blocked=true;
    local action, text=rest:match('^(%S+)%s*(.*)$'); action=(action or 'ui'):lower();
    if action == 'craftprepare' then preparer:request(text);
    elseif action == 'craftcancel' then preparer:cancel(text);
    elseif action == 'ui' then window[1]=not window[1];
    elseif action == 'monitor' and ready() then profile.monitor.enabled=not profile.monitor.enabled; settings.save();
    elseif action == 'find' then query[1]=text:sub(1,255); window[1]=true;
    elseif action == 'shamitrace' then
        if text=='stop' then shami_trace:stop(); print('[InvMaster] Shami trace stopped.');
        elseif ready() then
            crystal_trace:stop();
            local ok=shami_trace:start();
            print(ok and '[InvMaster] Passive Shami trace armed for 120 seconds. Browse his menu normally, then cancel. Log: shami-menu-trace.log' or '[InvMaster] Could not open Shami trace log.');
        end
    elseif action == 'crystaltrace' then
        if text=='stop' then crystal_trace:stop(); print('[InvMaster] Crystal trace stopped.');
        elseif ready() then
            shami_trace:stop();
            local ok=crystal_trace:start();
            print(ok and '[InvMaster] Passive crystal trace armed for 60 seconds. Talk to the Ephemeral Moogle and manually withdraw crystals. Log: crystal-menu-trace.log' or '[InvMaster] Could not open trace log.');
        end
    elseif action == 'refresh' then next_read=0;
    elseif action == 'status' then
        local key,reason=transfer_context();
        print('[InvMaster] Current: ' .. (key or reason));
        print('[InvMaster] Recorded: ' .. (bag_access.key or 'none') .. ' | Mog House: ' .. tostring(bag_access.home) .. ' | Entry flag: ' .. tostring(bag_access.home_byte));
        print('[InvMaster] Capacity update: ' .. (bag_access.sizes and 'received' or 'missing') .. ' | Wardrobe flags: ' .. tostring(bag_access.paid));
        for _,id in ipairs({0,1,2,4,5,9}) do
            local bag=snapshot and snapshot[id+1];
            local free=bag and bag.state=='Client snapshot' and tostring(bag.free) or 'unknown';
            local allowed=key and current_access()[id];
            print(('[InvMaster] %s: access=%s, free=%s, reported size=%s, secondary=%s'):format(model.containers[id+1],tostring(allowed==true),free,tostring(bag_access.sizes and bag_access.sizes[id]),tostring(bag_access.secondary and bag_access.secondary[id])));
        end
    else print('[InvMaster] /im | /im find <name> | /im refresh | /im status'); end
end);
ashita.events.register('d3d_present', 'invmaster_present', function()
    local ok, err=pcall(poll);
    if not ok then snapshot=nil; last_read=nil; next_read=os.clock()+profile.refresh_seconds; status='Inventory read failed; retrying.'; end
    mover:tick();
    sorter:tick();
    withdrawer:tick();
    preparer:tick();
    crystal_withdrawer:tick();
    shami_controller:tick();
    if currency_refresh_due and not busy() and crystal_key() and os.clock()>=currency_next_request then
        currency_refresh_due=false; currency_refresh.request();
    end
    if sort_request~=nil and not mover.pending and not sorter.pending then
        local bag=sort_request; sort_request=nil; sorter:start(bag);
    end
    if ready() then
        bag_monitor.render(snapshot,profile.monitor,settings.save,function(id)
            selected=id; query[1]=''; focus_items=true; window[1]=true;
        end,last_read);
    end
    render();
end);
