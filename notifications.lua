--[[
    Due-time notification scheduler.

    Uses UIManager:scheduleIn() to fire an InfoMessage overlay at a task's due time.
    A recurring "sweep" syncs the task list and re-arms task callbacks at configurable
    intervals. All scheduling is active only while KOReader is running.

    See ADR-002 (notification mechanism) and SPEC-002.

    Timezone note: Todoist datetimes are UTC. os.time{} treats its input as *local*
    time, so the computed epoch will be off by the device's UTC offset.
    Users can compensate via the "notify X minutes before" lead-time setting.
    A proper fix requires timegm(3) via FFI and is deferred to a future release.
--]]

local UIManager       = require("ui/uimanager")
local InfoMessage     = require("ui/widget/infomessage")
local NetworkMgr      = require("ui/network/manager")
local logger          = require("logger")

local STAGGER_SECS    = 2 -- delay between simultaneous notifications to avoid UI collision

local Notifications   = {}
Notifications.__index = Notifications

function Notifications:new(opts)
    local o      = setmetatable({}, self)
    o.api        = opts.api
    o.task_store = opts.task_store
    o.settings   = opts.settings
    o._sweep_fn  = nil -- stored for UIManager:unschedule()
    o._task_cbs  = {}  -- list of scheduled task callback refs
    return o
end

function Notifications:isEnabled()
    return self.settings:isTrue("notifications_enabled")
end

function Notifications:start()
    if not self:isEnabled() then return end
    -- Arm task callbacks immediately from the cache so we don't miss any tasks
    -- that fall within the first sweep interval (e.g. after a context switch).
    self:scheduleTaskNotifications(self.task_store:getTasks())
    self:_scheduleSweep()
end

function Notifications:stop()
    if self._sweep_fn then
        UIManager:unschedule(self._sweep_fn)
        self._sweep_fn = nil
    end
    for _, cb in ipairs(self._task_cbs) do
        UIManager:unschedule(cb)
    end
    self._task_cbs = {}
end

function Notifications:restart()
    self:stop()
    self:start()
end

--- Called by the plugin's onResume handler when the device wakes from sleep.
--- UIManager's monotonic clock pauses during sleep, so any scheduled callback
--- may be stale. Re-schedule the sweep to run shortly after wake, then re-arm
--- individual task callbacks against the current wall-clock time.
function Notifications:onResume()
    if not self:isEnabled() then return end
    -- Cancel stale sweep and task callbacks
    self:stop()
    -- Re-arm task notifications with fresh delay calculations
    self:scheduleTaskNotifications(self.task_store:getTasks())
    -- Run a sweep soon so we fetch any updates missed during sleep
    self._sweep_fn = function() self:_runSweep() end
    UIManager:scheduleIn(2, self._sweep_fn)
end

--- Schedule notification callbacks for all tasks with a due datetime.
--- Cancels any previously scheduled task callbacks first.
--- Safe to call after every sync.
function Notifications:scheduleTaskNotifications(tasks)
    for _, cb in ipairs(self._task_cbs) do
        UIManager:unschedule(cb)
    end
    self._task_cbs = {}

    if not self:isEnabled() then return end

    local lead_secs = (self.settings:readSetting("notification_lead_minutes") or 0) * 60
    local disp_secs = self.settings:readSetting("notification_display_seconds") or 10
    local now       = os.time()
    local stagger   = 0

    for _, task in ipairs(tasks) do
        if task.due and task.due.date then
            local due_ts = self:_parseIso(task.due.date)
            if due_ts then
                local notify_ts = due_ts - lead_secs
                local delay     = notify_ts - now
                if delay > 0 and not self.task_store:wasNotified(task.id) then
                    local cb = self:_makeTaskCb(task, due_ts, disp_secs)
                    UIManager:scheduleIn(delay + stagger, cb)
                    table.insert(self._task_cbs, cb)
                    stagger = stagger + STAGGER_SECS
                end
            end
        end
    end
end

-- ── Private ───────────────────────────────────────────────────────────────────

function Notifications:_scheduleSweep()
    local interval_secs = (self.settings:readSetting("notification_poll_minutes") or 5) * 60
    -- Build a new closure each time so we can reliably unschedule it by reference
    self._sweep_fn = function()
        self:_runSweep()
    end
    UIManager:scheduleIn(interval_secs, self._sweep_fn)
end

function Notifications:_runSweep()
    if not self:isEnabled() then return end

    if NetworkMgr:isConnected() then
        local tasks, err = self.api:getTodayTasks()
        if tasks then
            self.task_store:setTasks(tasks)
            self:_retryPendingCompletions()
        else
            logger.warn("Todoist: sweep sync error:", err)
        end
    end

    self:scheduleTaskNotifications(self.task_store:getTasks())
    self:_scheduleSweep() -- re-arm for the next interval
end

function Notifications:_retryPendingCompletions()
    for _, pending in ipairs(self.task_store:getPendingCompletions()) do
        local ok, err = self.api:closeTask(pending.task_id)
        if ok or err == "http_error:404" then
            -- 404 means completed elsewhere — accept as success
            self.task_store:confirmCompletion(pending.task_id)
        end
        -- On other failures: leave in queue, try next sweep.
        -- UI already shows the sync_pending indicator.
    end
end

function Notifications:_makeTaskCb(task, due_ts, disp_secs)
    return function()
        -- If the device slept through the notification by >30 min, suppress it
        if os.time() > due_ts + 30 * 60 then return end
        if self.task_store:wasNotified(task.id) then return end

        self.task_store:markNotified(task.id)
        local hhmm = os.date("%H:%M", due_ts)
        UIManager:show(InfoMessage:new {
            text    = (task.content or "?") .. " — due " .. hhmm,
            timeout = disp_secs,
        })
    end
end

--- Parse an ISO 8601 UTC datetime to a Unix timestamp.
--- NOTE: treats input as local time (see module docstring re: timezone).
function Notifications:_parseIso(dt)
    if not dt then return nil end
    local Y, M, D, h, m, s = dt:match("(%d%d%d%d)-(%d%d)-(%d%d)T(%d%d):(%d%d):(%d%d)")
    if not Y then return nil end
    return os.time {
        year  = tonumber(Y),
        month = tonumber(M),
        day   = tonumber(D),
        hour  = tonumber(h),
        min   = tonumber(m),
        sec   = tonumber(s),
    }
end

return Notifications
