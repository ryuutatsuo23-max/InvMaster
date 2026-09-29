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


## v0.20.5: current capacities near storage-service Moogles

User evidence in Mog Garden (zone 280): the learned entry flag is 1, and Safe,
Storage, Locker and Safe 2 are accessible. Reloading v0.20.4 without zoning
clears the recorded key, capacities and flag while readable contents remain.

A narrowly scoped fallback now uses the existing nearby-NPC reader within six
yalms, current SDK capacities, stable update counters and the idle character key.
It is rebuilt on demand, not saved as home access. It applies to Green Thumb
Moogle only in zone 280, and Nomad Moogle only in Tavnazian Safehold (26),
Nashmau (53), Rabao (247), Kazham (250) and Norg (252). NPC names alone do not
suffice; the level-limit Nomad in Ru'Lude and generic/event Moogles are excluded.
Nomads never grant Storage access. A capacity must be a whole number from 1 to
80; Locker also requires a positive secondary capacity up to 81. A learned
server report disabling the bag takes precedence. Missing raw Locker data leaves
Locker unavailable, without preventing other verified bags. The existing home
entry path and paid-Wardrobe checks are unchanged.

Sources inspected, without copying an addon implementation:
- Installed official Ashita SDK `IInventory:GetRawStructure`,
  `inventory_t.ContainerMaxCapacity2`, and `GetContainerCountMax`.
- https://www.bg-wiki.com/ffxi/Mog_House : storage-service Nomad locations and
  their exclusion of Storage.
- https://github.com/Windower/Resources/blob/master/resources_data/zones.lua :
  zone identifiers.
- https://github.com/LandSandBoat/server/blob/base/scripts/zones/Mog_Garden/npcs/Green_Thumb_Moogle.lua :
  reference for the Mog House menu service, not proof of Retail behavior.

No interaction, access request, or transfer is sent by proximity or `/im status`.
Normal previews and user confirmation still control all actions. Every subsequent
move uses a fresh access check, including route continuation. Walking away during
an in-flight first leg prevents its follow-up when no learned home access exists.
No profiles, unlocks or saved balances are changed. Ordinary Mog House reload
recovery remains outside this fallback because a generic Moogle name is not
sufficient evidence of a private residence.

Offline validation covers recovery without a zone packet, supported locations,
wrong names/zones, six-yalm bounds, Locker capacity failures, disabled bags,
context changes, explicit moves and stopping a route on loss of proximity.
Live verification of the new fallback is pending. `/im status` now reports the
nearby storage Moogle and live Locker secondary capacity to support that check.


### Reload test and Locker diagnostic (v0.20.6)

The user confirmed the v0.20.5 status after reloading beside Green Thumb Moogle:
recorded state remains empty, but Safe, Storage and Safe 2 report access=true.
Locker reports false because raw `ContainerMaxCapacity2[4]` is zero, while the
previous zone-entry capacity update reported Locker secondary 81. This does not
establish whether the raw array index or its semantics differ from the wire data.
No Locker guard is loosened. `/im status raw` prints raw capacity indices 0-6 and
the corresponding SDK bag capacities, read-only, to establish the mapping.
Actual transfers with the recovered access have not yet been confirmed live.


### Confirmed raw array mapping (v0.20.7)

The live `/im status raw` output shows both raw capacity arrays are one-based:
index 0 unavailable; indices 1-6 are 81,81,11,0,81,81. The SDK method for bag
IDs 0-6 returns 80,80,10,0,80,80,80. Therefore Locker (bag ID 4) uses raw entry
5, not entry 4 (Temporary). Recovery and diagnostics now read entry 5. Fixtures
match that observed mapping and also test that positive Temporary capacity cannot
authorize a disabled Locker. The secondary-capacity requirement is unchanged.
Locker recovery after this correction still awaits a live check.


### Green Thumb success and Mhaura omission (v0.20.8)

The user confirmed v0.20.7 recovers Safe, Storage, Locker and Safe 2 after reload
beside Green Thumb Moogle without rezoning, and transfers work there. Locker's
correct raw secondary value is 81.

A subsequent screenshot beside a Nomad Moogle shows current/recorded zone 249
(Mhaura), entry flag 2, secondary Locker capacity 81, and no verified storage
Moogle. Mhaura was missing from the location allowlist, so discovery was never
attempted. Add zone 249 based on this live NPC/location evidence and the zone
resource mapping; preserve exact-name, range, capacity and no-Storage checks.
The location regression is offline-tested; live Nomad transfers remain pending.


### Complete listed Nomad locations (v0.20.9)

Compared https://www.bg-wiki.com/ffxi/Nomad_Moogle with the allowlist on
2026-09-30. Selbina (zone 248) was the only missing storage-service location
following the Mhaura fix. It is now included and covered by the existing access
regression matrix. All seven listed zones are supported: Selbina, Mhaura, Rabao,
Kazham, Norg, Tavnazian Safehold and Nashmau. The page explicitly excludes
Ru'Lude Gardens' special Nomad from ordinary Mog House services; it remains
excluded. Range, identity, capacity, Locker and no-Storage guards are unchanged.
Selbina and the other Nomad locations still require live transfer verification.

### Nomad organization confirmed live (2026-09-30)

The user confirmed organization succeeds beside a Nomad Moogle. The screenshot
shows 5/5 moves confirmed and a finished run, with one destination bag skipped
during stacking to protect untouched items. This follows the Mhaura discovery
fix; the success screenshot itself does not display a zone ID or individual
transfer endpoints. It confirms a completed Nomad organization run, not every
bag or every supported location. Other Nomad locations remain unverified live.

### Mog House reload and Storage Slip diagnostic (v0.20.12)

The user reported unavailable access after reloading inside a Mog House in
zone 235; the screenshot shows no recorded zone entry. This is the remaining
ordinary-residence limitation, not a regression of Nomad recovery. No generic
Moogle access bypass is added. `/im status detail` reads the SDK residence value
and Storage Slip 22 slot metadata without sending requests or exposing extra
data contents. The residence value is diagnostic only until its semantics are
verified. The screenshot shows an access notice for Storage Slip 22; the earlier
reported unknown-identity notice has not been reproduced. Item identity and
locked/in-use warnings now distinguish these different validation failures.

### Storage Slip 22 resource evidence (v0.20.13)

Live diagnostics show item 29333, type 27, count 1, flags and price zero,
28 identity bytes, and stack size zero. The installed SDK enums identify 27 as
StorageSlip. Transfer validation now treats exactly this type/count/zero-size
combination as a single non-stackable item. Missing or malformed sizes for other
items remain blocked. Confirmation still requires matching extra data; the raw
resource value is preserved in snapshots. Offline tests cover exact identity
confirmation and malformed/locked cases; live movement remains pending.
The same capture reports residence 1 inside the Mog House after reload. An
outside comparison is still needed before using that value to authorize access.

### Residence comparison and room probe (v0.20.14)

The user confirmed residence remains 1 outside and away from all Moogles.
It is not an inside/outside discriminator and is excluded from access decisions.
The SDK documents `ITarget:GetMyroomCallback` as the exit-door callback and
`IEntity:GetZoneId` as a local-player field set under certain conditions. Neither
is currently accepted as access evidence. `/im status room` reads these values,
party Zone2, and bounded exact-name Moogle identity entries while context is
ready. It never invokes callbacks or changes access. Client comparison pending.

### Combined Mog House recovery (v0.20.15)

Inside: local entity zone 0, party Zone2 0, room callback 91906112, Moogle
index 97 / ID 17739873 at squared distance 2.25 with flags 1078985216.
Outside: callback 0 and no entity named Moogle. Residence stays 1 in both.
The fallback now requires a positive integer room callback and an exact-name,
rendered Moogle within six yalms, plus the existing idle character context,
stable inventory update counter, bag capacities and Locker secondary capacity.
It rereads the callback before accepting capacities. It does not invoke the
callback or persist access. Nomad and Garden paths remain unchanged.
Offline tests cover missing/invalid callback, absent/distant/hidden Moogle,
context changes, disabled Locker, callback changes during reads, and loss of
the indicator during a routed move. Live reload-and-transfer verification is
pending; other residences and floors have not yet been tested.

### Live recovery and slip transfer confirmed (2026-09-30)

After reloading v0.20.15 inside the Mog House in zone 235, the user showed no
recorded zone entry, a verified nearby Moogle, and Safe, Storage, Locker and
Safe 2 all accessible. The reviewed six-move plan included Storage Slip 22
from Satchel to Safe 2 via Inventory. Subsequent screenshots show progress
at 1/6 and 4/6 and a finished 6/6 result. This confirms the tested Mog House
reload path and slip transfer; other residences and floors remain untested.
