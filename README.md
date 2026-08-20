# Displaywright — per-display wallpapers for Omarchy

A different wallpaper on each display, with every fit mode Windows has.

Omarchy's built-in background renderer shows **one image on every display,
always cropped to fill**. This plugin replaces it with one that takes a picture
per display, a fit for each, and a colour or video where you want one.

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

Needs Omarchy 4.x with `omarchy-shell`, plus `qt6-multimedia-ffmpeg` if you want
video wallpapers.

### You probably want the window too

This repository is the **renderer only** — QML that runs inside `omarchy-shell`.
It has no window and installs no command. To pick wallpapers by clicking rather
than by editing JSON, install the app:

```bash
git clone https://github.com/BlackKingBarOrg/displaywright
cd displaywright && make install
displaywright
```

It gives you a picture library, live previews of every fit, and a display
arrangement editor on a second page. `make plugin` there installs this same
renderer and disables `omarchy.background` in one step, so if you start from the
app you can skip the two commands above.

## Use

Everything is one file: `~/.config/displaywright/wallpapers.json`. The renderer
watches it, so edits take effect immediately.

```json
{
  "version": 1,
  "monitors": {
    "eDP-1": { "kind": "image", "path": "/home/you/a.jpg", "fit": "fill" },
    "DP-1":  { "kind": "image", "path": "/home/you/b.png", "fit": "center",
               "backdrop": "#101820" },
    "DP-2":  { "kind": "color", "color": "#101820" }
  },
  "span": null
}
```

A display that is not listed keeps following the Omarchy theme background, so a
fresh install looks exactly like stock Omarchy. Run `hyprctl monitors -j` if you
are not sure what your outputs are called.

| `fit` | Windows | What it does |
|---|---|---|
| `fill` | Fill | Scales until the display is covered, crops the overflow. The default. |
| `fit` | Fit | Scales until the whole picture is visible, `backdrop` in the bars. |
| `stretch` | Stretch | Ignores the aspect ratio and distorts to fit exactly. |
| `tile` | Tile | Repeats the file at its own resolution from the top-left corner. |
| `center` | Center | Draws the file at its own resolution in the middle, `backdrop` around it. |

Center and Tile are measured in **device pixels**, so they look the way they do
on Windows even on a scaled display.

**One picture across every display** — set `span` instead of listing monitors,
and it wins over anything in `monitors`:

```json
{ "version": 1, "monitors": {}, "span": { "kind": "image", "path": "/home/you/wide.jpg" } }
```

The renderer cuts it from your live display list, so moving a display re-cuts
the picture on its own.

**`kind`** is `image`, `color` (with `"color": "#101820"`) or `video`. Video
loops muted and pauses under a fullscreen window; it type-checks clean but has
not been run on hardware yet, so treat it as untested.

**Double-clicking the desktop** opens the picker for whatever governs that
display — the app where this plugin decides the picture, Omarchy's own switcher
where the theme still does. Right-click always reaches the theme switcher.

Anything unparseable in the file is dropped rather than raised on: a mangled
entry costs you that wallpaper, never your desktop.

## Remove

```bash
omarchy plugin remove ai.bkblab.displaywright
omarchy plugin enable omarchy.background
```

## Issues

This repository is generated from `plugin/` in
[BlackKingBarOrg/displaywright](https://github.com/BlackKingBarOrg/displaywright),
so bug reports and pull requests belong there.

## License

MIT — see [LICENSE](LICENSE).
