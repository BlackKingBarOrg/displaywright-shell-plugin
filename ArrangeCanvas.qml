// The desk drawn small: one draggable rectangle per output.
//
// Dragging rewrites the state's logical position through snapAndResolve, so a
// drop lands flush against its neighbours with no overlap -- the same function
// `node --test` checks, rather than a second implementation for the UI.

import QtQuick

Item {
  id: view

  property var controller: null
  property var pal: null
  function c(role, fallback) { return pal && pal[role] !== undefined ? pal[role] : fallback }
  readonly property var geo: controller ? controller.geo : null
  readonly property var snap: controller ? controller.snap : null

  readonly property var states: controller ? controller.states : []
  readonly property real padding: 26
  //: Never draw a monitor larger than a third of life size, or a single
  //: display fills the view and it stops reading as a scaled-down desk.
  readonly property real maxZoom: 0.34

  readonly property var box: {
    if (controller) controller.revision
    // Bindings run once before the shell injects the service, so `geo` is null
    // for that first pass. Answer with a plausible desk rather than throwing.
    if (!geo) return { x: 0, y: 0, w: 1920, h: 1080 }
    const rects = states.map(geo.rectOf)
    return rects.length ? geo.boundingBox(rects) : { x: 0, y: 0, w: 1920, h: 1080 }
  }

  readonly property real zoom: {
    const usableW = Math.max(width - 2 * padding, 40)
    const usableH = Math.max(height - 2 * padding, 40)
    return Math.min(usableW / Math.max(box.w, 1), usableH / Math.max(box.h, 1), maxZoom)
  }
  readonly property real originX: (width - box.w * zoom) / 2 - box.x * zoom
  readonly property real originY: (height - box.h * zoom) / 2 - box.y * zoom

  function toDeviceX(x) { return originX + x * zoom }
  function toDeviceY(y) { return originY + y * zoom }

  Rectangle {
    anchors.fill: parent
    radius: 10
    color: c("selectedBackground", "#25324a")
    opacity: 0.25
    border.color: c("border", "#33333f")
    border.width: 1
  }

  Text {
    anchors.centerIn: parent
    visible: view.states.length === 0
    text: "No outputs reported by Hyprland"
    color: c("muted", "#9a9aa6")
    font.pixelSize: 14
  }

  Repeater {
    model: view.states.length

    delegate: Rectangle {
      id: tile

      required property int index
      objectName: "tile-" + state.name
      readonly property var state: view.states[index]
      readonly property var rect: {
        if (view.controller) view.controller.revision
        return view.geo ? view.geo.rectOf(state) : { x: 0, y: 0, w: 0, h: 0 }
      }
      readonly property bool isSelected: view.controller
        && view.controller.selectedName === state.name

      x: view.toDeviceX(rect.x)
      y: view.toDeviceY(rect.y)
      width: rect.w * view.zoom
      height: rect.h * view.zoom

      radius: Math.min(9, width / 6, height / 6)
      color: !state.enabled ? c("background", "#16161d")
        : (isSelected ? c("selectedBackground", "#25324a") : c("active", "#242430"))
      border.color: isSelected ? c("selectedBorder", "#6aa3f0") : c("unselectedBorder", "#41414f")
      border.width: isSelected ? 3 : 1
      opacity: state.enabled ? 1 : 0.55

      Column {
        anchors.centerIn: parent
        spacing: 2
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: tile.state.name
          color: c("text", "#e6e6ea")
          font.pixelSize: 14
          font.bold: true
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          visible: tile.height > 46 && tile.width > 96
          text: {
            if (view.controller) view.controller.revision
            if (!tile.state.enabled) return "disabled"
            if (!view.geo) return ""
            const px = view.geo.pixelSizeRotated(tile.state)
            return px[0] + "×" + px[1]
          }
          color: c("muted", "#9a9aa6")
          font.pixelSize: 11
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          visible: tile.height > 66 && tile.width > 110 && tile.state.enabled
            && Math.abs(tile.state.scale - 1) > 1e-6
          text: {
            if (view.controller) view.controller.revision
            if (!view.geo) return ""
            const l = view.geo.logicalSize(tile.state)
            return "×" + view.geo.trimNumber(tile.state.scale)
              + " → " + Math.round(l[0]) + "×" + Math.round(l[1])
          }
          color: c("muted", "#9a9aa6")
          font.pixelSize: 11
        }
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.OpenHandCursor
        property real grabX: 0
        property real grabY: 0
        property bool dragging: false

        onPressed: function (mouse) {
          view.controller.selectedName = tile.state.name
          grabX = mouse.x
          grabY = mouse.y
          dragging = true
        }
        onReleased: dragging = false

        onPositionChanged: function (mouse) {
          if (!dragging) return
          const dx = (mouse.x - grabX) / view.zoom
          const dy = (mouse.y - grabY) / view.zoom
          if (!view.geo || !view.snap) return
          const others = view.states.filter(s => s.name !== tile.state.name).map(view.geo.rectOf)
          const wanted = { x: tile.state.x + dx, y: tile.state.y + dy,
                           w: tile.rect.w, h: tile.rect.h }
          const result = view.snap.snapAndResolve(wanted, others)
          tile.state.x = result.x
          tile.state.y = result.y
          view.controller.touch()
        }
      }
    }
  }
}
