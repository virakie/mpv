-- presence.lua
--
-- Works out what show or film is playing and publishes it for Discord Rich
-- Presence. Alt+p toggles it, Alt+P re-picks if it guessed wrong.
--
-- The Discord half is a separate compiled plugin. This script does not talk
-- to Discord at all: it writes the finished activity to the mpv property
-- `user-data/presence/activity`, and shows it on the OSD so you can see what
-- would be sent. A plugin only has to observe that one property.
--
-- Lookups use TVmaze, which needs no key but is TV only. Put a TMDB key in
-- script-opts/presence.conf to cover films as well.

local utils = require 'mp.utils'
local msg = require 'mp.msg'
local options = require 'mp.options'

local o = {
    -- start with presence already on
    enabled = false,
    -- TMDB api key. Empty falls back to TVmaze: no signup, but no films.
    tmdb_key = "",
    -- what to publish
    show_timestamps = true,
    show_episode = true,
    show_episode_title = true,
    -- name the director on films. Needs a TMDB key; TVmaze has no films.
    show_director = true,
    -- ask which title you meant when the match looks weak
    ask_when_unsure = true,
    -- a search hit below this scores as unsure (0-1)
    confident_score = 0.75,
    -- seconds to wait on the network
    timeout = 8,
    -- size of the picker text, out of 720
    osd_size = 20,
    -- Drive the prebuilt rich-presence.dll, which reads the media title. This
    -- is what makes Discord say the show instead of mpv without compiling
    -- anything. It also renames the mpv window, which is the price.
    drive_plugin = true,
}
options.read_options(o, "presence")

-- The TMDB key is a credential and this config is a public repo, so it lives
-- in presence-key.txt next to the config rather than in presence.conf. That
-- file is git-ignored; the conf stays safe to publish.
if o.tmdb_key == "" then
    local key_file = io.open(mp.command_native({"expand-path", "~~/presence-key.txt"}), "r")
    if key_file then
        o.tmdb_key = (key_file:read("*l") or ""):gsub("%s", "")
        key_file:close()
    end
end

local cache_path = mp.command_native({"expand-path", "~~/presence-cache.json"})

-- Bumped whenever a remembered entry gains a new field. Entries stamped with
-- an older number are looked up again rather than served stale, which is how
-- shows remembered before posters existed pick one up without you having to
-- know the cache file is there.
local CACHE_VERSION = 3

local enabled = false
local current = nil        -- the activity we last published
local picking = false
local choices, chosen = {}, 1
local overlay = mp.create_osd_overlay("ass-events")
overlay.res_y = 720

--------------------------------------------------------------------------
-- Filename parsing
--------------------------------------------------------------------------

-- Release tags that are never part of a title.
local JUNK = {
    "1080p", "720p", "480p", "2160p", "4k", "8bit", "10bit", "x264", "x265",
    "h264", "h265", "hevc", "avc", "aac", "ac3", "flac", "opus", "dts",
    "bluray", "bdrip", "brrip", "webrip", "web", "webdl", "hdtv", "dvdrip",
    "remux", "repack", "proper", "uncensored", "dual", "audio", "multi",
    "subs", "sub", "eng", "jpn", "hi10p", "ma", "5", "1", "ddp", "hdr",
}
local JUNK_SET = {}
for _, word in ipairs(JUNK) do JUNK_SET[word] = true end

local function tidy(name)
    name = name:gsub("[%._]", " ")
    -- drop anything in brackets: [group], (1080p), [CRC32]
    name = name:gsub("%b[]", " "):gsub("%b()", " ")
    name = name:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    -- cut the trailing run of release tags
    local words = {}
    for word in name:gmatch("%S+") do words[#words + 1] = word end
    while #words > 1 and JUNK_SET[words[#words]:lower()] do
        table.remove(words)
    end
    name = table.concat(words, " ")
    return (name:gsub("%s*[-–]%s*$", ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Returns a table: { title=, kind="tv"|"movie", season=, episode=, year= }
local function parse(filename, folder)
    local base = filename:gsub("%.[%a%d]+$", "")
    local out = { kind = "tv", season = 1 }

    -- Show.Name.S02E07 / Show Name - S02E07 / Show Name S2 E7
    local head, s, e = base:match("^(.-)[%s%._%-]*[Ss](%d%d?)[%s%._%-]*[Ee](%d%d?%d?)")
    if head then
        out.title, out.season, out.episode = tidy(head), tonumber(s), tonumber(e)
        return out
    end

    -- Show Name 1x05
    head, s, e = base:match("^(.-)[%s%._%-]+(%d%d?)[xX](%d%d?%d?)")
    if head then
        out.title, out.season, out.episode = tidy(head), tonumber(s), tonumber(e)
        return out
    end

    -- [Group] Show Name - 05 (1080p) [hash]   -- absolute numbering
    local stripped = base:gsub("^%s*%b[]%s*", "")
    head, e = stripped:match("^(.-)%s+%-%s+(%d%d?%d?)%s*[%(%[]")
    if not head then
        head, e = stripped:match("^(.-)%s+%-%s+(%d%d?%d?)%s*$")
    end
    if not head then
        head, e = stripped:match("^(.-)%s+[Ee][Pp]%.?%s*(%d%d?%d?)")
    end
    if head and head ~= "" then
        out.title, out.episode = tidy(head), tonumber(e)
        return out
    end

    -- Film.Name.2019 / Film Name (2019)
    --
    -- Titles containing a year are the trap here: "Blade Runner 2049 2017"
    -- and "1917". So prefer a year in brackets, else take the LAST one that
    -- still has text after it. A trailing number with nothing following is
    -- left alone, on the grounds that it is probably part of the name.
    local mhead, year = base:match("^(.-)[%(%[](19%d%d)[%)%]]")
    if not mhead then
        mhead, year = base:match("^(.-)[%(%[](20%d%d)[%)%]]")
    end
    if not mhead then
        local from = 1
        while true do
            local s, e, found = base:find("(%d%d%d%d)", from)
            if not s then break end
            local n = tonumber(found)
            local before = s > 1 and base:sub(s - 1, s - 1) or ""
            local after = base:sub(e + 1)
            if n >= 1900 and n <= 2099 and s > 1
               and before:match("[%s%._%-]") and after:match("%S") then
                mhead, year = base:sub(1, s - 1), found
            end
            from = e + 1
        end
    end
    if mhead and tidy(mhead) ~= "" then
        out.title, out.kind, out.year = tidy(mhead), "movie", tonumber(year)
        out.season = nil
        return out
    end

    -- Nothing matched. If the name is basically a number, the folder above
    -- is almost always the show.
    local bare = base:match("^%s*(%d%d?%d?)%s*$")
    if bare and folder and folder ~= "" then
        out.title, out.episode = tidy(folder), tonumber(bare)
        return out
    end

    out.title = tidy(base)
    out.kind = "movie"
    out.season = nil
    return out
end

--------------------------------------------------------------------------
-- Cache of "this folder is that show"
--------------------------------------------------------------------------

local cache = nil

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
    if not file then return end
    file:write(utils.format_json(cache))
    file:close()
end

--------------------------------------------------------------------------
-- Lookup providers
--------------------------------------------------------------------------

local function curl(url, done)
    mp.command_native_async({
        name = "subprocess", capture_stdout = true, playback_only = false,
        args = { "curl", "-s", "-m", tostring(o.timeout), url },
    }, function(ok, res)
        local body = ok and res and res.stdout or nil
        done(body and utils.parse_json(body) or nil)
    end)
end

local function urlencode(text)
    return (text:gsub("[^%w%-%._~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local tvmaze = {}

function tvmaze.search(title, _, done)
    curl("https://api.tvmaze.com/search/shows?q=" .. urlencode(title),
         function(json)
        local out = {}
        for _, hit in ipairs(json or {}) do
            local show = hit.show or {}
            out[#out + 1] = {
                id = show.id, name = show.name, kind = "tv",
                year = tonumber((show.premiered or ""):sub(1, 4)),
                score = hit.score,
                -- Discord accepts a plain URL as the large image, so the
                -- poster needs no uploading anywhere. medium is plenty at
                -- the size Discord draws it.
                image = (show.image or {}).medium or (show.image or {}).original,
            }
        end
        done(out)
    end)
end

function tvmaze.episode(id, season, number, done)
    curl(string.format(
            "https://api.tvmaze.com/shows/%s/episodebynumber?season=%d&number=%d",
            tostring(id), season or 1, number or 1),
         function(json) done(json and json.name or nil) end)
end

local tmdb = {}

function tmdb.search(title, kind, done)
    local path = (kind == "movie") and "movie" or "tv"
    curl(string.format(
            "https://api.themoviedb.org/3/search/%s?api_key=%s&query=%s",
            path, o.tmdb_key, urlencode(title)),
         function(json)
        local out = {}
        for i, hit in ipairs((json or {}).results or {}) do
            local date = hit.release_date or hit.first_air_date or ""
            out[#out + 1] = {
                id = hit.id, name = hit.title or hit.name, kind = kind,
                year = tonumber(date:sub(1, 4)),
                -- TMDB has no match score, so rank by position
                score = (i == 1) and 0.9 or 0.5,
                image = hit.poster_path
                    and ("https://image.tmdb.org/t/p/w500" .. hit.poster_path)
                    or nil,
            }
        end
        done(out)
    end)
end

function tmdb.director(id, done)
    curl(string.format("https://api.themoviedb.org/3/movie/%s/credits?api_key=%s",
                       tostring(id), o.tmdb_key),
         function(json)
        local names = {}
        for _, person in ipairs((json or {}).crew or {}) do
            if person.job == "Director" then names[#names + 1] = person.name end
        end
        -- a couple of films have two; more than that is a crowd, so stop there
        done(#names > 0 and table.concat(names, ", ", 1, math.min(#names, 2)) or nil)
    end)
end

function tmdb.episode(id, season, number, done)
    curl(string.format(
            "https://api.themoviedb.org/3/tv/%s/season/%d/episode/%d?api_key=%s",
            tostring(id), season or 1, number or 1, o.tmdb_key),
         function(json) done(json and json.name or nil) end)
end

local function provider()
    if o.tmdb_key ~= "" then return tmdb end
    return tvmaze
end

--------------------------------------------------------------------------
-- Publishing
--------------------------------------------------------------------------

-- The prebuilt plugin builds its presence from `media-title`, and
-- `force-media-title` is the writable override for that. So this is how the
-- show name reaches Discord without a custom build. Everything has to fit on
-- the one line, hence name and details joined together.
--
-- Putting it back is the awkward half: force-media-title cannot be cleared.
-- Setting it to "" reports success and changes nothing, and setting it to nil
-- errors. So the default title has to be rebuilt by hand, the same way mpv
-- would: the metadata title if the file has one, otherwise the filename.
local function real_title()
    local meta = mp.get_property("metadata/by-key/title")
    if meta and meta ~= "" then return meta end
    return mp.get_property("filename") or ""
end

local function drive_plugin(activity)
    if not o.drive_plugin then return end
    if activity then
        local line = activity.name
        if activity.details and activity.details ~= "" then
            line = line .. "  -  " .. activity.details
        end
        mp.set_property("force-media-title", line)
        mp.commandv("script-message-to", "rich_presence", "on")
    else
        mp.commandv("script-message-to", "rich_presence", "off")
        mp.set_property("force-media-title", real_title())
    end
end

local function publish(activity)
    current = activity
    mp.set_property_native("user-data/presence/activity", activity or {})
    drive_plugin(activity)
    if not activity then
        overlay.data = ""
        overlay:update()
        return
    end
    local lines = { activity.name }
    if activity.details and activity.details ~= "" then
        lines[#lines + 1] = activity.details
    end
    msg.info("presence: " .. utils.format_json(activity))
    mp.commandv("script-message-to", "osd_theme", "say", "Presence",
                activity.name, activity.details or "")
end

local function build(info, match, episode_title)
    local activity = { type = "watching", name = match and match.name or info.title }
    -- The year rides on the title, so the header reads "Watching House (2004)"
    -- for series and films alike.
    if match and match.year then
        activity.name = activity.name .. " (" .. match.year .. ")"
    end
    if match and match.image then
        activity.image = match.image
        activity.image_text = match.name
    end
    local bits = {}
    if info.kind == "tv" and o.show_episode and info.episode then
        if info.season then
            bits[#bits + 1] = string.format("S%d:E%d", info.season, info.episode)
        else
            bits[#bits + 1] = "Episode " .. info.episode
        end
    end
    if o.show_episode_title and episode_title then
        bits[#bits + 1] = episode_title
    end
    if info.kind == "movie" and match then
        -- `false` means we asked and the provider had nobody, so we do not ask
        -- again; nil means we have not looked yet.
        if o.show_director and match.director then
            bits[#bits + 1] = match.director
        end
    end
    activity.details = table.concat(bits, "  -  ")
    if o.show_timestamps then
        local pos = mp.get_property_number("time-pos") or 0
        local dur = mp.get_property_number("duration")
        activity.start = os.time() - math.floor(pos)
        if dur then activity["end"] = activity.start + math.floor(dur) end
    end
    return activity
end

local function finish(info, match)
    if info.kind == "tv" and info.episode and o.show_episode_title and match then
        provider().episode(match.id, info.season, info.episode, function(title)
            publish(build(info, match, title))
        end)
    elseif info.kind == "movie" and match and o.show_director
           and match.director == nil and provider().director then
        provider().director(match.id, function(name)
            -- Stored on the match, which is the same table the cache holds,
            -- so one lookup covers every later play of this film.
            match.director = name or false
            save_cache()
            publish(build(info, match, nil))
        end)
    else
        publish(build(info, match, nil))
    end
end

--------------------------------------------------------------------------
-- Picker
--------------------------------------------------------------------------

local function draw_picker()
    local font = mp.get_property("osd-font") or "sans-serif"
    local rows = { "{\\1c&HFFFFFF&}Which one are you watching?" }
    for i, c in ipairs(choices) do
        local label = c.name
        if c.year then label = label .. "  (" .. c.year .. ")" end
        rows[#rows + 1] = (i == chosen and "{\\1c&H4AD2FF&}>" or "{\\1c&HE0E0E0&}\\h")
                          .. "\\h" .. label:gsub("[{}\\]", "")
    end
    rows[#rows + 1] = "{\\1c&HA0A0A0&}Up/Down pick   Enter choose   Esc skip"
    overlay.data = string.format(
        "{\\an7\\pos(24,18)\\fs%d\\bord1.6\\shad0\\fn%s\\3c&H000000&}%s",
        o.osd_size, font, table.concat(rows, "\\N"))
    overlay:update()
end

local close_picker

local PICKER_KEYS = {
    { "DOWN",  "presence-down",  function() chosen = chosen % #choices + 1; draw_picker() end },
    { "UP",    "presence-up",    function() chosen = (chosen - 2) % #choices + 1; draw_picker() end },
    { "ENTER", "presence-take",  function() close_picker(true) end },
    { "ESC",   "presence-skip",  function() close_picker(false) end },
}

local pending_info = nil

close_picker = function(take)
    if not picking then return end
    picking = false
    for _, k in ipairs(PICKER_KEYS) do mp.remove_key_binding(k[2]) end
    overlay.data = ""
    overlay:update()
    if take and choices[chosen] and pending_info then
        local folder = mp.get_property("working-directory")
        local path = mp.get_property("path") or ""
        local dir = utils.split_path(path)
        choices[chosen].v = CACHE_VERSION
        load_cache()[dir or folder] = choices[chosen]
        save_cache()
        finish(pending_info, choices[chosen])
    end
end

local function open_picker(info, hits)
    choices, chosen, pending_info = hits, 1, info
    picking = true
    draw_picker()
    for _, k in ipairs(PICKER_KEYS) do
        mp.add_forced_key_binding(k[1], k[2], k[3])
    end
end

--------------------------------------------------------------------------
-- Driving it
--------------------------------------------------------------------------

local function identify(force_pick)
    if not enabled then return end
    local path = mp.get_property("path")
    if not path then return end
    local dir, file = utils.split_path(path)
    local folder = dir and dir:gsub("[\\/]+$", ""):match("([^\\/]+)$") or nil
    local info = parse(file, folder)

    -- A folder you have already answered for never asks again.
    local remembered = not force_pick and load_cache()[dir]
    if remembered and remembered.v ~= CACHE_VERSION then
        msg.verbose("re-looking up " .. tostring(remembered.name) .. ": stale entry")
        remembered = nil
    end
    if remembered then
        finish(info, remembered)
        return
    end

    if info.kind == "movie" and o.tmdb_key == "" then
        -- TVmaze has no films, so publish what the filename said.
        publish(build(info, nil, nil))
        return
    end

    provider().search(info.title, info.kind, function(hits)
        if not enabled then return end
        if not hits or #hits == 0 then
            publish(build(info, nil, nil))
            return
        end
        local top = hits[1]
        local unsure = (top.score or 0) < o.confident_score
        if force_pick or (unsure and o.ask_when_unsure) then
            local short = {}
            for i = 1, math.min(#hits, 6) do short[i] = hits[i] end
            open_picker(info, short)
        else
            top.v = CACHE_VERSION
            load_cache()[dir] = top
            save_cache()
            finish(info, top)
        end
    end)
end

local function set_enabled(state)
    enabled = state
    -- The plugin keys off this: while it exists, the script owns the presence
    -- and the plugin's own toggle stays out of the way.
    mp.set_property("user-data/presence/active", enabled and "yes" or "no")
    if enabled then
        mp.commandv("script-message-to", "osd_theme", "say", "Presence", "on", "")
        identify(false)
    else
        close_picker(false)
        publish(nil)
        mp.commandv("script-message-to", "osd_theme", "say", "Presence", "off", "")
    end
end

mp.add_key_binding(nil, "toggle", function() set_enabled(not enabled) end)
mp.add_key_binding(nil, "repick", function()
    if not enabled then set_enabled(true) return end
    identify(true)
end)

mp.register_event("file-loaded", function()
    if enabled then
        identify(false)
    elseif o.drive_plugin then
        -- a new file must not keep wearing the last one's name
        mp.set_property("force-media-title", real_title())
    end
end)

-- Keep the elapsed time honest after a seek.
mp.register_event("seek", function()
    if enabled and current and o.show_timestamps then
        local pos = mp.get_property_number("time-pos") or 0
        current.start = os.time() - math.floor(pos)
        mp.set_property_native("user-data/presence/activity", current)
    end
end)

if o.enabled then
    mp.register_event("file-loaded", function() set_enabled(true) end)
end

-- Announce ourselves at load, so the plugin knows a script is in charge even
-- before the first toggle.
mp.set_property("user-data/presence/active", "no")

-- Debug helper: script-message presence-parse "<filename>"
mp.register_script_message("presence-parse", function(name, folder)
    msg.info("parse(" .. name .. ") -> " .. utils.format_json(parse(name, folder)))
end)
