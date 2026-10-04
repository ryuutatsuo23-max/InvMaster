# Explicit Inventory disposal

`disposal.lua` is an independent controller with injected context, inventory,
rule, NPC, clock and packet interfaces. It shares the addon action lock with
transfers, organization, stacking, currency and CraftMaster preparation.
Neither marking nor previewing sends packets. Selling and dropping require
separate confirmations. Preview controls stay above the scrollable item list.

## Rules and identity

Sell and Drop save per character by item ID, including future copies. They are
mutually exclusive; untouched takes priority. Organization gathers either kind
into Inventory through its existing reviewed runner. Disposal never retrieves
items from other bags and never converts rejected sales into drops.

A confirmed preview freezes its rows and the snapshot/rule signatures. Each
send rechecks character/zone, idle or merchant state, other actions, rules,
Inventory slot, ID, count, flags, bazaar price, full extra bytes, resource type,
stack size and equipment. Changes cancel remaining work. Storage slips retain
the existing type-27, count-one exception for a zero resource stack size.
The NoSale resource flag (0x1000) excludes items from sale previews.

## Merchant protocol

Field reference: [Windower packet definitions](https://github.com/Windower/Lua/blob/dev/addons/libs/packets/fields.lua).
Only protocol facts were used; no other addon's implementation was copied.

A user interaction (outgoing 0x01A, category zero) records the nearby NPC's
server ID and index. A normal shop list (incoming 0x03C) within 30 seconds arms
a session pinned to that NPC, character and zone. It expires after 120 seconds;
distance, availability and identity are rechecked. Guild shops are excluded.
A shop already open before addon load must be reopened.

For each reviewed stack, 0x084 requests its price using count at offset 4,
item ID at offset 8 and Inventory slot at offset 10. A positive-price 0x03D
reply for that slot, received before the eight-second deadline, triggers one
0x085 confirmation. Price-check counts can be one even for a full stack.
Final sale confirmation requires a type-one 0x03D with the reviewed quantity,
plus two stable Inventory reads showing the emptied slot and exact quantity
reduction for the matching ID/extra bytes. A late price reply never confirms
an expired appraisal.

## Drop and interruption

0x028 requests the reviewed quantity from bag zero and the reviewed slot.
The same two-read Inventory confirmation applies. Each stack is processed
sequentially; no game packets are sent by offline tests.

Stop cancels future sends. An already-sent sale/drop stays locked until its
outcome is confirmed. Timeouts, uncertain send returns and exceptions never
retry. A late confirmation may settle a stopped request but cannot restart
remaining work. Zoning or profile changes invalidate sessions and previews;
uncertain sent requests retain the action lock. Reloading does not resume work.

Manual inventory/shop actions cancel remaining work. Outgoing injections are
matched against a short-lived queue of our own packet bytes so an unrelated
addon's appraisal cannot silently replace the item awaiting sale confirmation.
No native events are blocked, menus opened, or existing shop selections driven.

## Validation

Offline LuaJIT tests cover packet layout, full-stack sequencing, marker settings,
mutual exclusion, protected/locked/equipped items, stale previews, context/rule
changes, late/malformed replies, NPC distance/session expiry, Stop, timeout,
uncertain sends, external addon interference, and UI child-stack balancing.
Live normal-merchant sale and drop tests remain pending. Begin with one explicitly
marked low-value stack for each action and check the final Inventory result.
