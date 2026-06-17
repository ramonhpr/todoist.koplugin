---
id: SPEC-008
title: Task List Grouping
status: DRAFT
created: 2026-06-16
updated: 2026-06-16
gate: G1
---

## Goal

Allow the user to group the task list into labelled sections — by project, priority, or due-date bucket — so that related tasks are visually clustered without leaving the today view.

## Background

The task list (SPEC-001) currently renders a flat, ungrouped list. KOReader's `Menu` widget (`ui/widget/menu`) supports non-interactive section header rows via items carrying `is_title = true`, which render as bold/dimmed separator entries with no tap callback. This mechanism makes grouping implementable without a custom widget and without requiring collapsible-section support, which the `Menu` widget does not provide natively.

Four grouping modes address the most-requested clustering patterns while keeping the feature surface small. The `"none"` default preserves today's flat-list behaviour for all existing users. Group mode is persisted via the settings layer described in SPEC-003, and section ordering within each group is governed by the active sort mode from SPEC-007 — the two features compose cleanly but are specified and implemented independently.

Project-based grouping depends on the project name data surfaced by SPEC-005. Date-bucket grouping introduces a set of named time windows (Overdue, Morning, Afternoon, Evening, All day) that mirror how users naturally think about their day in a reading-device context.

## Scope

### In scope
- Four grouping modes: `"none"`, `"project"`, `"priority"`, `"date"`
- Section header rows rendered using `is_title = true` items in the `Menu` widget
- Persistence of the selected grouping mode in settings under the key `group_mode`
- UI control (menu item or cycle button) on the task list screen to change the grouping mode
- Omission of empty sections from the rendered list
- Composed behaviour with SPEC-007 sort (sort governs task order within each group)

### Out of scope
- Collapsible or expandable sections
- Nested grouping (e.g. project then priority as a two-level hierarchy)
- Grouping by label or tag
- A dedicated grouping entry in the Settings screen (grouping is changed from the task list only)
- Any changes to the task fetch or filter logic

## Requirements

1. The plugin **must** read `group_mode` from settings on task list initialisation; if the key is absent the value **must** default to `"none"`.
2. When `group_mode` is `"none"`, the task list **must** render as a flat list with no section headers, identical to current behaviour.
3. When `group_mode` is `"project"`, the task list **must** render one section per project present in the current task set, with the **project name** as the section header label; sections **must** be ordered alphabetically (case-insensitive) by project name, with the Inbox section placed last.
4. The `"project"` grouping mode **must** use the project name data made available by SPEC-005; if project name data is unavailable for a task, that task **must** be placed in a section labelled `"Unknown Project"`.
5. When `group_mode` is `"priority"`, the task list **must** render up to four sections in the fixed order: `"P1 — Urgent"`, `"P2 — High"`, `"P3 — Medium"`, `"P4"`; each section contains only tasks whose Todoist API priority value matches that level.
6. When `group_mode` is `"date"`, the task list **must** render sections in the fixed order: `"Overdue"`, `"Morning (before 12:00)"`, `"Afternoon (12:00–17:00)"`, `"Evening (after 17:00)"`, `"All day"`; a task is placed in `"Overdue"` if its due datetime is before the current local time, in the appropriate time-window section if it has a time component due today, and in `"All day"` if it has no time component.
7. Section header items **must** be rendered using `is_title = true` and **must not** have a tap callback; tapping a section header **must** produce no action.
8. Any section that contains zero tasks **must** be omitted entirely from the rendered list.
9. Within each section, tasks **must** be ordered according to the active sort mode defined by SPEC-007.
10. The task list screen **must** expose a control (menu item or cycle button) that cycles through the grouping modes in the order `"none"` → `"project"` → `"priority"` → `"date"` → `"none"`.
11. Activating the grouping-change control **must** immediately re-render the task list with the new grouping applied without requiring the user to navigate away and back.
12. When the user changes the grouping mode, the new value **must** be written to settings so that the same mode is restored on the next plugin launch.
13. The grouping control **must not** appear on the Settings screen; it **must** only be accessible from within the task list screen.
14. If `group_mode` in settings contains an unrecognised value, the plugin **must** fall back to `"none"` and overwrite the invalid value.

## Edge Cases

- A task list in which all tasks belong to a single project must render exactly one section header followed by all tasks, with no empty sections, under `"project"` grouping.
- A task list in which every task is `"P4"` must render exactly one section under `"priority"` grouping; the three higher-priority sections must be omitted.
- In `"date"` grouping, a task whose due datetime is exactly midnight tonight (00:00 of tomorrow) must be classified by local time comparison, not by string comparison.
- In `"date"` grouping with an empty Overdue bucket, the `"Overdue"` section must be omitted and the next non-empty time-window section must appear first.
- In `"project"` grouping, multiple tasks sharing the same project must all appear under a single header, not duplicate headers, even if the project names differ only in case.
- An empty task list must render without section headers and without error under all four grouping modes.
- When both SPEC-007 sort and SPEC-008 grouping are active simultaneously, changing either one independently must not affect the other's persisted setting.
- Section header rows must not be counted or numbered as if they were tasks (e.g. no position indicator that treats them as list items).

## Open Questions

<!-- leave as HTML comment if none -->

## Related

- SPEC-001 — task list surface (the screen this feature modifies)
- SPEC-003 — settings persistence (`group_mode` key lives here)
- SPEC-005 — project names required by `"project"` grouping mode
- SPEC-007 — sort order (governs task ordering within each group)
