-- track-menu.lua
-- Press Tab for a track picker (audio + subtitles).
-- Stays open so you can set both. Close with Esc, Tab, or a click outside.
--
-- Keyboard: Up/Down or j/k to move, Enter to apply, wheel to scroll
-- Mouse:    hover to highlight, left-click to apply
--
-- Styled to match the subtitle adjust panel in substyle.lua: same font,
-- same sizes, same colours, laid out against a 720-tall coordinate system
-- so it looks identical whatever the window size.

local mp = require 'mp'

local osd = mp.create_osd_overlay("ass-events")

local dpy_w, dpy_h = 0, 0
local menu_open = false
local items = {}
local hovered = 1
local rows = {}              -- pixel geometry of the last render, for hit-testing
local menu_right, menu_bottom = 0, 0
local window_dragging = nil  -- borrowed while the menu is up

-- Layout, in the same units substyle.lua uses: sizes out of a 720-tall
-- screen, scaled to real pixels at render time.
local BASE_H      = 720
local FONT_SIZE   = 20
local LINE_HEIGHT = 24
local SECTION_GAP = 12
local PAD_X       = 24
local PAD_Y       = 18
local BORDER      = 1.6
local MAX_CHARS   = 52

-- ASS colours are &HBBGGRR&
local COLOR_HEAD   = "FFFFFF"   -- section headers
local COLOR_IDLE   = "A0A0A0"   -- a track you are not on
local COLOR_ACTIVE = "FFFFFF"   -- the track currently playing
local COLOR_CURSOR = "4AD2FF"   -- the row under the cursor (amber)

local function scale()
    if dpy_h and dpy_h > 0 then
        return dpy_h / BASE_H
    end
    return 1
end

local function truncate(text)
    if #text <= MAX_CHARS then return text end
    return text:sub(1, MAX_CHARS - 1) .. "..."
end

-- "3  [eng]  Signs & Songs  ass  (external)"
local function describe(t)
    local parts = { tostring(t.id) }
    parts[#parts + 1] = t.lang and ("[" .. t.lang .. "]") or "[--]"
    if t.title then parts[#parts + 1] = t.title end
    -- Codec and channel count are deliberately left out: they say nothing
    -- about which track you want. forced/external do, so they stay.
    local tail = {}
    if t.forced then tail[#tail + 1] = "forced" end
    if t.external then tail[#tail + 1] = "external" end
    if #tail > 0 then
        parts[#parts + 1] = "(" .. table.concat(tail, " ") .. ")"
    end
    return truncate(table.concat(parts, "  "))
end

local function build_items()
    items = {}
    local tracklist = mp.get_property_native("track-list") or {}

    items[#items + 1] = { header = "Audio" }
    local any_audio = false
    for _, t in ipairs(tracklist) do
        if t.type == "audio" then
            items[#items + 1] = { kind = "audio", id = t.id, label = describe(t) }
            any_audio = true
        end
    end
    if not any_audio then
        items[#items + 1] = { note = "none" }
    end

    items[#items + 1] = { header = "Subtitles" }
    items[#items + 1] = { kind = "sub", id = "no", label = "off" }
    for _, t in ipairs(tracklist) do
        if t.type == "sub" then
            items[#items + 1] = { kind = "sub", id = t.id, label = describe(t) }
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

local function selectable_indices()
    local idxs = {}
    for i, it in ipairs(items) do
        if it.kind then idxs[#idxs + 1] = i end
    end
    return idxs
end

-- Pixel y of every item, plus where the list ends.
local function layout()
    local s = scale()
    local ys = {}
    local y = PAD_Y * s
    for i, it in ipairs(items) do
        if it.header and i > 1 then
            y = y + SECTION_GAP * s
        end
        ys[i] = y
        y = y + LINE_HEIGHT * s
    end
    return ys, y
end

local function event(ass, x, y, size, color, text)
    ass[#ass + 1] = string.format(
        "{\\an7\\pos(%.1f,%.1f)\\fs%.1f\\bord%.1f\\shad0\\fn%s\\3c&H000000&\\1c&H%s&}%s",
        x, y, size, BORDER * scale(),
        mp.get_property("osd-font") or "sans-serif", color, text)
end

local function render()
    local s = scale()
    local ys, list_bottom = layout()
    local x = PAD_X * s
    local size = FONT_SIZE * s
    local ass = {}
    rows = {}

    for i, it in ipairs(items) do
        local y = ys[i]
        if it.header then
            event(ass, x, y, size, COLOR_HEAD, it.header)
        elseif it.note then
            event(ass, x, y, size, COLOR_IDLE, "\\h\\h\\h\\h" .. it.note)
        else
            local active = is_active(it)
            local color = COLOR_IDLE
            if i == hovered then
                color = COLOR_CURSOR
            elseif active then
                color = COLOR_ACTIVE
            end
            -- \h is the ASS hard space. A plain leading space gets trimmed,
            -- which would leave the id column ragged: only the rows that
            -- happen to start with > or * would line up.
            local cursor = (i == hovered) and ">" or "\\h"
            local mark   = active and "*" or "\\h"
            event(ass, x, y, size, color,
                  cursor .. "\\h" .. mark .. "\\h" .. it.label)
            rows[#rows + 1] = { index = i, top = y, bottom = y + LINE_HEIGHT * s }
        end
    end

    -- Width the menu occupies, for hit-testing and click-outside. JetBrains
    -- Mono and friends advance about 0.6 em per character.
    local widest = 0
    for _, it in ipairs(items) do
        local text = it.label or it.header or it.note or ""
        if #text > widest then widest = #text end
    end
    menu_right = x + (widest + 6) * size * 0.6
    menu_bottom = list_bottom

    osd.data = table.concat(ass, "\n")
    osd:update()
end

local function apply(idx)
    local it = items[idx]
    if not it or not it.kind then return end
    if it.kind == "audio" then
        mp.set_property("aid", tostring(it.id))
    else
        mp.set_property("sid", tostring(it.id))
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

local function row_at(mx, my)
    if mx < 0 or mx > (menu_right or 0) then return nil end
    for _, r in ipairs(rows) do
        if my >= r.top and my < r.bottom then return r.index end
    end
    return nil
end

local close_menu   -- forward, on_click can dismiss

local function on_click()
    if not menu_open then return end
    local m = mp.get_property_native("mouse-pos")
    if not m then return end
    local i = row_at(m.x, m.y)
    if i then
        hovered = i
        apply(i)
    elseif m.y > (menu_bottom or 0) or m.x > (menu_right or 0) then
        close_menu()   -- clicking away from the menu dismisses it
    end
end

local function on_mouse_move(_, m)
    if not menu_open or not m then return end
    local i = row_at(m.x, m.y)
    if i and i ~= hovered then
        hovered = i
        render()
    end
end

close_menu = function()
    if not menu_open then return end
    menu_open = false
    osd.data = ""
    osd:update()
    mp.unobserve_property(on_mouse_move)
    if window_dragging ~= nil then
        mp.set_property_bool("window-dragging", window_dragging)
        window_dragging = nil
    end
    for _, name in ipairs({
        "track-menu-down", "track-menu-down-arrow", "track-menu-up",
        "track-menu-up-arrow", "track-menu-enter", "track-menu-click",
        "track-menu-wheel-up", "track-menu-wheel-down", "track-menu-close",
        "track-menu-close-tab",
    }) do
        mp.remove_key_binding(name)
    end
end

local function open_menu()
    build_items()
    local idxs = selectable_indices()
    if #idxs == 0 then
        mp.osd_message("no audio/sub tracks found", 1.5)
        return
    end

    -- Start on the subtitle track in use, since that is usually what you
    -- opened this for; fall back to the first row.
    hovered = idxs[1]
    for _, i in ipairs(idxs) do
        if items[i].kind == "sub" and is_active(items[i]) then
            hovered = i
            break
        end
    end

    menu_open = true
    -- Same reason as the seek bar: mpv drags the window on any left press
    -- its input system does not claim, which would make picking a track
    -- shove the window across the screen.
    window_dragging = mp.get_property_bool("window-dragging")
    mp.set_property_bool("window-dragging", false)

    render()
    mp.observe_property("mouse-pos", "native", on_mouse_move)

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
    if not d then return end
    dpy_w, dpy_h = d.w, d.h
    osd.res_x, osd.res_y = d.w, d.h
    if menu_open then render() end
end)

-- A new file has different tracks; do not leave a stale list on screen.
mp.register_event("start-file", close_menu)

mp.add_key_binding("TAB", "toggle-track-menu", function()
    if menu_open then close_menu() else open_menu() end
end)
