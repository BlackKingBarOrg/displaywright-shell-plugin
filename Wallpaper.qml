// Displaywright's renderer: one wallpaper surface per output.
//
// This plugin *replaces* omarchy.background rather than sitting beside it.
// Two plugins drawing full-screen surfaces on WlrLayer.Background have no
// defined stacking order between them, so only one of them can own the layer.
// Owning it means inheriting two jobs from the plugin we displace:
//
//   1. the `background` IPC target, so `omarchy-theme-bg-set`, the SUPER +
//      CTRL + SPACE switcher and `omarchy-theme-set` keep working; and
//   2. applying the theme palette that rides along with `themeTransition`.
//      That call is how the whole shell recolours on a theme switch, and it
//      lands nowhere else. Dropping it would leave the bar on the old palette.
//
// Outputs displaywright has no opinion about keep following the theme
// background, so a fresh install looks and behaves exactly like stock Omarchy.

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

Item {
  id: root

  // Injected by the shell host when it instantiates a service plugin.
  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")
  readonly property string configPath: configHome + "/displaywright/wallpapers.json"
  readonly property string themeLink: home + "/.local/state/omarchy/current/background"

  // ---------------------------------------------------------------- config

  // { outputName: source }. Absent output means "follow the theme".
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
        // empty values and every output reverts to the theme background.
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

  // ------------------------------------------------------ theme background

  function refreshTheme() {
    if (!themeLinkProc.running) themeLinkProc.running = true
  }

  Process {
    id: themeLinkProc
    command: ["readlink", "-f", root.themeLink]
    stdout: StdioCollector {
      onStreamFinished: {
        var path = String(text || "").trim()
        if (path.length > 0) root.themeBackground = path
      }
    }
  }

  property string themeBackground: ""

  // Theme payload that arrived with a themeTransition and is waiting for the
  // reveal to start, so the palette flips together with the picture instead of
  // a frame or two ahead of it.
  property string pendingColors: ""
  property string pendingShell: ""
  property bool themePending: false

  function applyPendingTheme() {
    if (!themePending) return
    themePending = false
    themeFallbackTimer.stop()
    Color.loadColors(pendingColors)
    // loadShell also refreshes Style, so the type scale changes with the
    // palette rather than one repaint later.
    Color.loadShell(pendingShell)
    Style.scheduleRefresh()
    pendingColors = ""
    pendingShell = ""
  }

  // Every output may be pinned, in which case no surface will ever start a
  // reveal and nothing would apply the palette. Apply it anyway, shortly.
  Timer {
    id: themeFallbackTimer
    interval: 300
    onTriggered: root.applyPendingTheme()
  }

  // ------------------------------------------------------------------- IPC

  // Displaywright's own surface. The config file is the source of truth; this
  // only spares the caller the filesystem-watch latency.
  IpcHandler {
    target: "displaywright"

    function reload(): string {
      configFile.reload()
      root.refreshTheme()
      root.refreshSpanBox()
      return "ok"
    }

    function status(): string {
      var out = []
      var screens = Quickshell.screens || []
      for (var i = 0; i < screens.length; i++) {
        var name = screens[i].name
        var src = root.sourceFor(name)
        var where = root.spanSource ? "span" : (src ? "pinned" : "theme")
        var what = src ? (src.kind === "color" ? src.color : src.path) : root.themeBackground
        out.push(name + "\t" + where + "\t" + (src && src.fit ? src.fit : "fill") + "\t" + what)
      }
      return out.join("\n")
    }

    function ping(): string {
      return "ok"
    }
  }

  // Drop-in for the target omarchy.background used to own. Everything here
  // affects the theme background only, which is what the unpinned outputs draw.
  IpcHandler {
    target: "background"

    function refresh(): void {
      root.refreshTheme()
    }

    function set(path: string): void {
      var next = String(path || "").trim()
      if (next.length > 0) root.themeBackground = next
    }

    function setInstant(path: string): void {
      set(path)
    }

    function transition(fromPath: string, path: string): void {
      set(path)
    }

    function themeTransition(fromPath: string, path: string, finalPath: string,
                             colorsB64: string, shellB64: string): void {
      root.pendingColors = Util.decodeBase64(colorsB64)
      root.pendingShell = Util.decodeBase64(shellB64)
      root.themePending = true
      themeFallbackTimer.restart()
      // `path` is a short-lived snapshot omarchy-theme-set deletes a few
      // seconds later; `finalPath` is the file that stays. Showing the durable
      // one avoids a surface pointing at a deleted inode after the transition.
      var next = String(finalPath || path || "").trim()
      if (next.length > 0) root.themeBackground = next
      else root.applyPendingTheme()
    }
  }

  // --------------------------------------------------------------- surfaces

  Component.onCompleted: {
    refreshTheme()
    refreshSpanBox()
  }

  Variants {
    model: Quickshell.screens

    Surface {
      controller: root
    }
  }
}
