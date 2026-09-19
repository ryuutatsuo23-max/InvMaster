# Bag monitor

Inspected installed InvMon1.1 (Ashita Development Team/atom0s, GPL3-or-later)
for behaviour: container toggles, used/capacity, background and low-space colours.
No implementation copied. `bag_monitor.lua` is independently written against
InvMaster's inventory_model snapshots and installed ImGui API annotations.
No new inventory reads, game packets, or writes to InvMon files/settings.

Defaults mirror the containers selected in the user's screenshot. Monitor is
opt-in; saved per character. Existing ImGui layout persists its window placement.
Clicking a container selects Items and clears text search without altering saved
category choices. Offline tests cover defaults/normalization, threshold edges,
unknown states, hidden-main-window operation, close persistence, profile isolation
and click navigation. Live layout/drag/click behaviour still needs confirmation.
