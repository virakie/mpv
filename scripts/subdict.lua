-- subdict.lua
--
-- Press d while a subtitle is on screen: playback pauses, the line comes
-- back as individually clickable words, and the word most likely to be the
-- unfamiliar one is looked up straight away. Click or arrow onto any other
-- word to look that one up instead. Esc (or d again) resumes.
--
-- Definitions come from dictionaryapi.dev via curl, and every answer is
-- cached to subdict-cache.json in the config folder, so a word you have
-- looked up once resolves instantly and works offline afterwards.
--
-- Only works on text subtitles. Bitmap subs (Blu-ray PGS) carry no text
-- for mpv to hand over, and the script says so rather than looking dead.

local utils = require 'mp.utils'
local msg = require 'mp.msg'
local options = require 'mp.options'

local o = {
    -- text size for the word strip and the definition panel, out of 720
    font_size = 20,
    -- how many senses to show
    max_definitions = 3,
    -- characters per line before the definition wraps
    wrap_at = 62,
    -- seconds to wait on the network before giving up
    timeout = 8,
}
options.read_options(o, "subdict")

local cache_path = mp.command_native({"expand-path", "~~/subdict-cache.json"})

-- The palette osd-theme uses, so a definition reads like every other message
-- this config puts on screen.
local LABEL   = "&HFFD9CE&"
local VALUE   = "&HF3AB5D&"
local DETAIL  = "&HE6B9AC&"
local OUTLINE = "&H36231E&"

-- Words that are never the one you paused for.
local COMMON = {}
for word in ([[the be to of and a in that have i it for not on with he as you
do at this but his by from they we say her she or an will my one all would
there their what so up out if about who get which go me when make can like
time no just him know take people into year your good some could them see
other than then now look only come its over think also back after use two
how our work first well way even new want because any these give day most us
is was are were been has had did does said were am being your yours very
much many more should must might shall into upon such those thing things
something nothing everything someone anyone here where why while before
after again still ever never always]]):gmatch("%a+") do
    COMMON[word] = true
end

local panel = mp.create_osd_overlay("ass-events")
local strip = mp.create_osd_overlay("ass-events")
local ruler = mp.create_osd_overlay("ass-events")
panel.res_y, strip.res_y, ruler.res_y = 720, 720, 720
ruler.hidden = true
ruler.compute_bounds = true

local open = false
local strip_y = 620       -- where the word strip sits, in 720-space
local words = {}          -- { text=, clean=, x=, w= }
local selected = 1
local entry = nil         -- the definition being shown
local status = nil        -- a message shown in place of a definition
local saved = {}          -- playback state to put back on close
local cache = nil
local widths = {}         -- measurement memo, keyed by the string

local function font()
    return mp.get_property("osd-font") or "sans-serif"
end

local function ass_escape(text)
    return (text:gsub("\\", "\\\\"):gsub("{", "\\{"):gsub("}", "\\}"))
end

-- Render text into a hidden overlay just to find out how wide it is. This
-- is what makes per-word hit-testing possible: mpv will not tell us where
-- libass put the real subtitle, but it will measure text we hand it.
local function measure(text)
    if widths[text] then return widths[text] end
    ruler.data = string.format("{\\an7\\pos(0,0)\\fs%d\\fn%s}%s",
                               o.font_size, font(), ass_escape(text))
    local r = ruler:update()
    local w = (r and r.x1 and r.x0) and (r.x1 - r.x0) or (#text * o.font_size * 0.6)
    widths[text] = w
    return w
end

--------------------------------------------------------------------------
-- Cache
--------------------------------------------------------------------------

local function load_cache()
    if cache then return cache end
    cache = {}
    local file = io.open(cache_path, "r")
    if file then
        local parsed = utils.parse_json(file:read("*a") or "")
        file:close()
        if type(parsed) == "table" then cache = parsed end
    end
    return cache
end

local function save_cache()
    local file = io.open(cache_path, "w")
    if not file then
        msg.warn("could not write " .. cache_path)
        return
    end
    file:write(utils.format_json(cache))
    file:close()
end

--------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------

local function wrap(text, width)
    local lines, line = {}, ""
    for word in text:gmatch("%S+") do
        if line == "" then
            line = word
        elseif #line + #word + 1 <= width then
            line = line .. " " .. word
        else
            lines[#lines + 1] = line
            line = word
        end
    end
    if line ~= "" then lines[#lines + 1] = line end
    return lines
end

local function draw_panel()
    local rows = {}
    local word = words[selected]
    local head = word and word.clean or "?"
    if entry and entry.phonetic and entry.phonetic ~= "" then
        head = head .. "   " .. entry.phonetic
    end
    rows[#rows + 1] = "{\\b1\\1c" .. LABEL .. "}" .. ass_escape(head)

    -- Definitions sit a size down from the headword, the way osd-theme puts
    -- its detail line under its label.
    local small = "{\\b0\\fs" .. o.font_size .. "}"

    if status then
        rows[#rows + 1] = small .. "{\\1c" .. DETAIL .. "}" .. ass_escape(status)
    elseif entry then
        for _, sense in ipairs(entry.senses) do
            local first = true
            for _, line in ipairs(wrap(sense, o.wrap_at)) do
                rows[#rows + 1] = small
                    .. "{\\1c" .. (first and VALUE or DETAIL) .. "}"
                    .. (first and "" or "\\h\\h") .. ass_escape(line)
                first = false
            end
        end
    end

    panel.data = string.format(
        "{\\an7\\pos(26,24)\\fs%d\\bord2\\shad1\\fn%s\\3c%s\\4c%s}%s",
        o.font_size + 6, font(), OUTLINE, OUTLINE, table.concat(rows, "\\N"))
    panel:update()
end

-- The line itself, one ASS event per word so each has a known x range.
local function draw_strip()
    local events = {}
    for i, w in ipairs(words) do
        local color = (i == selected) and VALUE or LABEL
        events[#events + 1] = string.format(
            "{\\an7\\pos(%.1f,%.1f)\\fs%d\\bord2\\shad1\\fn%s\\3c%s\\4c%s\\1c%s}%s",
            w.x, w.y, o.font_size, font(), OUTLINE, OUTLINE, color, ass_escape(w.text))
    end
    strip.data = table.concat(events, "\n")
    strip:update()
end

--------------------------------------------------------------------------
-- Lookup
--------------------------------------------------------------------------

local function shape(json)
    -- dictionaryapi.dev hands back a list of entries; keep it small.
    if type(json) ~= "table" or not json[1] then return nil end
    local first = json[1]
    local out = { phonetic = first.phonetic, senses = {} }
    for _, meaning in ipairs(first.meanings or {}) do
        for _, def in ipairs(meaning.definitions or {}) do
            if #out.senses < o.max_definitions then
                out.senses[#out.senses + 1] =
                    (meaning.partOfSpeech or "?") .. ".  " .. (def.definition or "")
            end
        end
    end
    if #out.senses == 0 then return nil end
    return out
end

local lookup

-- Plain dictionaries do not hold inflected forms, so on a miss try the
-- obvious stems before giving up: scurried -> scurry, houses -> house.
local function stems(word)
    local out = {}
    local function add(s) if s and #s > 2 and s ~= word then out[#out + 1] = s end end
    add(word:match("^(.*)s$"))
    add(word:match("^(.*)es$"))
    add(word:match("^(.*)ed$"))
    add(word:match("^(.*)ing$"))
    local body = word:match("^(.*)ied$") or word:match("^(.*)ies$")
    if body then add(body .. "y") end
    local doubled = word:match("^(.*)(%a)%2ed$") or word:match("^(.*)(%a)%2ing$")
    if doubled then add(doubled) end
    return out
end

lookup = function(word, fallbacks)
    local hit = load_cache()[word]
    if hit then
        entry, status = hit, nil
        draw_panel()
        return
    end

    status = "looking up ..."
    draw_panel()

    mp.command_native_async({
        name = "subprocess", capture_stdout = true, playback_only = false,
        -- -4 because the odd IPv6 attempt here stalls until the whole
        -- timeout is spent, and one retry covers the API's occasional hiccup.
        args = { "curl", "-s", "-4", "--connect-timeout", "4", "--retry", "1",
                 "-m", tostring(o.timeout),
                 "https://api.dictionaryapi.dev/api/v2/entries/en/" .. word },
    }, function(ok, res)
        if not open then return end
        local parsed = ok and res and res.stdout and utils.parse_json(res.stdout)
        local shaped = parsed and shape(parsed)
        if shaped then
            cache[word] = shaped
            save_cache()
            entry, status = shaped, nil
            draw_panel()
            return
        end
        -- try a stem, then admit defeat
        local next_try = fallbacks and table.remove(fallbacks, 1)
        if next_try then
            lookup(next_try, fallbacks)
        else
            entry = nil
            status = (ok and res and res.status == 0)
                     and "no definition found"
                     or  "lookup failed - is the network up?"
            draw_panel()
        end
    end)
end

local function lookup_selected()
    local w = words[selected]
    if not w then return end
    entry = nil
    lookup(w.clean, stems(w.clean))
end

--------------------------------------------------------------------------
-- Opening and closing
--------------------------------------------------------------------------

-- The longest word that is not everyday vocabulary: a crude stand-in for
-- word frequency, and usually right about which word stopped you.
local function hardest()
    local best, best_len = 1, -1
    for i, w in ipairs(words) do
        local len = #w.clean
        if not COMMON[w.clean] and len > best_len then
            best, best_len = i, len
        end
    end
    return best
end

-- The overlay is 720 tall, so its width follows the window's aspect rather
-- than being a fixed 1280.
local function overlay_width()
    local osd = mp.get_property_native("osd-dimensions")
    if osd and osd.w and osd.h and osd.h > 0 then
        return 720 * (osd.w / osd.h)
    end
    return 1280
end

local function tokenize(text)
    words = {}
    local width = overlay_width()
    local limit = width - 48
    local line_h = o.font_size * 1.35
    local space = measure("m m") - (2 * measure("m"))
    if space <= 0 then space = o.font_size * 0.35 end

    -- Lay out into rows, breaking where a two-line subtitle would otherwise
    -- run off the side.
    local rows_of, row, x = {}, {}, 0
    for token in text:gmatch("%S+") do
        local w = measure(token)
        if #row > 0 and x + w > limit then
            rows_of[#rows_of + 1] = { items = row, width = x - space }
            row, x = {}, 0
        end
        local clean = token:lower():gsub("[^%a'-]", ""):gsub("^'+", ""):gsub("'+$", "")
        row[#row + 1] = { text = token, clean = clean, x = x, w = w }
        x = x + w + space
    end
    if #row > 0 then
        rows_of[#rows_of + 1] = { items = row, width = x - space }
    end

    -- Sit where the subtitle itself was, so the line does not jump when it
    -- is handed over to us. sub-pos is a percentage down the frame.
    local pos = mp.get_property_number("sub-pos") or 100
    local bottom = math.min(720 * (pos / 100), 720 - line_h) - (o.font_size * 0.4)
    local top = bottom - (#rows_of - 1) * line_h

    for r, entry_row in ipairs(rows_of) do
        local shift = (width - entry_row.width) / 2
        local y = top + (r - 1) * line_h
        for _, w in ipairs(entry_row.items) do
            w.x = w.x + shift
            w.y = y
            words[#words + 1] = w
        end
    end
    strip_y = top
end

local close

local function on_click()
    if not open then return end
    local m = mp.get_property_native("mouse-pos")
    if not m then return end
    local osd = mp.get_property_native("osd-dimensions")
    if not osd or not osd.h or osd.h == 0 then return end
    local scale = 720 / osd.h
    local mx, my = m.x * scale, m.y * scale
    for i, w in ipairs(words) do
        if mx >= w.x - 4 and mx <= w.x + w.w + 4 and
           my >= w.y - 6 and my <= w.y + o.font_size + 10 then
            selected = i
            draw_strip()
            lookup_selected()
            return
        end
    end
end

local function move(delta)
    if #words == 0 then return end
    selected = (selected - 1 + delta) % #words + 1
    draw_strip()
    lookup_selected()
end

local BINDINGS = {
    { "RIGHT", "subdict-next",  function() move(1) end },
    { "LEFT",  "subdict-prev",  function() move(-1) end },
    { "ENTER", "subdict-again", function() lookup_selected() end },
    { "MBTN_LEFT", "subdict-click", function() on_click() end },
    { "ESC",   "subdict-close", function() close() end },
    { "d",     "subdict-close-d", function() close() end },
}

close = function()
    if not open then return end
    open = false
    panel.data, strip.data = "", ""
    panel:update()
    strip:update()
    for _, b in ipairs(BINDINGS) do mp.remove_key_binding(b[2]) end
    if saved.window_dragging ~= nil then
        mp.set_property_bool("window-dragging", saved.window_dragging)
    end
    if saved.sub_visibility ~= nil then
        mp.set_property_bool("sub-visibility", saved.sub_visibility)
    end
    if saved.pause ~= nil then
        mp.set_property_bool("pause", saved.pause)
    end
    saved = {}
end

local function lookup_line()
    if open then close() return end

    local text = mp.get_property("sub-text")
    if not text or text:gsub("%s", "") == "" then
        mp.commandv("script-message-to", "osd_theme", "say", "Dictionary", "", "no subtitle line on screen")
        return
    end

    tokenize((text:gsub("\n", " ")))
    if #words == 0 then
        mp.commandv("script-message-to", "osd_theme", "say", "Dictionary", "", "nothing to look up")
        return
    end

    saved.pause = mp.get_property_bool("pause")
    saved.sub_visibility = mp.get_property_bool("sub-visibility")
    saved.window_dragging = mp.get_property_bool("window-dragging")
    mp.set_property_bool("pause", true)
    -- our copy of the line replaces the real one, so it is not drawn twice
    mp.set_property_bool("sub-visibility", false)
    -- clicking a word must not drag the window, same as the seek bar
    mp.set_property_bool("window-dragging", false)

    open = true
    selected = hardest()
    entry, status = nil, nil
    draw_strip()
    draw_panel()
    lookup_selected()

    for _, b in ipairs(BINDINGS) do
        mp.add_forced_key_binding(b[1], b[2], b[3])
    end
end

mp.register_event("start-file", close)
mp.add_key_binding(nil, "lookup", lookup_line)
