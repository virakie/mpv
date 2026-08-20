-- substyle.lua
--
-- Cycles the subtitle presets defined at the bottom of mpv.conf.
-- Fonts and styles are two separate cycles, so changing one keeps the other.
--
-- Key bindings live in input.conf:
--     Alt+Right / Alt+Left   next / previous font
--     Alt+Up    / Alt+Down   next / previous style
--     Alt+i                  show what is active
--     Alt+a                  open the adjust panel
--
-- A style preset is allowed to set sub-font itself (the Crunchyroll /
-- Netflix / fansub looks do). When one does, the font cycle notices and
-- either lands on the matching entry, or steps aside so the next Alt+Right
-- starts the fonts line from the top instead of from a stale position.
--
-- Which presets are in each cycle: script-opts/substyle.conf
-- The last used pair is written to substyle-state.txt in the config folder
-- and restored on the next launch.

local options = require 'mp.options'
local msg = require 'mp.msg'

local o = {
    -- profile names, in cycle order, comma separated
    fonts = "sub-font-inter",
    styles = "sub-style-clean",
    -- remember the last used preset between sessions
    persist = true,
    -- snap back to the default style every time subtitles come on
    default_on_subs = false,
    -- how long the on-screen name stays up, in seconds
    osd_duration = 2,
    -- text size for this script's messages and panel. mpv's own OSD
    -- default is 55, which is huge for a nine-row list; lower to shrink.
    osd_size = 20,
}
options.read_options(o, "substyle")

local state_file = mp.command_native({"expand-path", "~~/substyle-state.txt"})

-- mpv's OSD text is sized for one-line notices, and an inline {\fs} tag in
-- an osd_message does not override that, so a nine-row panel came out
-- filling the screen. Draw an ASS overlay instead: res_y sets the height of
-- the coordinate system, so osd_size is a size out of 720 no matter what
-- the window or display is.
local overlay = mp.create_osd_overlay("ass-events")
overlay.res_y = 720

local adjusting = false   -- true while the adjust panel is open
local draw_panel          -- defined further down, called back into from here
local hide_timer

local function ass_escape(text)
    return (text:gsub("\\", "\\\\"):gsub("{", "\\{"):gsub("}", "\\}")
                :gsub("\n", "\\N"))
end

-- `body` is ASS, already escaped. A nil duration leaves it up indefinitely.
local function draw(body, duration)
    if hide_timer then
        hide_timer:kill()
        hide_timer = nil
    end
    overlay.data = string.format(
        "{\\an7\\pos(24,18)\\fs%d\\bord1.6\\shad0\\fn%s\\3c&H000000&}%s",
        o.osd_size, mp.get_property("osd-font") or "sans-serif", body)
    overlay:update()
    if duration then
        hide_timer = mp.add_timeout(duration, function()
            hide_timer = nil
            -- a notice shown over the open panel must not wipe it out
            if adjusting then draw_panel() else overlay:remove() end
        end)
    end
end

local function show(text, duration)
    draw("{\\1c&HFFFFFF&}" .. ass_escape(text), duration or o.osd_duration)
end

local function hide()
    if hide_timer then
        hide_timer:kill()
        hide_timer = nil
    end
    overlay:remove()
end

local function split(str)
    local list = {}
    for item in string.gmatch(str or "", "([^,]+)") do
        item = item:match("^%s*(.-)%s*$")
        if item ~= "" then
            list[#list + 1] = item
        end
    end
    return list
end

local function index_of(list, name)
    for i, entry in ipairs(list) do
        if entry == name then return i end
    end
end

-- One entry per cycle. `index` points at the preset currently applied.
local sets = {
    font  = { label = "Sub font",  list = split(o.fonts),  index = 1 },
    style = { label = "Sub style", list = split(o.styles), index = 1 },
}

-- Readable names come from the profile-desc line of each profile, and we
-- note which sub-font each font preset stands for, to recognise it later.
local descriptions = {}
local font_of = {}
local saved_presets = {}
for _, profile in ipairs(mp.get_property_native("profile-list") or {}) do
    if profile.name then
        descriptions[profile.name] = profile["profile-desc"]
        for _, opt in ipairs(profile.options or {}) do
            if opt.key == "sub-font" then
                font_of[profile.name] = opt.value
            end
        end
        -- Presets written by the adjust panel's w key, picked up through
        -- the include line in mpv.conf.
        if profile.name:find("^sub%-style%-custom") then
            saved_presets[#saved_presets + 1] = profile.name
        end
    end
end

-- Add saved presets to the end of the style cycle, so one is usable on the
-- next launch without editing substyle.conf. Listing it there by hand still
-- works and takes precedence -- that is how you move one to the front.
table.sort(saved_presets)
for _, name in ipairs(saved_presets) do
    if not index_of(sets.style.list, name) then
        sets.style.list[#sets.style.list + 1] = name
    end
end

local function pretty(name)
    return descriptions[name] or name
end

local function save_state()
    if not o.persist then return end
    local file = io.open(state_file, "w")
    if not file then
        msg.warn("could not write " .. state_file)
        return
    end
    for kind, set in pairs(sets) do
        local name = set.list[set.index]
        -- An adrift font is one a style chose for us, not one you picked;
        -- saving it would make it override that style on the next launch.
        if name and not set.adrift then
            file:write(kind .. "=" .. name .. "\n")
        end
    end
    file:close()
end

-- Returns a set of the cycles that had a saved position, e.g. {style = true}.
local function load_state()
    local restored = {}
    if not o.persist then return restored end
    local file = io.open(state_file, "r")
    if not file then return restored end
    for line in file:lines() do
        local kind, name = line:match("^(%a+)=(.+)$")
        local set = kind and sets[kind]
        if set then
            local i = index_of(set.list, name)
            if i then
                set.index = i
                restored[kind] = true
            else
                -- preset was renamed or dropped from the cycle
                msg.verbose("ignoring unknown saved preset: " .. name)
            end
        end
    end
    file:close()
    return restored
end

-- A style may have changed the font out from under us. Point the font cycle
-- at whichever preset matches what is now on screen; if nothing matches,
-- mark it adrift so the next step restarts the line rather than continuing
-- from a position that no longer means anything.
local function resync_font()
    local active = mp.get_property("sub-font")
    for i, name in ipairs(sets.font.list) do
        if font_of[name] == active then
            sets.font.index = i
            sets.font.adrift = false
            return
        end
    end
    sets.font.adrift = true
end

local function apply(kind, announce)
    local set = sets[kind]
    local name = set.list[set.index]
    if not name then return end
    mp.commandv("apply-profile", name)
    msg.verbose("applied " .. name)
    if kind == "style" then
        resync_font()
    end
    if announce then
        show(set.label .. ": " .. pretty(name))
    end
end

local function cycle(kind, step)
    local set = sets[kind]
    if #set.list == 0 then
        show("substyle: nothing listed for '" .. kind ..
             "' in script-opts/substyle.conf")
        return
    end
    if set.adrift then
        -- restart the line from whichever end we are heading towards
        set.index = step > 0 and 1 or #set.list
        set.adrift = false
    else
        set.index = (set.index - 1 + step) % #set.list + 1
    end
    apply(kind, true)
    save_state()
end

mp.add_key_binding(nil, "next-font",  function() cycle("font",   1) end)
mp.add_key_binding(nil, "prev-font",  function() cycle("font",  -1) end)
mp.add_key_binding(nil, "next-style", function() cycle("style",  1) end)
mp.add_key_binding(nil, "prev-style", function() cycle("style", -1) end)

mp.add_key_binding(nil, "show", function()
    -- Report the font mpv is actually using, not the last one we picked:
    -- a style preset or an adjustment may have replaced it.
    show(sets.font.label  .. ": " .. (mp.get_property("sub-font") or "-") .. "\n" ..
         sets.style.label .. ": " .. pretty(sets.style.list[sets.style.index] or "-"),
         o.osd_duration + 1)
end)

-- Jump straight to a preset and keep the cycle position in sync, e.g.
--     Ctrl+2 script-message substyle-set style sub-style-box
mp.register_script_message("substyle-set", function(kind, name)
    local set = sets[kind]
    if not set then
        msg.warn("unknown cycle: " .. tostring(kind))
        return
    end
    local i = index_of(set.list, name)
    if not i then
        msg.warn("'" .. tostring(name) .. "' is not listed in the " .. kind .. " cycle")
        return
    end
    set.index = i
    apply(kind, true)
    save_state()
end)

--------------------------------------------------------------------------
-- Adjust mode.
--
-- Alt+a opens a small panel. Up/Down picks a parameter, Left/Right changes
-- it, and you watch the subtitle change under it. The keys are "forced"
-- bindings, so while the panel is open the arrows adjust subtitles instead
-- of seeking and changing volume, and everything is handed back on exit.
--
-- Tweaks last until you switch preset or quit. To keep one:
--   s  overwrite the preset you are adjusting, in whichever file holds it
--   w  save as a new preset in substyle-custom.conf
--   x  delete the preset you are on, if it was one saved with w
-- The first write to a file copies it to <name>.before-substyle first.
--------------------------------------------------------------------------

local params = {
    { label = "Size",         prop = "sub-font-size",     step = 1,    min = 5,   max = 200, fmt = "%.0f" },
    { label = "Scale",        prop = "sub-scale",         step = 0.05, min = 0.1, max = 5,   fmt = "%.2f" },
    { label = "Position",     prop = "sub-pos",           step = 1,    min = 0,   max = 150, fmt = "%.0f" },
    { label = "Outline",      prop = "sub-border-size",   step = 0.2,  min = 0,   max = 10,  fmt = "%.1f" },
    { label = "Shadow",       prop = "sub-shadow-offset", step = 0.2,  min = 0,   max = 10,  fmt = "%.1f" },
    { label = "Shadow alpha", prop = "sub-shadow-color",  step = 16,   alpha = true },
    { label = "Blur",         prop = "sub-blur",          step = 0.2,  min = 0,   max = 20,  fmt = "%.1f" },
    { label = "Box alpha",    prop = "sub-back-color",    step = 16,   alpha = true },
    { label = "Bold",         prop = "sub-bold",          toggle = true },
}

-- Every option a style preset sets, in the order the presets list them, so
-- an exported block reads like the hand-written ones.
local exported = {
    "sub-ass-override", "sub-scale", "sub-font", "sub-font-size", "sub-color",
    "sub-bold", "sub-pos", "sub-border-size", "sub-border-color",
    "sub-shadow-offset", "sub-shadow-color", "sub-back-color", "sub-blur",
}

-- `adjusting` is declared up with the overlay, which needs to see it.
local selected = 1

-- Colors are #AARRGGBB; the alpha rows edit those first two digits in place.
local function alpha_of(prop)
    local a = (mp.get_property(prop) or ""):match("^#(%x%x)%x%x%x%x%x%x$")
    return a and tonumber(a, 16) or 255
end

local function set_alpha(prop, value)
    local rgb = (mp.get_property(prop) or ""):match("^#%x%x(%x%x%x%x%x%x)$") or "000000"
    mp.set_property(prop, string.format("#%02X%s", value, rgb))
end

local function value_of(param)
    if param.toggle then
        return mp.get_property(param.prop) or "?"
    elseif param.alpha then
        return string.format("%d%%", math.floor(alpha_of(param.prop) / 255 * 100 + 0.5))
    end
    return string.format(param.fmt, mp.get_property_number(param.prop) or 0)
end

-- Assignment, not "local function": the name is declared up top so that
-- draw() can put the panel back after a passing notice covers it.
draw_panel = function(note)
    -- ASS colours are &HBBGGRR&, i.e. reversed from the #RRGGBB you write
    -- everywhere else in this config.
    local rows = { "{\\1c&HFFFFFF&}" ..
                   ass_escape(pretty(sets.style.list[sets.style.index] or "-")) }
    for i, param in ipairs(params) do
        -- libass trims a leading plain space, which would pull every
        -- unselected row one character left of the marked one. \h is the
        -- ASS hard space and survives.
        rows[#rows + 1] =
            (i == selected and "{\\1c&H4AD2FF&}>" or "{\\1c&HE0E0E0&}\\h") ..
            ass_escape(string.format(" %-12s %s", param.label, value_of(param)))
    end
    rows[#rows + 1] = "{\\1c&HA0A0A0&}" .. ass_escape(note or
        "Left/Right change  Up/Down pick  r reset  " ..
        "s save  w save as new  x delete  ESC close")
    draw(table.concat(rows, "\\N"), nil)
end

local function nudge(direction)
    local param = params[selected]
    if param.toggle then
        mp.set_property_bool(param.prop, not mp.get_property_bool(param.prop))
    elseif param.alpha then
        local a = alpha_of(param.prop) + direction * param.step
        set_alpha(param.prop, math.max(0, math.min(255, a)))
    else
        local v = (mp.get_property_number(param.prop) or 0) + direction * param.step
        v = math.max(param.min, math.min(param.max, v))
        -- steps like 0.2 drift into 1.7999999 otherwise
        mp.set_property_number(param.prop, math.floor(v * 1000 + 0.5) / 1000)
    end
    draw_panel()
end

local function pick(direction)
    selected = (selected - 1 + direction) % #params + 1
    draw_panel()
end

local function reset()
    apply("style", false)
    draw_panel("reset to the preset's own values")
end

-- mpv hands values back as "43.000000" and "force"; write them the way the
-- presets in mpv.conf are written, so an exported block can be pasted in
-- without tidying it up by hand.
local function tidy(value)
    local number = tonumber(value)
    if number then
        return (string.format("%.3f", number):gsub("%.?0+$", ""))
    end
    if value:find(" ") or value:sub(1, 1) == "#" then
        return '"' .. value .. '"'
    end
    return value
end

local custom_path = mp.command_native({"expand-path", "~~/substyle-custom.conf"})
local mpv_conf    = mp.command_native({"expand-path", "~~/mpv.conf"})

--------------------------------------------------------------------------
-- Editing the config files in place, for saving into an existing preset
-- and for deleting one. Both keep every line's trailing \r, so mpv.conf
-- stays CRLF, and both leave the comments around a block alone.
--------------------------------------------------------------------------

local function read_lines(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local data = file:read("*a")
    file:close()
    local lines, from = {}, 1
    while true do
        local nl = data:find("\n", from, true)
        if not nl then
            if from <= #data then lines[#lines + 1] = data:sub(from) end
            break
        end
        lines[#lines + 1] = data:sub(from, nl - 1)   -- keeps any \r
        from = nl + 1
    end
    return lines
end

local function write_lines(path, lines)
    local file = io.open(path, "wb")
    if not file then return false end
    file:write(table.concat(lines, "\n"), "\n")
    file:close()
    return true
end

-- The lines of a [name] block: from its header to just before the next one.
local function find_block(lines, name)
    local first
    for i, line in ipairs(lines) do
        if line:match("^%s*%[(.-)%]%s*\r?$") == name then
            first = i
            break
        end
    end
    if not first then return nil end
    local last = #lines
    for i = first + 1, #lines do
        if lines[i]:match("^%s*%[") then
            last = i - 1
            break
        end
    end
    -- Blank lines and comments at the tail belong to whatever comes next,
    -- not to this block. Hand them back separately so they stay put.
    local body_end = last
    while body_end > first and
          (lines[body_end]:match("^%s*\r?$") or lines[body_end]:match("^%s*#")) do
        body_end = body_end - 1
    end
    return first, body_end, last
end

local function locate(name)
    for _, path in ipairs({ mpv_conf, custom_path }) do
        local lines = read_lines(path)
        if lines then
            local first, body_end, last = find_block(lines, name)
            if first then return path, lines, first, body_end, last end
        end
    end
end

-- Keep one copy of a config file as it was before this script first wrote
-- to it. Only the first time: a later bug must not overwrite a good backup.
local function backup_once(path)
    local backup = path .. ".before-substyle"
    local existing = io.open(backup, "rb")
    if existing then
        existing:close()
        return
    end
    local source = io.open(path, "rb")
    if not source then return end
    local data = source:read("*a")
    source:close()
    local file = io.open(backup, "wb")
    if file then
        file:write(data)
        file:close()
        msg.info("kept a copy of " .. path .. " as " .. backup)
    end
end

local function option_lines(eol, skip)
    local out = {}
    for _, prop in ipairs(exported) do
        local value = mp.get_property(prop)
        if value and not (skip and skip[prop]) then
            out[#out + 1] = prop .. "=" .. tidy(value) .. eol
        end
    end
    return out
end

-- Overwrite the preset currently selected with what is on screen now.
local function save_into_current()
    local name = sets.style.list[sets.style.index]
    if not name then return end
    local path, lines, first, body_end, last = locate(name)
    if not path then
        draw_panel("no [" .. name .. "] block found to save into")
        return
    end
    backup_once(path)
    local eol = lines[first]:sub(-1) == "\r" and "\r" or ""

    -- A plain style leaves the font to the font cycle. Saving into one must
    -- not quietly give it the font that happens to be on screen, or it stops
    -- being font-agnostic; only a preset that already names a font keeps one.
    local had_font = false
    for i = first + 1, body_end do
        if lines[i]:match("^%s*sub%-font%s*=") then had_font = true end
    end

    local rebuilt = { lines[first] }                    -- the [name] header
    for i = first + 1, body_end do                      -- its own comments
        if lines[i]:match("^%s*#") or lines[i]:match("^profile%-desc=") then
            rebuilt[#rebuilt + 1] = lines[i]
        end
    end
    for _, line in ipairs(option_lines(eol, not had_font and { ["sub-font"] = true })) do
        rebuilt[#rebuilt + 1] = line
    end

    local out = {}
    for i = 1, first - 1 do out[#out + 1] = lines[i] end
    for _, line in ipairs(rebuilt) do out[#out + 1] = line end
    for i = body_end + 1, #lines do out[#out + 1] = lines[i] end

    if write_lines(path, out) then
        msg.info("saved into [" .. name .. "] in " .. path)
        draw_panel("saved into " .. pretty(name) .. "  (r uses it after a restart)")
    else
        draw_panel("could not write " .. path)
    end
end

-- Delete a preset saved with w. Built-in ones are left alone: their block
-- in mpv.conf comes with comments worth keeping, so that is a hand edit.
local function delete_current()
    local name = sets.style.list[sets.style.index]
    if not name then return end
    if not name:find("^sub%-style%-custom") then
        draw_panel("only presets saved with w can be deleted here")
        return
    end
    local lines = read_lines(custom_path)
    local first, body_end
    if lines then first, body_end = find_block(lines, name) end
    if not first then
        draw_panel("no [" .. name .. "] block found in substyle-custom.conf")
        return
    end
    backup_once(custom_path)
    -- take the blank separator above the block with it
    local from = first
    while from > 1 and lines[from - 1]:match("^%s*\r?$") do from = from - 1 end

    local out = {}
    for i = 1, from - 1 do out[#out + 1] = lines[i] end
    for i = body_end + 1, #lines do out[#out + 1] = lines[i] end
    if not write_lines(custom_path, out) then
        draw_panel("could not write " .. custom_path)
        return
    end

    table.remove(sets.style.list, sets.style.index)
    if #sets.style.list == 0 then
        draw_panel("deleted " .. name .. " - the style cycle is now empty")
        return
    end
    if sets.style.index > #sets.style.list then
        sets.style.index = #sets.style.list
    end
    apply("style", false)
    save_state()
    msg.info("deleted [" .. name .. "] from " .. custom_path)
    draw_panel("deleted " .. name)
end

-- Two saves in the same minute would otherwise both be called ...-2231,
-- and mpv would merge two blocks sharing a name into one profile.
local function unique_name()
    local taken = {}
    for _, existing in ipairs(saved_presets) do taken[existing] = true end
    local lines = read_lines(custom_path)
    if lines then
        for _, line in ipairs(lines) do
            local found = line:match("^%s*%[(.-)%]%s*\r?$")
            if found then taken[found] = true end
        end
    end
    local base = "sub-style-custom-" .. os.date("%H%M")
    if not taken[base] then return base end
    local n = 2
    while taken[base .. "-" .. n] do n = n + 1 end
    return base .. "-" .. n
end

local function export()
    local path = custom_path
    local file = io.open(path, "a")
    if not file then
        draw_panel("could not write " .. path)
        return
    end
    local name = unique_name()
    file:write("\n[" .. name .. "]\n")
    file:write("profile-desc=Custom - saved " .. os.date("%Y-%m-%d %H:%M") .. "\n")
    for _, prop in ipairs(exported) do
        local value = mp.get_property(prop)
        if value then
            file:write(prop .. "=" .. tidy(value) .. "\n")
        end
    end
    file:close()
    msg.info("wrote [" .. name .. "] to " .. path)
    draw_panel("saved as [" .. name .. "] in substyle-custom.conf")
end

local mode_keys
local function close_panel()
    if not adjusting then return end
    adjusting = false
    for _, key in ipairs(mode_keys) do
        mp.remove_key_binding(key[2])
    end
    hide()
end

mode_keys = {
    { "RIGHT", "adjust-up",    function() nudge(1) end,  { repeatable = true } },
    { "LEFT",  "adjust-down",  function() nudge(-1) end, { repeatable = true } },
    { "DOWN",  "adjust-next",  function() pick(1) end,   { repeatable = true } },
    { "UP",    "adjust-prev",  function() pick(-1) end,  { repeatable = true } },
    { "r",     "adjust-reset",  reset },
    { "s",     "adjust-save",   save_into_current },
    { "w",     "adjust-write",  export },
    { "x",     "adjust-delete", delete_current },
    { "ESC",   "adjust-close", function() close_panel() end },
    { "ENTER", "adjust-done",  function() close_panel() end },
}

mp.add_key_binding(nil, "adjust", function()
    if adjusting then
        close_panel()
        return
    end
    adjusting = true
    for _, key in ipairs(mode_keys) do
        mp.add_forced_key_binding(key[1], key[2], key[3], key[4])
    end
    draw_panel()
end)

--------------------------------------------------------------------------
-- default_on_subs: put the default style back every time subtitles come on,
-- so a file always starts from the same look no matter what you switched to
-- while watching the last one.
--------------------------------------------------------------------------

local subs_were_on = false

local function subs_are_on()
    local sid = mp.get_property("sid")
    return sid ~= nil and sid ~= "no" and mp.get_property_bool("sub-visibility")
end

local function subs_changed()
    local on = subs_are_on()
    if on and not subs_were_on then
        -- The default is the first name on the styles line, the same one
        -- startup falls back to. Applied quietly, and deliberately not
        -- written to the state file: the preset you last chose by hand stays
        -- remembered for whenever this option gets turned back off.
        sets.style.index = 1
        sets.style.adrift = false
        apply("style", false)
    end
    subs_were_on = on
end

if o.default_on_subs then
    mp.observe_property("sid", "native", subs_changed)
    mp.observe_property("sub-visibility", "native", subs_changed)
    -- A new file often selects the same track id as the last one, which is
    -- not a change and so raises no notification. Treat every load as
    -- subtitles arriving fresh.
    mp.register_event("file-loaded", function()
        subs_were_on = false
        subs_changed()
    end)
end

-- Startup. Whatever was in use last time wins; with nothing saved, each
-- cycle falls back to its index of 1, which is why the first name on a line
-- in substyle.conf is that line's default.
local restored = load_state()

apply("style", false)   -- style first: it may carry its own font

-- Only then the font, and only if it is genuinely yours to impose. With no
-- saved font, a style that brought its own keeps it -- otherwise starting on
-- the Crunchyroll preset would immediately lose Trebuchet to font entry 1.
if restored.font or not font_of[sets.style.list[sets.style.index]] then
    apply("font", false)
end
