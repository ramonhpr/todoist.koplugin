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
function TaskListWidget:refresh(explicit)
    local tasks   = self.task_store:getTasks()
    local valid   = self.task_store:isCacheValid()
    local online  = NetworkMgr:isConnected()

    if valid and not online and not explicit then
        -- Fresh cache, offline — show it
        self:_render(tasks, true)
    elseif (not valid or #tasks == 0) and not online and not explicit then
        -- Stale / empty + offline — show whatever we have with a staleness warning
        self:_render(tasks, true)
    elseif valid and online and not explicit then
        -- Fresh cache + online — show immediately, refresh in background
        self:_render(tasks, false)
        self:_fetchAndRender(true, explicit)
    else
        -- Stale / empty + online or explicit refresh — block on fetch
        self:_fetchAndRender(false, explicit)
    end
end

-- ── Private: networking ───────────────────────────────────────────────────────

function TaskListWidget:_fetchAndRender(background, explicit)
    if not background then
        UIManager:show(InfoMessage:new{ text = _("Syncing tasks…"), timeout = 2 })
    end
    NetworkMgr:runWhenConnected(function()
        if explicit or not self.task_store:hasProjects() then
            local projects, err = self.api:getProjects()
            if projects then
                self.task_store:setProjects(projects)
            end
        end

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
            if task.due then
                if task.due.datetime then
                    local h, m = task.due.datetime:match("T(%d%d):(%d%d)")
                    if h then due_str = "  " .. h .. ":" .. m end
                elseif task.due.date then
                    due_str = "  " .. task.due.date
                end
            end
            local pending_mark = task.sync_pending and "  ⚠" or ""
            local title = task.content or "?"
            local project_name = self.task_store:getProjectName(task.project_id)
            local proj_label = project_name and ("  [" .. project_name .. "]") or ""
            
            -- Limit string length to 78 chars
            local max_len = 78
            local extra = prio .. due_str .. pending_mark
            
            if #extra + #title + #proj_label > max_len then
                -- Truncate title first, but leave at least 15 chars for it if possible
                local min_title_len = 15
                local avail_for_title = max_len - #extra - #proj_label
                if avail_for_title < min_title_len then
                    -- Project label is so long that title is squeezed. Truncate project label too.
                    avail_for_title = min_title_len
                    local max_proj_len = max_len - #extra - avail_for_title
                    -- "  [...]" requires at least 5 chars (spaces + brackets), so max_proj_len must be > 5
                    if max_proj_len > 5 then
                        local proj_inner_len = max_proj_len - 5 -- Subtract spaces and brackets
                        project_name = project_name:sub(1, proj_inner_len - 1) .. "…"
                        proj_label = "  [" .. project_name .. "]"
                    else
                        proj_label = ""
                        avail_for_title = max_len - #extra
                    end
                end
                
                if #title > avail_for_title then
                    title = title:sub(1, avail_for_title - 1) .. "…"
                end
            end
            
            local text = prio .. title .. proj_label .. due_str .. pending_mark

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
        callback = function() self:refresh(true) end,
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
        { text = _("↺  Retry"),    callback = function() self:refresh(true) end },
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
    if self._processing_task == task.id then return end

    local short = task.content or ""
    if #short > 52 then short = short:sub(1, 49) .. "…" end

    local items = {
        {
            text = _("Complete"),
            callback = function()
                self:_completeTask(task)
            end,
        },
        {
            text = _("Reschedule"),
            callback = function()
                self:_showRescheduleMenu(task)
            end,
        },
        {
            text = _("Cancel"),
            callback = function() end, -- Menu naturally closes on selection
        }
    }

    local action_menu = Menu:new{
        title         = short,
        item_table    = items,
        width         = Screen:getWidth(),
        height        = Screen:getHeight(),
        is_borderless = true,
        is_popout     = false,
    }
    UIManager:show(action_menu)
end

function TaskListWidget:_completeTask(task)
    if self._processing_task == task.id then return end
    self._processing_task = task.id

    -- Optimistic removal (SPEC-004 Req 2)
    self.task_store:removeTask(task.id)
    self:_render(self.task_store:getTasks(), false)

    local function finish(success, err)
        self._processing_task = nil
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
        self._processing_task = nil
    end
end

function TaskListWidget:_showRescheduleMenu(task)
    local items = {
        {
            text = _("Tomorrow"),
            callback = function() self:_rescheduleTask(task, "tomorrow", false) end,
        },
        {
            text = _("Later this week"),
            callback = function() self:_rescheduleTask(task, "in 3 days", false) end,
        },
        {
            text = _("This weekend"),
            callback = function() self:_rescheduleTask(task, "this saturday", false) end,
        },
        {
            text = _("Next week"),
            callback = function() self:_rescheduleTask(task, "next monday", false) end,
        },
    }

    if task.due and task.due.is_recurring == true then
        table.insert(items, {
            text = _("Postpone"),
            callback = function() self:_rescheduleTask(task, nil, true) end,
        })
    end

    table.insert(items, { text = string.rep("─", 30), dim = true, callback = function() end })
    table.insert(items, {
        text = _("Cancel"),
        callback = function() end,
    })

    local short = task.content or ""
    if #short > 52 then short = short:sub(1, 49) .. "…" end

    local menu = Menu:new{
        title         = "Reschedule: " .. short,
        item_table    = items,
        width         = Screen:getWidth(),
        height        = Screen:getHeight(),
        is_borderless = true,
        is_popout     = false,
    }
    UIManager:show(menu)
end

function TaskListWidget:_rescheduleTask(task, due_string, is_postpone)
    if self._processing_task == task.id then return end

    if not NetworkMgr:isConnected() then
        UIManager:show(InfoMessage:new{
            text    = _("Offline — rescheduling requires a network connection."),
            timeout = 3,
        })
        return
    end

    self._processing_task = task.id
    self.task_store:removeTask(task.id)
    self:_render(self.task_store:getTasks(), false)

    local function finish(success, err)
        self._processing_task = nil
        if success then
            self.task_store:confirmCompletion(task.id)
        else
            self.task_store:restoreTask(task.id)
            self:_render(self.task_store:getTasks(), false)
            UIManager:show(ConfirmBox:new{
                text        = 'Could not reschedule\n"' .. (task.content or "?") .. '"\n\n' .. tostring(err or ""),
                ok_text     = _("Retry"),
                cancel_text = _("Dismiss"),
                ok_callback = function()
                    self:_rescheduleTask(task, due_string, is_postpone)
                end,
            })
        end
    end

    if is_postpone then
        local ok, err = self.api:closeTask(task.id)
        finish(ok, err)
    else
        local ok, err = self.api:updateTask(task.id, { due_string = due_string })
        finish(ok, err)
    end
end

return TaskListWidget
