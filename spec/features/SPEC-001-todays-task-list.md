---
id: SPEC-001
title: Today's Task List
status: IN PROGRESS
created: 2026-06-16
updated: 2026-06-16
gate: G1
---

## Goal

Display a scrollable list of the user's Todoist tasks due today, accessible from the KOReader menu.

## Background

Users want a quick glance at their day's tasks without leaving KOReader. The device may be a
Kindle operating in Airplane mode most of the time, so the list must be usable both online
and from a recent cache. See ADR-001 (API auth), ADR-003 (cache strategy).

## Scope

### In scope
- Fetch tasks with Todoist filter `today` via REST API v2
- Display task title, priority indicator, and due time (if time-specific)
- Show cache age and an "offline" badge when data comes from disk cache
- Manual "Refresh" button to force a live fetch
- Empty state when no tasks are due today
- Error state when fetch fails and no cache is available

### Out of scope
- Completing or editing tasks (future SPEC)
- Overdue tasks (separate filter, future SPEC)
- Sub-tasks / comments
- Projects or labels display beyond what the API returns in the task object

## Requirements

1. The plugin entry point must be reachable from KOReader's **Tools** menu under the label "Todoist".
2. On open, the plugin must display the task list within **3 seconds** when online, or immediately from cache when offline.
3. Each task row must show: **title**, **priority** (P1–P4 colour or label), and **due time** if the task has a time component.
4. Tasks must be sorted by: due time ascending (time-specific tasks first), then by Todoist priority descending.
5. When the cache is used, a banner must show "Last synced: HH:MM" and an "Offline" badge if Wi-Fi is unavailable.
6. A "Refresh" action must be available from the task list; it must attempt a live API fetch and update the list on success.
7. When no tasks are due today, the screen must show the message "No tasks due today".
8. When the fetch fails and no cache exists, the screen must show an error message with the failure reason and a "Retry" button.
9. The plugin must not crash KOReader if the API returns unexpected JSON or a non-200 status.
10. The API token must be masked in all log output.

## Edge Cases

- Wi-Fi drops mid-fetch: show cached data if available, otherwise error state
- Todoist returns 429 (rate limit): show a "Rate limited, try again in X seconds" message derived from the `Retry-After` header
- Task has a due date but no due time: show date only, sort after time-specific tasks
- Task title is very long (>80 chars): truncate with ellipsis in the list row; full title visible on row tap (future)
- Zero tasks returned (empty array, not an error): show empty state message (Requirement 7)
- Cache file is corrupt or unreadable: treat as missing cache, attempt live fetch

## Open Questions

<!-- None — spec is APPROVED -->

## Related

- Architecture Decision: `architecture/adr/ADR-001-todoist-api-auth.md`
- Architecture Decision: `architecture/adr/ADR-003-task-cache-strategy.md`
- Agent Prompt: `agents/workflows/spec-to-code.md`
