# mpv config

My mpv setup. Custom subtitle styling, a small seek bar instead of the default
OSC, a track picker, and a subtitle dictionary.

## Install

Copy everything into `%APPDATA%\mpv` (Windows) and it just works.

```powershell
robocopy "path\to\this\repo" "$env:APPDATA\mpv" /E /XD .git
```

To try it without touching your real config:

```powershell
& "C:\Program Files\mpv\mpv.exe" "--config-dir=path\to\this\repo" "video.mkv"
```

---

## Subtitles

The main thing this config does. Subtitle looks are saved as **presets**, split
into two lists you flip through separately: the **font**, and the **style**
(size, position, outline, shadow).

| Key | What it does |
| --- | --- |
| `Alt` + `←` `→` | previous / next **font** |
| `Alt` + `↑` `↓` | previous / next **style** |
| `Alt` + `i` | show which font and style are on right now |
| `Alt` + `a` | open the adjust panel (see below) |
| `g` / `f` | subtitles bigger / smaller |
| `t` / `r` | subtitles up / down |

**Styles:** Fansub, Clean, Box, Crunchyroll, Netflix, Retro, Big, Compact, Native.
Crunchyroll and Netflix copy how those services actually draw their subtitles.
Native turns the styling off so anime signs and karaoke look how the subber
intended.

**Fonts:** Inter, Netflix Sans, Open Sans, Atkinson Hyperlegible, Tiresias,
Trebuchet, JetBrains Mono.

Fansub is the default, and it comes back every time subtitles turn on, so every
video starts the same. To use a different one as your default, move its name to
the front of the `styles=` line in `script-opts/substyle.conf`.

### Adjust panel — `Alt` + `a`

Tweak the subtitles live and watch them change.

| Key | What it does |
| --- | --- |
| `←` `→` | change the value |
| `↑` `↓` | pick a different setting |
| `r` | undo, back to the preset |
| `s` | save into the preset you are on |
| `w` | save as a brand new preset |
| `x` | delete a preset you saved with `w` |
| `Esc` | close |

Presets you save turn up in the `Alt` + `↑` `↓` list next time you open mpv.

### Dictionary — `d`

See a word you don't know? Press `d`. The video pauses, the subtitle line comes
back with every word clickable, and the hardest-looking word is already looked
up. Click or arrow onto any other word to look that one up. `Esc` resumes.

Definitions are saved, so a word you have looked up once works offline forever
after. Text subtitles only — Blu-ray picture subs have no text to read.

---

## Everything else

| Key | What it does |
| --- | --- |
| `Tab` | audio + subtitle track picker (click a track, or arrow to it) |
| `←` `→` | seek 2 seconds |
| `↑` `↓` | volume by 1 |
| `=` / `-` | speed up / slow down |
| `[` `]` | previous / next in playlist |
| `c` | crop |
| `e` / `E` | mark GIF start / end, then `Ctrl` + `e` to make it |
| `W` | webm encoder |
| `Ctrl` + `c` / `v` | copy / paste a video path or URL |
| `s` | screenshot (goes to `E:\Virak\Pictures\Screenshots`) |

**Mouse:** drag the seek bar to skim through the video. Drag anywhere else to
move the window.

---

## Things that might surprise you

- **Every video loops.** `loop=yes` in `mpv.conf` — delete that line if you
  don't want it.
- **`w` `o` `p` `j` `l` `v` `a` do nothing** on purpose, so they can't be hit by
  accident. They are listed at the bottom of `input.conf`.
- **No default seek bar.** `minimal.lua` draws a thin one at the bottom instead.
- **English audio is picked automatically** when a video has more than one track
  (`alang=en,eng`).
- The window opens at **half your screen size** (`autofit=50%`).

---

## What's in here

| File | What it is |
| --- | --- |
| `mpv.conf` | settings, and the subtitle presets at the bottom |
| `input.conf` | keybinds |
| `scripts/substyle.lua` | subtitle preset switching + the adjust panel |
| `scripts/subdict.lua` | the subtitle dictionary |
| `scripts/track-menu.lua` | the `Tab` track picker |
| `scripts/minimal.lua` | the seek bar |
| `scripts/thumbfast.lua` | thumbnail previews on the seek bar |
| `scripts/autoload.lua` | queues up the rest of the folder automatically |
| `scripts/gifgen.lua`, `webm.lua` | clip exporting |
| `script-opts/` | settings for each script |
| `fonts/` | subtitle fonts, loaded without installing them |

Presets you save with `w` land in `substyle-custom.conf`.
