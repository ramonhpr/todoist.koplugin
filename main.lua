--[[
    Todoist KOReader plugin — entry point.

    KOReader's plugin manager loads this file automatically as "main" from
    inside the plugin folder (todoist.koplugin/main.lua).

    Registers a "Todoist" item in the KOReader Tools menu (available in both
    FileManager and Reader contexts). Initialises the API client, task store,
    and notification scheduler on load.

    Sub-modules (loaded lazily to keep startup fast):
      api.lua           — Todoist API v1 client
      taskstore.lua     — in-memory task state + disk cache
      notifications.lua — UIManager-based due-time scheduler
      ui/tasklist.lua   — today's task list widget
      ui/settings.lua   — settings widget
--]]

local DataStorage     = require("datastorage")
local InfoMessage     = require("ui/widget/infomessage")
local LuaSettings     = require("luasettings")
local UIManager       = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger          = require("logger")
local _               = require("gettext")

local Api             = require("api")
local Notifications   = require("notifications")
local TaskStore       = require("taskstore")

local TodoistPlugin   = WidgetContainer:extend {
    name                   = "todoist",
    is_doc_only            = false,
    -- Class-level flag (survives instance teardown, like readtimer.koplugin).
    -- onCloseWidget sets this so the next context's init() can restore the sweep.
    _restore_notifications = false,
}

function TodoistPlugin:init()
    -- Stop any callbacks from a previous instance on the same class (re-init guard).
    if self.notifications then
        self.notifications:stop()
    end

    self.settings      = LuaSettings:open(
        DataStorage:getSettingsDir() .. "/todoist.lua"
    )
    self.task_store    = TaskStore:new {
        settings   = self.settings,
        cache_path = DataStorage:getSettingsDir() .. "/todoist_cache.lua",
    }
    self.api           = Api:new {
        token = self.settings:readSetting("api_token") or "",
    }
    self.notifications = Notifications:new {
        api        = self.api,
        task_store = self.task_store,
        settings   = self.settings,
    }

    self.ui.menu:registerToMainMenu(self)

    -- Restore notifications if they were running in the previous context
    -- (class-level flag set by onCloseWidget, same pattern as readtimer.koplugin),
    -- or start fresh if the user has opted in via settings.
    if TodoistPlugin._restore_notifications
        or self.settings:isTrue("notifications_enabled") then
        TodoistPlugin._restore_notifications = false
        self.notifications:start()
    end
end

function TodoistPlugin:addToMainMenu(menu_items)
    menu_items.todoist = {
        text         = _("Todoist"),
        sorting_hint = "tools",
        callback     = function()
            self:openTaskList()
        end,
    }
end

-- ── Navigation helpers ────────────────────────────────────────────────────────

function TodoistPlugin:openTaskList()
    local token = self.settings:readSetting("api_token")
    if not token or token == "" then
        UIManager:show(InfoMessage:new {
            text    = _("Please set your Todoist API token in Settings first."),
            timeout = 3,
        })
        self:openSettings()
        return
    end

    -- Sync the token into the API client (may have changed in Settings)
    self.api:setToken(token)

    local TaskListWidget = require("ui/tasklist")
    local widget = TaskListWidget:new {
        plugin        = self,
        task_store    = self.task_store,
        api           = self.api,
        notifications = self.notifications,
        settings      = self.settings,
        on_settings   = function(on_display_changed) self:openSettings(on_display_changed) end,
    }
    widget:refresh()
end

function TodoistPlugin:openSettings(on_display_changed)
    local SettingsWidget = require("ui/settings")
    SettingsWidget:new {
        plugin             = self,
        settings           = self.settings,
        api                = self.api,
        notifications      = self.notifications,
        on_token_changed   = function(token)
            self.api:setToken(token)
        end,
        on_display_changed = on_display_changed,
    }
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

--- Save notification state to a class-level flag before teardown so the next
--- context's init() (Reader after FileManager, or vice-versa) can restore it.
--- Mirrors the pattern used by readtimer.koplugin.
function TodoistPlugin:onCloseWidget()
    TodoistPlugin._restore_notifications =
        self.notifications ~= nil and self.notifications:isEnabled()
    self.notifications:stop()
end

--- Re-arm the sweep after the device wakes from sleep.
--- UIManager's monotonic clock pauses during suspend, so any pending callback
--- may fire late or not at all. Delegates to Notifications:onResume().
function TodoistPlugin:onResume()
    if self.notifications then
        self.notifications:onResume()
    end
end

return TodoistPlugin
