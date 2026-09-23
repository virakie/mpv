-- cheatsheet.lua
--
-- A port of ento/mpv-cheatsheet (https://github.com/ento/mpv-cheatsheet),
-- the "press ? for every shortcut" sheet, reworked for this config:
--
--   * The list is read from mpv's live `input-bindings`, not typed in by hand,
--     so it shows what the keys do here: your input.conf, the scripts, and
--     whatever mpv defaults are still left over. Each key appears once, with
--     whatever binding actually wins it.
--   * The description is the `# comment` at the end of the input.conf line.
--     Script keys without one fall back to the SCRIPT_KEYS table below.
--   * Keys are grouped by what they do rather than by where they are bound.
--   * Drawn in osd-theme's palette and laid out in columns, a page at a time,
--     instead of one long list you scroll.
--   * Type to filter.
--
-- Options go in script-opts/cheatsheet.conf.
--
-- Original: MIT License, Copyright (c) 2019 Marica Odagaki.

local options = require "mp.options"

local o = {
    -- Text size, out of a 720-tall screen like the other panels here.
    font_size = 16,
    -- 0 shows the video untouched behind the sheet, 1 hides it.
    backdrop_opacity = 0.82,
    -- Longer descriptions are cut short with an ellipsis.
    max_description = 46,
    -- Play/Stop/Volume keys on media keyboards and remotes.
    show_media_keys = false,
    -- Mac Cmd-key bindings, which some scripts add on every platform.
    show_meta_keys = false,
}
options.read_options(o, "cheatsheet")

-- osd-theme's palette, &HBBGGRR& order.
local LABEL = "&HFFD9CE&"
local VALUE = "&HF3AB5D&"
local DETAIL = "&HE6B9AC&"
local OUTLINE = "&H36231E&"

-- Descriptions for script keys that have no input.conf comment, keyed by
-- the "script/binding" name after script-binding.
local SCRIPT_KEYS = {
    ["webm/display-webm-encoder"] = "Clip to WebM",
    ["gifgen/set_gif_start"] = "GIF: mark the start",
    ["gifgen/set_gif_end"] = "GIF: mark the end",
    ["gifgen/make_gif"] = "GIF: make it",
    ["gifgen/make_gif_with_subtitles"] = "GIF: make it, subtitles burnt in",
    ["SmartCopyPaste/copy"] = "Copy the file path or URL",
    ["SmartCopyPaste/copy-specific"] = "Copy just the path",
    ["SmartCopyPaste/paste"] = "Paste a path or URL to play",
    ["SmartCopyPaste/paste-specific"] = "Paste into the playlist",
    ["vlcaspectratio/toggle_stretch"] = "Stretch to fill the window",
    ["cheatsheet/toggle"] = "This list",
}

-- First match wins, tested against the command in lower case. The order
-- here is the checking order; CATEGORY_ORDER is the order on screen.
local RULES = {
    { "Window & interface", { "toggle%-ui" } },
    -- mpv's F8 / F9 print the playlist and track list
    { "Menus & lists", { "show%-text" } },
    { "Menus & lists", { "uosc_menu/", "uosc/", "track_picker/", "chapters_menu/",
                         "keybind%-visualizer", "sub%-seek%-list", "cheatsheet/" } },
    { "Capture & share", { "screenshot", "clipshot/", "gifgen/", "webm/", "smartcopypaste/" } },
    { "Subtitles", { "sub" } },
    { "Seeking", { "seek", "chapter", "playlist", "frame%-", "ab%-loop" } },
    { "Audio", { "volume", "mute", "audio" } },
    { "Video", { "video", "zoom", "pan", "contrast", "brightness", "gamma", "saturation",
                 "deinterlace", "aspect", "crop", "hwdec", "reset%-all" } },
    { "Playback", { "pause", "speed", "quit", "loop" } },
    { "Window & interface", { "fullscreen", "ontop", "window", "osd", "stats", "console",
                              "restart", "presence" } },
}
local CATEGORY_ORDER = {
    "Playback", "Seeking", "Subtitles", "Audio", "Video",
    "Menus & lists", "Capture & share", "Window & interface", "Other",
}

local MEDIA_KEYS = {
    POWER = true, PLAY = true, PAUSE = true, PLAYPAUSE = true, PLAYONLY = true,
    PAUSEONLY = true, STOP = true, FORWARD = true, REWIND = true, NEXT = true,
    PREV = true, VOLUME_UP = true, VOLUME_DOWN = true, MUTE = true, ZOOMIN = true,
    ZOOMOUT = true, MBTN_BACK = true, MBTN_FORWARD = true, CHANNEL_UP = true,
    CHANNEL_DOWN = true, RECORD = true,
    -- not keys at all: the window's close button
    CLOSE_WIN = true,
}

local KEY_NAMES = {
    RIGHT = "→", LEFT = "←", UP = "↑", DOWN = "↓",
    SPACE = "Space", ENTER = "Enter", KP_ENTER = "Enter", BS = "Backspace",
    ESC = "Esc", TAB = "Tab", PGUP = "PgUp", PGDWN = "PgDn", SHARP = "#",
    HOME = "Home", END = "End", DEL = "Del", INS = "Ins", MENU = "Menu key",
    MBTN_LEFT = "Click", MBTN_LEFT_DBL = "Double-click", MBTN_RIGHT = "Right-click",
    MBTN_MID = "Middle-click", MBTN_BACK = "Mouse back", MBTN_FORWARD = "Mouse forward",
    WHEEL_UP = "Wheel ↑", WHEEL_DOWN = "Wheel ↓", WHEEL_LEFT = "Wheel ←",
    WHEEL_RIGHT = "Wheel →",
}
local MODIFIER_ORDER = { Ctrl = 1, Alt = 2, Shift = 3, Meta = 4 }

-- "Shift+Ctrl+LEFT" -> "Ctrl+Shift+←", "Q" -> "Shift+q"
local function pretty_key(key)
    local mods, rest = {}, key
    while true do
        local mod, after = rest:match("^(%a+)%+(.+)$")
        if not (mod and MODIFIER_ORDER[mod]) then break end
        mods[#mods + 1] = mod
        rest = after
    end
    if rest:match("^%u$") then
        mods[#mods + 1] = "Shift"
        rest = rest:lower()
    end
    table.sort(mods, function(a, b) return MODIFIER_ORDER[a] < MODIFIER_ORDER[b] end)
    mods[#mods + 1] = KEY_NAMES[rest] or rest
    return table.concat(mods, "+")
end

local function capitalise(text)
    return (text:gsub("^%l", string.upper))
end

-- input.conf comments; the uosc menu syntax ("! Path > Title @icon ?tip")
-- is reduced to its title and tooltip.
local function describe(binding)
    local comment = binding.comment
    if comment and comment ~= "" then
        local menu = comment:match("^!%s*(.*)")
        if menu then
            local tip = menu:match("%?(.*)$")
            local title = menu:gsub("%s*[@?].*$", ""):match("([^>]*)$"):match("^%s*(.-)%s*$")
            comment = tip and (title .. ": " .. tip:lower():gsub("^%s+", "")) or title
        end
        return capitalise(comment)
    end
    local script_key = binding.cmd:match("^script%-binding%s+(%S+)")
    if script_key and SCRIPT_KEYS[script_key] then return SCRIPT_KEYS[script_key] end
    -- mpv's own uncommented defaults: "add contrast -1" reads "Contrast -1"
    local prop, amount = binding.cmd:match("^add%s+(%S+)%s+(%S+)$")
    if prop then
        if not amount:match("^[-+]") then amount = "+" .. amount end
        return capitalise(prop:gsub("-", " ")) .. " " .. amount
    end
    return capitalise(binding.cmd)
end

local function categorise(cmd)
    local text = cmd:lower()
    for _, rule in ipairs(RULES) do
        for _, pattern in ipairs(rule[2]) do
            if text:find(pattern) then return rule[1] end
        end
    end
    return "Other"
end

-- input.conf first, then scripts, then what is left of mpv's own defaults.
local function source_rank(binding)
    if binding.section == "default" then
        return binding.is_weak and 2 or 0
    end
    return 1
end

local function collect()
    -- For each key, the binding that actually gets it: the highest priority.
    -- A negative priority means the binding is inactive.
    local winners, order = {}, {}
    for i, binding in ipairs(mp.get_property_native("input-bindings") or {}) do
        if binding.priority >= 0 then
            local best = winners[binding.key]
            if not best then order[#order + 1] = binding.key end
            if not best or binding.priority > best.priority then
                binding.index = i
                winners[binding.key] = binding
            end
        end
    end

    local groups = {}
    for _, key in ipairs(order) do
        local binding = winners[key]
        local cmd = binding.cmd or ""
        local base = key:match("([^+]+)$") or key
        local skip = cmd == "" or cmd == "ignore"
            or (not o.show_media_keys and MEDIA_KEYS[base])
            or (not o.show_meta_keys and key:find("Meta+", 1, true))
        if not skip then
            local category = categorise(cmd)
            local description = describe(binding)
            groups[category] = groups[category] or { rows = {}, by_text = {} }
            local group = groups[category]
            -- keys that do the same thing share a row
            local row = group.by_text[description]
            if row then
                row.keys[#row.keys + 1] = pretty_key(key)
            else
                row = {
                    keys = { pretty_key(key) },
                    text = description,
                    rank = source_rank(binding),
                    index = binding.index,
                }
                group.by_text[description] = row
                group.rows[#group.rows + 1] = row
            end
        end
    end

    local sheet = {}
    for _, name in ipairs(CATEGORY_ORDER) do
        local group = groups[name]
        if group then
            table.sort(group.rows, function(a, b)
                if a.rank ~= b.rank then return a.rank < b.rank end
                return a.index < b.index
            end)
            for _, row in ipairs(group.rows) do
                row.key_text = table.concat(row.keys, " / ")
            end
            sheet[#sheet + 1] = { name = name, rows = group.rows }
        end
    end
    return sheet
end

-- UTF-8 aware, since the arrows are multi-byte.
local function ulen(text)
    local _, count = text:gsub("[^\128-\191]", "")
    return count
end

local function utruncate(text, limit)
    if ulen(text) <= limit then return text end
    local out, n = {}, 0
    for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        n = n + 1
        if n >= limit then break end
        out[#out + 1] = char
    end
    return table.concat(out) .. "…"
end

local function ass_escape(text)
    return (text:gsub("\\", "\\\\"):gsub("{", "\\{"):gsub("}", "\\}"))
end

local overlay = mp.create_osd_overlay("ass-events")
overlay.res_y = 720

local state = { open = false, filter = "", page = 1, sheet = nil }
local char_width

local function font()
    return mp.get_property("osd-font") or "sans-serif"
end

-- The OSD font is monospace here, so one measured character sizes every
-- column. Measured rather than assumed, in case the font changes.
local function measure_char()
    local probe = mp.create_osd_overlay("ass-events")
    probe.res_y = 720
    probe.hidden = true
    probe.compute_bounds = true
    probe.data = string.format("{\\fn%s\\fs%d\\bord0\\shad0}%s", font(), o.font_size, string.rep("M", 40))
    local bounds = probe:update()
    probe:remove()
    if bounds and bounds.x1 and bounds.x1 > bounds.x0 then
        return (bounds.x1 - bounds.x0) / 40
    end
    return o.font_size * 0.46
end

local function matches(row, category, needle)
    if needle == "" then return true end
    return (row.key_text .. " " .. row.text .. " " .. category):lower():find(needle, 1, true) ~= nil
end

-- Lines are { kind = "heading" | "row" | "gap", ... }; columns take lines
-- until they are full, and pages take columns until the screen is.
local function layout(screen_w, rows_per_column)
    local needle = state.filter:lower()
    local lines = {}
    for _, category in ipairs(state.sheet) do
        local shown = {}
        for _, row in ipairs(category.rows) do
            if matches(row, category.name, needle) then shown[#shown + 1] = row end
        end
        if #shown > 0 then
            if #lines > 0 then lines[#lines + 1] = { kind = "gap" } end
            lines[#lines + 1] = { kind = "heading", text = category.name }
            for _, row in ipairs(shown) do
                lines[#lines + 1] = { kind = "row", row = row, category = category.name }
            end
        end
    end

    local columns, column = {}, nil
    local function new_column()
        column = { lines = {}, key_w = 0, text_w = 0 }
        columns[#columns + 1] = column
    end
    for _, line in ipairs(lines) do
        local full = not column or #column.lines >= rows_per_column
        -- a gap at the top of a fresh column is just wasted space
        if not (full and line.kind == "gap") then
            if full then
                new_column()
                -- a category that runs over carries its heading onto the next column
                if line.kind == "row" then
                    column.lines[1] = { kind = "heading", text = line.category .. " (cont.)" }
                end
            elseif line.kind == "heading" and #column.lines >= rows_per_column - 1 then
                -- don't leave a heading alone at the foot of a column
                new_column()
            end
            column.lines[#column.lines + 1] = line
            if line.kind == "row" then
                line.text = utruncate(line.row.text, o.max_description)
                column.key_w = math.max(column.key_w, ulen(line.row.key_text))
                column.text_w = math.max(column.text_w, ulen(line.text))
            end
        end
    end

    local pages, page, used = {}, nil, 0
    local gutter = 3 * char_width
    for _, col in ipairs(columns) do
        local heading_w = 0
        for _, line in ipairs(col.lines) do
            if line.kind == "heading" then heading_w = math.max(heading_w, ulen(line.text)) end
        end
        col.width = math.max(col.key_w + 2 + col.text_w, heading_w) * char_width
        if not page or used + col.width > screen_w then
            page = {}
            pages[#pages + 1] = page
            used = 0
        end
        page[#page + 1] = col
        used = used + col.width + gutter
    end
    return pages
end

local function render()
    if not state.open then
        overlay:remove()
        return
    end
    local osd_w, osd_h = mp.get_osd_size()
    if not osd_w or osd_h == 0 then return end
    local screen_w = 720 * osd_w / osd_h
    local left, top = 26, 24
    local line_h = math.floor(o.font_size * 1.3 + 0.5)
    local title_h = math.floor(o.font_size * 1.6 + 0.5) + line_h
    local body_top = top + title_h
    local rows_per_column = math.max(4, math.floor((720 - body_top - 24 - line_h * 2) / line_h))

    local pages = layout(screen_w - left * 2, rows_per_column)
    state.page = math.max(1, math.min(state.page, #pages))

    local style = string.format("\\fn%s\\bord1.5\\shad1\\3c%s\\4c%s", font(), OUTLINE, OUTLINE)
    local events = {}
    local alpha = string.format("%02X", math.floor(255 * (1 - o.backdrop_opacity) + 0.5))
    events[#events + 1] = string.format(
        "{\\an7\\pos(0,0)\\bord0\\shad0\\1c%s\\1a&H%s&\\p1}m 0 0 l %d 0 %d 720 0 720",
        OUTLINE, alpha, math.ceil(screen_w), math.ceil(screen_w))

    -- title, and the filter as you type it
    local title = "{\\b1\\1c" .. LABEL .. "}Keyboard shortcuts"
    if state.filter ~= "" then
        title = title .. "{\\b0\\1c" .. DETAIL .. "}   filter: {\\1c" .. VALUE .. "}" .. ass_escape(state.filter) .. "_"
    end
    events[#events + 1] = string.format("{\\an7\\pos(%d,%d)%s\\fs%d}%s",
        left, top, style, math.floor(o.font_size * 1.3 + 0.5), title)

    local page = pages[state.page]
    if not page then
        events[#events + 1] = string.format("{\\an7\\pos(%d,%d)%s\\fs%d\\1c%s}Nothing matches.",
            left, body_top, style, o.font_size, DETAIL)
    else
        local x = left
        for _, col in ipairs(page) do
            local y = body_top
            local text_x = x + (col.key_w + 2) * char_width
            for _, line in ipairs(col.lines) do
                if line.kind == "heading" then
                    events[#events + 1] = string.format("{\\an7\\pos(%d,%d)%s\\fs%d\\b1\\1c%s}%s",
                        x, y, style, o.font_size, LABEL, ass_escape(line.text))
                elseif line.kind == "row" then
                    events[#events + 1] = string.format("{\\an7\\pos(%d,%d)%s\\fs%d\\1c%s}%s",
                        x, y, style, o.font_size, VALUE, ass_escape(line.row.key_text))
                    events[#events + 1] = string.format("{\\an7\\pos(%d,%d)%s\\fs%d\\1c%s}%s",
                        text_x, y, style, o.font_size, DETAIL, ass_escape(line.text))
                end
                y = y + line_h
            end
            x = x + col.width + 3 * char_width
        end
    end

    local footer = "Type to filter   Backspace delete   Esc " ..
        (state.filter ~= "" and "clear" or "close")
    if #pages > 1 then
        footer = string.format("Page %d/%d   ←/→ or wheel turn   ", state.page, #pages) .. footer
    end
    events[#events + 1] = string.format("{\\an1\\pos(%d,%d)%s\\fs%d\\1c%s}%s",
        left, 720 - 24, style, o.font_size, DETAIL, footer)

    overlay.data = table.concat(events, "\n")
    overlay:update()
end

local close

local function turn(direction)
    state.page = state.page + direction
    render()
end

local function set_filter(text)
    state.filter = text
    state.page = 1
    render()
end

local BINDINGS = {
    { "ESC", function()
        if state.filter ~= "" then set_filter("") else close() end
    end },
    { "BS", function()
        set_filter(state.filter:gsub("[%z\1-\127\194-\244][\128-\191]*$", ""))
    end, { repeatable = true } },
    { "RIGHT", function() turn(1) end, { repeatable = true } },
    { "LEFT", function() turn(-1) end, { repeatable = true } },
    { "PGDWN", function() turn(1) end },
    { "PGUP", function() turn(-1) end },
    { "WHEEL_DOWN", function() turn(1) end },
    { "WHEEL_UP", function() turn(-1) end },
    { "MBTN_RIGHT", function() close() end },
    -- Every printable key filters, except ? which closes the sheet it opened.
    { "any_unicode", function(info)
        if info.event == "up" or not info.key_text then return end
        if info.key_text == "?" then return close() end
        set_filter(state.filter .. info.key_text)
    end, { complex = true, repeatable = true } },
}

local function on_resize()
    render()
end

local function open()
    state.open = true
    state.filter = ""
    state.page = 1
    state.sheet = collect()
    char_width = measure_char()
    for i, binding in ipairs(BINDINGS) do
        mp.add_forced_key_binding(binding[1], "cheatsheet-" .. i, binding[2], binding[3])
    end
    mp.observe_property("osd-dimensions", "native", on_resize)
    render()
end

close = function()
    state.open = false
    for i in ipairs(BINDINGS) do
        mp.remove_key_binding("cheatsheet-" .. i)
    end
    mp.unobserve_property(on_resize)
    render()
end

mp.add_key_binding(nil, "toggle", function()
    if state.open then close() else open() end
end)
