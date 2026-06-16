---
id: ADR-003
title: Cache today's tasks on disk with a TTL
status: ACCEPTED
date: 2026-06-16
---

## Context

Kindle devices frequently operate in Airplane mode to preserve battery. If the plugin always
requires a live API call, it will be unusable offline. A disk cache allows the task list to
be shown even when Wi-Fi is unavailable, and reduces API calls during a session.

Todoist imposes a rate limit of 450 requests per 15-minute window. A simple per-session
in-memory store with no TTL would hammer the API on every plugin open.

## Decision

Persist the task list to a local JSON file (`todoist_cache.lua` via `LuaSettings`) with a
**TTL of 15 minutes** (configurable). On plugin open:

1. If cache is fresh (age < TTL) and Wi-Fi is off → show cached data, show "offline" badge
2. If cache is fresh and Wi-Fi is on → show cached data, refresh in background
3. If cache is stale or empty → block on a live fetch before showing the list

A manual "Refresh" action is always available from the task list screen regardless of TTL.

## Consequences

- Task list works offline with potentially stale data (age shown to user)
- Reduces API calls to at most 4/hour under normal use
- Stale cache could show completed or rescheduled tasks; partial staleness badge makes
  this transparent to the user
- Cache file contains task titles (potentially sensitive); stored under KOReader's
  existing settings directory with no additional encryption

## Options Considered

| Option | Pros | Cons |
|--------|------|------|
| Disk cache with TTL | Works offline, rate-limit friendly | Stale data risk |
| In-memory only | Always fresh when online | Broken offline, fetches on every open |
| Full offline Sync API | True offline-first | Very complex, out of scope for v1 |
