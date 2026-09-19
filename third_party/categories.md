# Item category data

`category_data.lua` contains item-ID/category facts extracted from LandSandBoat's
`sql/item_basic.sql`, commit `60a09d1e00be2a4dc34b75df6cbf9c3f97a89f19`:
https://github.com/LandSandBoat/server/blob/60a09d1e00be2a4dc34b75df6cbf9c3f97a89f19/sql/item_basic.sql

LandSandBoat contributors' project license is included in `LandSandBoat-LICENSE`.
No server implementation code or item names are included in this lookup.
Regenerate with `python tools/build_categories.py path/to/item_basic.sql`.
Categories are a pinned reference, not a guarantee for custom server items.
Unmapped items remain Other / Unknown; live client equipment slots take priority.
