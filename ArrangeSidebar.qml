// Per-display settings for whatever the canvas has selected.

import QtQuick
import QtQuick.Layouts

Item {
  id: sidebar

  property var controller: null
  property var pal: null
  readonly property var geo: controller ? controller.geo : null
  readonly property var snap: controller ? controller.snap : null
  readonly property var state: controller ? controller.selected : null
  readonly property bool ready: !!(state && geo)

  function edit(fn) {
    if (!state) return
    fn(state)
    controller.touch()
  }

  //: Distinct resolutions this panel advertises, newest first.
  readonly property var resolutions: {
    if (controller) controller.revision
    if (!ready) return []
    const seen = []
    for (const m of state.availableModes) {
      const r = sidebar.geo.modeResolution(m)
      if (!seen.includes(r)) seen.push(r)
    }
    return seen
  }

  //: Refresh rates available at the selected resolution.
  readonly property var refreshRates: {
    if (controller) controller.revision
    if (!ready || !state.mode) return []
    const rates = state.availableModes
      .filter(m => m.width === state.mode.width && m.height === state.mode.height && m.refresh)
      .map(m => m.refresh)
    const unique = [...new Set(rates)].sort((a, b) => b - a)
    if (state.mode.refresh && !unique.includes(state.mode.refresh)) unique.unshift(state.mode.refresh)
    return unique
  }

  Rectangle {
    anchors.fill: parent
    radius: 10
    color: pal.selectedBackground
    opacity: 0.18
  }

  Text {
    anchors.centerIn: parent
    visible: !sidebar.ready
    text: "Select a display"
    color: pal.muted
    font.pixelSize: 13
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: 14
    spacing: 10
    visible: sidebar.ready

    Text {
      Layout.fillWidth: true
      text: sidebar.ready ? sidebar.geo.prettyName(sidebar.state) : ""
      color: pal.text
      font.pixelSize: 15
      font.bold: true
      elide: Text.ElideRight
    }
    Text {
      Layout.fillWidth: true
      text: sidebar.ready ? sidebar.geo.panelSummary(sidebar.state) : ""
      color: pal.muted
      font.pixelSize: 12
      elide: Text.ElideRight
    }

    ArrangeRow {
            pal: sidebar.pal
      label: "Enabled"
      ArrangeButton {
            pal: sidebar.pal
        label: sidebar.state && sidebar.state.enabled ? "On" : "Off"
        primary: !!(sidebar.state && sidebar.state.enabled)
        onTriggered: sidebar.edit(s => {
          s.enabled = !s.enabled
          if (s.enabled && !s.mode && s.availableModes.length) s.mode = sidebar.geo.preferredMode(s)
        })
      }
    }

    ArrangeRow {
            pal: sidebar.pal
      label: "Resolution"
      ArrangeCycler {
            pal: sidebar.pal
        options: sidebar.resolutions
        current: sidebar.state && sidebar.state.mode
          ? sidebar.geo.modeResolution(sidebar.state.mode) : "preferred"
        onPicked: function (value) {
          sidebar.edit(s => {
            const [w, h] = value.split("x").map(Number)
            const keep = s.mode ? s.mode.refresh : 0
            const options = s.availableModes.filter(m => m.width === w && m.height === h)
            s.mode = options.length
              ? options.reduce((best, m) =>
                  Math.abs(m.refresh - keep) < Math.abs(best.refresh - keep) ? m : best)
              : { width: w, height: h, refresh: 0 }
          })
        }
      }
    }

    ArrangeRow {
            pal: sidebar.pal
      label: "Refresh"
      ArrangeCycler {
            pal: sidebar.pal
        options: sidebar.refreshRates.map(r => sidebar.geo.trimNumber(r) + " Hz")
        current: sidebar.state && sidebar.state.mode && sidebar.state.mode.refresh
          ? sidebar.geo.trimNumber(sidebar.state.mode.refresh) + " Hz" : "—"
        onPicked: function (value) {
          sidebar.edit(s => {
            const rate = parseFloat(value)
            s.mode = { width: s.mode.width, height: s.mode.height, refresh: rate }
          })
        }
      }
    }

    ArrangeRow {
            pal: sidebar.pal
      label: "Scale"
      RowLayout {
        spacing: 6
        ArrangeCycler {
            pal: sidebar.pal
          options: ["1", "1.25", "1.5", "1.75", "2", "2.5"]
          current: sidebar.ready ? sidebar.geo.trimNumber(sidebar.state.scale) : ""
          onPicked: function (value) { sidebar.edit(s => { s.scale = parseFloat(value) }) }
        }
        ArrangeButton {
            pal: sidebar.pal
          label: "Auto"
          onTriggered: sidebar.edit(s => { s.scale = sidebar.geo.suggestScale(s) })
        }
      }
    }

    ArrangeRow {
            pal: sidebar.pal
      label: "Rotation"
      ArrangeCycler {
            pal: sidebar.pal
        options: [0, 1, 2, 3].map(t => sidebar.geo.TRANSFORMS[t][0])
        current: sidebar.ready ? sidebar.geo.TRANSFORMS[sidebar.state.transform][0] : ""
        onPicked: function (value) {
          sidebar.edit(s => {
            for (const t of [0, 1, 2, 3, 4, 5, 6, 7]) {
              if (sidebar.geo.TRANSFORMS[t][0] === value) { s.transform = t; return }
            }
          })
        }
      }
    }

    ArrangeRow {
            pal: sidebar.pal
      label: "Position"
      Text {
        text: sidebar.state ? `${sidebar.state.x}, ${sidebar.state.y}` : ""
        color: pal.muted
        font.pixelSize: 13
      }
    }

    Item { Layout.fillHeight: true }

    Text {
      Layout.fillWidth: true
      wrapMode: Text.WordWrap
      visible: text.length > 0
      color: pal.textError
      font.pixelSize: 12
      text: sidebar.state ? (sidebar.geo.scaleWarning(sidebar.state) || "") : ""
    }

    Text {
      Layout.fillWidth: true
      wrapMode: Text.WordWrap
      color: pal.placeholder
      font.pixelSize: 11
      text: sidebar.state ? "rule: " + sidebar.geo.summary(sidebar.state) : ""
    }
  }
}
