--[[
    actions.lua — Task write operations for TaskListWidget.

    Composition pattern: M.extend(T, C) installs methods onto the shared
    TaskListWidget table at module-load time. See tasklist.lua.

    Methods installed:
      _onTaskTap, _completeTask, _showRescheduleMenu, _rescheduleTask,
      _removeFromViewTasks, _restoreToViewTasks
--]]

local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local Menu       = require("ui/widget/menu")
local NetworkMgr = require("ui/network/manager")
local Screen     = require("device").screen
local UIManager  = require("ui/uimanager")
local _          = require("gettext")

local M = {}

function M.extend(T, _C)

    function T:_removeFromViewTasks(task_id)
        if not self._view_raw_tasks then return end
        local out = {}
        for _, t in ipairs(self._view_raw_tasks) do
            if t.id ~= task_id then table.insert(out, t) end
        end
        self._view_raw_tasks = out
    end

    function T:_restoreToViewTasks(task)
        if not self._view_raw_tasks then return end
        table.insert(self._view_raw_tasks, task)
    end

    function T:_onTaskTap(task)
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

    function T:_completeTask(task)
        if self._processing_task == task.id then return end
        self._processing_task = task.id

        -- Optimistic removal
        if self.view_mode == "today" then
            self.task_store:removeTask(task.id)
        else
            self:_removeFromViewTasks(task.id)
        end
        self:_rerender()

        local function finish(success, err)
            self._processing_task = nil
            if success then
                if self.view_mode == "today" then
                    self.task_store:confirmCompletion(task.id)
                end
            elseif err == "http_error:404" then
                if self.view_mode == "today" then
                    self.task_store:confirmCompletion(task.id)
                end
            else
                -- Rollback
                if self.view_mode == "today" then
                    self.task_store:restoreTask(task.id)
                else
                    self:_restoreToViewTasks(task)
                end
                self:_rerender()
                UIManager:show(ConfirmBox:new {
                    text        = 'Could not complete\n"' .. (task.content or "?") .. '"\n\n' .. tostring(err or ""),
                    ok_text     = _("Retry"),
                    cancel_text = _("Dismiss"),
                    ok_callback = function() self:_completeTask(task) end,
                })
            end
        end

        if NetworkMgr:isConnected() then
            local ok, err = self.api:closeTask(task.id)
            finish(ok, err)
        else
            UIManager:show(InfoMessage:new {
                text    = _("Offline — completion will sync when connected."),
                timeout = 3,
            })
            self._processing_task = nil
        end
    end

    function T:_showRescheduleMenu(task)
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

    function T:_rescheduleTask(task, due_string, is_postpone)
        if self._processing_task == task.id then return end

        if not NetworkMgr:isConnected() then
            UIManager:show(InfoMessage:new {
                text    = _("Offline — rescheduling requires a network connection."),
                timeout = 3,
            })
            return
        end

        self._processing_task = task.id

        if self.view_mode == "today" then
            self.task_store:removeTask(task.id)
        else
            self:_removeFromViewTasks(task.id)
        end
        self:_rerender()

        local function finish(success, err)
            self._processing_task = nil
            if success then
                if self.view_mode == "today" then
                    self.task_store:confirmCompletion(task.id)
                end
            else
                if self.view_mode == "today" then
                    self.task_store:restoreTask(task.id)
                else
                    self:_restoreToViewTasks(task)
                end
                self:_rerender()
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
            local effective_due_string = due_string
            if task.due and task.due.is_recurring and task.due.string and task.due.string ~= "" then
                effective_due_string = task.due.string .. " starting " .. due_string
            end
            local ok, err = self.api:updateTask(task.id, { due_string = effective_due_string })
            finish(ok, err)
        end
    end

end

return M
