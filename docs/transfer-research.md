# Transfer research

v0.2.0 implements the first narrow route set: Inventory to/from Sack or Case.
No live transfers have been tested or sent by developer tools.

Bellhop is an existing Ashita plugin with get/put commands. Its implementation
uses outgoing item-movement requests with a source slot, quantity and destination.
It separately checks Mog House/Nomad Moogle access, bag unlocks, item flags and
destination restrictions. Readable contents alone are not an access check.

Sources inspected at commit baa47e8855a03c363e908457a79176df03da6419:

- https://github.com/ThornyFFXI/Bellhop/blob/baa47e8855a03c363e908457a79176df03da6419/readme.md
- https://github.com/ThornyFFXI/Bellhop/blob/baa47e8855a03c363e908457a79176df03da6419/Get.cpp
- https://github.com/ThornyFFXI/Bellhop/blob/baa47e8855a03c363e908457a79176df03da6419/Helpers.cpp
- https://github.com/ThornyFFXI/Bellhop/blob/baa47e8855a03c363e908457a79176df03da6419/Packets.h

A command adapter would add a plugin dependency and name/ID matching can choose
the wrong copy of an augmented item. Prefer an independent, exact-slot transfer
controller. No source implementation was copied into FindMyStuff.

First scope: one selected item and quantity between Inventory and one verified
accessible portable container. Revalidate source identity and flags, destination
access and space, then verify inventory changes before reporting success. Stop
on timeout, zoning or changed source; never blindly retry.

Next: Mog House containers after validating access detection. Storage-to-storage
via Inventory needs an explicit two-step operation and intermediate space.
Temporary and Recycle, bulk organization and automatic moves remain excluded.

Unresolved: client-specific access/unlock detection, equipped/in-use flag semantics,
stack merges, augmented instance identity, and reliable completion signals.
Existing plugin behavior demonstrates feasibility, not live validation of a new
implementation. No plugins were installed during this investigation.

## Implementation decisions

The installed SDK item_t stores 28 extra-data bytes (not the 24-byte wire field
some other interfaces expose). Selection retains all 28 and checks equality.
Only zero item flags and zero bazaar price are accepted initially. Equipped
indices are checked separately across all 16 equipment slots using the SDK's
packed container/slot index. Furniture is excluded instead of guessing placement.

Sack and Case follow the always-accessible portable bag classification in the
inspected Bellhop implementation; available consistent bag data and player state
are additionally required. Satchel and other unlock/access paths remain excluded.
No pointer scanning or new plugin dependency is introduced.


## v0.3.0 access and destination filtering

Access is independently implemented from passive incoming updates, scoped to
player name, server ID and zone from 0x00A. 0x00B discards the learned state;
profile reload also clears it. Injected/blocked packets are ignored. Loading in
an already-entered zone requires re-entry to learn home and unlock state.

Sources:
- Installed official `addons/filterscan/filterscan.lua` uses the 0x00A byte at
  offset 0x80 equal to 1 to identify Mog House entry.
- https://github.com/Windower/Lua/blob/dev/addons/libs/packets/fields.lua
  (retrieved 2026-09-19; saved in `.firecrawl/packet-fields.lua`): 0x00A player ID
  0x04, zone 0x30, name 0x84; 0x01C primary bag capacities 0x04 onward;
  secondary capacities 0x24 onward are zero for disabled bags, except paid
  wardrobes. Require nonzero secondary capacities for Locker and Satchel.
  0x037 identifies the player at 0x24 and paid wardrobe flags at 0x5C:
  Wardrobes 3/4 use bits 0/1; Wardrobes 5-8 use bits 3-6.
- Bellhop Helpers.cpp, pinned above: wardrobe equipment eligibility is resource
  Flags bit 0x800, and ordinary Wardrobes 1-2 are in its base accessible group.

Only Inventory-to/from-bag routes are enabled. No Nomad detection, furniture,
Temporary, Recycle or automatic intermediary transfers. Home-only routes require
both a learned Mog House flag and a positive reported capacity. Paid wardrobes
also require explicit unlock evidence. Every move revalidates access and fresh
source identity, resource eligibility and destination space before queueing.
The UI filters full/inaccessible/ineligible destinations and clears a destination
that stops qualifying instead of silently choosing another one.

User confirmed Case transfers and several menu-open transfers. The earlier delayed
Case transfer remains unexplained; this change does not alter packet sending.
Expanded access remains subject to controlled in-game validation.


## v0.4.1 live capacity regression

User diagnostics showed matching current/recorded character and zone, Mog House
true, and 0x01C sizes 81 for Locker and Satchel with SDK capacity 80. Safe
reported 51. The access check incorrectly capped wire sizes at 80. Accept up to
81 without altering the actual SDK slot limits, secondary disabled flags, home
requirements, or paid wardrobe unlock checks. Satchel is not gated on home state.
Regression coverage includes Locker inside home, Satchel outside, and invalid or
disabled sizes. No developer tools performed live moves.


## v0.5.0 routing and native sort

Two-leg routes compose the same validated single-leg controller. The received
Inventory slot must be the sole matching identity whose quantity increased by
exactly the requested amount. Existing stack merges forward only that amount.
Split or ambiguous arrivals stop in Inventory. Destination/access/equipment and
source identity are rechecked for step two. Timeouts or context changes cancel
automatic continuation of a late first-leg result. No repeated sends.

Native stacking uses outgoing 0x03A: eight bytes, four-byte header followed by bag
ID and three zero bytes. References: Windower packets fields.lua (cached above),
https://github.com/Windower/Lua/blob/dev/addons/libs/packets/data.lua defines
Sort Item as stacking items; installed XIUI/modules/satchel/packets.lua uses this
packet layout for native stacking. Independent implementation, no code copied.
A sort starts only with accessible stable bag contents and mergeable stacks.
Completion requires conserved item/extra-data totals and expected occupied-slot
reduction on two reads. Uncertain requests keep the shared operation lock.
Opt-in destination auto-stacking only follows fully confirmed transfers.
