// The display arrangement overlay: everything that has to touch Quickshell.
//
// Deliberately thin. A plugin overlay is mounted through the shell's Loader,
// and a component loaded that way resolves no imports of its own -- not
// scripts, not qs.Commons -- so the logic modules and the theme arrive through
// the `service` property the shell injects. Worse, the shell serves a cached
// component for any file changed while it runs, so testing a change here costs
// a full shell restart.
//
// Both problems are contained by keeping this file small and putting the whole
// interface in ArrangeView.qml, which is plain QtQuick and can be driven by
// qmltestrunner against a fake controller, offscreen, with no shell involved.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null
  //: The wallpaper service. It owns the imports this file cannot make.
  property var service: null

  readonly property var geo: service ? service.geo : null
  readonly property var snap: service ? service.snap : null
  readonly property var lua: service ? service.lua : null
  readonly property bool ready: !!geo

  readonly property ArrangePalette pal: ArrangePalette {
    theme: root.service ? root.service.palette : null
  }

  property bool opened: false
  property var states: []
  property var liveStates: []
  property string selectedName: ""
  property int revision: 0
  property string busy: ""
  property string notice: ""
  property int countdown: 0

  readonly property string home: Quickshell.env("HOME")
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")
  readonly property string monitorsPath: configHome + "/hypr/monitors.lua"

  function touch() { revision += 1 }

  readonly property var selected: {
    revision
    if (!ready) return null
    for (var i = 0; i < states.length; i++) if (states[i].name === selectedName) return states[i]
    return null
  }

  readonly property bool dirty: {
    revision
    if (!ready || states.length !== liveStates.length) return states.length !== liveStates.length
    for (var i = 0; i < states.length; i++) {
      var live = null
      for (var j = 0; j < liveStates.length; j++) {
        if (liveStates[j].name === states[i].name) { live = liveStates[j]; break }
      }
      if (!live || !geo.configEquals(states[i], live)) return true
    }
    return false
  }

  readonly property var problems: { revision; return ready ? snap.validate(states) : [] }

  // ------------------------------------------------------------ shell entry

  function open(payload) {
    if (!ready) { console.warn("displaywright: the arrangement needs the renderer service"); return }
    reload()
    root.opened = true
  }

  function hide() {
    root.opened = false
    root.notice = ""
  }

  // ------------------------------------------------------------------- hypr

  function reload() { readProc.running = true }

  Process {
    id: readProc
    command: ["hyprctl", "-j", "monitors", "all"]
    stdout: StdioCollector {
      onStreamFinished: {
        var parsed = []
        try { parsed = JSON.parse(text) } catch (e) {
          root.notice = "Could not read monitors: " + e
          return
        }
        var next = parsed.map(root.geo.stateFromHyprctl)
        next.sort(function (a, b) {
          return (Number(!a.enabled) - Number(!b.enabled)) || (a.x - b.x) || (a.y - b.y)
            || a.name.localeCompare(b.name)
        })
        root.states = next
        root.liveStates = next.map(root.geo.copyState)
        var known = false
        for (var i = 0; i < next.length; i++) if (next[i].name === root.selectedName) known = true
        if (!known) {
          var focused = next.filter(function (s) { return s.focused })
          root.selectedName = focused.length ? focused[0].name : (next.length ? next[0].name : "")
        }
        root.touch()
      }
    }
  }

  // Hyprland 0.56 with a Lua config refuses `keyword` and wants `eval`; older
  // hyprlang builds have no `eval`. hyprctl exits 0 either way, so the reply
  // text is the only signal -- the fallback is chained in the shell.
  property var snapshot: []

  Process {
    id: applyProc
    command: ["true"]
    onExited: {
      root.busy = ""
      if (root.countdown === 0 && root.opened) root.startCountdown()
    }
  }

  function applyStates(list) {
    var luaText = list.map(root.lua.renderCall).join("; ")
    var legacy = list.map(function (s) { return "keyword monitor " + root.lua.ruleArgs(s) }).join(" ; ")
    applyProc.command = ["bash", "-c",
      'out=$(hyprctl eval "$1" 2>&1); '
      + 'case "${out,,}" in *error*|*"can'"'"'t work"*|*"unknown request"*) '
      + 'hyprctl --batch "$2" >/dev/null 2>&1 ;; esac',
      "displaywright", luaText, legacy]
    root.busy = "Applying — waiting for Hyprland…"
    applyProc.running = true
  }

  function apply() {
    if (root.busy !== "" || !ready) return
    root.snapshot = root.liveStates.map(root.geo.copyState)
    applyStates(root.states)
  }

  function autoArrange() {
    if (!ready) return
    root.snap.autoArrange(root.states)
    root.touch()
  }

  // ------------------------------------------------------- keep or revert

  function startCountdown() {
    root.countdown = 15
    countdownTimer.restart()
  }

  Timer {
    id: countdownTimer
    interval: 1000
    repeat: true
    onTriggered: {
      root.countdown -= 1
      if (root.countdown <= 0) root.revert()
    }
  }

  function keep() {
    countdownTimer.stop()
    root.countdown = 0
    root.liveStates = root.states.map(root.geo.copyState)
    root.touch()
    root.save()
  }

  function revert() {
    countdownTimer.stop()
    root.countdown = 0
    if (root.snapshot && root.snapshot.length) {
      root.states = root.snapshot.map(root.geo.copyState)
      root.touch()
      applyStates(root.snapshot)
    }
    root.notice = "Reverted to the previous arrangement"
  }

  // -------------------------------------------------------------- persisting

  FileView {
    id: monitorsFile
    path: root.monitorsPath
    printErrors: false
    blockLoading: true
  }

  function save() {
    if (!ready) return
    var existing = ""
    try { existing = monitorsFile.text() } catch (e) { existing = "" }
    // Everything outside displaywright's own block survives, and a laptop panel
    // switched off is written through Omarchy's toggle rather than as a rule
    // nothing would ever remove.
    monitorsFile.setText(root.lua.renderFile(existing, root.states, true))
    root.notice = "Saved to " + root.monitorsPath
  }

  // ----------------------------------------------------------------- surface

  PanelWindow {
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "displaywright-arrange"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    ArrangeView {
      anchors.fill: parent
      controller: root
      pal: root.pal
    }
  }
}
