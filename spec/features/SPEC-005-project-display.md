---
id: SPEC-005
title: Project Display on Task Rows
status: DONE
created: 2026-06-16
updated: 2026-06-22
gate: G1
---

## Goal

Show the project a task belongs to directly on each task row in the task list, so users can distinguish tasks across projects at a glance without opening the task detail view.

## Background

Every Todoist task carries a `project_id` field that references one of the user's projects. Projects are a first-class resource in the Todoist API v1, fetchable via `GET /projects`, which returns a paginated envelope `{results: [{id, name, color, is_inbox_project, ...}], next_cursor}`. Until now the plugin has ignored this field, leaving users with no visual indication of which project each task belongs to.

The existing cache layer in `todoist_cache.lua` already persists task data using LuaSettings. Rather than introducing a second cache file — which would complicate invalidation and increase I/O — project data should be stored as a new `projects` key within the same file, consistent with the strategy established in ADR-003.

Every Todoist account contains exactly one Inbox project identified by `is_inbox_project: true`. The API returns its `name` as an account-specific string (often a UUID-derived value), so the plugin must special-case it and always display it as `"Inbox"` to present a consistent, human-readable label.

## Scope

### In scope
- Fetching the project list from `GET /projects` (with cursor pagination) once per session
- Caching the project list under a `projects` key in the existing `todoist_cache.lua` LuaSettings file
- Resolving each task's `project_id` to a human-readable project name at render time
- Displaying the project name on each task row, formatted as `<title>  [<Project>]`
- Treating the inbox project (`is_inbox_project: true`) as the display name `"Inbox"` regardless of its API `name` value
- Truncating the combined title + project label to respect the existing 78-character row limit in `ui/tasklist.lua`

### Out of scope
- Rendering project colours (not meaningful on e-ink displays)
- Creating or editing projects
- Filtering the task list by project (covered by SPEC-008)
- Syncing project changes mid-session (projects are fetched once and cached for the session)

## Requirements

1. The plugin **MUST** call `GET /projects` (following `next_cursor` pagination until exhausted) once per session, immediately after successful authentication, as defined in ADR-001.
2. The fetched project list **MUST** be stored under the key `projects` in the same LuaSettings file used by the task cache (`todoist_cache.lua`), as a table mapping `project_id` (string) to `project_name` (string).
3. The **Inbox project** — identified by `is_inbox_project: true` in the API response — **MUST** be stored and displayed with the name `"Inbox"`, ignoring the value of its `name` field.
4. Each task row in the task list **MUST** display the resolved project name after the task title, using the format `<title>  [<Project>]` (two spaces before the opening bracket).
5. If a task's `project_id` cannot be resolved (project missing from cache), the task row **MUST** render without a project label rather than showing an error or a raw UUID.
6. The combined length of the rendered row string (including priority prefix, title, spacing, and project label) **MUST NOT** exceed 78 characters, consistent with the limit already enforced in `ui/tasklist.lua`.
7. When truncation is required to meet the 78-character limit, the **task title MUST be truncated first** (with a trailing `…`), preserving the full project label where possible; if the project label alone would exceed the limit it too **MUST** be truncated.
8. The project cache **MUST** be invalidated and re-fetched whenever the task cache is explicitly refreshed by the user.
9. The plugin **MUST NOT** make an additional `GET /projects` request on subsequent task list renders within the same session if a valid project cache already exists in memory.
10. The project label **MUST** be visually de-emphasised relative to the task title; on devices that support font weight, it **MUST** render at a lighter weight or, where only a single weight is available, it **MUST** be enclosed in square brackets as specified in requirement 4.

## Edge Cases

- A task whose `project_id` is `null` or absent (should not occur under normal API use) must render without a project label and must not raise an error.
- Cursor pagination returning zero results on the first page (empty project list) must be handled gracefully; the cache should store an empty table and no project labels should be shown.
- A project name that is itself very long (e.g. 60+ characters) must be truncated within the label so the overall row still fits within 78 characters.
- If the `GET /projects` request fails (network error, 401, 429, etc.), the plugin must fall back to any previously cached project data; if no prior cache exists, tasks must render without project labels.
- An account's Inbox project name changing on the server has no effect — the plugin always overrides it with `"Inbox"` locally.
- Tasks in the Inbox must display `[Inbox]`, not an empty label, even though many users treat it as the "default" uncategorised bucket.

## Open Questions

<!-- leave as HTML comment if none -->

## Related

- ADR-001 — Authentication (session lifecycle, when to fetch projects)
- ADR-003 — Cache strategy (single LuaSettings file, new `projects` key)
- SPEC-001 — Task list surface (row layout, 78-char limit)
- SPEC-008 — Filter by project (future; project cache introduced here will be reused there)
