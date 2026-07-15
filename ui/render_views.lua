--[[
    render_views.lua — Inbox and Upcoming fetch and render for TaskListWidget.

    Composition pattern: M.extend(T, C) installs methods onto the shared
    TaskListWidget table at module-load time. See tasklist.lua.

    Methods installed:
      _buildUpcomingQuery, _fetchAndRenderView, _renderView, _renderViewError
--]]

local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr  = require("ui/network/manager")
local UIManager   = require("ui/uimanager")
local _           = require("gettext")

-- ── Date-header helpers (module-locals) ────────────────────────────────────

local DAY_NAMES   = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
local MONTH_NAMES = { "Jan", "Feb", "Mar", "Apr", "May", "Jun",
                      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

--- Format a YYYY-MM-DD string as e.g. "Mon 14 Jul · Today"
local function format_date_header(date_str)
    local y, mo, d = date_str:match("^(%d%d%d%d)-(%d%d)-(%d%d)")
    if not y then return date_str end
    local ts  = os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d),
                          hour = 12, min = 0, sec = 0 })
    local dow = tonumber(os.date("%w", ts))   -- 0 = Sunday
    local label = DAY_NAMES[dow + 1] .. " " .. tostring(tonumber(d))
                  .. " " .. MONTH_NAMES[tonumber(mo)]
    local today    = os.date("%Y-%m-%d")
    local tomorrow = os.date("%Y-%m-%d", os.time() + 86400)
    if date_str == today    then label = label .. " · Today"
    elseif date_str == tomorrow then label = label .. " · Tomorrow" end
    return label
end

-- ───────────────────────────────────────────────────────────────────────────

local M = {}

function M.extend(T, C)

    --- Build the Todoist filter query and a human-readable range label.
    function T:_buildUpcomingQuery()
        local days  = self.upcoming_range_days or 7
        local start = self.upcoming_start_ts
        if not start then
            -- Natural-language query anchored to today
            return string.format("next%%20%d%%20days", days),
                   string.format("Next %d days", days)
        end
        -- Specific start date: use ISO range filter.
        -- Todoist "due after" is exclusive, so subtract one day from start.
        local after  = os.date("%Y-%m-%d", start - 86400)
        local before = os.date("%Y-%m-%d", start + days * 86400)
        local label  = os.date("%d %b", start) .. " – "
                       .. os.date("%d %b %Y", start + (days - 1) * 86400)
        local query  = string.format(
            "due%%20after%%3A%%20%s%%20%%26%%20due%%20before%%3A%%20%s", after, before)
        return query, label
    end

    function T:_fetchAndRenderView(explicit)
        local query, title_base
        if self.view_mode == "inbox" then
            query      = "%23Inbox"
            title_base = "Inbox"
        else
            query, title_base = self:_buildUpcomingQuery()
            title_base = "Upcoming — " .. title_base
        end

        UIManager:show(InfoMessage:new { text = _("Loading…"), timeout = 2 })
        NetworkMgr:runWhenConnected(function()
            -- Lazily fetch user_id if absent (SPEC-015)
            if not self.settings:readSetting("user_id") then
                local user, _ = self.api:getCurrentUser()
                if user and user.id then
                    self.settings:saveSetting("user_id", tostring(user.id))
                    self.settings:flush()
                end
            end

            -- Fetch projects if needed
            if explicit or not self.task_store:hasProjects() then
                local projects, _ = self.api:getProjects()
                if projects then self.task_store:setProjects(projects) end
            end

            local data, err = self.api:_request("GET", "/tasks/filter?query=" .. query)
            local tasks
            if data then
                tasks = (type(data) == "table" and data.results) and data.results
                        or (type(data) == "table" and not data.results and data)
                        or {}
            end

            if tasks then
                self:_renderView(title_base, tasks)
            else
                self:_renderViewError(title_base, err)
            end
        end)
    end

    function T:_renderView(title_base, raw_tasks)
        -- Store for re-render on sort/filter change
        self._view_raw_tasks  = raw_tasks
        self._view_title_base = title_base

        local tasks = self:_sortTasks(self:_filterTasks(raw_tasks))
        local items = {}

        if self.view_mode == "upcoming" then
            -- Tappable date-range item: opens DateTimeWidget to jump to any date
            do
                local _, rlabel = self:_buildUpcomingQuery()
                table.insert(items, {
                    text     = "[>] " .. rlabel,
                    callback = function()
                        local DateTimeWidget = require("ui/widget/datetimewidget")
                        local pre = self.upcoming_start_ts
                            and os.date("*t", self.upcoming_start_ts) or os.date("*t")
                        UIManager:show(DateTimeWidget:new {
                            title_text = _("Jump to date"),
                            ok_text    = _("View"),
                            year  = pre.year, month = pre.month, day = pre.day,
                            callback = function(t)
                                self.upcoming_start_ts = os.time({
                                    year = t.year, month = t.month, day = t.day,
                                    hour = 0, min = 0, sec = 0,
                                })
                                self:refresh(false)
                            end,
                        })
                    end,
                })
            end
            if #tasks == 0 then
                local msg = self.filter_assignee ~= "all"
                    and _("No tasks match the current filter")
                    or _("No upcoming tasks in this range")
                table.insert(items, { text = msg, dim = true, callback = function() end })
            else
                local groups, date_order = {}, {}
                for _, task in ipairs(tasks) do
                    local dk = task.due and task.due.date and task.due.date:sub(1, 10) or "no_date"
                    if not groups[dk] then groups[dk] = {}; table.insert(date_order, dk) end
                    table.insert(groups[dk], task)
                end
                for _, dk in ipairs(date_order) do
                    local hdr = dk == "no_date" and "No due date" or format_date_header(dk)
                    table.insert(items, { text = hdr, is_title = true, callback = function() end })
                    for _, task in ipairs(groups[dk]) do
                        table.insert(items, self:_buildTaskItem(task, false))
                    end
                end
            end
        else
            -- Inbox: flat list
            if #tasks == 0 then
                local msg = self.filter_assignee ~= "all"
                    and _("No tasks match the current filter")
                    or  _("No tasks in Inbox")
                table.insert(items, { text = msg, dim = true, callback = function() end })
            else
                for _, task in ipairs(tasks) do
                    table.insert(items, self:_buildTaskItem(task, true))
                end
            end
        end

        -- Footer
        table.insert(items, { text = string.rep("─", 30), dim = true, callback = function() end })
        -- Sort cycle
        table.insert(items, {
            text = _("⇋  Sort: ") .. (C.SORT_LABELS[self.sort_mode] or self.sort_mode),
            callback = function()
                local next_mode = C.SORT_MODES[1]
                for i, m in ipairs(C.SORT_MODES) do
                    if m == self.sort_mode then
                        next_mode = C.SORT_MODES[(i % #C.SORT_MODES) + 1]; break
                    end
                end
                self.sort_mode = next_mode
                self.settings:saveSetting("sort_mode", next_mode)
                self.settings:flush()
                self:_renderView(self._view_title_base, self._view_raw_tasks)
            end,
        })
        -- Direction toggle
        table.insert(items, {
            text = _("⇅  Direction: ") .. (C.DIR_LABELS[self.sort_dir] or self.sort_dir),
            callback = function()
                local next_dir = self.sort_dir == "asc" and "desc" or "asc"
                self.sort_dir = next_dir
                self.settings:saveSetting("sort_dir", next_dir)
                self.settings:flush()
                self:_renderView(self._view_title_base, self._view_raw_tasks)
            end,
        })
        -- Assignee filter cycle (SPEC-015)
        table.insert(items, {
            text = _("Assignee: ") .. (C.FILTER_LABELS[self.filter_assignee] or self.filter_assignee),
            callback = function()
                local next_f = C.FILTER_MODES[1]
                for i, f in ipairs(C.FILTER_MODES) do
                    if f == self.filter_assignee then
                        next_f = C.FILTER_MODES[(i % #C.FILTER_MODES) + 1]; break
                    end
                end
                self.filter_assignee = next_f
                self.settings:saveSetting("filter_assignee", next_f)
                self.settings:flush()
                self:_renderView(self._view_title_base, self._view_raw_tasks)
            end,
        })
        -- Inbox gets a Refresh button; upcoming gets range toggle + refresh
        if self.view_mode == "upcoming" then
            local ranges = { 7, 14, 30 }
            table.insert(items, {
                text = _("Range: ") .. self.upcoming_range_days .. _(" days"),
                callback = function()
                    local next_r = ranges[1]
                    for i, r in ipairs(ranges) do
                        if r == self.upcoming_range_days then
                            next_r = ranges[(i % #ranges) + 1]; break
                        end
                    end
                    self.upcoming_range_days = next_r
                    self:refresh(false)
                end,
            })
        end
        table.insert(items, {
            text     = _("Refresh"),
            callback = function() self:refresh(true) end,
        })
        -- Settings
        table.insert(items, {
            text     = _("⚙  Settings"),
            callback = function()
                self.on_settings(function()
                    if self._view_raw_tasks then
                        self:_renderView(self._view_title_base, self._view_raw_tasks)
                    end
                end)
            end,
        })
        -- Home: just close this menu; home is underneath in UIManager stack
        table.insert(items, {
            text     = _("← Home"),
            callback = function()
                if self._menu then UIManager:close(self._menu) end
            end,
        })

        -- Title bar
        local sort_label   = (C.SORT_LABELS[self.sort_mode] or self.sort_mode)
            .. " " .. (self.sort_dir == "desc" and "↓" or "↑")
        local filter_badge = self.filter_assignee ~= "all"
            and ("  ·  " .. (C.FILTER_LABELS[self.filter_assignee] or self.filter_assignee)) or ""
        local title = title_base .. "  ·  by " .. sort_label .. filter_badge

        self:_showOrUpdate(title, items)
    end

    function T:_renderViewError(title_base, err)
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
            { text = _("↺  Retry"),  callback = function() self:refresh(true) end },
            { text = _("← Home"),    callback = function()
                if self._menu then UIManager:close(self._menu) end
            end },
        }
        self:_showOrUpdate(title_base .. " — Error", items)
    end

end

return M
