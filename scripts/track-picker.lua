-- track-picker.lua
--
-- The audio + subtitle track chooser that used to be track-menu.lua, rebuilt
-- to draw through uosc so it matches the rest of the interface instead of
-- being its own thing. Bound to TAB.
--
-- uosc renders it: we hand it a menu over `open-menu` and it does the rest,
-- which is why the look follows the theme automatically. An item's `value` is
-- an mpv command array, run when the item is picked.

local utils = require 'mp.utils'

local function describe(track)
    local bits = {}
    bits[#bits + 1] = track.lang or "--"
    if track.title then bits[#bits + 1] = track.title end
    if track.forced then bits[#bits + 1] = "forced" end
    if track.external then bits[#bits + 1] = "external" end
    return table.concat(bits, "  ")
end

-- Codec and channels say nothing about which track you want, so they stay in
-- the hint column rather than the title.
local function hint(track)
    local bits = {}
    if track.codec then bits[#bits + 1] = track.codec end
    local channels = track["audio-channels"] or track["demux-channel-count"]
    if track.type == "audio" and channels then bits[#bits + 1] = channels .. "ch" end
    return table.concat(bits, ", ")
end

local function section(items, tracks, kind, prop, off_label)
    local current = mp.get_property(prop)
    items[#items + 1] = {
        title = (kind == "audio") and "Audio" or "Subtitles",
        bold = true, selectable = false, muted = true,
    }
    items[#items + 1] = {
        title = off_label,
        value = { "set", prop, "no" },
        active = (current == "no"),
        italic = true,
    }
    local found = false
    for _, track in ipairs(tracks) do
        if track.type == kind then
            found = true
            items[#items + 1] = {
                title = describe(track),
                hint = hint(track),
                value = { "set", prop, tostring(track.id) },
                active = (tostring(track.id) == current),
            }
        end
    end
    if not found then
        items[#items].selectable = false
    end
    items[#items].separator = true
end

local function open()
    local tracks = mp.get_property_native("track-list") or {}
    local items = {}
    section(items, tracks, "audio", "aid", "No audio")
    section(items, tracks, "sub", "sid", "Subtitles off")
    items[#items].separator = false

    mp.commandv("script-message-to", "uosc", "open-menu", utils.format_json({
        type = "track-picker",
        title = "Tracks",
        items = items,
        -- Stay open so audio and subtitles can both be set in one visit, the
        -- way the old menu did.
        keep_open = true,
        anchor_at_cursor = true,
    }))
end

mp.add_key_binding(nil, "open", open)
