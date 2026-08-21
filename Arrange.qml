// The display arrangement, as an Omarchy overlay.
//
// Everything this draws is decided by lib/geometry.mjs and lib/snapping.mjs,
// the same modules `node --test` exercises, so the awkward parts -- rotation,
// fractional scales, snapping, what counts as a valid layout -- are tested
// without a compositor in the room.
//
// The root has to be an Item: the shell mounts plugins through a Loader, which
// cannot hold a Window. The PanelWindow lives inside it.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null
  //: The wallpaper service, injected by the shell. It owns the imports.
  property var service: null

  readonly property var geo: service ? service.geo : null
  readonly property var snap: service ? service.snap : null
  readonly property var lua: service ? service.lua : null
  readonly property bool ready: !!geo

  readonly property ArrangePalette pal: ArrangePalette {
    theme: root.service ? root.service.palette : null
  }

  property bool opened: false
  //: Desired layout, mutated by dragging and by the sidebar.
  property var states: []
  //: What Hyprland last reported, for the dirty check and for reverting.
  property var liveStates: []
  property string selectedName: ""
  //: Bumped whenever `states` is mutated in place, to re-run bindings.
  property int revision: 0
  property string busy: ""
  property string notice: ""
  property int countdown: 0

  readonly property string home: Quickshell.env("HOME")
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")
  readonly property string monitorsPath: configHome + "/hypr/monitors.lua"

  readonly property var selected: {
    revision
    if (!ready) return null
    for (const s of states) if (s.name === selectedName) return s
    return null
  }

  readonly property bool dirty: {
    revision
    if (!ready) return false
    if (states.length !== liveStates.length) return true
    for (const s of states) {
      const live = liveStates.find(l => l.name === s.name)
      if (!live || !geo.configEquals(s, live)) return true
    }
    return false
  }

  readonly property var problems: { revision; return ready ? snap.validate(states) : [] }

  function touch() { revision += 1 }

  // ------------------------------------------------------------- shell entry

  function open(payload) {
    if (!root.ready) return
    reload()
    root.opened = true
  }

  function hide() {
    root.opened = false
    root.notice = ""
  }

  // ------------------------------------------------------------------- hypr

  function reload() {
    readProc.running = true
  }

  Process {
    id: readProc
    command: ["hyprctl", "-j", "monitors", "all"]
    stdout: StdioCollector {
      onStreamFinished: {
        let parsed = []
        try {
          parsed = JSON.parse(text)
        } catch (e) {
          root.notice = "Could not read monitors: " + e
          return
        }
        const next = parsed.map(geo.stateFromHyprctl)
        next.sort((a, b) => (Number(!a.enabled) - Number(!b.enabled))
          || (a.x - b.x) || (a.y - b.y) || a.name.localeCompare(b.name))
        root.states = next
        root.liveStates = next.map(geo.copyState)
        if (!next.some(s => s.name === root.selectedName)) {
          const focused = next.find(s => s.focused)
          root.selectedName = focused ? focused.name : (next.length ? next[0].name : "")
        }
        root.touch()
      }
    }
  }

  // Hyprland 0.56 with a Lua config refuses `keyword` and wants `eval`; older
  // hyprlang builds have no `eval`. hyprctl exits 0 either way, so the reply
  // text is the only signal -- the fallback is chained in the shell.
  Process {
    id: applyProc
    property var snapshot: []
    command: ["bash", "-c", ""]
    onExited: function (code) {
      root.busy = ""
      root.startCountdown()
    }
  }

  function applyStates(list, onDone) {
    const lua = list.map(lua.renderCall).join("; ")
    const legacy = list.map(s => "keyword monitor " + lua.ruleArgs(s)).join(" ; ")
    applyProc.command = ["bash", "-c",
      'out=$(hyprctl eval "$1" 2>&1); '
      + 'case "${out,,}" in *error*|*"can\'t work"*|*"unknown request"*) '
      + 'hyprctl --batch "$2" >/dev/null 2>&1 ;; esac',
      "displaywright", lua, legacy]
    root.busy = "Applying — waiting for Hyprland…"
    applyProc.running = true
  }

  function apply() {
    if (root.busy) return
    applyProc.snapshot = root.liveStates.map(geo.copyState)
    applyStates(root.states)
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
      if (root.countdown <= 0) { countdownTimer.stop(); root.revert() }
    }
  }

  function keep() {
    countdownTimer.stop()
    root.countdown = 0
    root.liveStates = root.states.map(geo.copyState)
    root.touch()
    root.save()
  }

  function revert() {
    countdownTimer.stop()
    root.countdown = 0
    const snapshot = applyProc.snapshot
    if (snapshot && snapshot.length) {
      root.states = snapshot.map(geo.copyState)
      root.touch()
      applyStates(snapshot)
      countdownTimer.stop()
      root.countdown = 0
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
    // Everything outside displaywright's own block survives, and a laptop
    // panel switched off is written through Omarchy's toggle rather than as a
    // rule nothing would ever remove.
    let existing = ""
    try { existing = monitorsFile.text() } catch (e) { existing = "" }
    const next = lua.renderFile(existing, root.states, true)
    monitorsFile.setText(next)
    root.notice = "Saved to " + root.monitorsPath
  }

  // ----------------------------------------------------------------- surface

  PanelWindow {
    id: window
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "displaywright-arrange"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Rectangle {
      anchors.fill: parent
      color: pal.scrim
      MouseArea { anchors.fill: parent; onClicked: root.hide() }
    }

    Rectangle {
      id: panel
      anchors.centerIn: parent
      width: Math.min(parent.width - 80, 1180)
      height: Math.min(parent.height - 80, 760)
      radius: 14
      color: pal.background
      border.color: pal.border
      border.width: 1
      // Swallow clicks so they do not reach the scrim behind.
      MouseArea { anchors.fill: parent }

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 12

        RowLayout {
          Layout.fillWidth: true
          Text {
            text: "Displays"
            color: pal.text
            font.pixelSize: 20
            font.bold: true
          }
          Item { Layout.fillWidth: true }
          Text {
            text: root.busy || root.notice || (root.problems.length ? root.problems[0] : "")
            color: root.problems.length ? pal.textError : pal.muted
            font.pixelSize: 13
            elide: Text.ElideRight
            Layout.maximumWidth: 520
          }
        }

        RowLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: 14

          ArrangeCanvas {
            pal: root.pal
            id: canvas
            Layout.fillWidth: true
            Layout.fillHeight: true
            controller: root
            pal: root.pal
          }

          ArrangeSidebar {
            pal: root.pal
            Layout.preferredWidth: 320
            Layout.fillHeight: true
            controller: root
            pal: root.pal
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: 10

          Text {
            text: {
              root.revision
              const on = root.states.filter(s => s.enabled)
              if (!on.length) return "nothing enabled"
              const box = geo.boundingBox(on.map(geo.rectOf))
              return `${on.length} display${on.length === 1 ? "" : "s"} · `
                + `${Math.round(box.w)}×${Math.round(box.h)}`
                + (root.dirty ? " · unapplied changes" : "")
            }
            color: pal.muted
            font.pixelSize: 13
          }
          Item { Layout.fillWidth: true }

          ArrangeButton {
            pal: root.pal
            label: "Auto arrange"
            onTriggered: { snap.autoArrange(root.states); root.touch() }
          }
          ArrangeButton {
            pal: root.pal
            label: "Close"
            onTriggered: root.hide()
          }
          ArrangeButton {
            pal: root.pal
            label: "Apply"
            primary: true
            enabled: root.dirty && root.busy === ""
            onTriggered: root.apply()
          }
        }
      }

      // Keep-or-revert, defaulting to revert: a display that went black cannot
      // lock anybody out while this is on screen.
      Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: pal.scrim
        visible: root.countdown > 0

        Rectangle {
          anchors.centerIn: parent
          width: 460
          height: 150
          radius: 12
          color: pal.background
          border.color: pal.countdown
          border.width: 2

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12
            Text {
              text: "Keep this arrangement?"
              color: pal.text
              font.pixelSize: 17
              font.bold: true
            }
            Text {
              Layout.fillWidth: true
              wrapMode: Text.WordWrap
              color: pal.muted
              font.pixelSize: 13
              text: `Reverting in ${root.countdown}s if you do not confirm, and saving to `
                + "monitors.lua if you do."
            }
            RowLayout {
              Layout.fillWidth: true
              Item { Layout.fillWidth: true }
              ArrangeButton { label: "Revert"; onTriggered: root.revert() }
              ArrangeButton { label: "Keep"; primary: true; onTriggered: root.keep() }
            }
          }
        }
      }

      focus: root.opened
      Keys.onEscapePressed: root.countdown > 0 ? root.revert() : root.hide()
    }
  }
}
