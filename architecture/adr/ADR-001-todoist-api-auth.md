---
id: ADR-001
title: Use Todoist REST API v2 with Bearer token auth
status: ACCEPTED
date: 2026-06-16
---

## Context

The plugin needs to read tasks from Todoist. Todoist offers a REST API v2 and a legacy Sync API.
KOReader runs Lua 5.1 with the `socket` and `ssl` libraries available via `LuaSec`/`LuaSocket`,
so any HTTP client must be built on those primitives or use KOReader's own `http` wrapper.

OAuth2 is the recommended auth for multi-user apps but requires a redirect URI and a browser,
which is impractical on an e-ink reader with no browser. Personal API tokens are simpler and
sufficient for a single-user device plugin.

## Decision

Use the **Todoist REST API v2** (`https://api.todoist.com/rest/v2/`) authenticated with a
**personal API token** passed as `Authorization: Bearer <token>` on every request.

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
