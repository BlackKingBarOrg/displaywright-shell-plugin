# Displaywright — per-display wallpapers for Omarchy

A different wallpaper on each display, with every fit mode Windows has.

Omarchy's built-in background renderer shows **one image on every display,
always cropped to fill**. This plugin replaces it with one that takes a picture
per display, a fit for each, and a colour or a video where you want one.

![each display showing its own wallpaper, at its real position, size and rotation](preview.png)

## Install

```bash
omarchy plugin add https://github.com/BlackKingBarOrg/displaywright-shell-plugin.git --enable
omarchy plugin disable omarchy.background
```

**Both lines.** `omarchy plugin add` will not disable the built-in renderer for
you, and two plugins drawing on `WlrLayer.Background` means the wallpaper you
get is a coin flip per session. Theme switching keeps working — this plugin
implements the whole `background` IPC target, palette transition included.

Needs Omarchy 4.x with `omarchy-shell`. Video wallpapers also need
`qt6-multimedia-ffmpeg`.

## Use

Nothing changes until you ask for something. Every display keeps following the
Omarchy theme background, and **SUPER + CTRL + SPACE** still switches it for all
of them — so a fresh install looks and behaves exactly like stock Omarchy.

What you choose per display lives in one file:

```
~/.config/displaywright/wallpapers.json
```

It does not exist yet. Create it, and the renderer picks it up the moment you
save — no restart, no command to run.

### Give each display its own wallpaper

First, the names of your displays:

```bash
hyprctl monitors -j | jq -r '.[].name'      # e.g. eDP-1, DP-1
```

Then write them in, with a picture for each:

```json
{
  "version": 1,
  "monitors": {
    "eDP-1": { "kind": "image", "path": "/home/you/Pictures/laptop.jpg", "fit": "fill" },
    "DP-1":  { "kind": "image", "path": "/home/you/Pictures/desk.png",  "fit": "fill" }
  }
}
```

Save it and both displays change. A display you leave out of `monitors` keeps
following the theme, so you can take over one screen and leave the rest alone.

### Choose how a picture fills the screen

Change `"fit"` on any entry:

| `fit` | Windows | What it does |
|---|---|---|
| `fill` | Fill | Scales until the display is covered, crops the overflow. The default. |
| `fit` | Fit | Scales until the whole picture is visible, `backdrop` in the bars. |
| `stretch` | Stretch | Ignores the aspect ratio and distorts to fit exactly. |
| `tile` | Tile | Repeats the file at its own resolution from the top-left corner. |
| `center` | Center | Draws the file at its own resolution in the middle, `backdrop` around it. |

`fit` and `center` leave bare space, so they take a colour behind them:

```json
"DP-1": { "kind": "image", "path": "/home/you/art.png", "fit": "center",
          "backdrop": "#101820" }
```

Center and Tile are measured in **device pixels**, so a picture is the size it
would be on Windows even on a scaled display.

### A flat colour instead of a picture

```json
"DP-1": { "kind": "color", "color": "#101820" }
```

### One picture across every display

Use `span` instead of listing monitors. It wins over anything in `monitors`:

```json
{ "version": 1, "monitors": {},
  "span": { "kind": "image", "path": "/home/you/Pictures/ultrawide.jpg" } }
```

The renderer cuts it from your live display list, so moving a display re-cuts
the picture on its own. Displays that are not flush leave part of the picture in
the gap between them, where nothing can draw it.

### A video

```json
"DP-1": { "kind": "video", "path": "/home/you/Videos/loop.mp4" }
```

It loops, stays muted, and stops decoding under a fullscreen window. This one
type-checks clean but has not been run on hardware yet — treat it as untested.

### Clicking the desktop

Double-click a display's background to open the picker for whatever governs it:
Omarchy's own background switcher where the display still follows the theme, and
the Displaywright window where this plugin has taken over. Right-click always
reaches the theme switcher.

### If something is wrong with the file

A line the renderer cannot read is dropped rather than raised on — a mangled
entry costs you that wallpaper, never your desktop. `journalctl --user -u
omarchy-shell` (or wherever your shell logs) carries a `displaywright:` line
saying which one.

## Prefer clicking to editing JSON?

The window that drives all of this — a picture library, a live preview of every
fit, and a display arrangement editor — is a separate project:

**https://github.com/BlackKingBarOrg/displaywright**

It writes the same file, and installs this same renderer for you.

## Remove

```bash
omarchy plugin remove ai.bkblab.displaywright
omarchy plugin enable omarchy.background
```

## Issues

This repository is generated from `plugin/` in the project above, so bug reports
and pull requests belong there.

## License

MIT — see [LICENSE](LICENSE).
