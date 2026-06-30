---
id: SPEC-010
title: Overdue Tasks in Today View
status: DRAFT
created: 2026-06-30
updated: 2026-06-30
resolved: 2026-06-30
gate: G1
---

## Goal

Surface tasks that are past their due date within the today view so users can see and act on outstanding work without switching contexts.

## Background

The today view (SPEC-001) fetches tasks using the `today` filter (`GET /tasks/filter?query=today`), which returns only tasks due on the current calendar day. Tasks whose due date has already passed are silently excluded, leaving users unaware of outstanding commitments visible in the Todoist app but not in the plugin.

Todoist exposes an `overdue` filter via the same `GET /tasks/filter` endpoint already used by the today view. Overdue tasks are a natural extension of the today surface — users need to address them before they can clear their day. Displaying them as a distinct "⚠ Overdue" section above today's tasks mirrors the layout of the Todoist mobile app and leverages the section-header mechanism already planned in SPEC-008.

Overdue tasks participate in the same task-action model established by SPEC-004 and SPEC-009: they can be completed or rescheduled through the same per-task action menu, with the same optimistic-update and rollback behaviour. Project label resolution from SPEC-005 applies identically.

Storage follows ADR-003: a new `overdue_tasks` key is added to the existing `todoist_cache.lua` LuaSettings file, avoiding a second cache file and keeping invalidation logic centralised.

## Scope

### In scope
- Fetching overdue tasks from `GET /tasks/filter?query=overdue` on each sync, alongside today's tasks
- Storing overdue tasks under the key `overdue_tasks` in the existing LuaSettings cache file (ADR-003)
- Rendering a non-tappable "⚠ Overdue" section header above today's tasks when at least one overdue task is present
- Displaying overdue task rows using the same row format as today's tasks (priority prefix, title, project label, detail sub-row)
- Applying the active sort mode and direction (SPEC-007) within the overdue section independently of today's section
- Supporting Complete and Reschedule (SPEC-004, SPEC-009) on overdue tasks
- A settings toggle `show_overdue` (boolean, default `true`) that controls visibility of the overdue section
- Reflecting the overdue count in the task list title bar when the section is visible

### Out of scope
- Batch-completing or batch-rescheduling all overdue tasks in one action
- Filtering or grouping the overdue section separately from the today section
- A dedicated overdue-only view (overdue always appears inline within the today view)
- Notifications for overdue tasks (SPEC-002 is today-scoped)
- Pagination beyond the first API page (same 50-task default as today's tasks)

## Requirements

1. When the plugin syncs (explicit or background), it **MUST** issue two sequential API requests in the following fixed order: first `GET /tasks/filter?query=today`, then `GET /tasks/filter?query=overdue`. The overdue request **MUST NOT** begin until the today request has completed (successfully or via fallback). Both results **MUST** be available before the task list is rendered.
2. Overdue tasks **MUST** be stored under the key `overdue_tasks` in the same LuaSettings cache file as today's tasks, following ADR-003.
3. A user-visible settings toggle `show_overdue` (boolean, default `true`) **MUST** control whether the overdue section is displayed; it **MUST** be readable and writable via the Settings screen (SPEC-003).
4. When `show_overdue` is `true` and at least one overdue task exists, the task list **MUST** render a non-tappable section header labelled `"⚠ Overdue"` immediately above today's tasks, using `is_title = true` (the same mechanism as SPEC-008).
5. When `show_overdue` is `true` and no overdue tasks exist, the section header **MUST** be omitted and the list **MUST** render identically to the current today-only view.
6. When `show_overdue` is `false`, the overdue section and its header **MUST** be omitted entirely, regardless of whether overdue tasks exist.
7. When the overdue section is visible, the task list title bar **MUST** include the overdue count (e.g. `"Todoist — Today · 2 overdue · by Date ↑"`); when the section is hidden or empty the overdue count **MUST NOT** appear.
8. Tasks in the overdue section **MUST** be sorted by the active sort mode and direction (SPEC-007) independently of today's tasks.
9. Overdue tasks **MUST** support the Complete and Reschedule actions (SPEC-004, SPEC-009) with the same optimistic-update and rollback semantics; an optimistically removed overdue task **MUST** be removed from the overdue list, not the today list.
10. If the `GET /tasks/filter?query=overdue` request fails, the plugin **MUST** fall back to any cached overdue data; if no prior cache exists, the overdue section **MUST** be omitted and the failure **MUST NOT** prevent today's tasks from rendering.
11. The overdue task cache **MUST** be invalidated and re-fetched whenever the task cache is explicitly refreshed by the user (same cycle as today's tasks).
12. A task whose `id` appears in both the overdue and today API results **MUST** be deduplicated: it **MUST** appear only in the overdue section and **MUST NOT** appear in today's section.

## Edge Cases

- Zero overdue tasks: the "⚠ Overdue" header must not appear; the list renders identically to the pre-SPEC-010 today view.
- All tasks are overdue and none are due today: only the overdue section renders; the today section is omitted (no "No tasks due today" empty state, since the screen is not empty).
- The `overdue_tasks` cache key is absent or corrupted: treat as an empty overdue list; do not raise an error.
- A task is completed from the overdue section while offline: the same offline-optimistic behaviour from SPEC-004 applies.
- A task is rescheduled from the overdue section to today: the task is removed from the overdue list; it will appear in today's list on the next full refresh, not immediately.
- Very large overdue list (50+ tasks returned on the first page): render all results without additional pagination; the count in the title reflects the number of visible overdue tasks.
- `show_overdue` toggled while the task list is open: the change must take effect immediately on the next render (no restart required).

## Open Questions

<!-- None — all questions resolved. -->

## Related

- SPEC-001 — Today's task list (base view this feature extends)
- SPEC-003 — Settings screen (`show_overdue` toggle lives here)
- SPEC-004 — Complete Task Action (optimistic-update pattern reused)
- SPEC-005 — Project display (project labels applied to overdue rows)
- SPEC-007 — Sort order (applied within overdue section)
- SPEC-008 — Task grouping (section-header mechanism reused)
- SPEC-009 — Reschedule Task Action (available on overdue tasks)
- ADR-003 — Cache strategy (`overdue_tasks` key added to existing cache file)
