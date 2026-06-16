---
id: ADR-002
title: Use UIManager scheduler for due-time notifications
status: ACCEPTED
date: 2026-06-16
---

## Context

KOReader has no persistent background daemon or cron system. Notifications must be driven
from within the running KOReader process. The platform provides `UIManager:scheduleIn(seconds, fn)`
which fires a callback after a delay within KOReader's event loop.

E-ink screens have slow refresh rates and notifications must not force a full-screen redraw
unless the user has opted in. KOReader's `InfoMessage` widget provides a non-blocking overlay
that fades after a configurable timeout and triggers only a partial refresh.

## Decision

Use **`UIManager:scheduleIn()`** to schedule a notification callback for each task whose due
time falls within the current session. On each callback:

1. Show an `InfoMessage` overlay with the task title and due time.
2. Re-schedule a "next check" sweep every N minutes (configurable, default 5) to pick up
   tasks added or updated since the last sync.

Notifications are only active while KOReader is running. No attempt is made to wake the
device from sleep.

## Consequences

- Notifications only fire while the app is in the foreground — acceptable for an e-reader
- The polling interval is configurable so users on slow Wi-Fi can reduce sync frequency
- No system-level notification (lock screen, push) — out of scope for v1
- If KOReader is closed before a task is due, the notification is silently missed

## Options Considered

| Option | Pros | Cons |
|--------|------|------|
| UIManager:scheduleIn() | Native, no extra deps, partial refresh | Only works while app is open |
| System cron / alarm (Kindle jailbreak) | Could wake device | Not portable, requires jailbreak |
| Poll on reader events (page turn, etc.) | Zero idle overhead | Unreliable timing |
