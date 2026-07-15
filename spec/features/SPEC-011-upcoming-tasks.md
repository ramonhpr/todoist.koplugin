---
id: SPEC-011
title: Home Screen, Inbox View, and Upcoming Tasks View
status: DONE
created: 2026-06-30
updated: 2026-07-14
gate: G1
---

## Goal

Replace the direct-launch-to-Today behaviour with a **home navigation screen** that gives users
instant access to three task views — Inbox, Today, and Upcoming — from a single, consistent
entry point. The Upcoming view presents tasks grouped by date across a configurable range, with
a built-in date-picker to jump to any start date.

## Background

Previously, tapping the plugin icon opened the Today task list directly. An "Upcoming…" footer
button allowed browsing future dates from the Today view, but only via four fixed presets
(Tomorrow, In 2 days, This Weekend, Next Week). User feedback identified two gaps:

1. **Inbox access** — users frequently need to triage newly captured tasks without digging through Today.
2. **Upcoming flexibility** — fixed presets made it impossible to browse arbitrary future dates.

The new design addresses both: a home screen is the entry point for all views, and the Upcoming
view shows a multi-day grouped list (matching the layout of the Todoist mobile app) with a
KOReader-native `DateTimeWidget` date picker to jump to any start date.

The home screen always remains in KOReader's UIManager stack while any child view is open,
so closing a child view naturally reveals the home screen — no callback-based back-navigation
is required.

## Scope

### In scope

- A **home navigation screen** titled `"KO-Tasks for Todoist"` with entries for Inbox, Today,
  Upcoming, and Settings
- An **Inbox view** fetching `GET /tasks/filter?query=%23Inbox`, displaying a flat sorted task list
- An **Upcoming view** that:
  - Fetches tasks for a configurable date range (`next N days` or an ISO date-range query)
  - Groups tasks by due date with human-readable section headers (e.g. `"Mon 14 Jul · Today"`)
  - Exposes a tappable date-range item at the top that opens KOReader's `DateTimeWidget` to
    pick a custom start date
  - Supports a footer range-cycle button: 7 → 14 → 30 days → 7
- Applying sort (SPEC-007), assignee filter (SPEC-015), and project labels (SPEC-005) in all views
- Complete and Reschedule actions (SPEC-004, SPEC-009) in Inbox and Upcoming with optimistic
  update operating on the in-memory view task list only
- A `"← Home"` footer button in all three task views
- Offline detection for Inbox and Upcoming: show a notice and stay on the home screen

### Out of scope

- Caching Inbox or Upcoming results to disk (both are session-transient)
- A date-picker sub-menu with fixed presets (replaced by the grouped list + DateTimeWidget)
- Displaying multiple upcoming date ranges simultaneously
- Notifications for Inbox or Upcoming tasks (SPEC-002 is Today-scoped only)
- The `"📅  Upcoming…"` footer button on the Today view (removed)
- Group mode (SPEC-008) in Inbox/Upcoming (sort and filter only; grouping by project/priority
  is out of scope for these transient views)

## Requirements

### Home Screen

1. When the user taps the plugin icon, the plugin **MUST** display the home navigation screen
   before any task list.
2. The home screen **MUST** be titled `"KO-Tasks for Todoist"` and **MUST** display exactly the
   following entries in order:
   - `"Inbox"`
   - `"Today"`
   - `"Upcoming"`
   - a visual separator
   - `"Settings"`
3. Tapping `"Today"` **MUST** open the Today task list (existing SPEC-001 behaviour).
4. Tapping `"Inbox"` **MUST** open the Inbox view; if the device is offline the plugin **MUST**
   show a notice and remain on the home screen.
5. Tapping `"Upcoming"` **MUST** open the Upcoming view; if the device is offline the plugin
   **MUST** show a notice and remain on the home screen.
6. Tapping `"Settings"` **MUST** open the existing settings screen.

### Inbox View

7. The Inbox view **MUST** fetch tasks via `GET /tasks/filter?query=%23Inbox`.
8. The Inbox view title **MUST** follow the format `"Inbox  ·  by <sort> <dir>"`.
9. The Inbox view **MUST** render a flat sorted task list using the same row format as Today
   (priority prefix, title, due date, project label), with `show_date = true` so the full
   date is always visible on each row.
10. When the fetch returns zero tasks, the Inbox view **MUST** show `"No tasks in Inbox"`;
    when a non-`"all"` assignee filter is active and produces an empty list, the message
    **MUST** read `"No tasks match the current filter"`.
11. Inbox results **MUST NOT** be written to the disk cache; they **MUST** be discarded when
    the user returns to the home screen or closes the plugin.
12. Tasks in the Inbox view **MUST** support Complete and Reschedule (SPEC-004, SPEC-009) with
    optimistic update operating on the in-memory Inbox task list only.
13. If the Inbox fetch fails, the plugin **MUST** show an error message (same classification as
    Today) and **MUST** offer `"Refresh"` and `"Back"` buttons.

### Upcoming View

14. The Upcoming view **MUST** fetch tasks via `GET /tasks/filter?query=<encoded_query>` where
    the query is one of:
    - `next%20N%20days` (N = 7, 14, or 30) when no custom start date is set, anchored to today
    - An ISO date-range query `due%20after%3A%20<start-1>%20%26%20due%20before%3A%20<start+N>`
      when a custom start date has been set via the DateTimeWidget
15. The Upcoming view title **MUST** follow the format `"Upcoming — <range_label>  ·  by <sort> <dir>"`,
    where `<range_label>` is either `"Next N days"` or `"DD Mon – DD Mon YYYY"`.
16. At the **top of the item list** (before any tasks or empty-state message), the Upcoming view
    **MUST** render a tappable item displaying the current range label (e.g. `"[>] Next 7 days"`
    or `"[>] 14 Jul – 20 Jul 2026"`). Tapping it **MUST** open KOReader's `DateTimeWidget`
    pre-filled with the current start date (today if no custom date is set).
17. When the user confirms a date in the `DateTimeWidget`, the plugin **MUST** store that date as
    the new `upcoming_start_ts`, close the picker, and re-fetch immediately.
18. Tasks **MUST** be grouped by due date using `is_title = true` section headers formatted as
    `"<Day> <D> <Mon>"` (e.g. `"Mon 14 Jul"`), with `"· Today"` or `"· Tomorrow"` appended
    where applicable. Days with no tasks **MUST** be omitted.
19. Within each date group, tasks **MUST** be sorted by the active sort mode and direction
    (SPEC-007); `show_date = false` is used since the date appears in the section header.
20. When the fetch returns zero tasks, the Upcoming view **MUST** show
    `"No upcoming tasks in this range"`; when a non-`"all"` assignee filter produces an empty
    list the message **MUST** read `"No tasks match the current filter"`.
21. The Upcoming view footer **MUST** include a `"Range: N days"` cycle button that advances
    through 7 → 14 → 30 → 7 and immediately re-fetches.
22. Upcoming results **MUST NOT** be written to the disk cache.
23. Tasks in the Upcoming view **MUST** support Complete and Reschedule (SPEC-004, SPEC-009)
    with optimistic update operating on the in-memory Upcoming task list only.
24. If the Upcoming fetch fails, the plugin **MUST** show an error message and offer
    `"Refresh"` and `"Back"` buttons.

### Shared footer and sort/filter

25. All three task views (Inbox, Today, Upcoming) **MUST** include the following footer buttons:
    - Sort cycle (`"Sort: <mode>"`)
    - Direction toggle (`"Direction: <dir>"`)
    - Assignee filter cycle (`"Assignee: <mode>"`) (SPEC-015)
    - `"Refresh"` (re-fetches fresh data)
    - `"Settings"`
    - `"Back"` (closes the current menu; the home screen is revealed underneath)
26. The `"📅  Upcoming…"` footer button that existed on the Today view **MUST NOT** appear.
27. Tapping `"Back"` **MUST** call `UIManager:close(self._menu)`; no additional callback is
    required because the home screen remains in the UIManager stack.

## Edge Cases

- **Custom start date in the past**: the ISO date-range query is sent as-is; the server returns
  tasks for the requested range (may include overdue tasks); no special client-side handling.
- **Custom start date far in the future**: same — query sent as-is; the server returns results
  or an empty list.
- **DateTimeWidget cancelled**: `upcoming_start_ts` is unchanged; the view is not re-fetched.
- **Range changed while a custom start date is set**: the custom `upcoming_start_ts` is
  preserved; the new range is applied from the same start date.
- **"Back" tapped from Home → Today → Back**: Today menu closes; Home is visible again.
- **User completes an Upcoming task and taps "Back"**: the Today view is unaffected.
- **Network drops mid-fetch**: treated as a network error; error state shown with Refresh and
  Back buttons.
- **Inbox opened with "project" sort but project cache empty**: project labels omitted per
  SPEC-005 rules; no error shown.
- **Very long task title**: same 78-character truncation rules as SPEC-001 apply.
- **`upcoming_start_ts` set to today**: the ISO range query `due after: yesterday & due before: today+N`
  produces the same effective result as `next N days`; no special handling needed.

## Open Questions

<!-- None — all questions resolved. -->

## Related

- SPEC-001 — Today's task list (shared row format, title format, error patterns)
- SPEC-004 — Complete Task Action (optimistic-update pattern reused)
- SPEC-005 — Project display (project labels in all views)
- SPEC-007 — Sort order (applied in all views)
- SPEC-009 — Reschedule Task Action (available in Inbox and Upcoming)
- SPEC-015 — Assignee filter (applied in all views)
