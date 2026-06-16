--[[
    Today's task list widget (SPEC-001, SPEC-004).

    Wraps a KOReader Menu widget and handles:
      • Online / offline / cached rendering with a sync-age banner
      • Sorting (time-specific first, then by priority)
      • Per-task complete action with optimistic UI update and rollback
      • Error state with Retry button
--]]

local ConfirmBox  = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local Menu        = require("ui/widget/menu")
local NetworkMgr  = require("ui/network/manager")
local Screen      = require("device").screen
local UIManager   = require("ui/uimanager")
local _           = require("gettext")

-- Priority prefix shown before task title
local PRIO_PREFIX = { [1] = "[!!!] ", [2] = "[!! ] ", [3] = "[ ! ] ", [4] = "" }

local TaskListWidget = {}
TaskListWidget.__index = TaskListWidget

function TaskListWidget:new(opts)
    local o = setmetatable({
        plugin        = opts.plugin,
        task_store    = opts.task_store,
        api           = opts.api,
        notifications = opts.notifications,
        settings      = opts.settings,
        on_settings   = opts.on_settings,
        _menu         = nil,
    }, self)
    return o
end

--- Decide whether to show cached data or fetch fresh, then render.
function TaskListWidget:refresh()
    local tasks   = self.task_store:getTasks()
    local valid   = self.task_store:isCacheValid()
    local online  = NetworkMgr:isConnected()

    if valid and not online then
        -- Fresh cache, offline — show it
        self:_render(tasks, true)
    elseif (not valid or #tasks == 0) and not online then
        -- Stale / empty + offline — show whatever we have with a staleness warning
        self:_render(tasks, true)
    elseif valid and online then
        -- Fresh cache + online — show immediately, refresh in background
        self:_render(tasks, false)
        self:_fetchAndRender(true)
    else
        -- Stale / empty + online — block on fetch
        self:_fetchAndRender(false)
    end
end

-- ── Private: networking ───────────────────────────────────────────────────────

function TaskListWidget:_fetchAndRender(background)
    if not background then
        UIManager:show(InfoMessage:new{ text = _("Syncing tasks…"), timeout = 2 })
    end
    NetworkMgr:runWhenConnected(function()
        local tasks, err = self.api:getTodayTasks()
        if tasks then
            self.task_store:setTasks(tasks)
            self.notifications:scheduleTaskNotifications(tasks)
            self:_render(tasks, false)
        else
            local cached = self.task_store:getTasks()
            if #cached > 0 then
                self:_render(cached, true)
                UIManager:show(InfoMessage:new{
                    text    = _("Sync failed — showing cached tasks."),
                    timeout = 3,
                })
            else
                self:_renderError(err)
            end
        end
    end)
end

-- ── Private: rendering ────────────────────────────────────────────────────────

function TaskListWidget:_render(tasks, from_cache)
    -- Sort: time-specific tasks first (ascending), then by priority descending
    local sorted = {}
    for _, t in ipairs(tasks) do table.insert(sorted, t) end
    table.sort(sorted, function(a, b)
        local adt = a.due and a.due.datetime
        local bdt = b.due and b.due.datetime
        if adt and not bdt then return true  end
        if not adt and bdt then return false end
        if adt and bdt and adt ~= bdt then return adt < bdt end
        -- Higher priority number = lower priority in Todoist (P1=4, P4=1)
        return (a.priority or 1) > (b.priority or 1)
    end)

    local items = {}

    if #sorted == 0 then
        table.insert(items, {
            text     = _("No tasks due today"),
            dim      = true,
            callback = function() end,
        })
    else
        for _, task in ipairs(sorted) do
            local prio = PRIO_PREFIX[task.priority] or ""
            local due_str = ""
            if task.due and task.due.datetime then
                local h, m = task.due.datetime:match("T(%d%d):(%d%d)")
                if h then due_str = "  " .. h .. ":" .. m end
            end
            local pending_mark = task.sync_pending and "  ⚠" or ""
            local text = prio .. (task.content or "?") .. due_str .. pending_mark
            -- Truncate long titles so they fit one line on a Kindle screen
            if #text > 78 then text = text:sub(1, 75) .. "…" end

            table.insert(items, {
                text     = text,
                callback = function()
                    self:_onTaskTap(task)
                end,
            })
        end
    end

    -- ── Footer actions ──
    table.insert(items, { text = string.rep("─", 30), dim = true, callback = function() end })
    table.insert(items, {
        text     = _("↻  Refresh"),
        callback = function() self:refresh() end,
    })
    table.insert(items, {
        text     = _("⚙  Settings"),
        callback = function() self.on_settings() end,
    })

    -- ── Title with optional cache banner ──
    local title = "Todoist — Today"
    if from_cache then
        local age_min = math.floor(self.task_store:getCacheAgeSeconds() / 60)
        local badge   = NetworkMgr:isConnected() and "" or "  ·  Offline"
        title = "Todoist  (synced " .. age_min .. "m ago" .. badge .. ")"
    end

    self:_showOrUpdate(title, items)
end

function TaskListWidget:_renderError(err)
    local msg
    if err == "unauthorized" or err == "no_token" then
        msg = _("Invalid or missing API token — open Settings.")
    elseif err and err:match("^rate_limited:") then
        local secs = err:match("rate_limited:(%d+)")
        msg = "Rate limited — retry in " .. (secs or "60") .. "s."
    elseif err then
        msg = "Error: " .. tostring(err)
    else
        msg = _("Failed to load tasks.")
    end

    local items = {
        { text = msg, dim = true, callback = function() end },
        { text = _("↺  Retry"),    callback = function() self:refresh() end },
        { text = _("⚙  Settings"), callback = function() self.on_settings() end },
    }
    self:_showOrUpdate("Todoist — Error", items)
end

--- Create the Menu on first call; use switchItemTable on subsequent calls.
function TaskListWidget:_showOrUpdate(title, items)
    if self._menu then
        self._menu:switchItemTable(title, items, 1)
    else
        self._menu = Menu:new{
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

-- ── Private: task interactions ────────────────────────────────────────────────

function TaskListWidget:_onTaskTap(task)
    -- Guard against double-tap opening two dialogs
    if self._completing == task.id then return end

    local short = task.content or ""
    if #short > 52 then short = short:sub(1, 49) .. "…" end

    UIManager:show(ConfirmBox:new{
        text        = "Complete this task?\n\n" .. short,
        ok_text     = _("Complete"),
        cancel_text = _("Cancel"),
        ok_callback = function()
            self:_completeTask(task)
        end,
    })
end

function TaskListWidget:_completeTask(task)
    if self._completing == task.id then return end
    self._completing = task.id

    -- Optimistic removal (SPEC-004 Req 2)
    self.task_store:removeTask(task.id)
    self:_render(self.task_store:getTasks(), false)

    local function finish(success, err)
        self._completing = nil
        if success then
            self.task_store:confirmCompletion(task.id)
        elseif err == "http_error:404" then
            -- Already completed in another client — not an error
            self.task_store:confirmCompletion(task.id)
        else
            -- Rollback (SPEC-004 Req 5)
            self.task_store:restoreTask(task.id)
            self:_render(self.task_store:getTasks(), false)
            UIManager:show(ConfirmBox:new{
                text        = 'Could not complete\n"' .. (task.content or "?") .. '"\n\n' .. tostring(err or ""),
                ok_text     = _("Retry"),
                cancel_text = _("Dismiss"),
                ok_callback = function()
                    self:_completeTask(task)
                end,
            })
        end
    end

    if NetworkMgr:isConnected() then
        local ok, err = self.api:closeTask(task.id)
        finish(ok, err)
    else
        -- Offline: task stays removed optimistically, queued for retry (SPEC-004 Req 9)
        UIManager:show(InfoMessage:new{
            text    = _("Offline — completion will sync when connected."),
            timeout = 3,
        })
        self._completing = nil
    end
end

return TaskListWidget
