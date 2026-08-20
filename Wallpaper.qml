// Displaywright's renderer: one wallpaper surface per output.
//
// This plugin sits *on top of* omarchy.background rather than replacing it.
// Its surface is transparent on every output it has no opinion about, so the
// stock renderer shows through and keeps doing its jobs -- the `background` IPC
// target, the SUPER + CTRL + SPACE switcher, and the palette that rides along
// with a theme transition. A fresh install therefore changes nothing at all
// until you pin a wallpaper to a display.
//
// Two surfaces on WlrLayer.Background have no stacking order defined by
// Wayland; the one created last is drawn on top. Omarchy's plugin registry
// merges first-party manifests before third-party ones and mounts services in
// that order, so a plugin like this one is always created after
// omarchy.background and lands above it. That is an implementation detail
// rather than a guarantee -- but the failure mode if it ever changed is a
// pinned wallpaper hidden behind the theme's, not a black desktop.

import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  // Injected by the shell host when it instantiates a service plugin.
  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")
  readonly property string configPath: configHome + "/displaywright/wallpapers.json"

  // ---------------------------------------------------------------- config

  // { outputName: source }. An absent output is left to omarchy.background.
  property var monitorSources: ({})
  // One source stretched over every output; wins over monitorSources.
  property var spanSource: null
  property int configRevision: 0

  function sourceFor(name) {
    if (spanSource) return spanSource
    var found = monitorSources[String(name)]
    return found ? found : null
  }

  function parseConfig(text) {
    var next = ({})
    var span = null
    var raw = String(text || "").trim()
    if (raw.length > 0) {
      try {
        var parsed = JSON.parse(raw)
        if (parsed && typeof parsed === "object") {
          if (parsed.monitors && typeof parsed.monitors === "object") {
            for (var key in parsed.monitors) {
              var entry = parsed.monitors[key]
              if (entry && typeof entry === "object") next[String(key)] = entry
            }
          }
          if (parsed.span && typeof parsed.span === "object") span = parsed.span
        }
      } catch (e) {
        // A half-written or hand-mangled config should cost the user their
        // custom wallpapers for a moment, not their desktop: fall through with
        // empty values and every output goes back to the theme background.
        console.warn("displaywright: could not parse " + root.configPath + ": " + e)
      }
    }
    monitorSources = next
    spanSource = span
    configRevision += 1
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    // `text()` is stale inside onFileChanged, so both the first load and every
    // later change are routed through reload() -> onLoaded.
    onFileChanged: reload()
    onLoaded: root.parseConfig(text())
    onLoadFailed: root.parseConfig("")
  }

  // The config file usually does not exist yet. FileView cannot watch a path
  // that is absent, so watch the directory that will hold it and re-arm once
  // it appears.
  FileView {
    id: configDirProbe
    path: root.configHome + "/displaywright"
    watchChanges: true
    printErrors: false
    onFileChanged: configFile.reload()
  }

  // ------------------------------------------------------ span geometry
  //
  // Recomputed here rather than stored in the config so that moving a display
  // re-cuts a spanned image immediately, whether or not the GUI is running.

  property var spanBox: null

  function refreshSpanBox() {
    var screens = Quickshell.screens || []
    if (screens.length === 0) {
      spanBox = null
      return
    }
    var left = Infinity, top = Infinity, right = -Infinity, bottom = -Infinity
    for (var i = 0; i < screens.length; i++) {
      var s = screens[i]
      left = Math.min(left, s.x)
      top = Math.min(top, s.y)
      right = Math.max(right, s.x + s.width)
      bottom = Math.max(bottom, s.y + s.height)
    }
    spanBox = { x: left, y: top, w: right - left, h: bottom - top }
  }

  onSpanSourceChanged: refreshSpanBox()
  Connections {
    target: Quickshell
    function onScreensChanged() { root.refreshSpanBox() }
  }

  // ------------------------------------------------------------------- IPC

  // Only displaywright's own target. `background` belongs to omarchy.background
  // again, along with everything a theme switch needs.
  IpcHandler {
    target: "displaywright"

    function reload(): string {
      configFile.reload()
      root.refreshSpanBox()
      return "ok"
    }

    function status(): string {
      var out = []
      var screens = Quickshell.screens || []
      for (var i = 0; i < screens.length; i++) {
        var name = screens[i].name
        var src = root.sourceFor(name)
        if (!src) {
          out.push(name + "\ttheme\t-\t-")
          continue
        }
        var what = src.kind === "color" ? String(src.color || "") : String(src.path || "")
        out.push(name + "\t" + (root.spanSource ? "span" : "pinned")
                 + "\t" + String(src.fit || "fill") + "\t" + what)
      }
      return out.join("\n")
    }

    function ping(): string {
      return "ok"
    }
  }

  // --------------------------------------------------------------- surfaces

  Component.onCompleted: refreshSpanBox()

  Variants {
    model: Quickshell.screens

    Surface {
      controller: root
    }
  }
}
