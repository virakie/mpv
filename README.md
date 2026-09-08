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

Toggle it on and Discord shows "Watching <show name>" instead of mpv. It reads
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

---

## Everything else

| Key | Does |
| --- | --- |
| `Tab` | audio + subtitle track picker |
| `←` `→` | seek 2s |
| `↑` `↓` | volume |
| `=` / `-` | speed |
| `[` `]` | playlist |
| `c` | crop |
| `e` / `E` | GIF start / end, then `Ctrl` + `e` to make |
| `W` | webm encoder |
| `Ctrl` + `c` / `v` | copy / paste path or URL |
| `s` | screenshot |

Drag the seek bar to skim. Drag anywhere else to move the window.

---

## Gotchas

- Every video loops. Delete `loop=yes` from `mpv.conf` to stop it.
- `w` `o` `p` `j` `l` `v` `a` do nothing on purpose. See bottom of `input.conf`.
- No default seek bar. `minimal.lua` draws a thin one.
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
| `scripts/track-menu.lua` | `Tab` picker |
| `scripts/minimal.lua` | seek bar |
| `scripts/thumbfast.lua` | seek bar thumbnails |
| `scripts/autoload.lua` | queues the rest of the folder |
| `scripts/gifgen.lua`, `webm.lua` | clip exporting |
| `script-opts/` | per-script settings |
| `fonts/` | loaded without installing |

Fonts here: Inter, Open Sans, Atkinson Hyperlegible, Tiresias, JetBrains Mono.
Trebuchet and Verdana come with Windows. Netflix Sans you need yourself.

Presets saved with `w` go to `substyle-custom.conf`.

## Credits

`scripts/rich-presence.dll` is built from
[goodtrailer/mpv-rich-presence](https://github.com/goodtrailer/mpv-rich-presence),
modified to take the show name from `presence.lua`. It is AGPL-3.0, so the
modified source has to be published alongside the binary - see `licenses/`.
