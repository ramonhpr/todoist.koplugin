---
id: SPEC-015
title: Filter by Assignee
status: APPROVED
created: 2026-07-08
updated: 2026-07-08
gate: G1
---

## Goal

Allow users to narrow the task list to tasks assigned to them, tasks that are unassigned, or all tasks — so that people working in shared Todoist projects can focus on their own work without manual scanning.

## Background

Every Todoist task carries an `assignee_id` field. In personal (non-shared) projects this field is always `null`; in shared projects it holds the numeric ID of the user the task has been delegated to. Until now the plugin shows every fetched task regardless of assignment, which means users in team workspaces see their colleagues' tasks mixed in with their own.

Filtering is applied **client-side** after the standard fetch, consistent with the deduplication and overdue-split logic already in the render pipeline. No additional API calls are needed once the current user's ID is known.

The current user's ID is obtained from `GET /user`, which returns the authenticated user's profile. The ID is stable for the lifetime of an API token and therefore safe to cache under the `user_id` key in the main plugin settings file (alongside the token). It must be refreshed whenever the token changes, because a new token may belong to a different account.

The active filter mode is persisted under the key `filter_assignee` in the main settings file. Changing the filter re-renders the task list immediately without a new network request, identical to how sort mode changes work in SPEC-007.

## Scope

### In scope
- Three filter modes: `"all"` (default), `"me"`, `"unassigned"`
- Fetching and caching the current user's ID via `GET /user` in `api.lua`
- Storing `user_id` in the main plugin settings file; refreshing it when the API token changes
- Storing the active filter mode under `filter_assignee` in main settings; defaulting to `"all"` when absent or invalid
- A cycle button in the today task list footer to change the filter mode, labelled `"👤  Assignee: <mode>"`
- Applying the filter to **both** the today section and the overdue section in the today view
- Applying the same filter in the upcoming view (SPEC-011)
- Displaying the active filter mode in the task list title bar when it is not `"all"`
- A new `Api:getCurrentUser()` method in `api.lua`

### Out of scope
- Filtering by a specific named collaborator (only "me" and "unassigned" are in scope; named collaborators are a future enhancement)
- Fetching or displaying the collaborator list
- Server-side filtering via Todoist query syntax (client-side is sufficient and consistent with the existing pipeline)
- Applying the filter to notifications (SPEC-002 is unaffected)

## Requirements

1. The plugin **MUST** expose a new `Api:getCurrentUser()` method in `api.lua` that calls `GET /user` and returns `(user_object, nil)` on success or `(nil, err_string)` on failure.
2. Immediately after a successful API token save-and-test in the Settings screen, the plugin **MUST** call `Api:getCurrentUser()` and, if successful, store the returned `id` field under the key `user_id` in the main plugin settings file.
3. On plugin initialisation (`init()`), if `user_id` is absent from settings and a valid API token is present, the plugin **MUST** attempt to fetch and store the user ID before the first task list render; if the fetch fails, the plugin **MUST** proceed without a user ID and treat the filter as `"all"` until a successful fetch occurs.
4. The plugin **MUST** read `filter_assignee` from settings on task list initialisation; if the key is absent or holds an unrecognised value, the mode **MUST** default to `"all"` and the invalid value **MUST** be overwritten.
5. The three valid `filter_assignee` values and their semantics are:

   | Value | Tasks shown |
   |---|---|
   | `"all"` | All tasks regardless of `assignee_id` (current behaviour) |
   | `"me"` | Only tasks where `assignee_id` equals the cached `user_id` |
   | `"unassigned"` | Only tasks where `assignee_id` is `null` or absent |

6. The today task list footer **MUST** include a cycle button labelled `"👤  Assignee: <mode>"` (e.g. `"👤  Assignee: All"`, `"👤  Assignee: Me"`, `"👤  Assignee: Unassigned"`) that advances through the three modes in the order `"all"` → `"me"` → `"unassigned"` → `"all"`.
7. Activating the filter cycle button **MUST** immediately re-render the task list with the new filter applied, without a network request.
8. When the user changes the filter mode, the new value **MUST** be written to settings so the same mode is restored on the next plugin launch.
9. The filter **MUST** be applied to both the today section and the overdue section in the today view (SPEC-010), independently of the sort mode (SPEC-007) and group mode (SPEC-008).
10. The filter **MUST** also be applied to tasks rendered in the upcoming view (SPEC-011).
11. When `filter_assignee` is `"me"` but `user_id` is not yet cached in settings, the plugin **MUST** display all tasks (behave as `"all"`) and **MUST** show a brief notice `"User ID not yet resolved — showing all tasks"` to explain the fallback.
12. When `filter_assignee` is not `"all"`, the task list title bar **MUST** append the active filter label to the existing sort label (e.g. `"Todoist — Today  ·  by Date ↑  ·  Me"`); when `filter_assignee` is `"all"` no filter label **MUST** appear in the title bar.
13. The filter cycle button **MUST** appear only in the today task list and the upcoming view; it **MUST NOT** appear in the Settings screen.

## Edge Cases

- User has only personal (non-shared) projects: all tasks have `assignee_id == null`. With `"me"` selected the list will always be empty; with `"unassigned"` the list shows all tasks. Both are correct and expected.
- `user_id` changes (user switches to a different Todoist account by re-entering the token): the stored `user_id` **MUST** be overwritten by the new value fetched after the token change; the filter re-applies automatically on the next render.
- `filter_assignee == "me"` and the cached `user_id` does not match any task's `assignee_id` (e.g. all tasks are unassigned or assigned to colleagues): the task list renders empty, which is correct; no error is shown.
- An empty list after filtering (all tasks filtered out): the standard empty-state message **MUST** read `"No tasks match the current filter"` instead of `"No tasks due today"`, to distinguish a filter-induced empty state from a genuinely empty day.
- `GET /user` fails during token save (network error, 401, etc.): the plugin **MUST** still save the token and proceed; `user_id` is left absent; Req 11 fallback applies.
- The filter is changed while the upcoming view is open: the upcoming view **MUST** re-render immediately with the new filter applied to the already-fetched task list, without a new network request.

## Open Questions

<!-- None — all questions resolved. The footer cycle button is the sole control; no Settings screen entry is needed. -->

## Related

- SPEC-001 — Today's task list (filter applied here)
- SPEC-003 — Settings screen (token change triggers `user_id` refresh)
- SPEC-007 — Sort order (filter is orthogonal to sort; both active simultaneously)
- SPEC-008 — Task grouping (filter applied before grouping)
- SPEC-010 — Overdue tasks (filter applied to overdue section)
- SPEC-011 — Upcoming tasks (filter applied in upcoming view)
