# Crystal deposits and Retail capture — v0.20.1

The v0.18.0 preview and passive trace are now joined by an explicitly confirmed
deposit, now with an optional reviewed batch queue. Withdrawal and organization remain separate. No items are
automatically gathered from other bags and no saved preferences are changed.

## Active deposit scope

At any verified Ephemeral Moogle within 6 yalms, select up to 12 loose
crystals OR 12 clusters of one element from one eligible Inventory stack.
Preview, then click **Confirm crystal deposit**.

Alternatively, **Preview deposit all crystals / clusters** selects every eligible
ordinary crystal/cluster stack currently in Inventory. It shows all selected slots,
totals by element and the number of trades. **Confirm deposit all** freezes that
selection and processes at most eight stacks per trade, including mixed elements
and both crystals and clusters. Unrelated items and gil are never included.
Locked/unvalidated crystal stacks are visibly skipped. Nothing is pulled from
other bags. Newly acquired items are not appended to the reviewed queue.

The full remaining selection must fit the 5000-unit per-element storage limits;
otherwise the run stops rather than silently reducing quantities. Fresh currencies,
the same NPC and all remaining source slots are checked before each trade.
Every batch requires matching per-element menu quantities, all 16 crystal/cluster
Inventory totals and all eight stored balances. Only after final confirmation and
the NPC becoming idle does the next batch request fresh balances.

The controller refreshes currencies, pins NPC/character identity, and rechecks
the exact reviewed slot, quantity and instance data. Fresh balance plus selected
units must not exceed 5000. The returned menu must match the selected quantities,
pinned NPC and zone, with a nonzero menu ID and all eight exact quantity parameters.
The menu ID from that verified response is used for both replies and refreshed
for every batch, rather than assuming Bastok menu 618. An unverified menu is left native, with no
automatic response and an uncertain-action lock.

After the verified menu, it sends the captured automated response, requires an
exact eight-element balance update and checks the Inventory decrease on two reads.
It then sends the final response and requests currencies once. Success requires
both final stored balances and the Inventory delta. No event update alone is
treated as confirmation of the full operation.

**Stop crystal deposits** or `/im depositstop` cancels remaining batches.
**Cancel deposit before trade** also cancels while awaiting fresh balances.
A sent trade cannot be undone; its verified dialogue and confirmation finish,
then the remaining queue is discarded. Unexpected replies, manual actions,
context changes, send failures and timeouts remain locked without retry.
Check bags and finish any native dialogue before reloading.

Single-stack and mixed-element three-stack deposits are live-confirmed at the
Bastok Markets Goldsmiths Moogle. The mixed trade deposited 1 Water, 2 Light and
4 Dark crystals, increasing balances from 51/6/11 to 52/8/15. Other Moogle
locations, full eight-slot trades, multiple batches and Stop during batching
still need live checks. Location-independent menu handling is offline-tested.
On 2026-09-29 the user deferred testing another Ephemeral Moogle until later.

## Preview

In Currency > Crystals, open **Plan crystal deposit**, choose an element and
quantities of loose crystals and clusters, then **Preview crystal deposit**.
Each cluster contributes 12 crystal units. Only readable Inventory is considered;
locked or unvalidated stacks are excluded. The preview lists selected slots,
checks the eight-slot trade limit and shows a notice when quantities are missing.
It checks nearby NPC availability through the existing identity/range/idle guard.
Deposits remove items, so the preview does not demand an empty Inventory slot.

The projected stored total uses the last known balance, explicitly labeled as an
estimate. Unknown balances remain unknown. A selected amount exceeding the 5000
limit produces a notice; it is never silently reduced. No preview authorizes a
trade until Confirm is clicked. Input/profile changes reset the view; results use the latest
available bag snapshot.

## Why a manual capture is needed

Protocol references, consulted 2026-09-29:

- https://github.com/LandSandBoat/server/blob/base/scripts/globals/hobbies/crafting/ephemeral_moogle.lua
- https://github.com/Windower/Lua/blob/dev/addons/libs/packets/fields.lua
  (previously retrieved locally as `.firecrawl/currency-fields.lua`).

The server reference separates deposit trade events from withdrawal triggers;
it confirms deposited items on an event update. Event IDs vary by location, and
the reference does not implement Mog Garden. It supports crystals and clusters,
with 12 units per cluster and a 5000-unit cap per element. These are reference
facts, not proof of the Retail event sequence. No implementation was copied.

The packet layout reference identifies outgoing NPC trade 0x036 (0x40 bytes):
target at 0x04, nine counts at 0x08, nine Inventory indices at 0x30, target index
at 0x3A and entry count at 0x3C. Incoming 0x05C has 32 event parameter bytes at
0x04. The preview does not encode or send either packet.

## Passive manual capture

1. Stand beside an Ephemeral Moogle with no addon action pending.
2. Run `/im deposittrace`, then manually trade **one ordinary crystal** through
   the normal game trade menu. Complete the NPC dialogue.
3. Click **Refresh balances** in Currency. Note element, location, inventory loss
   and stored-balance increase. Repeat separately with one cluster when needed.

The trace lasts 60 seconds, records at most 24 matching packets and sends nothing.
`/im deposittrace stop` stops it early; zoning also stops capture. Log file:
`crystal-menu-trace.log` in the installed InvMaster folder.

The initial outgoing trade must match the Ephemeral Moogle's name, entity index
and server ID. Deposit menus must match that trade; subsequent matching responses
and event updates are recorded, plus only the crystal section of currency updates.
Injected and blocked traffic is excluded by the main addon. Incoming 0x05C has no
NPC identity field; its correlation to the accepted menu is contextual, not proof
of origin. Unrelated menu traffic clears the active menu target. Capture output
must be reviewed before implementing any active deposit state machine.

Offline tests cover conversion, unknown/over-cap balances, quantity boundaries,
eligible slots, profile reset, no sends, trace identity checks, timeouts and limits.
The first live deposit capture is documented below. Future execution must recheck
fresh state, pin NPC identity, send only the explicitly reviewed amount, confirm
both Inventory and balance changes, and never retry an uncertain trade.

## First Retail capture: one Lightning Crystal

On 2026-09-29 at 21:57, the user manually deposited one Lightning Crystal at the
Goldsmiths' Guild Ephemeral Moogle in Bastok Markets and confirmed the balance
increased by one. The game message reports one stored, total three; refreshed
InvMaster currency also shows three. Local trace decoding establishes:

- NPC ID `0x010EB1B1`, index 433 (`0x01B1`), zone 235, deposit menu 618.
- Outgoing 0x036: one trade entry, quantity one, Inventory slot 16, remaining
  entry counts/slots zero. No gil offered.
- Incoming 0x034: eight event parameters; Lightning (fifth) is `0x00010000`,
  all others zero. This corresponds to one loose crystal in the upper 16 bits.
- Outgoing 0x05B: option word zero, automated-message byte one.
- Incoming 0x05C: stored balances 2, 31, 4, 176, 3, 51, 6, 11.
- Final outgoing 0x05B: option word zero, automated-message byte zero.
- Refreshed 0x113 crystal balances exactly match that 0x05C balance list.

This captures the successful single loose-crystal path at this NPC, not clusters,
mixed or multi-slot trades, cancellation, near-cap behavior, or other locations.
The pre-trade balance increase is user-confirmed; the trace itself contains only
post-trade balances.

## Second Retail capture: one Earth Cluster

At 22:01 on 2026-09-29, the same NPC accepted one Earth Cluster. The screenshot
shows a cluster withdrawal beforehand, followed by a deposit message reporting
one Earth Cluster stored for a total of 176. The user confirmed a balance increase.

The trace again has one 0x036 entry, quantity one, Inventory slot 16. Menu 618's
fourth (Earth) parameter is `0x00000001`, with the other element parameters zero;
the cluster count is in the lower 16 bits. Option zero/automated byte one precedes
0x05C; option zero/automated byte zero closes the dialogue. Both the event update
and refreshed currencies contain 2, 31, 4, 176, 3, 51, 6, 11.

This establishes the cluster parameter and successful sequence at this NPC, not
mixed/multi-slot trades, near-cap behavior or other locations.

## Automated single-stack live confirmations

The user confirmed an automated Earth Crystal deposit with balance 176 to 177,
then an automated Earth Cluster deposit with balance 166 to 178. Both reported
matching Inventory and stored balances. These confirm v0.19.0's single-stack flow
at the captured NPC, not v0.20.0's mixed/multi-slot batching.
