from pathlib import Path
from lupa.luajit21 import LuaRuntime
ROOT = Path(__file__).parent
scenarios = 0

def setup():
    global scenarios
    scenarios += 1
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute('''
    now=0; os.clock=function() return now end
    counts={[0]=2,[1]=1,[5]=0}; capacity={[0]=10,[1]=80,[5]=30}; counter=1
    slots={[0]={[1]={Id=101,Count=1},[2]={Id=102,Count=12}}, [1]={[4]={Id=101,Count=1}}, [5]={}}
    resource_data={[101]={Name={[1]="Lgn. Knuckles"},LogNameSingular={[1]="Legionnaire's Knuckles"}}, [102]={Name={[1]='Copper Ore'}}}
    for _, bag in pairs(slots) do for _, item in pairs(bag) do item.Flags=0; item.Price=0; item.Extra=string.rep(string.char(0),28) end end
    for _, r in pairs(resource_data) do r.StackSize=99; r.Type=1 end
    inv={GetContainerUpdateCounter=function() return counter end,
      GetContainerCountMax=function(_,b) return capacity[b] or 0 end,
      GetContainerCount=function(_,b) return counts[b] end,
      GetContainerItem=function(_,b,s) return slots[b] and slots[b][s] end}
    resources={GetItemById=function(_,id) return resource_data[id] end}
    ''')
    for name in ['category_data', 'item_categories']:
        lua.globals().module_source=(ROOT/(name+'.lua')).read_text()
        lua.execute("package.preload['"+name+"']=assert(loadstring(module_source))")
    model=lua.execute((ROOT/'inventory_model.lua').read_text())
    lua.globals().model=model
    return lua

def run(lua, text):
    lua.execute(text)

l=setup(); run(l, "local s=model.scan(inv,resources); assert(#s==18 and s[1].used==2 and s[1].free==8); local rows,n=model.search(s,'knuckles'); assert(#rows==2 and n==2); assert(rows[1].bag.name=='Inventory' and rows[2].bag.name=='Safe'); assert(s[6].used==0 and s[6].free==30)")
for query in ['LEGIONNAIRES', "legionnaire's knuckles", 'knuckles legion', '101', 'lgn knuckles']:
    l=setup(); l.globals().q=query; run(l, "local rows,n=model.search(model.scan(inv,resources),q); assert(#rows==2 and n==2)")
l=setup(); run(l, "local s=model.scan(inv,resources); local rows,n=model.search(s,'',0); assert(#rows==2 and n==13); assert(rows[1].item.name=='Copper Ore'); local one=model.search(s,'knuckles',1); assert(#one==1 and one[1].item.slot==4)")
for query in ['missing', '%', '[', 'knuckles copper']:
    l=setup(); l.globals().q=query; run(l, "assert(#model.search(model.scan(inv,resources),q)==0)")
l=setup(); run(l, "slots[0][3]={Id=101,Count=1}; counts[0]=3; local rows=model.search(model.scan(inv,resources),'knuckles',0); assert(#rows==2 and rows[1].item.slot==1 and rows[2].item.slot==3)")
for mutation in ['capacity[0]=9999','capacity[0]=-1','capacity[0]=0/0','counts[0]=3','slots[0][1].Count=-1','slots[0][1].Id=999999','slots[0][1].Count=0/0']:
    l=setup(); run(l, mutation+"; local s=model.scan(inv,resources); assert(s[1].state~='Client snapshot'); assert(#model.search(s,'knuckles',0)==0); assert(#model.search(s,'knuckles',1)==1)")
l=setup(); run(l, "local read=inv.GetContainerItem; inv.GetContainerItem=function(self,b,s) if b==0 then error('unavailable') end; return read(self,b,s) end; local s=model.scan(inv,resources); assert(s[1].state=='Read error' and #s[1].items==0); assert(#model.search(s,'knuckles')==1)")
l=setup(); run(l, "inv.GetContainerUpdateCounter=function() counter=counter+1; return counter end; local s,reason=model.scan(inv,resources); assert(s==nil and reason:find('updating'))")
l=setup(); run(l, "resource_data[101]=nil; local rows=model.search(model.scan(inv,resources),'101'); assert(#rows==2 and rows[1].item.name=='Item #101')")

# Integration mocks: outgoing requests are captured locally, never sent to the game.
def addon_setup():
    lua=setup()
    lua.globals().transfer_module=lua.execute((ROOT/'transfer.lua').read_text())
    lua.globals().access_module=lua.execute((ROOT/'bag_access.lua').read_text())
    lua.globals().route_source=(ROOT/'route_transfer.lua').read_text()
    lua.globals().stack_source=(ROOT/'stack_sort.lua').read_text()
    lua.globals().monitor_source=(ROOT/'bag_monitor.lua').read_text()
    lua.globals().nearby_source=(ROOT/'nearby_npc.lua').read_text()
    lua.globals().shami_source=(ROOT/'shami.lua').read_text()
    lua.globals().crystal_source=(ROOT/'crystal_withdraw.lua').read_text()
    lua.globals().trace_source=(ROOT/'crystal_trace.lua').read_text()
    lua.globals().withdraw_source=(ROOT/'withdraw.lua').read_text()
    lua.globals().currency_source=(ROOT/'currency.lua').read_text()
    lua.globals().custom_source=(ROOT/'customization.lua').read_text()
    lua.globals().ownership_source=(ROOT/'ownership_view.lua').read_text()
    lua.execute('''
    package.preload.common=function() end; T=function(t) return t end
    package.preload.inventory_model=function() return model end
    package.preload.transfer=function() return transfer_module end
    package.preload.route_transfer=function() return assert(loadstring(route_source))() end
    package.preload.stack_sort=function() return assert(loadstring(stack_source))() end
    package.preload.bag_monitor=function() return assert(loadstring(monitor_source))() end
    package.preload.nearby_npc=function() return assert(loadstring(nearby_source))() end
    package.preload.shami=function() return assert(loadstring(shami_source))() end
    package.preload.crystal_withdraw=function() return assert(loadstring(crystal_source))() end
    package.preload.crystal_trace=function() return assert(loadstring(trace_source))() end
    package.preload.withdraw=function() return assert(loadstring(withdraw_source))() end
    package.preload.currency=function() return assert(loadstring(currency_source))() end
    package.preload.customization=function() return assert(loadstring(custom_source))() end
    package.preload.ownership_view=function() return assert(loadstring(ownership_source))() end
    package.preload.bag_access=function() return access_module end
    player={Name='Alice',ServerId=100}; zoning=0; zone=1; callbacks={}; saves=0
    settingsmock={logged_in=true,name='Alice',server_id=100}
    settingsmock.load=function(d) current_profile=d; return d end
    settingsmock.register=function(_,_,cb) switch_profile=cb end
    settingsmock.save=function() saves=saves+1; saved_interval=current_profile.refresh_seconds end
    package.preload.settings=function() return settingsmock end
    sent={}; player_status=0; hp=100; equipment={}
    inv.GetEquippedItem=function(_,i) return {Index=equipment[i] or 0} end
    addon={}; ashita={events={register=function(e,_,cb) callbacks[e]=cb end}}
    GetPlayerEntity=function() return player end
    local mm={GetPlayer=function() return {GetIsZoning=function() return zoning end} end,
      GetTarget=function() return {GetTargetIndex=function() return target_index or 0 end} end,
      GetEntity=function() return {GetName=function(_,i) return i==(npc_index or target_index) and target_name or nil end,GetRenderFlags0=function() return 0x200 end,GetDistance=function() return target_distance end,GetServerId=function() return target_id end,GetStatus=function() return player_status end,GetHPPercent=function() return hp end} end,
      GetParty=function() return {GetMemberTargetIndex=function() return 1 end,GetMemberZone=function() return zone end} end,
      GetInventory=function() return inv end}
    AshitaCore={GetPacketManager=function() return {AddOutgoingPacket=function(_,id,p) sent[#sent+1]={id=id,data=p}; if fail_send_at==#sent then error("uncertain API result") end end} end,GetMemoryManager=function() return mm end,GetResourceManager=function() return resources end}
    ImGuiCond_Always=1; ImGuiCond_FirstUseEver=4; ImGuiTableColumnFlags_WidthStretch=8; ImGuiTableColumnFlags_WidthFixed=16
    ImGuiTableFlags_ScrollY=33554432; ImGuiTableFlags_Resizable=1; ImGuiTableFlags_Reorderable=2; ImGuiTableFlags_Sortable=8; ImGuiTableColumnFlags_DefaultSort=4; ImGuiSortDirection_Descending=2
    ImGuiWindowFlags_AlwaysAutoResize=64; ImGuiWindowFlags_NoMove=4; ImGuiCol_PlotHistogram=40; ImGuiTabItemFlags_SetSelected=2
    sort_specs=nil; edit_interval=nil; rendered_items={}
    ui={}; child=0; tabs=0; tables=0; click=nil; hide_child=false
    package.preload.imgui=function() return {
      CollapsingHeader=function() return false end, SetNextWindowBgAlpha=function() end,
      PushStyleColor=function() end, PopStyleColor=function() end, ProgressBar=function(value,size,label) ui[#ui+1]=label; assert(value>=0 and value<=1) end,
      GetContentRegionAvail=function() return 500,300 end,
      TableSetupScrollFreeze=function(cols,rows) assert(cols==0 and rows==1) end,
      SetNextWindowSize=function(size,cond) next_window_size=size; next_window_cond=cond end, SetNextItemWidth=function(width) item_width=width end,
      Begin=function(name,visible) if close_monitor and name=='InvMaster Bags###InvMasterBagMonitor' then visible[1]=false; close_monitor=false end; return true end, End=function() end,
      Text=function(t) ui[#ui+1]=t end, TextWrapped=function(t) ui[#ui+1]=t end,
      TableGetSortSpecs=function() return sort_specs end,
      InputInt=function(_,v) if edit_interval then v[1]=edit_interval; edit_interval=nil; return true end; return false end,
      InputTextWithHint=function(label,hint,v) if edit_search and edit_search.label==label then v[1]=edit_search.value; edit_search=nil; return true end; return false end,
      BeginCombo=function(label,preview) if label=='Move to' then assert(item_width==260); move_preview=preview end; combo_active=(open_combo==label); return combo_active end, EndCombo=function() combo_active=false end, Selectable=function(label) last_item=label; if combo_active then combo_options[label]=true end; ui[#ui+1]=label:gsub('##.*',''); if click==label then click=nil; return true end; return false end,
      IsItemClicked=function(button) assert(button==1); if right_click==last_item then right_click=nil; return true end; return false end,
      OpenPopup=function(id) popup=id end, BeginPopup=function(id) assert(next_window_size[1]==440 and next_window_size[2]==0 and next_window_cond==ImGuiCond_Always); if popup==id then popups=(popups or 0)+1; return true end; return false end, EndPopup=function() popups=popups-1 end, CloseCurrentPopup=function() popup=nil end,
      Button=function(label) if click==label then click=nil; return true end; return false end,
      Checkbox=function(label,value) if toggle_checkbox==label then value[1]=not value[1]; toggle_checkbox=nil; return true end; return false end, SameLine=function() end, Separator=function() end,
      BeginTabBar=function() return true end, EndTabBar=function() end,
      BeginTabItem=function(name) tab_names[name]=true; if (active_tab and name~=active_tab and not (active_tab=='Currency' and name==(currency_subtab or 'Crystals'))) or (not active_tab and (name=='Move' or name=='Ownership' or name=='Customization' or name=='Currency')) then return false end; tabs=tabs+1; return true end, EndTabItem=function() tabs=tabs-1 end,
      BeginChild=function() child=child+1; return not hide_child end, EndChild=function() child=child-1 end,
      BeginTable=function(name,_,flags,size) assert(size[2]==300); if name=='MovePanes' then assert(flags==1) elseif name=='Items' or name=='Ownership' or name:find('MoveItems',1,true) then assert(flags==33554443) else assert(flags==33554432) end; tables=tables+1; return true end, EndTable=function() tables=tables-1 end,
      TableSetupColumn=function() end, TableHeadersRow=function() end, TableNextRow=function() end, TableNextColumn=function() end,
    } end
    function cmd(s) local e={command=s}; callbacks.command(e); return e.blocked end
    function tick(t) now=t; ui={}; combo_options={}; tab_names={}; callbacks.d3d_present(); assert(child==0 and tabs==0 and tables==0 and (popups or 0)==0) end
    function shown(s) for _,v in ipairs(ui) do if v:find(s,1,true) then return true end end; return false end
    ''')
    lua.execute((ROOT/'invmaster.lua').read_text())
    return lua

l=addon_setup(); run(l, "tick(0); tick(3); assert(#ui==0); assert(cmd('/fms find knuckles')); tick(4); assert(shown('2 matching slots | 2 items')); assert(not shown('Copper Ore')); assert(not cmd('/gp')); assert(saves==0)")
l=addon_setup(); run(l, "cmd('/fms'); tick(0); assert(shown('Waiting for inventory')); tick(3); assert(shown('3 / 18 containers read')); zoning=1; tick(4); assert(not shown('Lgn. Knuckles')); zoning=0; zone=2; tick(5); assert(not shown('Lgn. Knuckles')); tick(8); assert(shown('Lgn. Knuckles'))")
l=addon_setup(); run(l, "cmd('/fms'); tick(0); tick(3); player={Name='Bob',ServerId=200}; tick(4); assert(not shown('Lgn. Knuckles')); settingsmock.name='Bob'; settingsmock.server_id=200; switch_profile({}); slots={}; counts={}; capacity={}; tick(5); assert(#ui==0); cmd('/fms'); tick(8); assert(shown('0 matching slots') and not shown('Lgn. Knuckles'))")
l=addon_setup(); run(l, "cmd('/fms'); tick(0); tick(3); inv.GetContainerUpdateCounter=function() counter=counter+1; return counter end; tick(5); assert(not shown('Lgn. Knuckles') and shown('waiting for a stable read'))")
l=addon_setup(); run(l, "cmd('/fms'); tick(0); tick(3); inv.GetContainerUpdateCounter=function() error('not ready') end; tick(5); assert(shown('Inventory read failed') and not shown('Lgn. Knuckles')); hide_child=true; tick(6)")
l=addon_setup(); run(l, "cmd('/fms'); tick(0); tick(3); slots[0][2].Count=5; tick(4); assert(shown('14 items')); cmd('/fms refresh'); tick(4); assert(shown('7 items')); cmd('/fms'); tick(5); assert(#ui==0)")
# Header identifies each excluded container, distinguishes its state, and clears recovered states.
l=addon_setup(); run(l, "counts[0]=3; cmd('/fms'); tick(0); tick(3); assert(shown('Updating: Inventory')); assert(shown('Unavailable: Storage, Temporary, Locker')); assert(shown('Auto-refresh: 2s | Last read: 0s ago')); tick(4); assert(shown('Last read: 1s ago')); counts[0]=2; tick(5); assert(not shown('Updating: Inventory')); assert(shown('3 / 18 containers read')); inv.GetContainerItem=function() error('read failure') end; tick(7); assert(shown('Read error: Inventory, Safe, Satchel')); zoning=1; tick(8); assert(not shown('Read error:'))")
# All four sort columns, both directions, numeric quantities/slots and stable ties.
for column in range(4):
    for descending in [False, True]:
        l=setup(); l.globals().sort_column=column; l.globals().descending=descending
        run(l, "slots[0][2].Count=12; slots[1][4].Count=2; local rows=model.search(model.scan(inv,resources),''); model.sort(rows,sort_column,descending); local function value(r) if sort_column==0 then return r.item.name:lower() elseif sort_column==1 then return r.bag.name:lower() elseif sort_column==2 then return r.item.count else return r.item.slot end end; for i=2,#rows do if descending then assert(value(rows[i-1])>=value(rows[i])) else assert(value(rows[i-1])<=value(rows[i])) end end")
# Native single-column sort spec works on every fresh search, including after refresh.
l=addon_setup(); run(l, "cmd('/fms'); sort_specs={SpecsCount=1,SpecsDirty=true,Specs={ColumnUserID=2,ColumnIndex=0,SortDirection=2}}; tick(0); tick(3); assert(not sort_specs.SpecsDirty); local first; for _,v in ipairs(ui) do if v=='Copper Ore' or v=='Lgn. Knuckles' then first=v; break end end; assert(first=='Copper Ore'); tick(5); assert(shown('14 items'))")
# Interval changes save and reschedule; manual refresh does not overwrite the preference.
l=addon_setup(); run(l, "cmd('/fms'); tick(0); tick(3); edit_interval=10; tick(4); assert(saves==1 and saved_interval==10); slots[0][2].Count=5; tick(6); assert(shown('14 items') and shown('Auto-refresh: 10s')); tick(14); assert(shown('7 items')); slots[0][2].Count=2; cmd('/fms refresh'); tick(15); assert(shown('4 items') and current_profile.refresh_seconds==10)")
# Existing profiles default to 2 seconds; corrupt and out-of-range values are sanitized.
for value, expected in [('nil',2), ('0',1), ('100',60), ('0/0',2), ('math.huge',2), ("'bad'",2), ('3.9',3)]:
    l=addon_setup(); run(l, f"switch_profile({{refresh_seconds={value}}}); cmd('/fms'); tick(0); assert(shown('Auto-refresh: {expected}s'))")
# Independent transfer-controller tests. Requests only enter the local mock log.
def transfer_setup():
    l=setup()
    l.globals().transfer=l.execute((ROOT/'transfer.lua').read_text())
    run(l, """
    counts[6]=0; capacity[6]=80; slots[6]={}; counts[7]=0; capacity[7]=80; slots[7]={}
    local data=model.scan(inv,resources); chosen={bag=0}; for k,v in pairs(data[1].items[2]) do chosen[k]=v end
    sent={}; changed=0; owner='Alice:100:1'; is_equipped=false; send_error=false
    mover=transfer.new({now=function() return now end,context=function() return owner,'Not idle' end,
      scan=function() return model.scan(inv,resources) end,equipped=function() return is_equipped end,
      changed=function() changed=changed+1 end,
      send=function(p) sent[#sent+1]=p; if send_error then error('uncertain send') end end})
    function moved(q)
      slots[0][2].Count=12-q
      if q==12 then slots[0][2]=nil; counts[0]=1 end
      slots[6][1]={Id=102,Count=q,Flags=0,Price=0,Extra=string.rep(string.char(0),28)}; counts[6]=1
    end
    """)
    return l

for q in [1,3,12]:
    l=transfer_setup(); l.globals().q=q
    run(l, "assert(mover:start(chosen,6,q)); assert(#sent==1 and #sent[1]==12); assert(sent[1][5]==q and sent[1][9]==0 and sent[1][10]==6 and sent[1][11]==2 and sent[1][12]==82); assert(not mover:start(chosen,6,q)); moved(q); now=1; mover:tick(); assert(mover.pending); now=1.25; mover:tick(); assert(not mover.pending and changed==1 and mover.message:find('Moved')); assert(#sent==1)")
for mutation in ["slots[0][2].Id=101", "slots[0][2].Count=11", "slots[0][2].Extra=string.rep('x',28)", "slots[0][2].Flags=5", "slots[0][2].Price=100", "is_equipped=true", "resource_data[102].Type=10", "resource_data[102].StackSize=nil", "slots[0][2].Extra=nil", "slots[0][2].Extra='short'", "capacity[6]=0", "counts[6]=1", "owner=nil", "chosen.slot=0"]:
    l=transfer_setup(); run(l, mutation+"; assert(not mover:start(chosen,6,1)); assert(#sent==0)")
for dest in [0,1,2,3,4,5,8,17,99]:
    l=transfer_setup(); run(l,f"assert(not mover:start(chosen,{dest},1)); assert(#sent==0)")
for q in ['0','-1','13','1.5','0/0','math.huge']:
    l=transfer_setup(); run(l,f"assert(not mover:start(chosen,6,{q})); assert(#sent==0)")
l=transfer_setup(); run(l,"capacity[6]=1; counts[6]=1; slots[6][1]={Id=102,Count=1,Flags=0,Extra=string.rep(string.char(0),28)}; assert(not mover:start(chosen,6,1)); assert(#sent==0)")
# Timeout and interrupted confirmation stay locked; no retry or invented success.
l=transfer_setup(); run(l,"mover:start(chosen,6,1); now=9; mover:tick(); assert(mover.pending and mover.message:find('not confirmed')); assert(not mover:start(chosen,6,1)); owner=nil; now=10; mover:tick(); assert(mover.pending); owner='Alice:100:1'; moved(1); now=11; mover:tick(); now=11.25; mover:tick(); assert(not mover.pending and #sent==1)")
l=transfer_setup(); run(l,"send_error=true; mover:start(chosen,6,1); assert(mover.pending and mover.message:find('unknown')); assert(not mover:start(chosen,6,1)); now=9; mover:tick(); assert(#sent==1)")
# One-sided updates do not confirm; stack merges use quantities rather than slot counts.
l=transfer_setup(); run(l,"slots[6][1]={Id=102,Count=2,Flags=0,Price=0,Extra=string.rep(string.char(0),28)}; counts[6]=1; mover:start(chosen,6,3); slots[0][2].Count=9; now=1; mover:tick(); now=2; mover:tick(); assert(mover.pending); slots[6][1].Count=5; now=3; mover:tick(); now=3.25; mover:tick(); assert(not mover.pending and #sent==1)")
# Nonstackable copies require the exact extra data at the destination.
l=transfer_setup(); run(l,"resource_data[102].StackSize=1; slots[0][2].Count=1; chosen.count=1; mover:start(chosen,6,1); slots[0][2]=nil; counts[0]=1; slots[6][1]={Id=102,Count=1,Flags=0,Extra=string.rep('x',28)}; counts[6]=1; now=1; mover:tick(); now=2; mover:tick(); assert(mover.pending); slots[6][1].Extra=chosen.extra; now=3; mover:tick(); now=3.25; mover:tick(); assert(not mover.pending)")
# Reverse routes work; portable-to-portable does not silently create two requests.
for bag in [6,7]:
    l=transfer_setup(); run(l,f"slots[{bag}][1]=slots[0][2]; counts[{bag}]=1; slots[0][2]=nil; counts[0]=1; chosen.bag={bag}; chosen.slot=1; assert(mover:start(chosen,0,1)); assert(sent[1][9]=={bag} and sent[1][10]==0)")
l=transfer_setup(); run(l,"chosen.bag=6; assert(not mover:start(chosen,7,1)); assert(#sent==0)")
# A complete UI click sends exactly one request, while ordinary searches send none.
l=addon_setup(); run(l,"capacity[6]=80; counts[6]=0; slots[6]={}; cmd('/fms'); tick(0); right_click='Copper Ore##0_2'; tick(3); click='Move item'; tick(4); assert(#sent==1 and sent[1].id==0x029); click='Move item'; tick(5); assert(#sent==1); zoning=1; tick(6); zoning=0; tick(7); tick(10); assert(#sent==1)")
for state in ["player_status=1", "player_status=4", "hp=0", "equipment[0]=2"]:
    l=addon_setup(); run(l,"capacity[6]=80; counts[6]=0; slots[6]={}; cmd('/fms'); tick(0); right_click='Copper Ore##0_2'; tick(3); "+state+"; click='Move item'; tick(4); assert(#sent==0)")
# All selects this slot's full stack without sending; Move still requires its own click.
l=addon_setup(); run(l,"capacity[6]=80; counts[6]=0; slots[6]={}; cmd('/fms'); tick(0); right_click='Copper Ore##0_2'; tick(3); click='All'; tick(4); assert(#sent==0); click='Move item'; tick(5); assert(#sent==1 and sent[1].data[5]==12)")
# The existing stale-selection guard still blocks a stack changed after All.
l=addon_setup(); run(l,"capacity[6]=80; counts[6]=0; slots[6]={}; cmd('/fms'); tick(0); right_click='Copper Ore##0_2'; tick(3); click='All'; tick(4); slots[0][2].Count=11; click='Move item'; tick(5); assert(#sent==0)")

# Passive access: raw wire offsets, ownership, zone transitions, and unavailable flags.
PACKET_HELPERS = r"""
function wire(size,fields)
  local b={}; for i=1,size do b[i]=0 end
  for offset,values in pairs(fields or {}) do
    if type(values)=='number' then b[offset+1]=values
    elseif type(values)=='string' then for i=1,#values do b[offset+i]=values:byte(i) end
    else for i,v in ipairs(values) do b[offset+i]=v end end
  end
  return string.char(unpack(b));
end
function zone_packet(home) return wire(0x94,{[4]=100,[0x30]=1,[0x80]=home and 1 or 0,[0x84]='Alice'}) end
function sizes_packet() local f={}; for i=0,16 do f[4+i]=80 end; f[0x2C]=80; f[0x2E]=80; return wire(0x48,f) end
function flags_packet(flags) return wire(0x60,{[0x24]=100,[0x5C]=flags}) end
"""
def access_setup():
    l=setup(); l.globals().access_module=l.execute((ROOT/'bag_access.lua').read_text())
    l.execute(PACKET_HELPERS); l.execute('access=access_module.new()'); return l

l=access_setup(); run(l,"local b=access:allowed('Alice:100:1'); assert(b[0] and b[6] and b[7] and b[8] and b[10]); assert(not b[1] and not b[5] and not b[11]); access:observe(0x01C,sizes_packet()); assert(not access:allowed('Alice:100:1')[5])")
l=access_setup(); run(l,"access:observe(0x00A,zone_packet(true)); access:observe(0x01C,sizes_packet()); access:observe(0x037,flags_packet(123)); local b=access:allowed('Alice:100:1'); for _,i in ipairs({0,1,2,4,5,6,7,8,9,10,11,12,13,14,15,16}) do assert(b[i],i) end; assert(not b[3] and not b[17]); assert(not access:allowed('Bob:100:1')[1]); assert(not access:allowed('Alice:100:2')[1])")
for bag, flag in [(11,1),(12,2),(13,8),(14,16),(15,32),(16,64)]:
    l=access_setup(); run(l,f"access:observe(0x00A,zone_packet(false)); access:observe(0x01C,sizes_packet()); access:observe(0x037,flags_packet({flag})); local b=access:allowed('Alice:100:1'); assert(b[{bag}] and b[5]); assert(not b[1] and not b[2] and not b[4] and not b[9]); for i=11,16 do assert(b[i]==(i=={bag})) end; access:observe(0x037,flags_packet(0)); assert(not access:allowed('Alice:100:1')[{bag}])")
l=access_setup(); run(l,"access:observe(0x00A,zone_packet(true)); access:observe(0x01C,sizes_packet()); access:observe(0x037,wire(0x60,{[0x24]=101,[0x5C]=123})); assert(not access:allowed('Alice:100:1')[11]); access:observe(0x00B,''); assert(not access:allowed('Alice:100:1')[1]); access:observe(0x00A,'short'); assert(not access.key)")
l=access_setup(); run(l,"access:observe(0x00A,zone_packet(true)); access:observe(0x01C,sizes_packet()); access:observe(0x01C,wire(0x48,{[8]=80,[9]=80})); local b=access:allowed('Alice:100:1'); assert(not b[4] and not b[5]); access:observe(0x01C,'short'); assert(not access:allowed('Alice:100:1')[1])")
# Every expanded bag uses the same guarded single-step controller in both directions.
for bag in [1,2,4,5,8,9,10,11,12,13,14,15,16]:
    for reverse in [False,True]:
        l=transfer_setup(); run(l,f"""
        capacity[{bag}]=80; counts[{bag}]=0; slots[{bag}]={{}};
        resource_data[102].Flags=0x800; chosen.resource_flags=0x800;
        local dest={bag};
        if {str(reverse).lower()} then slots[{bag}][1]=slots[0][2]; counts[{bag}]=1; slots[0][2]=nil; counts[0]=1; chosen.bag={bag}; chosen.slot=1; dest=0 end
        local data=model.scan(inv,resources);
        local move,reason=transfer.prepare(data,chosen,dest,3,function() return false end,{{[0]=true,[{bag}]=true}});
        assert(move,reason); assert(move.quantity==3 and move.source==chosen.bag and move.destination==dest);
        assert(not transfer.prepare(data,chosen,dest,3,function() return false end,{{[0]=true}}));
        """)
# Wardrobe eligibility is rechecked against fresh resource data; non-gear stays blocked.
l=transfer_setup(); run(l,"capacity[8]=80; counts[8]=0; slots[8]={}; chosen.resource_flags=0x800; local data=model.scan(inv,resources); assert(not transfer.prepare(data,chosen,8,1,function() return false end,{[0]=true,[8]=true})); chosen.resource_flags=0; assert(not transfer.route(data,chosen,8,{[0]=true,[8]=true}))")
# UI hides full bags, keeps other choices, and clears a newly full selected destination.
l=addon_setup(); run(l,"capacity[6]=1; counts[6]=1; slots[6]={[1]=slots[0][1]}; capacity[7]=80; counts[7]=0; slots[7]={}; cmd('/fms'); tick(0); right_click='Copper Ore##0_2'; tick(3); open_combo='Move to'; tick(4); assert(not combo_options.Sack and combo_options.Case); assert(move_preview=='Choose container'); click='Case'; tick(4); click='Move item'; tick(4); assert(#sent==1 and sent[1].data[10]==7)")
l=addon_setup(); run(l,"capacity[6]=1; counts[6]=0; slots[6]={}; capacity[7]=80; counts[7]=0; slots[7]={}; cmd('/fms'); tick(0); right_click='Copper Ore##0_2'; tick(3); slots[6][1]=slots[0][1]; counts[6]=1; click='Move item'; tick(5); assert(#sent==0 and move_preview=='Choose container')")
l=addon_setup(); run(l,"capacity[5]=0; cmd('/fms'); tick(0); right_click='Copper Ore##0_2'; tick(3); tick(4); assert(shown('No accessible destination')); click='Move item'; tick(5); assert(#sent==0)")
# Integration: home access learned passively, ignored injected packets, and lost on exit.
l=addon_setup(); l.execute(PACKET_HELPERS); run(l,"cmd('/fms'); tick(0); tick(3); callbacks.packet_in({id=0x00A,data=zone_packet(true),injected=true}); callbacks.packet_in({id=0x01C,data=sizes_packet()}); right_click='Copper Ore##0_2'; tick(4); open_combo='Move to'; tick(4); assert(not combo_options.Safe); callbacks.packet_in({id=0x00A,data=zone_packet(true)}); callbacks.packet_in({id=0x01C,data=sizes_packet()}); tick(4); click='Safe'; tick(4); click='Move item'; tick(4); assert(#sent==1 and sent[1].data[10]==1)")
l=addon_setup(); l.execute(PACKET_HELPERS); run(l,"cmd('/fms'); tick(0); tick(3); callbacks.packet_in({id=0x00A,data=zone_packet(true)}); callbacks.packet_in({id=0x01C,data=sizes_packet()}); right_click='Copper Ore##0_2'; tick(4); open_combo='Move to'; click='Safe'; tick(4); callbacks.packet_in({id=0x00B,data=''}); click='Move item'; tick(4); assert(#sent==0)")
# A profile reload must discard previously learned home access even for the same name.
l=addon_setup(); l.execute(PACKET_HELPERS); run(l,"cmd('/fms'); tick(0); tick(3); callbacks.packet_in({id=0x00A,data=zone_packet(true)}); callbacks.packet_in({id=0x01C,data=sizes_packet()}); switch_profile({}); cmd('/fms'); tick(4); right_click='Copper Ore##0_2'; tick(7); open_combo='Move to'; tick(8); assert(not combo_options.Safe)")
# A blocked capacity packet cannot enable a new container.
l=addon_setup(); l.execute(PACKET_HELPERS); run(l,"cmd('/fms'); tick(0); tick(3); callbacks.packet_in({id=0x00A,data=zone_packet(true)}); callbacks.packet_in({id=0x01C,data=sizes_packet(),blocked=true}); right_click='Copper Ore##0_2'; tick(4); open_combo='Move to'; tick(4); assert(not combo_options.Safe and combo_options.Satchel)")

# Source access failures must not be presented as a full Inventory.
l=addon_setup(); run(l,"cmd('/fms'); tick(0); right_click='Lgn. Knuckles##1_4'; tick(3); tick(4); assert(shown('Safe source access is not confirmed') and shown('No zone-entry update')); assert(not shown('No accessible destination with free space'))")
l=addon_setup(); l.execute(PACKET_HELPERS); run(l,"cmd('/fms'); tick(0); tick(3); callbacks.packet_in({id=0x00A,data=zone_packet(true)}); right_click='Lgn. Knuckles##1_4'; tick(4); tick(4); assert(shown('Waiting for a complete bag-capacity update'))")
l=access_setup(); run(l,"access:observe(0x00A,zone_packet(true)); assert(access:reason('Alice:100:2',4):find('differs')); access:observe(0x01C,wire(0x48,{[8]=80})); assert(access:reason('Alice:100:1',4):find('disabled')); assert(access.secondary[4]==0); access:observe(0x00A,zone_packet(false)); assert(access:reason('Alice:100:1',4):find('not detected'))")
l=addon_setup(); l.execute(PACKET_HELPERS); run(l,"local lines={}; print=function(s) lines[#lines+1]=s end; cmd('/fms'); tick(0); tick(3); callbacks.packet_in({id=0x00A,zone=1,data=zone_packet(true)}); callbacks.packet_in({id=0x01C,sizes=1,data=sizes_packet()}); assert(cmd('/fms status')); assert(#lines==9); assert(lines[1]:find('Alice:100:1',1,true)); assert(lines[2]:find('Entry flag: 1',1,true)); assert(lines[7]:find('Locker: access=true',1,true)); assert(#sent==0)")

# Context menu setup, no transfers merely from opening it.
def move_setup():
    l=addon_setup(); l.execute("""
    capacity[7]=80; counts[7]=1; slots[7]={[1]={Id=102,Count=3,Flags=0,Price=0,Extra=string.rep(string.char(0),28)}};
    cmd('/fms'); tick(0); tick(3); right_click='Copper Ore##7_1'; tick(4);
    """); return l
l=move_setup(); run(l,"assert(#sent==0 and popup=='Item actions'); click='All'; tick(4); click='Move item'; tick(4); assert(#sent==1 and sent[1].data[5]==3 and popup==nil)")
# Live diagnostic regression: 80 usable slots can be reported as 81 on the wire.
for home in [True,False]:
    l=access_setup(); run(l,f"access:observe(0x00A,zone_packet({str(home).lower()})); access:observe(0x01C,wire(0x48,{{[8]=81,[9]=81,[0x2C]=81,[0x2E]=81}})); local b=access:allowed('Alice:100:1'); assert(b[5]); assert(b[4]=={str(home).lower()}); assert(not access:reason('Alice:100:1',5))")
# Invalid sizes and explicitly disabled secondary sizes still fail closed.
for size in [0,82,255]:
    l=access_setup(); run(l,f"access:observe(0x00A,zone_packet(true)); access:observe(0x01C,wire(0x48,{{[8]={size},[9]={size},[0x2C]=81,[0x2E]=81}})); local b=access:allowed('Alice:100:1'); assert(not b[4] and not b[5])")
l=access_setup(); run(l,"access:observe(0x00A,zone_packet(true)); access:observe(0x01C,wire(0x48,{[8]=81,[9]=81})); local b=access:allowed('Alice:100:1'); assert(not b[4] and not b[5])")
# Locker inside home and Satchel outside home can actually reach the transfer sender.
for bag,home in [(4,True),(5,False)]:
    l=addon_setup(); l.execute(PACKET_HELPERS); run(l,f"capacity[{bag}]=80; counts[{bag}]=1; slots[{bag}]={{[1]={{Id=102,Count=1,Flags=0,Price=0,Extra=string.rep(string.char(0),28)}}}}; cmd('/fms'); tick(0); tick(3); callbacks.packet_in({{id=0x00A,data=zone_packet({str(home).lower()})}}); callbacks.packet_in({{id=0x01C,data=wire(0x48,{{[8]=81,[9]=81,[0x2C]=81,[0x2E]=81}})}}); right_click='Copper Ore##{bag}_1'; tick(4); click='Move item'; tick(4); assert(#sent==1 and sent[1].data[9]=={bag} and sent[1].data[10]==0)")
# Paid wardrobes still require their explicit unlock bit when the size is 81.
l=access_setup(); run(l,"access:observe(0x00A,zone_packet(false)); access:observe(0x01C,wire(0x48,{[15]=81})); assert(not access:allowed('Alice:100:1')[11]); access:observe(0x037,flags_packet(1)); assert(access:allowed('Alice:100:1')[11])")

def bridge_setup():
    l=move_setup(); l.execute("""
    capacity[6]=80; counts[6]=0; slots[6]={}; cmd('/fms refresh'); tick(4);
    open_combo='Move to'; click='Sack'; tick(4); open_combo=nil;
    click='All'; tick(4); click='Move item'; tick(4);
    function first_done() slots[7]={}; counts[7]=0; slots[0][2].Count=15; tick(5); tick(5.25) end
    """); return l
l=bridge_setup(); run(l,"assert(#sent==1 and sent[1].data[9]==7 and sent[1].data[10]==0); first_done(); assert(#sent==2 and sent[2].data[9]==0 and sent[2].data[10]==6 and sent[2].data[5]==3 and sent[2].data[11]==2); slots[0][2].Count=12; slots[6][1]={Id=102,Count=3,Flags=0,Price=0,Extra=string.rep(string.char(0),28)}; counts[6]=1; tick(6); tick(6.25); assert(shown('via Inventory') and #sent==2)")
l=bridge_setup(); run(l,"capacity[6]=1; counts[6]=1; slots[6][1]=slots[0][1]; first_done(); tick(6); assert(#sent==1 and shown('reached Inventory') and shown('free slot'))")
l=bridge_setup(); run(l,"slots[7]={}; counts[7]=0; slots[0][2].Count=13; slots[0][3]={Id=102,Count=2,Flags=0,Price=0,Extra=string.rep(string.char(0),28)}; counts[0]=3; tick(5); tick(5.25); tick(6); assert(#sent==1 and shown('Could not identify one received stack'))")
l=bridge_setup(); run(l,"tick(13); assert(#sent==1); slots[7]={}; counts[7]=0; slots[0][2].Count=15; tick(14); tick(14.25); assert(#sent==1 and shown('continuation was cancelled'))")
l=bridge_setup(); run(l,"player_status=4; tick(4.5); player_status=0; first_done(); tick(6); assert(#sent==1 and shown('continuation was cancelled'))")
l=bridge_setup(); run(l,"first_done(); tick(14); assert(#sent==2 and shown('not confirmed')); tick(15); assert(#sent==2)")
# Full intermediate Inventory prevents storage-to-storage routes.
l=move_setup(); run(l,"capacity[0]=2; capacity[6]=80; counts[6]=0; slots[6]={}; cmd('/fms refresh'); tick(4); open_combo='Move to'; tick(4); assert(not combo_options.Sack); click='Move item'; tick(4); assert(#sent==0)")

# Native stacking: exact request, conserved totals, two stable reads and shared lock.
def stack_setup():
    l=move_setup(); l.execute("""
    slots[7][2]={Id=102,Count=1,Flags=0,Price=0,Extra=string.rep(string.char(0),28)}; counts[7]=2;
    cmd('/fms refresh'); tick(4); right_click='Copper Ore##7_1'; click='Stack bag'; tick(4); tick(4);
    """); return l
l=stack_setup(); run(l,"assert(#sent==1 and sent[1].id==0x03A and #sent[1].data==8 and sent[1].data[5]==7); right_click='Copper Ore##0_2'; tick(4.25); assert(#sent==1); slots[7][1].Count=4; slots[7][2]=nil; counts[7]=1; tick(5); tick(5.25); assert(shown('Stacks combined')); right_click='Copper Ore##7_1'; click='Stack bag'; tick(6); tick(6); assert(#sent==1 and shown('No combinable'))")
l=stack_setup(); run(l,"slots[7][1].Count=3; slots[7][2]=nil; counts[7]=1; tick(5); tick(5.25); assert(not shown('Stacks combined')); tick(13); assert(shown('Stacking not confirmed')); right_click='Copper Ore##0_2'; tick(14); click='Move item'; tick(14); assert(#sent==1)")
l=stack_setup(); run(l,"tick(13); slots[7][1].Count=4; slots[7][2]=nil; counts[7]=1; tick(14); tick(14.25); assert(shown('Stacks combined') and #sent==1)")
l=move_setup(); run(l,"right_click='Copper Ore##7_1'; click='Stack bag'; tick(4); tick(4); assert(#sent==0 and shown('No combinable'))")
# Different instance extra data is never treated as a mergeable pair.
l=move_setup(); run(l,"slots[7][2]={Id=102,Count=1,Flags=0,Price=0,Extra=string.rep('x',28)}; counts[7]=2; right_click='Copper Ore##7_1'; click='Stack bag'; tick(4); tick(4); assert(#sent==0)")
# Auto-stacking is opt-in and only runs after both legs finish at the final destination.
l=bridge_setup(); run(l,"current_profile.auto_stack=true; first_done(); assert(#sent==2); slots[0][2].Count=12; slots[6][1]={Id=102,Count=1,Flags=0,Price=0,Extra=string.rep(string.char(0),28)}; slots[6][2]={Id=102,Count=2,Flags=0,Price=0,Extra=string.rep(string.char(0),28)}; counts[6]=2; tick(6); tick(6.25); assert(#sent==3 and sent[3].id==0x03A and sent[3].data[5]==6); tick(7); assert(#sent==3)")
l=bridge_setup(); run(l,"assert(current_profile.auto_stack==false); first_done(); slots[0][2].Count=12; slots[6][1]={Id=102,Count=1,Flags=0,Price=0,Extra=string.rep(string.char(0),28)}; slots[6][2]={Id=102,Count=2,Flags=0,Price=0,Extra=string.rep(string.char(0),28)}; counts[6]=2; tick(6); tick(6.25); tick(7); assert(#sent==2)")
# New intermediate slot is identified by its actual slot number, not the original slot.
l=bridge_setup(); run(l,"slots[7]={}; counts[7]=0; slots[0][5]={Id=102,Count=3,Flags=0,Price=0,Extra=string.rep(string.char(0),28)}; counts[0]=3; tick(5); tick(5.25); assert(#sent==2 and sent[2].data[11]==5)")
# A busy/equipped intermediate item cannot be forwarded.
l=bridge_setup(); run(l,"equipment[0]=2; first_done(); tick(6); assert(#sent==1 and shown('Unequip'))")
# Zoning between the legs clears work and cannot resume the route later.
l=bridge_setup(); run(l,"zoning=1; tick(4.5); zoning=0; tick(5); tick(8); assert(#sent==1)")

# A send exception may mean the request was queued: never issue a replacement.
l=bridge_setup(); run(l,"fail_send_at=2; first_done(); assert(#sent==2); tick(6); tick(14); assert(#sent==2 and shown('not confirmed'))")
l=move_setup(); run(l,"slots[7][2]={Id=102,Count=1,Flags=0,Price=0,Extra=string.rep(string.char(0),28)}; counts[7]=2; fail_send_at=1; right_click='Copper Ore##7_1'; click='Stack bag'; tick(4); tick(4); assert(#sent==1 and shown('outcome unknown')); tick(13); assert(#sent==1 and shown('Stacking not confirmed'))")

# Ownership grouping uses ID, includes all slots, and never modifies the snapshot.
l=setup(); run(l,"local data=model.scan(inv,resources); local g=model.ownership(data,'knuckles',0); assert(#g==1 and g[1].total==2 and #g[1].rows==2 and #g[1].locations==2); assert(g[1].locations[1].name=='Inventory' and g[1].locations[2].name=='Safe'); assert(data[1].items[1].count==1)")
l=setup(); run(l,"resource_data[102].Name[1]='Lgn. Knuckles'; local g=model.ownership(model.scan(inv,resources),'',0); assert(#g==2 and g[1].id~=g[2].id)")
l=setup(); run(l,"slots[0][3]={Id=102,Count=1,Flags=0,Price=0,Extra=string.rep(string.char(0),28)}; counts[0]=3; local g=model.ownership(model.scan(inv,resources),'copper',2); assert(#g==1 and g[1].total==13 and #g[1].locations==1 and #g[1].rows==2); assert(#model.ownership(model.scan(inv,resources),'copper',1)==0)")
l=setup(); run(l,"resource_data[101].Flags=0x800; resource_data[101].StackSize=1; slots[1][4].Extra=string.rep('x',28); local g=model.ownership(model.scan(inv,resources),'',3); assert(#g==1 and g[1].id==101 and g[1].variant_count==2 and g[1].rows[1].variant~=g[1].rows[2].variant); assert(#model.ownership(model.scan(inv,resources),'knuckles',2)==0)")
l=setup(); run(l,"counts[1]=2; local g=model.ownership(model.scan(inv,resources),'knuckles',0); assert(#g==1 and g[1].total==1 and #g[1].locations==1); assert(#model.ownership(model.scan(inv,resources),'knuckles',1)==0); assert(#model.ownership(nil,'',0)==0)")
for query in ['101',"legionnaire's knuckles",'knuckles legion']:
    l=setup(); l.globals().q=query; run(l,"local g=model.ownership(model.scan(inv,resources),q,0); assert(#g==1 and g[1].total==2)")
for column in range(3):
    for desc in [True,False]:
        l=setup(); run(l,f"local g=model.ownership(model.scan(inv,resources),'',0); model.sort_ownership(g,{column},{str(desc).lower()}); local function val(v) if {column}==1 then return v.total elseif {column}==2 then return #v.locations else return v.name:lower() end end; assert({str(desc).lower()} and val(g[1])>=val(g[2]) or not {str(desc).lower()} and val(g[1])<=val(g[2]))")
# UI expansion preserves individual slots, filter/search are independent, no packets.
l=addon_setup(); run(l,"active_tab='Ownership'; resource_data[101].Flags=0x800; resource_data[101].StackSize=1; slots[1][4].Extra=string.rep('x',28); cmd('/fms'); tick(0); tick(3); assert(shown('Inventory: 1 | Safe: 1')); click='[+] Lgn. Knuckles##Owned101'; tick(4); assert(shown('Slot 1 | ID 101 | Data variant 1') and shown('Slot 4 | ID 101 | Data variant 2')); open_combo='Show##Ownership'; click='Equipment copies##OwnershipFilter'; tick(4); open_combo=nil; assert(shown('1 item types') and not shown('Copper Ore')); edit_search={label='##OwnershipSearch',value='missing'}; tick(4); assert(shown('No matches')); assert(#sent==0)")
l=addon_setup(); run(l,"active_tab='Ownership'; cmd('/fms'); tick(0); tick(3); zoning=1; tick(4); assert(not shown('Lgn. Knuckles')); zoning=0; tick(5); tick(8); assert(shown('Lgn. Knuckles')); hide_child=true; tick(9); assert(#sent==0)")

# The removed Move tab cannot be opened, and ordinary left-clicks do not open actions.
l=addon_setup(); run(l,"cmd('/fms'); tick(0); tick(3); assert(not tab_names.Move); click='Copper Ore##0_2'; tick(4); assert(popup==nil and #sent==0); right_click='Copper Ore##0_2'; tick(4); assert(popup=='Item actions' and #sent==0)")
# Explicit dismiss closes the popup without requesting anything.
l=move_setup(); run(l,"click='Clear selection'; tick(4); assert(popup==nil and #sent==0); click='Move item'; tick(5); assert(#sent==0)")
# Opening another copy resets quantity and binds its precise source slot.
l=move_setup(); run(l,"click='All'; tick(4); popup=nil; right_click='Copper Ore##0_2'; tick(4); open_combo='Move to'; click='Case'; tick(4); open_combo=nil; click='Move item'; tick(4); assert(#sent==1 and sent[1].data[9]==0 and sent[1].data[11]==2 and sent[1].data[5]==1)")
# A pending transfer cannot open another menu or start a sort.
l=move_setup(); run(l,"click='Move item'; tick(4); right_click='Copper Ore##0_2'; tick(5); click='Stack bag'; tick(5); assert(popup==nil and #sent==1)")
# A stale source is rejected without closing the menu or issuing a request.
l=move_setup(); run(l,"slots[7][1].Count=2; click='Move item'; tick(4); tick(4); assert(#sent==0 and popup=='Item actions' and shown('Selected slot changed'))")
# New commands and the legacy alias all reach the renamed addon.
l=addon_setup(); run(l,"assert(addon.name=='invmaster'); assert(cmd('/im')); tick(0); tick(3); assert(shown('Right-click an item')); assert(cmd('/im')); tick(4); assert(#ui==0); assert(cmd('/invmaster find copper')); tick(4); assert(shown('Copper Ore')); assert(cmd('/fms refresh')); assert(not cmd('/somethingelse'))")
# Popup uses a fixed width on every frame and on reopening for another item.
l=move_setup(); run(l,"for i=1,10 do tick(4+i/30); assert(next_window_size[1]==440) end; popup=nil; right_click='Lgn. Knuckles##1_4'; tick(5); assert(popup=='Item actions' and next_window_size[1]==440 and #sent==0)")

# Reload outdoors: Satchel access comes from usable SDK capacity, without any packets.
l=addon_setup(); run(l,"counts[5]=1; slots[5][1]={Id=102,Count=2,Flags=0,Price=0,Extra=string.rep(string.char(0),28)}; cmd('/im'); tick(0); tick(3); right_click='Copper Ore##5_1'; tick(4); click='All'; tick(4); click='Move item'; tick(4); assert(#sent==1 and sent[1].data[9]==5 and sent[1].data[10]==0 and sent[1].data[5]==2)")
l=addon_setup(); run(l,"cmd('/im'); tick(0); tick(3); right_click='Copper Ore##0_2'; tick(4); open_combo='Move to'; click='Satchel'; tick(4); open_combo=nil; click='Move item'; tick(4); assert(#sent==1 and sent[1].data[10]==5)")
for capacity in ['0','81','-1','0/0',"'bad'"]:
    l=access_setup(); run(l,f"local b=access:allowed('Alice:100:1',{capacity}); assert(not b[5] and not b[4]); assert(access:reason('Alice:100:1',5):find('Wait for inventory'))")
l=access_setup(); run(l,"local b=access:allowed('Alice:100:1',80); assert(b[5] and not b[4]); access:observe(0x00A,zone_packet(false)); assert(access:allowed('Alice:100:1',80)[5]); access:observe(0x01C,wire(0x48,{[9]=81})); assert(not access:allowed('Alice:100:1',80)[5])")
# Category filters: client slots, pinned non-equipment facts, unknowns and UI persistence.
for mask, expected in [(1,'weapons'),(4,'ranged'),(8,'ammo'),(2,'shield'),(16,'head'),(32,'body'),(64,'hands'),(128,'legs'),(256,'feet'),(512,'neck'),(1024,'waist'),(2048,'ears'),(4096,'ears'),(8192,'rings'),(16384,'rings'),(32768,'back')]:
    l=setup(); l.globals().mask=mask; l.globals().expected=expected
    run(l, "local c=require('item_categories'); assert(c.classify({id=65535,item_type=5,equip_slots=mask})==expected)")
for item_id, expected in [(640,'materials'),(688,'materials'),(4096,'crystals'),(4504,'food'),(4401,'fish'),(65535,'other')]:
    l=setup(); l.globals().item_id=item_id; l.globals().expected=expected
    run(l, "local c=require('item_categories'); assert(c.classify({id=item_id,item_type=1})==expected)")
l=setup(); run(l, "local c=require('item_categories'); assert(c.classify({id=640,item_type=5,equip_slots=1024})=='waist'); assert(c.classify({id=65535,item_type=10})=='furniture'); assert(c.classify({item_type=5,equip_slots=0/0})=='equipment'); local f=c.normalize({fish=false,materials='bad'}); assert(f.fish==false and f.materials and f.other); assert(c.normalize(false).fish)")
l=setup(); run(l, "resource_data[101].Type=5; resource_data[101].Slots=1024; local s=model.scan(inv,resources); assert(s[1].items[1].equip_slots==1024); local rows,n=model.search(s,'knuckles',nil,{waist=false}); assert(#rows==0 and n==0); assert(#model.ownership(s,'knuckles',0,{waist=false})==0); assert(#model.ownership(s,'knuckles',0,{waist=true})==1); assert(#model.search(s,'knuckles',1,{waist=true})==1)")
l=addon_setup(); run(l, "resource_data[101].Type=5; resource_data[101].Slots=1024; cmd('/im'); tick(0); tick(3); open_combo='Categories##Items'; toggle_checkbox='Waist##Items'; tick(4); assert(not current_profile.categories.waist and saves==1); assert(shown('1 matching slots')); active_tab='Ownership'; tick(5); assert(not shown('Lgn. Knuckles')); open_combo='Categories##Ownership'; click='All##Ownership'; tick(6); assert(current_profile.categories.waist and saves==2 and shown('Lgn. Knuckles')); click='None##Ownership'; tick(7); assert(shown('0 item types') and saves==3); active_tab=nil; open_combo='Categories##Items'; click='All##Items'; tick(8); assert(shown('3 matching slots')); assert(#sent==0)")
l=addon_setup(); run(l, "current_profile.categories.waist=false; switch_profile(current_profile); assert(not current_profile.categories.waist); local new={}; switch_profile(new); assert(new.categories.waist and current_profile.categories.waist==false)")

# Customization: persistent item-ID membership, read-only views and UI edits.
l=addon_setup(); run(l, "local c=require('customization'); local d=c.normalize(nil); assert(next(d.favorites)==nil and #d.bags==0); assert(c.rename(d,nil,' Ore ')); assert(d.bags[1].name=='Ore'); assert(not c.rename(d,nil,'ore')); assert(not c.rename(d,nil,'  ')); assert(not c.rename(d,nil,'Favourites')); assert(c.rename(d,1,'Metals')); assert(d.bags[1].name=='Metals')")
l=addon_setup(); run(l, "local c=require('customization'); local d=c.normalize({favorites={['101']='Knuckles',['bad']='Bad',['-1']='No'},bags={{name='Ore',items={['102']='Copper Ore'}},false}}); assert(d.favorites['101']=='Knuckles' and d.favorites.bad==nil and d.favorites['-1']==nil); assert(#d.bags==1 and d.bags[1].items['102']=='Copper Ore'); local s=model.scan(inv,resources); local rows=c.rows(s,d.favorites,'knuckles'); assert(#rows==1 and rows[1].total==2 and rows[1].locations=='Inventory: 1 | Safe: 1'); rows=c.rows({},d.favorites,''); assert(#rows==1 and rows[1].total==0); assert(#c.rows(s,d.favorites,'missing')==0); assert(d.favorites['101']=='Knuckles')")
l=addon_setup(); run(l, "cmd('/im'); tick(0); tick(3); right_click='Lgn. Knuckles##0_1'; toggle_checkbox='Favourite item type'; tick(4); assert(current_profile.customization.favorites['101']=='Lgn. Knuckles'); assert(saves==1 and #sent==0); popup=nil; active_tab='Customization'; tick(5); assert(shown('Lgn. Knuckles') and shown('Inventory: 1 | Safe: 1')); click='Remove##Collection101'; tick(6); assert(current_profile.customization.favorites['101']==nil and #sent==0)")
l=addon_setup(); run(l, "cmd('/im'); tick(0); tick(3); active_tab='Customization'; edit_search={label='##VirtualName',value='Ore'}; click='Create bag'; tick(4); assert(#current_profile.customization.bags==1 and saves==1); edit_search={label='##CollectionAdd',value='copper'}; click='+ Copper Ore##AddCollection102'; tick(5); assert(current_profile.customization.bags[1].items['102']=='Copper Ore'); tick(6); assert(shown('Inventory: 12')); edit_search={label='##VirtualName',value='Crafting'}; click='Rename bag'; tick(7); assert(current_profile.customization.bags[1].name=='Crafting'); click='Delete virtual bag'; tick(8); assert(#current_profile.customization.bags==1); click='Cancel deletion'; tick(9); assert(#current_profile.customization.bags==1); click='Delete virtual bag'; tick(10); click='Confirm deletion'; tick(11); assert(#current_profile.customization.bags==0 and #sent==0)")
l=addon_setup(); run(l, "current_profile.customization.bags={{name='Ore',items={}}}; cmd('/im'); tick(0); tick(3); right_click='Copper Ore##0_2'; open_combo='Virtual bags'; toggle_checkbox='Ore##Virtual1'; tick(4); assert(current_profile.customization.bags[1].items['102']=='Copper Ore'); toggle_checkbox='Ore##Virtual1'; tick(5); assert(current_profile.customization.bags[1].items['102']==nil and #sent==0)")
l=addon_setup(); run(l, "current_profile.customization.favorites['101']='Knuckles'; current_profile.customization.bags={{name='Ore',items={['102']='Copper Ore'}}}; switch_profile(current_profile); assert(current_profile.customization.favorites['101']=='Knuckles' and current_profile.customization.bags[1].items['102']=='Copper Ore'); local bob={}; switch_profile(bob); assert(next(bob.customization.favorites)==nil and #bob.customization.bags==0); assert(current_profile.customization.favorites['101']=='Knuckles')")
l=addon_setup(); run(l, "current_profile.customization.favorites['101']='Knuckles'; current_profile.categories=require('item_categories').normalize(); for k in pairs(current_profile.categories) do current_profile.categories[k]=false end; cmd('/im'); tick(0); tick(3); active_tab='Customization'; tick(4); assert(shown('Inventory: 1 | Safe: 1')); counts[0]=0; counts[1]=0; slots[0]={}; slots[1]={}; cmd('/im refresh'); tick(5); assert(shown('Not in readable bags') and current_profile.customization.favorites['101']=='Knuckles' and #sent==0)")

# Multi-stack withdrawals, confirmations and cancellation.
def withdraw_setup():
    l=addon_setup()
    run(l, """
    slots[6]={[1]={Id=102,Count=3,Flags=0,Price=0,Extra=string.rep(string.char(0),28)}}; capacity[6]=80; counts[6]=1
    slots[7]={[1]={Id=102,Count=4,Flags=0,Price=0,Extra=string.rep(string.char(0),28)}}; capacity[7]=80; counts[7]=1
    allowed={[0]=true,[6]=true,[7]=true}; owner='Alice'; confirmed=0
    w=require('withdraw').new({now=function() return now end,context=function() return owner end,
      scan=function() return model.scan(inv,resources) end,access=function() return allowed end,
      equipped=function() return false end,changed=function() confirmed=confirmed+1 end,
      send=function(p) sent[#sent+1]=p; if fail_send then error('uncertain') end end})
    function receive(bag,q)
      local v=slots[bag][1]; v.Count=v.Count-q; if v.Count==0 then slots[bag][1]=nil; counts[bag]=0 end
      slots[0][2].Count=slots[0][2].Count+q
    end
    """)
    return l
l=withdraw_setup(); run(l, "assert(w:start(102,5)); assert(#sent==1 and sent[1][5]==3); receive(6,3); now=1; w:tick(); assert(#sent==1); now=1.3; w:tick(); assert(#sent==2 and sent[2][5]==2); receive(7,2); now=2; w:tick(); now=2.3; w:tick(); assert(not w.active and not w.pending and confirmed==2 and w.message:find('5 items'))")
for mutation in ["allowed[7]=false", "slots[7][1].Count=3", "slots[7][1].Extra=string.rep('x',28)", "capacity[0]=counts[0]"]:
    l=withdraw_setup(); run(l, "assert(w:start(102,7)); receive(6,3); "+mutation+"; now=1; w:tick(); now=1.3; w:tick(); assert(#sent==1 and not w.active)")
for action in ["w:cancel()", "owner=nil", "now=9"]:
    l=withdraw_setup(); run(l, "assert(w:start(102,7)); "+action+"; w:tick(); receive(6,3); owner='Alice'; now=10; w:tick(); now=10.3; w:tick(); assert(#sent==1 and not w.active)")
l=withdraw_setup(); run(l, "fail_send=true; assert(w:start(102,7)); now=9; w:tick(); now=20; w:tick(); assert(#sent==1 and w.pending and not w.active)")
l=withdraw_setup(); run(l, "assert(not w:start(102,8)); assert(#sent==0); allowed[6]=false; assert(not w:start(102,5)); assert(#sent==0)")
l=withdraw_setup(); run(l, "current_profile.customization.favorites['102']='Copper Ore'; cmd('/im'); tick(0); tick(3); active_tab='Customization'; right_click='Copper Ore##Withdraw102'; tick(4); assert(shown('Available outside Inventory: 7')); click='All##Withdraw'; tick(5); click='Withdraw to Inventory'; tick(6); assert(#sent==1 and sent[1].data[5]==3)")
# Currency packet decoding distinguishes unknown, zero and 16-bit values.
l=addon_setup(); l.execute(PACKET_HELPERS); run(l, "local c=require('currency'); assert(c.decode('')==nil and c.decode(wire(0xF7))==nil); local d=c.decode(wire(0xF8,{[0x10]=54,[0x12]=14,[0x14]=18,[0xE8]={190,1},[0xF0]=105,[0xF6]=7})); assert(d.seals[1]==54 and d.seals[5]==0 and d.crystals[1]==446 and d.crystals[5]==105 and d.crystals[8]==7)")
l=addon_setup(); l.execute(PACKET_HELPERS); run(l, "local c=require('currency'); local captured; local original=c.render; c.render=function(d) captured=d end; cmd('/im'); active_tab='Currency'; tick(0); tick(3); assert(captured==nil); callbacks.packet_in({id=0x113,data=wire(0xF8,{[0x10]=54})}); tick(4); assert(captured.seals[1]==54 and captured.time); callbacks.packet_in({id=0x113,data=wire(0xF8,{[0x10]=99}),injected=true}); tick(5); assert(captured.seals[1]==54); callbacks.packet_in({id=0x00B,data=''}); tick(6); assert(captured.seals[1]==54); assert(#sent==0)")

# Crystal tracing is passive, bounded and restricted to identified Moogle menus.
l=addon_setup(); l.execute(PACKET_HELPERS); run(l, "local writes={}; local t=require('crystal_trace').new({now=function() return now end,name=function(i) return i==12 and 'Ephemeral Moogle' or 'Other NPC' end,write=function(s) writes[#writes+1]=s; return true end}); assert(t:start()); t:observe('in',0x034,wire(0x30,{[4]=100,[0x28]=11})); t:observe('out',0x05B,wire(0x14,{[4]=100})); assert(#writes==1); t:observe('in',0x034,wire(0x30,{[4]=100,[0x28]=12})); t:observe('out',0x05B,wire(0x14,{[4]=99})); assert(#writes==2); t:observe('out',0x05B,wire(0x14,{[4]=100})); assert(#writes==3); now=61; t:observe('out',0x05B,wire(0x14,{[4]=100})); assert(#writes==3 and not t.deadline and #sent==0)")
l=addon_setup(); l.execute(PACKET_HELPERS); run(l, "local n=0; local t=require('crystal_trace').new({now=function() return now end,name=function() return 'Ephemeral Moogle' end,write=function() n=n+1; return true end}); t:start(); t:observe('in',0x034,'short'); assert(n==1); t:observe('in',0x034,wire(0x30,{[4]=100,[0x28]=12})); for i=1,20 do t:observe('out',0x05B,wire(0x14,{[4]=100})) end; assert(n==13 and not t.deadline); t:start(); t:observe('in',0x00B,''); assert(not t.deadline)")

# Calibrated Ephemeral Moogle controller: captured wire response and failures.
def crystal_setup():
    l=addon_setup(); l.execute(PACKET_HELPERS)
    run(l, """
    npc={key='Alice:100:234',id=0x010EA17D,index=0x17D,zone=234}; now=0; changed=0
    bag={state='Client snapshot',free=10,items={}}; crystal_sent={}; key=npc.key
    cw=require('crystal_withdraw').new({now=function() return now end,key=function() return key end,
      target=function() return npc end,inventory=function() return bag end,
      changed=function() changed=changed+1 end,
      send=function(id,p) crystal_sent[#crystal_sent+1]={id=id,data=p}; if send_error then error('uncertain') end end})
    function menu(balance)
      return {id=0x034,data=wire(0x30,{[4]={0x7D,0xA1,0x0E,0x01},[8]=balance or 190,[0x28]={0x7D,1},[0x2A]=234,[0x2C]={0x69,2}})}
    end
    """); return l
for q in [1,12,25]:
    l=crystal_setup(); l.globals().q=q
    run(l, "assert(cw:start(1,q)); assert(#crystal_sent==1 and crystal_sent[1].id==0x01A and #crystal_sent[1].data==28); local e=menu(); cw:observe(e); assert(e.blocked and #crystal_sent==2); local p=crystal_sent[2].data; assert(crystal_sent[2].id==0x05B and p[9]==q and p[10]==0 and p[11]==1 and p[12]==64 and p[13]==125 and p[14]==1 and p[15]==0 and p[17]==234 and p[19]==105 and p[20]==2); assert(not cw:start(1,q)); bag.items={{id=4096,count=q%12},{id=4104,count=math.floor(q/12)}}; now=1; cw:tick(); assert(cw.pending); now=1.3; cw:tick(); assert(not cw.pending and changed==1 and #crystal_sent==2)")
for mutation in ["e.id=0x032", "e.data=wire(0x30)", "e.data='short'", "npc=nil", "now=9", "bag.free=0"]:
    l=crystal_setup(); run(l, "assert(cw:start(1,12)); local e=menu(); "+mutation+"; cw:observe(e); assert(not e.blocked and #crystal_sent==1 and not cw.pending)")
l=crystal_setup(); run(l, "assert(cw:start(1,12)); local e=menu(11); cw:observe(e); assert(not e.blocked and #crystal_sent==1)")
for mutation in ["npc=nil", "npc.zone=235", "bag.free=0", "bag.state='Updating'"]:
    l=crystal_setup(); run(l, mutation+"; assert(not cw:start(1,12)); assert(#crystal_sent==0)")
l=crystal_setup(); run(l, "assert(cw:start(1,12)); local e=menu(); e.injected=true; cw:observe(e); assert(#crystal_sent==1 and not e.blocked); now=9; cw:tick(); assert(not cw.pending); e.injected=false; cw:observe(e); assert(#crystal_sent==1 and not e.blocked)")
l=crystal_setup(); run(l, "assert(cw:start(1,12)); cw:manual_action({id=0x05B}); local e=menu(); cw:observe(e); assert(not e.blocked and #crystal_sent==1)")
l=crystal_setup(); run(l, "assert(cw:start(1,12)); cw:observe(menu()); now=11; cw:tick(); assert(cw.pending and cw.message:find('not confirmed') and #crystal_sent==2); assert(not cw:start(1,12)); key='Bob'; bag.items={{id=4104,count=1}}; now=12; cw:tick(); assert(cw.pending and changed==0)")
l=crystal_setup(); run(l, "send_error=true; assert(cw:start(1,12)); cw:observe(menu()); now=20; cw:tick(); assert(#crystal_sent==2 and cw.pending)")
l=crystal_setup(); run(l, "local c=require('crystal_withdraw'); assert(c.space(1)==1 and c.space(12)==1 and c.space(25)==2 and c.space(145)==2); assert(not cw:start(1,0)); assert(not cw:start(9,12)); assert(not cw:start(1,0/0)); assert(#crystal_sent==0)")

l=addon_setup(); l.execute(PACKET_HELPERS); run(l, "zone=234; target_index=381; target_id=0x010EA17D; target_name='Ephemeral Moogle'; target_distance=9; cmd('/im'); tick(0); tick(3); active_tab='Currency'; right_click='Fire: --##Crystal1'; tick(4); assert(shown('Fire -> Inventory')); edit_interval=12; tick(5); assert(shown('1 cluster(s) + 0 crystal(s)')); click='Withdraw crystals'; tick(6); assert(#sent==1 and sent[1].id==0x01A); local e={id=0x034,data=wire(0x30,{[4]={0x7D,0xA1,0x0E,1},[8]=190,[0x28]={0x7D,1},[0x2A]=234,[0x2C]={0x69,2}})}; callbacks.packet_in(e); assert(e.blocked and #sent==2 and sent[2].id==0x05B and sent[2].data[9]==12)")

# Named Shami trace remains read-only and cannot capture another NPC's response.
l=addon_setup(); l.execute(PACKET_HELPERS); run(l, "local lines={}; local t=require('crystal_trace').new({npc_name='shami',label='manual Shami menu',duration=120,now=function() return now end,name=function(i) return i==22 and 'Shami' or 'Ephemeral Moogle' end,write=function(s) lines[#lines+1]=s; return true end}); assert(t:start()); assert(lines[1]=='BEGIN manual Shami menu trace'); t:observe('in',0x034,wire(0x30,{[4]=100,[0x28]=12})); t:observe('out',0x05B,wire(0x14,{[4]=100})); assert(#lines==1); t:observe('in',0x034,wire(0x30,{[4]=101,[0x28]=22,[0x2A]=246,[0x2C]={66,1}})); now=90; t:observe('out',0x05B,wire(0x14,{[4]=101})); assert(#lines==3); now=121; t:observe('out',0x05B,wire(0x14,{[4]=101})); assert(#lines==3 and not t.deadline and #sent==0)")

# Shami request/confirmation state machine and calibrated option bytes.
def shami_setup():
    l=addon_setup(); l.execute(PACKET_HELPERS)
    run(l, """
    npc={key='Alice:100:246',id=0x010F6049,index=73,zone=246}; key=npc.key; shami_sent={}; changed=0
    data={{id=0,state='Client snapshot',free=10,items={}}}
    sc=require('shami').new({now=function() return now end,key=function() return key end,
      target=function() return npc end,scan=function() return data end,
      changed=function() changed=changed+1 end,
      send=function(id,p) shami_sent[#shami_sent+1]={id=id,data=p}; if fail_send then error('uncertain') end end})
    function smenu()
      return {id=0x034,data=wire(0x30,{[4]={0x49,0x60,0x0F,1},[8]=62,[10]=30,[12]=79,[14]=32,[16]=20,[0x28]=73,[0x2A]=246,[0x2C]={66,1}})}
    end
    """); return l
for seal in range(1,6):
    l=shami_setup();l.globals().seal=seal
    run(l, "local plan=require('shami').plan('withdraw',seal,1); assert(sc:start('withdraw',seal,1)); local e=smenu(); sc:observe(e); assert(e.blocked and #shami_sent==2); local packet=shami_sent[2].data; assert(packet[9]+packet[10]*256==plan.option and packet[11]==0 and packet[12]==0 and packet[13]==73 and packet[17]==246 and packet[19]==66 and packet[20]==1); if seal==1 then assert(packet[9]==254 and packet[10]==1) end; data[1].items={{id=plan.item,count=1}}; now=1; sc:tick(); now=1.3; sc:tick(); assert(not sc.pending and changed==1)")
for orb in range(1,16):
    l=shami_setup();l.globals().orb_index=orb
    run(l, "local p=require('shami').plan('orb',orb_index,1); assert(p and p.count==1 and p.slots==1); assert(sc:start('orb',orb_index,1)); local e=smenu(); local bytes={}; for i=1,#e.data do bytes[i]=e.data:byte(i) end; bytes[9+(p.seal-1)*2]=200; e.data=string.char(unpack(bytes)); sc:observe(e); assert(e.blocked and #shami_sent==2 and shami_sent[2].data[9]==orb_index and shami_sent[2].data[10]==0); data[1].items={{id=p.item,count=1}}; now=1; sc:tick(); now=1.3; sc:tick(); assert(not sc.pending and changed==1)")
for mutation in ["e.data='short'", "e.id=0x032", "e.data=wire(0x30)", "npc=nil", "now=9", "data[1].free=0", "data[1].items={{id=1551,count=1}}", "data[2]={state='Client snapshot',items={{id=1551,count=1}}}"]:
    l=shami_setup();run(l, "assert(sc:start('orb',1,1)); local e=smenu(); "+mutation+"; sc:observe(e); assert(not e.blocked and #shami_sent==1 and not sc.pending)")
l=shami_setup();run(l, "data[2]={state='Client snapshot',items={{id=1551,count=1}}}; assert(not sc:start('orb',1,1) and #shami_sent==0); data[2]=nil; assert(sc:start('orb',9,1)); local e=smenu(); sc:observe(e); assert(not e.blocked and #shami_sent==1 and not sc.pending)")
l=shami_setup();run(l, "assert(sc:start('withdraw',1,1)); local e=smenu(); e.injected=true; sc:observe(e); assert(#shami_sent==1); sc:manual_action({id=0x05B}); e.injected=false; sc:observe(e); assert(not e.blocked and #shami_sent==1)")
l=shami_setup();run(l, "assert(sc:start('orb',1,1)); fail_send=true; sc:observe(smenu()); now=20; sc:tick(); assert(sc.pending and #shami_sent==2); assert(not sc:start('orb',1,1)); key='Bob'; data[1].items={{id=1551,count=1}}; now=21; sc:tick(); assert(changed==0 and sc.pending)")
l=shami_setup();run(l, "local m=require('shami'); assert(m.plan('withdraw',1,100).slots==2); for _,v in ipairs({0,-1,1.5,10000,math.huge}) do assert(not sc:start('withdraw',1,v)) end; assert(not sc:start('withdraw',1,0/0)); assert(not sc:start('orb',16,1)); assert(#shami_sent==0)")
l=addon_setup();run(l, """zone=246; target_index=73; target_id=0x010F6049; target_name='Shami'; target_distance=9; cmd('/im'); tick(0); tick(3); active_tab='Currency'; currency_subtab='Seals & Crests'; right_click="Beastmen's Seals: --##Seal1"; tick(4); open_combo='Orb'; click='Cloudy Orb (20)##Orb1'; tick(5); assert(shown("Cost: 20 Beastmen's Seals for one Cloudy Orb.") and #sent==0); click='Review exchange'; tick(6); assert(#sent==0); click='Confirm: spend 20 for Cloudy Orb'; tick(7); assert(#sent==1 and sent[1].id==0x01A)""")

# Nearby NPC discovery: radius, visibility, nearest, cache and pinned identity.
l=addon_setup();run(l, "local entities={[5]={name='Shami',id=5,distance=36,flags=512},[9]={name='Shami',id=9,distance=4,flags=512},[2]={name='Other',id=2,distance=1,flags=512}}; local finder=require('nearby_npc').new({now=function() return now end,read=function(i) return entities[i] end}); assert(finder:find('Shami','A',nil,true).id==9); local pinned={index=9,id=9,key='A'}; entities[5].distance=1; assert(finder:find('Shami','A',pinned).id==9); entities[9].id=99; assert(finder:find('Shami','A',pinned)==nil); entities[9]=nil; assert(finder:find('Shami','A',nil,true).id==5); entities[5].distance=36.01; assert(finder:find('Shami','A',nil,true)==nil); entities[5].distance=36; entities[5].flags=512+16384; assert(finder:find('Shami','A',nil,true)==nil); entities[5].flags=512; entities[5].distance=0/0; assert(finder:find('Shami','A',nil,true)==nil); assert(finder:find('Shami','B',pinned)==nil)")
for name, zone_id, index, tab, label, button in [('Shami',246,73,'Seals & Crests',"Beastmen's Seals: --##Seal1",'Withdraw seals / crests'),('Ephemeral Moogle',234,381,'Crystals','Fire: --##Crystal1','Withdraw crystals')]:
    l=addon_setup(); l.globals().test_name=name; l.globals().test_zone=zone_id; l.globals().test_index=index; l.globals().test_tab=tab; l.globals().test_label=label; l.globals().test_button=button
    run(l, "zone=test_zone; npc_index=test_index; target_index=0; target_name=test_name; target_id=123456; target_distance=36; cmd('/im'); tick(0); tick(3); active_tab='Currency'; currency_subtab=test_tab; right_click=test_label; tick(4); click=test_button; tick(5); assert(#sent==1 and sent[1].id==0x01A); local p=sent[1].data; assert(p[9]+p[10]*256==npc_index and target_index==0)")
l=addon_setup();l.execute(PACKET_HELPERS);run(l, "cmd('/im'); tick(0); tick(3); active_tab='Currency'; click='Refresh balances'; tick(4); assert(#sent==1 and sent[1].id==0x10F and #sent[1].data==4); click='Refresh balances'; tick(5); assert(#sent==1); callbacks.packet_in({id=0x113,data=wire(0xF8,{[0x10]=41,[0xE8]=165})}); tick(6); assert(shown('Fire: 165') and not shown('Requesting fresh')); zoning=1; click='Refresh balances'; tick(7); assert(#sent==1)")
l=addon_setup();run(l, "cmd('/im'); tick(0); tick(3); active_tab='Currency'; click='Refresh balances'; tick(4); tick(15); assert(#sent==1 and shown('No fresh balances received')); click='Refresh balances'; tick(16); assert(#sent==2)")

# Saved currency snapshots survive zones/reload, remain isolated, and reject corruption.
l=addon_setup();l.execute(PACKET_HELPERS);run(l, "cmd('/im'); tick(0); tick(3); active_tab='Currency'; callbacks.packet_in({id=0x113,data=wire(0xF8,{[0xE8]=187,[0x10]=41})}); tick(4); assert(shown('Fire: 187') and current_profile.currency_cache.seals[1]==41); zoning=1; tick(5); zoning=0; zone=246; tick(6); tick(9); assert(shown('Fire: 187')); switch_profile(current_profile); cmd('/im'); tick(10); assert(shown('Fire: 187') and shown('Last known balances')); local bob={}; settingsmock.name='Bob'; settingsmock.server_id=200; player={Name='Bob',ServerId=200}; switch_profile(bob); cmd('/im'); tick(11); assert(not shown('Fire: 187') and shown('No saved balances'))")
l=addon_setup();l.execute(PACKET_HELPERS);run(l, "local c=require('currency'); local d=c.decode(wire(0xF8)); d.time=123; d.owner_name='Alice'; d.owner_id=100; local v=c.restore(d,'Alice',100); assert(v and v.crystals[1]==0); v.crystals[1]=7; assert(d.crystals[1]==0); assert(c.restore(d,'Bob',100)==nil); d.seals[5]=nil; assert(c.restore(d,'Alice',100)==nil); d.seals[5]=0/0; assert(c.restore(d,'Alice',100)==nil)")
l=addon_setup();l.execute(PACKET_HELPERS);run(l, """zone=246; npc_index=73; target_name='Shami'; target_id=0x010F6049; target_distance=9; cmd('/im'); tick(0); tick(3); callbacks.packet_in({id=0x113,data=wire(0xF8,{[0x10]=41})}); active_tab='Currency'; currency_subtab='Seals & Crests'; right_click="Beastmen's Seals: 41##Seal1"; tick(4); click='Withdraw seals / crests'; tick(5); callbacks.packet_in({id=0x034,data=wire(0x30,{[4]={73,96,15,1},[8]=41,[0x28]=73,[0x2A]=246,[0x2C]={66,1}})}); slots[0][3]={Id=1126,Count=1,Flags=0,Price=0,Extra=string.rep(string.char(0),28)}; counts[0]=3; tick(6); tick(6.3); assert(#sent==3 and sent[3].id==0x10F and shown("Beastmen's Seals: 41")); tick(7); assert(#sent==3); callbacks.packet_in({id=0x113,data=wire(0xF8,{[0x10]=40})}); tick(8); assert(shown("Beastmen's Seals: 40") and current_profile.currency_cache.seals[1]==40)""")

# Optional monitor preserves bag choices, uses current snapshots, and navigates to bags.
l=addon_setup();run(l, "local m=require('bag_monitor'); local d=m.normalize(nil); assert(not d.enabled and d.warning==5 and d.bags['0'] and d.bags['9'] and not d.bags['2']); local saved=m.normalize({enabled=true,warning=500,bags={['0']=false,['2']=true}}); assert(saved.enabled and saved.warning==80 and not saved.bags['0'] and saved.bags['2']); assert(m.normalize({warning=0/0}).warning==5); assert(m.level({state='Client snapshot',free=0},5)=='full'); assert(m.level({state='Client snapshot',free=5},5)=='warning'); assert(m.level({state='Client snapshot',free=6},5)=='normal'); assert(m.level({state='Updating',free=0},5)=='unknown')")
l=addon_setup();run(l, "assert(cmd('/im monitor')); tick(0); assert(shown('Waiting for inventory')); tick(3); assert(shown('2/10 | 8 free') and not shown('Right-click an item')); click='Safe##Monitor1'; tick(4); assert(shown('1 matching slots | 1 items')); assert(#sent==0); cmd('/im'); tick(5); assert(shown('2/10 | 8 free')); zoning=1; tick(6); assert(not shown('2/10 | 8 free') and shown('Waiting for inventory'))")
l=addon_setup();run(l, "cmd('/im monitor'); tick(0); tick(3); close_monitor=true; tick(4); assert(not current_profile.monitor.enabled and saves==2); tick(5); assert(#ui==0)")
l=addon_setup();run(l, "current_profile.monitor.enabled=true; current_profile.monitor.bags['0']=false; switch_profile(current_profile); assert(current_profile.monitor.enabled and not current_profile.monitor.bags['0']); local bob={}; switch_profile(bob); assert(not bob.monitor.enabled and bob.monitor.bags['0']); assert(current_profile.monitor.enabled)")

print(f'PASS: {scenarios} scenarios (LuaJIT), including search, UI, access, transfer validation, confirmation and isolation.')
