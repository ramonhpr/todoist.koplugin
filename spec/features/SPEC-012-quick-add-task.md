---
id: SPEC-012
title: Quick Add Task
status: DRAFT
created: 2026-06-30
updated: 2026-06-30
resolved: 2026-06-30
gate: G1
---

## Goal

Allow users to create a new Todoist task — including a natural-language due date parsed by the server — from within KOReader without opening the Todoist mobile app.

## Background

Users frequently want to capture tasks while reading or browsing on their e-ink device. Switching to the Todoist mobile app interrupts the reading flow. The Todoist REST API v1 `POST /tasks` endpoint accepts a `content` field (the task title) and an optional `due_string` field containing a natural-language date expression such as `"today at 3pm"` or `"next Friday"`. The server is fully responsible for parsing and resolving the date, so no local date arithmetic is needed in the plugin.

KOReader provides a `MultiInputDialog` widget that renders multiple labelled text fields on e-ink hardware. A single dialog with two fields — task name (required) and due date (optional) — lets users fill in both values and confirm in one step, which minimises the number of screen transitions on a slow e-ink display.

Task creation follows the same write-operation design established by ADR-004: the API call is made synchronously inside a `NetworkMgr:runWhenConnected` callback. On success the today task list is immediately refreshed and the notification schedule is updated (SPEC-002) so that any newly-due-today task with a time component fires its notification correctly.

## Scope

### In scope
- A `"＋  Add Task"` footer button on the today task list
- A single `MultiInputDialog` with two fields: task name (required) and due date (optional)
- Calling `POST /tasks` with `content` and, when provided, `due_string`; tasks are always created in the Inbox (no `project_id` sent)
- A new `Api:createTask(payload)` method in `api.lua`
- Refreshing the today task list after successful task creation
- Re-scheduling notifications (SPEC-002) after the post-creation list refresh
- Offline detection with a meaningful error message

### Out of scope
- Setting priority, labels, or comments at creation time (future SPEC)
- Project selection at creation time (tasks always go to Inbox)
- A `default_project_id` setting (not needed; Inbox is the fixed destination)
- Offline queuing of task creation requests
- Editing existing tasks (SPEC-009 handles rescheduling; general editing is a future SPEC)
- Subtask creation

## Requirements

1. The today task list footer **MUST** include a menu item labelled `"＋  Add Task"`.
2. Tapping `"＋  Add Task"` **MUST** open a KOReader `MultiInputDialog` titled `"New Task"` containing exactly two input fields in order:
   - **Task name** — label `"Task name"`, hint `"What needs to be done?"`, required.
   - **Due date** — label `"Due date (optional)"`, hint `"e.g. today, tomorrow at 3 pm, next Friday"`, optional.
3. The dialog **MUST** provide a **Save** button and a **Cancel** button.
4. Tapping **Cancel** **MUST** close the dialog and return the user to the today task list without making any API call; no partial state is saved.
5. If the user taps **Save** with an empty or whitespace-only task name, the dialog **MUST** remain open and display the inline validation message `"Task name cannot be empty"`. The task name field **MUST** be trimmed of leading and trailing whitespace before this check.
6. The due-date field **MUST** be treated as optional: if the user leaves it blank or enters only whitespace, the plugin **MUST** proceed to task creation with no `due_string` in the request body.
7. The plugin **MUST** call `POST /tasks` via a new `Api:createTask(payload)` method in `api.lua`, with a JSON body of at minimum `{"content": "<trimmed name>"}`, plus `"due_string": "<trimmed due text>"` when the user provided a non-empty due-date value. The request body **MUST NOT** include a `project_id` field; tasks are always created in the user's Inbox.
8. On a successful API response (HTTP 200 with a task object), the plugin **MUST** close the dialog, show a brief `InfoMessage` confirmation (e.g. `"Task added"`), trigger an immediate refresh of the today task list, and then call `notifications:scheduleTaskNotifications` with the refreshed task list so that any newly-added task with a due time today is scheduled for notification.
9. On an API failure, the plugin **MUST** display the appropriate error message using the same error-classification patterns as the today view, and **MUST** offer the user a **Retry** button and a **Dismiss** button; if the user retries, the same `content` and `due_string` values **MUST** be re-submitted without requiring re-entry.
10. If the device is offline when the user taps **Save**, the plugin **MUST** show a notice stating that creating a task requires an internet connection, **MUST NOT** attempt the API call, and **MUST** leave the dialog open so the user can wait for connectivity or cancel.
11. The `"＋  Add Task"` button **MUST** be guarded against double-tap: while the add-task dialog is open or an API call is in progress, tapping the footer button again **MUST** produce no effect.
12. `Api:createTask(payload)` **MUST** be implemented in `api.lua` as `self:_request("POST", "/tasks", payload)`, consistent with the existing `Api:updateTask` pattern, and **MUST** return `(task_object, nil)` on success or `(nil, err_string)` on failure.

## Edge Cases

- Task name contains only whitespace: trim and reject per Requirement 5; the dialog stays open with the validation message.
- Due-date field left blank: treat as no due date — omit `due_string` from the request body per Requirement 6.
- Due string that Todoist cannot parse (e.g. `"asdfgh"`): the API returns an error; the plugin treats this as an API failure per Requirement 9 and allows the user to correct the due string on retry.
- The new task's due date is today and the today list is already loaded: the refresh triggered by Requirement 8 fetches a fresh list and reschedules notifications, so the new task appears and its notification fires without the user manually tapping Refresh.
- The new task's due date is not today (e.g. `"next Friday"`): the refresh re-fetches today's tasks; the new task will not appear in the today view, which is correct.
- The new task has a due time today but the notification for that time has already passed: `scheduleTaskNotifications` will not schedule a callback in the past; this is existing behaviour and requires no special handling.
- API returns HTTP 200 but the response body does not contain a valid task object: treat as a success (the list refresh will include it if due today); do not raise an error.
- The `MultiInputDialog` is open and the screen auto-locks: on resume the dialog should still be visible or the user should be returned safely to the task list.

## Open Questions

<!-- None — all questions resolved. -->

## Related

- SPEC-001 — Today's task list (footer button added here; list refreshed on success)
- SPEC-002 — Due notifications (notification schedule updated after creation)
- SPEC-004 — Complete Task Action (establishes the write-operation + optimistic-update pattern)
- ADR-001 — API authentication (Bearer token used in `POST /tasks`)
- ADR-004 — Write operations design (pattern for `createTask` implementation)
