--[[
    render_today.lua — Today + overdue fetch and render for TaskListWidget.

    Composition pattern: M.extend(T, C) installs methods onto the shared
    TaskListWidget table at module-load time. See tasklist.lua.

    Methods installed: _fetchAndRender, _render, _renderError
--]]

local InfoMessage = require("ui/widget/infomessage")
local NetworkMgr  = require("ui/network/manager")
local UIManager   = require("ui/uimanager")
local _           = require("gettext")

local M = {}

function M.extend(T, C)

    function T:_fetchAndRender(background, explicit)
        if not background then
            UIManager:show(InfoMessage:new { text = _("Syncing tasks…"), timeout = 2 })
        end
        NetworkMgr:runWhenConnected(function()
            -- SPEC-015 Req 3: lazily fetch user_id if absent (e.g. existing installs
            -- that set their token before SPEC-015 was introduced)
            if not self.settings:readSetting("user_id") then
                local user, _ = self.api:getCurrentUser()
                if user and user.id then
                    self.settings:saveSetting("user_id", tostring(user.id))
                    self.settings:flush()
                end
            end

            if explicit or not self.task_store:hasProjects() then
                local projects, _ = self.api:getProjects()
                if projects then
                    self.task_store:setProjects(projects)
                end
            end

            -- Single combined request: today + overdue in one round-trip (SPEC-010)
            local today_tasks, overdue_tasks, fetch_err = self.api:getTodayAndOverdueTasks()
            if today_tasks then
                self.task_store:setTasks(today_tasks)
                self.notifications:scheduleTaskNotifications(today_tasks)
                self.task_store:setOverdueTasks(overdue_tasks)
            end

            if today_tasks then
                self:_render(false)
            else
                local cached = self.task_store:getTasks()
                if #cached > 0 then
                    self:_render(true)
                    UIManager:show(InfoMessage:new {
                        text    = _("Sync failed — showing cached tasks."),
                        timeout = 3,
                    })
                else
                    self:_renderError(fetch_err)
                end
            end
        end)
    end

    function T:_render(from_cache)
        -- Read both task lists from store (SPEC-010); apply assignee filter (SPEC-015)
        local today_tasks   = self:_filterTasks(self.task_store:getTasks())
        local overdue_tasks = self:_filterTasks(self.task_store:getOverdueTasks())

        -- SPEC-010 Req 3: show_overdue defaults to true when the key is absent
        local show_overdue  = self.settings:readSetting("show_overdue") ~= false

        -- SPEC-010 Req 12: build overdue ID set for deduplication; sort overdue section
        local overdue_ids    = {}
        local sorted_overdue = {}
        if show_overdue and #overdue_tasks > 0 then
            sorted_overdue = self:_sortTasks(overdue_tasks)
            for _, t in ipairs(overdue_tasks) do
                overdue_ids[t.id] = true
            end
        end

        -- Sort today's tasks and filter out any IDs already shown in overdue
        local sorted_today   = self:_sortTasks(today_tasks)
        local filtered_today = {}
        for _, t in ipairs(sorted_today) do
            if not overdue_ids[t.id] then
                table.insert(filtered_today, t)
            end
        end

        local items               = {}
        local has_overdue_section = #sorted_overdue > 0

        -- ── Overdue section (SPEC-010 Req 4, 8) ──
        if has_overdue_section then
            table.insert(items, {
                text     = "⚠ Overdue",
                is_title = true,
                callback = function() end,
            })
            for _, task in ipairs(sorted_overdue) do
                table.insert(items, self:_buildTaskItem(task, true)) -- show_date=true
            end
        end

        -- ── Today section ──
        -- Add a "Today" header only when the overdue section is also visible,
        -- so the boundary between the two sections is unambiguous.
        if has_overdue_section and #filtered_today > 0 then
            table.insert(items, {
                text     = "Today",
                is_title = true,
                callback = function() end,
            })
        end
        -- Show the empty-state message only when the whole screen is blank
        -- SPEC-015 Req: distinguish filter-induced empty from genuinely empty day
        local empty_msg = (self.filter_assignee ~= "all")
            and _("No tasks match the current filter") or _("No tasks due today")
        if #filtered_today == 0 and not has_overdue_section then
            table.insert(items, {
                text     = empty_msg,
                dim      = true,
                callback = function() end,
            })
        else
            for _, task in ipairs(filtered_today) do
                table.insert(items, self:_buildTaskItem(task)) -- show_date=false (default)
            end
        end

        -- ── Footer actions ──
        table.insert(items, { text = string.rep("─", 30), dim = true, callback = function() end })
        -- SPEC-007 Req 7/8/11: sort cycle button on task list only
        table.insert(items, {
            text = _("⇋  Sort: ") .. (C.SORT_LABELS[self.sort_mode] or self.sort_mode),
            callback = function()
                local next_mode = C.SORT_MODES[1]
                for i, m in ipairs(C.SORT_MODES) do
                    if m == self.sort_mode then
                        next_mode = C.SORT_MODES[(i % #C.SORT_MODES) + 1]
                        break
                    end
                end
                self.sort_mode = next_mode
                self.settings:saveSetting("sort_mode", next_mode)
                self.settings:flush()
                self:_render(from_cache)
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
                self:_render(from_cache)
            end,
        })
        -- SPEC-015 Req 6: assignee filter cycle button
        table.insert(items, {
            text = _("👤  Assignee: ") .. (C.FILTER_LABELS[self.filter_assignee] or self.filter_assignee),
            callback = function()
                local next_f = C.FILTER_MODES[1]
                for i, f in ipairs(C.FILTER_MODES) do
                    if f == self.filter_assignee then
                        next_f = C.FILTER_MODES[(i % #C.FILTER_MODES) + 1]
                        break
                    end
                end
                self.filter_assignee = next_f
                self.settings:saveSetting("filter_assignee", next_f)
                self.settings:flush()
                self:_render(from_cache)
            end,
        })
        table.insert(items, {
            text     = _("↻  Refresh"),
            callback = function() self:refresh(true) end,
        })
        table.insert(items, {
            text     = _("⚙  Settings"),
            callback = function()
                -- Pass a re-render callback so display toggles in Settings
                -- (e.g. show_overdue) take effect immediately on the task list.
                self.on_settings(function() self:_render(false) end)
            end,
        })
        table.insert(items, {
            text     = _("← Home"),
            callback = function()
                if self._menu then UIManager:close(self._menu) end
            end,
        })

        -- ── Title bar: cache banner + overdue badge + sort label + filter badge ──
        -- SPEC-007 Req 6, SPEC-010 Req 7, SPEC-015 Req 12
        local sort_label    = (C.SORT_LABELS[self.sort_mode] or self.sort_mode)
            .. " " .. (self.sort_dir == "desc" and "↓" or "↑")
        local overdue_badge = has_overdue_section
            and ("  ·  " .. #sorted_overdue .. " overdue") or ""
        local filter_badge  = self.filter_assignee ~= "all"
            and ("  ·  " .. (C.FILTER_LABELS[self.filter_assignee] or self.filter_assignee)) or ""
        local title
        if from_cache then
            local age_min = math.floor(self.task_store:getCacheAgeSeconds() / 60)
            local badge   = NetworkMgr:isConnected() and "" or "  ·  Offline"
            title         = "Todoist  (synced " .. age_min .. "m ago" .. badge .. ")"
                .. overdue_badge .. "  ·  by " .. sort_label .. filter_badge
        else
            title = "Todoist — Today" .. overdue_badge .. "  ·  by " .. sort_label .. filter_badge
        end

        self:_showOrUpdate(title, items)
    end

    function T:_renderError(err)
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

end

return M
