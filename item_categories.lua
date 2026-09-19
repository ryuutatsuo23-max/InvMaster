local data=require 'category_data';
local M={};
M.options={
    {'weapons','Weapons'}, {'ranged','Ranged'}, {'ammo','Ammo'}, {'shield','Shields / Grips'},
    {'head','Head'}, {'body','Body'}, {'hands','Hands'}, {'legs','Legs'}, {'feet','Feet'},
    {'neck','Neck'}, {'waist','Waist'}, {'ears','Earrings'}, {'rings','Rings'}, {'back','Back'},
    {'equipment','Other equipment'}, {'materials','Materials'}, {'fish','Fish'},
    {'furniture','Furniture'}, {'food','Food / Ingredients'}, {'medicines','Medicines'},
    {'crystals','Crystals'}, {'scrolls','Scrolls / Dice'}, {'tools','Tools / Cards'},
    {'pet','Pet items / Attachments'}, {'fishing','Fishing gear'}, {'other','Other / Unknown'},
};
local slots={{1,'weapons'},{4,'ranged'},{8,'ammo'},{2,'shield'},
    {16,'head'},{32,'body'},{64,'hands'},{128,'legs'},{256,'feet'},
    {512,'neck'},{1024,'waist'},{2048,'ears'},{4096,'ears'},
    {8192,'rings'},{16384,'rings'},{32768,'back'}};
function M.classify(item)
    if item.item_type==4 or item.item_type==5 then
        if data[item.id]=='fishing' then return 'fishing' end
        local mask=item.equip_slots;
        if type(mask)=='number' and mask>=0 and mask<=65535 and mask==math.floor(mask) then
            for _,slot in ipairs(slots) do
                if math.floor(mask/slot[1])%2==1 then return slot[2] end
            end
        end
        return item.item_type==4 and 'weapons' or 'equipment';
    end
    if item.item_type==10 or item.item_type==11 or item.item_type==12 or item.item_type==14 then return 'furniture' end
    return data[item.id] or 'other';
end
function M.normalize(value)
    local result={};
    for _,option in ipairs(M.options) do
        result[option[1]]=not (type(value)=='table' and value[option[1]]==false);
    end
    return result;
end
function M.matches(item,enabled)
    return not enabled or enabled[M.classify(item)]~=false;
end
function M.render(imgui,enabled,id,save)
    local count=0;
    for _,option in ipairs(M.options) do if enabled[option[1]]~=false then count=count+1 end end
    local preview=count==#M.options and 'All categories' or ('%d / %d categories'):format(count,#M.options);
    if imgui.BeginCombo('Categories##'..id,preview) then
        local changed=false;
        if imgui.Button('All##'..id) then for _,o in ipairs(M.options) do enabled[o[1]]=true end; changed=true end
        imgui.SameLine();
        if imgui.Button('None##'..id) then for _,o in ipairs(M.options) do enabled[o[1]]=false end; changed=true end
        for _,o in ipairs(M.options) do
            local checked={enabled[o[1]]~=false};
            if imgui.Checkbox(o[2]..'##'..id,checked) then enabled[o[1]]=checked[1]; changed=true end
        end
        if changed then save() end
        imgui.EndCombo();
    end
end
return M;
