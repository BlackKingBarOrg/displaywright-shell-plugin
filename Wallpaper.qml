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
import qs.Commons
import "lib/geometry.mjs" as Geo
import "lib/snapping.mjs" as Snap
import "lib/luawriter.mjs" as Lua
import "lib/applyflow.mjs" as Flow

Item {
  id: root

  // Injected by the shell host when it instantiates a service plugin.
  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  // The arrangement overlay is mounted through the shell's Loader, and a
  // component loaded that way resolves no imports of its own -- neither a
  // script nor qs.Commons. A service is created synchronously and can, so this
  // is where they are imported, and the overlay reads them off `service`.
  //
  // Everything reachable through here has to stay inside the JavaScript Qt's
  // QML engine accepts. Object spread does not qualify: it takes this service
  // down, and with it every wallpaper on the desktop.
  readonly property var geo: Geo
  readonly property var snap: Snap
  readonly property var lua: Lua
  readonly property var flow: Flow

  //: Omarchy installs no launcher entry for a plugin, so the service writes
  //: one. Without it the overlay has no name to search for and no icon to
  //: click, which is indistinguishable from not being installed.
  //: A plain child rather than a typed property: resolving a sibling .qml as
  //: a property *type* is stricter than instantiating it, and this file is
  //: the one whose failure takes every wallpaper on the desktop with it.
  LauncherEntry { manifest: root.manifest }

  //: A plain-value snapshot of the shell theme, for the same reason.
  readonly property var palette: ({
    background: Color.background, text: Color.text, muted: Color.muted,
    placeholder: Color.placeholder, border: Color.border, active: Color.active,
    accent: Color.accent, scrim: Color.scrim,
    selectedBackground: Color.selectedBackground, selectedBorder: Color.selectedBorder,
    selectedText: Color.selectedText, unselectedBorder: Color.unselectedBorder,
    textError: Color.textError, countdown: Color.countdown,
  })

  readonly property string home: Quickshell.env("HOME")
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")
  readonly property string configPath: configHome + "/displaywright/wallpapers.json"

  // Where this plugin was loaded from. The shell stamps it into the manifest;
  // hardcoding an install path would break a symlinked checkout and anyone who
  // installed by hand somewhere else.
  readonly property string pluginDir: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir) : ""

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

  //: This file is user-writable, and FileView reads whatever the path resolves
  //: to: no size limit, no way to refuse a device, no no-follow. It reads into
  //: the shell's own process, so a wallpapers.json of a few gigabytes -- or one
  //: symlinked at /dev/zero -- would take the whole desktop down rather than
  //: this plugin. read-config.sh bounds it: regular files only, and never more
  //: than its cap.
  readonly property string configDir: configHome + "/displaywright"

  Process {
    id: configReader
    command: root.pluginDir ? [root.pluginDir + "/read-config.sh", root.configPath] : ["true"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseConfig(text)
    }
  }

  function reloadConfig() {
    if (!root.pluginDir || configReader.running) return
    configReader.running = true
  }

  //: A FileView on the file would read it, which is the thing being avoided,
  //: and a FileView on the directory does not fire on an in-place write --
  //: checked, and "save it and the renderer picks it up" is documented
  //: behaviour. inotifywait is what omarchy's own plugin registry watches
  //: with, and it reports the change without reading the file.
  Process {
    id: configWatcher
    running: root.pluginDir !== ""
    command: ["sh", "-c",
      'mkdir -p "$1" 2>/dev/null; '
      + 'exec inotifywait -m -q -e close_write,create,move,delete --format %f "$1"',
      "sh", root.configDir]
    stdout: SplitParser {
      onRead: function (name) {
        if (String(name).trim() === "wallpapers.json") root.reloadConfig()
      }
    }
    onExited: configWatcherRestart.restart()
  }

  Timer {
    id: configWatcherRestart
    interval: 1000
    onTriggered: if (root.pluginDir) configWatcher.running = true
  }

  onPluginDirChanged: root.reloadConfig()
  Component.onCompleted: root.reloadConfig()

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
