--[[
    Today's task list widget (SPEC-001, SPEC-004, SPEC-007).

    Wraps a KOReader Menu widget and handles:
      • Online / offline / cached rendering with a sync-age banner
      • Sorting: three user-selectable modes (date / priority / project) (SPEC-007)
      • Per-task complete action with optimistic UI update and rollback
      • Error state with Retry button
--]]

local ConfirmBox       = require("ui/widget/confirmbox")
local InfoMessage      = require("ui/widget/infomessage")
local Menu             = require("ui/widget/menu")
local NetworkMgr       = require("ui/network/manager")
local Screen           = require("device").screen
local UIManager        = require("ui/uimanager")
local _                = require("gettext")

-- Priority prefix shown before task title
local PRIO_PREFIX      = { [1] = "[!!!] ", [2] = "[!! ] ", [3] = "[ ! ] ", [4] = "" }

local TaskListWidget   = {}
TaskListWidget.__index = TaskListWidget

-- Valid sort modes in cycle order (SPEC-007 Req 7)
local SORT_MODES       = { "date", "priority", "project" }
local SORT_LABELS      = { date = "Date", priority = "Priority", project = "Project" }

-- Sort direction labels
local DIR_LABELS       = { asc = "↑ Asc", desc = "↓ Desc" }

function TaskListWidget:new(opts)
    -- SPEC-007 Req 1: read sort_mode; default to "date" when absent or invalid
    local raw_mode = opts.settings:readSetting("sort_mode")
    local mode = "date"
    for _, m in ipairs(SORT_MODES) do
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

    local o = setmetatable({
        plugin        = opts.plugin,
        task_store    = opts.task_store,
        api           = opts.api,
        notifications = opts.notifications,
        settings      = opts.settings,
        on_settings   = opts.on_settings,
        sort_mode     = mode,
        sort_dir      = dir,
        _menu         = nil,
    }, self)
    return o
end

--- Decide whether to show cached data or fetch fresh, then render.
function TaskListWidget:refresh(explicit)
    local tasks  = self.task_store:getTasks()
    local valid  = self.task_store:isCacheValid()
    local online = NetworkMgr:isConnected()

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
        UIManager:show(InfoMessage:new { text = _("Syncing tasks…"), timeout = 2 })
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
                UIManager:show(InfoMessage:new {
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

-- ── Private: sort helpers (SPEC-007) ─────────────────────────────────────────

--- Compare two optional datetime strings for ascending order.
--- nil (no due time) sorts after any real value.
local function cmp_datetime(adt, bdt)
    if adt and not bdt then return true end
    if not adt and bdt then return false end
    if adt and bdt and adt ~= bdt then return adt < bdt end
    return nil -- equal
end

--- SPEC-007 Req 2: Date sort — time-specific ascending, then all-day, ties by priority desc.
local function sort_date(a, b)
    local adt = a.due and a.due.date
    local bdt = b.due and b.due.date
    local r = cmp_datetime(adt, bdt)
    if r ~= nil then return r end
    return (a.priority or 1) > (b.priority or 1)
end

--- SPEC-007 Req 3: Priority sort — priority desc, ties by due time asc (no time = last).
local function sort_priority(a, b)
    local ap = a.priority or 1
    local bp = b.priority or 1
    if ap ~= bp then return ap > bp end
    local adt = a.due and a.due.date
    local bdt = b.due and b.due.date
    local r = cmp_datetime(adt, bdt)
    if r ~= nil then return r end
    return false
end

--- SPEC-007 Req 4/5: Project sort — project name asc (case-insensitive), ties by due time asc.
function TaskListWidget:_sort_project(a, b, task_store)
    local function proj_key(task)
        local name = task_store:getProjectName(task.project_id)
        return (name or ""):lower()
    end
    local ak = proj_key(a)
    local bk = proj_key(b)
    if ak ~= bk then return ak < bk end
    local adt = a.due and a.due.date
    local bdt = b.due and b.due.date
    local r = cmp_datetime(adt, bdt)
    if r ~= nil then return r end
    return false
end

function TaskListWidget:_sortTasks(tasks)
    local sorted = {}
    for _, t in ipairs(tasks) do table.insert(sorted, t) end
    local mode = self.sort_mode
    if mode == "priority" then
        table.sort(sorted, sort_priority)
    elseif mode == "project" then
        local ts = self.task_store
        table.sort(sorted, function(a, b) return self:_sort_project(a, b, ts) end)
    else
        -- "date" is the default (SPEC-007 Req 2)
        table.sort(sorted, sort_date)
    end
    -- Reverse the list for descending direction
    if self.sort_dir == "desc" then
        local n = #sorted
        for i = 1, math.floor(n / 2) do
            sorted[i], sorted[n - i + 1] = sorted[n - i + 1], sorted[i]
        end
    end
    return sorted
end

function TaskListWidget:_render(tasks, from_cache)
    local sorted = self:_sortTasks(tasks)

    local items = {}

    if #sorted == 0 then
        table.insert(items, {
            text     = _("No tasks due today"),
            dim      = true,
            callback = function() end,
        })
    else
        for _, task in ipairs(sorted) do
            local prio         = PRIO_PREFIX[task.priority] or ""
            local pending_mark = task.sync_pending and "  ⚠" or ""
            local title        = task.content or "?"

            -- Truncate title if too long (simpler now that time/project are on their own row)
            local max_title    = 72 - #prio - #pending_mark
            if #title > max_title then
                title = title:sub(1, max_title - 1) .. "…"
            end

            -- ── Build detail line: due time · project ──
            local due_str = ""
            if task.due and task.due.date then
                local h, m = task.due.date:match("T(%d%d):(%d%d)")
                if h then due_str = h .. ":" .. m end
            end
            local project_name = self.task_store:getProjectName(task.project_id)

            local detail_parts = {}
            if due_str ~= "" then
                table.insert(detail_parts, "⏱ " .. due_str)
            end
            if project_name then
                table.insert(detail_parts, "#" .. project_name)
            end

            local main_text = prio .. title .. pending_mark
            if #detail_parts > 0 then
                main_text = main_text .. "\n    " .. table.concat(detail_parts, "   ·   ")
            end

            table.insert(items, {
                text     = main_text,
                callback = function() self:_onTaskTap(task) end,
            })
        end
    end

    -- ── Footer actions ──
    table.insert(items, { text = string.rep("─", 30), dim = true, callback = function() end })
    -- SPEC-007 Req 7/8/11: sort cycle button on task list only
    table.insert(items, {
        text = _("⇋  Sort: ") .. (SORT_LABELS[self.sort_mode] or self.sort_mode),
        callback = function()
            -- Advance to the next sort mode in cycle order
            local next_mode = SORT_MODES[1]
            for i, m in ipairs(SORT_MODES) do
                if m == self.sort_mode then
                    next_mode = SORT_MODES[(i % #SORT_MODES) + 1]
                    break
                end
            end
            self.sort_mode = next_mode
            -- SPEC-007 Req 9: persist the new mode
            self.settings:saveSetting("sort_mode", next_mode)
            self.settings:flush()
            -- SPEC-007 Req 8: immediately re-render in the new order
            self:_render(self.task_store:getTasks(), from_cache)
        end,
    })
    -- Direction toggle: cycles between ascending and descending
    table.insert(items, {
        text = _("⇅  Direction: ") .. (DIR_LABELS[self.sort_dir] or self.sort_dir),
        callback = function()
            local next_dir = self.sort_dir == "asc" and "desc" or "asc"
            self.sort_dir = next_dir
            self.settings:saveSetting("sort_dir", next_dir)
            self.settings:flush()
            self:_render(self.task_store:getTasks(), from_cache)
        end,
    })
    table.insert(items, {
        text     = _("↻  Refresh"),
        callback = function() self:refresh(true) end,
    })
    table.insert(items, {
        text     = _("⚙  Settings"),
        callback = function() self.on_settings() end,
    })

    -- ── Title with optional cache banner + sort mode + direction (SPEC-007 Req 6) ──
    local sort_label = (SORT_LABELS[self.sort_mode] or self.sort_mode)
        .. " " .. (self.sort_dir == "desc" and "↓" or "↑")
    local title
    if from_cache then
        local age_min = math.floor(self.task_store:getCacheAgeSeconds() / 60)
        local badge   = NetworkMgr:isConnected() and "" or "  ·  Offline"
        title         = "Todoist  (synced " .. age_min .. "m ago" .. badge .. ")  ·  by " .. sort_label
    else
        title = "Todoist — Today  ·  by " .. sort_label
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
        { text = _("↺  Retry"), callback = function() self:refresh(true) end },
        { text = _("⚙  Settings"), callback = function() self.on_settings() end },
    }
    self:_showOrUpdate("Todoist — Error", items)
end

--- Create the Menu on first call; use switchItemTable on subsequent calls.
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

-- ── Private: task interactions ────────────────────────────────────────────────

function TaskListWidget:_onTaskTap(task)
    -- Guard against double-tap opening two dialogs
    if self._processing_task == task.id then return end

    local short = task.content or ""
    if #short > 52 then short = short:sub(1, 49) .. "…" end

    local action_menu
    local items = {
        {
            text = _("Complete"),
            callback = function()
                UIManager:close(action_menu)
                self:_completeTask(task)
            end,
        },
        {
            text = _("Reschedule"),
            callback = function()
                UIManager:close(action_menu)
                self:_showRescheduleMenu(task)
            end,
        },
        {
            text = _("Cancel"),
            callback = function()
                UIManager:close(action_menu)
            end,
        }
    }

    action_menu = Menu:new {
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
            UIManager:show(ConfirmBox:new {
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
        UIManager:show(InfoMessage:new {
            text    = _("Offline — completion will sync when connected."),
            timeout = 3,
        })
        self._processing_task = nil
    end
end

function TaskListWidget:_showRescheduleMenu(task)
    local menu
    local items = {
        {
            text = _("Tomorrow"),
            callback = function()
                UIManager:close(menu); self:_rescheduleTask(task, "tomorrow", false)
            end,
        },
        {
            text = _("Later this week"),
            callback = function()
                UIManager:close(menu); self:_rescheduleTask(task, "in 3 days", false)
            end,
        },
        {
            text = _("This weekend"),
            callback = function()
                UIManager:close(menu); self:_rescheduleTask(task, "this saturday", false)
            end,
        },
        {
            text = _("Next week"),
            callback = function()
                UIManager:close(menu); self:_rescheduleTask(task, "next monday", false)
            end,
        },
    }

    if task.due and task.due.is_recurring == true then
        table.insert(items, {
            text = _("Postpone"),
            callback = function()
                UIManager:close(menu); self:_rescheduleTask(task, nil, true)
            end,
        })
    end

    table.insert(items, { text = string.rep("─", 30), dim = true, callback = function() end })
    table.insert(items, {
        text = _("Cancel"),
        callback = function() UIManager:close(menu) end,
    })

    local short = task.content or ""
    if #short > 52 then short = short:sub(1, 49) .. "…" end

    menu = Menu:new {
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
        UIManager:show(InfoMessage:new {
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
            UIManager:show(ConfirmBox:new {
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
