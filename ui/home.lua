--[[
    Home navigation screen (SPEC-011).

    Shows three navigation options: Inbox / Today / Upcoming.
    Remains open in the UIManager stack beneath the task-list views so that
    closing a task-list view automatically returns the user here.
--]]

local InfoMessage = require("ui/widget/infomessage")
local Menu        = require("ui/widget/menu")
local NetworkMgr  = require("ui/network/manager")
local Screen      = require("device").screen
local UIManager   = require("ui/uimanager")
local _           = require("gettext")

local HomeWidget   = {}
HomeWidget.__index = HomeWidget

function HomeWidget:new(opts)
    local o = setmetatable({
        on_view     = opts.on_view,
        on_settings = opts.on_settings,
        _menu       = nil,
    }, self)
    o:_show()
    return o
end

function HomeWidget:_show()
    local items = {
        {
            text     = _("Inbox"),
            callback = function() self.on_view("inbox", nil, nil) end,
        },
        {
            text     = _("Today"),
            callback = function() self.on_view("today", nil, nil) end,
        },
        {
            text     = _("Upcoming"),
            callback = function()
                if not NetworkMgr:isConnected() then
                    UIManager:show(InfoMessage:new {
                        text    = _("An internet connection is required."),
                        timeout = 3,
                    })
                    return
                end
                self.on_view("upcoming", nil, nil)
            end,
        },
        { text = string.rep("-", 30), dim = true, callback = function() end },
        {
            text     = _("Settings"),
            callback = function() self.on_settings() end,
        },
    }

    self._menu = Menu:new {
        title         = _("KO-Tasks for Todoist"),
        item_table    = items,
        width         = Screen:getWidth(),
        height        = Screen:getHeight(),
        is_borderless = true,
        is_popout     = false,
    }
    UIManager:show(self._menu)
end

return HomeWidget

local HomeWidget   = {}
HomeWidget.__index = HomeWidget

-- Upcoming date options shown in the sub-menu (queries are URL-encoded)
local UPCOMING_OPTIONS = {
    { label = "Tomorrow",     query = "tomorrow" },
    { label = "In 2 days",   query = "in%202%20days" },
    { label = "This Weekend", query = "this%20saturday" },
    { label = "Next Week",   query = "next%20monday" },
    { label = "Next 2 weeks", query = "next%2014%20days" },
}

function HomeWidget:new(opts)
    local o = setmetatable({
        on_view     = opts.on_view,
        on_settings = opts.on_settings,
        _menu       = nil,
    }, self)
    o:_show()
    return o
end

function HomeWidget:_show()
    local items = {
        {
            text     = _("📥  Inbox"),
            callback = function()
                self.on_view("inbox", "Inbox", nil)
            end,
        },
        {
            text     = _("📅  Today"),
            callback = function()
                self.on_view("today", "Today", nil)
            end,
        },
        {
            text     = _("🗓  Upcoming…"),
            callback = function()
                self:_showUpcomingMenu()
            end,
        },
        { text = string.rep("─", 30), dim = true, callback = function() end },
        {
            text     = _("⚙  Settings"),
            callback = function()
                self.on_settings()
            end,
        },
    }

    self._menu = Menu:new {
        title         = _('KO-Tasks for Todoist'),
        item_table    = items,
        width         = Screen:getWidth(),
        height        = Screen:getHeight(),
        is_borderless = true,
        is_popout     = false,
    }
    UIManager:show(self._menu)
end

function HomeWidget:_showUpcomingMenu()
    local sub_menu
    local items = {}
    for _, opt in ipairs(UPCOMING_OPTIONS) do
        local label = opt.label
        local query = opt.query
        table.insert(items, {
            text     = label,
            callback = function()
                UIManager:close(sub_menu)
                if not NetworkMgr:isConnected() then
                    UIManager:show(InfoMessage:new {
                        text    = _("An internet connection is required for Upcoming."),
                        timeout = 3,
                    })
                    return
                end
                self.on_view("upcoming", label, query)
            end,
        })
    end
    table.insert(items, { text = string.rep("─", 30), dim = true, callback = function() end })
    table.insert(items, {
        text     = _("← Back"),
        callback = function()
            UIManager:close(sub_menu)
        end,
    })

    sub_menu = Menu:new {
        title         = _("Upcoming — choose range"),
        item_table    = items,
        width         = Screen:getWidth(),
        height        = Screen:getHeight(),
        is_borderless = true,
        is_popout     = false,
    }
    UIManager:show(sub_menu)
end

return HomeWidget
