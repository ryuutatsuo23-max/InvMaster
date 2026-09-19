-- Passive Currencies I snapshot. Offsets documented in docs/currency-research.md.
local imgui=require 'imgui';
local M={};
local shami=require 'shami';
M.crystals={'Fire','Ice','Wind','Earth','Lightning','Water','Light','Dark'};
M.seals={"Beastmen's Seals","Kindred's Seals","Kindred's Crests","High Kindred's Crests","Sacred Kindred's Crests"};
-- Copy and validate saved snapshots; never share state between profiles.
function M.restore(value,name,id)
    if type(value)~='table' or value.owner_name~=name or value.owner_id~=id then return nil end
    local t=value.time;
    if type(t)~='number' or t~=t or t<1 or t>4102444800 or t~=math.floor(t) then return nil end
    local copy={time=t,owner_name=name,owner_id=id};
    for _,group in ipairs({{'crystals',8},{'seals',5}}) do
        local values=value[group[1]]; if type(values)~='table' then return nil end
        copy[group[1]]={};
        for i=1,group[2] do
            local n=values[i];
            if type(n)~='number' or n~=n or n<0 or n>65535 or n~=math.floor(n) then return nil end
            copy[group[1]][i]=n;
        end
    end
    return copy;
end
function M.decode(data)
    if type(data)~='string' or #data<0xF8 then return nil end
    local function u16(offset) local a,b=data:byte(offset+1,offset+2); return a+b*256 end
    local result={crystals={},seals={}};
    for i=1,8 do result.crystals[i]=u16(0xE8+(i-1)*2) end
    for i=1,5 do result.seals[i]=u16(0x10+(i-1)*2) end
    return result;
end
local selected,quantity=nil,{1};
local seal_selected,seal_quantity,orb_selected,confirm_orb=nil,{1},nil,nil;
function M.reset() selected=nil; quantity[1]=1; seal_selected=nil; seal_quantity[1]=1; orb_selected=nil; confirm_orb=nil end
function M.render(data,withdraw,exchange,refresh)
    imgui.TextWrapped('Stored NPC balances. Use Refresh balances to request an update. Right-click a crystal to withdraw at a nearby Ephemeral Moogle. Right-click seals/crests for Shami withdrawals and orb exchanges.');
    if refresh then
        if imgui.Button('Refresh balances') then refresh.request() end
        local status=refresh.status(); if status then imgui.TextWrapped(status) end
    end
    if data then imgui.Text('Last known balances: '..os.date('%Y-%m-%d %H:%M:%S',data.time)); imgui.TextWrapped('Saved per character. Values may have changed since this update.')
    else imgui.TextWrapped('No saved balances yet. Use Refresh balances; unknown values are shown as --.') end
    local open=false; local open_shami=false;
    if imgui.BeginTabBar('CurrencyTabs') then
        for _,tab in ipairs({{'Crystals','crystals',M.crystals,'Ephemeral Moogle'}, {'Seals & Crests','seals',M.seals,'Shami'}}) do
            if imgui.BeginTabItem(tab[1]) then
                imgui.Text(tab[4]);
                for i,name in ipairs(tab[3]) do
                    local label=name..': '..(data and tostring(data[tab[2]][i]) or '--');
                    if tab[2]=='crystals' then
                        imgui.Selectable(label..'##Crystal'..i,false);
                        if withdraw and imgui.IsItemClicked(1) and not withdraw.busy() then selected=i; quantity[1]=1; open=true end
                    else
                        imgui.Selectable(label..'##Seal'..i,false);
                        if exchange and imgui.IsItemClicked(1) and not exchange.busy() then
                            seal_selected=i; seal_quantity[1]=1; orb_selected=nil; confirm_orb=nil; open_shami=true;
                        end
                    end
                end
                imgui.EndTabItem();
            end
        end
        imgui.EndTabBar();
    end
    if open_shami then imgui.OpenPopup('Shami actions') end
    imgui.SetNextWindowSize({440,0},ImGuiCond_Always);
    if imgui.BeginPopup('Shami actions') then
        if not seal_selected or not exchange or exchange.busy() then imgui.CloseCurrentPopup()
        else
            imgui.TextWrapped(M.seals[seal_selected]);
            local npc,reason=exchange.target(true);
            local available=npc and npc.zone==246;
            if not available then imgui.TextWrapped(reason or 'Move within 6 yalms of Shami in Port Jeuno.') end
            imgui.TextWrapped('Shami is detected automatically within 6 yalms. Keep his normal menu closed. Fresh balances and Inventory space are checked before sending.');
            imgui.SetNextItemWidth(120); imgui.InputInt('Seal / crest quantity',seal_quantity);
            local n=tonumber(seal_quantity[1]); if not n or n~=n then n=1 end
            seal_quantity[1]=math.max(1,math.min(9999,math.floor(n)));
            if available and imgui.Button('Withdraw seals / crests') then exchange.start('withdraw',seal_selected,seal_quantity[1]); imgui.CloseCurrentPopup() end
            imgui.Separator();
            imgui.Text('Orb exchange');
            imgui.SetNextItemWidth(260);
            if imgui.BeginCombo('Orb',orb_selected and shami.orbs[orb_selected].name or 'Choose an orb') then
                for i,orb in ipairs(shami.orbs) do
                    if orb.seal==seal_selected and imgui.Selectable(orb.name..' ('..orb.cost..')##Orb'..i,orb_selected==i) then orb_selected=i; confirm_orb=nil end
                end
                imgui.EndCombo();
            end
            if orb_selected then
                local orb=shami.orbs[orb_selected];
                imgui.TextWrapped(('Cost: %d %s for one %s.'):format(orb.cost,M.seals[orb.seal],orb.name));
                if available and imgui.Button('Review exchange') then confirm_orb=orb_selected end
                if available and confirm_orb==orb_selected then
                    imgui.TextWrapped('This spends your stored seals/crests.');
                    if imgui.Button('Confirm: spend '..orb.cost..' for '..orb.name) then
                        exchange.start('orb',orb_selected,1); confirm_orb=nil; imgui.CloseCurrentPopup();
                    end
                end
            end
            if imgui.Button('Cancel##Shami') then confirm_orb=nil; imgui.CloseCurrentPopup() end
        end
        imgui.EndPopup();
    end
    if open then imgui.OpenPopup('Withdraw crystals') end
    imgui.SetNextWindowSize({440,0},ImGuiCond_Always);
    if imgui.BeginPopup('Withdraw crystals') then
        if not selected or not withdraw or withdraw.busy() then imgui.CloseCurrentPopup()
        else
            imgui.Text(M.crystals[selected]..' -> Inventory');
            imgui.SetNextItemWidth(120); imgui.InputInt('Crystal units',quantity);
            local n=tonumber(quantity[1]); if not n or n~=n then n=1 end
            quantity[1]=math.max(1,math.min(65535,math.floor(n)));
            imgui.Text(('%d cluster(s) + %d crystal(s)'):format(math.floor(quantity[1]/12),quantity[1]%12));
            local npc,reason=withdraw.target(true);
            if not npc then imgui.TextWrapped(reason)
            else
                imgui.TextWrapped('The nearest Moogle within 6 yalms is selected automatically. Keep its menu closed. Fresh balances are checked before withdrawing.');
                if imgui.Button('Withdraw crystals') then withdraw.start(selected,quantity[1]); imgui.CloseCurrentPopup() end
            end
            if imgui.Button('Cancel##Crystals') then imgui.CloseCurrentPopup() end
        end
        imgui.EndPopup();
    end
end
return M;
