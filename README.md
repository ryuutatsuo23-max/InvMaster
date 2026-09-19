# InvMaster

An Ashita v4 addon by **DragoHorse** for **FFXI Retail**.
Find items across your bags, move and stack them, organise favourites and collections,
and manage crystals, seals and crests stored with NPCs.

## Install

1. Download **InvMaster-v0.14.0.zip** from [Releases](https://github.com/ryuutatsuo23-max/InvMaster/releases/latest).
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

The window starts hidden. `/invmaster` and the old `/fms` alias also work.

## Features

- **Find your items:** search by name or item ID, filter by category, and sort or resize columns.
- **See what you own:** view total quantities, bag locations and duplicate stacks.
- **Move and stack:** right-click an item to move a quantity or its whole stack, or choose **Stack bag**.
- **Organise collections:** save favourites and create virtual bags such as Crafting or Fishing. These group items without moving them; right-click a collection item to withdraw it to Inventory.
- **Check your space:** use `/im monitor` for bag usage bars and free slots. Click a bag name to open its contents.
- **Prepare crafting materials:** optional CraftMaster integration retrieves missing ingredients through InvMaster. Preparation does not start crafting.

Filters, favourites, collections and monitor preferences save per character.
Transfers between two storage bags pass through Inventory, so leave space there too.

## Crystals, seals and crests

Open **Currency** and click **Refresh balances** to check your stored amounts.
Saved balances survive zoning and reloads; their timestamp shows how old they are.

Stand within **6 yalms** of the NPC with its normal menu closed. No targeting needed.

- **Ephemeral Moogle:** right-click a crystal and choose how many crystal units to withdraw. For example, **25 units = 2 clusters + 1 crystal**.
- **Shami in Port Jeuno:** right-click a seal or crest to withdraw it or exchange for an orb. Orb purchases show the cost and require confirmation.

Withdrawals check fresh balances and Inventory space before proceeding.

## Notes

- Only your current character's readable bags are searched. Other characters, delivery boxes and storage slips are not included.
- For Safe, Safe 2, Storage and Locker transfers, leave and re-enter your Mog House after loading the addon. Nomad Moogle access is not supported.
- Stay idle while moving items. Do not manually rearrange bags or run another inventory mover during a transfer.
- Hiding the window does not cancel an action. If a move cannot be confirmed, check your bags before reloading; InvMaster does not retry it automatically.
- Moogle withdrawals have worked in Bastok Mines and another location, but not every Moogle or Shami exchange has been tested in game. CraftMaster preparation still needs a live check.

For development and troubleshooting, see [the technical notes](docs/).

## License

Copyright © 2026 **DragoHorse**. InvMaster's original code is licensed under
[GNU GPL v3.0](LICENSE). Third-party data retains its [original attribution and license](third_party/categories.md).
