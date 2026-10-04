# InvMaster

An Ashita v4 addon by **DragoHorse** for **FFXI Retail**.
Find items across your bags, move and stack them, organise favourites and collections,
and manage crystals, seals and crests stored with NPCs.

## Install

1. Download the latest **InvMaster ZIP** from [Releases](https://github.com/ryuutatsuo23-max/InvMaster/releases/latest).
2. Extract the `invmaster` folder into your Ashita `addons` folder.
3. In game, run `/addon load invmaster`, then `/im` to open the window.

Updating? Wait for any transfers or NPC actions to finish, then unload the addon
before replacing its files. Your character settings are stored separately and are kept.

## Commands

| Command | Action |
| --- | --- |
| `/im` | Show or hide the main window |
| `/im find knuckles` | Open the window and search for an item |
| `/im monitor` | Show or hide the small bag monitor |
| `/im refresh` | Refresh bag contents |
| `/im status` | Print bag space and access information |

The window starts hidden on first use. Its open/closed state is saved per character
when the addon unloads and restored on reload. `/invmaster` and the old `/fms` alias also work.

## Features

- **Find your items:** search by name or item ID, filter by category, and sort or resize columns.
- **See what you own:** view total quantities, bag locations and duplicate stacks.
- **Move and stack:** right-click an item to move a quantity or its whole stack, or choose **Stack bag**.
- **Organise collections:** save favourites and create virtual bags such as Crafting or Fishing. These group items without moving them; right-click a collection item to withdraw it to Inventory.
- **Check your space:** use `/im monitor` for bag usage bars and free slots. Click a bag name to open its contents.
- **Prepare crafting materials:** optional CraftMaster integration retrieves missing ingredients through InvMaster. Preparation does not start crafting.

Filters, favourites, collections and monitor preferences save per character.
When Items is filtered to one bag, **Show all bags** clears that filter without changing your search or categories.
Transfers between two storage bags pass through Inventory, so leave space there too.
The move popup explains blocked items and unavailable destinations before you act.
Status lines distinguish current actions from the last result; **Clear result** dismisses old messages.

## Organize your bags (v0.17.0)

Open **Organize** to set quantities to keep in Inventory, choose storage bags,
or mark an item **Leave this item untouched**. Category rules provide defaults;
individual item destinations override them. Click **Apply** to save a rule, then
**View organization plan** to see proposed moves and anything blocking them.
Choose **Inventory** as the destination to gather all copies of an item there,
for example before selling. A keep quantity is not required.

Right-click an item and choose **Mark for selling** or **Mark for dropping**,
or enable one under **Item rules**. Marked items show **[sell]** or **[drop]**
and gather into Inventory when you preview and run
organization. Inaccessible bags or insufficient space appear as notices; preview
again when available. Nothing is sold or discarded automatically. **Leave untouched**
takes priority. Unmarking restores the previous destination and keep settings.

Saved item rules have a green **[rule]** marker. Click **Run organization** to
carry out the reviewed moves, one confirmed transfer at a time. Plans are limited
to 50 transfer steps per run; larger plans are split without changing your rules.
The preview separates **This run** from later moves. After a run finishes, view
a fresh plan and confirm again to continue. **Stop organization** (or `/im organizestop`) prevents
further sends; a move already sent still needs confirmation.

Optionally tick **Stack destination bags after this run** to combine partial
stacks after all moves finish. It starts off for each new preview and skips bags
containing items marked **Leave this item untouched**.

Rules start empty, save per character and cover all copies of an item ID.
Protection applies to organization and Sell / Drop, not your manual transfer controls.
Plans clear when bag contents or applied rules change. Nothing runs automatically.
See [organization details](docs/organization.md).

## Sell / Drop (v0.22.0)

Markers save per character and apply to future copies, even after selling or
dropping every current copy. Sell and Drop are mutually exclusive. Use Organize
first to gather marked items from accessible bags, then open **Sell / Drop**.

- **Sell:** open a normal NPC merchant's shop, stay within 6 yalms, and leave it
  open. Click **Preview sell marked items**, review the list, then
  **Confirm SELL listed items** to sell at that NPC's prices. Guild shops are not
  supported. Reopen the shop if its session expires or the addon was reloaded.
- **Drop:** click **Preview drop marked items**, review the list, then
  **Confirm DROP listed items**. This permanently discards every listed stack.

Only reviewed stacks already in Inventory are processed, one at a time.
Equipped, locked, unreadable and untouched items are skipped. Items that cannot
be sold are never changed to Drop automatically. **Stop disposal** cancels
remaining items; an already-sent request still needs confirmation. An uncertain
outcome locks further actions without retrying. Check Inventory before reloading.
Do not manually buy, sell or rearrange items during a run.

These actions have offline coverage; live sale and drop confirmation are still
pending. See [implementation and validation details](docs/disposal.md).

## Crystals, seals and crests

Open **Currency** and click **Refresh balances** to check your stored amounts.
Saved balances survive zoning and reloads; their timestamp shows how old they are.

Stand within **6 yalms** of the NPC with its normal menu closed. No targeting needed.

- **Ephemeral Moogle:** right-click a crystal and choose how many crystal units to withdraw. For example, **25 units = 2 clusters + 1 crystal**.
- **Shami in Port Jeuno:** right-click a seal or crest to withdraw it or exchange for an orb. Orb purchases show the cost and require confirmation.

Withdrawals check fresh balances and Inventory space before proceeding.

**Plan crystal deposit** previews crystals and clusters already in Inventory.
At any nearby **Ephemeral Moogle**, confirm a selected stack,
or choose **Preview deposit all crystals / clusters** then **Confirm deposit all**.
Deposit all processes up to eight Inventory stacks per trade, confirming each
trade before continuing. **Stop crystal deposits** cancels remaining batches.
See [deposit details](docs/crystal-deposits.md).

## Notes

- Only your current character's readable bags are searched. Other characters, delivery boxes and storage slips are not included.
- In Mog Garden, stand within 6 yalms of **Green Thumb Moogle** to recover bag access after loading. Supported **Nomad Moogles** in Rabao, Selbina, Mhaura, Kazham, Norg, Tavnazian Safehold and Nashmau provide Safe/Safe 2 and available Locker access, but not Storage. Keep the NPC menu closed. After reload in an ordinary Mog House, stand within 6 yalms of its Moogle; recovery also requires the live room-exit indicator.
- Stay idle while moving items. Do not manually rearrange bags or run another inventory mover during a transfer.
- Hiding the window does not cancel an action. If a move cannot be confirmed, check your bags before reloading; InvMaster does not retry it automatically.
- Moogle withdrawals have worked in Bastok Mines and another location, but not every Moogle or Shami exchange has been tested in game. CraftMaster preparation still needs a live check.

For development and troubleshooting, see [the technical notes](docs/).

## License

Copyright © 2026 **DragoHorse**. InvMaster's original code is licensed under
[GNU GPL v3.0](LICENSE). Third-party data retains its [original attribution and license](third_party/categories.md).
