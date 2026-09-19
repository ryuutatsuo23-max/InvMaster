# CraftMaster preparation bridge (InvMaster 0.14.0)

CraftMaster 0.4.0 and later can request target Inventory quantities for up to nine distinct
item IDs. InvMaster retains ownership of all movement: `prepare_bridge.lua` uses
the existing `withdraw.sources` and `transfer` checks and confirmation engine.
No settings, collections, or transfer rules are migrated or changed.

Internal local commands (not chat messages to other players):

- `/im craftprepare TOKEN CHARACTER:ID:ZONE EXPIRY ID=TARGET,ID=TARGET`
- `/im craftcancel TOKEN`
- Reply: `/cm prepare_result TOKEN CODE`

Tokens consist of three decimal components separated by hyphens. Requests are
bounded to nine unique IDs, 7992 units per item, 400 characters and 60 seconds.
The context must match the current idle character and zone. Duplicate tokens are
ignored through expiration. Commands are queued with Ashita's ChatManager; no files
or shared Lua globals are used to communicate between addons.

The entire request is preflighted for accessible materials and conservative space.
Fresh snapshots are used for each sequential move. Other InvMaster operations see
preparation as busy. Cancellation, expiry, zoning or synthesis prevents further
moves. Already-sent transfers retain their existing confirmation/uncertainty lock.

Reply codes: accepted, done, busy, context, read, materials, space, transfer,
uncertain, stopped. CraftMaster checks final Inventory quantities after `done`.
The bridge never requests crafting and has no automatic retry.

Offline integration tests: `test_prepare.py` in the sibling CraftMaster project
(nine tests passed against CraftMaster 0.5.1 and InvMaster 0.14.0).
In-game command delivery and preparation still require manual validation.
