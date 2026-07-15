--[[
    task_row.lua — Single task-row builder for TaskListWidget.

    Composition pattern: M.extend(T, C) installs _buildTaskItem onto the
    shared TaskListWidget table at module-load time. See tasklist.lua.
--]]

local M = {}

function M.extend(T, C)
    --- Build a single Menu item for a task row.
    --- Shared by both the overdue section and the today section.
    --- Pass show_date=true for overdue rows so the due date is always visible.
    function T:_buildTaskItem(task, show_date)
        local prio         = C.PRIO_PREFIX[task.priority] or ""
        local pending_mark = task.sync_pending and "  ⚠" or ""
        local title        = task.content or "?"

        local max_title    = 72 - #prio - #pending_mark
        if #title > max_title then
            title = title:sub(1, max_title - 1) .. "…"
        end

        local due_str = ""
        if task.due and task.due.date then
            local h, m = task.due.date:match("T(%d%d):(%d%d)")
            if show_date then
                -- Overdue rows: always show the date; append time when present.
                local MONTHS = {
                    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
                    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
                }
                local _, mo, d = task.due.date:match("^(%d%d%d%d)-(%d%d)-(%d%d)")
                if mo then
                    local day_label = tostring(tonumber(d)) -- strip leading zero
                    due_str = (MONTHS[tonumber(mo)] or mo) .. " " .. day_label
                    if h then due_str = due_str .. " " .. h .. ":" .. m end
                end
            else
                -- Today rows: show time only (all-day tasks show nothing).
                if h then due_str = h .. ":" .. m end
            end
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

        return {
            text     = main_text,
            callback = function() self:_onTaskTap(task) end,
        }
    end
end

return M
