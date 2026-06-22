--[[
    In-memory task state + disk-backed cache.

    Responsibilities:
      • Hold the current list of today's tasks (visible in the UI)
      • Track optimistic completions (pending_completions) for rollback
      • Track which tasks have already fired a notification this session
      • Persist task list to a DEDICATED cache file (todoist_cache.lua)

    The task cache is intentionally stored in a separate LuaSettings file
    from the main plugin settings (todoist.lua). This prevents cache writes
    from ever touching — or corrupting — the file that holds the API token.

    See ADR-003 (cache strategy) and ADR-004 (write operations).
--]]

local LuaSettings = require("luasettings")
local logger      = require("logger")

local TaskStore   = {}
TaskStore.__index = TaskStore

function TaskStore:new(opts)
    local o               = setmetatable({}, self)
    o.settings            = opts.settings                     -- user prefs (token, TTL, etc.) — read-only here
    o._cache              = LuaSettings:open(opts.cache_path) -- dedicated cache file
    o.tasks               = {}                                -- visible task list
    o.projects            = {}                                -- cached projects map [id] = name
    o.pending_completions = {}                                -- [task_id] = { task, orig_index }
    o.notified_tasks      = {}                                -- [task_id] = true  (session-scoped)
    o.last_sync_time      = 0
    o:_load()
    return o
end

-- ── Persistence ──────────────────────────────────────────────────────────────

-- Writes only to the dedicated cache file; never touches the main settings.
function TaskStore:_save()
    self._cache:saveSetting("tasks", self.tasks)
    self._cache:saveSetting("timestamp", self.last_sync_time)
    self._cache:flush()
end

function TaskStore:_load()
    -- _cache is already loaded by LuaSettings:open(); just read from it.
    local tasks         = self._cache:readSetting("tasks")
    self.tasks          = type(tasks) == "table" and tasks or {}
    
    local projects      = self._cache:readSetting("projects")
    self.projects       = type(projects) == "table" and projects or {}

    self.last_sync_time = tonumber(self._cache:readSetting("timestamp")) or 0
end

-- ── Task list management ──────────────────────────────────────────────────────

--- Replace the task list with a freshly fetched set.
--- Preserves notification dedup state for tasks whose due time has not changed.
--- Drops tasks that have a pending optimistic completion.
function TaskStore:setTasks(tasks)
    -- Reset notified flag for any task whose due time changed
    for _, new_task in ipairs(tasks) do
        if self.notified_tasks[new_task.id] then
            local old = self:_findById(new_task.id)
            if old then
                local old_dt = old.due and old.due.datetime
                local new_dt = new_task.due and new_task.due.datetime
                if old_dt ~= new_dt then
                    self.notified_tasks[new_task.id] = nil
                end
            end
        end
    end

    -- Exclude tasks that are optimistically completed (avoid re-insertion)
    local filtered = {}
    for _, task in ipairs(tasks) do
        if not self.pending_completions[task.id] then
            table.insert(filtered, task)
        end
    end

    self.tasks          = filtered
    self.last_sync_time = os.time()
    self:_save()
end

function TaskStore:getTasks()
    return self.tasks
end

-- ── Projects management (SPEC-005) ───────────────────────────────────────────

function TaskStore:hasProjects()
    return next(self.projects) ~= nil
end

function TaskStore:setProjects(projects_list)
    local projects_map = {}
    for _, p in ipairs(projects_list) do
        local name = p.name
        if p.is_inbox_project then
            name = "Inbox"
        end
        projects_map[p.id] = name
    end
    self._cache:saveSetting("projects", projects_map)
    self._cache:flush()
    self.projects = projects_map
end

function TaskStore:getProjectName(project_id)
    if not project_id or not self.projects then return nil end
    return self.projects[project_id]
end

-- ── Optimistic completion (SPEC-004) ─────────────────────────────────────────

--- Remove task from the visible list immediately (optimistic).
--- Stores it in pending_completions for possible rollback.
--- Returns the removed task, or nil if not found.
function TaskStore:removeTask(task_id)
    for i, task in ipairs(self.tasks) do
        if task.id == task_id then
            table.remove(self.tasks, i)
            self.pending_completions[task_id] = { task = task, orig_index = i }
            self:_save()
            return task
        end
    end
end

--- Restore a task after a failed completion (rollback).
--- Marks the task with sync_pending = true so the UI can show an indicator.
function TaskStore:restoreTask(task_id)
    local pending = self.pending_completions[task_id]
    if not pending then return end
    self.pending_completions[task_id] = nil

    -- Re-insert at original position, clamped to current list length
    local insert_at = math.min(pending.orig_index, #self.tasks + 1)
    table.insert(self.tasks, insert_at, pending.task)
    pending.task.sync_pending = true
    self:_save()
end

--- Clean up a successful completion.
function TaskStore:confirmCompletion(task_id)
    self.pending_completions[task_id] = nil
    self.notified_tasks[task_id]      = nil
end

--- Return all tasks waiting for a background close call.
function TaskStore:getPendingCompletions()
    local out = {}
    for task_id, entry in pairs(self.pending_completions) do
        table.insert(out, { task_id = task_id, task = entry.task })
    end
    return out
end

-- ── Notification dedup (SPEC-002) ────────────────────────────────────────────

function TaskStore:markNotified(task_id)
    self.notified_tasks[task_id] = true
end

function TaskStore:wasNotified(task_id)
    return self.notified_tasks[task_id] == true
end

-- ── Cache metadata ────────────────────────────────────────────────────────────

function TaskStore:getCacheAgeSeconds()
    if self.last_sync_time == 0 then return math.huge end
    return os.time() - self.last_sync_time
end

function TaskStore:isCacheValid()
    local ttl_secs = (self.settings:readSetting("cache_ttl_minutes") or 15) * 60
    return self:getCacheAgeSeconds() < ttl_secs
end

function TaskStore:clearCache()
    self.tasks               = {}
    self.projects            = {}
    self.last_sync_time      = 0
    self.pending_completions = {}
    self.notified_tasks      = {}
    self._cache:delSetting("tasks")
    self._cache:delSetting("projects")
    self._cache:delSetting("timestamp")
    self._cache:flush()
end

-- ── Private ───────────────────────────────────────────────────────────────────

function TaskStore:_findById(id)
    for _, task in ipairs(self.tasks) do
        if task.id == id then return task end
    end
end

return TaskStore
