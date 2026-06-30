---
id: SPEC-011
title: Upcoming Tasks View
status: DRAFT
created: 2026-06-30
updated: 2026-06-30
resolved: 2026-06-30
gate: G1
---

## Goal

Let users browse tasks due on dates other than today — tomorrow, in two days, this weekend, next week — from within the plugin, without leaving KOReader.

## Background

The today view (SPEC-001) is limited to the current calendar day. Users preparing for the next day or planning the rest of the week currently have to open the Todoist mobile app on a separate device, which disrupts the reading flow.

The Todoist REST API v1 exposes the same `GET /tasks/filter?query=<expression>` endpoint already used by the today view, and the server resolves natural-language date expressions such as `"tomorrow"`, `"this saturday"`, and `"next monday"` natively. This makes preset-based upcoming browsing straightforward to implement without any local date arithmetic.

The upcoming view is intentionally transient: it is a temporary overlay that does not replace or invalidate the today view. Users enter it, browse or act on tasks, then return to today. This keeps the cache model simple — upcoming results are never written to disk — and avoids complicating the notification and overdue logic that is anchored to the today session.

Task actions (Complete, Reschedule) are available in the upcoming view using the same optimistic-update pattern from SPEC-004 and SPEC-009, so users can act on tomorrow's tasks immediately upon discovering them.

## Scope

### In scope
- A `"📅  Upcoming…"` footer menu item on the today task list
- A date-selection sub-menu with four preset options: Tomorrow, In 2 days, This Weekend, Next Week
- Fetching tasks for the selected date via `GET /tasks/filter?query=<encoded_query>`
- Displaying the results in a dedicated upcoming view titled `"Upcoming — <label>"`
- Applying the active sort mode and direction (SPEC-007) to the fetched tasks
- Project label display (SPEC-005) and priority prefixes on upcoming task rows
- Complete and Reschedule actions on upcoming tasks (SPEC-004, SPEC-009)
- Applying the active group mode (SPEC-008) to the fetched tasks, using the same section-header rendering as the today view
- A `"← Today"` footer button in the upcoming view that returns the user to the today list
- Offline detection with a meaningful error message

### Out of scope
- Caching upcoming results to disk (upcoming data is session-transient)
- Arbitrary date-picker input (presets only)
- Displaying multiple upcoming days simultaneously
- Notifications for upcoming tasks (SPEC-002 is today-scoped only)

## Requirements

1. The today task list footer **MUST** include a menu item labelled `"📅  Upcoming…"` that opens a date-selection sub-menu when tapped.
2. The date-selection sub-menu **MUST** offer exactly four presets with the following labels and Todoist query strings:

   | Label | Query string |
   |---|---|
   | Tomorrow | `tomorrow` |
   | In 2 days | `in 2 days` |
   | This Weekend | `this saturday` |
   | Next Week | `next monday` |

3. The date-selection sub-menu **MUST** include a `"Cancel"` entry that dismisses the sub-menu and returns the user to the today view without making any API call.
4. When the user selects a preset and the device is online, the plugin **MUST** display a loading indicator and then call `GET /tasks/filter?query=<URL-encoded query>` with the corresponding query string.
5. On a successful fetch, the plugin **MUST** display the results in a menu-style upcoming view titled `"Upcoming — <label>"` (e.g. `"Upcoming — Tomorrow"`).
6. The upcoming view title **MUST** include the active sort label and direction (e.g. `"Upcoming — Tomorrow · by Date ↑"`), consistent with the today view title format.
7. The upcoming view **MUST** apply the active sort mode and direction from SPEC-007 to the fetched tasks.
8. The upcoming view **MUST** apply the active group mode from SPEC-008 to the fetched tasks, rendering section headers using `is_title = true` items in the same way as the today view; empty sections **MUST** be omitted.
9. The upcoming view **MUST** display project labels (SPEC-005) and priority prefixes on each task row, using the same row format as the today view.
10. When the fetch returns zero tasks (and no group headers are shown), the upcoming view **MUST** show the message `"No tasks due on <label>"` (e.g. `"No tasks due on Tomorrow"`).
11. The upcoming view **MUST** include a footer `"← Today"` button that closes the upcoming view and restores the today task list.
12. Tasks in the upcoming view **MUST** support the Complete and Reschedule per-task actions (SPEC-004, SPEC-009) with the same optimistic-update and rollback semantics; a successfully completed upcoming task is removed from the upcoming view only.
13. If the fetch fails (network error, 401, 429, etc.), the plugin **MUST** display an error message inside the upcoming view using the same error-classification patterns as the today view, and **MUST** offer both a `"↺ Retry"` and a `"← Today"` button.
14. If the device is offline when the user selects a preset, the plugin **MUST** display a notice stating that an internet connection is required, **MUST NOT** navigate away from the today view, and **MUST NOT** attempt the API call.
15. Upcoming task data **MUST NOT** be written to the disk cache; all upcoming results **MUST** be discarded when the user returns to the today view or closes the plugin.
16. While an upcoming fetch is in progress, the plugin **MUST** prevent a second upcoming fetch from starting (e.g. by disabling the `"📅  Upcoming…"` button or showing the loading indicator).

## Edge Cases

- `"This Weekend"` selected on a Saturday or Sunday: `"this saturday"` is resolved server-side; the plugin passes the literal string and does no local date arithmetic.
- `"Next Week"` selected on a Monday: `"next monday"` resolves to the following Monday server-side; no special handling in the plugin.
- User completes an upcoming task and taps `"← Today"`: the today view is unaffected — the completed task was not in today's list.
- User reschedules an upcoming task to today from the upcoming view: the task is removed from the upcoming view; the today list is not immediately updated (it refreshes on next sync or explicit refresh).
- Network drops mid-fetch: treat as a network error; show the error state within the upcoming view with Retry and `"← Today"` buttons.
- Very long task title in the upcoming view: the same truncation rules from SPEC-001 apply (78-character row limit).
- Upcoming view opened with `"project"` sort mode but the project cache is empty: project labels are omitted per SPEC-005 rules; no error is shown.
- Upcoming view opened with `"project"` group mode but the project cache is empty: all tasks fall into the `"Unknown Project"` group per SPEC-008 rules; no error is shown.
- `"date"` group mode active in the upcoming view: time-bucket section headers (Morning, Afternoon, Evening, All day) apply normally; the `"Overdue"` bucket is conceptually irrelevant for future dates but **MUST** still be rendered for any task the API returns whose due datetime compares as past at render time.
- User rapidly taps `"📅  Upcoming…"` multiple times: only one sub-menu may be open at a time; subsequent taps before the first closes must be ignored.

## Open Questions

<!-- None — all questions resolved. -->

## Related

- SPEC-001 — Today's task list (base view; upcoming is an overlay on top of it)
- SPEC-004 — Complete Task Action (optimistic-update pattern reused in upcoming view)
- SPEC-005 — Project display (project labels shown on upcoming task rows)
- SPEC-007 — Sort order (sort mode and direction applied within upcoming view)
- SPEC-008 — Task grouping (group mode applied within upcoming view)
- SPEC-009 — Reschedule Task Action (available on upcoming tasks)
