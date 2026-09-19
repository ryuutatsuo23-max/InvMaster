# Shami investigation

Scope: user requested both stored seal/crest retrieval and orb exchanges.

Reference: https://github.com/LandSandBoat/server/blob/base/scripts/zones/Port_Jeuno/npcs/Shami.lua
Fetched with Firecrawl to `.firecrawl/shami.lua`.
Reference trigger menu 322 packs the five stored currencies into parameters;
orb responses 1-15 select individual items and costs. Seal retrieval uses a
different quantity/type encoding. These are reference facts, not a verified
current-client protocol; no Shami interaction or exchange sends are enabled.

v0.10.1 provides `/im shamitrace`: passive, opt-in, 120 seconds, maximum 12
matching menu packets. Reuses the existing trace with an exact Shami NPC-name
filter. Captures incoming 032/033/034 and outgoing 05B matching that NPC.
Injected/blocked traffic is ignored; profile or zone changes end capture.
It writes only `shami-menu-trace.log` in the installed addon directory.
`/im shamitrace stop` stops early. It never requests interactions or sends packets.

Next evidence: manually retrieve one Beastmen's Seal; record success and the
result. Separately browse the orb menu and cancel without purchasing. Active
orb exchanges will require verified menu choices, explicit cost confirmation,
fresh balance/space/ownership checks and observed result confirmation.

## Captured evidence and v0.11.0 implementation

2026-09-19 15:30:19: NPC 0x010F6049, index 73, Port Jeuno zone246,
menu322. One Beastmen's Seal retrieval option 0x000001FE; following menu
balance falls from62 to61. Cancelling orb selections emitted0 or0x40000000.
15:32:20: user-selected Cloudy Orb purchase succeeded. Response option1,
automated byte0, same target/index/zone/menu. Cost20 Beastmen's Seals.

Additional mapping reference:
https://github.com/LandSandBoat/server/blob/base/scripts/globals/seals.lua
Captured to `.firecrawl/seals.lua` with Firecrawl. Retrieval option is
(quantity+1)*256-selector, with selectors2,1,3,4,5 for the five currencies.
Orb option indices/costs are from Shami.lua, checked against user screenshot;
Cloudy purchase validates index1. Item IDs/stack sizes from pinned item_basic.sql.
No reference implementation copied; independent controller uses these wire facts.

New controller checks selected Shami identity, distance, profile/zone, fresh
menu322 balances, Inventory capacity and existing orb copies in readable bags.
It suppresses only the requested matching menu, sends one result, then requires
two consistent Inventory observations. No retries. Other menus remain native.
Orb UI requires review and a named-cost confirmation before any interaction.
Tests cover all selectors/15 orb mappings, existing orb in Inventory/other bags,
insufficient balance, changed NPC/menu, short/injected data, manual cancellation,
timeouts, uncertain sends, profile change, and confirmation. Automated Shami
operations and non-Cloudy orb choices remain unverified in game.
