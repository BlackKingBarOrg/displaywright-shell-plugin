// The whole arrangement interface, in plain QtQuick.
//
// Nothing here imports Quickshell, which is the point: qmltestrunner can build
// it offscreen against a fake controller and check the behaviour without a
// compositor, a shell, or the restart that testing inside the shell costs.
//
// The controller supplies: states, revision, selectedName, geo, snap, pal,
// dirty, problems, busy, notice, countdown, and the actions touch(), apply(),
// keep(), revert(), hide(), autoArrange().

import QtQuick
import QtQuick.Layouts

Item {
  id: view

  property var controller: null
  property var pal: null

  readonly property var geo: controller ? controller.geo : null
  readonly property var states: controller ? controller.states : []
  readonly property bool ready: !!geo

  Rectangle {
    anchors.fill: parent
    color: view.pal ? view.pal.scrim : "#cc0c0c11"
    MouseArea { anchors.fill: parent; onClicked: if (view.controller) view.controller.hide() }
  }

  Rectangle {
    id: panel
    anchors.centerIn: parent
    width: Math.min(parent.width - 80, 1180)
    height: Math.min(parent.height - 80, 760)
    radius: 14
    color: view.pal ? view.pal.background : "#16161d"
    border.color: view.pal ? view.pal.border : "#33333f"
    border.width: 1
    // Swallow clicks so they do not dismiss through the scrim behind.
    MouseArea { anchors.fill: parent }

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: 18
      spacing: 12

      RowLayout {
        Layout.fillWidth: true
        Text {
          text: "Displays"
          color: view.pal ? view.pal.text : "#e6e6ea"
          font.pixelSize: 20
          font.bold: true
        }
        Item { Layout.fillWidth: true }
        Text {
          Layout.maximumWidth: 520
          elide: Text.ElideRight
          font.pixelSize: 13
          text: {
            if (!view.controller) return ""
            if (view.controller.busy) return view.controller.busy
            if (view.controller.problems.length) return view.controller.problems[0]
            return view.controller.notice
          }
          color: view.controller && view.controller.problems.length
            ? (view.pal ? view.pal.textError : "#f08a8a")
            : (view.pal ? view.pal.muted : "#9a9aa6")
        }
      }

      RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 14

        ArrangeCanvas {
          id: canvas
          Layout.fillWidth: true
          Layout.fillHeight: true
          controller: view.controller
          pal: view.pal
        }

        ArrangeSidebar {
          Layout.preferredWidth: 320
          Layout.fillHeight: true
          controller: view.controller
          pal: view.pal
          popupLayer: popupLayer
        }
      }

      ArrangeWallpapers {
        Layout.fillWidth: true
        controller: view.controller
        pal: view.pal
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 10

        Text {
          objectName: "summary"
          font.pixelSize: 13
          color: view.pal ? view.pal.muted : "#9a9aa6"
          text: {
            if (!view.ready || !view.controller) return ""
            view.controller.revision
            var on = view.states.filter(function (s) { return s.enabled })
            if (!on.length) return "nothing enabled"
            var box = view.geo.boundingBox(on.map(view.geo.rectOf))
            return on.length + " display" + (on.length === 1 ? "" : "s")
              + " · " + Math.round(box.w) + "×" + Math.round(box.h)
              + (view.controller.dirty ? " · unapplied changes" : "")
          }
        }
        Item { Layout.fillWidth: true }

        ArrangeButton {
          objectName: "autoArrange"
          pal: view.pal
          label: "Auto arrange"
          onTriggered: if (view.controller) view.controller.autoArrange()
        }
        ArrangeButton {
          pal: view.pal
          label: "Close"
          onTriggered: if (view.controller) view.controller.hide()
        }
        ArrangeButton {
          objectName: "apply"
          pal: view.pal
          label: "Apply"
          primary: true
          enabled: !!view.controller && view.controller.dirty && view.controller.busy === ""
          onTriggered: if (view.controller) view.controller.apply()
        }
      }
    }

    // Keep-or-revert, defaulting to revert: a display that went black cannot
    // lock anybody out while this is on screen.
    Rectangle {
      objectName: "countdownDialog"
      anchors.fill: parent
      radius: parent.radius
      color: view.pal ? view.pal.scrim : "#cc0c0c11"
      visible: !!view.controller && view.controller.countdown > 0

      MouseArea { anchors.fill: parent }

      Rectangle {
        anchors.centerIn: parent
        width: 460
        height: 156
        radius: 12
        color: view.pal ? view.pal.background : "#16161d"
        border.color: view.pal ? view.pal.countdown : "#e8b04b"
        border.width: 2

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: 18
          spacing: 10
          Text {
            text: "Keep this arrangement?"
            color: view.pal ? view.pal.text : "#e6e6ea"
            font.pixelSize: 17
            font.bold: true
          }
          Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: view.pal ? view.pal.muted : "#9a9aa6"
            font.pixelSize: 13
            text: view.controller
              ? "Reverting in " + view.controller.countdown + "s if you do not confirm, "
                + "and saving to monitors.lua if you do."
              : ""
          }
          RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            ArrangeButton {
              objectName: "revert"
              pal: view.pal
              label: "Revert"
              onTriggered: if (view.controller) view.controller.revert()
            }
            ArrangeButton {
              objectName: "keep"
              pal: view.pal
              label: "Keep"
              primary: true
              onTriggered: if (view.controller) view.controller.keep()
            }
          }
        }
      }
    }

    // Anything that has to escape the layouts is drawn here. `z` only orders
    // siblings, so a list inside a sidebar row is covered by the rows beneath
    // it however high its z -- it has to be reparented out to be on top.
    Item {
      id: popupLayer
      objectName: "popupLayer"
      anchors.fill: parent
      z: 1000
    }

    focus: true
    Keys.onEscapePressed: {
      if (!view.controller) return
      if (view.controller.countdown > 0) view.controller.revert()
      else view.controller.hide()
    }
  }
}
