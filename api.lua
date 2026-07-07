--[[
    Todoist API v1 client.
    Handles authentication, HTTP dispatch, and basic error classification.
    All operations are synchronous (called inside NetworkMgr callbacks).
    See ADR-001 for the auth approach and ADR-004 for write-operation design.
--]]

local https     = require("ssl.https")
local ltn12     = require("ltn12")
local rapidjson = require("rapidjson")
local logger    = require("logger")

local BASE_URL  = "https://api.todoist.com/api/v1"

local Api       = {}
Api.__index     = Api

function Api:new(opts)
    return setmetatable({ token = opts.token or "" }, self)
end

function Api:setToken(token)
    self.token = token or ""
end

-- Internal HTTP dispatcher.
-- Returns (data, nil) on success or (nil, err_string) on failure.
-- err_string values: "no_token", "unauthorized", "rate_limited:<secs>",
--                    "http_error:<code>", "network_error:<msg>", "json_error"
function Api:_request(method, path, body)
    if self.token == "" then
        return nil, "no_token"
    end

    local req_body = body and rapidjson.encode(body) or nil
    local resp_chunks = {}

    local headers = {
        ["Authorization"] = "Bearer " .. self.token,
        ["Content-Type"]  = "application/json",
        ["Accept"]        = "application/json",
    }
    if req_body then
        headers["Content-Length"] = tostring(#req_body)
    end

    -- In LuaSec's table form: result==1 on success, nil on connection failure.
    -- When result==nil, `code` carries the error string instead of an HTTP status.
    local result, code, resp_headers = https.request {
        url     = BASE_URL .. path,
        method  = method,
        headers = headers,
        source  = req_body and ltn12.source.string(req_body) or nil,
        sink    = ltn12.sink.table(resp_chunks),
    }

    if result == nil then
        -- code is an error string (e.g. "connection refused")
        logger.warn("Todoist API: connection error:", code)
        return nil, "network_error:" .. tostring(code)
    end

    if code == 401 then
        return nil, "unauthorized"
    end

    if code == 429 then
        local retry_after = (resp_headers and resp_headers["retry-after"]) or "60"
        return nil, "rate_limited:" .. retry_after
    end

    if code < 200 or code > 299 then
        logger.warn("Todoist API: unexpected HTTP status", code, "for", path)
        return nil, "http_error:" .. tostring(code)
    end

    local body_str = table.concat(resp_chunks)
    -- closeTask returns 204 No Content — handle empty body gracefully
    if body_str == "" or body_str == "null" then
        return true, nil
    end

    local ok, data = pcall(rapidjson.decode, body_str)
    if not ok then
        logger.warn("Todoist API: JSON decode error:", data)
        return nil, "json_error"
    end

    return data, nil
end

-- Returns (today_tasks, overdue_tasks, nil) or (nil, nil, err_string).
-- Issues a single "today | overdue" query and splits results client-side
-- by comparing each task's due date to today's local date (SPEC-010).
function Api:getTodayAndOverdueTasks()
    local data, err = self:_request("GET", "/tasks/filter?query=today%20%7C%20overdue")
    if not data then return nil, nil, err end

    local all_tasks = (type(data) == "table" and data.results) and data.results or data
    if type(all_tasks) ~= "table" then return {}, {}, nil end

    local today_str     = os.date("%Y-%m-%d")
    local today_tasks   = {}
    local overdue_tasks = {}
    for _, task in ipairs(all_tasks) do
        local due_date  = task.due and task.due.date
        local date_part = due_date and due_date:sub(1, 10)
        -- Tasks whose due date is strictly before today belong to overdue;
        -- tasks due today or with no date belong to today.
        if date_part and date_part < today_str then
            table.insert(overdue_tasks, task)
        else
            table.insert(today_tasks, task)
        end
    end
    return today_tasks, overdue_tasks, nil
end

-- Returns (tasks_array, nil) or (nil, err_string).
-- API v1 uses a dedicated filter endpoint that returns a paginated envelope.
-- We fetch the first page (default 50 tasks) which is sufficient for a daily list.
function Api:getTodayTasks()
    local data, err = self:_request("GET", "/tasks/filter?query=today")
    if not data then return nil, err end
    -- Unwrap paginated envelope: { results = [...], next_cursor = "..." }
    if type(data) == "table" and data.results then
        return data.results, nil
    end
    -- Fallback: plain array (future-proofing)
    return data, nil
end

-- Returns (true, nil) on success or (nil, err_string) on failure.
-- Returns HTTP 204 No Content on success.
function Api:closeTask(task_id)
    return self:_request("POST", "/tasks/" .. tostring(task_id) .. "/close")
end

-- Returns (true, nil) on success or (nil, err_string) on failure.
function Api:updateTask(task_id, payload)
    return self:_request("POST", "/tasks/" .. tostring(task_id), payload)
end

-- Returns (projects_array, nil) or (nil, err_string).
-- API v1 uses a dedicated projects endpoint that returns a paginated envelope.
function Api:getProjects()
    local all_projects = {}
    local cursor = nil

    repeat
        local url = "/projects"
        if cursor and cursor ~= "" then
            url = url .. "?cursor=" .. tostring(cursor)
        end
        local data, err = self:_request("GET", url)
        if not data then return nil, err end

        if type(data) == "table" then
            local items = data.results or data.projects or data
            if type(items) == "table" then
                for _, p in ipairs(items) do
                    if type(p) == "table" and p.id then
                        table.insert(all_projects, p)
                    end
                end
            end

            cursor = data.next_cursor
            if type(cursor) ~= "string" then
                cursor = nil
            end
        else
            -- If the API doesn't return the expected format, we must abort safely
            break
        end
    until not cursor or cursor == ""

    return all_projects, nil
end

-- Quick connectivity / token sanity check.
function Api:testConnection()
    local data, err = self:getTodayTasks()
    if data then return true, nil end
    return false, err
end

return Api
