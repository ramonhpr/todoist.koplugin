---
id: ADR-006
title: Split tasklist.lua into focused submodules
status: PROPOSED
date: 2026-07-14
---

## Context

`ui/tasklist.lua` has grown to 1,058 lines and 26 functions across 5 distinct
concerns that are fully interleaved in a single file:

1. **Widget lifecycle** — `new`, `refresh`, `_showOrUpdate`, `_rerender`,
   `_buildTaskItem`, `_onTaskTap` (~180 lines)
2. **Sort helpers** — `cmp_datetime`, `sort_date`, `sort_priority`,
   `_sort_project`, `_sortTasks` (~80 lines)
3. **Filter helper** — `is_null`, `_filterTasks` (~60 lines)
4. **Today/overdue rendering** — `_fetchAndRender`, `_render`, `_renderError`
   (~260 lines)
5. **Inbox/Upcoming rendering** — `_fetchAndRenderView`, `_renderView`,
   `_renderViewError`, `_buildUpcomingQuery`, `format_date_header` (~260 lines)
6. **Task write actions** — `_completeTask`, `_showRescheduleMenu`,
   `_rescheduleTask`, `_removeFromViewTasks`, `_restoreToViewTasks` (~200 lines)

At this size the file is hard to onboard into, difficult to navigate without
editor tooling, and impossible to unit-test individual concerns (e.g. sort
logic) without pulling in the full widget lifecycle. Adding the planned
grouping-modes view (SPEC-008) would push the file past 1,300 lines.

## Decision

Split `ui/tasklist.lua` into **6 files** — a slim coordinator plus 5 focused
submodules — all living under `ui/`:

| File | Responsibility | Approx lines |
|---|---|---|
| `ui/tasklist.lua` | Widget core: `new`, `refresh`, `_showOrUpdate`, `_rerender` | ~120 |
| `ui/task_row.lua` | `_buildTaskItem` — shared row builder used by all views | ~60 |
| `ui/sort_filter.lua` | All sort/filter logic: `is_null`, `_filterTasks`, `_sortTasks`, sort comparators | ~140 |
| `ui/render_today.lua` | Today+overdue fetch and render: `_fetchAndRender`, `_render`, `_renderError` | ~260 |
| `ui/render_views.lua` | Inbox/Upcoming fetch and render: `_fetchAndRenderView`, `_renderView`, `_renderViewError`, `_buildUpcomingQuery`, `format_date_header` | ~300 |
| `ui/actions.lua` | Write operations: `_completeTask`, `_showRescheduleMenu`, `_rescheduleTask`, `_removeFromViewTasks`, `_restoreToViewTasks` | ~200 |

### Composition pattern

Each submodule exposes a single `extend(T, constants)` function that installs
methods directly onto the shared `TaskListWidget` table. This avoids multiple
inheritance and keeps Lua's single-metatable idiom intact:

```lua
-- ui/sort_filter.lua
-- Extends TaskListWidget with sort and filter methods.
-- Called once by tasklist.lua during module load; no runtime overhead.
local M = {}
function M.extend(T, C)          -- C = shared constants table
    local function is_null(v) ... end
    function T:_filterTasks(tasks) ... end
    function T:_sortTasks(tasks) ... end
    -- sort comparators remain module-locals (not exposed on T)
end
return M
```

```lua
-- ui/tasklist.lua (coordinator)
local TaskListWidget = {}
TaskListWidget.__index = TaskListWidget

local CONSTANTS = {
    SORT_MODES   = ...,
    SORT_LABELS  = ...,
    DIR_LABELS   = ...,
    FILTER_MODES = ...,
    FILTER_LABELS= ...,
    PRIO_PREFIX  = ...,
}

-- Install submodule methods onto TaskListWidget at load time.
require("ui/sort_filter").extend(TaskListWidget, CONSTANTS)
require("ui/task_row").extend(TaskListWidget, CONSTANTS)
require("ui/render_today").extend(TaskListWidget, CONSTANTS)
require("ui/render_views").extend(TaskListWidget, CONSTANTS)
require("ui/actions").extend(TaskListWidget, CONSTANTS)

function TaskListWidget:new(opts) ... end
function TaskListWidget:refresh(explicit) ... end
function TaskListWidget:_showOrUpdate(title, items) ... end
function TaskListWidget:_rerender() ... end

return TaskListWidget
```

### Shared constants

`SORT_MODES`, `SORT_LABELS`, `DIR_LABELS`, `FILTER_MODES`, `FILTER_LABELS`, and
`PRIO_PREFIX` remain defined in `tasklist.lua` and are passed to each submodule
as the second argument of `extend`. Submodules reference them as upvalues of
the `extend` closure, so there is no global state and no circular `require`.

### File size constraint

No file in `ui/` may exceed 300 lines. This is the forcing function for the
split and acts as a guard against future re-bloat.

## Consequences

**Easier:**
- Each file has one job; onboarding a new contributor to sort/filter logic no
  longer requires reading 1,000 lines of unrelated UI code.
- Sort and filter logic (`sort_filter.lua`) can be unit-tested independently
  of the widget lifecycle using KOReader's busted test harness.
- Adding a new view (e.g. a grouping-modes view for SPEC-008) only requires a
  new `render_*.lua` file and a single `extend` call in the coordinator; no
  existing file needs to grow.
- KOReader's `require()` caches modules after first load, so the additional
  `require` calls in `tasklist.lua` incur no measurable runtime overhead after
  the first render.

**Harder / watch-outs:**
- The `extend` pattern is unconventional for KOReader plugins. Each submodule
  file must include a brief comment explaining the pattern so it is not
  mistaken for a standalone module.
- Method names across submodules must remain unique; there is no namespacing
  within `TaskListWidget`. Naming conventions (`_render*` for render modules,
  `_*Task*` for actions) mitigate collision risk.
- Debugging a stack trace now shows method calls from multiple source files.
  The coordinator file is still the single entry point, which limits confusion.
- Any future extraction of `TaskListWidget` into a reusable library would need
  to carry all 6 files. Acceptable given this is a single-plugin codebase.

## Options Considered

| Option | Pros | Cons |
|--------|------|------|
| Keep as single file | Easy to navigate with editor outline; no refactor risk | Onboarding and testing harder as file grows; SPEC-008 would push past 1,300 lines |
| One file per view (`today_widget.lua`, `inbox_widget.lua`, `upcoming_widget.lua`) | Clean separation of view rendering | Duplicates widget lifecycle and `_buildTaskItem` row-builder across files |
| Responsibility-based split into 5 submodules + coordinator (chosen) | Each file has one job; no code duplication; constants shared cleanly; sort/filter independently testable | `extend` pattern is unconventional; method names must stay globally unique within the widget table |
