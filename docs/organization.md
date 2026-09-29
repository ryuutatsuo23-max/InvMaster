# Organization rules and execution — v0.17.0

The planner remains read-only. The separate runner starts only when the user
clicks **Run organization** after reviewing a plan. It uses InvMaster's existing
confirmed transfer and routing engine. Existing manual moves, collections and
CraftMaster preparation share the busy lock.

## Rules

- Rules are stored in a new per-character `organization` settings field.
  Existing favourites, collections, filters and other settings are preserved.
- **Leave this item untouched** excludes every copy of that item ID from the
  organization plan, regardless of keep quantities or destinations.
- **Keep a quantity in Inventory** requests a total, counting what is already
  there. Zero explicitly requests no retained quantity; the option being off
  means no refill target. Both still need a destination to propose storing extras.
- Item destinations override category destinations. **Use category rule** removes
  that override. **Leave where it is** disables surplus placement for that rule;
  an independently enabled keep target can still propose refilling Inventory.
- No rules, default layout or automatic carry quantities are enabled by default.
- Rules apply across copies/augments of the same item ID. Per-instance protection
  and protection of a partial quantity are not part of this phase.
- Saved item rules remain editable even when the item is absent from readable bags.
  Removing an item rule restores category behavior, if configured.

## Preview limits

The plan uses readable bag contents, current access and existing transfer checks,
including equipment, flags, resource data and routing through Inventory. It does
not imply that all owned items have been read or that a future move will succeed.

Items are planned in stable item-ID order. Each proposed arrival reserves a new
destination slot, even when a merge might be possible. The planner does not count
slots freed by other proposed moves, consolidate stacks across bags, or swap full
bags. Storage-to-storage proposals also require an available Inventory staging
slot. These choices can produce conservative space blockers.

A source stack partly reserved to refill Inventory is not reused for another
proposal; its remaining surplus is deferred with a notice. After a run, review a
fresh plan for any remaining work.

Changes to observed bag contents, applied rules, access or character context
invalidate the displayed plan. Unchanged refreshes preserve it. A draft edit has
no effect until Apply; previews use saved rules. Busy operations block planning.

## Running and stopping

- Only the reviewed moves run, with at most 50 transfer steps. A route through
  Inventory counts as two steps. Notices are skipped, never silently converted
  into new moves. Narrow rules if the preview exceeds the limit.
- The runner checks the preview against fresh bags and saved rules before
  accepting it. Each next move is revalidated for source identity, quantity,
  equipment, access and space. A changed or blocked move stops the run.
- One transfer must be confirmed by inventory changes before another starts.
  Changes to character context, saved rules or access cancel further sends.
- **Stop organization** or `/im organizestop` stops further sends. It does not
  undo a request already sent. If the first leg of a route is pending, its items
  remain in Inventory when confirmed instead of continuing to storage.
- An uncertain or timed-out transfer remains locked until confirmed or the addon
  is reloaded. There are no automatic retries; late confirmation after timeout
  never resumes the queue. Check bags before reloading.
- Hiding the window does not stop a run. Avoid other inventory movers or manual
  rearrangement while it runs. Stack merging or unrelated changes can require
  a fresh preview rather than allowing the remaining reviewed moves.

## Optional stacking

**Stack destination bags after this run** is off for every new preview. It does
not change the saved manual-transfer auto-stack setting or save a new preference.
After all reviewed moves confirm, it checks each distinct final destination once.
It uses native bag stacking only when partial stacks can free a slot, confirms
that bag before continuing, and never retries a request. Inventory used only as
a staging bag is not included.

Native stacking affects the whole bag. Any destination containing an item marked
**Leave this item untouched** is skipped, and the final result reports the skipped
bag count. The protection check is repeated against the snapshot used to send.
Source-only bags are not stacked. No stack request is sent for a zero-move plan.

Stop, rule/access/context changes, or an unsuccessful move cancel remaining
stacking. A stacking request already sent keeps the busy lock until confirmed;
a timeout cancels the remaining queue even if confirmation later arrives.
The preview's 50-step limit counts transfers; optional stacking adds at most one
request for each distinct final destination bag.

Default rules, NPC deposits and full-bag swaps remain outside this phase.
No saved user data is migrated or discarded.

## Validation

`python -B test_invmaster.py` covers the planner and mocked UI in addition to the
existing regression suite. Checks include precedence, protection, keep quantities,
missing/inaccessible items, shared free-slot reservation, unchanged input data,
preview invalidation, profile isolation, sequential routing, stale-plan rejection,
Stop, timeouts and no retries. All requests are captured by local mocks.

Live confirmed: one reviewed run moved 40 Pickaxes and 5 Thief's Tools from
Satchel to Inventory, reaching targets of 99 and 12. Both moves confirmed, and
a fresh preview proposed no further moves while retaining three shortage notices.
Storage-to-storage organization and Stop were also confirmed live: four of 14
moves completed before Stop left Tortoise Shield in Inventory after its first
leg. A fresh preview correctly proposed its remaining leg and nine other moves.
The red Notice labels were visually confirmed after reloading. The revised
manual-stop wording still needs a visual check.

Optional organization stacking is offline-tested, including default-off behavior,
destination deduplication, sequential confirmation, protected bags, Stop, timeouts,
uncertain sends, context changes, and the UI packet path. A subsequent live run
confirmed 8/8 moves and stacking in one destination bag, with zero protected-bag
skips. Its fresh preview showed no remaining moves. Protected-bag skipping and
Stop during stacking remain offline-tested rather than live-confirmed.

OddOrg's public README was used as a feature reference only:
https://github.com/FFXIOddone/OddOrg
The rules, planner and UI were implemented independently in InvMaster's architecture.
