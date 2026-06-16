--[[
    In-memory task state + disk-backed cache.

    Responsibilities:
      • Hold the current list of today's tasks (visible in the UI)
      • Track optimistic completions (pending_completions) for rollback
      • Track which tasks have already fired a notification this session
      • Persist task list to LuaSettings with a timestamp for TTL checks

    See ADR-003 (cache strategy) and ADR-004 (write operations).
--]]

local logger = require("logger")

local TaskStore = {}
TaskStore.__index = TaskStore

function TaskStore:new(opts)
    local o = setmetatable({}, self)
    o.settings            = opts.settings
    o.tasks               = {}  -- visible task list
    o.pending_completions = {}  -- [task_id] = { task, orig_index }
    o.notified_tasks      = {}  -- [task_id] = true  (session-scoped)
    o.last_sync_time      = 0
    o:_load()
    return o
end

-- ── Persistence ──────────────────────────────────────────────────────────────

function TaskStore:_save()
    self.settings:saveSetting("task_cache", {
        tasks     = self.tasks,
        timestamp = self.last_sync_time,
    })
    self.settings:flush()
end

function TaskStore:_load()
    -- Wrap in pcall so a corrupt cache file doesn't crash startup
    local ok, cache = pcall(function()
        return self.settings:readSetting("task_cache")
    end)
    if ok and type(cache) == "table" then
        self.tasks          = type(cache.tasks) == "table" and cache.tasks or {}
        self.last_sync_time = tonumber(cache.timestamp) or 0
    end
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
    self.last_sync_time      = 0
    self.pending_completions = {}
    self.notified_tasks      = {}
    self.settings:delSetting("task_cache")
    self.settings:flush()
end

-- ── Private ───────────────────────────────────────────────────────────────────

function TaskStore:_findById(id)
    for _, task in ipairs(self.tasks) do
        if task.id == id then return task end
    end
end

return TaskStore
