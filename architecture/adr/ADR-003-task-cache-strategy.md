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

Persist the task list to a **dedicated** `todoist_cache.lua` file (a separate `LuaSettings`
instance from the main `todoist.lua` settings) with a **TTL of 15 minutes** (configurable).
Using a separate file is a hard requirement: `LuaSettings.flush()` rewrites the entire file
on every save, so mixing task data into the main settings file risks overwriting the API token
if two plugin instances (FileManager and Reader contexts) hold divergent in-memory copies and
flush concurrently. On plugin open:

1. If cache is fresh (age < TTL) and Wi-Fi is off → show cached data, show "offline" badge
2. If cache is fresh and Wi-Fi is on → show cached data, refresh in background
3. If cache is stale or empty → block on a live fetch before showing the list

A manual "Refresh" action is always available from the task list screen regardless of TTL.

## Consequences

- Task list works offline with potentially stale data (age shown to user)
- Reduces API calls to at most 4/hour under normal use
- Stale cache could show completed or rescheduled tasks; staleness badge makes this
  transparent to the user
- Cache corruption or deletion only affects task display, never the API token or user prefs
- Cache file contains task titles (potentially sensitive); stored under KOReader's
  existing settings directory with no additional encryption

## Options Considered

| Option | Pros | Cons |
|--------|------|------|
| Disk cache with TTL | Works offline, rate-limit friendly | Stale data risk |
| In-memory only | Always fresh when online | Broken offline, fetches on every open |
| Full offline Sync API | True offline-first | Very complex, out of scope for v1 |
