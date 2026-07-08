---
id: ADR-001
title: Use Todoist API v1 with Bearer token auth
status: ACCEPTED
date: 2026-06-16
---

## Context

The plugin needs to read tasks from Todoist. Todoist originally offered REST API v2
(`/rest/v2/`) and a Sync API. The REST v2 endpoint was deprecated in 2025 in favour of
the unified **Todoist API v1** (`/api/v1/`), which merges the REST and Sync APIs and adds
cursor-based pagination to list endpoints.

KOReader runs Lua 5.1 with `ssl.https` / `ltn12` available, so HTTP requests are built
on those primitives directly.

OAuth2 is impractical on an e-ink reader (requires a browser redirect), so personal API
tokens are used instead.

## Decision

Use the **Todoist API v1** (`https://api.todoist.com/api/v1/`) authenticated with a
**personal API token** passed as `Authorization: Bearer <token>` on every request.

Key endpoints used by the plugin:

| Action | Endpoint |
|---|---|
| Today + overdue tasks | `GET /tasks/filter?query=today%20%7C%20overdue` — single request, split client-side |
| Arbitrary date filter (upcoming) | `GET /tasks/filter?query=<encoded>` |
| Projects list | `GET /projects` — cursor-paginated, cached per session |
| Close (complete) a task | `POST /tasks/{id}/close` — returns HTTP 204 No Content |
| Update a task (reschedule) | `POST /tasks/{id}` — accepts `due_string` for natural-language dates |
| Create a task | `POST /tasks` — accepts `content` and optional `due_string` |
| Current user profile | `GET /user` — used to resolve the caller's ID for assignee filtering |

The token is entered once in the plugin's settings screen and stored in KOReader's local
settings file (`LuaSettings`).

## Consequences

- Simple implementation: one HTTP GET, JSON response, no OAuth dance
- Token is stored on-device in plaintext inside KOReader's settings directory; acceptable
  for a personal device but users should be warned not to share the settings file
- If Todoist changes the API v1 base URL, `api.lua` is the only file that needs updating
- Write operations (complete, reschedule, create) use the same Bearer token with no
  additional authentication step (see ADR-004)

## Options Considered

| Option | Pros | Cons |
|--------|------|------|
| REST API v2 + personal token | Simple, no OAuth, stable | Token stored in plaintext |
| Sync API | Full offline sync capability | Complex protocol, overkill for read-only v1 |
| OAuth2 | Standard, revocable | Requires browser/redirect; impractical on Kindle |
