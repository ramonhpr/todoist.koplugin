--[[
    Plugin settings screen (SPEC-003).

    Provides a Menu-based settings UI for:
      • API token entry (masked, with a live connection test)
      • Notification toggle + sub-settings (disabled when toggle is off)
      • Cache TTL and cache clear action

    Settings are persisted to LuaSettings immediately on change (no Save button).
--]]

local ConfirmBox       = require("ui/widget/confirmbox")
local InfoMessage      = require("ui/widget/infomessage")
local InputDialog      = require("ui/widget/inputdialog")
local Menu             = require("ui/widget/menu")
local Screen           = require("device").screen
local UIManager        = require("ui/uimanager")
local _                = require("gettext")

local CACHE_TTL_OPTS   = { 5, 15, 30, 60 }
local LEAD_MINS_OPTS   = { 0, 5, 10, 15, 30, 60 }
local POLL_MINS_OPTS   = { 1, 5, 10, 15, 30, 60 }
local DISP_SECS_OPTS   = { 5, 10, 15, 30, 60 }

local SettingsWidget   = {}
SettingsWidget.__index = SettingsWidget

function SettingsWidget:new(opts)
    local o = setmetatable({
        plugin             = opts.plugin,
        settings           = opts.settings,
        api                = opts.api,
        notifications      = opts.notifications,
        on_token_changed   = opts.on_token_changed,
        on_display_changed = opts.on_display_changed,
        _menu              = nil,
    }, self)
    o:_render()
    return o
end

-- ── Private: rendering ────────────────────────────────────────────────────────

function SettingsWidget:_render()
    local s            = self.settings
    local token        = s:readSetting("api_token") or ""
    local notif        = s:isTrue("notifications_enabled")
    local lead         = s:readSetting("notification_lead_minutes") or 0
    local poll         = s:readSetting("notification_poll_minutes") or 5
    local disp         = s:readSetting("notification_display_seconds") or 10
    local ttl          = s:readSetting("cache_ttl_minutes") or 15
    -- SPEC-010 Req 3: default true when key is absent
    local show_overdue = s:readSetting("show_overdue") ~= false

    -- Mask token: show only last 4 chars
    local token_disp   = token ~= "" and ("••••" .. token:sub(-4)) or _("(not set)")

    local items        = {}

    -- ── API Token ──
    local token_text   = "API Token:  " .. token_disp
    if token == "" then
        token_text = token_text .. "  ← tap to set"
    end
    table.insert(items, {
        text     = token_text,
        callback = function() self:_editToken() end,
    })

    table.insert(items, { text = string.rep("─", 30), dim = true, callback = function() end })

    -- ── Notifications toggle ──
    table.insert(items, {
        text     = "Notifications:  " .. (notif and "Enabled ✓" or "Disabled"),
        callback = function()
            s:saveSetting("notifications_enabled", not notif)
            s:flush()
            self.notifications:restart()
            self:_render()
        end,
    })

    -- ── Notification sub-settings (greyed out when disabled) ──
    table.insert(items, {
        text     = "  Notify before due:  " .. lead .. " min",
        dim      = not notif,
        callback = notif and function()
            self:_pickFrom("Notify before due (minutes)", LEAD_MINS_OPTS, lead, function(v)
                s:saveSetting("notification_lead_minutes", v)
                s:flush()
                self.notifications:restart()
                self:_render()
            end)
        end or nil,
    })
    table.insert(items, {
        text     = "  Check interval:  " .. poll .. " min",
        dim      = not notif,
        callback = notif and function()
            self:_pickFrom("Polling interval (minutes)", POLL_MINS_OPTS, poll, function(v)
                s:saveSetting("notification_poll_minutes", v)
                s:flush()
                self.notifications:restart()
                self:_render()
            end)
        end or nil,
    })
    table.insert(items, {
        text     = "  Notification display:  " .. disp .. " sec",
        dim      = not notif,
        callback = notif and function()
            self:_pickFrom("Notification display (seconds)", DISP_SECS_OPTS, disp, function(v)
                s:saveSetting("notification_display_seconds", v)
                s:flush()
                self:_render()
            end)
        end or nil,
    })

    table.insert(items, { text = string.rep("─", 30), dim = true, callback = function() end })

    -- ── Cache settings ──
    table.insert(items, {
        text     = "Cache TTL:  " .. ttl .. " min",
        callback = function()
            self:_pickFrom("Cache TTL (minutes)", CACHE_TTL_OPTS, ttl, function(v)
                s:saveSetting("cache_ttl_minutes", v)
                s:flush()
                self:_render()
            end)
        end,
    })
    table.insert(items, {
        text     = _("Clear cache"),
        callback = function()
            UIManager:show(ConfirmBox:new {
                text        = _("Clear the local task cache?"),
                ok_text     = _("Clear"),
                cancel_text = _("Cancel"),
                ok_callback = function()
                    self.plugin.task_store:clearCache()
                    UIManager:show(InfoMessage:new {
                        text    = _("Cache cleared."),
                        timeout = 2,
                    })
                end,
            })
        end,
    })

    table.insert(items, { text = string.rep("─", 30), dim = true, callback = function() end })

    -- ── Task display settings (SPEC-010) ──
    table.insert(items, {
        text     = "Show overdue tasks:  " .. (show_overdue and "Yes ✓" or "No"),
        callback = function()
            s:saveSetting("show_overdue", not show_overdue)
            s:flush()
            -- Immediately re-render the task list behind the settings screen
            if self.on_display_changed then self.on_display_changed() end
            self:_render()
        end,
    })

    table.insert(items, { text = string.rep("─", 30), dim = true, callback = function() end })

    table.insert(items, {
        text     = _("About"),
        callback = function()
            local version = self.plugin.version or "1"
            UIManager:show(InfoMessage:new {
                text    = "KO-Tasks for Todoist" ..
                    "\nVersion: " .. tostring(version) ..
                    "\n\nNot created by, affiliated with," ..
                    "\nor supported by Doist.",
                timeout = 5,
            })
        end,
    })

    local title = "Todoist Settings"
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

-- ── Private: token editor ─────────────────────────────────────────────────────

function SettingsWidget:_editToken()
    local dialog
    dialog = InputDialog:new {
        title       = _("Todoist API Token"),
        description = _("todoist.com/app/settings/integrations/developer"),
        input       = "", -- never pre-fill for security
        text_type   = "password",
        buttons     = { {
            {
                text     = _("Cancel"),
                callback = function()
                    UIManager:close(dialog)
                end,
            },
            {
                text             = _("Save & Test"),
                is_enter_default = true,
                callback         = function()
                    local new_token = dialog:getInputText()
                    if not new_token or new_token == "" then
                        UIManager:show(InfoMessage:new {
                            text    = _("Token cannot be empty."),
                            timeout = 2,
                        })
                        return
                    end
                    UIManager:close(dialog)

                    self.settings:saveSetting("api_token", new_token)
                    self.settings:flush()
                    self.on_token_changed(new_token)

                    -- Live connection test (SPEC-003 Req 3)
                    UIManager:show(InfoMessage:new {
                        text    = _("Testing connection…"),
                        timeout = 2,
                    })
                    local ok, err = self.api:testConnection()
                    if ok then
                        -- SPEC-015 Req 2: cache user_id whenever the token is (re-)saved
                        local user, _ = self.api:getCurrentUser()
                        if user and user.id then
                            self.settings:saveSetting("user_id", tostring(user.id))
                            self.settings:flush()
                        end
                        UIManager:show(InfoMessage:new {
                            text    = _("Connected to Todoist ✓"),
                            timeout = 3,
                        })
                    elseif err == "unauthorized" then
                        UIManager:show(InfoMessage:new {
                            text    = _("Invalid token — please check and re-enter."),
                            timeout = 4,
                        })
                    else
                        UIManager:show(InfoMessage:new {
                            text    = "Connection failed: " .. tostring(err),
                            timeout = 4,
                        })
                    end
                    self:_render()
                end,
            },
        } },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

-- ── Private: option picker ────────────────────────────────────────────────────

--- Show a full-screen menu for picking one value from a list.
--- Closes itself and calls on_select(value) when an item is tapped.
function SettingsWidget:_pickFrom(title, options, current, on_select)
    local picker_menu
    local items = {}
    for _, v in ipairs(options) do
        local check = (v == current) and "✓  " or "   "
        table.insert(items, {
            text     = check .. tostring(v),
            callback = function()
                UIManager:close(picker_menu)
                on_select(v)
            end,
        })
    end
    picker_menu = Menu:new {
        title         = title,
        item_table    = items,
        width         = Screen:getWidth(),
        height        = Screen:getHeight(),
        is_borderless = true,
        is_popout     = false,
    }
    UIManager:show(picker_menu)
end

return SettingsWidget
