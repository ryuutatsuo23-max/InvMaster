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
matched against a short-lived queue of our own operation fields using the
effective `data_modified` packet (falling back to `data`). Extra buffer bytes
and reserved padding do not change the operation identity; ID, quantity and
slot must still match. This prevents self-cancellation while an unrelated
addon's different appraisal still cancels the item awaiting sale confirmation.
The source, packet ID and buffer size of an interrupting outgoing action remain
in the final result for diagnosing client-specific interruptions.
Ashita's [SDK event contract](https://github.com/AshitaXI/Ashita-v4beta/blob/main/plugins/sdk/Ashita.h)
defines modified packet data as the effective data after previous plugin changes.
No native events are blocked, menus opened, or existing shop selections driven.

## Validation

Offline LuaJIT tests cover packet layout, full-stack sequencing, marker settings,
mutual exclusion, protected/locked/equipped items, stale previews, context/rule
changes, late/malformed replies, NPC distance/session expiry, Stop, timeout,
uncertain sends, external addon interference, and UI child-stack balancing.
The user observed one successful drop followed by a stopped four-stack run,
and a cancelled sale, on v0.22.0. v0.22.1 corrects outgoing packet matching and
adds cancellation reasons. Offline regression tests simulate effective buffers,
reserved padding, two-stack drop/sale completion and conflicting injected
appraisals. Live multi-stack drop and merchant sale confirmation remain pending.


## v0.22.2: native Inventory auto-sort

Live v0.22.1 results identified outgoing 0x03A (size 8, event buffer 512)
after the first successful drop and sale. These were being treated as manual
interruptions. A valid bag-zero sort now preserves the queue and merchant
session. It sends no additional sort requests and does not suppress the client.

The runner waits at least 0.75 seconds after the latest sort request, then
requires an unchanged readable Inventory snapshot across at least 0.5 seconds.
Sorting has an eight-second overall bound; existing appraisal/action deadlines
are not extended. Price replies received during sorting are held until this
settle check completes. Every subsequent action still checks its exact reviewed
slot, ID, quantity and metadata; relocated/merged stacks require a new preview.
Other-bag or malformed sort requests still interrupt the run. Stop, context
changes and uncertain-outcome locks remain in effect.

Regression coverage includes auto-sort during sent requests, between stacks,
and while a sale price is pending, plus changing Inventory, merged stacks,
Stop and invalid sort packets. Live multi-stack confirmation remains pending.
