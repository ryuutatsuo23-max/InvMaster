# Currency balances (2026-09-19)

Reference: https://github.com/Windower/Lua/blob/dev/addons/libs/packets/fields.lua
Retrieved to `.firecrawl/currency-fields.lua` with Firecrawl.

Incoming Currencies I, 0x113: unsigned little-endian 16-bit fields at 0x10,
0x12, 0x14, 0x16, 0x18 for the five seals/crests; crystals at 0xE8 through
0xF6 in Fire, Ice, Wind, Earth, Lightning, Water, Light, Dark order.
The source Lightning offset comment says E0, but its sequential field definition
puts it at F0 (following Earth at EE, preceding Water at F2). Decode F0.
0x118 crystal Set fields are synthesis-related, not these stored balances.
No parser implementation copied; only wire-layout facts used.

Require enough bytes for all fields. Observe only non-injected, non-blocked
updates with a matching active character profile outside zoning. No packet
requests are sent. Clear on zone/profile changes. Unknown stays distinct from
zero. No saved cache or NPC operations. Live comparison remains necessary.

## Ephemeral Moogle withdrawal investigation

Reference: https://github.com/LandSandBoat/server/blob/base/scripts/globals/hobbies/crafting/ephemeral_moogle.lua
Retrieved with Firecrawl to `.firecrawl/ephemeral-logic.lua`.
The reference finishes the active trigger event with quantity in the low 16 bits
and element in bits 16-23. It returns clusters for each twelve crystal units,
plus loose remainder. This is reference evidence, not current-client validation.
Do not enable sends until a manual interaction identifies the client's event,
NPC, zone, menu and option encoding. No static menu identifiers are implemented.

v0.9.1 adds `/im crystaltrace` (60 seconds, maximum 12 matching packets).
Only incoming menu 032/033/034 identified as Ephemeral Moogle and outgoing 05B
for that NPC are logged, excluding injected/blocked traffic. Zoning ends capture.
No game actions or packet injection. `/im crystaltrace stop` ends it early.
The appended log is `crystal-menu-trace.log` in the installed addon folder.
Manual validation: arm before talking; withdraw a known small quantity, record
element, quantity and actual resulting items. This must precede an active UI.

### Successful manual capture, 2026-09-19 15:09-15:10

User confirmed a manual withdrawal of 1 Fire Crystal succeeded.
Installed `crystal-menu-trace.log` recorded incoming 0x034 and outgoing 0x05B.
NPC server ID 0x010EA17D, index 0x017D, zone 234, menu 617.
Incoming balances: 190, 37, 91, 249, 105, 46, 3, 7.
Outgoing response: option word 0x40010001 (quantity=1, element=1,
plus high bit 0x40000000); automated byte zero. Target/index/zone/menu match.
The captured high flag is not explained by the reference server script.
One quantity-1 trace cannot establish how Retail returns a full dozen or whether
the high flag controls its form. Before arbitrary-quantity sends, capture a manual
12 Fire withdrawal and record actual output (12 crystals versus 1 cluster).
No active withdrawal controls or packet sends have been implemented.

### Second capture and first implementation

At 15:14:21 a successful Fire quantity-12 withdrawal produced option 0x4001000C.
User confirmed the result was one cluster. Same target/index/zone/menu as above;
the incoming Fire balance was 189 (one lower following the first withdrawal).

v0.10.0 uses a single selected, nearby Ephemeral Moogle interaction (outgoing
0x01A category zero), then accepts only incoming 0x034 for the matching target,
zone 234 and menu 617. All quantities are crystal units, with cluster conversion.
It validates menu balance and conservative free slots before suppressing the
verified incoming menu and responding once with 0x05B. Unknown/mismatched menus
remain native, without a withdrawal response. Checks include identity, distance,
profile/zone, timeout, manual menu responses and exact Inventory deltas over two
reads. No retry. Sends are exercised only in mocks; native UI lifecycle and other
element selections still need in-game validation. Menu IDs are limited to the
one manually captured location; this is not a universal Moogle implementation.

## v0.12.0: nearby discovery and balance refresh

Manual NPC targeting is replaced by visible entity discovery within squared
range36 using installed Ashita GetName/GetServerId/GetDistance/GetRenderFlags0.
NPC identity is pinned during the pending menu phase. No visual target switching.
Matches GatherPoint's visibility bits0x200 required,0x4000 excluded and entity
range1..0x8FF. Half-second UI discovery cache; action starts force a fresh scan.

Existing Windower packet reference `.firecrawl/currency-fields.lua` defines
outgoing0x10F Currency Menu as header-only. Refresh balances sends four zero
header bytes through AddOutgoingPacket; existing incoming0x113 decoder supplies
results. Five-second click cooldown, ten-second status timeout, no retries.
Fresh character/zoning guard precedes send. Mocked checks cover these flows;
auto-discovery and direct refresh still require live validation.
