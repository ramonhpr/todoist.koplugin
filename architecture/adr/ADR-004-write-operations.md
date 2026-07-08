---
id: ADR-004
title: Write operations use optimistic local update then API confirm
status: ACCEPTED
date: 2026-06-16
---

## Context

Several write operations exist in the plugin. Two strategies exist for
updating local state after a write: wait for the API to confirm before updating the UI
("pessimistic"), or update the UI immediately and roll back on failure ("optimistic").

On an e-ink device, round-trip latency from Wi-Fi association to API response can be 2–5
seconds. A pessimistic update would leave the user staring at a frozen screen waiting for
confirmation, which is a poor experience. The write operations in scope are low-risk and
reversible in Todoist, so the cost of a brief inconsistency is low.

Write operations using this pattern:
- **Complete a task** — `POST /tasks/{id}/close` (SPEC-004)
- **Reschedule a task** — `POST /tasks/{id}` with `due_string` (SPEC-009)
- **Complete / reschedule in the upcoming view** — same endpoints, in-memory list only (SPEC-011)
- **Create a task** — `POST /tasks` (SPEC-012)

## Decision

Use an **optimistic local update** strategy for all write operations:

1. Immediately remove or update the task in the local list
2. Fire the appropriate API call
3. If the API call succeeds: confirm and clean up pending state
4. If the API call fails: restore the task in the list, show an error message with a
   "Retry" option, and mark the task with a "sync pending" (`⚠`) indicator

For **task creation** (SPEC-012) no optimistic removal applies; instead, a full list
refresh is triggered on success so newly-due tasks appear immediately.

## Consequences

- UI feels instant on slow connections for all write operations
- A brief window of inconsistency between local state and Todoist is acceptable
- Rollback logic must be implemented for each write operation type
- `TaskStore` tracks `pending_completions` with an `orig_index` and `from_overdue` flag
  so rollback always restores a task to the correct list at the correct position
- Upcoming view (SPEC-011) manages its own in-memory pending state, never touching
  `TaskStore`, since upcoming results are not persisted
- Tasks completed offline stay removed optimistically; if KOReader is closed before
  the API call can be retried, the completion is lost (acceptable trade-off)
- No new authentication mechanism needed — same Bearer token from ADR-001

## Options Considered

| Option | Pros | Cons |
|--------|------|------|
| Optimistic update + rollback | Instant UI, good UX | Rollback complexity |
| Pessimistic (wait for API) | Simpler, always consistent | Slow on e-ink, bad UX |
| Queue-only (offline-first) | Works fully offline | Complex sync engine, out of scope |
