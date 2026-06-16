---
id: SPEC-004
title: Complete a Task
status: APPROVED
created: 2026-06-16
updated: 2026-06-16
gate: G1
---

## Goal

Allow the user to mark a task as complete directly from the task list, with the change reflected in Todoist.

## Background

Users need to act on their tasks, not just view them. Completing a task is the most common
write action in Todoist. Because the device may have a slow or intermittent connection,
completion uses an optimistic local update (task is removed from the list immediately) with
a background API call and rollback on failure. See ADR-004 (write operations).

## Scope

### In scope
- Mark a single task as complete via a tap-and-confirm interaction on the task list
- Optimistic removal from the local list and cache on confirm
- Background `POST /tasks/{id}/close` to the Todoist API
- Rollback and error message if the API call fails
- Retry option after failure
- Pending-completion indicator for tasks awaiting API confirmation

### Out of scope
- Re-opening (uncompleting) a task (future SPEC)
- Bulk completion of multiple tasks
- Completing sub-tasks
- Offline queue persistence across KOReader restarts (future SPEC)

## Requirements

1. Each task row in the task list must expose a **"Complete"** action; it must require a single deliberate interaction (tap on a checkmark icon or a "Complete" button) and a confirmation step to prevent accidental completion.
2. On confirmation, the task must be **immediately removed** from the visible list (optimistic update) and removed from the local cache.
3. A `POST /tasks/{task_id}/close` request must be dispatched in the background after the optimistic removal.
4. If the API call returns **204**, no further UI change is required; the task remains absent from the list.
5. If the API call returns any non-204 response or a network error, the task must be **restored** to its original position in the list and marked with a visual "sync pending" indicator (e.g. a small icon or italic style).
6. When a task is restored after failure, an error message must appear stating "Could not complete '[task title]'" with a **"Retry"** button and a **"Dismiss"** button.
7. Tapping "Retry" must re-dispatch `POST /tasks/{task_id}/close`; tapping "Dismiss" must leave the task in the list with the "sync pending" indicator visible until the next successful sync or manual refresh.
8. A task with a "sync pending" completion must be retried automatically when the next scheduled sync runs (see SPEC-002 Req 2 polling interval).
9. If the device is offline when the user completes a task, the task must still be removed optimistically and queued for retry; an "Offline — will sync when connected" toast must be shown.
10. The confirmation step must show the task title so the user can verify they are completing the correct task.

## Edge Cases

- User completes a task while a refresh is in progress: the optimistic removal must survive the refresh; the refreshed task list must not re-insert the just-completed task unless the API confirms it is still open
- Network drops after the POST is sent but before the 204 is received: treat as a failure (Req 5), restore the task; a duplicate completion server-side is harmless in Todoist
- User taps "Complete" on a task that has already been completed in another client (API returns 404 on close): treat as success — task is gone from Todoist, do not restore it
- Two rapid taps on the complete action before the first confirmation dialog closes: ignore the second tap
- Task list is empty after completion: show the empty state message (SPEC-001 Req 7)

## Open Questions

<!-- None — spec is APPROVED -->

## Related

- Architecture Decision: `architecture/adr/ADR-004-write-operations.md`
- Architecture Decision: `architecture/adr/ADR-001-todoist-api-auth.md`
- Architecture Decision: `architecture/adr/ADR-003-task-cache-strategy.md`
- Depends on: `SPEC-001-todays-task-list.md` (task list is the surface for this action)
- Agent Prompt: `agents/workflows/spec-to-code.md`
