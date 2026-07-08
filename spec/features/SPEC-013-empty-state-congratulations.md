---
id: SPEC-013
title: Empty State Congratulations Message
status: DRAFT
created: 2026-06-30
updated: 2026-06-30
gate: G1
---

## Goal

Show a personalised congratulations message when the user has no remaining tasks for today, celebrating their productivity by displaying their name and the number of tasks they completed.

## Background

SPEC-001 (Req 7) specifies a plain "No tasks due today" message for the empty state. This covers two
distinct situations that deserve different messaging:

1. **All done** — the user had tasks today and completed all of them. This is an achievement worth celebrating.
2. **Truly empty** — no tasks were ever scheduled for today.

Displaying the user's display name (retrieved from the Todoist API) and the count of tasks completed
during the current day makes the message personal and motivating, reinforcing the habit of using the
plugin on e-ink devices where sessions tend to be focused and intentional.

## Scope

### In scope
- Distinguish between "all tasks completed" and "no tasks scheduled" empty states
- Fetch and cache the user's display name from the Todoist API (`GET /user`)
- Display a congratulations message when all tasks for today have been completed
- Include the count of tasks completed today in the message
- Display a neutral "nothing scheduled" message when no tasks were ever due today

### Out of scope
- Push or system-level notifications
- Persistent completion history across days (counts reset when the plugin is reopened the next day)
- Gamification beyond the single message (streaks, badges, etc.)
- Editing or customising the congratulations message text

## Requirements

1. When the task list becomes empty **because all of today's tasks were completed** (i.e. at least one task was closed during the current plugin session or the API returns completed tasks for today), the screen must display a congratulations message in the following format:
   ```
   Enjoy your day, <display name>.
   Today you completed <N> task(s)
   ```
   where `<display name>` is the Todoist user's display name and `<N>` is the number of tasks completed today.
2. When the task list is empty **because no tasks were ever scheduled for today** (zero tasks returned by the API and no completions recorded), the screen must display the neutral message: `"No tasks due today"` (preserving SPEC-001 Req 7 behaviour).
3. The user's display name must be fetched from `GET /user` (Todoist REST API v2) and cached locally for the duration of the plugin session. If the request fails, the message must fall back to `"Enjoy your day."` (without a name) rather than showing an error.
4. The task completion count must reflect only tasks closed **within the current plugin session** (i.e. via SPEC-004 complete-task interactions). The count must not be persisted across sessions or plugin restarts.
5. Both empty-state messages must be centred on the screen and styled consistently with the existing empty-state presentation (same font size, no animations).
6. The congratulations message must be shown immediately when the last task is removed from the list (optimistic update per SPEC-004 Req 2) — no additional user action required.
7. The empty state must still include the "Refresh" action (SPEC-001 Req 6) so the user can manually sync.

## Edge Cases

- **User name contains special characters** (e.g. accented letters, CJK): render as-is; do not escape or truncate.
- **Very long display name**: truncate to 40 characters with an ellipsis to prevent layout overflow on narrow e-ink screens.
- **`GET /user` returns an empty or whitespace-only display name**: fall back to the no-name variant (`"Enjoy your day."`).
- **Task is restored after a failed completion** (SPEC-004 Req 5): decrement the in-session completion counter and return to the normal task list view; do not show the congratulations screen while tasks are still present.
- **Plugin is reopened later in the same day**: the session counter resets to 0, so the empty state shows the neutral "No tasks due today" message unless the user completes more tasks in the new session.
- **Offline when opening the plugin, then all cached tasks completed**: congratulations message is shown using the cached user name (or fallback if not yet fetched); no network call for the name is required if already cached this session.

## Open Questions

- [ ] Should the completion count include tasks that were already completed before the session started (i.e. returned by a hypothetical `GET /tasks?filter=today&completed=true` endpoint)? If so, the count may need a separate API call.
- [ ] Is the Todoist `GET /user` endpoint available in the API tier used by all users, or is it restricted to certain plans?

## Related

- Architecture Decision: `architecture/adr/ADR-001-todoist-api-auth.md`
- Architecture Decision: `architecture/adr/ADR-003-task-cache-strategy.md`
- Depends on: `SPEC-001-todays-task-list.md` (empty state surface)
- Depends on: `SPEC-004-complete-task.md` (completion count source)
- Agent Prompt: `agents/workflows/spec-to-code.md`
