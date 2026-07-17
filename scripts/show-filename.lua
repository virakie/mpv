-- show-filename.lua
-- Toggle a persistent filename display on/off.
-- Place in: ~/.config/mpv/scripts/show-filename.lua
--
-- Bind a key in input.conf, e.g.:
--   f script-binding show-filename/toggle-filename

local mp = require 'mp'
local assdraw = require 'mp.assdraw'

local osd = mp.create_osd_overlay("ass-events")
local visible = false

local FONT_SIZE = 20
local PAD = 12
local COLOR = "FFFFFF"

local function render()
    local name = mp.get_property("filename", "")
    local ass = assdraw.ass_new()
    ass:new_event()
    ass:pos(PAD, PAD)
    ass:append(string.format(
        "{\\an7\\fs%d\\bord1\\shad0\\1c&H%s&}%s",
        FONT_SIZE, COLOR, name
    ))
    osd.data = ass.text
    osd:update()
end

local function clear()
    osd.data = ""
    osd:update()
end

local function toggle()
    visible = not visible
    if visible then
        render()
    else
        clear()
    end
end

-- keep it current if the file changes while toggled on
mp.observe_property("filename", "string", function()
    if visible then render() end
end)

mp.add_key_binding(nil, "toggle-filename", toggle)
