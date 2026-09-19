-- Independent bag-space HUD, backed by InvMaster's existing read-only snapshot.
local imgui=require 'imgui';
local model=require 'inventory_model';
local M={};
local defaults={[0]=true,[1]=true,[4]=true,[5]=true,[6]=true,[7]=true,[9]=true};
function M.normalize(value)
    value=type(value)=='table' and value or {};
    local threshold=tonumber(value.warning);
    if not threshold or threshold~=threshold then threshold=5 end
    local out={enabled=value.enabled==true,locked=value.locked==true,background=value.background~=false,
        warning=math.max(0,math.min(80,math.floor(threshold))),bags={}};
    for id=0,#model.containers-1 do
        local saved;
        if type(value.bags)=='table' then saved=value.bags[tostring(id)] end
        out.bags[tostring(id)]=type(saved)=='boolean' and saved or (saved==nil and defaults[id]==true);
    end
    return out;
end
function M.level(bag,warning)
    if not bag or bag.state~='Client snapshot' then return 'unknown' end
    if bag.free==0 then return 'full' end
    if bag.free<=warning then return 'warning' end
    return 'normal';
end
local colors={normal={0.20,0.57,0.62,1},warning={0.82,0.55,0.16,1},full={0.76,0.25,0.22,1},unknown={0.30,0.32,0.36,1}};
function M.settings(options,save)
    if not imgui.CollapsingHeader('Bag monitor') then return end
    local changed=false;
    for _,entry in ipairs({{'enabled','Show bag monitor'},{'locked','Lock monitor position'},{'background','Monitor background'}}) do
        local value={options[entry[1]]};
        if imgui.Checkbox(entry[2],value) then options[entry[1]]=value[1]; changed=true end
    end
    local warning={options.warning}; imgui.SetNextItemWidth(120);
    if imgui.InputInt('Warn at free slots',warning) then options.warning=M.normalize({warning=warning[1]}).warning; changed=true end
    imgui.TextWrapped('Amber at this many free slots or fewer; red when full. Click a bag to open its items. /im monitor toggles the window.');
    for id,name in ipairs(model.containers) do
        local key=tostring(id-1); local value={options.bags[key]};
        if imgui.Checkbox(name..'##MonitorBag',value) then options.bags[key]=value[1]; changed=true end
    end
    if changed then save() end
end
function M.render(snapshot,options,save,open_bag,last_read)
    if not options.enabled then return end
    local visible={true};
    imgui.SetNextWindowSize({350,0},ImGuiCond_FirstUseEver);
    imgui.SetNextWindowBgAlpha(options.background and 0.9 or 0);
    local flags=ImGuiWindowFlags_AlwaysAutoResize+(options.locked and ImGuiWindowFlags_NoMove or 0);
    if imgui.Begin('InvMaster Bags###InvMasterBagMonitor',visible,flags) then
        if not snapshot then imgui.Text('Waiting for inventory...')
        else
            local shown=0;
            for _,bag in ipairs(snapshot) do
                if options.bags[tostring(bag.id)] then
                    shown=shown+1;
                    local level=M.level(bag,options.warning);
                    if imgui.Selectable(bag.name..'##Monitor'..bag.id,false,0,{110,20}) then open_bag(bag.id) end
                    imgui.SameLine();
                    local label=level=='unknown' and '-- / --' or ('%d/%d | %d free'):format(bag.used,bag.capacity,bag.free);
                    imgui.PushStyleColor(ImGuiCol_PlotHistogram,colors[level]);
                    imgui.ProgressBar(level=='unknown' and 0 or bag.used/bag.capacity,{210,20},label);
                    imgui.PopStyleColor();
                end
            end
            if shown==0 then imgui.Text('Choose bags in Settings > Bag monitor.') end
            if last_read then imgui.Text(('Updated %ds ago'):format(math.max(0,math.floor(os.clock()-last_read)))) end
        end
    end
    imgui.End();
    if not visible[1] then options.enabled=false; save() end
end
return M;
