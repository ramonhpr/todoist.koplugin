---
id: ADR-004
title: Write operations use optimistic local update then API confirm
status: ACCEPTED
date: 2026-06-16
---

## Context

Task completion is the first write operation in the plugin. Two strategies exist for
updating local state after a write: wait for the API to confirm before updating the UI
("pessimistic"), or update the UI immediately and roll back on failure ("optimistic").

On an e-ink device, round-trip latency from Wi-Fi association to API response can be 2–5
seconds. A pessimistic update would leave the user staring at a frozen screen waiting for
confirmation, which is a poor experience. Completion is also a low-risk, reversible
operation in Todoist (tasks can be re-opened), so the cost of a brief inconsistency is low.

The Todoist API v1 endpoint for completing a task is:
`POST /tasks/{task_id}/close` — returns HTTP 204 No Content on success.

## Decision

Use an **optimistic local update** strategy for task completion:

1. Immediately remove (or strike-through) the task from the local list and cache
2. Fire `POST /tasks/{task_id}/close` in the background
3. If the API call succeeds (204): no further action needed
4. If the API call fails: restore the task in the list, show an error message with a
   "Retry" option, and mark the task with a "sync pending" indicator

A write queue (`taskstore.lua`) will hold pending completion requests so they can be
retried if Wi-Fi becomes available mid-session.

## Consequences

- UI feels instant on slow connections
- A brief window of inconsistency between local state and Todoist is acceptable
- Rollback logic must be implemented and tested
- Tasks completed offline will be queued and retried; if KOReader is closed before retry,
  the completion is lost (acceptable for v1; silent queue flush on close)
- No new authentication mechanism needed — same Bearer token from ADR-001

## Options Considered

| Option | Pros | Cons |
|--------|------|------|
| Optimistic update + rollback | Instant UI, good UX | Rollback complexity |
| Pessimistic (wait for API) | Simpler, always consistent | Slow on e-ink, bad UX |
| Queue-only (offline-first) | Works fully offline | Complex sync engine, out of scope |
