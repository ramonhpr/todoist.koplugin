--[[
    tasklist.lua — TaskListWidget coordinator (SPEC-001, SPEC-004, SPEC-007, SPEC-010, SPEC-015).

    This file is the single entry point.  All rendering, sorting, filtering, and
    action logic lives in focused submodules under ui/ that are composed in via
    the extend(T, C) pattern:

      ui/sort_filter.lua  — _filterTasks, _sortTasks, sort comparators
      ui/task_row.lua     — _buildTaskItem (shared row builder)
      ui/render_today.lua — _fetchAndRender, _render, _renderError
      ui/render_views.lua — _fetchAndRenderView, _renderView, _renderViewError, _buildUpcomingQuery
      ui/actions.lua      — _onTaskTap, _completeTask, _showRescheduleMenu, _rescheduleTask,
                            _removeFromViewTasks, _restoreToViewTasks

    Each submodule receives the shared constants table (C) as its second argument
    so it can reference SORT_MODES, PRIO_PREFIX, etc. without globals or circular
    requires.
--]]

local Menu      = require("ui/widget/menu")
local Screen    = require("device").screen
local UIManager = require("ui/uimanager")
local NetworkMgr = require("ui/network/manager")
local _         = require("gettext")

-- ── Shared constants ────────────────────────────────────────────────────────

local C = {
    -- Priority prefix shown before task title
    PRIO_PREFIX   = { [1] = "[!!!] ", [2] = "[!! ] ", [3] = "[ ! ] ", [4] = "" },

    -- Valid sort modes in cycle order (SPEC-007 Req 7)
    SORT_MODES    = { "date", "priority", "project" },
    SORT_LABELS   = { date = "Date", priority = "Priority", project = "Project" },

    -- Sort direction labels
    DIR_LABELS    = { asc = "↑ Asc", desc = "↓ Desc" },

    -- Filter by assignee modes (SPEC-015)
    FILTER_MODES  = { "all", "me", "unassigned", "me_and_unassigned" },
    FILTER_LABELS = { all = "All", me = "Me", unassigned = "Unassigned",
                      me_and_unassigned = "Me & Unassigned" },
}

-- ── Widget table ────────────────────────────────────────────────────────────

local TaskListWidget   = {}
TaskListWidget.__index = TaskListWidget

-- Install submodule methods onto TaskListWidget at load time (no runtime overhead).
require("ui/sort_filter").extend(TaskListWidget, C)
require("ui/task_row").extend(TaskListWidget, C)
require("ui/render_today").extend(TaskListWidget, C)
require("ui/render_views").extend(TaskListWidget, C)
require("ui/actions").extend(TaskListWidget, C)

-- ── Constructor ─────────────────────────────────────────────────────────────

function TaskListWidget:new(opts)
    -- SPEC-007 Req 1: read sort_mode; default to "date" when absent or invalid
    local raw_mode = opts.settings:readSetting("sort_mode")
    local mode = "date"
    for _, m in ipairs(C.SORT_MODES) do
        if raw_mode == m then
            mode = m; break
        end
    end
    if raw_mode ~= nil and raw_mode ~= mode then
        -- Overwrite invalid value (SPEC-007 edge-case)
        opts.settings:saveSetting("sort_mode", mode)
        opts.settings:flush()
    end

    -- Read sort direction; default to "asc", reject any unrecognised value
    local raw_dir = opts.settings:readSetting("sort_dir")
    local dir = (raw_dir == "asc" or raw_dir == "desc") and raw_dir or "asc"
    if raw_dir ~= nil and raw_dir ~= dir then
        opts.settings:saveSetting("sort_dir", dir)
        opts.settings:flush()
    end

    -- SPEC-015 Req 4: read filter_assignee; default to "all" when absent or invalid
    local raw_filter = opts.settings:readSetting("filter_assignee")
    local fmode = "all"
    for _, f in ipairs(C.FILTER_MODES) do
        if raw_filter == f then
            fmode = f; break
        end
    end
    if raw_filter ~= nil and raw_filter ~= fmode then
        opts.settings:saveSetting("filter_assignee", fmode)
        opts.settings:flush()
    end

    local o = setmetatable({
        plugin          = opts.plugin,
        task_store      = opts.task_store,
        api             = opts.api,
        notifications   = opts.notifications,
        settings        = opts.settings,
        on_settings     = opts.on_settings,
        sort_mode       = mode,
        sort_dir        = dir,
        filter_assignee = fmode,
        _menu           = nil,
        view_mode           = opts.view_mode or "today",
        upcoming_start_ts   = nil,   -- nil = today; set by DateTimeWidget
        upcoming_range_days = 7,     -- 7 | 14 | 30
        _view_raw_tasks     = nil,
        _view_title_base    = nil,
    }, self)
    return o
end

-- ── Public: decide whether to show cached data or fetch fresh ───────────────

function TaskListWidget:refresh(explicit)
    if self.view_mode == "inbox" or self.view_mode == "upcoming" then
        self:_fetchAndRenderView(explicit)
        return
    end

    local tasks  = self.task_store:getTasks()
    local valid  = self.task_store:isCacheValid()
    local online = NetworkMgr:isConnected()

    if valid and not online and not explicit then
        -- Fresh cache, offline — show it
        self:_render(true)
    elseif (not valid or #tasks == 0) and not online and not explicit then
        -- Stale / empty + offline — show whatever we have with a staleness warning
        self:_render(true)
    elseif valid and online and not explicit then
        -- Fresh cache + online — show immediately, refresh in background
        self:_render(false)
        self:_fetchAndRender(true, explicit)
    else
        -- Stale / empty + online or explicit refresh — block on fetch
        self:_fetchAndRender(false, explicit)
    end
end

-- ── Mode-aware re-render helper ─────────────────────────────────────────────

function TaskListWidget:_rerender()
    if self.view_mode == "today" then
        self:_render(false)
    elseif self._view_raw_tasks ~= nil then
        self:_renderView(self._view_title_base, self._view_raw_tasks)
    end
end

-- ── Menu create / update ────────────────────────────────────────────────────

function TaskListWidget:_showOrUpdate(title, items)
    if self._menu then
        self._menu:switchItemTable(title, items, 1)
    else
        self._menu = Menu:new {
            title         = title,
            item_table    = items,
            width         = Screen:getWidth(),
            height        = Screen:getHeight(),
            is_borderless = true,
            is_popout     = false,
        }
        UIManager:show(self._menu)
    end
end

return TaskListWidget
