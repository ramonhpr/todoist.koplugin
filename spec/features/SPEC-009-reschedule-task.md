---
id: SPEC-009
title: Reschedule Task Action
status: DRAFT
created: 2026-06-16
updated: 2026-06-16
gate: G1
---

## Goal

Add a **Reschedule** action to the per-task action menu so that users can push a task's due date forward to a preset target (Tomorrow, Later this week, This weekend, Next week, or — for recurring tasks — Postpone) without leaving KOReader.

## Background

SPEC-004 introduced per-task completion via a `ConfirmBox` dialog triggered by tapping a task row. That dialog currently offers a single **Complete** action. As reading sessions frequently surface tasks that are relevant but not actionable right now, users need a lightweight way to defer work without opening the Todoist mobile app.

Rescheduling is implemented through the Todoist REST API v1 `POST /tasks/{task_id}` endpoint, which accepts a `due_string` field containing a natural-language date expression that the server resolves. No local date arithmetic is required in the plugin. Recurring tasks are a special case: advancing a recurring task to its next occurrence must be done via `POST /tasks/{task_id}/close` (the same endpoint used by SPEC-004 for completion), because patching `due_string` alone does not shift the recurrence pattern.

A rescheduled task ceases to match Todoist's `today` filter and must be removed from the visible list, following the same optimistic-update-with-rollback pattern established by SPEC-004. Offline rescheduling is not queueable because the server is responsible for parsing the natural-language string and returning the resolved date; the plugin cannot replicate that logic locally.

## Scope

### In scope

- Replacing the current single-action `ConfirmBox` (SPEC-004) with a three-button dialog: **Complete**, **Reschedule**, **Cancel**
- A second-level preset menu offering: Tomorrow, Later this week, This weekend, Next week
- A **Postpone** option in the preset menu, shown only when `due.is_recurring == true`
- Calling `POST /tasks/{task_id}` with the appropriate `due_string` for non-recurring reschedules
- Calling `POST /tasks/{task_id}/close` for the Postpone action on recurring tasks
- Optimistic removal of the rescheduled task from the visible list, with rollback on API failure
- Surfacing a network-unavailable error when the device is offline at the moment the user confirms a reschedule

### Out of scope

- Free-form due date or time input (planned for a future SPEC)
- Editing task content, priority, labels, or project
- Recurring task pattern modification
- Bulk reschedule of multiple tasks
- Offline queuing of reschedule requests

## Requirements

1. **Primary action dialog**: When the user taps a task row, the plugin **must** display a dialog containing exactly three buttons — **Complete**, **Reschedule**, and **Cancel** — replacing the previous two-button dialog introduced in SPEC-004.

2. **Cancel behaviour**: Tapping **Cancel** in the primary action dialog **must** dismiss the dialog and leave the task list unchanged.

3. **Reschedule submenu**: Tapping **Reschedule** in the primary action dialog **must** close that dialog and open a second menu listing the preset options: **Tomorrow**, **Later this week**, **This weekend**, **Next week**.

4. **Postpone option visibility**: The **Postpone** option **must** appear in the reschedule submenu if and only if the tapped task has `due.is_recurring == true`; it **must not** appear for non-recurring tasks.

5. **Submenu cancel**: The reschedule submenu **must** provide a way to dismiss it (e.g. a **Back** or **Cancel** entry, or the hardware back key) that returns the user to the task list without modifying any task.

6. **due_string mapping**: When the user selects a preset, the plugin **must** send the following `due_string` values to the API: Tomorrow → `"tomorrow"`, Later this week → `"in 3 days"`, This weekend → `"this saturday"`, Next week → `"next monday"`.

7. **Non-recurring reschedule API call**: For any preset other than Postpone, the plugin **must** call `POST /tasks/{task_id}` with a JSON body of `{"due_string": "<value>"}` and the user's Bearer token in the `Authorization` header.

8. **Postpone API call**: When the user selects **Postpone** on a recurring task, the plugin **must** call `POST /tasks/{task_id}/close` and **must not** call the update endpoint with a `due_string`.

9. **Optimistic update**: Immediately upon the user confirming a preset selection, the plugin **must** remove the task from the visible list before the API response is received.

10. **Rollback on failure**: If the API call returns a non-2xx status code or a network error, the plugin **must** re-insert the task into the visible list at its original position and display an error notice describing the failure.

11. **Success — no restoration**: If the API call returns HTTP 200, the plugin **must not** re-insert the task into the visible list, because a rescheduled task no longer matches the `today` filter.

12. **Offline detection**: If the device has no network connectivity when the user confirms a preset selection, the plugin **must** display an error notice stating that rescheduling requires a network connection, and **must not** attempt the API call or remove the task from the visible list.

13. **Existing Complete action unchanged**: The **Complete** button in the updated primary action dialog **must** trigger exactly the same behaviour as the confirm action from SPEC-004, with no change to its API call, optimistic-update logic, or rollback logic.

14. **Single in-flight request**: While a reschedule API call is in progress for a task, the plugin **must** prevent the user from triggering a second action (complete or reschedule) on the same task until the first call settles.

## Edge Cases

- Task has a due date but `due.is_recurring` is `nil` or `false` — Postpone must not appear
- Task has no due date at all (`due` field is absent) — Postpone must not appear; remaining presets still apply
- API call succeeds but returns a task object whose `due.date` is today (e.g. Todoist resolved "tomorrow" to today because of timezone handling) — still remove the task from the list, as the server is authoritative
- User taps a preset and immediately loses network mid-request — treat as a network error and roll back
- "Later this week" selected on a Thursday or Friday — `"in 3 days"` may land on the weekend or next week; no special handling required, as the server resolves this
- Postponing a recurring task via `/close` causes the task to disappear from today's list — handle identically to a regular reschedule removal (optimistic update already applied)
- Device clock is wrong — irrelevant, because all date arithmetic happens on the Todoist server
- The reschedule submenu is open and the screen auto-locks — on resume the submenu should still be visible or the user should be returned safely to the task list

## Open Questions

<!-- leave as HTML comment if none -->

## Related

- SPEC-004 — Complete Task Action (introduces per-task `ConfirmBox`, optimistic-update pattern, and `/close` endpoint usage)
- SPEC-001 — Plugin architecture and HTTP client abstraction
- SPEC-002 — Task list rendering and row tap handling
- ADR-003 — Optimistic UI updates with rollback
