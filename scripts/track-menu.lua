-- track-menu.lua
-- Press Tab to open a track picker (audio + subtitles).
-- Stays open so you can adjust both. Close with Esc or Tab.
--
-- Keyboard: j/k or Up/Down to move, Enter to apply highlighted item
-- Mouse: hover to highlight, left-click to apply, wheel to scroll
--
-- Place in: ~/.config/mpv/scripts/track-menu.lua

local mp = require 'mp'
local assdraw = require 'mp.assdraw'

local osd = mp.create_osd_overlay("ass-events")

local dpy_w, dpy_h = 0, 0
local menu_open = false
local items = {}
local hovered = 1
local mouse = { x = 0, y = 0, hover = false }

-- layout
local FONT_SIZE   = 18
local LINE_HEIGHT = 24
local SECTION_GAP = 10
local PAD_X       = 16
local PAD_Y       = 16
local COLOR_TEXT    = "CCCCCC"
local COLOR_HOVER   = "FFFFFF"
local COLOR_ACTIVE  = "7FD98C"

local function build_items()
    items = {}
    local tracklist = mp.get_property_native("track-list")

    table.insert(items, { header = "audio" })
    for _, t in ipairs(tracklist) do
        if t.type == "audio" then
            local label = "  " .. t.id
            if t.lang then label = label .. "  [" .. t.lang .. "]" end
            if t.title then label = label .. "  " .. t.title end
            table.insert(items, { kind = "audio", id = t.id, label = label })
        end
    end

    table.insert(items, { header = "subtitles" })
    table.insert(items, { kind = "sub", id = "no", label = "  off" })
    for _, t in ipairs(tracklist) do
        if t.type == "sub" then
            local label = "  " .. t.id
            if t.lang then label = label .. "  [" .. t.lang .. "]" end
            if t.title then label = label .. "  " .. t.title end
            table.insert(items, { kind = "sub", id = t.id, label = label })
        end
    end
end

local function is_active(item)
    if item.kind == "audio" then
        return tostring(item.id) == tostring(mp.get_property("aid"))
    elseif item.kind == "sub" then
        return tostring(item.id) == tostring(mp.get_property("sid"))
    end
    return false
end

-- selectable rows only (skips headers), in item order
local function selectable_indices()
    local idxs = {}
    for i, it in ipairs(items) do
        if it.kind then table.insert(idxs, i) end
    end
    return idxs
end

local function compute_positions()
    local ys = {}
    local y = PAD_Y
    for i, it in ipairs(items) do
        if it.header and i > 1 then
            y = y + SECTION_GAP
        end
        ys[i] = y
        y = y + LINE_HEIGHT
    end
    return ys, y
end

local function render()
    local ass = assdraw.ass_new()
    local ys, content_bottom = compute_positions()

    local box_h = (content_bottom - PAD_Y) + 24
    local box_w = 240

    -- background
    ass:new_event()
    ass:pos(0, 0)
    ass:append(string.format("{\\bord0\\shad0\\1c&H%s&\\1a&H%s&}", "000000", "50"))
    ass:draw_start()
    ass:rect_cw(PAD_X - 12, PAD_Y - 12, PAD_X - 12 + box_w, PAD_Y - 12 + box_h)
    ass:draw_stop()

    for i, it in ipairs(items) do
        local y = ys[i]
        if it.header then
            ass:new_event()
            ass:pos(PAD_X, y)
            ass:append(string.format(
                "{\\an7\\fs%d\\bord0\\shad0\\b1\\1c&H888888&}%s",
                FONT_SIZE - 2, it.header
            ))
        else
            local color = is_active(it) and COLOR_ACTIVE or COLOR_TEXT
            local pointer = (i == hovered) and "> " or "  "
            ass:new_event()
            ass:pos(PAD_X, y)
            ass:append(string.format(
                "{\\an7\\fs%d\\bord0\\shad0\\1c&H%s&}%s%s",
                FONT_SIZE, color, pointer, it.label
            ))
        end
    end

    osd.data = ass.text
    osd:update()
end

local function apply(idx)
    local it = items[idx]
    if not it or not it.kind then return end
    if it.kind == "audio" then
        mp.set_property("aid", it.id)
    else
        mp.set_property("sid", it.id)
    end
    render()
end

local function move(delta)
    local idxs = selectable_indices()
    if #idxs == 0 then return end
    local pos = 1
    for i, v in ipairs(idxs) do
        if v == hovered then pos = i break end
    end
    pos = pos + delta
    if pos < 1 then pos = #idxs end
    if pos > #idxs then pos = 1 end
    hovered = idxs[pos]
    render()
end

local function hit_test(my)
    local ys = compute_positions()
    for i, it in ipairs(items) do
        if it.kind then
            local top = ys[i]
            local bottom = top + LINE_HEIGHT
            if my >= top and my < bottom then
                return i
            end
        end
    end
    return nil
end

local function on_click()
    if not menu_open then return end
    local m = mp.get_property_native("mouse-pos")
    local i = hit_test(m.y)
    if i then
        hovered = i
        apply(i)
    end
end

local function close_menu()
    if not menu_open then return end
    menu_open = false
    osd.data = ""
    osd:update()
    mp.remove_key_binding("track-menu-down")
    mp.remove_key_binding("track-menu-down-arrow")
    mp.remove_key_binding("track-menu-up")
    mp.remove_key_binding("track-menu-up-arrow")
    mp.remove_key_binding("track-menu-enter")
    mp.remove_key_binding("track-menu-click")
    mp.remove_key_binding("track-menu-wheel-up")
    mp.remove_key_binding("track-menu-wheel-down")
    mp.remove_key_binding("track-menu-close")
    mp.remove_key_binding("track-menu-close-tab")
end

local function open_menu()
    build_items()
    local idxs = selectable_indices()
    if #idxs == 0 then
        mp.osd_message("no audio/sub tracks found", 1.5)
        return
    end
    hovered = idxs[1]
    menu_open = true
    render()

    mp.add_forced_key_binding("j", "track-menu-down", function() move(1) end, "repeatable")
    mp.add_forced_key_binding("DOWN", "track-menu-down-arrow", function() move(1) end, "repeatable")
    mp.add_forced_key_binding("k", "track-menu-up", function() move(-1) end, "repeatable")
    mp.add_forced_key_binding("UP", "track-menu-up-arrow", function() move(-1) end, "repeatable")
    mp.add_forced_key_binding("ENTER", "track-menu-enter", function() apply(hovered) end)
    mp.add_forced_key_binding("MBTN_LEFT", "track-menu-click", on_click)
    mp.add_forced_key_binding("WHEEL_UP", "track-menu-wheel-up", function() move(-1) end)
    mp.add_forced_key_binding("WHEEL_DOWN", "track-menu-wheel-down", function() move(1) end)
    mp.add_forced_key_binding("ESC", "track-menu-close", close_menu)
    mp.add_forced_key_binding("TAB", "track-menu-close-tab", close_menu)
end

mp.observe_property("osd-dimensions", "native", function(_, d)
    dpy_w, dpy_h = d.w, d.h
    osd.res_x, osd.res_y = d.w, d.h
end)

mp.add_key_binding("TAB", "toggle-track-menu", function()
    if menu_open then close_menu() else open_menu() end
end)