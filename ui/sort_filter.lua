--[[
    sort_filter.lua — Sort and filter methods for TaskListWidget.

    Composition pattern: M.extend(T, C) installs methods directly onto the
    shared TaskListWidget table at module-load time. See tasklist.lua for the
    coordinator that calls all extend() functions.
--]]

local InfoMessage = require("ui/widget/infomessage")
local UIManager   = require("ui/uimanager")
local logger      = require("logger")
local _           = require("gettext")

local M = {}

function M.extend(T, _C)
    -- rapidjson represents JSON null as a userdata sentinel, not Lua nil.
    -- Both must be treated as "no assignee".
    local function is_null(v)
        return v == nil or type(v) == "userdata"
    end

    -- ── Filter (SPEC-015) ───────────────────────────────────────────────────

    function T:_filterTasks(tasks)
        local mode = self.filter_assignee
        if mode == "all" then return tasks end

        local user_id = self.settings:readSetting("user_id")

        -- Debug: log assignee_id values on the first call to help diagnose issues
        if not self._filter_debug_logged then
            self._filter_debug_logged = true
            logger.dbg("Todoist SPEC-015: filter mode=", mode, " user_id=", tostring(user_id))
            for _, t in ipairs(tasks) do
                logger.dbg("  task id=", t.id, " responsible_uid=", tostring(t.responsible_uid),
                    " type=", type(t.responsible_uid), " content=", (t.content or "?"):sub(1, 40))
            end
        end

        if mode == "me" then
            if not user_id then
                if not self._user_id_notice_shown then
                    self._user_id_notice_shown = true
                    UIManager:show(InfoMessage:new {
                        text    = _("User ID not yet resolved — showing all tasks"),
                        timeout = 3,
                    })
                end
                return tasks
            end
            self._user_id_notice_shown = nil
            local out = {}
            for _, t in ipairs(tasks) do
                if not is_null(t.responsible_uid)
                    and tostring(t.responsible_uid) == tostring(user_id) then
                    table.insert(out, t)
                end
            end
            return out
        elseif mode == "unassigned" then
            local out = {}
            for _, t in ipairs(tasks) do
                if is_null(t.responsible_uid) then table.insert(out, t) end
            end
            return out
        elseif mode == "me_and_unassigned" then
            local out = {}
            for _, t in ipairs(tasks) do
                if is_null(t.responsible_uid) then
                    table.insert(out, t)
                elseif user_id and not is_null(t.responsible_uid)
                    and tostring(t.responsible_uid) == tostring(user_id) then
                    table.insert(out, t)
                end
            end
            return out
        end
        return tasks
    end

    -- ── Sort comparators (module-locals, not exposed on T) ──────────────────

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
    local function sort_project(self_widget, a, b, task_store)
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

    function T:_sortTasks(tasks)
        local sorted = {}
        for _, t in ipairs(tasks) do table.insert(sorted, t) end
        local mode = self.sort_mode
        if mode == "priority" then
            table.sort(sorted, sort_priority)
        elseif mode == "project" then
            local ts = self.task_store
            table.sort(sorted, function(a, b) return sort_project(self, a, b, ts) end)
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
end

return M
