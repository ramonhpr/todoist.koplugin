--[[
    Todoist KOReader plugin — entry point.

    Registers a "Todoist" item in the KOReader Tools menu (available in both
    FileManager and Reader contexts). Initialises the API client, task store,
    and notification scheduler on load.

    Sub-modules (loaded lazily to keep startup fast):
      api.lua           — Todoist REST API v2 client
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

local Api           = require("api")
local Notifications = require("notifications")
local TaskStore     = require("taskstore")

local TodoistPlugin = WidgetContainer:extend{
    name        = "todoist",
    is_doc_only = false,
}

function TodoistPlugin:init()
    self.settings = LuaSettings:open(
        DataStorage:getSettingsDir() .. "/todoist.lua"
    )
    self.task_store = TaskStore:new{ settings = self.settings }
    self.api        = Api:new{
        token = self.settings:readSetting("api_token") or "",
    }
    self.notifications = Notifications:new{
        api        = self.api,
        task_store = self.task_store,
        settings   = self.settings,
    }

    self.ui.menu:registerToMainMenu(self)

    -- Start notification scheduler if the user has opted in
    if self.settings:isTrue("notifications_enabled") then
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
        UIManager:show(InfoMessage:new{
            text    = _("Please set your Todoist API token in Settings first."),
            timeout = 3,
        })
        self:openSettings()
        return
    end

    -- Sync the token into the API client (may have changed in Settings)
    self.api:setToken(token)

    local TaskListWidget = require("ui/tasklist")
    local widget = TaskListWidget:new{
        plugin        = self,
        task_store    = self.task_store,
        api           = self.api,
        notifications = self.notifications,
        settings      = self.settings,
        on_settings   = function() self:openSettings() end,
    }
    widget:refresh()
end

function TodoistPlugin:openSettings()
    local SettingsWidget = require("ui/settings")
    SettingsWidget:new{
        plugin           = self,
        settings         = self.settings,
        api              = self.api,
        notifications    = self.notifications,
        on_token_changed = function(token)
            self.api:setToken(token)
        end,
    }
end

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

function TodoistPlugin:onCloseWidget()
    -- Cancel all scheduled callbacks when the plugin is torn down
    self.notifications:stop()
end

return TodoistPlugin
