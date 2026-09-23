# mpv config

My personal config - switchable subtitle styles, a subtitle dictionary, a thin seek bar, a track picker.

## Install

Unzip [the latest release](https://github.com/virakie/mpv/releases) into your
mpv config folder and that is it.

| OS | Folder |
| --- | --- |
| Windows | `%APPDATA%\mpv` |
| Linux / macOS | `~/.config/mpv` |

Everything works out of the box. Two optional extras:

- **Film posters in the Discord status** need a free
  [TMDB key](https://www.themoviedb.org/settings/api). Put it on one line in a
  file called `presence-key.txt` next to `mpv.conf`. Without it, TV still works
  through TVmaze, which has no films.
- **Screenshots** land in a `screenshots` folder inside the config. Change
  `screenshot-dir` in `mpv.conf` if you want them elsewhere.

The Discord plugin is Windows-only. The rest works anywhere.

To build the zip yourself: `powershell -ExecutionPolicy Bypass -File package.ps1`

---

## Subtitles

Two lists you flip through separately: the font, and the style.

| Key | Does |
| --- | --- |
| `Alt` + `←` `→` | font |
| `Alt` + `↑` `↓` | style |
| `Alt` + `i` | show what is on |
| `Alt` + `a` | adjust panel |
| `g` / `f` | bigger / smaller |
| `t` / `r` | up / down |

Styles: Fansub, Clean, Box, Crunchyroll, Netflix, Retro, Big, Compact, Native.

Crunchyroll and Netflix copy how those services really draw subtitles. Native
turns styling off, so anime signs and karaoke look how the subber made them.

Fonts: Inter, Netflix Sans, Open Sans, Atkinson Hyperlegible, Tiresias,
Trebuchet, JetBrains Mono.

Fansub is the default. It comes back every time subs turn on. To change the
default, move a name to the front of `styles=` in `script-opts/substyle.conf`.

### Adjust panel — `Alt` + `a`

| Key | Does |
| --- | --- |
| `←` `→` | change value |
| `↑` `↓` | pick setting |
| `r` | undo |
| `s` | save into this preset |
| `w` | save as new preset |
| `x` | delete a saved preset |
| `Esc` | close |

Saved presets show up in the `Alt` + `↑` `↓` list next launch.

### Discord presence — `Alt` + `p`

Toggle it on and Discord shows "Watching a Series" or "Watching a Film", the
title in bold, then `(2004) - S7:E2` or `(1996) - Danny Boyle`, then the
progress bar. Every line is a template in `script-opts/presence.conf` -
placeholders like `{title}` `{year}` `{season}` `{episode}` `{episode_title}`
`{director}` - so what shows is yours to rearrange. Episode titles are off by
default because they are spoilers; `show_episode_title=yes` turns them on. It reads
the filename, asks TVmaze what the show is, and asks you only when unsure.
`Alt` + `o` re-picks if it guessed wrong. Your answer is remembered
per folder, so a season only asks once.

The plugin that talks to Discord is bundled (`scripts/rich-presence.dll`, from
goodtrailer/mpv-rich-presence, AGPL, licences in `licenses/`). Discord has to be
running. Your mpv window title changes to the show name while it is on.

### Dictionary — `d`

Press `d` on a word you don't know. Video pauses. The line comes back with every
word clickable, hardest word already looked up. Click another word to look it up
instead. `Esc` resumes.

Definitions are saved, so looked-up words work offline after. Text subs only.

There is a full offline dictionary too: 147k words from WordNet in
`subdict-words.tsv`. The online dictionary is still tried first, since it has
pronunciations and more modern wording, but if it is slow or you are on a
plane the local copy answers instead. `subdict-morph.tsv` maps inflected forms
onto their base, so "scurried" finds "scurry" with no network.

---

## Everything else

| Key | Does |
| --- | --- |
| `Right-click` | play / pause |
| `Middle-click` | main menu, opens where the pointer is |
| `Menu` | main menu, centred |
| `Tab` | audio + subtitle track picker (Tab again closes it) |
| `Alt` + `c` | chapters: jump, add, rename, delete |
| `Ctrl` + `Tab` | show or hide the whole interface |
| `←` `→` | seek 2s |
| `↑` `↓` | volume |
| `=` / `-` | speed |
| `[` `]` | previous / next in the playlist |
| `p` | playlist menu (`p` again closes it) |
| `c` | crop |
| `e` / `E` | GIF start / end, then `Ctrl` + `e` to make |
| `W` | webm encoder |
| `Ctrl` + `Shift` + `C` / `Ctrl` + `v` | copy / paste path or URL |
| `s` | screenshot to file |
| `Ctrl` + `c` | copy the frame to the clipboard, subtitles included |
| `Ctrl` + `Shift` + `c` | copy the frame without subtitles |
| `?` or `Ctrl` + `Alt` + `k` | every shortcut, grouped by what it does; type to filter |
| `F4` | list every subtitle line, filter and jump to one |
| `Ctrl` + `←` `→` `↓` | previous / next / replay subtitle line |
| `Ctrl` + `r` | refresh: reload this file at the same spot |
| `F11` | auto-skip opening and ending chapters on/off |
| `Alt` + `F5` | reset zoom, speed, delays and colours |

Drag the seek bar to skim. Drag anywhere else to move the window.

---

## Gotchas

- Every video loops. Delete `loop=yes` from `mpv.conf` to stop it.
- `w` `o` `p` `j` `l` `v` `a` do nothing on purpose. See bottom of `input.conf`.
- The seek bar and menus are uosc. It stays hidden until you move the mouse,
  and the control buttons are off - the right-click menu does that job.
- `minimal.lua`, `track-menu.lua` and the sub-select pair sit in `scripts/.unused`.
- English audio auto-picked when there are several tracks.
- Window opens at half your screen size.

---

## Files

| File | Is |
| --- | --- |
| `mpv.conf` | settings, subtitle presets at the bottom |
| `input.conf` | keybinds |
| `scripts/substyle.lua` | style switching + adjust panel |
| `scripts/subdict.lua` | dictionary |
| `scripts/presence.lua` | works out what you are watching, for Discord |
| `scripts/cheatsheet.lua` | the `?` shortcut sheet |
| `scripts/keybind-visualizer.lua` | the keyboard map (Tools menu) |
| `scripts/sub-seek.lua` | the `F4` subtitle line list |
| `scripts/osd-theme.lua` | one look for on-screen messages |
| `scripts/track-menu.lua` | `Tab` picker |
| `scripts/uosc/` | seek bar, menus, the whole interface |
| `scripts/uosc-menu.lua` | builds the menu from `#!` comments in `input.conf` |
| `scripts/track-picker.lua` | the `Tab` track chooser, drawn by uosc |
| `scripts/thumbfast.lua` | seek bar thumbnails |
| `scripts/autoload.lua` | queues the rest of the folder |
| `scripts/gifgen.lua`, `webm.lua` | clip exporting |
| `script-opts/` | per-script settings |
| `fonts/` | loaded without installing |

Fonts here: Inter, Open Sans, Atkinson Hyperlegible, Tiresias, JetBrains Mono.
Trebuchet and Verdana come with Windows. Netflix Sans you need yourself.

Presets saved with `w` go to `substyle-custom.conf`.

## Credits

Several scripts come from [v-amorim/moonlight-mpv](https://github.com/v-amorim/moonlight-mpv):
`keybind-visualizer`, `sub-seek`, `osd-theme`, `pause-indicator`, `restart-mpv`,
`reset-all`, `skip-chapters`, and the three menu scripts, along with its uosc
theme and the cascade-menu patch.

`cheatsheet.lua` is a Lua port of [ento/mpv-cheatsheet](https://github.com/ento/mpv-cheatsheet)
(MIT, © 2019 Marica Odagaki), rebuilt to read the live bindings.

The interface itself is [uosc](https://github.com/tomasklaen/uosc) 5.13.0, with
that patch applied so submenus cascade to the right of the pointer.

Two local edits live in `scripts/uosc/elements/Menu.lua` and will be lost if
uosc is updated: the submenu hover delay is 0.05s rather than 0.2s, and the
"cursor has settled" tolerance is 24px rather than 8px. Upstream's values made
submenus feel unresponsive to a slowly moving pointer.

The menu is built from the `#!` comments at the bottom of `input.conf`. Those
lines start with `#` so they bind nothing - they exist only to place an entry.

The keyboard map reads the `#` comment at the end of each `input.conf` line, so
describing a binding there is what makes it readable on the map.

`scripts/rich-presence.dll` is built from
[goodtrailer/mpv-rich-presence](https://github.com/goodtrailer/mpv-rich-presence),
modified to take the show name from `presence.lua`. It is AGPL-3.0, so the
modified source has to be published alongside the binary - see `licenses/`.
