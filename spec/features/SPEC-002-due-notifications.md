---
id: SPEC-002
title: Due-Time Notifications
status: DONE
created: 2026-06-16
updated: 2026-06-16
gate: G1
---

## Goal

Optionally notify the user with an on-screen message when a task's due time is reached while KOReader is running.

## Background

Users want a lightweight reminder system so they don't miss time-specific tasks while reading.
KOReader has no push notification infrastructure, so notifications are delivered as in-app overlays
via `UIManager:scheduleIn()`. This feature is opt-in by default.
See ADR-002 (notification mechanism).

## Scope

### In scope
- Opt-in notification toggle (off by default)
- Per-task `InfoMessage` overlay shown at the task's due time
- Configurable lead time: notify N minutes before the due time (default: 0 = at due time)
- Configurable polling interval: how often the scheduler re-checks for new/updated tasks (default: 5 min)
- Notifications only fire for tasks with a **time component** in their due date
- Notification dismissed automatically after a configurable timeout (default: 10 seconds)

### Out of scope
- System-level or lock-screen notifications
- Notifications for tasks without a specific due time
- Sound or vibration alerts
- Snoozeable notifications (future SPEC)
- Notifications when KOReader is closed

## Requirements

1. A **"Enable notifications"** toggle must exist in the plugin's Settings screen; it defaults to **off**.
2. When notifications are enabled, the plugin must schedule a check sweep every N minutes using `UIManager:scheduleIn()`; N must be configurable in Settings (1–60 min, default 5).
3. A **"Notify X minutes before"** setting must allow values of 0, 5, 10, 15, 30, and 60; default is 0 (at due time).
4. When a task's notification fires, an `InfoMessage` overlay must display: task title and the due time string (e.g. "Buy groceries — due 14:00").
5. The `InfoMessage` must auto-dismiss after a configurable timeout (5–60 seconds, default 10).
6. Each task must fire its notification **at most once per KOReader session** to prevent repeated alerts after a sync.
7. Notifications must only fire for tasks whose due object includes a `datetime` field (time-specific); date-only tasks must be silently skipped.
8. When notifications are **disabled**, no `UIManager` callbacks may be scheduled by the notification system.
9. Settings changes (toggle, lead time, interval) must take effect immediately without requiring a plugin restart.
10. If the task list is refreshed and a previously-notified task now has a different due time, its "already notified" state must be reset so it can fire again.

## Edge Cases

- KOReader is opened after a task's due time has already passed: do not fire a late notification for that task
- Multiple tasks due at the same time: show one `InfoMessage` per task, staggered by 2 seconds to avoid UI collision
- Notification fires while the task list screen is open: show normally; do not suppress
- User disables notifications while a callback is already scheduled: cancel the pending callback immediately
- Device enters sleep between the schedule and the callback: callback fires when the device wakes; if the task is now overdue by more than 30 minutes, suppress the notification silently

## Open Questions

<!-- None — spec is APPROVED -->

## Related

- Architecture Decision: `architecture/adr/ADR-002-notification-mechanism.md`
- Architecture Decision: `architecture/adr/ADR-003-task-cache-strategy.md`
- Depends on: `SPEC-001-todays-task-list.md` (task data source)
- Agent Prompt: `agents/workflows/spec-to-code.md`
