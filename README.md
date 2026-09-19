# InvMaster v0.14.0

Item search, storage overview and individual transfers for Ashita v4, by DragoHorse.

## Install

Copy `invmaster.lua`, `inventory_model.lua`, `transfer.lua`, `route_transfer.lua`, `stack_sort.lua`, `bag_access.lua`, `ownership_view.lua`, `item_categories.lua`, `category_data.lua`, `customization.lua`, `withdraw.lua`, `prepare_bridge.lua`, `currency.lua`, `crystal_trace.lua`, `crystal_withdraw.lua`, `shami.lua`, `nearby_npc.lua`, `bag_monitor.lua` and the `third_party/` folder into `addons/invmaster/`.
Run `/addon load invmaster`, then `/im`.

CraftMaster 0.4.0 and later can use **Prepare materials** to request missing recipe ingredients
through InvMaster's existing transfer checks. See [the integration notes](docs/craftmaster-preparation.md).
Preparation never starts crafting; existing saved settings and collections are preserved.

## Renaming from FindMyStuff

Unload the old addon with `/addon unload findmystuff`, then load
`/addon load invmaster`. Use `/im` or `/invmaster`; `/fms` remains a compatibility
alias. Do not load both addons together. For manual upgrades, copy the contents
of `config/addons/findmystuff/` into `config/addons/invmaster/` before first load,
without overwriting existing InvMaster profiles. The installed migration already
copied the existing profile. The internal window ID is retained for layout continuity.

## Use

- `/im`: show or hide the window (hidden on load).
- `/im find knuckles`: search and open the window.
- `/im refresh`: request a new client snapshot.
- `/im status`: print current and recorded access state, bag sizes and free slots.

**Items** searches names, full resource names and numeric IDs. Search words can
appear in any order; capitalization and apostrophes are ignored. Results show the
container, quantity and slot. Each occupied slot stays separate, including
same-name items with different augments. Augments are not decoded yet.
Click Item, Location, Qty or Slot to sort; click again to reverse direction.
Drag column boundaries to resize, or drag headers to reorder columns.
Item and Storage table headers remain visible while scrolling.
Quantity and slot sorting are numeric and stay applied after refreshes.

**Storage** shows occupied slots, capacity and free slots for containers returned
by the client. **Settings** can show unavailable containers too. This preference
is saved per character by Ashita's settings library.

## Category filters

Open **Categories** in Items or Ownership and check the types you want to see.
**All** resets the filter; **None** lets you start with just one category.
Both tabs share the choices, saved per character. Searches and totals in these
views reflect the filters; Storage capacity and transfer checks still use all items.

Equipment uses client slot data (including Waist, Earrings and Rings). Materials,
fish, food and other consumables use a bundled category reference; no internet
connection is needed. Acorns, for example, are Food / Ingredients. Unmapped items
remain **Other / Unknown**. Custom server items may differ from the reference.
Filtering only changes the display and never moves items. See Customization for favourites and virtual bags.

## Customization

**Customization** contains Favourites and your own named virtual bags, such as
Ore or Crafting. Create a bag, then search owned items to add them. Alternatively,
right-click an item in **Items** to favourite it or toggle its virtual bags.
An item can belong to several collections.

Collections show total quantities and real bag locations, independent of category
filters. Membership applies to the item ID across all copies, not an individual
stack or augmented piece. Choices are saved per character and stay saved when an
item is absent. Zero means not found in currently readable bags, not proof of
non-ownership. Rename bags, remove memberships, or delete a virtual bag with the
inline confirmation. Collection edits never move or delete game items.

Right-click a collection item to withdraw a quantity or choose **All**, then
**Withdraw to Inventory**. All includes eligible copies outside Inventory, across
accessible bags, including different augments of the same item ID. Each stack
must be confirmed before the next request. Inventory needs free slots; the batch
stops if space, access or source identity changes. **Stop withdrawal** cancels
remaining requests; an already-sent move still completes and is checked. No retries.

## Currency

**Currency > Crystals** displays balances at the Ephemeral Moogle;
**Seals & Crests** displays the five Shami seal/crest balances. Press **Refresh balances** in Currency to request current stored balances. The tab shows
when the snapshot was received. Until then values are unknown (`--`), not zero.
Snapshots are saved per character and remain visible across zoning and reloads,
labelled as last known with their receipt timestamp.
Right-click a seal/crest for Shami withdrawals or orb exchanges. NPC controls are described below.
Client packet compatibility still needs in-game comparison with the Currencies menu.

## Ownership overview

**Ownership** groups readable contents by item ID, showing total quantity, number
of bags and a per-bag breakdown. Click an item to expand every stack/copy with its
bag, quantity and slot. Search accepts the same names and item IDs as Items.
Headers stay visible and can be resized, reordered and clicked to sort.

Use the **In multiple bags**, **Multiple stacks**, or **Equipment copies** filters
to find scattered items. Multiple stacks includes full stacks, so it is not a
promise of recoverable space. Equipment entries retain separate instance data;
expanded copies show data-variant labels. These labels compare raw bytes, not
decoded augments or equipment equivalence. Missing instance data is marked unknown.

Totals describe the logged-in character's currently readable client snapshot;
unavailable/updating bags are excluded. This view does not move or delete items.
Protected items and transfer history remain future work.

## Right-click item actions

In **Items**, right-click an item name to open its actions. Choose an available
destination, set **Quantity** or **All**, then press **Move item**. Opening the
menu does not move anything. All means the selected slot's stack only.
Full/inaccessible destinations remain filtered out. A two-step route is shown
before sending. **Clear selection** or clicking outside dismisses the menu.

**Stack bag** combines compatible stacks in the selected item's source bag.
The shared operation lock prevents another transfer or sort while one is pending.
The old two-pane Move tab has been removed. Ownership, Storage and Settings remain.

## Two-step transfers and stack combining

For example, right-click an Acorn in Locker, choose Sack, set Quantity/All,
and click **Move item**. The addon first moves that
quantity into Inventory, confirms it on two reads, then identifies the received
stack and forwards only the requested quantity. The entire operation shares one
transfer lock. No bulk queue or automatic retry is used.

If the final destination fills, access changes, or the received stack cannot be
identified unambiguously, the addon stops and reports that the items reached
Inventory. A delayed first step also cancels automatic continuation. An uncertain
second step stays locked until confirmed. Do not manually sort or move these bags
while a transfer is pending.

**Stack bag** in the item context menu asks the game to combine compatible partial
stacks in that bag. It works on full bags too. It does not merely sort the displayed
list. The addon waits for matching item totals and fewer occupied slots before
unlocking transfers. An unconfirmed sort is not retried.

Settings offers **Auto-stack destination after transfers**, off by default and
saved per character. It only runs after the complete move is confirmed, never
between the two legs. When no combinable stacks are detected, no sort is sent.

## Data limits

Settings offers a saved per-character refresh interval of 1-60 seconds (default 2).
Snapshots also refresh while the window is hidden; Refresh requests an immediate read.
The header names unavailable, updating and failed containers separately; the
last-read age is not the refresh interval.
After login or zoning there is a short initial wait. Zoning, logout and character
changes discard prior snapshots. Concurrent updates, inconsistent slot counts
and read failures are withheld instead of being reported as empty containers.

A client snapshot is not proof that the server has fully loaded every container,
and seeing contents does not mean a container is accessible for transfers.
Unavailable may mean locked, unsupported or not loaded. No search matches does
not prove that you do not own an item. Zero free slots means the reported occupied
slot count equals the reported capacity; quantities are separate from slot counts.

This version searches only the logged-in character's client data. It does not save
item history or search other characters, delivery boxes, NPC storage or storage
slips. Items only move after an explicit click on Move item. Nothing is used, dropped
or sold. Historical contents and additional transfer routes remain future work.

## Move one item

1. Right-click an item name in the Items table.
2. Choose the destination and quantity, or press **All** for the selected slot's full stack.
3. Click **Move item** and wait for the confirmation message.

Supported containers: **Inventory, Safe, Safe 2, Storage, Locker, Satchel,
Sack, Case and Wardrobes 1-8**, when access is known and the bags are available.
Full destinations are hidden. Wardrobes are offered only for equipment.
If the selected destination becomes unavailable, choose a destination again.

**After loading/reloading, leave and re-enter your Mog House.** The addon learns
home access and unlocks from normal incoming game updates; it does not request
packets or scan memory. Until those updates arrive, Satchel, Sack, Case and Wardrobes 1-2
remain available where consistent bag data permits. Paid wardrobes additionally
require a matching player update showing that wardrobe is enabled.
Safe, Safe 2, Storage and Locker transfers currently require a detected Mog House;
Nomad Moogle access is not included. Temporary and Recycle remain excluded.

The character must be alive and idle. The source slot, ID, count, flags and full
28-byte extra data are rechecked before sending. Equipped, locked, in-use,
bazaared items, furniture and unknown resource/identity data are blocked.
Only one slot is moved at a time, with at least one free destination slot required,
even if merging into an existing stack might work. No bulk moves are performed. Two-step
storage-to-storage moves require space in both Inventory and the destination.

Do not manually reorganize these bags or run another inventory mover during a
pending move. Completion requires matching source/destination quantity changes
on two successive reads. Nonstackable items must retain matching extra data.
These observations are confirmation evidence, not a server transaction receipt.

An unconfirmed move locks further transfers after eight seconds; no retry is
sent. Check both bags before reloading the addon to clear that lock. Late matching
updates can still confirm a pending move. Hiding the window does not cancel a sent
request. Zoning/profile changes clear runtime work without resending it.

## Validation

Current v0.14.0 validation: **346 InvMaster offline scenarios** and **9 CraftMaster
preparation integration tests** pass. LuaJIT syntax and Git whitespace checks pass.
The user confirmed a withdrawal at another Ephemeral Moogle after the popup fix;
the exact location was not recorded. This does not establish every Moogle's live
compatibility. CraftMaster preparation still needs manual in-game validation.
The notes below retain earlier validation history and its then-current limits.

`python test_invmaster.py` requires Python and `lupa` with LuaJIT support.
201 offline scenarios cover search, sorting, refresh intervals, partial reads,
transfer validation, packet layout, confirmations, uncertain sends, timeouts,
reverse routes, bag access, unlock flags, full destination filtering, zoning and character isolation. All transfer requests in tests
are captured by mocks; no game input is sent by the suite.

Search/UI and Inventory/Case transfers have been tested in game by the user.
The expanded bag routes need live validation, including leaving the Mog House
and checking that home-only destinations disappear. An earlier delayed Case move
is still unexplained; the send mechanism and no-retry behavior are unchanged.
No live transfers have been performed by the developer tools.

API references: installed Ashita v4 SDK annotations and inventory item structure;
container IDs follow the installed invmon mapping. Transfer protocol research is
recorded in `docs/transfer-research.md`. The implementation is independent.

Locker access investigation: v0.3.1 distinguishes source access failures from full
destinations and adds read-only diagnostics. The user confirmed Wardrobe transfers
in both directions; Locker access after re-entry is still under investigation.

The v0.5.0 two-pane view has offline interaction coverage; visual layout and new
controls still require in-game validation. Existing Locker diagnostics remain.

In v0.5.0, access checks accept the observed wire size of 81 for an 80-slot
bag. Actual source slots and destination capacity still use the SDK values.
This fixes the false Locker/Satchel access denial identified in live diagnostics;
Satchel does not require Mog House access. The corrected transfers need live retesting.

Version 0.5.0 two-step transfers and native stacking passed offline tests;
both features still need controlled in-game testing with ordinary stackable items.

The user confirmed Locker-to-Satchel routing and native stacking in game.
The v0.6.0 Ownership view has offline coverage and needs an in-game UI check.

Version 0.6.1 replaces the Move tab with Items context actions. Regression tests
were adapted to the new interaction; obsolete two-pane tests were removed.
Right-click menu positioning and interaction still require in-game validation.

Version 0.6.3 fixes the item popup width and destination-control width to avoid
the repeated size changes seen in the supplied recording. In-game confirmation
of the visual fix is still required.

Version 0.6.4 uses the SDK usable Satchel capacity after reload, so portable
Satchel transfers no longer need a zone-entry packet. Explicit disabled packet
state still blocks access. Home-storage and paid-wardrobe checks remain unchanged.

### Crystal withdrawals

Withdrawals are location-independent for **Ephemeral Moogles** using the standard
crystal balance menu. Bastok Mines and one additional, unspecified location are
live-confirmed; remaining locations still need verification. Stand within 6 yalms,
with its normal menu closed; the nearest visible matching
NPC is detected automatically. No manual target selection is needed. In Currency > Crystals, right-click an element, enter
crystal units and press **Withdraw crystals**. Multiples of twelve return as
clusters; 25 units means two clusters plus one loose crystal.

The addon requests a fresh NPC menu, checks identity, zone, menu structure, balance and
Inventory space, then sends one withdrawal response. It confirms received items
through Inventory changes. The response uses the menu ID returned by that NPC,
instead of a fixed Bastok menu ID. No retries. Unexpected menu layouts are rejected.
Native menus stay untouched unless they match this exact requested interaction.
After success, the last known balances stay visible while one refresh request
fetches the updated totals. Bastok withdrawals are user-confirmed, including
25 units returning two clusters and one loose crystal.

For troubleshooting, `/im crystaltrace` arms a passive 60-second
trace of an Ephemeral Moogle menu and its manual responses (maximum 12 packets).
Talk to the Moogle and make one normal small withdrawal. `/im crystaltrace stop`
ends capture early. The log is `crystal-menu-trace.log` in the addon folder.
It sends no packets. The trace can verify menu behaviour at additional locations.

### Shami: seals, crests and orbs

Stand within 6 yalms of Shami in Port Jeuno, with his normal menu closed.
He is detected automatically; manual targeting is not required.
Right-click a currency in **Seals & Crests** to withdraw a quantity to Inventory,
or choose an orb that uses that currency. **Review exchange** shows the cost;
the separate **Confirm: spend ...** button authorizes one orb exchange.

Fresh Shami menu balances and conservative free Inventory space are checked
before a response is sent. Orb exchanges also reject an orb already present
in a readable bag (including a used/cracked copy with the same item ID).
Unreadable storage is not proof of non-ownership; the server still enforces
Rare-item restrictions. The addon waits for Inventory confirmation and never
retries uncertain requests. No deposits or seal conversion are automated.
After confirmation, press **Refresh balances** to refresh stored totals.

Manual captures verified one Beastmen's Seal retrieval and one Cloudy Orb
purchase. Other seal/crest selectors and the 15 orb mappings follow the reference
protocol and pass offline tests; automated operations still need live validation.

For diagnostics, `/im shamitrace` records up to 12 matching menu packets over
120 seconds in `shami-menu-trace.log`. It sends no packets. Use
`/im shamitrace stop` to stop early.

### Nearby NPCs and balance refresh

NPC actions detect the nearest visible matching NPC within 6 yalms. This does
not change your selected target or trigger an action by proximity alone; press
the withdrawal/exchange button as usual. Once started, the NPC identity is fixed
and rechecked instead of switching to another NPC. Ephemeral Moogle withdrawals
are no longer restricted to Bastok Mines. Shami remains Port Jeuno.

**Refresh balances** requests the same Currencies I data used by the game menu
(outgoing 0x10F, incoming 0x113). Clicks are limited to one per five seconds.
There is no automatic retry. A ten-second timeout reports that no update arrived;
existing values keep their original receipt timestamp. Requests are blocked while
zoning or without a matching character profile.

### Saved balances

The last received currency snapshot is saved in the character's existing settings
profile. A reload or zone change keeps those values, labelled **Last known
balances** with their timestamp. They may be stale; NPC actions still validate
against a fresh server menu rather than this display cache. Missing/invalid saved
snapshots show `--` until a successful refresh. Character profiles stay isolated.

Confirmed Shami/Moogle actions schedule one currency refresh, respecting the
five-second request cooldown. Until it arrives, saved values remain visible.
No values are guessed or locally decremented, and failed refreshes do not erase
the snapshot or cause automatic retries.

## Bag monitor (InvMon replacement)

Run `/im monitor` to toggle **InvMaster Bags**. It works while the main window
is closed. Drag its title bar to position it. Settings > Bag monitor controls
visibility, position locking, background, warning threshold and included bags.
These choices save per character; window placement uses ImGui's existing layout.

Each row shows used/capacity and free slots with a usage bar: teal normally,
amber at the warning threshold (default five free slots), red when full.
Click a bag name to open Items for that container. Search text clears; your
category filters remain applied. Counts share InvMaster's auto-refresh interval
and show their age. Unavailable bags show `--`; zoning clears stale counts.

Initially disabled so you can test alongside InvMon. Once satisfied, use
`/addon unload invmon`; its installed files and settings are untouched.
If InvMon is in your startup script, remove that load entry when ready.
