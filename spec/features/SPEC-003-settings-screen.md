---
id: SPEC-003
title: Plugin Settings Screen
status: DONE
created: 2026-06-16
updated: 2026-06-16
gate: G1
---

## Goal

Provide a single Settings screen where the user can configure their API token, notification preferences, and sync behaviour.

## Background

The plugin needs at minimum an API token to function. All other options (notifications, cache TTL, polling interval) should have sensible defaults so the plugin works out-of-the-box once the token is set.
Settings must survive KOReader restarts.

## Scope

### In scope
- API token entry (masked input)
- Notification toggle and related sub-settings (lead time, display timeout, polling interval)
- Cache TTL setting
- "Clear cache" action
- Settings persistence via `LuaSettings`

### Out of scope
- Multiple Todoist accounts
- Per-project or per-label filters (future SPEC)
- Import/export of settings

## Requirements

1. The Settings screen must be reachable from both the plugin's task list screen and from KOReader's plugin settings menu.
2. The API token field must mask the entered value (show `••••••••` after entry); a "Show / Hide" toggle must reveal it temporarily.
3. After saving the API token, the plugin must immediately attempt a test call (`GET /tasks/filter?query=today`) and show a success or failure message.
4. The **"Enable notifications"** toggle (SPEC-002 Req 1) must be present; sub-settings (lead time, display timeout, polling interval) must be visually disabled and non-interactive when the toggle is off.
5. Cache TTL must be configurable in minutes: options are 5, 15, 30, 60; default is 15.
6. A **"Clear cache"** button must delete the on-disk task cache and show a confirmation toast.
7. All settings must be persisted to `LuaSettings` immediately on change (no explicit "Save" button required).
8. When the Settings screen is opened with no API token configured, the token field must be focused and a helper text "Enter your Todoist API token to get started" must be visible.
9. Settings values must be validated before persisting: empty token must show an error; polling interval outside 1–60 must be clamped and a warning shown.

## Edge Cases

- User clears the API token: task list and notifications must be disabled and user prompted to re-enter the token on next open
- Test call on token save returns 401: show "Invalid token — please check and re-enter"
- Settings screen opened while a sync is in progress: allow opening, but disable the "Clear cache" button until the sync completes

## Open Questions

<!-- None — spec is APPROVED -->

## Related

- Depends on: `SPEC-001-todays-task-list.md`, `SPEC-002-due-notifications.md`
- Architecture Decision: `architecture/adr/ADR-001-todoist-api-auth.md`
