---
id: ADR-005
title: UI navigation uses a home screen and UIManager stack
status: ACCEPTED
date: 2026-07-14
---

## Context

Prior to SPEC-011 the plugin opened the Today task list directly when the user tapped the
"Todoist" entry in KOReader's Tools menu. Adding Inbox and Upcoming views (SPEC-011) made
this untenable: the plugin now has three peer views, a settings screen, and an Upcoming
date-range sub-menu, so a navigation model was needed.

KOReader's `UIManager` is a simple widget stack: calling `UIManager:show(widget)` pushes a
widget on top; calling `UIManager:close(widget)` removes it and reveals whatever was below.
There is no built-in router or back-stack manager beyond this primitive.

The decision had to account for the following requirements:

- The user must be able to return to a "home" screen from any view without losing context.
- Upcoming requires a secondary date-range picker step before a task list is shown.
- A single "Back" action per view should be enough to navigate up one level — no multi-step
  teardown.
- The implementation should be as small as possible; the codebase targets Lua 5.1 on
  constrained hardware and code size matters.

## Decision

Use a **persistent HomeWidget + UIManager stack** model:

1. On plugin tap, `HomeWidget` is created and pushed onto the UIManager stack. It stays there
   for the duration of the session as the permanent base layer.
2. When the user picks a view, a `TaskListWidget` is created and pushed **on top** of
   HomeWidget. HomeWidget is not closed.
3. Each child view's "Back" button calls `UIManager:close(self._menu)`. Because HomeWidget
   is still on the stack underneath, KOReader reveals it automatically — no explicit
   back-callback is needed.
4. The Upcoming sub-menu (date preset picker) follows the same pattern: it is pushed on top
   of HomeWidget and closed before the TaskListWidget is shown.

All three view types — Today, Inbox, and Upcoming — share a **single `TaskListWidget` class**
parameterised by `view_mode`:

| `view_mode` | Data source | Cached? |
|---|---|---|
| `"today"` | `GET /tasks/filter?query=today%20%7C%20overdue`, split client-side | Yes (ADR-003) |
| `"inbox"` | `GET /tasks/filter?query=%23Inbox` | No (session-transient) |
| `"upcoming"` | `GET /tasks/filter?query=<built by _buildUpcomingQuery()>` | No (session-transient) |

The Upcoming view additionally carries two sub-state fields inside the widget instance:

- `upcoming_start_ts` — Unix timestamp for the range start (`nil` = today-anchored,
  natural-language query).
- `upcoming_range_days` — window length: `7`, `14`, or `30`. Toggled via an action-bar button;
  each change triggers an in-place `refresh(false)`.

## Consequences

- **Simpler child views**: Back is a single `UIManager:close` call; no parent reference or
  callback is stored.
- **Home is always reachable**: closing any child view unconditionally returns the user to
  the Home menu, regardless of how deep the navigation path was.
- **One widget class for three views**: sorting, filtering, optimistic-update, and error-
  handling logic are written once. The trade-off is that `tasklist.lua` has grown large
  (~1058 lines); see the planned ADR-006 for a proposed split.
- **No global navigation state**: each session starts fresh; there is no "restore last view"
  on plugin re-open (acceptable for a reading-device use case).
- **Upcoming sub-menu is ephemeral**: if the user opens the Upcoming sub-menu and dismisses
  it without picking a range, the UIManager stack is cleanly restored to just HomeWidget.

## Options Considered

| Option | Pros | Cons |
|--------|------|------|
| UIManager stack with persistent HomeWidget (chosen) | Simple; Back requires no callbacks; KOReader idiom | Home widget stays in memory for session lifetime |
| Separate widget class per view (Today/Inbox/Upcoming) | Maximum isolation; each file stays small | Significant code duplication (sort, filter, optimistic-update logic repeated 3×) |
| Modal overlay on top of a single persistent task list | Single widget instance; no stack management | KOReader `Menu` does not support layered overlays cleanly; would require custom widget scaffolding |
| Callback-based back navigation (old pre-SPEC-011 model) | No stack management needed | Does not scale beyond two levels; every view must accept and forward a back callback |
