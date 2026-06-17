---
id: SPEC-007
title: Task List Sort Order
status: DRAFT
created: 2026-06-16
updated: 2026-06-16
gate: G1
---

## Goal

Allow the user to choose how tasks are ordered in the task list by selecting one of three sort modes — Date, Priority, or Project — with the chosen mode persisted across sessions and displayed in the task list title bar.

## Background

The task list (SPEC-001) currently sorts tasks in `ui/tasklist.lua` `_render()` with a hardcoded two-level rule: time-specific due tasks appear first in ascending time order, followed by all-day tasks, with ties broken by priority descending (API value 4 = highest). This ordering is sensible as a default but gives users no control.

Three named sort modes cover the most common user workflows without introducing the complexity of a general-purpose multi-level sort configuration UI. The `"date"` mode preserves the existing hardcoded behaviour exactly, ensuring a non-breaking default for all current users. Sort mode is persisted via the settings layer described in SPEC-003 so the user's choice survives plugin restarts.

SPEC-008 (task grouping) composes with this feature: when grouping is active, the sort mode governs the ordering of tasks *within* each group. The two features are specified and implemented independently; neither blocks the other, but their interaction must be considered during implementation of whichever ships second.

## Scope

### In scope
- Three sort modes: `"date"`, `"priority"`, `"project"`
- Persistence of the selected sort mode in settings under the key `sort_mode`
- Display of the active sort mode in the task list title bar or as a subtitle line
- UI control (menu item or cycle button) on the task list screen to change the sort mode
- Correct composed behaviour with SPEC-008 grouping (sort applies within each group)

### Out of scope
- Custom sort expressions or user-defined sort keys
- Sort by label or tag
- Multi-level sort configuration UI (e.g. "primary sort + secondary sort" pickers)
- A dedicated sort entry in the Settings screen (sort is changed from the task list only)
- Any changes to the task fetch or filter logic

## Requirements

1. The plugin **must** read `sort_mode` from settings on task list initialisation; if the key is absent the value **must** default to `"date"`.
2. The `"date"` sort mode **must** order tasks identically to the current hardcoded behaviour: time-specific due tasks ascending by due time, followed by all-day tasks, with ties at any level broken by priority descending (API value 4 first).
3. The `"priority"` sort mode **must** order tasks by **priority** descending (API value 4 first through 1 last), with ties broken by due time ascending (tasks with no due time sorted after tasks that have one).
4. The `"project"` sort mode **must** order tasks alphabetically by **project name** ascending (case-insensitive), with ties broken by due time ascending (no-due-time tasks last within a project).
5. The `"project"` sort mode **must** use the project name data made available by SPEC-005; if project name data is unavailable for a task, that task **must** sort as if its project name is an empty string (sorts first alphabetically).
6. The task list **must** display the active sort mode in the title bar or as a subtitle line in a human-readable form (e.g. `Todoist — Today  ·  by Priority`).
7. The task list screen **must** expose a control (menu item or cycle button) that cycles through the three sort modes in the order `"date"` → `"priority"` → `"project"` → `"date"`.
8. Activating the sort-change control **must** immediately re-render the task list in the new sort order without requiring the user to navigate away and back.
9. When the user changes the sort mode, the new value **must** be written to settings so that the same mode is restored on the next plugin launch.
10. When SPEC-008 grouping is active, the sort mode **must** be applied to tasks within each individual group rather than across the whole flat list.
11. The sort control **must not** appear on the Settings screen; it **must** only be accessible from within the task list screen.

## Edge Cases

- Tasks with no due date in `"date"` mode must always sort after all tasks that have a due date (time-specific or all-day).
- Tasks with no due time (all-day) in `"priority"` mode must sort after tasks with a due time when priority is equal.
- In `"project"` mode, tasks belonging to the Todoist Inbox (which has no user-visible project name beyond "Inbox") must sort using the literal string `"Inbox"` as their project name.
- If `sort_mode` in settings contains an unrecognised value, the plugin must fall back to `"date"` and overwrite the invalid value.
- A task list containing only one task must render without error under all three sort modes.
- An empty task list must render without error under all three sort modes.
- Sort must be stable: two tasks that compare equal under all tiebreaker rules must retain their original API response order relative to each other.

## Open Questions

<!-- leave as HTML comment if none -->

## Related

- SPEC-001 — task list surface (the screen this feature modifies)
- SPEC-003 — settings persistence (`sort_mode` key lives here)
- SPEC-005 — project data required by `"project"` sort mode
- SPEC-008 — task grouping (composes with sort; sort applies within groups)
