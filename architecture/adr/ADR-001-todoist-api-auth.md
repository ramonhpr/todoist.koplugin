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
| Today's tasks | `GET /tasks/filter?query=today` — returns `{results: [...], next_cursor}` |
| Close a task | `POST /tasks/{id}/close` — returns HTTP 200 with null body |

The token is entered once in the plugin's settings screen and stored in KOReader's local
settings file (`LuaSettings`).

## Consequences

- Simple implementation: one HTTP GET, JSON response, no OAuth dance
- Token is stored on-device in plaintext inside KOReader's settings directory; acceptable
  for a personal device but users should be warned not to share the settings file
- If Todoist deprecates REST v2, the API module (`api.lua`) is the only file that needs updating
- Write operations (completing tasks) are possible in a future version with the same auth

## Options Considered

| Option | Pros | Cons |
|--------|------|------|
| REST API v2 + personal token | Simple, no OAuth, stable | Token stored in plaintext |
| Sync API | Full offline sync capability | Complex protocol, overkill for read-only v1 |
| OAuth2 | Standard, revocable | Requires browser/redirect; impractical on Kindle |
