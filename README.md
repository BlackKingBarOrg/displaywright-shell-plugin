# Displaywright — per-display wallpapers and display arrangement for Omarchy

A different wallpaper on each display, with every fit mode Windows has, and an
overlay for dragging your displays into place.

Omarchy's built-in background renderer shows **one image on every display,
always cropped to fill**. This plugin draws on top of it, taking over only the
displays you give a picture to — with a fit for each, and a colour or a video
where you want one.

![the arrangement overlay: three displays dragged into place, each drawn with the wallpaper it is set to, and the picture strip along the bottom](preview.png)

## Install

```bash
omarchy plugin add https://github.com/BlackKingBarOrg/displaywright-shell-plugin.git --enable
```

That is the whole install on a machine that has not had this plugin before.
Nothing you can see on your displays changes: the stock renderer stays switched
on and keeps every one of them exactly as it was — along with the theme
background, the SUPER + CTRL + SPACE switcher and the palette that changes with
your theme. This plugin only draws on a display once you have given that display
a picture of its own. What it does add is a row in the Apps menu, which is how
you open it.

**Updating from an earlier version needs the shell restarted as well.** The one
running is still the one compiled before the update, so a file the plugin has
only just gained cannot execute — including the file that adds that row:

```bash
omarchy plugin update ai.bkblab.displaywright
omarchy restart shell
```

Needs Omarchy 4.x with `omarchy-shell`. Video wallpapers also need
`qt6-multimedia-ffmpeg`.

## Use

**Open it from the Apps menu: SUPER + ALT + SPACE, then type `Displays`.** That
is the arrangement window — drag your displays into place, set resolution,
refresh rate, scale and rotation, and give the selected display a wallpaper from
the strip along the bottom. Escape closes it. [What is in it](#the-arrangement-window)
is further down.

Installing puts that row in the Apps menu; updating from an earlier version
needs the shell restarted first, as above. For a keyboard shortcut and a row in
the Omarchy menu (SUPER + SPACE) as well, run this once — it finishes an update
on its own too:

```bash
~/.config/omarchy/plugins/ai.bkblab.displaywright/install-shortcuts.sh
```

**Double-click a display's background** to give just that display a wallpaper,
without opening anything. Omarchy's own picture picker comes up, and whatever
you choose becomes that display's wallpaper — that display only, the rest of
your desktop untouched. Do it again on the next screen to give it a different one.

It offers your theme's backgrounds, anything you have dropped in
`~/.config/omarchy/backgrounds/<theme>/`, and the folder the Displaywright app
keeps its pictures in. Right-click still opens the theme switcher, as always.

That is the whole of it for most people. Everything below is the file the picker
writes, for when you want a fit other than the default, a flat colour, a video,
or one picture spanned across every screen.

### The config file

What each display shows lives in one file:

```
~/.config/displaywright/wallpapers.json
```

It does not exist yet. Create it, and the renderer picks it up the moment you
save — no restart, no command to run.

### Setting a display by hand

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

Save it and both displays change. A display you leave out of `monitors` is not
touched at all — the stock renderer keeps drawing it, so you can take over one
screen and leave the rest of your desktop exactly as it was.

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

### If something is wrong with the file

A line the renderer cannot read is dropped rather than raised on — a mangled
entry costs you that wallpaper, never your desktop. `journalctl --user -u
omarchy-shell` (or wherever your shell logs) carries a `displaywright:` line
saying which one.

## The arrangement window

One overlay for where your displays are and what is on them: drag the outputs
into place, set resolution, refresh rate, scale and rotation, and pick a
wallpaper for whichever display is selected from the strip along the bottom.
Each display is drawn with the picture it is actually set to, so the
arrangement doubles as the preview.

**Add…** brings in a file from anywhere through the desktop file chooser and
copies it into `~/Pictures/Displaywright`, so the wallpaper survives you
emptying `~/Downloads`. A format Qt cannot draw — AVIF, WebP, JPEG XL — is
converted to PNG on the way in. Hovering a picture you added shows a **×** that
puts it in the trash and hands any display using it back to the theme; the
theme's own backgrounds have no ×, since they are not this tool's to delete.
**Follow theme** hands the selected display back on its own.

Applying a layout takes effect immediately and then asks to keep or revert with
a fifteen-second countdown that defaults to revert — a display that goes black
cannot lock you out. Keeping it writes the layout to
`~/.config/hypr/monitors.lua`, leaving everything outside its own block alone.

`install-shortcuts.sh`, from [Use](#use) above, writes the launcher entry itself
rather than waiting for the service to — which is what makes it finish an update
as well — and adds the Omarchy menu row and a key. It picks the first key nothing
else has claimed, asking Hyprland rather than reading your config, and prints
what it chose. If every candidate is taken it stops and tells you — it will
never unbind something of yours to make room.
Every edit goes between markers, so running it again changes nothing, it reports
only what actually landed, and `--remove` takes out exactly what it added.

A plugin cannot do this for itself: Omarchy's manifest has no field for a
keybinding or a menu row, and `omarchy plugin add` deliberately runs nothing
from inside a plugin. Hence a command you run rather than an install step.

This half needs nothing but Hyprland — it talks to `hyprctl` directly and does
not care whether the wallpaper renderer is doing anything.

## Source

**https://github.com/BlackKingBarOrg/displaywright**

This repository is generated from that one's `plugin/` directory, so that
`manifest.json` sits at a repository root the way `omarchy plugin add` needs.
File issues against the source repository.

## Remove

```bash
~/.config/omarchy/plugins/ai.bkblab.displaywright/install-shortcuts.sh --remove
omarchy plugin remove ai.bkblab.displaywright
```

Run the first line only if you ran the installer; it takes the keybinding, the
menu row and the launcher entry back out. Removing the plugin on its own clears
the launcher entry as well — `omarchy plugin remove` deletes the folder before it
tells the shell, and that is how the service knows a teardown is a removal and
not one of the reloads it has to survive. Nothing else to put back: the stock
renderer was never switched off.

## Issues

This repository is generated from `plugin/` in the project above, so bug reports
and pull requests belong there.

## License

MIT — see [LICENSE](LICENSE).
